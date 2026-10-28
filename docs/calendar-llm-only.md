# Calendar LLM-only agent and integration design

**Status: backend and frontend implemented; live LLM-only smoke test pending.** The agent-facing domain specification
is [calendar-domain.md](calendar-domain.md). The controlled language is specified
separately in [calendar-language-v1.md](calendar-language-v1.md); that document
must not be included in the LLM-only agent's context.

This engineering document is not itself an agent prompt. Only the domain rules,
mode-specific responsibilities and final tool/approval contracts may be assembled
into that prompt. Architecture notes, historical proposals, benchmark designs and
symbolic engine internals are excluded.

## Agreed architecture

- The separate **Calendar · LLM-only** chat selection uses the same weekly display, GUI
  editor, underlying calendar and selected-week domain. Keep agent identity,
  session, conversation history and pending task state independent of the
  symbolic Calendar chat. Clearly label which chat mode is active.
- Use the same configured model and reasoning setting as the translator. Both
  agents receive these shared rules, factual event data and explicit time/week
  context. The symbolic translator additionally receives its grammar and
  translation examples; the LLM-only agent receives Calendar tool definitions.
  It must not inherit the translator-only instructions forbidding reasoning.
- LLM-only chat uses no Haskell parser, resolver, evaluator, scheduling algorithm,
  answer checker or controlled-language intermediate representation. GPT asks
  clarifications, maintains commitments and decides primitive operations. Python
  mediates MCP access and owns credentials. Google remains the source of truth.
- Reuse the shared chat appearance, composer, history navigation and token usage
  display. Keep token/session attribution distinct by mode. Selecting the other
  mode is not an implicit acceptance, cancellation or permission to bypass busy
  state; shared-calendar write exclusion must cover both modes.

## Implemented backend and tool contract

The separate `calendar-llm-only` agent uses the configured `gpt-6-luna` model,
medium reasoning effort, no environment, no subagents and no code execution. It
receives this project's shared domain specification and its own role/transport
instructions. The Calendar translator also receives the same shared domain
specification, plus its grammar and translation instructions. No solver recipe,
controlled-English examples or engine-derived schedule is sent to the baseline.

