# Joint-QVP Synthetic Validation Study Plan

Date: 2026-07-02  
Scope: joint multi-quantile QVP/Q-DESN validation planning for the article
lane. This note does not change the TT500, GloFAS, or PriceFM application
handoffs.

## Executive Recommendation

Build a new multi-quantile synthetic validation study instead of using the old
Q-DESN synthetic data sets as the primary evidence.

The old Q-DESN validation data are still valuable, but mainly as a baseline and
infrastructure reference. They were designed for single-target quantile fits
across families, inference methods, priors, and training sizes. The joint-QVP
model now needs a validation study that tests the full object it estimates:
several conditional quantile levels at the same time, noncrossing behavior,
posterior/variational uncertainty for the quantile curves, fit recovery, and
rolling-origin forecast performance.

The best path is therefore:

1. Keep the existing Q-DESN TT500 and historical 144-fit studies as article
   context and baseline comparators.
2. Promote the current joint-QVP time-series synthetic suite into a formal
   registry with larger train/test windows, repeated seeds, and explicit
   forecast blocks.
3. Add bridge scenarios that preserve the article's current synthetic families
   (`normal`, `laplace`, `gausmix`) and stress scenarios that target the new
   joint-QVP model behavior (`student_t`, asymmetric Laplace, heteroskedastic
   scale, persistence, regime changes).
4. Use VB as the first validation engine, then use selected VB fits to
   initialize longer MCMC references.

This gives us a study that is professional, reproducible, efficient, and aligned
with the current repo architecture.

## Repo Findings

### Existing Article Simulation Study

The manuscript section `Simulation Validation Study` already defines a
controlled fit-and-forecast validation. It uses known dynamic oracle quantile
paths, fixed target quantile levels, and a held-out rolling-origin forecast
block. The section currently reports the finalized TT500 handoff through
`tables/qdesn_validation_tt500_final_*`.

Key properties already in place:

- Families: Gaussian, Laplace, and Gaussian mixture.
- Target quantile levels: `0.05`, `0.25`, and `0.50`.
- TT500 training window: source indices `8501:9000`.
- Forecast block: source indices `9001:10000`.
- Rolling-origin protocol: leads `1:30`, stride `30`, no refit.
- Metrics: fit oracle-quantile RMSE, fit pinball loss, forecast oracle-quantile
  MAE/RMSE, forecast pinball loss, and runtime.
- Strong provenance: exact interface hashes, source registry hash, branch,
  commit, table manifest, and article-side guards.

This is rigorous, but it is single-quantile per fit and fixed-root. It is not a
complete validation of a joint multi-quantile QVP model.

### Historical Q-DESN 144-Fit Study

`scripts/build_qdesn_simulation_tables.R` is intentionally locked to
`QDESN_SIMULATION_TABLE_SOURCE_MODE=fit_only_historical`. Its default source is
the external validation worktree
`/data/jaguir26/local/src/exdqlm__wt__qdesn_0p4p0_integration`.

The official baseline note in that worktree records a 144-fit dynamic grid:

- Scenario: `dlm_constV_p90_m0amp_highnoise_steepertrend_v1`.
- Families: `gausmix`, `laplace`, `normal`.
- Taus: `0.05`, `0.25`, `0.50`.
- Effective fit sizes: `500`, `5000`.
- Inference engines: `vb`, `mcmc`.
- Likelihoods/priors: AL/exAL, ridge/RHS variants.
- Q-DESN washout: `300`.
- Outputs: RMSE against the known target path, pinball loss, runtime.

This is useful for reproducibility conventions and baseline comparisons. It
should not be treated as the main joint-QVP validation because each fit targets
one quantile level at a time and the study does not test simultaneous
multi-quantile coherence.

### Current Joint-QVP Prototype Suite

The current joint-QVP work already has the right foundation:

