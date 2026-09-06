#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))), "_joint_qdesn_shared_backbone_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_shared_default_root(), worker_id = NA_integer_))
root <- args$root %||% args[["output-dir"]]
worker_id <- as.integer(args[["worker-id"]] %||% args$worker_id)
if (!is.finite(worker_id)) stop("--worker-id is required.", call. = FALSE)
app_joint_shared_run_ridge_worker(root, worker_id)
