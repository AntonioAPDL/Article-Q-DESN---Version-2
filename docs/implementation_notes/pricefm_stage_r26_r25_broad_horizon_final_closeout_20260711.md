# PriceFM Stage-R26 Final Closeout for Stage-R25 Broad Horizon

Date: 2026-07-11

## Scope

This stage finalizes the completed PriceFM Stage-R25 broad horizon-weighted run
as a read-only closeout. It supersedes the earlier Stage-R26 in-flight
diagnosis for decision purposes, while retaining that diagnosis as an upstream
evidence source.

No launcher is invoked. No models are fit. No registry, manuscript, article, or
non-PriceFM files are mutated by the closeout script.

## Script

- `application/scripts/pricefm/151_closeout_pricefm_stage_r26_r25_broad_horizon.py`

The script consumes:

- Stage-R26 in-flight diagnosis outputs;
- Stage-R25 grid summary, launch summary, launch status, exit file, and time
  log;
- Stage-R25 run directories and required artifacts.

It verifies:

- launcher exit code zero;
- all launch-status rows completed with return code zero;
- all 200 experiment rows completed;
- all 80 window-build rows completed;
- 200 run directories;
- 200 metric summaries;
- 200 horizon-group summaries;
- 200 cell-status files;
- 200 training-weight summaries;
- 200 model-prediction files;
- 200 prediction-with-naive files;
- no `.rds`, `.rda`, `.RData`, or `.rdata` artifacts.

## Outputs

Default output directory:

`application/data_local/pricefm/authoritative/pricefm_stage_r26_r25_broad_horizon_final_closeout_20260711`

Planned outputs:

- `pricefm_stage_r26_final_completion_audit.csv`
- `pricefm_stage_r26_final_metric_rows.csv`
- `pricefm_stage_r26_final_validation_selected_case.csv`
- `pricefm_stage_r26_final_test_oracle_case.csv`
- `pricefm_stage_r26_final_full_quantile_promotion_queue.csv`
- `pricefm_stage_r26_final_mcmc_confirmation_gate.csv`
- `pricefm_stage_r26_final_mechanism_learning_summary.csv`
- `pricefm_stage_r26_r27_pivot_plan.csv`
- `pricefm_stage_r26_final_closeout_gates.csv`
- `source_manifest.csv`
- `summary.json`
- `pricefm_stage_r26_r25_broad_horizon_final_closeout_report.md`

## Decision Gate

The promotion rule is strict:

1. candidate must be selected by validation AQL on the complete Stage-R25
   surface;
2. test metrics are audit-only after frozen validation selection;
3. candidate must beat current authoritative Q-DESN on test;
4. candidate must beat cached PriceFM on test;
5. candidate must later pass full-quantile confirmation, MCMC confirmation, and
   reproducibility/hash-manifest gates before registry or article mutation.

Rows that improve over current Q-DESN but still lose to cached PriceFM remain
mechanism-learning evidence only.

## Interpretation Plan

If the completed R25 surface has no validation-selected beat-both candidate:

- keep registry, manuscript, article, and MCMC blocked;
- treat the run as a clean negative for the current horizon-weight/readout,
  capacity, and lag family;
- pivot Stage-R27 to read-only prediction-artifact calibration and
  information-set parity audits before any new expensive launch.

This is scientifically stronger than immediately relaunching a larger
same-family search because R25 already tested a broad set of horizon-weighted
case-specific specifications and produced complete prediction artifacts that can
be audited without fitting new models.

## Validation Commands

```bash
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/151_closeout_pricefm_stage_r26_r25_broad_horizon.py

application/data_local/pricefm/venv/bin/python -m pytest -q \
  application/tests/test_pricefm_stage_r26_r25_broad_horizon_closeout.py
```

After those pass, materialize with:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/151_closeout_pricefm_stage_r26_r25_broad_horizon.py \
  --force true
```
