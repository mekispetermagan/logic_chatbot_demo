from uuid import UUID, uuid4

from .repository import ConversationRepository
from .engine import LogicEngine
from .schemas import ConversationState, EditState, World, ClarificationChoice, DomainId


class ConversationService:
    def __init__(self, repository: ConversationRepository, initial_worlds: dict[DomainId, World],
                 engine: LogicEngine):
        self.repository = repository
        self.initial_worlds = initial_worlds
        self.engine = engine

    def create(self, domain: DomainId) -> ConversationState:
        return self.repository.create(uuid4(), self.initial_worlds[domain].model_copy(deep=True), domain)

    def get(self, conversation_id: UUID) -> ConversationState | None:
        return self.repository.get(conversation_id)

    def edit(self, conversation_id: UUID, action: dict) -> EditState | None:
        return self.repository.edit(conversation_id, lambda domain, world, salience, pending: self.engine.edit(domain, world, action, salience, pending))

    def undo(self, conversation_id: UUID) -> EditState | None:
        return self.repository.undo(conversation_id)

    def chat(self, conversation_id: UUID, text: str) -> EditState | None:
        return self.repository.edit(conversation_id,
            lambda domain, world, salience, pending: self.engine.edit(domain, world, {"type": "chat", "text": text}, salience, pending), user_text=text)

    def clarify(self, conversation_id: UUID, choice: ClarificationChoice) -> EditState | None:
        action = {"type": "clarify", **choice.model_dump(exclude_none=True)}
        if choice.objectId is not None:
            label = f"#{choice.objectId}"
        else:
            x, y = choice.position.x, choice.position.y
            label = f"{chr(65 + x)}{y + 1}" if 0 <= x < 8 and 0 <= y < 8 else f"({x}, {y})"
        return self.repository.edit(conversation_id,
            lambda domain, world, salience, pending: self.engine.edit(domain, world, action, salience, pending),
            user_text=label, continuation=True)
