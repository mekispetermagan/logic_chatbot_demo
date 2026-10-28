import json
from uuid import UUID, uuid4
from collections.abc import Callable

from .database import Database
from .engine import EngineReply
from .schemas import (ChatMessage, ConversationState, EditState, World, WorldState, CellularWorld,
                      PendingEntry, DomainId, LlmUsage, world_from_json,
                      InterpretationProposal, InterpretationPreview, WorldSlot)
from .llm_budget import budget_in, hydrate_usage


class PendingConflict(Exception):
    pass


class SnapshotConflict(Exception):
    pass


class WorldSlotEmpty(Exception):
    pass


ConversationRevision = tuple[int, str, str, str, int, str, int]


def record_outcome(connection, conversation_id, **payload):
    # Appended within the same transaction as the actual backend decision.
    # Sent on the next agent turn, not a separate paid call at decision time.
    connection.execute('INSERT INTO llm_session_events (conversation_id, payload_json) VALUES (?, ?)',
                       (str(conversation_id), json.dumps(payload)))


class ConversationRepository:
    def __init__(self, database: Database):
        self.database = database

    def _messages(self, connection, conversation_id: UUID) -> list[ChatMessage]:
        rows = connection.execute(
            "SELECT role, text, is_error, llm_json FROM chat_messages WHERE conversation_id = ? ORDER BY sequence",
            (str(conversation_id),),
        ).fetchall()
        return [ChatMessage(role=row["role"], text=row["text"], isError=bool(row["is_error"]),
                            llm=LlmUsage.model_validate_json(row['llm_json']) if row['llm_json'] else None) for row in rows]

    def _latest(self, connection, conversation_id):
        return connection.execute("""
            SELECT world_snapshots.*, conversations.domain, conversations.language_version,
                   conversations.next_object_id, conversations.reset_pending FROM world_snapshots
            JOIN conversations ON conversations.id = world_snapshots.conversation_id
            WHERE conversation_id = ? ORDER BY sequence DESC LIMIT 1
        """, (str(conversation_id),)).fetchone()

    def _pending(self, row):
        value = json.loads(row["pending_json"])
        return PendingEntry.model_validate(value) if value is not None else None

    def _require_not_resetting(self, row):
        if row['reset_pending']:
            raise PendingConflict('Reply yes or no in Chat to confirm or cancel the reset')

    def _replacement(self, connection, conversation_id, feedback=None):
        receipt = connection.execute('SELECT new_id FROM conversation_resets WHERE old_id=?',
                                     (str(conversation_id),)).fetchone()
        if receipt is None:
            return None
        replacement_id = UUID(receipt['new_id'])
        row = self._latest(connection, replacement_id)
        if row is None:
            return None
        state = self._state(connection, row, replacement_id,
                            self._messages(connection, replacement_id), feedback)
        state.resetFrom = conversation_id
        return state

    def _active_proposal(self, connection, conversation_id):
        return connection.execute(
            "SELECT * FROM interpretation_proposals WHERE conversation_id = ? AND status = 'pending'",
            (str(conversation_id),),
        ).fetchone()

    def _append_messages(self, connection, conversation_id, feedback, is_error=False, llm=None, user_text=None):
        sequence = connection.execute(
            'SELECT COALESCE(MAX(sequence), -1) + 1 FROM chat_messages WHERE conversation_id = ?',
            (str(conversation_id),),
        ).fetchone()[0]
        rows = []
        if user_text is not None:
            rows.append((str(conversation_id), sequence, 'user', user_text, 0, None))
            sequence += 1
        rows.append((str(conversation_id), sequence, 'machine', feedback, int(is_error),
                     llm.model_dump_json() if llm else None))
        connection.executemany(
            'INSERT INTO chat_messages (conversation_id, sequence, role, text, is_error, llm_json) VALUES (?, ?, ?, ?, ?, ?)', rows)

    def _state(self, connection, row, conversation_id, messages, feedback=None):
        proposal = self._active_proposal(connection, conversation_id)
        saved_slots = {slot['slot']: slot['saved_at'] for slot in connection.execute(
            'SELECT slot, saved_at FROM world_slots WHERE conversation_id=?',
            (str(conversation_id),)).fetchall()}
        values = dict(conversationId=conversation_id, domain=row["domain"],
                      world=world_from_json(row['domain'], row["world_json"]),
                      canUndo=row["sequence"] > 0, messages=messages, pending=self._pending(row),
                      llmBudget=budget_in(connection),
                      languageVersion=row['language_version'], nextObjectId=row['next_object_id'],
                      resetPending=bool(row['reset_pending']),
                      proposal=InterpretationProposal.model_validate_json(proposal['proposal_json']) if proposal else None,
                      worldSlots=[WorldSlot(slot=slot, savedAt=saved_slots.get(slot)) for slot in range(1, 6)])
        values['messages'] = [ChatMessage.model_validate(hydrate_usage(connection, m.model_dump(mode='json'))) for m in messages]
        if values['proposal']:
            values['proposal'] = InterpretationProposal.model_validate(hydrate_usage(connection, values['proposal'].model_dump(mode='json')))
        return ConversationState(**values) if feedback is None else EditState(**values, feedback=feedback)

    def create(self, conversation_id: UUID, world: WorldState, domain: DomainId) -> ConversationState:
        next_id = max((o.id for o in world.objects), default=-1) + 1 if isinstance(world, World) else 0
        with self.database.connection() as connection:
            connection.execute("INSERT INTO conversations (id, domain, language_version, next_object_id) VALUES (?, ?, ?, ?)",
                               (str(conversation_id), domain, domain + '-v2', next_id))
            connection.execute(
                "INSERT INTO world_snapshots (conversation_id, sequence, world_json) VALUES (?, 0, ?)",
                (str(conversation_id), world.model_dump_json()),
            )
        return self.get(conversation_id)

    def get(self, conversation_id: UUID) -> ConversationState | None:
        snapshot = self.get_with_revision(conversation_id)
        return snapshot[0] if snapshot is not None else None

    def _revision(self, connection, row, conversation_id) -> ConversationRevision:
        last_message = connection.execute(
            'SELECT COALESCE(MAX(sequence), -1) FROM chat_messages WHERE conversation_id = ?',
            (str(conversation_id),),
        ).fetchone()[0]
        return (row['sequence'], row['world_json'], row['salience_json'], row['pending_json'], last_message,
                row['language_version'], row['next_object_id'])

    def get_with_revision(self, conversation_id: UUID) -> tuple[ConversationState, ConversationRevision] | None:
        with self.database.connection() as connection:
            # Capture the world, discourse state and message revision consistently;
            # this short read transaction ends before any model request starts.
            connection.execute('BEGIN')
            row = self._latest(connection, conversation_id)
            if row is None:
                replacement = self._replacement(connection, conversation_id)
                if replacement is None:
                    return None
                current = self._latest(connection, replacement.conversationId)
                return replacement, self._revision(connection, current, replacement.conversationId)
            state = self._state(connection, row, conversation_id, self._messages(connection, conversation_id))
            return state, self._revision(connection, row, conversation_id)

    def reset_control(self, conversation_id: UUID, text: str,
                      cellular_initial: CellularWorld | None = None) -> EditState | None:
        """Chat-only lifecycle command; neither Haskell nor the interpreter sees it."""
        command = ' '.join(text.strip().casefold().split())
        with self.database.connection() as connection:
            connection.execute('BEGIN IMMEDIATE')
            row = self._latest(connection, conversation_id)
            if row is None:
                # A lost confirmation response can be retried without resetting twice
                # or replaying an old command against the fresh conversation.
                return self._replacement(connection, conversation_id, 'Conversation reset. New conversation started.')
            requesting = command in ('full reset', 'full reset.')
            if not requesting and not row['reset_pending']:
                return None
            if row['reset_pending'] and command in ('yes', 'yes.'):
                replacement_id = uuid4()
                previous = world_from_json(row['domain'], row['world_json'])
                if isinstance(previous, CellularWorld):
                    if cellular_initial is None:
                        raise SnapshotConflict('Cellular initial state is unavailable')
                    empty = cellular_initial
                else:
                    empty = World(width=previous.width, height=previous.height, objects=[])
                connection.execute('''
                    INSERT INTO conversations (id, domain, language_version, next_object_id)
                    VALUES (?, ?, ?, ?)
                ''', (str(replacement_id), row['domain'], row['language_version'], row['next_object_id']))
                connection.execute('''
                    INSERT INTO world_snapshots (conversation_id, sequence, world_json)
                    VALUES (?, 0, ?)
                ''', (str(replacement_id), empty.model_dump_json()))
                connection.execute('''
                    INSERT INTO world_slots
                    (conversation_id, slot, language_version, world_json, salience_json, saved_at)
                    SELECT ?, slot, language_version, world_json, salience_json, saved_at
                    FROM world_slots WHERE conversation_id=?
                ''', (str(replacement_id), str(conversation_id)))
                # Retain only ID handover receipts, so device preferences can recover
                # after a lost response. Old chat, worlds and agent-session links go.
                connection.execute('UPDATE conversation_resets SET new_id=? WHERE new_id=?',
                                   (str(replacement_id), str(conversation_id)))
                connection.execute('INSERT INTO conversation_resets (old_id, new_id) VALUES (?, ?)',
                                   (str(conversation_id), str(replacement_id)))
                connection.execute('DELETE FROM conversations WHERE id=?', (str(conversation_id),))
                feedback = 'Conversation reset. New conversation started.'
                self._append_messages(connection, replacement_id, feedback)
                state = self._state(connection, self._latest(connection, replacement_id), replacement_id,
                                    self._messages(connection, replacement_id), feedback)
                state.resetFrom = conversation_id
                return state
            active = self._active_proposal(connection, conversation_id)
            revision = self._revision(connection, row, conversation_id)
            cancelling = row['reset_pending'] and command in ('no', 'no.')
            feedback = ('Reset cancelled.' if cancelling else
                        'Reset this conversation permanently? Saved slots will be kept. Reply yes or no.')
            connection.execute('UPDATE conversations SET reset_pending=? WHERE id=?',
                               (0 if cancelling else 1, str(conversation_id)))
            self._append_messages(connection, conversation_id, feedback, user_text=text)
            current = self._latest(connection, conversation_id)
            # A cancelled confirmation leaves an otherwise valid offer reviewable.
            if active is not None and tuple(json.loads(active['base_revision_json'])) == revision:
                connection.execute('UPDATE interpretation_proposals SET base_revision_json=? WHERE id=?',
                                   (json.dumps(self._revision(connection, current, conversation_id)), active['id']))
            return self._state(connection, current, conversation_id,
                               self._messages(connection, conversation_id), feedback)

    def edit(self, conversation_id: UUID,
             update: Callable[[DomainId, WorldState, list[dict], PendingEntry | None, int], EngineReply],
             user_text: str | None = None, continuation: bool = False,
             llm: LlmUsage | None = None,
             expected_revision: ConversationRevision | None = None,
             accepting_proposal: tuple[UUID, int] | None = None) -> EditState | None:
        with self.database.connection() as connection:
            # The entire engine round trip is serialized with snapshot persistence.
            connection.execute("BEGIN IMMEDIATE")
            row = self._latest(connection, conversation_id)
            if row is None:
                return None
            self._require_not_resetting(row)
            active = self._active_proposal(connection, conversation_id)
            selected = None
            if accepting_proposal is not None:
                _, selected = self._review_candidate(connection, conversation_id, row, *accepting_proposal)
            elif active is not None:
                raise PendingConflict('Accept or reject the interpretation first')
            if expected_revision is not None and self._revision(connection, row, conversation_id) != expected_revision:
                raise SnapshotConflict('Conversation changed during LLM translation; retry your entry')
            pending = self._pending(row)
            if (continuation and not pending) or (pending and not continuation and user_text is None):
                raise PendingConflict("Choose an object, square, or grouping, or undo" if pending else "No clarification pending")
            previous = world_from_json(row['domain'], row["world_json"])
            salience = json.loads(row["salience_json"])
            reply = update(row["domain"], previous, salience, pending, row['next_object_id'])
            if reply.nextObjectId is not None:
                if reply.nextObjectId < row['next_object_id']:
                    raise SnapshotConflict('Engine allocation state moved backwards')
                connection.execute('UPDATE conversations SET next_object_id=? WHERE id=?',
                                   (reply.nextObjectId, str(conversation_id)))
            feedback = reply.feedback
            if reply.undoRequested:
                row, feedback = self._undo_snapshot(connection, conversation_id, row)
                if llm and llm.status == 'translated' and llm.translation:
                    feedback = 'Interpreted as: ' + llm.translation + '\n\n' + feedback
            else:
                if pending and not continuation:
                    raise PendingConflict("Choose an object, square, or grouping, or undo")
                changed = reply.world != previous or reply.salience != salience or reply.pending != pending
                if changed:
                    values = (reply.world.model_dump_json(), json.dumps(reply.salience),
                              reply.pending.model_dump_json() if reply.pending else "null")
                    if continuation:
                        # All continuations replace this entry's snapshot; its predecessor
                        # remains the complete pre-entry world AND discourse state.
                        connection.execute("""
                            UPDATE world_snapshots SET world_json = ?, salience_json = ?, pending_json = ?
                            WHERE conversation_id = ? AND sequence = ?
                        """, (*values, str(conversation_id), row["sequence"]))
                    else:
                        connection.execute("""
                            INSERT INTO world_snapshots
                            (world_json, salience_json, pending_json, conversation_id, sequence)
                            VALUES (?, ?, ?, ?, ?)
                        """, (*values, str(conversation_id), row["sequence"] + 1))
            if selected is not None:
                feedback = f'Accepted interpretation {selected.rank}: {selected.translation}\n\n' + feedback
                connection.execute("UPDATE interpretation_proposals SET status = 'accepted' WHERE id = ?",
                                   (str(accepting_proposal[0]),))
            if user_text is not None or selected is not None:
                self._append_messages(connection, conversation_id, feedback, reply.isError, llm, user_text)
            current = self._latest(connection, conversation_id)
            record_outcome(connection, conversation_id,
                           kind='accepted' if selected else 'undo' if reply.undoRequested else 'engine_result',
                           userText=user_text, translation=selected.translation if selected else None,
                           feedback=feedback, pending=self._pending(current) is not None, isError=reply.isError)
            result = self._state(connection, current, conversation_id,
                                 self._messages(connection, conversation_id), feedback)
            result.changes = reply.changes
            result.changedCells = reply.changedCells
            return result

    def _undo_snapshot(self, connection, conversation_id, row):
        if row["sequence"] == 0:
            return row, "No change"
        connection.execute("DELETE FROM world_snapshots WHERE conversation_id = ? AND sequence = ?",
                           (str(conversation_id), row["sequence"]))
        return self._latest(connection, conversation_id), "Undone"

    def world_slot(self, conversation_id: UUID, slot: int, *, save: bool,
                   overwrite: bool = False) -> EditState | None:
        """Store or restore an exact checkpoint; this does not interpret or edit objects."""
        with self.database.connection() as connection:
            connection.execute('BEGIN IMMEDIATE')
            row = self._latest(connection, conversation_id)
            if row is None:
                return None
            self._require_not_resetting(row)
            if self._active_proposal(connection, conversation_id) is not None or self._pending(row) is not None:
                raise PendingConflict('Finish the pending interpretation or clarification first')
            stored = connection.execute(
                'SELECT * FROM world_slots WHERE conversation_id=? AND slot=?',
                (str(conversation_id), slot)).fetchone()
            if save:
                if stored is not None and not overwrite:
                    raise SnapshotConflict(f'Slot {slot} is already saved; confirm overwrite')
                connection.execute('''
                    INSERT INTO world_slots (conversation_id, slot, language_version, world_json, salience_json)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(conversation_id, slot) DO UPDATE SET
                        language_version=excluded.language_version, world_json=excluded.world_json,
                        salience_json=excluded.salience_json,
                        saved_at=strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
                ''', (str(conversation_id), slot, row['language_version'], row['world_json'], row['salience_json']))
                feedback = f'Saved slot {slot}'
            else:
                if stored is None:
                    raise WorldSlotEmpty(f'Slot {slot} is empty')
                if stored['language_version'] != row['language_version']:
                    raise SnapshotConflict('Saved setup uses a different language version')
                # Allocation is conversation-wide and never moves backwards, including
                # when restoring earlier identifiers from a saved world.
                connection.execute('''
                    INSERT INTO world_snapshots
                    (conversation_id, sequence, world_json, salience_json, pending_json)
                    VALUES (?, ?, ?, ?, 'null')
                ''', (str(conversation_id), row['sequence'] + 1, stored['world_json'], stored['salience_json']))
                feedback = f'Loaded slot {slot}'
                self._append_messages(connection, conversation_id, feedback)
                record_outcome(connection, conversation_id, kind='world_loaded', slot=slot,
                               feedback=feedback, referenceContextRestored=True)
                row = self._latest(connection, conversation_id)
            return self._state(connection, row, conversation_id,
                               self._messages(connection, conversation_id), feedback)

    def undo(self, conversation_id: UUID) -> EditState | None:
        with self.database.connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = self._latest(connection, conversation_id)
            if row is None:
                return None
            self._require_not_resetting(row)
            if self._active_proposal(connection, conversation_id) is not None:
                raise PendingConflict('Accept or reject the interpretation first')
            row, feedback = self._undo_snapshot(connection, conversation_id, row)
            record_outcome(connection, conversation_id, kind='undo', feedback=feedback)
            return self._state(connection, row, conversation_id, self._messages(connection, conversation_id), feedback)

    def propose(self, conversation_id: UUID, proposal: InterpretationProposal,
                expected_revision: ConversationRevision, feedback: str,
                replacing_proposal: UUID | None = None, answer: str | None = None) -> EditState | None:
        with self.database.connection() as connection:
            connection.execute('BEGIN IMMEDIATE')
            row = self._latest(connection, conversation_id)
            if row is None:
                return None
            self._require_not_resetting(row)
            if self._revision(connection, row, conversation_id) != expected_revision:
                raise SnapshotConflict('Conversation changed during LLM translation; retry your entry')
            if replacing_proposal is not None:
                self._review_proposal(connection, conversation_id, row, replacing_proposal)
                # Retire the old draft without treating either draft as a world edit.
                connection.execute("UPDATE interpretation_proposals SET status = 'rejected' WHERE id = ?",
                                   (str(replacing_proposal),))
            elif self._active_proposal(connection, conversation_id) is not None:
                raise PendingConflict('Finish the pending interpretation or clarification first')
            if self._pending(row) is not None:
                raise PendingConflict('Finish the pending interpretation or clarification first')
            self._append_messages(connection, conversation_id, feedback, llm=proposal.llm,
                                  user_text=answer if answer is not None else proposal.originalText,
                                  is_error=not proposal.candidates and proposal.llm.status != 'clarification')
            revision = self._revision(connection, row, conversation_id)
            connection.execute(
                'INSERT INTO interpretation_proposals (id, conversation_id, proposal_json, base_revision_json) VALUES (?, ?, ?, ?)',
                (str(proposal.id), str(conversation_id), proposal.model_dump_json(), json.dumps(revision)))
            if proposal.validationFailures:
                record_outcome(connection, conversation_id, kind='parser_rejection',
                               failures=[failure.model_dump() for failure in proposal.validationFailures])
            return self._state(connection, row, conversation_id, self._messages(connection, conversation_id), feedback)

    def converse(self, conversation_id: UUID, user_text: str, reply: str, llm: LlmUsage,
                 expected_revision: ConversationRevision, proposal_id: UUID | None = None) -> EditState | None:
        """Persist plain dialogue without evaluating or advancing symbolic state."""
        with self.database.connection() as connection:
            connection.execute('BEGIN IMMEDIATE')
            row = self._latest(connection, conversation_id)
            if row is None:
                return None
            self._require_not_resetting(row)
            if self._revision(connection, row, conversation_id) != expected_revision:
                raise SnapshotConflict('Conversation changed during LLM response; refresh and resend')
            if proposal_id is not None:
                self._review_proposal(connection, conversation_id, row, proposal_id)
            elif self._active_proposal(connection, conversation_id) is not None:
                raise PendingConflict('Accept or reject the interpretation first')
            self._append_messages(connection, conversation_id, reply, llm=llm, user_text=user_text)
            if proposal_id is not None:
                # Courtesy is not an answer and must not stale the existing offer.
                revision = self._revision(connection, row, conversation_id)
                connection.execute('UPDATE interpretation_proposals SET base_revision_json=? WHERE id=?',
                                   (json.dumps(revision), str(proposal_id)))
            return self._state(connection, row, conversation_id, self._messages(connection, conversation_id), reply)

    def _review_proposal(self, connection, conversation_id, row, proposal_id):
        self._require_not_resetting(row)
        active = self._active_proposal(connection, conversation_id)
        if active is None or active['id'] != str(proposal_id):
            raise PendingConflict('This interpretation is no longer pending; refresh the conversation')
        if tuple(json.loads(active['base_revision_json'])) != self._revision(connection, row, conversation_id):
            raise SnapshotConflict('Conversation changed; reject this interpretation and resend your prompt')
        proposal = InterpretationProposal.model_validate_json(active['proposal_json'])
        if proposal.languageVersion != row['language_version']:
            raise SnapshotConflict('Interpretation uses an older language version; reject it and resend your prompt')
        return proposal

    def proposal_with_revision(self, conversation_id: UUID, proposal_id: UUID):
        with self.database.connection() as connection:
            connection.execute('BEGIN')
            row = self._latest(connection, conversation_id)
            if row is None:
                return None
            self._review_proposal(connection, conversation_id, row, proposal_id)
            return (self._state(connection, row, conversation_id, self._messages(connection, conversation_id)),
                    self._revision(connection, row, conversation_id))

    def _review_candidate(self, connection, conversation_id, row, proposal_id, rank):
        proposal = self._review_proposal(connection, conversation_id, row, proposal_id)
        candidate = next((candidate for candidate in proposal.candidates if candidate.rank == rank), None)
        if candidate is None:
            raise PendingConflict('Choose one of the listed interpretations')
        return proposal, candidate

    def preview(self, conversation_id: UUID, proposal_id: UUID, rank: int,
                evaluate: Callable) -> EditState | None:
        with self.database.connection() as connection:
            connection.execute('BEGIN')
            row = self._latest(connection, conversation_id)
            if row is None:
                return None
            _, candidate = self._review_candidate(connection, conversation_id, row, proposal_id, rank)
            world = world_from_json(row['domain'], row['world_json'])
            reply = evaluate(row['domain'], world, json.loads(row['salience_json']), candidate.translation, row['next_object_id'])
            if reply.undoRequested:
                previous = connection.execute(
                    'SELECT * FROM world_snapshots WHERE conversation_id = ? AND sequence < ? ORDER BY sequence DESC LIMIT 1',
                    (str(conversation_id), row['sequence']),
                ).fetchone()
                reply.world = world_from_json(row['domain'], previous['world_json']) if previous else world
                reply.pending = self._pending(previous) if previous else self._pending(row)
                reply.feedback = 'Undone' if previous else 'No change'
            state = self._state(connection, row, conversation_id, self._messages(connection, conversation_id),
                                'Preview only; nothing was applied.')
            state.preview = InterpretationPreview(proposalId=proposal_id, rank=rank, world=reply.world,
                                                   feedback=reply.feedback, pending=reply.pending, changes=reply.changes)
            return state

    def accept(self, conversation_id: UUID, proposal_id: UUID, rank: int, evaluate: Callable) -> EditState | None:
        # Candidate text is loaded from storage, never supplied by the client.
        state = self.get(conversation_id)
        if state is None:
            return None
        if state.proposal is None or state.proposal.id != proposal_id:
            raise PendingConflict('This interpretation is no longer pending; refresh the conversation')
        candidate = next((candidate for candidate in state.proposal.candidates if candidate.rank == rank), None)
        if candidate is None:
            raise PendingConflict('Choose one of the listed interpretations')
        return self.edit(conversation_id,
                         lambda domain, world, salience, pending, next_id: evaluate(domain, world, salience, candidate.translation, next_id),
                         accepting_proposal=(proposal_id, rank))

    def reject(self, conversation_id: UUID, proposal_id: UUID) -> EditState | None:
        with self.database.connection() as connection:
            connection.execute('BEGIN IMMEDIATE')
            row = self._latest(connection, conversation_id)
            if row is None:
                return None
            self._require_not_resetting(row)
            active = self._active_proposal(connection, conversation_id)
            if active is None or active['id'] != str(proposal_id):
                raise PendingConflict('This interpretation is no longer pending; refresh the conversation')
            connection.execute("UPDATE interpretation_proposals SET status = 'rejected' WHERE id = ?", (str(proposal_id),))
            feedback = 'Interpretation rejected. Edit your original prompt and resend it.'
            self._append_messages(connection, conversation_id, feedback)
            record_outcome(connection, conversation_id, kind='rejected', proposalId=str(proposal_id),
                           originalText=InterpretationProposal.model_validate_json(active['proposal_json']).originalText)
            return self._state(connection, row, conversation_id, self._messages(connection, conversation_id), feedback)
