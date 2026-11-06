#!/usr/bin/env python3.11
"""Generated metadata/text mutations only; no fits, forecasts or science writes."""
import copy
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("clarity_receipts", ROOT / "scripts/refresh_article_clarity_editorial_receipts_20261104.py")
REFRESH = importlib.util.module_from_spec(spec)
spec.loader.exec_module(REFRESH)
next_spec = importlib.util.spec_from_file_location("reader_appendix_successor", ROOT / "scripts/refresh_reader_online_appendix_receipts_20261106.py")
SUCCESSOR = importlib.util.module_from_spec(next_spec)
next_spec.loader.exec_module(SUCCESSOR)


def digest(value):
    return REFRESH.sha(value.encode())


class ReceiptTests(unittest.TestCase):
    def setUp(self):
        self.baseline = dict(schema="independent-forecast-300-500-article-v1",
            authority_id="independent_forecast_300_primary_500_sensitivity_v1",
            sources={p: digest("old " + p) for p in REFRESH.MUTABLE},
            outputs={"tables/scientific_fixture.csv": digest("immutable science")},
            editorial_source_refresh={"schema": "authentic historical IND record"},
            glofas_article_source_refresh={"schema": "authentic historical GloFAS record"},
            fits_launched=0, forecasts_launched=0, primary_cutoff=300)
        self.baseline["sources"]["tables/source_fixture.csv"] = digest("immutable source")
        self.hashes = self.baseline["sources"] | self.baseline["outputs"]
        self.hashes.update({p: digest("new " + p) for p in REFRESH.MUTABLE})
        self.context = {p: digest(p) for p in ("presentation_sha256", "display_sha256", "generator_sha256", "refresher_sha256")}

    def plan(self, current=None):
        return REFRESH.receipt_plan(self.baseline, self.baseline if current is None else current,
            self.hashes.__getitem__, self.context)

    def test_exact_document_only_successor_preserves_both_historical_records(self):
        result = self.plan()
        successor = result.pop(REFRESH.FIELD)
        for path in REFRESH.MUTABLE:
            self.assertEqual(result["sources"][path], self.hashes[path])
            result["sources"][path] = self.baseline["sources"][path]
        self.assertEqual(result, self.baseline)
        self.assertEqual(successor["updated_paths"], list(REFRESH.MUTABLE))
        self.assertEqual(successor["baseline_commit"], REFRESH.BASELINE)
        for field in ("scientific_values_changed", "scientific_outputs_regenerated", "fits_launched", "forecasts_launched", "scores_recomputed"):
            self.assertFalse(successor[field])
        self.assertEqual(self.plan(self.plan()), self.plan())

    def test_later_document_edits_remain_narrow_and_repeatable(self):
        first = self.plan()
        self.hashes["main.tex"] = digest("later reviewed prose")
        updated = self.plan(first)
        self.assertEqual(updated["outputs"], first["outputs"])
        for field in REFRESH.HISTORICAL:
            self.assertEqual(updated[field], first[field])
        self.assertNotEqual(first["sources"]["main.tex"], updated["sources"]["main.tex"])

    def test_scientific_and_historical_mutations_rejected(self):
        changes = [lambda d: d.update(fits_launched=1), lambda d: d.update(primary_cutoff=500),
            lambda d: d.update(unapproved="extra"), lambda d: d.update(authority_id="different"),
            lambda d: d["outputs"].update({"tables/scientific_fixture.csv": digest("changed")}),
            lambda d: d["sources"].update({"tables/source_fixture.csv": digest("changed")}),
            lambda d: d["sources"].update({"tables/new_source.csv": digest("extra")})]
        changes += [lambda d, field=field: d[field].update(schema="rewritten") for field in REFRESH.HISTORICAL]
        for change in changes:
            candidate = copy.deepcopy(self.baseline); change(candidate)
            with self.subTest(change=change), self.assertRaises(REFRESH.EditorialError):
                self.plan(candidate)

    def test_every_immutable_live_hash_verified(self):
        for path in ("tables/source_fixture.csv", "tables/scientific_fixture.csv"):
            old = self.hashes[path]; self.hashes[path] = digest("tampered live bytes")
            with self.subTest(path=path), self.assertRaises(REFRESH.EditorialError):
                self.plan()
            self.hashes[path] = old

    def test_successor_cannot_widen_scope_or_forge_prior_receipt(self):
        changes = [lambda d: d.update(updated_paths=list(REFRESH.MUTABLE) + ["tables/source_fixture.csv"]),
            lambda d: d.update(scientific_values_changed=True), lambda d: d.update(forecasts_launched=1),
            lambda d: d.update(original_manifest_sha256="0" * 64),
            lambda d: d["preserved_historical_fields_sha256"].update(editorial_source_refresh="0" * 64),
            lambda d: d["updated_source_sha256"].update({"main.tex": "0" * 64}),
            lambda d: d["presentation_manifest"].update(operation="regenerate scientific values")]
        for change in changes:
            candidate = self.plan(); change(candidate[REFRESH.FIELD])
            with self.subTest(change=change), self.assertRaises(REFRESH.EditorialError):
                self.plan(candidate)

    def test_context_must_have_exact_valid_hashes(self):
        for field in list(self.context):
            old = self.context[field]; self.context[field] = "invalid"
            with self.subTest(field=field), self.assertRaises(REFRESH.EditorialError):
                self.plan()
            self.context[field] = old
        self.context["extra"] = digest("not allowed")
        with self.assertRaises(REFRESH.EditorialError):
            self.plan()

    def test_duplicate_json_keys_rejected(self):
        with self.assertRaises(REFRESH.EditorialError):
            REFRESH.decode(b'{"sources":{}, "sources":{}}')

    def test_safe_regular_files_exclude_runtime_and_symlinks(self):
        with tempfile.TemporaryDirectory(prefix="clarity_path_fixture_") as directory:
            root = Path(directory); (root / "tables").mkdir()
            (root / "tables/data.csv").write_text("synthetic public fixture")
            self.assertTrue(REFRESH.regular(root, "tables/data.csv"))
            (root / "tables/link.csv").symlink_to(root / "tables/data.csv")
            for path in ("../outside", "tables/link.csv", "/etc/passwd", "application/cache/x.csv", "local_trackers/x.csv", "tables/fit.RDS", "tables/../data.csv"):
                with self.subTest(path=path), self.assertRaises(REFRESH.EditorialError):
                    REFRESH.regular(root, path)

    def test_two_metadata_writes_are_read_back_and_race_protected(self):
        with tempfile.TemporaryDirectory(prefix="clarity_atomic_fixture_") as directory:
            root = Path(directory); (root / "tables").mkdir()
            receipt = self.plan(); presult = {"generated": "presentation receipt"}
            old = {"generated": "original receipt"}; pold = {"generated": "original presentation"}
            (root / REFRESH.RECEIPT).write_bytes(REFRESH.canonical(old))
            (root / REFRESH.PRESENTATION).write_bytes(REFRESH.canonical(pold))
            pins = {p: REFRESH.sha((root / p).read_bytes()) for p in (REFRESH.RECEIPT, REFRESH.PRESENTATION)}
            prepared = (root, old, pold, receipt, presult, pins, {"synthetic": True})
            with mock.patch.object(REFRESH, "prepare", return_value=prepared):
                with self.assertRaises(REFRESH.EditorialError):
                    REFRESH.refresh(root)
                REFRESH.refresh(root, write=True)
            self.assertEqual(json.loads((root / REFRESH.RECEIPT).read_text()), receipt)
            self.assertEqual(json.loads((root / REFRESH.PRESENTATION).read_text()), presult)
            self.assertEqual(list((root / "tables").glob(".article_clarity_receipt_*")), [])
            with mock.patch.object(REFRESH, "prepare", return_value=prepared), self.assertRaises(REFRESH.EditorialError):
                REFRESH.refresh(root, write=True)

    def test_interruption_after_first_metadata_write_fails_closed_and_is_retryable(self):
        with tempfile.TemporaryDirectory(prefix="clarity_interrupted_fixture_") as directory:
            root = Path(directory); (root / "tables").mkdir()
            old, pold = {"fixture": "old shared"}, {"fixture": "old display"}
            result, presult = self.plan(), {"fixture": "new display"}
            for path, value in ((REFRESH.RECEIPT, old), (REFRESH.PRESENTATION, pold)):
                (root / path).write_bytes(REFRESH.canonical(value))
            pins = {p: REFRESH.sha((root / p).read_bytes()) for p in (REFRESH.RECEIPT, REFRESH.PRESENTATION)}
            prepared = (root, old, pold, result, presult, pins, {"fixture": True})
            original_replace = REFRESH.os.replace
            def interrupt(source, destination):
                if destination == root / REFRESH.RECEIPT:
                    raise OSError("generated interruption")
                return original_replace(source, destination)
            with mock.patch.object(REFRESH, "prepare", return_value=prepared), mock.patch.object(REFRESH.os, "replace", side_effect=interrupt), self.assertRaises(OSError):
                REFRESH.refresh(root, write=True)
            self.assertEqual(json.loads((root / REFRESH.RECEIPT).read_text()), old)
            self.assertEqual(json.loads((root / REFRESH.PRESENTATION).read_text()), presult)
            self.assertEqual(list((root / "tables").glob(".article_clarity_receipt_*")), [])
            pins[REFRESH.PRESENTATION] = REFRESH.sha((root / REFRESH.PRESENTATION).read_bytes())
            retry = (root, old, presult, result, presult, pins, {"fixture": True})
            with mock.patch.object(REFRESH, "prepare", return_value=retry):
                REFRESH.refresh(root, write=True)
            self.assertEqual(json.loads((root / REFRESH.RECEIPT).read_text()), result)


