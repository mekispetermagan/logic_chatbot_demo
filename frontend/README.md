# Logic Chatbot Demo Frontend

Flutter Material 3 interface with a dark, teal-seeded theme. At widths of 900
logical pixels or more, world and chat appear side by side; smaller screens use
tabs. The vector board uses a `Stack`, with chessboard coordinates and partial
objects. Missing shape uses `?`, missing color a neutral outline, and missing
size a medium footprint with a superscript `?`. Tooltips describe all attributes.

## Conversations

The app creates an anonymous conversation through FastAPI and saves its ID in
device/browser preferences, separately for each API URL. On restart it retrieves
the server's current world. Only a missing conversation (HTTP 404) creates a
replacement; other failures show Retry and preserve the saved ID.

The server supplies the initial toy world. The running app no longer uses local
world history or the Dart toy fixture. Property edits, placement, erasure, Clear,
and Undo call the API and display its returned world and feedback. Build the
Haskell editor executable as described in `backend/api/README.md` before editing.
Chat is still a placeholder. The
previous local editor controller and fixture remain for existing interaction
tests and reference.

Select one of ten properties and tap a square to apply it. Right click or long
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
