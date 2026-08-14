#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))

health <- app_joint_exqdesn_phase178_vb_health()
print(health, row.names = FALSE)
if (health$remaining[[1L]] == 0L) {
  result <- app_joint_exqdesn_phase178_finalize_vb()
  print(result$assessment, row.names = FALSE)
}
