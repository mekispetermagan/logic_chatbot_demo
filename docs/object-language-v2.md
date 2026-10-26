# Object Domain Controlled Language — Version 2

## 1. Status and purpose

**Runtime semantic version: `objects-v2`.**

This is a standalone specification of the object domain's vocabulary, grammar
and evaluation semantics. It defines three compositional layers:

1. **Atomic operations, predicates and queries.**
2. **Referential macros resolved by the logic engine.**
3. **Conceptual macros, derived predicates and aggregate questions.**

The language is designed for precise execution and human inspection. Humans may
request tasks in ordinary language; an LLM proposes expressions in this language.
The proposal must expose consequential distinctions, including distinctions that
cannot be seen in a graphical preview. Haskell resolves references and evaluates
the established meaning. The complete contract is versioned as one document.

### 1.1 Design commitments and policy choices

The design commitments are explicit imperative actions, canonical vocabulary,
separate square and object terms, explicit creation, identity preservation,
symbolic reference resolution, and the three layers above.

The approved v2 policy choices are:

- The exact sentence forms and punctuation below.
- Stop-on-failure sequences and separate atomic batches.
- Conversation-wide identifier freshness, including across Undo.
- The macro inventory, Boolean predicate grammar and collection syntax.
- Rotation/reflection parameters and explicit appearance-bundle operations.
- The detailed salience policy for newly introduced compound operations.

Every rule below describes the v2 language, including these choices.
There are no implicit aliases or additional accepted forms.

## 2. World, types and vocabulary

The world contains objects with immutable identifiers and optional color, size,
shape and position attributes. There is full information about this partial
world: a missing attribute is known to be absent, not an unknown value.

| Type or term | Vocabulary | Meaning |
| --- | --- | --- |
| Color | `red`, `blue`, `green`, `yellow` | One optional object attribute |
| Size | `small`, `medium`, `large` | A categorical attribute; no physical collision radius |
| Shape | `bloom`, `spark`, `drop`, `loop` | One optional object attribute |
| Square | `A1` through `H8` | One of 64 fixed locations |
| Identifier | `#0`, `#1`, … | An immutable object identity within this conversation |
| Absence result/literal | `none` | No value; allowed only in designated answer and bundle positions |
| Appearance | Color, size and shape together | Excludes identifier and position |
| Stored attribute | `color`, `size`, `shape`, `position` | Nullable object state |
| Derived coordinate | `row`, `column` | Obtained from position; absent when unplaced |
| Direction | `north`, `east`, `south`, `west` | Increasing row, increasing column, decreasing row, decreasing column |
| Square shading | `light`, `dark` | A fixed board property, independent of objects |

Shape names have no parser aliases. The interpretation layer may understand
natural synonyms and translate them to the canonical names.

A1 is bottom-left; H8 is top-right. For geometric definitions, columns A–H have
indices 1–8, and rows have indices 1–8. A square is light when its column index
plus row is odd, and dark when that sum is even. Thus A8 is light and A1 is dark.
These are semantic shading classes; changing display shades does not change them.

An object may be unplaced and may lack any appearance attribute. At most one
object occupies each square. Unplaced objects occupy no square. There is no
orientation attribute, numerical size, continuous movement or path traversal.

**A square term never implicitly denotes an object.** `A4` is a location.
`the object at A4` refers to its occupant. A missing occupant is a failed object
reference, not an instruction to create one.

### 2.1 Identity and allocation

Only explicit creation and cloning allocate identifiers. A new identifier must
never have identified a different object in this conversation, including objects
deleted or removed by Undo. References cannot allocate or resurrect objects.
An identifier supplied in a sentence always denotes an existing or missing
identity, never a requested allocation number.

The engine receives allocation state as input and returns its updated value;
persistence does not make semantic allocation decisions. The allocation record
is not rolled back by Undo. Aborted staged work may leave gaps in identifiers;
gaps do not denote objects. Failed creation never leaves an object behind.

## 3. Notation and lexical rules

Grammar blocks use EBNF. Quoted text is literal, `|` separates alternatives,
`[ ... ]` means optional, `{ ... }` means zero or more repetitions, and
parentheses outside quotes group grammar expressions. Semicolons end rules.
Metavariable names are not literal input.

Words are case-insensitive; canonical output uses lowercase words, uppercase
columns and decimal identifiers without leading zeroes. Whitespace separates
words. Line breaks are whitespace. Integer literals have no leading zeroes;
signed integers use a minus sign only for negative values, and never `-0`.
Implementations must report numeric range limits without wrapping numbers.

Every command ends with `.`, including the final command. Every question ends
with `?`. There are no bare declarative update sentences. The parser consumes
the complete entry before evaluation; a lexical, syntactic or static type error
rejects the entire entry without changing domain or discourse state.

