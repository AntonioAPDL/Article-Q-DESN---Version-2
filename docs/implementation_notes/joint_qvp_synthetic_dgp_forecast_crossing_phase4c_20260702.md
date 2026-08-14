# Joint-QVP Synthetic DGP Forecast Crossing Phase 4c

Date: 2026-07-02  
Scope: targeted crossing audit and noncrossing forecast-output contract for the
joint multi-quantile QVP synthetic forecast validation lane. This stage does
not change TT500, GloFAS, or PriceFM outputs.

## Purpose

Phase 4b showed that the calibration-size forecast validation machinery was
reproducible, finite, and leakage-free, but article-candidate validation was
blocked by forecast quantile crossings. Phase 4c implements a conservative
forecast-output contract:

- preserve raw model forecast quantiles as diagnostics;
- apply an explicit monotone rearrangement before scoring;
- score and gate the monotone contract quantiles;
- keep raw crossings as review evidence, not hidden behavior.

## Motivating Failure

Source calibration artifact:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_20260702
```

Phase 4b found 8 raw/contract crossing pairs in the pre-contract artifact:

- `asymmetric_laplace_tail__calibration_r02`: 1 lower-tail crossing.
- `regime_shift__calibration_r02`: 2 lower-tail crossings.
- `nonlinear_reservoir_friendly__calibration_r02`: 5 upper-tail crossings.

The exact failed seeds were preserved through:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_20260702/phase4c_crossing_audit/targeted_crossing_registry.csv
```

The preserved rows have seeds:

- `202613002`
- `202616002`
- `202617002`

## Implemented Contract

Phase 3 forecast validation now writes:

- `forecast_quantiles_raw.csv`: raw model output before monotone projection.
- `forecast_quantiles.csv`: monotone contract forecasts used for scoring.
- `forecast_monotone_adjustment.csv`: raw-to-contract adjustment diagnostics.
- `raw_crossing_summary.csv`: raw crossing diagnostics.
- `crossing_summary.csv`: contract crossing diagnostics.

The contract uses the existing isotonic quantile helper:

```text
app_isotonic_quantiles()
```

from `application/R/synthesize_quantiles.R`.

The Phase 3 gate now hard-fails only if the contract forecasts cross. Raw
crossings that are corrected by the monotone contract produce `review`, not
`fail`.

## Crossing Audit

New script:

```sh
Rscript application/scripts/80_audit_joint_qvp_synthetic_dgp_forecast_crossings.R
```

It consumes either a Phase 4 directory or a Phase 3 directory and writes:

- `crossing_event_audit.csv`
- `crossing_origin_context.csv`
- `crossing_pair_detail.csv`
- `crossing_vb_context.csv`
- `crossing_remediation_recommendation.csv`
- `targeted_crossing_registry.csv` when a Phase 4 calibration registry is
  available
- `README.md`
- `artifact_manifest.csv`

The audit records scenario metadata, replicate ids, forecast origins, raw
crossed tau pairs, raw and contract qhat values, true quantiles, fit/reuse
context, and source-fit VB convergence status.

## Targeted Follow-Up

Command run:

```sh
Rscript application/scripts/77_run_joint_qvp_synthetic_dgp_forecast_validation.R \
  --registry application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_20260702/phase4c_crossing_audit/targeted_crossing_registry.csv \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_crossing_followup_phase4c_20260702 \
  --vb-max-iter 240 \
  --adaptive-vb-max-iter-grid 240,360 \
  --refit-stride 20 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 40
```

Follow-up artifact:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_crossing_followup_phase4c_20260702
```

Follow-up crossing audit:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_crossing_followup_phase4c_20260702/phase4c_crossing_audit
```

## Results

Before Phase 4c, the exact failing rows had 8 crossing pairs and all three rows
failed the forecast gate. After Phase 4c:

- contract crossing pairs: 0;
- raw crossing pairs: 3;
- adjusted origins: 3;
- maximum monotone adjustment: about `0.0411`;
- all three rows moved from `fail` to `review`.

Scenario-level follow-up:

- `asymmetric_laplace_tail__calibration_r02`: raw crossings reduced from 1 to
  1; contract crossings 0; max adjustment about `0.0021`.
- `regime_shift__calibration_r02`: raw crossings remained 2; contract crossings
  0; max adjustment about `0.0411`.
- `nonlinear_reservoir_friendly__calibration_r02`: raw crossings reduced from 5
  to 0; contract crossings 0.

Truth-distance and hit-rate summaries stayed comfortably inside Phase 3 review
thresholds. The remaining review reason is raw crossing/adjustment evidence and
VB convergence review.

Runtime increased under the higher VB controls:

- asymmetric-Laplace r02: about `82.3` to `145.9` seconds;
- nonlinear reservoir-friendly r02: about `82.7` to `133.8` seconds;
- regime-shift r02: about `86.0` to `108.8` seconds.

VB max-iteration rates remained high:

- asymmetric-Laplace r02: `1.0`;
- nonlinear reservoir-friendly r02: `1.0`;
- regime-shift r02: `0.5`.

## Interpretation

The original hard crossing blocker was caused by forecast-time raw output not
having the same monotone synthesis contract expected of final multi-quantile
forecast products. The problem is localized to extreme adjacent tails and is
amplified by max-iteration VB fits. It is not a leakage, finiteness, or manifest
failure.

The noncrossing contract resolves the scored-output hard gate while preserving
raw crossing diagnostics for review. Large or frequent raw adjustments remain
review evidence and should be reported separately from final contract scores.

## Next Step

Article-candidate validation is not yet fully promoted. The crossing hard gate
is unblocked for the targeted exact-seed follow-up, but the full calibration
campaign should be rerun under the new contract before article-candidate
freezing.

The prepared Phase 4d runbook is:

```text
docs/implementation_notes/joint_qvp_synthetic_dgp_forecast_calibration_contract_rerun_phase4d_20260702.md
```

Recommended preflight command:

```sh
Rscript application/scripts/81_prepare_joint_qvp_synthetic_dgp_forecast_contract_calibration_rerun.R \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702
```

Recommended launch command:

```sh
Rscript application/scripts/81_prepare_joint_qvp_synthetic_dgp_forecast_contract_calibration_rerun.R \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702 \
  --execute true
```

If that calibration run has zero contract crossings, finite scores, verified
hashes, and only review-level raw adjustments/VB convergence, then the next
stage can proceed to article-candidate validation planning.
