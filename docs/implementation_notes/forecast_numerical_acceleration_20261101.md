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

## First authentic qualification results

At source `a099aba928e6d1fb01931a4b12466125bbb2bc64`, the registered
repository suite passed in 563.08 wall seconds (508.89 CPU seconds), including
3,181 new checks. One pre-existing optional external-engine adapter was
skipped. These are software checks, not scientific campaign completion.

The authentic IND probe completed all six particle calculations in 809.33
CPU seconds. Guidance reduced resampling to 30--42 of 500 observations,
compared with approximately 430--471 under the earlier bootstrap proposal.
However, only 13 of 27 prespecified resolution agreements passed. The probe
therefore remains REVIEW; high median ESS does not certify filter accuracy.

The authentic MQ probe compared 122,880 recursive responses, 860,160
conditional-kernel values and 210 integrated quantiles with the unchanged
scalar reference. Every difference was exactly zero. Training wall time fell
from 97.416 to 15.809 seconds, a 6.162-fold speedup. Of 210 requirements,
122 split diagnostics and 128 independent-CDF certificates passed. All
validation mean brackets contained their target probability, but the
confidence bounds were too wide for some endpoints. This is REVIEW, not a
waiver or a basis for publishing results.

The private packets retain all original matrices, streams, checks, resource
charges and hash inventories. No unsuccessful evidence is replaced by a
later calculation. The manuscript and its reported results are unchanged.

## Prospective precision extension

A separate opt-in purpose increases training integration to 65,536 paths.
Its candidate quantiles and .01 absolute-OR-relative tolerance endpoints
are fixed before generating new validation paths. The training split
criterion remains .005 absolute OR relative; failure stops the purpose
before validation rather than spending more computation on an ineligible
candidate.

Validation uses fresh path IDs 65,537--327,680, with only three allowed
looks at 65,536, 131,072 and 262,144 validation paths. Each look receives
failure probability .05/3. Applying the endpoint/side union within each
look and then the finite union across looks controls the declared .05
error probability, conditional on the training candidates and fixed
draw/origin. Optional inspection at unlisted sample sizes is not allowed.
The candidate is not moved in response to validation outcomes.

Validation retains Welford counts, means and second central moments,
per-block data and path-ID hashes, and the frozen contracts and all
look-level bounds. It does not retain a new full validation matrix. This
prospective storage policy is explicit; old validation matrices remain
retained. Streaming moments reproduce the same sample variance used by
the fixed-sample bound. Neither this variance calculation nor its hash
chain authenticates the source or establishes iid sampling on its own;
the source-bound qualification separately verifies the generation procedure.

The extension inherits the authenticated 4,096-path scalar/batch parity
receipt, rechecks all its artifact hashes and unchanged executable-source
pins, and adds predetermined scalar checks at larger path IDs. It has its
own finite CPU, wall, memory, storage and lifetime contract. A failed split,
parity check, source pin, resource limit or final certificate remains a
failure or REVIEW, with no automatic budget renewal or production dispatch.

## Native independent-study parameter catalog

The retained dynamic-model inventory contains 54 chain-specific fits:
27 AL fits from source C72/version 1.0.0 and 27 exAL fits from source
7ace/version 1.1.1. Each fit retains 20,000 native post-burn parameter
columns. The legacy 4,000 metric-draw labels instead identify generated
metric summaries; they do not establish a map to native MCMC columns.

An explicit enrollment reads one protected fit at a time, authenticates its
full payload, native source and retained model specification, and validates
the observed response prefix, state/auxiliary axes, support and pairing.
The catalog records original columns and iterations without thinning,
namespace replacement or parameter re-estimation. Three equal-sized chains
give 60,000 equally weighted native static draws per model cell, with weight
1/60,000. This is the empirical training-parameter measure supplied to later
reconstruction; catalog validation does not certify the historical posterior
target or the accuracy of a subsequent conditional filter.

The historical `old_realization_reproduced` flag concerns agreement between
old and replayed metric calculations. It is not a test of whether two models
use the same simulated series. Source checks separately establish the
observed/evaluation series identity, and enrollment rechecks the actual
500-observation fitting prefix and its transformations. The original flag
and its narrower meaning remain recorded rather than discarded.
