"""Source-grounded vector-figure QA; no inference or runtime evidence reads.

Run with a Python environment containing PyMuPDF, for example:
  /tmp/qdesn-technometrics-pdf-venv/bin/python \
    application/tests/test_joint_qdesn_laplace_article_figures_v2.py
"""
from collections import Counter
import csv
import math
from pathlib import Path
import re
import unittest

import fitz


ROOT = Path(__file__).resolve().parents[2]
PREFIX = "joint_qdesn_pure_desn_v2_"
FIGURES = ROOT / "figures" / "joint_qdesn_simulation"
SCENARIOS = {
    "asymmetric_laplace_tail": "Asymmetric-Laplace tail",
    "gaussian_mixture_bridge": "Gaussian-mixture innovations",
    "laplace_bridge": "Laplace innovations",
    "nonlinear_reservoir_friendly": "Nonlinear reservoir dynamics",
    "normal_bridge": "Gaussian innovations",
    "persistent_heavy_tail": "Persistent heavy tails",
    "regime_shift": "Regime shift",
    "student_t_location_scale": "Student-t location-scale",
}
MODELS = {"joint_qdesn_rhs_mcmc", "qdesn_rhs_independent_mcmc",
          "joint_exqdesn_rhs_mcmc", "exqdesn_rhs_independent_mcmc"}


def read_rows(name):
    with (ROOT / "tables" / (PREFIX + name + ".csv")).open(newline="") as stream:
        return list(csv.DictReader(stream))


def mcmc_rows(name):
    return [row for row in read_rows(name) if row["inference_method"] == "mcmc"]


def text_spans(page):
    return [span for block in page.get_text("dict")["blocks"]
            for line in block.get("lines", []) for span in line["spans"]
            if span["text"].strip()]


