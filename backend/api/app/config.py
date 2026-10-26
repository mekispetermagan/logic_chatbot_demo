import os
from dataclasses import dataclass, field
from pathlib import Path

API_DIR = Path(__file__).resolve().parents[1]
TOY_WORLD_PATH = API_DIR.parent / "shared" / "toy_world.json"
INITIAL_WORLD_PATHS = {"objects": TOY_WORLD_PATH, "network": API_DIR.parent / "shared" / "network_world.json",
                       "cellular": API_DIR.parent / "shared" / "cellular_world.json"}
ENGINE_PATH = API_DIR.parent / "logic_engine" / "bin" / "logic-engine-editor"
LLM_LOG_PATH = API_DIR / "logs" / "gpt-conversation.jsonl"


@dataclass(frozen=True)
class Settings:
    database_path: Path
    cors_origins: tuple[str, ...] = ("http://localhost:8080", "http://127.0.0.1:8080")
    engine_path: Path = ENGINE_PATH
    openai_api_key: str | None = field(default=None, repr=False)
    llm_log_path: Path | None = None
    llm_backend: str = 'agents'
    calendar_enabled: bool = False
    calendar_writes_enabled: bool = False
    calendar_node: str = 'node'
    calendar_mcp_path: Path | None = None
    google_oauth_credentials: Path | None = None
    calendar_token_path: Path | None = None
    calendar_account: str = 'demo'
    calendar_id: str = 'logic.engine.demo@gmail.com'

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
            openai_api_key=os.environ.get("OPENAI_API_KEY") or None,
            llm_log_path=Path(os.environ.get('LOGIC_CHATBOT_LLM_LOG_PATH', str(LLM_LOG_PATH))),
            llm_backend=os.environ.get('LOGIC_CHATBOT_LLM_BACKEND', 'agents'),
            calendar_enabled=os.environ.get('LOGIC_CHATBOT_CALENDAR_ENABLED', '').lower() in ('1', 'true'),
            calendar_writes_enabled=os.environ.get('LOGIC_CHATBOT_CALENDAR_WRITES_ENABLED', '').lower() in ('1', 'true'),
            calendar_node=os.environ.get('LOGIC_CHATBOT_CALENDAR_NODE', 'node'),
            calendar_mcp_path=Path(value).expanduser() if (value := os.environ.get('LOGIC_CHATBOT_CALENDAR_MCP_PATH')) else None,
            google_oauth_credentials=Path(value).expanduser() if (value := os.environ.get('GOOGLE_OAUTH_CREDENTIALS')) else None,
            calendar_token_path=Path(value).expanduser() if (value := os.environ.get('GOOGLE_CALENDAR_MCP_TOKEN_PATH')) else None,
            calendar_account=os.environ.get('LOGIC_CHATBOT_CALENDAR_ACCOUNT', 'demo'),
            calendar_id=os.environ.get('LOGIC_CHATBOT_CALENDAR_ID', 'logic.engine.demo@gmail.com'),
        )
