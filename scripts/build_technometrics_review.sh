#!/usr/bin/env bash
# Build identified and anonymous PDF proofs; this does not publish or submit.
set -euo pipefail
[[ $# -eq 0 ]] || { echo "Usage: bash scripts/build_technometrics_review.sh" >&2; exit 2; }
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for dependency in pdflatex bibtex pdfinfo pdftotext rg zip; do
  command -v "$dependency" >/dev/null || { echo "Missing $dependency" >&2; exit 1; }
done
build_root=$(mktemp -d "${TMPDIR:-/tmp}/qdesn-technometrics-review.XXXXXX")
cd "$repo_root"
for mode in identified anonymous; do
  mkdir -p "$build_root/$mode"
  for document in main qdesn-supplement; do
    build_dir="$build_root/$mode/$document"
    mkdir -p "$build_dir"
    tex_input="\\input{$document.tex}"
    if [[ "$mode" == anonymous ]]; then
      tex_input="\\def\\QdesnReviewMode{1}$tex_input"
    fi
    pdflatex -interaction=nonstopmode -halt-on-error -recorder \
      -jobname="$document" -output-directory="$build_dir" "$tex_input" \
      > "$build_dir/first-pass.txt"
    (cd "$build_dir" && BIBINPUTS="$repo_root:" BSTINPUTS="$repo_root:" bibtex "$document" > bibtex-output.txt)
    for pass in 2 3 4; do
      pdflatex -interaction=nonstopmode -halt-on-error -recorder \
        -jobname="$document" -output-directory="$build_dir" "$tex_input" \
        > "$build_dir/pass-$pass.txt"
    done
    if rg -n '^!|LaTeX Warning|Package .* Warning|undefined|Overfull|Underfull' "$build_dir/$document.log"; then
      echo "Unresolved manuscript build: $mode/$document" >&2
      exit 1
    fi
    pdfinfo "$build_dir/$document.pdf" > "$build_dir/pdfinfo.txt"
    printf '%s/%s: ' "$mode" "$document"
    awk '/^Pages:|^Page size:/ {printf "%s; ", $0} END {print ""}' "$build_dir/pdfinfo.txt"
    pdftotext "$build_dir/$document.pdf" "$build_dir/$document.txt"
    if [[ "$mode" == anonymous ]]; then
      if rg -ni 'Antonio De Leon|Raquel Prado|Bruno Sans|University of California|AntonioAPDL' \
           "$build_dir/$document.txt"; then
        echo "Author-identifying text remains in $mode/$document" >&2; exit 1
      fi
      if ! awk '/^Author:|^Subject:|^Keywords:/ {sub(/^[^:]+:[[:space:]]*/, ""); if (length($0)) bad=1} END {exit bad}' \
           "$build_dir/pdfinfo.txt"; then
        echo "Identifying metadata remains in $mode/$document" >&2; exit 1
      fi
    fi
  done
done
mkdir -p "$build_root/anonymous-review"
cp "$build_root/anonymous/main/main.pdf" "$build_root/anonymous-review/manuscript.pdf"
cp "$build_root/anonymous/qdesn-supplement/qdesn-supplement.pdf" "$build_root/anonymous-review/supplement.pdf"
cp "$repo_root/docs/reproducibility/anonymous_review_README.txt" "$build_root/anonymous-review/README.txt"
(cd "$build_root/anonymous-review" && zip -q "$build_root/anonymous-review.zip" manuscript.pdf supplement.pdf README.txt)
echo "TECHNOMETRICS_REVIEW_PROOFS_BUILT=$build_root"
echo "ANONYMOUS_REVIEW_PDF_PACKAGE=$build_root/anonymous-review.zip"
echo "FULL_SUBMISSION_READY=NO: consult the preparation record for open gates."
