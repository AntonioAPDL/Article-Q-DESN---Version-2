"""Mocked cost-worker tests; never import NumPy or execute scientific kernels."""
from __future__ import annotations

import builtins
import ast
import copy
import datetime as dt
import hashlib
import math
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from . import benchmark as b
from . import benchmark_plan as p
from .benchmark_plan_tests import metadata
from .fixture import digest, write_json


class Prediction:
    def __init__(self, value):
        self.value = value

    def copy(self):
        return Prediction(self.value)


class PanelTests(unittest.TestCase):
    def setup_panel(self, study="FI", warm_failure=False):
        config, prep = metadata(study)
        for task in prep["tasks"]:
            task["spec"] = {"region": task["region"]}
        plan = dict(study=study, schedule=p.make_schedule(study, config, prep))
        observed, contexts, counts, retained_flags = [], [], {}, []
        budget = SimpleNamespace(check=Mock(), receipt=dict(lease_expires_epoch=time.time() + 1200))
        def context(task):
            contexts.append((task["mode"], task["package_id"]))
            return dict(name=task["name"])
        def predict(context, task, descriptor, beat):
            key = task["name"]
            counts[key] = counts.get(key, 0) + 1
            observed.append(("predict", task["mode"], task["package_id"]))
            value = key + ("changed" if warm_failure and task["mode"] == "D" and task["package_id"] == "C0" and counts[key] == 2 else "")
            return Prediction(value), "truth", dict(paths=100)
        def replay(context, task, descriptor, prediction, truth):
            observed.append(("replay", task["mode"], task["package_id"]))
            return dict(status="PASS_ACTUAL_C0_ORIGINAL_MATH_REPLAY")
        def retained(context, task, descriptor, prediction, truth, compute_loss=True):
            retained_flags.append(compute_loss)
            if compute_loss is not False:
                raise AssertionError("candidate AQL would be computed")
            observed.append(("retain", task["mode"], task["package_id"]))
            return dict(origin_AQL="zero without loss evaluation")
        metric = Mock(side_effect=AssertionError("metric function must not be called"))
        adapter = SimpleNamespace(context=context, predict=predict, control_replay=replay, retained_arrays=retained,
            preflight=Mock(return_value=dict(parents=p.COUNTS[study]["parents"], records=[])),
            pools=lambda: [dict(num_threads=1)], cleanup=Mock(), metric=metric)
        def serializer(path, arrays):
            path.write_bytes(repr(arrays).encode())
        return plan, prep, adapter, budget, observed, contexts, retained_flags, serializer

    def test_complete_exact_panel_no_loss_and_control_before_serialization(self):
        for study in ("FI", "DK2"):
            plan, prep, adapter, budget, observed, contexts, flags, serialize = self.setup_panel(study)
            with tempfile.TemporaryDirectory() as directory:
                result = b.timing_panel(plan, prep, adapter, budget, directory, serialize, lambda a, old: a.value == old.value)
                self.assertEqual(len(list(Path(directory).glob("*.npz"))), 16)
            self.assertEqual(result["arithmetic_calls"], 18)
            self.assertEqual(result["numerical_preflight"]["parents"], p.COUNTS[study]["parents"])
            self.assertEqual([call["sequence"] for call in result["calls"]], list(range(1, 19)))
            self.assertEqual(observed[:3], [("predict", "D", "C0"), ("replay", "D", "C0"), ("retain", "D", "C0")])
            s0 = observed.index(("predict", "S", "C0"))
            self.assertEqual(observed[s0:s0 + 3], [("predict", "S", "C0"), ("replay", "S", "C0"), ("retain", "S", "C0")])
            self.assertEqual(len(contexts), 8)
            self.assertEqual(adapter.cleanup.call_count, 8)
            self.assertEqual(flags, [False] * 16)
            adapter.metric.assert_not_called()
            self.assertIs(result["prefix_pricing_performed"], False)
            self.assertIs(result["full_prefix_admitted"], False)

    def test_warm_repeat_failure_stops_and_cleans_without_retry(self):
        plan, prep, adapter, budget, observed, contexts, flags, serialize = self.setup_panel(warm_failure=True)
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(b.BenchmarkError, "warm arithmetic repeat changed"):
                b.timing_panel(plan, prep, adapter, budget, directory, serialize, lambda a, old: a.value == old.value)
            self.assertEqual(len(list(Path(directory).glob("*.npz"))), 1)
        self.assertEqual(len(contexts), 1)
        self.assertEqual(adapter.cleanup.call_count, 1)
        self.assertEqual(len([x for x in observed if x[0] == "predict"]), 2)
        adapter.metric.assert_not_called()

    def test_incomplete_all_parent_preflight_admits_no_calls(self):
        plan, prep, adapter, budget, observed, contexts, flags, serialize = self.setup_panel()
        adapter.preflight.return_value = dict(parents=59)
        with tempfile.TemporaryDirectory() as directory, self.assertRaisesRegex(b.BenchmarkError, "preflight incomplete"):
            b.timing_panel(plan, prep, adapter, budget, directory, serialize, lambda a, old: True)
        self.assertEqual(observed, [])
        self.assertEqual(contexts, [])

    def test_budget_exhaustion_stops_before_first_model_call(self):
        plan, prep, adapter, budget, observed, contexts, flags, serialize = self.setup_panel()
        budget.check.side_effect = b.BenchmarkError("whole cap exhausted")
        with tempfile.TemporaryDirectory() as directory, self.assertRaisesRegex(b.BenchmarkError, "cap exhausted"):
            b.timing_panel(plan, prep, adapter, budget, directory, serialize, lambda a, old: True)
        self.assertEqual(observed, [])
        adapter.preflight.assert_not_called()


