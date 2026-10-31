"""Metadata/mocked regressions for r176; no child, burn, R or kernel proof."""
import ast
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from . import startup_stop_candidate as c
from . import startup_stop_helper as adapter
from . import startup_helper_tests as legacy_tests
from . import startup_batch_tests as legacy_batch_tests
from . import startup_batch_stop as controller
from . import startup_batch_stop_worker as worker
from . import startup_batch_stop_kernel as kernel


class PolicyTests(unittest.TestCase):
    def test_original_guard_is_byte_identical(self):
        path, raw = c.verified_original()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), c.ORIGINAL_SHA256)
        self.assertEqual(path.name, "profile_supervisor.py")

    def test_only_three_reviewed_decision_expressions_change(self):
        _, raw = c.verified_original()
        original = next(x for x in ast.parse(raw).body if isinstance(x,ast.FunctionDef) and x.name == "run")
        text = ast.get_source_segment(raw.decode(), original)
        # Independent textual expectation over the complete frozen run body.
        self.assertEqual(text.count("cpu >= active_ceiling"), 2)
        expected = text.replace("cpu >= active_ceiling", "cpu >= active_ceiling - 0.25")
        self.assertEqual(expected.count("time.monotonic() >= deadline"), 1)
        expected = expected.replace("time.monotonic() >= deadline", "time.monotonic() >= deadline - 0.25")
        run = next(x for x in ast.parse(expected).body if isinstance(x,ast.FunctionDef) and x.name == "run")
        actual = c.candidate_run_ast(raw).body[0]
        self.assertEqual(ast.dump(actual,include_attributes=False), ast.dump(run,include_attributes=False))

    def test_missing_or_extra_comparator_fails_closed(self):
        _, raw = c.verified_original()
        for changed in (raw.replace(b"cpu >= active_ceiling", b"cpu > active_ceiling", 1),
                        raw.replace(b"cpu >= active_ceiling", b"cpu >= active_ceiling or cpu >= active_ceiling", 1)):
            with self.assertRaisesRegex(ValueError,"three decision-comparator"):
                c.candidate_run_ast(changed)

    def test_valid_thresholds_preserve_stop_reserve(self):
        self.assertEqual(c.decision_thresholds(2.73,100.),(2.48,99.75))
        for active in (.73,2.73,28.73):
            cpu, wall = c.decision_thresholds(active,100.)
            self.assertLess(cpu,active)
            self.assertEqual(active-cpu,.25)
            self.assertEqual(wall,99.75)

    def test_nonfinite_boolean_or_unfunded_thresholds_rejected(self):
        for active, deadline in ((float("nan"),100.),(3.,float("inf")),(True,100.),(.25,100.),(2.,.1)):
            with self.assertRaises(ValueError):
                c.decision_thresholds(active,deadline)

    def test_different_or_linked_original_source_rejected(self):
        with tempfile.TemporaryDirectory(prefix="r176_source_metadata_") as directory:
            root = Path(directory)
            wrong = root/"wrong.py"; wrong.write_text("# not the frozen source\n")
            with self.assertRaisesRegex(ValueError,"bytes differ"):
                c.verified_original(wrong)
            linked = root/"linked.py"; linked.symlink_to(c.verified_original()[0])
            with self.assertRaisesRegex(ValueError,"canonical"):
                c.verified_original(linked)

    def test_import_candidate_creates_no_child(self):
        with patch.object(c.os,"fork",side_effect=AssertionError("metadata cannot fork")):
            guard = c.load_candidate()
            self.assertEqual(guard.BOOTSTRAP_ANCHOR_TAG,"OWNED_PRE_FIRST_FORK_CPU_AND_WAITED_MONOTONIC_V2")

    def test_original_stop_upper_boundary_remains_failure(self):
        guard = c.load_candidate()
        for state in ("R","D","S"):
            with self.subTest(state=state), patch.object(guard.time,"monotonic",return_value=1.):
                with self.assertRaises(guard.OwnedStopError) as failure:
                    guard.await_owned_stop(lambda:[{"state":state}],stop_start=1.,inner_deadline=20.,
                        active_ceiling=2.73,cpu_upper=lambda now:2.73,heartbeat=lambda now:None,
                        context={},killed=lambda:False)
                self.assertEqual(failure.exception.witness["failure"],"STOP_WAIT_CPU_UPPER_BOUNDARY")

    def test_original_stop_window_remains_failure(self):
        guard = c.load_candidate()
        with patch.object(guard.time,"monotonic",return_value=6.):
            with self.assertRaises(guard.OwnedStopError) as failure:
                guard.await_owned_stop(lambda:[{"state":"R"}],stop_start=1.,inner_deadline=20.,
                    active_ceiling=2.73,cpu_upper=lambda now:0.,heartbeat=lambda now:None,
                    context={},killed=lambda:False)
            self.assertEqual(failure.exception.witness["failure"],"STOP_WAIT_WINDOW_EXHAUSTED")

    def test_original_stopped_states_only(self):
        guard = c.load_candidate()
        for state in ("T","t","Z"):
            with self.subTest(state=state),patch.object(guard.time,"monotonic",return_value=1.):
                items, waited = guard.await_owned_stop(lambda:[{"state":state}],stop_start=1.,inner_deadline=20.,
                    active_ceiling=2.73,cpu_upper=lambda now:3.,heartbeat=lambda now:None,
                    context={},killed=lambda:False)
                self.assertEqual(items,[{"state":state}])
                self.assertEqual(waited,0.)

    def test_unmodified_guardian_and_other_original_functions(self):
        path, raw = c.verified_original()
        namespace = {};exec(compile(raw,str(path),"exec"),namespace)
        candidate = c.load_candidate()
        for name in ("guarded_run","await_owned_stop","one_core_stop_upper","guardian_SELF_boundary",
                     "inherited_monitor_SELF_cap","session_records","child_guard"):
            with self.subTest(name=name):
                self.assertEqual(getattr(candidate,name).__code__.co_code,namespace[name].__code__.co_code)

    def test_receipt_requires_exact_candidate_policy(self):
        value = dict(supervision_profile=c.PROFILE,original_supervisor_sha256=c.ORIGINAL_SHA256,
                     conservative_stop_policy=c.policy(),CPU_active_ceiling=2.73,CPU_decision_ceiling=2.48)
        c.require_candidate_receipt(value)
        for key in ("supervision_profile","original_supervisor_sha256","conservative_stop_policy","CPU_decision_ceiling"):
            broken = dict(value);broken.pop(key)
            with self.assertRaises(ValueError):
                c.require_candidate_receipt(broken)

    def test_explicit_staging_closure_and_frozen_original_pins(self):
        for name in ("startup_stop_candidate.py","startup_stop_helper.py","startup_batch_stop.py",
                     "startup_batch_stop_worker.py","startup_batch_stop_kernel.py"):
            self.assertIn(name,controller.NAMES)
        root = Path(__file__).absolute().parent
        for name,digest in worker.FROZEN_RUNTIME_SOURCES.items():
            self.assertEqual(hashlib.sha256((root/name).read_bytes()).hexdigest(),digest)
        closure = adapter.source_pins("R_STARTUP_METADATA_ONLY")
        self.assertEqual(Path(closure["adapter"]["path"]).name,"startup_stop_helper.py")
        self.assertEqual(Path(closure["supervisor"]["path"]).name,"startup_stop_candidate.py")
        self.assertEqual(closure["original_supervisor"]["sha256"],c.ORIGINAL_SHA256)

    def test_profile_receipt_required_only_when_monitor_can_return(self):
        for expected in ("SUCCESS","CPU_BOUNDARY","WALL_BOUNDARY"):
            self.assertTrue(kernel.candidate_receipt_required(expected))
        for expected in ("MONITOR_DEATH","GUARDIAN_DEATH"):
            self.assertFalse(kernel.candidate_receipt_required(expected))
        with self.assertRaises(ValueError):
            kernel.candidate_receipt_required("UNKNOWN")