- Core implementation and diagnostics in `application/R/joint_qvp_qdesn.R`.
- Synthetic time-series generator with exact true conditional quantiles.
- Default scenario registry with six cases:
  `ts_student_t_lscale`, `ts_gaussian_homoskedastic`,
  `ts_student_t_heteroskedastic`, `ts_asymmetric_laplace_tail`,
  `ts_seasonal_low_ar`, and `ts_persistent_heavy_tail`.
- VB and VB-initialized MCMC fit validation.
- Fit overlays, ELBO traces, parameter traces, error/hit-rate figures,
  crossing diagnostics, truth-distance summaries, artifact manifests, and
  provenance.
- Repeated-seed threshold calibration and selected deep-MCMC references.
- A larger retained `T=500` asymmetric-Laplace example with simulated length
  `1000`, washout `500`, retained length `500`, and tau grid
  `{0.10, 0.50, 0.90}`.

The T500 washout review is an especially useful prototype:

- VB adaptive runtime: about `28.7` seconds for `346` iterations.
- Short pooled MCMC runtime: about `21.9` seconds for two short chains.
- VB hit-rate errors: about `-0.002`, `-0.002`, `0.004` at taus
  `0.10`, `0.50`, `0.90`.
- Central true band coverage for `0.10` to `0.90`: `0.826`.
- Central VB and MCMC fitted band coverage: both `0.806`.

This proves feasibility, but it is still a prototype fit-validation example,
not the final article-grade validation campaign.

### Existing Scoring Infrastructure

The application already includes the scoring pieces a multi-quantile forecast
study needs:

- `application/R/score_forecasts.R` implements pinball/check loss, interval
  score, quantile-grid CRPS approximation, and summaries.
- `application/R/synthesize_quantiles.R` implements monotone quantile synthesis
  by isotonic rearrangement and crossing diagnostics.
- `application/R/validation_interface_contract.R` implements the article-side
  provenance and forecast-window guard philosophy.
- The TT500 final table builder already reports lead-level rolling-origin
  summaries and writes manifests.

The new study should extend these pieces rather than create a separate
validation stack.

## Best-Practice Principles

The validation study should follow these principles.

### Separate Fit Recovery From Forecast Evaluation

Synthetic studies with known truth should report both:

- Fit recovery: how close the fitted quantile functions are to the true
  conditional quantiles on the training/post-washout window.
- Forecast evaluation: how well the model predicts held-out observations and
  held-out true conditional quantiles under a predeclared forecast protocol.

These are different questions. A model can recover a training path but forecast
poorly, or score well by pinball loss while showing biased oracle-quantile
recovery.

### Use Proper Scores For Quantile Forecasts

For individual quantile levels, pinball/check loss should remain the primary
proper quantile score. For quantile grids, interval score and weighted interval
score are the natural summary scores. A quantile-grid CRPS approximation is
also useful when the grid is dense enough.

Recommended metrics:

- Pinball loss by tau and horizon.
- Interval score for central intervals such as 50%, 80%, and 90%.
- Weighted interval score over the interval set.
- Quantile-grid CRPS approximation for compact full-grid comparison.
- Empirical coverage and calibration error for each tau and interval.
- Interval width/sharpness reported separately from coverage.

### Use Calibration And Sharpness Together

Coverage alone is not enough. Very wide intervals can cover well but be
uninformative. The study should always pair:

- Coverage/calibration: empirical hit rates and interval coverage.
- Sharpness: interval width, band width, or posterior quantile-band width.
- Proper scores: pinball, interval score, WIS, or CRPS approximation.

### Use Rolling-Origin Forecast Tests

For time-series forecasts, use rolling-origin out-of-sample evaluation rather
than a single fixed test point. The current article protocol already uses leads
`1:30`, stride `30`, and no refit for TT500. The joint-QVP study should reuse
that style, with optional smaller smoke protocols for development.

### Predeclare The Study Grid

Do not tune thresholds or model settings on the same seeds used for final
claims. Use separate tiers:

- Development/smoke seeds for implementation debugging.
- Calibration seeds for threshold selection.
- Article seeds for final summaries.
- Deep-reference seeds for longer MCMC checks.

