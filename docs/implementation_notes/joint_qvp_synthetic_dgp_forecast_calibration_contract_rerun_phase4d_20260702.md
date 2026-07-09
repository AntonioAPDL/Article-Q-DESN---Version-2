# Joint-QVP Synthetic DGP Forecast Calibration Contract Rerun Phase 4d

Date: 2026-07-02  
Scope: preparation and launch protocol for rerunning the full calibration-size
forecast campaign under the Phase 4c raw/contract noncrossing forecast policy.
This stage does not touch TT500, GloFAS, or PriceFM lanes.

## Purpose

Phase 4b showed that the calibration-size campaign was reproducible and finite
but failed because forecast quantiles crossed. Phase 4c fixed the output
contract: raw forecasts are preserved, monotone contract forecasts are scored,
and raw crossings remain review evidence. Phase 4d prepares the full
calibration rerun under that new contract before article-candidate validation is
considered.

This is still not final article evidence. It is the calibration rerun that
should decide whether the article-candidate workflow is unblocked.

## Added Launch Tooling

New helper layer:

```text
app_joint_qvp_prepare_synthetic_dgp_forecast_contract_calibration_rerun()
```

New script:

```sh
Rscript application/scripts/81_prepare_joint_qvp_synthetic_dgp_forecast_contract_calibration_rerun.R
```

The script writes a preflight packet by default. It only launches the expensive
calibration campaign when called with `--execute true`.

The preflight packet contains:

- `contract_rerun_plan.csv`
- `contract_rerun_commands.csv`
- `contract_rerun_preflight.csv`
- `expected_artifacts.csv`
- `calibration_registry_preview.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

## Full Rerun Controls

Prepared output:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702
```

Prepared preflight packet:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4d_contract_calibration_preflight
```

Prepared campaign size:

- 9 enabled base scenarios.
- 5 replicated seeds per base scenario.
- 45 replicated registry rows.
- 40 forecast origins per replicated scenario.
- 1,800 forecast-origin rows.
- 7 forecast quantile levels.
- 12,600 forecast quantile rows.

Controls:

- `tier = calibration`
- `seed_base = 202608000`
- `simulated_length = 1200`
- `washout_length = 300`
- `train_length = 500`
- `test_length = 400`
- `vb_max_iter = 240`
- `adaptive_vb_max_iter_grid = 240,360`
- `refit_stride = 20`
- `forecast_origin_stride = 10`
- `max_origins_per_scenario = 40`

## Runtime Expectation

The previous pre-contract Phase 4b calibration used 27 replicated scenario rows
and recorded about 2,319.7 seconds total, with a mean of about 85.9 seconds per
replicated scenario row.

The Phase 4c exact-seed higher-control follow-up used 3 replicated scenario rows
and recorded about 388.5 seconds total, with a mean of about 129.5 seconds per
replicated scenario row and a maximum of about 145.9 seconds.

The 45-row contract calibration should therefore be treated as a bounded
multi-hour run. A practical planning window is roughly 1.5 to 2.5 hours,
depending on stress-scenario runtime and VB max-iteration behavior.

## Preflight Command

This command prepares the launch packet and does not run the heavy campaign:

```sh
Rscript application/scripts/81_prepare_joint_qvp_synthetic_dgp_forecast_contract_calibration_rerun.R \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702
```

Current preflight outcome:

- Gate: `pass`.
- Replicated registry rows: 45.
- Expected forecast origins: 1,800.
- Expected forecast quantile rows: 12,600.

## Launch Command

Use this command to run the full calibration and both audits from start to
finish:

```sh
Rscript application/scripts/81_prepare_joint_qvp_synthetic_dgp_forecast_contract_calibration_rerun.R \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702 \
  --execute true
