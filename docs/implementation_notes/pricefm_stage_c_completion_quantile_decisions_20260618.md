# PriceFM Stage-C Completion Quantile Decisions, 2026-06-18

## Purpose

This note records the Stage-C priority-0 completion-fold closeout. It freezes
the six completion folds into explicit paper-quantile decisions after comparing
local DESN/Q-DESN outputs with cached fold-aligned PriceFM Phase-I predictions.

The key rule is unchanged:

```text
median screening is candidate-generation evidence only;
seven-paper-quantile original-unit test AQL decides promotion.
```

## Code Added

```text
application/scripts/pricefm/52_freeze_pricefm_stage_c_quantile_candidate_registry.py
application/scripts/pricefm/53_freeze_pricefm_stage_c_quantile_decisions.py
application/tests/test_pricefm_stage_c_quantile_candidate_registry.py
application/tests/test_pricefm_stage_c_quantile_decisions.py
```

The candidate-registry script freezes validation-selected median winners into
priority queues without using test or PriceFM metrics for candidate selection.
The decision-freeze script consumes a completed local-vs-PriceFM paper-quantile
comparison and writes promoted, close-call, and PriceFM-fallback registries.

## Source Inputs

Median-selection source:

```text
application/data_local/pricefm/authoritative/pricefm_stage_c_all_median_selection_20260618
```

Stage-C manifest:

```text
application/data_local/pricefm/authoritative/pricefm_stage_c_manifest_20260618
```

Cached PriceFM benchmark root:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_stage_b_apples_to_apples_20260616
```

## Candidate Registry

Command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/52_freeze_pricefm_stage_c_quantile_candidate_registry.py \
  --median-selection-dir application/data_local/pricefm/authoritative/pricefm_stage_c_all_median_selection_20260618 \
  --manifest-dir application/data_local/pricefm/authoritative/pricefm_stage_c_manifest_20260618 \
  --cached-pricefm-root application/data_local/pricefm/authoritative/pricefm_phase1_stage_b_apples_to_apples_20260616 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_c_quantile_candidate_registry_20260618 \
  --grid-id pricefm_stage_c_quantile_candidate_registry_20260618
```

Summary:

| Item | Count |
|---|---:|
| Candidate rows | 42 |
| Priority 0 completion rows | 6 |
| Priority 1 green rows | 12 |
| Priority 2 yellow rows | 11 |
| Hold/rescue rows | 13 |
| Rows with cached PriceFM benchmark | 6 |
| Rows still requiring PriceFM cache | 36 |

The six priority-0 rows were the only rows launched in this closeout because
their PriceFM benchmark cache already exists.

## Priority-0 Paper-Quantile Launch

Generated config:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_completion_paper_quantiles_20260618.yaml
```

Generated local run root:

```text
application/data_local/pricefm/runs/pricefm_stage_c_completion_paper_quantiles_20260618
```

Paper quantiles:

```text
0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90
```

Dry-run selected 42 experiments:

```text
6 region/folds x 7 quantiles = 42 fits
```

Real launch:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/logs/pricefm_stage_c_completion_paper_quantiles_20260618/completion_quantiles.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_completion_paper_quantiles_20260618.yaml \
  --priorities 0 \
  --experiment-jobs 8 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run false \
  --resume true
```

Launch result:

| Check | Result |
|---|---:|
| Selected experiments | 42 |
| Metric files written | 42 |
| Launcher exit status | 0 |
| Wall time | 1:53:54 |
| Max RSS | 1,523,004 KB |
| Error signatures | 0 |

## Summary And Cached PriceFM Comparison

Local quantile panel summary:

```text
application/data_local/pricefm/authoritative/pricefm_stage_c_completion_paper_quantiles_summary_20260618
```

