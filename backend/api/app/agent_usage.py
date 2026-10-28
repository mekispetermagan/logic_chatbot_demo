"""Read delayed provider accounting; never submit or replay an agent input."""
import asyncio
from datetime import datetime, timezone
import logging
import time

from .agent_llm import remote_id
from .llm import create_client

LOGGER = logging.getLogger(__name__)


def epoch(value):
    if isinstance(value, (float, int)):
        return float(value)
    if isinstance(value, str):
        parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
        return (parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)).timestamp()
    return None


class AgentUsageReconciler:
    def __init__(self, translator):
        self.translator = translator
        self.database = translator.ledger.database
        self._session_poll = {}

    def reconcile(self):
        translator = self.translator
        with self.database.connection() as db:
            rows = [dict(r) for r in db.execute('''SELECT r.*, t.session_id, t.turn_id, t.next_poll
                FROM llm_requests r LEFT JOIN llm_agent_turns t ON t.reservation_id=r.id
                WHERE r.cost_nano IS NULL AND (t.next_poll IS NULL OR t.next_poll<=?)
                ORDER BY r.created_at LIMIT 100''', (time.time(),))]
            sessions = {r['conversation_id']: r['session_id'] for table in
                        ('llm_sessions', 'calendar_llm_sessions') for r in db.execute('SELECT * FROM '+table)}
        groups = {}
        for row in rows:
            session = row['session_id'] or sessions.get(row['conversation_id'])
            if session:
                groups.setdefault(session, []).append(row)
        deadline = time.monotonic()+20
        with create_client() as client:
            for session, requests in groups.items():
                if self._session_poll.get(session, 0) > time.time():
                    continue
                if time.monotonic() >= deadline:
                    break
                try:
                    turns, cursor = [], None
                    for _ in range(10):
                        page = translator.request(client, 'GET', '/sessions/'+remote_id(session)+'/turns',
                            {'operation': 'usage-reconciliation'}, deadline,
                            params={'order': 'desc', 'limit': 100, **({'after': cursor} if cursor else {})})
                        turns.extend(page['data'])
                        if not page.get('has_more'):
                            break
                        cursor = page.get('last_id')
                        if not cursor:
                            break
                    self.apply(session, requests, turns)
                except Exception as error:
                    # No request payloads or credentials in this diagnostic.
                    LOGGER.warning('Delayed agent usage remains pending (%s)', type(error).__name__)
                finally:
                    self._session_poll[session] = time.time()+15
                    with self.database.connection() as db:
                        db.execute('UPDATE llm_agent_turns SET next_poll=? WHERE session_id=?',
                                   (time.time()+15, session))

    def apply(self, session, requests, turns):
        by_id = {t['id']: t for t in turns if t.get('session_id') == session}
        # Older releases did not persist reservation/turn links. Recover only
        # unambiguous timestamp matches in the same conversation's saved session.
        unbound = [r for r in requests if not r['turn_id']]
        with self.database.connection() as db:
            bound_ids = {r[0] for r in db.execute('SELECT turn_id FROM llm_agent_turns')}
        candidates = {}
        for row in unbound:
            start = epoch(row['created_at'])
            candidates[row['id']] = [t for t in by_id.values() if t['id'] not in bound_ids
                and epoch(t.get('created_at')) is not None and 0 <= epoch(t['created_at'])-start <= 15]
        for row in requests:
            turn = by_id.get(row['turn_id']) if row['turn_id'] else None
            if not row['turn_id']:
                matches = candidates[row['id']]
                if len(matches) == 1 and sum(any(t['id']==matches[0]['id'] for t in xs) for xs in candidates.values()) == 1:
                    turn = matches[0]
                    with self.database.connection() as db:
                        db.execute('INSERT OR IGNORE INTO llm_agent_turns (reservation_id,session_id,turn_id) '
                                   'VALUES (?,?,?)', (row['id'],session,turn['id']))
            if turn and turn.get('status') in ('completed', 'failed', 'cancelled') and turn.get('usage') is not None:
                try:
                    with self.database.connection() as db:
                        link = db.execute('SELECT turn_id FROM llm_agent_turns WHERE reservation_id=?', (row['id'],)).fetchone()
                    if not link or link['turn_id'] != turn['id']:
                        continue
                    self.translator.ledger.settle(row['id'],
                        {'id': turn['id'], 'model': self.translator_model, 'usage': turn['usage']}, agent=True)
                except (ValueError, KeyError, TypeError):
                    LOGGER.warning('Invalid delayed agent usage; reservation retained')

    @property
    def translator_model(self):
        from .llm_budget import MODEL
        return MODEL

    async def run(self):
        while True:
            await asyncio.sleep(5)
            try:
                await asyncio.to_thread(self.reconcile)
            except Exception as error:
                LOGGER.warning('Usage reconciliation will retry (%s)', type(error).__name__)
