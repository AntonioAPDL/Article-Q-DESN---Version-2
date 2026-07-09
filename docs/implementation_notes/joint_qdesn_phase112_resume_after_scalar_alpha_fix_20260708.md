# Joint QDESN Phase 112 Resume After Scalar-Alpha Fix

This note records the July 8, 2026 diagnosis and resume plan for the joint QDESN VB calibration screen.

## Diagnosis

The first Phase 112 launch stopped after two new candidates because the generated registry included vector-valued `alpha_prior_sd` rows:

- `alpha_tailwide_tau0_0p5`
- `alpha_tailtight_tau0_0p5`

The mixed Phase 112 screen evaluates both joint multi-quantile models and independent single-quantile comparators. To keep that comparison contract reproducible across all launch surfaces, Phase 112 now requires scalar `alpha_prior_sd` values. Tail-specific vector priors are deferred until they are wired and tested as a separate model-contract change.

## Code Fix

The screening registry validator now accepts an explicit `allow_alpha_prior_vectors` flag. The Phase 112 runner and Phase 111 registry generator call it with `FALSE`, so unsupported vector rows fail before any worker launch.

The former vector candidates were replaced with scalar width probes:

- `alpha_sd_1p25_tau0_0p5`
- `alpha_sd_0p35_tau0_0p5`

## Completed Partial Evidence

Before the fix, the Phase 112 cache completed:

- `current_selected_reference`
- `alpha_sd_0p75_tau0_0p5`
- `alpha_sd_1p0_tau0_0p5`

The audit-only summary selected `alpha_sd_0p75_tau0_0p5` as the best completed candidate, but with `gate_status = review`; it is promising but not frozen.

## Resume Contract

The regenerated registry is:

```text
application/cache/joint_qdesn_calibration_screening_readiness_phase111_20260707/recommended_screening_registry.csv
```

Contract checks:

- 11 declared rows.
- 0 comma-valued `alpha_prior_sd` rows.
- 3 candidates already complete and reused.
- 8 candidates remaining.

Resume command:

```bash
Rscript application/scripts/106_run_joint_qdesn_vb_spec_screening.R \
  --registry /data/jaguir26/local/src/Article-Q-DESN__wt__main_validation_tables/application/cache/joint_qdesn_calibration_screening_readiness_phase111_20260707/recommended_screening_registry.csv \
  --output-dir /data/jaguir26/local/src/Article-Q-DESN__wt__main_validation_tables/application/cache/joint_qdesn_vb_spec_screening_phase112_20260707 \
  --n-cores 9 \
  --reuse-completed true \
  --audit-only false
```

## Selection Gate

Do not promote a VB specification from Phase 112 until the resumed run writes a complete top-level artifact manifest and `selected_spec_recommendation.csv`. A candidate with `gate_status = review` can be used as a diagnostic or confirmation target, but it should not be treated as frozen article evidence without reviewing raw crossings, max-iteration behavior, and exQDESN forecast calibration.
