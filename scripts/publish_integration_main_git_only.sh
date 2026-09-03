#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C
export GIT_TERMINAL_PROMPT=0
unset GIT_ASKPASS SSH_ASKPASS

usage() {
  cat >&2 <<'USAGE'
Usage:
  publish_integration_main_git_only.sh \
    --expected-main <40-hex-commit> \
    --expected-head <40-hex-commit> \
    --source-head <40-hex-commit> \
    --source-branch <remote-branch> \
    --integration-branch <integration/...> \
    [--dry-run]

Publish a validated integration commit to origin/main with command-line Git.
The current worktree must be clean and checked out at the named integration
branch and expected HEAD. No force push is performed.
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '%s\n' "$*"
}

# Clear URL-specific hosting-service helpers as well as the generic helper.
# Network authentication is therefore handled only by command-line Git's
# credential cache, never by GitHub CLI or an editor integration.
git_network() {
  git \
    -c credential.helper= \
    -c 'credential.helper=cache --timeout=900' \
    -c credential.https://github.com.helper= \
    -c 'credential.https://github.com.helper=cache --timeout=900' \
    "$@"
}

require_value() {
  local option=$1
  local remaining=$2
  (( remaining >= 2 )) || die "Missing value for ${option}."
}

expected_main=
expected_head=
source_head=
source_branch=
integration_branch=
dry_run=false

while (( $# > 0 )); do
  case "$1" in
    --expected-main)
      require_value "$1" "$#"
      expected_main=$2
      shift 2
      ;;
    --expected-head)
      require_value "$1" "$#"
      expected_head=$2
      shift 2
      ;;
    --source-head)
      require_value "$1" "$#"
      source_head=$2
      shift 2
      ;;
    --source-branch)
      require_value "$1" "$#"
      source_branch=$2
      shift 2
      ;;
    --integration-branch)
      require_value "$1" "$#"
      integration_branch=$2
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      die "Unknown argument: $1"
      ;;
  esac
done

[[ "$expected_main" =~ ^[0-9a-f]{40}$ ]] ||
  die "--expected-main must be a lowercase 40-hex commit ID."
[[ "$expected_head" =~ ^[0-9a-f]{40}$ ]] ||
  die "--expected-head must be a lowercase 40-hex commit ID."
[[ "$source_head" =~ ^[0-9a-f]{40}$ ]] ||
  die "--source-head must be a lowercase 40-hex commit ID."
command -v git >/dev/null 2>&1 || die "git is required."
command -v flock >/dev/null 2>&1 || die "flock is required."

[[ -n "$integration_branch" ]] || die "--integration-branch is required."
[[ "$integration_branch" == integration/* ]] ||
  die "The integration branch must start with integration/."
git check-ref-format --branch "$integration_branch" >/dev/null 2>&1 ||
  die "Invalid integration branch name: ${integration_branch}"
[[ -n "$source_branch" ]] || die "--source-branch is required."
git check-ref-format --branch "$source_branch" >/dev/null 2>&1 ||
  die "Invalid source branch name: ${source_branch}"
case "$source_branch" in
  main|integration/*|overleaf/*|overleaf-*|*/overleaf-*|*github-sync*)
    die "Forbidden source branch for scientific integration: ${source_branch}"
    ;;
esac

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) ||
  die "Run this command from a Git worktree."
cd "$repo_root"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  die "The current directory is not a Git worktree."

current_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) ||
  die "Detached HEAD is not permitted."
[[ "$current_branch" == "$integration_branch" ]] ||
  die "Current branch ${current_branch} does not equal ${integration_branch}."

current_head=$(git rev-parse --verify HEAD^{commit})
[[ "$current_head" == "$expected_head" ]] ||
  die "Current HEAD ${current_head} does not equal expected HEAD ${expected_head}."

[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] ||
  die "The integration worktree is not clean."

for state_ref in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  if git rev-parse --quiet --verify "$state_ref" >/dev/null 2>&1; then
    die "An unfinished Git operation is present: ${state_ref}."
  fi
done

git remote get-url origin >/dev/null 2>&1 ||
  die "The origin remote is not configured."
