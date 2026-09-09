#!/usr/bin/env Rscript

Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1"
)
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_shared_backbone_article_confirmation_bootstrap.R"))

args <- app_parse_args(list(root = app_joint_article_default_root(), job_id = NA_integer_))
job_id <- as.integer(args[["job-id"]] %||% args$job_id)
if (!is.finite(job_id)) stop("--job-id is required.", call. = FALSE)
contract <- app_joint_article_read_contract(file.path(args$root, "frozen_contract.csv"))
if (!identical(Sys.getenv("JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION"), "VB")) {
  stop("Refusing VB worker without JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION=VB.",
    call. = FALSE)
}
app_joint_article_assert_clean_execution(contract)
app_joint_article_assert_capacity_authorized(contract)
app_joint_article_host_preflight(contract)

tryCatch(
  app_joint_article_run_vb_worker(args$root, job_id),
  error = function(e) {
    out <- app_joint_article_vb_worker_dir(args$root, job_id)
    app_ensure_dir(out)
    if (!file.exists(file.path(out, "failure.csv"))) {
      app_write_csv(data.frame(
        job_id = job_id, status = "failed", error_message = conditionMessage(e),
        recorded_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
        stringsAsFactors = FALSE
      ), file.path(out, "failure.csv"))
    }
    writeLines("failed", file.path(out, "FAILED"))
    message(conditionMessage(e))
    quit(status = 1L)
  }
)
