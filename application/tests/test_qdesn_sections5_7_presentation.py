"""Bounded positive and adversarial editorial-display contracts.

Fixtures copy authenticated sources and compact display assets only. No fitting,
forecasting, scoring, cache, private evidence, or publication is invoked.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("sections5_7_checker", ROOT / "scripts/check_qdesn_sections5_7_presentation.py")
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class EditorialPresentationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="qdesn-editorial-mutation-")
        self.fixture = Path(self.temporary.name)
        files = CHECKER.dependency_paths(ROOT) | {
            "tables/glofas_mq_display_overrides.tex", "tables/pricefm_full_current_outputs.tex",
            "tables/glofas_application_current_outputs.tex", "tables/glofas_review_figure_overrides.tex",
            "tables/glofas_figure4_common_window_outputs.tex",
        }
        for relative in files:
            source = ROOT / relative
            if source.exists():
                target = self.fixture / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
        self.builder = CHECKER.load_builder(self.fixture)

    def tearDown(self):
        self.temporary.cleanup()

    def alter(self, path, old, new, *, update_hash=False):
        target = self.fixture / path
        value = target.read_text()
        self.assertIn(old, value)
        target.write_text(value.replace(old, new, 1))
        if update_hash:
            manifest_path = self.fixture / self.builder.MANIFEST
            manifest = json.loads(manifest_path.read_text())
            for entry in manifest["outputs"]:
                if entry["file"] == path:
                    entry["sha256"] = hashlib.sha256(target.read_bytes()).hexdigest()
            manifest_path.write_text(json.dumps(manifest))

    def reject(self, *, effective=False):
        with self.assertRaises((AssertionError, FileNotFoundError)):
            CHECKER.check(self.fixture, effective=effective)

    def test_authentic_assets(self):
        receipt = CHECKER.check(ROOT, effective=False)
        self.assertEqual(receipt["outputs"], 20)
        self.assertEqual(receipt["pdf_outputs"], 7)
        self.assertEqual(receipt["table_outputs"], 6)
        self.assertEqual(receipt["caption_wrappers"], 5)
        self.assertEqual(receipt["scientific_runs"], 0)

    def test_current_document_selections(self):
        self.assertEqual(CHECKER.check(ROOT)["status"], "PASS")

    def test_isolated_current_document_selections(self):
        self.assertEqual(CHECKER.check(self.fixture)["status"], "PASS")

    def test_current_ind_forecast_mutation_rejected(self):
        path = "figures/independent_simulation/independent_train500_eval300_mcmc_forecast_mae_v1.pdf"
        target = self.fixture / path
        target.write_bytes(target.read_bytes() + b"\n% mutation\n")
        self.reject(effective=True)

    def test_current_ind_policy_cannot_disappear(self):
        (self.fixture / "application/config/independent_forecast_300_500_v1.json").unlink()
        self.reject(effective=True)

    def test_score_mutation_rejected_even_with_rehashed_receipt(self):
        self.alter(self.builder.TABLE_OUTPUTS["glofas_main"][1], "0.7156", "0.7000", update_hash=True)
        self.reject()

    def test_al_exal_model_swap_rejected(self):
        self.alter(self.builder.TABLE_OUTPUTS["glofas_main"][1], "Q--DESN (AL)", "Q--DESN (exAL)", update_hash=True)
        self.reject()

    def test_independent_mq_relabeling_rejected(self):
        self.alter(self.builder.TABLE_OUTPUTS["glofas_main"][1], "Q--DESN (AL)", "MQ--DESN (AL)", update_hash=True)
        self.reject()

    def test_seventh_family_deletion_rejected(self):
        self.alter(self.builder.TABLE_OUTPUTS["glofas_main"][1], "Normal RHS/VB & 0.8038 & 1.4790 & 0.107", "", update_hash=True)
        self.reject()

    def test_unscored_discrepancy_cannot_be_zero(self):
        self.alter(self.builder.TABLE_OUTPUTS["glofas_components"][1], "Discrepancy & Normal Ridge & ---", "Discrepancy & Normal Ridge & 0.0000", update_hash=True)
        self.reject()

    def test_component_crossing_mutation_rejected(self):
        self.alter(self.builder.TABLE_OUTPUTS["glofas_components"][1], "0.5028 & 0.600 & 3", "0.5028 & 0.600 & 0", update_hash=True)
        self.reject()

    def test_prior_value_mutation_rejected(self):
        self.alter(self.builder.TABLE_OUTPUTS["glofas_component_priors"][1], "5.2043087e-05", "0.0001", update_hash=True)
        self.reject()

    def test_origin_horizon_count_cannot_change(self):
        self.alter(self.builder.TABLE_OUTPUTS["mq_design"][1], "990 origin--horizon pairs", "960 origin--horizon pairs", update_hash=True)
        self.reject()

    def test_candidate_identifier_cannot_return(self):
        self.alter(self.builder.TABLE_OUTPUTS["glofas_specifications"][1], "reference & 1", "reference search3_ref_001 & 1", update_hash=True)
        self.reject()

    def test_pricefm_historical_current_swap_rejected(self):
        self.alter(self.builder.TABLE_OUTPUTS["pricefm_global"][1], "7.217007", "6.823677", update_hash=True)
        self.reject()

    def test_original_source_change_rejected(self):
        self.alter(self.builder.TABLE_OUTPUTS["glofas_main"][0], "0.7156", "0.7000")
        self.reject()

    def test_missing_pdf_receipt_rejected(self):
        path = self.fixture / self.builder.MANIFEST
        value = json.loads(path.read_text())
        value["outputs"] = [entry for entry in value["outputs"] if entry["role"] != "glofas_discrepancy"]
        path.write_text(json.dumps(value))
        self.reject()

    def test_pdf_stale_digest_rejected(self):
        target = self.fixture / self.builder.PDF_OUTPUTS["glofas_reference"][1]
        target.write_bytes(target.read_bytes() + b"\n% mutation\n")
        self.reject()

    def test_graphics_path_change_in_caption_rejected(self):
        role = "mq_forecast"
        self.alter(self.builder.WRAPPER_OUTPUTS[role][1], "forecast_dgp_acrps.pdf", "fit_oracle_rmse.pdf", update_hash=True)
        self.reject()

    def test_score_interval_scope_cannot_be_rewritten(self):
        self.alter(self.builder.WRAPPER_OUTPUTS["mq_forecast"][1], "conditional on each model's averaged recursive future features", "measuring variation across forecast origins", update_hash=True)
        self.reject()

    def test_main_stale_alias_rejected(self):
        main = self.fixture / "main.tex"
        main.write_text(main.read_text() + "\n\\input{tables/glofas_mq_display_overrides.tex}\n")
        self.reject(effective=True)

    def test_supp_stale_pricefm_alias_rejected(self):
        supp = self.fixture / "qdesn-supplement.tex"
        supp.write_text(supp.read_text() + "\n\\input{tables/pricefm_full_current_outputs.tex}\n")
        self.reject(effective=True)

    def test_missing_upload_asset_rejected(self):
        self.alter("overleaf/article_files.txt", self.builder.PDF_OUTPUTS["pricefm_region"][1], "")
        self.reject(effective=True)


if __name__ == "__main__":
    unittest.main()
