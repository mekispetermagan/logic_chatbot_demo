from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .config import Settings, INITIAL_WORLD_PATHS
from .database import Database
from .engine import EngineUnavailable, EngineInvalidRequest, LogicEngine
from .repository import ConversationRepository, PendingConflict
from .routes import router
from .schemas import World
from .service import ConversationService


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings if settings is not None else Settings.from_environment()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        database = Database(settings.database_path)
        database.initialize()
        initial_worlds = {domain: World.model_validate_json(path.read_text(encoding="utf-8"))
                          for domain, path in INITIAL_WORLD_PATHS.items()}
        app.state.conversation_service = ConversationService(
            ConversationRepository(database), initial_worlds, LogicEngine(settings.engine_path)
        )
        yield

    app = FastAPI(title="Logic Chatbot Demo API", lifespan=lifespan)

    @app.exception_handler(EngineUnavailable)
    async def engine_unavailable(request, exception):
        return JSONResponse(status_code=503, content={"detail": "Logic engine unavailable"})

    @app.exception_handler(EngineInvalidRequest)
    async def engine_invalid_request(request, exception):
        return JSONResponse(status_code=422, content={"detail": str(exception)})

    @app.exception_handler(PendingConflict)
    async def pending_conflict(request, exception):
        return JSONResponse(status_code=409, content={"detail": str(exception)})

    app.add_middleware(CORSMiddleware, allow_origins=list(settings.cors_origins),
                       allow_methods=["GET", "POST"], allow_headers=["Accept", "Content-Type"])
    app.include_router(router)
    return app


app = create_app()
