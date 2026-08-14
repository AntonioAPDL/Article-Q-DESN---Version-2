# Joint-QVP Synthetic DGP Forecast Phase 4j Actual Launch Audit And Plan

Date: 2026-07-04

## Executive Decision

Do not run more smoke tests or pilot campaigns for the synthetic DGP forecast validation lane.

The next stage should be an actual, launch-labelled, article-scale tau0 candidate launch. The launch should compare the only two credible tau0 candidates from Phase 4h:

- `tau0 = 0.10`: primary candidate.
- `tau0 = 0.15`: comparator with possible upper-tail/runtime advantages.

The launch must not produce final artifacts labelled as `smoke`, `pilot`, or `calibration_pilot`. The current Phase 4i implementation is useful infrastructure, but its naming is not article-launch clean enough. Therefore the first implementation task is a small launch-labelled wrapper/refactor, followed immediately by the actual full launch.

## Current Evidence Audited

### Registry

The enabled Phase 1 synthetic DGP registry contains 9 scenarios:

| scenario id | class | family | dynamics |
|---|---|---|---|
| `normal_bridge` | bridge | gaussian | ar1 seasonal location-scale |
| `laplace_bridge` | bridge | laplace | ar1 seasonal location-scale |
| `gaussian_mixture_bridge` | bridge | gaussian mixture | ar1 seasonal location-scale |
| `student_t_location_scale` | stress | student t | ar1 seasonal location-scale |
| `asymmetric_laplace_tail` | stress | asymmetric Laplace | ar1 seasonal location-scale |
| `heteroskedastic_seasonal` | stress | student t | heteroskedastic seasonal |
| `persistent_heavy_tail` | stress | student t | ar1 seasonal location-scale |
| `regime_shift` | stress | student t | regime shift |
| `nonlinear_reservoir_friendly` | stress | gaussian mixture | nonlinear reservoir-friendly |

All use the multi-quantile grid:

```text
0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95
```

### Phase 4h Tau0 Evidence

Phase 4h was a targeted crossing-row refinement, not a full launch. It is still the best available candidate-selection evidence.

| rank | tau0 | raw crossings | upper-tail crossings | contract crossings | truth MAE | tau 0.95 MAE | VB max-iter rate | runtime sec | interpretation |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | 0.10 | 13 | 10 | 0 | 0.1323865 | 0.2243435 | 0.1765 | 954.750 | primary candidate |
| 2 | 0.15 | 13 | 10 | 0 | 0.1365169 | 0.2180140 | 0.1765 | 755.692 | only serious comparator |
| 3 | 0.20 | 14 | 11 | 0 | 0.1377835 | 0.2218685 | 0.1765 | 717.841 | defer |
| 4 | 0.25 | 15 | 12 | 0 | 0.1383506 | 0.2229567 | 0.1250 | 571.601 | stable but less accurate |
| 5 | 0.05 | 17 | 14 | 0 | 0.1322589 | 0.2284943 | 0.1875 | 674.208 | reject, raw geometry worse |
| 6 | 0.075 | 18 | 15 | 0 | 0.1321670 | 0.2253353 | 0.1250 | 950.618 | reject, raw geometry worse |

Diagnosis:

- `tau0 = 0.10` remains primary because it has the best overall rank and best global truth distance among credible candidates.
- `tau0 = 0.15` must be carried into the launch because it ties raw/contract crossings, improves tau `0.95` truth MAE, and reduces runtime.
- `tau0 < 0.10` is rejected because raw crossings and crossing magnitudes worsen sharply.
- `tau0 >= 0.20` is not worth including in the decisive launch because it increases raw crossings and worsens global truth distance.

### Phase 4i Smoke Evidence

Phase 4i smoke verified implementation wiring only:

| item | value |
|---|---:|
| enabled registry rows | 9 |
| candidate arms | 2 |
| contract crossings | 0 |
| raw crossings | 4 |
| mean VB max-iteration rate | 1.0 |
| gate | review |

This is not statistical evidence. It only confirms the two-arm runner, manifests, shared fixtures, and raw/contract forecast policy are working.

## Diagnosis Of Current Implementation Gap

