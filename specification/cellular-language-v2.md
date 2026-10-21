# Cellular Domain Controlled Language — Version 2

## 1. Status, purpose and boundaries

**Runtime semantic version: `cellular-v2`.** This document specifies the
implemented language. It extends the existing cellular world protocol with
parsing, symbolic reference resolution, clarification, execution and questions.

The language is a precise, human-readable execution and review medium. An LLM
may interpret ordinary requests and propose alternatives. Haskell resolves
references, validates operations, computes evolution and supplies answers.
Courtesy remains outside the executable language. Natural synonyms belong to
the interpretation layer rather than the canonical grammar.

The language follows the [controlled-language manifesto](controlled-language-manifesto.md)
and shares execution and discourse conventions with the
[object](object-language-v2.md) and [network](network-language-v2.md) languages.
Its three layers are:

| Layer | Responsibility |
| --- | --- |
| 1: atoms | Cell assignment, synchronous evolution, ruleset operations and direct questions |
| 2: referential macros | Cell pronouns and descriptions resolved by the symbolic engine |
| 3: conceptual macros | Collections, spatial/color operations, neighborhood reasoning and bounded forecasts |

An atom can update many fields indivisibly. Replacing a complete ruleset,
possibly together with an explicitly authorized refill, is one such atom.
Layer membership never changes punctuation, atomicity or reference guarantees.

**Implemented foundations:** the 16×16 toroidal board, six-color model,
cell painting, one-generation evolution, complete ruleset replacement, GUI
presets, confirmed palette-related random refill, save/load and Undo. The
[backend contract](cellular-automata-backend.md) documents those foundations.
The syntax, discourse integration, multi-generation commands, conceptual
operations and questions below are available through the shared chat/review API.

Regression, predecessor search, historical timeline queries and full first-order
binding remain outside this version. In particular, Undo is never described as
reversing the transition function.

## 2. Domain model and exact meanings

### 2.1 Cells, colors and configuration

The board has 256 fixed cells, **A1–P16**, with A1 at the bottom left.
Every cell always exists and has exactly one active color. A coordinate denotes
that cell/location directly: there is no separate occupant and no implicit
conversion between an object and its position.

| Type | Values and meaning |
| --- | --- |
| Cell | A fixed coordinate A1–P16 |
| Color | `white`, `black`, `red`, `green`, `blue`, `yellow` |
| Active palette | A set of two to six of those colors |
| Neighborhood | `von neumann`: four orthogonal neighbors; `moore`: those four plus four diagonals |
| Direction | `north`, `east`, `south`, `west` |
| Configuration | The complete mapping from the 256 cells to colors |
| Ruleset | Active palette, global neighborhood and optional rule for each source color |
| Automaton state | Configuration, ruleset, generation number and ruleset revision |

Cell identity is its fixed coordinate. Changing a color never creates, deletes
or moves a cell. A traveling glider is an evolving color pattern, not an object
with an identifier or a persistent trajectory. There are no `#` identifiers,
unplaced cells, absent colors, occupancy, shape or size attributes.

White is a color, not vacancy. Black is not intrinsically alive. The Life preset
interprets black/white in its particular rules, but `alive`, `dead`, `empty` and
`occupied` are not canonical cellular predicates.

### 2.2 Topology and coordinates

Both axes wrap. North of A16 is A1; east of P4 is A4. The orthogonal neighbors
of A1 are A2, B1, A16 and P1. Moore additionally includes B2, B16, P2 and P16.
A cell never counts itself. Every neighborhood contains exactly four or eight
distinct cells.

Literal coordinates outside A1–P16 are invalid, not wrapped. Wrapping belongs
to defined spatial operations, not to repairing malformed input. Rectangle
bounds describe the ordinary displayed coordinate rectangle, bottom-left then
top-right; they never silently select a region across a seam.

There is no topological edge or corner. Display-border predicates and chessboard
shading are omitted. Row and column predicates remain available for selecting
visible strips without suggesting a boundary to evolution.

### 2.3 Rules and synchronous evolution

The rule literal has a **shared counted/target color**. A rule for
source red with target green and counts `[2, 3]` means:

> A red cell changes to green exactly when it has two or three green neighbors.

The source and target differ and are active colors. Counts form a set of
distinct integers from zero through the neighborhood maximum. An empty set
never fires. Each source has at most one stored rule. A missing or disabled
rule retains the source color; disabling preserves the stored target/counts
for later enabling, whereas clearing removes that stored rule.

All cells read the same pre-generation configuration. One application of the
fixed ruleset produces the entire next configuration simultaneously. There
are no update-order effects, rule priorities or probabilistic transitions.
Intermediate generations of a multi-generation command use its initial ruleset.

The underlying transition function acts on configurations. Configuration
equality compares every color at the same coordinate; equal color totals,
rotated pictures or translated patterns are not equality. Temporal recurrence
tests ignore the generation counter, which increases even on a fixed point.

### 2.4 Generation, revision and history

Painting, bulk color edits, copying, exchanging and spatial color transforms
preserve the generation number and ruleset revision. They edit the current
configuration, not a recorded past. Advancing by N adds N to the generation,
including when no cell color changes.

