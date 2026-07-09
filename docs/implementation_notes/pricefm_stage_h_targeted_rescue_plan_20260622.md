# PriceFM Stage-H Targeted Rescue Plan

Date: 2026-06-22

## Objective

Stage H continues from the Stage-G seed-robust authoritative quantile registry.
The goal is to rescue the remaining region/folds where the local
DESN/Q-DESN panel is still close to, or worse than, the cached fold-aligned
PriceFM Phase-I benchmark.

This is deliberately not a new broad global search. Stage-G already gives a
42-row authoritative registry with a small mean edge over cached PriceFM, but
14 rows still fall back to PriceFM and 6 rows remain close. The highest-return
next step is therefore a targeted median-only rescue pass over those weak
rows, followed by seed robustness and seven-quantile promotion only for
validated replacements.

## Current Authoritative Inputs

- Authoritative Stage-G decision registry:
  `application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_g_seedrob_20260622/authoritative_quantile_decision_registry.csv`
- Stage-G patched median registry:
  `application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_patched_registry_20260622/patched_selection_registry.csv`
- Cached fold-aligned PriceFM Phase-I benchmark:
  `application/data_local/pricefm/authoritative/pricefm_phase1_stage_e_full_panel_missing_paper_quantiles_20260619`

The cached PriceFM benchmark remains the comparison source for Stage H. A fresh
PriceFM rerun is currently blocked by a missing TensorFlow dependency in the
local PriceFM environment, so Stage H is a cache-aware modeling stage. The
TensorFlow environment should be fixed before final paper-grade claims that
require fresh PriceFM execution.

## Evidence Behind The Stage-H Scope

Stage-G merged registry summary:

| Decision | Rows |
|---|---:|
| `stage_c_confirmed_local_win` | 22 |
| `stage_c_local_close_to_pricefm` | 6 |
| `stage_c_pricefm_fallback` | 14 |

Graph-khop remains the strongest empirical lever:

| Feature policy | Wins | Close | Fallback |
|---|---:|---:|---:|
| `graph_khop` | 17 | 1 | 4 |
| `target_only` | 5 | 5 | 10 |

This motivates converting target-only fallbacks and close rows to graph-khop
candidates, while tuning graph geometry for rows that already use graph
features but still fall back to PriceFM.

## Stage-H Priority Tiers

Priority is based only on the authoritative Stage-G decision registry. Test
and cached PriceFM metrics are audit fields; median model selection remains
validation-clean.

| Priority | Rule | Role |
|---:|---|---|
| 0 | PriceFM fallback with absolute AQL gap at least `1.0` | Severe fallback rescue |
| 1 | Remaining PriceFM fallbacks | Moderate fallback rescue |
| 2 | Close-to-PriceFM rows | Low-risk close-row rescue |

The expected Stage-G-derived scope is:

- Priority 0 severe fallbacks:
  `EE-1`, `LT-1`, `HU-2`, `SK-3`, `FI-1`, `SK-1`, `RO-1`, `HU-1`.
- Priority 1 remaining fallbacks:
  `RO-3`, `AT-3`, `SE_4-1`, `PL-3`, `NL-3`, `BE-3`.
- Priority 2 close rows:
  `LV-1`, `SI-1`, `PL-1`, `HU-3`, `LV-2`, `SE_4-3`.

## Candidate Design

The generator is:

`application/scripts/pricefm/60_prepare_pricefm_stage_h_targeted_rescue.py`

Candidate design principles:

1. Keep `RHS_NS` exact-chunked Q-DESN as the default comparison backbone.
2. Emphasize `graph_khop`, because it has delivered most successful rescues.
3. Use target-only guardrails when a current row is already graph-informed.
4. Vary representation geometry first: graph degree, input scale, leakage
   `alpha`, spectral radius `rho`, lag window, depth, and units.
5. Do not make `tau0` a broad grid axis. Earlier evidence indicates the main
   bottleneck is representation/information set, not shrinkage strength.
6. Do not promote any median candidate directly to authoritative status.
   Seed robustness and seven-paper-quantile comparison are required first.

## Generated Artifacts

The preparation step writes ignored operational artifacts:

- Grid config:
  `application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_h_targeted_median_rescue_20260622.yaml`
- Generated grid root:
  `application/data_local/pricefm/experiment_grids/pricefm_stage_h_targeted_median_rescue_20260622`
- Run root:
  `application/data_local/pricefm/runs/pricefm_stage_h_targeted_median_rescue_20260622`
- Plan artifacts:
  `application/data_local/pricefm/authoritative/pricefm_stage_h_targeted_median_rescue_plan_20260622`

