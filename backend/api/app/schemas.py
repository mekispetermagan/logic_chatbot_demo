from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StrictBool, StrictInt, model_validator, model_serializer


class Schema(BaseModel):
    model_config = ConfigDict(extra="forbid")


DomainId = Literal["objects", "network"]


class CreateConversation(Schema):
    domain: DomainId


class Position(Schema):
    x: StrictInt
    y: StrictInt


class WorldObject(Schema):
    id: StrictInt
    attributes: dict[str, str]
    position: Position | None = None


class World(Schema):
    width: StrictInt = Field(gt=0)
    height: StrictInt = Field(gt=0)
    objects: list[WorldObject]


class LlmUsage(Schema):
    status: str
    model: str = "gpt-6-luna"
    requestId: str | None = None
    translation: str | None = None
    inputTokens: int | None = None
    cachedTokens: int | None = None
    cacheWriteTokens: int | None = None
    outputTokens: int | None = None
    reasoningTokens: int | None = None
    costUsd: float | None = None
    reservedUsd: float = 0


class LlmBudget(Schema):
    limitUsd: float = 1
    spentUsd: float = 0
    reservedUsd: float = 0
    remainingUsd: float = 1
    requestCount: int = 0


class ChatMessage(Schema):
    role: Literal["user", "machine"]
    text: str
    isError: bool = False
    llm: LlmUsage | None = None

    @model_serializer(mode="wrap")
    def serialize_message(self, handler):
        value = handler(self)
        if self.llm is None:
            value.pop("llm", None)
        return value


class ChatEntry(Schema):
    text: str = Field(min_length=1)
    useLlm: StrictBool = False


class ClarificationChoice(Schema):
    objectId: StrictInt | None = Field(default=None, ge=0)
    position: Position | None = None

    @model_validator(mode="after")
    def exactly_one_choice(self):
        if (self.objectId is None) == (self.position is None):
            raise ValueError("Choose an object or a square")
        return self


class Candidate(Schema):
    objectId: StrictInt = Field(ge=0)
    label: str


class PendingEntry(Schema):
    sentence: str
    remaining: str
    candidateIds: list[StrictInt]
    candidates: list[Candidate]
    resolvedSubjects: list[StrictInt] = Field(default_factory=list)
    squareChoices: list[Position] = Field(default_factory=list)


class InterpretationCandidate(Schema):
    rank: StrictInt = Field(ge=1, le=3)
    interpretation: str
    translation: str = Field(min_length=1)
    explanation: str


class InterpretationFailure(Schema):
    interpretation: str
    translation: str
    reason: str


class InterpretationTurn(Schema):
    question: str
    answer: str


class InterpretationAnswer(Schema):
    text: str = Field(min_length=1)


class InterpretationProposal(Schema):
    id: UUID
    originalText: str
    question: str = ''
    explanation: str = ''
    candidates: list[InterpretationCandidate] = Field(default_factory=list, max_length=3)
    validationFailures: list[InterpretationFailure] = Field(default_factory=list)
    clarifications: list[InterpretationTurn] = Field(default_factory=list)
    llm: LlmUsage


class InterpretationChoice(Schema):
    rank: StrictInt = Field(ge=1, le=3)


class InterpretationPreview(Schema):
    proposalId: UUID
    rank: StrictInt
    world: World
    feedback: str
    pending: PendingEntry | None = None


class ConversationState(Schema):
    conversationId: UUID
    domain: DomainId
    world: World
    canUndo: bool
    messages: list[ChatMessage] = Field(default_factory=list)
    pending: PendingEntry | None = None
    llmBudget: LlmBudget | None = None
    proposal: InterpretationProposal | None = None


class EditState(ConversationState):
    feedback: str
    preview: InterpretationPreview | None = None


class AttributeProperty(Schema):
    attribute: str = Field(min_length=1)
    value: str = Field(min_length=1)


class PropertyEdit(Schema):
    position: Position
    property: AttributeProperty


class PortsEdit(Schema):
    position: Position
    ports: list[Literal["north", "east", "south", "west"]]


class PlaceEdit(Schema):
    objectId: StrictInt = Field(ge=0)
    position: Position


class EraseEdit(Schema):
    position: Position