A real ruleset change increments its revision once. If the board remains valid,
it preserves cells and generation. An authorized palette-related random refill
replaces every cell and starts generation zero. Explicit random initialization
also starts generation zero, but preserves the ruleset and its revision.

Undo restores configuration, ruleset, generation, revision, discourse and any
pending continuation together. Revision and generation numbers can repeat
after Undo or on different branches. They are not globally unique snapshot IDs
and are insufficient by themselves for preview freshness checks.

Rule changes affect future evolution. They never reinterpret old snapshots.
A generation number does not establish that the current edited board was
actually reached by that many uninterrupted applications of the current rules.

## 3. Shared lexical, scope and execution conventions

Words are case-insensitive. Canonical words are lowercase and coordinates have
uppercase columns. Every command ends with `.`, including a single final
command; every question ends with `?`. Whitespace and line breaks separate
tokens. Decimal integers have no leading zeroes; negative offsets use `-`,
never `-0`. Range failures must be reported without machine-integer wrapping.

In EBNF below, quoted text is literal, `|` separates alternatives, `[ ... ]`
marks an optional item, `{ ... }` repetition, and unquoted parentheses group
grammar. Literal square brackets in programs delimit explicit lists.

```ebnf
entry = "undo", "."
      | sentence, { sentence }
      | "atomically", "{", command, { command }, "}", "." ;
sentence = command | question ;
command = command-body, "." ;
question = question-body, "?" ;
condition = primary
          | "not", condition
          | condition, "and", condition
          | condition, "or", condition
          | "(", condition, ")" ;
```

`undo.` is a complete entry, not a prefix with an ignored suffix. Atomic batches
contain commands only and cannot nest. Application-level `full reset` and saved
slot controls remain orchestration operations, outside this grammar.

The engine parses and statically checks the entire entry before executing it.
Unknown words, invalid coordinate literals, malformed lists and static type
errors reject the entry without domain or discourse changes. Contextual checks,
such as whether a target color is active or a rule fits the current neighborhood,
belong to command evaluation. A lexical count literal is in 0–8; whether count
8 is admissible depends on the neighborhood at that operation.

Boolean input has no implicit precedence. Meaningful scope ambiguities produce
fully parenthesized alternatives before any sentence executes. Associative
chains of only `and` or only `or` normalize directly. Nested description and
quantifier-condition boundaries follow the same policy. The engine must not
choose a grouping because its current answer happens to match another reading.
Redundant parentheses are optional; explicit list brackets and batch braces
remain required.

Ordinary sequences execute left to right and stop on failure, preserving earlier
completed sentences. Each command is atomic. Ambiguity pauses immediately before
the affected operation and retains resolved operands. An atomic batch stages
all domain/discourse effects privately and commits them together; failure
discards the entire staged batch. Paused staged state is explicitly provisional.

One user entry, including clarification rounds, is one Undo unit. A multi-step
advance is not several Undo units. No-change commands continue normally.
Questions and no-change commands may still alter discourse; a world no-op is
not necessarily a discourse no-op. Unchanged GUI submissions introduce no chat
mentions and retain their existing no-history behavior.

## 4. Layer 1 — Elementary operations and questions

At this layer, a cell operand is a coordinate literal. Later layers extend
operand expressions while retaining the same operation contracts.

### 4.1 Values and complete literals

```ebnf
color = "white" | "black" | "red" | "green" | "blue" | "yellow" ;
neighborhood = "moore" | "von neumann" ;
boolean = "true" | "false" ;
counts = "[", [ count, { ",", count } ], "]" ;
palette = "[", color, { ",", color }, "]" ;
rule-value = "target", color, ",", "counts", counts,
             ",", "enabled", boolean ;
rule-entry = color, ":", rule-value ;
ruleset-value = "palette", palette, ",", "neighborhood", neighborhood,
                ",", "rules", "[", [ rule-entry, { ",", rule-entry } ], "]" ;
board-policy = "preserving the board"
             | "randomly refilling the board if required" ;
```

Palette/count lists are sets: duplicate literal values are rejected and
canonical output sorts them. Palette order is white, black, red, green, blue,
yellow. Source entries are unique and printed in that order. The fields in
complete values appear in the fixed order shown above. Every stored rule,
including a disabled one, must satisfy palette/target/count constraints.

### 4.2 Commands

| Canonical command | Contract |
| --- | --- |
| `Set color of Q to C.` | Assign an active color to the resolved cell; preserve all other state. |
| `Advance N generations.` | Apply the initial ruleset synchronously N times, atomically; increase generation by N. |
| `Set rule for C to RULE-VALUE.` | Replace that active source's complete stored rule; preserve the remaining rules, palette and neighborhood. |
| `Clear rule for C.` | Remove that active source's stored rule; clearing a missing rule is a no-op. |
| `Enable rule for C.` | Enable an existing stored rule; a missing rule is a diagnostic. |
| `Disable rule for C.` | Disable an existing stored rule without discarding its values; missing is a diagnostic. |
| `Set neighborhood to NEIGHBORHOOD.` | Preserve palette/rules/cells; fail if any stored rule has an out-of-range count. |
| `Replace ruleset with RULESET-VALUE, BOARD-POLICY.` | Validate and replace the complete ruleset, applying exactly the stated board policy. |

