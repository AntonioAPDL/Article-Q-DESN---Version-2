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
        # The real research checkout passed full Git-backed admission above.
        # This separate mode tests copied public-source mutations only; it
        # cannot create a qualifying receipt or authenticate source ancestry.
        portable = CHECKER.check(cls.fixture, portable_reader_fixture=True)
        if CHECKER.READER_FIELD in CHECKER.load_json(cls.fixture, CHECKER.READER_RECEIPT):
            assert portable["source_ancestry_authenticated"] is False

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
            compression = CHECKER.compression_helper(self.root)
            if compression is not None:
                # Explicit copied negative fixture only: reseal the changed
                # text/routes so the semantic guard, not a stale checksum,
                # decides. Historical receipt namespaces stay immutable.
                manifest_path = self.root / compression.selected_manifest_path(self.root)
                manifest = json.loads(manifest_path.read_text())
                manifest["current_source_sha256"][relative] = receipt["sources"][relative]
                try:
                    routes = compression.route_inventory(self.root)
                except ValueError:
                    # A forbidden consumer is itself the intended negative
                    # fixture. Leave its route receipt stale so CHECKER, not
                    # this test helper, rejects the invalid allowlist closure.
                    pass
                else:
                    manifest["actual_input_routes"] = {p: docs for p, docs in routes.items() if docs}
                manifest_path.write_text(json.dumps(manifest))
            elif CHECKER.READER_FIELD in receipt:
                receipt[CHECKER.READER_FIELD]["updated_source_sha256"][relative] = receipt["sources"][relative]
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
        revision = CHECKER.READER_FIELD in CHECKER.load_json(self.root, CHECKER.READER_RECEIPT)
        essential = (self.root / "tables/appendix_essential_20261106_contract.json").exists()
        expected = (3 if essential else 4 if revision else 9) if (self.root / "tables/glofas_same_family_current_authority.json").exists() else 8
        result = CHECKER.check(self.root, portable_reader_fixture=True)
        self.assertEqual(result["selected_mq_pdfs"], expected)
        self.assertFalse(result["source_ancestry_authenticated"])

    def test_copied_fixture_cannot_use_default_full_admission_without_git(self):
        if CHECKER.READER_FIELD not in CHECKER.load_json(self.root, CHECKER.READER_RECEIPT):
            self.skipTest("Historical projection has no new successor")
        self.assertFalse((self.root / ".git").exists())
        with self.assertRaisesRegex(CHECKER.CheckError, "Git|fixed Git evidence|baseline|ancestry"):
            CHECKER.check(self.root)

    def test_mandatory_current_mq_evidence_cannot_be_removed(self):
        displays = (
            "tables/qdesn_multiquantile_score_display.tex",
            "tables/qdesn_multiquantile_crossing_display.tex",
            "tables/qdesn_multiquantile_recursive_policy_display.tex",
        )
        if CHECKER.compression_helper(self.root) is not None:
            displays = ("tables/appendix_compact_20261106_mq_scores.tex",
                        "tables/qdesn_multiquantile_crossing_display.tex",
                        "tables/appendix_compact_20261106_mq_fit_rmse.tex")
        if (self.root / "tables/appendix_essential_20261106_contract.json").exists():
            displays = ("tables/appendix_compact_20261106_mq_scores.tex",
                        "tables/appendix_essential_20261106_mq_crossings.tex")
        for relative in displays:
            with self.subTest(relative=relative):
                path = self.root / "qdesn-supplement.tex"
                original = path.read_text()
                marker = "\\input{" + relative + "}"
                self.assertIn(marker, original)
                path.write_text(original.replace(marker, "", 1))
                self.refresh_ind_manuscript_receipt("qdesn-supplement.tex")
                with self.assertRaisesRegex(CHECKER.CheckError, "mandatory appendix evidence|mandatory actual role consumer absent|not selected|omits an authenticated"):
                    CHECKER.check(self.root, portable_reader_fixture=True)
                path.write_text(original)
                self.refresh_ind_manuscript_receipt("qdesn-supplement.tex")

    def test_essential_archived_fit_panel_cannot_return(self):
        if not (self.root / "tables/appendix_essential_20261106_contract.json").exists():
            self.skipTest("Essential-layout successor is not selected")
        path = self.root / "qdesn-supplement.tex"
        path.write_text(path.read_text() + "\n\\input{tables/appendix_compact_20261106_mq_fit_rmse.tex}\n")
        self.refresh_ind_manuscript_receipt("qdesn-supplement.tex")
        with self.assertRaisesRegex(CHECKER.CheckError, "archived|Archived|not selected|forbidden"):
            CHECKER.check(self.root, portable_reader_fixture=True)

    def test_archived_role_cannot_be_forged_into_current_evidence(self):
        path = self.root / CHECKER.READER_DISPOSITION
        records = CHECKER.csv_rows(self.root, CHECKER.READER_DISPOSITION)
        row = next(r for r in records if r["role_id"] == "mq_secondary_score_table")
        row["disposition"] = "retained"
        with path.open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=tuple(records[0]), lineterminator="\n")
            writer.writeheader(); writer.writerows(records)
        relative = CHECKER.READER_ARCHIVES["mq_secondary_score_table"]
        supplement = self.root / "qdesn-supplement.tex"
        supplement.write_text(supplement.read_text() + "\n\\input{" + relative + "}\n")
        self.refresh_ind_manuscript_receipt("qdesn-supplement.tex")
        receipt_path = self.root / CHECKER.READER_RECEIPT
        receipt = CHECKER.load_json(self.root, CHECKER.READER_RECEIPT)
        receipt[CHECKER.READER_FIELD]["disposition_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        receipt_path.write_text(json.dumps(receipt))
        compression = CHECKER.compression_helper(self.root)
        if compression is not None and compression.essential_requested(self.root):
            # Forge the mutable copied-fixture pin too: the frozen historical
            # namespace, not an accidentally stale checksum, must still reject.
            manifest_path = self.root / compression.selected_manifest_path(self.root)
            manifest = json.loads(manifest_path.read_text())
            manifest["current_source_sha256"][CHECKER.READER_DISPOSITION] = hashlib.sha256(path.read_bytes()).hexdigest()
            manifest_path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(CHECKER.CheckError, "archived display cannot be promoted|archived display has returned|historical reader receipt or immutable outer scientific pins changed|historical namespace or immutable outer scientific pins changed"):
            CHECKER.check(self.root, portable_reader_fixture=True)

    def test_archived_scientific_table_remains_immutable(self):
        relative = "tables/qdesn_multiquantile_secondary_score_display.tex"
        path = self.root / relative
        self.assertNotIn("\\input{" + relative + "}", (self.root / "qdesn-supplement.tex").read_text())
        path.write_text(path.read_text() + "\nunauthorized archived edit\n")
        with self.assertRaisesRegex(CHECKER.CheckError, "bytes/hash mismatch|immutable scientific|Unpermitted table/caption|copied (?:fixture current|essential) source differs: tables/qdesn_multiquantile_secondary_score_display.tex"):
            CHECKER.check(self.root, portable_reader_fixture=True)

    def test_current_glofas_approval_cannot_be_omitted(self):
        path = self.root / "tables/glofas_same_family_current_authority.json"
        if not path.exists():
            self.skipTest("Historical-only projection has no corrected GloFAS authority")
        path.unlink()
        with self.assertRaisesRegex(CHECKER.CheckError,
                "without its approved authority|(?:Missing allowlisted file|bounded regular public file required): tables/glofas_same_family_current_authority\\.json"):
            CHECKER.check(self.root, portable_reader_fixture=True)

    def test_superseded_issued_glofas_table_cannot_return(self):
        if not (self.root / "tables/glofas_same_family_current_authority.json").exists():
            self.skipTest("Historical-only projection has no corrected GloFAS authority")
        path = self.root / "qdesn-supplement.tex"
        path.write_text(path.read_text() + "\n\\input{tables/glofas_forecast_correction_main_scores_display.tex}\n")
        self.refresh_ind_manuscript_receipt("qdesn-supplement.tex")
        with self.assertRaisesRegex(CHECKER.CheckError, "superseded GloFAS issued-window table"):
            CHECKER.check(self.root, portable_reader_fixture=True)

    def test_all_active_mq_caption_derivatives_preserve_table_rows(self):
        builder = CHECKER.editorial_checker(self.root).load_builder(self.root)
        for source, output in CHECKER.EDITORIAL_JOINT_TABLES.items():
            self.assertEqual(builder.table_rows(CHECKER.read(self.root, source)),
                             builder.table_rows(CHECKER.read(self.root, output)))

    def test_superseded_mq_table_cannot_replace_caption_derivative(self):
        if (self.root / "tables/appendix_essential_20261106_contract.json").exists():
            source, output = ("tables/joint_qdesn_pure_desn_v2_mq_crossing_table.tex",
                              "tables/appendix_essential_20261106_mq_crossings.tex")
        else:
            source, output = next((s, o) for s, o in CHECKER.EDITORIAL_JOINT_TABLES.items()
                                  if o in (self.root / "qdesn-supplement.tex").read_text())
        path = self.root / "qdesn-supplement.tex"
        text = path.read_text()
        self.assertIn(output, text)
        path.write_text(text.replace(output, source, 1))
        self.refresh_ind_manuscript_receipt("qdesn-supplement.tex")
        with self.assertRaisesRegex(CHECKER.CheckError,
                "omits an authenticated|superseded|mandatory appendix evidence|mandatory actual role consumer absent|"
                "Source-inferred inputs absent from allowlist: tables/joint_qdesn_pure_desn_v2_mq_(?:score|crossing)_table\\.tex"):
            CHECKER.check(self.root, portable_reader_fixture=True)

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
        with self.assertRaisesRegex(CHECKER.CheckError, "Unpermitted table/caption transformation|scientific table rows|copied (?:fixture current|essential) source differs: tables/qdesn_multiquantile_score_display.tex"):
            CHECKER.check(self.root, portable_reader_fixture=True)

    def test_historical_unverified_target_table_cannot_return_as_current_evidence(self):
        path = self.root / "qdesn-supplement.tex"
        relative = "tables/joint_qdesn_article_validation_phase153_replication_summary_mq_display.tex"
        path.write_text(path.read_text() + "\n\\input{" + relative + "}\n")
        self.refresh_ind_manuscript_receipt("qdesn-supplement.tex")
        with self.assertRaisesRegex(CHECKER.CheckError,
                "Historical unverified-target replication|Source-inferred inputs absent from allowlist: "
                "tables/joint_qdesn_article_validation_phase153_replication_summary_mq_display\\.tex"):
            CHECKER.check(self.root, portable_reader_fixture=True)

    def test_registry_al_exal_label_swap_fails_with_updated_receipts(self):
        def swap(rows):
            joint_al = next(r for r in rows if r["source_key"] == "joint_qdesn_rhs_mcmc")
            joint_exal = next(r for r in rows if r["source_key"] == "joint_exqdesn_rhs_mcmc")
            for field in ("display_tex", "display_text"):
                joint_al[field], joint_exal[field] = joint_exal[field], joint_al[field]
        self.mutate_registry(swap)
        with self.assertRaisesRegex(CHECKER.CheckError, "semantic mapping"):
            CHECKER.check(self.root, portable_reader_fixture=True)

    def test_independent_model_cannot_be_relabelled_mq(self):
        def relabel(rows):
            row = next(r for r in rows if r["source_key"] == "qdesn_rhs_independent_mcmc")
            row.update(model_family="MQ-DESN", display_text="MQ-DESN (AL)", display_tex="MQ--DESN (AL)")
        self.mutate_registry(relabel)
        with self.assertRaisesRegex(CHECKER.CheckError, "semantic mapping"):
            CHECKER.check(self.root, portable_reader_fixture=True)

    def test_stale_derivative_hash_fails(self):
        relative = "tables/joint_qdesn_pure_desn_v2_mq_score_table.tex"
        with (self.root / relative).open("a") as stream:
            stream.write("\n% stale derivative\n")
        with self.assertRaisesRegex(CHECKER.CheckError, "Hash mismatch"):
            CHECKER.check(self.root, portable_reader_fixture=True)

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
        with self.assertRaisesRegex(CHECKER.CheckError, "display-label counts|(?:Frozen source changed|copied (?:fixture current|essential) source differs): tables/joint_qdesn_(?:mq_presentation_manifest.json|pure_desn_v2_mq_score_table.tex)"):
            CHECKER.check(self.root, portable_reader_fixture=True)

    def test_stale_manifest_output_hash_fails(self):
        path = self.root / CHECKER.GLOFAS_MANIFEST
        receipt = json.loads(path.read_text())
        receipt["assets"][0]["output_sha256"] = "0" * 64
        path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(CHECKER.CheckError, "Hash mismatch"):
            CHECKER.check(self.root, portable_reader_fixture=True)

    def test_late_stale_selected_alias_fails(self):
        path = self.root / "qdesn-supplement.tex"
        text = path.read_text()
        needle = (r"\input{tables/glofas_same_family_20261103_display_aliases.tex}"
                  if (self.root / "tables/glofas_same_family_current_authority.json").exists()
                  else r"\input{tables/qdesn_sections5_7_supp_display_overrides.tex}")
        self.assertIn(needle, text)
        path.write_text(text.replace(needle, needle + "\n" + r"\input{tables/glofas_review_figure_overrides.tex}", 1))
        self.refresh_ind_manuscript_receipt("qdesn-supplement.tex")
        with self.assertRaisesRegex(CHECKER.CheckError,
                "selected aliases|selected alias|A stale later alias overrides|effective|selected|MQ TeX|"
                "Source-inferred inputs absent from allowlist: figures/glofas_application/glofas_search3_review_20261008_part4\\.pdf"):
            CHECKER.check(self.root, portable_reader_fixture=True)

    def test_stale_joint_main_wrapper_fails(self):
        path = self.root / "main.tex"
        text = path.read_text()
        needle = "tables/qdesn_multiquantile_forecast_figure_display.tex"
        self.assertIn(needle, text)
        path.write_text(text.replace(needle, "tables/joint_qdesn_pure_desn_v2_forecast_figure.tex", 1))
        self.refresh_ind_manuscript_receipt("main.tex")
        with self.assertRaisesRegex(CHECKER.CheckError,
                "MQ TeX|selected aliases|Stale JOINT|effective|selected|"
                "Source-inferred inputs absent from allowlist: .*joint_qdesn_pure_desn_v2_forecast_figure\\.tex"):
            CHECKER.check(self.root, portable_reader_fixture=True)

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
            CHECKER.check(self.root, portable_reader_fixture=True)

    def test_pricefm_mq_assertion_fails(self):
        path = self.root / "main.tex"
        text = path.read_text()
        needle = r"\label{sec:pricefm-application}"
        self.assertIn(needle, text)
        path.write_text(text.replace(needle, needle + "\nThe fitted model is MQ--DESN.\n", 1))
        self.refresh_ind_manuscript_receipt("main.tex")
        with self.assertRaisesRegex(CHECKER.CheckError, "PriceFM"):
            CHECKER.check(self.root, portable_reader_fixture=True)

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
            CHECKER.check(self.root, portable_reader_fixture=True)


if __name__ == "__main__":
    unittest.main()
