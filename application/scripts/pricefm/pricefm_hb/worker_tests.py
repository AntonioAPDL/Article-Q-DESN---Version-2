#!/usr/bin/env python3
"""Stdlib-only worker interface checks; no subprocess or scientific execution."""
from __future__ import annotations

import contextlib
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from pricefm_hb import control, registry as reg, science, worker
from pricefm_hb.environment import EnvironmentError, THREAD_ENV


ALLOCATION = {"job_id": "12345", "node": "node1", "affinity": [4],
              "cpus_per_task": 1, "allocation_nodes": ["node1"]}
EVIDENCE = ("interpreter-artifact-manifest.json", "runtime-verification.json", "conda-explicit.txt",
            "conda-create.log", "venv-create.log", "pip-install.log", "pip-check.log",
            "runtime-verification.log")


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.release = Path(self.temp.name) / "release"
        (self.release / "code/pricefm_hb").mkdir(parents=True)
        (self.release / "code/pricefm_hb/environment_build.sh").write_text("# mocked build\n")
        (self.release / "env").mkdir()
        self.outputs = self.release / "outputs"
        self.calls = []
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(worker, "require_compute", return_value=ALLOCATION).start()
        self.process = mock.patch.object(worker.subprocess, "run", side_effect=self.fake_build).start()

    def seal(self, kind="environment"):
        self.manifest = control.seal_release(
            self.release, {"namespace": "TEST", "kind": kind}, ["reviewed-worker"],
            {"cpus": 1, "memory_MiB": 4096, "wall_seconds": 1200},
            runtime_python="/home/user/verified/runtime/venv/bin/python",
            environment_bundle="/home/user/verified/env")
        self.release_sha = reg.digest(self.release / "release.json")
        self.outputs.mkdir()
        return self.manifest

    def fake_build(self, argv, *, env, check, timeout):
        self.calls.append((argv, env, timeout))
        self.assertTrue(check)
        self.assertEqual(argv[:2], ["bash", str(self.release / "code/pricefm_hb/environment_build.sh")])
        self.assertEqual(argv[argv.index("--bundle") + 1], str(self.release / "env"))
        self.assertEqual(argv[argv.index("--report") + 1], str(self.outputs / "build-report.json"))
        prefix = Path(argv[argv.index("--prefix") + 1])
        prefix.mkdir()
        for name in EVIDENCE:
            (prefix / name).write_text("fixture evidence: " + name + "\n")
        # Real conda/venv trees contain links. Only evidence may be retrieved.
        (prefix / "venv/bin").mkdir(parents=True)
        (prefix / "venv/bin/python").symlink_to("/usr/bin/python3")
        reg.write(self.outputs / "build-report.json", {"status": "verified", "allocation": ALLOCATION})
        return subprocess.CompletedProcess(argv, 0)

    def test_environment_build_flags_exports_and_evidence_seal(self):
        self.seal()
        result = worker.execute(self.release, self.release_sha)
        self.assertEqual(result, {"status": "PASS_QUALIFICATION", "kind": "environment"})
        self.assertEqual(len(self.calls), 1)
        _, variables, timeout = self.calls[0]
        self.assertEqual(timeout, 1170)
        for name, value in THREAD_ENV.items():
            self.assertEqual(variables[name], value)
        self.assertEqual(variables["PYTHONNOUSERSITE"], "1")
        self.assertEqual(variables["PYTHONDONTWRITEBYTECODE"], "1")
        self.assertEqual(variables["PYTHONPATH"], str(self.release / "code"))
        evidence = self.outputs / "environment-evidence"
        self.assertEqual({path.name for path in evidence.iterdir()}, set(EVIDENCE))
        self.assertFalse(any(path.is_symlink() for path in self.outputs.rglob("*")))
        seal = reg.read(self.outputs / "completed_evidence.json")
        self.assertTrue(seal["application_passed"])
        self.assertEqual(seal["allocation"], ALLOCATION)
        self.assertEqual(seal["fits"], 0)
        self.assertEqual(seal["official_origins"], 0)
        claim = {"task_key": reg.identity(self.manifest["task"]), "job_id": ALLOCATION["job_id"],
                 "release_sha256": self.release_sha}
        self.assertEqual(control.validate_outputs(self.outputs, claim, self.manifest), seal)

    def test_different_build_allocation_is_rejected(self):
        self.seal()
        def changed(*args, **kwargs):
            result = self.fake_build(*args, **kwargs)
            reg.write(self.outputs / "build-report.json", {"status": "verified", "allocation":
                dict(ALLOCATION, job_id="different")})
            return result
        self.process.side_effect = changed
        with self.assertRaisesRegex(RuntimeError, "qualification failed"):
            worker.execute(self.release, self.release_sha)
        seal = reg.read(self.outputs / "completed_evidence.json")
        self.assertFalse(seal["application_passed"])
        self.assertEqual(seal["error"]["type"], "ValueError")
        self.assertIn("attestation mismatch", seal["error"]["message"])

    def test_subprocess_failure_retains_logs_and_false_application_seal(self):
        self.seal()
        def failed(*args, **kwargs):
            self.fake_build(*args, **kwargs)
            raise subprocess.CalledProcessError(1, args[0])
        self.process.side_effect = failed
        with self.assertRaisesRegex(RuntimeError, "qualification failed"):
            worker.execute(self.release, self.release_sha)
        seal = reg.read(self.outputs / "completed_evidence.json")
        self.assertFalse(seal["application_passed"])
        self.assertEqual(seal["error"]["type"], "CalledProcessError")
        self.assertTrue((self.outputs / "worker-failure.json").is_file())
        self.assertEqual({path.name for path in (self.outputs / "environment-evidence").iterdir()},
                         {name for name in EVIDENCE if name.endswith(".log")})

    def test_changed_manifest_is_rejected_before_any_process(self):
        self.seal()
        with self.assertRaisesRegex(ValueError, "manifest digest mismatch"):
            worker.execute(self.release, "0" * 64)
        self.process.assert_not_called()

    def test_existing_outputs_prevent_retry(self):
        self.seal()
        (self.outputs / "retained").write_text("original")
        with self.assertRaisesRegex(FileExistsError, "no retry/overwrite"):
            worker.execute(self.release, self.release_sha)
        self.process.assert_not_called()
        self.assertEqual((self.outputs / "retained").read_text(), "original")

    def test_compute_guard_failure_never_launches_build(self):
        self.seal()
        with mock.patch.object(worker, "require_compute", side_effect=EnvironmentError("no compute")):
            with self.assertRaises(EnvironmentError):
                worker.execute(self.release, self.release_sha)
        self.process.assert_not_called()
        self.assertEqual(list(self.outputs.iterdir()), [])

    def test_parity_subprocess_arguments_match_actual_science_parser(self):
        self.seal("parity")
        parser_calls = []
        def parity(argv, *, env, check, timeout):
            self.assertTrue(check)
            self.assertEqual({name: env[name] for name in THREAD_ENV}, THREAD_ENV)
            if "pricefm_hb.environment" in argv:
                reg.write(self.outputs / "environment-runtime.json", {"status": "verified", "threadpoolctl": []})
                return subprocess.CompletedProcess(argv, 0)
            self.assertEqual(argv[:4], [self.manifest["runtime_python"], "-B", "-m", "pricefm_hb.science"])
            expected_manifest = str(self.release / "fixture/manifest.json")
            expected_output = str(self.outputs / "TEST/parity")
            with mock.patch.object(science, "run_fixture", return_value={"status": "PASS_TEST_FORECAST_PARITY"}) as run, \
                 mock.patch.object(sys, "argv", ["science"] + argv[4:]), contextlib.redirect_stdout(io.StringIO()):
                science.main()
                run.assert_called_once_with(expected_manifest, expected_output)
            parser_calls.append(True)
            (self.outputs / "TEST/parity").mkdir(parents=True)
            reg.write(self.outputs / "TEST/parity/parity.json", {"status": "PASS_TEST_FORECAST_PARITY", "accepted": True})
            return subprocess.CompletedProcess(argv, 0)
        self.process.side_effect = parity
        self.assertEqual(worker.execute(self.release, self.release_sha)["kind"], "parity")
        self.assertEqual(parser_calls, [True])


if __name__ == "__main__":
    unittest.main()
