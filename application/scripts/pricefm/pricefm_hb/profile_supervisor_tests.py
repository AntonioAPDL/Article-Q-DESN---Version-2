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
import struct
import resource
from types import SimpleNamespace
from unittest.mock import patch
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

    def assert_failed_boundary(self,result,receipt,*,normal,cpu,wall):
        self.assertTrue(receipt.get('all_owned_descendants_reaped'),receipt)
        self.assertLess(receipt['aggregate_CPU_seconds'],cpu,receipt)
        self.assertLessEqual(receipt['complete_lifecycle_wall_seconds'],wall,receipt)
        if result.returncode==124:
            self.assertEqual(receipt['cap_reason'],normal,receipt);return True
        self.assertEqual(result.returncode,125,receipt)
        witness=receipt.get('owned_stop_witness');self.assertIsInstance(witness,dict,receipt)
        self.assertIn(witness.get('failure'),('STOP_WAIT_CPU_UPPER_BOUNDARY','STOP_WAIT_INNER_WALL'),receipt)
        self.assertTrue(receipt.get('independent_guardian'));self.assertTrue(receipt.get('guardian_included_in_CPU'))
        self.assertTrue(witness.get('states_are_not_accepted_for_accounting'))
        self.assertEqual(witness['uid'],os.getuid());self.assertGreater(witness['leader_start_ticks'],0)
        core=witness['monitor_affinity'];self.assertIsInstance(core,list);self.assertEqual(len(core),1)
        self.assertGreater(witness['session_id'],0);self.assertTrue(witness['exact_proved_owned_items'])
        for item in witness['exact_proved_owned_items']:
            self.assertEqual(item['uid'],os.getuid());self.assertGreater(item['pid'],0)
            self.assertEqual(item['pgid'],witness['session_id']);self.assertEqual(item['sid'],witness['session_id'])
            self.assertGreaterEqual(item['start_ticks'],witness['leader_start_ticks'])
            if item['state']!='Z':
                self.assertTrue(item['affinity_proved']);self.assertEqual(item['affinity'],core)
        if witness['failure']=='STOP_WAIT_CPU_UPPER_BOUNDARY':
            self.assertGreaterEqual(witness['one_core_CPU_upper'],witness['CPU_active_ceiling'])
        else:self.assertGreaterEqual(witness['observed_monotonic'],witness['original_inner_deadline_monotonic'])
        return False

    def test_simple_fresh_command_is_proved_and_reaped(self):
        # Positive owned-kernel proof, not a minimum-2CPU availability benchmark.
        result, receipt = self.run_command('print("owned")', cpu=4)
        detail={'receipt':receipt,'supervisor_stderr':result.stderr.decode()}
        self.assertEqual(result.returncode, 0, detail); self.assertEqual(receipt['stdout'], 'owned\n', detail)
        self.assertTrue(receipt['kernel_escape_filter'], detail); self.assertTrue(receipt['all_owned_descendants_reaped'], detail)
        self.assertLess(receipt['aggregate_CPU_seconds'], 4, detail)

    def test_real_nondumpable_owned_guardian_proc_SELF_sample_is_readable_and_bounded(self):
        # This checks nondumpable guardian readability/accounting at a bounded
        # proof allowance; production helper caps and negative tests are separate.
        result,receipt=self.run_command('print("owned guardian stat proof")',cpu=4)
        detail={'receipt':receipt,'supervisor_stderr':result.stderr.decode()}
        self.assertEqual(result.returncode,0,detail)
        self.assertTrue(receipt['guardian_nondumpable'],detail)
        self.assertEqual(receipt['guardian_CPU_snapshot_source'],'OWNED_PROC_SELF_TICKS_PLUS_TWO_ROUNDING_TICKS',detail)
        self.assertGreaterEqual(receipt['maximum_live_tick_rounding_seconds'],2/os.sysconf('SC_CLK_TCK'),detail)
        self.assertTrue(receipt['all_owned_descendants_reaped'],detail);self.assertLess(receipt['aggregate_CPU_seconds'],4,detail)

    def test_real_guardian_heartbeat_survives_synthetic_delayed_stop_observation(self):
        with tempfile.TemporaryDirectory(prefix='pricefm_delayed_state_',dir='/dev/shm') as tmp:
            private=Path(tmp)/'supervisor_delayed_observation.py';source=Path(s.__file__).read_text()
            anchor='    return result\n\n\ndef guardian_self_upper'
            replacement=('    until=globals().setdefault("PRIVATE_SYNTHETIC_STOP_UNTIL",time.monotonic()+1.1)\n'
                '    if time.monotonic()<until:\n'
                '        for item in result:item["state"]="D"  # Deliberately false fixture observations, never accepted.\n'
                '    return result\n\n\ndef guardian_self_upper')
            self.assertEqual(source.count(anchor),1);private.write_text(source.replace(anchor,replacement))
            argv=command('print("after coherent real stop")',cpu=4,wall=8);argv[3]=str(private)
            result=subprocess.run(argv,capture_output=True,timeout=12);self.assertTrue(result.stdout,result.stderr.decode())
            receipt=json.loads(result.stdout);self.assertEqual(result.returncode,0,receipt)
            self.assertFalse(receipt['guardian_forced_monitor_stop']);self.assertGreater(receipt['maximum_stop_wait_seconds'],1)
            self.assertLess(receipt['aggregate_CPU_seconds'],4);self.assertTrue(receipt['all_owned_descendants_reaped'])

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
        coherent=self.assert_failed_boundary(result,receipt,normal='AGGREGATE_CPU_BOUNDARY',cpu=3,wall=8)
        if coherent:self.assertGreaterEqual(len(receipt['reaped']),3)

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
        coherent=self.assert_failed_boundary(result,receipt,normal='WALL_BOUNDARY',cpu=3,wall=4)
        if coherent:self.assertLess(receipt['wall_seconds'],4)

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


