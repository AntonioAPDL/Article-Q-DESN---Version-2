suppressPackageStartupMessages({
  library(pkgload)
})

package_path <- "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"
pkgload::load_all(package_path, quiet = TRUE, export_all = TRUE)
factory <- get("beta_prior", envir = asNamespace("exdqlm"), inherits = FALSE)

first <- factory("rhs_ns", rhs = list(
  tau0 = 1e-4, init_tau = 1, shrink_intercept = FALSE, intercept_prec = 1e-16
))
second <- factory("rhs_ns", rhs = list(
  tau0 = 1e-4, init_tau = 0.1, shrink_intercept = FALSE, intercept_prec = 1e-16
))
state_first <- first$init(5L)
state_second <- second$init(5L)

# d = p - 1 = 4 active slopes, so the corrected shape is (d + 1) / 2 = 2.5.
stopifnot(identical(first$hypers, second$hypers))
stopifnot(isFALSE(first$hypers$shrink_intercept))
stopifnot(isTRUE(all.equal(state_first$a_tau, 2.5, tolerance = 1e-12)))
stopifnot(isTRUE(all.equal(state_second$a_tau, 2.5, tolerance = 1e-12)))
stopifnot(!isTRUE(all.equal(state_first$tau2, state_second$tau2)))

source("application/R/pricefm_recursive_normal_fit.R")
toy <- list(
  n = 20L, p = 3L, XtX = diag(c(20, 10, 8)),
  Xty = c(2, 1, -1), yty = 15
)
fit <- app_pricefm_fit_rhs_stats(
  toy, tau0 = 1e-4, beta_prior_factory = factory,
  max_iter = 10L, min_iter = 2L, tol = 1e-2
)
stopifnot(identical(fit$initialization_contract, "scaled_ridge_initialization_only_prior_unchanged"))
stopifnot(isFALSE(fit$beta_prior$hypers$shrink_intercept))
stopifnot(isTRUE(all.equal(fit$beta_prior$state$a_tau, 1.5, tolerance = 1e-12)))
