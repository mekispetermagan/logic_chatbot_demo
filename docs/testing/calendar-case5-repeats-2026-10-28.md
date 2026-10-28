# Calendar case 5 — five fresh repeats

Follow-up to the [five-case comparison](calendar-comparison-2026-10-28.md). The original case failed because the translator omitted the required final period.

**The missing-period failure did not recur in five new attempts. Four completed the task; one returned an unsupported-scope response without producing a command.**

## Conditions

- Same request: “Remove the clashes on Thursday morning with the least total weighted movement.”
- Same fixture: Normal Preparation, Thursday 09:00–10:00; Important Customer meeting, Thursday 09:30–10:30. Empty location and description.
- Same model (`gpt-6-luna`), low reasoning effort, frozen Wednesday 28 October 2026 at 08:00 Budapest, and selected week 26 October–1 November.
- Fresh database, fresh remote session and isolated secondary calendar for each attempt. No correction prompts or grammar repairs.
- The full agent configuration matched the original. Instruction text was byte-for-byte identical.
- Repeats 2, 3 and 5 also had byte-for-byte identical model input to the original failed attempt. Repeats 1 and 4 differed only in assigned event handles and event ordering; all event facts were identical.
- When the engine asked maximum movable importance, the operator selected Important (Normal and Important may move), as specified in the original test.

## Results

| Repeat | Outcome | Returned command | Input tokens | Output tokens | Total tokens |
| --- | --- | --- | ---: | ---: | ---: |
| 1 | Completed; expected minimum cost 1.5 | `Remove clashes on thursday, choosing ask.` | 19,490 | 339 | 19,829 |
| 2 | Completed; expected minimum cost 1.5 | `Remove clashes on thursday.` | 19,490 | 85 | 19,575 |
| 3 | Completed; expected minimum cost 1.5 | `Remove clashes on thursday.` | 19,490 | 330 | 19,820 |
| 4 | Stopped: morning/day scope | None — unsupported response | 19,490 | 200 | 19,690 |
| 5 | Completed; expected minimum cost 1.5 | `Remove clashes on thursday.` | 19,490 | 85 | 19,575 |
| **Total** | | | **97,450** | **1,039** | **98,489** |
| **Average** | | | **19,490.0** | **207.8** | **19,697.8** |

Counts come from unique provider turns; cached input was reported as zero in all five. Each attempt used one model turn. Typed importance answers and write approvals added no model turns. Setup, read-only accounting and cleanup are excluded.

All four completed runs moved Preparation to **10:30–11:30**, left Customer meeting at **09:30–10:30**, preserved identities and non-time fields, and reported weighted movement cost **1.5**.

## Different response in repeat 4

The translator returned `unsupported`, explaining that the controlled language repairs a whole day and cannot restrict the target set to morning-only clashes. It produced no executable translation, so this was **not another punctuation failure**. The calendar remained unchanged.

This refers to a real language restriction: the supported family is “Remove clashes on a specified day.” In this particular fixture all events are morning-bounded, so whole-Thursday repair achieves the intended outcome; that equivalence does not hold for arbitrary fixtures. The refusal therefore deserves separate scope/translation review rather than being counted as a missing-period recurrence.

## Interpretation

The original punctuation omission is **intermittent, not consistently reproducible under these conditions**. Three exact-input repeats succeeded. Across the original case and these five follow-ups there were four completed tasks, one missing-period rejection and one unsupported-scope response. This small sample does not establish a failure probability or rule out recurrence. The follow-up does not replace the failed observation in the original comparison.

## Evidence and isolation

[JSON evidence](calendar-case5-repeats-2026-10-28-evidence.json) contains the original failed output, all five new raw model outputs, exact submitted model inputs, configuration-match checks, event readbacks, transcripts, provider turn IDs and usage. Full redacted logs and per-run databases are retained locally under `backend/api/logs/calendar-case5-repeats-20261028/`.

Five initial setup invocations failed before any model submission. They were rerun using absolute run-directory paths and are not counted as translation attempts. No follow-up model response was resubmitted or given a repair prompt.

All five temporary calendars were deleted and absence verified. Temporary OAuth copies were removed. Production calendar data, database, agent sessions, prompts, grammar and application code were unchanged.
