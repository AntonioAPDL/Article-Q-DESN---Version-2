# PriceFM DE_LU Fold 2/3 Deep Targeted Median Grid Results

Date: 2026-06-03

## Scope

This note records the completed deep targeted median grid for PriceFM `DE_LU`
folds 2 and 3, including the optional P2 feature-geometry diagnostics. The run
was intended to test whether a broader but still targeted reservoir search could
improve the fold-specific median Q-DESN specifications before promoting them to
the seven-quantile PriceFM comparison workflow.

This was a model-selection and diagnostics pass only. It did not modify the
PriceFM data pipeline, the paper-reference predictions, or the promoted
seven-quantile comparison outputs.

## Inputs

- Grid config:
  `application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_deep_targeted_20260603.yaml`
- Grid id:
  `pricefm_median_de_lu_folds23_deep_targeted_20260603`
- Region:
  `DE_LU`
- Folds:
  `2,3`
- Selection split:
  validation
- Selection unit:
  original scale
- Selection metric:
  `AQL`
- Selection methods:
  `qdesn_exal_rhs_ns_exact_chunked`,
  `qdesn_al_rhs_ns_exact_chunked`

## Launch Summary

The grid was launched in two phases.

| Phase | Experiments | Cells | Status | Wall Time | Max RSS |
|---|---:|---:|---|---:|---:|
| P0 smoke | 6 | 12 | complete | 1:04:17 | 1,279,872 KB |
| P1 main | 162 | 324 | complete | 12:49:56 | 1,443,532 KB |
| P2 optional feature diagnostics | 21 | 42 | complete | 16:37:29 | 8,953,920 KB |

Local logs:

- `application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_deep_targeted_20260603/launch_logs/priority0_launch.time.log`
- `application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_deep_targeted_20260603/launch_logs/priority1_launch.time.log`
- `application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_deep_targeted_20260603/launch_logs/priority2_launch.time.log`

All selected P0/P1/P2 cells completed:

- `priority = 0`: 12 / 12 cells complete
- `priority = 1`: 324 / 324 cells complete
- `priority = 2`: 42 / 42 cells complete

No current-pass PriceFM DESN grid/model processes were active at the final
health check. The run directory was about 15 GB, and `/data` still had about
732 GB free, so the run completed without creating a storage pressure incident.

## Registry Outputs

The selection registry was regenerated after fixing the selector report column
deduplication issue. The original P0/P1 registry is preserved, and the final
P0/P1/P2 registry is the source for the completed-grid diagnostics.

P0/P1 registry path:

`application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_deep_targeted_registry_20260603/`

P0/P1/P2 registry path:

`application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_p2_registry_20260603/`

Important files:

- `median_selection_registry.csv`
- `median_candidate_rankings.csv`
- `median_candidate_metrics.csv`
- `median_candidate_completion.csv`
- `median_selection_registry_report.md`
- `summary.json`

P0/P1 diagnostic summary path:

`application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_deep_targeted_diagnostics_20260603/`

P0/P1/P2 diagnostic summary path:

`application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_p2_diagnostics_20260603/`

Important files:

- `completion_summary.csv`
- `selection_delta_summary.csv`
- `top_candidates_compact.csv`
- `stage_pattern_summary.csv`
- `horizon_group_diagnostics.csv`
- `horizon_group_delta_summary.csv`
- `seven_quantile_pricefm_context.csv`
- `median_grid_diagnostics_report.md`
- `figures/median_registry_new_vs_previous_aql.png`
- `figures/median_horizon_group_delta_aql.png`
- `figures/seven_quantile_phase1_context_aql.png`

These outputs are under `application/data_local/` and are intentionally ignored
by git.

## Selection Result

The new deep targeted grid did not beat the previous promoted fold-specific
median registry.

| Fold | Previous Experiment | Previous Val AQL | Previous Test AQL | New Experiment | New Val AQL | New Test AQL | Val Delta | Test Delta | Decision |
|---:|---|---:|---:|---|---:|---:|---:|---:|---|
| 2 | `rf_p0_f23_d1n120_l072_a0p50_r0p90_in0p50_seed20260601` | 6.181033 | 7.017320 | `rfdeep_p1_input_lag_window96_units120_rho0p9_input_scale0p25` | 6.194532 | 7.033291 | 0.013498 | 0.015971 | Retain previous |
| 3 | `rf_p0_f23_d1n080_l096_a0p50_r0p90_in0p50_seed20260601` | 6.765381 | 8.559254 | `rfdeep_p1_input_lag_window96_units80_rho0p97_input_scale0p35` | 6.798915 | 8.583866 | 0.033534 | 0.024612 | Retain previous |

