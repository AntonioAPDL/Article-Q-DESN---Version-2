# Q-DESN VB Modes Gap Analysis and Implementation TODO

Date: 2026-05-28

Status: planning and verification document. This note does not implement new
algorithms. It records what is implemented now, what remains missing, what is
worth implementing, and the documentation, derivation, testing, and
reproducibility gates required before each additional mode is allowed into the
Q-DESN AL/exAL workflow.

## Scope

This document covers the univariate Q-DESN readout model after fixed DESN
feature construction. The target likelihoods are:

- AL: the asymmetric Laplace working likelihood reduction used for quantile
  regression;
- exAL: the quantile-fixed generalized asymmetric Laplace working likelihood
  used in this article and package.

The beta-prior families in scope are:

- ridge;
- RHS/RHS_NS shrinkage.

The document is package-first. Article GloFAS latent-path adapters and future
multivariate Q-DESN extensions are downstream consumers and should not be used
as the first place to introduce new approximate algorithms.

## Current Repos

Article repo:

- path: `/data/jaguir26/local/src/Article-Q-DESN`
- branch: `application-ensemble-likelihood-redesign`
- current local HEAD when this note was created:
  `5438445ae2f7ee02e0bd6f749a9b6cc6607d57e9`

Package/shared validation repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- current local HEAD when this note was created:
  `9ff6272cbaa67ecbd9be4701934185833037cee3`

Do not edit the Overleaf/main worktree for this work unless explicitly
instructed:

`/data/jaguir26/local/src/Article-Q-DESN__wt__main_overleaf_20260514`.

## Existing Source-of-Truth Notes

Use these tracked notes before implementing any new mode:

- `docs/implementation_notes/qdesn_vb_batching_derivations_20260527.md`
- `docs/implementation_notes/qdesn_vb_batching_roadmap_20260527.md`
- `docs/implementation_notes/qdesn_vb_method_availability_20260528.md`
- `docs/implementation_notes/qdesn_vb_comparison_plan_20260528.md`
- `docs/implementation_notes/qdesn_vb_comparison_results_20260528.md`
- `docs/implementation_notes/qdesn_vb_source_tt500_median_comparison_20260528.md`
- `docs/implementation_notes/qdesn_vb_source_last1000_wash500_d1n300_comparison_20260528.md`

The ignored local report `QDESN_Batched_VB_Implementation_Report.md` remains
background only. It is not authoritative for the repo layout or implementation
contracts.

## Verification Pass on 2026-05-28

This note was re-audited against the package and article worktrees after the
initial commit.

Verified article state:

- path: `/data/jaguir26/local/src/Article-Q-DESN`
- branch: `application-ensemble-likelihood-redesign`
- audited HEAD before this update: `12d5703a050f4232dbfe2135af9719607686b00e`

Verified package state:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- audited HEAD after the hybrid AL and source-harness stage:
  `c51e9da4508f6fb89a73f8b78e08f9d80604e11a`

The audit checked the current package surfaces for:

- likelihood routing and Q-DESN VB API;
- exact and stochastic chunking controls;
- AL-only stochastic fail-early behavior;
- RHS/RHS_NS prior and intercept policy;
- online VB-LD helper modules;
- canonical Q-DESN VB warm-start controls plus warmup and MCMC warm-start
  controls;
- existing exact, stochastic, likelihood-family, and RHS tests;
- current article/source comparison notes and economical gates.

No package code was edited by this documentation pass.

## Posterior-as-Prior Update on 2026-05-28

After the independent rolling-window stage, the package added the first
posterior-as-prior Q-DESN mode:

- package commit `fef2558`: beta prior natural-parameter hook;
- package commit `1259199`: Q-DESN AL ridge posterior-as-prior rolling mode and
  economical gate script;
- package commit `3df0e15`: expanding-origin posterior-as-prior test coverage.

The article documentation was updated in
`qdesn_vb_posterior_as_prior_stage_20260528.md`. No article application code or
config was changed by this stage.

## Diagonal Covariance Update on 2026-05-28

After posterior-as-prior, the package added the first beta covariance
approximation:

- package commit `03aab6c`: AL + ridge diagonal beta covariance approximation
  for package static/readout and univariate Q-DESN routing.

The article documentation was updated in
`qdesn_vb_diagonal_covariance_stage_20260528.md`. No article application code
or config was changed by this stage.

## Fixed Subset Update on 2026-05-28

After diagonal covariance, the package added the first explicit subset-data
target mode:

- package commit `fbf04f1`: fixed deterministic subset VB for AL + ridge,
  with unchunked and exact chunked subset-target fits.

The article documentation was updated in
`qdesn_vb_fixed_subset_stage_20260528.md`. No article application code or
config was changed by this stage.

## Online VB-LD Audit Update on 2026-05-28

After fixed subset, the package added readiness tests around the existing
static/readout online exAL VB-LD helpers:

- package commit `36428a8`: online VB-LD serialization, one-row streaming,
  reproducibility, order-sensitivity, disabled pass-through, and enabled-AL
  fail-early tests.

This is not a new Q-DESN online wrapper. The article documentation was updated
in `qdesn_vb_online_integration_audit_20260528.md`.

## Stratified Subset Update on 2026-05-28

After the online audit, the package added the first stratified subset-data
target mode:

- package commit `7f310ed`: time-block stratified subset VB for AL + ridge,
  with proportional allocation, explicit seed, unchunked subset-target fits, and
  exact chunked subset-target equivalence.

The article documentation was updated in
`qdesn_vb_stratified_subset_stage_20260528.md`. No article application code or
config was changed by this stage.

## RHS Diagonal Covariance Update on 2026-05-28

After the stratified subset stage, the package extended the diagonal beta
covariance approximation to AL + RHS/RHS_NS priors:

- package commit `28251d8`: RHS/RHS_NS diagonal beta covariance support for
  package static/readout AL and univariate Q-DESN AL routing, with exact
  chunked equivalence and fail-early unsupported modes.

The article documentation was updated in
`qdesn_vb_rhs_diagonal_covariance_stage_20260528.md`. No article application
code or config was changed by this stage.

## Q-DESN Online Wrapper Update on 2026-05-28

After the RHS diagonal covariance stage, the package added the first canonical
Q-DESN online wrapper:

- package commit `b7369b9`: `qdesn_vb_fit_online()` for ordered AL + ridge
  Q-DESN batch fits with posterior-as-prior Gaussian beta handoff, full beta
  covariance, and unchunked or exact chunked per-batch VB.

The article documentation was updated in
`qdesn_vb_online_wrapper_al_ridge_stage_20260528.md`. No article application
code or config was changed by this stage.

## Hybrid exAL and Equal Subset Update on 2026-05-29

After the implemented-mode comparison pass, the package extended two existing
surfaces without changing full-data defaults:

- package commit `4912699`: hybrid exAL now supports ridge, RHS, and RHS_NS
  beta priors for package static/readout and univariate Q-DESN routing. Pure
  stochastic exAL remains forbidden.
- package commit `4912699`: time-block stratified subset VB now supports
  `allocation = "equal"` in addition to `allocation = "proportional"`.

