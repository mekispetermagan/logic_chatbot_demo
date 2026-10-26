# Persistent Interpreter Agents

The default LLM transport is the OpenAI Agents API, using GPT-6 Luna. Haskell
still checks syntax first, owns all evaluation, and applies only accepted
proposals. Flutter's API and Preview / Accept / Reject / Submit answer flow are
unchanged. Set `LOGIC_CHATBOT_LLM_BACKEND=responses` to explicitly use the earlier
stateless transport; there is no automatic provider/model fallback.

## Instructions and saved agents

Each agent receives its standalone v2 language reference: [Objects v2](object-language-v2.md)
with 184 validated examples, [Network v2](network-language-v2.md) with 214,
or [Cellular v2](cellular-language-v2.md) with 120.
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

