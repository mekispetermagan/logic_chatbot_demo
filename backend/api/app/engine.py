import json
import subprocess
from pathlib import Path

from pydantic import Field, ValidationError

from .schemas import Schema, World, PendingEntry


class EngineUnavailable(Exception):
    pass


class EngineReply(Schema):
    world: World
    feedback: str
    isError: bool = False
    salience: list[dict] = Field(default_factory=list)
    pending: PendingEntry | None = None


class LogicEngine:
    """Transport only: the Haskell executable decides every world change."""

    def __init__(self, executable: Path, timeout: float = 5):
        self.executable = executable
        self.timeout = timeout

    def edit(self, world: World, action: dict, salience: list[dict] | None = None,
             pending: PendingEntry | None = None) -> EngineReply:
        try:
            result = subprocess.run(
                [str(self.executable)],
                input=json.dumps({"world": world.model_dump(), "action": action,
                                  "salience": salience or [],
                                  "pending": pending.model_dump() if pending else None}),
                capture_output=True, text=True, encoding="utf-8",
                timeout=self.timeout, check=True,
            )
            reply = EngineReply.model_validate_json(result.stdout)
        except (OSError, subprocess.SubprocessError, ValidationError, UnicodeError) as error:
            raise EngineUnavailable("Logic engine unavailable") from error
        return reply
