# PriceFM DE_LU Folds 2-3 Median Selection Registry

Date: 2026-06-03

This note records the reproducible region-fold median selection pass for the PriceFM DE_LU folds 2 and 3 follow-up. It builds on the framework introduced in commit `64871b1` and keeps large run artifacts under ignored `application/data_local` paths.

## Scope

- Region: `DE_LU`
- Folds: `2`, `3`
- Selection quantile: median, `tau = 0.50`
- Selection split/unit/metric: `val` / `original` / `AQL`
- Selection methods: `qdesn_exal_rhs_ns_exact_chunked`, `qdesn_al_rhs_ns_exact_chunked`
- Test metrics are audit-only and were not used to choose the specs.

## Implementation Fixes

During the first priority-0 launch, fold 3 was missing prebuilt windows for `L=72` and `L=128`. The full configs were correctly scoped to folds `[2, 3]`; the issue was that the window builder still used the data-config pilot fold.

Fixes added in this pass:

- `05_build_windows.py` accepts explicit `--regions` and `--folds`.
- `13_run_desn_experiment_grid.py` passes full-config scope into window builds.
- `14_validate_reservoir_grid_artifacts.py` validates every scoped region/fold cell.
- `20_select_pricefm_desn_median_specs.py` accepts explicit priority/stage/id filters, so optional unrun grid cells do not block a completed priority-0 registry.

## Commands

Generate the grid configs:

```sh
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_selection_20260602.yaml \
  --write
```

Priority-0 launch:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_selection_20260602/launch_logs/priority0_launch.time.log \
  application/data_local/pricefm/venv/bin/python application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_selection_20260602.yaml \
  --priorities 0 \
  --experiment-jobs 6 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```

Targeted rerun after fixing multi-fold window scope:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_selection_20260602/launch_logs/missing_fold3_rerun.time.log \
  application/data_local/pricefm/venv/bin/python application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_selection_20260602.yaml \
  --ids rf_p0_f23_d1n120_l072_a0p50_r0p90_in0p50_seed20260601,rf_p0_f23_d1n120_l128_a0p50_r0p90_in0p50_seed20260601 \
  --experiment-jobs 2 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```

Select fold-specific median specs:

```sh
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/20_select_pricefm_desn_median_specs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_selection_20260602.yaml \
  --priorities 0 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_selection_registry_20260602 \
  --regions DE_LU \
  --folds 2,3 \
  --selection-split val \
  --selection-unit original \
  --selection-metric AQL \
  --require-complete true
```

Materialize the promoted paper-quantile grid:

```sh
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py \
  --template-grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_paper_quantiles_authoritative_20260602.yaml \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_selection_registry_20260602/median_selection_registry.csv \
  --output-grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_registry_promoted_quantiles_20260602.yaml \
  --grid-id pricefm_de_lu_folds23_registry_promoted_quantiles_20260602 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_de_lu_folds23_registry_promoted_quantiles_20260602 \
  --run-root application/data_local/pricefm/runs/pricefm_de_lu_folds23_registry_promoted_quantiles_20260602
```

## Validation

- Priority-0 metrics: `24 / 24` cells present.
- Artifact validator: `24 / 24` scoped cells passed.
- Missing fold-3 windows were created for `L=72` and `L=128`.
- Promotion grid dry run: passed for one generated quantile experiment.
- Python checks:
  - `py_compile` passed for scripts `05`, `12`, `13`, `14`, `20`, and `21`.
  - `pytest application/tests/test_pricefm_desn_experiment_grid.py application/tests/test_pricefm_median_selection_registry.py -q`: `14 passed`.

Runtime observations:

- Main priority-0 launch: `1:49:19`, max RSS `1546852 KB`, exit status `0`.
- Targeted missing-cell rerun: `22:35.55`, max RSS `2018976 KB`, exit status `0`.

## Selected Specs

| region | fold | selected_method_id | val_AQL | test_AQL | experiment_id | L | n | D | alpha | rho | input_scale | tau0 |
| --- | ---: | --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| DE_LU | 2 | qdesn_exal_rhs_ns_exact_chunked | 6.181033 | 7.017320 | rf_p0_f23_d1n120_l072_a0p50_r0p90_in0p50_seed20260601 | 72 | 120 | 1 | 0.5 | 0.9 | 0.5 | 0.001 |
| DE_LU | 3 | qdesn_exal_rhs_ns_exact_chunked | 6.765381 | 8.559254 | rf_p0_f23_d1n080_l096_a0p50_r0p90_in0p50_seed20260601 | 96 | 80 | 1 | 0.5 | 0.9 | 0.5 | 0.001 |

Tracked compact snapshots:

- `docs/implementation_notes/pricefm_de_lu_folds23_median_selection_registry_snapshot_20260602.csv`
- `docs/implementation_notes/pricefm_de_lu_folds23_median_candidate_top_snapshot_20260602.csv`

Ignored local registry directory:

```text
application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_selection_registry_20260602
```

## Promoted Quantile Grid

The promoted grid is tracked here:

```text
application/config/pricefm_desn_experiment_grid_de_lu_folds23_registry_promoted_quantiles_20260602.yaml
```

It contains `14` experiments:

- 2 fold-specific median-selected specs
- 7 paper quantiles per fold: `0.10`, `0.25`, `0.45`, `0.50`, `0.55`, `0.75`, `0.90`

Dry-run command:

```sh
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_registry_promoted_quantiles_20260602.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run true \
  --max-experiments 1
```

Real launch command, not run in this pass:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/experiment_grids/pricefm_de_lu_folds23_registry_promoted_quantiles_20260602/launch_logs/priority0_launch.time.log \
  application/data_local/pricefm/venv/bin/python application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_registry_promoted_quantiles_20260602.yaml \
  --priorities 0 \
  --experiment-jobs 8 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```

## Decision

The fold-specific median-selection framework is ready to scale. For DE_LU folds 2 and 3, the priority-0 grid is complete, the selected median specs are frozen in the local registry and tracked snapshots, and the promoted paper-quantile grid is generated and dry-run checked.

Next step: launch the promoted fold-2/3 paper-quantile grid, then run the existing fold-level PriceFM comparison summarizer against folds 1, 2, and 3.
