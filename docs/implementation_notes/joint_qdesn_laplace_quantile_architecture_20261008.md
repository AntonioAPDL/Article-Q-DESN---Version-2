# JOINT Laplace quantile-aware architecture experiment

Date: 2026-10-08

## Scientific decision

The difficult Laplace Bridge cell remains broad and worse for both joint AL and
joint exAL after the completed fixed-backbone prior and coupling experiments.
Those experiments localized most point-score loss to the reservoir coefficient
block, found no material functional convergence failure, and found no useful
gain from relaxed exAL slabs. Repeating a broad DESN search, tau0 screen, gamma
sampler screen, or joint-prior grid would therefore duplicate completed work.

The remaining non-duplicative question is whether the Gaussian screen selected
the wrong member of a near-tied architecture frontier for quantile forecasting.
This lane re-ranks only archived, verified Laplace Bridge architectures using
the quantile models themselves. The successful Asymmetric Laplace Tail case is
retained as a reference and is not refitted.

## Frozen design

The archived expanded screen is accepted only after its 18,432 ridge jobs,
7,680 Gaussian-RHS jobs, terminal status, top-level manifests, and all 24 RHS
workers supporting the shortlist verify. The shortlist contains the current
baseline plus seven deterministic farthest-point choices from architectures
within 2% of its Gaussian calibration score. Diversity is measured over depth,
state count, output lags, leakage, spectral radius, recurrent and input
connectivity, input scale, and width shape. No quantile result enters this
freeze.

Each architecture uses three matched internal selector replicates. Fits use
350 training rows and 150 calibration rows. Origins are teacher forced, while
each 30-step horizon is recursive and feeds back the contracted median
quantile. The protected article fixture is not used. The nested initialization
graph is Gaussian RHS, median-outward independent AL, paired independent exAL,
joint AL, then joint exAL. The architecture and tau0 remain shared across all
four model rows.

An architecture advances only when mean DGP-integrated finite-grid score is
lower than the baseline for both joint AL and joint exAL and the equal-weight
mean relative score across all four rows is also lower. At most two candidates
advance: the best balanced candidate and the best joint-average candidate,
deduplicated. If none passes, the campaign stops.

The fresh-seed MCMC screen uses two replicates, two chains, AL 2,000/500/thin 2,
and exAL 4,000/1,000/thin 2. At most one challenger advances. Confirmation uses
two new replicates, three chains, AL 4,000/1,000/thin 4, and exAL
8,000/2,000/thin 4. Every exAL chain uses exact M0
`M0_v_collapsed_support_logit`; exAL VB uses `VB1_structured_v`.

Finite scores and zero contract crossings are hard requirements. Scalar and
functional mixing diagnostics are retained but are review-level unless the
forecast behavior is pathological. A positive confirmed mean improvement is
scientific evidence even if posterior score intervals overlap. This experiment
does not authorize an article replacement or Overleaf publication.

## Runtime and stop rules

The launcher accepts at most 15 distinct physical cores, pins one process per
core, forces one numerical thread, requires 50 GiB free on `/data`, and refuses
cores with measured or affinity-reserved conflicts. `schedule` mode performs
no fitting until the capacity gate passes. The controller stops after one
confirmation and never recursively expands the search.

## Reproducibility surface

- contract: `application/config/joint_qdesn_laplace_quantile_architecture_contract_v1.csv`;
- implementation: `application/R/joint_qdesn_laplace_quantile_architecture.R`;
- controller: `application/scripts/joint_qdesn_laplace_quantile_architecture.R`;
- capacity gate: `application/scripts/joint_qdesn_laplace_quantile_architecture_capacity.R`;
- launcher: `application/scripts/launch_joint_qdesn_laplace_quantile_architecture.sh`;
- focused test: `application/tests/test_joint_qdesn_laplace_quantile_architecture.R`.

Runtime roots, posterior draws, model objects, logs, and local tracker plans
remain ignored. Main, article files, Overleaf, PriceFM, GloFAS, Phase182, and
all historical JOINT runtimes are outside this lane.

## Completed campaign

The Jerez campaign closed with 180/180 tracked work units, 96/96 MCMC chains,
zero failures, nine verified freeze entries, and five verified closeout
artifacts. `arch_02` passed the predeclared shared-backbone gate. Relative mean
scores versus `arch_00` were 0.6350 for joint AL, 0.7992 for joint exAL,
0.9059 for independent AL, and 0.9662 for independent exAL. Average joint
score-interval widths fell by 95.41% and 94.08%. One joint-AL quantile
functional remained review-level, while score R-hat, ESS, chain ranges, and
state-half score sensitivity were stable; this is not a hard rejection under
the frozen policy.

The scientific claim is case-specific fresh-seed evidence, not article
supersession. The separately frozen matched article-fixture confirmation is
documented in
`docs/implementation_notes/joint_qdesn_laplace_architecture_article_confirmation_20261008.md`.
