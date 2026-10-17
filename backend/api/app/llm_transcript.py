"""Append complete API exchanges to a credential-redacted JSON Lines file."""
import json
import logging
import re
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock

LOGGER = logging.getLogger('uvicorn.error.llm')
SENSITIVE_FIELDS = frozenset({
    'authorization', 'proxyauthorization', 'apikey', 'openaiapikey', 'xapikey',
    'accesstoken', 'refreshtoken', 'clientsecret', 'password', 'secret',
    'privatekey', 'cookie', 'setcookie',
})


class LlmTranscript:
    def __init__(self, path: Path, api_key: str | None):
        self.path = path
        self._api_key = api_key
        self._lock = Lock()
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch(mode=0o600, exist_ok=True)
        except OSError:
            LOGGER.warning('GPT transcript file could not be created')

    def _redact(self, value):
        if isinstance(value, dict):
            return {self._redact(key): '[redacted]' if
                    re.sub(r'[^a-z0-9]', '', key.casefold()) in SENSITIVE_FIELDS else self._redact(item)
                    for key, item in value.items()}
        if isinstance(value, list):
            return [self._redact(item) for item in value]
        if isinstance(value, str):
            if self._api_key:
                value = value.replace(self._api_key, '[redacted]')
            value = re.sub(r'sk-[A-Za-z0-9_-]+', '[redacted]', value)
            # Messages may themselves contain encoded JSON, including credential fields.
            try:
                nested = json.loads(value)
            except ValueError:
                return value
            if isinstance(nested, (dict, list)):
                return json.dumps(self._redact(nested), ensure_ascii=False)
        return value

    def record(self, event: str, **fields) -> None:
        entry = {'timestamp': datetime.now(timezone.utc).isoformat(), 'event': event, **fields}
        encoded = json.dumps(self._redact(entry), ensure_ascii=False) + '\n'
        try:
            with self._lock, self.path.open('a', encoding='utf-8') as output:
                output.write(encoded)
        except OSError:
            # Diagnostic I/O must not turn a successful paid call into a failed edit.
            LOGGER.warning('GPT transcript could not be written')
