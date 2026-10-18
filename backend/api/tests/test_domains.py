import json
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from app.config import Settings, INITIAL_WORLD_PATHS
from app.database import Database
from app.engine import EngineInvalidRequest, LogicEngine
from app.main import create_app
from app.schemas import World, PendingEntry


class DomainIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / 'conversations.sqlite3'
        self.settings = Settings(database_path=self.path)
        self.client = TestClient(create_app(self.settings))
        self.client.__enter__()
        self.addCleanup(self.client.__exit__, None, None, None)
        self.initial = self.client.post('/conversations', json={'domain':'network'}).json()
        self.base = '/conversations/' + self.initial['conversationId']
        self.n = self.initial['nextObjectId']

    def chat(self, text, base=None):
        response = self.client.post((base or self.base) + '/chat', json={'text':text})
        self.assertEqual(response.status_code,200,response.text)
        return response.json()

    def rank(self, conversation_id=None):
        with Database(self.path).connection() as connection:
            return json.loads(connection.execute('SELECT salience_json FROM world_snapshots WHERE conversation_id=? ORDER BY sequence DESC LIMIT 1',
                              (conversation_id or self.initial['conversationId'],)).fetchone()[0])

    def clear(self):
        return self.client.post(self.base+'/clear').json()

    def at(self,state,x,y):
        return next(o for o in state['world']['objects'] if o['position']=={'x':x,'y':y})

    def test_versions_initial_world_and_isolation(self):
        self.assertEqual(self.initial['languageVersion'],'network-v2')
        self.assertEqual(self.initial['world'],json.loads(INITIAL_WORLD_PATHS['network'].read_text()))
        self.assertEqual(len(self.initial['world']['objects']),7)
        objects=self.client.post('/conversations',json={'domain':'objects'}).json()
        self.assertEqual(objects['languageVersion'],'objects-v2')
        self.clear()
        self.assertEqual(self.client.get('/conversations/'+objects['conversationId']).json(),objects)
        for base,prop in [(self.base,{'attribute':'shape','value':'bloom'}),
                          ('/conversations/'+objects['conversationId'],{'attribute':'north','value':'north'})]:
            self.assertEqual(self.client.post(base+'/property',json={'position':{'x':0,'y':0},'property':prop}).status_code,422)

    def test_delete_all_restores_world_and_salience_in_both_domains(self):
        for domain in ('objects','network'):
            state=self.client.post('/conversations',json={'domain':domain}).json()
            base='/conversations/'+state['conversationId']
            before=self.chat('Create object with color green off the board. Does #0 satisfy color is red?',base)
            ranking=self.rank(state['conversationId'])
            cleared=self.chat('Delete every object.',base)
            self.assertEqual(cleared['world']['objects'],[])
            with TestClient(create_app(self.settings)) as restarted:
                self.assertEqual(restarted.get(base).json()['world'],cleared['world'])
                self.assertEqual(restarted.post(base+'/undo').json()['world'],before['world'])
            self.assertEqual(self.rank(state['conversationId']),ranking)

    def test_connection_opens_endpoints_recolors_and_undo_restores_salience(self):
        self.clear()
        before=self.chat('Create object with color red and pattern ---- on A1. Create object with color green and pattern ---- on C1.')
        ranking=self.rank()
        connected=self.chat('Build shortest connection from A1 to C1 with route color blue.')
        self.assertIsNone(connected['pending'])
        self.assertEqual(len(connected['world']['objects']),3)
        self.assertEqual(self.at(connected,0,0)['attributes'],{'color':'blue','east':'east'})
        self.assertEqual(self.at(connected,1,0)['attributes'],{'color':'blue','east':'east','west':'west'})
        self.assertEqual(self.at(connected,2,0)['attributes'],{'color':'blue','west':'west'})
        self.assertIn('2 steps',connected['feedback'])
        self.assertEqual(connected['nextObjectId'],self.n+3)
        with TestClient(create_app(self.settings)) as restarted:
            self.assertEqual(restarted.get(self.base).json()['world'],connected['world'])
            self.assertEqual(restarted.post(self.base+'/undo').json()['world'],before['world'])
        self.assertEqual(self.rank(),ranking)
        again=self.chat('Build shortest connection from A1 to C1.')
        self.assertEqual(self.at(again,1,0)['id'],self.n+3)
        self.assertNotIn('color',self.at(again,1,0)['attributes'])

    def test_connection_clarification_restart_and_one_undo_unit(self):
        self.clear()
        before=self.chat('Create object with color red and pattern ---- on C1. Create object with color red and pattern ---- on C3.')
        paused=self.chat('Create object with color yellow on H8. Build shortest connection from A1 to the object with color red with route color blue.')
        self.assertEqual(set(paused['pending']['candidateIds']),{self.n,self.n+1})
        self.assertEqual(len(paused['world']['objects']),3)
        self.assertEqual(paused['pending']['payload']['version'],'network-v2')
        with TestClient(create_app(self.settings)) as restarted:
            self.assertEqual(restarted.get(self.base).json()['pending'],paused['pending'])
            response=restarted.post(self.base+'/clarify',json={'objectId':self.n})
            self.assertEqual(response.status_code,200,response.text)
            updated=response.json()
            self.assertIsNone(updated['pending'])
            self.assertEqual(len(updated['world']['objects']),5)
            self.assertEqual(self.at(updated,2,0)['attributes'],{'color':'blue','west':'west'})
            self.assertEqual(self.at(updated,2,2)['attributes']['color'],'red')
            self.assertEqual(restarted.post(self.base+'/undo').json()['world'],before['world'])

    def test_editor_monotonic_ids_and_chat_edit_same_node(self):
        response=self.client.post(self.base+'/property',json={'position':{'x':0,'y':1},'property':{'attribute':'north','value':'north'}})
        self.assertEqual(response.status_code,200,response.text)
        edited=response.json()
        self.assertEqual(self.at(edited,0,1)['id'],self.n)
        chatted=self.chat('Open east port of the object at A2. Set color of it to yellow. Does it satisfy north port is present? Close north port of it. Does it satisfy north port is present? Does it satisfy east port is present? What is the color of it?')
        self.assertEqual(self.at(chatted,0,1)['attributes'],{'east':'east','color':'yellow'})
        self.assertIn('false',chatted['feedback']);self.assertIn('true',chatted['feedback'])
        self.assertEqual(self.client.post(self.base+'/undo').json()['world'],edited['world'])
        with TestClient(create_app(self.settings)) as restarted:
            self.assertEqual(restarted.get(self.base).json()['world'],edited['world'])
        self.client.post(self.base+'/undo')
        fresh=self.client.post(self.base+'/ports',json={'position':{'x':0,'y':1},'ports':[]}).json()
        self.assertEqual(self.at(fresh,0,1)['id'],self.n+1)

    def test_ports_replace_preserves_color_and_undoes_in_one_step(self):
        changed=self.client.post(self.base+'/ports',json={'position':{'x':0,'y':0},'ports':['south','west']}).json()
        self.assertEqual(self.at(changed,0,0)['attributes'],{'color':'red','south':'south','west':'west'})
        self.assertEqual(self.client.post(self.base+'/undo').json()['world'],self.initial['world'])
        dot=self.client.post(self.base+'/ports',json={'position':{'x':0,'y':0},'ports':[]}).json()
        self.assertEqual(self.at(dot,0,0)['attributes'],{'color':'red'})
        for ports in [['up'],['north','north']]:
            self.assertEqual(self.client.post(self.base+'/ports',json={'position':{'x':0,'y':0},'ports':ports}).status_code,422)

    def test_scoped_graph_facts_restart_and_purge_on_remote_color_edit(self):
        self.clear()
        self.chat('Create object with color blue and pattern -e-- on A1. Create object with color blue and pattern -e-w on B1. Create object with color red and pattern ---w on C1.')
        queried=self.chat('Does the object at B1 satisfy endpoint within the subgraph of the network induced by objects matching color is blue?')
        self.assertTrue(queried['feedback'].endswith('\n  true'),queried['feedback'])
        before=self.rank()
        self.assertTrue(any(p['kind']=='defined' and p['value'].startswith('v2:') for m in before for p in m['properties']))
        with TestClient(create_app(self.settings)) as restarted:
            self.assertEqual(restarted.get(self.base).json()['world'],queried['world'])
            changed=restarted.post(self.base+'/property',json={'position':{'x':2,'y':0},'property':{'attribute':'color','value':'blue'}})
            self.assertEqual(changed.status_code,200,changed.text)
            after=self.rank()
            self.assertLess(sum(p['kind']=='defined' for m in after for p in m['properties']),sum(p['kind']=='defined' for m in before for p in m['properties']))
            self.assertEqual(restarted.post(self.base+'/undo').json()['world'],queried['world'])
        self.assertEqual(self.rank(),before)

    def test_three_blue_graph_readings_are_distinct(self):
        self.clear()
        self.chat('Create object with color blue and pattern -e-- on A1. Create object with color red and pattern -e-w on B1. Create object with color blue and pattern ---w on C1.')
        n=self.n
        entries=[(f'Does the component of #{n} satisfy tree and monochromatic with color blue?',False),
                 (f'Does the component of #{n} within the subgraph of the network induced by objects matching color is blue satisfy tree?',True),
                 (f'Does the subgraph of the component of #{n} induced by objects matching color is blue satisfy tree?',False)]
        for text,result in entries:
            state=self.chat(text)
            self.assertIsNone(state['pending'],state['feedback'])
            self.assertTrue(state['feedback'].endswith('\n  '+str(result).lower()),state['feedback'])

    def test_atomic_reference_pause_restart_and_failure_rollback(self):
        self.clear()
        before=self.chat('Create object with color red on A1. Create object with color red on B1.')
        paused=self.chat('Atomically { Set color of the object with color red to blue. Move it to B1. }.')
        self.assertEqual(paused['world'],before['world'])
        self.assertIsNotNone(paused['pending']['stagedWorld'])
        with TestClient(create_app(self.settings)) as restarted:
            result=restarted.post(self.base+'/clarify',json={'objectId':self.n}).json()
            self.assertIsNone(result['pending'])
            self.assertTrue(result['messages'][-1]['isError'])
            self.assertEqual(result['world'],before['world'])

    def test_boolean_scope_choices_survive_restart(self):
        self.clear()
        paused=self.chat('Does the network satisfy connected or tree and cyclic?')
        self.assertEqual(len(paused['pending']['groupingChoices']),2)
        with TestClient(create_app(self.settings)) as restarted:
            result=restarted.post(self.base+'/clarify',json={'groupingId':1}).json()
            self.assertIsNone(result['pending'])
            self.assertFalse(result['messages'][-1]['isError'],result['feedback'])

    def test_legacy_contract_and_shorthand_rejected(self):
        for text in ['A1 red.','a red on A1.','connect A1 to H8.','Clear the world.','Set pattern of #0 to ne.']:
            result=self.chat(text)
            self.assertTrue(result['messages'][-1]['isError'])
            self.assertEqual(result['world'],self.initial['world'])
        engine=LogicEngine(self.settings.engine_path)
        for domain in ['network','objects']:
            with self.assertRaises(EngineInvalidRequest):
                engine.edit(domain,World(width=8,height=8,objects=[]),{'type':'clarify','objectId':0},
                    pending=PendingEntry(sentence='old',remaining='old',candidateIds=[0],candidates=[],payload={'version':domain+'-v1'}))
