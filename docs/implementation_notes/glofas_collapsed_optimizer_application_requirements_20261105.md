# Application requirements for collapsed GloFAS parameter optimization

## Audited scope

This is a source and small-metadata audit for the new parameter optimizer,
not a model fit or an accuracy certificate. No original RDS was opened,
hashed or statted. Existing application results and article assets remain
unchanged. The explicit comparison specification is **preserve executed**:
reference/discrepancy input multipliers 0.5/0.35 and bias multipliers one,
with the authenticated reservoirs, histories, input scalers and feature order.
The different normalized screening multipliers are not substituted here.

The relevant application target is
`app_glofas_family_transition_contract()` in
`application/R/glofas_family_transition.R`: 28 future dates, all 51 issued
members at each date, one normalized same-family future-reference transition
per date, and ordinary unit member factors. Future USGS is excluded.
The conditioned weather record remains the frozen realized PRISM/ERA5
record; this stage cannot relabel it as issue-time weather forecasts.

### Exact application interfaces

| Role | Source and function/fields |
|---|---|
| Historical numerical target | `design$H_fixed`, `z_fixed`, `source_fixed`, `weight_fixed`, `beta_index`, `alpha_index`, `intercept_index`; `app_latent_fixed_block_design()` and `app_latent_normal_fixed_cache()` |
| Current independent priors | `latent_path_vb_al.R`: `app_latent_prior_state_init()`, `app_latent_rhs_state_init()`, `app_latent_rhs_prior_precision()`, `app_latent_rhs_state_update()` |
| Retained initial moments | AL/Normal `fit$variational_state`: `theta_mean`, `theta_cov`, `sigma`, `prior`, `y_future_mean`, `y_future_cov`; these are initialization information, not a new prior |
| Current source-specific exAL factors | `latent_path_vb_exal.R`: `app_latent_exal_scale_shape_update()`, `app_fit_latent_path_exal_vb_core()`; source names `Y`, `G` |
| MQ coefficient hierarchy | `glofas_part3_partitioned_rhs.R`: `app_glofas_part3_rhs_initialize()`, `app_glofas_part3_rhs_update()`, `app_glofas_part3_rhs_prior_terms()`; `latent_path_vb_joint.R`: `app_fit_latent_path_joint_vb_core()` |
| Retained nonlinear continuation | `latent_path_design.R`: `app_qdesn_compile_future_input_contract()`, `app_qdesn_continue_one_step()`, `app_qdesn_readout_row_from_states()`; `fit_qdesn_latent_path.R`: `app_make_latent_path_future_builder()` |
| Frozen-basis preflight | `scripts/diagnostics/glofas_specification_reconciliation.R`: `app_glofas_reconcile_specification()`, `app_glofas_bind_executed_replay()`, `app_glofas_assert_specification_basis()` |

The historical design has 12,455 Y rows and 12,455 G rows. Check these
counts and the stored row order, source labels and unit weights after any
newly admitted extraction; do not manufacture them from sample-size defaults.
`z_fixed` is the executed response coordinate, including any already-applied
known-baseline adjustment. Do not subtract that baseline again.

## 1. Full parameter inventory

The preserved readout has 1,501 reference coefficients and 1,001 discrepancy
coefficients, including one intercept in each block: 2,502 coefficients and
2,500 penalized slopes. Both components use the executed `rhs_ns` product
construction. The small retained field audit records learned slabs in both
components; the screening discrepancy entry with fixed slab 16 is not the
executed independent application prior.

For a component with r penalized slopes, retain these physical unknowns:

| Coordinates | Number | Treatment |
|---|---:|---|
| Intercept and slopes | r + 1 | Real-valued; intercept excluded from the horseshoe factors |
| Local variances `lambda2` and auxiliaries `nu` | 2r | Positive; one pair per penalized slope |
| Global variance `tau2` and auxiliary `xi` | 2 | Positive; `tau0` is a fixed hyperparameter, not this random global variance |
| Slab variance `zeta2` | 1 when learned | Positive; omit only when the destination prior explicitly fixes it |
| Source error scales | 2 per probability level | Positive, separate Y and G scales; not one common scale |
| exAL shapes | 2 per probability level | Separate Y/G shapes on the probability-specific open support |

