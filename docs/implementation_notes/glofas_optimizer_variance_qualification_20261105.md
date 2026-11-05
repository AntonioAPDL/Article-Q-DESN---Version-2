# GloFAS optimizer: variance and step qualification

## Scope

This stage changes numerical inference code, not the statistical model,
application fits or article. It retains the executed input gains0.5/0.35,
bias gains one, destination priors, normalized same-family future law and
all51 ordinary member likelihood factors. Future USGS remains excluded from
fitting and selection. Original model payloads are not read by these tests.
No application or publication authority follows from a generated calculation.

The full parameter target remains proportional to pi_H(eta)Z_G(eta), where
Z_G integrates the normalized future-response law and ordinary member factors.
A particle estimate supplies an expected-log objective, not an unbiased log
normalizer. The parameter-dependent finite-particle gap remains a separate
accuracy question. No cut posterior or substitute Gaussian path is introduced.

## Why variance reduction alone was insufficient

The earlier concentrated H1 benchmark failed even with an exact objective
and exact gradients: the legacy optimizer exhausted1000 iterations with an
extra ELBO gap about0.318 and zero Monte Carlo error. Its late objective rose
monotonically, clipping was inactive, and no variance bound was active.
This isolates slow step dynamics from stochastic-gradient and particle error.

The new code preserves the legacy Adam strategy as the default. Explicit
`short_memory_adam_099` and `short_memory_adam_095` options retain the paired
updates v<-beta2*v+(1-beta2)*g^2 and their matching bias corrections. They
change an optimizer setting, not a prior or statistical learning rate.
All starts, seeds, iteration/evaluation caps and acceptance thresholds remain
the same in the controlled comparison. No strategy is selected by application
case or protected forecast performance.

An exploratory wrapper initially changed beta2 without its paired gradient
weight. Those noncanonical outputs are retained and excluded from qualification;
the corrected comparison and actual named implementation agree. Another
exploratory run completed its calculations but correctly failed its source
hash guard after a nonnumerical reference-scope edit. Its results remain
unfrozen exploratory evidence. Fresh committed-source driver runs supply
the reproducible qualification packets; neither failure is silently hidden.

## Function-valued controls

Let R=logZhat and let c be fixed during the current gradient calculation.
The controlled future score is

```text
E[score_q (R-c)] + E[score_q c].
```

The objective likewise adds E[c] after subtracting c from sampled rewards.
Controls contain no prior, entropy or parameter-transformation Jacobian.
Historical analytic terms already contain their entropy and Jacobian once.
A factory using the current variational state supplies partial score moments
holding its anchor fixed, not a total derivative through that anchor.
Independent outer draws and leave-one-out baselines retain the required
expectations; jackknife MCSE accounts for the shared baselines.

