from uuid import UUID, uuid4

from .repository import ConversationRepository
from .engine import LogicEngine
from .schemas import ConversationState, EditState, World


class ConversationService:
    def __init__(self, repository: ConversationRepository, initial_world: World,
                 engine: LogicEngine):
        self.repository = repository
        self.initial_world = initial_world
        self.engine = engine

    def create(self) -> ConversationState:
        return self.repository.create(uuid4(), self.initial_world.model_copy(deep=True))

    def get(self, conversation_id: UUID) -> ConversationState | None:
        return self.repository.get(conversation_id)

    def edit(self, conversation_id: UUID, action: dict) -> EditState | None:
        return self.repository.edit(conversation_id, lambda world: self.engine.edit(world, action))

    def undo(self, conversation_id: UUID) -> EditState | None:
        return self.repository.undo(conversation_id)
