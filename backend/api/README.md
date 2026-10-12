# Demo conversation API

A small FastAPI application using Python's built-in SQLite library. Requires
Python 3.10 or newer. First build the editor from `backend/logic_engine/`:

```sh
cabal build exe:logic-engine-editor
mkdir -p bin
cp "$(cabal list-bin exe:logic-engine-editor)" bin/logic-engine-editor
```

Then run from `backend/api/`:

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
uvicorn app.main:app --reload
```

The real entry point is `app/main.py`; there is no root forwarding script or
packaging configuration. Interactive API documentation is at `/docs`.

## Endpoints

- `POST /conversations` with `{"domain":"objects"}` or `{"domain":"network"}`: creates a random UUID conversation and its
  initial toy-world snapshot. Returns HTTP 201 and a `Location` header.
- `GET /conversations/{id}`: retrieves the latest stored world. Unknown UUIDs
  return 404; malformed IDs return 422.

Both return `conversationId`, `domain`, `world`, `canUndo`, ordered `messages`, and nullable `pending`. World JSON has `width`,
`height`, and `objects`; each object has an integer `id`, a required `attributes`
map of canonical attribute/value strings, and nullable `position`. A present
position requires integer `x` and `y`, zero-based with A1 at the bottom left.
Absent attributes are omitted. Domain initial worlds live in
`backend/shared/toy_world.json` and `backend/shared/network_world.json`.

## Editing

All editing endpoints use `POST /conversations/{id}/...` and return
`conversationId`, `domain`, `world`, `canUndo`, messages, pending, and concise `feedback`:

| Endpoint suffix | JSON body | Action |
| --- | --- | --- |
| `property` | `{"position":{"x":0,"y":0},"property":{"attribute":"color","value":"red"}}` | Apply one property; create on an empty square |
| `ports` | `{"position":{"x":0,"y":0},"ports":["north","east"]}` | Replace network ports atomically, preserving color |
| `place` | `{"objectId":5,"position":{"x":0,"y":0}}` | Place an existing unplaced object |
| `erase` | `{"position":{"x":0,"y":0}}` | Remove the object on a square |
| `clear` | No body | Empty the world, including unplaced objects |
| `undo` | No body | Restore the previous snapshot |

Properties are explicit attribute/value pairs validated by Haskell. Objects use
color, size, and shape; networks use color and unary north/east/south/west ports.
JSON uses canonical names; aliases belong to chat. Invalid pairs return 422
without saving history. Coordinates are zero-based; both domains use 8×8 boards.
Placement preserves identity and attributes and requires an empty destination.

FastAPI sends the stored world and structured action to the Haskell executable.
Haskell owns world edits and semantic checks. `LOGIC_CHATBOT_ENGINE_PATH`
overrides the default `backend/logic_engine/bin/logic-engine-editor` path.
Calls time out after five seconds. Missing/broken engines return 503 without
changing history. Creation/retrieval and Undo work without the executable.

Malformed requests return 422; unknown conversations return 404. Blocked actions
(occupied destinations, coordinates outside the board) return 200 with the
unchanged world and feedback. Changes to world or discourse state create snapshots. Each edit
is a SQLite transaction covering retrieval, evaluation, and persistence. Undo
retains the initial snapshot; editing after Undo starts a new history branch.

## Chat

`POST /conversations/{id}/chat` accepts `{"text":"#0 blue. #0 blue? color of #0?"}`.
It returns the current conversation state plus `feedback`, like editing calls.
Haskell parses the entire entry, then evaluates its sentences in order using
[Layer 2 resolution](../../specification/controlled-english-layer2.md).
Non-final performatives require periods; questions always require `?`.
Chat also supports `remove`, `swap`, and `erase`/`delete` with references,
pronouns, or definite descriptions. Swap clarification may pause once per operand;
resolved operands are persisted without partial world changes. Layer 3 adds
relative movement, attribute copying, spatial questions, counts, and quantifiers;
see [Layer 3](../../specification/controlled-english-layer3.md). No extra editing
endpoint is needed.
Feedback includes each prettyprinted sentence and its changes or answer.
Parse errors preserve world and discourse and are saved as error replies.
Blank entries and malformed request bodies return 422.

An entry beginning with `undo` after optional whitespace, in any case, is checked
first by Haskell. Everything after the prefix is ignored. The engine returns
`undoRequested: true`; FastAPI uses the same Undo operation as the button,
restoring both world and salience and recording the chat reply atomically.
An Undo entry is also accepted by the API while clarification is pending.

`messages` contains ordered objects with `role` (`user` or `machine`), `text`,
and `isError`. Messages remain visible after Undo. Each submission saves a
user/machine pair and at most one paired world/salience snapshot. Questions can
create snapshots through salience changes. Engine failures save neither messages
nor snapshots; refresh after a lost response instead of automatically resending.

Ambiguity returns `pending` with `sentence`, canonical `remaining` entry text,
`candidateIds`, `candidates` (`objectId`, printable `label`), and
`resolvedSubjects` (already resolved operand IDs, defaulting to `[]`). Resume with
`POST /conversations/{id}/clarify`, body `{"objectId":3}`. Candidate selection
is evaluated by Haskell. An invalid choice leaves the pending state intact.
For square clarification, `pending.squareChoices` contains `{x,y}` positions,
`candidateIds` and `candidates` are empty, and resolved operand IDs are retained.
Resume with `{"position":{"x":3,"y":4}}` at the same `/clarify` endpoint.
Exactly one of `objectId` and `position` is required. Existing pending object
choices default to an empty `squareChoices` list. Haskell validates the selection.
Further ambiguity can pause again. All continuations replace the same entry
snapshot, so one Undo restores the complete pre-entry world and salience.
The choice and feedback are also recorded as chat messages.

While pending, ordinary chat/editor requests return 409. Clarification without a
pending entry also returns 409. Undo cancels the entry, including earlier partial
progress. Retrieval restores pending state and choices after restart.

Startup migrates old snapshots with empty salience and no pending entry; it
preserves existing world history and does not reinterpret old messages.

## Persistence

Flutter web development uses port 8080. CORS allows `http://localhost:8080` and
`http://127.0.0.1:8080` by default. Set `LOGIC_CHATBOT_CORS_ORIGINS` to a
comma-separated list of exact browser origins for other ports or deployment.
Android and Linux native clients do not require CORS configuration.

