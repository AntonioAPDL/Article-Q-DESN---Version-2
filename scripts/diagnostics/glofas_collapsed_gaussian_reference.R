# Generated conditional/affine Gaussian reference for the marginal AL target.
# No authentic inputs, auxiliary-variable approximation, production updates,
# fitting entry point or scientific launch is present. This is not a drop-in
# nonlinear/unknown-parameter, exAL or multiquantile variational algorithm.

gcgr_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste0("Collapsed Gaussian reference: ", message), call. = FALSE)
}

gcgr_expand <- function(x, n, name) {
  gcgr_require(is.numeric(x) && length(x) %in% c(1L, n) && all(is.finite(x)),
    paste0("finite scalar/aligned ", name, " required"))
  rep(x, length.out = n)
}

gcgr_expected_check_loss <- function(residual_mean, residual_sd, p) {
  e <- as.numeric(residual_mean); n <- length(e)
  gcgr_require(n > 0L && all(is.finite(e)), "finite residual means required")
  s <- gcgr_expand(residual_sd, n, "residual standard deviations")
  p <- gcgr_expand(p, n, "probabilities")
  gcgr_require(all(s >= 0) && all(p > 0 & p < 1), "nonnegative sd/interior probability required")
  out <- e * (p - (e < 0))
  active <- s > 0
  z <- e[active] / s[active]
  out[active] <- s[active] * stats::dnorm(z) + e[active] * (p[active] - stats::pnorm(-z))
  out
}

gcgr_single_al_optimum <- function(p, sigma = 1, mu = 0) {
  gcgr_require(length(p) == 1L && is.finite(p) && p > 0 && p < 1 &&
    length(sigma) == 1L && is.finite(sigma) && sigma > 0 &&
    length(mu) == 1L && is.finite(mu), "one valid fixed AL target required")
  z <- stats::qnorm(p); s <- sigma / stats::dnorm(z); m <- mu - s * z
  loss <- gcgr_expected_check_loss(m - mu, s, p)
  list(mean = m, sd = s, variance = s^2, target_probability = p,
    target_quantile = mu, Gaussian_target_quantile = m + s * z,
    collapsed_KL = -log(p * (1 - p) / sigma) + loss / sigma -
      .5 * log(2 * pi * exp(1) * s^2),
    interpretation = "reverse-KL Gaussian matches this AL probability level, not the full AL distribution")
}

gcgr_affine_contract <- function(A, offset = 0, p = .5, scale = 1) {
  A <- as.matrix(A); H <- ncol(A); N <- nrow(A)
  gcgr_require(is.numeric(A) && H %in% 1:2 && N >= H && N <= 128L && all(is.finite(A)),
    "generated one/two-dimensional affine factors only (at most 128 rows)")
  offset <- gcgr_expand(offset, N, "offsets")
  p <- gcgr_expand(p, N, "probabilities")
  scale <- gcgr_expand(scale, N, "AL scales")
  gcgr_require(all(p > 0 & p < 1) && all(scale > 0) && qr(A)$rank == H,
    "positive scales/interior probabilities/full-rank affine rows required")
  structure(list(A = A, offset = offset, p = p, scale = scale, H = H,
    mode = "generated_affine_only", factor_weights = rep(1, N),
    parameter_uncertainty = "fixed_parameters_only"), class = "gcgr_affine_contract")
}

