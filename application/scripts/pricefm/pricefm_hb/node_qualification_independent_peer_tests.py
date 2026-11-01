
"""Independent synthetic protocol/adversarial fixtures; no jobs, network, R or arrays."""
import copy
import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile
import time
import types
import unittest
from unittest.mock import patch
from . import independent_foundation_release_peer as foundation
from . import independent_scientific_ready_peer as scientific
from . import independent_unallocated_drain_review as drain
from . import independent_complete_return_peer as returned
from . import numerical_independent_peer as numeric
from . import startup_batch_stop as producer_foundation
from . import unallocated_tail as tail

PEERS=['independent_foundation_release_peer.py','independent_scientific_ready_peer.py',
       'independent_unallocated_drain_review.py','independent_complete_return_peer.py']


def put(path,value):
    path.write_text(json.dumps(value,indent=2,sort_keys=True,allow_nan=False)+'\n')
    return foundation.pin(path)


def healthy(value=None,cpu=4,wall=.1,pid=123,birth=456):
    g=dict(returncode=0,command_returncode=0,cap_reason=None,CPU_limit=cpu,
        aggregate_CPU_seconds=.02,complete_lifecycle_wall_seconds=wall,
        guardian_forced_monitor_stop=False,session_id=pid,leader_start_ticks=birth,
        stdout=json.dumps(value),stderr='')
    g.update({k:True for k in ['all_owned_descendants_reaped','independent_guardian',
        'kernel_escape_filter','orphan_subreaper','guardian_included_in_CPU','inherited_waited_history_included_once']})
    return g


