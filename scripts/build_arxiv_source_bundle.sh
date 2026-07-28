#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stamp="$(date +%Y%m%d_%H%M%S)"
out_dir="${1:-/tmp/qdesn_arxiv_source_bundle_${stamp}}"

cd "$repo_root"

files=(
  main.tex
  qdesn-supplement.tex
  refs.bib
  tables/glofas_application_current_outputs.tex
  tables/glofas_application_current_score_summary.tex
  tables/pricefm_full_current_outputs.tex
  tables/pricefm_full_main_summary.tex
  tables/pricefm_full_input_set_summary.tex
  tables/pricefm_full_horizon_diagnostic_summary.tex
  tables/qdesn_validation_tt500_final_mcmc_tables.tex
  tables/qdesn_validation_tt500_final_mcmc_normal.tex
  tables/qdesn_validation_tt500_final_mcmc_laplace.tex
  tables/qdesn_validation_tt500_final_mcmc_gausmix.tex
  tables/qdesn_validation_tt500_final_tables.tex
  tables/qdesn_validation_tt500_final_normal.tex
  tables/qdesn_validation_tt500_final_laplace.tex
  tables/qdesn_validation_tt500_final_gausmix.tex
  tables/joint_qdesn_article_validation_mcmc_balanced_model_summary.tex
  tables/joint_qdesn_article_validation_provenance_tables.tex
  tables/joint_qdesn_article_validation_mcmc_balanced_protocol.tex
  tables/joint_qdesn_article_validation_mcmc_balanced_scenario_summary.tex
  tables/joint_qdesn_article_validation_mcmc_balanced_gate_summary.tex
  tables/joint_qdesn_article_validation_mcmc_balanced_winner_summary.tex
  figures/glofas_application/glofas_qdesn_discrepancy_corrected_quantile_paths__glofas_stage_n_winner_scorebalanced_20260703.pdf
  figures/glofas_application/diagnostics/glofas_stage_n_winner_full7_scorebalanced_qdesn_synthesized_bands__glofas_stage_n_winner_scorebalanced_20260703.pdf
)

if [[ -e "$out_dir" ]]; then
  echo "Output path already exists; choose a new path: $out_dir" >&2
  exit 1
fi
mkdir -p "$out_dir"

for f in "${files[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing required source file: $f" >&2
    exit 1
  fi
  mkdir -p "$out_dir/$(dirname "$f")"
  cp -p "$f" "$out_dir/$f"
done

cat > "$out_dir/README_ARXIV_SOURCE.txt" <<'EOF'
Q-DESN arXiv source bundle

Main article:
  pdflatex -interaction=nonstopmode -halt-on-error main.tex
  bibtex main
  pdflatex -interaction=nonstopmode -halt-on-error main.tex
  pdflatex -interaction=nonstopmode -halt-on-error main.tex

Supplement source is included as qdesn-supplement.tex. If the supplement is
submitted as an ancillary file, compile it separately and upload the resulting
PDF as ancillary material:
  pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
  bibtex qdesn-supplement
  pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
  pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex

This bundle intentionally excludes repository history, application scripts,
local run artifacts, validation caches, and implementation notes.
EOF

(
  cd "$out_dir"
  find . -type f | sort
) > "$out_dir/source_file_manifest.txt"

echo "$out_dir"
