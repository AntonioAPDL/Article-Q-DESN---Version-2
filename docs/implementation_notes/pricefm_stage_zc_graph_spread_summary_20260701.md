# PriceFM Stage-ZC Graph Spread-Summary Diagnostics And Probe

Date: 2026-07-01

## Purpose

Stage ZC followed the negative Stage-ZB graph-direct result.  Stage ZB proved
that the direct graph-neighbor path was technically launchable, but the
full-budget PL fold-3 result was not scientifically competitive.  Stage ZC
therefore did not broaden the graph-direct recipe.  It first diagnosed why raw
neighbor columns were risky, then tested one compact alternative:

```text
graph_neighbor_spread_summary
```

The spread-summary policy keeps the target-region lag/lead features and replaces
raw direct neighbor columns with compact neighbor-minus-target summaries.  This
is still a target-region forecast; neighboring regions are used only as
covariates.

## Diagnostic Gate

Diagnostic script:

```text
application/scripts/pricefm/91_diagnose_pricefm_stage_zc_graph_design.py
```

Ignored diagnostic outputs:

```text
application/data_local/pricefm/authoritative/pricefm_stage_zc_graph_design_diagnostics_20260701/
```

Main diagnostic results:

| Field | Value |
|---|---:|
| Stage-ZB Q-DESN AL test AQL | 10.1448 |
| Current target-only registry test AQL | 8.4032 |
| Cached PriceFM test AQL | 7.6902 |
| Stage-ZB delta vs current | 1.7415 |
| Stage-ZB delta vs PriceFM | 2.4545 |
| Mean neighbor-target price correlation | 0.7509 |
| Neighbor/target lag norm ratio | 1.6249 |
| Neighbor/target lead norm ratio | 1.2445 |

Decision from the diagnostic gate:

```text
direct_recipe_promotable = false
recommended_next_contract = graph_neighbor_spread_summary
diagnostic_supports_revised_graph_contract = true
```

Interpretation: the graph information is strongly related to the target region,
but direct raw neighbor blocks are larger and highly correlated with target
blocks.  A compact relative-spread representation was therefore the only
approved next test.

## Implemented Feature Policy

New feature policy:

```text
graph_neighbor_spread_summary
```

Contract:

- target response remains `target_region_Y_only`;
- target lag features are retained: `price`, `load`, `solar`, `wind`;
- target lead features are retained: `load`, `solar`, `wind`;
- neighbor lag features considered for summaries: `price`, `load`;
- neighbor lead features considered for summaries: `load`, `wind`;
- summary statistics are `mean_diff`, `sd`, `min_diff`, `max_diff`;
- neighbor responses are never used as inputs;
- target future price is not used as an input;
- lead covariates remain labeled `realized_ex_post`;
- feature provenance records `target` and `neighbor_summary` roles.

For PL fold 3, the graph neighbors are:

```text
CZ, DE_LU, LT, SE_4, SK
```

The full-budget adapter provenance had 23 rows:

| Source role | Block | Count |
|---|---|---:|
| `target` | `lag` | 4 |
| `target` | `lead` | 3 |
| `neighbor_summary` | `lag` | 8 |
| `neighbor_summary` | `lead` | 8 |

The model design used 231 features after the direct-horizon adapter feature-map
construction.

## Commands

Prepare and run the diagnostic:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/91_diagnose_pricefm_stage_zc_graph_design.py \
  --force true
```

Prepare the one-cell smoke grid:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/92_prepare_pricefm_stage_zc_graph_spread_smoke.py \
  --force true
```

Smoke dry run:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_zc_graph_spread_smoke_20260701.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run true \
  --resume true \
  --force false
```

Smoke launch:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/authoritative/pricefm_stage_zc_graph_spread_smoke_20260701/smoke.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_zc_graph_spread_smoke_20260701.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run false \
  --resume true \
  --force true
```

Prepare the full-budget probe after the smoke passed:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/93_prepare_pricefm_stage_zc_graph_spread_fullbudget.py \
  --force true
```

Full-budget dry run:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_zc_graph_spread_fullbudget_pl_f3_20260701.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run true \
  --resume true \
  --force false
```

