import copy
import json
import unittest

from app.agent_context import build_input, InputTooLong, MAX_INPUT_BYTES, MAX_OUTCOMES


def gui(feedback='Generation 1: 4 cells changed', **extra):
    return {'kind': 'engine_result', 'userText': None, 'translation': None,
            'isError': False, 'pending': False, 'feedback': feedback, **extra}


class AgentContextTests(unittest.TestCase):
    def test_small_payload_is_unchanged(self):
        events = [gui(), {'kind': 'undo', 'feedback': 'Undone'}]
        payload = json.loads(build_input('Hi.', {'cells': ['white'] * 256}, events))
        self.assertEqual(payload['outcomes'], events)
        self.assertNotIn('historySummary', payload)

    def test_thousand_visual_updates_fit_without_losing_current_world_or_request(self):
        world = {'cells': ['white', 'black'] * 128, 'generation': 1083}
        events = [gui(f'Generation {n}: 4 cells changed') for n in range(1083)]
        before = copy.deepcopy(events)
        encoded = build_input('Hi.', world, events)
        payload = json.loads(encoded)
        self.assertLessEqual(len(encoded.encode('utf-8')), MAX_INPUT_BYTES)
        self.assertEqual(payload['world'], world)
        self.assertEqual(payload['entry'], 'Hi.')
        self.assertEqual(len(payload['outcomes']), 1)
        self.assertEqual(payload['outcomes'][0]['count'], 1083)
        self.assertEqual(payload['outcomes'][0]['feedback'], events[-1]['feedback'])
        self.assertEqual(payload['historySummary']['coalescedGuiEvents'], 1083)
        self.assertEqual(payload['historySummary']['omittedEvents'], 0)
        self.assertEqual(events, before)

    def test_only_consecutive_successful_nonpending_gui_updates_coalesce(self):
        important = [
            {'kind': 'accepted', 'translation': 'Set color of A1 to black.'},
            {'kind': 'rejected', 'originalText': 'Make it blue'},
            {'kind': 'undo', 'feedback': 'Undone'},
            {'kind': 'world_loaded', 'slot': 1},
            {'kind': 'parser_rejection', 'feedback': 'Unsupported syntax'},
            gui(isError=True), gui(pending=True), gui(userText='Advance 1 generation.'),
        ]
        events = [gui(), gui(), *important, gui(), gui()]
        payload = json.loads(build_input('Hello', {}, events))
        self.assertEqual(payload['outcomes'][1:-1], important)
        self.assertEqual(payload['outcomes'][0]['count'], 2)
        self.assertEqual(payload['outcomes'][-1]['count'], 2)

    def test_recent_whole_events_retained_with_explicit_omission_counts(self):
        events = [{'kind': 'rejected', 'originalText': str(n)} for n in range(MAX_OUTCOMES + 20)]
        payload = json.loads(build_input('Try again', {}, events))
        self.assertEqual(payload['outcomes'], events[-MAX_OUTCOMES:])
        self.assertEqual(payload['historySummary']['omittedEvents'], 20)
        self.assertEqual(payload['historySummary']['omittedByKind'], {'rejected': 20})

    def test_single_oversized_event_is_omitted_not_cut_or_retried_forever(self):
        event = {'kind': 'accepted', 'translation': 'x' * MAX_INPUT_BYTES}
        clarification = {'turns': [{'question': 'Which color?', 'answer': 'Blue'}]}
        encoded = build_input('Hi.', {'cells': ['blue'] * 256}, [event], clarification)
        payload = json.loads(encoded)
        self.assertEqual(payload['outcomes'], [])
        self.assertEqual(payload['clarification'], clarification)
        self.assertEqual(payload['historySummary']['omittedByKind'], {'accepted': 1})
        self.assertLessEqual(len(encoded.encode('utf-8')), MAX_INPUT_BYTES)

    def test_byte_limit_preserves_newest_events_with_exact_programs(self):
        events = [{'kind': 'accepted', 'translation': 'Set color of A1 to black.',
                   'feedback': '\u00e1' * 5000} for _ in range(3)]
        encoded = build_input('Hi.', {}, events)
        payload = json.loads(encoded)
        self.assertEqual(payload['outcomes'], events[-1:])
        self.assertEqual(payload['historySummary']['omittedEvents'], 2)
        self.assertLessEqual(len(encoded.encode('utf-8')), MAX_INPUT_BYTES)

    def test_current_entry_world_and_clarification_are_never_truncated(self):
        for text, world, clarification in [
            ('x' * MAX_INPUT_BYTES, {}, None),
            ('Hi', {'cells': ['x' * MAX_INPUT_BYTES]}, None),
            ('Hi', {}, {'answer': 'x' * MAX_INPUT_BYTES}),
        ]:
            with self.subTest(world=bool(world), clarification=bool(clarification)):
                with self.assertRaises(InputTooLong):
                    build_input(text, world, [gui()], clarification)
