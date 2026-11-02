# Independent-study ancestor-first filtering and future CDF components

## Scope

This additive implementation supplies an alternative conditional numerical
filter and a known-feature horizon-marginal calculation. It does not fit
parameters, read retained objects, generate random numbers, authenticate an
input source, dispatch work, or promote article results. The existing
`ind_gaf_filter` and its historical REVIEW receipts remain unchanged.

The empirical training-parameter population is fixed. Each call conditions
on one retained parameter identity and integrates its state/augmentation
uncertainty. Predictive normalizers are within-parameter quantities; they
must not reweight the outer parameter population at later origins.

## Ancestor-first auxiliary filter

The opt-in implementation is `scripts/ind_adapted_auxiliary_filter.R`.
At time t, ancestor j has Gaussian state moments and weight w_j. Its
prediction uses the native rule

\[
 P_j=G C_jG^\top,\qquad W_j=D\odot P_j,\qquad R_j=P_j+W_j,
 \qquad f_j=F^\top Gm_j,\quad S_j=F^\top R_jF.
\]

For AL, the scalar Normal--AL convolution gives the exact lookahead ell_j.
Select ancestors with probabilities proportional to w_j ell_j, then draw
a fresh conditional v for each selected child. The conditional-v proposal
integrates the temporary projected Gaussian location; that temporary value
is discarded before the Gaussian state update. The final AL child weights
are equal. Resampling ancestors first avoids copying one already-sampled
auxiliary to all offspring of a selected ancestor.

For nonzero exAL shape, the lookahead is a positive, fixed midpoint
approximation to the half-Normal integral (16 nodes by default, explicitly
recorded). The half-Normal s itself is proposed from its native prior and v
from the exact conditional proposal given s. The child importance ratio is

\[
 \omega_i\propto{\ell_{A_i}(y\mid s_i)\over
                       \widetilde\ell_{A_i}(y)},\qquad
 Z_{\rm incr}=\left(\sum_jw_j\widetilde\ell_j(y)\right)
                     {1\over N}\sum_i\omega_i^{\rm unnormalized}.
\]

The lookahead approximation therefore changes the proposal, not the target.
Its residual weights and the evidence scale are both retained. This exAL
method is not fully adapted over s. At gamma=0 it reduces to the AL method.

The implementation records lookahead ESS, residual ESS, selected ancestors,
initial-lineage diversity, residual underflow and post-update resampling.
Equal AL child weights do not demonstrate an accurate filter: ancestor
concentration can remain severe. The historical 13/27 agreement result is
not replaced by these synthetic checks or by the new algorithm's existence.

### API and causal continuation

1. `ind_aaf_initialize(m0,C0,df_mat,eta,particle_count,parameter_id,...)`
   binds the static parameter, initial prior and numerical policy.
2. `ind_aaf_step(state,y,F,G,innovations,time_index)` consumes exactly the
   next observation and returns the actual continuation state.
3. `ind_aaf_continue(state,y,FF,GG,uniforms,time_indices,checkpoint_indices)`
   processes one contiguous block and returns `state`, named `checkpoints`
   and per-step `diagnostics`.

Step innovations are a particle-by-four proposal matrix, a scalar ancestor
resampling innovation, a separate scalar residual-resampling innovation,
and an exAL-only half-Normal innovation per particle. Every supplied value
lies strictly between zero and one. The module never calls an RNG.

`state$last_report` is the weighted Gaussian mixture **before** optional
post-update residual resampling. `state$mean`, `state$covariance` and
`state$weights` are the actual **after-resampling carry**. These can differ
for exAL. Continue with the returned state, not a reporting checkpoint.
With identical supplied streams, chunked and uninterrupted runs agree
exactly, including resampling and diagnostics. Forecast computation must
not mutate this state or its filtering streams.

The state holds only the current mixture and most recent report/diagnostics.
The continuation wrapper retains only explicitly requested checkpoints.
It does not allocate an entire historical particle cloud or claim production
restart authentication. An external source-bound worker must bind model,
absolute time, streams and restart bytes before accepting a saved carry.

## Known-feature future marginal components

