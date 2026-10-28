# Calendar controlled language v1

The local demo implements Calendar parsing, reference resolution, evaluation and
planning in Haskell, with a controlled-English chat panel alongside the weekly
calendar. Optional natural-language interpretation uses the same app-managed
agent transport, shared review UI and admission budget as the other domains.

The detailed grammar, temporal rules, reference policy and decision structures
are in [the Calendar language design](proposed-calendar-language.md). The
implementation uses `calendar-v1` and policy `calendar-demo-1`.

## Try it locally

Build and install `logic-engine-editor` as described in
[the engine README](../backend/logic_engine/README.md), then restart FastAPI.
Keep the [Calendar MCP configuration](calendar-mcp.md) enabled; accepting event
changes also needs `LOGIC_CHATBOT_CALENDAR_WRITES_ENABLED=true`. No new OAuth
consent or LLM key is needed for controlled-English dialogue. For natural
language, export the existing `OPENAI_API_KEY`, restart FastAPI and enable the
LLM switch in Calendar. Its agent is provisioned on first interpretation; no
manual agent ID or dashboard setup is needed. Run one local API
worker against the dedicated demo account.

Select **Calendar**, then enter a command ending in a period or a question ending
in a question mark. Keywords ignore case; quoted strings preserve it.

```text
Create event from friday at 11:00 to friday at 11:15 with title "Laundry machine mechanic".
How many events match importance is critical and overlaps thursday?
Schedule event lasting 30 minutes within thursday morning with title "Meeting".
Make room for event lasting 60 minutes within starting at thursday at 09:00.
Remove clashes on thursday.
```

Missing duration, window, date, reference or movement permission produces a typed
clarification. Buttons submit the exact selected value; free-text temporal answers
use the same syntax, such as `thursday morning` or `thursday at 09:00`.
The shared chat composer sends with Enter; Shift+Enter inserts a newline.
Up/down recall previous user entries at the first/last line, preserving the
current draft. Rejected syntax and its feedback remain in persistent history.
Clarification replies use the same composer.
The revision control lists established parameters and lets the user replace one
while retaining independent commitments. Importance replies are -1 (None),
0 (Normal), 1 (Important) or 2 (Critical). Protected handles use a JSON list.

## Implemented behavior

- Atomic creation, deletion and setters for title, location, description,
  importance and interval. Text defaults to `""`; importance defaults to Normal.
  Creation optionally accepts title, location, description and importance in that
  order via `with`, joining fields with `and`. Explicit `unspecified` values
  trigger clarification before creation; fixed intervals permit overlaps.
  Empty titles display as `(Untitled)` without changing their stored value.
- Stable `#N` handles, `it`, ordered descriptions, explicit reference choices and
  Boolean-scope clarification before evaluation. Tooltips show imported handles
  once the dialogue has encountered them.
- Earliest placement without moving existing events; minimal-cost insertion;
  date-based clash repair. Automatic moves obey approved importance/protection
  constraints, original date and inferred period envelopes, and preserve
  normalized elapsed duration. Weighted movement costs use 1/4/9.
- Atomic field/existence tests, conditions, duration/gap, selection/counts,
  every/some, free intervals, clash pairs/counts, earliest interval, feasibility
  and minimum-cost questions. Planning questions compute hypothetical witnesses
  and grant no write permission.
- Five-minute rounding with halfway values rounded down, exact-original checks,
  DST-gap rejection and explicit repeated-time choices. Imported timestamps and
  raw colors survive unrelated edits.

The language universe contains timed events wholly inside the selected Budapest
Monday–Sunday week. All-day events, cancelled events and events crossing a week
boundary are excluded. Cross-day events inside the week are supported. The
weekly GUI has broader display scope and can show boundary-crossing events.
Recurring events are readable but cannot be changed by the language.

## Review, persistence and recovery

Evaluation is provisional. Commands produce a net change plan; **Accept changes**
checks the same week snapshot before sending writes. A failed later sentence can
produce a separately labeled successful prefix. Accepting that prefix ends the
remaining entry. Cancelling a pending entry submits no proposed writes. Changing
weeks cancels pending evaluation; navigation is blocked during write recovery.
Manual editing is disabled while chat evaluates or awaits clarification/review.

SQLite stores discourse, handle allocation, pending evaluation and a durable write
journal. It is not an event source for new entries: each starts with fresh Google
reads. Temporary event content is retained only for pending/recovery work;
completed entries keep their dialogue/decision record rather than a world mirror.

Each creation reserves its Google ID before submission. Writes run serially and
are read back. A timeout stops application and enters recovery. **Reconcile** only
reads; **Authorize remaining writes** explicitly continues confirmed outstanding
operations; **Keep verified partial result** abandons the intended remainder.
Neither automatic retry nor rollback is used. Final discourse commits only after
fresh events match the accepted result. External changes require renewed review.

Candidate/check/node caps and an accumulated ten-second evaluation watchdog
produce resource-limited outcomes rather than false infeasibility or optimality
claims. Explicit requirement revision records prior work and starts a new budget.
Up to 64 optimal schedule examples are retained for explicit choice; they are not
presented as an exhaustive list or as a user preference.

Natural-language requests produce a separate interpretation proposal. Preview is
private; Accept interpretation starts/resumes provisional Haskell evaluation.
Even an accepted translation cannot submit Google writes: the later Calendar
change plan still requires **Accept changes**. Operational holes are clarified
by Haskell. Free-form replies to text-valued engine questions (or replies that do
not parse as the expected typed value) can be interpreted into reviewed JSON
values, bound to that exact pending question. They cannot become new commands.
Rejection restores the pending engine task; courtesy replies do not consume it.
The current week/context fingerprint is checked again before preview/acceptance.

Calendar Undo, alternative scheduling objectives, arbitrary-list/global repair,
additional task families and public deployment remain outside this version.

## Transport and verification

Loopback-only `GET /calendar/dialogue` restores state. `POST /calendar/dialogue`
accepts a `type` and current `revision`; start additionally carries `text`,
`timeMin` and `timeMax`, while answer/revise carry a parameter `key` and typed
`value`. Actions are `start`, `answer`, `revise`, `accept`, `cancel`, `reconcile`,
`continue` and `keepPartial`. Interpretation actions are `previewInterpretation`,
`acceptInterpretation`, `rejectInterpretation` and `answerInterpretation`, bound
to a `proposalId` and (for preview/accept) candidate `rank`. Start/answer may carry
`useLlm:true`; typed answer requests additionally retain their original `text`. Stale revisions return 409. The Haskell bridge is
independent of HTTP, SQLite and Google access.

Tests cover grammar round trips, real-engine semantics, a small exhaustive
optimization oracle, clarification/revision, persistence, stale snapshots,
reserved-ID recovery and UI review behavior. Provider tests use a fake Calendar;
they never mutate the dedicated Google account.
