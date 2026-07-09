# PriceFM Region-Fold Median Selection Framework

Date: 2026-06-02

## Objective

Build a reproducible framework for selecting DESN/Q-DESN specifications per
`region x fold` using median validation performance, then promoting those
selected specifications to the PriceFM paper-quantile grid for final test
comparison against local PriceFM Phase-I predictions.

The immediate implementation target is:

```text
region: DE_LU
folds: 2, 3
selection quantile: 0.50
selection split: val
audit split: test
```

## Why This Stage Exists

The fold-1 selected Q-DESN exAL RHS_NS specification beat local PriceFM Phase-I
on fold 1, but not on folds 2 and 3. This suggests the fold-1 winner is a
valid local baseline but not a robust global specification.

The next scientifically cleaner step is not to tune on fold-2/3 test metrics.
Instead, each `region x fold` should select a median specification on validation
data, freeze the selected spec in a registry, and use test only once for the
paper-quantile evaluation.

## Framework Stages

1. Generate a median candidate grid.
2. Run candidate cells for one or more `region x fold` pairs.
3. Select one median spec per `region x fold` using validation original-unit
   AQL.
4. Save a machine-readable registry with all selected geometry and provenance.
5. Materialize a paper-quantile grid from the registry.
6. Run the seven PriceFM paper quantiles:

```text
0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90
```

7. Synthesize the quantile outputs and compare to local PriceFM Phase-I on the
   same region/fold/split/horizons/row grid.
8. Clean loser artifacts while preserving the selected registry, compact metric
   snapshots, configs, reports, and winner outputs.

## Tracked Implementation Pieces

Median selection grid for DE_LU folds 2 and 3:

```text
application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_selection_20260602.yaml
```

Grid generator update:

```text
application/scripts/pricefm/12_prepare_desn_experiment_grid.py
```

The generator now supports optional per-experiment `regions` and `folds`, which
is necessary for a future promotion grid containing different specs for
different folds.

Median registry selector:

```text
application/scripts/pricefm/20_select_pricefm_desn_median_specs.py
```

Paper-quantile promotion materializer:

```text
application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py
```

Focused tests:

```text
application/tests/test_pricefm_desn_experiment_grid.py
application/tests/test_pricefm_median_selection_registry.py
```

## Selection Rule

Use validation metrics only:

```text
split: val
unit: original
metric: AQL
eligible methods:
  - qdesn_exal_rhs_ns_exact_chunked
  - qdesn_al_rhs_ns_exact_chunked
```

Test metrics are written into the registry only as audit fields. They do not
select the winner.

## Immediate DE_LU Fold-2/3 Grid

The priority-0 screen has 12 candidates. It is intentionally focused around the
corrected fold-1 winner and nearby dynamics:

```text
lag windows: 72, 96, 128
depths: 1 and compact 2
units: [80], [120], [180], [40,40], [80,80]
alpha: 0.50, 0.70
rho: 0.80, 0.90, 0.97
input_scale: 0.25, 0.50
tau0: 1.0e-3
train_origin_limit: 3000 tail origins
VB iterations: min 50, max 100
chunking: exact chunked
```

The optional priority-1 expansion is not launched automatically. It broadens
`n=120` dynamics and context/capacity around the selected region if the
priority-0 registry suggests more search is worthwhile.

## Commands

Generate configs:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_selection_20260602.yaml \
  --write
```

Dry run:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_selection_20260602.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run true \
  --max-experiments 1
```

Run priority-0 screen:

```bash
/usr/bin/time -v \
  -o application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_selection_20260602/launch_logs/priority0_launch.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_selection_20260602.yaml \
  --priorities 0 \
  --experiment-jobs 6 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```

Select fold-specific median winners:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/20_select_pricefm_desn_median_specs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_selection_20260602.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_selection_registry_20260602 \
  --regions DE_LU \
  --folds 2,3 \
  --selection-split val \
  --selection-unit original \
  --selection-metric AQL \
  --require-complete true
```

Materialize a future paper-quantile grid from the registry:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py \
  --template-grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_paper_quantiles_authoritative_20260602.yaml \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_selection_registry_20260602/median_selection_registry.csv \
  --output-grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_registry_promoted_quantiles_20260602.yaml \
  --grid-id pricefm_de_lu_folds23_registry_promoted_quantiles_20260602 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_de_lu_folds23_registry_promoted_quantiles_20260602 \
  --run-root application/data_local/pricefm/runs/pricefm_de_lu_folds23_registry_promoted_quantiles_20260602
```

## Validation Criteria

- Existing grid configs still generate the same global-scope full configs unless
  an experiment explicitly sets `regions` or `folds`.
- Candidate selection fails if required completed cells are missing.
- Selection uses validation only.
- The registry contains test metrics only as audit columns.
- Promotion grids scope each experiment to exactly one selected
  `region x fold x tau`.
- Generated local outputs remain ignored.
- Compact metric snapshots and final selected registries can be tracked when
  they become authoritative.

## Next Decision After Priority-0

If the priority-0 registry improves fold-2/3 validation and test audit metrics,
promote the selected fold-specific specs to paper quantiles. If the selected
specs are weak or unstable, run the optional priority-1 expansion before
promotion.
