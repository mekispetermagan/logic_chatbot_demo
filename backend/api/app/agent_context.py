"""Bound transport history without changing stored outcomes or world semantics."""
import json
from collections import Counter


MAX_INPUT_BYTES = 40_000
MAX_OUTCOMES = 64


class InputTooLong(ValueError):
    pass


def _gui_update(event):
    # Only successful, non-pending GUI results can be coalesced. Keep dialogue,
    # acceptance, rejection, Undo, slot loads, errors and choices separate.
    return (event.get('kind') == 'engine_result'
            and event.get('userText') is None
            and event.get('translation') is None
            and event.get('isError') is False
            and event.get('pending') is False)


def _coalesce(events):
    """Return (transport event, original event count) pairs in original order."""
    result, run = [], []

    def flush():
        if len(run) == 1:
            result.append((run[0], 1))
        elif run:
            result.append(({
                **run[-1], 'count': len(run), 'historyCompacted': True,
                'notice': ('Consecutive successful visual editor updates; feedback describes '
                           'only the last update. Use the supplied current world.'),
            }, len(run)))
        run.clear()

    for event in events:
        if _gui_update(event):
            run.append(event)
        else:
            flush()
            result.append((event, 1))
    flush()
    return result


def build_input(text, world, events, clarification=None):
    """Keep the current request intact; retain only a bounded recent event suffix.

    Omission is explicit, and complete events are omitted rather than cutting
    programs or feedback in half. Cursor advancement is the caller's job, only
    after the remote turn has been observed. No database data is changed here.
    """
    payload = {'entry': text, 'world': world, 'outcomes': []}
    if clarification is not None:
        payload['clarification'] = clarification

    def encode():
        return json.dumps(payload, separators=(',', ':'))

    if len(encode().encode('utf-8')) > MAX_INPUT_BYTES:
        raise InputTooLong('Entry, current world or clarification exceeds the LLM input limit.')

    compacted = _coalesce(events)
    retained = compacted[-MAX_OUTCOMES:]
    omitted = Counter()
    for event, count in compacted[:-MAX_OUTCOMES]:
        omitted[event.get('kind', 'unknown')] += count
    while True:
        coalesced = sum(count for _, count in retained if count > 1)
        payload['outcomes'] = [event for event, _ in retained]
        if coalesced or omitted:
            payload['historySummary'] = {
                'coalescedGuiEvents': coalesced,
                'omittedEvents': sum(omitted.values()),
                'omittedByKind': dict(sorted(omitted.items())),
                'notice': ('History was compacted for this request; full history remains in '
                           'the database. The current world is authoritative. Do not invent '
                           'omitted details; ask if missing context matters.'),
            }
        encoded = encode()
        if len(encoded.encode('utf-8')) <= MAX_INPUT_BYTES:
            return encoded
        if not retained:
            raise InputTooLong('Entry, current world or clarification leaves no room for the history omission notice.')
        event, count = retained.pop(0)
        omitted[event.get('kind', 'unknown')] += count
