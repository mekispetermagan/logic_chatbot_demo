# Calendar v1 controlled syntax reference

Keywords ignore case, strings preserve case and use JSON quoting. Commands end
with a period, questions with ?. Whole entries may contain several sentences.
Use exact canonical vocabulary, no natural-English fragments inside translations.
No Undo or Atomically construct exists in this domain.

## Values and references

- importance: normal | important | critical
- threshold: none | normal | important | critical
- date: monday | tuesday | wednesday | thursday | friday | saturday | sunday |
  today | tomorrow | YYYY-MM-DD (a real date inside the selected week)
- date slot: date | unspecified date
- clock: HH:MM (00:00–23:59) | one of [05:00, 17:00]
- moment: date-slot at clock-slot [offset +01:00]
- clock slot and whole moment slot may be unspecified.
- Closing endpoint may be the next Monday 00:00, expressed with its literal date.
- Window: selected week | date-slot [night|dawn|morning|lunchtime|afternoon|evening]
  [after clock-slot | at or after clock-slot] [before clock-slot | by clock-slot]
  | interval from moment-slot to moment-slot | starting at moment-slot
- Whole window hole: unspecified. `starting at` is only for placement, not counts.
- Night is 22:00–06:00 on the following date; dawn 06–09, morning 09–12,
  lunchtime 12–13, afternoon 13–18, evening 18–22.
- Event reference: #3 | it | the event with descriptors |
  the unique event with descriptors. A missing reference is unspecified.
- Descriptors: title "Meeting" and location "Office" and description "Review"
  and importance important and start date thursday. Any nonempty subset is
  allowed, once each, in that fixed field order. No adjective shorthand.
- Lists of event references: [#3, it, the event with title "Meeting"].
- Durations: 1 minute | N minutes. Scheduling requires positive multiples of 5;
  unsupported explicit precision is not permission for you to round it silently.

## Primitive commands

Create event from thursday at 09:00 to thursday at 10:00 [with fields].
Set title of #3 to "Meeting".
Set location of it to "Office".
Set description of #3 to "Review".
Set location of #3 to "".
Set importance of #3 to critical.
Set interval of #3 from thursday at 10:00 to thursday at 11:00.
Delete #3.

Creation accepts the same optional `with fields` clause defined below for conceptual
commands, with the same order and typed holes. It fixes the interval and permits
overlaps; it does not search for a free slot.

Each reference/value/moment slot can be unspecified. Fields are total strings;
there is no separate clear command, optional/maybe value or color command.

## Conceptual commands

Schedule event [lasting duration-slot] [within window-slot] [with fields].
Make room for event [lasting duration-slot] [within window-slot] [with fields]
  [, moving up to threshold-slot] [, protecting list-slot]
  [, choosing ask | choosing preserve original order].
Remove clashes [on date-slot] [, moving up to threshold-slot]
  [, protecting list-slot] [, choosing ask | choosing preserve original order].

`with fields` is a nonempty subset in title/location/description/importance order:
with title "Meeting" and location "Office" and description "Review" and importance important
Each value may be unspecified. Omitted fields default to ""/normal; other omitted
placement parameters remain holes. Omitted protecting means []; explicitly
unknown protection is `protecting unspecified`. Only movement permission is
asked lazily when an engine no-movement baseline proves insufficient.

## Conditions

true | unspecified | title is string-slot | location is string-slot |
description is string-slot | importance is importance-slot |
importance is at least importance-slot | importance is at most importance-slot |
starts on date-slot | within window-slot | overlaps window-slot |
overlaps event event-slot | before event event-slot | after event event-slot |
duration is duration-slot | duration is at least duration-slot |
duration is at most duration-slot | has a clash [within window-slot]

Conditions combine with not/and/or/parentheses. Preserve consequential Boolean
scope rather than silently imposing precedence. In particular an event relation
requires the word `event`: overlaps event the event with importance critical.
Descriptions use field/value pairs, e.g. the event with importance important.

## Questions

Does #3 exist?
What is the title of #3?
What is the location of it?
What is the description of #3?
What is the importance of #3?
What is the start of #3?
What is the end of #3?
What is the interval of #3?
Does #3 satisfy condition?
What is the duration of #3?
What is the gap between #3 and #5?
Which events match condition?
How many events match condition?
Does every event matching condition satisfy condition?
Does some event matching condition satisfy condition?
Which intervals are free [within window-slot]?
What is the earliest available interval [lasting duration-slot] [within window-slot]?
Which event pairs clash [within window-slot]?
How many overlaps occur [within window-slot] [, counting pairs | counting events]?
Can an event [lasting duration-slot] [within window-slot] fit movement-options?
What is the minimum movement cost to fit an event [lasting duration-slot]
  [within window-slot] movement-options?
Can clashes [on date-slot] be removed movement-options?

Here movement-options means the optional comma clauses of Make room for event.
Omitted counting unit and scope remain holes, not a guessed pair/day/week count.
Question field/subject/condition/date/window/duration slots may be unspecified.
The existence question takes #identifier or unspecified, not a description.

For a scheduling need, use a task primitive rather than computing free slots or
atomic rearrangements yourself. For an engineAnswer-mode translation return only
one JSON value in candidate.translation, with no period/question punctuation
outside that JSON value. This exception never authorizes a new controlled entry.

## Joint scheduling and freeing a window

Schedule events jointly [event lasting 90 minutes within any of [monday morning; tuesday morning] with title "Workshop"; event lasting 120 minutes within monday morning with title "Review"], on different dates, choosing earliest in listed order.
Schedule events jointly unspecified.
Schedule events jointly [event; event], on different dates.
Free window interval from thursday at 10:00 to thursday at 11:00, moving up to normal.
Free window thursday morning, moving up to important, protecting [#4], choosing ask.
Free window unspecified.
Can events [event lasting 60 minutes within monday morning; event lasting 60 minutes within tuesday morning] be scheduled jointly, on different dates?
Can window thursday morning be freed, moving up to normal?
What is the minimum movement cost to free window interval from thursday at 10:00 to thursday at 11:00, moving up to important?

Joint lists contain 2–16 `event` items separated by semicolons. Each item uses
optional lasting, within and with-fields clauses in that order, with the same
field order/defaults/holes as single scheduling. A missing whole list is unspecified.
A joint window is one ordinary window, unspecified, or any of [window; window].
`any of` explicitly permits choosing among windows; do not replace ambiguous clock
`one of` with it. Joint options, in fixed order, are optional `, on different dates`
and optional `, choosing ask` or `, choosing earliest in listed order`.
The latter is a user-delegated priority, never a translator default. Joint scheduling
keeps existing events fixed; do not split a joint request into sequential Schedule commands.
Free window uses ordinary bounded windows, excluding starting at, followed by the
same ordered movement options as Make room. It means rearrange now, not reserve time
against future commands. Missing movement permission remains unresolved.
Do not translate scheduling, freeing or feasibility into precomputed assignments.
