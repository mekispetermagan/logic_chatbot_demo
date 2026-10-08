import os
from dataclasses import dataclass
from pathlib import Path

API_DIR = Path(__file__).resolve().parents[1]
TOY_WORLD_PATH = API_DIR.parent / "shared" / "toy_world.json"
ENGINE_PATH = API_DIR.parent / "logic_engine" / "bin" / "logic-engine-editor"


@dataclass(frozen=True)
class Settings:
    database_path: Path
    cors_origins: tuple[str, ...] = ("http://localhost:8080", "http://127.0.0.1:8080")
    engine_path: Path = ENGINE_PATH

    @classmethod
    def from_environment(cls) -> "Settings":
        origins = os.environ.get(
            "LOGIC_CHATBOT_CORS_ORIGINS", "http://localhost:8080,http://127.0.0.1:8080"
        )
        return cls(
            database_path=Path(os.environ.get(
                "LOGIC_CHATBOT_DB_PATH", str(API_DIR / "data" / "conversations.sqlite3")
            )),
            cors_origins=tuple(origin.strip() for origin in origins.split(",") if origin.strip()),
            engine_path=Path(os.environ.get("LOGIC_CHATBOT_ENGINE_PATH", str(ENGINE_PATH))),
        )
