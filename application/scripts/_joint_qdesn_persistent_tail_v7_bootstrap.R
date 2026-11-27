#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application", "R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application", "scripts",
  "_joint_qdesn_persistent_tail_v6_bootstrap.R"))
source(file.path(repo_root, "application", "R", "joint_qdesn_stronger_window_confirmation.R"))
source(file.path(repo_root, "application", "R", "joint_qdesn_stronger_window_score.R"))
source(file.path(repo_root, "application", "R", "joint_qdesn_persistent_tail_v7_confirmation.R"))
