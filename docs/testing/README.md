# Calendar testing

The current experiment compares Logic + LLM with LLM-only using Luna Medium,
12 tasks, and 10 attempts per task/approach. The selected week is 2–8 November 2026.

- [Protocol and assessment rules](calendar-benchmark-protocol.md)
- [Results, success-only token averages, variation and failure counts](calendar-benchmark-summary.md)
- [Machine-readable summary](calendar-benchmark-summary.json)
- [Earlier experiments](archive/)

The summary links the detailed specification, outcomes, transcripts and JSON evidence
for each case. During execution, it explicitly states how many of the 240 attempts
are recorded; partial statistics are provisional. Failed attempts remain in the reports.

Runner: `backend/api/tools/calendar_benchmark.py`.
Independent checker/report generator: `backend/api/tools/calendar_benchmark_check.py`.
Public task fixtures: `backend/api/tools/calendar_benchmark_cases.py`.
Offline tests: `backend/api/tests/test_calendar_benchmark.py`.

Credentials and raw private traces stay outside these documents, in gitignored storage.
