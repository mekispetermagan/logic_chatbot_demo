# Cellular Automata Backend

## Implemented scope

The `cellular` domain uses the existing FastAPI application, anonymous
conversations, SQLite snapshots, save/load slots, Undo and Haskell executable.
The implementation supports data models, single forward generations, cell
painting and complete ruleset replacement. Flutter displays server state and
provides a local rule-editor draft. Cellular v2 adds dialogue, references,
connectivity, ruleset commands, spatial/color operations and bounded forecasts.
Regression, predecessor inference and historical timeline queries remain deferred.

## State and rules

Every square of the 16×16 toroidal board has exactly one color. The six canonical
color identifiers are `white`, `black`, `red`, `green`, `blue`, and `yellow`.
A ruleset activates any two to six distinct colors. Colors are identifiers,
independent of their ordering in the palette or a future display.

The world contains:

| Field | Meaning |
| --- | --- |
| `width`, `height` | Both exactly 16 |
| `topology` | `torus`; both axes wrap |
| `cells` | Exactly 256 color strings, A1 through P1, then A2 through P2, up to P16 |
| `ruleset` | Palette, neighborhood, and rules keyed by source color |
| `generation` | Nonnegative generation number; creation starts at 0 |
| `rulesetRevision` | Positive revision number; the preset starts at 1 |

For zero-based coordinates, `cells[x + 16*y]` is the color at `(x,y)`; A1 is
`(0,0)`. Cells have no object identifiers, absent attributes, or unplaced state.

Example ruleset:

```json
{
  "palette": ["white", "black"],
  "neighborhood": 8,
  "rules": {
    "white": {"targetColor":"black", "neighborColor":"black", "counts":[3], "enabled":true},
    "black": {"targetColor":"white", "neighborColor":"black", "counts":[0,1,4,5,6,7,8], "enabled":true}
  }
}
```

There is at most one rule per source color. Source, target and counted neighbor
color must be active, and target must differ from source. `counts` is a set of
distinct integers between zero and the neighborhood size. An empty set never
fires. A missing or disabled rule leaves the source color unchanged; disabled
rules must still be valid. Every cell color must be active.

Four-neighbor mode counts N/E/S/W; eight-neighbor mode adds the four diagonals.
Wrapping uses both axes: A1 has A2, B1, A16 and P1 as orthogonal neighbors, plus
B2, B16, P2 and P16 in eight-neighbor mode. No cell counts itself.

## Pure forward evaluation

`Domains.Cellular.Evaluation.step` validates an `Automaton` and returns either
an error or the next state and number of changed cells. Each cell reads the
same original board. If its enabled rule's neighbor count belongs to `counts`,
it takes the target color; otherwise it retains its source color. All changes
are synchronous. The generation increases by exactly one, including for a
stable board; palette, rules and ruleset revision are preserved.

Python validates transport/storage structure and consistency but does not
compute evolution. Haskell independently validates the input and owns all
forward transition semantics. There are no new solver dependencies.

## Initial Game of Life preset

New conversations start from the fixed fixture
[`cellular_world.json`](../backend/shared/cellular_world.json), with white cells
representing dead cells and black representing live cells. Eight neighbors and
the rules above implement standard B3/S23 Life.

The single glider has black cells at **I10, J9, H8, I8, J8**. All other cells are
white. After one step its black cells are **H9, J9, I8, J8, I7**, with four cells
changed. After four steps it is the original pattern translated one square
east and one square south, with wrapping when necessary.

## API contract

1. `POST /conversations` with `{"domain":"cellular"}` creates the preset and
   returns HTTP 201. `world` uses the cellular representation above; existing
   domains retain their object-list representation.
2. `POST /conversations/{id}/step` with no body (or `{}`) advances exactly one
   generation. Extra fields, including a step count or client-supplied state,
   are rejected with HTTP 422.
