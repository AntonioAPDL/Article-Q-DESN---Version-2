# Exact generated two-horizon AL smoothing reference. This is not an
# application-data analysis, a change to member weights, or a model refit.

gftsr_contract <- function(n_members = 51L) {
  n_members <- as.integer(n_members)
  if (length(n_members) != 1L || is.na(n_members) || n_members < 1L) {
    stop("Generated member count must be a positive integer.", call. = FALSE)
  }
  list(p = .5, sigma_y = .07, sigma_g = .05, g = -.1,
       slope = .05, n_members = n_members, breakpoints = c(-2, 0),
       role = "generated_information_strength_not_an_application_weight_proposal")
}

gftsr_log_kernel <- function(y, contract) {
  # Normalization constants independent of y cancel. G1 is constant in Y1,
  # and the independent future-Y2 density integrates to one. Every included
  # G2 member contributes one ordinary AL factor with weight one.
  -abs(as.numeric(y)) / (2 * contract$sigma_y) -
    contract$n_members * abs(contract$g - contract$slope * as.numeric(y)) /
      (2 * contract$sigma_g)
}

gftsr_peak <- function(contract) {
  max(gftsr_log_kernel(contract$breakpoints, contract))
}

gftsr_integrate <- function(contract, upper = Inf, tight = TRUE) {
  if (length(upper) != 1L || is.na(upper)) stop("Invalid integration endpoint.")
  if (upper == -Inf) return(list(value = 0, abs_error = 0))
  peak <- gftsr_peak(contract)
  points <- c(-Inf, contract$breakpoints, Inf)
  value <- error <- 0
  for (i in seq_len(length(points) - 1L)) {
    left <- points[i]
    right <- min(points[i + 1L], upper)
    if (right <= left) next
    integral <- stats::integrate(function(y) exp(gftsr_log_kernel(y, contract) - peak),
      lower = left, upper = right,
      rel.tol = if (tight) 1e-11 else 1e-9,
      abs.tol = if (tight) 1e-13 else 1e-11,
      subdivisions = 1000L)
    value <- value + integral$value
    error <- error + integral$abs.error
  }
  list(value = value, abs_error = error)
}

gftsr_cdf <- function(y, contract, tight = TRUE) {
  normalization <- gftsr_integrate(contract, tight = tight)$value
  if (!is.finite(normalization) || normalization <= 0) stop("Invalid normalization.")
  vapply(as.numeric(y), function(upper) {
    gftsr_integrate(contract, upper = upper, tight = tight)$value / normalization
  }, numeric(1L))
}

gftsr_piecewise_cdf <- function(y, contract) {
  # Independent closed-form oracle for the prescribed p=.5 fixture:
  # k(y)=exp{-a|y|-b|y+2|}. It does not use the numerical integration helper.
  if (contract$p != .5 || contract$g != -.1 || contract$slope != .05) {
    stop("Closed-form reference is scoped to the declared generated fixture.")
  }
  a <- 1 / (2 * contract$sigma_y)
  b <- contract$n_members * contract$slope / (2 * contract$sigma_g)
  peak <- max(-2 * a, -2 * b)
  left_mass <- exp(-2 * a - peak) / (a + b)
  start <- exp(-2 * a - peak)
  rate <- a - b
  middle_integral <- function(length) {
    if (abs(rate) < 1e-12) start * length else start * expm1(rate * length) / rate
  }
  middle_mass <- middle_integral(2)
  right_mass <- exp(-2 * b - peak) / (a + b)
  normalization <- left_mass + middle_mass + right_mass
  vapply(as.numeric(y), function(x) {
    if (x < -2) {
      exp((a + b) * x + 2 * b - peak) / (a + b) / normalization
    } else if (x < 0) {
      (left_mass + middle_integral(x + 2)) / normalization
    } else {
      (left_mass + middle_mass + right_mass * (-expm1(-(a + b) * x))) /
        normalization
    }
  }, numeric(1L))
}

gftsr_quantile <- function(probability, contract, tight = TRUE) {
  if (length(probability) != 1L || !is.finite(probability) ||
      probability <= 0 || probability >= 1) stop("Invalid target probability.")
  stats::uniroot(function(x) gftsr_cdf(x, contract, tight) - probability,
                  interval = c(-4, 2), tol = 1e-11)$root
}

