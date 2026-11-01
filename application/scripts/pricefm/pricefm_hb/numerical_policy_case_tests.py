"""Synthetic policy-token regressions; no Slurm query, R, target or grant.

The producer executes against mocked current-job facts and emits its normal
metadata. Both independent validators then consume that same metadata. The
uppercase singleton case reproduces the token/topology shape observed in the
failed closed job; it does not claim a new actual allocation or admission.
"""
import copy
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

from . import numerical_physical_admission as producer
from . import numerical_independent_peer as peer
from . import numerical_stage_tests as retained


class PolicyCaseTests(unittest.TestCase):
    def roundtrip(self,token,siblings,allocated=None):
        config,spec,template=retained.IndependentPhysicalFactsTests().fixture()
        old=template['physical_snapshot_value'];topology=dict(cpu=0,physical_package_id=0,core_id=0,thread_siblings=siblings)
        cpuset=dict(old['job_cpuset'],effective_cpus=siblings if allocated is None else allocated)
        records=copy.deepcopy(old['native_observations_value']['records'])
        for index,row in enumerate(records):
            row['identity'].update(pid=__import__('os').getpid()+100+index,start_ticks=101+index)
            if row['argv']==['/usr/bin/scontrol','show','config']:
                row['stdout']=row['stdout'].replace('CR_Core_Memory',token)
        native={tuple(row['argv']):row for row in records}
        original_read=Path.read_text
        def read_text(path,*args,**kwargs):
            if str(path)=='/sys/devices/system/cpu/online':return '0-63\n'
            return original_read(path,*args,**kwargs)
        with tempfile.TemporaryDirectory(prefix='pricefm_unit_r186_') as folder:
            root=Path(folder);filesystem=dict(old['filesystem'],path=str(root),observed_epoch=time.time())
            with patch.object(producer.os,'sched_getaffinity',return_value={0}),\
                 patch.object(producer.allocation,'live',return_value=old['scheduler']),\
                 patch.object(producer.allocation,'exact_cgroup',return_value=old['scheduler']['cgroups']),\
                 patch.object(producer,'observed_native',side_effect=lambda argv:copy.deepcopy(native[tuple(argv)])),\
                 patch.object(producer,'topology',return_value=topology),patch.object(producer,'job_cpuset',return_value=cpuset),\
                 patch.object(producer,'own_children',return_value=[]),patch.object(producer.h,'process_birth_ticks',return_value=100),\
                 patch.object(producer,'filesystem_facts',return_value=filesystem),patch.object(Path,'read_text',read_text):
                snapshot=producer.capture('123','node-13',config['known_prior_jobs'],root/'physical',disk_root=root)
                producer.h.write_new(root/'PHYSICAL_SNAPSHOT.json',snapshot);snapshot_pin=producer.h.pin(root/'PHYSICAL_SNAPSHOT.json')
                if token:self.assertEqual(snapshot['Slurm_core_policy']['SelectTypeParameters'],token)
                now=time.time();proof=dict(status='ROOT_ADMITTED_EXACT_SLURM_NUMERICAL_PHYSICAL_CORE',job_id='123',node='node-13',
                    uid=snapshot['uid'],affinity=[0],topology=topology,Slurm_core_policy=snapshot['Slurm_core_policy'],actual_snapshot=snapshot_pin,
                    all_SMT_siblings_reserved_to_this_job=True,unreviewed_numerical_peer_intersections=[],priority_drain_complete=True,
                    old_processes_signalled_or_peer_allowlist_broadened=False,issued_epoch=now-1,expires_epoch=now+300,**snapshot['witness_pins'])
                review=dict(status='PASS_REVIEWED_EXACT_SLURM_NUMERICAL_CORE_AND_PEER_DRAIN',job_id='123',node='node-13',topology=topology,
                    actual_snapshot=snapshot_pin,all_peer_and_drain_witnesses_bound=True,**snapshot['witness_pins'])
                ready=dict(job_id='123',node='node-13',affinity=[0],worker_identity=snapshot['supervisor'],
                    physical_snapshot_value=snapshot,physical_snapshot=snapshot_pin)
                outcomes=[]
                for check in [lambda:producer.validate(snapshot,proof,review,job_id='123',node='node-13',affinity=[0],now=now),
                              lambda:peer.physical_facts(config,dict(remote_root=str(root)),ready)]:
                    try:check();outcomes.append(True)
                    except ValueError:outcomes.append(False)
                return outcomes

    def test_observed_uppercase_CPU_MEMORY_singleton(self):
        self.assertEqual(self.roundtrip('CR_CPU_MEMORY',[0]),[True,True])

    def test_uppercase_CORE_MEMORY_complete_online_SMT(self):
        self.assertEqual(self.roundtrip('CR_CORE_MEMORY',[0,32]),[True,True])

    def test_prior_mixed_case_spellings_remain_compatible(self):
        for token,siblings in [('CR_CPU_Memory',[0]),('CR_Core_Memory',[0,32])]:
            with self.subTest(token=token):self.assertEqual(self.roundtrip(token,siblings),[True,True])

    def test_known_nonmemory_tokens_remain_compatible(self):
        for token,siblings in [('CR_CPU',[0]),('CR_Core',[0,32])]:
            with self.subTest(token=token):self.assertEqual(self.roundtrip(token,siblings),[True,True])

    def test_unknown_token_does_not_gain_admission(self):
        for token in ['CR_CPU_MEMORY_FAKE','CR_UNKNOWN','']:
            with self.subTest(token=token):self.assertEqual(self.roundtrip(token,[0]),[False,False])

    def test_CPU_MEMORY_with_multiple_SMT_siblings_stays_forbidden(self):
        self.assertEqual(self.roundtrip('CR_CPU_MEMORY',[0,32]),[False,False])

    def test_CORE_MEMORY_missing_reserved_online_sibling_stays_forbidden(self):
        self.assertEqual(self.roundtrip('CR_CORE_MEMORY',[0,32],allocated=[0]),[False,False])


if __name__=='__main__':unittest.main()