```ebnf
color = "red" | "blue" | "green" | "yellow" ;
size = "small" | "medium" | "large" ;
shape = "bloom" | "spark" | "drop" | "loop" ;
appearance-attribute = "color" | "size" | "shape" ;
stored-attribute = appearance-attribute | "position" ;
comparison-attribute = stored-attribute | "row" | "column" ;
component = appearance-attribute | "appearance" ;
direction = "north" | "east" | "south" | "west" ;
shading = "light" | "dark" ;
row = "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" ;
column = "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" ;
square = column, row ;
identifier = "#", nonnegative-integer ;
initial-field = "color", color | "size", size | "shape", shape ;
description = description-fields | "(", description-fields, ")" ;
description-fields = initial-field, { "and", initial-field } ;
appearance-literal = appearance-fields | "(", appearance-fields, ")" ;
appearance-fields = "color", (color | "none"), ",",
                    "size", (size | "none"), ",",
                    "shape", (shape | "none") ;
creation-site = "on", square-expr | "off the board" ;
```

`nonnegative-integer` and `signed-integer` are lexical integer classes defined
above. In `square` and `identifier`, comma denotes adjacent lexical concatenation,
not input whitespace. Elsewhere grammar items are token-separated except for
literal punctuation.

A description contains each named attribute at most once, in color–size–shape
order with omissions allowed. It contains no absence literals. For example,
`color red and shape bloom` is valid; repeated, conflicting or reordered fields
are rejected. An appearance literal always lists all three fields in the shown
order. Its `none` entries explicitly clear or represent absent attributes.

### 3.1 Surface syntax normalization

Parentheses are scope markers, not compulsory wrappers. Descriptions, complete
appearance values, movement offsets and simple conditions can be written without
them. Existing parenthesized forms remain accepted. The word `and` between
initial description fields lists attributes; it is not a Boolean operator.

Before execution, a grammar-driven surface pass reconstructs omitted delimiters
and validates each complete reading with the strict internal parser. It never
uses an LLM and never chooses a meaning using Boolean precedence or the current
world's truth values. Malformed syntax, invalid field values and static type
errors still reject the entire entry.

Explicit grouping is needed to settle genuinely different scopes when there
are multiple Boolean operators, or when a nested condition has an ambiguous
boundary even with only one operator. For example, the engine asks whether
`color is red or size is large and shape is bloom` means:

1. `color is red or (size is large and shape is bloom)`
2. `(color is red or size is large) and shape is bloom`

The same applies to negation scope. An ungrouped nested square test such as
`on a square matching shading is light or true` also has two scopes: the `or`
may belong to the square condition or to the surrounding object condition.
A simple test such as `on a square matching shading is light` needs no grouping.

A grouping clarification pauses **before any sentence in that entry executes**,
consistent with complete-entry parsing. All alternatives are displayed with
sufficient parentheses to distinguish their meanings. After a choice, the
selected reading proceeds through ordinary reference resolution and evaluation;
further reference clarification may still be needed. The pending choice survives
reloads and restarts. Undo cancels a pending entry or reverses the whole resolved
entry, preserving the usual world and salience history semantics.

The internal canonical representation retains explicit delimiters for validation
and replay. User-facing feedback removes redundant parentheses and preserves
those needed to state scope. Square brackets for explicit lists and braces for
atomic batches remain required.

## 4. Entry and execution grammar

```ebnf
entry = "undo", "."
      | sentence, { sentence }
      | "atomically", "{", command, { command }, "}", "." ;
sentence = command | question ;
command = (atomic-command | conceptual-command), "." ;
question = (atomic-question | conceptual-question), "?" ;
```

`undo.` is an entire entry. It has no ignored suffix and cannot be embedded in a
sequence or atomic batch. Atomic batches contain commands only and cannot nest.

### 4.1 Ordinary sequences

Sentences execute left to right. Each sees the state resulting from preceding
completed sentences. Each command, including a conceptual macro, is atomic.
A blocked command or unresolved reference stops the sequence; completed
sentences remain effective, and later sentences are reported as not executed.
A successful no-change result does not stop the sequence.

Ambiguity pauses before the affected command or question. Its unresolved work
has no domain effect. Earlier completed sentences remain visible. Clarification
retains already resolved operands and resumes that same entry, not a new one.

### 4.2 Atomic batches

Commands execute sequentially against a private staged world and salience state.
Each command can refer to results of earlier staged commands. Success commits
the entire staged result once. Failure discards all staged domain and salience
changes and reports that nothing in the batch was applied.

Clarification may pause a batch, preserving its private staged continuation.
Staged effects must be labeled as provisional and remain distinct from the
committed world. A rejected or cancelled batch discards them. Reserved identifier
numbers may remain consumed, as specified in Section 2.1.

