#!/usr/bin/env Rscript

root <- if (dir.exists(file.path(getwd(), "application", "scripts"))) {
  normalizePath(getwd())
} else if (exists("repo_root", inherits = TRUE) &&
    dir.exists(file.path(get("repo_root", inherits = TRUE), "application", "scripts"))) {
  normalizePath(get("repo_root", inherits = TRUE))
} else {
  stop("Run the persistent-tail v3 bootstrap from the repository root.", call. = FALSE)
}
source(file.path(root, "application", "scripts", "_joint_qdesn_persistent_tail_targeted_bootstrap.R"))
source(file.path(root, "application", "R", "rhs_global_scale_reference.R"))
source(file.path(root, "application", "R", "joint_qdesn_persistent_tail_exploration_v3.R"))
