#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(
  root, "application/scripts/_joint_qdesn_phase181_score_stability_bootstrap.R"
))

cache_root <- app_joint_qdesn_phase181_arg(
  "--cache-root", app_joint_exqdesn_phase164_cache_root()
)
result <- app_joint_qdesn_phase181_stage_article_assets(
  cache_root = cache_root,
  force = app_joint_qdesn_phase181_flag("--force")
)
cat(sprintf("Phase181 article staging: %s\n", result$out_dir))
cat(sprintf("Scenario-model rows: %d\n", nrow(result$table)))
