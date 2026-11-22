#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_stronger_window_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_sw_default_root(), stage = "m1", worker_id = NA_integer_))
worker_id <- as.integer(args[["worker-id"]] %||% args$worker_id)
if (!is.finite(worker_id)) stop("--worker-id is required.", call. = FALSE)
app_joint_swq_run_worker(args$root, args$stage, worker_id)
