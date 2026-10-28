# Five-case Calendar comparison — 28 October 2026

## Experiment

**Observed completion: Hybrid 4/5; LLM-only 5/5.** On the four mutually completed cases, Hybrid used 67.74% fewer total tokens (LLM-only used 3.10× the Hybrid total). Case 5 exposed a rejected translation and is reported as incomplete, not repaired or replaced.

This is a small supervised demonstration experiment, not a statistically powered
benchmark. It compares the implemented Calendar translator + Haskell engine with
the implemented LLM-only Calendar agent. Neither agent receives expected solutions.

Both use `gpt-6-luna`, low reasoning effort, the same shared domain specification,
real Google Calendar through the local MCP server, and the real FastAPI dialogue
routes. Requests are sent through an in-process FastAPI TestClient; the Flutter UI
is not involved. Each of the ten runs starts with an empty database, empty chat
history and a fresh remote agent session. Instructions and tools remain those of
the respective application modes. The translator additionally receives its
controlled-language grammar; the baseline does not.

The universe is 26 October–1 November 2026, Europe/Budapest. Application dialogue
clocks are fixed to Wednesday 28 October, 08:00 Budapest time. Provider, OAuth and
logging clocks remain real. This injection is confined to the runner process.

An isolated secondary calendar was created under the dedicated demo account.
Production data, sessions, SQLite database and calendar events are not changed.
The runner temporarily binds the existing calendar allowlist to that isolated
calendar **in its own process only**. Production guard code remains unchanged.
Fixtures are created/read back through MCP before each run. Cases, fixtures and user preferences were agreed before execution; this was not a formally preregistered statistical protocol. All fields below
must match between paired fixtures; provider-generated identities and metadata
are excluded from cross-run equality, but existing identities must be preserved
within each run. Unless stated otherwise, locations and descriptions are empty.
Only the listed events are present in each fixture.

Codex supervises the runner and supplies only the previously specified user preferences.
A unique translation candidate is previewed and accepted, and each cloud write
proposal is approved without consulting the expected final schedule. Expected
solutions are used afterward by a separate checker. Any unsupported response,
extra intervention, failure or deviation is reported explicitly. Selecting a
typed engine answer and answering the baseline in natural language exercise the
actual interfaces; this asymmetry is recorded rather than hidden.

