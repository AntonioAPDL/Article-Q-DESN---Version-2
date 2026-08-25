#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)

for (file in c(
  "input_contract.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R",
  "joint_exqdesn_phase164_165_readiness.R",
  "joint_exqdesn_phase167_169_mcmc_method_selection.R"
)) source(app_path("application/R", file))

dirs <- app_joint_exqdesn_phase167_169_dirs()
freeze_path <- file.path(dirs$phase169_freeze, "readiness_assessment.csv")
if (!file.exists(freeze_path)) {
  cat("Phase169 has not been prepared.\n")
  quit(status = 0L)
}
health <- app_joint_exqdesn_phase169_health(dirs$phase169_freeze)
print(health, row.names = FALSE)

failures <- list.files(
  file.path(dirs$phase169_orchestration, "failures"),
  pattern = "[.]csv$", full.names = TRUE
)
cat(sprintf("\nFailure receipts: %d\n", length(failures)))
assessment_path <- file.path(dirs$phase169, "phase169_assessment.csv")
if (file.exists(assessment_path)) {
  cat("\nFinal assessment:\n")
  print(app_read_csv(assessment_path), row.names = FALSE)
}
