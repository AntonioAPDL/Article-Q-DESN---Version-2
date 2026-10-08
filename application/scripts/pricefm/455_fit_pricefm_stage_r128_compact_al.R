#!/usr/bin/env Rscript
# Compact CRAN AL summaries suffice for downstream initialization and scoring.
args <- commandArgs(trailingOnly = TRUE)
at <- match('--config', args); stopifnot(!is.na(at), at < length(args))
cpath <- normalizePath(args[[at + 1L]], mustWork = TRUE)
c <- jsonlite::read_json(cpath, simplifyVector = TRUE)
hash <- function(path) digest::digest(path, file = TRUE, algo = 'sha256')
stopifnot(identical(c$stage, 'R128'), identical(c$family, 'al'),
  identical(c$test_opened, FALSE), identical(c$prior_center_from_initializer, FALSE),
  !dir.exists(c$output_dir), c$max_iter == 1000L,
  identical(hash(c$cran_adapter), c$cran_adapter_sha256),
  identical(hash(c$cran_manifest), c$cran_manifest_sha256),
  identical(hash(file.path(c$design_dir, 'terminal.json')), c$design_terminal_sha256),
  identical(hash(file.path(c$parent_dir, 'terminal.json')), c$parent_terminal_sha256))
source(c$cran_adapter)
pkg <- r67_assert_cran_package(c$cran_library, expected_version = '1.1.1')
manifest <- jsonlite::read_json(c$cran_manifest, simplifyVector = TRUE)
stopifnot(identical(manifest$status, 'installed_exact_cran_exdqlm_1.1.1'),
  identical(manifest$installed_package$repository, 'CRAN'))
d <- jsonlite::read_json(file.path(c$design_dir, 'design.json'), simplifyVector = TRUE)
t <- jsonlite::read_json(file.path(c$design_dir, 'terminal.json'), simplifyVector = TRUE)
stopifnot(identical(t$status, 'completed_r128_quantile_design'), identical(t$test_opened, FALSE),
  identical(d$feature_names[[1L]], 'intercept'), !any(startsWith(d$feature_names, 'input::')))
for (name in names(t$files)) stopifnot(identical(hash(file.path(c$design_dir, name)), t$files[[name]]))
read_f64 <- function(path, n) {
  con <- file(path, 'rb'); on.exit(close(con))
  x <- readBin(con, double(), n, size = 8L, endian = 'little')
  stopifnot(length(x) == n, all(is.finite(x))); x
}
X <- matrix(read_f64(file.path(c$design_dir, 'X.bin'), d$n * d$p), d$n, byrow = TRUE)
y <- read_f64(file.path(c$design_dir, 'y.bin'), d$n)
parent <- jsonlite::read_json(file.path(c$parent_dir, 'terminal.json'), simplifyVector = TRUE)
beta0 <- read_f64(file.path(c$parent_dir, 'beta_mean.bin'), d$p)
sigma0 <- if (identical(c$parent_type, 'normal_rhs')) {
  stopifnot(isTRUE(parent$full_variational_certified))
  sqrt(parent$omega_rate / (parent$omega_shape - 1))
} else {
  stopifnot(isTRUE(parent$formal_converged), isTRUE(parent$finite_core))
  parent$sigma
}
stopifnot(is.finite(sigma0), sigma0 > 0)
rhs <- list(tau0 = c$tau0, shrink_intercept = FALSE,
  freeze_tau_iters = 0L, freeze_tau_warmup_iters = 0L)
qcfg <- list(max_iter = c$max_iter, tol = c$tol, n_samp_xi = c$n_samp_xi,
  n_samp = c$n_samp, prior_sigma = list(a = 1, b = 1), verbose = FALSE)
started <- proc.time()[['elapsed']]
fit <- r67_fit_quantile(c$cran_library, X, y, c$tau, 'al', rhs, qcfg,
  init = list(beta = beta0, sigma = sigma0), seed = c$seed, expected_version = '1.1.1')
elapsed <- proc.time()[['elapsed']] - started
beta <- as.numeric(fit$qbeta$m); V <- as.matrix(fit$qbeta$V); sigma <- r67_safe_sigma(fit)
trace <- as.data.frame(fit$diagnostics$vb_trace)
finite <- length(beta) == d$p && all(is.finite(beta)) && all(is.finite(V)) &&
  all(diag(V) > 0) && is.finite(sigma) && sigma > 0 && nrow(trace) > 0
error <- y - as.numeric(X %*% beta)
pinball <- mean(pmax(c$tau * error, (c$tau - 1) * error))
dir.create(dirname(c$output_dir), recursive = TRUE, showWarnings = FALSE)
tmp <- tempfile(pattern = paste0(basename(c$output_dir), '.tmp.'), tmpdir = dirname(c$output_dir)); dir.create(tmp)
write_f64 <- function(name, x) {
  con <- file(file.path(tmp, name), 'wb'); on.exit(close(con))
  writeBin(as.double(x), con, size = 8L, endian = 'little')
}
write_f64('beta_mean.bin', beta); write_f64('beta_cov.bin', t(V))
utils::write.csv(trace, file.path(tmp, 'vb_trace.csv'), row.names = FALSE)
result <- list(status = 'completed_r128_al_fit', family = 'al', n = d$n, p = d$p,
  tau = c$tau, tau0 = c$tau0, sigma = sigma, gamma = 0, fold = c$fold,
  iterations = fit$iter, formal_converged = isTRUE(fit$converged), finite_core = finite,
  train_seconds = elapsed, posterior_target_sha256 = c$posterior_target_sha256,
  training_pinball_inner_units = pinball,
  contract_sha256 = hash(cpath), contract_path = cpath,
  package = pkg, initialization_only = TRUE, prior_center_from_initializer = FALSE,
  rhs_freeze_iters = 0L, test_opened = FALSE, full_fit_object_retained = FALSE,
  exact_optimizer_resumption_supported = FALSE,
  retained = c('beta_mean', 'beta_covariance', 'sigma', 'trace', 'target_and_source_contract'),
  termination = if (isTRUE(fit$converged)) 'formal_converged' else 'iteration_cap_or_uncertified',
  registry_mutated = FALSE, article_mutated = FALSE)
jsonlite::write_json(result, file.path(tmp, 'terminal.json'),
  auto_unbox = TRUE, pretty = TRUE, null = 'null', digits = 17)
stopifnot(!dir.exists(c$output_dir), file.rename(tmp, c$output_dir))
cat(jsonlite::toJSON(result, auto_unbox = TRUE, null = 'null'), '\n')
