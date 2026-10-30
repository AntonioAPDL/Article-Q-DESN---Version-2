# GloFAS issued-member likelihood correction

This change is restricted to the issued-window latent-path application. It
does not alter historical Parts 1–3, the simulations, PriceFM, or any article
result. All fitted issued-window families are refitted under a separately
versioned target. The historical fractional-weight calculation remains
reproducible through the unchanged default policy.

## Target and forecast quantity

Write `y_t` for transformed gauge observations, `z_t` for transformed
retrospective GloFAS, and `z_he` for the 51 members at each of 28 issued
horizons. Given a latent future reference path `ell`, the reference and
discrepancy locations are `q_hp(ell)=x_h(ell)' beta_p` and
`d_hp(ell)=r_h(ell)' alpha_p`. GloFAS location is their sum. The discrepancy
sign is GloFAS minus reference. Each included observation has one ordinary
likelihood contribution; there are 1,428 issued contributions. Residual
conditional independence across members and horizons, given parameters and
the path, is an explicit baseline assumption, not a claim that the ensemble
contains 51 independent gauge measurements.

For each independent quantile regression the target is proportional to

```
prior(theta_p) * L_history(theta_p) * R_T(ell_p)
  * product_{h=1}^{28} product_{e=1}^{51}
      f_p(z_he | q_hp(ell_p)+d_hp(ell_p), sigma_Gp, gamma_Gp).
```

For AL, omit gamma. `R_T` is the existing Gaussian path prior calibrated from
the historically fitted Normal-RHS recursive bank. It replaces, rather than
supplements, a future-Y likelihood. Excluded future-Y factors remain absent;
future USGS observations are scoring-only. The two Gaussian comparators use
their existing future-Y construction instead of this replacement prior.

MQ retains seven level-specific paths, the existing prior on the first slope
vector and adjacent slope differences in each coefficient block, and the
original intercept/RHS priors. The likelihood/path product above occurs once
per level and the MQ coefficient prior occurs once. Numerical initial values
from separate fits do not add their priors to the MQ target.

The selected reporting rule is preserved: quantile-family forecasts are Monte
Carlo means of extrapolated reference-readout locations. These are not
asserted to equal quantiles of the latent-reference path or a fully integrated
posterior predictive distribution. Gaussian comparator curves use empirical
type-8 quantiles of simulated latent future paths. Their different path laws
and reporting operators are retained, so this is a comparison of complete
forecast procedures, not a pure likelihood ablation.

## Why the weights change

The historical code raises the complete augmented contribution to `w=1/51`.
In general, integrating that powered joint density does not equal powering
the marginal density. For an AL contribution, its normalized marginal then
has probability approximately 0.01904919 below the location when `p=.05`,
instead of .05. This is a fixed-parameter mathematical calculation, not the
application's empirical coverage. Unit weights remove that particular
augmentation discrepancy for AL and quantile-fixed exAL. They also change
the information allocation in the Gaussian comparison, which must therefore
be refitted as part of the complete six-family comparison.

## Conditional calculations

Use `IG(a,b)` with density proportional to `u^(-a-1) exp(-b/u)` and
`GIG(nu,chi,psi)` with kernel `u^(nu-1) exp[-(chi/u+psi*u)/2]`.
All source counts below include only included density factors; replaced
future-Y factors do not enter those counts.

For Gaussian errors of variance `s_c^2` and a coefficient prior independent
of that variance,

```
P = P0 + sum_i h_i h_i'/s_c(i)^2
b = P0 m0 + sum_i h_i z_i/s_c(i)^2
theta | ... ~ Normal(P^-1 b, P^-1)
s_c^2 | ... ~ IG(a_c+n_c/2, b_c+sum_i residual_i^2/2).
```

VB residual second moments retain coefficient covariance and feature/path
moments. When a response is latent, the cross moment is `E(h_i z_i)`, not in
general `E(h_i) E(z_i)`. Source-specific variances and all original priors
are unchanged.

For AL, `A=(1-2p)/(p(1-p))`, `B=2/(p(1-p))`,
`v~Exp(rate=1/sigma)` and
`z|v~Normal(mu+A v, variance=sigma B v)`. Then

```
v | ... ~ GIG(1/2, residual^2/(sigma B), (A^2/B+2)/sigma)
sigma_c | ... ~ IG(a_c+3 n_c/2,
  b_c+sum_i[v_i+(residual_i-A v_i)^2/(2B v_i)]).
```

