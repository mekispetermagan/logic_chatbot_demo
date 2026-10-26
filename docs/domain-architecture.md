# Domain libraries and the shared grid engine

## Language boundary

All three served languages use v2: [Objects](object-language-v2.md),
[Network](network-language-v2.md) and [Cellular](cellular-language-v2.md).
`bridge/EditorJson.hs` selects a domain from an explicit request identifier. It never uses the experimental legacy parsers.
There is no mutable global domain or conversation state in Haskell.

`ControlledLanguage/` implements the shared syntax tree, domain-parameterized
surface and canonical grammars, readable/canonical formatting, reference
resolution, typed object/square salience, staged execution, continuation replay and change reporting.
`Domains.Objects.Language` and `Domains.Network.Language` provide convenient
pure entry points bound to each immutable domain definition. Cellular has its
own typed syntax, parser, formatter and evaluator in `Domains/Cellular/Language/`,
reusing the shared coordinate referents and discourse policy.

## Ontology and domain algorithms

For Objects and Network, `Ontology.hs` defines identifiers, optional positions,
generic attribute maps and worlds. A missing attribute is absent, not unknown. `Domain.hs` declares
finite attributes, canonical values, board dimensions and identifiers;
`Domains/Objects/Definition.hs` and `Domains/Network/Definition.hs` supply the
two constant ontologies. Executable grammars exclude legacy aliases.

Objects use color, size and shape. Network uses color and four independent
unary ports; patterns and appearances are bundles, not stored shape fields.
Both domains currently use 8×8 boards. The v2 lexical grammar explicitly supports
A1–H8; changing board dimensions also requires updating that grammar.

Cellular uses 256 fixed cells on a 16×16 torus, A1–P16, with one active color
per cell and no object identifiers or occupants. Its state includes a ruleset,
generation and ruleset revision. `Domains/Cellular/Evaluation.hs` owns synchronous
evolution, painting and ruleset replacement. The cellular language adds
same-color connectivity, bulk color/spatial operations and bounded forecasts.
Forecasts do not advance the committed world.

`Domains/Network/Graph.hs`, `Patterns.hs`, `Pathfinding.hs`, and `Analysis.hs`
provide pure port, reachability, route construction and graph algorithms.
Components and induced views are transient values, never persistent entities.
Induction evaluates its selector once in the input graph. Layer 3 distinguishes
port transforms, identity movement, appearance permutations and drawing transforms.

`DomainLibrary.hs`, atomic modules and old domain parser/evaluator modules remain
experimental GHCi helpers and regression fixtures. They do not define the public
v2 grammar or continue old saved conversations.

## State, presentation and verification

Each language evaluation receives its world, discourse ranking, program and
clarification transcript as arguments. Objects and Network also receive a
fresh-ID counter; Cellular receives a random seed. Random choices are frozen
through preview, acceptance and continuation. Results contain updated state,
feedback, typed changes and an optional pause. Fully delimited replay keeps
resolved choices deterministic. Object and square mentions share a clock but retain distinct referent types.
Pronouns use the required type; mixed ties are clarified without conversion.
Contextual object facts contain their graph scope and grounded object operands.
Cellular facts retain grounded cell operands. False facts are purged after
updates, including changes to other entities or rules that invalidate them.

FastAPI transports requests and persists world/salience/pending history in
SQLite. Undo restores the entire entry’s world and discourse; object/network
ID counters remain monotonic outside history. Flutter renders committed/provisional/preview
worlds and changes without implementing semantics. Existing schema-version-2
databases are retained; startup applies additive updates and expands older
cellular snapshots and saved slots to 16×16. Other schema versions and legacy
continuations are rejected unchanged. See the
[JSON contract](json-contract.md).

All three domain language suites cover parsing, round trips, scope clarification,
reference resolution, failure and atomicity. Network tests additionally cover
endpoint openings, unchanged intermediate ports, route recoloring, graph laws,
color-filter construction order and contextual salience. Cellular tests cover
toroidal neighborhoods, synchronous evolution, rulesets, frozen randomness,
connectivity and bounded temporal answers. API tests exercise the real executable,
restart, Undo, proposal preview and acceptance; Flutter tests
exercise review and editor behavior.

Future domains may add Haskell libraries and exported ontology metadata. Constant
ontology documents and changing conversation state remain separate. Runtime
ontology loading, continuous attributes and arbitrary stored relations are
outside this demo.