class BridgeTests(unittest.TestCase):
    def test_retained_integer_schema_is_exact_original_R150_contract(self):
        path = Path(b.SOURCE_PINS["canonical497"][0]).with_name("pricefm_r150_contract.py")
        assignment = next(node for node in ast.parse(path.read_text()).body if isinstance(node, ast.Assign)
            and any(isinstance(target, ast.Name) and target.id == "INT_KEYS" for target in node.targets))
        self.assertEqual(b.RETAINED_INT_KEYS, frozenset(ast.literal_eval(assignment.value)))

    def test_every_exact_original_function_compiles_with_only_approved_globals(self):
        shared = dict(dt=dt, producer=Mock(), CONFIG="logical-config", read=Mock(), hashlib=hashlib,
            INT_KEYS=frozenset(), math=math, time=time)
        resolver = SimpleNamespace(path=lambda path: Path(path))
        for name, record in b.FUNCTIONS.items():
            bindings = {key: vars(builtins)[key] if key in vars(builtins) else shared[key] for key in record["globals"]}
            with self.subTest(name=name):
                function = b.extract_original(name, resolver, bindings)
                self.assertEqual(function.__name__, name)
                self.assertNotIn("ROOT", function.__globals__)
                self.assertEqual(set(function.__globals__) - {"__builtins__", name}, set(record["globals"]))

    def test_changed_source_and_unapproved_binding_fail_before_function_execution(self):
        resolver = SimpleNamespace(path=lambda path: Path(path))
        with patch.object(b, "digest", return_value="changed"), self.assertRaisesRegex(b.BenchmarkError, "source changed"):
            b.extract_original("predict", resolver, {})
        with self.assertRaisesRegex(b.BenchmarkError, "global allowlist"):
            b.extract_original("predict", resolver, {"forbidden": object()})


