# Joint QDESN Simulation Study Preparation

Date: 2026-07-06

Scope: preparation and discussion plan only. This note does not launch a new
validation run and does not promote the current Phase 4k/4o joint-QVP artifacts
as manuscript evidence.

## 1. Current Decision

The current article is being reset around the validated single-quantile Q-DESN
simulation study. The previous joint multi-quantile validation section has been
removed from the main manuscript because it mixed model-specification search,
crossing diagnostics, runtime gates, and article assets. That material remains
valuable as implementation history, but it is not the clean simulation study we
want for a publishable article.

The next joint simulation study should be designed before any new large run is
started.

## 2. Naming Convention

Use the following manuscript-facing labels:

- `QDESN ridge` and `QDESN RHS` for AL working-likelihood fits.
- `exQDESN ridge` and `exQDESN RHS` for exAL working-likelihood fits.

The broader method class can still be described as Q--DESN when discussing the
Bayesian quantile readout for fixed DESN features. The compact row labels avoid
the awkward and redundant likelihood-suffix form.

For a future joint model, use the same convention:

- `JOINT QDESN RHS` for AL joint quantile-vector readouts with the RHS prior.
- `JOINT exQDESN RHS` for exAL joint quantile-vector readouts with the RHS
  prior.
- `QDESN RHS` and `exQDESN RHS` for independent single-quantile comparators.

## 3. What Must Be Decided Before Implementation

### 3.1 Scientific role

The joint study should answer one primary question:

Can a joint QDESN/exQDESN readout recover and forecast a grid of conditional
quantiles while preserving a transparent noncrossing contract?

It should not be framed as a search over many tau0 values, feature screens, or
runtime rescue paths. Those are calibration diagnostics and should live outside
the main evidence unless they are the scientific object.

### 3.2 Model scope

Before launching, confirm which models are included:

| Candidate | Include in main study? | Reason |
|---|---:|---|
| JOINT QDESN RHS VB | yes | Fast primary engine under AL. |
| JOINT exQDESN RHS VB--LD | yes | exAL counterpart needed for the validation study. |
| JOINT QDESN RHS MCMC | yes, after VB is finalized | Used after VB delivers stable evidence, because MCMC is more expensive. |
| JOINT exQDESN RHS MCMC | yes, after VB is finalized | Highest-fidelity exAL reference, postponed until the VB design is frozen. |
| independent QDESN/exQDESN RHS plus monotone synthesis | yes | Comparator that isolates the gain from fitting the quantile vector jointly. |

The readiness audit must confirm AL/exAL, VB/MCMC, RHS prior behavior, K=1
reduction, and raw/contract monotone outputs before this becomes article
evidence.

### 3.3 DGP families

The study should be smaller and cleaner than the Phase 4 campaign. Recommended
families:

| Class | Candidate DGP | Purpose |
|---|---|---|
| Bridge | Gaussian location-scale | Connects to the article's Gaussian TT500 family. |
| Bridge | Laplace location-scale | Connects to AL behavior and the Laplace TT500 family. |
| Bridge | Gaussian mixture | Connects to skew/heavy mixture behavior. |
| Stress | Student-t location-scale | Heavy-tail robustness. |
| Stress | Asymmetric-Laplace tail | Tail asymmetry and AL target behavior. |
| Stress | Regime shift or heteroskedastic seasonal | Dynamic adaptation under nonstationarity. |

Because this second simulation study is not benchmarking against QDLM or
exDQLM baselines, it does not need to restrict itself to DQLM-compatible linear
dynamics. The DGP set can include nonlinear, heavy-tailed, asymmetric, and
regime-changing cases, provided each case has a reproducible oracle quantile
construction and a clear reason for inclusion.

### 3.4 Series length and indexing

Use the user's proposed long-series design unless we find a computational
blocker:

- Simulate full length 12000.
- Use observations 1:2000 as DGP initialization/warmup.
- Store observations 2001:12000 as the effective 10000-point series.
- Use DESN washout length 500.
- Fit on 500 retained observations after washout.
- Validate on the next 1000 retained observations.
- Preserve original time index, effective-series index, retained index, role,
  forecast origin, and forecast lead.

This design keeps the DGP warmup separate from the DESN washout and makes the
fit/forecast windows comparable to the TT500 study.

### 3.5 Forecast protocol

Use a no-refit multi-step protocol:

- forecast origins spaced every 30 observations;
- score leads 1 through 30;
- do not refit within the 30-step lead block;
- fit using only observations available before the forecast origin;
- store raw forecast quantiles and monotone contract forecast quantiles.

This mirrors the TT500 rolling-origin logic and avoids turning the joint study
into a refit-frequency study.

### 3.6 Oracle quantiles

Use this hierarchy:

1. Analytic conditional quantiles when available.
2. Numerical inversion when the conditional CDF is available.
3. Monte Carlo oracle only when needed.

For Monte Carlo oracle quantiles:

- compute once per DGP;
- use fixed seed roles;
- use enough draws for stable tails;
- store oracle quantiles as fixture artifacts;
- hash oracle files;
- never recompute oracle quantiles inside fit or forecast runners.

The article should state whether each DGP has analytic, numerical, or
Monte Carlo oracle quantiles.

## 4. Metrics to Keep

Keep the main metric set compact:

