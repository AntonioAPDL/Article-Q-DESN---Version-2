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

# aCRPS is the trapezoidal finite-grid approximation to integrated check loss;
# legacy CRPS column names remain as compatibility aliases.
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
stopifnot(abs(app_acrps_quantile_grid(block[c(3L, 1L, 2L), ]) - expected_acrps) < 1.0e-12)

trapezoidal_weights <- function(p) {
  stopifnot(length(p) >= 2L, all(diff(p) > 0), all(p > 0), all(p < 1))
  c(
    (p[[2L]] - p[[1L]]) / 2,
    if (length(p) > 2L) (p[3:length(p)] - p[1:(length(p) - 2L)]) / 2 else numeric(),
    (p[[length(p)]] - p[[length(p) - 1L]]) / 2
  )
}
score_grids <- list(
  joint = list(
    p = c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95),
    w = c(0.025, 0.100, 0.200, 0.250, 0.200, 0.100, 0.025)
  ),
  glofas = list(
    p = c(0.05, 0.15, 0.35, 0.50, 0.65, 0.80, 0.95),
    w = c(0.050, 0.150, 0.175, 0.150, 0.150, 0.150, 0.075)
  )
)
for (grid in score_grids) {
  weights <- trapezoidal_weights(grid$p)
  stopifnot(all(weights > 0))
  stopifnot(max(abs(weights - grid$w)) < 1.0e-12)
  stopifnot(abs(sum(weights) - (max(grid$p) - min(grid$p))) < 1.0e-12)
  stopifnot(abs(sum(weights) - 0.90) < 1.0e-12)
}

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
assert_contains("qdesn-supplement.tex", "The AL special case")

# The selected GloFAS authority is FR09 persistence-anchored innovation with a
# retrospective blended future-covariate policy and disabled response-level
# posterior-predictive sampling.
cfg <- yaml::read_yaml(app_path("tables/glofas_application_run_config__glofas_fr09_authoritative_full7_20260811.yaml"))
stopifnot(identical(cfg$prediction$discrepancy_transition_strategy, "persistence_anchored_innovation"))
stopifnot(identical(cfg$covariates$source_policy, "realized_history_and_blended_gefs_forecast"))
stopifnot(isTRUE(cfg$covariates$allow_realized_future_blend))
stopifnot(identical(cfg$prediction$posterior_predictive_sampling, "disabled"))
assert_contains("application/R/fit_qdesn_latent_path.R", "d_feature_future <- discrepancy_baseline_future")
assert_contains("main.tex", "persistence-plus-adjustment specification anchors")
assert_contains("main.tex", "persistence-anchored discrepancy")
assert_contains("main.tex", "observed history and Global Ensemble Forecast System (GEFS) forecasts")
assert_not_contains("main.tex", "forecast-window discrepancy reservoir is driven by the horizon-keyed contrast")

# PriceFM is a retrospective comparison with retrospectively observed own-region
# leads in every selected row and additional neighbor leads when neighborhood
# summaries are included.
assert_contains("main.tex", "Both predictor sets use retrospectively")
assert_contains("main.tex", "own-region load, solar, and wind lead covariates")
assert_contains("main.tex", "evaluations with neighborhood summaries add retrospectively observed neighboring-region lead")
manifest <- jsonlite::fromJSON(app_path("tables/pricefm_paper_aligned_main_comparison_manifest.json"))
stopifnot(identical(manifest$applicability$cross_panel_comparison, "context_only_not_head_to_head"))

# The visible score label is aCRPS. Legacy variable names remain as
# compatibility aliases, while current-output labels identify the finite-grid
# score precisely.
assert_contains("main.tex", "\\(\\aCRPS\\)")
assert_contains("main.tex", "\\mathcal P_K=\\{p_1,\\ldots,p_K\\}")
assert_contains("main.tex", "K\\geq2")
assert_contains("main.tex", "q_{T,h,k}^*")
assert_contains("main.tex", "\\sum_{k=1}^K\\omega_k=p_K-p_1")
assert_contains("main.tex", "integrated check-loss")
assert_contains("main.tex", "with finite first moment")
assert_contains("main.tex", "pooled posterior means of the MCMC coefficient draws")
assert_contains("main.tex", "variational posterior-mean quantile estimates")
assert_contains("qdesn-supplement.tex", "Response-level posterior predictive")
assert_contains("qdesn-supplement.tex", "fitted \\(p\\)-level quantile")
assert_contains("main.tex", "fixed forecast-design rows derived from the")
assert_contains("qdesn-supplement.tex", "fixed forecast-design rows derived from the")
assert_not_contains("main.tex", "stated interpolation and tail specification")
assert_not_contains("qdesn-supplement.tex", "stated interpolation and tail specification")
assert_not_contains("main.tex", "pinball loss")
assert_not_contains("qdesn-supplement.tex", "pinball loss")
assert_not_contains("main.tex", "Grid CRPS")
assert_not_contains("qdesn-supplement.tex", "Grid CRPS")
assert_not_contains("main.tex", "CRPS-grid")
assert_not_contains("qdesn-supplement.tex", "CRPS-grid")
assert_not_contains("application/R/joint_qdesn_phase123_mcmc_article_freeze.R", "Grid CRPS")
assert_not_contains("application/R/joint_qdesn_phase125_balanced_mcmc_audit.R", "Grid CRPS")
assert_not_contains("application/scripts/20_make_glofas_reservoir_only_full7_diagnostic_figures.R", "Quantile-Grid CRPS")
assert_not_contains("tables/joint_qdesn_article_validation_mcmc_balanced_winner_summary.csv", "Grid CRPS")
assert_contains("main.tex", "tables/qdesn_validation_500obs_metric_dependence_sensitivity.tex")
assert_contains("overleaf/article_files.txt", "tables/qdesn_validation_500obs_metric_dependence_sensitivity.tex")
assert_not_contains("main.tex", "metric_interval_contract_clarification")
assert_not_contains("overleaf/article_files.txt", "metric_interval_contract_clarification")
assert_contains("tables/glofas_application_current_score_summary.tex", "aCRPS")
assert_not_contains("tables/glofas_application_current_score_summary.tex", " & CRPS & ")
assert_contains("tables/glofas_application_current_outputs.tex", "GlofasApplicationCurrentQdesnAcrps")
assert_contains("scripts/build_arxiv_source_bundle.sh", "overleaf/article_files.txt")
assert_not_contains("scripts/build_arxiv_source_bundle.sh", "glofas_stage_n_winner")

cat("Corrected manuscript and score checks passed.\n")
