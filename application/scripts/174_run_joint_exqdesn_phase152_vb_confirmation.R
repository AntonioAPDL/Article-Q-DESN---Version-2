#!/usr/bin/env Rscript

script_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
repo_root <- normalizePath(file.path(dirname(normalizePath(script_arg)), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_vb_spec_screening.R", "joint_qdesn_mcmc_readiness.R",
  "joint_exqdesn_trace_tools.R",
  "joint_exqdesn_phase149_case_specific_screening.R",
  "joint_exqdesn_phase150_case_specific_mcmc_confirmation.R",
  "latent_path_design.R", "joint_exqdesn_phase151_feature_design_screening.R",
  "joint_exqdesn_phase152_independent_confirmation.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  output_dir = app_joint_exqdesn_phase152_default_vb_dir(),
  readiness_dir = app_joint_exqdesn_phase152_default_readiness_dir(),
  fixture_dir = app_joint_exqdesn_phase152_default_fixture_dir(),
  n_cores = "16",
  incomplete_only = "true"
))
value <- function(hyphen, underscore) args[[hyphen]] %||% args[[underscore]]

result <- app_joint_exqdesn_run_phase152_vb(
  out_dir = value("output-dir", "output_dir"),
  readiness_dir = value("readiness-dir", "readiness_dir"),
  fixture_dir = value("fixture-dir", "fixture_dir"),
  n_cores = as.integer(value("n-cores", "n_cores")),
  incomplete_only = app_as_bool(value("incomplete-only", "incomplete_only"))
)
cat(sprintf("Phase152 VB artifacts written to %s\n", result$out_dir))
print(result$assessment)
print(result$decision[, c(
  "base_scenario_id", "promotion_status", "dgp_forecast_mae_wins",
  "median_relative_forecast_mae_gain", "reservoir_seed_win_fraction"
)])
if (result$assessment$gate_status[[1L]] == "fail") quit(status = 1L)
