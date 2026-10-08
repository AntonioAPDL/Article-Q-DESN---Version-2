#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
at <- match('--config', args); stopifnot(!is.na(at), at < length(args))
config <- normalizePath(args[[at + 1L]], mustWork = TRUE)
c <- jsonlite::read_json(config, simplifyVector = TRUE)
hash <- function(path) digest::digest(path, file = TRUE, algo = 'sha256')
stopifnot(identical(c$stage, 'R129'), identical(c$action, 'public_AL_fit'),
  identical(c$test_opened, FALSE), !dir.exists(c$output_dir),
  c$max_iter == 1000L, c$tol == .001)
for (name in names(c$input_sha256)) stopifnot(identical(hash(name), c$input_sha256[[name]]))
source(c$cran_adapter); source(c$helper)
ns <- r129_namespace(c$cran_library)
d <- jsonlite::read_json(file.path(c$design_dir, 'design.json'), simplifyVector = TRUE)
design_terminal <- jsonlite::read_json(file.path(c$design_dir, 'terminal.json'), simplifyVector = TRUE)
for (name in names(design_terminal$files)) {
  stopifnot(identical(hash(file.path(c$design_dir, name)), design_terminal$files[[name]]))
}
stopifnot(!any(startsWith(d$feature_names, 'input::')))
parent <- jsonlite::read_json(file.path(c$parent_dir, 'terminal.json'), simplifyVector = TRUE)
stopifnot(isTRUE(parent$independent_fixedpoint_certified), parent$tau0 == c$tau0,
  parent$p == d$p, abs(parent$tau - .5) < abs(c$tau - .5))
read_bin <- function(path, size) {
  con <- file(path, 'rb'); on.exit(close(con))
  x <- readBin(con, double(), size, size = 8, endian = 'little')
  stopifnot(length(x) == size, all(is.finite(x))); x
}
X <- matrix(read_bin(file.path(c$design_dir, 'X.bin'), d$n * d$p), d$n, byrow = TRUE)
y <- read_bin(file.path(c$design_dir, 'y.bin'), d$n)
m0 <- read_bin(file.path(c$parent_dir, 'beta_mean.bin'), d$p)
start <- proc.time()[['elapsed']]
fit <- r67_fit_quantile(c$cran_library, X, y, c$tau, 'al',
  list(tau0 = c$tau0, shrink_intercept = FALSE, freeze_tau_iters = 0L, freeze_tau_warmup_iters = 0L),
  list(max_iter = c$max_iter, tol = c$tol, n_samp_xi = c$n_samp,
    n_samp = c$n_samp, prior_sigma = list(a = 1, b = 1), verbose = FALSE),
  init = list(beta = m0, sigma = parent$sigma), seed = c$seed, expected_version = '1.1.1')
fit_seconds <- proc.time()[['elapsed']] - start
m <- as.numeric(fit$qbeta$m); V <- fit$qbeta$V; sigma <- r67_safe_sigma(fit)
certificate <- r129_certificate(ns, X, y, m, V, sigma, c$tau, c$tau0, c$limits,
  max_rhs_iter = c$max_rhs_iter)
dir.create(c$output_dir, recursive = TRUE)
write_bin <- function(name, x) {
  con <- file(file.path(c$output_dir, name), 'wb'); on.exit(close(con))
  writeBin(as.double(x), con, size = 8, endian = 'little')
}
write_bin('beta_mean.bin', m); write_bin('beta_cov.bin', t(V))
utils::write.csv(fit$diagnostics$vb_trace, file.path(c$output_dir, 'vb_trace.csv'), row.names = FALSE)
saveRDS(list(original_public_prior = fit$beta_prior, original_public_qsigma = fit$qsig,
  original_public_latent = fit$qv, reconstructed_prior = certificate$reconstructed_rhs_state,
  reconstructed_qsigma = certificate$likelihood_scale_state, reconstructed_latent = certificate$latent_state),
  file.path(c$output_dir, 'variational_state.rds'), compress = 'xz')
certificate[c('reconstructed_rhs_state', 'likelihood_scale_state', 'latent_state', 'beta_covariance', 'prior_center')] <- NULL
jsonlite::write_json(certificate, file.path(c$output_dir, 'certificate.json'),
  auto_unbox = TRUE, pretty = TRUE, null = 'null', digits = 17)
finite <- all(is.finite(m)) && all(is.finite(V)) && is.finite(sigma) && sigma > 0
terminal <- list(status = 'completed_r129_public_AL_with_independent_certificate', family = 'al',
  p = d$p, n = d$n, fold = c$fold, tau = c$tau, tau0 = c$tau0, sigma = sigma, gamma = 0,
  iterations = fit$iter, formal_converged = isTRUE(fit$converged), finite_core = finite,
  computational_stop_tol = c$tol, independent_fixedpoint_certified = certificate$certified,
  convergence_policy = 'full_AL_RHS_fixedpoint_certificate_not_raw_beta_stop_alone',
  train_seconds = fit_seconds, total_seconds = proc.time()[['elapsed']] - start,
  posterior_target_sha256 = c$posterior_target_sha256,
  prior_center_from_initializer = FALSE, initialization_only = TRUE, test_opened = FALSE,
  beta_prior = 'rhs_ns', public_cran_version = '1.1.1', public_api = 'exalStaticLDVB',
  exact_optimizer_resumption_supported = FALSE, source_config_sha256 = hash(config),
  contract_path = config, registry_mutated = FALSE, article_mutated = FALSE)
jsonlite::write_json(terminal, file.path(c$output_dir, 'terminal.json'),
  auto_unbox = TRUE, pretty = TRUE, null = 'null', digits = 17)
cat(jsonlite::toJSON(terminal, auto_unbox = TRUE, null = 'null'), '\n')
