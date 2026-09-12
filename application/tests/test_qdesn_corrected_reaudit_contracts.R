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
    p = c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95),
    w = c(0.075, 0.150, 0.150, 0.150, 0.150, 0.150, 0.075)
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

# The selected GloFAS authority is the Part 4 Joint AL latent-path analysis.
# The future USGS path is latent during fitting, and the issued-member
# likelihood is normalized to one unit of information at each horizon.
part4_scores <- read.csv(
  app_path("tables/glofas_application_part4_forecast_scores__glofas_part4_joint_al_sweep10_20260911.csv"),
  stringsAsFactors = FALSE
)
stopifnot(all(part4_scores$n_scored_horizons == 28L))
stopifnot(identical(
  part4_scores$numerical_status[part4_scores$family == "Joint AL"],
  "cap_stabilized_after_rhs_release"
))
stopifnot(identical(
  part4_scores$numerical_status[part4_scores$family == "Joint exAL"],
  "source_fit_not_qualified"
))
assert_contains("main.tex", "represented as latent during fitting")
assert_contains("main.tex", "51 issued members has weight \\(1/51\\)")
assert_contains("main.tex", "No crossing correction is applied")
assert_contains("main.tex", "cap-stabilized after RHS release")
assert_not_contains("main.tex", "persistence-anchored discrepancy")