gcgr_affine_objective <- function(mean, covariance, contract) {
  c <- contract; m <- as.numeric(mean); V <- as.matrix(covariance)
  gcgr_require(inherits(c, "gcgr_affine_contract") && identical(c$mode, "generated_affine_only") &&
    length(m) == c$H && all(is.finite(m)) && identical(dim(V), c(c$H, c$H)) &&
    all(is.finite(V)) && max(abs(V - t(V))) < 1e-12, "aligned finite symmetric Gaussian state required")
  R <- tryCatch(chol(V), error = function(e) NULL)
  gcgr_require(!is.null(R), "strictly positive-definite covariance required")
  e <- as.numeric(c$offset + c$A %*% m)
  variance <- rowSums((c$A %*% V) * c$A)
  active <- rowSums(c$A^2) > 0
  gcgr_require(all(variance[active] > 0), "nonconstant affine residuals need positive variance")
  s <- sqrt(pmax(variance, 0)); z <- numeric(length(e)); z[active] <- e[active] / s[active]
  # Constant factors contribute their literal check loss but no derivative of
  # the Gaussian approximation. This also handles A=0 and offset=0 exactly.
  dm <- dv <- numeric(length(e))
  dm[active] <- (c$p[active] - stats::pnorm(-z[active])) / c$scale[active]
  dv[active] <- stats::dnorm(z[active]) / (c$scale[active] * s[active])
  Vinv <- chol2inv(R)
  list(value = sum(gcgr_expected_check_loss(e, s, c$p) / c$scale) - sum(log(diag(R))),
    mean_gradient = as.numeric(crossprod(c$A, dm)),
    covariance_gradient = .5 * crossprod(c$A, sweep(c$A, 1L, dv, "*")) - .5 * Vinv,
    residual_mean = e, residual_sd = s,
    interpretation = "exact expected marginal-AL check loss minus Gaussian entropy; additive constants omitted")
}

gcgr_unpack <- function(parameters, H) {
  if (H == 1L) {
    L <- matrix(exp(parameters[2L]), 1L, 1L)
  } else {
    L <- matrix(c(exp(parameters[3L]), parameters[4L], 0, exp(parameters[5L])), 2L, 2L)
  }
  list(mean = parameters[seq_len(H)], L = L, covariance = tcrossprod(L))
}

gcgr_affine_optimize <- function(contract, initial_mean = rep(0, contract$H),
                                 initial_covariance = diag(contract$H), max_iterations = 1000L) {
  gcgr_affine_objective(initial_mean, initial_covariance, contract)
  gcgr_require(length(max_iterations) == 1L && is.finite(max_iterations) &&
    max_iterations >= 1 && max_iterations <= 2000 && max_iterations == floor(max_iterations),
    "bounded generated optimizer iterations required")
  H <- contract$H; L <- t(chol(initial_covariance))
  initial <- if (H == 1L) c(initial_mean, log(L[1L, 1L])) else
    c(initial_mean, log(L[1L, 1L]), L[2L, 1L], log(L[2L, 2L]))
  value <- function(parameters) {
    u <- gcgr_unpack(parameters, H)
    if (any(!is.finite(u$covariance)) || any(diag(u$L) <= 0)) return(1e100)
    gcgr_affine_objective(u$mean, u$covariance, contract)$value
  }
  gradient <- function(parameters) {
    u <- gcgr_unpack(parameters, H); obj <- gcgr_affine_objective(u$mean, u$covariance, contract)
    dL <- 2 * obj$covariance_gradient %*% u$L
    if (H == 1L) c(obj$mean_gradient, dL[1L, 1L] * u$L[1L, 1L]) else
      c(obj$mean_gradient, dL[1L, 1L] * u$L[1L, 1L], dL[2L, 1L], dL[2L, 2L] * u$L[2L, 2L])
  }
  fit <- stats::optim(initial, value, gradient, method = "BFGS",
    control = list(maxit = max_iterations, reltol = 1e-13))
  u <- gcgr_unpack(fit$par, H); obj <- gcgr_affine_objective(u$mean, u$covariance, contract)
  norm <- max(abs(c(obj$mean_gradient, obj$covariance_gradient)))
  list(mean = as.numeric(u$mean), covariance = u$covariance, objective = obj$value,
    optimizer_code = fit$convergence, maximum_stationarity_residual = norm,
    objective_counts = fit$counts,
    status = if (fit$convergence == 0L && norm < 1e-5) "GENERATED_COLLAPSED_GAUSSIAN_STATIONARY" else
      "INCONCLUSIVE_GENERATED_OPTIMIZATION",
    authentic_reads = 0L, full_parameter_refits = 0L,
    interpretation = "conditional/affine approximation candidate only; stationary does not mean exact posterior")
}

