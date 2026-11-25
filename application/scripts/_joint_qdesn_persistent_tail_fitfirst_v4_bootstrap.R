#!/usr/bin/env Rscript

root <- if (dir.exists(file.path(getwd(), "application", "scripts"))) {
  normalizePath(getwd())
} else if (exists("repo_root", inherits = TRUE) &&
    dir.exists(file.path(get("repo_root", inherits = TRUE), "application", "scripts"))) {
  normalizePath(get("repo_root", inherits = TRUE))
} else {
  stop("Run the persistent-tail V4 bootstrap from the repository root.", call. = FALSE)
}
source(file.path(root, "application", "scripts",
  "_joint_qdesn_persistent_tail_fit_first_bootstrap.R"))
source(file.path(root, "application", "R", "joint_qdesn_dgp_integrated_acrps.R"))
source(file.path(root, "application", "R", "joint_qdesn_persistent_tail_fitfirst_v4.R"))
