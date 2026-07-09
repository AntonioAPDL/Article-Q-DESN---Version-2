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
  phase106_dir = "",
  phase107_dir = "",
  screening_output_dir = "",
  n_cores = "9"
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

out_dir <- resolve_path(
  arg_value("output_dir"),
  app_joint_qdesn_default_calibration_screening_readiness_dir(),
  must_work = FALSE
)
phase106_dir <- resolve_path(
  arg_value("phase106_dir"),
  app_joint_qdesn_default_vb_spec_screening_dir(),
  must_work = TRUE
)
phase107_dir <- resolve_path(
  arg_value("phase107_dir"),
  app_path("application/cache/joint_qdesn_selected_vb_freeze_phase107_20260707"),
  must_work = TRUE
)
screening_output_dir <- resolve_path(
  arg_value("screening_output_dir"),
  app_joint_qdesn_default_next_vb_screening_dir(),
  must_work = FALSE
)

result <- app_joint_qdesn_run_calibration_screening_readiness(
  out_dir = out_dir,
  phase106_dir = phase106_dir,
  phase107_dir = phase107_dir,
  screening_output_dir = screening_output_dir,
  n_cores = parse_integer(arg_value("n_cores"))
)

cat(sprintf("Joint QDESN Phase 111 calibration-screening readiness artifacts written to %s\n", result$out_dir))
cat("Largest tau-level joint exQDESN gap:\n")
print(
  result$tau_diagnosis[order(-result$tau_diagnosis$joint_exal_minus_joint_al), c(
    "tau", "joint_exal_minus_joint_al", "recommended_focus"
  ), drop = FALSE][1L, , drop = FALSE],
  row.names = FALSE
)
cat("Recommended Phase 112 launch command:\n")
cat(result$launch_command$command[[1L]], "\n")
cat(sprintf("Recommended registry: %s\n", result$paths[["recommended_screening_registry"]]))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