class StopWaitProofTests(unittest.TestCase):
    def exercise(self,delay=0.,state='D',ceiling=10.,inner=20.,initial=.1):
        clock={'now':10.};beats=[];observations=[]
        item=dict(pid=123,start_ticks=45,uid=os.getuid(),sid=123,pgid=123,ppid=1,
                  own_ticks=0,waited_ticks=0,last_processor=31,affinity=[31],affinity_proved=True)
        def records():
            value=dict(item,state='T' if clock['now']>=10.+delay else state)
            observations.append(value['state']);return [value]
        def sleep(value):clock['now']+=value
        with patch.object(s.time,'monotonic',side_effect=lambda:clock['now']),patch.object(s.time,'sleep',side_effect=sleep):
            result=s.await_owned_stop(records,stop_start=10.,inner_deadline=inner,active_ceiling=ceiling,
                cpu_upper=lambda now:initial+now-10.,heartbeat=beats.append,killed=lambda:False,
                context={'fixture_only':True,'monitor_affinity':[31],'session_id':123,'leader_start_ticks':45,'uid':os.getuid()})
        return result,beats,observations
    def test_delayed_nonterminal_state_is_never_accepted_before_coherent_stop(self):
        (items,waited),beats,observations=self.exercise(delay=.6)
        self.assertGreaterEqual(waited,.6);self.assertLess(waited,.602)
        self.assertIn('D',observations);self.assertTrue(all(item['state']=='T' for item in items))
        self.assertGreater(len(beats),100)
    def test_metadata_two_CPU_budget_aborts_before_blind_five_second_wait(self):
        ceiling=2-1.25-2/100
        with self.assertRaises(s.OwnedStopError) as caught:self.exercise(delay=9,ceiling=ceiling,initial=.2)
        witness=caught.exception.witness;self.assertEqual(witness['failure'],'STOP_WAIT_CPU_UPPER_BOUNDARY')
        self.assertLess(witness['elapsed_stop_wait_seconds'],.532)
        self.assertGreaterEqual(witness['one_core_CPU_upper'],ceiling)
        self.assertEqual(witness['exact_proved_owned_items'][0]['state'],'D')
        self.assertTrue(witness['states_are_not_accepted_for_accounting'])
    def test_original_inner_wall_clips_stop_wait(self):
        with self.assertRaises(s.OwnedStopError) as caught:self.exercise(delay=9,inner=10.05)
        witness=caught.exception.witness;self.assertEqual(witness['failure'],'STOP_WAIT_INNER_WALL')
        self.assertEqual(witness['stop_deadline_monotonic'],10.05)
        self.assertLessEqual(witness['elapsed_stop_wait_seconds'],.051)
    def test_five_second_ceiling_is_finite_and_does_not_accept_unknown_state(self):
        with self.assertRaises(s.OwnedStopError) as caught:self.exercise(delay=9,ceiling=100.)
        witness=caught.exception.witness;self.assertEqual(witness['failure'],'STOP_WAIT_WINDOW_EXHAUSTED')
        self.assertEqual(witness['stop_deadline_monotonic'],15.)
        self.assertIn('owned_stop_witness=',str(caught.exception))
    def test_wait_heartbeat_progress_is_frequent_across_guardian_stale_interval(self):
        _,beats,_=self.exercise(delay=1.2)
        self.assertGreater(beats[-1]-beats[0],1.)
        self.assertLess(max(b-a for a,b in zip(beats,beats[1:])),.00101)
    def test_first_snapshot_uses_floored_birth_lifetime_not_zero_CPU(self):
        with patch.object(s.time,'clock_gettime',return_value=100.75):
            self.assertAlmostEqual(s.one_core_stop_upper(None,None,10000,100,10.),.75)
        self.assertAlmostEqual(s.one_core_stop_upper(.3,9.8,10000,100,10.),.5)
        with self.assertRaisesRegex(RuntimeError,'anchor clock changed'):
            s.one_core_stop_upper(.3,10.1,10000,100,10.)
    def test_guardian_tick_sample_requires_immutable_identity_and_affinity(self):
        shared=bytearray(128);pid=os.getppid();shared[40:48]=struct.pack('Q',pid);shared[72:80]=struct.pack('Q',123)
        item=dict(pid=pid,uid=os.getuid(),start_ticks=123,own_ticks=10)
        with patch.object(s,'GUARD_SHARED',shared),patch.object(s,'process_record',return_value=item),patch.object(s.os,'sched_getaffinity',return_value={31}):
            self.assertEqual(s.guardian_self_upper(31,100),(.12000000000000001,.02))
        with patch.object(s,'GUARD_SHARED',shared),patch.object(s,'process_record',return_value=dict(item,start_ticks=124)):
            with self.assertRaisesRegex(RuntimeError,'identity changed'):s.guardian_self_upper(31,100)
        with patch.object(s,'GUARD_SHARED',shared),patch.object(s,'process_record',return_value=item),patch.object(s.os,'sched_getaffinity',return_value={30,31}):
            with self.assertRaisesRegex(RuntimeError,'affinity changed'):s.guardian_self_upper(31,100)


