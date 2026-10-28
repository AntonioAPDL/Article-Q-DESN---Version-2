"""Stdlib/mocked tests: no numerical imports, arrays, forecasts or R calls."""
from __future__ import annotations

import ast
import builtins
import datetime as dt
import hashlib
import os
from pathlib import Path
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
import zipfile

from . import fixture as f
from . import science as s


class FixtureTests(unittest.TestCase):
    def test_metadata_headers_do_not_need_numpy_or_array_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            packet = Path(directory) / "small.npz"
            header = b"{'descr': '<f8', 'fortran_order': False, 'shape': (8, 96, 7)}\n"
            # A header-only synthetic member proves the preparation reader does
            # not deserialize a numerical payload; replay validates the arrays.
            with zipfile.ZipFile(packet, "w") as archive:
                archive.writestr("prediction.npy", b"\x93NUMPY\x01\x00" + struct.pack("<H", len(header)) + header)
            result = f.npz_headers(packet)
            self.assertEqual(result["prediction"]["shape"], [8, 96, 7])
            self.assertEqual(result["prediction"]["dtype"], "<f8")

    def test_bad_header_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            packet = Path(directory) / "bad.npz"
            with zipfile.ZipFile(packet, "w") as archive:
                archive.writestr("../bad.npy", b"bad")
            with self.assertRaisesRegex(ValueError, "invalid NPZ"):
                f.npz_headers(packet)

    def test_resolver_hash_and_relocation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            physical = root / "files/original/fit.rds"
            physical.parent.mkdir(parents=True)
            physical.write_bytes(b"opaque-rds-provenance")
            manifest = {"assets": {"/original/fit.rds": dict(path="files/original/fit.rds",
                bytes=physical.stat().st_size, sha256=f.digest(physical))}}
            resolver = f.Resolver(root, manifest)
            self.assertEqual(resolver.path("/original/fit.rds"), physical)
            self.assertEqual(resolver.directory("/original"), physical.parent)
            physical.write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "staged bytes differ"):
                resolver.path("/original/fit.rds")

    def test_resolver_rejects_unmapped_and_escaping_files(self):
        with tempfile.TemporaryDirectory() as directory:
            resolver = f.Resolver(directory, {"assets": {"/original": dict(path="../outside", bytes=0, sha256="x")}})
            with self.assertRaisesRegex(ValueError, "unsafe"):
                resolver.path("/original")
            with self.assertRaises(KeyError):
                resolver.path("/missing-rds")

    def test_stage_copies_opaque_bytes_without_importing_science(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = root / "original.rds"
            original.write_bytes(b"never-deserialized")
            target = root / "stage"
            target.mkdir()
            assets = {str(original): dict(path="files/fit.rds", bytes=original.stat().st_size, sha256=f.digest(original))}
            manifest = dict(assets=assets, size=dict(files=1, bytes=18))
            resolver = f.Resolver(target, manifest)
            manifest_path = target / "manifest.json"
            manifest_path.write_text("synthetic manifest")
            with patch.object(f, "load_fixture", return_value=(manifest, resolver)):
                result = f.stage_fixture(manifest_path)
            self.assertEqual(resolver.path(original).read_bytes(), b"never-deserialized")
            self.assertEqual(result["status"], "STAGED_HASH_VERIFIED_NO_NUMERICAL_IMPORTS")

    def test_manifest_seal_tampering_fails_before_file_verification(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.json"
            path.write_text("{}")
            path.with_suffix(".sha256").write_text("0" * 64)
            with self.assertRaisesRegex(ValueError, "manifest seal"):
                f.load_fixture(path)

    def test_fixed_selection_cannot_be_changed(self):
        with self.assertRaisesRegex(ValueError, "selection is fixed"):
            f.plan_fixture("/unused", task_name="some-favorable-loss-task")

    def test_identity_rejects_subchunk_seed_clock_or_parent_changes(self):
        positions = list(range(506, 514))
        times = [(dt.datetime(2023, 6, 25, tzinfo=dt.timezone.utc) + dt.timedelta(days=i)).isoformat() for i in range(8)]
        task = dict(name=f.TASK, region="EE", role="C0", seed_index=0, split=1, paths=100,
            forecast_seed=2026101502, test_opened=False, posterior_updated=False, new_model_fits=0,
            clock_offsets_steps=[0, 24, 48, 72], daily_origin_positions=positions,
            origin_timestamps={"0": times}, validation_origin_positions=positions, train_origin_positions=[0, 1],
            scientific_identity_sha256="science", parent_source={"head": "parent"}, parent_seal_sha256="seal",
            scaler_sha256="scaler", bank={"path": "training"}, kernel_sha256="kernel")
        descriptor = dict(name=f.CHUNK, clock_offset_steps=0, start=0, origin_positions=positions,
            origin_timestamps=times, stable_rng_origin_keys=[p * 96 for p in positions])
        source = {"head": "original"}
        context = f.scientific_context(task, source)
        metadata = dict(certified=True, descriptor=descriptor, context=context, posterior_updated=False, new_model_fits=0)
        seal = dict(metadata=dict(certified=True, context=context), artifacts={"chunk.json": "chunk", "predictions.npz": f.REFERENCE_SHA256})
        f.validate_scientific_identity(task, descriptor, metadata, seal, source)
        for change in (dict(paths=1), dict(forecast_seed=17), dict(parent_seal_sha256="replacement"), dict(test_opened=True)):
            with self.subTest(change=change), self.assertRaises(ValueError):
                f.validate_scientific_identity({**task, **change}, descriptor, metadata, seal, source)
        with self.assertRaisesRegex(ValueError, "eight-origin"):
            f.validate_scientific_identity(task, {**descriptor, "origin_positions": positions[:1]}, metadata, seal, source)
        with self.assertRaisesRegex(ValueError, "eight-origin"):
            f.validate_scientific_identity(task, {**descriptor, "clock_offset_steps": 24}, metadata, seal, source)


class SourceBridgeTests(unittest.TestCase):
    @staticmethod
    def bindings():
        return {"INT_ARRAYS": frozenset(f.INT_KEYS), "dt": dt, "kernel": Mock(), "validate_arrays": Mock(),
            **{n: vars(builtins)[n] for n in f.FUNCTION_GLOBALS if n in vars(builtins)}}

    def test_exact_original_function_can_be_bound_without_calling_it(self):
        path, sha = f.SOURCE_PINS["retained"]
        # Reading and compiling original source is not a numerical import.
        bindings = self.bindings()
        function = s.extract_function(path, sha, f.FUNCTION_AST_SHA256, bindings)
        self.assertEqual(function.__name__, "retained_chunk")
        self.assertIs(function.__globals__["kernel"], bindings["kernel"])
        self.assertIsNone(function.__defaults__[0])
        self.assertNotIn("ROOT", function.__globals__)

    def test_tampered_source_ast_and_missing_globals_are_rejected(self):
        path, sha = f.SOURCE_PINS["retained"]
        with tempfile.TemporaryDirectory() as directory:
            changed = Path(directory) / "changed.py"
            changed.write_text(Path(path).read_text() + "\n# tampered bytes\n")
            with self.assertRaisesRegex(ValueError, "source bytes"):
                s.extract_function(changed, sha, f.FUNCTION_AST_SHA256, self.bindings())
        with self.assertRaisesRegex(ValueError, "AST"):
            s.extract_function(path, sha, "0" * 64, self.bindings())
        bindings = self.bindings()
        del bindings["kernel"]
        with self.assertRaisesRegex(ValueError, "globals"):
            s.extract_function(path, sha, f.FUNCTION_AST_SHA256, bindings)

    def test_unsupported_global_fails_even_with_new_source_and_ast_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "unsupported.py"
            path.write_text("def retained_chunk(context, task, descriptor, heartbeat, deterministic_override=None):\n    return forbidden_global()\n")
            node = ast.parse(path.read_text()).body[0]
            sha = hashlib.sha256(ast.dump(node, include_attributes=False).encode()).hexdigest()
            with self.assertRaisesRegex(ValueError, "globals"):
                s.extract_function(path, f.digest(path), sha, self.bindings())

    def test_decorated_or_executable_default_function_fails_before_exec(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "unsupported.py"
            for source, message in (("@decorator\ndef retained_chunk():\n    pass\n", "undecorated"),
                    ("def retained_chunk(value=execute_now()):\n    pass\n", "defaults")):
                path.write_text(source)
                node = ast.parse(source).body[0]
                sha = hashlib.sha256(ast.dump(node, include_attributes=False).encode()).hexdigest()
                with self.subTest(source=source), self.assertRaisesRegex(ValueError, message):
                    s.extract_function(path, f.digest(path), sha, self.bindings())


class ContextMappingTests(unittest.TestCase):
    def setup_context(self):
        scaler = dict(price_mean=7.0, price_scale=3.0)
        train, validation = [0, 1], [2, 3]
        runtime = SimpleNamespace(internal_splits=Mock(return_value=[dict(train=SimpleNamespace(tolist=lambda: train), validation=SimpleNamespace(tolist=lambda: validation))]),
            standardize_from_training_origins=Mock(return_value=("scaled", scaler)),
            load_normal_fit=Mock(return_value=dict(beta_mean=[1, 2])))
        core = SimpleNamespace(dependencies=Mock(return_value=runtime), load_arrays=Mock(return_value=SimpleNamespace(response=[0, 1, 2, 3])))
        resolver = SimpleNamespace(directory=lambda path: Path("/stage") / path.strip("/"), path=lambda path: Path("/stage") / path.strip("/"))
        task = dict(split=1, train_origin_positions=train, validation_origin_positions=validation,
            bank=dict(path="/logical/bank.npz"), scaler_path="/logical/scaler.json", parent_fit="/logical/fit")
        manifest = dict(task=task, dependency_root="/logical/dependency", size=dict(normal_dimension=2))
        return manifest, resolver, core, runtime, scaler

    def test_only_normal_loader_receives_resolved_parent_moments(self):
        manifest, resolver, core, runtime, scaler = self.setup_context()
        with patch.object(s, "_assert_frozen_imports"), patch.object(s, "read_json", return_value=scaler):
            context = s._context(manifest, resolver, core, SimpleNamespace(numerical_threadpools=lambda: ["one-thread"]))
        core.dependencies.assert_called_once_with(Path("/stage/logical/dependency"))
        runtime.load_normal_fit.assert_called_once_with(Path("/stage/logical/fit"))
        self.assertEqual(manifest["task"]["parent_fit"], "/logical/fit")
        self.assertEqual(context["scaled"], "scaled")

    def test_cohort_or_scaler_mismatch_stops_before_moment_loading(self):
        manifest, resolver, core, runtime, scaler = self.setup_context()
        manifest["task"]["train_origin_positions"] = [99]
        with patch.object(s, "_assert_frozen_imports"), self.assertRaisesRegex(RuntimeError, "cohort"):
            s._context(manifest, resolver, core, SimpleNamespace(numerical_threadpools=lambda: []))
        runtime.load_normal_fit.assert_not_called()
        manifest, resolver, core, runtime, scaler = self.setup_context()
        with patch.object(s, "_assert_frozen_imports"), patch.object(s, "read_json", return_value=dict(price_mean=0.0)), self.assertRaisesRegex(RuntimeError, "scaler"):
            s._context(manifest, resolver, core, SimpleNamespace(numerical_threadpools=lambda: []))
        runtime.load_normal_fit.assert_not_called()


class ExecutionGateTests(unittest.TestCase):
    def test_no_local_scientific_execution(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(s, "load_fixture") as load:
            with self.assertRaisesRegex(RuntimeError, "Slurm"):
                s.run_fixture("manifest", "/tmp/TEST/result")
            load.assert_not_called()

    def test_no_campaign_output_and_no_multithread_execution(self):
        with patch.dict(os.environ, {"SLURM_JOB_ID": "synthetic"}, clear=True), patch.object(s, "require_compute", return_value=dict(job_id="synthetic")), patch.object(s, "load_fixture") as load:
            with self.assertRaisesRegex(ValueError, "TEST output"):
                s.run_fixture("manifest", "/tmp/campaign/tasks_done/result")
            with self.assertRaisesRegex(RuntimeError, "one numerical thread"):
                s.run_fixture("manifest", "/tmp/TEST/result")
            load.assert_not_called()

    def test_compute_attestation_failure_stops_before_fixture_read(self):
        with patch.object(s, "require_compute", side_effect=RuntimeError("unallocated or unbound compute process")) as gate, patch.object(s, "load_fixture") as load:
            with self.assertRaisesRegex(RuntimeError, "unallocated"):
                s.run_fixture("manifest", "/tmp/TEST/result")
            gate.assert_called_once_with()
            load.assert_not_called()

    def test_success_seals_every_output_and_binds_actual_job(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path = root / "manifest.json"
            manifest_path.write_text("synthetic fixture bytes")
            metadata = root / "metadata.json"
            f.write_json(metadata, dict(context=dict(original_source="original-science")))
            manifest = dict(source=dict(head="original-head"), descriptor=dict(name="complete-original-chunk"), reference=dict(metadata="logical-metadata"))
            resolver = SimpleNamespace(path=lambda logical: metadata)
            allocation = dict(job_id="123", node="compute01", affinity=[4], cpus_per_task=1)
            environment = {**{key: "1" for key in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS", "NUMEXPR_NUM_THREADS")}, "SLURM_JOB_ID": "123"}
            def execute(fixture, paths, output):
                (output / "predictions.npz").write_bytes(b"synthetic-test-output")
                f.write_json(output / "saved_array_validation.json", dict(status="synthetic"))
                f.write_json(output / "extra_diagnostic.json", dict(retained=True))
                return dict(status="PASS_TEST_FORECAST_PARITY", accepted=True)
            output = root / "TEST/parity"
            with patch.dict(os.environ, environment, clear=True), patch.object(s, "require_compute", return_value=allocation), patch.object(s, "load_fixture", return_value=(manifest, resolver)), patch.object(s, "_execute_fixture", side_effect=execute):
                result = s.run_fixture(manifest_path, output)
            seal = f.read_json(output / "completed_evidence.json")
            expected_files = {p.name for p in output.iterdir() if p.name != "completed_evidence.json"}
            self.assertEqual(set(seal["artifacts"]), expected_files)
            self.assertIn("extra_diagnostic.json", seal["artifacts"])
            for name, sha in seal["artifacts"].items():
                self.assertEqual(sha, f.digest(output / name))
            self.assertEqual(result["execution"]["allocation"], allocation)
            self.assertEqual(result["execution"]["slurm_job_id"], "123")
            self.assertEqual(result["execution"]["fixture_manifest_sha256"], f.digest(manifest_path))

    def test_failed_execution_retains_outputs_and_cannot_retry_namespace(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path = root / "manifest.json"
            manifest_path.write_text("synthetic fixture bytes")
            metadata = root / "metadata.json"
            f.write_json(metadata, dict(context=dict(original_source="original-science")))
            manifest = dict(source=dict(head="original-head"), descriptor=dict(name="complete-original-chunk"), reference=dict(metadata="logical-metadata"))
            resolver = SimpleNamespace(path=lambda logical: metadata)
            environment = {**{key: "1" for key in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS", "NUMEXPR_NUM_THREADS")}, "SLURM_JOB_ID": "123"}
            def execute(fixture, paths, output):
                (output / "predictions.npz").write_bytes(b"preserved-failed-test-output")
                raise RuntimeError("synthetic parity mismatch")
            output = root / "TEST/parity"
            with patch.dict(os.environ, environment, clear=True), patch.object(s, "require_compute", return_value=dict(job_id="123")), patch.object(s, "load_fixture", return_value=(manifest, resolver)), patch.object(s, "_execute_fixture", side_effect=execute) as called:
                with self.assertRaisesRegex(RuntimeError, "synthetic parity mismatch"):
                    s.run_fixture(manifest_path, output)
                with self.assertRaises(FileExistsError):
                    s.run_fixture(manifest_path, output)
                called.assert_called_once()
            self.assertEqual((output / "predictions.npz").read_bytes(), b"preserved-failed-test-output")
            self.assertEqual(f.read_json(output / "failure.json")["status"], "FAILED_TEST_NO_RETRY")
            self.assertFalse((output / "completed_evidence.json").exists())

    def test_sampler_identity_strict_and_diagnostic_tolerance_predeclared(self):
        reference = dict(paths=100, covariance_inflation=0.0, relative_reconstruction_error=1e-15,
            seed=123, future_target_access=False)
        s.compare_nested(reference, {**reference, "relative_reconstruction_error": 2e-15})
        for change in (dict(seed=124), dict(paths=99), dict(covariance_inflation=1e-15),
                dict(future_target_access=True), dict(relative_reconstruction_error=0.01)):
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                s.compare_nested(reference, {**reference, **change})


if __name__ == "__main__":
    unittest.main()
