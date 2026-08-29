#!/usr/bin/env bash
set -euo pipefail

# End-to-end tests for the command-line Git-only Overleaf publisher.
#
# Every repository and remote used by this test is created below a private
# temporary directory.  In particular, this script never reads from or writes
# to the real origin or Overleaf remotes.

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
publisher="$repo_root/scripts/publish_overleaf_article_snapshot.sh"
builder="$repo_root/scripts/build_overleaf_article_snapshot.sh"
checker="$repo_root/scripts/check_overleaf_article_snapshot.sh"

for required in "$publisher" "$builder" "$checker"; do
  if [[ ! -x "$required" ]]; then
    printf 'Required executable is missing: %s\n' "$required" >&2
    exit 2
  fi
done

test_root=$(mktemp -d "${TMPDIR:-/tmp}/qdesn-overleaf-publisher-test.XXXXXX")
cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$test_root/home" "$test_root/xdg"
export HOME="$test_root/home"
export XDG_CONFIG_HOME="$test_root/xdg"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$test_root/gitconfig"
export GIT_TERMINAL_PROMPT=0
unset GIT_ASKPASS SSH_ASKPASS GITHUB_TOKEN GH_TOKEN

git config --file "$GIT_CONFIG_GLOBAL" user.name "QDESN publisher test"
git config --file "$GIT_CONFIG_GLOBAL" user.email "publisher-test@example.invalid"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" protocol.file.allow always

umask 077

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  return 1
}

assert_equal() {
  local expected=$1
  local actual=$2
  local context=$3
  [[ "$actual" == "$expected" ]] ||
    fail "$context (expected '$expected', found '$actual')"
}

assert_ref() {
  local git_dir=$1
  local ref=$2
  local expected=$3
  local actual
  actual=$(git --git-dir="$git_dir" rev-parse "$ref")
  assert_equal "$expected" "$actual" "$git_dir:$ref"
}

assert_ref_absent() {
  local git_dir=$1
  local ref=$2
  if git --git-dir="$git_dir" show-ref --verify --quiet "$ref"; then
    fail "$git_dir:$ref should be absent"
  fi
}

expect_publish_success() {
  local fixture=$1
  shift
  local log="$fixture/publisher-success.log"
  if ! (
    cd "$fixture/repo"
    scripts/publish_overleaf_article_snapshot.sh "$@"
  ) >"$log" 2>&1; then
    sed -n '1,240p' "$log" >&2
    fail "publisher unexpectedly failed"
  fi
}

expect_publish_failure() {
  local fixture=$1
  shift
  local log="$fixture/publisher-expected-failure.log"
  if (
    cd "$fixture/repo"
    scripts/publish_overleaf_article_snapshot.sh "$@"
  ) >"$log" 2>&1; then
    sed -n '1,240p' "$log" >&2
    fail "publisher unexpectedly succeeded"
  fi
}

copy_projection() {
  local source_dir=$1
  local destination=$2

  find "$destination" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf -- {} +
  cp -a "$source_dir"/. "$destination"/
}

build_projection() {
  local fixture=$1
  local source_commit=$2
  local destination=$3

  mkdir -p "$destination"
  (
    cd "$fixture/repo"
    scripts/build_overleaf_article_snapshot.sh "$source_commit" "$destination"
  ) >"$fixture/builder.log" 2>&1
}

seed_snapshot_remotes() {
  local fixture=$1
  local source_commit=$2
  local projection="$fixture/baseline-projection"
  local snapshot_repo="$fixture/baseline-snapshot-repo"

  build_projection "$fixture" "$source_commit" "$projection"
  git init -q -b snapshot "$snapshot_repo"
  copy_projection "$projection" "$snapshot_repo"
  git -C "$snapshot_repo" add --force --all
  git -C "$snapshot_repo" commit -q \
    -m "Publish article-only snapshot from $source_commit"
  git -C "$snapshot_repo" remote add origin "$fixture/origin.git"
  git -C "$snapshot_repo" remote add overleaf-direct "$fixture/overleaf.git"
  git -C "$snapshot_repo" push -q origin HEAD:refs/heads/overleaf/article-snapshot
  git -C "$snapshot_repo" push -q overleaf-direct HEAD:refs/heads/main

  FIXTURE_BASE_SNAPSHOT=$(git -C "$snapshot_repo" rev-parse HEAD)
}

