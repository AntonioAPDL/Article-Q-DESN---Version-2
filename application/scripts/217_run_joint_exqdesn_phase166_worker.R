#!/usr/bin/env Rscript

Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1"
)
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_phase153_balanced_independent_replication.R",
  "joint_exqdesn_exact_structured_inference.R",
  "joint_exqdesn_inference_dispatch.R",
  "joint_exqdesn_phase164_165_readiness.R",
  "joint_exqdesn_phase166_168_structured_vb.R"
)) source(app_path("application/R", file))

arg_value <- function(name, default = NULL) {
  args <- commandArgs(trailingOnly = TRUE)
  index <- match(name, args)
  if (is.na(index) || index == length(args)) return(default)
  args[[index + 1L]]
}
worker_id <- as.integer(arg_value("--worker-id"))
worker_count <- as.integer(arg_value("--worker-count"))
if (!is.finite(worker_id) || !is.finite(worker_count) || worker_id < 1L || worker_id > worker_count) {
  stop("Worker id/count are invalid.", call. = FALSE)
}
dirs <- app_joint_exqdesn_phase164_dirs()
phase164 <- app_read_csv(file.path(dirs$phase164, "phase164_readiness_assessment.csv"))
phase165 <- app_read_csv(file.path(dirs$phase165, "phase165_assessment.csv"))
if (phase164$gate_status[[1L]] != "pass" || phase165$gate_status[[1L]] != "pass") {
  stop("Phase166 worker launch is blocked by Phase164/165.", call. = FALSE)
}
registry <- app_read_csv(file.path(dirs$phase164, "method_development_registry.csv"))
row_indices <- app_joint_exqdesn_phase166_worker_row_indices(registry, worker_id, worker_count)
result <- app_joint_exqdesn_phase166_run_rows(row_indices, dirs)
orchestration <- file.path(dirs$phase166, "orchestration")
app_ensure_dir(orchestration)
app_joint_qvp_write_csv(result, file.path(orchestration, sprintf("worker_%03d_result.csv", worker_id)))
print(table(result$status))
if (any(result$status == "failed")) {
  print(result[result$status == "failed", ], row.names = FALSE)
  quit(status = 1L)
}
