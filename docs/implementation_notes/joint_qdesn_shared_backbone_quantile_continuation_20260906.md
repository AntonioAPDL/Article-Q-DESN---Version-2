# JOINT Shared-Backbone Quantile Continuation Pilot

## Purpose

This pilot completes the quantile stage that follows the frozen Regime Shift
Gaussian shared-backbone screen. The Gaussian ridge and Gaussian regularized
horseshoe fits are initialization devices only. They are not article-facing
comparators and their scores are not compared with quantile scores.

The selected design and regularized-horseshoe global-scale control were chosen
using only the observational fitting window. Three fresh protected DGP
replicates evaluate the quantile continuation without changing that selection.

## Frozen Model Graph

For each replicate, the pipeline performs:

1. Refit Gaussian ridge and Gaussian RHS on all 500 fitting rows using the
   frozen direct design and `tau0 = 1`.
2. Initialize AL QDESN at the median from the Gaussian RHS location and scale.
3. Continue AL fits outward as `0.50 -> {0.25, 0.75} -> {0.10, 0.90} ->
   {0.05, 0.95}`.
4. Initialize each independent exAL fit from its same-level AL fit, using the
   established structured-`v` variational approximation.
5. Initialize Joint QDESN from the seven completed independent AL fits.
6. Initialize Joint exQDESN from the seven completed independent exAL fits and
   the Joint QDESN RHS state.

This gives 51 jobs: 3 Gaussian initialization jobs and 48 quantile VB jobs.
The stage-aware launcher runs at most 10 one-thread workers concurrently and
will skip atomically completed workers when restarted.

## Evaluation Contract

The frozen quantile grid is
`{0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95}`. Forecast origins are spaced by
30 and score leads 1--30 without refitting. Protected forecasts report
DGP-integrated finite-grid aCRPS, realized aCRPS, average check loss, oracle
quantile MAE/RMSE, and raw/contract crossings. The monotone reporting contract
is applied before scores are computed, while raw crossings remain visible as a
coherence diagnostic.

The four comparable models are Independent QDESN RHS, Joint QDESN RHS,
Independent exQDESN RHS, and Joint exQDESN RHS. This pilot does not run MCMC,
modify article assets, select a universal DESN specification, or use protected
scores to tune the design.

## Reproducibility

The frozen contract is
`application/config/joint_qdesn_shared_backbone_quantile_contract_v1.csv`.
Preparation verifies the parent commit-facing artifact hashes and its nested
manifest before writing fixtures, designs, worker plan, source Git state, and a
launch manifest.

Focused test:

```bash
Rscript application/tests/test_joint_qdesn_shared_backbone_quantile_fit.R
```

Launch:

```bash
JOINT_SHARED_QUANTILE_WORKERS=10 \
  bash application/scripts/launch_joint_qdesn_shared_backbone_quantile_pilot.sh
```

Health check:

```bash
Rscript application/scripts/check_joint_qdesn_shared_backbone_quantile_pilot.R
```

Finalization is failure-closed: all 51 jobs must be complete, finite, and
manifested, and every reported forecast grid must have zero contract crossings.
Finite fits reaching their iteration ceiling are retained as review cases, not
silently reclassified as converged.

The active Phase182 dense-grid campaign belongs to a separate worktree and is
not read, modified, stopped, or used by this pilot.
