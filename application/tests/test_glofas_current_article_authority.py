#!/usr/bin/env python3
"""Corrected GloFAS release guards in disposable local-only Git repositories.

Python 3.6 standard library. No real remote, model object or scientific input.
"""
import csv
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zlib


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/glofas_current_article_authority.py"
spec = importlib.util.spec_from_file_location("glofas_guard", str(SCRIPT))
GUARD = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GUARD)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def generated_pdf(text="Generated fixture only", title="Generated figure", incidental=False, attachment=False):
    def literal(value):
        return value.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)").encode("ascii")
    content = b"BT /F1 12 Tf 20 40 Td (" + literal(text) + b") Tj ET\n"
    if incidental:
        content += b"% Incidental binary-pattern test d:\\ marker\n"
    compressed = zlib.compress(content, 0)
    objects = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 240 100] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        b"<< /Length " + str(len(compressed)).encode("ascii") + b" /Filter /FlateDecode >>\nstream\n" + compressed + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", b"<< /Title (" + literal(title) + b") >>"]
    if attachment:
        objects[0] = b"<< /Type /Catalog /Pages 2 0 R /Names << /EmbeddedFiles << /Names [(receipt.txt) 7 0 R] >> >> >>"
        objects.extend([b"<< /Type /Filespec /F (receipt.txt) /EF << /F 8 0 R >> >>",
                        b"<< /Type /EmbeddedFile /Length 7 >>\nstream\nprivate\nendstream"])
    data = b"%PDF-1.4\n"; offsets = [0]
    for index, value in enumerate(objects, 1):
        offsets.append(len(data)); data += str(index).encode("ascii") + b" 0 obj\n" + value + b"\nendobj\n"
    startxref = len(data)
    data += b"xref\n0 " + str(len(offsets)).encode("ascii") + b"\n0000000000 65535 f \n"
    data += b"".join(("%010d 00000 n \n" % offset).encode("ascii") for offset in offsets[1:])
    data += b"trailer\n<< /Size " + str(len(offsets)).encode("ascii") + b" /Root 1 0 R /Info 6 0 R >>\nstartxref\n" + str(startxref).encode("ascii") + b"\n%%EOF\n"
    return data


