"""Local administration of app-managed interpreter associations; no provider calls."""
import argparse
import sqlite3

from .agent_store import AgentStore
from .config import Settings
from .database import Database
from .repository import PendingConflict


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['recreate'])
    parser.add_argument('--domain', required=True, choices=['objects', 'network', 'cellular', 'calendar', 'calendar-llm-only', 'all'])
    args = parser.parse_args(argv)
    settings = Settings.from_environment()
    if not settings.database_path.is_file():
        parser.exit(1, 'Application database not found. Start the backend once, or check LOGIC_CHATBOT_DB_PATH.\n')
    domains = ('objects', 'network', 'cellular', 'calendar', 'calendar-llm-only') if args.domain == 'all' else (args.domain,)
    try:
        agents, sessions = AgentStore(Database(settings.database_path)).recreate(domains)
    except PendingConflict as error:
        parser.exit(1, str(error) + '\n')
    except (sqlite3.Error, ValueError, OSError):
        parser.exit(1, 'Cannot update agent associations. Check database permissions and schema version.\n')
    print(f'Detached {agents} saved agent(s) and {sessions} session(s) for {", ".join(domains)}.')
    print('Replacement agents and sessions will be created on the next LLM request in each domain.')
    print('Local worlds, chat, review proposals, Undo, slots and accounting are preserved. No provider calls were made.')


if __name__ == '__main__':
    main()
