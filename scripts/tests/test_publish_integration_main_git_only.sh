#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_TERMINAL_PROMPT=0
unset GIT_ASKPASS SSH_ASKPASS

test_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "${test_dir}/../.." && pwd)
publisher="${repo_root}/scripts/publish_integration_main_git_only.sh"
[[ -x "$publisher" ]] || {
  printf 'FAIL: publisher is not executable: %s\n' "$publisher" >&2
  exit 1
}

tmp_parent=${TMPDIR:-/tmp}
mkdir -p "$tmp_parent"
tmp_parent=$(cd "$tmp_parent" && pwd)
test_root=$(mktemp -d "${tmp_parent}/qdesn-publish-integration-main-test.XXXXXX")

cleanup() {
  [[ -n "${test_root:-}" && -d "$test_root" ]] || return 0
  [[ "$(dirname "$test_root")" == "$tmp_parent" ]] || return 0
  [[ "$(basename "$test_root")" == qdesn-publish-integration-main-test.* ]] ||
    return 0
  find "$test_root" -depth -delete
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  local actual=$1
  local expected=$2
  local label=$3
  [[ "$actual" == "$expected" ]] ||
    fail "${label}: expected ${expected}, got ${actual}"
}

assert_contains() {
  local path=$1
  local text=$2
  grep -Fq -- "$text" "$path" ||
    fail "Expected output to contain: ${text}"
}

assert_ref_absent() {
  local origin=$1
  local ref=$2
  if git --git-dir="$origin" show-ref --verify --quiet "$ref"; then
    fail "Reference should be absent: ${ref}"
  fi
}

remote_commit() {
  local origin=$1
  local ref=$2
  git --git-dir="$origin" rev-parse --verify "${ref}^{commit}"
}

configure_repository() {
  local work=$1
  git -C "$work" config user.name "Publisher Test"
  git -C "$work" config user.email publisher-test@example.invalid
  git -C "$work" config commit.gpgSign false
}

create_base_repository() {
  local name=$1

  fixture_origin="${test_root}/${name}-origin.git"
  fixture_work="${test_root}/${name}-work"
  git init -q --bare "$fixture_origin"
  git init -q "$fixture_work"
  configure_repository "$fixture_work"
  git -C "$fixture_work" checkout -q -b main
  git -C "$fixture_work" commit -q --allow-empty -m "${name}: base authority"
  fixture_base=$(git -C "$fixture_work" rev-parse HEAD)
  git -C "$fixture_work" remote add origin "$fixture_origin"
  git -C "$fixture_work" push -q -u origin main
  git --git-dir="$fixture_origin" symbolic-ref HEAD refs/heads/main
}

create_standard_fixture() {
  local name=$1

  create_base_repository "$name"
  fixture_branch="integration/${name}"
  fixture_source_branch="work/${name}-lane"
  git -C "$fixture_work" checkout -q -b "$fixture_source_branch"
  git -C "$fixture_work" commit -q --allow-empty -m "${name}: lane payload"
  fixture_source_head=$(git -C "$fixture_work" rev-parse HEAD)
  git -C "$fixture_work" push -q origin \
    "HEAD:refs/heads/${fixture_source_branch}"
  git -C "$fixture_work" checkout -q -b "$fixture_branch" "$fixture_base"
  git -C "$fixture_work" merge -q --no-ff "$fixture_source_branch" \
    -m "${name}: merge lane"
  fixture_head=$(git -C "$fixture_work" rev-parse HEAD)
}

run_expect_failure() {
  local output=$1
  shift
  if "$@" >"$output" 2>&1; then
    fail "Command unexpectedly succeeded; output: ${output}"
  fi
}

