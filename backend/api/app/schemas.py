from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StrictInt, model_validator


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


class ChatMessage(Schema):
    role: Literal["user", "machine"]
    text: str
    isError: bool = False


class ChatEntry(Schema):
    text: str = Field(min_length=1)


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


class ConversationState(Schema):
    conversationId: UUID
    domain: DomainId
    world: World
    canUndo: bool
    messages: list[ChatMessage] = Field(default_factory=list)
    pending: PendingEntry | None = None


class EditState(ConversationState):
    feedback: str


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
