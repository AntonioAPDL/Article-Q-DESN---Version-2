# JOINT Persistent-Tail and Regime-Shift Recalibration v2

## Authority and Scope

This version supersedes the unlaunched v1 packet. It changes no article authority and uses no protected outcomes for selection. It targets only `persistent_heavy_tail` and `regime_shift`, with one case-specific DESN/RHS specification ultimately shared across independent/joint AL/exAL comparisons within a scenario.

The current evidence shows good fit-window recovery but poor recursive forecast generalization. The earlier 768-candidate expansion retained the original backbones for both scenarios. MCMC score functionals pass stability checks, so sampler tuning is not the primary intervention.

## Corrections to v1

1. Exact authority parity is run first and must reproduce the historical internal calibration score.
2. The broad architecture screen uses one canonical reservoir seed, avoiding architecture/seed confounding.
3. The best 50 include mandatory parity, 34 numerical leaders, and 15 diversity representatives.
4. Each finalist is evaluated across three reservoir seeds; non-parity structures use the median-performing seed, while parity retains its exact historical seed.
5. RHS uses a coarse `tau0` grid followed by bounded half-decade refinement.
6. The median shortlist contains 12 distinct architectures, not repeated `tau0` values from one architecture.
7. Four median leaders plus parity receive independent AL `0.05/0.95` sentinels.
8. Tail recursion uses the fitted median as the central future-response action.
9. The parity comparator retains the exact authoritative architecture, reservoir seed, and `tau0` through every transfer gate; retuning the same architecture cannot silently redefine parity.
10. The pipeline stops before seven-level, joint, exAL, MCMC, article, or Overleaf work.

## Frozen Selection Geometry

- Three observational selector realizations per scenario.
- 500 washout rows, 350 internal training rows, 150 internal calibration rows.
- Teacher forcing between 30-step origins; recursive central-action forecasts within each origin.
- Readout: intercept plus all reservoir states, no raw inputs.
- Exactly zero protected rows persisted in selector fixtures.
- Ridge selection uses realized finite-grid aCRPS; DGP truth and oracle errors remain diagnostics.
- Median/tail transfer uses realized check loss.

## Candidate Allocation

Each scenario receives exactly 1,024 candidates:

| Stratum | Count | Purpose |
|---|---:|---|
| Exact authority | 1 | Reproducible parity |
| Local | 383 | Refine the existing winner neighborhood |
| Global | 512 | Explore depth, width, lag, scaling, sparsity, and layer schedules broadly |
| Mechanism-specific | 128 | Long-memory heavy-tail or mixed-memory regime-shift emphasis |

The space includes depths 1-6, state budgets through 600, lags through 240, flat/tapered/expanding widths, layer-specific `alpha/rho`, and screened input scaling/sparsity.

## Stages and Gates

1. **Parity:** 6 RHS fits. Relative calibration-score discrepancy must be at most `1e-8`.
2. **Ridge:** 6,144 fits. Advance mandatory parity, 34 numerical leaders, and 15 diverse candidates per scenario.
3. **Seed robustness:** 600 additional ridge fits. Aggregate three DGP replicates by three reservoir seeds.
4. **Coarse RHS:** 2,400 fits over `tau0 = 10,...,1e-6`.
5. **Adaptive RHS:** at most 144 fits around 12 distinct architectures per scenario.
6. **Median AL:** 72 fits. Finite max-iteration results are review-level rather than automatically rejected.
7. **Tail AL:** 48-60 fits at `0.05/0.95`, initialized through the corresponding median path.
8. **Review:** compare the normalized `0.25/0.50/0.25` lower/median/upper check-loss proxy with parity. Any finite lower matched mean is eligible for later seven-level confirmation, but overlapping evidence remains descriptive.

## Promotion Boundary

No result from this campaign directly replaces the article authority. A later, separately frozen contract must fit all seven independent AL quantiles, joint AL, independent/joint exAL VB, and then MCMC. Every exAL MCMC fit must use exact M0. Poor scalar mixing remains review-level unless predictive functionals or fit/forecast behavior are pathological.

## Reproducibility Checklist

- [x] v1 remains preserved and unlaunched.
- [x] v2 contract, axes, scenario registry, and source branch are versioned.
- [x] Exact parity is mandatory and failure-closed.
- [x] Architecture and reservoir-seed effects are separated.
- [x] Scenario-specific search strata are explicit.
- [x] Protected data are absent from selection fixtures.
- [x] Every stage has a worker plan, health state, artifacts, and finalizer.
- [x] Fifteen one-thread worker slots use distinct physical CPU identifiers.
- [x] Automatic execution stops after the three-quantile AL review.
- [x] Focused v2 and inherited JOINT regression tests pass under the release-candidate source.
- [x] A disposable prepared packet verified 2,048 candidates, 6,144 ridge jobs, six fixtures, 11 manifest entries, and the 9,426-job maximum.
- [x] Six exact-parity sentinels reproduced both authoritative internal calibration scores to relative error below `1.3e-15`.
- [x] Real median and lower-tail AL workers completed from the staged compact-initializer path.
- [ ] Capacity is rechecked immediately before launch.
- [ ] Completed results receive a frozen scientific closeout before any broader confirmation.
