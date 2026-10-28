"""LLM-only routing is tested with no Haskell executable and mocked providers."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import httpx
from fastapi.testclient import TestClient
from app.calendar_mcp import CalendarError
from app.config import Settings
from app.main import create_app

START='2026-10-26T00:00:00+01:00'
END='2026-11-02T00:00:00+01:00'
SCHEMAS=json.loads((Path(__file__).parent/'fixtures/calendar_mcp_tools.json').read_text())

class Calendar:
    def __init__(self,settings):
        self.settings=settings;self.calls=[];self.writable=True;self.lose_write=False
        self.data={'a':{'id':'a','summary':'Meeting','colorId':'5',
            'start':{'dateTime':'2026-10-30T09:00:00+01:00'},'end':{'dateTime':'2026-10-30T10:00:00+01:00'}}}
    def require_writes(self):
        if not self.writable:raise CalendarError('Writes disabled.',403)
    async def describe_tools(self):
        return {n:{'description':n,'parameters':s} for n,s in SCHEMAS.items()}
    async def events(self,*args):return {'events':copy.deepcopy(list(self.data.values()))}
    async def event(self,identifier):
        if identifier not in self.data:raise CalendarError('Absent.',404)
        return {'event':copy.deepcopy(self.data[identifier])}
    async def editable_event(self,identifier):
        self.require_writes()
        if (await self.event(identifier))['event'].get('recurringEventId'):raise CalendarError('Read-only.',409)
    async def _call(self,name,args):
        self.calls.append((name,copy.deepcopy(args)))
        if name=='list-events':return {'events':copy.deepcopy(list(self.data.values())),'opaqueProviderField':{'unchanged':True}}
        if name=='get-event':return await self.event(args['eventId'])
        self.require_writes();identifier=args['eventId']
        if name=='delete-event':
            self.data.pop(identifier,None);result={'success':True,'eventId':identifier,'calendarId':self.settings.calendar_id}
        else:
            event=self.data.setdefault(identifier,{'id':identifier})
            for f in ('summary','description','location','colorId','start','end'):
                if f in args:
                    v=args[f]
                    if f in ('start','end'):v=json.loads(v) if v.startswith('{') else {'dateTime':v}
                    event[f]=v
            result={'event':copy.deepcopy(event),'providerReceipt':'unchanged'}
        if self.lose_write:
            self.lose_write=False;raise CalendarError('Lost acknowledgement.',504,identifier,True)
        return result

class Provider:
    def __init__(self):
        self.configs=[];self.sessions={};self.queue=[];self.results=[];self.lose_result=False
        self.usage={'input_tokens':1000,'output_tokens':100,'input_tokens_details':{'cached_tokens':100},'output_tokens_details':{'reasoning_tokens':20}}
    def next_turn(self,sid,body):
        steps,reply=self.queue.pop(0) if self.queue else ([],{'kind':'answer','text':'Answer from GPT.'})
        count=self.sessions.get(sid,{}).get('count',0)+1
        self.sessions[sid]={'count':count,'turn':f'turn_{sid}_{count}','steps':steps,'index':0,'reply':reply,'input':body}
    def actions(self,sid):
        s=self.sessions[sid]
        if s['index']>=len(s['steps']):return []
        step=s['steps'][s['index']]
        if callable(step):step=step(self)
        return [{'type':'function_call','turn_id':s['turn'],'call_id':f'call_{s["index"]}','name':step[0],'arguments':step[1]}]
    def handle(self,request):
        b=json.loads(request.content) if request.content else {}
        p=request.url.path.removeprefix('/v1/agents').strip('/').split('/')
        if request.method=='POST' and (p==[''] or p[0].startswith('agent_')):
            self.configs.append(b);return httpx.Response(200,json={'id':'agent_baseline','model':'gpt-6-luna'})
        if p==['sessions'] and request.method=='POST':
            sid=f'session_{len(self.sessions)}';self.next_turn(sid,b);return httpx.Response(201,json={'id':sid})
        sid=p[1];s=self.sessions[sid]
        if len(p)==2:return httpx.Response(200,json={'id':sid,'agent':{'model':'gpt-6-luna'},'status':'requires_action' if self.actions(sid) else 'idle','required_actions':self.actions(sid)})
        if p[2]=='events':
            e=b['events'][0]
            if e['type']=='agent.session.input.message':self.next_turn(sid,b)
            elif e['type']=='agent.session.input.cancel':s['index']=len(s['steps'])
            else:
                self.results.append(e);s['index']+=1
                if self.lose_result:self.lose_result=False;raise httpx.ReadTimeout('Lost result acknowledgement')
            return httpx.Response(200,json={})
        if p[2]=='turns' and len(p)==3:return httpx.Response(200,json={'data':[{'id':s['turn'],'session_id':sid,'status':'waiting' if self.actions(sid) else 'completed','usage':self.usage}],'has_more':False})
        if p[-1]=='items':return httpx.Response(200,json={'data':[{'turn_id':s['turn'],'type':'message','role':'assistant','phase':'final_answer','status':'completed','content':[{'type':'output_text','text':json.dumps(s['reply'])}]}]})
        raise AssertionError(str(request.url))

class CalendarLlmOnlyTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.settings=Settings(database_path=Path(self.tmp.name)/'state.sqlite3',engine_path=Path('/no-haskell'),openai_api_key='mock-key',calendar_enabled=True,calendar_writes_enabled=True)
        self.provider=Provider()
        for module in ('app.agent_llm','app.calendar_llm_dialogue','app.agent_usage'):
            p=patch(module+'.create_client',side_effect=lambda:httpx.Client(transport=httpx.MockTransport(self.provider.handle)))
            p.start();self.addCleanup(p.stop)
        self.app=create_app(self.settings)
        self.client=TestClient(self.app,client=('127.0.0.1',1234));self.client.__enter__();self.addCleanup(self.client.__exit__,None,None,None)
        self.calendar=Calendar(self.settings);self.app.state.calendar=self.calendar;self.base='/calendar/llm-only/dialogue'
    def state(self):return self.client.get(self.base).json()
    def post(self,typ,expected=200,**fields):
        r=self.client.post(self.base,json={'type':typ,'revision':self.state()['revision'],**fields})
        self.assertEqual(r.status_code,expected,r.text);return r.json()
    def message(self,text='Handle my request.'):return self.post('message',text=text,timeMin=START,timeMax=END)
    def args(self,**fields):return {'account':self.settings.calendar_account,'calendarId':self.settings.calendar_id,**fields}
    def change(self,**fields):return ('calendar_propose_changes',{'operations':[{'tool':'update-event','arguments':self.args(eventId='a',sendUpdates='none',**fields)}]})
    def approve(self):return self.post('accept',proposalId=self.state()['review']['id'])
    def test_reads_and_results_forward_unchanged_without_haskell(self):
        args=self.args(timeMin=START,timeMax=END,timeZone='Europe/Budapest')
        self.calendar.data['all-day']={'id':'all-day','start':{'date':'2026-10-30'},'end':{'date':'2026-10-31'}}
        self.provider.queue=[([('calendar_list_events',args)],{'kind':'answer','text':'GPT answer.'})]
        s=self.message();self.assertEqual(s['status'],'answered');self.assertEqual(self.calendar.calls,[('list-events',args)])
        self.assertEqual(json.loads(self.provider.results[0]['output']),{'events':list(self.calendar.data.values()),'opaqueProviderField':{'unchanged':True}})
        self.assertEqual(s['llmBudget']['inputTokens'],1000)
        config=self.provider.configs[0]
        for text in ('Schedule event lasting','entry age','branch-and-bound','Try a no-movement','proposed-calendar-language'):self.assertNotIn(text,config['instructions'])
        from app.agent_instructions import configuration_for
        rules=(Path(__file__).resolve().parents[3]/'docs/calendar-domain.md').read_text()
        self.assertIn(rules,config['instructions']);self.assertIn(rules,configuration_for('calendar')['instructions'])
        self.assertIn('(importance + 1)^2',config['instructions']);self.assertEqual(config['reasoning'],{'effort':'low'});self.assertEqual(len(config['tools']),4)
    def test_wrong_semantic_plan_is_not_corrected_and_needs_exact_approval(self):
        self.provider.queue=[([self.change(colorId='11')],{'kind':'answer','text':'Agent reply.'})]
        s=self.message('Make the meeting normal.');self.assertEqual(s['status'],'review');self.assertEqual(self.calendar.calls,[])
        self.assertEqual(s['review']['operations'][0]['arguments']['colorId'],'11')
        s=self.approve();self.assertEqual(s['status'],'answered')
        self.assertEqual(self.calendar.calls[0],('update-event',self.args(eventId='a',sendUpdates='none',colorId='11')))
        self.assertEqual(json.loads(self.provider.results[0]['output'])['operations'][0]['result']['providerReceipt'],'unchanged')
        self.post('accept',expected=409,proposalId='old')
    def test_creation_id_and_raw_timestamps(self):
        def create(p):
            identifier=json.loads(p.results[-1]['output'])['eventId']
            return ('calendar_propose_changes',{'operations':[{'tool':'create-event','arguments':self.args(eventId=identifier,summary='Mechanic',start='2026-10-30T11:00:00+01:00',end='2026-10-30T11:15:00+01:00',sendUpdates='none')}]})
        self.provider.queue=[([('calendar_reserve_event_id',{}),create],{'kind':'answer','text':'Done.'})]
        s=self.message();identifier=s['review']['operations'][0]['arguments']['eventId'];s=self.approve()
        self.assertIn(identifier,self.calendar.data);self.assertEqual(self.calendar.calls[0][1]['start'],'2026-10-30T11:00:00+01:00');self.assertEqual(s['journal'][0]['status'],'verified')
    def test_rejection_returns_error_without_writes(self):
        self.provider.queue=[([self.change(summary='Changed')],{'kind':'answer','text':'Understood.'})]
        self.message();s=self.post('reject',proposalId=self.state()['review']['id'])
        self.assertEqual(s['status'],'answered');self.assertFalse(self.provider.results[-1]['success']);self.assertEqual(self.calendar.calls,[])
    def test_stale_proposals_and_shared_gate(self):
        self.provider.queue=[([self.change(summary='Changed')],{'kind':'answer','text':'Done.'})];s=self.message()
        self.assertEqual(self.client.patch('/calendar/events/a',json={'title':'New'}).status_code,409)
        symbolic=self.app.state.calendar_dialogue.read()
        r=self.client.post('/calendar/dialogue',json={'type':'start','revision':symbolic['revision'],'text':'Delete #0.','timeMin':START,'timeMax':END})
        self.assertEqual(r.status_code,409)
        self.calendar.data['a']['location']='External';self.post('accept',expected=409,proposalId=s['review']['id']);self.assertEqual(self.calendar.calls,[])
    def test_clarification_preserves_context_and_session(self):
        self.provider.queue=[([],{'kind':'clarification','text':'How long?'}),([],{'kind':'answer','text':'Thirty minutes.'})]
        first=self.message();s=self.post('message',text='30 minutes')
        self.assertEqual(s['scope'],first['scope']);self.assertEqual(len(self.provider.sessions),1);self.assertEqual(s['llmBudget']['requestCount'],2);self.assertEqual(self.app.state.calendar_dialogue.read()['messages'],[])
    def test_bad_arguments_and_unknown_tool_return_errors(self):
        args=self.args(eventId='a');args['calendarId']='other'
        self.provider.queue=[([('calendar_get_event',args),('invented_solver',{})],{'kind':'answer','text':'Cannot proceed.'})]
        self.assertEqual(self.message()['status'],'answered');self.assertTrue(all(not x['success'] for x in self.provider.results));self.assertEqual(self.calendar.calls,[])
    def test_cloud_ack_loss_reconciles_without_replay(self):
        self.provider.queue=[([self.change(summary='Changed')],{'kind':'answer','text':'Recovered.'})]
        self.message();self.calendar.lose_write=True;self.assertEqual(self.approve()['status'],'recovery');self.assertEqual(len(self.calendar.calls),1)
        self.assertFalse(self.state()['canContinue'])
        self.post('continue',expected=409)
        self.assertEqual(self.post('reconcile')['journal'][0]['status'],'verified')
        self.assertTrue(self.state()['canContinue'])
        self.assertEqual(self.post('continue')['status'],'answered');self.assertEqual(len(self.calendar.calls),1)
    def test_tool_ack_loss_resumes_without_replay(self):
        self.provider.queue=[([self.change(summary='Changed')],{'kind':'answer','text':'Done.'})]
        self.message();self.provider.lose_result=True;self.assertEqual(self.approve()['status'],'suspended')
        self.assertEqual(self.post('resume')['status'],'answered');self.assertEqual(len(self.calendar.calls),1)
    def test_restart_preserves_pending_review(self):
        self.provider.queue=[([self.change(summary='Changed')],{'kind':'answer','text':'Done.'})];original=self.message()
        with TestClient(create_app(self.settings),client=('127.0.0.1',1)) as c:
            c.app.state.calendar=self.calendar;s=c.get(self.base).json();self.assertEqual(s['review'],original['review'])
            r=c.post(self.base,json={'type':'accept','revision':s['revision'],'proposalId':s['review']['id']})
            self.assertEqual(r.status_code,200,r.text);self.assertEqual(r.json()['status'],'answered')
        self.assertEqual(len(self.calendar.calls),1)
    def test_disabled_writes_and_loopback(self):
        self.calendar.writable=False;self.provider.queue=[([self.change(summary='Changed')],{'kind':'answer','text':'Disabled.'})]
        self.assertEqual(self.message()['status'],'answered');self.assertEqual(self.calendar.calls,[])
        with TestClient(create_app(self.settings),client=('203.0.113.1',1)) as c:self.assertEqual(c.get(self.base).status_code,403)
    def test_pending_usage(self):
        self.provider.usage=None;s=self.message();self.assertEqual(s['llmBudget']['pendingUsageCount'],1);self.assertIsNone(s['messages'][-1]['llm'].get('inputTokens'))

    def test_delete_is_a_raw_approved_primitive(self):
        args=self.args(eventId='a',sendUpdates='none')
        self.provider.queue=[([('calendar_propose_changes',{'operations':[{'tool':'delete-event','arguments':args}]})],{'kind':'answer','text':'Deleted.'})]
        self.message();s=self.approve()
        self.assertEqual(s['status'],'answered');self.assertNotIn('a',self.calendar.data)
        self.assertEqual(self.calendar.calls,[('delete-event',args)])

    def test_partial_failure_stops_remainder_until_explicit_continuation(self):
        ops=[{'tool':'update-event','arguments':self.args(eventId='a',summary='Changed',sendUpdates='none')},
             {'tool':'update-event','arguments':self.args(eventId='a',location='Office',sendUpdates='none')}]
        self.provider.queue=[([('calendar_propose_changes',{'operations':ops})],{'kind':'answer','text':'Done.'})]
        self.message();self.calendar.lose_write=True;s=self.approve()
        self.assertEqual(s['status'],'recovery');self.assertEqual(len(self.calendar.calls),1)
        self.post('reconcile');self.assertEqual(len(self.calendar.calls),1)
        s=self.post('continue');self.assertEqual(s['status'],'answered');self.assertEqual(len(self.calendar.calls),2)
        self.assertEqual(self.calendar.data['a']['location'],'Office')

    def test_second_proposal_always_requires_another_approval(self):
        self.provider.queue=[([self.change(summary='First'),self.change(location='Second')],{'kind':'answer','text':'Done.'})]
        self.message();s=self.approve()
        self.assertEqual(s['status'],'review');self.assertEqual(len(self.calendar.calls),1)
        s=self.approve();self.assertEqual(s['status'],'answered');self.assertEqual(len(self.calendar.calls),2)

    def test_unavailable_write_tools_do_not_prevent_read_only_chat(self):
        from dataclasses import replace
        self.app.state.calendar_llm_only.settings=replace(self.settings,calendar_writes_enabled=False)
        async def metadata():
            return {n:{'description':n,'parameters':SCHEMAS[n]} for n in ('list-events','get-event')}
        self.calendar.describe_tools=metadata
        self.assertEqual(self.message()['status'],'answered')
        self.assertEqual(len(self.provider.configs[0]['tools']),2)

    def test_admin_recreation_keeps_accounting_and_pending_state(self):
        self.message()
        service=self.app.state.calendar_llm_only
        original=self.state()
        count=service.agent.store.recreate(('calendar-llm-only',))
        self.assertEqual(count,(1,1));self.assertEqual(self.state()['messages'],original['messages'])
        self.assertEqual(self.state()['llmBudget'],original['llmBudget'])

    def test_no_key_and_reverse_gate_do_not_run_a_turn(self):
        from dataclasses import replace
        service=self.app.state.calendar_llm_only
        original=service.settings
        service.settings=replace(original,openai_api_key=None)
        self.post('message',expected=503,text='Hello',timeMin=START,timeMax=END)
        service.settings=original
        symbolic=self.app.state.calendar_dialogue
        state=symbolic.read();state['status']='review';symbolic.save(state)
        self.post('message',expected=409,text='Hello',timeMin=START,timeMax=END)
        state['status']='idle';symbolic.save(state)
        self.assertEqual(self.provider.configs,[])