class TailFixture:
    """Actual producer query and independent consumer; all native/H values synthetic."""
    def __init__(self,base,present=True):
        self.base=base;self.now=time.time();self.present=present
        self.source=Path(tail.__file__).resolve().parent
        self.out=base/'tail';self.out.mkdir(mode=0o700)
        self.registry=base/'registry';self.root=self.registry/'COMPUTE_RUNTIME_INVENTORY';self.root.mkdir(parents=True)
        self.parent=dict(issued_epoch=self.now-100,expires_epoch=self.now+1000,
            execution_node='node-15',qualification_node='node-15',qualification_route_id='a'*32,
            cached_artifact_origin_node='node-13',allowed_metadata_output_root=str(base))
        self.sp=put(base/'PARENT_SCOPE.json',self.parent)
        self.budget=dict(schema='node_unallocated_failure_budget_v1',
            status='PROSPECTIVE_DISTINCT_NODE_UNALLOCATED_FAILURE_TAIL_BUDGET',parent_scope=self.sp,
            role=self.root.name,allocations=drain.ALLOCATIONS,total_administrative_CPU=28,
            maximum_query_calls=1,maximum_drain_calls=1,maximum_peer_calls=1,expires_epoch=self.parent['expires_epoch'])
        bp=put(base/'BUDGET.json',self.budget)
        sources={name:foundation.pin(self.source/name,code=True)['sha256'] for name in producer_foundation.NAMES}
        imap={name:foundation.pin(self.source/name,code=True)['sha256'] for name in PEERS}
        extra={name:foundation.pin(self.source/name,code=True)['sha256'] for name in foundation.EXTRA_ADMIN_FILES}
        family_maps={family:{name:foundation.pin(self.source/name,code=True)['sha256'] for name in names}
            for family,names in [('startup',foundation.FOUNDATION_FILES),('scientific',foundation.SCIENTIFIC_FILES),
                ('numerical',foundation.NUMERICAL_FILES)]}
        core=dict(source_family_files=family_maps,independent_source_files=imap,extra_administrative_source_files=extra,
            administrative_source_files={name:foundation.pin(self.source/name,code=True)['sha256'] for name in foundation.NUMERICAL_ADMIN_FILES},
            scientific_source_files=foundation.FIXED_SCIENCE)
        publication=dict(status='PASS_UNIT_SYNTHETIC_SOURCE_PUBLICATION_NOT_ACTUAL_AUTHORITY',commit='1'*40,
            source_files=sources,independent_source_files=imap,extra_administrative_source_files=extra,core_source_maps=core)
        review=dict(status='PASS_REVIEWED_UNIT_SYNTHETIC_SOURCE_NOT_ACTUAL_AUTHORITY',source_commit='1'*40,
            source_files=sources,independent_source_files=imap,extra_administrative_source_files=extra,core_source_maps=core)
        pp=put(base/'PUBLICATION.json',publication);rp=put(base/'SOURCE_REVIEW.json',review)
        (base/'UNIT_known_hosts').write_text('UNIT synthetic noncredential\n')
        (base/'UNIT_identity').write_text('UNIT synthetic noncredential\n')
        site=dict(host='hb.ucsc.edu',user='jaguir26',account='128x24',partition='128x24',qos='normal',
            known_hosts_file=str(base/'UNIT_known_hosts'),ssh_identity_file=str(base/'UNIT_identity'))
        sitepin=put(base/'SITE.json',site)
        self.config=dict(scope=self.sp,node='node-15',source_dir=str(self.source),registry=str(self.registry),
            publication=pp,source_review=rp,site=sitepin,
            failure_tail_budgets={self.root.name:bp},
            remote_namespace='/mnt/beegfs/home/jaguir26/pricefm_UNIT_NEVER_ISSUED')
        canonical=dict(status='ROOT_AUTHORIZED_CANONICAL_STARTUP_BATCH_CONFIG',binding=copy.deepcopy(self.config),
            issued_epoch=self.now-90,expires_epoch=self.now+900)
        self.config['canonical_authority']=put(base/'CANONICAL.json',canonical)
        cp=put(base/'CONFIG.json',self.config)
        self.packet=dict(role=self.root.name,scope_id='UNIT_NONCANDIDATE_JOB',
            remote_root=self.config['remote_namespace']+'/UNIT_NONCANDIDATE_JOB',
            execution_node='node-15',qualification_route_id='a'*32)
        packetpin=put(self.root/'PACKET.json',self.packet)
        self.job=dict(job_id='123456789',scope_id=self.packet['scope_id'])
        jobpin=put(self.root/'JOB.json',self.job)
        started=dict(status='ACTION_STARTED_NOT_SUCCESS',role=self.root.name,action='ready',
            command_pid=111,command_birth_ticks=222,source_sha256=sources['startup_batch_stop.py'],
            limits=dict(local_CPU=6,remote_unknown_fee=6,wall=330,maximum_calls=1))
        startpin=put(self.registry/'control_0000.started.json',started)
        failed=dict(returncode=125,cap_reason='OwnedStopError: UNIT',all_owned_descendants_reaped=True,
            independent_guardian=True,guardian_forced_monitor_stop=False,guardian_included_in_CPU=True,
            inherited_waited_history_included_once=True,aggregate_CPU_seconds=.1,
            owned_stop_witness=dict(schema='r164_owned_stop_failure_witness_v1',uid=os.getuid(),monitor_affinity=[31],
                states_are_not_accepted_for_accounting=True,session_id=111,leader_start_ticks=222,
                exact_proved_owned_items=[dict(pid=111,start_ticks=222,sid=111,pgid=111,uid=os.getuid(),affinity=[31])]))
        self.failed=failed;fg=put(base/'FAILED_GUARD.json',failed)
        self.scope=dict(schema='node_unallocated_failure_tail_scope_v1',
            status='PROSPECTIVE_EXACT_UNALLOCATED_NODE_ROLE_DRAIN_SCOPE',config=cp,parent_scope=self.sp,parent_budget=bp,
            family='startup',role=self.root.name,job=jobpin,packet=packetpin,job_id=self.job['job_id'],
            scope_id=self.packet['scope_id'],execution_node='node-15',qualification_node='node-15',qualification_route_id='a'*32,
            query_source=foundation.pin(tail.__file__,code=True),drain_source=foundation.pin(tail.__file__,code=True),
            peer_source=foundation.pin(drain.__file__,code=True),peer_source_approval=rp,
            failure_evidence=dict(kind='FAILED_NATIVE_ACTION_DRAINED',failed_guard=fg,failed_started=startpin),
            allocations=drain.ALLOCATIONS,total_administrative_CPU=28,maximum_query_calls=1,maximum_drain_calls=1,
            maximum_peer_calls=1,issued_epoch=self.now-80,expires_epoch=self.now+800,allowed_output_root=str(self.out))
        self.scope_path=base/'TAIL_SCOPE.json';self.scopepin=put(self.scope_path,self.scope)
        self.calls=[];self.query=None
    def native(self,site,argv):
        self.calls.append(argv)
        if argv[0]=='sacct':
            text='|'.join([self.job['job_id'],self.packet['scope_id'],'jaguir26',str(os.getuid()),
                '128x24','128x24','CANCELLED','0:0','00:00:00','0','0','1','None','2026-11-01T05:00:00','None'])+'\n'
            return dict(argv=argv,returncode=0,stdout=text,stderr='')
        if argv[0]=='squeue':return dict(argv=argv,returncode=1,stdout='',stderr='slurm_load_jobs error: Invalid job id specified\n')
        if argv[0]=='stat':
            lock=self.config['remote_namespace']+'/qualification.lock';marker=lock+'/OWNED_'+self.packet['scope_id']
            text=f'{os.getuid()}|10|101|4096|2|{stat.S_IFDIR|0o700:x}|{lock}\n'
            text+=f'{os.getuid()}|10|102|0|1|{stat.S_IFREG|0o600:x}|{marker}\n'
            return dict(argv=argv,returncode=0,stdout=text,stderr='')
        if argv[0]=='test':
            exists=self.present and ('qualification.lock' in argv[-1])
            return dict(argv=argv,returncode=0 if exists else 1,stdout='',stderr='')
        if argv[0] in {'rm','rmdir'}:
            self.present=False;return dict(argv=argv,returncode=0,stdout='',stderr='')
        raise AssertionError('nonfixture native operation')
    def produce(self):
        with patch.object(tail,'outer_context'),patch.object(tail,'native',side_effect=self.native):
            self.query=tail.run('query',self.scopepin)
        put(self.out/'QUERY_GUARD.json',healthy(self.query,pid=self.query['command_pid'],birth=self.query['command_birth_ticks']))
    def review(self):
        return drain.review_query(str(self.out/'QUERY_RESULT.json'),str(self.out/'QUERY_GUARD.json'),
            str(self.scope_path),str(self.out/'QUERY_REVIEW.json'))
    def mutate_raw(self,name,change):
        path=self.out/name;value=json.loads(path.read_text());change(value);newpin=put(path,value)
        if name=='QUERY_accounting.json':self.query['raw_accounting']=newpin
        elif name=='QUERY_queue.json':self.query['raw_queue']=newpin
        elif name=='QUERY_claim_stat.json':self.query['claim_identity']['raw_stat']=newpin
        else:
            key=name.removeprefix('QUERY_').removesuffix('.json');self.query['observations'][key]['observation']=newpin
        self.sync()
    def sync(self):
        put(self.out/'QUERY_RESULT.json',self.query)
        put(self.out/'QUERY_GUARD.json',healthy(self.query,pid=self.query['command_pid'],birth=self.query['command_birth_ticks']))


