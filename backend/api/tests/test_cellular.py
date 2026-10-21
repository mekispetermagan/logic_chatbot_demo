import copy
import json
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.config import ENGINE_PATH, INITIAL_WORLD_PATHS, Settings
from app.database import Database
from app.engine import EngineInvalidRequest, LogicEngine
from app.main import create_app
from app.schemas import CellularRuleset, CellularWorld, World, world_from_json


class CellularTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / 'cellular.sqlite3'
        self.settings = Settings(database_path=self.path, openai_api_key='')
        self.app = create_app(self.settings)
        self.client = TestClient(self.app)
        self.client.__enter__()
        self.addCleanup(self.client.__exit__, None, None, None)
        self.initial = self.client.post('/conversations', json={'domain': 'cellular'}).json()
        self.base = '/conversations/' + self.initial['conversationId']

    def post(self, action, body=None, base=None):
        response = self.client.post((base or self.base) + '/' + action, json=body)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def snapshots(self):
        with Database(self.path).connection() as connection:
            return connection.execute('SELECT COUNT(*) FROM world_snapshots WHERE conversation_id=?',
                                      (self.initial['conversationId'],)).fetchone()[0]

    def test_initial_world_contract_and_known_first_glider_generation(self):
        initial = self.initial
        self.assertEqual(initial['world'], json.loads(INITIAL_WORLD_PATHS['cellular'].read_text()))
        self.assertEqual(initial['languageVersion'], 'cellular-v2')
        self.assertEqual(initial['nextObjectId'], 0)
        self.assertFalse(initial['canUndo'])
        self.assertEqual(initial['world']['cells'].count('black'), 5)
        stepped = self.post('step')
        expected = {(7, 8), (9, 8), (8, 7), (9, 7), (8, 6)}
        live = {(i % 16, i // 16) for i, color in enumerate(stepped['world']['cells']) if color == 'black'}
        self.assertEqual(live, expected)
        self.assertEqual(stepped['changedCells'], 4)
        self.assertEqual(stepped['world']['generation'], 1)
        self.assertEqual(stepped['world']['ruleset'], initial['world']['ruleset'])
        self.assertEqual(stepped['world']['rulesetRevision'], 1)
        self.assertTrue(stepped['canUndo'])
        self.assertEqual(self.snapshots(), 2)
        self.assertIsNone(stepped['pending'])
        self.assertEqual(stepped['messages'], [])

    def test_four_generations_translate_glider_and_restart_undo_and_slots_preserve_everything(self):
        self.post('slots/1/save', {})
        old_live = {i for i, color in enumerate(self.initial['world']['cells']) if color == 'black'}
        for _ in range(4):
            stepped = self.post('step')
        expected = {((i % 16 + 1) % 16) + 16 * ((i // 16 - 1) % 16) for i in old_live}
        self.assertEqual({i for i, color in enumerate(stepped['world']['cells']) if color == 'black'}, expected)
        self.assertEqual(stepped['world']['generation'], 4)
        self.assertEqual(self.snapshots(), 5)
        with TestClient(create_app(self.settings)) as restarted:
            self.assertEqual(restarted.get(self.base).json()['world'], stepped['world'])
            self.assertEqual(restarted.post(self.base + '/undo').json()['world']['generation'], 3)
            self.assertEqual(restarted.post(self.base + '/slots/1/load').json()['world'], self.initial['world'])
            self.assertEqual(restarted.post(self.base + '/undo').json()['world']['generation'], 3)

    def test_generic_six_color_four_neighbor_rules_are_stored_and_evaluated(self):
        world = CellularWorld.model_validate({
            'cells': ['red'] * 256,
            'generation': 12, 'rulesetRevision': 7,
            'ruleset': {'palette': ['white', 'black', 'red', 'green', 'blue', 'yellow'], 'neighborhood': 4,
                        'rules': {'red': {'targetColor': 'blue', 'neighborColor': 'red', 'counts': [4]}}}})
        identifier = uuid4()
        self.app.state.conversation_service.repository.create(identifier, world, 'cellular')
        base = '/conversations/' + str(identifier)
        result = self.post('step', base=base)
        self.assertEqual(result['world']['cells'], ['blue'] * 256)
        self.assertEqual(result['changedCells'], 256)
        self.assertEqual(result['world']['generation'], 13)
        self.assertEqual(result['world']['rulesetRevision'], 7)
        self.post('slots/4/save', {}, base=base)
        stable = self.post('step', base=base)
        self.assertEqual(stable['changedCells'], 0)
        self.assertEqual(stable['world']['generation'], 14)
        self.assertEqual(self.post('undo', base=base)['world'], result['world'])
        self.assertEqual(self.post('slots/4/load', base=base)['world'], result['world'])

    def test_step_only_uses_persisted_state_and_never_calls_llm(self):
        with patch.object(self.app.state.conversation_service.translator, 'translate',
                          side_effect=AssertionError('Step must not call an LLM')):
            self.assertEqual(self.client.post(self.base + '/step', json={
                'steps': 100, 'world': {'cells': ['black'] * 256}}).status_code, 422)
            result = self.post('step')
        self.assertEqual(result['world']['generation'], 1)
        self.assertEqual(result['changedCells'], 4)
        for llm in (False, True):
            response = self.client.post(self.base + '/chat', json={'text': 'Step.', 'useLlm': llm})
            self.assertEqual(response.status_code, 200, response.text)
            self.assertTrue(response.json()['messages'][-1]['isError'])
            self.assertEqual(response.json()['world'], result['world'])
        self.assertEqual(self.snapshots(), 2)

    def test_other_domains_and_unimplemented_cellular_actions_are_isolated(self):
        for domain in ('objects', 'network'):
            other = self.client.post('/conversations', json={'domain': domain}).json()
            base = '/conversations/' + other['conversationId']
            self.assertIn('objects', other['world'])
            self.assertEqual(self.client.post(base + '/step').status_code, 422)
            self.assertEqual(self.client.get(base).json(), other)
        for action, body in [('clear', None), ('erase', {'position': {'x': 0, 'y': 0}}),
                             ('property', {'position': {'x': 0, 'y': 0},
                                           'property': {'attribute': 'color', 'value': 'red'}})]:
            self.assertEqual(self.client.post(self.base + '/' + action, json=body).status_code, 422)
        self.assertEqual(self.client.post(f'/conversations/{uuid4()}/step').status_code, 404)
        self.assertEqual(self.snapshots(), 1)

    def test_engine_errors_and_persistence_failures_do_not_commit_a_generation(self):
        with patch.object(self.app.state.conversation_service.engine, 'executable', Path('/missing/engine')):
            self.assertEqual(self.client.post(self.base + '/step').status_code, 503)
        self.assertEqual(self.snapshots(), 1)
        with Database(self.path).connection() as connection:
            connection.execute('''CREATE TRIGGER reject_step BEFORE INSERT ON world_snapshots
                                  BEGIN SELECT RAISE(ABORT, 'step rejected'); END''')
        with self.assertRaises(sqlite3.IntegrityError):
            self.post('step')
        self.assertEqual(self.client.get(self.base).json()['world'], self.initial['world'])
        self.assertEqual(self.snapshots(), 1)

    def test_full_reset_uses_valid_life_preset_and_keeps_saved_setups(self):
        advanced = self.post('step')
        self.post('slots/2/save', {})
        self.post('chat', {'text': 'full reset'})
        self.assertEqual(self.client.post(self.base + '/step').status_code, 409)
        self.assertEqual(self.client.post(self.base + '/cell', json={
            'position': {'x': 0, 'y': 0}, 'color': 'black'}).status_code, 409)
        reset = self.post('chat', {'text': 'yes'})
        self.assertEqual(reset['world'], self.initial['world'])
        self.assertFalse(reset['canUndo'])
        new_base = '/conversations/' + reset['conversationId']
        self.assertEqual(self.post('slots/2/load', base=new_base)['world'], advanced['world'])

    def test_cell_painting_noops_undo_slots_and_restart_preserve_generation(self):
        advanced = self.post('step')
        with patch.object(self.app.state.conversation_service.translator, 'translate',
                          side_effect=AssertionError('Painting must not call an LLM')):
            painted = self.post('cell', {'position': {'x': 15, 'y': 15}, 'color': 'black'})
        expected = copy.deepcopy(advanced['world'])
        expected['cells'][255] = 'black'
        self.assertEqual(painted['world'], expected)
        self.assertEqual(painted['changedCells'], 1)
        self.assertEqual(painted['feedback'], 'P16: white -> black')
        self.assertEqual(painted['messages'], [])
        self.assertEqual(self.snapshots(), 3)
        same = self.post('cell', {'position': {'x': 15, 'y': 15}, 'color': 'black'})
        self.assertEqual(same['changedCells'], 0)
        self.assertEqual(same['feedback'], 'No change')
        self.assertEqual(self.snapshots(), 3)
        self.post('slots/1/save', {})
        erased = self.post('cell', {'position': {'x': 15, 'y': 15}, 'color': 'white'})
        self.assertEqual(erased['world'], advanced['world'])
        with TestClient(create_app(self.settings)) as restarted:
            self.assertEqual(restarted.get(self.base).json()['world'], advanced['world'])
            self.assertEqual(restarted.post(self.base + '/undo').json()['world'], expected)
            self.assertEqual(restarted.post(self.base + '/slots/1/load').json()['world'], expected)

    def test_painting_rejects_inactive_colors_bad_coordinates_and_other_domains(self):
        for color, x, y in [('red', 0, 0), ('purple', 0, 0), ('black', -1, 0),
                            ('black', 0, -1), ('black', 16, 0), ('black', 0, 16),
                            ('black', True, 0), ('black', 1.5, 0)]:
            with self.subTest(color=color, x=x, y=y):
                result = self.client.post(self.base + '/cell', json={
                    'position': {'x': x, 'y': y}, 'color': color})
                self.assertEqual(result.status_code, 422, result.text)
        self.assertEqual(self.client.post(self.base + '/cell', json={
            'position': {'x': 0, 'y': 0}, 'color': 'black', 'generation': 99}).status_code, 422)
        self.assertEqual(self.client.get(self.base).json()['world'], self.initial['world'])
        self.assertEqual(self.snapshots(), 1)
        for domain in ('objects', 'network'):
            other = self.client.post('/conversations', json={'domain': domain}).json()
            base = '/conversations/' + other['conversationId']
            self.assertEqual(self.client.post(base + '/cell', json={
                'position': {'x': 0, 'y': 0}, 'color': 'red'}).status_code, 422)
            self.assertEqual(self.client.get(base).json(), other)
        self.assertEqual(self.client.post(f'/conversations/{uuid4()}/cell', json={
            'position': {'x': 0, 'y': 0}, 'color': 'white'}).status_code, 404)

    def test_painting_supports_all_six_active_colors(self):
        value = copy.deepcopy(self.initial['world'])
        colors = ['white', 'black', 'red', 'green', 'blue', 'yellow']
        value['ruleset']['palette'] = colors
        value['generation'] = 12
        identifier = uuid4()
        self.app.state.conversation_service.repository.create(identifier, CellularWorld.model_validate(value), 'cellular')
        base = '/conversations/' + str(identifier)
        for color in colors:
            result = self.post('cell', {'position': {'x': 0, 'y': 0}, 'color': color}, base=base)
            self.assertEqual(result['world']['cells'][0], color)
            self.assertEqual(result['world']['generation'], 12)
            self.assertEqual(result['world']['ruleset'], value['ruleset'])


class CellularModelTests(unittest.TestCase):
    def setUp(self):
        self.world = json.loads(INITIAL_WORLD_PATHS['cellular'].read_text())

    def test_all_palette_sizes_modes_and_count_sets_are_representable(self):
        colors = ['white', 'black', 'red', 'green', 'blue', 'yellow']
        for size in range(2, 7):
            for neighbors in (4, 8):
                active = colors[:size]
                ruleset = CellularRuleset.model_validate({
                    'palette': active, 'neighborhood': neighbors,
                    'rules': {source: {'targetColor': active[(i + 1) % size], 'neighborColor': source,
                                       'counts': list(range(neighbors + 1)), 'enabled': i % 2 == 0}
                              for i, source in enumerate(active)}})
                self.assertEqual(len(ruleset.rules), size)
                self.assertEqual(CellularRuleset.model_validate_json(ruleset.model_dump_json()), ruleset)
        self.assertIsInstance(world_from_json('cellular', json.dumps(self.world)), CellularWorld)
        self.assertIsInstance(world_from_json('objects', INITIAL_WORLD_PATHS['objects'].read_text()), World)

    def test_invalid_boards_palettes_rules_and_counts_are_rejected_by_models_and_haskell(self):
        variants = []
        def variant(change):
            value = copy.deepcopy(self.world)
            change(value)
            variants.append(value)
        variant(lambda w: w.update(cells=w['cells'][:-1]))
        variant(lambda w: w.update(width=9))
        variant(lambda w: w.update(topology='bounded'))
        variant(lambda w: w.update(generation=-1))
        variant(lambda w: w.update(rulesetRevision=0))
        variant(lambda w: w['cells'].__setitem__(0, 'red'))
        variant(lambda w: w['cells'].__setitem__(0, 'purple'))
        variant(lambda w: w['ruleset'].update(palette=['white']))
        variant(lambda w: w['ruleset'].update(palette=['white', 'white']))
        variant(lambda w: w['ruleset'].update(neighborhood=6))
        variant(lambda w: w['ruleset']['rules']['white'].update(targetColor='white'))
        variant(lambda w: w['ruleset']['rules']['white'].update(neighborColor='red'))
        variant(lambda w: w['ruleset']['rules']['white'].update(counts=[-1]))
        variant(lambda w: w['ruleset']['rules']['white'].update(counts=[9]))
        variant(lambda w: w['ruleset']['rules']['white'].update(counts=[3, 3]))
        variant(lambda w: w['ruleset'].update(neighborhood=4))
        for value in variants:
            with self.subTest(value=value):
                with self.assertRaises(ValidationError):
                    CellularWorld.model_validate(value)
                response = subprocess.run([str(ENGINE_PATH)], input=json.dumps({
                    'domain': 'cellular', 'world': value, 'action': {'type': 'step'}}),
                    text=True, capture_output=True, timeout=5)
                self.assertEqual(response.returncode, 2, response.stdout + response.stderr)
        engine = LogicEngine(ENGINE_PATH)
        with self.assertRaises(EngineInvalidRequest):
            engine.edit('cellular', CellularWorld.model_validate(self.world), {'type': 'step'},
                        next_object_id=1)


if __name__ == '__main__':
    unittest.main()
