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
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_exqdesn_trace_tools.R"))
source(app_path("application/R/joint_exqdesn_phase136_gamma_kernel_packet.R"))
source(app_path("application/R/joint_exqdesn_phase142_post_geometry_synthesis.R"))

args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase142_post_geometry_synthesis_20260722",
  phase135_dir = "application/cache/joint_qdesn_phase135_matched_exal_screening_20260715",
  fixed_dir = "application/cache/joint_qdesn_phase140_exal_fixed_gamma_zero_sensitivity_recovery_20260718",
  primary_dir = "application/cache/joint_qdesn_phase141_primary_narrow_gamma_geometry_screen_20260719",
  focus_dir = "application/cache/joint_qdesn_phase141_focus_width_sensitivity_screen_20260719",
  regularized_output_dir = "application/cache/joint_qdesn_phase142_regularized_gamma_screen_20260722",
  n_cores = "24"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_integer <- function(x) {
  out <- as.integer(suppressWarnings(as.numeric(as.character(x)[[1L]])))
  if (is.na(out)) stop(sprintf("Expected integer value, got '%s'.", x), call. = FALSE)
  out
}

result <- app_joint_exqdesn_run_phase142_post_geometry_synthesis(
  out_dir = arg_value("output_dir"),
  phase135_dir = arg_value("phase135_dir"),
  fixed_dir = arg_value("fixed_dir"),
  primary_dir = arg_value("primary_dir"),
  focus_dir = arg_value("focus_dir"),
  regularized_out_dir = arg_value("regularized_output_dir"),
  n_cores = parse_integer(arg_value("n_cores"))
)

cat(sprintf("Phase142 post-geometry synthesis artifacts written to %s\n", result$out_dir))
cat(sprintf("Decision: %s\n", result$decision$sampled_gamma_geometry_decision[[1L]]))
cat(sprintf("Next stage: %s\n", result$decision$next_stage_decision[[1L]]))
cat(sprintf("Regularized launch command: %s\n", result$paths[["launch_command"]]))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
