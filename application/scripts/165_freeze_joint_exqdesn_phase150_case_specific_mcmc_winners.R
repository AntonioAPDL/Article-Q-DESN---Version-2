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
source(app_path("application/R/joint_exqdesn_phase148_target_invariance.R"))
source(app_path("application/R/joint_exqdesn_phase149_case_specific_screening.R"))
source(app_path("application/R/joint_exqdesn_phase150_case_specific_mcmc_confirmation.R"))

args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_freeze_20260727",
  phase149_dir = "application/cache/joint_qdesn_phase149_case_specific_exal_screening_20260726",
  readiness_dir = "application/cache/joint_qdesn_phase149_case_specific_exal_screening_readiness_20260726",
  phase149_audit_dir = "",
  mcmc_dir = "application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727",
  fixture_dir = "application/cache/joint_qdesn_simulation_dgp_fixtures_20260706",
  n_chains = "8",
  mcmc_n_iter = "8000",
  mcmc_burn = "2000",
  mcmc_thin = "4",
  mcmc_seed_offset = "9500",
  chain_seed_stride = "100",
  sigma_upper_multiplier = "50",
  distance_pass = "5",
  chain_pass = "5",
  n_cores = "8"
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

parse_number <- function(x) {
  out <- suppressWarnings(as.numeric(as.character(x)[[1L]]))
  if (is.na(out)) stop(sprintf("Expected numeric value, got '%s'.", x), call. = FALSE)
  out
}

resolve_path <- function(path, default = "", must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(trimws(path))) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

phase149_dir <- resolve_path(arg_value("phase149_dir"), must_work = TRUE)
phase149_audit_dir <- resolve_path(
  arg_value("phase149_audit_dir"),
  default = file.path(phase149_dir, "phase149_result_audit"),
  must_work = TRUE
)

result <- app_joint_exqdesn_run_phase150_mcmc_freeze(
  out_dir = resolve_path(arg_value("output_dir"), must_work = FALSE),
  phase149_dir = phase149_dir,
  readiness_dir = resolve_path(arg_value("readiness_dir"), must_work = TRUE),
  phase149_audit_dir = phase149_audit_dir,
  mcmc_dir = resolve_path(arg_value("mcmc_dir"), must_work = FALSE),
  fixture_dir = resolve_path(arg_value("fixture_dir"), must_work = TRUE),
  n_chains = parse_integer(arg_value("n_chains")),
  mcmc_n_iter = parse_integer(arg_value("mcmc_n_iter")),
  mcmc_burn = parse_integer(arg_value("mcmc_burn")),
  mcmc_thin = parse_integer(arg_value("mcmc_thin")),
  mcmc_seed_offset = parse_integer(arg_value("mcmc_seed_offset")),
  chain_seed_stride = parse_integer(arg_value("chain_seed_stride")),
  sigma_upper_multiplier = parse_number(arg_value("sigma_upper_multiplier")),
  distance_pass = parse_number(arg_value("distance_pass")),
  chain_pass = parse_number(arg_value("chain_pass")),
  n_cores = parse_integer(arg_value("n_cores"))
)

cat(sprintf("Phase150 case-specific MCMC freeze written to %s\n", result$out_dir))
cat(sprintf("Gate status: %s\n", result$assessment$gate_status[[1L]]))
cat(sprintf("Selected cases: %s\n", result$assessment$n_cases[[1L]]))
cat("Selected scenarios:\n")
print(result$controls[, c("scenario_ids", "phase149_role", "tau0", "zeta2", "alpha_prior_sd", "gamma_init_policy", "selected_forecast_truth_mae")], row.names = FALSE)
cat("Launch plan:\n")
print(result$launch_plan[, c("launch_status", "n_cases", "n_chains", "mcmc_n_iter", "mcmc_burn", "mcmc_thin", "n_cores")], row.names = FALSE)
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