The singular temporal spelling is `Advance 1 generation.`; values greater than
one use `generations`. This is number agreement, not a second operation.
Zero is not an advance. A stable board still advances time.

Rule component commands require an active source. Replacing a rule overwrites
the old complete value, including its enabled state. Missing rules can be set;
this writes a configuration entry and allocates no entity. Enabling an enabled
rule or disabling a disabled rule is a no-op.

All configuration commands increment the revision only for an actual change.
Equivalent two-color rules expressed with complementary neighbor counts are
no-ops, preserving the stored representation. Ordinary rule edits never refill
cells. There is no implicit count clamping, palette extension, rule deletion or
retargeting to make an edit succeed.

With `preserving the board`, every existing cell color must belong to the new
palette. With `randomly refilling the board if required`, the engine may refill
the whole board **only if** its colors would otherwise be invalid. A compatible
board remains unchanged. This permission is part of the reviewed command; a
failed preserve command never silently acquires refill permission.

Palette changes use complete replacement rather than an ambiguous command that
might also remove rules. Both board policies preserve unchanged semantics as a
no-op. The explicit random-initialization macro below is the tool for requesting
a new random board even when the palette is already compatible.

```text
Set color of A1 to black.
Set rule for white to target black, counts [3], enabled true.
Set rule for black to target white, counts [0, 1, 2, 3, 4, 7, 8], enabled true.
Advance 3 generations.
```

Those two rules are standard Moore-neighborhood Life: black cells retain their
color with five or six white neighbors, equivalently two or three black ones.

### 4.3 Direct questions

| Canonical question | Answer |
| --- | --- |
| `What is the color of Q?` | Its current color; never `none`. |
| `Does Q satisfy CELL-CONDITION?` | A Boolean about that resolved cell. |
| `What is the generation?` | Current generation number. |
| `What is the palette?` | Complete active color list. |
| `What is the neighborhood?` | `moore` or `von neumann`, with the corresponding count. |
| `What is the ruleset revision?` | Current snapshot's revision number. |
| `What is the ruleset?` | A complete readable ruleset value. |
| `What is the rule for C?` | The complete rule value, or `none` with an inactive/missing explanation. |

Basic cell predicates are `true` and `color is C`, closed under Boolean
composition. Derived predicates are added below. All six colors are valid
predicate literals: testing an inactive color returns false. Assignment to an
inactive color fails instead. A missing cell referent is a diagnostic, even
under negation or in a branch that could have been short-circuited.

A disabled rule is returned as a stored value with `enabled false`; an absent
rule returns `none`. Thus disabled, missing, never-triggering empty counts, and
an enabled rule whose condition currently fails remain distinguishable.

## 5. Layer 2 — Cell references and discourse

```ebnf
base-cell-ref = square
              | "it"
              | "the cell with color", color ;
cell-ref = base-cell-ref
         | "the cell matching", cell-condition
         | "the unique cell matching", cell-condition
         | "the cell", direction, "of", base-cell-ref ;
```

Literal coordinates, pronouns and simple color descriptions are Layer 2.
Computed descriptions and relative cells use Layer 3 predicates/spatial
calculation. Conditions inside computed descriptions can refer only to base
cell references; recursively nested computed targets and nested quantifiers
are excluded.

`it` denotes the most recent eligible cell mention; ties require clarification.
An anaphoric description first uses compatible, currently true mentioned facts.
If none qualifies, it searches all 256 cells: one match resolves, multiple
matches require a choice, and no match fails. `the unique cell matching ...`
uses the whole board without a salience preference; multiple matches still
require a choice. Resolution never paints, initializes or advances anything.

An explicit relative cell wraps according to the torus, independently of the
active four/eight-neighbor mode. It denotes a cell, not a moving pattern. Rules
are named explicitly by source color; rules, palettes, collections and patterns
do not become additional `it` referents in this version.

### 5.1 Shared salience policy

Cell referents use the shared square-coordinate kind, extended to A1–P16.
Records contain entry age, utterance age, the coordinate and mentioned facts.
The present entry and previous three entries are eligible. Entry age increments
once per executable entry. Completing a sentence ages older present-entry
mentions and adds its mentions at `(0,0)`; clarification does not age it again.

Pronouns use the lexicographically most recent age pair. For a description with
n required facts, use each fact's best truthful mention score
`10 × entry age + utterance age`, sum the scores and clarify candidates less
than `n + 1` above the best score. World fallback does not bypass a salience tie.
These are the existing demo heuristics, not a new ranking system.

Direct checks, assignments, copy/exchange operands and explicit reference targets
mention their resolved cells. Bulk writes mention their selected targets at the
same age, including successful no-change assignments. A later `it` must clarify
those ties. Selection/count/quantifier answers do not introduce each result as
an antecedent. Aggregate questions still mention explicit targets in their
conditions. Coordinate predicate values and rectangle bounds are values, not
additional mentions.

Evolution, random initialization and implicit cells inspected by an algorithm
do not introduce 256 arbitrary antecedents. They age discourse once as their
one sentence and purge obsolete facts. Ruleset/color literals do not introduce
cell mentions. Failed sentences add no successful mentions but advance the
utterance clock according to the shared execution policy.

