> Archived historical design. Current contracts are [shared Calendar rules](../calendar-domain.md),
> [Calendar language v1](../calendar-language-v1.md) and [LLM-only design](../calendar-llm-only.md).
> Historical status statements below are not current implementation status.

# Proposed Calendar controlled language and task dialogues

## 1. Status and purpose

**Semantic version: `calendar-v1`, policy `calendar-demo-1`.** The subsequently
authorized implementation now supplies controlled-English execution, reference
resolution, clarification, the three task solvers and reviewed provider writes.
See [the implementation guide](../calendar-language-v1.md) for setup and current
boundaries. This document retains its design history and detailed contracts;
unimplemented extensions remain outside the approved inventory.

The design follows the [controlled-language manifesto](../controlled-language-manifesto.md)
and the [object](../object-language-v2.md), [network](../network-language-v2.md) and
[cellular](../cellular-language-v2.md) conventions. The motivation is described in
[Six problems with an LLM-only approach](../logic_chatbot_demo20261021_six_problems.md).
Current provider setup and GUI behavior are in [Calendar MCP setup](../calendar-mcp.md).

The demonstration must establish intended meaning through dialogue, retain
requirements, and produce checkable results. A successful scheduling algorithm
alone does not demonstrate those capabilities. **No consequential decision is
taken silently.** The human settles intentions and permissions; Haskell resolves
references and computes consequences. The LLM may interpret requests and answers
and express feedback, but does not invent constraints or compute domain answers.

The labels below preserve the design provenance; the implementation guide
records current operational coverage:

- **Agreed:** established in the design conversation.
- **Proposed:** a concrete design candidate; the bounded v1 inventory was
  subsequently authorized for implementation. Deferred extensions remain proposals.
- **Open:** a consequential distinction still requiring a policy or grammar choice.
- **Demo policy:** an edge-case rule selected under the user's delegation. It is
  documented here as part of the bounded v1 policy.

## 2. Domain foundations

These grammar-independent rules have been extracted into
[the shared Calendar domain reference](../calendar-domain.md), which is also the
semantic reference for the proposed LLM-only agent. This document retains the
controlled grammar, symbolic evaluation, algorithms and execution contracts.
The extraction does not implement the LLM-only interface or change v1 semantics.

### 2.1 Universe and scope

