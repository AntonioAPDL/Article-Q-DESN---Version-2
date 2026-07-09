# PriceFM DE_LU Fold 2/3 Follow-Up Seed And Refinement Grid

Date: 2026-06-05

## Scope

This note records the follow-up stage after the completed fold 2/3
seed-robustness grid. The previous grid showed:

- fold 2 has a robust small candidate, but the prior P2 selected candidate was
  not exactly seed-tested;
- fold 3 still has a validation/test-audit tension, and the prior P2 selected
  candidate remained competitive on the test audit.

This stage prepares a focused median-only grid for `DE_LU` folds 2 and 3. It
does not broaden the search randomly. It targets:

1. exact 5-seed retests of the prior P2 selected fold winners;
2. a fold-3 local refinement around the promising `L = 96`, `n = 80` geometry.

Selection remains validation-only. Test metrics remain audit-only.

## Tracked Files

```text
application/scripts/pricefm/28_prepare_median_folds23_followup_grid.py
application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml
application/tests/test_pricefm_horizon_block_materializer.py
docs/implementation_notes/pricefm_de_lu_folds23_followup_seed_refine_20260605.md
application/README.md
```

## Ignored Local Outputs

```text
application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_followup_grid_20260605/
application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_followup_summary_20260605/
application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_followup_registry_20260605/
application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_followup_20260605/
application/data_local/pricefm/runs/pricefm_median_de_lu_folds23_followup_20260605/
application/data_local/pricefm/experiment_grids/pricefm_de_lu_folds23_followup_promoted_quantiles_20260605/
application/data_local/pricefm/runs/pricefm_de_lu_folds23_followup_promoted_quantiles_20260605/
```

## Grid Design

Fixed settings:

| Field | Value |
|---|---:|
| region | `DE_LU` |
| folds | `2, 3` |
| quantile | `0.50` |
| horizons | `1:96` |
| train origins | tail `3000` |
| likelihoods | AL and exAL |
| prior | `RHS_NS` |
| `tau0` | `1e-3` |
| intercept shrinkage | disabled |
| VB iterations | min `50`, max `100` |
| row chunk size | `512` |
| jobs per cell | `1` |

Fold 2 exact prior-P2 retest:

| Fold | L | Units | D | alpha | rho | input scale | Seeds |
|---:|---:|---:|---:|---:|---:|---:|---|
| 2 | 96 | `[120]` | 1 | 0.5 | 0.9 | 0.25 | `20260601:20260605` |

Fold 3 local refinement:

| Fold | L | Units | D | alpha | rho | input scale | Seeds |
|---:|---:|---:|---:|---|---|---|---|
| 3 | 96 | `[80]` | 1 | `0.4, 0.5` | `0.90, 0.97` | `0.25, 0.35, 0.50` | `20260601:20260605` |
| 3 | 96 | `[80, 80]` | 2 | `0.4, 0.5` | `0.90, 0.97` | `0.25, 0.35, 0.50` | `20260601:20260605` |

The fold-3 prior P2 selected geometry
`L=96, D=1, units=[80], alpha=0.5, rho=0.97, input_scale=0.35`
is included in the fold-3 surface and tagged as both `prior_p2_retest` and
`fold3_local_refine`.

Counts:

| Quantity | Count |
|---|---:|
| unique geometries | 25 |
| fold 2 experiments | 5 |
| fold 3 experiments | 120 |
| total experiments | 125 |

## Preparation Commands

Generate the tracked grid config:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/28_prepare_median_folds23_followup_grid.py \
  --template-grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_deep_targeted_20260603.yaml \
  --p2-registry-csv application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_p2_registry_20260603/median_selection_registry.csv \
  --output-grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml \
  --summary-output application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_followup_grid_20260605/summary.json \
  --grid-id pricefm_median_de_lu_folds23_followup_20260605 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_followup_20260605 \
  --run-root application/data_local/pricefm/runs/pricefm_median_de_lu_folds23_followup_20260605 \
  --region DE_LU \
  --seeds 20260601,20260602,20260603,20260604,20260605
