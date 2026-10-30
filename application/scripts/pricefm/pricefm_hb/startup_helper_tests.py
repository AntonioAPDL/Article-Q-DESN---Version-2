"""Metadata-only negative/intent/finalization tests; no children or R are run.

Guard/review objects below are explicit temporary test doubles.  They never
constitute a real independent source review or kernel/runtime qualification.
"""
import copy
import hashlib
import json
import os
from pathlib import Path
import signal
import tempfile
import time
import unittest
from unittest.mock import patch

from . import startup_helper as h
from . import startup_helper_kernel_tests as k


class ExecReached(Exception):
    pass


class MetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pricefm_startup_unit_")
        self.root = Path(self.temp.name)
        self.python = self.root / "private_fake_python"
        self.python.write_bytes(b"\x7fELFexplicit-unit-test-double-not-executable")
        self.now = time.time()
        self.scope = self.save("scope.json", {"status": "PROSPECTIVE_PRICEFM_CONTINUATION_IMPLEMENTATION_SCOPE",
                                               "issued_epoch": self.now - 2, "expires_epoch": self.now + 3600})
        self.plan = dict(schema="pricefm_startup_helper_plan_v1", role="SYNTHETIC_OWNED_HELPER",
            nonce="a" * 32, sources=h.source_pins("SYNTHETIC_OWNED_HELPER"),
            limits=dict(CPU=4, wall=20, output_cap=4096), case="wait_and_escape",
            placement=dict(kind="ADMINISTRATIVE_SYNTHETIC", CPU=31, hostname=os.uname().nodename),
            environment=dict(**{x: "1" for x in h.THREAD_KEYS}, PATH="/usr/bin:/bin", LC_ALL="C"),
            supervisor_python=h.pin(self.python), runtime=dict(kind="PYTHON_METADATA", executable=h.pin(self.python)),
            runtime_files=[], output_dir=str(self.root / "output"))
        self.plan["command"] = [str(self.python), "-I", "-B", self.plan["sources"]["fixture"]["path"],
                                "--case", self.plan["case"], "--nonce", self.plan["nonce"]]
        self.bind()

    def tearDown(self):
        self.temp.cleanup()

    def save(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value, sort_keys=True))
        return h.pin(path)

    def bind(self):
        self.pp = self.save("plan.json", self.plan)
        self.review = dict(status="PASS_REVIEWED_STARTUP_HELPER_SOURCE_AND_PLAN", plan=self.pp,
                           sources=self.plan["sources"], limits=self.plan["limits"])
        self.rp = self.save("review.json", self.review)
        self.authority = dict(schema="pricefm_startup_helper_authority_v1",
            status="ROOT_AUTHORIZED_SOURCE_BOUND_STARTUP_HELPER_PROOF", plan=self.pp, source_review=self.rp,
            role=self.plan["role"], sources=self.plan["sources"], limits=self.plan["limits"],
            placement=self.plan["placement"], executions=1, no_real_target_data_or_optimizer=True,
            root_scope=self.scope, issued_epoch=self.now - 1, expires_epoch=self.now + 1800,
            allowed_output_parent=str(self.root))
        self.ap = self.save("authority.json", self.authority)

    def validate(self, **kw):
        return h.validate(self.pp, self.ap, self.rp, now=self.now, affinity={31}, **kw)

    def R_plan(self):
        self.scope = self.save("scope.json", dict(status="PROSPECTIVE_PRICEFM_STARTUP_COMPUTE_QUALIFICATION_SCOPE",
                                                 issued_epoch=self.now - 2, expires_epoch=self.now + 3600))
        self.plan["role"] = "R_STARTUP_METADATA_ONLY"
        self.plan["sources"] = h.source_pins(self.plan["role"])
        self.plan["placement"] = dict(kind="SLURM_SINGLE_CPU_METADATA", job_id="123456", node="node-13")
        home = self.root / "R_HOME"; home.mkdir()
        uname = h.pin(Path("/usr/bin/uname").resolve(strict=True))
        which = h.pin(Path("/usr/bin/which").resolve(strict=True))
        self.plan["runtime"] = dict(kind="NATIVE_R_METADATA", executable=h.pin(self.python),
            version="4.6.0", R_home=str(home), uname=uname, which=which,
            helper_aliases=[dict(logical_path="/usr/bin/uname", resolved_file=uname),
                            dict(logical_path="/usr/bin/which", resolved_file=which)])
        self.plan["runtime_files"] = [uname, which]
        self.plan["environment"].update(R_HOME=str(home), SLURM_JOB_ID="123456",
                                        SLURMD_NODENAME="node-13", SLURM_CPUS_PER_TASK="1")
        self.plan["command"] = [str(self.python), "--vanilla", "--slave", "--no-save", "--no-restore",
            "--file=" + self.plan["sources"]["fixture"]["path"], "--args", self.plan["nonce"]]
        self.bind()
        return dict(SLURM_JOB_ID="123456", SLURMD_NODENAME="node-13", SLURM_CPUS_PER_TASK="1")

    def intent(self):
        with patch.object(h.os, "sched_getaffinity", return_value={31}):
            with self.assertRaises(ExecReached):
                h.launch(self.pp, self.ap, self.rp, CLI_CPU=4, CLI_wall=20,
                         execute=lambda *_: (_ for _ in ()).throw(ExecReached()))
        return h.read(h.pin(self.root / "output/execution_intent.json"))

    def fake_guard(self):
        intent = self.intent()
        fixture = dict(status="PASS_SYNTHETIC_OWNED_HELPER_FIXTURE", role=self.plan["role"],
            case=self.plan["case"], nonce=self.plan["nonce"], models=0, optimizer_invocations=0,
            scientific_data_read=False, helper_wait_status=0, escape_operations_denied=3,
            deliberate_nonzero_helper_status_observed=7)
        guard = dict(returncode=0, command_returncode=0, cap_reason=None, CPU_limit=4,
            aggregate_CPU_seconds=.2, complete_lifecycle_wall_seconds=1., stderr="", stdout=json.dumps(fixture),
            reaped=[dict(pid=1000000, returncode=0)],
            guardian_forced_monitor_stop=False,
            bootstrap_anchor=dict(guardian_pid=intent["process_pid"], guardian_birth_ticks=intent["process_birth_ticks"]))
        for name in ("all_owned_descendants_reaped", "kernel_escape_filter", "orphan_subreaper",
                     "guardian_included_in_CPU", "independent_guardian", "guardian_nondumpable",
                     "inherited_waited_history_included_once"):
            guard[name] = True
        return guard

    def test_valid_metadata_no_fork(self):
        with patch.object(os, "fork", side_effect=AssertionError("unit tests cannot fork")):
            self.assertEqual(self.validate()["plan"], self.plan)

    def test_source_change_rejected(self):
        self.plan["sources"]["fixture"]["sha256"] = "0" * 64; self.bind()
        with self.assertRaisesRegex(ValueError, "source closure"):
            self.validate()

    def test_expired_authority_rejected(self):
        self.authority["expires_epoch"] = self.now
        self.ap = self.save("authority.json", self.authority)
        with self.assertRaisesRegex(ValueError, "expired"):
            self.validate()

    def test_boolean_execution_count_rejected(self):
        self.authority["executions"] = True; self.ap = self.save("authority.json", self.authority)
        with self.assertRaisesRegex(ValueError, "one metadata"):
            self.validate()

    def test_false_independent_review_rejected(self):
        self.review["status"] = "PREPARED_NOT_REVIEWED"; self.rp = self.save("review.json", self.review)
        with self.assertRaisesRegex(ValueError, "independent"):
            self.validate()

    def test_helper_environment_patch_rejected(self):
        self.plan["environment"]["R_DEFAULT_PACKAGES"] = "NULL"; self.bind()
        with self.assertRaisesRegex(ValueError, "allowlisted"):
            self.validate()

    def test_multithread_environment_rejected(self):
        self.plan["environment"]["OMP_NUM_THREADS"] = "2"; self.bind()
        with self.assertRaisesRegex(ValueError, "single-thread"):
            self.validate()

    def test_changed_exact_argv_rejected(self):
        self.plan["command"].append("another-path"); self.bind()
        with self.assertRaisesRegex(ValueError, "argv differs"):
            self.validate()

    def test_runtime_file_type_rejected_before_reads(self):
        self.plan["runtime_files"] = "not-a-list"; self.bind()
        with self.assertRaisesRegex(ValueError, "bounded runtime"):
            self.validate()

    def test_changed_hash_rejected(self):
        self.python.write_bytes(b"\x7fELFchanged")
        with self.assertRaisesRegex(ValueError, "pinned bytes"):
            self.validate()

    def test_large_runtime_pin_needs_explicit_bound(self):
        path = self.root / "synthetic_runtime.so"
        with path.open("wb") as handle:
            handle.seek(17 * 1024**2 - 1); handle.write(b"\0")
        with self.assertRaisesRegex(ValueError, "bounded pin"):
            h.pin(path)
        value = h.pin(path, 20 * 1024**2)
        self.assertEqual(len(h.read_pin(value, 20 * 1024**2)), 17 * 1024**2)

    def test_symlink_rejected(self):
        alias = self.root / "alias"; alias.symlink_to(self.python)
        with self.assertRaisesRegex(ValueError, "symlink"):
            h.read_pin(dict(path=str(alias), sha256=h.pin(self.python)["sha256"]))

    def test_duplicate_json_rejected(self):
        with self.assertRaisesRegex(ValueError, "duplicate"):
            h.strict_json('{"x":1,"x":2}')

    def test_nonfinite_json_rejected(self):
        with self.assertRaisesRegex(ValueError, "nonfinite"):
            h.strict_json('{"x":NaN}')

    def test_wrong_cpu_rejected(self):
        with self.assertRaisesRegex(ValueError, "host/CPU"):
            h.validate(self.pp, self.ap, self.rp, now=self.now, affinity={30})

    def test_wrong_host_rejected(self):
        with self.assertRaisesRegex(ValueError, "host/CPU"):
            self.validate(hostname="another-private-host")

    def test_create_only_execution_intent(self):
        intent = self.intent()
        self.assertTrue(intent["no_child_created_by_adapter"])
        self.assertEqual(intent["process_pid"], os.getpid())
        with self.assertRaisesRegex(ValueError, "create-only"):
            self.validate()

    def test_failed_intent_publication_prevents_exec(self):
        with patch.object(h.os, "sched_getaffinity", return_value={31}), \
             patch.object(h, "write_new", side_effect=OSError("unit injected publication failure")):
            execute = unittest.mock.Mock()
            with self.assertRaises(OSError):
                h.launch(self.pp, self.ap, self.rp, CLI_CPU=4, CLI_wall=20, execute=execute)
            execute.assert_not_called()

    def test_success_is_synthetic_not_R_or_production(self):
        gp = self.save("guard.json", self.fake_guard())
        value = h.finalize(self.pp, self.ap, self.rp, gp)
        self.assertEqual(value["status"], "PASS_SYNTHETIC_OWNED_HELPER_CASE_NOT_R_STARTUP")
        self.assertFalse(value["R_startup_proved"] or value["numerical_parity_proved"] or value["production_ready"])

    def test_nonzero_guard_never_finalizes(self):
        guard = self.fake_guard(); guard["command_returncode"] = 7
        with self.assertRaisesRegex(ValueError, "guardian command must pass"):
            h.finalize(self.pp, self.ap, self.rp, self.save("guard.json", guard))

    def test_false_drain_rejected(self):
        guard = self.fake_guard(); guard["all_owned_descendants_reaped"] = False
        with self.assertRaisesRegex(ValueError, "guarantees"):
            h.finalize(self.pp, self.ap, self.rp, self.save("guard.json", guard))

    def test_stale_guard_pid_rejected(self):
        guard = self.fake_guard(); guard["bootstrap_anchor"]["guardian_pid"] += 1
        with self.assertRaisesRegex(ValueError, "PID/birth"):
            h.finalize(self.pp, self.ap, self.rp, self.save("guard.json", guard))

    def test_stale_guard_birth_rejected(self):
        guard = self.fake_guard(); guard["bootstrap_anchor"]["guardian_birth_ticks"] += 1
        with self.assertRaisesRegex(ValueError, "PID/birth"):
            h.finalize(self.pp, self.ap, self.rp, self.save("guard.json", guard))

    def test_boolean_zero_models_rejected(self):
        guard = self.fake_guard(); value = json.loads(guard["stdout"]); value["models"] = False
        guard["stdout"] = json.dumps(value)
        with self.assertRaisesRegex(ValueError, "metadata-only"):
            h.finalize(self.pp, self.ap, self.rp, self.save("guard.json", guard))

    def test_fixture_alone_never_accepted(self):
        self.intent()
        with self.assertRaises(KeyError):
            h.finalize(self.pp, self.ap, self.rp, self.save("fixture-only.json", {"status": "PASS"}))

    def test_finalization_revalidates_root_authority(self):
        guard = self.fake_guard(); self.authority["status"] = "UNADMITTED"
        self.ap = self.save("authority.json", self.authority)
        with self.assertRaisesRegex(ValueError, "root startup authority"):
            h.finalize(self.pp, self.ap, self.rp, self.save("guard.json", guard))

    def test_arbitrary_expiry_json_is_not_root_scope(self):
        self.scope = self.save("scope.json", dict(status="ARBITRARY", issued_epoch=self.now - 2,
                                                 expires_epoch=self.now + 3600))
        self.bind()
        with self.assertRaisesRegex(ValueError, "purpose-specific"):
            self.validate()

    def test_expired_finalization_rejected(self):
        guard = self.fake_guard()
        with patch.object(h.time, "time", return_value=self.now + 2000):
            with self.assertRaisesRegex(ValueError, "finalization cannot extend"):
                h.finalize(self.pp, self.ap, self.rp, self.save("guard.json", guard))

    def test_boolean_guard_zero_rejected(self):
        guard = self.fake_guard(); guard["returncode"] = False
        with self.assertRaisesRegex(ValueError, "guardian command"):
            h.finalize(self.pp, self.ap, self.rp, self.save("guard.json", guard))

    def test_guard_failure_is_not_relabelled_success(self):
        guard = self.fake_guard(); guard["reaped"].append(dict(pid=1000001, returncode=-9))
        with self.assertRaisesRegex(ValueError, "failed adopted helper"):
            h.finalize(self.pp, self.ap, self.rp, self.save("guard.json", guard))

    def test_fake_Slurm_environment_on_Muscat_is_rejected(self):
        env = self.R_plan()
        with self.assertRaisesRegex(ValueError, "actual Slurm compute host"):
            h.validate(self.pp, self.ap, self.rp, now=self.now, affinity={30}, environ=env,
                       hostname="muscat.be.ucsc.edu")

    def test_HB_allocated_CPU31_is_not_Muscat_admin_CPU31(self):
        env = self.R_plan()
        # The fake ELF is never executed: this tests only metadata placement.
        value = h.validate(self.pp, self.ap, self.rp, now=self.now, affinity={31}, environ=env,
                           hostname="node-13")
        self.assertEqual(value["plan"]["role"], "R_STARTUP_METADATA_ONLY")

    def test_R_version_substitution_rejected(self):
        env = self.R_plan(); self.plan["runtime"]["version"] = "4.4.1"; self.bind()
        with self.assertRaisesRegex(ValueError, "R4.6.0"):
            h.validate(self.pp, self.ap, self.rp, now=self.now, affinity={0}, environ=env, hostname="node-13")

    def test_R_replacement_environment_cannot_lose_job_identity(self):
        env = self.R_plan(); self.plan["environment"].pop("SLURM_JOB_ID"); self.bind()
        with self.assertRaisesRegex(ValueError, "replacement R environment"):
            h.validate(self.pp, self.ap, self.rp, now=self.now, affinity={0}, environ=env, hostname="node-13")


