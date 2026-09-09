# JOINT Q--DESN common-posterior contract repair

## Status

`IMPLEMENTATION_READY_SCIENTIFIC_RESULTS_REQUIRE_COMPLETE_REFIT`

## Purpose

The completed Phase181, Jerez article-confirmation, and Phase182 calculations
remain retained historical evidence. They are not changed or deleted by this
repair. The independent single-quantile validation is separate and remains
valid. This change prepares a new, complete four-model JOINT comparison; it
does not launch a fit or alter the article.

## Corrected contract

Every variational fit and every MCMC chain for a given model cell must use one
posterior target. The target record includes the likelihood family, fitting
responses and design, quantile grid, coefficient hierarchy, likelihood power,
global and slab scales, intercept prior, ordering rule, scale support, score,
monotone projection, and independent-draw coupling convention. Its SHA-256 is
independent of the chain seed. Chain dispersion may change only initial
coefficient, intercept, scale, shape, and latent-variable values.

The corrected scientific specification uses:

- the first quantile-specific coefficient vector as the anchor and adjacent
  coefficient differences thereafter for joint fits, with separate
  quantile-specific RHS priors for independent fits;
- the corrected global variance shape `(block_size + 1) / 2`;
- a fixed finite slab variance of one, held fixed in both MCMC and VB and
  consistently labeled as a regularized horseshoe prior;
- Gaussian-location quantiles as the empirical-Bayes intercept-prior centers,
  resolved once per mechanism;
- twice the Gaussian residual standard deviation as the common intercept-prior
  standard deviation;
- ordered intercepts for joint fits only;
- positive, unbounded scale support, represented by `c(0, Inf)`, with no
  upper bound derived from a chain start; and
- the existing DGP-integrated seven-level score and equal-weight isotonic
  reporting rule, augmented by a repeated-permutation coupling sensitivity.

The intercept-prior centers and scale are empirical-Bayes quantities. They are
frozen before comparative evaluation and shared by VB and MCMC. They are not
chain starting values.

## Source changes

`application/R/joint_qdesn_posterior_contract.R` creates and compares
canonical target hashes and rejects initialization objects containing target
fields. The article-confirmation worker now resolves prior and support fields
from the frozen Gaussian initializer and contract before applying chain
dispersion. It writes the target contract and hash beside each MCMC result.

The shared AL and exAL MCMC routines now accept the natural positive,
unbounded scale support. Existing finite numerical bounds remain accepted for
historical callers, but the corrected contract uses no finite upper cap. The
independent exAL dispatcher now maps vector intercept-prior centers and scales
to the corresponding probability level.

The confirmation closeout now requires every worker to record its target hash,
requires one hash across all chains in a model cell, checks the prescribed
number of chains for each likelihood family, and covers all 32 model cells.
The MCMC target is therefore auditable without treating a starting value as a
prior hyperparameter.

## Required scientific rerun

The new JOINT result must refit all 32 cells: eight mechanisms crossed with
independent AL, joint AL, independent exAL, and joint exAL. Each cell uses five
chains, for 160 MCMC workers. Pre-correction VB summaries cannot serve as fitted
evidence; the full median-outward VB initialization sequence must be rerun.

No old and new cells may be mixed. Article replacement requires a complete
frozen packet, verified manifests, all posterior-target hashes, score and
crossing diagnostics, and a separate coordinator review.

## Protected evidence and active-work boundary

The completed Jerez runtime remains ignored and retained at
`Article-Q-DESN---Version-2__wt__joint_article_confirmation_jerez_review_20260908/application/cache/joint_qdesn_shared_backbone_article_confirmation_jerez_20260907`.
Its frozen transfer inventory was verified at 2,867 files and 470,322,631
bytes. Subsequent closeout auditing added two local audit records, so the
current retained snapshot contains 2,869 files and 470,784,073 bytes. Neither
the historical runtime nor its audit records belong in Git or in a corrected
campaign.

At the 2026-09-09 capacity audit, Muscat had 64 logical CPUs, but an active
20-worker PriceFM shard occupied the upper CPU set and a GloFAS Part 4
continuation was still running. Memory and disk space were adequate, but
Muscat did not have an interference-free 50-worker allocation. The official
corrected campaign should therefore run once on Jerez after its PriceFM work
releases 50 CPUs. Muscat is restricted to tests or a small, separately tagged
pilot after another capacity check.

## Verification

Under R 4.6.0, the posterior-contract, AL and exAL MCMC, AL and exAL VB,
structured exAL, inference-dispatch, precision-repair, RHS global-shape,
shared-backbone continuation, and score-packet tests pass. The complete
`application/tests/run_tests.R` harness also passes. The host-specific article
confirmation test reaches its intentional Muscat guard because the retained
source-evidence worktree is attached rather than detached; that worktree is
not modified merely to satisfy a host provenance check. All changed R files
parse and `git diff --check` passes.

## Execution boundary

This repair performs no scientific launch and publishes no manuscript or
Overleaf file. The preferred production host is Jerez after PriceFM releases
the requested CPUs. Muscat may run portable tests and a deliberately small
pilot only after an explicit capacity and non-interference check; it must not
run a duplicate official campaign.
