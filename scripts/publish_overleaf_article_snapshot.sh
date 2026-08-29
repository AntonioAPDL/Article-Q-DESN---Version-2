#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C

usage() {
  cat <<'EOF'
Usage:
  scripts/publish_overleaf_article_snapshot.sh \
    --source-commit FULL_ORIGIN_MAIN_SHA [--dry-run]

This is the sole supported Overleaf publication command. It publishes the
verified article-only projection of an exact, freshly fetched origin/main to
origin/overleaf/article-snapshot and overleaf-direct/main using normal
command-line Git pushes only.
EOF
}

die() {
  echo "GIT_ONLY_OVERLEAF_PUBLISH_ERROR: $*" >&2
  exit 1
}

# Clear URL-specific hosting-service helpers as well as the generic helper.
# Authentication is therefore handled only by command-line Git's credential
# cache, never by GitHub CLI, an editor socket, or a browser integration.
git_network() {
  git \
    -c credential.helper= \
    -c 'credential.helper=cache --timeout=900' \
    -c credential.https://github.com.helper= \
    -c 'credential.https://github.com.helper=cache --timeout=900' \
    -c credential.https://git.overleaf.com.helper= \
    -c 'credential.https://git.overleaf.com.helper=cache --timeout=900' \
    "$@"
}