Thus the full independent AL–RHS hierarchy has **7,510 physical coordinates**:
2,502 coefficients, 5,006 shrinkage/auxiliary coordinates and two AL scales.
Independent exAL adds two shapes, giving 7,512. Historical and future AL
augmentation variables need not be additional optimizer coordinates if their
integration is exact. Integrating out `nu` or `xi` is also permissible, but
requires the resulting exact marginal prior and an explicit conditional
reconstruction; fixing them at retained expectations is not that operation.

The inspected retained-field CSV confirms the median and lower-tail AL
settings `tau0` approximately 5.2043087e-5/0.0001159, `a_zeta=2`,
`b_zeta=4`, intercept precision 1e-9, `zeta2_fixed=NULL`,
`update_zeta=TRUE` and zero prior linear term. Its interpretation explicitly
says **checked fields only**, not a complete target identity. Obtain exact
hyperparameters from the newly bound destination configuration and prior
state; do not replace them by these rounded values or recalibrate them.
The retained reference is
`median_equations_v1/checked_prior_fields.csv` in the ignored fixed-target
diagnostic evidence. The tracked historical summaries are
`tables/glofas_search3_part1234_final_20261007_prior_settings.csv` and
`..._executed_prior_scalars.csv`; neither is a substitute for a new complete
configuration binding.

### Preserve the product prior, not only its Gaussian conditional variance

For each slope b_j, the implemented prior kernel contains both factors

```text
Normal(b_j; 0, tau2 * lambda2_j) * Normal(b_j; 0, zeta2).
lambda2_j | nu_j ~ IG(1/2, 1/nu_j),   nu_j ~ IG(1/2, 1).
tau2 | xi ~ IG(1/2, 1/xi),          xi ~ IG(1/2, 1/tau0^2).
zeta2 ~ IG(a_zeta, b_zeta) when learned.
intercept ~ Normal(0, 1/intercept_prec).
```

Use the inverse-gamma density with rate in the reciprocal variable:
`b^a/Gamma(a) * x^(-a-1) * exp(-b/x)`. Retain the Normal scale factors,
including the `tau2`, `lambda2` and `zeta2` logarithms. Replacing this product
by a normalized Normal with summed precision, while keeping unchanged
hyperpriors, removes a parameter-dependent factor and changes the target.
This distinction is consequential for direct parameter-density evaluation.
Constants depending only on fixed, authenticated hyperparameters may be
dropped for a within-task objective; parameter-dependent constants may not.

As an algebra check, the global inverse-gamma full conditional has shape
`(r+1)/2`, the local conditional shape is one, and the learned slab shape is
`a_zeta+r/2`. These are checks on the joint kernel, not additional density
terms to append to that kernel. The destination uses separate reference and
discrepancy shrinkage blocks. Intercepts are proper, zero-centered and not
centered at transferred VB starting values.

## 2. Historical density and collapsed future evidence

For independent AL at fixed probability p, the historical log target is

```text
log pi_H(eta) = log original_parameter_prior(eta)
  + sum over historical i [log p + log(1-p) - log sigma_source(i)
                           - rho_p(z_fixed[i] - H_fixed[i,] theta)
                             / sigma_source(i)].
```

This integrates each historical Normal–Exponential augmentation variable out.
It keeps the source-specific AL normalizer. The augmented conditional shape
`a+3n/2` in `app_latent_update_sigma()` must not be reused as an extra
marginal-density contribution. Independent scale priors come from
`vb_args$prior_sigma$a/b` for each source; inspected functions default to
2/1, but the native adapter must authenticate the destination values.

Normal methods require Normal **variances**, not AL scales; see
`app_latent_normal_sigma_update()` in `latent_path_vb_normal.R`.
Ridge coefficient precision and intercept precision must likewise come from
the destination contract. Reusing a Normal baseline is a separate complete
identity decision, not an implication of qualifying the AL optimizer.

For all parameters eta, let P_eta(Y_F) be the normalized causal future Y
law and L_G(Y_F,eta) all 1,428 issued member factors. The unchanged target is

