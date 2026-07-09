# PriceFM DE_LU Fold-2/3 Paper-Quantile Robustness Comparison

Date: 2026-06-02

## Objective

Run the fold-1 selected Article-Q-DESN PriceFM winner specification on `DE_LU`
folds `2` and `3`, then compare the resulting paper-quantile predictive
distributions against locally regenerated PriceFM Phase-I predictions on the
same region, fold, split, horizons, and quantile grid.

This note extends the fold-1 apples-to-apples comparison documented in:

```text
docs/implementation_notes/pricefm_phase1_de_lu_fold1_apples_to_apples_20260602.md
docs/implementation_notes/pricefm_de_lu_fold1_paper_quantile_authoritative_20260602.md
```

## Winner Specification Reused

The fold-2/3 launch reuses the corrected fold-1 reservoir winner geometry:

```text
region: DE_LU
folds: 2, 3
quantiles: 0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90
horizons: 1:96
lag window: 96
feature_map: window_reservoir_v1
depth: 1
units: [120]
alpha: 0.5
rho: 0.9
input_scale: 0.5
recurrent_sparsity: 0.05
state_output: final_layer
tau0: 1.0e-3
prior: RHS_NS
shrink_intercept: false
train_origin_limit: 3000 tail origins
VB min_iter: 50
VB max_iter: 100
Q-DESN modes: AL RHS_NS exact chunked, exAL RHS_NS exact chunked
normal-DESN modes: scaled ridge, RHS_NS
```

Each quantile was launched as an independent one-core experiment so the seven
paper quantiles could run in parallel. Cross-quantile warm starts are therefore
not used. Within each quantile/fold cell, AL still warm-starts from normal
RHS_NS and exAL warm-starts from AL at the same quantile.

## Tracked Files

```text
application/config/pricefm_desn_experiment_grid_de_lu_folds23_paper_quantiles_authoritative_20260602.yaml
application/scripts/pricefm/13_run_desn_experiment_grid.py
application/scripts/pricefm/15_summarize_paper_quantile_runs.py
application/scripts/pricefm/16_plot_paper_quantile_diagnostics.py
application/scripts/pricefm/18_compare_pricefm_phase1_desn_quantiles.py
application/scripts/pricefm/19_summarize_pricefm_phase1_desn_fold_comparisons.py
application/tests/test_pricefm_phase1_comparison.py
```

The script changes are small reproducibility/generalization hooks:

- `13_run_desn_experiment_grid.py` accepts optional region/fold overrides and
  otherwise respects the generated full-config scope.
- `15_summarize_paper_quantile_runs.py`, `16_plot_paper_quantile_diagnostics.py`,
  and `18_compare_pricefm_phase1_desn_quantiles.py` use dynamic region/fold
  labels in reports and figures.
- `19_summarize_pricefm_phase1_desn_fold_comparisons.py` aggregates completed
  fold comparison folders into fold-wise, macro, and PriceFM-delta summaries.

## Commands

Generate fold-2/3 configs:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_paper_quantiles_authoritative_20260602.yaml \
  --write
```

Launch seven quantile experiments across folds 2 and 3:

```bash
/usr/bin/time -v \
  -o application/data_local/pricefm/experiment_grids/pricefm_de_lu_folds23_paper_quantiles_authoritative_20260602/launch_logs/folds23_launch.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_paper_quantiles_authoritative_20260602.yaml \
  --priorities 0 \
  --experiment-jobs 7 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```

Summarize the DESN/Q-DESN paper-quantile outputs:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/15_summarize_paper_quantile_runs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_paper_quantiles_authoritative_20260602.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold2_paper_quantiles_authoritative_20260602 \
  --region DE_LU \
  --fold 2 \
  --require-complete true

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/15_summarize_paper_quantile_runs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_paper_quantiles_authoritative_20260602.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold3_paper_quantiles_authoritative_20260602 \
  --region DE_LU \
  --fold 3 \
  --require-complete true
```

Regenerate local PriceFM Phase-I predictions:

