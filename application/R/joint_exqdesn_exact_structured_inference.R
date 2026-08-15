# Exact scale-shape and structured-inference helpers for joint exQDESN.
#
# This module is intentionally additive. It is sourced after joint_qvp_qdesn.R
# and leaves every historical exAL entry point unchanged. New methods are
# available only through explicit immutable method identifiers.

.app_joint_exqdesn_cache <- new.env(parent = emptyenv())

app_joint_exqdesn_assert_scalar_tau <- function(tau) {
  tau <- app_joint_qvp_validate_tau_grid(tau)
  if (length(tau) != 1L) stop("This scale-shape operation requires one tau value.", call. = FALSE)
  tau[[1L]]
}

app_joint_exqdesn_logsumexp <- function(x) {
  x <- as.numeric(x)
  if (!length(x) || all(!is.finite(x))) return(-Inf)
  m <- max(x[is.finite(x)])
  m + log(sum(exp(x - m)))
}

app_joint_exqdesn_support <- function(tau) {
  tau <- app_joint_exqdesn_assert_scalar_tau(tau)
  key <- paste0("support_", format(tau, digits = 17, scientific = FALSE))
  if (!exists(key, envir = .app_joint_exqdesn_cache, inherits = FALSE)) {
    assign(key, app_joint_qvp_exal_support(tau), envir = .app_joint_exqdesn_cache)
  }
  get(key, envir = .app_joint_exqdesn_cache, inherits = FALSE)
}

app_joint_exqdesn_log_g <- function(gamma) {
  gamma <- as.numeric(gamma)
  if (any(!is.finite(gamma))) stop("gamma must be finite.", call. = FALSE)
  a <- abs(gamma)
  log(2) + stats::pnorm(-a, log.p = TRUE) + 0.5 * a^2
}

app_joint_exqdesn_mills_ratio <- function(a) {
  a <- abs(as.numeric(a))
  if (any(!is.finite(a))) stop("Mills-ratio arguments must be finite.", call. = FALSE)
  out <- exp(stats::dnorm(a, log = TRUE) - stats::pnorm(-a, log.p = TRUE))
  if (any(!is.finite(out))) {
    idx <- which(!is.finite(out))
    out[idx] <- a[idx] + 1 / pmax(a[idx], 1) + 2 / pmax(a[idx], 1)^3
  }
  out
}

app_joint_exqdesn_gamma_to_p_raw <- function(tau, gamma) {
  gamma <- as.numeric(gamma)
  g <- exp(app_joint_exqdesn_log_g(gamma))
  out <- ifelse(
    gamma < 0,
    1 - (1 - tau) / g,
    ifelse(gamma > 0, tau / g, tau)
  )
  pmin(pmax(out, .Machine$double.eps), 1 - .Machine$double.eps)
}

app_joint_exqdesn_dp_dgamma_raw <- function(tau, gamma, p_gamma = NULL) {
  gamma <- as.numeric(gamma)
  p_gamma <- as.numeric(p_gamma %||% app_joint_exqdesn_gamma_to_p_raw(tau, gamma))
  slope <- app_joint_exqdesn_mills_ratio(abs(gamma)) - abs(gamma)
  out <- ifelse(gamma < 0, (1 - p_gamma) * slope, p_gamma * slope)
  zero <- gamma == 0
  if (any(zero)) out[zero] <- sqrt(2 / pi) * pmin(tau, 1 - tau)
  out
}

