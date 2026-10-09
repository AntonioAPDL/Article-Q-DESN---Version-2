#!/usr/bin/env Rscript
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
source(file.path(dirname(script), "_joint_qdesn_laplace_architecture_article_confirmation_bootstrap.R"))
args <- commandArgs(TRUE)
if (length(args) < 2L) stop("Usage: SCRIPT ACTION ROOT [KIND_OR_ID]")
action <- args[[1L]]
root <- normalizePath(args[[2L]], mustWork = FALSE)

if (action == "prepare") {
  app_joint_laplace_article_prepare(root)
} else if (action == "verify") {
  app_joint_laplace_article_verify_freeze(root, verify_large_inputs = TRUE)
  cat("PASS: frozen sources, protected fixture, oracle, and execution plan verify.\n")
} else if (action == "finalize") {
  app_joint_laplace_article_finalize(root)
} else if (action == "health") {
  print(app_joint_laplace_article_health(root), row.names = FALSE)
  terminal <- if (file.exists(file.path(root, "COMPLETE"))) {
    readLines(file.path(root, "COMPLETE"), warn = FALSE)[[1L]]
  } else "not_complete"
  cat("Terminal:", terminal, "\n")
} else if (action == "ids") {
  kind <- args[[3L]]
  plan <- app_read_csv(file.path(root, "article", paste0(kind, ".csv")))
  key <- switch(kind, datasets = "dataset_id", warmups = "worker_id",
    chains = "worker_id", cells = "cell_id", stop("Unknown plan kind."))
  cat(plan[[key]], sep = "\n")
} else {
  stopifnot(action %in% c("dataset", "warmup", "chain", "score"))
  id <- as.integer(args[[3L]])
  stopifnot(length(id) == 1L, is.finite(id), id > 0L)
  kind <- switch(action, dataset = "datasets", warmup = "warmups", chain = "chains", score = "scores")
  width <- switch(action, dataset = 2L, warmup = 3L, chain = 4L, score = 4L)
  prefix <- switch(action, dataset = "dataset_", warmup = "worker_", chain = "worker_", score = "cell_")
  folder <- file.path(root, "article", kind, sprintf(paste0(prefix, "%0", width, "d"), id))
  if (app_joint_arch_done(folder)) quit(status = 0L)
  app_joint_laplace_article_verify_freeze(root, verify_large_inputs = action == "dataset")
  app_ensure_dir(folder)
  writeLines(paste(Sys.getpid(), format(Sys.time(), tz = "UTC", usetz = TRUE)),
    file.path(folder, "RUNNING"))
  success <- tryCatch({
    fun <- switch(action, dataset = app_joint_laplace_article_dataset,
      warmup = function(root, id) app_joint_arch_warmup(root, "article", id),
      chain = function(root, id) app_joint_arch_chain(root, "article", id),
      score = function(root, id) app_joint_prior_score(root, "article", id))
    fun(root, id)
    TRUE
  }, error = function(e) {
    writeLines(conditionMessage(e), file.path(folder, "FAILED"))
    message(conditionMessage(e))
    FALSE
  })
  unlink(file.path(folder, "RUNNING"))
  quit(status = if (success) 0L else 1L)
}
