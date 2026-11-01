"""Synthetic cohort/control tests; no R fitting, subprocess launch or SSH."""
import copy
import importlib.util
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SOURCE = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("glofas_campaign", SOURCE / "scripts/run_glofas_transition_campaign.py")
G = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(G)


def write(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj))
    return G.C.file_sha256(path)


def make_fixture(tmp_path):
    prepared = tmp_path / "prepared"
    identity = dict(source_commit="a" * 40, source_tree="b" * 40,
                    source_manifest_sha256="c" * 64, posterior_target_sha256="d" * 64,
                    input_manifest_sha256="e" * 64, task_manifest_sha256="f" * 64)
    state = tmp_path / "private"
    config = {"hosts": {"muscat": {"rscript": "/qualified/Rscript", "python_bin": "/usr/bin/python3.11"}},
              "worker_scripts": {"glofas_family_transition": "application/scripts/run_glofas_family_transition.R"},
              "launch_authorized": False}
    master = dict(schema_version="glofas_transition_campaign_master_v1", allow_launch=True,
        authorize_derived_ready_wave_authorizations=True, authorize_live_resource_observation=True,
        approved_by="synthetic test", campaign_id="test_cohort",
        expires_utc="2099-01-01T00:00:00Z", host="muscat", logical_cpus=[24, 25], max_workers=2,
        max_cpu_busy_fraction=.2, poll_seconds=30, max_driver_wall_seconds=3600, resource_ttl_seconds=60,
        measured_peak_worker_rss_bytes=1024 ** 3, reserved_logical_cpus=list(range(16, 24)),
        qualified_host={"output_root": str(prepared / "results"), "python_bin": "/usr/bin/python3.11",
                        "metadata_root": str(state / "metadata"), "expires_utc": "2099-01-01T00:00:00Z"},
        templates={}, task_budgets={}, state_root=str(state), config=config, master_sha256="1" * 64,
        config_path=str(tmp_path / "config.json"), source_manifest_path="/pinned/source_manifest.csv", **identity)
    master["config_sha256"] = write(Path(master["config_path"]), config)
    master["preparation_sha256"] = write(prepared / "PREPARED_NO_LAUNCH.json", identity)
    for tid in G.TASK_IDS:
        request = dict(schema_version="glofas_family_transition_request_v1", task_id=tid,
            rng_namespace="scientific_" + tid, workflow="glofas_family_transition", allow_launch=False,
            authorization_sha256="", config_path=str(prepared / "configs" / (tid + ".rds")),
            source_manifest_path="/pinned/source_manifest.csv", prerequisites=[],
            expected_output_keys=["fit"], expected_output_keys_sha256=G.C.object_sha256(["fit"]), **identity)
        task = {key: request[key] for key in (*G.C.IDENTITY_FIELDS, "workflow", "expected_output_keys", "expected_output_keys_sha256")}
        task.update(schema_version="forecast_transition_task_v1", routing_id="UNASSIGNED", routing_revision=1,
            prerequisites=[dict(task_id=p, task_manifest_sha256=identity["task_manifest_sha256"],
                                posterior_target_sha256=identity["posterior_target_sha256"]) for p in G.dependencies(tid)])
        master["templates"][tid] = {
            "request_sha256": write(prepared / "requests" / (tid + ".template.json"), request),
            "control_sha256": write(prepared / "control_tasks" / (tid + ".template.json"), task)}
        master["task_budgets"][tid] = dict(workers=1, cpus=1, memory_bytes=2 * 1024 ** 3,
            wall_seconds=600, cpu_seconds=600, output_bytes=1024 ** 2, log_bytes=1024 ** 2,
            metadata_bytes=1024 ** 2, total_output_bytes=3 * 1024 ** 2)
    master["budget"] = dict(max_submissions=16, max_cpu_seconds=9600, max_wall_seconds=9600,
                            max_output_bytes=32 * 1024 ** 2, max_metadata_bytes=16 * 1024 ** 2)
    master["resource_grant_path"] = str(tmp_path / "resource_grant.json")
    master["resource_grant_sha256"] = write(Path(master["resource_grant_path"]), {
        "grant_id": "exact_grant", "scope": "forecast_transition", "pricefm_grant": False,
        "host": "muscat", "logical_cpus": [24, 25], "max_workers": 2, "expires_utc": "2099-01-01T00:00:00Z"})
    master_path = tmp_path / "external_master.json"
    master["master_sha256"] = write(master_path, {k: v for k, v in master.items() if k not in ("master_sha256", "config")})
    master["master_grant_path"] = str(master_path)
    return master, prepared, state