Generated Stage-H counts after running the preparer:

| Item | Count |
|---|---:|
| Targeted region/folds | 20 |
| Total median experiments | 324 |
| Priority-0 experiments | 192 |
| Priority-1 experiments | 84 |
| Priority-2 experiments | 48 |
| Graph-khop experiments | 315 |
| Target-only guardrail experiments | 9 |

Targeted-row reasons:

| Reason | Rows |
|---|---:|
| Severe PriceFM fallback | 8 |
| Moderate PriceFM fallback | 6 |
| Close local loss | 6 |

## Commands

Generate the grid:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/60_prepare_pricefm_stage_h_targeted_rescue.py
```

Dry-run priority 0:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_h_targeted_median_rescue_20260622.yaml \
  --priorities 0 \
  --experiment-jobs 20 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run true
```

Launch priority 0 after dry-run validation:

```sh
tmux new-session -d -s pricefm_stage_h_p0_20260622 \
  "cd /data/jaguir26/local/src/Article-Q-DESN; \
   export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
     VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1; \
   /usr/bin/time -v \
     -o application/data_local/pricefm/authoritative/pricefm_stage_h_targeted_median_rescue_plan_20260622/priority0_launch.time.log \
     application/data_local/pricefm/venv/bin/python \
     application/scripts/pricefm/13_run_desn_experiment_grid.py \
     --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_h_targeted_median_rescue_20260622.yaml \
     --priorities 0 \
     --experiment-jobs 20 \
     --cell-jobs 1 \
     --build-windows true \
     --resume true \
     --dry-run false \
     > application/data_local/pricefm/authoritative/pricefm_stage_h_targeted_median_rescue_plan_20260622/priority0_launch.console.log \
     2>&1"
```

## Monitoring

```sh
tmux list-sessions | rg 'pricefm_stage_h_p0_20260622' || true

find application/data_local/pricefm/runs/pricefm_stage_h_targeted_median_rescue_20260622 \
  -path '*/metric_summary.csv' -type f | wc -l

find application/data_local/pricefm/runs/pricefm_stage_h_targeted_median_rescue_20260622 \
  -type f \( -name '*.rds' -o -name '*.rda' -o -name '*.RData' -o -name '*.rdata' \) | wc -l
```

## Launch Status

The priority-0 dry-run materialized the intended priority-0 scope:

```text
dry_run: true
n_selected_experiments: 192
status_csv: application/data_local/pricefm/experiment_grids/pricefm_stage_h_targeted_median_rescue_20260622/launch_status.csv
```

Some experiment dry-run rows report `missing_windows` for lag variants whose
window arrays have not yet been built. That is expected before the live run
because `--dry-run true` also dry-runs the window-build step. The live launch
therefore keeps `--build-windows true` and `--resume true` so missing lag/window
arrays are built before actual model fits.

The priority-0 live launch was started in tmux session:

```text
pricefm_stage_h_p0_20260622
```

The live launch uses `--experiment-jobs 20`, `--cell-jobs 1`, and pins
BLAS/OpenMP-style thread counts to one thread per process.

## Closeout Criteria

Do not promote any Stage-H candidate unless:

- the selected priority tier completes without failed experiment rows;
- every expected `metric_summary.csv` exists;
- no large R binary fit artifacts are retained in the Stage-H run tree;
- selection uses median validation AQL only;
- graph rows carry `feature_policy`, `graph_degree`, `graph_source`,
  `graph_hash`, `input_scope`, and `spatial_information_set`;
- promising median replacements pass seed robustness;
- seed-robust replacements are promoted to all seven paper quantiles;
- the seven-quantile comparison is run against the cached fold-aligned PriceFM
  benchmark, or against a freshly regenerated PriceFM benchmark after the
  TensorFlow environment is fixed;
- the authoritative registry is updated only through the freeze/merge scripts.

## Stop Conditions

Stop and report instead of promoting if:

- the dry-run selects an unexpected row count;
- graph metadata is missing from graph candidates;
- generated grids include full-data/test leakage in model selection metadata;
- the launch emits failed experiment logs;
- binary fit artifacts accumulate unexpectedly;
- a candidate improves test metrics but not validation median AQL;
- PriceFM cache row alignment fails;
- fresh PriceFM execution is required but TensorFlow remains unavailable.

## Next Step After Priority 0

After priority 0 finishes, close out the median results against the current
Stage-G median registry. Only then decide whether to launch priorities 1 and 2
or proceed directly to seed robustness for priority-0 improvements.