After every successful operation and visual edit, purge false color and derived
facts throughout the ranking. Changing another cell may invalidate a neighbor
count; changing rules may invalidate a next-generation prediction even without
recoloring anything. A coordinate mention survives those changes while eligible:
the cell still exists. Recorded contextual predicates retain grounded reference
targets rather than resolving old pronouns again.

Visual edits purge facts without inventing dialogue mentions. Undo restores the
complete ranking. Questions can therefore require an Undo unit despite making
no domain change. Preview, courtesy and rejected interpretations do not age
committed discourse.

```text
Set color of A1 to black.
What is the color of it?
Advance 1 generation.
What is the color of it?
```

Both queries refer to A1. Evolution does not make the pronoun follow a black
pattern to another coordinate. A later color description must match current
facts, not the remembered appearance of a vanished pattern.

## 6. Layer 3 — Predicates, collections and spatial operations

### 6.1 Reusable cell and board predicates

| Cell predicate | Exact meaning |
| --- | --- |
| `row is N` | Current fixed row, 1–16. |
| `column is A` | Current fixed column, A–P. |
| `same cell as R` | Coordinate equality. |
| `color equals that of R` | Equal present colors at the evaluated snapshot. |
| `neighbor of R` | Membership in R's active Moore/von Neumann neighborhood; never self. |
| `connected to R` | Membership in R's same-color connected component, including R itself. |
| `neighbor count for color C is in COUNTS` | Number of C-colored active neighbors belongs to the explicit count set. |
| `changes in the next generation` | Its next color differs under the evaluated snapshot's ruleset. |

All these cell predicates support `not`, `and`, `or`, and are available uniformly
in single-cell checks, descriptions, collection filters, counting and
quantification. Reference operands resolve eagerly before testing members,
including for empty selections and logically irrelevant Boolean branches.

`neighbor of R` changes meaning when the active neighborhood changes; the
explicit compass construction still means one orthogonal step. Neighbor-count
predicate sets must fit the evaluated neighborhood. An impossible count is a
diagnostic rather than a silently false condition.

Connectivity is the reflexive transitive closure of same-color neighbor steps,
using the active neighborhood and toroidal wrapping. Every cell along a path
must share the seed's color. Equal endpoint colors alone do not establish
connectivity. A cell is connected to itself; an isolated cell's component is a
singleton. The predicate applies uniformly in checks, descriptions, filters,
counts, quantification and forecasts. For example:

```text
Does A3 satisfy connected to D5?
How many cells match connected to A3?
After 20 generations, does A3 satisfy connected to D5?
```

Forecast connectivity is computed on the forecast configuration, with reference
coordinates resolved against the current state. Changes anywhere along a path,
or to the active neighborhood, can invalidate remembered connectivity facts;
recheck them rather than retaining a stale component association.

Board predicates are `monochromatic`, `monochromatic with color C`, and
`fixed point`, with the same Boolean grouping policy. Monochromatic means all
256 cells have one color. Fixed point means the next **configuration** equals
the current one under the current rules. The generation number is excluded
from that equality. These are predicates over the complete board, not aliases
for cell predicates.

### 6.2 Collections and color operations

```ebnf
collection = "cells", "[", cell-ref, { ",", cell-ref }, "]"
           | "cells matching", cell-condition
           | "cells connected to", cell-ref
           | "cells in rectangle", square, "to", square ;
```

Collections are frozen sets of coordinates at the start of their operation.
Explicit lists must resolve all members and reject duplicate resolved cells.
Matching selections may be empty. Rectangles include both bounds, require
nondecreasing column and row coordinates, and never wrap across a seam.

`cells connected to R` selects R's complete same-color component, including R.
It is equivalent to `cells matching connected to R`. Resolve the seed and freeze
the component before writing: recoloring cannot recruit additional cells during
the operation. For example, `Set color of cells connected to A3 to blue.` paints
exactly the original component, provided blue belongs to the active palette.
Discovering a component does not itself mention every member; subsequent bulk
writes follow the existing selected-cell mention policy.

| Command | Contract |
| --- | --- |
| `Set color of COLLECTION to C.` | Assign one active color to every selected cell simultaneously. |
| `Copy color from R to T.` | Capture R's color, assign it to T, preserve R. |
| `Exchange color of R and T.` | Exchange the two captured colors atomically. |
| `Replace colors by [R to C, ...].` | Simultaneous explicit cell-to-color mapping; duplicate resolved destinations fail. |
| `Permute colors by [R to T, ...].` | Closed one-to-one permutation of captured colors among the same selected coordinates. |
| `Shift colors of the board by east INTEGER, north INTEGER.` | Translate all 256 captured colors modulo 16; preserve fixed cell identities. |
| `Rotate colors of COLLECTION by ANGLE about PIVOT.` | Permute captured colors by the exact geometric mapping. |
| `Reflect colors of COLLECTION across AXIS through PIVOT.` | Permute captured colors by the exact reflection. |
| `Initialize the board randomly.` | Replace the complete configuration using the current palette and restart generation zero; preserve rules/revision. |

`cells matching true` selects the whole board. There is no separate clear/delete
operation: a uniform white board is an explicit color assignment, valid only
when white is active. Transfer is omitted because clearing a source has no
colorless state and must not invent a background color.

