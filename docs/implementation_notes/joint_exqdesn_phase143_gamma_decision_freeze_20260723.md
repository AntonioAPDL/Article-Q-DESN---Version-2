# Joint exQDESN Phase143 Gamma Decision Freeze

Phase143 is the decision/freeze layer after the Phase140--Phase142 sampled-gamma
experiments for the joint exQDESN validation study.

## Purpose

Phase140 showed that fixing the exAL gamma parameter at the AL-like zero value
recovered strong fit and forecast performance. Phase141 then tested sampled
gamma slice geometry and width changes. Phase142B tested explicit logit-normal
gamma shrinkage around the AL-like reference.

The Phase142B result is implementation-clean enough to make a decision:

- raw crossings are zero;
- contract crossings are zero;
- tight gamma shrinkage improves Rhat and rough ESS;
- looser shrinkage improves scores within Phase142B;
- no sampled-gamma Phase142B variant beats Phase140 fixed-gamma-zero on forecast
  MAE in the common high-priority cases.

Therefore Phase143 does not launch another MCMC screen. It freezes the evidence
and prepares a conservative article recommendation.

## Implemented Files

Phase143 adds:

- `application/R/joint_exqdesn_phase143_gamma_decision.R`;
- `application/scripts/152_freeze_joint_exqdesn_phase143_gamma_decision.R`;
- `application/tests/test_joint_exqdesn_phase143_gamma_decision.R`;
- this implementation note.

The implementation follows the existing Phase136/142 artifact style:

- source artifacts are manifest-verified;
- output tables are CSV-based;
- an output SHA-256 `artifact_manifest.csv` is written;
- article files are not modified.

## Inputs

Default source artifacts:

- Phase140 fixed-gamma-zero recovery:
  `application/cache/joint_qdesn_phase140_exal_fixed_gamma_zero_sensitivity_recovery_20260718`
- Phase141 focus width-sensitivity screen:
  `application/cache/joint_qdesn_phase141_focus_width_sensitivity_screen_20260719`
- Phase142B regularized gamma screen:
  `application/cache/joint_qdesn_phase142_regularized_gamma_screen_20260722`

Each source packet must contain:

- `artifact_manifest.csv`;
- `run_config.csv`;
- `phase136_case_assessment.csv`;
- `phase136_best_variant_by_case.csv`;
- `phase136_chain_jobs.csv`;
- `phase136_chain_worker_failures.csv`;
- `phase136_case_variant_prep_failures.csv`;
- `runtime_summary.csv`.

## Outputs

Default output:

`application/cache/joint_qdesn_phase143_gamma_decision_freeze_20260723`

The freeze writes:

- `run_config.csv`;
- `source_manifest_verification.csv`;
- `gamma_packet_health_summary.csv`;
- `gamma_packet_comparison_by_case.csv`;
- `gamma_variant_metric_first_winners.csv`;
- `gamma_variant_gate_first_winners.csv`;
- `gamma_diagnostic_tradeoff_summary.csv`;
- `gamma_decision_summary.csv`;
- `article_integration_recommendation.csv`;
- `next_experiment_recommendation.csv`;
- `provenance.csv`;
- `README.md`;
- `artifact_manifest.csv`.

## Decision Logic

Phase143 keeps two winner notions separate:

- **metric-first winner**: lowest forecast MAE within the Phase142B regularized
  sampled-gamma packet;
- **gate-first winner**: pass/review/fail gate first, then lowest forecast MAE.

This distinction matters because tight gamma shrinkage can pass diagnostics while
losing more forecast accuracy, whereas looser gamma shrinkage can improve scores
while remaining review-level for gamma autocorrelation.

The final decision is conservative:

- promote neither sampled-gamma geometry nor sampled-gamma shrinkage as the
  article-primary exAL result;
- keep `Joint QDESN RHS` under AL as the main article validation anchor;
- treat fixed-gamma-zero exAL as an AL-like sensitivity/reference, not as a full
  sampled-gamma exAL posterior analysis;
- do not launch another broad gamma MCMC screen without a model redesign.

## Gates

Hard fail:

- missing required source artifacts;
- source manifest hash failures;
- nonfinite selected metrics;
- nonzero contract crossings in promoted fixed-gamma reference rows.

Review:

- raw crossings in fixed-gamma reference rows;
- non-promoted sampled-gamma worker failures;
- high gamma autocorrelation;
- fixed-gamma-zero is not a full sampled-gamma exAL model.

The expected Phase143 status for the current artifacts is `review`, not `fail`.
That is intentional: the workflow is reproducible and the decision is clear, but
the article claim must remain carefully scoped.

## Reproduction Command

```bash
Rscript application/scripts/152_freeze_joint_exqdesn_phase143_gamma_decision.R \
  --phase140-dir application/cache/joint_qdesn_phase140_exal_fixed_gamma_zero_sensitivity_recovery_20260718 \
  --phase141-focus-dir application/cache/joint_qdesn_phase141_focus_width_sensitivity_screen_20260719 \
  --phase142-dir application/cache/joint_qdesn_phase142_regularized_gamma_screen_20260722 \
  --output-dir application/cache/joint_qdesn_phase143_gamma_decision_freeze_20260723
```

Focused test:

```bash
Rscript application/tests/test_joint_exqdesn_phase143_gamma_decision.R
```

## Next Step

After reviewing the Phase143 freeze artifact, the next useful step is a separate
article-safe manuscript/table/caption pass. That pass should make clear that the
main validation evidence is quantile-grid evidence, that AL is the primary model
anchor, and that sampled-gamma exAL did not improve the validation metrics under
the current implementation.
