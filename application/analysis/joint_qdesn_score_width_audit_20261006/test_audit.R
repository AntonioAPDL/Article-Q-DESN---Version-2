set.seed(13)
loss <- matrix(rnorm(900), 300, 3)
chain <- rep(1:3, each = 100)
d <- joint_width_decompose(loss, chain)
stopifnot(abs(d$summary$total_variance - stats::var(rowSums(loss))) < 1e-12,
  abs(d$summary$between_chain_variance_fraction + d$summary$within_chain_variance_fraction - 1) < 1e-12)
common <- rnorm(300)
correlated <- sweep(loss, 1L, 5 * common, "+")
stopifnot(joint_width_decompose(correlated, chain)$summary$covariance_fraction > .5)
Z <- matrix(rnorm(20), 10, 2)
beta <- matrix(rnorm(120), 20, 6)
alpha <- matrix(rnorm(60), 20, 3)
y <- matrix(rnorm(500), 50, 10)
sorted <- apply(y, 2, sort)
oracle <- list(sorted_response = sorted, prefix_response = apply(sorted, 2, cumsum),
  observed_y = rnorm(10), true_q = matrix(0, 10, 3))
tau <- c(.1, .5, .9); weights <- c(.2, .4, .2)
map <- data.frame(origin_index = rep(1:2, each = 5), horizon = rep(1:5, 2))
actual <- joint_width_reconstruct(Z, beta, alpha, oracle, tau, weights, map, chunk_size = 7L)
reference <- app_joint_recursive_score_draws(Z, beta, alpha, oracle, tau, weights,
  chunk_size = 5L, chain_id = rep(1:2, each = 10))
stopifnot(max(abs(rowSums(actual$loss) - reference$origin_marginal_dgp_integrated_acrps)) < 1e-10,
  max(abs(rowSums(actual$loss) - rowMeans(actual$lead))) < 1e-10,
  identical(dim(actual$origin_q), c(5L, 20L, 3L)))
p <- joint_width_projection(Z, Z, Z, beta, alpha, tau)
stopifnot(all(abs(p$forecast_fit_variance_ratio - 1) < 1e-12),
  all(abs(p$native_common_variance_ratio - 1) < 1e-12))
cat("PASS: covariance identity, chain variance identity, frozen score reconstruction, horizon aggregation, readout projection.\n")
