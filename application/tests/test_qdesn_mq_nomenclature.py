"""Isolated, fail-closed mutation tests for presentation-only MQ nomenclature."""
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("mq_checker", ROOT / "scripts/check_qdesn_mq_nomenclature.py")
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class MQNomenclatureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Require the real baseline to pass before constructing negative fixtures.
        CHECKER.check(ROOT)
        cls.fixture_temp = tempfile.TemporaryDirectory(prefix="qdesn-mq-fixture-")
        cls.fixture = Path(cls.fixture_temp.name)
        cls.dependencies = CHECKER.dependency_paths(ROOT)
        for relative in cls.dependencies:
            target = cls.fixture / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)

    @classmethod
    def tearDownClass(cls):
        cls.fixture_temp.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="qdesn-mq-mutation-")
        self.root = Path(self.temp.name)
        shutil.copytree(self.fixture, self.root, dirs_exist_ok=True)

    def tearDown(self):
        self.temp.cleanup()

    def refresh_ind_manuscript_receipt(self, relative):
        # Intentional non-IND manuscript mutations must reach their semantic
        # guards rather than fail early on the whole-manuscript IND receipt.
        receipt_path = self.root / "tables/independent_forecast_300_500_article_manifest_v1.json"
        if receipt_path.exists():
            receipt = json.loads(receipt_path.read_text())
            self.assertIn(relative, receipt["sources"])
            receipt["sources"][relative] = hashlib.sha256((self.root / relative).read_bytes()).hexdigest()
            receipt_path.write_text(json.dumps(receipt))

    def mutate_registry(self, mutate):
        path = self.root / CHECKER.REGISTRY
        with path.open(newline="", encoding="utf-8") as stream:
            rows = list(csv.DictReader(stream))
        mutate(rows)
        with path.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=CHECKER.REGISTRY_FIELDS, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        # Even coordinated receipt updates cannot bless a semantic label swap.
        fingerprint = hashlib.sha256(path.read_bytes()).hexdigest()
        for relative in (CHECKER.JOINT_MANIFEST, CHECKER.GLOFAS_MANIFEST):
            receipt = json.loads((self.root / relative).read_text())
            receipt["registry_sha256"] = fingerprint
            (self.root / relative).write_text(json.dumps(receipt))

    def test_complete_isolated_dependency_closure_passes(self):
        self.assertEqual(CHECKER.check(self.root)["selected_mq_pdfs"], 8)

    def test_all_active_mq_caption_derivatives_preserve_table_rows(self):
        builder = CHECKER.editorial_checker(self.root).load_builder(self.root)
        for source, output in CHECKER.EDITORIAL_JOINT_TABLES.items():
            self.assertEqual(builder.table_rows(CHECKER.read(self.root, source)),
                             builder.table_rows(CHECKER.read(self.root, output)))

    def test_superseded_mq_table_cannot_replace_caption_derivative(self):
        source, output = next(iter(CHECKER.EDITORIAL_JOINT_TABLES.items()))
        path = self.root / "qdesn-supplement.tex"
        text = path.read_text()
        self.assertIn(output, text)
        path.write_text(text.replace(output, source, 1))
        self.refresh_ind_manuscript_receipt("qdesn-supplement.tex")
        with self.assertRaisesRegex(CHECKER.CheckError, "omits an authenticated|superseded"):
            CHECKER.check(self.root)

    def test_current_mq_table_numeric_edit_fails_with_rehashed_editorial_receipt(self):
        relative = "tables/qdesn_multiquantile_score_display.tex"
        path = self.root / relative
        text = path.read_text()
        self.assertIn("0.3805", text)
        path.write_text(text.replace("0.3805", "0.3000", 1))
        manifest_path = self.root / CHECKER.EDITORIAL_MANIFEST
        receipt = json.loads(manifest_path.read_text())
        entry = next(r for r in receipt["outputs"] if r["file"] == relative)
        entry["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        manifest_path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(CHECKER.CheckError, "Unpermitted table/caption transformation|scientific table rows"):
            CHECKER.check(self.root)

    def test_historical_unverified_target_table_cannot_return_as_current_evidence(self):
        path = self.root / "qdesn-supplement.tex"
        relative = "tables/joint_qdesn_article_validation_phase153_replication_summary_mq_display.tex"
        path.write_text(path.read_text() + "\n\\input{" + relative + "}\n")
        self.refresh_ind_manuscript_receipt("qdesn-supplement.tex")
        with self.assertRaisesRegex(CHECKER.CheckError, "Historical unverified-target replication"):
            CHECKER.check(self.root)

    def test_registry_al_exal_label_swap_fails_with_updated_receipts(self):
        def swap(rows):
            joint_al = next(r for r in rows if r["source_key"] == "joint_qdesn_rhs_mcmc")
            joint_exal = next(r for r in rows if r["source_key"] == "joint_exqdesn_rhs_mcmc")
            for field in ("display_tex", "display_text"):
                joint_al[field], joint_exal[field] = joint_exal[field], joint_al[field]
        self.mutate_registry(swap)
        with self.assertRaisesRegex(CHECKER.CheckError, "semantic mapping"):
            CHECKER.check(self.root)

    def test_independent_model_cannot_be_relabelled_mq(self):
        def relabel(rows):
            row = next(r for r in rows if r["source_key"] == "qdesn_rhs_independent_mcmc")
            row.update(model_family="MQ-DESN", display_text="MQ-DESN (AL)", display_tex="MQ--DESN (AL)")
        self.mutate_registry(relabel)
        with self.assertRaisesRegex(CHECKER.CheckError, "semantic mapping"):
            CHECKER.check(self.root)

    def test_stale_derivative_hash_fails(self):
        relative = "tables/joint_qdesn_pure_desn_v2_mq_score_table.tex"
        with (self.root / relative).open("a") as stream:
            stream.write("\n% stale derivative\n")
        with self.assertRaisesRegex(CHECKER.CheckError, "Hash mismatch"):
            CHECKER.check(self.root)

    def test_independent_table_label_cannot_be_mq_even_with_updated_receipt(self):
        relative = "tables/joint_qdesn_pure_desn_v2_mq_score_table.tex"
        path = self.root / relative
        original = path.read_text()
        mutated, count = re.subn(r"(?<![A-Za-z])Q--DESN \(AL\)", "MQ--DESN (AL)", original, count=1)
        self.assertEqual(count, 1)
        path.write_text(mutated)
        receipt_path = self.root / CHECKER.JOINT_MANIFEST
        receipt = json.loads(receipt_path.read_text())
        asset = next(r for r in receipt["outputs"] if r["file"] == relative)
        asset["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        asset["size_bytes"] = path.stat().st_size
        receipt_path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(CHECKER.CheckError, "display-label counts|Frozen source changed: tables/joint_qdesn_(?:mq_presentation_manifest.json|pure_desn_v2_mq_score_table.tex)"):
            CHECKER.check(self.root)

    def test_stale_manifest_output_hash_fails(self):
        path = self.root / CHECKER.GLOFAS_MANIFEST
        receipt = json.loads(path.read_text())
        receipt["assets"][0]["output_sha256"] = "0" * 64
        path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(CHECKER.CheckError, "Hash mismatch"):
            CHECKER.check(self.root)

    def test_late_stale_selected_alias_fails(self):
        path = self.root / "qdesn-supplement.tex"
        text = path.read_text()
        needle = r"\input{tables/qdesn_sections5_7_supp_display_overrides.tex}"
        self.assertIn(needle, text)
        path.write_text(text.replace(needle, needle + "\n" + r"\input{tables/glofas_review_figure_overrides.tex}", 1))
        with self.assertRaisesRegex(CHECKER.CheckError, "selected aliases|selected alias|A stale later alias overrides|effective|selected|MQ TeX"):
            CHECKER.check(self.root)

    def test_stale_joint_main_wrapper_fails(self):
        path = self.root / "main.tex"
        text = path.read_text()
        needle = "tables/qdesn_multiquantile_forecast_figure_display.tex"
        self.assertIn(needle, text)
        path.write_text(text.replace(needle, "tables/joint_qdesn_pure_desn_v2_forecast_figure.tex", 1))
        self.refresh_ind_manuscript_receipt("main.tex")
        with self.assertRaisesRegex(CHECKER.CheckError, "MQ TeX|selected aliases|Stale JOINT|effective|selected"):
            CHECKER.check(self.root)

    def test_posterior_target_mutation_fails_even_with_updated_module_receipt(self):
        path = self.root / CHECKER.TARGET_AUDIT
        text = path.read_text()
        old = CHECKER.csv_rows(self.root, CHECKER.TARGET_AUDIT)[0]["posterior_target_sha256"]
        path.write_text(text.replace(old, "0" * 64, 1))
        receipt_path = self.root / CHECKER.JOINT_MANIFEST
        receipt = json.loads(receipt_path.read_text())
        receipt["sources"][CHECKER.TARGET_AUDIT] = hashlib.sha256(path.read_bytes()).hexdigest()
        receipt_path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(CHECKER.CheckError, "Hash mismatch"):
            CHECKER.check(self.root)

    def test_pricefm_mq_assertion_fails(self):
        path = self.root / "main.tex"
        text = path.read_text()
        needle = r"\label{sec:pricefm-application}"
        self.assertIn(needle, text)
        path.write_text(text.replace(needle, needle + "\nThe fitted model is MQ--DESN.\n", 1))
        self.refresh_ind_manuscript_receipt("main.tex")
        with self.assertRaisesRegex(CHECKER.CheckError, "PriceFM"):
            CHECKER.check(self.root)

    def test_historical_numeric_edit_fails_even_with_updated_receipt(self):
        relative = "tables/joint_qdesn_article_validation_phase153_replication_summary_mq_display.tex"
        path = self.root / relative
        text = path.read_text()
        self.assertIn("-0.054", text)
        path.write_text(text.replace("-0.054", "-0.055", 1))
        receipt_path = self.root / CHECKER.HISTORICAL_MANIFEST
        receipt = json.loads(receipt_path.read_text())
        asset = next(r for r in receipt["assets"] if r["output"] == relative)
        asset["output_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        receipt_path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(CHECKER.CheckError, "approved replacements"):
            CHECKER.check(self.root)


if __name__ == "__main__":
    unittest.main()
