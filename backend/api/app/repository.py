from uuid import UUID
from collections.abc import Callable

from .database import Database
from .schemas import ConversationState, EditState, World


class ConversationRepository:
    def __init__(self, database: Database):
        self.database = database

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
        if row is None:
            return None
        return ConversationState(
            conversationId=conversation_id,
            world=World.model_validate_json(row["world_json"]),
            canUndo=row["sequence"] > 0,
        )

    def edit(
        self, conversation_id: UUID, update: Callable[[World], tuple[World, str]]
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
            world, feedback = update(previous)
            sequence = row["sequence"]
            if world != previous:
                sequence += 1
                connection.execute(
                    "INSERT INTO world_snapshots (conversation_id, sequence, world_json) VALUES (?, ?, ?)",
                    (str(conversation_id), sequence, world.model_dump_json()),
                )
        return EditState(conversationId=conversation_id, world=world,
                         canUndo=sequence > 0, feedback=feedback)

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
        return EditState(conversationId=conversation_id,
                         world=World.model_validate_json(row["world_json"]),
                         canUndo=row["sequence"] > 0, feedback=feedback)
