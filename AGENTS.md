# Repository Guidelines

## Purpose & Specification Status

This repository is a demo for a project proposal presentation on October 19, 2026. The broader project is not yet underway. Its goal is a symbolic–probabilistic dialogue system combining explicit, revisable information state, LLM interpretation and expression, and symbolic verification with search. Distributed-protocol development is its proposed first benchmark, not this demo's task.

Read `specification/logic-dialogue-concept-note.pdf` for that overall goal, then `specification/logic-chatbot-demo-brief.md` for the demo scope. The ChatGPT-generated brief outlines most demo requirements; it does not supply the chatbot logic. Peter will provide that logic later, possibly with older chatbot code for reference. Do not invent semantic rules or treat reference code as approved design; review it against Peter's instructions when supplied.

## Project Structure & Module Organization

Flutter lives in `frontend/`, with presentation in `frontend/lib/widgets/`, editing state in `frontend/lib/controllers/`, and platform configuration in `frontend/web/`, `frontend/linux/`, and `frontend/android/`. FastAPI lives in `backend/api/app/`; Haskell modules live in `backend/logic_engine/`. Shared JSON fixtures live in `backend/shared/`. Keep presentation, orchestration, and semantic world updates separate. Keep specifications in `specification/`.

## Architecture & Scope

- Flutter presents an 8×8 board, pieces, animations, and dialogue history.
- FastAPI exposes the public API and manages persistence in SQLite.
- Haskell owns parsing, reference resolution, ambiguity detection, world updates, and derived answers. Keep it independent of HTTP and database concerns.

Prioritize a polished, reliable symbolic dialogue demonstration with 2D logic and 2.5D-looking pieces. LLM integration, learned search, distributed-protocol tooling, and true 3D are outside demo scope. Python must not make interpretation or world-update decisions. Once supplied, document the supported grammar. Preserve piece identities, enforce board bounds and single-cell occupancy, and clarify ambiguity. Distinguish stated information from derived facts.

Keep logic out of UI and UI out of logic. Prefer stateless widgets where natural, while retaining Flutter's built-in stateful solutions when appropriate.

## Build, Test, and Development Commands

From `frontend/`, run `flutter pub get`, `flutter analyze`, and `dart format lib`. Launch with `flutter run -d chrome`, `flutter run -d linux`, or an Android device ID from `flutter devices`. Build with `flutter build web`, `flutter build linux`, or `flutter build apk`. See `frontend/README.md` for prerequisites. The Dart SDK constraint is in `frontend/pubspec.yaml`.

From `backend/api/`, install `requirements.txt` into a virtual environment, run `uvicorn app.main:app --reload`, and test with `python -m unittest discover -s tests -v`. First build `exe:logic-engine-editor` from `backend/logic_engine/` and copy it into that directory's `bin/`; API editing tests call this real executable. From `backend/logic_engine/`, run `cabal test` or `cabal repl`. See each backend directory's README for setup.

## Coding Style & Naming Conventions

Use standard language formatters and descriptive names for board state, dialogue turns, and references. Keep Markdown concise with descriptive headings.

## Testing Guidelines

Place Flutter tests in `frontend/test/` with `_test.dart` filenames and run `flutter test`. Python persistence/API tests live in `backend/api/tests/` and use temporary SQLite databases; Haskell tests live in `backend/logic_engine/test/`. Test board boundaries, occupancy, reference resolution, revisions, persistence, and frontend interactions at their respective layers. No coverage threshold is defined.

## Commit & Pull Request Guidelines

No Git history establishes conventions. Use concise, imperative commit subjects. Pull requests should explain behavior and validation, link relevant specifications or issues, and include screenshots for visual changes.
