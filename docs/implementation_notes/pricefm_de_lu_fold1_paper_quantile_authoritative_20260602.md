# PriceFM DE_LU Fold-1 Paper-Quantile Authoritative DESN Plan

Date: 2026-06-02

## Objective

Run the corrected PriceFM DE_LU fold-1 reservoir baseline at the PriceFM tutorial quantile grid:

```text
0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90
```

The purpose is to move from the median-only corrected winner to a paper-style multi-quantile comparison against the local PriceFM phase-I reference row.

## Current Baseline Geometry

The run uses the corrected median winner from:

```text
application/config/pricefm_desn_model_median_de_lu_fold1_authoritative_reservoir_corrected_20260602.yaml
```

Core DESN controls:

```text
region: DE_LU
fold: 1
horizons: 1:96
lag window: 96
train_origin_limit: 3000
feature_map: window_reservoir_v1
depth: 1
units: [120]
alpha: 0.5
rho: 0.9
input_scale: 0.5
recurrent_sparsity: 0.05
state_output: final_layer
tau0: 1.0e-3
shrink_intercept: false
VB min_iter: 50
VB max_iter: 100
```

The main modeled methods remain:

- `normal_scaled_ridge`
- `normal_rhs_ns`
- `qdesn_al_rhs_ns_exact_chunked`
- `qdesn_exal_rhs_ns_exact_chunked`

The local summarizer also includes naive reference forecasts.

## Parallelization Design

The existing PriceFM full-run launcher parallelizes over independent experiment cells. The Q-DESN warm-start code fits quantiles sequentially within a cell, so direct within-cell quantile parallelism would require a larger model-runner refactor.

For this pass, each quantile is therefore a separate one-core experiment cell. This gives clean process-level parallelism:

```text
experiment_jobs: 7
cell_jobs: 1
```

Important consequence:

- Cross-quantile warm starts are intentionally not used.
- Within each quantile cell, AL still warm-starts from the normal RHS_NS fit.
- exAL still warm-starts from AL at the same quantile.

This is the safest reusable implementation for launching the seven quantile models concurrently without changing the model engines.

## Tracked Config

```text
application/config/pricefm_desn_experiment_grid_de_lu_fold1_paper_quantiles_authoritative_20260602.yaml
```

This grid has seven priority-0 experiments, one per quantile.

Generated configs and run artifacts are intentionally ignored:

```text
application/data_local/pricefm/experiment_grids/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/
application/data_local/pricefm/runs/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/
application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/
```

## Reusable Code Added

The grid generator now supports per-experiment quantile controls:

```yaml
quantile: 0.10
```

or:

```yaml
quantiles: [0.25, 0.75]
```

For the paper-quantile run, each experiment uses exactly one quantile. The generator also aligns the exact-equivalence quantile to the experiment quantile for single-quantile cells.

The paper-style aggregation script is:

```text
application/scripts/pricefm/15_summarize_paper_quantile_runs.py
```

It merges completed single-quantile cells, checks row identity across cells, validates quantile coverage by method, computes multi-quantile metrics, and writes a local comparison against:

```text
application/data_local/pricefm/external/PriceFM/Result/phase1_pretraining.csv
```

The DE_LU reference row in that file is:

```text
AQL: 5.675211
RMSE: 24.339258
MAE: 14.211875
```

## Validation Commands

Generate configs:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_fold1_paper_quantiles_authoritative_20260602.yaml \
  --write
```

Dry-run launch:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_fold1_paper_quantiles_authoritative_20260602.yaml \
  --priorities 0 \
  --experiment-jobs 7 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run true
```

Run all seven quantile cells:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_fold1_paper_quantiles_authoritative_20260602.yaml \
  --priorities 0 \
  --experiment-jobs 7 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```

Summarize after cells complete:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/15_summarize_paper_quantile_runs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_fold1_paper_quantiles_authoritative_20260602.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602 \
  --require-complete true
```

## Output Contract

The aggregation script writes:

```text
quantile_cell_status.csv
quantile_cell_runtime.csv
quantile_coverage.csv
combined_predictions_scaled.csv
paper_quantile_metric_summary.csv
paper_quantile_metric_by_horizon.csv
paper_quantile_metric_by_horizon_group.csv
pricefm_reference_comparison.csv
exact_equivalence_by_quantile.csv
method_summary_by_quantile.csv
warm_start_diagnostics_by_quantile.csv
parameter_summary_by_quantile.csv
trace_summary_by_quantile.csv
paper_quantile_report.md
figures/
summary.json
```

## Diagnostic Figures

After the seven quantile cells are summarized, the diagnostic plotting script is:

```text
application/scripts/pricefm/16_plot_paper_quantile_diagnostics.py
```

Regenerate the paper-quantile diagnostic figures with:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/16_plot_paper_quantile_diagnostics.py \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602 \
  --horizon 1 \
  --max-origins 120
```

The script writes a manifest:

```text
application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/paper_quantile_diagnostic_figure_manifest.json
```

and the following local ignored figures:

```text
application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/figures/paper_quantile_diagnostics/test_quantile_fans_all_methods_h01.png
application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/figures/paper_quantile_diagnostics/winner_quantile_fans_h001_h024_h048_h096.png
application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/figures/paper_quantile_diagnostics/trace_elbo.png
application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/figures/paper_quantile_diagnostics/trace_sigma.png
application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/figures/paper_quantile_diagnostics/trace_gamma.png
application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/figures/paper_quantile_diagnostics/trace_rhs_lambda_mean.png
application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/figures/paper_quantile_diagnostics/trace_parameter_change.png
application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/figures/paper_quantile_diagnostics/final_beta_l2_by_tau.png
application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/figures/paper_quantile_diagnostics/final_beta_max_abs_by_tau.png
application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/figures/paper_quantile_diagnostics/final_beta_cov_trace_by_tau.png
application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/figures/paper_quantile_diagnostics/final_sigma_by_tau.png
application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/figures/paper_quantile_diagnostics/final_gamma_by_tau.png
application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602/figures/paper_quantile_diagnostics/final_omega2_by_tau.png
```

The figures show:

- all-method test quantile fans at the requested horizon;
- winner quantile fans at horizons 1, 24, 48, and 96;
- VB objective/ELBO traces by method and quantile;
- sigma, gamma, RHS lambda, and parameter-change traces;
- final beta and likelihood-parameter summaries by quantile.

## Pass Criteria

- All seven quantile cells complete.
- No `.rds`, `.rda`, or `.RData` artifacts remain in successful model directories.
- Row identity matches across quantile cells.
- Each method has predictions for all seven quantiles.
- Exact chunked gates pass in every quantile cell.
- Aggregated test original-unit metrics are finite.
- The report includes PriceFM DE_LU reference metrics.

## Limitations

This is not a direct clone of the PriceFM paper training protocol. It is a controlled Article-Q-DESN PriceFM adaptation using the corrected DESN reservoir baseline and local fold-1 split. The PriceFM reference is useful as an external benchmark row, but not a perfect apples-to-apples claim.

The independent-quantile parallelization also means cross-quantile warm starts are not used. A future sequential multi-quantile run can test whether cross-quantile warm starts improve runtime or stability after this paper-grid baseline is established.
