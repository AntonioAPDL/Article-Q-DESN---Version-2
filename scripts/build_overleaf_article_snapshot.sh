#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 SOURCE_REF DESTINATION" >&2
  echo "Materialize the verified article-only Overleaf snapshot." >&2
}

die() {
  echo "OVERLEAF_SNAPSHOT_BUILD_ERROR: $*" >&2
  exit 1
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

source_ref=$1
destination=$2

source_commit=$(git rev-parse --verify "${source_ref}^{commit}" 2>/dev/null) ||
  die "source ref is not a commit: $source_ref"

if [[ -e "$destination" ]] &&
   [[ -n "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  die "destination is not empty: $destination"
fi

mkdir -p "$destination"
destination=$(cd "$destination" && pwd)

manifest_text=$(git show "${source_commit}:overleaf/article_files.txt") ||
  die "cannot read overleaf/article_files.txt at $source_commit"

mapfile -t article_files < <(
  printf '%s\n' "$manifest_text" |
    sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d'
)

if [[ ${#article_files[@]} -eq 0 ]]; then
  die "article manifest is empty"
fi

declare -A seen_paths=()
for path in "${article_files[@]}"; do
  trimmed=$(printf '%s' "$path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [[ "$path" == "$trimmed" ]] || die "manifest path has surrounding whitespace: $path"
  [[ "$path" != /* ]] || die "absolute manifest path is forbidden: $path"
  [[ "/$path/" != *"/../"* ]] || die "parent traversal is forbidden: $path"
  [[ "/$path/" != *"/./"* ]] || die "dot path component is forbidden: $path"
  [[ "$path" != *\\* ]] || die "backslashes are forbidden in manifest paths: $path"
  [[ "$path" != *//* ]] || die "empty path components are forbidden: $path"
  [[ "$path" =~ ^[A-Za-z0-9._/-]+$ ]] ||
    die "manifest path contains forbidden characters: $path"
  case "$path" in
    main.tex|qdesn-supplement.tex|refs.bib|tables/*|figures/*) ;;
    *) die "path is outside the article-only allowlist: $path" ;;
  esac
  [[ -z "${seen_paths[$path]+x}" ]] || die "duplicate manifest path: $path"
  seen_paths[$path]=1
done

for required in main.tex qdesn-supplement.tex refs.bib; do
  [[ -n "${seen_paths[$required]+x}" ]] || die "required article file is absent: $required"
done

sorted_manifest=$(printf '%s\n' "${article_files[@]}" | LC_ALL=C sort)
actual_manifest=$(printf '%s\n' "${article_files[@]}")
[[ "$actual_manifest" == "$sorted_manifest" ]] || die "article manifest must be sorted"

for path in "${article_files[@]}"; do
  git cat-file -e "${source_commit}:${path}" 2>/dev/null ||
    die "manifest path is absent at $source_commit: $path"
  [[ "$(git cat-file -t "${source_commit}:${path}")" == "blob" ]] ||
    die "manifest path is not a file: $path"
  file_mode=$(git ls-tree "$source_commit" -- "$path" | awk '{print $1}')
  [[ "$file_mode" == 100644 || "$file_mode" == 100755 ]] ||
    die "manifest path is not a regular tracked file: $path"
done

git archive --format=tar "$source_commit" -- "${article_files[@]}" |
  tar -xf - -C "$destination"
git show "${source_commit}:overleaf/overleaf.gitignore" > "$destination/.gitignore"
git show "${source_commit}:overleaf/README.md" > "$destination/README.md"

source_tree=$(git rev-parse "${source_commit}^{tree}")
manifest_blob=$(git rev-parse "${source_commit}:overleaf/article_files.txt")
manifest_sha256=$(git show "${source_commit}:overleaf/article_files.txt" | sha256sum | awk '{print $1}')
main_sha256=$(sha256sum "$destination/main.tex" | awk '{print $1}')
supplement_sha256=$(sha256sum "$destination/qdesn-supplement.tex" | awk '{print $1}')
refs_sha256=$(sha256sum "$destination/refs.bib" | awk '{print $1}')

cat > "$destination/SOURCE_AUTHORITY.txt" <<EOF
schema=1
authority_policy=command-line-git-only
source_remote=origin
source_branch=main
source_commit=$source_commit
source_tree=$source_tree
manifest_blob=$manifest_blob
manifest_sha256=$manifest_sha256
main_tex_sha256=$main_sha256
supplement_tex_sha256=$supplement_sha256
refs_bib_sha256=$refs_sha256
EOF

file_count=$(find "$destination" -type f | wc -l)
byte_count=$(find "$destination" -type f -printf '%s\n' | awk '{total += $1} END {print total + 0}')

if [[ "$file_count" -ne $((${#article_files[@]} + 3)) ]]; then
  die "unexpected snapshot file count: $file_count"
fi

printf 'source_commit=%s\n' "$source_commit"
printf 'source_tree=%s\n' "$source_tree"
printf 'manifest_files=%d\n' "${#article_files[@]}"
printf 'snapshot_files=%d\n' "$file_count"
printf 'snapshot_bytes=%d\n' "$byte_count"
printf 'destination=%s\n' "$destination"
