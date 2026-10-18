# Network Domain Controlled Language — Version 2

## 1. Status and purpose

**Runtime semantic version: `network-v2`.** This standalone contract defines the
revised network language. It shares revision number 2, execution rules and
reference machinery with the object-domain language. Natural synonyms belong to
LLM interpretation; the controlled language exposes the exact operation and
meaning for human review. The logic engine resolves references and computes
answers. This release starts with a fresh database; previous syntax and saved
continuations are unsupported.

The three layers are elementary operations/questions, symbolic referential
macros, and domain-specific conceptual operations/questions. An elementary
operation can affect multiple fields atomically. Layer membership does not
change execution, reference or punctuation rules.

## 2. World, values and identity

The world is an 8×8 board, A1 bottom-left and H8 top-right. Coordinates are
locations; an object reference requires an identifier or explicit description.
At most one object occupies a square. Objects can be unplaced and can lack color.

Each object has an immutable nonnegative identifier, optional color, optional
position and four independent unary attributes: north, east, south and west.
A present port is open and an absent port is closed. Color values are `red`,
`blue`, `green`, `yellow`. There are no size, shape or orientation attributes.
Absence is known absence, not uncertainty or another color.

An exact **pattern** has four N/E/S/W slots. Each slot is its corresponding
letter or `-`: `ne--` opens north/east and closes south/west; `----` is a dot.
All 16 combinations are supported. There are no additive letter shorthands or
direction aliases. A **pattern** bundle includes all four port states; an
**appearance** bundle includes color and pattern, excluding identity/position.

Placed orthogonal neighbors are linked only when both facing ports are open.
Links are undirected. All arms of a cross meet at one junction. Dangling ports,
including ports facing outside the board, are permitted. Color does not determine
which links exist. A dot occupies its square even though it has no ports.

Only explicit creation, cloning, extension and connection construction allocate
identifiers. Allocation advances outside Undo history; deletion, Clear and Undo
never permit reuse for a different object. Aborted staged work can leave gaps.
A missing reference never allocates. All world updates enforce bounds and occupancy.

## 3. Lexical rules, scope and entries

Words are case-insensitive; rendered words are lowercase and coordinates uppercase.
Whitespace and line breaks separate words. Identifiers use `#0`, `#1`, etc.;
leading zeroes and negative identifiers are rejected. Signed offsets allow a
minus sign, but neither leading zeroes nor `-0`.

Every command requires a final period, even a single command. Every question
requires `?`. The entire entry is parsed and statically checked before execution.
A malformed entry changes neither world nor discourse state.

Descriptions, appearance values and offsets can omit redundant parentheses.
Conditions support `not`, `and`, `or`. Surface input has no implicit Boolean
precedence: meaningful scope ambiguity produces explicitly grouped choices
before any sentence executes. Associative chains of only `and` or only `or`
normalize directly. Explicit parentheses settle scope. Nested description,
graph and filter boundaries must also be grouped when ambiguous. Internal replay
uses a fully delimited canonical representation.

```ebnf
entry = "undo", "." | sentence, { sentence }
      | "atomically", "{", command, { command }, "}", "." ;
sentence = command | question ;
command = command-body, "." ;
question = question-body, "?" ;
object-condition = object-atom | "not", object-condition
                 | object-condition, "and", object-condition
                 | object-condition, "or", object-condition
                 | "(", object-condition, ")" ;
graph-condition = graph-atom | "not", graph-condition
                | graph-condition, "and", graph-condition
                | graph-condition, "or", graph-condition
                | "(", graph-condition, ")" ;
```

Ordinary sequences stop on failure and retain earlier completed sentences.
Each command is atomic. An `atomically { ... }.` batch commits all world/salience
updates together, or none. Questions and nested batches are excluded from batches.
A failed command adds no object mention. No-change operations continue normally.
Undo is exactly `Undo.` with optional surrounding whitespace and no suffix.

Ambiguity pauses at the affected operation. Staged batch state is provisional;
committed state stays unchanged until completion. Choices survive reload/restart.
One entry and all its clarification rounds form one Undo unit, restoring world
and salience. Chat is retained; allocation is not rolled back. Preview evaluates
without applying changes or persisting allocations. Acceptance checks state/version.

## 4. Layer 1: elementary operations and questions

In the following forms, R and T are object references, Q is a square expression,
C is a color, D a compass direction, P an exact pattern, and TARGET either one
object reference or a collection. Uppercase metavariables are not literal words.

