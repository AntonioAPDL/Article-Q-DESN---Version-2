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
source(app_path("application/R/joint_exqdesn_phase137_gamma_kernel_readiness.R"))

args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase137_exal_gamma_kernel_readiness_20260716",
  phase136_dir = "application/cache/joint_qdesn_phase136_exal_gamma_kernel_packet_20260715",
  next_n_chains = "8",
  next_mcmc_n_iter = "16000",
  next_mcmc_burn = "4000",
  next_mcmc_thin = "1",
  next_mcmc_seed_offset = "8600"
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

result <- app_joint_exqdesn_run_phase137_gamma_kernel_readiness(
  out_dir = arg_value("output_dir"),
  phase136_dir = arg_value("phase136_dir"),
  next_n_chains = parse_integer(arg_value("next_n_chains")),
  next_mcmc_n_iter = parse_integer(arg_value("next_mcmc_n_iter")),
  next_mcmc_burn = parse_integer(arg_value("next_mcmc_burn")),
  next_mcmc_thin = parse_integer(arg_value("next_mcmc_thin")),
  next_mcmc_seed_offset = parse_integer(arg_value("next_mcmc_seed_offset"))
)

cat(sprintf("Phase137 gamma-kernel readiness artifacts written to %s\n", result$out_dir))
print(result$decision, row.names = FALSE)
cat("\nHealth summary:\n")
print(result$health[, c("check", "status", "observed")], row.names = FALSE)
cat("\nPrepared launch groups:\n")
print(result$launch_plan[, c("launch_group_id", "n_cases", "total_chain_jobs", "mcmc_n_iter", "n_cores", "launched_in_phase137")], row.names = FALSE)
