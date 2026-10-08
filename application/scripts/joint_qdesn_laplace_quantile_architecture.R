#!/usr/bin/env Rscript
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
source(file.path(dirname(script), "_joint_qdesn_laplace_quantile_architecture_bootstrap.R"))
args <- commandArgs(TRUE)
if (length(args) < 2L) stop("Usage: SCRIPT ACTION ROOT [STAGE] [ID_OR_SOURCE]")
action <- args[[1L]]; root <- normalizePath(args[[2L]], mustWork = FALSE)
if (action == "prepare") {
  source_root <- if (length(args) >= 3L) args[[3L]] else app_joint_arch_contract()$source_runtime
  app_joint_arch_prepare(root, source_root)
} else if (action == "select-vb") {
  app_joint_arch_select_vb(root)
} else if (action == "select-mcmc") {
  app_joint_arch_mcmc_select(root)
} else if (action == "finalize") {
  app_joint_arch_finalize(root)
} else if (action == "health") {
  print(app_joint_arch_health(root), row.names = FALSE)
  cat("Terminal:", if (file.exists(file.path(root, "COMPLETE"))) readLines(file.path(root, "COMPLETE")) else "not_complete", "\n")
} else if (action == "ids") {
  stage <- args[[3L]]; kind <- args[[4L]]
  plan <- app_read_csv(file.path(root, stage, paste0(kind, ".csv")))
  key <- switch(kind, datasets = "dataset_id", warmups = "worker_id", chains = "worker_id", cells = "cell_id")
  cat(plan[[key]], sep = "\n")
} else {
  stopifnot(action %in% c("vb", "dataset", "warmup", "chain", "score"))
  stage <- args[[3L]]; id <- as.integer(args[[4L]])
  stopifnot(length(id) == 1L, is.finite(id), id > 0L)
  if (action == "vb") {
    folder <- file.path(root, "vb", "workers", sprintf("worker_%03d", id))
    if (app_joint_arch_done(folder)) quit(status = 0L)
    success <- tryCatch({app_joint_arch_vb_worker(root, id); TRUE}, error = function(e) {
      app_ensure_dir(folder); writeLines(conditionMessage(e), file.path(folder, "FAILED")); message(conditionMessage(e)); FALSE
    })
    quit(status = if (success) 0L else 1L)
  }
  stopifnot(stage %in% c("screen", "confirmation"))
  kind <- switch(action, dataset = "datasets", warmup = "warmups", chain = "chains", score = "scores")
  width <- switch(action, dataset = 2L, warmup = 3L, chain = 4L, score = 4L)
  prefix <- switch(action, dataset = "dataset_", warmup = "worker_", chain = "worker_", score = "cell_")
  folder <- file.path(root, stage, kind, sprintf(paste0(prefix, "%0", width, "d"), id))
  if (app_joint_arch_done(folder)) quit(status = 0L)
  app_joint_arch_verify_freeze(root)
  checked <- app_joint_shared_verify_manifest(file.path(root, stage), file.path(root, stage, "plan_manifest.csv"))
  stopifnot(all(checked$verified))
  if (stage == "screen") app_joint_arch_verify_selection(root, "vb") else app_joint_arch_verify_selection(root, "screen")
  app_ensure_dir(folder); writeLines(paste(Sys.getpid(), format(Sys.time(), tz = "UTC", usetz = TRUE)), file.path(folder, "RUNNING"))
  success <- tryCatch({
    fun <- switch(action, dataset = app_joint_arch_dataset, warmup = app_joint_arch_warmup,
      chain = app_joint_arch_chain, score = app_joint_prior_score)
    fun(root, stage, id); TRUE
  }, error = function(e) {
    writeLines(conditionMessage(e), file.path(folder, "FAILED")); message(conditionMessage(e)); FALSE
  })
  unlink(file.path(folder, "RUNNING"))
  quit(status = if (success) 0L else 1L)
}
