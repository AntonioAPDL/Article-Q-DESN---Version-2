# JOINT pure-recursive MCMC preflight recovery

## Scope

This recovery resumes the frozen pure-DESN article-confirmation campaign after
MCMC batch 6 stopped at host preflight. It is orchestration-only. It does not
change the eight case-specific DESN specifications, RHS `tau0`, article
fixtures, VB initializers, posterior targets, chain seeds, MCMC budgets,
samplers, forecast definitions, score contracts, or article assets.

## Frozen failure state

At the recovery decision point, the source selection stages were complete:

- ridge: 6,144/6,144, zero failures;
- RHS: 6,000/6,000, zero failures;
- quantile VB: 408/408, zero failures;
- article-confirmation VB: 136/136, zero failures;
- article-confirmation MCMC: 75/160 complete, 15 failed at host preflight, and
  70 not attempted.

Workers 76--90 failed together before sampling, in 0.37--0.43 seconds, with the
recorded host-preflight error. The preceding 75 workers have verified manifests
and retained draws. A fresh preflight passes the frozen Jerez host, R/library,
storage, one-thread, physical-affinity, and competing-process gates. The
historical failed predicate is not recoverable because the old error path wrote
only a generic message.

## Recovery contract

1. Keep all 75 completed worker directories byte-for-byte unchanged.
2. Generate the existing failure-class audit and require all current failures
   to classify as `infrastructure_host_preflight`.
3. Generate the existing resume-compatibility audit and require every completed
   worker to pass manifest, posterior-target, draw-count, finiteness, execution
   ancestry, and precision-policy checks.
4. Require a fresh exact-affinity host preflight before changing worker state.
5. Copy and hash-verify the 15 failed directories, both audit packets, and queue
   metadata into a dedicated ignored recovery archive.
6. Remove only the 15 verified failed worker directories. This converts the
   runtime state to 75 complete, zero failed, and 85 pending.
7. Resume the existing queue. Worker IDs, chain/component seeds, VB starts,
   posterior targets, and iteration budgets remain frozen.
8. Require 160/160 MCMC workers and zero failures before score preparation.
9. Continue through the existing DGP-oracle and 64-cell score-packet workflow.
   Partial MCMC output remains ineligible for article promotion.

The retry is idempotent at the launcher level: after the verified recovery
summary exists, a relaunch does not repeat the archive operation. Queue locking
still prevents duplicate MCMC execution.

## Diagnostic repair

Future host-preflight failures identify the exact failed gates. Worker failure
directories additionally retain structured preflight, process-table, CPU
affinity, and shared-capacity snapshots. This repair affects diagnostics only;
the sampler and scientific model code are unchanged.

## Commands

The production recovery runs only on Jerez from the clean, synchronized branch
`work/joint-qdesn-pure-desn-recursive-selection-20260925` using pinned R 4.6.0
and the frozen 15-core affinity:

```bash
bash application/scripts/launch_joint_qdesn_pure_recursive_mcmc_preflight_recovery_jerez.sh
```

The launcher first runs the recovery audits and verified archive, then delegates
to the existing shared-capacity confirmation launcher. That launcher completes
MCMC, builds the score packet, and writes the final pipeline status before the
already-running expanded-screen scheduler becomes eligible to continue.

## Completion gates

- 160/160 MCMC workers complete, zero failed;
- all worker and final manifests verify;
- DGP-oracle precision gate passes or follows its frozen extension rule;
- 64/64 score cells complete;
- final score packet and hashes verify;
- no partial result is promoted;
- dedicated branch clean and synchronized;
- frozen integration handoff reports the exact old and recovery execution
  commits.
