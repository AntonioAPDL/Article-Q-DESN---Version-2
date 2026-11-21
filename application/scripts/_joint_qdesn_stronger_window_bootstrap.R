#!/usr/bin/env Rscript

root <- if (dir.exists(file.path(getwd(), "application", "scripts"))) {
  normalizePath(getwd())
} else if (exists("repo_root", inherits = TRUE) &&
    dir.exists(file.path(get("repo_root", inherits = TRUE), "application", "scripts"))) {
  normalizePath(get("repo_root", inherits = TRUE))
} else {
  stop("Run the stronger-window bootstrap from the repository root.", call. = FALSE)
}
source(file.path(root, "application", "scripts", "_joint_qdesn_pure_recursive_bootstrap.R"))
