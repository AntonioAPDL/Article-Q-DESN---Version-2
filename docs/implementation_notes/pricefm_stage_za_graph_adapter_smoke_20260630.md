# PriceFM Stage-ZA Graph Adapter Smoke

Date: 2026-06-30

## Purpose

Stage ZA implements the first concrete graph-adapter step after the Stage-Z
contracts.  It adds a reusable `graph_neighbor_direct` feature policy and
prepares a one-cell smoke grid for the largest graph-information-gap row.  It
does not launch model fits or a broad grid.

The stage is intentionally narrow because Stage-X and Stage-Y showed that broad
parameter sweeps were no longer the right tool.  The plausible remaining issue
for the selected graph-gap rows is an information-set mismatch, so this stage
tests the feature-adapter path before spending model-selection compute.

## Implemented Adapter

New feature policy:

```text
graph_neighbor_direct
```

Contract:

- target response remains the target region only;
- target lag and lead features are preserved;
- selected neighbor lag and lead features are appended directly;
- active neighbors come from the PriceFM graph and can be explicitly narrowed;
- all active regions must have identical anchors and compatible lag/lead shapes;
- feature provenance is written to `feature_provenance.csv`;
- the leakage contract records that neighbor responses are not used as inputs.

This differs from previous graph policies:

| Policy | Role |
|---|---|
| `graph_khop` | raw full k-hop concatenation |
| `graph_summary_mean` / `graph_summary_mean_std` | compact neighbor summaries |
| `graph_neighbor_direct` | selected direct neighbor covariates with explicit provenance |

## Orchestration Wiring

The shared graph helper now resolves required window regions for all graph
policies, including:

- `graph_khop`;
- `graph_summary_mean`;
- `graph_summary_mean_std`;
- `graph_neighbor_direct`.

This wiring is used by:

- the adapter;
- the full-run missing-window gate;
- the experiment-grid launcher window prebuild step.

## Reproducible Commands

Prepare the Stage-ZA smoke grid:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/89_prepare_pricefm_stage_za_graph_adapter_smoke.py \
  --force true
```

Dry-run the generated one-cell grid:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_za_graph_adapter_smoke_20260630.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run true \
  --resume true \
  --force false
```

Build only the adapter, not the model fit:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/authoritative/pricefm_stage_za_graph_adapter_smoke_20260630/adapter_build.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/07_build_desn_direct_horizon_adapter.py \
  --smoke-config application/data_local/pricefm/runs/pricefm_stage_za_graph_adapter_smoke_20260630/stageza_graph_direct_pl_f3_l096_d1_n120_seed20260630/cells/region=PL/fold=3/config.yaml \
  --force true
```

After the adapter smoke, the generated `X_*.csv` matrices were removed from the
ignored Stage-ZA adapter directory.  The manifests, rows, responses, provenance,
and timing log were retained.

## Generated Outputs

Stage-ZA planning outputs are ignored locally:

```text
application/data_local/pricefm/authoritative/pricefm_stage_za_graph_adapter_smoke_20260630/
```

Generated smoke grid config:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_za_graph_adapter_smoke_20260630.yaml
```

Generated smoke run root:

```text
application/data_local/pricefm/runs/pricefm_stage_za_graph_adapter_smoke_20260630/
```

The smoke manifest intentionally records `launch_ready = false`.  That value is
a guardrail, not a failure: Stage ZA is allowed to write the launch config and
prove the adapter can be built, but model fitting remains a separate explicit
decision after the dry-run and provenance checks are inspected.

## Smoke Specification

| Field | Value |
|---|---|
| Region | `PL` |
| Fold | `3` |
| Quantile | `0.5` |
| Horizons | `1:96` |
| Feature policy | `graph_neighbor_direct` |
| Neighbor regions | `CZ`, `DE_LU`, `LT`, `SE_4`, `SK` |
| Target lag features | `price`, `load`, `solar`, `wind` |
| Target lead features | `load`, `solar`, `wind` |
| Neighbor lag features | `price`, `load` |
| Neighbor lead features | `load`, `wind` |
| Train-origin cap | `50` |
| Feature map | `window_reservoir_v1` |
| Reservoir units | `120` |

## Adapter Smoke Result

| Check | Result |
|---|---:|
| Adapter build completed | true |
| Model fit launched | false |
| Train rows | 4,800 |
| Validation rows | 11,808 |
| Test rows | 11,712 |
| Design features | 233 |
| Feature provenance rows | 27 |
| Neighbor regions | 5 |
| Lag feature count before reservoir | 14 |
| Lead feature count before reservoir | 13 |
| Adapter directory after matrix cleanup | 5.3 MB |

Leakage/provenance contract:

- response source is `target_region_Y_only`;
- active regions are anchor-aligned;
- neighbor responses are not used as inputs;
- target future price is not used as an input;
- lead covariates remain labeled `realized_ex_post`.

