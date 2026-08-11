#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R",
  "joint_qdesn_simulation_validation.R", "joint_qdesn_vb_spec_screening.R",
  "joint_qdesn_calibration_screening.R", "joint_qdesn_mcmc_readiness.R",
  "joint_exqdesn_trace_tools.R", "joint_exqdesn_phase156_collapsed_gamma_sigma.R"
)) source(app_path("application/R", file))
args <- app_parse_args(list(
  freeze_dir = "application/cache/joint_qdesn_phase156b_collapsed_gamma_sigma_recovery_freeze_20260802",
  output_dir = "application/cache/joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802"
))
value <- function(name) args[[gsub("_", "-", name, fixed = TRUE)]] %||% args[[name]]
path <- function(name, must) {
  x <- as.character(value(name))[[1L]]
  normalizePath(if (grepl("^/", x)) x else app_path(x), mustWork = must)
}
result <- app_joint_exqdesn_finalize_phase157(path("freeze_dir", TRUE), path("output_dir", TRUE))
cat(sprintf("Phase157 finalized: %s\n", result$out_dir))
print(result$assessment[, c("scenario_id", "gate_status", "max_gamma_rank_rhat", "min_gamma_bulk_ess", "forecast_truth_mae", "raw_crossing_pairs", "contract_crossing_pairs")], row.names = FALSE)
