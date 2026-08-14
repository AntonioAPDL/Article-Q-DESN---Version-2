# Joint-QVP Synthetic DGP Forecast Calibration Phase 4b Readiness

Date: 2026-07-02  
Scope: calibration-size readiness audit for the registry-driven joint
multi-quantile QVP synthetic forecast study. This stage does not change TT500,
GloFAS, or PriceFM outputs.

## Purpose

Phase 4b turns the Phase 4 calibration machinery into a decision layer. Phase 4
proved that replicated calibration fixtures, forecast validation, threshold
candidates, provenance, and manifests can be produced. Phase 4b runs a
calibration-size campaign, audits the result, and decides whether the workflow
is ready for article-candidate validation.

This is not final article evidence. It is a readiness and failure-mode audit
before freezing article validation outputs.

## Added Audit Tooling

Core function:

```text
app_joint_qvp_audit_synthetic_dgp_forecast_calibration()
```

Script:

```sh
Rscript application/scripts/79_audit_joint_qvp_synthetic_dgp_forecast_calibration.R
```

The audit consumes a completed Phase 4 directory and writes:

- `calibration_readiness_summary.csv`
- `threshold_readiness_audit.csv`
- `scenario_failure_mode_audit.csv`
- `family_failure_mode_audit.csv`
- `tau_failure_mode_audit.csv`
- `vb_runtime_readiness_audit.csv`
- `article_candidate_recommendation.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

It verifies both the Phase 4 artifact manifest and the nested Phase 3 artifact
manifest, checks leakage/finiteness/crossing gates, summarizes thresholds,
classifies scenario/family/tau failure modes, and writes a conservative
article-candidate recommendation.

## Smoke Artifact Audit

Smoke source:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_20260702
```

Audit output:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_20260702/phase4b_readiness_audit
```

Smoke outcome:

- Phase 4 manifest hashes verified: yes.
- Nested Phase 3 manifest hashes verified: yes.
- No train/test leakage: yes.
- Finite forecasts and scores: yes.
- Forecast quantile crossings: zero.
- Gate: `review`.
- Recommendation: `review_before_article_candidate`.

The smoke review is expected: it used one replicate and tiny VB iteration
controls, so threshold support and VB convergence were intentionally weak.

## Calibration-Size Run

Command run:

```sh
Rscript application/scripts/78_run_joint_qvp_synthetic_dgp_forecast_calibration.R \
  --tier calibration \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_20260702 \
  --n-replicates 3 \
  --vb-max-iter 120 \
  --adaptive-vb-max-iter-grid 120,240 \
  --refit-stride 20 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 40
```

Calibration artifact:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_20260702
```

Readiness audit:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_20260702/phase4b_readiness_audit
```

Run size:

- 9 base scenarios.
- 3 replicate seeds per scenario.
- 27 replicated registry rows.
- 40 forecast origins per replicated scenario.
- 7 quantile levels.

## Calibration Outcome

Implementation/reproducibility checks:

- Phase 4 manifest hashes verified: yes.
- Nested Phase 3 manifest hashes verified: yes.
- Recorded nested manifest hashes verified: yes.
- No train/test leakage: yes.
- Finite forecasts and scores: yes.
- Total forecast quantile crossing pairs: 8.

Gate outcome:

- Phase 4 gate: `fail`.
- Phase 4b readiness gate: `fail`.
- Recommendation: `blocked_fix_implementation`.

The failure is not due to missing hashes, leakage, or nonfinite scores. It is a
hard crossing-contract failure plus VB convergence review.

## Threshold Readiness

The calibration-size run improved threshold support substantially:

- 11 threshold rows have `candidate` support.
- The crossing threshold remains `ready_for_article_candidate`.
- No threshold rows are marked `needs_more_calibration`.

This means the provisional forecast thresholds are now usable as candidate
calibration summaries, but they cannot be promoted while forecast quantile
crossings remain.

## Failure Modes

Crossing failures are localized to three replicated scenario rows:

- `asymmetric_laplace_tail__calibration_r02`: 1 crossing pair.
- `regime_shift__calibration_r02`: 2 crossing pairs.
- `nonlinear_reservoir_friendly__calibration_r02`: 5 crossing pairs.

The crossing pairs occurred at the extreme adjacent tails:

- lower-tail `0.05` to `0.10` crossings in asymmetric-Laplace and regime-shift
  cases;
- upper-tail `0.90` to `0.95` crossings in the nonlinear reservoir-friendly
  case.

Family-level failures therefore appear in:

- asymmetric Laplace;
- Student-t/regime-shift;
- Gaussian-mixture/nonlinear reservoir-friendly.

Tau-level score summaries themselves did not produce readiness review rows, so
the main defect is not broad tau-score instability. It is localized forecast
quantile nonmonotonicity.

## VB Runtime And Convergence

The calibration run completed as a batch job rather than an interactive smoke
check. The Phase 4b runtime summary reports:

- total recorded runtime: about 2319.7 seconds;
- maximum replicated-scenario runtime: about 113.0 seconds;
- mean VB max-iteration rate: about 0.917;
- maximum VB max-iteration rate: 1.0.

VB convergence remains a review item under `vb_max_iter = 120` with adaptive
grid `120,240`. The next run should either increase VB iteration controls or
diagnose whether the current convergence status is too strict relative to
stable forecast summaries.

## Recommendation

Do not run article-candidate validation yet.

The immediate next step is to resolve or explicitly contract the crossing
behavior before article-candidate promotion. A conservative follow-up command is:

```sh
Rscript application/scripts/78_run_joint_qvp_synthetic_dgp_forecast_calibration.R \
  --tier calibration \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_followup_20260702 \
  --n-replicates 5 \
  --vb-max-iter 180 \
  --adaptive-vb-max-iter-grid 180,300 \
  --refit-stride 20 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 40
```

Before launching the full follow-up, a targeted crossing diagnostic is also
recommended:

```sh
Rscript application/scripts/78_run_joint_qvp_synthetic_dgp_forecast_calibration.R \
  --tier calibration \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_crossing_followup_20260702 \
  --scenario-ids asymmetric_laplace_tail,regime_shift,nonlinear_reservoir_friendly \
  --n-replicates 3 \
  --vb-max-iter 240 \
  --adaptive-vb-max-iter-grid 240,360 \
  --refit-stride 20 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 40
```

Article-candidate validation should only proceed after the crossing hard gate is
clean and VB convergence review is either improved or explicitly justified by
stable finite forecast summaries.
