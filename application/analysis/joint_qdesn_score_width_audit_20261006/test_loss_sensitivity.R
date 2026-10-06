set.seed(781)
Z <- matrix(rnorm(20), 10, 2)
bm <- rnorm(6); am <- c(1, 0, -1)
y <- matrix(rnorm(1000), 100, 10)
sorted <- apply(y, 2L, sort)
oracle <- list(sorted_response = sorted, prefix_response = apply(sorted, 2L, cumsum),
  observed_y = rnorm(10), true_q = matrix(0, 10, 3))
tau <- c(.1, .5, .9); weights <- c(.2, .4, .2)
g <- joint_width_score_gradient(Z, bm, am, oracle, tau, weights)
db <- rnorm(6); da <- rnorm(3)
analytic <- sum(vapply(1:3, function(k) {
  sum(g$gradient[, k] * c(da[k], db[((k - 1L) * 2L + 1L):(k * 2L)]))
}, numeric(1L)))
evaluate <- function(eps) app_joint_recursive_canonical_metrics(Z, bm + eps * db,
  am + eps * da, oracle, tau, weights)$origin_marginal_dgp_integrated_acrps
numeric <- (evaluate(1e-6) - evaluate(-1e-6)) / 2e-6
stopifnot(abs(numeric - analytic) < 1e-7,
  all(is.finite(g$mean_abs_cdf_error)), all(g$mean_abs_cdf_error <= 1))
cat("PASS: DGP loss gradient and isotonic Jacobian match the frozen scorer's directional derivative.\n")