test_dry_run_and_success() {
  create_standard_fixture success
  local output_dry="${test_root}/success-dry-run.out"
  local output_live="${test_root}/success-live.out"

  (
    cd "$fixture_work"
    "$publisher" \
      --expected-main "$fixture_base" \
      --expected-head "$fixture_head" \
      --source-head "$fixture_source_head" \
      --source-branch "$fixture_source_branch" \
      --integration-branch "$fixture_branch" \
      --dry-run
  ) >"$output_dry" 2>&1

  assert_contains "$output_dry" GIT_ONLY_MAIN_PUBLICATION_DRY_RUN_PASS
  assert_equal "$(remote_commit "$fixture_origin" refs/heads/main)" \
    "$fixture_base" "dry-run main"
  assert_ref_absent "$fixture_origin" "refs/heads/${fixture_branch}"

  (
    cd "$fixture_work"
    "$publisher" \
      --expected-main "$fixture_base" \
      --expected-head "$fixture_head" \
      --source-head "$fixture_source_head" \
      --source-branch "$fixture_source_branch" \
      --integration-branch "$fixture_branch"
  ) >"$output_live" 2>&1

  assert_contains "$output_live" GIT_ONLY_MAIN_PUBLICATION_COMPLETE
  assert_equal "$(remote_commit "$fixture_origin" "refs/heads/${fixture_branch}")" \
    "$fixture_head" "published integration branch"
  assert_equal "$(remote_commit "$fixture_origin" refs/heads/main)" \
    "$fixture_head" "published main"

  local integration_line main_line
  integration_line=$(grep -n -m1 \
    "Pushing the integration branch" "$output_live" | cut -d: -f1)
  main_line=$(grep -n -m1 \
    "Publishing the tested integration HEAD" "$output_live" | cut -d: -f1)
  [[ -n "$integration_line" && -n "$main_line" ]] ||
    fail "Publication-order messages are missing."
  (( integration_line < main_line )) ||
    fail "Main was published before the integration branch."

  printf 'PASS: dry-run and successful publication\n'
}

test_stale_main() {
  create_standard_fixture stale-main
  local output="${test_root}/stale-main.out"
  local advancer="${test_root}/stale-main-advancer"

  git clone -q --branch main "$fixture_origin" "$advancer"
  configure_repository "$advancer"
  git -C "$advancer" commit -q --allow-empty -m "advance authoritative main"
  git -C "$advancer" push -q origin HEAD:main
  local advanced_main
  advanced_main=$(git -C "$advancer" rev-parse HEAD)

  run_expect_failure "$output" bash -c '
    cd "$1"
    exec "$2" --expected-main "$3" --expected-head "$4" \
      --source-head "$5" --source-branch "$6" --integration-branch "$7"
  ' _ "$fixture_work" "$publisher" "$fixture_base" "$fixture_head" \
    "$fixture_source_head" "$fixture_source_branch" "$fixture_branch"

  assert_contains "$output" "origin/main is ${advanced_main}; expected ${fixture_base}"
  assert_equal "$(remote_commit "$fixture_origin" refs/heads/main)" \
    "$advanced_main" "stale-main authority"
  assert_ref_absent "$fixture_origin" "refs/heads/${fixture_branch}"
  printf 'PASS: stale origin/main fails without movement\n'
}

test_dirty_worktree() {
  create_standard_fixture dirty-worktree
  local output="${test_root}/dirty-worktree.out"
  : >"${fixture_work}/untracked-test-file"

  run_expect_failure "$output" bash -c '
    cd "$1"
    exec "$2" --expected-main "$3" --expected-head "$4" \
      --source-head "$5" --source-branch "$6" --integration-branch "$7"
  ' _ "$fixture_work" "$publisher" "$fixture_base" "$fixture_head" \
    "$fixture_source_head" "$fixture_source_branch" "$fixture_branch"

  assert_contains "$output" "integration worktree is not clean"
  assert_equal "$(remote_commit "$fixture_origin" refs/heads/main)" \
    "$fixture_base" "dirty-worktree main"
  assert_ref_absent "$fixture_origin" "refs/heads/${fixture_branch}"
  printf 'PASS: dirty worktree fails without movement\n'
}

test_non_integration_branch() {
  create_standard_fixture non-integration
  local output="${test_root}/non-integration.out"
  local invalid_branch="topic/non-integration"
  git -C "$fixture_work" branch -m "$invalid_branch"

  run_expect_failure "$output" bash -c '
    cd "$1"
    exec "$2" --expected-main "$3" --expected-head "$4" \
      --source-head "$5" --source-branch "$6" --integration-branch "$7"
  ' _ "$fixture_work" "$publisher" "$fixture_base" "$fixture_head" \
    "$fixture_source_head" "$fixture_source_branch" "$invalid_branch"

  assert_contains "$output" "must start with integration/"
  assert_equal "$(remote_commit "$fixture_origin" refs/heads/main)" \
    "$fixture_base" "non-integration main"
  assert_ref_absent "$fixture_origin" "refs/heads/${invalid_branch}"
  printf 'PASS: non-integration branch is rejected\n'
}

