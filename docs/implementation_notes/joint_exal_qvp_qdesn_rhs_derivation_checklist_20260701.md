# Joint exAL-QVP-QDESN-RHS Derivation And Test Checklist

Date: 2026-07-01
Status: derivation audit checklist; no implementation should depend on an
unchecked expression.

Implementation status on 2026-07-01: the algebra layer, tiny AL-MCMC and
exAL-MCMC reference samplers, first AL-VB and exAL-VB/VB-LD prototypes, an
AL-VB objective stress harness, and a VB-initialized AL-MCMC calibration
harness are
implemented in
`application/R/joint_qvp_qdesn.R`, with targeted tests in
`application/tests/test_joint_qvp_qdesn_algebra.R`,
`application/tests/test_joint_qvp_qdesn_al_mcmc.R`,
`application/tests/test_joint_qvp_qdesn_al_vb.R`, and
`application/tests/test_joint_qvp_qdesn_exal_mcmc.R`,
`application/tests/test_joint_qvp_qdesn_exal_vb.R`,
`application/tests/test_joint_qvp_qdesn_synthetic_validation.R`,
`application/tests/test_joint_qvp_qdesn_synthetic_artifacts.R`, and
`application/tests/test_joint_qvp_qdesn_objective_stress.R`,
`application/tests/test_joint_qvp_qdesn_mcmc_calibration.R`. The AL and exAL
paths support arbitrary positive `kappa` under the complete-data powered target
documented below.

This checklist is the tracked theory gate for the joint multi-quantile
exAL-QVP-QDESN-RHS extension. It complements the repo-native model plan in
`docs/implementation_notes/joint_exal_qvp_qdesn_rhs_model_plan_20260630.md`
and the ignored operational tracker in
`local_trackers/joint_exal_qvp_qdesn_rhs/`.

The current article evidence remains the existing single-quantile Q-DESN model
with post hoc synthesis. This checklist is for new extension work only.

Current next gate: decide whether the wide-grid VB/MCMC distance gap is an
acceptable review threshold or requires a VB/model update before broader
synthetic validation. The first validation stage uses VB because it is faster,
then initializes MCMC from the VB state for regression/reference checks.
Mean-field RHS scale updates, storage-light synthetic artifacts, `K = 1` smoke
coverage, repeated-run artifact hash checks, a six-case AL-VB objective stress
matrix, a six-case VB-initialized AL-MCMC calibration run, and a dedicated
wide-grid multi-chain MCMC reference are implemented for the tiny path. After
calibrated stress controls, the default stress matrix has six implementation
passes, six convergence passes, six accounted-objective monotonicity passes
with `max_drop = 0`, and zero fitted crossing pairs. The default MCMC
calibration now uses matched finite-mean `IG(2, 1)` sigma priors in VB and MCMC
and a broad `50 * max(sigma_VB)` guardrail. It has six implementation passes,
six reference-bound passes, zero fitted crossing pairs, five distance passes,
and one distance-review row for the wide three-quantile grid. The wide-grid
multi-chain reference has four chains, 60 pooled retained draws, no sigma
bound hits, no crossings, stable chain-to-pooled spread, and a pooled
normalized VB/MCMC distance of `7.008`, so it remains threshold-review. AL-VB
now exports explicit partial-ELBO term accounting with missing full-ELBO pieces
labeled; GIG `E[log v]`/entropy and RHS mean-field scale prior/entropy terms
are implemented for AL-VB. Exact RHS log-precision accounting, point-intercept
entropy, production sparse scaling, and statistical agreement thresholds remain
open.

Threshold policy note: `docs/implementation_notes/joint_qvp_validation_threshold_policy_20260701.md`
audits the current repo validation conventions and records the joint-QVP
pass/review/fail policy used in the synthetic artifacts.

## Audit Rules

- [ ] Every expression has declared dimensions.
- [ ] Every conditional distribution names its conditioning set.
- [ ] Every reduction case is checked before code.
- [ ] Every approximation is labeled as exact, Laplace, Delta, or numerical.
- [ ] Every derivation section maps to implementation helpers and tests.
- [ ] No manuscript claim is added before implementation and validation exist.

## Notation Registry

Core dimensions:

- [ ] `T`: number of post-washout training observations.
- [ ] `K`: number of fitted quantile levels.
- [ ] `p`: number of non-intercept fixed Q-DESN readout features.
- [ ] `tau_1 < ... < tau_K`: fitted quantile grid.
- [ ] `z_t in R^p`: non-intercept fixed DESN feature vector.
- [ ] `Z in R^{T x p}`: fixed non-intercept design matrix.
- [ ] `alpha_k`: quantile-specific intercept.
- [ ] `beta_k in R^p`: quantile-specific readout slopes.
- [ ] `Delta_k = beta_k - beta_{k-1}` for `k = 2,...,K`.
- [ ] `sigma_k > 0`: quantile-specific working scale.
- [ ] `gamma_k`: exAL asymmetry parameter with support depending on `tau_k`.
- [ ] `v_{k,t} > 0`: AL/exAL scale-mixture latent variable.
- [ ] `s_{k,t} > 0`: exAL positive-shift latent variable.
- [ ] `kappa > 0`: composite/general-Bayes learning rate.

