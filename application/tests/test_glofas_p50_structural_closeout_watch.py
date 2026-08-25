import importlib.util
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def load_script_module(name, relative_path):
    path = REPO_ROOT / relative_path
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


watch = load_script_module(
    "glofas_p50_structural_closeout_watch",
    "application/scripts/glofas_p50_structural_closeout_watch.py",
)


class GlofasP50StructuralCloseoutWatchTests(unittest.TestCase):
    def test_gate_decision_is_fail_closed(self):
        self.assertEqual(
            watch.closeout_action({"cold_confirmation_warranted": "TRUE"}),
            "await_cold_confirmation_without_cleanup",
        )
        self.assertEqual(
            watch.closeout_action({"full7_warranted": "true"}),
            "await_full7_decision_without_cleanup",
        )
        self.assertEqual(
            watch.closeout_action({"article_update_warranted": "yes"}),
            "await_article_integration_without_cleanup",
        )
        self.assertEqual(
            watch.closeout_action({}),
            "strict_closeout_and_cleanup_nonprotected",
        )

    def test_output_root_must_be_task_owned_and_materialized(self):
        with tempfile.TemporaryDirectory(dir=str(REPO_ROOT / "local_trackers")) as tmp:
            root = Path(tmp)
            with self.assertRaisesRegex(ValueError, "outside the task-owned runtime tree"):
                watch.require_owned_output_root(root, REPO_ROOT)

        owned_parent = REPO_ROOT / "local_trackers" / "runtime_configs"
        owned_parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=str(owned_parent)) as tmp:
            root = Path(tmp)
            with self.assertRaisesRegex(ValueError, "lacks required campaign evidence"):
                watch.require_owned_output_root(root, REPO_ROOT)
            (root / "runtime_manifest.csv").write_text("candidate_id\n", encoding="utf-8")
            (root / "screening_space_snapshot.yaml").write_text("screen: test\n", encoding="utf-8")
            self.assertEqual(watch.require_owned_output_root(root, REPO_ROOT), root.resolve())


if __name__ == "__main__":
    unittest.main()
