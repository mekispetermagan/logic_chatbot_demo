# Calendar benchmark protocol

Approved cohort: 12 fixed cases × 10 attempts × 2 approaches = **240 attempts**.
Model: **gpt-6-luna**, reasoning **medium**, for both approaches.
Selected week: **2–8 November 2026**, Europe/Budapest; bounds November 2 00:00
through November 9 00:00, UTC+01:00. Frozen conversational clock: November 4 08:00.
The live-demo week and production application database are not used.

## Isolation and configuration

Each active case has a disposable secondary Google calendar. A calendar may be reused
sequentially by a later case if Google refuses further provisioning; cases never share
a calendar concurrently. Each attempt
restores and reads back the fixture, and starts with a fresh SQLite database, empty
conversation and fresh remote agent session. Both approaches use the same public
requests, event values and shared domain rules. Provider-generated event IDs differ;
checks preserve each attempt's original identities. No concurrent user edits occur.
Per-case calendars permit parallel independent workers. The approach running first
alternates by case/repetition parity. Ten attempts are recorded, not ten successes.

The existing app endpoints, real Google MCP and real Agents API are used for all
measured dialogue operations. Fixture preparation is outside those operations. The symbolic
approach uses the real Haskell runtime; the LLM-only approach receives no Haskell
solver, expected schedule or checker. Only isolated worker processes rebind the Calendar
allowlist to their own disposable calendar. Production settings are untouched.

Application, prompt, shared-domain, executable, runner and task-definition hashes are
recorded before the first attempt. Application, prompt and task inputs remain fixed.
A versioned operator-controller correction is documented below; earlier incomplete
attempts remain included. An application or prompt fix requires a separate experiment.

## Public tasks

| Case | Complexity | Task |
| ---: | --- | --- |
| 1 | Simple | Earliest available gap |
| 2 | Simple | Edit title, location, description and importance |
| 3 | Simple | Count Critical events and overlapping pairs; no writes |
| 4 | Moderate | Clarify which Project review, then move it |
| 5 | Moderate | Make room, permitting Normal movement only |
| 6 | Moderate | Free a straightforward interval |
| 7 | Complex | Repair clashes with minimum weighted movement |
| 8 | Complex | Joint scheduling requiring backtracking |
| 9 | Complex | Correctly refuse insufficient movement permission; no writes |
| 10 | Very complex | Joint scheduling across alternative days and distinct dates |
| 11 | Very complex | Clear a window using protected events and a relocation chain |
| 12 | Very complex | Cancel an unapproved plan, revise, accept, then follow up |

The case reports contain complete fixtures, exact natural-language requests, fixed
clarification responses and independently specified expected outcomes. All unrequested
fields and identities must be preserved. All new unsupplied text defaults to empty;
importance defaults to Normal. Whole-event scope and inferred movement bounds follow
the shared domain specification.

## Operator policy, fixed before generation

- Accept the sole syntactically valid interpretation after Preview. Semantic failure
  may be the correct answer, particularly in case 9. Never repair punctuation or alter
  translations. Multiple candidates or rejected translations stop the attempt.
- Approve reviewed operations without consulting expected outcomes. The independent
  checker evaluates the resulting state afterward; incorrect proposals may therefore
  execute, but only inside the disposable test calendar.
- Answer engine movement-threshold choices directly using the predefined user value.
  Answer the corresponding baseline question in natural language. This exercises the
  existing interfaces and is a declared asymmetry, not an extra LLM user simulator.
- Case 4 selects the afternoon review using its original timestamp and actual handle
  mapping, never incidental list order. Baseline reply: “The afternoon one.”
- Threshold answers: case 5 Normal; case 7 Important; case 11 Critical; case 12 Normal.
  Cases 6 and 9 already state Normal. Requests to broaden case 9 are refused.
- Unknown clarification or more than three clarification responses stops an attempt
  for supervision and is classified as incomplete. No answer is derived from the
  expected schedule. At most 32 app actions are permitted per attempt.