| Command form | Contract |
| --- | --- |
| `Create object [with DESCRIPTION] on Q.` | Fresh identity at an unoccupied resolved square. |
| `Create object [with DESCRIPTION] off the board.` | Fresh unplaced object. |
| `Set color of TARGET to C.` | Set color; retain ports, identity and position. |
| `Clear color of TARGET.` | Clear color only. |
| `Open D port of TARGET.` | Add one port on each selected object. |
| `Close D port of TARGET.` | Remove one port; never repair the neighbor. |
| `Set pattern of TARGET to P.` | Replace all four port states. |
| `Clear pattern of TARGET.` | Set `----`; retain the objects. |
| `Move R to Q.` | Move an existing identity to a free square, or no change for its current square. |
| `Unplace TARGET.` | Clear position, retain identity and appearance. |
| `Exchange positions of R and T.` | Simultaneously exchange nullable positions. |
| `Delete TARGET.` | Delete selected identities. |
| `Delete every object.` | Delete placed and unplaced objects. |

DESCRIPTION lists `color C`, `pattern P`, or both in that order joined by `and`.
Each field appears at most once. Omitted fields mean no color and closed ports.
Named categories such as bend do not choose an orientation for creation. An
occupied creation destination fails without leaving an unplaced object.

| Question form | Answer |
| --- | --- |
| `Does #3 exist?` | False for a missing identity; no failed-reference diagnostic. |
| `Does R satisfy OBJECT-CONDITION?` | Boolean; missing R is a diagnostic, not false. |
| `Does Q satisfy SQUARE-CONDITION?` | Boolean without creating an occupant. |
| `Which object occupies Q?` | Identifier or `none`; no implicit object mention for the occupant. |
| `What is the ATTRIBUTE of R?` | Value, complete bundle, or `none`. |

ATTRIBUTE is `color`, `pattern`, `position`, `identifier`, `row`, `column`, or
`appearance`. A complete appearance is `color C-or-none, pattern P`. A pattern
query always returns four slots. Ordinary predicates include `color is C`,
`color is present/absent`, `D port is present/absent`, `pattern is P`,
`position is A4`, `position is present/absent`, `identifier is #3`, and `true`.

Square conditions include `occupied`, `true`, `row is 1`, `column is A`,
`at the edge`, `in a corner`, and `shading is light/dark`, with Boolean composition.
A8 is light and A1 dark; shading is independent of display shades and objects.

```text
Create object with color red and pattern ne-- on C4.
Open south port of it.
Does it satisfy north port is present and west port is absent?
What is the pattern of it?
Does D4 satisfy not occupied?
```

## 5. Layer 2: references and discourse

| Object reference | Resolution |
| --- | --- |
| `#3` | Existing identity; never a requested new identifier. |
| `it` | Most recent eligible object/square antecedent for the required type; ties require clarification. |
| `the object at Q` | Current occupant; an unoccupied square is a failed reference. |
| `the object with DESCRIPTION` | Compatible salient antecedent, then world fallback. |
| `the object matching OBJECT-CONDITION` | Anaphoric computed description with the same preference for compatible mentions. |
| `the unique object matching OBJECT-CONDITION` | World-wide selection without a salience preference; multiple matches require choice. |

A square expression is a literal A1–H8, `it`, or `the square D of BASE-REFERENCE`.
BASE-REFERENCE is an identifier, `it`, or an explicit occupant/simple description.
Computed references can be parenthesized to settle a nested reference boundary.
There are no indefinite object references or user-level bound variables.

Resolution always searches existing world/discourse referents. A graph filter
does not quietly restrict the world searched by a definite description. A
computed description can explicitly include a graph-dependent condition.

Salience records entry/utterance recency, a typed object/square referent, and mentioned properties.
Keep the current entry and previous three entries. A mention is an explicit
reference in a command or question; all operands of one sentence share recency.
Compatible facts can accumulate across mentions. For compound descriptions,
sum the best mention scores (`10 × entry age + utterance age`) and clarify when
scores differ by less than the number of required properties plus one. If no
eligible anaphoric evidence exists, use matching world objects.

Record only currently true facts. Purge false properties after changes, including
computed facts invalidated by changes to other nodes. Contextual facts retain
an explicit graph expression and grounded target identities; an old pronoun
is never resolved again under a new ranking. Being an endpoint in a blue graph
does not establish being an endpoint globally. Scoped views are recomputed
against the new world when their facts are rechecked.

