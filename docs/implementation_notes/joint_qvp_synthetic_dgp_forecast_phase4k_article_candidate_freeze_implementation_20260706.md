# Joint-QVP Synthetic DGP Forecast Phase 4k Article-Candidate Freeze Implementation

Date: 2026-07-06

## Purpose

Phase 4k freezes the selected Phase 4j tau0 candidate launch arm and builds
storage-light article assets from the freeze.  It does not run new model fits.

The selected arm is:

```text
tau0_0p15_comparator
```

with selected `tau0 = 0.15`.

## Implemented Entry Points

R helpers in `application/R/joint_qvp_qdesn.R`:

- `app_joint_qvp_freeze_synthetic_dgp_phase4k_article_candidate()`
- `app_joint_qvp_build_synthetic_dgp_phase4k_article_assets()`
- `app_joint_qvp_audit_synthetic_dgp_phase4k_article_assets()`

Scripts:

- `application/scripts/91_freeze_joint_qvp_synthetic_dgp_phase4k_article_candidate.R`
- `application/scripts/92_build_joint_qvp_synthetic_dgp_phase4k_article_assets.R`
- `application/scripts/93_audit_joint_qvp_synthetic_dgp_phase4k_article_assets.R`

Focused tests:

- `application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4k_article_candidate_freeze.R`
- `application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4k_article_assets.R`

The focused tests are wired into `application/tests/run_tests.R` after the
Phase 4j launch test.

## Commands Run

Freeze:

```bash
Rscript application/scripts/91_freeze_joint_qvp_synthetic_dgp_phase4k_article_candidate.R \
  --launch-dir application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_tau0_candidate_launch_20260704 \
  --audit-dir application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_tau0_candidate_launch_20260704/phase4j_launch_audit \
  --freeze-dir application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704
```

Article assets:

```bash
Rscript application/scripts/92_build_joint_qvp_synthetic_dgp_phase4k_article_assets.R \
  --freeze-dir application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704
```

Article asset audit:

```bash
Rscript application/scripts/93_audit_joint_qvp_synthetic_dgp_phase4k_article_assets.R \
  --freeze-dir application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704
```

Focused tests:

```bash
Rscript -e 'source("application/R/00_packages.R"); app_set_repo_root("."); source(app_path("application/R/input_contract.R")); source(app_path("application/R/synthesize_quantiles.R")); source(app_path("application/R/score_forecasts.R")); source(app_path("application/R/joint_qvp_qdesn.R")); source(app_path("application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4j_tau0_candidate_launch.R"))'

Rscript -e 'source("application/R/00_packages.R"); app_set_repo_root("."); source(app_path("application/R/input_contract.R")); source(app_path("application/R/synthesize_quantiles.R")); source(app_path("application/R/score_forecasts.R")); source(app_path("application/R/joint_qvp_qdesn.R")); source(app_path("application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4k_article_candidate_freeze.R"))'

Rscript -e 'source("application/R/00_packages.R"); app_set_repo_root("."); source(app_path("application/R/input_contract.R")); source(app_path("application/R/synthesize_quantiles.R")); source(app_path("application/R/score_forecasts.R")); source(app_path("application/R/joint_qvp_qdesn.R")); source(app_path("application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4k_article_assets.R"))'
```

All focused tests passed.

## Artifact Locations

Freeze directory:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704
```

Freeze manifest:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704/artifact_manifest.csv
```

Article tables:

```text
tables/joint_qvp_synthetic_dgp_phase4k_*.tex
tables/joint_qvp_synthetic_dgp_phase4k_asset_manifest.csv
```

Article figures:

```text
figures/joint_qvp_synthetic_dgp/phase4k_*.png
```

Article asset audit:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704/phase4k_article_asset_audit
```

## Gate Outcomes

| Gate | Status | Interpretation |
|---|---:|---|
| Freeze gate | review | Freeze is ready; raw crossings remain diagnostic review evidence. |
| Contract crossings | pass | Selected-arm contract crossing pairs are zero. |
| Source manifests | pass | Launch, fixture, audit, and selected Phase 3 manifests verify. |
| Article asset hashes | pass | Generated table and figure hashes verify. |
| Large source references | pass | Referenced selected-arm Phase 3 files exist and match recorded hashes. |
| Article asset audit | review | Review is due to disclosed raw crossings, not implementation defects. |

## Generated Article Assets

Tables:

- `tables/joint_qvp_synthetic_dgp_phase4k_protocol.tex`
- `tables/joint_qvp_synthetic_dgp_phase4k_tau0_decision.tex`
- `tables/joint_qvp_synthetic_dgp_phase4k_selected_forecast_scores.tex`
- `tables/joint_qvp_synthetic_dgp_phase4k_selected_truth_by_tau.tex`
- `tables/joint_qvp_synthetic_dgp_phase4k_selected_scenario_summary.tex`
- `tables/joint_qvp_synthetic_dgp_phase4k_crossing_diagnostics.tex`
- `tables/joint_qvp_synthetic_dgp_phase4k_runtime_convergence.tex`
- `tables/joint_qvp_synthetic_dgp_phase4k_asset_manifest.csv`

Figures:

- `figures/joint_qvp_synthetic_dgp/phase4k_truth_error_by_tau.png`
- `figures/joint_qvp_synthetic_dgp/phase4k_scenario_truth_error.png`
- `figures/joint_qvp_synthetic_dgp/phase4k_raw_crossing_adjustments.png`
- `figures/joint_qvp_synthetic_dgp/phase4k_hit_coverage_by_tau.png`
- `figures/joint_qvp_synthetic_dgp/phase4k_runtime_convergence.png`

## Interpretation

The Phase 4k freeze is article-candidate ready.  The selected arm preserves
zero contract crossings and finite forecast scores.  Raw forecast crossings are
not hidden: they are summarized in the freeze and remain the reason the gate is
`review` rather than `pass`.

The freeze is storage-light.  Large selected-arm Phase 3 files are referenced by
path and SHA-256 hash in `freeze_large_file_registry.csv`; they are not copied
unless the freeze script is run with `--copy-large-forecast-files true`.

## Next Step

Use the Phase 4k table and figure assets for manuscript integration.  The
manuscript text should describe the raw/contract forecast policy explicitly:
contract quantiles are used for scoring, raw quantiles are preserved as
diagnostics, and sparse raw crossings are review evidence concentrated in
extreme-tail stress cases.
