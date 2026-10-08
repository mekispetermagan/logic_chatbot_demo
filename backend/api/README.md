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

- `POST /conversations` (no body): creates a random UUID conversation and its
  initial toy-world snapshot. Returns HTTP 201 and a `Location` header.
- `GET /conversations/{id}`: retrieves the latest stored world. Unknown UUIDs
  return 404; malformed IDs return 422.

Both return `conversationId`, `world`, `canUndo`, and ordered `messages`. World JSON has `width`,
`height`, and `objects`; each object has an integer `id`, nullable `shape`,
`size`, `color`, and nullable `position`. A present position requires integer
`x` and `y`, zero-based with A1 at the bottom left. Missing attributes mean
absent. The initial fixture is `backend/shared/toy_world.json`, matching the
current frontend toy scene; it is data, not Python world-update logic.

## Editing

All editing endpoints use `POST /conversations/{id}/...` and return
`conversationId`, `world`, `canUndo`, and concise `feedback`:

| Endpoint suffix | JSON body | Action |
| --- | --- | --- |
| `property` | `{"position":{"x":0,"y":0},"property":"red"}` | Apply one property; create on an empty square |
| `place` | `{"objectId":5,"position":{"x":0,"y":0}}` | Place an existing unplaced object |
| `erase` | `{"position":{"x":0,"y":0}}` | Remove the object on a square |
| `clear` | No body | Empty the world, including unplaced objects |
| `undo` | No body | Restore the previous snapshot |

Property options are `red`, `blue`, `green`, `yellow`, `small`, `medium`, `large`,
`cube`, `sphere`, and `pyramid`. Coordinates are zero-based, A1 = `(0,0)`.
The engine currently supports only 8×8 worlds. Placement preserves identity and
attributes, never creates, and requires an empty destination.

FastAPI sends the stored world and structured action to the Haskell executable.
Haskell owns world edits and semantic checks. `LOGIC_CHATBOT_ENGINE_PATH`
overrides the default `backend/logic_engine/bin/logic-engine-editor` path.
Calls time out after five seconds. Missing/broken engines return 503 without
changing history. Creation/retrieval and Undo work without the executable.

Malformed requests return 422; unknown conversations return 404. Blocked actions
(occupied destinations, coordinates outside the board) return 200 with the
unchanged world and feedback. Only changed worlds create snapshots. Each edit
is a SQLite transaction covering retrieval, evaluation, and persistence. Undo
retains the initial snapshot; editing after Undo starts a new history branch.

## Chat

`POST /conversations/{id}/chat` accepts `{"text":"#0 blue. #0 blue? color of #0?"}`.
It returns the current conversation state plus `feedback`, like editing calls.
Haskell parses the entire entry, then evaluates its atomic sentences in order.
Machine text includes each prettyprinted sentence and its update feedback or
answer. Parse errors leave the world unchanged and are saved as error replies.
Blank entries and malformed request bodies return 422.

`messages` contains ordered objects with `role` (`user` or `machine`), `text`,
and `isError`. Retrieval, editing, and Undo all return the existing messages.
Each submission saves the user/machine pair and at most one changed-world
snapshot together. Questions, parse errors, and entries whose final world equals
the starting world create no snapshot. Undo reverses a submission's world changes
together and retains messages. Engine failures save neither messages nor snapshots;
clients should refresh after a lost response rather than automatically resend.

`chat_messages` is created automatically on startup, including for existing
databases; conversation IDs and world history remain valid.

## Persistence

Flutter web development uses port 8080. CORS allows `http://localhost:8080` and
`http://127.0.0.1:8080` by default. Set `LOGIC_CHATBOT_CORS_ORIGINS` to a
comma-separated list of exact browser origins for other ports or deployment.
Android and Linux native clients do not require CORS configuration.

`LOGIC_CHATBOT_DB_PATH` sets the SQLite file location. The default is
`backend/api/data/conversations.sqlite3`, independent of the working directory.
Parent directories and tables are created during application startup. Each
conversation and its initial snapshot are inserted in one transaction.
`conversations` stores IDs and creation times; `world_snapshots` stores ordered
JSON worlds, starting at sequence 0. The latest snapshot is the current state.
`canUndo` becomes true when that sequence is greater than 0. Keep the database
file and its SQLite sidecars on persistent storage when deploying.

There is no authentication, cookie, shared conversation, or session expiry.
Clients will retain their conversation ID to resume after restart. The API
offers atomic-sentence chat. Semantic world validation and updates belong to Haskell;
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
