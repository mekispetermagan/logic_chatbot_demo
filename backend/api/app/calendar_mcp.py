"""Scoped Calendar MCP adapter. Google is the source of truth; no SQL mirror."""
import asyncio
import json
import os
import shutil
from datetime import datetime, timedelta
from uuid import uuid4

import anyio
from jsonschema import Draft202012Validator, ValidationError
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp.shared.exceptions import McpError

from .config import Settings

READ_TOOLS = ('list-calendars', 'list-events', 'get-freebusy', 'get-event')
WRITE_TOOLS = ('create-event', 'update-event', 'delete-event')
DEMO_CALENDAR_ID = 'logic.engine.demo@gmail.com'


class CalendarError(Exception):
    def __init__(self, detail, status_code=503, event_id=None, outcome_unknown=False):
        self.detail = detail
        self.status_code = status_code
        self.event_id = event_id
        self.outcome_unknown = outcome_unknown
        super().__init__(detail)


class CalendarMcp:
    def __init__(self, settings: Settings, timeout=30):
        self.settings = settings
        self.timeout = timeout
        # Serialize subprocesses so concurrent operations do not race token refresh.
        self._lock = asyncio.Lock()

    def require_writes(self):
        if not self.settings.calendar_enabled or not self.settings.calendar_writes_enabled:
            raise CalendarError('Calendar writes are disabled on this backend.', 403)
        if self.settings.calendar_id != DEMO_CALENDAR_ID:
            raise CalendarError('Calendar writes are restricted to the dedicated demo calendar.', 403)

    def parameters(self):
        settings = self.settings
        if not settings.calendar_enabled:
            raise CalendarError('Calendar integration is disabled on this backend.')
        credentials = settings.google_oauth_credentials
        if credentials is None or not credentials.is_file():
            raise CalendarError('Calendar OAuth credentials are not configured or readable.')
        try:
            document = json.loads(credentials.read_text())
            client = document.get('installed', {})
            if not all(isinstance(client.get(key), str) and client[key] for key in ('client_id', 'client_secret')):
                raise ValueError('Invalid desktop client')
        except (OSError, ValueError, AttributeError, TypeError):
            raise CalendarError('Calendar OAuth credentials are invalid or unreadable.') from None
        tokens = settings.calendar_token_path or credentials.parent / 'tokens.json'
        if not tokens.is_file():
            raise CalendarError('Calendar authorization is missing. Run the local Calendar MCP authorization command.')
        if not settings.calendar_mcp_path or not settings.calendar_mcp_path.is_file() or not shutil.which(settings.calendar_node):
            raise CalendarError('Calendar MCP executable is not configured or installed.')
        return StdioServerParameters(
            command=settings.calendar_node,
            args=[str(settings.calendar_mcp_path), '--enable-tools', ','.join(
                READ_TOOLS + WRITE_TOOLS if settings.calendar_writes_enabled and settings.calendar_id == DEMO_CALENDAR_ID else READ_TOOLS)],
            env={'GOOGLE_OAUTH_CREDENTIALS': str(credentials),
                 'GOOGLE_CALENDAR_MCP_TOKEN_PATH': str(tokens),
                 'GOOGLE_ACCOUNT_MODE': settings.calendar_account},
            cwd=str(settings.calendar_mcp_path.parent),
        )

    @staticmethod
    def failure(error):
        if isinstance(error, CalendarError):
            return error
        if isinstance(error, BaseExceptionGroup):
            for nested in error.exceptions:
                failure = CalendarMcp.failure(nested)
                if failure is not None:
                    return failure
        if isinstance(error, TimeoutError):
            return CalendarError('Calendar MCP request timed out.', 504)
        if isinstance(error, McpError):
            return CalendarMcp.upstream_failure(error.error.message)
        return None

    @staticmethod
    def upstream_failure(message):
        text = message.lower()
        if any(word in text for word in ('invalid_grant', 'authentication', 'unauthorized', 'oauth', 're-auth', 'token', 'account')):
            return CalendarError('Calendar authorization failed. Reauthorize the local demo account.')
        if '410' in text or 'gone' in text:
            return CalendarError('Calendar event is deleted or unavailable.', 410)
        if '404' in text or 'not found' in text:
            return CalendarError('Calendar event or resource was not found.', 404)
        return CalendarError('Google Calendar rejected the request.', 502)

    @staticmethod
    def decode(result):
        if result.isError:
            # Inspect error classification only; never echo upstream text or credentials.
            raise CalendarMcp.upstream_failure(' '.join(item.text for item in result.content if item.type == 'text'))
        data = result.structuredContent
        if data is None:
            try:
                data = json.loads('\n'.join(item.text for item in result.content if item.type == 'text'))
            except ValueError:
                raise CalendarError('Calendar MCP returned invalid JSON.', 502) from None
        if not isinstance(data, dict):
            raise CalendarError('Calendar MCP returned an invalid result.', 502)
        return data

    async def _read(self, tool, arguments):
        if tool not in READ_TOOLS:
            raise CalendarError('Unsupported Calendar operation.', 422)
        return await self._call(tool, arguments)

    async def _call(self, tool, arguments):
        mutating = tool in WRITE_TOOLS
        if mutating:
            self.require_writes()
        elif tool not in READ_TOOLS:
            raise CalendarError('Unsupported Calendar operation.', 422)
        submitted = False
        try:
            parameters = self.parameters()
            # No automatic retries, especially after a mutation may have been sent.
            with anyio.fail_after(self.timeout):
                async with self._lock:
                    # Raw MCP stderr can contain credential-bearing provider errors.
                    with open(os.devnull, 'w') as errors:
                        async with stdio_client(parameters, errlog=errors) as (read, write):
                            async with ClientSession(read, write, read_timeout_seconds=timedelta(seconds=self.timeout)) as session:
                                await session.initialize()
                                schemas = {}
                                cursor = None
                                while True:
                                    page = await session.list_tools(cursor=cursor)
                                    schemas.update({item.name: item.inputSchema for item in page.tools})
                                    if not page.nextCursor:
                                        break
                                    if page.nextCursor == cursor:
                                        raise CalendarError('Calendar MCP tool discovery failed.', 502)
                                    cursor = page.nextCursor
                                if any(name not in schemas for name in READ_TOOLS) or tool not in schemas:
                                    raise CalendarError('Calendar MCP is missing a required tool.', 502)
                                try:
                                    Draft202012Validator(schemas[tool]).validate(arguments)
                                except ValidationError:
                                    raise CalendarError('Calendar MCP tool schema is incompatible with this adapter.', 502) from None
                                submitted = True
                                return self.decode(await session.call_tool(tool, arguments))
        except Exception as error:
            # SDK task-group failures may wrap process/transport/provider errors.
            failure = self.failure(error)
            failure = failure or CalendarError('Calendar MCP connection failed. Check installation and local authorization.')
            if mutating and submitted:
                raise CalendarError(
                    'Calendar write outcome is unconfirmed. Read the event before retrying; the operation may have completed.',
                    failure.status_code, arguments['eventId'], True) from None
            raise failure from None

    def event_result(self, result, event_id):
        event = result.get('event')
        if not isinstance(event, dict) or event.get('id') != event_id:
            raise CalendarError('Calendar MCP returned an invalid event.', 502)
        if event.get('calendarId', self.settings.calendar_id) != self.settings.calendar_id:
            raise CalendarError('Calendar MCP returned an unexpected calendar.', 502)
        return {'account': self.settings.calendar_account, 'calendarId': self.settings.calendar_id, 'event': event}

    async def event(self, event_id):
        result = await self._read('get-event', {
            'account': self.settings.calendar_account, 'calendarId': self.settings.calendar_id,
            'eventId': event_id,
        })
        return self.event_result(result, event_id)

    async def editable_event(self, event_id):
        self.require_writes()
        event = (await self.event(event_id))['event']
        if event.get('recurrence') or event.get('recurringEventId') or event.get('originalStartTime'):
            raise CalendarError('Recurring events require an explicit edit scope and are not supported by this editor yet.', 409)
        if event.get('status') == 'cancelled':
            raise CalendarError('Calendar event is deleted or unavailable.', 410)

    async def verified_write(self, tool, event_id, fields):
        if set(fields) - {'summary', 'start', 'end', 'description', 'location', 'colorId'}:
            raise CalendarError('Unsupported event fields; account and calendar are fixed by the backend.', 422)
        arguments = {'account': self.settings.calendar_account, 'calendarId': self.settings.calendar_id,
                     'eventId': event_id, 'sendUpdates': 'none', **fields}
        result = await self._call(tool, arguments)
        try:
            if tool == 'delete-event':
                if result.get('success') is not True or result.get('eventId') != event_id or result.get('calendarId') != self.settings.calendar_id:
                    raise CalendarError('Calendar MCP returned an invalid deletion result.', 502)
                try:
                    readback = await self.event(event_id)
                except CalendarError as error:
                    if error.status_code in (404, 410):
                        return {'account': self.settings.calendar_account, 'calendarId': self.settings.calendar_id,
                                'eventId': event_id, 'deleted': True, 'verified': True}
                    raise
                if readback['event'].get('status') != 'cancelled':
                    raise CalendarError('Calendar event still exists after deletion.', 409)
                return {'account': self.settings.calendar_account, 'calendarId': self.settings.calendar_id,
                        'eventId': event_id, 'deleted': True, 'verified': True}
            self.event_result(result, event_id)
            readback = await self.event(event_id)
            self.verify_fields(readback['event'], fields)
            return {**readback, 'verified': True}
        except CalendarError as error:
            raise CalendarError('Calendar write was acknowledged but verification failed. Read the event before retrying.',
                                error.status_code, event_id, True) from None

    @staticmethod
    def verify_fields(event, fields):
        try:
            for name, value in fields.items():
                if name in ('start', 'end'):
                    expected = json.loads(value)
                    actual = event[name]
                    if 'date' in expected:
                        matches = actual.get('date') == expected['date'] and 'dateTime' not in actual
                    else:
                        matches = (datetime.fromisoformat(actual['dateTime']) == datetime.fromisoformat(expected['dateTime'])
                                   and ('timeZone' not in expected or actual.get('timeZone') == expected['timeZone']))
                else:
                    matches = event.get(name, '') == value
                if not matches:
                    raise ValueError('Read-back mismatch')
            if event.get('status') == 'cancelled':
                raise ValueError('Read-back event is cancelled')
        except (KeyError, TypeError, ValueError):
            raise CalendarError('Calendar read-back does not match the requested event changes.', 409) from None

    async def create_event(self, fields):
        self.require_writes()
        # Google-compatible ID gives callers a lookup target if the response is lost.
        return await self.verified_write('create-event', uuid4().hex, fields)

    async def update_event(self, event_id, fields):
        await self.editable_event(event_id)
        return await self.verified_write('update-event', event_id, fields)

    async def delete_event(self, event_id):
        await self.editable_event(event_id)
        return await self.verified_write('delete-event', event_id, {})

    async def calendars(self):
        result = await self._read('list-calendars', {'account': self.settings.calendar_account})
        calendars = result.get('calendars')
        if not isinstance(calendars, list) or any(not isinstance(item, dict) or not isinstance(item.get('id'), str) for item in calendars):
            raise CalendarError('Calendar MCP returned an invalid calendar list.', 502)
        return {'account': self.settings.calendar_account, 'calendars': calendars, 'totalCount': len(calendars)}

    async def events(self, time_min, time_max, time_zone):
        result = await self._read('list-events', {
            'account': self.settings.calendar_account, 'calendarId': self.settings.calendar_id,
            'timeMin': time_min.isoformat(), 'timeMax': time_max.isoformat(), 'timeZone': time_zone,
        })
        events = result.get('events')
        if not isinstance(events, list) or any(not isinstance(item, dict) or not isinstance(item.get('id'), str) for item in events):
            raise CalendarError('Calendar MCP returned an invalid event list.', 502)
        # Preserve Google IDs, date vs dateTime, offsets, recurrence and timezone fields.
        return {'account': self.settings.calendar_account, 'calendarId': self.settings.calendar_id,
                'timeMin': time_min.isoformat(), 'timeMax': time_max.isoformat(), 'timeZone': time_zone,
                'events': events, 'totalCount': len(events)}

    async def freebusy(self, time_min, time_max, time_zone):
        result = await self._read('get-freebusy', {
            'account': self.settings.calendar_account, 'calendars': [{'id': self.settings.calendar_id}],
            'timeMin': time_min.isoformat(), 'timeMax': time_max.isoformat(), 'timeZone': time_zone,
        })
        calendars = result.get('calendars')
        entry = calendars.get(self.settings.calendar_id) if isinstance(calendars, dict) else None
        if not isinstance(entry, dict) or entry.get('errors') or not isinstance(entry.get('busy'), list):
            raise CalendarError('Calendar free/busy lookup failed.', 502)
        return {'account': self.settings.calendar_account, 'calendarId': self.settings.calendar_id,
                'timeMin': time_min.isoformat(), 'timeMax': time_max.isoformat(), 'timeZone': time_zone,
                'busy': entry['busy']}
