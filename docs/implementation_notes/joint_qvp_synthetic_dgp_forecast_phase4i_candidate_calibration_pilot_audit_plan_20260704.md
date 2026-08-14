# Joint-QVP Synthetic DGP Forecast Phase 4i Candidate Calibration Pilot: Audit, Diagnosis, And Plan

Date: 2026-07-04

## Purpose

This note turns the Phase 4h closeout recommendation into a concrete Phase 4i implementation plan. The goal is to verify that the proposed next step is truly optimal before spending more compute or changing article-candidate defaults.

The audited recommendation is:

```text
Run a bounded two-arm calibration pilot with tau0 = 0.10 as the primary candidate and tau0 = 0.15 as a stability/tail comparator.
```

This is the best next step because Phase 4h was intentionally targeted to known crossing rows. It is strong evidence about the local tau0 tradeoff, but it is not yet evidence that the candidate generalizes across the registry and replicate seeds.

## Source Evidence Audited

Primary Phase 4h artifact:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4h_tau0_refinement
```

Primary closeout note:

```text
docs/implementation_notes/joint_qvp_synthetic_dgp_forecast_phase4h_closeout_next_plan_20260704.md
```

Code paths inspected:

- `app_joint_qvp_run_synthetic_dgp_forecast_validation()`
- `app_joint_qvp_run_synthetic_dgp_forecast_calibration()`
- `app_joint_qvp_phase4_build_calibration_registry()`
- `app_joint_qvp_run_synthetic_dgp_phase4g_prior_design_screen()`
- `app_joint_qvp_run_synthetic_dgp_phase4h_tau0_refinement()`
- `application/scripts/78_run_joint_qvp_synthetic_dgp_forecast_calibration.R`
- `application/scripts/87_run_joint_qvp_synthetic_dgp_phase4h_tau0_refinement.R`

Health checks:

| item | status | evidence | interpretation |
|---|---|---|---|
| Phase 4h run | pass | log ended with `PHASE4H_EXIT_CODE=0` | Completed normally. |
| Root manifest | pass | 13 rows, all SHA-256 hashes verified | Root outputs reproducible. |
| Nested manifests | pass | 6 of 6 nested Phase 3 manifests verified independently | Nested forecast outputs reproducible. |
| Frozen targeted registry | pass | 7 exact Phase 4c scenario rows/seeds | No seed drift. |
| Contract crossings | pass | 0 for all six tau0 screens | Scoring contract remains safe. |
| Raw crossings | review | best candidates still have 13 raw crossings | Raw model behavior remains diagnostic review evidence. |
| VB convergence | review | best candidate max-iteration rate 0.1765 | Acceptable for pilot, not final clean evidence. |
| Phase 4h recommendation | review | `reference_remains_candidate_for_calibration_pilot` | Ready for calibration pilot only. |

## Phase 4h Evidence Summary

| rank | screen | tau0 | raw crossings | upper-tail crossings | max raw crossing | contract crossings | truth MAE | tau=0.95 MAE | VB max-iter rate | runtime sec |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | `tau0_0p10_reference` | 0.100 | 13 | 10 | 0.1231 | 0 | 0.1323865 | 0.2243435 | 0.1765 | 954.750 |
| 2 | `tau0_0p15` | 0.150 | 13 | 10 | 0.1239 | 0 | 0.1365169 | 0.2180140 | 0.1765 | 755.692 |
| 3 | `tau0_0p2` | 0.200 | 14 | 11 | 0.1286 | 0 | 0.1377835 | 0.2218685 | 0.1765 | 717.841 |
| 4 | `tau0_0p25_reference` | 0.250 | 15 | 12 | 0.1319 | 0 | 0.1383506 | 0.2229567 | 0.1250 | 571.601 |
| 5 | `tau0_0p05` | 0.050 | 17 | 14 | 0.2756 | 0 | 0.1322589 | 0.2284943 | 0.1875 | 674.208 |
| 6 | `tau0_0p075` | 0.075 | 18 | 15 | 0.2934 | 0 | 0.1321670 | 0.2253353 | 0.1250 | 950.618 |

Interpretation:

- `tau0 = 0.10` remains the formal best candidate.
- `tau0 = 0.15` is the only serious comparator.
- `tau0 < 0.10` is not promising because raw crossing counts and magnitudes worsen sharply.
- `tau0 = 0.20` and `0.25` are stable but leave more raw crossings and worse global truth MAE.

## Detailed Diagnostic Findings

### 1. Why tau0 = 0.10 remains primary

`tau0 = 0.10` has:

- best Phase 4h rank;
- tied lowest raw crossing count;
- tied lowest upper-tail `0.90-0.95` crossing count;
- lowest max raw crossing magnitude among the tied candidates;
- best global truth MAE among non-over-shrunk candidates;
- zero contract crossings.

It is not perfect:

- runtime is the slowest among the leading candidates;
- VB max-iteration rate remains review-level at 0.1765;
- it has one `0.75-0.90` raw crossing;
- residual raw crossings remain concentrated in persistent heavy-tail and related stress rows.

Conclusion:

```text
tau0 = 0.10 is strong enough for calibration-pilot promotion, not strong enough for direct article-candidate default promotion.
```

### 2. Why tau0 = 0.15 should be included

`tau0 = 0.15` ties `tau0 = 0.10` on:

- total raw crossings: 13 vs 13;
- upper-tail crossings: 10 vs 10;
- contract crossings: 0 vs 0;
- VB max-iteration rate: 0.1765 vs 0.1765.

It improves:

- runtime by about 21 percent;
- `tau = 0.95` truth MAE: 0.2180140 vs 0.2243435;
- crossing migration: no `0.75-0.90` crossing.

It worsens:

- global truth MAE by about 3.12 percent;
- lower-tail crossings: 3 vs 2;
- `tau = 0.05`, `0.10`, and `0.90` truth MAE.

Conclusion:

```text
tau0 = 0.15 is not the current winner, but it is a scientifically meaningful comparator that may generalize better across calibration replicates or article-scale runtime constraints.
```

### 3. Why tau0 below 0.10 should not be carried forward

`tau0 = 0.075` and `tau0 = 0.05` have attractive global truth MAE but fail the raw-geometry diagnostic:

- raw crossings increase to 18 and 17;
- upper-tail crossings increase to 15 and 14;
- max raw crossing magnitudes more than double relative to `tau0 = 0.10`;
- persistent heavy-tail crossings jump from 5 at `tau0 = 0.10` to 10 at both `0.075` and `0.05`.

Conclusion:

```text
Values below 0.10 over-shrink or destabilize the targeted raw tail geometry and should not be included in the pilot.
```

### 4. Scenario-level residual diagnosis

For `tau0 = 0.10` vs `tau0 = 0.15`:

| base scenario | tau0=0.10 crossings | tau0=0.15 crossings | interpretation |
|---|---:|---:|---|
| `persistent_heavy_tail` | 5 | 6 | main residual blocker; `0.10` is better |
| `student_t_location_scale` | 3 | 2 | `0.15` helps |
| `gaussian_mixture_bridge` | 2 | 2 | tied |
| `regime_shift` | 2 | 2 | insensitive |
| `laplace_bridge` | 1 | 1 | tied |
| `asymmetric_laplace_tail` | 0 | 0 | clean |
| `heteroskedastic_seasonal` | 0 | 0 | clean |

Conclusion:

```text
Scalar tau0 is helpful but not a complete structural fix. If the pilot confirms persistent heavy-tail/regime-shift residuals, the next stage should be structural diagnostics rather than more scalar tau0 tuning.
```

## Alternatives Rechecked

| option | decision | reason |
|---|---|---|
| Direct article-candidate run with `tau0=0.10` | reject | Phase 4h is targeted evidence, not replicated calibration evidence. |
| Full calibration with only `tau0=0.10` | reject | Would miss whether `0.15` generalizes better for runtime/tails. |
| Include `tau0=0.20` or `0.25` in primary pilot | defer | Useful references, but not necessary for a bounded pilot; they are worse on crossings and global truth MAE. |
| Include `tau0 < 0.10` | reject | Raw crossing geometry worsened sharply. |
| Start structural shrinkage redesign now | defer | Only justified if the two-arm pilot fails to generalize or residual scenario patterns persist. |
| Keep current raw/contract policy and stop tuning | reject | Phase 4h showed meaningful candidate differences worth validating. |

## Implementation Wiring Audit

Existing usable pieces:

- Phase 3 forecast validation already accepts `tau0`, `zeta2`, `alpha_prior_sd`, `rhs_vb_inner`, VB controls, refit controls, and writes raw/contract forecast diagnostics.
- Phase 4 registry expansion already creates replicated calibration registries with fixed seed roles.
- Phase 4 calibration summaries already compute metric distributions, thresholds, runtime, convergence, and readiness artifacts.
- Phase 4h already provides a tested pattern for candidate-screen loops and arm-level aggregation.

Gap:

```text
The existing Phase 4 calibration runner does not yet expose tau0 as an arm-level calibration control.
```

Therefore the best implementation is not a rewrite. It should add a thin Phase 4i candidate-arm layer that:

1. uses Phase 4 registry expansion;
2. runs Phase 3 once per `tau0` arm;
3. reuses Phase 4-style distribution summaries and Phase 4h-style arm comparisons;
4. writes root arm-comparison artifacts with manifests and provenance.

## Recommended Phase 4i Design

Add a runner:

```text
app_joint_qvp_run_synthetic_dgp_phase4i_tau0_candidate_calibration_pilot()
```

Add a script:

```text
application/scripts/88_run_joint_qvp_synthetic_dgp_phase4i_tau0_candidate_calibration_pilot.R
```

Default output directory:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4i_tau0_candidate_pilot_20260704
```