- fit MAE/RMSE to oracle quantiles by tau;
- forecast pinball loss by tau;
- forecast MAE/RMSE to oracle quantiles by tau;
- empirical hit-rate error by tau;
- central interval coverage and width for paired tau levels;
- CRPS using the integrated quantile representation already used in the
  repository;
- raw crossing and monotone-adjustment diagnostics;
- runtime and convergence in a reproducibility table.

Do not report WIS in the main article unless a specific sensitivity-analysis
reason is documented. The main aggregate grid score should be CRPS under the
integrated quantile representation, alongside check loss and the fit/forecast
truth-distance metrics.

## 5. Raw and Contract Quantiles

The monotone-adjustment question is about separating two things that should not
be conflated:

- raw model output: the fitted or forecasted quantiles produced directly by the
  model at each tau;
- contract output: the quantile vector after the declared noncrossing
  rearrangement or synthesis step, which is the output used for scoring and
  article-facing forecast bands.

If raw outputs cross, for example if the fitted 0.10 quantile is below the
fitted 0.05 quantile at the same time point, then the raw model is violating the
quantile ordering. A monotone rearrangement can repair the displayed/scored
quantile vector, but it does not erase the diagnostic information that the raw
model needed repair.

The adjustment rate is the fraction of time points, forecast origins, or
origin-lead-tau pairs where the raw vector had to be changed to satisfy
monotonicity. A small rate with tiny adjustments is usually a review diagnostic.
A large rate, repeated tail crossings, or large changes after rearrangement
suggests that the joint prior, the DESN feature map, the tau coupling, or the
optimization settings need redesign. For this study, raw crossings should be
reported transparently, while hard failure should be reserved for contract
outputs that still cross after the declared monotone step.

## 6. Decisions from User Discussion

The current agreed design is:

1. Include both `JOINT QDESN RHS` and `JOINT exQDESN RHS` in the validation
   study.
2. Include independent single-quantile `QDESN RHS` and `exQDESN RHS`
   comparators, with monotone synthesis, so the study can measure the benefit
   of the joint fit.
3. Do not restrict the second simulation study to DQLM-compatible linear
   dynamics, because QDLM/exDQLM are not the baselines in this stage.
4. Run MCMC for the study, but only after the VB implementation is complete,
   stable, and delivering the desired behavior.
5. Use CRPS under the integrated quantile representation, check loss, and the
   previously used fit/forecast diagnostics. Do not use WIS as the main
   aggregate score.
6. Treat raw monotone adjustments as diagnostics to be understood and reported;
   use the monotone contract output for scoring, and reserve failure for
   implementation defects or contract quantiles that still cross.

## 7. Readiness Gate Before Launch

Before any new launch, produce a readiness audit with pass/review/fail rows for:

- joint QDESN RHS VB;
- joint exQDESN RHS VB--LD;
- joint QDESN RHS MCMC;
- joint exQDESN RHS MCMC;
- K=1 reduction;
- oracle quantile fixture generation;
- train/test leakage prevention;
- raw and contract quantile outputs;
- monotone-adjustment diagnostics;
- deterministic artifact manifests.

Only after that audit should the 12000-length simulation fixtures and validation
runners be implemented.

## 8. Recommended Next Action

Freeze the compact article design around the decisions above. Then implement
the readiness audit for VB first. Once VB is stable for JOINT QDESN RHS, JOINT
exQDESN RHS, and the independent QDESN/exQDESN comparators, build the
long-series fixtures and validation runners. MCMC should be introduced only
after that VB stage is complete.

## 9. VB-First Readiness Audit Implementation

The VB-first readiness layer is implemented in:

- `application/R/joint_qdesn_simulation_readiness.R`;
- `application/scripts/97_run_joint_qdesn_simulation_vb_readiness_audit.R`;
- `application/tests/test_joint_qdesn_simulation_vb_readiness_audit.R`;
- `docs/implementation_notes/joint_qdesn_simulation_vb_readiness_audit_20260706.md`.

The default artifact directory is:

`application/cache/joint_qdesn_simulation_vb_readiness_audit_20260706`

The audit deliberately uses a small deterministic toy fixture and does not
launch the 12000-length fixture generation. Its role is to verify that the VB
paths, independent K=1 comparators, raw/contract quantile policy, oracle
policy, long-series design geometry, provenance, and artifact manifest are in
place before the next implementation stage.

## 10. Long-Series Fixture Layer

The long-series DGP fixture layer is implemented in:

- `application/config/joint_qdesn_simulation_dgp_registry_20260706.csv`;
- `application/R/joint_qdesn_simulation_fixtures.R`;
- `application/scripts/98_generate_joint_qdesn_simulation_dgp_fixtures.R`;
- `application/tests/test_joint_qdesn_simulation_dgp_fixtures.R`;
- `docs/implementation_notes/joint_qdesn_simulation_dgp_fixtures_20260706.md`.

The default artifact directory is:

`application/cache/joint_qdesn_simulation_dgp_fixtures_20260706`

This stage follows the TT500 validation structure more closely by using the
last 2000 effective observations of the simulated series: 500 DESN washout
rows, 500 fit rows, and 1000 held-out validation rows. It writes oracle
quantiles, split metadata, forecast-origin plans, provenance, and SHA-256
manifests, but it does not launch VB or MCMC fitting.