class AdmissionTests(unittest.TestCase):
    def test_current_environment_or_parity_grants_cannot_open_gate_evidence(self):
        plan = dict(study="FI", claim=dict(planned_attempt_id="scope", scientific_exclusion_key="exclusion"))
        for role in ("environment", "parity"):
            with patch.object(b, "_pin_json") as read, self.assertRaisesRegex(b.BenchmarkError, "COST_ONLY authority"):
                b.validate_authority(dict(role=role), plan, "plan", dict(job_id="123", node="compute"))
            read.assert_not_called()

    def test_no_compute_admission_means_no_plan_or_input_reads(self):
        with patch.object(b, "require_compute", side_effect=b.BenchmarkError("no allocated compute")), patch.object(b.planning, "dry_run") as read:
            with self.assertRaisesRegex(b.BenchmarkError, "no allocated"):
                b.run_benchmark("plan", "authority", "sha", "stage", "output")
            read.assert_not_called()

    def test_reference_environment_required_before_plan_or_scientific_imports(self):
        with patch.object(b, "require_compute", return_value=dict(job_id="123", node="compute")), patch.dict(b.os.environ, b.THREAD_ENV, clear=True), patch.object(b.planning, "dry_run") as read:
            with self.assertRaisesRegex(b.BenchmarkError, "original numerical environment"):
                b.run_benchmark("plan", "authority", "sha", "stage", "output")
            read.assert_not_called()

    def test_live_dispatch_guard_precedes_core_and_moment_loading(self):
        with patch.object(b, "require_reference_profile", side_effect=b.BenchmarkError("wrong actual CPU dispatch")) as guard, patch.object(b, "_load_module") as load:
            with self.assertRaisesRegex(b.BenchmarkError, "wrong actual CPU"):
                b.frozen_adapter({}, {}, {}, None, None, {"/actual/numpy.so": "0" * 64, "/actual/scipy.so": "1" * 64})
            guard.assert_called_once()
            load.assert_not_called()

    def test_whole_CPU_and_wall_caps_include_startup(self):
        authority = dict(expires_epoch=time.time() + 100)
        cpu = Mock(return_value=1200)
        budget = b.Budget(authority, wall=lambda: 100.0, cpu=cpu)
        with self.assertRaisesRegex(b.BenchmarkError, "cap exhausted"):
            budget.check()
        budget = b.Budget(authority, wall=lambda: 100.0, cpu=lambda: 0.0)
        budget.deadline = 99.0
        with self.assertRaisesRegex(b.BenchmarkError, "cap exhausted"):
            budget.check()

    def test_aggregate_cpu_includes_reaped_administrative_children(self):
        with patch.object(b.time, "process_time", return_value=17.0), patch.object(b.resource, "getrusage", return_value=SimpleNamespace(ru_utime=2.0, ru_stime=3.0)):
            self.assertEqual(b.aggregate_cpu_seconds(), 22.0)

    def test_actual_runtime_versions_are_checked_before_numerical_loading(self):
        with patch.object(b.platform, "python_version", return_value="3.11.13"), patch.object(b.metadata, "version", return_value="2.0"):
            b.validate_actual_runtime(dict(python_version="3.11.13", versions=dict(numpy="2.0")))
            with self.assertRaisesRegex(b.BenchmarkError, "versions differ"):
                b.validate_actual_runtime(dict(python_version="3.11.13", versions=dict(numpy="different")))

    def test_valid_new_authority_requires_all_sealed_physical_gates(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            now = time.time()
            def pin(name, value):
                path = root / name
                write_json(path, value)
                return dict(path=str(path), sha256=digest(path))
            runtime_value = dict(status="verified", threadpoolctl=[dict(num_threads=1)], python_version="3.11.13",
                executable="/future/runtime/venv/bin/python", versions=dict(numpy="2.0.2", scipy="1.13.1"))
            runtime = pin("runtime.json", runtime_value)
            parity = pin("parity.json", dict(status="PASS_TEST_FORECAST_PARITY", accepted=True,
                execution=dict(namespace="TEST", fixture_manifest_sha256="fixture", slurm_job_id="prior-parity")))
            parity_seal = pin("parity_seal.json", dict(status="COMPLETE_TEST_ONLY", artifacts={"parity.json": parity["sha256"]}))
            disabled = b.REFERENCE_NUMERICAL_ENV["NPY_DISABLE_CPU_FEATURES"].split(",")
            numerical_profile = dict(enabled=True, environment=b.REFERENCE_NUMERICAL_ENV,
                numpy_cpu_features={key: False for key in disabled}, numpy_dispatch_targets=disabled,
                openblas_architectures=["Sandybridge", "Sandybridge"])
            parity_runtime_value = dict(runtime_value, allocation=dict(job_id="prior-parity"), reference_numerical_profile=numerical_profile,
                native_library_sha256={"/future/numpy_openblas.so": "0" * 64, "/future/scipy_openblas.so": "1" * 64})
            parity_runtime = pin("parity-runtime.json", parity_runtime_value)
            qualification = pin("parity-qualification.json", dict(schema=b.QUALIFICATION_SCHEMA, application_passed=True, job_id="prior-parity",
                files={"environment-runtime.json": parity_runtime["sha256"], "TEST/parity/parity.json": parity["sha256"]}))
            qualified = ["r134_984fd326bd5fd13e"]
            required = ["EE_{}_s{}_S_seed{}".format(package, split, seed)
                for package in ["C0"] + qualified for seed in (1, 2) for split in (1, 2, 3)]
            assessment_value = dict(status="COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT_NOT_PROMOTED", required_task_names=required,
                qualified_from_unchanged_initial_S0=qualified, disposition="HOLD_ALGORITHMIC_STABILITY_UNRESOLVED",
                all_new_components_independently_revalidated=True, AL_proposal_admitted=False, automatic_followon=False, new_fits=0, official_origins=0)
            assessment = pin("assessment.json", assessment_value)
            report = root / "DELIVERED.md"
            report.write_text("sealed delivered EE disposition")
            drain = pin("drain.json", dict(status="DRAINED", live_worker_pids=[], live_job_ids=[], active_scientific_claims=[], observed_epoch=now))
            ee_value = dict(status="COMPLETE_EE_DISPOSITION_DELIVERED_DRAINED", required_task_names=required,
                completed_task_names=required, assessment_accepted=True, scientific_assessment=assessment,
                delivered_report=dict(path=str(report), sha256=digest(report)), physical_drain=drain)
            ee = pin("EE.json", ee_value)
            claim = pin("claim.json", dict(schema="r156_hb_cross_server_cost_claim_v1", status="EXCLUSIVE_CLAIMED", scope_id="scope", slurm_job_id="123",
                scientific_exclusion_key="exclusion", overlapping_live_claims=[], all_hosts_observed=True, observed_epoch=now,
                controller=b.EXPECTED_CONTROLLER, study="FI", region="FI", plan_sha256="plan", all_hosts=sorted(b.EXPECTED_HOSTS)))
            source_closure = {name: digest(Path(b.__file__).with_name(name)) for name in b.EXECUTED_SOURCE_FILES}
            adapter_sources = {name: source_closure[name] for name in ("benchmark.py", "benchmark_plan.py", "science.py", "fixture.py", "environment.py")}
            review = pin("review.json", dict(schema="r156_hb_cost_adapter_review_v1", status="REVIEWED_TESTED_COST_ONLY",
                issuer=b.EXPECTED_CONTROLLER, controller_sources=source_closure, adapter_sources=adapter_sources,
                plan_sha256="plan", tests_passed=True, no_AQL=True, no_selection=True, full_prefix_admitted=False))
            authority = dict(schema=b.AUTHORITY_SCHEMA, status="ADMITTED_COST_ONLY", role="FI_COST_ONLY_BENCHMARK", plan_sha256="plan", study="FI",
                scope_id="scope", scientific_exclusion_key="exclusion", slurm_job_id="123", node="compute", resources=p.LIMITS,
                full_prefix_admitted=False, automatic_retry=False, started_epoch=now - 1, expires_epoch=now + 1199, memory_mib=4096,
                runtime_result=runtime, parity_result=parity, parity_seal=parity_seal, accepted_parity_fixture_manifest_sha256="fixture",
                parity_runtime_result=parity_runtime, parity_qualification_seal=qualification, reference_numerical_environment=b.REFERENCE_NUMERICAL_ENV,
                EE_completion_receipt=ee, cross_server_claim=claim, issuer=b.EXPECTED_CONTROLLER, controller=b.EXPECTED_CONTROLLER,
                executed_sources=source_closure, adapter_review=review)
            plan = dict(study="FI", region="FI", claim=dict(planned_attempt_id="scope", scientific_exclusion_key="exclusion"),
                adapter_feasibility=dict(adapter_sources=adapter_sources))
            b.validate_authority(authority, plan, "plan", dict(job_id="123", node="compute"), now)
            expired = copy.deepcopy(authority)
            expired["expires_epoch"] = now
            with self.assertRaisesRegex(b.BenchmarkError, "finite current"):
                b.validate_authority(expired, plan, "plan", dict(job_id="123", node="compute"), now)
            stale_drain = pin("stale_drain.json", dict(status="DRAINED", live_worker_pids=[], live_job_ids=[], active_scientific_claims=[], observed_epoch=now - 301))
            changed_ee = b._pin_json(ee)
            changed_ee["physical_drain"] = stale_drain
            changed = dict(authority, EE_completion_receipt=pin("EE_stale.json", changed_ee))
            with self.assertRaisesRegex(b.BenchmarkError, "physical EE drain"):
                b.validate_authority(changed, plan, "plan", dict(job_id="123", node="compute"), now)
            for disposition in ("STOP_NO_QUALIFYING_CONFIRMED_LEAD", "HOLD_ALGORITHMIC_STABILITY_UNRESOLVED", "ONE_CONDITIONAL_AL_PROPOSAL_NOT_ADMITTED"):
                changed_ee = dict(ee_value, scientific_assessment=pin("clean-assessment.json", dict(assessment_value, disposition=disposition)))
                changed = dict(authority, EE_completion_receipt=pin("clean-EE.json", changed_ee))
                b.validate_authority(changed, plan, "plan", dict(job_id="123", node="compute"), now)
            for change in (dict(disposition="STOP_OPERATIONAL_FAILURE"), dict(all_new_components_independently_revalidated=False),
                    dict(AL_proposal_admitted=True), dict(automatic_followon=True), dict(new_fits=1), dict(official_origins=1)):
                changed_ee = dict(ee_value, scientific_assessment=pin("bad-assessment.json", dict(assessment_value, **change)))
                changed = dict(authority, EE_completion_receipt=pin("bad-EE.json", changed_ee))
                with self.subTest(change=change), self.assertRaisesRegex(b.BenchmarkError, "complete matched assessment"):
                    b.validate_authority(changed, plan, "plan", dict(job_id="123", node="compute"), now)
            partial = dict(ee_value, required_task_names=required[:-1], completed_task_names=required[:-1])
            with self.assertRaisesRegex(b.BenchmarkError, "complete accepted EE"):
                b.validate_authority(dict(authority, EE_completion_receipt=pin("partial-EE.json", partial)), plan, "plan", dict(job_id="123", node="compute"), now)
            for change in (dict(issuer="unknown-issuer"), dict(controller="other-controller")):
                with self.subTest(change=change), self.assertRaisesRegex(b.BenchmarkError, "COST_ONLY authority"):
                    b.validate_authority(dict(authority, **change), plan, "plan", dict(job_id="123", node="compute"), now)
            missing_sources = dict(source_closure)
            del missing_sources["cost_control.py"]
            with self.assertRaisesRegex(b.BenchmarkError, "source closure"):
                b.validate_authority(dict(authority, executed_sources=missing_sources), plan, "plan", dict(job_id="123", node="compute"), now)


if __name__ == "__main__":
    unittest.main()