### 4.3 History and review

One user entry is one Undo unit across all its clarification rounds. Persist
history of world **and salience**, including pending continuations. Undo restores
the complete pre-entry world and discourse state and cancels its continuation;
chat messages and identifier allocation history remain. Questions may be
undoable because they affect discourse even when domain facts do not change.

LLM interpretations are proposals until explicitly accepted. Preview uses the
same semantics without committing domain or salience changes. Review must show
resolved identities when available, selections, existence changes, movement and
appearance changes. Changes to relevant world, discourse or semantic version
invalidate a stale review. Social replies never enter this executable grammar.

## 5. Layer 1 — Atomic operations and queries

For Layer 1 alone, `object-ref` means an identifier and `square-expr` means a
square literal. Higher layers extend those operand categories without altering
the atomic operations' contracts.

### 5.1 Commands

```ebnf
atomic-command = "create object", [ "with", description ], creation-site
               | "delete", object-ref
               | "delete every object"
               | "set color of", object-ref, "to", color
               | "set size of", object-ref, "to", size
               | "set shape of", object-ref, "to", shape
               | "clear", appearance-attribute, "of", object-ref
               | "move", object-ref, "to", square-expr
               | "unplace", object-ref
               | "exchange positions of", object-ref, "and", object-ref ;
```

| Operation | Contract |
| --- | --- |
| Create | Allocate one fresh identity; initialize named appearance fields; omitted fields are absent; create at the explicit site |
| Delete one | Remove that existing object, including any position and salience mentions |
| Delete every object | Delete all placed and unplaced objects; clear their salience mentions |
| Set | Set the named attribute on an existing object; preserve all other state |
| Clear | Make the named appearance attribute absent; preserve everything else |
| Move | Set an existing object's position; preserve its identity and appearance |
| Unplace | Clear position; preserve the object and its appearance |
| Exchange positions | Atomically exchange two nullable positions; preserve both identities and appearances |

Creation on an occupied square fails without creating an unplaced fallback.
A move to a square occupied by another object fails without displacing it.
Moving to one's own square succeeds with no change. Clearing an absent attribute,
unplacing an unplaced object, and deleting all objects from an empty world also
succeed with no change. Deleting a missing object is a reference failure.

Exchanging positions works on a full board without a spare square. Placed and
unplaced objects exchange placement; two unplaced objects or an object exchanged
with itself produce no change. Neither operand is resolved after moving the other.

Position cannot be set or cleared through appearance operations. It has the
explicit `move`, `unplace` and `exchange positions` tools. No command implicitly
creates its referenced subject.

```text
create object with color red and shape bloom on A4. create object off the board. set color of #3 to blue. clear size of #3. move #3 to B3. unplace #3. exchange positions of #3 and #4. delete #3. delete every object.
```

### 5.2 Predicates and questions

```ebnf
atomic-question = "does", identifier, "exist"
                | "does", object-ref, "satisfy", object-condition
                | "does", square-expr, "satisfy", square-condition
                | "what is the", query-attribute, "of", object-ref
                | "which object occupies", square-expr ;
query-attribute = stored-attribute | "identifier" | "row" | "column"
                | "appearance" ;
object-condition = object-primary
                 | "not", object-condition
                 | object-condition, "and", object-condition
                 | object-condition, "or", object-condition ;
object-primary = object-atom | "(", object-condition, ")" ;
object-atom = "true"
            | "color is", color
            | "size is", size
            | "shape is", shape
            | "position is", square
            | stored-attribute, "is present"
            | stored-attribute, "is absent"
            | "identifier is", identifier
            | derived-object-atom ;
square-condition = square-primary
                 | "not", square-condition
                 | square-condition, "and", square-condition
                 | square-condition, "or", square-condition ;
square-primary = square-atom | "(", square-condition, ")" ;
square-atom = "true" | "occupied" | derived-square-atom ;
```

Layer 1 includes the stored-attribute and identifier queries, basic object atoms,
and `occupied`. Row, column and appearance queries, and the `derived-...` atoms,
belong to Layer 3. Boolean composition is shared grammar available in every layer.
There is no implicit Boolean precedence in surface input. Parentheses settle
scope explicitly. Multiple Boolean operators (`not`, `and`, `or`) require
explicit grouping when different groupings have different logical meanings.
Omitting such grouping is an ambiguity, not a syntax error: the engine offers
fully specified readings and asks which one was intended. Pure chains of `and`
or pure chains of `or` normalize without a question because association does
not change their meaning. This equivalence rule does not depend on the current
world or on coincidentally equal answers.

