#!/usr/bin/env python3
"""Metadata-only source/receipt gates; never execute R, targets or arrays."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
def load(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
oldtests=load('oldfinalizetests',HERE/'525_projection_validation_finalize_test.py')
final=oldtests.module;nr=final.native
AUDIT=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_r157_parallel_implementation_20261028/local')
NATIVE=nr.pin(AUDIT/'NATIVE_METADATA_01/owned_guard_receipt.json')

class NativeRuntime(unittest.TestCase):
 def fixture(self,root):
  cp,gp,rp,_=oldtests.Finalize().fixture(root)
  core,grant,guard=map(final.read,(cp,gp,rp))
  source=dict(kind='R154_project_fullstate_consumer_pinned_CRAN111',branch='work/pricefm-r157-native-bootstrap-fixture',head='a'*40)
  actual=nr.read(NATIVE)
  grant.update(schema='r157_projection_toy_grant_v1',source=source,native_metadata_proof_pin=NATIVE,boundary_library_pin=actual['boundary_library'],actual_R_runtime_binding=actual['actual_R_runtime_binding'],bootstrap_exec_allowlist=actual['bootstrap_executable_allowlist'])
  wrapper=nr.pin(nr.HERE/'527_project_bootstrap.R');grant['source_bindings'].append(wrapper)
  Path(gp['path']).write_text(json.dumps(grant));gp=nr.pin(gp['path'])
  core.update(source=source,root_grant_pin=gp,actual_R_runtime_binding=grant['actual_R_runtime_binding']);Path(cp['path']).write_text(json.dumps(core));cp=nr.pin(cp['path'])
  receipt=dict(actual,source=source,root_grant_sha256=gp['sha256'],actual_R_runtime_binding=grant['actual_R_runtime_binding'],launcher='pinned_native_ELF_no_Rscript_shell_wrapper',validation_kind='synthetic_project_projection_only',validation_core_pin=cp,entrypoint_pin=guard['entrypoint_pin'],wrapper_entrypoint_pin=wrapper)
  Path(rp['path']).write_text(json.dumps(receipt));rp=nr.pin(rp['path'])
  return cp,gp,rp,receipt
 def test_actual_metadata_proof_and_deployed_bootstrap_prefix_match(self):
  proof=nr.read(NATIVE)
  self.assertTrue(nr.completed(proof));nr.compatibility(NATIVE,proof['boundary_library'])
  self.assertEqual(proof['optimizer_invocations'],0);self.assertFalse(proof['numerical_parity_proved'])
 def test_new_finalizer_reports_truthful_boundary_and_requires_paid_accounting(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d)/'case';cp,gp,rp,_=self.fixture(root)
   v=final.read(final.finalize(cp,gp,rp,root/'result.json'))
   self.assertEqual(v['schema'],'r157_project_adapter_validation_v1')
   self.assertTrue(v['native_R_ELF_traced_bootstrap_scientific_filter_pass'])
   self.assertFalse(v['native_R_ELF_seccomp_startup_pass'])
   self.assertFalse(v['whole_startup_subprocess_creation_kernel_denied'])
   self.assertTrue(v['resource_accounting_required_before_production'])
 def test_old_whole_startup_receipt_cannot_validate_new_source(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d)/'case';cp,gp,rp,r=self.fixture(root)
   r.update(schema='r154_owned_stage_guard_receipt_v1',preexec_kernel_boundary_proved=True,subprocess_creation_kernel_denied=True)
   Path(rp['path']).write_text(json.dumps(r))
   with self.assertRaises(ValueError):final.finalize(cp,gp,nr.pin(rp['path']),root/'bad.json')
   self.assertFalse((root/'bad.json').exists())
 def test_each_kernel_proof_and_exact_BPF_are_mandatory(self):
  base=nr.read(NATIVE)
  cases=[(k,False) for k in nr.FLAGS]+[('whole_startup_subprocess_creation_kernel_denied',True),('bootstrap_subprocess_creation_allowed',False),('remaining_owned_lifetimes',[{'pid':1}]),('unexpected_untraced_child_waits',[1]),('CPU_accounting_basis','sum inclusive wait4 rows'),('child_tree_CPU_seconds',float('nan')),('child_tree_CPU_seconds',-1)]
  for key,value in cases:
   with self.subTest(key=key):
    changed=copy.deepcopy(base);changed[key]=value;self.assertFalse(nr.completed(changed))
  for key,value in [('program_sha256','0'*64),('instruction_count',1),('kernel_return',-1),('flags','0')]:
   with self.subTest(attestation=key):
    changed=copy.deepcopy(base);changed['scientific_filter_kernel_attestation'][key]=value;self.assertFalse(nr.completed(changed))
 def test_wrong_boundary_binary_is_rejected(self):
  proof=nr.read(NATIVE);bad=dict(proof['boundary_library'],sha256='0'*64)
  with self.assertRaises(ValueError):nr.compatibility(NATIVE,bad)
 def test_source_class_distinguishes_new_lineage(self):
  self.assertTrue(nr.new_source({'branch':'work/pricefm-r157-native-bootstrap-test'}))
  self.assertFalse(nr.new_source({'branch':'work/pricefm-r154-fullstate-pilot-adapter-test'}))
 def test_unowned_PID_cannot_be_added_to_peer_census(self):
  current=nr.traced.identity(os.getpid())
  with self.assertRaisesRegex(ValueError,'exact current kernel tracee'):
   nr.physical_peer_guard({'allowed_intersecting_processes':[]},Path('/tmp'),[current])
 def test_missing_handoff_authority_rejected_without_owner_creation(self):
  with self.assertRaisesRegex(ValueError,'root owner handoff'):nr._owner_package({})

class OwnerAdmission(unittest.TestCase):
 def setup_fixture(self,root,*,scope='r157-exact-toy-test'):
  def write(path,value):path.write_text(json.dumps(value));return nr.pin(path)
  owners=root/'owners';owners.mkdir()
  policy=write(root/'policy.json',{'owner_admission_dir':str(owners)})
  grant={'scope_id':scope,'owner_handoff':{'scope_id':scope,'policy_pin':policy,'source_bindings':[]}}
  gp=write(root/'grant.json',grant)
  admission={'scope_id':scope,'stage_grant':gp}
  path=owners/(scope+'.json');write(path,admission)
  # Only emulate the independently tested HB policy validator, never ownership
  # or the local canonical-path/scope/exact-grant checks under test.
  implementation=(SimpleNamespace(),SimpleNamespace(pinned=nr.read,validate_policy=lambda x:None,
      validate_owner_admission=lambda *a:None))
  return grant,gp,path,admission,implementation
 def test_publish_grant_then_canonical_admission_is_acyclic(self):
  with tempfile.TemporaryDirectory() as d:
   grant,gp,path,_,impl=self.setup_fixture(Path(d))
   before=Path(gp['path']).read_bytes()
   with patch.object(nr,'_owner_package',return_value=impl):_,pp,ap=nr.resolve_owner_admission(grant,gp)
   self.assertEqual(ap,nr.pin(path));self.assertEqual(pp,grant['owner_handoff']['policy_pin'])
   self.assertEqual(Path(gp['path']).read_bytes(),before)
   self.assertNotIn('owner_admission_pin',grant['owner_handoff'])
 def test_wrong_actual_grant_and_wrong_admission_stage_are_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   grant,gp,path,admission,impl=self.setup_fixture(Path(d))
   with patch.object(nr,'_owner_package',return_value=impl):
    with self.assertRaises(ValueError):nr.resolve_owner_admission(dict(grant,scope_id='different'),gp)
    admission['stage_grant']=dict(gp,sha256='0'*64);path.write_text(json.dumps(admission))
    with self.assertRaisesRegex(ValueError,'actual grant'):nr.resolve_owner_admission(grant,gp)
 def test_wrong_scope_circular_pin_or_path_override_rejected(self):
  for field,value in [('scope_id','different'),('scope_id','../escape'),('owner_admission_pin',{'path':'/wrong','sha256':'0'*64}),('owner_admission_path','/wrong')]:
   with self.subTest(field=field,value=value),tempfile.TemporaryDirectory() as d:
    grant,gp,path,admission,impl=self.setup_fixture(Path(d))
    grant['owner_handoff'][field]=value;Path(gp['path']).write_text(json.dumps(grant));gp=nr.pin(gp['path'])
    with patch.object(nr,'_owner_package',return_value=impl),self.assertRaises(ValueError):nr.resolve_owner_admission(grant,gp)
 def test_noncanonical_or_symlink_admission_never_used(self):
  with tempfile.TemporaryDirectory() as d:
   grant,gp,path,admission,impl=self.setup_fixture(Path(d))
   other=Path(d)/'elsewhere.json';path.rename(other)
   with patch.object(nr,'_owner_package',return_value=impl):
    with self.assertRaises(ValueError):nr.resolve_owner_admission(grant,gp)
    path.symlink_to(other)
    with self.assertRaises(ValueError):nr.resolve_owner_admission(grant,gp)
 def test_wrong_scope_inside_canonical_file_is_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   grant,gp,path,admission,impl=self.setup_fixture(Path(d));admission['scope_id']='r157-other-scope';path.write_text(json.dumps(admission))
   with patch.object(nr,'_owner_package',return_value=impl),self.assertRaisesRegex(ValueError,'another scope'):nr.resolve_owner_admission(grant,gp)

if __name__=='__main__':unittest.main(verbosity=2)
