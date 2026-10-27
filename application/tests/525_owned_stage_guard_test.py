#!/usr/bin/env python3
"""Metadata/sleep fixtures only. Run this test process on administrative CPU31."""
import ctypes
import datetime
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parents[1] / 'scripts/pricefm'
SPEC = importlib.util.spec_from_file_location('owned_stage_guard', HERE / '525_owned_stage_guard.py')
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


def deadline(seconds=60):
    return (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=seconds)).isoformat()


def fixture_process(root, pid, *, state='S', comm='python', affinity=62, ppid=1):
    process = root / str(pid)
    (process / 'task' / str(pid)).mkdir(parents=True)
    fields = ['0'] * 40
    fields[0], fields[1], fields[19] = state, str(ppid), str(pid * 100)
    (process / 'stat').write_text(str(pid) + ' (' + comm + ') ' + ' '.join(fields))
    command = b'python\0metadata_fixture.py\0'
    (process / 'cmdline').write_bytes(command)
    (process / 'exe').symlink_to('/usr/bin/python3')
    return dict(pid=pid, start_ticks=pid * 100, cmdline_sha256=hashlib.sha256(command).hexdigest(),
                boot_id='fixture-boot', allowed_states=['T']), {pid: {affinity}}


class PeerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / 'sys/kernel/random').mkdir(parents=True)
        (self.root / 'sys/kernel/random/boot_id').write_text('fixture-boot')

    def tearDown(self):
        self.temp.cleanup()

    def run_peer(self, census, affinities, **extra):
        return guard.physical_peer_guard(census, self.root, proc_root=self.root,
                                         affinity_reader=lambda tid: affinities[tid],
                                         resource_reader=lambda: (192 * guard.GIB, 80 * guard.GIB),
                                         verify_topology=False, **extra)

    def test_unknown_numerical_smt62_rejected(self):
        _, affinity = fixture_process(self.root, 90001)
        with self.assertRaisesRegex(guard.GuardError, 'SMT62'):
            self.run_peer({'allowed_intersecting_processes': []}, affinity)
        affinity[90001] = {31}
        self.assertEqual(self.run_peer({'allowed_intersecting_processes': []}, affinity)['physical_pair'], [30, 62])

    def test_frozen_numerical_shell_marker_rejected_before_R_child(self):
        _, affinity = fixture_process(self.root, 90006, comm='bash')
        p=self.root/'90006';(p/'exe').unlink();(p/'exe').symlink_to('/usr/bin/bash')
        marker='run_independent_qdesn_cellwise_refinement_v2_pipeline.sh'
        (p/'cmdline').write_bytes(('bash\0/some/path/'+marker+'\0').encode())
        with self.assertRaisesRegex(guard.GuardError,'unknown numerical peer'):
            self.run_peer({'allowed_intersecting_processes':[],'numerical_markers':[marker]},affinity)

    def test_stopped_peer_resumed_and_boot_hash_lifetime_changes(self):
        entry, affinity = fixture_process(self.root, 90002, state='T')
        census = {'allowed_intersecting_processes': [entry]}
        self.run_peer(census, affinity)
        for key, value in [('boot_id', 'wrong'), ('start_ticks', 1), ('cmdline_sha256', '0' * 64), ('allowed_states', ['S'])]:
            changed = dict(entry, **{key: value})
            with self.subTest(key=key), self.assertRaises(guard.GuardError):
                self.run_peer({'allowed_intersecting_processes': [changed]}, affinity)
        # Resuming a reviewed stopped peer fails even if moved away from pair.
        affinity[90002] = {31}
        entry['allowed_states'] = ['S']
        with self.assertRaisesRegex(guard.GuardError, 'identity/state'):
            self.run_peer(census, affinity)

    def test_permission_error_and_false_disappearance_fail(self):
        _, affinity = fixture_process(self.root, 90003)
        original = Path.read_bytes
        def denied(path):
            if path.name == 'cmdline':
                raise PermissionError('fixture denied')
            return original(path)
        with patch.object(Path, 'read_bytes', denied), self.assertRaises(PermissionError):
            self.run_peer({'allowed_intersecting_processes': []}, affinity)
        (self.root / '90003/cmdline').unlink()
        with self.assertRaisesRegex(guard.GuardError, 'still present'):
            self.run_peer({'allowed_intersecting_processes': []}, affinity)

    def test_floors_and_exact_owned_child_exclusion(self):
        _, affinity = fixture_process(self.root, 90004, ppid=os.getpid())
        owned = dict(pid=90004, start_ticks=9000400, ppid=os.getpid(), boot_id='fixture-boot')
        self.run_peer({'allowed_intersecting_processes': []}, affinity, owned_identity=owned)
        with self.assertRaisesRegex(guard.GuardError, 'lifetime changed'):
            self.run_peer({'allowed_intersecting_processes': []}, affinity,
                          owned_identity=dict(owned, start_ticks=1))
        with self.assertRaisesRegex(guard.GuardError, 'floor'):
            guard.physical_peer_guard({'allowed_intersecting_processes': []}, self.root,
                proc_root=self.root, affinity_reader=lambda _: {31}, verify_topology=False,
                resource_reader=lambda: (192 * guard.GIB - 1, 80 * guard.GIB))


