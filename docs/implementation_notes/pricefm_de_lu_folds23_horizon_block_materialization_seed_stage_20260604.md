# PriceFM DE_LU Fold 2/3 Horizon-Block Materialization And Seed Plan

Date: 2026-06-04

## Scope

This note records the implementation stage after the no-fit feature-geometry
diagnostics. The goal was to make the promising horizon-block idea concrete
without launching another model grid.

This stage:

- materialized validation-selected horizon-block median composites from already
  completed model outputs;
- recomputed row-level metrics from the materialized prediction/truth rows;
- prepared a fold-scoped seed-robustness grid config;
- generated ignored grid configs/manifests for dry-run validation;
- added a seed-robustness summarizer for after launch.

No model fits were launched in this stage.

## Tracked Files

Scripts:

```text
application/scripts/pricefm/25_materialize_median_horizon_block_composite.py
application/scripts/pricefm/26_prepare_median_seed_robustness_grid.py
application/scripts/pricefm/27_summarize_median_seed_robustness.py
```

Config:

```text
application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_seed_robustness_20260604.yaml
```

Tests:

```text
application/tests/test_pricefm_horizon_block_materializer.py
```

## Ignored Local Outputs

Materialized composite:

```text
application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_horizon_block_composite_materialized_20260604/
```

Seed-grid prep summary:

```text
application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_seed_robustness_grid_20260604/
```

Seed-summary scaffold:

```text
application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_seed_robustness_summary_20260604/
```

Generated configs/manifests:

```text
application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_seed_robustness_20260604/
```

## Commands

Materialize the horizon-block composite:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/25_materialize_median_horizon_block_composite.py \
  --selection-dir application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_horizon_block_selection_20260604 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_horizon_block_composite_materialized_20260604 \
  --data-config application/config/pricefm_data_pipeline.yaml \
  --region DE_LU \
  --folds 2,3 \
  --splits val,test \
  --unit original \
  --metric AQL
```

Prepare the seed-robustness grid config:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/26_prepare_median_seed_robustness_grid.py \
  --template-grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_deep_targeted_20260603.yaml \
  --baseline-registry-csv application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_selection_registry_20260602/median_selection_registry.csv \
  --horizon-selection-csv application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_horizon_block_selection_20260604/horizon_block_selection.csv \
  --output-grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_seed_robustness_20260604.yaml \
  --summary-output application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_seed_robustness_grid_20260604/summary.json \
  --grid-id pricefm_median_de_lu_folds23_seed_robustness_20260604 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_seed_robustness_20260604 \
  --run-root application/data_local/pricefm/runs/pricefm_median_de_lu_folds23_seed_robustness_20260604 \
  --region DE_LU \
  --folds 2,3 \
  --seeds 20260601,20260602,20260603,20260604,20260605
```

Dry-run and write generated configs:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_seed_robustness_20260604.yaml

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_seed_robustness_20260604.yaml \
  --write
```

Summarize seed robustness after launch. Before launch, this correctly reports
`0 / 50` completed cells:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/27_summarize_median_seed_robustness.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_seed_robustness_20260604.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_seed_robustness_summary_20260604 \
  --regions DE_LU \
  --folds 2,3 \
  --selection-split val \
  --audit-split test \
  --unit original \
  --metric AQL
```

## Materialized Composite Result

The materializer reconstructs composite predictions by taking each
validation-selected horizon specialist and copying only its assigned horizon
block. It aligns rows by split, origin time, response time, horizon, and
quantile. It does not trust `origin_id` alone across models with different lag
windows.

Coverage passed:

| Fold | Split | Blocks | Horizons | Quantiles | Prediction Rows | Origin Count Per Horizon |
|---:|---|---:|---:|---:|---:|---:|
| 2 | val | 4 | 96 | 1 | 11520 | 120 |
| 2 | test | 4 | 96 | 1 | 11808 | 123 |
| 3 | val | 4 | 96 | 1 | 11808 | 123 |
| 3 | test | 4 | 96 | 1 | 11712 | 122 |

Original-unit AQL deltas versus the retained global median:

| Fold | Role | Retained AQL | Materialized Block AQL | Delta |
|---:|---|---:|---:|---:|
| 2 | validation | 6.181033 | 6.101601 | -0.079433 |
| 2 | test audit | 7.017320 | 6.925543 | -0.091776 |
| 3 | validation | 6.765381 | 6.676970 | -0.088411 |
| 3 | test audit | 8.559254 | 8.586891 | 0.027637 |

Interpretation:

- Fold 2 horizon-block materialization remains promising.
- Fold 3 still has a mild test-audit overfit signal and should not be promoted
  without seed robustness.
- AQL matches the previous no-refit composite delta exactly up to numerical
  precision.
- Row-level RMSE is recomputed by the materializer and is not forced to match
  the previous group-mean RMSE diagnostic.

## Seed-Robustness Grid

The prepared grid contains:

| Quantity | Count |
|---|---:|
| Geometries | 10 |
| Seeds | 5 |
| Experiments | 50 |
| Fold 2 experiments | 25 |
| Fold 3 experiments | 25 |

Seeds:

```text
20260601, 20260602, 20260603, 20260604, 20260605
```

The geometry set is the union of:

- retained fold 2/3 global median winners;
- validation-selected horizon-block specialists.

Duplicate geometries within a fold are deduplicated before seed expansion.

## Launch Rule

Do not launch this grid until the generated config has been inspected. The
launch should remain median-only, `DE_LU` folds 2 and 3 only, one core per cell,
and validation-selected.

Recommended launch command after approval:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_seed_robustness_20260604.yaml \
  --priorities 0 \
  --experiment-jobs 10 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run false
```

After launch, rerun:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/27_summarize_median_seed_robustness.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_seed_robustness_20260604.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_seed_robustness_summary_20260604 \
  --regions DE_LU \
  --folds 2,3 \
  --selection-split val \
  --audit-split test \
  --unit original \
  --metric AQL
```

## Validation

Focused checks:

```text
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/25_materialize_median_horizon_block_composite.py \
  application/scripts/pricefm/26_prepare_median_seed_robustness_grid.py \
  application/scripts/pricefm/27_summarize_median_seed_robustness.py

application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_horizon_block_materializer.py -q
```

Result:

```text
4 passed
```

The broader PriceFM diagnostic/regression checks should be rerun before launch
if any existing grid-generation behavior is changed.

## Decision

This stage is ready. The next action is a human launch decision for the 50-cell
seed-robustness grid. The result of that grid should decide whether to promote:

- the retained global fold winners;
- the fold 2 horizon-block composite only;
- a fold 3 horizon-block composite after robustness evidence;
- or a new feature-map engineering stage.
