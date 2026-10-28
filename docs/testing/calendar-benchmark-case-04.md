# Case 4: Ambiguous reference

Complexity: Moderate. Week: 2–8 November 2026, Europe/Budapest.

## Initial events

| Date | Title | Time | Importance | Location | Description |
| --- | --- | --- | --- | --- | --- |
| Nov 5 | Project review | 09:00–09:30 | Normal |  |  |
| Nov 5 | Project review | 14:00–14:30 | Important |  |  |

## Request and user policy

Move "Project review" to Thursday, 15:00–15:30.

Reference clarification: The afternoon one.

## Expected outcome

| Date | Event | Interval | Importance | Location | Description |
| --- | --- | --- | --- | --- | --- |
| 2026-11-05 | Project review | 09:00–09:30 | Normal |  |  |
| 2026-11-05 | Project review | 15:00–15:30 | Important |  |  |

All existing identities and unrequested fields must be preserved.

## Attempt results

Token counts include all task turns; failures are retained here but excluded from summary means.

| Repeat | Approach | Outcome | Input | Output | Total | Explanation |
| ---: | --- | --- | ---: | ---: | ---: | --- |
| 1 | LLM-only | PASS | 84074 | 907 | 84981 | Passed all independent checks |
| 1 | Logic + LLM | FAIL | 20940 | 594 | 21534 | runner stopped at a known clarification |
| 2 | LLM-only | PASS | 84044 | 873 | 84917 | Passed all independent checks |
| 2 | Logic + LLM | FAIL | 20940 | 361 | 21301 | runner stopped at a known clarification |
| 3 | LLM-only | PASS | 118154 | 1338 | 119492 | Passed all independent checks |
| 3 | Logic + LLM | FAIL | 42882 | 952 | 43834 | translation used an unbound pronoun |
| 4 | LLM-only | PASS | 118389 | 937 | 119326 | Passed all independent checks |
| 4 | Logic + LLM | PASS | 42970 | 1133 | 44103 | Passed all independent checks |
| 5 | LLM-only | PASS | 118920 | 1122 | 120042 | Passed all independent checks |
| 5 | Logic + LLM | FAIL | 20940 | 798 | 21738 | runner stopped at a known clarification |
| 6 | LLM-only | FAIL | 205772 | 998 | 206770 | computer shutdown |
| 6 | Logic + LLM | PASS | 42645 | 1007 | 43652 | Passed all independent checks |
| 7 | LLM-only | PASS | 67156 | 945 | 68101 | Passed all independent checks |
| 7 | Logic + LLM | PASS | 20940 | 567 | 21507 | Passed all independent checks |
| 8 | LLM-only | PASS | 67052 | 1051 | 68103 | Passed all independent checks |
| 8 | Logic + LLM | FAIL | 42931 | 947 | 43878 | translation used an unbound pronoun |
| 9 | LLM-only | PASS | 66654 | 800 | 67454 | Passed all independent checks |
| 9 | Logic + LLM | FAIL | 20940 | 432 | 21372 | runner stopped at a known clarification |
| 10 | LLM-only | PASS | 66562 | 735 | 67297 | Passed all independent checks |
| 10 | Logic + LLM | FAIL | 42908 | 1170 | 44078 | translation used an unbound pronoun |

### Repeat 1 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** There are two “Project review” events on Thursday, November 5: one from 09:00–09:30 and one from 14:00–14:30. Which one should I move to 15:00–15:30?

**user:** The afternoon one.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Moved the afternoon “Project review” on Thursday, November 5, from 14:00–14:30 to 15:00–15:30 Europe/Budapest. Calendar verified the change.

### Repeat 1 — Logic + LLM

Outcome: FAIL. runner stopped at a known clarification

Failed checks: finalStateMatches, runnerCompleted, terminalStatus, referenceClarified.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** Translation needs clarification or repair; nothing was applied.