### Preserve Reproducibility At The Artifact Level

Every runner should write:

- A scenario registry/config snapshot.
- Source-code provenance: repo path, branch, commit, dirty status if any, R
  version, package versions.
- RNG seeds and seed roles.
- Fit controls and forecast controls.
- Artifact manifest with SHA-256 hashes.
- Summary CSVs and compact path tables sufficient to regenerate figures.
- Test/gate assessment table with pass/review/fail statuses.

## Proposed Synthetic Validation Set

### Quantile Grid

Use this grid for the main study:

```text
0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95
```

This grid supports lower-tail, median, upper-tail, and interval validation:

- 50% interval: `0.25` to `0.75`.
- 80% interval: `0.10` to `0.90`.
- 90% interval: `0.05` to `0.95`.

Keep a smaller smoke grid, `{0.10, 0.50, 0.90}`, for fast development and
debugging.

### Size Tiers

Use three tiers.

| Tier | Purpose | Simulated length | Washout | Train | Test | Seeds |
|---|---:|---:|---:|---:|---:|---:|
| Smoke | implementation and tests | 300 | 100 | 120 | 80 | 1-3 |
| Calibration | thresholds and failure modes | 1200 | 300 | 500 | 400 | 10 |
| Article | final evidence | 2500 | 500 or 1000 | 1000 | 500 | 20-30 |

For DESN-specific runs where reservoir washout should be more conservative,
use the user's current convention: simulate `1000`, discard `500`, and retain
`500` for the medium example; for article-scale runs, simulate enough history
to retain `1000` training observations plus `500` forecast observations after
washout.

### DGP Panel

The panel should include both bridge scenarios and stress scenarios.

| ID | Scenario | Distribution | Dynamics | Why It Matters |
|---|---|---|---|---|
| B1 | Normal bridge | Gaussian | local trend plus seasonality | Connects directly to article `normal` family. |
| B2 | Laplace bridge | Laplace or AL with median centering | local trend plus seasonality | Connects to article `laplace` family and AL likelihood. |
| B3 | Gaussian-mixture bridge | two-component Gaussian mixture | local trend plus seasonality | Connects to article `gausmix` misspecification. |
| S1 | Student-t location-scale | Student-t, df 4-6 | AR/seasonal location and time-varying scale | Heavy-tail robustness with analytic quantiles. |
| S2 | Asymmetric-Laplace tail | AL with skew tau about 0.30 | AR/seasonal location and heteroskedastic scale | Checks the AL target and extreme quantile behavior. |
| S3 | Persistent heavy tail | Student-t, df about 3.5 | high AR coefficient and wide tau grid | Stress test for persistence and tail recovery. |
| S4 | Heteroskedastic seasonal | Gaussian or Student-t | stochastic/ARCH-like or deterministic scale | Tests dynamic interval width and calibration. |
| S5 | Regime shift | Gaussian or Student-t | intercept/scale regime switch in test block | Forecast robustness under nonstationary dynamics. |
| S6 | Nonlinear reservoir case | mixture or Student-t | nonlinear lag/seasonal terms | Tests whether DESN features add value beyond linear dynamics. |

The current six joint-QVP scenarios already cover S1, S2, S3, and a simple
Gaussian/seasonal reference. The main additions should be B1-B3 bridge cases
and a formal forecast split.

### True Quantiles

Each DGP must export true conditional quantiles for every retained time point
and tau. Prefer analytic true quantiles:

- Gaussian: `mu_t + sigma_t qnorm(tau)`.
- Laplace: `mu_t + sigma_t qlaplace(tau)` under a declared scale convention.
- Student-t: `mu_t + sigma_t qt(tau, df) / sd_scale`.
- Asymmetric Laplace: `mu_t + sigma_t qal(tau, p) / sd_scale`.
- Gaussian mixture: numerical root inversion of the mixture CDF with a stable
  bracket and fixed tolerance.