3. The normal editing response includes the complete updated `world`, `canUndo`,
   `changedCells` (0–256), and feedback such as `Generation 1: 4 cells changed`.
   A step does not add a chat message or call an LLM.
4. `GET /conversations/{id}`, `undo`, and the five save/load slots work through
   the existing endpoints. Each step, including a stable generation, is one
   undoable snapshot. Saving/loading captures the entire board, ruleset,
   generation and ruleset revision.

### Cell painting

`POST /conversations/{id}/cell` accepts
`{"position":{"x":0,"y":0},"color":"black"}`. Coordinates are zero-based
within 0–15. The color must belong to the current ruleset's active palette.
Haskell's `Domains.Cellular.Evaluation.paintCell` validates and replaces exactly
that cell. Invalid coordinates do not wrap, and inactive colors are rejected
with HTTP 422 without changing state. Other domains reject this action.

Painting preserves generation, palette, rules and ruleset revision. A changed
cell creates one undoable snapshot; repainting its existing color returns
`changedCells: 0` and `No change` without adding history. A changed cell returns
`changedCells: 1` and feedback such as `A1: white -> black`. Painting adds no
chat messages and does not call an LLM. It shares the normal persistence,
failure and reset-confirmation blocking behavior.

### Complete ruleset replacement

`POST /conversations/{id}/ruleset` takes `ruleset` (the complete palette,
neighborhood and rule map) and optional `refill` (a boolean, default false).
It accepts no world, generation, revision, or client-supplied random seed.
The normal ruleset validation applies even to disabled rules. Each source
color has at most one rule; missing or disabled rules retain that color.

Haskell validates the entire request before applying it. A rules-only change
preserves cells and generation and increments `rulesetRevision` once. If the
new palette excludes any existing cell color, `refill: false` returns HTTP 422
without changes. With confirmed `refill: true`, Haskell fills every square
randomly from the selected palette, resets generation to zero, and increments
the revision once. FastAPI supplies server-generated entropy; the Haskell
evaluator remains pure and reproducible for that seed. Refill permission does
not replace cells when all existing cell colors remain active.

An unchanged ruleset is a no-op, including equivalent binary-color rules
expressed using complementary neighbor counts. Such submissions preserve the
stored representation, revision and Undo history. Every actual ruleset change,
including a refill, is one snapshot. Undo and save/load restore cells, palette,
rules, generation and revision together. Persistence failures roll back the
whole operation. Ruleset submissions add no chat messages and do not call an LLM.

Unknown conversations return 404. Stepping another domain or using unimplemented
cellular actions returns 422. A missing/failed engine returns 503. Engine
evaluation and snapshot persistence are one serialized transaction; a failed
step cannot leave a partial generation. Existing reset-confirmation blocking
still returns 409 until answered.

The existing JSON bridge dispatches `domain: "cellular"` to its cellular module
with `action: {"type":"step"}` or
`{"type":"cell","position":{"x":0,"y":0},"color":"black"}`.
Ruleset replacement uses `{"type":"ruleset","ruleset":{...},"refill":false}`;
confirmed refills also carry an internal `randomSeed` supplied by FastAPI.
It uses `languageVersion: "cellular-v2"` for the
[Cellular v2 language](cellular-language-v2.md) as well as structured GUI actions.
`nextObjectId` remains zero. `salience` records typed coordinate mentions with
truth-checked cellular facts; `pending` can hold cell/grouping choices and a
provisional dense `stagedWorld` for an atomic batch.
The `changedCells` response field is nullable/unused for the other domains.

## Persistence and lifecycle

The existing `world_snapshots.world_json` and `world_slots.world_json` store
the complete cellular model, including any valid six-color ruleset. No separate
enumeration of possible rulesets or new database table is necessary. Existing
v2 databases are retained.

