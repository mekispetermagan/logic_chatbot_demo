# Optional LLM Translation

Status: implemented with ranked proposals and explicit user acceptance.
The default interpreter now uses saved agents and persistent sessions; see
[Persistent Interpreter Agents](agent-sessions.md) for configuration, memory,
accounting and failure behavior. The earlier Responses transport remains an
explicit fallback via `LOGIC_CHATBOT_LLM_BACKEND=responses`.
The app-bar switch defaults to off on app start.
It sends `useLlm` on each chat entry; it never changes another client's setting.

## Request flow

1. With the switch off, chat follows the existing Haskell path.
2. With it on, Haskell checks the entire entry's syntax without evaluation.
   Valid entries, Undo, and semantic failures do not invoke the model.
3. A syntax failure can invoke GPT-6 Luna with the active domain's grammar,
   examples and current world. In Agents mode, conversation context persists in
   the remote session; salience rankings remain local to Haskell.
4. The model returns up to three distinct readings ranked by plausibility, each
   with a label, a complete controlled entry and a brief explanation of its
   assumptions. Multiple readings require a targeted clarification question.
   Missing essential information can produce a question without candidates.
   Clear requests can produce one reading; no alternatives are fabricated and
   there are no numeric confidence thresholds.
   A separate `reply` field provides brief, unmistakable courtesy or a neutral
   scope decline. Reply-only `conversation` results appear directly in chat,
   with no syntax-error feedback, review proposal or symbolic state changes.
   Mixed entries retain their task in candidates/questions. The agent's reply
   text is never sent to Haskell for evaluation. With the LLM switch off, strict
   controlled-English behavior remains.
5. Haskell syntax-checks every candidate. Invalid candidates and duplicates with
   identical canonical text are removed, preserving the remaining order.
   Parser failures remain visible with the rejected program and Haskell's
   reason. An invalid program is labelled a translation failure, separately
   from any clarification question. The original prompt, paid-attempt metadata
   and review proposal are saved, but **no world or salience changes are applied**.
   If there is no candidate, question or parser failure to review, the original
   syntax error remains. For
   `unsupported`, the model's reason is shown as `LLM explanation: ...` and
   persisted in the machine message. It is normalized to one line, limited to
   400 characters, and credentials are redacted; it is model-authored feedback.
6. The user selects a ranked reading and chooses Preview, Accept or Reject.
   Preview runs Haskell on temporary state and shows the trial board and
   feedback marked “Preview — not applied”. Accept evaluates the stored
   candidate and commits it. Reject discards the proposal and restores the
   original prompt in the input field for revision and resubmission.
   When clarification is needed, the input stays enabled with **Submit answer**.
   Answers request a fresh proposal using the original entry, previous question,
   candidates, parser failures and accumulated answers; they never execute a
   translation. Each submitted answer is a new bounded, budgeted GPT call.
7. Before saving a proposal, and again before preview/accept, the repository
   checks the world, discourse state and message revision. Changed state returns
   HTTP 409; a stale proposal can still be rejected. No model call is retried
   automatically, and its charge remains in the independent ledger.

The LLM proposes interpretations; Haskell owns reference resolution, queries and
world updates. A valid translation can still misunderstand the user, so even
one candidate or a translated question requires acceptance. Existing
object/square clarification can pause evaluation after acceptance; its preview
is temporary and reports that clarification will be needed. All evaluation and
continuations from one accepted entry share one Undo snapshot. Undo restores
world and salience together and does not undo API charges.

While review is pending, editing, Undo and unrelated chat are blocked for that
conversation. Answer the question in the composer, or reject to edit the
original prompt. Failed validation also allows a correction via Submit answer.
Other conversations remain independent. SQLite stores pending and archived
proposals separately from world history, so review survives refresh/restart.
Preview is ephemeral and changes neither snapshots nor chat messages; choosing
another candidate or refreshing clears it. Acceptance/rejection adds a machine
message without adding a fake user prompt. Preview, Accept and Reject call only
the local engine/database and incur no additional GPT charge.

## Prompt and transport

`app/agent_instructions.py` assembles the reviewed common/domain instructions
from `docs/agent-instructions-draft.md`, the active standalone
[Objects v2](object-language-v2.md), [Network v2](network-language-v2.md) or
[Cellular v2](cellular-language-v2.md) reference, and
`backend/api/prompts/examples.json`. Both transports use that contract.
There are 184 object, 214 network and 120 cellular examples; tests validate every
translation with the real Haskell parser. The short files under `prompts/` point
to these authoritative sources rather than defining another grammar.

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
uses the active domain's world contract. Objects and Network include dimensions
and objects with identifiers, attributes and nullable positions; x=0/y=0 denotes
A1. Unplaced objects occupy no square. Cellular supplies its dense cell colors,
ruleset, generation and ruleset revision instead. The model may select targets by snapshot data, while pronouns and definite
references remain for Haskell. Coordinates denote locations; explicit occupant references edit existing nodes,
and explicit creation introduces a new identity. Missing references never create
objects. The complete world payload
is included in token counting before generation.

In Responses mode, follow-up requests add `clarification`, containing ordered question/answer
`turns`, `previousCandidates` and `validationFailures`. The original `entry`
remains unchanged. The same full input is counted before each generation, so
growing clarification context stays within the existing token and cost caps.
Context is explicitly supplied with each fresh request, as supported by the
[official OpenAI conversation-state documentation](https://developers.openai.com/api/docs/guides/conversation-state).
Provider failures replace the old candidate set with a failure draft, preserving
the original request and answers; they never apply or silently reuse an old plan.

Questions must retain their meaning. Returning several checks cannot replace
one question requiring an unsupported logical or arithmetic combination. The
translator neither answers it itself nor substitutes a weaker intermediate query.

In the optional `responses` transport, FastAPI uses HTTPX and the OpenAI Responses API with strict structured JSON,
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

The ledger uses integer nanodollars. The following caps and exact-count settlement
describe the optional Responses transport; Agents uses the accounting described
in [Persistent Interpreter Agents](agent-sessions.md).
Rates verified October 17, 2026, per million
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
`GPT reply` includes the model's structured status, ranked candidates, question, explanation,
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
failures, parser feedback and proposal/preview/accept/reject events are also recorded. The transcript has no console
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
