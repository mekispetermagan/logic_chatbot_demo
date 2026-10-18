# Domain-aware JSON contract

## Conversations and worlds

Create an anonymous conversation with `POST /conversations` and
`{"domain":"objects"}` or `{"domain":"network"}`. Each domain starts with its
own fixed seven-object world. The response includes `conversationId`, `domain`,
`world`, `canUndo`, `messages`, `languageVersion`, `nextObjectId`, and nullable `pending` and `proposal`. Editing replies also
include `feedback`, typed `changes`, and nullable `preview`. Domain selection is immutable for a conversation; subsequent
requests address the conversation ID and inherit its domain.

A world contains integer `width`, `height`, and an `objects` list. Both current
domains use 8×8 boards. Example network object:

```json
{
  "id": 3,
  "attributes": {"color": "red", "north": "north", "east": "east"},
  "position": {"x": 0, "y": 3}
}
```

`attributes` is required and maps canonical attribute names to canonical value
names. Absence is omission, never a null value. An empty map represents an object
with no attributed properties. `position` is null for an unplaced object, or a
complete zero-based coordinate pair (A1 is `(0,0)`). An objects-domain object
might have `{"color":"blue","size":"small","shape":"bloom"}`. Network ports
are independent unary attributes: `"north":"north"` means present. Aliases such
as `up` belong to LLM interpretation only, not either domain grammar or JSON. Object-domain synonyms
such as `flower` belong to LLM interpretation only; Objects v2 accepts `bloom`.

## V2 execution state

Conversations use `objects-v2` or `network-v2`, with standalone contracts in
[Objects v2](object-language-v2.md) and [Network v2](network-language-v2.md).
FastAPI supplies `languageVersion` and `nextObjectId` on every engine request.
Haskell echoes the version and returns its allocation counter. FastAPI rejects
outdated executables and backwards counters.

The counter is stored in `conversations.next_object_id`, outside Undo history.
Delete, Clear and Undo never decrement it. Preview does not persist allocations.
Aborted staged work can consume identifiers without committing objects. Initial
allocation starts above the fixed world's greatest identifier.

Pending entries in both domains add `payload` and nullable `stagedWorld`:

- For reference/placement clarification, `payload.version` is the conversation’s `objects-v2` or `network-v2`;
  the payload contains fully delimited source, the
  entry's immutable initial world/ranking/counter, accepted clarification choices,
  and a completed-sentence count. Clients must treat it as opaque server state.
- Continuation replays from that frozen seed and choice transcript, preserving
  operand binding and allocated identities without aging the entry twice.
- `stagedWorld` is present only for a paused atomic batch. The ordinary `world`
  remains committed state. Flutter labels a displayed staged world provisional.
- Existing `sentence`, `candidateIds`, `candidates` and `squareChoices` drive the
  same choice UI. `remaining` stores canonical entry text; `resolvedSubjects` is unused.

For surface grouping clarification, pending state additionally has
`groupingChoices: [{"groupingId": 1, "label": "does #3 satisfy color is red or (size is large and shape is bloom)?"}, ...]`.
`candidateIds`, `candidates` and `squareChoices` are empty. The opaque payload
has `version: "objects-v2-grouping"` or `"network-v2-grouping"` and fully delimited alternative entries.
No entry sentences, world mutations, salience aging or allocations happen
before this choice. POST to the existing `/clarify` endpoint with
`{"groupingId": 1}`; exactly one of `objectId`, `position` or `groupingId` is
required. A selected grouping can subsequently pause for reference resolution.
Both steps remain one entry and one Undo unit. Invalid choices retain pending
state. `checkSyntax` recognizes ambiguous but well-formed input without creating
pending state or setting `syntaxError`; the subsequent chat call asks the question
without invoking the LLM. Both domains use these same grouping and continuation
mechanisms. Replays use the fully delimited canonical parser, retaining the
chosen scope. Unsupported/missing continuation versions are rejected.

Execution and previews in either domain return `changes`, an ordered list of:

```json
{"objectId":3,"kind":"position","detail":"#3: on D4 -> on D5"}
```

Kinds are `created`, `deleted`, `position`, and `appearance`. Details describe
actual identity-specific effects, independent of rendering. Atomic failure or
staged work has no committed changes. Preview changes are nested under
`preview.changes` and never persisted as world edits.

Interpretation proposals include `languageVersion`. Revision checks include
the active version and allocation counter as well as world/discourse/messages.
An older proposal cannot be previewed, accepted or answered; it remains
rejectable so the original prompt can be resent. This rule applies to both domains.

## Visual editing

`POST /conversations/{id}/property` assigns one attribute:

```json
{
  "position": {"x": 0, "y": 3},
  "property": {"attribute": "north", "value": "north"}
}
```

The Haskell engine validates attribute/value membership in the selected domain.
Invalid transport or domain properties return HTTP 422 without changing history.
Property assignment creates an object on an empty square, or updates the existing
object. Other editing bodies (`place`, `erase`, `clear`, `undo`) are unchanged.
Chat and clarification bodies are unchanged. Network chat supports Layers 1,
2 and the documented network Layer 3.

Network pattern edits use `POST /conversations/{id}/ports` with
`{"position":{"x":0,"y":3},"ports":["north","east"]}`. The engine replaces all
four port attributes together and preserves color and identity. An empty list
clears the ports while retaining the object; on an empty square it creates an
isolated node. Repeated identical edits are no-ops. Each changed edit produces
one undoable snapshot. Duplicate ports, aliases, and use outside the network
domain are rejected. The engine action has `"type":"ports"` with the same fields.

## Engine requests and discourse storage

Each FastAPI-to-Haskell request contains `domain`, `world`, `action`, `salience`,
`languageVersion`, `nextObjectId`, and nullable `pending`. Every successful response echoes `domain`. Invalid engine
requests exit with status 2 and diagnostics on stderr; execution failures are
reported by FastAPI as HTTP 503. Syntax failures in chat remain normal responses
with `isError: true` and feedback.

Salience mentions retain `entry`, `utterance`, and `properties`, plus exactly
one typed reference: `objectId` for an object or `position: {x,y}` for a square.
Existing object-only records retain their representation and remain readable.
Square records cannot carry object attributes. Their true predicates use opaque
`{"kind":"defined","value":"square:..."}` facts, recomputed by Haskell after
updates. A square mention remains after its occupant is deleted; false occupancy
facts are removed. Python stores the ranking unchanged and Undo restores both kinds.

Mixed pronoun ties populate both `candidates`/`candidateIds` and `squareChoices`.
The frontend labels the alternatives Object and Square and submits exactly one
existing `/clarify` body (`objectId` or `position`). Replay records the typed
choice. No implicit occupant/position conversion occurs. Square-only ties use
`squareChoices` just like placement choices; the opaque program identifies the
semantic purpose. Query/command syntax and punctuation remain v2.

Attribute properties retain explicit identifiers:

```json
{"kind":"attribute","attribute":"color","value":"red"}
```

Position properties retain their representation:

```json
{"kind":"position","value":{"x":0,"y":3}}
```

Network computed facts use `{"kind":"defined","value":"v2:..."}`. This opaque
engine encoding includes a grounded predicate and its graph expression, with
reference operands bound to identifiers. Facts are rechecked against the current
world, including changes to remote colors/ports and visual edits; they
are not stored object attributes. World and salience snapshots are restored together by Undo.

Pending entries retain sentence text, remaining text, candidates, resolved
subjects, and square choices. They are parsed using the conversation's domain.

## SQLite release policy

Fresh databases use SQLite `user_version = 2`. An existing database with another
schema version is rejected unchanged. There is no migration or legacy grammar
continuation. The demo database is reset for this release, including conversation,
salience, proposal, agent-session and local accounting records. Provider-side
billing is unaffected.