The current Phase 4i code can technically run a large two-arm job by overriding controls, but this is not optimal for an actual launch because:

- the script name contains `candidate_calibration_pilot`;
- the default output directory contains `candidate_pilot`;
- registry versions use `phase4i_calibration_pilot_20260704`;
- scenario ids use `__calibration_pilot_rXX`;
- README/scope/gate labels say `calibration-pilot`;
- tests assert the pilot labels.

For final article-launch reproducibility, naming matters. We should not create expensive final artifacts whose metadata says "pilot." The correct move is a small launch-labelled Phase 4j layer that reuses Phase 4i mechanics but writes launch-clean metadata.

## Optimal Launch Design

### Stage 1: Launch-Labeled Wiring Patch

Add a Phase 4j launch wrapper, not a new modeling engine.

Recommended new entry points:

```text
app_joint_qvp_phase4j_tier_defaults()
app_joint_qvp_run_synthetic_dgp_phase4j_tau0_candidate_launch()
```

Recommended new script:

```text
application/scripts/89_run_joint_qvp_synthetic_dgp_phase4j_tau0_candidate_launch.R
```

Recommended focused test:

```text
application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4j_tau0_candidate_launch.R
```

The wrapper should reuse:

- Phase 1 registry materialization;
- Phase 3 raw/contract forecast validation;
- Phase 4i two-arm comparison helpers;
- existing SHA-256 manifest/provenance helpers.

The wrapper must write launch-clean labels:

- `validation_tier = tau0_candidate_launch`;
- `seed_role = tau0_candidate_launch_replicate_seed`;
- scenario ids like `normal_bridge__tau0_candidate_launch_r01`;
- phase label `phase4j_tau0_candidate_launch`;
- no `smoke`, `pilot`, or `calibration_pilot` labels in launch artifacts.

### Stage 2: Actual Full Tau0 Candidate Launch

Run the full two-arm candidate launch once.

Recommended command:

```bash
Rscript application/scripts/89_run_joint_qvp_synthetic_dgp_phase4j_tau0_candidate_launch.R \
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
  --max-origins-per-scenario 100
```

Expected scale:

| quantity | value |
|---|---:|
| enabled base scenarios | 9 |
| replicates per scenario | 10 |
| replicated scenario rows | 90 |
| tau0 arms | 2 |
| origins per scenario row | 100 |
| forecast origins across both arms | 18,000 |
| quantile forecast rows across both arms | 126,000 |
| expected VB refits per scenario row per arm | 4 |
| expected VB refits across both arms | 720 |

Runtime expectation:

- This is a real launch and can take many hours.
- Phase 4h timing suggests the job is large but appropriate for article-scale validation.
- It should be launched in a durable shell/session with logs captured.

Recommended launch log:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_tau0_candidate_launch_20260704/phase4j_launch.log
```

### Stage 3: Launch Health Audit

Add or reuse an audit script after the launch:

```text
application/scripts/90_audit_joint_qvp_synthetic_dgp_phase4j_tau0_candidate_launch.R
```

It should write:

- `phase4j_launch_health_summary.csv`
- `phase4j_tau0_decision_summary.csv`
- `phase4j_crossing_by_arm_scenario_family_tau.csv`
- `phase4j_truth_distance_by_arm_tau.csv`
- `phase4j_hit_coverage_by_arm_tau.csv`
- `phase4j_vb_convergence_runtime_audit.csv`
- `phase4j_article_candidate_promotion_plan.csv`
- `README.md`
- `artifact_manifest.csv`

The audit must verify:

- root manifest hashes;
- nested Phase 3 manifest hashes;
- fixture hashes;
- no train/test leakage;
- finite forecasts and scores;
- contract crossings equal zero;
- raw crossings and monotone adjustments preserved;
- VB max-iteration rate;
- runtime by arm, scenario, and family;
- selected tau0 decision is reproducible from CSV evidence.

### Stage 4: Tau0 Freeze

Freeze one tau0 from the launch.

Hard fail either arm if:

- contract crossings are positive;
- artifact hashes fail;
- nonfinite forecasts/scores/truth comparisons appear;
- train/test leakage appears.

Prefer `tau0 = 0.10` unless `tau0 = 0.15` clearly improves launch evidence.

Promote `tau0 = 0.15` only if all are true:

- contract crossings remain zero;
- raw crossings are materially lower, or monotone adjustments are materially smaller;
- tau `0.95` truth distance improves;
- global truth MAE/RMSE is no worse by more than a declared tolerance, recommended 1 to 2 percent;
- hit-rate/coverage metrics do not degrade materially;
- runtime or VB convergence is meaningfully better.

Keep `tau0 = 0.10` if:

- it has better global truth distance;
- raw crossing differences are small or scenario-specific;
- `tau0 = 0.15` gains are mostly runtime-only;
- evidence is mixed.

### Stage 5: Article-Candidate Promotion Without Duplicate Compute

Do not immediately rerun the same full validation with the selected tau0 only. The two-arm launch already contains full article-scale Phase 3 artifacts for each arm under identical seeds, scenarios, and controls.

Instead, promote the selected arm into an article-candidate freeze directory:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704
```