gftsr_rows <- function(mean, covariance, contract) {
  n <- contract$n_members
  source <- c("Y", "Y", rep("G", 2L * n))
  Hy <- matrix(c(1, 1, 0, 0), 2L, 2L)
  Hg <- matrix(c(1, 1, 0, mean[1L]), 2L, 2L)
  Jy <- list(matrix(0, 2L, 2L), matrix(0, 2L, 2L))
  Jg <- list(matrix(0, 2L, 2L), matrix(c(0, 1, 0, 0), 2L, 2L))
  e_g <- c(rep(contract$g, n),
            rep(contract$g - contract$slope * mean[1L], n))
  R_g <- e_g^2 + c(rep(0, n), rep(contract$slope^2 * covariance[1L, 1L], n))
  list(strategy = "streamed_grouped", source = source,
    fixed = list(n = 0L, source = character(), R = numeric(), e = numeric(),
                 weight = numeric()),
    future = list(n_y = 2L, n_g = 2L * n, H_y = Hy, H_g_key = Hg,
      J_y = Jy, J_g_key = Jg, R_y = mean^2 + diag(covariance), R_g = R_g,
      e_y = mean, e_g = e_g, z_g = rep(contract$g, 2L * n),
      g_future_index = rep(1:2, each = n),
      g_index_by_h = list(seq_len(n), n + seq_len(n)),
      weight_y = rep(1, 2L), weight_g = rep(1, 2L * n)))
}