Primary candidate arms:

| arm id | tau0 | role |
|---|---:|---|
| `tau0_0p10_primary` | 0.10 | primary candidate from Phase 4h |
| `tau0_0p15_comparator` | 0.15 | stability/tail comparator |

Optional reference arm:

| arm id | tau0 | role |
|---|---:|---|
| `tau0_0p25_reference` | 0.25 | stable lower-VB-reference, only if compute allows |

The default should be two arms. The optional reference should require an explicit flag such as `--include-reference-arm`.

## Recommended Compute Controls

Pilot defaults:

```text
tier = calibration_pilot
n_replicates = 3
seed_base = 202607400
simulated_length = 1200
washout_length = 300
train_length = 500
test_length = 400
vb_max_iter = 480
adaptive_vb_max_iter_grid = 480,720
refit_stride = 20
forecast_origin_stride = 10
max_origins_per_scenario = 40
```

Reasoning:

- Keep VB controls identical to Phase 4h so candidate differences are not confounded by compute.
- Use three replicates to get minimal candidate-level support.
- Keep `max_origins_per_scenario = 40` to match the targeted-screen origin budget.
- Use fresh pilot seeds to test generalization beyond the frozen Phase 4c crossing rows.

Runtime expectation:

- Phase 4h six-arm targeted run took about 80 minutes wall-clock under the observed environment.
- A two-arm, three-replicate all-scenario pilot is expected to be heavier than Phase 4h because it expands to all enabled scenarios over replicates.
- If runtime becomes too high, reduce `n_replicates` to 2 and label the run `calibration_pilot_r2`; do not reduce VB controls first.

