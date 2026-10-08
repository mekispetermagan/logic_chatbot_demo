from uuid import UUID
from collections.abc import Callable

from .database import Database
from .schemas import ChatMessage, ConversationState, EditState, World


class ConversationRepository:
    def __init__(self, database: Database):
        self.database = database

    def _messages(self, connection, conversation_id: UUID) -> list[ChatMessage]:
        rows = connection.execute(
            "SELECT role, text, is_error FROM chat_messages WHERE conversation_id = ? ORDER BY sequence",
            (str(conversation_id),),
        ).fetchall()
        return [ChatMessage(role=row["role"], text=row["text"], isError=bool(row["is_error"])) for row in rows]

    def create(self, conversation_id: UUID, world: World) -> ConversationState:
        # Conversation and initial snapshot are committed together.
        with self.database.connection() as connection:
            connection.execute("INSERT INTO conversations (id) VALUES (?)", (str(conversation_id),))
            connection.execute(
                "INSERT INTO world_snapshots (conversation_id, sequence, world_json) VALUES (?, 0, ?)",
                (str(conversation_id), world.model_dump_json()),
            )
        return ConversationState(conversationId=conversation_id, world=world, canUndo=False)

    def get(self, conversation_id: UUID) -> ConversationState | None:
        with self.database.connection() as connection:
            row = connection.execute("""
                SELECT world_json, sequence FROM world_snapshots
                WHERE conversation_id = ? ORDER BY sequence DESC LIMIT 1
            """, (str(conversation_id),)).fetchone()
            messages = self._messages(connection, conversation_id)
        if row is None:
            return None
        return ConversationState(
            conversationId=conversation_id,
            world=World.model_validate_json(row["world_json"]),
            canUndo=row["sequence"] > 0,
            messages=messages,
        )

    def edit(
        self, conversation_id: UUID, update: Callable[[World], tuple[World, str, bool]],
        user_text: str | None = None,
    ) -> EditState | None:
        with self.database.connection() as connection:
            # Serialize read/evaluate/write so even duplicate requests cannot
            # overwrite an intervening snapshot. Engine failure rolls back.
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute("""
                SELECT world_json, sequence FROM world_snapshots
                WHERE conversation_id = ? ORDER BY sequence DESC LIMIT 1
            """, (str(conversation_id),)).fetchone()
            if row is None:
                return None
            previous = World.model_validate_json(row["world_json"])
            world, feedback, is_error = update(previous)
            sequence = row["sequence"]
            if world != previous:
                sequence += 1
                connection.execute(
                    "INSERT INTO world_snapshots (conversation_id, sequence, world_json) VALUES (?, ?, ?)",
                    (str(conversation_id), sequence, world.model_dump_json()),
                )
            if user_text is not None:
                next_message = connection.execute(
                    "SELECT COALESCE(MAX(sequence), -1) + 1 FROM chat_messages WHERE conversation_id = ?",
                    (str(conversation_id),),
                ).fetchone()[0]
                connection.executemany(
                    "INSERT INTO chat_messages (conversation_id, sequence, role, text, is_error) VALUES (?, ?, ?, ?, ?)",
                    [(str(conversation_id), next_message, "user", user_text, 0),
                     (str(conversation_id), next_message + 1, "machine", feedback, int(is_error))],
                )
            messages = self._messages(connection, conversation_id)
        return EditState(conversationId=conversation_id, world=world,
                         canUndo=sequence > 0, feedback=feedback, messages=messages)

    def undo(self, conversation_id: UUID) -> EditState | None:
        with self.database.connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute("""
                SELECT world_json, sequence FROM world_snapshots
                WHERE conversation_id = ? ORDER BY sequence DESC LIMIT 1
            """, (str(conversation_id),)).fetchone()
            if row is None:
                return None
            feedback = "No change"
            if row["sequence"] > 0:
                connection.execute(
                    "DELETE FROM world_snapshots WHERE conversation_id = ? AND sequence = ?",
                    (str(conversation_id), row["sequence"]),
                )
                row = connection.execute("""
                    SELECT world_json, sequence FROM world_snapshots
                    WHERE conversation_id = ? ORDER BY sequence DESC LIMIT 1
                """, (str(conversation_id),)).fetchone()
                feedback = "Undone"
            messages = self._messages(connection, conversation_id)
        return EditState(conversationId=conversation_id,
                         world=World.model_validate_json(row["world_json"]),
                         canUndo=row["sequence"] > 0, feedback=feedback, messages=messages)
