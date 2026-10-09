# Controlled English: Layer 2

Status: syntax and demo evaluation implemented October 10, 2026.
Layer 1 is the atomic core, Layer 2 adds pronouns/descriptions, and Layer 3 will
add derived terms. See the [core reference](controlled-english-core.md) for the
ontology and existing evaluation.

## Entry boundaries

Every performative requires a period unless it ends the user entry. Every
question requires `?`, including the final question. Whitespace alone does not
separate sentences. Words and coordinates are case-insensitive. The complete
entry is parsed before anything is evaluated.

```text
#3 red. #3 cube. Is #3 red?
It is large. The red cube is small
```

## Subjects

| Kind | Examples | Performatives | Questions |
| --- | --- | --- | --- |
| Identifier | `#23` | Yes | Yes |
| Square | `A4` | Yes | Yes |
| Pronoun | `it` | Yes | Yes |
| Indefinite | `a cube`, `a red`, `red cube` | Only with a destination | No |
| Definite | `the cube`, `the large cube`, `the red` | Yes | Yes |

Descriptions contain one or more color, size, or shape descriptors. Order is
arbitrary and repetition is preserved: `a cube red cube`, `the red red cube`.
An indefinite article can be omitted. Optional terminal `one` is accepted for
either description kind, including `a red one` and `the cube one`.

## Performatives

A predicate contains one or more color/size/shape values, an optional destination,
or a destination alone. There is at most one destination and it comes **last**.
Optional predicate article `a` is decoration, not another subject.

```text
#23 is a cube.
#23 is a red.
A4 large blue sphere.
A4 is a red cube on B3.
It is small red.
It to A4.
```

`is` is optional for identifier, square, and pronoun subjects. For description
subjects followed by property descriptors, `is` or `to` is compulsory. A
position-only predicate is already distinguishable by its coordinate or marker.

```text
The cube is large green.
The cube large is green.
The cube on A4.
A red cube on A4.
Cube A4.
A red cube is large on B3.
```

An indefinite performative must include a destination. Optional `move` introduces
a position-only predicate; optional `turn` introduces at least one property
descriptor, optionally followed by a destination.

```text
Move it to A4.
Move the red cube on A4.
Turn it red.
Turn it to a cube.
Turn the cube large to green.
Turn A4 a red.
Turn A4 to a large blue sphere on B3.
```

Repeated or conflicting predicates evaluate in their original order after the
subject is resolved once. The last value of an attribute wins; the destination
is applied last. A blocked movement preserves earlier property updates.

## Property checks

A check tests **exactly one value**: color, size, shape, or position. Indefinite
subjects and the performative verbs `move`/`turn` are not accepted.

```text
B3 red?
It on A4?
The large cube is red?
Is it red?
Is the large cube red?
Is #3 on A4?
```

Subject-first definite checks need `is` or `to` before a non-positional property.
Position checks may use a coordinate or `on`; positional `to` remains
performative-only, so `it to A4?` is rejected.

In inverted checks, the single final property fixes the boundary. Thus
`Is the large cube red?` checks red of subject `the large cube`.
`Is the cube red green?` is also accepted, but checks green of subject
`the cube red`; it does not check two values.

`B3 red green sphere?` and `the cube is red green?` are rejected.

## Attribute-value questions

Attributes are `color`, `size`, `shape`, `position`, `row`, and `column`. All
non-indefinite subjects are allowed. Full, shorthand, and natural forms work:

```text
Color of it?
Shape of the red cube?
The red cube color?
The red one is size?
What is the shape of the red cube?
What is shape of it?
```

The natural form is `what is [the] attribute of subject?`. Attribute-first forms
require `of`. The optional article before the attribute is distinct from a
definite subject's article after `of`.

## Unambiguous boundaries

`the cube large green` is rejected because it lacks a subject/predicate boundary.
`The cube is large green.` and `The cube large is green.` are distinct parses.

`the red cube red cube on A4` is accepted as one repeated-description subject
and one position predicate. It cannot mean two whitespace-separated sentences.
The parser enumerates legal boundaries and accepts only one complete parse;
multiple complete parses produce an ambiguity error rather than a greedy choice.

## Parser and prettyprinting

`Layer2Syntax.Subject` distinguishes `Reference`, `It`, `Indefinite`, and `Definite`.
`Layer2Syntax.Sentence` distinguishes compound `Attribution`, single-value `Check`,
and attribute `Query`. Lists preserve descriptor order and repetition.