## Required Artifacts

Root Phase 4i artifact directory should write:

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

Nested arm outputs should be written under:

```text
arm_runs/<arm_id>/
```

Each arm directory should contain a complete Phase 3 forecast-validation artifact set and artifact manifest.

## Required Tests

Add focused tests for:

- candidate arm grid construction;
- deterministic seed expansion for pilot registries;
- arm-level `tau0` propagation into nested Phase 3 `run_config.csv`;
- smoke run with two tiny scenarios, two arms, and tiny lengths;
- schema of all root Phase 4i artifacts;
- root and nested SHA-256 manifest completeness;
- finite candidate metrics;
- zero contract crossings in smoke;
- recommendation schema and allowed statuses;
- existing Phase 4h focused test still passing.

Recommended focused verification command:

```bash
Rscript -e 'source("application/R/00_packages.R"); app_set_repo_root(getwd()); source(app_path("application/R/input_contract.R")); source(app_path("application/R/synthesize_quantiles.R")); source(app_path("application/R/score_forecasts.R")); source(app_path("application/R/joint_qvp_qdesn.R")); source(app_path("application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4h_tau0_refinement.R")); source(app_path("application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4i_tau0_candidate_calibration_pilot.R"))'
```

## Decision Gates

Hard fail:

- missing root or nested manifests;
- failed SHA-256 verification;
- malformed pilot registry;
- seed drift or duplicate scenario ids;
- train/test leakage;
- nonfinite forecasts, truth metrics, or scores;
- contract forecast crossings;
- missing provenance.

