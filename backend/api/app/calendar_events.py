"""Transport validation for the initial one-off calendar event editor."""
import re
from datetime import date as Date, datetime
from typing import Annotated, Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator

Summary = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1024)]
ColorId = Literal['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11']


class EventTime(BaseModel):
    model_config = ConfigDict(extra='forbid')
    date: Date | None = None
    dateTime: AwareDatetime | None = None
    timeZone: str | None = None

    @field_validator('date', mode='before')
    @classmethod
    def date_only(cls, value):
        if value is not None and not (
                isinstance(value, Date) and not isinstance(value, datetime)
                or isinstance(value, str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}', value)):
            raise ValueError('date must be YYYY-MM-DD')
        return value

    @field_validator('dateTime', mode='before')
    @classmethod
    def explicit_datetime(cls, value):
        if value is not None and not isinstance(value, (str, datetime)):
            raise ValueError('dateTime must be an ISO timestamp with an offset')
        return value

    @model_validator(mode='after')
    def valid_time(self):
        if (self.date is None) == (self.dateTime is None):
            raise ValueError('Provide exactly one of date or dateTime')
        if self.date is not None and self.timeZone is not None:
            raise ValueError('All-day dates do not use timeZone')
        if self.dateTime is not None:
            if self.dateTime.microsecond or self.dateTime.utcoffset().total_seconds() % 60:
                raise ValueError('Use whole seconds and a timezone offset in whole minutes')
            if self.timeZone is not None:
                try:
                    zone = ZoneInfo(self.timeZone)
                except (ZoneInfoNotFoundError, ValueError):
                    raise ValueError('timeZone must be an IANA timezone') from None
                if self.dateTime.astimezone(zone).utcoffset() != self.dateTime.utcoffset():
                    raise ValueError('dateTime offset does not match timeZone at that instant')
        return self


def validate_times(start, end):
    if (start.date is None) != (end.date is None):
        raise ValueError('start and end must both be all-day dates or both timed')
    if (start.date is not None and start.date >= end.date) or (
            start.dateTime is not None and start.dateTime >= end.dateTime):
        raise ValueError('start must precede end; all-day end dates are exclusive')


class CreateEvent(BaseModel):
    model_config = ConfigDict(extra='forbid')
    summary: Summary
    start: EventTime
    end: EventTime
    description: str = Field(default='', max_length=8192)
    location: str = Field(default='', max_length=1024)
    colorId: ColorId | None = None

    @model_validator(mode='after')
    def valid_event(self):
        validate_times(self.start, self.end)
        return self

    def tool_fields(self):
        return {'summary': self.summary, 'start': self.start.model_dump_json(exclude_none=True),
                'end': self.end.model_dump_json(exclude_none=True),
                'description': self.description, 'location': self.location,
                **({'colorId': self.colorId} if self.colorId is not None else {})}


class UpdateEvent(BaseModel):
    model_config = ConfigDict(extra='forbid')
    summary: Summary | None = None
    start: EventTime | None = None
    end: EventTime | None = None
    description: str | None = Field(default=None, max_length=8192)
    location: str | None = Field(default=None, max_length=1024)
    colorId: ColorId | None = None

    @model_validator(mode='after')
    def valid_update(self):
        if not self.model_fields_set or any(getattr(self, field) is None for field in self.model_fields_set):
            raise ValueError('Provide at least one non-null update; use an empty string to clear description or location')
        if ('start' in self.model_fields_set) != ('end' in self.model_fields_set):
            raise ValueError('Update start and end together')
        if self.start is not None:
            validate_times(self.start, self.end)
        return self

    def tool_fields(self):
        fields = self.model_dump(exclude_unset=True)
        for name in ('start', 'end'):
            if name in fields:
                fields[name] = getattr(self, name).model_dump_json(exclude_none=True)
        return fields
