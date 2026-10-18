# PriceFM R140 frozen all-region rollout

## Purpose

R140 evaluates the R137 pure-QDESN workflow over the complete 38-region,
three-fold PriceFM surface.  It is a computation campaign, not a promotion.
Registry, article, Overleaf, MCMC, joint-model, and exAL mutations remain
disabled.

The four completed R137 regions (`EE`, `HU`, `IT_NORD`, and `SK`) are reused
exactly.  Their sealed closeout evidence is pinned by SHA-256.  The remaining
34 regions are partitioned once across Muscat and Jerez.

## Frozen scientific contract

R140 changes orchestration only.  The controller checks the exact R137 config,
controller, and AL-fitter hashes and compares every scientific field in the
R137 protocol.  The preserved workflow is:

1. Generate 960 balanced training-only candidates and retain at least 640
   admissible candidates, including protected R135 controls.
2. Rank Ridge candidates on three internal forward splits contained wholly in
   fold-1 training data.
3. Fit the top 30 Normal RHS structures plus protected controls at three
   dimension-aware `tau0` magnitudes.
4. Confirm two finalists with seven independent AL quantiles.
5. Freeze one region-level DESN and `tau0` before opening any final fold.
6. Refit Normal RHS and seven AL readouts in each of the three folds and score
   recursive 96-step forecasts with teacher forcing between origins.

The primary operator remains `cdf_pool_clipped`, using 500 posterior paths and
the exact CRAN `exdqlm` 1.1.1 AL fitter at 300 VB iterations plus the existing
same-state fixed-point certificate.

## Resource model

Each host has two disjoint slots.  Each slot owns 15 physical cores, so each
server uses 30 of 32 physical cores and retains two physical cores for the OS
and monitoring.  Every fit is single-threaded.  A slot runs one regional
controller at a time and advances to the next region only after a sealed
regional closeout.

The scheduler never kills an active campaign at a health threshold.  It stops
starting the next region and preserves all evidence.  The host floors are 180
GiB available memory and 80 GiB free disk on Muscat or 50 GiB on Jerez.  These
are queue health reserves, not campaign-size caps.

## Provenance and resumption

Every preparation freezes source, dependency, raw-data, benchmark, training
bank, and runtime hashes.  A source-matched release receipt is mandatory.  An
interrupted host scheduler adopts a live regional controller or resumes the
next incomplete task from sealed task evidence; it never duplicates a region.

Runtime outputs remain under ignored `application/data_local/pricefm` paths.
Tracked source contains only protocol, orchestration, tests, and this note.

## Closeout gate

The all-region closeout refuses to run unless it can verify exactly 38 regions,
114 region-fold cells, four operators per region, the four R137 evidence
hashes, one common R140 source HEAD for the 34 new regions, and a sealed
regional terminal for every campaign.  It produces comparison tables but does
not decide promotion or mutate authority.

## Runtime commands

After a clean commit, each host creates its own release receipt and runs:

```bash
python application/scripts/pricefm/477_release_pricefm_stage_r140.py \
  --dependency <host-specific-r127-worktree> \
  --output application/data_local/pricefm/launch_prep/pricefm_stage_r140_frozen_all_region_rollout_20261018/release

python application/scripts/pricefm/478_schedule_pricefm_stage_r140_host.py run \
  --host <muscat-or-jerez> \
  --dependency <host-specific-r127-worktree> \
  --release application/data_local/pricefm/launch_prep/pricefm_stage_r140_frozen_all_region_rollout_20261018/release/validation.json
```

The schedulers are launched with `nohup` from the clean R140 worktree.  Their
progress and terminal receipts live below the corresponding ignored
`launch_prep` directory.