Final calendar:
```json
[
  {
    "title": "Project review",
    "start": "2026-11-05T09:00:00+01:00",
    "end": "2026-11-05T09:30:00+01:00",
    "importance": 0,
    "location": "",
    "description": ""
  },
  {
    "title": "Project review",
    "start": "2026-11-05T14:00:00+01:00",
    "end": "2026-11-05T14:30:00+01:00",
    "importance": 1,
    "location": "",
    "description": ""
  }
]
```

### Repeat 2 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** There are two events titled “Project review” in the selected week: Thursday, Nov 5, 09:00–09:30 (Normal) and Thursday, Nov 5, 14:00–14:30 (Important). Which one should I move to 15:00–15:30?

**user:** The afternoon one.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Moved the afternoon “Project review” on Thursday, Nov 5 from 14:00–14:30 to 15:00–15:30 Budapest time. The calendar confirmed the update.

### Repeat 2 — Logic + LLM

Outcome: FAIL. runner stopped at a known clarification

Failed checks: finalStateMatches, runnerCompleted, terminalStatus, referenceClarified.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** Translation needs clarification or repair; nothing was applied.

Final calendar:
```json
[
  {
    "title": "Project review",
    "start": "2026-11-05T09:00:00+01:00",
    "end": "2026-11-05T09:30:00+01:00",
    "importance": 0,
    "location": "",
    "description": ""
  },
  {
    "title": "Project review",
    "start": "2026-11-05T14:00:00+01:00",
    "end": "2026-11-05T14:30:00+01:00",
    "importance": 1,
    "location": "",
    "description": ""
  }
]
```

### Repeat 3 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** I found two events titled “Project review” on Thursday, November 5: one from 09:00–09:30 and one from 14:00–14:30 (Europe/Budapest). Which one should I move to 15:00–15:30? The requested time is currently clear of both events.

**user:** The afternoon one.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Moved the afternoon “Project review” on Thursday, November 5 from 14:00–14:30 to 15:00–15:30 Europe/Budapest. The calendar verified the update.

### Repeat 3 — Logic + LLM

Outcome: FAIL. translation used an unbound pronoun

Failed checks: finalStateMatches, terminalStatus.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** Translation needs clarification or repair; nothing was applied.

**user:** The afternoon one.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

**machine:** Week 2026-11-02–2026-11-08 (Europe/Budapest). No event antecedent for it.

Proposed translations:

```text
Set interval of it from thursday at 15:00 to thursday at 15:30.
```

Final calendar:
```json
[
  {
    "title": "Project review",
    "start": "2026-11-05T09:00:00+01:00",
    "end": "2026-11-05T09:30:00+01:00",
    "importance": 0,
    "location": "",
    "description": ""
  },
  {
    "title": "Project review",
    "start": "2026-11-05T14:00:00+01:00",
    "end": "2026-11-05T14:30:00+01:00",
    "importance": 1,
    "location": "",
    "description": ""
  }
]
```

### Repeat 4 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** There are two “Project review” events on Thursday, November 5, so I need to know which one to move to 15:00–15:30 (Europe/Budapest): the 09:00–09:30 event (ID `s9s6370aeju8irinoqbl4dspi4`) or the 14:00–14:30 event (ID `j7ccltnbqnjs2lrprku86suv6g`)? No changes have been proposed yet.

**user:** The afternoon one.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Moved the afternoon “Project review” to Thursday, November 5, 15:00–15:30 Europe/Budapest. Calendar readback confirms the updated time.

### Repeat 4 — Logic + LLM

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** Translation needs clarification or repair; nothing was applied.

**user:** The afternoon one.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

**machine:** Week 2026-11-02–2026-11-08 (Europe/Budapest). Evaluation completed.
set interval of the event with title "Project review" and importance important from thursday at 15:00 to thursday at 15:30.
Interval assigned; overlaps are permitted for explicit assignments.

**machine:** All proposed changes were read back and verified. Google Calendar is current.

