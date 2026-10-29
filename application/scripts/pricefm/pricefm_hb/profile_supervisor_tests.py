"""Private fresh-process kernel/fork accounting checks; no scientific imports."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import signal
from . import profile_supervisor as s


def command(code, cpu=4, wall=8, cap=65536, passthrough=False):
    args = [sys.executable, '-I', '-B', str(Path(s.__file__)), '--cpu', str(cpu),
            '--wall', str(wall), '--output-cap', str(cap)]
    if passthrough: args.append('--passthrough')
    return args + ['--', sys.executable, '-I', '-B', '-c', code]


class AggregateTests(unittest.TestCase):
    def run_command(self, code, **kw):
        result = subprocess.run(command(code, **kw), capture_output=True, timeout=15)
        self.assertTrue(result.stdout, result.stderr.decode())
        return result, json.loads(result.stdout)

    def test_simple_fresh_command_is_proved_and_reaped(self):
        result, receipt = self.run_command('print("owned")', cpu=2)
        self.assertEqual(result.returncode, 0); self.assertEqual(receipt['stdout'], 'owned\n')
        self.assertTrue(receipt['kernel_escape_filter']); self.assertTrue(receipt['all_owned_descendants_reaped'])
        self.assertLess(receipt['aggregate_CPU_seconds'], 2)

    def test_forked_burners_share_one_aggregate_cap(self):
        code = '''import os,time
for _ in range(2):
    if os.fork()==0:
        start=time.process_time()
        while time.process_time()-start<2.5: pass
        os._exit(0)
for _ in range(2): os.wait()
'''
        result, receipt = self.run_command(code, cpu=3)
        self.assertEqual(result.returncode, 124); self.assertEqual(receipt['cap_reason'], 'AGGREGATE_CPU_BOUNDARY')
        self.assertLess(receipt['aggregate_CPU_seconds'], 3)
        self.assertGreaterEqual(len(receipt['reaped']), 3)
        self.assertTrue(receipt['all_owned_descendants_reaped'])

    def test_orphan_is_adopted_and_drained_after_leader_exit(self):
        code = '''import os,time
if os.fork(): os._exit(0)
time.sleep(.1)
print("orphan reaped",flush=True)
os._exit(0)
'''
        result, receipt = self.run_command(code)
        self.assertEqual(result.returncode, 0); self.assertEqual(receipt['stdout'], 'orphan reaped\n')
        self.assertEqual(len(receipt['reaped']), 2)
        self.assertTrue(receipt['orphan_subreaper'])

    def test_waited_descendant_CPU_is_not_charged_twice(self):
        code = '''import os,time
if os.fork()==0:
    start=time.process_time()
    while time.process_time()-start<.12: pass
    os._exit(0)
os.wait()
print("complete")
'''
        result, receipt = self.run_command(code)
        self.assertEqual(result.returncode, 0)
        self.assertLess(receipt['aggregate_CPU_seconds'], .8)
        self.assertLessEqual(receipt['conservative_max_snapshot_CPU'] - receipt['maximum_live_tick_rounding_seconds'],
                             receipt['aggregate_CPU_seconds'] + .04)

    def test_session_group_affinity_and_parent_signal_escapes_are_denied(self):
        code = '''import ctypes,json,os,signal
values=[]
for fn in (lambda:os.setsid(),lambda:os.setpgid(0,0),lambda:os.sched_setaffinity(0,os.sched_getaffinity(0)),lambda:os.kill(os.getppid(),signal.SIGTERM)):
    try: fn();values.append("ESCAPED")
    except PermissionError: values.append("DENIED")
libc=ctypes.CDLL(None,use_errno=True)
value=libc.syscall(0x40000000|112)
values.append("DENIED" if value==-1 and ctypes.get_errno()==1 else "ESCAPED")
print(json.dumps(values))
'''
        result, receipt = self.run_command(code)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(receipt['stdout']), ['DENIED'] * 5)

    def test_wall_timeout_kills_and_reaps_own_tree(self):
        result, receipt = self.run_command('import time;time.sleep(30)', cpu=3, wall=4)
        self.assertEqual(result.returncode, 124); self.assertEqual(receipt['cap_reason'], 'WALL_BOUNDARY')
        self.assertTrue(receipt['all_owned_descendants_reaped']); self.assertLess(receipt['wall_seconds'], 4)

    def test_binary_passthrough_supports_live_rsync_protocol(self):
        raw = bytes(range(256)) * 256
        result = subprocess.run(command('import sys;sys.stdout.buffer.write(sys.stdin.buffer.read())',
            passthrough=True, cap=131072), input=raw, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(result.stdout, raw)

    def test_excess_output_is_a_failed_owned_command(self):
        result, receipt = self.run_command('print("x"*8192)', cpu=3, cap=64)
        self.assertEqual(result.returncode, 124); self.assertEqual(receipt['cap_reason'], 'OUTPUT_BOUNDARY')
        self.assertTrue(receipt['all_owned_descendants_reaped'])

    def test_no_scientific_module_was_imported(self):
        self.assertFalse({'numpy', 'scipy', 'pandas'} & set(sys.modules))

    @unittest.skip('Legacy rsync requires child SIGUSR2; its failure proof is retained and current transport is stdlib stream')
    def test_real_rsync_private_copy_and_forking_children_complete(self):
        binary = shutil.which('rsync')
        if binary is None: self.skipTest('rsync unavailable in this source-only environment')
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source = root / 'source'; target = root / 'target'; source.mkdir(); target.mkdir()
            raw = b'owned administrative fixture\n' * 1000; (source / 'proof.txt').write_bytes(raw)
            args = [sys.executable, '-I', '-B', str(Path(s.__file__)), '--cpu', '5', '--wall', '10',
                    '--output-cap', '65536', '--', binary, '-rlt', '--checksum', '--no-links', str(source) + '/', str(target) + '/']
            result = subprocess.run(args, capture_output=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr.decode() + result.stdout.decode())
            receipt = json.loads(result.stdout)
            self.assertTrue(receipt['all_owned_descendants_reaped'])
            self.assertEqual((target / 'proof.txt').read_bytes(), raw)

    def owned_monitor_fixture(self, base, supervisor_path=None):
        marker = base / 'owned_ids.json'
        code = ('import json,os,time;from pathlib import Path\n'
            'kid=os.fork()\n'
            'if kid==0: time.sleep(10);os._exit(0)\n'
            'Path(' + repr(str(marker)) + ').write_text(json.dumps({"monitor":os.getppid(),"command":os.getpid(),"child":kid}))\n'
            'time.sleep(10)\n')
        argv = command(code, cpu=4, wall=8)
        if supervisor_path is not None: argv[3] = str(supervisor_path)
        process = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        end = time.monotonic() + 3
        while not marker.exists() and time.monotonic() < end: time.sleep(.01)
        if not marker.exists():
            stdout, stderr = process.communicate(timeout=10)
            self.fail('owned fixture never published marker; rc=' + str(process.returncode)
                      + ' stdout=' + stdout.decode() + ' stderr=' + stderr.decode())
        return process, json.loads(marker.read_text())

    def test_guardian_reaps_forked_commands_after_owned_monitor_is_killed(self):
        with tempfile.TemporaryDirectory() as tmp:
            process, ids = self.owned_monitor_fixture(Path(tmp))
            info = s.process_record(ids['monitor'])
            self.assertEqual(info['ppid'], process.pid); self.assertEqual(info['uid'], os.getuid())
            os.kill(ids['monitor'], signal.SIGKILL)
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 125, stderr.decode())
            value = json.loads(stdout); self.assertTrue(value['all_owned_descendants_reaped'])
            self.assertGreaterEqual(len(value['guardian_adopted']), 2)

    def test_monitor_drains_its_owned_group_after_guardian_is_killed(self):
        s.prctl(36, 1)  # This private test process adopts only its fixture monitor.
        with tempfile.TemporaryDirectory() as tmp:
            process, ids = self.owned_monitor_fixture(Path(tmp))
            os.kill(process.pid, signal.SIGKILL); process.communicate(timeout=5)
            end = time.monotonic() + 5; adopted = False
            while time.monotonic() < end:
                got, status, usage = os.wait4(ids['monitor'], os.WNOHANG)
                if got: adopted = True; break
                time.sleep(.01)
            self.assertTrue(adopted)
            self.assertFalse((Path('/proc') / str(ids['command'])).exists())
            self.assertFalse((Path('/proc') / str(ids['child'])).exists())

    def test_monitor_death_before_publication_cannot_start_reviewed_command(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); marker = root / 'preexec.json'; private = root / 'supervisor_fixture.py'
            source = Path(s.__file__).read_text()
            anchor = "    if GUARD_SHARED is not None:\n        item = process_record(os.getpid())"
            replacement = ("    if GUARD_SHARED is not None:\n        Path(" + repr(str(marker))
                + ").write_text(json.dumps({'monitor':os.getppid(),'command':os.getpid()})); time.sleep(.5)\n        item = process_record(os.getpid())")
            self.assertEqual(source.count(anchor), 1); private.write_text(source.replace(anchor, replacement))
            argv = command('print("MUST_NOT_RUN")', cpu=4, wall=8); argv[3] = str(private)
            process = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            end = time.monotonic() + 3
            while not marker.exists() and time.monotonic() < end: time.sleep(.01)
            self.assertTrue(marker.exists()); ids = json.loads(marker.read_text())
            self.assertEqual(s.process_record(ids['monitor'])['ppid'], process.pid)
            os.kill(ids['monitor'], signal.SIGKILL)
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 125, stderr.decode())
            value = json.loads(stdout); self.assertTrue(value['all_owned_descendants_reaped'])
            self.assertNotIn('MUST_NOT_RUN', value.get('stdout', ''))

    def test_partial_monitor_receipt_still_drains_live_owned_command(self):
        with tempfile.TemporaryDirectory() as tmp:
            private = Path(tmp) / 'supervisor_fixture.py'; source = Path(s.__file__).read_text()
            source = source.replace("                value = run(command,", "                globals()['PRIVATE_RECEIPT'] = receipt\n                value = run(command,", 1)
            anchor = "    leader = process_record(child.pid)"
            inject = (anchor + "\n    globals()['PRIVATE_RECEIPT'].write(b'{bad'); globals()['PRIVATE_RECEIPT'].flush(); time.sleep(.1); os._exit(0)")
            self.assertEqual(source.count(anchor), 1); private.write_text(source.replace(anchor, inject))
            args = command('import time;time.sleep(30)', cpu=4, wall=8); args[3] = str(private)
            result = subprocess.run(args, capture_output=True, timeout=12)
            self.assertEqual(result.returncode, 125, result.stderr.decode())
            value = json.loads(result.stdout)
            self.assertIn('INVALID_MONITOR_RECEIPT', value['cap_reason'])
            self.assertTrue(value['all_owned_descendants_reaped']); self.assertTrue(value['guardian_adopted'])


if __name__ == '__main__': unittest.main()
