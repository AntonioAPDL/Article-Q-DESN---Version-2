# PriceFM Stage-B Region Expansion Batch 1

Date: 2026-06-16

## Objective

Expand beyond the frozen six-region graph/local panel without overfitting the
current weak folds. This stage prepares and launches a local-first median-only
selection batch for new regions. Graph-neighbor A/B and paper-quantile
promotion are intentionally deferred until the local median closeout exists.

## Frozen Baseline

The current authoritative six-region median registry remains:

```text
application/data_local/pricefm/authoritative/pricefm_region_panel_median_graph_local_closeout_20260614/merged_selection_registry.csv
```

The graph/local seven-quantile PriceFM comparison remains:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_region_panel_graph_local_20260614
```

The `IT_SICI` fold-3 rescue seed gate completed successfully but failed
promotion because only `2/3` seeds improved validation AQL. Therefore no patch
was applied to the frozen registry.

## Batch Scope

Stage-B batch 1 uses eight uncovered regions selected to span graph complexity,
Phase-I difficulty, and price-distribution behavior:

| Region | Role |
|---|---|
| `PT` | Low graph degree edge case. |
| `BG` | Hard Phase-I AQL with low graph degree. |
| `ES` | Iberian medium-graph pair with `PT`. |
| `FR` | High-volatility graph hub. |
| `FI` | Nordic negative-price/graph behavior. |
| `IT_NORD` | Italian hub with high price spread. |
| `AT` | High graph degree, hub-adjacent. |
| `PL` | High graph degree and harder Phase-I AQL. |

All three folds are included. The target quantile is median only, `tau = 0.50`.

## Method Scope

The first launch is local-only:

```text
feature_policy = target_only
spatial_information_set = local_only_not_pricefm_graph
selection split = validation
audit split = test
metric = AQL
```

Priority 0 contains three transferred local geometries:

1. D1, 120 units, `alpha=0.50`, `rho=0.90`, `input_scale=0.50`.
2. D1, 120 units, `alpha=0.50`, `rho=0.90`, `input_scale=0.25`.
3. D2, units `[80, 80]`, `alpha=0.40`, `rho=0.90`,
   `input_scale=0.35`.

Priority 1 contains optional diagnostics and must not launch until priority 0
has a completed closeout.

## Generated Local Artifacts

The tracked preparer is:

```text
application/scripts/pricefm/46_prepare_pricefm_stage_b_region_batch.py
```

It writes ignored local artifacts:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_b_median_batch1_20260616.yaml
application/data_local/pricefm/authoritative/pricefm_stage_b_median_batch1_plan_20260616/
application/data_local/pricefm/experiment_grids/pricefm_stage_b_median_batch1_20260616/
application/data_local/pricefm/runs/pricefm_stage_b_median_batch1_20260616/
```

Preparation completed successfully. The generated local summary reports:

```text
n_regions: 8
n_experiments: 6
n_priority0_experiments: 3
n_priority0_cells: 72
n_all_cells: 144
```

Priority-0 dry-run passed. It selected exactly:

```text
stageb_core_l096_d1_n120_a0p5_r0p9_in0p50_seed20260601
stageb_d2_l096_d2_n080x080_a0p4_r0p9_in0p35_seed20260603
stageb_lowinput_l096_d1_n120_a0p5_r0p9_in0p25_seed20260603
```

Priority 0 was launched in a detached tmux session:

```text
pricefm_stageb_batch1_p0_0616
```

Runtime logs:

```text
application/data_local/pricefm/experiment_grids/pricefm_stage_b_median_batch1_20260616/tmux_priority0.log
application/data_local/pricefm/experiment_grids/pricefm_stage_b_median_batch1_20260616/tmux_priority0.time.log
application/data_local/pricefm/experiment_grids/pricefm_stage_b_median_batch1_20260616/tmux_priority0.exit
```

## Commands

Prepare the batch grid and manifest:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/46_prepare_pricefm_stage_b_region_batch.py \
  --write true
```

Materialize generated configs:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_b_median_batch1_20260616.yaml \
  --write
```

