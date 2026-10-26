# Logic Engine Demo — Google Calendar MCP integration

**Progress:** Stages A and B are implemented for local read-only use; see
[Calendar MCP setup](calendar-mcp.md) for installation, authorization, endpoints
and validation. Stage C's scoped write endpoints are implemented with mocked
tests; its explicitly authorized live create/update/delete checkpoint remains
pending. Flutter's weekly display and create/edit/delete dialogs are implemented;
subsequent language/chat control remains pending. This proposal preserves the staged plan.

## Objective

Extend the existing **Logic Engine Demo** with a genuine external domain: Google Calendar. The immediate task is to establish a working, reproducible **local MCP connection**, then expose a small set of calendar operations through the existing FastAPI backend. Later iterations will use those same operations for a comparison between LLM-driven tool orchestration and formal, symbolic control.

**Priorities:** working connection, safe calendar operations, clear architecture, minimal changes to the existing demo. **Do not implement a calendar-planning language or benchmarking system yet.**

## Existing project

- Repository: <https://github.com/mekispetermagan/logic_chatbot_demo>
- Frontend: Flutter (`frontend/`).
- API: Python/FastAPI (`backend/api/app/`).
- Logic engine: Haskell (`backend/logic_engine/`).
- Persistence: SQLite, managed by FastAPI.
- Existing toy domains: objects, networks, and cellular automata.
- Current public deployment: `https://logic-chatbot-demo.mekis.dev`, but **work locally first; do not change the production deployment**.
- Read `AGENTS.md`, `backend/api/README.md`, and the relevant existing API modules before editing. The repository has evolved; inspect the current checkout rather than assuming older architecture notes are fully current.

The Calendar MCP integration belongs in the Python backend. **Do not implement Google API access directly in Flutter or Haskell.** Do not disturb the existing domain implementations, dialogue behavior, or LLM toggle.

## Google-side setup — already completed

The user has prepared:

- Google account and calendar: **logic.engine.demo@gmail.com**.
- Google Cloud project / OAuth application: **Logic Engine Demo**.
- Google Calendar API enabled.
- OAuth audience: **External**, in testing mode.
- The above Gmail account registered as a test user.
- OAuth **Desktop app** client created.
- OAuth client secrets JSON downloaded locally.

**Do not ask the user to recreate these resources.** Ask only for the local path to the downloaded JSON when it is needed. Never ask the user to paste the credential contents into chat or commit the file.

The demo account is dedicated to testing. The calendar can be populated with fictional appointments, but do not alter events without explicit authorization for the test operation.

## MCP implementation

Use the open-source **nspady/google-calendar-mcp** server:

- Repository: <https://github.com/nspady/google-calendar-mcp>
- Setup: <https://github.com/nspady/google-calendar-mcp#quick-start>
- Authentication: <https://github.com/nspady/google-calendar-mcp/blob/main/docs/authentication.md>
- Architecture and tools: <https://github.com/nspady/google-calendar-mcp/blob/main/docs/architecture.md>

The upstream package is currently published as `@cocal/google-calendar-mcp`. Verify the package name, current documentation, and MCP tool schemas before implementation; do not infer them from this brief alone.

The upstream server supports local **stdio** transport, which is the preferred starting point: the FastAPI-side MCP client should communicate with an MCP server subprocess. Avoid introducing a public HTTP MCP endpoint just for this phase.

OAuth credential configuration is documented through `GOOGLE_OAUTH_CREDENTIALS`, pointing to the downloaded JSON; tokens are stored separately by the MCP server. The initial browser authorization should be performed **on the local Ubuntu machine**, where the browser can receive the localhost OAuth redirect. Do not attempt server-side/headless OAuth deployment yet.

**Note:** Google's OAuth *Testing* status can cause refresh-token expiry after seven days. Document how to reauthorize; treat this as a known test-environment limitation, not a software bug.

## Implementation stages

### Stage A — Independently verify the MCP server

1. Check local Node.js/npm availability and install the upstream MCP server using a reproducible, documented method. Pin or record the working version.
2. Configure the path to the OAuth JSON **outside the Git repository**. Ensure credentials and tokens are never committed or logged.
3. Complete browser-based OAuth authorization as `logic.engine.demo@gmail.com`.
4. Verify that the MCP client can discover tools and call at least:
   - `list-calendars`
   - `list-events` with an explicit date range
   - `get-freebusy` with an explicit time interval
5. Report the connected account, available calendar IDs (not tokens), discovered tool names, and any authentication limitations.

**Checkpoint:** demonstrate successful *read-only* access before proceeding to writes or application integration.