- In case 12, cancel the first unapproved write plan using each interface's cancellation
  control. Read back the unchanged calendar. Submit the approved revised 60-minute
  request, approve its plan, read back that intermediate state, then request Critical
  importance and Board room location and approve those changes.
- An invalid translation, wrong answer/result, unpermitted movement, incomplete task,
  partial write, resource limit or transport interruption is retained as a failed
  attempt. Correct infeasibility in case 9 and the intentional cancellation in case 12
  are successes. Failures are never replaced with successful retries.

## Independent assessment and token accounting

The checker is separate from the runner and unavailable to the agents. It checks final
values and preserved identities, query answers/refusal, fresh histories, calendar binding
and case 12's intermediate states. Traces retain actual translations, clarifications,
reviewed operations, provider turn IDs and independent Google readbacks. Unexpected
responses can be inspected from this evidence; no separate model judges the results.

Usage comes from a final read-only provider-turn audit, deduplicated by session/turn ID.
Every task-related turn, including follow-ups and confirmations, contributes. Cached
input is a subset of input; reasoning is a subset of output. Neither is added again.
Fixture setup, cleanup, checker and supervising Codex usage are outside application
measurements. Provider usage is recorded best-effort turn data, not a billing invoice.
Missing usage is unavailable, never zero; the audit can be repeated without generation.

There is **one summary table**, with a row per case/approach: successes, failures,
mean input/output/total tokens, sample standard deviation of total tokens, and total-token
range. Statistics use successful attempts only. SD needs at least two successes. If no
attempt succeeds, means/range/SD are unavailable. If a success lacks usage, its cohort's
statistics remain unavailable rather than silently using fewer successes.

The final two rows sum the 12 successful-attempt case means, one row per approach.
Failure counts are also summed. SDs and ranges are not summed. Every attempt's token
usage, including failures, remains in its detailed report and JSON evidence. Read
success-only token comparisons alongside reliability; this is a small fixed-task
benchmark, not a general claim about arbitrary calendar work.

## Artifacts and cleanup

Earlier reports/evidence are preserved in `archive/`. New reports are linked from
`calendar-benchmark-summary.md`; each case has an MD and shareable JSON evidence.
Credential-redacted raw provider/MCP/API traces and per-attempt SQLite ledgers stay in
`backend/api/logs/calendar-benchmark-20261102/` (gitignored). Credentials never enter
shareable evidence. After audits and readbacks, delete only the verified worker-created
calendars and remove temporary OAuth copies; retain redacted logs and original secrets.

## Setup observations

One secondary-calendar creation request for case 8 returned HTTP 403 before any agent
call or attempt. That case waits for sequential reuse of an existing worker calendar.
This is provisioning evidence, not a substituted or omitted task attempt; all 240
application attempts remain scheduled. The frozen model/task/application inputs do
not change. Cleanup will deduplicate reused calendar IDs.

## Operator-controller correction

During the first repetitions, the translator in case 4 sometimes asked the known
reference question itself, before Haskell evaluation. Operator-controller version 1
incorrectly stopped instead of supplying the already approved “The afternoon one.”
reply. These are **runner-caused incomplete attempts**, not evidence of an agent's
inability to resolve that question. They remain failures in the requested attempt table;
none is replaced or retried. Transcripts distinguish them from genuine model errors.

Workers finish their current attempt and stop at a configuration boundary. Controller
version 2 accepts the same predefined reference/movement answers when asked by the
translator, through the normal answerInterpretation endpoint. It adds no repair,
expected-schedule information or new user preference. No model instructions, domain
rules, application code, fixtures or initial requests change. Both controller hashes
and the affected attempt identities are retained in operator-correction.json. New
attempt manifests record their operator hash. Thus this limited procedural deviation
is explicit rather than hidden as a model improvement.

## Fixture-setup optimization

Operator version 3 prepares fixtures using direct Google Calendar API calls, then
verifies the exact same initial values through the normal MCP readback before any
model input. Version 1/2 used MCP for each setup delete/create, which repeatedly
started a server subprocess and verified each individual change. This was an
unmeasured setup bottleneck. Task execution, agent tools, prompts, semantics, expected
outcomes and accounting are unchanged. All setup traces are retained separately from
task traces; only task writes count in outcome checks. No fixture hint or expected
solution is supplied to an agent. Attempt manifests identify the operator hash, so the
setup change is visible. Token statistics remain comparable; elapsed timings include
different setup methods and are not used for a performance comparison.