Questions may change salience but never world facts. Aggregate results and
implicit intermediate route nodes do not become arbitrary antecedents.
Components, graph views, links and returned paths are not new `it` referents.
Explicit object operands such as a component seed or an object path endpoint receive
mentions. Square endpoints mention their locations; pre-existing occupants do not
become object antecedents implicitly. Newly created endpoint objects are introductions. Query failures add no successful mention.

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

## 6. Layer 3: collections, bundles and spatial transformations

Collections are `objects [R, T, ...]`, `objects at [Q, Q, ...]`,
`objects matching OBJECT-CONDITION`, or `objects in GRAPH`.
Explicit lists require square brackets. Duplicate resolved identities fail.
Matching collections can be empty; graph collections contain placed members only.
Selections and source values are frozen before updates within one operation.

| Command form | Contract |
| --- | --- |
| `Copy COMPONENT from R to T.` | Copy the captured nullable value/bundle. |
| `Transfer COMPONENT from R to T.` | Copy, then clear the source component atomically. |
| `Exchange COMPONENT of R and T.` | Exchange pre-operation values atomically. |
| `Clone appearance of R into a new object CREATION-SITE.` | Fresh identity with complete source appearance. |
| `Set appearance of TARGET to color C-or-none, pattern P.` | Replace complete appearance, including color absence. |
| `Clear appearance of TARGET.` | Clear color and all ports; keep identities/positions. |
| `Step R D.` | Exactly one square; source must be placed. |
| `Move R next to T.` | Choose a free orthogonal neighbor N/E/S/W; multiple choices ask. |
| `Shift positions of COLLECTION by east INTEGER, north INTEGER.` | Simultaneously shift all placed selections. |
| `Rearrange positions by [R to Q, ...].` | Simultaneous unique destination mapping. |
| `Permute appearance by [R to T, ...].` | Closed permutation of captured bundles among the same identities. |

COMPONENT is `color`, `pattern`, `appearance`, or `D port`. Copying a closed port
closes the destination port. Transferring pattern leaves a dot; transferring
appearance leaves a colorless dot. Self-copy/transfer/exchange makes no change.

Rotation angles are `90 degrees clockwise`, `180 degrees`, and
`90 degrees counterclockwise`. Reflection axes are `vertical` (exchange E/W)
and `horizontal` (exchange N/S). Geometric pivots are
`the center of rectangle A1 to H8`, with bottom-left then top-right coordinates.
Use exact half-cell arithmetic; reject results not landing on board cell centers.

| Transformation | Canonical command family |
| --- | --- |
| Ports only | `Rotate ports of TARGET by ANGLE.` / `Reflect ports of TARGET across AXIS.` |
| Positions only | `Rotate positions of COLLECTION by ANGLE about PIVOT.` / `Reflect positions of COLLECTION across AXIS through PIVOT.` |
| Appearance permutation | The same forms with `appearance` instead of `positions`. |
| Whole drawing | The same forms with `drawing` instead of `positions`. |

Ports-only operations retain identity, position and color, including for unplaced
objects. Positions-only operations carry identities and unchanged port states.
Appearance transforms keep identities/positions fixed and require the transformed
square set to equal the selected occupied square set. Drawing transforms move
identities and transform each object's ports simultaneously, retaining color.
Outside objects are never moved or repaired. Occupancy/boundary failure rolls
back the whole operation. Empty geometric selections fail; empty ordinary bulk
updates report no matching objects.

## 7. Network construction

| Command | Exact effects |
| --- | --- |
| `Link R to T.` | Placed orthogonal neighbors: open both facing ports, create nothing. |
| `Unlink R from T.` | Same operand requirements: close both facing ports, including a one-sided stub. |
| `Extend R D.` | Create a neighbor on an empty in-board square and link it; inherit source color including absence. |
| `Close unmatched ports of TARGET.` | Freeze unmatched ports, close only those on the selected placed objects. |
| `Build shortest connection from ENDPOINT to ENDPOINT [with route color C].` | Plan and apply the shortest permitted route atomically. |

A construction ENDPOINT is either a square expression or an existing placed
object reference. A bare endpoint `it` permits either kind, resolving by recency
and clarifying ties; mixed endpoints are supported. Square endpoints permit object
creation there as an explicit macro effect. This does not make coordinates
implicit object references in other operations.

