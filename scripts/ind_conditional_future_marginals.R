# Qualification components for known-feature DQLM horizon marginals.
# No protected input, random draws, model fitting, or production enrollment.

ind_cfm_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste0("IND future marginal: ", message), call. = FALSE)
  invisible(TRUE)
}

ind_cfm_psd <- function(M, dimension, tolerance, label) {
  ind_cfm_require(is.numeric(M) && is.matrix(M) &&
    identical(dim(M), c(dimension, dimension)) && all(is.finite(M)),
    paste("invalid", label))
  ind_cfm_require(max(abs(M - t(M))) <= tolerance * max(1, max(abs(M))),
    paste("nonsymmetric", label))
  values <- eigen(.5 * (M + t(M)), symmetric = TRUE, only.values = TRUE)$values
  ind_cfm_require(min(values) >= -tolerance * max(1, max(abs(values))),
    paste("indefinite", label))
  invisible(TRUE)
}

# C_aux controls the native, auxiliary-history-dependent discount innovation.
# S is the unobserved state's marginal covariance conditional on this
# auxiliary path. These are equal at the origin, but generally differ later.
ind_cfm_future <- function(m_origin, C_origin, FF, GG, ex_f, ex_q, df_mat,
    future_features, tolerance = 1e-10) {
  ind_cfm_require(!missing(future_features) &&
    identical(future_features, "known_deterministic"),
    "explicit known deterministic future F/G required; response-dependent features are unsupported")
  ind_cfm_require(is.numeric(tolerance) && length(tolerance) == 1L &&
    is.finite(tolerance) && tolerance > 0 && is.numeric(m_origin) &&
    length(m_origin) >= 1L && all(is.finite(m_origin)), "invalid origin or tolerance")
  p <- length(m_origin)
  ind_cfm_require(is.numeric(FF) && is.matrix(FF) && nrow(FF) == p &&
    ncol(FF) >= 1L && all(is.finite(FF)), "invalid future observation vectors")
  H <- ncol(FF)
  if (is.matrix(GG)) {
    ind_cfm_require(is.numeric(GG) && identical(dim(GG), c(p, p)),
      "invalid constant future evolution matrix")
    GG <- array(rep(GG, H), c(p, p, H))
  }
  ind_cfm_require(is.numeric(GG) && identical(dim(GG), c(p, p, H)) &&
    all(is.finite(GG)) && is.numeric(ex_f) && length(ex_f) == H &&
    is.numeric(ex_q) && length(ex_q) == H && all(is.finite(c(ex_f, ex_q))) &&
    all(ex_q >= 0), "incompatible future evolution/augmentation dimensions or support")
  ind_cfm_psd(C_origin, p, tolerance, "origin covariance")
  ind_cfm_psd(df_mat, p, tolerance, "discount matrix")
  ind_cfm_require(all(df_mat >= 0), "negative discount inflation is unsupported")
  sym <- function(M) .5 * (M + t(M))
  C_aux <- R_aux <- P_aux <- W_eff <- S <- array(0, c(p, p, H))
  M <- matrix(0, p, H)
  Q_aux <- response_mean <- response_variance <- numeric(H)
  C_previous <- S_previous <- C_origin
  m_previous <- m_origin
  for (h in seq_len(H)) {
    G <- matrix(GG[, , h], p, p); F <- as.numeric(FF[, h])
    P <- G %*% C_previous %*% t(G)
    R <- sym(P + df_mat * P)
    W <- R - sym(P)
    ind_cfm_psd(R, p, tolerance, "auxiliary-conditional predictive covariance")
    ind_cfm_psd(W, p, tolerance, "effective state innovation")
    Q <- as.numeric(t(F) %*% R %*% F) + ex_q[h]
    # A native Q floor is an exception, not an exact probability law.
    ind_cfm_require(is.finite(Q) && Q > 0,
      "nonpositive auxiliary forecast variance; no silent native Q-floor substitution")
    C <- sym(R - (R %*% F %*% t(F) %*% R) / Q)
    Sh <- sym(G %*% S_previous %*% t(G)) + W
    mh <- as.numeric(G %*% m_previous)
    V <- as.numeric(t(F) %*% Sh %*% F) + ex_q[h]
    ind_cfm_psd(C, p, tolerance, "auxiliary covariance control")
    ind_cfm_psd(Sh, p, tolerance, "unobserved predictive-state covariance")
    ind_cfm_require(all(is.finite(c(mh, V))) && V > 0,
      "invalid marginal response moments")
    C_aux[, , h] <- C; R_aux[, , h] <- R; P_aux[, , h] <- P
    W_eff[, , h] <- W; S[, , h] <- Sh; M[, h] <- mh
    Q_aux[h] <- Q
    response_mean[h] <- sum(F * mh) + ex_f[h]
    response_variance[h] <- V
    C_previous <- C; S_previous <- Sh; m_previous <- mh
  }
  ind_cfm_require(all(is.finite(response_mean)), "nonfinite marginal response mean")
  structure(list(schema_version = "ind_known_feature_conditional_future_marginals_v1",
    state_mean = M, state_covariance = S, auxiliary_covariance = C_aux,
    auxiliary_predictive_covariance = R_aux, auxiliary_propagated_covariance = P_aux,
    effective_innovation = W_eff, auxiliary_forecast_variance = Q_aux,
    response_mean = response_mean, response_variance = response_variance,
    conditioning = "static_parameters_origin_Gaussian_component_and_future_auxiliary_path",
    future_features = future_features, Gaussian_states_integrated = TRUE,
    future_feature_provenance_authenticated = FALSE,
    intermediate_responses_integrated = TRUE, auxiliaries_integrated = FALSE,
    origin_filter_integrated = FALSE, trajectory_joint_law_returned = FALSE,
    covariance_regularization = "symmetrize_only_no_floor_or_cap",
    numerical_Q_floor_allowed = FALSE, random_draws_generated = 0L,
    new_model_fits = 0L, production_authorized = FALSE),
    class = c("ind_conditional_future_marginals", "list"))
}