class CandidateAdapterMetadataTests(legacy_tests.MetadataTests):
    """Exercise the established adapter gates with the new source closure."""
    def setUp(self):
        change = patch.object(legacy_tests,"h",adapter)
        change.start();self.addCleanup(change.stop)
        super().setUp()

    def fake_guard(self):
        value = super().fake_guard()
        value.update(supervision_profile=c.PROFILE,original_supervisor_sha256=c.ORIGINAL_SHA256,
                     conservative_stop_policy=c.policy(),CPU_active_ceiling=2.73,CPU_decision_ceiling=2.48)
        return value

    def test_fixture_alone_never_accepted(self):
        self.intent()
        with self.assertRaisesRegex(ValueError,"candidate receipt"):
            adapter.finalize(self.pp,self.ap,self.rp,self.save("fixture-only.json",{"status":"PASS"}))

    def test_failed_intent_publication_prevents_exec(self):
        # Launch executes in the privately loaded frozen adapter namespace.
        # A module-level test double on this forwarding module would not patch
        # that implementation's global, so inject the failure at its writer.
        with patch.object(adapter.os,"sched_getaffinity",return_value={31}), \
             patch.object(adapter._base,"write_new",side_effect=OSError("injected publication failure")):
            execute = unittest.mock.Mock()
            with self.assertRaises(OSError):
                adapter.launch(self.pp,self.ap,self.rp,CLI_CPU=4,CLI_wall=20,execute=execute)
            execute.assert_not_called()

    def test_receipt_from_old_profile_never_finalizes_R_or_helper(self):
        guard = self.fake_guard();guard.pop("supervision_profile")
        with self.assertRaisesRegex(ValueError,"candidate receipt"):
            adapter.finalize(self.pp,self.ap,self.rp,self.save("old-profile.json",guard))


