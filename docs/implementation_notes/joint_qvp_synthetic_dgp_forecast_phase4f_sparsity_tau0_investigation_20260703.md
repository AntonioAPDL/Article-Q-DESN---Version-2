# Joint-QVP Synthetic DGP Forecast Validation: Phase 4f Sparsity/Tau0 Investigation

Date: 2026-07-03

## Purpose

Phase 4e showed that stronger VB controls materially improved max-iteration behavior but did not materially reduce raw forecast quantile crossings. This note records the next model-side investigation: whether stronger RHS sparsity, more similar adjacent quantile coefficients, or DESN/readout design controls are the right levers before another full calibration campaign.

## Artifact

Diagnostic artifact:

`application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4f_sparsity_tau0_diagnostics`

Data/truth/fit overlay artifact:

`application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4e_targeted_crossing_followup_vb480/phase4f_data_truth_fit_overlays`

The artifact contains:

- `01_raw_contract_crossing_counts_by_scenario.png`
- `02_vb_max_iter_rate_vs_raw_crossings.png`
- `03_max_monotone_adjustment_by_scenario.png`
- `04_crossing_magnitude_by_tau_pair.png`
- `05_qhat_ladder_examples_baseline_vs_vb480.png`
- `06_crossing_origin_set_overlap.png`
- `07_rhs_tau0_prior_precision_curve.png`
- `08_tau_pair_crossing_heatmap.png`
- `phase4f_summary.csv`
- `phase4f_prior_interpretation.csv`
- `phase4f_rhs_prior_tau0_precision_grid.csv`
- `phase4f_sparsity_recommendation.csv`
- `phase4f_plot_index.csv`
- `artifact_manifest.csv`

Generation command:

```bash
Rscript application/scripts/83_plot_joint_qvp_phase4f_sparsity_tau0_diagnostics.R
Rscript application/scripts/84_plot_joint_qvp_phase4f_data_truth_fit_overlays.R
```

The overlay artifact plots the retained train/test observations, oracle true conditional quantile dynamics, and the Phase 4e stronger-VB contract forecast quantiles at the rolling-origin test rows. Red dashed horizontal segments identify raw adjacent crossing levels before the noncrossing contract is applied.

## Main Numerical Findings

The Phase 4f plots use the exact Phase 4d full contract calibration and the Phase 4e targeted stronger-VB follow-up.

- Tau grid size: 7 quantiles, `0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95`.
- Baseline raw crossing pairs: 23.
- Stronger-VB raw crossing pairs: 22.
- Raw crossing reduction fraction: 0.04347826.
- Baseline contract crossing pairs: 0.
- Stronger-VB contract crossing pairs: 0.
- Baseline targeted-row VB max-iteration rate: 0.69230769.
- Stronger-VB targeted-row VB max-iteration rate: 0.125.

Interpretation: stronger VB controls fix much of the convergence review signal, but the raw crossing pattern is mostly stable. The raw crossings therefore look less like a pure iteration-limit artifact and more like an output/readout regularization and extreme-tail stability issue.

## RHS Prior Direction

The implemented RHS prior precision is:

```text
precision = 1 / (tau2 * lambda2) + 1 / zeta2
```

and the RHS state initializes:

```text
tau2 = tau0^2
```

Therefore, all else fixed, larger `tau0` decreases prior precision and increases prior variance. In the current implementation, a larger `tau0` is weaker RHS shrinkage, not stronger shrinkage.

This is important for the next experiment: if the goal is to reduce noisy readout coefficients, the direct direction is smaller `tau0`, finite/smaller `zeta2`, or a more explicit adjacent-innovation shrinkage design.

## Sparsity And Coefficient Similarity Recommendation

More sparsity may help, but the most careful version is not simply to shrink every readout coefficient equally. The joint-QVP RHS prior is structured through an anchor plus adjacent quantile innovations. Crossings are adjacent-tail failures, so the highest-value experiment is to shrink adjacent innovations more strongly while allowing the shared anchor readout to remain flexible.

Recommended targeted sensitivity before any full rerun:

- Preserve the exact Phase 4e targeted crossing rows and seeds.
- Keep the raw/contract forecast policy.
- Test smaller global RHS scales, for example `tau0 in {1, 0.5, 0.25, 0.1}`.
- Test finite slab scales, for example `zeta2 in {Inf, 10, 4, 1}`.
- If feasible, add a narrow experimental option separating `anchor_tau0` and `innovation_tau0`, with stronger shrinkage on innovations.
- Track raw crossings, monotone adjustment size, truth distance, hit-rate error, VB max-iteration rate, and runtime.

## DESN/Readout Design Recommendation

A better DESN design can also reduce raw crossings if crossings are driven by unstable or noisy features. The safe audit order is:

1. Confirm feature standardization and retained-feature scale by scenario.
2. Audit whether crossing origins have unusually large design-feature norms.
3. Test a targeted readout-design sensitivity on the same crossing rows before full calibration.
4. Avoid changing article outputs silently.

For the current synthetic registry, the Phase 4f evidence points first to RHS/readout regularization rather than another full calibration rerun.

## Gate

Phase 4f status: `review`.

Reason: contract quantiles remain noncrossing, but raw crossings persist after stronger VB. The next step should be targeted model-side sensitivity, not article-candidate freezing.

Recommended next action:

`run_targeted_prior_design_sensitivity_before_full_calibration`

## Next Stage

Implement a Phase 4g targeted RHS-prior/readout-design sensitivity runner over the exact Phase 4e crossing rows. The runner should preserve seeds and origin controls, expose `tau0` and `zeta2` controls, and preferably support separate anchor and adjacent-innovation shrinkage. Only after a material raw-crossing improvement should the full calibration campaign be rerun.