Search minimizes route steps, using N/E/S/W discovery order for equal-length
routes. Empty squares are available for construction. Existing intermediate
objects must already have the incoming/outgoing ports required by the route.
The source and target may gain required ports, preserving all previously open
ports. These endpoint permissions participate in search. New route objects have
exactly their required route ports and fresh identifiers. Existing identities
and positions survive; intermediate port patterns never change.

Without route color, existing colors survive and new nodes are colorless.
With route color, **all route nodes are recolored**, including existing endpoints
and intermediate objects with other colors. Color does not restrict construction
search. The operation does not promise minimal edits or an exclusive/acyclic route.

No route means no creation, port edits or recoloring. A same-square route has
zero steps, opens no ports, and creates a dot if unoccupied; requested route color
still applies. Only explicit endpoints receive salience mentions, not implicit
intermediates. Ordinary link/unlink never invoke path construction.

```text
Create object with color green and pattern ---- on A1.
Build shortest connection from it to D1 with route color blue.
Build shortest connection from D1 to D4 with route color blue.
What is the distance from the object at A1 to the object at D4?
```

## 8. Graph expressions and predicates

All graph values are computed from a frozen world snapshot. They do not allocate
objects or modify ports. Prefix constructors expose their evaluation order:

```ebnf
graph = "the network"
      | "the component of", reference, [ "within", graph ]
      | "the subgraph of", graph, "induced by objects matching", object-condition
      | "(", graph, ")" ;
```

The whole graph contains placed objects. A component seed must be placed and
belong to its input graph; otherwise return a diagnostic. A component without
`within` uses the whole network. An induced subgraph keeps **all** qualifying
input nodes and every existing input link between them. It may be empty or
have many components; never choose one component implicitly.

Induction evaluates the selector once on the input graph. Unqualified graph-role
predicates in that selector use that input graph. Elsewhere their default context
is the whole network; `within GRAPH` supplies an explicit context. Do not filter
to a fixed point or let a selector refer implicitly to the output it is defining.
Resolve explicit reference operands eagerly, even in Boolean branches or empty
selections. Symbolic object resolution retains its ordinary global/discourse rules.

| Object predicate | Meaning |
| --- | --- |
| `dot`, `tip`, `straight`, `bend`, `tee`, `cross` | Intrinsic ports: zero; one; two opposite; two adjacent; three; four. Unscoped intrinsic checks include unplaced objects. |
| `isolated [within GRAPH]` | Placed member with degree zero. |
| `endpoint [within GRAPH]` | Degree one; distinct from a tip. |
| `junction [within GRAPH]` | Degree three or four. |
| `unmatched [within GRAPH]` | Has an open port without a reciprocal neighbor in that graph. |
| `on a cycle [within GRAPH]` | Belongs to a simple cycle; not merely a cyclic component. |
| `articulation [within GRAPH]` | Removing this member and incident links would increase component count. |
| `linked to R [within GRAPH]` | Direct reciprocal link. |
| `connected to R [within GRAPH]` | Reachability, including a placed member's length-zero path to itself. |

Explicitly scoped intrinsic checks also require membership in their specified
graph. Graph-role and relation checks are false for excluded/unplaced objects;
missing object references remain diagnostics. Additional shared object predicates
are `same object as R`, `next to R`, `one square D of R`, `at the edge`,
`in a corner`, `row is N`, `column is A`, and `on a square matching SQUARE-CONDITION`.
Attribute comparison uses `COMPONENT equals that of R` or
`COMPONENT shares a present value with R` where supported: color, individual ports,
pattern, position, row and column. Equality of absent colors/positions differs
from sharing a present value; a complete pattern is always present.

| Graph predicate | Meaning |
| --- | --- |
| `connected` | Nonempty and exactly one component. |
| `tree` | Nonempty, connected and acyclic. |
| `forest` | Acyclic, possibly disconnected. |
| `cyclic` | Contains a simple cycle. |
| `monochromatic` | Nonempty; every member has the same present color. |
| `monochromatic with color C` | Every member has this particular present color; nonempty. |
| `properly colored` | Every member has a color; every link joins different colors. |

These predicates apply uniformly to arbitrary graph expressions. Empty graphs
satisfy forest and properly colored, and fail connected, tree, cyclic and
monochromatic. A colorless singleton is a tree/forest but is neither monochromatic
nor properly colored. Reciprocal links are counted once. Analysis of hypothetical
removal for bridge/articulation predicates never changes the world.

