#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))

args <- app_parse_args(list(
  runtime_root = "local_trackers/runtime_configs/glofas_part3_joint_historical_deferred_20260903"
))

runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
manifest_path <- file.path(runtime_root, "configs", "part3_model_manifest.csv")
if (!file.exists(manifest_path)) stop(sprintf("Missing Part 3 manifest: %s", manifest_path), call. = FALSE)
manifest <- app_read_csv(manifest_path)
app_check_required_columns(
  manifest,
  c("run_label", "job_id", "model_family", "depends_on", "worker_slots", "status"),
  "GloFAS Part 3 launch manifest"
)

status_dir <- file.path(runtime_root, "status")
app_ensure_dir(status_dir)
marker_exists <- function(job_id, suffix) {
  file.exists(file.path(status_dir, paste0(job_id, ".", suffix)))
}
job_status <- manifest
job_status$current_state <- vapply(seq_len(nrow(manifest)), function(i) {
  job_id <- as.character(manifest$job_id[[i]] %||% manifest$model_family[[i]])
  if (marker_exists(job_id, "completed")) return("completed")
  if (marker_exists(job_id, "failed")) return("failed")
  if (marker_exists(job_id, "running")) return("running")
  if (grepl("quantile", as.character(manifest$status[[i]])) ||
      grepl("quantile", as.character(manifest$model_family[[i]]))) return("blocked")
  dependency <- as.character(manifest$depends_on[[i]] %||% "")
  if (nzchar(dependency) && !marker_exists(dependency, "completed")) return("pending_dependency")
  if (grepl("^blocked_missing", as.character(manifest$status[[i]]))) return("blocked")
  "ready"
}, character(1L))
job_status$checked_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
app_write_csv(job_status, file.path(status_dir, "job_status_latest.csv"))
summary <- data.frame(
  runtime_root = runtime_root,
  total_slots = nrow(manifest),
  ready_slots = sum(job_status$current_state == "ready"),
  pending_slots = sum(job_status$current_state == "pending_dependency"),
  blocked_slots = sum(job_status$current_state == "blocked"),
  completed_markers = sum(job_status$current_state == "completed"),
  running_markers = sum(job_status$current_state == "running"),
  failed_markers = sum(job_status$current_state == "failed"),
  launched = any(job_status$current_state %in% c("completed", "running", "failed")),
  checked_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  stringsAsFactors = FALSE
)
print(summary)
app_write_csv(summary, file.path(status_dir, "health_latest.csv"))

score_files <- list.files(file.path(runtime_root, "scores"), pattern = "_summary[.]csv$", full.names = TRUE)
if (length(score_files)) {
  scores <- app_bind_rows_fill(lapply(score_files, app_read_csv))
  scores <- scores[order(scores$valid_mean_crps), , drop = FALSE]
  print(utils::head(scores[, intersect(
    c("candidate_id", "method", "valid_mean_crps", "valid_mae", "valid_rmse", "runtime_seconds", "status"),
    names(scores)
  ), drop = FALSE], 10L))
}