For multi-step forecasts with recursive dynamics, use either analytic
one-step truth or a predeclared Monte Carlo oracle with enough simulations and
fixed seeds. Record oracle Monte Carlo error if the truth is simulated.

## Fit Protocol

For each scenario, seed, and method:

1. Generate the full series from the DGP.
2. Remove washout.
3. Split the retained series into train and test.
4. Fit joint-QVP VB on the train block first.
5. Check hard implementation gates before any statistical interpretation.
6. Initialize MCMC from selected VB fits.
7. Export compact train-path summaries, posterior/variational quantile bands,
   crossing diagnostics, and runtime.

Main methods:

- Joint-QVP AL-VB/RHS as the primary fast engine.
- Joint-QVP exAL-VB when the derivation and implementation are promoted.
- VB-initialized MCMC on selected smoke/calibration/article cells.
- Legacy single-quantile Q-DESN baselines for selected bridge scenarios.
- DQLM/exDQLM baselines where the interface already supports the same DGP and
  forecast split.

Do not require full MCMC for every final cell at first. Use MCMC as a reference
and diagnostic layer, with selection rules declared before running the deep
checks.

## Forecast Protocol

The forecast study should reuse the article's rolling-origin style.

Recommended default:

- Max lead: `30`.
- Origin stride: `30`.
- Refit per origin: no for the initial study.
- State update: use the same declared recursive/update contract for all
  methods.
- Forecast scoring block: the retained test block only.

For the article-scale synthetic study, store lead-level predictions, not just
aggregates. This allows later tables by:

- DGP.
- Tau.
- Horizon/lead.
- Method.
- Seed.
- Inference engine.

If no-refit forecasting is too limiting for some DGPs, add a secondary
rolling-refit sensitivity study, but keep it separate from the primary table.

## Metrics

### Fit Metrics

Report by scenario, seed, method, and tau:

- RMSE and MAE to true conditional quantile.
- Bias to true conditional quantile.
- Maximum absolute error to truth.
- Pinball loss on training observations.
- Empirical hit rate and `hit_rate - tau`.
- Adjacent quantile crossing count and maximum crossing magnitude.
- Posterior/variational band width for fitted quantiles.
- VB convergence status, iteration count, objective monotonicity, and runtime.
- MCMC finite-draw checks, chain-to-pooled distance, and runtime.
- VB-to-MCMC distance on selected reference cells.

### Forecast Metrics

Report by scenario, seed, method, tau, and horizon:

- Forecast quantile MAE/RMSE to true held-out conditional quantile.
- Forecast pinball loss on held-out observations.
- Empirical tau coverage and calibration error.
- Interval coverage for 50%, 80%, and 90% central intervals.
- Interval width/sharpness.
- Interval score.
- WIS over the interval grid.
- Quantile-grid CRPS approximation.
- Crossing diagnostics before and after monotone synthesis.
- Runtime for fit and forecast separately.

### Aggregate Summaries

Use paired summaries across seeds:

- Median and IQR by scenario/method/tau.
- Mean with Monte Carlo standard error where appropriate.
- Paired loss difference versus baseline, with uncertainty.
- Relative score improvement versus baseline.
- Runtime/accuracy Pareto table.

Avoid making claims from a single seed except for smoke and illustrative
figures.

## Acceptance Gates

### Hard Fail

A run should fail hard if any of these occur:

- Missing required columns or malformed scenario registry.
- Nonfinite observations, true quantiles, fitted quantiles, or scores.
- Nonpositive scale parameters in the DGP or model.
- Missing provenance or artifact hashes.
- Forecast windows overlap training windows.
- Forecast origin does not match the declared split.
- VB/MCMC output has nonfinite summaries.
- Warm-started MCMC does not report a provided initialization.
- Quantile crossing remains after the declared monotone synthesis step for
  article-facing predictions.

### Review

A run should be review, not fail, when:

