#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))

dirs <- app_joint_exqdesn_phase176_dirs()
health <- app_joint_exqdesn_phase178_m0_health(
  dirs$phase178_m0_freeze, dirs$phase178_m0_orchestration,
  "phase178_post_m0_exact_ranking_freeze"
)
print(health$summary, row.names = FALSE); print(health$by_case, row.names = FALSE)
if (health$summary$failed[[1L]] == 0L && health$summary$remaining[[1L]] == 0L) {
  result <- app_joint_exqdesn_phase178_finalize_m0_ranking()
  print(result$assessment, row.names = FALSE)
}