gcgr_smoothing_contract <- function(n_members = 51L) {
  gcgr_require(length(n_members) == 1L && n_members %in% c(1L, 51L),
    "generated smoothing fixture uses one or 51 ordinary members")
  n <- as.integer(n_members)
  A <- rbind(diag(2L), matrix(0, n, 2L), matrix(rep(c(-.05, 0), n), n, 2L, byrow = TRUE))
  gcgr_affine_contract(A, offset = c(0, 0, rep(-.1, 2L * n)), p = .5,
    scale = c(.07, .07, rep(.05, 2L * n)))
}

gcgr_gaussian_kl <- function(mean, covariance, target_mean, target_covariance) {
  m <- as.numeric(mean); mu <- as.numeric(target_mean); V <- as.matrix(covariance)
  S <- as.matrix(target_covariance); d <- length(m)
  gcgr_require(length(mu) == d && identical(dim(V), c(d, d)) && identical(dim(S), c(d, d)) &&
    all(is.finite(c(m, mu, V, S))) && max(abs(V - t(V))) < 1e-12 &&
    max(abs(S - t(S))) < 1e-12, "aligned finite symmetric Gaussian KL inputs required")
  RV <- tryCatch(chol(V), error = function(e) NULL); RS <- tryCatch(chol(S), error = function(e) NULL)
  gcgr_require(!is.null(RV) && !is.null(RS), "Gaussian KL covariance matrices must be SPD")
  P <- chol2inv(RS); delta <- m - mu
  .5 * (sum(P * t(V)) + as.numeric(crossprod(delta, P %*% delta)) - d +
    2 * sum(log(diag(RS))) - 2 * sum(log(diag(RV))))
}

gcgr_normal_coupled_reference <- function(mean0 = .4, covariance0 = matrix(1.1),
                                         x = 1, observation_variance = .8) {
  mu <- as.numeric(mean0); V <- as.matrix(covariance0); x <- as.numeric(x); P <- length(mu)
  gcgr_require(P %in% 1:2 && length(x) == P && identical(dim(V), c(P, P)) &&
    all(is.finite(c(mu, V, x))) && max(abs(V - t(V))) < 1e-12 && length(observation_variance) == 1L &&
    is.finite(observation_variance) && observation_variance > 0,
    "one/two uncertain Normal coefficients and one normalized future transition required")
  C <- tryCatch(chol(V), error = function(e) NULL)
  gcgr_require(!is.null(C), "coefficient prior covariance must be SPD")
  cross <- as.numeric(V %*% x)
  S <- rbind(cbind(V, cross), c(cross, sum(x * cross) + observation_variance))
  joint_mean <- c(mu, sum(x * mu))
  # In coordinates epsilon = Y - x'theta, the normalized future transition
  # is independent of theta and the transformation has determinant one.
  transform <- rbind(cbind(diag(P), rep(0, P)), c(x, 1))
  independent_coordinates <- diag(P + 1L)
  independent_coordinates[seq_len(P), seq_len(P)] <- V
  independent_coordinates[P + 1L, P + 1L] <- observation_variance
  constructed <- transform %*% independent_coordinates %*% t(transform)
  mf_theta <- solve(chol2inv(C) + tcrossprod(x) / observation_variance)
  mf_covariance <- matrix(0, P + 1L, P + 1L)
  mf_covariance[seq_len(P), seq_len(P)] <- mf_theta
  mf_covariance[P + 1L, P + 1L] <- observation_variance
  list(mean = joint_mean, covariance = S, covariance_from_independent_residual = constructed,
    coefficient_marginal_mean = mu, coefficient_marginal_covariance = S[seq_len(P), seq_len(P), drop = FALSE],
    theta_future_cross_covariance = cross, coefficient_prior_covariance = V,
    independent_future_block_theta_covariance = mf_theta,
    independent_future_block_joint_covariance = mf_covariance,
    coupled_KL = gcgr_gaussian_kl(joint_mean, constructed, joint_mean, S),
    independent_future_block_KL = gcgr_gaussian_kl(joint_mean, mf_covariance, joint_mean, S),
    closed_form_independent_KL = .5 * log1p(sum(x * cross) / observation_variance),
    original_reads = 0L, full_parameter_refits = 0L,
    interpretation = "joint Gaussian theta,Y retains normalized no-ensemble theta marginal; q(Y) independent of theta does not")
}
