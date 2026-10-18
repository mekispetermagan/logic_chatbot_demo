# Network Language Revision Plan

## Historical implementation plan

**Implemented.** The standalone [Network v2](network-language-v2.md) contract supersedes this planning record. Both domains now use v2; legacy databases and continuations are discontinued, with no migration. The final grammar and tests settle the decisions listed below.

## Original scope

This planning record explains the implemented revision. It applies the [controlled-language manifesto](controlled-language-manifesto.md)
and the lessons of [Objects v2](object-language-v2.md) to the network domain.
The implemented release uses `objects-v2` and `network-v2`. Object-language
semantics remain the revised explicit language; network adds the toolkit below.
The complete contracts are [Objects v2](object-language-v2.md) and
[Network v2](network-language-v2.md). Old network documentation is archived.

Legacy pending entries and proposals are not resumed or migrated. The demo
starts from a fresh SQLite database. Previously saved grammar is never silently
reinterpreted as v2.

## 1. Shared language and execution commitments

Adopt the Objects v2 commitments where their semantics are shared:

- Imperative commands, each ending in `.`, and questions ending in `?`.
- One canonical vocabulary; natural synonyms belong to LLM interpretation.
- A coordinate denotes a square. `the object at A4` denotes its occupant.
- Explicit creation; failed references and updates never create objects.
- Stable identity, with allocation state outside Undo history.
- Complete-entry parsing before evaluation; stop-on-failure sequences.
- Individually atomic conceptual operations and explicit atomic batches.
- Frozen operands, selections and source values within one operation.
- World **and salience** history; one entry and its continuations form one Undo unit.
- Readable surface syntax without redundant parentheses. Genuine grouping
  ambiguity produces explicitly parenthesized choices before execution.
- LLM proposals require review. Symbolic reference resolution stays in Haskell.

Visual editing can retain its convenient create-or-update behavior as an explicit
editor action. Its contract must remain separate from strict language updates.

## 2. Layer 1: exact operations on stored state

Use `object` consistently with the shared ontology; the interpreter can translate
natural references to nodes. Color is nullable. A port is present or absent,
with no unknown state. A complete pattern specifies all four port states.

| Meaning | Proposed form | Required distinction |
| --- | --- | --- |
| Explicit creation | `Create object with color red and pattern ne-- on C4.` | Fresh identity; occupied destination fails without leaving an object |
| Create a dot | `Create object with pattern ---- on C4.` | A no-port object exists and occupies C4 |
| Set/clear color | `Set color of #3 to blue.` / `Clear color of #3.` | Preserve identity, position and ports |
| Add/remove one port | `Open north port of #3.` / `Close north port of #3.` | Affect only the named object's port; no neighbor repair |
| Replace all ports | `Set pattern of #3 to ne--.` | Clear south/west as well as opening north/east |
| Move/unplace/delete | Objects v2 operation forms | Distinguish location change, absent position and nonexistence |
| Exchange positions | `Exchange positions of #3 and #4.` | Atomic identity-preserving movement |

Retain a single exact N/E/S/W four-slot pattern notation. Remove additive letter
shorthand such as `ne`; its meaning remains expressible through explicit port
operations and presence predicates. Remove U/R/D/L aliases from executable input.

Define **pattern** as all four port states and **appearance** as color plus
pattern, excluding identity and position. Give copy, transfer, exchange and clone
their Objects v2 meanings for the supported components. Copy includes absence;
transfer also clears the source component. Clearing a pattern yields a dot,
not a deleted object. A complete appearance literal must specify nullable color
and an exact pattern; there is no separate absent-pattern state.
Omitted creation fields mean absent color and closed ports. Reject contradictory
simultaneous initial assignments rather than choosing an implementation order.
Named categories such as bend do not specify an orientation for creation; the
interpreter must obtain or explicitly propose an exact pattern.