`does #99 exist?` tests identity membership without first requiring its existence.
It returns false for a missing identifier. An identifier used as a predicate
value, such as `identifier is #99`, is also a literal, not a reference to resolve.
Every other object query requires a resolved subject; failure is a diagnostic,
never false or `none`. A value query on an existing object's absent attribute
returns `none`. Its identifier query returns its identity.

An absent attribute fails a positive value test. Its `is absent` test succeeds.
Negation is classical over known facts: a colorless object satisfies `not color
is red`, but that alone does not establish a different present color. Missing
references are errors even under negation or a logically short-circuited branch.

Square occupancy returns true or false without selecting an object or creating
one. `which object occupies ...?` returns its identifier, or `none` if unoccupied.
There are no `empty`, `free` or `taken` aliases; vacancy is `not occupied`.

```text
does #99 exist? does #3 satisfy color is red and shape is bloom? does #3 satisfy color is absent or (not size is large)? does A4 satisfy occupied? does A4 satisfy not occupied? what is the color of #3? which object occupies A4?
```

## 6. Layer 2 — Referential macros

Layer 2 extends object operands, not the action vocabulary. Its machinery is
domain-independent; the appearance descriptors supplied here are domain data.

```ebnf
base-object-ref = identifier
                | "it"
                | "the object at", (square | "it")
                | "the object with", description ;
object-ref = base-object-ref
           | "the object at", relative-square
           | "the unique object matching", object-condition ;
square-expr = square | "it" | relative-square ;
```

Only `base-object-ref` belongs to Layer 2. Relative squares and unique computed
descriptions are Layer 3 extensions defined below. There is no indefinite
reference operand. Indefinite introductions are expressed by explicit creation.

| Reference | Resolution |
| --- | --- |
| Identifier | That identity, or a missing-reference diagnostic |
| `it` | Most recent eligible mention of the required kind; ties require clarification |
| `the object at A4` | The existing occupant of A4, irrespective of salience |
| `the object with color red` | Compatible salient antecedent; world-description fallback if none qualifies |

No resolution path creates an entity. Anaphoric descriptions must currently be
true of their resolved object. If an anaphoric description has no eligible
antecedent, inspect all objects: one match resolves, several require a choice,
and none fail. A salience ambiguity is clarified rather than bypassed by fallback.

Every operand of one operation resolves against that operation's initial world
and ranking. Resolution order may determine which clarification is presented
first, but must not determine semantic preference. Preserve resolved identifiers
when pausing. A later operation in a sequence resolves against the updated state.

```text
move the object at A4 to B3. set color of it to green. exchange positions of the object with color red and the object with shape loop. what is the shape of the object at B3?
```

### 6.1 Salience state

Salience is a list of records `(entry age, utterance age, typed referent, mentioned
properties)`. A referent identifies an object or a square. Separate mentions are retained. The present entry has age 0; the
previous three entries, ages 1–3, remain eligible. Lower ages mean more recent.
Utterance age 0 is the most recently completed sentence in that entry.

On starting an executable entry, increment entry ages and discard those beyond
3. On completing a sentence, age older mentions within the present entry once
and add its new mentions at `(0,0)`. Clarification does not start a new entry or
age the paused sentence again. Courtesy and rejected previews do not age salience.

`it` uses the lexicographically smallest eligible age pair within the required kind; multiple distinct
referents at that pair require clarification. For an anaphoric description,
consider only objects satisfying all its descriptors now. Each descriptor must
have an eligible truthful mention of that object. Give each descriptor its best
score `10 * entry age + utterance age`, and sum those scores. With `n` distinct
descriptors, candidates whose total is less than `n + 1` above the best total
are tied. This is a specified demo heuristic, not a general theory of salience.

Successful commands and questions mention their explicit resolved object and
square operands. Creation also mentions the new object. Bulk mutations mention every
affected object at the same age; copying/cloning mention their source and
destination/new object at the same age. `it` does not arbitrarily pick the first.
Successful no-change operations still mention their resolved operands.

Associate only explicitly relevant, currently true appearance values and actual
positions: descriptors, tested values, returned values, and values set, copied,
exchanged or moved. False tests do not introduce false antecedent properties.
An object mention can have an empty property list. After every completed sentence,
purge false properties and deleted identifiers from the whole ranking.

Aggregate selection, counting and quantification do not introduce each member
of the tested class as an antecedent. Explicit reference targets in their
conditions do receive mentions. Failed sentences add no new mentions but advance
utterance age once. Visual edits purge stale properties and identities without
inventing chat mentions. Atomic-batch salience is staged and commits or rolls
back with its domain state.

### Typed square and object salience

A discourse referent is either an object identifier or a square coordinate.
Both kinds share one `(entry age, utterance age)` clock and the current-entry plus
previous-three-entry window. Mentions at the same age are tied, including across
kinds when both kinds are permitted by an expression.

