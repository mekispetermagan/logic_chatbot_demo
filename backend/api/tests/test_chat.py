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

    def test_chat_undo_prefix_restores_world_and_salience_ignores_suffix(self):
        before = self.chat("#0 red?")
        self.chat("#1 green. #1 large.")
        result = self.chat(" \tUnDo #99 red. ignored garbage?")
        self.assertEqual(result["world"], before["world"])
        self.assertEqual(result["feedback"], "Undone")
        self.assertEqual(result["messages"][-2]["text"], " \tUnDo #99 red. ignored garbage?")
        self.assertFalse(result["messages"][-1]["isError"])
        self.assertEqual(self.snapshots(), 2)
        referenced = self.chat("It is yellow.")
        self.assertEqual(next(o for o in referenced["world"]["objects"] if o["id"] == 0)["color"], "yellow")

    def test_chat_undo_preserves_initial_snapshot(self):
        for text in ("undo", "UNDOanything", "\n undo."):
            result = self.chat(text)
            self.assertEqual(result["world"], self.initial["world"])
            self.assertEqual(result["feedback"], "No change")
            self.assertFalse(result["canUndo"])
            self.assertEqual(self.snapshots(), 1)

    def test_chat_undo_cancels_pending_entry_and_prior_partial_updates(self):
        self.client.post(f"{self.base}/clear")
        before = self.chat("#0 cube. #1 cube.")
        paused = self.chat("#2 red. The cube is blue.")
        self.assertIsNotNone(paused["pending"])
        result = self.chat("  UNDO rest ignored")
        self.assertIsNone(result["pending"])
        self.assertEqual(result["world"], before["world"])
        self.assertEqual(result["feedback"], "Undone")
        self.assertEqual(self.snapshots(), 3)

    def test_chat_undo_rolls_back_if_feedback_cannot_be_saved(self):
        before = self.chat("#0 blue.")
        with Database(self.path).connection() as connection:
            connection.execute("""CREATE TRIGGER reject_undo_message BEFORE INSERT ON chat_messages
                BEGIN SELECT RAISE(ABORT, 'undo message rejected'); END;""")
        with self.assertRaises(sqlite3.IntegrityError):
            self.client.post(f"{self.base}/chat", json={"text": "undo"})
        loaded = self.client.get(self.base).json()
        self.assertEqual(loaded["world"], before["world"])
        self.assertEqual(loaded["messages"], before["messages"])
        self.assertEqual(self.snapshots(), 2)

    def test_layer3_square_choices_restart_resume_and_whole_entry_undo(self):
        self.client.post(f"{self.base}/clear")
        before = self.chat("#0 red cube on A1. #1 blue sphere on D4.")
        count = self.snapshots()
        paused = self.chat("#0 green. Move #0 next to #1. #0 large.")
        self.assertEqual(paused["pending"]["candidateIds"], [])
        self.assertEqual(len(paused["pending"]["squareChoices"]), 4)
        self.assertEqual(paused["pending"]["resolvedSubjects"], [0, 1])
        self.assertEqual(self.snapshots(), count + 1)
        invalid = self.client.post(f"{self.base}/clarify", json={"position": {"x": 7, "y": 7}})
        self.assertEqual(invalid.status_code, 200)
        self.assertEqual(invalid.json()["pending"], paused["pending"])
        with TestClient(create_app(self.settings)) as restarted:
            loaded = restarted.get(self.base).json()
            self.assertEqual(loaded["pending"], paused["pending"])
            selected = restarted.post(f"{self.base}/clarify", json={"position": {"x": 3, "y": 4}})
        self.assertEqual(selected.status_code, 200, selected.text)
        result = selected.json()
        self.assertIsNone(result["pending"])
        obj = next(o for o in result["world"]["objects"] if o["id"] == 0)
        self.assertEqual((obj["position"], obj["color"], obj["size"]), ({"x": 3, "y": 4}, "green", "large"))
        self.assertEqual(self.snapshots(), count + 1)
        restored = self.chat("undo")
        self.assertEqual(restored["world"], before["world"])
        referenced = self.chat("It remove color.")
        self.assertIsNone(next(o for o in referenced["world"]["objects"] if o["id"] == 1)["color"])

    def test_layer3_null_and_vacuous_answers_and_choice_validation(self):
        self.client.post(f"{self.base}/clear")
        self.chat("#0 cube. #1 sphere.")
        result = self.chat("#0 same color as #1? Is every red object a cube? Some red are cube? How many free?")
        self.assertFalse(result["messages"][-1]["isError"])
        self.assertIn("true — both lack color", result["feedback"])
        self.assertIn("true — no matching objects", result["feedback"])
        self.assertIn("false — no matching objects", result["feedback"])
        self.assertIn("\n  64", result["feedback"])
        rejected = self.chat("All red objects are cube?")
        self.assertTrue(rejected["messages"][-1]["isError"])
        self.assertEqual(rejected["world"], result["world"])
        for choice in [{}, {"objectId": 0, "position": {"x": 0, "y": 0}}, {"position": {"x": "0", "y": 0}}]:
            self.assertEqual(self.client.post(f"{self.base}/clarify", json=choice).status_code, 422)

    def test_attribute_removal_chat_and_whole_entry_undo(self):
        self.client.post(f"{self.base}/clear")
        before = self.chat("#0 red small cube on H7.")
        count = self.snapshots()
        result = self.chat("H7 remove color. It remove size. The cube remove shape. #0 remove square.")
        self.assertFalse(result["messages"][-1]["isError"])
        self.assertIsNone(result["pending"])
        self.assertEqual(result["world"]["objects"], [
            {"id": 0, "color": None, "size": None, "shape": None, "position": None}])
        self.assertIn("#0: red -> none", result["feedback"])
        self.assertEqual(self.snapshots(), count + 1)
        restored = self.chat("undo")
        self.assertEqual(restored["world"], before["world"])
        referenced = self.chat("The red cube remove color.")
        self.assertIsNone(referenced["pending"])
        self.assertIsNone(referenced["world"]["objects"][0]["color"])

    def test_structural_sequence_and_undo_restore_world_and_salience(self):
        self.client.post(f"{self.base}/clear")
        before = self.chat("#0 red cube on A1. #1 blue sphere on B1.")
        count = self.snapshots()
        result = self.chat("Swap #0 #1. Remove #0 from board. Erase #1. Position of #0?")
        self.assertIsNone(result["pending"])
        self.assertEqual(result["world"]["objects"], [
            {"id": 0, "color": "red", "shape": "cube", "size": None, "position": None}])
        self.assertIn("Swapped #0 and #1", result["feedback"])
        self.assertIn("Deleted #1", result["feedback"])
        self.assertIn("position of #0?\n  none", result["feedback"])
        self.assertEqual(self.snapshots(), count + 1)
        with Database(self.path).connection() as connection:
            import json
            ranking = json.loads(connection.execute(
                "SELECT salience_json FROM world_snapshots ORDER BY sequence DESC LIMIT 1").fetchone()[0])
        self.assertTrue(all(mention["objectId"] != 1 for mention in ranking))
        self.assertTrue(all(prop["kind"] != "position" for mention in ranking for prop in mention["properties"]))
        restored = self.chat("undo")
        self.assertEqual(restored["world"], before["world"])
        referenced = self.chat("It is green.")
        self.assertEqual(next(o for o in referenced["world"]["objects"] if o["id"] == 1)["color"], "green")

    def test_swap_placed_and_unplaced_then_both_unplaced(self):
        self.client.post(f"{self.base}/clear")
        self.chat("#0 red on A3. #1 blue.")
        result = self.chat("swap #0 and #1")
        objects = {o["id"]: o for o in result["world"]["objects"]}
        self.assertIsNone(objects[0]["position"])
        self.assertEqual(objects[1]["position"], {"x": 0, "y": 2})
        self.assertEqual(objects[0]["color"], "red")
        self.assertEqual(objects[1]["color"], "blue")
        result = self.chat("Remove #1. Swap #0 #1.")
        self.assertTrue(all(o["position"] is None for o in result["world"]["objects"]))
        self.assertIn("No change", result["feedback"])

    def test_swap_resolves_both_ambiguous_operands_across_restarts(self):
        self.client.post(f"{self.base}/clear")
        before = self.chat("#0 cube on A1. #1 cube on B1. #2 sphere on C1. #3 sphere on D1.")
        paused = self.chat("swap the cube and the sphere")
        self.assertCountEqual(paused["pending"]["candidateIds"], [0, 1])
        count = self.snapshots()
        second = self.client.post(f"{self.base}/clarify", json={"objectId": 0}).json()
        self.assertEqual(second["world"], before["world"])
        self.assertEqual(second["pending"]["resolvedSubjects"], [0])
        self.assertCountEqual(second["pending"]["candidateIds"], [2, 3])
        self.assertEqual(self.snapshots(), count)
        with TestClient(create_app(self.settings)) as restarted:
            loaded = restarted.get(self.base).json()
            self.assertEqual(loaded["pending"], second["pending"])
            result = restarted.post(f"{self.base}/clarify", json={"objectId": 2}).json()
        self.assertIsNone(result["pending"])
        objects = {o["id"]: o for o in result["world"]["objects"]}
        self.assertEqual(objects[0]["position"], {"x": 2, "y": 0})
        self.assertEqual(objects[2]["position"], {"x": 0, "y": 0})
        self.assertEqual(self.snapshots(), count)
        restored = self.client.post(f"{self.base}/undo").json()
        self.assertEqual(restored["world"], before["world"])

    def test_structural_failures_do_not_create_objects_or_partially_swap(self):
        before = self.chat("#99 red on A1.")
        result = self.chat("Swap #99 #999. Remove H8. Delete #999.")
        self.assertEqual(result["world"], before["world"])
        self.assertIn("No object", result["feedback"])
        rejected = self.chat("Remove #99?")
        self.assertTrue(rejected["messages"][-1]["isError"])
        self.assertEqual(rejected["world"], before["world"])
