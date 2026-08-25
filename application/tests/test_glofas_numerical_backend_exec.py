import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "application/scripts/glofas_numerical_backend_exec.py"
SPEC = importlib.util.spec_from_file_location("glofas_backend_exec", SCRIPT)
backend_exec = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backend_exec)


class GlofasNumericalBackendExecTests(unittest.TestCase):
    def test_cpu_set_normalization(self):
        self.assertEqual(backend_exec.normalize_cpu_set("0,2-4"), [0, 2, 3, 4])
        with self.assertRaisesRegex(ValueError, "distinct"):
            backend_exec.normalize_cpu_set("1,1")

    def test_bundled_backend_pins_all_thread_controls(self):
        env, manifest = backend_exec.prepare_backend(
            "bundled_rblas", 1, base_env={"PATH": os.environ.get("PATH", "")}
        )
        self.assertEqual(manifest["backend"], "bundled_rblas")
        self.assertTrue(all(env[name] == "1" for name in backend_exec.THREAD_ENV))
        self.assertNotIn("QDESN_BLAS_LIBRARY_PATH", env)

    def test_openblas_backend_fails_closed_on_hash_drift(self):
        with tempfile.TemporaryDirectory() as tmp:
            library = Path(tmp) / "libopenblas.so"
            library.write_bytes(b"test library")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                backend_exec.prepare_backend(
                    "openblas_serial", 1, str(library), "0" * 64,
                    base_env={"PATH": os.environ.get("PATH", "")},
                )

    def test_openblas_backend_records_resolved_hash(self):
        with tempfile.TemporaryDirectory() as tmp:
            library = Path(tmp) / "libopenblas.so"
            library.write_bytes(b"test library")
            digest = hashlib.sha256(library.read_bytes()).hexdigest()
            env, manifest = backend_exec.prepare_backend(
                "openblas_serial", 2, str(library), digest,
                base_env={"PATH": os.environ.get("PATH", "")},
            )
            self.assertEqual(manifest["library_sha256"], digest)
            self.assertEqual(env["OPENBLAS_NUM_THREADS"], "2")
            self.assertEqual(env["LD_PRELOAD"], str(library.resolve()))

    def test_wrapper_writes_terminal_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "execution.json"
            code = backend_exec.main([
                "--backend", "bundled_rblas",
                "--threads", "1",
                "--manifest", str(manifest),
                "--", "/bin/true",
            ])
            self.assertEqual(code, 0)
            payload = json.loads(manifest.read_text(encoding="utf-8"))
            self.assertEqual(payload["status"], "completed")
            self.assertEqual(payload["return_code"], 0)
            self.assertEqual(payload["schema_version"], "glofas_numerical_backend_execution_v1")


if __name__ == "__main__":
    unittest.main()
