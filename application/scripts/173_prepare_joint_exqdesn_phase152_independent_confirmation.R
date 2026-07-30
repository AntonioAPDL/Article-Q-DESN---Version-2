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
  output_dir = app_joint_exqdesn_phase152_default_readiness_dir(),
  fixture_dir = app_joint_exqdesn_phase152_default_fixture_dir(),
  phase151_dir = app_joint_exqdesn_phase152_default_phase151_dir(),
  phase151_readiness_dir = app_joint_exqdesn_phase152_default_phase151_readiness_dir(),
  registry = app_joint_qdesn_default_simulation_registry_path(),
  n_dgp_replicates = "10",
  n_reservoir_replicates = "3",
  n_chains = "8"
))
value <- function(hyphen, underscore) args[[hyphen]] %||% args[[underscore]]

result <- app_joint_exqdesn_run_phase152_readiness(
  out_dir = value("output-dir", "output_dir"),
  fixture_dir = value("fixture-dir", "fixture_dir"),
  phase151_dir = value("phase151-dir", "phase151_dir"),
  phase151_readiness_dir = value(
    "phase151-readiness-dir", "phase151_readiness_dir"
  ),
  base_registry_path = value("registry", "registry"),
  n_dgp_replicates = as.integer(value("n-dgp-replicates", "n_dgp_replicates")),
  n_reservoir_replicates = as.integer(value(
    "n-reservoir-replicates", "n_reservoir_replicates"
  )),
  n_chains = as.integer(value("n-chains", "n_chains"))
)
cat(sprintf("Phase152 readiness written to %s\n", result$out_dir))
print(result$assessment)
if (result$assessment$gate_status[[1L]] == "fail") quit(status = 1L)