The package branch later advanced to `71cac6c` with unrelated Normal DESN
forecast work. The Q-DESN VB implemented-mode source gate was rerun at that
source-gate HEAD and passed. The package then advanced again to `0f5d4f6` for
a Normal DESN comparison metadata fix; that later commit does not change the
Q-DESN VB mode conclusions. Documentation was added in:

- `qdesn_vb_rhs_hybrid_exal_stage_20260529.md`;
- `qdesn_vb_equal_stratified_subset_stage_20260529.md`;
- `qdesn_vb_implemented_modes_last1000_wash500_d1n300_gate_20260529.md`;
- `qdesn_vb_exal_diagonal_covariance_stop_gate_20260529.md`.

The attempted exAL diagonal covariance stage was initially backed out because
exact chunked diagonal exAL did not match unchunked diagonal exAL after
sigma/gamma LD feedback.

## Extended Mode Completion Update on 2026-05-29

The package subsequently completed the next narrow gates in commit `f0d45ea`:

- response-quantile and design-leverage stratified subset-data VB for AL +
  ridge, with unchunked and exact chunked subset-target gates;
- exAL + ridge diagonal beta covariance, with exact chunked equivalence under a
  practical `1e-6` absolute and relative source gate;
- a polished implemented-mode comparison report summarizer.

The implemented-mode source gate used the last 1000 source rows, washout 500,
D=1, reservoir n=300, and 500 effective fitted rows. It ran 35 methods and
passed 15/15 exact gates. The largest exact-gate absolute difference was
`1.638e-04`, and the largest relative difference was `3.181e-08`.

Important caveat: exAL ridge diagonal covariance is finite and exact-chunked
equivalent, but it performed poorly on the source gate (`pinball_y =
166.227109`, `rmse_mu = 332.79075`). Treat it as a supported covariance
approximation for diagnostics and method coverage, not a recommended predictive
default.

Still gated after this update:

- pure stochastic exAL;
- exAL RHS/RHS_NS diagonal covariance;
- stochastic/hybrid diagonal covariance combinations;
- RHS/RHS_NS or exAL subset targets;
- divide-and-combine VB and variational coresets.

Documentation was added in:

- `qdesn_vb_richer_subset_stage_20260529.md`;
- `qdesn_vb_extended_modes_completion_20260529.md`.

## Implemented Modes

Implemented and tested for package static/readout and Q-DESN paths:

- full-data CAVI/LDVB for AL;
- full-data CAVI/LDVB for exAL;
- exact chunked CAVI/LDVB for AL;
- exact chunked CAVI/LDVB for exAL;
- stochastic mini-batch VB for AL, explicitly approximate;
- Q-DESN AL routing for stochastic mini-batch VB;
- hybrid AL SVI with periodic full refresh for package static/readout and
  univariate Q-DESN AL, explicitly approximate unless every iteration is a full
  refresh;
- independent rolling/expanding-window Q-DESN AL VB refits for ridge priors,
  with unchunked or exact chunked full-window VB per origin;
- posterior-as-prior Q-DESN AL ridge beta handoff over rolling or expanding
  origin sequences, target-changing and not a warm start;
- canonical Q-DESN AL ridge online wrapper over ordered batches, using
  posterior-as-prior beta handoff and target-changing state metadata;
- fixed Gaussian beta prior natural-vector hook for posterior-as-prior;
- diagonal beta covariance approximation for AL + ridge/RHS/RHS_NS, explicitly
  approximate in covariance while preserving the full-data row target when no
  subset mode is used;
- diagonal beta covariance approximation for exAL + ridge, explicitly
  approximate in covariance and supported only for unchunked or exact chunked
  full-data rows;
- fixed deterministic subset CAVI for AL + ridge, target-changing and not a
  full-data posterior approximation;
- time-block stratified subset CAVI for AL + ridge with proportional or equal
  allocation, target-changing and not a full-data posterior approximation;
- response-quantile and design-leverage stratified subset CAVI for AL + ridge,
  target-changing and not a full-data posterior approximation;
- hybrid exAL with periodic full refresh for ridge/RHS/RHS_NS beta priors,
  explicitly approximate unless every iteration is a full refresh;
- static/readout online exAL VB-LD readiness tests for the existing helper
  surface;
- ridge prior for beta;
- RHS/RHS_NS prior support with global shrinkage updates.

Implemented for article GloFAS latent-path AL-VB:

- full-data article-side AL-VB;
- exact chunking for fixed historical rows only.

Not implemented:

- stochastic exAL;
- variance-reduced SVI;
- posterior-as-prior Q-DESN for RHS/RHS_NS, exAL, stochastic, or hybrid modes;
- rolling-window Q-DESN for RHS/RHS_NS, exAL, stochastic, or hybrid modes;
- online Q-DESN for RHS/RHS_NS, exAL, stochastic, hybrid, diagonal covariance,
  or article adapters;
- diagonal beta covariance for exAL RHS/RHS_NS, stochastic, or hybrid modes;
- custom allocation and non-AL-ridge subset modes;
- subset CAVI for RHS/RHS_NS, exAL, stochastic, or hybrid modes;
- article online adapters;
- divide-and-combine VB;
- variational coreset VB;
- low-rank covariance CAVI;
- article-side warm-start adapters;
- article-side stochastic/hybrid batching;
- multivariate Q-DESN batching.

## Status Matrix

Status labels:

- `implemented`: coded, tested, and documented;
- `partial`: supporting code or validation infrastructure exists, but not a
  coherent current Q-DESN VB mode;
- `high priority`: worth implementing next or soon;
- `medium priority`: useful, but after higher-priority foundations;
- `low priority`: interesting but not needed for the current article unless a
  new scalability story demands it;
- `defer`: do not implement before a derivation/runtime contract.