class NodeAndSourceTests(unittest.TestCase):
    def test_exact_selected_node_and_cache_origin_are_distinct(self):
        c=dict(node='node-15');s=dict(execution_node='node-15',qualification_node='node-15',
            qualification_route_id='a'*32,cached_artifact_origin_node='node-13')
        self.assertEqual(foundation.route_fields(c,s),('node-15','a'*32))
        for field,value in [('execution_node','node-13'),('qualification_node','node-13'),
                            ('qualification_route_id','b'*31),('cached_artifact_origin_node','node-15')]:
            bad=copy.deepcopy(s);bad[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):foundation.route_fields(c,bad)
    def test_numeric_peer_requires_exact_same_scope_route(self):
        c=dict(node='node-15');s=dict(execution_node='node-15',qualification_node='node-15',
            qualification_route_id='a'*32,cached_artifact_origin_node='node-13')
        self.assertEqual(numeric.selected_qualification_route(c,s),('node-15','a'*32))
        with self.assertRaises(ValueError):numeric.selected_qualification_route(c,s,dict(node='node-15',qualification_route_id='b'*32))
    def test_original_guard_boolean_CPU_and_nonfinite_rejected(self):
        for key,value in [('CPU_limit',True),('aggregate_CPU_seconds',float('nan')),
                          ('complete_lifecycle_wall_seconds',float('inf')),('all_owned_descendants_reaped',False)]:
            g=healthy();g[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):foundation.guard(g,4,120)
    def test_duplicate_and_nonfinite_JSON_rejected(self):
        for value in ['{"a":1,"a":2}','{"x":NaN}','{"x":1e999}']:
            with self.subTest(value=value),self.assertRaises(ValueError):foundation.strict(value)
    def test_foreign_cached_dependency_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            with patch.dict('sys.modules',{'pricefm_hb.foreign':types.SimpleNamespace(__file__='/UNIT_FOREIGN/foreign.py')}):
                with self.assertRaises(ValueError):foundation.import_core(Path(td),[])
    def test_closed_maps_reject_cardinality_preserving_substitution_before_import(self):
        pub=dict(source_files={n:'a'*64 for n in foundation.FOUNDATION_FILES},
            independent_source_files={n:'b'*64 for n in foundation.INDEPENDENT_FILES},
            extra_administrative_source_files={n:'c'*64 for n in foundation.EXTRA_ADMIN_FILES})
        pub['core_source_maps']=dict(source_family_files={family:{n:'a'*64 for n in names}
            for family,names in [('startup',foundation.FOUNDATION_FILES),('scientific',foundation.SCIENTIFIC_FILES),
                ('numerical',foundation.NUMERICAL_FILES)]},administrative_source_files={n:'d'*64 for n in foundation.NUMERICAL_ADMIN_FILES},
            scientific_source_files=foundation.FIXED_SCIENCE,independent_source_files=pub['independent_source_files'],
            extra_administrative_source_files=pub['extra_administrative_source_files'])
        foundation.closed_source_maps(pub,copy.deepcopy(pub),'foundation',{})
        for key in ['source_files','independent_source_files','extra_administrative_source_files']:
            bad=copy.deepcopy(pub);old=next(iter(bad[key]));bad[key]['UNIT_UNREVIEWED.py']=bad[key].pop(old)
            with self.subTest(key=key),self.assertRaises(ValueError):foundation.closed_source_maps(bad,copy.deepcopy(bad),'foundation',{})
        numeric_pub=dict(source_files={n:'a'*64 for n in foundation.NUMERICAL_FILES},
            administrative_source_files={n:'d'*64 for n in foundation.NUMERICAL_ADMIN_FILES},
            independent_source_files=pub['independent_source_files'],extra_administrative_source_files=pub['extra_administrative_source_files'],
            core_source_maps=pub['core_source_maps'],scientific_source_files=foundation.FIXED_SCIENCE)
        config=dict(scientific_sources={n:dict(path='/UNIT_SOURCE/'+n,sha256=sha) for n,sha in foundation.FIXED_SCIENCE.items()})
        foundation.closed_source_maps(numeric_pub,copy.deepcopy(numeric_pub),'numerical',config)
        bad=copy.deepcopy(numeric_pub);old=next(iter(bad['administrative_source_files']));bad['administrative_source_files']['UNIT_UNREVIEWED.py']=bad['administrative_source_files'].pop(old)
        with self.assertRaises(ValueError):foundation.closed_source_maps(bad,copy.deepcopy(bad),'numerical',config)
        bad=copy.deepcopy(config);old=next(iter(bad['scientific_sources']));bad['scientific_sources']['UNIT_DIFFERENT.R']=bad['scientific_sources'].pop(old)
        with self.assertRaises(ValueError):foundation.closed_source_maps(numeric_pub,copy.deepcopy(numeric_pub),'numerical',bad)