A computed link reference is `the link between R and T [within GRAPH]`.
Both endpoints must resolve, and an actual reciprocal link must exist in the
selected graph. `bridge` means removing it would increase component count. A
nonexistent link is a failed link reference, not an existing non-bridge.

### Three different blue-component questions

```text
Does the component of #11 satisfy tree and monochromatic with color blue?
Does the component of #11 within the subgraph of the network induced by objects matching color is blue satisfy tree?
Does the subgraph of the component of #11 induced by objects matching color is blue satisfy tree?
```

The first checks the entire original component. The second finds only the blue
region containing #11, requiring #11 to be blue. The third finds the original
component first, then retains **all** its blue objects, even in disconnected
regions; #11 need not be blue or survive filtering. Distinct readings remain
distinct even when answers or pictures currently coincide. Interpretation must
ask when the user's intended graph construction is unspecified.

## 9. Derived questions, selection and quantification

| Question family | Result |
| --- | --- |
| `Does GRAPH satisfy GRAPH-CONDITION?` | Boolean about exactly that constructed graph. |
| `Does the link between R and T [within GRAPH] satisfy LINK-CONDITION?` | Boolean bridge check, including Boolean compositions. |
| `What is the degree of R [within GRAPH]?` | Reciprocal neighbor count; requires placed membership. |
| `What is the distance from R to T [within GRAPH]?` | Shortest existing-path length, or `no path`. |
| `What is a shortest path from R to T [within GRAPH]?` | Ordered object identifiers, or `no path`; deterministic N/E/S/W ties. |
| `How many components in GRAPH?` | Number of connected components. |
| `How many links in GRAPH?` | Number of undirected reciprocal links. |
| `How many objects in GRAPH?` | Member count. |
| `Which objects match OBJECT-CONDITION?` | Sorted matching identifiers. |
| `How many objects match OBJECT-CONDITION?` | Matching count. |
| `Which squares match SQUARE-CONDITION?` | Matching board coordinates. |
| `How many squares match SQUARE-CONDITION?` | Matching count. |
| `Does every object matching P satisfy Q?` | Universal check over P's matches. |
| `Does some object matching P satisfy Q?` | Existential check over P's matches. |

Every/some also accept `square` and square conditions. There is one explicit
quantifier per question; no nested quantifiers or indefinite relational targets.
Domain graph algorithms provide their own precise derived predicates without
adding user-level bound-object syntax. An empty restriction makes every true
and some false, with an explanation. Object matching includes unplaced objects;
graph collections do not. `not isolated` consequently includes unplaced objects;
use `position is present and not isolated` for placed non-isolated objects.

Distance/path operands must be placed; excluded endpoints yield no qualifying
path, whereas an unplaced operand produces a diagnostic. Colored paths are
ordinary paths in an induced graph: both endpoints and all intermediates must
satisfy the filter. They never recolor objects. Two red nodes connected only
through blue nodes are globally connected but not connected in the red graph.

```text
Does #3 satisfy connected to #4 within the subgraph of the network induced by objects matching color is red?
What is the distance from #3 to #4 within the subgraph of the network induced by objects matching color is red?
How many components in the subgraph of the network induced by objects matching color is blue?
Which objects match articulation?
Does every object matching color is red satisfy connected to #3?
```

## 10. Review and implementation boundary

Graph checks and graph counts report the exact evaluated member identifiers
before their answer. Review exposes resolved identities, graph construction order, selected members,
new objects, endpoint port additions and every overwritten route color.
References remain symbolic until Haskell resolves them. Queries return symbolic
answers; the LLM cannot substitute a guessed truth value or weaker questions.
Preview/acceptance and all clarification rounds use compatible state and version.

Graph expressions, references, selectors and captured bundles are frozen per
operation. Later sentences intentionally see earlier successful effects. The
shared pure execution core is `ControlledLanguage`; domain wrappers are
`Domains.Network.Language` and `Domains.Objects.Language`. Network port/graph
algorithms stay in the network domain library. FastAPI persists execution state;
Flutter renders it. Neither decides graph semantics or reference resolution.

Cycles and structural/color-aware predicates are part of this v2 contract.
Stored path entities, general first-order binding, arbitrary path optimization
objectives and implicit topology repair are excluded. Changes to grammar and
semantics must be versioned together and receive explicit review.
