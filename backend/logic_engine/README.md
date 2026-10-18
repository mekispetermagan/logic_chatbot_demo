# Haskell logic engine

The served languages are [Objects v2](../../specification/object-language-v2.md)
and [Network v2](../../specification/network-language-v2.md). Both implement
three layers: atomic operations, symbolic references, and conceptual macros.
Commands require a period; questions require `?`. Coordinates denote locations;
`the object at A4` explicitly denotes an existing occupant. Creation is explicit.

## Build and test

Run from this directory:

```sh
cabal build exe:logic-engine-editor
mkdir -p bin
cp "$(cabal list-bin exe:logic-engine-editor)" bin/logic-engine-editor
cabal test
cabal repl
```

Rebuild and copy after Haskell changes; FastAPI invokes the installed executable.
The JSON bridge reads one request from stdin, writes one reply to stdout, and
exits. Invalid transport/versions exit 2 with a diagnostic on stderr. Language
syntax/evaluation failures are normal structured responses. No HTTP, database or
provider access occurs in Haskell. See the [JSON contract](../../specification/json-contract.md).

## Interactive use

In `cabal repl`, select one domain façade to avoid conflicting short names:

```haskell
:module Domains.Network.Language Ontology
let Right program = parseEntry "Create object with color red and pattern ---- on A1. Build shortest connection from A1 to H8 with route color blue."
let result = runEntry (World []) [] 0 program [] 0
putStrLn (resultFeedback result)
resultWorld result
```

Use `Domains.Objects.Language` similarly. `runEntry` takes the initial world,
salience, next identifier, parsed entry, clarification choices, and count of
completed sentences already displayed. Its result includes state, feedback,
typed changes, and optional reference/placement pause. `parseEntryAlternatives`
returns meaningful surface-scope readings; `parseEntry` requires a unique one.

## Modules and execution

`ControlledLanguage/` shares domain-parameterized grammar, AST, canonical replay,
formatting and evaluation. Domain-bound façades live in `Domains/*/Language/`.
Immutable definitions supply ontology values; network graph algorithms live in
`Domains/Network/{Graph,Patterns,Pathfinding,Analysis}.hs`.

Normal sequences stop on failure, retaining completed operations. Every macro is
atomic; explicit `Atomically { ... }.` batches commit all world/salience changes
or none. Pending atomic work exposes a separate provisional world. Continuations
replay their frozen seed and accepted choices through the canonical parser.
One entry and all its clarifications form one Undo unit in FastAPI.

Both domains return monotonic allocation counters outside Undo history. Preview
does not persist allocations. Visual editor operations retain explicit
create-or-update convenience. Ordinary chat never creates a missing referent.
Graph facts in salience carry explicit context and are rechecked after updates.

There is no legacy continuation support or database migration. Older atomic,
Layer 2, DomainLibrary and Sandbox modules remain available for experiments and
regression tests; their aliases and convenience semantics are not served grammar.
See [domain architecture](../../specification/domain-architecture.md).

## Object and square antecedents

`ControlledLanguage.Discourse` keeps typed object identifiers and square
coordinates on one recency clock. Predicate/operand types restrict eligible
antecedents; shared spatial predicates use recency across both and clarify ties.
`Does D1 satisfy not occupied? Does it satisfy occupied?` refers to the same
square twice, without introducing its occupant. `the object at it` is an explicit
occupant selection. No object-to-position or square-to-occupant coercion occurs.

Square mentions and their currently true facts are persisted alongside object
mentions. False occupancy evidence is purged after updates, while the location
survives deletion of its occupant. Clarification choices retain their types;
Undo and atomic rollback restore both kinds together. Old object-only ranking
records retain their JSON representation. The experimental legacy `Discourse`
module is separate from the served typed ranking.
