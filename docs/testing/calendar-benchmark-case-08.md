# Case 8: Joint scheduling with backtracking

Complexity: Complex. Week: 2–8 November 2026, Europe/Budapest.

## Initial events

| Date | Title | Time | Importance | Location | Description |
| --- | --- | --- | --- | --- | --- |
| — | Empty calendar | — | — | — | — |

## Request and user policy

Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

## Expected outcome

| Date | Event | Interval | Importance | Location | Description |
| --- | --- | --- | --- | --- | --- |
| 2026-11-05 | Review | 09:00–11:00 | Normal |  |  |
| 2026-11-05 | Workshop | 11:00–12:00 | Normal |  |  |

All existing identities and unrequested fields must be preserved.

## Attempt results

Token counts include all task turns; failures are retained here but excluded from summary means.

| Repeat | Approach | Outcome | Input | Output | Total | Explanation |
| ---: | --- | --- | ---: | ---: | ---: | --- |
| 1 | LLM-only | PASS | 65404 | 1205 | 66609 | Passed all independent checks |
| 1 | Logic + LLM | PASS | 20751 | 230 | 20981 | Passed all independent checks |
| 2 | LLM-only | PASS | 65139 | 1089 | 66228 | Passed all independent checks |
| 2 | Logic + LLM | PASS | 20751 | 754 | 21505 | Passed all independent checks |
| 3 | LLM-only | PASS | 65167 | 1113 | 66280 | Passed all independent checks |
| 3 | Logic + LLM | PASS | 20751 | 211 | 20962 | Passed all independent checks |
| 4 | LLM-only | PASS | 81587 | 1311 | 82898 | Passed all independent checks |
| 4 | Logic + LLM | PASS | 20751 | 216 | 20967 | Passed all independent checks |
| 5 | LLM-only | PASS | 65154 | 1215 | 66369 | Passed all independent checks |
| 5 | Logic + LLM | PASS | 20751 | 529 | 21280 | Passed all independent checks |
| 6 | LLM-only | PASS | 65274 | 1192 | 66466 | Passed all independent checks |
| 6 | Logic + LLM | FAIL | 20751 | 787 | 21538 | multiple interpretations requiring user review |
| 7 | LLM-only | PASS | 65345 | 1229 | 66574 | Passed all independent checks |
| 7 | Logic + LLM | FAIL | 20751 | 997 | 21748 | multiple interpretations requiring user review |
| 8 | LLM-only | PASS | 65064 | 1171 | 66235 | Passed all independent checks |
| 8 | Logic + LLM | PASS | 20751 | 553 | 21304 | Passed all independent checks |
| 9 | LLM-only | PASS | 65031 | 1104 | 66135 | Passed all independent checks |
| 9 | Logic + LLM | FAIL | 20751 | 911 | 21662 | multiple interpretations requiring user review |
| 10 | LLM-only | PASS | 65243 | 1145 | 66388 | Passed all independent checks |
| 10 | Logic + LLM | PASS | 20751 | 281 | 21032 | Passed all independent checks |

### Repeat 1 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Scheduled and verified both events for Thursday, November 5, 2026 (Budapest time). The week had no existing in-scope events. **Review:** 09:00–11:00. **Workshop:** 11:00–12:00, the earliest morning start that avoids overlapping the Review.

### Repeat 1 — Logic + LLM

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

**machine:** Week 2026-11-02–2026-11-08 (Europe/Budapest). Evaluation completed.
schedule events jointly [event lasting 60 minutes within thursday morning with title "Workshop"; event lasting 120 minutes within starting at thursday at 09:00 with title "Review"], choosing earliest in listed order.
Complete lexicographic earliest joint schedule in listed order. Existing events remain fixed.
#0 "Workshop" 2026-11-05 11:00 Europe/Budapest (UTC+01:00) – 2026-11-05 12:00 Europe/Budapest (UTC+01:00)
#1 "Review" 2026-11-05 09:00 Europe/Budapest (UTC+01:00) – 2026-11-05 11:00 Europe/Budapest (UTC+01:00)

**machine:** All proposed changes were read back and verified. Google Calendar is current.

### Repeat 2 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Both events were created and verified for Thursday, November 5 (Budapest time):

- Review: 09:00–11:00
- Workshop: 11:00–12:00

The Workshop is at the earliest possible time within Thursday morning that avoids overlapping the Review.

### Repeat 2 — Logic + LLM

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

