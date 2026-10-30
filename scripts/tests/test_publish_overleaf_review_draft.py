#!/usr/bin/env python3
"""Exercise review-draft publication against disposable file-only Git remotes.

Python 3.6 standard library only. The actual publication scripts and real LaTeX
compiler are used. No repository, commit, credential, or remote outside the
TemporaryDirectory is modified; HOME, home, and CODEX_HOME are never replaced.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = (
    "publish_overleaf_article_snapshot.sh",
    "build_overleaf_article_snapshot.sh",
    "check_overleaf_article_snapshot.sh",
    "overleaf_review_draft_status.py",
)
DRAFT_FIELDS = {
    "publication_status": "review-draft",
    "glofas_status": "historical-weighted-unit-member-refits-pending",
}
# Keep independent, exact reader-facing fixtures: importing the implementation's
# own marker list would let a weakened implementation weaken its tests as well.
NOTICES = (
    ("main.tex", "analysis", r"""\noindent\textit{[The issued-window analysis is being recomputed under the
unit-member likelihood specified below. Its numerical results and displays
in this draft remain from the earlier weighted analysis.]}"""),
    ("main.tex", "results", r"""\noindent\textit{[The following comparison is retained as the historical
weighted analysis until all six unit-member refits and their scoring checks
are complete; it is not a result of the revised likelihood.]}"""),
    ("main.tex", "table", r"""\caption{Historical weighted forecast correction at the 25 December 2022
origin, retained pending the unit-member refits."""),
    ("main.tex", "figure", r"""\caption{Streamflow data and two historical weighted quantile forecasts at
the 25 December 2022 origin, retained pending the unit-member refits."""),
    ("main.tex", "discussion", r"""\textit{[Streamflow findings will be updated after the unit-member refits.]}"""),
    ("qdesn-supplement.tex", "supplement", r"""\textit{[The following issued-window numerical summaries and displays
describe the historical weighted analysis. They will be replaced together
after the unit-member refits and their checks are complete.]}"""),
)
EXPLANATION = ("The numerical target is corrected, but the numerical summaries "
               "below are explicitly historical until the corresponding refits "
               "are complete.")


def isolated_environment():
    env = os.environ.copy()
    # Do not inherit repository redirects, credentials, or injected Git config.
    for name in list(env):
        if name.startswith("GIT_") or name in ("GH_TOKEN", "GITHUB_TOKEN", "SSH_ASKPASS"):
            env.pop(name, None)
    env.update({
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_ALLOW_PROTOCOL": "file",
        "GIT_AUTHOR_NAME": "Isolated review draft test",
        "GIT_AUTHOR_EMAIL": "review-draft-test@example.invalid",
        "GIT_COMMITTER_NAME": "Isolated review draft test",
        "GIT_COMMITTER_EMAIL": "review-draft-test@example.invalid",
        "LC_ALL": "C",
    })
    return env


def run(command, cwd, env, success=True):
    result = subprocess.run(
        [str(part) for part in command], cwd=str(cwd), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        universal_newlines=True, timeout=120,
    )
    if success and result.returncode != 0:
        raise AssertionError("Command failed: {}\n{}".format(command, result.stdout))
    if not success and result.returncode == 0:
        raise AssertionError("Command unexpectedly succeeded: {}\n{}".format(command, result.stdout))
    return result.stdout


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def documents(pending):
    if pending:
        main_body = "\n\n".join((
            NOTICES[0][2], NOTICES[1][2],
            "\\begin{table}[ht]\n\\centering\n" + NOTICES[2][2] +
            "}\n\\begin{tabular}{cc}Model & Score\\\\A & 1\\end{tabular}\n\\end{table}",
            "\\begin{figure}[ht]\n\\centering\n\\fbox{Historical fixture}\n" +
            NOTICES[3][2] + "}\n\\end{figure}",
            NOTICES[4][2],
        ))
        supplement_body = EXPLANATION + "\n\n" + NOTICES[5][2]
    else:
        main_body = "Corrected release fixture results."
        supplement_body = "Corrected release fixture supplementary results."
    template = ("\\documentclass{{article}}\n\\begin{{document}}\n"
                "\\input{{{body_file}}}\n{body}\n\n"
                "[PriceFM findings to be updated.]\n\n"
                "Fixture citation \\cite{{fixture-reference}}.\n"
                "\\bibliographystyle{{plain}}\n\\bibliography{{refs}}\n"
                "\\end{{document}}\n")
    return {
        "main.tex": template.format(body_file="tables/body.tex", body=main_body),
        "qdesn-supplement.tex": template.format(
            body_file="tables/supplement-body.tex", body=supplement_body),
    }


class Fixture:
    def __init__(self, parent, name):
        self.root = parent / name
        self.root.mkdir()
        self.env = isolated_environment()
        self.repo = self.root / "repo"
        self.origin = self.root / "origin.git"
        self.direct = self.root / "overleaf.git"
        self.sequence = 0
        for remote in (self.origin, self.direct):
            self.command(["git", "init", "--bare", "--quiet", remote], cwd=self.root)
            self.command(["git", "--git-dir=" + str(remote), "symbolic-ref", "HEAD",
                          "refs/heads/main"], cwd=self.root)
        self.init_repo(self.repo)
        for script in SCRIPTS:
            destination = self.repo / "scripts" / script
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(str(ROOT / "scripts" / script), str(destination))
            destination.chmod(destination.stat().st_mode | 0o100)
        write(self.repo / "refs.bib", """@article{fixture-reference,
  author = {Test, Publisher},
  title = {An Isolated Review Draft Fixture},
  journal = {Journal of Isolated Tests},
  year = {2026},
  volume = {1},
  pages = {1--2}
}
""")
        write(self.repo / "tables/body.tex", "Main fixture body.\n")
        write(self.repo / "tables/supplement-body.tex", "Supplement fixture body.\n")
        write(self.repo / "overleaf/article_files.txt", "\n".join((
            "main.tex", "qdesn-supplement.tex", "refs.bib", "tables/body.tex",
            "tables/supplement-body.tex", "")))
        write(self.repo / "overleaf/README.md", "# Isolated article fixture\n")
        write(self.repo / "overleaf/overleaf.gitignore", "*.aux\n*.bbl\n*.blg\n*.log\n*.pdf\n")
        write(self.repo / "application/README.md", "Excluded scientific source sentinel.\n")
        self.set_documents(False)
        self.base_source = self.commit("Create isolated release authority", push=False)
        self.git("remote", "add", "origin", self.origin)
        self.git("remote", "add", "overleaf-direct", self.direct)
        self.git("push", "--quiet", "--set-upstream", "origin", "main")
        projection = self.build(self.base_source)
        self.snapshot_repo = self.root / "seed-snapshot"
        self.init_repo(self.snapshot_repo)
        self.copy_projection(projection, self.snapshot_repo)
        self.git_at(self.snapshot_repo, "add", "--force", "--all")
        self.git_at(self.snapshot_repo, "commit", "--quiet", "-m",
                    "Publish article-only snapshot from " + self.base_source)
        self.base_snapshot = self.git_at(self.snapshot_repo, "rev-parse", "HEAD").strip()
        self.git_at(self.snapshot_repo, "push", "--quiet", self.origin,
                    "HEAD:refs/heads/overleaf/article-snapshot")
        self.git_at(self.snapshot_repo, "push", "--quiet", self.direct, "HEAD:refs/heads/main")
        self.set_documents(True)
        self.source = self.commit("Create fully disclosed historical review draft")

    def command(self, command, cwd=None, success=True):
        return run(command, cwd or self.repo, self.env, success=success)

    def git_at(self, repo, *arguments):
        return self.command(["git", "-C", repo] + list(arguments), cwd=self.root)

    def git(self, *arguments):
        return self.git_at(self.repo, *arguments)

    def init_repo(self, repo):
        self.command(["git", "init", "--quiet", repo], cwd=self.root)
        self.git_at(repo, "symbolic-ref", "HEAD", "refs/heads/main")
        self.git_at(repo, "config", "user.name", "Isolated review draft test")
        self.git_at(repo, "config", "user.email", "review-draft-test@example.invalid")
        self.git_at(repo, "config", "protocol.file.allow", "always")
        self.git_at(repo, "config", "commit.gpgSign", "false")

    def set_documents(self, pending):
        for name, text in documents(pending).items():
            write(self.repo / name, text)

    def commit(self, message, push=True):
        self.git("add", "--all")
        self.git("commit", "--quiet", "-m", message)
        source = self.git("rev-parse", "HEAD").strip()
        if push:
            self.git("push", "--quiet", "origin", "main")
        return source

    def publish(self, source=None, draft=False, dry_run=False, success=True):
        arguments = [self.repo / "scripts" / SCRIPTS[0], "--source-commit", source or self.source]
        if draft:
            arguments.append("--review-draft")
        if dry_run:
            arguments.append("--dry-run")
        return self.command(arguments, success=success)

    def build(self, source):
        self.sequence += 1
        destination = self.root / ("projection-{}".format(self.sequence))
        self.command([self.repo / "scripts" / SCRIPTS[1], source, destination])
        return destination

    def check(self, directory, source, success=True):
        return self.command([self.repo / "scripts" / SCRIPTS[2], directory, source], success=success)

    def status(self, source=None, draft=False, success=True):
        arguments = ["python3", self.repo / "scripts" / SCRIPTS[3], source or self.source,
                     "--require-authorization"]
        if draft:
            arguments.append("--review-draft")
        return self.command(arguments, success=success)

    def refs(self):
        return (
            self.command(["git", "--git-dir=" + str(self.origin), "rev-parse",
                          "refs/heads/main"]).strip(),
            self.command(["git", "--git-dir=" + str(self.origin), "rev-parse",
                          "refs/heads/overleaf/article-snapshot"]).strip(),
            self.command(["git", "--git-dir=" + str(self.direct), "rev-parse",
                          "refs/heads/main"]).strip(),
        )

    def marker(self, remote, commit):
        return self.command(["git", "--git-dir=" + str(remote), "show",
                             commit + ":SOURCE_AUTHORITY.txt"])

    def copy_projection(self, source, destination):
        # Both paths are owned children of this TemporaryDirectory fixture.
        assert self.root.resolve() in destination.resolve().parents
        for child in destination.iterdir():
            if child.name == ".git":
                continue
            if child.is_dir() and not child.is_symlink():
                shutil.rmtree(str(child))
            else:
                child.unlink()
        for child in source.iterdir():
            target = destination / child.name
            if child.is_dir():
                shutil.copytree(str(child), str(target))
            else:
                shutil.copy2(str(child), str(target))

    def origin_only_snapshot(self, corrupt_metadata=False):
        projection = self.build(self.source)
        if corrupt_metadata:
            marker = projection / "SOURCE_AUTHORITY.txt"
            content = marker.read_text(encoding="utf-8")
            for key, value in DRAFT_FIELDS.items():
                content = content.replace("{}={}\n".format(key, value), "")
            write(marker, content)
        clone = self.root / "origin-only-snapshot"
        self.command(["git", "clone", "--quiet", "--branch", "overleaf/article-snapshot",
                      self.origin, clone], cwd=self.root)
        self.copy_projection(projection, clone)
        self.git_at(clone, "add", "--force", "--all")
        self.git_at(clone, "commit", "--quiet", "-m",
                    "Publish article-only snapshot from " + self.source)
        commit = self.git_at(clone, "rev-parse", "HEAD").strip()
        self.git_at(clone, "push", "--quiet", "origin",
                    "HEAD:refs/heads/overleaf/article-snapshot")
        return commit


class ReviewDraftPublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="qdesn-review-draft-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def fixture(self, name="fixture"):
        return Fixture(self.root, name)

    def assert_draft_marker(self, marker, source):
        self.assertIn("source_commit=" + source + "\n", marker)
        for key, value in DRAFT_FIELDS.items():
            self.assertEqual(marker.count(key + "="), 1)
            self.assertIn(key + "=" + value + "\n", marker)

    def assert_rejected_without_ref_movement(self, fixture, draft, contains, source=None):
        before = fixture.refs()
        output = fixture.publish(source=source, draft=draft, success=False)
        self.assertIn(contains, output)
        self.assertEqual(before, fixture.refs())
        return output

    def test_flagged_draft_dry_run_success_and_idempotence(self):
        fixture = self.fixture()
        before = fixture.refs()
        dry_run = fixture.publish(draft=True, dry_run=True)
        self.assertIn("GIT_ONLY_OVERLEAF_PUBLICATION_DRY_RUN_COMPLETE", dry_run)
        self.assertIn("publication_status=review-draft", dry_run)
        self.assertEqual(before, fixture.refs())
        published = fixture.publish(draft=True)
        self.assertIn("GIT_ONLY_OVERLEAF_REVIEW_DRAFT_PUBLICATION_COMPLETE", published)
        refs = fixture.refs()
        self.assertEqual(refs[0], fixture.source)
        self.assertEqual(refs[1], refs[2])
        self.assertNotEqual(refs[1], before[1])
        self.assert_draft_marker(fixture.marker(fixture.origin, refs[1]), fixture.source)
        names = fixture.command(["git", "--git-dir=" + str(fixture.origin), "ls-tree",
                                 "-r", "--name-only", refs[1]]).splitlines()
        self.assertFalse(any(name.startswith(("application/", "scripts/", "docs/")) for name in names))
        article = fixture.command(["git", "--git-dir=" + str(fixture.origin), "show",
                                   refs[1] + ":main.tex"])
        self.assertIn("[PriceFM findings to be updated.]", article)
        self.assertIn("it is not a result of the revised likelihood.", article)
        repeated = fixture.publish(draft=True)
        self.assertIn("publication_action=noop", repeated)
        self.assertEqual(refs, fixture.refs())

    def test_absent_flag_rejects_pending_source_even_for_dry_run(self):
        fixture = self.fixture()
        self.assert_rejected_without_ref_movement(fixture, False, "GLOFAS_CORRECTION_PENDING")
        before = fixture.refs()
        self.assertIn("GLOFAS_CORRECTION_PENDING",
                      fixture.publish(dry_run=True, success=False))
        self.assertEqual(before, fixture.refs())

    def test_each_notice_removed_or_commented_fails_closed(self):
        for index, (name, label, notice) in enumerate(NOTICES):
            for mutation in ("removed", "commented"):
                with self.subTest(notice=label, mutation=mutation):
                    fixture = self.fixture("notice-{}-{}".format(index, mutation))
                    original = (fixture.repo / name).read_text(encoding="utf-8")
                    self.assertEqual(original.count(notice), 1)
                    replacement = ("\n" if mutation == "removed" else
                                   "\n".join("% " + line for line in notice.splitlines()))
                    write(fixture.repo / name, original.replace(notice, replacement))
                    fixture.source = fixture.commit("Ablate {} notice: {}".format(label, mutation))
                    self.assert_rejected_without_ref_movement(
                        fixture, True, "REVIEW_DRAFT_NOTICE_INVALID")

    def test_all_notices_as_comments_do_not_authorize_a_pending_source(self):
        fixture = self.fixture()
        for name, label, notice in NOTICES:
            original = (fixture.repo / name).read_text(encoding="utf-8")
            write(fixture.repo / name, original.replace(
                notice, "\n".join("% " + line for line in notice.splitlines())))
        fixture.source = fixture.commit("Comment out all six historical disclosures")
        self.assert_rejected_without_ref_movement(fixture, True, "REVIEW_DRAFT_NOTICE_INVALID")

    def test_flag_cannot_bypass_dirty_worktree_or_change_committed_status(self):
        fixture = self.fixture()
        fixture.set_documents(False)
        self.assertEqual("review-draft", fixture.status(draft=True).strip())
        self.assert_rejected_without_ref_movement(fixture, True, "DIRTY_WORKTREE")
        fixture.set_documents(True)
        original = (fixture.repo / "main.tex").read_text(encoding="utf-8")
        write(fixture.repo / "main.tex", original.replace(NOTICES[0][2], ""))
        fixture.source = fixture.commit("Commit a missing historical intro notice")
        fixture.set_documents(True)
        self.assertIn("REVIEW_DRAFT_NOTICE_INVALID", fixture.status(draft=True, success=False))

    def test_hidden_conditional_and_preamble_notices_fail_closed(self):
        for mutation in ("conditional", "preamble"):
            with self.subTest(mutation=mutation):
                fixture = self.fixture(mutation)
                original = (fixture.repo / "main.tex").read_text(encoding="utf-8")
                notice = NOTICES[0][2]
                if mutation == "conditional":
                    changed = original.replace(notice, "\\iffalse\n" + notice + "\n\\fi")
                    expected = "hidden or conditional document text"
                else:
                    changed = original.replace(notice, "").replace(
                        "\\begin{document}", notice + "\n\\begin{document}")
                    expected = "REVIEW_DRAFT_NOTICE_INVALID"
                write(fixture.repo / "main.tex", changed)
                fixture.source = fixture.commit("Hide intro disclosure in " + mutation)
                self.assert_rejected_without_ref_movement(fixture, True, expected)

    def test_each_notice_hidden_in_unused_macro_fails_closed(self):
        for index, (name, label, notice) in enumerate(NOTICES):
            with self.subTest(notice=label):
                fixture = self.fixture("hidden-macro-{}".format(index))
                original = (fixture.repo / name).read_text(encoding="utf-8")
                hidden = "\\newcommand{\\UnusedHistoricalNotice}{" + notice + "}"
                write(fixture.repo / name, original.replace(notice, hidden))
                fixture.source = fixture.commit("Hide {} notice in unused macro".format(label))
                self.assert_rejected_without_ref_movement(
                    fixture, True, "REVIEW_DRAFT_NOTICE_INVALID")

    def test_checker_rejects_each_draft_metadata_tampering(self):
        fixture = self.fixture()
        projection = fixture.build(fixture.source)
        self.assertIn("OVERLEAF_ARTICLE_SNAPSHOT_CHECK=PASS", fixture.check(projection, fixture.source))
        marker = projection / "SOURCE_AUTHORITY.txt"
        original = marker.read_text(encoding="utf-8")
        self.assert_draft_marker(original, fixture.source)
        for key, value in DRAFT_FIELDS.items():
            for mutation in ("removed", "replaced", "duplicated"):
                with self.subTest(field=key, mutation=mutation):
                    line = "{}={}\n".format(key, value)
                    if mutation == "removed":
                        changed = original.replace(line, "")
                    elif mutation == "replaced":
                        changed = original.replace(line, key + "=approved-corrected-results\n")
                    else:
                        changed = original + line
                    write(marker, changed)
                    self.assertIn("OVERLEAF_SNAPSHOT_CHECK_ERROR",
                                  fixture.check(projection, fixture.source, success=False))
        write(marker, original)

    def test_origin_only_draft_recovery_requires_flag_and_honors_dry_run(self):
        fixture = self.fixture()
        recovery = fixture.origin_only_snapshot()
        before = fixture.refs()
        self.assertEqual(before[1], recovery)
        self.assertEqual(before[2], fixture.base_snapshot)
        self.assert_rejected_without_ref_movement(fixture, False, "GLOFAS_CORRECTION_PENDING")
        output = fixture.publish(draft=True, dry_run=True)
        self.assertIn("GIT_ONLY_OVERLEAF_PUBLICATION_DRY_RUN_RECOVERY_REQUIRED", output)
        self.assertEqual(before, fixture.refs())
        fixture.publish(draft=True)
        self.assertEqual((fixture.source, recovery, recovery), fixture.refs())
        self.assert_draft_marker(fixture.marker(fixture.direct, recovery), fixture.source)

    def test_corrected_current_source_does_not_bypass_draft_recovery_authorization(self):
        fixture = self.fixture()
        historical_source = fixture.source
        historical_snapshot = fixture.origin_only_snapshot()
        fixture.set_documents(False)
        fixture.source = fixture.commit("Complete corrected release source")
        before = fixture.refs()
        self.assert_rejected_without_ref_movement(fixture, False, "GLOFAS_CORRECTION_PENDING")
        self.assertEqual(before[1], historical_snapshot)
        self.assert_draft_marker(fixture.marker(fixture.origin, historical_snapshot), historical_source)
        output = fixture.publish(draft=True)
        self.assertIn("GIT_ONLY_OVERLEAF_PUBLICATION_COMPLETE", output)
        after = fixture.refs()
        self.assertEqual(after[0], fixture.source)
        self.assertEqual(after[1], after[2])
        self.assertNotEqual(after[1], historical_snapshot)
        marker = fixture.marker(fixture.origin, after[1])
        self.assertIn("source_commit=" + fixture.source + "\n", marker)
        for key in DRAFT_FIELDS:
            self.assertNotIn(key + "=", marker)

    def test_recovery_rejects_removed_draft_metadata_without_ref_movement(self):
        fixture = self.fixture()
        fixture.origin_only_snapshot(corrupt_metadata=True)
        self.assert_rejected_without_ref_movement(
            fixture, True, "origin-ahead tree differs from its verified source projection")

    def test_divergent_refs_are_not_bypassed_by_draft_flag(self):
        fixture = self.fixture()
        fixture.origin_only_snapshot()
        direct_edit = fixture.root / "direct-edit"
        fixture.command(["git", "clone", "--quiet", "--branch", "main", fixture.direct,
                         direct_edit], cwd=fixture.root)
        write(direct_edit / "main.tex", (direct_edit / "main.tex").read_text(encoding="utf-8") +
              "\n% Unrelated direct-side edit.\n")
        fixture.git_at(direct_edit, "add", "--force", "main.tex")
        fixture.git_at(direct_edit, "commit", "--quiet", "-m", "Divergent direct fixture edit")
        fixture.git_at(direct_edit, "push", "--quiet", "origin", "HEAD:refs/heads/main")
        self.assert_rejected_without_ref_movement(fixture, True, "PUBLICATION_REF_DIVERGENCE")

    def test_stale_source_is_not_bypassed_by_draft_flag(self):
        fixture = self.fixture()
        stale = fixture.source
        write(fixture.repo / "tables/body.tex", "A newer committed fixture article body.\n")
        fixture.source = fixture.commit("Advance source main after reviewed draft")
        self.assert_rejected_without_ref_movement(
            fixture, True, "SOURCE_MAIN_MOVED", source=stale)

    def test_release_snapshot_keeps_original_marker_and_rejects_draft_metadata(self):
        fixture = self.fixture()
        projection = fixture.build(fixture.base_source)
        marker = projection / "SOURCE_AUTHORITY.txt"
        original = marker.read_text(encoding="utf-8")
        for key in DRAFT_FIELDS:
            self.assertNotIn(key + "=", original)
        self.assertIn("OVERLEAF_ARTICLE_SNAPSHOT_CHECK=PASS", fixture.check(projection, fixture.base_source))
        for key, value in DRAFT_FIELDS.items():
            with self.subTest(field=key):
                write(marker, original + "{}={}\n".format(key, value))
                self.assertIn("release source must not carry conditional review-draft metadata",
                              fixture.check(projection, fixture.base_source, success=False))


if __name__ == "__main__":
    for dependency in ("git", "flock", "pdflatex", "bibtex", "pdfinfo", "kpsewhich"):
        if shutil.which(dependency) is None:
            raise SystemExit("Missing required local test dependency: " + dependency)
    for script in SCRIPTS:
        if not (ROOT / "scripts" / script).is_file():
            raise SystemExit("Missing actual publication script: " + script)
    unittest.main(verbosity=2)
