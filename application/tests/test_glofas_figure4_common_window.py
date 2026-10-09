"""Presentation-only checks for the common-window GloFAS Figure 4."""
import csv
import datetime as dt
import hashlib
import json
import math
from statistics import NormalDist
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "tables/glofas_figure4_common_window_manifest.json"
FAMILIES = {"Independent AL", "Normal Ridge"}
LEVELS = {0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95}


def rows(path):
    with (ROOT / path).open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def date_range(start, end):
    first, last = dt.date.fromisoformat(start), dt.date.fromisoformat(end)
    return {(first + dt.timedelta(days=i)).isoformat() for i in range((last - first).days + 1)}


class CommonWindowFigureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))

    def test_source_and_output_hashes(self):
        m = self.manifest
        self.assertEqual(m["schema"], "glofas-figure4-common-window-v1")
        self.assertEqual(sha(m["source_script"]), m["script_sha256"])
        for path, expected in m["sources"].items():
            self.assertEqual(sha(path), expected, path)
        for output in m["outputs"]:
            self.assertEqual(sha(output["file"]), output["sha256"], output["file"])
        # The entire authenticated scientific source remains byte-identical.
        self.assertEqual(sha("tables/glofas_search3_part1234_final_20261007_source_quantiles.csv"),
                         "d4a6c18eac599c66e9e95edda01e98d9f14c8f6a8efc6dd2a54f16544ae7181a")

    def test_historical_presentation_bundle_is_unchanged(self):
        historical = json.loads((ROOT / "tables/qdesn_pro_review_presentation_manifest.json").read_text())
        self.assertEqual(sha(historical["source_script"]), historical["script_sha256"])
        self.assertEqual(sha("scripts/qdesn_evaluation_figure_style.R"), historical["shared_style_sha256"])
        self.assertEqual(len(historical["outputs"]), 13)
        for output in historical["outputs"]:
            self.assertEqual(sha(output["file"]), output["sha256"], output["file"])
        for path, expected in historical["sources"].items():
            self.assertEqual(sha(path), expected, path)

    def test_complete_fitted_and_forecast_grids(self):
        fitted = rows("tables/glofas_search3_part4_history_fitted_quantiles.csv")
        forecast = [r for r in rows("tables/glofas_search3_part1234_final_20261007_source_quantiles.csv")
                    if r["part"] == "Part 4" and r["family"] in FAMILIES]
        self.assertEqual(len(fitted), 420)
        self.assertEqual(len(forecast), 392)
        for block, dates in ((fitted, date_range("2022-11-26", "2022-12-25")),
                             (forecast, date_range("2022-12-26", "2023-01-22"))):
            actual = [(r["family"], r["target_date"], float(r["quantile_level"])) for r in block]
            expected = {(f, d, q) for f in FAMILIES for d in dates for q in LEVELS}
            self.assertEqual(set(actual), expected)
            self.assertEqual(len(actual), len(expected))
            self.assertTrue(all(math.isfinite(float(r["qhat"])) for r in block))

    def test_shared_limits_ticks_and_physical_alignment(self):
        m = self.manifest
        self.assertEqual(m["common_x_limits"], ["2022-11-26", "2023-01-22"])
        self.assertEqual(m["history_dates"], ["2022-11-26", "2022-12-25"])
        self.assertEqual(m["forecast_dates"], ["2022-12-26", "2023-01-22"])
        self.assertEqual(m["origin_date"], "2022-12-25")
        self.assertEqual(m["common_x_tick_dates"],
                         ["2022-11-26", "2022-12-10", "2022-12-25", "2023-01-08", "2023-01-22"])
        self.assertEqual(m["historical_usgs_repeated_panels"], 3)
        self.assertEqual(m["heldout_usgs_repeated_panels"], 3)
        self.assertEqual(m["total_model_quantile_rows"], 812)
        positions = m["plot_panel_geometry"]
        self.assertEqual(len(positions), 3)
        for key in ("x_left_mm", "x_right_mm"):
            self.assertLess(max(p[key] for p in positions) - min(p[key] for p in positions), 1e-8)
        self.assertTrue(all(p["x_right_mm"] > p["x_left_mm"] for p in positions))
        values = []
        for path, fields in (("tables/glofas_search3_review_history_plot_inputs.csv", ("y_transformed", "g_transformed")),
                             ("tables/glofas_search3_review_ensemble_plot_inputs.csv", ("g_transformed",)),
                             ("tables/glofas_search3_review_truth_plot_inputs.csv", ("y_transformed",)),
                             ("tables/glofas_search3_part4_history_fitted_quantiles.csv", ("qhat",))):
            values.extend(float(r[key]) for r in rows(path) for key in fields)
        values.extend(float(r["qhat"]) for r in rows("tables/glofas_search3_part1234_final_20261007_source_quantiles.csv")
                      if r["part"] == "Part 4" and r["family"] in FAMILIES)
        self.assertLessEqual(m["common_y_limits"][0], min(values))
        self.assertGreaterEqual(m["common_y_limits"][1], max(values))

    def test_provenance_and_no_inference_operations(self):
        m = self.manifest
        for key in ("credible_ribbons", "smoothing", "quantile_projection", "rescoring", "fitting"):
            self.assertIs(m[key], False)
        self.assertEqual(m["quantile_linewidth_mm"], .17)
        self.assertEqual(m["median_linewidth_mm"], .35)
        self.assertGreaterEqual(m["effective_ordinary_label_pt_at_6p5in_textwidth"], 9)
        provenance = json.loads((ROOT / "tables/glofas_search3_part4_history_fitted_quantile_provenance.json").read_text())
        self.assertTrue(provenance)
        text = json.dumps(provenance)
        self.assertNotIn("/data/", text)
        self.assertNotIn("local_trackers", text)
        self.assertNotIn("/tmp/", text)
        self.assertNotIn("/data/", json.dumps(m))

    def test_historical_summary_formula_and_frozen_fit_provenance(self):
        path = "tables/glofas_search3_part4_history_fitted_quantile_provenance.json"
        p = json.loads((ROOT / path).read_text())
        self.assertEqual(p["schema"], "glofas-part4-historical-conditional-quantile-extract-v1")
        self.assertEqual(p["historical_rows"], 420)
        self.assertEqual(p["origin_date"], "2022-12-25")
        self.assertEqual(p["historical_dates"], ["2022-11-26", "2022-12-25"])
        self.assertEqual(set(p["families"]), FAMILIES)
        self.assertEqual(set(p["quantile_grid"]), LEVELS)
        output = p["outputs"]["historical_quantiles"]
        self.assertEqual(output["file"], "glofas_search3_part4_history_fitted_quantiles.csv")
        self.assertEqual(sha("tables/" + output["file"]), output["sha256"])
        self.assertEqual(sha("scripts/extract_glofas_part4_historical_quantiles.R"), p["extraction_script_sha256"])
        self.assertEqual(p["source_authority"]["truth_free_design"]["sha256"],
                         "a2fbcec6523802f01c98ec272253e58a598a5adc5c7b0f9063b615b36c07bcf9")
        self.assertEqual(len(p["source_authority"]["model_fits"]), 8)
        self.assertEqual(p["crossing_correction"], "None; raw fitted quantiles retained")
        shape, rate = p["normal_residual_variance_shape"], p["normal_residual_variance_rate"]
        expected_sd = math.exp(.5 * math.log(rate) + math.lgamma(shape - .5) - math.lgamma(shape))
        self.assertAlmostEqual(expected_sd, p["normal_expected_residual_sd"], places=8)
        for r in rows("tables/glofas_search3_part4_history_fitted_quantiles.csv"):
            self.assertEqual(r["part"], "Part 4")
            self.assertEqual(r["period"], "historical_fit")
            self.assertEqual(r["summary_role"], "posterior_mean_conditional_response_quantile")
            location, quantile = float(r["location_mean"]), float(r["qhat"])
            if r["family"] == "Independent AL":
                self.assertEqual(location, quantile)
            else:
                self.assertAlmostEqual(float(r["expected_residual_sd"]), expected_sd, places=8)
                expected = location + NormalDist().inv_cdf(float(r["quantile_level"])) * expected_sd
                self.assertAlmostEqual(expected, quantile, places=8)

    def test_reader_wiring(self):
        alias = (ROOT / "tables/glofas_figure4_common_window_outputs.tex").read_text()
        main = (ROOT / "main.tex").read_text()
        self.assertIn(r"\renewcommand{\GlofasApplicationCurrentForecastWindowFigure}", alias)
        self.assertIn("glofas_search3_part4_common_window_three_panel_review.pdf", alias)
        self.assertEqual(main.count(r"\input{tables/glofas_figure4_common_window_outputs.tex}"), 1)
        self.assertIn(r"\includegraphics[width=0.94\textwidth]{\GlofasApplicationCurrentForecastWindowFigure}", main)

    def test_vector_pdf_and_readable_fonts(self):
        try:
            import fitz
        except ImportError:
            self.skipTest("PyMuPDF is optional; vector/font check recorded separately when available")
        path = ROOT / "figures/glofas_application/glofas_search3_part4_common_window_three_panel_review.pdf"
        with fitz.open(path) as pdf:
            self.assertEqual(len(pdf), 1)
            page = pdf[0]
            self.assertEqual(page.get_images(), [])
            self.assertAlmostEqual(page.rect.width, 6.5 * 72, places=4)
            self.assertAlmostEqual(page.rect.height, 6.625 * 72, places=4)
            spans = [s for b in page.get_text("dict")["blocks"] if "lines" in b
                     for line in b["lines"] for s in line["spans"] if s["text"].strip()]
            self.assertTrue(spans)
            self.assertGreaterEqual(min(s["size"] for s in spans), 9.7)
            text = page.get_text()
            for heading in ("(a) Data and issued ensemble", "(b) Independent AL", "(c) Normal Ridge"):
                self.assertIn(heading, text)
            self.assertEqual(text.count("Fitted quantiles before cutoff; forecasts after cutoff"), 2)
            for span in spans:
                x0, y0, x1, y1 = span["bbox"]
                self.assertGreaterEqual(x0, -0.1)
                self.assertGreaterEqual(y0, -0.1)
                self.assertLessEqual(x1, page.rect.width + 0.1)
                self.assertLessEqual(y1, page.rect.height + 0.1)


if __name__ == "__main__":
    unittest.main()
