script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- sub("^--file=", "", script_arg[[1L]])
repo_root <- normalizePath(file.path(dirname(normalizePath(script_path)), "..", ".."))
source(file.path(repo_root, "application/R/pricefm_recursive_normal_fit.R"))

set.seed(19)
X <- cbind(1, matrix(rnorm(120 * 5), 120, 5))
y <- as.numeric(X %*% c(0.5, -0.2, 0.1, 0.3, 0, -0.1) + rnorm(120, sd = 0.4))
stats <- app_pricefm_normal_stats_from_design(X, y)
fit <- app_pricefm_fit_scaled_ridge_stats(stats)

P0 <- diag(c(1e-6, rep(1e-4, ncol(X) - 1L)))
Pn <- P0 + crossprod(X)
expected_mean <- as.numeric(solve(Pn, crossprod(X, y)))
stopifnot(max(abs(fit$beta$mean - expected_mean)) < 1e-10)
stopifnot(isTRUE(fit$converged), isTRUE(fit$exact_closed_form))
stopifnot(all(is.finite(fit$beta$cov)), fit$omega2$a == 62)

mock_prior <- function(type, rhs = list()) {
  stopifnot(identical(type, "rhs_ns"), !isTRUE(rhs$shrink_intercept))
  list(
    type = type,
    hypers = list(tau0 = rhs$tau0, shrink_intercept = FALSE),
    init = function(p) list(p = p, calls = 0L),
    expected_prec = function(state, p) c(1e-16, rep(1 / rhs$tau0^2, p - 1L)),
    update = function(state, qbeta) { state$calls <- state$calls + 1L; state }
  )
}
rhs <- app_pricefm_fit_rhs_stats(
  stats, tau0 = 0.5, beta_prior_factory = mock_prior,
  max_iter = 8L, min_iter = 2L, tol = 1e9
)
stopifnot(isTRUE(rhs$converged), nrow(rhs$trace) == 2L)
stopifnot(identical(rhs$initialization_contract, "scaled_ridge_initialization_only_prior_unchanged"))
stopifnot(rhs$beta_prior$hypers$tau0 == 0.5, rhs$beta_prior$state$calls == 2L)

bad <- stats
bad$Xty <- bad$Xty[-1L]
stopifnot(inherits(try(app_pricefm_fit_scaled_ridge_stats(bad), silent = TRUE), "try-error"))
cat("PriceFM recursive Normal sufficient-statistic fit tests passed.\n")
