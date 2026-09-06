#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
  stop(
    "Usage: pricefm_stage_r67_cran_al_rhsns_probe.R LIBRARY EXPECTED_VERSION OUTPUT_JSON",
    call. = FALSE
  )
}

library_path <- normalizePath(args[[1L]], mustWork = TRUE)
expected_version <- as.character(args[[2L]])
output_path <- args[[3L]]
description <- utils::packageDescription("exdqlm", lib.loc = library_path)
if (!identical(as.character(description$Version), expected_version)) {
  stop("Unexpected exdqlm version: ", description$Version, call. = FALSE)
}
if (!identical(as.character(description$Repository), "CRAN")) {
  stop("Probe requires an exact CRAN installation.", call. = FALSE)
}
namespace <- loadNamespace("exdqlm", lib.loc = library_path)
fit_function <- getExportedValue("exdqlm", "exalStaticLDVB")

x <- seq(-1, 1, length.out = 120L)
X <- cbind(1, x, sin(3 * x), cos(2 * x))
y <- 0.4 - 0.7 * x + 0.2 * sin(3 * x) + 0.08 * cos(11 * x)
set.seed(7731L)
fit <- fit_function(
  y = y,
  X = X,
  p0 = 0.25,
  al.ind = TRUE,
  beta_prior = "rhs_ns",
  beta_prior_controls = list(
    tau0 = 1e-3,
    shrink_intercept = FALSE,
    freeze_tau_iters = 5L,
    freeze_tau_warmup_iters = 5L
  ),
  max_iter = 120L,
  tol = 1e-7,
  n.samp = 20L,
  verbose = FALSE
)

payload <- list(
  package = "exdqlm",
  version = as.character(description$Version),
  repository = as.character(description$Repository),
  packaged = as.character(description$Packaged),
  engine = "exalStaticLDVB_public_al_rhs_ns",
  seed = 7731L,
  tau = 0.25,
  tau0 = 1e-3,
  converged = isTRUE(fit$converged),
  iter = as.integer(fit$iter),
  qbeta_m = as.numeric(fit$qbeta$m),
  qbeta_V = as.numeric(fit$qbeta$V),
  qsig = fit$qsig,
  samp_beta = as.numeric(fit$samp.beta),
  samp_sigma = as.numeric(fit$samp.sigma),
  prediction = as.numeric(X %*% fit$qbeta$m)
)

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
cat(
  jsonlite::toJSON(payload, auto_unbox = TRUE, pretty = TRUE, digits = 17),
  "\n",
  file = output_path,
  sep = ""
)
