#!/usr/bin/env Rscript
# Deterministic reference and production-kernel checks; no application fit.
local({
  if (!exists("app_set_repo_root", mode = "function")) {
    source("application/R/00_packages.R")
    app_set_repo_root(getwd())
  }
  for (file in c("latent_path_vb_al.R", "latent_path_vb_normal.R",
    "joint_qvp_qdesn.R", "joint_exqdesn_exact_structured_inference.R",
    "latent_path_vb_exal.R", "fit_qdesn_latent_path.R")) {
    source(app_path("application/R", file), local = TRUE)
  }
  receipts <- list()
  record <- function(name, error, tolerance = 1e-9) {
    if (length(error) != 1L || !is.finite(error) || error > tolerance) {
      stop(sprintf("%s failed: error=%s tolerance=%g", name, error, tolerance), call. = FALSE)
    }
    receipts[[length(receipts) + 1L]] <<- data.frame(check = name, error = error,
      tolerance = tolerance, status = "PASS")
  }
  p_grid <- c(.05, .20, .35, .50, .65, .80, .95)
  al_A <- function(p) (1-2*p)/(p*(1-p))
  al_B <- function(p) 2/(p*(1-p))
  al_cdf <- function(r, p) {
    value <- numeric(length(r))
    left <- r < 0
    value[left] <- p*exp((1-p)*r[left])
    value[!left] <- 1-(1-p)*exp(-p*r[!left])
    value
  }
  log_al <- function(r, p, sigma) log(p*(1-p))-log(sigma)-r*(p-as.numeric(r < 0))/sigma
  for (p in p_grid) {
    constants <- app_latent_al_constants(p)
    record(paste("AL constants", p), max(abs(c(constants$A-al_A(p), constants$B-al_B(p)))))
    for (sigma in c(.4, 2)) for (residual in c(-.7, 0, .9)) {
      density <- integrate(function(u) {
        dnorm(residual, al_A(p)*sigma*u, sigma*sqrt(al_B(p)*u))*dexp(u)
      }, 0, Inf, rel.tol = 1e-10, subdivisions = 1000L)$value
      record(paste("AL marginal", p, sigma, residual),
        abs(density-exp(log_al(residual, p, sigma))))
    }
    support <- app_joint_exqdesn_support(p)
    for (gamma in c(.8*support$lower, .25*support$lower, 0,
                    .25*support$upper, .8*support$upper)) {
      cst <- app_joint_exqdesn_constants(p, gamma)
      probability <- integrate(function(s) {
        al_cdf(-cst$lambda*s, cst$p_gamma)*2*dnorm(s)
      }, 0, Inf, rel.tol = 1e-11, subdivisions = 1000L)$value
      record(paste("exAL component quantile", p, gamma), abs(probability-p))
    }
  }

  # All 51 Gaussian members identify beta+delta, not both components separately.
  members <- seq(-2, 2, length.out = 51L)
  member_variance <- .7
  cache <- list(beta_index = 1L, alpha_index = 2L, p = 2L,
    Y = list(Pbb = matrix(0, 1L, 1L), rb = 0, yty = 0, n_weight = 0),
    G = list(Pbb = matrix(51, 1L, 1L), Pba = matrix(51, 1L, 1L),
      Paa = matrix(51, 1L, 1L), rb = sum(members), ra = sum(members),
      yty = sum(members^2), n_weight = 51))
  sigma_state <- list(inv_mean = c(Y = 1, G = 1/member_variance))
  stats <- app_latent_normal_fixed_theta_stats(cache, sigma_state)
  expected_increment <- matrix(51/member_variance, 2L, 2L)
  record("Gaussian full likelihood precision", max(abs(stats$precision-expected_increment)))
  record("Gaussian sum direction only", max(abs(stats$precision %*% c(1, -1))))
  prior_precision <- diag(c(1, 2))
  prior_mean <- c(.2, -.1)
  posterior <- app_latent_solve_spd(prior_precision+stats$precision,
    prior_precision %*% prior_mean+stats$rhs)
  exact_cov <- solve(prior_precision+expected_increment)
  exact_mean <- exact_cov %*% (prior_precision %*% prior_mean+
    rep(sum(members)/member_variance, 2L))
  record("Gaussian full posterior mean", max(abs(posterior$mean-exact_mean)))
  record("Gaussian full posterior covariance", max(abs(posterior$cov-exact_cov)))
  stopifnot(posterior$cov[1L, 2L] < 0)
  H <- matrix(1, length(members), 2L)
  m <- c(.2, -.1)
  V <- matrix(c(.4, -.1, -.1, .3), 2L)
  direct_sse <- sum((members-as.numeric(H %*% m))^2)+
    sum(diag(H %*% V %*% t(H)))
  cached_sse <- app_latent_normal_fixed_expected_sse(cache, m, V)
  record("Gaussian reference/discrepancy cross-covariance in SSE",
    abs(cached_sse[["G"]]-direct_sse))

  # Feed the real local/scale functions a fixed included-member block.
  residual <- members-.31
  moments <- list(strategy = "dense_debug", fixed = list(n = 51L,
    source = rep("G", 51L), weight = rep(1, 51L), e = residual,
    R = residual^2), rows = list())
  normal_scale <- app_latent_normal_sigma_update(moments, list(a = 2, b = 1))
  record("Normal source variance counts 51 unit members", abs(normal_scale$shape[["G"]]-(2+51/2)))
  record("Normal source variance residual rate", abs(normal_scale$rate[["G"]]-(1+sum(residual^2)/2)))
  for (p in p_grid) {
    constants <- app_latent_al_constants(p)
    local <- app_latent_update_v(moments, sigma_state, constants)
    chi <- residual^2/(member_variance*al_B(p))
    psi <- rep((al_A(p)^2/al_B(p)+2)/member_variance, 51L)
    record(paste("AL local unit inverse moments", p),
      max(abs(local$inv_mean-sqrt(psi/chi))))
    record(paste("AL local unit first moments", p),
      max(abs(local$mean-(sqrt(chi/psi)+1/psi))))
    scale <- app_latent_update_sigma(moments, local$mean, local$inv_mean,
      constants, list(a = 2, b = 1))
    expected_rate <- 1+sum(local$mean+
      (local$inv_mean*residual^2-2*al_A(p)*residual+al_A(p)^2*local$mean)/(2*al_B(p)))
    record(paste("AL unit scale shape", p), abs(scale$shape[["G"]]-(2+1.5*51)))
    record(paste("AL unit scale rate", p), abs(scale$rate[["G"]]-expected_rate), 1e-8)
  }

  # Actual exAL structured kernel, including shape-dependent cross/normalizers.
  r <- c(-.7, .2, 1.1)
  v <- c(.4, .9, 1.7)
  s <- c(.3, .8, 1.2)
  sigma_grid <- c(.3, .7, 1.3, 2.5)
  for (p in p_grid) for (gamma in c(-.025, 0, .025)) {
    cst <- app_joint_exqdesn_constants(p, gamma)
    terms <- app_joint_exqdesn_structured_terms_grid(gamma, p, "v",
      r, r^2, v, 1/v, s, s^2, a_sigma = 2, b_sigma = 1,
      observation_weight = rep(1, 3L))
    direct <- vapply(sigma_grid, function(sigma) {
      -3*log(sigma)-1/sigma +
        sum(dnorm(r, cst$A*v+sigma*cst$lambda*s, sqrt(sigma*cst$B*v), log = TRUE))+
        sum(dexp(v, rate = 1/sigma, log = TRUE))+
        sum(log(2)+dnorm(s, log = TRUE))
    }, numeric(1L))
    kernel <- terms$log_shape+terms$cross+(terms$nu-1)*log(sigma_grid)-
      (terms$chi/sigma_grid+terms$psi*sigma_grid)/2
    offset <- direct-kernel
    record(paste("Production exAL scale kernel", p, gamma),
      max(abs(offset-offset[1L])), 1e-9)
    record(paste("Production exAL included source count", p, gamma), abs(terms$nu-(-2-1.5*3)))
  }

  # Versioned policy: unit members, not horizon averages; old policy unchanged.
  ensemble <- data.frame(target_date = rep(as.Date("2022-12-26")+0:1, each = 51L),
    horizon = rep(1:2, each = 51L))
  unit <- app_glofas_latent_path_ensemble_weights(ensemble, "unit_member_likelihood_v1")
  legacy <- app_glofas_latent_path_ensemble_weights(ensemble)
  record("Unit weights for every included member", max(abs(unit-1)))
  record("Legacy default unchanged", max(abs(legacy-1/51)))
  record("Unit counts per horizon", max(abs(tapply(unit, ensemble$horizon, sum)-51)))
  record("Legacy total per horizon", max(abs(tapply(legacy, ensemble$horizon, sum)-1)))
  omitted <- list(strategy = "streamed_grouped", fixed = list(n = 0L, weight = numeric()),
    future = list(n_y = 2L, n_g = 102L, weight_y = c(1,1), weight_g = unit), metadata = list())
  omitted <- app_latent_apply_future_y_weight_policy(omitted, include = FALSE)
  stopifnot(identical(omitted$future$weight_y, c(0,0)),
    identical(omitted$future$weight_g, unit),
    !omitted$metadata$future_y_working_likelihood_used)
  record("Replaced future-Y factors stay excluded", 0)

  # Exact singular limit is not a finite inverse moment. Do not compare a
  # numerical epsilon floor to a false finite E(1/V) reference at r=0.
  gamma_mean <- integrate(function(v) v*dgamma(v, .5, rate = 2),
    0, Inf, rel.tol = 1e-10)$value
  record("Zero-residual Gamma limit mean", abs(gamma_mean-.25))
  truncated_inverse <- function(epsilon, rate = 2) {
    2*sqrt(rate)/(sqrt(pi*epsilon))*exp(-rate*epsilon)-
      4*rate*pnorm(-sqrt(2*rate*epsilon))
  }
  inverse_large <- truncated_inverse(1e-8)
  inverse_small <- truncated_inverse(1e-4)
  stopifnot(inverse_large > 50*inverse_small)

  if (identical(Sys.getenv("QDESN_TEST_VERBOSE"), "1")) {
    print(do.call(rbind, receipts), row.names = FALSE)
  }
  cat("maximum_absolute_error=", max(vapply(receipts, function(x) x$error, numeric(1))), "\n", sep = "")
  cat("GLOFAS_UNIT_MEMBER_MATH_REFERENCE_PASS", length(receipts), "\n")
})