Queries and predicates distinguish identity existence, occupancy, color presence,
port presence and exact pattern equality. Use `occupied`/`not occupied` for
squares and `dot` for a no-port object; drop `empty` as a node synonym.

### Core questions

Questions are part of every applicable layer, not a separate afterthought.
Retain the shared check/query/selection/count/every/some wrappers and add typed
network predicates and value queries to them.

| Purpose | Proposed question |
| --- | --- |
| Identity existence | `Does #3 exist?` |
| Occupancy | `Does C4 satisfy occupied?` |
| Vacancy | `Does C4 satisfy not occupied?` |
| Occupant identity | `Which object occupies C4?` |
| Color value/presence | `What is the color of #3?` / `Does #3 satisfy color is present?` |
| Port presence/absence | `Does #3 satisfy north port is present?` / `Does #3 satisfy west port is absent?` |
| Exact pattern | `What is the pattern of #3?` / `Does #3 satisfy pattern is ne--?` |
| Shared attribute state | `Does #3 satisfy color equals that of #4?` |
| Shared present color | `Does #3 satisfy color shares a present value with #4?` |
| Position/appearance | `What is the position of #3?` / `What is the appearance of #3?` |
| Identity/coordinates | `What is the identifier of it?` / `What is the row of #3?` / `What is the column of #3?` |

Color absence returns `none`, not an unknown value. Exact pattern queries always
return all four slots, including `----` for a dot. Equality of absent colors is
distinct from sharing a present color.

## 3. Layer 2: symbolic references

Reuse identifiers, `it`, explicit occupants, anaphoric descriptions and globally
unique computed descriptions. Retain the current salience window and ambiguity
policy. No resolution path allocates an object.

Descriptions must distinguish an exact pattern from a list of required ports.
Requiring north and east permits additional ports; requiring `ne--` does not.
Computed descriptions can use intrinsic categories and graph roles through
explicit predicate vocabulary, rather than an expanding list of aliases.

Preserve intrinsic/relational distinctions: a **tip** has one port, whereas an
**endpoint** has one actual reciprocal connection. A dot and a node with several
unmatched ports may both be isolated. Unplaced objects can satisfy intrinsic
conditions but do not participate in the placed graph.

Recheck computed mentions against the current world. Changing a port or moving
one object can invalidate graph-role mentions about other objects, so purging
must account for dependencies beyond the directly edited object.
Keep a computed mention's graph context: being an endpoint in a blue-induced
graph does not establish being an endpoint in the full graph. Ground referenced
objects when recording such mentions; do not later reinterpret an old `it`
against a new ranking. The final contract must specify this representation and
its dependency-aware truth check before adding contextual anaphoric descriptors.

## 4. Layer 3: a precise network toolkit

### Separate mutation contracts

| Operation | Proposed contract |
| --- | --- |
| Link existing objects | Both operands must be placed orthogonal neighbors. Open their two facing ports; create nothing. |
| Unlink existing objects | Both operands must be placed orthogonal neighbors. Close their two facing ports; preserve other attributes. Missing operands fail; already closed ports give no change. |
| Extend toward an empty square | Explicitly create the adjacent object and link it. Require an empty in-board destination; copy the source's current color, including absence, into the new object. |
| Close one port | Layer 1 operation; does not close the neighbor's corresponding port. |
| Trim unmatched ports | Determine unmatched ports first, then close only those on the selected object. |
| Build a shortest connection | Adapt the current planner to allow opening required source/target ports, while preserving intermediate objects' ports; retain explicit square/object endpoints and route-wide coloring semantics. |

Do not preserve the current conditional `link/extend` alias, which sometimes
updates an existing neighbor and sometimes creates one. Separate those effects.
Use **link/unlink** for direct connections. Do not use `disconnect` as an alias:
unlinking one edge need not destroy reachability through other paths.
Pairwise unlinking does not require both facing ports to be open: it also closes
a one-sided facing port. This differs from referring to a computed link for a
bridge question, which requires an actual reciprocal link.

Shortest-connection construction finds the shortest route under these permissions:

- At the **source and target**, the algorithm may open the ports required by
  the chosen route. Preserve every previously open port; never replace their
  entire patterns or close an existing port.
- An existing **intermediate object** must already have the required incoming
  and outgoing ports. Its port pattern cannot be modified.
- Empty route squares receive new objects with exactly the required route ports.
  Existing objects keep their identities and positions.

Endpoint permissions participate in the search itself, so closed endpoint ports
do not prevent finding a route. Retain shortest step count and deterministic
N/E/S/W tie-breaking. This supports incremental drawing: a later connection can
open another port on an earlier endpoint, forming a turn or branch while keeping
the previous connection intact.

Without coloring, new objects are colorless and existing colors survive. An
explicit route-color option recolors **every** route object, including existing
endpoints. Plan and apply the operation atomically: no route means no changes,
including no prematurely opened ports or color changes. A same-square connection
has zero steps and requires no ports; create a dot if the square is unoccupied.
Object references must be placed; square endpoints may be unoccupied.
Adapt allocation to the persisted counter; do not use current-world maximum IDs.
The builder explicitly accepts either endpoint type, including mixed types.
A square endpoint names a location and permits creation there as part of this
macro's declared effect; an object endpoint resolves an existing identity first.
This permission does not extend to ordinary object-reference resolution.

Coloring remains more permissive than changing intermediate port patterns:
existing differently colored endpoints and intermediate objects may be recolored
by the explicit route-color option. Wrong color is not a construction failure
and does not restrict search. Colored-path **questions**, by contrast, inspect a
color-filtered graph without recoloring anything. Preview must list old/new
colors even for preexisting intermediate objects.

The optimization objective is link-step count, not the number of new objects,
recolorings or port edits. Do not claim a minimum-change or unique-route
guarantee. A construction may create a cycle or reuse part of an existing one;
its guarantee is a qualifying connection, not that the result is a tree.

### Distinguish transformations

- **Rotate/reflect ports:** change the selected object's directional attributes
  in place. Name angles and reflection axes explicitly.
- **Transform positions:** move identities with their colors and port states;
  do not silently rotate ports.
- **Permute appearance:** keep identities/positions fixed while transferring
  color and pattern bundles.

A geometric rotation of a complete network drawing may require both position
and port transformations. Decide whether it warrants a dedicated atomic macro
or an explicit composition; do not hide it under an underspecified `rotate`.
Neighboring ports are never repaired implicitly after a transformation.

Represent components as computed collections. Component coloring can then use
an ordinary collection update with membership frozen before mutation.

### Retain and strengthen the graph vocabulary

The following existing ideas remain first-class features. Their meanings must
be available wherever the corresponding predicate or collection type is allowed.

| Concept | Contract |
| --- | --- |
| Intrinsic categories | Dot, tip, straight, bend, tee and cross describe ports, independently of reciprocal neighbors. |
| Graph roles | Isolated, endpoint and junction describe actual degree; unmatched describes an open port lacking a reciprocal neighbor. |
| Direct linkage | Two placed neighbors with both facing ports open; distinct from mere grid adjacency. |
| Reachability | A path of existing reciprocal links; distinct from a path that could be constructed. |
| Degree and distance | Actual incident-link count and shortest existing-path length. |
| Components | Maximal connected collections of placed objects, including singleton isolated objects. |
| Colored reachability | Restrict every path node, including endpoints, to the selected color. |
| Graph-guided editing | Frozen component selection for recoloring; pattern transformation, copying and unmatched-port trimming. |

Propose these additional concepts for the v2 contract, with explicit definitions
and small algorithms. They provide useful inspection and editing selectors,
rather than alternative spellings of existing operations:

| New concept | Precise meaning and use |
| --- | --- |
| Cycle membership | An object lies on a simple cycle of actual links. Distinguish this from merely belonging to a component containing a cycle. |
| Acyclic/tree component | A component is a tree exactly when it has no cycle. A singleton is a tree; the empty graph is not one tree. |
| Forest | The placed graph is acyclic, possibly with multiple components; the empty graph is a forest. |
| Connected network | The nonempty placed graph has exactly one component; distinguish this global property from reachability between two references. |
| Bridge link | Removing an existing link would increase the component count. Identify it by its two endpoint identities. |
| Articulation object | Removing the object and its incident links would increase the component count. This is a query, not a deletion. |
| Component size/link count | Return the number of objects and reciprocal links, counting each undirected link once. |
| Representative shortest path | Return an ordered list of existing object identities, with deterministic N/E/S/W tie-breaking. |

Cycle, bridge and articulation tests inspect derived structure without modifying
the world. Components, links and paths remain computed values/collections,
not persistent entities with freshly allocated identifiers. A graph-theoretic
link is the reciprocal relation, not either individual port in isolation.

Useful commands then compose existing updates with these concepts, for example:

- `Set color of objects in the component of #3 to blue.`
- `Set color of objects matching articulation to red.`
- `Close unmatched ports of objects in the component of #3.`

The last form trims only unmatched ports; it does not remove every connection.
Graph-derived selections are captured once before any updates. Add dedicated
topology-changing macros only for distinct, approved contracts; do not silently
cut bridges or delete objects while answering structural questions.

### Put colors to use as graph constraints

Color is more than decoration. Build a reusable **filtered graph** by selecting
placed objects satisfying an explicit condition and retaining their existing
links to one another. Selection never manufactures links. This supports:

- Red-only paths and red-induced connected components. Two red objects connected
  through a blue object are connected in the full graph but not by a red path.
- Paths allowing several colors or excluding a color, using Boolean conditions.
- Distance, component size and cycle questions within that filtered graph.
- Monochromatic components: every member has the same **present** color.
  A wholly colorless component is not monochromatic under this definition.
- Proper coloring: every node in the specified graph has a color and every
  actual link joins different colors. Uncolored nodes cause a false result
  with an explanation; absence is not another color.

Base graph roles and filtered-graph roles must be explicitly distinguished.
An object can be a junction globally and an endpoint within the red graph.
A component seed must belong to its specified filtered graph; otherwise report
that precondition failure. For path questions, excluded endpoints mean no
qualifying path. Color-based editing freezes membership before recoloring,
even when the edit changes the condition that selected the objects.

### Graph construction order is part of meaning

Use typed, compositional graph expressions. The underlying whole-network graph
contains every placed object and exactly the reciprocal links between them.
The proposed constructors are:

| Graph expression | Contract |
| --- | --- |
| `the network` | The whole placed graph. |
| `the component of S` | Find S's component in the whole graph. S must be placed. |
| `the component of S within G` | Find S's component in the already constructed graph G. S must belong to G. |
| `the subgraph of G induced by objects matching P` | Evaluate P on G's objects and retain every qualifying object and every G link between retained objects. The result may have multiple components or be empty. |

S is an ordinary symbolic object reference, G a graph expression and P a typed
object condition. These are semantic constructors, not new stored entities or
bound variables. Do not silently turn a subgraph into one chosen component.

The three readings of “#11's blue component is a tree” require distinct proposals:

| Reading | Proposed question | Seed requirement |
| --- | --- | --- |
| The entire original component is blue and a tree | `Does the component of #11 satisfy tree and monochromatic with color blue?` | #11 must be placed; its color is tested as part of the whole component. |
| The blue-connected region containing #11 is a tree | `Does the component of #11 within the subgraph of the network induced by objects matching color is blue satisfy tree?` | #11 must be placed and blue. |
| All blue objects from the original component induce a tree | `Does the subgraph of the component of #11 induced by objects matching color is blue satisfy tree?` | #11 must be placed; it need not be blue or survive filtering. |

In the third reading, find the full component **first**, then keep all its blue
objects. Blue regions connected only through other colors become disconnected;
testing one surviving blue region would answer a weaker, different question.
The result is a tree only if it is nonempty, connected and acyclic.