class PresentationTests(unittest.TestCase):
    def setUp(self):
        self.base = dict(schema="qdesn-sections5-7-presentation-v1", generator=REFRESH.GENERATOR,
            generator_sha256=digest("old generator"), sources={"source.csv": digest("source")},
            scientific_values_changed=False,
            outputs=[dict(role="glofas_specifications", file=REFRESH.DISPLAY, sha256=digest("old header"), rows=90),
                     dict(role="unchanged_science", file="figures/frozen.pdf", sha256=digest("frozen"))])

    def plan(self, candidate):
        return REFRESH.presentation_plan(self.base, candidate, actual_generator_sha=digest("new generator"), actual_display_sha=digest("new header"))

    def test_only_two_declared_hashes_change_and_interrupted_retry_is_safe(self):
        result = self.plan(self.base)
        self.assertEqual(self.plan(result), result)
        result["generator_sha256"] = self.base["generator_sha256"]
        result["outputs"][0]["sha256"] = self.base["outputs"][0]["sha256"]
        self.assertEqual(result, self.base)

    def test_presentation_cannot_admit_numeric_source_row_or_other_output_changes(self):
        changes = [lambda d: d.update(scientific_values_changed=True),
            lambda d: d["sources"].update({"source.csv": digest("tampered")}),
            lambda d: d["outputs"][0].update(rows=180),
            lambda d: d["outputs"][0].update(file="tables/unapproved.tex"),
            lambda d: d["outputs"][1].update(sha256=digest("new science"))]
        for change in changes:
            candidate = self.plan(self.base); change(candidate)
            with self.subTest(change=change), self.assertRaises(REFRESH.EditorialError):
                self.plan(candidate)