class IndependentTailTests(unittest.TestCase):
    def fixture(self,test,present=True):
        with tempfile.TemporaryDirectory(prefix='UNIT_NODE_QUALIFICATION_',dir='/home/jaguir26/.local/state/pricefm') as name:
            f=TailFixture(Path(name),present);f.produce();test(f)
    def test_real_producer_independent_peer_and_exact_drain_present(self):
        def check(f):
            r=f.review();self.assertEqual(len(f.calls),8)
            self.assertEqual(r['permitted_operation'],'REMOVE_EXACT_OWNED_ZERO_BYTE_MARKER_THEN_NONRECURSIVE_EMPTY_LOCK')
            authority=dict(status='ROOT_AUTHORIZED_EXACT_UNALLOCATED_NODE_ROLE_DRAIN',
                **{k:f.query[k] for k in ['config','tail_scope','parent_scope','family','role','job','packet','job_id',
                    'scope_id','execution_node','qualification_route_id','source']},
                parent_budget=f.scope['parent_budget'],query_result=foundation.pin(f.out/'QUERY_RESULT.json'),
                query_guard=foundation.pin(f.out/'QUERY_GUARD.json'),independent_review=foundation.pin(f.out/'QUERY_REVIEW.json'),
                issued_epoch=time.time(),expires_epoch=f.scope['expires_epoch'])
            ap=put(f.out/'ROOT_AUTHORITY.json',authority)
            with patch.object(tail,'outer_context'),patch.object(tail,'native',side_effect=f.native):
                result=tail.run('drain',f.scopepin,ap)
            self.assertEqual(result['status'],'EXACT_UNALLOCATED_NODE_ROLE_CLAIM_ABSENCE_PENDING_OUTER_GUARD')
            self.assertEqual([x[0] for x in f.calls[-5:]],['stat','rm','rmdir','test','test'])
        self.fixture(check)
    def test_absent_claim_never_invents_inode_or_mutation(self):
        def check(f):
            r=f.review();self.assertEqual(len(f.calls),7);self.assertIsNone(r['claim_identity'])
            self.assertEqual(r['permitted_operation'],'VERIFY_TWO_EXACT_ABSENCES_ONLY')
        self.fixture(check,False)
    def test_actual_cancelled_queue_invalid_job_is_allowed_only_exactly(self):
        for field,value in [('returncode',255),('returncode',True),('stderr','permission denied'),
                            ('stderr','slurm_load_jobs error: Invalid job id specified'),('stdout','123456789|RUNNING\n')]:
            def check(f):
                f.mutate_raw('QUERY_queue.json',lambda x:x.update({field:value}))
                with self.assertRaises(ValueError):f.review()
            with self.subTest(field=field,value=value):self.fixture(check)
    def test_Alloc0_owner_start_node_and_steps_fail_closed(self):
        for index,value in [(0,'987'),(2,'other'),(3,'0'),(6,'COMPLETED'),(8,'00:00:01'),
                            (9,'1'),(10,'1'),(12,'2026-11-01T05:00:00'),(14,'node-15')]:
            def check(f):
                def mutate(x):
                    a=x['stdout'].strip().split('|');a[index]=value;x['stdout']='|'.join(a)+'\n'
                f.mutate_raw('QUERY_accounting.json',mutate)
                with self.assertRaises(ValueError):f.review()
            with self.subTest(index=index):self.fixture(check)
    def test_exact_native_argv_foreign_nonce_and_permission_denied_rejected(self):
        for action in ['argv','stderr','returncode']:
            def check(f):
                def mutate(x):
                    x[action]=(['test','-e','/UNIT_FOREIGN/READY.json'] if action=='argv'
                        else 'permission denied' if action=='stderr' else 255)
                f.mutate_raw('QUERY_ready.json',mutate)
                with self.assertRaises(ValueError):f.review()
            with self.subTest(action=action):self.fixture(check)
    def test_owned_marker_stat_symlink_hardlink_size_uid_and_inode(self):
        for field,value in [(0,'0'),(2,'0'),(3,'1'),(4,'2'),(5,f'{stat.S_IFLNK|0o777:x}')]:
            def check(f):
                def mutate(x):
                    a=x['stdout'].splitlines();v=a[1].split('|');v[field]=value;a[1]='|'.join(v);x['stdout']='\n'.join(a)+'\n'
                f.mutate_raw('QUERY_claim_stat.json',mutate)
                with self.assertRaises(ValueError):f.review()
            with self.subTest(field=field):self.fixture(check)
    def test_query_guard_PID_birth_false_reap_and_source_splice(self):
        for key,value in [('session_id',999),('leader_start_ticks',999),('all_owned_descendants_reaped',False)]:
            def check(f):
                p=f.out/'QUERY_GUARD.json';v=json.loads(p.read_text());v[key]=value;put(p,v)
                with self.assertRaises(ValueError):f.review()
            with self.subTest(key=key):self.fixture(check)
    def test_redundant_artifacts_unknown_fields_and_replay_rejected(self):
        for mode in ['extra','unknown','replay']:
            def check(f):
                if mode=='extra':put(f.out/'QUERY_foreign.json',dict(UNIT=True))
                elif mode=='unknown':f.query['extra_admission']=True;f.sync()
                else:f.review()
                with self.assertRaises((ValueError,FileExistsError)):f.review()
            with self.subTest(mode=mode):self.fixture(check)
    def test_nested_original_failed_guard_without_top_CPU_session_is_honest(self):
        f=types.SimpleNamespace()
        start=dict(status='ACTION_STARTED_NOT_SUCCESS',source_sha256='a'*64,command_pid=11,command_birth_ticks=12,
            action='ready',limits=dict(local_CPU=6,remote_unknown_fee=6,wall=330,maximum_calls=1))
        g=dict(returncode=125,all_owned_descendants_reaped=True,independent_guardian=True,
            guardian_forced_monitor_stop=False,guardian_included_in_CPU=True,inherited_waited_history_included_once=True,
            owned_stop_witness=dict(schema='r164_owned_stop_failure_witness_v1',session_id=11,leader_start_ticks=12,
                uid=os.getuid(),monitor_affinity=[31],states_are_not_accepted_for_accounting=True,
                exact_proved_owned_items=[dict(pid=11,start_ticks=12,sid=11,uid=os.getuid())]))
        drain.failed_action_guard(g,start,'a'*64)
        for key,value in [('leader_start_ticks',99),('uid',0),('monitor_affinity',[0])]:
            bad=copy.deepcopy(g);bad['owned_stop_witness'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):drain.failed_action_guard(bad,start,'a'*64)
        for key,value in [('action','UNKNOWN'),('action','prepare'),('action','reconcile'),
                          ('limits',dict(local_CPU=1000000)),
                          ('limits',dict(local_CPU=6,remote_unknown_fee=600,wall=330,maximum_calls=1)),
                          ('limits',dict(local_CPU=6,remote_unknown_fee=6,wall=330,maximum_calls=True))]:
            bad=copy.deepcopy(start);bad[key]=value
            with self.subTest(start_field=key,value=value),self.assertRaises(ValueError):drain.failed_action_guard(g,bad,'a'*64)