class CandidateProtocolTests(legacy_batch_tests.ProtocolTests):
    """Run transport/publication/accounting regressions against the new lane."""
    def setUp(self):
        for name,value in (("b",controller),("w",worker)):
            change = patch.object(legacy_batch_tests,name,value)
            change.start();self.addCleanup(change.stop)
        super().setUp()

    def test_new_packet_stages_and_executes_exact_candidate_worker(self):
        source = Path(__file__).absolute().parent
        scope = self.save(self.base/"scope.json",{"expires_epoch":2000000000.})
        publication = self.save(self.base/"publication.json",{"commit":"b"*40})
        review = self.save(self.base/"review.json",{"status":"UNIT_DOUBLE_NOT_AUTHORITY"})
        registry = self.base/"candidate_registry";registry.mkdir()
        config = dict(source_dir=str(source),remote_namespace="/mnt/beegfs/home/jaguir26/pricefm_r176_unit",
                      scope=scope,publication=publication,source_review=review,
                      cached_python="/mnt/beegfs/home/jaguir26/pricefm_unit/runtime/venv/bin/python",
                      cached_python_sha256="c"*64,node="node-13")
        hashes = {name:controller.digest(source/name) for name in controller.NAMES}
        packet = controller.prepare(config,{"expires_epoch":2000000000.},controller.ROLES[0],hashes,registry)
        root = registry/controller.ROLES[0]/"packet"
        spec = json.loads((root/"SPEC.json").read_text())
        script = (root/"job.sbatch").read_text()
        self.assertEqual(set(spec["sources"]),set(controller.NAMES))
        self.assertIn("/startup_batch_stop_worker.py",script)
        self.assertNotIn("/startup_batch_worker.py",script)
        for name in controller.NAMES:
            self.assertEqual(hashlib.sha256((root/"package/pricefm_hb"/name).read_bytes()).hexdigest(),hashes[name])
            self.assertEqual(spec["sources"][name]["sha256"],hashes[name])
        self.assertEqual(packet["sources"],spec["sources"])


if __name__ == "__main__":
    unittest.main()
