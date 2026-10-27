#!/usr/bin/env Rscript
# Synthetic fixed states only; no production target files or certificates read.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3L)
root <- normalizePath(args[[1L]], mustWork = TRUE)
library_path <- normalizePath(args[[2L]], mustWork = TRUE)
out <- args[[3L]]; stopifnot(!file.exists(out))
source(file.path(root, 'application/R/pricefm_r129_al_fixedpoint_certificate.R'))
source(file.path(root, 'application/R/522_certificate_reference.R'))
ns <- r129_namespace(library_path)
started <- proc.time(); rows <- vector('list', 32L)
max_error <- 0; max_mean_error <- 0; max_cov_error <- 0
for (i in seq_len(32L)) {
  n <- 1L + ((i - 1L) %% 8L); p <- 1L + ((i - 1L) %% 4L)
  # No n*p production-sized input can enter this test.
  stopifnot(n <= 8L, p <= 4L)
  X <- matrix(sin(seq_len(n * p) / 3), n, p); X[, 1L] <- 1
  y <- seq(-.2, .4, length.out = n); m <- seq(.01, .04, length.out = p)
  V <- diag(seq(.01, .04, length.out = p), p)
  sigma <- .2 + (i - 1L) / 7; tau <- c(.1, .45, .5, .9)[1L + ((i - 1L) %% 4L)]
  if (i %% 8L == 1L) { X[,] <- 0; y[] <- 0 }
  if (i %% 8L == 2L) sigma <- 1e20
  prior <- r129_prior(ns, p, .01); state <- prior$init_vb()
  old <- r129_elbo(ns, prior, state, m, V, sigma, y, X, tau)
  stable <- r522_elbo_reference(prior, state, m, V, sigma, y, X, tau)
  error <- abs(old$elbo - stable$objective) / max(1, abs(old$elbo))
  stopifnot(is.finite(error), error < 2e-12)
  scales <- 10^seq(-3, 3, length.out = p)
  P <- matrix(.125, p, p); diag(P) <- 1; P <- P * outer(scales, scales)
  b <- seq_len(p) * scales; g <- r522_gaussian_reference(P, b)
  mean_error <- max(abs(as.numeric(P %*% g$beta) - b) / pmax(1, abs(b)))
  cov_error <- max(abs(P %*% g$covariance - diag(p)))
  stopifnot(mean_error < 1e-10, cov_error < 1e-9, g$jitter_added == 0)
  rows[[i]] <- list(n = n, p = p, residual = old$residual, second = old$second,
    sigma = sigma, tau = tau, logdetV = 2 * sum(log(diag(chol(V)))),
    original_prior_elbo = stable$terms[['prior']], original_objective = old$elbo,
    stable_objective = stable$objective, relative_difference = error,
    chi_floor_count = stable$chi_floor_count, psi_floor_active = stable$psi_floor_active)
  max_error <- max(max_error, error); max_mean_error <- max(max_mean_error, mean_error)
  max_cov_error <- max(max_cov_error, cov_error)
}
elapsed <- proc.time() - started
result <- list(status = 'PASS_32_SYNTHETIC_FIXED_STATE_REFERENCES',
  record_kind = 'diagnostic_only_no_production_acceptance_authority',
  tiny_fixed_state_cases = 32L, cases = rows,
  max_original_vs_collapsed_relative_error = max_error,
  max_original_unit_mean_error = max_mean_error, max_original_unit_inverse_residual = max_cov_error,
  elapsed_wall_seconds = unname(elapsed[['elapsed']]),
  process_CPU_seconds = unname(elapsed[['user.self']] + elapsed[['sys.self']]),
  process_CPU_seconds_total_including_startup = unname(sum(proc.time()[c('user.self', 'sys.self')])),
  posterior_fits = 0L, target_numeric_diagnoses = 0L, certificate_recomputations = 0L,
  package = list(path = find.package('exdqlm'), version = as.character(packageVersion('exdqlm'))),
  R = R.version.string, BLAS = unname(extSoftVersion()[['BLAS']]),
  original_prior_scalar_independently_oracled = FALSE)
con <- file(out, open = 'wx'); on.exit(close(con))
writeLines(jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE, digits = 17), con)
cat('PASS 32 synthetic states; no target arithmetic or fits\n')
