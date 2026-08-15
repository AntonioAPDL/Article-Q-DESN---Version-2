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
  output_dir = app_joint_qdesn_phase154_default_final_dir(),
  readiness_dir = app_joint_qdesn_phase154_default_readiness_dir(),
  joint_al_dir = app_joint_qdesn_phase154_default_joint_al_dir(),
  independent_al_dir = app_joint_qdesn_phase154_default_independent_al_dir(),
  independent_exal_dir =
    app_joint_qdesn_phase154_default_independent_exal_dir(),
  phase150_dir = app_joint_qdesn_phase154_default_phase150_dir()
))
value <- function(hyphen, underscore) args[[hyphen]] %||% args[[underscore]]

result <- app_joint_qdesn_phase154_finalize(
  out_dir = value("output-dir", "output_dir"),
  readiness_dir = value("readiness-dir", "readiness_dir"),
  joint_al_dir = value("joint-al-dir", "joint_al_dir"),
  independent_al_dir = value("independent-al-dir", "independent_al_dir"),
  independent_exal_dir = value(
    "independent-exal-dir", "independent_exal_dir"
  ),
  phase150_dir = value("phase150-dir", "phase150_dir")
)
cat(sprintf("Phase154 final balanced MCMC audit written to %s\n", result$out_dir))
print(result$assessment)
print(result$model_summary)
if (result$assessment$gate_status[[1L]] == "fail") quit(status = 1L)
