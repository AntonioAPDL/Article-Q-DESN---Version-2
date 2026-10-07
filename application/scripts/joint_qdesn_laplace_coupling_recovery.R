#!/usr/bin/env Rscript
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
source(file.path(dirname(script), "_joint_qdesn_laplace_coupling_recovery_bootstrap.R"))
stopifnot(getRversion() == "4.6.0")
args <- commandArgs(TRUE)
if (length(args) < 2L) stop("Usage: SCRIPT ACTION ROOT [SOURCE|STAGE|KIND|ID]")
action <- args[[1L]]; root <- normalizePath(args[[2L]], mustWork = FALSE)
folder_for <- function(stage, action, id) {
  kind <- switch(action, dataset = "datasets", calibrate = "calibrations",
    warmup = "warmups", chain = "chains", score = "scores")
  width <- switch(action, dataset = 2L, calibrate = 2L, warmup = 3L, chain = 4L, score = 4L)
  prefix <- if (action %in% c("dataset", "calibrate")) "dataset_" else if (action == "score") "cell_" else "worker_"
  file.path(root, stage, kind, sprintf(paste0(prefix, "%0", width, "d"), id))
}
if (action == "prepare") {
  stopifnot(length(args) == 3L)
  app_joint_recovery_prepare(root, args[[3L]])
} else if (action == "validate-source") {
  stopifnot(length(args) == 3L)
  verified <- app_joint_recovery_verify_source(args[[3L]])
  cat(sprintf("Verified %d frozen source evidence files.\n", nrow(verified)))
} else if (action == "adjudicate") {
  app_joint_recovery_adjudicate(root)
} else if (action == "finalize") {
  app_joint_recovery_finalize(root)
} else if (action == "ids") {
  stage <- args[[3L]]; kind <- args[[4L]]
  worker_action <- if (length(args) >= 5L) args[[5L]] else switch(kind,
    datasets = "dataset", warmups = "warmup", chains = "chain", cells = "score")
  plan <- app_read_csv(file.path(root, stage, paste0(kind, ".csv")))
  key <- switch(kind, datasets = "dataset_id", warmups = "worker_id",
    chains = "worker_id", cells = "cell_id")
  ids <- plan[[key]]
  pending <- !vapply(ids, function(id) app_joint_prior_done(folder_for(stage, worker_action, id)), logical(1L))
  if (any(pending)) cat(ids[pending], sep = "\n")
} else if (action == "health") {
  rows <- list()
  for (stage in c("screen", "confirmation")) {
    if (!dir.exists(file.path(root, stage))) next
    kinds <- if (stage == "screen") c("chains", "cells") else
      c("datasets", "calibrations", "warmups", "chains", "cells")
    for (kind in kinds) {
      plan_name <- if (kind == "calibrations") "datasets" else kind
      path <- file.path(root, stage, paste0(plan_name, ".csv")); if (!file.exists(path)) next
      plan <- app_read_csv(path)
      action_name <- switch(kind, datasets = "dataset", calibrations = "calibrate",
        warmups = "warmup", chains = "chain", cells = "score")
      ids <- if (kind %in% c("datasets", "calibrations")) plan$dataset_id else if (kind == "cells") plan$cell_id else plan$worker_id
      dirs <- vapply(ids, function(id) folder_for(stage, action_name, id), character(1L))
      done <- vapply(dirs, app_joint_prior_done, logical(1L))
      failed <- file.exists(file.path(dirs, "FAILED")) & !done
      running <- file.exists(file.path(dirs, "RUNNING")) & !done & !failed
      expected <- if (stage == "screen" && kind == "chains") sum(plan$chain_id > 2L) else nrow(plan)
      complete <- if (stage == "screen" && kind == "chains") sum(done & plan$chain_id > 2L) else sum(done)
      run_count <- if (stage == "screen" && kind == "chains") sum(running & plan$chain_id > 2L) else sum(running)
      fail_count <- if (stage == "screen" && kind == "chains") sum(failed & plan$chain_id > 2L) else sum(failed)
      rows[[length(rows) + 1L]] <- data.frame(stage, kind, expected, complete,
        failed = fail_count, running = run_count, left = expected - complete)
    }
  }
  if (length(rows)) print(do.call(rbind, rows), row.names = FALSE)
  cat("Selection frozen:", file.exists(file.path(root, "screen/SELECTION_FROZEN")), "\n")
  cat("Final closeout:", file.exists(file.path(root, "COMPLETE")), "\n")
} else {
  stopifnot(action %in% c("dataset", "calibrate", "warmup", "chain", "score"), length(args) == 4L)
  stage <- args[[3L]]; id <- as.integer(args[[4L]])
  stopifnot(stage %in% c("screen", "confirmation"), length(id) == 1L, is.finite(id), id > 0)
  folder <- folder_for(stage, action, id)
  if (app_joint_prior_done(folder)) quit(status = 0)
  app_joint_prior_verify_freeze(root)
  checked <- app_joint_shared_verify_manifest(file.path(root, stage),
    file.path(root, stage, "plan_manifest.csv"))
  stopifnot(all(checked$verified))
  if (stage == "confirmation") app_joint_prior_verify_selection(root)
  app_ensure_dir(folder)
  writeLines(paste(Sys.getpid(), format(Sys.time(), tz = "UTC", usetz = TRUE)),
    file.path(folder, "RUNNING"))
  success <- tryCatch({
    fun <- switch(action, dataset = app_joint_prior_dataset,
      calibrate = app_joint_coupling_calibrate, warmup = app_joint_prior_warmup,
      chain = app_joint_prior_chain, score = app_joint_prior_score)
    fun(root, stage, id); TRUE
  }, error = function(e) {
    writeLines(conditionMessage(e), file.path(folder, "FAILED"))
    message(conditionMessage(e)); FALSE
  })
  unlink(file.path(folder, "RUNNING"))
  if (success) unlink(file.path(folder, "FAILED"))
  quit(status = if (success) 0 else 1)
}