Stacking convention:

- [ ] `beta = (beta_1', ..., beta_K')' in R^{Kp}`.
- [ ] `alpha = (alpha_1, ..., alpha_K)' in R^K`.
- [ ] `y_stack = (y_1,...,y_T, ..., y_1,...,y_T)' in R^{KT}`.
- [ ] `Z_stack = I_K kron Z in R^{KT x Kp}`.
- [ ] `H beta = (beta_1', Delta_2', ..., Delta_K')'`.

## Source Reconciliation

Current article/supplement expressions to preserve:

- [ ] exAL constants `A(gamma)`, `B(gamma)`, `C(gamma)`,
  `lambda(gamma) = C(gamma) |gamma|`.
- [ ] Supplement shorthand `D_gamma` reconciled with `lambda(gamma)`.
- [ ] AL special case constants.
- [ ] Single-quantile Gaussian beta block.
- [ ] GIG latent `v_t` update.
- [ ] exAL truncated-normal `s_t` update.
- [ ] `rhs_ns` inverse-gamma local/global/slab updates.
- [ ] VB/VB-LD factorization and ELBO decomposition.

Required source checks:

- [ ] Main text single-quantile model section read.
- [ ] Supplement single-quantile MCMC section read.
- [ ] Supplement `rhs_ns` section read.
- [ ] Supplement VB/VB-LD section read.
- [ ] Application AL-VB limitations read.
- [ ] Existing synthesis diagnostics read.

## 1. Joint Working Likelihood

Target expression:

```text
q_{k,t} = alpha_k + z_t' beta_k
```

For AL:

```text
y_t | beta_k, alpha_k, sigma_k, v_{k,t}
  ~ Normal(q_{k,t} + A_k v_{k,t}, B_k sigma_k v_{k,t})
v_{k,t} | sigma_k ~ Exp(rate = 1 / sigma_k)
```

For exAL:

```text
y_t | beta_k, alpha_k, sigma_k, gamma_k, s_{k,t}, v_{k,t}
  ~ Normal(q_{k,t} + lambda_k sigma_k s_{k,t} + A_k v_{k,t},
           B_k sigma_k v_{k,t})
v_{k,t} | sigma_k ~ Exp(rate = 1 / sigma_k)
s_{k,t} ~ TN(0, 1)
```

Audit items:

- [ ] Confirm `q_{k,t}` is the target `tau_k` conditional quantile.
- [ ] Confirm AL constants are functions of `tau_k`.
- [ ] Confirm exAL constants are functions of `(tau_k, gamma_k)`.
- [ ] Confirm latent variables do not change the marginal quantile target.
- [ ] Write complete-data log likelihood for AL.
- [ ] Write complete-data log likelihood for exAL.
- [ ] Apply composite weight `kappa` consistently.
- [ ] Check whether latent priors should be raised to `kappa` in the chosen
  general-Bayes target, and document the decision.
- [x] Decision for the prototype sampler: use a complete-data powered target.
  For each `(k,t)`, raise the Gaussian AL/exAL conditional density and the
  corresponding augmentation density to `kappa`; leave model priors
  unweighted. This is a computational general-Bayes target for the augmented
  posterior and is recorded in fit manifests through `kappa`.
- [x] Derive the generic AL `kappa != 1` latent `v_{k,t}` conditional. If
  `r_{k,t}=y_t-alpha_k-z_t'beta_k`, then

```text
v_{k,t} | ... ~ GIG(lambda_v, chi_v, psi_v)
lambda_v = 1 - kappa / 2
chi_v = kappa * r_{k,t}^2 / (B_k sigma_k)
psi_v = kappa * (A_k^2 / (B_k sigma_k) + 2 / sigma_k)
```

  This reduces to the supplement's `GIG(1/2, chi, psi)` update when
  `kappa = 1`.
- [ ] Verify normal variance is positive for all valid states.

Reduction checks:

- [ ] exAL with AL special-case constants recovers AL expression.
- [ ] `K = 1` recovers the current single-quantile likelihood.
- [ ] `kappa = 1` recovers the unweighted product working likelihood.

Tests implied:

- [ ] Hand-computed AL working response on a toy example.
- [ ] Hand-computed exAL working response on a toy example.
- [ ] Invalid `sigma_k`, `v_{k,t}`, or `gamma_k` fails loudly.

## 2. Composite/General-Bayes Scaling

Audit items:

- [ ] Define target posterior proportional to weighted complete-data target
  times priors.
- [x] Prototype target: weighted complete-data AL/exAL augmentation terms times
  unweighted priors. This keeps the beta/alpha weighted least-squares blocks
  coherent with the latent-variable updates.
- [x] Decide default `kappa = 1` for the AL validation lane after the 2026-07-02
  extreme-tail audit.
- [ ] State that `kappa` is a learning-rate choice, not a probability model
  correction.
- [ ] Confirm coefficient precision receives likelihood contribution scaled by
  `kappa`.
- [x] In the implemented AL prototype, beta and alpha likelihood precisions use
  weights `kappa / (B_k sigma_k v_{k,t})`.
