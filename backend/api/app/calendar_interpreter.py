"""Calendar binding for the shared interpreter transport and review contract."""
import asyncio
import copy
from dataclasses import dataclass
import json
from uuid import uuid4

from .calendar_mcp import CalendarError
from .engine import EngineInvalidRequest
from .repository import PendingConflict
from .schemas import InterpretationProposal, InterpretationFailure, InterpretationTurn


@dataclass
class CalendarInterpreterWorld:
    data: dict

    def model_dump(self):
        return self.data


def _invalid_json_constant(value):
    raise ValueError('Invalid JSON value: ' + value)


BASE_FIELDS = ('status', 'work', 'question', 'plan', 'parameters', 'feedback',
               'usage', 'fingerprint', 'handles', 'nextHandle', 'salience', 'activeSeconds')
PRIVATE_FIELDS = ('interpretationBase', 'interpretationPreviewWork', 'interpretationCandidatesWork')


class CalendarInterpreter:
    def __init__(self, dialogue, translator):
        self.dialogue, self.translator = dialogue, translator

    def record(self, state, kind, **values):
        self.dialogue.record_interpreter(state, kind, **values)

    async def snapshot(self, state, ctx, events):
        result = await asyncio.to_thread(self.dialogue.engine, copy.deepcopy(state), {'type': 'snapshot'}, ctx, events)
        state['handles'].update(result['handles'])
        state['nextHandle'] = max(state['nextHandle'], result['nextHandle'])
        return result['world']

    def base(self, state, ctx, events, target, key=None):
        return {**{k: copy.deepcopy(state.get(k)) for k in BASE_FIELDS},
                'context': ctx, 'events': events, 'target': target, 'key': key}

    async def propose(self, state, text, ctx, events, *, target='entry', key=None, previous=None, source_error=None):
        world = await self.snapshot(state, ctx, events)
        base = state.get('interpretationBase') if previous else self.base(state, ctx, events, target, key)
        clarification = {'mode': 'engineAnswer' if base['target'] == 'answer' else 'entry',
                         'engineQuestion': base.get('question') if base['target'] == 'answer' else None}
        if source_error:
            clarification['parserFeedback'] = source_error
        turns = []
        original = text
        if previous:
            original = previous['originalText']
            turns = [*previous.get('clarifications', []), {'question': previous['question'], 'answer': text}]
            clarification.update(turns=turns, previousCandidates=previous['candidates'],
                                 validationFailures=previous['validationFailures'])
        state['interpretationBase'] = base
        state['status'] = 'interpreting'
        self.dialogue.save(state)  # Durable pending intent precedes a provider turn.
        if self.translator is None:
            state['status'] = base['status']
            state['messages'].append({'role': 'machine', 'text': 'LLM is not configured on the server.'})
            state.pop('interpretationBase', None)
            state['revision'] += 1
            self.dialogue.save(state)
            return self.dialogue.public(state)
        try:
            attempt = await asyncio.to_thread(self.translator.translate, state['interpreterId'], 'calendar',
                                              original, CalendarInterpreterWorld(world), clarification)
        except PendingConflict:
            state['status'] = 'interpretation' if previous else base['status']
            if not previous:
                state.pop('interpretationBase', None)
            state['messages'].append({'role': 'machine', 'text': 'The interpreter is busy; wait before resending. Nothing was applied.'})
            state['revision'] += 1
            self.dialogue.save(state)
            return self.dialogue.public(state)
        if attempt.usage.status == 'conversation':
            state['status'] = 'interpretation' if previous else ('answered' if base['target'] == 'entry' else base['status'])
            if not previous:
                state.pop('interpretationBase', None)
            state['messages'].append({'role': 'machine', 'text': attempt.reply, 'llm': attempt.usage.model_dump()})
            state['revision'] += 1
            self.dialogue.save(state)
            return self.dialogue.public(state)
        valid, failures, seen, prepared = [], [], set(), {}
        for candidate in attempt.candidates:
            try:
                if base['target'] == 'answer':
                    reply = await asyncio.to_thread(self.evaluate, base, candidate.translation)
                    if reply.get('question') and reply['question']['key'] == base['key']:
                        raise EngineInvalidRequest(reply['question']['prompt'])
                    canonical = candidate.translation
                else:
                    checked = await asyncio.to_thread(self.dialogue.engine, copy.deepcopy(base),
                        {'type': 'checkSyntax', 'text': candidate.translation}, ctx, events)
                    canonical = '\n'.join(checked['alternatives'])
                if canonical not in seen:
                    seen.add(canonical)
                    valid.append(candidate.model_copy(update={'rank': len(valid)+1}))
                    if base['target'] == 'answer':
                        prepared[str(len(valid))] = reply
            except (EngineInvalidRequest, ValueError, TypeError) as error:
                failures.append(InterpretationFailure(interpretation=candidate.interpretation,
                    translation=candidate.translation, reason=self.translator.safe_text(str(error), 1000)))
        if valid or failures or attempt.question:
            attempt.usage.status = 'proposed' if valid else 'invalid' if failures else 'clarification'
            proposal = InterpretationProposal(id=uuid4(), originalText=original, candidates=valid,
                question=attempt.question, explanation=attempt.explanation, validationFailures=failures,
                clarifications=[InterpretationTurn(**turn) for turn in turns],
                llm=attempt.usage, languageVersion=state['languageVersion'])
            state['interpretation'] = {**proposal.model_dump(mode='json'),
                                       'translationFormat': 'json' if base['target'] == 'answer' else 'controlledEnglish'}
            state['status'] = 'interpretation'
            state['interpretationCandidatesWork'] = prepared
            state.pop('interpretationPreview', None)
            state.pop('interpretationPreviewWork', None)
            feedback = 'Interpretations ready for review; no Calendar changes were submitted.' if valid else 'Translation needs clarification or repair; nothing was applied.'
        else:
            state['status'] = 'interpretation' if previous else base['status']
            if not previous:
                state.pop('interpretationBase', None)
            if source_error and not previous:
                state['messages'].append({'role': 'machine', 'text': source_error, 'isError': True})
            feedback = attempt.note or attempt.explanation or 'No supported interpretation was returned.'
        state['messages'].append({'role': 'machine', 'text': '\n'.join(filter(None, [attempt.reply, feedback, attempt.note])),
                                  'llm': attempt.usage.model_dump()})
        state['revision'] += 1
        self.record(state, 'interpretation_proposed', target=base['target'], userText=text,
                    candidates=[c.model_dump() for c in valid], question=attempt.question)
        self.dialogue.save(state)
        return self.dialogue.public(state)

    def evaluate(self, base, translation):
        if base['target'] == 'answer':
            value = json.loads(translation, parse_constant=_invalid_json_constant)
            action = {'type': 'answer', 'key': base['key'], 'value': value}
        else:
            action = {'type': 'start', 'text': translation}
        evaluation = copy.deepcopy(base)
        reply = self.dialogue.engine(evaluation, action, base['context'], base['events'])
        reply['_activeSeconds'] = evaluation.get('activeSeconds', 0)
        return reply

    async def fresh(self, state):
        from .calendar_dialogue import fingerprint
        base = state['interpretationBase']
        events = await self.dialogue.fetch(base['context'])
        if fingerprint(events) != base['fingerprint']:
            raise CalendarError('Calendar changed since interpretation. Reject/cancel and start a fresh request.', 409)
        return base

    async def act(self, state, body):
        proposal = state.get('interpretation')
        if not proposal or body.get('proposalId') != proposal['id']:
            raise CalendarError('This interpretation is no longer pending. Refresh dialogue status.', 409)
        typ = body['type']
        base = state['interpretationBase']
        if typ == 'rejectInterpretation':
            self.restore(state, base)
            self.clear(state)
            state['messages'].append({'role': 'machine', 'text': 'Interpretation rejected; no proposed Calendar changes were submitted.'})
            self.record(state, 'interpretation_rejected', proposalId=proposal['id'])
            state['revision'] += 1
            self.dialogue.save(state)
            return self.dialogue.public(state)
        await self.fresh(state)
        if typ == 'answerInterpretation':
            if not (proposal['question'] or proposal['validationFailures'] or not proposal['candidates']):
                raise CalendarError('Choose, preview or reject the interpretation first.', 409)
            state['messages'].append({'role': 'user', 'text': body['text']})
            return await self.propose(state, body['text'], base['context'], base['events'], previous=proposal)
        if proposal['languageVersion'] != state['languageVersion']:
            raise CalendarError('Reject this obsolete interpretation and start again.', 409)
        rank = body.get('rank')
        candidates = [c for c in proposal['candidates'] if c['rank'] == rank]
        if len(candidates) != 1:
            raise CalendarError('Choose a listed interpretation.', 422)
        candidate = candidates[0]
        preview = state.get('interpretationPreview')
        reply = (state.get('interpretationPreviewWork') if preview and preview['rank'] == rank else None)
        if reply is None:
            reply = state.get('interpretationCandidatesWork', {}).get(str(rank))
        if reply is None:
                reply = await asyncio.to_thread(self.evaluate, base, candidate['translation'])
        state['nextHandle'] = max(state['nextHandle'], reply.get('nextHandle', 0))
        if typ == 'previewInterpretation':
            from .calendar_dialogue import provider_fields
            message = '\n'.join([reply.get('message', ''), *reply.get('feedback', [])])
            if reply.get('question'):
                message += '\nAfter acceptance: ' + reply['question']['prompt']
            state['interpretationPreview'] = {'proposalId': proposal['id'], 'rank': rank, 'world': None,
                'feedback': message, 'hasClarification': reply['status'] == 'clarify',
                'changes': [{'objectId': op['handle'], 'kind': op['type'],
                    'detail': f"#{op['handle']} {op['type']}: " + json.dumps(provider_fields(op['fields']), ensure_ascii=False)} for op in reply.get('plan', [])]}
            state['interpretationPreviewWork'] = reply
            self.record(state, 'interpretation_preview', proposalId=proposal['id'], rank=rank, feedback=message)
            state['revision'] += 1
            self.dialogue.save(state)
            return self.dialogue.public(state)
        if typ != 'acceptInterpretation':
            raise CalendarError('Unsupported interpretation action.', 422)
        self.restore(state, base)
        self.clear(state)
        self.record(state, 'interpretation_accepted', proposalId=proposal['id'], translation=candidate['translation'])
        # This only commits provisional evaluation / question discourse. Cloud
        # application still goes through the existing separate Accept changes.
        return self.dialogue.complete_evaluation(state, reply, base['context'],
            0 if base['target'] == 'entry' else len(base.get('feedback') or []))

    @staticmethod
    def restore(state, base):
        reserved = state['nextHandle']
        for key in BASE_FIELDS:
            if key in base:
                state[key] = copy.deepcopy(base[key])
        state['nextHandle'] = max(reserved, state['nextHandle'])

    @staticmethod
    def clear(state):
        for key in ('interpretation', 'interpretationPreview', *PRIVATE_FIELDS):
            state.pop(key, None)