Full-budget launch:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/authoritative/pricefm_stage_zc_graph_spread_fullbudget_pl_f3_20260701/fullbudget.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_zc_graph_spread_fullbudget_pl_f3_20260701.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run false \
  --resume true \
  --force true
```

## Generated Outputs

Ignored planning outputs:

```text
application/data_local/pricefm/authoritative/pricefm_stage_zc_graph_design_diagnostics_20260701/
application/data_local/pricefm/authoritative/pricefm_stage_zc_graph_spread_smoke_20260701/
application/data_local/pricefm/authoritative/pricefm_stage_zc_graph_spread_fullbudget_pl_f3_20260701/
```

Ignored run outputs:

```text
application/data_local/pricefm/runs/pricefm_stage_zc_graph_spread_smoke_20260701/
application/data_local/pricefm/runs/pricefm_stage_zc_graph_spread_fullbudget_pl_f3_20260701/
```

Full-budget model report:

```text
application/data_local/pricefm/runs/pricefm_stage_zc_graph_spread_fullbudget_pl_f3_20260701/stagezc_graph_spread_pl_f3_l096_d1_n120_fullbudget_seed20260701/cells/region=PL/fold=3/model/report.md
```

Full-budget figures:

```text
application/data_local/pricefm/runs/pricefm_stage_zc_graph_spread_fullbudget_pl_f3_20260701/stagezc_graph_spread_pl_f3_l096_d1_n120_fullbudget_seed20260701/cells/region=PL/fold=3/model/figures/
```

## Smoke Result

The smoke used `train_origin_limit = 50` and completed successfully.

| Check | Result |
|---|---:|
| Window build status | completed |
| Experiment status | completed |
| Cell status | completed |
| Nonzero return codes | 0 |
| Smoke wall time | 154.711 s |
| Binary fit artifacts retained | 0 |
| Methods summarized | 7 |

Original-unit smoke test metrics:

| Method | Test AQL |
|---|---:|
| `normal_rhs_ns` | 11.1366 |
| `qdesn_al_rhs_ns_exact_chunked` | 11.2723 |
| `qdesn_exal_rhs_ns_exact_chunked` | 11.2750 |
| `naive3_prev7_avg` | 12.8429 |

The smoke passed its technical gate and justified one full-budget probe.  It was
not used for scientific promotion.

## Full-Budget Run Status

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
| Design features | 231 |
| Full launcher wall time | 23:36.78 |
| Model wall time | 18:43.61 |
| Max RSS | 1,428,608 KB |
| Run directory size after hygiene | 42 MB |
| Binary fit artifacts retained | 0 |
| `X_*.csv` matrices retained after success | 0 |

As in Stage ZB, the `train_origin_limit = 3000` cap selected all available PL
fold-3 training origins.

## Original-Unit Metrics

Test metrics:

| Method | Test AQL | Test MAE | Test RMSE |
|---|---:|---:|---:|
| `qdesn_al_rhs_ns_exact_chunked` | 10.1560 | 20.3121 | 34.4095 |
| `qdesn_exal_rhs_ns_exact_chunked` | 10.1809 | 20.3619 | 34.5172 |
| `normal_rhs_ns` | 10.8092 | 21.6185 | 33.3431 |
| `normal_scaled_ridge` | 12.0413 | 24.0825 | 35.5131 |
| `naive3_prev7_avg` | 12.3942 | 24.7883 | 39.2303 |
| `naive1_prev_day` | 13.3989 | 26.7978 | 43.8661 |
| `naive2_prev3_avg` | 13.6075 | 27.2150 | 42.9741 |

Validation metrics:

| Method | Validation AQL | Validation MAE | Validation RMSE |
|---|---:|---:|---:|
| `normal_rhs_ns` | 9.1682 | 18.3363 | 26.2947 |
| `qdesn_exal_rhs_ns_exact_chunked` | 9.3255 | 18.6510 | 28.7148 |
| `qdesn_al_rhs_ns_exact_chunked` | 9.3339 | 18.6678 | 28.8070 |
| `normal_scaled_ridge` | 10.5298 | 21.0597 | 28.8845 |
| `naive3_prev7_avg` | 10.9703 | 21.9406 | 32.1540 |

## Horizon Groups

| Horizon group | Best method | Best AQL | Q-DESN AL AQL |
|---|---|---:|---:|
| 1-24 | `qdesn_exal_rhs_ns_exact_chunked` | 5.9249 | 5.9481 |
| 25-48 | `qdesn_al_rhs_ns_exact_chunked` | 10.0576 | 10.0576 |
| 49-72 | `qdesn_al_rhs_ns_exact_chunked` | 13.9148 | 13.9148 |
| 73-96 | `naive3_prev7_avg` | 10.3083 | 10.7037 |

The spread-summary Q-DESN is competitive within the run across horizons 1-72,
but it still loses late horizons 73-96 to the simple previous-week average.

## Baseline Context

| Source | Test AQL |
|---|---:|
| Cached PriceFM row | 7.6902 |
| Current target-only Q-DESN registry row | 8.4032 |
| Stage-ZB graph-direct Q-DESN AL | 10.1448 |
| Stage-ZC graph-spread Q-DESN AL | 10.1560 |
| Stage-ZC graph-spread best naive | 12.3942 |

Relative to baselines:

| Comparison | Delta AQL |
|---|---:|
| Stage-ZC Q-DESN AL minus PriceFM | 2.4658 |
| Stage-ZC Q-DESN AL minus current target-only registry | 1.7528 |
| Stage-ZC Q-DESN AL minus Stage-ZB graph-direct | 0.0113 |
| Stage-ZC Q-DESN AL minus best Stage-ZC naive | -2.2381 |

Stage ZC improves substantially over the naive baselines, but it does not
recover the current target-only registry row and does not improve over the
Stage-ZB graph-direct candidate.

## Validation Checks

Exact chunking gate:

| Likelihood | Prior | Tau | Rows | Max beta mean diff | Max beta cov diff | Max train pred diff | Tolerance | Passed |
|---|---|---:|---:|---:|---:|---:|---:|---|
| AL | RHS_NS | 0.5 | 1,000 | 0 | 0 | 0 | 1e-6 | true |

Model fit summary:

| Method | Converged | Iterations | Train seconds |
|---|---:|---:|---:|
| `normal_scaled_ridge` | true | 1 | 8.070 |
| `normal_rhs_ns` | false | 100 | 11.287 |
| `qdesn_al_rhs_ns_exact_chunked` | true | 50 | 517.842 |
| `qdesn_exal_rhs_ns_exact_chunked` | true | 50 | 518.807 |

Warm-start summary:

| Method | Init source | Fallback used | Converged | Iterations |
|---|---|---:|---:|---:|
| `normal_rhs_ns` | `normal_scaled_ridge` | false | false | 100 |
| `qdesn_al_rhs_ns_exact_chunked` | `normal_rhs_ns` | false | true | 50 |
| `qdesn_exal_rhs_ns_exact_chunked` | `qdesn_al_tau_0.5` | false | true | 50 |

Focused tests:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_zc_graph_spread_fullbudget.py \
  application/tests/test_pricefm_stage_zc_graph_spread_smoke.py \
  application/tests/test_pricefm_stage_zc_graph_design_diagnostics.py \
  application/tests/test_pricefm_desn_adapter_graph_spread_summary.py \
  application/tests/test_pricefm_graph.py -q
```

Result before the full-budget launch: 20 passed.

## Decision

Do not promote `graph_neighbor_spread_summary` for PL fold 3, and do not expand
this specific graph-spread recipe to the broader graph-gap candidate panel.

Stage ZC is technically successful:

- diagnostics are reproducible and do not fit models;
- the new feature policy has explicit provenance and leakage labels;
- smoke and full-budget runs complete;
- exact chunking remains equivalent;
- artifact hygiene removes `X_*.csv` and binary fit-state files after success.

Scientifically, however, the compact spread summaries do not solve the PL fold-3
gap.  They are slightly worse than direct neighbor columns, much worse than the
current target-only selected row, and much worse than the cached PriceFM result.
This is negative evidence for graph-neighbor covariates under the current
small-reservoir PL fold-3 geometry, not evidence against all spatial input
designs.

The next stage should not broaden `graph_neighbor_direct` or
`graph_neighbor_spread_summary`.  If graph inputs are revisited, the next design
should change the representation more materially, for example by combining
region-specific model selection with a larger-capacity graph-aware reservoir or
by testing graph inputs only on folds where target-only selection is already
near the PriceFM frontier.
