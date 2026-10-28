# Calendar benchmark: 240 Luna Medium attempts

Recorded attempts: **240/240**. Selected week: **2–8 November 2026**, Europe/Budapest. Model: `gpt-6-luna`, reasoning: `medium`.

[Protocol](calendar-benchmark-protocol.md). Earlier experiments are in [archive](archive/).

## Successful-attempt token statistics

Means, sample standard deviations and ranges use successful attempts only. Failures remain in the failure column and detailed evidence. No failed attempt is replaced. Missing usage is unavailable, never zero. SD requires at least two successes. The sum rows add the 12 case means; SD and ranges are not additive.

| Case | Approach | Successes | Failures | Mean input | Mean output | Mean total | Total SD | Total min–max |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | Logic + LLM | 9 | 1 | 20,916.0 | 140.9 | 21,056.9 | 12.4 | 21,037–21,077 |
| 1 | LLM-only | 10 | 0 | 79,363.0 | 731.9 | 80,094.9 | 17,382.6 | 66,400–100,513 |
| 2 | Logic + LLM | 8 | 2 | 20,853.0 | 290.9 | 21,143.9 | 27.4 | 21,107–21,180 |
| 2 | LLM-only | 10 | 0 | 71,520.3 | 580.3 | 72,100.6 | 26,879.4 | 49,053–113,889 |
| 3 | Logic + LLM | 10 | 0 | 21,035.0 | 186.9 | 21,221.9 | 19.0 | 21,194–21,251 |
| 3 | LLM-only | 9 | 1 | 32,125.4 | 678.3 | 32,803.8 | 268.6 | 32,323–33,196 |
| 4 | Logic + LLM | 3 | 7 | 35,518.3 | 902.3 | 36,420.7 | 12,917.6 | 21,507–44,103 |
| 4 | LLM-only | 9 | 1 | 87,889.4 | 967.6 | 88,857.0 | 24,120.5 | 67,297–120,042 |
| 5 | Logic + LLM | 9 | 1 | 20,930.0 | 258.8 | 21,188.8 | 53.5 | 21,140–21,293 |
| 5 | LLM-only | 10 | 0 | 115,584.6 | 3,085.2 | 118,669.8 | 44,130.1 | 90,366–226,157 |
| 6 | Logic + LLM | 10 | 0 | 20,789.0 | 181.9 | 20,970.9 | 27.3 | 20,923–21,018 |
| 6 | LLM-only | 10 | 0 | 74,208.9 | 1,007.6 | 75,216.5 | 34,075.6 | 49,575–151,411 |
| 7 | Logic + LLM | 9 | 1 | 20,895.0 | 173.2 | 21,068.2 | 18.5 | 21,042–21,104 |
| 7 | LLM-only | 8 | 2 | 101,984.9 | 2,284.6 | 104,269.5 | 41,624.1 | 70,092–194,220 |
| 8 | Logic + LLM | 7 | 3 | 20,751.0 | 396.3 | 21,147.3 | 215.2 | 20,962–21,505 |
| 8 | LLM-only | 10 | 0 | 66,840.8 | 1,177.4 | 68,018.2 | 5,230.5 | 66,135–82,898 |
| 9 | Logic + LLM | 10 | 0 | 21,025.0 | 181.8 | 21,206.8 | 18.1 | 21,176–21,237 |
| 9 | LLM-only | 9 | 1 | 39,642.9 | 603.4 | 40,246.3 | 9,267.7 | 32,304–50,452 |
| 10 | Logic + LLM | 0 | 10 | — | — | — | — | — |
| 10 | LLM-only | 9 | 1 | 105,254.8 | 1,938.4 | 107,193.2 | 39,655.7 | 72,484–183,707 |
| 11 | Logic + LLM | 10 | 0 | 21,297.0 | 313.2 | 21,610.2 | 68.8 | 21,521–21,726 |
| 11 | LLM-only | 8 | 2 | 145,404.1 | 4,578.6 | 149,982.8 | 19,818.9 | 128,455–180,133 |
| 12 | Logic + LLM | 10 | 0 | 66,795.2 | 896.2 | 67,691.4 | 254.8 | 67,322–68,185 |
| 12 | LLM-only | 8 | 2 | 239,514.2 | 3,865.8 | 243,380.0 | 61,301.1 | 188,688–364,331 |
| **Sum of case means** | Logic + LLM | 95 | 25 | — | — | — | — | — |
| **Sum of case means** | LLM-only | 110 | 10 | 1,159,333.4 | 21,499.2 | 1,180,832.6 | — | — |