- [ ] Confirm ELBO likelihood and latent terms receive the same documented
  scaling.
- [ ] Confirm runtime manifests record `kappa`.

Reduction checks:

- [ ] If `K` changes while data are fixed, subunit `kappa` can keep total
  augmented-target observation weight approximately stable, but this is now a
  stress-diagnostic convention unless a marginal-safe derivation is added.
- [ ] `kappa` does not scale prior terms unless explicitly chosen and justified.
- [x] Current prototype leaves priors unweighted.

Tests implied:

- [ ] Doubling `K` with duplicated quantile constants and subunit `kappa` leaves
  augmented-target precision stable in a controlled toy case; do not treat this
  as the default observed-likelihood target.
- [ ] Invalid `kappa <= 0` fails.

## 3. QVP Difference Prior

Target definitions:

```text
eta = H beta = (beta_1', Delta_2', ..., Delta_K')'
P_delta = blockdiag(P_1, P_Delta_2, ..., P_Delta_K)
P_beta = H' P_delta H
```

Audit items:

- [ ] Define `H` explicitly for `K = 1`.
- [ ] Define `H` explicitly for `K = 2`.
- [ ] Define general block first-difference matrix.
- [ ] Verify `H` is square and nonsingular.
- [ ] Verify `P_beta` is block tridiagonal.
- [ ] Verify dimensions of each `P_Delta_k`.
- [ ] Verify `P_beta` is positive definite if all block precisions are positive
  definite.
- [ ] Decide whether `tau_delta_k` is quantile-adaptive by default.
- [ ] Keep intercepts outside `H`.

Reduction checks:

- [ ] `K = 1`: `H = I_p`, `P_beta = P_1`.
- [ ] Weak fusion: `P_Delta_k -> 0` approximates independent slopes.
- [ ] Strong fusion: `P_Delta_k -> infinity` approximates common slopes.

Tests implied:

- [ ] `H beta` equals manual differences.
- [ ] `P_beta` equals dense reference for tiny `K, p`.
- [ ] Sparse symmetry and positive-definiteness tests pass.

## 4. RHS_NS Blocks

Target precision for a generic block coefficient `theta_j`:

```text
precision_j = tau^{-2} lambda_j^{-2} + zeta^{-2}
```

Audit items:

- [ ] Reconcile notation with the supplement's `lambda_j`, `nu_j`, `tau`,
  `xi`, and `zeta`.
- [ ] Derive local-scale update for anchor block `beta_1`.
- [ ] Derive global-scale update for anchor block `beta_1`.
- [ ] Derive slab-scale update for anchor block `beta_1`.
- [ ] Derive local-scale update for each innovation block `Delta_k`.
- [ ] Derive global-scale update for each innovation block `Delta_k`.
- [ ] Derive slab-scale update for each innovation block `Delta_k`.
- [ ] Confirm intercepts are excluded.
- [ ] Confirm all shape/rate parameters are positive.

Reduction checks:

- [ ] `K = 1` gives the current single-quantile `rhs_ns` update.
- [ ] Fixed slab omits `q(zeta^2)` or its MCMC update.

Tests implied:

- [ ] RHS update input builder returns expected sufficient statistics.
- [ ] Positive scale checks.
- [ ] Anchor and innovation blocks are kept distinct in manifests.

## 5. Coefficient Conditional

Target working response:

```text
y_star_{k,t} = y_t - alpha_k
               - lambda_k sigma_k s_{k,t}
               - A_k v_{k,t}
w_{k,t} = kappa / (B_k sigma_k v_{k,t})
```

For AL, omit the `lambda_k sigma_k s_{k,t}` term.

Target Gaussian block:

```text
K_beta = Z_stack' W Z_stack + P_beta
m_beta = K_beta^{-1} (Z_stack' W y_star)
beta | ... ~ Normal(m_beta, K_beta^{-1})
```

Audit items:

- [ ] Verify `Z_stack' W Z_stack` dimensions.
- [ ] Verify `Z_stack' W y_star` dimensions.
- [ ] Verify prior mean is zero for non-intercept slopes.
- [ ] Decide whether an optional nonzero prior mean is needed later.
- [ ] Confirm `K_beta` is sparse block tridiagonal plus block-diagonal
  likelihood terms.
- [ ] State solve method: sparse Cholesky or sparse linear solver.
- [x] For MCMC, specify draw generation from precision Cholesky. The
  implementation uses dense precision Cholesky only below a configured tiny
  threshold, and otherwise samples with Matrix/CHOLMOD sparse Cholesky using
  the expanded permutation and triangular factor.
- [ ] For VB, specify coupled Gaussian `q(beta)`.

Reduction checks:

- [ ] `K = 1` equals single-quantile beta conditional without intercept column.
- [ ] If intercept is folded back into design, expression matches the old form.

Tests implied:

- [ ] Sparse solve equals dense solve on tiny toy data.
- [ ] Coefficient update returns finite values.
- [ ] No direct matrix inverse in production helper.

## 6. Ordered Intercepts

Target constraint:

```text
alpha_1 < alpha_2 < ... < alpha_K
```

Audit items:

