app_pricefm_sym_solve <- function(P, h = NULL) {
  P <- 0.5 * (P + t(P))
  jitter <- 0
  R <- NULL
  for (attempt in seq_len(10L)) {
    candidate <- if (jitter > 0) P + diag(jitter, nrow(P)) else P
    R <- tryCatch(chol(candidate), error = function(e) NULL)
    if (!is.null(R)) break
    jitter <- if (attempt == 1L) sqrt(.Machine$double.eps) * max(1, mean(diag(P))) else jitter * 10
  }
  if (is.null(R)) stop("normal sufficient-statistic precision is not positive definite", call. = FALSE)
  inverse <- chol2inv(R)
  out <- list(
    inv = 0.5 * (inverse + t(inverse)),
    logdet = 2 * sum(log(diag(R))),
    jitter = jitter
  )
  if (!is.null(h)) out$x <- as.numeric(backsolve(R, forwardsolve(t(R), h)))
  out
}

app_pricefm_validate_normal_stats <- function(stats) {
  required <- c("n", "p", "XtX", "Xty", "yty")
  missing <- setdiff(required, names(stats))
  if (length(missing)) stop(sprintf("missing sufficient statistic(s): %s", paste(missing, collapse = ", ")), call. = FALSE)
  stats$n <- as.integer(stats$n)
  stats$p <- as.integer(stats$p)
  stats$XtX <- as.matrix(stats$XtX)
  stats$Xty <- as.numeric(stats$Xty)
  stats$yty <- as.numeric(stats$yty)
  if (stats$n < 1L || stats$p < 1L || !all(dim(stats$XtX) == c(stats$p, stats$p)) ||
      length(stats$Xty) != stats$p || length(stats$yty) != 1L ||
      any(!is.finite(stats$XtX)) || any(!is.finite(stats$Xty)) || !is.finite(stats$yty)) {
    stop("invalid Normal sufficient statistics", call. = FALSE)
  }
  stats$XtX <- 0.5 * (stats$XtX + t(stats$XtX))
  stats
}

app_pricefm_fit_scaled_ridge_stats <- function(
    stats,
    beta_ridge_tau2 = 1e4,
    intercept_var = 1e6,
    omega_a = 2,
    omega_b = 1) {
  stats <- app_pricefm_validate_normal_stats(stats)
  precision0 <- rep(1 / as.numeric(beta_ridge_tau2), stats$p)
  precision0[[1L]] <- 1 / as.numeric(intercept_var)
  P0 <- diag(precision0, stats$p)
  b0 <- numeric(stats$p)
  Pn <- P0 + stats$XtX
  solution <- app_pricefm_sym_solve(Pn, stats$Xty)
  mean <- solution$x
  shape <- as.numeric(omega_a) + stats$n / 2
  rate <- as.numeric(omega_b) + 0.5 * (stats$yty - as.numeric(crossprod(mean, Pn %*% mean)))
  rate <- max(rate, .Machine$double.eps)
  marginal_cov <- if (shape > 1) (rate / (shape - 1)) * solution$inv else matrix(NA_real_, stats$p, stats$p)
  structure(list(
    type = "scaled_ridge_exact_sufficient_statistics",
    beta = list(
      mean = mean,
      cov = marginal_cov,
      scale_cov = (rate / shape) * solution$inv,
      precision = Pn,
      precision_inv = solution$inv,
      df = 2 * shape
    ),
    omega2 = list(a = shape, b = rate, mean = rate / (shape - 1), mode = rate / (shape + 1)),
    prior = list(type = "scaled_ridge", mean = b0, precision = P0),
    stats = stats,
    trace = data.frame(),
    converged = TRUE,
    exact_closed_form = TRUE,
    uses_vb = FALSE,
    jitter = solution$jitter
  ), class = c("app_pricefm_recursive_normal_fit", "list"))
}

