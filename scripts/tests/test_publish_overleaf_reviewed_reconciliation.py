#!/usr/bin/env python3
"""Test exact, reviewed Overleaf reconciliation using private file-only remotes.

The actual publisher and LaTeX compiler are exercised. All fixture repositories,
hooks and evidence are children of TemporaryDirectory; no production refs,
credentials, HOME or CODEX_HOME are read or changed by these fixtures.
"""

import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest


DIRECTORY = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "independent_review_draft_fixture", str(DIRECTORY / "test_publish_overleaf_review_draft.py"))
draft = importlib.util.module_from_spec(spec)
spec.loader.exec_module(draft)
ROOT = DIRECTORY.parents[1]
CONTRACT_PATH = "overleaf/reviewed_direct_reconciliation_20261030.json"
LEDGER_PATH = "docs/reproducibility/advisor_revision_resolution_20261029.csv"
HELPER = "overleaf_reviewed_reconciliation.py"
REVIEWED_PATHS = ("main.tex", "tables/body.tex", "tables/supplement-body.tex")


def sha256(content):
    return hashlib.sha256(content).hexdigest()


class ReconciliationFixture(draft.Fixture):
    """Keep reviewed browser history separate from research-main ancestry."""

    def __init__(self, parent, name):
        super().__init__(parent, name)
        draft.write(self.repo / "README.md", "# Research repository fixture\n")
        self.historical_main = self.commit("Freeze historical research-source fixture")
        shutil.copy2(str(ROOT / "scripts" / HELPER), str(self.repo / "scripts" / HELPER))
        draft.write(self.repo / LEDGER_PATH,
                    "issue_id,status\nE50,IMPLEMENTED_IN_REVIEW_DRAFT\n")
        self.source_anchor = self.commit("Record reviewed source and annotation disposition")

        self.editor = self.root / "independent-browser-history"
        self.command(["git", "clone", "--quiet", "--branch", "overleaf/article-snapshot",
                      self.origin, self.editor], cwd=self.root)
        self.git_at(self.editor, "config", "user.name", "Isolated advisor fixture")
        self.git_at(self.editor, "config", "user.email", "advisor@example.invalid")
        self.git_at(self.editor, "config", "commit.gpgSign", "false")
        self.git_at(self.editor, "checkout", "--quiet", "-b", "captured-review")
        self.reviewed_bytes = {}
        for path in REVIEWED_PATHS:
            old = (self.editor / path).read_text(encoding="utf-8")
            if path == "main.tex":
                old = old.replace("\\end{document}",
                                  "Advisor review: clarify the forecast construction.\n\\end{document}")
            else:
                old += "\nAdvisor review: explain this comparison.\n"
            self.reviewed_bytes[path] = old
            draft.write(self.editor / path, old)
        self.git_at(self.editor, "add", "--all")
        self.git_at(self.editor, "commit", "--quiet", "-m", "Preserve captured advisor annotations")
        self.captured_review = self.git_at(self.editor, "rev-parse", "HEAD").strip()
        self.git("fetch", "--quiet", self.editor,
                 "refs/heads/captured-review:refs/remotes/captured/review")

        self.git_at(self.editor, "checkout", "--quiet", "-b", "browser-main", self.base_snapshot)
        for path, content in self.reviewed_bytes.items():
            draft.write(self.editor / path, content)
        draft.write(self.editor / "README.md", self.git(
            "show", self.historical_main + ":README.md"))
        draft.write(self.editor / "application/README.md", self.git(
            "show", self.historical_main + ":application/README.md"))
        self.git_at(self.editor, "add", "--all")
        self.git_at(self.editor, "commit", "--quiet", "-m", "Update on isolated Overleaf")
        self.reviewed_direct = self.git_at(self.editor, "rev-parse", "HEAD").strip()
        self.git_at(self.editor, "push", "--quiet", self.direct, "HEAD:refs/heads/main")
        self.git("fetch", "--quiet", "overleaf-direct", "main")

        self.contract = {
            "schema": 1,
            "decision": "publish_reviewed_advisor_revision_no_external_history_in_main",
            "canonical_snapshot": self.base_snapshot,
            "direct_commit": self.reviewed_direct,
            "direct_tree": self.git("rev-parse", self.reviewed_direct + "^{tree}").strip(),
            "direct_diff_sha256": self.raw_diff_sha256(),
            "historical_main": self.historical_main,
            "source_anchor": self.source_anchor,
            "source_article_inputs_sha256": self.article_inputs_sha256(self.source_anchor),
            "captured_review": self.captured_review,
            "reviewed_article_paths": list(REVIEWED_PATHS),
            "extra_support_paths": ["README.md"],
            "expected_added_paths": 1,
            "expected_modified_paths": 4,
            "resolution_ledger_path": LEDGER_PATH,
            "resolution_ledger_sha256": sha256(self.git(
                "show", self.source_anchor + ":" + LEDGER_PATH).encode("utf-8")),
            "resolution_status_counts": {"IMPLEMENTED_IN_REVIEW_DRAFT": 1},
        }
        self.commit_contract()

    def raw_diff_sha256(self):
        raw = self.git("diff", "--raw", "--no-abbrev", "--no-renames", "--no-ext-diff",
                       "--no-textconv", self.base_snapshot, self.reviewed_direct)
        return sha256(raw.encode("utf-8"))

    def article_inputs_sha256(self, source):
        manifest = self.git("show", source + ":overleaf/article_files.txt")
        paths = {line for line in manifest.splitlines() if line and not line.startswith("#")}
        paths.update(("overleaf/article_files.txt", "overleaf/README.md", "overleaf/overleaf.gitignore"))
        rows = []
        for path in sorted(paths):
            entry = self.git("ls-tree", source, "--", path).strip()
            metadata, recorded_path = entry.split("\t", 1)
            mode, object_type, blob = metadata.split()
            if recorded_path != path or object_type != "blob":
                raise AssertionError("Invalid fixture article input: " + path)
            rows.append({"path": path, "mode": mode, "blob": blob})
        return sha256(json.dumps(rows, sort_keys=True, separators=(",", ":")).encode("utf-8"))

    def commit_contract(self):
        draft.write(self.repo / CONTRACT_PATH,
                    json.dumps(self.contract, sort_keys=True, indent=2) + "\n")
        self.source = self.commit("Authorize the exact reviewed browser reconciliation")

    def publish_reviewed(self, requested=None, reconcile=True, draft_mode=True,
                         dry_run=False, success=True, source=None):
        command = [self.repo / "scripts/publish_overleaf_article_snapshot.sh",
                   "--source-commit", source or self.source]
        if draft_mode:
            command.append("--review-draft")
        if reconcile:
            command.extend(("--reconcile-reviewed-direct", requested or self.reviewed_direct))
        if dry_run:
            command.append("--dry-run")
        return self.command(command, success=success)

    def advance_direct(self):
        self.git_at(self.editor, "checkout", "--quiet", "browser-main")
        path = self.editor / "main.tex"
        draft.write(path, path.read_text(encoding="utf-8").replace(
            "\\end{document}", "UNREVIEWED CONCURRENT EDIT\n\\end{document}"))
        self.git_at(self.editor, "add", "main.tex")
        self.git_at(self.editor, "commit", "--quiet", "-m", "Unreviewed later advisor edit")
        self.git_at(self.editor, "push", "--quiet", self.direct, "HEAD:refs/heads/main")
        return self.git_at(self.editor, "rev-parse", "HEAD").strip()


class ReviewedReconciliationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="qdesn-reviewed-reconciliation-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def fixture(self, name="fixture"):
        return ReconciliationFixture(self.root, name)

    def assert_rejected(self, fixture, contains=None, **arguments):
        before = fixture.refs()
        output = fixture.publish_reviewed(success=False, **arguments)
        if contains:
            self.assertIn(contains, output)
        self.assertEqual(fixture.refs(), before)
        return output

    def test_direct_ahead_remains_rejected_without_explicit_authorization(self):
        fixture = self.fixture()
        self.assert_rejected(fixture, "DIRECT_OVERLEAF_AHEAD", reconcile=False)

    def test_reconciliation_does_not_grant_review_draft_permission(self):
        fixture = self.fixture()
        self.assert_rejected(fixture, "GLOFAS_CORRECTION_PENDING", draft_mode=False)

    def test_reviewed_dry_run_changes_no_remote_reference(self):
        fixture = self.fixture()
        before = fixture.refs()
        output = fixture.publish_reviewed(dry_run=True)
        self.assertIn("GIT_ONLY_OVERLEAF_PUBLICATION_DRY_RUN_COMPLETE", output)
        self.assertEqual(before, fixture.refs())

    def test_success_sanitizes_exact_projection_and_preserves_external_parent(self):
        fixture = self.fixture()
        output = fixture.publish_reviewed()
        self.assertIn("GIT_ONLY_OVERLEAF_REVIEW_DRAFT_PUBLICATION_COMPLETE", output)
        source, origin_snapshot, direct = fixture.refs()
        self.assertEqual(source, fixture.source)
        self.assertEqual(origin_snapshot, direct)
        self.assertNotEqual(direct, fixture.reviewed_direct)
        parents = fixture.command(["git", "--git-dir=" + str(fixture.direct),
                                   "rev-list", "--parents", "-n", "1", direct]).strip().split()
        self.assertEqual(parents, [direct, fixture.reviewed_direct])
        inventory = fixture.command(["git", "--git-dir=" + str(fixture.direct),
                                     "ls-tree", "-r", "--name-only", direct]).splitlines()
        self.assertFalse(any(path.startswith(("application/", "local_trackers/")) for path in inventory))
        marker = fixture.marker(fixture.direct, direct)
        self.assertIn("source_commit=" + fixture.source + "\n", marker)
        self.assertIn("publication_status=review-draft\n", marker)
        fixture.command(["git", "merge-base", "--is-ancestor", fixture.reviewed_direct,
                         fixture.source], success=False)
        projection = fixture.build(fixture.source)
        self.assertIn("OVERLEAF_ARTICLE_SNAPSHOT_CHECK=PASS", fixture.check(projection, fixture.source))
        for path in ("main.tex", "qdesn-supplement.tex", "tables/body.tex", "README.md"):
            self.assertEqual(
                fixture.command(["git", "--git-dir=" + str(fixture.direct), "show", direct + ":" + path]),
                (projection / path).read_text(encoding="utf-8"))

    def test_successful_reconciliation_is_idempotent(self):
        fixture = self.fixture()
        fixture.publish_reviewed()
        before = fixture.refs()
        repeated = fixture.publish_reviewed()
        self.assertIn("publication_action=noop", repeated)
        self.assertEqual(before, fixture.refs())

    def test_one_sided_failure_recovers_with_normal_guarded_publisher(self):
        fixture = self.fixture()
        hook = fixture.direct / "hooks/pre-receive"
        draft.write(hook, "#!/bin/sh\nprintf 'Controlled isolated push failure\\n' >&2\nexit 1\n")
        hook.chmod(0o700)
        failed = fixture.publish_reviewed(success=False)
        self.assertIn("Controlled isolated push failure", failed)
        source, sanitized, direct = fixture.refs()
        self.assertEqual(source, fixture.source)
        self.assertEqual(direct, fixture.reviewed_direct)
        self.assertNotEqual(sanitized, direct)
        hook.unlink()
        recovered = fixture.publish_reviewed(reconcile=False)
        self.assertIn("GIT_ONLY_OVERLEAF_REVIEW_DRAFT_PUBLICATION_COMPLETE", recovered)
        self.assertEqual(fixture.refs(), (source, sanitized, sanitized))

    def test_exact_requested_direct_hash_is_mandatory(self):
        fixture = self.fixture()
        self.assert_rejected(fixture, requested=fixture.captured_review)

    def test_later_unreviewed_direct_tip_is_not_authorized(self):
        fixture = self.fixture()
        later = fixture.advance_direct()
        self.assertNotEqual(later, fixture.reviewed_direct)
        self.assert_rejected(fixture)

    def test_changed_canonical_base_is_not_authorized(self):
        fixture = self.fixture()
        fixture.git_at(fixture.editor, "push", "--quiet", fixture.origin,
                       fixture.captured_review + ":refs/heads/overleaf/article-snapshot")
        self.assert_rejected(fixture, "PUBLICATION_REF_DIVERGENCE")

    def test_each_contract_anchor_or_inventory_mismatch_is_rejected(self):
        fixture = self.fixture()
        original = dict(fixture.contract)
        mutations = {
            "canonical_snapshot": fixture.historical_main,
            "direct_commit": fixture.captured_review,
            "direct_tree": fixture.git("rev-parse", fixture.base_snapshot + "^{tree}").strip(),
            "direct_diff_sha256": "0" * 64,
            "historical_main": fixture.captured_review,
            "source_anchor": fixture.captured_review,
            "source_article_inputs_sha256": "0" * 64,
            "captured_review": fixture.base_snapshot,
            "expected_added_paths": 2,
            "expected_modified_paths": 3,
            "resolution_ledger_sha256": "0" * 64,
            "resolution_status_counts": {"IMPLEMENTED_IN_REVIEW_DRAFT": 2},
            "reviewed_article_paths": ["main.tex"],
            "extra_support_paths": [],
        }
        for key, value in mutations.items():
            with self.subTest(field=key):
                fixture.contract = dict(original)
                fixture.contract[key] = value
                fixture.commit_contract()
                self.assert_rejected(fixture)

    def test_changed_current_article_input_is_not_the_reviewed_source(self):
        fixture = self.fixture()
        draft.write(fixture.repo / "tables/body.tex", "Unreviewed scientific text.\n")
        fixture.source = fixture.commit("Change an article input after review")
        self.assert_rejected(fixture)

    def test_changed_resolution_ledger_is_rejected(self):
        fixture = self.fixture()
        draft.write(fixture.repo / LEDGER_PATH,
                    "issue_id,status\nE50,MODEL_TEXT_REVISED_CORRECTED_RESULT_PACKET_PENDING\n")
        fixture.source = fixture.commit("Change a resolution after the freeze")
        self.assert_rejected(fixture)

    def test_missing_committed_contract_is_rejected(self):
        fixture = self.fixture()
        (fixture.repo / CONTRACT_PATH).unlink()
        fixture.source = fixture.commit("Remove reconciliation authorization")
        self.assert_rejected(fixture)

    def test_dirty_and_stale_sources_remain_rejected(self):
        fixture = self.fixture()
        old_source = fixture.source
        draft.write(fixture.repo / "review.tmp", "Uncommitted fixture note.\n")
        self.assert_rejected(fixture, "DIRTY_WORKTREE")
        fixture.source = fixture.commit("Advance source after the requested authority")
        self.assert_rejected(fixture, "SOURCE_MAIN_MOVED", source=old_source)

    def test_unreviewed_edit_racing_between_remote_pushes_survives(self):
        fixture = self.fixture()
        fixture.git_at(fixture.editor, "checkout", "--quiet", "browser-main")
        main = fixture.editor / "main.tex"
        draft.write(main, main.read_text(encoding="utf-8").replace(
            "\\end{document}", "UNREVIEWED CONCURRENT EDIT\n\\end{document}"))
        fixture.git_at(fixture.editor, "add", "main.tex")
        fixture.git_at(fixture.editor, "commit", "--quiet", "-m", "Stage a concurrent advisor edit")
        raced = fixture.git_at(fixture.editor, "rev-parse", "HEAD").strip()
        fixture.git_at(fixture.editor, "push", "--quiet", fixture.direct,
                       "HEAD:refs/heads/isolated-race-staging")
        hook = fixture.origin / "hooks/pre-receive"
        draft.write(hook, """#!/bin/sh
unset GIT_DIR GIT_WORK_TREE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_QUARANTINE_PATH
git --git-dir='{remote}' update-ref refs/heads/main {raced} {expected} || exit 1
exit 0
""".format(remote=fixture.direct, raced=raced, expected=fixture.reviewed_direct))
        hook.chmod(0o700)
        output = fixture.publish_reviewed(success=False)
        self.assertNotIn("GIT_ONLY_OVERLEAF_REVIEW_DRAFT_PUBLICATION_COMPLETE", output)
        self.assertEqual(fixture.refs()[0], fixture.source)
        self.assertEqual(fixture.refs()[2], raced, output)
        preserved = fixture.command(["git", "--git-dir=" + str(fixture.direct),
                                     "show", raced + ":main.tex"])
        self.assertIn("UNREVIEWED CONCURRENT EDIT", preserved)


if __name__ == "__main__":
    unittest.main(verbosity=2)
