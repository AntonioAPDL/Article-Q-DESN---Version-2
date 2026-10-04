# JOINT expanded-continuation score closeout

Date: 2026-10-04

## Objective

Close the expanded, case-specific pure-DESN continuation without changing a
model, posterior, score definition, frozen gate, protected fixture, or MCMC
budget. Preserve the successful 160-chain MCMC campaign and 16-shard DGP
oracle, recover the two unresolved score cells, finalize the 64-cell packet,
and retain a complete audit trail for integration review.

This work belongs only to the JOINT simulation lane. It must not modify main,
Overleaf, PriceFM, GloFAS, Phase182, or another lane's runtime.

## Audited entry state

The expanded campaign selected new case-specific DESN/RHS specifications only
for Asymmetric Laplace Tail and Nonlinear Reservoir Friendly. Six unchanged
scenario specifications and their fitted artifacts were reused only after
design, target, and artifact hashes verified.

At closeout preparation:

- expanded ridge/RHS screening: `26,112 / 26,112`, zero failures;
- nested quantile VB: `408 / 408`, zero failures;
- article-window VB: `136 / 136`, zero failures;
- MCMC: `160 / 160`, zero failures and 32 verified posterior targets;
- primary DGP-oracle shards: `16 / 16`, complete;
- score cells: 59 complete, worker 41 failed its score-stability gate, workers
  61, 62, and 64 active, and worker 56 skipped by its queue slot.

The active score controller and its runtime remain read-only until all active
workers stop and its exit receipt is present.

## Root-cause diagnosis

Worker 41 is Laplace Bridge joint AL MCMC. It is not an MCMC, numerical-linear-
algebra, exAL, gamma, or M0 failure. Its five chains are finite, hash-consistent,
use `AL_latent_GIG_Gibbs`, have zero contract crossings, and required at most
one negligible precision repair.

The full-posterior mean-design tier used all 3,750 retained posterior draws. Its
standardized RMS half-design difference was `0.03003`, below the unchanged
`0.10` gate. Its relative half-score difference was `0.00513519`, narrowly
above the unchanged `0.005` gate. The failure is therefore a bounded recursive
state-integration stability issue.

Worker 56 is Persistent Heavy Tail independent exAL MCMC. It did not fail: the
score queue used `set -e` semantics inside each sequential slot, so worker 41's
nonzero result stopped that slot before worker 56 was invoked.

## Preserved scientific contract

The closeout keeps fixed:

- every case-specific DESN architecture and RHS `tau0`;
- all VB and MCMC posterior draws and five-chain allocations;
- exact M0 for every exAL MCMC fit;
- the seven-level quantile grid and trapezoidal weights;
- teacher forcing between origins and recursive 30-step forecasting within
  each origin;
- the article fixtures, DGP-oracle banks, and finite-grid integrated aCRPS;
- the mean-state and recursive-path forecast actions;
- the `0.10` RMS and `0.005` score-stability gates.

No rescreening, refitting, gate relaxation, partial ranking, or article
promotion is allowed during recovery.

## Implementation

### Failure-isolated queues

`_joint_qdesn_score_queue.sh` runs every worker assigned to a slot, writes an
atomic exit receipt for each worker, and returns a nonzero slot status only
after all assigned workers have been attempted. The expanded continuation
launcher uses this helper for future oracle and score queues. A behavioral test
forces the middle of three jobs to fail and proves the third job still runs.

### Strict score-only recovery

The run-specific recovery contract freezes SHA-256 hashes for:

- the score contract;
- the 64-cell plan;
- worker 41's original `FAILED`, diagnostics, and stability progress.

After the active controller closes, the recovery launcher requires exactly
`62 complete / 1 failed / 1 pending`, with worker 41 failed and worker 56
pending. It then runs:

1. worker 56 through the ordinary frozen worker path;
2. worker 41 through the validated antithetic-uniform recovery, first one and
   then at most two antithetic pairs per retained posterior draw.

Both use distinct idle physical cores, pinned R 4.6.0, and one numerical thread.
Worker 41's original failure is archived atomically and hash-inventoried.

### Bounded review, only if required

