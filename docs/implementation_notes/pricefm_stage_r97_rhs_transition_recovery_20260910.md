# PriceFM Stage-R97 RHS transition recovery

## Scope

This recovery preserves the frozen Stage-R97 scientific design and every completed
Ridge result. It repairs only the handoff from the completed Ridge screen to the
normal-RHS stage. It does not change candidate specifications, validation windows,
ranking, region ownership, likelihood families, worker limits, or promotion rules.
Test scoring, registry mutation, article mutation, joint models, and MCMC remain
blocked.

## Audited state

At 2026-09-10 16:43 America/New_York, Muscat had completed all 2,880 assigned
Ridge bundles, including 614 frozen at the distributed cutover and 2,266 completed
by the host controller. All 2,266 controller status rows were `completed`, and the
2,880 hash-valid compaction terminals remain the resume authority. The controller
then exited before creating any RHS manifest.

Jerez remained healthy with 4,668 of 6,000 Ridge bundles complete, including the
1,042 frozen cutover results. Its live controller had 49 active models, 1,283 queued
bundles, no recorded model failure, approximately 295 GiB free disk, and no `DRAIN`
sentinel. The Jerez controller must not be interrupted for this repair.

Combined Ridge progress was 7,548 of 8,880 bundles, or 22,644 of 26,640 individual
inner-validation model fits. No normal-RHS or AL/exAL surface result existed, so no
scientific winner or article conclusion was available.

## Root cause

`Campaign.prepare_ridge()` intentionally materializes each region's grid as
`ridge_prep/ridge_grid.yaml`. The downstream R93 Ridge-to-RHS script accepts an
explicit `--ridge-grid`, but without that option it looks for
`ridge_prep/pricefm_stage_r93_ridge_grid.yaml`. The R97 controller omitted the
explicit option. The files therefore agreed scientifically but not by basename.

The observed Muscat failure was:

```text
FileNotFoundError: .../regions/AT/ridge_prep/pricefm_stage_r93_ridge_grid.yaml
```

This is a deterministic orchestration defect. It is not a numerical failure, a
selection failure, or evidence against any model family. Every one of the 37 region
directories contains the nonempty intended `ridge_grid.yaml`, and none contains the
legacy default basename.

The first repaired transition completed AT ranking and materialized all 90 AT RHS
configurations. BG then exposed a second input-representation defect: 17 region
manifests store authoritative source folds as integer-like CSV floats (`1.0`, `2.0`,
`3.0`), while the remaining 20 use integer or semicolon-combined text. All 37
manifests normalize exactly to folds 1, 2, and 3, with no fractional or nonfinite
token. The consumer nevertheless called `int("1.0")`. The recovery therefore adds a
strict parser that accepts mathematically integral representations and rejects
fractional or nonfinite values. It does not change any fold assignment.

## Repair contract

1. `319_orchestrate_pricefm_stage_r97_global_campaign.py` passes the actual
   `ridge_prep/ridge_grid.yaml` through `--ridge-grid`.
2. The controller fails closed before running downstream code when that grid is
   missing or empty.
3. A focused test covers both the failed-closed case and the exact path passed to
   the R93 consumer. A second test covers integer, semicolon-combined, and CSV-float
   fold provenance and confirms that fractional values fail closed.
4. A recovery Muscat contract changes only the code identity to the tested repair
   commit. It retains the original checkpoint, assignment, ownership, resources,
   and firewalls, records the original sealed contract, and requires the repair
   commit to descend from the frozen code. The scheduler then scans valid
   `r97_compaction_terminal.json` files and queues no completed Ridge bundle again.
5. The already-running Jerez Python process has the old controller module in memory.
   A compatibility alias from the legacy expected basename to the immutable
   `ridge_grid.yaml` is permitted only after target existence, nonzero size, and
   SHA-256 identity are checked. This lets the live process cross the boundary
   without stopping its healthy Ridge work. The committed controller repair remains
   the authority for every fresh process.
6. The first RHS materialization and model completion on each host must be checked
   before the recovery is considered operationally complete.

## Validation and recovery gates

- focused R93 Ridge-to-RHS tests pass;
- focused R97 global-campaign tests pass;
- focused R97 distributed-continuation tests pass;
- `py_compile` passes for scripts 292, 319, and 324;
- `git diff --check` passes;
- task branch is clean and synchronized before a fresh controller starts;
- all compatibility aliases resolve inside their region's `ridge_prep` directory
  and have the same SHA-256 as `ridge_grid.yaml`;
- no existing Jerez PID is stopped or signaled;
- no test, registry, article, joint, or MCMC action is opened.

## Continuation sequence

After validation, commit and push the scoped repair on the dedicated PriceFM branch.
Create the sealed Muscat recovery contract from the original contract and resume with
the original CPU assignment. On Jerez, install the checked compatibility aliases
while Ridge continues. Monitor Muscat until RHS preparation succeeds and the first
RHS completion is recorded. Jerez should remain untouched until it naturally enters
RHS. If either host fails for any different reason, stop admission, preserve
artifacts, and audit before retrying.

After both hosts finish validation, transfer the Jerez-owned artifact surface using
the existing SHA-256 inventory workflow, reconcile all 37 disjoint closeouts on
Muscat, and keep test sealed until explicit one-time authorization. The final decision
is the frozen unweighted mean AQL across all 114 region-fold cases, compared with the
current complete Q-DESN and cached PriceFM surfaces; there is no per-case veto.
