# Generated scalar references for the existing AL latent-path approximation.
# These functions do not fit application data, read model objects or change the
# production inference implementation. Algorithm parity and statistical
# approximation accuracy are deliberately reported as separate quantities.

app_gftd_scalar_production_namespace <- function(repo_root) {
  path <- file.path(repo_root, "application", "R", "latent_path_vb_al.R")
  if (!file.exists(path)) stop("Missing production AL source.", call. = FALSE)
  out <- new.env(parent = baseenv())
  out$`%||%` <- function(x, y) if (is.null(x)) y else x
  sys.source(normalizePath(path, mustWork = TRUE), envir = out)
  needed <- c("app_latent_al_constants", "app_latent_update_v",
              "app_latent_update_future_gaussian_delta")
  if (!all(vapply(needed, exists, logical(1L), envir = out, inherits = FALSE))) {
    stop("Production AL coordinate helpers are incomplete.", call. = FALSE)
  }
  out
}

app_gftd_scalar_al_cdf <- function(y, p, mu = 0, sigma = 1) {
  if (length(p) != 1L || !is.finite(p) || p <= 0 || p >= 1 ||
      length(sigma) != 1L || !is.finite(sigma) || sigma <= 0 ||
      length(mu) != 1L || !is.finite(mu)) {
    stop("Invalid fixed AL parameter.", call. = FALSE)
  }
  z <- (as.numeric(y) - mu) / sigma
  ifelse(z < 0, p * exp((1 - p) * z),
         1 - (1 - p) * exp(-p * z))
}

app_gftd_scalar_reference <- function(p, sigma = 1, mu = 0, jitter = 0) {
  app_gftd_scalar_al_cdf(mu, p, mu, sigma)
  if (length(jitter) != 1L || !is.finite(jitter) || jitter < 0) {
    stop("Invalid numerical jitter.", call. = FALSE)
  }
  A <- (1 - 2 * p) / (p * (1 - p))
  B <- 2 / (p * (1 - p))
  lambda <- 1 / sigma + sqrt(1 / sigma^2 + 2 * jitter * B)
  mean <- mu + A / lambda
  variance <- B * sigma / (lambda + jitter * B * sigma)
  quantile <- mean + stats::qnorm(p) * sqrt(variance)
  list(A = A, B = B, lambda = lambda, mean = mean,
       variance = variance, quantile = quantile,
       cdf = app_gftd_scalar_al_cdf(quantile, p, mu, sigma))
}

app_gftd_scalar_rows <- function(mean, variance, mu, n_members = 51L) {
  n_members <- as.integer(n_members)
  if (length(n_members) != 1L || is.na(n_members) || n_members < 0L) {
    stop("Invalid generated member count.", call. = FALSE)
  }
  # Every member is an ordinary factor; its location is fixed here and cannot
  # inform the current Y. No descendants are present in this one-step fixture.
  members <- if (n_members) seq(-0.7, 1.3, length.out = n_members) else numeric()
  list(
    strategy = "streamed_grouped",
    source = c("Y", rep("G", n_members)),
    fixed = list(n = 0L, source = character(), H = matrix(0, 0L, 1L),
                 R = numeric(), e = numeric(), weight = numeric()),
    future = list(
      n_y = 1L, n_g = n_members,
      H_y = matrix(1, 1L, 1L), H_g_key = matrix(1, 1L, 1L),
      J_y = list(matrix(0, 1L, 1L)),
      J_g_key = list(matrix(0, 1L, 1L)),
      R_y = (mean - mu)^2 + variance, R_g = (members - mu)^2,
      e_y = mean - mu, e_g = members - mu,
      z_g = members, g_future_index = rep(1L, n_members),
      g_index_by_h = list(seq_len(n_members)),
      weight_y = 1, weight_g = rep(1, n_members)
    )
  )
}

app_gftd_scalar_actual <- function(production, p, sigma = 1, mu = 0,
                                  jitter = 1e-8, n_members = 51L,
                                  max_iter = 3000L, tolerance = 1e-12) {
  reference <- app_gftd_scalar_reference(p, sigma, mu, jitter)
  constants <- production$app_latent_al_constants(p)
  sigma_state <- list(inv_mean = c(Y = 1 / sigma, G = 1 / sigma))
  mean <- mu + 0.1 * sigma
  variance <- 0.4 * sigma^2
  rows <- app_gftd_scalar_rows(mean, variance, mu, n_members)
  v <- production$app_latent_update_v(rows, sigma_state, constants)
  old <- c((mean - mu) / sigma, variance / sigma^2,
           sigma * v$inv_mean[[1L]])
  converged <- FALSE
  repaired <- FALSE
  for (iteration in seq_len(max_iter)) {
    update <- production$app_latent_update_future_gaussian_delta(
      row_moments = rows, y_start = mean, theta_mean = mu,
      theta_cov = matrix(0, 1L, 1L), e_inv_v = v$inv_mean,
      sigma_state = sigma_state, constants = constants, jitter = jitter,
      future_gaussian_prior = NULL,
      include_future_y_working_likelihood = TRUE
    )
    mean <- as.numeric(update$mean)
    variance <- as.numeric(update$cov)
    repaired <- repaired || isTRUE(update$repaired)
    rows <- app_gftd_scalar_rows(mean, variance, mu, n_members)
    v <- production$app_latent_update_v(rows, sigma_state, constants)
    current <- c((mean - mu) / sigma, variance / sigma^2,
                 sigma * v$inv_mean[[1L]])
    if (max(abs(current - old)) <= tolerance) {
      converged <- TRUE
      break
    }
    old <- current
  }
  expected <- c((reference$mean - mu) / sigma,
                reference$variance / sigma^2, sigma * reference$lambda)
  quantile <- mean + stats::qnorm(p) * sqrt(variance)
  list(mean = mean, variance = variance, lambda = v$inv_mean[[1L]],
       quantile = quantile,
       cdf = app_gftd_scalar_al_cdf(quantile, p, mu, sigma),
       max_scaled_parity_error = max(abs(current - expected)),
       iteration = iteration, converged = converged, repaired = repaired,
       constants_parity_error = max(abs(c(constants$A - reference$A,
                                          constants$B - reference$B))))
}

