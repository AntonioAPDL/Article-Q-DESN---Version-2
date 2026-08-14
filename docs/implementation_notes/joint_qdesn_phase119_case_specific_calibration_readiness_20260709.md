# Joint QDESN Phase 119 Case-Specific Calibration Readiness

Date: 2026-07-09

## Purpose

Phase 119 changes the calibration target from a single global specification to
a case-specific specification policy.  A case is defined as one synthetic
scenario and one model:

- Joint QDESN RHS;
- Independent QDESN RHS;
- Joint exQDESN RHS;
- Independent exQDESN RHS.

This is motivated by the current validation evidence: the primary Joint QDESN
RHS is the strongest global anchor, while exQDESN variants are stable but
tail-compressed in several scenarios.  A single common-control specification is
therefore useful as a fairness/reference diagnostic, but it is not the right
optimization target if the goal is to maximize fit and forecast performance
case by case.

## What Was Implemented

Phase 119 adds an auditable readiness layer in:

- `application/R/joint_qdesn_calibration_screening.R`
- `application/scripts/119_prepare_joint_qdesn_phase119_case_specific_calibration_readiness.R`
- `application/tests/test_joint_qdesn_phase119_case_specific_calibration_readiness.R`

It also extends the screening contract in:

- `application/R/joint_qdesn_simulation_validation.R`
- `application/R/joint_qdesn_vb_spec_screening.R`

The screening registry now supports optional `scenario_ids` and `model_ids`
columns.  Existing registries remain valid; omitted or empty values mean
"all scenarios" and "all models."  New Phase 119 candidate rows set exactly one
scenario and one model per row.

## Readiness Artifacts

The default readiness artifact is:

```text
application/cache/joint_qdesn_phase119_case_specific_calibration_readiness_20260709
```

It writes:

- `phase119_run_config.csv`;
- `source_asset_manifest_verification.csv`;
- `current_model_metric_audit.csv`;
- `case_specific_audit.csv`;
- `phase119_case_specific_screening_registry.csv`;
- priority shard registries such as `phase119_exal_high_priority_registry.csv`;
- `selection_policy.csv`;
- `next_action_plan.csv`;
- `launch_commands.csv`;
- `provenance.csv`;
- `artifact_manifest.csv`;
- `README.md`.

## Case-Specific Registry

Each Phase 119 candidate row includes:

- `scenario_ids`: one scenario id;
- `model_ids`: one model id;
- `case_id`;
- `case_priority`;
- `case_focus`;
- the current case metric used to define the screening priority;
- standard VB/RHS controls already consumed by the Phase 106 runner.

This keeps the implementation wired into the validated Phase 106 fit/forecast
runner while allowing a later audit to select different controls for different
scenarios and models.

## Priority Logic

High-priority cases include:

- exAL cases where the current exAL scenario gap versus the best AL comparator
  is large;
- Joint QDESN RHS cases where the joint AL model is already the scenario winner;
- Independent QDESN RHS cases where the independent AL comparator is already the
  scenario winner.

Moderate and context cases are retained so the final case-specific table does
not overfit only the obvious failures.

## Selection Policy

Selection is performed within case, not globally.  The primary metric is
forecast truth MAE.  Fit truth MAE, check loss, CRPS-grid, hit-rate error,
coverage error, raw monotone adjustment, raw crossings, convergence flags, and
runtime remain required diagnostics.

Hard failures remain implementation-level failures:

- missing or unverifiable manifests;
- worker failures;
- nonfinite quantiles or scores;
- contract quantile crossings.

Raw crossings are retained as diagnostics.  They are not hidden by the monotone
contract, but the reported/scored quantile grid must remain noncrossing.

## Recommended Execution

First let the currently running Phase 118 common-control screen finish unless
spare cores are explicitly available.  Then launch Phase 119 in shards:

1. `exal_high_priority`;
2. `al_high_priority`;
3. `moderate_priority`;
4. `context_priority`.

The generated `launch_commands.csv` contains exact commands.  The first launch
wave should usually target `exal_high_priority`, because it addresses the most
visible current weakness: exQDESN tail fan compression.

The launch commands intentionally use the row-parallel wrapper:

```text
application/scripts/121_launch_joint_qdesn_phase119_parallel_chunks.sh
```

This wrapper verifies the Phase 118 clean-exit marker with POSIX `grep`, checks
the shard registry and fixture paths, splits incomplete candidate rows into
disjoint `--candidate-ids` chunks, records the resolved commands, and launches
multiple Phase 106 screening workers in detached `tmux` sessions.  This avoids a
fragile dependency on `rg` in noninteractive launch shells and uses row-level
parallelism, which is the efficient strategy for Phase 119 because each row
targets exactly one scenario and one model.  The older
`application/scripts/120_launch_joint_qdesn_phase119_case_specific_screening.sh`
remains available as a single-shard fallback/debug launcher.

## Promotion Rule

Phase 119 is still a calibration-preparation stage.  A per-case selected
specification should not replace article tables until it is confirmed on fresh
held-out fixtures or fresh replicate seeds.  After confirmation, article assets
should explicitly record the case-specific specification used for each
scenario/model row.

## Tests

Focused test:

```text
Rscript application/tests/test_joint_qdesn_phase119_case_specific_calibration_readiness.R
```

Adjacent regression checks should include:

```text
Rscript application/tests/test_joint_qdesn_vb_spec_screening.R
Rscript application/tests/test_joint_qdesn_phase118_exal_tail_calibration_readiness.R
```

## Next Step

After Phase 118 finishes, generate the real Phase 119 readiness artifact and
launch the high-priority case-specific shard in the background.  Do not rebuild
article validation tables until the selected per-case specifications pass a
fresh-holdout confirmation layer.
