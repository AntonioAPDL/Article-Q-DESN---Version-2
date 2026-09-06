args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(if (length(args)) args[[1L]] else ".", mustWork = TRUE)
package_library <- Sys.getenv(
  "PRICEFM_R66_PACKAGE_LIBRARY",
  "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_libraries/exdqlm_ab5741c"
)

source(file.path(root, "application/scripts/pricefm/pricefm_stage_r66_vb_helpers.R"))
suppressPackageStartupMessages(library("exdqlm", character.only = TRUE, lib.loc = package_library))

set.seed(6601)
n <- 36L
X <- cbind(1, matrix(stats::rnorm(n * 3L), nrow = n))
beta <- c(0.2, -0.4, 0.3, 0.1)
y <- as.numeric(X %*% beta + stats::rt(n, df = 7) * 0.35)
rhs <- list(
  tau0 = 0.001,
  shrink_intercept = FALSE,
  freeze_tau_iters = 2L,
  freeze_tau_warmup_iters = 2L
)
qcfg <- list(
  max_iter = 50L,
  min_iter_elbo = 10L,
  tol = 1e-4,
  tol_par = 1e-4,
  n_samp_xi = 12L,
  prior_sigma = list(a = 1, b = 1),
  prior_gamma = list(mu0 = 0, s20 = 10),
  chunking = list(enabled = TRUE, mode = "exact", chunk_size = 18L, order = "sequential", trace = FALSE)
)
profile <- list(
  factorization = "structured",
  structured_grid_size = 51L,
  structured_span_sd = 6,
  freeze_warmup_iters = 2L,
  force_after_warmup = TRUE,
  postwarmup_damping = 0.2,
  postwarmup_damping_iters = 5L,
  min_postwarmup_updates = 8L
)

normal <- exdqlm::normal_desn_fit(
  X,
  y,
  beta_prior_type = "rhs_ns",
  omega_prior = list(a = 2, b = 1),
  rhs = rhs,
  control = list(max_iter = 25L, min_iter = 8L, tol = 1e-5, verbose = FALSE)
)

telemetry <- list()
for (index in seq_along(c(0.10, 0.50, 0.90))) {
  tau <- c(0.10, 0.50, 0.90)[[index]]
  al_init <- r66_make_init(normal, ncol(X), gamma_zero = FALSE)
  al <- r66_fit_quantile(X, y, tau, "al", rhs, qcfg, profile, al_init$init, 6610L + index)
  exal_init <- r66_make_init(al, ncol(X), gamma_zero = TRUE)
  exal <- r66_fit_quantile(X, y, tau, "exal", rhs, qcfg, profile, exal_init$init, 6620L + index)
  item <- r66_sigmagam_telemetry(exal)
  stopifnot(identical(item$factorization, "structured_qgamma_qsigma_given_gamma"))
  stopifnot(identical(item$moment_source, "conditional_gig_exact"))
  stopifnot(identical(item$optimizer_start_source, "eta_start"))
  stopifnot(!isTRUE(item$optimizer_used_fallback))
  stopifnot(item$exact_commit_count >= 2L)
  stopifnot(is.finite(item$gamma), is.finite(item$sigma), item$sigma > 0)
  stopifnot(is.finite(item$gamma_relative_boundary_margin), item$gamma_relative_boundary_margin > 0)
  stopifnot(r66_sigmagam_telemetry_pass(exal, minimum_exact_commits = 2L))
  telemetry[[r66_tau_key(tau)]] <- item
}

stopifnot(telemetry[["0.1"]]$gamma > telemetry[["0.9"]]$gamma)

tmp <- tempfile("pricefm_r66_external_contract_")
dir.create(tmp)
fit_path <- file.path(tmp, "fit.rds")
status_path <- file.path(tmp, "status.json")
r66_atomic_save_rds(normal, fit_path)
r66_atomic_write_json(list(
  fit_sha256 = r66_sha256(fit_path),
  role = "shared_normal_rhs_anchor",
  case_id = "fixture"
), status_path)
contract <- r66_external_fit_contract(
  list(fit_path = fit_path, status_path = status_path, fit_sha256 = r66_sha256(fit_path), authorized = TRUE),
  list(role = "shared_normal_rhs_anchor", case_id = "fixture")
)
stopifnot(identical(contract$fit_sha256, r66_sha256(fit_path)))

cat("PriceFM Stage-R66 corrected structured-exAL helper test passed.\n")
