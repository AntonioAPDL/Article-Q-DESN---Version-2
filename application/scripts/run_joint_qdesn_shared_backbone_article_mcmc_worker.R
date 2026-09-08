#!/usr/bin/env Rscript

Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1"
)
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_shared_backbone_article_confirmation_bootstrap.R"))

args <- app_parse_args(list(root = app_joint_article_default_root(), worker_id = NA_integer_))
worker_id <- as.integer(args[["worker-id"]] %||% args$worker_id)
if (!is.finite(worker_id)) stop("--worker-id is required.", call. = FALSE)

tryCatch(
  app_joint_article_run_mcmc_worker(args$root, worker_id),
  error = function(e) {
    msg <- conditionMessage(e)
    if (grepl("^(Refusing MCMC launch|Production workers require|MCMC launch blocked)",
        msg)) {
      message(msg)
      quit(status = 64L)
    }
    out <- app_joint_article_mcmc_worker_dir(args$root, worker_id)
    app_ensure_dir(out)
    if (!file.exists(file.path(out, "failure.csv"))) {
      app_write_csv(data.frame(
        worker_id = worker_id, status = "failed", error_message = msg,
        recorded_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
        stringsAsFactors = FALSE
      ), file.path(out, "failure.csv"))
    }
    writeLines("failed", file.path(out, "FAILED"))
    message(msg)
    quit(status = 1L)
  }
)
