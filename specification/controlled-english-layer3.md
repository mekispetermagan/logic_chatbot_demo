# Controlled English: Layer 3

Layer 3 adds relative movement, attribute copying, spatial questions, counting,
and quantification to the existing core and Layer 2 syntax. Chat uses
`parseSentences` and `evaluateEntry`; the atomic parser remains Layer 1 only.
Input is case-insensitive. Questions require `?`; performatives require a period
except at the end of an entry.

## Subjects and reference resolution

`S` and `S'` are existing-object subjects: `#3`, `A4`, `it`, or a definite
description such as `the large red bloom`. Indefinite descriptions are not
accepted in these new forms. Missing subjects produce diagnostics without
creating objects. Reference resolution, anaphoric salience, and object-choice
clarification follow Layer 2. Both operands resolve against the world before
that utterance changes anything.

## Relative movement

```text
Move #3 up.
Move it down.
Move the bloom left.
Move A4 right.
Move #3 just above #4.
Move #3 under #4.
Move #3 right of #4.
Move #3 left of #4.
Move #3 next to #4.
```

Directions move exactly one square. Up increases the row number; right increases
the column. Relative destinations are immediately adjacent to the reference
object; optional `just` makes no semantic difference. The reference must be
placed. A relative move may place an unplaced source; a directional move requires
its source to be placed.

Out-of-board or occupied destinations leave the world unchanged with concise
feedback (`Outside board` or `A4 occupied`). Movement reuses Layer 1 position
attribution and its collision checks.

`next to` examines the four orthogonal neighbors, excluding diagonals and
out-of-board squares. Only currently empty squares are offered. One free square
is selected automatically; multiple free squares pause evaluation and offer
square buttons; none reports `No free squares`. The source's current square is
occupied and is not a free destination.

## Attribute copying

```text
Make #3 the same color as #4.
Make it the same size as the spark.
Make #3 the same shape as #4.
```

The target supplies its stored value. A present value becomes a Layer 1
attribution; an absent value becomes attribute removal. Copying absence clears
the source attribute. Identity and other attributes remain unchanged. Copying
square, row, or column is not included in this performative.

## Spatial and attribute questions

```text
Is #3 on the board?
Does #3 have a color?
#3 have a size?
Does it have a shape?
#3 have a square?
Is #3 next to #4?
Does #3 have the same color as #4?
#3 same size as #4?
#3 same shape as #4?
Is #3 in the same square as #4?
#3 same row as #4?
#3 same column as #4?
Is #3 at the edge?
Is #3 in a corner?
```

Leading `is` and `does` are optional. `on board` and `on the board` are equivalent.
For equality, `have the` is optional; `in the` is also accepted for square, row,
and column. Equality accepts color, size, shape, square, row, and column.

On-board means a position is present. `have a ...` tests presence of the named
stored attribute. Adjacency requires two placed objects at Manhattan distance
one; unplaced objects are not adjacent. Edges include corners; unplaced objects
are neither at an edge nor in a corner.

Absent values compare equal. When both are absent, feedback explains the answer,
for example `true — both lack color`. Two unplaced objects also have equal
absent square, row, and column values. One absent and one present value compare
unequal. Missing objects still produce diagnostics, rather than null comparisons.

## Counting

```text
How many objects are red bloom?
How many red?
How many objects are next to #3?
How many objects are at the edge?
How many in a corner?
How many squares are empty?
How many free?
How many squares are occupied?
How many taken?
```

`objects` and `are` are optional. Object descriptors are conjunctive and may be
reordered or repeated. Counting objects includes unplaced objects when their
stored properties satisfy the description. With no descriptors, it counts all
objects. Counting neighbors requires a placed reference object. Spatial counts
exclude unplaced objects.

Square counts cover all 64 board squares. `empty/free` and `occupied/taken` are
synonyms; unplaced objects occupy no squares.

## Quantified questions

```text
Is every red object a bloom?
Every red object is large?
Every red is bloom?
Some red objects are large spark?
Some bloom objects green?
```

For `every`, leading `is` is optional. At least one of `object` and `is` must
separate the subject description from its predicate. An optional `a` can precede
the predicate. Both descriptions are nonempty conjunctions of color, size, and
shape values; order and repetition are allowed. `every red bloom?` is rejected
because it has no boundary. The former `all` syntax is no longer accepted.

For `some`, leading `are` remains optional, and at least one of `objects` and
`are` separates the descriptions. Its syntax and evaluation are unchanged.

`every` checks every matching object; `some` checks whether at least one matching
object satisfies the predicate. `every` carries no existential commitment. An
empty subject class returns `true — no matching objects` for `every` and
`false — no matching objects` for `some`.

## Clarification, salience, and undo

Evaluation pauses at the exact utterance needing a choice. Earlier utterances
in the same entry remain applied; later utterances wait. A square choice retains
the already resolved object operands, so their references are not resolved again.
Object ambiguity can be followed by square ambiguity in the same utterance.

Pending state, offered squares, and resolved operands persist with the world
and salience snapshot. Invalid choices leave that state unchanged. A valid
choice completes the paused move and evaluates the remainder. Continuations
replace the same entry snapshot: one Undo restores the entire pre-entry world
and salience, including when clarification is still pending.

Resolved subjects receive mentions; copying and movement associate their actual
resulting attributes. False or cleared properties are purged. Aggregate counts
and quantified questions do not introduce individual-object antecedents.
