# Joint QDESN Phase 106: VB specification screening audit and implementation plan

Date: 2026-07-06

This note defines the next stage after the joint QDESN article evidence pack. The purpose is to determine whether the current VB article table should be replaced by a better calibrated single specification before moving to MCMC.

## Current Evidence

The current article evidence pack is reproducible and implementation-clean, but it should be treated as the first complete VB evidence pack rather than the final specification search.

| Article row | Forecast MAE | Check loss | Raw crossings | Contract crossings | Diagnosis |
|---|---:|---:|---:|---:|---|
| Joint QDESN RHS | 0.103 | 0.161 | 4 | 0 | Strongest current row; mild convergence/raw-crossing review. |
| Independent QDESN RHS | 0.104 | 0.161 | 157 | 0 | Accuracy is close to the joint AL row, but raw monotone repair is much larger. |
| Joint exQDESN RHS | 0.155 | 0.163 | 0 | 0 | Stable and coherent, but less accurate, especially in extreme tails. |
| Independent exQDESN RHS | 58.502 | 19.417 | 1102 | 0 | Not article-ready; dominated by an asymmetric-tail K=1 exAL failure. |

The evidence supports the following interpretation:

- the AL likelihood under RHS is already competitive for both fit and forecast;
- joint fitting improves raw monotonicity relative to independent single-quantile AL fits;
- joint exAL is numerically stable but not yet competitive in accuracy;
- independent exAL is not merely untuned; it has a localized numerical/statistical pathology around the asymmetric-tail scenario and tau = 0.75;
- most rows still reach conservative VB iteration caps, but the targeted 720/960-iteration audit showed negligible score movement except one review-level quantile-delta row.

## Key Implementation Finding

The validation controls expose `alpha_prior_sd`, and AL uses an empirical-quantile alpha prior. The exAL VB-LD function, however, does not currently include the same alpha-prior contribution in its alpha-coordinate update. This means the current exAL rows are not using the full declared stabilizing contract.

Phase 106 should therefore do two things before MCMC:

1. make the exAL alpha-prior contract explicit and backwards-compatible;
2. screen a small number of full-scenario VB specifications over the frozen fixtures.

This is a targeted calibration stage, not an open-ended search.

## Why Screening Before MCMC Is Optimal

MCMC should confirm a stable VB specification. It should not be used to choose between several uncalibrated VB specifications or to rescue a known independent exAL pathology. Running MCMC now would mix three questions:

1. whether the RHS shrinkage is calibrated;
2. whether the exAL alpha/gamma/sigma updates are stable;
3. whether posterior uncertainty agrees with the selected VB approximation.

The optimal order is therefore:

1. freeze the synthetic fixtures;
2. screen VB specifications using fit and forecast evidence;
3. select a single table-ready VB specification;
4. regenerate manuscript assets from the selected specification;
5. run VB-initialized MCMC for selected stable rows and scenarios.

## Screening Scope

The screening must use the same frozen fixture directory:

`application/cache/joint_qdesn_simulation_dgp_fixtures_20260706`

It must evaluate the same four article model classes:

- Joint QDESN RHS;
- Independent QDESN RHS;
- Joint exQDESN RHS;
- Independent exQDESN RHS.

It must evaluate both:

- fit-window recovery against oracle conditional quantiles;
- no-refit held-out forecast validation over the frozen validation-origin plan.

It must preserve raw and monotone-contract quantiles, and it must continue scoring only the noncrossing contract quantiles.

## Candidate Specification Registry

The default candidate registry should be small and interpretable. It should include the current article baseline by reference, then full-rerun candidates that test one statistically meaningful change at a time.

Recommended defaults:

| Candidate | Purpose |
|---|---|
| `baseline_current` | Existing article-scale artifacts: `tau0=1`, `zeta2=Inf`, `alpha_prior_sd=1`, `alpha_min_spacing=0`, `240,480` iteration grid. |
| `rhs_tau0_0p5` | Stronger RHS shrinkage. Smaller `tau0` means stronger global shrinkage. |
| `rhs_tau0_0p25` | More aggressive RHS shrinkage for raw-crossing/noise reduction. |
| `rhs_tau0_0p5_alpha0p5` | Stronger RHS shrinkage plus tighter empirical alpha prior, especially relevant after adding exAL alpha-prior support. |

