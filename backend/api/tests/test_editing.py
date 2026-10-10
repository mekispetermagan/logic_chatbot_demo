import os
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from fastapi.testclient import TestClient

from app.config import ENGINE_PATH, Settings
from app.database import Database
from app.engine import EngineUnavailable, LogicEngine
from app.main import create_app
from app.schemas import World


class EditingTests(unittest.TestCase):
    """These tests call the real Haskell executable, built before running tests."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.database_path = Path(self.temporary.name) / "conversations.sqlite3"
        self.settings = Settings(database_path=self.database_path,
                                 engine_path=Path(os.environ.get("LOGIC_CHATBOT_ENGINE_PATH", str(ENGINE_PATH))))
        self.client = TestClient(create_app(self.settings))
        self.client.__enter__()
        self.addCleanup(self.client.__exit__, None, None, None)
        self.initial = self.client.post("/conversations").json()
        self.base = f'/conversations/{self.initial["conversationId"]}'

    def edit(self, action, body=None):
        response = self.client.post(f"{self.base}/{action}", json=body) if body is not None else self.client.post(f"{self.base}/{action}")
        self.assertEqual(response.status_code, 200, response.text)
        state = response.json()
        self.assertEqual(state["conversationId"], self.initial["conversationId"])
        self.assertIn("feedback", state)
        return state

    def snapshots(self):
        with Database(self.database_path).connection() as connection:
            return connection.execute("SELECT count(*) FROM world_snapshots WHERE conversation_id = ?",
                                      (self.initial["conversationId"],)).fetchone()[0]

    def test_all_four_shape_properties_use_canonical_transport_names(self):
        for index, shape in enumerate(["bloom", "spark", "drop", "loop"]):
            with self.subTest(shape=shape):
                result = self.edit("property", {"position": {"x": index, "y": 0}, "property": shape})
                obj = next(o for o in result["world"]["objects"] if o["position"] == {"x": index, "y": 0})
                self.assertEqual(obj["shape"], shape)
        for shape in ["cube", "sphere", "pyramid", "flower", "star", "tear", "ring"]:
            response = self.client.post(f"{self.base}/property", json={"position": {"x": 0, "y": 0}, "property": shape})
            self.assertEqual(response.status_code, 422)

    def test_property_creation_addition_revision_and_no_op(self):
        action = {"position": {"x": 0, "y": 0}, "property": "red"}
        created = self.edit("property", action)
        objects = created["world"]["objects"]
        new = next(value for value in objects if value["position"] == action["position"])
        self.assertEqual(new, {"id": 7, "position": action["position"], "color": "red", "size": None, "shape": None})
        self.assertTrue(created["canUndo"])
        self.assertEqual(self.snapshots(), 2)
        repeated = self.edit("property", action)
        self.assertEqual(repeated["feedback"], "No change")
        self.assertEqual(self.snapshots(), 2)
        self.edit("property", {**action, "property": "small"})
        revised = self.edit("property", {**action, "property": "blue"})
        new = next(value for value in revised["world"]["objects"] if value["id"] == 7)
        self.assertEqual((new["color"], new["size"], new["shape"]), ("blue", "small", None))
        self.assertEqual(self.snapshots(), 4)
        loaded = self.client.get(self.base).json()
        self.assertEqual(loaded["world"], revised["world"])

    def test_missing_properties_are_added_without_replacing_objects(self):
        for identifier, prop in [(2, "green"), (3, "spark"), (4, "small")]:
            previous = next(value for value in self.initial["world"]["objects"] if value["id"] == identifier)
            updated = self.edit("property", {"position": previous["position"], "property": prop})
            value = next(value for value in updated["world"]["objects"] if value["id"] == identifier)
            field = {2: "color", 3: "shape", 4: "size"}[identifier]
            self.assertEqual(value, {**previous, field: prop})

    def test_placement_preserves_object_and_blocked_actions_do_not_add_history(self):
        source = next(value for value in self.initial["world"]["objects"] if value["id"] == 5)
        occupied = self.initial["world"]["objects"][0]["position"]
        blocked = self.edit("place", {"objectId": 5, "position": occupied})
        self.assertEqual(blocked["world"], self.initial["world"])
        self.assertIn("occupied", blocked["feedback"])
        self.assertEqual(self.snapshots(), 1)
        destination = {"x": 0, "y": 0}
        placed = self.edit("place", {"objectId": 5, "position": destination})
        value = next(value for value in placed["world"]["objects"] if value["id"] == 5)
        self.assertEqual(value, {**source, "position": destination})
        self.edit("place", {"objectId": 5, "position": {"x": 1, "y": 0}})
        self.edit("place", {"objectId": 999, "position": {"x": 1, "y": 0}})
        self.assertEqual(self.snapshots(), 2)

    def test_erase_clear_and_undo_preserve_initial_snapshot(self):
        self.edit("erase", {"position": {"x": 0, "y": 0}})
        self.assertEqual(self.snapshots(), 1)
        position = self.initial["world"]["objects"][0]["position"]
        erased = self.edit("erase", {"position": position})
        self.assertEqual(len(erased["world"]["objects"]), 6)
        cleared = self.edit("clear")
        self.assertEqual(cleared["world"]["objects"], [])
        self.edit("clear")
        self.assertEqual(self.snapshots(), 3)
        self.assertEqual(self.edit("undo")["world"], erased["world"])
        restored = self.edit("undo")
        self.assertEqual(restored["world"], self.initial["world"])
        self.assertFalse(restored["canUndo"])
        self.assertEqual(self.edit("undo")["feedback"], "No change")
        self.assertEqual(self.snapshots(), 1)
        self.edit("property", {"position": {"x": 0, "y": 0}, "property": "yellow"})
        self.assertEqual(self.snapshots(), 2)

    def test_bounds_are_checked_by_engine(self):
        for action, body in [
            ("property", {"position": {"x": -1, "y": 0}, "property": "red"}),
            ("place", {"objectId": 5, "position": {"x": 8, "y": 0}}),
            ("erase", {"position": {"x": 0, "y": 8}}),
        ]:
            result = self.edit(action, body)
            self.assertEqual(result["feedback"], "Outside board")
            self.assertEqual(result["world"], self.initial["world"])
        self.assertEqual(self.snapshots(), 1)

    def test_structural_validation_and_missing_conversations(self):
        for action, body in [
            ("property", {"position": {"x": 0, "y": 0}, "property": "purple"}),
            ("property", {"position": {"x": True, "y": 0}, "property": "red"}),
            ("place", {"objectId": -1, "position": {"x": 0, "y": 0}}),
            ("erase", {"position": {"x": 0}}),
        ]:
            self.assertEqual(self.client.post(f"{self.base}/{action}", json=body).status_code, 422)
        for action, body in [
            ("property", {"position": {"x": 0, "y": 0}, "property": "red"}),
            ("place", {"objectId": 5, "position": {"x": 0, "y": 0}}),
            ("erase", {"position": {"x": 0, "y": 0}}), ("clear", {}), ("undo", {}),
        ]:
            self.assertEqual(self.client.post(f"/conversations/{uuid4()}/{action}", json=body).status_code, 404)

    def test_history_survives_restart_and_other_conversations_are_unchanged(self):
        other = self.client.post("/conversations").json()
        changed = self.edit("clear")
        with TestClient(create_app(self.settings)) as restarted:
            self.assertEqual(restarted.get(self.base).json()["world"], changed["world"])
            self.assertEqual(restarted.post(f"{self.base}/undo").json()["world"], self.initial["world"])
        self.assertEqual(self.client.get(f'/conversations/{other["conversationId"]}').json(), other)

    def test_engine_failure_does_not_change_history_and_undo_does_not_need_engine(self):
        self.edit("clear")
        with patch("app.engine.subprocess.run", side_effect=FileNotFoundError()):
            failed = self.client.post(f"{self.base}/clear")
            self.assertEqual(failed.status_code, 503)
            self.assertEqual(self.snapshots(), 2)
            restored = self.edit("undo")
            self.assertEqual(restored["world"], self.initial["world"])

    def test_failed_snapshot_insert_rolls_back_edit(self):
        with Database(self.database_path).connection() as connection:
            connection.execute("""
                CREATE TRIGGER reject_edit BEFORE INSERT ON world_snapshots
                BEGIN SELECT RAISE(ABORT, 'snapshot rejected'); END;
            """)
        with self.assertRaises(sqlite3.IntegrityError):
            self.client.post(f"{self.base}/clear")
        self.assertEqual(self.snapshots(), 1)
        self.assertEqual(self.client.get(self.base).json(), self.initial)


class EngineTransportTests(unittest.TestCase):
    def test_timeout_process_failure_and_invalid_response(self):
        engine = LogicEngine(Path("/unused/engine"))
        world = World(width=8, height=8, objects=[])
        for error in [subprocess.TimeoutExpired("engine", 5), subprocess.CalledProcessError(1, "engine")]:
            with patch("app.engine.subprocess.run", side_effect=error):
                with self.assertRaises(EngineUnavailable):
                    engine.edit(world, {"type": "clear"})
        with patch("app.engine.subprocess.run", return_value=subprocess.CompletedProcess([], 0, stdout='{}')):
            with self.assertRaises(EngineUnavailable):
                engine.edit(world, {"type": "clear"})