The function-tool bridge follows the [Agents API function-tool protocol](https://developers.openai.com/api/docs/guides/agents-api/tools/functions).
It discovers actual schemas from the local stdio MCP server; no public MCP
endpoint is needed. Available functions are:

| Function | Effect |
| --- | --- |
| `calendar_list_events` | Forward `list-events` arguments and its raw result |
| `calendar_get_event` | Forward `get-event` arguments and its raw result |
| `calendar_reserve_event_id` | Reserve a durable provider-compatible ID, without creating an event |
| `calendar_propose_changes` | Submit an ordered array of primitive `create-event`, `update-event`, `delete-event` calls for approval |

Tool schemas are narrowed to the existing primitive event fields and fixed
account/calendar. Writes require `sendUpdates: none`; raw timestamps, field values
and call order are not corrected, rounded, mapped to importance or optimized by
Python. Creation uses the ID explicitly obtained through the reservation tool.
With writes disabled, only read tools are advertised. Read results are forwarded
unchanged, including provider metadata and out-of-universe events returned by the
MCP query. **GPT applies the domain's week-membership and event-type rules itself.**
There is no hidden scope projection, reference resolver or answer checker.
Free/busy, conflict-solving options, attendees and recurrence-modification tools
are not exposed by this bridge.

The entire proposed write array is reviewed as exact calls and arguments. No
write occurs before `accept`. The provider's function call stays pending until
real execution or rejection; the bridge never reports a staged call as success.
Acceptance submits the reviewed primitives in the agent's original order. Raw
MCP responses are returned inside execution records alongside readback evidence;
verification establishes submitted effects, not semantic plan correctness.
Rejection returns an explicit function error to the same pending call. A further
write proposal always requires another approval.

Argument schemas, fixed namespace, write-enable settings and adapter read-only
capabilities are application controls. Python does not test movement permissions,
infer dates/periods, compute availability/cost, resolve conversational references,
repair plans or consult Haskell. Model-selected domain violations are not silently
fixed: they remain visible for review and independent benchmark scoring.

## Local API and persistence

Loopback-only `GET /calendar/llm-only/dialogue` returns the separate conversation,
revision, status, transcript, selected week, proposed calls, execution journal,
tool-call trace and shared `llmBudget` counters. `requiresResume` identifies an
interrupted agent loop. No Haskell executable is needed for this API.

`POST /calendar/llm-only/dialogue` accepts `type` and the current `revision`:

- `message`: natural-language `text`; initial/new-week requests supply aware ISO
  `timeMin`/`timeMax` for the selected Budapest Monday-to-Monday week. Clarification
  replies retain the task's frozen context. Completed tasks refresh from Google.
- `accept` / `reject`: include the current `proposalId`.
- `resume`: inspect and continue the existing agent turn without replaying input.
- `cancel`: cancel unsubmitted work; cannot discard uncertain cloud writes.
- `reconcile`: read actual submitted outcomes; never write.
- `continue`: explicitly authorize verified outstanding calls after reconciliation.
- `keepPartial`: abandon remaining calls after uncertainty has been resolved,
  report verified partial effects to GPT, and do not roll them back.

The response state is `idle`, `running`, `clarification`, `review`, `applying`,
`recovery`, `suspended` or `answered`. Stale revisions/proposal IDs return 409.
Pending state, exact tool-call identities/results, creation reservations and the
application journal survive restart. Lost result delivery resends the saved
result only when that same call remains pending; it never repeats a confirmed
Calendar write. A lost initial session response is not automatically resubmitted.

SQLite uses separate `calendar_llm_only_dialogue`, `calendar_llm_only_sessions`
and `calendar_llm_only_events` records. Completed read results are not retained
as an event cache. Existing Google IDs identify tool operands; explicit reserved
IDs identify proposed creations. No symbolic numeric-handle resolution is
performed. A recreated session receives the visible transcript with an explicit
notice that earlier tool results are not included and fresh facts may be needed.

Both modes and GUI writes share the current Calendar mutation gate. A pending
clarification/review/recovery in one mode blocks the other writer. Sessions and
accounting use distinct `calendar-llm-only:` context IDs. Every user-started agent
turn creates one accounting record; returning function results resumes the same turn.
Delayed usage reconciliation and shared token totals include this mode. Provider
and tool failures remain recorded independently of mathematical feasibility.

Local agent associations can be detached without provider calls using
`python -m app.agents recreate --domain calendar-llm-only`; `all` includes this
agent. This retains dialogue, proposed writes, recovery evidence and accounting.
No new environment variables, OAuth account or key are required. Restart FastAPI
to load this backend. Frontend selection/chat wiring remains separate work.

## Measurement boundary

Benchmark the same initial week and task, with the same semantic information,
model/settings and primitive Calendar capabilities. Restore identical initial
states between runs; separate chat histories do not isolate cloud event changes.
Count all model calls, clarifications, corrections and retries attributable to a
task. Report input/cached input/output/reasoning usage, correctness and elapsed
time, including engine computation in the symbolic mode. Keep interactive usage
labels unchanged. Detailed case generation, budget and experimental protocol are
a separate benchmark task; no outcomes or performance advantage are assumed.
An independent checker may score completed benchmark results, but must not feed
solutions or corrections into the LLM-only interactive chat path.

## Agent instruction boundary

Include the shared domain specification, explicit selected week/frozen Budapest
time, factual event data, tool definitions and approval/tool-result semantics.
Assign natural-language interpretation, reference resolution, clarification,
reasoning, planning and answers to GPT. Request ordinary clear English rather
than translation candidates or controlled-English intermediate programs.

Exclude the controlled grammar, translation pairs, Haskell salience scores,
command decomposition, finite-domain solver procedures, propagation/pruning,
no-movement-first strategies, tick-arithmetic advice, worked scheduling solutions,
and solutions/diagnostics supplied by an independent task checker. Domain
examples explaining a definition, such as rounding or cost units, are allowed;
solved planning examples are not. The agent is free to choose a different or
better method, subject to the same domain constraints and objective.

Python owns credentials, fixed account/calendar access, primitive argument
validation, execution state and verified provider outcomes. It must not supply
semantic reference choices, task feasibility decisions, optimized arrangements,
objective scores or corrected plans to the baseline. Adapter failures must not
be disguised as reasoning feedback from a hidden solver. The current Calendar
GUI editor calls Python/MCP directly; no Haskell path is required for that editor.

## Existing execution infrastructure

Google is the source of truth. SQLite may persist conversation/session identity,
commitments, private proposed operations and a recovery journal; it is not an
authoritative event mirror. Reserve Google-compatible creation IDs durably,
serialize approved writes, verify readback and stop on uncertain outcomes.
Reconciliation is read-only; completing a remainder requires explicit approval.
Do not automatically replay an uncertain creation or compensate earlier writes.
Preserve the confirmed partial result and pending recovery state across restart.

Use fresh snapshots at task boundaries and reject stale approval. Disable GUI
editing and conflicting chat mutations while either Calendar mode owns pending
work or recovery. Week navigation cancels unaccepted work and is blocked during
uncertain application. Switching modes must not release the shared mutation gate.
The local demo has one backend worker; the MCP subprocess/token lock alone is
not a task-level lock. Existing loopback-only access and write-enable settings
continue to apply. See [Calendar MCP setup](calendar-mcp.md) for OAuth, installation
and dedicated single-user account/testing assumptions; do not duplicate secrets
or setup instructions here.

## Validation and remaining work

Tests use fake Google data and mocked HTTP provider sessions. They cover raw
forwarding, creation/update/deletion, argument errors, exact approval/rejection,
clarification/session isolation, stale plans, both mutation-gate directions,
restart recovery, partial application, lost cloud/result acknowledgements,
read-only settings, accounting and admin recreation. The Haskell executable path
in baseline tests is deliberately nonexistent. A deliberately wrong model plan
is forwarded rather than repaired. No paid provider turns or live Calendar
writes were used for implementation verification.

Frontend wiring and a separately authorized live end-to-end check remain to be
done. Tool schemas come from the installed MCP server at first use; a live check
will verify compatibility with that server and the real agent account. These
mock-based tests do not establish baseline reasoning quality or token savings.

## Presentation and lifecycle details

These are application behavior, not part of the agent-facing domain specification.
The shared weekly GUI displays timed events overlapping the week, including events
that cross its boundaries, whereas chat excludes boundary-crossing events. Display
segments refer to one complete event. Tooltips/details show full timestamps; the
GUI may show exact imported times while chat reasons under the domain's normalized
model. `(Untitled)` is a display fallback, not a stored title. GUI form requirements
do not override the chat's permission to create an untitled event.

Changing weeks cancels unaccepted proposals and pending clarification, preserves
the transcript and requires fresh resolution in the new context. It cannot carry
a plan silently into another week. Navigation is explicit UI context control,
not an implicit agent scheduling action. During uncertain-write recovery, context
changes remain blocked. Cancellation does not undo confirmed cloud writes.

Time displays normally use minutes; show seconds where needed to explain exact
originals, rounding differences or validity. Movement review shows both exact
original and proposed intervals, disclosing changed normalized elapsed duration.
Populated event creation is reviewed as a complete proposed event, not as a
sequence of intermediate visible appointments. These presentation requirements
are shared by the two Calendar interfaces where applicable.


## Implemented frontend

Select **Calendar · LLM-only** in the app bar. The LLM switch is on and disabled
in this mode; the original Calendar mode retains its optional translator switch.
Both modes use one CalendarController, weekly display and GUI editor, with
separate dialogue histories and backend sessions. The shared chat composer keeps
Enter submission and Up/Down entry recall. Controlled-English help is available
only in the symbolic Calendar mode. Token usage uses the shared display.

The LLM-only adapter sends ordinary messages to `/calendar/llm-only/dialogue`.
Proposed MCP operations are shown for explicit acceptance or rejection. Interrupted
turns expose Resume; uncertain writes expose read-only reconciliation before
authorizing remaining writes or keeping the verified partial result. A failed
POST requires explicit status refresh before another submission. Refresh does
not repeat the request. Calendar events are fetched again after baseline actions.

Pending work locks the shared editor across both modes. Switching modes preserves
the pending task; the other chat tells the user to return to its owner. Week
navigation is blocked by the other mode's pending task and during recovery.
Frontend tests use mocked HTTP responses and perform no live model calls or
Calendar writes.
