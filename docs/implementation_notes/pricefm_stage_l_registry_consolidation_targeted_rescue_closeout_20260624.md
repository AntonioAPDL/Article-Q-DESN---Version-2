# PriceFM Stage-L Registry Consolidation And Targeted Rescue Closeout

Date: 2026-06-24

## Purpose

Stage L closed the PriceFM registry-consolidation and targeted-rescue pass that
followed the Stage-K regularized graph-summary screen.  The goal was to freeze a
finite current decision surface, harden multi-seed summaries, and run only the
narrow SI fold-1 seed expansion justified by Stage-K evidence.

This pass did not promote from test-only performance.  Validation AQL remained
the selection gate; test AQL remained audit-only.

## Repo State

Article branch:

```text
application-ensemble-likelihood-redesign
```

The PriceFM Stage-L plan started from:

```text
706205b Plan PriceFM Stage-L registry consolidation
```

Later unrelated GloFAS commits were already present on the same branch during
this closeout.  Stage-L did not edit GloFAS outputs or Overleaf/main.

## Tracked Tooling Changes

Stage-L added or updated these PriceFM tools:

```text
application/scripts/pricefm/62_summarize_pricefm_multiseed_median_screen.py
application/scripts/pricefm/65_validate_pricefm_current_decision_surface.py
application/scripts/pricefm/66_prepare_pricefm_stage_l_si_seed_expansion.py
application/scripts/pricefm/67_summarize_pricefm_stage_l_split_diagnostics.py
```

The multi-seed summarizer now:

- records the current registry path and label in `summary.json`;
- fails early on duplicate current-registry keys;
- fails early on non-finite current `selection_AQL` or `test_AQL`;
- reports unique missing current-registry keys instead of repeating one row per
  seed.

## Current Decision Surface

Command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/65_validate_pricefm_current_decision_surface.py
```

Output directory:

```text
application/data_local/pricefm/authoritative/pricefm_stage_l_current_decision_surface_20260624/
```

Summary:

| item | value |
|---|---:|
| fatal failures | 0 |
| current median rows | 42 |
| current quantile rows | 42 |
| Stage-J closeout rows | 9 |
| Stage-K geometry rows | 44 |
| broad quantile median-field gaps documented | 20 |

All required health checks passed:

- required columns;
- unique `(region, fold)` keys;
- finite median registry `selection_AQL` and `test_AQL`;
- finite paper-quantile `local_AQL`, `pricefm_AQL`, and `delta_abs`;
- current median registry covers all current quantile keys.

The 20 broad-quantile median-field gaps are documented in:

```text
application/data_local/pricefm/authoritative/pricefm_stage_l_current_decision_surface_20260624/quantile_registry_median_field_gaps.csv
```

Those gaps are not fatal because the finite current median registry is the
authoritative source for median comparisons.

## Stage-K Summary Hardening

Stage-K was rerun through the hardened summarizer with an explicit Stage-J
baseline label:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/62_summarize_pricefm_multiseed_median_screen.py \
  --manifest-csv application/data_local/pricefm/experiment_grids/pricefm_stage_k_regularized_graph_20260623/manifest.csv \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_priority0_closeout_20260623/rescue_closeout_decisions.csv \
  --current-registry-label stage_j_priority0_closeout \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_k_regularized_graph_multiseed_summary_20260623 \
  --require-complete true
```

Result:

| item | value |
|---|---:|
| manifest rows | 87 |
| seed metric rows | 87 |
| geometry rows | 44 |
| missing metric rows | 0 |
| pre-closeout rows | 0 |

Stage K remains a no-promotion result.

## SI Fold-1 Targeted Seed Expansion

Stage L prepared and launched only the Stage-K near-miss geometry:

| field | value |
|---|---|
| region/fold | `SI` / `1` |
| method | `qdesn_exal_rhs_ns_exact_chunked` |
| feature policy | `graph_summary_mean` |
| graph degree | `2` |
| lag window | `96` |
| depth/units | `1` / `[120]` |
| alpha/rho | `0.5` / `0.9` |
| input scale | `0.35` |
| projection scale | `1.0` |
| tau0 | `0.001` |

Existing Stage-K seeds:

```text
20260624, 20260625, 20260626
```

New Stage-L seeds:

```text
20260627, 20260628, 20260629, 20260630, 20260631
```

Generated grid:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_l_si_seed_expansion_20260624.yaml
```

Dry-run verified exactly five new experiments before launch.

Launch command:

```sh
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

/usr/bin/time -v \
  -o application/data_local/pricefm/authoritative/pricefm_stage_l_si_seed_expansion_plan_20260624/seed_expansion_launch.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_l_si_seed_expansion_20260624.yaml \
  --priorities 0 \
  --experiment-jobs 5 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run false