| Mode | AL Q-DESN status | exAL Q-DESN status | Priority | Reason |
| --- | --- | --- | --- | --- |
| Full-data CAVI/LDVB | implemented | implemented | baseline | Reference target for every exact or approximate method. |
| Exact chunked CAVI/LDVB | implemented | implemented | baseline | Full-data equivalent; row-block memory tool and equivalence gate. |
| Stochastic mini-batch VB/SVI | implemented | defer | high for AL, defer exAL | AL path exists and is approximate; exAL needs separate q(s), sigma/gamma, and objective contract. |
| Hybrid SVI with full refresh | implemented | implemented for ridge/RHS/RHS_NS | baseline for AL/exAL hybrid diagnostics | Package commit `685d2f5` implements AL hybrid mode with periodic full refresh. Package commit `9c25db3` implements exAL ridge hybrid; package commit `4912699` extends hybrid exAL to RHS-family priors. Pure stochastic exAL remains gated. |
| Rolling-window CAVI/posterior-as-prior | implemented for AL ridge independent refits and posterior-as-prior beta handoff | defer | high/medium | Rolling/expanding windows are implemented with no future leakage. Posterior-as-prior is implemented only for AL ridge Gaussian beta handoff and remains target-changing. RHS/RHS_NS, exAL, stochastic, hybrid, and article adapters remain gated. |
| Fixed/stratified subset CAVI | fixed, time-block, response-quantile, and design-leverage subsets implemented for AL ridge; RHS/stochastic variants gated | defer | medium | Subset modes are target-changing cheap screening tools. exAL, RHS/RHS_NS, custom strata, and stochastic/hybrid subset modes need separate contracts. |
| Online VB | implemented for AL ridge ordered-batch posterior-as-prior wrapper; static/readout exAL helper remains partial | partial static/readout helper only | medium | Package commit `b7369b9` adds `qdesn_vb_fit_online()` for AL + ridge, full covariance, unchunked/exact chunked batches. exAL, RHS/RHS_NS, stochastic/hybrid, diagonal covariance, and article adapters remain gated. |
| Warm starts | implemented for full/exact | implemented for full/exact | baseline foundation | Package commit `438aea8` adds the first-stage Q-DESN VB warm-start API for full-data and exact-chunked AL/exAL under ridge and RHS_NS coverage. Stochastic and hybrid warm starts remain gated. |
| AL/ridge simplification ladder | implemented | implemented | baseline | Formal Q-DESN AL/exAL by ridge/RHS/RHS_NS ladder is implemented in package commit `258b6e9` and documented in `qdesn_vb_simplification_ladder_20260528.md`. |
| Diagonal covariance CAVI | implemented for AL ridge/RHS/RHS_NS | implemented for exAL ridge only | medium | Package commits `03aab6c` and `28251d8` implement explicit approximate diagonal beta covariance for full-data and exact-chunked AL. Package commit `f0d45ea` implements exAL ridge diagonal covariance; exAL RHS/RHS_NS, stochastic/hybrid, low-rank, and article adapters remain gated. |
| Low-rank plus diagonal CAVI | not implemented | not implemented | medium/low | More defensible than pure diagonal but more complex; start only if full covariance becomes limiting. |
| Divide-and-combine VB | not implemented | not implemented | low | Hard to combine local latent variables, sigma/gamma, and RHS states coherently. |
| Variational coresets | not implemented | not implemented | low | Research-heavy; not needed unless coreset construction becomes a main contribution. |
| Variance-reduced SVI | not implemented | defer | low/medium | Useful only after stochastic and hybrid AL are stable and benchmarked. |

## Global Design Principles

Every new mode must satisfy these principles.

1. Preserve the full-data unchunked API and default behavior.
2. Preserve exact chunking as full-data equivalent.
3. Mark approximate modes explicitly in controls, result objects, traces, and
   documentation.
4. Keep DESN features fixed before inference. Batching acts on the static
   readout problem, not on reservoir construction.
5. Keep RHS/RHS_NS updates global. Do not update RHS local/global shrinkage
   states as if they were row-level sufficient statistics.
6. Keep AL and exAL contracts separate. AL simplifications must not be silently
   applied to exAL.
7. Keep article GloFAS future latent paths and no-leakage checks intact.
8. Add one mode at a time, with a coherent commit and focused tests.
9. Prefer package-level implementation first, then Q-DESN routing, then article
   adapters if justified.
10. Do not promote a mode into article main configs before an economical real
    data gate and a package synthetic/source gate pass.

## Documentation Criteria

Each new mode requires a tracked implementation note before or in the same
commit series as the implementation. The note must include:

- target likelihood and prior family;
- whether the mode is exact or approximate;
- mathematical update contract;
- relationship to full-data CAVI and exact chunking;
- supported API controls and defaults;
- unsupported combinations and fail-early behavior;
- test files and commands;
- economical validation dataset/config;
- reproducibility controls and seed behavior;
- runtime and memory observation plan;
- rollback point;
- remaining limitations.

Recommended note names:

- `docs/implementation_notes/qdesn_vb_warm_start_contract_YYYYMMDD.md`
- `docs/implementation_notes/qdesn_vb_hybrid_al_contract_YYYYMMDD.md`
- `docs/implementation_notes/qdesn_vb_rolling_window_contract_YYYYMMDD.md`
- `docs/implementation_notes/qdesn_vb_subset_contract_YYYYMMDD.md`
- `docs/implementation_notes/qdesn_vb_covariance_approximations_contract_YYYYMMDD.md`
- `docs/implementation_notes/qdesn_vb_exal_approximate_contract_YYYYMMDD.md`

## Separate Derivation Documents

The current derivation note is broad. Before implementing the remaining modes,
split or extend it into smaller derivation documents so each algorithm has a
reviewable mathematical source of truth.

Required derivation docs were split on 2026-05-28:

1. `qdesn_vb_full_exact_al_exal_ridge_rhs_derivations_20260528.md`
   - full-data beta update;
   - exact chunked additivity;
   - AL local \(q(v_i)\);
   - exAL local \(q(v_i)\), \(q(s_i)\);
   - sigma/gamma LD updates;
   - ridge prior contribution;
   - RHS/RHS_NS global update contribution.

2. `qdesn_vb_warm_start_contract_20260528.md`
   - same-target initialization contract;
   - required warm-start state;
   - likelihood, prior, dimension, row-count, and design-hash checks;
   - RHS/RHS_NS state validation;
   - cold versus warm equivalence tests.

3. `qdesn_vb_stochastic_hybrid_al_derivations_20260528.md`
   - stochastic data-stat scaling;
   - stale local-variable behavior;
   - Robbins-Monro or damped natural-stat update;
   - periodic full refresh;
   - global RHS refresh cadence;
   - full-data objective refresh versus noisy surrogate.

4. `qdesn_vb_exal_approximate_derivations_20260528.md`
   - why AL stochastic equations are insufficient for exAL;
   - stochastic or hybrid treatment of \(q(s_i)\);
   - sigma/gamma LD sufficient-stat refresh;
   - failure modes from stale \(s_i\), gamma, or xi expectations;
   - required full-refresh schedule.

5. `qdesn_vb_rolling_online_derivations_20260528.md`
   - rolling-window target definition;
   - posterior-as-prior transition;
   - forgetting/window weights if used;
   - time-index leakage rules;
   - forecast-origin state handoff.

6. `qdesn_vb_covariance_approx_derivations_20260528.md`
   - diagonal beta covariance update;
   - low-rank plus diagonal update;
   - prediction variance correction;
   - uncertainty limitations;
   - compatibility with RHS expected precisions.

Each derivation doc must contain an explicit "implementation mapping" section
that names the package functions it will touch.

## Mathematical Validation Checks

For every derivation, perform these checks before coding:

- dimensions of every vector/matrix are stated and consistent;
- intercept handling is explicit and matches Q-DESN RHS policy;
- ridge and RHS/RHS_NS prior terms are separated from data terms;
- row-additive terms are identified;
- non-row-additive terms are explicitly marked global;
- AL reduction is verified separately from exAL;
- sigma/gamma update path matches existing LD machinery;
- stochastic scaling applies only to data terms;
- full refresh recovers the exact/full-data update within tolerance;
- objective labels distinguish ELBO, full-data objective refresh, and noisy
  stochastic surrogate;
- finite and positive-domain constraints are written for every latent moment;
- expected values used by code (`xis`, qv, qs, qsiggam, RHS states) are mapped
  to mathematical notation.

