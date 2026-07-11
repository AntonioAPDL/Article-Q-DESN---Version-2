# Joint QDESN Phase 124 Balanced Completion

Date: 2026-07-11

## Purpose

Phase 123 froze and audited the available MCMC-confirmed joint validation rows.
That artifact is useful, but it is not yet a balanced article table: the
article-facing comparison needs the same scenario-by-model coverage for

- Joint QDESN RHS under AL,
- Independent QDESN RHS under AL,
- Joint exQDESN RHS under exAL, and
- Independent exQDESN RHS under exAL.

Phase 124 fills the missing cells before article promotion.  It does not change
the model implementation and it does not alter manuscript files.  It prepares a
targeted VB/VB-LD completion registry from the already versioned Phase 119
case-specific screening grid, then launches only the missing cells.  MCMC
completion is intentionally deferred until those missing cells have frozen VB
winners.

## Audit Findings

The Phase 123 article-scope matrix contains 17 MCMC-confirmed model-scenario
cells and 15 missing cells.  No scenario has all four model classes confirmed by
MCMC.  Therefore, promoting the current Phase 123 table would mix per-case
optimized MCMC evidence with missing model-scenario rows and would weaken the
main scientific message.

The Phase 119 full case-specific screening registry already contains candidate
grids for all 15 missing cells.  However, the actual fit/forecast artifact
directories for those cells were not materialized in the earlier high-priority
launches.  The correct next step is therefore not MCMC and not a new broad grid:
it is a targeted VB completion launch for the missing cells.

## Implemented Layer

New Phase 124 helpers are implemented in:

```text
application/R/joint_qdesn_phase124_balanced_completion.R
```

The preparation script is:

```text
application/scripts/127_prepare_joint_qdesn_phase124_balanced_completion.R
```

The script writes:

- `run_config.csv`
- `source_manifest_verification.csv`
- `phase124_missing_cells.csv`
- `phase124_vb_completion_registry.csv`
- `phase124_candidate_source_map.csv`
- `phase124_screening_progress.csv`
- `phase124_readiness_gate_summary.csv`
- `health_check_summary.csv`
- `phase124_screening_launch_plan.csv`
- `phase124_mcmc_completion_plan.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

The registry preserves the Phase 119 source candidate identifiers and controls,
but rewrites fit/forecast output paths into the Phase 124 completion root:

```text
application/cache/joint_qdesn_vb_balanced_completion_phase124_20260711
```

This prevents accidental reuse or overwrite of Phase 119 artifacts while keeping
the source provenance explicit.

## Gates

Hard-fail gates:

- Phase 123 freeze manifest mismatch.
- Phase 119 readiness manifest mismatch.
- Missing Phase 119 source candidate rows for any missing balanced cell.
- Invalid Phase 106 screening-registry schema.
- Duplicate candidate identifiers.
- Phase 124 fit/forecast paths still pointing to a Phase 119 screening root.

Review gates:

- The balanced comparison is incomplete until Phase 124 VB and MCMC completion
  finish.
- MCMC launch readiness remains blocked until one VB/VB-LD winner is frozen for
  each missing cell.

Pass gates:

- The Phase 124 registry is complete for all missing cells.
- The registry is schema-valid and hash-manifested.
- The chunked VB screening launch command is recorded reproducibly.

## Launch Sequence

Prepare the Phase 124 artifact:

```bash
Rscript application/scripts/127_prepare_joint_qdesn_phase124_balanced_completion.R
```

Optional dry-run chunk inspection:

```bash
bash application/scripts/123_launch_joint_qdesn_screening_parallel_chunks.sh \
  --registry application/cache/joint_qdesn_phase124_balanced_completion_20260711/phase124_vb_completion_registry.csv \
  --canonical-output-dir application/cache/joint_qdesn_vb_balanced_completion_phase124_20260711 \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --workers 12 \
  --n-cores-per-worker 1 \
  --session-prefix joint_qdesn_phase124_vb_20260711 \
  --run-id phase124_20260711 \
  --incomplete-only true \
  --dry-run true
```

Actual launch:

```bash
bash application/scripts/123_launch_joint_qdesn_screening_parallel_chunks.sh \
  --registry application/cache/joint_qdesn_phase124_balanced_completion_20260711/phase124_vb_completion_registry.csv \
  --canonical-output-dir application/cache/joint_qdesn_vb_balanced_completion_phase124_20260711 \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --workers 12 \
  --n-cores-per-worker 1 \
  --session-prefix joint_qdesn_phase124_vb_20260711 \
  --run-id phase124_20260711 \
  --incomplete-only true \
  --dry-run false
```

After all chunk logs show `EXIT_CODE=0`, build the canonical audit:

```bash
Rscript application/scripts/106_run_joint_qdesn_vb_spec_screening.R \
  --registry application/cache/joint_qdesn_phase124_balanced_completion_20260711/phase124_vb_completion_registry.csv \
  --output-dir application/cache/joint_qdesn_vb_balanced_completion_phase124_20260711 \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --n-cores 1 \
  --reuse-completed true \
  --audit-only true
```

## Next Stage

After Phase 124 VB completion is done:

1. Audit all candidate rows for implementation failures, raw/contract crossings,
   convergence flags, fit truth metrics, forecast truth metrics, check loss, and
   grid CRPS.
2. Freeze one VB/VB-LD winner for each missing model-scenario cell.
3. Run a Phase 122-style VB-initialized MCMC completion only for those missing
   cells.
4. Merge Phase 122 and Phase 124 MCMC evidence into a balanced 32-cell
   article-candidate validation artifact.
5. Touch the manuscript only after the balanced MCMC artifact is complete,
   audited, reproducible, and hash-manifested.
