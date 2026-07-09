#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- if (!is.na(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_fixtures.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))

args <- app_parse_args(list(
  output_dir = "",
  catastrophic_truth_mae = "5"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

resolve_path <- function(path, default, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(path)) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

parse_number <- function(x) {
  out <- suppressWarnings(as.numeric(as.character(x)[[1L]]))
  if (is.na(out)) stop(sprintf("Expected numeric value, got '%s'.", as.character(x)[[1L]]), call. = FALSE)
  out
}

out_dir <- resolve_path(arg_value("output_dir"), app_joint_qdesn_default_vb_spec_screening_dir(), must_work = TRUE)
result <- app_joint_qdesn_audit_vb_spec_screening(
  out_dir = out_dir,
  catastrophic_truth_mae = parse_number(arg_value("catastrophic_truth_mae"))
)

cat(sprintf("Joint QDESN Phase 106 audit refreshed in %s\n", result$out_dir))
cat("Health summary:\n")
print(result$health[, c("candidate_id", "gate_status", "forecast_raw_crossings", "max_forecast_truth_mae", "elapsed_seconds")], row.names = FALSE)
cat("Selected specification:\n")
print(result$selected[, c("candidate_id", "gate_status", "screening_score", "next_action")], row.names = FALSE)
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