Recommended numeric math checks:

- one-row hand check against direct formula;
- two-batch additivity check against full data;
- chunk-size-one exactness check;
- ridge versus RHS prior-only checks on the same fixed \(X,y\);
- AL fixed-gamma reduction check;
- exAL exact chunking check with a strict and a practical tolerance;
- finite-difference check for any new RHS or covariance approximation update;
- seed reproducibility check for stochastic paths.

## Economical Testing Criteria

Every new mode should pass three levels before being considered usable.

### Level 1: Unit and Synthetic Tests

Use tiny matrices where results can be checked directly.

Minimum requirements:

- R 4.6.0 command recorded;
- fixed seed;
- finite qbeta, qv, qs where applicable, sigma/gamma, and RHS states;
- exact modes match full data within tolerance;
- approximate modes are reproducible under fixed seed;
- unsupported likelihood/mode combinations fail early.

### Level 2: Package Source Gate

Use the shared median source datasets already documented:

- literal TT500 median source subset:
  `/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500`
- larger last1000/wash500/D1n300 gate:
  `docs/implementation_notes/qdesn_vb_source_last1000_wash500_d1n300_comparison_20260528.md`

Minimum outputs:

- method summary CSV;
- exact equivalence CSV where relevant;
- stochastic/approximate diagnostics CSV where relevant;
- prediction metrics against \(y\) and true median `q_target`;
- forbidden-mode checks;
- `/usr/bin/time -v` log.

### Level 3: Article Adapter Gate

Only when package gates pass, use article-side economical gates.

Current repeated article gate:

- tiny D1N5 real-data latent-path pair;
- unchunked versus exact chunked only;
- no stochastic article controls yet.

Do not use article main Dec25 as the first validation gate for a new approximate
mode. It is too expensive and has application-specific latent future-path
contracts.

## Reproducibility Criteria

Every new mode must record:

- article and package repo SHA;
- package SHA pinned in article configs, if article configs are touched;
- R path and version;
- seed and RNG strategy;
- dataset path and hash or manifest;
- source window and row counts;
- Q-DESN design settings \(D,n,m,\) washout, lag/covariate inputs;
- likelihood and prior controls;
- batching controls;
- output directory;
- command line;
- timing and peak memory;
- pass/fail gates;
- exact files changed and commit IDs.

Generated heavy outputs should remain under ignored `results/`,
`application/logs/`, or `application/data_local/` paths unless the output is a
small summary deliberately intended for documentation.

## API Integration Criteria

Preferred control surface remains `vb_control$chunking` or `vb_args$chunking`
for Q-DESN routing.

Current exact/stochastic controls should not be broken:

```r
chunking = list(
  enabled = TRUE,
  mode = "exact",
  chunk_size = 64L,
  order = "sequential"
)
```

```r
chunking = list(
  enabled = TRUE,
  mode = "stochastic",
  chunk_size = 64L,
  order = "random",
  seed = 20260528,
  learning_rate = list(t0 = 10, kappa = 0.75, rho_min = 0.02),
  refresh = list(
    full_every = 20,
    objective_every = 20,
    sigma_every = 5,
    rhs_every = 20,
    local_every = 20
  ),
  diagnostics = list(
    trace = TRUE,
    store_batch_ids = TRUE,
    check_finite_every = 1
  )
)
```

New modes should extend this structure only when the semantics remain about
row-processing of the same static readout target. If a method changes the target
itself, such as rolling windows, subsets, divide-and-combine, or coresets, it
should use a separate explicit top-level control rather than hiding the target
change under `chunking`.

Recommended future control families:

- `warm_start`: initialization/state import;
- `rolling_window`: target window and posterior-as-prior behavior;
- `subset_fit`: fixed or stratified subset target;
- `covariance_approx`: full, diagonal, low-rank plus diagonal;
- `combine`: divide-and-combine, if ever implemented;
- `coreset`: coreset construction, if ever implemented.

## Current Code Evidence Map

The following package files are the main evidence for the status labels above.

Core package implementation files:

- `R/qdesn_vb.R`
  - builds fixed Q-DESN features;
  - routes `qdesn_fit_vb()` into the static readout engine;
  - forwards `likelihood_family`, `al_fixed_gamma`, and chunking controls.
- `R/exal_ldvb_fit.R`
  - package static/readout VB entry point;
  - supports `likelihood_family = c("exal", "al")`;
  - delegates to `exal_ldvb_engine()`.
- `R/exal_ldvb_engine.R`
  - owns the full-data, exact-chunked, and stochastic AL update loops;
  - keeps stochastic mode AL-only;
  - stores `misc$stochastic`, stochastic traces, chunking metadata, RHS traces,
    and the approximate-objective note;
  - keeps RHS/RHS_NS updates global rather than row-batched.
- `R/exal_inference_config.R`
  - normalizes `exal_make_vb_control()`;
  - normalizes exact and stochastic `chunking` blocks;
  - rejects invalid modes such as `hybrid` until implemented;
  - exposes `exal_make_beta_prior()` for ridge, RHS, and RHS_NS;
  - contains online-control builders and MCMC VB warm-start controls, which are
    related to but distinct from the canonical Q-DESN VB warm-start API added
    in package commit `438aea8`.
- `R/qdesn_vb_warm_start.R`
  - defines the canonical `qdesn_vb_warm_start` object;
  - exports `qdesn_vb_make_warm_start()`;
  - validates design hash, likelihood, prior, p0, finite state, and RHS/RHS_NS
    expected precision before routing through `qdesn_fit_vb()`.
- `R/priors_beta.R`
  - implements ridge, RHS, and RHS_NS beta-prior constructors;
  - enforces Q-DESN RHS-family no-intercept-shrink policy.
- `R/qdesn_rhs_ns_prior.R`
  - implements RHS_NS state initialization, expected precision, update, and
    ELBO pieces;
  - contains tau warmup/force-after-warmup scheduling.
- `R/exal_online_state.R`, `R/exal_online_step.R`,
  `R/exal_online_vbld.R`, and `R/exal_online_stage0.R`
  - provide online/streaming VB-LD infrastructure and benchmarks;
  - these files justify the `partial` online status, but they should be audited
    before being presented as a current Q-DESN batching comparison mode.

Current package test anchors:

- `tests/testthat/test-exal-exact-chunking-stats.R`
  - exact beta-stat additivity;
  - exact chunking preservation for small exAL fits.
- `tests/testthat/test-exal-likelihood-family-al.R`
  - AL likelihood-family path.
- `tests/testthat/test-exal-inference-config.R`
  - config normalization and inference controls.
- `tests/testthat/test-qdesn-vb-likelihood-family.R`
  - Q-DESN default exAL routing;
  - explicit AL routing;
  - exact chunking forwarding;
  - stochastic exAL fail-early behavior.
- `tests/testthat/test-exal-batching-controls.R`
  - exact/stochastic chunking normalization;
  - invalid stochastic controls fail early;
  - stochastic beta stats scale data terms only.
