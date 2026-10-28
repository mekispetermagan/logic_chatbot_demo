# Persistent Interpreter Agents

The default LLM transport is the OpenAI Agents API, using GPT-6 Luna. Haskell
still checks syntax first, owns all evaluation, and applies only accepted
proposals. Flutter's API and Preview / Accept / Reject / Submit answer flow are
unchanged. Set `LOGIC_CHATBOT_LLM_BACKEND=responses` to explicitly use the earlier
stateless transport; there is no automatic provider/model fallback.

## Setup for a fresh clone

No agent IDs or API keys are shipped in the repository. SQLite and `.env` are
local, Git-ignored files. A fresh clone uses agents created under the OpenAI
project accessible to its own configured `OPENAI_API_KEY`, not the author's agents.
The key must have access to the configured model and Agents read/write operations.

1. Follow the [root quickstart](../README.md#ubuntulinux-quickstart), save your own
   key in `backend/api/.env`, export it in the backend terminal, and start Uvicorn.
2. Select Objects, enable the LLM switch and submit ordinary language, for example
   `Please make the object at A1 blue`. The first interpretation automatically
   creates the Objects agent from the common policy, Objects instructions,
   Objects v2 reference and validated examples.
3. Select Network and submit `Please make the object at A1 blue` with the LLM
   switch enabled. This independently creates the Network agent using its own
   instructions, Network v2 reference and examples.
4. Select Cellular and submit `Please paint A1 black` with the LLM switch enabled.
   This creates the Cellular agent with its instructions, Cellular v2 reference
   and examples. A separate session is created for each conversation.
5. Configure the optional Calendar MCP connection, select Calendar, enable its
   LLM switch and submit `Find a free half hour on Thursday morning`. This creates
   the Calendar agent/session using the same configured key and shared budget.
6. Review the returned proposal. Preview and Accept use Haskell; neither manual
   dashboard setup nor copying agent IDs into configuration is necessary.

Direct controlled English bypasses the interpreter, so it does not provision an
agent. Only domains actually used for LLM interpretation need remote agents.
Check the backend's `agent configured` log for the new ID and domain, and the
usual proposal/usage feedback for a completed interpretation. Setup/transport
errors remain explicit. Without a key, all controlled-English features work.
These examples request normal model turns under the shared admission budget;
they are not free connectivity probes. The optional Responses backend does not
create or use saved agents.

## Recreate agents or change account/project

Saved IDs belong to the local database, not to the source checkout. If you reuse
a database with a key for a different project/account, or its remote agents or
sessions have been deleted or become inaccessible, explicitly recreate the local
associations. Replacing a key with another key for the same project does not
require recreation if it retains access to the existing resources.

Stop the backend first and wait for any active request to finish. From
`backend/api/`, with `.venv` active and the same database configuration used by
Uvicorn, run one of:

```bash
python -m app.agents recreate --domain objects
python -m app.agents recreate --domain network
python -m app.agents recreate --domain cellular
python -m app.agents recreate --domain calendar
```

For a project/account change, use all domains:

```bash
python -m app.agents recreate --domain all
```

This local-only command detaches the selected saved agent IDs and all local
session associations for conversations in those domains, in one transaction.
It rejects active affected interpreter leases and leaves other domains alone.
Replacements are created lazily on the next LLM request for each selected domain,
with a new session for each conversation when next used. Repeating the command
before that request is harmless. The command honors `LOGIC_CHATBOT_DB_PATH`,
requires an existing current-schema database, and does not load `.env` itself.

Worlds, salience, chat, pending review/clarification, Undo, saved slots, queued
outcomes, and all usage/reservations remain unchanged. A new session receives
the authoritative world, bounded queued outcomes and explicit clarification
context; it does not recover the old remote session's full memory. The command
does not invoke the provider, need a key, or reset the budget. It does not delete
old remote agents or sessions, cancel uncertain remote turns, or undo their costs.

After a key/project change, edit `.env`, reload/export it in the backend terminal,
then restart Uvicorn. Reload the same custom `LOGIC_CHATBOT_DB_PATH` if set.
Use an ordinary request with the LLM switch enabled to verify each domain you
need. Do not delete the database to repair agent access: that also removes local
worlds and accounting. Attaching externally managed agents by ID is unsupported;
the application owns configuration assembled from the versioned local sources.

## Instructions and saved agents

The board-domain agents receive their standalone v2 language references: [Objects v2](object-language-v2.md)
with 184 validated examples, [Network v2](network-language-v2.md) with 214,
or [Cellular v2](cellular-language-v2.md) with 120. Calendar uses its v1 contract
and sources described [below](#calendar-interpreter).
Both transports assemble the same reviewed instructions for their active domain.
Explicit creation, location/occupant distinctions, identity versus appearance,
and consequential graph-scope alternatives are part of those contracts.

[`agent-instructions-draft.md`](agent-instructions-draft.md) is the approved
instruction source despite its original filename. `app/agent_instructions.py`
assembles common policy, one domain section, its standalone grammar and its
examples. It excludes maintainer assembly notes and the other domains’ languages.

The original object/network v2 release required a fresh local database and
discontinued pre-v2 agent/session metadata, conversations and continuations.
Current v2 databases and sessions are retained across startup, including when
Cellular is added or older cellular boards are expanded to 16×16. Unsupported
schema versions are rejected unchanged. Agents are configured lazily on the
next LLM request.

On the first LLM use of each domain, FastAPI creates a saved agent and stores its
ID and assembled configuration hash in `llm_agents`. The configuration fixes
the model to `gpt-6-luna`, uses low reasoning and Standard service tier, and
constrains final text to the existing proposal JSON schema. No tools, subagents,
hosted sandbox or web search are enabled in this stage.

Editing the instruction source, examples or output configuration changes the
hash. On next use, the backend updates the same saved agent ID and starts a new
session for affected conversations. Existing world, salience, chat, proposal,
Undo and cost histories in SQLite remain intact. Instructions are not uploaded
on every chat request. Dashboard edits are not a substitute for updating the
versioned local source.

## Sessions and state

Each conversation gets its own session on its first LLM use. `llm_sessions`
stores its remote session ID, agent ID, configuration hash, last completed turn
and outcome cursor. Restarts reuse those records. Different domains and
conversations never share a session.

The first request creates a session with its saved agent ID and initial input;
later requests submit input-message events to that session. Each input contains
the current world, the entry and backend outcomes not yet sent to the session.
Clarification requests also carry the original prompt, accumulated answers,
previous candidates and parser failures. The remote session manages its own
conversation context and compaction rather than receiving a reconstructed full
history on each request. SQLite retains the application's complete local history;
only queued backend outcomes are sent, subject to the bounds below.

### Bounded outcome context

`app/agent_context.py` prepares the input without changing stored history.
Consecutive successful GUI results with no user text, translation, error or
pending choice are coalesced into one outcome with their count and the final
update's feedback. Commands, acceptance/rejection, Undo, slot loads, errors and
clarification remain separate events.

Each request retains at most the newest 64 resulting outcome entries. Older
whole entries are omitted as needed to fit the existing 40,000-byte UTF-8 input
limit. `historySummary` reports how many GUI events were coalesced, how many
original events were omitted and their kinds. The agent is instructed to use
the current world, avoid inventing missing history and clarify when it matters.
Programs and feedback are never cut into misleading partial sentences.

The current world, user entry and clarification are always complete. If these
alone exceed the limit, the backend rejects the request before agent setup or
spend reservation. Outcome compaction applies on first use, session reuse and
session replacement, including conversations with large pre-existing backlogs.
Only transport context is bounded: SQLite outcome records, chat, worlds, Undo
history and saved slots are retained. The outcome cursor advances across the
complete fetched range after the remote turn is observed, including entries
represented by summaries or omission counts. Failed admission and uncertain
turns do not advance it; a subsequent request can compact that backlog again.

`llm_session_events` is a durable outcome queue. Accepted programs, rejection,
direct controlled-English evaluation, visual edits, reference clarification,
Undo and parser rejections are recorded in the same transactions as their
local changes. They reach the agent on its next requested interpretation; none
starts an extra paid turn by itself. Preview stays temporary. A submitted
proposal or clarification answer does not establish a world change.

The latest supplied world always overrides remembered state. Haskell's salience
ranking still resolves `it` and definite descriptions; it is not replaced by
model memory. New sessions after instruction changes start with the current
world, queued outcomes and any explicit pending-clarification context. They do
not replay the old remote session's complete conversation.

## Turn completion and failures

Final JSON contains `status`, `reply`, `candidates`, `question` and `explanation`.
The domain-independent `reply` field is reserved for brief conventional courtesy
and neutral scope declines. Instructions require certainty that a reply-only
entry contains no task or clarification answer; uncertainty stays in the task
interpretation/clarification flow. Gossip, political/news discussion and other
substantive unrelated topics receive a brief decline without discussion. A
mixed greeting/task keeps the task in the candidate fields.

Reply-only `conversation` results display immediately as chat messages, without
a review proposal, Haskell evaluation, salience aging or Undo snapshot. Courtesy
during an interpretation clarification preserves its question and candidate
choices. Every LLM turn is still logged and accounted for. Other statuses may
include a short `reply` with their task-specific content. Haskell never receives
the agent's `reply` field; the existing read-only syntax probe of raw user input
is unchanged. No frontend contract change is needed.

The backend follows turn status and reads only completed `final_answer` messages
from that turn, including paginated items. Commentary and older-turn outputs
cannot become executable proposals. Completion alone does not apply anything:
the returned entry still passes Haskell validation and user review.

Short SQLite leases prevent simultaneous LLM submissions to one conversation
and simultaneous configuration updates for a domain. Network operations occur
outside world-write transactions. Existing revision checks reject proposals if
the conversation changed during inference. A still-running remote session
returns HTTP 409 rather than accepting a second input as steering.

Requests have a total 65-second deadline and per-operation timeouts up to 30
seconds. Uncertain turns are cancelled when their session ID is known; user
input is never automatically resubmitted. Transport/model/permissions failures
remain explicit errors. There is no silent switch away from Luna.

## Accounting and logging

The global $1 admission guard and durable usage ledger remain independent of
Undo. Each submitted agent turn reserves $0.0035; reported turn usage settles
the reservation. Unknown usage leaves it reserved and the UI shows cost unknown.
Failure and cancellation do not imply a refund.

Agents provides best-effort turn usage and no separate cache-write count. Local
estimates therefore use the higher cache-write rate for noncached input. These
are conservative estimates of the reported token usage, not final invoices;
recorded counts can later change. The previous Responses-specific 20,000-input
and 2,000-output caps are not Agents configuration fields. Agent inputs sent by
this app are limited to 40,000 UTF-8 bytes; the managed session controls its
history/compaction and generated length. Consequently the $1 guard blocks new
turns based on accounting/reservations, but cannot guarantee a hard provider
spending ceiling for an in-flight managed turn.

The existing credential-redacted JSONL transcript records saved-agent setup,
session creation, follow-up inputs, polling, paginated output, cancellation and
usage. Console feedback includes session/turn IDs and structured proposals.
No API key is sent to Flutter or stored in SQLite.

## Official references

- [Saved agent configuration](https://developers.openai.com/api/docs/guides/agents-api/configuration)
- [Sessions and turns](https://developers.openai.com/api/docs/guides/agents-api/sessions)
- [Events and items](https://developers.openai.com/api/docs/guides/agents-api/sessions/events)
- [Best-effort usage and caching](https://developers.openai.com/api/docs/guides/agents-api/observability)



## Calendar interpreter

Calendar has a separate `calendar-v1` contract. The authoring source is the
Calendar section of [agent-instructions-draft.md](agent-instructions-draft.md),
its compact [syntax reference](../backend/api/prompts/calendar.md), and
[64 translation examples](../backend/api/prompts/calendar-examples.json).
Tests validate every entry example using the real Haskell parser.
[Typed reply examples](../backend/api/prompts/calendar-answer-examples.json)
cover JSON-valued answers to engine questions. Assembly excludes
other domains' sections and grid-specific reference/geometric-planning policy.

The backend supplies a Haskell-scoped selected-week snapshot with stable handles,
Budapest exact/normalized intervals, importance, read-only flags and current
salience. Provider event IDs are omitted. The interpreter must preserve event
references and operational holes for Haskell, use native scheduling tasks rather
than solving them, and translate calendar questions instead of answering them.
The explicit frozen time anchors relative language. Event text is untrusted data.

A natural-language entry is attempted only after the raw entry fails parsing.
Controlled-English input bypasses the agent. Haskell validates candidates before
review; preview remains private and is checked against the original Google
snapshot. Accept interpretation starts provisional evaluation, including engine
clarifications. **Accept changes** is a separate approval of the net Google plan.

For a free-form reply to an engine text question, or a reply that does not parse
as the required typed value, the agent can propose a JSON value bound to that
question. It cannot replace the speech act or submit another command. These
proposals have the same review/preview/reject flow; rejecting restores the
original pending task. Numeric/option answers already understood by Haskell
bypass interpretation. Courtesy-only responses retain the pending question.

Calendar stores a stable interpreter-context ID with its dialogue. Persistent
sessions and bounded outcome queues use `calendar_llm_sessions` and
`calendar_llm_events`; no board conversation or event-world mirror is created.
Configuration IDs, leases, transcripts and the global $1 admission ledger are
shared with the existing interpreter infrastructure. Schema additions happen on
backend startup without deleting existing conversations or accounting. Recreate
supports `--domain calendar`; `--domain all` now includes it. Remote resources are
still created lazily, and this command remains local-only.

Both configured transports work: app-managed Agents is the default; Responses
uses the same Calendar instructions without saved sessions. No new model, key,
Google consent, tool access or fallback transport is introduced. Provider tests
use fake endpoints and fake Google data, not paid live turns or live event writes.
