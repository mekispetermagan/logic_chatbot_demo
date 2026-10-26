# Logic Chatbot Demo

Flutter interface, FastAPI/SQLite backend, and a Haskell logic engine for Objects,
Network and Cellular worlds. Controlled English works locally without an API key.
Optional LLM interpretation proposes translations for Preview / Accept / Reject;
Haskell resolves references, evaluates operations and computes answers.

## Ubuntu/Linux quickstart

Use Bash for the commands below. Start in the repository root unless a step says
otherwise. Keep the backend and frontend running in separate terminals.

### 1. Prerequisites

Install the native build tools and Python virtual-environment support:

```bash
sudo apt-get update
sudo apt-get install git curl unzip xz-utils build-essential clang cmake \
  ninja-build pkg-config libgtk-3-dev libgmp-dev libffi-dev libtinfo-dev \
  zlib1g-dev python3 python3-venv
```

Install [Flutter](https://docs.flutter.dev/install) and the GHC/Cabal toolchain
through [GHCup](https://www.haskell.org/ghcup/) before continuing. The current frontend
lockfile requires Flutter 3.47.0 or newer with Dart 3.13.0 or newer. The backend
requires Python 3.10 or newer; the Haskell build was verified with GHC 9.10.3 and
Cabal 3.18.2.0. For a GHCup installation, activate those installed versions with:

```bash
export PATH="$HOME/.ghcup/bin:$PATH"
ghcup set ghc 9.10.3
ghcup set cabal 3.18.2.0
```

If Flutter is installed in `~/flutter`, add it to this terminal's PATH too:

```bash
export PATH="$HOME/flutter/bin:$PATH"
flutter doctor
ghc --version
cabal --version
python3 --version
```

The PATH exports affect the current terminal. Add them to your shell startup file
if needed in future terminals. `ghcup set` selects an already installed version;
use `ghcup install ghc 9.10.3` / `ghcup install cabal 3.18.2.0` first if absent.
Resolve Linux toolchain issues reported by `flutter doctor`. Android setup is
needed only for Android development.

### 2. Build and install the logic engine

```bash
cd backend/logic_engine
cabal update
cabal build exe:logic-engine-editor
mkdir -p bin
cp "$(cabal list-bin exe:logic-engine-editor)" bin/logic-engine-editor
cd ../..
```

The API invokes the copy in `bin/`; rebuild and copy again after Haskell changes.
If linking fails with `cannot find -lgmp`, install `libgmp-dev` from step 1.

### 3. Prepare the Python backend

```bash
cd backend/api
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

If venv creation reports that `ensurepip` is unavailable, install `python3-venv`
(or the matching versioned package for a separately installed Python) and retry.
On later starts, reuse `.venv`; creation and dependency installation are setup steps.

For LLM interpretation, create `backend/api/.env` in an editor with:

```dotenv
OPENAI_API_KEY=your-secret-key
```

`.env` is ignored by Git. The application does not load it automatically. In the
same terminal that will start Uvicorn, while still in `backend/api/`, run:

```bash
set -a
source .env
set +a
```

`set -a` exports the loaded variables so the backend inherits them; `set +a` turns
automatic exporting off afterward. Skip this block for controlled-English-only
use. See the [API README](backend/api/README.md#optional-llm-translation) for key
permissions, the default Agents transport and the shared $1 admission budget.

A fresh clone does not depend on the author's agents: the backend automatically
creates an app-managed agent for each domain on its first LLM request, using your
key's project and the repository's instructions, grammar and examples. No manual
agent-ID setup is needed. See [per-domain setup and recovery](docs/agent-sessions.md#setup-for-a-fresh-clone).
If reusing a database under a different account/project, stop the backend and run
`python -m app.agents recreate --domain all` from `backend/api/` with `.venv`
active and the same database settings. Replacements are created on the next LLM
request; local worlds, chat, slots, Undo and accounting are retained. One-domain
recreation is also supported. Reload/export the new key before restarting Uvicorn.

### 4. Start the backend — terminal 1

From `backend/api/`, with `.venv` active and any `.env` variables exported:

```bash
uvicorn app.main:app --reload
```

Leave this running. Open `http://127.0.0.1:8000/docs` to check that the API started.
For later sessions, activate `.venv`, load `.env` if wanted, and start Uvicorn again.
After editing `.env`, stop Uvicorn with Ctrl+C, reload the file in its terminal,
and restart it; changing the file alone does not update the running environment.

### 5. Start the frontend — terminal 2

From the repository root in a second terminal:

```bash
cd frontend
flutter pub get
flutter run -d linux
```

Linux launches fullscreen and connects to `http://127.0.0.1:8000` by default.
For web, use `flutter run -d chrome --web-port=8080` instead. Android and custom
API addresses are documented in the [frontend README](frontend/README.md#development).

### 6. Verify the complete flow

1. Select Objects and submit `How many objects match true?` with the LLM switch off.
   An engine-derived count confirms the API can invoke Haskell.
2. If you configured a key, enable the LLM switch and submit an ordinary request
   such as `Please make the object at A1 blue`. Review the translation, then use
   Preview or Accept. Valid controlled English bypasses the LLM even with it enabled.
3. If the app reports that LLM is not configured, reload/export the key in the
   backend terminal and restart Uvicorn. The LLM switch defaults to off on app start.
4. If edits report that the logic engine is unavailable, check the build/copy step
   and the backend terminal. If the app cannot connect, check Uvicorn is still running.

## Tests and further documentation

Run `cabal test` in `backend/logic_engine/`,
`python -m unittest discover -s tests -v` in `backend/api/` with `.venv` active,
and `flutter analyze` / `flutter test` in `frontend/`. API editing tests require
the built Haskell executable. Python tests use temporary databases and mocked LLM
responses; they do not require an API key or incur model charges.

- [API setup, configuration and persistence](backend/api/README.md)
- [Haskell engine build and development](backend/logic_engine/README.md)
- [Frontend development and platforms](frontend/README.md)
- [Current domain architecture](docs/domain-architecture.md)
- [Objects v2](docs/object-language-v2.md), [Network v2](docs/network-language-v2.md),
  [Cellular v2](docs/cellular-language-v2.md)

Worlds, dialogue, saved slots and local LLM accounting persist in
`backend/api/data/conversations.sqlite3` by default. Preserve that file across
restarts; deleting it also removes saved state and local accounting history.
