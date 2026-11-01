# Independent finite-mixture composition proof. No fitted objects or data.
source("scripts/ind_conditional_auxiliary_filter.R")
source("scripts/ind_conditional_future_marginals.R")
ffc_n <- 0L
ffc_check <- function(ok) { stopifnot(isTRUE(ok)); ffc_n <<- ffc_n + 1L }
ffc_close <- function(x, y, tolerance = 1e-12)
  isTRUE(all.equal(x, y, tolerance = tolerance, check.attributes = FALSE))
set.seed(82349L); ffc_rng <- .Random.seed

# Enumerate the two independent, equiprobable auxiliary variances at each
# observed time. Repeated first-time histories carry their prior mass.
variance_history <- as.matrix(expand.grid(c(.5, 2), c(.5, 2)))
y <- c(.6, -.3)
filtered <- ind_caf_filter_moments(y, matrix(1, 1L, 2L), matrix(1, 1L),
  0, matrix(1, 1L), matrix(.25, 1L), .1 * variance_history,
  variance_history, 2L, "synthetic-column-1", "finite_prior_fixture",
  2L, c(.2, .7), ess_fraction = 0)
origin <- filtered$checkpoints[["2"]]

# Derive the training mixture independently from each component's joint
# bivariate Gaussian observation law, not from the filtering implementation.
log_density <- origin_mean <- origin_variance <- numeric(4L)
for (j in seq_len(4L)) {
  R1 <- 5/4
  C1 <- R1 * variance_history[j, 1L] / (R1 + variance_history[j, 1L])
  S2 <- R1 + C1 / 4
  B <- matrix(c(R1 + variance_history[j, 1L], R1, R1,
    S2 + variance_history[j, 2L]), 2L)
  residual <- y - .1 * variance_history[j, ]
  cross <- c(R1, S2)
  log_density[j] <- -log(2*pi) - .5 * as.numeric(determinant(B, logarithm = TRUE)$modulus) -
    .5 * as.numeric(t(residual) %*% solve(B, residual))
  origin_mean[j] <- sum(cross * solve(B, residual))
  origin_variance[j] <- S2 - sum(cross * solve(B, cross))
}
omega <- exp(log_density - max(log_density)); omega <- omega / sum(omega)
ffc_check(ffc_close(origin$weights, omega))
ffc_check(ffc_close(as.numeric(origin$mean), origin_mean))
ffc_check(ffc_close(as.numeric(origin$covariance), origin_variance))

# Four equiprobable future histories per origin component. Repeat each
# history j times for component j: the resulting counts 4,8,12,16 must not
# change origin weights. The finite grid is an exact mathematical fixture,
# not a claim about continuous AL/exAL integration accuracy.
component <- integer(); mu <- variance <- numeric()
for (j in seq_len(4L)) for (k in seq_len(4L)) for (copy in seq_len(j)) {
  future <- ind_cfm_future(as.numeric(origin$mean[, j]),
    matrix(origin$covariance[, , j], 1L), matrix(1, 1L, 2L),
    matrix(1, 1L), .1 * variance_history[k, ], variance_history[k, ],
    matrix(.25, 1L), "known_deterministic")
  mu <- c(mu, future$response_mean[2L])
  variance <- c(variance, future$response_variance[2L])
  component <- c(component, j)
  ffc_check(!future$production_authorized && !future$auxiliaries_integrated &&
    !future$origin_filter_integrated && future$random_draws_generated == 0L)
}
weights <- ind_cfm_origin_path_weights(origin$weights, component)
ffc_check(identical(tabulate(component), c(4L, 8L, 12L, 16L)))
ffc_check(ffc_close(sum(weights), 1))
ffc_check(ffc_close(vapply(seq_len(4L), function(j) sum(weights[component == j]), numeric(1L)), omega))

x <- c(-3, -1, 0, 1, 3)
actual <- ind_cfm_mixture_cdf(x, mu, variance, weights)
# Independently propagate the unobserved future state variance. For fixed
# origin variance C and first future observation variance v1, C_aux,1 is
# R1*v1/(R1+v1), while the unobserved state variance at horizon 2 is
# R1+C_aux,1/4, not the covariance that conditions on a future observation.
expected <- vapply(x, function(value) sum(vapply(seq_len(4L), function(j) {
  R1 <- (5/4) * origin_variance[j]
  conditional_cdf <- vapply(seq_len(4L), function(k) {
    C_aux1 <- R1 * variance_history[k, 1L] / (R1 + variance_history[k, 1L])
    stats::pnorm(value, origin_mean[j] + .1 * variance_history[k, 2L],
      sqrt(R1 + C_aux1 / 4 + variance_history[k, 2L]))
  }, numeric(1L))
  omega[j] * sum(conditional_cdf) / 4
}, numeric(1L))), numeric(1L))
ffc_check(ffc_close(actual, expected))
ffc_check(all(diff(actual) > 0))
# Equal weighting over all paths would silently change the origin mixture.
unweighted <- ind_cfm_mixture_cdf(x, mu, variance, rep(1, length(mu)))
ffc_check(max(abs(unweighted - expected)) > 1e-3)
ffc_check(!filtered$parameter_weights_updated && !filtered$production_authorized &&
  !filtered$numerical_accuracy_qualified && filtered$new_model_fits == 0L &&
  filtered$random_draws_generated == 0L && filtered$forecast_paths_generated == 0L)
ffc_check(!origin$production_authorized && !origin$source_draw_inventory_authenticated &&
  origin$future_outcomes_used == 0L)
ffc_check(identical(.Random.seed, ffc_rng))
cat(sprintf("IND_FILTER_FUTURE_COMPOSITION_CHECKS=%d PASS; protected_reads=0 fits=0 production_launches=0 max_cdf_difference=%.17g\n",
  ffc_n, max(abs(actual - expected))))
