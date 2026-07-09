# PriceFM Stage-G Targeted Median Rescue

Date: 2026-06-21

Stage G follows the Stage-F graph rescue closeout. It targets the remaining
region/folds where the authoritative seven-paper-quantile decision is either:

- `stage_c_local_close_to_pricefm`, or
- `stage_c_pricefm_fallback`.

The stage is median-only and validation-clean. Test metrics and cached
PriceFM metrics are audit fields; they are not selection criteria.

## Source State

Authoritative decision registry:

```text
application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_f_20260621/authoritative_quantile_decision_registry.csv
```

Median registry used for candidate geometry:

```text
application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_promoted_registry_20260621/patched_selection_registry.csv
```

The Stage-F decision summary has 42 region/folds:

| decision type | rows |
|---|---:|
| local wins | 17 |
| close to PriceFM | 6 |
| PriceFM fallback | 19 |

Stage G targets the 25 close/fallback rows only.

## Design

The generator is:

```text
application/scripts/pricefm/59_prepare_pricefm_stage_g_targeted_rescue.py
```

It builds a tiered median grid from the current authoritative registries:

| priority | rule | role |
|---:|---|---|
| 0 | all close losses plus fallbacks with `abs(delta_abs) >= 1.25` or `abs(delta_rel) >= 0.15` | first launch tier |
| 1 | remaining fallbacks with `abs(delta_rel) >= 0.08` | secondary launch tier |
| 2 | mild fallbacks | reserve tier |

Candidate families:

- graph-khop degree 1 and degree 2 variants;
- local perturbations around input scale, leakage `alpha`, and spectral scaling `rho`;
- short-context variants at lags 48, 72, and 144 for priority 0;
- compact D1/D2/D3 capacity variants for priority 0;
- target-only guardrail anchors for rows whose current best median registry
  entry is already graph-informed.

The target-only guardrail is intentionally inserted before graph perturbations
so the per-row max-variant cap cannot prune it away.

## Generated Artifacts

Preparation command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/59_prepare_pricefm_stage_g_targeted_rescue.py
```

Generated ignored artifacts:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_g_targeted_median_rescue_20260621.yaml
application/data_local/pricefm/experiment_grids/pricefm_stage_g_targeted_median_rescue_20260621
application/data_local/pricefm/runs/pricefm_stage_g_targeted_median_rescue_20260621
application/data_local/pricefm/authoritative/pricefm_stage_g_targeted_median_rescue_plan_20260621
```

Generated counts:

| item | count |
|---|---:|
| targeted region/folds | 25 |
| total median experiments | 370 |
| priority-0 experiments | 288 |
| priority-1 experiments | 70 |
| priority-2 experiments | 12 |
| graph-khop experiments | 359 |
| target-only guardrail experiments | 11 |

Targeted-row reasons:

| reason | rows |
|---|---:|
| close local loss | 6 |
| large PriceFM fallback | 10 |
| moderate PriceFM fallback | 7 |
| mild PriceFM fallback | 2 |

## Validation

Focused tests:

```sh
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/59_prepare_pricefm_stage_g_targeted_rescue.py

application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_g_targeted_rescue.py \
  application/tests/test_pricefm_stage_f_graph_rescue.py \
  application/tests/test_pricefm_stage_e_quantile_completion.py -q
```

Result:

```text
7 passed
```

Dry-run launch gate:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_g_targeted_median_rescue_20260621.yaml \
  --priorities 0 \
  --experiment-jobs 10 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run true
```

Result:

```text
dry_run: true
n_selected_experiments: 288
status_csv: application/data_local/pricefm/experiment_grids/pricefm_stage_g_targeted_median_rescue_20260621/launch_status.csv
```

## Launch Command

The first live launch should use independent single-threaded experiments with
experiment-level parallelism:

```sh
tmux new-session -d -s pricefm_stage_g_p0_20260621 \
  "cd /data/jaguir26/local/src/Article-Q-DESN; \
   export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
     VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1; \
   /usr/bin/time -v \
     -o application/data_local/pricefm/authoritative/pricefm_stage_g_targeted_median_rescue_plan_20260621/priority0_launch.time.log \
     application/data_local/pricefm/venv/bin/python \
     application/scripts/pricefm/13_run_desn_experiment_grid.py \
     --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_g_targeted_median_rescue_20260621.yaml \
     --priorities 0 \
     --experiment-jobs 20 \
     --cell-jobs 1 \
     --build-windows true \
     --dry-run false \
     --resume true \
     > application/data_local/pricefm/authoritative/pricefm_stage_g_targeted_median_rescue_plan_20260621/priority0_launch.console.log \
     2>&1"
```

Monitoring:

```sh
tmux list-sessions | rg 'pricefm_stage_g_p0_20260621' || true

ps -eo pid,ppid,etime,pcpu,pmem,rss,stat,cmd |
  rg 'pricefm_stage_g|10_run_desn_model_full|13_run_desn_experiment_grid' |
  rg -v 'rg ' || true

find application/data_local/pricefm/runs/pricefm_stage_g_targeted_median_rescue_20260621 \
  -path '*/metric_summary.csv' -type f | wc -l

find application/data_local/pricefm/runs/pricefm_stage_g_targeted_median_rescue_20260621 \
  -type f \( -name '*.rds' -o -name '*.rda' -o -name '*.RData' \) | wc -l
```

The live priority-0 launch was started in tmux session
`pricefm_stage_g_p0_20260621` after the dry-run gate passed.

## Closeout Gates

Do not promote any Stage-G candidate until all gates pass:

- every priority-0 launched experiment completes with return code 0;
- every expected `metric_summary.csv` exists;
- no `.rds`, `.rda`, or `.RData` artifacts remain in the Stage-G run root;
- selection uses median validation AQL only;
- test/PriceFM metrics remain audit-only;
- graph candidates carry `feature_policy = graph_khop`,
  `spatial_information_set = pricefm_released_graph_khop`, and a graph hash;
- promising median improvements pass seed robustness before seven-quantile
  promotion;
- seven-paper-quantile promotion and PriceFM comparison are rerun before the
  authoritative decision registry changes.

## Next Steps

1. Launch priority 0.
2. Close out median validation results against the Stage-F promoted median
   registry.
3. Seed-robust only the promising Stage-G median replacements.
4. Promote robust replacements to seven quantiles.
5. Compare against cached fold-aligned PriceFM metrics.
6. Freeze a Stage-G authoritative decision registry only after the quantile
   comparison passes.
