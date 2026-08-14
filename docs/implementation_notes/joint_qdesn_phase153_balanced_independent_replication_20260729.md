# Joint QDESN Phase 153: Balanced Independent Replication

## Purpose

Phase 153 is the full fresh-data confirmation layer for the four balanced
joint-validation rows:

1. Joint QDESN RHS under the AL working likelihood.
2. Independent QDESN RHS under the AL working likelihood.
3. Joint exQDESN RHS under the exAL working likelihood.
4. Independent exQDESN RHS under the exAL working likelihood.

The phase addresses a limitation shared by the earlier screening and
confirmation packets: many decisions were evaluated on a small number of
realizations, and some comparisons reused data that had already informed
case-specific calibration. Phase 153 freezes the selected controls first and
then evaluates every model on the same independent DGP replications.

This is a confirmation campaign, not another hyperparameter screen. It does
not select one global DESN specification, reopen exhausted gamma/feature-map
screens, run MCMC, or alter article assets.

## Prelaunch Audit

The implementation audit reached the following conclusions.

- **Scenario-specific controls are required.** The scientific target is the
  best stable specification for each scenario-model cell, not a universal
  setting across all mechanisms.
- **The control grid is complete.** The Phase 121 and Phase 124b freezes supply
  24 AL and independent-exAL cells. The Phase 150 freeze supplies the eight
  updated Joint exQDESN cells. The resulting grid contains exactly 32 unique
  scenario-model cells.
- **Phase 151 is closed.** Its feature-design alternatives failed independent
  confirmation in Phase 152 and are held fixed rather than screened again.
- **Fresh DGP replication is the missing evidence.** Additional tuning on the
  same realizations would not establish that observed gains generalize.
- **VB is the correct first layer.** The full balanced comparison is feasible
  with VB, while MCMC should be reserved for predeclared winners after the
  independent evidence is audited.

## Frozen Sources

The readiness packet verifies the SHA-256 manifests for:

- Phase 121 case-specific VB winners;
- Phase 124b missing-cell VB winners;
- Phase 125 balanced MCMC audit;
- Phase 150 Joint exQDESN case-specific freeze;
- Phase 150 Joint exQDESN MCMC confirmation;
- Phase 152 independent-confirmation readiness.

The 32-row `frozen_case_model_controls.csv` records the source candidate,
source freeze, source directory, and source control-file hash for every cell.
No metric from a Phase 153 replicate can change these controls.

## Replication Design

The full launch uses:

- eight synthetic mechanisms;
- four model/readout combinations;
- 50 fresh DGP replicates per mechanism;
- 400 materialized fixtures;
- 1,600 VB fits;
- 20 process-level workers;
- one BLAS thread per worker.

Every fixture preserves the formal article geometry:

- total simulated length: 12,000;
- DGP warmup: 2,000;
- DESN washout: 500;
- fit window: 500;
- validation window: 1,000;
- forecast-origin stride: 30;
- forecast leads: 1--30;
- no refitting across validation blocks.

The fit is computed once per scenario-model-replicate cell and reused for fit
and held-out forecast scoring. The original registry seeds and all Phase 152
seeds are excluded. Phase 153 seeds and seed roles are frozen in the readiness
packet.

## Metrics and Contrasts

The campaign stores compact summaries for:

- oracle-quantile MAE and RMSE;
- check loss;
- grid CRPS;
- absolute hit-rate error;
- interval diagnostics;
- raw and monotone-contract crossings;
- monotone-adjustment magnitude;
- VB convergence and runtime.

All six pairwise model contrasts are retained. The four predeclared scientific
contrasts are:

- Joint QDESN versus Independent QDESN;
- Joint exQDESN versus Independent exQDESN;
- Joint exQDESN versus Joint QDESN;
- Independent exQDESN versus Independent QDESN.

Contrasts are paired by scenario, fresh DGP replicate, and metric. The audit
reports replicate-level deltas, win fractions with Wilson intervals, and
deterministic bootstrap intervals for median deltas. Primary interpretation is
based on forecast oracle-quantile MAE; other metrics diagnose whether gains are
coherent rather than serving as additional selection objectives.

## Reproducibility and Resume Contract

Each fit writes an atomic, hash-manifested candidate directory containing only
compact CSV summaries and a README. Fitted R objects are deliberately not
retained. A resumed launch skips only checkpoints whose complete manifest
verifies; malformed checkpoints are quarantined before recomputation.

The root readiness and result directories contain SHA-256 manifests,
provenance, frozen registries, source verification, run configuration, and
human-readable summaries. Bootstrap seeds and DGP seed roles are explicit.

## Gates

Hard failure is reserved for:

- source or candidate hash failure;
- malformed frozen controls or fresh registry;
- seed collision;
- worker or implementation failure;
- nonfinite model summaries or scores;
- crossing after the monotone output contract.

Review is appropriate for:

- VB reaching its adaptive iteration limit;
- raw crossings that require monotone repair;
- adjustments exceeding the frozen review threshold.

Model underperformance on fresh data is scientific evidence and is not an
implementation failure.

## Commands

Focused regression:

```bash
Rscript application/tests/test_joint_qdesn_phase153_balanced_independent_replication.R
```

Prepare without launching:

```bash
bash application/scripts/182_launch_joint_qdesn_phase153_balanced_independent_replication.sh
```

Launch the full campaign:

```bash
bash application/scripts/182_launch_joint_qdesn_phase153_balanced_independent_replication.sh \
  --execute \
  --workers 20 \
  --n-dgp-replicates 50
```

Health check:

```bash
Rscript application/scripts/181_check_joint_qdesn_phase153_balanced_independent_replication.R
```

The default tmux session is
`joint_qdesn_phase153_balanced_replication_20260729`. The workflow log is
`application/cache/joint_qdesn_phase153_balanced_independent_replication_20260729_orchestration/phase153_workflow.log`.

## Decision After Completion

Phase 153 must be fully audited before any MCMC or article action. The next
decision is scenario-specific:

1. retain or reject each frozen VB specification from paired fresh-DGP
   evidence;
2. define a narrow Phase 154 MCMC packet only for article-relevant cells that
   survive;
3. initialize MCMC from the selected VB fits using fresh predeclared roots;
4. regenerate article assets only after MCMC diagnostics and manifests pass.

No Phase 153 code automatically performs these later actions.