```bash
application/data_local/pricefm/venv_pricefm_tf/bin/python \
  application/scripts/pricefm/17_run_pricefm_phase1_predictions.py \
  --config application/config/pricefm_data_pipeline.yaml \
  --pricefm-repo application/data_local/pricefm/external/PriceFM \
  --model-path application/data_local/pricefm/external/PriceFM/Model/PhaseI_best.keras \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold2_apples_to_apples_20260602 \
  --region DE_LU \
  --fold 2 \
  --splits test \
  --window-mode operational \
  --batch-size 128

application/data_local/pricefm/venv_pricefm_tf/bin/python \
  application/scripts/pricefm/17_run_pricefm_phase1_predictions.py \
  --config application/config/pricefm_data_pipeline.yaml \
  --pricefm-repo application/data_local/pricefm/external/PriceFM \
  --model-path application/data_local/pricefm/external/PriceFM/Model/PhaseI_best.keras \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold3_apples_to_apples_20260602 \
  --region DE_LU \
  --fold 3 \
  --splits test \
  --window-mode operational \
  --batch-size 128
```

Compare PriceFM to DESN/Q-DESN and aggregate folds 1-3:

```bash
application/data_local/pricefm/venv_pricefm_tf/bin/python \
  application/scripts/pricefm/18_compare_pricefm_phase1_desn_quantiles.py \
  --pricefm-output-dir application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold2_apples_to_apples_20260602 \
  --desn-output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold2_paper_quantiles_authoritative_20260602 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold2_20260602 \
  --region DE_LU \
  --fold 2 \
  --split test \
  --fan-horizon 1 \
  --max-origins 120

application/data_local/pricefm/venv_pricefm_tf/bin/python \
  application/scripts/pricefm/18_compare_pricefm_phase1_desn_quantiles.py \
  --pricefm-output-dir application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold3_apples_to_apples_20260602 \
  --desn-output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold3_paper_quantiles_authoritative_20260602 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold3_20260602 \
  --region DE_LU \
  --fold 3 \
  --split test \
  --fan-horizon 1 \
  --max-origins 120

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/19_summarize_pricefm_phase1_desn_fold_comparisons.py \
  --region DE_LU \
  --folds 1,2,3 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_folds123_20260602
```

## Output Paths

DESN/Q-DESN fold summaries:

```text
application/data_local/pricefm/authoritative/pricefm_de_lu_fold2_paper_quantiles_authoritative_20260602
application/data_local/pricefm/authoritative/pricefm_de_lu_fold3_paper_quantiles_authoritative_20260602
```

PriceFM local prediction outputs:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold2_apples_to_apples_20260602
application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold3_apples_to_apples_20260602
```

Row-aligned comparison outputs:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold2_20260602
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold3_20260602
```

Fold-robustness aggregate:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_folds123_20260602
```

Tracked machine-readable metric snapshots:

```text
docs/implementation_notes/pricefm_de_lu_folds123_fold_metric_snapshot_20260602.csv
docs/implementation_notes/pricefm_de_lu_folds123_macro_metric_snapshot_20260602.csv
docs/implementation_notes/pricefm_de_lu_folds123_delta_vs_pricefm_snapshot_20260602.csv
```

Key aggregate figures:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_folds123_20260602/figures/aql_by_fold_method.png
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_folds123_20260602/figures/aql_delta_vs_pricefm_by_fold.png
```

## Runtime And Memory

The seven fold-2/3 quantile experiments completed successfully:

```text
launcher wall time: 52:44.47
launcher max RSS: 1,508,464 KB
launcher exit status: 0
```

Local PriceFM Phase-I prediction runtimes:

```text
fold 2: 0:16.23, max RSS 936,344 KB, exit 0
fold 3: 0:15.25, max RSS 924,616 KB, exit 0
```

Row-aligned comparison runtimes:

```text
fold 2: 0:29.33, max RSS 526,748 KB, exit 0
fold 3: 0:29.28, max RSS 525,176 KB, exit 0
```

TensorFlow emitted the expected CPU/CUDA registration messages and the known
scikit-learn scaler-version warning when loading the released PriceFM artifacts.
Both local PriceFM inference runs completed and recorded the model SHA:

```text
PhaseI_best.keras SHA256:
387f1ba06dc42235d23267d0b2228225e33efffb20aeca9c94094f9fef4d19a5
```

## Row Alignment

All selected methods aligned on the same response rows within each fold.

```text
fold 1: 80,640 prediction rows, 11,520 response rows per method
fold 2: 82,656 prediction rows, 11,808 response rows per method
fold 3: 81,984 prediction rows, 11,712 response rows per method
```

