# Logic engine experiments

`Ontology.hs` contains the base types and world helpers. `AtomicPerformative.hs`
owns atomic updates; `AtomicPropertyCheck.hs` owns check evaluation.
`AtomicSentence.hs` combines both kinds of sentence. `Pretty.hs` defines the
pretty-printing class, with instances alongside their types, and `Result.hs`
defines evaluation results. `Sandbox.hs` holds the experimental examples.
`Grammar.hs` re-exports these modules for compatibility.

`AtomicParser.hs` uses Megaparsec to parse controlled-English atomic sentences
without updating state.

Identifiers use `#3`; square references use A1-H8. The old `o3` spelling is
not accepted. The parser accepts case-insensitive properties and squares, optional `is`,
optional `on` for positions, and optional periods only at the end of an entry.
Adjacent performatives must be separated by a period. Squares A1-H8 map to zero-based
coordinates with A1 at `(0, 0)`. Empty input and malformed suffixes are rejected.

`parseAtomicPerformative` parses exactly one performative;
`parseAtomicPerformatives` returns an ordered list. Both return `Either String`
with a readable parse error on failure.

`parseAtomicSentence` and `parseAtomicSentences` also accept property checks,
marked with `?`, such as `#1 is red?` or `#1 on B3?`. They return
`AtomicSentence` values tagged as `Performative` or `PropertyCheck`.
`evaluateAtomicPropertyCheck` queries a world and returns `Result Bool`:
absent or different properties are false, and a missing object yields `Message`.
`pretty` renders a property check as controlled English ending in `?`.

`AtomicPropertyQuery.hs` adds attribute-value questions: `color of #3?`,
`size of #3?`, `shape of #3?`, `position of #3?`, `row of #3?`, and
`column of #3?`. Mixed parsers return these as `PropertyQuery` sentences.
`evaluateAtomicPropertyQuery` returns `Result QueryAnswer`, with `Absent` for
missing attributes and `Message` for missing objects. Answers support `pretty`:
positions print as A1-H8, rows as 1-8, columns as A-H, and absence as `none`.

`AtomicEvaluation.hs` provides `evaluateAtomicSentences world sentences`, returning
the final world and ordered `AtomicFeedback` values. Each feedback includes the
parsed sentence and an answer or update change, and supports `pretty`. Questions
see preceding updates; missing referents produce messages without stopping the
sequence. Repeating a fact reports no change. Parsing remains separate, and
updates reject out-of-board positions and occupied destinations.

`ReferenceResolution.hs` resolves either `ById` or `AtSquare` subjects.
Performatives create missing objects during resolution; an empty square gets
`nextId` and that position. Questions never create, and ambiguous references
produce a message. A failed movement preserves any object just created at its
source. For example, `A4 to A5` creates at A4 if needed, then moves if A5 is free.
`to` is performative-only; `on` supports both updates and property checks.
Every question requires `?`; performatives do not accept it. Attribute shorthand
works with both references: `B3 column?` and `#3 column?`.

`Console.hs` provides `chatLoop :: World -> IO ()`. In `cabal repl`, run
`:module + Console` followed by `Console.main` to start from `Sandbox.world`,
or `chatLoop world` with another starting world. Each round prints the world,
reads one line, prints feedback, and repeats with the updated world. Parse errors
preserve state. Enter `:quit` or send end-of-input to exit the loop.

With Cabal and dependency downloads available, run from this directory:

```sh
cabal test
cabal repl
```

Inside the REPL, use `:module + AtomicParser` to expose the parsing functions.
If Megaparsec is already available to GHCi, you can instead run:

```sh
ghci -XInstanceSigs Grammar.hs AtomicParser.hs
```

`InstanceSigs` is needed for the existing signature in the `Ord Identifier`
instance. Cabal enables it for this project. Parsing does not perform collision
checks or apply updates; those belong to the world-update layer.

## Visual editor bridge

`WorldEditor.hs` evaluates property edits, placement, erasure, and clearing as
pure operations. Property edits reuse atomic performatives; placement requires
an existing unplaced object. Undo belongs to FastAPI persistence.

`bridge/EditorJson.hs` handles JSON; `bridge/Main.hs` provides a one-request
executable. Each process reads one JSON document from stdin and writes one
response to stdout. Invalid protocol input exits unsuccessfully with diagnostics
on stderr. The bridge validates 8×8 dimensions, unique identifiers, bounds, and
occupancy of the supplied world before evaluation.

```sh
cabal build exe:logic-engine-editor
mkdir -p bin
cp "$(cabal list-bin exe:logic-engine-editor)" bin/logic-engine-editor
cabal test
```

Rebuild and copy after changes to engine code. FastAPI uses the copied executable.
A request has `world` (the shared JSON representation) and `action`, for example:

```json
{"world":{"width":8,"height":8,"objects":[]},"action":{"type":"property","position":{"x":0,"y":0},"property":"red"}}
```

The response contains the resulting `world` and concise `feedback`. Other action
types are `place` (with `objectId` and `position`), `erase` (with `position`),
`clear`, `chat` (with `text`), and `clarify` (with `objectId`). Requests also
carry `salience` and nullable `pending`; both default to empty for older callers.
Responses return both alongside `world`, `feedback`, and `isError`.
Chat entries with a case-insensitive `undo` prefix after optional whitespace
return `undoRequested: true` before grammar parsing or clarification checks.
All trailing text is ignored; Haskell leaves the state intact for FastAPI to
restore from history.
The bridge owns JSON transport; `Discourse.hs` and `Layer2Evaluation.hs` own
pure reference resolution, salience updates, ordered evaluation, and continuations.
Haskell contains no HTTP or database handling.

## Layer 2 syntax and evaluation

`Layer2Syntax.hs` records pronouns, definite/indefinite descriptions, compound
attributions, single-property checks, and attribute questions. `Layer2Parser.hs`
exports `parseSentence` and `parseSentences`; `Grammar` re-exports both modules.
The parser retains arbitrary descriptor order and repetition, requires explicit
boundaries for descriptive property subjects, and requires destinations last.
See [Layer 2 Syntax](../../specification/controlled-english-layer2.md).

```haskell
:module + Grammar
either putStrLn (mapM_ (putStrLn . pretty)) $ parseSentences "Turn the cube large to green. What is the shape of it?"
```

Chat uses this parser and `evaluateEntry world ranking sentences`. Pronouns,
definite/indefinite descriptions, and compound updates now evaluate. Ambiguity
returns a `Pending` value containing the paused sentence, remaining sentences,
and candidate identifiers. `resumeEntry` continues without beginning a new entry.
See the [Layer 2 reference](../../specification/controlled-english-layer2.md)
for scoring, salience purging, clarification, and whole-entry Undo rules.
The console still uses the narrower atomic parser.