mapfile -t origin_fetch_urls < <(git remote get-url --all origin)
mapfile -t origin_push_urls < <(git remote get-url --all --push origin)
(( ${#origin_fetch_urls[@]} == 1 )) ||
  die "origin must have exactly one fetch URL."
(( ${#origin_push_urls[@]} == 1 )) ||
  die "origin must have exactly one push URL."
[[ "${origin_fetch_urls[0]}" == "${origin_push_urls[0]}" ]] ||
  die "origin fetch and push URLs must be identical."
if [[ "${origin_fetch_urls[0]}" =~ ^https?://[^/]*@ ]] ||
   [[ "${origin_fetch_urls[0]}" =~ [Aa][Cc][Cc][Ee][Ss][Ss]_[Tt][Oo][Kk][Ee][Nn]= ]] ||
   [[ "${origin_fetch_urls[0]}" =~ [Tt][Oo][Kk][Ee][Nn]= ]]; then
  die "Credential-bearing origin URLs are forbidden."
fi

git_common_dir=$(git rev-parse --path-format=absolute --git-common-dir)
[[ -d "$git_common_dir" ]] || die "Unable to resolve the Git common directory."
lock_path="${git_common_dir}/qdesn-git-only-publication.lock"
exec 9>"$lock_path"
flock -n 9 || die "Another integration publisher holds ${lock_path}."

# Recheck mutable local state after acquiring the repository-wide publisher lock.
[[ "$(git symbolic-ref --quiet --short HEAD)" == "$integration_branch" ]] ||
  die "The current branch changed while acquiring the publisher lock."
[[ "$(git rev-parse --verify HEAD^{commit})" == "$expected_head" ]] ||
  die "HEAD changed while acquiring the publisher lock."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] ||
  die "The worktree changed while acquiring the publisher lock."

note "Fetching origin before any remote mutation..."
git_network fetch --prune origin

remote_main=$(git rev-parse --verify refs/remotes/origin/main^{commit})
[[ "$remote_main" == "$expected_main" ]] ||
  die "origin/main is ${remote_main}; expected ${expected_main}. Reintegrate on the new authority."

git cat-file -e "${expected_main}^{commit}" ||
  die "Expected main commit is unavailable: ${expected_main}."
git cat-file -e "${expected_head}^{commit}" ||
  die "Expected HEAD commit is unavailable: ${expected_head}."
remote_source_ref="refs/remotes/origin/${source_branch}"
remote_source=$(git rev-parse --verify "${remote_source_ref}^{commit}" 2>/dev/null) ||
  die "The source branch is absent from origin: ${source_branch}."
[[ "$remote_source" == "$source_head" ]] ||
  die "origin/${source_branch} is ${remote_source}; expected ${source_head}."
git merge-base --is-ancestor "$expected_main" "$expected_head" ||
  die "Expected main is not an ancestor of expected HEAD."

read -r integrated_commit first_parent second_parent extra_parent < <(
  git rev-list --parents -n 1 "$expected_head"
)
[[ "$integrated_commit" == "$expected_head" && -n "${first_parent:-}" &&
   -n "${second_parent:-}" && -z "${extra_parent:-}" ]] ||
  die "Expected HEAD must be one two-parent integration merge commit."
[[ "$first_parent" == "$expected_main" ]] ||
  die "The integration merge first parent is not expected origin/main."
[[ "$second_parent" == "$source_head" ]] ||
  die "The integration merge second parent is not the declared frozen source."
merge_commit=$expected_head

git diff --check "$expected_main" "$expected_head"

note "Preflight passed:"
note "  origin/main:       ${expected_main}"
note "  integration HEAD:  ${expected_head}"
note "  integration branch: ${integration_branch}"
note "  source branch:      ${source_branch}"
note "  source HEAD:        ${source_head}"
note "  merge commit:      ${merge_commit}"

integration_ref="refs/heads/${integration_branch}"
remote_integration_ref="refs/remotes/origin/${integration_branch}"
main_ref=refs/heads/main
remote_main_ref=refs/remotes/origin/main
source_ref="refs/heads/${source_branch}"

refresh_authority_refs() {
  git_network fetch origin \
    "${main_ref}:${remote_main_ref}" \
    "${source_ref}:${remote_source_ref}"
}

verify_authority_refs() {
  remote_main=$(git rev-parse --verify "${remote_main_ref}^{commit}")
  [[ "$remote_main" == "$expected_main" ]] ||
    die "origin/main changed during publication: ${remote_main}."
  remote_source=$(git rev-parse --verify "${remote_source_ref}^{commit}")
  [[ "$remote_source" == "$source_head" ]] ||
    die "origin/${source_branch} changed during publication: ${remote_source}."
}

if [[ "$dry_run" == true ]]; then
  note "Dry-running the integration-branch push..."
  git_network push --dry-run origin "HEAD:${integration_ref}"

  note "Dry-running the main push..."
  git_network push --dry-run origin "HEAD:${main_ref}"

  refresh_authority_refs
  verify_authority_refs

  note "GIT_ONLY_MAIN_PUBLICATION_DRY_RUN_PASS"
  note "No remote reference was changed."
  exit 0
fi

note "Pushing the integration branch with a normal non-force push..."
git_network push origin "HEAD:${integration_ref}"

note "Reading back the integration branch..."
git_network fetch origin "${integration_ref}:${remote_integration_ref}"
remote_integration=$(git rev-parse --verify "${remote_integration_ref}^{commit}")
[[ "$remote_integration" == "$expected_head" ]] ||
  die "Remote integration branch read-back is ${remote_integration}; expected ${expected_head}."

note "Rechecking origin/main immediately before publication..."
refresh_authority_refs
verify_authority_refs

note "Dry-running the main update..."
git_network push --dry-run origin "HEAD:${main_ref}"

# Close the interval introduced by the dry-run negotiation. A concurrent update
# that occurs after this fetch is still protected by the normal non-force push.
refresh_authority_refs
verify_authority_refs

note "Publishing the tested integration HEAD to origin/main..."
git_network push origin "HEAD:${main_ref}"

note "Reading back origin/main..."
git_network fetch origin \
  "${main_ref}:${remote_main_ref}" \
  "${source_ref}:${remote_source_ref}"
published_main=$(git rev-parse --verify "${remote_main_ref}^{commit}")
[[ "$published_main" == "$expected_head" ]] ||
  die "origin/main read-back is ${published_main}; expected ${expected_head}."
published_source=$(git rev-parse --verify "${remote_source_ref}^{commit}")
[[ "$published_source" == "$source_head" ]] ||
  die "origin/${source_branch} read-back is ${published_source}; expected ${source_head}."

[[ "$(git symbolic-ref --quiet --short HEAD)" == "$integration_branch" ]] ||
  die "The current branch changed during publication."
[[ "$(git rev-parse --verify HEAD^{commit})" == "$expected_head" ]] ||
  die "Local HEAD changed during publication."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] ||
  die "The integration worktree is dirty after publication."

note "GIT_ONLY_MAIN_PUBLICATION_COMPLETE"
note "origin/main=${published_main}"
note "origin/${integration_branch}=${remote_integration}"
