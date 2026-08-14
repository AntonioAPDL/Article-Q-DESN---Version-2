# Joint exQDESN Phase 171-175 Cache Cleanup

## Purpose

This note records the pre-closeout cache audit performed while the Phase 173
pooled posterior and functional audit was running. The cleanup was restricted
to superseded joint-QDESN validation artifacts from this workstream. It did not
modify source code, tracked article assets, current fixtures, active MCMC
checkpoints, or any PriceFM, GloFAS, TT500, or independent-validation output.

## Safety contract

Deletion was allowed only when all of the following held:

1. the candidate directory was inactive and had no open file descriptors;
2. its artifact manifest verified before cleanup;
3. it was absent from the Phase 171-175 protected source graph;
4. a newer authoritative packet superseded its scientific role;
5. compact metrics, diagnostics, provenance, and a SHA-256 inventory of every
   removed file were preserved when the artifact contained nontrivial evidence;
6. the replacement summary archive verified before closeout.

## Protected evidence

The following classes were explicitly retained:

- original article DGP fixtures;
- Phase 149 selected-control evidence and Phase 150 joint-exAL freeze/results;
- Phase 153 replicated fixtures and VB evidence;
- Phase 154 AL and independent-exAL MCMC packets and balanced packet;
- Phase 155 article assets;
- Phase 166 selected method-development fixtures;
- corrected Phase 169R method evidence and the Phase 170 M0 decision;
- the current Phase 171 freeze and complete Phase 172 posterior checkpoints;
- all inputs and outputs required by the running Phase 173 audit.

The large retained fixture directories are reproducibility inputs, not obsolete
model workspaces. They must not be removed as part of a model-output cleanup.
The compact Phase 169 failed-postfit closeout was also retained because it
documents a historical failure rather than consuming material disk space.

## Removed artifacts

| Source | Pre-cleanup bytes | Files | Source manifest | Preserved archive | Archive manifest | Approximate recovered bytes |
|---|---:|---:|---:|---|---:|---:|
| `joint_qdesn_phase124c_mcmc_balanced_completion_20260711` | 630,192,623 | 38 | 37/37 | `joint_qdesn_phase124c_mcmc_balanced_completion_summary_archive_20260812` | 30/30 | 629,739,769 |
| `joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802` | 205,240,670 | 482 | 31/31 | `joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_summary_archive_20260812` | 29/29 | 204,058,242 |
| timestamped superseded Phase 171 freeze | 813,014 | 29 | 28/28 | current verified Phase 171 freeze | 28/28 | 813,014 |

Total recovered space was approximately 834,611,025 bytes, or 796 MiB.

Phase 124C was superseded by the Phase 154/155 article evidence and is not a
source for the current closeout. Phase 157B was a pre-M0 sampler-development
packet superseded by corrected Phase 169R and Phase 170. The timestamped Phase
171 directory was an unreferenced prior freeze; the current Phase 171 freeze
remains intact and verified.

## Preserved archive contents

Each summary archive contains:

- the original source artifact manifest;
- a recursive source-file inventory with byte counts and SHA-256 hashes;
- run configuration and provenance;
- case-level fit and forecast summaries;
- convergence, scale, crossing, calibration, and runtime summaries relevant to
  the source packet;
- a cleanup completion record;
- a new archive artifact manifest.

Large row-level quantile grids, monotone-adjustment tables, rank histograms,
autocorrelation grids, and superseded posterior-draw payloads were not retained.
They can be identified by hash in `source_file_inventory.csv`, but the archives
are diagnostic history and are not intended to recreate deleted draws.

## Post-cleanup verification

The post-cleanup audit verified 15 manifests and 326 manifest rows with zero
mismatches. This included the original fixtures, all Phase 150/153/154/155
article-lineage packets, corrected Phase 169R, Phase 170, current Phase 171,
complete Phase 172, and both new summary archives.

At cleanup completion, Phase 173 remained active at sustained CPU utilization,
with stable memory and no log error. Its atomic output directory had not yet
been published. No active file or required source was removed.

## Remaining retention rule

Do not prune Phase 172 posterior checkpoints or any source named by the Phase
171 retention policy until Phase 173B, Phase 174 staging, and Phase 175 article
promotion are complete and hash-verified. After Phase 175, perform a separate
closeout audit before deciding whether the 128 Phase 172 chain checkpoints can
be reduced to a frozen pooled posterior and compact diagnostic archive.