class CompleteReturnProtocolTests(unittest.TestCase):
    def test_original_exact_TSYNC_program_and_ACK_required(self):
        deny=0x00050000|1;enosys=0x00050000|38
        ins=[(0x20,0,0,4),(0x15,1,0,0xc000003e),(0x06,0,0,0x80000000),(0x20,0,0,0),
             (0x45,0,1,0x40000000),(0x06,0,0,deny),(0x15,0,1,57),(0x06,0,0,deny),
             (0x15,0,1,58),(0x06,0,0,deny),(0x15,0,1,435),(0x06,0,0,enosys),
             (0x15,0,3,56),(0x20,0,0,16),(0x45,1,0,0x10000),(0x06,0,0,deny),(0x06,0,0,0x7fff0000)]
        import struct
        digest=hashlib.sha256(b''.join(struct.pack('<HBBI',*x) for x in ins)).hexdigest()
        g=dict(scientific_filter_kernel_attestation=dict(operation='SECCOMP_SET_MODE_FILTER',flags='TSYNC',
            kernel_return=0,instruction_count=17,program_sha256=digest),postbootstrap_TSYNC_scientific_fork_denial=True,
            scientific_target_access_handshake=True)
        self.assertEqual(returned.kernel_tsync(g),digest)
        for key,value in [('kernel_return',1),('instruction_count',True),('program_sha256','f'*64)]:
            v=copy.deepcopy(g);v['scientific_filter_kernel_attestation'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):returned.kernel_tsync(v)
    def test_closed_opaque_toy_inventory_has_thirteen_states_and_eight_arrays(self):
        names,binaries=returned.numerical_output_inventory('TOY_PARITY')
        self.assertEqual(sum(x.endswith('.rds') for x in binaries),13)
        self.assertEqual(sum(x.endswith('.bin') for x in binaries),8)
        self.assertNotIn('numerical/bridge/full_state.rds',names)
        bridge,opaque=returned.numerical_output_inventory('ZERO_UPDATE_BRIDGE')
        self.assertEqual(opaque,{'numerical/bridge/full_state.rds'})
        with self.assertRaises(ValueError):returned.numerical_output_inventory('PILOT')
    def test_scalar_whitelist_rejects_arrays_duplicates_and_unknown_members(self):
        with self.assertRaises(AssertionError):returned.atom(dict(available=True,kind='number',value=[1,2]))
        with self.assertRaises(ValueError):returned.unique_pairs([('x',1),('x',2)])
        with self.assertRaises(AssertionError):returned.atom(dict(available=False,label='UNAVAILABLE',array=[1]))
    def test_wrong_current_owner_birth_never_retirement(self):
        identity=dict(uid=os.getuid(),pid=11,start_ticks=12,boot_id='UNIT',affinity=[0])
        ready=dict(worker_identity=identity,inventory=dict(scheduler=dict(uid=os.getuid())))
        g=dict(schema='r157_traced_bootstrap_guard_receipt_v1',status='EXITED',remaining_owned_lifetimes=[],
            unexpected_untraced_child_waits=[],maximum_combined_CPU_seconds=450,parent_plus_all_reaped_child_CPU_seconds=1,
            wall_seconds=1,supervisor=identity)
        g.update({x:True for x in ['reaped','drained','CPU_accounting_complete','all_newborns_kernel_traced_before_execution',
            'tracer_death_kernel_EXITKILL_enabled']})
        a=dict(path='/UNIT_AUTH.json',sha256='a'*64)
        tree=dict(state='CLOSED',scope='UNIT',authority_pin=a,supervisor=identity)
        returned.owner_lifetime(g,tree,ready,'UNIT',a)
        bad=copy.deepcopy(tree);bad['supervisor']['start_ticks']=99
        with self.assertRaises(ValueError):returned.owner_lifetime(g,bad,ready,'UNIT',a)


from . import node_startup_watch as watcher
from . import scientific_batch as producer_scientific
from . import numerical_batch as producer_numerical


class WatchClock:
    def __init__(self):self.now=time.time()
    def time(self):self.now+=.002;return self.now
    def monotonic(self):return self.now
    def sleep(self,value):self.now+=value


