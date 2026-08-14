# Joint-QVP Synthetic DGP Forecast Phase 4e Raw-Crossing/VB Audit

Date: 2026-07-03  
Scope: targeted stronger-VB follow-up for raw forecast crossings observed after
the Phase 4d full contract-calibration rerun. This stage does not modify TT500,
GloFAS, PriceFM, or article outputs.

## Purpose

Phase 4d resolved the hard crossing gate for scored forecasts: contract
forecast quantiles were monotone and finite. However, Phase 4d still produced
review evidence:

- 23 raw forecast crossing pairs;
- 23 monotone-adjusted origins;
- mean VB max-iteration rate about 0.602 over the full calibration campaign.

Phase 4e tests whether stronger VB controls materially reduce those raw
crossings and max-iteration rates without rerunning the full 45-row calibration
campaign.

## Inputs

Baseline calibration artifact:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702
```

Targeted registry:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4c_crossing_audit/targeted_crossing_registry.csv
```

The targeted registry contains 7 replicated scenario rows preserving the exact
seeds that produced the 23 raw crossing origins:

- `laplace_bridge__calibration_r05`
- `gaussian_mixture_bridge__calibration_r05`
- `student_t_location_scale__calibration_r05`
- `asymmetric_laplace_tail__calibration_r02`
- `heteroskedastic_seasonal__calibration_r04`
- `persistent_heavy_tail__calibration_r05`
- `regime_shift__calibration_r02`

## Stronger-VB Follow-Up

Command run:

```sh
Rscript application/scripts/77_run_joint_qvp_synthetic_dgp_forecast_validation.R \
  --registry application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4c_crossing_audit/targeted_crossing_registry.csv \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4e_targeted_crossing_followup_vb480 \
  --vb-max-iter 480 \
  --adaptive-vb-max-iter-grid 480,720 \
  --refit-stride 20 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 40
```

Follow-up artifact:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4e_targeted_crossing_followup_vb480
```

Run size:

- 7 replicated scenarios.
- 280 forecast origins.
- 1,960 forecast quantile rows.

The Phase 3 runner completed with all 7 rows in `review`; no hard fail was
reported.

## Crossing Audit

Command run:

```sh
Rscript application/scripts/80_audit_joint_qvp_synthetic_dgp_forecast_crossings.R \
  --artifact-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4e_targeted_crossing_followup_vb480 \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4e_targeted_crossing_followup_vb480/phase4e_crossing_audit
```

Crossing audit result:

- Gate: `review`.
- Recommendation: `contract_unblocked_raw_review`.
- Contract crossing pairs: 0.
- Raw crossing pairs: 22.
- Raw crossing event rows: 22.
- Raw crossing pair rows: 22.

## Phase 4e Comparison Audit

New script:

```sh
Rscript application/scripts/82_audit_joint_qvp_synthetic_dgp_phase4e_raw_crossing_vb_followup.R
```

Command run:

```sh
Rscript application/scripts/82_audit_joint_qvp_synthetic_dgp_phase4e_raw_crossing_vb_followup.R \
  --baseline-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702 \
  --followup-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4e_targeted_crossing_followup_vb480 \
  --followup-audit-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4e_targeted_crossing_followup_vb480/phase4e_crossing_audit
```

Comparison artifact:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4e_targeted_crossing_followup_vb480/phase4e_raw_crossing_vb_audit
```

Primary files:

- `phase4e_before_after_overall_summary.csv`
- `phase4e_before_after_scenario_comparison.csv`
- `phase4e_crossing_origin_set_comparison.csv`
- `phase4e_vb_runtime_comparison.csv`
- `phase4e_recommendation.csv`
- `artifact_manifest.csv`

## Results

Overall:

- Baseline raw crossing pairs: 23.
- Follow-up raw crossing pairs: 22.
- Raw crossing reduction: 1 pair, about 4.3%.
- Baseline contract crossing pairs: 0.
- Follow-up contract crossing pairs: 0.
- Baseline adjusted origins: 23.
- Follow-up adjusted origins: 22.
- Baseline maximum monotone adjustment: about 0.07357.
- Follow-up maximum monotone adjustment: about 0.07304.
- Baseline targeted-scenario VB max-iteration rate: about 0.692.
- Follow-up VB max-iteration rate: about 0.125.
- Baseline targeted-scenario runtime: about 905.0 seconds.
- Follow-up runtime: about 594.3 seconds.

Scenario-level raw crossing pairs:

| Scenario | Baseline | Follow-up | Delta |
|---|---:|---:|---:|
| `laplace_bridge__calibration_r05` | 2 | 2 | 0 |
| `gaussian_mixture_bridge__calibration_r05` | 6 | 6 | 0 |
| `student_t_location_scale__calibration_r05` | 3 | 3 | 0 |
| `asymmetric_laplace_tail__calibration_r02` | 1 | 0 | -1 |
| `heteroskedastic_seasonal__calibration_r04` | 1 | 1 | 0 |
| `persistent_heavy_tail__calibration_r05` | 8 | 8 | 0 |
| `regime_shift__calibration_r02` | 2 | 2 | 0 |

Crossing-origin set comparison:

- 22 crossing pairs appear in both baseline and follow-up.
- 1 crossing pair is baseline-only.
- 0 crossing pairs are follow-up-only.

Interpretation: stronger VB controls materially improved the VB max-iteration
rate but did not materially reduce raw forecast crossing behavior. The raw
crossings are therefore not primarily a simple insufficient-iteration artifact
at these controls.

## Recommendation

Phase 4e gate: `review`.

Recommendation status:

```text
vb_improved_raw_crossings_persist
```

Do not rerun the full calibration campaign again with only stronger VB controls.
The targeted evidence suggests that stronger VB is useful for convergence
diagnostics but is not a sufficient remedy for raw extreme-tail crossing
frequency.

The next decision should be methodological rather than computational:

1. Keep the Phase 4c raw/contract policy, since scored contract forecasts remain
   monotone and finite.
2. Treat raw crossings and monotone adjustments as explicit review diagnostics.
3. Inspect whether the observed maximum adjustment, about 0.073, is acceptable
   relative to the forecast scale and truth-distance metrics.
4. If acceptable, proceed to article-candidate planning while reporting raw
   adjustment diagnostics.
5. If not acceptable, investigate model-side tail smoothing or a stronger
   joint monotonicity prior/parameterization before article-candidate validation.

## Verification

Verified manifests:

- Phase 4e forecast artifact: pass.
- Phase 4e crossing audit: pass.
- Phase 4e raw-crossing/VB comparison audit: pass.

The Phase 4e comparison audit artifact manifest contains SHA-256 hashes for all
generated comparison outputs.
