# Reconstructed full-state initialization: scientific audit and consumer design

This is a read-only stock-CAVI audit and bounded future-consumer design. No full
state was constructed for a new optimizer, no target update was run, and no new
posterior attempt is admitted.

## What the actual stock implementation does

Pinned CRAN 1.1.1 `utils.R` lines 1556–1577 consume only `init$beta` and
`init$sigma`. They reset V to prior V0, RHS factors through `init_vb()`, ell/nu
and chi to ones, psi to one, Elog-v to zero, iteration/stable counters to zero,
formal convergence to false and trace to empty. Supplying extra full-state keys
to this interface does not restore them.

The first Gaussian update at lines 1597–1613 overwrites supplied beta before
updating residual/latent moments. Supplied beta primarily affects the first
reported delta. The order is Gaussian beta, RHS update, residual moments, GIG
latents, inverse-Gamma sigma, ELBO, then the joint stopping test. The Gaussian
update currently forms an inverse-product mean and may silently add 1e-10 I
after a failed Cholesky; a future target-preserving consumer must factor the
original precision or stop and explicitly record the event.

There is also an important sigma distinction. The retained compact sigma comes
from `fit$qsig$E_sigma`, as confirmed by the pinned adapter. Stock initialization
sets a=1+1.5n and b=a*sigma0. Feeding the retained mean back as sigma0 therefore
initializes E[sigma]=a/(a-1) times that saved mean. For LT this relative difference
is 1/135360, about 7.39e-6. Reconstructing the original reported mean instead
requires b=(a-1)*sigma. This b is a variational rate; the actual sigma-prior
hyperparameters must remain a_sigma=b_sigma=1.

The full original return at lines 1707 onward contains qbeta, qv, qsig, RHS state
and controls, trace and convergence information before wrapper compaction.
Existing compact artifacts discarded those intermediate factors and optimizer
scheduling/RNG boundary. Their recovery cannot be labeled an exact resume.

## What LT establishes and what it leaves open

LT reproduces all seven stored scalar measures, both objectives, RHS iteration
counts and residuals exactly. Six independent component gates pass; its objective
gate remains about 3.813 times its limit under either objective formulation.
This is evidence of drift under the specified computational fixed-point map.
It does not prove that every contribution is genuine mathematical posterior
drift, because the Gaussian precision is ill-conditioned and covariance forward
accuracy remains unresolved. The tested objective-only arithmetic rewrite is
not a repair.

Conditional reconstruction can create a valid new variational distribution:
retain m and positive-definite V, set the sigma shape/rate consistently with the
reported mean, reconstruct RHS factors from the pinned original prior recipe,
and derive shape-1/2 GIG factors in the original design units with the exact
floors. Such factors need not be mutually stationary to define a valid product
distribution. They are an initializer for a new algorithmic trajectory, not
the missing original optimizer state, and they carry no recovered stable count,
convergence flag or trace.

This can be scientifically justified as a future initialization mechanism if
fixed-state evidence shows that discarding coherent near-stationary factors is
the relevant obstacle and a consumer is proved to ingest them. LT alone does
not establish that claim or guarantee improved convergence. A stock beta/sigma
warm start is not that consumer.

## Minimal explicit consumer contract

A future schema must bind the posterior target, original design/response units,
source/runtime hashes, prior factory/normalized controls and state provenance.
Required variational fields are m, full V, sigma a/b and its derived moments,
RHS shapes/rates/moments and controls, GIG shape/chi/psi/ell/nu/Elog-v, n/p/tau,
and the exact update order and floor conventions. Shapes, rates, dimensions,
SPD covariance and every derived moment need validation.

Prior inputs remain zero center, V0=diag(1e6), unchanged RHS tau0 and slab
hyperparameters, unshrunk intercept, no freeze warmup, and sigma prior IG(1,1).
Posterior factors must never be repurposed as prior center, prior V0 or prior
sigma rate. The stock normalization and all objective constants remain fixed.

Reset the new consumer's iteration, stability, formal flag and trace explicitly.
Record the initial objective and all acceptance measures before any update.
Use deterministic RNG with a recorded pre/post-sampling boundary; numerical
variational initialization does not itself reconstruct old posterior draws.
Retain the complete new return for reproducibility if a future fit is admitted.

## Proof and admission sequence

1. On the existing bounded synthetic states, prove import validation and state
   round-trip, original-unit prior invariance, and correct sigma-mean semantics.
2. Show zero-update consumption preserves all supplied factors and objective;
   reject silently ignored fields, reset covariance/latents, stale source hashes,
   changed units/prior controls or inherited convergence flags.
3. Compare one diagnostic block against an independent same-state map with
   identical update order. All computational work receives an explicit budget.
4. If numerical/algorithmic evidence supports the mechanism, prepare a separate
   posterior-attempt manifest with whole-attempt pricing, total-update history,
   initializer provenance and original AL300/Normal2000 policy constraints.

The current diagnostic envelope authorizes zero posterior fits. A full-state
start must not hide an effective extension of the old 300 updates, reset a
cumulative budget, or disguise AL600 as two calls. If the existing total-update
policy forbids that new trajectory, it cannot run without a separately explicit
policy decision. No such decision is inferred here. Formal OR independent
acceptance and the unchanged independent gates remain mandatory.
