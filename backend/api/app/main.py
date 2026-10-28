from contextlib import asynccontextmanager, suppress
import asyncio
from .agent_usage import AgentUsageReconciler

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .config import Settings, INITIAL_WORLD_PATHS
from .database import Database
from .engine import EngineUnavailable, EngineInvalidRequest, LogicEngine
from .repository import ConversationRepository, PendingConflict, SnapshotConflict, WorldSlotEmpty
from .routes import router
from .schemas import world_from_json
from .service import ConversationService
from .llm import LlmTranslator
from .llm_budget import LlmBudgetLedger
from .llm_transcript import LlmTranscript
from .agent_llm import AgentTranslator
from .calendar_mcp import CalendarError, CalendarMcp
from .calendar_dialogue import CalendarDialogue
from .calendar_llm_dialogue import CalendarLlmDialogue
from .calendar_llm_routes import router as calendar_llm_router
from .calendar_routes import router as calendar_router
from .language_help import router as language_help_router


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings if settings is not None else Settings.from_environment()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        database = Database(settings.database_path)
        database.initialize()
        initial_worlds = {domain: world_from_json(domain, path.read_text(encoding="utf-8"))
                          for domain, path in INITIAL_WORLD_PATHS.items()}
        if settings.llm_backend not in ('agents', 'responses'):
            raise ValueError('LOGIC_CHATBOT_LLM_BACKEND must be agents or responses')
        translator_class = AgentTranslator if settings.llm_backend == 'agents' else LlmTranslator
        app.state.conversation_service = ConversationService(
            ConversationRepository(database), initial_worlds, LogicEngine(settings.engine_path),
            translator_class(settings.openai_api_key, LlmBudgetLedger(database),
                          LlmTranscript(settings.llm_log_path, settings.openai_api_key)
                          if settings.llm_log_path is not None else None)
        )
        app.state.calendar = CalendarMcp(settings)
        app.state.calendar_dialogue = CalendarDialogue(database, settings.engine_path, lambda: app.state.calendar, app.state.conversation_service.translator)
        translator = app.state.conversation_service.translator
        app.state.calendar_llm_only = CalendarLlmDialogue(database, settings,
            lambda: app.state.calendar, app.state.calendar_dialogue, translator.transcript)
        usage_task = (asyncio.create_task(AgentUsageReconciler(app.state.calendar_llm_only.agent).run())
                      if settings.openai_api_key else None)
        try:
            yield
        finally:
            if usage_task:
                usage_task.cancel()
                with suppress(asyncio.CancelledError):
                    await usage_task

    app = FastAPI(title="Logic Chatbot Demo API", lifespan=lifespan)

    @app.exception_handler(CalendarError)
    async def calendar_error(request, exception):
        content = {'detail': exception.detail}
        if exception.outcome_unknown:
            content.update(eventId=exception.event_id, outcomeUnknown=True)
        return JSONResponse(status_code=exception.status_code, content=content)

    @app.exception_handler(EngineUnavailable)
    async def engine_unavailable(request, exception):
        return JSONResponse(status_code=503, content={"detail": "Logic engine unavailable"})

    @app.exception_handler(EngineInvalidRequest)
    async def engine_invalid_request(request, exception):
        return JSONResponse(status_code=422, content={"detail": str(exception)})

    @app.exception_handler(PendingConflict)
    async def pending_conflict(request, exception):
        return JSONResponse(status_code=409, content={"detail": str(exception)})

    @app.exception_handler(SnapshotConflict)
    async def snapshot_conflict(request, exception):
        return JSONResponse(status_code=409, content={"detail": str(exception)})

    @app.exception_handler(WorldSlotEmpty)
    async def world_slot_empty(request, exception):
        return JSONResponse(status_code=404, content={"detail": str(exception)})

    app.add_middleware(CORSMiddleware, allow_origins=list(settings.cors_origins),
                       allow_methods=["GET", "POST", "PATCH", "DELETE"], allow_headers=["Accept", "Content-Type"])
    app.include_router(router)
    app.include_router(calendar_router)
    app.include_router(calendar_llm_router)
    app.include_router(language_help_router)
    return app


app = create_app()