- [ ] Choose strict or weak ordering for numerical implementation.
- [ ] Define prior on `alpha_1` and increments, or an order-cone prior.
- [ ] Derive conditional Gaussian likelihood contribution for each
  `alpha_k`.
- [ ] Derive truncated-normal Gibbs update for each `alpha_k`.
- [ ] Define boundary behavior for `k = 1` and `k = K`.
- [ ] Define minimum spacing tolerance if needed.
- [ ] State clearly that ordered intercepts do not guarantee global
  noncrossing with varying `z_t' beta_k`.

Reduction checks:

- [ ] `K = 1` gives unconstrained single intercept.
- [ ] If `z_t = 0`, ordered intercepts imply noncrossing.

Tests implied:

- [ ] Ordered intercept sampler respects bounds.
- [ ] Crossing diagnostics still detect slope-induced crossing.

## 7. Latent Variable Blocks

AL `v_{k,t}`:

- [x] Derive `chi_{k,t}`:
  `chi_{k,t} = kappa * r_{k,t}^2 / (B_k sigma_k)`.
- [x] Derive `psi_{k,t}`:
  `psi_{k,t} = kappa * (A_k^2 / (B_k sigma_k) + 2 / sigma_k)`.
- [x] Confirm GIG parameterization matches supplement when `kappa = 1`, with
  general shape `lambda_v = 1 - kappa / 2`.
- [x] Implemented sampler uses a log-scale slice sampler for the general GIG
  update, including the `lambda_v = 1/2` case, avoiding a new package
  dependency and keeping the prototype numerically stable.

exAL `v_{k,t}` and `s_{k,t}`:

- [x] Derive exAL residual without `A_k v_{k,t}` for `v` update. With
  `r_{k,t}=y_t-alpha_k-z_t'beta_k`, use
  `delta_{k,t}=r_{k,t}-lambda_k sigma_k s_{k,t}`.
- [x] Derive `chi_{k,t}` and `psi_{k,t}`:

```text
chi_v = kappa * delta_{k,t}^2 / (B_k sigma_k)
psi_v = kappa * (A_k^2 / (B_k sigma_k) + 2 / sigma_k)
lambda_v = 1 - kappa / 2
```

- [x] Derive truncated-normal precision for `s_{k,t}` under the powered
  complete-data target:

```text
prec_s = kappa * (1 + sigma_k lambda_k^2 / (B_k v_{k,t}))
```

- [x] Derive truncated-normal mean for `s_{k,t}`:

```text
mean_s = lambda_k * (r_{k,t} - A_k v_{k,t}) /
         (B_k v_{k,t} + sigma_k lambda_k^2)
```

- [x] Confirm all parameters are finite and valid in targeted tests.

Reduction checks:

- [ ] exAL latent blocks reduce to current supplement expressions when `K = 1`
  and `kappa = 1`.

Tests implied:

- [ ] GIG parameter positivity.
- [ ] Truncated-normal support.
- [ ] Hand-computed toy updates.

## 8. Scale And Asymmetry Blocks

AL scale:

- [x] Derive `sigma_k` inverse-gamma update under the complete-data powered
  target:

```text
sigma_k | ... ~ IG(a_sigma + 3 kappa T / 2,
                   b_sigma + kappa * [sum_t v_{k,t}
                     + 1/2 sum_t {(r_{k,t} - A_k v_{k,t})^2 / (B_k v_{k,t})}])
```

- [x] Include `kappa` in shape/rate terms consistently.
- [x] Check `K = 1`, `kappa = 1` reduction to the supplement's AL update.

exAL scale/asymmetry:

- [x] Write conditional scale kernel for `sigma_k`. Under the powered
  complete-data target,

```text
sigma_k | ... ~ GIG(lambda_sigma, chi_sigma, psi_sigma)
lambda_sigma = -a_sigma - 3 kappa T / 2
chi_sigma = 2 b_sigma + 2 kappa sum_t v_{k,t}
            + kappa sum_t {(r_{k,t} - A_k v_{k,t})^2 / (B_k v_{k,t})}
psi_sigma = kappa sum_t {lambda_k^2 s_{k,t}^2 / (B_k v_{k,t})}
```

- [x] Define support bounds for `gamma_k` using the exAL support implied by
  `tau_k`.
- [x] Define bounded slice update for `gamma_k` with a uniform support prior.
- [x] State exact vs approximate parts: the prototype uses exact univariate
  slice transitions for the GIG-form scale draw and the bounded gamma kernel,
  up to numerical slice-sampling tolerance.
- [x] Confirm per-quantile independence conditional on other blocks in the
  prototype.

Tests implied:

- [ ] AL sigma update finite and positive.
- [ ] exAL kernel finite on valid inputs.
- [ ] invalid gamma rejected.
- [ ] transformed-coordinate round trip.

## 9. VB/VB-LD Factorization

Target factorization:

```text
q(beta) q(alpha)
prod_k q(sigma_k, gamma_k)
prod_{k,t} q(v_{k,t}) q(s_{k,t})
prod_blocks q(rhs_ns scales)
```

Audit items:

