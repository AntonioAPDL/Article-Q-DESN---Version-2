# R123 Full-State Convergence Diagnosis

## Scope and preserved evidence

BG only, within Fold-1 training-internal origins. The prior campaign completed
1,298 Ridge decisions (646 fits and 652 washout exclusions), 90 Normal centre
attempts (66 accepted and 24 capped), and 66 scores. All old source worktrees,
contracts, scores and checkpoints stay immutable. No test, official validation,
quantile fit, exAL, joint, MCMC, registry or article is authorized by this stage.
The source fitting revision remains 7ae8d6f578000ab17cd30567a23f7b806028cee0.

## Findings that motivate correction

The frozen `predictive_fixed_point` helper accepted either a last-step absolute
coefficient change below 1e-5 OR ten steps of four predictive/prior checks.
Twenty-seven accepted fits, including the three leading-candidate splits,
passed only the first route. This establishes predictive stability under that
rule, not full variational stationarity. Separately, the controller demanded
all 30 centre candidates complete all three splits, despite 21 complete
candidates and a downstream need for only ten. That stop was intentional,
but unnecessarily inflexible for a screening stage with difficult structures.

Failures were finite results at the 2,000-iteration cap; the R entrypoint raised
before writing their trace/state. The absence of failure diagnostics prevents
an evidence-based distinction between slow prior scales, coefficient movement,
conditioning and numerical objective problems. Changing the iteration cap or
silently admitting partial candidates would not repair that observability gap.

## Target and objective derivation

The exact frozen Normal factory uses the project's product density
`N(beta_j;0,tau2*lambda_j2) N(0;beta_j,zeta2)` for j=2,...,p.
The intercept has its separate fixed, zero-centred precision 1e-16.
IG(a,b) has density proportional to x^(-a-1) exp(-b/x).
The d=p-1 HS normalizers contribute -d/2 log(tau2); the auxiliary
IG(1/2,1/xi) contributes -3/2 log(tau2). Consequently the global conditional
shape is (d+1)/2=p/2, with rate E(1/xi)+.5 sum E(beta_j^2)E(1/lambda_j2).
The slab factor is independent of tau2. No shape correction or prior change
is justified by this convergence diagnosis.

With Gaussian likelihood and independent IG(a0=2,b0=1) noise prior, compute
Elog(omega2)=log(b)-digamma(a) and E(1/omega2)=a/b. Expected SSE is
yty-2*m'Xty+tr[XtX*(V+mm')]. The total objective sums expected likelihood,
noise prior, IG entropy, Gaussian beta entropy, and the frozen product-prior
expected joint plus its latent entropies. Retain all normalizers. This is the
objective of the implemented product/augmentation convention, not a claim
that it is interchangeable with a differently normalized RHS hierarchy.
Compare objective values only for the same data, dimensions and fixed prior.

Methodological reference for the auxiliary hierarchy:
Makalic and Schmidt, https://arxiv.org/abs/1508.03884.
For the project product regularization distinction see Nishimura and Suchard,
https://arxiv.org/abs/1911.02160. The algebra above follows the actual executed
code, not a mechanical substitution of a formula from another model.

## Correction implemented on an isolated task branch

The original modes keep their historical behavior. New opt-in
`full_variational` convergence requires ten consecutive stable steps in all
existing four checks AND covariance-relative change, maximum active RHS
log-rate change, and absolute objective increment per observation. No
coefficient-only shortcut. Record total objective, global/slab inverse moments
and any precision jitter. Finite capped checkpoints/traces are persisted in
the separate diagnostic namespace and explicitly excluded from selection.

Continuation restores beta mean/covariance, noise shape/rate and every RHS
variational factor and iteration counter. Exact sufficient statistics and
fixed hyperparameters must agree. Legacy checkpoints are admissible only
under their known noise prior (2,1). Initial tau changes the initial factor
only, never the fixed tau0. No upstream estimate becomes a prior centre.

## Bounded experiment and decision plan

Run ten jobs, at most 15 available physical cores, one pinned core per model:
six continuations for the top two specifications across three splits; two
previously rejected D3/D6 structures on split 1, each initialized at tau=1
and tau=tau0. Keep total cap at 2,000 and original statistics/runtime/prior.
This panel asks whether the strongest saved fits reach full stationarity and
whether the legacy start explains rejection, without rerunning screening.

Before launch: independent Monte Carlo objective check; monotonicity on a
small well-conditioned design; bitwise fresh-versus-resumed fitting test;
changed prior/statistic rejection tests; cap evidence and selection-isolation
tests; frozen-source/parent artifact verification; idle physical-core and
200-GiB memory/disk reserves. Source code must be committed and clean.

After launch: inspect raw objective and all scale/covariance traces; normalized
Gram spectrum and jitter; rank sensitivity to continued fitting. If a fit
remains genuinely slow, reject it at its bounded cap or justify one focused
training-only continuation, not a blanket budget increase. If necessary,
explicitly authorize a NEW protocol selecting only fully certified three-split
candidates. Never silently alter the old 30/30 requirement or fill missing
validation scores. Tau/AL fitting remains blocked until this review is complete.

## Files, exclusions and reproducibility

New protocol and entrypoints: `pricefm_stage_r123_stationarity_protocol_20261004.json`,
`436_diagnose_pricefm_stage_r123_stationarity.R`,
`437_run_pricefm_stage_r123_stationarity.py`. Extend only the task-owned
`pricefm_recursive_normal_fit.R`. Tests:
`test_pricefm_rhs_stationarity.R`, `test_pricefm_stage_r123_stationarity.py`
and the existing Normal/R120-R123 regressions.

Generated evidence is under `application/data_local/pricefm/campaigns/
pricefm_stage_r123_stationarity_diagnosis_20261004`, already ignored. Keep the
master tracker under ignored `local_trackers/`. Commit only source, protocol,
tests and this methods note on the dedicated branch. No main or Overleaf push.
No article-safe replacement is produced. NOT_READY_FOR_INTEGRATION.
