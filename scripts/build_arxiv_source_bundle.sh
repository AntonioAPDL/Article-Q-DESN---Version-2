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

copy_as main.tex article.tex
copy_as qdesn-supplement.tex supplement.tex
copy_as refs.bib references.bib

copy_as tables/glofas_application_current_outputs.tex tables/glofas_application_macros.tex
copy_as tables/glofas_application_current_score_summary.tex tables/glofas_score_summary.tex
copy_as tables/pricefm_full_current_outputs.tex tables/pricefm_benchmark_macros.tex
copy_as tables/pricefm_full_main_summary.tex tables/pricefm_benchmark_main_summary.tex
copy_as tables/pricefm_full_input_set_summary.tex tables/pricefm_benchmark_input_set_summary.tex
copy_as tables/pricefm_full_horizon_diagnostic_summary.tex tables/pricefm_benchmark_horizon_summary.tex

copy_as tables/qdesn_validation_tt500_final_mcmc_tables.tex tables/independent_simulation_mcmc_tables.tex
copy_as tables/qdesn_validation_tt500_final_mcmc_normal.tex tables/independent_simulation_mcmc_gaussian.tex
copy_as tables/qdesn_validation_tt500_final_mcmc_laplace.tex tables/independent_simulation_mcmc_laplace.tex
copy_as tables/qdesn_validation_tt500_final_mcmc_gausmix.tex tables/independent_simulation_mcmc_gaussian_mixture.tex
copy_as tables/qdesn_validation_tt500_final_tables.tex tables/independent_simulation_vb_mcmc_tables.tex
copy_as tables/qdesn_validation_tt500_final_normal.tex tables/independent_simulation_vb_mcmc_gaussian.tex
copy_as tables/qdesn_validation_tt500_final_laplace.tex tables/independent_simulation_vb_mcmc_laplace.tex
copy_as tables/qdesn_validation_tt500_final_gausmix.tex tables/independent_simulation_vb_mcmc_gaussian_mixture.tex

copy_as tables/joint_qdesn_article_validation_mcmc_balanced_model_summary.tex tables/joint_simulation_mcmc_model_summary.tex
copy_as tables/joint_qdesn_article_validation_provenance_tables.tex tables/joint_simulation_protocol_diagnostics.tex
copy_as tables/joint_qdesn_article_validation_mcmc_balanced_protocol.tex tables/joint_simulation_protocol.tex
copy_as tables/joint_qdesn_article_validation_mcmc_balanced_scenario_summary.tex tables/joint_simulation_scenario_summary.tex
copy_as tables/joint_qdesn_article_validation_mcmc_balanced_gate_summary.tex tables/joint_simulation_diagnostic_gates.tex
copy_as tables/joint_qdesn_article_validation_mcmc_balanced_winner_summary.tex tables/joint_simulation_winner_summary.tex

copy_as figures/independent_simulation/qdesn_mcmc_metric_envelope_heatmap.pdf figures/independent_simulation_mcmc_performance.pdf
copy_as figures/glofas_application/glofas_qdesn_discrepancy_corrected_quantile_paths__glofas_stage_n_winner_scorebalanced_20260703.pdf figures/glofas_calibrated_quantile_paths.pdf
copy_as figures/glofas_application/diagnostics/glofas_stage_n_winner_full7_scorebalanced_qdesn_synthesized_bands__glofas_stage_n_winner_scorebalanced_20260703.pdf figures/glofas_forecast_bands.pdf

rewrite_files=(
  "$out_dir/article.tex"
  "$out_dir/supplement.tex"
  "$out_dir/tables/glofas_application_macros.tex"
  "$out_dir/tables/pricefm_benchmark_macros.tex"
  "$out_dir/tables/independent_simulation_mcmc_tables.tex"
  "$out_dir/tables/independent_simulation_vb_mcmc_tables.tex"
  "$out_dir/tables/joint_simulation_protocol_diagnostics.tex"
)

