from uuid import UUID, uuid4

from .repository import ConversationRepository
from .engine import LogicEngine
from .llm import LlmTranslator
from .schemas import ConversationState, EditState, World, ClarificationChoice, DomainId


class ConversationService:
    def __init__(self, repository: ConversationRepository, initial_worlds: dict[DomainId, World],
                 engine: LogicEngine, translator: LlmTranslator | None = None):
        self.repository = repository
        self.initial_worlds = initial_worlds
        self.engine = engine
        self.translator = translator

    def create(self, domain: DomainId) -> ConversationState:
        return self.repository.create(uuid4(), self.initial_worlds[domain].model_copy(deep=True), domain)

    def get(self, conversation_id: UUID) -> ConversationState | None:
        return self.repository.get(conversation_id)

    def edit(self, conversation_id: UUID, action: dict) -> EditState | None:
        return self.repository.edit(conversation_id, lambda domain, world, salience, pending: self.engine.edit(domain, world, action, salience, pending))

    def undo(self, conversation_id: UUID) -> EditState | None:
        return self.repository.undo(conversation_id)

    def chat(self, conversation_id: UUID, text: str, use_llm: bool = False) -> EditState | None:
        interpreted, attempt = text, None
        expected_revision = None
        if use_llm and self.translator is not None:
            snapshot = self.repository.get_with_revision(conversation_id)
            if snapshot is None:
                return None
            state, revision = snapshot
            if state.pending is None:
                checked = self.engine.edit(state.domain, state.world, {'type': 'checkSyntax', 'text': text})
                if checked.syntaxError:
                    attempt = self.translator.translate(conversation_id, state.domain, text, state.world)
                    if attempt.translation:
                        candidate = self.engine.edit(state.domain, state.world,
                                                     {'type': 'checkSyntax', 'text': attempt.translation})
                        if not candidate.isError:
                            interpreted = attempt.translation
                            expected_revision = revision
                        else:
                            self.translator.log_feedback('parser rejection', conversationId=str(conversation_id),
                                                         requestId=attempt.usage.requestId,
                                                         translation=attempt.translation,
                                                         parserFeedback=candidate.feedback)
                            attempt.usage.status = 'invalid'
                            attempt.note = 'LLM interpretation did not parse; nothing was applied.'
        def update(domain, world, salience, pending):
            reply = self.engine.edit(domain, world, {'type': 'chat', 'text': interpreted}, salience, pending)
            if attempt is not None:
                if interpreted != text:
                    reply.feedback = 'Interpreted as: ' + interpreted + '\n\n' + reply.feedback
                elif attempt.note:
                    reply.feedback += '\n\n' + attempt.note
            return reply
        return self.repository.edit(conversation_id, update, user_text=text,
                                    llm=attempt.usage if attempt else None, expected_revision=expected_revision)

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