**machine:** Week 2026-11-02–2026-11-08 (Europe/Budapest). Evaluation completed.
schedule events jointly [event lasting 60 minutes within thursday morning with title "Workshop"; event lasting 120 minutes within starting at thursday at 09:00 with title "Review"], choosing earliest in listed order.
Complete lexicographic earliest joint schedule in listed order. Existing events remain fixed.
#0 "Workshop" 2026-11-05 11:00 Europe/Budapest (UTC+01:00) – 2026-11-05 12:00 Europe/Budapest (UTC+01:00)
#1 "Review" 2026-11-05 09:00 Europe/Budapest (UTC+01:00) – 2026-11-05 11:00 Europe/Budapest (UTC+01:00)

**machine:** All proposed changes were read back and verified. Google Calendar is current.

### Repeat 3 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Both events are confirmed for Thursday, November 5, 2026 (Europe/Budapest): Review, 09:00–11:00; Workshop, 11:00–12:00. This is the earliest feasible Workshop start given the fixed Review time, and the events do not overlap.

### Repeat 3 — Logic + LLM

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

**machine:** Week 2026-11-02–2026-11-08 (Europe/Budapest). Evaluation completed.
schedule events jointly [event lasting 60 minutes within thursday morning with title "Workshop"; event lasting 120 minutes within starting at thursday at 09:00 with title "Review"], choosing earliest in listed order.
Complete lexicographic earliest joint schedule in listed order. Existing events remain fixed.
#0 "Workshop" 2026-11-05 11:00 Europe/Budapest (UTC+01:00) – 2026-11-05 12:00 Europe/Budapest (UTC+01:00)
#1 "Review" 2026-11-05 09:00 Europe/Budapest (UTC+01:00) – 2026-11-05 11:00 Europe/Budapest (UTC+01:00)

**machine:** All proposed changes were read back and verified. Google Calendar is current.

### Repeat 4 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Both events are confirmed for Thursday, November 5 (Europe/Budapest):

- Workshop: 11:00–12:00
- Review: 09:00–11:00

The calendar had no existing events in the selected week. Since the Review occupies 09:00–11:00 and the events cannot overlap, 11:00 is the earliest available Workshop start within Thursday morning. The events meet at 11:00 without overlapping.

### Repeat 4 — Logic + LLM

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

**machine:** Week 2026-11-02–2026-11-08 (Europe/Budapest). Evaluation completed.
schedule events jointly [event lasting 60 minutes within thursday morning with title "Workshop"; event lasting 120 minutes within starting at thursday at 09:00 with title "Review"], choosing earliest in listed order.
Complete lexicographic earliest joint schedule in listed order. Existing events remain fixed.
#0 "Workshop" 2026-11-05 11:00 Europe/Budapest (UTC+01:00) – 2026-11-05 12:00 Europe/Budapest (UTC+01:00)
#1 "Review" 2026-11-05 09:00 Europe/Budapest (UTC+01:00) – 2026-11-05 11:00 Europe/Budapest (UTC+01:00)

**machine:** All proposed changes were read back and verified. Google Calendar is current.

### Repeat 5 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Scheduled and verified for Thursday, November 5, in Europe/Budapest: Review, 09:00–11:00; Workshop, 11:00–12:00. The selected week had no existing in-scope events, and the two events are adjacent without overlap.

### Repeat 5 — Logic + LLM

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

**machine:** Week 2026-11-02–2026-11-08 (Europe/Budapest). Evaluation completed.
schedule events jointly [event lasting 60 minutes within thursday morning with title "Workshop"; event lasting 120 minutes within starting at thursday at 09:00 with title "Review"], choosing earliest in listed order.
Complete lexicographic earliest joint schedule in listed order. Existing events remain fixed.
#0 "Workshop" 2026-11-05 11:00 Europe/Budapest (UTC+01:00) – 2026-11-05 12:00 Europe/Budapest (UTC+01:00)
#1 "Review" 2026-11-05 09:00 Europe/Budapest (UTC+01:00) – 2026-11-05 11:00 Europe/Budapest (UTC+01:00)

**machine:** All proposed changes were read back and verified. Google Calendar is current.

### Repeat 6 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Both events were created and verified for Thursday, November 5, 2026 (Europe/Budapest): Workshop, 11:00–12:00; Review, 09:00–11:00. The selected week had no other in-scope timed events. This is the earliest Workshop start that avoids the fixed Review interval while staying within Thursday morning.

### Repeat 6 — Logic + LLM

Outcome: FAIL. multiple interpretations requiring user review

Failed checks: finalStateMatches, runnerCompleted, terminalStatus.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

Proposed translations:

```text
Schedule events jointly [event lasting 60 minutes within thursday morning with title "Workshop"; event lasting 120 minutes within interval from thursday at 09:00 to thursday at 11:00 with title "Review"], choosing earliest in listed order.
```

