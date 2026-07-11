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
source(app_path("application/R/joint_qdesn_calibration_screening.R"))

args <- app_parse_args(list(
  output_dir = "",
  screening_output_dir = "",
  fixture_dir = "",
  table_dir = "tables",
  n_cores = "1"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_integer <- function(x) {
  out <- as.integer(suppressWarnings(as.numeric(as.character(x)[[1L]])))
  if (is.na(out)) stop(sprintf("Expected integer value, got '%s'.", as.character(x)[[1L]]), call. = FALSE)
  out
}

resolve_path <- function(path, default, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(path)) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

result <- app_joint_qdesn_run_phase119_case_specific_calibration_readiness(
  out_dir = resolve_path(
    arg_value("output_dir"),
    app_joint_qdesn_default_phase119_case_readiness_dir(),
    must_work = FALSE
  ),
  screening_output_dir = resolve_path(
    arg_value("screening_output_dir"),
    app_joint_qdesn_default_phase119_case_screening_dir(),
    must_work = FALSE
  ),
  fixture_dir = resolve_path(
    arg_value("fixture_dir"),
    app_joint_qdesn_default_simulation_fixture_dir(),
    must_work = FALSE
  ),
  table_dir = resolve_path(arg_value("table_dir"), "tables", must_work = TRUE),
  n_cores = parse_integer(arg_value("n_cores"))
)

cat(sprintf("Joint QDESN Phase 119 case-specific calibration readiness written to %s\n", result$out_dir))
cat("Readiness decision:\n")
print(result$run_config[, c("readiness_decision", "article_asset_manifest_status", "n_cases", "n_high_priority_cases", "n_registry_rows")], row.names = FALSE)
cat("Case priority counts:\n")
print(as.data.frame(table(result$case_table$priority), stringsAsFactors = FALSE), row.names = FALSE)
cat("Shard registries:\n")
print(data.frame(shard = names(result$shard_paths), path = unname(result$shard_paths), stringsAsFactors = FALSE), row.names = FALSE)
cat("Recommended launch commands:\n")
print(result$launch_commands[, c("command_id", "registry_shard", "run_condition")], row.names = FALSE)
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
