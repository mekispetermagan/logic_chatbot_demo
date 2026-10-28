import json
import subprocess
from pathlib import Path

from pydantic import Field, model_validator

from .language_help import LanguageDomain, LanguageExamples
from .schemas import Schema, WorldState, PendingEntry, DomainId, WorldChange, validate_world_domain, CELLULAR_CELL_COUNT


class EngineInvalidRequest(Exception):
    pass


class EngineUnavailable(Exception):
    pass


class EngineReply(Schema):
    domain: DomainId
    world: WorldState
    feedback: str
    isError: bool = False
    undoRequested: bool = False
    syntaxError: bool = False
    salience: list[dict] = Field(default_factory=list)
    pending: PendingEntry | None = None
    languageVersion: str = 'unknown'
    nextObjectId: int | None = Field(default=None, ge=0)
    changes: list[WorldChange] = Field(default_factory=list)
    changedCells: int | None = Field(default=None, ge=0, le=CELLULAR_CELL_COUNT)

    @model_validator(mode='after')
    def world_matches_domain(self):
        validate_world_domain(self.domain, self.world)
        return self


class LogicEngine:
    """Transport only: the Haskell executable decides every world change."""

    def __init__(self, executable: Path, timeout: float = 5):
        self.executable = executable
        self.timeout = timeout

    def examples(self, domain: LanguageDomain) -> LanguageExamples:
        try:
            result = subprocess.run(
                [str(self.executable)],
                input=json.dumps({'domain': domain, 'action': {'type': 'examples'}}),
                capture_output=True, text=True, encoding='utf-8',
                timeout=self.timeout, check=True,
            )
            reply = LanguageExamples.model_validate_json(result.stdout)
            version = 'calendar-v1' if domain == 'calendar' else domain + '-v2'
            if reply.domain != domain or reply.languageVersion != version:
                raise ValueError('Unexpected language examples domain/version')
            return reply
        except (OSError, subprocess.SubprocessError, ValueError) as error:
            raise EngineUnavailable('Language examples unavailable') from error

    def edit(self, domain: DomainId, world: WorldState, action: dict, salience: list[dict] | None = None,
             pending: PendingEntry | None = None, next_object_id: int | None = None) -> EngineReply:
        try:
            result = subprocess.run(
                [str(self.executable)],
                input=json.dumps({"domain": domain, "world": world.model_dump(), "action": action,
                                  "salience": salience or [],
                                  "pending": pending.model_dump() if pending else None,
                                  'languageVersion': domain + '-v2',
                                  **({'nextObjectId': next_object_id} if next_object_id is not None else {})}),
                capture_output=True, text=True, encoding="utf-8",
                timeout=self.timeout, check=True,
            )
            reply = EngineReply.model_validate_json(result.stdout)
            if reply.domain != domain:
                raise ValueError("Unexpected engine domain")
            if reply.languageVersion != domain + '-v2' or reply.nextObjectId is None:
                raise ValueError('Logic engine does not support the v2 language contract')
        except subprocess.CalledProcessError as error:
            if error.returncode == 2:
                raise EngineInvalidRequest(error.stderr.strip() or "Invalid engine request") from error
            raise EngineUnavailable("Logic engine unavailable") from error
        except (OSError, subprocess.SubprocessError, ValueError) as error:
            raise EngineUnavailable("Logic engine unavailable") from error
        return reply
