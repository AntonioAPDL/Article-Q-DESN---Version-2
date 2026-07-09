# Joint QDESN Phase 113 Cache Cleanup and Next Plan

Date: 2026-07-08

## Status Before Cleanup

The repository was clean on `main` and synchronized with `origin/main` after committing the Phase 113 readiness layer. The active validation job was the Phase 113 top-candidate verification run:

```text
tmux session: joint_qdesn_phase113_20260708
log: application/cache/joint_qdesn_vb_spec_screening_phase113_20260708_tmux.log
output: application/cache/joint_qdesn_vb_spec_screening_phase113_20260708
```

The run had started the first new hybrid candidate:

```text
zeta2_16_inner10_iter1440_alpha0p5_tau0_0p5
```

The disk was under pressure:

```text
/data before cleanup: 916G total, 836G used, 34G available, 97% used
```

## Cleanup Rule

The cleanup was intentionally conservative. It preserved every artifact required by the active Phase 113 run and by near-term reproducibility:

- the synthetic simulation fixtures;
- the Phase 113 readiness audit;
- the live Phase 113 output directory;
- the two Phase 112 reference candidates reused by the Phase 113 registry:
  - `inner10_iter1440_alpha0p5_tau0_0p5`;
  - `zeta2_16_alpha0p5_tau0_0p5`;
- top-level Phase 112 summaries, scorecards, registries, and manifests;
- small manuscript/article asset and audit directories.

The cleanup removed old or superseded cache bodies that are reproducible from committed scripts and registries, or no longer needed for the active Phase 113 run.

## Removed Cache Bodies

Large legacy directories removed:

- `application/cache/joint_qdesn_vb_spec_screening_phase106_20260706`
- `application/cache/joint_qdesn_selected_vb_freeze_phase107_20260707`
- `application/cache/joint_qdesn_simulation_vb_forecast_validation_article_20260706`
- `application/cache/joint_qdesn_simulation_vb_fit_validation_article_20260706`
- `application/cache/joint_qdesn_mcmc_readiness_phase108_20260707`
- `application/cache/joint_qdesn_mcmc_article_phase109_20260707`

Non-reference Phase 112 candidate bodies removed:

- `alpha_sd_0p35_tau0_0p5`
- `alpha_sd_0p75_tau0_0p5`
- `alpha_sd_1p0_tau0_0p5`
- `alpha_sd_1p25_tau0_0p5`
- `gamma_zero_alpha0p5_tau0_0p5`
- `gamma_halfdefault_alpha0p5_tau0_0p5`
- `tau0_0p75_alpha0p5`
- `tau0_1p0_alpha0p5`
- `alpha_tailwide_tau0_0p5`

The generated cleanup audit is stored in the ignored cache directory:

```text
application/cache/joint_qdesn_cache_cleanup_phase113_20260708
```

## Status After Cleanup

The cleanup preserved the active run inputs and freed roughly 6 GB:

```text
/data after cleanup: 916G total, 830G used, 40G available, 96% used
```

The remaining large joint-QDESN cache bodies are:

- `application/cache/joint_qdesn_vb_spec_screening_phase112_20260707`: about 968 MB, preserving top-level summaries and the two Phase 112 reference candidates;
- `application/cache/joint_qdesn_simulation_dgp_fixtures_20260706`: about 122 MB, required by active and future validation runs.

## Current Scientific Diagnosis

Phase 112 established a clear accuracy-stability tradeoff:

- `inner10_iter1440_alpha0p5_tau0_0p5` is the stability reference, with the lowest aggregate screening score, fewer raw crossings, and less VB max-iteration pressure.
- `zeta2_16_alpha0p5_tau0_0p5` is the accuracy reference, with stronger mean forecast truth distance and max-scenario behavior.
- Joint QDESN under AL remains the strongest anchor in the current evidence.
- exQDESN remains important for the article, but its fan geometry is still too compressed in several tail cases. It has good noncrossing behavior but worse truth-distance and coverage behavior than expected.
- MCMC should remain deferred until one VB specification is stable enough to serve as the initialization and article-candidate target.

Phase 113 is therefore the right next stage. It tests whether finite `zeta2 = 16` accuracy can be combined with the stronger `rhs_vb_inner = 10` and larger VB iteration budget from the stability candidate. A second hybrid tests whether zero gamma initialization improves exQDESN behavior without changing the model contract.

## Next Audit After Phase 113 Completes

When the tmux job finishes, audit these files first:

- `application/cache/joint_qdesn_vb_spec_screening_phase113_20260708/candidate_scorecard.csv`
- `application/cache/joint_qdesn_vb_spec_screening_phase113_20260708/screening_health_summary.csv`
- `application/cache/joint_qdesn_vb_spec_screening_phase113_20260708/fit_model_metric_summary.csv`
- `application/cache/joint_qdesn_vb_spec_screening_phase113_20260708/forecast_model_metric_summary.csv`
- `application/cache/joint_qdesn_vb_spec_screening_phase113_20260708/forecast_scenario_metric_summary.csv`
- `application/cache/joint_qdesn_vb_spec_screening_phase113_20260708/forecast_tau_metric_summary.csv`
- `application/cache/joint_qdesn_vb_spec_screening_phase113_20260708/artifact_manifest.csv`

Decision criteria:

1. Hard implementation gate: manifests pass, no worker failures, finite scores, and zero contract crossings.
2. Stability gate: raw crossings and monotone adjustments are no worse than Phase 112 references, preferably improved.
3. VB gate: max-iteration counts are reduced or bounded relative to Phase 112.
4. Accuracy gate: fit and forecast truth distances match or improve the Phase 112 accuracy reference.
5. exQDESN gate: exQDESN tail gaps shrink without harming the AL QDESN anchor.

## Recommended Path

If the primary hybrid wins:

1. Freeze it as the VB article-candidate specification.
2. Rebuild article validation tables and figures from the frozen VB candidate.
3. Launch VB-initialized MCMC references only for the frozen specification.
4. Update the manuscript simulation section with the final compact tables and coherent notation.

If the zero-gamma hybrid wins only for exQDESN:

1. Treat gamma initialization as a reviewed exAL-specific computational control.
2. Confirm the AL QDESN anchor is not degraded.
3. Decide whether a common-control table or model-specific exQDESN control is more defensible for the article.

If neither hybrid improves the Phase 112 references:

1. Keep `inner10_iter1440_alpha0p5_tau0_0p5` as the conservative VB candidate for AL QDESN.
2. Open a narrower exQDESN-only investigation focused on fan-width calibration rather than broader DESN screening.
3. Do not launch MCMC until the exQDESN role in the main article table is settled.

Do not delete the remaining Phase 112 reference candidate directories until the Phase 113 audit has completed and the winning VB candidate has been frozen.
