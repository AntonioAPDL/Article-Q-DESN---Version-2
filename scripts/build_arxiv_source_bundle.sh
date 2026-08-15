#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stamp="$(date +%Y%m%d_%H%M%S)"
out_dir="${1:-/tmp/qdesn_arxiv_source_${stamp}}"
manifest="${QDESN_ARTICLE_MANIFEST:-overleaf/article_files.txt}"

cd "$repo_root"

if [[ -e "$out_dir" ]]; then
  echo "Output path already exists; choose a new path: $out_dir" >&2
  exit 1
fi

if [[ ! -f "$manifest" ]]; then
  echo "Missing article manifest: $manifest" >&2
  exit 1
fi

mkdir -p "$out_dir"

copy_manifest_entry() {
  local src="$1"
  case "$src" in
    ""|\#*) return 0 ;;
    /*|*..*|*.git/*|.git/*)
      echo "Unsafe manifest entry: $src" >&2
      exit 1
      ;;
  esac
  if [[ ! -f "$src" ]]; then
    echo "Missing required source file: $src" >&2
    exit 1
  fi
  mkdir -p "$out_dir/$(dirname "$src")"
  cp -p "$src" "$out_dir/$src"
}

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%$'\r'}"
  copy_manifest_entry "$line"
done < "$manifest"

cat > "$out_dir/README_ARXIV_SOURCE.txt" <<'EOF'
Q-DESN arXiv source bundle

The bundle is copied directly from overleaf/article_files.txt, preserving the
same relative paths used by the manuscript source. It intentionally excludes
repository history, workflow notes, local run artifacts, validation caches, and
other files not needed to compile the article sources.

Main article:
  pdflatex -interaction=nonstopmode -halt-on-error main.tex
  bibtex main
  pdflatex -interaction=nonstopmode -halt-on-error main.tex
  pdflatex -interaction=nonstopmode -halt-on-error main.tex

Supplement:
  pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
  bibtex qdesn-supplement
  pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
  pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
EOF

(
  cd "$out_dir"
  find . -type f | LC_ALL=C sort
) > "$out_dir/file_list.txt"

(
  cd "$out_dir"
  find . -type f ! -name SHA256SUMS.txt -print0 |
    LC_ALL=C sort -z |
    xargs -0 sha256sum
) > "$out_dir/SHA256SUMS.txt"

echo "$out_dir"
