#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R")); app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R", "joint_exqdesn_trace_tools.R", "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_exqdesn_phase158_fan_audit.R", "joint_exqdesn_phase159_split_rhs_screening.R",
  "joint_exqdesn_phase160_independent_confirmation.R"
)) source(app_path("application/R", file))
args <- app_parse_args(list(freeze_dir = app_joint_exqdesn_phase160_default_freeze_dir(), worker_id = NA_integer_))
freeze_dir <- args[["freeze-dir"]] %||% args$freeze_dir
worker_id <- as.integer(args[["worker-id"]] %||% args$worker_id)
if (is.na(worker_id)) stop("--worker-id is required.", call. = FALSE)
result <- app_joint_exqdesn_phase160_run_worker(freeze_dir, worker_id)
cat(sprintf("worker=%d status=%s\n", worker_id, result$status))