## One-Cell Model Smoke Closeout

After the adapter-only smoke, the approved one-cell model smoke was launched:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/authoritative/pricefm_stage_za_graph_adapter_smoke_20260630/model_smoke_rerun.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_za_graph_adapter_smoke_20260630.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run false \
  --resume true \
  --force true
```

The first non-forced launch attempt correctly exposed a resume-mode hygiene
bug: `adapter_manifest.json` existed from the adapter-only smoke, but the
temporary `X_*.csv` matrices had already been cleaned, so the R model step could
not read `X_train.csv`.  The full-run orchestrator now requires the complete set
of adapter files needed by the model step before reusing an adapter.  This keeps
post-success artifact cleanup compatible with later forced or resumed model
smokes.

Clean rerun status:

| Check | Result |
|---|---:|
| Window build status | completed |
| Experiment status | completed |
| Cell status | completed |
| Nonzero return codes | 0 |
| Model wall time | 1:44.35 |
| Model max RSS | 851,600 KB |
| Full launcher wall time | 3:09.97 |
| Full launcher max RSS | 1,151,396 KB |
| Binary fit artifacts retained | 0 |
| `X_*.csv` matrices retained after success | 0 |

Original-unit test metrics:

| Method | Test AQL | Test MAE | Test RMSE |
|---|---:|---:|---:|
| `normal_rhs_ns` | 12.1942 | 24.3884 | 35.5037 |
| `qdesn_al_rhs_ns_exact_chunked` | 12.5796 | 25.1591 | 36.6223 |
| `qdesn_exal_rhs_ns_exact_chunked` | 12.5849 | 25.1698 | 36.6292 |
| `naive3_prev7_avg` | 12.8429 | 25.6859 | 39.8901 |
| `naive1_prev_day` | 13.4361 | 26.8721 | 43.9151 |
| `naive2_prev3_avg` | 13.6072 | 27.2143 | 43.0612 |

Baseline context from Stage Z for the same region/fold median target:

| Source | Test AQL |
|---|---:|
| Current target-only Q-DESN registry row | 8.4032 |
| Cached PriceFM row | 7.6902 |
| Stage-ZA one-cell graph-direct Q-DESN AL smoke | 12.5796 |

The Stage-ZA model smoke used only 50 train origins by design.  It verifies the
graph-neighbor-direct adapter and full model path, but it is not a promotion
candidate and should not be compared as if it were a full training-budget row.
It is useful negative evidence against expanding immediately from the bounded
smoke alone.

Diagnostics were written under:

```text
application/data_local/pricefm/runs/pricefm_stage_za_graph_adapter_smoke_20260630/stageza_graph_direct_pl_f3_l096_d1_n120_seed20260630/cells/region=PL/fold=3/model/
```

Important figures:

```text
figures/trace_elbo.png
figures/trace_parameter_diagnostics.png
figures/final_parameter_summary.png
figures/test_fit_first14_origins.png
figures/test_fit_qdesn_al_rhs_ns_exact_chunked.png
figures/test_fit_qdesn_exal_rhs_ns_exact_chunked.png
figures/test_fit_normal_rhs_ns.png
```

## Validation

Focused tests:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_graph.py \
  application/tests/test_pricefm_desn_adapter_graph_neighbor_direct.py \
  application/tests/test_pricefm_desn_adapter_graph_summary.py \
  application/tests/test_pricefm_desn_experiment_grid.py \
  application/tests/test_pricefm_full_run_orchestrator.py \
  application/tests/test_pricefm_stage_za_graph_adapter_smoke.py -q
```

Result: 48 passed.

Broader graph-adapter and grid/orchestrator regression:

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
  application/tests/test_pricefm_stage_za_graph_adapter_smoke.py -q
```

Result after the adapter-readiness regression was added: 62 passed.

Additional regression after the one-cell model smoke found the resume-mode
adapter readiness bug:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_full_run_orchestrator.py \
  application/tests/test_pricefm_desn_experiment_grid.py \
  application/tests/test_pricefm_stage_za_graph_adapter_smoke.py -q
```

Result: 33 passed.

The broader planner chain should also remain green:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_z_design_contracts.py \
  application/tests/test_pricefm_stage_y_targeted_design.py \
  application/tests/test_pricefm_stage_x_selection_failure_contract.py -q
```

## Decision

Stage ZA is technically complete: the direct graph-neighbor adapter builds,
the full model path runs, exact chunking remains equivalent on the smoke gate,
and success cleanup now preserves reproducibility while removing large
intermediate matrices after the model step.

Do not expand to all six graph rows from this result alone.  The 50-origin smoke
is intentionally too small for performance selection and is much worse than the
current full-budget target-only registry row.  The next scientifically safer
step is to decide whether to run a small full-budget graph-direct candidate for
`PL` fold 3, or to revise the graph-direct design before spending the six-row
budget.
