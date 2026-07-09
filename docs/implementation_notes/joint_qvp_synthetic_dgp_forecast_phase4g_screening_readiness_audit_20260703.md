# Joint-QVP Synthetic DGP Forecast Validation: Phase 4g Screening Readiness Audit

Date: 2026-07-03

## Purpose

This note records the comprehensive readiness audit for the Phase 4g prior/design screening plan. The goal was to verify whether the proposed targeted screen is truly the optimal next step before implementing new controls or rerunning calibration.

## Audit Artifact

Readiness artifact:

`application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4g_prior_design_screening_readiness_audit`

Generation command:

```bash
Rscript application/scripts/86_audit_joint_qvp_phase4g_prior_design_screening_readiness.R
```

Primary files:

- `phase4g_readiness_summary.csv`
- `phase4g_control_plumbing_audit.csv`
- `phase4g_code_presence_audit.csv`
- `phase4g_evidence_audit.csv`
- `phase4g_hypothesis_diagnosis.csv`
- `phase4g_screen_grid.csv`
- `phase4g_metric_priority.csv`
- `phase4g_promotion_gates.csv`
- `phase4g_risk_register.csv`
- `phase4g_workflow_plan.csv`
- `artifact_manifest.csv`

Manifest status: complete. The generated manifest contains 12 hashed files, all present.

## Readiness Decision

Audit decision:

`ready_to_implement_phase4g_screening`

Optimality assessment:

`targeted_prior_design_screen_is_optimal_next_step`

Rationale:

- Stronger VB reduced max-iteration review but did not materially reduce raw crossings.
- Contract forecast outputs are already noncrossing.
- The implemented RHS prior direction means smaller `tau0`, not larger `tau0`, is the direct global shrinkage lever.
- `zeta2` and `alpha_min_spacing` exist in lower-level VB code but are not yet exposed through adaptive VB / Phase 3 forecast validation.
- The frozen targeted registry preserves the exact crossing-prone seeds, scenario ids, and replicate ids.
- A full calibration rerun before this screen would be computationally expensive and weakly informative.

## Plumbing Diagnosis

Current control status:

- `tau0`: partially wired. Phase 3 runner accepts it, but the CLI does not expose it.
- `alpha_prior_sd`: partially wired. Phase 3 runner accepts it, but the CLI does not expose it.
- `rhs_vb_inner`: partially wired. Phase 3 runner accepts it, but the CLI does not expose it.
- `zeta2`: internal only. Lower-level AL-VB supports it, but adaptive VB and Phase 3 forecast validation do not expose it.
- `alpha_min_spacing`: internal only. Lower-level AL-VB supports it, but adaptive VB and Phase 3 forecast validation do not expose it.
- `anchor_tau0` versus `innovation_tau0`: not wired. This should be a second-wave structural screen, not the first implementation.
- Raw/contract forecast policy: wired and should be retained.
- Targeted registry seed preservation: wired through Phase 4c targeted registry.
- Feature/readout norm audit: not wired; add later if Tier 1 is inconclusive.

## Evidence Diagnosis

The audit confirms:

- Raw crossings changed from 23 to 22 under stronger VB, only a 4.3% reduction.
- Contract crossings remained zero.
- VB max-iteration rate improved from 0.692 to 0.125.
- Persistent heavy-tail remains the largest raw crossing contributor.
- Regime shift has the largest mean absolute truth error among targeted rows.
- The next screen must rank crossing improvements jointly with truth-distance, hit-rate, interval, convergence, and runtime metrics.

## Recommended Screening Grid

Tier 1 should screen the exact seven frozen crossing-prone replicated rows using Phase 4e compute controls:

- `vb_max_iter = 480`
- `adaptive_vb_max_iter_grid = 480,720`
- `refit_stride = 20`
- `forecast_origin_stride = 10`
- `max_origins_per_scenario = 40`

Recommended first candidate grid:

- `baseline_vb480`
- `tau0_0p5`
- `tau0_0p25`
- `tau0_0p1`
- `zeta2_10`
- `zeta2_4`
- `tau0_0p5_zeta2_10`
- `tau0_0p25_zeta2_10`
- `alpha_sd_0p5`
- `rhs_inner_8`

The full grid is frozen in:

`phase4g_screen_grid.csv`

## Promotion Logic

Hard fail:

- missing artifacts or hashes;
- leakage;
- nonfinite forecasts/scores;
- contract crossings.

Review:

- raw crossings persist with limited reduction;
- truth metrics worsen mildly;
- VB max-iteration rate remains high;
- runtime increases materially.

Promote:

- raw crossing count or max crossing magnitude improves materially;
- contract crossings remain zero;
- truth-distance, hit rates, interval metrics, convergence, and runtime are neutral or improved.

## Implementation Implication

The next implementation should add:

`application/scripts/85_run_joint_qvp_synthetic_dgp_phase4g_prior_design_screen.R`

and narrowly scoped plumbing for:

- `tau0`
- `zeta2`
- `alpha_prior_sd`
- `alpha_min_spacing`
- `rhs_vb_inner`

Defaults must remain unchanged. New controls must be explicit and recorded in output configs.

## Recommended Next Command After Implementation

```bash
Rscript application/scripts/85_run_joint_qvp_synthetic_dgp_phase4g_prior_design_screen.R \
  --targeted-registry application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4c_crossing_audit/targeted_crossing_registry.csv \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4g_prior_design_screen \
  --tier targeted \
  --vb-max-iter 480 \
  --adaptive-vb-max-iter-grid 480,720 \
  --refit-stride 20 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 40
```

## Conclusion

The comprehensive audit supports the targeted prior/design screen as the highest-value next step. A full calibration rerun should wait until the Phase 4g screen identifies one or more candidates that reduce raw crossings without degrading forecast quality.
