# Additive observation-guided filtering at one fixed native parameter value.
# Mathematical qualification only; no protected-file I/O or launch authority.
source("scripts/ind_conditional_auxiliary_filter.R")
source("scripts/ind_guided_auxiliary_primitives.R")

ind_gaf_eta <- function(eta) {
  ind_cfr_require(is.list(eta) && identical(sort(names(eta)), sort(c("family", "p", "sigma", "gamma"))) &&
    eta$family %in% c("al", "exal"), "explicit complete native parameter specification required")
  # Native support validation, including AL/exAL parameterization and scale.
  ind_cfr_augmentation(eta$family, eta$p, eta$sigma, 1,
    if (eta$family == "exal") 0 else NULL, eta$gamma)
  invisible(TRUE)
}

ind_gaf_filter <- function(y, FF, GG, m0, C0, df_mat, eta, uniforms,
    observed_prefix_length, parameter_id, checkpoint_indices,
    ess_fraction = .5, tolerance = 1e-10) {
  ind_gaf_eta(eta)
  ind_cfr_require(!missing(observed_prefix_length) && is.numeric(observed_prefix_length) &&
    length(observed_prefix_length) == 1L && is.finite(observed_prefix_length) &&
    observed_prefix_length >= 1 && observed_prefix_length == as.integer(observed_prefix_length),
    "explicit observed prefix required for guided filter")
  n <- as.integer(observed_prefix_length); p <- length(m0)
  ind_cfr_require(is.numeric(tolerance) && length(tolerance) == 1L && is.finite(tolerance) &&
    tolerance > 0 && is.numeric(y) && length(y) == n && all(is.finite(y)) &&
    is.numeric(m0) && p >= 1L && all(is.finite(m0)) && is.character(parameter_id) &&
    length(parameter_id) == 1L && !is.na(parameter_id) && nzchar(parameter_id),
    "invalid guided-filter observed data or parameter identity")
  if (is.matrix(GG)) {
    ind_cfr_require(identical(dim(GG), c(p, p)), "invalid constant guided evolution")
    GG <- array(rep(GG, n), c(p, p, n))
  }
  ind_cfr_require(is.numeric(FF) && identical(dim(FF), c(p, n)) && is.matrix(FF) &&
    is.numeric(GG) && identical(dim(GG), c(p, p, n)) && all(is.finite(c(FF, GG))),
    "observed feature/evolution dimensions differ from the exact prefix")
  ind_caf_psd(C0, p, tolerance, "guided initial covariance")
  ind_caf_psd(df_mat, p, tolerance, "guided discount matrix")
  ind_cfr_require(all(df_mat >= 0), "negative guided discount inflation")
  ind_cfr_require(is.list(uniforms) && is.numeric(uniforms$proposal) &&
    length(dim(uniforms$proposal)) == 3L && dim(uniforms$proposal)[1L] >= 1L &&
    identical(dim(uniforms$proposal)[2:3], c(n, 4L)) &&
    all(is.finite(uniforms$proposal)) && all(uniforms$proposal > 0 & uniforms$proposal < 1),
    "guided proposal requires four retained open-unit innovation channels")
  N <- dim(uniforms$proposal)[1L]
  ind_cfr_require(is.numeric(uniforms$resampling) && length(uniforms$resampling) == n &&
    all(is.finite(uniforms$resampling)) && all(uniforms$resampling > 0 & uniforms$resampling < 1) &&
    is.numeric(ess_fraction) && length(ess_fraction) == 1L && is.finite(ess_fraction) &&
    ess_fraction >= 0 && ess_fraction <= 1,
    "invalid guided resampling stream or ESS fraction")
  if (eta$family == "exal") {
    ind_caf_uniforms(uniforms$half_normal, "guided exAL half-Normal")
    ind_cfr_require(identical(dim(uniforms$half_normal), c(N, n)), "guided half-Normal shape mismatch")
  } else ind_cfr_require(is.null(uniforms$half_normal), "AL cannot inherit an exAL auxiliary")
  ind_cfr_require(is.numeric(checkpoint_indices) && length(checkpoint_indices) >= 1L &&
    all(is.finite(checkpoint_indices)) && all(checkpoint_indices == as.integer(checkpoint_indices)) &&
    all(checkpoint_indices >= 1L & checkpoint_indices <= n) &&
    !anyDuplicated(checkpoint_indices) && !is.unsorted(checkpoint_indices),
    "sorted unique guided checkpoint indices required")
  m <- matrix(rep(m0, N), p, N); C <- array(rep(C0, N), c(p, p, N))
  weights <- rep(1 / N, N); ESS <- numeric(n); resampled <- logical(n)
  ancestors <- matrix(0L, N, n); log_increment <- numeric(n)
  underflow <- zero_weights <- integer(n); checkpoints <- list()
  sym <- function(M) .5 * (M + t(M))
  for (tt in seq_len(n)) {
    G <- matrix(GG[, , tt], p, p); F <- as.numeric(FF[, tt])
    mn <- matrix(0, p, N); Cn <- array(0, c(p, p, N)); lp <- numeric(N)
    for (j in seq_len(N)) {
      a <- as.numeric(G %*% m[, j]); P <- G %*% matrix(C[, , j], p, p) %*% t(G)
      W <- sym(df_mat * P); R <- sym(P + df_mat * P)
      ind_caf_psd(W, p, tolerance, "guided innovation covariance")
      ind_caf_psd(R, p, tolerance, "guided predictive covariance")
      RF <- as.numeric(R %*% F); f <- sum(F * a); S <- sum(F * RF)
      ind_cfr_require(is.finite(S) && S >= 0, "invalid projected Gaussian-state variance")
      u <- as.numeric(uniforms$proposal[j, tt, ])
      if (eta$family == "al") {
        proposal <- ind_gap_propose(y[tt], f, S, eta$p, eta$sigma, u)
      } else {
        hs <- stats::qnorm((1 - uniforms$half_normal[j, tt]) / 2, lower.tail = FALSE)
        proposal <- ind_gap_exal_propose(y[tt], f, S, eta$p, eta$sigma, eta$gamma, hs, u)
      }
      # Temporary projected L is used solely to draw the correct marginal v
      # proposal. It must NOT be an additional state observation here.
      Q <- S + proposal$ex_q
      ind_cfr_require(is.finite(Q) && Q > 0 && is.finite(proposal$log_predictive_density),
        "nonpositive guided variance or nonfinite predictive normalizer")
      mn[, j] <- a + RF * ((y[tt] - f - proposal$ex_f) / Q)
      Cn[, , j] <- sym(R - tcrossprod(RF) / Q)
      ind_caf_psd(matrix(Cn[, , j], p, p), p, tolerance, "guided filtered covariance")
      # AL uses its exact locally optimal normalizer; exAL's prior-s proposal
      # uses the conditionally optimal-v normalizer at that sampled shift.
      lp[j] <- log(weights[j]) + proposal$log_predictive_density
    }
    ind_cfr_require(all(is.finite(mn)) && any(is.finite(lp)) && !anyNA(lp),
      "guided state or particle weights collapsed")
    hi <- max(lp); z <- sum(exp(lp - hi)); log_increment[tt] <- hi + log(z)
    weights <- exp(lp - hi) / z; ESS[tt] <- 1 / sum(weights^2)
    underflow[tt] <- sum(is.finite(lp) & weights == 0); zero_weights[tt] <- sum(weights == 0)
    if (tt %in% checkpoint_indices) checkpoints[[as.character(tt)]] <- list(
      observed_prefix_length = tt, parameter_id = parameter_id, eta = eta,
      mean = mn, covariance = Cn, weights = weights,
      representation = "weighted_pre_resampling", future_outcomes_used = 0L,
      conditioning = "fixed_static_parameter_observed_prefix_auxiliary_mixture",
      temporary_projected_location_assimilated = FALSE,
      approximation = "observation_guided_particle_filter_accuracy_unqualified",
      source_draw_inventory_authenticated = FALSE, production_authorized = FALSE)
    resampled[tt] <- ESS[tt] < ess_fraction * N
    idx <- if (resampled[tt]) ind_caf_systematic_indices(weights, uniforms$resampling[tt]) else seq_len(N)
    ancestors[, tt] <- idx; m <- mn[, idx, drop = FALSE]; C <- Cn[, , idx, drop = FALSE]
    if (resampled[tt]) weights <- rep(1 / N, N)
  }
  structure(list(schema_version = "ind_guided_auxiliary_filter_qualification_v1",
    parameter_id = parameter_id, eta = eta, observed_prefix_length = n, particle_count = N,
    checkpoints = checkpoints, ESS = ESS, resampled = resampled, ancestry = ancestors,
    log_predictive_normalizers = log_increment, log_weight_underflow_count = underflow,
    zero_weight_count = zero_weights, parameter_weights_updated = FALSE,
    proposal = if (eta$family == "al") "exact_locally_optimal_v" else "prior_s_conditionally_optimal_v",
    iid_stream_authenticated = FALSE, numerical_accuracy_qualified = FALSE,
    training_auxiliary_integration = "finite_particle_approximation",
    random_draws_generated = 0L, new_model_fits = 0L, production_authorized = FALSE),
    class = c("ind_guided_auxiliary_filter_qualification", "list"))
}

