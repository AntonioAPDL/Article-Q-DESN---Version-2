#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  runtime_root = "local_trackers/runtime_configs/glofas_part3_cross_input_normal_challenger_jerez_20260905"
))

runtime_root <- app_resolve_path(args$runtime_root, must_work = FALSE)
jobs <- c("design_cache", "normal_ridge_joint", "normal_rhs_vb_joint", "comparison")
status_dir <- file.path(runtime_root, "status")
status_for <- function(job) {
  states <- c("failed", "running", "completed")
  hit <- states[file.exists(file.path(status_dir, paste0(job, ".", states)))]
  if (length(hit)) hit[[1L]] else "pending"
}
status <- data.frame(
  job_id = jobs,
  status = vapply(jobs, status_for, character(1L)),
  stringsAsFactors = FALSE
)
status$completed <- status$status == "completed"
status$failed <- status$status == "failed"
status$running <- status$status == "running"
status$left_to_finish <- !status$completed & !status$failed
app_write_csv(status, file.path(runtime_root, "tables", "cross_input_job_status_latest.csv"))

health <- data.frame(
  total = nrow(status),
  completed = sum(status$completed),
  running = sum(status$running),
  failed = sum(status$failed),
  pending = sum(status$status == "pending"),
  left_to_finish = sum(status$left_to_finish),
  stringsAsFactors = FALSE
)
app_write_csv(health, file.path(runtime_root, "tables", "cross_input_health_latest.csv"))

cat(sprintf("Runtime root: %s\n", runtime_root))
print(status, row.names = FALSE)
print(health, row.names = FALSE)

decision_path <- file.path(runtime_root, "scores", "cross_input_decision.csv")
if (file.exists(decision_path)) {
  cat("\nDecision:\n")
  print(app_read_csv(decision_path), row.names = FALSE)
}

comparison_path <- file.path(runtime_root, "scores", "baseline_vs_cross_input_comparison.csv")
if (file.exists(comparison_path)) {
  cmp <- app_read_csv(comparison_path)
  keep <- cmp$method == "normal_rhs_vb_joint" & cmp$metric %in% c(
    "reference_valid_mean_crps",
    "discrepancy_valid_mean_crps",
    "corrected_valid_mean_crps",
    "joint_usgs_valid_mean_crps",
    "joint_glofas_valid_mean_crps"
  )
  cat("\nNormal RHS/VB primary comparison:\n")
  print(cmp[keep, , drop = FALSE], row.names = FALSE)
}
