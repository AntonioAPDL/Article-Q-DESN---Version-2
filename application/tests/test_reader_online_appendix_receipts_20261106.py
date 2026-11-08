#!/usr/bin/env python3.11
"""Bounded editorial/mathematical fixtures; no fits, payloads or publication."""
from __future__ import annotations
import copy
import csv
import importlib.util
import math
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("reader_appendix_receipts", ROOT / "scripts/refresh_reader_online_appendix_receipts_20261106.py")
R = importlib.util.module_from_spec(spec)
spec.loader.exec_module(R)


class ReceiptTests(unittest.TestCase):
    def setUp(self):
        self.hashes = {p: R.sha(p.encode()) for p in R.MUTABLE - {R.RECEIPT, R.PRESENTATION}}
        self.baseline = dict(schema="frozen-public-fixture", authority_id="unchanged",
            sources={p: R.sha(("old " + p).encode()) for p in self.hashes},
            outputs={"tables/fixture_scientific.csv": R.sha(b"science")},
            **{p: {"original": p} for p in R.HISTORY}, fits_launched=0, forecasts_launched=0)
        self.context = dict(refresher=R.REFRESHER, refresher_sha256=R.sha(b"code"),
            disposition_map=R.DISPOSITION, disposition_sha256=R.sha(b"roles"),
            presentation_manifest_sha256=R.sha(b"presentation"), protected_inventory_sha256=R.sha(b"protected"),
            protected_files=2, semantic_checks=["actual-current-fixture"], disposition_roles=3,
            validation_source_sha256={p: R.sha(p.encode()) for p in R.VALIDATION_PATHS},
            role_routing_sha256=R.sha(b"required actual selected roles"),
            publication_inventory_changed=False,
            legacy_fixture_policy="validated_live_semantics_then_637_prose_only_never_scientific_inputs")

    def plan(self, current=None, hashes=None, context=None):
        return R.receipt_plan(self.baseline, self.baseline if current is None else current,
            self.hashes if hashes is None else hashes, self.context if context is None else context)

    def test_all_three_histories_and_scientific_outputs_preserved(self):
        result = self.plan()
        self.assertEqual(result["outputs"], self.baseline["outputs"])
        for key in R.HISTORY:
            self.assertEqual(result[key], self.baseline[key])
        self.assertEqual(self.plan(result), result)

    def test_legitimate_later_prose_refresh_preserves_history(self):
        first = self.plan()
        changed = dict(self.hashes); changed["main.tex"] = R.sha(b"new approved prose")
        result = self.plan(first, hashes=changed)
        self.assertEqual(result[R.FIELD]["updated_source_sha256"]["main.tex"], changed["main.tex"])
        self.assertEqual(result["general_editorial_source_refresh"], self.baseline["general_editorial_source_refresh"])

    def test_refuses_mutations_including_write_planning(self):
        changes = (
            lambda x: x.update(fits_launched=1),
            lambda x: x["outputs"].update({"tables/fixture_scientific.csv": "0" * 64}),
            lambda x: x["editorial_source_refresh"].update(original="forged"),
        )
        for change in changes:
            value = copy.deepcopy(self.baseline); change(value)
            with self.subTest(change=change), self.assertRaises(R.EditorialError): self.plan(value)

    def test_previous_scope_and_zero_counters_cannot_be_forged_before_refresh(self):
        changes = (
            lambda x: x.update(fits_launched=1), lambda x: x.update(forecasts_launched=1),
            lambda x: x.update(scores_recomputed=1), lambda x: x.update(scientific_values_changed=True),
            lambda x: x.update(publication_inventory_changed=True),
            lambda x: x.update(original_presentation_manifest_sha256="0" * 64),
            lambda x: x.update(original_manifest_sha256="0" * 64),
            lambda x: x.update(updated_paths=x["updated_paths"] + ["application/R/unapproved.R"]),
            lambda x: x.update(legacy_fixture_policy="trust_old_text_only"),
            lambda x: x.update(unreviewed=True),
            lambda x: x["updated_source_sha256"].update({"tables/unapproved.csv": "0" * 64}),
        )
        for change in changes:
            current = self.plan(); change(current[R.FIELD])
            with self.subTest(change=change), self.assertRaises(R.EditorialError): self.plan(current)

    def test_reject_source_inventory_and_context_expansion(self):
        paths = dict(self.hashes); paths["application/R/unapproved.R"] = "0" * 64
        with self.assertRaises(R.EditorialError): self.plan(hashes=paths)
        context = dict(self.context); context["unknown"] = 1
        with self.assertRaises(R.EditorialError): self.plan(context=context)
        context = dict(self.context); context["publication_inventory_changed"] = True
        with self.assertRaises(R.EditorialError): self.plan(context=context)

    def test_json_duplicate_paths_symlinks_and_runtime_rejected(self):
        with self.assertRaises(R.EditorialError): R.decode(b'{"key":1,"key":2}')
        with tempfile.TemporaryDirectory(prefix="reader_appendix_fixture_") as directory:
            root = Path(directory); (root / "good.txt").write_text("public generated fixture")
            (root / "link.txt").symlink_to(root / "good.txt")
            self.assertEqual(R.regular(root, "good.txt"), b"public generated fixture")
            for name in ("link.txt", "../good.txt", "/tmp/good.txt", "cache/file.txt", "model.rds"):
                with self.subTest(name=name), self.assertRaises(R.EditorialError): R.regular(root, name)
        with self.assertRaises(R.EditorialError): R.historical_text(ROOT, "tables/fixture.csv")

    def test_atomic_partial_failure_retains_recoverable_metadata(self):
        with tempfile.TemporaryDirectory(prefix="reader_appendix_atomic_") as directory:
            root = Path(directory); (root / "tables").mkdir()
            old, pold = {"old": "receipt"}, {"old": "presentation"}
            result, presentation = self.plan(), {"new": "presentation"}
            (root / R.RECEIPT).write_bytes(R.canonical(old))
            (root / R.PRESENTATION).write_bytes(R.canonical(pold))
            pins = {p: R.sha((root / p).read_bytes()) for p in (R.RECEIPT, R.PRESENTATION)}
            prepared = (root, old, pold, result, presentation, pins)
            real_replace = R.os.replace
            def fail_second(source, destination):
                if destination == root / R.RECEIPT: raise OSError("constructed interruption")
                real_replace(source, destination)
            with mock.patch.object(R, "prepare", return_value=prepared), mock.patch.object(R.os, "replace", side_effect=fail_second):
                with self.assertRaises(OSError): R.refresh(root, write=True)
            self.assertEqual(R.decode((root / R.RECEIPT).read_bytes()), old)
            self.assertEqual(R.decode((root / R.PRESENTATION).read_bytes()), presentation)
            self.assertEqual(list((root / "tables").glob(".reader_appendix_receipt_*")), [])
            pins[R.PRESENTATION] = R.sha((root / R.PRESENTATION).read_bytes())
            retry = (root, old, presentation, result, presentation, pins)
            with mock.patch.object(R, "prepare", return_value=retry): R.refresh(root, write=True)
            self.assertEqual(R.decode((root / R.RECEIPT).read_bytes()), result)

    def test_source_change_during_metadata_replacement_cannot_report_success(self):
        with tempfile.TemporaryDirectory(prefix="reader_appendix_postwrite_") as directory:
            root = Path(directory); (root / "tables").mkdir()
            old, pold = {"old": "receipt"}, {"old": "presentation"}
            result, presentation = self.plan(), {"new": "presentation"}
            for path,value in ((R.RECEIPT,old),(R.PRESENTATION,pold)):
                (root/path).write_bytes(R.canonical(value))
            (root/"scoped.txt").write_bytes(b"original generated public fixture")
            pins = {p:R.sha((root/p).read_bytes()) for p in (R.RECEIPT,R.PRESENTATION,"scoped.txt")}
            prepared = (root,old,pold,result,presentation,pins)
            real_replace = R.os.replace
            def mutate_after_replacement(source,destination):
                real_replace(source,destination)
                if destination == root/R.RECEIPT:
                    (root/"scoped.txt").write_bytes(b"constructed concurrent source change")
            with mock.patch.object(R,"prepare",return_value=prepared), mock.patch.object(R.os,"replace",side_effect=mutate_after_replacement):
                with self.assertRaises(R.EditorialError): R.refresh(root,write=True)