```text
Schedule events jointly [event lasting 60 minutes within thursday morning with title "Workshop"; event lasting 120 minutes within starting at thursday at 09:00 with title "Review"], choosing earliest in listed order.
```

Final calendar:
```json
[]
```

### Repeat 7 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Both events were created and verified for Thursday, November 5, 2026 (Budapest time): Review, 09:00–11:00; Workshop, 11:00–12:00. With no other in-scope timed events that week, this is the earliest Workshop start that avoids overlap with the fixed 09:00 Review.

### Repeat 7 — Logic + LLM

Outcome: FAIL. multiple interpretations requiring user review

Failed checks: finalStateMatches, runnerCompleted, terminalStatus.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

Proposed translations:

```text
Schedule events jointly [event lasting 60 minutes within thursday morning with title "Workshop"; event lasting 120 minutes within starting at thursday at 09:00 with title "Review"], choosing earliest in listed order.
```

```text
Schedule events jointly [event lasting 60 minutes within thursday morning with title "Workshop"; event lasting 120 minutes within interval from thursday at 09:00 to thursday at 11:00 with title "Review"], choosing earliest in listed order.
```

Final calendar:
```json
[]
```

### Repeat 8 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Both events are confirmed for Thursday, November 5 (Europe/Budapest):

- Workshop: 11:00–12:00
- Review: 09:00–11:00

The selected week had no listed events. The Review’s fixed 09:00–11:00 slot means 11:00 is the earliest nonoverlapping Workshop start within Thursday morning.

### Repeat 8 — Logic + LLM

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

**machine:** Week 2026-11-02–2026-11-08 (Europe/Budapest). Evaluation completed.
schedule events jointly [event lasting 60 minutes within thursday morning with title "Workshop"; event lasting 120 minutes within starting at thursday at 09:00 with title "Review"], choosing earliest in listed order.
Complete lexicographic earliest joint schedule in listed order. Existing events remain fixed.
#0 "Workshop" 2026-11-05 11:00 Europe/Budapest (UTC+01:00) – 2026-11-05 12:00 Europe/Budapest (UTC+01:00)
#1 "Review" 2026-11-05 09:00 Europe/Budapest (UTC+01:00) – 2026-11-05 11:00 Europe/Budapest (UTC+01:00)

**machine:** All proposed changes were read back and verified. Google Calendar is current.

### Repeat 9 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Both events are confirmed for Thursday, November 5 (Europe/Budapest):

- Review: 09:00–11:00
- Workshop: 11:00–12:00

The selected week had no existing events. The Review’s fixed 09:00 start makes 11:00 the earliest Workshop start that fits the morning without overlap.

### Repeat 9 — Logic + LLM

Outcome: FAIL. multiple interpretations requiring user review

Failed checks: finalStateMatches, runnerCompleted, terminalStatus.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

Proposed translations:

```text
Schedule events jointly [event lasting 60 minutes within thursday morning with title "Workshop"; event lasting 120 minutes within starting at thursday at 09:00 with title "Review"], choosing earliest in listed order.
```

```text
Schedule events jointly [event lasting 60 minutes within thursday morning with title "Workshop"; event lasting 120 minutes within interval from thursday at 09:00 to thursday at 11:00 with title "Review"], choosing earliest in listed order.
```

Final calendar:
```json
[]
```

### Repeat 10 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Both events were created and verified for Thursday, November 5, 2026 (Europe/Budapest): Review, 09:00–11:00; Workshop, 11:00–12:00. The Workshop is at its earliest feasible start within Thursday morning.

### Repeat 10 — Logic + LLM

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Jointly schedule a 60-minute "Workshop" within Thursday morning and a 120-minute "Review" starting Thursday at 09:00. Prioritize the earliest possible Workshop start, then the earliest Review start.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

**machine:** Week 2026-11-02–2026-11-08 (Europe/Budapest). Evaluation completed.
schedule events jointly [event lasting 60 minutes within thursday morning with title "Workshop"; event lasting 120 minutes within starting at thursday at 09:00 with title "Review"], choosing earliest in listed order.
Complete lexicographic earliest joint schedule in listed order. Existing events remain fixed.
#0 "Workshop" 2026-11-05 11:00 Europe/Budapest (UTC+01:00) – 2026-11-05 12:00 Europe/Budapest (UTC+01:00)
#1 "Review" 2026-11-05 09:00 Europe/Budapest (UTC+01:00) – 2026-11-05 11:00 Europe/Budapest (UTC+01:00)

**machine:** All proposed changes were read back and verified. Google Calendar is current.

[Machine-readable evidence](calendar-benchmark-case-08-evidence.json).