Lower AQL is better. Both new validation winners are worse than the previous
registry on validation and also worse on the held-out test audit.

## Horizon Diagnostics

The new deep-grid winners improve the first horizon group, but lose enough in
later horizon groups to lose the fold-level selection gate.

| Fold | Horizon Group | Previous Median AQL | New Median AQL | New Minus Previous |
|---:|---|---:|---:|---:|
| 2 | 1-24 | 3.765461 | 3.615623 | -0.149838 |
| 2 | 25-48 | 8.060998 | 8.263051 | 0.202053 |
| 2 | 49-72 | 8.839639 | 8.834721 | -0.004918 |
| 2 | 73-96 | 7.403180 | 7.419768 | 0.016588 |
| 3 | 1-24 | 6.335374 | 6.031487 | -0.303888 |
| 3 | 25-48 | 8.797448 | 8.864572 | 0.067124 |
| 3 | 49-72 | 10.057397 | 10.321947 | 0.264550 |
| 3 | 73-96 | 9.046797 | 9.117456 | 0.070660 |

Interpretation: the search found short-horizon repairs but not a better
overall median model. This points toward feature geometry or horizon-specific
structure rather than another blind reservoir hyperparameter expansion.

## P2 Feature-Geometry Diagnostics

The optional P2 diagnostics completed, but they did not produce a promotable
candidate. The final P0/P1/P2 selector still chose P1 input-scale candidates,
and both were worse than the previous authoritative registry.

P2 was useful because it ruled out an attractive but expensive hypothesis: that
direct flat lag windows or large random window projections would quickly close
the fold 2/3 gap. In this implementation, they did not.

Key P2 findings:

- Direct flat lag windows were not competitive with the D1 reservoir winners.
- Larger projected feature maps were not competitive either.
- The best P2 optional-window DESN projection was still far behind the retained
  D1 reservoir registry.
- The good local signal remains around short contexts, low-to-moderate input
  scale, and D1 reservoirs, not broader projection capacity.

Representative P2 validation AQL levels:

| Fold | P2 Pattern | Best Validation AQL | Interpretation |
|---:|---|---:|---|
| 2 | optional window DESN projection | 9.849500 | Far worse than retained 6.181033 |
| 2 | direct flat lag window | 10.783741 | Far worse than retained 6.181033 |
| 3 | optional window DESN projection | 10.222126 | Far worse than retained 6.765381 |

The P2 result should be treated as a feature-geometry diagnostic, not as a
failed production launch. It says that the current flat/window projection path
is not the right way to improve these folds without first auditing the feature
construction, scaling, and horizon-specific information geometry.

## PriceFM Reference Context

The prior local PriceFM comparison is a seven-quantile comparison and should not
be read as a median-only registry selector. It is still useful context for the
eventual paper-style evaluation.

| Fold | Method | Seven-Quantile Test AQL | MAE | RMSE |
|---:|---|---:|---:|---:|
| 2 | `pricefm_phase1_pretraining` | 5.355079 | 13.235907 | 20.013961 |
| 2 | `qdesn_exal_rhs_ns_exact_chunked` | 5.627840 | 14.034639 | 21.203163 |
| 2 | `qdesn_al_rhs_ns_exact_chunked` | 5.674629 | 14.099082 | 21.222417 |
| 3 | `pricefm_phase1_pretraining` | 6.029767 | 14.783424 | 25.517975 |
| 3 | `qdesn_exal_rhs_ns_exact_chunked` | 7.015117 | 17.118508 | 26.954982 |
| 3 | `qdesn_al_rhs_ns_exact_chunked` | 7.135959 | 17.191822 | 27.019668 |

The seven-quantile context confirms that folds 2 and 3 remain weaker than the
local PriceFM Phase-I baseline, especially fold 3.

## Code Changes

Two small reproducibility improvements were added.

1. `application/scripts/pricefm/20_select_pricefm_desn_median_specs.py`

   - Deduplicates report/ranking columns when the selected metric is already
     `AQL`.
   - Escapes markdown table values with newlines or pipes.

