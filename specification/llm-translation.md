# Optional LLM Translation

Status: implemented first stage. The app-bar switch defaults to off on app start.
It sends `useLlm` on each chat entry; it never changes another client's setting.

## Request flow

1. With the switch off, chat follows the existing Haskell path.
2. With it on, Haskell checks the entire entry's syntax without evaluation.
   Valid entries, Undo, and semantic failures do not invoke the model.
3. A syntax failure can invoke GPT-6 Luna with the active domain's grammar,
   examples and current world. Salience rankings and chat history are not sent.
4. The model considers alternatives but returns one clearly supported controlled
   entry, potentially containing several planned commands, or `unsupported`.
   There are no numeric confidence thresholds.
5. Haskell validates the complete proposed entry before evaluation. If valid,
   the original user text and visible `Interpreted as: ...` feedback are saved.
   Otherwise the original syntax error remains, with a short explanation. For
   `unsupported`, the model's reason is shown as `LLM explanation: ...` and
   persisted in the machine message. It is normalized to one line, limited to
   400 characters, and credentials are redacted; it is model-authored feedback.
6. Before applying a valid translation, the repository checks the world,
   discourse state and message revision inside its write transaction. A changed
   conversation returns HTTP 409 with a retry instruction. The model call is not
   retried automatically, and its charge remains in the independent ledger.

The LLM translates; Haskell owns reference resolution, clarification, queries
and world updates. A valid translation can still misunderstand the user; this
stage does not present translation alternatives. Existing object/square
clarification works normally, without another model call. All evaluation from
one entry shares one Undo snapshot. Undo does not undo API charges.

## Prompt and transport

`backend/api/prompts/shared.md` defines the translation task and common syntax.
`objects.md` and `network.md` define domain vocabulary and operations.
`examples.json` contains 142 object-domain and 191 network-domain examples;
tests validate every example translation with Haskell's parser.
The prompt permits general knowledge, coordinate calculations, ordered
assignments and creative composition of supported operations. No live web tools
are provided. Examples illustrate syntax without enumerating all possible goals.
Preparatory updates needed for the requested goal are allowed; unrelated updates
or unrequested clearing are not. Existing object references stay symbolic.

The network prompt explains path creation, endpoint ports and deterministic
north/east/south/west search order. Limits on a single command do not prohibit
goals achievable with sequences, including intermediate points and closed shapes.
Explicit constraints must be preserved by that composition. The current world
lets the model inspect occupancy, attributes and positions when planning. Haskell
still determines feasibility, and a valid translation can still be a poor plan.

The Responses user message contains JSON with `entry` and `world`. The latter
uses the existing world contract: dimensions and objects with identifiers,
attributes and nullable positions; x=0/y=0 denotes A1. Unplaced objects occupy no
square. The model may select targets by snapshot data, while pronouns and definite
references remain for Haskell. Coordinate assignment edits an occupied cell;
indefinite creation always introduces a new object. The complete world payload
is included in token counting before generation.

Questions must retain their meaning. Returning several checks cannot replace
one question requiring an unsupported logical or arithmetic combination. The
translator neither answers it itself nor substitutes a weaker intermediate query.

FastAPI uses HTTPX and the OpenAI Responses API with strict structured JSON,
`gpt-6-luna`, Standard (`default`) service tier, low reasoning, no tools,
`store: false`, and no automatic retries or previous response IDs. Input is
counted with `/v1/responses/input_tokens`, including instructions and schema,
before generation. The complete input limit is 20,000 tokens and the output
limit is 2,000 tokens including reasoning. Each HTTP operation times out after
30 seconds; Flutter gives opted-in chat requests 90 seconds and never retries.

## Persistent $1 experiment budget

The total budget is **USD 1 across all requests, conversations and domains**,
persisted in the application's SQLite database. It does not reset with app/API
restart, Undo, Clear, or creation of a new conversation. There is no public reset
endpoint. Deleting/changing the database also changes its accounting history.

The ledger uses integer nanodollars. Rates verified October 17, 2026, per million
tokens: uncached input $0.10, cached input $0.01, cache writes $0.125, output $0.50.
It reserves $0.0035 before each generation: maximum input at the cache-write
rate plus maximum output. A serialized SQLite transaction prevents concurrent
reservations from exceeding $1. Generation is refused if its maximum cost no
longer fits, even if a small balance remains.

Reported input, cached, cache-write, total output and reasoning counts are
recorded, with reasoning included in output rather than charged twice. Reported
usage settles the reservation at the calculated token cost, including invalid,
unsupported or incomplete translations. If the response/usage is unavailable,
the maximum reservation stays counted indefinitely; it is never assumed free
or automatically retried. Ledger transactions are separate from world/message
persistence, so rolling back a conversation does not refund a paid attempt.

Chat shows request cost and the global spent/reserved totals. These are local
calculations using the published rates, not the provider's invoice. The guard
covers this app at these rates, not unrelated account usage or future rate changes.
Compare with the OpenAI usage dashboard when enabling live calls.

## Configuration

Set the **secret** `OPENAI_API_KEY` in the API server's environment. It is never
sent to Flutter, stored in SQLite, or printed in feedback. Without it, controlled
English still works, and failed syntax receives an LLM-not-configured note.
See the backend README for a hidden terminal prompt. Tests use mocked HTTP
responses and do not contact OpenAI or consume paid API tokens.

## GPT feedback logs

The Uvicorn terminal shows INFO records from `uvicorn.error.llm` by default:
`GPT reply` includes the model's structured status, translation, explanation,
response ID, token usage and calculated cost. `GPT parser rejection` records the
rejected translation and Haskell's parser feedback. Invalid model JSON and
incomplete responses have separate records. These are final model outputs, not
hidden reasoning. Lines are limited to 20,000 characters with credentials
redacted and control characters escaped; prompts, worlds and HTTP headers are
not logged. No separate log file or configuration is required.

The API additionally creates `backend/api/logs/gpt-conversation.jsonl` at startup
and appends the complete future HTTP exchanges there. `LOGIC_CHATBOT_LLM_LOG_PATH`
can select another location. The default logs directory is ignored by Git and
new transcript files have mode 0600. Records contain UTC timestamps, events,
conversation IDs and attempt IDs. Token-counting and generation requests include
their complete headers and JSON bodies: instructions, examples, world snapshot,
entry and parameters. Responses include status, headers and complete bodies,
including errors and all metadata actually returned by the provider. Transport
failures and parser feedback are also recorded. The transcript has no console
length cap, and is preserved across reloads and restarts.

Authentication/credential fields, the configured API key and OpenAI-style keys
in text are redacted, including encoded JSON message contents. This file records
only what is actually exchanged; it cannot recover earlier prompts/responses or
hidden reasoning unavailable from the API. Transcript I/O failures emit a warning
without failing an otherwise successful model call or world edit.

Failed calls report their processing stage and, for HTTP errors, status plus
recognized error codes and parameter names. Server warning logs also include a
validated `x-request-id` when available, following the official
[request debugging guidance](https://developers.openai.com/api/reference/overview#debugging-requests).
Provider messages, raw bodies, exception text and credentials are excluded;
unrecognized diagnostic fields are omitted. Diagnostics do not change retries,
world updates or budget reservations.

References: [model and rates](https://developers.openai.com/api/docs/models/gpt-6-luna),
[token counting](https://developers.openai.com/api/docs/guides/token-counting),
[structured output](https://developers.openai.com/api/docs/guides/structured-outputs).
