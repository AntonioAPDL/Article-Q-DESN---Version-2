# Joint exQDESN Phase133B posterior qhat summary sensitivity

Date: 2026-07-14

## Purpose

Phase133B implements the compact posterior quantile-readout sensitivity layer recommended by the Phase133 performance-first audit. The goal is to determine whether the weak Joint exQDESN exAL-RHS article-facing performance in the high-priority scenarios is partly a posterior-summary problem rather than only a model-specification or sampler-geometry problem.

The stage compares three posterior summaries of the MCMC quantile grid:

- posterior mean qhat;
- posterior median qhat;
- posterior 10 percent trimmed-mean qhat.

This is intentionally a quantile-grid validation layer. It does not reinterpret the composite exAL working likelihood as a scalar posterior predictive density.

## Scope

Default input sources are:

- Phase133 performance-first audit:
  `application/cache/joint_qdesn_phase133_performance_first_audit_20260714`;
- Phase121 case-specific VB/VB-LD winner freeze:
  `application/cache/joint_qdesn_phase121_case_vb_winner_freeze_20260711`;
- formal long-series simulation fixtures:
  `application/cache/joint_qdesn_simulation_dgp_fixtures_20260706`.

The default scenario set is the five Phase133 high-priority scenarios:

1. `regime_shift`;
2. `nonlinear_reservoir_friendly`;
3. `normal_bridge`;
4. `student_t_location_scale`;
5. `laplace_bridge`.

The default model is `joint_exqdesn_rhs_vb`, confirmed with VB-initialized MCMC and relabeled as the corresponding MCMC validation row.

## Implementation

The new helper module is:

```text
application/R/joint_exqdesn_phase133b_qhat_sensitivity.R
```

The new runner is:

```bash
Rscript application/scripts/139_run_joint_exqdesn_phase133b_qhat_summary_sensitivity.R
```

Default output:

```text
application/cache/joint_qdesn_phase133b_qhat_summary_sensitivity_20260714
```

The runner:

- verifies source manifests;
- fits the selected VB/VB-LD specification for each scenario;
- runs short VB-initialized MCMC confirmations using the Phase121 per-case controls;
- samples a bounded, deterministic subset of retained MCMC draws for qhat summarization;
- computes mean, median, trimmed-mean, q05, and q95 qhat summaries;
- preserves raw qhat summaries;
- applies the monotone quantile-grid contract before scoring;
- writes raw crossing, contract crossing, and monotone-adjustment diagnostics;
- scores fit and forecast windows under each qhat summary method.

## Generated artifacts

The Phase133B artifact directory contains:

- `run_config.csv`;
- `source_manifest_verification.csv`;
- `posterior_qhat_draw_sampling_plan.csv`;
- raw and contract fit/forecast qhat summary tables;
- monotone-adjustment and uncertainty summaries;
- raw and contract crossing summaries;
- method-level fit/forecast truth-distance, check-loss, hit-rate, grid-CRPS, and interval summaries;
- `posterior_qhat_summary_method_metrics.csv`;
- `qhat_summary_method_recommendation.csv`;
- VB convergence, objective, MCMC draw, VB-to-MCMC distance, chain-to-pooled distance, and runtime diagnostics;
- `audit_assessment.csv`;
- `provenance.csv`;
- `README.md`;
- `artifact_manifest.csv`.

The method-specific summary tables retain `qhat_summary_method`, so posterior mean, median, and trimmed mean are never silently averaged together.

## Gates

Hard fail:

- missing or failing source hashes;
- no successful worker results;
- nonfinite forecast truth metrics;
- nonzero contract forecast crossings.

Review:

- method sensitivity does not close the Phase125 performance gap;
- a high-priority sampler-geometry case still needs paired specification and sampler work;
- raw crossings or monotone adjustments remain diagnostically large while contract crossings are zero.

Pass:

- all implementation gates pass;
- all contract crossings are zero;
- posterior-summary sensitivity produces competitive quantile-grid performance for all high-priority scenarios.

## Commands

Focused regression:

```bash
Rscript application/tests/test_joint_exqdesn_phase133b_qhat_sensitivity.R
```

Default five-scenario run:

```bash
Rscript application/scripts/139_run_joint_exqdesn_phase133b_qhat_summary_sensitivity.R \
  --output-dir application/cache/joint_qdesn_phase133b_qhat_summary_sensitivity_20260714 \
  --n-cores 5
```

Optional targeted one-scenario debugging:

```bash
Rscript application/scripts/139_run_joint_exqdesn_phase133b_qhat_summary_sensitivity.R \
  --scenario-ids nonlinear_reservoir_friendly \
  --output-dir application/cache/joint_qdesn_phase133b_qhat_summary_sensitivity_nonlinear_20260714 \
  --n-cores 1
```

## Interpretation

If median or trimmed-mean qhat materially improves forecast MAE/check loss/grid CRPS without large monotone adjustments, then the current exAL weakness is partly a posterior-summary instability problem and should be incorporated into the next confirmation packet.

If all three qhat summaries remain far behind the current winners, then the next stage should prioritize targeted exAL specification screening and sampler-geometry experiments rather than longer chains alone.

No manuscript table should be promoted from Phase133B by itself. Phase133B is a decision layer for the next calibrated MCMC confirmation campaign.
