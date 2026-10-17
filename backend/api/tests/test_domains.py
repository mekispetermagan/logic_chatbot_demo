import json
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from app.config import Settings, INITIAL_WORLD_PATHS
from app.database import Database
from app.main import create_app


class DomainIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "conversations.sqlite3"
        self.settings = Settings(database_path=self.path)

    def test_clear_chat_aliases_persist_and_undo_world_and_salience_in_both_domains(self):
        database = Database(self.path)
        for domain in ('objects', 'network'):
            for alias in ('clear the world', 'clear everything', 'CLEAR ALL.'):
                with self.subTest(domain=domain, alias=alias):
                    with TestClient(create_app(self.settings)) as client:
                        state = client.post('/conversations', json={'domain': domain}).json()
                        conversation_id = state['conversationId']
                        base = '/conversations/' + conversation_id
                        previous = client.post(base + '/chat', json={'text': '#99 green. #0 red?'}).json()
                        with database.connection() as connection:
                            ranking_before = json.loads(connection.execute(
                                'SELECT salience_json FROM world_snapshots WHERE conversation_id=? ORDER BY sequence DESC LIMIT 1',
                                (conversation_id,)).fetchone()[0])
                        response = client.post(base + '/chat', json={'text': alias})
                        self.assertEqual(response.status_code, 200, response.text)
                        cleared = response.json()
                        self.assertEqual(cleared['world']['objects'], [])
                        self.assertIn('clear the world.\n  World cleared', cleared['feedback'])
                        self.assertIsNone(cleared['pending'])
                        self.assertTrue(cleared['canUndo'])
                        with database.connection() as connection:
                            ranking_after = json.loads(connection.execute(
                                'SELECT salience_json FROM world_snapshots WHERE conversation_id=? ORDER BY sequence DESC LIMIT 1',
                                (conversation_id,)).fetchone()[0])
                            self.assertEqual(ranking_after, [])
                    with TestClient(create_app(self.settings)) as client:
                        self.assertEqual(client.get(base).json()['world'], cleared['world'])
                        restored = client.post(base + '/undo').json()
                        self.assertEqual(restored['world'], previous['world'])
                        with database.connection() as connection:
                            ranking_restored = json.loads(connection.execute(
                                'SELECT salience_json FROM world_snapshots WHERE conversation_id=? ORDER BY sequence DESC LIMIT 1',
                                (conversation_id,)).fetchone()[0])
                            self.assertEqual(ranking_restored, ranking_before)

    def test_shortest_connection_colors_persists_and_undo_restores_salience(self):
        database = Database(self.path)
        with TestClient(create_app(self.settings)) as client:
            state = client.post('/conversations', json={'domain': 'network'}).json()
            conversation_id = state['conversationId']
            base = '/conversations/' + conversation_id
            client.post(base + '/clear')
            previous = client.post(base + '/chat', json={'text': 'B1 red ew. #9 green.'}).json()
            with database.connection() as connection:
                previous_salience = connection.execute(
                    'SELECT salience_json FROM world_snapshots WHERE conversation_id=? ORDER BY sequence DESC LIMIT 1',
                    (conversation_id,)).fetchone()[0]
            response = client.post(base + '/chat', json={'text': 'Connect A1 to C1 with blue.'})
            self.assertEqual(response.status_code, 200, response.text)
            connected = response.json()
            self.assertIsNone(connected['pending'])
            placed = {tuple(node['position'].values()): node for node in connected['world']['objects']
                      if node['position'] is not None}
            self.assertEqual(set(placed), {(0, 0), (1, 0), (2, 0)})
            self.assertTrue(all(node['attributes']['color'] == 'blue' for node in placed.values()))
            self.assertEqual(placed[(1, 0)]['attributes'],
                             {'color': 'blue', 'east': 'east', 'west': 'west'})
            self.assertIn('2 steps', connected['feedback'])
        with TestClient(create_app(self.settings)) as client:
            self.assertEqual(client.get(base).json()['world'], connected['world'])
            restored = client.post(base + '/undo').json()
            self.assertEqual(restored['world'], previous['world'])
            with database.connection() as connection:
                restored_salience = connection.execute(
                    'SELECT salience_json FROM world_snapshots WHERE conversation_id=? ORDER BY sequence DESC LIMIT 1',
                    (conversation_id,)).fetchone()[0]
                self.assertEqual(json.loads(restored_salience), json.loads(previous_salience))

    def test_connection_clarification_creates_nothing_until_resumed_after_restart(self):
        with TestClient(create_app(self.settings)) as client:
            state = client.post('/conversations', json={'domain': 'network'}).json()
            base = '/conversations/' + state['conversationId']
            client.post(base + '/clear')
            previous = client.post(base + '/chat', json={'text': 'C1 red w. C3 red w.'}).json()
            response = client.post(base + '/chat', json={
                'text': 'H8 yellow. Connect A1 to the red with blue.'})
            self.assertEqual(response.status_code, 200, response.text)
            paused = response.json()
            self.assertEqual(set(paused['pending']['candidateIds']), {0, 1})
            self.assertEqual(len(paused['world']['objects']), 3)
        with TestClient(create_app(self.settings)) as client:
            self.assertEqual(client.get(base).json()['pending'], paused['pending'])
            response = client.post(base + '/clarify', json={'objectId': 0})
            self.assertEqual(response.status_code, 200, response.text)
            updated = response.json()
            self.assertIsNone(updated['pending'])
            self.assertEqual(len(updated['world']['objects']), 5)
            self.assertEqual(next(node for node in updated['world']['objects'] if node['id'] == 0)
                             ['attributes'], {'color': 'blue', 'west': 'west'})
            self.assertEqual(next(node for node in updated['world']['objects'] if node['id'] == 1)
                             ['attributes']['color'], 'red')
            self.assertEqual(client.post(base + '/undo').json()['world'], previous['world'])

    def test_network_edit_chat_undo_restart_and_domain_isolation(self):
        with TestClient(create_app(self.settings)) as client:
            network = client.post("/conversations", json={"domain": "network"}).json()
            objects = client.post("/conversations", json={"domain": "objects"}).json()
            self.assertEqual(network["domain"], "network")
            self.assertEqual(network["world"], json.loads(INITIAL_WORLD_PATHS["network"].read_text()))
            self.assertEqual(len(network["world"]["objects"]), 7)
            base = '/conversations/' + network["conversationId"]
            response = client.post(base + "/property", json={"position": {"x": 0, "y": 1},
                "property": {"attribute": "north", "value": "north"}})
            self.assertEqual(response.status_code, 200, response.text)
            edited = response.json()
            node = next(o for o in edited["world"]["objects"] if o["id"] == 7)
            self.assertEqual(node["attributes"], {"north": "north"})
            response = client.post(base + "/chat", json={"text":
                "A2 right. A2 yellow. A2 north? A2 remove up. A2 north? It east? color of it?"})
            self.assertEqual(response.status_code, 200, response.text)
            chatted = response.json()
            node = next(o for o in chatted["world"]["objects"] if o["id"] == 7)
            self.assertEqual(node["attributes"], {"east": "east", "color": "yellow"})
            self.assertIn("false", chatted["feedback"])
            self.assertIn("true", chatted["feedback"])
            for prop in ({"attribute": "shape", "value": "bloom"},
                         {"attribute": "north", "value": "up"},
                         {"attribute": "north", "value": "east"}):
                invalid = client.post(base + "/property", json={"position": {"x": 0, "y": 1}, "property": prop})
                self.assertEqual(invalid.status_code, 422)
                self.assertEqual(client.get(base).json()["world"], chatted["world"])
            restored = client.post(base + "/undo").json()
            self.assertEqual(restored["domain"], "network")
            self.assertEqual(restored["world"], edited["world"])
            self.assertEqual(client.get('/conversations/' + objects["conversationId"]).json(), objects)
            objects_reject = client.post('/conversations/' + objects["conversationId"] + '/property',
                json={"position": {"x": 0, "y": 0}, "property": {"attribute": "north", "value": "north"}})
            self.assertEqual(objects_reject.status_code, 422)
        with TestClient(create_app(self.settings)) as client:
            self.assertEqual(client.get(base).json()["world"], edited["world"])

    def test_legacy_migration_preserves_pending_messages_and_undo_salience(self):
        with TestClient(create_app(self.settings)) as client:
            created = client.post("/conversations", json={"domain": "objects"}).json()
            base = '/conversations/' + created["conversationId"]
            client.post(base + '/clear')
            previous = client.post(base + '/chat', json={"text": "#0 red bloom. #1 red bloom."}).json()
            paused = client.post(base + '/chat', json={"text": "#0 small. The red is blue."}).json()
            self.assertIsNotNone(paused["pending"])
        database = Database(self.path)
        with database.connection() as connection:
            rows = connection.execute('SELECT * FROM world_snapshots').fetchall()
            for row in rows:
                world = json.loads(row['world_json'])
                for obj in world['objects']:
                    attrs = obj.pop('attributes')
                    obj.update({name: attrs.get(name) for name in ('color', 'size', 'shape')})
                ranking = json.loads(row['salience_json'])
                for mention in ranking:
                    for prop in mention['properties']:
                        if prop['kind'] == 'attribute':
                            prop['kind'] = 'descriptor'
                            del prop['attribute']
                connection.execute('UPDATE world_snapshots SET world_json=?, salience_json=? WHERE conversation_id=? AND sequence=?',
                    (json.dumps(world), json.dumps(ranking), row['conversation_id'], row['sequence']))
            connection.execute('PRAGMA user_version=0')
        with TestClient(create_app(self.settings)) as client:
            loaded = client.get(base).json()
            self.assertEqual(loaded, {k: v for k, v in paused.items() if k not in ('feedback', 'preview')})
            continued = client.post(base + '/clarify', json={"objectId": 1})
            self.assertEqual(continued.status_code, 200, continued.text)
            self.assertIsNone(continued.json()['pending'])
            restored = client.post(base + '/undo').json()
            self.assertEqual(restored['world'], previous['world'])
            with database.connection() as connection:
                latest = connection.execute('SELECT salience_json FROM world_snapshots ORDER BY sequence DESC LIMIT 1').fetchone()[0]
                ranking = json.loads(latest)
                self.assertTrue(any(p['kind'] == 'attribute' for m in ranking for p in m['properties']))
        # Migration marker and encoding survive repeated startup unchanged.
        with TestClient(create_app(self.settings)) as client:
            self.assertEqual(client.get(base).json()['world'], previous['world'])
        with database.connection() as connection:
            self.assertEqual(connection.execute('PRAGMA user_version').fetchone()[0], 1)

    def test_network_clarification_survives_restart_and_undo_cancels_entry(self):
        with TestClient(create_app(self.settings)) as client:
            created = client.post("/conversations", json={"domain": "network"}).json()
            base = '/conversations/' + created['conversationId']
            empty = client.post(base + '/clear').json()
            response = client.post(base + '/chat', json={"text": "#0 north. #1 north. The north is red."})
            self.assertEqual(response.status_code, 200, response.text)
            paused = response.json()
            self.assertEqual(set(paused['pending']['candidateIds']), {0, 1})
        with TestClient(create_app(self.settings)) as client:
            self.assertEqual(client.get(base).json()['pending'], paused['pending'])
            reply = client.post(base + '/clarify', json={"objectId": 1})
            self.assertEqual(reply.status_code, 200, reply.text)
            objects = {obj['id']: obj for obj in reply.json()['world']['objects']}
            self.assertEqual(objects[0]['attributes'], {'north': 'north'})
            self.assertEqual(objects[1]['attributes'], {'north': 'north', 'color': 'red'})
            self.assertIsNone(reply.json()['pending'])
            restored = client.post(base + '/undo').json()
            self.assertEqual(restored['world'], empty['world'])
            self.assertEqual(restored['domain'], 'network')

    def test_failed_migration_rolls_back_world_and_salience_together(self):
        database = Database(self.path)
        database.initialize()
        with database.connection() as connection:
            connection.execute("INSERT INTO conversations (id, domain) VALUES ('legacy', 'objects')")
            world = {'width': 8, 'height': 8, 'objects': [
                {'id': 0, 'color': 'red', 'size': None, 'shape': None, 'position': None}]}
            good = [{'entry': 0, 'utterance': 0, 'objectId': 0,
                     'properties': [{'kind': 'descriptor', 'value': 'red'}]}]
            bad = [{'entry': 0, 'utterance': 0, 'objectId': 0,
                    'properties': [{'kind': 'descriptor', 'value': 'unrecognized-legacy-value'}]}]
            for sequence, salience in enumerate((good, bad)):
                connection.execute('INSERT INTO world_snapshots (conversation_id, sequence, world_json, salience_json) VALUES (?, ?, ?, ?)',
                    ('legacy', sequence, json.dumps(world), json.dumps(salience)))
            connection.execute('PRAGMA user_version=0')
            before = [tuple(row) for row in connection.execute('SELECT * FROM world_snapshots ORDER BY sequence')]
        with self.assertRaises(KeyError):
            database.initialize()
        with database.connection() as connection:
            self.assertEqual(connection.execute('PRAGMA user_version').fetchone()[0], 0)
            self.assertEqual([tuple(row) for row in connection.execute('SELECT * FROM world_snapshots ORDER BY sequence')], before)

    def test_ports_replace_preserves_color_and_undoes_in_one_step(self):
        with TestClient(create_app(self.settings)) as client:
            state = client.post('/conversations', json={'domain': 'network'}).json()
            base = '/conversations/' + state['conversationId']
            response = client.post(base + '/ports', json={'position': {'x': 0, 'y': 0}, 'ports': ['south', 'west']})
            self.assertEqual(response.status_code, 200, response.text)
            node = next(o for o in response.json()['world']['objects'] if o['id'] == 0)
            self.assertEqual(node['attributes'], {'color': 'red', 'south': 'south', 'west': 'west'})
            self.assertEqual(client.post(base + '/undo').json()['world'], state['world'])
            dot = client.post(base + '/ports', json={'position': {'x': 0, 'y': 0}, 'ports': []}).json()
            self.assertEqual(next(o for o in dot['world']['objects'] if o['id'] == 0)['attributes'], {'color': 'red'})
            client.post(base + '/undo')
            created = client.post(base + '/ports', json={'position': {'x': 0, 'y': 1}, 'ports': []}).json()
            self.assertEqual(next(o for o in created['world']['objects'] if o['id'] == 7)['attributes'], {})
            self.assertEqual(client.post(base + '/undo').json()['world'], state['world'])
            for ports in [['up'], ['north', 'north']]:
                self.assertEqual(client.post(base + '/ports', json={'position': {'x': 0, 'y': 0}, 'ports': ports}).status_code, 422)
            other = client.post('/conversations', json={'domain': 'objects'}).json()
            self.assertEqual(client.post('/conversations/' + other['conversationId'] + '/ports',
                json={'position': {'x': 0, 'y': 0}, 'ports': []}).status_code, 422)

    def test_network_graph_facts_restart_visual_purge_and_whole_entry_undo(self):
        with TestClient(create_app(self.settings)) as client:
            state = client.post('/conversations', json={'domain': 'network'}).json()
            conversation_id = state['conversationId']
            base = '/conversations/' + conversation_id
            empty = client.post(base + '/clear').json()
            response = client.post(base + '/chat', json={'text':
                'A1 red. Link A1 right. Is A1 an endpoint? '
                'Is A1 connected to B1 by a red path? How many components?'})
            self.assertEqual(response.status_code, 200, response.text)
            linked = response.json()
            self.assertIsNone(linked['pending'])
            self.assertIn('true', linked['feedback'])
            self.assertEqual(len(linked['world']['objects']), 2)
        database = Database(self.path)
        with database.connection() as connection:
            ranking = json.loads(connection.execute(
                'SELECT salience_json FROM world_snapshots WHERE conversation_id=? ORDER BY sequence DESC LIMIT 1',
                (conversation_id,)).fetchone()[0])
            self.assertTrue(any(p == {'kind': 'defined', 'value': 'endpoint'}
                                for mention in ranking for p in mention['properties']))
        with TestClient(create_app(self.settings)) as client:
            self.assertEqual(client.get(base).json()['world'], linked['world'])
            response = client.post(base + '/ports', json={'position': {'x': 1, 'y': 0}, 'ports': []})
            self.assertEqual(response.status_code, 200, response.text)
            with database.connection() as connection:
                ranking = json.loads(connection.execute(
                    'SELECT salience_json FROM world_snapshots WHERE conversation_id=? ORDER BY sequence DESC LIMIT 1',
                    (conversation_id,)).fetchone()[0])
                self.assertFalse(any(p.get('value') == 'endpoint'
                                     for mention in ranking for p in mention['properties']))
            self.assertEqual(client.post(base + '/undo').json()['world'], linked['world'])
            self.assertEqual(client.post(base + '/undo').json()['world'], empty['world'])

    def test_network_computed_clarification_restart_and_atomic_component_update(self):
        with TestClient(create_app(self.settings)) as client:
            state = client.post('/conversations', json={'domain': 'network'}).json()
            base = '/conversations/' + state['conversationId']
            client.post(base + '/clear')
            previous = client.post(base + '/chat', json={'text': 'A1 n. C1 n.'}).json()
            response = client.post(base + '/chat', json={'text':
                'Color the component of the tip red.'})
            self.assertEqual(response.status_code, 200, response.text)
            paused = response.json()
            self.assertEqual(set(paused['pending']['candidateIds']), {0, 1})
            self.assertEqual(paused['world'], previous['world'])
        with TestClient(create_app(self.settings)) as client:
            self.assertEqual(client.get(base).json()['pending'], paused['pending'])
            response = client.post(base + '/clarify', json={'objectId': 1})
            self.assertEqual(response.status_code, 200, response.text)
            updated = response.json()
            self.assertIsNone(updated['pending'])
            nodes = {node['id']: node for node in updated['world']['objects']}
            self.assertNotIn('color', nodes[0]['attributes'])
            self.assertEqual(nodes[1]['attributes']['color'], 'red')
            self.assertEqual(client.post(base + '/undo').json()['world'], previous['world'])