`Layer2Parser.parseSentence` parses one sentence; `parseSentences` parses a whole
nonempty entry. Both return `Either String ...` and are re-exported by `Grammar`.
`AtomicParser` remains available for narrow atomic syntax, with the new punctuation.

In `cabal repl`:

```haskell
:module + Grammar
either putStrLn (mapM_ (putStrLn . pretty)) $ parseSentences "Turn the cube large to green. What is the shape of it?"
```

Prettyprinting uses explicit `is`, `on` for positions, and
`attribute of subject?` for value queries. It prints indefinite articles and
omits decorative `one`, `move`, and `turn`. `Turn A4 to a cube` prints as
`A4 is cube.`. Prettyprinted syntax parses back to the same syntax tree.

## Reference resolution and evaluation

`Layer2Evaluation.evaluateEntry world ranking sentences` returns the final world,
salience ranking, optional pending clarification, and printable feedback.
`resumeEntry world ranking pending identifier` continues the same entry.
`Grammar` re-exports both functions. For example, in `cabal repl`:

```haskell
:module + Grammar
either putStrLn (\sentences -> let (w, r, pending, feedback) = evaluateEntry world [] sentences in putStrLn feedback >> putStrLn (pretty w) >> print r >> print pending) $ parseSentences "#0 red. It is a cube. What is the color of it?"
```

Identifiers and squares keep the core resolution rules. Missing identifiers or
empty squares create partial objects only in performatives. An indefinite
creates a fresh object, applies its descriptive properties, then its predicate.
Creation happens before destination validation, so a blocked move can leave a
new unplaced object. Questions never create objects.

`it` selects the most recent eligible object mention. A definite description first
looks for compatible recent mentions, combining separate mentions of the same
object when needed. If none qualify, it searches the world: exactly one matching
object resolves; several require clarification; none produce a short diagnostic.
Neither `it` nor a definite description creates an object when resolution fails.
Missing referents produce feedback and evaluation continues with the next sentence.

A resolved compound attribution becomes an ordered sequence of atomic updates
on the same identifier. Checks test one value; an absent property is false.
Value queries return the value or `none`. Feedback includes the parsed sentence
in canonical form, followed by concise changes or an answer.

## Salience ranking

`Discourse.SalienceRanking` is a list of `((entryAge, utteranceAge), id, properties)`
records. Lower ages mean more recent. The current entry (0) and previous
three entries (1–3) are retained. Utterance age 0 denotes the latest completed utterance;
2 denotes three utterances ago when resolving the next utterance. Separate
mentions of an object are retained.

Every successfully resolved performative or question registers a mention.
Associated properties include descriptive subject properties, attributed/tested
properties, or the returned query value; an empty list still records the object.
After evaluation, false properties are removed from all mentions; deleted objects
are removed entirely. Thus asking whether a blue object is green does not make
it an antecedent for `the green`. A property's removal does not erase the object
mention itself. Visual edits purge stale mentions but do not add chat mentions.

For a definite description, each distinct descriptor uses its most recent
matching mention. Its demo score is `10 * entryAge + utteranceAge`; sum the
scores for the descriptors. Candidates within less than `n + 1` of the best
score are tied, where `n` is the number of distinct descriptors. Compare all
candidates directly with the best, without chaining ties. Repeated mentions of
one identifier do not create ambiguity. Pronouns use the most recent age pair;
different identifiers at that same pair require clarification. This heuristic
is deliberately simple and may be revised after the demo.

## Clarification and Undo

Ambiguity pauses immediately before that sentence. Earlier updates and mentions
remain visible, while that sentence and the remainder wait. Flutter displays
explicit candidate buttons; selecting one resumes from the paused state and
can encounter another ambiguity. New chat entries and visual edits are disabled
while pending. Undo remains available and cancels the pending entry.

FastAPI stores **history of paired world and salience snapshots**, including
pending continuations. One user entry is one Undo unit across all clarification
rounds. Undo restores its complete pre-entry world and salience; chat messages
remain visible. Questions can therefore be undoable without changing the world.
The shared Undo button is in the app bar, available from either panel.

Existing database snapshots acquire empty salience automatically; older chat
messages are not reinterpreted to invent historical mentions. Pending entries
and their candidates survive restart. The console remains an atomic-only
experiment; the demo uses the API chat loop.
