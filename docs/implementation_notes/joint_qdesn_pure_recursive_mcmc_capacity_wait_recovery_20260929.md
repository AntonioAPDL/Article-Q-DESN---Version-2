# JOINT Pure-Recursive MCMC Capacity-Wait Recovery

## Scope

This document governs only the JOINT pure-DESN recursive-selection article
confirmation rooted at:

`application/cache/joint_qdesn_pure_recursive_article_confirmation_jerez_15core_20260925`

It does not change selected scenario-specific DESN architectures, RHS controls,
quantile levels, likelihoods, posterior targets, chain seeds, MCMC budgets,
forecast policies, score definitions, article files, or publication branches.

## Audited state

At the recovery boundary, the frozen 160-worker MCMC plan had:

| State | Workers | Interpretation |
|---|---:|---|
| Manifest-complete | 90 | Valid posterior artifacts; retain unchanged |
| Host-preflight-only failure | 15 | Workers 91--105; sampler never started |
| Never attempted | 55 | Workers 106--160 |
| Scientific/sampler failures | 0 | No posterior computation failed |

All 15 failed attempts stopped at the same host gate in less than one second.
They contain no posterior draws and are therefore infrastructure records, not
failed scientific fits. The MCMC queue lock and controller are absent. The 90
completed worker manifests remain verifiable.

## Diagnosis

The previous queue performed host-capacity preflight independently inside each
worker. A temporary host-level block was consequently written into 15 worker
directories as if 15 model fits had failed. Retrying workers without changing
this queue boundary would reproduce the same failure mode.

The frozen JOINT CPU allocation is still valid. Amending the frozen scientific
contract is unnecessary and would create avoidable provenance complexity. The
proper repair is to move the transient capacity decision to the queue boundary,
while retaining worker-level preflight as a final race-condition defense.

## Recovery contract

1. Preserve all 90 completed worker directories byte-for-byte.
2. Audit the 15 failed directories and require every failure to classify as
   `infrastructure_host_preflight`.
3. Verify completed-worker posterior targets, manifests, designs, seeds, and
   compatible execution commits before any deletion.
4. Copy the 15 failed directories, audit inputs, and queue snapshots into a
   hashed recovery archive; verify size and SHA-256 before removing originals.
5. Require the post-archive state to be exactly 90 complete, 0 failed, and 70
   pending.
6. Start one resumable queue controller on the frozen 15-core JOINT affinity.
7. Before each batch, poll the host preflight at queue level. Only
   `competing_processes` is waitable. Host, R, library, storage, affinity, and
   thread-policy failures remain fatal.
8. Persist every capacity poll with a manifest, process snapshot, affinity
   mapping, shared-capacity mapping, status row, and cumulative history.
9. Require two consecutive clean polls before launching a batch.
10. Keep worker-level preflight enabled. A capacity change between queue release
    and worker startup therefore fails closed.
11. Resume only pending worker IDs; never rerun manifest-complete workers.
12. Require 160/160 verified workers and zero failures before confirmation
    finalization and score-packet execution.

## Downstream order

After the MCMC gate passes, the existing frozen launcher continues in order:

1. finalize the 160-worker confirmation packet;
2. prepare the score packet;
3. run the 16 primary DGP-oracle shards;
4. run an oracle extension only if the frozen primary audit requests it;
5. run sentinel score cells;
6. run all 64 path/mean-state score cells;
7. finalize and hash the score packet;
8. write the terminal source-pipeline status;
9. allow the already-deferred expanded screen to proceed only after that
   terminal status exists.

## Verification checklist

- [ ] Focused capacity-wait/recovery tests pass under pinned R 4.6.0.
- [ ] Pure-recursive campaign tests pass.
- [ ] Article-confirmation tests pass.
- [ ] Shell launchers pass `bash -n`.
- [ ] `git diff --check` passes.
- [ ] Dedicated JOINT branch is committed, pushed, clean, and synchronized.
- [ ] Recovery archive verifies before failed runtime directories are removed.
- [ ] Post-recovery state is 90 complete, 0 failed, 70 pending.
- [ ] Background controller owns exactly one queue lock.
- [ ] Capacity waiting creates no worker failure directories.
- [ ] First resumed batch starts only after the frozen host gate passes.
- [ ] Final closeout records run counts, manifests, hashes, tests, storage, and
      integration exclusions.

## Decision rule

The phase is not ready for integration until all 160 workers and the required
score packet are complete and verified. While the controller is waiting or any
worker remains pending, the correct state is `NOT_READY_FOR_INTEGRATION`.