Avoid a large grid at this stage. Each full candidate over all scenarios and all four models is expensive. The recorded current validation runtime suggests about 20 minutes for fit and 19 minutes for forecast per candidate when nine scenario-level workers are available.

## Gates

Hard fail:

- missing or mismatched source hashes;
- nonfinite quantiles, scores, traces, RHS summaries, or scale summaries;
- nonpositive scale paths;
- contract quantile crossings;
- train/validation leakage;
- missing provenance or artifact manifests;
- catastrophic scenario/tau behavior, defined as any stable row with extreme truth distance that is orders of magnitude larger than the rest of the table.

Review:

- VB reaches max iterations but produces finite, stable scores;
- raw crossings before monotone contract;
- large monotone adjustment;
- exAL worse than AL by a practically material margin;
- runtime increase too large for later MCMC initialization;
- independent exAL remains unstable even after the explicit alpha-prior contract.

Pass:

- all implementation gates pass;
- contract quantiles are finite and noncrossing;
- fit and forecast metrics are finite;
- raw crossing and monotone-adjustment rates are acceptable or clearly smaller than baseline;
- no model row contains a catastrophic scenario/tau failure.

## Ranking Rule

Screening should use gates first and metrics second.

Primary ranking:

1. no hard failures;
2. no catastrophic independent exAL failure if independent exAL is to remain in the main table;
3. low forecast truth MAE/RMSE;
4. low fit truth MAE/RMSE;
5. low check loss and CRPS-grid;
6. low raw crossing count and max monotone adjustment;
7. acceptable hit-rate and interval-coverage errors;
8. acceptable runtime.

The selected specification does not need to minimize every metric. It should be the best article-ready compromise across fit, forecast, stability, and interpretability.

## Artifacts

The Phase 106 screening directory should contain:

- `candidate_registry.csv`;
- `screening_run_config.csv`;
- `candidate_artifact_dirs.csv`;
- `candidate_manifest_verification.csv`;
- `fit_model_metric_summary.csv`;
- `forecast_model_metric_summary.csv`;
- `fit_scenario_metric_summary.csv`;
- `forecast_scenario_metric_summary.csv`;
- `forecast_tau_metric_summary.csv`;
- `candidate_scorecard.csv`;
- `selected_spec_recommendation.csv`;
- `screening_health_summary.csv`;
- `provenance.csv`;
- `README.md`;
- `artifact_manifest.csv`.

Candidate-specific full validation artifacts should be written under:

`application/cache/joint_qdesn_vb_spec_screening_phase106_20260706/candidates/<candidate_id>/fit`

and

`application/cache/joint_qdesn_vb_spec_screening_phase106_20260706/candidates/<candidate_id>/forecast`

The baseline candidate may reference the existing article-scale artifact directories instead of rerunning them.

## Tests

Focused tests should cover:

- exAL alpha-prior arguments are accepted and recorded;
- a small deterministic fixture can run the screening layer;
- candidate ids are unique;
- baseline artifact references can be verified;
- candidate manifests are verified;
- top-level screening artifacts exist and have SHA-256 hashes;
- scorecard and selected-spec recommendation schemas are stable;
- contract quantiles remain noncrossing in the screening smoke fixture.

The tests should remain fast by using a reduced temporary fixture. The production Phase 106 run should use the frozen full fixtures and all four model rows.

## Definition of Done

- The exAL alpha-prior contract is implemented and tested.
- A reproducible Phase 106 screening helper and script exist.
- A documented candidate registry is generated.
- The screening runner can reuse the current baseline artifacts and launch full new candidates.
- Top-level screening audits, manifests, and recommendations are written.
- Focused tests pass.
- The production screening run is launched or completed with clear artifact paths and status.
- MCMC remains deferred until the selected VB specification is frozen.
