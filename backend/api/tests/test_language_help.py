import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from fastapi.testclient import TestClient

from app.config import Settings
from app.engine import EngineUnavailable, LogicEngine
from app.main import create_app

EXE = Path(__file__).resolve().parents[2] / 'logic_engine/bin/logic-engine-editor'


class LanguageHelpTests(unittest.TestCase):
    def test_all_domains_serve_static_examples_without_world_or_google_access(self):
        with tempfile.TemporaryDirectory() as root:
            app = create_app(Settings(database_path=Path(root)/'state.sqlite3', engine_path=EXE))
            with TestClient(app) as client:
                calendar = Mock(spec=[])
                app.state.calendar = calendar
                before = app.state.calendar_dialogue.read()
                for domain in ('objects', 'network', 'cellular', 'calendar'):
                    response = client.get(f'/languages/{domain}/examples')
                    self.assertEqual(response.status_code, 200, response.text)
                    body = response.json()
                    self.assertEqual(body['domain'], domain)
                    self.assertEqual(body['languageVersion'], domain + ('-v1' if domain == 'calendar' else '-v2'))
                    self.assertEqual([s['title'] for s in body['sections']], [
                        'Primitive commands', 'Primitive questions', 'Conceptual commands', 'Conceptual questions'])
                    for section in body['sections']:
                        self.assertTrue(section['examples'])
                        for segments in section['examples']:
                            self.assertTrue(segments)
                            self.assertTrue(all(isinstance(segment['reference'], bool) for segment in segments))
                            sentence = ''.join(segment['text'] for segment in segments)
                            self.assertNotIn('[[', sentence)
                            self.assertNotIn('unspecified', sentence)
                            self.assertIn(sentence[-1], '.?')
                    references = [segment['text'] for section in body['sections'] for example in section['examples'] for segment in example if segment['reference']]
                    self.assertIn('it', references)
                    self.assertTrue(any(text.startswith('the ') for text in references))
                    self.assertEqual(client.get(f'/languages/{domain}/examples').json(), body)
                self.assertEqual(app.state.calendar_dialogue.read(), before)
                self.assertEqual(calendar.mock_calls, [])
                self.assertEqual(client.get('/languages/unknown/examples').status_code, 422)

    def test_examples_transport_never_sends_a_world_or_edit(self):
        body = {'domain':'calendar', 'languageVersion':'calendar-v1', 'sections':[
            {'title':title, 'examples':[[{'text':'Does '}, {'text':'#3', 'reference':True}, {'text':' exist?'}]]} for title in
            ['Primitive commands', 'Primitive questions', 'Conceptual commands', 'Conceptual questions']]}
        with patch('app.engine.subprocess.run', return_value=subprocess.CompletedProcess([], 0, json.dumps(body), '')) as run:
            LogicEngine(EXE).examples('calendar')
        self.assertEqual(json.loads(run.call_args.kwargs['input']), {'domain':'calendar', 'action':{'type':'examples'}})

    def test_unavailable_or_mismatched_engine_is_an_explicit_failure(self):
        for result in ('{}', '{"domain":"objects"}', 'not json'):
            with self.subTest(result=result), patch('app.engine.subprocess.run', return_value=subprocess.CompletedProcess([], 0, result, '')):
                with self.assertRaises(EngineUnavailable):
                    LogicEngine(EXE).examples('calendar')