for f in "${rewrite_files[@]}"; do
  perl -0pi -e '
    s{tables/glofas_application_current_outputs\.tex}{tables/glofas_application_macros.tex}g;
    s{tables/glofas_application_current_score_summary\.tex}{tables/glofas_score_summary.tex}g;
    s{tables/pricefm_full_current_outputs\.tex}{tables/pricefm_benchmark_macros.tex}g;
    s{tables/pricefm_full_main_summary\.tex}{tables/pricefm_benchmark_main_summary.tex}g;
    s{tables/pricefm_full_input_set_summary\.tex}{tables/pricefm_benchmark_input_set_summary.tex}g;
    s{tables/pricefm_full_horizon_diagnostic_summary\.tex}{tables/pricefm_benchmark_horizon_summary.tex}g;
    s{tables/qdesn_validation_tt500_final_mcmc_tables\.tex}{tables/independent_simulation_mcmc_tables.tex}g;
    s{tables/qdesn_validation_tt500_final_mcmc_normal\.tex}{tables/independent_simulation_mcmc_gaussian.tex}g;
    s{tables/qdesn_validation_tt500_final_mcmc_laplace\.tex}{tables/independent_simulation_mcmc_laplace.tex}g;
    s{tables/qdesn_validation_tt500_final_mcmc_gausmix\.tex}{tables/independent_simulation_mcmc_gaussian_mixture.tex}g;
    s{tables/qdesn_validation_tt500_final_tables\.tex}{tables/independent_simulation_vb_mcmc_tables.tex}g;
    s{tables/qdesn_validation_tt500_final_normal\.tex}{tables/independent_simulation_vb_mcmc_gaussian.tex}g;
    s{tables/qdesn_validation_tt500_final_laplace\.tex}{tables/independent_simulation_vb_mcmc_laplace.tex}g;
    s{tables/qdesn_validation_tt500_final_gausmix\.tex}{tables/independent_simulation_vb_mcmc_gaussian_mixture.tex}g;
    s{tables/joint_qdesn_article_validation_mcmc_balanced_model_summary\.tex}{tables/joint_simulation_mcmc_model_summary.tex}g;
    s{tables/joint_qdesn_article_validation_provenance_tables\.tex}{tables/joint_simulation_protocol_diagnostics.tex}g;
    s{tables/joint_qdesn_article_validation_mcmc_balanced_protocol\.tex}{tables/joint_simulation_protocol.tex}g;
    s{tables/joint_qdesn_article_validation_mcmc_balanced_scenario_summary\.tex}{tables/joint_simulation_scenario_summary.tex}g;
    s{tables/joint_qdesn_article_validation_mcmc_balanced_gate_summary\.tex}{tables/joint_simulation_diagnostic_gates.tex}g;
    s{tables/joint_qdesn_article_validation_mcmc_balanced_winner_summary\.tex}{tables/joint_simulation_winner_summary.tex}g;
    s{figures/independent_simulation/qdesn_mcmc_metric_envelope_heatmap\.pdf}{figures/independent_simulation_mcmc_performance.pdf}g;
    s{figures/glofas_application/glofas_qdesn_discrepancy_corrected_quantile_paths__glofas_stage_n_winner_scorebalanced_20260703\.pdf}{figures/glofas_calibrated_quantile_paths.pdf}g;
    s{figures/glofas_application/diagnostics/glofas_stage_n_winner_full7_scorebalanced_qdesn_synthesized_bands__glofas_stage_n_winner_scorebalanced_20260703\.pdf}{figures/glofas_forecast_bands.pdf}g;
    s{\\bibliography\{refs\}}{\\bibliography{references}}g;
    s#\\input\{\\GlofasApplicationCurrentScoreTable\}#\\input\x7btables/glofas_score_summary.tex\x7d#g;
    s#\\input\{\\PricefmFullMainSummaryTable\}#\\input\x7btables/pricefm_benchmark_main_summary.tex\x7d#g;
    s#\\includegraphics(\[[^\]]*\])?\{\\GlofasApplicationCurrentCorrectedPathsFigure\}#\\includegraphics${1}\x7bfigures/glofas_calibrated_quantile_paths.pdf\x7d#g;
    s#\\includegraphics(\[[^\]]*\])?\{\\GlofasApplicationCurrentForecastWindowFigure\}#\\includegraphics${1}\x7bfigures/glofas_forecast_bands.pdf\x7d#g;
  ' "$f"
done

cat > "$out_dir/README_ARXIV_SOURCE.txt" <<'EOF'
Q-DESN arXiv source bundle

Main article:
  pdflatex -interaction=nonstopmode -halt-on-error article.tex
  bibtex article
  pdflatex -interaction=nonstopmode -halt-on-error article.tex
  pdflatex -interaction=nonstopmode -halt-on-error article.tex
  pdflatex -interaction=nonstopmode -halt-on-error article.tex

Supplement source is included as supplement.tex. If the supplement is submitted
as ancillary material, compile it separately and upload the resulting PDF:
  pdflatex -interaction=nonstopmode -halt-on-error supplement.tex
  bibtex supplement
  pdflatex -interaction=nonstopmode -halt-on-error supplement.tex
  pdflatex -interaction=nonstopmode -halt-on-error supplement.tex
  pdflatex -interaction=nonstopmode -halt-on-error supplement.tex

This bundle intentionally excludes repository history, workflow notes,
application scripts, local run artifacts, validation caches, and other files not
needed to process the article.
EOF

(
  cd "$out_dir"
  find . -type f | sort
) > "$out_dir/file_list.txt"

echo "$out_dir"
