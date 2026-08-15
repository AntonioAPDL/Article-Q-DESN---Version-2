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

args <- commandArgs(trailingOnly = TRUE)
value_after <- function(flag, default = NULL) {
  idx <- match(flag, args)
  if (is.na(idx) || idx == length(args)) default else args[[idx + 1L]]
}
dirs <- app_joint_exqdesn_phase163b_dirs()
dirs$phase150 <- value_after("--phase150-dir", dirs$phase150)
dirs$phase163_readiness <- value_after("--phase163-readiness-dir", dirs$phase163_readiness)
dirs$phase163 <- value_after("--phase163-dir", dirs$phase163)
dirs$output <- value_after("--output-dir", dirs$output)

result <- app_joint_exqdesn_phase163b_run(dirs)
print(result$assessment, row.names = FALSE)
