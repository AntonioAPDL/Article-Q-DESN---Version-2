#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_pure_default_root(), stage_order = NA_integer_))
stage_order <- as.integer(args[["stage-order"]] %||% args$stage_order)
if (is.na(stage_order)) stop("--stage-order is required.", call. = FALSE)
queue <- app_joint_pure_quantile_job_queue(args$root, stage_order)
utils::write.table(queue, file = stdout(), sep = "\t", quote = FALSE,
  row.names = FALSE, col.names = FALSE)
