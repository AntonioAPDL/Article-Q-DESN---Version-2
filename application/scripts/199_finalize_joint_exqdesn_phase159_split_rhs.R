#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R", "joint_exqdesn_trace_tools.R", "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_exqdesn_phase158_fan_audit.R", "joint_exqdesn_phase159_split_rhs_screening.R"
)) source(app_path("application/R", file))
args <- app_parse_args(list(
  freeze_dir = "application/cache/joint_qdesn_phase159_split_rhs_calibration_freeze_20260804",
  output_dir = "application/cache/joint_qdesn_phase159_split_rhs_calibration_mcmc_20260804"
))
resolve <- function(name) {
  x <- args[[gsub("_", "-", name, fixed = TRUE)]] %||% args[[name]]
  normalizePath(if (grepl("^/", x)) x else app_path(x), mustWork = TRUE)
}
result <- app_joint_exqdesn_phase159_finalize(resolve("freeze_dir"), resolve("output_dir"))
print(result$assessment, row.names = FALSE)
print(result$selection, row.names = FALSE)
