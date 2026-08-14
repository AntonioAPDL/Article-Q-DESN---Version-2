# PriceFM Stage-B Confirmed Panel Gate, 2026-06-18

## Purpose

This note records the post-rescue Stage-B confirmation gate for the PriceFM
local DESN/Q-DESN comparison. The gate separates median-screening evidence from
the actual seven-paper-quantile apples-to-apples comparison against cached
PriceFM Phase-I predictions.

The key rule is:

```text
median selection or seed robustness is not sufficient for promotion;
confirmed promotion requires completed seven-quantile comparison and
original-unit test AQL delta < 0 versus PriceFM.
```

## Code Added

```text
application/scripts/pricefm/49_freeze_pricefm_stage_b_confirmed_panel.py
application/tests/test_pricefm_stage_b_confirmed_panel.py
```

The finalizer reads an existing region-panel comparison directory and writes
compact ignored outputs:

```text
evaluated_stage_b_panel.csv
confirmed_stage_b_panel.csv
stage_b_exceptions.csv
horizon_group_diagnostics.csv
stage_b_confirmed_panel_report.md
summary.json
```

It does not fit models, regenerate PriceFM, or modify large local artifacts.

## Source Artifacts

Comparison root:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_cached_vs_stage_b_combined_promotion_rescue_20260617
```

Combined local registry:

```text
application/data_local/pricefm/authoritative/pricefm_stage_b_combined_promotion_rescue_registry_20260617/combined_promotion_rescue_registry.csv
```

Cached PriceFM root:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_stage_b_apples_to_apples_20260616
```

Frozen confirmation output:

```text
application/data_local/pricefm/authoritative/pricefm_stage_b_confirmed_panel_20260618
```

All of these local data artifacts are ignored by git.

## Command

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/49_freeze_pricefm_stage_b_confirmed_panel.py \
  --comparison-dir application/data_local/pricefm/authoritative/pricefm_phase1_cached_vs_stage_b_combined_promotion_rescue_20260617 \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_b_combined_promotion_rescue_registry_20260617/combined_promotion_rescue_registry.csv \
  --cached-pricefm-root application/data_local/pricefm/authoritative/pricefm_phase1_stage_b_apples_to_apples_20260616 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_b_confirmed_panel_20260618 \
  --grid-id pricefm_stage_b_confirmed_panel_20260618 \
  --notes 'Freeze after combined Stage-B promotion/rescue seven-quantile cached PriceFM comparison.'
```

## Gate Checks

The finalizer fails early if:

- `summary.json` is absent or not `completed`;
- `region_panel_comparison_status.csv` has a failed or nonzero row;
- original-unit test metrics are missing;
- `panel_row_alignment.csv` is imperfect;
- best-local rows have duplicate `region,fold` keys;
- horizon-group diagnostics cannot be aligned to the best local method and
  PriceFM baseline.

Promotion labels:

| Label | Meaning |
|---|---|
| `confirmed_win` | Best local seven-quantile model beats cached PriceFM on original-unit test AQL. |
| `evaluated_loss` | Best local seven-quantile model loses to cached PriceFM. |
| `needs_short_horizon_rescue` | Losing row whose largest horizon loss is group `1-24`. |

## Result

| Panel | Region/folds | Local wins | Mean local AQL | Mean PriceFM AQL | Mean delta | Mean relative delta |
|---|---:|---:|---:|---:|---:|---:|
| Evaluated combined panel | 18 | 17 | 6.372830 | 7.171624 | -0.798795 | -0.113879 |
| Confirmed wins only | 17 | 17 | 6.270299 | 7.165271 | -0.894971 | -0.127335 |

Confirmed regions:

```text
AT, BG, ES, FR, IT_NORD, PL, PT
```

The exception is:

| Region | Fold | Best local method | Local AQL | PriceFM AQL | Delta | Label |
|---|---:|---|---:|---:|---:|---|
| FI | 3 | `qdesn_exal_rhs_ns_exact_chunked` | 8.115846 | 7.279637 | 0.836210 | `needs_short_horizon_rescue` |

FI fold 3 loses primarily at the first horizon block:

| Horizon group | Local AQL | PriceFM AQL | Delta |
|---|---:|---:|---:|
| 1-24 | 5.583460 | 3.131551 | 2.451910 |
| 25-48 | 8.691989 | 8.901877 | -0.209889 |
| 49-72 | 9.819816 | 9.513461 | 0.306355 |
| 73-96 | 8.368121 | 7.571657 | 0.796463 |

## Reproducibility Contract

For Stage-C and later panels:

1. Use median screens only as candidate generation.
2. Require seed robustness for fragile candidates.
3. Require the seven-paper-quantile cached PriceFM comparison before a row is
   called `confirmed_win`.
4. Promote only from `confirmed_stage_b_panel.csv`, not from median-only
   registries.
5. Keep `stage_b_exceptions.csv` as the starting point for targeted rescue.
6. Preserve configs, logs, metrics, figures, and summaries; clean generated
   `.rds`, `.rda`, and `.RData` intermediates after successful metric/figure
   extraction.

## Next Step

Implement the Stage-C candidate launcher against the confirmed gate:

1. Start with missing folds for partially evaluated regions.
2. Keep FI fold 3 in a targeted short-horizon rescue queue.
3. Use cached PriceFM for comparison unless a sentinel check requires
   regeneration.
4. Continue to label the current local graph/input information set separately
   from the full PriceFM spatial information set.