class JointFigureV2Tests(unittest.TestCase):
    def setUp(self):
        self.score = mcmc_rows("forecast_score_summary")
        self.fit = mcmc_rows("fit_oracle_diagnostics")

    def test_complete_matching_input_grids(self):
        self.assertEqual(len(read_rows("forecast_score_summary")), 64)
        self.assertEqual(len(self.score), 32)
        self.assertEqual(len(self.fit), 32)
        self.assertEqual({row["scenario_id"] for row in self.score}, set(SCENARIOS))
        self.assertEqual({row["model_id"] for row in self.score}, MODELS)
        self.assertEqual({row["model_cell_id"] for row in self.score},
                         {row["model_cell_id"] for row in self.fit})
        for scenario in SCENARIOS:
            self.assertEqual({row["model_id"] for row in self.score
                              if row["scenario_id"] == scenario}, MODELS)
        for row in self.score:
            values = [float(row[key]) for key in (
                "posterior_score_mean", "posterior_score_q025", "posterior_score_q975")]
            self.assertTrue(all(math.isfinite(value) for value in values))
            self.assertLessEqual(values[1], values[2])
            self.assertEqual(int(row["canonical_contract_crossing_pairs"]), 0)
        for row in self.fit:
            self.assertTrue(math.isfinite(float(row["fit_oracle_rmse"])))
            self.assertGreaterEqual(float(row["fit_oracle_rmse"]), 0)
            self.assertEqual(int(row["fit_contract_crossing_pairs"]), 0)

    def test_one_page_vector_output_and_embedded_fonts(self):
        for suffix in ("forecast_dgp_acrps", "fit_oracle_rmse"):
            with self.subTest(figure=suffix), fitz.open(FIGURES / (PREFIX + suffix + ".pdf")) as doc:
                self.assertEqual(len(doc), 1)
                page = doc[0]
                self.assertEqual(len(page.get_images()), 0)
                self.assertAlmostEqual(page.rect.width, 504, delta=1)
                self.assertAlmostEqual(page.rect.height, 583.2, delta=1)
                self.assertTrue(page.get_drawings())
                fonts = page.get_fonts(full=True)
                self.assertTrue(fonts)
                for font in fonts:
                    self.assertGreater(font[0], 0)
                    descriptor_kind, descriptor = doc.xref_get_key(font[0], "FontDescriptor")
                    self.assertEqual(descriptor_kind, "xref")
                    descriptor_xref = int(descriptor.split()[0])
                    embedded = [doc.xref_get_key(descriptor_xref, key)[0]
                                for key in ("FontFile", "FontFile2", "FontFile3")]
                    self.assertIn("xref", embedded, font[3])

    def test_legible_inserted_typography_without_clipped_or_overlapping_text(self):
        # The 12-point letterpaper manuscript has a 468 TeX-point text width.
        # Convert TeX points to PDF points, then apply the 0.94 insertion width.
        insertion_width_bp = .94 * 468 * 72 / 72.27
        for suffix in ("forecast_dgp_acrps", "fit_oracle_rmse"):
            with self.subTest(figure=suffix), fitz.open(FIGURES / (PREFIX + suffix + ".pdf")) as doc:
                page = doc[0]
                spans = text_spans(page)
                self.assertTrue(spans)
                minimum_inserted_pt = min(span["size"] for span in spans) * insertion_width_bp / page.rect.width
                self.assertGreaterEqual(minimum_inserted_pt, 8.5)
                bounds = fitz.Rect(-.1, -.1, page.rect.width + .1, page.rect.height + .1)
                for span in spans:
                    self.assertTrue(bounds.contains(fitz.Rect(span["bbox"])), span["text"])
                for i, first in enumerate(spans):
                    for second in spans[i + 1:]:
                        overlap = fitz.Rect(first["bbox"]) & fitz.Rect(second["bbox"])
                        overlap_area = max(0, overlap.width) * max(0, overlap.height)
                        self.assertLessEqual(overlap_area, .25,
                            "Overlapping figure text: %r and %r" % (first["text"], second["text"]))

    def test_all_panels_and_model_labels_are_reader_facing(self):
        for suffix in ("forecast_dgp_acrps", "fit_oracle_rmse"):
            with self.subTest(figure=suffix), fitz.open(FIGURES / (PREFIX + suffix + ".pdf")) as doc:
                text = doc[0].get_text()
                for heading in SCENARIOS.values():
                    self.assertIn(heading, text)
                # Facet labels repeat on the four left-hand panels; the four
                # model rows and all 32 crossing annotations remain visible.
                for label in ("Joint AL", "Independent AL", "Joint exAL", "Independent exAL"):
                    self.assertEqual(text.splitlines().count(label), 4)
                self.assertEqual(len(re.findall(r"c\s*=\s*\d+\.\d{2}%", text)), 32)
                for internal in ("canonical-action", "arch_00", "arch_02", "Jerez", "Muscat", "Phase"):
                    self.assertNotIn(internal, text)

    def test_crossing_annotations_match_canonical_grid_denominators(self):
        specifications = (
            ("forecast_dgp_acrps", self.score, "canonical_raw_crossing_pairs", 33 * 30 * 6),
            ("fit_oracle_rmse", self.fit, "fit_raw_crossing_pairs", 500 * 6),
        )
        for suffix, records, column, denominator in specifications:
            with self.subTest(figure=suffix), fitz.open(FIGURES / (PREFIX + suffix + ".pdf")) as doc:
                expected = Counter("%.2f%%" % (100 * int(row[column]) / denominator)
                                   for row in records)
                actual = Counter(re.findall(r"c\s*=\s*(\d+\.\d{2}%)", doc[0].get_text()))
                self.assertEqual(actual, expected)

    def test_metric_and_uncertainty_definitions_in_versioned_wrappers(self):
        forecast = (ROOT / "tables" / (PREFIX + "forecast_figure.tex")).read_text()
        fit = (ROOT / "tables" / (PREFIX + "fit_figure.tex")).read_text()
        self.assertIn("equal-tailed 95\\% intervals", forecast)
        self.assertIn("averaged recursively generated forecast design", forecast)
        self.assertIn("Points show RMSE rather than posterior interval summaries", fit)
        self.assertNotIn("95\\%", fit)
        self.assertNotIn("canonical-action", forecast + fit)
        for text, suffix, label in (
            (forecast, "forecast_dgp_acrps", "forecast-acrps"),
            (fit, "fit_oracle_rmse", "fit-rmse"),
        ):
            self.assertIn(PREFIX + suffix + ".pdf", text)
            self.assertIn("fig:joint-qdesn-pure-desn-v2-" + label, text)
            self.assertNotIn("_v1_", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
