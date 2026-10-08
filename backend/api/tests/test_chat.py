import os
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from fastapi.testclient import TestClient

from app.config import ENGINE_PATH, Settings
from app.database import Database
from app.main import create_app


class ChatTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "chat.sqlite3"
        self.settings = Settings(database_path=self.path,
            engine_path=Path(os.environ.get("LOGIC_CHATBOT_ENGINE_PATH", str(ENGINE_PATH))))
        self.client = TestClient(create_app(self.settings))
        self.client.__enter__()
        self.addCleanup(self.client.__exit__, None, None, None)
        self.initial = self.client.post("/conversations").json()
        self.base = f'/conversations/{self.initial["conversationId"]}'

    def chat(self, text):
        reply = self.client.post(f"{self.base}/chat", json={"text": text})
        self.assertEqual(reply.status_code, 200, reply.text)
        return reply.json()

    def snapshots(self):
        with Database(self.path).connection() as connection:
            return connection.execute("SELECT count(*) FROM world_snapshots").fetchone()[0]

    def test_sequence_one_snapshot_and_undo_keeps_messages(self):
        text = "#0 blue. #0 small. #0 blue? color of #0?"
        result = self.chat(text)
        obj = next(obj for obj in result["world"]["objects"] if obj["id"] == 0)
        self.assertEqual((obj["color"], obj["size"]), ("blue", "small"))
        self.assertEqual(self.snapshots(), 2)
        self.assertEqual(result["messages"][0]["text"], text)
        self.assertEqual(result["messages"][1]["text"], result["feedback"])
        self.assertIn("#0 blue?\n  true", result["feedback"])
        self.assertIn("color of #0?\n  blue", result["feedback"])
        undone = self.client.post(f"{self.base}/undo").json()
        self.assertEqual(undone["world"], self.initial["world"])
        self.assertEqual(undone["messages"], result["messages"])
        self.assertEqual(self.snapshots(), 1)

    def test_questions_and_parse_errors_do_not_create_snapshots(self):
        self.chat("color of #0? #0 red?")
        result = self.chat("#0 blue. not a sentence")
        self.assertEqual(result["world"], self.initial["world"])
        self.assertEqual(self.snapshots(), 1)
        self.assertTrue(result["messages"][-1]["isError"])
        self.assertEqual([m["role"] for m in result["messages"]], ["user", "machine", "user", "machine"])

    def test_revision_returning_to_original_world_is_not_undoable(self):
        result = self.chat("#0 blue. #0 red.")
        self.assertEqual(result["world"], self.initial["world"])
        self.assertEqual(self.snapshots(), 1)
        self.assertFalse(result["canUndo"])

    def test_restart_isolation_and_visual_edits_preserve_chat(self):
        result = self.chat("#99 green. color of #99?")
        self.assertIsNone(next(o for o in result["world"]["objects"] if o["id"] == 99)["position"])
        visual = self.client.post(f"{self.base}/clear").json()
        self.assertEqual(visual["messages"], result["messages"])
        with TestClient(create_app(self.settings)) as restarted:
            loaded = restarted.get(self.base).json()
            self.assertEqual(loaded["messages"], result["messages"])
            self.assertEqual(loaded["world"], visual["world"])
        other = self.client.post("/conversations").json()
        self.assertEqual(other["messages"], [])

    def test_invalid_request_and_engine_failure_save_nothing(self):
        for body in [{"text": ""}, {"text": " \n "}, {"text": 3}, {}]:
            self.assertEqual(self.client.post(f"{self.base}/chat", json=body).status_code, 422)
        self.assertEqual(self.client.post(f"/conversations/{uuid4()}/chat", json={"text": "#0 red."}).status_code, 404)
        with patch("app.engine.subprocess.run", side_effect=FileNotFoundError()):
            self.assertEqual(self.client.post(f"{self.base}/chat", json={"text": "#0 blue."}).status_code, 503)
        self.assertEqual(self.client.get(self.base).json(), self.initial)

    def test_message_insert_failure_rolls_back_world_update(self):
        with Database(self.path).connection() as connection:
            connection.execute("""CREATE TRIGGER reject_message BEFORE INSERT ON chat_messages
                BEGIN SELECT RAISE(ABORT, 'message rejected'); END;""")
        with self.assertRaises(sqlite3.IntegrityError):
            self.client.post(f"{self.base}/chat", json={"text": "#0 blue."})
        self.assertEqual(self.snapshots(), 1)
        self.assertEqual(self.client.get(self.base).json(), self.initial)
