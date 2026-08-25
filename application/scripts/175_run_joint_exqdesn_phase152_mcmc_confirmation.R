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
  output_dir = app_joint_exqdesn_phase152_default_mcmc_dir(),
  vb_dir = app_joint_exqdesn_phase152_default_vb_dir(),
  readiness_dir = app_joint_exqdesn_phase152_default_readiness_dir(),
  fixture_dir = app_joint_exqdesn_phase151_default_fixture_dir(),
  phase150_dir = app_joint_exqdesn_phase150_default_mcmc_dir(),
  n_chains = "8",
  mcmc_n_iter = "8000",
  mcmc_burn = "2000",
  mcmc_thin = "4",
  n_cores = "16",
  sigma_upper_multiplier = "50"
))
value <- function(hyphen, underscore) args[[hyphen]] %||% args[[underscore]]

result <- app_joint_exqdesn_run_phase152_mcmc(
  out_dir = value("output-dir", "output_dir"),
  vb_dir = value("vb-dir", "vb_dir"),
  readiness_dir = value("readiness-dir", "readiness_dir"),
  fixture_dir = value("fixture-dir", "fixture_dir"),
  phase150_dir = value("phase150-dir", "phase150_dir"),
  n_chains = as.integer(value("n-chains", "n_chains")),
  mcmc_n_iter = as.integer(value("mcmc-n-iter", "mcmc_n_iter")),
  mcmc_burn = as.integer(value("mcmc-burn", "mcmc_burn")),
  mcmc_thin = as.integer(value("mcmc-thin", "mcmc_thin")),
  n_cores = as.integer(value("n-cores", "n_cores")),
  sigma_upper_multiplier = as.numeric(value(
    "sigma-upper-multiplier", "sigma_upper_multiplier"
  ))
)
cat(sprintf("Phase152 MCMC artifacts written to %s\n", result$out_dir))
print(result$assessment)
if (!is.null(result$case_assessment)) print(result$case_assessment)
if (result$assessment$gate_status[[1L]] == "fail") quit(status = 1L)
