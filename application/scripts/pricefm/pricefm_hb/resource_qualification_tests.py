"""Private metadata controller tests; no SSH, Slurm, arrays or real data."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import shutil
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('resource_qualification_under_test', Path(__file__).with_name('resource_qualification.py'))
q = importlib.util.module_from_spec(spec); spec.loader.exec_module(q)


def text_rows(state='COMPLETED', count=2, elapsed=30, cpu='00:00:00.500'):
    rows = []
    for i in range(count):
        key = '123_'+str(i); raw = str(123+i)
        steps = ('', '.batch', '.0') if state == 'COMPLETED' else ('',)
        for step in steps:
            rows.append('|'.join([key+step, raw+step, state, '0:0', str(elapsed), '1', cpu, '100K', 'node-13',
                '2026-10-29T01:00:00', '2026-10-29T01:00:30']))
    return '\n'.join(rows)+'\n'


class ControllerTests(unittest.TestCase):
    def test_pending_and_missing_worker_are_not_terminal_success(self):
        p = q.accounting(text_rows('PENDING', elapsed=0, cpu='00:00:00'), '123', 2)
        self.assertFalse(p['terminal']); self.assertFalse(p['complete'])
        self.assertFalse(q.accounting('', '123', 2)['terminal'])

    def test_success_accounts_primary_only(self):
        p = q.accounting(text_rows(), '123', 2)
        self.assertTrue(p['complete']); self.assertEqual(p['allocated_primary_CPU'], 1)
        self.assertEqual(p['allocated_primary_wall'], 60)

    def test_failed_before_worker_is_reconcilable(self):
        p = q.accounting(text_rows('FAILED'), '123', 2)
        self.assertTrue(p['terminal']); self.assertFalse(p['complete'])

    def test_cancelled_by_user_is_terminal(self):
        p = q.accounting(text_rows('CANCELLED by 1234'), '123', 2)
        self.assertTrue(p['terminal']); self.assertFalse(p['complete'])

    def test_resource_violation_retained_instead_of_hiding_failure(self):
        p = q.accounting(text_rows(elapsed=121), '123', 2)
        self.assertTrue(p['terminal']); self.assertFalse(p['complete']); self.assertTrue(p['scope_violations'])

    def test_foreign_accounting_row_rejected(self):
        with self.assertRaisesRegex(ValueError, 'foreign'):
            q.accounting(text_rows().replace('123_0|', '999_0|', 1), '123', 2)

    def test_grouped_pending_can_be_cancelled_but_never_accepted(self):
        row='123_[0-1]|123|PENDING|0:0|0|1|00:00:00||None|Unknown|Unknown\n'
        self.assertFalse(q.accounting(row,'123',2)['terminal'])
        value=q.accounting(row.replace('PENDING','CANCELLED by 123'),'123',2)
        self.assertTrue(value['terminal']);self.assertFalse(value['complete'])
        with self.assertRaises(ValueError):q.accounting(row.replace('PENDING','COMPLETED'),'123',2)

    def test_nan_or_negative_rss_is_retained_violation(self):
        for rss in ('nanK','-1K','5000000K'):
            parsed=q.accounting(text_rows().replace('100K',rss),'123',2)
            self.assertTrue(parsed['terminal']);self.assertFalse(parsed['complete']);self.assertTrue(parsed['scope_violations'])

    def test_submission_holds_limits_and_isolates_inherited_limits(self):
        c = dict(remote_root='/new', node='node-13', scope_id='scope', max_tasks=2, _sha256='sha')
        args = q.sbatch_args(c)
        for option in ('--hold', '--export=NONE', '--propagate=NONE', '--no-requeue', '--cpus-per-task=1', '--mem=4096M', '--time=00:02:00', '--array=0-1%2'):
            self.assertIn(option, args)
        self.assertEqual(args[-2:], ['/new', 'sha'])

    def test_ambiguous_job_reply_never_parsed_as_success(self):
        for reply in ('123\n124', 'submitted 123', '', '123;cluster\nextra'):
            with self.assertRaises(ValueError): q.job_id(reply)
        self.assertEqual(q.job_id('123;hummingbird\n'), '123')

    def test_dotdot_and_symlink_paths_rejected(self):
        with self.assertRaises(ValueError): q.physical(q.TRACK/'../outside')
        with tempfile.TemporaryDirectory() as t:
            p = Path(t); (p/'target').mkdir(); (p/'link').symlink_to(p/'target')
            with self.assertRaises(ValueError): q.physical(p/'link'/'new')

    def test_only_exact_wholly_pending_owned_array_can_be_cancelled(self):
        c = dict(scope_id='scope', remote_root='/new')
        line = 'JobId=123 JobName=scope WorkDir=/new UserId=jaguir26(1) JobState=PENDING'
        self.assertTrue(q.owned_pending(line, c, '123'))
        for old,new in [('JobName=scope','JobName=scope-foreign'),('WorkDir=/new','WorkDir=/other'),('JobState=PENDING','JobState=RUNNING'),('UserId=jaguir26','UserId=other')]:
            with self.assertRaises(ValueError): q.owned_pending(line.replace(old,new), c, '123')

    def test_budget_debits_before_io_and_cannot_retry_failed_stage(self):
        with tempfile.TemporaryDirectory() as t:
            a = dict(registry_path=str(Path(t)/'new.json'), allocated_CPU_cap=240, metadata_limit=13, transfer_limit=2)
            b = q.Budget(a, {'path':'authority','sha256':'sha'}, dict(max_tasks=2,scope_id='scope'))
            b.begin('stage')
            self.assertEqual(b.snapshot()['parent_reserved_CPU'], 8)
            self.assertEqual(b.snapshot()['control_CPU_reserved'], 90)
            with self.assertRaises(FileExistsError): b.begin('stage')
            for _ in range(13): b.operation('metadata')
            with self.assertRaises(ValueError): b.operation('metadata')
            self.assertEqual(b.snapshot()['counts']['metadata'], 13)

    def collection(self, root):
        for n in ('logs', 'results', 'rendezvous'): (root/n).mkdir()
        source = {}
        for n in ('resource_io_worker.py','run_io.sh'):
            data = n.encode(); (root/n).write_bytes(data); source[n] = dict(sha256=hashlib.sha256(data).hexdigest(), bytes=len(data))
        (root/'contract.json').write_text('{}'); (root/'authorization.json').write_text('{}')
        sha = q.pin(root/'contract.json')['sha256']; auth = q.pin(root/'authorization.json')['sha256']
        c = dict(_sha256=sha, source_files=source, max_tasks=2, scope_id='scope', node='node-13', remote_root='/new', tasks=[])
        for i in range(2):
            (root/'rendezvous'/('task_'+str(i)+'.ready.json')).write_text('{}')
            files = {'stage/opaque.bin': dict(sha256='a'*64,bytes=1)}
            c['tasks'].append(dict(study='FI' if i==0 else 'DK2', files=files))
            alloc = dict(job_id=str(123+i),array_task_id=i,array_job_id='123',array_task_count=2,node='node-13',user='jaguir26',cpus_per_task=1,memory_MiB=4096,affinity=[i],boot_id='boot',physical_core=dict(physical_package_id='0',core_id=str(i)))
            (root/'rendezvous'/('task_'+str(i)+'.ready.json')).write_text(json.dumps(dict(scope_id='scope',contract_sha256=sha,allocation=alloc)))
            phases = [dict(name=n,CPU=.1,wall=.2,started_epoch=1793235601,ended_epoch=1793235602,details=dict(files=1,bytes=1)) for n in ('source_hash','copy_to_scratch','scratch_hash')]
            value = dict(scope_id='scope',contract_sha256=sha,authorization_sha256=auth,allocation=alloc,status='OPAQUE_IO_COMPLETE_NO_SCIENTIFIC_SCALE_ADMISSION',purpose=q.PURPOSE,cache_state='UNKNOWN',source_files=source,new_model_fits=0,new_predictions=0,numerical_arrays_deserialized=0,scientific_scale_admitted=False,aggregate_CPU_seconds=.4,elapsed_seconds=3,peak_RSS_KiB=100,started_epoch=1793235600,ended_epoch=1793235603,study=c['tasks'][i]['study'],io=dict(files=1,total_bytes=1,source_immutable=True,scratch_cleanup='OWNED_TREE_REMOVED',cache_state='UNKNOWN',source_fingerprints=files,phases=phases))
            folder = root/'results'/('task_'+str(i)); folder.mkdir(); q.put(folder/'result.json',value)
            seal = dict(result_sha256=q.pin(folder/'result.json')['sha256'],task_id=i,status='COMPLETE_OPAQUE_IO_ONLY',scope_id='scope',contract_sha256=sha,authorization_sha256=auth,allocation=alloc,source_files=source)
            q.put(folder/'completed_evidence.json',seal)
        peers={str(i):json.loads((root/'rendezvous'/('task_'+str(i)+'.ready.json')).read_text()) for i in range(2)}
        for i in range(2):
            f=root/'results'/('task_'+str(i))/'result.json';v=json.loads(f.read_text());v['rendezvous']=dict(peers=peers);v['aggregate_scratch_floor']=dict(all_task_bytes=2,required_free_bytes=2**30+4,observed_free_bytes=2**31);f.write_text(json.dumps(v));e=f.parent/'completed_evidence.json';seal=json.loads(e.read_text());seal['result_sha256']=q.pin(f)['sha256'];e.write_text(json.dumps(seal))
        return c, dict(job_id='123',authorization_sha256=auth), q.accounting(text_rows(),'123',2)

    def test_valid_collection_binds_both_scheduler_raw_ids_and_all_files(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t); c,s,p=self.collection(root)
            self.assertEqual(len(q.verify_collection(root,c,s,p)),2)

    def test_resealed_foreign_numeric_job_id_is_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t); c,s,p=self.collection(root);f=root/'results/task_0/result.json';v=json.loads(f.read_text());v['allocation']['job_id']='999';f.write_text(json.dumps(v));e=f.parent/'completed_evidence.json';seal=json.loads(e.read_text());seal['allocation']=v['allocation'];seal['result_sha256']=q.pin(f)['sha256'];e.write_text(json.dumps(seal))
            ready=root/'rendezvous/task_0.ready.json';rv=json.loads(ready.read_text());rv['allocation']=v['allocation'];ready.write_text(json.dumps(rv))
            peers={str(i):json.loads((root/'rendezvous'/('task_'+str(i)+'.ready.json')).read_text()) for i in range(2)}
            for i in range(2):
                target=root/'results'/('task_'+str(i))/'result.json';item=json.loads(target.read_text());item['rendezvous']['peers']=peers;target.write_text(json.dumps(item));sp=target.parent/'completed_evidence.json';sv=json.loads(sp.read_text());sv['result_sha256']=q.pin(target)['sha256'];sp.write_text(json.dumps(sv))
            with self.assertRaisesRegex(ValueError,'raw job ID'): q.verify_collection(root,c,s,p)

    def test_stage_four_requires_canonical_accepted_two_stage_source_lineage(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);pub=root/'pub';pub.mkdir();c,s,p=self.collection(pub)
            old=dict(source_files=c['source_files'],tasks=c['tasks']);(pub/'contract.json').write_text(json.dumps(old))
            evidence=dict(status='COLLECTED_OPAQUE_IO_PROOF',accepted=True,task_count=2,parallel_opaque_IO_qualified=True,distinct_physical_cores=2,common_source_hash_overlap_seconds=.1,scientific_scale_admitted=False,contract_sha256=q.pin(pub/'contract.json')['sha256']);(pub/'collection.json').write_text(json.dumps(evidence))
            q.put(root/'r162_io_stage_2_20261028.claim.json',dict(scope_id='prior'));q.put(root/'prior.registry.json',dict(state='COLLECTED_OPAQUE_IO_PROOF',accepted=True,publication=str(pub)))
            four=dict(c,max_tasks=4,tasks=c['tasks']*2)
            with patch.object(q,'CENTRAL',root):
                q.predecessor_proof(dict(previous_qualification=q.pin(pub/'collection.json')),four)
                evidence['parallel_opaque_IO_qualified']=False;(pub/'collection.json').write_text(json.dumps(evidence))
                with self.assertRaises(ValueError):q.predecessor_proof(dict(previous_qualification=q.pin(pub/'collection.json')),four)

    def test_retrieved_source_or_extra_member_cannot_pass(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);c,s,p=self.collection(root);(root/'run_io.sh').write_text('changed')
            with self.assertRaises(ValueError):q.verify_collection(root,c,s,p)

    def test_full_finish_publishes_and_revalidates_local_receipt(self):
        with tempfile.TemporaryDirectory() as t:
            base=Path(t);payload=base/'payload';payload.mkdir();c,s,p=self.collection(payload)
            output=base/'output';output.mkdir();s.update(state='SUBMITTED',released_epoch=0)
            class FakeBudget:
                def snapshot(self):return s.copy()
                def update(self, fn):return fn(s)
            def fetch(b,site,source,target):shutil.copytree(payload,Path(target),dirs_exist_ok=True)
            with patch.object(q,'remote',side_effect=['',text_rows()]),patch.object(q,'transfer',side_effect=fetch):
                r=q.finish(FakeBudget(),dict(output_root=str(output)),c,dict(user='jaguir26',host='hb.ucsc.edu'))
            self.assertTrue(r['accepted']);self.assertTrue((output/'published/collection.json').exists())
            self.assertEqual(len(q.verify_collection(output/'published',c,s,p,collection_receipt=r)),2)

    def test_ambiguous_release_of_known_authorized_running_job_is_tracked(self):
        c=dict(scope_id='scope',remote_root='/new')
        info='JobId=123 JobName=scope WorkDir=/new UserId=jaguir26(1) JobState=RUNNING'
        self.assertEqual(q.owned_job(info,c,'123'),['RUNNING'])
        with self.assertRaises(ValueError):q.owned_pending(info,c,'123')


if __name__=='__main__': unittest.main()
