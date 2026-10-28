"""Read-only language help; example text comes exclusively from Haskell."""
from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel, ConfigDict, Field

LanguageDomain = Literal['objects', 'network', 'cellular', 'calendar']


class ExampleSegment(BaseModel):
    model_config = ConfigDict(extra='forbid')
    text: str = Field(min_length=1)
    reference: bool = False


class ExampleSection(BaseModel):
    model_config = ConfigDict(extra='forbid')
    title: Literal['Primitive commands', 'Primitive questions', 'Conceptual commands', 'Conceptual questions']
    examples: list[list[ExampleSegment]] = Field(min_length=1)


class LanguageExamples(BaseModel):
    model_config = ConfigDict(extra='forbid')
    domain: LanguageDomain
    languageVersion: str
    sections: list[ExampleSection] = Field(min_length=4, max_length=4)


router = APIRouter(prefix='/languages', tags=['languages'])


@router.get('/{domain}/examples', response_model=LanguageExamples)
def examples(domain: LanguageDomain, request: Request):
    return request.app.state.conversation_service.engine.examples(domain)
