# Repository Guidelines

## Purpose & Specification Status

This repository began as a demo for a project proposal presentation on October 19, 2026. It now implements Objects, Network and Cellular domains with controlled-language dialogue and optional LLM interpretation. Its goal is a symbolic–probabilistic dialogue system combining explicit, revisable information state, LLM interpretation and expression, and symbolic verification with search. Distributed-protocol development is its proposed first benchmark, not this demo's task.

Read `docs/logic-dialogue-concept-note.pdf` for the overall goal and `docs/domain-architecture.md` for the current implementation. The standalone `docs/object-language-v2.md`, `docs/network-language-v2.md` and `docs/cellular-language-v2.md` define the supported grammar and semantics. `docs/logic-chatbot-demo-brief.md` preserves the original historical scope; `docs/archive/` contains superseded designs. Proposed extensions are not approved semantics. Do not invent semantic rules or treat reference code as approved design.

## Project Structure & Module Organization

Flutter lives in `frontend/`, with presentation in `frontend/lib/widgets/`, editing state in `frontend/lib/controllers/`, and platform configuration in `frontend/web/`, `frontend/linux/`, and `frontend/android/`. FastAPI lives in `backend/api/app/`; Haskell modules live in `backend/logic_engine/`. Shared JSON fixtures live in `backend/shared/`. Keep presentation, orchestration, and semantic world updates separate. Keep specifications in `docs/`.

## Architecture & Scope

- Flutter presents 8×8 Objects and Network boards, a 16×16 toroidal Cellular board, dialogue history, and interpretation review.
- FastAPI exposes the public API and manages persistence in SQLite.
- Haskell owns parsing, reference resolution, ambiguity detection, world updates, and derived answers. Keep it independent of HTTP and database concerns.

Prioritize a polished, reliable symbolic dialogue demonstration. Optional LLM interpretation proposes controlled-English entries for Preview / Accept / Reject; persistent interpreter sessions are supported. Python orchestrates interpretation, review and persistence; Haskell owns reference resolution, symbolic evaluation and world updates. Learned search, distributed-protocol tooling and true 3D remain outside the implemented demo. Preserve object identities, enforce each domain's constraints, clarify consequential ambiguity, and distinguish stated information from derived facts. Calendar MCP has optional local FastAPI reads and separately enabled one-off event writes, documented in `docs/calendar-mcp.md`; Flutter has a weekly display and create/edit/delete dialogs; Calendar controlled-language chat, clarification, scheduling and reviewed writes are implemented; see `docs/calendar-language-v1.md`. Shared Calendar rules are in `docs/calendar-domain.md`; the proposed LLM-only integration is in `docs/calendar-llm-only.md`. Historical Calendar proposals are in `docs/archive/`. Keep Google access in the Python MCP adapter and Google as the source of truth; do not mirror calendar events into SQLite or expose unauthenticated public calendar operations.

Keep logic out of UI and UI out of logic. Prefer stateless widgets where natural, while retaining Flutter's built-in stateful solutions when appropriate.

## Build, Test, and Development Commands

From `frontend/`, run `flutter pub get`, `flutter analyze`, and `dart format lib`. Launch with `flutter run -d chrome`, `flutter run -d linux`, or an Android device ID from `flutter devices`. Build with `flutter build web`, `flutter build linux`, or `flutter build apk`. See `frontend/README.md` for prerequisites. The Dart SDK constraint is in `frontend/pubspec.yaml`.

From `backend/api/`, install `requirements.txt` into a virtual environment, run `uvicorn app.main:app --reload`, and test with `python -m unittest discover -s tests -v`. First build `exe:logic-engine-editor` from `backend/logic_engine/` and copy it into that directory's `bin/`; API editing tests call this real executable. From `backend/logic_engine/`, run `cabal test` or `cabal repl`. See each backend directory's README for setup.

## Coding Style & Naming Conventions

Use standard language formatters and descriptive names for board state, dialogue turns, and references. Keep Markdown concise with descriptive headings.

## Testing Guidelines

Place Flutter tests in `frontend/test/` with `_test.dart` filenames and run `flutter test`. Python persistence/API tests live in `backend/api/tests/` and use temporary SQLite databases; Haskell tests live in `backend/logic_engine/test/`. Test board boundaries, occupancy, reference resolution, revisions, persistence, and frontend interactions at their respective layers. No coverage threshold is defined.

## Commit & Pull Request Guidelines

Use concise, imperative commit subjects. Pull requests should explain behavior and validation, link relevant specifications or issues, and include screenshots for visual changes.