validate_remote_urls() {
  local remote=$1
  local allowed_http_user=${2:-}
  local authority userinfo url
  local -a fetch_urls push_urls

  git remote get-url "$remote" >/dev/null 2>&1 ||
    die "required remote is absent: $remote"
  mapfile -t fetch_urls < <(git remote get-url --all "$remote")
  mapfile -t push_urls < <(git remote get-url --all --push "$remote")
  (( ${#fetch_urls[@]} == 1 )) ||
    die "$remote must have exactly one fetch URL"
  (( ${#push_urls[@]} == 1 )) ||
    die "$remote must have exactly one push URL"
  [[ "${fetch_urls[0]}" == "${push_urls[0]}" ]] ||
    die "$remote fetch and push URLs must be identical"

  url=${fetch_urls[0]}
  if [[ "$url" == *olp_* ]] ||
     [[ "$url" =~ [Aa][Cc][Cc][Ee][Ss][Ss]_[Tt][Oo][Kk][Ee][Nn]= ]] ||
     [[ "$url" =~ [\?\&][Tt][Oo][Kk][Ee][Nn]= ]]; then
    die "credential material in a remote URL is forbidden: $remote"
  fi
  if [[ "$url" =~ ^https?://([^/]+) ]]; then
    authority=${BASH_REMATCH[1]}
    if [[ "$authority" == *@* ]]; then
      userinfo=${authority%@*}
      [[ -n "$allowed_http_user" && "$userinfo" == "$allowed_http_user" ]] ||
        die "credential-bearing or unexpected HTTP(S) user information is forbidden: $remote"
    fi
  fi
}

source_commit=
dry_run=false

while (( $# > 0 )); do
  case "$1" in
    --source-commit)
      (( $# >= 2 )) || die "--source-commit requires a value"
      source_commit=$2
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
      die "unknown argument: $1"
      ;;
  esac
done

[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] ||
  die "--source-commit must be a lowercase 40-character commit hash"

for command_name in git flock pdflatex bibtex pdfinfo; do
  command -v "$command_name" >/dev/null 2>&1 ||
    die "$command_name is unavailable"
done

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) ||
  die "run inside the article repository"
repo_root=$(cd "$repo_root" && pwd)
cd "$repo_root"

[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] ||
  die "DIRTY_WORKTREE: commit or remove all local changes before publication"

validate_remote_urls origin
validate_remote_urls overleaf-direct git
origin_url=$(git remote get-url origin)
direct_url=$(git remote get-url overleaf-direct)

unset GIT_ASKPASS SSH_ASKPASS
export GIT_TERMINAL_PROMPT=0

git_common_dir=$(git rev-parse --path-format=absolute --git-common-dir)
[[ -d "$git_common_dir" ]] || die "unable to resolve the Git common directory"
exec 9>"$git_common_dir/qdesn-git-only-publication.lock"
flock -n 9 ||
  die "another integration or publication process holds the repository lock"

[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] ||
  die "WORKTREE_CHANGED: publication aborted after acquiring the lock"

temp_root=$(mktemp -d /tmp/qdesn_git_only_overleaf_publish.XXXXXX)
stage_dir=$temp_root/stage
recovery_stage=$temp_root/recovery-stage
publish_repo=$temp_root/publish-repo
empty_template=$temp_root/empty-git-template
empty_hooks=$temp_root/empty-git-hooks
empty_attributes=$temp_root/empty-git-attributes
mkdir -p "$empty_template" "$empty_hooks"
: >"$empty_attributes"
cleanup() {
  case "$temp_root" in
    /tmp/qdesn_git_only_overleaf_publish.*) rm -rf -- "$temp_root" ;;
  esac
}
trap cleanup EXIT

fetch_origin_refs() {
  git_network fetch --no-tags origin \
    "refs/heads/main:refs/remotes/origin/main" \
    "refs/heads/overleaf/article-snapshot:refs/remotes/origin/overleaf/article-snapshot"
}

fetch_direct_ref() {
  git_network fetch --no-tags overleaf-direct \
    "refs/heads/main:refs/remotes/overleaf-direct/main"
}

init_disposable_repo() {
  local directory=$1
  git init -q --template="$empty_template" "$directory"
  git -C "$directory" config core.hooksPath "$empty_hooks"
  git -C "$directory" config core.attributesFile "$empty_attributes"
  git -C "$directory" config core.autocrlf false
  git -C "$directory" config core.safecrlf true
  git -C "$directory" config commit.gpgSign false
}

fetch_origin_refs || die "ORIGIN_FETCH_FAILED: no publication ref was changed"
fetch_direct_ref ||
  die "OVERLEAF_FETCH_FAILED: prime Git's credential cache securely and rerun; no publication ref was changed"

actual_source=$(git rev-parse --verify refs/remotes/origin/main^{commit})
[[ "$actual_source" == "$source_commit" ]] ||
  die "SOURCE_MAIN_MOVED: expected $source_commit but origin/main is $actual_source"
local_head=$(git rev-parse --verify HEAD^{commit})
[[ "$local_head" == "$source_commit" ]] ||
  die "LOCAL_HEAD_MISMATCH: run from a clean worktree checked out at the source origin/main commit"

old_origin_snapshot=$(git rev-parse --verify refs/remotes/origin/overleaf/article-snapshot^{commit})
old_direct=$(git rev-parse --verify refs/remotes/overleaf-direct/main^{commit})

marker_value_from_commit() {
  local commit=$1
  local key=$2
  local marker value count
  marker=$(git show "${commit}:SOURCE_AUTHORITY.txt" 2>/dev/null) ||
    die "verified publisher commit lacks SOURCE_AUTHORITY.txt: $commit"
  value=$(sed -n "s/^${key}=//p" <<<"$marker")
  count=$(grep -c "^${key}=" <<<"$marker" || true)
  [[ "$count" -eq 1 && -n "$value" ]] ||
    die "verified publisher commit has an invalid $key marker: $commit"
  printf '%s' "$value"
}

validate_origin_ahead_recovery() {
  local ahead=$1
  local behind=$2
  local ahead_count recovery_commit parent extra_parent marker_source subject
  local expected_subject recovery_tree

  ahead_count=$(git rev-list --count "${behind}..${ahead}")
  [[ "$ahead_count" -eq 1 ]] ||
    die "PARTIAL_PUBLICATION_INVALID: origin snapshot must be exactly one commit ahead"
  read -r recovery_commit parent extra_parent < <(
    git rev-list --parents -n 1 "$ahead"
  )
  [[ "$recovery_commit" == "$ahead" && "$parent" == "$behind" &&
     -z "${extra_parent:-}" ]] ||
    die "PARTIAL_PUBLICATION_INVALID: publisher commit must have exactly one expected parent"
  [[ "$(marker_value_from_commit "$ahead" schema)" == 1 ]] ||
    die "PARTIAL_PUBLICATION_INVALID: unsupported marker schema"
  [[ "$(marker_value_from_commit "$ahead" authority_policy)" == command-line-git-only ]] ||
    die "PARTIAL_PUBLICATION_INVALID: authority policy marker is absent"
  [[ "$(marker_value_from_commit "$ahead" source_remote)" == origin ]] ||
    die "PARTIAL_PUBLICATION_INVALID: source remote marker is invalid"
  [[ "$(marker_value_from_commit "$ahead" source_branch)" == main ]] ||
    die "PARTIAL_PUBLICATION_INVALID: source branch marker is invalid"
  marker_source=$(marker_value_from_commit "$ahead" source_commit)
  [[ "$marker_source" =~ ^[0-9a-f]{40}$ ]] ||
    die "PARTIAL_PUBLICATION_INVALID: source marker is not a commit ID"
  git cat-file -e "${marker_source}^{commit}" 2>/dev/null ||
    die "PARTIAL_PUBLICATION_INVALID: marked source commit is unavailable"
  git merge-base --is-ancestor "$marker_source" refs/remotes/origin/main ||
    die "PARTIAL_PUBLICATION_INVALID: marked source is not in origin/main history"
  subject=$(git show -s --format=%s "$ahead")
  expected_subject="Publish article-only snapshot from $marker_source"
  [[ "$subject" == "$expected_subject" ]] ||
    die "PARTIAL_PUBLICATION_INVALID: publisher commit subject is invalid"

  mkdir -p "$recovery_stage"
  scripts/build_overleaf_article_snapshot.sh "$marker_source" "$recovery_stage"
  scripts/check_overleaf_article_snapshot.sh "$recovery_stage" "$marker_source"
  init_disposable_repo "$temp_root/recovery-tree-repo"
  cp -a "$recovery_stage/." "$temp_root/recovery-tree-repo/"
  git -C "$temp_root/recovery-tree-repo" add --force --all
  recovery_tree=$(git -C "$temp_root/recovery-tree-repo" write-tree)
  [[ "$(git rev-parse "${ahead}^{tree}")" == "$recovery_tree" ]] ||
    die "PARTIAL_PUBLICATION_INVALID: origin-ahead tree differs from its verified source projection"
}

if [[ "$old_origin_snapshot" != "$old_direct" ]]; then
  if git merge-base --is-ancestor "$old_direct" "$old_origin_snapshot"; then
    validate_origin_ahead_recovery "$old_origin_snapshot" "$old_direct"

    fetch_origin_refs || die "RECOVERY_ORIGIN_REFETCH_FAILED"
    fetch_direct_ref || die "RECOVERY_OVERLEAF_REFETCH_FAILED"
    [[ "$(git rev-parse refs/remotes/origin/overleaf/article-snapshot)" == "$old_origin_snapshot" ]] ||
      die "SNAPSHOT_REF_MOVED_DURING_RECOVERY"
    [[ "$(git rev-parse refs/remotes/overleaf-direct/main)" == "$old_direct" ]] ||
      die "OVERLEAF_REF_MOVED_DURING_RECOVERY"
    git_network push --dry-run overleaf-direct \
      "$old_origin_snapshot:refs/heads/main" >/dev/null ||
      die "verified direct-Overleaf recovery negotiation failed"

    if [[ "$dry_run" == true ]]; then
      printf 'recovery_snapshot_commit=%s\n' "$old_origin_snapshot"
      echo "GIT_ONLY_OVERLEAF_PUBLICATION_DRY_RUN_RECOVERY_REQUIRED"
      echo "No remote reference was changed. Run without --dry-run to repair the verified one-sided publication."
      exit 0
    fi

    git_network push overleaf-direct \
      "$old_origin_snapshot:refs/heads/main" ||
      die "VERIFIED_OVERLEAF_RECOVERY_PUSH_FAILED"
    fetch_direct_ref || die "VERIFIED_OVERLEAF_RECOVERY_READBACK_FAILED"
    [[ "$(git rev-parse refs/remotes/overleaf-direct/main)" == "$old_origin_snapshot" ]] ||
      die "VERIFIED_OVERLEAF_RECOVERY_READBACK_MISMATCH"
    old_direct=$old_origin_snapshot

    fetch_origin_refs || die "POST_RECOVERY_ORIGIN_FETCH_FAILED"
    [[ "$(git rev-parse refs/remotes/origin/main)" == "$source_commit" ]] ||
      die "RECOVERY_COMPLETE_SOURCE_MAIN_MOVED: publication refs are equal; rerun from the new origin/main"
  elif git merge-base --is-ancestor "$old_origin_snapshot" "$old_direct"; then
    die "DIRECT_OVERLEAF_AHEAD: forbidden one-way flow violation; inspect browser edits without merging them"
  else
    die "PUBLICATION_REF_DIVERGENCE: snapshot and direct Overleaf have unrelated commits"
  fi
fi

[[ "$old_origin_snapshot" == "$old_direct" ]] ||
  die "INTERNAL_RECOVERY_ERROR: publication refs remain unequal"

mkdir -p "$stage_dir"
scripts/build_overleaf_article_snapshot.sh "$source_commit" "$stage_dir"
scripts/check_overleaf_article_snapshot.sh "$stage_dir" "$source_commit"

init_disposable_repo "$publish_repo"
git -C "$publish_repo" remote add origin "$origin_url"
git -C "$publish_repo" remote add overleaf-direct "$direct_url"
git_network -C "$publish_repo" fetch -q --no-tags origin \
  "refs/heads/main:refs/remotes/origin/main" \
  "refs/heads/overleaf/article-snapshot:refs/remotes/origin/overleaf/article-snapshot"
git_network -C "$publish_repo" fetch -q --no-tags overleaf-direct \
  "refs/heads/main:refs/remotes/overleaf-direct/main"
git -C "$publish_repo" checkout -q --detach "$old_origin_snapshot"

git -C "$publish_repo" rm -q -r -f --ignore-unmatch .
cp -a "$stage_dir/." "$publish_repo/"
git -C "$publish_repo" add --force --all
staged_tree=$(git -C "$publish_repo" write-tree)

parent_tree=$(git rev-parse "${old_origin_snapshot}^{tree}")
if [[ "$staged_tree" == "$parent_tree" ]]; then
  publish_commit=$old_origin_snapshot
  publication_action=noop
else
  git -C "$publish_repo" config user.name "Q-DESN Integration"
  git -C "$publish_repo" config user.email "jaguir26@ucsc.edu"
  source_date=$(git show -s --format=%cI "$source_commit")
  GIT_AUTHOR_DATE=$source_date GIT_COMMITTER_DATE=$source_date \
    git -C "$publish_repo" commit -q \
      -m "Publish article-only snapshot from $source_commit"
  publish_commit=$(git -C "$publish_repo" rev-parse HEAD)
  publication_action=new_commit
fi

[[ "$(git -C "$publish_repo" rev-parse "${publish_commit}^{tree}")" == "$staged_tree" ]] ||
  die "PUBLISH_COMMIT_TREE_MISMATCH: hooks, filters, or Git configuration changed the verified tree"

marker_source=$(git -C "$publish_repo" show "$staged_tree:SOURCE_AUTHORITY.txt" |
  sed -n 's/^source_commit=//p')
[[ "$marker_source" == "$source_commit" ]] ||
  die "staged source-authority marker is incorrect"
[[ "$(git rev-parse --verify HEAD^{commit})" == "$source_commit" ]] ||
  die "LOCAL_HEAD_MOVED: publication aborted before push"
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] ||
  die "WORKTREE_CHANGED: publication aborted before push"

fetch_origin_refs || die "ORIGIN_REFETCH_FAILED: publication aborted before push"
fetch_direct_ref || die "OVERLEAF_REFETCH_FAILED: publication aborted before push"
[[ "$(git rev-parse refs/remotes/origin/main)" == "$source_commit" ]] ||
  die "SOURCE_MAIN_MOVED: publication aborted before push"
[[ "$(git rev-parse refs/remotes/origin/overleaf/article-snapshot)" == "$old_origin_snapshot" ]] ||
  die "SNAPSHOT_REF_MOVED: publication aborted before push"
[[ "$(git rev-parse refs/remotes/overleaf-direct/main)" == "$old_direct" ]] ||
  die "OVERLEAF_REF_MOVED: publication aborted before push"

# The origin-side source guard and snapshot update are atomic. If main moves,
# the server rejects the whole group before the snapshot ref changes.
git_network -C "$publish_repo" push --atomic --dry-run origin \
  "$source_commit:refs/heads/main" \
  "$publish_commit:refs/heads/overleaf/article-snapshot" >/dev/null ||
  die "atomic source-and-snapshot push negotiation failed"
git_network -C "$publish_repo" push --dry-run overleaf-direct \
  "$publish_commit:refs/heads/main" >/dev/null ||
  die "direct Overleaf push negotiation failed"

if [[ "$dry_run" == true ]]; then
  printf 'source_commit=%s\n' "$source_commit"
  printf 'snapshot_commit=%s\n' "$publish_commit"
  printf 'publication_action=%s\n' "$publication_action"
  echo "GIT_ONLY_OVERLEAF_PUBLICATION_DRY_RUN_COMPLETE"
  echo "No remote reference was changed."
  exit 0
fi

git_network -C "$publish_repo" push --atomic origin \
  "$source_commit:refs/heads/main" \
  "$publish_commit:refs/heads/overleaf/article-snapshot" ||
  die "ATOMIC_ORIGIN_PUBLICATION_FAILED: neither origin ref was intentionally advanced"

fetch_origin_refs ||
  die "SNAPSHOT_READBACK_FAILED: direct Overleaf was not changed"
[[ "$(git rev-parse refs/remotes/origin/overleaf/article-snapshot)" == "$publish_commit" ]] ||
  die "SNAPSHOT_READBACK_MISMATCH: direct Overleaf was not changed"

# Once the canonical snapshot advances, always mirror that verified commit to
# direct Overleaf. This keeps retries recoverable even if origin/main advances
# immediately after the atomic origin update.
if [[ "$old_direct" != "$publish_commit" ]]; then
  git_network -C "$publish_repo" push overleaf-direct \
    "$publish_commit:refs/heads/main" ||
    die "OVERLEAF_PUSH_FAILED_AFTER_SNAPSHOT: rerun to resume the verified one-sided publication"
fi

fetch_origin_refs || die "FINAL_ORIGIN_READBACK_FAILED"
fetch_direct_ref || die "FINAL_OVERLEAF_READBACK_FAILED"

final_source=$(git rev-parse refs/remotes/origin/main)
final_snapshot=$(git rev-parse refs/remotes/origin/overleaf/article-snapshot)
final_direct=$(git rev-parse refs/remotes/overleaf-direct/main)

[[ "$final_snapshot" == "$publish_commit" ]] || die "FINAL_SNAPSHOT_READBACK_MISMATCH"
[[ "$final_direct" == "$publish_commit" ]] || die "FINAL_OVERLEAF_READBACK_MISMATCH"
[[ "$(git rev-parse "${final_snapshot}^{tree}")" == "$staged_tree" ]] ||
  die "FINAL_SNAPSHOT_TREE_MISMATCH"
[[ "$(git rev-parse "${final_direct}^{tree}")" == "$staged_tree" ]] ||
  die "FINAL_OVERLEAF_TREE_MISMATCH"

final_marker_source=$(git show "${final_direct}:SOURCE_AUTHORITY.txt" |
  sed -n 's/^source_commit=//p')
[[ "$final_marker_source" == "$source_commit" ]] ||
  die "FINAL_SOURCE_AUTHORITY_MISMATCH"

printf 'source_commit=%s\n' "$source_commit"
printf 'snapshot_commit=%s\n' "$publish_commit"
printf 'snapshot_tree=%s\n' "$staged_tree"
printf 'publication_action=%s\n' "$publication_action"
printf 'origin_snapshot=%s\n' "$final_snapshot"
printf 'overleaf_direct_main=%s\n' "$final_direct"

[[ "$final_source" == "$source_commit" ]] ||
  die "SOURCE_MAIN_ADVANCED_AFTER_SYNCHRONIZED_PUBLICATION: refs are safely equal for $source_commit; publish the newer origin/main"

echo "GIT_ONLY_OVERLEAF_PUBLICATION_COMPLETE"
