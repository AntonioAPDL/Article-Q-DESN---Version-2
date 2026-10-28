#!/usr/bin/env python3
"""Real-kernel disposable Python tree tests; zero R/optimizer/target calls."""
import ctypes
import datetime as dt
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT=Path(__file__).resolve().parents[2];HERE=ROOT/'application/scripts/pricefm'
spec=importlib.util.spec_from_file_location('traced',HERE/'526_traced_bootstrap_guard.py')
g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
PY='/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python'
PYEXE=str(Path(PY).resolve());OLD=str(HERE/'525_owned_stage_guard.py')

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()

HANDSHAKE="""
import importlib.util
spec=importlib.util.spec_from_file_location('traced',NEW)
new=importlib.util.module_from_spec(spec);spec.loader.exec_module(new)
class I(ctypes.Structure): _fields_=[('code',ctypes.c_ushort),('jt',ctypes.c_ubyte),('jf',ctypes.c_ubyte),('k',ctypes.c_uint32)]
class P(ctypes.Structure): _fields_=[('length',ctypes.c_ushort),('filter',ctypes.POINTER(I))]
rows=new.scientific_filter_rows();table=(I*len(rows))(*(I(*r) for r in rows));program=P(len(rows),table)
l=ctypes.CDLL(None,use_errno=True)
assert l.syscall(317,1,1,ctypes.byref(program))==0,ctypes.get_errno()
os.write(int(os.environ['R157_FILTER_PROOF_FD']),os.environ['R157_FILTER_TOKEN'].encode())
os.close(int(os.environ['R157_FILTER_PROOF_FD']))
assert os.read(int(os.environ['R157_FILTER_ACK_FD']),1)==b'1'
os.close(int(os.environ['R157_FILTER_ACK_FD']))
"""

class TracedGuardTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.d=Path(self.temp.name)
  self.fd=os.open(self.d/'private.lock',os.O_CREAT|os.O_RDWR,0o600);fcntl.flock(self.fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
 def tearDown(self):os.close(self.fd);self.temp.cleanup()
 def run_case(self,code,*,handshake=True,wall=3,peer=None,extra_exec=(),owner=False):
  env=dict(os.environ,OMP_NUM_THREADS='1',OPENBLAS_NUM_THREADS='1',MKL_NUM_THREADS='1',NUMEXPR_NUM_THREADS='1',PYTHONDONTWRITEBYTECODE='1')
  own,reaped=g.cpu()
  allow={PYEXE:sha(PYEXE),**{str(Path(p).resolve()):sha(Path(p).resolve()) for p in extra_exec}}
  pre='import os,time,ctypes,json\nOLD='+repr(OLD)+'\nNEW='+repr(str(HERE/'526_traced_bootstrap_guard.py'))+'\n'
  with (self.d/'stdout').open('x') as out,(self.d/'stderr').open('x') as err:
   return g.run_traced([PY,'-B','-c',pre+code],env=env,stdout=out,stderr=err,lock_fd=self.fd,affinity={31},wall_seconds=wall,maximum_combined_CPU_seconds=own+reaped+10,absolute_deadline_UTC=(dt.datetime.now(dt.timezone.utc)+dt.timedelta(seconds=wall+2)).isoformat(),peer_callback=peer or (lambda owned:dict(private_fixture=True,owned=len(owned))),bootstrap_exec_allowlist=allow,owner_path=self.d/'owner.json' if owner else None,require_science_handshake=handshake,peer_interval_seconds=.05)
 def test_normal_helper_reaped_then_strict_boundary(self):
  code="p=os.fork()\nif p==0: os._exit(0)\nos.waitpid(p,0)\n"+HANDSHAKE+"\ntry: os.fork()\nexcept PermissionError: pass\nelse: raise RuntimeError('fork escaped')\n"
  r=self.run_case(code,owner=True)
  self.assertEqual(r['status'],'EXITED',r);self.assertEqual(r['returncode'],0)
  self.assertTrue(r['postbootstrap_TSYNC_scientific_fork_denial']);self.assertFalse(r['whole_startup_subprocess_creation_kernel_denied'])
  self.assertEqual(len([x for x in r['events'] if x['event']=='KERNEL_OWNED_NEWBORN']),2)
  self.assertEqual(json.loads((self.d/'owner.json').read_text())['state'],'CLOSED')
 def test_raw_wait_rows_are_not_summed_for_CPU(self):
  code="p=os.fork()\nif p==0:\n s=time.process_time()\n while time.process_time()-s<.08: pass\n os._exit(0)\nos.waitpid(p,0)\n"+HANDSHAKE
  r=self.run_case(code);raw=sum(x['raw_wait4_inclusive_CPU_seconds'] for x in r['raw_wait4_rows'])
  self.assertEqual(r['status'],'EXITED',r);self.assertGreater(raw,r['child_tree_CPU_seconds']+.04)
  self.assertIn('not_summed',r['CPU_accounting_basis'])
 def test_surviving_helper_at_boundary_rejects_and_drains(self):
  code="p=os.fork()\nif p==0: time.sleep(5);os._exit(0)\n"+HANDSHAKE
  r=self.run_case(code);self.assertEqual(r['status'],'ABORTED');self.assertTrue(r['drained']);self.assertIn('helper survives',r['error'])
 def test_root_death_drains_orphan_helpers(self):
  r=self.run_case("p=os.fork()\nif p==0: time.sleep(5);os._exit(0)\nos._exit(0)",handshake=False)
  self.assertEqual(r['abort_reason'],'ROOT_EXIT_WITH_LIVE_HELPER');self.assertTrue(r['drained']);self.assertEqual(r['remaining_owned_lifetimes'],[])
 def test_false_handshake_without_filter_is_rejected(self):
  r=self.run_case("os.write(int(os.environ['R157_FILTER_PROOF_FD']),os.environ['R157_FILTER_TOKEN'].encode());time.sleep(4)")
  self.assertEqual(r['status'],'ABORTED');self.assertIn('not attested',r['error']);self.assertTrue(r['drained'])
 def test_unreviewed_exec_is_stopped_before_execution(self):
  r=self.run_case("os.execv('/usr/bin/true',['true'])",handshake=False)
  self.assertEqual(r['abort_reason'],'UNREVIEWED_BOOTSTRAP_EXECUTABLE');self.assertTrue(r['drained'])
 def test_reviewed_exec_is_captured_and_reaped(self):
  r=self.run_case("p=os.fork()\nif p==0: os.execv('/usr/bin/true',['true'])\nos.waitpid(p,0)\n"+HANDSHAKE,extra_exec=('/usr/bin/true',))
  self.assertEqual(r['status'],'EXITED',r);self.assertGreaterEqual(len([e for e in r['events'] if e['event']=='EXEC']),2)
 def test_kernel_denies_namespace_affinity_and_untraced_clone(self):
  code="l=ctypes.CDLL(None,use_errno=True)\nfor nr,args in [(112,()),(109,(0,0)),(203,(0,8,0)),(272,(0,)),(56,(0x800000|17,0,0,0,0))]:\n ctypes.set_errno(0);v=l.syscall(nr,*args)\n if v==0 and nr==56: os._exit(97)\n assert v==-1 and ctypes.get_errno()==1,(nr,v,ctypes.get_errno())\n"+HANDSHAKE
  r=self.run_case(code);self.assertEqual(r['status'],'EXITED',r);self.assertEqual(r['returncode'],0)
 def test_wall_expiry_stops_only_owned_tree(self):
  r=self.run_case("p=os.fork()\nif p==0: time.sleep(5);os._exit(0)\ntime.sleep(5)",handshake=False,wall=.2)
  self.assertEqual(r['abort_reason'],'WALL_OR_ABSOLUTE_LIMIT');self.assertTrue(r['drained']);self.assertLess(r['wall_seconds'],2)
 def test_peer_conflict_fails_before_any_fork(self):
  def no(owned):raise ValueError('peer conflict')
  with self.assertRaisesRegex(ValueError,'peer conflict'):self.run_case('',peer=no)
 def test_nonexclusive_or_wrong_lock_is_rejected(self):
  fcntl.flock(self.fd,fcntl.LOCK_UN)
  with self.assertRaisesRegex(g.GuardError,'exclusive FLOCK'):self.run_case('')
 def test_live_owner_fd_and_wrong_lock(self):
  now=time.time();v={'schema':'r157_ptrace_owner_v1','state':'LIVE','supervisor':g.identity(os.getpid()),'permit':g.held_lock(self.fd),'phase':'TEST_OWNER','scope':'PRIVATE_METADATA','source':{'guard':sha(HERE/'526_traced_bootstrap_guard.py')},'authority_pin':None,'absolute_deadline_epoch':now+5}
  g.immutable(self.d/'live.json',v)
  self.assertEqual(g.inspect_owner(self.d/'live.json',self.d/'private.lock')['status'],'VERIFIED_CURRENT_TRACE_OWNER')
  other=self.d/'other.lock';other.touch()
  with self.assertRaisesRegex(g.GuardError,'wrong lock'):g.inspect_owner(self.d/'live.json',other)
 def test_tracer_death_EXITKILL_drains_all_and_releases_private_permit(self):
  # This harness is a subreaper only for its own newly spawned test controller.
  l=ctypes.CDLL(None,use_errno=True);old=ctypes.c_int();l.prctl(37,ctypes.byref(old),0,0,0);l.prctl(36,1,0,0,0)
  data=self.d/'tree.json';lock=self.d/'death.lock'
  script=self.d/'controller.py'
  script.write_text("import os,time,json,sys,fcntl,datetime as dt,importlib.util,hashlib\nfrom pathlib import Path\nspec=importlib.util.spec_from_file_location('g',"+repr(str(HERE/'526_traced_bootstrap_guard.py'))+");g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)\nfd=os.open("+repr(str(lock))+",os.O_CREAT|os.O_RDWR,0o600);fcntl.flock(fd,fcntl.LOCK_EX)\ncode="+repr("import os,time,json\np=os.fork()\nif p==0: time.sleep(10);os._exit(0)\nopen("+repr(str(data))+",'w').write(json.dumps([os.getpid(),p]));time.sleep(10)")+"\nout=open(os.devnull,'w');own,ch=g.cpu();g.run_traced(["+repr(PY)+",'-B','-c',code],env=dict(os.environ),stdout=out,stderr=out,lock_fd=fd,affinity={31},wall_seconds=15,maximum_combined_CPU_seconds=own+ch+5,absolute_deadline_UTC=(dt.datetime.now(dt.timezone.utc)+dt.timedelta(seconds=20)).isoformat(),peer_callback=lambda own:{},bootstrap_exec_allowlist={"+repr(PYEXE)+":hashlib.sha256(Path("+repr(PYEXE)+").read_bytes()).hexdigest()},require_science_handshake=False)\n")
  p=subprocess.Popen([PY,'-B',str(script)],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  try:
   end=time.monotonic()+5
   while not data.exists() and time.monotonic()<end:time.sleep(.01)
   self.assertTrue(data.exists());kids=json.loads(data.read_text());p.kill();p.communicate(timeout=3)
   for kid in kids:
    end=time.monotonic()+3
    while time.monotonic()<end:
     try:w,_,_=os.wait4(kid,os.WNOHANG)
     except ChildProcessError:break
     if w:break
     time.sleep(.01)
    self.assertFalse(Path('/proc',str(kid)).exists(),'EXITKILL left tracee')
   q=os.open(lock,os.O_RDWR);fcntl.flock(q,fcntl.LOCK_EX|fcntl.LOCK_NB);os.close(q)
  finally:
   if p.poll() is None:p.kill();p.communicate()
   l.prctl(36,old.value,0,0,0)

if __name__=='__main__':unittest.main()
