# Joint QDESN Phase 125 Balanced MCMC Audit

Date: 2026-07-12

## Purpose

Phase 125 freezes the completed balanced MCMC evidence layer for the joint QDESN synthetic validation study.

The immediate motivation is that the final MCMC evidence is now split across two completed source artifacts:

- Phase 122: the original case-specific MCMC confirmation block with 17 rows.
- Phase 124c: the missing-cell MCMC completion block with 15 rows.

Together these should form the intended balanced validation grid:

- 8 synthetic scenarios.
- 4 model classes per scenario.
- 32 scenario-model MCMC confirmation rows.

Phase 125 does not run VB, VB-LD, MCMC, fixture generation, or manuscript edits. It is a reproducibility and readiness layer that consumes frozen CSV artifacts, verifies their SHA-256 manifests, checks the balanced grid, and writes compact article-candidate summaries.

## Source Artifacts

Default source blocks:

```text
application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711
application/cache/joint_qdesn_phase124c_mcmc_balanced_completion_20260711
```

Default Phase 125 output:

```text
application/cache/joint_qdesn_phase125_balanced_mcmc_audit_20260712
```

## Design

The Phase 125 audit:

1. Loads each source MCMC block using the existing Phase 122/123 schema checks.
2. Verifies each source artifact manifest.
3. Preserves source-block labels for traceability.
4. Merges case summaries, case assessments, forecast summaries, fit summaries, VB-MCMC distances, chain summaries, runtime summaries, and source manifests.
5. Checks the expected 8-by-4 balanced scenario-model grid.
6. Fails on missing or duplicated scenario-model rows, source manifest failures, worker failures, nonfinite MCMC draws, missing VB initialization, scalar predictive-density claims, or contract quantile crossings.
7. Keeps raw crossings and VB initialization diagnostics as review-level evidence, not hard failures.
8. Writes compact CSV and LaTeX tables for article-asset construction, but does not mutate article files.

The output intentionally references the heavy source MCMC artifacts rather than copying full quantile-grid files. This keeps Phase 125 small, inspectable, and reproducible while preserving traceability to the full source outputs through manifest hashes.

## Predictive Contract

The validation remains a quantile-grid/readout validation. The composite AL/exAL likelihood is treated as a working likelihood for quantile-path inference, not as a unique scalar posterior predictive density.

Consequently:

- Oracle quantile MAE/RMSE, check loss, grid CRPS, hit-rate/coverage diagnostics, and crossing diagnostics remain valid.
- Reported scores use monotone contract quantile grids.
- Raw crossings are retained as diagnostics.
- No scalar posterior predictive-density validation is claimed by Phase 125.

## Generated Files

The Phase 125 artifact writes:

- `run_config.csv`
- `source_blocks.csv`
- `source_block_summary.csv`
- `source_artifact_manifest_verification.csv`
- `source_vb_freeze_manifest_verification.csv`
- `fixture_source_manifest_verification.csv`
- `combined_mcmc_case_summary.csv`
- `combined_mcmc_case_assessment.csv`
- `model_confirmation_summary.csv`
- `scenario_model_confirmation_summary.csv`
- `scenario_winner_summary.csv`
- `balanced_scope_matrix.csv`
- `balanced_scope_by_model.csv`
- `balanced_scope_decision.csv`
- `balanced_gate_summary.csv`
- `health_check_summary.csv`
- `raw_contract_crossing_summary.csv`
- `raw_crossing_diagnostic_summary.csv`
- `vb_mcmc_delta_summary.csv`
- `chain_stability_summary.csv`
- `runtime_summary.csv`
- combined fit and forecast score summaries
- compact article-candidate CSV/TeX tables
- `article_promotion_recommendation.csv`
- `article_integration_plan.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

## Gates

Hard fail:

- source manifest hash failures;
- source worker failures;
- missing or duplicated balanced scenario-model rows;
- nonfinite MCMC draw summaries;
- missing VB initialization;
- contract quantile crossings;
- scalar posterior predictive-density claim.

Review:

- raw pre-contract crossings;
- VB initialization max-iteration diagnostics inherited from the selected winners;
- VB-to-MCMC distance or chain-distance review statuses.

Pass:

- all source, manifest, balanced-grid, MCMC finiteness, VB initialization, contract-crossing, and predictive-contract gates pass.

## Commands

Focused test:

```bash
Rscript application/tests/test_joint_qdesn_phase125_balanced_mcmc_audit.R
```

Generate the real Phase 125 artifact:

```bash
Rscript application/scripts/129_freeze_joint_qdesn_phase125_balanced_mcmc_audit.R
```

Optional explicit source paths:

```bash
Rscript application/scripts/129_freeze_joint_qdesn_phase125_balanced_mcmc_audit.R \
  --phase122-dir application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711 \
  --phase124c-dir application/cache/joint_qdesn_phase124c_mcmc_balanced_completion_20260711 \
  --output-dir application/cache/joint_qdesn_phase125_balanced_mcmc_audit_20260712
```

## Current Recommendation

If Phase 125 hard gates pass, the balanced MCMC evidence is ready for the next article-safe stage: rebuild article validation tables and figures from the Phase 125 artifact, then perform manuscript QA and compile.

The article should still use review language for raw crossings and VB initialization diagnostics. The final evidence should say that VB/VB-LD performed screening/calibration/initialization and that MCMC provides the balanced article-facing confirmation layer.