Make graph predicates apply uniformly to graph expressions: connected, tree,
forest, cyclic, monochromatic, monochromatic with a specified color, and properly
colored. Monochromatic requires a nonempty graph with one present color shared
by every object; the color-specific version requires that particular color.
These predicates inspect the selected graph even when it is disconnected.

Evaluate an induced-subgraph selection once against its **input graph**, before
constructing its output. Unqualified graph-role predicates in that selection
refer to the input graph; an explicitly supplied graph context overrides it.
Outside an explicitly scoped graph operation, graph-role predicates refer to
the whole network. The grammar must make any context change visible.
Do not repeatedly filter until a fixed point or evaluate a selector against the
subgraph it is defining. Resolve explicit reference operands eagerly, including
in Boolean branches or selections with no matches.

Ordinary symbolic references keep their world/discourse resolution rules;
filtering a graph does not silently restrict the world searched for a definite
description. Explicit graph-dependent conditions can restrict a computed
description. Freeze the resolved identities and every graph view for the current
operation or question; later edits reconstruct views from the new world.

Before evaluation, establish which constructor order and predicate scope was
intended. If natural input leaves the three readings open, the LLM should offer
the meaningful alternatives and ask. If controlled input has ambiguous scope,
the symbolic normalization/clarification path handles it. Equal answers or
identical highlighting in the current world do not make different graph
constructions interchangeable. The final grammar must expose attachment of
graph qualifiers and Boolean scope explicitly, using parentheses where needed.

### Explicit Layer 3 questions

Use the same typed predicates in individual checks, descriptions, selections,
counts and every/some questions. Include the existing intrinsic categories,
graph roles, direct linkage, reachability, colored reachability, spatial relations
and square conditions. Support Boolean composition with scope clarification;
relation targets remain explicit existing-object references.

The following table is a proposed question inventory, to be made exact in the
standalone grammar. `#3` and `#4` may be replaced by supported symbolic references.
Each row names one meaning; aliases are not needed.

| Purpose | Proposed question |
| --- | --- |
| Intrinsic pattern category | `Does #3 satisfy bend?` |
| Graph role | `Does #3 satisfy endpoint?` |
| Port consistency | `Does #3 satisfy unmatched?` |
| Grid adjacency | `Does #3 satisfy next to #4?` |
| Direct linkage | `Does #3 satisfy linked to #4?` |
| Full-graph reachability | `Does #3 satisfy connected to #4?` |
| Colored reachability | `Does #3 satisfy connected to #4 within the subgraph of the network induced by objects matching color is red?` |
| Multi-color reachability | `Does #3 satisfy connected to #4 within the subgraph of the network induced by objects matching (color is red or color is blue)?` |
| Degree | `What is the degree of #3?` |
| Existing-network distance | `What is the distance from #3 to #4?` |
| Filtered distance | `What is the distance from #3 to #4 within the subgraph of the network induced by objects matching color is red?` |
| One shortest existing path | `What is a shortest path from #3 to #4?` |
| Component membership | `Which objects match connected to #3?` |
| Component size | `How many objects match connected to #3?` |
| Components/link count | `How many components in the network?` / `How many links in the network?` |
| Red-induced components | `How many components in the subgraph of the network induced by objects matching color is red?` |
| Cycle membership | `Does #3 satisfy on a cycle?` |
| Cycle in a component | `Does the component of #3 satisfy cyclic?` |
| Tree component | `Does the component of #3 satisfy tree?` |
| Blue-induced part of a full component | `Does the subgraph of the component of #3 induced by objects matching color is blue satisfy tree?` |
| Whole-graph acyclicity | `Does the network satisfy forest?` |
| Whole-graph connectivity | `Does the network satisfy connected?` |
| Critical object | `Does #3 satisfy articulation?` |
| Critical link | `Does the link between #3 and #4 satisfy bridge?` |
| Critical-object selection | `Which objects match articulation?` |
| Monochromatic component | `Does the component of #3 satisfy monochromatic?` |
| Proper coloring | `Does the network satisfy properly colored?` |
| Filtered proper coloring | `Does the subgraph of the network induced by objects matching color is red or color is blue satisfy properly colored?` |
| Combined condition | `Which objects match color is red and endpoint?` |
| Combined scope | `Does #3 satisfy endpoint or (junction and color is red)?` |
| Universal question | `Does every object matching color is red satisfy connected to #3?` |
| Existential question | `Does some object matching color is blue satisfy unmatched?` |
| Square property | `How many squares match not occupied?` |
| Board shading | `Does C4 satisfy shading is dark?` |

