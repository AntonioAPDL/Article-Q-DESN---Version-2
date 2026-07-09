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
  fixture_dir = "",
  registry = "",
  candidate_ids = "",
  n_cores = "9",
  reuse_completed = "true",
  audit_only = "false",
  catastrophic_truth_mae = "5"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_csv <- function(x) {
  vals <- trimws(strsplit(as.character(x), ",", fixed = TRUE)[[1L]])
  vals[nzchar(vals)]
}

parse_bool <- function(x) {
  x <- tolower(trimws(as.character(x)[[1L]]))
  if (x %in% c("true", "t", "1", "yes", "y")) return(TRUE)
  if (x %in% c("false", "f", "0", "no", "n")) return(FALSE)
  stop(sprintf("Expected boolean value, got '%s'.", x), call. = FALSE)
}

parse_integer <- function(x) {
  out <- as.integer(suppressWarnings(as.numeric(as.character(x)[[1L]])))
  if (is.na(out)) stop(sprintf("Expected integer value, got '%s'.", as.character(x)[[1L]]), call. = FALSE)
  out
}

parse_number <- function(x) {
  out <- suppressWarnings(as.numeric(as.character(x)[[1L]]))
  if (is.na(out)) stop(sprintf("Expected numeric value, got '%s'.", as.character(x)[[1L]]), call. = FALSE)
  out
}

resolve_path <- function(path, default, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(path)) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

out_dir <- resolve_path(arg_value("output_dir"), app_joint_qdesn_default_vb_spec_screening_dir(), must_work = FALSE)
fixture_dir <- resolve_path(arg_value("fixture_dir"), app_joint_qdesn_default_simulation_fixture_dir(), must_work = TRUE)
registry_path <- as.character(arg_value("registry"))[[1L]]
candidate_registry <- if (nzchar(registry_path)) {
  app_read_csv(resolve_path(registry_path, registry_path, must_work = TRUE))
} else {
  NULL
}
candidate_ids <- parse_csv(arg_value("candidate_ids"))

result <- app_joint_qdesn_run_vb_spec_screening(
  out_dir = out_dir,
  fixture_dir = fixture_dir,
  candidate_registry = candidate_registry,
  candidate_ids = if (length(candidate_ids)) candidate_ids else NULL,
  n_cores = parse_integer(arg_value("n_cores")),
  reuse_completed = parse_bool(arg_value("reuse_completed")),
  audit_only = parse_bool(arg_value("audit_only")),
  catastrophic_truth_mae = parse_number(arg_value("catastrophic_truth_mae"))
)

cat(sprintf("Joint QDESN Phase 106 VB spec screening artifacts written to %s\n", result$out_dir))
cat("Health summary:\n")
print(result$health[, c("candidate_id", "gate_status", "forecast_raw_crossings", "max_forecast_truth_mae", "elapsed_seconds")], row.names = FALSE)
cat("Selected specification:\n")
print(result$selected[, c("candidate_id", "gate_status", "screening_score", "next_action")], row.names = FALSE)
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