## Case reports

- [1. Earliest available gap](calendar-benchmark-case-01.md)
- [2. Edit several fields](calendar-benchmark-case-02.md)
- [3. Count critical events and overlapping pairs](calendar-benchmark-case-03.md)
- [4. Ambiguous reference](calendar-benchmark-case-04.md)
- [5. Make room with limited permission](calendar-benchmark-case-05.md)
- [6. Free a straightforward interval](calendar-benchmark-case-06.md)
- [7. Minimum weighted clash repair](calendar-benchmark-case-07.md)
- [8. Joint scheduling with backtracking](calendar-benchmark-case-08.md)
- [9. Refuse insufficient movement permission](calendar-benchmark-case-09.md)
- [10. Joint scheduling across alternative days](calendar-benchmark-case-10.md)
- [11. Free a window through a relocation chain](calendar-benchmark-case-11.md)
- [12. Cancel, revise, and follow up](calendar-benchmark-case-12.md)

## Recorded outcomes

- Logic + LLM: 95/120 completed successfully. Failure categories: multiple interpretations requiring user review (3), runner stopped at a known clarification (4), computer shutdown (3), Haskell search limit (10), translation reused the old title after renaming (2), translation used an unbound pronoun (3).
  Full sum of case means is unavailable while cases 10 have no successful accounted attempts.
- LLM-only: 110/120 completed successfully. Failure categories: execution_exception:RuntimeError (1), incorrect_answer_or_final_state (1), computer shutdown (5), transport interruption or partial result (2), unresolved or repeated clarification (1).

## Evidence and limitations

Each attempt used a fresh local database/history and remote session. Initial fixtures were verified from Google. Expected outcomes were checked separately and were never supplied to either agent. Case 12 includes intermediate readbacks. Provider usage is deduplicated by session/turn identity; cached input and reasoning output are subsets, not additions.

Hybrid engine clarifications use native typed controls; LLM-only clarification replies use ordinary English. Translator-level clarification replies still consume LLM turns. These results compare the implemented interfaces, including structured answers, rather than isolating algorithmic reasoning alone. The operator policy accepts one valid translation and reviewed changes without consulting the expected outcome. Unknown clarification, invalid translation, partial/transport interruption or excessive dialogue terminates the attempt and is reported. No repair retries or algorithm/prompt changes occur. A versioned operator correction handles predefined translator questions; four runner-caused reference-review stops remain failures and are documented in the protocol. The dedicated disposable calendars contain no concurrent user edits.

Full credential-redacted provider/MCP/API traces and SQLite ledgers are stored locally under the gitignored benchmark directory. The per-case JSON contains shareable transcripts, outcomes, token counts and provider turn IDs. No live-demo calendar or production database is used.

Case 3 has three pairwise-overlapping events, so the affected-event count also equals three; the checker requires pair wording/query units, but this fixture alone does not numerically distinguish the two counting methods. These are descriptive results for 12 fixed tasks with 10 repetitions per approach, not a general performance guarantee. Success-only token comparisons must be read together with failure counts.

## Verification and cleanup

- All 240 unique attempt slots are present; starting fixtures, histories, model/reasoning settings and calendar bindings were checked.
- Independent fraction-based means and variance calculations match the reported statistics. Application, prompt and task hashes match the frozen inputs.
- 22 offline runner/checker/cleanup checks passed. Actual write traces passed movement-permission, date/period and unchanged-field checks.
- All successful attempts have complete provider usage. 1 failed provider turn has unavailable usage, shown as unavailable rather than zero.
- Eight shutdown interruptions and four runner-caused reference-review stops remain in failure counts; no failed attempt was replaced.

Deleted **11 unique disposable calendars** (case 8 reused case 3’s calendar sequentially), verified that the primary demo calendar remains present, and removed temporary OAuth copies. The live-demo calendar and production database were not used for test operations.