Named graph/component predicates are domain algorithms, not an extension to
general nested quantification. Keep one explicit quantifier per question and
no indefinite relation targets. Do not introduce special syntax for two bound
objects through the symmetric-relation exception we previously rejected. Domain
macros can nevertheless express particular relational facts: for example, link
counts in a red-induced graph concern pairs without introducing user-level
bound variables. General first-order reference and quantifier syntax remains
deferred; avoid blanket claims that every two-object fact is inexpressible.

Keep **existing-network distance** distinct from the length of a connection that
could be built. Distance and reachability inspect reciprocal links already in
the world; the construction planner can cross empty squares. Retain degree and
component-count queries. Colored paths include both endpoints and every
intermediate node. Paths remain computed structures, not discourse referents.

Retain the old edge-case contracts: placed self-reachability and zero distance,
isolated singleton components, zero components on an empty board, no path for
unreachable objects, diagnostics for missing references, and false graph
predicates on unplaced objects. Numeric graph queries requiring placement report
an unplaced reference rather than returning an artificial zero.

Make compositional counting explicit. Ordinary object predicates range over all
objects, including unplaced ones. Graph collections contain placed objects only.
Thus `not isolated` also holds of an unplaced object when `isolated` is false;
use `position is present and not isolated` to select placed non-isolated objects.
Do not change Boolean meaning by silently dropping objects based on predicate
keywords. Every over an empty restriction is true and some is false, with the
existing vacuity explanation. Define the corresponding empty-graph results for
new graph predicates; properly colored and forest are vacuously true.
Whole-network connectivity is false for an empty graph and true for a singleton.
For every graph expression, tree and monochromatic are false on an empty graph,
and cyclic is false. A colorless singleton is a tree and a forest, but is neither
monochromatic nor properly colored. Its full-graph degree is zero. Isolated means
placed with degree zero; an unplaced dot has an intrinsic pattern but no graph
membership.
A reference to a computed link requires an actual reciprocal link between the
resolved endpoints; a nonexistent link is a failed link reference, not an
existing non-bridge. Path, link and component questions must expose these
preconditions just as object questions expose missing-object failures.

Questions may update salience for their explicitly referenced objects, under the
shared mention policy, while leaving world facts unchanged. Computed graphs,
components, links and paths do not become new `it` referents. Enumerating a
component or returning a path must not arbitrarily make every result object
salient. Specify which true contextual facts each explicit mention records;
Undo restores that discourse state together with the entry's world state.

### Review obligations

Every proposal must expose the operation, graph construction and predicate scope
that determine its meaning. Review should distinguish:

- The full component, a component found after filtering, and an induced subgraph
  of a component found before filtering, including their exact member identities.
- Grid adjacency, reciprocal linkage and reachability.
- Existing-path queries and connection construction with new objects or port edits.
- Route coloring that can overwrite existing colors and color filtering that
  changes only the graph being inspected.
- Port transformation, identity-preserving position transformation and appearance
  permutation, even when preview pictures happen to coincide.

For construction, show created identities/positions/patterns, endpoint port
additions and all recolorings. For questions, return the symbolic answer and
enough graph/member/path information to identify what was evaluated. Never
replace the intended question with an LLM-computed answer or separate weaker
questions. Ambiguity must be resolved before the affected operation executes;
preview and acceptance must use compatible frozen state and semantics.

