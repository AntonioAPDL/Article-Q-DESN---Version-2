# Generated known-answer checks of the existing Gaussian--Delta path update.
# No fit, retained design, scoring truth, or scientific runtime is read here.

gfta_engine <- function(root = ".") {
  env <- new.env(parent = baseenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  # The production file defines functions only. Its Gaussian--Delta helper and
  # matrix helpers used below need base/recommended R, not the fitting harness.
  sys.source(file.path(root, "application/R/latent_path_vb_al.R"), envir = env)
  env
}

gfta_norm <- function(x) sqrt(sum(as.numeric(x)^2))

gfta_fixture <- function(horizon = 2L, n_members = 51L, nonlinear = FALSE) {
  horizon <- as.integer(horizon)
  n_members <- as.integer(n_members)
  if (!horizon %in% 1:2 || n_members < 0L) stop("Unsupported generated fixture.")
  list(horizon = horizon, n_members = n_members, nonlinear = isTRUE(nonlinear),
    history_y = .3, issued_centers = c(.9, 1.1),
    theta_mean = c(.7, .35, -.2, -.15),
    sigma = c(Y = .8, G = .5),
    variance_y = .9,
    members = if (n_members) vapply(seq_len(horizon), function(h)
      .2 + .1 * h + seq(-.3, .3, length.out = n_members), numeric(n_members)) else
        matrix(numeric(), 0L, horizon))
}

gfta_features <- function(fixture, y) {
  H <- fixture$horizon
  y <- as.numeric(y)
  if (length(y) != H || any(!is.finite(y))) stop("Generated path is not aligned.")
  Hy <- Hg <- matrix(0, H, 4L)
  Jy <- Jg <- vector("list", H)
  for (h in seq_len(H)) {
    previous <- if (h == 1L) fixture$history_y else y[h - 1L]
    center <- if (h == 1L) 1.1 else fixture$issued_centers[h - 1L]
    ref_feature <- previous + if (fixture$nonlinear) .1 * previous^2 else 0
    disc_feature <- center - previous + if (fixture$nonlinear) .07 * previous^2 else 0
    Hy[h, ] <- c(1, ref_feature, 0, 0)
    Hg[h, ] <- c(1, ref_feature, 1, disc_feature)
    Jy[[h]] <- Jg[[h]] <- matrix(0, 4L, H)
    if (h > 1L) {
      Jy[[h]][2L, h - 1L] <- 1 + if (fixture$nonlinear) .2 * previous else 0
      Jg[[h]][2L, h - 1L] <- Jy[[h]][2L, h - 1L]
      Jg[[h]][4L, h - 1L] <- -1 + if (fixture$nonlinear) .14 * previous else 0
    }
  }
  list(H_y = Hy, H_g_key = Hg, J_y = Jy, J_g_key = Jg)
}

gfta_row_moments <- function(fixture, y) {
  f <- gfta_features(fixture, y)
  H <- fixture$horizon
  M <- fixture$n_members
  index <- rep(seq_len(H), each = M)
  list(strategy = "streamed_grouped", fixed = list(n = 0L),
    future = c(list(n_y = H, n_g = H * M,
      g_future_index = index,
      g_index_by_h = split(seq_len(H * M), factor(index, levels = seq_len(H))),
      z_g = as.numeric(fixture$members),
      weight_y = rep(1, H), weight_g = rep(1, H * M)), f))
}

gfta_inverse_v <- function(fixture, B = 8) {
  H <- fixture$horizon
  M <- fixture$n_members
  variance_g <- if (M) 1.4 * (1 + .002 * (seq_len(M) - (M + 1) / 2)) else numeric()
  c(rep(B * fixture$sigma[["Y"]] / fixture$variance_y, H),
    rep(B * fixture$sigma[["G"]] / variance_g, H))
}

gfta_gaussian_oracle <- function(fixture, jitter = 0) {
  if (fixture$nonlinear) stop("The exact Gaussian oracle requires affine features.")
  # Construct the Gaussian density directly from its structural equations,
  # without reusing row-moment or production-gradient helpers.
  H <- fixture$horizon
  M <- fixture$n_members
  b <- fixture$theta_mean
  Ly <- diag(H)
  if (H > 1L) Ly[2L, 1L] <- -b[2L]
  by <- rep(b[1L], H)
  by[1L] <- by[1L] + b[2L] * fixture$history_y
  precision <- crossprod(Ly) / fixture$variance_y
  eta <- as.numeric(crossprod(Ly, by)) / fixture$variance_y
  if (M) for (h in seq_len(H)) for (e in seq_len(M)) {
    ell <- numeric(H)
    if (h > 1L) ell[h - 1L] <- -(b[2L] - b[4L])
    center <- if (h == 1L) 1.1 else fixture$issued_centers[h - 1L]
    intercept <- b[1L] + b[3L] + b[4L] * center
    if (h == 1L) intercept <- intercept + (b[2L] - b[4L]) * fixture$history_y
    variance <- 1.4 * (1 + .002 * (e - (M + 1) / 2))
    precision <- precision + tcrossprod(ell) / variance
    eta <- eta + ell * (intercept - fixture$members[e, h]) / variance
  }
  list(mean = as.numeric(solve(precision, eta)),
    target_covariance = solve(precision),
    operational_covariance = solve(precision + diag(jitter, H)),
    precision = precision, eta = eta)
}

gfta_update <- function(engine, fixture, y, inverse_v = gfta_inverse_v(fixture),
                        constants = list(A = 0, B = 8), theta_cov = matrix(0, 4L, 4L),
                        jitter = 1e-8) {
  engine$app_latent_update_future_gaussian_delta(
    row_moments = gfta_row_moments(fixture, y), y_start = y,
    theta_mean = fixture$theta_mean, theta_cov = theta_cov,
    e_inv_v = inverse_v,
    sigma_state = list(inv_mean = 1 / fixture$sigma), constants = constants,
    jitter = jitter, future_gaussian_prior = NULL,
    include_future_y_working_likelihood = TRUE)
}

gfta_literal <- function(fixture, y, inverse_v, constants, theta_cov) {
  # Independently sum every augmented row, including all 51 member rows.
  # The expected log factor is evaluated literally, not from the production
  # grouped sufficient statistics. Its derivative and linearized Hessian are
  # returned separately; nonlinear features have a known Hessian remainder.
  f <- gfta_features(fixture, y)
  H <- fixture$horizon
  b <- fixture$theta_mean
  grad <- numeric(H)
  GN <- remainder <- matrix(0, H, H)
  objective <- 0
  add <- function(z, h, J, a, src, einv, is_g = FALSE, time) {
    c <- einv / (constants$B * fixture$sigma[[src]])
    d <- constants$A / (constants$B * fixture$sigma[[src]])
    e <- z - sum(h * b)
    ell <- a - as.numeric(crossprod(J, b))
    Sh <- as.numeric(theta_cov %*% h)
    objective <<- objective + .5 * c * (e^2 + sum(h * Sh)) - d * e
    grad <<- grad + c * (ell * e + as.numeric(crossprod(J, Sh))) - d * ell
    GN <<- GN + c * (tcrossprod(ell) + crossprod(J, theta_cov %*% J))
    if (fixture$nonlinear && time > 1L) {
      second <- c(0, .2, 0, if (is_g) .14 else 0)
      remainder[time - 1L, time - 1L] <<-
        remainder[time - 1L, time - 1L] + sum((c * Sh - c * e * b + d * b) * second)
    }
  }
  for (h in seq_len(H)) {
    a <- numeric(H); a[h] <- 1
    add(y[h], f$H_y[h, ], f$J_y[[h]], a, "Y", inverse_v[h], time = h)
  }
  if (fixture$n_members) for (h in seq_len(H)) for (e in seq_len(fixture$n_members)) {
    i <- H + (h - 1L) * fixture$n_members + e
    add(fixture$members[e, h], f$H_g_key[h, ], f$J_g_key[[h]],
      numeric(H), "G", inverse_v[i], is_g = TRUE, time = h)
  }
  list(value = objective, gradient = grad, GN = GN, nonlinear_remainder = remainder)
}

gfta_finite_difference <- function(fun, u, step) {
  n <- length(u)
  gradient <- numeric(n)
  hessian <- matrix(0, n, n)
  f0 <- fun(u)
  for (i in seq_len(n)) {
    ei <- numeric(n); ei[i] <- step
    gradient[i] <- (fun(u + ei) - fun(u - ei)) / (2 * step)
    hessian[i, i] <- (fun(u + ei) - 2 * f0 + fun(u - ei)) / step^2
    if (i > 1L) for (j in seq_len(i - 1L)) {
      ej <- numeric(n); ej[j] <- step
      hessian[i, j] <- hessian[j, i] <-
        (fun(u + ei + ej) - fun(u + ei - ej) - fun(u - ei + ej) + fun(u - ei - ej)) /
        (4 * step^2)
    }
  }
  list(gradient = gradient, hessian = hessian)
}

gfta_run_affine_diagnostics <- function(engine_env = NULL, root = ".") {
  engine <- if (is.null(engine_env)) gfta_engine(root) else engine_env
  rows <- list(); fixtures <- list()
  record <- function(id, error, tolerance, detail, accuracy = "NOT_ASSESSED",
                     relevance = "generated_helper_only") {
    rows[[length(rows) + 1L]] <<- data.frame(test_id = id,
      reference_validity = "PASS", implementation_parity = if (error <= tolerance) "PASS" else "FAIL",
      numerical_stability = if (is.finite(error)) "PASS" else "FAIL",
      approximation_accuracy = accuracy, production_relevance = relevance,
      error = error, tolerance = tolerance, detail = detail, stringsAsFactors = FALSE)
  }
  for (H in 1:2) for (jitter in c(1e-8, .005)) {
    fixture <- gfta_fixture(H)
    oracle <- gfta_gaussian_oracle(fixture, jitter)
    y <- seq(-.4, .6, length.out = H)
    for (i in seq_len(50L)) {
      update <- gfta_update(engine, fixture, y, jitter = jitter)
      change <- max(abs(update$mean - y)); y <- update$mean
      if (change < 1e-14) break
    }
    id <- paste0("gaussian_h", H, "_j", format(jitter, scientific = TRUE))
    record(paste0(id, "_mean"), gfta_norm(y - oracle$mean),
      1e-10 + 1e-9 * gfta_norm(oracle$mean),
      "Incremental fixed-point mean compared with exact target mean, not ridge mean.", accuracy = "EXACT_FIXTURE")
    record(paste0(id, "_operational_covariance"), gfta_norm(update$cov - oracle$operational_covariance),
      1e-10 + 1e-8 * gfta_norm(oracle$operational_covariance),
      "Production covariance compared with stabilized inverse precision; target covariance retained separately.")
    record(paste0(id, "_precision"), gfta_norm(update$precision - oracle$precision - diag(jitter, H)),
      1e-10 * (1 + gfta_norm(oracle$precision)), "Literal 51-member Gaussian precision.")
    fixtures[[id]] <- list(mean = y, exact_mean = oracle$mean,
      target_covariance = oracle$target_covariance, operational_covariance = update$cov,
      jitter_covariance_error = gfta_norm(update$cov - oracle$target_covariance), iterations = i)
  }
  # At a single horizon all current G factors are constant in current latent Y.
  f1 <- gfta_fixture(1L); f1_shift <- f1; f1_shift$members <- f1$members + 100
  u1 <- gfta_update(engine, f1, -.2); u2 <- gfta_update(engine, f1_shift, -.2)
  record("h1_current_members_cancel", max(abs(c(u1$mean - u2$mean, u1$cov - u2$cov))),
    1e-12, "Fixed coefficients/scales, one horizon, no descendant factors.")
  # At two horizons later issued data can smooth the earlier latent response.
  f2 <- gfta_fixture(2L); shifted <- f2; shifted$members[, 2L] <- shifted$members[, 2L] + .5
  a <- gfta_gaussian_oracle(f2); b <- gfta_gaussian_oracle(shifted)
  effect <- abs(a$mean[1L] - b$mean[1L])
  record("h2_descendant_smoothing_present", if (effect > 1e-3) 0 else 1, 0,
    "Nonzero earlier-response influence from later member factors is expected, not leakage.", relevance = "reference_fixture_only")

  for (nonlinear in c(FALSE, TRUE)) {
    fixture <- gfta_fixture(2L, nonlinear = nonlinear)
    y <- c(.4, -.1)
    theta_cov <- matrix(c(.12,.01,0,.005, .01,.08,.004,0,
                          0,.004,.06,.008, .005,0,.008,.04), 4L, 4L)
    constants <- list(A = (1 - 2 * .2) / (.2 * .8), B = 2 / (.2 * .8))
    inverse_v <- gfta_inverse_v(fixture, constants$B)
    ref <- gfta_literal(fixture, y, inverse_v, constants, theta_cov)
    update <- gfta_update(engine, fixture, y, inverse_v, constants, theta_cov, jitter = 1e-8)
    production_gradient <- -as.numeric(update$precision %*% (update$mean - y))
    label <- if (nonlinear) "nonlinear" else "affine"
    record(paste0(label, "_gradient_literal_51"), gfta_norm(production_gradient - ref$gradient),
      1e-10 * (1 + gfta_norm(ref$gradient)), "Literal ungrouped augmented factors versus production streamed/grouped gradient.")
    record(paste0(label, "_GN_literal_51"), gfta_norm(update$precision - diag(1e-8, 2L) - ref$GN),
      1e-10 * (1 + gfta_norm(ref$GN)), "Production precision compared with linearized, not full nonlinear Hessian.")
    # Derivatives in dimensionless u coordinates with fixed declared scales.
    scales <- c(.8, 1.2); D <- diag(scales)
    objective <- function(u) gfta_literal(fixture, y + scales * u, inverse_v, constants, theta_cov)$value
    grad_u <- scales * ref$gradient
    hess_u <- D %*% (ref$GN + ref$nonlinear_remainder) %*% D
    for (step in c(1e-4, 3e-5, 1e-5)) {
      fd <- gfta_finite_difference(objective, c(0, 0), step)
      record(paste0(label, "_finite_gradient_", step),
        gfta_norm(fd$gradient - grad_u) / max(1, gfta_norm(grad_u)), 1e-6,
        "Centered finite difference in declared dimensionless coordinates.")
      record(paste0(label, "_finite_hessian_", step),
        gfta_norm(fd$hessian - hess_u) / max(1, gfta_norm(hess_u)), 1e-4,
        "Full finite-difference Hessian includes the independently predicted nonlinear remainder.")
    }
    if (nonlinear) record("nonlinear_GN_remainder_nonzero",
      if (gfta_norm(ref$nonlinear_remainder) > 1e-3) 0 else 1, 0,
      "Nonzero omitted nonlinear curvature is an approximation, not an implementation mismatch.", relevance = "reference_fixture_only")
    fixtures[[paste0(label, "_derivative")]] <- ref
  }
  # Verify the generated fixture's causal convention. These checks do not
  # authenticate any retained DESN feature-builder or serialized callback.
  f <- gfta_fixture(2L); y <- c(.4, -.1); fs <- gfta_features(f, y)
  future_error <- max(vapply(1:2, function(h) max(abs(c(
    fs$J_y[[h]][, h:2, drop = FALSE], fs$J_g_key[[h]][, h:2, drop = FALSE]))), numeric(1L)))
  record("fixture_current_future_derivatives_zero", future_error, 0,
    "Generated fixture excludes Y_h,...,Y_H, while permitted past latent dependence remains.", relevance = "reference_fixture_only")
  record("fixture_discrepancy_derivative_negative", abs(fs$J_g_key[[2]][4,1] + 1), 0,
    "Generated discrepancy-input lag has derivative -1.", relevance = "reference_fixture_only")
  changed <- gfta_features(f, y + c(0, 100))
  record("fixture_current_response_invariance", max(abs(c(changed$H_y - fs$H_y, changed$H_g_key - fs$H_g_key))),
    0, "Changing current/future Y leaves each relevant predictor unchanged.", relevance = "reference_fixture_only")
  list(schema_version = "glofas_fixed_target_affine_diagnostics_v1", checks = do.call(rbind, rows),
    fixtures = fixtures, scientific_runs = 0L, authentic_reads = 0L,
    oracle_contract = paste("Gaussian augmented working factors with fixed inverse-v moments,",
      "coefficients/scales and affine dynamics; not the marginal AL response law."),
    scope = "Generated helper checks only; no authentic feature replay or campaign posterior accuracy certificate.")
}
