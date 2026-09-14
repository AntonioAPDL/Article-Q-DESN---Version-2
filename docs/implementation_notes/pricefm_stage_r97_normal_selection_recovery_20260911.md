# PriceFM Stage-R97 normal-selection recovery

## Scope and decision

This recovery repairs the deterministic handoff from completed coarse normal-RHS
screening to conditional `tau0` refinement. It does not alter the 240-arm Ridge
bank, top-30 rule, coarse `tau0` values, validation windows, candidate ranking,
region ownership, likelihood implementations, or final complete-surface decision.
No Ridge or coarse-RHS model is to be refitted. Test access, registry and article
mutation, joint models, and MCMC remain blocked.

The optimal continuation is to preserve Jerez's healthy live RHS shard, repair the
shared closeout code, and resume only Muscat from its compacted terminals under a
new descendant-bound recovery contract.

## Audited state

At 2026-09-11 13:57 America/New_York:

- all 8,880 Ridge bundles were complete across Muscat and Jerez;
- Muscat had completed and compacted all 1,080 assigned coarse-RHS bundles, but
  its controller had exited at `normal_selection` before any refinement fit;
- Jerez had crossed the previously repaired Ridge-to-RHS boundary, created all 25
  regional RHS manifests, and completed 419 of 2,250 RHS bundles with 49 workers;
- all reported Muscat and Jerez completions had matching compaction terminals;
- no R execution failure, traceback, segmentation fault, OOM, or killed model was
  found in the completed model logs;
- both task worktrees were clean and synchronized at
  `aea12fa083425453d8f505ae29f15b8c87bdaaf2` before this repair;
- test, registry, article, joint-model, and MCMC firewalls remained closed.

The minimum model-fit surface was 31,137 of 38,295 complete. The remaining minimum
surface comprised 5,493 coarse-RHS fits on Jerez and 1,665 normal/AL/exAL surface
fits. Conditional refinement can add at most 333 fits, and the final 111 no-refit
test evaluations remain a separate post-reconciliation authorization.

## Root cause

`292_advance_pricefm_stage_r93_ridge_to_rhs.py` retained `feature_dim` in both the
selected Ridge table and each RHS YAML experiment but omitted it from
`pricefm_stage_r93_rhs_coarse_launch_manifest.csv`.

`294_advance_pricefm_stage_r93_validation_ladder.py` joined completed coarse-RHS
metrics to that CSV and later accessed `winner.feature_dim` while constructing a
refinement manifest. The first Muscat region, AT, correctly triggered refinement
and failed with:

```text
AttributeError: 'Series' object has no attribute 'feature_dim'
```

The error occurred after AT's ranking and refinement decision were written but
before its closeout summary was written. The host controller therefore failed
closed. This was a schema propagation defect, not a fit, convergence, ranking, or
scientific-design failure.

## Recoverability audit

All 37 regional coarse-RHS manifests contain exactly 90 unique experiment IDs.
For every region, those IDs match the corresponding immutable RHS YAML experiment
set one-to-one. Every matching YAML experiment has a positive integer
`feature_dim`. Therefore all omitted values are recoverable exactly from the
scientific configuration that produced the model; no heuristic reconstruction,
test metric, or refit is needed.

The 12 completed Muscat coarse surfaces all triggered the pre-registered
refinement rule:

| Trigger | Regions |
|---|---|
| coarse `tau0` boundary | AT, BG, EE, ES, FI, LV, SE_3, SK |
| same-geometry near tie | IT_CSUD, IT_SARD |
| numerically incomplete coarse alternatives | NO_3, PL |

The coarse winning `tau0` values were region-specific: five regions selected
`1e-4`, four selected `1e-3`, and three selected `1e-2`. These are validation-only
intermediate findings and are not final candidate or article evidence.

## Repair contract

1. Future coarse-RHS CSV manifests carry `feature_dim` directly from the selected
   Ridge row.
2. The normal-selection closeout requires unique experiment IDs and exact equality
   between the manifest ID set and source-grid experiment ID set.
