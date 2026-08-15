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
source(app_path("application/R/joint_exqdesn_phase141_gamma_redesign_readiness.R"))

args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase141_exal_gamma_redesign_readiness_20260719",
  fixed_gamma_dir = "application/cache/joint_qdesn_phase140_exal_fixed_gamma_zero_sensitivity_recovery_20260718",
  launch_root = "application/cache",
  n_cores = "32"
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

result <- app_joint_exqdesn_run_phase141_gamma_redesign_readiness(
  out_dir = arg_value("output_dir"),
  fixed_gamma_dir = arg_value("fixed_gamma_dir"),
  launch_root = arg_value("launch_root"),
  n_cores = parse_integer(arg_value("n_cores"))
)

cat(sprintf("Phase141 gamma-redesign readiness artifacts written to %s\n", result$out_dir))
cat(sprintf("Decision: %s\n", result$decision$phase141_decision[[1L]]))
cat(sprintf("Prepared launches: %s\n", nrow(result$launch_plan)))
cat(sprintf("Prepared chain jobs: %s\n", sum(result$launch_plan$total_chain_jobs)))
cat(sprintf("Launch command file: %s\n", result$paths[["phase141_launch_commands"]]))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