Empty matching writes succeed with `No matching cells`. Copy/exchange to oneself
is a no-op. Explicit mappings capture all sources and destinations before any
write; repeated destinations fail even when their proposed colors coincide.
Intentional successive assignments belong in a sequence. Closed permutations
require distinct source and destination coordinates with equal coordinate sets.

Shift offsets are signed integers; mathematical modulo is intentional toroidal
geometry, not numeric overflow. Rotations are `90 degrees clockwise`,
`180 degrees`, or `90 degrees counterclockwise`; axes are `vertical` or
`horizontal`. The pivot is `the center of rectangle A1 to P16`, with arbitrary
valid rectangle bounds allowed. Use exact half-cell arithmetic and require
the transformed selected coordinate set to equal the original set. Do not
round, wrap rotation results, overwrite outside cells or invent vacated colors.
Empty geometric selections fail. Only the whole-board shift explicitly wraps.

Random initialization is a new configuration, not one generation of evolution.
It promises active colors and a reproducible recorded random choice, not exact
color proportions, a specified pattern or guaranteed visually interesting output.
Review must show that it resets the generation. Rule-related refill permission
is different: it initializes only when required by the new palette.

### 6.3 Ruleset presets

A ruleset value can also be `preset game of life` or `preset rgb cycle`.
These are named complete semantic values used by `Replace ruleset`, not hidden
board templates. The board-policy suffix remains compulsory.

| Preset | Exact definition |
| --- | --- |
| `game of life` | Palette white/black, Moore; white→black at black counts `[3]`; black→white at white counts `[0, 1, 2, 3, 4, 7, 8]`; both enabled. |
| `rgb cycle` | Palette red/green/blue, Moore; red→green, green→blue, blue→red, each at target-color counts `[2, 3, 4, 5, 6, 7, 8]`; all enabled. |

Applying Life rules does not install a glider. Applying RGB rules does not
always randomize an already-compatible RGB board. GUI preset buttons continue
to prefill a local draft; an accepted chat `Replace ruleset` command applies
the specified value. These are different interface actions with explicit effects.

```text
Replace ruleset with preset rgb cycle, randomly refilling the board if required.
Advance 3 generations.
```

## 7. Layer 3 — Selection, counting and quantification

| Question | Result |
| --- | --- |
| `Which cells match P?` | All matching coordinates, ascending row then column. |
| `How many cells match P?` | Matching count, 0–256. |
| `Which neighbors of R match P?` | Matching active neighbors of the resolved cell, sorted by row then column. |
| `How many neighbors of R match P?` | Matching count, 0–4 or 0–8. |
| `Does every cell matching P satisfy Q?` | Every P-selected cell satisfies Q. |
| `Does some cell matching P satisfy Q?` | At least one P-selected cell satisfies Q. |
| `Does the board satisfy BOARD-CONDITION?` | Boolean over the whole configuration and its current rules. |
| `What is the next transition of R?` | Source color, stored rule or its absence, enabled status, actual target-color neighbor count, and resulting color. |

P and Q use the same complete cell-predicate language. There is one explicit
quantifier per question. Restriction and predicate apply to the same bound cell;
explicit reference targets resolve once outside that binding. There are no
bound-variable pronouns, nested quantifiers or indefinite relational targets.

Empty selections produce `[]` or zero. An empty universal restriction is true
with `no matching cells`; an empty existential restriction is false with that
explanation. Missing explicit reference targets remain diagnostics, even when
the restriction would be empty.

The next-transition answer is prospective symbolic evidence. It uses the current
board/rules, never a reconstructed historical story. Distinguish a missing rule,
a disabled rule, an empty count set, and a nonmatching count. Deriving this answer
does not apply the transition. For a missing rule, target and target-color count
are not applicable, rather than zero. A disabled stored rule can still show its
actual neighbor count while explaining that it is not applied. Its predicted
result color is never recorded as the cell's current color in salience.

```text
Which cells match color is black and neighbor count for color black is in [3]?
How many neighbors of A1 match color is black?
Does every cell matching color is red satisfy neighbor count for color green is in [2, 3, 4, 5, 6, 7, 8]?
What is the next transition of A1?
```

## 8. Layer 3 — Forecasting and bounded temporal questions

### 8.1 Exact-offset forecasts

```ebnf
forecast-question = "after", nonnegative-integer, generation-unit, ",",
                    forecast-state-question, "?" ;
```

`generation-unit` is `generation` for 1 and `generations` otherwise. The forecast
body is a color query, cell check, selection/count question, neighbor selection/
count question, every/some question, board check or next-transition question
from Sections 4 and 7. A forecast cannot contain a command, another forecast,
a bounded temporal query or Undo. Configuration metadata queries are asked
directly without a forecast prefix.

At offset N, evaluate the question on `F^N(B)` using the current ruleset F.
Offset zero means the current configuration. Nothing advances or commits to
the current world: cells, rules, actual generation and revision remain unchanged.

Resolve all explicit cell references against the current world/discourse **before
forecasting**, then retain their coordinates. A description does not silently
start selecting a different future cell. Collection filters, predicate values
and quantifier restrictions are evaluated on the forecast configuration.
Thus a question about the currently red cell differs from a selection of cells
that will be red at the requested offset.

