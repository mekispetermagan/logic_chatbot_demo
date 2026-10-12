# Domain libraries and the shared grid engine

The engine separates domain declarations from world state. Haskell and FastAPI
support objects and network domains on 8×8 boards. The network domain currently
has Layers 1/2 only; see [network core](network-core.md). The generic JSON
contract identifies the domain explicitly. Flutter transport/models support both
domains, including domain selection and the network editor.
There is no runtime ontology loader or metadata endpoint yet.

## Generic ontology

`Ontology.hs` defines identifiers, references, positions, and entities. An entity
has an identifier, an optional position, and a map from `AttributeId` to
`ValueId`. Missing map entries mean absent attributes. Each attribute has at
most one stored value; assignment replaces that value without changing other
attributes. An attribute with one permitted value represents a unary property:
assignment adds it, removal clears it, and absence makes its property check
false. Absence is not an unknown truth value.

Position remains structural. Bounds come from the selected ontology, and the
engine retains one-object-per-square occupancy. Coordinate syntax supports
single-letter columns A–Z and positive decimal rows within the declared board.
The objects domain still permits only A1–H8.

`Domain.hs` declares finite attributes, their values and aliases, attribute
ordering, board dimensions, and the domain identifier. `validateDomain` rejects
invalid dimensions, empty or duplicate declarations, ambiguous vocabulary,
reserved words, and vocabulary that conflicts with references. Unary attributes
use the same representation as other finite attributes; no Boolean type is
needed. Definitions are ordinary immutable Haskell values, not conversation state.

## Domain library

`DomainLibrary.hs` combines an ontology with pure callbacks for derived
performative parsing, derived question parsing, and derived evaluation. The
shared engine still owns entry boundaries, Layer 1 operations, descriptions,
reference resolution, salience, clarification, and entry sequencing. The current
domain's derived evaluator supplies spatial questions, counting, quantification,
and movement/copying. These algorithms remain ordinary Haskell functions.

| Module | Responsibility |
|---|---|
| `Domains/Objects/Definition.hs` | Current color, size, shape, vocabulary, and 8×8 dimensions |
| `Domains/Objects/Parser.hs` | Current derived sentence forms |
| `Domains/Objects/Evaluation.hs` | Current derived semantics, using generic attributes and supplied dimensions |
| `Domains/Objects/Library.hs` | Assemble `objectsLibrary` |
| `Domains/Objects/Vocabulary.hs` | Domain-specific convenience patterns and fixture constructors |
| `SyntaxVocabulary.hs` | Shared domain-aware lexical and description helpers |

The domain library is passed explicitly to chat parsing and evaluation. Its
ontology is passed onward to atomic evaluation and reference creation. No
mutable global selection or remembered conversation is introduced. Existing
short function names remain convenience wrappers selecting the objects domain;
production bridge entry points use explicit selection.

## Layer 1

Attribute assignment, removal, property checks, and value queries now operate
on attribute identifiers rather than separate color/size/shape branches.
Evaluation checks attribute/value membership in the selected domain. Position
assignment, unplacement, swapping, and deletion retain their structural meaning.
Questions and structural operations never create referents. Attribution retains
creation during reference resolution, including preserving a newly created
source when its subsequent move is blocked.

## Formatting and compatibility boundary

Canonical value identifiers are printable descriptor words; aliases normalize
to those identifiers. `pretty` for a generic entity prints named stored
attributes. Use `prettyObjectIn objectsDomain` or `prettyWorldIn objectsDomain`
for the original ordered display, including question marks for absent values.
The console and clarification labels use this domain-aware formatting.

`bridge/EditorJson.hs` transports a generic `attributes` map for each object and
explicit attribute/value properties for edits and salience. It selects and
validates the domain library from the required `domain` field, before parsing
state, and echoes that identifier in responses. FastAPI stores the immutable
domain on each conversation. SQLite startup migration converts all legacy world
and salience snapshots together, preserving history and pending entries.
See the [JSON contract](json-contract.md) for details.

A future domain can provide another Haskell library and, later, exported JSON
metadata. Ontology documents and changing world/discourse documents will remain
separate. Continuous attributes, stored arbitrary relations, and dynamically
loaded language extensions are outside this refactor.

## Verification

The existing parser, evaluation, editor, and API regression suites exercise the
original domain. `test/DomainTest.hs` adds test-only attributes to that same
definition to check unary semantics, vocabulary isolation, invalid declarations,
domain bounds, and propagation through descriptions and derived evaluation.
These fixtures are not additional production domains.
