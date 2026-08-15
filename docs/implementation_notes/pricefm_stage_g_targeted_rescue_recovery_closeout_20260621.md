# PriceFM Stage-G Targeted Rescue Recovery Closeout

Date: 2026-06-21

## Status

The Stage-G priority-0 graph-khop lag recovery is complete and closed out.
The original priority-0 launch had 39 graph-khop lag cells fail because the
window prebuild step only created target-region lag windows. Graph-khop
experiments also need lag windows for their graph-neighbor input regions.

This pass fixed the window prebuild contract, reran the 39 failed priority-0
cells, and reran the median rescue closeout with a priority-0 filter. The
current Stage-F median registry remains authoritative until queued candidates
pass seed robustness and seven-quantile promotion.

## Code Fix

Commit:

```text
bd8cce5 Fix PriceFM graph window prebuild
```

The grid launcher now expands window-build dependencies for
`feature_policy = graph_khop` using the target region plus graph neighbors from
the configured PriceFM graph degree. Target-only windows are still used for
non-graph experiments.

The closeout script was also hardened in this pass:

- plan manifests that omit `run_dir` now fall back to `--run-root / id`;
- plan manifests with Python-style list strings such as `['DK_2']` are parsed;
- closeout supports `--priority 0`, so unlaunched priority-1/2 manifest rows
  are not counted as missing metrics.

## Recovery Inputs

Plan directory:

```text
application/data_local/pricefm/authoritative/pricefm_stage_g_targeted_median_rescue_plan_20260621
```

Grid root:

```text
application/data_local/pricefm/experiment_grids/pricefm_stage_g_targeted_median_rescue_20260621
```

Run root:

```text
application/data_local/pricefm/runs/pricefm_stage_g_targeted_median_rescue_20260621
```

Closeout output:

```text
application/data_local/pricefm/authoritative/pricefm_stage_g_targeted_median_rescue_closeout_20260621
```

Generated run outputs are ignored by git.

## Recovery Command

```sh
PLAN_DIR=application/data_local/pricefm/authoritative/pricefm_stage_g_targeted_median_rescue_plan_20260621
FAILED_IDS=$(cat "$PLAN_DIR/priority0_failed_ids_before_recovery.txt")
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

/usr/bin/time -v -o "$PLAN_DIR/priority0_recovery.time.log" \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_g_targeted_median_rescue_20260621.yaml \
  --ids "$FAILED_IDS" \
  --experiment-jobs 13 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force true \
  --dry-run false \
  > "$PLAN_DIR/priority0_recovery.console.log" 2>&1
```

Runtime and memory:

| item | value |
|---|---:|
| exit status | `0` |
| wall time | `1:12:34` |
| max RSS | `1,417,948 KB` |
| CPU utilization | `939%` |

## Recovery Health Check

| item | result |
|---|---:|
| recovered experiment IDs | 39 |
| completed window-build rows | 39 |
| completed experiment rows | 39 |
| metric summaries | 39 / 39 |
| reports | 39 / 39 |
| scaled prediction files | 39 / 39 |
| repo metadata files | 39 / 39 |
| remaining missing metrics | 0 |
| `.rds` / `.rda` / `.RData` files under Stage-G run root | 0 |

Per-experiment elapsed seconds for the recovered cells:

| group | min | median | max |
|---|---:|---:|---:|
| window builds | `10.437` | `14.589` | `22.565` |
| model experiments | `834.323` | `1038.667` | `1526.350` |

## Closeout Command

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/42_closeout_pricefm_graph_local_rescue.py \
  --manifest-csv application/data_local/pricefm/authoritative/pricefm_stage_g_targeted_median_rescue_plan_20260621/stage_g_targeted_rescue_experiment_manifest.csv \
  --run-root application/data_local/pricefm/runs/pricefm_stage_g_targeted_median_rescue_20260621 \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_promoted_registry_20260621/patched_selection_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_g_targeted_median_rescue_closeout_20260621 \
  --split-select val \
  --split-audit test \
  --unit original \
  --metric AQL \
  --priority 0
