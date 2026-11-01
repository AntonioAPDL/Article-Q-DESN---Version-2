"""Producer -> independently authored peer -> proposal, synthetic metadata only.

The native/provenance entry context is a temporary fixture. No fixture is a
published source approval, healthy native execution, or runtime proof.
"""
import copy,json,tempfile,time,unittest
from pathlib import Path
from unittest.mock import patch
from . import startup_helper as h
from . import startup_batch_stop as producer
from . import independent_foundation_release_peer as peer


def put(path,value):
    path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n');return h.pin(path)


class FoundationReleaseProposalTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='UNIT_FOUNDATION_RELEASE_');self.base=Path(self.temp.name)
    def tearDown(self):self.temp.cleanup()
    def fixture(self):
        now=time.time();role=producer.ROLES[0];root=self.base/'registry'/role;root.mkdir(parents=True)
        scope=dict(status='PROSPECTIVE_TWO_ROLE_HB_RUNTIME_QUALIFICATION_SCOPE',issued_epoch=now-10,expires_epoch=now+3600,
            allowed_metadata_output_root=str(self.base),execution_node='node-15',qualification_node='node-15',
            qualification_route_id='a'*32,cached_artifact_origin_node='node-13',maximum_jobs=2,compute_CPU_reservation=1200)
        scopepin=put(self.base/'SCOPE.json',scope);source=Path(producer.__file__).absolute().parent
        hashes={name:h.pin(source/name)['sha256'] for name in producer.NAMES}
        remote='/mnt/beegfs/home/jaguir26/pricefm_UNIT_NEVER_RUNTIME/role'
        sources={name:dict(path=remote+'/package/pricefm_hb/'+name,sha256=sha) for name,sha in hashes.items()}
        spec=dict(role=role,scope_id='UNIT_NEVER_RUNTIME',scope=dict(path=remote+'/Q_SCOPE.json',sha256=scopepin['sha256']),
            node='node-15',qualification_route_id='a'*32,remote_root=remote,sources=sources,expires_epoch=scope['expires_epoch'])
        (root/'packet').mkdir();specpin=put(root/'packet/SPEC.json',spec)
        packet=dict(role=role,scope_id=spec['scope_id'],remote_root=remote,execution_node='node-15',qualification_route_id='a'*32,
            sources=sources,spec_sha256=specpin['sha256'])
        packetpin=put(root/'PACKET.json',packet);producer.append(root,'PREPARED',packet=packetpin)
        job=dict(job_id='123456789',scope_id=spec['scope_id']);put(root/'JOB.json',job)
        ready=dict(status='READY_SOURCE_BOUND_COMPUTE_METADATA',role=role,scope_id=spec['scope_id'],job_id=job['job_id'],node='node-15',
            qualification_route_id='a'*32,spec_sha256=specpin['sha256'],sources=sources,affinity=[1],cpus_per_task=1,models=0,
            observed_epoch=now,carrier=None)
        put(root/'READY.json',ready)
        unit=put(self.base/'UNIT_SYNTHETIC_EVIDENCE.json',dict(synthetic_only=True))
        c=dict(node='node-15',scope=scopepin,registry=str(root.parent),source_dir=str(source),publication=unit,source_review=unit)
        cp=put(self.base/'CONFIG.json',c);pr=put(self.base/'PACKET_REVIEW.json',dict(synthetic_only=True));out=self.base/'release'
        ps=put(self.base/'PEER_SCOPE.json',dict(parent=scopepin,role=role,allocations=dict(independent_release_peer8=8),
            allowed_review_output_root=str(out),allowed_packet_review_output_root=str(self.base/'packet_review'),
            issued_epoch=now-1,expires_epoch=scope['expires_epoch']))
        return c,scope,source,hashes,root,packet,spec,job,ready,cp,pr,out,ps
    def actual_peer_bundle(self):
        c,s,source,hashes,root,p,spec,job,ready,cp,pr,out,ps=self.fixture()
        with patch.object(producer,'load_config',return_value=(c,s,{},hashes)):
            producer.prepare_foundation_release(cp['path'],str(out),producer.ROLES[0])
            context=(c,s,source,hashes,root,p,spec,job,ready,{})
            with patch.object(peer,'foundation_context',return_value=context):
                reviewed=peer.review_foundation(cp['path'],producer.ROLES[0],'/UNIT_SYNTHETIC_GUARD',pr['path'],ps,str(out),'release')
        return c,s,hashes,root,p,cp,out,reviewed
    def test_actual_producer_independent_peer_and_pin_map_proposal(self):
        c,s,hashes,root,p,cp,out,reviewed=self.actual_peer_bundle()
        self.assertEqual(reviewed['sources'],p['sources']);self.assertNotEqual(reviewed['sources'],hashes)
        with patch.object(producer,'load_config',return_value=(c,s,{},hashes)):
            result=producer.foundation_release_proposal(cp['path'],str(out),producer.ROLES[0])
        self.assertEqual(result['sources'],reviewed['sources'])
        self.assertEqual(result['independent_review'],dict(path=p['remote_root']+'/release/PEER_RELEASE.json',sha256=h.pin(out/'PEER_RELEASE.json')['sha256']))
        self.assertEqual(result['files'],[dict(relative='PEER_RELEASE.json',sha256=h.pin(out/'PEER_RELEASE.json')['sha256'])])
        self.assertFalse((out/'RELEASE.json').exists(),'proposal creates no root release or runtime acceptance')
    def test_foreign_source_node_route_job_READY_and_SPEC_review_splices_rejected(self):
        c,s,hashes,root,p,cp,out,reviewed=self.actual_peer_bundle()
        changed=[('sources',hashes),('node','node-13'),('qualification_route_id','b'*32),('job_id','987654321'),
                 ('ready_sha256','0'*64),('spec_sha256','0'*64),('role',producer.ROLES[1])]
        for key,value in changed:
            bad=copy.deepcopy(reviewed);bad[key]=value;put(out/'PEER_RELEASE.json',bad)
            with self.subTest(field=key),patch.object(producer,'load_config',return_value=(c,s,{},hashes)),self.assertRaises(ValueError):
                producer.foundation_release_proposal(cp['path'],str(out),producer.ROLES[0])

    def test_exact_R_actual_preparation_plan_peer_authority_peer_and_proposal(self):
        c,s,source,hashes,kroot,kp,kspec,kjob,kready,cp,pr,kout,ps=self.fixture()
        role=producer.ROLES[1];root=kroot.parent/role;root.mkdir();(root/'packet').mkdir()
        prior=dict(status='ACCEPTED_COMPLETE_STARTUP_BATCH_METADATA_ROLE',role=producer.ROLES[0],kernel_matrix_pass=True,
            job_id=kjob['job_id'],scope_id=kp['scope_id'],qualification_route_id=s['qualification_route_id'])
        put(kroot/'ACCEPTED.json',prior);producer.append(kroot,'ACCEPTED',accepted=h.pin(kroot/'ACCEPTED.json'))
        remote='/mnt/beegfs/home/jaguir26/pricefm_UNIT_NEVER_RUNTIME/R_role'
        sources={name:dict(path=remote+'/package/pricefm_hb/'+name,sha256=sha) for name,sha in hashes.items()}
        archive=self.base/'UNIT_code_carrier';archive.write_text('UNIT source bytes not executable\n');ap=h.pin(archive)
        native='9d76330f01cace4574a9ec7a5407ca50b9faacc9813bbf4339595582e5c33c27'
        manifest=dict(files=[dict(relative='R_HOME/bin/exec/R',bytes=100,mode=493,sha256=native)],total_bytes=100)
        mp=put(self.base/'R_MANIFEST.json',manifest)
        integrity=put(self.base/'R_INTEGRITY.json',dict(status='PASS_REVIEWED_STREAMING_RUNTIME_ARCHIVE_REAL_ARTIFACT',archive=ap,manifest=mp))
        c.update(carrier=ap,carrier_manifest=mp,carrier_integrity_review=integrity);cp=put(self.base/'R_CONFIG.json',c)
        spec=dict(schema='pricefm_startup_batch_spec_v1',role=role,scope_id='UNIT_R_NEVER_RUNTIME',remote_root=remote,
            scope=dict(path=remote+'/Q_SCOPE.json',sha256=c['scope']['sha256']),sources=sources,node='node-15',qualification_route_id=s['qualification_route_id'],
            aggregate_CPU_reservation=600,threads=1,memory_MiB=8192,expires_epoch=s['expires_epoch'],accepted_inventory=prior,
            carrier_manifest=mp,carrier=ap,cached_python='/UNIT_SOURCE_ONLY/python',cached_python_sha256='4'*64)
        specpin=put(root/'packet/SPEC.json',spec)
        packet=dict(role=role,scope_id=spec['scope_id'],remote_root=remote,execution_node='node-15',qualification_route_id=s['qualification_route_id'],
            sources=sources,spec_sha256=specpin['sha256'])
        pp=put(root/'PACKET.json',packet);producer.append(root,'PREPARED',packet=pp)
        job=dict(job_id='123456790',scope_id=spec['scope_id']);put(root/'JOB.json',job)
        inv=dict(status='COMPUTE_RUNTIME_FACTS_NO_R',job_id=job['job_id'],node='node-15',qualification_route_id=s['qualification_route_id'],
            affinity=[1],R_executions=0,python=dict(path=spec['cached_python'],sha256=spec['cached_python_sha256']),
            helpers={name:dict(logical_path='/usr/bin/'+name,resolved_file=dict(path='/usr/bin/'+name,sha256='6'*64),bytes=20) for name in ['which','uname']})
        ready=dict(status='READY_SOURCE_BOUND_COMPUTE_METADATA',role=role,scope_id=spec['scope_id'],job_id=job['job_id'],node='node-15',
            qualification_route_id=s['qualification_route_id'],spec_sha256=specpin['sha256'],sources=sources,affinity=[1],cpus_per_task=1,models=0,
            observed_epoch=time.time(),inventory=inv,carrier=dict(status='DURABLE_BYTE_IDENTICAL_RUNTIME_CARRIER_INSTALLED',root=remote+'/runtime_carrier',
                manifest=mp,files=[dict(path=remote+'/runtime_carrier/R_HOME/bin/exec/R',sha256=native)],file_count=1,total_bytes=100,
                all_writes_before_file_sync=True,no_original_runtime_mutation=True))
        put(root/'READY.json',ready);out=self.base/'R_release'
        ps=put(self.base/'R_PEER_SCOPE.json',dict(parent=c['scope'],role=role,allocations=dict(independent_release_peer8=8),
            allowed_review_output_root=str(out),allowed_packet_review_output_root=str(self.base/'R_packet_review'),
            issued_epoch=time.time()-1,expires_epoch=s['expires_epoch']))
        guard=put(self.base/'UNIT_READY_GUARD.json',dict(synthetic_only=True));context=(c,s,source,hashes,root,packet,spec,job,ready,dict(ready=guard))
        with patch.object(producer,'load_config',return_value=(c,s,{},hashes)),patch.object(producer,'validate_kernel_prerequisite'),\
             patch.object(peer,'foundation_context',return_value=context),patch.object(peer,'accepted_chain',return_value=(prior,{},{})):
            producer.prepare_foundation_release(cp['path'],str(out),role)
            child=json.loads((out/'R_CHILD_SCOPE_TEMPLATE.json').read_text());child.pop('required_issued_status')
            child.update(status='PROSPECTIVE_PRICEFM_STARTUP_COMPUTE_QUALIFICATION_SCOPE',issued_epoch=time.time());put(out/'R_CHILD_SCOPE.json',child)
            peer.review_foundation(cp['path'],role,guard['path'],pr['path'],ps,str(out),'plan')
            authority=json.loads((out/'R_AUTHORITY_TEMPLATE.json').read_text());authority['status']=authority.pop('required_status')
            authority.update(issued_epoch=time.time(),source_review=dict(path=remote+'/release/R_REVIEW.json',sha256=h.pin(out/'R_REVIEW.json')['sha256']),
                root_scope=dict(path=remote+'/release/R_CHILD_SCOPE.json',sha256=h.pin(out/'R_CHILD_SCOPE.json')['sha256']))
            put(out/'R_AUTHORITY.json',authority);peer.review_foundation(cp['path'],role,guard['path'],pr['path'],ps,str(out),'release')
            result=producer.foundation_release_proposal(cp['path'],str(out),role)
        self.assertEqual(result['sources'],sources);self.assertEqual(len(result['files']),5)
        self.assertFalse((out/'RELEASE.json').exists());self.assertEqual(result['startup_plan']['path'],remote+'/release/R_STARTUP_PLAN.json')
        reviewed=json.loads((out/'PEER_RELEASE.json').read_text())
        for field in ['path','sha256']:
            bad=copy.deepcopy(reviewed);name=next(iter(bad['sources']))
            bad['sources'][name][field]='/UNIT_FOREIGN/source.py' if field=='path' else '0'*64
            put(out/'PEER_RELEASE.json',bad)
            with self.subTest(source_field=field),patch.object(producer,'load_config',return_value=(c,s,{},hashes)),self.assertRaises(ValueError):
                producer.foundation_release_proposal(cp['path'],str(out),role)


if __name__=='__main__':unittest.main()
