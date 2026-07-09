# Q-DESN VB Scaled Approaches Closeout

Date: 2026-05-30

This note closes the local implementation and comparison pass for the Q-DESN
and Normal DESN scaled VB approaches. It is a repository hygiene note, not a
new modeling result.

## Scope

The pass covers the feature family implemented across the shared exdqlm package
and article documentation:

- Q-DESN AL/exAL full-data VB under ridge, RHS, and RHS_NS;
- exact chunked full-data VB;
- stochastic and hybrid AL approximations;
- hybrid exAL approximation for supported priors;
- diagonal covariance diagnostics;
- fixed and stratified subset targets;
- rolling, posterior-as-prior, online, and warm-start workflow tools;
- Normal DESN scaled ridge and Normal RHS/RHS_NS comparison support;
- unified Normal/Q-DESN source-level comparison reporting.

The pass deliberately does not close or modify the independent GloFAS memory
refinement work, the ongoing validation study results, divide-and-combine VB,
or variational coresets.

## Repository State At Closeout

Package repo:

`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`

- branch: `validation/shared-fitforecast-v2-1.0.0`
- closeout package HEAD before this article note: `d4411eb`
- package working tree: clean before and after ignored-output cleanup

Article repo:

`/data/jaguir26/local/src/Article-Q-DESN`

- branch: `application-ensemble-likelihood-redesign`
- closeout article HEAD before this note: `c1e530d`
- tracked article working tree: clean except for unrelated untracked GloFAS
  memory-refinement files that were intentionally left untouched

## Cleanup Performed

Generated package comparison outputs were reduced to one final artifact set:

`results/normal_qdesn_unified_source_median_n300_m30_tau0_0p01_20260530`

The protected validation-study result root was preserved:

`results/qdesn_mcmc_validation`

Removed package-side ignored scratch outputs:

- older Q-DESN batching comparison gates;
- older source-median and last1000 source comparison runs;
- subset/exAL diagonal covariance smoke outputs;
- simplification ladder output directories;
- first-pass Normal/Q-DESN unified comparison output superseded by the n300
  m30 tau0 0.01 comparison.

Article-side binary pilot artifacts were already removed from exact-chunked
pilot/smoke log and cache locations. The GloFAS application cache/run objects
and the unrelated memory-refinement files were not touched.

## Final Comparison Artifact

Final source-level comparison:

`results/normal_qdesn_unified_source_median_n300_m30_tau0_0p01_20260530`

Tracked article report:

`docs/implementation_notes/normal_qdesn_authoritative_approach_comparison_n300_m30_tau0_0p01_20260530.md`

Key manuscript-ready generated files retained in the package result root:

- `manuscript_ready/normal_qdesn_manuscript_ready_summary.md`
- `manuscript_ready/manuscript_method_table.csv`
- `manuscript_ready/manuscript_compact_methods.csv`
- `manuscript_ready/manuscript_exact_gate_summary.csv`
- `manuscript_ready/manuscript_approximate_summary.csv`
- `manuscript_ready/figures/figure_predictive_metrics.png`
- `manuscript_ready/figures/figure_runtime_vs_loss.png`
- `manuscript_ready/figures/figure_prediction_overlay.png`
- `manuscript_ready/figures/figure_exact_gates.png`

These generated outputs remain ignored by git and reproducible from the command
recorded in the tracked report.

## Supported Method Labels

Use these labels consistently in downstream reports:

- `full_data_exact`: ordinary full-data VB/CAVI/LDVB reference.
- `full_data_exact_chunked`: exact chunked implementation of the same target.
- `full_data_approx_stochastic`: stochastic AL approximation.
- `full_data_approx_hybrid`: hybrid approximation with periodic full refresh.
- `covariance_approximation`: same row-data target with approximate beta
  covariance.
- `subset_target`: target-changing subset-data fit.
- `posterior_as_prior_target`: target-changing sequential posterior handoff.
- `online_state_handoff`: ordered-batch workflow built on posterior-as-prior.
- `normal_closed_form`: Normal DESN scaled ridge closed-form reference.
- `normal_rhs_vb_approx`: Normal DESN RHS/RHS_NS approximate global VB readout.

Exact chunking is the only scaled implementation mode here that preserves the
same full-data VB target exactly. Stochastic, hybrid, diagonal covariance,
subset, rolling, posterior-as-prior, and online rows must remain explicitly
labeled as approximate, target-changing, or workflow rows as appropriate.

## Remaining Gated Work

The following remain intentionally out of scope:

- pure stochastic exAL;
- exAL RHS/RHS_NS diagonal covariance;
- RHS/RHS_NS posterior-as-prior and online handoff;
- low-rank covariance;
- article-side stochastic, hybrid, rolling, and online adapters;
- divide-and-combine VB;
- variational coresets.

None of these should be presented as implemented in article reports.

## Reproduction Commands

Final comparison rerun:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0

/usr/bin/time -v \
  -o results/normal_qdesn_unified_source_median_n300_m30_tau0_0p01_20260530/time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_normal_qdesn_unified_source_median_20260529.R \
  --output-dir results/normal_qdesn_unified_source_median_n300_m30_tau0_0p01_20260530 \
  --source-dir /data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500 \
  --seed 20260530 \
  --D 1 \
  --n 300 \
  --m 30 \
  --washout 50 \
  --chunk-size 128 \
  --subset-size 180 \
  --max-iter 25 \
  --stochastic-max-iter 60 \
  --hybrid-max-iter 60 \
  --hybrid-full-every 15 \
  --rhs-tau0 0.01 \
  --ridge-tau2 50 \
  --exact-tolerance 1e-6 \
  --exact-relative-tolerance 1e-7 \
  --cores 1
```

Focused package regression commands:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-normal-comparison-script.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-normal-qdesn-unified-summarizer.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-normal-qdesn-unified-comparison.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-normal-qdesn-manuscript-plots.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-batching-modes.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-exact-chunking-stats.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-beta-covariance-approx.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-subset-fit.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-static-beta-prior-rhs.R")'
```

## Closeout Criteria

This project slice is ready to close when:

- package focused regressions pass;
- article and package `git diff --check` pass;
- package generated results are limited to the final comparison root and the
  protected validation-study root;
- article has no tracked dirty files;
- remaining untracked article files are only the unrelated GloFAS
  memory-refinement files;
- no generated binary comparison outputs are committed;
- all exact, approximate, target-changing, workflow, and gated labels remain
  explicit in tracked documentation.

