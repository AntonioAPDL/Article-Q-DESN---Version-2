# GloFAS specification reconciliation and collapsed future-path inference

## Scope and decision

This stage preserves the executed reference and discrepancy reservoirs for
the inference comparison. It does not alter application fits, prior
hyperparameters, observation/member weights, article assets or conclusions.
The unsuccessful fixed-parameter reference pilots remain retained. Their
completion and exact-coordinate checks do not make their poorly mixed paths
usable as posterior references.

The selected screening registry and executed application contain different
input/bias multipliers. This transfer discrepancy already exists in the
earlier application, before the recent change of future-response likelihood
and member-weight construction. It cannot by itself explain the difference
between the earlier and recent forecasts. Nor does it establish that the
two reservoir specifications are equivalent.

The explicit decision for a controlled inference comparison is to retain
the executed specification, not restore the screened multipliers. The new
reconciliation functions require that decision, compare the common feature
definitions and bind the preserved basis to the existing numeric replay
fingerprints. They do not modify the historical mapper or rebuild weights.
No model run is authorized by a successful metadata preflight.

## Two distinct reservoir specifications

For an effective input gain `g`, input sparsity `pi_in` and input dimension
`d`, screening sets both the input and bias multipliers to

```text
g / sqrt(pi_in * d).
```

The historical component-to-anchor mapper instead uses input multiplier
`g` and bias multiplier one. For the retained reference/discrepancy components
the input dimensions are 722/542 and sparsities are 0.1. The respective
screening multipliers are approximately 0.05884/0.04754, whereas the executed
input multipliers are 0.5/0.35 with both bias multipliers one. Candidate IDs,
widths and seeds agree, but those agreements are not complete feature-map
identities. A later change of this specification would require new feature
and target identities and matching coefficient fits.

The metadata audit checks the selected and anchor records, reused YAMLs,
source history and the previously authenticated numeric replay. It does not
open, hash or copy original RDS payloads. Its statements about historic
numeric objects are bounded by those authenticated receipts, not an
unperformed new read of those objects. The old mapper and frozen prediction
source remain unchanged.

## Why a new inference calculation is needed

The existing coordinate helpers reproduce their stated variational updates
on the small exact targets. Those approximations can nevertheless miss
coefficient--future-path covariance, scale marginals and AL tail quantiles.
A joint Gaussian coefficient/path factor would address a dependence
restriction in a Gaussian example but would not generally preserve the AL
future-response distribution. Iterating the same updates longer is not an
established remedy for that restriction.

