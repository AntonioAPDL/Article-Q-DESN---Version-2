# Joint exAL-QVP-QDESN-RHS Extension Plan

Date: 2026-06-30

This note records a repo-native design for a joint multi-quantile
exAL-QVP-QDESN-RHS extension. It is an extension plan, not current article
evidence. The current manuscript-facing Q-DESN model fits one quantile level at
a time and uses post hoc monotone synthesis when a multi-quantile curve is
needed.

## Provenance Snapshot

- Article worktree: `/data/jaguir26/local/src/Article-Q-DESN`
- Branch: `application-ensemble-likelihood-redesign`
- HEAD: `e48c5edda7f2d0f4e3142e5202756e414c8f53b5`
- Tracking branch: `origin/application-ensemble-likelihood-redesign`
- Worktree status at audit: existing local PriceFM edits were present in
  `application/scripts/pricefm/` and `application/tests/`; this note does not
  touch them.
- Branch divergence from `origin/main`: `109 35` for
  `git rev-list --left-right --count origin/main...HEAD`; the article branch
  and Overleaf/main branch should not be silently merged.
- Shared validation worktree:
  `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Shared validation branch: `validation/shared-fitforecast-v2-1.0.0`
- Live validation HEAD at audit:
  `c051364d6fb5d119e9598bfd81d13578113cf80d`
- Article-pinned validation evidence commit:
  `4d77027184df369a0607f3ac78eb7eae2687a5ed`

The live validation worktree also had local changes beyond the article pin.
The article-facing TT500 evidence should therefore be read from
`application/config/shared_validation_tt500_final_fitforecast.yaml`, not from
the current validation worktree state.

## Current Article Boundary

The current model is a fixed-design, single-quantile Q-DESN. For a target
level `p0`, the DESN feature matrix is fixed after reservoir construction, and
posterior inference is over the readout coefficients, exAL scale/asymmetry,
latent augmentation variables, and shrinkage scales. The supplement already
derives:

- AL and exAL latent Gaussian representations;
- separate intercept treatment;
- ridge and `rhs_ns` coefficient priors;
- MCMC blocks for coefficients, GIG latent variables, truncated-normal exAL
  latents, scale/asymmetry, and RHS scales;
- VB/VB-LD factors and ELBO terms.

Multi-quantile output in the article is currently independent quantile fits
plus isotonic/rearrangement synthesis. That synthesis produces monotone
summaries but is not a joint posterior over a quantile function.

## Validation And Application Guardrails

The final TT500 article validation is:

`shared_validation_tt500_final_fitforecast_20260629_stage4_qdesn_vb_repair`

It is pinned by `application/config/shared_validation_tt500_final_fitforecast.yaml`.
The table builder consumes 3240 lead-level TT500 rows and produces 108 summary
rows, with 9 Q-DESN VB exAL RHS replacements from Stage 3 and Stage 4 repair
handoffs. It excludes TT5000 MCMC claims.

The current GloFAS manuscript aliases are under
`tables/glofas_application_current_*`. The selected run at audit was
`glofas_stage_m_stage_l_full7_confirmation_20260629_m_stage_l_runnerup_a0125_win200_scorebalanced_synthesis_final`.
Those fits use independent AL/VB quantile levels and no-refit synthesis-time
spread calibration.

The current PriceFM manuscript assets are Stage M aliases under
`tables/pricefm_stage_m_*`. Later Stage N-Z files are diagnostic/design
contracts unless separately promoted.

No joint-QVP claim should be attached to the current TT500, GloFAS, or PriceFM
evidence.

## QVP Source Alignment

Kohns and Szendrei's QVP construction uses a decision-theoretic/general-Bayes
multi-quantile likelihood, an ALD working likelihood across quantile levels, a
state-space difference prior over quantile-indexed coefficients, fused
horseshoe shrinkage, and sparse precision sampling. The repo-native extension
should borrow those structural ideas while using the article's exAL notation
and `rhs_ns` product representation.

Important adaptation choices:

- Treat repeated use of the same `y_t` across quantile levels as a composite
  or general-Bayes working likelihood.
- Include an explicit learning-rate option `kappa`. The calibrated AL validation
  default is `kappa = 1`; subunit values such as `kappa = 1 / K` are retained
  only for explicitly labeled stress or mis-target diagnostics until a
  marginal-likelihood-safe tempering derivation exists.
- Use sparse precision algebra; do not build dense `(K * p) x (K * p)`
  covariance matrices except in tiny tests.
- Keep intercept/order parameters outside the fused reservoir-weight prior.
- Do not put a QVP prior on reservoir states or recurrent weights.

## Proposed Model

Let `tau_1 < ... < tau_K`. Let `z_t` be the non-intercept Q-DESN feature vector
after the existing fixed DESN construction and scaling. Define

```text
q_{k,t} = alpha_k + z_t' beta_k
```

where `alpha_1 < ... < alpha_K` are ordered quantile intercepts and `beta_k`
are quantile-specific readout slopes.

Use an anchor-state QVP prior:

```text
beta_1 ~ RHS_NS(tau_base, lambda_base, zeta_base)
Delta_k = beta_k - beta_{k-1} ~ fused RHS_NS(tau_delta_k, lambda_delta_k, zeta_delta_k),
  k = 2, ..., K.
