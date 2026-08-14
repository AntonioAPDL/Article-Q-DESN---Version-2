#!/usr/bin/env Rscript

script_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
repo_root <- normalizePath(file.path(dirname(normalizePath(script_arg)), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R",
  "joint_qdesn_phase153_balanced_independent_replication.R",
  "joint_qdesn_phase154_mcmc_evidence_reconciliation.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  orchestration_dir = app_joint_qdesn_phase154_default_orchestration_dir(),
  final_dir = app_joint_qdesn_phase154_default_final_dir()
))
value <- function(hyphen, underscore) args[[hyphen]] %||% args[[underscore]]

health <- app_joint_qdesn_phase154_health(
  orchestration_dir = value("orchestration-dir", "orchestration_dir"),
  final_dir = value("final-dir", "final_dir")
)
print(health$summary)
print(health$blocks)
if (health$summary$lifecycle_state[[1L]] == "failed") quit(status = 2L)
