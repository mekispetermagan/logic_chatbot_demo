from uuid import UUID, uuid4

from .repository import ConversationRepository, PendingConflict
from .engine import LogicEngine
from .llm import LlmTranslator
from .schemas import (ConversationState, EditState, World, ClarificationChoice, DomainId,
                      InterpretationProposal, InterpretationFailure, InterpretationTurn)


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
        attempt = None
        if use_llm and self.translator is not None:
            snapshot = self.repository.get_with_revision(conversation_id)
            if snapshot is None:
                return None
            state, revision = snapshot
            if state.proposal is not None:
                raise PendingConflict('Accept or reject the interpretation first')
            if state.pending is None:
                checked = self.engine.edit(state.domain, state.world, {'type': 'checkSyntax', 'text': text})
                if checked.syntaxError:
                    attempt = self.translator.translate(conversation_id, state.domain, text, state.world)
                    if attempt.usage.status == 'conversation':
                        return self.repository.converse(conversation_id, text, attempt.reply, attempt.usage, revision)
                    proposal = self._interpretation_proposal(conversation_id, state, text, attempt)
                    if proposal is not None:
                        return self.repository.propose(conversation_id, proposal, revision,
                                                       self._with_reply(attempt.reply, self._proposal_feedback(proposal)))
        def update(domain, world, salience, pending):
            reply = self.engine.edit(domain, world, {'type': 'chat', 'text': text}, salience, pending)
            if attempt is not None and attempt.note:
                reply.feedback += '\n\n' + attempt.note
            if attempt is not None:
                reply.feedback = self._with_reply(attempt.reply, reply.feedback)
            return reply
        return self.repository.edit(conversation_id, update, user_text=text,
                                    llm=attempt.usage if attempt else None)

    def _interpretation_proposal(self, conversation_id, state, text, attempt, clarifications=None):
        valid, failures, seen = [], [], set()
        for candidate in attempt.candidates:
            checked = self.engine.edit(state.domain, state.world,
                                       {'type': 'checkSyntax', 'text': candidate.translation})
            if checked.isError:
                failures.append(InterpretationFailure(interpretation=candidate.interpretation,
                                                      translation=candidate.translation,
                                                      reason=self.translator.safe_text(checked.feedback, 1000)))
                self.translator.log_feedback('parser rejection', conversationId=str(conversation_id),
                                             requestId=attempt.usage.requestId, rank=candidate.rank,
                                             translation=candidate.translation, parserFeedback=checked.feedback)
            elif checked.feedback not in seen:
                seen.add(checked.feedback)
                valid.append(candidate.model_copy(update={'rank': len(valid) + 1}))
        if not (valid or failures or attempt.question):
            return None
        attempt.usage.status = 'proposed' if valid else 'invalid' if failures else 'clarification'
        proposal = InterpretationProposal(id=uuid4(), originalText=text, candidates=valid,
                                          question=attempt.question, explanation=attempt.explanation,
                                          validationFailures=failures, clarifications=clarifications or [],
                                          llm=attempt.usage)
        self.translator.log_feedback('proposal', conversationId=str(conversation_id), proposalId=str(proposal.id),
                                     candidates=[c.model_dump() for c in valid], question=proposal.question,
                                     validationFailures=[failure.model_dump() for failure in failures])
        return proposal

    def _proposal_feedback(self, proposal):
        if proposal.candidates:
            feedback = 'Interpretations ready for review; nothing was applied.'
        elif proposal.validationFailures:
            feedback = 'Translation failed validation; nothing was applied.'
        elif proposal.question:
            feedback = 'Please clarify your request; nothing was applied.'
        else:
            feedback = 'No valid translation; nothing was applied.'
        if proposal.question:
            feedback += '\n' + proposal.question
        if proposal.explanation:
            feedback += '\n' + proposal.explanation
        for failure in proposal.validationFailures:
            feedback += '\nDiscarded translation: ' + failure.reason
        return feedback

    def _with_reply(self, reply, feedback):
        return reply + '\n\n' + feedback if reply else feedback

    def answer(self, conversation_id: UUID, proposal_id: UUID, text: str) -> EditState | None:
        snapshot = self.repository.proposal_with_revision(conversation_id, proposal_id)
        if snapshot is None:
            return None
        state, revision = snapshot
        previous = state.proposal
        if previous.candidates and not (previous.question or previous.validationFailures):
            raise PendingConflict('No clarification pending; accept or reject the interpretation')
        if self.translator is None:
            raise PendingConflict('LLM is not configured on the server')
        turns = [*previous.clarifications, InterpretationTurn(question=previous.question, answer=text)]
        context = {
            'turns': [turn.model_dump() for turn in turns],
            'previousCandidates': [candidate.model_dump() for candidate in previous.candidates],
            'validationFailures': [failure.model_dump() for failure in previous.validationFailures],
        }
        attempt = self.translator.translate(conversation_id, state.domain, previous.originalText,
                                            state.world, clarification=context)
        if attempt.usage.status == 'conversation':
            return self.repository.converse(conversation_id, text, attempt.reply, attempt.usage, revision,
                                            proposal_id=proposal_id)
        proposal = self._interpretation_proposal(conversation_id, state, previous.originalText, attempt, turns)
        if proposal is None:
            # Preserve a reviewable draft and the answer even on provider failure;
            # never fall back to executing an earlier, now-refined interpretation.
            proposal = InterpretationProposal(id=uuid4(), originalText=previous.originalText,
                                              clarifications=turns, llm=attempt.usage,
                                              explanation=attempt.note or attempt.explanation)
        self.translator.log_feedback('answer', conversationId=str(conversation_id), proposalId=str(proposal_id),
                                     replacementId=str(proposal.id), question=previous.question, answer=text)
        return self.repository.propose(conversation_id, proposal, revision,
                                       self._with_reply(attempt.reply, self._proposal_feedback(proposal)),
                                       replacing_proposal=proposal_id, answer=text)

    def _evaluate_interpretation(self, domain, world, salience, text):
        return self.engine.edit(domain, world, {'type': 'chat', 'text': text}, salience)

    def preview(self, conversation_id: UUID, proposal_id: UUID, rank: int) -> EditState | None:
        state = self.repository.preview(conversation_id, proposal_id, rank, self._evaluate_interpretation)
        if state is not None and self.translator is not None:
            self.translator.log_feedback('preview', conversationId=str(conversation_id), proposalId=str(proposal_id),
                                         rank=rank, feedback=state.preview.feedback)
        return state

    def accept(self, conversation_id: UUID, proposal_id: UUID, rank: int) -> EditState | None:
        state = self.repository.accept(conversation_id, proposal_id, rank, self._evaluate_interpretation)
        if state is not None and self.translator is not None:
            self.translator.log_feedback('accepted', conversationId=str(conversation_id), proposalId=str(proposal_id),
                                         rank=rank, feedback=state.feedback)
        return state

    def reject(self, conversation_id: UUID, proposal_id: UUID) -> EditState | None:
        state = self.repository.reject(conversation_id, proposal_id)
        if state is not None and self.translator is not None:
            self.translator.log_feedback('rejected', conversationId=str(conversation_id), proposalId=str(proposal_id))
        return state

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