class CurrentTextTests(unittest.TestCase):
    def setUp(self):
        self.reader_revision = SUCCESSOR.active(ROOT)
        if self.reader_revision:
            # Actual CURRENT semantics and scientific blobs pass the successor
            # before these dated C01--C11 prose fixtures are authenticated.
            SUCCESSOR.refresh(ROOT)
            self.main = SUCCESSOR.historical_text(ROOT, "main.tex")
            self.supplement = SUCCESSOR.historical_text(ROOT, "qdesn-supplement.tex")
        else:
            self.main = (ROOT / "main.tex").read_text()
            self.supplement = (ROOT / "qdesn-supplement.tex").read_text()
        self.display = (ROOT / REFRESH.DISPLAY).read_text()

    def test_all_eleven_approved_corrections_present(self):
        self.assertEqual(set(REFRESH.editorial_checks(self.main, self.supplement, self.display)),
            {"C%02d" % i for i in range(1, 12)})

    def test_live_successor_authenticates_public_evidence_and_current_metadata(self):
        if self.reader_revision:
            live = SUCCESSOR.refresh(ROOT)
            self.assertEqual(live[SUCCESSOR.FIELD]["baseline_commit"], SUCCESSOR.BASELINE)
            self.assertFalse(live[SUCCESSOR.FIELD]["scientific_values_changed"])
            return
        live = REFRESH.refresh(ROOT)
        self.assertEqual(live[REFRESH.FIELD]["baseline_commit"], REFRESH.BASELINE)
        self.assertFalse(live[REFRESH.FIELD]["scientific_values_changed"])

    def test_supported_readonly_cli_uses_the_reviewed_version(self):
        # On Muscat this interpreter is Python 3.6.8. The historical adapter
        # must execute the 3.11 successor rather than import its new syntax.
        command = (["/usr/bin/python3.11", "-I", "-B", str(ROOT / SUCCESSOR.REFRESHER)] if self.reader_revision else
            ["/usr/bin/python3", "-I", "-B", str(ROOT / "scripts/refresh_glofas_article_shared_receipts.py")])
        result = subprocess.run(command + ["--root", str(ROOT), "--check"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("READER_ONLINE_APPENDIX_RECEIPTS_CHECK_PASS" if self.reader_revision else
            "ARTICLE_CLARITY_EDITORIAL_RECEIPTS_CHECK_PASS", result.stdout)

    def test_historical_write_entrypoint_refuses_a_general_editorial_receipt(self):
        oldspec = importlib.util.spec_from_file_location("old_glofas_refresh_scope",
            ROOT / "scripts/refresh_glofas_article_shared_receipts.py")
        old = importlib.util.module_from_spec(oldspec); oldspec.loader.exec_module(old)
        with tempfile.TemporaryDirectory(prefix="clarity_old_writer_fixture_") as directory:
            root = Path(directory); target = root / old.RECEIPT
            target.parent.mkdir(parents=True)
            before = REFRESH.canonical({REFRESH.FIELD: {"generated": "fixture"}})
            target.write_bytes(before)
            with self.assertRaises(old.RefreshError):
                old.refresh(root, write=True)
            self.assertEqual(target.read_bytes(), before)

    def test_every_correction_has_a_real_negative_fixture(self):
        fixtures = [
            ("C01", "main", "quantile-specific forecast correction", "best forecast correction"),
            ("C02", "display", "$m_z$", "$m_x$"),
            ("C03", "main", "equal-weight isotonic projection", "sorting"),
            ("C04", "main", "\\section{Posterior Computation}", "It is distinct from a variational quadrature calculation.\\section{Posterior Computation}"),
            ("C05", "main", "\\section{Posterior Computation}", "\\label{tab:main-computation-map}\\section{Posterior Computation}"),
            ("C06", "main", "\\section{Posterior Computation}", "\\label{tab:main-computation-settings}\\section{Posterior Computation}"),
            ("C07", "main", "\\bar{\\vect x}_{o+h}^{\\top}\\vect\\beta_k^{(b)}", "\\tilde{\\vect x}_{o+h}^{(b)\\top}\\vect\\beta_k^{(b)}"),
            ("C08", "main", "Observation times", "Retained indices"),
            ("C09", "main", "\\clearpage", ""),
            ("C10", "main", "Additional structure", "Internal row type"),
            ("C11", "main", "final historical time", "arbitrary time"),
        ]
        for correction, role, before, after in fixtures:
            texts = {key: re.sub(r"\s+", " ", text) for key, text in
                dict(main=self.main, supplement=self.supplement, display=self.display).items()}
            self.assertTrue(before in texts[role], "Missing actual negative fixture: " + correction)
            texts[role] = texts[role].replace(before, after)
            with self.subTest(correction=correction), self.assertRaises(REFRESH.EditorialError):
                REFRESH.editorial_checks(**texts)


if __name__ == "__main__":
    unittest.main()
