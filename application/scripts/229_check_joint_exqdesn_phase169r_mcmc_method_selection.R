#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)

for (file in c(
  "input_contract.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R",
  "joint_exqdesn_phase164_165_readiness.R",
  "joint_exqdesn_phase167_169_mcmc_method_selection.R",
  "joint_exqdesn_phase169r_recovery.R"
)) source(app_path("application/R", file))

dirs <- app_joint_exqdesn_phase169r_dirs()
readiness_path <- file.path(dirs$phase169r_freeze, "readiness_assessment.csv")
if (!file.exists(readiness_path)) {
  cat("Phase169R has not been prepared.\n")
  quit(status = 0L)
}
health <- app_joint_exqdesn_phase169_health(dirs$phase169r_freeze)
print(health, row.names = FALSE)
failures <- list.files(
  file.path(dirs$phase169r_orchestration, "failures"),
  pattern = "[.]csv$", full.names = TRUE
)
checkpoints <- vapply(
  app_joint_exqdesn_phase169_load_freeze(dirs$phase169r_freeze)$plan$worker_output_dir,
  app_joint_exqdesn_phase169_checkpoint_complete,
  logical(1L)
)
cat(sprintf("\nVerified checkpoints: %d\n", sum(checkpoints)))
cat(sprintf("Failure receipts: %d\n", length(failures)))
assessment_path <- file.path(dirs$phase169r, "phase169_assessment.csv")
if (file.exists(assessment_path)) {
  cat("\nFinal assessment:\n")
  print(app_read_csv(assessment_path), row.names = FALSE)
}