```

Generate ignored per-cell configs:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml \
  --write
```

Dry-run the launcher:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml \
  --priorities 0 \
  --experiment-jobs 2 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run true \
  --max-experiments 3
```

## Launch Command

Use a persistent tmux session:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
tmux new-session -d -s pricefm_followup_20260605 \
  'cd /data/jaguir26/local/src/Article-Q-DESN && \
   /usr/bin/time -v \
     -o application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_followup_20260605/launch_logs/followup_full.time.log \
     application/data_local/pricefm/venv/bin/python \
     application/scripts/pricefm/13_run_desn_experiment_grid.py \
       --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml \
       --priorities 0 \
       --experiment-jobs 10 \
       --cell-jobs 1 \
       --build-windows true \
       --resume true \
       --dry-run false \
       > application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_followup_20260605/launch_logs/followup_full.stdout.log 2>&1'
```

## Post-Launch Summary

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/27_summarize_median_seed_robustness.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_followup_summary_20260605 \
  --regions DE_LU \
  --folds 2,3 \
  --selection-split val \
  --audit-split test \
  --unit original \
  --metric AQL
```

## Validation

Completed before launch:

- `test_pricefm_horizon_block_materializer.py`: 5 pass;
- `py_compile` for the prep, grid, launcher, and summarizer scripts;
- grid generation: 125 experiments;
- dry-run launcher: planned 3 cells successfully;
- manifest audit:
  - fold 2: 5 cells;
  - fold 3: 120 cells;
  - factors match the tables above.

## Decision Rule

Use validation metrics for selection:

1. rank by validation AQL mean across seeds;
2. inspect validation worst-case and seed standard deviation;
3. use test AQL only as an audit field;
4. do not promote a fold-3 spec unless it improves the validation criterion
   and does not show worse audit instability than the prior P2 candidate.

After this pass, the next step is to freeze fold-specific median specs and then
promote those fold-specific geometries to the multi-quantile run.

## Completed Run

The full follow-up launch completed successfully on 2026-06-06.

| Item | Value |
|---|---:|
| window builds | 125 / 125 |
| experiments | 125 / 125 |
| metric summaries | 125 |
| reports | 125 |
| failed cells | 0 |
| wall time | 4:14:32 |
| max RSS | 1,566,924 KB |
| `.rds/.rda/.RData` artifacts | 0 |

The launch status and timing logs are local ignored artifacts:

```text
application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_followup_20260605/launch_status.csv
application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_followup_20260605/launch_logs/followup_full.time.log
application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_followup_20260605/launch_logs/followup_full.stdout.log
```

## Registry And Summary Outputs

Post-run summary and validation-only registry commands:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/27_summarize_median_seed_robustness.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_followup_summary_20260605 \
  --regions DE_LU \
  --folds 2,3 \
  --selection-split val \
  --audit-split test \
  --unit original \
  --metric AQL

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/20_select_pricefm_desn_median_specs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_followup_registry_20260605 \
  --regions DE_LU \
  --folds 2,3 \
  --selection-split val \
  --selection-unit original \
  --selection-metric AQL \
  --selection-methods qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked \
  --require-complete true \
  --priorities 0
```

Ignored local outputs:

```text
application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_followup_summary_20260605/
application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_followup_registry_20260605/
```

Tracked compact snapshots:

```text
docs/implementation_notes/pricefm_de_lu_folds23_followup_median_selection_registry_snapshot_20260605.csv
docs/implementation_notes/pricefm_de_lu_folds23_followup_candidate_top_snapshot_20260605.csv
```

## Selected Median Specs

Selection used validation AQL on the original scale. Test metrics remain
audit-only.

