# PriceFM Graph/Local Median Rescue Closeout

Date: 2026-06-16

## Status

The targeted graph/local median rescue grid completed successfully and has been
closed out as a diagnostic run. The current graph/local median registry remains
authoritative.

## Inputs

- Rescue manifest:
  `application/data_local/pricefm/experiment_grids/pricefm_graph_local_median_rescue_20260615/manifest.csv`
- Rescue run root:
  `application/data_local/pricefm/runs/pricefm_graph_local_median_rescue_20260615`
- Current authoritative median registry:
  `application/data_local/pricefm/authoritative/pricefm_region_panel_median_graph_local_closeout_20260614/merged_selection_registry.csv`
- Closeout output:
  `application/data_local/pricefm/authoritative/pricefm_graph_local_median_rescue_closeout_20260616`

Generated local outputs are ignored by git.

## Command

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/42_closeout_pricefm_graph_local_rescue.py \
  --manifest-csv application/data_local/pricefm/experiment_grids/pricefm_graph_local_median_rescue_20260615/manifest.csv \
  --run-root application/data_local/pricefm/runs/pricefm_graph_local_median_rescue_20260615 \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_region_panel_median_graph_local_closeout_20260614/merged_selection_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_graph_local_median_rescue_closeout_20260616 \
  --robustness-seeds 20260616,20260617,20260618
```

## Health Check

| Item | Result |
|---|---:|
| Rescue experiments in manifest | 88 |
| Candidate metric rows | 352 |
| Experiment-level best rows | 88 |
| Rescue folds closed out | 9 |
| Missing metric files | 0 |
| Robustness candidates | 1 |
| Test-only diagnostics | 2 |

The earlier launch completed with exit status `0`, wall time `2:49:22`, and
maximum resident set size `1,895,872 KB`.

## Decision Counts

| Closeout label | Count | Meaning |
|---|---:|---|
| `robustness_candidate` | 1 | Validation and audit test both improved; queue seed robustness before any promotion. |
| `validation_candidate_audit_worse` | 4 | Validation improved, but test audit worsened. |
| `validation_overfit_warning` | 1 | Validation improved, but test audit worsened materially. |
| `test_only_diagnostic` | 2 | Test audit improved but validation did not; useful diagnostic only. |
| `keep_current` | 1 | No validation or test improvement. |

## Candidate Queue

Only one fold should move to seed robustness:

| Region | Fold | Experiment | Method | Val AQL delta | Test AQL delta | Next action |
|---|---:|---|---|---:|---:|---|
| `IT_SICI` | 3 | `rescue_itsici_f3_graphd2_base` | `qdesn_exal_rhs_ns_exact_chunked` | `-0.180626` | `-0.424872` | Rerun with seeds `20260616`, `20260617`, `20260618`. |

The specification is graph degree 2, depth 3, units `[80, 80, 80]`,
`alpha = 0.35`, `rho = 0.9`, `input_scale = 0.2`, and `tau0 = 0.001`.

## Registry-Level Audit

| Registry | Mean median test AQL | Mean selection AQL | Interpretation |
|---|---:|---:|---|
| Current authoritative | `8.338592` | `7.751438` | Baseline to keep for now. |
| Hypothetical validation-selected rescue | `8.447553` | `7.682242` | Worse on test audit despite better validation. |
| Hypothetical robustness-candidates only | `8.314988` | `7.741403` | Slightly better, but requires seed robustness before promotion. |

## Interpretation

The rescue grid is technically successful but scientifically conservative:
small geometry changes rescue one weak fold, while most validation improvements
do not transfer to the test audit. The correct next move is not seven-quantile
promotion for all rescue rows. Instead:

1. Keep the current graph/local median registry authoritative.
2. Run seed robustness only for `IT_SICI` fold 3.
3. Treat `NO_4` fold 3 and `SE_2` fold 3 as diagnostic clues, not selection
   winners, because their validation AQL did not improve.
4. Launch seven-quantile synthesis only after a median rescue candidate passes
   seed robustness.

## Validation

- New script syntax check passed.
- Focused graph/local rescue tests passed: `4 passed`.
- Closeout generated all expected local CSV/Markdown outputs.
- No large rescue `.rds`, `.rda`, or `.RData` files were found under the rescue
  run root.

## Next Stage

Prepare and launch a small seed-robustness grid for the single queued
`IT_SICI` fold 3 candidate. If the validation advantage is stable and no audit
instability appears, then create a patch median registry and promote only that
fold to seven paper quantiles.