# PriceFM is a retrospective comparison with retrospectively observed own-region
# leads in every selected row and additional neighbor leads when neighborhood
# summaries are included.
assert_contains("main.tex", "Both predictor sets use retrospectively")
assert_contains("main.tex", "own-region load, solar, and wind lead covariates")
assert_contains("main.tex", "evaluations with neighborhood summaries add retrospectively observed neighboring-region lead")
manifest <- jsonlite::fromJSON(app_path("tables/pricefm_paper_aligned_main_comparison_manifest.json"))
stopifnot(identical(manifest$applicability$cross_panel_comparison, "context_only_not_head_to_head"))
stopifnot(identical(manifest$published_comparison$external_table_rows, 0L))
stopifnot(identical(
  manifest$published_comparison$overall_and_fold_table,
  "tables/pricefm_full_main_summary.tex"
))
stopifnot(identical(
  manifest$published_comparison$horizon_table,
  "tables/pricefm_full_horizon_diagnostic_summary.tex"
))
aligned <- utils::read.csv(
  app_path("tables/pricefm_paper_aligned_main_comparison.csv"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)
qdesn_aligned <- aligned[aligned$model_family == "qdesn_case_specific", , drop = FALSE]
pricefm_aligned <- aligned[aligned$model_family == "pricefm_phase1_released_checkpoint", , drop = FALSE]
stopifnot(nrow(qdesn_aligned) == 1L, nrow(pricefm_aligned) == 1L)
stopifnot(abs(qdesn_aligned$AQL - 6.823677420470439) < 1.0e-12)
stopifnot(abs(qdesn_aligned$AQCR_percent - 2.579293032015585) < 1.0e-12)
stopifnot(abs(qdesn_aligned$MAE - 16.721997707630997) < 1.0e-12)
stopifnot(abs(qdesn_aligned$RMSE - 25.449231419703835) < 1.0e-12)
stopifnot(abs(pricefm_aligned$AQL - 7.038685346534470) < 1.0e-12)
updates <- utils::read.csv(
  app_path("tables/pricefm_r91_selective_promotions.csv"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)
stopifnot(nrow(updates) == 12L)
stopifnot(sum(updates$selected_family == "exal") == 11L)
stopifnot(sum(updates$selected_family == "al") == 1L)
stopifnot(all(updates$promoted_qdesn_AQL < updates$old_qdesn_AQL))
stopifnot(all(updates$promoted_qdesn_AQL < updates$pricefm_AQL))
assert_contains("main.tex", "AL and exAL specifications were chosen using validation AQL")
assert_contains("main.tex", "The reported aggregate uses the selected specification")
assert_contains("main.tex", "\\input{tables/pricefm_full_main_summary.tex}")
assert_contains("main.tex", "\\input{tables/pricefm_full_horizon_diagnostic_summary.tex}")
assert_contains("main.tex", "forecast-lead-specific results")
assert_contains(
  "tables/pricefm_full_main_summary.tex",
  "Overall & 114 & 66 & 12 & 36 & 6.824 & 7.039 & -0.215 & -0.083"
)
assert_contains("tables/pricefm_full_main_summary.tex", "PriceFM\\\\lower by $\\leq 5\\%$")
assert_not_contains("tables/pricefm_full_main_summary.tex", "Near\\\\ties")
assert_contains(
  "tables/pricefm_full_main_summary.tex",
  "Fold 3 & 38 & 14 & 4 & 20 & 6.998 & 6.993 & 0.005 & 0.281"
)
assert_contains(
  "tables/pricefm_full_horizon_diagnostic_summary.tex",
  "1--24 & 72 & 22 & 0.415 & 0.351"
)
assert_contains(
  "tables/pricefm_full_horizon_diagnostic_summary.tex",
  "73--96 & 72 & 42 & -0.155 & -0.114"
)
assert_contains("tables/pricefm_full_horizon_diagnostic_summary.tex", "Forecast-lead block")
assert_not_contains("main.tex", "PriceFM v4 Table II")
assert_not_contains("main.tex", "tab:pricefm-paper-aligned-main-comparison")
for (external_model in c(
  "Naive1", "Naive2", "Naive3", "FEDFormer", "PatchTST", "iTransformer",
  "TimesNet", "TimeXer", "GraphConv", "GraphAttn", "GraphSAGE",
  "GraphDiffusion", "GraphARMA"
)) {
  assert_not_contains("main.tex", external_model)
}
assert_not_contains(
  "tables/pricefm_paper_aligned_current_outputs.tex",
  "PricefmPaperAlignedMainComparisonTable"
)
assert_not_contains(
  "overleaf/article_files.txt",
  "tables/pricefm_paper_aligned_main_comparison.tex"
)
assert_contains("qdesn-supplement.tex", "tab:supp-pricefm-selective-updates")
assert_contains("qdesn-supplement.tex", "Comparison of selected and reference Q--DESN specifications")
assert_not_contains("qdesn-supplement.tex", "tab:supp-pricefm-full-fold-summary")
assert_not_contains("qdesn-supplement.tex", "tab:supp-pricefm-full-horizon-diagnostic-summary")
assert_contains("overleaf/article_files.txt", "tables/pricefm_r91_selective_promotions.tex")

# The visible score label is aCRPS. Legacy variable names remain as
# compatibility aliases, while current-output labels identify the finite-grid
# score precisely.
assert_contains("main.tex", "\\(\\aCRPS\\)")
assert_contains("main.tex", "finite evaluation grid \\(p_1,\\ldots,p_K\\)")
assert_contains("main.tex", "\\aCRPS_{p_1:p_K}")
assert_not_contains("main.tex", "\\mathcal P_K")
assert_contains("main.tex", "K\\geq2")
assert_contains("main.tex", "q_{T,h,k}^*")
assert_contains("main.tex", "\\sum_{k=1}^K\\omega_k=p_K-p_1")
assert_contains("main.tex", "integrated check-loss")
assert_contains("main.tex", "with finite first moment")
assert_contains("main.tex", "posterior-mean quantile curve")
assert_contains("main.tex", "variational posterior-mean quantile estimates")
assert_contains("qdesn-supplement.tex", "Response-level posterior predictive")
assert_contains("qdesn-supplement.tex", "fitted \\(p\\)-level quantile")
assert_contains("main.tex", "held-out design points")
assert_contains("qdesn-supplement.tex", "fixed held-out")
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
