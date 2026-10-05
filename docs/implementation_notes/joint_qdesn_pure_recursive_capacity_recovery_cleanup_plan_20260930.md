# JOINT pure-DESN capacity recovery and storage closeout

Date: 2026-09-30

## Scope

This plan covers only the JOINT pure-DESN recursive-selection lane and its
directly superseded JOINT runtime copies. It does not authorize changes to
PriceFM, GloFAS, Phase182, article, Overleaf, or another scientific lane.

The scientific objective remains unchanged: complete the frozen 32-cell,
160-chain article confirmation; build the path-versus-mean recursive score
packet; then release the separately frozen expanded DESN/RHS screen. The MCMC
target, M0 exAL transition, VB initializers, seeds, selected case-specific DESN
and RHS controls, forecast protocol, and score definitions are immutable.

## Audited state before recovery

- Ridge screening: 6,144/6,144 complete, zero failures.
- RHS pruning: 6,000/6,000 complete, zero failures.
- Nested quantile VB: 408/408 complete, zero failures.
- Article-window VB: 136/136 complete; 32/32 compact initializers complete.
- Article-window MCMC: 135/160 complete, zero scientific worker failures,
  25 chains pending, and no active JOINT MCMC child.
- Completed chains have finite posterior quantile matrices and zero contract
  crossings. All 65 completed exAL chains use exact M0.
- The queue is paused only because the frozen process-name whitelist recognizes
  PriceFM R120 while the active, physically disjoint campaign is PriceFM R122.
- The deferred expanded-screen scheduler also waits on a historical controller
  receipt whose terminal value is permanently nonzero.

## Recovery design

### Capacity gate

Keep the frozen allowed-process pattern as historical evidence. Add a second,
fail-closed execution gate for a newer PriceFM process family:

1. identify a PriceFM controller only when its command contains a parseable
   `--cpu-list` and a PriceFM launcher path;
2. resolve that controller's descendants from the live PID/PPID graph;
3. map the declared controller CPUs and each worker's kernel
   `Cpus_allowed_list` to physical package/core identities;
4. approve the controller only when its declared physical cores are distinct
   from the JOINT physical cores;
5. approve a worker only when its kernel affinity is readable, is a subset of
   the controller's declared CPUs, and has zero JOINT physical-core overlap;
6. reject unknown, unattached, malformed, or overlapping processes;
7. retain the complete decision table in every capacity-wait attempt.

This is an execution-control amendment. It does not modify the frozen model or
rewrite the original contract.

### Resume policy

1. Run focused tests and an actual Jerez preflight while the existing queue is
   idle.
2. Gracefully stop only the idle JOINT capacity-wait session.
3. Commit and push the dedicated JOINT branch.
4. Fast-forward the same dedicated branch on Jerez.
5. Resume from the existing confirmation root. Completed worker directories
   remain immutable; only the 25 missing worker IDs may run.
6. Require two consecutive clean capacity polls before work starts.
7. Continue through MCMC finalization and score-packet production without a
   refit of completed work.

### Expanded-screen scheduler

Replace the obsolete-controller dependency with final-artifact gates:

- source `final_pipeline_status.csv` has the declared terminal status;
- confirmation `mcmc_final_artifact_manifest.csv` exists;
- score packet `final_packet/DONE` exists;
- no source confirmation or score worker remains active.

Only then may the expanded screen launch. It reuses the frozen 6,144-job ridge
packet and performs the already planned broader case-specific screen; it does
not alter the current article confirmation.

## Storage policy

### Preserve

- the current pure-DESN campaign, confirmation, and future score roots;
- all completed MCMC workers and compact initializers;
- current manifests, hashes, contracts, health tables, controller receipts,
  and the reviewed preliminary atlas;
- the deferred expanded-screen code, scheduler evidence, and future target;
- one verified Muscat copy of each historical authoritative packet still used
  for comparison.

### Eligible for removal

- byte-identical Jerez runtime copies already verified on Muscat;
- superseded preflight-only directories and failed preparation replicas;
- redundant capacity-poll directories after their aggregate history, terminal
  attempts, and cleanup receipt are retained;
- duplicated `.rds`, `.rda`, `.rdata`, posterior draws, and worker payloads
  contained only in those superseded copies.

### Ineligible for removal

- any path referenced by an active process;
- any current worker, fixture, design, initializer, contract, or manifest;
- any artifact without a verified surviving copy or a reproducible upstream;
- another lane's runtime, regardless of age or size.

## Verification and closeout

- focused capacity/recovery and shared-contract tests pass under pinned R 4.6.0;
- `git diff --check` passes;
- live Jerez preflight records zero unapproved competitors and zero physical
  overlap;
- the resumed queue starts only pending IDs and leaves completed worker hashes
  unchanged;
- the expanded scheduler records the corrected final-artifact dependency;
- cleanup inventory records every removed path, prior bytes, surviving source,
  verification method, and reclaimed bytes;
- task branches are clean, pushed, and synchronized; no main or Overleaf branch
  is touched.
