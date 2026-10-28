"""Private JSON qualification lineage; no numerical, scheduler or live I/O."""
import copy,hashlib,json,sys,tempfile,types,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts/pricefm'))
from pricefm_hb import lifecycle as l,activation as a,operation_budget as ob,registry as r
from pricefm_hb.fixture import ARRAY_SHAPES


def build_qualification_fixture(testcase):
    """Shared metadata fixture; patches only host/qualification/funding edges."""
    tmp=tempfile.TemporaryDirectory();testcase.addCleanup(tmp.cleanup);root=Path(tmp.name)
    def write(path,value):
        path=Path(path);path.parent.mkdir(parents=True,exist_ok=True);r.write(path,value);return l.pin(path)
    def enter(target,**kwargs):
        manager=patch.object(target,**kwargs);value=manager.start();testcase.addCleanup(manager.stop);return value
    mutable={'lifecycle.py','activation.py','admission.py','benchmark.py','cost_control.py','operation_budget.py'}
    old={name:hashlib.sha256(('old:'+name).encode()).hexdigest() for name in a.BASE_SOURCES}
    current={name:hashlib.sha256(('new:'+name).encode()).hexdigest() if name in mutable else value for name,value in old.items()}
    state={'schema':l.SCHEMA,'owner':a.OWNER,'claims':{},'spent_tests':[]};now=200
    old_spec={'path':str(root/'old03.control_cpu.json'),'authorization_pin':{},'scope_id':'old03'}
    refs=[]
    for number,job in ((1,'868958'),(2,'869313')):
        key='test'+str(number).zfill(2);scope='r157_control_placement_'+str(number).zfill(2)
        src=root/key;pub=root/('published-'+key)
        release={'purpose':'CONTROL_TEST','scope_id':scope,'task_key':key,'source_hashes':old,
            'resources':{'cpus':1,'memory_MiB':4096,'cpu_seconds':120,'wall_seconds':120},'control_cpu_scope':old_spec}
        rel=write(src/'release.json',release);write(pub/'release.json',release)
        failure={'type':'ExpectedFailure','message':'retained original failure'};fp=write(pub/'outputs/worker-failure.json',failure)
        wp=write(pub/'outputs/worker_evidence.json',{'schema':l.SCHEMA,'task_key':key,'job_id':job,
            'release_sha256':rel['sha256'],'application_passed':False,'files':{'worker-failure.json':fp['sha256']},'error':failure})
        ap=write(pub/'accounting.json',{'task_key':key,'job_id':job,'release_sha256':rel['sha256'],
            'complete':False,'terminal':True,'squeue':'','sacct_with_times':'failed-'+job})
        cp=write(pub/'collection.json',{'schema':l.SCHEMA,'task_key':key,'application_accepted':False,'no_refund':True,'reserved_CPU_seconds':120})
        state['claims'][key]={'task_key':key,'task':{'purpose':'CONTROL_TEST'},'scope_id':scope,'state':'FAILED_RECONCILED',
            'application_accepted':False,'job_id':job,'release_path':str(src),'release_sha256':rel['sha256'],'publication':str(pub),'created':10}
        state['spent_tests'].append(key)
        refs.append({'prior_failed_claim_key':key,'prior_failed_job_id':job,'prior_publication':cp,
            'prior_evidence':{'accounting':ap,'worker_evidence':wp,'worker_failure':fp}})
    old_authorization=write(root/'old03-authorization.json',{'status':'ROOT_ADMITTED_R157_CONTROL_CPU_SCOPE','scope_id':'old03','expires_epoch':100})
    old_spec['authorization_pin']=old_authorization
    request={'accepted_parity_fixture_manifest_sha256':'f'*64}
    src=root/'test03';pub=root/'published-test03';request_pin=write(src/'launch-request.json',request)
    release03={'task_key':'test03','purpose':'CONTROL_TEST','scope_id':'r157_control_placement_03','source_hashes':old,
        'request_sha256':request_pin['sha256'],'control_cpu_scope':old_spec,
        'resources':{'cpus':1,'memory_MiB':4096,'cpu_seconds':120,'wall_seconds':120}}
    rel=write(src/'release.json',release03);write(pub/'release.json',release03)
    parity={'status':'PASS_TEST_FORECAST_PARITY','accepted':True,
        'array_comparison':{name:{'accepted':True,'shape':shape} for name,shape in ARRAY_SHAPES.items()},
        'execution':{'namespace':'TEST','slurm_job_id':'869369','fixture_manifest_sha256':'f'*64}}
    pp=write(pub/'outputs/TEST/parity/parity.json',parity)
    sp=write(pub/'outputs/TEST/parity/completed_evidence.json',{'status':'COMPLETE_TEST_ONLY','artifacts':{'parity.json':pp['sha256']}})
    runtime={'status':'verified','allocation':{'job_id':'869369'},'executable':'/private/qualified-python',
        'python_version':'3.11.13','versions':{'Python':'3.11.13'},'native_library_sha256':{'R':'a'*64,'BLAS':'b'*64}}
    rp=write(pub/'outputs/environment-runtime.json',runtime)
    wp=write(pub/'outputs/worker_evidence.json',{'schema':l.SCHEMA,'task_key':'test03','job_id':'869369',
        'release_sha256':rel['sha256'],'authority_sha256':'a'*64,'source_hashes':old,'application_passed':True,
        'new_model_fits':0,'official_origins':0,'files':{'TEST/parity/parity.json':pp['sha256'],
        'TEST/parity/completed_evidence.json':sp['sha256'],'environment-runtime.json':rp['sha256']}})
    ap=write(pub/'accounting.json',{'task_key':'test03','job_id':'869369','release_sha256':rel['sha256'],
        'squeue':'','complete':True,'terminal':True,'sacct_with_times':'accepted-869369'})
    cp=write(pub/'collection.json',{'schema':l.SCHEMA,'task_key':'test03','application_accepted':True,'no_refund':True,'reserved_CPU_seconds':120})
    state['claims']['test03']={'task_key':'test03','task':{'purpose':'CONTROL_TEST','study':'TEST'},'state':'COLLECTED',
        'application_accepted':True,'scope_id':'r157_control_placement_03','job_id':'869369','authority_sha256':'a'*64,
        'release_path':str(src),'release_sha256':rel['sha256'],'publication':str(pub),'created':10}
    state['spent_tests'].append('test03')
    reference03={'claim_key':'test03','job_id':'869369','release':rel,'publication':cp,'accounting':ap,
        'worker_evidence':wp,'parity_result':pp,'parity_seal':sp,'runtime_result':rp,'source_hashes':old}
    paid03={'scope_id':'old03','expires_epoch':100,'claims':{'test03':{'reserved_CPU':230},'FI':{'reserved_CPU':230,'violations':[{'reason':'PARENT_CPU_CAP_EXCEEDED'}]},'DK2':{'reserved_CPU':230}}}
    paid_pin=write(root/'paid03.json',paid03);write(Path(old_spec['path']),paid03)
    lineage={'schema':l.QUALIFICATION_LINEAGE_SCHEMA,'status':'ROOT_ADMITTED_TEST04_PRESERVING_OLD_ACCEPTED_TEST',
        'protocol_version':l.REPLACEMENT_PROTOCOL,'controller':a.OWNER,'created_epoch':150,'expires_epoch':1000,
        'max_new_attempts':1,'old_charges_refunded':False,'old_clocks_mutated':False,
        'prior_failed_tests':refs,'prior_accepted_test':reference03,'paid_control_snapshot':paid_pin,'paid_control_authorization':old_authorization}
    lineage_pin=write(root/'lineage.json',lineage)
    roles={'test04':{'purpose':'CONTROL_TEST','study':'TEST','scope_id':'r161_control_placement_04'},
        'newFI':{'purpose':'COST_ONLY','study':'FI','scope_id':'new-FI'},'newDK2':{'purpose':'COST_ONLY','study':'DK2','scope_id':'new-DK2'}}
    new_authorization={'protocol_version':l.REPLACEMENT_PROTOCOL,'qualification_lineage':lineage_pin,'recovery_claims':roles}
    auth_pin=write(root/'new-auth.json',new_authorization)
    new_spec={'path':str(root/'new.control_cpu.json'),'authorization_pin':auth_pin,'scope_id':'new-control'}
    new_control={'kind':'INITIAL','CPU_ceiling':720,'scope_id':'new-control','expires_epoch':1000,'authorization':auth_pin}
    requalification04={'schema':l.REQUALIFICATION_SCHEMA,'status':'ROOT_ADMITTED_ONE_SOURCE_BOUND_REPLACEMENT_TEST',
        'protocol_version':l.REPLACEMENT_PROTOCOL,'controller':a.OWNER,'scope_id':'r161_control_placement_04',
        'created_epoch':150,'expires_epoch':1000,'max_new_attempts':1,'old_charges_refunded':False,
        'new_executed_sources':current,'qualification_lineage':lineage_pin}
    requalification_pin=write(root/'requalification04.json',requalification04)
    packet={'expires_epoch':1000}
    release04={'purpose':'CONTROL_TEST','study':'TEST','scope_id':'r161_control_placement_04','task_key':'test04',
        'source_hashes':current,'control_cpu_scope':new_spec,'control_test_requalification':requalification_pin,
        'resources':{'cpus':1,'memory_MiB':4096,'cpu_seconds':120,'wall_seconds':120},'policy_pin':{'path':str(root/'policy.json'),'sha256':'c'*64},'remote_root':'/private/test04'}
    release04_root=root/'test04';write(release04_root/'release.json',release04)
    central=root/'central';central.mkdir();write(central/'activation_registry.json',state)
    enter(l,attribute='CENTRAL',new=central);enter(l,attribute='owner',new=lambda:None)
    enter(l,attribute='policy_document',new=lambda pin:packet);enter(l,attribute='hb_concurrency',new=lambda packet:1)
    enter(l,attribute='control_scope',new=lambda *args,**kw:(object(),new_control))
    enter(l.time,attribute='time',new=lambda:now)
    enter(a,attribute='executed_sources',new=lambda purpose:current)
    enter(a,attribute='validate_qualification',new=lambda *args,**kw:{'parity_runtime':runtime})
    enter(l,attribute='parse_accounting',new=lambda raw,*args,**kw:{'terminal':True,'complete':not raw.startswith('failed-'),'scope_violations':[]})
    enter(ob.OperationBudget,attribute='__init__',new=lambda self,path:setattr(self,'path',Path(path)))
    enter(ob.OperationBudget,attribute='historical_snapshot',new=lambda self,*args:copy.deepcopy(paid03))
    enter(ob,attribute='recovery_claims',new=lambda auth:auth['recovery_claims'])
    return types.SimpleNamespace(**locals())


