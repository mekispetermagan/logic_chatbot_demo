# Calendar case 5 — ten medium-reasoning repeats

**Result: 10/10 completed correctly. No missing-period errors, unsupported-scope refusals or repair prompts.**

This is a follow-up to the [original comparison](calendar-comparison-2026-10-28.md) and the [five low-reasoning repeats](calendar-case5-repeats-2026-10-28.md). Only the hybrid Calendar translation path is measured here.

## Test case

Selected week: 26 October–1 November 2026, Europe/Budapest. Fixed dialogue clock: Wednesday 28 October at 08:00 Budapest.

| Event | Thursday interval | Importance |
| --- | --- | --- |
| Preparation | 09:00–10:00 | Normal |
| Customer meeting | 09:30–10:30 | Important |

Locations and descriptions are empty. Request:

> Remove the clashes on Thursday morning with the least total weighted movement.

When the engine asks maximum movable importance, select **Important**, permitting both Normal and Important events to move. Expected result: Preparation moves to **10:30–11:30**; Customer meeting remains **09:30–10:30**. Durations, identities and non-time fields remain unchanged. Minimum weighted movement cost is **1.5**, compared with **2** for moving Customer meeting 30 minutes later.

## Controls and procedure

- `gpt-6-luna`, reasoning effort **medium**, Standard service tier. Actual saved API requests were inspected; settings were not inferred from defaults.
- The instruction text was byte-for-byte identical to the low-reasoning tests. Agent configuration differed only in reasoning effort and its derived configuration-hash metadata.
- Fresh database, empty chat history, fresh remote agent session and a dedicated isolated secondary calendar for every attempt. All ten sessions are distinct and separate from the earlier low sessions.
- Same initial event facts, user request, frozen time and private movement permission. Differences in provider IDs and assigned handle/order do not change event facts.
- Eight attempts (1, 2, 4, 5, 6, 8, 9 and 10) had byte-for-byte identical model input to the original missing-period failure. The other two differed only in event handles/order.
- A single valid translation candidate was previewed and accepted. The operator selected the predefined typed importance option; the concrete cloud proposal was approved. These steps used no additional model turns.
- No translation was edited, repaired, retried or replaced. Expected schedules were checked independently after execution. The ten attempts ran in two batches of five.
- The removal of the spending cap introduced no generation-setting or input difference: each fresh run had zero prior spending, so the earlier cap would not have blocked it either.

## Per-attempt outcomes and usage

All ten asked the expected permission question, returned valid punctuation and produced a readback matching the expected schedule. Original Google event identities were preserved. Each engine result reported proven minimum weighted movement cost **1.5**.

| Attempt | Accepted translation | Input | Output, including reasoning | Reasoning subset | Total |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 — PASS | `Remove clashes on thursday.` | 19,490 | 464 | 348 | 19,954 |
| 2 — PASS | `Remove clashes on thursday.` | 19,490 | 502 | 393 | 19,992 |
| 3 — PASS | `Remove clashes on thursday.` | 19,490 | 549 | 422 | 20,039 |
| 4 — PASS | `Remove clashes on thursday.` | 19,490 | 708 | 598 | 20,198 |
| 5 — PASS | `Remove clashes on thursday.` | 19,490 | 180 | 92 | 19,670 |
| 6 — PASS | `Remove clashes on thursday.` | 19,490 | 615 | 494 | 20,105 |
| 7 — PASS | `Remove clashes on thursday.` | 19,490 | 943 | 825 | 20,433 |
| 8 — PASS | `Remove clashes on thursday.` | 19,490 | 698 | 577 | 20,188 |
| 9 — PASS | `Remove clashes on thursday.` | 19,490 | 570 | 448 | 20,060 |
| 10 — PASS | `Remove clashes on thursday.` | 19,490 | 643 | 516 | 20,133 |
| **Total** | | **194,900** | **5,872** | **4,713** | **200,772** |
| **Average** | | **19,490.0** | **587.2** | **471.3** | **20,077.2** |

Counts come from a final read-only fetch of unique provider turns, deduplicated by session and turn ID. Each attempt used one model turn; all usage was available. Cached input was reported as zero throughout. Reasoning is included in output, and is not added to the total again. Setup, checker, supervision and cleanup usage is excluded.

## Comparison with low reasoning

| Cohort | Attempts | Completed | Missing-period rejection | Unsupported-scope response |
| --- | ---: | ---: | ---: | ---: |
| Original low attempt | 1 | 0 | 1 | 0 |
| Five fresh low repeats | 5 | 4 | 0 | 1 |
| Ten fresh medium repeats | 10 | 10 | 0 | 0 |

The earlier two non-completions belong to **six** low attempts (the original plus five repeats), not two failures in the five-repeat cohort. The original attempt was selected for follow-up because it failed; it is shown separately and is not pooled into an unbiased failure-rate estimate.

| Cohort | Average input | Average output | Average reasoning subset | Average total |
| --- | ---: | ---: | ---: | ---: |
| Five low repeats | 19,490.0 | 207.8 | 105.8 | 19,697.8 |
| Ten medium repeats | 19,490.0 | 587.2 | 471.3 | 20,077.2 |

Medium averaged **587.2 output tokens**, versus **207.8** at low effort. Input was unchanged at **19,490**. Average total token quantity rose **1.93%**. This is a token-count comparison, not a monetary-cost comparison; token categories have different prices. The low averages include its one incomplete scope refusal.

## Interpretation

Observed completion improved from **4/5 (80%)** in the fresh low cohort to **10/10 (100%)** at medium. This is encouraging evidence for the setting change, with no prompt or grammar edits. It does **not** establish a reliable improvement rate: the samples are small, unequal in size and collected sequentially rather than as an interleaved randomized experiment.

The specific missing-period omission did not recur in either follow-up cohort, so these repeats do not demonstrate that medium eliminated that particular error. The observed difference is that the low follow-up contained one scope refusal while medium contained none.

The morning/day policy was unchanged. All ten medium translations chose the supported whole-day repair operation. That has the intended target set in this fixture, where both events are morning-bounded, but does not establish general equivalence for calendars containing other Thursday events.

## Evidence and isolation

[JSON evidence](calendar-case5-medium-repeats-2026-10-28-evidence.json) contains actual model inputs/outputs, provider turns and usage, instruction hashes, configuration comparisons, API actions, initial/final Google readbacks and independent checks. Local redacted provider/MCP logs and databases are in `backend/api/logs/calendar-case5-medium-repeats-20261028/`.

Production calendar events, database, sessions and application code were unchanged by this experiment. All ten temporary calendars were deleted and their removal verified. Temporary OAuth copies were removed; the primary calendar remained present. No results or token totals in the earlier reports were replaced.