```text
pi(eta | history, issued members) proportional to pi_H(eta) * Z_G(eta),
Z_G(eta) = integral P_eta(Y_F) L_G(Y_F,eta) dY_F.
```

No members means `Z_G=1` for every eta. With members, Z_G can update
coefficients, both error scales and shrinkage variables through their joint
posterior dependence. Holding the historical posterior fixed, or optimizing
only a future path at one retained parameter point, does not implement this
parameter target.

## 3. A finite-particle outer-score optimizer is a legitimate new method

Use unconstrained coordinates u: coefficients unchanged and logarithms of
positive variance/scale coordinates. Include the sum of those logarithms
as the parameter transformation Jacobian **once** in `log pi_H^u`.
Use `log q_phi(u)` in the same coordinates. Do not also apply a physical-
coordinate lognormal density to the same transformed factor.

If a positive unbiased particle estimate Zhat_N is produced conditionally on
u, a specified finite-N objective is

```text
L_N(phi) = E_(u~q_phi) E_(omega~K_u) [
  log pi_H^u(u) - log q_phi(u) + log Zhat_N(u,omega)].
```

Here the conditional particle law K_u must not depend on phi except through
u. An outer score-function gradient is then

```text
E [(log pi_H^u(u) - log q_phi(u) + log Zhat_N(u,omega) - baseline)
   * gradient_phi log q_phi(u)].
```

This route does not require a pathwise derivative through particle
resampling. It is not the fixed-path Fisher gradient of the exact log Z_G.
Use an independent or frozen baseline. A leave-one-out baseline is valid when
the remaining draws are independent of the omitted draw; with antithetic
pairs, omit the entire pair and use other independent pairs. Subtracting the
same batch average including an observation's own score is generally biased.
Respect antithetic or common-random-number pairing in uncertainty estimates.
A deterministic bank of inner draws is not interchangeable with the
expectation in L_N without an explicitly stated approximation.

For a diagonal Gaussian q on u, both mean and log-standard-deviation are
optimization parameters for every physical unknown: 15,020 variational
coordinates for the full AL hierarchy. A structured covariance is a separate
variational-family decision. Updating all coordinates does not establish
adequate covariance or tail accuracy. This is a different inference method
from the existing CAVI updates; name and freeze it separately.

Finite bounds on variational means/log standard deviations and explicit
iteration/particle budgets are legitimate optimization constraints. Clipping
physical draws, imposing unrecorded scale floors, freezing RHS coordinates,
or interpreting a failed particle evaluation as a finite objective value is
not legitimate target preservation. Since the particle Jensen gap depends
on eta, increasing N and checking parameter/path summaries is necessary even
if stochastic optimization converges. Ordinary acceptance or finite weights
does not resolve this approximation error.

The new generated-only `scripts/diagnostics/glofas_collapsed_al_target.R`
supplies a lower-variance historical route: `gcat_historical_elbo()` evaluates
the full historical ELBO and its derivatives analytically for a diagonal
Gaussian on these transformed coordinates. For a Gaussian readout with mean
m and variance v, its expected AL check loss is
`sqrt(v)*dnorm(a) + (z-m)*(p-pnorm(a, lower.tail=FALSE))`, where
`a=(z-m)/sqrt(v)`. Gaussian moment-generating functions give the remaining
NS and inverse-scale expectations. This callback already includes the
parameter Jacobian and entropy; the outer score term then concerns future
evidence only. Its diagonal independence is essential: supplying a different
coefficient covariance without a new expectation/derivative derivation is
not supported. The generated focused test independently compares literal
densities, numerical integrals and all-coordinate finite differences;
passing it does not authenticate native design or prior inputs.

## 4. Required application continuation adapter

At horizon h and particle history through h-1:

```text
x_beta,h = retained reference DESN continuation using preceding Y values.
x_alpha,h = retained discrepancy DESN continuation using
            issued_center[j] - Y[j] at preceding j.
mu_Y,h = x_beta,h' beta.
mu_G,h = x_beta,h' beta + x_alpha,h' alpha + known_baseline[h].
G_h = product(e=1,...,51) f_p(g[h,e] | mu_G,h, sigma_G[,gamma_G]).
Y[h] ~ f_p(mu_Y,h, sigma_Y[,gamma_Y]).
```