### Repeat 5 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** There are two in-scope events titled “Project review” on Thursday, November 5 (Budapest time): one at 09:00–09:30, Normal importance, and one at 14:00–14:30, Important importance. Which one should I move to 15:00–15:30?

**user:** The afternoon one.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Moved the Important “Project review” from Thursday, November 5, 14:00–14:30 to 15:00–15:30 (Europe/Budapest). The update was approved and verified.

### Repeat 5 — Logic + LLM

Outcome: FAIL. runner stopped at a known clarification

Failed checks: finalStateMatches, runnerCompleted, terminalStatus, referenceClarified.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

Proposed translations:

```text
Set interval of the event with title "Project review" and importance normal from thursday at 15:00 to thursday at 15:30.
```

```text
Set interval of the event with title "Project review" and importance important from thursday at 15:00 to thursday at 15:30.
```

Final calendar:
```json
[
  {
    "title": "Project review",
    "start": "2026-11-05T09:00:00+01:00",
    "end": "2026-11-05T09:30:00+01:00",
    "importance": 0,
    "location": "",
    "description": ""
  },
  {
    "title": "Project review",
    "start": "2026-11-05T14:00:00+01:00",
    "end": "2026-11-05T14:30:00+01:00",
    "importance": 1,
    "location": "",
    "description": ""
  }
]
```

### Repeat 6 — LLM-only

Outcome: FAIL. computer shutdown

Failed checks: finalStateMatches, runnerCompleted, terminalStatus, referenceClarified.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

Final calendar:
```json
[
  {
    "title": "Project review",
    "start": "2026-11-05T09:00:00+01:00",
    "end": "2026-11-05T09:30:00+01:00",
    "importance": 0,
    "location": "",
    "description": ""
  },
  {
    "title": "Project review",
    "start": "2026-11-05T14:00:00+01:00",
    "end": "2026-11-05T14:30:00+01:00",
    "importance": 1,
    "location": "",
    "description": ""
  }
]
```

### Repeat 6 — Logic + LLM

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** Translation needs clarification or repair; nothing was applied.

**user:** The afternoon one.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

**machine:** Week 2026-11-02–2026-11-08 (Europe/Budapest). Evaluation completed.
set interval of the event with title "Project review" and importance important from thursday at 15:00 to thursday at 15:30.
Interval assigned; overlaps are permitted for explicit assignments.

**machine:** All proposed changes were read back and verified. Google Calendar is current.

### Repeat 7 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** There are two “Project review” events on Thursday, November 5: one at 09:00–09:30 and one at 14:00–14:30. Which one should I move to 15:00–15:30?

**user:** The afternoon one.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Moved the afternoon “Project review” on Thursday, November 5 from 14:00–14:30 to 15:00–15:30 Europe/Budapest. The update was verified.

### Repeat 7 — Logic + LLM

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

**machine:** Week 2026-11-02–2026-11-08 (Europe/Budapest). Which event do you mean?

**user:** 0

**machine:** Week 2026-11-02–2026-11-08 (Europe/Budapest). Evaluation completed.
set interval of the event with title "Project review" from thursday at 15:00 to thursday at 15:30.
Interval assigned; overlaps are permitted for explicit assignments.

**machine:** All proposed changes were read back and verified. Google Calendar is current.

### Repeat 8 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** There are two “Project review” events on Thursday, November 5. Which one should I move to 15:00–15:30 Budapest time?

- 09:00–09:30 (Normal)
- 14:00–14:30 (Important)

**user:** The afternoon one.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Moved the afternoon “Project review” from Thursday, November 5, 14:00–14:30 to 15:00–15:30 Budapest time. The Calendar update was verified.

### Repeat 8 — Logic + LLM

Outcome: FAIL. translation used an unbound pronoun

Failed checks: finalStateMatches, terminalStatus.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** Translation needs clarification or repair; nothing was applied.

**user:** The afternoon one.

**machine:** LLM translation failed (agent turn: HTTP 409); nothing was applied.
LLM translation failed (agent turn: HTTP 409); nothing was applied.

