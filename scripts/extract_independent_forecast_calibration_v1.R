#!/usr/bin/env Rscript
options(stringsAsFactors = FALSE, digits = 17)
Sys.setenv(OMP_NUM_THREADS = 1, OPENBLAS_NUM_THREADS = 1, MKL_NUM_THREADS = 1,
  VECLIB_MAXIMUM_THREADS = 1, RCPP_PARALLEL_NUM_THREADS = 1)
script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))
root <- normalizePath(file.path(dirname(script), ".."))
args <- commandArgs(TRUE)
if (!length(args) || length(args) %% 2L || anyDuplicated(args[seq.int(1L, length(args), 2L)]) ||
    !all(args[seq.int(1L, length(args), 2L)] %in% c("--validation-root", "--output-dir")))
  stop("Usage: Rscript scripts/extract_independent_forecast_calibration_v1.R --validation-root PATH [--output-dir PATH]", call. = FALSE)
value <- function(flag, default = NULL) {
  i <- match(flag, args); if (is.na(i)) default else args[i + 1L]
}
validation <- value("--validation-root")
if (is.null(validation) || !nzchar(validation)) stop("--validation-root is required.", call. = FALSE)
output <- value("--output-dir", file.path(root, "local_trackers/independent_forecast_calibration_v1/derived"))
source(file.path(root, "application/R/independent_forecast_calibration_v1.R"))
ifc_extract(root, validation, output)
cat("PASS: 72 descriptive quantile frequencies from 108 retained chains; no fits or forecasts launched.\n")
