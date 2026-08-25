#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))

cache_root <- app_joint_exqdesn_phase176_180_arg(
  "--cache-root", app_joint_exqdesn_phase164_cache_root()
)
out_dir <- app_joint_exqdesn_phase176_180_arg(
  "--output-dir", app_joint_qdesn_phase179_dirs(cache_root)$closeout
)
result <- app_joint_qdesn_phase179_freeze_closeout(
  cache_root = cache_root,
  out_dir = out_dir,
  force = "--force" %in% commandArgs(trailingOnly = TRUE)
)
print(result$assessment, row.names = FALSE)
cat(sprintf(
  "Phase179 closeout: %s\nReused verified packet: %s\n",
  result$out_dir, result$reused
))