Flutter retains one conversation ID per domain. A removed conversation returns
404 and the client creates a fresh one. Both domains retain seven fixed initial
objects. The app bar switches domains; network controls offer four colors and
all sixteen exact patterns. Generic object attributes are unchanged.

## Optional LLM translation and accounting

The public proposal/review contract is unchanged by the move to persistent
agents. The default backend stores saved-agent and session IDs internally;
Flutter continues to send the same requests. See
[Persistent Interpreter Agents](agent-sessions.md) for session lifecycle,
outcome synchronization and the differences in estimated usage accounting.

Flutter sends optional `useLlm` (strict Boolean, default false) with chat `text`.
For translation, FastAPI supplies the current world and entry to the model;
Flutter does not need to send an additional world payload. GPT readings are
offered for review and never applied automatically. Saving a proposal and
previewing/accepting it check that the conversation revision is unchanged.
HTTP 409 means a stale proposal must be rejected and the prompt resent against
the new state; a completed model call remains charged.
The flag is per request. FastAPI may translate only after Haskell reports a syntax
failure, and Haskell validates the proposed entry before evaluation.

The Haskell bridge accepts `{"type":"checkSyntax","text":"..."}`: it returns
normalized readable sentence text in `feedback`, or explicitly grouped choices
for an ambiguous object entry, without changing world, salience or pending
state. A syntax failure in `chat` or `checkSyntax` adds `syntaxError: true`
to the engine response. Other failures do not set it. These fields are internal
to the FastAPI/Haskell boundary; Python does not parse controlled English.

Public conversation responses add `llmBudget`: `limitUsd`, `spentUsd`,
`reservedUsd`, `remainingUsd`, and `requestCount`, shared globally. Machine
messages from translation attempts add nullable `llm` metadata containing status,
model, requestId, translation, inputTokens, cachedTokens, cacheWriteTokens,
outputTokens (including reasoning), reasoningTokens, costUsd, and reservedUsd.
Messages without an attempt omit `llm`. An unknown charge has null costUsd and
retains its maximum reservedUsd. API keys never appear in either contract.

Spending is not part of undoable world/discourse snapshots. See
[LLM translation](llm-translation.md) for the persistent $1 budget and failure rules.

## Interpretation review contract

### Agent response versus controlled translation

The agent's structured response has exactly five required fields: `status`,
`reply`, `candidates`, `question`, and `explanation`. `reply` is an empty string
when unused. It contains only brief neutral courtesy or a polite scope decline;
it is never included in a candidate program or sent to Haskell for evaluation.
For a mixed greeting/task entry, FastAPI displays `reply` alongside the normal
proposal feedback and validates only the candidates' `translation` strings.

`status: "conversation"` requires a nonempty `reply`, no candidates, and empty
`question` and `explanation`. Invalid combinations are rejected, not interpreted
as commands. A valid reply-only result is persisted directly as ordinary user
and machine chat messages, with its LLM usage metadata, and no review proposal.
World, salience, `canUndo` and symbolic history stay unchanged. There is no new
public endpoint or frontend response schema required.

During an interpretation clarification, a courtesy-only Submit answer leaves
the same proposal, candidates and question pending and does not append a
clarification turn. Its stored message revision is advanced to include the
courtesy exchange so Preview/Accept remain available. The reply is charged as
one ordinary LLM turn. Existing raw-input Haskell syntax checks still run first
for normal chat; only agent candidate translations proceed to interpretation
validation. With `useLlm: false`, chat remains strict controlled English.

### Review proposal

Every conversation response has nullable `proposal`. It is independent of the
Haskell reference-clarification `pending` field. A pending proposal contains:

```json
{
  "id": "d29172df-c643-42ca-b7fb-753fc51ed30e",
  "originalText": "Give B2 a warm color",
  "question": "By warm, do you mean red or yellow?",
  "explanation": "Both colors fit the request.",
  "candidates": [
    {"rank": 1, "interpretation": "Use red", "translation": "B2 red.", "explanation": "Red is a warm color."},
    {"rank": 2, "interpretation": "Use yellow", "translation": "B2 yellow.", "explanation": "Yellow is another warm color."}
  ],
  "validationFailures": [],
  "clarifications": [],
  "llm": {"status": "proposed", "model": "gpt-6-luna", "costUsd": 0.0001}
}
```

