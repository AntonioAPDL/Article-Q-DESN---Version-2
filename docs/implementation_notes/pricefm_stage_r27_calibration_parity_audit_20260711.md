# PriceFM Stage-R27 Calibration and Information-Set Parity Audit

Date: 2026-07-11

## Scope

Stage-R27 is a read-only deep investigation after the completed Stage-R25 broad
horizon run and Stage-R26 final closeout.

It answers two immediate questions:

1. Can validation-only postfit calibration of existing Stage-R25 predictions
   close the cached PriceFM gap?
2. Does the remaining gap look more like an information-set parity problem, a
   calibration/readout problem, or an objective/model-family problem?

No launcher is invoked. No models are fit. No registry, manuscript, article, or
non-PriceFM files are mutated. No launch YAML is written.

## Inputs

Primary inputs:

- Stage-R26 final metric rows:
  `application/data_local/pricefm/authoritative/pricefm_stage_r26_r25_broad_horizon_final_closeout_20260711/pricefm_stage_r26_final_metric_rows.csv`
- Stage-R26 validation-selected rows:
  `application/data_local/pricefm/authoritative/pricefm_stage_r26_r25_broad_horizon_final_closeout_20260711/pricefm_stage_r26_final_validation_selected_case.csv`
- Stage-R26 test-oracle rows:
  `application/data_local/pricefm/authoritative/pricefm_stage_r26_r25_broad_horizon_final_closeout_20260711/pricefm_stage_r26_final_test_oracle_case.csv`
- Stage-R25 launch manifest:
  `application/data_local/pricefm/authoritative/pricefm_stage_r25_post_r24_broad_launch_prep_20260709/pricefm_stage_r25_launch_manifest.csv`
- Existing Stage-R25 prediction, adapter, and feature-manifest artifacts under:
  `application/data_local/pricefm/runs/pricefm_stage_r25_post_r24_broad_horizon_weighted_20260709`

## Method

Stage-R27 audits all 400 Stage-R25 Q-DESN/exQDESN method rows.

For each candidate, it reads existing:

- `model_predictions_scaled.csv`
- `predictions_with_naive_scaled.csv`
- `adapter/rows_val.csv`
- `adapter/rows_test.csv`
- `adapter/feature_manifest.json`
- `model_method_summary.csv`
- `model_parameter_summary.csv`

It then estimates postfit calibration parameters from validation rows only and
applies them to validation and test predictions.

Calibration rules:

- `baseline_replay`
- `global_quantile_shift_on_validation`
- `horizon_block_quantile_shift_on_validation`
- `horizon_block_affine_shift_scale_on_validation`

Test rows are audit-only after frozen validation selection.

## Outputs

Default output directory:

`application/data_local/pricefm/authoritative/pricefm_stage_r27_calibration_parity_audit_20260711`

Outputs:

- `pricefm_stage_r27_candidate_readiness.csv`
- `pricefm_stage_r27_calibration_params.csv`
- `pricefm_stage_r27_calibration_metric_summary.csv`
- `pricefm_stage_r27_calibration_selection_gate.csv`
- `pricefm_stage_r27_case_calibration_selection.csv`
- `pricefm_stage_r27_information_set_parity_audit.csv`
- `pricefm_stage_r27_mechanism_diagnosis.csv`
- `pricefm_stage_r27_next_action_plan.csv`
- `pricefm_stage_r27_no_launch_gates.csv`
- `source_manifest.csv`
- `summary.json`
- `pricefm_stage_r27_calibration_parity_report.md`

## Promotion Logic

Stage-R27 does not promote anything by itself.

The cleanest future path opens only if a candidate that was already
Stage-R26/R25 validation-selected becomes a validation-selected calibrated
beat-both row:

- beats current authoritative Q-DESN on test audit;
- beats cached PriceFM on test audit;
- uses validation-only calibration parameters;
- then passes full-quantile confirmation, MCMC confirmation, and
  reproducibility/hash-manifest gates.

If only a full-surface calibrated row beats both, but it was not part of the
original Stage-R26 validation-selected subset, the result is promising but more
post-hoc. It should require a preregistered confirmation stage before any
promotion.

If no calibrated validation-selected row beats both, the next scientific move is
not another same-family broad horizon-weighted launch. The next move should
pivot to objective/loss/model-family design, with a narrow information-set
parity audit first.

## Validation Commands

```bash
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/152_audit_pricefm_stage_r27_calibration_parity.py

application/data_local/pricefm/venv/bin/python -m pytest -q \
  application/tests/test_pricefm_stage_r27_calibration_parity.py
```

After validation passes, materialize with:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/152_audit_pricefm_stage_r27_calibration_parity.py \
  --force true
```
