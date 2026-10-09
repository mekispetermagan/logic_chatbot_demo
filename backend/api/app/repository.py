import json
from uuid import UUID
from collections.abc import Callable

from .database import Database
from .engine import EngineReply
from .schemas import ChatMessage, ConversationState, EditState, World, PendingEntry


class PendingConflict(Exception):
    pass


class ConversationRepository:
    def __init__(self, database: Database):
        self.database = database

    def _messages(self, connection, conversation_id: UUID) -> list[ChatMessage]:
        rows = connection.execute(
            "SELECT role, text, is_error FROM chat_messages WHERE conversation_id = ? ORDER BY sequence",
            (str(conversation_id),),
        ).fetchall()
        return [ChatMessage(role=row["role"], text=row["text"], isError=bool(row["is_error"])) for row in rows]

    def _latest(self, connection, conversation_id):
        return connection.execute("""
            SELECT * FROM world_snapshots WHERE conversation_id = ? ORDER BY sequence DESC LIMIT 1
        """, (str(conversation_id),)).fetchone()

    def _pending(self, row):
        value = json.loads(row["pending_json"])
        return PendingEntry.model_validate(value) if value is not None else None

    def _state(self, row, conversation_id, messages, feedback=None):
        values = dict(conversationId=conversation_id,
                      world=World.model_validate_json(row["world_json"]),
                      canUndo=row["sequence"] > 0, messages=messages, pending=self._pending(row))
        return ConversationState(**values) if feedback is None else EditState(**values, feedback=feedback)

    def create(self, conversation_id: UUID, world: World) -> ConversationState:
        with self.database.connection() as connection:
            connection.execute("INSERT INTO conversations (id) VALUES (?)", (str(conversation_id),))
            connection.execute(
                "INSERT INTO world_snapshots (conversation_id, sequence, world_json) VALUES (?, 0, ?)",
                (str(conversation_id), world.model_dump_json()),
            )
        return ConversationState(conversationId=conversation_id, world=world, canUndo=False)

    def get(self, conversation_id: UUID) -> ConversationState | None:
        with self.database.connection() as connection:
            row = self._latest(connection, conversation_id)
            return None if row is None else self._state(row, conversation_id, self._messages(connection, conversation_id))

    def edit(self, conversation_id: UUID,
             update: Callable[[World, list[dict], PendingEntry | None], EngineReply],
             user_text: str | None = None, continuation: bool = False) -> EditState | None:
        with self.database.connection() as connection:
            # The entire engine round trip is serialized with snapshot persistence.
            connection.execute("BEGIN IMMEDIATE")
            row = self._latest(connection, conversation_id)
            if row is None:
                return None
            pending = self._pending(row)
            if bool(pending) != continuation:
                raise PendingConflict("Choose an object or undo" if pending else "No clarification pending")
            previous = World.model_validate_json(row["world_json"])
            salience = json.loads(row["salience_json"])
            reply = update(previous, salience, pending)
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
                    "INSERT INTO chat_messages (conversation_id, sequence, role, text, is_error) VALUES (?, ?, ?, ?, ?)",
                    [(str(conversation_id), next_message, "user", user_text, 0),
                     (str(conversation_id), next_message + 1, "machine", reply.feedback, int(reply.isError))],
                )
            return self._state(self._latest(connection, conversation_id), conversation_id,
                               self._messages(connection, conversation_id), reply.feedback)

    def undo(self, conversation_id: UUID) -> EditState | None:
        with self.database.connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = self._latest(connection, conversation_id)
            if row is None:
                return None
            feedback = "No change"
            if row["sequence"] > 0:
                connection.execute("DELETE FROM world_snapshots WHERE conversation_id = ? AND sequence = ?",
                                   (str(conversation_id), row["sequence"]))
                row = self._latest(connection, conversation_id)
                feedback = "Undone"
            return self._state(row, conversation_id, self._messages(connection, conversation_id), feedback)