class WatchFixture:
    def __init__(self,base,family='startup'):
        self.base=base;self.clock=WatchClock();self.family=family;self.source=Path(watcher.__file__).parent
        self.role={'startup':'COMPUTE_RUNTIME_INVENTORY','scientific':'SCIENTIFIC_NAMESPACE_NO_OPTIMIZER',
                   'numerical':'TOY_PARITY'}[family]
        self.root=base/'registry'/self.role;self.root.mkdir(parents=True)
        self.out=base/'watch';self.out.mkdir(mode=0o700)
        self.scope=dict(issued_epoch=self.clock.now-10,expires_epoch=self.clock.now+1000,
            execution_node='node-15',qualification_node='node-15',qualification_route_id='a'*32,
            cached_artifact_origin_node='node-13',allowed_metadata_output_root=str(base),
            administrative_allocations={('startup_watch120' if family=='startup' else 'startup_watch60'):120 if family=='startup' else 60})
        sp=put(base/'SCOPE.json',self.scope)
        count=2 if family=='startup' else 1
        bp=put(base/'WATCH_BUDGET.json',dict(status=('PROSPECTIVE_FRESH_NUMERICAL_STARTUP_WATCH_BUDGET'
            if family=='numerical' else 'PROSPECTIVE_FRESH_NODE_STARTUP_WATCH_BUDGET'),
            scope=sp,profile=watcher.PROFILE,roles=['COMPUTE_RUNTIME_INVENTORY','EXACT_R46_STARTUP_METADATA'] if count==2 else [self.role],
            combined_startup_watch_CPU_ceiling=60*count,expires_epoch=self.scope['expires_epoch']))
        src=foundation.pin(watcher.__file__,code=True)
        imap={name:foundation.pin(self.source/name,code=True)['sha256'] for name in PEERS}
        pp=put(base/'PUB.json',dict(extra_administrative_source_files={'node_startup_watch.py':src['sha256']},independent_source_files=imap))
        rp=put(base/'REVIEW.json',dict(extra_administrative_source_files={'node_startup_watch.py':src['sha256']},independent_source_files=imap))
        self.config=dict(source_dir=str(self.source),registry=str(base/'registry'),scope=sp,node='node-15',
            startup_watch_roots={self.role:str(self.out)},startup_watch_budget=bp,publication=pp,source_review=rp)
        self.cp=put(base/'CONFIG.json',self.config)
        bname={'startup':'startup_batch_stop.py','scientific':'scientific_batch.py','numerical':'numerical_batch.py'}[family]
        self.packet=dict(role=self.role,scope_id='UNIT_WATCH_NONCANDIDATE',remote_root='/UNIT_REMOTE/UNIT_WATCH_NONCANDIDATE',
            sources={bname:foundation.pin(self.source/bname,code=True)},spec_sha256='a'*64,
            execution_node='node-15',qualification_route_id='a'*32)
        self.job=dict(job_id='123456789',scope_id=self.packet['scope_id'])
        put(self.root/'PACKET.json',self.packet);put(self.root/'JOB.json',self.job)
        self.ready=dict(status='READY_SOURCE_BOUND_COMPUTE_METADATA',role=self.role,job_id=self.job['job_id'],
            scope_id=self.packet['scope_id'],sources=self.packet['sources'],spec_sha256='a'*64,node='node-15',
            qualification_route_id='a'*32,inventory=dict(qualification_route_id='a'*32),observed_epoch=self.clock.now,
            affinity=[0],cpus_per_task=1,models=0)
        self.authority=dict(status='ROOT_AUTHORIZED_NODE_STARTUP_WATCH',config=self.cp,parent_scope=sp,
            role=self.role,family=family,source=src,budget=bp,profile=watcher.PROFILE,maximum_calls=1,
            automatic_retry=False,output_root=str(self.out),
            original_supervisor=foundation.pin(self.source/'profile_supervisor.py',code=True),
            issued_epoch=self.clock.now-5,expires_epoch=self.scope['expires_epoch'])
        self.ap=put(base/'AUTHORITY.json',self.authority)
        self.index=0
        producer={'startup':producer_foundation,'scientific':producer_scientific,'numerical':producer_numerical}[family]
        def context(*args):return producer,self.config,self.scope,{},self.authority,self.out,self.root,self.packet,self.job
        def native(site,argv):return dict(argv=argv,returncode=1 if self.index<2 else 0,stdout='',stderr='')
        def transfer(site,commands,path):
            path.write_text('\n'.join(commands)+'\n')
            put(self.out/'startup'/('probe_%02d.READY.json'%self.index),self.ready)
            return dict(returncode=0,stdout='',stderr='')
        def child(argv,stdout,stderr,**kwargs):
            self.index=int(argv[-1])
            value=watcher.probe(self.cp['path'],self.role,family,self.ap,self.index)
            stdout.write(json.dumps(healthy(value,cpu=3,pid=value['command_pid'],birth=value['command_birth_ticks'])).encode())
            return types.SimpleNamespace(wait=lambda:0)
        # The actual producer's state/intent and transfer-code plumbing is used;
        # scheduler/transfer/H executions remain explicitly synthetic fixtures.
        with patch.object(watcher,'context',side_effect=context),patch.object(producer,'require_outer_context'),\
             patch.object(watcher.resource,'getrlimit',return_value=(3,3)),patch.object(watcher.resource,'setrlimit'),\
             patch.object(producer,'run_native',side_effect=native),patch.object(producer,'run_sftp',side_effect=transfer),\
             patch.object(watcher.subprocess,'Popen',side_effect=child),patch.object(watcher.time,'time',side_effect=self.clock.time),\
             patch.object(watcher.time,'monotonic',side_effect=self.clock.monotonic),patch.object(watcher.time,'sleep',side_effect=self.clock.sleep):
            self.watch=watcher.wait(self.cp['path'],self.role,family,self.ap)
        (self.root/'READY.json').write_bytes((self.out/'startup/probe_02.READY.json').read_bytes())
    def review(self):
        with patch.object(foundation.time,'time',side_effect=self.clock.time):
            return foundation.review_startup_watch(self.cp['path'],self.config,self.scope,self.packet,self.job,self.ready,self.family)
    def mutate(self,index,change):
        p=self.out/'startup'/('probe_%02d.RESULT.json'%index);v=json.loads(p.read_text());change(v);put(p,v)
        gp=self.out/'startup'/('probe_%02d.guard.json'%index)
        g=json.loads(gp.read_text());g['stdout']=json.dumps(v);put(gp,g)
        self.watch['attempts'][index]=dict(guard=foundation.pin(gp),result=v)
        put(self.out/'STARTUP_WATCH.json',self.watch)


class IndependentGenericWatchTests(unittest.TestCase):
    def fixture(self,callback,family='startup'):
        with tempfile.TemporaryDirectory(prefix='UNIT_INDEPENDENT_WATCH_') as name:callback(WatchFixture(Path(name),family))
    def test_actual_generic_wait_with_delayed_READY_then_independent_reconcile(self):
        self.fixture(lambda f:self.assertEqual(f.review(),foundation.pin(f.out/'STARTUP_WATCH.json')))
    def test_same_watch_protocol_for_scientific_role(self):
        self.fixture(lambda f:self.assertEqual(f.review(),foundation.pin(f.out/'STARTUP_WATCH.json')),'scientific')
    def test_actual_generic_numerical_watch_to_current_independent_peer_branch(self):
        def check(f):
            with patch.object(numeric.time,'time',side_effect=f.clock.time):
                result=numeric.startup_watch_review(f.cp['path'],f.scope,f.root,f.ready,
                    dict(startup_watch_authority=f.ap),'/UNIT_NOT_EXECUTED_AUTHORITY.json')
            self.assertEqual(result,f.watch)
        self.fixture(check,'numerical')
    def test_numerical_lifecycle_must_bind_exact_generic_watch_authority(self):
        def check(f):
            with patch.object(numeric.time,'time',side_effect=f.clock.time),self.assertRaises(ValueError):
                numeric.startup_watch_review(f.cp['path'],f.scope,f.root,f.ready,
                    dict(startup_watch_authority=dict(path='/UNIT_FOREIGN.json',sha256='f'*64)),
                    '/UNIT_NOT_EXECUTED_AUTHORITY.json')
        self.fixture(check,'numerical')
    def test_current_source_authority_route_and_contiguous_index(self):
        for key,value in [('execution_node','node-13'),('qualification_route_id','b'*32),('probe_index',True),
                          ('watch_source',dict(path='/UNIT_FOREIGN.py',sha256='f'*64))]:
            def check(f):
                f.mutate(0,lambda x:x.update({key:value}))
                with self.assertRaises(ValueError):f.review()
            with self.subTest(key=key):self.fixture(check)
    def test_exact_SFTP_transfer_proof_required(self):
        def check(f):
            p=f.out/'startup/probe_02.transfer.json';v=json.loads(p.read_text());v['returncode']=1;put(p,v)
            with self.assertRaises(ValueError):f.review()
        self.fixture(check)
    def test_exact_SFTP_single_command_and_no_redundant_probe(self):
        for kind in ['command','extra']:
            def check(f):
                if kind=='command':(f.out/'startup/probe_02.sftp').write_text('get /UNIT_FOREIGN /UNIT_WRONG\n')
                else:put(f.out/'startup/probe_03.native.json',dict(UNIT_FOREIGN=True))
                with self.assertRaises(ValueError):f.review()
            with self.subTest(kind=kind):self.fixture(check)
    def test_scientific80second_READY_age_preserved(self):
        def check(f):
            f.clock.now=f.ready['observed_epoch']+80
            with self.assertRaises(ValueError):f.review()
        self.fixture(check,'scientific')