Evaluate the 51 member factors before propagating Y[h], because their
location uses earlier responses, not the current future Y value. Preserve
the existing issued-center definition as a fixed part of the discrepancy
input map; it is not averaging future DESN features or parameter draws.
Use either raw issued observations with the baseline in mu_G, or the
existing adjusted observations without it, but never apply it twice.

The native adapter must accept **changing parameters**, not a closure fixed
at `theta_mean` and `1/E(precision)`. `giv_state_factory()` is explicitly a
fixed-parameter AL-median diagnostic and cannot be relabelled an optimizer.
Its qualified per-step construction can guide an additive adapter:

1. Compile static input/date contracts once. Keep weights, reducers, gains,
   scaler values, readout order and cutoff states immutable.
2. For each parameter draw, start all particles from the same retained cutoff
   states; carry each particle's two DESN states and generated lag history.
3. On resampling, select histories and **both** state collections together.
   Recomputing a full H-step callback for every particle/horizon is neither
   needed nor an acceptable unmeasured cost assumption.
4. Compare new features and locations with fresh production `gcv`/uncached
   continuation at several generated parameter draws and paths. Do not call
   saved closures or generate another reservoir realization.
5. Historical residual evaluation can cache the certified fixed X_beta/X_alpha
   blocks and share the reference product across paired Y/G rows. Cache only
   parameter-independent quantities; AL residuals and both scale normalizers
   must still be evaluated at every parameter draw.

Particle count N is not the number of independent paths after repeated
resampling. Record pre-resampling ESS, retained ancestry and independent
replicate variation of log evidence, parameters and forecast quantiles.

## 5. exAL and MQ are separate extensions, not aliases for median AL

For exAL, add `(gamma_Y,gamma_G)` and use the normalized quantile-fixed
family throughout the historical density, future simulator and member
likelihood. `app_joint_qvp_exal_support()` gives different open bounds for
each p. The available transformations include
`app_joint_exqdesn_support_eta_to_gamma()` and
`app_joint_exqdesn_log_support_jacobian()`; the alternative p_gamma map has
a different Jacobian. Choose one coordinate convention and include its
Jacobian once. `app_latent_exal_scale_shape_update()` currently calls the
structured helper with its default `gamma_prior_type="none"` (a constant
kernel within the fixed support); authenticate rather than invent a new
shape prior. The existing q(gamma)q(sigma|gamma) quadrature is a variational
update, not the marginal exAL observation density needed by this optimizer.
Obtain and test a stable marginal-density/CDF/simulator implementation before
claiming exAL support; gamma=0 must recover the AL family.

For GloFAS MQ, the grid is `.05,.20,.35,.50,.65,.80,.95`, not the JOINT
simulation's grid. `app_glofas_part3_rhs_update()` applies independent
product-RHS blocks to the first coefficient vector and each **unscaled raw
adjacent difference**, separately for reference and discrepancy. Its leading
intercepts are exempt from horseshoe shrinkage but have proper Normal
anchor/difference factors; no simulation-specific ordered-intercept or
additional latent-baseline constraint is introduced. The cumulative
coefficient-to-increment map has determinant one.

There is a separate Y path and Y/G scale pair per level. Conditional on the
full parameter vector the path integrals factor across levels, while the
coefficient prior couples levels. Repeated historical observations across
levels enter the stated composite target, not a claim of independent copies
of observed USGS. With learned slabs throughout, MQ AL has 52,570 physical
coordinates and MQ exAL adds 14 shapes. The generated helper's 20,000-entry
parameter limit is therefore not a ready MQ interface. A new optimizer must
not silently pool level paths, use one global error scale, or describe a
single-level success as MQ qualification.

The recorded path-precision `1e-8` and MQ inner-ridge `1e-12` controls are
numerical regularizations of the existing approximation, not additional
historical coefficient priors. Do not add either to the marginal parameter
target merely because it appears in a variational linear solve.

## 6. Concrete evidence required before the first native application pilot

1. **Density and coordinate record:** exact field-to-coordinate map for all
   7,510 median-AL unknowns; fixed hyperparameters and proper intercepts;
   independent log-density and finite-difference checks of the NS product and
   transformed Jacobian. A point or frozen inverse-moment substitution fails
   this requirement.
