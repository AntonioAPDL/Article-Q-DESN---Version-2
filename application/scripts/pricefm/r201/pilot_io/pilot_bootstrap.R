#!/usr/bin/env Rscript
# New pilot bootstrap: no target data or numerical entry before actual parent ACK.
args <- commandArgs(TRUE)
stopifnot(length(args) == 6L)
loadNamespace("digest"); loadNamespace("jsonlite")
checked_json <- function(path, sha) {
  stopifnot(grepl("^[0-9a-f]{64}$", sha),
    identical(digest::digest(path, file = TRUE, algo = "sha256"), sha))
  jsonlite::read_json(path, simplifyVector = FALSE)
}
spec_pin <- list(path = args[[1L]], sha256 = args[[2L]])
authority_pin <- list(path = args[[3L]], sha256 = args[[4L]])
review_pin <- list(path = args[[5L]], sha256 = args[[6L]])
spec <- checked_json(spec_pin$path, spec_pin$sha256)
authority <- checked_json(authority_pin$path, authority_pin$sha256)
review <- checked_json(review_pin$path, review_pin$sha256)
stopifnot(identical(spec$role, "NO3_AL300_PILOT"),
  identical(authority$spec, spec_pin), identical(authority$source_review, review_pin),
  identical(spec$job_id, Sys.getenv("SLURM_JOB_ID")),
  identical(spec$node, Sys.getenv("SLURMD_NODENAME")))
# Load definitions from exactly the source pin reviewed by the current parent.
io_source <- spec$source_pins[["pilot_io/pilot_owned_io.R"]]
stopifnot(is.list(io_source), identical(digest::digest(io_source$path, file = TRUE,
  algo = "sha256"), io_source$sha256))
source(io_source$path)
cap <- r200_begin_after_real_ack(spec_pin, spec$io_request, authority_pin, review_pin)
result <- r200_execute_exact_pilot(cap)
stopifnot(isTRUE(result$candidate_only), identical(result$production_admission, FALSE))
cat("R200 pilot returned a candidate; independent return/acceptance remains required\n")
