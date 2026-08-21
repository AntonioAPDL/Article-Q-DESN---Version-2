#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_exqdesn_exact_structured_inference.R"))

assert_contains <- function(path, pattern, fixed = TRUE) {
  txt <- paste(readLines(app_path(path), warn = FALSE), collapse = "\n")
  stopifnot(grepl(pattern, txt, fixed = fixed))
}

assert_not_contains <- function(path, pattern, fixed = TRUE) {
  txt <- paste(readLines(app_path(path), warn = FALSE), collapse = "\n")
  stopifnot(!grepl(pattern, txt, fixed = fixed))
}

# aCRPS is the finite-grid trapezoidal integrated pinball score, with legacy
# CRPS column names retained only as compatibility aliases.
block <- data.frame(
  model_id = "toy",
  origin_date = as.Date("2026-01-01"),
  target_date = as.Date("2026-01-02"),
  horizon = 1L,
  quantile_level = c(0.1, 0.5, 0.9),
  qhat_monotone = c(0, 1, 2),
  y_reference = 1.5
)
loss <- app_check_loss(block$y_reference, block$qhat_monotone, block$quantile_level)
expected_acrps <- 2 * sum(diff(block$quantile_level) * (head(loss, -1L) + tail(loss, -1L)) / 2)
stopifnot(abs(app_acrps_quantile_grid(block) - expected_acrps) < 1.0e-12)
stopifnot(abs(app_crps_quantile_grid(block) - expected_acrps) < 1.0e-12)
acrps_scores <- app_score_acrps_grid(block)
legacy_scores <- app_score_crps_grid(block)
stopifnot(all(c("acrps_quantile_grid", "crps_quantile_grid") %in% names(acrps_scores)))
stopifnot(abs(acrps_scores$acrps_quantile_grid[[1L]] - acrps_scores$crps_quantile_grid[[1L]]) < 1.0e-12)
stopifnot(identical(names(acrps_scores), names(legacy_scores)))

# Independent quantile synthesis operates on point summaries and does not imply
# a joint posterior over level-indexed readouts.
crossing <- data.frame(
  model_id = "toy",
  origin_date = as.Date("2026-01-01"),
  target_date = as.Date("2026-01-02"),
  horizon = 1L,
  quantile_level = c(0.1, 0.5, 0.9),
  qhat = c(3, 2, 4)
)
synthesized <- app_synthesize_quantile_grid(crossing)
stopifnot(all(diff(synthesized$qhat_monotone) >= -1.0e-12))
stopifnot(identical(crossing$qhat, crossing$qhat))
assert_contains("application/R/fit_qdesn_discrepancy.R", 'out$qhat_summary <- "posterior_draw_mean"')

# qf-GAL/exAL nests AL at gamma=0 but is only branchwise smooth there for
# nonmedian quantiles.
eps <- 1.0e-7
for (tau in c(0.05, 0.25, 0.5, 0.75, 0.95)) {
  p0 <- app_joint_exqdesn_gamma_to_p(tau, 0)
  left <- (p0 - app_joint_exqdesn_gamma_to_p(tau, -eps)) / eps
  right <- (app_joint_exqdesn_gamma_to_p(tau, eps) - p0) / eps
  stopifnot(abs(left - sqrt(2 / pi) * (1 - tau)) < 1.0e-5)
  stopifnot(abs(right - sqrt(2 / pi) * tau) < 1.0e-5)
  if (abs(tau - 0.5) > 1.0e-12) stopifnot(abs(left - right) > 1.0e-2)
}
assert_contains("qdesn-supplement.tex", "branchwise smooth for")
assert_contains("qdesn-supplement.tex", "the AL special case")

# The selected GloFAS authority is FR09 persistence-anchored innovation with a
# retrospective blended future-covariate policy and disabled response-level
# posterior-predictive sampling.
cfg <- yaml::read_yaml(app_path("tables/glofas_application_run_config__glofas_fr09_authoritative_full7_20260811.yaml"))
stopifnot(identical(cfg$prediction$discrepancy_transition_strategy, "persistence_anchored_innovation"))
stopifnot(identical(cfg$covariates$source_policy, "realized_history_and_blended_gefs_forecast"))
stopifnot(isTRUE(cfg$covariates$allow_realized_future_blend))
stopifnot(identical(cfg$prediction$posterior_predictive_sampling, "disabled"))
assert_contains("application/R/fit_qdesn_latent_path.R", "d_feature_future <- discrepancy_baseline_future")
assert_contains("main.tex", "\\GlofasApplicationCurrentDiscrepancyTransitionStrategy{} rule")
assert_contains("main.tex", "realized-history and blended Global Ensemble Forecast System")
assert_not_contains("main.tex", "forecast-window discrepancy reservoir is driven by the horizon-keyed contrast")

# PriceFM is a retrospective comparison with retrospectively observed target leads in every
# selected row and additional neighbor leads for graph-derived rows.
assert_contains("main.tex", "Both input policies use retrospectively")
assert_contains("main.tex", "target-region load, solar, and wind lead covariates")
assert_contains("main.tex", "add retrospectively observed neighboring-region lead")
manifest <- jsonlite::fromJSON(app_path("tables/pricefm_paper_aligned_main_comparison_manifest.json"))
stopifnot(identical(manifest$applicability$cross_panel_comparison, "context_only_not_head_to_head"))

# The article-facing score label is aCRPS; legacy variable names may remain in
# source artifacts for compatibility, but visible current-output labels should
# not assert full CRPS for the finite grid.
assert_contains("main.tex", "\\(\\aCRPS\\)")
assert_contains("tables/glofas_application_current_score_summary.tex", "aCRPS")
assert_not_contains("tables/glofas_application_current_score_summary.tex", " & CRPS & ")
assert_contains("tables/glofas_application_current_outputs.tex", "GlofasApplicationCurrentQdesnAcrps")
assert_contains("scripts/build_arxiv_source_bundle.sh", "overleaf/article_files.txt")
assert_not_contains("scripts/build_arxiv_source_bundle.sh", "glofas_stage_n_winner")

cat("Corrected PRO re-audit contract tests passed.\n")