On API startup, existing 8×8 cellular snapshots and saved slots are expanded
to 16×16 in one transaction. Each old `(x,y)` becomes `(x+4,y+4)`, surrounded
by white cells. Rules, generation, revision, history order and saved timestamps
are preserved. White is added to custom palettes when absent. The migration is
idempotent and does not alter object/network worlds, which remain 8×8.

Confirmed `full reset` creates a new cellular conversation with the initial
Life preset at generation zero, since an automaton has no empty-board state.
Saved slots transfer unchanged; the reset has no Undo. Other domains retain
their existing full-reset behavior.

## Flutter player

The app-bar selector includes Cellular, using a dropdown on narrow screens.
Its 16×16 grid shares the other domains' coordinate frame, with A1 at the
bottom left. Single-select color buttons show the active palette, initially
white and black with black selected. Tap or left-click a cell to paint it;
right-click and long press do not edit. The color row scrolls horizontally when
needed, keeping a fixed height. The action row contains Step and the current generation; the five
save/load slots remain below it. Undo restores the previous server snapshot.
The controller owns selection and requests and disables editing/Step during requests.
Loading a palette without the selected color selects its first active color.
Stateless widgets receive the board and callbacks; evolution stays in Haskell.
Chat and LLM interpretation use the shared chat/review API. Commands, questions,
connectivity and bounded forecasts are implemented in Haskell. Random-operation
seeds are frozen in review proposals and continuation payloads, so repeated
previews and acceptance agree. The existing `full reset` flow remains available.

### Ruleset modal

Edit rules opens a modal with palette selection (at least two of the six
colors), Moore/von Neumann selection, and one rule row per selected source
color. Each row has an enabled toggle, a shared counted/target color, and
multiselect count buttons 0–8 or 0–4. Targets differ from the source color.
An empty count set never fires. Out-of-range counts left after switching to
four neighbors must be explicitly removed before submission.

Game of Life and RGB-cycle presets replace only the local form draft. Life
uses white-to-black with three black neighbors, and black-to-white with
0,1,2,3,4,7,8 white neighbors. RGB uses Moore neighbors and red→green,
green→blue, blue→red, each with 2–8 neighbors of the target color.
For binary stored rules, the editor converts complementary counts without
changing behavior. More general stored rules that count a third color require
explicit replacement in this simplified editor.

Only Submit sends the full ruleset. Palette changes that exclude board colors
first ask for random-refill confirmation. Canceling that question keeps the
draft open and sends nothing; canceling the editor leaves the world unchanged.
Submission disables the form and prevents dismissal until the response arrives.
An uncertain failed request requires closing the modal and refreshing the world
before retrying, so a random refill is not blindly repeated.

Run `cabal test cellular-tests` in `backend/logic_engine/` and
`python -m unittest discover -s tests -p 'test_cellular*.py' -v` in `backend/api/`.
The API checks use temporary databases and the real built Haskell executable.

## Controlled language and review

`POST /conversations/{id}/chat` accepts Cellular v2 through the existing body
`{"text":"Does the board reach a fixed point within 100 generations?"}`.
The optional `useLlm` switch proposes translations for review, using a separate
cellular interpreter configuration/session. No new chat endpoint is needed.
Commands require a period; questions require `?`. For example:

```text
Set color of cells connected to A3 to black.
Advance 20 generations.
After 20 generations, how many cells match color is black?
What is the stabilization time of the board within 100 generations?
```

Forecasts leave configuration, rules and generation unchanged. Stabilization is
a fixed point, not periodic recurrence; already stable means offset zero.
Advances and temporal bounds are capped at 256 generations, with a 4096-transition
entry work budget. Resource exhaustion is a diagnostic, never a negative answer.
One chat entry, including its clarification rounds, is one complete Undo unit.
Cellular reference choices use `position`, including P16; grouping choices use
`groupingId`. Existing persisted worlds and slots are retained.

Run `cabal test cellular-language-tests` and the API `test_cellular_language`
suite for syntax, temporal semantics, references, atomicity and persistence.
