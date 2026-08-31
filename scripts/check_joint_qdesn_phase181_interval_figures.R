#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
repo_root <- normalizePath(if (length(args)) args[[1L]] else ".", mustWork = TRUE)
table_dir <- file.path(repo_root, "tables")
figure_dir <- file.path(repo_root, "figures", "joint_qdesn_simulation")

sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
read_csv <- function(path) {
  read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}
expect_true <- function(value, message) {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}
expect_equal <- function(x, y, message, tolerance = 1e-10) {
  if (!isTRUE(all.equal(x, y, tolerance = tolerance))) {
    stop(message, call. = FALSE)
  }
}

summary_path <- file.path(
  table_dir, "joint_qdesn_phase181_metric_interval_summary.csv"
)
fit_pdf <- file.path(
  figure_dir, "joint_qdesn_phase181_fit_oracle_rmse_intervals.pdf"
)
forecast_pdf <- file.path(
  figure_dir, "joint_qdesn_phase181_forecast_dgp_score_intervals.pdf"
)
wrapper <- file.path(table_dir, "joint_qdesn_phase181_interval_figures.tex")
article_summary_path <- file.path(
  table_dir, "joint_qdesn_phase181_article_scenario_model_summary.csv"
)
manifest_path <- file.path(
  table_dir, "joint_qdesn_phase181_article_asset_manifest.csv"
)

for (path in c(summary_path, fit_pdf, forecast_pdf, wrapper,
               article_summary_path, manifest_path)) {
  expect_true(file.exists(path), paste("Missing required joint figure asset:", path))
}
for (path in c(fit_pdf, forecast_pdf)) {
  header <- readChar(path, nchars = 4L, useBytes = TRUE)
  expect_true(identical(header, "%PDF"), paste("Figure is not a PDF:", path))
  expect_true(file.info(path)$size > 10000, paste("Figure PDF is unexpectedly small:", path))
}

metric <- read_csv(summary_path)
article <- read_csv(article_summary_path)
manifest <- read_csv(manifest_path)
required <- c(
  "scenario_id", "source_model_id", "likelihood_family", "fit_structure",
  "metric_window", "metric_role", "posterior_mean", "posterior_median",
  "posterior_q025", "posterior_q975", "n_draws", "n_chains",
  "draws_per_chain", "point_reference_value", "canonical_metric_value",
  "canonical_raw_crossing_pairs", "canonical_rearranged_crossing_pairs",
  "crossing_opportunities_per_scenario", "primary_pairing_seed",
  "model_label", "scenario_label"
)
expect_true(all(required %in% names(metric)),
            "The joint metric interval summary has missing columns.")

model_order <- c(
  "joint_qdesn_rhs_vb",
  "qdesn_rhs_independent_vb",
  "joint_exqdesn_rhs_vb",
  "exqdesn_rhs_independent_vb"
)
scenario_order <- c(
  "asymmetric_laplace_tail", "gaussian_mixture_bridge", "laplace_bridge",
  "nonlinear_reservoir_friendly", "normal_bridge", "persistent_heavy_tail",
  "regime_shift", "student_t_location_scale"
)

expect_true(
  nrow(metric) == 64L &&
    setequal(metric$metric_window, c("fit", "forecast")) &&
    all(table(metric$metric_window) == 32L) &&
    setequal(metric$source_model_id, model_order) &&
    setequal(metric$scenario_id, scenario_order),
  "The interval summary is not the expected 64-row fit/forecast grid."
)
expect_true(
  all(table(metric$metric_window, metric$scenario_id) == 4L) &&
    all(table(metric$metric_window, metric$source_model_id) == 8L),
  "The interval summary is not balanced by scenario and model."
)
expect_true(
  all(is.finite(metric$posterior_mean)) &&
    all(is.finite(metric$posterior_median)) &&
    all(is.finite(metric$posterior_q025)) &&
    all(is.finite(metric$posterior_q975)) &&
    all(metric$posterior_q025 <= metric$posterior_median) &&
    all(metric$posterior_median <= metric$posterior_q975) &&
    all(metric$n_draws == 8000L) &&
    all(metric$n_chains == 8L) &&
    all(metric$draws_per_chain == 1000L) &&
    all(metric$primary_pairing_seed == 17819001L) &&
    all(metric$canonical_rearranged_crossing_pairs == 0L),
  "The posterior intervals, draw counts, or crossing fields are invalid."
)

fit <- metric[metric$metric_window == "fit", , drop = FALSE]
forecast <- metric[metric$metric_window == "forecast", , drop = FALSE]
expect_true(
  all(fit$metric_role == "oracle_fit_rmse") &&
    all(fit$point_reference_value == 0) &&
    all(fit$crossing_opportunities_per_scenario == 3000L),
  "Fit rows do not use the oracle-RMSE convention."
)
expect_true(
  all(forecast$metric_role == "dgp_integrated_acrps") &&
    all(forecast$crossing_opportunities_per_scenario == 5940L),
  "Forecast rows do not use the DGP-integrated aCRPS convention."
)