- VB reaches the maximum iteration cap but numerical summaries are finite.
- VB/MCMC distance is above the calibrated threshold on a short reference.
- MCMC chain diagnostics are weak but finite and clearly labeled.
- Coverage is outside binomial tolerance for a single seed.
- A stress DGP intentionally violates modeling assumptions.

### Statistical Pass

A result should be eligible for article interpretation only when:

- Hard gates pass.
- Repeated-seed aggregate coverage is within predeclared tolerance.
- Proper scores are competitive with declared baselines.
- Quantile crossing diagnostics are zero after the final prediction contract.
- VB is validated on the main grid and MCMC agrees on selected reference cells
  at the calibrated tolerance.

## Figures And Tables

### Required Figures

For each representative DGP:

- Data with true quantile bands and fitted VB/MCMC bands.
- Coverage-band comparison over time: true, VB, and MCMC.
- Hit-rate calibration by tau.
- Fit error by tau and time.
- Forecast pinball/WIS heatmap by tau and horizon.
- Runtime versus score scatter.
- ELBO/objective trace for VB.
- MCMC parameter traces for selected reference cases.

### Required Tables

- DGP registry table with parameters and truth-oracle type.
- Fit recovery summary by DGP and method.
- Forecast scoring summary by DGP, tau, and method.
- Coverage/sharpness table for central intervals.
- Runtime table split into fit and forecast.
- Gate assessment table with pass/review/fail counts.
- Artifact manifest and provenance table.

## Implementation Phases

### Phase 0: Freeze The Current Prototype Evidence

- Record the current T500 asymmetric-Laplace washout run as a prototype, not
  final evidence.
- Keep its figures and summaries available as a reference bundle.
- Confirm artifact hashes and tests for the current suite.
- Do not modify TT500, GloFAS, or PriceFM lanes.

### Phase 1: Create A Formal DGP Registry

- Add a CSV/YAML registry for the validation DGP panel.
- Include bridge scenarios B1-B3 and stress scenarios S1-S6.
- Add exact true-quantile functions for every DGP.
- Add tests for monotone true quantiles, finite data, reproducible seeds, and
  positive scales.
- Export compact observed/design/truth tables for each scenario.

### Phase 2: Promote Fit Validation

- Generalize the current fit runner to consume the registry.
- Run smoke grid with `{0.10, 0.50, 0.90}`.
- Run calibration grid with full seven-quantile grid.
- Keep VB as the primary engine.
- Add selected VB-initialized MCMC references.
- Export figures and compact summaries.
- Add tests for artifact schema, hashes, crossing, convergence, and truth
  distances.

### Phase 3: Add Rolling-Origin Forecast Validation

- Add a forecast runner using the same split and lead contract as TT500 where
  possible.
- Export lead-level predictions and scores.
- Reuse `score_forecasts.R` for pinball, interval score, WIS-compatible
  interval summaries, and quantile-grid CRPS.
- Add forecast-window guards similar to `validation_interface_contract.R`.
- Test no train/test leakage, correct lead indexing, and finite scores.

### Phase 4: Calibrate Statistical Thresholds

- Run repeated seeds on the calibration tier.
- Set thresholds from repeated-seed distributions, not from a single example.
- Calibrate hit-rate tolerance using binomial standard errors with a practical
  floor for extremes.
- Calibrate VB/MCMC distance thresholds only on selected longer-chain
  references.
- Record every threshold with a rationale in a `validation_thresholds.csv`.

### Phase 5: Article-Ready Study

- Run article-tier seeds and final DGP grid.
- Generate manuscript tables and figures from frozen outputs.
- Write an article-side config with exact paths and hashes.
- Add a table builder and tests analogous to the TT500 final handoff.
- Include bridge comparisons to the historical Q-DESN study only where the
  target is genuinely comparable.

## Testing Checklist

### DGP Tests

- Scenario registry has unique IDs.
- All required DGP fields are present.
- Re-running a scenario with the same seed reproduces observations and truth.
- True quantiles are finite and nondecreasing in tau.
- Scale paths are strictly positive.
- Washout/train/test lengths match the declared split.
- Mixture quantile inversion is monotone and accurate to tolerance.

