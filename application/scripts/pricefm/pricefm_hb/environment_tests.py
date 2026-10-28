#!/usr/bin/env python3
"""Stdlib-only checks: hash failures, exact closure, compute guards and failures."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from pricefm_hb import environment as env


class BundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.bundle = Path(self.temp.name) / "bundle"
        (self.bundle / "wheels").mkdir(parents=True)
        packages = {}
        for raw_name in env.ROOT_PACKAGES:
            name = env.canonical(raw_name)
            packages[name] = {"name": raw_name, "version": "1.0", "active_dependencies": []}
            wheel = self.bundle / "wheels" / (name + "-1.0-py3-none-any.whl")
            with zipfile.ZipFile(wheel, "w") as archive:
                archive.writestr(name + "-1.0.dist-info/METADATA",
                                 "Metadata-Version: 2.1\nName: " + raw_name + "\nVersion: 1.0\n")
        self.source = {"schema": env.SCHEMA, "python_version": env.PYTHON_VERSION,
                       "roots": [env.canonical(name) for name in env.ROOT_PACKAGES],
                       "packages": dict(sorted(packages.items()))}
        env.write_new(self.bundle / "source-environment.json", env.json_bytes(self.source))
        env.write_new(self.bundle / "requirements.versions.txt", "".join(
            item["name"] + "==1.0\n" for item in self.source["packages"].values()))

        def upstream(name, version, filename, sha):
            return {"metadata_url": "https://pypi.org/pypi/" + name + "/1.0/json",
                    "url": "https://files.pythonhosted.org/" + filename,
                    "sha256": sha, "size": (self.bundle / "wheels" / filename).stat().st_size}

        with mock.patch.object(env, "pypi_artifact", side_effect=upstream):
            env.seal(self.bundle)

    def test_offline_audit_accepts_exact_hashed_wheel_closure(self):
        with mock.patch.object(env.urllib.request, "urlopen", side_effect=AssertionError("network")):
            result = env.audit_bundle(self.bundle)
        self.assertEqual(result["packages"], len(env.ROOT_PACKAGES))
        self.assertEqual(result["status"], "verified")

    def test_changed_wheel_is_rejected_before_install(self):
        wheel = next((self.bundle / "wheels").iterdir())
        with wheel.open("ab") as handle:
            handle.write(b"corruption")
        with self.assertRaisesRegex(env.EnvironmentError, "wheel hash mismatch"):
            env.audit_bundle(self.bundle)

    def test_extra_wheel_is_rejected(self):
        (self.bundle / "wheels" / "extra.whl").write_bytes(b"unexpected")
        with self.assertRaisesRegex(env.EnvironmentError, "extra/missing wheel"):
            env.audit_bundle(self.bundle)

    def test_symlink_wheel_directory_is_rejected(self):
        wheels = self.bundle / "wheels"
        moved = self.bundle / "moved-wheels"
        wheels.rename(moved)
        wheels.symlink_to(moved, target_is_directory=True)
        with self.assertRaisesRegex(env.EnvironmentError, "symlink path"):
            env.audit_bundle(self.bundle)

    def test_modified_lock_is_rejected(self):
        with (self.bundle / "requirements.lock").open("a") as handle:
            handle.write("unlocked==1.0\n")
        with self.assertRaisesRegex(env.EnvironmentError, "bundle hash mismatch"):
            env.audit_bundle(self.bundle)

    def test_missing_transfer_checksum_is_rejected(self):
        checksums = self.bundle / "SHA256SUMS"
        checksums.write_text("\n".join(checksums.read_text().splitlines()[1:]) + "\n")
        with self.assertRaisesRegex(env.EnvironmentError, "incomplete SHA256SUMS"):
            env.audit_bundle(self.bundle)

    def test_manifest_cannot_escape_wheel_directory(self):
        path = self.bundle / "wheel-manifest.json"
        manifest = json.loads(path.read_text())
        manifest["artifacts"][0]["filename"] = "../secret.whl"
        path.write_bytes(env.json_bytes(manifest))
        with self.assertRaisesRegex(env.EnvironmentError, "unsafe wheel path"):
            env.audit_bundle(self.bundle)

    def test_evidence_retries_are_idempotent_and_immutable(self):
        path = self.bundle / "requirements.lock"
        env.write_new(path, path.read_bytes())
        with self.assertRaisesRegex(env.EnvironmentError, "refusing to replace"):
            env.write_new(path, "different")

    def test_conda_failure_writes_report_and_does_not_continue(self):
        prefix, report = Path(self.temp.name) / "build", Path(self.temp.name) / "report.json"
        failure = subprocess.CalledProcessError(1, ["conda", "create"])
        with mock.patch.object(env, "require_compute", return_value={"job_id": "1"}), \
             mock.patch.object(env, "run_logged", side_effect=failure) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                env.build(self.bundle, prefix, report, "/conda")
        self.assertEqual(run.call_count, 1)
        self.assertEqual(json.loads(report.read_text())["status"], "failed")
        self.assertFalse((prefix / "venv").exists())


class ComputeGuardTests(unittest.TestCase):
    def test_login_host_is_rejected_even_with_forged_allocation_variables(self):
        variables = {"SLURM_JOB_ID": "123", "SLURM_CPUS_PER_TASK": "1",
                     "SLURM_JOB_NODELIST": "login1"}
        runner = mock.Mock(return_value=subprocess.CompletedProcess([], 0, "login1\n"))
        with self.assertRaisesRegex(env.EnvironmentError, "login host"):
            env.require_compute(variables, "login1", [31], runner)

    def test_missing_allocation_fails_before_node_query(self):
        runner = mock.Mock()
        with self.assertRaisesRegex(env.EnvironmentError, "Slurm compute allocation"):
            env.require_compute({}, "node1", [31], runner)
        runner.assert_not_called()

    def test_more_than_one_cpu_fails_before_node_query(self):
        runner = mock.Mock()
        with self.assertRaisesRegex(env.EnvironmentError, "exactly one"):
            env.require_compute({"SLURM_JOB_ID": "123", "SLURM_CPUS_PER_TASK": "1"},
                                "node1", [1, 2], runner)
        runner.assert_not_called()

    def test_runtime_verify_cannot_import_numerics_on_login(self):
        with mock.patch.dict(env.os.environ, {}, clear=True), \
             mock.patch.object(env, "audit_bundle", side_effect=AssertionError("audit reached")):
            with self.assertRaisesRegex(env.EnvironmentError, "Slurm compute allocation"):
                env.verify_runtime("/unused", "/unused")

    def test_one_cpu_single_compute_node_is_accepted(self):
        variables = {"SLURM_JOB_ID": "123", "SLURM_CPUS_PER_TASK": "1",
                     "SLURM_JOB_NODELIST": "node1"}
        runner = mock.Mock(return_value=subprocess.CompletedProcess([], 0, "node1\n"))
        result = env.require_compute(variables, "node1", [31], runner)
        self.assertEqual(result["affinity"], [31])
        self.assertEqual(result["node"], "node1")

    def test_default_dependency_markers_use_target_python_and_no_extras(self):
        dependencies = env.active_requirements([
            "numpy>=1.22; python_version < '3.11'",
            "numpy>=1.23; python_version == '3.11'",
            "pytest; extra == 'test'", "six>=1.5"])
        self.assertEqual([item["name"] for item in dependencies], ["numpy", "six"])


class InterpreterArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.interpreter = self.root / "interpreter"
        self.cache = self.root / "cache"
        self.report = self.root / "artifacts.json"
        (self.interpreter / "conda-meta").mkdir(parents=True)
        self.cache.mkdir()
        self.filename = "python-3.11.13-example_0.conda"
        artifact = self.cache / self.filename
        artifact.write_bytes(b"example pinned interpreter artifact bytes")
        self.package = {"name": "python", "version": "3.11.13", "build": "example_0",
                        "fn": self.filename, "sha256": env.digest(artifact),
                        "url": "https://conda.anaconda.org/conda-forge/linux-64/" + self.filename}
        self.metadata_path = self.interpreter / "conda-meta" / "python-3.11.13-example_0.json"
        self.write_metadata()

    def write_metadata(self):
        self.metadata_path.write_bytes(env.json_bytes(self.package))

    def test_cached_artifact_matches_installed_metadata_and_exact_python(self):
        result = env.interpreter_artifacts(self.interpreter, self.cache, self.report)
        self.assertEqual(result["python"]["version"], "3.11.13")
        self.assertEqual(result["artifact_count"], 1)
        self.assertEqual(result["manifest_sha256"], env.digest(self.report))

    def test_corrupted_conda_download_is_rejected(self):
        (self.cache / self.filename).write_bytes(b"changed")
        with self.assertRaisesRegex(env.EnvironmentError, "cached artifact SHA256 mismatch"):
            env.interpreter_artifacts(self.interpreter, self.cache, self.report)
        self.assertFalse(self.report.exists())

    def test_unofficial_conda_artifact_host_is_rejected(self):
        self.package["url"] = self.package["url"].replace("conda.anaconda.org", "example.org")
        self.write_metadata()
        with self.assertRaisesRegex(env.EnvironmentError, "untrusted conda artifact provenance"):
            env.interpreter_artifacts(self.interpreter, self.cache, self.report)

    def test_default_anaconda_channel_is_not_authorized(self):
        self.package["url"] = "https://repo.anaconda.com/pkgs/main/linux-64/" + self.filename
        self.write_metadata()
        with self.assertRaisesRegex(env.EnvironmentError, "untrusted conda artifact provenance"):
            env.interpreter_artifacts(self.interpreter, self.cache, self.report)

    def test_conda_forge_url_cannot_change_scheme_channel_or_add_credentials(self):
        valid = self.package["url"]
        for url in (valid.replace("https:", "http:"),
                    valid.replace("/conda-forge/", "/another-channel/"),
                    valid.replace("https://", "https://user@"),
                    valid + "?token=not-a-real-token", valid + "#fragment",
                    valid.replace("conda.anaconda.org/", "conda.anaconda.org:443/")):
            with self.subTest(url=url):
                self.package["url"] = url
                self.write_metadata()
                with self.assertRaisesRegex(env.EnvironmentError, "untrusted conda artifact provenance"):
                    env.interpreter_artifacts(self.interpreter, self.cache, self.report)

    def test_official_conda_forge_noarch_artifact_is_accepted(self):
        self.package["url"] = self.package["url"].replace("/linux-64/", "/noarch/")
        self.write_metadata()
        result = env.interpreter_artifacts(self.interpreter, self.cache, self.report)
        self.assertEqual(result["python"]["sha256"], self.package["sha256"])

    def test_different_python_patch_is_rejected(self):
        self.package["version"] = "3.11.14"
        self.write_metadata()
        with self.assertRaisesRegex(env.EnvironmentError, "lacks exact Python 3.11.13"):
            env.interpreter_artifacts(self.interpreter, self.cache, self.report)

    def test_missing_conda_artifact_hash_is_rejected(self):
        self.package.pop("sha256")
        self.write_metadata()
        with self.assertRaisesRegex(env.EnvironmentError, "untrusted conda artifact provenance"):
            env.interpreter_artifacts(self.interpreter, self.cache, self.report)


class ReferenceProfileTests(unittest.TestCase):
    def test_optional_default_does_not_assert_a_historical_dispatch(self):
        self.assertEqual(env.reference_environment({}), {})
        self.assertEqual(env.verify_reference_profile(None, [], {}), {"enabled": False, "environment": {}})

    def test_both_exact_controls_are_required_before_import(self):
        for variables in ({"OPENBLAS_CORETYPE": "Sandybridge"}, {"NPY_DISABLE_CPU_FEATURES": "AVX2,FMA3"},
                          {"OPENBLAS_CORETYPE": "Haswell", "NPY_DISABLE_CPU_FEATURES": "AVX2,FMA3"},
                          {"OPENBLAS_CORETYPE": "Sandybridge", "NPY_DISABLE_CPU_FEATURES": "AVX2"}):
            with self.subTest(variables=variables), self.assertRaisesRegex(env.EnvironmentError, "both exact"):
                env.reference_environment(variables)
        self.assertEqual(env.reference_environment(env.REFERENCE_NUMERICAL_ENV), env.REFERENCE_NUMERICAL_ENV)

    def numpy(self, avx2=False, fma3=False):
        dispatch = env.REFERENCE_NUMERICAL_ENV["NPY_DISABLE_CPU_FEATURES"].split(",")
        features = dict.fromkeys(dispatch, False)
        features.update(AVX2=avx2, FMA3=fma3, SSE2=True, AVX512VL=True)
        return SimpleNamespace(_core=SimpleNamespace(_multiarray_umath=SimpleNamespace(
            __cpu_features__=features, __cpu_dispatch__=dispatch)))

    def test_actual_reference_features_and_native_pools_are_attested(self):
        pools = [{"internal_api": "openblas", "architecture": "Sandybridge", "num_threads": 1},
                 {"internal_api": "openblas", "architecture": "Sandybridge", "num_threads": 1}]
        result = env.verify_reference_profile(self.numpy(), pools, env.REFERENCE_NUMERICAL_ENV)
        self.assertTrue(result["enabled"])
        self.assertFalse(result["numpy_cpu_features"]["AVX2"])
        self.assertFalse(result["numpy_cpu_features"]["FMA3"])
        self.assertFalse(result["numpy_cpu_features"]["F16C"])
        self.assertTrue(result["numpy_cpu_features"]["AVX512VL"])
        self.assertEqual(result["openblas_architectures"], ["Sandybridge", "Sandybridge"])

    def test_haswell_pool_or_enabled_feature_is_rejected(self):
        reference = [{"internal_api": "openblas", "architecture": "Sandybridge", "num_threads": 1}]
        for numpy, pools in ((self.numpy(avx2=True), reference), (self.numpy(fma3=True), reference),
                             (self.numpy(), [{"internal_api": "openblas", "architecture": "Haswell", "num_threads": 1}]),
                             (self.numpy(), [])):
            with self.subTest(pools=pools), self.assertRaisesRegex(env.EnvironmentError, "actual NumPy/OpenBLAS"):
                env.verify_reference_profile(numpy, pools, env.REFERENCE_NUMERICAL_ENV)

    def test_any_enabled_compiled_AVX512_target_is_rejected(self):
        numpy = self.numpy()
        numpy._core._multiarray_umath.__cpu_features__["AVX512_SKX"] = True
        with self.assertRaisesRegex(env.EnvironmentError, "actual NumPy/OpenBLAS"):
            env.verify_reference_profile(numpy, [{"internal_api": "openblas", "architecture": "Sandybridge", "num_threads": 1}], env.REFERENCE_NUMERICAL_ENV)

    def test_live_reference_guard_fails_before_numpy_without_compute(self):
        with mock.patch.dict(env.os.environ, {}, clear=True):
            with self.assertRaisesRegex(env.EnvironmentError, "Slurm compute allocation"):
                env.require_reference_profile()

    def test_loaded_native_library_hashes_cover_both_actual_files(self):
        with tempfile.TemporaryDirectory() as root:
            paths = [Path(root) / name for name in ("numpy-blas.so", "scipy-blas.so")]
            for path in paths:
                path.write_bytes(b"synthetic test library bytes: " + path.name.encode())
            pools = [{"internal_api": "openblas", "filepath": str(path)} for path in paths]
            self.assertEqual(env.native_library_hashes(pools), {str(path): env.digest(path) for path in paths})
            with self.assertRaisesRegex(env.EnvironmentError, "exact two bounded"):
                env.native_library_hashes(pools[:1])


if __name__ == "__main__":
    unittest.main()
