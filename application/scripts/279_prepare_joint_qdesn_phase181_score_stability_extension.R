#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(
  root, "application/scripts/_joint_qdesn_phase181_score_stability_bootstrap.R"
))

cache_root <- app_joint_qdesn_phase181_arg(
  "--cache-root", app_joint_exqdesn_phase164_cache_root()
)
vb_cores <- as.integer(app_joint_qdesn_phase181_arg("--vb-cores", "8"))
result <- app_joint_qdesn_phase181_prepare(
  cache_root = cache_root,
  n_vb_cores = vb_cores,
  force = app_joint_qdesn_phase181_flag("--force")
)
print(result$readiness, row.names = FALSE)
cat(sprintf("Phase181 freeze: %s\n", result$out_dir))