test_range_without_merge_commit() {
  create_base_repository no-merge
  fixture_branch=integration/no-merge
  git -C "$fixture_work" checkout -q -b "$fixture_branch" "$fixture_base"
  git -C "$fixture_work" commit -q --allow-empty -m "ordinary non-merge commit"
  fixture_head=$(git -C "$fixture_work" rev-parse HEAD)
  fixture_source_branch=work/no-merge-lane
  fixture_source_head=$fixture_head
  git -C "$fixture_work" push -q origin \
    "HEAD:refs/heads/${fixture_source_branch}"
  local output="${test_root}/no-merge.out"

  run_expect_failure "$output" bash -c '
    cd "$1"
    exec "$2" --expected-main "$3" --expected-head "$4" \
      --source-head "$5" --source-branch "$6" --integration-branch "$7"
  ' _ "$fixture_work" "$publisher" "$fixture_base" "$fixture_head" \
    "$fixture_source_head" "$fixture_source_branch" "$fixture_branch"

  assert_contains "$output" "must be one two-parent integration merge commit"
  assert_equal "$(remote_commit "$fixture_origin" refs/heads/main)" \
    "$fixture_base" "no-merge main"
  assert_ref_absent "$fixture_origin" "refs/heads/${fixture_branch}"
  printf 'PASS: range without merge commit is rejected\n'
}

test_remote_integration_divergence() {
  create_standard_fixture integration-divergence
  local output="${test_root}/integration-divergence.out"
  local advancer="${test_root}/integration-divergence-advancer"

  git clone -q --branch main "$fixture_origin" "$advancer"
  configure_repository "$advancer"
  git -C "$advancer" checkout -q -b "$fixture_branch" "$fixture_base"
  git -C "$advancer" commit -q --allow-empty -m "divergent integration tip"
  git -C "$advancer" push -q origin "HEAD:${fixture_branch}"
  local divergent_head
  divergent_head=$(git -C "$advancer" rev-parse HEAD)

  run_expect_failure "$output" bash -c '
    cd "$1"
    exec "$2" --expected-main "$3" --expected-head "$4" \
      --source-head "$5" --source-branch "$6" --integration-branch "$7"
  ' _ "$fixture_work" "$publisher" "$fixture_base" "$fixture_head" \
    "$fixture_source_head" "$fixture_source_branch" "$fixture_branch"

  assert_contains "$output" "non-fast-forward"
  assert_equal "$(remote_commit "$fixture_origin" refs/heads/main)" \
    "$fixture_base" "integration-divergence main"
  assert_equal "$(remote_commit "$fixture_origin" "refs/heads/${fixture_branch}")" \
    "$divergent_head" "divergent integration branch"
  printf 'PASS: remote integration divergence is rejected\n'
}

test_mismatched_push_url() {
  create_standard_fixture push-url
  local output="${test_root}/push-url.out"
  local unintended="${test_root}/push-url-unintended.git"
  git init -q --bare "$unintended"
  git -C "$fixture_work" remote set-url --push origin "$unintended"

  run_expect_failure "$output" bash -c '
    cd "$1"
    exec "$2" --expected-main "$3" --expected-head "$4" \
      --source-head "$5" --source-branch "$6" --integration-branch "$7"
  ' _ "$fixture_work" "$publisher" "$fixture_base" "$fixture_head" \
    "$fixture_source_head" "$fixture_source_branch" "$fixture_branch"

  assert_contains "$output" "fetch and push URLs must be identical"
  assert_equal "$(remote_commit "$fixture_origin" refs/heads/main)" \
    "$fixture_base" "push-url main"
  assert_ref_absent "$unintended" refs/heads/main
  printf 'PASS: mismatched push URL is rejected before movement\n'
}

test_forbidden_overleaf_source_branch() {
  create_standard_fixture forbidden-overleaf-source
  local output="${test_root}/forbidden-overleaf-source.out"
  local forbidden_branch="overleaf-2026-08-29-0000"
  git -C "$fixture_work" push -q origin \
    "$fixture_source_head:refs/heads/${forbidden_branch}"

  run_expect_failure "$output" bash -c '
    cd "$1"
    exec "$2" --expected-main "$3" --expected-head "$4" \
      --source-head "$5" --source-branch "$6" --integration-branch "$7"
  ' _ "$fixture_work" "$publisher" "$fixture_base" "$fixture_head" \
    "$fixture_source_head" "$forbidden_branch" "$fixture_branch"

  assert_contains "$output" "Forbidden source branch"
  assert_equal "$(remote_commit "$fixture_origin" refs/heads/main)" \
    "$fixture_base" "forbidden-overleaf-source main"
  assert_ref_absent "$fixture_origin" "refs/heads/${fixture_branch}"
  printf 'PASS: browser-generated Overleaf source branch is rejected\n'
}

test_dry_run_and_success
test_stale_main
test_dirty_worktree
test_non_integration_branch
test_range_without_merge_commit
test_remote_integration_divergence
test_mismatched_push_url
test_forbidden_overleaf_source_branch

printf 'PUBLISH_INTEGRATION_MAIN_GIT_ONLY_TESTS_PASS 9/9\n'