app_gftd_scalar_density_reference_error <- function(production, p) {
  constants <- production$app_latent_al_constants(p)
  # v=t^2 removes the integrable square-root singularity at y=mu.
  mixture_density_at_location <- stats::integrate(function(t) {
    2 * t * stats::dnorm(0, constants$A * t^2,
                        sqrt(constants$B) * t) * exp(-t^2)
  }, lower = 0, upper = Inf, rel.tol = 1e-11, abs.tol = 1e-12)$value
  abs(mixture_density_at_location - p * (1 - p))
}

app_gftd_scalar_mixture_cdf_reference <- function(y, p, sigma = 1, mu = 0,
                                                constants = NULL) {
  app_gftd_scalar_al_cdf(mu, p, mu, sigma)
  if (length(y) != 1L || !is.finite(y)) {
    stop("The generated mixture-CDF reference requires one finite response.",
         call. = FALSE)
  }
  if (is.null(constants)) {
    constants <- list(A = (1 - 2 * p) / (p * (1 - p)),
                      B = 2 / (p * (1 - p)))
  }
  if (length(constants$A) != 1L || length(constants$B) != 1L ||
      any(!is.finite(c(constants$A, constants$B))) || constants$B <= 0) {
    stop("Invalid conditional Normal-mixture constants.", call. = FALSE)
  }
  z <- (y - mu) / sigma
  # This integrates the conditional Normal CDF against Exp(v; mean=sigma),
  # independently of the analytic AL CDF. With v=sigma*t^2 the Jacobian and
  # exponential mixing density give 2*t*exp(-t^2); all scales cancel exactly.
  integrand <- function(t) {
    out <- numeric(length(t))
    positive <- t > 0 & is.finite(t)
    tt <- t[positive]
    out[positive] <- 2 * tt * exp(-tt^2) *
      stats::pnorm((z - constants$A * tt^2) / (sqrt(constants$B) * tt))
    out
  }
  coarse <- stats::integrate(integrand, 0, Inf, rel.tol = 1e-9,
                              abs.tol = 1e-10, subdivisions = 1000L)
  fine <- stats::integrate(integrand, 0, Inf, rel.tol = 1e-11,
                            abs.tol = 1e-12, subdivisions = 1000L)
  list(value = fine$value, estimated_absolute_error = fine$abs.error,
       tightening_difference = abs(fine$value - coarse$value),
       coarse_subdivisions = coarse$subdivisions,
       fine_subdivisions = fine$subdivisions,
       reference = "independent_Normal_CDF_integral_against_Exp_scale_sigma")
}

