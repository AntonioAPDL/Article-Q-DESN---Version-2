#!/usr/bin/env bash
# Small self-contained reproduction of the current JOINT forecast table/figure.
# Presentation reproduction from authenticated summaries, not posterior refitting.
set -euo pipefail
[[ $# -eq 0 ]] || { echo "Usage: bash scripts/build_qdesn_reproducibility_example.sh" >&2; exit 2; }
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for dependency in Rscript sha256sum cmp tar rg pdftotext pdftoppm; do
  command -v "$dependency" >/dev/null || { echo "Missing $dependency" >&2; exit 1; }
done
demo_root=$(mktemp -d "${TMPDIR:-/tmp}/qdesn-reproduction-example.XXXXXX")
mkdir -p "$demo_root/scripts" "$demo_root/tables" "$demo_root/expected"
cp "$repo_root/scripts/reproduce_qdesn_joint_forecast.R" "$demo_root/scripts/"
cp "$repo_root/scripts/qdesn_evaluation_figure_style.R" "$demo_root/scripts/"
sources=(forecast_score_summary)
for source in "${sources[@]}"; do
  cp "$repo_root/tables/joint_qdesn_pure_desn_v1_${source}.csv" "$demo_root/tables/"
done
cp "$repo_root/tables/joint_qdesn_pure_desn_v1_score_table.tex" "$demo_root/expected/"
cp "$repo_root/figures/joint_qdesn_simulation/joint_qdesn_pure_desn_v1_forecast_dgp_acrps.pdf" "$demo_root/expected/"
cp "$repo_root/docs/reproducibility/representative_result_README.md" "$demo_root/README.md"
cp "$repo_root/scripts/reproduce_qdesn_representative_result.sh" "$demo_root/reproduce.sh"
if rg -n '/data/|/home/|local_trackers|application/cache|AntonioAPDL' "$demo_root"; then
  echo "Private paths or author-owned links entered the example" >&2; exit 1
fi
(cd "$demo_root" && sha256sum scripts/* tables/* expected/* README.md reproduce.sh > INPUT_SHA256SUMS)
# Execute exactly the same script that will be delivered to a reviewer.
(cd "$demo_root" && bash reproduce.sh)
tar -czf "$demo_root.tar.gz" -C "$demo_root" .
echo "QDESN_REPRESENTATIVE_REPRODUCTION=PASS"
echo "REPRODUCTION_DIRECTORY=$demo_root"
echo "REPRODUCTION_ARCHIVE=$demo_root.tar.gz"
sha256sum "$demo_root.tar.gz"
