# JOINT Q--DESN corrected article-comparison handoff

## Decision

```text
COMMON_POSTERIOR_REPAIR:        INTEGRATED_IN_AUTHORITATIVE_MAIN
CORRECTED_EXECUTION_WORKFLOW:   READY_FOR_JEREZ_PREFLIGHT_AFTER_GIT_FREEZE
SCIENTIFIC_PRODUCTION:          NOT_LAUNCHED
CURRENT_JOINT_ARTICLE_RESULTS:  PROVISIONAL_PENDING_COMPLETE_REFIT
INDEPENDENT_VALIDATION:         UNCHANGED_AND_VALID
OVERLEAF:                       OUT_OF_SCOPE_UNTIL_RESULT_REVIEW
```

This handoff defines one complete replacement comparison for the JOINT
simulation study. It does not authorize a partial rerun, reuse of fitted
historical cells, or a second official campaign on Muscat.

## Git authority

The common-posterior repair is already part of authoritative main:

```text
Authoritative main: edf751e663977a13ba4e5eebc42219723efcae68
Merge parent 1:     cb943501027b35dd26d0db22eda71dfbfdebb743
Merge parent 2:     a7cf3232c4bc1fce9ad71abe1a416f431c4f22a8
```

The execution implementation belongs only to:

```text
Branch: work/joint-qdesn-corrected-article-comparison-jerez-20260909
Base:   edf751e663977a13ba4e5eebc42219723efcae68
```

Before any Jerez preparation, fetch with command-line Git and require the
remote branch to be clean and exactly synchronized with its upstream. Record
the final branch HEAD in the preflight report. Do not rebase the frozen
execution branch onto unrelated in-progress scientific work.

## Why the complete JOINT comparison must be repeated

The independent single-quantile study is not affected. The problem is confined
to the preceding JOINT article-confirmation implementation: dispersed
chain-specific intercept starting values could also become proper-prior
centers. This changes the posterior target across chains. The earlier JOINT
numbers remain useful historical sensitivity evidence, but they cannot be the
final evidence for the stated common posterior model.

The corrected implementation separates posterior specification from numerical
initialization. For each model cell, all five chains now share an immutable
posterior-target record and SHA-256. Chain dispersion changes starting values
only. The corrected specification also makes the following choices explicit:

- joint slopes use a first-quantile anchor and adjacent differences;
- independent fits use separate quantile-specific RHS priors;
- the global variance shape is `(block_size + 1) / 2`;
- the RHS slab variance is fixed at one in VB and MCMC;
- intercept-prior centers are the Gaussian-location quantiles, resolved once
  per mechanism, with a common prior standard deviation equal to twice the
  Gaussian residual standard deviation;
- only joint fits use ordered intercepts;
- the likelihood scale has support `(0, Inf)` and no bound derived from a
  chain start;
- the primary score is twice check loss integrated over the seven-level grid
  with the frozen trapezoidal weights; and
- joint draws retain their cross-level identity, whereas independent fits use
  seeded within-chain permutations with repeated-permutation sensitivity.

## Protected historical evidence

