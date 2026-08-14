# PriceFM Stage-ZB Graph-Direct Full-Budget PL Fold-3 Probe

Date: 2026-07-01

## Purpose

Stage ZB is the first full-training-budget run using the new
`graph_neighbor_direct` adapter introduced in Stage ZA.  The stage is deliberately
one cell: `PL` fold 3, median only, all horizons, and the current selected
target-only DESN geometry.  This isolates the information-set change from
ordinary reservoir/model-selection changes.

The candidate keeps:

- `lag_window = 96`;
- `depth = 1`;
- `units = [120]`;
- `alpha = 0.5`;
- `rho = 0.9`;
- `input_scale = 0.25`;
- `tau0 = 0.001`;
- `seed = 20260603`;
- RHS_NS prior with non-shrunk intercept;
- Q-DESN AL/exAL exact chunked VB;
- normal DESN scaled-ridge and RHS_NS baselines.

The only substantive design change relative to the target-only anchor is the
feature policy:

```text
graph_neighbor_direct
```

Neighbor inputs are `CZ`, `DE_LU`, `LT`, `SE_4`, and `SK`, with direct neighbor
lag features `price, load` and direct neighbor lead features `load, wind`.

## Commands

Prepare the one-cell launch config:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/90_prepare_pricefm_stage_zb_graph_direct_fullbudget.py \
  --force true
```

Dry-run the launcher:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_zb_graph_direct_fullbudget_pl_f3_20260701.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run true \
  --resume true \
  --force false
```

Launch the full-budget probe:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/authoritative/pricefm_stage_zb_graph_direct_fullbudget_pl_f3_20260701/fullbudget_probe.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_zb_graph_direct_fullbudget_pl_f3_20260701.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run false \
  --resume true \
  --force true
