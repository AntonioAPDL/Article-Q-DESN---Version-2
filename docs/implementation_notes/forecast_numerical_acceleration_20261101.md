# Conditional-filter guidance and batched forecast qualification

## Scientific scope

This additive implementation continues the approved independent-study
specification: retain the empirical training-parameter measure, integrate
latent-state and auxiliary uncertainty, and use the fitted covariance rule
consistently. It also accelerates the existing seven-level MQ recursive
forecast calculation without changing its response law or coupled posterior
draws. It neither fits parameters nor supplies production or publication
authority. Active GloFAS fits and the manuscript are unchanged.

The previous bootstrap filter completed its authentic numerical probe, but
its low effective sample sizes and resolution variability did not establish
accuracy. Likewise, the original MQ 4096-path qualification remains REVIEW.
Those results and their computational charges remain retained. A faster
calculation is not, by itself, a more accurate or promotable calculation.

## Observation-guided conditional filtering

At a fixed static parameter value and ancestor, let the state projection
before observing y be L~N(m,S), with m=F'a and S=F'RF. The covariance
R uses P=GCG', W=D elementwise P and R=sym(P+W), as in the native forward
operator. It depends on the preceding auxiliary history, not the current v.

Under AL_p scale sigma, write d=y-m, a=p/sigma and b=(1-p)/sigma. Splitting
the scalar convolution at L=y gives

\[
 K_- = e^{-ad+a^2S/2}\Phi(d/\sqrt S-a\sqrt S),\qquad
 K_+ = e^{bd+b^2S/2}\Phi(-d/\sqrt S-b\sqrt S),
\]
\[
 g(y)=\frac{p(1-p)}{\sigma}(K_-+K_+),\qquad
 F_Y(y)=\Phi(d/\sqrt S)-(1-p)K_-+pK_+.
\]

The implementation uses log-tail/positive-sum expressions to avoid
cancellation, with the exact AL limit at S=0. Conditional on y, L is a
mixture of N(m+aS,S) truncated below y and N(m-bS,S) truncated above y,
with weights proportional to Kminus and Kplus. Then, for native
A=(1-2p)/(p(1-p)) and B=2/(p(1-p)),

\[
 v\mid y,L\sim\operatorname{GIG}\left(\tfrac12,
          \frac{(y-L)^2}{B\sigma},\frac{A^2}{B\sigma}+\frac2\sigma\right).
\]

This composition samples the locally optimal observation-guided proposal
for v. The temporary L is discarded: the retained Gaussian state is updated
conditional on v, not conditioned on a second artificial observation L.
The particle weight increment is g(y). Weights still normalize within one
fixed static parameter; no later response reweights the parameter population.

For exAL, condition on its native half-Normal auxiliary, subtract its
sigma*C_r*abs(gamma)*s shift and apply the AL calculation at native r, not
p. The initial implementation proposes s from its prior and guides v
conditionally. The shape-zero limit reproduces AL. Supplied open-unit
innovations determine the entire calculation; the modules generate no RNG.
Zero-residual GIG sampling uses its Gamma limit without a zero midpoint.

The guided filter retains weighted pre-resampling checkpoints, ancestry,
ESS, numerical underflow and likelihood normalizers. Prefix causality,
native covariance propagation and destination support are explicit tests.
It remains a finite-particle approximation. Analytically exact local
guidance does not make the complete finite filter exact.

## Terminal auxiliary integration

For known deterministic future F/G, the predictive mean/state covariance at
horizon h depend on auxiliaries through h-1, not current v_h. Integrating
current v_h with the Normal-plus-AL CDF removes that auxiliary's Monte Carlo
variation. At H1, this is exact conditional on the supplied origin mixture.
It does not remove origin-filter approximation error.

Future exAL half-Normal variables affect only observation offsets, not the
covariance-control history. Their terminal contribution can be integrated
by one-dimensional quadrature. QUADPACK's reported absolute error is a
numerical estimate, not an interval-arithmetic probability guarantee.
Training auxiliary uncertainty still needs filtering. These reductions
must not be applied to DESN features depending on unobserved future responses.