**user:** The afternoon one.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

**machine:** Week 2026-11-02–2026-11-08 (Europe/Budapest). No event antecedent for it.

Proposed translations:

```text
Set interval of it from thursday at 15:00 to thursday at 15:30.
```

Final calendar:
```json
[
  {
    "title": "Project review",
    "start": "2026-11-05T09:00:00+01:00",
    "end": "2026-11-05T09:30:00+01:00",
    "importance": 0,
    "location": "",
    "description": ""
  },
  {
    "title": "Project review",
    "start": "2026-11-05T14:00:00+01:00",
    "end": "2026-11-05T14:30:00+01:00",
    "importance": 1,
    "location": "",
    "description": ""
  }
]
```

### Repeat 9 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** There are two “Project review” events in the selected week: Thursday, Nov 5, 09:00–09:30 (Normal) and Thursday, Nov 5, 14:00–14:30 (Important). Which one should I move to Thursday, Nov 5, 15:00–15:30?

**user:** The afternoon one.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Moved the afternoon “Project review” to Thursday, Nov 5, 15:00–15:30 Europe/Budapest. Calendar verified the change.

### Repeat 9 — Logic + LLM

Outcome: FAIL. runner stopped at a known clarification

Failed checks: finalStateMatches, runnerCompleted, terminalStatus, referenceClarified.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

Proposed translations:

```text
Set interval of the event with title "Project review" and importance normal from thursday at 15:00 to thursday at 15:30.
```

```text
Set interval of the event with title "Project review" and importance important from thursday at 15:00 to thursday at 15:30.
```

Final calendar:
```json
[
  {
    "title": "Project review",
    "start": "2026-11-05T09:00:00+01:00",
    "end": "2026-11-05T09:30:00+01:00",
    "importance": 0,
    "location": "",
    "description": ""
  },
  {
    "title": "Project review",
    "start": "2026-11-05T14:00:00+01:00",
    "end": "2026-11-05T14:30:00+01:00",
    "importance": 1,
    "location": "",
    "description": ""
  }
]
```

### Repeat 10 — LLM-only

Outcome: PASS. 

Failed checks: none.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** There are two “Project review” events in the selected week: Thursday, November 5, 09:00–09:30 (Normal) and 14:00–14:30 (Important). Which one should I move to 15:00–15:30 Budapest time?

**user:** The afternoon one.

**machine:** The agent proposed Calendar tool calls. Review and approve the exact list before execution. No writes in this list have run.

**machine:** All approved primitive calls were read back and verified. This verifies execution, not the agent’s reasoning.

**machine:** Moved the afternoon “Project review” on Thursday, November 5, from 14:00–14:30 to 15:00–15:30 Budapest time. The calendar update was verified.

### Repeat 10 — Logic + LLM

Outcome: FAIL. translation used an unbound pronoun

Failed checks: finalStateMatches, terminalStatus.

Conversation:

**user:** Move "Project review" to Thursday, 15:00–15:30.

**machine:** Translation needs clarification or repair; nothing was applied.

**user:** The afternoon one.

**machine:** Interpretations ready for review; no Calendar changes were submitted.

**machine:** Week 2026-11-02–2026-11-08 (Europe/Budapest). No event antecedent for it.

Proposed translations:

```text
Set interval of it from thursday at 15:00 to thursday at 15:30.
```

Final calendar:
```json
[
  {
    "title": "Project review",
    "start": "2026-11-05T09:00:00+01:00",
    "end": "2026-11-05T09:30:00+01:00",
    "importance": 0,
    "location": "",
    "description": ""
  },
  {
    "title": "Project review",
    "start": "2026-11-05T14:00:00+01:00",
    "end": "2026-11-05T14:30:00+01:00",
    "importance": 1,
    "location": "",
    "description": ""
  }
]
```

[Machine-readable evidence](calendar-benchmark-case-04-evidence.json).