Resolve `it` within the kind required by its operand:

| Expression | Eligible antecedents |
| --- | --- |
| `Set color of it to red.` | Objects only. |
| `Does it satisfy occupied?` | Squares only. |
| `Does it satisfy shading is dark?` | Squares only. |
| `Does it satisfy color is red?` | Objects only. |
| `Move #3 to it.` | Squares only. |
| `Create object on it.` | Squares only. |
| `Which object occupies it?` | Squares only. |
| `Does it satisfy at the edge?` | Either kind; use recency across both. |

`true`, edge, corner, row and column conditions apply to either kind. A Boolean
condition requires a single kind supported by every constituent: mixing
`occupied` with an object-color condition is a syntax error, even under `or`.
The parser retains an unresolved pronoun instead of asking for a syntactic
object-versus-square reading. Evaluation selects the most recent eligible
referent, not the most recent one for which the answer would be true. Equal-age
alternatives ask for a typed choice. No eligible antecedent is a diagnostic.

**Never implicitly convert a square into its occupant or an object into its
position.** Explicit `the object at it` first resolves a square pronoun and then
selects its existing occupant; an unoccupied square is a failed object reference.
A returned coordinate or occupant identifier does not automatically become a new
antecedent. An object query does not mention its position as a square.

Standalone square operands in questions, creation sites, movement destinations
and location lists used as destinations receive square mentions. Object operands
and newly created objects receive object mentions. `Move #3 to D4.` therefore
mentions both #3 and D4 at the same age: a subsequent edge question can require
clarification, while a color or occupancy question selects its required kind.
An occupant selector such as `the object at D4` mentions the selected object,
without separately introducing its nested location selector as a square antecedent.
Literal predicate values and rectangle pivot bounds are values, not extra mentions.
Aggregate results do not mention each selected member. Visual edits only purge.

Square facts are predicates of the fixed location, such as occupancy or shading.
False facts are purged after every successful operation and visual edit; movement,
creation or deletion elsewhere may invalidate occupancy evidence. The square
mention survives even if its occupant is deleted, while deleted object mentions
are removed. Atomic staging, persisted clarification, preview and Undo apply to
both kinds together. Undo restores world and the complete typed salience ranking.

```text
Does D1 satisfy not occupied?
Does it satisfy occupied?
```

The second question refers to D1 regardless of the first answer. It does not
select an object occupying D1.

## 7. Layer 3 — Conceptual terms and predicates

### 7.1 Computed terms and collections

```ebnf
relative-square = "the square", direction, "of", base-object-ref ;
collection = "objects", "[", object-ref, { ",", object-ref }, "]"
           | "objects at", "[", square-expr, { ",", square-expr }, "]"
           | "objects matching", object-condition ;
```

A relative square is the immediate orthogonal neighbor of a placed reference
object. An unplaced reference or an out-of-board result is a diagnostic. This
does not select or create the neighboring square's occupant. The explicit form
`the object at the square north of #3` does select that occupant and fails if
the square is unoccupied.

`the unique object matching condition` requires exactly one match in the whole world,
without a salience preference. Multiple matches require clarification; no match
fails. It is distinct from an anaphoric description. Its explicitly selected
object is mentioned normally.

Collections are sets of identities selected once at the start of their operation.
An explicit object list must resolve every member; duplicate resolved identities
are rejected. An `objects at [...]` list requires an occupant at every listed
square and rejects duplicates. A matching collection may be empty and includes
unplaced objects when its condition permits them. These collections have no
implicit ordering or permission to change membership during the operation.

Reference targets inside computed conditions must be `base-object-ref` terms;
recursively nested computed targets and nested quantifiers are not admitted.
All explicit targets resolve once before testing class members, even if the
class turns out to be empty. A missing target is a diagnostic, not false.

### 7.2 Derived predicate grammar

```ebnf
derived-object-atom = comparison-attribute, "equals that of", base-object-ref
                    | comparison-attribute, "shares a present value with", base-object-ref
                    | "same object as", base-object-ref
                    | "next to", base-object-ref
                    | "one square", direction, "of", base-object-ref
                    | "at the edge"
                    | "in a corner"
                    | "row is", row
                    | "column is", column
                    | "on a square matching", square-condition ;
derived-square-atom = "at the edge"
                    | "in a corner"
                    | "row is", row
                    | "column is", column
                    | "shading is", shading ;
```