Dry-run priority 0:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_b_median_batch1_20260616.yaml \
  --priorities 0 \
  --experiment-jobs 3 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run true
```

Launch priority 0 in a detached tmux session only after the dry-run passes.

## Closeout Plan

Priority 0 completed successfully:

```text
n_metric_summaries: 72
window_build elapsed: 183.05s
stageb_core_l096_d1_n120_a0p5_r0p9_in0p50_seed20260601 elapsed: 34002.31s
stageb_d2_l096_d2_n080x080_a0p4_r0p9_in0p35_seed20260603 elapsed: 27366.40s
stageb_lowinput_l096_d1_n120_a0p5_r0p9_in0p25_seed20260603 elapsed: 34603.90s
```

The validation-selected median registry was frozen with:

```text
application/data_local/pricefm/authoritative/pricefm_stage_b_median_batch1_registry_20260616/
```

Registry summary:

```text
n_region_folds: 24
n_regions: 8
selected qdesn_exal_rhs_ns_exact_chunked rows: 15
selected qdesn_al_rhs_ns_exact_chunked rows: 9
missing selected-method coverage rows: 0
```

The Stage-B closeout helper is:

```text
application/scripts/pricefm/47_closeout_pricefm_stage_b_median_registry.py
```

It appends Stage-B rows to the workflow without requiring that new regions
already exist in the previous six-region registry. The previous registry is
used only as context through an `already_in_previous_registry` flag. The helper
writes ignored local artifacts:

```text
application/data_local/pricefm/authoritative/pricefm_stage_b_median_batch1_closeout_20260616/
```

Closeout summary:

```text
n_region_folds: 24
n_regions: 8
n_beats_best_naive_test: 19
mean_selected_test_AQL: 8.8132
mean_best_naive_test_AQL: 10.9854
region triage: local_strong 5, local_promising 2, local_fail_rescue 1
```

Region-level triage:

| Region | Folds | Test Beats Best Naive | Mean Selected Test AQL | Mean Best Naive Test AQL | Triage |
|---|---:|---:|---:|---:|---|
| `AT` | 3 | 3 | 8.9821 | 10.4415 | `local_strong` |
| `BG` | 3 | 2 | 12.0250 | 12.0305 | `local_promising` |
| `ES` | 3 | 3 | 6.7880 | 9.9141 | `local_strong` |
| `FI` | 3 | 3 | 11.0551 | 17.6511 | `local_strong` |
| `FR` | 3 | 3 | 7.1421 | 10.0794 | `local_strong` |
| `IT_NORD` | 3 | 0 | 7.0775 | 5.9203 | `local_fail_rescue` |
| `PL` | 3 | 3 | 9.4536 | 11.9485 | `local_strong` |
| `PT` | 3 | 2 | 7.9823 | 9.8975 | `local_promising` |

The immediate follow-up is a median-only promoted rerun, not the full seven
paper quantiles. This keeps the Stage-B PriceFM Phase-I comparison aligned to
the tau `0.50` registry and avoids spending a seven-quantile launch before the
new regions are benchmarked.

The promoted median grid is:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_b_median_tau0p50_20260616.yaml
application/data_local/pricefm/experiment_grids/pricefm_stage_b_median_tau0p50_20260616/
application/data_local/pricefm/runs/pricefm_stage_b_median_tau0p50_20260616/
```

It contains 24 experiments, one selected median model for each Stage-B
region/fold row. Dry-run passed and the real run was launched in detached tmux
session:

```text
pricefm_stageb_median_tau0p50_0616
```

Runtime logs:

```text
application/data_local/pricefm/experiment_grids/pricefm_stage_b_median_tau0p50_20260616/tmux.log
application/data_local/pricefm/experiment_grids/pricefm_stage_b_median_tau0p50_20260616/tmux.time.log
application/data_local/pricefm/experiment_grids/pricefm_stage_b_median_tau0p50_20260616/tmux.exit
```

The median-only promoted rerun completed successfully:

