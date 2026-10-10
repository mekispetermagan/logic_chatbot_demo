# Controlled English: Core Language Reference

This document describes the **implemented atomic core**. Layer 2 syntax and
reference-resolution semantics are described in [Layer 2](controlled-english-layer2.md).
It is a reference for writing demo chat entries and understanding their evaluation.

[Controlled English Fragment for the Logic Demo](controlled-english-fragment.md)
describes the broader three-layer design. Its `o12` notation and descriptions of
unknown attributes predate the current implementation. For the implemented core,
use the syntax and semantics below: identifiers use `#`, and absent attributes
are part of a fully known, partially specified world.

## 1. World and base vocabulary

The world contains objects with persistent identifiers and four optional
attributes. Each attribute has at most one value.

| Attribute | Allowed values |
| --- | --- |
| Color | `red`, `blue`, `green`, `yellow` |
| Size | `small`, `medium`, `large` |
| Shape | `cube`, `sphere`, `pyramid` |
| Position | A square from `A1` to `H8` |

The board is currently fixed at 8×8. A1 is the bottom-left square, H8 the
top-right. Internally, coordinates are zero-based: A1 is `(0,0)`, A4 is `(0,3)`,
and H8 is `(7,7)`. The user-facing syntax and answers use chessboard coordinates.

An object can lack any attribute, including position. Such an object exists but
may be colorless, sizeless, shapeless, or unplaced. Absence is not an additional
enum value and is not uncertainty about an existing value. Two positioned
objects cannot occupy the same square.

## 2. Object references

Every atomic sentence has a subject, expressed in either of two ways:

| Reference | Example | Meaning |
| --- | --- | --- |
| Identifier | `#3` | The object whose identifier is 3 |
| Square | `A4` | The object currently occupying A4 |

Identifiers are nonnegative decimal integers within the engine's supported
integer range. `#0` is valid; `o3` and negative identifiers are not. A square
reference changes its referent when objects move. An identifier continues to
refer to the same object when its attributes or position change.

Questions resolve references without creating objects. Performatives can create
an object when resolving a reference that currently has no referent; see Section 6.

## 3. Sentence categories and punctuation

There are three distinct atomic sentence categories:

| Category | Example | Effect |
| --- | --- | --- |
| Performative | `#3 red.`, `remove #3.`, `swap #3 #4.`, `delete #3.` | Attribute an object, unplace it, exchange positions, or delete it |
| Property check | `#3 red?` | Return whether the object has that property |
| Attribute-value question | `color of #3?` | Return the value of an attribute |

**Every question requires `?`. Performatives have no question mark.** A
performative's period is optional only at the end of the user entry. Thus `#3 red` updates the world;
`#3 red?` asks a question. A trailing `?` selects a question category rather
than acting as optional decoration on an update.

Words and square references are case-insensitive. `#3 IS RED?` and `#3 is red?`
mean the same thing. Whitespace, including line breaks, is allowed between
sentences. A subject and its following words require whitespace: `#3red` fails.

### Performatives

An attribution performative sets exactly one color, size, shape, or position. `is` is
optional. Before a position, `on` is optional; `to` is another movement spelling.

```text
#3 red.
#3 is red
#3 medium.
#3 cube.
#3 A4.
#3 on A4
#3 is on A4.
#3 to A4.
A4 green.
A4 is large.
A4 to B3.
```

`to` is performative-only: `#3 to A4?` is rejected. To ask about a position,
use `#3 on A4?` or `#3 A4?`.

### Removal, swapping, and deletion

These are additional primitive performatives. Every operand must resolve
to an existing object; a missing identifier or empty square produces a diagnostic
without creating anything or changing the world.

```text
remove #3.
remove A4 from board.
swap #3 and #4.
swap A4 B3.
erase #3.
delete A4.
```

`remove subject [from board]` clears only the object's position. Identity and
all other attributes remain intact. Removing an unplaced object reports `No change`.

`subject remove color/size/shape/square` clears the named attribute, preserving
identity and every other attribute. For example, `#3 remove color.` clears its
color and `A4 remove shape.` clears the shape of the object on A4.
`square` clears position and is equivalent to `remove subject`.
An already absent attribute reports `No change`; a missing subject produces a
diagnostic without creating an object. A period is required except at the end
of an entry, and `?` is rejected. Layer 2 also supports pronouns and definite descriptions as subjects.

`swap subject [and] subject` exchanges the two nullable positions atomically.
Two placed objects exchange squares, with no free temporary square required.
A placed and unplaced object exchange the square and absence of position.
Two unplaced objects, or an object swapped with itself, report `No change`.
Other attributes and identities remain intact. Both operands resolve against
the pre-swap world, including when both are square references.

