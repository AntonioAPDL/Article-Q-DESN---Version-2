# PriceFM R136: targeted extended-readout comparison

## Decision addressed

R134/R135 test whether the pure readout
`[intercept, h1, ..., hD]` can replace the older PriceFM-application QDESN. R136
tests the scientifically distinct extended readout
`[intercept, u_t, h1, ..., hD]`, where `u_t` contains the same endogenous price
lags and current/lagged exogenous values that drive the first reservoir layer.
The experiment asks whether a direct linear bypass of those observed/generated
inputs repairs weaknesses of the pure reservoir representation.

R136 is a three-region development experiment, not a promotion campaign. It does
not replace authority, mutate the registry/article, authorize all-region work, or
alter the running R135 campaign on Jerez.

## Frozen evidence and separation from R135

- Parent design: `pricefm_stage_r134_pure_qdesn_optimization_20261011` at
  `5f8510c73236907aaf32ea3dd725e72bf24620b0`.
- Frozen dependency: `work/pricefm-r127-closeout-20261008` at
  `1e24342e1ecd2dd7a99d8df2445f29be7f7a03d2`.
- Regions: BG (weak), HR (middle), and DK_1 (strong), with all three official folds.
- R134 Ridge rankings define a local search neighborhood and paired controls only.
  They do not select an R136 model.
- R136 uses a separate Muscat worktree, branch, campaign tag, controller, task
  namespace, and output root. No Jerez process or R135 artifact is modified.

## Selection protocol

1. Build 192 deterministic extended-readout candidates per region around the top
   12 frozen R134 Ridge basins and R134 RHS finalists. Preserve exact extended
   versions of those parent structures as paired controls.
2. Screen every candidate with Normal Ridge on the same three forward internal
   splits within the fold-1 training window. Teacher forcing occurs between daily
   origins; each 96-step forecast is recursive within its origin.
3. Restrict dense Normal-RHS and quantile work to readout dimension at most 2,561.
   Select the best eight admissible Ridge structures and force inclusion of an
   admissible paired R134 RHS-finalist control.
4. Fit three fixed, dimension-aware `tau0` multipliers for every shortlisted
   structure on all three internal splits. Retain only complete certified groups.
5. Confirm one finalist per region using all seven independently fitted AL
   quantiles on all three internal splits. Freeze the structure and `tau0` by mean
   seven-quantile AQL, with worst-split AQL as the deterministic tie breaker.
6. Only after freezing, refit each winner for the three official folds and compute
   recursive 96-step forecasts with 500 posterior paths.

The official fold outcomes are retrospective development evidence and never enter
candidate, `tau0`, or model-family selection.

## Computational bounds

Ridge may inspect readouts up to dimension 4,609 because its sufficient-statistic
fit is cheap. Dense RHS/AL covariance work is capped at 2,561 dimensions. This cap
includes the exact extended versions of the principal R134 RHS controls (roughly
2,416--2,446 columns) while excluding larger readouts that cannot be completed
responsibly in this bounded campaign. Excluded high-dimensional Ridge candidates
remain in the audit as diagnostic evidence.

The controller uses at most 30 idle physical cores, pins one single-threaded worker
to each core, retains 180 GiB available memory and 170 GiB free disk, and caps R136
output at 60 GiB. A smoke gate precedes the broad launch. Every task is immutable,
hash-bound, atomic, and resumable; interrupted unsealed attempts are preserved.

## Statistical target and convergence

- Normal and AL RHS priors are fixed and zero centered. Parent estimates and
  adjacent quantiles are initialization only.
- AL fits use only the public CRAN `exdqlm` 1.1.1 API.
- Formal convergence is preferred. A finite capped AL fit is usable only when the
  independent R129 same-state fixed-point certificate passes all declared gates.
- The likelihood, prior, `tau0`, design matrix, tolerance, and posterior target are
  never changed by certification or resumption.
- No MCMC, exAL, or joint model is part of R136.

## Decision gate

R136 can justify a wider extended-readout campaign only after complete results for
all nine region-fold cells. The primary comparison is `cdf_pool_clipped` AQL
against the frozen QDESN and operational PriceFM references. Region means, fold
stability, late-horizon behavior, coverage, width, and the paired pure/extended
controls are supporting evidence. A single winning fold is insufficient, and the
campaign cannot promote itself.

## Reproduction

The tracked protocol, runner, fitter, core utilities, source-matched release test,
and regression suite are the reproducibility surface. Runtime preparation records
source, dependency, parent closeout, data, package, training-bank, and release
hashes before any task begins. The background controller additionally requires
`PRICEFM_R136_LAUNCH_APPROVED=true`.