app_pricefm_rhs_convergence_status <- function(
    trace,
    mode = c("legacy_max_abs", "predictive_fixed_point"),
    tol = 1e-5,
    stability_window = 10L,
    predictive_tol = 1e-7,
    relative_beta_tol = 1e-6,
    sigma_relative_tol = 1e-8,
    prior_rms_log_precision_tol = 1e-6) {
  mode <- match.arg(mode)
  stability_window <- as.integer(stability_window)
  if (stability_window < 1L || nrow(trace) < 1L) return(FALSE)
  strict <- utils::tail(trace$beta_max_abs_delta, 1L) <= as.numeric(tol)
  if (identical(mode, "legacy_max_abs")) return(strict)
  if (nrow(trace) < stability_window) return(FALSE)
  recent <- utils::tail(trace, stability_window)
  if (any(!is.finite(as.matrix(recent)))) return(FALSE)
  strict || (
    max(recent$fitted_rmse_delta) <= as.numeric(predictive_tol) &&
    max(recent$beta_relative_l2_delta) <= as.numeric(relative_beta_tol) &&
    max(recent$sigma_relative_delta) <= as.numeric(sigma_relative_tol) &&
    max(recent$prior_rms_log_precision_delta) <= as.numeric(prior_rms_log_precision_tol)
  )
}

