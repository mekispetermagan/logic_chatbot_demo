"""Offline verification of live-comparison accounting and independent checks."""
from pathlib import Path
import sys
import json
import tempfile
import unittest
from unittest.mock import MagicMock,patch

TOOLS=Path(__file__).resolve().parents[1]/'tools'
sys.path.insert(0,str(TOOLS))
from calendar_comparison import normalize,event_answer,isolated_settings,cleanup,LABEL
from calendar_comparison_check import outcome,usage

class ComparisonChecks(unittest.TestCase):
    def event(self,identifier='a',start='09:00',end='09:45',title='Team meeting',color='5'):
        return {'id':identifier,'summary':title,'colorId':color,
                'start':{'dateTime':f'2026-10-30T{start}:00+01:00'},
                'end':{'dateTime':f'2026-10-30T{end}:00+01:00'}}
    def test_repeated_turn_usage_is_counted_once(self):
        turn={'session_id':'s','id':'t','usage':{'input_tokens':10,'output_tokens':2,'total_tokens':12,
              'input_tokens_details':{'cached_tokens':4},'output_tokens_details':{'reasoning_tokens':1}}}
        self.assertEqual(usage([turn,turn]),{'turns':1,'input_tokens':10,'output_tokens':2,
                         'total_tokens':12,'cached_tokens':4,'reasoning_tokens':1})
    def test_missing_usage_is_not_zero(self):
        with self.assertRaises(ValueError):usage([{'session_id':'s','id':'t','usage':None}])
    def test_wrong_duration_is_detected(self):
        initial=[self.event(),self.event('b','11:00','11:30','Mechanic','10')]
        final=[*initial,self.event('c','09:45','10:40','Videoconference','10')]
        self.assertFalse(outcome(1,initial,final)['finalStateMatches'])
    def test_preserves_existing_identities(self):
        initial=[self.event(),self.event('b','11:00','11:30','Mechanic','10')]
        final=[{**initial[0],'id':'replacement'},initial[1],self.event('c','09:45','10:45','Videoconference','10')]
        result=outcome(1,initial,final)
        self.assertTrue(result['finalStateMatches']);self.assertFalse(result['originalIdentitiesPreserved'])
    def test_changed_starting_duration_cannot_be_hidden(self):
        a=normalize([self.event('a','11:00','11:15','Mechanic','10')])
        b=normalize([self.event('a','11:00','11:30','Mechanic','10')])
        self.assertNotEqual(a,b)

    def test_event_choice_uses_identity_mapping_not_list_order(self):
        initial=[self.event('morning'),self.event('afternoon','14:00','14:30')]
        state={'status':'clarify','eventHandles':{'morning':1,'afternoon':0},
               'question':{'key':'subject','options':[['#0',0],['#1',1]]}}
        self.assertEqual(event_answer(state,initial,'14:00'),
                         {'type':'answer','key':'subject','value':0})

    def test_runner_rejects_primary_calendar_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory)
            (folder/'calendar.json').write_text(json.dumps({'id':'logic.engine.demo@gmail.com'}))
            with self.assertRaisesRegex(RuntimeError,'primary calendar'):
                isolated_settings(folder)

    def test_acknowledged_cleanup_only_retries_reads(self):
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory)
            (folder/'calendar.json').write_text(json.dumps({'id':'isolated@group.calendar.google.com',
                'summary':LABEL+'test','deletionAcknowledged':True}))
            for name in ['oauth-client.json','tokens.json']:(folder/name).write_text('{}')
            client=MagicMock();client.__enter__.return_value=client
            client.get.side_effect=[MagicMock(status_code=200),MagicMock(status_code=404)]
            with patch('calendar_comparison.google_client',return_value=client),patch('time.sleep'):
                cleanup(folder)
            client.delete.assert_not_called()
            self.assertEqual(client.get.call_count,2)
            self.assertIn('deletedAt',json.loads((folder/'calendar.json').read_text()))
            self.assertFalse((folder/'tokens.json').exists())
