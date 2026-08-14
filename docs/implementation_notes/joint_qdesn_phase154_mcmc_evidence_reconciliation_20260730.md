# Joint QDESN Phase 154: MCMC Evidence Reconciliation

## Decision

Phase 153 completed 1,600 independent VB fits over 400 fresh fixtures. It
confirmed that the frozen scenario-specific controls are implementation-valid,
but it did not itself produce MCMC evidence. Phase 154 reconciles those frozen
controls against the historical balanced MCMC packets before launching any new
sampling.

The audit separates two questions:

1. Does exact control-matched MCMC evidence exist?
2. Is that evidence strong enough for final article confirmation?

Historical coverage alone is not treated as final adequacy.

## Reconciliation Result

Exact control-matched MCMC evidence exists for all 32 Phase 153
scenario-model cells:

- 11 cells from Phase 122;
- 13 cells from Phase 124c;
- eight updated Joint exQDESN cells from Phase 150.

The eight Phase 150 Joint exQDESN rows use eight chains, 8,000 iterations,
2,000 burn-in iterations, thinning by four, and 12,000 retained draws per
case. They meet the Phase 154 final-confirmation policy and are reused.

The remaining 24 rows use two chains, 1,200 iterations, 600 burn-in
iterations, thinning by ten, and only 120 retained draws per case. They remain
valid implementation references, but they are not promoted as final MCMC
evidence.

## Selective Completion Design

Phase 154 reruns exactly:

- eight Joint QDESN AL cases with four chains and 4,000 iterations;
- eight Independent QDESN AL cases with four chains and 4,000 iterations;
- eight Independent exQDESN cases with eight chains and 8,000 iterations.

The gamma-bearing independent exAL rows receive the stronger effort tier.
Joint exQDESN is not recomputed because Phase 150 already meets that tier.

All 24 reruns use the exact Phase 153 controls. No DESN, RHS, prior, fan,
initialization, or likelihood setting is changed after observing Phase 153.

## Parallelization and Reproducibility

The three model blocks run in separate tmux sessions. Each block uses eight
single-threaded case workers. This gives 24 process-level workers without
nested BLAS parallelism. A detached finalizer waits for all three exit markers
and builds the 32-cell final audit only when every block exits successfully.

Each source, freeze, rerun, and final packet has:

- explicit run controls and seeds;
- provenance;
- source-manifest verification;
- raw and monotone-contract quantiles;
- fit and forecast scores;
- chain-to-pooled diagnostics;
- finite-draw and initialization gates;
- SHA-256 artifact manifests.

## Gates

Hard failure:

- source or output manifest mismatch;
- any control difference from the Phase 153 freeze;
- missing or duplicated scenario-model cells;
- nonfinite MCMC draws or scores;
- initialization not supplied by VB;
- contract quantile crossings;
- MCMC effort below the model-specific final-confirmation policy.

Review:

- raw crossings before the monotone contract;
- chain-to-pooled or VB-to-MCMC distance review;
- nontrivial monotone adjustment.

Model underperformance is scientific evidence, not an implementation failure.

## Commands

Focused regression:

```bash
Rscript application/tests/test_joint_qdesn_phase154_mcmc_evidence_reconciliation.R
```

Prepare and audit without launching:

```bash
Rscript application/scripts/183_prepare_joint_qdesn_phase154_mcmc_evidence_reconciliation.R
```

Launch all three selective completion blocks:

```bash
bash application/scripts/184_launch_joint_qdesn_phase154_article_grade_mcmc.sh \
  --execute \
  --workers-per-block 8
```

Health:

```bash
Rscript application/scripts/186_check_joint_qdesn_phase154_balanced_mcmc.R
```

## Article Boundary

Phase 154 does not modify the manuscript. Article assets may be rebuilt only
after the final 32-cell audit verifies exact controls, adequate MCMC effort,
finite quantile-grid summaries, and zero contract crossings. The MCMC layer is
confirmation evidence; it is not interpreted as a mechanism for rescuing the
replicated exAL tail-accuracy deficit observed in Phase 153.