| Predicate | Meaning |
| --- | --- |
| Attribute `equals that of` a target | Equal nullable values, including two absences |
| Attribute `shares a present value with` a target | Both values are present and equal |
| `same object as` | Identifier equality; appearance is irrelevant |
| `next to` | Both placed, with Manhattan distance exactly 1; diagonals excluded |
| `one square D of` | Exact directed one-square offset from a placed target |
| `at the edge` | A placed object or square has row 1/8 or column A/H |
| `in a corner` | A placed object or square has both an extreme row and an extreme column |
| Row/column test | Exact coordinate value; false for an unplaced object |
| `on a square matching condition` | The object's actual position satisfies that square condition; false when unplaced |

Unplaced objects fail spatial predicates, except nullable attribute equality,
which explicitly compares their absent coordinate states. Presence tests provide
the on-board question: `position is present`. Feedback for two equal absent
values explains that both objects lack the queried attribute.

`on a square matching condition` is a predicate over the one stored position; its
article does not introduce a new reference or create a square or object.

```text
does it satisfy position is present? does #3 satisfy color equals that of #4? does #3 satisfy color shares a present value with #4? does #3 satisfy next to the object with shape bloom and (not in a corner)? does the object with color red satisfy on a square matching shading is dark? what is the row of it? what is the appearance of it?
```

Row answers are 1–8; column answers are A–H; both return `none` when unplaced.
An appearance answer is the complete three-field appearance literal.

## 8. Layer 3 — Conceptual commands

All conceptual commands are atomic, including their complete domain and salience
effects. Internal expansion must not expose partial movement, replacement or
selection changes. Resolve operands and capture source values before updating.
Expansion records one sentence's mentions; internal atomic steps do not separately
age salience or become additional Undo units.

```ebnf
conceptual-command = "step", object-ref, direction
                   | "move", object-ref, "next to", object-ref
                   | "copy", component, "from", object-ref, "to", object-ref
                   | "transfer", component, "from", object-ref, "to", object-ref
                   | "exchange", component, "of", object-ref, "and", object-ref
                   | "clone appearance of", object-ref, "into a new object", creation-site
                   | "set appearance of", object-ref, "to", appearance-literal
                   | "clear appearance of", object-ref
                   | bulk-command
                   | "rearrange positions by", "[", position-pair, { ",", position-pair }, "]"
                   | "permute appearance by", "[", appearance-pair, { ",", appearance-pair }, "]"
                   | "rotate", transform-component, "of", collection, "by", turn, "about", pivot
                   | "reflect", transform-component, "of", collection, "across", axis, "through", pivot ;
bulk-command = "set color of", collection, "to", color
             | "set size of", collection, "to", size
             | "set shape of", collection, "to", shape
             | "clear", component, "of", collection
             | "set appearance of", collection, "to", appearance-literal
             | "unplace", collection
             | "delete", collection
             | "shift positions of", collection, "by", offset ;
offset = offset-fields | "(", offset-fields, ")" ;
offset-fields = "east", signed-integer, ",", "north", signed-integer ;
position-pair = object-ref, "to", square-expr ;
appearance-pair = object-ref, "to", object-ref ;
transform-component = "positions" | "appearance" ;
turn = "90 degrees clockwise" | "180 degrees" | "90 degrees counterclockwise" ;
axis = "vertical" | "horizontal" ;
pivot = "the center of rectangle", square, "to", square ;
```

`move S to relative-square` is already supplied by the atomic movement form with
a computed square operand. It means relocation, not traversal through a path.

### 8.1 Relative movement and choices

`step S D` changes position by exactly one square in direction D. Its source must
be placed. Moving to a computed square can place an unplaced source, but its
reference object must be placed. Occupied or out-of-board destinations fail
without changing anything.

`move S next to T` considers currently unoccupied orthogonal neighbors of T,
in north–east–south–west order. T must be placed. S may be unplaced. S's current
square is occupied and is not an offered destination. No available destination
fails with `No free squares`; one is selected; several pause for a square choice.
The already resolved S and T are retained throughout that choice.

```text
step it north. move #3 to the square west of #4. move #3 next to #4.
```

### 8.2 Copy, transfer, exchange, replacement and cloning

The named component is either one appearance attribute or the complete appearance
bundle. Every operation includes absence: copying an absent value clears the
destination's value. None of these operations copies identity or position.

| Operation | Source | Destination |
| --- | --- | --- |
| Copy | Unchanged | Receives captured source component |
| Transfer | Component cleared | Receives captured source component |
| Exchange | Receives destination's captured component | Receives source's captured component |
| Set appearance | No source object | Receives the complete literal, including `none` fields |
| Clear appearance | No source object | All three appearance attributes become absent |
| Clone appearance | Unchanged | A newly allocated object receives source appearance and explicit placement |

Copy, transfer and exchange with the same resolved object succeed with no change;
transfer to oneself does not clear the source. Cloning always creates a distinct
identity. Its destination must be free or explicitly off the board; failure
creates no object. An absent source component is a legitimate value state, not
a missing-reference error.

