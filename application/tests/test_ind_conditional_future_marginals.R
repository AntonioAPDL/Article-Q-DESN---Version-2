# Deterministic synthetic checks: no retained models, forecasts or truth read.
source("scripts/ind_conditional_filter_replay.R")
source("scripts/ind_conditional_future_marginals.R")
cfm_n <- 0L
cfm_check <- function(ok) { stopifnot(isTRUE(ok)); cfm_n <<- cfm_n + 1L }
cfm_close <- function(x, y, tolerance = 1e-11) {
  isTRUE(all.equal(x, y, tolerance = tolerance, check.attributes = FALSE))
}
cfm_reject <- function(expr) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  cfm_check(inherits(error, "error"))
}
set.seed(90351L); cfm_rng <- .Random.seed
scalar <- list(m_origin = 0, C_origin = matrix(1, 1L),
  FF = matrix(1, 1L, 2L), GG = matrix(1, 1L), ex_f = c(0, 0),
  ex_q = c(1, 1), df_mat = matrix(.25, 1L), future_features = "known_deterministic")
sf <- do.call(ind_cfm_future, scalar)
cfm_check(cfm_close(sf$state_covariance[,,1L], 5/4))
cfm_check(cfm_close(sf$auxiliary_covariance[,,1L], 5/9))
cfm_check(cfm_close(sf$effective_innovation[,,2L], 5/36))
cfm_check(cfm_close(sf$state_covariance[,,2L], 25/18))
cfm_check(cfm_close(sf$response_variance[2L], 43/18))
cfm_check(!cfm_close(sf$response_variance[2L], 61/36))
cfm_check(!cfm_close(sf$response_variance[2L], 41/16))
cfm_check(sf$Gaussian_states_integrated && sf$intermediate_responses_integrated &&
  !sf$auxiliaries_integrated && !sf$origin_filter_integrated && !sf$production_authorized &&
  !sf$trajectory_joint_law_returned && !sf$numerical_Q_floor_allowed)
cfm_check(sf$random_draws_generated == 0L && sf$new_model_fits == 0L)

# First-horizon parity and independent covariance-control replay throughout.
replay <- ind_cfr_cpp_forward(c(10, -2), scalar$FF, scalar$GG, 0, scalar$C_origin,
  scalar$ex_f, scalar$ex_q, scalar$df_mat, 2L)
cfm_check(cfm_close(sf$state_covariance[,,1L], replay$lineage$R[,,1L]))
cfm_check(cfm_close(sf$response_mean[1L], replay$lineage$f[1L]))
cfm_check(cfm_close(sf$response_variance[1L], replay$lineage$Q[1L]))
cfm_check(cfm_close(sf$auxiliary_covariance, replay$fC))
cfm_check(cfm_close(sf$effective_innovation, replay$lineage$W))

# Unit discount adds no future state innovations; future responses are not
# assimilated merely because their auxiliary covariances are propagated.
unit <- scalar; unit$df_mat[] <- 0; unit$m_origin <- 3
uf <- do.call(ind_cfm_future, unit)
cfm_check(all(uf$effective_innovation == 0))
cfm_check(cfm_close(uf$state_covariance, array(1, c(1L, 1L, 2L))))
cfm_check(cfm_close(uf$response_mean, c(3, 3)))
cfm_check(cfm_close(uf$response_variance, c(2, 2)))
cfm_check(cfm_close(uf$auxiliary_covariance, array(c(.5, 1/3), c(1L,1L,2L))))

