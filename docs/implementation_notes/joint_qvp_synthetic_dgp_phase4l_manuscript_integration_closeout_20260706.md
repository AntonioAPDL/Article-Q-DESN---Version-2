# Joint-QVP Synthetic DGP Phase 4l Manuscript Integration Closeout

Date: 2026-07-06

## Purpose

Phase 4l integrates the frozen Phase 4k joint-QVP synthetic DGP
article-candidate evidence into the manuscript.  It does not rerun validation
fits or forecasts.

## Files Changed

Manuscript:

- `main.tex`

Manuscript table wrapper:

- `tables/joint_qvp_synthetic_dgp_phase4k_tables.tex`

Planning and closeout notes:

- `docs/implementation_notes/joint_qvp_synthetic_dgp_phase4l_manuscript_integration_audit_plan_20260706.md`
- `docs/implementation_notes/joint_qvp_synthetic_dgp_phase4l_manuscript_integration_closeout_20260706.md`

The generated Phase 4k article assets remain available under:

- `tables/joint_qvp_synthetic_dgp_phase4k_*.tex`
- `tables/joint_qvp_synthetic_dgp_phase4k_asset_manifest.csv`
- `figures/joint_qvp_synthetic_dgp/phase4k_*.png`

## Manuscript Integration

The simulation section now distinguishes two validation layers:

1. the finalized single-quantile TT500 benchmark;
2. the Phase 4k joint multi-quantile synthetic DGP forecast validation.

The Phase 4k subsection states:

- selected arm: `tau0_0p15_comparator`;
- selected `tau0`: 0.15;
- registry scale: 9 base scenarios, 10 replicates, 90 replicated rows;
- forecast scale: 9000 held-out forecast origins;
- tau grid: 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95;
- contract forecast crossings: 0;
- raw forecast crossings: 27, retained as review diagnostics;
- scored forecasts use monotone contract quantiles;
- raw model quantiles are preserved for audit and are not claimed to be
  intrinsically noncrossing.

The new manuscript wrapper
`tables/joint_qvp_synthetic_dgp_phase4k_tables.tex` provides compact
article-facing tables with stable labels:

- `tab:joint-qvp-phase4k-protocol`
- `tab:joint-qvp-phase4k-tau0-decision`
- `tab:joint-qvp-phase4k-selected-scores`
- `tab:joint-qvp-phase4k-truth-by-tau`
- `tab:joint-qvp-phase4k-crossing-diagnostics`
- `tab:joint-qvp-phase4k-scenario-summary`
- `tab:joint-qvp-phase4k-runtime-convergence`

The compact wrapper avoids the wide-column overflow produced by directly
including the generated audit tables.  The original generated table assets are
unchanged and remain hash-audited in the Phase 4k asset manifest.

Figures integrated in `main.tex`:

- `figures/joint_qvp_synthetic_dgp/phase4k_truth_error_by_tau.png`
- `figures/joint_qvp_synthetic_dgp/phase4k_scenario_truth_error.png`
- `figures/joint_qvp_synthetic_dgp/phase4k_raw_crossing_adjustments.png`
- `figures/joint_qvp_synthetic_dgp/phase4k_hit_coverage_by_tau.png`
- `figures/joint_qvp_synthetic_dgp/phase4k_runtime_convergence.png`

## Commands Run

Full manuscript build:

```bash
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

Final PDF:

```text
main.pdf
```

The final build produced a 44-page PDF.  A final log scan found no undefined
references, no label-rerun warnings, and no overfull-box warnings.

Log scan command:

```bash
rg -n "Warning:|undefined references|Label\\(s\\) may have changed|Overfull|Underfull|Rerun" main.log
```

## Reproducibility Checks

Manifest verification:

```bash
Rscript -e 'source("application/R/00_packages.R"); app_set_repo_root("."); dirs <- c("application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704", "application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704/phase4k_article_asset_audit"); for (d in dirs) { mf <- read.csv(file.path(d,"artifact_manifest.csv"), check.names=FALSE); ok <- logical(nrow(mf)); for (i in seq_len(nrow(mf))) { p <- file.path(d, mf$relative_path[[i]]); ok[[i]] <- file.exists(p) && identical(app_sha256_file(p), mf$sha256[[i]]) }; cat(d, "rows=", nrow(mf), "all_hashes=", all(ok), "\n") }; am <- read.csv("tables/joint_qvp_synthetic_dgp_phase4k_asset_manifest.csv", check.names=FALSE); ok <- logical(nrow(am)); for (i in seq_len(nrow(am))) { p <- if (grepl("^/", am$path[[i]])) am$path[[i]] else file.path(getwd(), am$path[[i]]); ok[[i]] <- file.exists(p) && identical(app_sha256_file(p), am$sha256[[i]]) }; cat("asset_manifest rows=", nrow(am), " tables=", sum(am$artifact_type=="table"), " figures=", sum(am$artifact_type=="figure"), " all_hashes=", all(ok), "\n", sep="")'
```

Result:

```text
freeze manifest rows = 17, all hashes TRUE
asset-audit manifest rows = 6, all hashes TRUE
asset manifest rows = 12, tables = 7, figures = 5, all hashes TRUE
```

Focused tests:

```bash
Rscript -e 'source("application/R/00_packages.R"); app_set_repo_root("."); source(app_path("application/R/input_contract.R")); source(app_path("application/R/synthesize_quantiles.R")); source(app_path("application/R/score_forecasts.R")); source(app_path("application/R/joint_qvp_qdesn.R")); source(app_path("application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4j_tau0_candidate_launch.R")); cat("phase4j test passed\n")'

Rscript -e 'source("application/R/00_packages.R"); app_set_repo_root("."); source(app_path("application/R/input_contract.R")); source(app_path("application/R/synthesize_quantiles.R")); source(app_path("application/R/score_forecasts.R")); source(app_path("application/R/joint_qvp_qdesn.R")); source(app_path("application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4k_article_candidate_freeze.R")); cat("phase4k freeze test passed\n")'

Rscript -e 'source("application/R/00_packages.R"); app_set_repo_root("."); source(app_path("application/R/input_contract.R")); source(app_path("application/R/synthesize_quantiles.R")); source(app_path("application/R/score_forecasts.R")); source(app_path("application/R/joint_qvp_qdesn.R")); source(app_path("application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4k_article_assets.R")); cat("phase4k assets test passed\n")'
```

Result:

```text
phase4j test passed
phase4k freeze test passed
phase4k assets test passed
```

## Gate Outcome

| Gate | Status | Interpretation |
|---|---:|---|
| Manuscript build | pass | `main.pdf` built successfully. |
| Cross references | pass | Final log scan found no unresolved references. |
| Table layout | pass | Compact wrapper removed wide-table overflow. |
| Freeze manifest | pass | Freeze artifacts hash-verified. |
| Article asset manifest | pass | 7 generated tables and 5 generated figures hash-verified. |
| Focused tests | pass | Phase 4j and Phase 4k focused tests passed. |
| Contract crossings | pass | Selected-arm contract crossing pairs remain zero. |
| Raw crossings | review | 27 raw crossings remain disclosed diagnostic evidence. |

## Remaining Caveat

The article now correctly distinguishes raw model quantiles from the monotone
forecast-output contract.  The remaining `review` status is intentional and
scientific: raw adjacent-tail crossings remain in sparse stress-case origins
and are disclosed rather than hidden.

## Recommended Next Step

Perform a human PDF read-through of the simulation section, then commit the
Phase 4k/Phase 4l joint-QVP files only.  Do not include unrelated GloFAS,
PriceFM, or derivation-note changes in the same commit.