```

Launch result:

| kind | rows | status |
|---|---:|---|
| window build | 1 | completed |
| experiment | 5 | completed |
| total | 6 | completed |

Runtime and memory:

| quantity | value |
|---|---:|
| wall time | 22:53.17 |
| max RSS | 1,231,668 KB |
| Stage-L run root size | 187 MB |

No Stage-L `.rds`, `.rda`, `.RData`, or `.rdata` files remained after the run.

## Expanded Seed Gate

Combined manifest:

```text
application/data_local/pricefm/authoritative/pricefm_stage_l_si_seed_expansion_plan_20260624/stage_l_si_combined_seed_manifest.csv
```

Summary output:

```text
application/data_local/pricefm/authoritative/pricefm_stage_l_si_seed_expansion_summary_20260624/
```

Summary command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/62_summarize_pricefm_multiseed_median_screen.py \
  --manifest-csv application/data_local/pricefm/authoritative/pricefm_stage_l_si_seed_expansion_plan_20260624/stage_l_si_combined_seed_manifest.csv \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_priority0_closeout_20260623/rescue_closeout_decisions.csv \
  --current-registry-label stage_j_priority0_closeout \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_l_si_seed_expansion_summary_20260624 \
  --min-validation-win-rate 0.75 \
  --max-mean-validation-delta 0.0 \
  --max-validation-delta 0.05 \
  --max-mean-test-delta-warning 0.0 \
  --require-complete true
```

Gate result:

| item | value |
|---|---:|
| seeds | 8 |
| validation-improving seeds | 4 |
| test-improving seeds | 8 |
| validation win rate | 0.50 |
| mean validation delta vs current | -0.054030 |
| max validation delta vs current | 0.193426 |
| mean test delta vs current | -1.725983 |
| max test delta vs current | -1.133649 |
| passed validation gate | false |
| recommended action | `do_not_promote` |

Seed-level deltas:

| seed | validation delta | test delta | validation improved | test improved |
|---:|---:|---:|---|---|
| 20260624 | 0.098492 | -1.749587 | false | true |
| 20260625 | -0.176153 | -1.428922 | true | true |
| 20260626 | -0.322898 | -1.836559 | true | true |
| 20260627 | -0.266000 | -1.862254 | true | true |
| 20260628 | -0.104084 | -2.113016 | true | true |
| 20260629 | 0.106515 | -1.133649 | false | true |
| 20260630 | 0.193426 | -1.930412 | false | true |
| 20260631 | 0.038465 | -1.753464 | false | true |

Interpretation: the SI graph-summary geometry is consistently test-helpful but
not validation-stable.  It must not be promoted under the current
validation-first protocol.

## Split Diagnostics

Command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/67_summarize_pricefm_stage_l_split_diagnostics.py
```

Output:

```text
application/data_local/pricefm/authoritative/pricefm_stage_l_split_diagnostics_20260624/
```

The diagnostic summarized LV and SI fold 1 train, validation, and test response
windows.  The main contrasts were:

| region | contrast | mean delta | sd ratio | median delta |
|---|---|---:|---:|---:|
| LV | val minus train | -0.533345 | 0.601814 | -0.235939 |
| LV | test minus val | 0.135871 | 1.013210 | 0.144380 |
| SI | val minus train | -0.392911 | 0.547271 | -0.106534 |
| SI | test minus val | 0.027950 | 0.752575 | 0.099744 |

Both regions show validation windows shifted lower and less variable than the
training windows.  SI test performance is better for every expanded seed, but
the validation behavior is too unstable to justify a registry patch.

## Final Decision

No Stage-L candidate is promoted.

The current Stage-I/Stage-J PriceFM decision surface remains authoritative.  No
paper-quantile synthesis was launched for Stage-L because the median seed gate
failed.  No quantile registry was patched.

## Tests And Checks

Focused tests:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_k_summarizers.py \
  application/tests/test_pricefm_stage_l_decision_surface.py
```

Result:

```text
10 passed
```

Compile check:

```sh
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/62_summarize_pricefm_multiseed_median_screen.py \
  application/scripts/pricefm/65_validate_pricefm_current_decision_surface.py \
  application/scripts/pricefm/66_prepare_pricefm_stage_l_si_seed_expansion.py \
  application/scripts/pricefm/67_summarize_pricefm_stage_l_split_diagnostics.py
```

Result: passed.

Additional cleanup checks:

- Stage-K launch status: 95/95 completed.
- Stage-L launch status: 6/6 completed.
- Stage-K/Stage-L run roots contained no disposable `.rds`, `.rda`, `.RData`,
  or `.rdata` files.
- No current-pass Stage-L fit process remained active after closeout.

## Recommended Next Step

Do not run another graph-summary seed expansion from this result.  The useful
signal is not a new candidate; it is the validation/test mismatch:

1. keep the current registry unchanged;
2. audit whether the validation window is the right selection proxy for this
   PriceFM fold design;
3. if more modeling is needed, propose a new design that is selected on
   validation-clean evidence before launching paper-quantile synthesis.

