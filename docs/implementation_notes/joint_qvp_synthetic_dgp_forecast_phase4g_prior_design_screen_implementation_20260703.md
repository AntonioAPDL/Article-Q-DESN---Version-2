# Joint-QVP Synthetic DGP Forecast Phase 4g Prior/Design Screen Implementation

Date: 2026-07-03

## Purpose

Phase 4g implements the targeted screening layer recommended after the Phase 4f/4g audit work. The goal is not to replace the Phase 4c raw/contract noncrossing forecast policy. The goal is to test whether conservative prior/design controls can reduce raw forecast quantile crossings and improve or preserve fit/forecast diagnostics on the exact Phase 4c targeted crossing rows.

The screen is deliberately bounded and inspectable. It uses frozen replicated scenario rows, records all controls, preserves raw forecasts, scores only the monotone contract forecasts, and treats large raw adjustments as review evidence.

## Implemented Controls

The Phase 3 forecast runner now exposes and records:

- `tau0`: RHS global shrinkage scale.
- `zeta2`: shared-coefficient coupling variance, with default `Inf`.
- `alpha_prior_sd`: intercept prior scale.
- `alpha_min_spacing`: intercept spacing floor, with default `0`.
- `rhs_vb_inner`: RHS prior-state VB inner iterations.
- `vb_tol`: VB tolerance.

Defaults remain unchanged relative to the existing validation path: `tau0 = 1`, `zeta2 = Inf`, `alpha_prior_sd = 1`, `alpha_min_spacing = 0`, `rhs_vb_inner = 5`, and `vb_tol = 1e-4`.

## Screen Grid

The targeted grid is:

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

Smoke mode uses a reduced grid by default:

- `baseline_vb480`
- `tau0_0p5`
- `zeta2_10`

## Artifacts

Script:

```bash
Rscript application/scripts/85_run_joint_qvp_synthetic_dgp_phase4g_prior_design_screen.R
```

Default targeted registry:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4c_crossing_audit/targeted_crossing_registry.csv
```

Default output:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4g_prior_design_screen
```

Root artifacts:

- `targeted_registry.csv`
- `screen_grid.csv`
- `screen_run_config.csv`
- `screen_metric_summary.csv`
- `screen_candidate_ranking.csv`
- `screen_crossing_summary.csv`
- `screen_truth_metric_summary.csv`
- `screen_vb_runtime_summary.csv`
- `screen_run_manifest.csv`
- `screen_recommendation.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

Each candidate screen also writes a nested Phase 3 artifact directory under `screen_runs/<screen_id>/`.

## Recommended Commands

Fast smoke check:

```bash
Rscript application/scripts/85_run_joint_qvp_synthetic_dgp_phase4g_prior_design_screen.R \
  --tier smoke \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4g_prior_design_screen_smoke_20260703
```

Targeted screen:

```bash
Rscript application/scripts/85_run_joint_qvp_synthetic_dgp_phase4g_prior_design_screen.R \
  --tier targeted \
  --vb-max-iter 480 \
  --adaptive-vb-max-iter-grid 480,720 \
  --refit-stride 20 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 40 \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4g_prior_design_screen
```

## Gates

Hard fail:

- missing or unverifiable manifests;
- nonfinite required metrics;
- contract forecast quantile crossings.

Review:

- raw crossings remain;
- monotone adjustments remain large or frequent;
- truth MAE worsens beyond the screen tolerance;
- hit-rate error worsens beyond the screen tolerance;
- VB max-iteration rates remain high;
- runtime is more than twice the baseline screen.

Promotion to a calibration pilot requires at least 50 percent reduction in raw crossing count or raw crossing magnitude, no contract crossings, no material truth or hit-rate degradation, acceptable VB max-iteration rate, and acceptable runtime.

## Next Step

Run the targeted screen over the frozen Phase 4c rows. If a candidate is promoted, rerun a calibration pilot with only that candidate under the same raw/contract policy. If no candidate is promoted, keep the raw/contract policy for article-candidate validation and move the remaining raw-crossing behavior to a model-design review rather than tuning thresholds around it.