2. **Generated optimizer checks:** no-member historical parameter invariance,
   the normalized future AL law, unknown Y and G scales, proper intercept
   uncertainty and the full two-component product prior. Compare finite-N
   expected-log/outer-score calculations with independent low-dimensional
   integration. Check particle-count sensitivity and cross-parameter/path
   moments, not only marginal means or objective ascent.
3. **Fresh nonlinear adapter parity and cost:** changing parameters, both
   state blocks, all 51 factors, scalar/no-member cases and resampling-state
   synchronization. Benchmark actual historical and per-particle operations;
   report outer draws x particle replicates x iterations. Parent-only timings
   previously underpredicted simultaneous-worker costs; use measured forked
   work and a new finite native allowance.
4. **New authentic purpose:** bind clean source and the preserved numeric
   basis, exact input roles, before/after hashes, read count, library and CPU/
   memory/wall/output caps. The previous two-input purposes are closed and
   cannot authorize an all-parameter run. Two payload roles suffice only if
   they and authenticated small configuration metadata supply every prior
   field; otherwise declare the additional required input before reading it.
5. **Single median-AL comparison:** native pilot optimizes every declared
   coordinate and returns all failed/partial replicates, gradient/objective
   Monte Carlo errors, particle diagnostics and optimizer boundary hits.
   Compare like-for-like parameter/path summaries at the preserved target;
   neither the poorly mixed old pCN paths nor the old product-VB approximation
   is an exact answer to fit toward. Do not tune on protected future truth.

Keep the model-result formatter separate from qualification. The existing
`app_glofas_family_transition_quantiles()` assumes a Gaussian path factor;
it cannot format the new particle approximation by merely copying its mean
and covariance. The intended report remains the level-p marginal response
quantile after integrating parameter and future-path uncertainty, transformed
by `expm1`, without extra response noise. An estimator-specific formatter,
Monte Carlo precision checks, complete coherent family packet and separate
article integration are later requirements. Historical caches and Normal
fits may be reused only when their full target/design/prior/reporting/source
identities remain unaffected; their model names alone are insufficient.

This audit identifies a valid route for changing the inference method
without rewriting the statistical model. It does not establish that the
proposed approximation improves forecasting or qualifies a production run.

## Implemented generated verification

`scripts/diagnostics/glofas_collapsed_al_target.R` evaluates the complete
historical marginal-AL/NS target and its exact diagonal-Gaussian ELBO and
derivatives. `glofas_collapsed_parameter_optimizer.R` performs genuine outer
optimization with independent score estimates, leave-one-out variance control,
jackknife Monte Carlo errors and local variational-standard-deviation mean
steps. Its fixed-factor family is not an unrestricted covariance family.
`glofas_collapsed_optimizer_reference.R` supplies independent deterministic
variational and exact-posterior comparisons. The reference distinguishes
optimization error from the Gaussian family's remaining approximation error.

The general score-function strategy follows
[Ranganath, Gerrish and Blei (2014)](https://proceedings.mlr.press/v33/ranganath14.html).
The expected-log particle-bound distinction is consistent with
[Naesseth et al. (2018)](https://proceedings.mlr.press/v84/naesseth18a.html).
The conditional outer-score derivative stated above is derived for this
implementation; neither citation qualifies the present application or implies
that omitted inner-proposal derivatives are generally harmless.

Run the four focused `test_glofas_collapsed_*` target/optimizer/reference/audit
tests registered in `application/tests/run_tests.R`. From a clean committed
source tree, the generated accuracy audit can be reproduced with R4.6:

```bash
mkdir -p local_trackers/glofas_collapsed_parameter_optimizer_20261105
Rscript --vanilla scripts/audit_glofas_collapsed_optimizer_generated.R \
  --output "$PWD/local_trackers/glofas_collapsed_parameter_optimizer_20261105/generated_audit_new"
```

The output must be a fresh ignored directory. All three predeclared cases,
including limited-budget or unfavorable outcomes, are retained. Its terminal
state explicitly says application not qualified. Software success, proximity
to a variational optimum, and fidelity to the full posterior are separate
claims; none automatically authorizes an application refit or article change.
