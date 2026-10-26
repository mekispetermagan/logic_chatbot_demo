# Logic Chatbot Demo Frontend

Flutter Material 3 interface with a dark, teal-seeded theme. At widths of 900
logical pixels or more, world and chat appear side by side; smaller screens use
tabs. The vector board uses a `Stack`, with chessboard coordinates and partial
objects. Missing shape uses `?`, missing color a neutral grey silhouette, and missing
size a medium footprint with a superscript `?`. Tooltips describe all attributes.

The Linux app launches fullscreen at the display's current resolution.

## Calendar week view

Select **Calendar** in the app bar (or the narrow-screen dropdown) to open a
Monday–Sunday week view inside the World panel. Wide screens retain
the World/Chat split; narrow screens retain the two tabs. The header shows weekday
names and dates;
previous/next arrows fetch the selected week's events, and Refresh reloads it.
The month/year label covers both months or years when a week crosses a boundary.

The grid scrolls vertically through 00:00–24:00, with fixed day headers, hourly
lines, and colored event rectangles spanning their start/end times. Overlapping
events share a day column side by side. Hover for title, date/time, description
and location; touch platforms can use Flutter's normal long-press tooltip.
Event colors show importance: Google color ID 11 is Critical (level 2, red),
ID 5 is Important (level 1, yellow), and every other or absent ID is Normal
(level 0, green).
A red current-time line spans today's column in Budapest time, updates at each
minute boundary and on app resume, and scrolls with the grid. It is hidden when
the selected week does not include today. Clock updates do not fetch events.

All times and week bounds use Europe/Budapest via the bundled IANA timezone
database, independently of the device timezone. Navigation constructs local
midnights so DST weeks can contain 167 or 169 actual hours. The grid remains a
24-hour wall-clock view; an event crossing the repeated autumn hour whose end
clock time is not later than its start uses elapsed duration for its rectangle,
with the clock change and offsets explained in its tooltip.

All-day, cancelled and cross-day events (including those ending exactly at the
next midnight) are omitted from this initial display. This is a presentation
filter; the API still returns its complete event list. Calendar is a separate
view, not a symbolic conversation domain: the Chat panel shows a placeholder,
LLM and Undo controls are hidden, and existing domain state is retained when
switching back.

Each selection/week change uses one `GET /calendar/events` request with explicit
week bounds and the Budapest timezone. Loading, empty and retry states are shown;
late responses from previous weeks cannot replace the selected week's data.
On narrow screens the seven-column grid can also scroll horizontally.
Enable/configure the local MCP backend using [Calendar setup](../docs/calendar-mcp.md).
Click an event to open read-only details. The pencil opens an editor for title,
date, start/end time, description, location and importance; Save submits
only changed fields, and Cancel discards the draft. The trash icon asks Yes/No
before deleting. Click an empty grid slot (rounded down to 15 minutes), or use
New event, to create a same-day timed event. Times use Budapest; ambiguous or
nonexistent DST times must be changed before saving. Recurring events are read-only.

The Importance selector offers Normal (0), Important (1) and Critical (2).
Setting them writes Google color IDs 10, 5 and 11 respectively. New events
default to Normal and write ID 10.
Viewing events or editing unrelated fields preserves their original color ID;
explicitly selecting level 0 writes ID 10 even if the old ID already mapped to 0.
Description and location can be cleared; omitted fields remain unchanged.

Writes require the backend's opt-in write configuration. A successful write
reloads the selected week from Google. While saving, dismissal and duplicate
submissions are disabled. If a response is lost or verification fails, close the
dialog and refresh before trying again; writes are never automatically retried.
Calendar chat remains future work.

## Conversations

The app creates an anonymous conversation through FastAPI and saves its ID in
device/browser preferences, separately for each API URL and domain. On restart it retrieves
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
`Set color of #0 to blue. Does #0 satisfy color is blue? What is the color of #0?`. A whole entry is one undoable world/discourse update,
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

Five numbered save/load slots sit below the property selectors. Save records
the current world and its reference ranking in SQLite; replacing a saved setup
asks for confirmation. Load restores that setup as one undoable step and clears
placement selection. Empty slots have disabled Load buttons. Each domain's
conversation has its own five slots, retained across restarts. Chat history stays
visible, with a short message when a setup is loaded. Slots are disabled during
requests, interpretation review, and reference clarification.

To start over, enter `full reset` in Chat and reply `yes` to confirm or `no` to
cancel. Confirmation starts a new conversation in the same domain, clears
chat/input history and reference context, and has no Undo. Objects/network start
empty; cellular restores its initial glider. The five saved slots
are preserved. The command bypasses the LLM and remains available during a
pending interpretation or symbolic clarification; other actions pause until
confirmation is answered. The new conversation ID is saved on this device.

