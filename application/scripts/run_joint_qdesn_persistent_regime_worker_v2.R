#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_pr2_default_root(), stage = "parity", worker_id = NA_integer_))
id <- as.integer(args[["worker-id"]] %||% args$worker_id)
if (is.na(id)) stop("--worker-id is required.", call. = FALSE)
app_joint_pr2_run_worker(args$root, args$stage, id)
