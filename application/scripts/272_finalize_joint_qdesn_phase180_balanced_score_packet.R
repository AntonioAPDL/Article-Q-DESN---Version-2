#!/usr/bin/env Rscript

source(file.path(dirname(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L])), "_joint_qdesn_phase180_balanced_score_bootstrap.R"))

cache_root <- app_joint_qdesn_phase180_arg(
  "--cache-root", app_joint_exqdesn_phase164_cache_root()
)
result <- app_joint_qdesn_phase180_finalize(
  cache_root = cache_root,
  freeze_dir = app_joint_qdesn_phase180_arg("--freeze-dir", NULL),
  out_dir = app_joint_qdesn_phase180_arg("--output-dir", NULL),
  score_cores = as.integer(app_joint_qdesn_phase180_arg("--score-cores", "8")),
  force = "--force" %in% commandArgs(trailingOnly = TRUE)
)
print(result$assessment, row.names = FALSE)
cat(sprintf("Phase180 score packet: %s\n", result$out_dir))