Forecasts mention explicit resolved cells using current truthful reference facts.
Future result colors and predicted facts are not recorded as current salience
properties. Aggregate future results do not become arbitrary antecedents. This
preserves reference resolution without claiming predicted facts already hold.

```text
After 3 generations, what is the color of A1?
After 3 generations, which cells match color is red?
After 3 generations, what is the color of the cell with color red?
```

The last question may require choosing among **currently** red cells before
computing an answer. It does not mean the color of a future red cell.

### 8.2 Bounded behavior

| Question | Exact meaning |
| --- | --- |
| `What is the least return time of the board within N generations?` | Least positive k≤N with `F^k(B)=B`, or `none within N generations`. |
| `What is the first generation offset within N generations at which R satisfies P?` | Least k in 1–N where the initially resolved coordinate satisfies P, or a bounded nonmatch. |
| `What is the first generation offset within N generations at which the board satisfies P?` | Least k in 1–N where the complete configuration satisfies the board condition, or a bounded nonmatch. |

These questions inspect possible future execution of the **current, fixed**
ruleset. They do not inspect stored history or mutate it. Time zero is excluded
by the positive-offset contract. `After 0 generations, ...?` tests the present
explicitly when needed. Conditions contain only the snapshot predicates above,
not recursive temporal questions.

A fixed point has return time 1. An oscillator returning after two generations
has least return time 2. A transient that later enters a cycle need not ever
return to its starting configuration. A translated pattern is not an exact
return, even if it looks like the same shape elsewhere. On this torus it may
return later after wrapping; that later equality is a separate derived fact.

`none within N generations` establishes exactly the bounded nonmatch. It is not
`never`, proof of aperiodicity, or proof that no fixed point is eventually reached.
No answer may replace exhaustive bounded evaluation with an LLM guess.

### 8.3 Stabilization ("termination")

For this domain, termination means reaching a fixed configuration: the next
generation has exactly the same colors at every coordinate. It does not mean
stopping the generation counter, becoming monochromatic, or entering an
oscillation of period greater than one. Use explicit fixed-point wording:

| Question | Exact meaning |
| --- | --- |
| `Does the board reach a fixed point within N generations?` | Whether some k in 0–N satisfies `F^(k+1)(B)=F^k(B)`; include the earliest k as evidence. |
| `What is the stabilization time of the board within N generations?` | Least such k, or `none within N generations`. |

Unlike the positive-offset first-hit questions above, these questions include
the present configuration. An already stable board has stabilization time 0.
Offset k names the first stable configuration; its equality with the following
configuration witnesses stability. Testing the endpoint k=N may therefore
inspect generation offset N+1. Neither query advances the actual board.

```text
Does the board reach a fixed point within 20 generations?
What is the stabilization time of the board within 100 generations?
```

With a fixed deterministic ruleset and p active colors, this board has at most
`p^256` configurations. Eventual stabilization is decidable in principle:
iterate until a fixed point or a repeated configuration is found. A repeated
nontrivial cycle rules out a later fixed point. The possible search is enormous,
so the demo exposes bounded queries. A bounded negative answer means only
`No fixed point within N generations`, not `never stabilizes`, unless an exact
cycle witness separately establishes that stronger conclusion.

### 8.4 Bounded cell-count reachability

```text
Does the count of cells matching color is black reach 0 within 70 generations?
Does the count of cells matching color is red reach 12 within 20 generations?
Does the count of cells matching color is black and row is 8 reach 1 within 5 generations?
```

The canonical form is `Does the count of cells matching P reach K within N
generations?`. K is an exact integer count from 0 through 256; N is a positive
bound from 1 through 256, with `generation` for 1. P uses the complete cell
predicate language, including Boolean conditions and explicit reference operands.
Nested temporal questions and quantifiers are excluded.

Search offsets **0 through N inclusive**, using the current fixed ruleset.
Return true with the least matching generation offset, or false with
`count does not reach K within N generations`. If the count already equals K,
the witness is offset 0. This tests equality, not a threshold or a requirement
that the count changed. Neither answer advances the current world or changes
its generation, rules or revision.

Resolve references once against current state/discourse, then evaluate P on
each hypothetical configuration. Only explicit reference operands are mentioned;
future facts and matching cells do not become arbitrary current antecedents.
Resource exhaustion is a diagnostic, never a negative answer.

For color black and K=0, this asks whether black becomes absent within the
bound. It **does not establish permanent extinction**: under general rules a
color may disappear and later reappear. A request explicitly requiring permanent
absence needs clarification or an unsupported-capability explanation; the LLM
must not silently weaken it to this bounded first-hit question.

### 8.5 Evaluation limits

**Runtime limits:** advance commands and positive temporal
queries accept 1–256 generations; forecasts accept 0–256. A one-step derived
predicate at the last forecast offset may inspect one additional generation.
Use a deterministic per-entry work budget, initially 4096 transition-function
applications, with reuse of cached frozen forecasts where appropriate.
A 100-generation query on the supplied glider takes approximately 0.06 seconds
in a local optimized-engine check; actual timing depends on hardware and predicates.

If a work/time limit interrupts evaluation, return a resource-limit diagnostic,
not false or a bounded nonmatch. An interrupted command commits none of its
own effects. These limits constrain work, not the automaton's nonnegative
generation number. No unbounded temporal query is part of this version.

