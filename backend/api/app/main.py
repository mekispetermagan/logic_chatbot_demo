from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .config import Settings, TOY_WORLD_PATH
from .database import Database
from .engine import EngineUnavailable, LogicEngine
from .repository import ConversationRepository
from .routes import router
from .schemas import World
from .service import ConversationService


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings if settings is not None else Settings.from_environment()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        database = Database(settings.database_path)
        database.initialize()
        initial_world = World.model_validate_json(TOY_WORLD_PATH.read_text(encoding="utf-8"))
        app.state.conversation_service = ConversationService(
            ConversationRepository(database), initial_world, LogicEngine(settings.engine_path)
        )
        yield

    app = FastAPI(title="Logic Chatbot Demo API", lifespan=lifespan)

    @app.exception_handler(EngineUnavailable)
    async def engine_unavailable(request, exception):
        return JSONResponse(status_code=503, content={"detail": "Logic engine unavailable"})

    app.add_middleware(CORSMiddleware, allow_origins=list(settings.cors_origins),
                       allow_methods=["GET", "POST"], allow_headers=["Accept", "Content-Type"])
    app.include_router(router)
    return app


app = create_app()