3. A missing legacy `feature_dim` is recovered only from the same experiment in
   the RHS YAML. A present value must match exactly. Missing, fractional,
   nonpositive, nonfinite, duplicate, or conflicting values fail closed.
4. The closeout emits a row-level geometry audit recording whether each value was
   verified or recovered and binds the source grid by SHA-256 in its summary.
5. Refinement construction rechecks the selected value against the source YAML.
6. A summary-less coarse closeout can be replaced only with the explicit
   `--resume-incomplete-closeout true` option. Every existing path must belong to a
   fixed allowlist, symlinks and unexpected files are rejected, and prior file
   hashes are written before downstream work resumes.
7. The R97 host controller supplies that explicit option. Completed closeouts are
   never replaced because their `summary.json` causes the controller to skip the
   action and the closeout command independently refuses to replace one.

## Validation gates

The focused validation must include:

```bash
PY=/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv/bin/python
$PY -m py_compile \
  application/scripts/pricefm/292_advance_pricefm_stage_r93_ridge_to_rhs.py \
  application/scripts/pricefm/294_advance_pricefm_stage_r93_validation_ladder.py \
  application/scripts/pricefm/324_orchestrate_pricefm_stage_r97_host_shard.py
$PY -m pytest -q \
  application/tests/test_pricefm_stage_r93_ridge_to_rhs.py \
  application/tests/test_pricefm_stage_r93_validation_ladder.py \
  application/tests/test_pricefm_stage_r97_global_region_campaign.py \
  application/tests/test_pricefm_stage_r97_distributed_continuation.py
git diff --check
```

Tests cover future manifest propagation, exact legacy recovery, ID drift and value
mismatch rejection, bounded partial-closeout replacement with prior hashes, exact
refinement propagation, existing scientific gates, host isolation, and the explicit
controller resume option.

## Operational continuation

1. Commit and push the tested repair only to the dedicated PriceFM branch.
2. Fast-forward the clean Jerez task worktree while its existing controller keeps
   running. The live controller invokes script 294 as an external process when RHS
   completes, so the repaired file will be used without restarting healthy fits.
3. Rebind the Muscat recovery contract to the tested descendant commit while
   preserving the frozen checkpoint, assignment, ownership, worker count, and all
   scientific firewalls. Record the normal-selection schema repair as the explicit
   recovery reason and forbid refitting either completed screening phase.
4. Restart only Muscat with its existing 20 one-core CPU assignment. Its 2,880
   Ridge and 1,080 coarse-RHS compaction terminals must all validate and be skipped.
5. Confirm that AT records its recognized partial-closeout hashes, all 12 coarse
   closeouts complete, exactly three refinement arms are materialized per region,
   and the first refinement terminal is valid.
6. Confirm Jerez's first successful normal-selection/refinement transition when its
   coarse RHS surface finishes. Do not restart Jerez unless it fails for a new,
   separately audited reason.
7. Complete both validation shards, transfer the Jerez-owned surface with the
   SHA-256 inventory, and reconcile 37 disjoint regional closeouts on Muscat.
8. Open the 111 no-refit test cases only after reconciliation and separate explicit
   authorization. Apply the frozen 114-case mean-AQL gate against authoritative
   Q-DESN (`6.823677420470439`) and cached PriceFM (`7.038685346534470`).

No article or registry promotion is justified until that final complete-surface
closeout exists.

## Subsequent surface-preprocessing recovery

The normal-selection recovery completed all 36 Muscat refinement bundles and
froze all 12 selected normal contracts. A later, independent orchestration defect
was then exposed at the next boundary: the shared preprocessing seal removed the
top-level `pricefm` mapping before passing the configuration to
`window_npz_path()`, which requires the full mapping. See
`pricefm_stage_r97_surface_preprocessing_recovery_20260911.md` for the audited
repair and continuation procedure. The selected contracts and completed model
artifacts remain authoritative and must not be refitted.
