# Joint Multi-Quantile Synthetic DGP Phase 4n DESN/Feature-Spec Screen Plan

Date: 2026-07-06

## Purpose

Phase 4k made the article-facing joint multi-quantile validation reproducible
and noncrossing after the declared monotone forecast contract.  The remaining
diagnostic limitation is raw adjacent-tail crossing before rearrangement.  The
current article-candidate run has 27 raw crossing pairs under the selected
\(\tau_0=0.15\) arm, concentrated in a small number of replicated scenario rows.

This stage launches a broader targeted screen over fit-feature specifications,
which is the joint synthetic lane's closest analogue to DESN specification
screening.  The synthetic fixtures do not currently rebuild full reservoir
states; instead, Phase 3 consumes deterministic DGP design columns.  Therefore
the appropriate screen is to preserve the DGP, seeds, train/test split, truth
quantiles, and scoring contract while changing only the fit-side feature map
used by AL--VB.

## Target Rows

The default source is:

`application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_tau0_candidate_launch_20260704`

The screen selects scenario rows from `launch_crossing_by_scenario.csv` for the
reported `tau0_0p15_comparator` arm with nonzero raw crossings.  These are the
rows that most directly explain the current raw-crossing diagnostic:

- `regime_shift__tau0_candidate_launch_r09`
- `laplace_bridge__tau0_candidate_launch_r06`
- `heteroskedastic_seasonal__tau0_candidate_launch_r06`
- `regime_shift__tau0_candidate_launch_r10`
- `student_t_location_scale__tau0_candidate_launch_r04`
- `student_t_location_scale__tau0_candidate_launch_r05`
- `persistent_heavy_tail__tau0_candidate_launch_r02`
- `laplace_bridge__tau0_candidate_launch_r01`

The seeds come from the frozen Phase 4j launch registry.  No new DGP seeds are
introduced.

## Screened Specifications

The first broad screen crosses feature-map changes with two RHS global-shrinkage
levels already studied in Phase 4g/4h:

- current raw design, \(\tau_0=0.15\);
- current raw design, \(\tau_0=0.10\);
- train-standardized design, \(\tau_0=0.15\) and \(0.10\);
- train-winsorized and standardized design, \(\tau_0=0.15\) and \(0.10\);
- compact core design, \(\tau_0=0.15\) and \(0.10\);
- tail-robust nonlinear design, \(\tau_0=0.15\) and \(0.10\);
- rich interaction design, \(\tau_0=0.15\) and \(0.10\);
- memory-augmented design, \(\tau_0=0.15\) and \(0.10\).

All scaling and clipping parameters are estimated from the declared train split
only and then applied to test rows.  This avoids test leakage while making the
feature-map comparison inspectable.

## Evaluation

Each screen runs the existing Phase 3 forecast-validation runner with the
raw/contract forecast policy:

- raw forecast quantiles are preserved;
- monotone reported quantiles are used for scoring;
- contract crossings remain a hard failure;
- raw crossings are ranked as diagnostics, not hidden.

The default controls match the article-candidate forecast-origin density on the
targeted rows:

- `vb_max_iter = 720`;
- `adaptive_vb_max_iter_grid = 720,960`;
- `refit_stride = 30`;
- `forecast_origin_stride = 10`;
- `max_origins_per_scenario = 100`.

## Ranking Rules

Candidates are compared against `baseline_current_tau0_0p15` using:

1. raw crossing count and raw crossing magnitude;
2. zero contract crossings;
3. truth MAE/RMSE and maximum truth error;
4. pinball, WIS, and CRPS-grid summaries;
5. empirical hit-rate errors;
6. VB maximum-iteration rate;
7. runtime;
8. feature diagnostics, including feature count and train-design condition
   number.

The desired outcome is not to make raw diagnostics disappear by overfitting or
over-smoothing.  A useful candidate should materially reduce raw adjacent-tail
crossings while preserving or improving truth-distance and score summaries.

## Artifacts

The run script is:

`application/scripts/94_run_joint_qvp_synthetic_dgp_phase4n_desn_feature_screen.R`

The default output directory is:

`application/cache/joint_qvp_synthetic_dgp_forecast_phase4n_desn_feature_screen_20260706`

Expected root artifacts include:

- `targeted_registry.csv`
- `target_source_crossing_rows.csv`
- `feature_spec_grid.csv`
- `feature_diagnostics.csv`
- `screen_metric_summary.csv`
- `screen_candidate_ranking.csv`
- `screen_crossing_by_scenario.csv`
- `screen_crossing_by_tau_pair.csv`
- `screen_truth_by_tau.csv`
- `screen_vb_runtime_summary.csv`
- `screen_run_manifest.csv`
- `screen_recommendation.csv`
- `README.md`
- `artifact_manifest.csv`

Nested Phase 3 artifacts are written under `screen_runs/<screen_id>/`.

## Interpretation

This screen is a targeted diagnostic and optimization stage.  It can recommend a
feature specification for a follow-up calibration or article-candidate rerun.  It
does not by itself replace the Phase 4k article-candidate assets.
