from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StrictInt, model_validator


class Schema(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Position(Schema):
    x: StrictInt
    y: StrictInt


class WorldObject(Schema):
    id: StrictInt
    shape: Literal["cube", "sphere", "pyramid"] | None = None
    size: Literal["small", "medium", "large"] | None = None
    color: Literal["red", "blue", "green", "yellow"] | None = None
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
    world: World
    canUndo: bool
    messages: list[ChatMessage] = Field(default_factory=list)
    pending: PendingEntry | None = None


class EditState(ConversationState):
    feedback: str


class PropertyEdit(Schema):
    position: Position
    property: Literal["red", "blue", "green", "yellow", "small", "medium", "large",
                      "cube", "sphere", "pyramid"]


class PlaceEdit(Schema):
    objectId: StrictInt = Field(ge=0)
    position: Position


class EraseEdit(Schema):
    position: Position
