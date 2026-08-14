#!/usr/bin/env Rscript
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)
for (file in c(
  "input_contract.R",
  "synthesize_quantiles.R",
  "score_forecasts.R",
  "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R",
  "joint_qdesn_simulation_validation.R",
  "joint_qdesn_vb_spec_screening.R",
  "joint_exqdesn_phase162_scenario_classification.R",
  "joint_exqdesn_phase163b_corrected_closure.R"
)) source(app_path("application/R", file))

result <- app_joint_exqdesn_phase163b_run()
print(result$assessment, row.names = FALSE)
