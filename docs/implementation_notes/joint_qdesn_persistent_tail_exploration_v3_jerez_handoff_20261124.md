# Jerez execution handoff: persistent-heavy-tail v3

This handoff transfers only the dedicated v3 execution lane. It does not
authorize main, article, or Overleaf changes.

## Required source

- Branch: `work/joint-qdesn-persistent-tail-exploration-v3-20261124`
- Parent HEAD: `a097b01df88496cacb75b86027aaa0dfe9e18825`
- Pinned R: `/data/jaguir26/local/opt/R/4.6.0/bin/Rscript`
- Host: `jerez.be.ucsc.edu`
- Runtime: `application/cache/joint_qdesn_persistent_tail_exploration_v3_20261124`

The preparation source HEAD is `517f5926e2a636889f28ded2c5bb02702beb95d4`.
N0 closed at `39d813c3c9aa65cde663d91d0050024e12525711` after correcting its
matched-equivalence audit. A1 numerical workers ran at that same HEAD. Its
finalizer and every later numerical stage used
`ab7a6c976016af0e3a91cf265483d294197457f9`, which only added the reviewed
historical-control selection classification. The A1 workers did not require a
rerun because that correction changes finalization, not worker calculations.

## Preflight

1. Fetch the branch with command-line Git and create a dedicated Jerez worktree.
2. Confirm the branch tracks its matching remote and is exactly `0 ahead / 0 behind`.
3. Run the focused v3 test under pinned R 4.6.0.
4. Confirm no competing JOINT, GloFAS, or PriceFM `R`/`Rscript` model process.
5. Confirm at least 80 GiB free under `/data` and 128 GiB available memory.
6. Select at most 30 logical CPU IDs representing distinct physical cores.
7. Prepare a new, empty runtime and run the v3 checker.

## Execution

Run stages only in this order:

`N0 -> A1 -> A2 -> A3 -> H1 -> H2 -> M1 -> T1 -> Q3`

Use:

```bash
CPU_LIST=<reviewed-distinct-physical-core-ids> \
  application/scripts/launch_joint_qdesn_persistent_tail_exploration_v3_stage.sh \
  application/cache/joint_qdesn_persistent_tail_exploration_v3_20261124 <stage>
```

After a stage completes, inspect health and diagnostics, then run the separate
finalizer. Never combine launch and finalization in one command. A finalizer may
prepare the next plan but never launches it.

## Stop conditions

Stop on any worker failure, manifest mismatch, protected-row use, nonfinite
score, lost exact control, empty realized reservoir, pathological recursive
state, failed supercritical perturbation gate, or violated stage cardinality.

N0 must establish the reviewed tiny-scale equivalence before A3 may prepare H1.
T1 must freeze four new challengers before confirmation fixtures are created.
Q3 is the terminal stage in this lane. Do not launch full joint/independent
AL/exAL VB or MCMC from this handoff.

## Completed execution

All nine stages completed with zero worker failures:

`N0 90/90; A1 12,288/12,288; A2 3,072/3,072; A3 1,152/1,152;
H1 1,344/1,344; H2 300/300; M1 288/288; T1 60/60; Q3 18/18`.

Q3 contains 126 complete component fits. All component fits converged, all
reported scores are finite, contract crossings and protected-row use are zero,
and every frozen manifest verifies. The terminal decision is
`SEALED_Q3_COMPLETE_RECOMMEND_CASE_LEVEL_CONTINUATION`. No downstream job was
launched.

The best finalist is `q3_challenger_02` / `persistent_heavy_tail__v3_1866`.
Its sealed mean score is `0.5163734617`, versus `0.5211643012` for the exact v2
winner. The matched absolute improvement is `0.0047908395` (about `0.919%`),
and all three confirmation replicates favor the challenger. This is sufficient
under the frozen contract to recommend a separately frozen four-model
continuation. It is not sufficient to replace article authority directly.

## Isolation

Do not modify or delete the v2 runtime, any other lane, main, article files,
Overleaf branches, or active model jobs. Runtime outputs remain ignored. Commit
and push source/reproducibility changes only on the dedicated v3 branch.
