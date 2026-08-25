#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))

cache_root <- app_joint_exqdesn_phase176_180_arg(
  "--cache-root", app_joint_exqdesn_phase164_cache_root()
)
force <- "--force" %in% commandArgs(trailingOnly = TRUE)
selection <- app_joint_qdesn_phase179_prepare_selection_freeze(
  cache_root = cache_root, force = force
)
confirmation <- app_joint_qdesn_phase179_prepare_confirmation(
  cache_root = cache_root,
  n_vb_cores = as.integer(app_joint_exqdesn_phase176_180_arg("--vb-cores", "12")),
  force = force
)
cat(sprintf(
  paste0(
    "Phase179 selection freeze: %s\n",
    "Case-specific templates: %d\n",
    "Phase179 confirmation freeze: %s\n",
    "Workers: %d\n"
  ),
  selection$out_dir, nrow(selection$templates),
  confirmation$out_dir, nrow(confirmation$plan)
))