## 9. Review, random choices and operation evidence

LLM translations remain proposals until accepted. Preview and acceptance use
the same resolved state, grammar version and frozen random choices. Any relevant
world, ruleset, discourse or pending-state change invalidates a stale review.
Equality of generation/revision labels alone does not establish freshness.

Random operations must obtain an execution-context seed from orchestration;
Haskell remains a pure transformation supplied with that seed. Freeze each
operation's seed before its first preview, persist it through clarification and
reuse it at acceptance. Reopening the same unchanged preview must not reroll
the board. A separately requested random initialization is a new choice.
Tentative randomness does not authorize a world update. A private staged batch
also preserves its seeds while paused and discards its tentative world on failure.

Review and feedback expose:

- Resolved cell coordinates and frozen bulk selections.
- Exact source/target/count/enabled changes and the neighborhood/palette involved.
- Whether the configuration is preserved or randomly replaced.
- Changes to generation and ruleset revision, including a zero-change stable advance.
- Forecast offset, fixed ruleset and derived witness or bounded nonmatch.
- A next-transition explanation derived from actual neighbor counts.
- Operation failure, successful no-change, an answer and a pending choice as
  separate outcomes.

Actual change reports come from the engine, never from an LLM courtesy reply.
One GUI ruleset Submit remains one API request. A chat entry also reaches Haskell
as one entry, not independent per-rule HTTP writes. Haskell may evaluate its
explicit commands sequentially or stage an explicit batch; FastAPI persists
their complete entry/continuation history and owns Undo storage.

## 10. Worked precision challenges

### 10.1 Predict without executing

Precondition: Moore Life, with a horizontal black blinker prepared by:

```text
Atomically {
  Set color of cells matching true to white.
  Set color of cells [H8, I8, J8] to black.
}.
```

In a subsequent entry:

```text
After 1 generation, which cells match color is black?
What is the least return time of the board within 4 generations?
What is the generation?
```

The first answer is `[I7, I8, I9]`; the second is 2. Neither query evolves the
actual board or increments its generation. `Advance 1 generation.` subsequently
does so. A fixed-point board advanced once still reports a generation increase
even when its changed-cell count is zero.

### 10.2 Same picture, different future

Prepare the same blinker. Ask its least return time: 2 under Life. Then:

```text
Disable rule for white.
```

The picture is unchanged but the birth rule is disabled. An exact-offset forecast
now differs. The ruleset revision changes, while generation stays fixed. Undo
restores the original law and its original future, not just the visible picture.

### 10.3 An incomplete neighborhood change

With Life's black rule containing white counts 7 and 8:

```text
Set neighborhood to von neumann.
```

The operation fails; it must not silently drop those counts. One valid explicit
alternative is a different, intentionally specified rule and neighborhood:

```text
Atomically {
  Set rule for black to target white, counts [0, 1, 2, 3, 4], enabled true.
  Set neighborhood to von neumann.
}.
```

That is a new automaton, not a claim to preserve Moore Life behavior. A failed
second command would roll back the first because the entry is a batch.

### 10.4 Palette preservation versus replacement

On a black/white board:

```text
Replace ruleset with preset rgb cycle, preserving the board.
```

This fails without recoloring anything. The materially different alternative is:

```text
Replace ruleset with preset rgb cycle, randomly refilling the board if required.
```

It changes the palette/rules and randomly replaces the board at generation zero
as one undoable operation. The preview must show those effects. On an already
compatible RGB board, the same permission preserves its colors. Only
`Initialize the board randomly.` explicitly requests another random initialization.

### 10.5 Stabilization versus recurrence

Under the Game of Life preset, an isolated 2×2 black block on a white board is
already stable: stabilization time 0, least return time 1. A blinker returns to
its starting configuration after 2 generations but does not reach a fixed point
within 100 generations. Its exact period-two cycle also proves that it will not
stabilize while the rules remain unchanged. Both answers must come from the
engine's configuration comparisons, without changing the world or its clock.

## 11. Implementation and compatibility

`Domains/Cellular/Language/` supplies typed syntax, parsing, canonical formatting,
reference resolution and evaluation. It reuses the shared typed square referents
and discourse aging policy without inventing object identifiers or occupants.
The existing pure cellular evaluator remains authoritative for single steps,
cell painting and complete ruleset replacement. FastAPI handles persistence,
review, random seeds and Undo; Flutter displays state and forwards requests.

The transport permits separate counted and target colors. New language literals
use the shared-color form. Existing binary rules, including the Life fixture,
are displayed in their equivalent complementary-count form; equivalent writes
preserve the stored representation and revision. Nonbinary rules counting a
different color remain executable and unchanged. Inspection explicitly discloses
the legacy counted color; replacing such a rule requires a complete explicit
new value. No automatic normalization discards their meaning.

Existing worlds, rules, Undo histories and slots remain valid. Empty salience
rankings need no migration. Cellular continuations store their original world,
ranking, canonical entry, accepted cell choices, completed-sentence offset and
random seed. Grouping choices are resolved before the entry starts. Random seeds
are stored with interpretation proposals and reused by preview, acceptance and
subsequent clarification. No database purge is required.