class IndependentRPlanTests(unittest.TestCase):
    def fixture(self):
        now=time.time();remote='/mnt/beegfs/home/jaguir26/pricefm_UNIT_RPLAN/UNIT_NONCANDIDATE'
        source=Path(producer_foundation.__file__).parent
        hashes={name:foundation.pin(source/name,code=True)['sha256'] for name in producer_foundation.NAMES}
        sources={name:dict(path=remote+'/package/pricefm_hb/'+name,sha256=sha) for name,sha in hashes.items()}
        scope=dict(status='PROSPECTIVE_TWO_ROLE_HB_RUNTIME_QUALIFICATION_SCOPE',maximum_jobs=2,
            compute_CPU_reservation=1200,issued_epoch=now-10,expires_epoch=now+1000,
            execution_node='node-15',qualification_node='node-15',qualification_route_id='a'*32,cached_artifact_origin_node='node-13')
        sp=dict(path='/UNIT_PARENT/SCOPE.json',sha256='1'*64)
        manifest=dict(files=[dict(relative='R_HOME/bin/exec/R',bytes=100,mode=0o755,sha256=foundation.NATIVE_R_SHA)],total_bytes=100)
        mp=dict(path=remote+'/carrier_manifest.json',sha256='2'*64);cp=dict(path=remote+'/carrier.tar.gz',sha256='3'*64)
        packet=dict(role='EXACT_R46_STARTUP_METADATA',scope_id='UNIT_RPLAN',remote_root=remote,sources=sources,spec_sha256='4'*64)
        spec=dict(schema='pricefm_startup_batch_spec_v1',role=packet['role'],scope_id=packet['scope_id'],remote_root=remote,
            sources=sources,scope=dict(path=remote+'/Q_SCOPE.json',sha256=sp['sha256']),
            aggregate_CPU_reservation=600,threads=1,memory_MiB=8192,expires_epoch=scope['expires_epoch'],
            node='node-15',qualification_route_id='a'*32,
            accepted_inventory=dict(status='ACCEPTED_COMPLETE_STARTUP_BATCH_METADATA_ROLE',role='COMPUTE_RUNTIME_INVENTORY',
                kernel_matrix_pass=True,qualification_route_id='a'*32),carrier_manifest=mp,carrier=cp,
            cached_python='/UNIT_CACHED/python',cached_python_sha256='5'*64)
        helpers={name:dict(logical_path='/usr/bin/'+name,resolved_file=dict(path='/usr/bin/'+name,sha256='6'*64),bytes=100)
            for name in ['which','uname']}
        inventory=dict(status='COMPUTE_RUNTIME_FACTS_NO_R',job_id='123456789',node='node-15',qualification_route_id='a'*32,
            affinity=[0],R_executions=0,python=dict(path=spec['cached_python'],sha256=spec['cached_python_sha256']),helpers=helpers)
        ready=dict(status='READY_SOURCE_BOUND_COMPUTE_METADATA',role=packet['role'],scope_id=packet['scope_id'],
            spec_sha256=packet['spec_sha256'],sources=sources,job_id=inventory['job_id'],node='node-15',
            qualification_route_id='a'*32,affinity=[0],cpus_per_task=1,models=0,inventory=inventory,
            carrier=dict(status='DURABLE_BYTE_IDENTICAL_RUNTIME_CARRIER_INSTALLED',root=remote+'/runtime_carrier',manifest=mp,
                files=[dict(path=remote+'/runtime_carrier/R_HOME/bin/exec/R',sha256=foundation.NATIVE_R_SHA)],file_count=1,
                total_bytes=100,all_writes_before_file_sync=True,no_original_runtime_mutation=True))
        review=dict(status='PASS_REVIEWED_STREAMING_RUNTIME_ARCHIVE_REAL_ARTIFACT',manifest=mp,archive=cp)
        plan,child=producer_foundation.build_R_startup_plan(ready,packet,spec,scope,review,manifest,now,sp,hashes)
        child.update(status='PROSPECTIVE_PRICEFM_STARTUP_COMPUTE_QUALIFICATION_SCOPE',issued_epoch=now)
        child.pop('required_issued_status',None)
        return plan,child,manifest,ready,spec,scope,sp,hashes
    def test_actual_R_plan_builder_then_independent_contract(self):
        args=self.fixture();self.assertEqual(foundation.validate_R_plan(*args),args[0])
    def test_R_plan_foreign_native_environment_alias_source_and_new_compute_rejected(self):
        for kind in ['node','native','env','source','new_compute']:
            args=list(copy.deepcopy(self.fixture()));plan,child=args[:2]
            if kind=='node':plan['placement']['node']='node-13'
            elif kind=='native':plan['runtime']['executable']['sha256']='0'*64
            elif kind=='env':plan['environment']['OPENBLAS_NUM_THREADS']='2'
            elif kind=='source':plan['sources']['original_supervisor']['sha256']='0'*64
            else:child['no_new_compute_reservation']=False
            with self.subTest(kind=kind),self.assertRaises(ValueError):foundation.validate_R_plan(*args)