`LOGIC_CHATBOT_DB_PATH` sets the SQLite file location. The default is
`backend/api/data/conversations.sqlite3`, independent of the working directory.
Parent directories and tables are created during application startup. Each
conversation and its initial snapshot are inserted in one transaction.
`conversations` stores IDs, immutable domain identifiers, and creation times; `world_snapshots` stores ordered
JSON worlds, salience rankings, and nullable pending entries, starting at sequence 0. The latest snapshot is the current state.
`canUndo` becomes true when that sequence is greater than 0. Keep the database
file and its SQLite sidecars on persistent storage when deploying.

There is no authentication, cookie, shared conversation, or session expiry.
Clients will retain their conversation ID to resume after restart. The API
offers controlled-English chat. Semantic world validation and updates belong to Haskell;
Python schemas validate only the transport shape. Flutter calls these endpoints
for visual edits and uses the returned world, feedback, and `canUndo` state.

## Tests

```sh
python -m unittest discover -s tests -v
```

Tests use temporary databases and cover isolation, restart persistence,
initialization, rollback, database constraints, missing IDs, and partial objects.
Editing tests call the real Haskell executable, so build/copy it first using the
commands above. They cover all editing endpoints, history, blocked actions, and
engine failures. `LOGIC_CHATBOT_ENGINE_PATH` can select a test binary.

## Domain contract

Creation requires a domain identifier; `objects` and `network` are supported.
Missing or unsupported identifiers return HTTP 422 without creating a conversation.
Every conversation response includes `domain`. Editing, chat, clarification, and
undo inherit it from the conversation; clients cannot change it through those endpoints.
FastAPI forwards it in each Haskell request and checks the response identifier.
Startup migrates existing conversations to `objects`, preserving snapshots,
salience history, pending clarification, and messages. Undo restores state within
the same domain.

Startup also migrates all legacy world and salience snapshots to generic
attributes, transactionally and without clearing history. Flutter uses generic property pairs and atomic network port-pattern edits. See the
[JSON contract](../../specification/json-contract.md) for wire formats and migration details.