Review:

- raw crossings remain high or concentrated in the same scenarios;
- VB max-iteration rate exceeds 0.20 for a candidate arm;
- runtime per arm is not article-scale feasible;
- `tau0=0.15` improves tails but worsens global metrics persistently;
- candidate ranking differs strongly by scenario family or tau.

Candidate for next stage:

- one arm dominates or is clearly preferable under the declared tradeoff rules;
- contract crossings remain zero;
- truth MAE and tail MAE are stable across replicates;
- raw crossing rate is materially lower than the old baseline profile;
- VB/runtime are acceptable for article-candidate planning.

## Candidate Selection Rules

Prefer `tau0 = 0.10` if:

- it has lower global truth MAE;
- it ties or beats raw crossings;
- persistent-heavy-tail behavior remains better;
- VB max-iteration rate stays at or below 0.20;
- runtime remains acceptable.

Prefer `tau0 = 0.15` only if:

- the global truth MAE penalty disappears or becomes negligible across replicates;
- it maintains better `tau = 0.95` performance;
- it ties or improves total and upper-tail raw crossings;
- runtime advantage persists;
- persistent-heavy-tail residuals do not worsen materially.

Escalate to structural diagnostics if:

- neither arm improves raw diagnostics consistently;
- persistent-heavy-tail and regime-shift residuals remain concentrated;
- raw crossings remain sensitive to scenario dynamics rather than tau0;
- VB max-iteration rates remain review-level across arms.

## Recommended Immediate Command After Implementation

Smoke:

```bash
Rscript application/scripts/88_run_joint_qvp_synthetic_dgp_phase4i_tau0_candidate_calibration_pilot.R \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4i_tau0_candidate_pilot_smoke_20260704 \
  --scenario-ids normal_bridge,laplace_bridge \
  --tau0-arms 0.10,0.15 \
  --n-replicates 1 \
  --simulated-length 72 \
  --washout-length 12 \
  --train-length 42 \
  --test-length 18 \
  --vb-max-iter 12 \
  --adaptive-vb-max-iter-grid 12,24 \
  --refit-stride 99 \
  --forecast-origin-stride 1 \
  --max-origins-per-scenario 2
```

Pilot:

```bash
Rscript application/scripts/88_run_joint_qvp_synthetic_dgp_phase4i_tau0_candidate_calibration_pilot.R \
  --registry application/config/joint_qvp_synthetic_dgp_registry_phase1.csv \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4i_tau0_candidate_pilot_20260704 \
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

## Final Recommendation

Phase 4i should be implemented next as a two-arm calibration pilot, not as a full article-candidate run and not as a structural redesign.

This is optimal because it:

- directly tests the only unresolved Phase 4h question;
- preserves the raw/contract forecast policy;
- keeps the study reproducible through fixed seed roles and manifests;
- reuses validated Phase 3/Phase 4/Phase 4h machinery;
- avoids over-tuning on targeted crossing rows;
- creates the evidence needed to justify either a candidate default or a structural diagnostic stage.