The general score-control and conditional-expectation approach has precedent
in [Ranganath, Gerrish and Blei (2014)](https://proceedings.mlr.press/v33/ranganath14.html).
The specific controls, derivative identities and source guards here are
separately derived and tested; that reference does not qualify this application.

An unbiased control need not reduce variance. The member log likelihood
contains -M*log(sigma)-exp(-log(sigma))*loss. Freezing only the reciprocal
scale can destroy the cancellation between those terms and increase gradient
noise. Both global and state-anchored versions of that control are retained
as negative comparisons.

The state-frozen Taylor2 control approximates exp(-eta) about an anchor a
using exp(-a)*(1-delta+delta^2/2), delta=eta-a. It preserves two orders of
that cancellation while retaining the exact sampled residual. Its expectation
and partial score moments are analytic for the supported independent Gaussian
coordinates. Unsupported correlated factors are rejected, not diagonalized.
This is an estimator control, not an approximate likelihood replacing AL.

Raw and controlled gradients, MCSEs, objective errors and resource counts
are retained. Control-factory/evaluation and projection calls have their own
bounds and are included in total cost; controls are not represented as free
computation. Default no-control behavior, RNG and legacy steps are preserved.

## Full-AL conditional score integration

For diagonal q, the future term depends on2502 coefficients and two scales,
not directly on the5006 RHS variables once coefficients/scales are given.
Their10012 future mean/log-SD score terms therefore have conditional
expectation zero. The authenticated projector removes this noise before
adding historical derivatives. Every RHS variable remains random and free to
update through the exact historical ELBO. No shrinkage parameter is frozen.

The generated evidence factory loads pinned text sources into locked private
environments and verifies every parameter role. Arbitrary masks, changed
sources, rebound control templates, unverified control dependencies and
unsupported correlated factors fail closed. These generated guards are not
authentication of an arbitrary native callback or retained model object.

Two authenticated controls are available. The first integrates all H*51
member normalizers and first-horizon loss. The full-frozen-design control
uses all ordinary member factors at separately declared fixed feature rows.
Those rows are a computational control only: the sampled residual still uses
the causal future law and changing paths. Neither averaging forecasts nor
replacing the posterior target is involved. Computational normalization of
particle weights is distinct from tempering member likelihoods.

## Independent accuracy assessments

The H1 comparison retains the no-member identity,51 dispersed members and51
concentrated members. It records the old method, negative controls, proposed
strategy/control and declared sensitivity. Accuracy thresholds are additional
ELBO gap<=1e-3, mean error<0.05 reference SD and variance error<5%, assessed
alongside the original stopping criteria. The independent deterministic
Gaussian reference is not a certificate of global optimality. Its KL is
called reference-family KL, not a proven minimum.

Forecast-function and parameter-family errors are assessed separately. The
Normal-AL convolution and conditional Normal integration over log scale give
predictive CDFs and quantiles without new response draws. Independent split
quadrature, tail-limit checks and32/64-node comparisons test that calculation.
The fixed reference gates use reported-p quantile error<=0.001 and CDF error
<=0.01 on a declared quantile/midpoint grid, not an asserted global supremum.
All parameter-variance/covariance discrepancies and nonpassing cases remain.

An H2 reference integrates an affine AL product exactly, retaining all102
ordinary member factors and both source scales; the last unobserved response
transition integrates to one. Particle comparisons retain all288 declared
replicates across weak/strong lag dependence, three scale pairs and counts
16/64/256. They report ancestry, ESS, individual and average log-normalizer
error, empirical Jensen gaps and measured time. A finite empirical gap is
not a certified bound, and conditional fixed-parameter accuracy is not
joint-parameter or nonlinear-H28 qualification.

## Reproduction and promotion boundary

The registered focused tests are in `application/tests/run_tests.R`.
From a clean committed tree with R4.6, create a fresh ignored parent:

```bash
mkdir -p local_trackers/glofas_optimizer_variance_qualification_20261105
Rscript --vanilla scripts/audit_glofas_optimizer_variance_qualification.R \
  --part candidate \
  --output "$PWD/local_trackers/glofas_optimizer_variance_qualification_20261105/candidate_new"
Rscript --vanilla scripts/audit_glofas_variance_auxiliary_references.R \
  --part predictive \
  --output "$PWD/local_trackers/glofas_optimizer_variance_qualification_20261105/predictive_new"
```

Optimizer parts baseline,negative,candidate,sensitivity and auxiliary parts
predictive,particle are independent and may run on separately reserved cores.
Each requires exact committed text-source hashes and clean source before and
after calculation, fresh output, complete manifests and explicit no-native/
no-publication flags. A fast test override cannot be exported as a default
qualification packet. Keep all earlier failed/unfavorable receipts.

Only after numerical, predictive/particle and native source/input/cost gates
are reviewed should one bounded median-AL application comparison be admitted.
The native method still needs changing-parameter continuation of both retained
DESNs, complete prior/input identities, adequate particle accuracy, a new
read/resource purpose and an estimator-specific forecast formatter. Neither
exAL nor MQ is qualified by a single-level AL example. A full coherent packet
is required before changing results, manuscript assets or Overleaf.
