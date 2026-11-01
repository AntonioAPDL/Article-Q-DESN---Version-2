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
            qualification_route_id='a'*32,cached_artifact_origin_node='node-13')
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
        for field in ['path','sha256']:
            bad=copy.deepcopy(reviewed);name=next(iter(bad['sources']))
            bad['sources'][name][field]='/UNIT_FOREIGN/source.py' if field=='path' else '0'*64
            put(out/'PEER_RELEASE.json',bad)
            with self.subTest(source_field=field),patch.object(producer,'load_config',return_value=(c,s,{},hashes)),self.assertRaises(ValueError):
                producer.foundation_release_proposal(cp['path'],str(out),producer.ROLES[0])


if __name__=='__main__':unittest.main()