# Time-varying, noncommuting dynamics. Construct the full joint Gaussian
# state law independently by linear maps of the origin and innovations.
G <- array(c(1, .3, -.2, .9, .8, -.1, .4, 1.2, 1.1, .2, -.3, .7), c(2L,2L,3L))
F <- matrix(c(1, .2, -.4, 1, .7, -.3), 2L, 3L)
C0 <- matrix(c(2, .3, .3, .8), 2L)
m0 <- c(.4, -1)
off <- c(.2, -.5, .1); noise <- c(.8, 1.3, .5)
D <- ind_cfr_discount_matrix(c(.8, .9), c(1L,1L))
tf <- ind_cfm_future(m0, C0, F, G, off, noise, D, "known_deterministic")
tr <- ind_cfr_cpp_forward(c(5, 7, -1), F, G, m0, C0, off, noise, D, 3L)
cfm_check(cfm_close(tf$auxiliary_covariance, tr$fC))
cfm_check(cfm_close(tf$effective_innovation, tr$lineage$W))
cfm_check(cfm_close(tf$state_covariance[,,1L], tr$lineage$R[,,1L]))
block_cov <- matrix(0, 8L, 8L)
block_cov[1:2, 1:2] <- C0
for (h in 1:3) block_cov[(2*h+1):(2*h+2), (2*h+1):(2*h+2)] <- tr$lineage$W[,,h]
maps <- vector("list", 3L)
previous_map <- cbind(diag(2), matrix(0, 2L, 6L))
state_mean <- m0
for (h in 1:3) {
  maps[[h]] <- G[,,h] %*% previous_map
  maps[[h]][, (2*h+1):(2*h+2)] <- diag(2)
  state_mean <- as.numeric(G[,,h] %*% state_mean)
  assembled <- maps[[h]] %*% block_cov %*% t(maps[[h]])
  cfm_check(cfm_close(tf$state_covariance[,,h], assembled))
  cfm_check(cfm_close(tf$state_mean[,h], state_mean))
  cfm_check(cfm_close(tf$response_mean[h], sum(F[,h]*state_mean) + off[h]))
  cfm_check(cfm_close(tf$response_variance[h],
    as.numeric(t(F[,h]) %*% assembled %*% F[,h]) + noise[h]))
  previous_S <- if (h == 1L) C0 else tf$state_covariance[,,h-1L]
  previous_C <- if (h == 1L) C0 else tf$auxiliary_covariance[,,h-1L]
  expected_gap <- G[,,h] %*% (previous_S - previous_C) %*% t(G[,,h])
  cfm_check(cfm_close(tf$state_covariance[,,h] - tf$auxiliary_predictive_covariance[,,h], expected_gap))
  cfm_check(min(eigen(expected_gap, symmetric = TRUE, only.values = TRUE)$values) >= -1e-12)
  previous_map <- maps[[h]]
}
# Scalar total-variance identity reproduces the second-horizon marginal.
response_cov12 <- 5/4; response_var1 <- 9/4
cfm_check(cfm_close(43/18 - response_cov12^2 / response_var1, 61/36))
cfm_check(cfm_close(response_cov12^2 / response_var1, 25/36))

# Extending or altering later future inputs cannot change earlier marginals.
prefix <- ind_cfm_future(m0, C0, F[,1:2,drop=FALSE], G[,,1:2,drop=FALSE],
  off[1:2], noise[1:2], D, "known_deterministic")
later_F <- F; later_F[,3] <- c(20, -99)
later <- ind_cfm_future(m0, C0, later_F, G, c(off[1:2], 300), noise, D, "known_deterministic")
for (key in c("response_mean", "response_variance", "auxiliary_forecast_variance")) {
  cfm_check(identical(prefix[[key]], tf[[key]][1:2]))
  cfm_check(identical(later[[key]][1:2], tf[[key]][1:2]))
}
for (key in c("state_covariance", "auxiliary_covariance", "effective_innovation")) {
  cfm_check(identical(prefix[[key]], tf[[key]][,,1:2,drop=FALSE]))
  cfm_check(identical(later[[key]][,,1:2,drop=FALSE], tf[[key]][,,1:2,drop=FALSE]))
}

# Reject unsupported response-dependent future predictors, malformed shapes,
# material non-PSD matrices and Q-floor cases rather than changing the law.
for (mutate in list(
  function(a) { a$future_features <- "response_dependent"; a },
  function(a) { a$future_features <- NULL; a },
  function(a) { a$GG <- matrix(1, 1L, 2L); a },
  function(a) { a$ex_f <- 0; a },
  function(a) { a$ex_q <- c(1, -1); a },
  function(a) { a$ex_q <- c(NA, 1); a },
  function(a) { a$C_origin[] <- -1; a },
  function(a) { a$df_mat[] <- -1; a },
  function(a) { a$C_origin[] <- 0; a$ex_q[] <- 0; a },
  function(a) { a$tolerance <- 0; a }
)) cfm_reject(do.call(ind_cfm_future, mutate(scalar)))
cfm_reject(ind_cfm_future(0, matrix(1,1L), matrix(1,1L), matrix(1,1L), 0, 1, matrix(0,1L)))
cfm_reject(ind_cfm_future(c(0,0), matrix(c(1,.5,0,1),2L), matrix(1,2L,1L),
  diag(2), 0, 1, diag(2), "known_deterministic"))
huge <- scalar; huge$C_origin[] <- 1e9
cfm_check(do.call(ind_cfm_future, huge)$state_covariance[,,1L] > 1e8)

