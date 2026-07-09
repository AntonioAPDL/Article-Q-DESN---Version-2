# Joint QDESN Phase 110 Article Validation Assets

Date: 2026-07-07

## Purpose

Phase 110 converts the completed joint QDESN simulation evidence into article-facing
tables, figures, and audit files. It does not rerun VB, regenerate fixtures, or launch
new MCMC chains.

The stage consumes two frozen sources:

- Phase 107 selected VB freeze:
  `application/cache/joint_qdesn_selected_vb_freeze_phase107_20260707`
- Phase 109 article-candidate MCMC launch:
  `application/cache/joint_qdesn_mcmc_article_phase109_20260707`

This separation is deliberate. Phase 107 is the forecast-validation source because it
contains the selected VB fit and held-out no-refit forecast results for the joint and
independent QDESN/exQDESN RHS rows. Phase 109 is a VB-initialized MCMC fit-reference
layer for the primary Joint QDESN RHS row. Phase 109 supports posterior/reference
stability for the fit window; it is not a forecast-MCMC rerun.

## Audit Findings

The current evidence supports article asset generation now.

- Phase 107 selected `rhs_tau0_0p5_alpha0p5`.
- Phase 107 gate is `review`, not `fail`: outputs are finite, worker failures are zero,
  and contract crossings are zero; review is due to raw crossings and VB max-iteration
  diagnostics.
- Phase 109 completed with `7 pass`, `2 review`, and `0 fail` scenario gates.
- The two Phase 109 review scenarios are `student_t_location_scale` and
  `persistent_heavy_tail`; both reviews are due to the VB warm-start reaching max
  iterations.
- Phase 109 MCMC worker failures are zero.
- Phase 109 raw and contract MCMC crossing counts are zero.
- Phase 109 artifact manifest verification passed for all recorded files.

The optimal next step is therefore an article extraction and readiness layer rather
than another inference launch. Additional sampling would be more expensive and would
not address the immediate need: a clear, reproducible, non-overclaiming presentation of
the selected VB forecast evidence and the MCMC reference evidence.

## Implemented Stage

Phase 110 adds:

- `application/R/joint_qdesn_article_assets.R`
- `application/scripts/110_build_joint_qdesn_article_validation_assets.R`
- `application/tests/test_joint_qdesn_article_validation_assets.R`

The runner verifies source manifests, builds article-facing assets, writes a cache
audit bundle, and records SHA-256 hashes for generated outputs.

Default command:

```bash
Rscript application/scripts/110_build_joint_qdesn_article_validation_assets.R
```

Default audit output:

```text
application/cache/joint_qdesn_article_validation_assets_phase110_20260707
```

## Generated Tables

The runner writes manuscript-facing tables under `tables/`:

- `joint_qdesn_article_validation_protocol.csv/.tex`
- `joint_qdesn_article_validation_vb_model_summary.csv/.tex`
- `joint_qdesn_article_validation_vb_scenario_summary.csv/.tex`
- `joint_qdesn_article_validation_mcmc_scenario_summary.csv/.tex`
- `joint_qdesn_article_validation_gate_summary.csv/.tex`
- `joint_qdesn_article_validation_tables.tex`
- `joint_qdesn_article_validation_asset_manifest.csv`

The VB model table includes all four selected RHS rows:

- Joint QDESN RHS
- Independent QDESN RHS
- Joint exQDESN RHS
- Independent exQDESN RHS

The MCMC table is restricted to the primary Joint QDESN RHS row and is explicitly
described as a fit-reference/readiness layer.

## Generated Figures

The runner writes PDF figures under `figures/joint_qdesn_simulation/`:

- `joint_qdesn_article_validation_vb_fit_forecast_mae.pdf`
- `joint_qdesn_article_validation_vb_forecast_mae_heatmap.pdf`
- `joint_qdesn_article_validation_mcmc_fit_truth_mae.pdf`
- `joint_qdesn_article_validation_mcmc_distance_diagnostics.pdf`
- `joint_qdesn_article_validation_mcmc_hit_rate_by_tau.pdf`
- `joint_qdesn_article_validation_mcmc_overlay_normal_bridge.pdf`
- `joint_qdesn_article_validation_mcmc_overlay_asymmetric_laplace_tail.pdf`
- `joint_qdesn_article_validation_mcmc_overlay_persistent_heavy_tail.pdf`

The overlays show observed data, true conditional quantile paths, and fitted MCMC
quantile paths. They are fit-window diagnostics, not forecast plots.

## Gates

Hard failures remain reserved for:

- missing or failed manifest hashes;
- source worker failures;
- nonfinite scored summaries;
- contract quantile crossings;
- missing provenance or artifact manifests.

Review status is retained for:

- VB max-iteration flags;
- raw pre-contract quantile crossings or nontrivial monotone adjustments;
- article interpretation risks, such as confusing Phase 109 with forecast-MCMC evidence.

The current expected outcome is `review` overall because Phase 107 and Phase 109 both
contain review-level VB diagnostics. This is acceptable for article drafting if the text
states the limitation clearly.

## Next Step

Use the Phase 110 tables and figures to draft the joint QDESN simulation results
subsection. The text should:

- report VB forecast performance from Phase 107;
- report MCMC fit-reference stability from Phase 109;
- state that MCMC was initialized from the selected VB fits;
- retain review language for VB max-iteration scenarios;
- avoid claiming that Phase 109 is rolling-origin forecast MCMC.
