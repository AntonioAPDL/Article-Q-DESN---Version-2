#!/usr/bin/env Rscript

source(file.path(dirname(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L])), "_joint_qdesn_phase180_balanced_score_bootstrap.R"))

cache_root <- app_joint_qdesn_phase180_arg(
  "--cache-root", app_joint_exqdesn_phase164_cache_root()
)
result <- app_joint_qdesn_phase180_freeze_handoff(
  cache_root = cache_root,
  out_dir = app_joint_qdesn_phase180_arg("--output-dir", NULL),
  force = "--force" %in% commandArgs(trailingOnly = TRUE)
)
print(result$readiness, row.names = FALSE)
cat(sprintf("Phase180 handoff: %s\n", result$out_dir))
