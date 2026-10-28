"""Loopback-only API for the separate Calendar LLM-only chat."""
from typing import Literal

from fastapi import APIRouter, Depends, Request
from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator

from .calendar_routes import local_calendar

router = APIRouter(prefix='/calendar/llm-only', tags=['calendar-llm-only'],
                   dependencies=[Depends(local_calendar)])


class Action(BaseModel):
    model_config = ConfigDict(extra='forbid')
    type: Literal['message','resume','accept','reject','cancel','reconcile','continue','keepPartial']
    revision: int = Field(ge=0)
    text: str = Field(default='', max_length=20000)
    timeMin: AwareDatetime | None = None
    timeMax: AwareDatetime | None = None
    proposalId: str | None = Field(default=None, max_length=100)

    @model_validator(mode='after')
    def both_bounds(self):
        if (self.timeMin is None)!=(self.timeMax is None):
            raise ValueError('Provide both week endpoints')
        return self


@router.get('/dialogue')
async def get_dialogue(request: Request):
    return request.app.state.calendar_llm_only.public()


@router.post('/dialogue')
async def act(body: Action, request: Request):
    return await request.app.state.calendar_llm_only.act(body.model_dump(mode='json'))
