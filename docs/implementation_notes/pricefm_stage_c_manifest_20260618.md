# PriceFM Stage-C Manifest, 2026-06-18

## Purpose

This note records the Stage-C candidate manifest handoff after the Stage-B
seven-quantile confirmation gate. The manifest is a planning and launch-input
artifact only. It does not fit models, regenerate PriceFM, or promote new
region/folds.

The Stage-C rule remains:

```text
median screening -> seed robustness when fragile -> seven paper quantiles
-> cached PriceFM comparison -> confirmed/evaluated/exception freeze
```

## Code Added

```text
application/scripts/pricefm/50_prepare_pricefm_stage_c_manifest.py
application/tests/test_pricefm_stage_c_manifest.py
```

The script reads the Stage-B confirmed gate and writes a compact ignored
manifest for the next median-screening batch.

## Source Gate

Stage-B confirmation root:

```text
application/data_local/pricefm/authoritative/pricefm_stage_b_confirmed_panel_20260618
```

Important files:

```text
confirmed_stage_b_panel.csv
evaluated_stage_b_panel.csv
stage_b_exceptions.csv
summary.json
```

Stage-B status:

| Panel | Region/folds | Local wins | Mean local AQL | Mean PriceFM AQL | Mean delta |
|---|---:|---:|---:|---:|---:|
| Evaluated | 18 | 17 | 6.372830 | 7.171624 | -0.798795 |
| Confirmed only | 17 | 17 | 6.270299 | 7.165271 | -0.894971 |

FI fold 3 remains an exception and is not part of the generic Stage-C candidate
manifest.

## Command

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/50_prepare_pricefm_stage_c_manifest.py \
  --confirmed-dir application/data_local/pricefm/authoritative/pricefm_stage_b_confirmed_panel_20260618 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_c_manifest_20260618 \
  --queue2-regions EE,LV,LT,DK_2,RO,HU,SE_4,DK_1,SK,SI,NL,BE \
  --folds 1,2,3 \
  --grid-id pricefm_stage_c_manifest_20260618 \
  --write true
```

## Output

Ignored output root:

```text
application/data_local/pricefm/authoritative/pricefm_stage_c_manifest_20260618
```

Files:

```text
stage_c_candidate_manifest.csv
stage_c_exception_rescue_queue.csv
stage_c_queue_summary.csv
stage_c_region_score_universe.csv
stage_c_deferred_regions.csv
stage_c_manifest_report.md
summary.json
```

Summary:

| Queue | Rows | Regions | Region/folds | Gate |
|---|---:|---:|---:|---|
| `completion_folds` | 6 | 3 | 6 | `median_screen` |
| `diverse_new_regions` | 36 | 12 | 36 | `median_screen` |
| `exception_rescue` | 1 | 1 | 1 | `short_horizon_rescue` |

The 42 median-screen candidate rows cover 15 regions:

```text
AT, FI, PL,
BE, DK_1, DK_2, EE, HU, LT, LV, NL, RO, SE_4, SI, SK
```

Completion-fold rows:

```text
AT folds 1,3
FI folds 1,2
PL folds 1,3
```

Diverse new-region rows:

```text
BE, DK_1, DK_2, EE, HU, LT, LV, NL, RO, SE_4, SI, SK
```

Exception rescue queue:

| Region | Fold | Gate | Reason |
|---|---:|---|---|
| FI | 3 | `short_horizon_rescue` | `needs_short_horizon_rescue` |

## Gate Semantics

Every Stage-C candidate row records:

- queue and priority;
- `region,fold`;
- candidate rationale;
- caution label;
- PriceFM Phase-I reference metrics;
- graph degree summaries;
- information-set labels;
- allowed final methods;
- cleanup and promotion discipline.

The generic candidate manifest excludes already evaluated rows unless an
explicit retest flag is used. FI fold 3 stays in the exception queue, not the
median-screen queue.

## Validation

Focused unit tests cover:

- completion-fold construction;
- diverse new-region construction;
- FI fold 3 exception separation;
- duplicate region/fold rejection;
- unknown region rejection;
- rejection of already evaluated regions in Queue 2.

Run:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_c_manifest.py
```

Before launching any Stage-C model fits, run:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm*.py
```

## Next Step

Build the Stage-C median grid from `stage_c_candidate_manifest.csv`, dry-run it,
and inspect command counts before launching. FI fold 3 should go through a
separate short-horizon rescue grid, not the generic Stage-C median grid.