If strict recovery remains narrowly above `0.005`, freeze a second addendum
from the strict-recovery outputs. Reuse the existing bounded-review API. The
original strict failure remains visible; the cell may be finalized as review
only when every predeclared finite, RMS, score-ceiling, pooled-drift,
chain-deviation, draw-count, trajectory-count, crossing, and manifest check
passes. The packet must then state
`COMPLETE_WITH_ONE_SCORE_STABILITY_REVIEW`, never 64 strict passes.

The review-contract materializer is intentionally unavailable until strict
recovery has produced exactly `63 complete / 1 failed / 0 pending`. It binds
the expanded score contract, cell plan, strict-recovery contract, worker-41
failure evidence, original failure inventory, and completed worker-56 manifest
by SHA-256. The review launcher passes the expanded recovery contract
explicitly and requires a clean, synchronized dedicated branch.

## Final analysis contract

Only a complete 64-cell packet may be compared. Report, by scenario and model:

- DGP-integrated finite-grid aCRPS posterior mean, median, and 95% interval;
- canonical-action DGP-integrated score;
- realized aCRPS as compatibility evidence;
- fit and forecast oracle MAE/RMSE as recovery diagnostics;
- mean-state versus recursive-path scores and interval widths;
- raw and contract crossings;
- joint-minus-independent contrasts;
- score, chain, provenance, and review status.

Promotions remain case-specific. A lower mean primary score may be promoted
when provenance is complete, values are finite, contract crossings are zero,
and behavior is nonpathological. Overlapping intervals require descriptive
wording. Scalar mixing is review-level unless predictive functionals are
pathological.

## Storage cleanup policy

Cleanup is a separate manifest-driven closeout action. Before deletion:

1. inventory only JOINT pure-recursive outputs produced by this lane during
   the preceding four weeks;
2. classify each root as active, authoritative/current source, promoted
   evidence, reproducibility dependency, failed/superseded, or ambiguous;
3. protect the expanded screen, current confirmation, current score packet,
   their exact six-scenario reuse sources, manifests, hashes, plans, logs, and
   compact diagnostic tables;
4. hash-inventory every deletion candidate and retain compact metadata before
   removing heavy `.rds`, `.rda`, `.RData`, posterior-draw, or redundant cache
   payloads;
5. delete only candidates proven failed or superseded and not referenced by a
   surviving manifest, symlink, current plan, or handoff;
6. record bytes freed, paths removed, evidence retained, and post-cleanup hash
   verification.

The audited deletion surface is limited to the prior narrow packet's eight
oracle-bank RDS files and sixteen oracle-shard RDS files. All 24 payloads must
have byte-identical copies in the current expanded packet before they are
eligible. `cleanup_joint_qdesn_pure_recursive_legacy_oracles.R` first writes a
hash inventory and, in apply mode, additionally requires the current 64-cell
packet, no active JOINT worker/finalizer, and exact cleanup authorization. It
preserves the prior final packet, score tables, shard summaries, artifact
manifests, DGP manifest, and a compaction receipt. Current oracle payloads,
posterior draws, selection caches, winner initializers, fixtures, and designs
are protected.

Ambiguous roots fail closed and remain in place. No cleanup runs while a JOINT
worker or finalizer is active.

## Checklist

- [x] Diagnose the unresolved cells and preserve active runtime isolation.
- [x] Reuse the validated strict-recovery and bounded-review design.
- [x] Freeze the expanded-continuation strict-recovery hashes.
- [x] Implement failure-isolated score queues and behavioral tests.
- [x] Commit, push, and synchronize the dedicated closeout branch.
- [ ] Wait for the active score controller to close.
- [ ] Verify the exact `62 / 1 / 1` recovery entry state.
- [ ] Select two idle physical cores and pass strict-recovery preflight.
- [ ] Complete ordinary worker 56 and strict worker-41 recovery.
- [ ] If required, freeze and execute the bounded-review addendum.
- [ ] Finalize and verify all 64 cells and the final packet.
- [ ] Perform the complete-packet scientific comparison.
- [ ] Execute manifest-driven legacy cleanup and write its receipt.
- [ ] Commit and push closeout metadata; provide the frozen integration handoff.
