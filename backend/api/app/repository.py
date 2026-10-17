import json
from uuid import UUID
from collections.abc import Callable

from .database import Database
from .engine import EngineReply
from .schemas import ChatMessage, ConversationState, EditState, World, PendingEntry, DomainId, LlmUsage
from .llm_budget import budget_in


class PendingConflict(Exception):
    pass


class SnapshotConflict(Exception):
    pass


ConversationRevision = tuple[int, str, str, str, int]


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

    def _state(self, connection, row, conversation_id, messages, feedback=None):
        values = dict(conversationId=conversation_id, domain=row["domain"],
                      world=World.model_validate_json(row["world_json"]),
                      canUndo=row["sequence"] > 0, messages=messages, pending=self._pending(row),
                      llmBudget=budget_in(connection))
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
             expected_revision: ConversationRevision | None = None) -> EditState | None:
        with self.database.connection() as connection:
            # The entire engine round trip is serialized with snapshot persistence.
            connection.execute("BEGIN IMMEDIATE")
            row = self._latest(connection, conversation_id)
            if row is None:
                return None
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
            if user_text is not None:
                next_message = connection.execute(
                    "SELECT COALESCE(MAX(sequence), -1) + 1 FROM chat_messages WHERE conversation_id = ?",
                    (str(conversation_id),),
                ).fetchone()[0]
                connection.executemany(
                    "INSERT INTO chat_messages (conversation_id, sequence, role, text, is_error, llm_json) VALUES (?, ?, ?, ?, ?, ?)",
                    [(str(conversation_id), next_message, "user", user_text, 0, None),
                     (str(conversation_id), next_message + 1, "machine", feedback, int(reply.isError),
                      llm.model_dump_json() if llm else None)],
                )
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
            row, feedback = self._undo_snapshot(connection, conversation_id, row)
            return self._state(connection, row, conversation_id, self._messages(connection, conversation_id), feedback)