ind_cfm_normal_mixture <- function(mean, variance, weight) {
  ind_cfm_require(is.numeric(mean) && length(mean) >= 1L &&
    is.numeric(variance) && length(variance) == length(mean) &&
    is.numeric(weight) && length(weight) == length(mean) &&
    all(is.finite(c(mean, variance, weight))) && all(variance > 0) &&
    all(weight >= 0) && max(weight) > 0,
    "finite, positive-variance Normal components and nonnegative nonzero weights required")
  originally_positive <- weight > 0
  weight <- weight / max(weight)
  ind_cfm_require(all(weight[originally_positive] > 0),
    "positive mixture weight underflow during normalization")
  weight <- weight / sum(weight)
  ind_cfm_require(all(weight[originally_positive] > 0),
    "positive normalized mixture weight is not representable")
  active <- weight > 0
  list(mean = mean[active], sd = sqrt(variance[active]), weight = weight[active])
}

# Every active origin component must be represented. Different numbers of
# future paths per component must not alter its marginal filtering weight.
ind_cfm_origin_path_weights <- function(origin_weight, origin_component) {
  ind_cfm_require(is.numeric(origin_weight) && length(origin_weight) >= 1L &&
    all(is.finite(origin_weight)) && all(origin_weight >= 0) && max(origin_weight) > 0 &&
    is.numeric(origin_component) && length(origin_component) >= 1L &&
    all(is.finite(origin_component)) && all(origin_component == as.integer(origin_component)) &&
    all(origin_component >= 1L & origin_component <= length(origin_weight)),
    "invalid origin weights or future-path component map")
  counts <- tabulate(as.integer(origin_component), nbins = length(origin_weight))
  ind_cfm_require(all(counts[origin_weight > 0] > 0), "an active origin component has no future path")
  positive <- origin_weight > 0
  omega <- origin_weight / max(origin_weight)
  ind_cfm_require(all(omega[positive] > 0), "positive origin weight underflow")
  omega <- omega / sum(omega)
  path_weight <- omega[origin_component] / counts[origin_component]
  ind_cfm_require(all(path_weight[origin_weight[origin_component] > 0] > 0),
    "positive origin-path weight is not representable")
  path_weight
}

