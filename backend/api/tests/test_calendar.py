import asyncio
import contextlib
import json
import tempfile
import unittest
from dataclasses import replace
from datetime import datetime
from pathlib import Path
from unittest.mock import AsyncMock, Mock, patch

from fastapi.testclient import TestClient
from mcp import types
from mcp.shared.exceptions import McpError

from app.calendar_mcp import CalendarError, CalendarMcp, READ_TOOLS, WRITE_TOOLS
from app.calendar_events import CreateEvent
from app.config import Settings
from app.main import create_app

SCHEMAS = json.loads((Path(__file__).parent / 'fixtures/calendar_mcp_tools.json').read_text())
START = datetime.fromisoformat('2026-10-26T00:00:00+01:00')
END = datetime.fromisoformat('2026-11-02T00:00:00+01:00')
CREATE = {'summary': 'Disposable demo test',
          'start': {'dateTime': '2026-10-29T09:00:00+01:00', 'timeZone': 'Europe/Budapest'},
          'end': {'dateTime': '2026-10-29T10:00:00+01:00', 'timeZone': 'Europe/Budapest'}}


def result(data=None, error=None, structured=False):
    return types.CallToolResult(
        content=[types.TextContent(type='text', text=error if error else json.dumps(data))],
        structuredContent=data if structured else None, isError=error is not None)


class CalendarTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.credentials, self.tokens, self.server = root / 'oauth.json', root / 'tokens.json', root / 'index.js'
        self.credentials.write_text(json.dumps({'installed': {'client_id': 'fake', 'client_secret': 'secret-never-echo'}}))
        self.tokens.write_text('{}')
        self.server.touch()
        self.settings = Settings(database_path=root / 'app.sqlite3', calendar_enabled=True,
                                 calendar_mcp_path=self.server, google_oauth_credentials=self.credentials,
                                 calendar_token_path=self.tokens)
        self.adapter = CalendarMcp(self.settings)
        self.session = AsyncMock()
        self.session.__aenter__.return_value = self.session
        self.session.list_tools.return_value = types.ListToolsResult(
            tools=[types.Tool(name=name, inputSchema=schema) for name, schema in SCHEMAS.items() if name in READ_TOOLS])
        self.session.call_tool.return_value = result({'calendars': []})
        self.opened, self.closed = 0, 0
        self.parameters = None

        @contextlib.asynccontextmanager
        async def transport(parameters, errlog):
            self.parameters = parameters
            self.opened += 1
            try:
                yield object(), object()
            finally:
                self.closed += 1

        for target, value in [('app.calendar_mcp.stdio_client', transport),
                              ('app.calendar_mcp.ClientSession', lambda *a, **kw: self.session),
                              ('app.calendar_mcp.shutil.which', lambda path: '/fake/node')]:
            patcher = patch(target, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    async def test_calendar_discovery_is_read_only_and_child_environment_is_isolated(self):
        calendars = [{'id': self.settings.calendar_id, 'summary': 'Demo', 'timeZone': 'Europe/Budapest'}]
        self.session.call_tool.return_value = result({'calendars': calendars}, structured=True)
        with patch.dict('os.environ', {'OPENAI_API_KEY': 'do-not-inherit'}):
            reply = await self.adapter.calendars()
        self.assertEqual(reply['calendars'], calendars)
        self.assertEqual(self.parameters.args[-1], ','.join(READ_TOOLS))
        self.assertNotIn('OPENAI_API_KEY', self.parameters.env)
        self.assertEqual(self.parameters.env['GOOGLE_ACCOUNT_MODE'], 'demo')
        self.session.call_tool.assert_awaited_once_with('list-calendars', {'account': 'demo'})
        self.assertEqual((self.opened, self.closed), (1, 1))

    async def test_events_preserve_all_day_and_recurring_representations(self):
        events = [
            {'id': 'all-day', 'start': {'date': '2026-10-27'}, 'end': {'date': '2026-10-28'}},
            {'id': 'instance', 'recurringEventId': 'series',
             'originalStartTime': {'dateTime': '2026-10-27T09:00:00+01:00', 'timeZone': 'Europe/Budapest'},
             'start': {'dateTime': '2026-10-27T09:00:00+01:00', 'timeZone': 'Europe/Budapest'},
             'end': {'dateTime': '2026-10-27T10:00:00+01:00', 'timeZone': 'Europe/Budapest'}},
            {'id': 'cancelled-instance', 'status': 'cancelled', 'recurringEventId': 'series'},
        ]
        self.session.call_tool.return_value = result({'events': events})
        reply = await self.adapter.events(START, END, 'Europe/Budapest')
        self.assertEqual(reply['events'], events)
        arguments = self.session.call_tool.call_args.args[1]
        self.assertEqual(arguments['calendarId'], 'logic.engine.demo@gmail.com')
        self.assertEqual(arguments['timeMin'], START.isoformat())

    async def test_empty_events_and_freebusy(self):
        self.session.call_tool.return_value = result({'events': []})
        self.assertEqual((await self.adapter.events(START, END, 'Europe/Budapest'))['totalCount'], 0)
        self.session.call_tool.return_value = result({'calendars': {self.settings.calendar_id: {'busy': []}}})
        self.assertEqual((await self.adapter.freebusy(START, END, 'Europe/Budapest'))['busy'], [])

    async def test_upstream_authorization_and_wrapped_errors_are_non_sensitive(self):
        self.session.call_tool.return_value = result(error='invalid_grant secret-never-echo refresh_token=secret')
        with self.assertRaises(CalendarError) as caught:
            await self.adapter.calendars()
        self.assertEqual(caught.exception.status_code, 503)
        self.assertIn('Reauthorize', str(caught.exception))
        self.assertNotIn('secret', str(caught.exception))
        self.session.initialize.side_effect = ExceptionGroup('SDK group', [McpError(types.ErrorData(
            code=-32600, message='No valid account tokens secret-never-echo'))])
        with self.assertRaises(CalendarError) as caught:
            await self.adapter.calendars()
        self.assertIn('Reauthorize', str(caught.exception))
        self.assertEqual(self.closed, 2)

    async def test_provider_error_invalid_json_and_invalid_shapes(self):
        for reply in (result(error='upstream failure secret-never-echo'),
                      types.CallToolResult(content=[types.TextContent(type='text', text='not json')]),
                      result({'calendars': [None]})):
            self.session.call_tool.return_value = reply
            with self.assertRaises(CalendarError) as caught:
                await self.adapter.calendars()
            self.assertNotIn('secret', str(caught.exception))
        self.assertEqual(self.opened, self.closed)

    async def test_freebusy_error_is_not_reported_as_available(self):
        self.session.call_tool.return_value = result({'calendars': {self.settings.calendar_id: {
            'errors': [{'reason': 'forbidden'}], 'busy': []}}})
        with self.assertRaises(CalendarError) as caught:
            await self.adapter.freebusy(START, END, 'Europe/Budapest')
        self.assertEqual(caught.exception.status_code, 502)

    async def test_missing_tools_or_incompatible_schema_prevent_invocation(self):
        self.session.list_tools.return_value = types.ListToolsResult(tools=[])
        with self.assertRaises(CalendarError):
            await self.adapter.calendars()
        self.session.call_tool.assert_not_awaited()
        self.session.list_tools.return_value = types.ListToolsResult(tools=[types.Tool(
            name=name, inputSchema={'type': 'object', 'required': ['newRequiredArgument']}) for name in READ_TOOLS])
        with self.assertRaises(CalendarError):
            await self.adapter.calendars()
        self.session.call_tool.assert_not_awaited()

    async def test_paginated_discovery(self):
        self.session.list_tools.side_effect = [
            types.ListToolsResult(tools=[types.Tool(name='list-calendars', inputSchema=SCHEMAS['list-calendars'])], nextCursor='next'),
            types.ListToolsResult(tools=[types.Tool(name=name, inputSchema=SCHEMAS[name]) for name in READ_TOOLS[1:]])]
        await self.adapter.calendars()
        self.session.list_tools.assert_any_await(cursor='next')

    async def test_timeout_closes_subprocess(self):
        async def delay():
            await asyncio.sleep(1)
        self.session.initialize.side_effect = delay
        self.adapter.timeout = 0.01
        with self.assertRaises(CalendarError) as caught:
            await self.adapter.calendars()
        self.assertEqual(caught.exception.status_code, 504)
        self.assertEqual((self.opened, self.closed), (1, 1))

    async def test_startup_failure_is_sanitized(self):
        self.session.initialize.side_effect = OSError('secret-never-echo')
        with self.assertRaises(CalendarError) as caught:
            await self.adapter.calendars()
        self.assertEqual(caught.exception.status_code, 503)
        self.assertNotIn('secret', str(caught.exception))

    async def test_missing_credentials_tokens_or_configuration_do_not_spawn(self):
        for settings in (replace(self.settings, calendar_enabled=False),
                         replace(self.settings, google_oauth_credentials=None),
                         replace(self.settings, calendar_token_path=self.tokens.parent / 'missing'),
                         replace(self.settings, calendar_mcp_path=None)):
            with self.assertRaises(CalendarError):
                await CalendarMcp(settings).calendars()
        self.credentials.write_text('invalid secret-never-echo')
        with self.assertRaises(CalendarError) as caught:
            await self.adapter.calendars()
        self.assertNotIn('secret', str(caught.exception))
        self.assertEqual(self.opened, 0)

    async def test_arbitrary_tools_are_rejected(self):
        with self.assertRaises(CalendarError):
            await self.adapter._read('create-event', {})
        with self.assertRaises(CalendarError):
            await self.adapter._read('manage-accounts', {'action': 'remove'})
        self.assertEqual(self.opened, 0)

    def enable_writes(self):
        self.adapter = CalendarMcp(replace(self.settings, calendar_writes_enabled=True))
        self.session.list_tools.return_value = types.ListToolsResult(
            tools=[types.Tool(name=name, inputSchema=schema) for name, schema in SCHEMAS.items()])

    async def test_create_update_delete_cycle_uses_fixed_calendar_and_verifies_each_change(self):
        self.enable_writes()
        stored = {}

        async def provider(tool, arguments):
            self.assertEqual(arguments['calendarId'], 'logic.engine.demo@gmail.com')
            self.assertEqual(arguments['account'], 'demo')
            identifier = arguments['eventId']
            if tool == 'get-event':
                return result({'event': stored[identifier]}) if identifier in stored else result(error='404 Not Found')
            self.assertEqual(arguments['sendUpdates'], 'none')
            if tool == 'delete-event':
                del stored[identifier]
                return result({'success': True, 'eventId': identifier, 'calendarId': self.settings.calendar_id})
            event = stored.setdefault(identifier, {'id': identifier, 'calendarId': self.settings.calendar_id})
            for name in ('summary', 'description', 'location', 'start', 'end', 'colorId'):
                if name in arguments:
                    event[name] = json.loads(arguments[name]) if name in ('start', 'end') else arguments[name]
            return result({'event': event})

        self.session.call_tool.side_effect = provider
        for body in (CREATE, {**CREATE, 'start': {'date': '2026-10-29'}, 'end': {'date': '2026-10-30'}}):
            created = await self.adapter.create_event(CreateEvent(**body).tool_fields())
            identifier = created['event']['id']
            self.assertRegex(identifier, r'^[a-f0-9]{32}$')
            self.assertTrue(created['verified'])
            self.assertEqual(created['event']['start'], body['start'])
            updated = await self.adapter.update_event(identifier, {'summary': 'Changed', 'location': '', 'colorId': '11'})
            self.assertEqual(updated['event']['summary'], 'Changed')
            self.assertEqual(updated['event']['colorId'], '11')
            self.assertTrue(updated['verified'])
            deleted = await self.adapter.delete_event(identifier)
            self.assertTrue(deleted['deleted'])
            self.assertTrue(deleted['verified'])
        self.assertEqual([call.args[0] for call in self.session.call_tool.await_args_list],
                         ['create-event', 'get-event', 'get-event', 'update-event', 'get-event',
                          'get-event', 'delete-event', 'get-event'] * 2)
        self.assertEqual(self.parameters.args[-1], ','.join(READ_TOOLS + WRITE_TOOLS))
        self.assertEqual(self.opened, self.closed)

    async def test_writes_disabled_or_non_demo_calendar_never_invoke_provider(self):
        for settings in (self.settings, replace(self.settings, calendar_writes_enabled=True,
                                               calendar_id='personal@example.com')):
            adapter = CalendarMcp(settings)
            for method, arguments in ((adapter.create_event, ({'summary': 'x'},)),
                                      (adapter.update_event, ('event', {'summary': 'x'})),
                                      (adapter.delete_event, ('event',))):
                with self.assertRaises(CalendarError) as caught:
                    await method(*arguments)
                self.assertEqual(caught.exception.status_code, 403)
        self.assertEqual(self.opened, 0)

    async def test_no_account_calendar_or_invitation_overrides(self):
        self.enable_writes()
        for extra in ({'calendarId': 'personal'}, {'account': 'personal'}, {'attendees': []}, {'eventId': 'another'}):
            with self.assertRaises(CalendarError):
                await self.adapter.create_event({'summary': 'x', **extra})
        self.assertEqual(self.opened, 0)

    async def test_recurring_events_require_explicit_scope_before_update_or_delete(self):
        self.enable_writes()
        for recurring in ({'recurrence': ['RRULE:FREQ=DAILY']}, {'recurringEventId': 'series'},
                          {'originalStartTime': {'date': '2026-10-29'}}):
            self.session.call_tool.return_value = result({'event': {'id': 'event', **recurring}})
            for method, arguments in ((self.adapter.update_event, ('event', {'summary': 'Changed'})),
                                      (self.adapter.delete_event, ('event',))):
                with self.assertRaises(CalendarError) as caught:
                    await method(*arguments)
                self.assertEqual(caught.exception.status_code, 409)
        self.assertTrue(all(call.args[0] == 'get-event' for call in self.session.call_tool.await_args_list))

    async def test_write_timeout_reports_unknown_outcome_and_id_without_retry(self):
        self.enable_writes()
        self.adapter.timeout = 0.01

        async def delayed_write(tool, arguments):
            await asyncio.sleep(1)
        self.session.call_tool.side_effect = delayed_write
        with self.assertRaises(CalendarError) as caught:
            await self.adapter.create_event(CreateEvent(**CREATE).tool_fields())
        self.assertEqual(caught.exception.status_code, 504)
        self.assertTrue(caught.exception.outcome_unknown)
        self.assertEqual(caught.exception.event_id, self.session.call_tool.call_args.args[1]['eventId'])
        self.assertEqual(self.session.call_tool.await_count, 1)
        self.assertEqual(self.opened, self.closed)

    async def test_failure_before_dispatch_is_not_reported_as_uncertain_write(self):
        self.enable_writes()
        self.session.initialize.side_effect = OSError('secret-never-echo')
        with self.assertRaises(CalendarError) as caught:
            await self.adapter.create_event(CreateEvent(**CREATE).tool_fields())
        self.assertFalse(caught.exception.outcome_unknown)
        self.session.call_tool.assert_not_awaited()

    async def test_mismatching_readback_does_not_report_verified_success(self):
        self.enable_writes()
        self.session.call_tool.side_effect = lambda tool, arguments: result({'event': {
            'id': arguments['eventId'], 'summary': 'Unexpected', 'start': CREATE['start'], 'end': CREATE['end']}})
        with self.assertRaises(CalendarError) as caught:
            await self.adapter.create_event(CreateEvent(**CREATE).tool_fields())
        self.assertTrue(caught.exception.outcome_unknown)
        self.assertEqual(caught.exception.status_code, 409)

    async def test_delete_requires_absence_not_a_failed_readback(self):
        self.enable_writes()
        self.session.call_tool.side_effect = [result({'event': {'id': 'event'}}),
                                             result({'success': True, 'eventId': 'event', 'calendarId': self.settings.calendar_id}),
                                             result(error='OAuth invalid_grant secret-never-echo')]
        with self.assertRaises(CalendarError) as caught:
            await self.adapter.delete_event('event')
        self.assertTrue(caught.exception.outcome_unknown)
        self.assertNotIn('secret', str(caught.exception))

    async def test_event_lookup_preserves_not_found_and_rejects_wrong_id(self):
        self.session.call_tool.return_value = result(error='404 Not Found')
        with self.assertRaises(CalendarError) as caught:
            await self.adapter.event('event')
        self.assertEqual(caught.exception.status_code, 404)
        self.session.call_tool.return_value = result({'event': {'id': 'other'}})
        with self.assertRaises(CalendarError) as caught:
            await self.adapter.event('event')
        self.assertEqual(caught.exception.status_code, 502)


class CalendarRouteTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.app = create_app(Settings(database_path=Path(temporary.name) / 'test.sqlite3'))
        self.client = TestClient(self.app, client=('127.0.0.1', 50000))
        self.client.__enter__()
        self.addCleanup(self.client.__exit__, None, None, None)
        self.adapter = AsyncMock()
        self.adapter.require_writes = Mock()
        self.app.state.calendar = self.adapter
        self.query = {'timeMin': START.isoformat(), 'timeMax': END.isoformat(), 'timeZone': 'Europe/Budapest'}

    def test_valid_read_routes(self):
        self.adapter.calendars.return_value = {'calendars': []}
        self.adapter.events.return_value = {'events': []}
        self.adapter.freebusy.return_value = {'busy': []}
        for suffix in ('calendars', 'events', 'freebusy'):
            response = self.client.get('/calendar/' + suffix, params=self.query if suffix != 'calendars' else {})
            self.assertEqual(response.status_code, 200, response.text)
            if suffix != 'events':
                self.assertEqual(self.client.post('/calendar/' + suffix, json={}).status_code, 405)
        self.adapter.events.assert_awaited_once_with(START, END, 'Europe/Budapest')

    def test_invalid_and_naive_intervals_never_invoke_mcp(self):
        for changes in ({'timeMax': START.isoformat()}, {'timeMin': END.isoformat(), 'timeMax': START.isoformat()},
                        {'timeMin': '2026-10-26T00:00:00'}, {'timeZone': 'Not/AZone'}, {'timeMin': 'bad'}):
            for suffix in ('events', 'freebusy'):
                response = self.client.get('/calendar/' + suffix, params={**self.query, **changes})
                self.assertEqual(response.status_code, 422, response.text)
        self.adapter.events.assert_not_awaited()
        self.adapter.freebusy.assert_not_awaited()

    def test_remote_clients_are_rejected(self):
        with TestClient(self.app, client=('203.0.113.8', 50000)) as remote:
            self.assertEqual(remote.get('/calendar/calendars').status_code, 403)

    def test_disabled_integration_leaves_existing_application_available(self):
        self.app.state.calendar = CalendarMcp(Settings(database_path=Path('unused')))
        self.assertEqual(self.client.get('/calendar/calendars').status_code, 503)
        response = self.client.post('/conversations', json={'domain': 'objects'})
        self.assertEqual(response.status_code, 201)

    def test_sanitized_error_status_is_preserved(self):
        self.adapter.events.side_effect = CalendarError('Calendar MCP request timed out.', 504)
        response = self.client.get('/calendar/events', params=self.query)
        self.assertEqual(response.status_code, 504)
        self.assertEqual(response.json()['detail'], 'Calendar MCP request timed out.')

    def test_create_update_delete_and_lookup_routes(self):
        self.adapter.create_event.return_value = {'event': {'id': 'event'}, 'verified': True}
        self.adapter.update_event.return_value = {'event': {'id': 'event'}, 'verified': True}
        self.adapter.delete_event.return_value = {'eventId': 'event', 'deleted': True, 'verified': True}
        self.adapter.event.return_value = {'event': {'id': 'event'}}
        self.assertEqual(self.client.post('/calendar/events', json=CREATE).status_code, 201)
        self.assertEqual(self.client.patch('/calendar/events/event', json={'summary': 'Changed'}).status_code, 200)
        self.assertEqual(self.client.delete('/calendar/events/event').status_code, 200)
        self.assertEqual(self.client.get('/calendar/events/event').status_code, 200)
        self.adapter.create_event.assert_awaited_once_with(CreateEvent(**CREATE).tool_fields())
        self.adapter.update_event.assert_awaited_once_with('event', {'summary': 'Changed'})
        self.adapter.delete_event.assert_awaited_once_with('event')

    def test_invalid_create_and_update_payloads_never_invoke_provider(self):
        bad_creates = [
            {**CREATE, 'start': CREATE['end']},
            {**CREATE, 'start': {'dateTime': '2026-10-29T09:00:00'}},
            {**CREATE, 'start': {'dateTime': 0}},
            {**CREATE, 'start': {'date': '2026-10-29T00:00:00'}},
            {**CREATE, 'start': {'dateTime': '2026-10-29T09:00:00+03:00', 'timeZone': 'Europe/Budapest'}},
            {**CREATE, 'start': {'dateTime': '2026-10-29T09:00:00+01:00', 'timeZone': 'Not/AZone'}},
            {**CREATE, 'start': {'date': '2026-10-29'}},
            {**CREATE, 'start': {'date': '2026-10-29', 'dateTime': CREATE['start']['dateTime']}},
            {**CREATE, 'start': {'date': '2026-10-29', 'timeZone': 'Europe/Budapest'}},
            {**CREATE, 'calendarId': 'personal'}, {**CREATE, 'attendees': []},
            {**CREATE, 'recurrence': ['RRULE:FREQ=DAILY']},
            {**CREATE, 'start': {'date': '2026-10-29'}, 'end': {'date': '2026-10-29'}},
        ]
        for body in bad_creates:
            response = self.client.post('/calendar/events', json=body)
            self.assertEqual(response.status_code, 422, (body, response.text))
        for body in ({}, {'summary': None}, {'location': None}, {'start': CREATE['start']},
                     {'account': 'personal'}, {'end': CREATE['end']}, {'sendUpdates': 'all'}):
            response = self.client.patch('/calendar/events/event', json=body)
            self.assertEqual(response.status_code, 422, response.text)
        self.adapter.create_event.assert_not_awaited()
        self.adapter.update_event.assert_not_awaited()

    def test_color_and_partial_text_updates_preserve_omitted_fields(self):
        self.adapter.create_event.return_value = {'event': {'id': 'event'}, 'verified': True}
        self.adapter.update_event.return_value = {'event': {'id': 'event'}, 'verified': True}
        self.assertEqual(self.client.post('/calendar/events', json={**CREATE, 'colorId': '2'}).status_code, 201)
        self.assertEqual(self.adapter.create_event.call_args.args[0]['colorId'], '2')
        for body in ({'colorId': '11'}, {'description': ''}, {'location': 'Meeting room 2'}):
            self.assertEqual(self.client.patch('/calendar/events/event', json=body).status_code, 200)
            self.assertEqual(self.adapter.update_event.call_args.args, ('event', body))
        for value in (None, '', '0', '12', 2, '#ff0000'):
            self.assertEqual(self.client.patch('/calendar/events/event', json={'colorId': value}).status_code, 422)

    def test_writes_default_disabled_and_remote_writes_denied(self):
        self.app.state.calendar = CalendarMcp(Settings(database_path=Path('unused'), calendar_enabled=True))
        for method, path, kwargs in (('post', '/calendar/events', {'json': CREATE}),
                                     ('patch', '/calendar/events/event', {'json': {'summary': 'Changed'}}),
                                     ('delete', '/calendar/events/event', {})):
            self.assertEqual(getattr(self.client, method)(path, **kwargs).status_code, 403)
        with TestClient(self.app, client=('203.0.113.8', 50000)) as remote:
            self.assertEqual(remote.post('/calendar/events', json=CREATE).status_code, 403)
            self.assertEqual(remote.delete('/calendar/events/event').status_code, 403)

    def test_uncertain_write_error_contains_lookup_id(self):
        self.adapter.create_event.side_effect = CalendarError('Read the event before retrying.', 504, 'event', True)
        response = self.client.post('/calendar/events', json=CREATE)
        self.assertEqual(response.status_code, 504)
        self.assertEqual(response.json(), {'detail': 'Read the event before retrying.', 'eventId': 'event', 'outcomeUnknown': True})
