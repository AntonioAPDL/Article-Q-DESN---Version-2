# PriceFM Stage-F Graph Rescue Plan

Date: 2026-06-20

This note plans the next graph-informed rescue stage after the Stage-E
full-panel closeout. It is intentionally median-first and validation-clean:
the grid is prepared, but not launched by this closeout pass.

## Objective

Stage F tests whether adding the released PriceFM graph as covariate input can
rescue target-only region/folds that remain:

- close to PriceFM but not better, or
- assigned to PriceFM fallback after the seven-quantile comparison.

The stage does not change the paper-facing decision registry until the usual
sequence passes:

1. median validation selection,
2. test and PriceFM metrics as audit only,
3. seed robustness for promising median candidates,
4. seven-paper-quantile promotion,
5. PriceFM comparison,
6. authoritative decision re-freeze.

## Current Baseline

Authoritative Stage-E registry:

```text
application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_e_20260619/authoritative_quantile_decision_registry.csv
```

Current decision counts:

| decision | rows |
|---|---:|
| confirmed local win | 10 |
| local close to PriceFM | 9 |
| PriceFM fallback | 23 |

The Stage-D graph-khop rows are already labeled as graph-informed and are
excluded from the default Stage-F candidate pool. Stage F therefore focuses on
remaining target-only close/fallback rows.

## Prepared Grid

Preparation command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/58_prepare_pricefm_stage_f_graph_rescue.py
```

Generated artifacts:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_f_graph_median_rescue_20260620.yaml
application/data_local/pricefm/experiment_grids/pricefm_stage_f_graph_median_rescue_20260620
application/data_local/pricefm/runs/pricefm_stage_f_graph_median_rescue_20260620
application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_plan_20260620
```

Prepared scope:

| item | value |
|---|---:|
| rescue region/folds | 30 |
| median experiments | 360 |
| graph degree 1 experiments | 216 |
| graph degree 2 experiments | 144 |
| close-loss rows | 9 |
| severe fallback rows | 6 |
| moderate fallback rows | 14 |
| mild fallback rows | 1 |

Priority rule:

| priority | rows targeted | experiments |
|---:|---|---:|
| 0 | close local losses and severe fallbacks | 180 |
| 1 | moderate fallbacks | 168 |
| 2 | mild fallbacks | 12 |

Priority-0 rows are:

| region | fold | reason |
|---|---:|---|
| EE | 3 | close local loss |
| LT | 3 | close local loss |
| LV | 1 | close local loss |
| LV | 2 | close local loss |
| LV | 3 | close local loss |
| PL | 1 | close local loss |
| RO | 2 | close local loss |
| SE_4 | 3 | close local loss |
| SI | 1 | close local loss |
| DK_1 | 1 | severe PriceFM fallback |
| DK_2 | 3 | severe PriceFM fallback |
| HU | 2 | severe PriceFM fallback |
| HU | 3 | severe PriceFM fallback |
| SK | 2 | severe PriceFM fallback |
| SK | 3 | severe PriceFM fallback |

## Launch Discipline

Recommended first launch:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_f_graph_median_rescue_20260620.yaml \
  --experiment-jobs 10 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run false \
  --resume true
```

Operational relaunch note:

The first live priority-0 launch used `--experiment-jobs 10`. It was
cancelled before any `metric_summary.csv` files were produced so the same
priority-0 work could be relaunched with more experiment-level parallelism. The
cancelled launch logs were copied to:

```text
application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_plan_20260620/priority0_launch_10worker_cancelled.console.log
application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_plan_20260620/priority0_launch_10worker_cancelled.time.log
```

The active higher-throughput launch uses 20 independent single-threaded
experiments:

```sh
tmux new-session -d -s pricefm_stage_f_p0_20w_20260620 \
  "cd /data/jaguir26/local/src/Article-Q-DESN; \
   export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
     VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1; \
   /usr/bin/time -v \
     -o application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_plan_20260620/priority0_launch_20worker.time.log \
     application/data_local/pricefm/venv/bin/python \
     application/scripts/pricefm/13_run_desn_experiment_grid.py \
     --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_f_graph_median_rescue_20260620.yaml \
     --priorities 0 \
     --experiment-jobs 20 \
     --cell-jobs 1 \
     --build-windows true \
     --dry-run false \
     --resume true \
     > application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_plan_20260620/priority0_launch_20worker.console.log \
     2>&1"
```

The scaling strategy remains experiment-level parallelism, not multi-threaded
fits. Each model process is single-threaded to avoid nested BLAS/OpenMP
oversubscription while allowing many independent region/fold/spec experiments
to run concurrently.

Recommended monitoring:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/14_check_desn_experiment_grid_status.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_f_graph_median_rescue_20260620.yaml
```

Run priority 0 first if a narrower launch is desired. Launch all priorities
only when enough cores and disk are free.

## Quality Gates

Stage F should not promote anything until all of these pass:

- all median grid cells complete with no failed `cell_status.csv` rows;
- no `.rds`, `.rda`, or `.rdata` artifacts remain in the run root after
  metrics and plots are produced;
- selection uses validation AQL only;
- test AQL, PriceFM AQL, and seven-quantile metrics are audit fields until
  the promotion step;
- graph metadata is present in every generated candidate:
  `feature_policy = graph_khop`,
  `spatial_information_set = pricefm_released_graph_khop`,
  and a 64-character `graph_hash`;
- seed robustness is required before seven-quantile promotion;
- Stage-D graph-rescue rows are not re-targeted unless explicitly requested;
- the final authoritative registry must preserve local-vs-graph provenance.

## Why This Is The Next Good Step

The Stage-E closeout shows that many remaining losses are target-only local
models. Stage-D already demonstrated that graph-khop inputs can materially
change outcomes for selected rows: 7 robust graph candidates were promoted to
paper quantiles and 5 of those beat PriceFM on the final comparison. Stage F
extends that lesson to the unresolved target-only rows while retaining the same
validation-first discipline.

This is a better next step than another broad target-only hyperparameter grid:
the target-only grid has already been heavily explored, while the graph-informed
input space remains under-sampled and directly addresses the main structural
gap relative to PriceFM.

## Deferred

The following remain out of scope for Stage F:

- new global all-region joint models;
- new Q-DESN inference modes;
- changing the paper quantile grid;
- promoting median-only graph candidates without seed robustness;
- replacing the authoritative Stage-E registry before the seven-quantile
  comparison is complete.