See [Universe and scope](../calendar-domain.md#universe-and-scope).

### 2.2 Events, values and identity

See [Events, values and identity](../calendar-domain.md#events-values-and-identity).

### 2.3 Five-minute model, originals and rounding

See [Five-minute model, originals and rounding](../calendar-domain.md#five-minute-model-originals-and-rounding).

### 2.4 Named periods and inferred rescheduling bounds

See [Named periods and inferred rescheduling bounds](../calendar-domain.md#named-periods-and-inferred-rescheduling-bounds).

### 2.5 Other temporal terms and literal policy

See [Other temporal terms and literal policy](../calendar-domain.md#other-temporal-terms-and-literal-policy).

## 3. Layer 1: atomic commands

**Agreed inventory:** create, delete, assign a text field, assign importance, and
assign the complete interval. Separate clear commands and an exchange primitive
are unnecessary. Uppercase names below are typed placeholders; these are
**illustrative surface forms**; Section 10 supplies their exact grammar.

| Candidate form | Contract |
| --- | --- |
| `Create event from T1 to T2 [with fields].` | Create one fresh identity with the interval and supplied fields; omitted text fields default to empty strings and importance to Normal |
| `Delete R.` | Delete the resolved existing event |
| `Set title of R to S.` | Replace only title with the string S, including `""` |
| `Set location of R to S.` | Replace only location with S |
| `Set description of R to S.` | Replace only description with S |
| `Set importance of R to I.` | Assign Normal, Important or Critical using its canonical provider encoding |
| `Set interval of R from T1 to T2.` | Assign both endpoints together; preserve identity and other fields |

### 3.1 Shared atomic contracts

**Proposed, following existing domain conventions:**

- Parse and statically validate the complete entry before evaluating any command.
  Commands end in periods. Natural synonyms belong to the interpretation layer.
- Resolve operands before mutation. Missing, ambiguous and out-of-scope
  references never create events, select an arbitrary event, or become `false`.
- Validate a new interval as a pair. Invalid endpoints leave that command's
  event and discourse effects unapplied. Overlap alone does not invalidate it.
- Setters preserve every unnamed field. Equal-value assignments succeed without
  a semantic field change, subject to the explicit importance encoding above.
- Deleting a missing identity is a reference failure, not successful deletion.
- Creation allocates a new identity; text assignment never changes identity.
  Section 10.4 specifies language handles; Section 13 specifies durable provider-ID
  reservation and the application boundary.
- Successful dialogue commands mention their explicit resolved event operands;
  creation mentions its new event. Deletion removes invalid event references.
  Section 10.4 specifies the proposed event salience rules.

Atomic here describes the operation's local semantic contract, not a distributed
Google transaction. Section 13 defines private entry evaluation, explicit prefix
acceptance, external application/recovery and the deliberate absence of Calendar
Undo in v1. A cloud partial failure is never reported as a successful atomic task.

Creation with populated fields expands privately into create plus setters as one
conceptual operation. Internal setters do not create extra dialogue turns,
salience ages or public intermediate appointments. Its proposed event is complete
before any creation is submitted, including empty/default attributes.

### 3.2 Questions and internal predicates

Section 12 specifies atomic and conceptual questions, including incomplete
questions. Engine clarifications remain ordinary clear English prompts, separate
from executable domain questions and their symbolic answers.

The first task algorithms still need internal typed predicates and calculations:
interval overlap, interval containment, event selection, importance ordering,
free intervals and movement cost. These symbolic capabilities serve both query
syntax and task evaluation. No LLM-generated answer substitutes for their evaluation.

## 4. Layer 2: reference foundations

Follow the shared conventions: typed event identities, `it`, descriptions,
clarification of ties, current truthful salience facts, and persistent pending
choices. An event, a date and an interval are different types. A title need not
be unique and is not an identity. A daily display segment denotes its original event.

Resolve event references before running an operation, freeze its selected
collection, and keep those identities through clarification. A GUI edit should
invalidate stale facts without inventing dialogue mentions. A question may affect
discourse even though it changes no calendar data.

Section 10.4 specifies proposed handle notation, ordered descriptions and salience.
Only events become discourse referents initially. Do not introduce possessive
aliases or bound-variable semantics merely because ordinary clarification text
uses “its” or “those meetings.”

## 5. Shared task dialogue and solver contracts

### 5.1 Decision structures, not questionnaires

A task consists of explicit commitments, unresolved choices, derived facts and
an execution/search status. Each meaningful decision node records:

1. The unresolved issue and why its answer matters.
2. Which earlier commitments already settle it, if any.
3. A clear question and typed alternatives, or an appropriate free-value answer.
4. The constraint or permission established by the answer.
5. The next branch, including failure and revision paths.

Ask only unresolved, consequential questions. Do not ask the user to repeat an
established duration or allowed window. Defaults explicitly agreed in this
specification, such as Normal importance, are disclosed defaults and need not
be asked on every creation. Task-specific assumptions have no such authority.

Persist commitments and pending questions across turns. A revised duration changes
that duration, not the previously established movement threshold, protected events
or allowed hours. Report consequential invalidations and recompute dependent
results. Rejection, courtesy or an ambiguous reply does not grant permission.

### 5.2 Common clarification points

| Issue | Example question | Established result |
| --- | --- | --- |
| Ambiguous event | “Which of these two appointments do you mean?” | Resolved identity |
| Duration | “How long should the meeting last?” | Positive duration with specified interpretation |
| Search bounds | “How late may it finish on Thursday?” | Explicit finite allowed window |
| Field interpretation | “Should ‘with Mr Black’ be part of the title?” | Agreed text assignment; no invented attendee/contact semantics |
| Permission to move | “What is the maximum importance level of events you are willing to move?” | None / Normal / Important / Critical |
| Preservation | “These events will keep their dates, periods and normalized durations. May I move them?” | Approval within disclosed inferred bounds |
| Objective | “I will minimize total movement, penalizing movement of more important events more heavily.” | Disclosed current optimization rule; explanation available |
| Equal optimal results | “These two schedules are equally good under your criteria. Which do you prefer?” | Selected result, or permission for a disclosed tie-break |
| Infeasibility | “Would you like to widen the allowed hours or allow higher-importance events to move?” | A specific authorized relaxation, or stop |

The importance threshold is **agreed**: None permits no existing-event movement;
Normal permits Normal only; Important permits Normal and Important; Critical
permits all three levels. Permission is not a requirement to move an event.
Other restrictions still apply. A protected event can never become movable
because search failed. Current recurring events are read-only through the adapter;
importance permission alone cannot override that capability restriction.

### 5.3 Search domains and honest outcomes

Each task must have a finite, explicit search domain and a validated set of
constraints. The week's finite event set does not by itself define timestamp
precision or a finite enumeration of possible placements.

Use the agreed five-minute domain and the exact-original validation rules in
Section 2.3. Event-specific inferred envelopes and endpoint-date constraints
further restrict the domain. Never imply infeasibility over unrestricted real
time or out-of-scope calendar data.

Distinguish these outcomes:

- Feasible and verified; state whether optimality was proved.
- Infeasible within the explicitly specified domain, after a complete decision.
- Feasible candidate found but optimality not established before the work limit.
- Search limit reached with no solution found; feasibility remains unresolved.
- Unresolved interpretation, reference or permission; ask before affected work.
- Provider/application failure, separate from mathematical infeasibility.

A valid candidate is not automatically authorized. Show its changes and their
justification before applying it through the established proposal/acceptance flow.
A resource limit never licenses silently weakening constraints or claiming failure
is a proof of impossibility.

### 5.4 Reusable constraint solver: proposed algorithm

For the rearrangement tasks, a transparent first solver can use finite-domain
constraint search with branch-and-bound:

1. Ground references, allowed windows, movable identities, durations and objective.
2. Preserve each original interval. Fixed events are immutable obstacles.
3. Give each movable event a domain of legal candidate starts; its end is derived
   using the accepted duration interpretation. Include its current placement when
   legal. The new event, if any, has its own placement domain.
4. Remove candidates violating unary bounds or an applicable required-pair
   constraint with a fixed event. Keep unchanged candidates even when an
   unrelated original clash is permitted by the operation's contract.
5. Propagate only the operation-specific required pair constraints defined below.
   Buffers and hard ordering constraints are outside the v1 grammar; tie-policy
   preferences do not become feasibility constraints.
6. Branch on an event with the smallest remaining domain, using stable internal
   enumeration for reproducibility. Prune domain wipeouts and branches whose
   admissible objective bound is strictly worse than an incumbent. Equal-bound
   branches remain eligible while material alternative optima are unresolved.
   Initially a weak valid lower bound is preferable to an unsound aggressive one.
7. Validate each complete assignment independently against the original task
   constraints; score it using the accepted objective.
8. Exhaust the relevant search to establish infeasibility or optimality, or return
   the explicitly limited status. Retain equal optima or enough information to
   present their consequential differences.

#### Required-pair constraints and unchanged candidates

Every existing event has a distinguished exact-unchanged candidate. Define
`moved(e)` by actual interval difference from that candidate, not by whether the
identity was eligible to move. Exclude normalization-only candidates as specified
in Section 2.3. The following predicates decide which unordered pairs of distinct events must be
clash-free in each **complete candidate**:

| Operation | Pair requires non-overlap when |
| --- | --- |
| Earliest scheduling | One endpoint is the new event |
| Insertion | One endpoint is the new event, or either existing endpoint actually moves |
| Day repair | Either endpoint belongs to the frozen repair target set |
| Explicit atomic assignment | Never solely because the intervals overlap; clashes remain allowed |

Apply every required pair constraint to both normalized final intervals and
exact final intervals. For an unchanged endpoint, these mean its projection and
its original respectively; changed/new intervals are their proposed grid values
in both checks. This also applies to fixed–fixed pairs: they prove infeasibility
only when their pair is required. Eligibility, importance or being a solver
variable is not itself a reason to require clash freedom.

Propagate a conditional insertion constraint only when its guard is established.
An unchanged candidate that clashes with an untouched fixed event is legal if
neither endpoint nor the new event triggers the guard. Changing that candidate
makes all its conflicts relevant. Do not pre-filter it using unconditional
all-different/non-overlap constraints. The independent final checker uses exactly
the same required-pair contract without relying on search's pruning decisions.

Example: insertion requires moving A in the morning, while untouched C and D
already clash in the afternoon. A solution leaving C/D untouched remains legal
and incurs no movement cost for them. Marking C eligible must not force their
repair. By contrast, day repair targeting C requires removing C's clashes even
if C itself remains in its original interval and D is moved instead.

Internal enumeration order is an implementation detail, not permission to pick
one of several materially different optimal schedules. Such a choice requires
clarification or a previously delegated, disclosed selection rule.

### 5.5 Weighted movement objective and equal solutions

**Agreed objective:** minimize the sum of absolute start-time displacement in
hours, weighted by `(importance + 1)^2`. The weights are Normal 1, Important 4,
and Critical 9. Normal moved two hours costs 2; Important moved three hours costs
12; Critical moved one hour costs 9. Durations are preserved under the normalized
elapsed-time policy, so one start displacement describes a rescheduled interval.
Use exact grid-tick arithmetic internally; multiplying the sum by twelve preserves
ranking and avoids floating-point errors. Cost is measured from each event's
original normalized start. An untouched event costs zero. The candidate rule in
Section 2.3 makes every permitted automatic change strictly positive-cost.
Therefore a feasible no-movement baseline proves minimum movement cost zero;
its earliest placement also proves the insertion secondary objective among all
zero-cost schedules. No unknown movement permission is needed for that result.
For exact 02:21–02:27, automatic scheduling cannot shorten it to 02:20–02:25 for
free. A five-minute meeting after it starts no earlier than 02:30 unless the
user separately approves an explicit manual interval normalization.

Importance simultaneously participates in movement **permission** and movement
**cost**; a low-cost forbidden move is still forbidden. The objective is not
fewest moves first: several small moves may cost less than one large move.
The requested new event has no movement cost because it has no old interval.
For insertion, **demo policy:** first minimize weighted existing-event movement,
then prefer the earliest permissible new-event start. Explicit requests assigning
a different priority must be clarified as a different objective rather than
silently treated as this operation. Earliest-available scheduling without movement
retains its own earliest-start objective.

Do not print the formula in every question. Disclose the policy once per task
review, expose weights and per-event contributions on request, and report relevant
normalization differences. Later selectable optimization policies are deferred.

For materially distinct equal optima, ask the user to choose. As an alternative,
the user may explicitly delegate a stated rule, such as preserving original event
order. There is no automatic identity-number or title-based semantic tie-break.
If many optima exist, summarize differing choices and refine them interactively
rather than dumping every arrangement or pretending two examples exhaust them.
Internal enumeration order remains irrelevant to authorization.

## 6. Concept 1: schedule at the earliest available time

### 6.1 Intended effect and inputs

Create one event at the earliest feasible start in an explicitly bounded search
window, without moving existing events. Optional strings and importance have the
agreed creation defaults. A requested title, location or description supplies
assignments; a person's name does not automatically denote a Google attendee.

Required task inputs: selected week, allowed date/window, duration,
timezone/precision interpretation, and any supplied field values. “Earliest”
orders feasible starts chronologically. Section 10.5 defines its proposed syntax.

### 6.2 Decision tree

1. Interpret the request without resolving ambiguous identities or field meanings
   by guesswork. Clarify consequential alternative readings.
2. Reuse established date/window and duration. Ask for missing duration and the
   missing end bound if the date/period expression did not supply it; do not assume
   a one-hour meeting or a 17:00 finish.
3. If a phrase such as “with Mr Black” is supplied, establish its field meaning
   when context does not settle it. Location is a string, not travel-time data.
4. Ground relative dates and strict/inclusive boundaries. Explain scope violations
   rather than silently searching next week.
5. Complete every explicit field/protection hole that applies to the task, then
   compute availability without moving existing events. Lazy movement permission
   is the sole hole that may remain unused in a successful no-movement result.
6. If feasible, show the earliest interval, supplied/default fields and evidence
   that no earlier eligible interval fits. Ask for acceptance.
7. If no interval fits, explain the exact bounded result. Offer a choice to change
   duration/window, stop, or enter Concept 2. Entering Concept 2 does not itself
   authorize moving anything.

### 6.3 Algorithm

1. Intersect permitted search windows with the approved scope. Sort and merge
   overlapping busy intervals from both normalized projections and exact unchanged
   originals of relevant events within each window. This union enforces both
   checks during search, rather than discovering a hidden exact conflict only
   after selecting a result. Clip intervals only for occupancy calculations.
2. Subtract that busy union to obtain maximal free intervals. Touching busy
   intervals can be merged because their intervening free duration is zero.
3. In chronological order, find the earliest permitted start in a free interval
   at which the requested duration finishes within that interval. Respect the
   chosen precision/grid and strictness of the lower bound.
4. If none qualifies after complete inspection, return bounded infeasibility.
5. Construct the proposed event using create and required setters. Independently
   verify containment, duration and non-overlap against the source snapshot.

Sorting dominates the elementary interval algorithm: O(n log n), plus window
processing. This is a baseline algorithm, not the main combinatorial demonstration.

### 6.4 Worked branches

On Thursday, permitted window 09:00–12:00; existing events 09:00–09:45 and
10:30–11:00. A 45-minute request has earliest placement 09:45–10:30. The explanation
identifies the blocking first interval and the exact fit before the next event.

If the user revises duration to 60 minutes, the earliest placement is 11:00–12:00.
The date and allowed window remain established. At 90 minutes, no placement fits;
the system asks which constraint to revise rather than silently using the afternoon.

## 7. Concept 2: make room with minimal disruption

### 7.1 Intended effect and inputs

Create one event satisfying its requested window by repositioning only explicitly
permitted existing events. Preserve existing identities and unnamed fields.
Preserve their normalized elapsed durations, original endpoint dates and inferred
period envelopes; move only intervals. Disclose these demo policies with the
permission request. A threshold answer cannot waive those other constraints.
No deletion, shortening or importance downgrade is implied by “make room.”

Inputs extend Concept 1 with movement permission, an explicit protected set and
a tie policy. Destination envelopes/dates, normalized duration preservation and
weighted movement cost are fixed disclosed v1 policies, not omitted user slots.

### 7.2 Decision tree

1. Establish the new event's requirements as in Concept 1, including every
   explicit text/importance hole and protection-list hole/reference.
2. Try the explicitly desired placement objective with no existing-event movement.
   If it succeeds and satisfies the requested objective, propose that solution.
   If the request explicitly prioritizes a different result, do not replace that
   priority with the no-movement shortcut.
3. If movement is needed and permission is unresolved, ask the maximum-importance
   question. None retains a no-movement problem; explain infeasibility if established.
4. Resolve any narrower explicit protected selection. Threshold permission and
   explicit protection combine; the more restrictive rule wins.
5. Compute and disclose inferred movement bounds and duration preservation; ask
   for missing task-specific restrictions rather than asking again about fixed
   demo policies. Read-only
   recurring events remain fixed even when their importance is below the threshold.
6. Disclose the weighted movement objective and secondary earliest placement.
   Clarify requests that prescribe a competing priority; retain prior commitments.
7. Solve using the required-pair constraints in Section 5.4. Show equal material
   optima as choices unless a tie-break was delegated.
8. If infeasible, show a verified obstruction when available. Ask whether to relax
   a named restriction; retain all other commitments. A search limit follows a
   separate branch and does not justify a relaxation request framed as necessity.
9. Present old/new intervals, protected events and the objective score for acceptance.

**Demo clash policy:** the new event and every moved event must be clash-free
against the complete resulting week. Pre-existing clashes solely between untouched
events are disclosed but do not silently turn insertion into whole-week repair.
Disclose this boundary. A request for global week-wide repair is unsupported in
v1; preserve that requirement as an interpretation issue and explain the limit.
Do not silently add it to insertion or weaken it to insertion's local guarantee.

### 7.3 Algorithm

1. Compute the no-movement availability baseline and report why it fails if needed.
2. Build the permitted movable set and fixed obstacles from the agreed constraints.
   Include cross-day intervals in full; no independent movement of display segments.
3. Use the shared finite-domain solver with domains for the new event and existing
   movable events. A tempting greedy move is only a candidate, not a completeness
   argument: freeing one interval can require a chain of relocations.
4. Score complete valid assignments under the accepted ordered objective. Preserve
   a best incumbent and a proof/status of whether any better solution is possible.
5. Generate interval assignments only for changed identities, plus creation and
   setters for the new event. Verify the proposed result against every retained
   commitment and disclose any untouched pre-existing clashes.

### 7.4 Worked branches

Thursday morning 09:00–12:00 is the permitted destination window. Normal events
A and B occupy 09:00–09:30 and 09:30–10:00. The requested new one-hour meeting is
fixed at 09:00–10:00. Existing normalized durations remain unchanged. All intervals
are on-grid and fit the inferred morning bounds.

- With None, the request is infeasible: both occupied intervals block the fixed slot.
- With Normal, A at 10:00–10:30 and B at 10:30–11:00 is feasible. Both must move;
  moving only one cannot free the requested interval. Total weighted cost is 2.
- Reversing A and B is also feasible and has equal total absolute displacement.
  Ask for a choice, or obtain permission for a disclosed ordering preference.
- If B is Critical and the threshold remains Normal, no solution exists under
  these constraints. Ask whether the threshold or requested slot may change;
  do not move B or shorten the new meeting silently.

## 8. Concept 3: remove clashes from a day's schedule

### 8.1 Intended effect and inputs

Reposition permitted existing events so the specified conflict set is eliminated.
Create or delete nothing. Preserve identities, text and importance. Normalized elapsed duration
preservation and inferred time envelopes are demo policies disclosed for approval.

In v1, “Thursday's events” means the in-scope events whose exact initial intervals
intersect Thursday. Require clash freedom over their complete final intervals,
not just Thursday's visible slices. The task review exposes that cross-day scope;
it does not ask the same already-defined policy question each time.

### 8.2 Decision tree

1. Establish the target date and complete explicit protection holes/references.
   The target is date-selected in v1, not an arbitrary supplied event collection.
2. Compute the required-pair clashes in both normalized and exact-original models.
   Return successful no-change only if both checks are clear and all explicit
   semantic/protection holes are resolved, even when the target set is empty.
   Disclose differences between models; do not rearrange for aesthetic reasons.
3. Apply and disclose the day-intersection/whole-event policy below, including
   cross-day identities. Clarify competing interpretations in the request instead
   of silently overriding that stated scope.
4. Ask the maximum movable importance threshold unless already supplied. Identify
   explicit protections and read-only events; display which identities are eligible.
5. Apply original endpoint dates, inferred period envelopes and normalized duration
   preservation; disclose these rules. Additional destination-hour constraints
   for existing events are unsupported in v1 and must not be silently assumed.
6. Disclose weighted movement cost and clarify material ties. Do not assume that
   calendar order, titles or identity numbers express scheduling priorities.
7. Solve. Present a verified result or the exact limited/infeasible status.
8. For verified infeasibility, present a relevant blocking constraint and ask which
   restriction may change. For equal optima, clarify or apply delegated tie-breaking.
9. Present the resolved moves and their scores for acceptance; preserve the rest
   of the week according to the task's stated permissions.

**Demo scope policy:** select events intersecting the requested day; require
affected events to be clash-free over their complete resulting intervals against
all events in the language universe. Unrelated clashes outside the affected set
remain outside the repair contract and are disclosed when relevant. Movement
requires approval within the inferred envelopes and original endpoint dates.
Disclose this scope in review; clarify requests explicitly suggesting another scope.

### 8.3 Algorithm

1. Sort events by start and use a sweep to identify overlapping pairs. Report
   relevant pairs under the chosen target/conflict scope. An overlap graph is
   evidence about the initial schedule, not a fixed list of all future conflicts.
2. Partition fixed and movable events. An unavoidable clash between two fixed
   events within the required repair scope is an immediate infeasibility witness.
3. Construct complete legal placement domains and invoke the shared solver.
   Recompute clash constraints for every candidate arrangement: moving an event
   can create conflicts with events absent from its initial overlap component.
4. Optimize according to the accepted criteria; never solve initial overlap
   components independently unless their destination resources are proven disjoint.
5. Validate every required pair in the resulting schedule, plus preservation and
   scope constraints. Present changed intervals and objective/optimality evidence.

An additional sound infeasibility witness is required event duration exceeding
available capacity in a common allowed window, accounting for fixed obstacles.
Capacity alone is not a complete feasibility test; order and fragmented free
intervals can still prevent placement.

### 8.4 Worked branches

Thursday's required scope contains Critical A at 09:00–10:00 and Normal B at
09:30–10:30. The inferred morning window is 09:00–12:00, durations are preserved, and the
threshold is Normal. B can move to 10:00–11:00; A remains fixed. Under the weighted objective, this moves B by 30 minutes at cost 0.5.

If B is also Critical and the threshold is Important, both are fixed. Their
reported overlap is an infeasibility witness. The engine asks whether to allow
Critical movement or stop; widening hours alone cannot fix two immovable events.

If A and B instead have identical 09:00–10:00 intervals and both are movable,
there are symmetric equally good repairs. The engine must not choose which
appointment moves based on an undisclosed identity-number tie-break.

## 9. Explanation, verification and demonstration obligations

A proposal should expose a compact decision record:

- User-supplied constraints and the clarification turn establishing each one.
- Disclosed agreed defaults and any explicitly delegated choices.
- Resolved identities, original intervals, permitted moves and protected events.
- Derived busy/free intervals or clash witnesses used in the result.
- Before/after changes, objective values and whether optimality was proved.
- Unresolved choices, search limits, infeasibility and provider failures as
  separate statuses. Claim only what the available evidence establishes.

The interface need not print every search branch. It must let the user understand
material choices without reverse-engineering the result. Explanations derive
from the actual task state, solver evidence and execution outcomes.

Required future tests include:

1. Empty titles/text, default importance, explicit clearing, stable identities,
   no-op setters and failed references remain distinct and correctly handled.
2. Half-open boundaries, midnight endings, cross-day events,
   full-week containment, off-grid obstacles and DST cases follow the temporal policy.
3. Missing duration/window/movement permission causes a meaningful question;
   an already established answer is not asked again or silently replaced.
4. Revising one answer preserves other commitments; resumable clarification
   retains selected identities and the task's intended scope.
5. Thresholds and explicit protections constrain every solution, including
   indirect chains of moves; read-only events are never mutated.
6. Each solver candidate satisfies an independent constraint checker. Small
   exhaustive instances verify optimality and true infeasibility claims.
7. Search interruption is never reported as impossibility. Equal material optima
   prompt a choice unless the tie-break was explicitly delegated.
8. Period-spanning events get their minimal consecutive-period envelope; exclusive
   ends do not recruit a later period. Same-day night events cannot cross dates;
   existing cross-day events retain endpoint dates. Bounds stay frozen in search.
9. Five-minute ties round down; collapsed positive intervals become five minutes.
   Originals survive unrelated edits; exact final checks catch hidden overlaps.
   Boundary normalization issues never silently expand the universe or permissions.
10. Weighted costs match 1/4/9 times displacement; several small moves can beat one
    large move. No unapproved lexicographic fewest-events objective survives.
11. Proposed results do not claim cloud completion before actual verification;
    application errors are not rewritten as mathematical impossibility.

For decision makers, demonstrate a simple scheduling success, a multi-move
insertion, and a clash repair with an infeasible/clarification branch. Include
an incremental requirement change to show retained commitments during replanning.
Measure LLM tokens, latency, constraint violations and objective quality against
an LLM-only controller with the same information and permitted primitive actions.
Token savings and accuracy are evaluation hypotheses, not established results.

## 10. Proposed exact syntax

This section proposes the first executable grammar. Its forms supersede the
illustrative placeholders above, but remain unimplemented and subject to review.
Layer 3 commands contain exactly the three selected task families. Section 12
adds atomic and conceptual questions. General quantified commands, arbitrary
optimization expressions, `Undo.` and `Atomically { ... }.` are not accepted in
this first grammar. Their absence is
explicit; no cloud transaction guarantee is implied by internal planning.

### 10.1 Lexical conventions and typed holes

Keywords are case-insensitive; canonical keywords are lowercase. Strings and
provider IDs are case-sensitive. Whitespace and line breaks separate tokens;
quoted punctuation inside strings is data. Every command ends in a period and
every domain question in a question mark.
The parser consumes the entire entry before any evaluation. Unknown keywords,
malformed literals, duplicated clauses and static type errors reject that entry
without changing domain or discourse state.

A string is a double-quoted JSON string, including `""`, with JSON escapes and
Unicode characters. Bare newline/control characters and invalid Unicode escape
sequences are rejected. An integer is decimal, without leading zeroes except
literal `0`. Identifiers concatenate `#` and a nonnegative integer. An ISO date
has exactly `YYYY-MM-DD`, with a real Gregorian date in years 0001–9999. A clock
has exactly `HH:MM`, 00:00–23:59; `24:00` is not a literal. Name the next date's
00:00 for a midnight end. An offset has signed `HH:MM`, is a valid UTC offset,
and must match Budapest at the resolved local instant; do not accept it merely
as a way to select an impossible local time.

`unspecified` is an explicit **typed hole in a request**, not an event attribute
value, `none`, permission, or an arbitrary solver variable. Missing task clauses
can also introduce holes as defined below. Evaluation asks for the missing value
when needed. `"unspecified"` is an ordinary string, not a hole. Omitted event text
and importance use their agreed defaults and do not introduce holes.

An unresolved field is represented in the pending request, never by wrapping the
actual event's strings/importance in `Maybe`. A created event always has complete
string and importance values.

EBNF uses quoted literals, `|` alternatives, `[ ... ]` optional material,
`{ ... }` repetition and unquoted parentheses for grouping. Lexical names
`integer`, `string`, `iso-date`, `clock` and `offset` have the definitions above.
Commas in EBNF concatenate items; quoted commas are required input punctuation.
Numeric domain checks occur during evaluation, except malformed/out-of-lexical-
range literals, which fail parsing/static validation.

### 10.2 Values and temporal expressions

```ebnf
importance = "normal" | "important" | "critical" ;
importance-slot = importance | "unspecified" ;
threshold = "none" | importance ;
threshold-slot = threshold | "unspecified" ;
text-slot = string | "unspecified" ;
duration = "1 minute" | integer-except-one, "minutes" ;
duration-slot = duration | "unspecified" ;

weekday = "monday" | "tuesday" | "wednesday" | "thursday"
        | "friday" | "saturday" | "sunday" ;
date-term = iso-date | weekday | "today" | "tomorrow" ;
date-slot = date-term | "unspecified date" ;
clock-term = clock
           | "one of", "[", clock, ",", clock, { ",", clock }, "]" ;
clock-slot = clock-term | "unspecified" ;
moment = date-slot, "at", clock-slot, [ "offset", offset ] ;
moment-slot = moment | "unspecified" ;
period = "night" | "dawn" | "morning" | "lunchtime"
       | "afternoon" | "evening" ;
lower-bound = ("after" | "at or after"), clock-slot ;
upper-bound = ("before" | "by"), clock-slot ;
window = "selected week"
       | date-slot, [ period ], [ lower-bound ], [ upper-bound ]
       | "interval from", moment-slot, "to", moment-slot
       | "starting at", moment-slot ;
window-slot = window | "unspecified" ;
```

`unspecified` alone in a window position is exclusively a whole-window hole.
`unspecified date` is exclusively a date hole: for example,
`within unspecified date morning` retains the period while asking for its date.
There is no second derivation of `within unspecified` as an unknown whole-day
window. Canonical repair without a supplied date emits `on unspecified date`.
A complete moment hole is `unspecified`; a partial moment can be
`unspecified date at 09:00`. Syntax, not parser preference, distinguishes these.

Duration means elapsed minutes; a positive multiple of five is required for a
completed request. `integer-except-one` is the lexical integer class excluding 1.
Singular `1 minute` parses but requires clarification of an admissible duration;
`1 minutes` and `5 minute` are malformed. Zero parses
as a value but is rejected during evaluation with a request for a positive value.
Other nonmultiples of five similarly require an explicit replacement, never a
silent rounding. Large values must produce range/scope diagnostics, not overflow.

A `one of` clock list contains distinct alternatives and preserves an unresolved
choice; it is not permission to choose the most convenient available slot.
For “at 5,” the interpretation can supply `one of [05:00, 17:00]`. Reference/time
resolution eliminates only readings inconsistent with established meaning
constraints, such as an explicitly supplied afternoon. Occupancy does not choose
AM/PM: if both fit the stated temporal bounds, ask even if only one is free.
Canonical output sorts clock alternatives by local clock value; list order is not
preference. This is the sole explicit alternative-value construction initially;
other interpretation alternatives remain separate reviewed candidate entries.

Resolve `date-term` as specified in Section 2.5. Moment endpoints have independent
dates: `thursday at 23:00` to `friday at 01:00` is valid; there is no implicit
next-day inference from an end clock preceding a start clock. A repeated local
clock asks for its occurrence if an offset does not already disambiguate it.
A supplied offset must agree with every eventual completed date/time value.
The date validation has an endpoint-role exception: a closing event/window
endpoint may resolve to W1 exactly, even though that date is outside the selected
week's seven day labels. For a week beginning 2026-10-26, an event from
`sunday at 23:00` to `2026-11-02 at 00:00` is valid. `2026-11-02 at 00:05`, a
start at W1, and `Remove clashes on 2026-11-02.` are not in scope. Resolve closing
endpoint roles before applying scope checks; do not globally reject the date
literal during lexical validation.

The date-based window form denotes that date's day or named-period occurrence,
intersected with its optional bounds. It is a complete allowed interval when the
date is resolved, even if neither bound was written. For a cross-midnight night,
bounds from 00:00 through **06:00 inclusive** refer to its following morning,
and bounds from 22:00 through 23:59 refer to its starting date. Clocks strictly
between 06:00 and 22:00 are invalid night bounds and require correction; do not
silently advance them to another date. `monday night by 06:00` includes its natural
Tuesday 06:00 end; `monday night after 06:00` has no feasible positive placement.
An exclusive `before 06:00` bound excludes an end at 06:00. For ordinary dated
whole-day windows, 00:00 means the starting midnight, not an inferred next day.
Empty intersections are diagnosed during evaluation.

`interval from ... to ...` gives an allowed containment interval; unresolved
endpoints are asked separately. `starting at ...` fixes the new event's start;
its end follows from its duration. It does not mean “no earlier than.” Bounds
inside a period constrain the new event, not every existing event's destination.

Window bounds constrain candidates exactly, even when not on the grid. Do not
round an allowed bound outward to manufacture permission. Normalize assigned
interval endpoints/fixed starts only under the explicit review policy; a bound
and a proposed appointment time have different roles.

A missing window is unresolved, not the whole week or an assumed working day.
`unspecified date morning after 09:00` retains its period and lower bound while asking
for its date. `thursday after unspecified` retains Thursday while asking for the
bound clock. A missing date can use an explicitly established task-date binding;
otherwise ask. A salience mention or the currently displayed date header alone
is not such a binding.

For repair, a requested date selects target events; it does not automatically
restrict all their complete intervals to that day. Night windows retain their
stated anchoring and the disclosed week clipping policy in Section 2.5.

### 10.3 Layer 1 commands

```ebnf
entry = sentence, { sentence } ;
sentence = command | question ;
command = (atomic-command | conceptual-command), "." ;
atomic-command = "create event from", moment-slot, "to", moment-slot, [ "with", initial-field, { "and", initial-field } ]
               | "delete", event-slot
               | "set", text-field, "of", event-slot, "to", text-slot
               | "set importance of", event-slot, "to", importance-slot
               | "set interval of", event-slot, "from", moment-slot,
                 "to", moment-slot ;
text-field = "title" | "location" | "description" ;
```

Atomic syntax requires its operation/operand positions. `Create event.` is not a
second shorthand; an incomplete atomic creation is
`Create event from unspecified to unspecified.` A reference/string hole is legal
only in a declared slot, not as a misspelling or missing token elsewhere.

```text
Create event from thursday at 10:00 to thursday at 10:30.
Set title of it to "Meeting with Mr Black".
Set location of it to "Head office".
Set importance of it to normal.
Set description of it to "".
Set interval of it from thursday at 23:00 to friday at 01:00.
```

Creation accepts the same nonempty field subset as `Schedule event`: title,
location, description, importance, once each in that order, joined by `and`.
For example: `Create event from friday at 11:00 to friday at 11:15 with title "Laundry machine mechanic".`
Omitted fields keep their defaults; explicit `unspecified` values use the existing
typed clarification rules. All supplied fields resolve before creation takes
effect, and the resulting event becomes the antecedent of `it`.

These are explicit assignments, not automatic scheduling. They may introduce
clashes and change a period, subject to week containment, reference validity,
write capability and explicit review of off-grid normalization. Creating with
missing endpoints asks before allocating or applying that creation's effects.

### 10.4 Layer 2 event references

```ebnf
identifier = "#", integer ;
event-slot = event-ref | "unspecified" ;
event-ref = identifier
          | "it"
          | "the event with", descriptor, { "and", descriptor }
          | "the unique event with", descriptor, { "and", descriptor } ;
descriptor = "title", string
           | "location", string
           | "description", string
           | "importance", importance
           | "start date", date-term ;
event-list = "[", [ event-ref, { ",", event-ref } ], "]" ;
event-list-slot = event-list | "unspecified" ;
```

Descriptors appear at most once and in title–location–description–importance–
start-date order; any nonempty ordered subset is allowed. `and` joins these
fields, not Boolean conditions. Strings compare exactly, including case and
emptiness. Start date is the Budapest date of the original/current event's actual
start. Arbitrary predicate grammar, nested descriptions, general collection
filters and quantified user commands are deferred.

`#N` is a persistent conversation-local handle mapped to one Google event
identity. Allocate handles monotonically; never reuse them for another event
after deletion, cancellation or any later Undo implementation. Import order must
not renumber existing handles. Provider identities, not title/time similarity,
establish mappings. Allocation bookkeeping is not a SQL mirror of event content.
Handle creation for imports and speculative creations is deterministic; reserved
handles may leave gaps after cancellation. Multiple segments share one handle.

A known handle outside the universe is a scope failure; a deleted/missing handle
is a missing-reference failure. Neither is a request to allocate or resurrect.
Section 13 defines durable provider-ID reservation for creation. That mapping is
an adapter/orchestration responsibility, not a user-level reference syntax rule.

Use the existing entry/utterance-age policy: current entry plus previous three,
`it` resolves the lexicographically most recent eligible event mention, and ties
ask. An anaphoric description uses compatible currently true descriptor evidence,
with each descriptor's best score `10 × entry age + utterance age`; candidates
less than `n + 1` above the best total tie for n descriptors. With no eligible
matching discourse evidence, search the universe; zero matches fail, one resolves,
and multiple ask. Do not bypass an eligible salience tie with world fallback.
The `unique` form searches the universe without salience preference; multiple
matches still ask which identity was intended.

Resolve all operands of an operation against its initial world/discourse, retain
chosen identities through clarification, and reject duplicate resolved list
members. An empty event list is permitted only as an empty protected set. Any
missing explicit member is a failure, not an instruction to drop it.

Only events are discourse referents initially; dates, periods, clock values,
intervals, task IDs, algorithm-inspected obstacles and returned schedules do not
become additional `it` antecedents. Successful explicit operands and newly created
events receive mentions. Internal macro atoms do not age discourse individually.
Bulk repair mentions events actually changed at equal recency; insertion mentions
the new event and explicitly changed existing events at equal recency. Ties are
clarified, never broken by list order. Successful no-change operations mention
explicit operands; a no-clash repair does not mention every inspected event.

Retain only explicitly mentioned truthful facts; purge stale facts after changes.
GUI edits purge without adding chat mentions. Pending clarification does not add
mentions or age an entry again. A failed evaluated command ages its sentence once
but adds no successful mention, matching the other domains' convention.

### 10.5 Layer 3 task commands

```ebnf
conceptual-command = schedule-command | insertion-command | repair-command ;
schedule-command = "schedule event", task-body ;
insertion-command = "make room for event", task-body, movement-options ;
repair-command = "remove clashes", [ "on", date-slot ], movement-options ;
task-body = [ "lasting", duration-slot ], [ "within", window-slot ],
            [ "with", initial-field, { "and", initial-field } ] ;
initial-field = "title", text-slot
              | "location", text-slot
              | "description", text-slot
              | "importance", importance-slot ;
movement-options = [ ", moving up to", threshold-slot ],
                   [ ", protecting", event-list-slot ],
                   [ ", choosing", tie-policy ] ;
tie-policy = "ask" | "preserve original order" ;
```

Initial fields are unique and ordered title–location–description–importance.
Task clauses and movement clauses have the exact order above. Omitted clauses
are allowed only where the grammar marks them optional; reordered/duplicate
clauses are invalid. The engine formats supplied fields canonically and exposes
all active defaults/holes in task review.

| Omitted material | Evaluated meaning |
| --- | --- |
| `lasting ...` | Unresolved duration; no one-hour default |
| `within ...` | Unresolved placement window; no working-hours default |
| Initial title/location/description | The respective empty string |
| Initial importance | Normal |
| `on ...` in repair | Unresolved target date |
| `moving up to ...` | Unresolved movement permission, not Normal and not Critical |
| `protecting ...` | Empty explicitly protected set; existing capability/threshold protections still apply |
| `choosing ...` | Ask about material equal optima |

Explicit `unspecified` in an initial field asks about that field rather than
using its default. Explicit `protecting unspecified` creates an unresolved
protection question; it does not become an empty list. Defaulting and missing
information are deliberately different.

`Schedule event` never moves existing events and rejects movement clauses.
`Make room for event` can ask for movement permission when it actually needs it.
Its placement window applies to the new event; movable existing events retain
their inferred envelopes and dates. `Remove clashes on D` selects every in-scope
event intersecting D, applies the whole-event repair contract, and moves only
members of that frozen target set. All other events are fixed obstacles. Thus
repair cannot silently rearrange another day's unrelated appointments. Insertion
may consider all in-scope events allowed by its movement permission and protected
set, subject to each event's own inferred bounds. Do not restrict candidates only
to events currently clashing with the new interval, or only to envelopes directly
intersecting it: relocation chains may need other events. Permissions apply to
every moved event, and weighted optimization determines which moves are necessary.

`preserve original order` delegates only tie-breaking among equal-cost complete
solutions, using chronological original starts: if A originally starts before B,
its proposed start must not be later than B's. Original equal-start events impose
no order. This does not override the primary cost or turn ordering into a new
feasibility constraint. If no optimal solution preserves that order, or several
material optima remain, ask rather than accepting a higher cost or inventing an
identity-based secondary order.

```text
Schedule event.
Schedule event lasting 45 minutes within thursday morning
  with title "Meeting with Mr Black" and location "Head office".
Schedule event lasting unspecified within unspecified date morning after 09:00.
Schedule event lasting 30 minutes within starting at thursday at one of [05:00, 17:00].
Make room for event lasting 60 minutes within starting at thursday at 09:00
  with title "Urgent meeting" and importance important,
  moving up to normal, protecting [#4], choosing ask.
Make room for event lasting 90 minutes within thursday afternoon.
Remove clashes.
Remove clashes on thursday, moving up to normal, protecting [], choosing ask.
```

Canonical task formatting emits all task fields in grammar order, filling omitted
required inputs with `unspecified`, omitted initial fields with their literal
defaults, and omitted movement options with `unspecified`, `[]` and `ask`
respectively. Repair emits `on unspecified date` when its date is absent. Short forms
above parse to that same representation. Formatting never fills an unresolved
permission with a grant.

No phrase claims that a person's calendar is available or sends invitations.
“With Mr Black” remains a field interpretation, not an unimplemented attendee
operation. Requests for extra buffers, arbitrary destination windows for existing
events, repair of explicit collections, global week-wide repair, different
optimization rules, or other unsupported constraints are preserved
as interpretation issues, not silently stripped to fit one of these forms.

## 11. Clarification is an evaluation outcome

### 11.1 Parsing incomplete requests versus evaluating them

The grammar accepts a well-typed request with unresolved parameters. Parsing
produces the request structure and typed holes; it does not ask the LLM to fill
them, choose an event, grant movement permission or solve a schedule. Evaluation
may return **Needs clarification** instead of a world transformation.

For each sentence, the engine follows this authoritative order:

1. Settle whole-entry interpretation/Boolean scope choices before any sentence
   executes, then resolve this sentence's explicit operands and interpretation.
   No task-specific shortcut overrides this step.
2. Ground temporal expressions, known fields and constraints from the entry's
   frozen context and previously established task commitments.
3. Validate supplied values. A validly parsed `0 minutes`, invalid endpoint order,
   impossible local time, or contradictory window gets a precise diagnostic and
   a correction opportunity; it is not silently replaced with an unspecified
   value/default. Preserve the rejected value and reason in the decision record.
4. Complete required task meaning, including explicit field/condition/protection
   holes and explicit references. A no-change/no-movement shortcut cannot skip
   them. Only a movement threshold may remain unanswered if no movement is needed.
5. Perform pure feasibility/search work only when its meaning is established.
   It may perform the no-movement baseline without movement permission.
6. Return a bounded result, a solver status, another clarification, or a proposed
   completed effect with its explanation and required review.

Use a dependency-aware question order: interpretation/reference, date/occurrence,
duration, placement bounds and explicit field holes, protection holes, then any
necessary movement permission, then material solution choices. Never treat this
as a mandatory questionnaire. For example, a named morning supplies both bounds;
a request with an established duration does not ask it again.

A clock's AM/PM or DST occurrence is resolved before occupancy-based search.
Conversely, movement permission is asked only after a no-movement attempt fails
or when an explicitly requested repair requires movement. A repair with no
required clashes in either model can complete without asking a threshold. An explicit unresolved protection list must
be completed before any task result; the no-movement shortcut cannot discard it.

### 11.2 Pending evaluation and answer authority

A pending clarification contains, as semantic state:

| Component | Required contents |
| --- | --- |
| Identity | Entry/task ID, command index, task revision and active question ID |
| Context | Selected week, frozen Budapest clock, language/policy versions and relevant snapshot fingerprint |
| Request | Parsed command, known values, typed holes and interpretation alternatives |
| Commitments | Each explicit/default/derived value, source turn, permission scope and dependency links |
| Resolution | Grounded handles, frozen selections, temporal occurrences and consumed choices |
| Progress | Completed semantic prefix and any provisional work, with its status made visible |
| Search | Validity context for cached results, candidate evidence, limits and unresolved material optima |
| Discourse | Pre-command ranking and pending mentions; no speculative mention is committed |

Questions are clear ordinary English with stable typed response alternatives.
They are not statements in the controlled language and cannot themselves mutate
events. The LLM may render the question without changing its alternatives, facts
or permission scope. A numeric/Boolean/textual answer is not a new scheduling
command merely because it can be parsed as natural language.

The response boundary carries the task ID/revision, question ID and a typed value
or selected engine-issued option ID. Direct UI choices can supply this without
an LLM. A free-text answer may be translated into a proposed typed response; the
engine validates that it answers the actual pending question. The exact HTTP/JSON
schema is deferred. This response protocol is separate from executable entry syntax.

- Wrong-type or out-of-range answers keep the question pending and explain why.
- Stale question/revision/option IDs are rejected; never apply them to a new question.
- A new value cannot change unrelated fields. “Important” in the threshold question
  authorizes levels 0–1 within its displayed scope; it does not change event importance.
- An unclear reply triggers clarification of the reply; it does not establish consent.
- Answering a parameter or granting movement permission does not also accept the
  final proposed schedule. Final review/acceptance remains a separate action.
- Completing a hole resumes the same command and entry, without rerunning earlier
  completed commands, duplicating creation, reallocating a resolved identity, or
  re-aging discourse for each answer.

### 11.3 Revising established requirements

A revision is an explicit task-control action identifying the task revision and
field/path to replace. It may arrive through a GUI control or interpreted answer;
it is not an arbitrary hidden replacement of the whole controlled entry. The
engine validates a typed patch and reports the old and new values. Patchable
command fields are duration, window or its unresolved date/bounds, initial event fields,
threshold, protected list, repair target date and tie policy, as applicable to
the particular task. The task family cannot change through a field patch.

Invalidate dependent grounding, solver evidence and proposals, but retain every
unaffected user commitment. In particular, a duration change does not erase a
threshold, title or protected set. Recompute frozen target selection only when
its explicit selector/date changes; otherwise retain the selected identities.
Permission is scoped to the reviewed task context: an expanded week, target set
or materially changed movement scope requires renewed approval, even if the
threshold value is retained. Do not infer broader permission from an old answer.

A revision after an event change was externally confirmed starts a new operation;
it cannot rewrite history as though the earlier write never happened. Cancel and
reject are explicit controls, not a choice of zero duration or threshold None.
Changing task family, such as moving from earliest-only scheduling to insertion,
requires a new reviewed task that can explicitly carry forward known constraints.
The engine cannot grant movement permission during that transfer.

### 11.4 Semantic sequences and effects while paused

Sentences in an entry evaluate left to right against preceding successful semantic
results. The affected sentence has no completed domain or discourse effect while
it needs clarification. Earlier completed commands are identified separately
from provisional effects; later commands are not executed. A failed command stops
the sequence; a successful no-change command continues. Clarification resumes
that command once, preserving its already resolved operands.

A conceptual task is one semantic operation. Its private search, creation/setter
expansion and speculative moves are not independent user commands, salience ages
or public intermediate appointments. No complete task effect is returned until
its required clarifications and candidate checks succeed. A blocked/infeasible
operation creates no event and no completed salience mentions of its own.

These rules govern semantic evaluation and pending work. Section 13 makes the
execution boundary definite: evaluate privately, obtain explicit acceptance of
the completed entry or its successful prefix, and then apply the recorded plan.
There is no implicit rollback of cloud writes and no Calendar Undo in v1.

If the relevant calendar/context changes, do not resume or accept using stale
solver results. Refresh and revalidate commitments, inferred envelopes, selected
identities and permissions; expose consequential changes and ask again as needed.
Deleting a referenced event is a failed reference, not permission to substitute a
similar title. Pending task/discourse state is persistent; restoring it after a
restart still requires context validation under Section 13. GUI editing and further executable
entries remain disabled while a task is busy/pending, apart from its explicit
answer, revise, cancel and context-change controls. An explicit week change
cancels pending work as specified in Section 2.1.

### 11.5 Worked incomplete-request evaluations

**Earliest scheduling:**

```text
Schedule event within thursday morning with title "Meeting with Mr Black".
```

The engine already has Thursday 09:00–12:00 and the title. It asks “How long should
the meeting last?” The answer 45 minutes completes the duration; it does not
create a second task. The engine computes the earliest interval and presents it
with empty location/description and Normal importance disclosed. It does not ask
for optional text that already has agreed defaults. Acceptance remains separate.

**Insertion with retained requirements:**

```text
Make room for event lasting 90 minutes within thursday afternoon
  with title "Meeting" and location "Head office".
```

First search 13:00–18:00 without moving events. If no placement exists, ask the
maximum movable importance threshold. An answer Normal preserves duration,
window, title and location while granting only Normal movement under the stated
inferred bounds. If infeasibility is established and the user explicitly revises
duration to 60 minutes, retain the other commitments and threshold, invalidate
the old solver result, and solve again. Never silently ask for or assume a higher
threshold. If the new duration fits without movement, propose it without using
the granted permission gratuitously.

**Repair with an unresolved day and protected selection:**

```text
Remove clashes on unspecified date, protecting unspecified.
```

Ask the day, then the protected-event selection. If neither model has required
clashes, report no change without requesting movement permission. Otherwise ask the threshold,
respect protection regardless of threshold, and run the repair solver. A choice
among equal optima carries engine-issued schedule IDs, not invented event edits.

**A pause inside a sequence:**

```text
Create event from thursday at 10:00 to thursday at 10:30.
Set title of it to unspecified.
Set location of it to "Head office".
```

The second command retains the newly resolved identity and asks for its title.
The third waits. An answer `""` is valid and clears/keeps the empty title; it is
not a missing response. Resuming does not repeat creation. The interface labels
the first command's semantic result and external-commit status separately.

### 11.6 Additional acceptance obligations

- Every grammar example parses completely and has a canonical round-trip form.
- Missing required task parameters parse as holes; malformed syntax does not.
  Empty string, unspecified string, absent clause, threshold None and no answer
  have their distinct meanings and tests.
- Both endpoint dates, night anchoring, AM/PM choices, DST offsets and boundary
  inequalities follow the same evaluation rules in direct commands and tasks.
- Negative/invalid literals fail at the specified phase; no error is repaired by
  guessed intent. Unknown operation aliases and unsupported clauses are rejected.
- Literal identity references cannot allocate; duplicate resolved protected-list
  members fail; ambiguous titles ask rather than selecting import order.
- Suspended evaluation survives restart and resumes once. Earlier commands and
  resolved references are neither replayed nor reassigned after an answer.
- Revision invalidates dependencies without erasing independent requirements;
  stale answers, stale candidate choices and broadened permissions are detected.
- Clarification and rejected previews do not alter committed salience. Internal
  search atoms cannot leak partial task effects or false explanatory evidence.

## 12. Atomic and conceptual questions

**Proposed addition to the first grammar:** questions are executable speech acts
with symbolic answers, not requests for an LLM opinion. They may be incomplete
and pause for clarification under Section 11. They never write calendar events
or silently become scheduling commands. A question's subjects, answers and
clarification history can change discourse state without changing calendar data.

### 12.1 Entry grammar extension and atomic questions

The shared entry productions from Section 10.3 are repeated here with the
question productions:

```ebnf
entry = sentence, { sentence } ;
sentence = command | question ;
question = (atomic-question | conceptual-question), "?" ;
identifier-slot = identifier | "unspecified" ;
event-field-slot = event-field | "unspecified" ;
atomic-question = "does", identifier-slot, "exist"
                | "what is the", event-field-slot, "of", event-slot
                | "does", event-slot, "satisfy", event-condition ;
event-field = "title" | "location" | "description" | "importance"
            | "start" | "end" | "interval" ;
```

The `satisfy` wrapper is shared across layers: its field equality predicates
below are layer 1, while derived predicates belong to layer 3. Layer 1 subjects
are identifiers; layer 2 adds the reference forms already in Section 10.4.
`event-condition` is defined in Section 12.2. Upper/lowercase spellings below
are equivalent; question marks are mandatory.

| Atomic question | Answer and failure contract |
| --- | --- |
| `Does #3 exist?` | Membership in the current language universe; no prerequisite existence resolution |
| `What is the title of R?` | A string, possibly `""`; never a display fallback |
| `What is the location of R?` | A string, including `""` |
| `What is the description of R?` | A string, including `""` |
| `What is the importance of R?` | Normal, Important or Critical |
| `What is the start of R?` | Normalized full date/time, with original disclosed if different |
| `What is the end of R?` | Normalized full date/time, with original disclosed if different |
| `What is the interval of R?` | Both endpoints, using the same disclosure rule |
| `Does R satisfy title is S?` | Exact string equality, including emptiness and case |
| `Does R satisfy location is S?` | Exact string equality |
| `Does R satisfy description is S?` | Exact string equality |
| `Does R satisfy importance is I?` | Categorical equality |

R/S/I are explanatory metavariables, not literal operands. Actual entries use
references and typed values from Section 10.

`What is the unspecified of #3?` asks which event field is wanted, retaining
the subject. A completed field name determines the answer type.

A missing or out-of-scope subject is a diagnostic for all queries except explicit
identifier existence. Existence answers false with the qualification “in the
selected week”; if the mapping already distinguishes outside-scope from deleted
identities, disclose that distinction without fetching an expanded universe.
It does not claim that no corresponding event exists anywhere in Google.
An unknown handle returns false, not allocation. `Does unspecified exist?` asks
which handle is being checked. A failed description is not an existence answer.

Successful questions mention explicit resolved event subjects even when their
answer is false. A false field test adds no false descriptor fact. A successful
existence check may mention its present handle; a false one introduces no missing
event antecedent. Values returned by a question are not new event referents.

### 12.2 Reusable conditions, scope and typed incompleteness

```ebnf
comparison = "is" | "is at least" | "is at most" ;
event-condition = event-atom
                | "not", event-condition
                | event-condition, "and", event-condition
                | event-condition, "or", event-condition
                | "(", event-condition, ")" ;
event-atom = "true"
           | "unspecified"
           | text-field, "is", text-slot
           | "importance", comparison, importance-slot
           | "starts on", date-slot
           | "within", window-slot
           | "overlaps", window-slot
           | "overlaps event", event-slot
           | "before event", event-slot
           | "after event", event-slot
           | "duration", comparison, duration-slot
           | "has a clash", [ "within", window-slot ] ;
```

A complete condition hole `unspecified` asks what property is intended; it is not
`true`. A typed sub-hole such as `importance is unspecified` asks only for the
importance, retaining the field/comparison and any other conditions.

| Predicate | Exact meaning |
| --- | --- |
| `true` | Every member of the finite event universe |
| Text equality | Exact total-string equality; `""` is a real value |
| Importance comparison | Ordinal comparison of 0, 1, 2, independent of color spelling |
| `starts on D` | Normalized start's Budapest date equals D |
| `within W` | Entire normalized interval lies in the allowed interval W |
| `overlaps W` | Positive intersection with W; touching a boundary is insufficient |
| `overlaps event R` | Positive intersection with resolved R; self-overlap is true |
| `before event R` | Subject end is at or before R's start; adjacency qualifies |
| `after event R` | Subject start is at or after R's end; adjacency qualifies |
| Duration comparison | Compare normalized elapsed duration with the supplied positive five-minute duration |
| `has a clash within W` | There exists a distinct in-scope event whose overlap with the subject intersects W positively |

An event never clashes with itself. This is distinct from testing interval
overlap with itself. A positive-duration event is neither before nor after itself.
Unqualified `has a clash` means within the selected week, an explicitly defined
predicate default. Canonical output expands it to `has a clash within selected week`.
Section 10.2's window grammar includes the literal `selected week` for this purpose
and for explicit whole-week questions. There is no hidden day or working-hours
assumption. `within starting at ...` is not a meaningful containment/count scope:
that window variant is placement-only and fails static role checking in queries
other than placement/planning questions.

Predicates use the normalized model consistently. When normalization changes a
temporal answer, matching set or count compared with exact originals, disclose
both and identify the affected events/pairs. Do not describe a normalized clash
count as an exact Google count when they differ. Week membership still uses exact
originals. `starts on D` in a condition intentionally tests the model projection;
Section 10.4's `start date` reference descriptor tests original truth. If these
differ, the distinction is shown, not used to retarget a previously resolved event.

For interval/order predicates with an event operand, resolve the target once
before testing subjects. In selection/quantification it is a fixed external
target, never an implicit variable bound to each selected event. Failure of an
explicit target is a diagnostic even under negation, in an empty selection, or
in an apparently short-circuited Boolean branch. Resolve all typed holes and
references needed to establish the question's meaning before answering; do not
return zero/false just because an unresolved branch currently looks irrelevant.

There is no implicit Boolean precedence. Produce explicit grouping alternatives
before evaluating any sentence if omitted parentheses leave consequential scopes.
Associative chains of only `and` or only `or` normalize directly. Equivalence must
not depend on coincidentally equal answers in today's calendar. Negation scope
uses the same rule. Explicit parentheses settle the choice; a selected reading
can still need reference/parameter clarification during evaluation.

These conditions are reused without a weaker predicate subset in direct checks,
selection, counting and quantification. Arbitrary nested quantifiers, bound-variable
pronouns and computed references remain deferred. Section 10.4's ordered simple
reference descriptions stay unchanged; this addition does not introduce a second
implicit description syntax.

### 12.3 Derived values, selections and quantifiers

```ebnf
quantifier = "every" | "some" ;
conceptual-question = derived-question | selection-question
                    | availability-question | conflict-question
                    | planning-question ;
derived-question = "what is the duration of", event-slot
                 | "what is the gap between", event-slot, "and", event-slot ;
selection-question = "which events match", event-condition
                   | "how many events match", event-condition
                   | "does", quantifier, "event matching", event-condition,
                     "satisfy", event-condition ;
```

Duration is elapsed time between normalized endpoints. Gap is symmetric:
for disjoint intervals return the elapsed separation, including zero for
adjacency; for overlapping intervals report `overlap` and its duration and
interval, never a misleading negative gap. Also disclose differing exact-original
results. Temporal answers include dates, timezone and offsets where necessary;
normalization differences may require seconds even though user input is minute-based.

Selection returns distinct stable handles in ascending handle order, not one
result per daily segment. An empty result is `[]`; its count is 0. Every/some
range over the whole in-scope universe filtered by the restriction. Empty every
is true and empty some is false, both with an explicit empty-restriction
explanation. There is one quantifier per question, with restriction and test
applied to the same event. Resolve external event operands eagerly as above.

No implicit commitment is made to every selected event as a discourse antecedent.
Only explicit resolved subjects/targets are mentioned; inspected members and
aggregate result handles do not all become eligible for `it`. Evidence for an
answer records the tested member set and normalized/exact basis without inventing
false salience facts. Boolean answers, counts, empty results, reference failures
and pending clarifications remain distinct outcomes.

```text
What is the duration of #3?
What is the gap between #3 and #4?
Does #3 satisfy overlaps event #4?
Which events match within thursday morning?
How many events match importance is critical and overlaps thursday?
How many events match has a clash?
Does every event matching importance is critical satisfy within thursday morning?
Does some event matching true satisfy duration is at least 60 minutes?
How many events match importance is unspecified and overlaps thursday?
How many events match unspecified?
```

The last two questions are well-typed incomplete requests. One asks for an
importance; the other asks for a selector. Neither delegates selector invention
to the LLM. The engine does not substitute `true` for an omitted intention.

### 12.4 Availability and conflict counts

```ebnf
availability-question = "which intervals are free", [ "within", window-slot ]
                      | "what is the earliest available interval",
                        placement-parameters ;
placement-parameters = [ "lasting", duration-slot ],
                       [ "within", window-slot ] ;
count-unit-slot = "pairs" | "events" | "unspecified" ;
conflict-question = "which event pairs clash", [ "within", window-slot ]
                  | "how many overlaps occur", [ "within", window-slot ],
                    [ ", counting", count-unit-slot ] ;
```

An omitted availability/counting window is unresolved and produces a scope
question. `selected week` explicitly supplies the whole universe's temporal
bounds. Absence is not silently interpreted as “today,” “Thursday,” or “all week.”
The unqualified `has a clash` predicate default above is separate and deliberate.

`Which intervals are free` returns maximal positive free intervals using the
same conservative busy union of normalized and exact unchanged intervals as
Concept 1. It does not enumerate all possible subintervals or round free-gap
boundaries outward. Report the first eligible grid start in a gap when relevant.
The earliest-interval question also needs duration and uses Concept 1's complete
algorithm and clarification rules, returning an interval or a bounded nonmatch.
A `starting at` placement window is valid for the earliest-interval question:
only that start qualifies, so report failure if blocked rather than choosing later.

For conflicts, first form unordered pairs of distinct events. A pair qualifies
within W when the pair's overlap interval intersects W with positive duration.
Count each qualifying pair once. Listing returns both handles and the clipped
witness overlap, with full event intervals available in details. Pair presentation
is sorted lexicographically by ascending handles; this is display ordering only.

`counting pairs` returns the number of qualifying pairs. `counting events` returns
the number of distinct events incident to at least one qualifying pair. Three
simultaneous events give three pairs and three affected events. A long event
clashing with four nonoverlapping short events gives four pairs and five affected
events. A cross-day pair counts once over a multi-day window, not once per day.
Two disjoint sets of pairs with adjoining/overlapping witnesses are not merged
into a count of busy periods. Connected conflict components, time-overlap periods
and maximum concurrency are different questions, deferred from this inventory.

Omitting `counting ...` or supplying `counting unspecified` leaves the counting
unit unresolved. Ask “Do you mean the number of clashing pairs or the number of
events involved?” Never infer the unit by looking at whether the numbers happen
to agree. An ordinary request “How many overlaps are there?” must preserve this
hole rather than silently choose a unit. The exact completed forms are:

```text
How many overlaps occur within thursday, counting pairs?
How many overlaps occur within thursday, counting events?
Which event pairs clash within thursday?
How many overlaps occur within unspecified, counting pairs?
How many overlaps occur within thursday?
How many overlaps occur?
Which intervals are free within thursday afternoon?
What is the earliest available interval lasting 60 minutes within thursday afternoon?
What is the earliest available interval?
```

The count of events matching `has a clash within thursday` equals the affected-
event count within Thursday. In contrast, `overlaps thursday and has a clash`
can include an event present Thursday whose actual clash happens Wednesday;
the explicit clash scope is consequential and must be retained in interpretation.
Likewise, `starts on thursday`, `within thursday` and `overlaps thursday` differ.
A Critical cross-day event overlapping Thursday counts once in Thursday's event
selection, regardless of whether its start is Wednesday.

Compute conflict witnesses with a sweep-line algorithm or pairwise checking of
the finite event set; normalize each pair's identity order before deduplication.
Use end-exclusive boundaries when processing simultaneous starts/ends. Recompute
exact-original witnesses and disclose discrepancies as specified in Section 12.2.
For free intervals use interval union/complement, not an LLM-generated list.

### 12.5 Planning questions reuse the task solvers

```ebnf
planning-question = "can an event", placement-parameters,
                    "fit", movement-options
                  | "what is the minimum movement cost to fit an event",
                    placement-parameters, movement-options
                  | "can clashes", [ "on", date-slot ],
                    "be removed", movement-options ;
```

Examples follow the exact clause order: the feasibility form places `fit` after
its placement parameters. These are the same three task families, not additional
scheduling objectives or hypothetical programs.

```text
Can an event lasting 90 minutes within thursday afternoon fit, moving up to normal?
What is the minimum movement cost to fit an event lasting 90 minutes within thursday afternoon, moving up to normal?
Can clashes on thursday be removed, moving up to normal?
Can an event fit?
Can clashes be removed?
```

The feasibility/insertion forms invoke Concept 2; repair invokes Concept 3.
The no-movement case is handled by Concept 1. Omitted duration/window/date and
movement scope use the same typed holes and dependency-aware questions as their
command counterparts. Protected sets, inferred period/date restrictions,
normalization/exact checks, read-only events and the finite grid remain identical.

The threshold now describes **hypothetical permission for the computation**, not
actual authorization to change Google events. Ask “What maximum importance should
I consider movable for this calculation?” A subsequent action must be separately
reviewed and approved. The system may offer to carry known constraints into that
action, but cannot treat an affirmative feasibility answer or a hypothetical
threshold response as write permission.

A feasibility answer includes a checked witness schedule when true. If exhaustive
search proves false, state the scoped domain/constraints and available obstruction.
If the budget expires, report unresolved feasibility rather than false. A valid
witness can establish feasibility even if optimization is unfinished. A question
asking only feasibility does not force the user to pick between equivalent valid
witnesses: state that the displayed one is an example, selected by disclosed
solver enumeration, not a preference or an action to execute. Choosing which
schedule to apply remains a later decision.

For minimum cost, return the proven optimum with its weighted contributions and
a witness. If interrupted, report best known cost and a sound lower bound when
available, explicitly labeled “optimum not established”; do not replace an optimum
question with an unqualified feasible answer. When no arrangement exists, say
`infeasible`, not zero or infinity disguised as a numeric optimum.

Multiple optimal witnesses do not make a scalar optimum ambiguous. Return the
cost and label any displayed arrangement as an example; ask for a schedule
choice only if the user requests choosing/applying one. `choosing ...` in a
planning question controls witness presentation among equal optimum witnesses;
it cannot change the numeric answer, increase the cost, or authorize writes.
If a requested order cannot be met among optima, explain that limitation without
falsely declaring the underlying problem infeasible.

### 12.6 Clarification, revision and discourse for questions

Section 11's pending evaluation is extended from commands/tasks to all sentences.
Store sentence kind, answer type, parsed condition, temporal/counting scope,
counting unit, resolved targets, known parameters, typed holes, grounding,
decision provenance and answer evidence. A pending question uses the same stable
IDs, revision checks and persistent continuation machinery. Its answer is an
engine result; a clarification reply fills a parameter, not that result.

Additional patchable parameters are atomic query field/subject, conditions and
their typed sub-values, comparison operators, quantified restriction/test,
counting window/unit and planning bounds. Replacing the speech act or requested
result type starts a new reviewed question; a field patch cannot turn a query
into a write. Revisions invalidate dependent answer evidence while preserving
independent date, duration, protection and threshold commitments within their
original scope. Wrong or stale answers retain the pending question and explain
why they were rejected.

Resolve Boolean scope before entry evaluation, then event references and temporal
meaning; ask for missing selectors/values and counting unit/scope as needed.
Planning questions may delay a hypothetical threshold question until a no-movement
baseline proves insufficient. Other unresolved parameters cannot be guessed or
ignored because a preliminary result seems obvious. A syntactically invalid
question is rejected before execution, not treated as an incomplete valid one.

```text
How many events match importance is unspecified and overlaps thursday?
```

The engine asks which importance and retains Thursday. Answering Critical resumes
counting with that condition. A subsequent explicit revision to Important retains
Thursday and computes a new answer; it does not reinterpret “Important” as a
movement permission or mutate any event.

```text
How many overlaps occur within thursday?
```

The engine asks pairs versus affected events. Answering pairs supplies a counting
unit, not a numeric result. If the user then revises Thursday to Friday, preserve
that unit, refresh the relevant evidence, and compute Friday's pair count.

```text
What is the minimum movement cost to fit an event within thursday afternoon?
```

Ask duration; retain Thursday afternoon. Search without movement first. If a
zero-cost placement exists, the optimum is zero and no hypothetical movement
threshold is needed. Otherwise ask which importance levels may be considered
movable. Do not declare infeasibility solely because that permission is missing.

Question evaluation mentions only its explicit resolved operands under the shared
salience policy. Correct answers do not commit hypothetical placements, future
field values or solver-inspected obstacles as current facts. Completing a
question or resolving its parameter holes ages the sentence once, not once per
clarification round. A question followed by `Set title of it ...` can use its
explicit event subject; a count followed by `it` cannot silently pick the first
counted member. Clarification questions and their English wording introduce no
extra event mentions.

### 12.7 Question acceptance obligations

1. Atomic strings return `""` for emptiness; display fallback text never becomes
   a stored/answered title. Missing subjects and false field values remain distinct.
2. Existence is scoped membership and cannot allocate; unresolved identity input
   asks rather than answering false. Out-of-week identity results are qualified.
3. Every condition is available in checks, selection, counting and quantification;
   all explicit targets resolve even for empty sets and under negation.
4. Boolean scope alternatives pause before any entry effects. Matching truth
   values in one snapshot do not suppress meaningful grouping clarification.
5. Cross-day identities count once; unordered clash pairs count once. Test three
   simultaneous events, a four-leaf conflict star, cross-day witnesses, adjacent
   endpoints and overlapping week boundaries excluded from the universe.
6. A missing counting unit triggers a question even if pair/event totals coincide.
   Missing scopes/selectors are retained holes; named periods and explicit whole-
   week scopes supply their bounds without unnecessary questions.
7. Every/some follow empty-set semantics and do not invent bound pronoun targets.
8. Normalized/exact differences are disclosed. Free intervals and proposed starts
   cannot manufacture space by rounding away occupied original time.
9. Questions share verified command algorithms but make no calendar writes;
   hypothetical thresholds and witnesses never confer real movement permission.
10. Feasibility, infeasibility, proven optimality and resource-limited answers stay
    distinct. Equal optimal schedules do not prevent answering a scalar cost.
11. Pending questions survive restart, reject stale replies, resume once, and
    retain unrelated commitments on revision. Aggregate results create no arbitrary
    event antecedent and hypothetical results create no false current facts.

## 13. Version, execution and resource contracts

The following are selected **demo policies** under the user's delegation. They
resolve specification gaps; they do not describe already implemented behavior
or promise distributed transactions. All executable proposals use semantic
version **`calendar-v1`** with policy **`calendar-demo-1`**, including the five-minute
grid, inferred envelopes, weighted objective and clarification rules above.

### 13.1 Private evaluation, review and successful prefixes

Evaluate an entry against a frozen input calendar/context and a private discourse
state. Earlier successful sentences supply values, identities and salience to
later sentences. All such results remain **provisional** until this entry reaches
its applicable completion/acceptance boundary. Clarification or speculative
search never changes the committed calendar or committed discourse ranking.
Handle reservations may advance monotonically; they do not establish existence.

For an entry containing mutations:

1. Resolve clarification and evaluate the entry privately. Present proposed net
   changes, explicit successful no-ops, answers, inferred constraints, permissions
   and any unexecuted suffix. A task's internal atoms never become public writes.
2. If all sentences succeed, offer acceptance of the complete evaluated entry.
   If a sentence fails or a search limit stops it, retain the successful prefix
   as a separate **prefix proposal**. Nothing is applied automatically. The user
   may explicitly accept that prefix, revise/re-evaluate pending work, or discard
   it. Prefix acceptance terminates the unexecuted suffix; it never schedules a
   hidden continuation to run later after changes are applied.
3. Acceptance names the entry revision, exact reviewed effect plan and context
   fingerprint. Reject stale acceptance rather than silently replan and execute.
   Recheck the relevant exact calendar state and all write-capability restrictions
   before application. External changes invalidate dependent work for renewed review.
4. Apply only the reviewed net changes after the required acceptance. Retain event
   identity and change only named/derived fields; coalesce multiple staged changes
   to the same field into its final value. Retain explicit encoding intent: setting
   Normal writes color ID 10 even if the old color already decoded to Normal.
   Staged create-then-delete has no provider
   event effect. The decision record still retains its meaningful intermediate
   operations and any valid discourse consequences.

A clarified answer, movement threshold, solver witness or interpretation preview
is not final acceptance of event writes. Explicitly accepted input can authorize
evaluation; where the resolved plan materially adds choices, it still needs final
review under this contract. No implicit best-effort execution policy is accepted.

Question-only entries make no event writes. Once meaning is accepted/resolved and
the relevant context is validated, finalize their answers and discourse state
without an event-write confirmation. If one question fails after earlier answered
sentences, commit the successfully completed question prefix's discourse once,
mark the failed/suffix sentences separately, and do not invent a domain update.
Earlier answers describe the frozen evaluation context, with its date/week shown.
Questions inside a mutating entry are labeled provisional until that entry's
outcome; they may describe a staged world, not the calendar currently on Google.

Revisions to an already finalized question are new executable question entries
with explicit carried-forward commitments, not edits to historical discourse.
Revisions of a still-pending entry retain its original identity and advance its
revision, with dependency invalidation as specified in Sections 11–12.

### 13.2 Durable application and confirmed completion

Before the first write, orchestration records the accepted plan and its stable
operation IDs in a recovery journal. This is execution bookkeeping, not a
synchronized SQL event store: Google remains authoritative. Store only the
required identity mappings, changed-field before/after images, context checks,
operation status and decision/discourse data needed to explain or recover this
operation. Persisted pending work can retain a compact staged delta and input
fingerprints; after restart, refetch Google rather than treating a saved world
as authoritative. Temporary plan evidence is retired when recovery completes.

Assign each proposed new event a Google-compatible creation ID once, durably,
before submission. Reuse that lookup identity for verification; do not allocate
a new creation ID just because a response was lost. This is an internal adapter
contract, not permission for public callers to choose arbitrary Google IDs.

Apply serially through the local MCP adapter: existing-event updates in ascending
stable-handle order, then creations in reservation order, then deletions in
ascending handle order. This ordering is transport determinism, not a semantic
preference. Intermediate Google states may contain transient clashes; the system
promises a validated final result, not transaction isolation or clash-free
intermediate remote states. All in-app mutation routes share the same backend
single-writer gate and frontend busy state. A cross-process deployment must not
claim this guarantee without a corresponding shared lock; the demo uses one
backend application process. MCP token-session locking alone is not a task lock.

Read back each submitted operation and verify its requested fields or confirmed
absence. Once all operations are verified, refresh relevant calendar data and
check the final required-pair/scope constraints against the actual result.
Finalize the entry's staged discourse only after this verified completion,
purging facts invalidated by normalized/provider representations. Report confirmed
effects, cost/model qualifications and answers; never substitute an LLM success
message for verification. An accepted entry with no external field differences
needs no provider write but still finalizes its applicable discourse effects
after context validation. Semantic category equality alone is not enough to
drop an explicitly requested color normalization or interval assignment.

### 13.3 Failure, uncertain outcomes and recovery

A provider plan is **not atomic across events**. On the first failed, unverifiable
or uncertain operation, stop submitting later operations. Record each operation
as unsubmitted, submitted/uncertain, verified-success or verified-not-applied.
A timeout does not establish that a submitted write failed. Keep the backend
mutation gate in recovery mode; allow inspection/status and explicit recovery,
not an unrelated task racing with reconciliation.

Refetch affected IDs and compare only the plan-relevant fields with recorded
before/after images. For creates, use the reserved provider ID; for deletes,
verify absence/cancelled status. Classify a submitted operation only when evidence
supports it. Conflicting or unavailable read-back remains unresolved and must
not be disguised as either full success or mathematical infeasibility.

Present verified actual effects, unconfirmed effects and unapplied remainder.
Do not automatically retry an uncertain write, roll back earlier successes,
or submit the remaining plan. After read-only reconciliation, the user may
explicitly authorize completing the verified remaining plan under a fresh
context check, or accept the actual partial result and end the operation. Recovery
retains the accepted constraints and frozen envelopes, not newly broadened inferred
permissions. A necessary change to those constraints requires a fresh reviewed plan. A
compensating/manual correction is a separately reviewed operation; no automatic
compensation promise is made. If Google is unreachable, retain recovery state
across restart and report the blockage rather than clearing the gate blindly.

If no effects were applied, retain pre-entry committed discourse. If the user
accepts a verified partial result, retain pre-entry discourse and purge facts/
references invalidated by actual confirmed state; do not commit the complete
intended task's staged mentions or pretend the conceptual command succeeded.
Preserve newly confirmed identity mappings for later explicit reference. Maintain
an auditable failed/partial entry record and the user-approved disposition.
This policy sacrifices some proposed salience rather than asserting facts about
changes that never happened. A recovered plan completed and verified in full may
finalize its staged discourse after revalidation; stale intermediate answers
remain labeled as statements about their original provisional snapshot.

### 13.4 Cancellation, navigation and Undo

Before application starts, cancel/reject discards the private entry, proposed
prefixes and pending questions; committed events and discourse remain unchanged.
Reserved handles are not reused. An explicit week change performs this same
cancellation before changing context. Ordinary GUI mutation and unrelated chat
entries stay disabled while an entry is paused or being evaluated; the user may
answer, revise, inspect, cancel, or explicitly change context.

Once the first provider write has been submitted, disable cancel, week changes
and unrelated writes until completion or reconciliation. A status request remains
available. Losing a client connection is not cancellation. After a partial result
is reconciled and explicitly accepted or recovered, release the gate. Cancellation
never means that already applied Google effects have been undone.

**No Calendar Undo in v1.** Hide/disable its UI control and reject `Undo.` as an
unsupported operation, not as a successful no-op. Manual corrections remain
available through new reviewed assignments. Chat/discourse history is retained;
there is no discourse-only Undo masquerading as restoration of the calendar.
Objects, Network and Cellular retain their existing Undo semantics unchanged.

### 13.5 Versioning, mappings and compatibility

Every Calendar conversation, executable entry, pending question, review, solver
checkpoint and recovery plan carries `calendar-v1` and `calendar-demo-1`, selected
week and the relevant exact input fingerprint. Import/reload preserves stable
handle mappings. Handle reservations and current pending state are persistent;
provider-ID absence and outside-week scope do not cause handle reassignment.

There is no pre-existing Calendar dialogue state to migrate for initial v1.
Existing GUI events, provider color IDs and other domains' databases/histories
remain valid; do not purge them. A later grammar/grid/rounding/objective change
requires an explicit semantic/policy version and a migration strategy. Do not
reinterpret stored programs or pending answers silently. On mismatch, block
replay/acceptance and explain which proposal must be restarted. An outstanding
recovery journal must first be reconciled using its recorded effect contract;
a version upgrade cannot discard evidence of submitted writes.

### 13.6 Deterministic solver budgets

For `calendar-demo-1`, share the following caps across sentences and resumed
clarifications of one **entry revision**:

| Counter | Cap | Increment rule |
| --- | --- | --- |
| Candidate placements | 200,000 | Each tested generated start/duration candidate, including rejected candidates |
| Constraint checks | 1,000,000 | Each unary candidate-bound test or unordered-pair non-overlap check; normalized and exact checks count separately |
| Search nodes | 100,000 | Each expanded partial-assignment node, including an immediately pruned node |

Use deterministic candidate/variable enumeration for reproducibility, while
keeping semantic schedule choice separate. Feasibility and cost proofs must stay
within these counters. Cache hits may reuse previously validated evidence only
for identical versions, context and constraints; do not count them as new search
or hide invalidated work behind a cache. Clarification, restart and repeated
inspection do not reset counters. Filling a hole/choosing a clarification option
also preserves the budget even if its response advances an internal revision ID.
Only an explicit user-requested requirement revision invalidates
dependent results and starts a new revision budget, while retaining the earlier
revision's work/decision record. No automatic revision loop resets the budget.

An additional ten-second accumulated active-computation watchdog per entry
revision prevents a sluggish UI; it excludes human wait and provider I/O. Across
process restart preserve deterministic counters and previously recorded active
time. The watchdog can make completion hardware-dependent, so its outcome is
always resource-limited, never infeasible. Interrupt only with explicit status;
commit no unfinished task effects and preserve any successful semantic prefix
for its separate review as above.

If a cap interrupts candidate generation, propagation or proof, report which
limit was reached, validated incumbents and sound bounds when available. A partial
variable domain never supports an infeasibility/optimality proof. Feasibility
questions can answer true once a complete witness passes all checks even without
an optimum proof. An optimization question may report best-known cost with its
qualification. Parsing, malformed-data diagnostics and exact snapshot validation
must also fail explicitly on resource exhaustion rather than truncate the event
universe. No event is silently omitted to meet a work limit. Resource checks are
part of the operation contract, not a hidden relaxation of its search domain.

## 14. Review resolution and remaining implementation work

This revision resolves the seven specification findings: distinct date/window
holes; W1/06:00 endpoint rules; guarded operation-specific clash constraints;
exact/no-op checks and positive-cost automatic moves; an explicit limited task
inventory; authoritative clarification ordering; and the execution, recovery,
versioning and budget contracts above.

Version 1 deliberately does **not** support repair of arbitrary event lists,
additional destination-hour constraints on existing events, global week-wide
repair, buffers, alternative objectives, general hypothetical programs, nested
quantifiers, distributed atomicity or Calendar Undo. Do not imply those abilities
in interpretation or silently weaken requests needing them. Date-based repair,
insertion and earliest scheduling keep their specified scopes. New task families
are outside this proposal.

The implementation supplies internal/HTTP response schemas, a Calendar dialogue
SQLite record, reserved provider-ID journaling and regression tests. The
[implementation guide](../calendar-language-v1.md) describes these artifacts and
local operation; they do not expand the resolved task inventory.


### 14.1 Regression obligations for these resolutions

- `within unspecified` has exactly one typed-hole reading;
  `within unspecified date morning` asks only the date. Canonical rendering and replay preserve both.
- A Sunday event ending exactly at W1 parses/resolves; a start at W1, end after
  W1 or repair selector outside the seven dates fails in its proper scope phase.
  Night bounds exactly at 06:00 resolve on the following morning.
- Insertion can leave unrelated original clashes untouched even when an involved
  identity was eligible to move; moving either endpoint activates the guard.
  Day repair applies its target-pair requirement regardless of which member moves.
- Normalized-adjacent 10:00–10:25 and 10:25–11:00 projections of exact
  10:00–10:27 and 10:26–11:00 do not trigger a false no-clash repair result.
- A normalization-only 02:21–02:27 -> 02:20–02:25 candidate is excluded from
  automatic search. No automatic interval change has zero weighted cost. A
  separately reviewed manual normalization remains expressible and cost-free
  only in the sense that scheduling optimization does not apply to that command.
- Explicit unresolved protection/field holes block all terminal result shortcuts;
  omitted or unused movement permission is the sole deliberate lazy exception.
- A failed later sentence offers a labeled prefix without performing writes.
  Cancel before application discards the prefix; accepting it ends the suffix.
- Restart after create submission reuses its reserved Google lookup ID and
  reconciles read-only before any authorized recovery. Never duplicate creation,
  auto-rollback, discard a submitted-write journal or publish full staged salience
  after partial failure. Version mismatch cannot bypass this recovery.
- Resource interruption during domain construction or proof never produces a
  false infeasibility/optimality claim. Resume preserves counters; explicit
  revision records a new budget without losing earlier commitments/history.