```

If the output directory already contains files, the wrapper refuses to run by
default. Use `--overwrite true` only after confirming the existing directory is
not an artifact that must be preserved.

## Equivalent Manual Commands

The preflight packet records the exact manual commands in
`contract_rerun_commands.csv`. The intended sequence is:

1. Run Phase 4 contract calibration.
2. Run Phase 4b readiness audit.
3. Run Phase 4c crossing audit.

The wrapper runs these same steps directly through the R helpers when
`--execute true` is provided.

## Expected Outputs After Execution

Phase 4 root:

- `calibration_registry.csv`
- `calibration_run_config.csv`
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
- `artifact_manifest.csv`

Nested Phase 3:

- `forecast_quantiles_raw.csv`
- `forecast_quantiles.csv`
- `forecast_monotone_adjustment.csv`
- `raw_crossing_summary.csv`
- `crossing_summary.csv`
- `forecast_validation_assessment.csv`
- `artifact_manifest.csv`

Audits:

- `phase4b_readiness_audit/calibration_readiness_summary.csv`
- `phase4b_readiness_audit/article_candidate_recommendation.csv`
- `phase4c_crossing_audit/crossing_remediation_recommendation.csv`

## Decision Gates

Hard fail:

- missing or unverifiable Phase 4, Phase 3, Phase 4b, or Phase 4c hashes;
- train/test leakage;
- nonfinite forecast quantiles, truths, or scores;
- any contract forecast quantile crossing;
- malformed calibration registry or missing provenance.

Review:

- raw forecast crossings corrected by the monotone contract;
- large or frequent monotone adjustments;
- high VB max-iteration rates;
- scenario/family/tau instability in calibrated metrics;
- runtime outliers that affect article-candidate planning.

Pass:

- manifests verify;
- no leakage;
- finite scores;
- zero contract crossings;
- thresholds are finite and candidate-supported;
- only acceptable review evidence remains, or no review evidence remains.

## Interpretation Policy

The contract rerun should not hide raw model behavior. The article-quality
summary should report both:

- contract forecast scores, based on monotone `forecast_quantiles.csv`; and
- raw crossing/adjustment diagnostics, based on `forecast_quantiles_raw.csv`,
  `raw_crossing_summary.csv`, and `forecast_monotone_adjustment.csv`.

If contract crossings are zero but raw crossings remain, article-candidate
validation can be considered unblocked only after reviewing adjustment size and
frequency. Large raw adjustments remain model-behavior evidence, not a software
defect.

## Verification

Focused tests run:

```sh
Rscript -e 'source("application/R/00_packages.R"); app_set_repo_root(normalizePath(".")); source(app_path("application/R/input_contract.R")); source(app_path("application/R/synthesize_quantiles.R")); source(app_path("application/R/score_forecasts.R")); source(app_path("application/R/joint_qvp_qdesn.R")); source(app_path("application/tests/test_joint_qvp_qdesn_synthetic_dgp_forecast_calibration_readiness.R")); source(app_path("application/tests/test_joint_qvp_qdesn_synthetic_dgp_forecast_crossing_audit.R")); source(app_path("application/tests/test_joint_qvp_qdesn_synthetic_dgp_forecast_contract_calibration_rerun.R")); cat("Phase 4b-4d focused tests completed\n")'
```

Outcome: passed.

## Launch Results

The full contract calibration was launched with:

```sh
Rscript application/scripts/81_prepare_joint_qvp_synthetic_dgp_forecast_contract_calibration_rerun.R \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702 \
  --execute true \
  --overwrite true
```

Completed artifact:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702
```

Postrun summary:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4d_contract_calibration_preflight/contract_rerun_postrun_summary.csv
```

Actual outcomes:

- Phase 4 gate: `review`.
- Phase 4b readiness gate: `review`.
- Phase 4c crossing audit gate: `review`.
- Implementation status: `pass`.
- Phase 4, nested Phase 3, Phase 4b, Phase 4c, and Phase 4d manifests all
  verified.
- No train/test leakage was detected.
- Forecasts, true quantiles, and scores were finite.
- Contract forecast crossing pairs: `0`.
- Raw forecast crossing pairs: `23`.
- Raw crossing origins: `23`.
- Monotone-adjusted origins: `23`.
- Maximum monotone adjustment: about `0.0736`.
- Forecast quantile rows: `12,600` raw and `12,600` contract.
- Mean VB max-iteration rate: about `0.602`.
- Maximum VB max-iteration rate: `1.0`.
- Recorded runtime total: about `6,079.4` seconds.
- Maximum replicated-scenario runtime: about `230.4` seconds.

Raw crossing or adjustment review appeared in these replicated rows:

- `laplace_bridge__calibration_r05`: 2 raw crossing pairs.
- `gaussian_mixture_bridge__calibration_r05`: 6 raw crossing pairs.
- `student_t_location_scale__calibration_r05`: 3 raw crossing pairs.
- `asymmetric_laplace_tail__calibration_r02`: 1 raw crossing pair.
- `heteroskedastic_seasonal__calibration_r04`: 1 raw crossing pair.
- `persistent_heavy_tail__calibration_r05`: 8 raw crossing pairs.
- `regime_shift__calibration_r02`: 2 raw crossing pairs.

Threshold support:

- 11 threshold rows have `candidate` support.
- 1 threshold row is `ready_for_article_candidate`.
- No threshold rows are marked `needs_more_calibration`.

Interpretation: the Phase 4c raw/contract policy unblocked the hard crossing
gate for scored forecasts. Article-candidate validation is still not promoted
because the readiness audit is `review`, driven by raw forecast crossings,
monotone adjustments, and VB max-iteration behavior.

## Next Step

The next stage should not repeat the same calibration blindly. The hard
implementation gates passed, so the appropriate follow-up is a targeted review
of raw crossing magnitude/frequency and VB max-iteration behavior before
article-candidate promotion.

Recommended immediate follow-up:

1. Audit the 23 raw crossing origins using the Phase 4c
   `targeted_crossing_registry.csv`.
2. Compare whether higher or scenario-specific VB controls materially reduce
   raw crossings and max-iteration rates.
3. Decide whether the raw crossing/monotone-adjustment rates are acceptable as
   article review evidence under the declared contract.
4. Only then run the article-candidate tier.
