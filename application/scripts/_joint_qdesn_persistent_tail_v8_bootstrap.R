#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application", "R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application", "scripts",
  "_joint_qdesn_persistent_tail_v7_bootstrap.R"))
source(file.path(repo_root, "application", "R", "joint_qdesn_fixed_backbone_prior_screen.R"))
source(file.path(repo_root, "application", "R",
  "joint_qdesn_persistent_tail_v8_joint_prior.R"))