class MathematicalTests(unittest.TestCase):
    def test_exact_interval_score_identity_and_current_non_wis_normalization(self):
        rho = lambda p, e: e * (p - (e < 0))
        interval = lambda a, lo, hi, y: hi - lo + 2 / a * max(lo-y, 0) + 2 / a * max(y-hi, 0)
        quantiles = [-3, -2, -1, 0, 1, 2, 3]
        levels = [.05, .1, .25, .5, .75, .9, .95]
        weights = [.025, .1, .2, .25, .2, .1, .025]
        for y in [-5, -3, -2.5, -1, 0, .7, 2, 3, 8]:
            score = 2 * sum(w*rho(p, y-q) for w,p,q in zip(weights,levels,quantiles))
            representation = .25*abs(y) + .0025*interval(.1,-3,3,y) + .02*interval(.2,-2,2,y) + .1*interval(.5,-1,1,y)
            self.assertAlmostEqual(score, representation, places=12)
        point_score = 2*sum(w*rho(p, 1) for w,p in zip(weights,levels))
        self.assertAlmostEqual(point_score, .9)
        self.assertAlmostEqual(2*sum(rho(p,1) for p in levels)/7, 1)
        score = 2*sum(w*rho(p,-q) for w,p,q in zip(weights,levels,quantiles))
        standard = 2*sum(rho(p,-q) for p,q in zip(levels,quantiles))/7
        self.assertNotAlmostEqual(score/.9, standard, places=10)

    def test_quantile_of_histories_is_not_the_average_conditional_quantile(self):
        # Two equally likely histories give nonoverlapping uniform responses.
        conditional_quartiles = [.25, 10.25]
        averaged_conditional = sum(conditional_quartiles)/2
        integrated_quartile = .5  # .5 * P(Unif(0,1)<=.5) = .25.
        self.assertEqual(averaged_conditional, 5.25)
        self.assertNotEqual(averaged_conditional, integrated_quartile)


