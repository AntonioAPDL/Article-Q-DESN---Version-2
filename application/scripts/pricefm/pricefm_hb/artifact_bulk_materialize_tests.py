"""Owned synthetic byte fixtures; no SSH, real spool, arrays or live helpers."""
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from pricefm_hb import profile_stream as s

_spec=importlib.util.spec_from_file_location('tested_bulk_materialize',Path(__file__).with_name('artifact_bulk_materialize.py'))
m=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(m)


class BulkTests(unittest.TestCase):
    def setUp(self):
        self.disk_tmp=tempfile.TemporaryDirectory(prefix='owned-unit-',dir=os.environ['PFM_BULK_TEST_DISK_ROOT'])
        self.disk=Path(self.disk_tmp.name)
        self.mem_tmp=tempfile.TemporaryDirectory(prefix='r173-owned-unit-',dir='/dev/shm');self.mem=Path(self.mem_tmp.name)
    def tearDown(self):self.mem_tmp.cleanup();self.disk_tmp.cleanup()
    def metadata(self,path,value):
        path.write_text(json.dumps(value,sort_keys=True));return m.pin(path)
    def source(self):
        root=self.mem/'source';root.mkdir();(root/'sub').mkdir();(root/'a.bin').write_bytes(b'owned\x00bytes\xff')
        (root/'sub/job.sh').write_bytes(b'#!/bin/sh\nexit 0\n');(root/'sub/job.sh').chmod(0o700)
        (root/'a.bin').chmod(0o600)
        value,_=s.manifest(root);return root,value
    def fixture(self,mutate=None,bad_hash=False):
        source,value=self.source();out=io.BytesIO();sent=s.send(source,out.write);raw=out.getvalue()
        if mutate:raw=mutate(raw)
        bank=self.disk/'bank';bank.mkdir();wire=bank/'wire.spool';wire.write_bytes(raw);before=s.regular(wire)
        binding=self.metadata(self.disk/'binding.json',{'owned_synthetic_fixture':True})
        bindings=dict(build_scope=binding,original_send=m.pin(Path(s.__file__)),manifest=binding)
        source_receipt=dict(schema='r173_synthetic_wire_source_v1',source_role='SYNTHETIC_FIXTURE',scope_id='r173-synthetic-unit',job_id=None,
            bindings=bindings,generated_from_owned_synthetic_bytes=True,original_send_receipt=sent,
            wire=dict(path=str(wire),bytes=len(raw),sha256='0'*64 if bad_hash else hashlib.sha256(raw).hexdigest(),identity=m.identity(before),fingerprint=list(s.fingerprint(before))))
        fixture_pin=self.metadata(bank/'fixture.json',source_receipt);auth=self.metadata(self.disk/'source_only_dummy_authority.json',{'unit_test_only':True})
        cfg=dict(schema='r173_bulk_materialize_task_v1',source_role='SYNTHETIC_FIXTURE',scope_id='r173-synthetic-unit',job_id=None,
            bindings=bindings,authority=auth,fixture_receipt=fixture_pin,memory_root=str(self.mem/'decoded'),target_root=str(self.disk/'decoded_raw'),stable_anchor=str(self.disk))
        config=self.disk/'config.json';self.metadata(config,cfg);return config,cfg,value
    def run_fixture(self,config):
        # Unit-only controlled authority/memory inputs, never a production grant.
        with patch.object(m,'validate_authority',return_value={'unit_only':True}),patch.object(m,'memory_headroom',return_value={'unit_only':True}):
            return m.bulk_materialize(config,self.disk/'receipts')
    def test_original_receive_then_durable_copy_typed_receipts(self):
        config,cfg,value=self.fixture();result=self.run_fixture(config)
        self.assertEqual(result['status'],'PASS_DURABLE_BULK_MATERIALIZATION');self.assertEqual(result['source_role'],'SYNTHETIC_FIXTURE')
        self.assertIsNone(result['spool_receipt']);self.assertIsNone(result['job_id']);self.assertTrue(result['no_canonical_install'])
        mem=result['memory_decode_receipt'];durable=result['durable_materialization_receipt']
        self.assertEqual(mem['schema'],'r173_memory_decode_receipt_v1');self.assertEqual(durable['schema'],'r173_durable_materialization_receipt_v1')
        self.assertNotEqual(mem['target_identity']['device'],durable['target_identity']['device'])
        self.assertNotEqual(mem['memory_root'],durable['target_root']);self.assertTrue(durable['completed'])
        self.assertEqual(len(durable['files_fsynced']),len(value['files']));self.assertTrue(durable['durable_wire_source']['source_receipt_fsynced'])
        for name,entry in result['target_manifest']['files'].items():
            self.assertEqual((self.disk/'decoded_raw'/name).read_bytes(),(self.mem/'source'/name).read_bytes())
            self.assertEqual(stat.S_IMODE((self.disk/'decoded_raw'/name).stat().st_mode),entry['mode'])
        self.assertEqual(m.read_pin(result['memory_decode']),mem);self.assertEqual(m.read_pin(result['durable_materialization']),durable)
    def test_all_writes_and_modes_precede_file_fsync_then_directories(self):
        source,value=self.source();target=self.disk/'decoded_raw';seen=[];original=m.os.fsync
        def check(fd):
            info=os.fstat(fd);path=Path(os.readlink('/proc/self/fd/'+str(fd)))
            if stat.S_ISREG(info.st_mode):
                for entry in value['files']:
                    candidate=target/entry['name'];self.assertTrue(candidate.exists());self.assertEqual(candidate.stat().st_size,entry['bytes']);self.assertEqual(stat.S_IMODE(candidate.stat().st_mode),entry['mode'])
                self.assertFalse(any(kind=='dir' for kind,_ in seen));seen.append(('file',str(path)))
            else:seen.append(('dir',str(path)))
            original(fd)
        with patch.object(m.os,'fsync',side_effect=check):manifest,files,dirs=m.materialize(source,target,value,self.disk)
        self.assertEqual(len([x for kind,x in seen if kind=='file']),2);self.assertEqual(len(files),2)
        self.assertEqual([len(Path(x).parts) for x in dirs],sorted([len(Path(x).parts) for x in dirs],reverse=True))
    def test_partial_payload_write_has_no_durable_claim(self):
        source,value=self.source();real=m.write_all
        def fail(f,block):f.write(block[:1]);raise OSError('owned injected partial write')
        with patch.object(m,'write_all',side_effect=fail),patch.object(m.os,'fsync') as sync:
            with self.assertRaises(OSError):m.materialize(source,self.disk/'decoded_raw',value,self.disk)
            sync.assert_not_called()
        self.assertTrue((self.disk/'decoded_raw/a.bin').exists())
    def test_durability_barrier_failure_no_success(self):
        config,_,_=self.fixture();real=m.materialize
        def fail(*args):
            with patch.object(m.os,'fsync',side_effect=OSError('owned sync failure')):return real(*args)
        with patch.object(m,'materialize',side_effect=fail):result=self.run_fixture(config)
        self.assertEqual(result['status'],'FAILED_BULK_MATERIALIZATION');self.assertNotIn('durable_materialization',result)
        self.assertIn('memory_decode',result)
    def test_wire_hash_failure_before_memory_allocation(self):
        config,_,_=self.fixture(bad_hash=True);result=self.run_fixture(config)
        self.assertEqual(result['status'],'FAILED_BULK_MATERIALIZATION');self.assertFalse((self.mem/'decoded').exists())
    def test_wire_trailer_failure_preserves_memory_partial(self):
        config,_,_=self.fixture(lambda raw:raw[:-1]+bytes([raw[-1]^1]));result=self.run_fixture(config)
        self.assertEqual(result['status'],'FAILED_BULK_MATERIALIZATION');self.assertNotIn('memory_decode',result)
        self.assertTrue(list((self.mem/'decoded').rglob('.*profile-part-*')))
    def test_wire_mutation_during_materialization_rejects_durable_receipt(self):
        config,cfg,_=self.fixture();wire=Path(m.read_pin(cfg['fixture_receipt'])['wire']['path']);real=m.materialize
        def mutate(*args):
            result=real(*args);raw=wire.read_bytes();wire.write_bytes(bytes([raw[0]^1])+raw[1:]);return result
        with patch.object(m,'materialize',side_effect=mutate):result=self.run_fixture(config)
        self.assertEqual(result['status'],'FAILED_BULK_MATERIALIZATION');self.assertNotIn('durable_materialization',result)
        self.assertIn('memory_decode',result)

    def test_stale_wire_identity_rejects(self):
        config,cfg,_=self.fixture();wire=Path(m.read_pin(cfg['fixture_receipt'])['wire']['path']);wire.write_bytes(wire.read_bytes())
        with self.assertRaises(ValueError):self.run_fixture(config)
    def test_source_hardlink_rejects(self):
        source,value=self.source();os.link(source/'a.bin',source/'linked')
        with self.assertRaises(ValueError):m.materialize(source,self.disk/'decoded_raw',value,self.disk)
    def test_source_symlink_rejects(self):
        source,value=self.source();(source/'a.bin').rename(source/'moved');(source/'a.bin').symlink_to('moved')
        with self.assertRaises(ValueError):m.materialize(source,self.disk/'decoded_raw',value,self.disk)
    def test_source_hash_and_mode_reject(self):
        source,value=self.source();(source/'a.bin').write_bytes(b'x'*len((source/'a.bin').read_bytes()))
        with self.assertRaises(ValueError):m.materialize(source,self.disk/'decoded_raw',value,self.disk)
        (source/'a.bin').chmod(0o700)
        with self.assertRaises(ValueError):m.materialize(source,self.disk/'another_raw',value,self.disk)
    def test_same_filesystem_source_target_reject(self):
        source,value=self.source()
        with self.assertRaises(ValueError):m.materialize(source,self.mem/'same_raw',value,self.disk)
    def test_no_overwrite_target_or_receipt(self):
        source,value=self.source();target=self.disk/'decoded_raw';target.mkdir();(target/'keep').write_bytes(b'keep')
        with self.assertRaises(FileExistsError):m.materialize(source,target,value,self.disk)
        self.assertEqual((target/'keep').read_bytes(),b'keep')
        with self.assertRaises(FileExistsError):m.new_directory(target)
    def test_ownership_and_anchor_reject(self):
        with patch.object(m.os,'getuid',return_value=os.getuid()+1):
            with self.assertRaises(ValueError):m.ancestors(self.disk,self.disk)
        with self.assertRaises(ValueError):m.ancestors(self.disk,self.mem)
    def test_low_memory_fails_before_allocation(self):
        with patch.object(m,'system_text',return_value='MemAvailable: 1 kB\n'):
            with self.assertRaises(ValueError):m.memory_headroom()
    def test_cgroup_ancestor_margin_reject(self):
        def system(path,limit=1024**2):
            if path=='/proc/self/cgroup':return '0::/owned\n'
            if path=='/proc/self/mountinfo':return '1 0 0:1 / /sys/fs/cgroup rw - cgroup2 cgroup rw\n'
            if path.endswith('memory.max'):return str(m.MEMORY_BUDGET)
            if path.endswith('memory.current'):return '1'
            raise AssertionError(path)
        with patch.object(m,'system_text',side_effect=system),patch.object(Path,'exists',return_value=True):
            with self.assertRaises(ValueError):m.cgroup_memory_margins()
    def test_cgroup_unlimited_and_finite_safe_parent(self):
        def system(path,limit=1024**2):
            if path=='/proc/self/cgroup':return '0::/owned\n'
            if path=='/proc/self/mountinfo':return '1 0 0:1 / /sys/fs/cgroup rw - cgroup2 cgroup rw\n'
            if path.endswith('/owned/memory.max'):return 'max'
            if path.endswith('memory.max'):return str(4*m.MEMORY_BUDGET)
            if path.endswith('memory.current'):return '1'
            raise AssertionError(path)
        with patch.object(m,'system_text',side_effect=system),patch.object(Path,'exists',return_value=True):rows=m.cgroup_memory_margins()
        self.assertEqual(len(rows),2);self.assertIsNone(rows[0]['limit']);self.assertGreater(rows[1]['margin'],2*m.MEMORY_BUDGET)
    def test_oversized_geometry_rejects(self):
        value=dict(schema='r164_exact_file_stream_v1',kind='directory',total_bytes=0,files=[dict(name=str(n),bytes=0,sha256=hashlib.sha256(b'').hexdigest(),mode=0o600) for n in range(521)])
        value['files'].sort(key=lambda x:x['name']);raw=json.dumps(value).encode();wire=io.BytesIO(s.MAGIC+len(raw).to_bytes(8,'big')+raw)
        with self.assertRaises(ValueError):m.wire_manifest(wire)
    def test_real_remote_and_python_source_binding_are_opaque(self):
        config,cfg,_=self.fixture();self.assertTrue(cfg['bindings']['original_send']['path'].endswith('.py'))
        cfg['bindings']['manifest']=dict(path='/mnt/beegfs/home/jaguir26/metadata/request.json',sha256='a'*64)
        src=m.read_pin(cfg['fixture_receipt']);src['bindings']=cfg['bindings'];cfg['fixture_receipt']=self.metadata(Path(cfg['fixture_receipt']['path']),src);self.metadata(config,cfg)
        result=self.run_fixture(config);self.assertEqual(result['status'],'PASS_DURABLE_BULK_MATERIALIZATION')
    def test_exact_real_remote_binding_shape_without_open(self):
        bindings={role:dict(path='/owned/'+role+'.json',sha256='a'*64) for role in ('spec','request','source_manifest')}
        bindings['request']['path']='/mnt/beegfs/home/jaguir26/metadata/request.json'
        with patch.object(m,'bounded_read',side_effect=AssertionError('opaque identity must not be opened')):
            m.validate_bindings('REAL_COMPLETED_SPOOL',bindings)
        for bad in ({},dict(bindings,other=bindings['spec'])):
            with self.assertRaises(ValueError):m.validate_bindings('REAL_COMPLETED_SPOOL',bad)

    def authority_case(self,role='SYNTHETIC_FIXTURE'):
        producer=dict(path='/owned/artifact_bulk_materialize.py',sha256='a'*64);receipt=dict(path='/owned/source.json',sha256='b'*64)
        cfg=dict(source_role=role,scope_id='unit',job_id=None,bindings={},memory_root='/dev/shm/owned',target_root='/owned/decoded_raw',stable_anchor='/owned',authority={'path':'authority','sha256':'c'*64})
        cfg['fixture_receipt' if role=='SYNTHETIC_FIXTURE' else 'spool_receipt']=receipt
        auth=dict(schema='r173_bulk_operation_authority_v1',status='ROOT_AUTHORIZED_SYNTHETIC_BULK_QUALIFICATION' if role=='SYNTHETIC_FIXTURE' else 'ROOT_AUTHORIZED_STRONG_BULK_ARTIFACT_RECOVERY',
            **{k:cfg[k] for k in ('source_role','scope_id','job_id','bindings','memory_root','target_root','stable_anchor')},source_receipt=receipt,receipt_dir='/owned/receipts',producer_source=producer,
            cpu_seconds=20,wall_seconds=300,wire_limit_bytes=m.WIRE_LIMIT,memory_budget_bytes=m.MEMORY_BUDGET,expires_epoch=m.ENDPOINT,no_guard_or_cap_changes=True,strong_raw_durability=True,
            root_scope={'path':'root','sha256':m.ROOT_SCOPE_SHA},source_review={'path':'review'},publication={'path':'pub'},synthetic_qualification=None if role=='SYNTHETIC_FIXTURE' else {'path':'qual'})
        docs={'authority':auth,'root':{'expires_epoch':m.ENDPOINT},'review':{'status':'PASS_REVIEWED_DURABLE_BULK_SOURCES','bulk_sources':{'artifact_bulk_materialize':producer}},
            'pub':{'status':'VERIFIED_FEATURE_PUBLICATION','bulk_sources':{'artifact_bulk_materialize':producer},'fresh_remote_hash_verified':True,'all_37_fetched_source_bytes_verified':True},'qual':{'status':'PASS_QUALIFIED_STRONG_BULK_ALGORITHM','bulk_helper_source':producer}}
        return cfg,producer,docs
    def test_exact_authority_and_gates(self):
        for role in ('SYNTHETIC_FIXTURE','REAL_COMPLETED_SPOOL'):
            cfg,producer,docs=self.authority_case(role)
            with patch.object(m,'read_pin',side_effect=lambda p:docs[p['path']]),patch.object(m.time,'time',return_value=m.ENDPOINT-1000):self.assertEqual(m.validate_authority(cfg,'/owned/receipts',producer),docs['authority'])
    def test_authority_wrong_role_cap_source_expiry_or_missing_gate_rejects(self):
        changes=[('status','ROOT_ALLOCATED_NEW_DISTINCT_CHILD'),('source_role','wrong'),('cpu_seconds',21),('wall_seconds',True),('strong_raw_durability',False),('producer_source',{'path':'wrong','sha256':'a'*64}),('expires_epoch',m.ENDPOINT+1)]
        for key,value in changes:
            cfg,producer,docs=self.authority_case();docs['authority'][key]=value
            with patch.object(m,'read_pin',side_effect=lambda p:docs[p['path']]),patch.object(m.time,'time',return_value=m.ENDPOINT-1000):
                with self.assertRaises(ValueError):m.validate_authority(cfg,'/owned/receipts',producer)
        for gate,key in [('review','status'),('pub','all_37_fetched_source_bytes_verified'),('qual','status')]:
            cfg,producer,docs=self.authority_case('REAL_COMPLETED_SPOOL');docs[gate].pop(key)
            with patch.object(m,'read_pin',side_effect=lambda p:docs[p['path']]),patch.object(m.time,'time',return_value=m.ENDPOINT-1000):
                with self.assertRaises(ValueError):m.validate_authority(cfg,'/owned/receipts',producer)
        cfg,producer,docs=self.authority_case()
        with patch.object(m,'read_pin',side_effect=lambda p:docs[p['path']]),patch.object(m.time,'time',return_value=m.ENDPOINT-299):
            with self.assertRaises(ValueError):m.validate_authority(cfg,'/owned/receipts',producer)


if __name__=='__main__':unittest.main()
