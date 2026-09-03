#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/scripts/_joint_qdesn_phase181_diagnostic_atlas_bootstrap.R"))

config <- app_joint_qdesn_atlas_arg(
  "--config", app_path("application/config/joint_qdesn_phase181_diagnostic_atlas_v1.csv")
)
source_root <- app_joint_qdesn_atlas_arg(
  "--source-root",
  Sys.getenv("JOINT_QDESN_PHASE181_SOURCE_ROOT",
             "/data/jaguir26/local/src/Article-Q-DESN---Version-2")
)
output_dir <- app_joint_qdesn_atlas_arg(
  "--output-dir",
  app_path("local_trackers/joint_qdesn_phase181_diagnostic_atlas_20260831")
)
cores <- as.integer(app_joint_qdesn_atlas_arg("--cores", "2"))
result <- app_joint_qdesn_atlas_prepare(
  config, source_root, output_dir, cores = cores,
  force = app_joint_qdesn_atlas_flag("--force")
)
cat(sprintf("output_dir=%s reused=%s\n", result$output_dir, result$reused))
