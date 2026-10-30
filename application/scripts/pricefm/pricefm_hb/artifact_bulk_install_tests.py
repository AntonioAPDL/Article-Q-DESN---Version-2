"""Pure temporary fixture proofs; no actual spool, registry, SSH or jobs."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).parent
spec = importlib.util.spec_from_file_location('bulk_install', HERE / 'artifact_bulk_install.py')
b = importlib.util.module_from_spec(spec); spec.loader.exec_module(b)
r = b.frozen_recovery(dict(path=str(HERE / 'artifact_recovery.py'), sha256=b.RECOVERY_SHA))


class Journal:
    def __init__(self, root, records):
        self.root, self.items = root, records
    def records(self):
        return self.items
    def put(self, state, **values):
        self.items.append(dict(state=state, **values))


class SourceLoadingTests(unittest.TestCase):
    def test_exact_frozen_source_executes_hash_verified_bytes(self):
        module=b.frozen_recovery(dict(path=str(HERE/'artifact_recovery.py'),sha256=b.RECOVERY_SHA))
        self.assertEqual(module.pin(HERE/'artifact_recovery.py')['sha256'],b.RECOVERY_SHA)

    def test_wrong_source_never_executes(self):
        with tempfile.TemporaryDirectory(dir='/dev/shm') as root:
            path=Path(root)/'wrong.py';path.write_text('raise RuntimeError("must never execute")\n')
            with self.assertRaisesRegex(ValueError,'frozen recovery bytes'):
                b.frozen_recovery(dict(path=str(path),sha256=b.RECOVERY_SHA))


class BridgeTests(unittest.TestCase):
    def setUp(self):
        # Persistent staging on /data and memory input on tmpfs are distinct.
        parent = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_r165_headroom_execution_20261029_1526PDT/artifact_recovery_06/bulk_materialization_08/bridge_source')
        self.disk = tempfile.TemporaryDirectory(prefix='unit_', dir=parent); self.addCleanup(self.disk.cleanup)
        self.ram = tempfile.TemporaryDirectory(prefix='bulk_bridge_unit_', dir='/dev/shm'); self.addCleanup(self.ram.cleanup)
        self.t = Path(self.disk.name) / 'T'; self.t.mkdir()
        self.u = self.t / 'R/U'; self.u.mkdir(parents=True)
        self.root = self.t / 'R/operations' / b.SCOPE; self.root.mkdir(parents=True)
        self.canonical = self.t / 'canonical'; self.canonical.mkdir()
        (self.canonical / 'release').mkdir(); r.write_new(self.canonical / 'release/release_manifest.json', {})
        self.staging = self.root / 'attempt_08/decoded_raw'; self.staging.mkdir(parents=True)
        self.memory = Path(self.ram.name)
        for root in (self.staging, self.memory):
            (root / 'nested').mkdir()
            for name, raw in (('x', b'AA'), ('nested/y', b'BBB')):
                (root / name).write_bytes(raw); (root / name).chmod(0o600)
        self.counter = 0
        self.cfg = dict(root_scope=r.write_new(self.u / 'ROOT_SCOPE.json', {}), authority=self.pinjson({}),
                        bulk_config=self.pinjson({}), old_prepare_guard=self.pinjson({}), spool_guard=self.pinjson({}))
        sources = dict(artifact_bulk_materialize=self.pinjson({'dummy_source':True}), artifact_bulk_install=r.pin(HERE / 'artifact_bulk_install.py'))
        self.auth = dict(new_sources=sources,memory_root=str(self.memory),target_root=str(self.staging),receipt_dir=str(self.u))
        request = dict(path='/remote/metadata/request.json', sha256='a'*64)
        original_spec = self.pinjson({}); old_config = self.pinjson({})
        self.ctx = dict(root=self.root, canonical=self.canonical, config_pin=old_config,
            cfg=dict(scope_id=b.SCOPE, original_spec=original_spec, authority=self.pinjson({}),
                terminal_claim=r.write_new(self.canonical / 'record_0027.json', {'state':'TERMINAL_OBSERVED'}),
                old_tip=r.write_new(self.canonical / 'record_0034.json', {'state':'AMBIGUOUS_SPENT'})),
            spec=dict(request=request), claim=dict(job_id='123'))
        bindings = dict(spec=original_spec, request=request,
                        source_manifest=r.pin(self.canonical / 'release/release_manifest.json'))
        bank = self.t / 'R/bank'; bank.mkdir()
        (bank / 'wire.spool').write_bytes(b'owned synthetic wire metadata fixture')
        s = (bank / 'wire.spool').stat()
        wire = dict(path=str(bank / 'wire.spool'), sha256=r.digest(bank / 'wire.spool'), bytes=s.st_size,
                    identity=dict(device=s.st_dev,inode=s.st_ino,uid=s.st_uid,mode=s.st_mode),fingerprint=['synthetic'])
        self.spool = dict(wire=wire, bindings=bindings)
        self.cfg['spool_receipt'] = self.pinjson(self.spool)
        header = dict(schema='r164_exact_file_stream_v1', kind='directory', total_bytes=5,
            files=[dict(name=n,bytes=len(v),sha256=hashlib.sha256(v).hexdigest(),mode=0o600)
                   for n,v in [('nested/y',b'BBB'),('x',b'AA')]])
        h = hashlib.sha256(json.dumps(header,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        original = dict(files=2, bytes=5, manifest_sha256=h)
        base = dict(authority=self.cfg['authority'],producer_source=sources['artifact_bulk_materialize'],
                    config=self.cfg['bulk_config'],scope_id=b.SCOPE,job_id='123',bindings=bindings,
                    source_role='REAL_COMPLETED_SPOOL',source_receipt=self.cfg['spool_receipt'],
                    spool_receipt=self.cfg['spool_receipt'],wire=wire)
        memory = dict(base,schema='r173_memory_decode_receipt_v1',status='PASS_MEMORY_DECODE',completed=True,
            volatile=True,memory_root=str(self.memory),target_identity=self.identity(self.memory),
            memory_manifest=self.manifest(self.memory),original_receive_receipt=original)
        memory_pin = self.pinjson(memory)
        dirs = [str(self.staging),str(self.staging/'nested')]; p = self.staging.parent
        while True:
            dirs.append(str(p))
            if p == self.t:break
            p = p.parent
        bank_dirs=[];p=bank
        while True:
            bank_dirs.append(str(p))
            if p==self.t:break
            p=p.parent
        durable = dict(base,schema='r173_durable_materialization_receipt_v1',status='PASS_DURABLE_MATERIALIZATION',
            completed=True,memory_root=str(self.memory),memory_decode=memory_pin,target_root=str(self.staging),
            target_manifest=self.manifest(self.staging),files_fsynced=['nested/y','x'],directories_fsynced=dirs,
            all_writes_before_file_sync=True,durable_wire_source=dict(wire_file_fsynced=True,
                source_receipt_fsynced=True,source_role='REAL_COMPLETED_SPOOL',source_receipt=self.cfg['spool_receipt'],
                stable_anchor=str(self.t),wire_identity=wire['identity'],wire_fingerprint=wire['fingerprint'],directories_fsynced=bank_dirs))
        self.value = dict(base,schema='r173_bulk_materialization_result_v1',status='PASS_DURABLE_BULK_MATERIALIZATION',
            source_role='REAL_COMPLETED_SPOOL',source_receipt=self.cfg['spool_receipt'],scope_id=b.SCOPE,job_id='123',
            config=self.cfg['bulk_config'],bindings=bindings,spool_receipt=self.cfg['spool_receipt'],wire=wire,
            required_outer_guard=dict(cpu=20,wall=300),no_canonical_install=True,wire_manifest=header,
            wire_manifest_sha256=h,original_receive_receipt=original,memory_root=str(self.memory),target_root=str(self.staging),
            target_identity=self.identity(self.staging),target_manifest=self.manifest(self.staging),
            memory_decode=memory_pin,memory_decode_receipt=memory,durable_materialization=self.pinjson(durable),
            durable_materialization_receipt=durable)
        fixture_result=dict(status='PASS_DURABLE_BULK_MATERIALIZATION',source_role='SYNTHETIC_FIXTURE',
            producer_source=sources['artifact_bulk_materialize'],wire_manifest=header)
        self.cfg['source_review']=self.pinjson({});self.cfg['publication']=self.pinjson({})
        proof=dict(status='PASS_QUALIFIED_STRONG_BULK_ALGORITHM',purpose='SYNTHETIC_AVAILABILITY_ONLY_NO_REAL_PAYLOAD',
            bulk_helper_source=sources['artifact_bulk_materialize'],bulk_sources=sources,protocol=b.PROTOCOL,
            source_review=self.cfg['source_review'],publication=self.cfg['publication'],fixture_shape=b.manifest_shape(header),
            result=self.pinjson(fixture_result),guardian=self.pinjson(self.guard(fixture_result,20)))
        self.cfg['qualification']=self.pinjson(proof)
        self.bundle=dict(cfg=self.cfg,authority=self.auth,old=self.ctx,spool=self.spool,config_pin=self.pinjson({'bridge':'fixture'}))
        self.refresh()

    def pinjson(self,value):
        self.counter += 1
        return r.write_new(self.u / ('meta_%03d.json'%self.counter),value)

    @staticmethod
    def identity(path):
        s=path.stat();return dict(device=s.st_dev,inode=s.st_ino,uid=s.st_uid,mode=s.st_mode)

    @staticmethod
    def manifest(path):
        m=r.tree_manifest(path)
        for item in m['files'].values():item['uid']=os.getuid()
        return m

    @staticmethod
    def guard(value,cpu):
        return dict(returncode=0,command_returncode=0,all_owned_descendants_reaped=True,kernel_escape_filter=True,
            independent_guardian=True,CPU_limit=cpu,aggregate_CPU_seconds=.1,complete_lifecycle_wall_seconds=1,stdout=json.dumps(value))

    def refresh(self):
        self.value['memory_decode']=self.pinjson(self.value['memory_decode_receipt'])
        self.value['durable_materialization_receipt']['memory_decode']=self.value['memory_decode']
        self.value['durable_materialization']=self.pinjson(self.value['durable_materialization_receipt'])
        self.cfg['bulk_receipt']=self.pinjson(self.value)
        self.cfg['bulk_guard']=self.pinjson(self.guard(self.value,20))

    def test_typed_real_result_and_cross_filesystem_provenance(self):
        path,manifest=b.verify_bulk(r,self.bundle,self.value)
        self.assertEqual(path,self.staging);self.assertEqual(manifest['file_count'],2)
        self.assertNotEqual(self.memory.stat().st_dev,self.staging.stat().st_dev)

    def test_actual_target_must_match_explicit_authority(self):
        self.auth['target_root']=str(self.root/'other_attempt/decoded_raw')
        with self.assertRaisesRegex(ValueError,'reviewed authority'):b.verify_bulk(r,self.bundle,self.value)

    def test_old_decode_status_not_accepted(self):
        self.value['schema']='r165_artifact_spool_decode_receipt_v1';self.refresh()
        with self.assertRaisesRegex(ValueError,'new typed'):b.verify_bulk(r,self.bundle,self.value)

    def test_failed_outer_guard_rejected(self):
        proof=self.guard(self.value,20);proof['returncode']=125;self.cfg['bulk_guard']=self.pinjson(proof)
        with self.assertRaisesRegex(ValueError,'outer guardian'):b.verify_bulk(r,self.bundle,self.value)

    def test_wrong_outer_CPU_rejected(self):
        self.cfg['bulk_guard']=self.pinjson(self.guard(self.value,40))
        with self.assertRaisesRegex(ValueError,'outer guardian'):b.verify_bulk(r,self.bundle,self.value)

    def test_equal_size_raw_mutation_rejected(self):
        (self.staging/'x').write_bytes(b'ZZ')
        with self.assertRaisesRegex(ValueError,'bytes/mode'):b.verify_bulk(r,self.bundle,self.value)

    def test_missing_file_fsync_rejected(self):
        self.value['durable_materialization_receipt']['files_fsynced']=['x'];self.refresh()
        with self.assertRaisesRegex(ValueError,'own fsync'):b.verify_bulk(r,self.bundle,self.value)

    def test_missing_owned_directory_fsync_rejected(self):
        self.value['durable_materialization_receipt']['directories_fsynced'].remove(str(self.staging/'nested'));self.refresh()
        with self.assertRaisesRegex(ValueError,'owned directories'):b.verify_bulk(r,self.bundle,self.value)

    def test_missing_wire_ancestor_fsync_rejected(self):
        self.value['durable_materialization_receipt']['durable_wire_source']['directories_fsynced']=[];self.refresh()
        with self.assertRaisesRegex(ValueError,'wire bank'):b.verify_bulk(r,self.bundle,self.value)

    def test_weaker_write_order_not_accepted(self):
        self.value['durable_materialization_receipt']['all_writes_before_file_sync']=False;self.refresh()
        with self.assertRaisesRegex(ValueError,'bulk ordering'):b.verify_bulk(r,self.bundle,self.value)

    def test_qualification_must_cover_real_shape(self):
        proof=r.read(self.cfg['qualification']);proof['fixture_shape']['files']=1
        self.cfg['qualification']=self.pinjson(proof)
        with self.assertRaisesRegex(ValueError,'actual shape'):b.verify_bulk(r,self.bundle,self.value)

    def test_missing_actual_qualification_rejected(self):
        proof=r.read(self.cfg['qualification']);proof['status']='PREPARED_ONLY';self.cfg['qualification']=self.pinjson(proof)
        with self.assertRaisesRegex(ValueError,'qualification'):b.verify_bulk(r,self.bundle,self.value)

    def test_wrong_phase_or_fixture_substitution_rejected(self):
        self.value['source_role']='SYNTHETIC_FIXTURE';self.refresh()
        with self.assertRaisesRegex(ValueError,'new typed'):b.verify_bulk(r,self.bundle,self.value)

    def legacy(self):
        for path,count in ((self.canonical/'returned_raw',195),(self.root/'decoded_raw',508)):
            path.mkdir()
            for index in range(count):
                (path/('old_%04d.profile-part'%index)).write_bytes(b'partial')
        r.write_new(self.root/'CONFIG_PIN.json',self.ctx['config_pin'])
        self.old195=r.tree_manifest(self.canonical/'returned_raw');self.old508=r.tree_manifest(self.root/'decoded_raw')
        return Journal(self.canonical,[{} for _ in range(35)])

    def test_true_install_marker_matches_result_preserves_both_old_trees(self):
        j=self.legacy();result=b.install(r,self.bundle,self.value,j)
        self.assertEqual(result,r.read(r.pin(self.root/'install.done.json')))
        self.assertEqual(result['bridge_source'],r.pin(HERE/'artifact_bulk_install.py'))
        self.assertEqual(j.items[-1]['state'],'RECOVERY_PROVENANCE')
        r.same_tree(self.old195,r.tree_manifest(self.canonical/'returned_raw_recovery06_preserved'))
        r.same_tree(self.old508,r.tree_manifest(self.root/'decoded_raw'))
        with self.assertRaisesRegex(ValueError,'no automatic retry'):b.install(r,self.bundle,self.value,j)

    def test_gap_failure_preserves_all_bytes_and_latches(self):
        j=self.legacy();rename=r.no_replace_rename;count=[0]
        def fail_second(source,target):
            count[0]+=1
            if count[0]==2:raise OSError('fixture interruption')
            return rename(source,target)
        with patch.object(r,'no_replace_rename',fail_second):
            with self.assertRaises(OSError):b.install(r,self.bundle,self.value,j)
        self.assertFalse((self.canonical/'returned_raw').exists());self.assertTrue(self.staging.exists())
        r.same_tree(self.old195,r.tree_manifest(self.canonical/'returned_raw_recovery06_preserved'))
        r.same_tree(self.old508,r.tree_manifest(self.root/'decoded_raw'))
        with self.assertRaisesRegex(ValueError,'no automatic retry'):b.install(r,self.bundle,self.value,j)

    def test_changed_old_configuration_latches_before_mutation(self):
        j=self.legacy();(self.root/'CONFIG_PIN.json').write_text('{}')
        with self.assertRaisesRegex(ValueError,'CFG_PIN'):b.install(r,self.bundle,self.value,j)
        r.same_tree(self.old195,r.tree_manifest(self.canonical/'returned_raw'))

    def test_no_acceptance_network_or_old_install_entry(self):
        text=(HERE/'artifact_bulk_install.py').read_text()
        for forbidden in ('subprocess.','collect_run(','r.install_tree(','accepted.json','os.sync(','syncfs('):
            self.assertNotIn(forbidden,text)


if __name__=='__main__':unittest.main()
