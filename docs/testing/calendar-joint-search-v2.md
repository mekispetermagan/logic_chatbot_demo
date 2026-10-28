# Joint scheduling search: implementation revision

The original [240-attempt benchmark](calendar-benchmark-summary.md) remains unchanged. Its case 10 reached the 100,000-node search limit in all ten hybrid attempts. This revision adds general forward checking and a distinct-date matching feasibility check to the Haskell joint scheduler. The existing candidate, check and node limits remain 200,000, 1,000,000 and 100,000 respectively. Grammar, priorities and domain rules are unchanged.

The solver preserves event and candidate order. It removes only placements incompatible with an already selected event, and rejects a distinct-date branch only when the remaining candidate dates cannot be matched to distinct events. Complete witnesses are checked against one another and against fixed events. Thus the first complete assignment retains the existing earliest-in-listed-order meaning.

## Original case 10: solver-only replay

All ten saved hybrid translations were evaluated against their original recorded initial events and frozen contexts using both the preserved original executable and the revised executable. Each original executable run exhausted the 100,000-node limit. Every revised run returned the expected four-event plan for review using **42 nodes**, 4,281 checks and 145 candidates. No existing event was changed in the proposed plans.

This is a **solver-only replay** of existing translations, not ten new live end-to-end agent trials. It incurred no new LLM token usage and did not write to Google Calendar. It does not replace the original benchmark failures or change their statistics.

## Correctness and fresh variants

The planning test compares the search with an independently exhaustive oracle across 686 small candidate-domain instances and 150 further deterministic variants, checking both the first solution and up to 64 solutions in their original order. It also covers a Hall-deficient date assignment, an augmenting path, same-day adjacency, cross-day starts, fixed events that already clash, and exhausted check budgets.

Seven additional controlled-language scenarios passed through the real Haskell bridge: Hall deficiency, date reassignment, impossible same-day packing, exact overnight occupancy, two Budapest/UTC date-boundary cases, and eight distinct dates within a seven-day week. These are engineering validation cases, not an independent market benchmark.

[Machine-readable replay and validation evidence](calendar-joint-search-v2-evidence.json) includes the saved translations, both runtime hashes, counters, proposed plans and fresh-case results. The original report files were checked against their pre-change hashes.
