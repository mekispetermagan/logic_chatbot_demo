import json
from uuid import UUID
from collections.abc import Callable

from .database import Database
from .engine import EngineReply
from .schemas import (ChatMessage, ConversationState, EditState, World, PendingEntry, DomainId, LlmUsage,
                      InterpretationProposal, InterpretationPreview)
from .llm_budget import budget_in


class PendingConflict(Exception):
    pass


class SnapshotConflict(Exception):
    pass


ConversationRevision = tuple[int, str, str, str, int]


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
            SELECT world_snapshots.*, conversations.domain FROM world_snapshots
            JOIN conversations ON conversations.id = world_snapshots.conversation_id
            WHERE conversation_id = ? ORDER BY sequence DESC LIMIT 1
        """, (str(conversation_id),)).fetchone()

    def _pending(self, row):
        value = json.loads(row["pending_json"])
        return PendingEntry.model_validate(value) if value is not None else None

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
        values = dict(conversationId=conversation_id, domain=row["domain"],
                      world=World.model_validate_json(row["world_json"]),
                      canUndo=row["sequence"] > 0, messages=messages, pending=self._pending(row),
                      llmBudget=budget_in(connection),
                      proposal=InterpretationProposal.model_validate_json(proposal['proposal_json']) if proposal else None)
        return ConversationState(**values) if feedback is None else EditState(**values, feedback=feedback)

    def create(self, conversation_id: UUID, world: World, domain: DomainId) -> ConversationState:
        with self.database.connection() as connection:
            connection.execute("INSERT INTO conversations (id, domain) VALUES (?, ?)", (str(conversation_id), domain))
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
        return row['sequence'], row['world_json'], row['salience_json'], row['pending_json'], last_message

    def get_with_revision(self, conversation_id: UUID) -> tuple[ConversationState, ConversationRevision] | None:
        with self.database.connection() as connection:
            # Capture the world, discourse state and message revision consistently;
            # this short read transaction ends before any model request starts.
            connection.execute('BEGIN')
            row = self._latest(connection, conversation_id)
            if row is None:
                return None
            state = self._state(connection, row, conversation_id, self._messages(connection, conversation_id))
            return state, self._revision(connection, row, conversation_id)

    def edit(self, conversation_id: UUID,
             update: Callable[[DomainId, World, list[dict], PendingEntry | None], EngineReply],
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
                raise PendingConflict("Choose an object or square, or undo" if pending else "No clarification pending")
            previous = World.model_validate_json(row["world_json"])
            salience = json.loads(row["salience_json"])
            reply = update(row["domain"], previous, salience, pending)
            feedback = reply.feedback
            if reply.undoRequested:
                row, feedback = self._undo_snapshot(connection, conversation_id, row)
                if llm and llm.status == 'translated' and llm.translation:
                    feedback = 'Interpreted as: ' + llm.translation + '\n\n' + feedback
            else:
                if pending and not continuation:
                    raise PendingConflict("Choose an object or square, or undo")
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
            record_outcome(connection, conversation_id,
                           kind='accepted' if selected else 'undo' if reply.undoRequested else 'engine_result',
                           userText=user_text, translation=selected.translation if selected else None,
                           feedback=feedback, pending=reply.pending is not None, isError=reply.isError)
            return self._state(connection, self._latest(connection, conversation_id), conversation_id,
                               self._messages(connection, conversation_id), feedback)

    def _undo_snapshot(self, connection, conversation_id, row):
        if row["sequence"] == 0:
            return row, "No change"
        connection.execute("DELETE FROM world_snapshots WHERE conversation_id = ? AND sequence = ?",
                           (str(conversation_id), row["sequence"]))
        return self._latest(connection, conversation_id), "Undone"

    def undo(self, conversation_id: UUID) -> EditState | None:
        with self.database.connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = self._latest(connection, conversation_id)
            if row is None:
                return None
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
        active = self._active_proposal(connection, conversation_id)
        if active is None or active['id'] != str(proposal_id):
            raise PendingConflict('This interpretation is no longer pending; refresh the conversation')
        if tuple(json.loads(active['base_revision_json'])) != self._revision(connection, row, conversation_id):
            raise SnapshotConflict('Conversation changed; reject this interpretation and resend your prompt')
        return InterpretationProposal.model_validate_json(active['proposal_json'])

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
            world = World.model_validate_json(row['world_json'])
            reply = evaluate(row['domain'], world, json.loads(row['salience_json']), candidate.translation)
            if reply.undoRequested:
                previous = connection.execute(
                    'SELECT * FROM world_snapshots WHERE conversation_id = ? AND sequence < ? ORDER BY sequence DESC LIMIT 1',
                    (str(conversation_id), row['sequence']),
                ).fetchone()
                reply.world = World.model_validate_json(previous['world_json']) if previous else world
                reply.pending = self._pending(previous) if previous else self._pending(row)
                reply.feedback = 'Undone' if previous else 'No change'
            state = self._state(connection, row, conversation_id, self._messages(connection, conversation_id),
                                'Preview only; nothing was applied.')
            state.preview = InterpretationPreview(proposalId=proposal_id, rank=rank, world=reply.world,
                                                   feedback=reply.feedback, pending=reply.pending)
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
                         lambda domain, world, salience, pending: evaluate(domain, world, salience, candidate.translation),
                         accepting_proposal=(proposal_id, rank))

    def reject(self, conversation_id: UUID, proposal_id: UUID) -> EditState | None:
        with self.database.connection() as connection:
            connection.execute('BEGIN IMMEDIATE')
            row = self._latest(connection, conversation_id)
            if row is None:
                return None
            active = self._active_proposal(connection, conversation_id)
            if active is None or active['id'] != str(proposal_id):
                raise PendingConflict('This interpretation is no longer pending; refresh the conversation')
            connection.execute("UPDATE interpretation_proposals SET status = 'rejected' WHERE id = ?", (str(proposal_id),))
            feedback = 'Interpretation rejected. Edit your original prompt and resend it.'
            self._append_messages(connection, conversation_id, feedback)
            record_outcome(connection, conversation_id, kind='rejected', proposalId=str(proposal_id),
                           originalText=InterpretationProposal.model_validate_json(active['proposal_json']).originalText)
            return self._state(connection, row, conversation_id, self._messages(connection, conversation_id), feedback)