class QualificationTests(unittest.TestCase):
    def setUp(self):self.f=build_qualification_fixture(self)
    def test_historical03_keeps_old_source_and_all15_without_current_verify(self):
        f=self.f
        with patch.object(l,'verify_release',side_effect=AssertionError('must not verify old release under new source')):
            claim,old=l.validate_historical_accepted_test(f.reference03,f.state)
        self.assertEqual(old['source_hashes'],f.old);self.assertNotEqual(f.old,f.current)
        self.assertEqual(claim['state'],'COLLECTED');self.assertEqual(len(f.parity['array_comparison']),15)
    def test_exact04_preserves03_and_rejects_default_fifth_and_boolean_attempt(self):
        f=self.f;l.validate_control_test_requalification(f.requalification04,f.release04,f.state,now=f.now,packet=f.packet)
        for bad in ('fifth','source','lineage','refund','scope','attempt'):
            value=copy.deepcopy(f.requalification04);state=copy.deepcopy(f.state)
            if bad=='fifth':state['spent_tests'].append('test05')
            if bad=='source':value['new_executed_sources']={}
            if bad=='lineage':value['protocol_version']='other'
            if bad=='refund':value['old_charges_refunded']=True
            if bad=='scope':value['scope_id']='r161_control_placement_05'
            if bad=='attempt':value['max_new_attempts']=True
            with self.subTest(bad=bad),self.assertRaises(ValueError):l.validate_control_test_requalification(value,f.release04,state,now=f.now,packet=f.packet)
    def test_old03_alone_cannot_qualify_new17(self):
        f=self.f;cost={'source_hashes':f.current}
        with self.assertRaisesRegex(ValueError,'exactly one accepted TEST'):l.select_cost_qualification(cost,f.state,f.packet)
    def test_current04_selection_explicit_and_old03_never_reverified(self):
        f=self.f;state=copy.deepcopy(f.state);state['spent_tests'].append('test04')
        state['claims']['test04']={'task_key':'test04','state':'COLLECTED','application_accepted':True,'scope_id':'r161_control_placement_04',
            'release_path':str(f.release04_root),'release_sha256':l.pin(f.release04_root/'release.json')['sha256'],'created':f.now}
        cost={'source_hashes':f.current,'task_key':'newFI','purpose':'COST_ONLY','study':'FI','scope_id':'new-FI','control_cpu_scope':f.new_spec,
            'accepted_control_test':{'claim_key':'test04','release':l.pin(f.release04_root/'release.json')}}
        with patch.object(l,'verify_release',side_effect=lambda path:f.release04 if Path(path)==f.release04_root else self.fail('historical full verify forbidden')):
            selected,_=l.select_cost_qualification(cost,state,f.packet)
            self.assertEqual(selected['task_key'],'test04')
            bad=dict(cost);bad.pop('accepted_control_test')
            with self.assertRaises(ValueError):l.select_cost_qualification(bad,state,f.packet)
        self.assertEqual(state['claims']['test03']['state'],'COLLECTED')
    def test_changed_historical_parity_or_numeric_source_rejects(self):
        f=self.f
        bad=copy.deepcopy(f.reference03);bad['source_hashes']['science.py']='0'*64
        with self.assertRaises(ValueError):l.validate_historical_accepted_test(bad,f.state)
        parity=copy.deepcopy(f.parity);parity['array_comparison'].pop(next(iter(parity['array_comparison'])))
        f.write(Path(f.reference03['parity_result']['path']),parity)
        with self.assertRaises(ValueError):l.validate_historical_accepted_test(f.reference03,f.state)

if __name__=='__main__':unittest.main()
