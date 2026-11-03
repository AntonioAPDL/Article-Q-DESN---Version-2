# Pure evaluation of the retained AL future-path coordinate equations.
# This file reads no files, calls no saved feature-builder, and applies no step.

gfst_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS stationarity diagnostic: ", why), call. = FALSE)
  invisible(TRUE)
}

gfst_plain_numeric <- function(x, why) {
  gfst_require(is.numeric(x) && !is.complex(x) && !is.object(x) && all(is.finite(x)), why)
  x
}

gfst_norm <- function(x) sqrt(sum(as.numeric(x)^2))

gfst_future_equations <- function(core, design, p0 = NULL, jitter = 1e-8) {
  q <- gfst_require
  q(is.numeric(p0) && length(p0) == 1L && is.finite(p0) && p0 > 0 && p0 < 1,
    "explicit authenticated probability is required; shared-design p0 is not used")
  q(is.numeric(jitter) && length(jitter) == 1L && is.finite(jitter) && jitter >= 0,
    "finite nonnegative recorded numerical jitter required")
  q(is.list(core) && identical(core$method, "vb") && identical(core$likelihood_family, "al") &&
      is.list(core$variational_state) && is.list(design) &&
      identical(design$ensemble_member_weight_policy, "unit_member_likelihood_v1") &&
      identical(design$future_truth_policy, "physically_excluded_from_fit_objects_scoring_sidecar_only"),
    "AL core and truth-free unit-member design required")
  q(isTRUE(core$vb_diagnostics$future_y_working_likelihood_used) &&
      identical(core$vb_diagnostics$future_gaussian_prior_used, FALSE),
    "same-family future-Y law without a replacement Gaussian path prior required")
  v <- core$variational_state
  lin <- v$future_linearization
  q(is.list(lin) && identical(lin$strategy, "first_order_delta"),
    "retained numeric first-order linearization required")
  m <- as.numeric(gfst_plain_numeric(v$y_future_mean, "finite path mean required"))
  H <- length(m)
  q(H >= 1L && H <= 28L, "one to twenty-eight aligned future dates required")
  V <- gfst_plain_numeric(v$y_future_cov, "finite stored path covariance required")
  theta <- as.numeric(gfst_plain_numeric(v$theta_mean, "finite coefficient mean required"))
  S <- gfst_plain_numeric(v$theta_cov, "finite coefficient covariance required")
  p <- length(theta)
  q(identical(dim(V), c(H, H)) && identical(dim(S), c(p, p)) &&
      isTRUE(all.equal(as.numeric(lin$y_mean), m, tolerance = 0)),
    "stored covariance or linearization/path dimensions differ")
  beta <- design$beta_index
  alpha <- design$alpha_index
  valid_index <- function(x) is.numeric(x) && length(x) > 0L && all(is.finite(x)) &&
    all(x == as.integer(x)) && !anyDuplicated(x)
  q(valid_index(beta) && valid_index(alpha) && !length(intersect(beta, alpha)) &&
      setequal(c(beta, alpha), seq_len(p)), "exact two-partition coefficient coordinates required")
  beta <- as.integer(beta); alpha <- as.integer(alpha)
  q(is.matrix(design$H_fixed) && ncol(design$H_fixed) == p &&
      is.character(colnames(design$H_fixed)) && !anyDuplicated(colnames(design$H_fixed)) &&
      identical(colnames(core$draws$theta), colnames(design$H_fixed)),
    "stored coefficient column order does not match historical design")
  fixed_n <- nrow(design$H_fixed)
  q(is.data.frame(design$future_key) && all(c("target_date", "horizon") %in% names(design$future_key)) &&
      nrow(design$future_key) == H &&
      identical(as.numeric(design$future_key$horizon), as.numeric(seq_len(H))),
    "ordered unique future key required")
  key_dates <- as.Date(design$future_key$target_date)
  q(!anyNA(key_dates) && !anyDuplicated(key_dates), "finite unique future dates required")
  Xb <- gfst_plain_numeric(lin$X_beta_future, "finite retained reference features required")
  Xa <- gfst_plain_numeric(lin$X_alpha_future, "finite retained discrepancy features required")
  q(identical(dim(Xb), c(H, length(beta))) && identical(dim(Xa), c(H, length(alpha))) &&
      is.list(lin$J_beta) && length(lin$J_beta) == H &&
      is.list(lin$J_alpha) && length(lin$J_alpha) == H,
    "retained feature/Jacobian partition dimensions differ")
  ens <- design$latent_data$g_ensemble
  q(is.data.frame(ens) && all(c("target_date", "horizon", "g_transformed", "ensemble_weight") %in% names(ens)),
    "numeric issued-member table required")
  forbidden <- intersect(c("y", "y_raw", "y_transformed", "y_reference", "usgs", "usgs_raw", "usgs_transformed"), names(ens))
  q(!length(forbidden) || !any(vapply(ens[forbidden], function(x)
    any(is.finite(as.numeric(x))), logical(1L))), "future scoring truth is not an allowed input")
  z_g <- as.numeric(gfst_plain_numeric(ens$g_transformed, "finite issued values required"))
  weights <- as.numeric(gfst_plain_numeric(ens$ensemble_weight, "finite member weights required"))
  q(all(weights == 1), "only ordinary unit member factors are allowed")
  ens_dates <- as.Date(ens$target_date)
  q(!anyNA(ens_dates) && is.numeric(ens$horizon) && all(is.finite(ens$horizon)) &&
      all(ens$horizon == as.integer(ens$horizon)), "issued date/horizon key differs")
  index <- match(paste(ens_dates, ens$horizon), paste(key_dates, design$future_key$horizon))
  q(!anyNA(index) && length(index) == 51L * H && all(tabulate(index, nbins = H) == 51L),
    "exactly fifty-one authenticated-order factors per future date required")
  baseline <- design$discrepancy_baseline_future
  if (is.null(baseline)) baseline <- rep(0, H)
  baseline <- as.numeric(gfst_plain_numeric(baseline, "finite known discrepancy baseline required"))
  q(length(baseline) == H, "future discrepancy baseline differs")
  z_g <- z_g - baseline[index]
  inverse_v <- as.numeric(gfst_plain_numeric(v$v$inv_mean, "finite inverse-v moments required"))
  q(length(inverse_v) == fixed_n + H + nrow(ens) && all(inverse_v > 0),
    "fixed/Y/member augmentation ordering or count differs")
  inv_sigma <- v$sigma$inv_mean
  q(is.numeric(inv_sigma) && identical(sort(names(inv_sigma)), c("G", "Y")) &&
      all(is.finite(inv_sigma)) && all(inv_sigma > 0), "two named positive inverse-scale moments required")
  A <- (1 - 2 * p0) / (p0 * (1 - p0))
  B <- 2 / (p0 * (1 - p0))
  gradient_y_residual <- gradient_y_covariance <- gradient_y_asymmetry <- numeric(H)
  gradient_g_residual <- gradient_g_covariance <- gradient_g_asymmetry <- numeric(H)
  precision_y <- precision_g <- matrix(0, H, H)
  locations <- data.frame(horizon = seq_len(H), target_date = as.character(key_dates),
    path_mean = m, reference_plugin = NA_real_, discrepancy_plugin = NA_real_,
    reference_residual = NA_real_, issued_mean_residual = NA_real_, stringsAsFactors = FALSE)
  causality <- data.frame(horizon = seq_len(H), reference_forbidden_max_abs = NA_real_,
    discrepancy_forbidden_max_abs = NA_real_)
  for (h in seq_len(H)) {
    Jb <- gfst_plain_numeric(lin$J_beta[[h]], "finite retained reference Jacobian required")
    Ja <- gfst_plain_numeric(lin$J_alpha[[h]], "finite retained discrepancy Jacobian required")
    q(identical(dim(Jb), c(length(beta), H)) && identical(dim(Ja), c(length(alpha), H)),
      "retained Jacobian shape differs")
    causality$reference_forbidden_max_abs[h] <- max(abs(Jb[, h:H, drop = FALSE]))
    causality$discrepancy_forbidden_max_abs[h] <- max(abs(Ja[, h:H, drop = FALSE]))
    hy <- hg <- numeric(p)
    hy[beta] <- hg[beta] <- Xb[h, ]
    hg[alpha] <- Xa[h, ]
    Jy <- Jg <- matrix(0, p, H)
    Jy[beta, ] <- Jg[beta, ] <- Jb
    Jg[alpha, ] <- Ja
    hy_mean <- sum(hy * theta); hg_mean <- sum(hg * theta)
    locations$reference_plugin[h] <- hy_mean
    locations$discrepancy_plugin[h] <- sum(Xa[h, ] * theta[alpha])
    locations$reference_residual[h] <- m[h] - hy_mean
    # The mean feature is the only nonlinear object here; no builder is called.
    Shy <- as.numeric(S %*% hy); Shg <- as.numeric(S %*% hg)
    ay <- numeric(H); ay[h] <- 1
    ly <- ay - as.numeric(crossprod(Jy, theta))
    lg <- -as.numeric(crossprod(Jg, theta))
    cy <- inv_sigma[["Y"]] * inverse_v[fixed_n + h] / B
    dy <- inv_sigma[["Y"]] * A / B
    ey <- m[h] - hy_mean
    cov_y <- as.numeric(crossprod(Jy, Shy))
    gradient_y_residual <- gradient_y_residual + cy * ly * ey
    gradient_y_covariance <- gradient_y_covariance + cy * cov_y
    gradient_y_asymmetry <- gradient_y_asymmetry - dy * ly
    precision_y <- precision_y + cy * (tcrossprod(ly) + crossprod(Jy, S %*% Jy))
    at <- which(index == h)
    eg <- z_g[at] - hg_mean
    cg <- inv_sigma[["G"]] * inverse_v[fixed_n + H + at] / B
    dg <- inv_sigma[["G"]] * A / B
    locations$issued_mean_residual[h] <- mean(eg)
    cov_g <- as.numeric(crossprod(Jg, Shg))
    # Sum all independent member contributions, reusing only their identical
    # feature/Jacobian matrices. This is not a collapse of the likelihood.
    gradient_g_residual <- gradient_g_residual + lg * sum(cg * eg)
    gradient_g_covariance <- gradient_g_covariance + cov_g * sum(cg)
    gradient_g_asymmetry <- gradient_g_asymmetry - lg * length(at) * dg
    precision_g <- precision_g + sum(cg) * (tcrossprod(lg) + crossprod(Jg, S %*% Jg))
  }
  gradient_y <- gradient_y_residual + gradient_y_covariance + gradient_y_asymmetry
  gradient_g <- gradient_g_residual + gradient_g_covariance + gradient_g_asymmetry
  gradient <- gradient_y + gradient_g
  precision <- (precision_y + precision_g + t(precision_y + precision_g)) / 2
  operational <- precision + diag(jitter, H)
  ch <- tryCatch(chol(operational), error = function(e) NULL)
  q(!is.null(ch), "diagnostic precision is not Cholesky-positive; no repair or step is applied")
  delta <- as.numeric(backsolve(ch, forwardsolve(t(ch), -gradient)))
  operational_covariance <- chol2inv(ch)
  solve_residual <- as.numeric(operational %*% delta + gradient)
  denominator <- norm(operational, "2") * gfst_norm(delta) + gfst_norm(gradient)
  normalized_residual <- if (denominator == 0 && gfst_norm(solve_residual) == 0) 0 else
    if (denominator == 0) Inf else gfst_norm(solve_residual) / denominator
  per_h <- cbind(locations, data.frame(
    gradient_y_residual = gradient_y_residual, gradient_y_coefficient_uncertainty = gradient_y_covariance,
    gradient_y_asymmetry = gradient_y_asymmetry, gradient_y = gradient_y,
    gradient_g_residual = gradient_g_residual, gradient_g_coefficient_uncertainty = gradient_g_covariance,
    gradient_g_asymmetry = gradient_g_asymmetry, gradient_g = gradient_g,
    gradient_total = gradient, diagnostic_preconditioned_step_not_applied = delta,
    marginal_covariance_relative_change = abs(diag(operational_covariance) - diag(V)) / pmax(1e-12, abs(diag(V))),
    stringsAsFactors = FALSE))
  list(schema_version = "glofas_future_stationarity_equations_v1", p0 = p0,
    per_horizon = per_h, gradient = gradient, gradient_y = gradient_y, gradient_g = gradient_g,
    precision_without_jitter = precision, precision_y = precision_y, precision_g = precision_g,
    recorded_jitter = jitter, operational_covariance = operational_covariance,
    stored_covariance = V, covariance_relative_frobenius_error =
      gfst_norm(operational_covariance - V) / max(1e-12, gfst_norm(V)),
    max_absolute_diagnostic_step_not_applied = max(abs(delta)),
    normalized_solve_residual = normalized_residual, precision_condition_number = kappa(operational, exact = TRUE),
    causality = causality, all_retained_jacobians_causal = all(causality[-1L] <= 1e-12),
    factor_counts = list(historical_rows_skipped = fixed_n, future_Y = H, future_G = nrow(ens)),
    coordinate_equation_evaluations = 1L, coordinate_updates_applied = 0L,
    saved_callback_calls = 0L, original_file_reads = 0L, future_truth_read = FALSE,
    inference_scope = paste("Current numeric future mean-coordinate equations and Gauss-Newton covariance only;",
      "not a full-state stationarity, stopping, exact-posterior, or approximation-accuracy certificate."))
}