class OwnedTests(unittest.TestCase):
    def setUp(self):
        self.assertEqual(os.sched_getaffinity(0), {31}, 'all tests must run administrative CPU31')
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.fd = os.open(self.root / 'permit.lock', os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def tearDown(self):
        os.close(self.fd)
        self.temp.cleanup()

    def callback(self, identity):
        if identity is not None:
            row = guard.proc_stat(identity['pid'])
            self.assertEqual(row['ppid'], os.getpid())
            self.assertEqual(row['start_ticks'], identity['start_ticks'])
            self.assertEqual(os.sched_getaffinity(identity['pid']), {31})
        return {'fixture': 'metadata only'}

    def run_child(self, script='import time;time.sleep(.12)', **overrides):
        own, reaped = guard._cpu_usage()
        args = dict(env=dict(os.environ), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    preexec_fn=lambda: os.sched_setaffinity(0, {31}), pass_fds=(self.fd,), lock_fd=self.fd,
                    wall_seconds=3, maximum_combined_CPU_seconds=own + reaped + 10,
                    absolute_deadline_UTC=deadline(), peer_check_callback=self.callback,
                    expected_child_affinity={31}, interval_seconds=.02, peer_interval_seconds=.02)
        args.update(overrides)
        return guard.run_owned([sys.executable, '-B', '-c', script], **args)

    def test_success_wait4_rusage_exact_identity_inherited_flock(self):
        observed = []
        def check(identity):
            result = self.callback(identity)
            if identity is not None:
                fd = os.open(self.root / 'permit.lock', os.O_RDWR)
                try:
                    with self.assertRaises(BlockingIOError):
                        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                finally:
                    os.close(fd)
                observed.append(identity)
            return result
        result = self.run_child(peer_check_callback=check)
        self.assertEqual(result['status'], 'EXITED')
        self.assertEqual(result['returncode'], 0)
        self.assertTrue(result['reaped'] and result['drained'] and result['CPU_accounting_complete'])
        self.assertGreater(result['child_CPU_seconds'], 0)
        self.assertTrue(observed)
        with self.assertRaises(ChildProcessError):
            os.waitpid(result['owned_child']['pid'], os.WNOHANG)

    def test_wall_and_periodic_permission_failure_stop_only_child(self):
        result = self.run_child('import time;time.sleep(10)', wall_seconds=.08)
        self.assertIn(result['abort_reason'], ('WALL_LIMIT', 'WALL_LIMIT_AFTER_REAP'))
        self.assertIn(result['returncode'], (-signal.SIGKILL, -signal.SIGALRM))
        self.assertTrue(result['reaped'] and result['drained'])
        def denied(identity):
            if identity is not None:
                raise PermissionError('periodic metadata denied')
            return {}
        result = self.run_child('import time;time.sleep(10)', peer_check_callback=denied)
        self.assertIn('PermissionError', result['error'])
        self.assertTrue(result['child_signalled'] and result['drained'])

    def test_budget_deadline_and_missing_flock_reject_before_launch(self):
        with patch.object(guard.subprocess, 'Popen', side_effect=AssertionError('must not launch')):
            with self.assertRaisesRegex(guard.GuardError, 'expired'):
                self.run_child(absolute_deadline_UTC=deadline(-1))
            with self.assertRaisesRegex(guard.GuardError, 'CPU already exhausted'):
                self.run_child(maximum_combined_CPU_seconds=.000001)
            with self.assertRaisesRegex(guard.GuardError, 'administrative CPU already exhausted'):
                self.run_child(maximum_administrative_CPU_seconds=.000001)
            with self.assertRaisesRegex(guard.GuardError, 'interval/grace'):
                self.run_child(peer_interval_seconds=10.1)
            fcntl.flock(self.fd, fcntl.LOCK_UN)
            with self.assertRaisesRegex(guard.GuardError, 'not held'):
                self.run_child()

    def test_absolute_deadline_during_run_and_combined_cpu(self):
        result = self.run_child('import time;time.sleep(10)', absolute_deadline_UTC=deadline(.08))
        self.assertIn(result['abort_reason'], ('ABSOLUTE_DEADLINE', 'ABSOLUTE_DEADLINE_AFTER_REAP'))
        own, reaped = guard._cpu_usage()
        # Startup/metadata CPU only; deliberately tiny allowance, no busy loop.
        result = self.run_child('import time;time.sleep(10)', maximum_combined_CPU_seconds=own + reaped + .006)
        self.assertIn(result['abort_reason'], ('COMBINED_CPU_LIMIT', 'COMBINED_CPU_LIMIT_AFTER_REAP'))
        self.assertTrue(result['reaped'])

    def test_separate_cheap_and_full_census_cadence_and_measured_cost(self):
        result=self.run_child('import time;time.sleep(.12)',peer_interval_seconds=.07)
        self.assertEqual(result['status'],'EXITED')
        self.assertEqual(result['owned_lifetime_CPU_wall_interval_seconds'],.02)
        self.assertEqual(result['full_peer_resource_interval_seconds'],.07)
        self.assertGreaterEqual(result['periodic_observations'],1)
        self.assertLessEqual(result['periodic_observations'],3)
        self.assertEqual(len(result['measured_peer_census_costs']),result['periodic_observations']+2)
        self.assertGreaterEqual(result['administrative_CPU_seconds_including_startup_and_helpers'],0)

    def test_preexec_pdeath_and_affinity_cannot_be_cleared(self):
        def clear_pdeath():
            ctypes.CDLL(None).prctl(1, 0, 0, 0, 0)
        result = self.run_child(preexec_fn=clear_pdeath)
        self.assertEqual(result['returncode'], 125)
        result = self.run_child(preexec_fn=lambda: None, expected_child_affinity={30})
        self.assertEqual(result['returncode'], 125)

    def test_kernel_denies_fork_vfork_nonthread_clone_but_allows_threads(self):
        script = '''import ctypes,errno,os,threading
libc=ctypes.CDLL(None,use_errno=True)
for nr in (57,58,56):
 ctypes.set_errno(0)
 value=libc.syscall(nr,0,0,0,0,0)
 assert value==-1 and ctypes.get_errno()==errno.EPERM,(nr,value,ctypes.get_errno())
ctypes.set_errno(0)
assert libc.syscall(435,0,0)==-1 and ctypes.get_errno()==errno.ENOSYS
try: os.fork()
except PermissionError: pass
else: os._exit(7)
finished=[]
t=threading.Thread(target=lambda:finished.append(os.sched_getaffinity(0)))
t.start();t.join();assert finished==[{31}]
'''
        result = self.run_child(script)
        self.assertEqual(result['returncode'], 0, result)
        self.assertTrue(result['subprocess_creation_kernel_denied'])
        self.assertTrue(result['CPU_accounting_complete'])

    def test_failed_or_unsupported_seccomp_exits_before_payload(self):
        output = self.root / 'must_not_exist'
        with patch.object(guard, 'deny_subprocess_creation', side_effect=guard.GuardError('unavailable')):
            result = self.run_child('from pathlib import Path;Path(' + repr(str(output)) + ').write_text("unsafe")')
        self.assertEqual(result['returncode'], 125)
        self.assertFalse(result['preexec_kernel_boundary_proved'])
        self.assertFalse(result['subprocess_creation_kernel_denied'])
        self.assertFalse(result['CPU_accounting_complete'])
        self.assertFalse(output.exists())

    def test_lost_identity_never_signals_reused_or_unknown_pid(self):
        real_stat = guard.proc_stat
        calls = []
        def changed(pid, *args):
            row = real_stat(pid, *args)
            calls.append(pid)
            if len(calls) > 1:
                row['start_ticks'] += 1
            return row
        # Child is a short sleep, so it exits itself; injected loss of identity
        # must never route through a generic kill. Reap it explicitly afterwards.
        with patch.object(guard, 'proc_stat', changed), patch.object(guard.os, 'kill') as kill:
            result = self.run_child('import time;time.sleep(.04)')
            kill.assert_not_called()
        self.assertFalse(result['reaped'])
        self.assertEqual(result['abort_reason'], 'OWNERSHIP_OR_OBSERVER_FAILURE')
        pid = result['owned_child']['pid']
        _, status, _ = os.wait4(pid, 0)
        self.assertEqual(os.waitstatus_to_exitcode(status), 0)
        for process in guard._UNREAPED:
            if process.pid == pid:
                process.returncode = 0

    def test_kernel_pdeath_reclaims_new_sleep_child_and_lock(self):
        # Disposable metadata-only supervisor exits itself. Its child inherits
        # its own separate flock; Linux PDEATHSIG must stop only that new child.
        script = '''import importlib.util,os,fcntl,signal,sys
from pathlib import Path
s=importlib.util.spec_from_file_location('g',sys.argv[1]);g=importlib.util.module_from_spec(s);s.loader.exec_module(g)
fd=os.open(sys.argv[2],os.O_CREAT|os.O_RDWR,0o600);fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
def check(identity):
 if identity and not Path(sys.argv[3]).exists():
  temporary=Path(sys.argv[3]+'.tmp');temporary.write_text(str(identity['pid']));os.replace(temporary,sys.argv[3])
 return {}
signal.signal(signal.SIGALRM,lambda *_:os._exit(0));signal.alarm(1)
g.run_owned([sys.executable,'-c','import time;time.sleep(30)'],env=dict(os.environ),stdout=-3,stderr=-3,preexec_fn=lambda:os.sched_setaffinity(0,{31}),pass_fds=(fd,),lock_fd=fd,wall_seconds=10,maximum_combined_CPU_seconds=10,absolute_deadline_UTC=sys.argv[4],peer_check_callback=check,expected_child_affinity={31},interval_seconds=.05,peer_interval_seconds=.05)
'''
        private_lock = self.root / 'pdeath.lock'
        pidfile = self.root / 'child.pid'
        supervisor = subprocess.Popen([sys.executable, '-B', '-c', script, str(HERE / '525_owned_stage_guard.py'),
                                       str(private_lock), str(pidfile), deadline()], stdout=subprocess.DEVNULL,
                                      stderr=subprocess.PIPE)
        _, stderr = supervisor.communicate(timeout=4)
        self.assertEqual(supervisor.returncode, 0, stderr.decode())
        self.assertTrue(pidfile.exists())
        pid = int(pidfile.read_text())
        end = time.monotonic() + 2
        while time.monotonic() < end:
            try:
                row = guard.proc_stat(pid)
                if row['state'] in ('Z', 'X', 'x'):
                    break
            except FileNotFoundError:
                break
            time.sleep(.01)
        else:
            self.fail('new disposable child survived its parent')
        fd = os.open(private_lock, os.O_RDWR)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        finally:
            os.close(fd)


if __name__ == '__main__':
    unittest.main(verbosity=2)
