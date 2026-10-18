# Manifesto for Domain-Specific Controlled Languages

## Purpose and status

A controlled language in this dialogue system is a precise, human-readable
medium for establishing intended meaning and executing it symbolically. Its
primary audience is a human reviewing a proposed interpretation. The human
should be able to understand exactly what is proposed without having to learn
how to formulate every request in that language.

This document records design principles and a direction for future development.
It does not claim that the current grammars implement every principle below,
and it does not authorize changing their existing semantics. Domain-specific
syntax and unresolved execution policies require separate specifications.

## 1. Put convenience at the interpretation boundary

Humans express goals in ordinary language. The LLM proposes controlled
interpretations. The controlled language makes consequential distinctions
explicit, and the symbolic engine evaluates their meaning.

An earlier chatbot without an LLM needed a grammar that humans could remember
and produce easily. In this architecture, that convenience can live in the
interpretation layer. Optional words, shorthand and many synonymous spellings
need not burden the executable language.

Choose one canonical form for each operation. Put natural synonyms, common
paraphrases and conversational variations in the interpreter's instructions
and examples. Natural input may be flexible; proposed programs must be exact.
Direct controlled-language input can remain available for experts and debugging.

## 2. Separate interpretation, resolution and authority

The components have distinct responsibilities:

| Component | Responsibility |
| --- | --- |
| Human | Establish intended meaning and settle consequential ambiguity |
| LLM | Propose and explain candidate interpretations; interpret clarification answers |
| Logic engine | Resolve references, enforce constraints, evaluate operations and derive answers |
| Search | Explore formal possibilities when direct evaluation is insufficient |
| Orchestration and interface | Present proposals and feedback, persist state and manage review and Undo |

Reference resolution belongs to the logic engine. If it becomes computationally
difficult, learned search may support symbolic exploration and candidate ranking.
Symbolic rules still determine admissibility; significant unresolved ambiguity
returns to the human. LLM confidence does not establish a referent.

Verification establishes consequences of a formal interpretation under a model.
It cannot establish that the interpretation captures the user's intention.

## 3. Use explicit actions and speech-act distinctions

Imperative wording is appropriate for requested changes. A canonical instruction
should name its operation: create, set, clear, move, copy, transfer, exchange or
delete, with vocabulary appropriate to the domain.

Imperative grammar does not require treating the system as an independent agent.
It can name an operation as directly as a button does. The philosophical
foundation remains compositional meaning and explicit information-state change.

Distinguish an instruction to change something, a claim about what already holds,
and a question about it. If a domain supports assertions, their commitment or
information-update semantics must be specified separately from commands that
change the modeled situation. Similar wording must not conceal different acts.

Brief conversational courtesy is a separate channel. It is never an executable
operation, a symbolic answer or implicit authorization to apply a proposal.

## 4. Make identity and types visible

Identity is independent of appearance, position, labels and other mutable
attributes. Moving an entity, changing its attributes and replacing it with a
new entity are different operations, even when their visible results coincide.

References to locations, entities, values, collections and relations must have
explicit types. Avoid implicit conversions that hide a consequential selection.
For example, a location denotes that location; referring to its occupant requires
an explicit occupant description. A missing occupant is not permission to create
one.

Each operation must state which identities survive, which are created or deleted,
and which attributes and relations remain unchanged. Identifier allocation and
lifetime must be specified, including deletion, Undo and retained dialogue
history. Reusing a label must never silently redirect an old identity reference.

## 5. Keep the three semantic layers

| Layer | Purpose | Domain dependence |
| --- | --- | --- |
| **1: Atoms** | Elementary operations, predicates and value queries with exact contracts | Shared structure plus domain-specific attributes and primitives |
| **2: Referential macros** | Identifiers, pronouns and definite descriptions resolved symbolically | Domain-independent machinery using domain vocabulary and state |
| **3: Conceptual macros** | Useful constructions, transformations and derived questions | Mostly domain-specific, with reusable abstractions where justified |

An atom is semantically elementary, not necessarily a short sentence or a
single-field write. An exchange may need to change two fields indivisibly.

Layer 2 determines which entities are concerned without replacing the operation
vocabulary. Layer 3 supplies meaningful domain concepts rather than spelling out
every elementary step. These are compositional responsibilities, not a demand
to flatten every proposal into a long transcript of atomic commands.

## 6. Give every consequential distinction a sharp tool

Prefer a small, orthogonal toolkit. Introduce an operation when it expresses a
distinct effect or a useful guarantee, rather than another way of saying the
same thing. Distinctions commonly needed across domains include:

- Creating an entity versus updating an existing entity.
- Clearing an attribute versus deleting its owner.
- Moving an entity versus transferring its attributes.
- Copying a value versus transferring it and clearing the source.
- Exchanging positions versus exchanging named attributes.
- Cloning an entity with a new identity versus moving the original.
- Setting selected attributes versus replacing an entire specified bundle.

Name source, destination and affected attributes explicitly. Define bundles by
their exact contents; a word such as “properties” must not leave it unclear
whether identity, location or relations are included.

Creation should be explicit. If create-or-update behavior is useful, give it an
explicitly named operation and contract. A failed update must not create an
entity as an unnoticed side effect of reference resolution.

## 7. Specify contracts before syntax

Every primitive and conceptual macro needs a contract covering:

- Operand types and reference-resolution rules.
- Preconditions, constraints and admissible parameter values.
- Effects on existence, identity, attributes, relations and discourse state.
- What remains unchanged.
- Behavior for absent values, missing referents and empty selections.
- Atomicity, failure, no-change and clarification behavior.
- Returned answers and explanations.

Reject conflicting assignments within one simultaneous update. Intentional
successive revisions belong in an explicitly ordered sequence. An operation
should not derive its meaning from an accidental implementation order.