```

This is the safest first implementation because `K = 1` reduces exactly to the
existing single-quantile slope prior. A later phase can add a separate
quantile-invariant slope `beta_bar`, but that should not be introduced until
the anchor-state version is tested because it creates an additional
identifiability choice.

For each `(k,t)`, use the article exAL working likelihood

```text
y_t | beta_k, alpha_k, sigma_k, gamma_k, s_{k,t}, v_{k,t}
  ~ Normal(q_{k,t} + lambda(gamma_k) * sigma_k * s_{k,t}
           + A(gamma_k) * v_{k,t},
           B(gamma_k) * sigma_k * v_{k,t})
v_{k,t} | sigma_k ~ Exp(rate = 1 / sigma_k)
s_{k,t} ~ TN(0, 1)
```

with the AL special case obtained by setting `gamma_k = 0` and omitting the
positive-shift latent block.

The composite complete-data target is proportional to

```text
prod_{k=1}^K prod_{t=1}^T
  p_exAL(y_t | q_{k,t}, sigma_k, gamma_k, s_{k,t}, v_{k,t})^kappa
  p(v_{k,t} | sigma_k)^kappa
  p(s_{k,t})^kappa
times priors.
```

The default should be `kappa = 1`, configurable and recorded in every manifest.
Subunit `kappa` sensitivity remains useful as a stress diagnostic, but it should
not be interpreted as the observed AL/check-loss target unless a separate
marginal tempering derivation is added.

## Sparse Coefficient Block

Stack `beta = (beta_1', ..., beta_K')'`. Let `H` be the block first-difference
operator such that

```text
H beta = (beta_1', Delta_2', ..., Delta_K')'.
```

Given latent variables and likelihood parameters, define the stacked weighted
Gaussian working response

```text
y_star_{k,t} = y_t - alpha_k
               - lambda(gamma_k) * sigma_k * s_{k,t}
               - A(gamma_k) * v_{k,t}
w_{k,t} = kappa / (B(gamma_k) * sigma_k * v_{k,t}).
```

Let `X_stack` contain block-diagonal copies of `z_t` by quantile. Let
`P_delta` be block diagonal with the `rhs_ns` precision for `beta_1` and the
fused `rhs_ns` precisions for `Delta_2, ..., Delta_K`. Then

```text
P_beta = H' P_delta H
K_beta = X_stack' W X_stack + P_beta
m_beta = K_beta^{-1} X_stack' W y_star
beta | ... ~ Normal(m_beta, K_beta^{-1})
```

where `K_beta` is block tridiagonal. Sampling and VB updates should solve
linear systems from sparse Cholesky factors rather than explicitly inverting.

## Intercept Block

The intercept block should be ordered separately from `beta_k`.

Recommended first sampler:

- Gaussian conditional for unconstrained `alpha` from the stacked likelihood;
- one-coordinate Gibbs updates from truncated normal conditionals with bounds
  `alpha_{k-1} < alpha_k < alpha_{k+1}`;
- diffuse prior on `alpha_1` and positive increments, or an equivalent order
  cone prior.

This encourages noncrossing through ordered baselines and fused slopes, but it
does not guarantee global noncrossing for all feature values. Crossing
diagnostics and post hoc synthesis remain required.

## RHS_NS Adaptation

Use the supplement's `rhs_ns` dialect, not a new horseshoe dialect. For each
coefficient block value `theta_j` in either `beta_1` or an innovation
`Delta_k`, the effective prior precision is

