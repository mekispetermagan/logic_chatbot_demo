"""Assemble exactly the reviewed common and active-domain instructions."""
import json
from pathlib import Path

from .llm import PROMPTS, RESPONSE_SCHEMA
from .llm_budget import MODEL

INSTRUCTIONS_PATH = Path(__file__).resolve().parents[3] / 'specification' / 'agent-instructions-draft.md'


def configuration_for(domain: str) -> dict:
    source = INSTRUCTIONS_PATH.read_text(encoding='utf-8')
    common = source.split('## Common instructions\n', 1)[1].split('## Objects agent:', 1)[0]
    common = common.split('## Shared language reference\n', 1)[0]
    if domain == 'objects':
        domain_text = source.split('## Objects agent: domain instructions\n', 1)[1].split('## Network agent:', 1)[0]
        reference = (INSTRUCTIONS_PATH.parent / 'object-language-v2.md').read_text(encoding='utf-8')
        domain_text += '\n## Authoritative Objects v2 language reference\n' + reference.split('## 2. World, types and vocabulary\n', 1)[1].split('## 12. Review checklist', 1)[0]
    elif domain == 'network':
        domain_text = source.split('## Network agent: domain instructions\n', 1)[1].split('## Cellular agent:', 1)[0]
        reference = (INSTRUCTIONS_PATH.parent / 'network-language-v2.md').read_text(encoding='utf-8')
        domain_text += '\n## Authoritative Network v2 language reference\n' + reference
    elif domain == 'cellular':
        before, remainder = common.split('### Object and square references\n', 1)
        common = before + '### Interpret and plan resourcefully\n' + remainder.split('### Interpret and plan resourcefully\n', 1)[1]
        domain_text = source.split('## Cellular agent: domain instructions\n', 1)[1]
        reference = (INSTRUCTIONS_PATH.parent / 'cellular-language-v2.md').read_text(encoding='utf-8')
        domain_text += '\n## Authoritative Cellular v2 language reference\n' + reference
    else:
        raise ValueError('Unknown domain')
    examples = json.loads((PROMPTS / 'examples.json').read_text(encoding='utf-8'))[domain]
    header = f'# Gridworld Interpreter\n\nACTIVE DOMAIN: {domain}\n\n'
    instructions = (header + '## Common instructions\n' + common +
                    f'\n## Active domain: {domain}\n' + domain_text +
                    '\n## Additional validated examples (input => translation)\n' + '\n'.join(
                        f'{example["input"]} => {example["translation"]}' for example in examples))
    return {
        'name': f'Logic Chatbot — {domain.title()}', 'model': MODEL,
        'instructions': instructions, 'reasoning': {'effort': 'low'},
        'service_tier': 'default', 'tools': [], 'multi_agent': {'enabled': False},
        'text': {'format': {'type': 'json_schema', 'schema': RESPONSE_SCHEMA}},
    }