- [x] Confirm `q(beta)` remains coupled across quantiles.
- [x] Decide approximate form for `q(alpha)` under ordering.
- [x] Derive AL `q(v)` update.
- [x] Derive AL `q(sigma)` update.
- [x] Derive exAL `q(v)` update with Laplace-Delta moments.
- [x] Derive exAL `q(s)` update.
- [ ] Derive `q(sigma_k, gamma_k)` Laplace approximation.
- [x] Derive RHS_NS variational updates for all blocks.
- [x] Define convergence criterion.
- [x] Define failure status.

Implemented AL-VB status:

- [x] First AL-VB prototype uses coupled dense Gaussian `q(beta)` for tiny
  validation cases.
- [x] Ordered intercepts are handled as point updates projected into the order
  cone.
- [x] AL latent `v` moments use GIG Bessel-ratio moments with deterministic
  log-scale numerical fallback.
- [x] AL scale factors use inverse-gamma variational moments.
- [x] AL-MCMC accepts the VB fit object as initialization through the shared
  init-normalization path.
- [x] First exAL-VB/VB-LD prototype uses point `gamma`, GIG `sigma` moments,
  truncated-normal `s` moments, and an approximate coordinate monitor.
- [x] exAL-MCMC accepts the VB/VB-LD fit object as initialization through the
  shared init-normalization path.
- [x] Mean-field RHS_NS local/global/slab scale updates are implemented for the
  anchor and all innovation blocks in the tiny VB prototypes.
- [ ] Full Laplace covariance for joint `q(sigma_k, gamma_k)` is not yet
  implemented.

RHS mean-field update implemented for each block:

```text
m_j = E(theta_j^2)
E(1/lambda_j^2) = 1 / { E(1/nu_j) + 0.5 m_j E(1/tau^2) }
E(1/nu_j) = 1 / { 1 + E(1/lambda_j^2) }
E(1/tau^2) = (p/2) / { E(1/xi) + 0.5 sum_j m_j E(1/lambda_j^2) }
E(1/xi) = 1 / { tau0^{-2} + E(1/tau^2) }
E(1/zeta^2) = (a_zeta + p/2) / { b_zeta + 0.5 sum_j m_j }
```

Reduction checks:

- [x] `K = 1` reduces to single-quantile VB dimensions.
- [ ] AL omits `q(s)` and `q(gamma)`.

Tests implied:

- [x] finite variational moments.
- [x] finite covariance.
- [x] AL-VB accounted objective monotonicity within tolerance on current tiny
  synthetic validation cases.
- [x] AL-VB accounted objective monotonicity within tolerance on the default
  six-case stress matrix.
- [x] exAL monitored objective labeled approximate.
- [x] RHS prior summaries are finite and hash-artifacted in synthetic smoke
  validation.
- [x] VB-to-MCMC reference distances are recorded in the synthetic artifact
  summary.
- [x] Validation assessment records implementation, distance, convergence, and
  overall gate status per unique synthetic `case_id`.
- [x] VB-initialized AL-MCMC calibration artifacts record normalized distances,
  draw summaries, sigma-bound hit fractions, and threshold-review status per
  unique stress `case_id`.

## 10. ELBO

Required terms:

- [x] weighted expected log likelihood monitor term;
- [x] weighted latent `v` prior monitor term if included in weighted target;
- [x] weighted latent `s` prior monitor term if included in weighted target;
- [x] QVP slope prior monitor term;
- [x] RHS_NS scale prior and entropy terms under the implemented mean-field
  convention;
- [ ] intercept prior or constraint term;
- [x] AL scale prior and `q(sigma)` entropy terms in partial accounting;
- [ ] gamma prior/support term;
- [x] entropy/log-determinant monitor for `q(beta)`;
- [ ] entropy or approximation for `q(alpha)`;
- [x] AL entropy of latent GIG factors;
- [ ] entropy of scale/asymmetry approximation;
- [x] entropy of RHS_NS factors under the implemented mean-field convention.

Audit items:

- [x] Decide and document which AL augmented terms receive `kappa` in the
  partial accounting.
- [x] Check constants retained or intentionally dropped for monitoring.
- [x] Ensure comparisons use the same monitor convention.
- [x] Label exAL Laplace-Delta monitor as approximate.
- [x] Add AL GIG log-normalizer, `E[log v]`, and entropy accounting.
- [x] Add RHS mean-field scale-prior, scale-entropy, and approximate
  log-precision accounting.
- [x] Add objective monotonicity diagnostics with explicit approximation status.

Tests implied:

- [x] monitor finite on toy state.
- [x] monitor term names stable in output.
- [x] GIG log-normalizer, `E[log v]`, and entropy helpers return finite values
  under the AL parameterization.
- [x] RHS mean-field accounting terms return finite block-level values.
- [x] AL-VB included partial-ELBO terms are finite and missing full-ELBO terms
  are marked as excluded/statused in the output.
- [x] AL-VB accounted objective is nondecreasing within tolerance on toy and
  synthetic artifact tests.
- [x] AL-VB accounted objective is nondecreasing within tolerance on the
  default objective stress matrix.
- [x] synthetic artifact bundle exports hash-pinned `elbo_terms.csv`.
- [ ] Missing or NaN included terms fail convergence rather than stopping the
  prototype.

