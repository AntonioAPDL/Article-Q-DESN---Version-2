"""Future COST_ONLY wire tests; all SSH, Slurm and arithmetic are mocked."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from pricefm_hb import cost_control as c

NOW = 1800000000.0
JOB = "12345"
ALLOCATION = {"job_id": JOB, "node": "node-07", "affinity": [4], "cpus_per_task": 1, "allocation_nodes": ["node-07"]}


def accounting(job=JOB, state="COMPLETED", code="0:0", cpu="00:00:01", elapsed="2"):
    return "\n".join("|".join((name, state, code, elapsed, "1", cpu, "128K", "node-07"))
                     for name in (job, job + ".batch", job + ".0")) + "\n"


class CostControlTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.release = self.root / "release"
        self.central = self.root / "canonical"
        self.central.mkdir()
        self.qualification = self.central / "spent-qualification.json"
        self.qualification.write_text('{"reserved_CPU_seconds":4500,"attempts":4}\n')
        self.qualification_bytes = self.qualification.read_bytes()
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(c, "CENTRAL", self.central).start()
        mock.patch.object(c.socket, "getfqdn", return_value=c.OWNER).start()
        self.clock = mock.patch.object(c.time, "time", return_value=NOW).start()
        self.external = mock.patch.object(c.subprocess, "run", side_effect=AssertionError("unmocked external process")).start()
        self.remote_calls, self.transfer_calls = [], []
        self.remote = mock.patch.object(c.ctl, "remote", side_effect=self.fake_remote).start()
        self.transfer = mock.patch.object(c.ctl, "run", side_effect=self.fake_transfer).start()
        self.queue, self.sacct, self.sbatch = "", accounting(), JOB + ";hummingbird\n"
        self.make_inputs()

    def write(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        c.r.write(path, value)
        return c.pin(path)

    def make_inputs(self):
        asset = self.root / "opaque-parent.txt"
        asset.write_text("opaque provenance fixture; no numerical execution\n")
        source_pins = {name: c.r.digest(Path(c.__file__).with_name(name)) for name in
                       ("benchmark.py", "benchmark_plan.py", "science.py", "fixture.py", "environment.py")}
        schedule = []
        for index in range(18):
            schedule.append({"sequence": index + 1, "kind": "timed_prediction" if index < 16 else "control_replay",
                             "task": "task" + str(index), "mode": "D" if index < 12 else "S", "package_id": "C0",
                             "repetition": index, "p": 2, "serialization": {"retained_packet":
                                 ("D" if index < 12 else "S") + "_C0_" + str(index) + ".npz"}})
        self.plan = {"schema": c.p.SCHEMA, "status": "METADATA_PLAN_COMPLETE_BENCHMARK_NOT_ADMITTED", "study": "FI", "region": "FI",
            "resources": c.p.LIMITS, "canonical_preparation": {"sha256": "a" * 64, "source": {"head": c.p.SOURCE_HEADS["FI"]}},
            "schedule": schedule, "all_parent_preflight": [{"p": 2} for _ in range(60)],
            "schedule_summary": {"arithmetic_calls": 18}, "inventory": {"bytes": asset.stat().st_size},
            "input_allowlist": {str(asset): {"sha256": c.r.digest(asset), "bytes": asset.stat().st_size,
                                          "staged_relative_path": str(Path("files") / asset.relative_to("/"))}},
            "claim": {"planned_attempt_id": "future-fi-once", "scientific_exclusion_key": "FI:source:protocol"},
            "adapter_feasibility": {"status": "COST_ONLY_RUNTIME_IMPLEMENTED_NOT_ADMITTED_NOT_SCIENTIFICALLY_QUALIFIED",
                                    "adapter_sources": source_pins},
            "launch_manifest": {"status": "NOT_ADMITTED", "actual_model_execution_authorized": False}}
        self.plan_pin = self.write("plan.json", self.plan)
        Path(self.plan_pin["path"]).with_suffix(".sha256").write_text(self.plan_pin["sha256"] + "\n")
        runtime_path = "/mnt/beegfs/home/jaguir26/qualified/r156-env03/runtime/venv/bin/python"
        runtime = self.write("proofs/runtime.json", {"status": "verified", "python_version": "3.11.13",
            "executable": runtime_path, "versions": {"numpy": "2.0.2"}, "threadpoolctl": [{"num_threads": 1}]})
        parity = self.write("proofs/parity.json", {"status": "PASS_TEST_FORECAST_PARITY", "accepted": True,
            "execution": {"namespace": "TEST", "fixture_manifest_sha256": "f" * 64, "slurm_job_id": "12"}})
        parity_seal = self.write("proofs/parity-seal.json", {"status": "COMPLETE_TEST_ONLY", "artifacts": {"parity.json": parity["sha256"]}})
        dispatch = c.REFERENCE_NUMERICAL_ENV["NPY_DISABLE_CPU_FEATURES"].split(",")
        self.reference_profile = {"enabled": True, "environment": c.REFERENCE_NUMERICAL_ENV,
            "numpy_dispatch_targets": dispatch, "numpy_cpu_features": dict.fromkeys(dispatch, False),
            "openblas_architectures": ["Sandybridge", "Sandybridge"]}
        self.reference_profile["numpy_cpu_features"]["AVX512VL"] = True
        parity_runtime = self.write("proofs/parity-runtime.json", {"status": "verified", "python_version": "3.11.13",
            "executable": runtime_path, "versions": {"numpy": "2.0.2"}, "threadpoolctl": [{"num_threads": 1}],
            "allocation": {"job_id": "12"}, "reference_numerical_profile": self.reference_profile,
            "native_library_sha256": {"/qualified/numpy-openblas.so": "1" * 64, "/qualified/scipy-openblas.so": "2" * 64}})
        self.required = ["EE_{}_s{}_S_seed{}".format(package, split, seed)
                         for package in ("C0", "r134_984fd326bd5fd13e") for seed in (1, 2) for split in (1, 2, 3)]
        self.assessment = {"status": "COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT_NOT_PROMOTED", "required_task_names": self.required,
            "qualified_from_unchanged_initial_S0": ["r134_984fd326bd5fd13e"], "disposition": "HOLD_ALGORITHMIC_STABILITY_UNRESOLVED",
            "all_new_components_independently_revalidated": True, "AL_proposal_admitted": False,
            "automatic_followon": False, "new_fits": 0, "official_origins": 0}
        assessment = self.write("proofs/assessment.json", self.assessment)
        report = self.root / "proofs/delivered-report.md"
        report.write_text("Complete scientific HOLD delivered to the user.\n")
        drain = self.write("proofs/drain.json", {"status": "DRAINED", "observed_epoch": NOW,
            "live_worker_pids": [], "live_job_ids": [], "active_scientific_claims": []})
        self.ee = {"status": "COMPLETE_EE_DISPOSITION_DELIVERED_DRAINED", "required_task_names": self.required,
            "completed_task_names": self.required, "assessment_accepted": True, "scientific_assessment": assessment,
            "delivered_report": c.pin(report), "physical_drain": drain}
        ee = self.write("proofs/EE.json", self.ee)
        review = self.write("proofs/review.json", {"schema": "r156_hb_cost_adapter_review_v1", "status": "REVIEWED_TESTED_COST_ONLY",
            "plan_sha256": self.plan_pin["sha256"], "adapter_sources": source_pins, "tests_passed": True,
            "issuer": c.OWNER, "controller_sources": c.executed_sources(),
            "no_AQL": True, "no_selection": True, "full_prefix_admitted": False})
        self.hosts = {"schema": "r156_hb_all_hosts_cost_observation_v1", "status": "NO_OVERLAP", "controller": c.OWNER,
            "hosts": sorted(c.HOSTS), "scientific_exclusion_key": self.plan["claim"]["scientific_exclusion_key"],
            "overlapping_scientific_claims": [], "live_cost_jobs": [], "observed_epoch": NOW,
            "unrelated_baseline_claims": ["preserved-owner"]}
        hosts = self.write("proofs/hosts.json", self.hosts)
        self.site = {"schema": "r156_hb_cost_site_admission_v1", "status": "ADMITTED_COST_ONLY_RESOURCES", "study": "FI",
            "plan_sha256": self.plan_pin["sha256"], "account": "128x24", "partition": "128x24", "qos": "normal",
            "node": "node-07", "observed_epoch": NOW, "memory_mib": 4096, "minimum_required_memory_mib": 1024,
            "available_memory_mib": 8192, "free_disk_bytes": 2 * 1024**3, "available_cpus": 1,
            "calendar_expires_epoch": NOW + 3600, "maximum_parent_p": 2}
        site = self.write("proofs/site.json", self.site)
        self.request = {"schema": c.REQUEST_SCHEMA, "plan": self.plan_pin, "study": "FI", "full_prefix_admitted": False,
            "automatic_retry": False, "runtime_result": runtime, "runtime_python": runtime_path,
            "environment_bundle": "/mnt/beegfs/home/jaguir26/qualified/r156-env03/env", "parity_result": parity,
            "parity_seal": parity_seal, "accepted_parity_fixture_manifest_sha256": "f" * 64,
            "parity_runtime_result": parity_runtime,
            "EE_completion_receipt": ee, "adapter_review": review, "site_admission": site, "all_hosts_observation": hosts}
        for prefix, result_pin, output_name in (("runtime", runtime, "environment-evidence/runtime-verification.json"),
                                                ("parity", parity, "TEST/parity/parity.json")):
            job = "11" if prefix == "runtime" else "12"
            files = {output_name: result_pin["sha256"]}
            if prefix == "parity": files["environment-runtime.json"] = parity_runtime["sha256"]
            self.request[prefix + "_qualification_seal"] = self.write("proofs/" + prefix + "-qualification.json",
                {"schema": c.r.SCHEMA, "application_passed": True, "job_id": job, "files": files})
            self.request[prefix + "_accounting"] = self.write("proofs/" + prefix + "-accounting.json",
                {"complete": True, "job_id": job, "squeue": "", "sacct": accounting(job=job)})
        self.request_path = self.root / "request.json"
        c.r.write(self.request_path, self.request)
        key, known = self.root / "synthetic-identity", self.root / "synthetic-host-trust"
        key.write_text("not a key\n"); known.write_text("not host trust\n")
        self.config = {"host": "hb.ucsc.edu", "user": "jaguir26", "account": "128x24", "partition": "128x24", "qos": "normal",
            "ssh_identity_file": str(key), "known_hosts_file": str(known), "remote_root": "/mnt/beegfs/home/jaguir26/future_cost_tests"}
        self.config_path = self.root / "config.json"
        c.r.write(self.config_path, self.config)

    def prepare(self):
        return c.prepare_launch(self.plan_pin["path"], self.request_path, self.config_path, self.release)

    def submit(self):
        self.assertEqual(self.prepare()["status"], "PREPARED_COST_ONLY_NOT_CLAIMED_NOT_SUBMITTED")
        return c.submit_held(self.release, self.config_path)

    def claim(self):
        claims = c.Ledger().snapshot()["claims"]
        self.assertEqual(len(claims), 1)
        return next(iter(claims.values()))

    def fake_remote(self, config, argv):
        self.remote_calls.append(list(argv))
        if argv[0] == "squeue": return self.queue
        if argv[0] == "sacct": return self.sacct
        if argv[0] == "mkdir": return ""
        if argv[0] == "sbatch":
            self.assertEqual(self.claim()["state"], "SUBMISSION_INTENT")
            self.assertIn("--hold", argv)
            return self.sbatch
        if argv[0] == "scontrol":
            self.assertEqual(argv, ["scontrol", "release", JOB])
            self.assertEqual(self.claim()["state"], "RELEASE_INTENT")
            return ""
        if argv[0] == "scancel": return ""
        if argv[0] == "sha256sum":
            filename = "authorization/packet.json" if "/authorization/" in argv[1] else "release.json"
            return c.r.digest(self.release / filename) + "  fixture\n"
        raise AssertionError("unexpected remote operation: " + str(argv))

    def fake_transfer(self, argv, timeout=120):
        self.transfer_calls.append((list(argv), timeout))
        self.assertEqual(argv[0], "rsync")
        self.assertIn("--no-links", argv)
        self.assertLessEqual(timeout, 240)
        if argv[-2].startswith("jaguir26@hb.ucsc.edu:"):
            name = "outputs" if "/outputs/" in argv[-2] else "logs"
            source = self.release / name
            if source.exists(): shutil.copytree(source, Path(argv[-1]), dirs_exist_ok=True)
        return ""

    def authorize_release(self):
        claim = self.submit()
        c.issue_authority(claim["task_key"], self.config_path)
        return c.release_job(claim["task_key"], self.config_path)

    def fake_benchmark(self, argv, *, env, check, timeout):
        self.assertEqual(argv[:4], [self.request["runtime_python"], "-B", "-m", "pricefm_hb.benchmark"])
        self.assertTrue(check)
        self.assertLessEqual(timeout, 1195)
        self.assertEqual({key: env[key] for key in c.THREAD_ENV}, c.THREAD_ENV)
        self.assertEqual({key: env[key] for key in c.REFERENCE_NUMERICAL_ENV}, c.REFERENCE_NUMERICAL_ENV)
        output = Path(argv[argv.index("--output-dir") + 1])
        output.mkdir(parents=True)
        claim = self.claim()
        authority_sha = argv[argv.index("--authority-sha256") + 1]
        identity = {"scope_id": claim["scope_id"], "namespace": "BENCHMARK_TEST", "allocation": ALLOCATION,
            "plan_sha256": claim["task"]["plan_sha256"], "authority_sha256": authority_sha,
            "scientific_exclusion_key": claim["task"]["scientific_exclusion_key"], "full_prefix_admitted": False}
        rows = [{"mode": call["mode"], "package_id": call["package_id"], "repetition": call["repetition"], "p": call["p"],
                 "split": 3, "clock_offset_steps": 0, "origin_count": 8, "numerical_threadpools": [{"num_threads": 1}]}
                for call in self.plan["schedule"] if call["kind"] == "timed_prediction"]
        for row, call in zip(rows, [call for call in self.plan["schedule"] if call["kind"] == "timed_prediction"]):
            packet = output / call["serialization"]["retained_packet"]
            packet.write_bytes(b"opaque test-only retained NPZ bytes; not numerical data")
            row.update(retained_prediction_packet=packet.name, retained_prediction_sha256=c.r.digest(packet), compressed_bytes=packet.stat().st_size)
        result = {"status": "COMPLETE_COST_ONLY_18_CALL_PANEL_NO_SELECTION_NO_ADMISSION", "execution": identity,
            "arithmetic_calls": 18, "timed_prediction_calls": 16, "untimed_control_replay_prediction_calls": 2,
            "rows": rows, "no_new_candidate_AQL_computed": True, "no_scientific_selection": True,
            "full_prefix_admitted": False, "prefix_pricing_performed": False, "automatic_retry": False,
            "new_model_fits": 0, "official_origins": 0, "process_CPU_seconds": 1, "aggregate_CPU_seconds": 1,
            "elapsed_seconds": 2, "calls": [{key: call[key] for key in ("sequence", "kind", "task")} for call in self.plan["schedule"]],
            "numerical_preflight": {"parents": c.p.COUNTS[self.plan["study"]]["parents"]}}
        c.r.write(output / "timings.json", result)
        c.r.write(output / "execution_identity.json", identity)
        c.r.write(output / "completed_evidence.json", {"status": "COMPLETE_COST_PANEL_ONLY_NO_SCIENCE_ADMISSION",
            "execution": identity, "artifacts": {path.name: c.r.digest(path) for path in output.iterdir() if path.is_file()}})
        return subprocess.CompletedProcess(argv, 0)

    def run_worker(self):
        (self.release / "outputs").mkdir()
        (self.release / "logs").mkdir()
        (self.release / "logs/job.log").write_text("synthetic scheduler log\n")
        remote_root = self.claim()["remote_root"]
        original_metadata = c.p.read_metadata
        def mapped(path):
            text = str(path)
            return self.release / text[len(remote_root) + 1:] if text.startswith(remote_root + "/") else Path(path)
        # Use the real benchmark authority validator against relocated proof bytes.
        # Only path resolution and the arithmetic subprocess are mocked.
        with mock.patch.object(c, "require_compute", return_value=ALLOCATION), \
             mock.patch.dict(c.os.environ, c.REFERENCE_NUMERICAL_ENV), \
             mock.patch.object(c.b, "digest", side_effect=lambda path: c.r.digest(mapped(path))), \
             mock.patch.object(c.p, "read_metadata", side_effect=lambda path: original_metadata(mapped(path))), \
             mock.patch.object(c.subprocess, "run", side_effect=self.fake_benchmark):
            return c.cost_worker(self.release, c.r.digest(self.release / "release.json"))

    def test_full_mocked_wire_preparation_claim_held_authority_release_worker_status_collect(self):
        claim = self.authorize_release()
        self.assertEqual(claim["state"], "SUBMITTED")
        self.assertEqual(self.run_worker()["status"], "COMPLETE_COST_ONLY_PENDING_ACCOUNTING_AND_COLLECTION")
        receipt = self.root / "status.json"
        self.assertTrue(c.status(claim["task_key"], self.config_path, receipt)["complete"])
        publication = self.root / "publication"
        result = c.collect(claim["task_key"], self.config_path, receipt, self.root / "incoming", publication)
        self.assertEqual(result["state"], "COLLECTED_COST_ONLY")
        self.assertTrue(result["application_accepted"])
        self.assertFalse(result["full_prefix_admitted"])
        self.assertTrue((publication / "outputs/worker_evidence.json").is_file())
        self.assertFalse((publication / "stage").exists())
        self.assertFalse((publication / "runtime").exists())
        job_script = (self.release / "job.sh").read_text()
        for key, value in c.REFERENCE_NUMERICAL_ENV.items():
            self.assertIn("export " + key + "=" + value, job_script)
        self.assertEqual(self.qualification.read_bytes(), self.qualification_bytes)
        self.assertEqual(result["reserved_CPU_seconds"], 1200)

    def test_missing_gate_blocks_before_claim_staging_or_any_network(self):
        self.request["EE_completion_receipt"] = None
        c.r.write(self.request_path, self.request)
        result = self.prepare()
        self.assertEqual(result["status"], "BLOCKED_NO_CLAIM_NO_NETWORK")
        self.assertFalse(self.release.exists())
        self.assertFalse((self.central / "cost_only_registry.json").exists())
        self.remote.assert_not_called(); self.transfer.assert_not_called(); self.external.assert_not_called()

    def test_DK2_independently_uses_same_exact_wire_and_full63_parent_panel(self):
        self.plan.update(study="DK2", region="DK_2", all_parent_preflight=[{"p": 2} for _ in range(63)])
        self.plan["canonical_preparation"]["source"]["head"] = c.p.SOURCE_HEADS["DK2"]
        self.plan["claim"].update(planned_attempt_id="future-dk2-once", scientific_exclusion_key="DK2:source:protocol")
        self.plan_pin = self.write("plan-DK2.json", self.plan)
        Path(self.plan_pin["path"]).with_suffix(".sha256").write_text(self.plan_pin["sha256"] + "\n")
        self.request.update(study="DK2", plan=self.plan_pin)
        self.site.update(study="DK2", plan_sha256=self.plan_pin["sha256"])
        self.request["site_admission"] = self.write("proofs/site-DK2.json", self.site)
        review = c.pinned(self.request["adapter_review"])
        review["plan_sha256"] = self.plan_pin["sha256"]
        self.request["adapter_review"] = self.write("proofs/review-DK2.json", review)
        self.hosts["scientific_exclusion_key"] = self.plan["claim"]["scientific_exclusion_key"]
        self.request["all_hosts_observation"] = self.write("proofs/hosts-DK2.json", self.hosts)
        c.r.write(self.request_path, self.request)
        claim = self.authorize_release()
        self.run_worker()
        receipt = self.root / "DK2-status.json"
        c.status(claim["task_key"], self.config_path, receipt)
        result = c.collect(claim["task_key"], self.config_path, receipt, self.root / "incoming", self.root / "publication")
        self.assertEqual(result["state"], "COLLECTED_COST_ONLY")
        self.assertEqual(result["task"]["study"], "DK2")
        self.assertTrue(result["application_accepted"])

    def test_malformed_runtime_or_infinite_calendar_is_blocked_without_network(self):
        original_runtime = self.request["runtime_result"]
        self.request["runtime_result"] = self.write("proofs/bad-runtime.json", {"status": "verified", "python_version": "3.11.13",
            "executable": self.request["runtime_python"], "threadpoolctl": [None]})
        c.r.write(self.request_path, self.request)
        self.assertEqual(self.prepare()["status"], "BLOCKED_NO_CLAIM_NO_NETWORK")
        self.request["runtime_result"] = original_runtime
        bad_site = self.root / "proofs/infinite-calendar.json"
        bad_site.write_text(json.dumps(dict(self.site, calendar_expires_epoch=float("inf"))).replace("Infinity", "1e999"))
        self.request["site_admission"] = c.pin(bad_site)
        c.r.write(self.request_path, self.request)
        result = self.prepare()
        self.assertEqual(result["status"], "BLOCKED_NO_CLAIM_NO_NETWORK")
        self.assertIn("measured account", result["reason"])
        self.remote.assert_not_called(); self.transfer.assert_not_called()

    def test_all_clean_scientific_dispositions_accept_without_AL_success(self):
        for disposition in ("STOP_NO_QUALIFYING_CONFIRMED_LEAD", "HOLD_ALGORITHMIC_STABILITY_UNRESOLVED",
                            "ONE_CONDITIONAL_AL_PROPOSAL_NOT_ADMITTED"):
            assessment = dict(self.assessment, disposition=disposition)
            ee = dict(self.ee, scientific_assessment=self.write("proofs/assessment-" + disposition + ".json", assessment))
            request = dict(self.request, EE_completion_receipt=self.write("proofs/EE-" + disposition + ".json", ee))
            c.validate_gates(request, self.plan, self.plan_pin["sha256"], NOW)
        self.remote.assert_not_called()

    def test_partial_scientific_set_or_operational_stop_blocks(self):
        for change in ({"required_task_names": self.required[:-1]}, {"disposition": "STOP_OPERATIONAL_FAILURE"},
                       {"all_new_components_independently_revalidated": False}, {"AL_proposal_admitted": True}):
            assessment = dict(self.assessment, **change)
            ee = dict(self.ee, scientific_assessment=self.write("proofs/bad-assessment.json", assessment))
            request = dict(self.request, EE_completion_receipt=self.write("proofs/bad-ee.json", ee))
            with self.subTest(change=change), self.assertRaises(c.GateError):
                c.validate_gates(request, self.plan, self.plan_pin["sha256"], NOW)
        self.remote.assert_not_called()

    def test_stale_drain_or_overlap_or_inadequate_memory_blocks_without_claim(self):
        changed = copy.deepcopy(self.request)
        changed["all_hosts_observation"] = self.write("proofs/overlap.json", dict(self.hosts, overlapping_scientific_claims=["other-host"]))
        with self.assertRaisesRegex(c.GateError, "all-host"):
            c.validate_gates(changed, self.plan, self.plan_pin["sha256"], NOW)
        changed = copy.deepcopy(self.request)
        changed["site_admission"] = self.write("proofs/low-memory.json", dict(self.site, memory_mib=9000))
        with self.assertRaisesRegex(c.GateError, "measured account"):
            c.validate_gates(changed, self.plan, self.plan_pin["sha256"], NOW)
        self.clock.return_value = NOW + 301
        self.assertEqual(self.prepare()["status"], "BLOCKED_NO_CLAIM_NO_NETWORK")
        self.assertFalse((self.central / "cost_only_registry.json").exists())
        self.remote.assert_not_called()

    def test_qualified_application_without_successful_Slurm_seal_is_blocked(self):
        changed = copy.deepcopy(self.request)
        changed["runtime_accounting"] = self.write("proofs/failed-runtime-accounting.json", {"complete": True,
            "job_id": "11", "squeue": "", "sacct": accounting(job="11", state="FAILED", code="1:0")})
        with self.assertRaisesRegex(c.GateError, "scheduler accounting"):
            c.validate_gates(changed, self.plan, self.plan_pin["sha256"], NOW)

    def test_reference_profile_must_belong_to_the_same_complete_parity_job(self):
        changed = copy.deepcopy(self.request)
        seal = c.pinned(changed["parity_qualification_seal"])
        seal["files"]["environment-runtime.json"] = "0" * 64
        changed["parity_qualification_seal"] = self.write("proofs/misbound-profile.json", seal)
        with self.assertRaisesRegex(c.GateError, "same accepted parity job"):
            c.validate_gates(changed, self.plan, self.plan_pin["sha256"], NOW)
        profile = copy.deepcopy(self.reference_profile)
        profile["numpy_cpu_features"]["AVX512_SKX"] = True
        report = c.pinned(self.request["parity_runtime_result"])
        report["reference_numerical_profile"] = profile
        changed = dict(self.request, parity_runtime_result=self.write("proofs/active-avx512.json", report))
        with self.assertRaisesRegex(c.GateError, "historical numerical profile"):
            c.validate_gates(changed, self.plan, self.plan_pin["sha256"], NOW)

    def test_wrong_controller_cannot_prepare_or_mutate_canonical_registry(self):
        with mock.patch.object(c.socket, "getfqdn", return_value="jerez.be.ucsc.edu"):
            with self.assertRaisesRegex(c.GateError, "canonical Muscat"):
                self.prepare()
            with self.assertRaises(c.GateError): c.Ledger()
        self.remote.assert_not_called()

    def test_global_lane_and_spent_region_cannot_be_bypassed_with_new_attempt_id(self):
        claim = self.submit()
        different = copy.deepcopy(self.plan)
        different["study"] = "DK2"; different["region"] = "DK_2"
        different["claim"]["planned_attempt_id"] = "other-attempt"
        with self.assertRaisesRegex(c.GateError, "all-host cost claim"):
            c.Ledger().reserve(different, "b" * 64, "c" * 64, "d" * 64, "/tmp/release", "/remote")
        # Terminal failure consumes FI forever; no automatic refund or retry.
        ledger = c.Ledger()
        ledger.transition(claim["task_key"], "HELD", "AMBIGUOUS")
        ledger.transition(claim["task_key"], "AMBIGUOUS", "FAILED_RECONCILED")
        retry = copy.deepcopy(self.plan)
        retry["claim"]["planned_attempt_id"] = "new-UUID-does-not-reset-region"
        with self.assertRaisesRegex(c.GateError, "already spent"):
            ledger.reserve(retry, "e" * 64, "f" * 64, "0" * 64, "/tmp/new", "/remote/new")
        self.assertEqual(self.claim()["reserved_CPU_seconds"], 1200)

    def test_lost_sbatch_reply_is_ambiguous_and_never_auto_resubmits(self):
        self.prepare()
        actual = self.fake_remote
        def lost(config, argv):
            if argv[0] == "sbatch":
                self.remote_calls.append(argv)
                self.assertEqual(self.claim()["state"], "SUBMISSION_INTENT")
                raise subprocess.TimeoutExpired("sbatch", 120)
            return actual(config, argv)
        self.remote.side_effect = lost
        with self.assertRaises(subprocess.TimeoutExpired): c.submit_held(self.release, self.config_path)
        self.assertEqual(self.claim()["state"], "AMBIGUOUS")
        with self.assertRaises(c.GateError): c.submit_held(self.release, self.config_path)
        self.assertEqual(sum(argv[0] == "sbatch" for argv in self.remote_calls), 1)

    def test_lost_release_reply_retains_known_ambiguous_job(self):
        claim = self.submit()
        c.issue_authority(claim["task_key"], self.config_path)
        actual = self.fake_remote
        self.remote.side_effect = lambda config, argv: (_ for _ in ()).throw(subprocess.TimeoutExpired("release", 120)) if argv[0] == "scontrol" else actual(config, argv)
        with self.assertRaises(subprocess.TimeoutExpired): c.release_job(claim["task_key"], self.config_path)
        self.assertEqual(self.claim()["state"], "AMBIGUOUS")
        self.assertEqual(self.claim()["job_id"], JOB)

    def test_authority_transfer_failure_stops_before_job_release(self):
        claim = self.submit()
        self.transfer.side_effect = OSError("small authorization transfer interrupted")
        with self.assertRaises(OSError): c.issue_authority(claim["task_key"], self.config_path)
        self.assertEqual(self.claim()["state"], "AMBIGUOUS")
        self.assertFalse(any(argv[0] == "scontrol" for argv in self.remote_calls))
        self.assertEqual(self.claim()["reserved_CPU_seconds"], 1200)

    def test_explicit_held_cancellation_retains_spent_claim_until_accounting(self):
        claim = self.submit()
        result = c.cancel_held(claim["task_key"], self.config_path)
        self.assertEqual(result["state"], "AMBIGUOUS")
        self.assertIn(["scancel", JOB], self.remote_calls)
        self.assertEqual(result["reserved_CPU_seconds"], 1200)

    def test_status_throttle_and_unknown_accounting_prevent_retrieval(self):
        claim = self.authorize_release()
        self.sacct = ""
        receipt = self.root / "unknown-status.json"
        self.assertFalse(c.status(claim["task_key"], self.config_path, receipt)["terminal"])
        before = len(self.remote_calls)
        with self.assertRaises(c.GateError): c.status(claim["task_key"], self.config_path, self.root / "too-soon.json")
        self.assertEqual(len(self.remote_calls), before)
        self.transfer.reset_mock()
        with self.assertRaisesRegex(c.GateError, "unknown/incomplete"):
            c.collect(claim["task_key"], self.config_path, receipt, self.root / "incoming", self.root / "publication")
        self.transfer.assert_not_called()

    def test_output_corruption_retains_claim_and_prevents_atomic_publication(self):
        claim = self.authorize_release(); self.run_worker()
        packet = next((self.release / "outputs/BENCHMARK_TEST").rglob("timings.json"))
        packet.write_text("{}\n")
        receipt = self.root / "status.json"
        c.status(claim["task_key"], self.config_path, receipt)
        with self.assertRaisesRegex(c.GateError, "output hash"):
            c.collect(claim["task_key"], self.config_path, receipt, self.root / "incoming", self.root / "publication")
        self.assertFalse((self.root / "publication").exists())
        self.assertEqual(self.claim()["state"], "SUBMITTED")

    def test_missing_prediction_packet_or_resealed_wrong_row_hash_cannot_pass(self):
        claim = self.authorize_release(); self.run_worker()
        release = c.verify_release(self.release)
        for case in ("missing-packet", "wrong-row-hash"):
            output = self.root / case
            shutil.copytree(self.release / "outputs", output)
            timings = next((output / "BENCHMARK_TEST").rglob("timings.json"))
            panel = timings.parent
            result = c.r.read(timings)
            if case == "missing-packet":
                (panel / result["rows"][0]["retained_prediction_packet"]).unlink()
            else:
                result["rows"][0]["retained_prediction_sha256"] = "0" * 64
                c.r.write(timings, result)
            inner = c.r.read(panel / "completed_evidence.json")
            inner["artifacts"] = {path.name: c.r.digest(path) for path in panel.iterdir() if path.is_file() and path.name != "completed_evidence.json"}
            c.r.write(panel / "completed_evidence.json", inner)
            outer = c.r.read(output / "worker_evidence.json")
            outer["files"] = {str(path.relative_to(output)): c.r.digest(path) for path in output.rglob("*")
                              if path.is_file() and path != output / "worker_evidence.json"}
            c.r.write(output / "worker_evidence.json", outer)
            with self.subTest(case=case), self.assertRaisesRegex(c.GateError, "retained prediction packet"):
                c.validate_results(output, claim, release)

    def test_changed_issued_authority_is_rejected_before_job_release_network(self):
        claim = self.submit()
        c.issue_authority(claim["task_key"], self.config_path)
        path = self.release / "authorization/authority.json"
        value = c.r.read(path); value["expires_epoch"] += 3600
        c.r.write(path, value)
        self.remote.reset_mock()
        with self.assertRaisesRegex(c.GateError, "issued authority packet"):
            c.release_job(claim["task_key"], self.config_path)
        self.remote.assert_not_called()
        self.assertEqual(self.claim()["state"], "AUTHORIZED")

    def test_failed_terminal_job_reconciles_without_application_credit_or_refund(self):
        claim = self.authorize_release()
        (self.release / "outputs").mkdir(); (self.release / "logs").mkdir()
        (self.release / "logs/failure.log").write_text("synthetic failure\n")
        self.sacct = accounting(state="FAILED", code="1:0")
        receipt = self.root / "failed-status.json"
        c.status(claim["task_key"], self.config_path, receipt)
        result = c.collect(claim["task_key"], self.config_path, receipt, self.root / "incoming", self.root / "publication")
        self.assertEqual(result["state"], "FAILED_RECONCILED")
        self.assertFalse(result["application_accepted"])
        self.assertEqual(result["reserved_CPU_seconds"], 1200)

    def test_whole_job_wall_and_CPU_caps_are_stricter_than_qualification_grace(self):
        for text in (accounting(cpu="00:20:01"), accounting(elapsed="1201")):
            with self.subTest(text=text):
                result = c.cost_accounting(text, JOB, 4096)
                self.assertTrue(result["terminal"])
                self.assertFalse(result["complete"])
                self.assertTrue(result["scope_violations"])


if __name__ == "__main__":
    unittest.main()
