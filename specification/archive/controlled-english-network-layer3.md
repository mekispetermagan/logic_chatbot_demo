> Archived pre-v2 language. Current contract: [Network v2](../network-language-v2.md).

# Controlled English: Network Domain, Layer 3

Status: implemented. This document describes the supported network Layer 3 syntax and evaluation.

Reference: the archived object domain's "Controlled English: Layer 3" specification,
[controlled-english-layer3.md](controlled-english-layer3.md). Retain its reference resolution,
movement, clarification, salience, undo, and restricted quantification rules
except for the explicit extensions below. The object domain now uses
[Objects v2](../object-language-v2.md); that revision does not change network syntax.

## Domain assumptions

- The board has 64 squares, A1 through H8. North/up increases the row number;
  east/right increases the column.
- Each object has four independent Boolean ports: north, east, south, and west.
  Their combinations give 16 patterns.
- A square may contain no object. This is distinct from an object with no ports,
  rendered as a dot. A dot occupies its square and may have a color.
- Adjacent objects are linked only when their facing ports are both open.
  Connections are undirected. At a cross, all four arms meet at one junction.
- Unmatched ports are permitted, including ports facing outside the board.
- Color is optional and does not determine whether a connection exists.
- The graph contains only placed objects. Unplaced objects retain their port
  patterns and colors, but do not participate in graph relations or components.

These rules make port patterns independent of the
connections that happen to exist in the current world.

## Defined vocabulary

### Intrinsic port patterns

| Term | Definition | Number of patterns |
|---|---|---:|
| {dot\|empty} | No ports | 1 |
| tip          | Exactly one port | 4 |
| straight     | Exactly two opposite ports | 2 |
| bend         | Exactly two perpendicular ports | 4 |
| tee          | Exactly three ports | 4 |
| cross        | All four ports | 1 |

These properties depend only on the object's port values, including for an
unplaced object. 

Each nonempty port pattern can also be referenced with shorthands made of the first letters of its ports:
| Term | Definition |
|---|---:|
| {nesw\|urdl} | north east south west |
| {esw\|rdl}   | east south west |
| {nsw\|udl}   | north south west |
| {new\|url}   | north east west |
| {nes\|urd}   | north east south |
| {sw\|dl}     | south west |
| {ew\|rl}     | east west |
| {es\|rd}     | east south |
| {nw\|ul}     | north west |
| {ns\|ud}     | north south |
| {ne\|ur}     | north east |
| {w\|l}       | west |
| {s\|d}       | south |
| {e\|r}       | east |
| {n\|u}       | north |



### Graph properties and relations

In the following table, S is an existing-object reference: an identifier,
coordinate, pronoun, or definite description, as in the current domain.

| Term | Definition |
|---|---|
| isolated | Has no actual connections |
| endpoint / dead end | Has exactly one actual connection |
| junction | Has three or four actual connections |
| unmatched | Has at least one open port without a reciprocal neighbor |
| linked to S | Has a direct connection to S through matching ports |
| connected to S | Is reachable from S through actual connections |
| distance to S | The length of a shortest path to S, measured in connections |

A tip can be isolated. An endpoint can have additional unmatched ports. The
intrinsic pattern and the actual graph role must therefore remain distinct.

Every placed isolated object is a component of its own, including a dot. A
length-zero path connects a placed object to itself, with distance zero.
Unreachable pairs return "no path" for distance queries.

Graph predicates return false for unplaced objects. Numeric graph queries
requiring an unplaced reference report that the object is not on the board.
Missing object references remain diagnostics, not false answers.

### Colored paths

- A red path contains only red nodes, including both endpoints. The same rule
  applies to other supported colors.
- Uncolored nodes do not satisfy a named-color path condition.
- Colors constrain which paths qualify; they do not change the underlying graph.

Paths and components are computed structures. The language does not introduce
stored path objects or pronoun references to paths.

## Descriptions and grammar extensions

Allow the intrinsic pattern names and named unary graph properties in
descriptions, alongside colors. Examples: "the red bend", "the blue endpoint",
and "the unmatched cross". Descriptors remain conjunctive; a definite
description must resolve uniquely or request clarification.

Use the new graph relations as predicates in ordinary and quantified questions.
Retain the current distinction between descriptions and predicate clauses.

Keep the existing every/some restrictions:

- Subject descriptions are nonempty.
- Quantifier boundaries use the existing object/objects or is/are forms.
- Predicate clauses may be joined with explicit "and".
- Relational targets are explicit existing-object references.
- No "or", nested quantification, or indefinite object targets such as
  "connected to a red object".
- Predicate conjunctions remain restricted to quantified questions.

Generalize counting so that descriptors can be combined with the same
fixed-reference graph predicates. For example: "How many red objects are
connected to A4?"

The colored-path condition in "connected to S by a red path" is a defined
relation predicate; it does not introduce general quantification over paths.

## Performatives

S and S' are existing-object references unless a form explicitly accepts empty
square endpoints. In `connect`, coordinates denote squares whether occupied or empty.

| Example | Operation |
|---|---|
| "Rotate A4 clockwise." | Rotate its port pattern 90 degrees clockwise, keeping its position and color |
| "Rotate A4 counterclockwise." | Rotate its port pattern 90 degrees counterclockwise |
| "Flip A4 horizontally." | Exchange east and west ports |
| "Flip A4 vertically." | Exchange north and south ports |
| "Make A4 the same [pattern] as B5." | Copy all four port values from B5 to A4 |
| "{Link\|extend} A4 right." | Open the two facing ports between adjacent existing objects, create new object if needed |
| "Disconnect A4 right." | Close both facing ports between adjacent existing objects, close port if no object to disconnect from |
| "Remove unmatched ports from A4." | Close only A4's unmatched ports |
| "Color the component of A4 red." | Recolor every object in A4's current component |
| "Connect A4 to H8." | Build a shortest allowed path, creating colorless nodes on empty squares |
| "Connect the red tip to H8 with blue." | Build the same path and color every route node blue |

Extension also accepts east, south, and west. The new object has only its port
toward the source open and inherits the source's color, including absence of
color. The source gains the corresponding outward port while retaining its
other ports.

Rotation, reflection, pattern copying, and unmatched-port removal affect only
the selected object's port values. They do not modify neighboring objects to
repair any resulting mismatches.

Pairwise link and disconnect require adjacent placed objects. They change only the
two facing ports, preserving all other ports and attributes. A nonadjacent
target does not trigger path construction. Repeating either operation is
idempotent.

Directional link/extend uses the adjacent object when occupied and creates one when empty.
Out-of-board link destinations leave the world unchanged. Disconnecting an
outward-facing port closes it, just as when an in-board neighbor is absent.

Component coloring determines membership before applying the color changes.
An isolated object's component contains only that object.

Resolve all object operands before mutation. Each performative affecting more
than one object is atomic: failure or pending clarification leaves that
utterance's changes unapplied. Earlier completed utterances in the entry remain
applied, following the current continuation rules. One Undo restores the entire
pre-entry world and salience, including an entry containing a pending choice.

## Questions

| Purpose | Examples |
|---|---|
| Pattern or graph role | "Is A4 a bend?"; "Is A4 isolated?"; "Is the red bend an endpoint?" |
| Direct connection | "Is A4 linked to A5?" |
| Reachability | "Is A4 connected to H8?" |
| Port consistency | "Does A4 have an unmatched port?" |
| Actual degree | "How many connections does A4 have?" |
| Shortest-path distance | "Distance A4 to H8?"; "Distance from A4 to H8?"; "What is the distance from A4 to H8?" |
| Colored reachability | "Is A4 connected to H8 by a red path?" |
| Property counting | "How many red endpoints?" |
| Relational counting | "How many objects are connected to A4?"; "How many red objects are connected to A4?" |
| Component counting | "How many components?" |
| Universal question | "Is every red object connected to A4 and unmatched?" |
| Existential question | "Are some blue objects unmatched?" |

Pattern counts include matching unplaced objects, following the current
descriptor-counting convention. Counts involving graph properties or graph
relations include placed objects only. The empty board has zero components.

Retain the current semantics of every/some: an empty subject class makes every
true and some false, with explanatory feedback. Aggregate questions do not
introduce individual-object antecedents; explicit reference targets still
receive mentions.

## Deferred features

- Monochromatic paths have a proposed meaning above, but an exact surface form
  for asking about them has not yet been selected.
- Cycles and cycle membership are deferred.


## Pattern attribution and creation

Positive shorthand is additive: `A4 ne.` opens north and east while preserving
south and west. In descriptions/checks, `ne` requires north and east, without
restricting other ports. Letters follow N/E/S/W order; U/R/D/L are aliases.

