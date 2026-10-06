#!/usr/bin/env Rscript
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
source(file.path(dirname(script), "_joint_qdesn_fixed_backbone_prior_bootstrap.R"))
args <- commandArgs(TRUE)
if (length(args) < 2L) stop("Usage: SCRIPT ACTION ROOT [STAGE] [WORKER_ID]")
action <- args[[1L]]; root <- normalizePath(args[[2L]], mustWork = FALSE)
if (action == "prepare") {
  app_joint_prior_prepare(root)
} else if (action == "select") {
  app_joint_prior_select(root)
} else if (action == "finalize") {
  app_joint_prior_finalize(root)
} else if (action == "ids") {
  stage <- args[[3L]]; kind <- args[[4L]]
  plan <- app_read_csv(file.path(root, stage, paste0(kind, ".csv")))
  key <- switch(kind, datasets = "dataset_id", warmups = "worker_id", chains = "worker_id", cells = "cell_id")
  cat(plan[[key]], sep = "\n")
} else if (action == "health") {
  rows <- list()
  for (stage in c("screen", "confirmation")) for (kind in c("datasets", "warmups", "chains", "cells")) {
    plan_path <- file.path(root, stage, paste0(kind, ".csv"))
    if (!file.exists(plan_path)) next
    plan <- app_read_csv(plan_path)
    prefix <- switch(kind, datasets = "dataset_", warmups = "worker_", chains = "worker_", cells = "cell_")
    width <- switch(kind, datasets = 2L, warmups = 3L, chains = 4L, cells = 4L)
    folder_kind <- if (kind == "cells") "scores" else kind
    folders <- file.path(root, stage, folder_kind, sprintf(paste0(prefix, "%0", width, "d"), seq_len(nrow(plan))))
    done <- vapply(folders, app_joint_prior_done, logical(1L))
    failed <- file.exists(file.path(folders, "FAILED")) & !done
    running <- file.exists(file.path(folders, "RUNNING")) & !done & !failed
    rows[[length(rows) + 1L]] <- data.frame(stage = stage, kind = kind, expected = nrow(plan),
      complete = sum(done), failed = sum(failed), running = sum(running), left = sum(!done))
  }
  print(do.call(rbind, rows), row.names = FALSE)
  cat("Final closeout:", file.exists(file.path(root, "COMPLETE")), "\n")
} else {
  stopifnot(action %in% c("dataset", "warmup", "chain", "score"))
  stage <- args[[3L]]; id <- as.integer(args[[4L]])
  stopifnot(stage %in% c("screen", "confirmation"), length(id) == 1L, is.finite(id), id > 0)
  kind <- switch(action, dataset = "datasets", warmup = "warmups", chain = "chains", score = "scores")
  width <- switch(action, dataset = 2L, warmup = 3L, chain = 4L, score = 4L)
  prefix <- switch(action, dataset = "dataset_", warmup = "worker_", chain = "worker_", score = "cell_")
  folder <- file.path(root, stage, kind, sprintf(paste0(prefix, "%0", width, "d"), id))
  if (app_joint_prior_done(folder)) quit(status = 0)
  app_joint_prior_verify_freeze(root)
  check <- app_joint_shared_verify_manifest(file.path(root, stage), file.path(root, stage, "plan_manifest.csv"))
  stopifnot(all(check$verified))
  if (stage == "confirmation") app_joint_prior_verify_selection(root)
  app_ensure_dir(folder)
  writeLines(paste(Sys.getpid(), format(Sys.time(), tz = "UTC", usetz = TRUE)), file.path(folder, "RUNNING"))
  success <- tryCatch({
    fun <- switch(action, dataset = app_joint_prior_dataset, warmup = app_joint_prior_warmup,
      chain = app_joint_prior_chain, score = app_joint_prior_score)
    fun(root, stage, id); TRUE
  }, error = function(e) {
    writeLines(conditionMessage(e), file.path(folder, "FAILED"))
    message(conditionMessage(e)); FALSE
  })
  unlink(file.path(folder, "RUNNING"))
  quit(status = if (success) 0 else 1)
}