`scripts/ind_future_cdf_reconstruction.R` reuses the existing
`ind_cfm_future` equations. Its API is:

```
components <- ind_fcm_components(checkpoint, FF, GG, df_mat, eta,
  v_paths, origin_component,
  future_features="known_deterministic",
  future_auxiliary_role="native_prior_Exp_scale_sigma_supplied_paths")
cdf <- ind_fcm_cdf(y, horizon, components, ...)
quantiles <- ind_fcm_quantile(probability, horizon, components, ...)
```

FF is state-by-horizon; GG is a constant state transition or a
state-by-state-by-horizon array. `v_paths` is path-by-horizon, strictly
positive and supplied by the caller. Its declared law is Exp(scale=sigma);
this low-level function cannot authenticate how the caller generated it.
`origin_component` maps every path to an original Gaussian checkpoint
component. Each positive-weight origin component must be represented.

If origin component j has weight w_j and n_j supplied future paths, each
such path receives weight w_j/n_j. Thus unequal path allocations do not
change the original origin measure. These are inner conditional weights,
not outer static-parameter weights. The caller must separately preserve
each original parameter's source identity and empirical posterior weight.

The Gaussian states and intermediate future responses are integrated
analytically conditional on the required prior-v histories. C_aux controls
the discount-generated W, while S is the marginal covariance of the
unobserved state. They are not interchangeable. Future intermediate
half-Normal shifts do not affect C_aux/W and need not be simulated for
these marginals. Each terminal v is integrated analytically under AL;
exAL additionally integrates its terminal half-Normal shift by declared
one-dimensional quadrature. No second observation error is added.

The returned arrays are horizon marginals, not joint simulated response
paths. This reduction does not apply to response-dependent DESN features.
The future sampler/worker for those features must retain recursive feedback.

### Numerical meaning and pending worker integration

AL finite-mixture inversion uses the analytic terminal CDF and an explicit
width tolerance. Nonzero-shape exAL uses numerical CDF inversion; its
QUADPACK error is labelled an **estimate**, not a rigorous bound. The
inverter rejects comparisons/endpoints unresolved at that declared
quadrature precision. It does not silently tighten the quadrature, choose
a favourable branch, or claim a certified posterior quantile bracket.

The component measure can feed a future IND worker through its CDF or
quantile API, but must have an IND-specific typed envelope. It is not an
`app_iqf_adapter`, a grid-response MQ trajectory, or a production receipt.
A valid worker still needs original parameter/origin membership, source
and future-input authentication, filter and future-integration qualification,
numerical receipts and central acceptance. Resampled filter particles are
not iid validation paths; no MQ Bernstein certificate may certify their
bias or origin-filter accuracy. All corresponding flags here remain false.

## Checks and remaining work

New focused tests:

- `application/tests/test_ind_adapted_auxiliary_filter.R`: independent AL
  likelihood integration, ancestor selection, fresh auxiliary offspring,
  exAL residual/evidence ratios, gamma-zero reduction, report/carry
  distinction, causal exact continuation and rejection checks.
- `application/tests/test_ind_future_cdf_reconstruction.R`: H1 reference,
  no-discount analytical limits, terminal/history dependence, 30-horizon
  prefix parity, original component weights under unequal path replication,
  signed exAL quantile-fixed limits and explicit numerical qualifications.

These complement rather than replace the existing guided primitive/filter
and conditional-future-marginal tests. The shared test registry is maintained
by the coordinator, not this isolated source lane.

No authentic qualification or computational speedup is established by this
implementation. A10 compiled/vectorized optimization requires a separately
profiled scalar-identical counterpart. IF01 still requires a fully source-,
payload-, runtime- and resource-bound authentic qualification driver and
representative AL/exAL/native-version/parameter checks. The H1--H30
connector's synthetic tests do not satisfy those gates. No metadata-only
CLI or source hash is substituted for an executed numerical qualification.

Full reconstruction remains blocked until these gates, the remaining
Q--DESN/VB enrollment, historical prior/execution audit, complete production
receipt wiring, whole-inventory cost and host admission pass. No parameter
refit or article replacement is authorized or implied here.