Each prediction-row count equals response rows times 7 quantiles.

## Fold Winners

| fold | best_method_id | best_AQL | best_MAE | best_RMSE |
| --- | --- | ---: | ---: | ---: |
| 1 | qdesn_exal_rhs_ns_exact_chunked | 5.074280 | 12.621029 | 20.029264 |
| 2 | pricefm_phase1_pretraining | 5.355079 | 13.235907 | 20.013961 |
| 3 | pricefm_phase1_pretraining | 6.029767 | 14.783424 | 25.517975 |

## Macro Metrics Across Folds 1-3

| method_id | AQL_mean | AQL_std | MAE_mean | RMSE_mean |
| --- | ---: | ---: | ---: | ---: |
| pricefm_phase1_pretraining | 5.569462 | 0.398948 | 13.714243 | 22.532710 |
| qdesn_exal_rhs_ns_exact_chunked | 5.926597 | 1.034579 | 14.688497 | 22.925932 |
| qdesn_al_rhs_ns_exact_chunked | 5.974807 | 1.038808 | 14.715785 | 22.919646 |
| normal_rhs_ns | 7.412828 | 0.952906 | 17.908234 | 24.875397 |
| normal_scaled_ridge | 34.784921 | 5.352148 | 26.019266 | 34.232329 |

## Delta Versus Local PriceFM Phase-I

Negative values mean the Article-Q-DESN method improved over the local PriceFM
Phase-I forecast on that fold.

| fold | method_id | delta_AQL | ratio_AQL | delta_MAE | delta_RMSE |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 | qdesn_exal_rhs_ns_exact_chunked | -0.249259 | 0.953178 | -0.502371 | -2.036928 |
| 1 | qdesn_al_rhs_ns_exact_chunked | -0.204374 | 0.961609 | -0.461374 | -2.012438 |
| 2 | qdesn_exal_rhs_ns_exact_chunked | 0.272747 | 1.050932 | 0.798699 | 1.189222 |
| 2 | qdesn_al_rhs_ns_exact_chunked | 0.319516 | 1.059666 | 0.863085 | 1.208425 |
| 3 | qdesn_exal_rhs_ns_exact_chunked | 1.047917 | 1.173791 | 2.626431 | 2.027374 |
| 3 | qdesn_al_rhs_ns_exact_chunked | 1.100892 | 1.182576 | 2.602913 | 1.964823 |

## Interpretation

The fold-1 selected Q-DESN exAL RHS_NS model generalizes cleanly in the sense
that all fold-2/3 quantile cells fit, summarize, align, and compare without
workflow failures. However, the fold-1 performance advantage is not robust
across the two later folds:

- Fold 1: Q-DESN exAL RHS_NS beats local PriceFM Phase-I by `0.249259` AQL.
- Fold 2: Q-DESN exAL RHS_NS trails local PriceFM Phase-I by `0.272747` AQL.
- Fold 3: Q-DESN exAL RHS_NS trails local PriceFM Phase-I by `1.047917` AQL.

Across folds 1-3, local PriceFM Phase-I has the best mean AQL among the methods
in this single-region comparison. Q-DESN exAL remains the best Article-Q-DESN
method and is consistently better than the normal-DESN variants.

This is a useful robustness result: the fold-1 winner is not enough to claim a
regional apples-to-apples win over PriceFM Phase-I. Further work should either
select hyperparameters using a multi-fold validation criterion or run a broader
multi-region comparison before making stronger claims.

## Validation

Focused checks after the code changes:

```text
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  application/scripts/pricefm/15_summarize_paper_quantile_runs.py \
  application/scripts/pricefm/16_plot_paper_quantile_diagnostics.py \
  application/scripts/pricefm/18_compare_pricefm_phase1_desn_quantiles.py \
  application/scripts/pricefm/19_summarize_pricefm_phase1_desn_fold_comparisons.py

application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_config.py \
  application/tests/test_pricefm_phase1_comparison.py \
  -q
```

Result:

```text
14 passed
```

`git diff --check` also passed before commit.

## Artifact Policy

Generated prediction tables, figures, R objects, and logs remain under ignored
`application/data_local/pricefm/...` paths. The tracked changes are limited to
reusable scripts, tests, the fold-2/3 grid config, and this documentation note.
