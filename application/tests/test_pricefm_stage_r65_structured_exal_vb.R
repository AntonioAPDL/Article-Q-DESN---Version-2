args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(if (length(args)) args[[1L]] else ".", mustWork = TRUE)
package_path <- Sys.getenv(
  "PRICEFM_R65_PACKAGE_PATH",
  "/data/jaguir26/local/src/exdqlm__wt__pricefm_r65_cc85a75"
)
package_library <- Sys.getenv("PRICEFM_R65_PACKAGE_LIBRARY", "")

source(file.path(root, "application/scripts/pricefm/pricefm_stage_r65_vb_helpers.R"))
if (nzchar(package_library)) {
  suppressPackageStartupMessages(library("exdqlm", character.only = TRUE, lib.loc = package_library))
} else {
  suppressPackageStartupMessages(pkgload::load_all(package_path, quiet = TRUE))
}

set.seed(6501)
n <- 48L
X <- cbind(1, matrix(stats::rnorm(n * 3L), nrow = n))
beta <- c(0.2, -0.4, 0.3, 0.1)
y <- as.numeric(X %*% beta + stats::rt(n, df = 7) * 0.4)
rhs <- list(
  tau0 = 0.001,
  shrink_intercept = FALSE,
  freeze_tau_iters = 2L,
  freeze_tau_warmup_iters = 2L
)
qcfg <- list(
  max_iter = 18L,
  min_iter_elbo = 6L,
  tol = 1e-4,
  tol_par = 1e-4,
  n_samp_xi = 12L,
  prior_sigma = list(a = 1, b = 1),
  prior_gamma = list(mu0 = 0, s20 = 10),
  chunking = list(enabled = TRUE, mode = "exact", chunk_size = 24L, order = "sequential", trace = FALSE)
)
profile <- list(
  factorization = "structured",
  structured_grid_size = 51L,
  structured_span_sd = 6,
  freeze_warmup_iters = 2L,
  force_after_warmup = TRUE,
  postwarmup_damping = 0.6,
  postwarmup_damping_iters = 2L,
  min_postwarmup_updates = 1L
)

normal <- exdqlm::normal_desn_fit(
  X,
  y,
  beta_prior_type = "rhs_ns",
  omega_prior = list(a = 2, b = 1),
  rhs = rhs,
  control = list(max_iter = 25L, min_iter = 8L, tol = 1e-5, verbose = FALSE)
)
al_init <- r65_make_init(normal, ncol(X), gamma_zero = FALSE)
stopifnot(max(abs(al_init$init$beta_m - as.numeric(normal$beta$mean))) < 1e-12)
al <- r65_fit_quantile(X, y, 0.5, "al", rhs, qcfg, profile, al_init$init, 6502L)
exal_init <- r65_make_init(al, ncol(X), gamma_zero = TRUE)
stopifnot(max(abs(exal_init$init$beta_m - as.numeric(al$qbeta$m))) < 1e-12)
exal <- r65_fit_quantile(X, y, 0.5, "exal", rhs, qcfg, profile, exal_init$init, 6503L)
telemetry <- r65_sigmagam_telemetry(exal)

stopifnot(identical(telemetry$factorization, "structured_qgamma_qsigma_given_gamma"))
stopifnot(identical(telemetry$configured_factorization, "structured"))
stopifnot(telemetry$postwarmup_update_count >= 1L)
stopifnot(telemetry$postwarmup_update_count >= telemetry$required_postwarmup_updates)

tmp <- tempfile("pricefm_r65_atomic_")
dir.create(tmp)
fit_path <- file.path(tmp, "fit.rds")
status_path <- file.path(tmp, "status.json")
r65_atomic_save_rds(exal, fit_path, compress = "gzip")
expected <- list(config_sha256 = "fixture", package_head = "fixture", case_id = "fixture")
r65_atomic_write_json(c(expected, list(fit_sha256 = r65_sha256(fit_path))), status_path)
stopifnot(r65_status_is_valid(status_path, fit_path, expected))

cat("PriceFM Stage-R65 structured-exAL helper test passed.\n")