app_joint_exqdesn_constants <- function(tau, gamma, check_support = TRUE) {
  tau <- app_joint_exqdesn_assert_scalar_tau(tau)
  gamma <- as.numeric(gamma)
  if (!length(gamma) || any(!is.finite(gamma))) stop("gamma must be finite and nonempty.", call. = FALSE)
  support <- app_joint_exqdesn_support(tau)
  if (isTRUE(check_support) && any(gamma <= support$lower[[1L]] | gamma >= support$upper[[1L]])) {
    stop("gamma lies outside the open exAL support.", call. = FALSE)
  }
  log_g <- app_joint_exqdesn_log_g(gamma)
  g <- exp(log_g)
  p_gamma <- app_joint_exqdesn_gamma_to_p_raw(tau, gamma)
  negative <- gamma < 0
  positive <- gamma > 0
  A <- (1 - 2 * p_gamma) / (p_gamma * (1 - p_gamma))
  B <- 2 / (p_gamma * (1 - p_gamma))
  lambda <- numeric(length(gamma))
  lambda[negative] <- abs(gamma[negative]) / (-p_gamma[negative])
  lambda[positive] <- gamma[positive] / (1 - p_gamma[positive])
  k <- 0.5 - p_gamma
  cp <- 0.5 * p_gamma * (1 - p_gamma)
  sd_factor <- sqrt(lambda^2 * (1 - 2 / pi) + A^2 + B)
  data.frame(
    gamma = gamma,
    log_g = log_g,
    g = g,
    p_gamma = p_gamma,
    A = A,
    B = B,
    lambda = lambda,
    k = k,
    cp = cp,
    sd_factor = sd_factor,
    branch = ifelse(negative, "negative", ifelse(positive, "positive", "zero")),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_dp_dgamma <- function(tau, gamma) {
  tau <- app_joint_exqdesn_assert_scalar_tau(tau)
  gamma <- as.numeric(gamma)
  support <- app_joint_exqdesn_support(tau)
  if (any(gamma <= support$lower[[1L]] | gamma >= support$upper[[1L]])) {
    stop("gamma lies outside the open exAL support.", call. = FALSE)
  }
  out <- app_joint_exqdesn_dp_dgamma_raw(tau, gamma)
  if (any(!is.finite(out) | out <= 0)) stop("p-gamma derivative is not positive and finite.", call. = FALSE)
  out
}

app_joint_exqdesn_gamma_to_p <- function(tau, gamma) {
  tau <- app_joint_exqdesn_assert_scalar_tau(tau)
  gamma <- as.numeric(gamma)
  support <- app_joint_exqdesn_support(tau)
  if (any(gamma <= support$lower[[1L]] | gamma >= support$upper[[1L]])) {
    stop("gamma lies outside the open exAL support.", call. = FALSE)
  }
  app_joint_exqdesn_gamma_to_p_raw(tau, gamma)
}

app_joint_exqdesn_p_bounds <- function(tau) {
  tau <- app_joint_exqdesn_assert_scalar_tau(tau)
  key <- paste0("p_bounds_", format(tau, digits = 17, scientific = FALSE))
  if (exists(key, envir = .app_joint_exqdesn_cache, inherits = FALSE)) {
    return(get(key, envir = .app_joint_exqdesn_cache, inherits = FALSE))
  }
  support <- app_joint_exqdesn_support(tau)
  width <- support$upper[[1L]] - support$lower[[1L]]
  padding <- max(1.0e-12, 64 * .Machine$double.eps * max(1, width))
  gamma_bounds <- c(
    lower = support$lower[[1L]] + padding,
    upper = support$upper[[1L]] - padding
  )
  p_bounds <- app_joint_exqdesn_gamma_to_p(tau, gamma_bounds)
  out <- c(lower = p_bounds[[1L]], upper = p_bounds[[2L]])
  if (any(!is.finite(out)) || out[["lower"]] <= 0 || out[["lower"]] >= tau ||
      out[["upper"]] <= tau || out[["upper"]] >= 1) {
    stop("Could not determine effective p-gamma bounds for the frozen native support.", call. = FALSE)
  }
  assign(key, out, envir = .app_joint_exqdesn_cache)
  out
}

app_joint_exqdesn_p_to_gamma <- function(tau, p_gamma, tol = 1.0e-12, max_iter = 40L) {
  tau <- app_joint_exqdesn_assert_scalar_tau(tau)
  p_gamma <- as.numeric(p_gamma)
  if (!length(p_gamma) || any(!is.finite(p_gamma)) || any(p_gamma <= 0 | p_gamma >= 1)) {
    stop("p_gamma must contain finite values in (0, 1).", call. = FALSE)
  }
  support <- app_joint_exqdesn_support(tau)
  p_bounds <- app_joint_exqdesn_p_bounds(tau)
  if (any(p_gamma < p_bounds[["lower"]] | p_gamma > p_bounds[["upper"]])) {
    stop("p_gamma lies outside the interval induced by the frozen native gamma support.", call. = FALSE)
  }
  padding <- max(1.0e-12, 16 * .Machine$double.eps *
    max(1, support$upper[[1L]] - support$lower[[1L]]))
  max_iter <- as.integer(max_iter)
  map_key <- paste0("p_inverse_map_", format(tau, digits = 17, scientific = FALSE))
  if (!exists(map_key, envir = .app_joint_exqdesn_cache, inherits = FALSE)) {
    map_size <- 4097L
    gamma_negative <- seq(support$lower[[1L]] + padding, 0, length.out = map_size)
    gamma_positive <- seq(0, support$upper[[1L]] - padding, length.out = map_size)
    inverse_map <- list(
      negative = data.frame(
        p_gamma = app_joint_exqdesn_gamma_to_p(tau, gamma_negative),
        gamma = gamma_negative
      ),
      positive = data.frame(
        p_gamma = app_joint_exqdesn_gamma_to_p(tau, gamma_positive),
        gamma = gamma_positive
      )
    )
    assign(map_key, inverse_map, envir = .app_joint_exqdesn_cache)
  }
  inverse_map <- get(map_key, envir = .app_joint_exqdesn_cache, inherits = FALSE)
  out <- numeric(length(p_gamma))
  zero <- abs(p_gamma - tau) <= tol
  out[zero] <- 0
  for (branch in c("negative", "positive")) {
    index <- if (branch == "negative") which(!zero & p_gamma < tau) else which(!zero & p_gamma > tau)
    if (!length(index)) next
    target <- p_gamma[index]
    map <- inverse_map[[branch]]
    x <- stats::approx(map$p_gamma, map$gamma, xout = target, rule = 2, ties = "ordered")$y
    lower <- rep(if (branch == "negative") support$lower[[1L]] + padding else 0, length(index))
    upper <- rep(if (branch == "negative") 0 else support$upper[[1L]] - padding, length(index))
    best <- x
    best_error <- rep(Inf, length(index))
    for (ii in seq_len(min(max_iter, 16L))) {
      value <- app_joint_exqdesn_gamma_to_p(tau, x) - target
      improved <- abs(value) < best_error
      best[improved] <- x[improved]
      best_error[improved] <- abs(value[improved])
      if (all(best_error <= tol)) break
      lower[value < 0] <- x[value < 0]
      upper[value >= 0] <- x[value >= 0]
      proposal <- x - value / app_joint_exqdesn_dp_dgamma(tau, x)
      invalid <- !is.finite(proposal) | proposal <= lower | proposal >= upper
      proposal[invalid] <- 0.5 * (lower[invalid] + upper[invalid])
      x <- proposal
    }
    out[index] <- best
  }
  # Root tolerances can round an endpoint-near solution onto the open native
  # support boundary. Keep the numerical inverse strictly inside that support.
  pmin(
    pmax(out, support$lower[[1L]] + padding),
    support$upper[[1L]] - padding
  )
}

app_joint_exqdesn_gamma_to_support_eta <- function(tau, gamma) {
  support <- app_joint_exqdesn_support(tau)
  app_joint_qvp_gamma_to_eta(gamma, support$lower[[1L]], support$upper[[1L]])
}

app_joint_exqdesn_support_eta_to_gamma <- function(tau, eta) {
  support <- app_joint_exqdesn_support(tau)
  app_joint_qvp_eta_to_gamma(eta, support$lower[[1L]], support$upper[[1L]])
}

app_joint_exqdesn_log_support_jacobian <- function(tau, eta) {
  support <- app_joint_exqdesn_support(tau)
  app_joint_qvp_gamma_logit_jacobian(eta, support$lower[[1L]], support$upper[[1L]])
}

app_joint_exqdesn_gamma_to_p_eta <- function(tau, gamma) {
  stats::qlogis(app_joint_exqdesn_gamma_to_p(tau, gamma))
}

app_joint_exqdesn_p_eta_to_gamma <- function(tau, eta) {
  app_joint_exqdesn_p_to_gamma(tau, stats::plogis(eta))
}

app_joint_exqdesn_log_p_eta_jacobian <- function(tau, eta) {
  p_gamma <- stats::plogis(eta)
  gamma <- app_joint_exqdesn_p_to_gamma(tau, p_gamma)
  log(p_gamma) + log1p(-p_gamma) - log(app_joint_exqdesn_dp_dgamma(tau, gamma))
}

app_joint_exqdesn_gamma_log_prior <- function(
  tau,
  gamma,
  gamma_prior_type = "none",
  gamma_prior_center = 0,
  gamma_prior_sd_eta = NA_real_
) {
  support <- app_joint_exqdesn_support(tau)
  vapply(as.numeric(gamma), function(g) {
    app_joint_qvp_gamma_log_prior(
      gamma = g,
      lower = support$lower[[1L]],
      upper = support$upper[[1L]],
      gamma_prior_type = gamma_prior_type,
      gamma_prior_center = gamma_prior_center,
      gamma_prior_sd_eta = gamma_prior_sd_eta
    )
  }, numeric(1L))
}

app_joint_exqdesn_gig_ig_limit <- function(nu, chi, psi, tolerance = 1.0e-10) {
  nu <- as.numeric(nu)
  chi <- as.numeric(chi)
  psi <- as.numeric(psi)
  n <- max(length(nu), length(chi), length(psi))
  nu <- rep(nu, length.out = n)
  chi <- rep(chi, length.out = n)
  psi <- rep(psi, length.out = n)
  shape <- -nu
  mean_ig <- ifelse(shape > 1, chi / (2 * (shape - 1)), Inf)
  exact_zero <- psi <= 0
  asymptotically_zero <- nu < -1 & is.finite(mean_ig) & 0.5 * psi * mean_ig <= tolerance
  exact_zero | asymptotically_zero
}

app_joint_exqdesn_log_bessel_k <- function(nu, z) {
  n <- max(length(nu), length(z))
  order <- rep(abs(as.numeric(nu)), length.out = n)
  z <- rep(as.numeric(z), length.out = n)
  if (any(!is.finite(order)) || any(!is.finite(z) | z <= 0)) {
    stop("Stable log-Bessel inputs must be finite with z > 0.", call. = FALSE)
  }
  scaled <- suppressWarnings(besselK(z, nu = order, expon.scaled = TRUE))
  out <- log(scaled) - z
  bad <- !is.finite(out)
  if (any(bad)) {
    a <- order[bad]
    x <- z[bad] / a
    root <- sqrt(1 + x^2)
    eta <- root + log(x) - log1p(root)
    t <- 1 / root
    u1 <- (3 * t - 5 * t^3) / 24
    u2 <- (81 * t^2 - 462 * t^4 + 385 * t^6) / 1152
    u3 <- (
      30375 * t^3 - 369603 * t^5 + 765765 * t^7 - 425425 * t^9
    ) / 414720
    series <- 1 - u1 / a + u2 / a^2 - u3 / a^3
    if (any(!is.finite(series) | series <= 0) || any(a <= 0)) {
      stop("Large-order log-Bessel expansion failed.", call. = FALSE)
    }
    out[bad] <- 0.5 * (log(pi) - log(2 * a)) -
      0.25 * log1p(x^2) - a * eta + log(series)
  }
  if (any(!is.finite(out))) stop("Could not compute stable log K_nu(z).", call. = FALSE)
  out
}

app_joint_exqdesn_gig_log_integral <- function(nu, chi, psi, limit_tolerance = 1.0e-10) {
  n <- max(length(nu), length(chi), length(psi))
  nu <- rep(as.numeric(nu), length.out = n)
  chi <- rep(as.numeric(chi), length.out = n)
  psi <- rep(as.numeric(psi), length.out = n)
  if (any(!is.finite(nu)) || any(!is.finite(chi) | chi <= 0) || any(!is.finite(psi) | psi < 0)) {
    stop("Invalid GIG integral parameters.", call. = FALSE)
  }
  use_ig <- app_joint_exqdesn_gig_ig_limit(nu, chi, psi, limit_tolerance)
  if (any(use_ig & nu >= 0)) stop("The psi=0 GIG integral requires nu < 0.", call. = FALSE)
  out <- numeric(n)
  if (any(use_ig)) {
    out[use_ig] <- lgamma(-nu[use_ig]) + nu[use_ig] * (log(chi[use_ig]) - log(2))
  }
  if (any(!use_ig)) {
    index <- which(!use_ig)
    z <- sqrt(chi[index] * psi[index])
    out[index] <- log(2) + app_joint_exqdesn_log_bessel_k(nu[index], z) +
      0.5 * nu[index] * (log(chi[index]) - log(psi[index]))
  }
  if (any(!is.finite(out))) stop("Could not compute the GIG/inverse-gamma integral.", call. = FALSE)
  out
}

app_joint_exqdesn_gig_moment <- function(nu, chi, psi, r, limit_tolerance = 1.0e-10) {
  r <- as.numeric(r)[[1L]]
  n <- max(length(nu), length(chi), length(psi))
  nu <- rep(as.numeric(nu), length.out = n)
  chi <- rep(as.numeric(chi), length.out = n)
  psi <- rep(as.numeric(psi), length.out = n)
  use_ig <- app_joint_exqdesn_gig_ig_limit(nu, chi, psi, limit_tolerance)
  out <- numeric(n)
  if (any(use_ig)) {
    shape <- -nu[use_ig]
    rate <- chi[use_ig] / 2
    if (any(shape <= r)) stop("Requested inverse-gamma moment does not exist.", call. = FALSE)
    log_moment <- r * log(rate) + lgamma(shape - r) - lgamma(shape)
    out[use_ig] <- exp(log_moment)
  }
  if (any(!use_ig)) {
    index <- which(!use_ig)
    z <- sqrt(chi[index] * psi[index])
    log_moment <- app_joint_exqdesn_log_bessel_k(nu[index] + r, z) -
      app_joint_exqdesn_log_bessel_k(nu[index], z) +
      0.5 * r * (log(chi[index]) - log(psi[index]))
    out[index] <- exp(log_moment)
  }
  if (any(!is.finite(out) | out <= 0)) stop("Could not compute a finite positive GIG moment.", call. = FALSE)
  out
}

app_joint_exqdesn_gig_log_moment <- function(nu, chi, psi, limit_tolerance = 1.0e-10) {
  n <- max(length(nu), length(chi), length(psi))
  nu <- rep(as.numeric(nu), length.out = n)
  chi <- rep(as.numeric(chi), length.out = n)
  psi <- rep(as.numeric(psi), length.out = n)
  use_ig <- app_joint_exqdesn_gig_ig_limit(nu, chi, psi, limit_tolerance)
  out <- numeric(n)
  if (any(use_ig)) out[use_ig] <- log(chi[use_ig] / 2) - digamma(-nu[use_ig])
  if (any(!use_ig)) {
    index <- which(!use_ig)
    h <- 1.0e-4 * pmax(1, abs(nu[index]))
    out[index] <- (
      app_joint_exqdesn_gig_log_integral(nu[index] + h, chi[index], psi[index], limit_tolerance = 0) -
        app_joint_exqdesn_gig_log_integral(nu[index] - h, chi[index], psi[index], limit_tolerance = 0)
    ) / (2 * h)
  }
  if (any(!is.finite(out))) stop("Could not compute E[log sigma].", call. = FALSE)
  out
}

app_joint_exqdesn_rgig <- function(nu, chi, psi, current = NULL, limit_tolerance = 1.0e-10) {
  nu <- as.numeric(nu)[[1L]]
  chi <- as.numeric(chi)[[1L]]
  psi <- as.numeric(psi)[[1L]]
  if (app_joint_exqdesn_gig_ig_limit(nu, chi, psi, limit_tolerance)) {
    return(app_joint_qvp_rinvgamma(1L, shape = -nu, rate = chi / 2)[[1L]])
  }
  app_joint_qvp_rgig(nu, chi, psi, current = current)[[1L]]
}

app_joint_exqdesn_gig_log_sigma_mode_scale <- function(nu, chi, psi) {
  nu <- as.numeric(nu)[[1L]]
  chi <- as.numeric(chi)[[1L]]
  psi <- as.numeric(psi)[[1L]]
  if (!is.finite(nu) || !is.finite(chi) || chi <= 0 || !is.finite(psi) || psi < 0) {
    stop("Invalid GIG mode parameters.", call. = FALSE)
  }
  root <- sqrt(nu^2 + chi * psi)
  sigma_mode <- if (psi <= 0) {
    if (nu >= 0) stop("The inverse-gamma log-scale mode requires nu < 0.", call. = FALSE)
    -chi / (2 * nu)
  } else {
    # This form avoids cancellation when nu is large and negative.
    chi / (root - nu)
  }
  if (!is.finite(sigma_mode) || sigma_mode <= 0 || !is.finite(root) || root <= 0) {
    stop("Could not determine a finite GIG log-scale mode.", call. = FALSE)
  }
  c(log_sigma_mode = log(sigma_mode), log_sigma_scale = 1 / sqrt(root))
}

app_joint_exqdesn_gauss_legendre <- function(n) {
  n <- as.integer(n)[[1L]]
  if (!is.finite(n) || n < 2L) stop("Gauss-Legendre order must be at least two.", call. = FALSE)
  key <- paste0("gauss_legendre_", n)
  if (exists(key, envir = .app_joint_exqdesn_cache, inherits = FALSE)) {
    return(get(key, envir = .app_joint_exqdesn_cache, inherits = FALSE))
  }
  off_diag <- seq_len(n - 1L) / sqrt(4 * seq_len(n - 1L)^2 - 1)
  jacobi <- matrix(0, nrow = n, ncol = n)
  jacobi[cbind(seq_len(n - 1L), 2:n)] <- off_diag
  jacobi[cbind(2:n, seq_len(n - 1L))] <- off_diag
  eig <- eigen(jacobi, symmetric = TRUE)
  ord <- order(eig$values)
  out <- list(nodes = eig$values[ord], weights = 2 * eig$vectors[1L, ord]^2)
  assign(key, out, envir = .app_joint_exqdesn_cache)
  out
}

app_joint_exqdesn_branch_grid <- function(tau, n_per_branch) {
  tau <- app_joint_exqdesn_assert_scalar_tau(tau)
  n_per_branch <- as.integer(n_per_branch)[[1L]]
  key <- paste0("branch_grid_", format(tau, digits = 17), "_", n_per_branch)
  if (exists(key, envir = .app_joint_exqdesn_cache, inherits = FALSE)) {
    return(get(key, envir = .app_joint_exqdesn_cache, inherits = FALSE))
  }
  rule <- app_joint_exqdesn_gauss_legendre(n_per_branch)
  support <- app_joint_exqdesn_support(tau)
  make_branch <- function(a, b, branch) {
    data.frame(
      gamma = 0.5 * (b - a) * rule$nodes + 0.5 * (a + b),
      log_quadrature_weight = log(0.5 * (b - a) * rule$weights),
      branch = branch,
      stringsAsFactors = FALSE
    )
  }
  out <- rbind(
    make_branch(support$lower[[1L]], 0, "negative"),
    make_branch(0, support$upper[[1L]], "positive")
  )
  constants <- app_joint_exqdesn_constants(tau, out$gamma)
  out <- cbind(out, constants[, setdiff(names(constants), c("gamma", "branch")), drop = FALSE])
  assign(key, out, envir = .app_joint_exqdesn_cache)
  out
}

app_joint_exqdesn_p_eta_state <- function(tau, eta, branch) {
  tau <- app_joint_exqdesn_assert_scalar_tau(tau)
  if (!branch %in% c("negative", "positive")) stop("Unknown gamma branch.", call. = FALSE)
  state <- app_joint_exqdesn_p_eta_values(tau, eta, branch)
  data.frame(
    gamma = state$gamma,
    p_gamma = state$p_gamma,
    eta = state$eta,
    log_jacobian = state$log_jacobian,
    branch = branch,
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_p_eta_values <- function(tau, eta, branch) {
  tau <- app_joint_exqdesn_assert_scalar_tau(tau)
  if (!branch %in% c("negative", "positive")) stop("Unknown gamma branch.", call. = FALSE)
  eta <- as.numeric(eta)
  branch_fraction <- stats::plogis(eta)
  p_bounds <- app_joint_exqdesn_p_bounds(tau)
  branch_width <- if (branch == "negative") {
    tau - p_bounds[["lower"]]
  } else {
    p_bounds[["upper"]] - tau
  }
  p_gamma <- if (branch == "negative") {
    p_bounds[["lower"]] + branch_width * branch_fraction
  } else {
    tau + branch_width * branch_fraction
  }
  gamma <- app_joint_exqdesn_p_to_gamma(tau, p_gamma)
  log_jacobian <- log(branch_width) + log(branch_fraction) + log1p(-branch_fraction) -
    log(app_joint_exqdesn_dp_dgamma_raw(tau, gamma, p_gamma))
  list(
    gamma = gamma,
    p_gamma = p_gamma,
    eta = eta,
    log_jacobian = log_jacobian,
    branch_fraction = branch_fraction
  )
}

app_joint_exqdesn_branch_geometry <- function(tau, branch, log_density, eta_limit = 18) {
  log_eta_target <- function(eta) {
    state <- app_joint_exqdesn_p_eta_values(tau, eta, branch)
    value <- log_density(state$gamma[[1L]]) + state$log_jacobian[[1L]]
    if (is.finite(value)) value else -Inf
  }
  coarse <- seq(-eta_limit + 2, eta_limit - 2, by = 2)
  coarse_value <- vapply(coarse, log_eta_target, numeric(1L))
  best <- which.max(coarse_value)
  mode_interval <- c(
    if (best == 1L) -eta_limit else coarse[[best - 1L]],
    if (best == length(coarse)) eta_limit else coarse[[best + 1L]]
  )
  mode <- stats::optimize(function(eta) -log_eta_target(eta), mode_interval, tol = 1.0e-10)$minimum
  step <- max(1.0e-3, min(0.05, 0.01 * max(1, abs(mode))))
  curvature <- (
    log_eta_target(mode + step) - 2 * log_eta_target(mode) + log_eta_target(mode - step)
  ) / step^2
  local_scale <- if (is.finite(curvature) && curvature < 0) 1 / sqrt(-curvature) else 1
  local_scale <- min(max(local_scale, 0.02), 5)
  breaks <- sort(unique(pmax(
    -eta_limit,
    pmin(eta_limit, c(
      -eta_limit,
      mode + local_scale * c(-12, -7, -4, -2, 0, 2, 4, 7, 12),
      eta_limit
    ))
  )))
  breaks <- breaks[c(TRUE, diff(breaks) > 1.0e-10)]
  list(mode = mode, local_scale = local_scale, breaks = breaks, eta_limit = eta_limit)
}

app_joint_exqdesn_mode_centered_branch_grid <- function(
  tau,
  branch,
  n_per_panel,
  log_density,
  eta_limit = 18,
  geometry = NULL
) {
  n_per_panel <- as.integer(n_per_panel)[[1L]]
  if (!is.finite(n_per_panel) || n_per_panel < 2L) stop("Panel order must be at least two.", call. = FALSE)
  eta_limit <- as.numeric(eta_limit)[[1L]]
  if (!is.finite(eta_limit) || eta_limit < 8) stop("eta_limit is too small.", call. = FALSE)
  geometry <- geometry %||% app_joint_exqdesn_branch_geometry(tau, branch, log_density, eta_limit)
  mode <- geometry$mode
  local_scale <- geometry$local_scale
  breaks <- geometry$breaks
  rule <- app_joint_exqdesn_gauss_legendre(n_per_panel)
  panels <- lapply(seq_len(length(breaks) - 1L), function(ii) {
    lower <- breaks[[ii]]
    upper <- breaks[[ii + 1L]]
    eta <- 0.5 * (upper - lower) * rule$nodes + 0.5 * (lower + upper)
    state <- app_joint_exqdesn_p_eta_state(tau, eta, branch)
    state$log_quadrature_weight <-
      log(0.5 * (upper - lower) * rule$weights) + state$log_jacobian
    state$panel_index <- ii
    state
  })
  grid <- do.call(rbind, panels)
  grid$branch_mode_eta <- mode
  grid$branch_local_scale <- local_scale
  grid$branch_panel_count <- length(panels)
  grid
}

app_joint_exqdesn_normalize_branch_quadrature <- function(
  tau,
  log_density,
  moment_function = NULL,
  node_grid = c(4L, 8L, 12L),
  tolerance = 1.0e-6
) {
  tau <- app_joint_exqdesn_assert_scalar_tau(tau)
  node_grid <- unique(as.integer(node_grid))
  if (!length(node_grid) || any(node_grid < 2L)) stop("Invalid quadrature node grid.", call. = FALSE)
  previous <- NULL
  converged <- FALSE
  diagnostics <- list()
  final <- NULL
  geometry <- list(
    negative = app_joint_exqdesn_branch_geometry(tau, "negative", log_density),
    positive = app_joint_exqdesn_branch_geometry(tau, "positive", log_density)
  )
  for (ii in seq_along(node_grid)) {
    n <- node_grid[[ii]]
    grid <- rbind(
      app_joint_exqdesn_mode_centered_branch_grid(
        tau, "negative", n, log_density, geometry = geometry$negative
      ),
      app_joint_exqdesn_mode_centered_branch_grid(
        tau, "positive", n, log_density, geometry = geometry$positive
      )
    )
    log_target <- tryCatch(as.numeric(log_density(grid$gamma)), error = function(e) numeric())
    if (length(log_target) != nrow(grid)) {
      log_target <- vapply(grid$gamma, log_density, numeric(1L))
    }
    log_weight <- log_target + grid$log_quadrature_weight
    log_z <- app_joint_exqdesn_logsumexp(log_weight)
    if (!is.finite(log_z)) stop("Branch quadrature found no finite target mass.", call. = FALSE)
    normalized_weight <- exp(log_weight - log_z)
    branch_mass <- c(
      negative = sum(normalized_weight[grid$branch == "negative"]),
      positive = sum(normalized_weight[grid$branch == "positive"])
    )
    moments <- numeric()
    moment_values <- NULL
    if (!is.null(moment_function)) {
      batched <- tryCatch(moment_function(grid$gamma), error = function(e) NULL)
      if ((is.matrix(batched) || is.data.frame(batched)) && nrow(batched) == nrow(grid)) {
        moment_values <- as.matrix(batched)
        moment_names <- colnames(moment_values)
      } else {
        rows <- lapply(seq_len(nrow(grid)), function(jj) {
          raw <- moment_function(grid$gamma[[jj]])
          x <- as.numeric(raw)
          names(x) <- names(raw)
          x
        })
        moment_names <- names(rows[[1L]])
        moment_values <- do.call(rbind, rows)
      }
      if (is.null(moment_names) || any(!nzchar(moment_names))) {
        stop("Quadrature moment functions must return named numeric vectors or a named matrix.", call. = FALSE)
      }
      colnames(moment_values) <- moment_names
      moments <- colSums(moment_values * normalized_weight)
    }
    current <- c(log_normalizer = log_z, branch_mass, moments)
    error <- if (is.null(previous)) Inf else max(abs(current - previous) / pmax(1, abs(current), abs(previous)))
    diagnostics[[ii]] <- data.frame(
      nodes_per_panel = n,
      total_nodes = nrow(grid),
      log_normalizer = log_z,
      negative_branch_mass = branch_mass[["negative"]],
      positive_branch_mass = branch_mass[["positive"]],
      relative_change = error,
      stringsAsFactors = FALSE
    )
    final <- list(
      tau = tau,
      grid = transform(grid, log_target = log_target, normalized_weight = normalized_weight),
      log_normalizer = log_z,
      branch_mass = branch_mass,
      moments = moments,
      moment_values = moment_values,
      diagnostics = do.call(rbind, diagnostics),
      nodes_per_panel = n,
      total_nodes = nrow(grid),
      relative_change = error,
      converged = FALSE
    )
    if (!is.null(previous) && is.finite(error) && error <= tolerance) {
      converged <- TRUE
      final$converged <- TRUE
      break
    }
    previous <- current
  }
  final$converged <- converged
  final
}

app_joint_exqdesn_u_sufficient_stats <- function(q, s, u) {
  q <- as.numeric(q)
  s <- as.numeric(s)
  u <- as.numeric(u)
  if (!length(q) || length(s) != length(q) || length(u) != length(q) ||
      any(!is.finite(q)) || any(!is.finite(s)) || any(s < 0) ||
      any(!is.finite(u)) || any(u <= 0)) {
    stop("u-augmented sufficient statistics require finite q/s and positive u.", call. = FALSE)
  }
  list(
    n = length(q),
    sum_q2_over_u = sum(q^2 / u),
    sum_q = sum(q),
    sum_u = sum(u),
    sum_sq_over_u = sum(s * q / u),
    sum_s = sum(s),
    sum_s2_over_u = sum(s^2 / u)
  )
}

app_joint_exqdesn_u_sigma_gig_terms <- function(
  gamma,
  tau,
  sufficient_stats,
  a_sigma = 0.1,
  b_sigma = 0.1
) {
  tau <- app_joint_exqdesn_assert_scalar_tau(tau)
  if (!is.finite(a_sigma) || a_sigma <= 0 || !is.finite(b_sigma) || b_sigma <= 0) {
    stop("Scale-prior parameters must be positive and finite.", call. = FALSE)
  }
  constants <- tryCatch(app_joint_exqdesn_constants(tau, gamma), error = function(e) NULL)
  if (is.null(constants)) return(NULL)
  p_gamma <- constants$p_gamma[[1L]]
  lambda <- constants$lambda[[1L]]
  k <- constants$k[[1L]]
  out <- list(
    nu = -a_sigma - 1.5 * sufficient_stats$n,
    chi = 2 * b_sigma + sufficient_stats$sum_q2_over_u -
      (1 - 2 * p_gamma) * sufficient_stats$sum_q + 0.25 * sufficient_stats$sum_u,
    psi = lambda^2 * sufficient_stats$sum_s2_over_u,
    cross = lambda * (sufficient_stats$sum_sq_over_u - k * sufficient_stats$sum_s),
    log_cp = log(constants$cp[[1L]]),
    constants = constants,
    sufficient_stats = sufficient_stats
  )
  if (!is.finite(out$nu) || !is.finite(out$chi) || out$chi <= 0 ||
      !is.finite(out$psi) || out$psi < 0 || !is.finite(out$cross)) return(NULL)
  out
}

app_joint_exqdesn_u_gamma_collapsed_log_kernel <- function(
  gamma,
  tau,
  sufficient_stats,
  a_sigma = 0.1,
  b_sigma = 0.1,
  gamma_prior_type = "none",
  gamma_prior_center = 0,
  gamma_prior_sd_eta = NA_real_
) {
  terms <- app_joint_exqdesn_u_sigma_gig_terms(
    gamma = gamma,
    tau = tau,
    sufficient_stats = sufficient_stats,
    a_sigma = a_sigma,
    b_sigma = b_sigma
  )
  if (is.null(terms)) return(-Inf)
  prior <- app_joint_exqdesn_gamma_log_prior(
    tau, gamma, gamma_prior_type, gamma_prior_center, gamma_prior_sd_eta
  )[[1L]]
  value <- prior + sufficient_stats$n * terms$log_cp + terms$cross +
    app_joint_exqdesn_gig_log_integral(terms$nu, terms$chi, terms$psi)
  if (is.finite(value)) value else -Inf
}

app_joint_exqdesn_u_sigma_gamma_collapsed_draw <- function(
  sigma,
  gamma,
  q,
  s,
  u,
  tau,
  coordinate = c("support_logit", "p_gamma_logit"),
  gamma_slice_width = 1,
  gamma_slice_max_steps = 100L,
  a_sigma = 0.1,
  b_sigma = 0.1,
  gamma_prior_type = "none",
  gamma_prior_center = 0,
  gamma_prior_sd_eta = NA_real_
) {
  coordinate <- match.arg(coordinate)
  tau <- app_joint_exqdesn_assert_scalar_tau(tau)
  sufficient_stats <- app_joint_exqdesn_u_sufficient_stats(q, s, u)
  density_evaluations <- 0L
  native_target <- function(g) {
    density_evaluations <<- density_evaluations + 1L
    app_joint_exqdesn_u_gamma_collapsed_log_kernel(
      gamma = g,
      tau = tau,
      sufficient_stats = sufficient_stats,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      gamma_prior_type = gamma_prior_type,
      gamma_prior_center = gamma_prior_center,
      gamma_prior_sd_eta = gamma_prior_sd_eta
    )
  }
  eps <- 1.0e-10
  if (identical(coordinate, "support_logit")) {
    support <- app_joint_exqdesn_support(tau)
    margin <- max(1.0e-10, eps * (support$upper[[1L]] - support$lower[[1L]]))
    lower_eta <- app_joint_exqdesn_gamma_to_support_eta(tau, support$lower[[1L]] + margin)
    upper_eta <- app_joint_exqdesn_gamma_to_support_eta(tau, support$upper[[1L]] - margin)
    eta0 <- app_joint_exqdesn_gamma_to_support_eta(tau, gamma)
    eta_target <- function(eta) {
      g <- app_joint_exqdesn_support_eta_to_gamma(tau, eta)
      native_target(g) + app_joint_exqdesn_log_support_jacobian(tau, eta)
    }
    eta <- app_joint_qvp_slice_bounded_one(
      x0 = eta0, lower = lower_eta, upper = upper_eta,
      width = gamma_slice_width, max_steps = gamma_slice_max_steps,
      log_density = eta_target
    )
    gamma_new <- app_joint_exqdesn_support_eta_to_gamma(tau, eta)
  } else {
    p_bounds <- app_joint_exqdesn_p_bounds(tau)
    lower_eta <- stats::qlogis(p_bounds[["lower"]])
    upper_eta <- stats::qlogis(p_bounds[["upper"]])
    eta0 <- app_joint_exqdesn_gamma_to_p_eta(tau, gamma)
    eta_target <- function(eta) {
      g <- app_joint_exqdesn_p_eta_to_gamma(tau, eta)
      native_target(g) + app_joint_exqdesn_log_p_eta_jacobian(tau, eta)
    }
    eta <- app_joint_qvp_slice_bounded_one(
      x0 = eta0, lower = lower_eta, upper = upper_eta,
      width = gamma_slice_width, max_steps = gamma_slice_max_steps,
      log_density = eta_target
    )
    gamma_new <- app_joint_exqdesn_p_eta_to_gamma(tau, eta)
  }
  terms <- app_joint_exqdesn_u_sigma_gig_terms(
    gamma_new, tau, sufficient_stats, a_sigma, b_sigma
  )
  if (is.null(terms)) stop("The collapsed u block produced invalid GIG terms.", call. = FALSE)
  sigma_new <- app_joint_exqdesn_rgig(terms$nu, terms$chi, terms$psi, current = sigma)
  list(
    sigma = sigma_new,
    gamma = gamma_new,
    p_gamma = app_joint_exqdesn_gamma_to_p(tau, gamma_new),
    coordinate = coordinate,
    density_evaluations = density_evaluations,
    gig_nu = terms$nu,
    gig_chi = terms$chi,
    gig_psi = terms$psi,
    inverse_gamma_limit = app_joint_exqdesn_gig_ig_limit(terms$nu, terms$chi, terms$psi)
  )
}

app_joint_exqdesn_u_log_joint_kernel <- function(
  sigma,
  gamma,
  q,
  s,
  u,
  tau,
  a_sigma = 0.1,
  b_sigma = 0.1,
  gamma_prior_type = "none",
  gamma_prior_center = 0,
  gamma_prior_sd_eta = NA_real_
) {
  if (!is.finite(sigma) || sigma <= 0) return(-Inf)
  stats <- app_joint_exqdesn_u_sufficient_stats(q, s, u)
  terms <- app_joint_exqdesn_u_sigma_gig_terms(gamma, tau, stats, a_sigma, b_sigma)
  if (is.null(terms)) return(-Inf)
  prior <- app_joint_exqdesn_gamma_log_prior(
    tau, gamma, gamma_prior_type, gamma_prior_center, gamma_prior_sd_eta
  )[[1L]]
  value <- prior + stats$n * terms$log_cp + terms$cross +
    (terms$nu - 1) * log(sigma) - 0.5 * (terms$chi / sigma + terms$psi * sigma)
  if (is.finite(value)) value else -Inf
}

app_joint_exqdesn_structured_terms <- function(
  gamma,
  tau,
  augmentation = c("v", "u"),
  r_mean,
  r2_mean,
  latent_mean,
  latent_inv_mean,
  s_mean,
  s2_mean,
  a_sigma = 0.1,
  b_sigma = 0.1,
  gamma_prior_type = "none",
  gamma_prior_center = 0,
  gamma_prior_sd_eta = NA_real_
) {
  augmentation <- match.arg(augmentation)
  tau <- app_joint_exqdesn_assert_scalar_tau(tau)
  r_mean <- as.numeric(r_mean)
  r2_mean <- as.numeric(r2_mean)
  latent_mean <- as.numeric(latent_mean)
  latent_inv_mean <- as.numeric(latent_inv_mean)
  s_mean <- as.numeric(s_mean)
  s2_mean <- as.numeric(s2_mean)
  n <- length(r_mean)
  if (!n || any(vapply(list(r2_mean, latent_mean, latent_inv_mean, s_mean, s2_mean), length, integer(1L)) != n) ||
      any(!is.finite(c(r_mean, r2_mean, latent_mean, latent_inv_mean, s_mean, s2_mean))) ||
      any(r2_mean < 0) || any(latent_mean <= 0) || any(latent_inv_mean <= 0) || any(s2_mean < 0)) {
    stop("Structured scale-shape moments are malformed.", call. = FALSE)
  }
  constants <- tryCatch(app_joint_exqdesn_constants(tau, gamma), error = function(e) NULL)
  if (is.null(constants)) return(NULL)
  A <- constants$A[[1L]]
  B <- constants$B[[1L]]
  lambda <- constants$lambda[[1L]]
  k <- constants$k[[1L]]
  p_gamma <- constants$p_gamma[[1L]]
  nu <- -a_sigma - 1.5 * n
  if (identical(augmentation, "u")) {
    chi <- 2 * b_sigma + sum(r2_mean * latent_inv_mean) -
      (1 - 2 * p_gamma) * sum(r_mean) + 0.25 * sum(latent_mean)
    psi <- lambda^2 * sum(s2_mean * latent_inv_mean)
    cross <- lambda * sum(s_mean * (r_mean * latent_inv_mean - k))
    log_shape <- n * log(constants$cp[[1L]])
  } else {
    chi <- 2 * b_sigma + 2 * sum(latent_mean) +
      (sum(r2_mean * latent_inv_mean) - 2 * A * sum(r_mean) + A^2 * sum(latent_mean)) / B
    psi <- lambda^2 * sum(s2_mean * latent_inv_mean) / B
    cross <- lambda / B * (sum(s_mean * r_mean * latent_inv_mean) - A * sum(s_mean))
    log_shape <- -0.5 * n * log(B)
  }
  prior <- app_joint_exqdesn_gamma_log_prior(
    tau, gamma, gamma_prior_type, gamma_prior_center, gamma_prior_sd_eta
  )[[1L]]
  if (!is.finite(chi) || chi <= 0 || !is.finite(psi) || psi < 0 || !is.finite(cross)) return(NULL)
  list(
    nu = nu,
    chi = chi,
    psi = psi,
    cross = cross,
    log_shape = log_shape,
    log_prior = prior,
    constants = constants,
    log_collapsed = prior + log_shape + cross +
      app_joint_exqdesn_gig_log_integral(nu, chi, psi)
  )
}

app_joint_exqdesn_structured_terms_grid <- function(
  gamma,
  tau,
  augmentation = c("v", "u"),
  r_mean,
  r2_mean,
  latent_mean,
  latent_inv_mean,
  s_mean,
  s2_mean,
  a_sigma = 0.1,
  b_sigma = 0.1,
  gamma_prior_type = "none",
  gamma_prior_center = 0,
  gamma_prior_sd_eta = NA_real_
) {
  augmentation <- match.arg(augmentation)
  tau <- app_joint_exqdesn_assert_scalar_tau(tau)
  gamma <- as.numeric(gamma)
  r_mean <- as.numeric(r_mean)
  r2_mean <- as.numeric(r2_mean)
  latent_mean <- as.numeric(latent_mean)
  latent_inv_mean <- as.numeric(latent_inv_mean)
  s_mean <- as.numeric(s_mean)
  s2_mean <- as.numeric(s2_mean)
  n <- length(r_mean)
  if (!length(gamma) || !n ||
      any(vapply(list(r2_mean, latent_mean, latent_inv_mean, s_mean, s2_mean), length, integer(1L)) != n) ||
      any(!is.finite(c(gamma, r_mean, r2_mean, latent_mean, latent_inv_mean, s_mean, s2_mean))) ||
      any(r2_mean < 0) || any(latent_mean <= 0) || any(latent_inv_mean <= 0) || any(s2_mean < 0)) {
    stop("Structured scale-shape grid moments are malformed.", call. = FALSE)
  }
  constants <- app_joint_exqdesn_constants(tau, gamma)
  A <- constants$A
  B <- constants$B
  lambda <- constants$lambda
  k <- constants$k
  p_gamma <- constants$p_gamma
  nu <- rep(-a_sigma - 1.5 * n, length(gamma))
  sum_r2_inv <- sum(r2_mean * latent_inv_mean)
  sum_r <- sum(r_mean)
  sum_latent <- sum(latent_mean)
  sum_s2_inv <- sum(s2_mean * latent_inv_mean)
  sum_sr_inv <- sum(s_mean * r_mean * latent_inv_mean)
  sum_s <- sum(s_mean)
  if (identical(augmentation, "u")) {
    chi <- 2 * b_sigma + sum_r2_inv - (1 - 2 * p_gamma) * sum_r + 0.25 * sum_latent
    psi <- lambda^2 * sum_s2_inv
    cross <- lambda * (sum_sr_inv - k * sum_s)
    log_shape <- n * log(constants$cp)
  } else {
    chi <- 2 * b_sigma + 2 * sum_latent +
      (sum_r2_inv - 2 * A * sum_r + A^2 * sum_latent) / B
    psi <- lambda^2 * sum_s2_inv / B
    cross <- lambda / B * (sum_sr_inv - A * sum_s)
    log_shape <- -0.5 * n * log(B)
  }
  log_prior <- app_joint_exqdesn_gamma_log_prior(
    tau, gamma, gamma_prior_type, gamma_prior_center, gamma_prior_sd_eta
  )
  if (any(!is.finite(chi) | chi <= 0) || any(!is.finite(psi) | psi < 0) || any(!is.finite(cross))) {
    stop("Structured scale-shape grid produced invalid GIG terms.", call. = FALSE)
  }
  data.frame(
    nu = nu,
    chi = chi,
    psi = psi,
    cross = cross,
    log_shape = log_shape,
    log_prior = log_prior,
    log_collapsed = log_prior + log_shape + cross +
      app_joint_exqdesn_gig_log_integral(nu, chi, psi),
    constants,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

app_joint_exqdesn_scale_shape_moments <- function(terms) {
  if (is.null(terms)) stop("Scale-shape terms are required.", call. = FALSE)
  cst <- terms$constants
  sigma_mean <- app_joint_exqdesn_gig_moment(terms$nu, terms$chi, terms$psi, 1)[[1L]]
  sigma2_mean <- app_joint_exqdesn_gig_moment(terms$nu, terms$chi, terms$psi, 2)[[1L]]
  sigma_inv_mean <- app_joint_exqdesn_gig_moment(terms$nu, terms$chi, terms$psi, -1)[[1L]]
  sigma_log_mean <- app_joint_exqdesn_gig_log_moment(terms$nu, terms$chi, terms$psi)[[1L]]
  gamma <- cst$gamma[[1L]]
  lambda <- cst$lambda[[1L]]
  A <- cst$A[[1L]]
  B <- cst$B[[1L]]
  k <- cst$k[[1L]]
  c(
    sigma_mean = sigma_mean,
    sigma2_mean = sigma2_mean,
    sigma_inv_mean = sigma_inv_mean,
    sigma_log_mean = sigma_log_mean,
    gamma_mean = gamma,
    gamma2_mean = gamma^2,
    p_gamma_mean = cst$p_gamma[[1L]],
    negative_branch = as.numeric(gamma < 0),
    lambda_mean = lambda,
    k_mean = k,
    A_mean = A,
    B_mean = B,
    inv_B_sigma_mean = sigma_inv_mean / B,
    lambda_over_B_mean = lambda / B,
    A_inv_B_sigma_mean = A * sigma_inv_mean / B,
    sigma_lambda2_over_B_mean = sigma_mean * lambda^2 / B,
    A2_inv_B_sigma_mean = A^2 * sigma_inv_mean / B,
    A_lambda_over_B_mean = A * lambda / B,
    sigma_lambda2_mean = sigma_mean * lambda^2,
    k_sigma_inv_mean = k * sigma_inv_mean,
    lambda_k_mean = lambda * k,
    sigma_lambda_mean = sigma_mean * lambda,
    actual_sd_mean = sigma_mean * cst$sd_factor[[1L]],
    actual_variance_mean = sigma2_mean * cst$sd_factor[[1L]]^2,
    inverse_gamma_limit = as.numeric(app_joint_exqdesn_gig_ig_limit(terms$nu, terms$chi, terms$psi))
  )
}

app_joint_exqdesn_scale_shape_moments_grid <- function(terms) {
  if (!is.data.frame(terms) || !nrow(terms)) stop("Scale-shape term grid is required.", call. = FALSE)
  sigma_mean <- app_joint_exqdesn_gig_moment(terms$nu, terms$chi, terms$psi, 1)
  sigma2_mean <- app_joint_exqdesn_gig_moment(terms$nu, terms$chi, terms$psi, 2)
  sigma_inv_mean <- app_joint_exqdesn_gig_moment(terms$nu, terms$chi, terms$psi, -1)
  sigma_log_mean <- app_joint_exqdesn_gig_log_moment(terms$nu, terms$chi, terms$psi)
  data.frame(
    sigma_mean = sigma_mean,
    sigma2_mean = sigma2_mean,
    sigma_inv_mean = sigma_inv_mean,
    sigma_log_mean = sigma_log_mean,
    gamma_mean = terms$gamma,
    gamma2_mean = terms$gamma^2,
    p_gamma_mean = terms$p_gamma,
    negative_branch = as.numeric(terms$gamma < 0),
    lambda_mean = terms$lambda,
    k_mean = terms$k,
    A_mean = terms$A,
    B_mean = terms$B,
    inv_B_sigma_mean = sigma_inv_mean / terms$B,
    lambda_over_B_mean = terms$lambda / terms$B,
    A_inv_B_sigma_mean = terms$A * sigma_inv_mean / terms$B,
    sigma_lambda2_over_B_mean = sigma_mean * terms$lambda^2 / terms$B,
    A2_inv_B_sigma_mean = terms$A^2 * sigma_inv_mean / terms$B,
    A_lambda_over_B_mean = terms$A * terms$lambda / terms$B,
    sigma_lambda2_mean = sigma_mean * terms$lambda^2,
    k_sigma_inv_mean = terms$k * sigma_inv_mean,
    lambda_k_mean = terms$lambda * terms$k,
    sigma_lambda_mean = sigma_mean * terms$lambda,
    actual_sd_mean = sigma_mean * terms$sd_factor,
    actual_variance_mean = sigma2_mean * terms$sd_factor^2,
    inverse_gamma_limit = as.numeric(app_joint_exqdesn_gig_ig_limit(terms$nu, terms$chi, terms$psi)),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

app_joint_exqdesn_structured_scale_shape_update <- function(
  tau,
  augmentation = c("v", "u"),
  r_mean,
  r2_mean,
  latent_mean,
  latent_inv_mean,
  s_mean,
  s2_mean,
  a_sigma = 0.1,
  b_sigma = 0.1,
  gamma_prior_type = "none",
  gamma_prior_center = 0,
  gamma_prior_sd_eta = NA_real_,
  quadrature_nodes = c(4L, 8L, 12L),
  quadrature_tolerance = 1.0e-6
) {
  augmentation <- match.arg(augmentation)
  terms_at <- function(gamma) app_joint_exqdesn_structured_terms_grid(
    gamma = gamma,
    tau = tau,
    augmentation = augmentation,
    r_mean = r_mean,
    r2_mean = r2_mean,
    latent_mean = latent_mean,
    latent_inv_mean = latent_inv_mean,
    s_mean = s_mean,
    s2_mean = s2_mean,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    gamma_prior_type = gamma_prior_type,
    gamma_prior_center = gamma_prior_center,
    gamma_prior_sd_eta = gamma_prior_sd_eta
  )
  quadrature <- app_joint_exqdesn_normalize_branch_quadrature(
    tau = tau,
    log_density = function(gamma) terms_at(gamma)$log_collapsed,
    moment_function = function(gamma) app_joint_exqdesn_scale_shape_moments_grid(terms_at(gamma)),
    node_grid = quadrature_nodes,
    tolerance = quadrature_tolerance
  )
  quadrature$augmentation <- augmentation
  quadrature
}

app_joint_exqdesn_point_scale_shape_moments <- function(tau, gamma, sigma) {
  cst <- app_joint_exqdesn_constants(tau, gamma)
  A <- cst$A[[1L]]
  B <- cst$B[[1L]]
  lambda <- cst$lambda[[1L]]
  k <- cst$k[[1L]]
  c(
    sigma_mean = sigma,
    sigma2_mean = sigma^2,
    sigma_inv_mean = 1 / sigma,
    sigma_log_mean = log(sigma),
    gamma_mean = gamma,
    gamma2_mean = gamma^2,
    p_gamma_mean = cst$p_gamma[[1L]],
    negative_branch = as.numeric(gamma < 0),
    lambda_mean = lambda,
    k_mean = k,
    A_mean = A,
    B_mean = B,
    inv_B_sigma_mean = 1 / (B * sigma),
    lambda_over_B_mean = lambda / B,
    A_inv_B_sigma_mean = A / (B * sigma),
    sigma_lambda2_over_B_mean = sigma * lambda^2 / B,
    A2_inv_B_sigma_mean = A^2 / (B * sigma),
    A_lambda_over_B_mean = A * lambda / B,
    sigma_lambda2_mean = sigma * lambda^2,
    k_sigma_inv_mean = k / sigma,
    lambda_k_mean = lambda * k,
    sigma_lambda_mean = sigma * lambda,
    actual_sd_mean = sigma * cst$sd_factor[[1L]],
    actual_variance_mean = sigma^2 * cst$sd_factor[[1L]]^2,
    inverse_gamma_limit = as.numeric(gamma == 0)
  )
}

app_joint_exqdesn_fit_exal_vb_structured <- function(
  y,
  Z,
  tau,
  augmentation = c("v", "u"),
  max_iter = 100L,
  tol = 1.0e-5,
  kappa = 1,
  tau0 = 1,
  zeta2 = Inf,
  anchor_tau0 = tau0,
  innovation_tau0 = tau0,
  anchor_zeta2 = zeta2,
  innovation_zeta2 = zeta2,
  a_sigma = 0.1,
  b_sigma = 0.1,
  alpha_prior_mean = NULL,
  alpha_prior_sd = Inf,
  gamma_init = NULL,
  alpha_min_spacing = 0,
  max_dense_dim = 300L,
  init = NULL,
  rhs_vb_inner = 5L,
  quadrature_nodes = c(4L, 8L, 12L),
  quadrature_tolerance = 1.0e-6,
  diagnostic_stride = 10L,
  method_id = NULL
) {
  augmentation <- match.arg(augmentation)
  if (!identical(as.numeric(kappa), 1)) {
    stop("Structured exAL inference is initially restricted to kappa = 1.", call. = FALSE)
  }
  y <- as.numeric(y)
  Z <- app_joint_qvp_check_design(Z)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  Tn <- length(y)
  K <- length(tau)
  p <- ncol(Z)
  if (nrow(Z) != Tn) stop("length(y) must match nrow(Z).", call. = FALSE)
  max_iter <- as.integer(max_iter)
  rhs_vb_inner <- as.integer(rhs_vb_inner)
  diagnostic_stride <- as.integer(diagnostic_stride)
  if (max_iter < 1L || !is.finite(tol) || tol <= 0 || rhs_vb_inner < 1L || diagnostic_stride < 1L) {
    stop("Invalid structured-VB controls.", call. = FALSE)
  }
  if (K * p > as.integer(max_dense_dim)) {
    stop("Structured exAL VB stores dense q(beta) covariance; raise max_dense_dim deliberately.", call. = FALSE)
  }
  normalized_init <- app_joint_qvp_normalize_init(init, K, p)
  if (is.null(normalized_init)) {
    al_init <- app_joint_qvp_fit_al_vb_tiny(
      y = y, Z = Z, tau = tau,
      max_iter = min(max_iter, 25L), tol = tol, kappa = 1,
      tau0 = tau0, zeta2 = zeta2,
      anchor_tau0 = anchor_tau0, innovation_tau0 = innovation_tau0,
      anchor_zeta2 = anchor_zeta2, innovation_zeta2 = innovation_zeta2,
      a_sigma = a_sigma, b_sigma = b_sigma,
      alpha_prior_mean = alpha_prior_mean, alpha_prior_sd = alpha_prior_sd,
      alpha_min_spacing = alpha_min_spacing,
      max_dense_dim = max_dense_dim, rhs_vb_inner = rhs_vb_inner
    )
    init <- al_init
    normalized_init <- app_joint_qvp_normalize_init(al_init, K, p)
  }
  gamma <- normalized_init$gamma %||%
    if (is.null(gamma_init)) app_joint_qvp_default_gamma(tau) else app_joint_qvp_check_gamma(tau, gamma_init)
  gamma <- app_joint_qvp_check_gamma(tau, gamma)
  sigma_mean <- normalized_init$sigma %||% rep(max(stats::mad(y), 1.0e-3), K)
  beta_mean <- normalized_init$beta %||% rep(0, K * p)
  alpha <- normalized_init$alpha %||% sort(as.numeric(stats::quantile(y, tau, names = FALSE, type = 8)))
  alpha_prior <- app_joint_qvp_alpha_prior_spec(y, tau, alpha_prior_mean, alpha_prior_sd)
  rhs_state <- app_joint_qvp_initialize_rhs_state(
    K, p, tau0 = tau0, zeta2 = zeta2,
    anchor_tau0 = anchor_tau0, innovation_tau0 = innovation_tau0,
    anchor_zeta2 = anchor_zeta2, innovation_zeta2 = innovation_zeta2
  )
  prior_state <- app_joint_qvp_rhs_state_to_prior(rhs_state)
  prior <- app_joint_qvp_build_prior_precision(K, p, prior_state$anchor, prior_state$innovations)
  beta_cov <- if (!is.null(init$beta_cov) && identical(dim(as.matrix(init$beta_cov)), c(K * p, K * p))) {
    as.matrix(init$beta_cov)
  } else {
    solve(as.matrix(prior$P_beta + Matrix::Diagonal(K * p) * 1.0e-8))
  }
  initial_constants <- lapply(seq_len(K), function(k) app_joint_exqdesn_constants(tau[[k]], gamma[[k]]))
  if (identical(augmentation, "u")) {
    latent_mean <- if (!is.null(init$u_mean) && identical(dim(as.matrix(init$u_mean)), c(Tn, K))) {
      as.matrix(init$u_mean)
    } else if (!is.null(init$v_mean) && identical(dim(as.matrix(init$v_mean)), c(Tn, K))) {
      out <- as.matrix(init$v_mean)
      for (k in seq_len(K)) out[, k] <- out[, k] * initial_constants[[k]]$B[[1L]]
      out
    } else {
      matrix(unlist(lapply(seq_len(K), function(k) rep(initial_constants[[k]]$B[[1L]] * sigma_mean[[k]], Tn))), nrow = Tn)
    }
    latent_inv_mean <- if (!is.null(init$u_inv_mean) && identical(dim(as.matrix(init$u_inv_mean)), c(Tn, K))) {
      as.matrix(init$u_inv_mean)
    } else {
      1 / pmax(latent_mean, .Machine$double.eps)
    }
  } else {
    latent_mean <- if (!is.null(init$v_mean) && identical(dim(as.matrix(init$v_mean)), c(Tn, K))) {
      as.matrix(init$v_mean)
    } else {
      matrix(rep(sigma_mean, each = Tn), nrow = Tn, ncol = K)
    }
    latent_inv_mean <- if (!is.null(init$v_inv_mean) && identical(dim(as.matrix(init$v_inv_mean)), c(Tn, K))) {
      as.matrix(init$v_inv_mean)
    } else {
      1 / pmax(latent_mean, .Machine$double.eps)
    }
  }
  s_mean <- if (!is.null(init$s_mean) && identical(dim(as.matrix(init$s_mean)), c(Tn, K))) {
    as.matrix(init$s_mean)
  } else matrix(sqrt(2 / pi), Tn, K)
  s2_mean <- if (!is.null(init$s2_mean) && identical(dim(as.matrix(init$s2_mean)), c(Tn, K))) {
    as.matrix(init$s2_mean)
  } else matrix(1, Tn, K)
  block_moments <- lapply(seq_len(K), function(k) {
    app_joint_exqdesn_point_scale_shape_moments(tau[[k]], gamma[[k]], sigma_mean[[k]])
  })
  trace <- vector("list", max_iter)
  quadrature_rows <- list()
  block_rows <- list()
  gamma_trace <- matrix(NA_real_, max_iter, K)
  sigma_trace <- matrix(NA_real_, max_iter, K)
  colnames(gamma_trace) <- colnames(sigma_trace) <- paste0("tau_", format(tau, trim = TRUE))
  converged <- FALSE
  qhat_old <- Z %*% app_joint_qvp_beta_matrix(beta_mean, K, p) + matrix(alpha, Tn, K, byrow = TRUE)
  rhs_summary <- app_joint_qvp_rhs_vb_summary(rhs_state, K, p)
  for (iter in seq_len(max_iter)) {
    beta_old <- beta_mean
    gamma_old <- gamma
    sigma_old <- sigma_mean
    precision <- prior$P_beta
    rhs <- rep(0, K * p)
    for (k in seq_len(K)) {
      idx <- ((k - 1L) * p + 1L):(k * p)
      m <- block_moments[[k]]
      if (identical(augmentation, "u")) {
        w <- m[["sigma_inv_mean"]] * latent_inv_mean[, k]
        linear <- w * (y - alpha[[k]]) -
          m[["lambda_mean"]] * s_mean[, k] * latent_inv_mean[, k] -
          m[["k_sigma_inv_mean"]]
      } else {
        w <- m[["inv_B_sigma_mean"]] * latent_inv_mean[, k]
        linear <- w * (y - alpha[[k]]) -
          m[["lambda_over_B_mean"]] * s_mean[, k] * latent_inv_mean[, k] -
          m[["A_inv_B_sigma_mean"]]
      }
      Zs <- Matrix::Matrix(Z, sparse = TRUE)
      precision[idx, idx] <- precision[idx, idx] + Matrix::t(Zs) %*% Matrix::Diagonal(x = w) %*% Zs
      rhs[idx] <- as.numeric(Matrix::t(Zs) %*% linear)
    }
    precision <- Matrix::forceSymmetric(precision)
    beta_mean <- as.numeric(Matrix::solve(precision, rhs))
    beta_cov <- solve(as.matrix(precision))
    beta_mat <- app_joint_qvp_beta_matrix(beta_mean, K, p)
    fitted_no_alpha <- Z %*% beta_mat
    beta_var <- lapply(seq_len(K), function(k) {
      idx <- ((k - 1L) * p + 1L):(k * p)
      rowSums((Z %*% beta_cov[idx, idx, drop = FALSE]) * Z)
    })
    for (k in seq_len(K)) {
      m <- block_moments[[k]]
      if (identical(augmentation, "u")) {
        w <- m[["sigma_inv_mean"]] * latent_inv_mean[, k]
        linear <- w * (y - fitted_no_alpha[, k]) -
          m[["lambda_mean"]] * s_mean[, k] * latent_inv_mean[, k] -
          m[["k_sigma_inv_mean"]]
      } else {
        w <- m[["inv_B_sigma_mean"]] * latent_inv_mean[, k]
        linear <- w * (y - fitted_no_alpha[, k]) -
          m[["lambda_over_B_mean"]] * s_mean[, k] * latent_inv_mean[, k] -
          m[["A_inv_B_sigma_mean"]]
      }
      prior_prec <- alpha_prior$precision[[k]]
      mean_alpha <- (sum(linear) + prior_prec * alpha_prior$mean[[k]]) / (sum(w) + prior_prec)
      lower <- if (k == 1L) -Inf else alpha[[k - 1L]] + alpha_min_spacing
      upper <- if (k == K) Inf else alpha[[k + 1L]] - alpha_min_spacing
      if (lower >= upper) stop("Ordered intercept bounds collapsed.", call. = FALSE)
      alpha[[k]] <- min(max(mean_alpha, lower), upper)
    }
    fitted_no_alpha <- Z %*% beta_mat
    block_updates <- vector("list", K)
    for (k in seq_len(K)) {
      m <- block_moments[[k]]
      r_mean <- y - alpha[[k]] - fitted_no_alpha[, k]
      r2_mean <- r_mean^2 + beta_var[[k]]
      if (identical(augmentation, "u")) {
        chi <- m[["sigma_inv_mean"]] * r2_mean -
          2 * m[["lambda_mean"]] * r_mean * s_mean[, k] +
          m[["sigma_lambda2_mean"]] * s2_mean[, k]
        psi <- rep(0.25 * m[["sigma_inv_mean"]], Tn)
      } else {
        chi <- m[["inv_B_sigma_mean"]] * r2_mean -
          2 * m[["lambda_over_B_mean"]] * r_mean * s_mean[, k] +
          m[["sigma_lambda2_over_B_mean"]] * s2_mean[, k]
        psi <- rep(m[["A2_inv_B_sigma_mean"]] + 2 * m[["sigma_inv_mean"]], Tn)
      }
      chi <- pmax(chi, .Machine$double.eps)
      psi <- pmax(psi, .Machine$double.eps)
      latent_mean[, k] <- app_joint_qvp_gig_moment(0.5, chi, psi, 1)
      latent_inv_mean[, k] <- app_joint_qvp_gig_moment(0.5, chi, psi, -1)
      if (identical(augmentation, "u")) {
        s_precision <- 1 + m[["sigma_lambda2_mean"]] * latent_inv_mean[, k]
        s_linear <- m[["lambda_mean"]] * r_mean * latent_inv_mean[, k] - m[["lambda_k_mean"]]
      } else {
        s_precision <- 1 + m[["sigma_lambda2_over_B_mean"]] * latent_inv_mean[, k]
        s_linear <- m[["lambda_over_B_mean"]] * r_mean * latent_inv_mean[, k] - m[["A_lambda_over_B_mean"]]
      }
      s_moments <- app_joint_qvp_truncnorm_positive_moments(
        mean = s_linear / s_precision,
        sd = sqrt(1 / s_precision)
      )
      s_mean[, k] <- s_moments$mean
      s2_mean[, k] <- s_moments$second
      block_updates[[k]] <- app_joint_exqdesn_structured_scale_shape_update(
        tau = tau[[k]], augmentation = augmentation,
        r_mean = r_mean, r2_mean = r2_mean,
        latent_mean = latent_mean[, k], latent_inv_mean = latent_inv_mean[, k],
        s_mean = s_mean[, k], s2_mean = s2_mean[, k],
        a_sigma = a_sigma, b_sigma = b_sigma,
        quadrature_nodes = quadrature_nodes,
        quadrature_tolerance = quadrature_tolerance
      )
      block_moments[[k]] <- block_updates[[k]]$moments
      gamma[[k]] <- block_moments[[k]][["gamma_mean"]]
      sigma_mean[[k]] <- block_moments[[k]][["sigma_mean"]]
      if (iter %% diagnostic_stride == 0L || iter == 1L || iter == max_iter) {
        quadrature_rows[[length(quadrature_rows) + 1L]] <- transform(
          block_updates[[k]]$diagnostics,
          iter = iter,
          quantile_index = k,
          tau = tau[[k]],
          augmentation = augmentation
        )
        block_rows[[length(block_rows) + 1L]] <- data.frame(
          iter = iter, quantile_index = k, tau = tau[[k]], augmentation = augmentation,
          t(block_moments[[k]]),
          negative_branch_mass = block_updates[[k]]$branch_mass[["negative"]],
          positive_branch_mass = block_updates[[k]]$branch_mass[["positive"]],
          quadrature_nodes_per_panel = block_updates[[k]]$nodes_per_panel,
          quadrature_relative_change = block_updates[[k]]$relative_change,
          quadrature_converged = block_updates[[k]]$converged,
          stringsAsFactors = FALSE,
          check.names = FALSE
        )
      }
    }
    rhs_update <- app_joint_qvp_update_rhs_vb_state(
      rhs_state = rhs_state, beta_mean = beta_mean, beta_cov = beta_cov,
      K = K, p = p, n_inner = rhs_vb_inner
    )
    rhs_state <- rhs_update$state
    prior_state <- app_joint_qvp_rhs_state_to_prior(rhs_state)
    prior <- app_joint_qvp_build_prior_precision(K, p, prior_state$anchor, prior_state$innovations)
    rhs_summary <- app_joint_qvp_rhs_vb_summary(rhs_state, K, p)
    qhat <- fitted_no_alpha + matrix(alpha, Tn, K, byrow = TRUE)
    max_beta_change <- max(abs(beta_mean - beta_old))
    max_gamma_change <- max(abs(gamma - gamma_old))
    max_sigma_change <- max(abs(sigma_mean - sigma_old))
    max_qhat_change <- max(abs(qhat - qhat_old))
    prior_quadratic <- 0.5 * app_joint_qvp_beta_prior_quadratic(beta_mean, beta_cov, prior$P_beta)
    beta_entropy_logdet <- 0.5 * app_joint_qvp_beta_logdet(beta_cov)
    scale_shape_log_normalizer <- sum(vapply(block_updates, `[[`, numeric(1L), "log_normalizer"))
    coordinate_monitor <- scale_shape_log_normalizer - prior_quadratic + beta_entropy_logdet
    gamma_trace[iter, ] <- gamma
    sigma_trace[iter, ] <- sigma_mean
    trace[[iter]] <- data.frame(
      iter = iter,
      max_beta_change = max_beta_change,
      max_gamma_change = max_gamma_change,
      max_sigma_change = max_sigma_change,
      max_qhat_change = max_qhat_change,
      rhs_mean_precision = mean(rhs_summary$mean_precision),
      rhs_max_precision = max(rhs_summary$max_precision),
      scale_shape_log_normalizer = scale_shape_log_normalizer,
      prior_quadratic = prior_quadratic,
      beta_entropy_logdet = beta_entropy_logdet,
      coordinate_monitor = coordinate_monitor,
      all_quadrature_converged = all(vapply(block_updates, `[[`, logical(1L), "converged")),
      stringsAsFactors = FALSE
    )
    qhat_old <- qhat
    if (max(max_beta_change, max_gamma_change, max_sigma_change, max_qhat_change) < tol) {
      converged <- TRUE
      trace <- trace[seq_len(iter)]
      gamma_trace <- gamma_trace[seq_len(iter), , drop = FALSE]
      sigma_trace <- sigma_trace[seq_len(iter), , drop = FALSE]
      break
    }
  }
  qhat_mean <- Z %*% app_joint_qvp_beta_matrix(beta_mean, K, p) + matrix(alpha, Tn, K, byrow = TRUE)
  trace_df <- do.call(rbind, trace)
  quadrature_trace <- if (length(quadrature_rows)) do.call(rbind, quadrature_rows) else data.frame()
  scale_shape_trace <- if (length(block_rows)) do.call(rbind, block_rows) else data.frame()
  final_scale_shape <- scale_shape_trace[
    ave(scale_shape_trace$iter, scale_shape_trace$quantile_index, FUN = max) == scale_shape_trace$iter,
    , drop = FALSE
  ]
  method_id <- method_id %||% if (identical(augmentation, "u")) "VB2_structured_u" else "VB1_structured_v"
  out <- list(
    beta_mean = beta_mean,
    beta_cov = beta_cov,
    alpha_mean = alpha,
    sigma_mean = sigma_mean,
    sigma_inv_mean = vapply(block_moments, `[[`, numeric(1L), "sigma_inv_mean"),
    gamma_mean = gamma,
    p_gamma_mean = vapply(block_moments, `[[`, numeric(1L), "p_gamma_mean"),
    s_mean = s_mean,
    s2_mean = s2_mean,
    rhs_state = rhs_state,
    rhs_prior_summary = rhs_summary,
    qhat_mean = qhat_mean,
    crossing_diagnostics = app_joint_qvp_crossing_diagnostics(qhat_mean, tau),
    trace = trace_df,
    gamma_trace = gamma_trace,
    sigma_trace = sigma_trace,
    quadrature_trace = quadrature_trace,
    scale_shape_trace = scale_shape_trace,
    scale_shape_summary = final_scale_shape,
    converged = converged,
    tau = tau,
    kappa = 1,
    augmentation = augmentation,
    inference_method_id = method_id,
    scale_shape_factor = "q_gamma_q_sigma_given_gamma",
    monitor_label = "structured_cavi_coordinate_monitor_not_full_elbo",
    objective_accounting_status = "partial_missing_local_and_point_alpha_entropy",
    alpha_prior_mean = alpha_prior$mean,
    alpha_prior_sd = alpha_prior$sd,
    alpha_prior_mean_source = alpha_prior$mean_source,
    manifest = app_joint_qvp_manifest_row(
      fit_id = sprintf("joint_exqdesn_%s_%s", method_id, format(Sys.time(), "%Y%m%d%H%M%S")),
      tau = tau, kappa = 1, likelihood = "exal",
      inference = method_id, seed = NA_integer_,
      status = if (converged) "experimental_success" else "experimental_max_iter"
    )
  )
  if (identical(augmentation, "u")) {
    out$u_mean <- latent_mean
    out$u_inv_mean <- latent_inv_mean
  } else {
    out$v_mean <- latent_mean
    out$v_inv_mean <- latent_inv_mean
  }
  class(out) <- c("joint_exqdesn_structured_vb_fit", "joint_qvp_qdesn_vb_fit", "list")
  out
}

app_joint_exqdesn_fit_exal_mcmc_u_collapsed <- function(
  y,
  Z,
  tau,
  n_iter = 200L,
  burn = 100L,
  thin = 1L,
  seed = NULL,
  kappa = 1,
  tau0 = 1,
  zeta2 = Inf,
  anchor_tau0 = tau0,
  innovation_tau0 = tau0,
  anchor_zeta2 = zeta2,
  innovation_zeta2 = zeta2,
  a_sigma = 0.1,
  b_sigma = 0.1,
  gamma_init = NULL,
  init = NULL,
  alpha_prior_mean = NULL,
  alpha_prior_sd = Inf,
  alpha_min_spacing = 0,
  max_dense_dim = 250L,
  gamma_slice_width = 1,
  gamma_slice_max_steps = 100L,
  gamma_coordinate = c("p_gamma_logit", "support_logit"),
  gamma_prior_type = "none",
  gamma_prior_center = 0,
  gamma_prior_sd_eta = NA_real_,
  method_id = NULL
) {
  if (!is.null(seed)) set.seed(seed)
  if (!identical(as.numeric(kappa), 1)) {
    stop("The exact u-augmented exAL sampler is restricted to kappa = 1.", call. = FALSE)
  }
  gamma_coordinate <- match.arg(gamma_coordinate)
  y <- as.numeric(y)
  Z <- app_joint_qvp_check_design(Z)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  Tn <- length(y)
  K <- length(tau)
  p <- ncol(Z)
  if (nrow(Z) != Tn) stop("length(y) must match nrow(Z).", call. = FALSE)
  n_iter <- as.integer(n_iter)
  burn <- as.integer(burn)
  thin <- as.integer(thin)
  if (n_iter <= 0L || burn < 0L || burn >= n_iter || thin <= 0L) {
    stop("Invalid MCMC iteration, burn, or thin controls.", call. = FALSE)
  }
  if (!is.finite(a_sigma) || a_sigma <= 0 || !is.finite(b_sigma) || b_sigma <= 0) {
    stop("a_sigma and b_sigma must be positive and finite.", call. = FALSE)
  }
  gamma_slice_width <- rep(as.numeric(gamma_slice_width), length.out = K)
  gamma_slice_max_steps <- rep(as.integer(gamma_slice_max_steps), length.out = K)
  if (any(!is.finite(gamma_slice_width) | gamma_slice_width <= 0) ||
      any(is.na(gamma_slice_max_steps) | gamma_slice_max_steps <= 0L)) {
    stop("Invalid gamma slice controls.", call. = FALSE)
  }
  normalized_init <- app_joint_qvp_normalize_init(init, K, p)
  alpha_prior <- app_joint_qvp_alpha_prior_spec(y, tau, alpha_prior_mean, alpha_prior_sd)
  gamma <- normalized_init$gamma %||%
    if (is.null(gamma_init)) app_joint_qvp_default_gamma(tau) else app_joint_qvp_check_gamma(tau, gamma_init)
  gamma <- app_joint_qvp_check_gamma(tau, gamma)
  beta <- normalized_init$beta %||% rep(0, K * p)
  alpha <- normalized_init$alpha %||% sort(as.numeric(stats::quantile(y, tau, names = FALSE, type = 8)))
  sigma <- normalized_init$sigma %||% rep(max(stats::mad(y), 1.0e-3), K)
  gamma_prior_center <- rep(as.numeric(gamma_prior_center), length.out = K)
  gamma_prior_sd_eta <- rep(as.numeric(gamma_prior_sd_eta), length.out = K)
  if (!identical(gamma_prior_type, "none")) {
    for (k in seq_len(K)) {
      invisible(app_joint_exqdesn_gamma_log_prior(
        tau[[k]], gamma[[k]], gamma_prior_type,
        gamma_prior_center[[k]], gamma_prior_sd_eta[[k]]
      ))
    }
  }
  constants <- lapply(seq_len(K), function(k) app_joint_exqdesn_constants(tau[[k]], gamma[[k]]))
  if (!is.null(init$u_mean) && identical(dim(as.matrix(init$u_mean)), c(Tn, K))) {
    u <- as.matrix(init$u_mean)
  } else if (!is.null(init$v_mean) && identical(dim(as.matrix(init$v_mean)), c(Tn, K))) {
    u <- as.matrix(init$v_mean)
    for (k in seq_len(K)) u[, k] <- u[, k] * constants[[k]]$B[[1L]]
  } else {
    u <- matrix(unlist(lapply(seq_len(K), function(k) rep(constants[[k]]$B[[1L]] * sigma[[k]], Tn))), nrow = Tn)
  }
  if (any(!is.finite(u) | u <= 0)) stop("Initial u values must be positive and finite.", call. = FALSE)
  s <- if (!is.null(init$s_mean) && identical(dim(as.matrix(init$s_mean)), c(Tn, K))) {
    pmax(as.matrix(init$s_mean), 0)
  } else {
    matrix(abs(stats::rnorm(Tn * K)), Tn, K)
  }
  rhs_state <- app_joint_qvp_initialize_rhs_state(
    K, p, tau0 = tau0, zeta2 = zeta2,
    anchor_tau0 = anchor_tau0, innovation_tau0 = innovation_tau0,
    anchor_zeta2 = anchor_zeta2, innovation_zeta2 = innovation_zeta2
  )
  keep_idx <- seq.int(burn + 1L, n_iter, by = thin)
  n_keep <- length(keep_idx)
  beta_draws <- matrix(NA_real_, n_keep, K * p)
  alpha_draws <- matrix(NA_real_, n_keep, K)
  sigma_draws <- matrix(NA_real_, n_keep, K)
  gamma_draws <- matrix(NA_real_, n_keep, K)
  p_gamma_draws <- matrix(NA_real_, n_keep, K)
  actual_sd_draws <- matrix(NA_real_, n_keep, K)
  sigma_lambda_draws <- matrix(NA_real_, n_keep, K)
  branch_draws <- matrix(NA_integer_, n_keep, K)
  gamma_density_evaluations <- integer(K)
  inverse_gamma_limit_draws <- integer(K)
  Z_stack <- app_joint_qvp_build_stacked_design(Z, K)
  keep_pos <- 0L
  for (iter in seq_len(n_iter)) {
    constants <- lapply(seq_len(K), function(k) app_joint_exqdesn_constants(tau[[k]], gamma[[k]]))
    prior_state <- app_joint_qvp_rhs_state_to_prior(rhs_state)
    prior <- app_joint_qvp_build_prior_precision(K, p, prior_state$anchor, prior_state$innovations)
    y_star <- numeric(Tn * K)
    weights <- numeric(Tn * K)
    for (k in seq_len(K)) {
      idx <- ((k - 1L) * Tn + 1L):(k * Tn)
      cst <- constants[[k]]
      y_star[idx] <- y - alpha[[k]] -
        cst$lambda[[1L]] * sigma[[k]] * s[, k] - cst$k[[1L]] * u[, k]
      weights[idx] <- 1 / (sigma[[k]] * u[, k])
    }
    beta_update <- app_joint_qvp_beta_gaussian_update(Z_stack, y_star, weights, prior$P_beta)
    beta <- app_joint_qvp_precision_draw(beta_update$mean, beta_update$precision, max_dense_dim = max_dense_dim)
    rhs_state <- app_joint_qvp_update_rhs_state(rhs_state, beta, K, p)
    beta_mat <- app_joint_qvp_beta_matrix(beta, K, p)
    fitted_no_alpha <- Z %*% beta_mat
    for (k in seq_len(K)) {
      cst <- constants[[k]]
      w <- 1 / (sigma[[k]] * u[, k])
      residual <- y - fitted_no_alpha[, k] -
        cst$lambda[[1L]] * sigma[[k]] * s[, k] - cst$k[[1L]] * u[, k]
      prior_prec <- alpha_prior$precision[[k]]
      precision <- sum(w) + prior_prec
      mean_alpha <- (sum(w * residual) + prior_prec * alpha_prior$mean[[k]]) / precision
      lower <- if (k == 1L) -Inf else alpha[[k - 1L]] + alpha_min_spacing
      upper <- if (k == K) Inf else alpha[[k + 1L]] - alpha_min_spacing
      if (lower >= upper) stop("Ordered intercept bounds collapsed.", call. = FALSE)
      alpha[[k]] <- app_joint_qvp_rtruncnorm(1L, mean_alpha, sqrt(1 / precision), lower, upper)
    }
    for (k in seq_len(K)) {
      cst <- app_joint_exqdesn_constants(tau[[k]], gamma[[k]])
      q <- y - alpha[[k]] - fitted_no_alpha[, k]
      chi_u <- (q - sigma[[k]] * cst$lambda[[1L]] * s[, k])^2 / sigma[[k]]
      psi_u <- rep(1 / (4 * sigma[[k]]), Tn)
      u[, k] <- app_joint_qvp_rgig(0.5, pmax(chi_u, .Machine$double.eps), psi_u, current = u[, k])
      s_precision <- 1 + sigma[[k]] * cst$lambda[[1L]]^2 / u[, k]
      s_mean <- cst$lambda[[1L]] * (q - cst$k[[1L]] * u[, k]) /
        (u[, k] + sigma[[k]] * cst$lambda[[1L]]^2)
      s[, k] <- app_joint_qvp_rtruncnorm(Tn, s_mean, sqrt(1 / s_precision), lower = 0)
      move <- app_joint_exqdesn_u_sigma_gamma_collapsed_draw(
        sigma = sigma[[k]], gamma = gamma[[k]], q = q, s = s[, k], u = u[, k],
        tau = tau[[k]], coordinate = gamma_coordinate,
        gamma_slice_width = gamma_slice_width[[k]],
        gamma_slice_max_steps = gamma_slice_max_steps[[k]],
        a_sigma = a_sigma, b_sigma = b_sigma,
        gamma_prior_type = gamma_prior_type,
        gamma_prior_center = gamma_prior_center[[k]],
        gamma_prior_sd_eta = gamma_prior_sd_eta[[k]]
      )
      sigma[[k]] <- move$sigma
      gamma[[k]] <- move$gamma
      gamma_density_evaluations[[k]] <- gamma_density_evaluations[[k]] + move$density_evaluations
      inverse_gamma_limit_draws[[k]] <- inverse_gamma_limit_draws[[k]] + as.integer(move$inverse_gamma_limit)
    }
    if (iter %in% keep_idx) {
      keep_pos <- keep_pos + 1L
      beta_draws[keep_pos, ] <- beta
      alpha_draws[keep_pos, ] <- alpha
      sigma_draws[keep_pos, ] <- sigma
      gamma_draws[keep_pos, ] <- gamma
      for (k in seq_len(K)) {
        cst <- app_joint_exqdesn_constants(tau[[k]], gamma[[k]])
        p_gamma_draws[keep_pos, k] <- cst$p_gamma[[1L]]
        actual_sd_draws[keep_pos, k] <- sigma[[k]] * cst$sd_factor[[1L]]
        sigma_lambda_draws[keep_pos, k] <- sigma[[k]] * cst$lambda[[1L]]
        branch_draws[keep_pos, k] <- as.integer(gamma[[k]] < 0)
      }
    }
  }
  beta_mean <- colMeans(beta_draws)
  alpha_mean <- colMeans(alpha_draws)
  qhat_mean <- Z %*% app_joint_qvp_beta_matrix(beta_mean, K, p) + matrix(alpha_mean, Tn, K, byrow = TRUE)
  method_id <- method_id %||% if (identical(gamma_coordinate, "p_gamma_logit")) {
    "M1_u_collapsed_p_logit"
  } else {
    "M1b_u_collapsed_support_logit"
  }
  out <- list(
    beta_draws = beta_draws,
    alpha_draws = alpha_draws,
    sigma_draws = sigma_draws,
    gamma_draws = gamma_draws,
    p_gamma_draws = p_gamma_draws,
    actual_sd_draws = actual_sd_draws,
    sigma_lambda_draws = sigma_lambda_draws,
    gamma_negative_branch_draws = branch_draws,
    beta_mean = beta_mean,
    alpha_mean = alpha_mean,
    sigma_mean = colMeans(sigma_draws),
    gamma_mean = colMeans(gamma_draws),
    p_gamma_mean = colMeans(p_gamma_draws),
    actual_sd_mean = colMeans(actual_sd_draws),
    qhat_mean = qhat_mean,
    crossing_diagnostics = app_joint_qvp_crossing_diagnostics(qhat_mean, tau),
    tau = tau,
    kappa = 1,
    augmentation = "u_equals_Bgamma_v",
    inference_method_id = method_id,
    gamma_update = paste0("u_sigma_collapsed_", gamma_coordinate),
    gamma_coordinate = gamma_coordinate,
    sigma_collapsed = TRUE,
    gamma_collapsed_density_evaluations = gamma_density_evaluations,
    inverse_gamma_limit_draws = inverse_gamma_limit_draws,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_mean = alpha_prior$mean,
    alpha_prior_sd = alpha_prior$sd,
    alpha_prior_mean_source = alpha_prior$mean_source,
    gamma_prior_type = gamma_prior_type,
    gamma_prior_center = gamma_prior_center,
    gamma_prior_sd_eta = gamma_prior_sd_eta,
    seed = seed,
    init_source = if (is.null(init)) "default" else "provided",
    manifest = app_joint_qvp_manifest_row(
      fit_id = sprintf("joint_exqdesn_%s_%s", method_id, format(Sys.time(), "%Y%m%d%H%M%S")),
      tau = tau, kappa = 1, likelihood = "exal", inference = method_id,
      seed = seed, status = "experimental_success"
    )
  )
  class(out) <- c("joint_exqdesn_exact_mcmc_fit", "joint_qvp_qdesn_tiny_fit", "list")
  out
}

app_joint_exqdesn_fixed_state_inverse_cdf_draw <- function(
  n,
  tau,
  q,
  s,
  u,
  a_sigma = 0.1,
  b_sigma = 0.1,
  gamma_prior_type = "none",
  gamma_prior_center = 0,
  gamma_prior_sd_eta = NA_real_,
  nodes_per_panel = 32L,
  seed = NULL
) {
  if (!is.null(seed)) set.seed(seed)
  n <- as.integer(n)
  if (n < 1L) stop("n must be positive.", call. = FALSE)
  stats <- app_joint_exqdesn_u_sufficient_stats(q, s, u)
  quadrature <- app_joint_exqdesn_normalize_branch_quadrature(
    tau = tau,
    log_density = function(gamma) app_joint_exqdesn_u_gamma_collapsed_log_kernel(
      gamma, tau, stats, a_sigma, b_sigma,
      gamma_prior_type, gamma_prior_center, gamma_prior_sd_eta
    ),
    node_grid = as.integer(nodes_per_panel),
    tolerance = Inf
  )
  index <- sample.int(nrow(quadrature$grid), size = n, replace = TRUE, prob = quadrature$grid$normalized_weight)
  gamma_draws <- quadrature$grid$gamma[index]
  sigma_draws <- vapply(gamma_draws, function(gamma) {
    terms <- app_joint_exqdesn_u_sigma_gig_terms(gamma, tau, stats, a_sigma, b_sigma)
    app_joint_exqdesn_rgig(terms$nu, terms$chi, terms$psi)
  }, numeric(1L))
  list(
    gamma_draws = gamma_draws,
    sigma_draws = sigma_draws,
    branch_mass = quadrature$branch_mass,
    quadrature = quadrature
  )
}
