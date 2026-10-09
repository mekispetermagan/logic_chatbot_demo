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
        self.assertIn("#0 is blue?\n  true", result["feedback"])
        self.assertIn("color of #0?\n  blue", result["feedback"])
        undone = self.client.post(f"{self.base}/undo").json()
        self.assertEqual(undone["world"], self.initial["world"])
        self.assertEqual(undone["messages"], result["messages"])
        self.assertEqual(self.snapshots(), 1)

    def test_questions_create_discourse_snapshot_parse_errors_do_not(self):
        self.chat("color of #0? #0 red?")
        result = self.chat("#0 blue. not a sentence")
        self.assertEqual(result["world"], self.initial["world"])
        self.assertEqual(self.snapshots(), 2)
        self.assertTrue(result["messages"][-1]["isError"])
        self.assertEqual([m["role"] for m in result["messages"]], ["user", "machine", "user", "machine"])

    def test_revision_returning_to_original_world_has_discourse_undo(self):
        result = self.chat("#0 blue. #0 red.")
        self.assertEqual(result["world"], self.initial["world"])
        self.assertEqual(self.snapshots(), 2)
        self.assertTrue(result["canUndo"])

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

    def test_layer2_evaluation(self):
        result = self.chat("#99 is a large blue sphere. It is red. Color of the sphere?")
        self.assertIn("red", result["feedback"])
        obj = next(o for o in result["world"]["objects"] if o["id"] == 99)
        self.assertEqual((obj["color"], obj["shape"], obj["size"]), ("red", "sphere", "large"))
        self.assertEqual(self.snapshots(), 2)

    def test_natural_atomic_forms_use_existing_evaluation(self):
        result = self.chat("#0 is a blue. Is #0 blue? What is the color of #0?")
        self.assertIn("#0 is blue?\n  true", result["feedback"])
        self.assertIn("color of #0?\n  blue", result["feedback"])
        self.assertEqual(self.snapshots(), 2)
        rejected = self.chat("#0 red #0 green")
        self.assertTrue(rejected["messages"][-1]["isError"])
        self.assertEqual(rejected["world"], result["world"])

    def test_pending_restart_resume_and_whole_entry_undo(self):
        self.client.post(f"{self.base}/clear")
        before = self.chat("#0 cube. #1 cube.")
        paused = self.chat("#2 red. The cube is blue. It is large.")
        self.assertIsNotNone(paused["pending"])
        self.assertCountEqual(paused["pending"]["candidateIds"], [0, 1])
        self.assertIsNone(next(o for o in paused["world"]["objects"] if o["id"] == 0)["color"])
        self.assertEqual(self.snapshots(), 4)
        for action, body in [("clear", None), ("chat", {"text": "#8 red."})]:
            self.assertEqual(self.client.post(f"{self.base}/{action}", json=body).status_code, 409)
        with TestClient(create_app(self.settings)) as restarted:
            self.assertEqual(restarted.get(self.base).json()["pending"], paused["pending"])
            resumed = restarted.post(f"{self.base}/clarify", json={"objectId": 1}).json()
        self.assertIsNone(resumed["pending"])
        obj = next(o for o in resumed["world"]["objects"] if o["id"] == 1)
        self.assertEqual((obj["color"], obj["size"]), ("blue", "large"))
        self.assertEqual(self.snapshots(), 4)
        undone = self.client.post(f"{self.base}/undo").json()
        self.assertEqual(undone["world"], before["world"])
        self.assertIsNone(undone["pending"])
        # Undo restored the previous entry's most recent referent (#1).
        result = self.chat("It is green.")
        self.assertEqual(next(o for o in result["world"]["objects"] if o["id"] == 1)["color"], "green")

    def test_undo_pending_and_question_salience(self):
        self.chat("#0 red?")
        self.chat("#1 blue?")
        self.client.post(f"{self.base}/undo")
        result = self.chat("It is yellow.")
        self.assertEqual(next(o for o in result["world"]["objects"] if o["id"] == 0)["color"], "yellow")

    def test_invalid_choice_keeps_pending_and_no_new_snapshot(self):
        self.client.post(f"{self.base}/clear")
        before = self.chat("#0 cube. #1 cube.")
        paused = self.chat("The cube is blue.")
        count = self.snapshots()
        reply = self.client.post(f"{self.base}/clarify", json={"objectId": 99}).json()
        self.assertEqual(reply["pending"], paused["pending"])
        self.assertEqual(self.snapshots(), count)
        undone = self.client.post(f"{self.base}/undo").json()
        self.assertEqual(undone["world"], before["world"])
        self.assertIsNone(undone["pending"])
        self.assertEqual(self.client.post(f"{self.base}/clarify", json={"objectId": 0}).status_code, 409)

    def test_repeated_clarifications_stay_in_one_undo_unit(self):
        self.client.post(f"{self.base}/clear")
        before = self.chat("#0 cube. #1 cube. #2 sphere. #3 sphere.")
        first = self.chat("The cube is blue. The sphere is green.")
        count = self.snapshots()
        second = self.client.post(f"{self.base}/clarify", json={"objectId": 0}).json()
        self.assertIsNotNone(second["pending"])
        self.assertCountEqual(second["pending"]["candidateIds"], [2, 3])
        self.assertEqual(self.snapshots(), count)
        complete = self.client.post(f"{self.base}/clarify", json={"objectId": 2}).json()
        self.assertIsNone(complete["pending"])
        self.assertEqual(self.snapshots(), count)
        undone = self.client.post(f"{self.base}/undo").json()
        self.assertEqual(undone["world"], before["world"])

    def test_continuation_failure_rolls_back_world_salience_and_pending(self):
        self.client.post(f"{self.base}/clear")
        self.chat("#0 cube. #1 cube.")
        paused = self.chat("The cube is blue.")
        with Database(self.path).connection() as connection:
            connection.execute("""CREATE TRIGGER reject_continuation BEFORE UPDATE ON world_snapshots
                BEGIN SELECT RAISE(ABORT, 'continuation rejected'); END;""")
        with self.assertRaises(sqlite3.IntegrityError):
            self.client.post(f"{self.base}/clarify", json={"objectId": 0})
        loaded = self.client.get(self.base).json()
        for field in ("world", "pending", "messages"):
            self.assertEqual(loaded[field], paused[field])

    def test_visual_revision_purges_properties_and_undo_restores_salience(self):
        self.chat("#0 red?")
        with Database(self.path).connection() as connection:
            before = connection.execute("SELECT salience_json FROM world_snapshots ORDER BY sequence DESC LIMIT 1").fetchone()[0]
        self.client.post(f"{self.base}/property", json={"position": {"x": 1, "y": 7}, "property": "blue"})
        with Database(self.path).connection() as connection:
            updated = connection.execute("SELECT salience_json FROM world_snapshots ORDER BY sequence DESC LIMIT 1").fetchone()[0]
        self.assertNotEqual(before, updated)
        self.client.post(f"{self.base}/undo")
        with Database(self.path).connection() as connection:
            restored = connection.execute("SELECT salience_json FROM world_snapshots ORDER BY sequence DESC LIMIT 1").fetchone()[0]
        self.assertEqual(restored, before)