class IndependentScientificBundleTests(unittest.TestCase):
    def fixture(self,base):
        from . import scientific_code_install as installer
        from . import scientific_metadata_owner as owner
        from . import scientific_namespace_contract as contract
        now=time.time();remote='/mnt/beegfs/home/jaguir26/pricefm_UNIT_SCI/UNIT_NONCANDIDATE'
        role='SCIENTIFIC_NAMESPACE_NO_OPTIMIZER';source=Path(producer_scientific.__file__).parent
        root=base/'registry'/role;root.mkdir(parents=True)
        scope=dict(issued_epoch=now-10,expires_epoch=now+2000,allowed_metadata_output_root=str(base),
            execution_node='node-15',qualification_node='node-15',qualification_route_id='a'*32,cached_artifact_origin_node='node-13')
        sp=put(base/'SCOPE.json',scope)
        c=dict(node='node-15',role=role,registry=str(base/'registry'),scope=sp)
        cp=put(base/'CONFIG.json',c)
        hashes={n:foundation.pin(source/n,code=True)['sha256'] for n in producer_scientific.NAMES}
        sources={n:dict(path=remote+'/package/pricefm_hb/'+n,sha256=sha) for n,sha in hashes.items()}
        packet=dict(role=role,scope_id='UNIT_NONCANDIDATE',remote_root=remote,sources=sources,spec_sha256='7'*64,
            execution_node='node-15',qualification_route_id='a'*32)
        put(root/'PACKET.json',packet)
        producer_scientific.append(root,'PREPARED',packet=foundation.pin(root/'PACKET.json'))
        spec=dict(role=role,scope_id=packet['scope_id'],remote_root=remote,sources=sources,nonce='b'*32,
            scope=dict(path=remote+'/Q_SCOPE.json',sha256=sp['sha256']),
            node='node-15',qualification_route_id='a'*32,
            inputs={name:dict(path=remote+'/'+name,sha256=sha) for name,sha in contract.INPUT_HASHES.items()},
            science={'fixedpoint_helper.R':dict(path=remote+'/science/fixedpoint_helper.R',sha256=contract.FIXEDPOINT_SHA),
                'traced_guard.py':dict(path=remote+'/science/traced_guard.py',sha256=owner.TRACE_SHA),
                'boundary.so':dict(path=remote+'/science/boundary.so',sha256=owner.BOUNDARY_SHA)})
        helpers={n:dict(resolved_file=dict(path='/usr/bin/'+n,sha256='8'*64)) for n in ['which','uname','bash','sh','rm']}
        inventory=dict(node='node-15',job_id='123456789',qualification_route_id='a'*32,libc=dict(UNIT='same'),
            python=dict(path='/UNIT_PYTHON',sha256='9'*64),python_version='UNIT',uname=['Linux','node-15','UNIT','UNIT','x86_64'],
            helpers=helpers,affinity=[0],scheduler=dict(uid=os.getuid(),job_id='123456789',node='node-15',
                cpus=1,tasks=1,nodes=1,memory_MiB=8192,cgroup_memory_limit_bytes=8192*1024**2,requeue=False))
        spec['accepted_R_context']=dict(inventory=copy.deepcopy(inventory))
        (root/'packet').mkdir();put(root/'packet/SPEC.json',spec)
        ready=dict(status='READY_SOURCE_BOUND_COMPUTE_METADATA',role=role,scope_id=packet['scope_id'],sources=sources,
            spec_sha256=packet['spec_sha256'],job_id=inventory['job_id'],node='node-15',qualification_route_id='a'*32,
            affinity=[0],cpus_per_task=1,models=0,inventory=inventory,
            worker_identity=dict(uid=os.getuid(),pid=111,start_ticks=222,boot_id='a'*8+'-'+'b'*4+'-'+'c'*4+'-'+'d'*4+'-'+'e'*12,affinity=[0]))
        put(root/'READY.json',ready);job=dict(job_id=inventory['job_id'],scope_id=packet['scope_id']);put(root/'JOB.json',job)
        out=base/'bundle'
        with patch.object(producer_scientific,'load_config',return_value=(c,scope,{},hashes)):
            proposal=producer_scientific.prepare_release(cp['path'],str(out))
        for name,status in [('install_authority','ROOT_ADMITTED_NEW_SCIENTIFIC_CODE_NAMESPACE_ONLY'),
                            ('owner_authority','ROOT_ADMITTED_R179_SCIENTIFIC_METADATA_ONLY')]:
            value=json.loads((out/(name+'_TEMPLATE.json')).read_text());value.pop('required_status')
            value.update(status=status,issued_epoch=now,expires_epoch=now+1500)
            put(out/(name+'.json'),value)
        return c,scope,spec,packet,ready,job,out,installer,owner,contract
    def test_actual_scientific_preparation_then_independent_spec_authority_review(self):
        with tempfile.TemporaryDirectory(prefix='UNIT_SCI_RELEASE_') as name:
            args=self.fixture(Path(name));result=scientific.validate_scientific_bundle(*args)
            self.assertEqual(result[2]['install_CPU_seconds'],60)
    def test_foreign_route_old_R_context_wide_environment_and_component_repricing_rejected(self):
        for kind in ['route','old_R','environment','budget','root_source']:
            with tempfile.TemporaryDirectory(prefix='UNIT_SCI_RELEASE_') as name:
                args=list(self.fixture(Path(name)));c,s,spec,packet,ready,job,out=args[:7]
                if kind=='route':spec['qualification_route_id']='b'*32
                elif kind=='old_R':spec['accepted_R_context']['inventory']['node']='node-13'
                else:
                    filename='owner_spec.json' if kind=='environment' else 'owner_authority.json'
                    value=json.loads((out/filename).read_text())
                    if kind=='environment':value['environment']['OPENBLAS_NUM_THREADS']='2'
                    elif kind=='budget':value['owner_CPU_seconds']=451
                    else:value['sources']={}
                    put(out/filename,value)
                with self.subTest(kind=kind),self.assertRaises(ValueError):scientific.validate_scientific_bundle(*args)


if __name__=='__main__':unittest.main()