`erase subject` and `delete subject` are synonyms that delete the entire object,
including unplaced objects. Prettyprinting uses `delete`, omits `from board`,
and inserts `and` in swaps. These operations follow the usual period rule and
never accept `?`; they introduce no new question forms.

### Property checks

A check supplies a particular property value and ends in `?`. Optional `is`
and position-specific `on` work as in performatives.

```text
#3 red?
#3 is medium?
#3 sphere?
#3 on A4?
#3 is A4?
A4 green?
A4 on B3?
```

The last example asks whether the object occupying A4 is on B3. In a valid world
it is false when A4 is occupied, and reports a missing referent when A4 is empty.

### Attribute-value questions

Supported attributes are `color`, `size`, `shape`, `position`, `row`, and `column`.
Both full and subject-first shorthand forms are accepted:

```text
color of #3?
size of A4?
shape of #3?
position of A4?
row of #3?
column of A4?
#3 color?
A4 position?
B3 column?
#3 is size?
```

`of` is required in the attribute-first form. Shorthand can include `is`.
Neither form can omit `?`: `color of #3` and `B3 column` are invalid.

### Compact syntax summary

In this summary, square brackets indicate optional words or punctuation, not
literal input. Required spacing is omitted for readability.

```text
subject      = identifier | square
base-value   = color | size | shape
attribute    = color | size | shape | position | row | column

performative = subject [is] base-value [ . ]
             | subject [is] [on] square [ . ]
             | subject [is] to square [ . ]
             | remove subject [from board] [ . ]
             | swap subject [and] subject [ . ]
             | (erase | delete) subject [ . ]

check        = subject [is] base-value ?
             | subject [is] [on] square ?

value-query  = attribute of subject ?
             | subject [is] attribute ?
```

## 4. Multiple sentences in one entry

One chat entry can contain an ordered sequence of any of these categories:

```text
#3 on B3. #3 red. #3 medium. #3 is cube. #3 red? color of #3?
```

Every non-final performative requires a period. Whitespace alone does not
separate sentences. A period or question mark separates sentences even without
following whitespace:

```text
#3 red.#3 cube.#3 red?shape of #3?
```

The parser consumes the **entire entry before evaluation begins**. Empty input,
unsupported words, malformed coordinates, and any unparsed suffix reject the
whole entry. For example, `#3 red. nonsense` makes no update, even though its
first sentence would be valid alone.

Examples of rejected input:

| Input | Reason |
| --- | --- |
| `o3 red.` | Old identifier spelling |
| `#3 purple.` | Unsupported color |
| `#3 on I1.` | Column outside A–H |
| `#3 on A9.` | Row outside 1–8 |
| `color #3?` | Missing `of` |
| `#3 to A4?` | `to` cannot introduce a question |
| `#3 red?.` | Extra punctuation after a question |
| `#3 red and small.` | Conjunction is not part of the atomic grammar |

## 5. Checks and attribute answers

For an existing object, a property check returns `true` exactly when its stored
attribute equals the requested value. A different value or an absent attribute
returns `false`. There is no third Boolean value for an absent attribute.

If an object has only a red color:

| Question | Answer |
| --- | --- |
| `#3 red?` | `true` |
| `#3 blue?` | `false` |
| `#3 cube?` | `false` |
| `color of #3?` | `red` |
| `shape of #3?` | `none` |
| `position of #3?` | `none` |

`none` means that the queried attribute is absent. For an unplaced object,
position, row, and column queries all return `none`. For an object on B3,
position returns `B3`, row returns `3`, and column returns `B`.

A missing subject is different from an existing object with an absent attribute.
For example, if #99 does not exist, `#99 red?` reports `No object at #99`, rather
than `false`. An empty-square query similarly reports `No object at A4`.

Reference resolution also detects ambiguity: more than one matching object
produces `Ambiguous #3` or `Ambiguous A4`. Normal demo worlds prevent duplicate
identifiers and square occupancy; the evaluator does not silently choose a match.

## 6. Updates and creation during reference resolution

Property attribution first resolves the subject, then applies the requested property:

1. An existing subject is selected without changing its identity.
2. A missing identifier creates an object with that exact identifier and no attributes.
3. An empty-square subject creates an object on that square with a fresh identifier.
4. The requested attribute is set; other attributes are preserved.

For square-based creation, the next identifier is one greater than the largest
identifier **currently present**, or 0 in an empty world. This is not a globally
monotonic allocation counter; removing the highest identifier can allow reuse.

Repeated properties report `No change`. New values revise single-valued
attributes: `#3 red. #3 blue.` leaves #3 blue, not both red and blue.
Updates have no automatic defaults for unspecified attributes.

### Positions, collisions, and blocked moves

A movement preserves the subject's identity and other attributes. Its destination
must be inside the board and unoccupied by another object. Staying on the same
square is allowed and reports no change.

Creation belongs to reference resolution and happens **before** destination
validation. A failed move can therefore leave a newly created subject behind:

