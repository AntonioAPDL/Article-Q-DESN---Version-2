#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_pure_default_root(), stage = "ridge", worker_id = NA_integer_))
worker_id <- as.integer(args[["worker-id"]] %||% args$worker_id)
if (is.na(worker_id)) stop("--worker-id is required.", call. = FALSE)
app_joint_pure_run_worker(args$root, args$stage, worker_id)
