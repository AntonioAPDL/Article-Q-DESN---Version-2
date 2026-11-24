#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application/scripts",
  "_joint_qdesn_persistent_tail_exploration_v3_bootstrap.R"))
args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) args[[1L]] else app_joint_pht3_default_root()
print(app_joint_pht3_prepare(root))
