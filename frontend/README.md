# Logic Chatbot Demo Frontend

Flutter Material 3 interface with a dark, teal-seeded theme. At widths of 900
logical pixels or more, world and chat appear side by side; smaller screens use
tabs. The vector board uses a `Stack`, with chessboard coordinates and partial
objects. Missing shape uses `?`, missing color a neutral grey silhouette, and missing
size a medium footprint with a superscript `?`. Tooltips describe all attributes.

## Conversations

The app creates an anonymous conversation through FastAPI and saves its ID in
device/browser preferences, separately for each API URL. On restart it retrieves
the server's current world. Only a missing conversation (HTTP 404) creates a
replacement; other failures show Retry and preserve the saved ID.

The server supplies the initial toy world. The running app no longer uses local
world history or the Dart toy fixture. Property edits, placement, erasure, Clear,
and Undo call the API and display its returned world. Chat feedback stays in Chat. Build the
Haskell editor executable as described in `backend/api/README.md` before editing.
Chat accepts the engine's controlled-English sentences and restores persisted messages on
restart. User bubbles use Material primary container colors; machine bubbles use
secondary container colors. Replies preserve prettyprinted sentences and answers;
parse errors have a distinct label and border. Enter submits, Shift+Enter inserts
a new line, and the Send button remains available; failed requests retain the
draft. For example, send
`#0 blue. #0 blue? color of #0?`. A whole entry is one undoable world/discourse update,
and Undo keeps chat messages. Ambiguity displays candidate buttons; choosing one
resumes the same entry. While clarification is pending, new entries and visual
edits are disabled. The shared Undo in the app bar cancels the whole entry,
including any updates before the pause. Pending choices survive restart. The
previous local editor controller and fixture remain for existing interaction
tests and reference.

Color, size, and shape buttons wrap as three intact groups.
Select one of eleven icon buttons and tap a square to apply it.
The selected button has a teal background and corner checkmark; color swatches
are inset so the selection stays visible. Right click or long
press erases. Select an unplaced object, then tap an empty square to place it;
blocked placement retains the selection. Choosing a property cancels placement.
Clear and Undo clear placement selection after a successful response.

Controls are disabled while a request is pending. Failed edits preserve the
displayed world and offer Refresh world. Refresh retrieves authoritative state
without repeating the edit, since a failed response may follow a committed edit.

## Development

Start FastAPI using `backend/api/README.md`, then run from `frontend/`:

```sh
flutter pub get
flutter run -d linux
flutter run -d chrome --web-port=8080
flutter run -d <android-device-id>
flutter analyze
flutter test
dart format lib test
```

Restart the app fully after installing the new native preferences plugin.
Linux and web default to `http://127.0.0.1:8000`; Android defaults to the emulator
host address `http://10.0.2.2:8000`. For a physical phone, start FastAPI with
`uvicorn app.main:app --host 0.0.0.0 --port 8000`, connect to the same network,
and substitute your computer's LAN IP:

```sh
flutter run -d <android-device-id> --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

`API_BASE_URL` also configures web/Linux and builds. Debug Android permits local
HTTP; release APKs should use an HTTPS API URL. Build with `flutter build web`,
`flutter build linux`, or `flutter build apk --dart-define=API_BASE_URL=https://your-api.example`.
Use `flutter devices` to find device IDs. Linux requires GTK development libraries
and the native desktop toolchain; Android requires its SDK and a compatible JDK.


## Shape assets

Bloom, Spark, Drop, and Loop use the existing SVG silhouettes in
`assets/images/shapes/`, rendered with `flutter_svg`. Selector icons and pieces
share these assets. Pieces and selector swatches use red `#C91A09`, blue `#0055BF`, yellow
`#FEC401`, and green `#237841`. Piece gradients mix 20% white at the top
and 20% black at the bottom; colorless
pieces use neutral grey, and the loop's hole remains transparent. Size scaling,
unknown-shape question marks, and unknown-size badges remain supported.

The API client creates either `WorldDomain.objects` (the default) or
`WorldDomain.network`. Conversation state stores that typed domain. Objects
retain immutable generic attribute maps, with color/size/shape getters for the
existing display and `NetworkPort` presence checks for network consumers.
Property edits send canonical `AttributeProperty` pairs. The existing objects
editor uses this transport; network rendering uses 16 SVG port patterns with the Lego palette. The app-bar
selector resumes a separate conversation for each domain. Later requests use the conversation ID and inherit
the server's stored domain. See the
[JSON contract](../specification/json-contract.md).

## Network editor

The network palette has four color buttons and 16 complete port patterns. Select
one option and tap a square. Pattern edits replace ports while preserving color;
the center-dot option clears ports without deleting the object. Erase, unplaced
placement, and shared Undo retain their usual behavior. Each pattern tap uses one
`ports` request and one undo step. SVG assets live in
`assets/images/network_shapes/`, with 20% center dots and center-lit gradients.
Domain-specific conversation IDs are stored separately per API URL; the original
objects key is retained for existing installations.
