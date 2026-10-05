args <- commandArgs(trailingOnly = TRUE)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), "..", ".."))
source(file.path(root, "application/R/pricefm_recursive_normal_fit.R"))
runtime <- if (length(args)) args[[1L]] else
  "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"
pkgload::load_all(runtime, quiet = TRUE, export_all = TRUE)
factory <- get("beta_prior", envir = asNamespace("exdqlm"))
set.seed(41)
X <- cbind(1, matrix(rnorm(180 * 5), 180, 5))
y <- as.numeric(X %*% c(.4, -.3, .1, 0, 0, .2) + rnorm(180, sd = .3))
stats <- app_pricefm_normal_stats_from_design(X, y)
run <- function(max_iter, initial_fit = NULL, tau0 = .05, omega_b = 1) {
  app_pricefm_fit_rhs_stats(stats, tau0, factory, min_iter = max_iter, max_iter = max_iter,
    convergence_mode = "full_variational", record_objective = TRUE,
    initial_fit = initial_fit, omega_b = omega_b)
}
full <- run(40L)
partial <- run(17L)
resumed <- run(40L, partial)
stopifnot(isTRUE(all.equal(full$beta, resumed$beta, tolerance = 0)),
  isTRUE(all.equal(full$beta_prior, resumed$beta_prior, tolerance = 0)),
  isTRUE(all.equal(full$omega2, resumed$omega2, tolerance = 0)),
  isTRUE(all.equal(full$trace, resumed$trace, tolerance = 0)))
stopifnot(inherits(try(run(40L, partial, tau0 = .1), silent = TRUE), "try-error"),
  inherits(try(run(40L, partial, omega_b = 2), silent = TRUE), "try-error"))
altered <- partial; altered$stats$Xty[[2L]] <- altered$stats$Xty[[2L]] + .1
stopifnot(inherits(try(run(40L, altered), silent = TRUE), "try-error"))
left <- app_pricefm_fit_rhs_stats(stats, .05, factory, min_iter = 20, max_iter = 20,
  initial_tau = 1, record_objective = TRUE)
right <- app_pricefm_fit_rhs_stats(stats, .05, factory, min_iter = 20, max_iter = 20,
  initial_tau = .05, record_objective = TRUE)
stopifnot(identical(left$beta_prior$hypers, right$beta_prior$hypers),
  identical(left$noise_prior, right$noise_prior),
  all(diff(full$trace$total_objective) >= -1e-7))

trace <- full$trace[rep(1L, 10), ]; trace$iter <- seq_len(10)
for (name in setdiff(names(trace), c("iter", "sigma2_mean", "total_objective", "tau_inverse_moment", "slab_inverse_moment"))) {
  trace[[name]] <- 0
}
stopifnot(app_pricefm_rhs_convergence_status(trace, "full_variational"))
trace$rhs_max_log_rate_delta[[10L]] <- .01
stopifnot(app_pricefm_rhs_convergence_status(trace, "predictive_fixed_point"),
  !app_pricefm_rhs_convergence_status(trace, "full_variational"))
trace$rhs_max_log_rate_delta[[10L]] <- 0; trace$beta_cov_relative_delta[[10L]] <- .01
stopifnot(!app_pricefm_rhs_convergence_status(trace, "full_variational"))
trace$beta_cov_relative_delta[[10L]] <- 0; trace$objective_delta_per_observation[[10L]] <- 1e-4
stopifnot(!app_pricefm_rhs_convergence_status(trace, "full_variational"))

# Independent Monte Carlo check of E_q[log joint - log q], including the product slab factor.
N <- 50000L; p <- stats$p; active <- 2:p; st <- full$beta_prior$state
draw_ig <- function(a, b) 1 / rgamma(N, shape = a, rate = b)
log_ig <- function(x, a, b) a * log(b) - lgamma(a) - (a + 1) * log(x) - b / x
beta <- sweep(matrix(rnorm(N * p), N, p) %*% chol(full$beta$cov), 2, full$beta$mean, "+")
omega <- draw_ig(full$omega2$a, full$omega2$b)
tau <- draw_ig(st$a_tau, st$b_tau); xi <- draw_ig(st$a_xi, st$b_xi)
slab <- draw_ig(st$a_zeta, st$b_zeta)
lam <- sapply(active, function(j) draw_ig(st$a_lambda[j], st$b_lambda[j]))
nu <- sapply(active, function(j) draw_ig(st$a_nu[j], st$b_nu[j]))
sse <- stats$yty - 2 * as.numeric(beta %*% stats$Xty) + rowSums((beta %*% stats$XtX) * beta)
log_joint <- -.5 * stats$n * (log(2 * pi) + log(omega)) - .5 * sse / omega +
  log_ig(omega, 2, 1) + dnorm(beta[, 1], 0, 1e8, log = TRUE) +
  log_ig(tau, .5, 1 / xi) + log_ig(xi, .5, 1 / .05^2) + log_ig(slab, 2, 1)
log_q <- log_ig(omega, full$omega2$a, full$omega2$b) + log_ig(tau, st$a_tau, st$b_tau) +
  log_ig(xi, st$a_xi, st$b_xi) + log_ig(slab, st$a_zeta, st$b_zeta)
for (j in seq_along(active)) {
  k <- active[j]
  log_joint <- log_joint + dnorm(beta[, k], 0, sqrt(tau * lam[, j]), log = TRUE) +
    dnorm(0, beta[, k], sqrt(slab), log = TRUE) + log_ig(lam[, j], .5, 1 / nu[, j]) +
    log_ig(nu[, j], .5, 1)
  log_q <- log_q + log_ig(lam[, j], st$a_lambda[k], st$b_lambda[k]) +
    log_ig(nu[, j], st$a_nu[k], st$b_nu[k])
}
centered <- sweep(beta, 2, full$beta$mean, "-")
precision <- solve(full$beta$cov)
log_q <- log_q - .5 * p * log(2 * pi) - .5 * as.numeric(determinant(full$beta$cov, logarithm = TRUE)$modulus) -
  .5 * rowSums((centered %*% precision) * centered)
samples <- log_joint - log_q
exact <- tail(full$trace$total_objective, 1)
stopifnot(abs(mean(samples) - exact) < 6 * sd(samples) / sqrt(N))
cat(sprintf("RHS stationarity tests passed; Monte Carlo objective %.8f, analytic %.8f, SE %.8f\n",
  mean(samples), exact, sd(samples) / sqrt(N)))