class CurrentSourceTests(unittest.TestCase):
    def test_actual_required_evidence_cannot_be_archived_by_forging_the_map(self):
        import shutil
        with (ROOT/R.DISPOSITION).open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        main = (ROOT/"main.tex").read_text()
        supplement = (ROOT/"qdesn-supplement.tex").read_text()
        compression = R.compression_successor(ROOT)
        R.current_route_checks(ROOT,rows)
        with tempfile.TemporaryDirectory(prefix="reader_appendix_routing_") as directory:
            root = Path(directory)
            # Public article-safe inputs only, never model/runtime payloads.
            paths = [p for p in (ROOT/"overleaf/article_files.txt").read_text().splitlines() if p and not p.startswith("#")]
            paths += ["overleaf/article_files.txt","scripts/audit_qdesn_article_dependencies.py"]
            if compression is not None:
                paths += list(compression.dependency_paths(ROOT))
            for path in paths:
                target = root/path; target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copyfile(ROOT/path,target)
            essential = compression is not None and compression.essential_requested(ROOT)
            mandatory = (("tables/appendix_essential_20261106_ind_forecast_mae.tex",
                          "tables/appendix_compact_20261106_ind_frequencies.tex") if essential else
                (compression.PREFIX + name + ".tex" for name in
                ("ind_forecast_mae", "ind_sensitivity", "ind_frequencies")) if compression is not None else
                (R.CAPTIONS[1].replace("figures_v1","mae_figure_v1"),
                 "tables/independent_train500_eval500_mcmc_figures_v1.tex",
                 "tables/independent_forecast_calibration_figure_v1.tex"))
            for path in mandatory:
                marker = "\\input{"+path+"}"
                self.assertIn(marker,supplement)
                (root/"qdesn-supplement.tex").write_text(supplement.replace(marker,"% omitted in generated fixture"))
                forged = copy.deepcopy(rows)
                for row in forged:
                    if path in row["asset_paths"]: row["disposition"]="public_archive"
                # Dynamic dispatch loads an independent module instance; assert
                # the public error contract rather than its Python class identity.
                with self.subTest(path=path),self.assertRaisesRegex(Exception,"not selected|actual role consumer absent"):
                    R.current_route_checks(root,forged)
                (root/"qdesn-supplement.tex").write_text(supplement)

    def test_actual_documents_and_real_negative_mutations(self):
        main = (ROOT / "main.tex").read_text()
        supplement = (ROOT / "qdesn-supplement.tex").read_text()
        bibliography = (ROOT / "refs.bib").read_text()
        compression = R.compression_successor(ROOT)
        essential = compression is not None and compression.essential_requested(ROOT)
        semantic = (compression.essential_semantic_checks if essential else
                    compression.semantic_checks if compression is not None else R.semantic_checks)
        error = compression.CompressionError if compression is not None else R.EditorialError
        semantic(main, supplement, bibliography)
        mutations = (
            ("main", "same parameter draw", "a new parameter draw"),
            ("main", "features averaged", "features selected separately"),
            ("main", "equal-weight isotonic", "unadjusted"),
            ("main", "\\Normal(0\\mid\\beta_j,\\zeta^2)", "1"),
            ("main", "\\sigma\\sim\\IG(a_\\sigma,b_\\sigma)", "\\sigma>0"),
            ("main", "\\xi\\sim\\IG(1/2,1/\\tau_0^2)", "\\xi\\sim\\IG(1/2,1)"),
            ("main", "future USGS measurements are reserved for scoring", "future USGS measurements are used for fitting"),
            ("main", "direct multihorizon predictors", "recursive multihorizon predictors"),
            ("main", "all six fitted corrections", "five fitted corrections"),
            ("supplement", "\\frac{r+1}{2}", "\\frac{r}{2}"),
            ("supplement", "\\mat H\\mat\\Sigma\\mat H^\\top", "\\operatorname{diag}(\\mat\\Sigma)"),
            ("supplement", "\\prod_{h=1}^{28}\\prod_{e=1}^{51}", "\\prod_{h=1}^{28}\\prod_{e=1}^{50}"),
            ("supplement", "\\prod_{h=1}^{28}\\prod_{e=1}^{51}", "\\{\\prod_{h=1}^{28}\\prod_{e=1}^{51}\\}^{1/51}"),
            ("supplement", "R_T(\\vect y_{F,k})", "1"),
            ("supplement", "0.025,0.10,0.20,0.25,0.20,0.10,0.025", "0.1,0.1,0.2,0.2,0.2,0.1,0.1"),
        )
        if compression is not None:
            # The new revision owns current semantics; dated assertions above
            # remain applicable to its historical branch, not to removed prose.
            mutations = tuple(value for value in mutations if value[1] not in
                {"same parameter draw", "equal-weight isotonic"}) + (
                ("supplement", r"\frac{D_\gamma^2}{B_\gamma}", r"D_\gamma^2"),
                ("supplement", r"a_\zeta+\frac r2" if essential else r"a_\zeta+\frac{r}{2}", r"a_\zeta+\frac{r+1}{2}"),
            )
        for role,before,after in mutations:
            value = main if role == "main" else supplement
            self.assertIn(before, R.plain(value), "negative fixture must actually match: " + before)
            changed = R.plain(value).replace(before, after)
            with self.subTest(role=role,before=before), self.assertRaises(error):
                semantic(changed if role == "main" else main,
                                  changed if role == "supplement" else supplement, bibliography)
        # Harmless line wrapping and a concise paraphrase do not erase meaning.
        paraphrase = main.replace("retaining the same parameter draw", "keeping the same parameter draw")
        self.assertNotEqual(paraphrase, main, "permitted paraphrase must match actual prose")
        semantic(paraphrase.replace("Quantile location:", "Quantile\n location:"), supplement, bibliography)

    def test_only_verified_bibliography_and_caption_substitutions(self):
        before = R.baseline_bytes(ROOT, "refs.bib")
        after = (ROOT / "refs.bib").read_bytes()
        R.verify_bibliography(before, after)
        with self.assertRaises(R.EditorialError): R.verify_bibliography(before, after.replace(b"1008618", b"1008619"))
        with self.assertRaises(R.EditorialError): R.verify_bibliography(before, after.replace(b"GneitingResin2023Calibration", b"changed_unrelated_key"))
        for path in R.CAPTIONS:
            R.verify_caption(R.baseline_bytes(ROOT, path), (ROOT/path).read_bytes(), path)
            with self.assertRaises(R.EditorialError):
                R.verify_caption(R.baseline_bytes(ROOT,path), (ROOT/path).read_bytes()+b"\nunauthorized caption", path)
        for path in R.GENERATORS:
            R.verify_generator(R.baseline_bytes(ROOT,path), (ROOT/path).read_bytes(), path)
            with self.assertRaises(R.EditorialError):
                R.verify_generator(R.baseline_bytes(ROOT,path), (ROOT/path).read_bytes()+b"\nunauthorized code", path)


if __name__ == "__main__":
    unittest.main()
