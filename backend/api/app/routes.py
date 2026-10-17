from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response

from .schemas import PortsEdit, CreateConversation, ClarificationChoice, ChatEntry, ConversationState, EditState, EraseEdit, PlaceEdit, PropertyEdit
from .service import ConversationService
from .schemas import InterpretationChoice, InterpretationAnswer

router = APIRouter(prefix="/conversations", tags=["conversations"])


def get_service(request: Request) -> ConversationService:
    return request.app.state.conversation_service


@router.post("", response_model=ConversationState, status_code=201)
def create_conversation(
    entry: CreateConversation, response: Response, service: ConversationService = Depends(get_service)
) -> ConversationState:
    state = service.create(entry.domain)
    response.headers["Location"] = f"/conversations/{state.conversationId}"
    return state


def require_edit(state: EditState | None) -> EditState:
    if state is None:
        raise HTTPException(status_code=404, detail="Conversation not found")
    return state


@router.post("/{conversation_id}/chat", response_model=EditState)
def chat(conversation_id: UUID, entry: ChatEntry,
         service: ConversationService = Depends(get_service)) -> EditState:
    if not entry.text.strip():
        raise HTTPException(status_code=422, detail="Message must not be blank")
    return require_edit(service.chat(conversation_id, entry.text, entry.useLlm))


@router.post("/{conversation_id}/property", response_model=EditState)
def apply_property(conversation_id: UUID, edit: PropertyEdit,
                   service: ConversationService = Depends(get_service)) -> EditState:
    return require_edit(service.edit(conversation_id, {"type": "property", **edit.model_dump()}))


@router.post('/{conversation_id}/interpretations/{proposal_id}/preview', response_model=EditState)
def preview(conversation_id: UUID, proposal_id: UUID, choice: InterpretationChoice,
            service: ConversationService = Depends(get_service)) -> EditState:
    return require_edit(service.preview(conversation_id, proposal_id, choice.rank))


@router.post('/{conversation_id}/interpretations/{proposal_id}/accept', response_model=EditState)
def accept(conversation_id: UUID, proposal_id: UUID, choice: InterpretationChoice,
           service: ConversationService = Depends(get_service)) -> EditState:
    return require_edit(service.accept(conversation_id, proposal_id, choice.rank))


@router.post('/{conversation_id}/interpretations/{proposal_id}/reject', response_model=EditState)
def reject(conversation_id: UUID, proposal_id: UUID,
           service: ConversationService = Depends(get_service)) -> EditState:
    return require_edit(service.reject(conversation_id, proposal_id))


@router.post('/{conversation_id}/interpretations/{proposal_id}/answer', response_model=EditState)
def answer(conversation_id: UUID, proposal_id: UUID, entry: InterpretationAnswer,
           service: ConversationService = Depends(get_service)) -> EditState:
    if not entry.text.strip():
        raise HTTPException(status_code=422, detail='Answer must not be blank')
    return require_edit(service.answer(conversation_id, proposal_id, entry.text))


@router.post("/{conversation_id}/ports", response_model=EditState)
def set_ports(conversation_id: UUID, edit: PortsEdit,
              service: ConversationService = Depends(get_service)) -> EditState:
    return require_edit(service.edit(conversation_id, {"type": "ports", **edit.model_dump()}))


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


@router.post("/{conversation_id}/clarify", response_model=EditState)
def clarify(conversation_id: UUID, choice: ClarificationChoice,
            service: ConversationService = Depends(get_service)) -> EditState:
    return require_edit(service.clarify(conversation_id, choice))
