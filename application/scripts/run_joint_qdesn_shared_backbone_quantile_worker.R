#!/usr/bin/env Rscript

Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1"
)
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_shared_backbone_quantile_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_shared_quantile_default_root(), job_id = NA_integer_))
job_id <- as.integer(args[["job-id"]] %||% args$job_id)
if (!is.finite(job_id)) stop("--job-id is required.", call. = FALSE)

tryCatch(
  app_joint_shared_quantile_run_worker(args$root, job_id),
  error = function(e) {
    out <- app_joint_shared_quantile_worker_dir(args$root, job_id)
    app_ensure_dir(out)
    failure <- file.path(out, "failure.csv")
    if (!file.exists(failure)) {
      app_write_csv(data.frame(
        job_id = job_id, status = "failed", error_message = conditionMessage(e),
        recorded_at = format(Sys.time(), tz = "UTC", usetz = TRUE), stringsAsFactors = FALSE
      ), failure)
    }
    writeLines("failed", file.path(out, "FAILED"))
    message(conditionMessage(e))
    quit(status = 1L)
  }
)
