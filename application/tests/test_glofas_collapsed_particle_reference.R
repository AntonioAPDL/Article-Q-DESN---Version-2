# Controlled exact-target mathematics; no original/model/draw object reads.
local({
  source("scripts/diagnostics/glofas_collapsed_particle_reference.R", local = TRUE)
  n <- 0L
  ok <- function(condition) { stopifnot(isTRUE(condition)); n <<- n + 1L }
  reject <- function(expr) ok(inherits(try(force(expr), silent = TRUE), "try-error"))
  members <- matrix(rep(c(.15, .22), 51L), 2L, 51L)
  for (p in c(.2, .5, .8)) for (lag in c(-.35, .35)) for (M in c(1L, 51L)) {
    G <- members[, seq_len(M), drop = FALSE]
    a <- gcpr_conditional(.1, .15, G, p, lag = lag)
    b <- gcpr_conditional_numeric(.1, .15, G, p, lag = lag)
    ok(abs(a$log_evidence - b) < 1e-9 &&
      max(abs(a$fisher_gradient - a$reparameterized_gradient)) < 1e-9 &&
      a$member_factors == 2L * M && all(a$member_weights == 1))
  }
  # Fisher's identity differentiates the complete centered density at FIXED
  # Y, including its future law; it is not a Gaussian update at fixed Z.
  for (lag in c(-.35, .35)) {
    a <- gcpr_conditional(.1, .15, members, .5, lag = lag)
    step <- 1e-6
    finite <- c(theta = (gcpr_conditional(.1 + step, .15, members, lag = lag)$log_evidence -
      gcpr_conditional(.1 - step, .15, members, lag = lag)$log_evidence) / (2 * step),
      log_sigma = (gcpr_conditional(.1, .15 * exp(step), members, lag = lag)$log_evidence -
      gcpr_conditional(.1, .15 * exp(-step), members, lag = lag)$log_evidence) / (2 * step))
    ok(max(abs(finite - a$fisher_gradient)) < 1e-6)
    cdf <- gcpr_conditional_cdf(c(-Inf, -.2, .1, .4, Inf), .1, .15, members, lag = lag)
    ok(cdf[1L] == 0 && abs(tail(cdf, 1L) - 1) < 1e-12 && all(diff(cdf) >= 0))
  }
  for (p in c(.2, .5)) for (previous in c(-.4, .7)) {
    mu <- .1 + .2 * previous
    integral <- stats::integrate(function(y) exp(gcpr_log_al(y, mu, p, .15)),
      -Inf, mu, rel.tol = 1e-11)$value +
      stats::integrate(function(y) exp(gcpr_log_al(y, mu, p, .15)), mu, Inf, rel.tol = 1e-11)$value
    ok(abs(integral - 1) < 1e-10)
  }

  empty <- gcpr_one_horizon_joint_scale()
  ok(abs(empty$log_evidence) < 1e-10 && abs(empty$normalization - 1) < 1e-10)
  ok(max(abs(c(empty$theta_mean - .1, empty$theta_variance - .04,
    empty$sigma_mean - .1, empty$sigma_variance - .005, empty$theta_sigma_covariance))) < 1e-10)
  ok(identical(empty$unknown_parameters, c("theta", "shared_AL_scale")) && !empty$production_qualified)
  joint <- gcpr_one_horizon_joint_scale(rep(.2, 51L), p = .2)
  ok(joint$conditional_sigma_shape == 55 && all(joint$member_weights == 1))
  ok(joint$theta_variance > 0 && joint$sigma_variance > 0 &&
    joint$theta_variance * joint$sigma_variance > joint$theta_sigma_covariance^2)
  ok(abs(joint$theta_mean - .1) > .05 && abs(joint$sigma_mean - .1) > .05 &&
    abs(joint$theta_sigma_covariance) > 1e-9)
  ok(all(diff(joint$future_cdf(c(-Inf, .1, .2, .3, Inf))) > 0) &&
    abs(tail(joint$future_cdf(c(-Inf, Inf)), 1L) - 1) < 1e-10)
  # The full joint density agrees with Normal(theta)*IG(sigma)*all51AL,
  # not a product of independently chosen posterior parameter marginals.
  for (theta in c(.19, .2, .22)) {
    sigma <- .007
    literal <- stats::dnorm(theta, .1, .2, log = TRUE) + gcpr_log_ig(sigma, 4, .3) +
      sum(gcpr_log_al(rep(.2, 51L), theta, .2, sigma))
    reconstructed <- log(joint$parameter_density(theta)) + joint$log_evidence +
      gcpr_log_ig(sigma, joint$conditional_sigma_shape, joint$conditional_sigma_rate(theta))
    ok(abs(literal - reconstructed) < 1e-9)
  }

  # A one-particle SMC normalizer is unbiased, but its expected logarithm is
  # strictly below log exact evidence when later-member weights vary.
  for (lag in c(-.35, .35)) {
    bound <- gcpr_log_bound_one_particle(.1, .15, members, lag = lag)
    ok(is.finite(bound$Jensen_gap) && bound$Jensen_gap > .01 &&
      bound$expected_log_estimate < bound$exact_log_evidence)
  }
  bound <- gcpr_log_bound_one_particle(.1, .15, matrix(numeric(), 2L, 0L))
  ok(bound$Jensen_gap == 0 && bound$expected_log_estimate == 0)

  # Both parameters remain random in the independent two-dimensional check.
  # Gamma moment shifting makes their no-member moments exact numerically.
  q0 <- gcpr_parameter_integral(NULL, theta_nodes = 32L, scale_nodes = 16L)
  ok(max(abs(c(q0$log_evidence, q0$theta_mean - .1, q0$theta_variance - .04,
    q0$sigma_mean - .1, q0$sigma_variance - .005, q0$theta_sigma_covariance))) < 1e-9)
  G <- matrix(c(.15, .22), 2L, 1L)
  coarse <- gcpr_parameter_integral(G, theta_nodes = 24L, scale_nodes = 24L)
  fine <- gcpr_parameter_integral(G, theta_nodes = 32L, scale_nodes = 32L)
  wide <- gcpr_parameter_integral(G, theta_nodes = 40L, scale_nodes = 32L, theta_range_sd = 12)
  values <- c("log_evidence", "theta_mean", "sigma_mean", "theta_variance", "sigma_variance", "theta_sigma_covariance")
  ok(max(abs(unlist(coarse[values]) - unlist(fine[values]))) < 5e-6)
  ok(max(abs(unlist(fine[values]) - unlist(wide[values]))) < 5e-7 &&
    fine$relative_outside_theta_evidence_bound < 1e-12 && wide$relative_outside_theta_evidence_bound < 1e-25)
  ok(fine$theta_variance > 0 && fine$sigma_variance > 0 &&
    abs(fine$theta_sigma_covariance) > 1e-6 && !fine$production_qualified)

  # At fixed innovations with no members, the future response density and
  # its transformation Jacobian cancel. Holding a response fixed instead
  # gives a different coefficient conditional; it cannot be reused at Z.
  fixed_y <- .4; theta <- .1; sigma <- .15; p <- .2
  centered_future_gradient <- (p - (fixed_y < theta)) / sigma
  ok(abs(centered_future_gradient) > 1 && 0 != centered_future_gradient)
  y1 <- theta + .3; lag <- .35
  member_gradient <- sum(.5 - (members[2L, ] < theta + lag * y1)) / .8
  ok(abs((1 + lag) * member_gradient - member_gradient) > 1)

  # Exact NS product hierarchy, not a normalized PV conditional prior.
  # Every auxiliary density is included in the pointwise identity.
  for (r in c(1L, 3L, 7L)) {
    beta <- seq(.03, .12, length.out = r); lambda2 <- seq(.7, 1.3, length.out = r)
    nu <- rep(.9, r); xi <- .8; zeta2 <- 4; tau0 <- .1
    xs <- c(.01, .1, .7)
    literal <- vapply(xs, function(x) gcpr_ns_log_joint(beta, x, lambda2, zeta2, xi, nu, tau0), numeric(1L))
    alternative <- vapply(xs, function(x) {
      effective <- 1 / (1 / (x * lambda2) + 1 / zeta2)
      sum(stats::dnorm(beta, 0, sqrt(effective), log = TRUE)) +
        sum(stats::dnorm(0, 0, sqrt(x * lambda2 + zeta2), log = TRUE)) +
        gcpr_log_ig(x, .5, 1 / xi) + gcpr_log_ig(xi, .5, 1 / tau0^2) +
        sum(gcpr_log_ig(lambda2, .5, 1 / nu)) + sum(gcpr_log_ig(nu, .5, 1)) + gcpr_log_ig(zeta2, 2, 4)
    }, numeric(1L))
    correct <- literal - gcpr_log_ig(xs, (r + 1) / 2, 1 / xi + .5 * sum(beta^2 / lambda2))
    wrong <- literal - gcpr_log_ig(xs, r / 2, 1 / xi + .5 * sum(beta^2 / lambda2))
    ok(max(abs(literal - alternative)) < 1e-10 && diff(range(correct)) < 1e-10 && diff(range(wrong)) > .1)
  }
  # Omitting the Normal-product overlap changes the global/local prior.
  overlap <- vapply(c(.01, .7), function(x)
    sum(stats::dnorm(0, 0, sqrt(x * c(.7, 1.3) + 4), log = TRUE)), numeric(1L))
  ok(abs(diff(overlap)) > .01)
  engine <- new.env(parent = baseenv())
  engine$`%||%` <- function(x, y) if (is.null(x)) y else x
  sys.source("application/R/latent_path_vb_al.R", envir = engine)
  state <- engine$app_latent_rhs_state_init(4L, 1L, list(tau0 = .1, zeta2_fixed = 4),
    list(freeze_tau_warmup_iters = 0L, update_every = 1L, min_tau_updates = 1L))
  mean <- c(.4, .1, -.2, .3); V <- diag(.02, 4L); before <- state
  after <- engine$app_latent_rhs_state_update(state, mean, V, iter = 1L)
  e2 <- mean[-1L]^2 + diag(V)[-1L]
  expected_lambda <- 1 / (before$e_inv_nu[-1L] + .5 * e2 * before$e_inv_tau2)
  expected_global <- ((3 + 1) / 2) / (before$e_inv_xi + .5 * sum(e2 * expected_lambda))
  ok(max(abs(after$e_inv_lambda2[-1L] - expected_lambda)) < 1e-12 &&
    abs(after$e_inv_tau2 - expected_global) < 1e-12)
  mean[1L] <- 1000
  shifted <- engine$app_latent_rhs_state_update(before, mean, V, iter = 1L)
  ok(identical(after$e_inv_tau2, shifted$e_inv_tau2) &&
    after$prior_precision[1L] == before$intercept_prec)
  learned <- engine$app_latent_rhs_state_init(4L, 1L, list(tau0 = .1, a_zeta = 2, b_zeta = 4),
    list(freeze_tau_warmup_iters = 0L, update_every = 1L, min_tau_updates = 1L))
  learned <- engine$app_latent_rhs_state_update(learned, mean, V, iter = 1L)
  ok(abs(learned$e_inv_zeta2 - (2 + 3 / 2) / (4 + .5 * sum(e2))) < 1e-12)
  reject(gcpr_contract(0, -1))
  reject(gcpr_one_horizon_joint_scale(rep(0, 2L)))
  reject(gcpr_parameter_integral(theta_range_sd = 7))
  cat(sprintf("GLOFAS_COLLAPSED_PARTICLE_REFERENCE_PASS checks=%d original_reads=0 application_fits=0 full_method_qualified=FALSE\n", n))
})
