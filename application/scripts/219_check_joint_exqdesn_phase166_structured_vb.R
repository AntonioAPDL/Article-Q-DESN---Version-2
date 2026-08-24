#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)
for (file in c(
  "input_contract.R", "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_exqdesn_phase164_165_readiness.R", "joint_exqdesn_phase166_168_structured_vb.R"
)) source(app_path("application/R", file))
dirs <- app_joint_exqdesn_phase164_dirs()
health <- app_joint_exqdesn_phase166_health(dirs)
print(health, row.names = FALSE)
assessment_path <- file.path(dirs$phase166, "phase166_assessment.csv")
if (file.exists(assessment_path)) {
  cat("\nFinal assessment:\n")
  print(app_read_csv(assessment_path), row.names = FALSE)
}
