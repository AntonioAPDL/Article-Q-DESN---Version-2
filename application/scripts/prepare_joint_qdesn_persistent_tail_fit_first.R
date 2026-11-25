#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application/scripts",
  "_joint_qdesn_persistent_tail_fit_first_bootstrap.R"))
args <- commandArgs(trailingOnly = TRUE)
if (!length(args) || length(args) > 2L) {
  stop("Usage: prepare.R SOURCE_V3_ROOT [OUTPUT_ROOT]", call. = FALSE)
}
root <- if (length(args) == 2L) args[[2L]] else app_joint_phtff_default_root()
print(app_joint_phtff_prepare(args[[1L]], root))