ind_gaf_origin_components <- function(checkpoint, FF, GG, df_mat, future_features,
    tolerance = 1e-10) {
  ind_cfr_require(identical(future_features, "known_deterministic") && is.list(checkpoint) &&
    identical(checkpoint$representation, "weighted_pre_resampling") &&
    is.matrix(checkpoint$mean) && is.numeric(checkpoint$mean) &&
    all(is.finite(checkpoint$mean)) && length(checkpoint$weights) == ncol(checkpoint$mean) &&
    all(is.finite(checkpoint$weights)) && all(checkpoint$weights >= 0) &&
    abs(sum(checkpoint$weights) - 1) <= 1e-10, "valid fixed-origin weighted Gaussian mixture required")
  p <- nrow(checkpoint$mean); N <- ncol(checkpoint$mean)
  ind_cfr_require(is.numeric(FF) && length(FF) == p && all(is.finite(FF)) &&
    is.matrix(GG) && identical(dim(GG), c(p, p)) && all(is.finite(GG)) &&
    identical(dim(checkpoint$covariance), c(p, p, N)), "known first-horizon feature/evolution geometry required")
  ind_caf_psd(df_mat, p, tolerance, "first-horizon discount matrix")
  ind_cfr_require(all(df_mat >= 0), "negative first-horizon discount")
  means <- variance <- numeric(N)
  for (j in seq_len(N)) {
    C <- matrix(checkpoint$covariance[, , j], p, p)
    ind_caf_psd(C, p, tolerance, "origin Gaussian component covariance")
    P <- GG %*% C %*% t(GG); R <- .5 * (P + df_mat * P + t(P + df_mat * P))
    ind_caf_psd(R, p, tolerance, "first-horizon predictive covariance")
    means[j] <- sum(FF * (GG %*% checkpoint$mean[, j]))
    variance[j] <- as.numeric(t(FF) %*% R %*% FF)
  }
  ind_cfr_require(all(is.finite(c(means, variance))) && all(variance >= 0),
    "invalid first-horizon Gaussian mixture moments")
  list(mean = means, variance = variance, weight = checkpoint$weights,
    origin_parameter_id = checkpoint$parameter_id,
    current_future_auxiliary_integration = "analytic_AL_or_exAL_shift_quadrature",
    origin_filter_accuracy_qualified = FALSE, future_feature_provenance_authenticated = FALSE,
    production_authorized = FALSE)
}
