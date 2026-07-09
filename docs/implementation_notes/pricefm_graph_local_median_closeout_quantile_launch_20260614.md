# PriceFM Graph/Local Median Closeout and Quantile Launch

Date: 2026-06-14

## Purpose

Use the completed graph-neighbor median A/B run to prepare the next
apples-to-apples PriceFM quantile panel comparison without changing the
selection rule after seeing test metrics.

The closeout rule is validation-only:

- promote graph-neighbor DESN only if median validation AQL improves over the
  current local-only median winner for the same region/fold;
- keep the local-only winner otherwise;
- retain test metrics as audit fields only.

## Inputs

- Local median registry:
  `application/data_local/pricefm/authoritative/pricefm_region_panel_median_local_ar_closeout_20260613/merged_selection_registry.csv`
- Graph-neighbor median registry:
  `application/data_local/pricefm/authoritative/pricefm_graph_neighbor_median_ab_registry_20260614/median_selection_registry.csv`
- Graph feature policy:
  `feature_policy = graph_khop`, `graph_degree = 1`,
  `spatial_information_set = pricefm_released_graph_khop`
- Paper quantiles:
  `0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90`

## Tracked Implementation

- `application/scripts/pricefm/38_closeout_pricefm_graph_neighbor_median_registry.py`
- `application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py`
- `application/tests/test_pricefm_graph_neighbor_closeout.py`

The quantile-grid generator now preserves the closeout decision metadata
(`selected_source`, `changed_from_local`, and `selection_decision_rule`) and
omits blank graph-only fields for local rows.

## Closeout Output

Ignored output directory:

`application/data_local/pricefm/authoritative/pricefm_region_panel_median_graph_local_closeout_20260614/`

Key outputs:

- `merged_selection_registry.csv`
- `promotion_decisions.csv`
- `graph_vs_local_median_comparison.csv`
- `graph_vs_local_region_summary.csv`
- `feature_policy_counts.csv`
- `graph_neighbor_closeout_report.md`
- `summary.json`

Observed closeout summary:

- region/fold rows: 18
- graph validation improvements: 9
- graph promoted: 9
- local kept: 9
- graph test improvements, audit only: 15
- mean validation AQL delta, graph minus local: `-0.432404`
- mean test AQL delta, graph minus local: `-0.954242`

Graph-promoted region/folds:

- `DE_LU`: folds 1, 2, 3
- `EE`: folds 2, 3
- `HU`: folds 1, 2, 3
- `IT_SICI`: fold 2

## Quantile Grid

Ignored grid config:

`application/data_local/pricefm/configs/pricefm_desn_experiment_grid_graph_local_promoted_quantiles_20260614.yaml`

Ignored grid root:

`application/data_local/pricefm/experiment_grids/pricefm_graph_local_promoted_quantiles_20260614/`

Ignored run root:

`application/data_local/pricefm/runs/pricefm_graph_local_promoted_quantiles_20260614/`

Generated scope:

- 18 region/fold selected median specs
- 7 quantiles
- 126 quantile experiments
- 63 graph-neighbor experiments
- 63 local-only experiments

Dry-run result:

- 126 experiment jobs planned
- 18 window jobs planned
- no graph/local metadata parsing failures

## Commands

Closeout:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/38_closeout_pricefm_graph_neighbor_median_registry.py \
  --local-registry-csv application/data_local/pricefm/authoritative/pricefm_region_panel_median_local_ar_closeout_20260613/merged_selection_registry.csv \
  --graph-registry-csv application/data_local/pricefm/authoritative/pricefm_graph_neighbor_median_ab_registry_20260614/median_selection_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_region_panel_median_graph_local_closeout_20260614 \
  --candidate-source graph_khop_degree1_20260614
```

Generate quantile grid:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py \
  --template-grid-config application/config/pricefm_desn_experiment_grid_de_lu_fold1_paper_quantiles_authoritative_20260602.yaml \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_region_panel_median_graph_local_closeout_20260614/merged_selection_registry.csv \
  --output-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_graph_local_promoted_quantiles_20260614.yaml \
  --grid-id pricefm_graph_local_promoted_quantiles_20260614 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_graph_local_promoted_quantiles_20260614 \
  --run-root application/data_local/pricefm/runs/pricefm_graph_local_promoted_quantiles_20260614 \
  --quantiles 0.10,0.25,0.45,0.50,0.55,0.75,0.90 \
  --priority 0
```

Dry run:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_graph_local_promoted_quantiles_20260614.yaml \
  --priorities 0 \
  --experiment-jobs 6 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run true
```

Background launch:

```sh
setsid bash -lc 'cd /data/jaguir26/local/src/Article-Q-DESN && exec application/data_local/pricefm/venv/bin/python application/scripts/pricefm/13_run_desn_experiment_grid.py --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_graph_local_promoted_quantiles_20260614.yaml --priorities 0 --experiment-jobs 6 --cell-jobs 1 --build-windows true --resume true --force false --dry-run false' \
  > application/data_local/pricefm/experiment_grids/pricefm_graph_local_promoted_quantiles_20260614/background_launch.log \
  2>&1 < /dev/null &
```

## Validation

Focused tests:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_graph_neighbor_closeout.py \
  application/tests/test_pricefm_graph_neighbor_grid.py \
  application/tests/test_pricefm_median_selection_registry.py \
  -q
```

Expected result: `11 passed`.

Full PriceFM test slice and `git diff --check` should pass before closing the
tracked implementation stage.

## Stop Conditions

- Do not promote graph rows based only on test improvement.
- Do not lose `feature_policy`, `spatial_information_set`, `graph_degree`,
  or `graph_hash` metadata for graph-selected rows.
- Do not commit ignored generated grids, run outputs, or heavy model objects.
- Do not scale beyond the six-region panel until the promoted seven-quantile
  run and PriceFM comparison are inspected.