### Fit Tests

- VB fit returns finite summaries for every smoke scenario.
- Objective diagnostics are finite and monotonic under the declared convention.
- Fitted quantile crossings are detected before synthesis and zero after final
  synthesis.
- Fit-truth RMSE/MAE tables have one row per method/scenario/tau.
- Runtime summaries are finite and positive.
- MCMC uses VB initialization on reference cells.
- MCMC draw summaries are finite and chain labels are complete.

### Forecast Tests

- Forecast predictions never use held-out observations for fitting.
- Forecast origin and lead indices match the declared split.
- Lead-level prediction table has all required columns.
- Pinball, interval score, WIS components, CRPS approximation, and coverage are
  finite.
- Forecast summaries aggregate exactly from lead-level rows.
- Monotone synthesis is applied consistently before interval scoring.

### Reproducibility Tests

- Every runner writes provenance and artifact manifest files.
- Repeated same-config smoke runs produce identical hashes for deterministic
  artifacts.
- Table builders refuse stale validation paths and missing hashes.
- Figure manifests point to existing files.
- Generated article tables are reproducible from the frozen config.

## Decision Points

Recommended defaults:

- Main tau grid: `{0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95}`.
- Smoke tau grid: `{0.10, 0.50, 0.90}`.
- First article-scale retained data: train `1000`, test `500`.
- Forecast protocol: leads `1:30`, stride `30`, no refit.
- Primary inference: VB.
- MCMC: selected VB-initialized references, then expand only if diagnostics
  require it.
- Old Q-DESN data: use as bridge/baseline context, not as primary joint-QVP
  evidence.

Open choices before implementation:

- Whether the main bridge Laplace DGP should use symmetric Laplace or AL with
  median centering.
- Whether the Gaussian-mixture bridge should match the article mixture exactly
  or use a milder mixture for stable multi-quantile extremes.
- Number of article seeds: `20` is probably enough for a first manuscript
  table; `30` is safer for extremes.
- Whether to include a rolling-refit sensitivity after the no-refit primary
  forecast protocol.
- Which legacy single-quantile Q-DESN baselines are worth rerunning under the
  new registry.

## References

Local repo references:

- `main.tex`, section `Simulation Validation Study`.
- `scripts/build_qdesn_simulation_tables.R`.
- `application/R/joint_qvp_qdesn.R`.
- `application/R/score_forecasts.R`.
- `application/R/synthesize_quantiles.R`.
- `application/R/validation_interface_contract.R`.
- `docs/implementation_notes/joint_qvp_validation_threshold_policy_20260701.md`.
- `docs/implementation_notes/shared_validation_tt500_final_article_handoff_20260621.md`.
- External validation baseline:
  `/data/jaguir26/local/src/exdqlm__wt__qdesn_0p4p0_integration/docs/BASELINE__qdesn_dynamic_p90_steepertrend_n300m50_20260428.md`.

External methodological references:

- Gneiting and Raftery (2007), "Strictly Proper Scoring Rules, Prediction, and
  Estimation": https://www.tandfonline.com/doi/abs/10.1198/016214506000001437
- Bracher, Ray, Gneiting, and Reich (2021), "Evaluating epidemic forecasts in
  an interval format": https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1008618
- Chernozhukov, Fernandez-Val, and Galichon (2010), "Quantile and Probability
  Curves without Crossing": https://onlinelibrary.wiley.com/doi/abs/10.3982/ECTA7880
- Tashman (2000), "Out-of-sample tests of forecasting accuracy: an analysis
  and review": https://www.sciencedirect.com/science/article/abs/pii/S0169207000000650
- Diebold and Mariano (1995), "Comparing Predictive Accuracy":
  https://www.jstor.org/stable/1392185
- Hyndman and Athanasopoulos, time-series cross-validation/rolling origin:
  https://otexts.com/fpp3/tscv.html
