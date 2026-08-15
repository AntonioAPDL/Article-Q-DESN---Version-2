# Joint-QVP Synthetic DGP Forecast Phase 4i Candidate Calibration Pilot

Date: 2026-07-04

## Purpose

Phase 4i promotes the Phase 4h tau0 refinement from a targeted crossing-row screen to a replicated calibration-pilot workflow. It is still not final article evidence. Its purpose is to compare the two Phase 4h survivors under a shared replicated synthetic DGP fixture set:

- `tau0_0p10_primary`: primary candidate from Phase 4h, best global truth MAE with zero contract crossings.
- `tau0_0p15_comparator`: comparator candidate from Phase 4h, similar raw crossings with slightly better upper-tail truth MAE and lower runtime.

The stage keeps the Phase 3 raw/contract forecast policy:

- raw forecast quantiles are preserved for diagnostics;
- monotone contract forecast quantiles are used for scoring;
- contract crossings remain a hard implementation failure;
- raw crossings remain review evidence, not hidden failures.

## Implementation

New implementation entry points:

- `app_joint_qvp_phase4i_tau0_arm_grid()`
- `app_joint_qvp_phase4i_build_candidate_registry()`
- `app_joint_qvp_run_synthetic_dgp_phase4i_tau0_candidate_calibration_pilot()`
- script: `application/scripts/88_run_joint_qvp_synthetic_dgp_phase4i_tau0_candidate_calibration_pilot.R`
- test: `application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4i_tau0_candidate_calibration_pilot.R`

The runner builds one candidate calibration registry, materializes one shared Phase 1 fixture directory, then runs Phase 3 forecast validation once per tau0 arm. This makes the arm comparison deterministic and avoids changing DGP seeds across arms.

## Default Controls

Smoke defaults are intentionally small and test-oriented:

- `tier = smoke`
- `n_replicates = 1`
- `simulated_length = 72`
- `washout_length = 12`
- `train_length = 42`
- `test_length = 18`
- `vb_max_iter = 12`
- `adaptive_vb_max_iter_grid = 12,24`
- `refit_stride = 99`
- `forecast_origin_stride = 1`
- `max_origins_per_scenario = 2`

Calibration-pilot defaults are bounded but realistic enough to evaluate the Phase 4h recommendation:

- `tier = calibration_pilot`
- `n_replicates = 3`
- `simulated_length = 1200`
- `washout_length = 300`
- `train_length = 500`
- `test_length = 400`
- `vb_max_iter = 480`
- `adaptive_vb_max_iter_grid = 480,720`
- `refit_stride = 20`
- `forecast_origin_stride = 10`
- `max_origins_per_scenario = 40`

## Artifacts

The Phase 4i artifact directory writes:

- `candidate_arm_grid.csv`
- `candidate_calibration_registry.csv`
- `candidate_run_config.csv`
- `candidate_arm_run_manifest.csv`
- `candidate_metric_summary.csv`
- `candidate_ranking.csv`
- `candidate_crossing_by_arm.csv`
- `candidate_crossing_by_scenario.csv`
- `candidate_crossing_by_family.csv`
- `candidate_crossing_by_tau_pair.csv`
- `candidate_truth_by_tau.csv`
- `candidate_tail_tradeoff_summary.csv`
- `candidate_vb_runtime_summary.csv`
- `candidate_recommendation.csv`
- `phase4i_readiness_assessment.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

Nested Phase 3 artifacts are written under `arm_runs/<arm_id>/`, and the root `candidate_arm_run_manifest.csv` records and verifies each nested manifest hash.

## Gates

Hard fail:

- malformed candidate registry;
- missing or unverifiable Phase 1 fixture hashes;
- missing or unverifiable nested Phase 3 artifact hashes;
- nonfinite core metrics;
- contract forecast quantile crossings;
- nonfinite ranking scores.

Review:

- any raw forecast quantile crossings;
- mean VB max-iteration rate above 0.20;
- no candidate-level recommendation.

Pass:

- implementation, manifest, finite-metric, ranking, and contract-crossing gates all pass;
- raw-crossing, VB-convergence, and recommendation checks do not trigger review.

## Commands

Focused smoke:

```bash
Rscript application/scripts/88_run_joint_qvp_synthetic_dgp_phase4i_tau0_candidate_calibration_pilot.R \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4i_tau0_candidate_pilot_smoke_20260704 \
  --tier smoke \
  --tau0-arms 0.10,0.15
```

Recommended bounded calibration pilot:

```bash
Rscript application/scripts/88_run_joint_qvp_synthetic_dgp_phase4i_tau0_candidate_calibration_pilot.R \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4i_tau0_candidate_pilot_20260704 \
  --tier calibration_pilot \
  --tau0-arms 0.10,0.15 \
  --n-replicates 3 \
  --seed-base 202607400 \
  --simulated-length 1200 \
  --washout-length 300 \
  --train-length 500 \
  --test-length 400 \
  --vb-max-iter 480 \
  --adaptive-vb-max-iter-grid 480,720 \
  --refit-stride 20 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 40
```

## Next Step

Run the bounded calibration pilot above. If contract crossings remain zero and tau0 `0.10` remains competitive, use it as the article-candidate default. If tau0 `0.15` materially improves upper-tail error or runtime without worsening global truth distance, run one additional bounded tie-breaker before freezing article-candidate controls.
