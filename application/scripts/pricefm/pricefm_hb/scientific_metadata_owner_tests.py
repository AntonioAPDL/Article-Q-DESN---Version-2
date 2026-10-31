import unittest
from pathlib import Path
from unittest.mock import patch

from . import scientific_metadata_owner as m


class MetadataOwnerTests(unittest.TestCase):
    def fixture(self,role='SCIENTIFIC_NAMESPACE_NO_OPTIMIZER'):
        pins=[{'path':'/meta/'+x+'.json','sha256':str(i)*64} for i,x in enumerate(['spec','authority','review','ns'],1)]
        env={k:'x' for k in m.h.ENV_KEYS};env.update({k:'1' for k in m.h.THREAD_KEYS})
        env.update(TZ='UTC',SLURM_JOB_ID='999',SLURMD_NODENAME='node-13',SLURM_CPUS_PER_TASK='1',
                   R_HOME='/new/R_HOME',R_LIBS_USER='/new/R_HOME/library',R_LIBS_SITE='/new/R_HOME/library')
        spec={'schema':'r179_scientific_metadata_owner_spec_v1','role':role,'optimizer_invocations':0,'scientific_data_read':False,'models':0,
              'job_id':'999','node':'node-13','affinity':[0],'traced_guard':{'path':'/source/tracer.py','sha256':m.TRACE_SHA},
              'boundary_library':{'path':'/source/boundary.so','sha256':m.BOUNDARY_SHA},'R_native':{'path':'/new/R_HOME/bin/exec/R','sha256':m.ELF_SHA},
              'fixture':m.h.pin(Path(m.__file__).parent/m.ROLES.get(role,'scientific_namespace_fixture.R')),
              'namespace_spec':pins[3],'environment':env,'nonce':'a'*32}
        auth={'status':'ROOT_ADMITTED_R179_SCIENTIFIC_METADATA_ONLY','spec':pins[0],'sources':m.sources('SCIENTIFIC_NAMESPACE_NO_OPTIMIZER' if role not in m.ROLES else role),
              'memory_MiB':8192,'whole_CPU_seconds':600,'whole_wall_seconds':1200,'owner_CPU_seconds':550,'owner_wall_seconds':900,
              'max_calls':1,'issued_epoch':1,'expires_epoch':7000}
        review={'status':'PASS_REVIEWED_R179_SCIENTIFIC_METADATA_OWNER_AND_SPEC','spec':pins[0],'authority':pins[1],'sources':auth['sources']}
        ns={'job_id':'999','node':'node-13','affinity':[0],'schema':'r179_scientific_namespace_fixture_spec_v1','optimizer_invocations':0,
            'scientific_data_read':False,'library':'/new/R_HOME/library','scientific_boundary_library':spec['boundary_library'],
            'namespace_fixture':m.h.pin(Path(m.__file__).parent/'scientific_namespace_fixture.R')}
        return pins,[spec,auth,review,ns]

    def validate(self,rows):
        pins,_=self.fixture()
        with patch.object(m.h,'read',side_effect=rows),patch.object(m.h,'read_pin',return_value=b'opaque'):
            return m.validate(*pins[:3],now=100,environ={'SLURM_JOB_ID':'999','SLURMD_NODENAME':'node-13','SLURM_CPUS_PER_TASK':'1','TZ':'UTC'},affinity={0},node='node-13')

    def test_new_metadata_role_requires_exact_review_without_science(self):
        pins,rows=self.fixture();self.assertEqual(self.validate(rows)[0],rows[0])
        pins,rows=self.fixture();rows[2]['authority']={'path':'/other','sha256':'a'*64}
        with self.assertRaises(ValueError):self.validate(rows)

    def test_models_targets_and_numerical_roles_are_not_authorized(self):
        for key,value in [('models',1),('optimizer_invocations',1),('scientific_data_read',True),('role','TOY_PARITY')]:
            pins,rows=self.fixture();rows[0][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):self.validate(rows)

    def test_other_job_core_runtime_or_environment_fails(self):
        for key,value in [('job_id','1000'),('affinity',[30]),('R_native',{'path':'/new/R_HOME/bin/exec/R','sha256':'0'*64})]:
            pins,rows=self.fixture();rows[0][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):self.validate(rows)
        pins,rows=self.fixture();rows[0]['environment']['LD_PRELOAD']='/unreviewed.so'
        with self.assertRaises(ValueError):self.validate(rows)

    def guard(self):
        return {'schema':'r157_traced_bootstrap_guard_receipt_v1','status':'EXITED','returncode':0,'reaped':True,'drained':True,
                'CPU_accounting_complete':True,'all_newborns_kernel_traced_before_execution':True,'tracer_death_kernel_EXITKILL_enabled':True,
                'remaining_owned_lifetimes':[],'unexpected_untraced_child_waits':[]}

    def test_namespace_pass_cannot_substitute_for_boundary_pass(self):
        r=self.guard();m.accepted_guard(r,'SCIENTIFIC_NAMESPACE_NO_OPTIMIZER')
        with self.assertRaises(ValueError):m.accepted_guard(r,'SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER')
        r.update(postbootstrap_TSYNC_scientific_fork_denial=True,scientific_target_access_handshake=True,
                 scientific_filter_kernel_attestation={'operation':'SECCOMP_SET_MODE_FILTER','flags':'TSYNC','kernel_return':0})
        m.accepted_guard(r,'SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER')
        r['scientific_filter_kernel_attestation']['kernel_return']=-1
        with self.assertRaises(ValueError):m.accepted_guard(r,'SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER')

    def test_unreaped_or_untraced_receipt_cannot_pass(self):
        for key,value in [('reaped',False),('remaining_owned_lifetimes',[{'pid':1}]),('unexpected_untraced_child_waits',[1]),('returncode',125)]:
            r=self.guard();r[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):m.accepted_guard(r,'SCIENTIFIC_NAMESPACE_NO_OPTIMIZER')

    def test_unbounded_authority_or_bad_nonce_fails(self):
        pins,rows=self.fixture();rows[1]['expires_epoch']=float('inf')
        with self.assertRaises(ValueError):self.validate(rows)
        pins,rows=self.fixture();rows[0]['nonce']='not-a-valid-nonce'
        with self.assertRaises(ValueError):self.validate(rows)


if __name__=='__main__':unittest.main()