```

## Closeout Summary

| item | value |
|---|---:|
| priority filter | `0` |
| priority-0 experiments in manifest | 288 |
| candidate metric rows | 1152 |
| experiment-best rows | 288 |
| rescue region/folds closed out | 16 |
| missing metric files | 0 |
| robustness candidates | 8 |
| test-only diagnostics | 0 |

Decision counts:

| closeout label | count |
|---|---:|
| `robustness_candidate` | 8 |
| `validation_candidate_audit_worse` | 4 |
| `validation_overfit_warning` | 2 |
| `keep_current` | 2 |

Robustness candidates:

| region | fold | experiment | method | val AQL delta | test AQL delta |
|---|---:|---|---|---:|---:|
| `DK_1` | 3 | `stageg_dk1_f3_graphd1_input_lo` | `qdesn_al_rhs_ns_exact_chunked` | `-4.185873` | `-2.250834` |
| `DK_2` | 1 | `stageg_dk2_f1_graphd1_d1_units_hi` | `qdesn_exal_rhs_ns_exact_chunked` | `-3.074940` | `-3.836078` |
| `DK_2` | 2 | `stageg_dk2_f2_graphd1_d3_compact` | `qdesn_exal_rhs_ns_exact_chunked` | `-4.159230` | `-3.823606` |
| `EE` | 1 | `stageg_ee_f1_graphd2_base` | `qdesn_al_rhs_ns_exact_chunked` | `-3.965233` | `-8.079737` |
| `EE` | 2 | `stageg_ee_f2_graphd2_alpha_lo` | `qdesn_al_rhs_ns_exact_chunked` | `-4.673420` | `-3.193027` |
| `HU` | 2 | `stageg_hu_f2_graphd1_d3_compact` | `qdesn_exal_rhs_ns_exact_chunked` | `-0.472258` | `-1.353866` |
| `LT` | 1 | `stageg_lt_f1_graphd1_alpha_hi` | `qdesn_exal_rhs_ns_exact_chunked` | `-0.912715` | `-0.391734` |
| `LT` | 2 | `stageg_lt_f2_graphd1_input_lo` | `qdesn_al_rhs_ns_exact_chunked` | `-1.292539` | `-3.285014` |

Registry-level audit:

| registry | mean median test AQL | median median test AQL | mean selection AQL |
|---|---:|---:|---:|
| current authoritative | `11.355631` | `10.648481` | `11.267714` |
| hypothetical validation-selected rescue | `10.838373` | `10.116061` | `10.598977` |
| hypothetical robustness-candidates only | `10.731491` | `9.926331` | `10.726376` |

## Interpretation

The recovery substantially improves the Stage-G evidence base: all previously
failed graph-lag cells are now valid, and eight region/folds have validation
and audit-test improvements. The correct next step is still conservative:
queue only the eight robustness candidates for seed robustness. Do not patch
the authoritative registry or launch seven-quantile promotion from single-seed
Stage-G candidates.

Priority-1 and priority-2 Stage-G rows remain reserve tiers. They were not
launched in this recovery and were intentionally excluded from closeout with
`--priority 0`.

## Validation

Focused checks passed:

```text
py_compile application/scripts/pricefm/13_run_desn_experiment_grid.py
py_compile application/scripts/pricefm/42_closeout_pricefm_graph_local_rescue.py
pytest application/tests/test_pricefm_desn_experiment_grid.py -q
pytest application/tests/test_pricefm_graph_local_rescue_workflow.py -q
pytest application/tests/test_pricefm_desn_experiment_grid.py \
       application/tests/test_pricefm_stage_g_targeted_rescue.py \
       application/tests/test_pricefm_stage_f_graph_rescue.py \
       application/tests/test_pricefm_graph_local_rescue_workflow.py -q
git diff --check
```

## Next Stage

1. Keep the Stage-F median registry authoritative.
2. Generate a seed-robustness grid for the eight Stage-G candidates above.
3. Use validation AQL stability plus audit-test sanity checks to decide which
   candidates may patch the median registry.
4. Promote only seed-robust median replacements to seven PriceFM quantiles.
5. Rerun fold-aligned PriceFM comparisons before freezing any Stage-G
   authoritative quantile decision registry.