Do not delete, edit, extend, or use as a destination:

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_article_confirmation_jerez_review_20260908/application/cache/joint_qdesn_shared_backbone_article_confirmation_jerez_20260907
```

The frozen transfer contained 2,867 files and 470,322,631 bytes. Two later
audit records raised the retained local snapshot to 2,869 files and
470,784,073 bytes. Phase181, Jerez-v1, and Phase182 outputs must remain
separate from the corrected packet.

The corrected runtime is a new ignored directory:

```text
application/cache/joint_qdesn_corrected_article_comparison_jerez_20260909
```

## Frozen source evidence

The preparation step requires this independent, detached source worktree on
Jerez:

```text
Worktree: /data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_shared_backbone_all_families_20260906
HEAD:     50cb2478bcbb9f59abf03203084b86e0a1d44ee6
Runtime:  application/cache/joint_qdesn_shared_backbone_family_campaign_20260906
```

Required source counts are 7,560/7,560 completed jobs, zero failures, eight
selected backbones, 56 aggregate VB rows, 14 source contrasts, and 32 future
article cells. The v2 contract records and verifies all eight frozen artifact
hashes. The source worktree must be detached and clean; do not switch its
branch merely to satisfy the guard.

## Complete execution graph

| Stage | Required work | Count |
|---|---|---:|
| Gaussian initialization | One Gaussian RHS fit per mechanism | 8 |
| Independent AL VB | Seven levels per mechanism, initialized from the median outward | 56 |
| Independent exAL VB | Each level initialized from its matching AL fit | 56 |
| Joint AL VB | One fit per mechanism after the complete independent AL grid | 8 |
| Joint exAL VB | One fit per mechanism after the complete independent exAL grid | 8 |
| Compact initializers | One for each mechanism--model cell | 32 |
| MCMC | Five chains for every one of the 32 cells | 160 |
| Contrasts | Joint minus independent within likelihood and mechanism | 16 |

All 136 VB components must be rerun. No pre-correction VB initializer, MCMC
worker, score cell, or favorable historical value can enter the new packet.

## Jerez capacity and environment gate

Jerez is the only authorized production host for this campaign. Wait until the
PriceFM campaign and any other user-owned PriceFM, GloFAS, or Phase182 process
on Jerez has stopped. Then verify at least 50 logical CPUs are available for
this work, at least 100 GiB is free on `/data`, and every numerical library is
restricted to one thread. The workflow checks the host, source and runtime
paths, R installation, library root, CPU count, free space, competing
processes, branch synchronization, and launch locks.

Required runtime:

```text
Rscript:  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript
Library:  /data/jaguir26/local/opt/R/4.6.0/lib64/R/library
Workers:  50 maximum
Threads:  1 per worker
```

Muscat currently has active PriceFM and GloFAS work and is not authorized for
the official 50-worker campaign. It may be used only for portable tests or a
separately tagged small pilot after a new capacity review. Never run duplicate
official campaigns on both hosts.

## Required Jerez procedure

Use command-line Git only. In a fresh Jerez execution worktree checked out on
`work/joint-qdesn-corrected-article-comparison-jerez-20260909`:

```sh
git fetch origin --prune
git status --short --branch
git rev-parse HEAD
git rev-parse '@{upstream}'
git rev-list --left-right --count '@{upstream}...HEAD'
```

Require a clean status and `0 0` divergence. Then run the portable gates:

```sh
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/tests/test_joint_qdesn_posterior_contract.R
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/tests/test_joint_qdesn_corrected_article_comparison_contract.R
bash -n application/scripts/launch_joint_qdesn_corrected_article_comparison.sh
git diff --check
```

Run the launch-free preflight:

```sh
application/scripts/launch_joint_qdesn_corrected_article_comparison.sh --preflight
```

Inspect `launch_free_preflight.csv`, `host_preflight.csv`,
`source_top_hash_verification.csv`, `source_nested_manifest_verification.csv`,
`seed_audit.csv`, `vb_worker_plan.csv`, and `mcmc_worker_plan.csv`. Continue
only if the preflight reports 136 VB components, 32 initializers, 160 MCMC
workers, zero source failures, all hashes verified, no seed collisions, and no
competing scientific process.

After recording a fresh 50-core capacity review, authorize only the VB phase:

```sh
export JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED=JEREZ_50_IDLE
export JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION=VB
application/scripts/launch_joint_qdesn_corrected_article_comparison.sh --launch-vb
unset JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION
```

Do not authorize MCMC until `check_joint_qdesn_shared_backbone_article_vb.R
--require-complete true` passes and all 32 compact initializer hashes verify.
Then authorize only MCMC:

```sh
export JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION=MCMC
application/scripts/launch_joint_qdesn_corrected_article_comparison.sh --launch-mcmc
unset JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION
```

After 160/160 workers complete with zero failures, finalize the score packet:

```sh
application/scripts/launch_joint_qdesn_corrected_article_comparison.sh --finalize-score
unset JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED
```

The queue commands may be supervised in a persistent terminal on Jerez. If
detached execution is used, write the PID and log inside the corrected ignored
runtime and verify them before treating the phase as active. Do not improvise
another runtime root or modify a frozen contract after fitting begins.

## Final scientific and publication gates

Finalization must stop unless:

- all 136 VB components, 32 compact initializers, and 160 MCMC workers verify;
- each cell has exactly five chains with one common posterior-target SHA-256;
- all manifests verify by size and hash;
- all reconstructed paths agree with stored summaries within `1e-8`;
- all 32 score cells and 16 contrasts are finite;
- the reported monotone grids have zero contract crossings;
- coupling, raw-crossing, functional, precision-repair, and gamma--scale
  diagnostics are retained; and
- no historical JOINT or Phase182 cell appears in the corrected packet.

Once complete, freeze the runtime and prepare a separate scientific closeout.
If the corrected comparison is valid, it replaces the complete current JOINT
article table, figures, and prose regardless of whether its scores are better
or worse. Do not update the article or Overleaf before that separate review.

## Copy-ready instruction for the JOINT Codex chat

```text
Work only on the corrected JOINT article comparison defined by
docs/implementation_notes/joint_qdesn_corrected_article_comparison_jerez_handoff_20260909.md
from the synchronized branch
work/joint-qdesn-corrected-article-comparison-jerez-20260909.

Use command-line Git only. Do not modify the frozen shared-backbone source,
historical Jerez runtime, Phase181, Phase182, PriceFM, GloFAS, the article, or
Overleaf. First confirm that PriceFM and every competing scientific process on
Jerez has ended and that 50 CPUs are available. Run all portable tests and the
launch-free preflight. Report the preflight evidence before launching. Then
run exactly one official campaign on Jerez: 136 VB components followed by 160
five-chain MCMC workers and the v2 score finalizer. Never mix historical and
corrected cells. Preserve all posterior-target hashes and manifests. Stop on
any branch, host, source hash, capacity, dependency, chain-count, target-hash,
or score gate failure. Do not publish results until a separate frozen
scientific closeout has been reviewed.
```

## Current boundary

No scientific model was launched while preparing this handoff. No article,
bibliography, table, figure, PDF, Overleaf branch, PriceFM runtime, GloFAS
runtime, Phase182 runtime, or historical JOINT runtime was modified.

`READY_FOR_JEREZ_PREFLIGHT_AFTER_BRANCH_PUSH`