# Unequal component weights, zero-weight components, and stable normalization.
means <- c(-2, 1, 6); variances <- c(.7, 2, .3); weights <- c(.375, .375, .25)
xx <- c(-Inf, -3, 0, 2, 7, Inf)
expected_cdf <- vapply(xx, function(x) sum(weights*pnorm(x, means, sqrt(variances))), numeric(1L))
cfm_check(cfm_close(ind_cfm_mixture_cdf(xx, means, variances, weights), expected_cdf))
cfm_check(cfm_close(ind_cfm_mixture_cdf(xx, means, variances, weights*1e300), expected_cdf))
cfm_check(cfm_close(ind_cfm_mixture_cdf(xx, c(means, 100), c(variances, 1), c(weights,0)), expected_cdf))
cfm_check(cfm_close(ind_cfm_mixture_cdf(xx, rev(means), rev(variances), rev(weights)), expected_cdf))
cfm_check(cfm_close(ind_cfm_mixture_cdf(xx, c(-2,-2,1,6), c(.7,.7,2,.3),
  c(.1875,.1875,.375,.25)), expected_cdf))
cfm_check(cfm_close(ind_cfm_origin_path_weights(c(.75, .25), c(1, 1, 2)), weights))
cfm_check(cfm_close(ind_cfm_origin_path_weights(c(3, 1, 0), c(1, 2, 1)), c(.375, .25, .375)))
cfm_check(cfm_close(sum(ind_cfm_origin_path_weights(c(3, 1, 0), c(1, 2, 1))), 1))
cfm_reject(ind_cfm_origin_path_weights(c(.75, .25), c(1, 1)))
cfm_reject(ind_cfm_origin_path_weights(c(.75, .25), c(1, 2.5)))
cfm_reject(ind_cfm_origin_path_weights(c(.75, .25), c(1, 3)))
cfm_reject(ind_cfm_origin_path_weights(c(0, 0), c(1, 2)))

probs <- c(.0001, .05, .5, .95, .9999)
qi <- ind_cfm_mixture_quantile(probs, means, variances, weights, 1e-10, 1e-12)
cfm_check(all(qi$result$upper - qi$result$lower <= qi$result$width_tolerance))
cfm_check(all(qi$result$cdf_lower <= probs & qi$result$cdf_upper >= probs))
cfm_check(all(diff(qi$result$quantile) > 0))
cfm_check(!qi$particle_filter_accuracy_qualified && !qi$auxiliary_integral_accuracy_qualified &&
  !qi$production_authorized && qi$random_draws_generated == 0L)
cfm_check(cfm_close(qi$normalized_component_weights, weights))
one <- ind_cfm_mixture_quantile(probs, 3, 4, 7, 1e-10, 1e-12)
cfm_check(cfm_close(one$result$quantile, 3 + 2*qnorm(probs), 1e-9))
perm <- ind_cfm_mixture_quantile(probs, rev(means), rev(variances), rev(weights), 1e-10, 1e-12)
cfm_check(cfm_close(qi$result$quantile, perm$result$quantile, 1e-9))
avg_quantile <- sum(weights * (means + sqrt(variances)*qnorm(.5)))
cfm_check(abs(qi$result$quantile[3L] - avg_quantile) > .1)
for (args in list(
  list(mean=1,variance=0,weight=1), list(mean=1,variance=1,weight=-1),
  list(mean=c(1,2),variance=1,weight=c(1,1)), list(mean=1,variance=1,weight=0),
  list(mean=NA_real_,variance=1,weight=1), list(mean=1,variance=Inf,weight=1)
)) cfm_reject(do.call(ind_cfm_normal_mixture, args))
cfm_reject(ind_cfm_mixture_cdf(NA_real_, 0, 1, 1))
cfm_reject(ind_cfm_normal_mixture(c(0,1), c(1,1), c(1e-308,1e308)))
cfm_reject(ind_cfm_mixture_quantile(0, 0, 1, 1, 1e-10, 0))
cfm_reject(ind_cfm_mixture_quantile(.5, 0, 1, 1, 0, 0))
cfm_reject(ind_cfm_mixture_quantile(.5, means, variances, weights, 1e-16, 0, max_iterations=1))
cfm_reject(ind_cfm_mixture_quantile(.5, c(-100, 100), c(1, 1), c(1, 1), 1e-10, 1e308))
cfm_check(identical(.Random.seed, cfm_rng))
cat(sprintf("IND_CONDITIONAL_FUTURE_MARGINAL_CHECKS=%d PASS; protected_reads=0 fits=0 production_forecasts=0\n", cfm_n))