new_fixture() {
  local name=$1
  local fixture="$test_root/$name"
  local repo="$fixture/repo"

  mkdir -p "$fixture"
  git init -q --bare "$fixture/origin.git"
  git init -q --bare "$fixture/overleaf.git"
  git init -q -b main "$repo"
  git --git-dir="$fixture/origin.git" symbolic-ref HEAD refs/heads/main
  git --git-dir="$fixture/overleaf.git" symbolic-ref HEAD refs/heads/main

  mkdir -p \
    "$repo/application" \
    "$repo/overleaf" \
    "$repo/scripts" \
    "$repo/tables"
  cp "$publisher" "$repo/scripts/publish_overleaf_article_snapshot.sh"
  cp "$builder" "$repo/scripts/build_overleaf_article_snapshot.sh"
  cp "$checker" "$repo/scripts/check_overleaf_article_snapshot.sh"
  chmod +x "$repo/scripts/"*.sh

  cat >"$repo/main.tex" <<'EOF'
\documentclass{article}
\begin{document}
\input{tables/body.tex}
Main citation \cite{fixture-reference}.
\bibliographystyle{plain}
\bibliography{refs}
\end{document}
EOF

  cat >"$repo/qdesn-supplement.tex" <<'EOF'
\documentclass{article}
\begin{document}
\input{tables/supplement-body.tex}
Supplement citation \cite{fixture-reference}.
\bibliographystyle{plain}
\bibliography{refs}
\end{document}
EOF

  cat >"$repo/refs.bib" <<'EOF'
@article{fixture-reference,
  author  = {Test, Publisher},
  title   = {A Local Publication Fixture},
  journal = {Journal of Isolated Tests},
  year    = {2026},
  volume  = {1},
  pages   = {1--2}
}
EOF

  cat >"$repo/tables/body.tex" <<'EOF'
This is the main article body from the manifest.
EOF
  cat >"$repo/tables/supplement-body.tex" <<'EOF'
This is the supplementary body from the manifest.
EOF

  cat >"$repo/overleaf/article_files.txt" <<'EOF'
# Minimal sorted fixture manifest.
main.tex
qdesn-supplement.tex
refs.bib
tables/body.tex
tables/supplement-body.tex
EOF

  cat >"$repo/overleaf/README.md" <<'EOF'
# Fixture article snapshot

This fixture is published only through command-line Git.
EOF

  cat >"$repo/overleaf/overleaf.gitignore" <<'EOF'
/application/
/scripts/
/overleaf/
/tables/*
/*.tex
*.aux
*.bbl
*.blg
*.fls
*.log
*.out
/*.pdf
EOF

  cat >"$repo/application/README.md" <<'EOF'
Full-repository sentinel excluded from the article snapshot.
EOF
  cat >"$repo/README.md" <<'EOF'
# Full fixture repository
EOF

  git -C "$repo" add --all
  git -C "$repo" commit -q -m "Create publisher fixture authority"
  git -C "$repo" remote add origin "$fixture/origin.git"
  git -C "$repo" remote add overleaf-direct "$fixture/overleaf.git"
  git -C "$repo" push -q -u origin main

  FIXTURE_BASE_SOURCE=$(git -C "$repo" rev-parse HEAD)
  seed_snapshot_remotes "$fixture" "$FIXTURE_BASE_SOURCE"

  printf '\nSource revision one.\n' >>"$repo/tables/body.tex"
  git -C "$repo" add tables/body.tex
  git -C "$repo" commit -q -m "Revise fixture article"
  git -C "$repo" push -q origin main

  FIXTURE_DIR=$fixture
  FIXTURE_REPO=$repo
  FIXTURE_SOURCE=$(git -C "$repo" rev-parse HEAD)
}

commit_manifest() {
  local fixture=$1
  local message=$2
  local content=$3
  printf '%s' "$content" >"$fixture/repo/overleaf/article_files.txt"
  git -C "$fixture/repo" add overleaf/article_files.txt
  git -C "$fixture/repo" commit -q -m "$message"
  git -C "$fixture/repo" push -q origin main
  FIXTURE_SOURCE=$(git -C "$fixture/repo" rev-parse HEAD)
}

assert_publication_marker() {
  local fixture=$1
  local snapshot_ref=$2
  local source_commit=$3
  local marker

  git --git-dir="$fixture/origin.git" cat-file -e \
    "$snapshot_ref:SOURCE_AUTHORITY.txt"
  marker=$(git --git-dir="$fixture/origin.git" show \
    "$snapshot_ref:SOURCE_AUTHORITY.txt")
  grep -Fq "$source_commit" <<<"$marker" ||
    fail "SOURCE_AUTHORITY.txt does not identify $source_commit"
}

make_direct_edit() {
  local fixture=$1
  local edit_repo="$fixture/direct-edit"

  git clone -q --branch main "$fixture/overleaf.git" "$edit_repo"
  printf '\nDirect browser-side edit.\n' >>"$edit_repo/main.tex"
  git -C "$edit_repo" add --force main.tex
  git -C "$edit_repo" commit -q -m "Create divergent direct edit"
  git -C "$edit_repo" push -q origin main
}

create_origin_only_snapshot() {
  local fixture=$1
  local source_commit=$2
  local projection="$fixture/origin-only-projection"
  local snapshot_repo="$fixture/origin-only-snapshot-repo"

  build_projection "$fixture" "$source_commit" "$projection"
  git clone -q "$fixture/origin.git" "$snapshot_repo"
  git -C "$snapshot_repo" switch -q --track \
    origin/overleaf/article-snapshot
  copy_projection "$projection" "$snapshot_repo"
  git -C "$snapshot_repo" add --force --all
  git -C "$snapshot_repo" commit -q \
    -m "Publish article-only snapshot from $source_commit"
  git -C "$snapshot_repo" push -q origin HEAD:refs/heads/overleaf/article-snapshot
  FIXTURE_ORIGIN_ONLY_SNAPSHOT=$(git -C "$snapshot_repo" rev-parse HEAD)
}

test_success_and_idempotence() {
  new_fixture success
  local fixture=$FIXTURE_DIR
  local source_commit=$FIXTURE_SOURCE
  local old_snapshot=$FIXTURE_BASE_SNAPSHOT

  expect_publish_success "$fixture" --source-commit "$source_commit" --dry-run
  assert_ref "$fixture/origin.git" refs/heads/overleaf/article-snapshot "$old_snapshot"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$old_snapshot"

  expect_publish_success "$fixture" --source-commit "$source_commit"
  local published
  published=$(git --git-dir="$fixture/origin.git" rev-parse \
    refs/heads/overleaf/article-snapshot)
  [[ "$published" != "$old_snapshot" ]] ||
    fail "successful publication did not advance the snapshot"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$published"
  assert_publication_marker "$fixture" \
    refs/heads/overleaf/article-snapshot "$source_commit"
  git --git-dir="$fixture/origin.git" cat-file -e \
    "$published^{tree}"

  expect_publish_success "$fixture" --source-commit "$source_commit"
  assert_ref "$fixture/origin.git" refs/heads/overleaf/article-snapshot "$published"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$published"
}

test_divergent_refs_fail_closed() {
  new_fixture divergent
  local fixture=$FIXTURE_DIR
  local source_commit=$FIXTURE_SOURCE
  make_direct_edit "$fixture"
  local origin_before direct_before
  origin_before=$(git --git-dir="$fixture/origin.git" rev-parse \
    refs/heads/overleaf/article-snapshot)
  direct_before=$(git --git-dir="$fixture/overleaf.git" rev-parse refs/heads/main)

  expect_publish_failure "$fixture" --source-commit "$source_commit"
  assert_ref "$fixture/origin.git" refs/heads/overleaf/article-snapshot "$origin_before"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$direct_before"
}

test_stale_source_fails_closed() {
  new_fixture stale-source
  local fixture=$FIXTURE_DIR
  local snapshot_before=$FIXTURE_BASE_SNAPSHOT

  expect_publish_failure "$fixture" --source-commit "$FIXTURE_BASE_SOURCE"
  assert_ref "$fixture/origin.git" refs/heads/overleaf/article-snapshot "$snapshot_before"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$snapshot_before"
}

test_unsafe_manifest_fails_closed() {
  new_fixture unsafe-manifest
  local fixture=$FIXTURE_DIR
  local snapshot_before=$FIXTURE_BASE_SNAPSHOT
  commit_manifest "$fixture" "Add unsafe manifest entry" $'../outside.tex\nmain.tex\nqdesn-supplement.tex\nrefs.bib\ntables/body.tex\ntables/supplement-body.tex\n'

  expect_publish_failure "$fixture" --source-commit "$FIXTURE_SOURCE"
  assert_ref "$fixture/origin.git" refs/heads/overleaf/article-snapshot "$snapshot_before"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$snapshot_before"
}

test_duplicate_manifest_fails_closed() {
  new_fixture duplicate-manifest
  local fixture=$FIXTURE_DIR
  local snapshot_before=$FIXTURE_BASE_SNAPSHOT
  commit_manifest "$fixture" "Duplicate manifest entry" $'main.tex\nmain.tex\nqdesn-supplement.tex\nrefs.bib\ntables/body.tex\ntables/supplement-body.tex\n'

  expect_publish_failure "$fixture" --source-commit "$FIXTURE_SOURCE"
  assert_ref "$fixture/origin.git" refs/heads/overleaf/article-snapshot "$snapshot_before"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$snapshot_before"
}

test_unsorted_manifest_fails_closed() {
  new_fixture unsorted-manifest
  local fixture=$FIXTURE_DIR
  local snapshot_before=$FIXTURE_BASE_SNAPSHOT
  commit_manifest "$fixture" "Unsort manifest entries" $'qdesn-supplement.tex\nmain.tex\nrefs.bib\ntables/body.tex\ntables/supplement-body.tex\n'

  expect_publish_failure "$fixture" --source-commit "$FIXTURE_SOURCE"
  assert_ref "$fixture/origin.git" refs/heads/overleaf/article-snapshot "$snapshot_before"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$snapshot_before"
}

test_omitted_tex_dependency_fails_closed() {
  new_fixture omitted-dependency
  local fixture=$FIXTURE_DIR
  local snapshot_before=$FIXTURE_BASE_SNAPSHOT
  commit_manifest "$fixture" "Omit active TeX dependency" $'main.tex\nqdesn-supplement.tex\nrefs.bib\ntables/supplement-body.tex\n'

  expect_publish_failure "$fixture" --source-commit "$FIXTURE_SOURCE"
  assert_ref "$fixture/origin.git" refs/heads/overleaf/article-snapshot "$snapshot_before"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$snapshot_before"
}

test_unavailable_direct_remote_fails_before_movement() {
  new_fixture unavailable-direct
  local fixture=$FIXTURE_DIR
  local source_commit=$FIXTURE_SOURCE
  local snapshot_before=$FIXTURE_BASE_SNAPSHOT
  local direct_before=$FIXTURE_BASE_SNAPSHOT

  git -C "$fixture/repo" remote set-url overleaf-direct \
    "$fixture/does-not-exist.git"
  expect_publish_failure "$fixture" --source-commit "$source_commit"
  assert_ref "$fixture/origin.git" refs/heads/overleaf/article-snapshot "$snapshot_before"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$direct_before"
}

test_mismatched_direct_push_url_fails_before_movement() {
  new_fixture mismatched-direct-push-url
  local fixture=$FIXTURE_DIR
  local source_commit=$FIXTURE_SOURCE
  local snapshot_before=$FIXTURE_BASE_SNAPSHOT
  local unintended="$fixture/unintended-overleaf.git"

  git init -q --bare "$unintended"
  git -C "$fixture/repo" remote set-url --push overleaf-direct "$unintended"
  expect_publish_failure "$fixture" --source-commit "$source_commit"
  grep -Fq "fetch and push URLs must be identical" \
    "$fixture/publisher-expected-failure.log" ||
    fail "mismatched direct push URL was not classified correctly"
  assert_ref "$fixture/origin.git" refs/heads/overleaf/article-snapshot "$snapshot_before"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$snapshot_before"
  assert_ref_absent "$unintended" refs/heads/main
}

test_local_head_mismatch_fails_closed() {
  new_fixture local-head-mismatch
  local fixture=$FIXTURE_DIR
  local source_commit=$FIXTURE_SOURCE
  local snapshot_before=$FIXTURE_BASE_SNAPSHOT

  git -C "$fixture/repo" checkout -q --detach "$FIXTURE_BASE_SOURCE"
  expect_publish_failure "$fixture" --source-commit "$source_commit"
  grep -Fq "LOCAL_HEAD_MISMATCH" "$fixture/publisher-expected-failure.log" ||
    fail "local source-policy mismatch was not classified correctly"
  assert_ref "$fixture/origin.git" refs/heads/overleaf/article-snapshot "$snapshot_before"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$snapshot_before"
}

test_external_absolute_tex_dependency_fails_closed() {
  new_fixture external-tex-dependency
  local fixture=$FIXTURE_DIR
  local snapshot_before=$FIXTURE_BASE_SNAPSHOT
  local external_file="$fixture/external-fragment.tex"

  printf 'Undeclared external fragment.\n' >"$external_file"
  sed -i "/\\\\end{document}/i\\\\input{$external_file}" \
    "$fixture/repo/main.tex"
  git -C "$fixture/repo" add main.tex
  git -C "$fixture/repo" commit -q -m "Add forbidden absolute TeX dependency"
  git -C "$fixture/repo" push -q origin main
  local source_commit
  source_commit=$(git -C "$fixture/repo" rev-parse HEAD)

  expect_publish_failure "$fixture" --source-commit "$source_commit"
  assert_ref "$fixture/origin.git" refs/heads/overleaf/article-snapshot "$snapshot_before"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$snapshot_before"
}

test_identical_tree_direct_ahead_fails_closed() {
  new_fixture identical-tree-direct-ahead
  local fixture=$FIXTURE_DIR
  local source_commit=$FIXTURE_SOURCE
  local origin_before=$FIXTURE_BASE_SNAPSHOT
  local edit_repo="$fixture/identical-tree-direct-edit"

  git clone -q --branch main "$fixture/overleaf.git" "$edit_repo"
  git -C "$edit_repo" commit -q --allow-empty \
    -m "Browser-created identical-tree commit"
  git -C "$edit_repo" push -q origin main
  local direct_before
  direct_before=$(git -C "$edit_repo" rev-parse HEAD)

  expect_publish_failure "$fixture" --source-commit "$source_commit"
  grep -Fq "DIRECT_OVERLEAF_AHEAD" "$fixture/publisher-expected-failure.log" ||
    fail "identical-tree direct-ahead state was not rejected"
  assert_ref "$fixture/origin.git" refs/heads/overleaf/article-snapshot "$origin_before"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$direct_before"
}

test_source_advance_after_snapshot_keeps_refs_equal() {
  new_fixture source-advance-after-snapshot
  local fixture=$FIXTURE_DIR
  local source_commit=$FIXTURE_SOURCE
  local snapshot_before=$FIXTURE_BASE_SNAPSHOT
  local hook="$fixture/origin.git/hooks/post-receive"

  cat >"$hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
git_dir="$fixture/origin.git"
old_main=\$(git --git-dir="\$git_dir" rev-parse refs/heads/main)
main_tree=\$(git --git-dir="\$git_dir" rev-parse "\${old_main}^{tree}")
export GIT_AUTHOR_NAME="Concurrent integration test"
export GIT_AUTHOR_EMAIL="concurrent@example.invalid"
export GIT_COMMITTER_NAME="Concurrent integration test"
export GIT_COMMITTER_EMAIL="concurrent@example.invalid"
new_main=\$(printf 'main advanced after snapshot\n' | \
  git --git-dir="\$git_dir" commit-tree "\$main_tree" -p "\$old_main")
git --git-dir="\$git_dir" update-ref refs/heads/main "\$new_main" "\$old_main"
rm -f -- "$hook"
EOF
  chmod +x "$hook"

  expect_publish_failure "$fixture" --source-commit "$source_commit"
  grep -Fq "SOURCE_MAIN_ADVANCED_AFTER_SYNCHRONIZED_PUBLICATION" \
    "$fixture/publisher-expected-failure.log" ||
    fail "concurrent source advance was not classified correctly"
  if grep -Fq "GIT_ONLY_OVERLEAF_PUBLICATION_COMPLETE" \
      "$fixture/publisher-expected-failure.log"; then
    fail "publisher reported completion after source main advanced"
  fi

  local origin_snapshot direct_snapshot advanced_main
  origin_snapshot=$(git --git-dir="$fixture/origin.git" rev-parse \
    refs/heads/overleaf/article-snapshot)
  direct_snapshot=$(git --git-dir="$fixture/overleaf.git" rev-parse refs/heads/main)
  advanced_main=$(git --git-dir="$fixture/origin.git" rev-parse refs/heads/main)
  [[ "$origin_snapshot" != "$snapshot_before" ]] ||
    fail "snapshot did not advance in the concurrent-main test"
  assert_equal "$origin_snapshot" "$direct_snapshot" \
    "publication refs after concurrent main advance"
  [[ "$advanced_main" != "$source_commit" ]] ||
    fail "origin/main did not advance in the synthetic race"
  assert_publication_marker "$fixture" \
    refs/heads/overleaf/article-snapshot "$source_commit"
}

test_global_git_hook_cannot_mutate_snapshot() {
  new_fixture hostile-global-hook
  local fixture=$FIXTURE_DIR
  local source_commit=$FIXTURE_SOURCE
  local hooks="$fixture/hostile-hooks"
  mkdir -p "$hooks"
  cat >"$hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
printf 'hostile global hook output\n' > HOSTILE_GLOBAL_HOOK.txt
git add --force HOSTILE_GLOBAL_HOOK.txt
EOF
  chmod +x "$hooks/pre-commit"
  git config --global core.hooksPath "$hooks"

  expect_publish_success "$fixture" --source-commit "$source_commit"
  git config --global --unset core.hooksPath

  local published
  published=$(git --git-dir="$fixture/origin.git" rev-parse \
    refs/heads/overleaf/article-snapshot)
  if git --git-dir="$fixture/origin.git" cat-file -e \
      "$published:HOSTILE_GLOBAL_HOOK.txt" 2>/dev/null; then
    fail "global pre-commit hook changed the verified snapshot tree"
  fi
  assert_ref "$fixture/overleaf.git" refs/heads/main "$published"
}

test_readback_mismatch_never_reports_success() {
  new_fixture readback-mismatch
  local fixture=$FIXTURE_DIR
  local source_commit=$FIXTURE_SOURCE
  local old_snapshot=$FIXTURE_BASE_SNAPSHOT
  local hook=$fixture/overleaf.git/hooks/post-receive

  cat >"$hook" <<EOF
#!/usr/bin/env bash
git --git-dir="$fixture/overleaf.git" update-ref refs/heads/main "$old_snapshot"
EOF
  chmod +x "$hook"

  expect_publish_failure "$fixture" --source-commit "$source_commit"
  grep -Fq "FINAL_OVERLEAF_READBACK_MISMATCH" \
    "$fixture/publisher-expected-failure.log" ||
    fail "publisher did not identify the synthetic read-back mismatch"

  local origin_ahead
  origin_ahead=$(git --git-dir="$fixture/origin.git" rev-parse \
    refs/heads/overleaf/article-snapshot)
  [[ "$origin_ahead" != "$old_snapshot" ]] ||
    fail "synthetic mismatch did not leave the expected resumable state"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$old_snapshot"

  rm -f "$hook"
  expect_publish_success "$fixture" --source-commit "$source_commit"
  assert_ref "$fixture/origin.git" refs/heads/overleaf/article-snapshot \
    "$origin_ahead"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$origin_ahead"
}

test_origin_ahead_one_sided_recovery() {
  new_fixture one-sided-recovery
  local fixture=$FIXTURE_DIR
  local source_one=$FIXTURE_SOURCE

  expect_publish_success "$fixture" --source-commit "$source_one"
  local shared_before
  shared_before=$(git --git-dir="$fixture/origin.git" rev-parse \
    refs/heads/overleaf/article-snapshot)
  assert_ref "$fixture/overleaf.git" refs/heads/main "$shared_before"

  printf '\nSource revision two.\n' >>"$fixture/repo/tables/body.tex"
  git -C "$fixture/repo" add tables/body.tex
  git -C "$fixture/repo" commit -q -m "Revise fixture article again"
  git -C "$fixture/repo" push -q origin main
  local source_two
  source_two=$(git -C "$fixture/repo" rev-parse HEAD)

  create_origin_only_snapshot "$fixture" "$source_two"
  local recovery_target=$FIXTURE_ORIGIN_ONLY_SNAPSHOT
  assert_ref "$fixture/origin.git" refs/heads/overleaf/article-snapshot \
    "$recovery_target"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$shared_before"

  expect_publish_success "$fixture" --source-commit "$source_two"
  assert_ref "$fixture/origin.git" refs/heads/overleaf/article-snapshot \
    "$recovery_target"
  assert_ref "$fixture/overleaf.git" refs/heads/main "$recovery_target"
  assert_publication_marker "$fixture" \
    refs/heads/overleaf/article-snapshot "$source_two"
}

run_test() {
  local name=$1
  local function_name=$2
  local log="$test_root/${name}.log"
  local status

  set +e
  (
    set -euo pipefail
    "$function_name"
  ) >"$log" 2>&1
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    printf 'not ok - %s\n' "$name"
    sed -n '1,280p' "$log" >&2
    return "$status"
  fi
  printf 'ok - %s\n' "$name"
}

run_test "successful publication and idempotent no-op" \
  test_success_and_idempotence
run_test "divergent publication refs fail closed" \
  test_divergent_refs_fail_closed
run_test "stale source commit fails closed" \
  test_stale_source_fails_closed
run_test "unsafe manifest entry fails closed" \
  test_unsafe_manifest_fails_closed
run_test "duplicate manifest entry fails closed" \
  test_duplicate_manifest_fails_closed
run_test "unsorted manifest fails closed" \
  test_unsorted_manifest_fails_closed
run_test "omitted TeX dependency fails closed" \
  test_omitted_tex_dependency_fails_closed
run_test "unavailable direct remote fails before movement" \
  test_unavailable_direct_remote_fails_before_movement
run_test "mismatched direct push URL fails before movement" \
  test_mismatched_direct_push_url_fails_before_movement
run_test "local HEAD must equal the source authority" \
  test_local_head_mismatch_fails_closed
run_test "external absolute TeX dependency fails closed" \
  test_external_absolute_tex_dependency_fails_closed
run_test "identical-tree direct-ahead history fails closed" \
  test_identical_tree_direct_ahead_fails_closed
run_test "source advance after snapshot keeps publication refs equal" \
  test_source_advance_after_snapshot_keeps_refs_equal
run_test "global Git hook cannot mutate verified snapshot" \
  test_global_git_hook_cannot_mutate_snapshot
run_test "read-back mismatch fails and resumes without force" \
  test_readback_mismatch_never_reports_success
run_test "origin-ahead one-sided publication recovers" \
  test_origin_ahead_one_sided_recovery

printf 'PASS: command-line Git-only publisher fixture tests completed.\n'