Exact patterns have four slots, always north/east/south/west: `A4 ne--.` sets
north/east and clears south/west; `A4 ----.` clears all ports. `ur--` is an alias
for `ne--`. Color, identity and position remain unchanged.

Named categories (`bend`, `endpoint`, etc.) are computed descriptors and checks,
not assignments. `The red bend is blue.` is allowed; `a bend on A4.` is rejected
because no orientation is specified. Explicit creation is supported:
`a ne-- on A4.` or `a ---- on A4.`. Existing Layer 1/2 color and port forms remain
available. Computed facts are rechecked against the current world before
reference resolution and removed from salience when false. Positive shorthand
mentions expand into their individual ports; exact patterns also retain their
absence constraints.

## Syntax reference

S and T denote identifiers (`#3`), coordinates, `it`, or definite descriptions.
Questions require `?`. Performatives require `.` between utterances; the final
period in an entry is optional. Parsing is case insensitive.

| Form | Notes |
|---|---|
| `rotate S clockwise.` / `rotate S counterclockwise.` | One quarter turn |
| `flip S horizontally.` / `flip S vertically.` | Swap E/W or N/S |
| `make S [the] same [pattern] as T.` | Copies absence as well as presence |
| `link S D.` / `extend S D.` | D: north/east/south/west or up/right/down/left |
| `disconnect S D.` | Closes both facing ports, or only source when neighbor absent |
| `link S to T.` / `extend S to T.` | Requires adjacent placed operands |
| `disconnect S from T.` | Requires adjacent placed operands |
| `connect S to T [with COLOR].` | Shortest allowed path; empty-square endpoints accepted |
| `clear {the world\|everything\|all}.` | Deletes all placed/unplaced objects and purges salience; whole-entry Undo restores both |
| `remove unmatched ports from S.` | Source only |
| `color the component of S red.` | Any supported color |
| `[is] S endpoint?` | Also intrinsic categories, unary graph roles and patterns |
| `[is] [the] square COORD {occupied\|taken}?` | Core square occupancy check, including no-port nodes |
| `[is] S linked to T?` / `[is] S connected to T?` | Existing explicit target |
| `[is] S connected to T by a red path?` | Any supported color |
| `[does] S have an unmatched port?` | Equivalent to unmatched check |
| `how many connections does S have?` | Actual reciprocal degree |
| `distance [from] S to T?` / `what is the distance from S to T?` | Shortest existing path, or no path; canonical form: `distance S to T?` |
| `how many components?` | Placed graph only |
| `how many red endpoints?` | Plural category aliases accepted |
| `how many red objects are connected to T?` | Fixed-reference predicate filtering |

Inherited movement, attribute copying, spatial questions, square counts and
every/some questions remain available with network descriptors. Multiple
predicates require explicit `and` and are limited to aggregate questions.
Ordinary checks accept a single property or defined pattern. Indefinite targets,
nested quantifiers, disjunction, user-specified routes and cycles are unsupported.


## Shortest connection construction

`Connect S to T [with COLOR].` accepts identifiers, `it`, definite descriptions,
and coordinates. Coordinates may be empty; other references must resolve to
existing placed objects. All references resolve before any creation or coloring.
Ambiguity pauses the utterance, and clarification resumes it atomically.

The planner temporarily treats empty squares as four-port nodes. A move is
allowed only when both facing ports are open: existing nodes must already have
the required ports. Breadth-first search chooses a shortest route by number of
steps. Equal-length routes follow discovery order, considering north, east,
south, west at each expansion. A predecessor map reconstructs the chosen route.

Only empty squares on that route receive real nodes, with fresh identifiers and
exactly the ports needed for the preceding/following steps. Existing nodes retain
their identities, positions and ports. Without `with COLOR`, new nodes are
colorless and all existing attributes are preserved. With it, every route node,
including existing nodes and endpoints, receives that color. Unplaced and
off-route objects are unaffected. Colors do not influence route selection.

If no route exists, feedback says `No path` and the world remains unchanged,
including colors. Unplaced references receive a diagnostic. Connecting a square
to itself has length zero: an empty square receives a dot; an existing node
remains as it is unless a color was requested. Repeating a completed connection
without a color change makes no world change.

Endpoints receive salience mentions; implicit intermediate nodes do not.
One Undo restores the entire pre-entry world and salience. Connection building
does not change existing reachability or distance-question meanings: those
questions still inspect actual current connections. `link` may alter existing
ports; `connect` never does.
