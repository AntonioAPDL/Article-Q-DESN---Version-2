#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, digits = 17)

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "scripts", "qdesn_evaluation_figure_style.R"))

if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("The ggplot2 package is required.", call. = FALSE)
}

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(flag, default) {
  at <- match(flag, args)
  if (is.na(at) || at == length(args)) default else args[[at + 1L]]
}
scope <- arg_value("--scope", "active")
if (!scope %in% c("active", "all")) {
  stop("--scope must be active or all.", call. = FALSE)
}

read_table <- function(name) read.csv(
  file.path(repo_root, "tables", name), stringsAsFactors = FALSE,
  check.names = FALSE
)
expect <- function(value, message) {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}

independent <- read_table(
  "qdesn_validation_500obs_dgp_oracle_figure_data_v14.csv"
)
required_independent <- c(
  "inference", "model_variant", "family", "tau", "metric_role",
  "posterior_mean", "cri_lower", "cri_upper", "diagnostic_grade",
  "plot_reference_value"
)
expect(all(required_independent %in% names(independent)),
       "The tracked independent figure table has an incomplete schema.")
expect(nrow(independent) == 216L, "The independent figure table must have 216 rows.")
independent_key <- with(
  independent,
  paste(inference, model_variant, family, sprintf("%.2f", tau), metric_role,
        sep = "|")
)
expect(!anyDuplicated(independent_key), "The independent figure key is duplicated.")
expect(setequal(unique(independent$model_variant), qdesn_independent_model_order),
       "The independent model surface changed.")
expect(all(is.finite(independent$posterior_mean)) &&
         all(is.finite(independent$cri_lower)) &&
         all(is.finite(independent$cri_upper)) &&
         all(independent$cri_lower <= independent$posterior_mean) &&
         all(independent$posterior_mean <= independent$cri_upper),
       "An independent interval is invalid.")
expect(sum(independent$diagnostic_grade == "WARN") == 5L,
       "The five independent diagnostic warnings changed.")

independent_dir <- file.path(repo_root, "figures", "independent_simulation")
independent_jobs <- data.frame(
  inference = c("mcmc", "mcmc", "mcmc", "vb"),
  metric_role = c("fit_rmse", "forecast_mae", "forecast_check", "fit_rmse"),
  filename = c(
    "qdesn_validation_500obs_v14_mcmc_fit_rmse_intervals.pdf",
    "qdesn_validation_500obs_v14_mcmc_forecast_mae_intervals.pdf",
    "qdesn_validation_500obs_v14_mcmc_forecast_check_loss_intervals.pdf",
    "qdesn_validation_500obs_v14_vb_fit_rmse_intervals.pdf"
  ), stringsAsFactors = FALSE
)
if (scope == "all") {
  independent_jobs <- rbind(independent_jobs, data.frame(
    inference = c("vb", "vb"),
    metric_role = c("forecast_mae", "forecast_check"),
    filename = c(
      "qdesn_validation_500obs_v14_vb_forecast_mae_intervals.pdf",
      "qdesn_validation_500obs_v14_vb_forecast_check_loss_intervals.pdf"
    ), stringsAsFactors = FALSE
  ))
}
for (ii in seq_len(nrow(independent_jobs))) {
  job <- independent_jobs[ii, , drop = FALSE]
  plot <- qdesn_independent_interval_plot(
    independent, job$inference[[1L]], job$metric_role[[1L]]
  )
  qdesn_save_vector_pdf(
    file.path(independent_dir, job$filename[[1L]]), plot,
    width = 7.2, height = 6.6
  )
}

score <- read_table("joint_qdesn_shared_backbone_score_summary.csv")
fit <- read_table("joint_qdesn_shared_backbone_fit_interval_summary.csv")
expect(nrow(score) == 32L && nrow(fit) == 32L,
       "The tracked joint figure tables must each have 32 rows.")
expect(setequal(score$source_model_id, qdesn_joint_model_order) &&
         setequal(fit$source_model_id, qdesn_joint_model_order),
       "The joint model surface changed.")
expect(all(score$canonical_contract_crossing_pairs == 0L) &&
         all(fit$canonical_contract_crossing_pairs == 0L),
       "A joint contract crossing is nonzero.")

joint_plot_data <- function(x, mean_name, lo_name, hi_name, crossing_name) {
  data.frame(
    scenario_id = x$scenario_id,
    source_model_id = x$source_model_id,
    likelihood_family = x$likelihood_family,
    mean = x[[mean_name]], lo = x[[lo_name]], hi = x[[hi_name]],
    crossing = x[[crossing_name]], stringsAsFactors = FALSE
  )
}
fit_plot <- joint_plot_data(
  fit, "posterior_mean", "posterior_q025", "posterior_q975",
  "canonical_raw_crossing_pairs"
)
forecast_plot <- joint_plot_data(
  score, "posterior_score_mean", "posterior_score_q025",
  "posterior_score_q975", "canonical_raw_crossing_pairs"
)
oracle_lines <- data.frame(
  scenario_id = score$scenario_id,
  oracle = score$posterior_score_mean - score$posterior_regret_mean
)
oracle_lines <- aggregate(oracle ~ scenario_id, oracle_lines, mean)

joint_dir <- file.path(repo_root, "figures", "joint_qdesn_simulation")
qdesn_save_vector_pdf(
  file.path(joint_dir, "joint_qdesn_shared_backbone_fit_oracle_rmse_intervals.pdf"),
  qdesn_joint_interval_plot(
    fit_plot, "Fitting-sample quantile-path RMSE"
  ), width = 7.0, height = 8.15
)
qdesn_save_vector_pdf(
  file.path(joint_dir, "joint_qdesn_shared_backbone_forecast_dgp_score_intervals.pdf"),
  qdesn_joint_interval_plot(
    forecast_plot, "DGP-integrated finite-grid quantile score", oracle_lines
  ), width = 7.0, height = 8.15
)

cat(sprintf(
  paste0("QDESN_EVALUATION_FIGURES_RENDERED=PASS ",
         "independent=%d joint=2 scope=%s\n"),
  nrow(independent_jobs), scope
))