CHANGES = [
    lambda m: m.update(allow_launch=False),
    lambda m: m.update(authorize_derived_ready_wave_authorizations=False),
    lambda m: m.update(authorize_live_resource_observation=False),
    lambda m: m.update(expires_utc="2000-01-01T00:00:00Z"),
    lambda m: m.update(host="jerez"),
    lambda m: m.update(logical_cpus=[24, 56]),
    lambda m: m.update(max_workers=3),
    lambda m: m["templates"].pop("gft-mq-al"),
    lambda m: m["budget"].update(max_submissions=15),
    lambda m: m["budget"].update(max_cpu_seconds=1),
    lambda m: m["budget"].update(max_output_bytes=1),
    lambda m: m["budget"].update(max_metadata_bytes=1),
    lambda m: m["task_budgets"]["gft-al-p050"].update(cpu_seconds=599),
    lambda m: m["task_budgets"]["gft-al-p050"].update(cpus=2),
]


def accepted_fit(path, digest="2" * 64, passed=True):
    return {"artifacts": [{"relative_path": "fit.rds", "path": str(path), "sha256": digest}],
            "manifest": {"numerical_gates_pass": passed}}


class CampaignTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.master, self.prepared, self.state = make_fixture(self.root)
        self.git = mock.patch.object(G.C, "git_identity", return_value=(self.master["source_commit"], self.master["source_tree"], True))
        self.git.start()
        self.addCleanup(self.git.stop)

    def test_exact_dag_and_initial_ready(self):
        templates = G.validate(self.master, self.prepared)
        self.assertEqual(len(templates), 16)
        self.assertEqual(G.ready(templates, {}, set()), ["gft-al-p050"])
        self.assertEqual(G.dependencies("gft-mq-al"), ["gft-al-p" + p for p in G.TAUS])
        self.assertEqual(G.dependencies("gft-mq-exal"), ["gft-exal-p" + p for p in G.TAUS])

    def test_median_outward_and_matching_exal(self):
        templates = G.validate(self.master, self.prepared)
        accepted = {"gft-al-p050": {}}
        self.assertEqual(set(G.ready(templates, accepted, set(accepted))), {"gft-al-p035", "gft-al-p065", "gft-exal-p050"})
        accepted["gft-al-p035"] = {}
        self.assertIn("gft-al-p020", G.ready(templates, accepted, set(accepted)))
        self.assertNotIn("gft-al-p005", G.ready(templates, accepted, set(accepted)))

    def test_mq_requires_complete_family(self):
        templates = G.validate(self.master, self.prepared)
        accepted = {"gft-al-p" + p: {} for p in G.TAUS}
        self.assertIn("gft-mq-al", G.ready(templates, accepted, set(accepted)))
        self.assertNotIn("gft-mq-exal", G.ready(templates, accepted, set(accepted)))
        self.assertNotIn("gft-al-p050", G.ready(templates, {}, {"gft-al-p050"}))

    def test_master_rejects_expansion_and_unpriced_work(self):
        for i, change in enumerate(CHANGES):
            with self.subTest(mutation=i):
                master = copy.deepcopy(self.master)
                change(master)
                with self.assertRaises(G.C.GateError):
                    G.validate(master, self.prepared)

    def test_source_and_template_drift_block(self):
        with mock.patch.object(G.C, "git_identity", return_value=(self.master["source_commit"], self.master["source_tree"], False)):
            with self.assertRaisesRegex(G.C.GateError, "clean pinned"):
                G.validate(self.master, self.prepared)
        (self.prepared / "requests/gft-al-p050.template.json").write_text("{}")
        with self.assertRaisesRegex(G.C.GateError, "pinned regular"):
            G.validate(self.master, self.prepared)

    def test_plan_is_readonly_and_cannot_launch(self):
        path = self.root / "master.json"
        digest = write(path, self.master)
        stdout = io.StringIO()
        with mock.patch.object(G.subprocess, "run", side_effect=AssertionError("no launch in plan")), contextlib.redirect_stdout(stdout):
            self.assertEqual(G.main(["plan", "--master-grant", str(path), "--master-sha256", digest,
                "--prepared-root", str(self.prepared), "--state-root", str(self.state), "--resource-grant", "/not/read/in/plan"]), 0)
        self.assertFalse(self.state.exists())
        self.assertEqual(json.loads(stdout.getvalue())["status"], "PLAN_ONLY_NO_WRITES_NO_JOBS")

    def test_freeze_uses_accepted_hash_and_preserves_template(self):
        templates = G.validate(self.master, self.prepared)
        before = copy.deepcopy(templates)
        self.state.mkdir()
        paths, auth = G.freeze("gft-al-p035", templates, {"gft-al-p050": accepted_fit("/accepted/nonce/fit.rds")},
                              self.master, self.state, 24, {"host": "muscat"}, {"grant_id": "exact_grant"})
        request, task = G.C.read_json(paths["request"]), G.C.read_json(paths["task"])
        self.assertEqual(request["prerequisites"], [{"task_id": "gft-al-p050", "fit_path": "/accepted/nonce/fit.rds", "fit_sha256": "2" * 64}])
        self.assertEqual(request["config_path"], before["gft-al-p035"][0]["config_path"])
        self.assertEqual(task["request_spec_sha256"], G.C.request_spec_sha256(request))
        self.assertEqual(auth["allowed_task_sha256"][task["task_id"]], G.C.object_sha256(task))
        self.assertEqual(auth["budget"], self.master["budget"])
        self.assertTrue(auth["approved_by"].startswith("coordinator under master "))
        self.assertEqual(templates, before)
        self.assertFalse(paths["ticket"].exists())

    def test_nonconverged_parent_never_freezes_child(self):
        self.state.mkdir()
        with self.assertRaisesRegex(G.C.GateError, "finite/converged"):
            G.freeze("gft-exal-p050", G.validate(self.master, self.prepared),
                {"gft-al-p050": accepted_fit("/retained/failed/fit.rds", passed=False)},
                self.master, self.state, 25, {}, {"grant_id": "exact_grant"})
        self.assertEqual(list(self.state.iterdir()), [])

    def test_frozen_derived_authority_passes_real_controller_loader(self):
        self.state.mkdir()
        paths, auth = G.freeze("gft-al-p050", G.validate(self.master, self.prepared), {}, self.master,
            self.state, 24, {"host": "muscat"}, G.C.read_json(self.master["resource_grant_path"]))
        loaded, digest = G.C.load_authorization(paths["authorization"], G.C.file_sha256(paths["authorization"]), SOURCE)
        self.assertEqual(loaded, auth)
        self.assertEqual(digest, G.C.file_sha256(paths["authorization"]))
        self.assertEqual(loaded["master_grant_path"], self.master["master_grant_path"])
        with Path(self.master["master_grant_path"]).open("a") as stream:
            stream.write("\n")
        with self.assertRaises(G.C.GateError):
            G.C.load_authorization(paths["authorization"], G.C.file_sha256(paths["authorization"]), SOURCE)

    def test_master_cannot_activate_false_source(self):
        with mock.patch.object(G.socket, "gethostname", return_value="muscat"):
            with self.assertRaisesRegex(G.C.GateError, "source launch switch"):
                G.run(self.master, self.prepared, G.validate(self.master, self.prepared), self.state, Path("/no/read"))

    def test_admin_storage_ceiling(self):
        self.state.mkdir()
        (self.state / "one.json").write_bytes(b"bounded receipt")
        G.administrative_bytes(self.state, self.master)
        (self.state / "unsafe").symlink_to("/tmp")
        with self.assertRaisesRegex(G.C.GateError, "symlinks"):
            G.administrative_bytes(self.state, self.master)

    def test_late_admission_preserves_worker_and_cleanup_lifetime(self):
        start = G.C.parse_utc("2030-01-01T00:00:00Z")
        entry = {"created_utc": "2030-01-01T00:00:00Z"}
        G.admission_time(self.master, entry, "gft-al-p050", start + G.dt.timedelta(seconds=2500))
        with self.assertRaisesRegex(G.C.GateError, "late admission"):
            G.admission_time(self.master, entry, "gft-al-p050", start + G.dt.timedelta(seconds=3000))

    def test_execute_rejects_whole_cohort_above_source_ceiling(self):
        self.master["config"]["launch_authorized"] = True
        self.master["config"]["production_budget"] = dict(self.master["budget"], max_metadata_bytes=1)
        with mock.patch.object(G.socket, "gethostname", return_value="muscat"):
            with self.assertRaisesRegex(G.C.GateError, "source price ceiling: metadata_bytes"):
                G.run(self.master, self.prepared, {}, self.state, Path("/never/read"))

    def test_failed_owner_stops_without_retry_or_new_admission(self):
        self.master["config"].update(launch_authorized=True, production_budget=self.master["budget"])
        self.state.mkdir(mode=0o700)
        (self.state / "metadata").mkdir(mode=0o700)
        write(self.state / "gft-al-p050.authorization.json", {})
        grant = Path(self.master["resource_grant_path"])
        ledger = mock.Mock()
        ledger.attempts.return_value = [{"state": "failed", "nonce": "retained_failure"}]
        with mock.patch.object(G.socket, "gethostname", return_value="muscat"), \
             mock.patch.object(G.C, "verify_file_manifest", return_value=[]), \
             mock.patch.object(G.C, "verify_production_config"), \
             mock.patch.object(G, "ledger_for", return_value=ledger), \
             mock.patch.object(G.subprocess, "run", side_effect=AssertionError("no retry/new launch")):
            with self.assertRaisesRegex(G.C.GateError, "workers now terminal"):
                G.run(self.master, self.prepared, G.validate(self.master, self.prepared), self.state, grant)
        self.assertTrue((self.state / "STOP_ADMISSION.json").is_file())
        ledger.close.assert_called_once()

    def test_parent_hash_changes_child_scientific_identity(self):
        templates = G.validate(self.master, self.prepared)
        self.state.mkdir()
        other = self.root / "other_state"
        other.mkdir()
        first, _ = G.freeze("gft-al-p035", templates, {"gft-al-p050": accepted_fit("/accepted/fit.rds", "2" * 64)},
                            self.master, self.state, 24, {}, {"grant_id": "g"})
        second, _ = G.freeze("gft-al-p035", templates, {"gft-al-p050": accepted_fit("/accepted/fit.rds", "3" * 64)},
                             self.master, other, 24, {}, {"grant_id": "g"})
        self.assertNotEqual(G.C.read_json(first["task"])["request_spec_sha256"],
                            G.C.read_json(second["task"])["request_spec_sha256"])

    def test_independent_proof_requires_dead_owner_and_no_session_children(self):
        proc = self.root / "proc"
        boot = proc / "sys/kernel/random/boot_id"
        boot.parent.mkdir(parents=True)
        boot.write_text("synthetic-boot")
        terminal = {"host": "muscat", "job_id": "pid:900:synthetic-boot:42", "accounting_complete": True,
            "supervisor_identity": {"pid": 900, "boot_id": "synthetic-boot", "start_ticks": 42},
            "child_identity": {"pid": 901, "boot_id": "synthetic-boot", "start_ticks": 43}}
        row = {"nonce": "nonce", "job_id": terminal["job_id"]}
        paths = {"/proc": proc, "/proc/sys/kernel/random/boot_id": boot}
        with mock.patch.object(G, "Path", side_effect=lambda path: paths[path]):
            proof = G.independent_proof(terminal, row)
            self.assertTrue(proof["no_orphans"])
            fields = ["S", "1", "901", "901"] + ["0"] * 16
            fields[19] = "100"
            stat = proc / "950/stat"
            stat.parent.mkdir()
            stat.write_text("950 (orphaned compiler) " + " ".join(fields))
            with self.assertRaisesRegex(G.C.GateError, "live supervisor/worker/session"):
                G.independent_proof(terminal, row)
            stat.unlink()
            with self.assertRaisesRegex(G.C.GateError, "exact locally dispatched"):
                G.independent_proof(terminal, dict(row, job_id="pid:different"))


if __name__ == "__main__":
    unittest.main()
