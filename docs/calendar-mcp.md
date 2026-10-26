# Local Google Calendar MCP connection

## Current scope

Implemented: local OAuth setup and FastAPI reads plus opt-in, scoped event writes through the upstream
[`@cocal/google-calendar-mcp`](https://github.com/nspady/google-calendar-mcp) server,
using stdio. Google Calendar is the source of truth; there is no SQL event mirror,
calendar conversation, Haskell language, LLM integration or Flutter calendar UI yet.
The existing Objects, Network and Cellular domains remain independent.

Verified locally with Node **24.22.1**, MCP server **2.7.0**, and Python MCP SDK
**1.30.0**. Node 20 or newer is required by the pinned server. Setup uses the
existing Google Desktop OAuth client and dedicated `logic.engine.demo@gmail.com`
account. Do not recreate Google Cloud resources already prepared for this demo.

## Installation and private configuration

Install Node/npm if absent using the [Node installation instructions](https://nodejs.org/en/download).
Then install the pinned MCP server outside the repository:

```bash
npm install --prefix "$HOME/.local/share/logic-chatbot-demo/calendar-mcp" \
  --save-exact @cocal/google-calendar-mcp@2.7.0
```

Retain that installation's package lock; subsequent reinstalls can use
`npm ci --prefix "$HOME/.local/share/logic-chatbot-demo/calendar-mcp"`.
The local machine currently uses a private Node installation under
`~/.local/share/logic-chatbot-demo/node-v24.22.1-linux-x64/`. It need not be
installed system-wide; configure its absolute `bin/node` path below.

Place the downloaded OAuth JSON outside the repository, for example
`~/.config/logic-chatbot-demo/google-calendar/oauth-client.json`. Use a private
directory (mode 700) and credential/token files (mode 600). Do not put JSON
credentials or generated tokens in Flutter assets, SQLite, logs or Git.

From the repository root, install the Python adapter dependencies:

```bash
cd backend/api
source .venv/bin/activate
python -m pip install -r requirements.txt
```

Add these entries to `backend/api/.env`, substituting real absolute paths:

```dotenv
LOGIC_CHATBOT_CALENDAR_ENABLED=true
LOGIC_CHATBOT_CALENDAR_WRITES_ENABLED=false
LOGIC_CHATBOT_CALENDAR_NODE=/absolute/path/to/node
LOGIC_CHATBOT_CALENDAR_MCP_PATH=/home/your-user/.local/share/logic-chatbot-demo/calendar-mcp/node_modules/@cocal/google-calendar-mcp/build/index.js
GOOGLE_OAUTH_CREDENTIALS=/home/your-user/.config/logic-chatbot-demo/google-calendar/oauth-client.json
GOOGLE_CALENDAR_MCP_TOKEN_PATH=/home/your-user/.config/logic-chatbot-demo/google-calendar/tokens.json
LOGIC_CHATBOT_CALENDAR_ACCOUNT=demo
LOGIC_CHATBOT_CALENDAR_ID=logic.engine.demo@gmail.com
```

The integration and writes both default to disabled. Set
`LOGIC_CHATBOT_CALENDAR_WRITES_ENABLED=true` only for local demo editing; writes
also require `LOGIC_CHATBOT_CALENDAR_ID=logic.engine.demo@gmail.com` exactly.
Reads can still use another configured calendar, but writes to it are denied.
`LOGIC_CHATBOT_CALENDAR_NODE` defaults to
`node` on PATH; `GOOGLE_CALENDAR_MCP_TOKEN_PATH` defaults to `tokens.json` beside
the explicitly configured OAuth file. All other paths must be configured.
The account nickname is a local token-store key, not an email address. The
calendar ID is the explicit Google resource used by event/freebusy routes.

## Authorize or reauthorize

From `backend/api/`, load the trusted local `.env` in Bash:

```bash
set -a
source .env
set +a
"$LOGIC_CHATBOT_CALENDAR_NODE" "$LOGIC_CHATBOT_CALENDAR_MCP_PATH" auth "$LOGIC_CHATBOT_CALENDAR_ACCOUNT"
```

Complete the browser sign-in as **logic.engine.demo@gmail.com** and approve
consent. The local callback normally uses port 3500, with fallbacks through 3505.
The helper writes tokens to `GOOGLE_CALENDAR_MCP_TOKEN_PATH` and exits on success.
The OAuth grant requests upstream's Calendar scope. The adapter's separate write
flag controls whether local event editing is available. Consent is not authorization
for an agent to change events without a user request.

Google's External/Testing OAuth setup can expire refresh tokens after seven days.
For expired or revoked authorization, rerun the auth command and complete consent.
Do not copy tokens into chat or delete the app database to repair authorization.
See the upstream [authentication guide](https://github.com/nspady/google-calendar-mcp/blob/main/docs/authentication.md).

## Start and verify FastAPI

After loading `.env`, run from `backend/api/`:

```bash
uvicorn app.main:app --reload
```

Keep the service bound to its default loopback address. Reload `.env` and restart
Uvicorn after configuration changes. There is no separate long-running MCP daemon
to manage: each MCP call starts a stdio subprocess, initializes an MCP session,
discovers tool schemas, validates the tool arguments, performs one operation,
and closes the session/process. Calls are serialized per backend process to avoid
concurrent token refresh; each call has a 30-second total timeout including waiting.
An edit can perform additional calls for preflight checks and read-back verification.
Run a single backend worker for this local demo.

In another terminal:

```bash
curl --fail http://127.0.0.1:8000/calendar/calendars
curl --fail --get http://127.0.0.1:8000/calendar/events \
  --data-urlencode 'timeMin=2026-10-26T00:00:00+01:00' \
  --data-urlencode 'timeMax=2026-11-02T00:00:00+01:00' \
  --data-urlencode 'timeZone=Europe/Budapest'
curl --fail --get http://127.0.0.1:8000/calendar/freebusy \
  --data-urlencode 'timeMin=2026-10-26T00:00:00+01:00' \
  --data-urlencode 'timeMax=2026-11-02T00:00:00+01:00' \
  --data-urlencode 'timeZone=Europe/Budapest'
```

Choose intervals relevant to your demo date. Use URL encoding so `+` in timezone
offsets is not interpreted as a space. `timeMin` and `timeMax` are mandatory,
timezone-aware, and strictly increasing. `timeZone` is an IANA timezone and
defaults to Europe/Budapest. All-day dates retain their date-only representation
and exclusive end date; timed-event offsets/timezones, recurring-event identifiers
and original-start fields are retained as supplied by MCP. No local expansion or
reinterpretation of recurring events occurs.

| Route | Result |
| --- | --- |
| `GET /calendar/calendars` | Calendar metadata visible to the configured account, plus account nickname and total count |
| `GET /calendar/events` | Events from the configured calendar with Google IDs and event fields preserved, interval metadata and count |
| `GET /calendar/events/{eventId}` | One event by its Google ID, including all-day/recurrence metadata |
| `GET /calendar/freebusy` | Busy intervals from the configured calendar and query metadata |
| `POST /calendar/events` | Create a one-off event and read it back; returns 201 on verified success |
| `PATCH /calendar/events/{eventId}` | Update supplied fields of a one-off event and read it back |
| `DELETE /calendar/events/{eventId}` | Delete a one-off event and verify its absence/cancelled state |

These routes do not accept caller-selected account/calendar IDs. They reject
non-loopback clients with 403. Write routes require the additional enable flag
and the fixed dedicated calendar; there is no arbitrary MCP endpoint.
Do not enable them behind a public reverse proxy: loopback filtering is a local
demo boundary, not application authentication. Public deployment requires a
separate authenticated access design. The controlled live write test and subsequent
GUI editor remain pending at this checkpoint.

The subprocess enables `list-calendars`, `list-events`, `get-freebusy`, and `get-event`.
With writes enabled for the dedicated calendar it also enables `create-event`,
`update-event`, and `delete-event`.
Upstream also advertises its mandatory `manage-accounts` tool even with filtering;
the adapter never permits its invocation. MCP stderr and provider errors are not
forwarded or logged, and the child receives only the SDK's basic process
environment plus the Calendar configuration, not the OpenAI API key.

Missing configuration/authorization or a startup failure returns 503; a timeout
returns 504; invalid intervals/timezones/payloads return 422; upstream result/schema
errors return 502; missing/deleted events return 404/410. Errors contain no raw provider response or credential values.
Free/busy lookup failures are never reported as empty availability.

## One-off event editing

After explicitly enabling writes in `.env`, reload/export the file and restart
Uvicorn. Reads work without this flag. The following is the JSON body for creation;
the example is documentation only and has not been submitted to Google:

```json
{
  "summary": "Disposable demo appointment",
  "start": {"dateTime": "2026-10-29T09:00:00+01:00", "timeZone": "Europe/Budapest"},
  "end": {"dateTime": "2026-10-29T10:00:00+01:00", "timeZone": "Europe/Budapest"},
  "description": "Fictional appointment for a controlled test",
  "location": "Demo"
}
```

For an all-day event, use `"start":{"date":"2026-10-29"}` and
`"end":{"date":"2026-10-30"}` instead. End dates are exclusive. Timed endpoints
must include explicit offsets, use whole seconds, and, if supplied, have an IANA
timezone consistent with that offset at the specified instant. Start must precede
end, and both endpoints must have the same kind.

PATCH accepts any of `summary`, `description`, `location`, or the pair `start` and
`end`. Omitted fields remain unchanged. Null values and empty updates are rejected;
use `"description":""` or `"location":""` to clear those text fields. A summary
must be nonblank. Changing times requires both endpoints to avoid hidden duration
or timezone assumptions. All payloads reject unknown fields.

Clients cannot supply an account, calendar ID, event ID for creation, attendees,
recurrence or notification settings. The adapter supplies an explicit demo account
and calendar and uses `sendUpdates: "none"`. It checks existing events before update
or delete and rejects recurring series and instances with 409: editing those requires
an explicit scope contract later. There are no calendar Undo snapshots; Google
remains authoritative.

Successful create/update replies contain `event` and `verified: true`, with the
event retrieved again from Google and checked against the requested changes.
Delete returns `eventId`, `deleted: true`, and `verified: true` only after a lookup
establishes absence (404/410) or cancelled status.

Writes are never automatically retried by the adapter. If a write was submitted
but its outcome or subsequent verification is uncertain, the error includes
`outcomeUnknown: true` and `eventId`. Use `GET /calendar/events/{eventId}` and refresh
the calendar before deciding whether another action is necessary. A failed response
does not establish that nothing changed. Creation uses a generated Google-compatible
event ID so this lookup is possible even after a timeout. Requests are not atomic
with external Google Calendar edits; no revision/ETag conflict protection is promised.

## Tests and manual checkpoint

From `backend/api/` with `.venv` active:

```bash
python -m unittest tests.test_calendar -v
python -m unittest discover -s tests -v
```

Calendar tests use mocked MCP sessions and captured 2.7.0 tool schemas; no Google
credentials, network calls or calendar changes are needed. The complete backend
suite still requires the built Haskell executable for the existing domains.

Manual OAuth-dependent checks, excluded from default tests:

1. Complete local authorization; verify the token file is outside Git and mode 600.
2. List calendars and confirm the intended account's primary ID and timezone.
3. Retrieve an explicit interval and compare IDs/times with Google Calendar.
4. Retrieve free/busy for that interval and compare the busy times.
5. Restart FastAPI and repeat a read to verify stored authorization is reused.
6. Check an existing toy domain still accepts controlled English and supports Undo.

After separate authorization for a disposable fictional appointment, the manual
write checkpoint is: enable writes locally, create the event, retrieve its returned
ID, update its title/time, confirm by ID, delete that same ID, and verify it is
absent. Do not reuse existing demo events for this lifecycle test without permission.
Automated tests cover timed/all-day write cycles, payloads, calendar scoping,
recurrence restrictions, read-back mismatches and uncertain outcomes with mocked MCP.

The initial live check found primary `logic.engine.demo@gmail.com` and
`en.hungarian#holiday@group.v.calendar.google.com`, both in Europe/Budapest.
The first explicit interval returned one existing event and one busy interval.
No calendar events were changed during the initial read-only setup/checks. A later,
explicitly authorized one-off creation was verified through API read-back and the
user's Google Calendar browser view. Live update/delete verification remains pending.