- `tests/testthat/test-exal-stochastic-al-vb.R`
  - stochastic AL is finite, reproducible, and labeled approximate;
  - stochastic AL remains broadly close on easy synthetic data;
  - stochastic AL keeps RHS updates global and finite;
  - stochastic exAL fails early while exact exAL remains available.
- `tests/testthat/test-qdesn-vb-batching-modes.R`
  - Q-DESN AL stochastic routing;
  - Q-DESN AL stochastic reproducibility;
  - Q-DESN exAL stochastic fail-early behavior;
  - Q-DESN exAL exact chunking preservation.
- `tests/testthat/test-static-beta-prior-rhs.R`
  - ridge/RHS/RHS_NS support and RHS scheduling diagnostics.
- `tests/testthat/test-qdesn-vb-warm-start.R`
  - Q-DESN warm-start object construction;
  - serialization round trip;
  - same-init routing checks;
  - warm-started exact AL equivalence;
  - exAL and RHS_NS finite-state coverage;
  - mismatch and stochastic-warm-start fail-early checks.

Current article and source comparison anchors:

- `docs/implementation_notes/qdesn_vb_comparison_results_20260528.md`
  - package synthetic/static and Q-DESN comparison readiness;
  - article tiny D1N5 exact gate.
- `docs/implementation_notes/qdesn_vb_source_tt500_median_comparison_20260528.md`
  - literal TT500 median source gate;
  - AL unchunked/exact/stochastic and exAL unchunked/exact comparison.
- `docs/implementation_notes/qdesn_vb_source_last1000_wash500_d1n300_comparison_20260528.md`
  - larger source gate with `D = 1`, `n = 300`, and 500 evaluated rows after
    washout.
- `application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_*.yaml`
  - economical article-side real-data exact-chunking gate.

These files are the first places Codex should inspect before starting any new
mode.

## Codex Handoff Checklist

For each future implementation task, Codex should complete this checklist
before editing package code:

1. Verify repo state for article and package:
   - branch;
   - HEAD;
   - upstream;
   - dirty/untracked state;
   - stashes;
   - latest origin.
2. Read this gap-analysis note and the relevant derivation note.
3. Confirm whether the mode changes only row-processing or changes the target.
4. If the mode changes only row-processing, decide whether `vb_control$chunking`
   is still the correct control surface.
5. If the mode changes the target, define a separate explicit control family,
   such as `warm_start`, `rolling_window`, `subset_fit`,
   `covariance_approx`, `combine`, or `coreset`.
6. Confirm AL versus exAL scope. Do not let exAL approximate paths run through
   AL-only equations.
7. Confirm ridge versus RHS/RHS_NS behavior. Do not row-batch RHS/RHS_NS states.
8. Add unit tests before or alongside engine edits.
9. Run the focused package tests listed in this note.
10. Run at least one economical source gate before documenting readiness.
11. If article configs are repinned, rerun the tiny D1N5 article gate.
12. Commit package and article changes separately.

## Mode-by-Mode TODO

### 1. Full-Data CAVI/LDVB

Status: implemented for AL/exAL, ridge, and RHS/RHS_NS in package static and
Q-DESN paths.

TODO:

- keep as reference baseline;
- add regression tests whenever any new approximate mode touches shared engine
  code;
- never change default behavior silently.

Validation:

- existing exact/stochastic test suite;
- TT500 and last1000 source comparisons;
- package comparison harness.

### 2. Exact Chunked CAVI/LDVB

Status: implemented for AL/exAL, package static and Q-DESN paths; article
fixed historical rows for latent-path AL-VB.

TODO:

- keep exact chunking full-data equivalent;
- add stricter reporting that separates fitted-state differences from sigma
  trace accumulation differences for exAL;
- maintain practical tolerance notes for larger exAL reservoir runs.

Validation:

- full-data equivalence checks;
- chunk-size-one and uneven-chunk tests;
- ridge and RHS/RHS_NS prior regression tests.

### 3. Warm Starts

Status: implemented for the first package stage. Package commit `438aea8`
adds a canonical Q-DESN VB warm-start object, exported
`qdesn_vb_make_warm_start()`, `qdesn_fit_vb()` routing through
`vb_args$warm_start`, and `exal_ldvb_engine()` support for initialized
RHS/RHS_NS beta-prior state.

Worth implementing: first package stage complete. Future extensions should be
added only after the corresponding target contract is written.

Implemented first-stage plan:

1. The package warm-start object contains qbeta, qv, qs, qsiggam, xi
   expectations, RHS/RHS_NS state when applicable, and metadata.
2. Validation checks current design dimensions/hash, likelihood, p0, prior
   family, finite state, and RHS/RHS_NS expected precision.
3. Full-data AL/exAL routing is implemented.
4. Exact-chunked AL routing is covered by focused equivalence tests.
5. Stochastic AL warm starts still fail early and remain gated.
6. Rolling-window and posterior-as-prior work should reuse this object later,
   but those modes must label the target change.

Tests:

- default cold-start behavior remains unchanged;
- warm-start API routes to the same engine init as explicit `init`;
- exact chunking plus warm start remains equivalent for AL ridge;
- exAL and RHS_NS warm-started states are finite;
- serialization round trip passes;
- design and likelihood mismatches fail early;
- stochastic AL warm starts fail early until a stochastic state contract exists.

### 4. Hybrid AL/exAL SVI with Periodic Full Refresh

Status: implemented for package static/readout and univariate Q-DESN AL, and
implemented for package static/readout and univariate Q-DESN exAL under ridge,
RHS, and RHS_NS beta priors. It is approximate unless `full_every = 1`, where
the tested paths recover the corresponding exact full-data AL/exAL behavior
within practical numerical tolerance.

Worth implementing: yes, after warm starts.

Implemented contract:

1. Use stochastic mini-batches between full refresh iterations.
2. On full refresh, recompute all local qv/qs-equivalent AL moments, sigma LD
   stats, full-data beta stats, RHS state, and full-data objective.
3. Mark the result approximate unless the final step is a full refresh and the
   convergence criterion is explicitly tied to full-data state stability.

Required derivation:

- stochastic beta natural-stat damping;
- full-refresh overwrite versus blend rule;
- sigma refresh rule;
- RHS global refresh cadence;
- objective trace interpretation.

Tests:

- `mode = "hybrid"` controls normalize;
- full refresh with every iteration recovers exact/full-data AL within
  tolerance;
- finite and reproducible on synthetic data;
- TT500 median gate;
- exact modes unchanged.

### 5. Stochastic exAL and exAL Hybrid Extensions

Status: stochastic exAL is not implemented and should fail early. Hybrid exAL is
implemented for ridge/RHS/RHS_NS with periodic full refresh and global
RHS-family updates.

Worth implementing: pure stochastic exAL, not yet. Defer until hybrid exAL is
exercised on enough examples and a stochastic exAL contract is written.

Why delicate:

- exAL has \(q(s_i)\) local moments in addition to \(q(v_i)\);
- sigma/gamma LD updates use coupled likelihood expectations;
- stale \(s_i\) and stale xi expectations can distort the stochastic target;
- objective traces are harder to interpret.

Implementation plan:

1. Maintain the exAL approximate derivation contract before broadening scope.
2. Keep pure stochastic exAL disabled.
3. Require full refresh of qv, qs, sigma/gamma LD stats, xi, beta stats, and
   RHS on a documented cadence.
4. Keep RHS/RHS_NS hybrid exAL global-only. Do not row-batch shrinkage states.

Tests:

- stochastic exAL forbidden-mode test remains;
- hybrid full-refresh-every-iteration recovers exact exAL within tolerance;
- RHS/RHS_NS hybrid exAL finite-state and reproducibility tests remain;
- sigma/gamma trace finite and stable;
- practical and strict tolerance reporting for larger reservoirs.

### 6. Rolling-Window CAVI and Posterior-as-Prior VB

Status: implemented for package univariate Q-DESN AL ridge independent
rolling/expanding refits and AL ridge posterior-as-prior beta handoff.
RHS/RHS_NS, exAL, stochastic/hybrid rolling, and article adapters remain gated.

Worth implementing: yes, medium-high priority, especially for forecasting.

Implemented contract:

1. Define target: fixed rolling training window, expanding window, or
   posterior-as-prior sequence.
2. Define whether DESN states are rebuilt per origin or carried forward.
3. Define no-leakage rules for lagged inputs and forecast horizons.
4. Implement package-level rolling Q-DESN before article latent-path adapters.
5. Use a Gaussian beta posterior-as-prior handoff only for AL ridge.

Tests:

- rolling window indices are exact and non-overlapping where required;
- no future leakage;
- posterior-as-prior dimensions and metadata match;
- exact chunked posterior-as-prior matches unchunked posterior-as-prior for the
  same handoff target;
- source-window verification using existing validation fixtures.

### 7. Fixed/Stratified Subset CAVI

Status: fixed deterministic subset CAVI, time-block stratified subset CAVI,
response-quantile subset CAVI, and design-leverage subset CAVI are implemented
for package static/readout and univariate Q-DESN AL + ridge only. RHS/RHS_NS,
exAL, stochastic/hybrid subset fitting, article adapters, and custom
allocations remain gated. Some validation scripts also use subsets for grids or
campaigns, which is separate from this explicit subset-data VB target.

Worth extending: maybe, as a diagnostic/screening tool.

Implemented contract:

1. Use explicit `subset_fit` controls, not `chunking`.
2. Support fixed deterministic subset first for AL + ridge.
3. Support time-block, response-quantile, and design-leverage stratified
   subsets with proportional or equal allocation, explicit subset size,
   explicit number of strata, and explicit seed.
4. Label the target as subset-data VB, not an approximation to the full-data
   posterior unless importance weighting is explicitly derived.
5. For Q-DESN fits, interpret row IDs as post-washout static readout rows.

Remaining extension plan:

1. Add custom strata only after their no-leakage/reproducibility and metadata
   contracts are documented.
2. Keep equal allocation limited to the implemented stratifiers until custom
   strata are documented.
3. Keep RHS/RHS_NS, exAL, stochastic/hybrid, and article adapters forbidden
   until each has a contract and tests.

Tests:

- subset row identity reproducible;
- subset target differs from full-data target and is labeled as such;
- exact chunking matches unchunked for the subset target;
- Q-DESN routes fixed subset controls;
- Q-DESN routes time-block stratified subset controls;
- stratified allocation sums to requested size and represents each stratum when
  possible;
- malformed and out-of-range row IDs fail early;
- exAL, RHS/RHS_NS, and stochastic/hybrid subset modes fail early;
- forbidden unsupported sampling schemes fail early.

### 8. Online VB

Status: canonical Q-DESN AL ridge ordered-batch wrapper implemented. Package
commit `b7369b9` adds `qdesn_vb_fit_online()`, which fits ordered Q-DESN AL
ridge batches and carries each batch's beta posterior forward as the next
batch's Gaussian beta prior. This is a target-changing workflow, not a new
streaming reservoir engine and not exact chunking.

The older static/readout exAL VB-LD helper surface remains separately audited.
Package files such as `R/exal_online_state.R`, `R/exal_online_step.R`,
`R/exal_online_vbld.R`, and `R/exal_online_stage0.R` exist. Package commit
`36428a8` adds readiness tests for serialization, one-row streaming,
reproducibility, order sensitivity, and explicit enabled-AL rejection for that
helper surface.

Worth extending: medium priority, but only after each target handoff contract is
explicit.

Implemented audit checks:

1. Disabled `exal_online_fit()` preserves batch `exal_ldvb_fit()` behavior.
2. Online states survive `saveRDS()` / `readRDS()` and resume.
3. One-row streaming records trace and metadata.
4. Stage-0 benchmark is deterministic under a fixed seed.
5. Forward and reversed streams are order-sensitive.
6. Enabled AL online mode fails early; disabled AL pass-through still works.

Remaining implementation plan:

1. Keep `qdesn_vb_fit_online()` limited to AL + ridge, full covariance, and
   unchunked/exact chunked per-batch VB.
2. Do not expose article adapters until no-leakage and latent future-path
   contracts are written.
3. Add comparison harness rows only after the chosen example explicitly wants a
   target-changing online/posterior-as-prior workflow.
4. Decide separately whether low-level DESN reservoir state handoff is worth
   implementing.

Tests:

- state serialization round trip for existing helper;
- one-batch online update metadata for existing helper;
- order sensitivity documented and tested under fixed seed;
- enabled AL online fails early because the current helper is exAL VB-LD;
- Q-DESN wrapper one-batch equivalence to ordinary AL ridge fit;
- Q-DESN wrapper exact chunking equivalence;
- Q-DESN wrapper no-leakage and batch-boundary metadata;
- Q-DESN wrapper forbidden-mode checks for exAL, RHS/RHS_NS,
  stochastic/hybrid, warm-start, and diagonal-covariance combinations.

### 9. Divide-and-Combine VB

Status: not implemented.

Worth implementing: low priority.

Reason:

- combining Gaussian beta posteriors is easy only in simplified conjugate
  settings;
- AL/exAL local variables, sigma/gamma LD states, and RHS shrinkage make naive
  combination risky;
- exact chunking and hybrid SVI are more defensible first.

Implementation plan if ever needed:

1. Start with ridge AL only.
2. Derive subset posterior de-biasing and prior correction.
3. Combine natural parameters for beta only.
4. Decide how to combine sigma and local latent states.
5. Treat RHS as unsupported until a global shrinkage combination rule is
   derived.

### 10. Variational Coresets

Status: not implemented.

Worth implementing: low priority/research-heavy.

Reason:

- coreset construction introduces a new weighted likelihood target;
- AL/exAL local latent variables and quantile objective require careful
  weighted updates;
- this is likely beyond the current article unless scalability becomes the main
  contribution.

Implementation plan if ever needed:

1. Derive weighted AL ridge CAVI first.
2. Validate weighted exact chunking.
3. Add deterministic coreset construction.
4. Defer RHS and exAL until weighted AL is stable.

### 11. Diagonal/Low-Rank Covariance CAVI

Status: not implemented.

Worth implementing: medium priority if full covariance becomes the bottleneck.

Implementation plan:

1. Add `covariance_approx = "full"` default.
2. Implement `covariance_approx = "diagonal"` for ridge AL first.
3. Validate predictive variance limitations.
4. Extend to RHS/RHS_NS only after prior expected precision mapping is checked.
5. Consider low-rank plus diagonal only after diagonal tradeoffs are measured.

Tests:

- full covariance default unchanged;
- diagonal moments finite and positive;
- diagonal posterior mean is close on low-correlation synthetic designs;
- prediction variance is labeled approximate;
- RHS expected precision compatibility test.

### 12. AL/Ridge Simplification Ladder

Status: implemented. AL, exAL, ridge, RHS, and RHS_NS now have a single formal
Q-DESN comparison harness in package commit `258b6e9`.

Worth implementing: complete; keep as a baseline regression and comparison
gate.

Recommended ladder:

1. AL + ridge;
2. AL + RHS/RHS_NS;
3. exAL + ridge;
4. exAL + RHS/RHS_NS;
5. exact chunked versions of each;
6. stochastic AL + ridge and stochastic AL + RHS/RHS_NS;
7. hybrid AL versions after implementation.

Tests:

- every ladder rung runs on the same fixed design;
- priors are recorded in output metadata;
- intercept shrinkage policy is checked;
- ridge and RHS/RHS_NS diagnostics are written side by side;
- exAL stochastic remains forbidden until implemented.

## Recommended Implementation Order

After the second critical pass, the optimal order is:

1. AL/ridge/RHS simplification ladder harness and documentation. Completed.
2. Canonical warm-start API for package Q-DESN AL/exAL under ridge and
   RHS/RHS_NS. Completed for the first package stage in commit `438aea8`.
3. Hybrid AL SVI with periodic full refresh. Completed for package/Q-DESN AL.
4. Independent rolling/expanding-window Q-DESN AL ridge refits. Completed as
   the first target-changing rolling stage.
5. Posterior-as-prior Q-DESN AL ridge VB. Completed for beta Gaussian handoff
   in package commits `fef2558`, `1259199`, and `3df0e15`.
6. Diagonal covariance CAVI prototype for AL ridge. Completed in package commit
   `03aab6c`.
7. Fixed deterministic subset CAVI as a diagnostic mode. Completed for AL
   ridge in package commit `fbf04f1`; stratified and non-AL-ridge variants
   remain gated.
8. Online VB integration, after rolling-window/posterior-as-prior semantics are
   settled.
9. Hybrid exAL, after exAL approximate derivation passes.
10. Variance-reduced AL SVI, only if stochastic/hybrid variability is a real
   limitation.
11. Divide-and-combine and coresets only if future scalability demands them.

The ladder should precede warm-start implementation because it is mostly a
reproducible comparison and documentation layer over already implemented
methods. It creates the clean baseline grid that later warm-start, hybrid,
rolling-window, and covariance-approximation modes should be required to pass.

## Immediate Next Task

Completed on 2026-05-28:

- package script `scripts/run_qdesn_vb_simplification_ladder_20260528.R`;
- package test `tests/testthat/test-qdesn-vb-simplification-ladder.R`;
- article note `docs/implementation_notes/qdesn_vb_simplification_ladder_20260528.md`;
- tiny synthetic ladder gate;
- TT500 source-data ladder gate.

Completed after the ladder:

- package file `R/qdesn_vb_warm_start.R`;
- exported helper `qdesn_vb_make_warm_start()`;
- Q-DESN `vb_args$warm_start` routing;
- engine `init$beta_state` support for RHS/RHS_NS state initialization;
- package test `tests/testthat/test-qdesn-vb-warm-start.R`.

Completed after hybrid AL:

- package file `R/qdesn_vb_rolling_window.R`;
- exported helper `qdesn_vb_fit_rolling()`;
- package test `tests/testthat/test-qdesn-vb-rolling-window.R`;
- article note `docs/implementation_notes/qdesn_vb_rolling_window_stage_20260528.md`.

Completed after the first rolling-window stage:

- beta prior natural-vector hook in `R/priors_beta.R`,
  `R/exal_online_state.R`, and `R/exal_ldvb_engine.R`;
- package test `tests/testthat/test-exal-beta-prior-natural.R`;
- posterior-as-prior AL ridge handoff in `R/qdesn_vb_rolling_window.R`;
- package gate script
  `scripts/run_qdesn_vb_posterior_as_prior_gate_20260528.R`;
- package tests in `tests/testthat/test-qdesn-vb-rolling-window.R` covering
  rolling and expanding posterior-as-prior origin sequences;
- article note
  `docs/implementation_notes/qdesn_vb_posterior_as_prior_stage_20260528.md`.

Completed after posterior-as-prior:

- diagonal beta covariance approximation for package static/readout and
  univariate Q-DESN AL ridge;
- package files `R/exal_online_state.R`, `R/exal_ldvb_engine.R`,
  `R/exal_inference_config.R`, and `R/qdesn_vb.R`;
- package test `tests/testthat/test-exal-beta-covariance-approx.R`;
- article note
  `docs/implementation_notes/qdesn_vb_diagonal_covariance_stage_20260528.md`.

Completed after diagonal covariance:

- fixed deterministic subset CAVI for package static/readout and univariate
  Q-DESN AL ridge;
- package files `R/exal_online_state.R`, `R/exal_ldvb_engine.R`,
  `R/exal_inference_config.R`, and `R/qdesn_vb.R`;
- package test `tests/testthat/test-exal-subset-fit.R`;
- article note
  `docs/implementation_notes/qdesn_vb_fixed_subset_stage_20260528.md`.

Completed after fixed subset:

- readiness tests for existing static/readout online exAL VB-LD helpers;
- package file `R/exal_online_vbld.R`;
- package test `tests/testthat/test-exal-online-vbld.R`;
- article note
  `docs/implementation_notes/qdesn_vb_online_integration_audit_20260528.md`.

Completed after online helper audit:

- time-block stratified subset CAVI for package static/readout and univariate
  Q-DESN AL ridge;
- package files `R/exal_online_state.R`, `R/exal_ldvb_engine.R`,
  `R/exal_inference_config.R`, and `tests/testthat/test-exal-subset-fit.R`;
- article note
  `docs/implementation_notes/qdesn_vb_stratified_subset_stage_20260528.md`.

Completed after stratified subset:

- RHS/RHS_NS diagonal beta covariance for package static/readout and
  univariate Q-DESN AL;
- exact chunked diagonal RHS/RHS_NS equivalence;
- package files `R/exal_ldvb_engine.R`, `R/exal_online_state.R`, and
  `tests/testthat/test-exal-beta-covariance-approx.R`;
- article note
  `docs/implementation_notes/qdesn_vb_rhs_diagonal_covariance_stage_20260528.md`.

The next implementation task should now be one of:

1. low-rank covariance, only after diagonal covariance is exercised on the
   intended comparison examples.
2. custom subset strata, only after no-leakage and metadata contracts are
   documented.

Do not start stochastic/hybrid exAL, RHS/RHS_NS posterior-as-prior, or
article-side approximate adapters until their contracts and fail-early tests
are explicit.

