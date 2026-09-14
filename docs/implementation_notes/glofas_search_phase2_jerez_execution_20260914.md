# GloFAS Search Phase II: Jerez Distributed Execution Plan

## Decision

Run the remaining Ridge candidate-fold jobs on Jerez without restarting the
completed Muscat work. The scientific design remains the frozen Search Phase
II design in `glofas_search_phase2_validity_first_20260914.md`; this document
changes execution location only.

This is preferable to a fresh Jerez launch because it avoids duplicate fits,
retains the exact prospective search, and preserves one authoritative Muscat
runtime for final aggregation. It is preferable to leaving the full campaign
on Muscat because Jerez has 64 cores, approximately 483 GiB available RAM at
preflight, and no active Article-Q-DESN computation.

## Audited State

| Item | Frozen value |
| --- | --- |
| Numerical source branch | `work/glofas-search-phase2-20260914` |
| Numerical source HEAD | `56b8b59245a600555e700bfb7c6cba1459ab50aa` |
| Central Muscat runtime | `glofas_search_phase2_ridge_20260914_r1` |
| Ridge design | 69 architectures x 6 folds x 2 targets = 828 jobs |
| Final Muscat ownership | 20 complete jobs |
| Initial Jerez assignment | 808 never-started job IDs |
| Final test origin | `2022-12-25`, excluded from all tuning packets |
| Search folds | `2018-12-25`, `2019-12-25`, `2020-12-25`, `2021-11-12`, `2021-12-21`, `2022-05-11` |
| Primary/secondary horizons | 28/30 days |
| Covariates | oracle realized PRISM precipitation and ERA5 soil moisture |
| Score precision | differences beyond four decimals treated as noise |

Muscat temporary `.failed` markers containing exactly
`DISTRIBUTION_HOLD_JEREZ_20260914` are scheduler control records, not model
failures. They are generated only for never-started jobs and are removed only
by the verified result importer.

## Execution Contract

1. Let every Muscat job active at the hold reach its normal `.done` or real
   `.failed` state. Stop only this lane's scheduler; do not touch unrelated
   tmux sessions or jobs.
2. Prepare a Jerez shard from the immutable job-ID assignment. Copy the 12
   sealed model packets and 12 sealed scoring packets, filtering the job and
   candidate manifests to the assigned jobs. Rewrite only runtime paths.
3. Verify every copied packet against its original SHA256. Pin the Jerez source
   worktree to the numerical HEAD above on a dedicated pushed branch. Require
   a clean worktree exactly synchronized with its upstream.
4. Run the focused R Search-II tests, Python scheduler tests, remote-shard
   tests, parse checks, and a no-fit launcher dry run on Jerez.
5. Launch the 808-job shard with 50 one-thread workers and weighted capacity
   100. This leaves 14 hardware cores outside the campaign and limits wide
   states even though RAM would permit a more aggressive launch.
6. Monitor health, memory, failures, and stale markers. Do not retry a genuine
   model failure silently. Diagnose it and record whether a no-refit scoring
   repair is sufficient.
7. After 808/808 completion, generate a hash manifest containing only
   job-specific result artifacts. Pull that manifest and its named files to a
   temporary Muscat import directory, verify all hashes, and then import into
   the central runtime. The importer refuses collisions and removes only the
   exact distribution-hold markers.
8. Run the central checker. Ridge is complete only when all 828 central jobs
   are scored, no real failures or stale workers remain, and all aggregate
   target/candidate rows contain six folds.

## Scientific Stages After Ridge

Jerez execution does not automatically start RHS work. Once the consolidated
Ridge gate passes on Muscat:

1. Prepare the 288-fit RHS prior pilot from the declared diverse candidate set.
2. Transfer that separately frozen runtime to Jerez and run grouped by
   architecture/fold so six priors share one design build while remaining
   independent scored fits.
3. Select the prior using mean primary CRPS and then worst-fold CRPS, subject to
   convergence, finite-state, and historical-fit guardrails.
4. Prepare the 240-evaluation RHS architecture screen, reusing eligible pilot
   cells rather than refitting them.
5. Confirm the top three per target over three additional seeds plus the
   original seed (144 fits). Never select the best seed realization.
6. Freeze component winners only after confirmation. Refit through
   `2022-12-25` and evaluate the untouched final window only after the search is
   irrevocably closed.

No later stage may be prepared from a partial Ridge aggregate, and no test
window score may alter candidate, prior, or seed selection.

## Reproducibility and Recovery

`402_manage_glofas_search_phase2_remote_shard.py` is the control surface:

- `prepare` creates the relocatable, assigned runtime and payload hashes;
- `verify` enforces clean/synchronized Git state, exact HEAD, path relocation,
  packet hashes, cardinality, and an empty initial status directory;
- `finalize` requires all assigned jobs complete and emits result hashes;
- `import-results` verifies the remote results, refuses overlap with Muscat
  ownership, removes only exact hold markers, and copies job-specific outputs.

Runtime data, fitted objects, logs, status markers, and transfer staging remain
under ignored runtime paths. Only this plan, the control utility, and its tests
are tracked. No article, manuscript, bibliography, figure, table, main branch,
or Overleaf branch is changed by this work.

## Stop Conditions

Stop the Jerez launch and preserve evidence if the preflight HEAD differs, the
worktree is dirty/diverged, a packet hash differs, assignment cardinality is
not exact, any assigned job already has a status marker, thread guards differ
from one, memory pressure becomes material, or a real failure appears. A
failed preflight must never be bypassed by editing a status marker.
