from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response

from .schemas import ConversationState, EditState, EraseEdit, PlaceEdit, PropertyEdit
from .service import ConversationService

router = APIRouter(prefix="/conversations", tags=["conversations"])


def get_service(request: Request) -> ConversationService:
    return request.app.state.conversation_service


@router.post("", response_model=ConversationState, status_code=201)
def create_conversation(
    response: Response, service: ConversationService = Depends(get_service)
) -> ConversationState:
    state = service.create()
    response.headers["Location"] = f"/conversations/{state.conversationId}"
    return state


def require_edit(state: EditState | None) -> EditState:
    if state is None:
        raise HTTPException(status_code=404, detail="Conversation not found")
    return state


@router.post("/{conversation_id}/property", response_model=EditState)
def apply_property(conversation_id: UUID, edit: PropertyEdit,
                   service: ConversationService = Depends(get_service)) -> EditState:
    return require_edit(service.edit(conversation_id, {"type": "property", **edit.model_dump()}))


@router.post("/{conversation_id}/place", response_model=EditState)
def place_object(conversation_id: UUID, edit: PlaceEdit,
                 service: ConversationService = Depends(get_service)) -> EditState:
    return require_edit(service.edit(conversation_id, {"type": "place", **edit.model_dump()}))


@router.post("/{conversation_id}/erase", response_model=EditState)
def erase_square(conversation_id: UUID, edit: EraseEdit,
                 service: ConversationService = Depends(get_service)) -> EditState:
    return require_edit(service.edit(conversation_id, {"type": "erase", **edit.model_dump()}))


@router.post("/{conversation_id}/clear", response_model=EditState)
def clear_world(conversation_id: UUID,
                service: ConversationService = Depends(get_service)) -> EditState:
    return require_edit(service.edit(conversation_id, {"type": "clear"}))


@router.post("/{conversation_id}/undo", response_model=EditState)
def undo_edit(conversation_id: UUID,
              service: ConversationService = Depends(get_service)) -> EditState:
    return require_edit(service.undo(conversation_id))


@router.get("/{conversation_id}", response_model=ConversationState)
def get_conversation(
    conversation_id: UUID, service: ConversationService = Depends(get_service)
) -> ConversationState:
    state = service.get(conversation_id)
    if state is None:
        raise HTTPException(status_code=404, detail="Conversation not found")
    return state
