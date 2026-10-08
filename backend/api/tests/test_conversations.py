import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.config import Settings, TOY_WORLD_PATH
from app.database import Database
from app.main import create_app
from app.repository import ConversationRepository
from app.schemas import World


class ConversationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "nested" / "conversations.sqlite3"
        self.settings = Settings(database_path=self.path)
        self.initial_world = json.loads(TOY_WORLD_PATH.read_text())

    def test_create_retrieve_and_isolation(self):
        with TestClient(create_app(self.settings)) as client:
            first = client.post("/conversations")
            second = client.post("/conversations")
            self.assertEqual(first.status_code, 201)
            self.assertEqual(second.status_code, 201)
            state = first.json()
            self.assertNotEqual(state["conversationId"], second.json()["conversationId"])
            self.assertEqual(UUID(state["conversationId"]).version, 4)
            self.assertEqual(state["world"], self.initial_world)
            self.assertFalse(state["canUndo"])
            self.assertEqual(first.headers["Location"], f'/conversations/{state["conversationId"]}')
            self.assertEqual(client.get(first.headers["Location"]).json(), state)
            # Insert a future snapshot at the storage boundary: verify latest-state
            # retrieval and independence without implementing world updates here.
            with Database(self.path).connection() as connection:
                connection.execute(
                    "INSERT INTO world_snapshots (conversation_id, sequence, world_json) VALUES (?, 1, ?)",
                    (state["conversationId"], json.dumps({"width": 8, "height": 8, "objects": []})),
                )
            updated = client.get(first.headers["Location"]).json()
            self.assertEqual(updated["world"]["objects"], [])
            self.assertTrue(updated["canUndo"])
            self.assertEqual(client.get(second.headers["Location"]).json(), second.json())

    def test_state_survives_restart_and_schema_initialization_is_idempotent(self):
        with TestClient(create_app(self.settings)) as client:
            created = client.post("/conversations")
        with TestClient(create_app(self.settings)) as client:
            loaded = client.get(created.headers["Location"])
            self.assertEqual(loaded.status_code, 200)
            self.assertEqual(loaded.json(), created.json())
        with Database(self.path).connection() as connection:
            self.assertEqual(connection.execute("SELECT count(*) FROM conversations").fetchone()[0], 1)
            self.assertEqual(connection.execute("SELECT count(*) FROM world_snapshots").fetchone()[0], 1)

    def test_unknown_and_malformed_ids(self):
        with TestClient(create_app(self.settings)) as client:
            missing = client.get(f"/conversations/{uuid4()}")
            self.assertEqual(missing.status_code, 404)
            self.assertEqual(missing.json()["detail"], "Conversation not found")
            self.assertEqual(client.get("/conversations/not-an-id").status_code, 422)

    def test_cors_allows_configured_browser_origin(self):
        with TestClient(create_app(self.settings)) as client:
            headers = {"Origin": "http://localhost:8080",
                       "Access-Control-Request-Method": "POST"}
            preflight = client.options("/conversations", headers=headers)
            self.assertEqual(preflight.status_code, 200)
            self.assertEqual(preflight.headers["access-control-allow-origin"], headers["Origin"])
            created = client.post("/conversations", headers={"Origin": headers["Origin"]})
            self.assertEqual(created.headers["access-control-allow-origin"], headers["Origin"])
            headers["Origin"] = "http://unlisted.example"
            rejected = client.options("/conversations", headers=headers)
            self.assertEqual(rejected.status_code, 400)
            self.assertNotIn("access-control-allow-origin", rejected.headers)

    def test_failed_initial_snapshot_rolls_back_conversation(self):
        database = Database(self.path)
        database.initialize()
        with database.connection() as connection:
            connection.execute("""
                CREATE TRIGGER reject_snapshot BEFORE INSERT ON world_snapshots
                BEGIN SELECT RAISE(ABORT, 'snapshot rejected'); END;
            """)
        repository = ConversationRepository(database)
        with self.assertRaises(sqlite3.IntegrityError):
            repository.create(uuid4(), World.model_validate(self.initial_world))
        with database.connection() as connection:
            self.assertEqual(connection.execute("SELECT count(*) FROM conversations").fetchone()[0], 0)

    def test_snapshot_constraints(self):
        database = Database(self.path)
        database.initialize()
        identifier = uuid4()
        ConversationRepository(database).create(identifier, World.model_validate(self.initial_world))
        for target, sequence in [(str(uuid4()), 0), (str(identifier), 0), (str(identifier), -1)]:
            with self.assertRaises(sqlite3.IntegrityError):
                with database.connection() as connection:
                    connection.execute(
                        "INSERT INTO world_snapshots (conversation_id, sequence, world_json) VALUES (?, ?, ?)",
                        (target, sequence, '{}'),
                    )

    def test_world_contract_preserves_absent_attributes_and_requires_complete_positions(self):
        world = World.model_validate(self.initial_world)
        self.assertIsNone(world.objects[2].color)
        self.assertIsNone(world.objects[3].shape)
        self.assertIsNone(world.objects[4].size)
        self.assertIsNone(world.objects[5].position)
        self.assertEqual(World.model_validate_json(world.model_dump_json()), world)
        for invalid in [
            {"width": 8, "height": 8, "objects": [{"id": 0, "position": {"x": 1}}]},
            {"width": 8, "height": 8, "objects": [{"id": "0"}]},
            {"width": 8, "height": 8, "objects": [{"id": 0, "color": "purple"}]},
            {"width": 0, "height": 8, "objects": []},
        ]:
            with self.assertRaises(ValidationError):
                World.model_validate(invalid)


if __name__ == "__main__":
    unittest.main()