The `3 n_c/2` shape is specific to these v coordinates. After marginalizing
v the scale conditional has the different shape `a_c+n_c`; there is no
contradiction. The separate RHS global conditional retains its corrected
`(r+1)/2` shape for r penalized slopes. It counts different quantities.
At exactly zero fixed residual, v has a Gamma-1/2 limit and infinite inverse
moment; implementation floors used for numerical VB are not exact finite
inverse-moment identities.

For quantile-fixed exAL use its existing supported shape transformation,
`A=A(ptilde)`, `B=B(ptilde)` and `lambda=lambda(gamma,p)`, with
`s~HalfNormal(0,1)` and
`z|v,s~Normal(mu+A v+sigma lambda s, variance=sigma B v)`. The local v
conditional has GIG index 1/2; the positive-Normal s conditional has
precision `1+sigma lambda^2/(B v)` and linear term
`lambda(residual-A v)/(B v)`. The scale conditional at fixed shape has

```
nu  = -a_c-3 n_c/2
chi = 2b_c+2 sum(v_i)+sum[(residual_i-A v_i)^2/(B v_i)]
psi = lambda^2/B * sum(s_i^2/v_i).
```

The scale-independent cross term is shape-dependent and is retained when
updating shape, together with B-dependent normalizers. The structured
scale–shape VB factor integrates scale analytically and evaluates shape by
one-dimensional quadrature. Mixed moments preserve that dependence. No
universal exAL conjugacy claim is made.

The nonlinear future-path calculation remains the existing Gaussian–Delta
approximation. Its coordinate monitor is not described as a fully evaluated
continuous-factor ELBO. Point blocks and numerical stabilization remain
distinguished from exact posterior integration.

## Reproducibility and execution

`application_model.ensemble_member_weight_policy` accepts
`fractional_per_horizon_v1` (unchanged default) or
`unit_member_likelihood_v1` (explicit new target). Validators reject
inconsistent weights. New fit diagnostics state the actual policy.

Preparation authenticates the frozen design, Gaussian path prior, historical
bank and its retained source-fit copy. It preserves historical matrices,
selected reservoirs, data, covariates, priors, seeds, member identities and
reporting rules. It rebuilds the future-builder closure from saved context,
clears compiled caches and gives the materialized design a new version/hash.
Future continuation uses the stored reservoir matrices and Article-side
functions. The frozen run at `60daab261d52eec0ae24060babe186d618303e2b`
retains its original source and launch manifest. Its worker's local engine
override did not intercept globally sourced helpers; this defensive gap does
not change the saved-reservoir continuation or fitted target. A subsequent
integration-only correction temporarily replaces the engine lookup in the
helpers' source environment for the explicit unit-member policy, immediately
after loading configuration and before validation. It restores the original
binding on normal return or error; legacy policies are unaffected. The no-fit
worker-AST regression exercises indirect helper lookup and both restoration
paths. The original source freeze includes all Article R files, worker scripts,
configuration files and runtime inputs used in the frozen construction; the
later defense does not rewrite that provenance or relaunch existing fits.

The initial DAG has 18 fits: Gaussian ridge, Gaussian RHS, seven median-outward
AL fits, their seven matching exAL fits, and two complete-grid MQ fits. No
historical Part 1–3 fit is relaunched. At most eight newly active jobs use
CPUs 48–55, one CPU per job; MQ inner workers and BLAS/OpenMP threads are one.
The controller uses `nice 10`, an exclusive lock and dependency/marker guards.
It does not touch other worktrees, jobs or Jerez.

The bounded numerical limits are frozen before examining new outcomes.
Independent fits allow up to 2,000 iterations, MQ up to 200 outer iterations
with up to 60 inner iterations, and exAL uses deterministic shape quadrature
at 16/24/32/48 nodes per panel with tolerance 1e-6. A limit is not convergence.
Caps and failures remain review states; there are no automatic continuations,
seed searches or refits selected by forecast score or held-out coverage.

After all initial processes exit, finalization verifies manifests, weights,
truth separation, complete dates/levels, numerical stopping and exAL
quadrature. It retains all six fitted families and raw ensemble, including
regressions. Its decision is scientific-review readiness, not publication.
Article replacement and direct-Git Overleaf publication are separate,
coordinator-owned gates.

Run preparation, then the focused tests. Only after source review/commit and
a matching PASS receipt may the launcher freeze and preflight. Production
execution additionally requires the coordinator's resource/launch review.
Ignored model/runtime evidence is never committed or deleted by this workflow.
