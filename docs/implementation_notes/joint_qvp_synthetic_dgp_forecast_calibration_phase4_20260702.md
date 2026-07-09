# Joint-QVP Synthetic DGP Forecast Calibration Phase 4

Date: 2026-07-02  
Scope: registry-driven calibration and readiness layer for the joint
multi-quantile QVP synthetic forecast study. This phase does not change TT500,
GloFAS, or PriceFM outputs.

## Purpose

Phase 4 sits after the Phase 3 rolling-origin forecast runner. Phase 3 verifies
held-out forecast behavior for a chosen registry and set of compute controls.
Phase 4 asks whether those controls and provisional forecast gates are ready for
article-scale use.

This is not final article evidence. It generates replicated calibration
registries, runs Phase 3 on those calibration fixtures, summarizes metric
distributions, proposes conservative threshold candidates, and writes an
article-candidate run plan. Final validation tables and figures should only be
frozen after a larger calibration or article-candidate run has been inspected.

## Registry Expansion

Core function:

```text
app_joint_qvp_phase4_build_calibration_registry()
```

The helper starts from the Phase 1 registry, optionally selects base scenario
ids, and expands each selected scenario over replicate seeds. It preserves the
base scenario metadata and adds:

- `base_scenario_id`
- `replicate_id`
- `validation_tier`
- `seed_role`
- `base_seed`

The generated registry is revalidated with the Phase 1 schema and split
constraints. Scenario ids are deterministic, for example
`normal_bridge__smoke_r01`.

## Runner

Core function:

```text
app_joint_qvp_run_synthetic_dgp_forecast_calibration()
```

Script:

```sh
Rscript application/scripts/78_run_joint_qvp_synthetic_dgp_forecast_calibration.R
```

Useful smoke command:

```sh
Rscript application/scripts/78_run_joint_qvp_synthetic_dgp_forecast_calibration.R \
  --tier smoke \
  --scenario-ids normal_bridge,laplace_bridge \
  --n-replicates 1 \
  --vb-max-iter 8 \
  --adaptive-vb-max-iter-grid 8 \
  --refit-stride 99 \
  --max-origins-per-scenario 2
```

Calibration-size command template:

```sh
Rscript application/scripts/78_run_joint_qvp_synthetic_dgp_forecast_calibration.R \
  --tier calibration \
  --n-replicates 5 \
  --vb-max-iter 120 \
  --adaptive-vb-max-iter-grid 120,240 \
  --refit-stride 20 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 40
```

Article-candidate command template:

```sh
Rscript application/scripts/78_run_joint_qvp_synthetic_dgp_forecast_calibration.R \
  --tier article_candidate \
  --n-replicates 10 \
  --vb-max-iter 180 \
  --adaptive-vb-max-iter-grid 180,360,500 \
  --refit-stride 30 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 100
```

The defaults are intentionally safe: smoke mode is small, calibration mode is
realistic but bounded, and article-candidate mode is heavier and should be run
only when the calibration evidence is understood.

## Outputs

Default output:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_20260702/
```

The runner writes:

- `calibration_registry.csv`
- `calibration_run_config.csv`
- `phase3_artifact_manifest.csv`
- `forecast_metric_distribution_summary.csv`
- `forecast_metric_by_scenario_summary.csv`
- `forecast_metric_by_family_summary.csv`
- `forecast_metric_by_tau_summary.csv`
- `interval_metric_summary.csv`
- `vb_convergence_calibration_summary.csv`
- `runtime_calibration_summary.csv`
- `forecast_calibrated_thresholds.csv`
- `forecast_calibration_assessment.csv`
- `article_candidate_run_plan.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

The underlying Phase 3 forecast-validation artifacts are written under:

```text
phase3_forecast_validation/
```

inside the Phase 4 artifact directory.

## Threshold Logic

`forecast_calibrated_thresholds.csv` contains candidate thresholds with:

- threshold name and metric;
- scope;
- recommended pass and review thresholds;
- calibration quantile used;
- number of finite calibration rows;
- rationale;
- status.

The default global thresholds use high empirical calibration quantiles, with
simple safeguards for bounded errors. Hit-rate and interval-coverage errors are
bounded to `[0, 1]`, normalized truth-distance thresholds have a conservative
floor, and crossings remain a hard implementation failure with a threshold of
zero.

Threshold statuses are deliberately conservative:

- `needs_more_calibration`: too few replicates or finite rows;
- `candidate`: enough support for internal use, not final promotion;
- `ready_for_article_candidate`: enough support for an article-candidate run.

## Gates

Hard failures include:

- missing or unverifiable Phase 3 artifact hashes;
- malformed calibration registry;
- train/test leakage inherited from Phase 3;
- nonfinite forecast quantiles, truth values, or scores;
- forecast quantile crossings;
- missing provenance or artifact manifests;
- missing or nonfinite threshold rows.

Review statuses include:

- too few calibration replicates;
- thresholds marked `needs_more_calibration`;
- high VB max-iteration rates;
- runtime outliers that need article-scale planning.

Passing Phase 4 means implementation, reproducibility, finiteness, crossing,
and threshold-completeness gates pass for the calibration run. It does not mean
the final article validation claim is complete.

## Tests

Focused Phase 4 tests exercise:

- deterministic registry expansion and unique scenario ids;
- Phase 1 schema validity for generated calibration registries;
- smoke calibration runner artifacts and schemas;
- finite metric summaries and threshold rows;
- SHA-256 artifact manifest completeness;
- stable repeated smoke-run hashes for deterministic non-runtime artifacts.

The Phase 1, Phase 2, and Phase 3 focused tests should continue to pass after
Phase 4 changes.

## Next Step

Run a calibration-size Phase 4 campaign over all enabled scenarios, inspect the
threshold support and VB convergence summaries, then run the article-candidate
Phase 3/Phase 4 workflow with realistic controls before freezing final
validation tables and figures.
