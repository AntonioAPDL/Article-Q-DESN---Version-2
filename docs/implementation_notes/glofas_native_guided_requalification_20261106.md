# GloFAS native guided-particle requalification

## Scope

The completed native Stage E calculation rejected the bootstrap particle
proposal for the median AL target. Native continuation, historical derivatives,
and RHS-only invariance passed, but the H28 filter reached one effective and one
ancestral particle. This development stage changes only the proposal used to
integrate the future response path. It does not alter a fitted model, prior,
reservoir, ensemble-member weight, posterior target, or article result.

## Proposal construction

Let the current particle contain the causal response prefix
`Y[1:(h-1)]` and both retained DESN states through horizon `h`. The exact
transition is

```text
f_h(y) = AL_p(y; mu_Y,h, sigma_Y).
```

The issued-member factor at the next horizon is

```text
G_(h+1)(y) = product_e AL_p(g_(h+1),e;
                             mu_G,h+1(y), sigma_G).
```

The retained nonlinear continuation supplies the value and analytic derivative
of `mu_G,h+1(y)` at `y = mu_Y,h`. The local affine map is

```text
a_h(y) = mu_G,h+1(mu_Y,h)
         + d mu_G,h+1(y) / dy |_(mu_Y,h) * (y - mu_Y,h).
```

The normalized proposal is

```text
q_h(y) proportional to f_h(y)
  * product_e AL_p(g_(h+1),e; a_h(y), sigma_G).
```

The existing piecewise-exponential affine-AL implementation evaluates its
normalizer, density, CDF, and inverse CDF on the whole real line. The proposal
is used for `h < H`; terminal `Y_H` is sampled from its original transition.

The actual particle target remains exact. After drawing from `q_h`, the kernel
retains `f_h/q_h`. At the next step it evaluates the actual nonlinear
`G_(h+1)`, not the affine approximation. No resampling occurs between the
correction and that factor. Thus the affine map affects variance but does not
replace the statistical target.

## Native derivative

The guide uses `app_qdesn_continue_one_step_with_jacobian()` and
`app_qdesn_readout_row_from_states_with_jacobian()` for both the reference and
discrepancy reservoirs. The candidate response has derivative `+1` in reference
lag positions and `-1` in discrepancy positions defined as issued centre minus
reference response. Earlier lags and conditioned exogenous inputs have zero
derivative. Coefficients map the resulting readout derivatives to the next
ensemble-location slope. Generated central differences independently check the
analytic result.

## Software isolation

The legacy null-guide path remains the default and retains its original RNG and
arithmetic behavior. A native guide is enabled only through an explicit bounded
control. Generic and native guides cannot be active simultaneously. The backend
records guide calls, continuation calls, and the observed slope range. Malformed
or nonfinite guide values fail the evidence evaluation rather than being clipped
or converted to a finite objective.

The guided requalification budget is separate from Stage E. Its initial
extension rule requires complete evaluations, all prespecified degeneracy
diagnostics, and at least a factor-of-two reduction in every context/count MCSE
relative to the first four frozen Stage E bootstrap replicates. Cost and memory
admission remain necessary. Failure stops before the 16-replicate extension.

## Authorization boundary

Generated tests and a later truth-free native qualification are not fits.
Neither can authorize Stage F, exAL, MQ, production, publication, or replacement
of current article authority. Stage F requires a separate explicit proposal even
if this guided qualification passes.

## Reader and qualification boundary

`scripts/glofas_native_guided_requalification_reader.R` accepts only an
external, private, digest-pinned purpose. It reuses the frozen Stage E target,
metadata, cost and two-read lifecycle, then requires the complete guided source
closure and its separate prospective budget. Execution authenticates exactly
the truth-free shared design and accepted median-AL fit used by Stage E. It
cannot deserialize generated RDS objects, read future truth, fit a model, run
an optimizer, score a forecast, change the article, publish, or launch Stage F.

The initial authentic grid remains the Stage E grid: three fixed parameter
contexts, 64/128/256 particles and four frozen seeds. Extension to 16 seeds is
admitted only when every initial evaluation completes, every prespecified
ESS/ancestry diagnostic passes, every context/count MCSE is at most one half
of its frozen Stage E bootstrap MCSE, and the original time/memory gate also
passes. A failed initial gate is retained as evidence and stops expansion.

Generated regressions establish:

- exact affine H2 evidence at one particle;
- analytic one-step slopes against central differences for affine and
  nonlinear reservoirs;
- unchanged legacy bootstrap behavior when the guide is absent;
- valid state, ancestry, callback and RNG bookkeeping;
- rejection of malformed controls and simultaneous generic/native guides;
- lower evidence dispersion in a fixed nonlinear H5 stress fixture.

The registered reader test mutates every forbidden authorization, the exact
two-read budget, wall-time ceiling, source closure and guide-budget pin. It
uses no authentic artifact. The repository's reader-appendix editorial test
pins `application/tests/run_tests.R`; therefore full-suite verification for a
new scientific branch is performed at the frozen commit in a disposable Git
worktree after an explicit test-only editorial receipt refresh. Those refreshed
receipts are never committed to this branch.