2. `application/scripts/pricefm/22_summarize_median_grid_diagnostics.py`

   - Summarizes a completed median grid without refitting models.
   - Compares a new registry against a previous registry.
   - Records completion, selected-spec deltas, top candidates, pattern summaries,
     horizon-group diagnostics, seven-quantile PriceFM context, and diagnostic
     figures.

## Reproducibility Commands

Regenerate the P0/P1 fixed selection registry report:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/20_select_pricefm_desn_median_specs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_deep_targeted_20260603.yaml \
  --priorities 0,1 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_deep_targeted_registry_20260603 \
  --regions DE_LU \
  --folds 2,3 \
  --selection-split val \
  --selection-unit original \
  --selection-metric AQL \
  --require-complete true
```

Regenerate the local diagnostic report:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/22_summarize_median_grid_diagnostics.py \
  --new-registry-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_deep_targeted_registry_20260603 \
  --previous-registry-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_selection_registry_20260602 \
  --pricefm-summary application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_folds123_20260602/fold_metric_summary.csv \
  --pricefm-fold-template application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold{fold}_20260602 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_deep_targeted_diagnostics_20260603 \
  --region DE_LU \
  --folds 2,3
```

Regenerate the final P0/P1/P2 selection registry:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/20_select_pricefm_desn_median_specs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_deep_targeted_20260603.yaml \
  --priorities 0,1,2 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_p2_registry_20260603 \
  --regions DE_LU \
  --folds 2,3 \
  --selection-split val \
  --selection-unit original \
  --selection-metric AQL \
  --require-complete true
```

Regenerate the final P0/P1/P2 diagnostic report:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/22_summarize_median_grid_diagnostics.py \
  --new-registry-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_p2_registry_20260603 \
  --previous-registry-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_selection_registry_20260602 \
  --pricefm-summary application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_folds123_20260602/fold_metric_summary.csv \
  --pricefm-fold-template application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold{fold}_20260602 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_p2_diagnostics_20260603 \
  --region DE_LU \
  --folds 2,3
```

Script checks:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/20_select_pricefm_desn_median_specs.py \
  application/scripts/pricefm/22_summarize_median_grid_diagnostics.py
git diff --check
```

## Decision

Do not promote the deep targeted grid winners.

Keep the previous fold-specific median registry as the authoritative fold 2/3
median source:

`application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_selection_registry_20260602/`

This decision still holds after the completed P2 diagnostics.

## Recommended Next Work

The next work should not be another broad `alpha/rho/n/L` reservoir sweep, and
it should not be another large flat/window-projection sweep until the P2 feature
geometry is audited.

Recommended checklist:

- [x] Keep the previous fold 2/3 median registry authoritative.
- [x] Complete the optional P2 feature-geometry diagnostic.
- [x] Confirm P2 does not change the authoritative fold 2/3 median decision.
- [x] Write the detailed next-stage feature-geometry plan:
      `docs/implementation_notes/pricefm_de_lu_folds23_next_feature_geometry_plan_20260604.md`.
- [x] Implement and run the no-fit feature-geometry and horizon-block
      diagnostics:
      `docs/implementation_notes/pricefm_de_lu_folds23_feature_geometry_diagnostics_20260604.md`.
- [ ] Use the diagnostic script whenever a candidate registry needs to be
      compared against the promoted registry.
- [x] Audit the flat/window feature geometry before launching more P2-like
      grids: feature counts, ranks, scaling, saturation, horizon alignment, and
      variance/correlation structure.
- [x] Investigate horizon-specific structure because the new specs improve
      horizons 1-24 but hurt 25-96.
- [ ] Consider a validation-only horizon-block selector that can retain the
      previous model for mid/long horizons while using a local short-horizon
      candidate, with strict no-leakage controls.
- [ ] Run seed-robustness checks around the retained fold-specific winners
      before changing the promoted median registry.
- [ ] Prioritize multi-scale lag features, calendar/regime features, and
      feature-normalization diagnostics over larger random reservoirs.
- [ ] Only rerun the seven paper quantiles after the median source registry is
      stable for each region/fold.
- [ ] Keep all large generated outputs under `application/data_local/` and
      track only scripts, configs, and concise documentation.
