# Haskell logic engine

The served languages are [Objects v2](../../docs/object-language-v2.md),
[Network v2](../../docs/network-language-v2.md) and
[Cellular v2](../../docs/cellular-language-v2.md). All implement
three layers: atomic operations, symbolic references, and conceptual macros.
Commands require a period; questions require `?`. Coordinates denote locations;
`the object at A4` explicitly denotes an existing occupant. Creation is explicit.

## Prerequisites

Install GHC, Cabal and native build dependencies before building. The build was
verified with GHC 9.10.3 and Cabal 3.18.2.0. On Ubuntu, `build-essential` and
`libgmp-dev` are required; a missing GMP development library produces the linker
error `cannot find -lgmp`. See the [root quickstart](../../README.md#ubuntulinux-quickstart)
for the combined Flutter/Haskell/Python prerequisite list.

For GHCup installations, ensure `~/.ghcup/bin` is on PATH and select installed
versions if the unversioned `ghc` and `cabal` commands are unavailable:

```bash
export PATH="$HOME/.ghcup/bin:$PATH"
ghcup set ghc 9.10.3
ghcup set cabal 3.18.2.0
ghc --version
cabal --version
```

If those versions are absent, install them with `ghcup install ghc 9.10.3` and
`ghcup install cabal 3.18.2.0` first. Persist the PATH export in your shell startup
file if needed. GHCup itself must already be installed.

## Build and test

Run from this directory:

```sh
cabal update
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
provider access occurs in Haskell. See the [JSON contract](../../docs/json-contract.md).

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

Object and network domains return monotonic allocation counters outside Undo history. Preview
does not persist allocations. Visual editor operations retain explicit
create-or-update convenience. Ordinary chat never creates a missing referent.
Graph facts in salience carry explicit context and are rechecked after updates.

Legacy continuations are unsupported. FastAPI retains current v2 databases,
applies additive schema updates and expands older cellular boards to 16×16;
it rejects other schema versions unchanged. Haskell does not migrate storage.
Older atomic, Layer 2, DomainLibrary and Sandbox modules remain available for experiments and
regression tests; their aliases and convenience semantics are not served grammar.
See [domain architecture](../../docs/domain-architecture.md).

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

## Cellular language

`Domains.Cellular.Language` exports its parser, formatter, typed syntax and
pure evaluator. `runEntry` takes an automaton, ranking, unsigned random seed,
entry, cell-coordinate choices and completed-sentence offset. Cellular cells
are fixed coordinates A1–P16, never occupants. The existing cellular evaluator
supplies synchronous stepping and ruleset validation.

Forecasts, bounded stabilization and return-time questions do not advance the
current world. Random operations and paused batches retain their seed through
review/continuation. Tests: `cabal test cellular-tests cellular-language-tests`.


## Calendar controlled language

`Domains/Calendar/` implements `calendar-v1`: parser/formatter, typed references,
resumable evaluation, questions and the three finite scheduling operations.
`logic-engine-editor` dispatches `domain: "calendar"` to this independent evaluator;
Python supplies timestamp/offset data and owns persistence and Google writes.
See [Calendar language v1](../../docs/calendar-language-v1.md). Run `cabal test`
for the grammar/model suite; API tests also exercise this real executable against
a fake provider, including write review and recovery.


## Language help examples

Each domain owns its static help list in `Domains/<Domain>/Language/Examples.hs`.
The editor bridge accepts `{"domain":"calendar","action":{"type":"examples"}}`
(and the other three domain IDs) without a world and returns versioned sections.
`language-examples-tests` parses every listed sentence with its domain parser.
Examples use `Plain` and `Reference` parts from `ControlledLanguage.Example`;
JSON preserves those boundaries for uniform reference highlighting. The tests
concatenate parts for parsing and require all three reference forms in each domain.
Keep examples concrete and grouped into primitive/conceptual commands/questions;
the frontend displays these lists without maintaining its own sentence catalog.

### Syntax diagnostics across domains

All four supported domain parsers retain ReadP for successful surface parsing
and ambiguity enumeration. On rejection, the same grammar runs with the shared
Megaparsec diagnostic backend in `ControlledLanguage/Parsing.hs`. Errors point
into the original input and name expected syntax or invalid values; no repair
or interpretation is chosen automatically. `parser-diagnostics-tests` checks
positions, value errors, surface syntax and preservation of Boolean readings.
