"""Bounded GloFAS MQ label-overlay checks; no scientific fitting or scoring."""
from __future__ import annotations

import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

try:
    import fitz
except ImportError:
    fitz = None

ROOT = Path(__file__).resolve().parents[2]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


@unittest.skipIf(fitz is None, "GloFAS vector overlay checks require the pinned PyMuPDF proof environment")
class GlofasMqPresentationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = ROOT / "scripts/build_glofas_mq_review_figures.py"
        spec = importlib.util.spec_from_file_location("glofas_mq_overlay", path)
        cls.builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.builder)
        cls.manifest = json.loads((ROOT / cls.builder.MANIFEST).read_text())
        cls.rows = cls.builder.registry_rows(ROOT / cls.builder.REGISTRY)

    def test_display_registry_keeps_model_and_likelihood(self):
        self.assertEqual(self.rows["Joint AL"]["display_text"], "MQ-DESN (AL)")
        self.assertEqual(self.rows["Joint exAL"]["display_text"], "MQ-DESN (exAL)")
        self.assertEqual(self.rows["Independent AL"]["display_tex"], "Q--DESN (AL)")
        self.assertEqual(self.rows["Independent exAL"]["fit_structure"], "independent")

    def test_registry_rejects_unknown_duplicate_or_wrong_assignments(self):
        original = list(self.rows.values())
        cases = [original + [dict(original[0])]]
        for field, value in (("source_key", "Unknown AL"),
                             ("model_family", "Q-DESN"),
                             ("likelihood_family", "exAL"),
                             ("display_tex", "exMQ--DESN")):
            changed = [dict(row) for row in original]
            changed[0][field] = value
            cases.append(changed)
        with tempfile.TemporaryDirectory(prefix="qdesn-glofas-mq-registry-") as temporary:
            for i, rows in enumerate(cases):
                path = Path(temporary) / f"invalid-{i}.csv"
                with path.open("w", newline="") as stream:
                    writer = csv.DictWriter(stream, fieldnames=original[0].keys())
                    writer.writeheader()
                    writer.writerows(rows)
                with self.assertRaises(AssertionError):
                    self.builder.registry_rows(path)

    def test_originals_and_unrelated_common_window_are_preserved(self):
        self.assertGreater(len(self.manifest["protected_sources"]), 30)
        for record in self.manifest["protected_sources"]:
            self.assertEqual(sha(ROOT / record["file"]), record["sha256"], record["file"])
        self.assertEqual(sha(ROOT / self.manifest["registry"]), self.manifest["registry_sha256"])
        self.assertEqual(sha(ROOT / self.manifest["generator"]), self.manifest["generator_sha256"])
        self.assertEqual(sha(ROOT / self.manifest["frozen_renderer"]), self.manifest["frozen_renderer_sha256"])
        self.assertEqual(self.manifest["scientific_computation"],
                         dict(new_model_runs=0, scores_recomputed=0, runtime_payloads_read=0))

    def test_six_vector_figures_have_exact_label_mapping_and_unchanged_marks(self):
        self.assertEqual(len(self.manifest["assets"]), 6)
        for asset in self.manifest["assets"]:
            self.assertEqual(sha(ROOT / asset["output"]), asset["output_sha256"])
            self.assertEqual(asset["output_vector_path_hash"], asset["historical_review_vector_path_hash"])
            self.assertTrue(asset["exact_mapped_text_tokens_retained"])
            self.assertTrue(asset["numeric_token_multiset_unchanged"])
            self.assertGreaterEqual(asset["minimum_native_label_bp"], 9 - 1e-4)
            self.assertGreaterEqual(asset["minimum_effective_label_bp"], 8)
            with fitz.open(ROOT / asset["output"]) as pdf:
                self.assertEqual(len(pdf), 1)
                self.assertFalse(pdf[0].get_images())
                text = pdf[0].get_text()
                self.assertIn("MQ-DESN (AL)", text)
                self.assertIn("MQ-DESN (exAL)", text)
                self.assertNotIn("Joint AL", text)
                self.assertNotIn("Joint exAL", text)
                if asset["role"] != "convergence":
                    self.assertIn("Q-DESN (AL)", text)
                    self.assertIn("Q-DESN (exAL)", text)
                if asset["role"] == "part3":
                    self.assertIn("Part 3: joint historical USGS forecast", text)

    def test_table_rows_and_all_non_label_bytes_are_preserved(self):
        self.assertEqual(len(self.manifest["table_assets"]), 6)
        for asset in self.manifest["table_assets"]:
            source = (ROOT / asset["source"]).read_text()
            derivative = (ROOT / asset["output"]).read_text()
            self.assertEqual(self.builder.restore_tex_labels(derivative, self.rows), source)
            self.assertEqual(asset["source_row_count"], self.builder.TABLE_ROW_COUNTS[asset["role"]])
            self.assertEqual(sha(ROOT / asset["source"]), asset["source_sha256"])
            self.assertEqual(sha(ROOT / asset["output"]), asset["output_sha256"])
            self.assertTrue(asset["numeric_cells_unchanged"])

    def test_overrides_do_not_change_main_forecast_or_numeric_macros(self):
        path = ROOT / self.manifest["overrides"]["file"]
        self.assertEqual(sha(path), self.manifest["overrides"]["sha256"])
        text = path.read_text()
        self.assertNotIn("GlofasApplicationCurrentForecastWindowFigure", text)
        self.assertNotIn("CurrentJointAlAcrps", text)
        self.assertNotIn("CurrentJointExalAcrps", text)
        self.assertEqual(text, self.builder.override_text(ROOT, self.rows))
        self.assertIn("glofas_search3_mq_main_scores.tex", text)
        self.assertIn("GlofasApplicationCurrentFullComparisonFigure", text)

    def test_complete_overlay_reproduces_without_repository_writes(self):
        completed = subprocess.run([sys.executable, str(ROOT / self.manifest["generator"]), "--check"],
                                   cwd=ROOT, check=True, capture_output=True, text=True)
        self.assertIn("GLOFAS_MQ_PRESENTATION_CHECK=PASS", completed.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
