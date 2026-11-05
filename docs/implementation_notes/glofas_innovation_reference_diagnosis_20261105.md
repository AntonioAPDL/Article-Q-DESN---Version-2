# GloFAS inference diagnosis: exact AL innovation coordinates

## Decision and scope

This stage follows the completed but inconclusive conditional-reference
calculations. The previous two-arm recovery pilot completed all eight chains,
with no execution failures, but neither arm passed the original precision
criteria at any of the 28 horizons. Those receipts remain evidence of an
unqualified reference, not a failed production fit. The earlier 80,000-path
reference also remains inconclusive.

The present additions are diagnostic code and generated mathematical tests.
They do not change the application model, fit, manuscript, tables, figures or
article authority. They admit no future USGS measurements, forecast-loss-based
selection, prior changes, new reservoir weights or changes to input gains.
The selected/applied gain discrepancy remains a separate decision after the
inference diagnosis. No performance gain is asserted.

## What the generated checks establish

The benchmark module invokes the actual Normal and AL coefficient, local
latent-variable, scale and Gaussian future-path coordinate helpers on small,
fully specified targets. Independent scalar equations and exact integration
provide separate checks of implementation parity and approximation accuracy.
All 19 implementation comparisons pass. All 19 complete-target comparisons
retain departures in at least one marginal moment or dependence feature.
This does not mean that every individual quantile fails: for example, the
51-member two-horizon lower-quantile check passes its CDF tolerance despite
incorrect joint moments.

Without issued members, a normalized future-response law integrates to one
and leaves the historical parameter marginal unchanged. The independent
coefficient/path variational factors cannot retain their exact covariance.
In a generated Normal example, the exact coefficient variance is 1.1 and the
future variance is 1.9; the corresponding factorized values are approximately
0.46316 and 0.8. With an unknown scale, the exact no-member scale marginal
remains the specified inverse-gamma law while its variational approximation
has different shape and rate. This is an approximation departure, not a
claim that the mathematical model changes its prior. Conditioning on issued
members can legitimately update parameters.

These results isolate plausible approximation mechanisms. They do not
quantify their contribution to the application's forecast loss, authenticate
a complete RHS/exAL/MQ fitting driver, or justify a production replacement.

## Exact change of variables

At fixed parameters, write the normalized future-response law as

```text
Y_h = mu_h(theta, Y_<h) + sigma_Y * F_AL,p^(-1)(Phi(Z_h)),
Z_h independently Normal(0,1), h=1,...,H.
```

Here `F_AL,p` is the standard, quantile-fixed AL CDF. The causal response
location uses the reference DESN; the member location below combines the
reference and discrepancy DESNs. Both continue the retained states with
fresh path-dependent inputs. If
`u_h = (Y_h-mu_h)/sigma_Y`, the triangular derivative has diagonal

```text
dY_h/dZ_h = sigma_Y * phi(Z_h) / f_AL,p(u_h).
```

Consequently, the response-density product times the absolute determinant
is exactly `prod_h phi(Z_h)`. With all 51 issued members, the conditional
coordinate target is therefore

```text
pi(Z | theta, issued) proportional to
    prod_h phi(Z_h) * prod_(h,e) f_AL,p(g_h,e | nu_h(theta,Y(Z)), sigma_G).
```

All member exponents are one. The transformation neither Gaussianizes the
AL observation law nor replaces the 51 likelihood factors by their mean.
The retained ensemble centre enters only where the frozen discrepancy input
construction already requires it. For unknown parameters the mapping
`(theta,Z) -> (theta,Y)` is block triangular; the identity parameter block
introduces no additional determinant. The generated tests verify that
identity, but the first authentic pilot holds parameters fixed.

The multiquantile identity uses a separate future path for each probability
level and includes the coupled historical prior once. It does not introduce
a single shared-path product or establish exAL or MQ computational accuracy.

## Computational candidate

The diagnostic continuation compiles only the retained static input
contracts, then performs the unchanged production state/readout updates once
per component and horizon. A forward evaluation requires `2H` state updates;
it does not call a complete trajectory builder `H` times. Generated tests
compare the full designs, locations, densities, inverse transformation and
Jacobian with the unchanged production continuation, including causal lags,
reducers, scaling and extreme Normal coordinates.

For a bounded computational pilot, the proposal is

```text
Z_new = sqrt(1-delta^2) Z + delta epsilon,
epsilon independently Normal(0,I).
```

This pCN proposal is reversible for the Normal reference, so the Metropolis
ratio contains only the issued-member likelihood ratio. Its scale adapts
only during the declared warmup and remains fixed for retained iterations.
Each iteration needs one forward value evaluation. Normal-reference balance,
nonconstant-likelihood sampling, random-number reproducibility, partial-state
retention and budget failure are tested separately. Gaussian-reference
preservation follows the construction of [Cotter et al. (2013)](https://arxiv.org/abs/1202.0709);
it is not a mixing guarantee. Centered and noncentered parameterizations can
have different efficiencies, with neither uniformly preferable
([Papaspiliopoulos et al., 2007](https://arxiv.org/abs/0708.3797)).

## Authentic admission and next gates

The new external, source-bound purpose allows exactly two original reads:
the frozen truth-free design and retained median-AL fit. It does not read old
numeric path arrays. Before any sampling, the reader checks clean committed
source, complete runtime source hashes, predecessor closure receipts, original
before/after hashes, exact fixed parameters and fresh feature/density parity.
Scales are reciprocals of retained mean inverse scales, not retained mean
scales. Coefficient covariance is zero in this conditional calculation.

The admission allows four one-thread workers, fixed seeds, 500 warmup and
1,000 retained iterations per chain, CPUs 26--29, finite evaluation/wall/CPU
budgets and private generated-draw export. A conservative measured-cost
projection must fit before forking. Native process identities, lineage,
affinity, limits, progress and termination are independently verified by the
durable controller. Incomplete and unsuccessful states remain unqualified;
they are not automatically retried or extended.

Original Rhat, bulk/tail ESS and quantile-MCSE thresholds remain unchanged.
Passing them in a short conditional pilot is recorded separately from
qualification. The pilot cannot authorize a full parameter-posterior method,
an application refit or publication. Those require independent complete-target
checks for parameter/path dependence, RHS, exAL scale/support, separate MQ
paths, and nonlinear feature continuation, plus a feasible measured schedule.
No deadline overrides these gates. More cores cannot remove sequential
median-outward and joint-initialization dependencies.

## Reproduction and integration

Use pinned R 4.6.0 for the five generated R tests and Python 3.11 for the
controller tests registered in `application/tests/run_tests.R`. Run the
generated benchmark export into a fresh ignored child of `local_trackers/`
with `scripts/audit_glofas_innovation_generated.R --out-dir PATH`. Its CSVs,
decision receipt and source/output manifests preserve accuracy failures.
They contain no authentic data and are not article assets.

Before integration, run the combined repository harness, parse changed R,
compile Python without leaving cache files, run `git diff --check`, verify
unchanged production and article-allowlisted blobs, and exclude runtime
payloads. Merge the frozen diagnostic branch without squashing in a fresh
integration worktree and publish through command-line Git. No article-only
snapshot or Overleaf action is needed for these diagnostic additions.
