#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(
  root, "application/scripts/_joint_qdesn_phase181_score_stability_bootstrap.R"
))

cache_root <- app_joint_qdesn_phase181_arg(
  "--cache-root", app_joint_exqdesn_phase164_cache_root()
)
score_cores <- as.integer(app_joint_qdesn_phase181_arg("--score-cores", "8"))
result <- app_joint_qdesn_phase181_finalize(
  cache_root = cache_root, score_cores = score_cores,
  force = app_joint_qdesn_phase181_flag("--force")
)
print(result$assessment, row.names = FALSE)
cat(sprintf("Phase181 packet: %s\n", result$out_dir))