All three layers described here are implemented, including bounded forecasts,
stabilization, same-color components, ruleset presets and spatial/color mappings.
The LLM receives the active domain's language reference and validated examples;
its proposals use the same preview/accept/reject controls as the other domains.

Deferred extensions include predecessor inference; historical explanations and
timeline navigation; exact-versus-translated pattern recurrence; persistent named
patterns/regions; seed syntax for expert input; nested quantification and
unbounded reachability. Future regression must verify witnesses by forward
evolution, distinguish unsolved from impossible, and remain distinct from Undo.

## 12. Acceptance obligations

1. **Topology:** literal A17 fails; north of A16 resolves A1; A1's four/eight
   neighbors are distinct and match the toroidal definitions. Connectivity
   includes self and seam paths, distinguishes Moore diagonals from von Neumann
   steps, and rejects disconnected equal-color endpoints.
2. **Atomic evolution:** N generations match N authoritative single steps;
   stable boards advance the clock; a resource failure commits no partial command.
3. **Rules:** missing, disabled, empty-count and nonmatching rules retain color
   with distinct explanations; all count boundaries and palette constraints hold.
4. **Complete replacement:** no invalid intermediate ruleset escapes; invalid
   palette preservation changes nothing; authorized refill and revision changes
   commit together and Undo restores the complete pre-entry state.
5. **Compatibility:** untouched or binary-equivalent rules add no domain change;
   nonbinary counted-color differences are never silently erased.
6. **Reference integrity:** `it` stays at its fixed coordinate through evolution;
   ties ask; false color, connectivity, neighbor-count and prediction facts are purged.
7. **Scope and quantification:** meaningful Boolean ambiguity pauses before the
   entry executes; empty every/some and failed explicit targets follow the
   shared semantics; no hidden quantifier binding is introduced.
8. **Frozen selections:** bulk operations, mappings and color permutations read
   pre-operation values; component painting never expands into newly connected
   cells; duplicates/conflicts fail without partial writes.
9. **Forecasting:** predicted answers equal authoritative evolution from the
   frozen snapshot; actual state stays unchanged; current-reference resolution
   and future filtering differ as specified; future facts never masquerade as
   current salience facts.
10. **Temporal claims:** a block is fixed with stabilization time 0 and return
    time 1; a blinker returns at 2 without stabilizing. A transient reaching its
    first fixed configuration at k reports k, including k=N after checking N+1.
    Transient recurrence is not starting-state recurrence; shifted pictures are
    not exact equality; a limit is never reported as false or impossible.
    Count reachability includes offsets 0 and N, reports the earliest exact
    count, grounds current reference operands and makes no permanence claim when
    a cyclic ruleset restores a color after its temporary absence.
11. **Review:** repeated previews reuse seeds; acceptance matches the preview;
    stale world/discourse/version rejects acceptance even when visible colors
    happen to match; cancellation commits nothing.
12. **Integration:** GUI and language use the same laws, presets and transition
    evaluator; question-only history and Undo restore salience; existing object
    and network conversations retain their semantics.

## 13. Syntax inventory

Uppercase names below are typed metavariables, not literal input. All commands
require a period and all questions a question mark. Lists retain their brackets.

| Category | Forms |
| --- | --- |
| Cell operands | `A1`–`P16`; `it`; `the cell with color C`; `the cell matching P`; `the unique cell matching P`; `the cell D of R` |
| Collections | `cells [R, ...]`; `cells matching P`; `cells connected to R`; `cells in rectangle Q to Q` |
| Rule values | `target C, counts [N, ...], enabled true/false` |
| Ruleset values | `palette [C, ...], neighborhood MODE, rules [C: RULE, ...]`; `preset game of life`; `preset rgb cycle` |
| Cell predicates | `true`; `color is C`; row/column; cell/color comparison; active-neighbor membership/count; `connected to R`; next-generation change |
| Board predicates | `monochromatic`; `monochromatic with color C`; `fixed point` |
| Boolean composition | `not P`; `P and Q`; `P or Q`; explicit grouping as needed |
| Cell/color commands | Set one/collection; copy; exchange; simultaneous replacement; closed permutation; whole-board shift; selected color rotation/reflection |
| Evolution | `Advance N generations.` with singular agreement for 1 |
| Laws | Set/clear/enable/disable source rule; set neighborhood; replace complete ruleset with an explicit board policy |
| Initialization | `Initialize the board randomly.` |
| Direct questions | Cell color/check; current generation/palette/neighborhood/revision; complete ruleset/source rule |
| Aggregate questions | Which/how many cells or neighbors; every/some cell; whole-board check |
| Explanation | `What is the next transition of R?` |
| Exact-time forecast | `After N generations, STATE-QUESTION?` with singular agreement for 1 |
| Bounded temporal queries | Fixed-point reachability and stabilization time (including offset 0); `Does the count of cells matching P reach K within N generations?` (including offset 0); least starting-board return time; first positive offset satisfying a cell/board condition |
| Entry control | Sequences; `Atomically { COMMANDS }.`; standalone `Undo.` |

No aliases, optional final punctuation, cell creation/deletion, occupancy,
pattern-following pronouns, silently selected background colors, or hidden
historical/regression semantics are part of this language.