### Stage B — FastAPI integration

Create a small, isolated MCP adapter in `backend/api/app/`, following existing configuration, routing, and test patterns.

- The adapter must manage MCP subprocess/session lifecycle appropriately, discover or validate tool schemas, invoke tools, and normalize structured results and errors.
- Expose minimal **backend-only** functionality for listing calendars, listing events by interval, and checking free/busy information. Fit endpoint names and response types to the project's existing conventions; do not invent a new API architecture.
- Use timezone-aware timestamps; preserve event timezone/offset, all-day-event semantics, and Google event IDs. Do not assume every event is in UTC or that every event has a `dateTime` field.
- Treat Google Calendar as the source of truth. Do not create an independent SQL mirror of calendar events.
- Handle missing credentials, expired/revoked authorization, MCP startup errors, Google API failures, and timeouts with useful but non-sensitive errors.
- Keep the implementation independent of LLM calls and the Haskell engine for now.

**Checkpoint:** demonstrate a FastAPI request that retrieves the demo calendar's events through the MCP server.

### Stage C — Controlled write test

After successful read-only integration, add the narrow operations required to test:

- Create one explicitly named fictional appointment.
- Retrieve it by ID.
- Update its time or title.
- Confirm the change by reading it again.
- Delete **that same test event**, and verify deletion.

Use upstream MCP tools (`create-event`, `get-event`, `update-event`, `delete-event`) rather than Google's API directly. Explicitly scope all test writes to the intended demo calendar. Prevent accidental writes to a user's personal calendar.

**Security:** The existing demo has been publicly deployed. Do **not** expose unauthenticated, general-purpose calendar-write endpoints on the public application. For this phase, keep write tests local/test-only or behind an explicit authorization gate. Never put OAuth credentials, refresh tokens, or MCP subprocess access in the browser.

### Stage D — Tests and documentation

- Add automated tests for adapter behavior using mocked MCP responses: success, no events, invalid intervals, upstream errors, invalid credentials, and all-day/recurring event representations where applicable.
- Provide a short manual integration checklist for the OAuth-dependent end-to-end tests; these should not be run by default in CI.
- Record local setup instructions, environment variables, how to start/stop the MCP server, where authentication state is stored, and how to reauthorize after token expiry.
- Run the relevant existing FastAPI tests to detect regressions.
- Summarize changed files, test results, and any remaining manual steps.

## Constraints and boundaries

- **Do not rewrite the existing Flutter, FastAPI, or Haskell architecture.**
- **Do not implement a new LLM agent, Controlled English grammar, symbolic scheduler, or benchmark in this task.** Those are subsequent tasks once the MCP connection works.
- **Do not add a specialized scheduling or constraint-solving MCP tool.** Future experimental fairness requires the LLM agent and the symbolic controller to access the **same primitive calendar operations**.
- Keep provider-specific MCP mechanics behind a narrow adapter so the later Haskell controller and LLM agent can reuse the same backend capability.
- Do not deploy, modify production services, push credentials, or modify real calendar events without user authorization.
- Present a brief implementation plan before making substantial changes, and work in verifiable checkpoints.

## Next-phase research context (not part of this implementation)

The research compares:

1. **LLM-controlled mode:** The LLM interprets natural language, plans, and selects MCP calls.
2. **Symbolic-controlled mode:** An LLM may translate natural language, but a formal engine interprets compositional constraints, plans, verifies, and invokes the *same MCP tools*.

The point is not to compare a dedicated scheduler with an LLM forced to calculate scheduling manually. Both controllers receive identical calendar operations. The hoped-for advantage of the symbolic approach arises from grammatical composition and precise execution constraints, including **“so that”**, **“without”**, quantifiers, temporal relations, and optimization expressions such as **“using the fewest changes.”**

Candidate later scenario: *“Schedule three 90-minute meetings next week so that they take place on different days between 10:00 and 17:00, without moving any existing appointments.”* This requires formal constraints and general search/planning, but must **not** be hardcoded as a special MCP operation.

## Definition of done for the current task

On the user's Ubuntu development machine:

1. Google Calendar MCP authenticates successfully with `logic.engine.demo@gmail.com`.
2. The MCP client can read the demo calendar and retrieve free/busy data.
3. FastAPI can access those capabilities through a reusable MCP adapter.
4. An explicitly authorized create/update/delete cycle works on a disposable fictional test event, with read-back verification.
5. Secrets remain private; existing domains continue working; no production deployment has changed.
6. Setup, reauthentication, tests, and outstanding limitations are documented.

Stop at these criteria. The calendar-domain semantics and dual-engine comparison will receive separate specifications.
