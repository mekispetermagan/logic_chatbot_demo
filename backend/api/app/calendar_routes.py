"""Opt-in local Calendar reads and scoped writes; no arbitrary MCP invocation."""
from typing import Annotated
from ipaddress import ip_address
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, HTTPException, Path, Request
from pydantic import AwareDatetime, BaseModel, model_validator

from .calendar_mcp import CalendarMcp
from .calendar_events import CreateEvent, UpdateEvent

router = APIRouter(prefix='/calendar', tags=['calendar'])
EventId = Annotated[str, Path(min_length=1, max_length=1024, pattern=r'^[A-Za-z0-9_-]+$')]


def local_calendar(request: Request) -> CalendarMcp:
    try:
        local = request.client is not None and ip_address(request.client.host).is_loopback
    except ValueError:
        local = False
    if not local:
        raise HTTPException(status_code=403, detail='Calendar access is limited to the local machine.')
    return request.app.state.calendar


def writable_calendar(calendar: CalendarMcp = Depends(local_calendar)) -> CalendarMcp:
    calendar.require_writes()
    return calendar


class CalendarInterval(BaseModel):
    timeMin: AwareDatetime
    timeMax: AwareDatetime
    timeZone: str

    @model_validator(mode='after')
    def valid_interval(self):
        if self.timeMin >= self.timeMax:
            raise ValueError('timeMin must precede timeMax')
        try:
            ZoneInfo(self.timeZone)
        except (ZoneInfoNotFoundError, ValueError):
            raise ValueError('timeZone must be an IANA timezone') from None
        return self


def interval(timeMin: AwareDatetime, timeMax: AwareDatetime, timeZone: str = 'Europe/Budapest'):
    # Model validators run explicitly here so interval errors are HTTP 422.
    from pydantic import ValidationError
    try:
        return CalendarInterval(timeMin=timeMin, timeMax=timeMax, timeZone=timeZone)
    except ValidationError:
        raise HTTPException(status_code=422, detail='Provide timeMin < timeMax with timezone offsets and a valid IANA timeZone.') from None


@router.get('/calendars')
async def calendars(calendar: CalendarMcp = Depends(local_calendar)):
    return await calendar.calendars()


@router.get('/events')
async def events(query: CalendarInterval = Depends(interval), calendar: CalendarMcp = Depends(local_calendar)):
    return await calendar.events(query.timeMin, query.timeMax, query.timeZone)


@router.get('/events/{event_id}')
async def event(event_id: EventId, calendar: CalendarMcp = Depends(local_calendar)):
    return await calendar.event(event_id)


@router.post('/events', status_code=201)
async def create_event(entry: CreateEvent, calendar: CalendarMcp = Depends(writable_calendar)):
    return await calendar.create_event(entry.tool_fields())


@router.patch('/events/{event_id}')
async def update_event(event_id: EventId, entry: UpdateEvent, calendar: CalendarMcp = Depends(writable_calendar)):
    return await calendar.update_event(event_id, entry.tool_fields())


@router.delete('/events/{event_id}')
async def delete_event(event_id: EventId, calendar: CalendarMcp = Depends(writable_calendar)):
    return await calendar.delete_event(event_id)


@router.get('/freebusy')
async def freebusy(query: CalendarInterval = Depends(interval), calendar: CalendarMcp = Depends(local_calendar)):
    return await calendar.freebusy(query.timeMin, query.timeMax, query.timeZone)