The completed first ladder runs only already implemented modes:

- AL + ridge, unchunked;
- AL + ridge, exact chunked;
- AL + ridge, stochastic approximate;
- AL + RHS/RHS_NS, unchunked;
- AL + RHS/RHS_NS, exact chunked;
- AL + RHS/RHS_NS, stochastic approximate if the current RHS stochastic path
  passes focused tests;
- exAL + ridge, unchunked;
- exAL + ridge, exact chunked;
- exAL + RHS/RHS_NS, unchunked;
- exAL + RHS/RHS_NS, exact chunked.

It does not include stochastic exAL, hybrid, rolling-window, covariance
approximations, subsets, online, divide-and-combine, or coresets in the first
ladder.

Minimum validation completed for the ladder:

- focused package tests for exact chunking, stochastic AL, Q-DESN likelihood
  routing, Q-DESN batching modes, and RHS/RHS_NS;
- one synthetic tiny ladder run;
- one TT500 median source ladder run;
- forbidden-mode check that stochastic exAL still fails early;
- exact chunking equivalence checks for every exact rung;
- stochastic AL diagnostics clearly labeled approximate;
- ridge and RHS/RHS_NS metadata recorded in every output row;
- docs updated with commit SHA and commands.

## Remaining Implementation Checklist

Use this checklist after every commit. A mode is not complete until it has a
derivation/contract, implementation, tests, economical validation, documentation,
and clear target labeling.

### Accepted Baseline Modes

- [x] Full-data AL/exAL Q-DESN VB under ridge and RHS/RHS_NS.
- [x] Exact chunked AL/exAL Q-DESN VB under ridge and RHS/RHS_NS.
- [x] Stochastic mini-batch AL Q-DESN VB, approximate.
- [x] Hybrid AL Q-DESN VB with periodic full refresh, approximate unless
  `full_every = 1`.
- [x] Canonical warm-start object for full/exact AL/exAL under ridge and
  RHS/RHS_NS.
- [x] Simplification ladder across implemented AL/exAL, ridge/RHS/RHS_NS, and
  batching controls.
- [x] Independent rolling/expanding-window Q-DESN AL ridge refits with no future
  leakage and exact chunking equivalence.
- [x] Posterior-as-prior Q-DESN AL ridge beta handoff over rolling/expanding
  origin sequences.
- [x] Diagonal beta covariance approximation for AL ridge and RHS/RHS_NS,
  explicitly approximate.

### Remaining Gated Work

- [ ] Posterior-as-prior extensions beyond AL ridge beta handoff.
  - RHS/RHS_NS rolling requires shrinkage-state semantics.
  - exAL posterior-as-prior requires q(s), q(v), sigma/gamma, xi, and metadata
    contracts.
  - Stochastic/hybrid posterior-as-prior requires approximate target labels per
    origin and refresh semantics.
- [ ] Rolling-window extensions beyond AL ridge refits and AL ridge
  posterior-as-prior.
  - RHS/RHS_NS rolling requires shrinkage-state semantics.
  - exAL rolling requires full/exact exAL window gates.
  - stochastic/hybrid rolling requires approximate target labels per origin.
- [ ] Diagonal covariance extensions.
  - exAL ridge is implemented with practical exact-chunking gates.
  - exAL RHS/RHS_NS still requires q(s), gamma/sigma, xi, and shrinkage-state
    feedback validation.
  - stochastic/hybrid diagonal covariance remains forbidden until a combined
    approximate contract exists.
- [ ] Low-rank plus diagonal covariance CAVI.
  - Start only after diagonal AL ridge passes.
- [x] Fixed deterministic subset CAVI for AL + ridge.
  - Use `subset_fit`, not `chunking`.
  - Record subset row IDs and target label.
  - Package commit `fbf04f1` implements unchunked and exact chunked subset
    targets.
- [x] Time-block stratified subset CAVI for AL + ridge.
  - Package commit `7f310ed` implements proportional time-block allocation with
    explicit `size`, `n_strata`, and `seed`.
  - Package commit `4912699` adds equal allocation for the same time-block
    subset target.
- [x] Richer subset stratification.
  - Package commit `f0d45ea` implements response-quantile and design-leverage
    stratified subset targets for AL + ridge.
  - Custom strata, RHS, exAL, and stochastic/hybrid subset modes remain gated.
- [x] Static/readout online exAL VB-LD helper readiness audit.
  - Package commit `36428a8` covers serialization, one-row streaming,
    reproducibility, order sensitivity, and enabled-AL fail-early behavior.
- [x] Canonical Q-DESN AL ridge online wrapper.
  - Package commit `b7369b9` implements `qdesn_vb_fit_online()` for ordered
    batches, posterior-as-prior Gaussian beta handoff, full covariance, and
    unchunked/exact chunked per-batch VB.
- [ ] Online VB extensions.
  - RHS/RHS_NS, exAL, stochastic/hybrid, diagonal covariance, low-level DESN
    reservoir handoff, and article adapters remain gated.
- [x] Hybrid exAL approximate VB for ridge/RHS/RHS_NS.
  - Implemented for package static/readout and univariate Q-DESN exAL
    ridge/RHS/RHS_NS.
  - `full_every = 1` recovers exact exAL within practical tolerance.
- [ ] Stochastic exAL.
  - Remains forbidden until hybrid exAL and exAL-specific stochastic equations
    are validated.
- [ ] Variance-reduced AL SVI.
  - Only if stochastic/hybrid variability becomes a measured limitation.
- [ ] Divide-and-combine VB.
  - Low priority; requires prior correction and local/sigma/RHS combination
    rules.
- [ ] Variational coresets.
  - Research-heavy; requires weighted AL CAVI and target-label contract.
- [ ] Article-side approximate GloFAS batching.
  - Do not expose before package-level approximate methods and no-leakage gates
    pass.

The next task after the extended-mode completion stage should be chosen from
the remaining checklist. The safest candidates are low-rank-plus-diagonal
covariance for AL + ridge, a custom-strata subset interface, or a narrow
exAL RHS/RHS_NS diagonal covariance derivation if that covariance approximation
matters. Keep pure stochastic exAL forbidden until the exAL-specific stochastic
derivation contract is implemented.

## Stop Gates

Stop implementation and report instead of continuing if:

- full-data defaults change;
- exact chunking equivalence breaks;
- RHS/RHS_NS semantics become row-batched or ambiguous;
- exAL approximate updates are introduced without a derivation doc;
- objective traces are mislabeled;
- stochastic/approximate modes are reported as exact;
- article future-path no-leakage contracts are touched unintentionally;
- tests fail or are skipped silently;
- runtime grows beyond the economical gate without documenting why.

## Summary Decision

Do not try to implement every listed mode in one undifferentiated change. The
repo now has the main baseline and exact memory-safe modes, AL stochastic
mini-batch VB, AL hybrid VB, warm starts, the simplification ladder, and the
first independent rolling-window AL ridge stage. The best next investment is a
single target-changing or approximation stage with its own contract, tests, and
economical gate, rather than mixing posterior-as-prior, covariance
approximations, exAL approximations, and article adapters in one commit.
