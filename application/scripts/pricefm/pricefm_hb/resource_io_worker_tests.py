"""Private tiny opaque fixtures; no cluster, retained input or numerical access."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest import mock

spec=importlib.util.spec_from_file_location('resource_io_worker',Path(__file__).with_name('resource_io_worker.py'))
w=importlib.util.module_from_spec(spec);spec.loader.exec_module(w)


class WorkerTests(unittest.TestCase):
    def test_shared_scratch_floor_covers_all_four_simultaneous_copies(self):
        with tempfile.TemporaryDirectory() as td:
            contract=dict(tasks=[dict(files={'stage/file.bin':dict(bytes=600000000)}) for _ in range(4)])
            disk=type('Disk',(),{'free':2*600000000+1024**3})()
            with mock.patch.object(w.shutil,'disk_usage',return_value=disk):
                with self.assertRaisesRegex(w.QualificationError,'aggregate scratch'):w.aggregate_scratch_floor(contract,td)
            disk.free=2*4*600000000+1024**3
            with mock.patch.object(w.shutil,'disk_usage',return_value=disk):
                self.assertEqual(w.aggregate_scratch_floor(contract,td)['all_task_bytes'],2400000000)

    def contract(self, base, n=2):
        source=Path(w.__file__).read_bytes();(base/'resource_io_worker.py').write_bytes(source);(base/'run_io.sh').write_bytes(b'#!/bin/sh\n')
        files={}
        for study,(count,total) in w.COUNTS.items():
            files[study]={('stage/private_'+str(i)+'.bin'):dict(bytes=1,sha256='a'*64) for i in range(count)}
            files[study]['stage/private_0.bin']['bytes']=total-count+1
        now=time.time();c=dict(schema=w.SCHEMA,purpose=w.PURPOSE,scope_id='r162_io_'+'a'*32,created_epoch=now-1,expires_epoch=now+600,
            remote_root=str(w.BASE/('r162_io_'+'a'*32)),node='node-13',account='128x24',partition='128x24',qos='normal',resources=dict(w.RESOURCES),max_tasks=n,max_concurrent=n,
            source_files={name:dict(bytes=(base/name).stat().st_size,sha256=hashlib.sha256((base/name).read_bytes()).hexdigest()) for name in w.SOURCE_NAMES},
            tasks=[dict(task_id=i,study='FI' if i%2==0 else 'DK2',retained_root=str(w.RETAINED['FI' if i%2==0 else 'DK2']),files=copy.deepcopy(files['FI' if i%2==0 else 'DK2'])) for i in range(n)])
        return c
    def validate(self,c,base):
        (base/'contract.json').write_text(json.dumps(c,sort_keys=True));sha=hashlib.sha256((base/'contract.json').read_bytes()).hexdigest()
        return w.validate_contract(c,sha,base)
    def private_task(self,base):
        retained=base/'retained';(retained/'stage').mkdir(parents=True);data=b'\x00opaque\xffbytes\x01'*100
        (retained/'stage/opaque.bin').write_bytes(data);scratch=base/'scratch';scratch.mkdir()
        return dict(task_id=0,retained_root=str(retained),files={'stage/opaque.bin':dict(bytes=len(data),sha256=hashlib.sha256(data).hexdigest())}),scratch

    def test_explicit_two_and_four_supported(self):
        for n in (2,4):
            with tempfile.TemporaryDirectory() as td:
                base=Path(td);c=self.contract(base,n);self.assertEqual(self.validate(c,base)['max_tasks'],n)
    def test_wrong_task_counts_ids_and_alternation_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            b=Path(td);original=self.contract(b)
            for change in ('count','id','study','concurrent'):
                c=copy.deepcopy(original)
                if change=='count':c['tasks'].pop()
                elif change=='id':c['tasks'][1]['task_id']=0
                elif change=='study':c['tasks'][1]['study']='FI'
                else:c['max_concurrent']=4
                with self.assertRaises(w.QualificationError):self.validate(c,b)
    def test_expiry_and_wrong_resource_types_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            b=Path(td);original=self.contract(b)
            for change in ('expired','duration','boolean','memory'):
                c=copy.deepcopy(original)
                if change=='expired':c['expires_epoch']=time.time()-1
                elif change=='duration':c['expires_epoch']=c['created_epoch']+1801
                elif change=='boolean':c['resources']['cpus']=True
                else:c['resources']['memory_MiB']=8192
                with self.assertRaises(w.QualificationError):self.validate(c,b)
    def test_partial_original_manifest_and_source_change_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            b=Path(td);c=self.contract(b);c['tasks'][0]['files'].popitem()
            with self.assertRaises(w.QualificationError):self.validate(c,b)
            c=self.contract(b);(b/'run_io.sh').write_text('changed')
            with self.assertRaises(w.QualificationError):self.validate(c,b)
    def test_wrong_contract_hash_and_source_membership_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            b=Path(td);c=self.contract(b);self.validate(c,b)
            with self.assertRaises(w.QualificationError):w.validate_contract(c,'0'*64,b)
            (b/'unexpected.txt').write_text('unexpected')
            with self.assertRaises(w.QualificationError):self.validate(c,b)
    def test_unsafe_member_paths_rejected(self):
        for name in ('../old.bin','/old.bin','stage/../old.bin','stage//old.bin','stage/./old.bin','other/a.bin','stage/a\nbin','stage\\x.bin'):
            with self.assertRaises(w.QualificationError):w.relative(name)
    def test_success_source_immutable_only_owned_scratch_removed(self):
        with tempfile.TemporaryDirectory() as td:
            b=Path(td);task,scratch=self.private_task(b);src=Path(task['retained_root'])/'stage/opaque.bin';before=(src.read_bytes(),w.fingerprint(src),src.stat().st_mode)
            unrelated=scratch/'unrelated';unrelated.mkdir();(unrelated/'keep').write_text('keep')
            r=w.execute_io(task,scratch)
            self.assertEqual((src.read_bytes(),w.fingerprint(src),src.stat().st_mode),before)
            self.assertEqual([p['name'] for p in r['phases']],['source_hash','copy_to_scratch','scratch_hash'])
            self.assertEqual(r['cache_state'],'UNKNOWN');self.assertFalse(Path(r['scratch_path']).exists());self.assertTrue((unrelated/'keep').exists())
    def test_corrupt_source_never_creates_scratch(self):
        with tempfile.TemporaryDirectory() as td:
            task,scratch=self.private_task(Path(td));(Path(task['retained_root'])/'stage/opaque.bin').write_bytes(b'bad')
            with self.assertRaises(w.QualificationError):w.execute_io(task,scratch)
            self.assertEqual(list(scratch.iterdir()),[])
    def test_scratch_corruption_retains_failure_without_touching_source(self):
        with tempfile.TemporaryDirectory() as td:
            task,scratch=self.private_task(Path(td));src=Path(task['retained_root'])/'stage/opaque.bin';sha=hashlib.sha256(src.read_bytes()).hexdigest()
            with self.assertRaisesRegex(w.QualificationError,'scratch retained'):
                w.execute_io(task,scratch,phase_hook=lambda root:(root/'stage/opaque.bin').write_bytes(b'bad'))
            self.assertEqual(hashlib.sha256(src.read_bytes()).hexdigest(),sha);self.assertTrue(list(scratch.iterdir()))
    def test_source_symlink_or_extra_member_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            task,scratch=self.private_task(Path(td));stage=Path(task['retained_root'])/'stage';(stage/'alias.bin').symlink_to(stage/'opaque.bin')
            with self.assertRaisesRegex(w.QualificationError,'symlink'):w.execute_io(task,scratch)
            (stage/'alias.bin').unlink();(stage/'extra.bin').write_bytes(b'extra')
            with self.assertRaisesRegex(w.QualificationError,'membership'):w.execute_io(task,scratch)
    def test_unsafe_scratch_parent_and_insufficient_space_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            task,scratch=self.private_task(Path(td))
            with self.assertRaises(w.QualificationError):w.execute_io(task,Path(task['retained_root'])/'stage')
            with mock.patch.object(w.shutil,'disk_usage',return_value=type('U',(),{'free':0})()):
                with self.assertRaisesRegex(w.QualificationError,'disk floor'):w.execute_io(task,scratch)
    def test_budget_guard_stops_before_stream_and_preserves_inputs(self):
        with tempfile.TemporaryDirectory() as td:
            task,scratch=self.private_task(Path(td))
            def stop():raise w.QualificationError('test budget exhausted')
            with self.assertRaisesRegex(w.QualificationError,'budget'):w.execute_io(task,scratch,check=stop)
            self.assertEqual(list(scratch.iterdir()),[])
    def test_atomic_metadata_never_overwrites(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'result.json';w.atomic_new(p,{'original':1})
            with self.assertRaises(FileExistsError):w.atomic_new(p,{'replacement':2})
            self.assertEqual(json.loads(p.read_text()),{'original':1})
    def test_postheld_authority_binds_job_source_resources_and_whole_clock(self):
        with tempfile.TemporaryDirectory() as td:
            c=self.contract(Path(td));now=time.time();sha='b'*64;context=dict(array_job_id='123')
            auth=dict(schema='r162_io_job_authorization_v1',status='ROOT_AUTHORIZED_OPAQUE_IO_QUALIFICATION',scope_id=c['scope_id'],contract_sha256=sha,slurm_array_job_id='123',resources=dict(c['resources']),max_tasks=2,max_concurrent=2,source_files=c['source_files'],created_epoch=now-1,expires_epoch=now+300,scientific_scale_admitted=False,new_model_fits=0)
            self.assertEqual(w.validate_authorization(auth,c,sha,context,now=now),auth)
            for key,value in (('slurm_array_job_id','456'),('expires_epoch',now+119),('scientific_scale_admitted',True),('max_concurrent',4)):
                bad=copy.deepcopy(auth);bad[key]=value
                with self.assertRaises(w.QualificationError):w.validate_authorization(bad,c,sha,context,now=now)
    def test_wrong_actual_allocation_rejected_before_io(self):
        with tempfile.TemporaryDirectory() as td:
            c=self.contract(Path(td));env=dict(SLURMD_NODENAME='node-13',SLURM_CPUS_PER_TASK='1',SLURM_MEM_PER_NODE='4096',SLURM_NTASKS='1',SLURM_ARRAY_JOB_ID='123',SLURM_ARRAY_TASK_ID='1',SLURM_ARRAY_TASK_COUNT='2',SLURM_JOB_ID='123_1')
            with mock.patch.object(w.socket,'gethostname',return_value='node-13'),mock.patch.object(w.pwd,'getpwuid',return_value=type('P',(),{'pw_name':'jaguir26'})()),mock.patch.object(w.os,'sched_getaffinity',return_value={31}):
                self.assertEqual(w.allocation(c,env)['array_task_id'],1)
                for key,value in (('SLURM_CPUS_PER_TASK','2'),('SLURM_MEM_PER_NODE','512'),('SLURM_ARRAY_TASK_COUNT','4'),('SLURM_JOB_ID','123_0')):
                    bad=dict(env);bad[key]=value
                    with self.assertRaises(w.QualificationError):w.allocation(c,bad)
    def test_rendezvous_observes_matching_peers_and_rejects_wrong_array(self):
        for wrong in (False,True):
            with tempfile.TemporaryDirectory() as td:
                root=Path(td);(root/'rendezvous').mkdir();contract=dict(remote_root=str(root),scope_id='private',max_tasks=2)
                context=dict(array_task_id=0,array_job_id='123',node='node-13',uid=w.os.getuid(),array_task_count=2,cpus_per_task=1,memory_MiB=4096)
                peer=dict(context,array_task_id=1,array_job_id='999' if wrong else '123')
                w.atomic_new(root/'rendezvous/task_1.ready.json',dict(schema=w.SCHEMA,purpose=w.PURPOSE,scope_id='private',contract_sha256='a'*64,created_epoch=time.time(),allocation=peer))
                if wrong:
                    with self.assertRaisesRegex(w.QualificationError,'identity'):w.rendezvous(contract,context,'a'*64,lambda:None)
                else:self.assertEqual(len(w.rendezvous(contract,context,'a'*64,lambda:None)['peers']),2)
    def test_rendezvous_finite_timeout_and_limit_checks(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);contract=dict(remote_root=str(root),scope_id='private',max_tasks=2)
            context=dict(array_task_id=0,array_job_id='123',node='node-13',uid=w.os.getuid(),array_task_count=2,cpus_per_task=1,memory_MiB=4096)
            base=w.IMPORT_MONOTONIC+1
            with mock.patch.object(w.time,'monotonic',side_effect=[base,base+16]):
                with self.assertRaisesRegex(w.QualificationError,'rendezvous'):w.rendezvous(contract,context,'a'*64,lambda:None)
        limit=w.Limit(time.time()+300)
        with mock.patch.object(w.time,'monotonic',return_value=limit.deadline+1):
            with self.assertRaises(w.QualificationError):limit.check()
        with mock.patch.object(w.resource,'getrusage',return_value=(100.,0.)):
            with self.assertRaises(w.QualificationError):limit.check()


if __name__=='__main__':unittest.main()