ind_cfm_mixture_cdf <- function(x, mean, variance, weight) {
  ind_cfm_require(is.numeric(x) && length(x) >= 1L && !anyNA(x),
    "CDF arguments cannot be missing or NaN")
  mix <- ind_cfm_normal_mixture(mean, variance, weight)
  vapply(x, function(value) sum(mix$weight * stats::pnorm(value, mix$mean, mix$sd)), numeric(1L))
}

# Invert the mixture, never the average of its component quantiles.
# Accuracy here concerns deterministic inversion of the supplied finite
# mixture; it does not certify particle or auxiliary integration accuracy.
ind_cfm_mixture_quantile <- function(probability, mean, variance, weight,
    absolute_tolerance, relative_tolerance, max_iterations = 256L) {
  ind_cfm_require(is.numeric(probability) && length(probability) >= 1L &&
    all(is.finite(probability)) && all(probability > 0 & probability < 1) &&
    is.numeric(absolute_tolerance) && length(absolute_tolerance) == 1L &&
    is.finite(absolute_tolerance) && absolute_tolerance > 0 &&
    is.numeric(relative_tolerance) && length(relative_tolerance) == 1L &&
    is.finite(relative_tolerance) && relative_tolerance >= 0 &&
    is.numeric(max_iterations) && length(max_iterations) == 1L &&
    is.finite(max_iterations) && max_iterations >= 1 &&
    max_iterations == as.integer(max_iterations), "invalid inversion contract")
  mix <- ind_cfm_normal_mixture(mean, variance, weight)
  cdf <- function(value) sum(mix$weight * stats::pnorm(value, mix$mean, mix$sd))
  rows <- lapply(probability, function(prob) {
    component_quantiles <- mix$mean + mix$sd * stats::qnorm(prob)
    ind_cfm_require(all(is.finite(component_quantiles)), "nonfinite quantile bracket")
    lo <- min(component_quantiles); hi <- max(component_quantiles)
    # Component quantiles bracket the mixture quantile in exact arithmetic.
    # Roundoff may put an endpoint a few ulps on the wrong side. Expand only
    # if its evaluated CDF does not bracket the requested probability.
    span <- max(1, hi - lo, max(mix$sd))
    expansion <- 0L
    while (cdf(lo) > prob || cdf(hi) < prob) {
      if (cdf(lo) > prob) lo <- lo - span
      if (cdf(hi) < prob) hi <- hi + span
      span <- 2 * span; expansion <- expansion + 1L
      ind_cfm_require(expansion <= max_iterations && all(is.finite(c(lo, hi, span))),
        "unable to establish finite mixture quantile bracket")
    }
    iter <- 0L
    repeat {
      tol <- absolute_tolerance + relative_tolerance * max(abs(c(lo, hi)))
      ind_cfm_require(is.finite(tol), "computed inversion tolerance is not finite")
      if (hi - lo <= tol) break
      ind_cfm_require(iter < max_iterations, "mixture quantile inversion exhausted declared iteration limit")
      mid <- lo / 2 + hi / 2
      ind_cfm_require(mid > lo && mid < hi,
        "requested inversion tolerance is below floating-point resolution")
      if (cdf(mid) >= prob) hi <- mid else lo <- mid
      iter <- iter + 1L
    }
    data.frame(probability = prob, quantile = hi, lower = lo, upper = hi,
      cdf_lower = cdf(lo), cdf_upper = cdf(hi), iterations = iter,
      bracket_expansions = expansion, width_tolerance = tol)
  })
  list(schema_version = "ind_finite_Normal_mixture_inversion_v1",
    result = do.call(rbind, rows), absolute_tolerance = absolute_tolerance,
    relative_tolerance = relative_tolerance, max_iterations = max_iterations,
    normalized_component_weights = mix$weight,
    accuracy_scope = "deterministic_inversion_of_supplied_finite_mixture_only",
    particle_filter_accuracy_qualified = FALSE, auxiliary_integral_accuracy_qualified = FALSE,
    random_draws_generated = 0L, production_authorized = FALSE)
}
