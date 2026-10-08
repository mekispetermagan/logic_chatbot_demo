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
optional `on` for positions, and optional final periods. Adjacent performatives
must be separated by whitespace or a period. Squares A1-H8 map to zero-based
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
