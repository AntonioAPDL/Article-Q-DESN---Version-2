#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))

cache_root <- app_joint_exqdesn_phase176_180_arg(
  "--cache-root", app_path("application/cache")
)
output_dir <- app_joint_exqdesn_phase176_180_arg("--output-dir", NULL)
result <- app_joint_qdesn_postscore_freeze_contract(
  cache_root = cache_root,
  out_dir = output_dir,
  force = "--force" %in% commandArgs(trailingOnly = TRUE)
)
cat(sprintf("Post-Phase178 score contract: %s\n", result$out_dir))