## 5. Implementation sequence

1. **Approve the standalone contracts.** Resolve the choices below and write
   `network-language-v2.md`, including typed graph constructors, command and
   question grammar, contracts and review examples. Align the object document/version label to v2 without
   introducing another object-language semantic revision.
2. **Extract shared language machinery with regression tests.** Reuse the existing
   ontology and discourse modules. Factor the genuinely shared typed syntax,
   normalization, reference handling, staged execution and outcome contracts
   out of object-specific code. Domain hooks supply attributes, bundles,
   derived predicates and macros. Preserve the Objects v2 public contract.
3. **Implement Haskell core, then references and existing macros.** Adapt existing
   `Patterns`, `Graph` and `Pathfinding` algorithms rather than replacing them.
   Add pure contracts for failure, allocation, mentions and atomic continuation.
   Audit legacy network dependencies on `Domains.Objects.Parser/Evaluation`.
4. **Add the approved graph extensions.** Reuse filtered graph traversal for
   colored reachability, distance, components and representative paths. Add
   cycle, tree, bridge, articulation and coloring checks with independent small
   examples, including cases that distinguish graph construction order. Keep
   graph predicates reusable over whole, component and induced graphs.
5. **Integrate persistence and review.** Route both domains by explicit version;
   pass and persist the network allocation counter. Generalize object-only
   proposal-version checks in FastAPI and Flutter. Reuse grouping choices,
   staged previews and identity/state changes; add port-pattern details where
   needed for meaningful review. Present path answers as ordered identities and
   critical-link answers as endpoint pairs; highlighting can be a later UI aid.
6. **Update the network agent and documentation.** Replace legacy aliases and
   examples with validated v2 entries. Teach consequential alternatives,
   including link versus creation and position versus port transformation.
   Archive superseded network guides after rollout, not before.

No authentication, ontology JSON redesign or domain-selection changes are
needed. Keep Python orchestration-only and Flutter presentation-only.

## 6. Release policy and verification

No legacy compatibility is retained in the JSON bridge or database startup.
Fresh databases use SQLite schema version 2. Both domains use v2 allocation,
continuation and review semantics. Experimental old Haskell modules remain
available for local experiments and regression tests, outside the served grammar.


Tests must cover strict creation, identity freshness through Undo, all 16 patterns,
additive versus replacement effects, port/connection distinctions, graph-role
invalidation, bounds and occupancy, absent colors, disconnected/unplaced cases,
Boolean scope choices, frozen collections, atomic failure, restart continuation,
and preview without application. Include visually identical outcomes with
different identities. Keep Objects v2 regression tests passing throughout.
For connection construction, cover dot endpoints, closed endpoint ports, turns
and branches added through successive connections, an intermediate object that
blocks traversal, preservation of existing endpoint ports, same-square routes,
and failure without partial endpoint edits.
For the new concepts, distinguish a cycle node from a tail attached to a cyclic
component, a bridge from a noncritical link, and an articulation object from an
endpoint. Include red paths broken by a blue node, uncolored versus monochromatic
components, and colorings that are valid in a filtered graph but invalid globally.
Test all three “blue component” readings on a full component containing several
blue regions joined by other colors; include a cycle in only one blue region.
Also cover a non-blue seed, zero retained blue objects, a colorless singleton,
and changes that invalidate filtered-graph mentions without changing a node's
intrinsic ports. Include cases where readings currently give the same answer;
they must still remain distinct interpretations. Verify that induction selects
against the input graph and never performs an implicit fixed-point computation.

## 7. Reuse audit against the old guides