## Opt-in MQ batching and original scientific streams

The new adapter batches path-specific states, lag features and readouts.
It preserves updated-lower/old-own reservoir recurrence, layer/projection
order, transformations, all original parameter rows, cross-level coupling,
equal-weight isotonic action and endpoint-clamped response simulation.
No feature, coefficient or quantile average replaces a path calculation.
Unsupported designs fail rather than silently taking a different model.

The default batch RNG uses one scoped native context while retaining each
original purpose key. An explicitly selected R4.6 first-step optimization
evaluates the same CMRG first uniform directly for the six positive 28-bit
purpose-state words. The original hash key, serializer, generator and
reference helpers remain unchanged. Seed words and uniforms are checked
bit-for-bit against native R; complete scalar/batched trajectories and
quantiles must additionally pass authentic-source qualification.

The exact local R4.6 RNG.c source SHA is
6ef2c5d552c087cd57e0ef49386e01e0174b40433e4ad8d572461b20c958450e.
An adapter's declaration is not authentication: the external qualification
must pin the actual source, runtime and byte identities. No existing
production loader opts in merely because this module exists.
The experimental adapter lives in `scripts/integrated_quantile_mq_batch.R`,
alongside the other qualification components, not in the frozen production
application module surface. Original source guards and their exact scientific
inventories remain unchanged; the new bounded CLI pins this extra helper.

## Independent future-CDF validation

The previous response-DKW diagnostic is retained, not retroactively changed.
A separate prospective certificate chooses quantile candidates using training
paths and evaluates their fixed tolerance endpoints using disjoint future
validation paths. Each validation value is a conditional CDF in [0,1].

For n iid validation paths, sample variance s2, M predeclared endpoints and
total failure probability alpha, use

\[
 r_n=\sqrt{2s^2\log(4M/\alpha)/n}
            +\frac{7\log(4M/\alpha)}{3(n-1)}.
\]

The radius follows from the two-sided finite union of
[Maurer and Pontil (2009), Theorem4](https://www.cs.mcgill.ca/~colt2009/papers/012.pdf).
For a candidate bracket [L,U], certify the target quantile only if
UCB(F(L))<p and LCB(F(U))>=p. Candidates may not be chosen using those same
validation paths. Existing .01 absolute/relative value limits and .005
split diagnostic limits remain unchanged. Failure remains REVIEW.

This bound concerns future iid trajectory integration at one original
parameter draw/origin. It does not certify dependent particle-filter draws,
stratified weighted origin components, source provenance or an entire
campaign's familywise error. Exact H1 output requires an authenticated
deterministic-first-kernel proof, not observed zero sample variance.

## Qualification and integration gates

The two new CLIs require clean frozen source, SHA-pinned original evidence,
new ignored output namespaces, finite lifetime/CPU/wall/memory/output limits,
fixed purpose geometry and single-thread bundled R4.6 numerical execution.
They retain early progress, unsuccessful receipts, all random streams,
output inventories and explicit no-production/no-scoring status.

The IND purpose uses one authenticated AL column, six prospectively fixed
particle calculations and H1 diagnostics at three training prefixes. Even
successful resolution agreement is not full filter accuracy certification
or enrollment of all source-version/likelihood cases. The MQ purpose uses
the same authentic draw/origin as the historical Q2, compares scalar/batch
outputs before validation, and records independent-CDF bounds separately.

All focused tests, original source guards and the registered combined suite
must pass before Git-only source integration. Original runtime and failed
evidence remain ignored and retained. Full scientific reconstruction still
requires authentic complete draw maps, separately qualified filtering and
future integration, representative full-inventory cost and fresh host grants.
No new parameter fit, partial-result promotion or manuscript publication is
implied by a passing code or numerical-unit test.