```text
tau^{-2} * lambda_j^{-2} + zeta^{-2}.
```

Conditional on the block values, the same inverse-gamma updates used in the
supplement apply blockwise:

- local scales for each feature;
- auxiliary local scales;
- block global scale;
- auxiliary global scale;
- optional slab scale `zeta^2`.

The fused blocks may have quantile-adaptive global scales `tau_delta_k`, while
the anchor block has its own `tau_base`. Intercepts are not included in these
RHS updates.

## MCMC Plan

One iteration should update:

1. `v_{k,t}` from the AL/exAL GIG full conditionals using residuals
   `y_t - alpha_k - z_t' beta_k`.
2. `s_{k,t}` for exAL from truncated-normal full conditionals.
3. stacked `beta` from the sparse Gaussian QVP block above.
4. RHS_NS scales for `beta_1` and each fused innovation block.
5. ordered intercepts `alpha_k`.
6. `sigma_k`, and for exAL `gamma_k`, using the existing scale/asymmetry
   kernels or a Metropolis/Laplace proposal on transformed coordinates.

The implementation should support shared or quantile-specific
`sigma_k/gamma_k`, but the first prototype should use quantile-specific
parameters to match independent single-quantile fits.

## VB/VB-LD Plan

Use a mean-field family that keeps the coefficient curve coupled:

```text
q(beta) *
q(alpha) *
prod_k q(sigma_k, gamma_k) *
prod_{k,t} q(v_{k,t}) q(s_{k,t}) *
prod_blocks q(RHS_NS scales).
```

The `q(beta)` factor is one multivariate Gaussian with sparse QVP precision.
The latent GIG and truncated-normal factors reuse the supplement's moment
forms with residual moments computed under `q(beta)` and `q(alpha)`.
The exAL scale/asymmetry block remains nonconjugate and should use the current
Laplace-Delta treatment per quantile. The ELBO is the existing complete-data
ELBO summed over quantiles with weight `kappa`, plus QVP/RHS prior terms and
minus the entropy of the coupled `q(beta)` and ordered-intercept approximation.

## Repo-Native Implementation Plan

Start with documentation and tiny prototypes before touching manuscript
claims.

Recommended files:

- `application/R/joint_qvp_qdesn.R` for prototype helpers only after the
  derivation checklist is complete.
- `application/tests/test_joint_qvp_qdesn.R` for synthetic and algebra tests.
- `docs/implementation_notes/joint_exal_qvp_qdesn_rhs_derivation_checklist_YYYYMMDD.md`
  before implementation.
- optional standalone `qdesn-supplement-joint-qvp-extension.tex`, not included
  from `main.tex` until requested.

Initial helper scope:

- build sorted quantile grid metadata;
- build sparse `H` and `P_beta` operators;
- build stacked exAL working rows;
- compute crossing diagnostics before and after synthesis;
- expose `kappa` in every fit object and manifest;
- provide a tiny AL-only MCMC or VB smoke path before exAL.

Do not change the final TT500 builder, GloFAS current aliases, PriceFM Stage M
aliases, or manuscript text as part of the first prototype.

## Test Plan

Required tests before any application use:

- `K = 1` gives the current single-quantile slope prior and design dimensions.
- `H beta` returns `(beta_1, beta_2 - beta_1, ..., beta_K - beta_{K-1})`.
- Sparse precision equals dense reference on a tiny toy example.
- Larger fused shrinkage reduces adjacent coefficient variation.
- Subunit `kappa` scales the complete-data augmented likelihood precision and
  ELBO contributions, but the calibrated AL validation lane uses `kappa = 1`.
- Ordered intercept updates respect monotonicity.
- Crossing diagnostics can still detect feature-induced crossings.
- Post hoc synthesis remains available and explicit.
- AL-only joint prototype passes before exAL/VB-LD is enabled.

Only after those tests pass should GloFAS or PriceFM be considered as
downstream stress tests.

## Citation Gaps

`refs.bib` currently contains the article's existing AL/exAL/RHS/isotonic and
rearrangement references, but the audit did not find QVP, Bissiri general
Bayes, Bondell-Reich-Wang noncrossing Bayesian quantile regression, or the
QVP-adjacent fused composite-quantile references. Add those BibTeX entries
only when a tracked extension draft cites them.