| Existing idea | Disposition |
| --- | --- |
| Six intrinsic pattern categories and all 16 exact patterns | Retain; remove redundant aliases and additive-letter shorthand, not their expressive power. |
| Pattern/graph-role descriptions and computed salience | Retain with explicit typed conditions and dependency-aware purging. |
| Degree, isolation, endpoints, junctions and unmatched ports | Retain in checks, selections, counts and descriptions. |
| Linked versus connected, shortest distance and component counts | Retain; add explicit question forms and keep construction separate. |
| Colored paths including endpoints | Retain implemented behavior and make the canonical syntax explicit; resolve the old guide's contradictory deferred note. |
| Component recoloring, rotation/reflection, copying and trimming | Retain with frozen selections, explicit bundles, axes and identity contracts. |
| Link/extend and directional disconnect | Preserve the useful effects through separate link, unlink, extension and single-port operations. |
| Shortest construction, deterministic ties and route coloring | Retain, using persistent fresh allocation and explicit route-color wording; refine the planner to open necessary endpoint ports while preserving all intermediate port patterns. |
| Occupancy questions, partial/unplaced objects and empty-world behavior | Retain with shared predicate semantics and precise graph domains. |
| Counting, every/some, reference clarification and whole-entry Undo | Retain; Boolean composition becomes consistent across question wrappers. |
| Previously deferred cycles | Promote to a proposed v2 feature, alongside useful structural graph queries; not assumed to exist today. |

## Decisions before the grammar is finalized

- Exact readable forms for port operations, pattern/appearance literals and
  network predicates; retain one form per meaning.
- Confirm strict separation of linking existing objects and extension creating
  a new neighbor, including extension's color policy.
- Whether whole-drawing transformations need a dedicated macro in this revision.
- Exact syntax exposing route-wide coloring and existing-network distance.
- Approve the proposed structural/color-aware graph inventory and the canonical
  typed forms for component, link and network questions.
- Exact attachment/grouping rules for graph constructors and qualifiers, without
  implicit conversion from a filtered subgraph to a selected component.
- Representation and truth checking of graph-context salience mentions, and the
  explicit-reference mention policy for graph/path/list answers.
- Clean database reset and rejection of all old continuation versions (settled).

These contracts were approved and implemented; consult the standalone references.

## 8. Manifesto review

The second review identified the following specification gaps. They are now
recorded as contracts or explicit grammar/representation decisions above.

| Manifesto obligation | Review result |
| --- | --- |
| Visible types and identity (§4) | Object, square, graph, component, induced subgraph, link and path roles are distinct. Computed structures allocate no identities; endpoint creation is an explicit construction-macro effect. |
| One tool per consequential meaning (§§1, 6) | Link/unlink, extension, port edits, path construction and graph inspection retain distinct contracts. Induced filtering and component finding are separate compositional constructors. |
| Preconditions, absence and failure (§7) | Excluded component seeds, nonexistent links, unplaced objects, empty graphs, colorless objects and no-path results are distinguished. Conflicting initial updates cannot depend on parser order. |
| Faithful macro composition (§8) | References, graph views and update selections are frozen. Induction selects on its input graph. Shortest construction preserves intermediate ports and explicitly authorizes endpoint openings and route recoloring. |
| Consequential clarification (§9) | The three blue-component readings remain different even when answers or pictures coincide. Missing scope produces choices; the LLM cannot silently substitute one graph construction. |
| Compositional questions (§10) | Graph predicates apply to arbitrary graph expressions. Object quantification remains singular; graph algorithms do not introduce hidden user-level bound variables. Boolean negation and placement rules are explicit. |
| Meaningful review and authority (§§2, 11) | Review exposes selected members, identities, port edits and overwritten colors. Symbolic evaluation supplies answers; human review settles intended meanings. Returned paths/components do not become accidental discourse entities. |
| Shared semantics and verification (§§12, 13) | Reuse shared machinery and existing algorithms, with counterexample-based tests for graph construction order, scoped mentions, failure, atomicity and Undo. Both domains share the planned v2 release policy. |

The standalone v2 reference records the finalized grammar, contextual mentions,
whole-drawing transforms and clean database release policy.
