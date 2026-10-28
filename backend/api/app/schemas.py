from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StrictBool, StrictInt, model_validator, model_serializer


class Schema(BaseModel):
    model_config = ConfigDict(extra="forbid")


DomainId = Literal["objects", "network", "cellular"]


class CreateConversation(Schema):
    domain: DomainId


class StepGeneration(Schema):
    """Exactly one step; no client-supplied board, rules or step count."""
    pass


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


CellColor = Literal['white', 'black', 'red', 'green', 'blue', 'yellow']
CELLULAR_BOARD_SIZE = 16
CELLULAR_CELL_COUNT = CELLULAR_BOARD_SIZE ** 2


class CellEdit(Schema):
    position: Position
    color: CellColor


class CellularRule(Schema):
    targetColor: CellColor
    neighborColor: CellColor
    counts: list[StrictInt] = Field(max_length=9)
    enabled: StrictBool = True


class CellularRuleset(Schema):
    palette: list[CellColor] = Field(min_length=2, max_length=6)
    neighborhood: Literal[4, 8]
    rules: dict[CellColor, CellularRule]

    @model_validator(mode='after')
    def valid_configuration(self):
        active = set(self.palette)
        if len(active) != len(self.palette):
            raise ValueError('Duplicate palette color')
        for source, rule in self.rules.items():
            if not {source, rule.targetColor, rule.neighborColor} <= active:
                raise ValueError('Rules must use active colors')
            if source == rule.targetColor:
                raise ValueError('A rule target must differ from its source')
            if len(set(rule.counts)) != len(rule.counts) or any(n < 0 or n > self.neighborhood for n in rule.counts):
                raise ValueError('Counts must be distinct integers within the neighborhood')
        return self


class RulesetEdit(Schema):
    ruleset: CellularRuleset
    refill: StrictBool = False


class CellularWorld(Schema):
    width: StrictInt = Field(default=CELLULAR_BOARD_SIZE, ge=CELLULAR_BOARD_SIZE, le=CELLULAR_BOARD_SIZE)
    height: StrictInt = Field(default=CELLULAR_BOARD_SIZE, ge=CELLULAR_BOARD_SIZE, le=CELLULAR_BOARD_SIZE)
    topology: Literal['torus'] = 'torus'
    # A1, B1, ..., P1, A2, ..., P16: y increases from the bottom of the board.
    cells: list[CellColor] = Field(min_length=CELLULAR_CELL_COUNT, max_length=CELLULAR_CELL_COUNT)
    ruleset: CellularRuleset
    generation: StrictInt = Field(default=0, ge=0)
    rulesetRevision: StrictInt = Field(default=1, ge=1)

    @model_validator(mode='after')
    def active_cells(self):
        if not set(self.cells) <= set(self.ruleset.palette):
            raise ValueError('A cell uses an inactive color')
        return self


WorldState = World | CellularWorld


def world_from_json(domain: DomainId, source: str) -> WorldState:
    model = CellularWorld if domain == 'cellular' else World
    return model.model_validate_json(source)


def validate_world_domain(domain: DomainId, world: WorldState):
    if (domain == 'cellular') != isinstance(world, CellularWorld):
        raise ValueError('World representation does not match its domain')


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
    inputTokens: int = 0
    outputTokens: int = 0
    pendingUsageCount: int = 0


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
    groupingId: StrictInt | None = Field(default=None, ge=1)

    @model_validator(mode="after")
    def exactly_one_choice(self):
        if sum(value is not None for value in (self.objectId, self.position, self.groupingId)) != 1:
            raise ValueError("Choose an object, square, or grouping")
        return self


class Candidate(Schema):
    objectId: StrictInt = Field(ge=0)
    label: str


class GroupingCandidate(Schema):
    groupingId: StrictInt = Field(ge=1)
    label: str


class PendingEntry(Schema):
    sentence: str
    remaining: str
    candidateIds: list[StrictInt]
    candidates: list[Candidate]
    resolvedSubjects: list[StrictInt] = Field(default_factory=list)
    squareChoices: list[Position] = Field(default_factory=list)
    groupingChoices: list[GroupingCandidate] = Field(default_factory=list)
    payload: dict | None = None
    stagedWorld: WorldState | None = None


class WorldChange(Schema):
    objectId: StrictInt = Field(ge=0)
    kind: Literal['created', 'deleted', 'position', 'appearance']
    detail: str


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
    languageVersion: str = 'unknown'
    executionSeed: StrictInt | None = Field(default=None, ge=0, lt=2**64)


class InterpretationChoice(Schema):
    rank: StrictInt = Field(ge=1, le=3)


class InterpretationPreview(Schema):
    proposalId: UUID
    rank: StrictInt
    world: WorldState
    feedback: str
    pending: PendingEntry | None = None
    changes: list[WorldChange] = Field(default_factory=list)


class WorldSlot(Schema):
    slot: StrictInt = Field(ge=1, le=5)
    savedAt: str | None = None


class SaveWorldSlot(Schema):
    overwrite: StrictBool = False


class ConversationState(Schema):
    conversationId: UUID
    domain: DomainId
    world: WorldState
    canUndo: bool
    messages: list[ChatMessage] = Field(default_factory=list)
    pending: PendingEntry | None = None
    llmBudget: LlmBudget | None = None
    proposal: InterpretationProposal | None = None
    languageVersion: str = 'unknown'
    nextObjectId: StrictInt = Field(default=0, ge=0)
    worldSlots: list[WorldSlot] = Field(default_factory=list)
    resetPending: bool = False
    resetFrom: UUID | None = None

    @model_validator(mode='after')
    def world_matches_domain(self):
        validate_world_domain(self.domain, self.world)
        return self


class EditState(ConversationState):
    feedback: str
    preview: InterpretationPreview | None = None
    changes: list[WorldChange] = Field(default_factory=list)
    changedCells: StrictInt | None = Field(default=None, ge=0, le=CELLULAR_CELL_COUNT)


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