Controls are disabled while a request is pending. Failed edits preserve the
displayed world and offer Refresh world. Refresh retrieves authoritative state
without repeating the edit, since a failed response may follow a committed edit.

## Development

See the [root quickstart](../README.md#ubuntulinux-quickstart) for first-time
Ubuntu setup. The current lockfile requires Flutter 3.47.0 or newer with Dart
3.13.0 or newer. Run `flutter doctor` and resolve Linux toolchain issues before
building; the prerequisite packages are listed in that quickstart.

Start FastAPI using the [API README](../backend/api/README.md) and leave it
running in its terminal. If using LLM interpretation, load/export the API key
there before starting Uvicorn. In a second terminal, run from `frontend/`:

```sh
flutter pub get
flutter run -d linux
```

For a different target, use one of these instead of the Linux run command:

```sh
flutter run -d chrome --web-port=8080
flutter run -d <android-device-id>
```

Development checks, also run from `frontend/`:

```sh
flutter analyze
flutter test
dart format lib test
```

Restart the app fully after installing the new native preferences plugin.
For a quick check, select Objects and send `How many objects match true?`.
Enable the LLM switch for ordinary language; it defaults to off. If it reports
that LLM is not configured, reload the key and restart the backend, not just Flutter.
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

The API client creates `WorldDomain.objects` (the default), `WorldDomain.network`,
or `WorldDomain.cellular`. Conversation state stores that typed domain. Objects
retain immutable generic attribute maps, with color/size/shape getters for the
existing display and `NetworkPort` presence checks for network consumers.
Property edits send canonical `AttributeProperty` pairs. The existing objects
editor uses this transport; network rendering uses 16 SVG port patterns with the Lego palette. The app-bar
selector resumes a separate conversation for each domain. Later requests use the conversation ID and inherit
the server's stored domain. See the
[JSON contract](../docs/json-contract.md).

## Network editor

The network palette has four color buttons and 16 complete port patterns. Select
one option and tap a square. Pattern edits replace ports while preserving color;
the center-dot option clears ports without deleting the object. Erase, unplaced
placement, and shared Undo retain their usual behavior. Each pattern tap uses one
`ports` request and one undo step. SVG assets live in
`assets/images/network_shapes/`, with 20% center dots and center-lit gradients.
Domain-specific conversation IDs are stored separately per API URL; the original
objects key is retained for existing installations.

## Cellular player

Select Cellular in the app bar to open a separate persisted conversation. On
narrow screens the domain selector becomes a dropdown. New cellular conversations
start with a centered Game of Life glider, black on white. The 16×16 grid uses
A1–P16 coordinates; Objects and Network retain their 8×8 grids. Colored rulesets also support red, green,
blue, and yellow.

Select one active color button and tap or left-click a cell to repaint it.
Black is initially selected for Game of Life. Right click and long press do not
edit cells. The color row scrolls horizontally when needed. Painting calls
`POST /conversations/{id}/cell` and displays the returned world; generation and
rules stay unchanged. Each changed cell is undoable; painting the same color
adds no history. Buttons and painting pause during requests.

Step requests exactly one generation from `POST /conversations/{id}/step` and
displays the returned board and generation number. Haskell computes every
transition; Flutter does not simulate cells locally. The button is disabled
during requests, and the grid keeps its size while updating. Undo and all five
save/load slots preserve the complete cellular state, including rules and
generation. A failed response offers Refresh world without repeating the step.

`CellularWorld` and `World` implement the shared `GridWorld` interface.
`ConversationController` owns API calls and request state; stateless cellular
widgets receive data and callbacks. Cellular chat and the LLM switch are enabled:
commands, questions, forecasts and clarification use the shared chat interface.
Preview and staged atomic batches display a dense cellular board without changing
the authoritative state. `full reset` still requires confirmation and preserves
saved slots. Continuous playback is not implemented.
See [Cellular v2](../docs/cellular-language-v2.md) for the grammar.

API startup expands older cellular worlds, Undo history, and saved slots with
white padding, keeping their patterns centered and generation numbers intact.

Edit rules opens a modal with a local `CellularRulesetController` draft: choose
at least two colors, Moore (8) or von Neumann (4) neighbors, then configure one
enabled/disabled rule per source color. Select a target color and any counts;
neighbors of that same target color are counted. Game of Life and RGB-cycle
buttons at the bottom only prefill the form. Submit sends the complete ruleset
to `POST /conversations/{id}/ruleset`, as one undoable operation.

Rules-only changes preserve the board/generation and increase the ruleset
revision. Removing colors still on the board asks for confirmation to refill
randomly using the new palette and restart generation zero. Cancel leaves the
draft open without sending anything. An unchanged submission adds no history.
The form pauses during submission; uncertain failures require refreshing the
authoritative world before retrying.
