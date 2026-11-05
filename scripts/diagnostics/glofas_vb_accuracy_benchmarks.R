# Generated complete-parameter targets for production coordinate helpers.
# This is not the application fitting driver: no saved fit, data, scientific
# callback, RHS update, campaign, scoring truth or publication is accessed.
# Gaussian/AL scales may be fixed in one fixture and unknown in another;
# every table states which parameters are uncertain. Parity is not accuracy.

gvab_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste0("GloFAS VB benchmark: ", message), call. = FALSE)
}

gvab_engine <- function(root = ".") {
  env <- new.env(parent = baseenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$setNames <- stats::setNames
  for (name in c("latent_path_vb_al.R", "latent_path_vb_normal.R")) {
    sys.source(file.path(root, "application/R", name), envir = env)
  }
  env
}

gvab_dependencies <- function(root = ".") {
  env <- new.env(parent = baseenv())
  sys.source(file.path(root, "scripts/diagnostics/glofas_coupled_parameter_reference.R"), env)
  env
}

gvab_members <- function(n, center = .2) {
  gvab_require(length(n) == 1L && n %in% c(0L, 1L, 51L), "member count must be 0, 1 or 51")
  rep(center, as.integer(n))
}

gvab_rows <- function(theta_mean, theta_variance, path_mean, path_covariance,
                      members = numeric(), bilinear = FALSE, second_members = numeric()) {
  m <- as.numeric(path_mean); V <- as.matrix(path_covariance); H <- length(m)
  gvab_require(H %in% 1:2 && identical(dim(V), c(H, H)) &&
    all(is.finite(c(theta_mean, theta_variance, m, V, members, second_members))) &&
    theta_variance >= 0 && min(eigen(V, symmetric = TRUE)$values) > 0 &&
    (!bilinear || (H == 2L && length(members) == length(second_members))),
    "finite one/two-horizon generated state required")
  n <- length(members)
  Hg <- matrix(if (bilinear) c(1, m[1L]) else 1, H, 1L)
  Jg <- lapply(seq_len(H), function(i) matrix(0, 1L, H))
  if (bilinear) Jg[[2L]][1L, 1L] <- 1
  z <- if (bilinear) c(members, second_members) else members
  index <- if (bilinear) rep(1:2, each = n) else rep(1L, n)
  e_g <- if (bilinear) c(members - theta_mean,
    second_members - theta_mean * m[1L]) else members - theta_mean
  R_g <- if (bilinear) c((members - theta_mean)^2 + theta_variance,
    (second_members - theta_mean * m[1L])^2 + theta_mean^2 * V[1L, 1L] +
      theta_variance * (m[1L]^2 + V[1L, 1L])) else e_g^2 + theta_variance
  list(strategy = "streamed_grouped", source = c(rep("Y", H), rep("G", length(z))),
    fixed = list(n = 0L, source = character(), H = matrix(numeric(), 0L, 1L),
      R = numeric(), e = numeric(), weight = numeric()),
    future = list(n_y = H, n_g = length(z), H_y = matrix(1, H, 1L), H_g_key = Hg,
      J_y = lapply(seq_len(H), function(i) matrix(0, 1L, H)), J_g_key = Jg,
      R_y = (m - theta_mean)^2 + diag(V) + theta_variance, R_g = R_g,
      e_y = m - theta_mean, e_g = e_g, z_g = z, b_y = lapply(m, function(x) x),
      y_cov = V, g_future_index = index,
      g_index_by_h = lapply(seq_len(H), function(h) which(index == h)),
      weight_y = rep(1, H), weight_g = rep(1, length(z))))
}

gvab_iterate <- function(engine, family = c("normal", "al"), probability = .5,
    prior_mean = .1, prior_variance = .09, response_scale = .07, member_scale = .05,
    members = numeric(), bilinear = FALSE, second_members = numeric(),
    unknown_scale = FALSE, scale_shape = 3, scale_rate = .4,
    max_iterations = 10000L, tolerance = 1e-12) {
  family <- match.arg(family)
  gvab_require(length(probability) == 1L && is.finite(probability) && probability > 0 && probability < 1 &&
    all(is.finite(c(prior_mean, prior_variance, response_scale, member_scale, scale_shape, scale_rate))) &&
    prior_variance >= 0 && response_scale > 0 && member_scale > 0 && scale_shape > 2 && scale_rate > 0 &&
    length(members) <= 51L && all(is.finite(members)) &&
    (!unknown_scale || (!bilinear && !length(members) && prior_variance == 0)) &&
    length(max_iterations) == 1L && max_iterations >= 1 && max_iterations <= 10000L &&
    is.finite(tolerance) && tolerance > 0 && tolerance <= 1e-7,
    "unsupported or unbounded generated target")
  constants <- if (family == "normal") list(A = 0, B = 1) else
    engine$app_latent_al_constants(probability)
  H <- if (bilinear) 2L else 1L
  tm <- prior_mean + if (prior_variance > 0) .02 else 0
  tv <- prior_variance
  ym <- rep(prior_mean + .05, H); YV <- diag(rep(response_scale, H), H)
  sigma <- list(inv_mean = c(Y = 1 / response_scale, G = 1 / member_scale))
  if (unknown_scale) sigma <- engine$app_latent_ig_expectations(
    c(Y = scale_shape, G = scale_shape), c(Y = scale_rate, G = scale_rate))
  prior <- if (prior_variance > 0) list(prior_precision = 1 / prior_variance,
    prior_linear = prior_mean / prior_variance) else NULL
  rows <- gvab_rows(tm, tv, ym, YV, members, bilinear, second_members)
  local <- if (family == "al") engine$app_latent_update_v(rows, sigma, constants) else
    list(mean = rep(1, H + length(rows$future$z_g)), inv_mean = rep(1, H + length(rows$future$z_g)))
  converged <- FALSE; repaired <- FALSE
  for (iteration in seq_len(as.integer(max_iterations))) {
    old <- c(tm, tv, ym, YV, sigma$inv_mean, local$mean, local$inv_mean)
    if (!is.null(prior)) {
      update <- engine$app_latent_update_theta(rows, local$inv_mean, sigma, constants, prior,
        fixed_stats_override = list(precision = matrix(0), rhs = 0))
      tm <- as.numeric(update$mean); tv <- as.numeric(update$cov)
      repaired <- repaired || isTRUE(update$repaired)
    }
    update <- engine$app_latent_update_future_gaussian_delta(rows, ym, tm, matrix(tv),
      local$inv_mean, sigma, constants, jitter = 0,
      future_gaussian_prior = NULL, include_future_y_working_likelihood = TRUE)
    ym <- as.numeric(update$mean); YV <- update$cov
    repaired <- repaired || isTRUE(update$repaired)
    rows <- gvab_rows(tm, tv, ym, YV, members, bilinear, second_members)
    if (family == "al") local <- engine$app_latent_update_v(rows, sigma, constants)
    if (unknown_scale) {
      sigma <- if (family == "normal") engine$app_latent_normal_sigma_update(rows,
        prior_sigma = list(a = scale_shape, b = scale_rate)) else
        engine$app_latent_update_sigma(rows, local$mean, local$inv_mean, constants,
          prior_sigma = list(a = scale_shape, b = scale_rate))
    }
    current <- c(tm, tv, ym, YV, sigma$inv_mean, local$mean, local$inv_mean)
    change <- max(abs(current - old) / pmax(1, abs(old)))
    if (is.finite(change) && change <= tolerance) { converged <- TRUE; break }
  }
  list(theta_mean = tm, theta_variance = tv, path_mean = ym, path_covariance = YV,
    theta_path_covariance = rep(0, H), sigma = sigma, local = local,
    iterations = iteration, residual = change, converged = converged, repaired = repaired,
    scientific_runs = 0L, authentic_reads = 0L,
    scope = "production_coordinate_helpers_on_generated_target_not_full_application_fitting_driver")
}

gvab_al_independent_cavi <- function(p, members, mu = .1, V = .09, sy = .07, sg = .05) {
  # Independent scalar expansion of the ordinary augmented AL target. No
  # production/GIG/matrix helper is called. Its fixed point is a parity oracle,
  # not the exact marginal posterior.
  A <- (1 - 2 * p) / (p * (1 - p)); B <- 2 / (p * (1 - p)); D <- A^2 + 2 * B
  tm <- mu + .02; tv <- V; ym <- mu + .05; yv <- sy
  local <- function(tm, tv, ym, yv) {
    R <- c((ym - tm)^2 + yv + tv, (members - tm)^2 + tv)
    scales <- c(sy, rep(sg, length(members)))
    list(inv = sqrt(D / R), mean = sqrt(R / D) + B * scales / D)
  }
  v <- local(tm, tv, ym, yv)
  for (iteration in seq_len(10000L)) {
    old <- c(tm, tv, ym, yv, v$inv, v$mean)
    tv <- 1 / (1 / V + v$inv[1L] / (B * sy) + sum(v$inv[-1L]) / (B * sg))
    tm <- tv * (mu / V + (v$inv[1L] * ym - A) / (B * sy) +
      sum((v$inv[-1L] * members - A) / (B * sg)))
    ym <- tm + A / v$inv[1L]; yv <- B * sy / v$inv[1L]
    v <- local(tm, tv, ym, yv)
    now <- c(tm, tv, ym, yv, v$inv, v$mean)
    if (max(abs(now - old) / pmax(1, abs(old))) < 1e-12) break
  }
  list(theta_mean = tm, theta_variance = tv, path_mean = ym, path_variance = yv,
    inverse_local = v$inv, iterations = iteration)
}

gvab_gaussian_two_reference <- function(n = 1L, mu = .4, V = .16,
                                        sy = .6, sg = .5, g1 = .8, g2 = .2) {
  gvab_members(n)
  # theta~N(mu,V), Y1,Y2|theta iid N(theta,sy), G1|theta~N(theta,sg),
  # G2|theta,Y1~N(theta*Y1,sg), with n literal factors at each horizon.
  # Integrate theta analytically conditional on Y1; integrate Y2 exactly.
  conditional <- function(y) {
    precision <- 1 / V + 1 / sy + n * (1 + y^2) / sg
    linear <- mu / V + y / sy + n * (g1 + y * g2) / sg
    list(mean = linear / precision, variance = 1 / precision,
      log_kernel = -.5 * (mu^2 / V + y^2 / sy + n * (g1^2 + g2^2) / sg) +
        .5 * linear^2 / precision - .5 * log(precision))
  }
  peak <- stats::optimize(function(y) conditional(y)$log_kernel, c(-8, 8),
    maximum = TRUE, tol = 1e-12)$objective
  kernel <- function(y) exp(conditional(y)$log_kernel - peak)
  integrate <- function(fun, upper = Inf, tight = TRUE) {
    points <- sort(unique(c(-Inf, -2, 0, mu, 2, Inf)))
    result <- 0
    for (j in seq_len(length(points) - 1L)) {
      right <- min(points[j + 1L], upper)
      if (right <= points[j]) next
      result <- result + stats::integrate(fun, points[j], right,
        rel.tol = if (tight) 1e-11 else 1e-8, abs.tol = if (tight) 1e-13 else 1e-10,
        subdivisions = 1000L)$value
    }
    result
  }
  norm <- integrate(kernel)
  density <- function(y) kernel(y) / norm
  ty <- integrate(function(y) conditional(y)$mean * density(y))
  y1 <- integrate(function(y) y * density(y))
  vt <- integrate(function(y) (conditional(y)$variance + (conditional(y)$mean - ty)^2) * density(y))
  vy <- integrate(function(y) (y - y1)^2 * density(y))
  cross <- integrate(function(y) (conditional(y)$mean - ty) * (y - y1) * density(y))
  cdf <- function(y, tight = TRUE) vapply(y, function(z) integrate(density, z, tight), numeric(1L))
  list(theta_mean = ty, theta_variance = vt, path_mean = c(y1, ty),
    path_covariance = matrix(c(vy, cross, cross, vt + sy), 2L),
    theta_path_covariance = c(cross, vt), cdf_y1 = cdf,
    normalization = integrate(density), coarse_normalization = integrate(density, tight = FALSE),
    original_reads = 0L, scope = "complete_generated_unknown_coefficient_known_variances_two_horizon_target")
}

gvab_two_independent_cavi <- function(n = 1L, mu = .4, V = .16, sy = .6, sg = .5, g1 = .8, g2 = .2) {
  tm <- mu; tv <- V; ym <- c(mu, mu); yv <- c(sy, sy)
  for (iteration in seq_len(10000L)) {
    old <- c(tm, tv, ym, yv)
    tv <- 1 / (1 / V + 2 / sy + n * (1 + ym[1L]^2 + yv[1L]) / sg)
    tm <- tv * (mu / V + sum(ym) / sy + n * (g1 + ym[1L] * g2) / sg)
    precision_y1 <- 1 / sy + n * (tm^2 + tv) / sg
    ym <- c((tm / sy + n * tm * g2 / sg) / precision_y1, tm)
    yv <- c(1 / precision_y1, sy)
    if (max(abs(c(tm, tv, ym, yv) - old)) < 1e-12) break
  }
  list(theta_mean = tm, theta_variance = tv, path_mean = ym, path_covariance = diag(yv))
}

gvab_gaussian_two_reverse_reference <- function(n = 1L, mu = .4, V = .16,
                                                sy = .6, sg = .5, g1 = .8, g2 = .2) {
  gvab_members(n)
  # Independent integration order: first Y1, then theta. For n>0 the product
  # of identical G2 densities is proportional to a density with variance sg/n;
  # its proportionality constant is independent of theta and cancels.
  conditional <- function(theta) {
    precision <- 1 / sy + n * theta^2 / sg
    list(mean = (theta / sy + n * theta * g2 / sg) / precision, variance = 1 / precision)
  }
  log_kernel <- function(theta) stats::dnorm(theta, mu, sqrt(V), log = TRUE) +
    n * stats::dnorm(g1, theta, sqrt(sg), log = TRUE) +
    if (n) stats::dnorm(g2, theta^2, sqrt(sg / n + theta^2 * sy), log = TRUE) else 0
  peak <- stats::optimize(log_kernel, c(-8, 8), maximum = TRUE, tol = 1e-12)$objective
  kernel <- function(theta) exp(log_kernel(theta) - peak)
  integrate <- function(f) {
    knots <- sort(unique(c(-Inf, -2, 0, mu, g1, 2, Inf)))
    sum(vapply(seq_len(length(knots) - 1L), function(i)
      stats::integrate(f, knots[i], knots[i + 1L], rel.tol = 1e-11,
        abs.tol = 1e-13, subdivisions = 1000L)$value, numeric(1L)))
  }
  norm <- integrate(kernel); density <- function(t) kernel(t) / norm
  mt <- integrate(function(t) t * density(t))
  my <- integrate(function(t) conditional(t)$mean * density(t))
  vt <- integrate(function(t) (t - mt)^2 * density(t))
  vy <- integrate(function(t) (conditional(t)$variance + (conditional(t)$mean - my)^2) * density(t))
  cross <- integrate(function(t) (t - mt) * (conditional(t)$mean - my) * density(t))
  c(theta_mean = mt, theta_variance = vt, y1_mean = my, y1_variance = vy, theta_y1_covariance = cross)
}

gvab_run_benchmarks <- function(root = ".", engine_env = NULL) {
  engine <- if (is.null(engine_env)) gvab_engine(root) else engine_env
  reference <- gvab_dependencies(root)
  checks <- list(); normal <- al <- scales <- two <- list()
  record <- function(id, parity, accuracy, error, tolerance, detail, stable = TRUE) {
    checks[[length(checks) + 1L]] <<- data.frame(test_id = id,
      reference_validity = "PASS", implementation_parity = if (parity) "PASS" else "FAIL",
      numerical_stability = if (is.finite(error) && isTRUE(stable)) "PASS" else "FAIL",
      approximation_accuracy = accuracy, production_relevance = "generated_complete_target_coordinate_helpers_only",
      error = error, tolerance = tolerance, detail = detail, stringsAsFactors = FALSE)
  }
  for (n in c(0L, 1L, 51L)) {
    members <- gvab_members(n)
    actual <- gvab_iterate(engine, "normal", prior_mean = .4, prior_variance = 1.1,
      response_scale = .8, member_scale = .5, members = members)
    exact_var <- 1 / (1 / 1.1 + n / .5)
    exact_mean <- exact_var * (.4 / 1.1 + sum(members) / .5)
    expected_vb_var <- 1 / (1 / exact_var + 1 / .8)
    parity <- max(abs(c(actual$theta_mean - exact_mean, actual$theta_variance - expected_vb_var,
      actual$path_mean - exact_mean, actual$path_covariance - .8)))
    normal[[as.character(n)]] <- data.frame(n_members = n, exact_theta_mean = exact_mean,
      vb_theta_mean = actual$theta_mean, exact_theta_variance = exact_var,
      vb_theta_variance = actual$theta_variance, exact_future_variance = exact_var + .8,
      vb_future_variance = actual$path_covariance[1L], exact_theta_future_covariance = exact_var,
      vb_theta_future_covariance = 0,
      relative_theta_variance_error = abs(actual$theta_variance / exact_var - 1),
      no_member_parameter_invariance = if (n == 0L) "FAIL" else "NOT_APPLICABLE_MEMBER_CONDITIONING",
      iterations = actual$iterations,
      target_unknown_parameters = "one_Normal_coefficient; both_variances_known")
    record(paste0("normal_coefficient_n", n), parity < 1e-9 && actual$converged && !actual$repaired,
      "FAIL", parity, 1e-9,
      "Actual theta/path coordinate parity; exact mean but independent factors omit covariance and contract variances.",
      stable = actual$converged && !actual$repaired)
  }
  for (p in c(.05, .5, .95)) for (n in c(0L, 1L, 51L)) {
    members <- gvab_members(n)
    exact <- reference$gcp_one_step_reference(prior_mean = .1, prior_sd = .3,
      probability = p, response_scale = .07, member_scale = .05, members = members)
    actual <- gvab_iterate(engine, "al", probability = p, members = members)
    independent <- gvab_al_independent_cavi(p, members)
    parity <- max(abs(c(actual$theta_mean - independent$theta_mean,
      actual$theta_variance - independent$theta_variance,
      actual$path_mean - independent$path_mean,
      actual$path_covariance - independent$path_variance,
      actual$local$inv_mean - independent$inverse_local)))
    quantile <- actual$path_mean + stats::qnorm(p) * sqrt(actual$path_covariance[1L])
    cdf <- exact$future_cdf(quantile)
    al[[paste(p, n)]] <- data.frame(probability = p, n_members = n,
      exact_theta_mean = exact$parameter_mean, vb_theta_mean = actual$theta_mean,
      exact_theta_variance = exact$parameter_variance, vb_theta_variance = actual$theta_variance,
      exact_future_variance = exact$future_variance, vb_future_variance = actual$path_covariance[1L],
      exact_theta_future_covariance = exact$coefficient_response_covariance,
      vb_theta_future_covariance = 0, vb_reported_quantile = quantile,
      exact_CDF_at_vb_quantile = cdf, absolute_CDF_error = abs(cdf - p),
      selected_quantile_accuracy = if (abs(cdf - p) <= .005) "PASS" else "FAIL",
      relative_theta_variance_error = abs(actual$theta_variance / exact$parameter_variance - 1),
      no_member_parameter_invariance = if (n == 0L) "FAIL" else "NOT_APPLICABLE_MEMBER_CONDITIONING",
      iterations = actual$iterations, target_unknown_parameters = "one_Normal_coefficient; both_AL_scales_known")
    record(paste0("al_coefficient_p", p, "_n", n), parity < 1e-8 && actual$converged && !actual$repaired,
      if (abs(cdf - p) <= .005 && abs(actual$theta_variance - exact$parameter_variance) < 1e-8) "PASS" else "FAIL",
      parity, 1e-8, "Independent scalar CAVI parity versus complete Normal-coefficient/AL-response exact marginal.",
      stable = actual$converged && !actual$repaired)
    gvab_require(abs(exact$parameter_normalization - 1) < 1e-8, "AL parameter reference normalization failed")
  }
  a <- 3; b <- .4
  for (family in c("normal", "al")) for (p in if (family == "normal") .5 else c(.05, .5, .95)) {
    actual <- gvab_iterate(engine, family, probability = p, prior_mean = .3, prior_variance = 0,
      unknown_scale = TRUE, scale_shape = a, scale_rate = b)
    extra <- if (family == "normal") .5 else 1.5
    A <- if (family == "normal") 0 else (1 - 2 * p) / (p * (1 - p))
    B <- if (family == "normal") 1 else 2 / (p * (1 - p))
    target_mean <- if (family == "normal") .3 else .3 + A * b / (a - 1)
    target_variance <- if (family == "normal") b / (a - 1) else
      (1 - 2 * p + 2 * p^2) / (p^2 * (1 - p)^2) * b^2 / ((a - 1) * (a - 2)) +
        A^2 * b^2 / ((a - 1)^2 * (a - 2))
    expected_mean <- .3 + if (family == "normal") 0 else A * b / (2 * a)
    expected_var <- if (family == "normal") b / a else B * b^2 / (2 * a^2)
    parity <- max(abs(c(actual$sigma$shape[["Y"]] - a - extra,
      actual$sigma$rate[["Y"]] - b * (a + extra) / a,
      actual$path_mean - expected_mean, actual$path_covariance - expected_var)))
    probability <- if (family == "normal") .05 else p
    quantile <- actual$path_mean + stats::qnorm(probability) * sqrt(actual$path_covariance[1L])
    e <- quantile - .3
    cdf <- if (family == "normal") stats::pt(e / sqrt(b / a), df = 2 * a) else
      if (e < 0) p * (b / (b - (1 - p) * e))^a else
        1 - (1 - p) * (b / (b + p * e))^a
    scales[[paste(family, p)]] <- data.frame(family = family, probability = p,
      scale_parameter = if (family == "normal") "Normal_variance" else "AL_scale",
      exact_scale_shape = a, exact_scale_rate = b, vb_scale_shape = actual$sigma$shape[["Y"]],
      vb_scale_rate = actual$sigma$rate[["Y"]], exact_scale_mean = b / (a - 1),
      vb_scale_mean = actual$sigma$mean[["Y"]], exact_future_mean = target_mean,
      vb_future_mean = actual$path_mean, exact_future_variance = target_variance,
      vb_future_variance = actual$path_covariance[1L], scored_probability = probability,
      exact_CDF_at_vb_quantile = cdf, absolute_CDF_error = abs(cdf - probability),
      selected_quantile_accuracy = if (abs(cdf - probability) <= .005) "PASS" else "FAIL",
      no_member_parameter_invariance = "FAIL",
      iterations = actual$iterations, target_unknown_parameters = "one_inverse_gamma_scale; location_known; no_members")
    record(paste0(family, "_unknown_scale_p", p), parity < 1e-8 && actual$converged && !actual$repaired,
      "FAIL", parity, 1e-8,
      "Normalized no-member transition leaves exact scale prior invariant; actual factorized updates change its shape/rate.",
      stable = actual$converged && !actual$repaired)
  }
  for (n in c(0L, 1L, 51L)) {
    exact <- gvab_gaussian_two_reference(n)
    reverse <- gvab_gaussian_two_reverse_reference(n)
    reference_error <- max(abs(c(exact$theta_mean, exact$theta_variance,
      exact$path_mean[1L], exact$path_covariance[1L, 1L], exact$theta_path_covariance[1L]) - reverse))
    gvab_require(reference_error < 1e-8, "independent two-horizon integration orders disagree")
    actual <- gvab_iterate(engine, "normal", prior_mean = .4, prior_variance = .16,
      response_scale = .6, member_scale = .5, members = gvab_members(n, .8),
      second_members = gvab_members(n, .2), bilinear = TRUE)
    independent <- gvab_two_independent_cavi(n)
    parity <- max(abs(c(actual$theta_mean - independent$theta_mean,
      actual$theta_variance - independent$theta_variance,
      actual$path_mean - independent$path_mean, actual$path_covariance - independent$path_covariance)))
    quantile <- actual$path_mean[1L] + stats::qnorm(.05) * sqrt(actual$path_covariance[1L, 1L])
    cdf <- exact$cdf_y1(quantile)
    two[[as.character(n)]] <- data.frame(n_members = n, exact_theta_mean = exact$theta_mean,
      vb_theta_mean = actual$theta_mean, exact_theta_variance = exact$theta_variance,
      vb_theta_variance = actual$theta_variance, exact_y1_mean = exact$path_mean[1L],
      vb_y1_mean = actual$path_mean[1L], exact_y1_variance = exact$path_covariance[1L, 1L],
      vb_y1_variance = actual$path_covariance[1L, 1L], exact_theta_y1_covariance = exact$theta_path_covariance[1L],
      vb_theta_y1_covariance = 0, exact_y1_y2_covariance = exact$path_covariance[1L, 2L],
      vb_y1_y2_covariance = actual$path_covariance[1L, 2L], exact_CDF_at_vb_lower_quantile = cdf,
      absolute_CDF_error = abs(cdf - .05), normalization_error = abs(exact$normalization - 1),
      selected_quantile_accuracy = if (abs(cdf - .05) <= .005) "PASS" else "FAIL",
      no_member_parameter_invariance = if (n == 0L) "FAIL" else "NOT_APPLICABLE_MEMBER_CONDITIONING",
      tightening_error = abs(exact$coarse_normalization - exact$normalization),
      independent_integration_order_error = reference_error,
      iterations = actual$iterations,
      target_unknown_parameters = "one_Normal_coefficient; both_variances_known; later_member_location_theta_times_Y1")
    record(paste0("two_horizon_unknown_coefficient_n", n), parity < 1e-8 && actual$converged && !actual$repaired,
      if (abs(cdf - .05) <= .005 && abs(actual$theta_variance - exact$theta_variance) < 1e-8) "PASS" else "FAIL",
      parity, 1e-8, "Actual production theta/path helpers versus independent mean-field equations; exact conditional integration preserves parameter/path dependence.",
      stable = actual$converged && !actual$repaired)
    gvab_require(max(abs(exact$normalization - 1), abs(exact$normalization - exact$coarse_normalization)) < 1e-8,
      "two-horizon reference normalization failed")
  }
  list(schema_version = "glofas_actual_vb_accuracy_benchmarks_v1", checks = do.call(rbind, checks),
    normal_coefficient = do.call(rbind, normal), al_coefficient = do.call(rbind, al),
    unknown_scale = do.call(rbind, scales), two_horizon = do.call(rbind, two),
    blocked = data.frame(scope = c("full_application_fitting_driver", "joint_parameter_path_factor",
      "unknown_RHS_and_slab", "exAL_scale_shape", "MQ_separate_path_prior", "nonlinear_DESN_features"),
      status = "NOT_QUALIFIED", reason = c("Only actual coordinate helpers are invoked, not a production fit.",
      "Production representation separates theta and future path; cross covariance cannot be represented.",
      "Generated proper Normal coefficient priors are not an RHS hierarchy.",
      "These references do not integrate unknown exAL shape/support.",
      "No across-quantile target or separate-path factorization is benchmarked.",
      "Affine generated features do not authenticate a fitted recurrent design."), stringsAsFactors = FALSE),
    scientific_runs = 0L, authentic_reads = 0L, full_parameter_refits = 0L,
    production_change = FALSE, article_change = FALSE,
    computation = list(future_helper_jitter = 0, coordinate_relative_tolerance = 1e-12,
      maximum_coordinate_iterations = 10000L, generated_quantile_CDF_tolerance = .005,
      actual_helpers = c("app_latent_update_theta", "app_latent_update_future_gaussian_delta",
        "app_latent_update_v", "app_latent_update_sigma", "app_latent_normal_sigma_update"),
      full_target_failure_interpretation = "Departure from exact complete-target marginal moments/dependence, not a production forecast-accuracy threshold.",
      stabilization_scope = "Zero jitter isolates target/approximation errors; existing affine diagnostics separately test production stabilization."),
    interpretation = "Coordinate parity and complete generated-target accuracy are separate. Failures expose a possible approximation mechanism, not its contribution to the application loss.")
}
