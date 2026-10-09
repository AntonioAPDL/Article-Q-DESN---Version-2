"""Bounded presentation checks; no inference, rescoring, or runtime reads."""
import csv
import hashlib
import json
from pathlib import Path
import re
import unittest

try:
    import fitz
except ImportError:
    fitz = None

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows(path):
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


class PresentationTests(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads((ROOT / "tables/qdesn_pro_review_presentation_manifest.json").read_text())

    def test_sources_and_generated_assets(self):
        for filename, expected in self.manifest["sources"].items():
            self.assertEqual(sha(ROOT / filename), expected, filename)
        self.assertEqual(sha(ROOT / self.manifest["source_script"]), self.manifest["script_sha256"])
        self.assertEqual(len(self.manifest["outputs"]), 13)
        for output in self.manifest["outputs"]:
            self.assertEqual(sha(ROOT / output["file"]), output["sha256"], output["file"])

    def test_authentic_compact_inputs_and_dates(self):
        provenance = json.loads((ROOT / "tables/glofas_search3_review_plot_input_provenance.json").read_text())
        self.assertEqual(provenance["source_authority"]["truth_free_design"]["sha256"],
                         "a2fbcec6523802f01c98ec272253e58a598a5adc5c7b0f9063b615b36c07bcf9")
        self.assertEqual(provenance["source_authority"]["scoring_only_truth_sidecar"]["sha256"],
                         "24be9fa631bca346a04a7a855bff5ef3ebc7bf5c748fbade7a213d88fdfe63e6")
        self.assertEqual(provenance["extraction_script_sha256"], sha(ROOT / "scripts/extract_glofas_pro_review_plot_inputs.R"))
        for output in provenance["outputs"].values():
            self.assertEqual(sha(ROOT / "tables" / output["file"]), output["sha256"])
        ensemble = rows(ROOT / "tables/glofas_search3_review_ensemble_plot_inputs.csv")
        history = rows(ROOT / "tables/glofas_search3_review_history_plot_inputs.csv")
        truth = rows(ROOT / "tables/glofas_search3_review_truth_plot_inputs.csv")
        self.assertEqual((len(history), len(ensemble), len(truth)), (30, 1428, 28))
        self.assertEqual(len({r["member"] for r in ensemble}), 51)
        self.assertEqual(len({(r["member"], r["target_date"]) for r in ensemble}), 1428)
        self.assertEqual({r["origin_date"] for r in ensemble}, {"2022-12-25"})
        self.assertEqual((history[0]["target_date"], history[-1]["target_date"]), ("2022-11-26", "2022-12-25"))
        public = rows(ROOT / "tables/glofas_search3_part1234_final_20261007_source_quantiles.csv")
        raw = {r["target_date"]: float(r["y_reference"]) for r in public
               if r["part"] == "Part 4" and r["family"] == "Raw GloFAS" and float(r["quantile_level"]) == .5}
        self.assertTrue(all(abs(float(r["y_transformed"]) - raw[r["target_date"]]) < 1e-12 for r in truth))
        self.assertNotIn("/data/", json.dumps(provenance))

    def test_score_table_preserves_seven_rows(self):
        original = (ROOT / "tables/glofas_search3_part1234_final_20261007_part4_scores.tex").read_text()
        derivative = (ROOT / "tables/glofas_search3_part4_main_scores_review.tex").read_text()
        old_rows = [line.split(" & ")[:5] for line in original.splitlines() if " & " in line][1:]
        new_rows = [line.removesuffix(" \\\\").split(" & ") for line in derivative.splitlines() if " & " in line][1:]
        self.assertEqual(old_rows, new_rows)
        self.assertEqual(len(new_rows), 7)
        self.assertIn("-3.00\\%", derivative)
        self.assertNotIn("Numerical status", derivative)
        self.assertNotIn("resizebox", derivative)

    @unittest.skipIf(fitz is None, "PDF typography QA requires PyMuPDF; source/input checks still run")
    def test_pdf_labels_vectors_and_glofas_panels(self):
        for output in self.manifest["outputs"]:
            filename = output["file"]
            if not filename.endswith(".pdf"):
                continue
            with fitz.open(ROOT / filename) as doc:
                self.assertEqual(len(doc), 1)
                page = doc[0]
                self.assertEqual(len(page.get_images()), 0)
                spans = [s for b in page.get_text("dict")["blocks"] for line in b.get("lines", []) for s in line["spans"]]
                self.assertTrue(spans)
                # All ordinary labels are native text, not enlarged page bitmaps.
                insertion = .98 if "independent_simulation" in filename else .94
                final_width_bp = insertion * 468 * 72 / 72.27
                minimum = min(s["size"] for s in spans) * final_width_bp / page.rect.width
                self.assertGreaterEqual(minimum, 8.5, filename)
                bounds = fitz.Rect(-.1, -.1, page.rect.width + .1, page.rect.height + .1)
                self.assertTrue(all(bounds.contains(fitz.Rect(s["bbox"])) for s in spans), filename)
                self.assertNotIn("canonical-action", page.get_text())
                if "glofas_application" in filename:
                    text = page.get_text()
                    for heading in ("(a) Data and issued ensemble", "(b) Independent AL", "(c) Normal Ridge"):
                        self.assertIn(heading, text)
                    self.assertEqual(text.count("log(1 + flow)"), 3)
                    self.assertNotIn("credible", text)

    def test_active_aliases(self):
        overrides = (ROOT / "tables/glofas_review_figure_overrides.tex").read_text()
        self.assertIn("glofas_search3_part4_three_panel_review.pdf", overrides)
        self.assertIn("GlofasApplicationCurrentFullComparisonFigure", overrides)
        self.assertIn("glofas_search3_part4_main_scores_review.tex", overrides)
        for filename in ("tables/qdesn_pro_review_mcmc_forecast_figures.tex",
                         "tables/qdesn_pro_review_mcmc_fit_figure.tex",
                         "tables/qdesn_pro_review_vb_fit_figure.tex",
                         "tables/joint_qdesn_pro_review_forecast_figure.tex",
                         "tables/joint_qdesn_pro_review_fit_figure.tex"):
            text = (ROOT / filename).read_text()
            self.assertIn("pro_review", text)
            for asset in re.findall(r"\\includegraphics\[[^]]*\]\{([^}]+)\}", text):
                self.assertTrue((ROOT / asset).is_file(), asset)


if __name__ == "__main__":
    unittest.main(verbosity=2)