The exact AL innovation transformation removes the future-response density
from its coordinate reference measure. It does not make centered Gaussian
coefficient or inverse-gamma scale conditionals valid when the innovations
are held fixed: the generated path then depends on these parameters. Any
such update requires its own derivation. The ordering of partially collapsed
and Metropolis updates also matters; it cannot be justified simply by naming
each individual conditional distribution
([van Dyk and Jiao, 2015](https://arxiv.org/abs/1309.3217)).

## Collapsed parameter target

Let `eta` collect coefficients, scales and shrinkage parameters, and let
`pi_H(eta)` denote their historical target, including the original priors.
For fixed `eta`, let `P_eta(Y)` be the normalized causal future-response law
and `L_G(Y,eta)` the product of all ordinary issued-member likelihood factors.
Define the future-member evidence

```text
Z_G(eta) = integral P_eta(Y) L_G(Y,eta) dY.
```

The parameter target is proportional to `pi_H(eta) Z_G(eta)`. The conditional
future-path law is proportional to `P_eta(Y) L_G(Y,eta)`. Thus a structured
approximation using the conditional path law has collapsed objective

```text
E_q [log pi_H(eta) - log q(eta) + log Z_G(eta)].
```

When members are absent, `Z_G` equals one exactly: a normalized, unobserved
future-response law must not add information to the historical parameter
target. With members, their integrated likelihood can update the parameters.
Dropping that term while retaining the paths would introduce a cut model,
not implement the stated joint target.

Where differentiation under the integral is justified, the fixed-path Fisher
identity is

```text
gradient_eta log Z_G(eta) = E_(Y|eta,G) [
    gradient_eta log P_eta(Y) + gradient_eta log L_G(Y,eta)].
```

This identity concerns the derivative of the exact collapsed target. It is
not automatically the gradient of a finite-particle expected-log objective.
Any log-scale coordinate Jacobian belongs in the parameter target exactly
once, with `log q` expressed in the same coordinates.

## Particle calculation and its limits

The generated implementation evaluates causal AL paths and issued-member
weights sequentially. At horizon `h`, the member location uses the path
through `h-1`; all 51 factors enter before propagating the current future
response from its normalized AL law. Adaptive multinomial resampling retains
the normalizing-constant accounting. Log weights, effective sample sizes and
ancestry are recorded; a concentration of ancestry is not concealed by a
uniform set of weights after resampling.

A positive unbiased estimate `Zhat_G` obeys

```text
E [log Zhat_G(eta)] <= log Z_G(eta).
```

The inequality applies to the expectation, not every realization. Replacing
the collapsed log evidence by this expectation gives a lower bound. It does
not make an individual particle run an exact posterior or establish adequate
numerical precision. This distinction underlies particle variational methods
([Naesseth et al., 2018](https://proceedings.mlr.press/v84/naesseth18a.html);
[Maddison et al., 2017](https://proceedings.neurips.cc/paper_files/paper/2017/hash/fa84632d742f2729dc32ce8cb5d49733-Abstract.html)).

The implemented objective allows varying parameter and scale draws rather
than substituting a fixed point. It does not provide a qualified application
optimizer. In particular, differentiating the expected-log objective through
parameter-dependent resampling requires the appropriate terms or an
explicitly declared gradient approximation. No resampling gradient is
silently omitted or relabelled as exact. A successful known-target test is
not an assertion that a bootstrap proposal will be adequate for the retained
nonlinear reservoirs and all member factors.

The finite-particle Jensen gap can depend on the parameters. Unbiasedness of
`Zhat_G` therefore does not establish accurate parameter marginals after
optimizing its expected logarithm, even if `q` is flexible. Qualification must
compare joint parameter/path moments and relevant quantiles as particle
accuracy increases, not merely check finite weights or effective sample size.

## Reporting quantity and dependency scope

The current future-reporting function evaluates the stated Gaussian path
factor quantile, `m_h + sqrt(V_hh) Phi^(-1)(p)`. Source inspection does not
identify an indexing or scoring error in that calculation. Historical AL/exAL
curves instead evaluate fitted conditional quantile locations. Those curves
and the ensemble-conditioned, future marginal quantiles are different
functionals; their visual difference alone does not identify an inference
defect. Replacing a marginal future quantile with its conditional location
would change the reported estimand, not correct the Gaussian approximation.

Any qualified remedy must retain the intended marginal forecast quantity
and make its approximation explicit. Its numerical dependency surface should
be established before refitting: a change confined to future-path inference
does not automatically require new historical screening or every preceding
application fit. Reuse of an unaffected baseline still requires its complete
target, design, prior, reporting and source identities; it is not justified
solely by a shared model label.

## Qualification and deployment boundary

Independent generated references examine coefficient and scale uncertainty,
normalizing constants, conditional CDFs, member updating and fixed-path
derivatives. The one-horizon joint-parameter reference uses one shared
response/member scale; the two-horizon reference uses an uncertain response
scale and fixed member scale. These controlled targets are not claimed to
reproduce the application's complete source-specific scale hierarchy.
The RHS checks retain the implemented product-hierarchy
convention and global inverse-gamma shape `(r+1)/2` for `r` penalized slopes;
they do not substitute the normalized Piironen--Vehtari hierarchy because
conditional coefficient variances happen to agree.

The small Normal-prior examples and prior-algebra tests do not qualify the
full RHS, exAL support/shape block, multiquantile paths or 2,502-coefficient
application. A complete parameter optimizer, accurate and cost-qualified
particle proposals, preserved full priors, native input/source/resource
admission and a bounded median-AL application comparison remain required
before production. There is no automatic broad refit, forecast scoring or
article publication in this stage.

New tests are registered with the repository harness. All evidence produced
by the metadata and generated-reference drivers remains ignored. Integration
uses a fresh worktree, preserved source commits and command-line Git. The
article projection and existing results remain unchanged until a separate,
complete scientifically qualified packet is frozen.
