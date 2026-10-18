import json
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient
from app.config import Settings
from app.database import Database
from app.engine import EngineInvalidRequest, LogicEngine
from app.main import create_app
from app.schemas import World


class TypedSalienceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)/'test.sqlite3'
        self.settings = Settings(database_path=self.path)
        self.client = TestClient(create_app(self.settings))
        self.client.__enter__()
        self.addCleanup(self.client.__exit__,None,None,None)

    def create(self,domain):
        state=self.client.post('/conversations',json={'domain':domain}).json()
        return '/conversations/'+state['conversationId'],state

    def chat(self,base,text):
        response=self.client.post(base+'/chat',json={'text':text})
        self.assertEqual(response.status_code,200,response.text)
        return response.json()

    def ranking(self,base):
        with Database(self.path).connection() as connection:
            return json.loads(connection.execute('SELECT salience_json FROM world_snapshots WHERE conversation_id=? ORDER BY sequence DESC LIMIT 1',(base.split('/')[-1],)).fetchone()[0])

    def test_square_question_pronoun_and_no_implicit_occupant_in_both_domains(self):
        for domain in ['objects','network']:
            base,initial=self.create(domain)
            p=next(o for o in initial['world']['objects'] if o['id']==0)['position']
            square=chr(65+p['x'])+str(p['y']+1)
            first=self.chat(base,f'Does {square} satisfy not occupied?')
            self.assertTrue(first['feedback'].endswith('\n  false'))
            self.assertTrue(all('position' in m and 'objectId' not in m for m in self.ranking(base)))
            second=self.chat(base,'Does it satisfy occupied?')
            self.assertTrue(second['feedback'].endswith('\n  true'))
            failed=self.chat(base,'Set color of it to green.')
            self.assertTrue(failed['messages'][-1]['isError'])
            self.assertIn('No object antecedent',failed['feedback'])
            self.assertEqual(failed['world'],initial['world'])
            self.assertIsNone(failed['proposal'])

    def test_object_question_cannot_be_used_as_square_in_both_domains(self):
        for domain in ['objects','network']:
            base,initial=self.create(domain)
            result=self.chat(base,'Does #0 exist? Does it satisfy occupied?')
            self.assertTrue(result['messages'][-1]['isError'])
            self.assertIn('No square antecedent',result['feedback'])
            self.assertEqual(result['world'],initial['world'])
            self.assertFalse(any('position' in m for m in self.ranking(base)))
            result=self.chat(base,'Move #1 to it.')
            self.assertIn('No square antecedent',result['feedback'])

    def test_each_operand_type_uses_its_own_history(self):
        for domain in ['objects','network']:
            base,_=self.create(domain)
            result=self.chat(base,'Does #0 exist? Does D4 satisfy occupied? Set color of it to green. Does it satisfy occupied?')
            self.assertIsNone(result['pending'])
            self.assertFalse(result['messages'][-1]['isError'],result['feedback'])
            self.assertEqual(next(o for o in result['world']['objects'] if o['id']==0)['attributes']['color'],'green')
            self.assertTrue(any('objectId' in m for m in self.ranking(base)))
            self.assertTrue(any('position' in m for m in self.ranking(base)))

    def test_mixed_tie_restart_choice_and_whole_entry_undo(self):
        for domain in ['objects','network']:
            base,state=self.create(domain)
            self.client.post(base+'/clear')
            n=state['nextObjectId']
            before=self.chat(base,'Create object off the board.')
            rank_before=self.ranking(base)
            paused=self.chat(base,f'Move #{n} to D4. Does it satisfy at the edge?')
            self.assertEqual(paused['pending']['candidateIds'],[n])
            self.assertEqual(paused['pending']['squareChoices'],[{'x':3,'y':3}])
            count=len(paused['world']['objects'])
            invalid=self.client.post(base+'/clarify',json={'position':{'x':0,'y':0}}).json()
            self.assertEqual(invalid['pending'],paused['pending'])
            with TestClient(create_app(self.settings)) as restarted:
                loaded=restarted.get(base).json()
                self.assertEqual(loaded['pending'],paused['pending'])
                response=restarted.post(base+'/clarify',json={'position':{'x':3,'y':3}})
                self.assertEqual(response.status_code,200,response.text)
                completed=response.json()
                self.assertIsNone(completed['pending'])
                self.assertTrue(completed['feedback'].endswith('\n  false'))
                self.assertEqual(len(completed['world']['objects']),count)
                self.assertEqual(restarted.post(base+'/undo').json()['world'],before['world'])
            self.assertEqual(self.ranking(base),rank_before)

    def test_repeated_square_then_object_choices_are_one_entry(self):
        for domain in ['objects','network']:
            base,state=self.create(domain);self.client.post(base+'/clear')
            n=state['nextObjectId']
            before=self.chat(base,'Create object off the board. Create object off the board.')
            paused=self.chat(base,f'Rearrange positions by [#{n} to C3, #{n+1} to D4]. Does it satisfy occupied? Set color of it to red.')
            self.assertEqual(paused['pending']['candidateIds'],[])
            self.assertEqual(len(paused['pending']['squareChoices']),2)
            second=self.client.post(base+'/clarify',json={'position':{'x':2,'y':2}}).json()
            self.assertEqual(set(second['pending']['candidateIds']),{n,n+1})
            self.assertEqual(second['pending']['squareChoices'],[])
            completed=self.client.post(base+'/clarify',json={'objectId':n}).json()
            self.assertIsNone(completed['pending'])
            self.assertEqual(next(o for o in completed['world']['objects'] if o['id']==n)['attributes']['color'],'red')
            self.assertEqual(self.client.post(base+'/undo').json()['world'],before['world'])

    def test_occupancy_facts_purge_after_visual_erase_and_restore_on_undo(self):
        for domain in ['objects','network']:
            base,initial=self.create(domain)
            p=next(o for o in initial['world']['objects'] if o['id']==0)['position']
            square=chr(65+p['x'])+str(p['y']+1)
            before=self.chat(base,f'Does {square} satisfy occupied?')
            facts=self.ranking(base)
            self.assertTrue(any(p['value']=='square:Occupied' for m in facts for p in m['properties']))
            self.client.post(base+'/erase',json={'position':p})
            after=self.ranking(base)
            self.assertTrue(any(m.get('position')==p for m in after))
            self.assertFalse(any(p['value']=='square:Occupied' for m in after for p in m['properties']))
            with TestClient(create_app(self.settings)) as restarted:
                restored=restarted.post(base+'/undo').json()
                self.assertEqual(restored['world'],before['world'])
            self.assertEqual(self.ranking(base),facts)
            self.assertTrue(self.chat(base,'Does it satisfy occupied?')['feedback'].endswith('\n  true'))

    def test_atomic_rollback_and_preview_do_not_commit_typed_mentions(self):
        for domain in ['objects','network']:
            base,state=self.create(domain);self.client.post(base+'/clear')
            n=state['nextObjectId']
            before=self.chat(base,'Create object off the board.')
            ranking=self.ranking(base)
            failed=self.chat(base,f'Atomically {{ Move #{n} to C3. Create object on it. }}.')
            self.assertTrue(failed['messages'][-1]['isError'])
            self.assertEqual(failed['world'],before['world'])
            self.assertEqual(self.ranking(base),ranking)
            # The exact production preview evaluator is pure, including both mention types.
            service=self.client.app.state.conversation_service
            preview=service._evaluate_interpretation(domain,World.model_validate(before['world']),ranking,
                                                      f'Move #{n} to C3. Does it satisfy occupied?',before['nextObjectId'])
            self.assertFalse(preview.isError)
            self.assertTrue(any('position' in m for m in preview.salience))
            self.assertEqual(self.ranking(base),ranking)

    def test_explicit_occupant_reference_and_square_destination(self):
        for domain in ['objects','network']:
            base,initial=self.create(domain)
            p=next(o for o in initial['world']['objects'] if o['id']==0)['position']
            square=chr(65+p['x'])+str(p['y']+1)
            result=self.chat(base,f'Does {square} satisfy occupied? Set color of the object at it to green.')
            self.assertFalse(result['messages'][-1]['isError'],result['feedback'])
            self.assertEqual(next(o for o in result['world']['objects'] if o['id']==0)['attributes']['color'],'green')
            self.chat(base,'Does D4 satisfy occupied?')
            result=self.chat(base,'Create object with color yellow on it.')
            self.assertFalse(result['messages'][-1]['isError'],result['feedback'])
            self.assertTrue(any(o['position']=={'x':3,'y':3} and o['attributes'].get('color')=='yellow' for o in result['world']['objects']))

    def test_malformed_typed_mentions_are_rejected(self):
        engine=LogicEngine(self.settings.engine_path)
        world=World(width=8,height=8,objects=[])
        invalid=[{'objectId':0,'position':{'x':0,'y':0}}, {'position':{'x':8,'y':0}},
                 {'position':{'x':0,'y':0},'properties':[{'kind':'attribute','attribute':'color','value':'red'}]},
                 {'position':{'x':0,'y':0},'properties':[{'kind':'defined','value':'square:ValueIs "color" "red"'}]}]
        for domain in ['objects','network']:
            for extra in invalid:
                with self.assertRaises(EngineInvalidRequest):
                    engine.edit(domain,world,{'type':'chat','text':'Does it satisfy occupied?'},
                                salience=[{'entry':0,'utterance':0,'properties':[],**extra}])