The `llm` example omits optional usage fields. Candidates are Haskell-validated,
ranked consecutively from 1, with at most three readings. A clear request may
have one candidate; a missing-detail clarification may have none, with a
nonempty `question` and `llm.status` of `clarification`. Initial offer replies
leave `world`, salience history, `pending` and `canUndo` unchanged. The user and
machine offer messages are saved, including the paid attempt's usage.

`validationFailures` contains `{interpretation, translation, reason}` for each
candidate rejected by Haskell. These programs are displayed as discarded and
cannot be previewed or accepted. If all candidates fail, `llm.status` is
`invalid`; an accompanying clarification question remains separately visible.
Failure details are retained even when no clarification question was generated.
`clarifications` stores ordered `{question, answer}` turns, initially empty.

All review actions are POSTs and return edit state:

| Path under `/conversations/{id}` | Body | Result |
| --- | --- | --- |
| `/interpretations/{proposalId}/preview` | `{"rank":2}` | Current state plus temporary `preview`. |
| `/interpretations/{proposalId}/accept` | `{"rank":2}` | Apply the stored translation; return `proposal: null`. |
| `/interpretations/{proposalId}/reject` | None | Discard the proposal; return `proposal: null`. |
| `/interpretations/{proposalId}/answer` | `{"text":"Use isolated nodes."}` | Make one new GPT interpretation request; replace the draft without applying it. |

`preview` is normally null. A preview response contains
`{proposalId, rank, world, feedback, pending}` in this field. Its top-level
`world` remains the committed world. The nested world, feedback and nullable
reference clarification describe trial Haskell evaluation only. No temporary
world, salience, pending entry or chat message is written. Preview does not
persist across refresh/restart. Flutter clears it when selecting another rank.

Accept uses the immutable stored translation, never client-supplied program
text. The entire entry is one undoable world/discourse snapshot; existing
reference clarification can pause it and continue within that snapshot.
Rejection preserves world/discourse history and appends a machine message.
Flutter restores `originalText` in the composer for editing. Neither action adds
a synthetic user message. Preview, acceptance and rejection make no GPT calls.

Submit answer is available when a question or validation failure is present,
or no valid candidate remains. It sends the answer to the pending proposal's
`answer` endpoint rather than normal chat. The API sends GPT the original entry,
current world and a `clarification` object with accumulated `turns`,
`previousCandidates` and `validationFailures`. Both token counting and generation
receive this same context. The answer is saved as a user message and the new
offer as a machine message with its own usage metadata. The replacement has a
new proposal ID but retains `originalText` and all clarification turns. The old
draft is retired with status `rejected`; acceptance of it returns 409.

Answering never changes world/salience snapshots. An unsuccessful model call
still leaves a draft showing the failure, with no old candidate available to
accept; the user can answer again or reject. Responses may ask another question.
Refresh/restart preserves accumulated answers. Submit answer incurs another
bounded GPT charge/reservation under the existing shared budget, with no
automatic retries. Blank or non-string answers return 422. Stale, consumed or
wrong-conversation drafts return 409 before contacting GPT; a state change
during the call also returns 409 without applying anything.

Drafts survive GET/restart in SQLite `interpretation_proposals`, including the
base revision; accepted/rejected drafts remain archived separately from world
snapshots. While a draft is pending, normal editing, chat, clarification and
Undo return HTTP 409. Missing conversations return 404; wrong/consumed proposal
IDs, unavailable ranks and stale preview/accept requests return 409. Rank must
be a JSON integer in 1..3; malformed choices return 422. Reject remains allowed
for a stale draft so the user can revise and resend. API charges survive both
rejection and Undo, with paid metadata recorded once on the offer message.