```text
copy color from #3 to #4. transfer shape from #3 to #4. exchange appearance of #3 and #4. set appearance of #3 to color red, size none, shape loop. set appearance of #3 to color none, size none, shape none. clone appearance of #3 into a new object on B3. clone appearance of #3 into a new object off the board.
```

### 8.3 Bulk mutation and explicit mappings

Bulk mutations capture their whole collection once. Unselected objects are
unchanged. A matching collection with no members succeeds with no change and
feedback `No matching objects`. Explicit lists still fail on missing members.
Every affected object receives the same literal assignment; no ordering decides
whose update wins. The whole operation fails if any effect violates a constraint.

Shifting requires every selected object to be placed. The offset adds its east
component to the column index and its north component to the row. Destinations
are checked simultaneously: cells vacated by selected objects may be reused;
cells occupied by unselected objects may not. Intermediate traversed squares
are irrelevant. A zero offset succeeds with no change.

`rearrange positions` supplies a simultaneous identity-to-square mapping. Sources
must resolve to distinct objects; destinations must be distinct, in bounds, and
free of unselected occupants. Sources may be unplaced. Only mapped objects move;
their appearances and identities are preserved. A full-board cycle needs no
temporary free square.

`permute appearance` supplies directed source-object-to-destination-object pairs.
Sources and destinations must each be distinct and their identity sets must be
equal. Every destination receives its source's captured complete appearance.
Positions and identities stay fixed. Fixed points are allowed. Pair order has
no effect; neither mapping form permits repeated destinations.

```text
set color of objects matching shape is bloom to red. clear size of objects [#3, #4]. shift positions of objects at [D4, E4] by east 0, north 1. rearrange positions by [#3 to D5, #4 to E5, #5 to E4, #6 to D4]. permute appearance by [#3 to #6, #6 to #5, #5 to #4, #4 to #3].
```

### 8.4 Rotation and reflection

The rectangle is named by its bottom-left and top-right squares. Both coordinate
components must be nondecreasing; degenerate rectangles are permitted. Its pivot
is the midpoint of the two cell centers, which may have half-integer coordinates.
Selection is independent of the rectangle: the rectangle specifies a pivot,
not an implicit collection or permission to affect other occupants.

For a source center `(x,y)` and pivot `(cx,cy)`, the destination is:

| Transformation | Destination center |
| --- | --- |
| 90 degrees clockwise | `(cx + y - cy, cy - x + cx)` |
| 180 degrees | `(2*cx - x, 2*cy - y)` |
| 90 degrees counterclockwise | `(cx - y + cy, cy + x - cx)` |
| Vertical reflection | `(2*cx - x, y)` |
| Horizontal reflection | `(x, 2*cy - y)` |

Every selected object must be placed and every transformed point must be an
in-bounds cell center. There is no rounding. An empty transformation collection
fails with `No selected objects`, rather than implying a drawing or creation.

- **Positions:** apply the simultaneous identity-to-destination mapping. Selected
  identities and appearances travel together; unselected occupants block it.
- **Appearance:** keep every identity and position fixed. The transformed square
  set must equal the selected original square set. Move complete captured
  appearance bundles along the mapping between those resident identities.

Both variants are atomic. They have different meanings even if their rendered
results coincide. Neither rotates the geometry of an individual shape or changes
its attributes to simulate movement.

```text
rotate positions of objects at [D4, E4, D5, E5] by 90 degrees clockwise about the center of rectangle D4 to E5. rotate appearance of objects at [D4, E4, D5, E5] by 90 degrees clockwise about the center of rectangle D4 to E5. reflect positions of objects matching position is present across vertical through the center of rectangle A1 to H8.
```

The clockwise center-square mapping is D4 → D5 → E5 → E4 → D4. In a position
rotation, the object formerly at D4 retains its identity at D5. In an appearance
rotation, the D5 object's identity stays at D5 and receives the appearance
formerly at D4. Review must display that distinction explicitly and ask when
the user's request leaves it unsettled.

## 9. Layer 3 — Selection, counting and quantification

```ebnf
conceptual-question = "which objects match", object-condition
                    | "how many objects match", object-condition
                    | "does", quantifier, "object matching", object-condition,
                      "satisfy", object-condition
                    | "which squares match", square-condition
                    | "how many squares match", square-condition
                    | "does", quantifier, "square matching", square-condition,
                      "satisfy", square-condition ;
quantifier = "every" | "some" ;
```

The same typed condition language is used for a single-object check, computed
selection, counting and quantification. There is no special shortened predicate
list for aggregates and no implicit comparison target. Boolean scope is explicit
through the grammar in Section 5.2. Restriction and predicate apply to the same
bound member; explicit reference targets are resolved once outside that binding.

