# Controlled English Fragment for the Logic Demo

For the implemented atomic language, see the
[Core Language Reference](controlled-english-core.md). This design note describes
the broader planned layers. [Layer 2 Syntax](controlled-english-layer2.md) documents
the newly implemented description/pronoun parser, without their evaluation.
This note’s original identifier notation and unknown-value
terminology have since changed in the core implementation.

## Purpose and scope

The demo uses a deliberately small fragment of English to create and inspect a world of objects on an 8×8 chessboard. It demonstrates three language layers, from statements that directly update the world model to ordinary-looking sentences that introduce and refer to objects.

This is a scoped language for a particular ontology and task, not an all-purpose chatbot language. The language processor maps user sentences into explicit logical content; the world model and its rules determine what is true, false, or unknown.

Coordinates follow chessboard convention: **A1 is the bottom-left square**. Internal object identifiers such as `o12` are rigid designators assigned by the system. Users do not need to know or type them.

## The three layers

| Layer | What it expresses | Example |
|---|---|---|
| 1. Direct ontological atoms | Explicit facts or questions about an object and the base ontology | `o12 red`; `o12 on A3`; `o12 color?` |
| 2. Compositional and discourse sentences | Descriptions, quantifiers, and pronouns that introduce, identify, or relate discourse referents | “Cube on A3. It is large and red.” |
| 3. Atoms with derived terms | Facts or questions using a relation or property defined over base ontology facts | `near(o12, o3)` |

Layer 2 adds subjects and sentence constructions interpreted against the core world and dialogue context. Layer 3 adds derived terms grounded in base ontology facts; these may be used by the descriptive language.

## Layer 1: Direct ontological atomic language

### Atoms and questions

The narrowest fragment contains atomic statements about named objects and base properties. It has no pronouns, quantifiers, descriptions, or derived relations.

Illustrative internal forms:

- `o5 on A3`
- `o12 red`
- `o3 cube`
- `o4 large`

A question is marked with `?`:

- `o5 on A3?` — ask whether the object is on that square
- `o12 red?` — ask whether the object is red
- `o4 color?` — ask for its color
- `o4 position?` — ask for its square
- `o4 column?` — ask for its column

These are semantic/internal forms for Codex and the engine. The user-facing controlled English need not expose this notation.

### Base ontology

For the demo, the board contains objects with a persistent identity and base attributes such as:

- shape: sphere, cube, pyramid
- color
- size
- board position (row and column, or one square such as A3)

An object may be only partially specified. Unknown attributes remain unknown; they are not silently treated as false. The board prevents two objects from occupying the same square.

### Update and query behavior

- A performative about a new system-assigned ID introduces a referent/object and records the supplied base facts. The object may remain partial while other attributes are unknown.
- A performative about an existing ID updates that object's stated facts. For a single-valued attribute such as color, a new value revises the current value rather than adding a second color.
- A question about an existing object returns the relevant truth value or property value; an unknown attribute remains unknown.
- A question about an ID with no referent returns no referent/unknown, not an ordinary false answer.

The facts are not all logically independent. For example, an object cannot be both red and blue when color is a single-valued attribute. The model must represent such exclusivity as a constraint; it should not assume each positive color predicate is independent.

## Layer 2: Descriptions, quantifiers, and pronouns

This layer lets the user speak naturally enough to introduce objects, make multiple claims, and refer back to them. It includes descriptions, quantifiers, and/or pronouns, but the demo should keep the grammar narrow and demonstrate only selected constructions.

### Introducing an object and resolving anaphora

Users do not supply internal IDs. A description can introduce a new discourse referent; the system assigns it an ID. A subsequent pronoun can refer back to that referent.

Example:

> Cube on A3. It is large and red.

If this introduces a new object assigned ID `o12`, interpretation yields these Layer 1 facts:

```text
o12 cube
o12 on A3
o12 large
o12 red
```

The pronoun `It` is resolved from dialogue context to `o12`. No indexed-pronoun notation such as `it_0` is part of the user-facing or narrowest atomic fragment.

Descriptions can leave an object partially specified. “Cube on A3” supplies shape and position; size and color remain unknown until stated or clarified.

### Ambiguity and clarification

When a description or reference could identify more than one object, the system should ask a focused clarification rather than silently choosing an interpretation. If a derived relation leaves a small set of legal board positions, it can present those choices directly. Clarifications should only be asked when the ambiguity affects the interpretation or resulting board state.

### Quantifiers and descriptors

Quantifiers and richer descriptions belong to this descriptive layer because they can refer to one or more objects rather than naming a specific internal ID. The broad demo scope includes this layer, but it does not require a broad English grammar. Choose one or two constructions that visibly add value and keep the rest out of scope.

## Layer 3: Atomic sentences with derived terms

This layer adds atomic-looking properties or relations whose meanings are defined over the base ontology. The derived term is not stored as a primitive fact in the world model. It must be evaluated from the underlying object attributes and board state.

### Example: `near`

In this chessboard demo, `near(x, y)` means that the objects occupy orthogonally neighboring squares: one square apart horizontally or vertically. Diagonal contact does not count.

For example, if `o3` is on A1, then the possible neighboring squares are A2 and B1. B2 is diagonal and is not near under this definition.

Thus `near(o12, o3)` is evaluated from the two objects' positions. If a user says “Put a sphere near the cube” and the cube is on A1, the system can ask the user to choose A2 or B1, for example with buttons, then update the sphere's base position after selection. `near` itself is not written into the base board state.

### Design principle

Derived properties and relations should be grounded in a systematic investigation of the ontology and its possible states, rather than accumulated as manually invented axioms. Discovering candidate derived concepts is a potential AI task; naming or mapping those concepts to ordinary English may use a language model. Any term used in the demo still needs an explicit, checkable interpretation over base facts.

For a small demo, a fixed, transparent definition such as the one above can illustrate the layer. That does not imply that all useful derived terms should be hand-authored in the full system.

## Interpretation pipeline

A useful implementation boundary is:

1. Interpret a controlled-English sentence and its dialogue context.
2. Resolve descriptions and pronouns to discourse referents / internal IDs.
3. Resolve derived terms against the base ontology and current board state.
4. Produce explicit base facts, a query, or a clarification request.
5. Apply valid updates to the board and return a concise response.

The world model remains the source of base facts. Derived evaluations and discourse interpretation should not be confused with those stored facts.

## Suggested end-to-end demo slice

A compact demonstration can exercise all three layers in sequence:

1. User: “Cube on A3. It is large and red.” The system creates an object and assigns an internal ID, then updates the board with its base properties.
2. User: “Put a sphere near it.” The system resolves “it” to the cube, evaluates the derived relation `near`, and offers legal neighboring squares if a choice is needed.
3. User asks a direct question such as “What color is the cube?” or “Is the cube red?” The system answers from the base facts.

This demonstrates referent introduction and anaphora (Layer 2), a derived relation (Layer 3), and direct ontology queries and updates (Layer 1), without requiring an all-purpose dialogue system.

## Keep out of the narrowest fragment

- Pronouns, descriptions, and quantifiers in Layer 1 atoms
- User-entered object IDs
- `near` or other derived relations as stored ontology predicates
- Treating unknown values as false
- Assuming color predicates are independent
- An unrestricted natural-language interface
