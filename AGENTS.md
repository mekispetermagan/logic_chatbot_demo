# Repository Guidelines

## Purpose & Specification Status

This repository is a demo for a project proposal presentation on October 19, 2026. The broader project is not yet underway. Its goal is a symbolic–probabilistic dialogue system combining explicit, revisable information state, LLM interpretation and expression, and symbolic verification with search. Distributed-protocol development is its proposed first benchmark, not this demo's task.

Read `specification/logic-dialogue-concept-note.pdf` for that overall goal, then `specification/logic-chatbot-demo-brief.md` for the demo scope. The ChatGPT-generated brief outlines most demo requirements; it does not supply the chatbot logic. Peter will provide that logic later, possibly with older chatbot code for reference. Do not invent semantic rules or treat reference code as approved design; review it against Peter's instructions when supplied.

## Project Structure & Module Organization

The Flutter skeleton lives in `frontend/`, with widgets in `frontend/lib/main.dart` and platform configuration in `frontend/web/`, `frontend/linux/`, and `frontend/android/`. Backend and engine modules do not exist yet. Keep Flutter presentation, FastAPI orchestration, and the Haskell engine separate, with tests for each stack. Keep specifications in `specification/`.

## Architecture & Scope

- Flutter presents an 8×8 board, pieces, animations, and dialogue history.
- FastAPI exposes the public API and manages persistence in SQLite.
- Haskell owns parsing, reference resolution, ambiguity detection, world updates, and derived answers. Keep it independent of HTTP and database concerns.

Prioritize a polished, reliable symbolic dialogue demonstration with 2D logic and 2.5D-looking pieces. LLM integration, learned search, distributed-protocol tooling, and true 3D are outside demo scope. Python must not make interpretation or world-update decisions. Once supplied, document the supported grammar. Preserve piece identities, enforce board bounds and single-cell occupancy, and clarify ambiguity. Distinguish stated information from derived facts.

Keep logic out of UI and UI out of logic. Prefer stateless widgets where natural, while retaining Flutter's built-in stateful solutions when appropriate.

## Build, Test, and Development Commands

From `frontend/`, run `flutter pub get`, `flutter analyze`, and `dart format lib`. Launch with `flutter run -d chrome`, `flutter run -d linux`, or an Android device ID from `flutter devices`. Build with `flutter build web`, `flutter build linux`, or `flutter build apk`. See `frontend/README.md` for prerequisites. The Dart SDK constraint is in `frontend/pubspec.yaml`.

## Coding Style & Naming Conventions

Use standard language formatters and descriptive names for board state, dialogue turns, and references. Keep Markdown concise with descriptive headings.

## Testing Guidelines

Flutter's `flutter_test` is available; no tests or coverage threshold are defined yet. Place Flutter tests in `frontend/test/` with `_test.dart` filenames and run `flutter test`. Later, test board boundaries, occupancy, ambiguity, revisions, and derived answers against the supplied logic. Test API persistence and Flutter interaction separately.

## Commit & Pull Request Guidelines

No Git history establishes conventions. Use concise, imperative commit subjects. Pull requests should explain behavior and validation, link relevant specifications or issues, and include screenshots for visual changes.