Cached PriceFM comparison:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_c_completion_paper_quantiles_20260618
```

Decision freeze:

```text
application/data_local/pricefm/authoritative/pricefm_stage_c_completion_quantile_decisions_20260618
```

The PriceFM comparison was run with cached PriceFM predictions only:

```text
run_pricefm = false
```

All six comparison panels completed, and row alignment was exact for every
method and region/fold.

## Decision Table

| Region | Fold | Best local method | Local AQL | PriceFM AQL | Delta | Relative delta | Decision |
|---|---:|---|---:|---:|---:|---:|---|
| AT | 1 | `qdesn_exal_rhs_ns_exact_chunked` | 6.74138 | 7.40219 | -0.660811 | -0.08927 | confirmed local win |
| AT | 3 | `qdesn_exal_rhs_ns_exact_chunked` | 7.64658 | 6.75504 | 0.891543 | 0.13198 | PriceFM fallback |
| FI | 1 | `qdesn_exal_rhs_ns_exact_chunked` | 10.55477 | 9.25337 | 1.301399 | 0.14064 | PriceFM fallback |
| FI | 2 | `qdesn_exal_rhs_ns_exact_chunked` | 7.95061 | 8.14646 | -0.195852 | -0.02404 | confirmed local win |
| PL | 1 | `qdesn_exal_rhs_ns_exact_chunked` | 6.93310 | 6.61847 | 0.314630 | 0.04754 | close local loss |
| PL | 3 | `qdesn_al_rhs_ns_exact_chunked` | 8.40323 | 7.69022 | 0.713009 | 0.09272 | PriceFM fallback |

Macro original-unit test means:

| Method | AQL | AQCR | MAE | RMSE |
|---|---:|---:|---:|---:|
| `pricefm_phase1_pretraining` | 7.64429 | 0.00000 | 18.63243 | 29.94300 |
| `qdesn_exal_rhs_ns_exact_chunked` | 8.12674 | 0.03645 | 19.79068 | 30.69480 |
| `qdesn_al_rhs_ns_exact_chunked` | 8.17232 | 0.04670 | 19.97555 | 30.81647 |
| `normal_rhs_ns` | 9.81761 | 0.00000 | 23.76769 | 33.03528 |
| `normal_scaled_ridge` | 35.62645 | 0.00000 | 43.18852 | 61.97170 |

## Frozen Outputs

Ignored decision output files:

```text
stage_c_quantile_decision_registry.csv
stage_c_quantile_promoted_local_registry.csv
stage_c_quantile_close_registry.csv
stage_c_quantile_pricefm_fallback_registry.csv
stage_c_quantile_horizon_group_diagnostics.csv
stage_c_quantile_decision_report.md
summary.json
```

Decision counts:

| Decision | Count |
|---|---:|
| `stage_c_confirmed_local_win` | 2 |
| `stage_c_local_close_to_pricefm` | 1 |
| `stage_c_pricefm_fallback` | 3 |

## Interpretation

The completion-fold gate did not produce a universal local-only win. It did
confirm that local Q-DESN can beat cached PriceFM on some held-out region/folds
using the narrower local-only information set:

```text
AT fold 1, FI fold 2
```

PL fold 1 is close enough to keep as a review/rescue candidate, but it is not a
confirmed local win under the strict rule. AT fold 3, FI fold 1, and PL fold 3
should use PriceFM as the benchmark choice for now unless a new targeted rescue
grid improves them.

The next expansion should not promote the priority-1 green rows until their
PriceFM Phase-I benchmark cache is generated or deliberately refreshed.

## Validation

Focused tests:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_c_quantile_candidate_registry.py \
  application/tests/test_pricefm_stage_c_quantile_decisions.py \
  application/tests/test_pricefm_stage_c_median_grid.py \
  application/tests/test_pricefm_stage_c_manifest.py -q
```

Result:

```text
16 passed
```

## Next Gates

1. Use the frozen promoted-local registry only for AT fold 1 and FI fold 2.
2. Keep PL fold 1 in close-review/rescue, not as a confirmed win.
3. Keep AT fold 3, FI fold 1, and PL fold 3 as PriceFM fallbacks unless a
   targeted rescue screen improves their seven-quantile AQL.
4. Before launching priority-1 green rows (`BE`, `SE_4`, `SI`, `NL`), create
   or verify the cached PriceFM Phase-I benchmark for those 12 rows.
5. Keep priority-2 yellow and hold/rescue rows gated until the priority-1 cache
   and comparison workflow is proven end to end.
