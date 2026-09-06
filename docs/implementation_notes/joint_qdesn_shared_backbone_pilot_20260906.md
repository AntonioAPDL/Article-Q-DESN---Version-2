# JOINT QDESN Shared-Backbone Pilot

## Purpose

This experiment tests whether a likelihood-neutral, scenario-specific DESN
backbone improves the Regime Shift comparison while holding the dynamic feature
representation fixed across independent and joint AL/exAL quantile readouts.
It is a new pilot and does not replace the Phase180/181 article authority.

## Frozen Selection Contract

- Pilot scenario: `regime_shift`.
- Grid: 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95.
- Candidate set: 192 new multilayer reservoir/hybrid designs plus the mandatory
  current-authority direct-design anchor.
- Replication: three independently generated calibration fixtures.
- Selection data: the 500 observational fit rows only, partitioned
  chronologically into 350 training and 150 calibration rows.
- Protected data: all 1,000 validation rows are removed before selector
  fixtures are persisted, so ridge and Gaussian RHS workers cannot load them.
- Primary selector: realized finite-grid aCRPS with trapezoidal weights.
- Ridge advancement: exactly 30 designs; if the authority anchor is outside the
  metric top 30, it replaces the lowest-ranked non-anchor.
- Gaussian RHS refinement: the 30 designs are crossed with tau0 in
  `{1, 0.1, 0.01, 0.001, 0.0001}` over three replicates.
- Runtime: exactly 10 concurrent one-thread workers at nice level 10.

The selected DESN architecture and Gaussian RHS sparsity control are
scenario-specific. The eventual independent QDESN, independent exQDESN, joint
QDESN, and joint exQDESN fits must all use that same frozen design. No protected
forecast score may alter the selection.

## Reproducibility and Isolation

The implementation lives on dedicated branch
`work/joint-qdesn-shared-backbone-pilot-20260906`, created from integrated
`origin/main`. It does not modify Phase182 code, runtime state, GloFAS-owned
files, PriceFM, GloFAS, or independent-QDESN workflows. It reuses the already
integrated generic Gaussian and reservoir APIs without changing them.

The Phase180 authority registry and its parent manifest are checked against
frozen SHA-256 values before preparation. Candidate, fixture, split, API,
source, Git, and runtime plans are persisted and hashed before workers start.
Each worker writes a terminal marker and compact CSV evidence. Launch scripts
are restartable and skip only terminal workers.

## Stage Graph

```text
prepare and hash selector-only fixtures
  -> 579 Gaussian ridge jobs (193 designs x 3 replicates)
  -> failure-closed top-30 freeze
  -> 450 Gaussian RHS-VB jobs (30 designs x 5 tau0 x 3 replicates)
  -> scenario-specific shared-backbone freeze
  -> later full-500-row refit and six-model VB comparison
  -> later VB-initialized MCMC, only after VB evidence passes
```

The launched pipeline intentionally stops after the Gaussian RHS winner is
frozen. Quantile VB, protected forecasting, and MCMC are outcome-dependent
scientific stages and cannot be selected or launched before this screen closes.

## Commands

```bash
Rscript application/tests/test_joint_qdesn_shared_backbone_screening.R
Rscript application/scripts/prepare_joint_qdesn_shared_backbone_pilot.R
bash application/scripts/launch_joint_qdesn_shared_backbone_pipeline.sh \
  application/cache/joint_qdesn_shared_backbone_pilot_20260906
```

Health checks:

```bash
Rscript application/scripts/check_joint_qdesn_shared_backbone_pilot.R \
  --root application/cache/joint_qdesn_shared_backbone_pilot_20260906
Rscript application/scripts/check_joint_qdesn_shared_backbone_pilot.R \
  --root application/cache/joint_qdesn_shared_backbone_pilot_20260906 \
  --stage rhs
```

## Promotion Boundary

The Gaussian winner is not article evidence. After closeout, the next change
must build and test the generic quantile continuation and initializer graph,
refit the frozen winner on all 500 observational rows, and compare the two
Gaussian references plus the four quantile VB models on a fresh non-article
fixture. MCMC and article promotion remain separately gated.