Token accounting uses a final read-only fetch of provider turns, deduplicated by
`(session_id, turn_id)`. It includes every turn for each test, including subsequent
clarifications and final confirmations. Repeated usage displays in chat are not
summed. Cached input is a subset of input, and reasoning is a subset of output;
neither is added again. Fixture setup, checker and supervising-operator activity
are excluded. No separate model API is called to simulate a user or judge the results; Codex supervision itself is outside the measured application usage. Counts are the
provider's recorded best-effort usage, not a final billing statement; see
[OpenAI's usage contract](https://developers.openai.com/api/docs/guides/agents-api/observability).

## Case 1 — Schedule into an available gap

### Fixture and request

Friday 30 October:

| Event | Time | Importance |
| --- | --- | --- |
| Team meeting | 09:00–09:45 | Important |
| Mechanic | 11:00–11:30 | Normal |

Request: “Schedule a 60-minute videoconference on Friday morning, as early as
possible.” No location or description; default Normal importance.

Expected: create Videoconference at **09:45–10:45**, Normal. Preserve both existing
events and their fields. No movement permission is needed.

Checks: earliest-time selection, correct duration, no unnecessary clarification,
and no unintended changes.

<!-- CASE1 -->

### Observed outcomes

**Hybrid — PASS.** No clarification required. One translation was previewed/accepted and one creation was approved. Earliest slot and preserved fixtures verified.

**LLM-only — PASS.** No clarification required. Agent obtained live events and proposed one creation. Approval and readback produced the expected schedule.

Independent readback comparison matched the expected final state for both modes. All original event identities were preserved.

| Mode | Agent turns | Input | Cached input (subset) | Output | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Hybrid | 1 | 19,497 | 0 | 143 | 19,640 |
| LLM-only | 1 | 63,602 | 46,321 | 591 | 64,193 |

<!-- ENDCASE1 -->

## Case 2 — Make room, then change importance

### Fixture and request

Same Friday fixture as case 1, freshly restored.

Request: “Schedule a 90-minute videoconference on Friday morning, as early as
possible.” After no opening is reported, say “Make room.” When movement permission
is asked, authorize Normal events only. After scheduling is complete, say
“The videoconference is critical.” If questions are combined, supply only the
corresponding known preferences; do not volunteer permission in advance.

Expected: leave Team meeting unchanged; move Mechanic to **11:15–11:45**, Normal;
create Videoconference at **09:45–11:15**, then set its importance to Critical.
Minimum weighted movement cost is **0.25** (hours × weight).

Checks: initial infeasibility, permission before movement, minimum movement,
preserved duration and a follow-up reference to the created event.

<!-- CASE2 -->

### Observed outcomes

**Hybrid — PASS.** Initial schedule evaluation reported no free interval with no writes. Make room was translated separately. The engine asked maximum movable importance; the operator selected Normal (typed value 0). Minimum weighted movement cost 0.25 was proven. After approval, the critical-importance follow-up was translated and approved separately.

**LLM-only — PASS.** Initial request reported no free interval without mutation. Make room prompted an importance-threshold question. Operator answered Normal events only. Approved movement and creation matched the expected intervals; a separate follow-up set the new event to Critical.

Independent readback comparison matched the expected final state for both modes. All original event identities were preserved.

| Mode | Agent turns | Input | Cached input (subset) | Output | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Hybrid | 3 | 61,630 | 20,387 | 438 | 62,068 |
| LLM-only | 4 | 180,010 | 141,846 | 1,607 | 181,617 |

<!-- ENDCASE2 -->

## Case 3 — Resolve an ambiguous reference

### Fixture and request

Thursday 29 October:

| Event | Time | Importance |
| --- | --- | --- |
| Project review | 09:00–09:30 | Normal |
| Project review | 14:00–14:30 | Important |

Request: “Move the project review to 15:00 on Thursday.” Withhold the fact that the
user means the **afternoon** review until asked. Preserve its 30-minute duration.

Expected: clarify which review, then move only the afternoon event to
**15:00–15:30**, retaining Important importance. The morning review is unchanged.
This is an explicit move, not automatic rescheduling.

Checks: consequential ambiguity is resolved before mutation, event identity and
duration are preserved, and the other review is untouched.

<!-- CASE3 -->

### Observed outcomes

**Hybrid — PASS.** Engine clarified the ambiguous subject before writes. Operator selected the offered event handle mapped to the 14:00 original timestamp (value 0 in this run), not by list position. The single translated interval assignment preserved the 30-minute duration and Important importance.

**LLM-only — PASS.** Agent listed both reviews and asked which to move before any writes. Operator answered The afternoon review. Preserve its duration. Only that event moved to 15:00–15:30 and retained Important importance.

Independent readback comparison matched the expected final state for both modes. All original event identities were preserved.

| Mode | Agent turns | Input | Cached input (subset) | Output | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Hybrid | 1 | 19,518 | 0 | 182 | 19,700 |
| LLM-only | 2 | 81,179 | 47,137 | 548 | 81,727 |

<!-- ENDCASE3 -->

## Case 4 — Impossibility under movement permission

### Fixture and request

Friday 30 October:

| Event | Time | Importance |
| --- | --- | --- |
| Planning | 09:00–10:00 | Important |
| Customer call | 10:00–11:00 | Critical |
| Administration | 11:00–12:00 | Normal |

Request: “Make room for a 90-minute training session on Friday morning.” When
asked, allow only Normal events to move. Do not widen the window, shorten the
session or authorize moving higher-importance events.

Expected: report that no permitted solution exists; **the entire calendar remains
unchanged**. Unchanged data alone is insufficient to pass: the system must also
complete the task with the correct infeasibility explanation.

Checks: permission is respected, the period envelope is preserved, no constraint
is silently relaxed, and no partial mutations occur.

Fixture limitation: the original events already occupy all three hours and remain
morning-bounded. Even permitting higher-importance movements cannot accommodate
an additional 90 minutes without another relaxation. This case checks refusal
and non-mutation, but does not isolate importance-threshold enforcement as the
cause of infeasibility.

<!-- CASE4 -->

### Observed outcomes

**Hybrid — PASS.** The engine asked maximum movable importance; operator selected Normal (value 0). It then returned the expected domain infeasibility result (API dialogue status error), not a transport failure. No task writes occurred.

**LLM-only — PASS.** Agent asked the movement threshold; operator answered Normal events only. It then explained infeasibility and made no task writes. Its suggested relaxations were not accepted or executed.

Independent readback comparison matched the expected final state for both modes. All original event identities were preserved.

| Mode | Agent turns | Input | Cached input (subset) | Output | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Hybrid | 1 | 19,607 | 0 | 122 | 19,729 |
| LLM-only | 2 | 47,376 | 14,621 | 647 | 48,023 |

<!-- ENDCASE4 -->

## Case 5 — Minimum weighted movement

### Fixture and request

Thursday 29 October:

| Event | Time | Importance |
| --- | --- | --- |
| Preparation | 09:00–10:00 | Normal |
| Customer meeting | 09:30–10:30 | Important |

Request: “Remove the clashes on Thursday morning with the least total weighted
movement.” When asked, allow Normal and Important events to move.

Expected: move Preparation to **10:30–11:30**; leave Customer meeting at
**09:30–10:30**. Preserve all durations and importance levels. Cost is
**1.5 × 1 = 1.5**. Moving the Important meeting 30 minutes later instead costs
**0.5 × 4 = 2**, so the shorter shift is worse under the approved objective.

Checks: weighted rather than unweighted minimization, clash freedom, preserved
durations and morning containment.

<!-- CASE5 -->

### Observed outcomes

**Hybrid — FAIL — incomplete task.** The translator proposed Remove clashes on thursday without the required final period. Syntax validation rejected it before engine evaluation and before any task writes. No importance question was reached. The operator supplied no grammar fix or retry; the task stopped for review with the initial clash still present.

**LLM-only — PASS.** Agent asked the movement threshold before proposing writes. Operator permitted Normal and Important events. After approval it moved only Preparation to 10:30–11:30, preserved both event identities/durations/importance, and correctly explained minimum weighted cost 1.5 versus 2 for moving Customer meeting.

The Hybrid calendar retained the original 09:30–10:00 overlap. The Haskell optimizer was never reached, so this is a translation failure, not evidence of an optimization failure. LLM-only achieved the expected minimum-cost final state. No successful Hybrid retry is substituted for this result.

| Mode | Agent turns | Input | Cached input (subset) | Output | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Hybrid | 1 | 19,490 | 0 | 92 | 19,582 |
| LLM-only | 2 | 64,472 | 30,692 | 886 | 65,358 |

<!-- ENDCASE5 -->

## Token summary

<!-- SUMMARY -->

**Completion: Hybrid 4/5; LLM-only 5/5.** The five-case totals below include the incomplete Hybrid case 5. They measure consumption across the test suite, not the token cost of equal completed work. The excluded operator attempt is not in these totals.

| Case / aggregate | Mode | Agent turns | Input | Cached input (subset) | Output | Total |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | Hybrid | 1 | 19,497 | 0 | 143 | 19,640 |
| 1 | LLM-only | 1 | 63,602 | 46,321 | 591 | 64,193 |
| 2 | Hybrid | 3 | 61,630 | 20,387 | 438 | 62,068 |
| 2 | LLM-only | 4 | 180,010 | 141,846 | 1,607 | 181,617 |
| 3 | Hybrid | 1 | 19,518 | 0 | 182 | 19,700 |
| 3 | LLM-only | 2 | 81,179 | 47,137 | 548 | 81,727 |
| 4 | Hybrid | 1 | 19,607 | 0 | 122 | 19,729 |
| 4 | LLM-only | 2 | 47,376 | 14,621 | 647 | 48,023 |
| 5 (incomplete) | Hybrid | 1 | 19,490 | 0 | 92 | 19,582 |
| 5 | LLM-only | 2 | 64,472 | 30,692 | 886 | 65,358 |
| **Total, 5 cases** | **Hybrid** | 7 | 139,742 | 20,387 | 977 | 140,719 |
| **Total, 5 cases** | **LLM-only** | 11 | 436,639 | 280,617 | 4,279 | 440,918 |
| **Average per case** | **Hybrid** | 1.40 | 27,948.40 | 4,077.40 | 195.40 | 28,143.80 |
| **Average per case** | **LLM-only** | 2.20 | 87,327.80 | 56,123.40 | 855.80 | 88,183.60 |

### Four mutually completed cases (1–4)

| Mode | Agent turns | Input | Cached input (subset) | Output | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Hybrid — total | 6 | 120,252 | 20,387 | 885 | 121,137 |
| LLM-only — total | 9 | 372,167 | 249,925 | 3,393 | 375,560 |
| Hybrid — average | 1.50 | 30,063.00 | 5,096.75 | 221.25 | 30,284.25 |
| LLM-only — average | 2.25 | 93,041.75 | 62,481.25 | 848.25 | 93,890.00 |

For cases 1–4, Hybrid used **67.74% fewer total tokens**; LLM-only used **3.10×** the Hybrid total. Input reduction was 67.69%; output reduction was 73.92%. These are aggregate ratios, not averages of per-case percentage reductions.

### Excluded operator attempt

An initial Case 3 Hybrid attempt was excluded because Codex selected numeric handle `#1` without first resolving its Google-ID mapping. In that run `#1` denoted the morning review, contrary to the user preference. The attempt reached another clarification and made no task writes. The corrected run used a freshly restored fixture and a fresh session, and resolved the afternoon event from its timestamp and returned handle mapping. A regression test now checks reversed handle ordering. This exclusion was caused by the operator, not an agent task failure.

| Mode | Agent turns | Input | Cached input (subset) | Output | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Excluded Case 3 Hybrid | 1 | 19,518 | 0 | 143 | 19,661 |

Total recorded application usage including this excluded attempt: **601,298 tokens**. No agent failure was retried or removed from the five-case results.

<!-- ENDSUMMARY -->

## Evidence and reproduction

Runner: [calendar_comparison.py](../../backend/api/tools/calendar_comparison.py).
Independent checker: [calendar_comparison_check.py](../../backend/api/tools/calendar_comparison_check.py).
Offline checker/accounting tests: [test_calendar_comparison.py](../../backend/api/tests/test_calendar_comparison.py).

<!-- EVIDENCE -->

The [shareable JSON evidence](calendar-comparison-2026-10-28-evidence.json)
contains fixtures, final Google event readbacks, assessments, user/action traces,
returned translations and validation errors, all provider turn IDs and recorded
usage, and the excluded attempt. Totals are calculated from those unique turns,
not from the repeated chat usage labels. All usage was present at the final audit.

Checks passed for all ten included runs: matched paired starting fixtures, empty
initial histories, distinct fresh sessions, frozen context time, preserved original
event identities, and all MCP event access bound to the isolated secondary calendar.
Full credential-redacted provider exchanges and MCP traces remain locally under
`backend/api/logs/calendar-comparison-20261028/`, alongside per-run SQLite ledgers.
Those local files are gitignored; the exported evidence contains no credentials.

The isolated calendar was deleted after final readbacks and its absence verified.
Temporary OAuth credential/token copies were removed; original credential files,
production events and the production application database were left unchanged.

Live runner order: Case 1 Hybrid then LLM-only; Case 2 LLM-only then Hybrid;
Case 3 excluded Hybrid attempt, corrected Hybrid run, then LLM-only; Case 4
LLM-only then Hybrid; Case 5 Hybrid then LLM-only. No production parser, grammar,
agent prompt or semantic evaluator was changed during the experiment.

For another experiment, export the normal backend `.env` and use a **new private,
gitignored run directory**. Run `calendar_comparison.py --directory <dir> provision`,
then `run <case> <symbolic|llm-only>`. The runner pauses at clarifications or unsupported
responses. `step` takes the actual API action JSON; `answer-event <case> 14:00` resolves
a symbolic reference-choice option by initial timestamp. Do not assume list order
matches handles. Each paired run restores the fixture before submitting its request.
Use `audit` to fetch usage without generating new turns; `cleanup` removes only the
verified runner-created secondary calendar. Export evidence with the independent
checker. Rejected translations remain failed/incomplete unless an explicit repair
policy is defined for a future experiment.

Offline runner/checker validation: 8 tests passed (deduplication, missing usage,
wrong durations, preserved identities, unequal fixtures, reversed reference
ordering, rejecting a primary-calendar manifest, and read-only cleanup after an acknowledged deletion).

<!-- ENDEVIDENCE -->

## Limitations

One observation per mode per case cannot establish variance, significance or a
general efficiency claim. Fresh sessions do not guarantee cold prompt caches;
cache counts are reported separately. The inputs and context formats differ by
architecture, which is part of the end-to-end comparison. No assertion is made
that both modes receive equally sized prompts. Human clarification supervision
and automatic review clicks replace UI interaction and are disclosed above.
The earlier exploratory comparison with unequal fixtures/history is excluded.


## Follow-up: repeatability of the case 5 failure

A [separate five-repeat follow-up](calendar-case5-repeats-2026-10-28.md) found no further missing-period omissions: four attempts completed and one returned an unsupported-scope response. These follow-up runs do not change the original observations or token totals above.
