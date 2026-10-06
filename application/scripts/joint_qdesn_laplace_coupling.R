#!/usr/bin/env Rscript
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
source(file.path(dirname(script), "_joint_qdesn_laplace_coupling_bootstrap.R"))
stopifnot(getRversion() == "4.6.0")
args <- commandArgs(TRUE)
if (length(args) < 2L) stop("Usage: SCRIPT ACTION ROOT [STAGE] [ID or KIND] [WORKER_ACTION]")
action <- args[[1L]]; root <- normalizePath(args[[2L]], mustWork = FALSE)
folder_for <- function(stage, action, id) {
  kind <- switch(action, dataset = "datasets", calibrate = "calibrations", warmup = "warmups", chain = "chains", score = "scores")
  width <- switch(action, dataset = 2L, calibrate = 2L, warmup = 3L, chain = 4L, score = 4L)
  prefix <- if (action %in% c("dataset", "calibrate")) "dataset_" else if (action == "score") "cell_" else "worker_"
  file.path(root, stage, kind, sprintf(paste0(prefix, "%0", width, "d"), id))
}
if (action == "prepare") {
  app_joint_prior_prepare(root)
} else if (action == "select") {
  app_joint_prior_select(root)
} else if (action == "finalize") {
  app_joint_prior_finalize(root)
} else if (action == "ids") {
  stage <- args[[3L]]; kind <- args[[4L]]
  worker_action <- if (length(args) >= 5L) args[[5L]] else switch(kind, datasets = "dataset", warmups = "warmup", chains = "chain", cells = "score")
  plan <- app_read_csv(file.path(root, stage, paste0(kind, ".csv")))
  key <- switch(kind, datasets = "dataset_id", warmups = "worker_id", chains = "worker_id", cells = "cell_id")
  ids <- plan[[key]]
  pending <- !vapply(ids, function(id) app_joint_prior_done(folder_for(stage, worker_action, id)), logical(1L))
  if (any(pending)) cat(ids[pending], sep = "\n")
} else if (action == "health") {
  rows <- list()
  for (stage in c("screen", "confirmation")) for (kind in c("datasets", "calibrations", "warmups", "chains", "cells")) {
    plan_path <- file.path(root, stage, paste0(if (kind == "calibrations") "datasets" else kind, ".csv"))
    if (!file.exists(plan_path)) next
    plan <- app_read_csv(plan_path)
    a <- switch(kind, datasets = "dataset", calibrations = "calibrate", warmups = "warmup", chains = "chain", cells = "score")
    dirs <- vapply(seq_len(nrow(plan)), function(id) folder_for(stage, a, id), character(1L))
    done <- vapply(dirs, app_joint_prior_done, logical(1L)); failed <- file.exists(file.path(dirs, "FAILED")) & !done
    running <- file.exists(file.path(dirs, "RUNNING")) & !done & !failed
    rows[[length(rows) + 1L]] <- data.frame(stage = stage, kind = kind, expected = nrow(plan),
      complete = sum(done), failed = sum(failed), running = sum(running), left = sum(!done))
  }
  print(do.call(rbind, rows), row.names = FALSE)
  cat("Final closeout:", file.exists(file.path(root, "COMPLETE")), "\n")
} else {
  stopifnot(action %in% c("dataset", "calibrate", "warmup", "chain", "score"), length(args) == 4L)
  stage <- args[[3L]]; id <- as.integer(args[[4L]])
  stopifnot(stage %in% c("screen", "confirmation"), length(id) == 1L, is.finite(id), id > 0)
  folder <- folder_for(stage, action, id)
  if (app_joint_prior_done(folder)) quit(status = 0)
  app_joint_prior_verify_freeze(root)
  checked <- app_joint_shared_verify_manifest(file.path(root, stage), file.path(root, stage, "plan_manifest.csv"))
  stopifnot(all(checked$verified))
  if (stage == "confirmation") app_joint_prior_verify_selection(root)
  app_ensure_dir(folder)
  writeLines(paste(Sys.getpid(), format(Sys.time(), tz = "UTC", usetz = TRUE)), file.path(folder, "RUNNING"))
  success <- tryCatch({
    fun <- switch(action, dataset = app_joint_prior_dataset, calibrate = app_joint_coupling_calibrate,
      warmup = app_joint_prior_warmup, chain = app_joint_prior_chain, score = app_joint_prior_score)
    fun(root, stage, id); TRUE
  }, error = function(e) {
    writeLines(conditionMessage(e), file.path(folder, "FAILED")); message(conditionMessage(e)); FALSE
  })
  unlink(file.path(folder, "RUNNING"))
  if (success) unlink(file.path(folder, "FAILED"))
  quit(status = if (success) 0 else 1)
}
