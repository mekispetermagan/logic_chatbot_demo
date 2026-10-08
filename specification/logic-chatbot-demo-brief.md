# Logic-Based Chatbot: Demo Brief

**Companion to:** the logic-dialogue concept note  
**Presentation:** in person with Egri Győző, CEO of Faulhorn, on October 19, 2026  
**Development window:** about two weeks from October 5

## Purpose

Build a polished, working vertical slice that makes the symbolic dialogue and state-update idea tangible. It is a demonstrator of the logic core, not a general-purpose chatbot and not a demonstration of the complete proposed AI architecture.

## Demo world

Use a small, flat 8×8 grid. It can hold up to 64 pieces, one per cell, plus the board. The presentation scene should start sparsely—roughly 6–8 pieces—so spatial relations remain easy to see and query.

Each piece has:

- A persistent identity
- A shape: cube, sphere, or pyramid
- A color: red, blue, green, or yellow
- A size: small, medium, or large
- A grid coordinate

Coordinates must be within the board; each cell can contain at most one piece. Size is a categorical property, not a physical occupancy rule.

Initial spatial vocabulary: left/right and above/below. Add other relations only when their meanings and boundary cases are precisely defined.

## Frontend and visual design

- Build the frontend in Flutter to show Peter’s Flutter skills.
- Use a 2D grid with 2.5D-looking pieces. Draw the shapes in Flutter; visual depth does not add a third spatial dimension to the logic model.
- Flutter’s `Stack` can layer the board and positioned piece widgets. Flame is unnecessary for this dialogue-driven board. Avoid real-time 3D rendering for this deadline.
- Animate accepted moves and property changes; show a compact dialogue/history area and a clear result or clarification prompt.

## Backend boundaries

- **FastAPI:** the public API for Flutter, request orchestration, and persistence.
- **SQLite:** conversation records, current state, and ordered turn history.
- **Haskell:** the semantically critical engine: parse the supported English, resolve references, identify ambiguity or inconsistency, update the formal world state, and derive answers.

Keep Haskell’s engine independent of HTTP and database concerns. Treat it as a state-transition computation: give it the current formal state and a user utterance; receive a result containing the response, any clarification or rejection, and the updated state when applicable. FastAPI loads and saves that state. The browser talks only to FastAPI. Python should not make interpretation or world-update decisions.

The world model is simple. Conversation state is richer because it needs dialogue history and reference context, but the demo does not need an elaborate relational schema: persist the current formal state and ordered turns per conversation. Derived facts can be recomputed rather than stored separately.

## Language and reasoning scope

- No LLM or other AI parser in this demo. Use a deliberately limited, documented English grammar.
- Demonstrate multi-turn state, reference resolution (including a clarification when a description has multiple matches), revisions, and exact answers derived from the current board.
- Keep stated information distinct from facts the engine derives where the interface can show that distinction clearly.
- Make unsupported or ambiguous requests explicit; do not silently guess.

## Illustrative demo arc

Finalize exact supported sentence forms during implementation. A useful sequence is: place a few pieces; ask a spatial question whose answer follows from their positions; change a property or position using a reference to an earlier piece; ask a follow-up question; then demonstrate clarification for a description that matches more than one piece.

## Scope discipline

Prioritize a reliable end-to-end flow and a polished, legible board. Do not spend the two-week window on true 3D, game mechanics, a broad English parser, or a complex database model. The pitch should present this honestly as a rule-based symbolic core for the larger architecture described in the concept note.