Objects range over every existing object, including unplaced ones. Squares range
over all 64 locations. `true` selects the entire relevant universe. An object
selection answer is a list of identifiers, sorted numerically; a square selection
answer is sorted by ascending row, then ascending column. Empty selections return
`[]` and counts return 0.

`every` means all matching members satisfy the predicate, with no existential
commitment. An empty restriction yields `true — no matching objects` or
`true — no matching squares`. `some` requires at least one matching member that
satisfies the predicate and is false for an empty restriction. The same empty
restriction explanation accompanies that false answer.

No implicit “same as one another” comparison, nested quantifier or indefinite
object reference is present. A request requiring an unsupported relation or scope
must be clarified or reported as unsupported, not replaced with weaker checks.

```text
which objects match color is red and shape is bloom? how many objects match next to #3 and size is large? does every object matching color is red satisfy at the edge? does some object matching shape is spark satisfy size is large and position is present? which squares match (not occupied) and shading is light? how many squares match not occupied? does every square matching in a corner satisfy occupied? how many objects match true?
```

## 10. Complete operation boundaries and feedback

Successful mutation feedback identifies created/deleted objects and gives
before/after values for changed attributes and positions. Macro feedback may be
compact, but the review must expose its complete resolved mapping. A changed
appearance is never described as an object move. Equal appearances do not make
distinct identities interchangeable.

Each command/question has a distinct outcome: completed with changes, completed
with no change, answered, blocked/unresolved, or paused for clarification.
Boolean false, absent value, missing reference, no-change and blocked operation
must remain distinguishable. A failed or paused command has no partial domain
effect of its own. Answers come from the logic engine, never the LLM.

Only object creation and cloning create objects. Only deletion ends their
existence. Movement and exchanges preserve identities. All appearance tools
exclude position and identity. Square predicates do not mutate the board.
Queries do not create entities or silently turn into commands.

Canonical syntax has no `make`, `turn`, `swap`, `erase`, bare square-as-object,
shape synonyms, optional copulas, optional final punctuation or ignored command
suffixes. Natural-language input may use those words; the interpreter must choose
the precise canonical operation or ask a consequential clarification.

The engine is a pure state transformation supplied with domain definitions,
world, discourse, pending work and allocation bookkeeping. HTTP, database access,
model transport and presentation do not belong to language evaluation. Learned
search may guide formal exploration if needed; it neither replaces symbolic
reference resolution nor determines human intent.

## 11. Worked entries and required distinctions

### 11.1 Explicit partial creation followed by reference

```text
create object with color red on A4. set shape of it to bloom. does it satisfy color is red and size is absent?
```

Creation supplies one identity, no size and no shape. The pronoun selects that
new object. Shape assignment preserves its color and position. The final answer
is true; no default size has been introduced.

### 11.2 Empty square versus absent attribute

```text
does A4 satisfy occupied? does the object at A4 satisfy color is absent?
```

The first question is false when the square is unoccupied. The second then fails
to resolve its subject; it does not answer true and does not create an object.
When A4 contains a colorless object, the first and second answers are both true.

### 11.3 An ordinary sequence versus a batch

```text
set color of #3 to red. move #3 to A4. set size of #3 to large.
```

If another object occupies A4, the color update remains, the move fails, and the
size assignment is not executed. One Undo reverses the completed entry effects.

```text
atomically { set color of #3 to red. move #3 to A4. set size of #3 to large. }.
```

Under the same collision, none of these domain or salience changes commits.

### 11.4 Two objects with absent colors

```text
does #3 satisfy color equals that of #4? does #3 satisfy color shares a present value with #4?
```

If both exist and lack color, the answers are respectively true with an absence
explanation, and false. If either identity is missing, reference resolution fails.

### 11.5 Identity-preserving versus appearance-only change

```text
exchange positions of #3 and #4.
```

The two objects move, carrying their attributes. In contrast:

```text
exchange appearance of #3 and #4.
```

The objects stay where they are and exchange all three nullable appearance
attributes. Preview may look identical. Neither reading authorizes the other.

## 12. Review checklist and versioning

Further revisions should review whether the canonical sentence forms are easy
to inspect, whether stop-on-failure and batch rollback fit the dialogue, and
whether the macro inventory has the right scope. Semantic requirements and
exact grammar must be versioned together. Each language version must remain a
standalone contract. The original coordinated object/network v2 release
required a fresh database; legacy syntax and continuations remain unsupported.
Current v2 databases are retained, as described in the [JSON contract](json-contract.md).
A semantic change requires an explicit compatibility or migration policy for stored continuations, interpretation proposals and sessions.