The promotion step should copy or reference:

- selected arm nested Phase 3 directory;
- selected arm metrics;
- selected arm raw/contract crossing diagnostics;
- selected arm manifest/provenance;
- tau0 decision summary;
- final readiness assessment.

This avoids wasting compute while preserving exact reproducibility.

Only rerun a selected single-arm article-candidate validation if:

- the two-arm launch had a recoverable artifact error;
- the launch wrapper labels were wrong;
- the selected arm needs different controls than the two-arm launch;
- a reviewer explicitly requires a single-arm final run.

## Pass/Review/Fail Gates

### Hard Fail

- missing or unverifiable root artifact hashes;
- missing or unverifiable nested Phase 3 hashes;
- missing fixture hashes;
- malformed launch registry;
- train/test leakage;
- nonfinite forecast quantiles or scores;
- nonfinite true quantiles;
- contract forecast quantile crossings;
- launch output still labelled as `smoke`, `pilot`, or `calibration_pilot`.

### Review

- raw crossings remain concentrated in the same scenarios;
- large or frequent monotone adjustments;
- VB max-iteration rate above 0.20;
- scenario/family instability between tau0 arms;
- runtime outliers;
- tau0 decision depends on a narrow metric rather than broad evidence.

### Pass

- all implementation and reproducibility gates pass;
- contract crossings are zero;
- raw crossings are preserved and explainable as diagnostic evidence;
- tau0 decision is supported by scenario/family/tau evidence;
- selected arm can be promoted without rerun.

## Why This Is The Optimal Way Forward

This plan is better than the alternatives:

| alternative | decision | reason |
|---|---|---|
| Run Phase 4i as-is with huge controls | reject | final artifacts would still say pilot/calibration_pilot. |
| Run another small pilot | reject | user explicitly wants actual launches; enough implementation validation already exists. |
| Run only `tau0=0.10` | reject | `tau0=0.15` is the only credible comparator and may improve tails/runtime. |
| Include more tau0 values | reject | Phase 4h already ruled out lower and higher values for the decisive launch. |
| Launch two arms and then rerun selected arm | usually reject | duplicate compute; promote selected arm from the full two-arm launch instead. |
| Redesign priors before launch | defer | current evidence supports a decisive tau0 launch first; structural redesign is only needed if launch fails/reviews badly. |

## Immediate Implementation Checklist

1. Commit or otherwise checkpoint current Phase 4h/4i infrastructure separately from unrelated PriceFM/RHS files.
2. Implement Phase 4j launch-labelled wrapper and script.
3. Add focused tests for launch labels, registry seed roles, scenario ids, manifests, and no pilot labels.
4. Run the Phase 4j actual two-arm launch in a durable session.
5. Run Phase 4j health audit.
6. Freeze tau0 decision.
7. Promote selected arm into article-candidate freeze artifacts.
8. Prepare final article validation tables/figures from the freeze directory.

## Expected Next Command After Implementing Phase 4j

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

Create the output directory before launching so the log redirection succeeds.

## Bottom Line

The optimal next move is not another test and not a pilot. It is:

```text
Implement launch-clean Phase 4j labels, then run one full two-arm article-scale tau0 candidate launch, audit it, and promote the selected arm without duplicate compute.
```