class BootstrapAnchorUnitTests(unittest.TestCase):
    def anchor(self, *, pid=123, birth=45, uid=None, core=31, ticks=100, when=10., cpu=.3):
        if uid is None: uid = os.getuid()
        values = (pid, birth, uid, core, ticks, when, cpu)
        return (s.BOOTSTRAP_ANCHOR_TAG, *values, s.bootstrap_anchor_digest(values))

    def test_tuple_sample_clock_rounding_and_mutations_fail_closed(self):
        anchor = self.anchor()
        self.assertEqual(s.bootstrap_anchor_fields(anchor, 31, 100, 11.), anchor)
        bad = [list(anchor), anchor[:-1], ('wrong', *anchor[1:]),
               self.anchor(when=float('nan')), self.anchor(cpu=float('inf')),
               self.anchor(when=12.), self.anchor(cpu=.019), self.anchor(uid=True),
               (anchor[0], *anchor[1:7], .31, anchor[8])]
        for value in bad:
            with self.subTest(value=repr(value)):
                with self.assertRaises(RuntimeError): s.bootstrap_anchor_fields(value, 31, 100, 11.)
        with self.assertRaises(RuntimeError): s.bootstrap_anchor_fields(anchor, 30, 100, 11.)
        with self.assertRaises(RuntimeError): s.bootstrap_anchor_fields(anchor, 31, 101, 11.)

    def test_capture_timestamps_before_counters_and_includes_actual_SELF_CPU(self):
        events = []; pid = os.getpid()
        item = dict(pid=pid, start_ticks=45, uid=os.getuid(), own_ticks=20, waited_ticks=0)
        def clock(): events.append('clock'); return 10.
        def usage(kind):
            if kind == resource.RUSAGE_SELF:
                self.assertIn('clock', events); events.append('counter')
                return SimpleNamespace(ru_utime=.1, ru_stime=.2)
            return SimpleNamespace(ru_utime=0., ru_stime=0.)
        with patch.object(s, 'process_record', return_value=item), \
             patch.object(s, 'children_of', return_value=set()), \
             patch.object(s.os, 'sched_getaffinity', return_value={31}), \
             patch.object(s.Path, 'iterdir', side_effect=lambda: iter([Path('one')])), \
             patch.object(s.resource, 'getrusage', side_effect=usage), \
             patch.object(s.time, 'monotonic', side_effect=clock):
            anchor = s.pre_fork_cpu_anchor(31, 100)
        self.assertEqual(anchor[6], 10.); self.assertAlmostEqual(anchor[7], .32)
        self.assertLess(events.index('clock'), events.index('counter'))

    def test_capture_rejects_threads_children_and_earlier_waited_CPU(self):
        pid = os.getpid()
        item = dict(pid=pid, start_ticks=45, uid=os.getuid(), own_ticks=0, waited_ticks=0)
        for thread_count, children, child_cpu, waited in [(2, set(), 0., 0), (1, {999}, 0., 0),
                                                         (1, set(), .01, 0), (1, set(), 0., 1)]:
            with self.subTest(thread_count=thread_count, children=children, child_cpu=child_cpu, waited=waited):
                with patch.object(s, 'process_record', return_value=dict(item, waited_ticks=waited)), \
                     patch.object(s, 'children_of', return_value=children), \
                     patch.object(s.os, 'sched_getaffinity', return_value={31}), \
                     patch.object(s.Path, 'iterdir', side_effect=lambda: iter([Path('one')] * thread_count)), \
                     patch.object(s.resource, 'getrusage', return_value=SimpleNamespace(ru_utime=child_cpu, ru_stime=0.)):
                    with self.assertRaises(RuntimeError): s.pre_fork_cpu_anchor(31, 100)

    def test_actual_guardian_identity_affinity_and_thread_count_are_bound(self):
        pid = os.getppid(); shared = bytearray(128)
        shared[40:48] = struct.pack('Q', pid); shared[72:80] = struct.pack('Q', 45)
        item = dict(pid=pid, start_ticks=45, uid=os.getuid())
        anchor = self.anchor(pid=pid)
        with patch.object(s, 'GUARD_SHARED', shared), patch.object(s, 'process_record', return_value=item), \
             patch.object(s.os, 'sched_getaffinity', return_value={31}), \
             patch.object(s.Path, 'iterdir', side_effect=lambda: iter([Path('one')])):
            self.assertEqual(s.validate_bootstrap_anchor(anchor, 31, 100, 11.), anchor)
            for changed in [self.anchor(pid=pid+1), self.anchor(pid=pid, birth=46),
                            self.anchor(pid=pid, uid=os.getuid()+1)]:
                with self.assertRaisesRegex(RuntimeError, 'identity changed'):
                    s.validate_bootstrap_anchor(changed, 31, 100, 11.)
        with patch.object(s, 'GUARD_SHARED', shared), patch.object(s, 'process_record', return_value=item), \
             patch.object(s.os, 'sched_getaffinity', return_value={30,31}):
            with self.assertRaisesRegex(RuntimeError, 'affinity or thread'):
                s.validate_bootstrap_anchor(anchor, 31, 100, 11.)

    def test_unknown_postanchor_interval_includes_validation_time(self):
        anchor = self.anchor()
        with patch.object(s, 'validate_bootstrap_anchor', return_value=anchor), \
             patch.object(s.time, 'monotonic', return_value=10.8):
            self.assertAlmostEqual(s.one_core_stop_upper(None, None, 45, 100, 10.5,
                bootstrap_anchor=anchor, core=31), 1.1)
        with patch.object(s, 'validate_bootstrap_anchor', return_value=anchor), \
             patch.object(s.time, 'monotonic', return_value=10.4):
            with self.assertRaisesRegex(RuntimeError, 'monotonic clock'):
                s.one_core_stop_upper(None, None, 45, 100, 10.5, bootstrap_anchor=anchor, core=31)