```

## Generated Outputs

Planning outputs:

```text
application/data_local/pricefm/authoritative/pricefm_stage_zb_graph_direct_fullbudget_pl_f3_20260701/
```

Run outputs:

```text
application/data_local/pricefm/runs/pricefm_stage_zb_graph_direct_fullbudget_pl_f3_20260701/stagezb_graph_direct_pl_f3_l096_d1_n120_anchor_seed20260603/
```

Model report:

```text
application/data_local/pricefm/runs/pricefm_stage_zb_graph_direct_fullbudget_pl_f3_20260701/stagezb_graph_direct_pl_f3_l096_d1_n120_anchor_seed20260603/cells/region=PL/fold=3/model/report.md
```

Diagnostic figures:

```text
application/data_local/pricefm/runs/pricefm_stage_zb_graph_direct_fullbudget_pl_f3_20260701/stagezb_graph_direct_pl_f3_l096_d1_n120_anchor_seed20260603/cells/region=PL/fold=3/model/figures/
```

## Run Status

| Check | Result |
|---|---:|
| Window build status | completed |
| Experiment status | completed |
| Cell status | completed |
| Nonzero return codes | 0 |
| Train origins available | 1,215 |
| Train origins selected | 1,215 |
| Training rows | 116,640 |
| Validation rows | 11,808 |
| Test rows | 11,712 |
| Design features | 233 |
| Full launcher wall time | 24:13.71 |
| Model wall time | 19:05.87 |
| Max RSS | 1,239,456 KB |
| Run directory size after hygiene | 42 MB |
| Binary fit artifacts retained | 0 |
| `X_*.csv` matrices retained after success | 0 |

The `train_origin_limit = 3000` cap is the project-standard full-budget cap for
PriceFM runs.  For `PL` fold 3, only 1,215 train origins are available, so the
run used the complete available training window.

## Original-Unit Metrics

Test metrics:

| Method | Test AQL | Test MAE | Test RMSE |
|---|---:|---:|---:|
| `qdesn_al_rhs_ns_exact_chunked` | 10.1448 | 20.2895 | 34.7566 |
| `qdesn_exal_rhs_ns_exact_chunked` | 10.1710 | 20.3420 | 34.8806 |
| `normal_rhs_ns` | 10.8529 | 21.7058 | 33.6207 |
| `normal_scaled_ridge` | 12.0809 | 24.1618 | 35.6537 |
| `naive3_prev7_avg` | 12.3942 | 24.7883 | 39.2303 |
| `naive1_prev_day` | 13.3989 | 26.7978 | 43.8661 |
| `naive2_prev3_avg` | 13.6075 | 27.2150 | 42.9741 |

Validation metrics:

| Method | Validation AQL | Validation MAE | Validation RMSE |
|---|---:|---:|---:|
| `normal_rhs_ns` | 9.1897 | 18.3795 | 26.2842 |
| `qdesn_al_rhs_ns_exact_chunked` | 9.3893 | 18.7787 | 29.0098 |
| `qdesn_exal_rhs_ns_exact_chunked` | 9.4046 | 18.8093 | 29.0258 |
| `normal_scaled_ridge` | 10.5257 | 21.0515 | 29.1289 |
| `naive3_prev7_avg` | 10.9703 | 21.9406 | 32.1540 |

## Horizon Groups

The graph-direct Q-DESN is strongest in the early and middle horizons but does
not solve the late-horizon weakness.

| Horizon group | Best method | Best AQL | Q-DESN AL AQL |
|---|---|---:|---:|
| 1-24 | `qdesn_exal_rhs_ns_exact_chunked` | 5.7636 | 5.8164 |
| 25-48 | `qdesn_al_rhs_ns_exact_chunked` | 9.9702 | 9.9702 |
| 49-72 | `normal_rhs_ns` | 14.0908 | 14.1822 |
| 73-96 | `naive3_prev7_avg` | 10.3083 | 10.6102 |

## Baseline Context

The Stage-Z graph contract for the same region/fold reported:

| Source | Test AQL |
|---|---:|
| Current target-only Q-DESN registry row | 8.4032 |
| Cached PriceFM row | 7.6902 |
| Stage-ZB graph-direct Q-DESN AL | 10.1448 |

The older Stage-C target-only anchor geometry had median test AQL about 10.1237
in its own run record.  Against that geometry-only anchor, the Stage-ZB direct
neighbor information set is essentially neutral to slightly worse.  Against the
current registry and PriceFM baselines, Stage ZB is clearly not competitive.

## Validation Checks

Exact chunking gate:

| Likelihood | Prior | Tau | Rows | Max beta mean diff | Max beta cov diff | Max train pred diff | Tolerance | Passed |
|---|---|---:|---:|---:|---:|---:|---:|---|
| AL | RHS_NS | 0.5 | 1,000 | 0 | 0 | 0 | 1e-6 | true |

Focused tests:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_zb_graph_direct_fullbudget.py \
  application/tests/test_pricefm_stage_za_graph_adapter_smoke.py \
  application/tests/test_pricefm_desn_experiment_grid.py \
  application/tests/test_pricefm_full_run_orchestrator.py -q
```

Result: 35 passed.

Broader graph/grid/orchestrator regression:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_desn_adapter.py \
  application/tests/test_pricefm_desn_adapter_graph_khop.py \
  application/tests/test_pricefm_desn_adapter_graph_summary.py \
  application/tests/test_pricefm_desn_adapter_graph_neighbor_direct.py \
  application/tests/test_pricefm_desn_experiment_grid.py \
  application/tests/test_pricefm_full_run_orchestrator.py \
  application/tests/test_pricefm_graph.py \
  application/tests/test_pricefm_stage_z_design_contracts.py \
  application/tests/test_pricefm_stage_za_graph_adapter_smoke.py \
  application/tests/test_pricefm_stage_zb_graph_direct_fullbudget.py -q
```

## Decision

Do not promote this Stage-ZB graph-direct row and do not expand the current
graph-direct design to all six graph-gap rows.

Stage ZB proves the full-budget graph-direct path is technically ready:

- graph-neighbor windows are built for all required active regions;
- feature provenance and leakage contracts are available;
- full-budget model fitting completes;
- exact chunking remains equivalent;
- artifact hygiene leaves a small reproducible result directory.

Scientifically, however, this specific design does not rescue `PL` fold 3.  The
neighbor-direct information set improves over naive baselines but is worse than
the current registry row and PriceFM.  The next stage should revise the graph
design rather than scale this exact direct-neighbor feature recipe.
