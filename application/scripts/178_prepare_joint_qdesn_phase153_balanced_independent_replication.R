#!/usr/bin/env Rscript

script_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
repo_root <- normalizePath(file.path(dirname(normalizePath(script_arg)), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_phase153_balanced_independent_replication.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  output_dir = app_joint_qdesn_phase153_default_readiness_dir(),
  fixture_dir = app_joint_qdesn_phase153_default_fixture_dir(),
  registry = app_joint_qdesn_default_simulation_registry_path(),
  phase121_dir = app_joint_qdesn_phase153_default_phase121_dir(),
  phase124b_dir = app_joint_qdesn_phase153_default_phase124b_dir(),
  phase125_dir = app_joint_qdesn_phase153_default_phase125_dir(),
  phase150_freeze_dir = app_joint_qdesn_phase153_default_phase150_freeze_dir(),
  phase150_mcmc_dir = app_joint_qdesn_phase153_default_phase150_mcmc_dir(),
  phase152_readiness_dir = app_joint_qdesn_phase153_default_phase152_readiness_dir(),
  n_dgp_replicates = "50",
  seed_base = "153000000",
  materialize_fixtures = "true"
))
value <- function(hyphen, underscore) args[[hyphen]] %||% args[[underscore]]

result <- app_joint_qdesn_run_phase153_readiness(
  out_dir = value("output-dir", "output_dir"),
  fixture_dir = value("fixture-dir", "fixture_dir"),
  base_registry_path = value("registry", "registry"),
  phase121_dir = value("phase121-dir", "phase121_dir"),
  phase124b_dir = value("phase124b-dir", "phase124b_dir"),
  phase125_dir = value("phase125-dir", "phase125_dir"),
  phase150_freeze_dir = value("phase150-freeze-dir", "phase150_freeze_dir"),
  phase150_mcmc_dir = value("phase150-mcmc-dir", "phase150_mcmc_dir"),
  phase152_readiness_dir = value(
    "phase152-readiness-dir", "phase152_readiness_dir"
  ),
  n_dgp_replicates = as.integer(value(
    "n-dgp-replicates", "n_dgp_replicates"
  )),
  seed_base = as.integer(value("seed-base", "seed_base")),
  materialize_fixtures = app_as_bool(value(
    "materialize-fixtures", "materialize_fixtures"
  ))
)
cat(sprintf("Phase153 readiness written to %s\n", result$out_dir))
cat(sprintf("Phase153 fixtures written to %s\n", result$fixture_dir))
print(result$assessment)
if (result$assessment$gate_status[[1L]] == "fail") quit(status = 1L)
