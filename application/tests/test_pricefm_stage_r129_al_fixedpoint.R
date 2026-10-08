args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) %in% c(2L, 3L))
source(args[[1L]])
ns <- r129_namespace(args[[2L]])
limits <- list(beta_posterior_sd_rms = 1e-4, predictor_rms = 1e-6,
  covariance_whitened_rms = 1e-4, sigma_relative = 1e-6,
  rhs_joint_log_rates = 1e-6, rhs_start_log_precision = 1e-6, elbo_relative = 1e-8)
set.seed(29)
X <- cbind(1, matrix(rnorm(400), 100, 4))
y <- as.numeric(X %*% c(.3, .8, -.2, .1, .4) + rnorm(100, sd = .5))
fit <- getExportedValue('exdqlm', 'exalStaticLDVB')(y = y, X = X, p0 = .5,
  dqlm.ind = TRUE, beta_prior = 'rhs_ns',
  beta_prior_controls = list(tau0 = .1, shrink_intercept = FALSE,
    freeze_tau_iters = 0L, freeze_tau_warmup_iters = 0L),
  a_sigma = 1, b_sigma = 1, n.samp = 0,
  vb_control = getExportedValue('exdqlm', 'exal_make_vb_control')(max_iter = 2000L, tol = 1e-8), verbose = FALSE)
stopifnot(isTRUE(fit$converged))
sigma <- fit$qsig$E_sigma
ok <- r129_certificate(ns, X, y, as.numeric(fit$qbeta$m), fit$qbeta$V,
  sigma, .5, .1, limits)
stopifnot(isTRUE(ok$certified), ok$diagnostic_rhs_shape == 2.5,
  identical(ok$shrunk_dimension, 4L), !ok$initialization_changes_prior)
bad_mean <- r129_certificate(ns, X, y, as.numeric(fit$qbeta$m) + .1,
  fit$qbeta$V, sigma, .5, .1, limits)
bad_cov <- r129_certificate(ns, X, y, as.numeric(fit$qbeta$m),
  fit$qbeta$V * 1.5, sigma, .5, .1, limits)
bad_sigma <- r129_certificate(ns, X, y, as.numeric(fit$qbeta$m),
  fit$qbeta$V, sigma * 1.5, .5, .1, limits)
stopifnot(!bad_mean$certified, !bad_cov$certified, !bad_sigma$certified)
p1 <- r129_prior(ns, 5L, .1, 'unit'); p2 <- r129_prior(ns, 5L, .1, 'dispersed')
for (k in c('tau0', 'intercept_prec', 'a_zeta', 'b_zeta', 'shrink_intercept')) {
  stopifnot(identical(p1$controls[[k]], p2$controls[[k]]))
}
q <- list(m = fit$qbeta$m, V = fit$qbeta$V)
stopifnot(abs(p1$elbo_vb(ok$reconstructed_rhs_state, q) -
  p2$elbo_vb(ok$reconstructed_rhs_state, q)) < 1e-12)
stopifnot(abs(ok$raw_reconstructed_elbo - tail(fit$diagnostics$elbo, 1L)) < 1e-5)
if (length(args) == 3L) {
  folder <- args[[3L]]; dir.create(folder, recursive = TRUE)
  write_bin <- function(name, x) {
    con <- file(file.path(folder, name), 'wb'); on.exit(close(con))
    writeBin(as.double(x), con, size = 8, endian = 'little')
  }
  write_bin('X.bin', t(X)); write_bin('y.bin', y)
  write_bin('beta_mean.bin', fit$qbeta$m); write_bin('beta_cov.bin', t(fit$qbeta$V))
  jsonlite::write_json(list(n = 100L, p = 5L,
    feature_names = c('intercept', paste0('layer1::', 1:4))), file.path(folder, 'design.json'),
    auto_unbox = TRUE, digits = 17)
  jsonlite::write_json(list(n = 100L, p = 5L, tau = .5, tau0 = .1,
    sigma = sigma, finite_core = TRUE, formal_converged = fit$converged,
    iterations = fit$iter, posterior_target_sha256 = 'test-target'),
    file.path(folder, 'terminal.json'), auto_unbox = TRUE, digits = 17)
}
cat('PASS: known converged public AL fit; altered beta/covariance/sigma rejection; RHS shape; init/prior separation; ELBO identity\n')