| Fold | Method | Val AQL | Test AQL | Test RMSE | Experiment | L | Units | D | alpha | rho | input scale | seed |
|---:|---|---:|---:|---:|---|---:|---|---:|---:|---:|---:|---:|
| 2 | `qdesn_exal_rhs_ns_exact_chunked` | 6.194532 | 7.033291 | 21.263970 | `fup_f2_priorp2retest_l96_d1_n120_a0p5_r0p9_in0p25_seed20260603` | 96 | `[120]` | 1 | 0.5 | 0.9 | 0.25 | 20260603 |
| 3 | `qdesn_exal_rhs_ns_exact_chunked` | 6.738954 | 8.504556 | 26.900755 | `fup_f3_fold3localrefine_l96_d2_n80x80_a0p4_r0p9_in0p35_seed20260603` | 96 | `[80, 80]` | 2 | 0.4 | 0.9 | 0.35 | 20260603 |

Seed-robustness summary for the selected exAL geometries:

| Fold | Geometry | Seeds | Mean Val AQL | SD Val AQL | Worst Val AQL | Mean Test AQL | Worst Test AQL |
|---:|---|---:|---:|---:|---:|---:|---:|
| 2 | `L96 D1 [120] alpha0.5 rho0.9 input0.25` | 5 | 6.241857 | 0.027945 | 6.270861 | 6.950607 | 7.033291 |
| 3 | `L96 D2 [80,80] alpha0.4 rho0.9 input0.35` | 5 | 6.830907 | 0.084766 | 6.979310 | 8.584591 | 8.668810 |

## Promoted Quantile Grid

The fold-specific median winners were materialized into a tracked paper-quantile
promotion grid:

```text
application/config/pricefm_desn_experiment_grid_de_lu_folds23_followup_promoted_quantiles_20260605.yaml
```

The grid has 14 experiments: folds 2 and 3 crossed with paper quantiles
`0.10`, `0.25`, `0.45`, `0.50`, `0.55`, `0.75`, and `0.90`.

Generation command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py \
  --template-grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_registry_promoted_quantiles_20260602.yaml \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_followup_registry_20260605/median_selection_registry.csv \
  --output-grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_followup_promoted_quantiles_20260605.yaml \
  --grid-id pricefm_de_lu_folds23_followup_promoted_quantiles_20260605 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_de_lu_folds23_followup_promoted_quantiles_20260605 \
  --run-root application/data_local/pricefm/runs/pricefm_de_lu_folds23_followup_promoted_quantiles_20260605 \
  --quantiles 0.10,0.25,0.45,0.50,0.55,0.75,0.90 \
  --priority 0
```

Prepare and dry-run commands:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_followup_promoted_quantiles_20260605.yaml \
  --write

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_followup_promoted_quantiles_20260605.yaml \
  --priorities 0 \
  --experiment-jobs 2 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run true \
  --max-experiments 2
```

The dry run selected the first two fold-2 quantile cells successfully.

## Final Validation

Post-run validation:

- `27_summarize_median_seed_robustness.py`: passed.
- `20_select_pricefm_desn_median_specs.py`: passed with `125 / 125`
  complete cells.
- `21_prepare_pricefm_quantile_grid_from_median_registry.py`: generated
  14 promoted quantile experiments.
- `12_prepare_desn_experiment_grid.py --write`: generated ignored per-cell
  configs.
- `13_run_desn_experiment_grid.py --dry-run --max-experiments 2`: passed.
- `py_compile` passed for scripts `12`, `13`, `20`, `21`, `27`, and `28`.
- `pytest application/tests/test_pricefm_horizon_block_materializer.py
  application/tests/test_pricefm_desn_experiment_grid.py
  application/tests/test_pricefm_median_selection_registry.py -q`: 19 passed.
- `git diff --check`: passed.

## Promotion Decision

The follow-up median registry is now the preferred fold-2/fold-3 median source
for the next DE_LU paper-quantile launch.

Relative to the older fold-2/fold-3 registry, the follow-up changes are:

- fold 2: promote the retested prior-P2 `L96/D1/n120/input0.25` seed
  `20260603` candidate;
- fold 3: promote the new `L96/D2/[80,80]/alpha0.4/rho0.9/input0.35`
  seed `20260603` candidate.

The next operational step is to launch
`application/config/pricefm_desn_experiment_grid_de_lu_folds23_followup_promoted_quantiles_20260605.yaml`
and then compare the resulting seven-quantile outputs against the local
PriceFM Phase-I fold references.
