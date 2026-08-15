# Joint-QVP Synthetic DGP Forecast Phase 4j Actual Launch Implementation

Date: 2026-07-04

## Purpose

Phase 4j implements the actual launch-labelled tau0 candidate validation layer for the joint-QVP synthetic DGP forecast study.

This stage replaces pilot-labelled Phase 4i launch attempts with clean launch metadata:

- phase: `phase4j_tau0_candidate_launch`
- tier: `tau0_candidate_launch`
- registry version: `phase4j_tau0_candidate_launch_20260704`
- seed role: `tau0_candidate_launch_replicate_seed`
- scenario ids: `<base_scenario_id>__tau0_candidate_launch_rXX`

The launch compares only the two credible tau0 candidates:

- `tau0_0p10_primary`
- `tau0_0p15_comparator`

## Implemented Entry Points

R helpers in `application/R/joint_qvp_qdesn.R`:

- `app_joint_qvp_default_synthetic_dgp_phase4j_launch_dir()`
- `app_joint_qvp_default_synthetic_dgp_phase4j_freeze_dir()`
- `app_joint_qvp_phase4j_tier_defaults()`
- `app_joint_qvp_phase4j_tau0_arm_grid()`
- `app_joint_qvp_phase4j_build_launch_registry()`
- `app_joint_qvp_run_synthetic_dgp_phase4j_tau0_candidate_launch()`
- `app_joint_qvp_audit_synthetic_dgp_phase4j_tau0_candidate_launch()`

Scripts:

- `application/scripts/89_run_joint_qvp_synthetic_dgp_phase4j_tau0_candidate_launch.R`
- `application/scripts/90_audit_joint_qvp_synthetic_dgp_phase4j_tau0_candidate_launch.R`

Focused implementation test:

- `application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4j_tau0_candidate_launch.R`

## Launch Artifact Contract

The Phase 4j launch writes:

- `launch_arm_grid.csv`
- `launch_registry.csv`
- `launch_run_config.csv`
- `launch_arm_run_manifest.csv`
- `launch_metric_summary.csv`
- `launch_ranking.csv`
- `launch_crossing_by_arm.csv`
- `launch_crossing_by_scenario.csv`
- `launch_crossing_by_family.csv`
- `launch_crossing_by_tau_pair.csv`
- `launch_truth_by_tau.csv`
- `launch_tail_tradeoff_summary.csv`
- `launch_vb_runtime_summary.csv`
- `launch_recommendation.csv`
- `phase4j_readiness_assessment.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

Nested Phase 3 forecast-validation artifacts are written under:

```text
arm_runs/<arm_id>/
```

Each nested artifact manifest is recorded in `launch_arm_run_manifest.csv`.

## Audit Artifact Contract

The Phase 4j audit writes:

- `phase4j_launch_health_summary.csv`
- `phase4j_tau0_decision_summary.csv`
- `phase4j_crossing_by_arm_scenario_family_tau.csv`
- `phase4j_truth_distance_by_arm_tau.csv`
- `phase4j_hit_coverage_by_arm_tau.csv`
- `phase4j_vb_convergence_runtime_audit.csv`
- `phase4j_article_candidate_promotion_plan.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

The audit checks:

- root launch manifest hashes;
- nested Phase 3 manifest hashes;
- fixture manifest hashes;
- launch-clean labels;
- contract crossings;
- raw crossing diagnostics;
- VB convergence/runtime evidence;
- selected tau0 and article-candidate promotion readiness.

## Full Launch Command

Create the launch directory first so log redirection succeeds:

```bash
mkdir -p application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_tau0_candidate_launch_20260704
```

Then launch:

```bash
nohup Rscript application/scripts/89_run_joint_qvp_synthetic_dgp_phase4j_tau0_candidate_launch.R \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_tau0_candidate_launch_20260704 \
  --tier tau0_candidate_launch \
  --tau0-arms 0.10,0.15 \
  --n-replicates 10 \
  --seed-base 202607400 \
  --simulated-length 2500 \
  --washout-length 500 \
  --train-length 1000 \
  --test-length 1000 \
  --vb-max-iter 720 \
  --adaptive-vb-max-iter-grid 720,960 \
  --refit-stride 30 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 100 \
  > application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_tau0_candidate_launch_20260704/phase4j_launch.log 2>&1 &
```

## Audit Command After Completion

```bash
Rscript application/scripts/90_audit_joint_qvp_synthetic_dgp_phase4j_tau0_candidate_launch.R \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_tau0_candidate_launch_20260704
```

## Decision Rule

Prefer `tau0=0.10` unless `tau0=0.15` clearly improves broad launch evidence.

Promote `tau0=0.15` only if:

- contract crossings remain zero;
- raw crossings or monotone adjustment diagnostics improve materially;
- tau `0.95` truth distance improves;
- global truth MAE/RMSE is no worse by more than 1 to 2 percent;
- hit-rate and interval coverage do not materially degrade;
- runtime or VB convergence improves meaningfully.

## Next Step

Run the full Phase 4j launch. After it finishes, run the Phase 4j audit and promote the selected arm into the article-candidate freeze directory without duplicate compute unless the audit finds an implementation defect.
