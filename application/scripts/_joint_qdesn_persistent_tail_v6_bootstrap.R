#!/usr/bin/env Rscript

root <- if (dir.exists(file.path(getwd(), "application", "scripts"))) normalizePath(getwd()) else
  if (exists("repo_root", inherits = TRUE)) normalizePath(get("repo_root", inherits = TRUE)) else
    stop("Run the V6 bootstrap from the repository root.", call. = FALSE)
source(file.path(root, "application", "scripts", "_joint_qdesn_persistent_tail_sealed_v5_bootstrap.R"))
source(file.path(root, "application", "R", "joint_qdesn_persistent_tail_v6.R"))
