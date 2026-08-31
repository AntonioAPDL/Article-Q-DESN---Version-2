#!/usr/bin/env Rscript

source(file.path(dirname(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L])), "_joint_qdesn_phase180_balanced_score_bootstrap.R"))

cache_root <- app_joint_qdesn_phase180_arg(
  "--cache-root", app_joint_exqdesn_phase164_cache_root()
)
result <- app_joint_qdesn_phase180_stage_article_assets(
  cache_root = cache_root,
  packet_dir = app_joint_qdesn_phase180_arg("--packet-dir", NULL),
  out_dir = app_joint_qdesn_phase180_arg("--output-dir", NULL),
  force = "--force" %in% commandArgs(trailingOnly = TRUE)
)
cat(sprintf("Phase180 article staging: %s\nRows: %d\n", result$out_dir,
            nrow(result$table)))