## 11. Posterior Prediction And Synthesis

Audit items:

- [ ] Define fitted quantile summary `q_{k,t}`.
- [ ] Define forecast design construction for fixed-design synthetic tests.
- [ ] Define draw-level prediction for MCMC.
- [ ] Define variational predictive summaries for VB.
- [ ] Define crossing diagnostics before synthesis.
- [ ] Reuse existing isotonic/rearrangement synthesis helpers where possible.
- [ ] State that synthesis is still post-processing unless exact noncrossing is
  imposed by the model.

Tests implied:

- [ ] monotone constant case remains monotone.
- [ ] crossing case is detected.
- [ ] synthesis repairs finite grid crossings.
- [ ] synthesis output schema matches existing helper expectations.

## 12. Implementation Mapping

Potential new R helpers:

- [x] `app_joint_qvp_validate_tau_grid()`
- [x] `app_joint_qvp_build_difference_matrix()`
- [x] `app_joint_qvp_apply_difference()`
- [x] `app_joint_qvp_build_stacked_design()`
- [x] `app_joint_qvp_build_prior_precision()`
- [x] `app_joint_qvp_build_working_response()`
- [x] `app_joint_qvp_crossing_diagnostics()`
- [x] `app_joint_qvp_update_rhs_vb_state()`
- [x] `app_joint_qvp_parse_tau_spec()`
- [x] `app_joint_qvp_default_validation_thresholds()`
- [x] `app_joint_qvp_assess_synthetic_validation()`
- [x] `app_joint_qvp_fit_al_mcmc_tiny()`
- [x] `app_joint_qvp_fit_exal_mcmc_tiny()`
- [x] `app_joint_qvp_fit_al_vb_tiny()`
- [x] `app_joint_qvp_fit_exal_vb_ld_tiny()`
- [x] `app_joint_qvp_simulate_synthetic()`
- [x] `app_joint_qvp_run_synthetic_vb_validation()`
- [x] `app_joint_qvp_manifest_row()`
- [x] `app_joint_qvp_al_vb_data_accounting()`
- [x] `app_joint_qvp_al_vb_partial_elbo_terms()`
- [x] `app_joint_qvp_partial_elbo()`
- [x] `app_joint_qvp_gig_log_integral()`
- [x] `app_joint_qvp_gig_log_moment()`
- [x] `app_joint_qvp_gig_entropy()`
- [x] `app_joint_qvp_rhs_vb_block_accounting()`
- [x] `app_joint_qvp_rhs_vb_elbo_terms()`
- [x] `app_joint_qvp_objective_diagnostics()`
- [x] `app_joint_qvp_default_objective_stress_scenarios()`
- [x] `app_joint_qvp_default_objective_stress_thresholds()`
- [x] `app_joint_qvp_assess_objective_stress()`
- [x] `app_joint_qvp_run_al_vb_objective_stress()`
- [x] `app_joint_qvp_default_mcmc_calibration_thresholds()`
- [x] `app_joint_qvp_mcmc_draw_summary()`
- [x] `app_joint_qvp_vb_mcmc_distance_summary()`
- [x] `app_joint_qvp_assess_mcmc_calibration()`
- [x] `app_joint_qvp_run_al_vb_mcmc_calibration()`
- [x] `app_joint_qvp_default_wide_multichain_scenarios()`
- [x] `app_joint_qvp_default_multichain_thresholds()`
- [x] `app_joint_qvp_pool_mcmc_chains()`
- [x] `app_joint_qvp_chain_to_pooled_summary()`
- [x] `app_joint_qvp_assess_multichain_reference()`
- [x] `app_joint_qvp_run_wide_multichain_mcmc_calibration()`

Potential tests:

- [x] `application/tests/test_joint_qvp_qdesn_algebra.R`
- [x] `application/tests/test_joint_qvp_qdesn_al_mcmc.R`
- [x] `application/tests/test_joint_qvp_qdesn_al_vb.R`
- [x] `application/tests/test_joint_qvp_qdesn_exal_mcmc.R`
- [x] `application/tests/test_joint_qvp_qdesn_exal_vb.R`
- [x] `application/tests/test_joint_qvp_qdesn_synthetic_validation.R`
- [x] `application/tests/test_joint_qvp_qdesn_synthetic_artifacts.R`
- [x] `application/tests/test_joint_qvp_qdesn_objective_stress.R`
- [x] `application/tests/test_joint_qvp_qdesn_mcmc_calibration.R`
- [x] `application/tests/test_joint_qvp_qdesn_multichain_calibration.R`
- [x] repeated-run artifact reproducibility coverage in
  `application/tests/test_joint_qvp_qdesn_synthetic_artifacts.R`
- [x] AL-VB partial-ELBO accounting coverage in
  `application/tests/test_joint_qvp_qdesn_al_vb.R`
- [x] AL-VB objective stress matrix and repeated-run artifact coverage in
  `application/tests/test_joint_qvp_qdesn_objective_stress.R`
- [x] VB-initialized AL-MCMC calibration artifact and repeated-run coverage in
  `application/tests/test_joint_qvp_qdesn_mcmc_calibration.R`
