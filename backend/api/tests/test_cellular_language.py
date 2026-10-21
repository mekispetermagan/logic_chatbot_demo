"""Cellular chat uses the real engine, persistence and shared continuation API."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.config import Settings, INITIAL_WORLD_PATHS
from app.database import Database
from app.main import create_app
from app.schemas import CellularWorld
from app.engine import LogicEngine
from app.agent_instructions import configuration_for


class CellularLanguageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / 'chat.sqlite3'
        self.settings = Settings(database_path=self.path, openai_api_key='')
        self.client = TestClient(create_app(self.settings))
        self.client.__enter__()
        self.addCleanup(self.client.__exit__, None, None, None)
        self.initial = self.client.post('/conversations', json={'domain': 'cellular'}).json()
        self.base = '/conversations/' + self.initial['conversationId']

    def post(self, action, body=None):
        response = self.client.post(self.base + '/' + action, json=body)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def chat(self, text):
        return self.post('chat', {'text': text})

    def snapshot(self):
        with Database(self.path).connection() as db:
            return dict(db.execute('SELECT * FROM world_snapshots WHERE conversation_id=? ORDER BY sequence DESC LIMIT 1',
                                   (self.initial['conversationId'],)).fetchone())

    def test_multi_sentence_entry_and_undo_restore_world_and_salience(self):
        first = self.chat('Set color of P16 to black. What is the color of it?')
        self.assertFalse(first['messages'][-1]['isError'])
        self.assertEqual(first['world']['cells'][-1], 'black')
        self.assertIn('P16', first['feedback'])
        stored = self.snapshot()
        self.assertEqual(stored['sequence'], 1)
        self.assertEqual(json.loads(stored['salience_json'])[0]['position'], {'x': 15, 'y': 15})
        with TestClient(create_app(self.settings)) as restarted:
            answer = restarted.post(self.base + '/chat', json={'text': 'Set color of it to white.'}).json()
            self.assertEqual(answer['world']['cells'][-1], 'white')
        self.assertEqual(self.post('undo')['world'], first['world'])
        self.assertEqual(self.snapshot()['salience_json'], stored['salience_json'])
        self.assertEqual(self.chat('Undo.')['world'], self.initial['world'])
        self.assertEqual(json.loads(self.snapshot()['salience_json']), [])

    def test_syntax_error_rejects_entire_entry(self):
        state = self.chat('Set color of A1 to black. Advance 1 generation')
        self.assertTrue(state['messages'][-1]['isError'])
        self.assertEqual(state['world'], self.initial['world'])
        self.assertEqual(self.snapshot()['sequence'], 0)

    def test_cell_choice_replay_is_one_undo_unit_after_restart(self):
        pending = self.chat('Set color of cells [O16, P16] to black. Set color of it to white.')
        self.assertIsNotNone(pending['pending'])
        self.assertEqual(pending['pending']['squareChoices'], [{'x': 14, 'y': 15}, {'x': 15, 'y': 15}])
        self.assertEqual(self.snapshot()['sequence'], 1)
        with TestClient(create_app(self.settings)) as restarted:
            continued = restarted.post(self.base + '/clarify', json={'position': {'x': 15, 'y': 15}})
            self.assertEqual(continued.status_code, 200, continued.text)
            resolved = continued.json()
        self.assertIsNone(resolved['pending'])
        self.assertEqual(resolved['world']['cells'][-2:], ['black', 'white'])
        self.assertIn('P16', resolved['messages'][-2]['text'])
        self.assertEqual(self.snapshot()['sequence'], 1)
        self.assertEqual(self.post('undo')['world'], self.initial['world'])

    def test_boolean_grouping_precedes_all_effects(self):
        state = self.chat('Set color of A1 to black. Does A1 satisfy color is black or color is white and row is 1?')
        self.assertEqual(state['world'], self.initial['world'])
        self.assertEqual(len(state['pending']['groupingChoices']), 2)
        selected = self.post('clarify', {'groupingId': 1})
        self.assertIsNone(selected['pending'])
        self.assertEqual(selected['world']['cells'][0], 'black')
        self.assertEqual(self.post('undo')['world'], self.initial['world'])

    def test_batch_pause_displays_provisional_cellular_world_and_rolls_back(self):
        state = self.chat('Atomically { Set color of cells [A1, B1] to black. Set color of it to white. }.')
        self.assertEqual(state['world'], self.initial['world'])
        self.assertEqual(state['pending']['stagedWorld']['cells'][:2], ['black', 'black'])
        continued = self.post('clarify', {'position': {'x': 0, 'y': 0}})
        self.assertEqual(continued['world']['cells'][:2], ['white', 'black'])
        self.assertEqual(self.post('undo')['world'], self.initial['world'])
        failed = self.chat('Atomically { Set color of A1 to black. Set color of B1 to red. }.')
        self.assertTrue(failed['messages'][-1]['isError'])
        self.assertEqual(failed['world'], self.initial['world'])

    def test_rule_change_and_advance_are_undone_together(self):
        state = self.chat('Disable rule for white. Advance 3 generations.')
        self.assertEqual(state['world']['generation'], 3)
        self.assertEqual(state['world']['rulesetRevision'], 2)
        self.assertFalse(state['world']['ruleset']['rules']['white']['enabled'])
        self.assertEqual(self.post('undo')['world'], self.initial['world'])

    def test_forecasts_and_stabilization_are_answers_not_mutations(self):
        self.chat('Set color of cells matching true to white. Set color of cells [H8, I8, J8] to black.')
        before = self.client.get(self.base).json()['world']
        state = self.chat('After 1 generation, which cells match color is black? What is the least return time of the board within 4 generations? Does the board reach a fixed point within 100 generations?')
        self.assertIn('[I7, I8, I9]', state['feedback'])
        self.assertIn('  2', state['feedback'])
        self.assertIn('false; no fixed point', state['feedback'])
        self.assertEqual(state['world'], before)

    def test_visual_edit_preserves_coordinate_but_purges_false_facts(self):
        self.chat('Set color of A1 to black. Does A1 satisfy neighbor count for color black is in [0]?')
        self.post('cell', {'position': {'x': 1, 'y': 0}, 'color': 'black'})
        ranking = json.loads(self.snapshot()['salience_json'])
        self.assertTrue(any(m['position'] == {'x': 0, 'y': 0} for m in ranking))
        self.assertFalse(any('NeighborCount' in p['value'] for m in ranking for p in m['properties']))
        state = self.chat('What is the color of it?')
        self.assertIn('Resolved A1', state['feedback'])
        self.assertFalse(state['messages'][-1]['isError'])

    def test_bounded_cell_count_reports_first_offset_without_mutating_world(self):
        prepared = self.chat('Set color of cells matching true to white. Set color of A1 to black.')
        state = self.chat('Does the count of cells matching color is black reach 0 within 70 generations?')
        self.assertFalse(state['messages'][-1]['isError'])
        self.assertIn('true; count reaches 0 at generation offset 1', state['feedback'])
        self.assertEqual(state['world'], prepared['world'])
        blank = self.chat('Set color of cells matching true to white.')
        already = self.chat('Does the count of cells matching color is black reach 0 within 70 generations?')
        self.assertIn('generation offset 0 (already matches)', already['feedback'])
        self.assertEqual(already['world'], blank['world'])
        invalid = self.chat('Set color of A1 to black. Does the count of cells matching true reach 257 within 70 generations?')
        self.assertTrue(invalid['messages'][-1]['isError'])
        self.assertEqual(invalid['world'], blank['world'])

    def test_bounded_count_reference_clarification_replays_and_undo_restores_context(self):
        self.chat('Set color of cells matching true to white.')
        self.post('cell', {'position': {'x': 0, 'y': 0}, 'color': 'black'})
        before = self.post('cell', {'position': {'x': 15, 'y': 15}, 'color': 'black'})
        previous_ranking = self.snapshot()['salience_json']
        state = self.chat('Does the count of cells matching color is white and same cell as the cell with color black reach 1 within 1 generation?')
        self.assertIsNotNone(state['pending'])
        self.assertEqual(state['pending']['squareChoices'], [{'x': 0, 'y': 0}, {'x': 15, 'y': 15}])
        self.assertEqual(state['world'], before['world'])
        completed = self.post('clarify', {'position': {'x': 15, 'y': 15}})
        self.assertIsNone(completed['pending'])
        self.assertIn('true; count reaches 1 at generation offset 1', completed['feedback'])
        self.assertEqual(completed['world'], before['world'])
        self.post('undo')
        self.assertEqual(self.snapshot()['salience_json'], previous_ranking)

    def test_cyclic_color_absence_is_not_reported_as_permanent(self):
        rules = ', '.join(f'{source}: target {target}, counts [0, 1, 2, 3, 4, 5, 6, 7, 8], enabled true'
                          for source, target in [('red', 'green'), ('green', 'blue'), ('blue', 'red')])
        prepared = self.chat(f'Replace ruleset with palette [red, green, blue], neighborhood moore, rules [{rules}], '
                             'randomly refilling the board if required. Set color of cells matching true to red.')
        state = self.chat('Does the count of cells matching color is red reach 0 within 3 generations? '
                          'After 3 generations, how many cells match color is red?')
        self.assertFalse(state['messages'][-1]['isError'])
        self.assertIn('true; count reaches 0 at generation offset 1', state['feedback'])
        self.assertIn('  256', state['feedback'])
        self.assertEqual(state['world'], prepared['world'])

    def test_component_count_and_seed_references(self):
        self.chat('Set color of cells matching true to white. Set color of cells [A1, P1] to black.')
        state = self.chat('How many cells match connected to A1? Does A1 satisfy connected to P1?')
        self.assertIn('  2', state['feedback'])
        self.assertIn('  true', state['feedback'])
        self.assertIsNone(state['pending'])

    def test_all_cellular_prompt_examples_parse_without_execution(self):
        world = CellularWorld.model_validate(json.loads(INITIAL_WORLD_PATHS['cellular'].read_text()))
        cases = json.loads((Path(__file__).resolve().parents[1] / 'prompts/examples.json').read_text())['cellular']
        self.assertGreater(len(cases), 100)
        engine = LogicEngine(self.settings.engine_path)
        for case in cases:
            result = engine.edit('cellular', world, {'type': 'checkSyntax', 'text': case['translation']})
            self.assertFalse(result.isError, result.feedback)
            self.assertEqual(result.world, world)
            self.assertEqual(result.salience, [])
        instructions = configuration_for('cellular')['instructions']
        self.assertIn('ACTIVE DOMAIN: cellular', instructions)
        self.assertIn('stabilization time', instructions)
        self.assertNotIn('## Network agent:', instructions)
        self.assertNotIn('## Objects agent:', instructions)


if __name__ == '__main__':
    unittest.main()