class BootstrapAnchorKernelTests(unittest.TestCase):
    def private_case(self, injection, *, cpu=4, wall=8, delayed_observation=False):
        source = Path(s.__file__).read_text()
        marker = '        bootstrap_anchor = pre_fork_cpu_anchor(core, ticks)'
        self.assertEqual(source.count(marker), 1)
        source = source.replace(marker, injection + '\n' + marker)
        if delayed_observation:
            anchor = '    return result\n\n\ndef guardian_self_upper'
            replacement = ('    until=globals().setdefault("PRIVATE_SYNTHETIC_STOP_UNTIL",time.monotonic()+1.1)\n'
                '    if time.monotonic()<until:\n'
                '        for item in result:item["state"]="D"\n'
                '    return result\n\n\ndef guardian_self_upper')
            self.assertEqual(source.count(anchor), 1); source = source.replace(anchor, replacement)
        with tempfile.TemporaryDirectory(prefix='pricefm_anchor_', dir='/dev/shm') as temporary:
            root = Path(temporary); private = root / 'supervisor.py'; private.write_text(source)
            marker_file = root / 'command_started'
            code = 'from pathlib import Path; Path(' + repr(str(marker_file)) + ').write_text("owned"); print("owned anchor proof")'
            argv = command(code, cpu=cpu, wall=wall); argv[3] = str(private)
            start = time.monotonic(); before = resource.getrusage(resource.RUSAGE_CHILDREN)
            result = subprocess.run(argv, capture_output=True, timeout=wall+5)
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            try: receipt = json.loads(result.stdout)
            except Exception: receipt = None
            proof = {'returncode': result.returncode, 'stdout': result.stdout.decode(errors='replace'),
                     'stderr': result.stderr.decode(errors='replace'), 'receipt': receipt,
                     'whole_observed_wall_seconds': time.monotonic()-start,
                     'observed_waited_CPU_seconds': after.ru_utime+after.ru_stime-before.ru_utime-before.ru_stime,
                     'command_started': marker_file.exists(), 'CPU_cap': cpu, 'wall_cap': wall,
                     'private_source_sha256': __import__('hashlib').sha256(source.encode()).hexdigest()}
            output = os.environ.get('PRICEFM_SUPERVISOR_PROOF_DIR')
            if output:
                directory = Path(output); directory.mkdir(parents=True, exist_ok=True)
                with (directory / (self._testMethodName+'.json')).open('x') as handle: json.dump(proof, handle, indent=2, sort_keys=True)
            return result, receipt, proof

    def assert_success(self, result, receipt, proof):
        self.assertEqual(result.returncode, 0, proof); self.assertIsInstance(receipt, dict, proof)
        self.assertTrue(receipt['all_owned_descendants_reaped'], proof)
        self.assertTrue(receipt['kernel_escape_filter'], proof)
        self.assertEqual(receipt['initial_bound_source'], 'PRE_FIRST_FORK_CPU_COUNTER_PLUS_ONE_CORE_WALL', proof)
        self.assertLess(receipt['aggregate_CPU_seconds'], proof['CPU_cap'], proof)
        self.assertLessEqual(receipt['complete_lifecycle_wall_seconds'], proof['wall_cap'], proof)

    def test_preanchor_wall_delay_does_not_replace_actual_CPU_but_preserves_wall(self):
        result, receipt, proof = self.private_case('        time.sleep(3.1)')
        self.assert_success(result, receipt, proof)
        self.assertGreater(proof['whole_observed_wall_seconds'], 3.1, proof)
        self.assertGreater(receipt['complete_lifecycle_wall_seconds'], 3.1, proof)
        self.assertLess(receipt['bootstrap_anchor']['startup_CPU_upper'], .73, proof)

    def test_actual_preanchor_CPU_is_included_in_immutable_sample(self):
        injection = '        private_cpu_start=time.process_time()\n        while time.process_time()-private_cpu_start<.25: pass'
        result, receipt, proof = self.private_case(injection)
        self.assert_success(result, receipt, proof)
        self.assertGreaterEqual(receipt['bootstrap_anchor']['startup_CPU_upper'], .25, proof)
        self.assertGreaterEqual(receipt['aggregate_CPU_seconds'], .25, proof)

    def test_preanchor_wall_exhaustion_rejects_before_any_child_command(self):
        result, receipt, proof = self.private_case('        time.sleep(3.1)', wall=4)
        self.assertNotEqual(result.returncode, 0, proof); self.assertFalse(proof['command_started'], proof)
        self.assertIn('three-second drain reserve', proof['stderr'], proof)
        self.assertLess(proof['whole_observed_wall_seconds'], 4.5, proof)

    def test_postanchor_unknown_interval_is_charged_and_refused_at_original_cap(self):
        result, receipt, proof = self.private_case('        pass', cpu=2, delayed_observation=True)
        self.assertEqual(result.returncode, 125, proof); self.assertTrue(receipt['all_owned_descendants_reaped'], proof)
        witness = receipt['owned_stop_witness']
        self.assertEqual(witness['failure'], 'STOP_WAIT_CPU_UPPER_BOUNDARY', proof)
        self.assertEqual(witness['initial_bound_source'], 'PRE_FIRST_FORK_CPU_COUNTER_PLUS_ONE_CORE_WALL', proof)
        self.assertGreaterEqual(witness['one_core_CPU_upper'], witness['CPU_active_ceiling'], proof)
        self.assertLess(receipt['aggregate_CPU_seconds'], 2, proof)
        self.assertTrue(witness['states_are_not_accepted_for_accounting'], proof)

    def test_mutated_sample_fails_before_command_spawn(self):
        injection = '        pass'
        source = Path(s.__file__).read_text()
        marker = '        bootstrap_anchor = pre_fork_cpu_anchor(core, ticks)'
        changed = marker + '\n        bootstrap_anchor=(bootstrap_anchor[0],bootstrap_anchor[1]+1,*bootstrap_anchor[2:])'
        with patch.object(s.Path, 'read_text', return_value=source.replace(marker, changed)):
            result, receipt, proof = self.private_case(injection)
        self.assertEqual(result.returncode, 125, proof); self.assertFalse(proof['command_started'], proof)
        self.assertTrue(receipt['all_owned_descendants_reaped'], proof)
        self.assertIn('bootstrap anchor', receipt['cap_reason'], proof)


if __name__ == '__main__': unittest.main()
