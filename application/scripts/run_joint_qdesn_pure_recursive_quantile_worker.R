#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(root = NA_character_, job_id = NA_integer_))
if (is.na(args$root) || is.na(as.integer(args[["job-id"]] %||% args$job_id))) stop("--root and --job-id are required.", call. = FALSE)
app_joint_shared_quantile_run_worker(args$root, as.integer(args[["job-id"]] %||% args$job_id))
