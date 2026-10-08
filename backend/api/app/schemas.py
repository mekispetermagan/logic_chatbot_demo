from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StrictInt


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


class ConversationState(Schema):
    conversationId: UUID
    world: World
    canUndo: bool


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
