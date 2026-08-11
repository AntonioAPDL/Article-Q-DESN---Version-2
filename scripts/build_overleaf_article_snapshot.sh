#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 SOURCE_REF DESTINATION" >&2
  echo "Materialize the recorder-verified article-only Overleaf snapshot." >&2
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

source_ref=$1
destination=$2

git rev-parse --verify "${source_ref}^{commit}" >/dev/null

if [[ -e "$destination" ]] && [[ -n "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  echo "Destination is not empty: $destination" >&2
  exit 3
fi

mkdir -p "$destination"
destination=$(cd "$destination" && pwd)

mapfile -t article_files < <(
  git show "${source_ref}:overleaf/article_files.txt" |
    sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d'
)

if [[ ${#article_files[@]} -eq 0 ]]; then
  echo "Article manifest is empty." >&2
  exit 4
fi

for path in "${article_files[@]}"; do
  git cat-file -e "${source_ref}:${path}"
done

git archive --format=tar "$source_ref" -- "${article_files[@]}" |
  tar -xf - -C "$destination"
git show "${source_ref}:overleaf/overleaf.gitignore" > "$destination/.gitignore"
git show "${source_ref}:overleaf/README.md" > "$destination/README.md"

file_count=$(find "$destination" -type f | wc -l)
byte_count=$(find "$destination" -type f -printf '%s\n' | awk '{total += $1} END {print total + 0}')
source_commit=$(git rev-parse "${source_ref}^{commit}")

if [[ "$file_count" -ne $((${#article_files[@]} + 2)) ]]; then
  echo "Unexpected snapshot file count: $file_count" >&2
  exit 5
fi

printf 'source_commit=%s\n' "$source_commit"
printf 'manifest_files=%d\n' "${#article_files[@]}"
printf 'snapshot_files=%d\n' "$file_count"
printf 'snapshot_bytes=%d\n' "$byte_count"
printf 'destination=%s\n' "$destination"