class KernelMetadataTests(unittest.TestCase):
    def signal_case(self, changed=None):
        item = dict(pid=1000000, uid=os.getuid(), ppid=999999, start_ticks=100)
        current = dict(item); current.update(changed or {})
        with patch.object(k, "pidfd_open", return_value=42), \
             patch.object(k.os, "close"), \
             patch.object(k, "process_record", return_value=current), \
             patch.object(k, "pidfd_kill") as send:
            if changed:
                with self.assertRaisesRegex(ValueError, "stale or non-owned"):
                    k.kill_proved(item, {999999})
                send.assert_not_called()
            else:
                k.kill_proved(item, {999999})
                send.assert_called_once_with(42)

    def test_exact_owned_pidfd_target_metadata(self):
        self.signal_case()

    def test_stale_pid_birth_never_signalled(self):
        self.signal_case(dict(start_ticks=101))

    def test_nonowned_parent_never_signalled(self):
        self.signal_case(dict(ppid=123))

    def test_nonowned_UID_never_signalled(self):
        self.signal_case(dict(uid=os.getuid() + 1))

    def test_preparation_has_no_authority_or_execution(self):
        with tempfile.TemporaryDirectory(prefix="pricefm_kernel_prepare_unit_") as directory:
            root = Path(directory); native = root / "fake_native"
            native.write_bytes(b"\x7fELFtest-double-not-executed")
            with patch.object(os, "fork", side_effect=AssertionError("preparation cannot fork")):
                value = k.prepare(root / "proposals", native)
            proposal = h.read(value)
            self.assertEqual(proposal["status"], "PREPARED_SYNTHETIC_KERNEL_PLANS_NOT_AUTHORIZED_OR_EXECUTED")
            self.assertEqual(proposal["total_CPU_reservation"], 30)
            self.assertEqual(len(proposal["cases"]), 6)
            self.assertFalse(any("authority" in row or "review" in row for row in proposal["cases"]))

    def test_pidfd_API_unavailable_fails_closed_without_signal_fallback(self):
        fake = unittest.mock.Mock()
        fake.syscall.return_value = -1
        with patch.object(k.ctypes, "CDLL", return_value=fake), \
             patch.object(k.ctypes, "get_errno", return_value=38), \
             patch.object(k.os, "kill") as arbitrary:
            with self.assertRaisesRegex(OSError, "no numeric-PID signal fallback"):
                k.pidfd_open(1000000)
            arbitrary.assert_not_called()

    def test_self_probe_has_only_zero_signal_and_closes_own_fd(self):
        fake = unittest.mock.Mock(); fake.syscall.return_value = 0
        with patch.object(k, "pidfd_open", return_value=42), \
             patch.object(k.ctypes, "CDLL", return_value=fake), \
             patch.object(k.os, "close") as close:
            result = k.self_pidfd_probe()
            arguments = fake.syscall.call_args.args
            self.assertEqual(arguments[0].value, 424)
            self.assertEqual(arguments[2].value, 0)
            close.assert_called_once_with(42)
            self.assertTrue(result["no_child_or_termination_signal"])

    def test_failed_self_probe_stops_before_child_cases(self):
        fake = unittest.mock.Mock(); fake.syscall.return_value = -1
        with patch.object(k, "pidfd_open", return_value=42), \
             patch.object(k.ctypes, "CDLL", return_value=fake), \
             patch.object(k.ctypes, "get_errno", return_value=38), \
             patch.object(k.os, "close") as close, \
             patch.object(k.subprocess, "Popen") as create:
            with self.assertRaisesRegex(OSError, "no child cases"):
                k.self_pidfd_probe()
            close.assert_called_once_with(42)
            create.assert_not_called()

if __name__ == "__main__":
    unittest.main()