- [x] Wide-grid multi-chain MCMC calibration artifact and repeated-run coverage
  in `application/tests/test_joint_qvp_qdesn_multichain_calibration.R`
- [ ] standalone `application/tests/test_joint_qvp_qdesn_reproducibility.R`

Integration check:

- [x] Add new tests to `application/tests/run_tests.R` only after helpers are
  implemented and deterministic.
- [x] Storage-light synthetic artifact manifest generated at
  `application/cache/joint_qvp_synthetic_vb_validation_20260701/artifact_manifest.csv`.
- [x] Artifact bundle includes `elbo_terms.csv` for AL-VB partial accounting.
- [x] Artifact bundle includes `objective_diagnostics.csv` with AL-VB
  monotonicity status and exAL approximate-monitor status.
- [x] Default synthetic artifact matrix includes `K = 1`, parallel slopes,
  slope variation, and crossing-pressure fixtures.
- [x] Default synthetic artifact assessment has no hard-fail gates; all current
  rows remain `review` because prototype VB runs hit `max_iter`.
- [x] Default AL-VB objective stress artifact matrix includes `K = 1`, wide
  quantile grids, high-noise slope variation, crossing pressure, and
  strong/weak RHS shrinkage fixtures.
- [x] Default AL-VB objective stress assessment has six implementation passes,
  six convergence passes, six objective monotonicity passes, zero fitted
  crossing pairs, and six overall passes after calibrated stress controls.
- [x] Storage-light objective stress artifact manifest generated at
  `application/cache/joint_qvp_al_vb_objective_stress_20260701/artifact_manifest.csv`.
- [x] Storage-light VB-initialized AL-MCMC calibration artifact manifest
  generated at
  `application/cache/joint_qvp_al_vb_mcmc_calibration_20260701/artifact_manifest.csv`.
- [x] Default VB-initialized AL-MCMC calibration assessment has six
  implementation passes, six reference-bound passes, zero fitted crossing
  pairs, five distance passes, and one wide-grid distance-review row under the
  current loose normalized-distance rule.
- [x] Storage-light wide-grid multi-chain calibration artifact manifest
  generated at
  `application/cache/joint_qvp_wide_multichain_mcmc_calibration_20260701/artifact_manifest.csv`.
- [x] Initial no-prior wide-grid multi-chain calibration assessment had
  implementation, reference-bound, and chain-stability passes, zero fitted
  crossing pairs, and a pooled-distance review row with
  `pooled_max_normalized_distance = 7.008`.
- [x] Alpha-gap audit confirmed that the no-prior wide-grid issue was
  ordered-intercept drift: `alpha_normalized_distance = 7.008`, max alpha gap
  `25.193`, and chain-spread pass `1.153`.
- [x] Added weak proper ordered-intercept prior controls to AL-VB and AL-MCMC:
  `alpha_prior_mean` and `alpha_prior_sd`, defaulting to the old no-prior
  behavior at the low-level fitter API through `alpha_prior_sd = Inf`.
- [x] Added alpha-gap audit helper and storage-light command:
  `app_joint_qvp_run_wide_alpha_gap_audit()` and
  `application/scripts/63_audit_joint_qvp_wide_alpha_gap.R`.
- [x] Added alpha-gap audit test:
  `application/tests/test_joint_qvp_qdesn_alpha_gap_audit.R`.
- [x] Storage-light alpha-gap audit artifact manifest generated at
  `application/cache/joint_qvp_wide_alpha_gap_audit_20260701/artifact_manifest.csv`.
- [x] Default wide-grid multi-chain calibration now uses documented finite
  reference controls: matched `IG(2, 1)` sigma priors and
  `alpha_prior_mean = empirical_quantile`, `alpha_prior_sd = 1`.
- [x] Regenerated default wide-grid multi-chain calibration assessment has
  implementation, reference-bound, chain-stability, and pooled-distance passes,
  zero fitted crossing pairs, zero sigma upper-bound hits, and
  `pooled_max_normalized_distance = 0.677`.
- [x] Added first closed-form time-series toy generator and artifact bundle:
  `app_joint_qvp_simulate_ts_toy_synthetic()`,
  `app_joint_qvp_run_ts_toy_synthetic()`, and
  `application/scripts/64_generate_joint_qvp_ts_toy_synthetic.R`.
- [x] The toy DGP has AR(1)/seasonal location-scale Student-t dynamics and
  exact conditional quantiles with known `alpha(tau)` and `beta(tau)`.
- [x] Added toy generator/artifact test:
  `application/tests/test_joint_qvp_qdesn_ts_toy_synthetic.R`.
- [x] Storage-light time-series toy artifact manifest generated at
  `application/cache/joint_qvp_ts_toy_synthetic_20260701/artifact_manifest.csv`.
- [x] Extended time-series toy innovations to standardized Gaussian,
  Student-t, and asymmetric-Laplace cases with analytic quantile functions.
- [x] Added toy fit-validation harness, command, and test:
  `app_joint_qvp_run_ts_toy_fit_validation()`,
  `application/scripts/65_run_joint_qvp_ts_toy_fit_validation.R`, and
  `application/tests/test_joint_qvp_qdesn_ts_toy_fit_validation.R`.
