#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(
  root, "application/scripts/_joint_qdesn_phase182_dense_grid_crossing_bootstrap.R"
))

cache_root <- app_joint_qdesn_phase182_arg(
  "--cache-root", app_joint_qdesn_phase182_cache_root()
)
source_cache_root <- app_joint_qdesn_phase182_arg(
  "--source-cache-root", app_joint_qdesn_phase182_source_cache_root()
)
vb_cores <- as.integer(app_joint_qdesn_phase182_arg("--vb-cores", "8"))
result <- app_joint_qdesn_phase182_prepare(
  cache_root = cache_root,
  source_cache_root = source_cache_root,
  n_vb_cores = vb_cores,
  force = app_joint_qdesn_phase182_flag("--force")
)
print(result$readiness, row.names = FALSE)
cat(sprintf("Phase182 freeze: %s\n", result$out_dir))