gftsr_engine <- function(root = ".") {
  env <- new.env(parent = baseenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  sys.source(file.path(root, "application/R/latent_path_vb_al.R"), envir = env)
  env
}

gftsr_actual_mean_field <- function(contract, engine, jitter = 1e-8,
                                    max_iter = 3000L, tolerance = 1e-12) {
  constants <- engine$app_latent_al_constants(.5)
  sigma_state <- list(inv_mean = c(Y = 1 / contract$sigma_y,
                                   G = 1 / contract$sigma_g))
  mean <- c(0, 0)
  covariance <- diag(rep(.02, 2L))
  rows <- gftsr_rows(mean, covariance, contract)
  local <- engine$app_latent_update_v(rows, sigma_state, constants)
  local_scales <- c(rep(contract$sigma_y, 2L),
                    rep(contract$sigma_g, 2L * contract$n_members))
  old <- c(mean / contract$sigma_y, covariance / contract$sigma_y^2,
           local_scales * local$inv_mean)
  converged <- FALSE
  repaired <- FALSE
  for (iteration in seq_len(max_iter)) {
    update <- engine$app_latent_update_future_gaussian_delta(
      rows, y_start = mean, theta_mean = c(0, contract$slope),
      theta_cov = matrix(0, 2L, 2L), e_inv_v = local$inv_mean,
      sigma_state = sigma_state, constants = constants, jitter = jitter,
      future_gaussian_prior = NULL, include_future_y_working_likelihood = TRUE)
    mean <- update$mean
    covariance <- update$cov
    repaired <- repaired || isTRUE(update$repaired)
    rows <- gftsr_rows(mean, covariance, contract)
    local <- engine$app_latent_update_v(rows, sigma_state, constants)
    current <- c(mean / contract$sigma_y, covariance / contract$sigma_y^2,
                 local_scales * local$inv_mean)
    if (max(abs(current - old)) <= tolerance) {
      converged <- TRUE
      break
    }
    old <- current
  }
  list(mean = mean, covariance = covariance, iterations = iteration,
       converged = converged, repaired = repaired,
       interpretation = "augmented_mean_field_not_the_exact_marginal_reference")
}

gftsr_run_smoothing_diagnostics <- function(engine_env = NULL, root = ".") {
  engine <- if (is.null(engine_env)) gftsr_engine(root) else engine_env
  cases <- checks <- quantile_tables <- list()
  for (n in c(1L, 51L)) {
    contract <- gftsr_contract(n)
    probabilities <- c(.05, .20, .35, .50, .65, .80, .95)
    quantiles <- vapply(probabilities, gftsr_quantile, numeric(1L), contract = contract)
    coarse_quantiles <- vapply(probabilities, gftsr_quantile, numeric(1L),
                                contract = contract, tight = FALSE)
    check_points <- sort(unique(c(-4, -2, -1, 0, 2, quantiles)))
    numerical_cdf <- gftsr_cdf(check_points, contract)
    analytic_cdf <- gftsr_piecewise_cdf(check_points, contract)
    cdf_error <- max(abs(numerical_cdf - analytic_cdf))
    cdf_tightening <- max(abs(numerical_cdf - gftsr_cdf(check_points, contract,
                                                       tight = FALSE)))
    quantile_tightening <- max(abs(quantiles - coarse_quantiles))
    norm <- gftsr_integrate(contract)
    norm_error <- norm$abs_error / norm$value
    actual <- gftsr_actual_mean_field(contract, engine)
    exact_median <- quantiles[probabilities == .5]
    exact_cdf_at_mean_field_median <- gftsr_cdf(actual$mean[1L], contract)
    cases[[as.character(n)]] <- data.frame(n_members = n,
      conditional_reference_location = 0, exact_median_y1 = exact_median,
      exact_cdf_at_conditional_location = gftsr_cdf(0, contract),
      mean_field_median_y1 = actual$mean[1L],
      mean_field_variance_y1 = actual$covariance[1L, 1L],
      mean_field_minus_exact_median = actual$mean[1L] - exact_median,
      exact_cdf_at_mean_field_median = exact_cdf_at_mean_field_median,
      mean_field_y2_mean = actual$mean[2L],
      iterations = actual$iterations,
      stringsAsFactors = FALSE)
    quantile_tables[[as.character(n)]] <- data.frame(n_members = n,
      probability = probabilities, exact_quantile = quantiles,
      exact_cdf = gftsr_piecewise_cdf(quantiles, contract),
      coarse_quantile = coarse_quantiles)
    for (what in c("cdf_piecewise", "cdf_tightening", "quantile_tightening",
                   "normalization_error")) {
      error <- switch(what, cdf_piecewise = cdf_error,
        cdf_tightening = cdf_tightening, quantile_tightening = quantile_tightening,
        normalization_error = norm_error)
      checks[[length(checks) + 1L]] <- data.frame(
        test_id = paste0("smoothing_n", n, "_", what),
        reference_validity = if (error <= 1e-8) "PASS" else "FAIL",
        implementation_parity = "NOT_ASSESSED",
        numerical_stability = if (is.finite(error)) "PASS" else "FAIL",
        approximation_accuracy = "EXACT_REFERENCE",
        production_relevance = "generated_later_member_smoothing_not_campaign_attribution",
        error = error, tolerance = 1e-8,
        detail = "Independent split integration, closed-form piecewise CDF and tightened integration.",
        stringsAsFactors = FALSE)
    }
    checks[[length(checks) + 1L]] <- data.frame(
      test_id = paste0("smoothing_n", n, "_mean_field_vs_exact_median"),
      reference_validity = if (max(cdf_error, cdf_tightening, quantile_tightening,
                                     norm_error) <= 1e-8) "PASS" else "FAIL",
      implementation_parity = "NOT_ASSESSED",
      numerical_stability = if (actual$converged && !actual$repaired) "PASS" else "FAIL",
      approximation_accuracy = if (abs(exact_cdf_at_mean_field_median - .5) <= .005)
        "PASS" else "FAIL",
      production_relevance = "actual_augmented_helper_on_generated_fixed_parameter_target",
      error = abs(exact_cdf_at_mean_field_median - .5), tolerance = .005,
      detail = "No requirement that augmented mean-field median equal the exact marginal median.",
      stringsAsFactors = FALSE)
  }
  list(schema_version = "glofas_fixed_target_smoothing_reference_v1",
       checks = do.call(rbind, checks), cases = do.call(rbind, cases),
       quantiles = do.call(rbind, quantile_tables),
       scientific_runs = 0L, authentic_reads = 0L,
       target = "AL(Y1;0,.07) times product of n ordinary AL(-.1;.05*Y1,.05) factors",
       scope = "Generated information-strength comparison; not attribution or a proposal to alter application weights.")
}