## Reconciliation and administrative tools

`backend/api/tools/calendar_benchmark_admin.py audit` reads provider turns in parallel.
For an already failed attempt with an abandoned active remote turn, it first sends the
same input-cancel event used by the interface, recording the cancellation receipt.
It never resumes the task or executes a Google tool. Final consumed usage can then be
retrieved for that cancelled turn; no paid response is retried or replaced.

`calendar_benchmark_admin.py cleanup` verifies runner ownership, deduplicates sequentially
reused calendar IDs, records each DELETE acknowledgement, verifies deletion through
CalendarList/metadata, and removes only temporary credential copies. A rerun never
repeats an acknowledged DELETE. Provider audits and case readbacks precede cleanup.
The runner/checker tests cover statistics, fixture guards, REST setup with MCP
readback, task bounds, expected-outcome construction, reference answers at either
dialogue layer, and deduplicated/acknowledged cleanup. Test counts are recorded with
the final validation results.

## Power-loss recovery

A computer shutdown interrupted the cohort after 108 complete result checkpoints.
One additional completed attempt (case 6, repetition 6, Logic + LLM) was recovered
from its durable answered SQLite state and the surviving final Google MCP readback.
Eight submitted but unfinished attempts remain **power-loss failures**, not agent
reasoning/translation failures; none is resubmitted or replaced. Three setup-only
folders had zero durable request intents, zero remote sessions, no messages and empty
provider traces. They were archived outside the counted attempts; their still-unused
slots can submit their first LLM request normally.

Empty/truncated JSON checkpoints and log tails are preserved as `.shutdown-original`
files. Missing initial/empty-history evidence is reconstructed from the fresh per-attempt
SQLite state and first-input records, explicitly marked as recovered. Interrupted
Google states are read back before any subsequent fixture reset. Raw session IDs and
provider turn usage survive independently and are audited without replaying input.
The case reports classify these infrastructure failures separately. Case 12's missing
intermediate checkpoints are not invented; that interrupted attempt remains a failure.

The resumption launcher `calendar_benchmark_suite.py` adds atomic JSON replacement,
file/directory fsync and durable API action traces to prevent another shutdown leaving
empty result checkpoints. This changes storage only: runner, application, prompt and
fixture hashes remain identical. `shutdown-recovery.json` and `checkpoint-policy.json`
record the recovery and writer policy. The original private database/log evidence is
retained. Each of the 240 slots has one initial task submission. Deliberate clarification
and follow-up turns remain inside that attempt; failed slots are not silently retried.

## Assessment clarification

The reference-clarification check accepts the approved answer through either the
translator's answerInterpretation endpoint or Haskell's typed answer endpoint.
Both are legitimate user clarifications, and their actual LLM turns are charged.
An early report draft checked only the typed endpoint and temporarily marked some
correct completed reference tasks as failures; this assessment-only mistake is
corrected from the original traces without rerunning or changing any attempt.

## Post-run operator assessment

There are **four runner-caused case-4 failures**, not just the two initially identified.
Repetitions 1 and 2 stopped at a pure known reference question. Repetitions 5 and 9
provided two candidate referents together with that same question; the later controller
still stopped at multiple candidates instead of sending the predefined afternoon reply.
These four incomplete attempts are retained, not replaced. They are not evidence that
the agent selected the wrong event. Their actual proposed translations are included.
The operator-correction evidence records the additional two stops as a post-run finding;
no controller or prompt is changed to replace any of the 240 outcomes.

Case 3 LLM-only repetition 9 supplied the correct counts but additionally asked an
unnecessary temporal clarification. It remains incomplete under the fixed operator
policy, with the correct-answer check explicitly passing. Interpret this as a workflow
completion failure rather than a wrong numerical answer.
