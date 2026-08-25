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
  worker_id = "1", reuse_completed = "true", failure_dir = ""
))
value <- function(name) args[[gsub("_", "-", name, fixed = TRUE)]] %||% args[[name]]
freeze_dir <- as.character(value("freeze_dir"))[[1L]]
freeze_dir <- normalizePath(if (grepl("^/", freeze_dir)) freeze_dir else app_path(freeze_dir), mustWork = TRUE)
reuse <- tolower(as.character(value("reuse_completed"))[[1L]]) %in% c("true", "1", "yes")
failure_dir <- as.character(value("failure_dir"))[[1L]]
if (nzchar(failure_dir)) {
  failure_dir <- normalizePath(if (grepl("^/", failure_dir)) failure_dir else app_path(failure_dir), mustWork = FALSE)
}
result <- app_joint_exqdesn_run_phase157_worker(
  freeze_dir = freeze_dir,
  worker_id = as.integer(as.character(value("worker_id"))[[1L]]),
  reuse_completed = reuse,
  failure_dir = failure_dir
)
cat(sprintf("worker=%d status=%s dir=%s\n", result$worker_id, result$status, result$worker_dir))