| Starting state for `A4 to A5.` | Result |
| --- | --- |
| A4 occupied; A5 empty | Move the A4 object to A5 |
| A4 occupied; A5 occupied | Leave the world unchanged |
| A4 empty; A5 empty | Create at A4, then move the new object to A5 |
| A4 empty; A5 occupied | Create at A4, but leave the new object there |

Similarly, `#99 on A5.` creates an unplaced #99 when that identifier is missing
and A5 is occupied. Feedback notes both creation and the blocked destination.
Moving an already existing object to an occupied destination does not create
anything or remove either occupant.

The parser cannot express an out-of-board square. Programmatically constructed
performatives are additionally checked by the evaluator, which reports
`Outside board`; any subject created during resolution is retained.

## 7. Sequential evaluation and feedback

After successful parsing, sentences are evaluated from left to right. Each
sentence sees the world resulting from every preceding sentence. Questions leave
that world unchanged. A missing referent or blocked operation produces feedback
and does not stop later sentences. Evaluation is not an all-or-nothing rollback
of individually unsuccessful operations.

For example, starting with an empty world:

```text
#3 red. #3 small. #3 cube. #3 on A4. #3 red? color of #3? row of #3? column of #3?
```

The reply is:

```text
#3 red.
  Created #3: red
#3 small.
  #3: none -> small
#3 cube.
  #3: none -> cube
#3 on A4.
  #3: none -> on A4
#3 red?
  true
color of #3?
  red
row of #3?
  4
column of #3?
  A
```

Feedback includes the parsed sentence in its canonical prettyprinted form,
followed by its answer or change. Optional `is` is removed, positions use `on`,
`to` becomes `on`, shorthand queries become `attribute of subject?`, property
words are lowercase, and square columns are uppercase. Performatives print a
period; questions print a question mark.

## 8. Chat persistence and Undo

Flutter submits one entry to FastAPI. Haskell returns the final world, discourse
state, and ordered feedback. FastAPI saves the user entry and machine reply with
**at most one** new paired world/salience snapshot, atomically. Individual
sentences are not separately undoable.

Undo restores the previous world and salience and retains chat messages.
Questions and revisions that return to the original world may still create a
snapshot through salience changes. Parse errors preserve both states. Layer 2
clarification pauses can expose partial progress, but one Undo still reverses
the whole entry. See [Layer 2](controlled-english-layer2.md) for those rules.

Visual edits and chat share the same stored world and history. Clear remains
an interface/API operation; object deletion is also available as `erase`/`delete`. An entry starting with `undo` after optional
leading whitespace requests Undo, case-insensitively; all remaining text is
ignored. For example, `  UnDo #3 red.` undoes once without applying `#3 red.`.
Haskell recognizes the request before sentence parsing and returns it to FastAPI,
which restores the previous world/salience snapshot. The input and `Undone`
(or `No change` at the initial snapshot) are saved as chat messages. Undo is an
entry-level command, not a core sentence; `#3 red. undo` is not accepted.
An engine or connection failure is distinct from a parse error: it does not persist a new chat pair. After a lost response, refresh
to retrieve committed state rather than automatically repeating the submission.

## 9. Implementation map and current limits

| Module | Responsibility |
| --- | --- |
| [Ontology.hs](../backend/logic_engine/Ontology.hs) | Objects, references, properties, world |
| [AtomicParser.hs](../backend/logic_engine/AtomicParser.hs) | Parse one sentence or a complete sequence |
| [ReferenceResolution.hs](../backend/logic_engine/ReferenceResolution.hs) | Resolve references; create performative subjects |
| [AtomicPerformative.hs](../backend/logic_engine/AtomicPerformative.hs) | Attribute, unplace, swap, or delete objects and report changes |
| [AtomicPropertyCheck.hs](../backend/logic_engine/AtomicPropertyCheck.hs) | Evaluate Boolean checks |
| [AtomicPropertyQuery.hs](../backend/logic_engine/AtomicPropertyQuery.hs) | Evaluate attribute-value questions |
| [AtomicEvaluation.hs](../backend/logic_engine/AtomicEvaluation.hs) | Evaluate sequences and format feedback |

Parsing returns `Either String ...`: a parse error or parsed syntax. Check and
query evaluation return the engine's `Result` type: an answer or a diagnostic
`Message`. Sequence evaluation returns a world and ordered feedback; HTTP and
SQLite handling remain outside Haskell.

The atomic evaluator currently has no negation, conjunction, disjunction,
quantifiers, description/pronoun resolution, or spatial relations such as `near`.
Layer 2 evaluates descriptions and pronouns. Position absence can be assigned
with `remove`; other attribute absences cannot be assigned. See the Layer 2
reference for additional accepted syntax and the boundary
between parsing and evaluation. Derived terms belong to Layer 3 and remain future work.