app_pricefm_fit_rhs_stats <- function(
    stats,
    tau0,
    beta_prior_factory,
    omega_a = 2,
    omega_b = 1,
    max_iter = 100L,
    min_iter = 50L,
    tol = 1e-5,
    convergence_mode = c("legacy_max_abs", "predictive_fixed_point"),
    stability_window = 10L,
    predictive_tol = 1e-7,
    relative_beta_tol = 1e-6,
    sigma_relative_tol = 1e-8,
    prior_rms_log_precision_tol = 1e-6) {
  stats <- app_pricefm_validate_normal_stats(stats)
  tau0 <- as.numeric(tau0)
  if (!is.finite(tau0) || tau0 <= 0) stop("tau0 must be finite and positive", call. = FALSE)
  if (!is.function(beta_prior_factory)) stop("beta_prior_factory must be a function", call. = FALSE)
  prior <- beta_prior_factory("rhs_ns", rhs = list(
    tau0 = tau0,
    init_tau = 1,
    shrink_intercept = FALSE,
    intercept_prec = 1e-16
  ))
  state <- prior$init(stats$p)
  ridge <- app_pricefm_fit_scaled_ridge_stats(stats, omega_a = omega_a, omega_b = omega_b)
  mean <- ridge$beta$mean
  covariance <- ridge$beta$cov
  sigma_shape <- as.numeric(omega_a) + stats$n / 2
  sigma_rate <- ridge$omega2$b
  convergence_mode <- match.arg(convergence_mode)
  trace <- data.frame(
    iter = integer(), sigma2_mean = numeric(), beta_max_abs_delta = numeric(),
    fitted_rmse_delta = numeric(), beta_relative_l2_delta = numeric(),
    sigma_relative_delta = numeric(), prior_rms_log_precision_delta = numeric()
  )
  converged <- FALSE
  for (iteration in seq_len(as.integer(max_iter))) {
    old_mean <- mean
    old_sigma <- if (sigma_shape > 1) sigma_rate / (sigma_shape - 1) else sigma_rate / sigma_shape
    expected_inverse_sigma <- sigma_shape / sigma_rate
    prior_precision <- as.numeric(prior$expected_prec(state, stats$p))
    if (length(prior_precision) != stats$p || any(!is.finite(prior_precision)) || any(prior_precision <= 0)) {
      stop("RHS expected precision must be finite and positive", call. = FALSE)
    }
    posterior_precision <- expected_inverse_sigma * stats$XtX + diag(prior_precision, stats$p)
    solution <- app_pricefm_sym_solve(posterior_precision, expected_inverse_sigma * stats$Xty)
    mean <- solution$x
    covariance <- solution$inv
    second_moment <- covariance + tcrossprod(mean)
    sse <- stats$yty - 2 * as.numeric(crossprod(mean, stats$Xty)) + sum(stats$XtX * second_moment)
    sigma_rate <- as.numeric(omega_b) + 0.5 * max(sse, .Machine$double.eps)
    state <- prior$update(state, list(m = mean, V = covariance))
    updated_prior_precision <- as.numeric(prior$expected_prec(state, stats$p))
    if (length(updated_prior_precision) != stats$p || any(!is.finite(updated_prior_precision)) ||
        any(updated_prior_precision <= 0)) {
      stop("updated RHS expected precision must be finite and positive", call. = FALSE)
    }
    sigma_mean <- if (sigma_shape > 1) sigma_rate / (sigma_shape - 1) else sigma_rate / sigma_shape
    beta_delta <- mean - old_mean
    beta_max_abs_delta <- max(abs(beta_delta))
    fitted_rmse_delta <- sqrt(max(
      0, as.numeric(crossprod(beta_delta, stats$XtX %*% beta_delta)) / stats$n
    ))
    beta_relative_l2_delta <- sqrt(sum(beta_delta^2)) / max(1, sqrt(sum(old_mean^2)))
    sigma_relative_delta <- abs(sigma_mean - old_sigma) / max(1, abs(old_sigma))
    prior_active <- if (stats$p >= 2L) seq.int(2L, stats$p) else seq_len(stats$p)
    prior_rms_log_precision_delta <- sqrt(mean(
      (log(updated_prior_precision[prior_active]) - log(prior_precision[prior_active]))^2
    ))
    trace <- rbind(trace, data.frame(
      iter = as.integer(iteration),
      sigma2_mean = as.numeric(sigma_mean),
      beta_max_abs_delta = as.numeric(beta_max_abs_delta),
      fitted_rmse_delta = as.numeric(fitted_rmse_delta),
      beta_relative_l2_delta = as.numeric(beta_relative_l2_delta),
      sigma_relative_delta = as.numeric(sigma_relative_delta),
      prior_rms_log_precision_delta = as.numeric(prior_rms_log_precision_delta)
    ))
    if (iteration >= as.integer(min_iter) && app_pricefm_rhs_convergence_status(
      trace,
      mode = convergence_mode,
      tol = tol,
      stability_window = stability_window,
      predictive_tol = predictive_tol,
      relative_beta_tol = relative_beta_tol,
      sigma_relative_tol = sigma_relative_tol,
      prior_rms_log_precision_tol = prior_rms_log_precision_tol
    )) {
      converged <- TRUE
      break
    }
  }
  structure(list(
    type = "rhs_ns_vb_sufficient_statistics",
    beta = list(
      mean = mean,
      cov = covariance,
      precision = app_pricefm_sym_solve(covariance)$inv,
      df = Inf
    ),
    omega2 = list(
      a = sigma_shape,
      b = sigma_rate,
      mean = sigma_rate / (sigma_shape - 1),
      mode = sigma_rate / (sigma_shape + 1)
    ),
    beta_prior = list(type = "rhs_ns", hypers = prior$hypers, state = state),
    stats = stats,
    trace = trace,
    converged = converged,
    exact_closed_form = FALSE,
    uses_vb = TRUE,
    controls = list(
      max_iter = max_iter, min_iter = min_iter, tol = tol,
      convergence_mode = convergence_mode, stability_window = stability_window,
      predictive_tol = predictive_tol, relative_beta_tol = relative_beta_tol,
      sigma_relative_tol = sigma_relative_tol,
      prior_rms_log_precision_tol = prior_rms_log_precision_tol
    ),
    initialization_contract = "scaled_ridge_initialization_only_prior_unchanged"
  ), class = c("app_pricefm_recursive_normal_fit", "list"))
}

app_pricefm_normal_stats_from_design <- function(X, y) {
  X <- as.matrix(X)
  y <- as.numeric(y)
  if (nrow(X) != length(y)) stop("X/y row mismatch", call. = FALSE)
  list(
    n = nrow(X),
    p = ncol(X),
    XtX = crossprod(X),
    Xty = as.numeric(crossprod(X, y)),
    yty = as.numeric(crossprod(y))
  )
}