```text
n_metric_summaries: 24
tmux exit status: 0
wall time: 1:15:02
max RSS: 1,546,996 KB
```

The promoted outputs were summarized under:

```text
application/data_local/pricefm/authoritative/pricefm_stage_b_median_tau0p50_outputs_20260616/
```

The fold-aligned PriceFM Phase-I comparison completed under:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_b_median_tau0p50_20260616/
```

Comparison status:

```text
PriceFM Phase-I regenerations: 24 completed
DESN/Q-DESN comparisons: 24 completed
quantiles compared: 0.50 only
```

Macro original-scale test metrics:

| Method | AQL | MAE | RMSE |
|---|---:|---:|---:|
| `qdesn_exal_rhs_ns_exact_chunked` | 8.8075 | 17.6150 | 25.3812 |
| `qdesn_al_rhs_ns_exact_chunked` | 8.8331 | 17.6661 | 25.3895 |
| `pricefm_phase1_pretraining` | 9.0174 | 18.0348 | 26.3869 |
| `normal_rhs_ns` | 10.3485 | 20.6969 | 27.9574 |
| `normal_scaled_ridge` | 19.8139 | 39.6277 | 55.2597 |

Best local Q-DESN per region/fold versus PriceFM Phase-I:

```text
qdesn_beats_pricefm: 14/24
qdesn_lags_pricefm: 10/24
mean best-Q-DESN AQL: 8.7847
mean PriceFM Phase-I AQL: 9.0174
mean absolute delta: -0.2326
mean relative delta: -3.23%
```

Region-level mean deltas for best local Q-DESN versus PriceFM Phase-I:

| Region | Mean Q-DESN AQL | Mean PriceFM AQL | Mean Delta | Mean Relative Delta |
|---|---:|---:|---:|---:|
| `FR` | 7.1146 | 9.3601 | -2.2455 | -23.40% |
| `IT_NORD` | 6.9318 | 8.4836 | -1.5518 | -18.76% |
| `ES` | 6.7820 | 7.6862 | -0.9042 | -11.80% |
| `PT` | 7.9792 | 8.4722 | -0.4930 | -5.82% |
| `AT` | 8.9635 | 8.6208 | 0.3428 | 4.35% |
| `PL` | 9.4267 | 8.8196 | 0.6072 | 6.91% |
| `FI` | 11.0551 | 10.1639 | 0.8912 | 8.70% |
| `BG` | 12.0250 | 10.5327 | 1.4923 | 13.95% |

The comparison required a small script generalization:
`18_compare_pricefm_phase1_desn_quantiles.py` and
`36_compare_pricefm_region_panel_quantiles.py` now accept `--quantiles`.
This is necessary because Stage-B median promotion intentionally emits only
tau `0.50`, while the previous comparison path assumed the seven-paper-quantile
grid. The default remains the seven-paper-quantile grid.

After this median-only comparison:

1. Treat the local-only Stage-B median result as promising but heterogeneous.
2. Do not treat the tau `0.50` result as a seven-quantile paper-grid result.
3. Decide whether `BG`, `FI`, `PL`, and `AT` require graph-neighbor or
   fold-specific rescue before paper-quantile promotion.
4. Decide whether `IT_NORD` still needs rescue: it failed the local-vs-naive
   closeout gate but beat PriceFM Phase-I on all three median folds.
5. Prepare graph-neighbor A/B from the Stage-B local registry only if the
   local median comparison says spatial covariates are needed.
6. Promote only validation-selected, stable rows to the seven PriceFM paper
   quantiles.
7. Compare to PriceFM Phase-I using the existing apples-to-apples comparison
   scripts.

## Stop Gates

- Do not select by test AQL.
- Do not launch graph-neighbor A/B before local median winners exist.
- Do not launch priority 1 before priority 0 is summarized.
- Do not promote paper quantiles before a validation-selected registry is
  frozen.
- Do not treat `IT_NORD` as solved by the local-only Stage-B run.
- Do not keep large `.rds`, `.rda`, `.RData`, or adapter matrix artifacts after
  successful cells.
