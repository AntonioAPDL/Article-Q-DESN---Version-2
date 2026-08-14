#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stamp="$(date +%Y%m%d_%H%M%S)"
out_dir="${1:-/tmp/qdesn_arxiv_source_${stamp}}"

cd "$repo_root"

copy_as() {
  local src="$1"
  local dest="$2"
  if [[ ! -f "$src" ]]; then
    echo "Missing required source file: $src" >&2
    exit 1
  fi
  mkdir -p "$out_dir/$(dirname "$dest")"
  cp -p "$src" "$out_dir/$dest"
}

if [[ -e "$out_dir" ]]; then
  echo "Output path already exists; choose a new path: $out_dir" >&2
  exit 1
fi
mkdir -p "$out_dir"

manifest="overleaf/article_files.txt"
if [[ ! -f "$manifest" ]]; then
  echo "Missing recorder-verified article manifest: $manifest" >&2
  exit 1
fi

mapfile -t article_files < <(
  sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$manifest"
)

if [[ ${#article_files[@]} -eq 0 ]]; then
  echo "Article manifest is empty: $manifest" >&2
  exit 1
fi

for path in "${article_files[@]}"; do
  case "$path" in
    /*|../*|*/../*)
      echo "Unsafe path in article manifest: $path" >&2
      exit 1
      ;;
  esac
  copy_as "$path" "$path"
done

cat > "$out_dir/README_ARXIV_SOURCE.txt" <<'EOF'
Q-DESN arXiv source bundle

Main article:
  pdflatex -interaction=nonstopmode -halt-on-error main.tex
  bibtex main
  pdflatex -interaction=nonstopmode -halt-on-error main.tex
  pdflatex -interaction=nonstopmode -halt-on-error main.tex
  pdflatex -interaction=nonstopmode -halt-on-error main.tex

Supplement source is included as qdesn-supplement.tex. If the supplement is
submitted as ancillary material, compile it separately and upload the resulting
PDF:
  pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
  bibtex qdesn-supplement
  pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
  pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
  pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex

The source closure is read from overleaf/article_files.txt, the same
recorder-verified allowlist used for the article-only Overleaf projection. The
bundle intentionally excludes repository history, workflow notes, application
scripts, local run artifacts, validation caches, and other files not needed to
process the article.
EOF

(
  cd "$out_dir"
  find . -type f | sort
) > "$out_dir/file_list.txt"

echo "$out_dir"
