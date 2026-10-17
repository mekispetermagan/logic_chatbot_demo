# Domain-aware JSON contract

## Conversations and worlds

Create an anonymous conversation with `POST /conversations` and
`{"domain":"objects"}` or `{"domain":"network"}`. Each domain starts with its
own fixed seven-object world. The response includes `conversationId`, `domain`,
`world`, `canUndo`, `messages`, and nullable `pending`. Editing replies also
include `feedback`. Domain selection is immutable for a conversation; subsequent
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
as `up` and `flower` belong to chat syntax, not JSON transport.

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
Chat and clarification bodies are unchanged. Network chat currently supports
Layers 1 and 2; derived network language is not yet available.

Network pattern edits use `POST /conversations/{id}/ports` with
`{"position":{"x":0,"y":3},"ports":["north","east"]}`. The engine replaces all
four port attributes together and preserves color and identity. An empty list
clears the ports while retaining the object; on an empty square it creates an
isolated node. Repeated identical edits are no-ops. Each changed edit produces
one undoable snapshot. Duplicate ports, aliases, and use outside the network
domain are rejected. The engine action has `"type":"ports"` with the same fields.

## Engine requests and discourse storage

Each FastAPI-to-Haskell request contains `domain`, `world`, `action`, `salience`,
and nullable `pending`. Every successful response echoes `domain`. Invalid engine
requests exit with status 2 and diagnostics on stderr; execution failures are
reported by FastAPI as HTTP 503. Syntax failures in chat remain normal responses
with `isError: true` and feedback.

Salience mentions retain `entry`, `utterance`, `objectId`, and `properties`.
Attribute properties now have explicit identifiers:

```json
{"kind":"attribute","attribute":"color","value":"red"}
```

Position properties retain their representation:

```json
{"kind":"position","value":{"x":0,"y":3}}
```

Network computed facts in salience use `{"kind":"defined","value":"endpoint"}`.
These are checked against the current world, including after visual edits; they
are not stored object attributes. World and salience snapshots are restored together by Undo.

Pending entries retain sentence text, remaining text, candidates, resolved
subjects, and square choices. They are parsed using the conversation's domain.

## SQLite migration and client compatibility

On startup, the API migrates every stored world snapshot from nullable
`color`/`size`/`shape` fields to the attributes map, and every salience snapshot
from descriptor words to explicit attribute/value properties. The conversion is
transactional and versioned with SQLite `user_version = 1`. Conversation IDs,
snapshot ordering, pending entries, and chat messages are preserved. Undo
restores paired world/discourse snapshots within the same domain.

This is a breaking transport change. Flutter models and API transport now
support both domains, and the existing objects editor sends generic property
edits. The app bar switches domains, retaining one conversation per domain on the
device. Network controls offer four colors and all 16 port patterns.
Older Flutter clients cannot consume these worlds or send property edits.
