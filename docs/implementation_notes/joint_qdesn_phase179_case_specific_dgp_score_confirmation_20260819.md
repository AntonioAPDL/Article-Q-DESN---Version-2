# Phase 179 case-specific DGP-score confirmation

## Purpose

Phase 178 completed the exact-M0 post-recovery ranking under its original,
frozen oracle-quantile MAE contract.  The subsequent current-grid postscore
audit reconstructed posterior quantile paths and evaluated their known-DGP
expected finite-grid quantile score.  Neither result is rewritten here.

Phase 179 is a prospective fresh-seed confirmation layer.  It asks whether the
small score improvements observed after Phase 178 repeat on the three protected
confirmation DGP replicates.  Selection and confirmation remain specific to a
scenario-readout cell: no common DESN configuration or common `tau0` is sought.

## Prospective selection

The frozen current-grid numerical minimum is selected independently within each
of five unresolved cells.  The user-directed promotion floor is zero: any
strictly positive DGP-integrated score gain may advance to fresh confirmation.
This replaces neither the historical half-percent near-tie audit nor the
original Phase 178 ranking.  Both remain preserved as separate source artifacts.

The resulting inventory contains five selected controls:

- parity for independent Laplace bridge;
- `tau0_upper` for independent normal bridge;
- parity for independent persistent heavy tail;
- `tau0_lower` for independent regime shift;
- `tau0_lower` for joint regime shift.

Selected-versus-parity deduplication yields eight templates.  Every template is
copied from the verified Phase 178 model-control freeze, including its exact
control-row hash, DESN input/design provenance, RHS controls, and `tau0`.

## Protected confirmation design

The confirmation uses the previously frozen and unused `confirmation`
partition.  It contains three DGP replicates per base scenario.  Article
fixtures remain excluded.  Each candidate-replicate fit uses:

- exact M0 (`M0_v_collapsed_support_logit`);
- structured-v VB initialization;
- 16 independent MCMC chains;
- 48,000 iterations, 8,000 burn-in iterations, and thinning by 8;
- one numerical thread per chain worker;
- the existing seven-level grid
  `(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)`.

The complete campaign therefore has 24 candidate-replicate cases and 384
checkpointed workers.  Compressed CSV posterior checkpoints are retained; no
serialized R workspace is written.

## Promotion contract

A nonparity challenger is promoted when all hard gates pass and:

1. its median matched DGP-integrated score ratio is strictly below one;
2. at least two of three fresh replicates have a lower score than parity;
3. median fit and forecast oracle-MAE ratios are at most 1.05;
4. no replicate has an oracle-MAE ratio above 1.10.

Posterior mean score, median score, equal-tailed 95% interval, and probability
of a lower score remain reported.  They are not converted into a practical-
significance requirement.  This implements the requested policy that even a
small repeatable improvement may be promoted.

Hard failure is reserved for incomplete or unverifiable sources, failed
workers, nonfinite scores, material score-functional instability, or nonzero
contract crossings.  Preferred R-hat/ESS thresholds and raw crossing rates
remain review diagnostics.  Thus imperfect scalar mixing does not erase a
stable quantile-functional gain, but clearly unreliable score functionals still
fail closed.

## Reproducible workflow

Prepare the prospective selection and MCMC freeze:

```bash
Rscript application/scripts/264_prepare_joint_qdesn_phase179_dgp_score_confirmation.R \
  --vb-cores 12
```

Launch from an audited CPU allocation:

```bash
JOINT_QDESN_PHASE179_SCORE_CPU_LIST="8,9,...,55" \
JOINT_QDESN_PHASE179_SCORE_MAX_PARALLEL=48 \
bash application/scripts/266_launch_joint_qdesn_phase179_dgp_score_confirmation.sh
```

Check health and finalize when all workers are complete:

```bash
Rscript application/scripts/265_check_joint_qdesn_phase179_dgp_score_confirmation.R \
  --score-cores 12
```

The launcher is completion-aware and invokes the same checker after the worker
queue closes.  Re-running a worker reuses only a complete, hash-verified
checkpoint.

## Artifacts

The selection freeze records the prospective policy, historical postscore
decision, all source checks, selected controls, confirmation templates,
protected seeds, provenance, and SHA-256 manifest.

The MCMC freeze records the exact chain/component seed plan, structured-VB
initialization, model controls, design preflight, source hashes, and manifest.

The final audit records posterior score draws and intervals, canonical-action
scores, matched candidate-parity contrasts, oracle diagnostics, crossing and
functional diagnostics, runtimes, case-specific decisions, final controls,
provenance, and a SHA-256 manifest.

## Boundary and next stage

This phase does not alter article files, run dense-grid models, or select a
universal specification.  Once its fresh-seed decisions are frozen, only the
qualified case-specific controls may proceed to article-fixture confirmation.
Article assets remain the responsibility of the later audited integration
stage.
