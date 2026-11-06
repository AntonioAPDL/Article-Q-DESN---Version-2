# GloFAS: same-target guided particle calculation

## Reason for this stage

The preceding generated audit completed 288 bootstrap particle calculations.
Although replicated mean evidence agreed with the conditional reference, all
18 groups retained a single-estimate precision review. At 256 particles,
log-evidence standard deviations ranged approximately from 0.043 to 0.360.
The revised parameter optimizer cannot remove this inner calculation error.
More cores alone do not establish its accuracy.

This stage adds a normalized observation-informed proposal and its complete
importance correction. It changes numerical sampling, not the model. The
ordinary 51 unit-power member factors, both AL scales, destination priors,
normalized future-response transitions and the executed reservoir
specification remain unchanged. Existing application results and article
assets are not replaced. No retained application object or future USGS truth
is read by these generated calculations.

## Conditional target and proposal

At a fixed parameter value, write the normalized future transition as
f_h(y_h | y_<h) and the member contribution as

```text
G_h(y_<h) = product_(e=1)^51 AL_p(g_(h,e); mu_G,h(y_<h), sigma_G).
Z = integral product_(h=1)^H [f_h(y_h | y_<h) G_h(y_<h)] dy_1:H.
```

All scale-dependent normalizers remain in G_h. No fractional member weights
are introduced. If a normalized, full-support proposal r_h replaces sampling
from f_h, the weight includes the entire ratio f_h/r_h. The terminal
unobserved response uses its prior transition and integrates to one.

The implementation first weights by G_h, optionally resamples, then proposes
y_h and normalizes the f_h/r_h correction. It does not resample this corrected
cloud before the next G_(h+1) contribution. Both normalizer increments are
retained. Log weights are retained through the correction and next member
factor, so probability-scale underflow cannot silently destroy a later
cancellation. Numerical normalization of particle weights is not likelihood
tempering.

For the affine H2 reference, choose

```text
r_1(y) = f_1(y) G_2(y) / I,    I = integral f_1(y) G_2(y) dy.
```

This product of AL densities is piecewise exponential. Its interval masses,
normalizer, density and inverse distribution function are evaluated on the
whole real line, with stable exponential-tail expressions. Then f_1/r_1
cancels G_2, so the complete estimate equals G_1 I for every particle count
in exact arithmetic. Tests compare the new normalizer with a separately
implemented piecewise integral and split numerical quadrature.

The proposal may depend on the sampled parameter value, issued members and
particle history. The narrow adapter has no additional dependence on the
variational distribution's evolving parameters. Adding such dependence
would require a new derivative argument; an outer score identity cannot
silently omit it.

The general importance-density ratio and observation-informed proposal are
described in [Doucet and Johansen's tutorial](https://www.stats.ox.ac.uk/~doucet/doucet_johansen_tutorialPF.pdf).
The finite-particle expected-log objective remains distinct from unbiased
evidence estimation; see [Naesseth et al. (2018)](https://proceedings.mlr.press/v84/naesseth18a.html).
Neither reference establishes accuracy for this application.

## Implementation and verification

- `glofas_al_affine_guided_proposal.R`: normalized affine AL guide, full-support
  sampling, analytic normalizer/log density and immutable guide snapshots.
- `glofas_guided_collapsed_particle.R`: separate experimental guided kernel
  and a narrow adapter for the locked generated affine H2 binding. The old
  bootstrap kernel and its frozen source fingerprints are untouched.
- `audit_glofas_guided_particle_qualification.R`: clean committed-source audit,
  fresh ignored outputs, all outcomes retained and complete file hashes.

The generic callback interface is experimental: a caller's scope flags do
not prove that its proposal is normalized. Only the explicitly checked affine
construction has the stated exact reference. Tests retain wrong-density,
omitted-correction and premature-resampling counterexamples, as well as
zero/negative lags, no-member identity, RNG restoration, finite resource caps
and source/value mutation checks.

The default audit uses the preceding audit's two lag contexts, three pairs
of AL scales, parameter points and fixed seed rule. It runs 384 guided
calculations at particle counts 1,16,64,256 and 288 matched bootstrap
calculations at 16,64,256. Sixteen replicates per group remain in the packet,
including ESS reviews or computational failures. Exact affine single-estimate
absolute log-evidence error must be at most 1e-8. This is a generated
conditional-reference gate, not an application precision certificate. An
empirical log-evidence gap is not a pointwise Jensen bound.
Member-stage ESS and initial-ancestor gates are two for both methods; the
N=1 algebraic reference necessarily uses one. Temporary post-correction ESS
is reported separately: it is not a resampling gate, since the next member
factor may cancel that correction. The receipt writer recomputes its pass
decision and summaries from the retained records before writing them.

From the clean committed worktree, using pinned R4.6:

```bash
mkdir -p local_trackers/glofas_guided_particle_qualification_20261105
Rscript --vanilla scripts/audit_glofas_guided_particle_qualification.R \
  --output "$PWD/local_trackers/glofas_guided_particle_qualification_20261105/fresh_audit"
```

The three registered focused tests also use text-only generated fixtures.
A reduced test budget is explicitly marked and cannot be mistaken for the
default audit. RDS files, posterior draws, runtime directories and logs
remain outside Git. Main integration requires a fresh isolated merge, focused
and combined repository tests, exact scope review and guarded CLI Git push
with remote readback. No manuscript compile is needed when every article
blob is unchanged; this stage does not publish Overleaf.

## Deterministic resource-boundary regression

The first combined guided integration run stopped in an older sampler test,
before reaching the new guided tests. That test allowed one millisecond
before the first callback and assumed exactly one callback would run. The
unchanged sampler correctly permits zero calls if the budget expires first,
so the test has an OS-scheduling-dependent assumption. Both states were
independently reproduced using controlled monotone clocks; the original test
also passed in isolation. The failed full run did not retain its exhaustion
object, so its exact callback count is not retrospectively asserted.

The corrected test supplies a synthetic clock to a private copy of the
sampler function and checks both pre-callback exhaustion (zero calls) and
post-callback exhaustion (one call), including their distinct failure
messages. Production code, budget thresholds and statistical gates are
unchanged. The original failed full-suite receipt is retained; success
requires a fresh complete combined-tree run, not a selective rerun that
discards the failure.

## Remaining native boundary

Exact affine H2 behavior does not certify the retained nonlinear H28 path,
joint parameter gradients or Gaussian variational-family accuracy. A native
adapter still requires changing-parameter continuation of both retained
DESNs, complete input/prior identities, a separately admitted read/resource
purpose, nonlinear proposal/weight checks and measured cost. Any locally
affine guide must retain the actual nonlinear member factors and exact f/r
correction. It must not replace the target by its linearization.

Only a subsequently qualified bounded median-AL comparison can justify a
broader all-family campaign. exAL and MQ require their own derivations and
tests. Current results, article inputs and Overleaf stay unchanged until a
coherent replacement passes the scientific gates. No full-result completion
date is inferred from generated reference timing.