- [x] Storage-light toy fit-validation artifact manifest generated at
  `application/cache/joint_qvp_ts_toy_fit_validation_20260701/artifact_manifest.csv`.
- [x] Toy fit-validation artifacts include observed data, design, true
  quantiles, VB fit summaries, VB-initialized MCMC summaries, truth-distance
  summaries, readout-parameter truth comparisons, ELBO/objective diagnostics,
  MCMC draw summaries, crossing summaries, and diagnostic PNGs.
- [x] Added first time-series synthetic suite, command, and test:
  `app_joint_qvp_default_ts_synthetic_scenarios()`,
  `app_joint_qvp_run_ts_synthetic_suite()`,
  `application/scripts/66_generate_joint_qvp_ts_synthetic_suite.R`, and
  `application/tests/test_joint_qvp_qdesn_ts_synthetic_suite.R`.
- [x] Storage-light time-series synthetic suite artifact manifest generated at
  `application/cache/joint_qvp_ts_synthetic_suite_20260701/artifact_manifest.csv`.
- [x] Suite covers six truth-known cases across Gaussian, Student-t, and
  asymmetric-Laplace innovations, with zero true quantile crossings in the
  generated default artifact.
- [x] Added suite-wide time-series fit-validation helpers, command, and test:
  `app_joint_qvp_fit_ts_synthetic_scenario()`,
  `app_joint_qvp_assess_ts_suite_fit_validation()`,
  `app_joint_qvp_run_ts_suite_fit_validation()`,
  `application/scripts/67_run_joint_qvp_ts_suite_fit_validation.R`, and
  `application/tests/test_joint_qvp_qdesn_ts_suite_fit_validation.R`.
- [x] Storage-light suite fit-validation artifact manifest generated at
  `application/cache/joint_qvp_ts_suite_fit_validation_20260701/artifact_manifest.csv`.
- [x] Suite fit-validation hard implementation gates are clean: zero VB and
  pooled-MCMC fitted crossings, finite MCMC draw summaries, all MCMC chains
  initialized from VB, and zero sigma upper-bound hit fractions.
- [x] Suite fit-validation gates pass after the adaptive VB retry policy:
  all six cases pass implementation, objective, truth-distance, hit-rate, and
  VB/MCMC agreement gates.
- [x] Added repeated-seed threshold calibration helpers, command, and test:
  `app_joint_qvp_expand_ts_suite_calibration_scenarios()`,
  `app_joint_qvp_run_ts_suite_threshold_calibration()`,
  `application/scripts/68_calibrate_joint_qvp_ts_suite_thresholds.R`, and
  `application/tests/test_joint_qvp_qdesn_ts_suite_threshold_calibration.R`.
- [x] Storage-light threshold calibration artifact manifest generated at
  `application/cache/joint_qvp_ts_suite_threshold_calibration_20260701/artifact_manifest.csv`.
- [x] Repeated-seed calibration covers six scenarios over five seeds each with
  summary-only output by default.
- [x] Calibration hard implementation gates are clean across 30 fits: zero VB
  and pooled-MCMC crossings, zero sigma upper-bound hits, finite MCMC draw
  summaries, and VB-initialized chains throughout.
- [x] Calibration review evidence is explicit after adaptive VB retries: 29 of
  30 replicated fits pass, and the only remaining review is
  `ts_persistent_heavy_tail_rep02_seed20260702` reaching the 500-iteration cap
  despite passing objective, truth-distance, hit-rate, and VB/MCMC gates.
- [x] Added targeted deep-MCMC reference helpers, command, and test:
  `app_joint_qvp_select_ts_deep_mcmc_targets()`,
  `app_joint_qvp_run_ts_deep_mcmc_reference()`,
  `application/scripts/69_run_joint_qvp_ts_deep_mcmc_reference.R`, and
  `application/tests/test_joint_qvp_qdesn_ts_deep_mcmc_reference.R`.
- [x] Storage-light deep-MCMC reference artifact manifest generated at
  `application/cache/joint_qvp_ts_deep_mcmc_reference_20260701/artifact_manifest.csv`.
- [x] Deep-MCMC reference hard gates are clean for four selected review targets:
  zero VB and pooled-MCMC crossings, zero sigma upper-bound hits, finite MCMC
  draw summaries, and VB/MCMC agreement passes.
- [x] Deep-MCMC reference labels all four selected targets
  `deep_reference_stable`, and all four pass after adaptive VB retry.
- [x] QVP-focused tests pass after adding the suite fit-validation,
  repeated-seed calibration, and targeted deep-reference lanes.
- [ ] Full application tests still pass. Current run still stops at the known
  unrelated `isTRUE(engine_report$ok) is not TRUE` boundary.

## Final Pre-Implementation Gate

Implementation may begin only when:

- [ ] this checklist has no unchecked theory blockers;
- [ ] all unresolved choices are explicitly marked as implementation choices;
- [ ] the first code target is algebra-only;
- [ ] test names and expected failure behavior are written down;
- [ ] no current article validation or application alias needs to change.