app_gftd_scalar_diagnostics <- function(repo_root,
    probabilities = c(.05, .20, .35, .50, .65, .80, .95),
    scales = c(.1, 1, 10), jitters = c(0, 1e-8),
    parity_tolerance = 1e-9, cdf_tolerance = .005,
    production_env = NULL) {
  production <- if (is.null(production_env)) {
    app_gftd_scalar_production_namespace(repo_root)
  } else production_env
  grid <- expand.grid(p = probabilities, sigma = scales, jitter = jitters,
                      KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  density_errors <- vapply(probabilities, function(p) {
    app_gftd_scalar_density_reference_error(production, p)
  }, numeric(1L))
  location_cdf <- lapply(probabilities, function(p) {
    app_gftd_scalar_mixture_cdf_reference(0, p,
      constants = production$app_latent_al_constants(p))
  })
  rows <- lapply(seq_len(nrow(grid)), function(i) {
    p <- grid$p[[i]]
    sigma <- grid$sigma[[i]]
    jitter <- grid$jitter[[i]]
    actual <- app_gftd_scalar_actual(production, p, sigma, mu = .3,
                                     jitter = jitter, n_members = 51L)
    density_error <- density_errors[[match(p, probabilities)]]
    location_reference <- location_cdf[[match(p, probabilities)]]
    quantile_reference <- app_gftd_scalar_mixture_cdf_reference(
      actual$quantile, p, sigma, mu = .3,
      constants = production$app_latent_al_constants(p))
    cdf_reference_error <- abs(quantile_reference$value - actual$cdf)
    location_reference_error <- abs(location_reference$value - p)
    tightening_error <- max(location_reference$tightening_difference,
                             quantile_reference$tightening_difference)
    integration_error <- max(location_reference$estimated_absolute_error,
                               quantile_reference$estimated_absolute_error)
    cdf_error <- abs(quantile_reference$value - p)
    # Constant member cancellation is checked at the primary unit-scale cases;
    # repeating it at every scale adds no independent likelihood information.
    cancellation_error <- NA_real_
    if (sigma == 1 && jitter == 1e-8) {
      without <- app_gftd_scalar_actual(production, p, sigma, mu = .3,
                                       jitter = jitter, n_members = 0L)
      cancellation_error <- max(abs(c(actual$mean - without$mean,
                                       actual$variance - without$variance)))
    }
    data.frame(
      fixture = "one_step_fixed_parameter_augmented_al",
      p = p, sigma = sigma, jitter = jitter, mu = .3,
      iterations = actual$iteration,
      mean = actual$mean, variance = actual$variance,
      e_inverse_v = actual$lambda, reported_quantile = actual$quantile,
      exact_cdf_at_reported_quantile = quantile_reference$value,
      analytic_cdf_at_reported_quantile = actual$cdf,
      cdf_error = cdf_error,
      max_scaled_parity_error = actual$max_scaled_parity_error,
      constants_parity_error = actual$constants_parity_error,
      mixture_density_reference_error = density_error,
      mixture_cdf_at_location_error = location_reference_error,
      mixture_cdf_reference_error = cdf_reference_error,
      mixture_cdf_tightening_error = tightening_error,
      mixture_cdf_estimated_absolute_error = integration_error,
      member_cancellation_error = cancellation_error,
      reference_validity = if (density_error <= 1e-10 &&
        max(cdf_reference_error, location_reference_error, tightening_error,
            integration_error) <= 1e-8) "PASS" else "FAIL",
      implementation_parity = if (actual$max_scaled_parity_error <= parity_tolerance &&
        actual$constants_parity_error <= 1e-10 &&
        (is.na(cancellation_error) || cancellation_error <= 1e-10)) "PASS" else "FAIL",
      numerical_stability = if (actual$converged && !actual$repaired) "PASS" else "FAIL",
      approximation_accuracy = if (cdf_error <= cdf_tolerance) "PASS" else "FAIL",
      production_relevance = "isolated_scalar_benchmark_not_campaign_attribution",
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_gftd_scalar_marginal_gaussian_reference <- function(p, sigma = 1, mu = 0) {
  app_gftd_scalar_al_cdf(mu, p, mu, sigma)
  z <- stats::qnorm(p)
  sd <- sigma / stats::dnorm(z)
  mean <- mu - z * sd
  list(mean = mean, variance = sd^2, quantile = mean + z * sd,
       target = "fixed_parameter_marginal_al",
       role = "explanatory_contrast_not_a_qualified_nonlinear_replacement")
}

app_gftd_scalar_no_information_reference <- function(prior_variance = 2,
                                                    response_variance = 1) {
  if (any(!is.finite(c(prior_variance, response_variance))) ||
      prior_variance <= 0 || response_variance <= 0) {
    stop("Generated variances must be positive and finite.", call. = FALSE)
  }
  precision <- matrix(c(1 / prior_variance + 1 / response_variance,
                        -1 / response_variance,
                        -1 / response_variance,
                        1 / response_variance), 2L, 2L)
  exact_theta_variance <- solve(precision)[1L, 1L]
  product_vb_theta_variance <- 1 / precision[1L, 1L]
  list(exact_theta_variance = exact_theta_variance,
       product_vb_theta_variance = product_vb_theta_variance,
       exact_expected = prior_variance,
       product_vb_expected = 1 / (1 / prior_variance + 1 / response_variance),
       interpretation = "different_reference_answers_for_parity_and_accuracy")
}

# Stable entry point for the coordinator's generated-only diagnostic reporter.
gfts_run_scalar_diagnostics <- function(engine_env = NULL, repo_root = getwd()) {
  results <- app_gftd_scalar_diagnostics(repo_root, production_env = engine_env)
  checks <- data.frame(
    test_id = sprintf("scalar_al_p%g_s%g_j%g", results$p, results$sigma,
                      results$jitter),
    results[c("reference_validity", "implementation_parity",
              "numerical_stability", "approximation_accuracy",
              "production_relevance")],
    error = results$max_scaled_parity_error,
    tolerance = 1e-9,
    detail = sprintf("AL CDF at reported p-quantile %.12g; absolute CDF error %.12g; accuracy tolerance .005",
                     results$exact_cdf_at_reported_quantile, results$cdf_error),
    stringsAsFactors = FALSE
  )
  list(checks = checks, results = results,
       no_information_reference = app_gftd_scalar_no_information_reference(),
       scientific_runs = 0L, authentic_reads = 0L)
}