class AuthorityFixture:
    def __init__(self, base):
        self.root = Path(base)
        self.env = os.environ.copy()
        for key in list(self.env):
            if key.startswith("GIT_") or key in ("GH_TOKEN", "GITHUB_TOKEN", "SSH_ASKPASS"):
                self.env.pop(key, None)
        self.env.update({"GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
                         "GIT_TERMINAL_PROMPT": "0", "GIT_ALLOW_PROTOCOL": "file",
                         "GIT_AUTHOR_NAME": "GloFAS generated test", "GIT_COMMITTER_NAME": "GloFAS generated test",
                         "GIT_AUTHOR_EMAIL": "generated@example.invalid", "GIT_COMMITTER_EMAIL": "generated@example.invalid"})
        self.git("init", "--quiet")
        for name in ("glofas_current_article_authority.py", "overleaf_review_draft_status.py"):
            self.write("scripts/" + name, (ROOT / "scripts" / name).read_bytes())
        for path in GUARD.EXPECTED_ASSETS:
            self.write(path, generated_pdf() if path.endswith(".pdf") else "Generated fixture\n")
        alias = ["\\renewcommand{\\" + key + "}{" + path + "}" for key, path in sorted(GUARD.ALIASES.items())]
        alias += [r"\renewcommand{\GlofasApplicationCurrentOriginDate}{25 December 2022}",
                  r"\renewcommand{\GlofasApplicationCurrentScoredHorizons}{28}"]
        alias += [r"\renewcommand{\GlofasApplicationCurrentQdesnAcrps}{0.8000}",
                  r"\renewcommand{\GlofasApplicationCurrentRawAcrps}{0.5000}",
                  r"\renewcommand{\GlofasApplicationCurrentQdesnCheckLoss}{0.4000}",
                  r"\renewcommand{\GlofasApplicationCurrentRawCheckLoss}{0.2500}"]
        alias += [r"\providecommand{\GlofasApplicationCurrentNormalRidgeAcrps}{}",
                  r"\providecommand{\GlofasApplicationCurrentNormalRhsAcrps}{}",
                  r"\renewcommand{\GlofasApplicationCurrentNormalRidgeAcrps}{0.6000}",
                  r"\renewcommand{\GlofasApplicationCurrentNormalRhsAcrps}{0.7000}"]
        self.write(GUARD.ALIAS_PATH, "\n".join(alias) + "\n")
        self.metrics = []
        for index, family in enumerate(("Raw GloFAS", "Normal Ridge", "Normal RHS", "Independent AL",
                                        "Independent exAL", "MQ AL", "MQ exAL")):
            self.metrics.append({"family": family, "grid_acrps_log1p": .5 + index / 10,
                "mean_check_loss": (.5 + index / 10) / 2, "covered90_count": 28 - index,
                "coverage90_percent": 100 * (28 - index) / 28, "raw_crossing_pairs": 2 * index,
                "raw_crossing_percent": 100 * 2 * index / 168,
                "max_positive_adjacent_violation_log1p": .001 * index, "n_horizons": 28})
        metric_stream = io.StringIO()
        metric_writer = csv.DictWriter(metric_stream, fieldnames=list(self.metrics[0]))
        metric_writer.writeheader(); metric_writer.writerows(self.metrics)
        self.write("tables/" + GUARD.PREFIX + "_family_metrics.csv", metric_stream.getvalue())
        labels = ("Raw GloFAS", "Normal Ridge", "Normal RHS", "Q--DESN (AL)", "Q--DESN (exAL)",
                  "MQ--DESN (AL)", "MQ--DESN (exAL)")
        main_rows, full_rows = [], []
        for row, label in zip(self.metrics, labels):
            main_rows.append("%s & %.4f & %d/28 (%.1f\\%%) & %.2f \\\\" % (label,
                row["grid_acrps_log1p"], row["covered90_count"], row["coverage90_percent"], row["raw_crossing_percent"]))
            full_rows.append("%s & %.4f & %.4f & %d/28 & %.2f & %.4f \\\\" % (label,
                row["grid_acrps_log1p"], row["mean_check_loss"], row["covered90_count"], row["raw_crossing_percent"],
                row["max_positive_adjacent_violation_log1p"]))
        self.write(GUARD.ALIASES["GlofasApplicationCurrentScoreTable"], "\n".join(main_rows) + "\n")
        self.write(GUARD.ALIASES["GlofasApplicationCurrentIssuedSupplementScoreTable"], "\n".join(full_rows) + "\n")
        historical = ["\\providecommand{\\" + key + "}{tables/historical.tex}" for key in sorted(GUARD.ALIASES)]
        self.write("tables/historical.tex", "\n".join(historical) + "\n")
        self.main = ("\\documentclass{article}\n\\newif\\ifAnonymous\n"
                     "\\input{tables/historical.tex}\n\\input{" + GUARD.ALIAS_PATH + "}\n"
                     "\\begin{document}\n\\section{GloFAS}\\label{sec:data}\n"
                     "\\input{\\GlofasApplicationCurrentScoreTable}\n"
                     "\\includegraphics[width=.94\\textwidth]{\\GlofasApplicationCurrentForecastWindowFigure}\n"
                     "\\end{document}\n")
        self.supp = ("\\documentclass{article}\n\\input{tables/historical.tex}\n\\input{" + GUARD.ALIAS_PATH + "}\n"
                     "\\begin{document}\n\\input{\\GlofasApplicationCurrentIssuedSupplementScoreTable}\n\\end{document}\n")
        self.write("main.tex", self.main)
        self.write("qdesn-supplement.tex", self.supp)
        self.packet_hash = "b" * 64
        self.decision = {
            "schema_version": "glofas_same_family_article_assets_v1",
            "status": "COMPLETE_ARTICLE_ASSET_CANDIDATE_NOT_AUTHORITY",
            "lineage": {"scientific_source": {"source_commit": GUARD.PRODUCER_SOURCE,
                          "posterior_target_sha256": GUARD.POSTERIOR_TARGET},
                        "packet_manifest_sha256": self.packet_hash},
            "forecast_rows": 1372, "models": 7, "probabilities": GUARD.PROBABILITIES,
            "historical_fitted_rows": 1260, "issued_member_rows": 1428, "history_rows": 30, "truth_rows": 28,
            "isotonic_adjustment": False, "clipping_or_smoothing": False,
            "added_credible_ribbons": False, "extra_response_noise_added": False,
            "article_publication_authorized": False, "new_fits": 0,
        }
        self.json(GUARD.DECISION_PATH, self.decision)
        self.authority = {
            "schema_version": "glofas_same_family_current_article_authority_v1",
            "status": "SCIENTIFIC_REVIEW_APPROVED", "producer_source_commit": GUARD.PRODUCER_SOURCE,
            "posterior_target_sha256": GUARD.POSTERIOR_TARGET,
            "execution_source_commit": "90309792229f98a6ad372fe6072f850f9b12deed",
            "scored_packet_manifest_sha256": self.packet_hash, "asset_manifest": {},
            "forecast_rows": 1372, "families": 7, "horizons": 28, "probabilities": GUARD.PROBABILITIES,
            "alias_file": GUARD.ALIAS_PATH, "active_aliases": dict(GUARD.ALIASES),
            "scientific_review": {key: True for key in GUARD.REVIEW_FIELDS},
        }
        self.reseal()

    def write(self, path, data):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data if isinstance(data, bytes) else data.encode("utf-8"))

    def json(self, path, data):
        self.write(path, json.dumps(data, sort_keys=True, indent=2) + "\n")

    def git(self, *args):
        value = subprocess.run(["git"] + list(args), cwd=str(self.root), env=self.env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=12)
        if value.returncode:
            raise AssertionError(value.stderr.decode("utf-8", "replace"))
        return value.stdout.decode("utf-8").strip()

    def reseal(self):
        stream = io.StringIO()
        writer = csv.DictWriter(stream, fieldnames=["relative_path", "size_bytes", "sha256"], lineterminator="\n")
        writer.writeheader()
        for path in sorted(GUARD.EXPECTED_ASSETS):
            value = (self.root / path).read_bytes()
            writer.writerow({"relative_path": path, "size_bytes": len(value), "sha256": sha(value)})
        data = stream.getvalue().encode("utf-8")
        self.write(GUARD.MANIFEST_PATH, data)
        self.authority["asset_manifest"] = {"relative_path": GUARD.MANIFEST_PATH, "sha256": sha(data)}
        self.json(GUARD.AUTHORITY_PATH, self.authority)

    def commit(self):
        self.git("add", "--all")
        self.git("commit", "--quiet", "--allow-empty", "-m", "Generated authority fixture")
        return self.git("rev-parse", "HEAD")

    def check(self, status=False):
        commit = self.commit()
        script = "overleaf_review_draft_status.py" if status else "glofas_current_article_authority.py"
        return subprocess.run([sys.executable, "-B", str(self.root / "scripts" / script), commit],
                              cwd=str(self.root), env=self.env, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, universal_newlines=True, timeout=15)


class AuthorityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="glofas_authority_generated_")
        self.addCleanup(self.temp.cleanup)
        self.f = AuthorityFixture(self.temp.name)

    def fails(self, fragment, status=False):
        result = self.f.check(status)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(fragment, result.stdout)

    def test_reviewed_complete_committed_release(self):
        self.assertEqual(len(GUARD.EXPECTED_ASSETS), 19)
        for status in (False, True):
            result = self.f.check(status)
            self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout.strip(), "release")

    def test_reviewed_source_tree_and_dependency_closure(self):
        reviewed = GUARD.validate_authority_tree(self.f.root)
        self.assertEqual(reviewed["status"], "SCIENTIFIC_REVIEW_APPROVED")
        paths = GUARD.authority_dependency_paths(self.f.root)
        self.assertTrue(GUARD.EXPECTED_ASSETS <= paths)
        self.assertTrue({GUARD.AUTHORITY_PATH, GUARD.MANIFEST_PATH, "main.tex", "qdesn-supplement.tex",
                         "tables/historical.tex", "scripts/glofas_current_article_authority.py"} <= paths)

    def test_source_tree_changed_asset_fails(self):
        self.f.write(GUARD.ALIASES["GlofasApplicationCurrentScoreTable"], "Changed uncommitted asset\n")
        with self.assertRaises(GUARD.AuthorityError):
            GUARD.validate_authority_tree(self.f.root)

    def test_source_tree_missing_approval_fails(self):
        (self.f.root / GUARD.AUTHORITY_PATH).unlink()
        with self.assertRaises(GUARD.AuthorityError):
            GUARD.validate_authority_tree(self.f.root)

    def test_source_tree_stale_late_alias_fails(self):
        self.f.write("main.tex", self.f.main +
            "\n\\renewcommand{\\GlofasApplicationCurrentScoreTable}{tables/historical.tex}\n")
        with self.assertRaises(GUARD.AuthorityError):
            GUARD.validate_authority_tree(self.f.root)

    def test_missing_approval_fails_after_notices_removed(self):
        (self.f.root / GUARD.AUTHORITY_PATH).unlink()
        self.fails("committed regular file required", status=True)

    def test_unreviewed_or_incomplete_contract(self):
        self.f.authority["status"] = "CANDIDATE_NOT_ARTICLE_AUTHORITY"
        self.f.json(GUARD.AUTHORITY_PATH, self.f.authority)
        self.fails("explicit scientific review")

    def test_unapproved_execution_or_target(self):
        self.f.authority["execution_source_commit"] = "a" * 40
        self.f.json(GUARD.AUTHORITY_PATH, self.f.authority)
        self.fails("unapproved producer")

    def test_missing_seven_family_surface(self):
        self.f.authority["forecast_rows"] = 1176
        self.f.json(GUARD.AUTHORITY_PATH, self.f.authority)
        self.fails("complete corrected forecast surface")

    def test_changed_asset_hash(self):
        self.f.write(GUARD.ALIASES["GlofasApplicationCurrentScoreTable"], "Changed values\n")
        self.fails("asset bytes differ")

    def test_rehashed_wrong_score_lineage(self):
        self.f.decision["lineage"]["packet_manifest_sha256"] = "c" * 64
        self.f.json(GUARD.DECISION_PATH, self.f.decision); self.f.reseal()
        self.fails("lineage differs")

    def test_no_claimed_ribbons_or_projection(self):
        self.f.decision["isotonic_adjustment"] = True
        self.f.json(GUARD.DECISION_PATH, self.f.decision); self.f.reseal()
        self.fails("asset functional")

    def test_later_direct_override_rejected(self):
        self.f.write("main.tex", self.f.main.replace(r"\begin{document}",
          r"\renewcommand{\GlofasApplicationCurrentScoreTable}{tables/historical.tex}" + "\n" + r"\begin{document}"))
        self.fails("stale effective alias")

    def test_later_shared_override_rejected(self):
        self.f.write("tables/late.tex", r"\renewcommand{\GlofasApplicationCurrentScoreTable}{tables/historical.tex}")
        self.f.write("main.tex", self.f.main.replace(r"\begin{document}", r"\input{tables/late.tex}" + "\n" + r"\begin{document}"))
        self.fails("stale effective alias")

    def test_unsupported_def_override_fails_closed(self):
        self.f.write("main.tex", self.f.main.replace(r"\begin{document}",
          r"\def\GlofasApplicationCurrentScoreTable{tables/historical.tex}" + "\n" + r"\begin{document}"))
        self.fails("unsupported current alias definition")

    def test_hidden_approved_input_rejected(self):
        self.f.write("main.tex", self.f.main.replace(r"\input{" + GUARD.ALIAS_PATH + "}",
            r"\newcommand{\unused}{\input{" + GUARD.ALIAS_PATH + "}}"))
        self.fails("hidden or conditional")

    def test_conditional_approved_input_rejected(self):
        self.f.write("main.tex", self.f.main.replace(r"\input{" + GUARD.ALIAS_PATH + "}",
            r"\iffalse\input{" + GUARD.ALIAS_PATH + r"}\fi"))
        self.fails("hidden or conditional")

    def test_duplicate_approved_input_rejected(self):
        self.f.write("qdesn-supplement.tex", self.f.supp.replace(r"\begin{document}",
            r"\input{" + GUARD.ALIAS_PATH + "}\n" + r"\begin{document}"))
        self.fails("exactly once")

    def test_supplement_missing_current_full_scores(self):
        self.f.write("qdesn-supplement.tex", self.f.supp.replace(
            r"\input{\GlofasApplicationCurrentIssuedSupplementScoreTable}", "Historical scores only"))
        self.fails("supplement must display")

    def test_unused_main_objects_are_not_visible(self):
        self.f.write("main.tex", self.f.main.replace(r"\input{\GlofasApplicationCurrentScoreTable}",
            r"\newcommand{\unusedScore}{\input{\GlofasApplicationCurrentScoreTable}}"))
        self.fails("main must display")

    def test_self_consistently_rehashed_wrong_table_rejected(self):
        path = GUARD.ALIASES["GlofasApplicationCurrentScoreTable"]
        self.f.write(path, (self.f.root / path).read_text().replace("0.5000", "0.4000"))
        self.f.reseal(); self.fails("displayed score row differs")

    def test_rehashed_wrong_numeric_alias_rejected(self):
        path = GUARD.ALIAS_PATH
        self.f.write(path, (self.f.root / path).read_text().replace("{0.8000}", "{0.7000}"))
        self.f.reseal(); self.fails("numerical alias differs")

    def test_rehashed_wrong_normal_ridge_alias_rejected(self):
        path = GUARD.ALIAS_PATH
        self.f.write(path, (self.f.root / path).read_text().replace("{0.6000}", "{0.5000}"))
        self.f.reseal(); self.fails("numerical alias differs")

    def test_rehashed_wrong_normal_rhs_alias_rejected(self):
        path = GUARD.ALIAS_PATH
        self.f.write(path, (self.f.root / path).read_text().replace("{0.7000}", "{0.5000}"))
        self.f.reseal(); self.fails("numerical alias differs")

    def test_rehashed_missing_public_family_rejected(self):
        path = "tables/" + GUARD.PREFIX + "_family_metrics.csv"
        self.f.write(path, "\n".join((self.f.root / path).read_text().splitlines()[:-1]) + "\n")
        self.f.reseal(); self.fails("seven distinct public family")

    def test_rehashed_extra_historical_table_row_rejected(self):
        path = GUARD.ALIASES["GlofasApplicationCurrentScoreTable"]
        self.f.write(path, (self.f.root / path).read_text() + "Old historical model & 0.2 & 28/28 & 0 \\\\\n")
        self.f.reseal(); self.fails("exactly seven model rows")

    def test_private_path_even_when_rehashed(self):
        self.f.write(GUARD.ALIASES["GlofasApplicationCurrentScoreTable"], "Source /home/private/run.rds\n")
        self.f.reseal(); self.fails("private path")

    def test_private_path_in_decoded_pdf_page_rejected(self):
        self.f.write(GUARD.ALIASES["GlofasApplicationCurrentForecastWindowFigure"], generated_pdf(text="C:\\private\\model.rds"))
        self.f.reseal(); self.fails("PDF text or metadata")

    def test_private_path_in_pdf_metadata_rejected(self):
        self.f.write(GUARD.ALIASES["GlofasApplicationCurrentForecastWindowFigure"], generated_pdf(title="C:\\private\\analysis"))
        self.f.reseal(); self.fails("PDF text or metadata")

    def test_incidental_drive_pattern_in_compressed_pdf_is_not_a_filename(self):
        data = generated_pdf(incidental=True)
        self.assertIsNotNone(GUARD.PRIVATE.search(data))
        self.f.write(GUARD.ALIASES["GlofasApplicationCurrentForecastWindowFigure"], data)
        self.f.reseal()
        result = self.f.check()
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_embedded_pdf_attachment_rejected(self):
        self.f.write(GUARD.ALIASES["GlofasApplicationCurrentForecastWindowFigure"], generated_pdf(attachment=True))
        self.f.reseal(); self.fails("embedded PDF files")

    def test_manifest_path_traversal_rejected(self):
        self.f.authority["asset_manifest"]["relative_path"] = "tables/../../runtime.csv"
        self.f.json(GUARD.AUTHORITY_PATH, self.f.authority)
        self.fails("namespaced asset manifest")

    def test_committed_symlink_asset_rejected(self):
        asset = self.f.root / GUARD.ALIASES["GlofasApplicationCurrentScoreTable"]
        asset.unlink(); asset.symlink_to(self.f.root / "tables/historical.tex")
        self.f.reseal(); self.fails("committed regular file")

    def test_glofas_release_missing_helper_fails_closed(self):
        (self.f.root / "scripts/glofas_current_article_authority.py").unlink()
        self.fails("GLOFAS_CURRENT_RELEASE_NOT_APPROVED", status=True)

    def test_generic_fixture_without_helper_still_releases(self):
        for path in ("main.tex", "qdesn-supplement.tex"):
            self.f.write(path, "\\documentclass{article}\n\\begin{document}Generic fixture.\\end{document}\n")
        (self.f.root / "scripts/glofas_current_article_authority.py").unlink()
        result = self.f.check(status=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout.strip(), "release")

    def test_dirty_worktree_is_not_a_committed_override(self):
        commit = self.f.commit()
        self.f.write("main.tex", self.f.main.replace(GUARD.ALIAS_PATH, "tables/uncommitted.tex"))
        result = subprocess.run([sys.executable, "-B", str(self.f.root / "scripts/glofas_current_article_authority.py"), commit],
                                cwd=str(self.f.root), env=self.f.env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, universal_newlines=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout)


if __name__ == "__main__":
    unittest.main()
