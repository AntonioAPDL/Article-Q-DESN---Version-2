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
source(app_path("application/R/joint_exqdesn_phase140_gamma_redesign_readiness.R"))

args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase140_exal_gamma_redesign_readiness_20260717",
  phase139_dir = "application/cache/joint_qdesn_phase139_exal_long_chain_synthesis_20260717",
  n_chains = "8",
  mcmc_n_iter = "12000",
  mcmc_burn = "3000",
  mcmc_thin = "1",
  mcmc_seed_offset = "9600"
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

result <- app_joint_exqdesn_run_phase140_gamma_redesign_readiness(
  out_dir = arg_value("output_dir"),
  phase139_dir = arg_value("phase139_dir"),
  n_chains = parse_integer(arg_value("n_chains")),
  mcmc_n_iter = parse_integer(arg_value("mcmc_n_iter")),
  mcmc_burn = parse_integer(arg_value("mcmc_burn")),
  mcmc_thin = parse_integer(arg_value("mcmc_thin")),
  mcmc_seed_offset = parse_integer(arg_value("mcmc_seed_offset"))
)

cat(sprintf("Phase140 gamma-redesign readiness artifacts written to %s\n", result$out_dir))
cat("\nDecision:\n")
print(result$decision, row.names = FALSE)
cat("\nPriority cases:\n")
print(result$case_priority[, c(
  "case_id", "scenario_id", "source_model_id",
  "forecast_gap_to_matched_al", "phase140_case_action"
)], row.names = FALSE)
cat("\nPrepared launch plan:\n")
print(result$launch_plan[, c(
  "launch_id", "launch_status", "variant_ids", "n_cases",
  "n_chains", "total_chain_jobs", "mcmc_n_iter", "output_dir"
)], row.names = FALSE)
cat(sprintf("\nLaunch command file: %s\n", result$paths[["phase140_launch_commands"]]))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
