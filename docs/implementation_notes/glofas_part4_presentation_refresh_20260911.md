# GloFAS Part 4 presentation refresh

## Purpose

This change revises the presentation of the frozen GloFAS Part 4 comparison.
It does not refit a model, alter a score, change the selected model, or modify
the numerical qualification of either joint fit. The objective is to compare
the completed model families on a common basis and to give the observational
and forecast paths a consistent graphical treatment.

## Frozen scientific inputs

The source score ledger is
`tables/glofas_application_part4_forecast_scores__glofas_part4_joint_al_sweep10_20260911.csv`.
Its SHA-256 is
`829d4467e4b734d4cd7a0dbab40ba72fe9b9c91c328908461f82f3093167d498`.
All displayed comparisons use the same 28 issued dates and the probability
grid `0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95`.

The main table contains the six qualified comparisons: Joint AL, Independent
AL, Independent exAL, Normal Ridge, Normal RHS/VB, and raw GloFAS. Joint exAL
is retained only in the supplement because its source fit has status
`source_fit_not_qualified`. Joint AL retains the status
`cap_stabilized_after_rhs_release`; it is not described as strictly
outer-converged.

## Statistical presentation

Mean check loss is an equal-weight average of the seven level-specific losses.
The displayed approximate CRPS, denoted by `aCRPS`, uses trapezoidal weights
over the same seven levels. Interval score and empirical coverage refer to the
central 90% interval. The Normal rows are Gaussian predictive baselines, not
quantile-likelihood fits. These distinctions are stated in the table caption
and results text because the score rankings need not coincide.

The article figure presents the selected Joint AL quantile paths. Three
supplementary figures compare the two Normal fits, the two independent
quantile fits, and the two joint quantile fits. The Joint exAL panel is marked
as an unqualified sensitivity result. The Normal comparison uses the central
90% predictive interval and the recursively simulated latent future-response
draws used by the frozen score calculation.

The common graphical encoding is:

- forest-green filled circles and a thin solid line for USGS observations
  available through the forecast origin;
- forest-green open circles and a short-dashed line for withheld USGS values
  used only for scoring;
- dark orange for retrospective GloFAS and issued ensemble members;
- a blue-to-plum ordered palette for probability levels;
- dashed quantile paths before the origin and solid paths after the origin.

## Reproduction

The tracked builder reads the two frozen runtime packages without modifying
them and writes only versioned article-safe tables, figures, aliases, and a
manifest:

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/393_build_glofas_part4_presentation_refresh.R \
  --source_runtime_root=/path/to/glofas_part4_latent_family_dec25_exactopt_r3_fivecore_20260906 \
  --continuation_runtime_root=/path/to/glofas_part4_joint_convergence_closeout_20260907
```

The generated package is verified independently with:

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/394_check_glofas_part4_presentation_refresh.R
```

The checker verifies the frozen source hash, exact displayed values, family
eligibility boundary, common horizon count, output aliases, complete output
hash manifest, and one-page vector-only figure contract. The focused test is
`application/tests/test_glofas_part4_presentation_refresh.R` and is registered
in the combined R test harness.

The independent-validation figure verifier also records hashes for
`main.tex`, `qdesn-supplement.tex`, and `overleaf/article_files.txt` as part of
its article-source closure. Those three entries in
`tables/qdesn_validation_500obs_dgp_oracle_figures_v14_manifest.txt` were
updated after this presentation change. Independent-validation numerical
inputs, tables, and figures were not regenerated or altered.

## Publication boundary

Only paths listed in `overleaf/article_files.txt` enter the article snapshot.
Runtime fits, posterior draws, caches, logs, and `local_trackers` remain outside
Git and outside Overleaf. The presentation manifest identifies the builder and
checker as reproduction code but does not authorize those scripts for the
article-only snapshot.