forecast_match <- merge(
  forecast,
  article[c(
    "scenario_id", "source_model_id", "posterior_score_mean",
    "posterior_score_median", "posterior_score_q025", "posterior_score_q975",
    "expected_oracle_acrps", "canonical_action_dgp_integrated_acrps",
    "canonical_raw_crossing_pairs", "canonical_contract_crossing_pairs"
  )],
  by = c("scenario_id", "source_model_id"),
  all.x = TRUE, sort = FALSE
)
expect_true(nrow(forecast_match) == 32L && !anyNA(forecast_match$posterior_score_mean),
            "Forecast figure rows failed to join to the article score summary.")
expect_equal(
  forecast_match$posterior_mean,
  forecast_match$posterior_score_mean,
  "Forecast posterior means do not match the article score table."
)
expect_equal(
  forecast_match$posterior_q025,
  forecast_match$posterior_score_q025,
  "Forecast posterior lower limits do not match the article score table."
)
expect_equal(
  forecast_match$posterior_q975,
  forecast_match$posterior_score_q975,
  "Forecast posterior upper limits do not match the article score table."
)
expect_equal(
  forecast_match$point_reference_value,
  forecast_match$expected_oracle_acrps,
  "Forecast oracle reference values do not match the article score table."
)
expect_equal(
  forecast_match$canonical_metric_value,
  forecast_match$canonical_action_dgp_integrated_acrps,
  "Forecast canonical score values do not match the article score table."
)
expect_true(
  identical(forecast_match$canonical_raw_crossing_pairs.x,
            forecast_match$canonical_raw_crossing_pairs.y) &&
    identical(forecast_match$canonical_rearranged_crossing_pairs,
              forecast_match$canonical_contract_crossing_pairs),
  "Forecast crossing counts do not match the article score table."
)

expected_totals <- data.frame(
  metric_window = rep(c("fit", "forecast"), each = 4L),
  source_model_id = rep(model_order, times = 2L),
  raw_crossings = c(0L, 7L, 0L, 0L, 1L, 25L, 0L, 0L),
  stringsAsFactors = FALSE
)
actual_totals <- aggregate(
  canonical_raw_crossing_pairs ~ metric_window + source_model_id,
  metric, sum
)
actual_totals <- merge(
  actual_totals, expected_totals,
  by = c("metric_window", "source_model_id"), all = TRUE, sort = FALSE
)
expect_true(
  all(actual_totals$canonical_raw_crossing_pairs == actual_totals$raw_crossings),
  "Canonical raw crossing totals changed."
)

main <- paste(readLines(file.path(repo_root, "main.tex"), warn = FALSE),
              collapse = "\n")
wrapper_text <- paste(readLines(wrapper, warn = FALSE), collapse = "\n")
article_files <- readLines(
  file.path(repo_root, "overleaf", "article_files.txt"), warn = FALSE
)
expect_true(
  grepl("\\input{tables/joint_qdesn_phase181_interval_figures.tex}",
        main, fixed = TRUE) &&
    grepl("fig:joint-qdesn-phase181-fit-rmse-intervals", wrapper_text,
          fixed = TRUE) &&
    grepl("fig:joint-qdesn-phase181-forecast-acrps-intervals", wrapper_text,
          fixed = TRUE),
  "The main article does not include the new joint interval figures."
)
expect_true(
  all(c(
    "figures/joint_qdesn_simulation/joint_qdesn_phase181_fit_oracle_rmse_intervals.pdf",
    "figures/joint_qdesn_simulation/joint_qdesn_phase181_forecast_dgp_score_intervals.pdf",
    "tables/joint_qdesn_phase181_interval_figures.tex"
  ) %in% article_files),
  "Overleaf article file list is missing the new joint figure assets."
)

expected_manifest_ids <- c(
  "metric_interval_summary", "fit_rmse_interval_figure",
  "forecast_acrps_interval_figure", "joint_phase181_interval_figures_tex"
)
expect_true(all(expected_manifest_ids %in% manifest$artifact_id),
            "The Phase181 manifest is missing the new figure assets.")
for (i in seq_len(nrow(manifest))) {
  path <- file.path(repo_root, manifest$tracked_path[[i]])
  expect_true(file.exists(path), paste("Manifest path is missing:", manifest$tracked_path[[i]]))
  expect_true(
    identical(sha256(path), manifest$tracked_sha256[[i]]),
    paste("Manifest hash mismatch:", manifest$tracked_path[[i]])
  )
}

cat(
  "JOINT_QDESN_PHASE181_INTERVAL_FIGURES_CHECK=PASS",
  "rows=64 fit_raw_crossings=0,7,0,0 forecast_raw_crossings=1,25,0,0\n"
)