Absence, uncertainty, falsity and reference failure are different concepts.
Represent and explain whichever distinctions a domain needs. In the current
partial-world model, absence is known absence, not an unknown value. Equality
of absent attribute states is distinct from sharing a present value.

## 8. Preserve meaning through macro expansion

A macro must preserve identity, constraints, binding and the execution guarantees
in its contract. A visual transformation must not be implemented by rewriting
attributes when its meaning is to move entities.

Resolve the operands and selected collection of one operation before changing
them. Specify when source values are read. A simultaneous exchange uses the
pre-operation values; a sequence may intentionally use the results of earlier
steps. Changing the state must not silently change the selection midway through
one conceptual operation.

Separate sequential execution, atomic batches and any explicit best-effort
execution policy. One Undo unit does not by itself imply atomic execution.
Specify whether a failure stops a sequence, preserves completed steps or rolls
back a batch. Do not inherit that choice accidentally from expansion into atoms.

An underdetermined macro may require clarification or search. If the user delegates
a design choice, the system may choose within that freedom, while preserving all
specified constraints and explaining material assumptions.

## 9. Clarify semantic alternatives, including invisible ones

Candidate interpretations should differ in meaning, not merely wording.
Rank plausible readings and ask when they differ consequentially and context
does not establish the intended one.

Compare consequences for the full relevant information state. Identical pictures
can conceal different identities, relations, provenance, discourse references or
future behavior. Conversely, synonymous programs need not become separate choices.
Even equal final states may not establish equivalence if intermediate effects or
commitments matter in the domain.

For example, rearranging entities and exchanging their appearance attributes can
produce the same picture. Their proposals must explain that one moves identities
and the other keeps identities fixed. A graphical preview alone cannot settle
that distinction.

The LLM may still omit a plausible interpretation. Language design and symbolic
validation reduce this risk but do not eliminate it; candidate coverage and
clarification quality need evaluation of their own.

## 10. Make questions compositional and faithful

Define reusable predicates, then use them consistently in checks, selections,
counting and quantification where supported. Avoid arbitrary gaps in which a
condition is expressible only under one question wrapper.

Distinguish entity existence, attribute presence, attribute value, identity
equality and relation membership. Specify connective scope, quantifier domains,
empty-set behavior and any supported negation. A domain need not support every
logical construction, but its supported boundaries must be explicit.

Questions remain questions. The LLM must not substitute a state-changing command,
a precomputed answer, or weaker questions whose answers do not establish the
requested result. The logic engine computes domain answers.

A question may leave domain facts unchanged while affecting discourse state.
Document both effects, including salience and Undo behavior. Preserve the
distinction between stated information, externally supplied information and
derived conclusions wherever the domain represents them.

## 11. Design proposals for meaningful review

Readable syntax is necessary but insufficient. Review should show:

- The proposed operation, scope and material assumptions.
- Resolved identities and selections when available from the logic engine.
- Changes to existence, attributes, relations and location, as applicable.
- Relevant preconditions, blocked effects and unresolved choices.

Keep pronouns and descriptions for symbolic resolution rather than having the
LLM silently substitute guessed identifiers. If resolution depends on earlier
steps, review must respect that dependency and expose later clarification.

Preview and acceptance must use compatible state and semantics. If relevant state
changes, reject a stale proposal or require renewed review. Clarification and
rejection do not establish authorization. Undo must restore the corresponding
domain and discourse state, not just the rendered scene.

## 12. Treat domain libraries as semantic libraries

A domain supplies more than a list of nouns. It defines types, attributes,
relations, constraints, primitives, conceptual macros and their verified
algorithms. Keep stable ontology and language definitions separate from changing
conversation state.

Data descriptions can declare vocabulary and structure; algorithms may remain in
Haskell. There is no requirement to encode an entire semantic library in JSON.
Domain selection and semantic versions must be explicit enough to interpret
stored state and executable proposals consistently.

Generalize abstractions supported by real shared semantics. Domain independence
does not require forcing every domain into grid positions, finite attributes or
independent entities. Different domains may need continuous quantities with units,
stored relations, dependencies or other structures with their own contracts.

## 13. Verify the distinctions the language promises

Tests should establish semantic obligations rather than merely reproduce parser
branches. Cover identity preservation, creation and deletion, absent values,
missing references, conflicting updates, boundary conditions, failure, atomicity,
clarification and restoration of discourse state.

Test conceptual macros against their contracts, including equivalence to an
appropriate atomic construction where possible. Include pairs of visually
identical results with different identities or dependencies. Test interpretation
separately: does the LLM offer the consequential alternatives, and does a
clarification preserve the original constraints?

Before adding a language feature, ask:

1. What distinct meaning or useful guarantee does it provide?
2. Can a reviewer tell exactly what it changes and preserves?
3. Are its references, missing values and failure behavior explicit?
4. Does its composition preserve that meaning?
5. Which obligations can the engine check, and which still require human intent?

The design goal is a toolkit with one sharp operation for each meaningful task,
composed into concepts humans can inspect and approve. Precision concerns both
correct execution and establishing what should be executed.

## Related documents

- [Overall project concept note](logic-dialogue-concept-note.pdf)
- [Current domain-library architecture](domain-architecture.md)
- [Current object-domain language](object-language-v2.md)
- [Archived atomic core](archive/controlled-english-core.md)
- [Archived referential layer](archive/controlled-english-layer2.md)
- [Archived object-domain conceptual layer](archive/controlled-english-layer3.md)
- [Current agent instruction source](agent-instructions-draft.md)

The archived references preserve earlier object-language design choices. The
versioned object-language document defines current behavior; this manifesto
provides the principles for reviewing future changes.
