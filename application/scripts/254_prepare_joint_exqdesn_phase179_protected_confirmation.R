#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))

result <- app_joint_exqdesn_phase179_prepare_protected_confirmation(
  n_vb_cores = as.integer(app_joint_exqdesn_phase176_180_arg("--vb-cores", "8")),
  force = "--force" %in% commandArgs(trailingOnly = TRUE)
)
cat(sprintf("Phase179 protected freeze: %s\nWorkers: %d\n", result$out_dir, nrow(result$plan)))
