import json
import subprocess
from pathlib import Path

from pydantic import Field

from .schemas import Schema, World, PendingEntry, DomainId


class EngineInvalidRequest(Exception):
    pass


class EngineUnavailable(Exception):
    pass


class EngineReply(Schema):
    domain: DomainId
    world: World
    feedback: str
    isError: bool = False
    undoRequested: bool = False
    syntaxError: bool = False
    salience: list[dict] = Field(default_factory=list)
    pending: PendingEntry | None = None


class LogicEngine:
    """Transport only: the Haskell executable decides every world change."""

    def __init__(self, executable: Path, timeout: float = 5):
        self.executable = executable
        self.timeout = timeout

    def edit(self, domain: DomainId, world: World, action: dict, salience: list[dict] | None = None,
             pending: PendingEntry | None = None) -> EngineReply:
        try:
            result = subprocess.run(
                [str(self.executable)],
                input=json.dumps({"domain": domain, "world": world.model_dump(), "action": action,
                                  "salience": salience or [],
                                  "pending": pending.model_dump() if pending else None}),
                capture_output=True, text=True, encoding="utf-8",
                timeout=self.timeout, check=True,
            )
            reply = EngineReply.model_validate_json(result.stdout)
            if reply.domain != domain:
                raise ValueError("Unexpected engine domain")
        except subprocess.CalledProcessError as error:
            if error.returncode == 2:
                raise EngineInvalidRequest(error.stderr.strip() or "Invalid engine request") from error
            raise EngineUnavailable("Logic engine unavailable") from error
        except (OSError, subprocess.SubprocessError, ValueError) as error:
            raise EngineUnavailable("Logic engine unavailable") from error
        return reply
