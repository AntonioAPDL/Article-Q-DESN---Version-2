# Qualification-only Rao--Blackwellized auxiliary filtering at fixed eta.
# No RNG, fitted-file I/O, parameter updating, dispatch or article promotion.
if (!exists("ind_cfr_require", mode = "function"))
  source("scripts/ind_conditional_filter_replay.R")

ind_caf_psd <- function(M, p, tolerance, label) {
  ind_cfr_require(is.numeric(M) && is.matrix(M) && identical(dim(M), c(p, p)) &&
    all(is.finite(M)), paste("invalid", label))
  ind_cfr_require(max(abs(M - t(M))) <= tolerance * max(1, max(abs(M))),
    paste("nonsymmetric", label))
  ev <- eigen(.5 * (M + t(M)), symmetric = TRUE, only.values = TRUE)$values
  ind_cfr_require(min(ev) >= -tolerance * max(1, max(abs(ev))), paste("indefinite", label))
  invisible(TRUE)
}

ind_caf_uniforms <- function(u, label) {
  ind_cfr_require(is.numeric(u) && is.matrix(u) && all(dim(u) >= 1L) &&
    all(is.finite(u)) && all(u > 0 & u < 1), paste("open-unit matrix required:", label))
  invisible(TRUE)
}

# The caller supplies and retains the scientific random-number stream. These
# transformations are the frozen Exp(scale=sigma) and half-Normal(0,1) laws.
# Supplying a deterministic matrix does not itself prove iid sampling quality.
ind_caf_prior_auxiliaries <- function(family, p, sigma, u_v, u_s = NULL, gamma = 0) {
  ind_caf_uniforms(u_v, "u_v")
  ind_cfr_require(is.numeric(sigma) && length(sigma) == 1L && is.finite(sigma) &&
    sigma > 0, "positive native auxiliary scale required")
  if (identical(family, "exal")) {
    ind_caf_uniforms(u_s, "u_s")
    ind_cfr_require(identical(dim(u_v), dim(u_s)), "paired auxiliary dimensions differ")
  } else ind_cfr_require(is.null(u_s), "AL cannot accept half-normal innovations")
  v <- matrix(stats::qexp(as.numeric(u_v), rate = 1 / sigma), nrow(u_v), ncol(u_v))
  s <- if (is.null(u_s)) NULL else
    matrix(stats::qnorm((1 - as.numeric(u_s)) / 2, lower.tail = FALSE), nrow(u_s), ncol(u_s))
  obs <- ind_cfr_augmentation(family, p, sigma, as.numeric(v),
    if (is.null(s)) NULL else as.numeric(s), gamma)
  structure(list(schema_version = "ind_native_prior_auxiliary_design_v1",
    family = family, p = p, sigma = sigma, gamma = gamma,
    ex_f = matrix(obs$ex_f, nrow(u_v), ncol(u_v)),
    ex_q = matrix(obs$ex_q, nrow(u_v), ncol(u_v)),
    proposal = "native_auxiliary_prior", random_draws_generated = 0L,
    iid_stream_authentication_performed = FALSE, production_authorized = FALSE),
    class = c("ind_native_prior_auxiliary_design", "list"))
}

ind_caf_systematic_indices <- function(weights, u) {
  N <- length(weights)
  ind_cfr_require(is.numeric(weights) && N >= 1L && all(is.finite(weights)) &&
    all(weights >= 0) && abs(sum(weights) - 1) < 1e-10 &&
    is.numeric(u) && length(u) == 1L && is.finite(u) && u > 0 && u < 1,
    "invalid normalized weights or resampling innovation")
  weights <- weights / sum(weights)
  active <- which(weights > 0)
  cdf <- pmin(1, cumsum(weights[active])); cdf[length(cdf)] <- 1
  # findInterval uses right-open intervals; exact boundaries have probability 0
  # under continuous supplied u. Form the CDF only on positive components:
  # rounding a final position to 1 must not select a trailing zero mass.
  pos <- pmin((seq_len(N) - 1 + u) / N, 1 - .Machine$double.eps / 2)
  as.integer(active[findInterval(pos, c(0, cdf), rightmost.closed = TRUE)])
}

# One fixed native parameter column per call. The column identifier is a label,
# not an assertion that an external fitted-file/parameter inventory was audited.
# ex_f/ex_q are proposal-particle x observed-time arrays. This low-level entry
# also permits explicitly labelled finite Gaussian-mixture mathematical fixtures.
# With resampling, an input row supplies a NEW innovation at each time: it is
# not a preselected complete auxiliary path carried through ancestor selection.
ind_caf_filter_moments <- function(y, FF, GG, m0, C0, df_mat, ex_f, ex_q,
    observed_prefix_length, parameter_id, proposal_role,
    checkpoint_indices, u_resample, ess_fraction = .5,
    initial_weights = NULL, tolerance = 1e-10) {
  ind_cfr_require(!missing(observed_prefix_length) && is.numeric(observed_prefix_length) &&
    length(observed_prefix_length) == 1L && is.finite(observed_prefix_length) &&
    observed_prefix_length >= 1 && observed_prefix_length == as.integer(observed_prefix_length),
    "explicit observed-prefix length required for auxiliary filter")
  n <- as.integer(observed_prefix_length); p <- length(m0)
  ind_cfr_require(is.numeric(tolerance) && length(tolerance) == 1L &&
    is.finite(tolerance) && tolerance > 0 && is.numeric(y) && length(y) == n &&
    all(is.finite(y)) && is.numeric(m0) && p >= 1L && all(is.finite(m0)),
    "invalid filter observed prefix or initial mean")
  if (is.matrix(GG)) {
    ind_cfr_require(identical(dim(GG), c(p, p)), "invalid constant filter evolution")
    GG <- array(rep(GG, n), c(p, p, n))
  }
  ind_cfr_require(is.character(parameter_id) && length(parameter_id) == 1L &&
    !is.na(parameter_id) && nzchar(parameter_id) && is.character(proposal_role) &&
    length(proposal_role) == 1L && proposal_role %in%
      c("native_auxiliary_prior", "finite_prior_fixture"),
    "one fixed parameter identity and explicit prior proposal required")
  ind_cfr_require(is.numeric(FF) && is.matrix(FF) && identical(dim(FF), c(p, n)) &&
    is.numeric(GG) && identical(dim(GG), c(p, p, n)) && all(is.finite(c(FF, GG))) &&
    is.numeric(ex_f) && is.matrix(ex_f) && is.numeric(ex_q) && is.matrix(ex_q) &&
    identical(dim(ex_f), dim(ex_q)) && ncol(ex_f) == n && nrow(ex_f) >= 1L &&
    all(is.finite(c(ex_f, ex_q))) && all(ex_q > 0),
    "incompatible observed filter or auxiliary moments")
  N <- nrow(ex_f)
  ind_caf_psd(C0, p, tolerance, "initial filter covariance")
  ind_caf_psd(df_mat, p, tolerance, "filter discount matrix")
  ind_cfr_require(all(df_mat >= 0), "negative filter discount inflation")
  ind_cfr_require(is.numeric(checkpoint_indices) && length(checkpoint_indices) >= 1L &&
    all(is.finite(checkpoint_indices)) && all(checkpoint_indices == as.integer(checkpoint_indices)) &&
    all(checkpoint_indices >= 1L & checkpoint_indices <= n) &&
    !anyDuplicated(checkpoint_indices) && !is.unsorted(checkpoint_indices),
    "sorted unique observed checkpoint indices required")
  ind_cfr_require(is.numeric(ess_fraction) && length(ess_fraction) == 1L &&
    is.finite(ess_fraction) && ess_fraction >= 0 && ess_fraction <= 1 &&
    is.numeric(u_resample) && length(u_resample) == n && all(is.finite(u_resample)) &&
    all(u_resample > 0 & u_resample < 1), "invalid ESS gate or resampling stream")
  if (is.null(initial_weights)) initial_weights <- rep(1 / N, N)
  ind_cfr_require(is.numeric(initial_weights) && length(initial_weights) == N &&
    all(is.finite(initial_weights)) && all(initial_weights >= 0) &&
    is.finite(sum(initial_weights)) && sum(initial_weights) > 0,
    "invalid initial within-parameter weights")
  weight <- initial_weights / sum(initial_weights)
  m <- matrix(rep(m0, N), p, N); C <- array(rep(C0, N), c(p, p, N))
  ess <- log_evidence_increment <- numeric(n); resampled <- logical(n)
  weight_underflow <- zero_weights <- integer(n)
  ancestry <- matrix(0L, N, n); checkpoints <- list()
  sym <- function(M) .5 * (M + t(M))
  for (tt in seq_len(n)) {
    G <- matrix(GG[, , tt], p, p); F <- as.numeric(FF[, tt])
    next_m <- matrix(0, p, N); next_C <- array(0, c(p, p, N))
    lp <- numeric(N)
    for (j in seq_len(N)) {
      a <- as.numeric(G %*% m[, j]); P <- G %*% matrix(C[, , j], p, p) %*% t(G)
      W <- sym(df_mat * P); R <- sym(P + df_mat * P)
      ind_caf_psd(W, p, tolerance, "particle innovation covariance")
      ind_caf_psd(R, p, tolerance, "particle prior covariance")
      RF <- as.numeric(R %*% F); f <- sum(F * a) + ex_f[j, tt]
      Q <- sum(F * RF) + ex_q[j, tt]
      ind_cfr_require(is.finite(Q) && Q > 0, "nonpositive particle variance; native Q floor is not a qualified probability law")
      next_m[, j] <- a + RF * ((y[tt] - f) / Q)
      next_C[, , j] <- sym(R - tcrossprod(RF) / Q)
      ind_caf_psd(matrix(next_C[, , j], p, p), p, tolerance, "particle filtered covariance")
      lp[j] <- log(weight[j]) + stats::dnorm(y[tt], f, sqrt(Q), log = TRUE)
    }
    ind_cfr_require(all(is.finite(next_m)) && any(is.finite(lp)) && !any(is.na(lp)),
      "nonfinite state update or collapsed auxiliary weights")
    lmax <- max(lp); z <- sum(exp(lp - lmax))
    log_evidence_increment[tt] <- lmax + log(z)
    weight <- exp(lp - lmax) / z; ess[tt] <- 1 / sum(weight^2)
    weight_underflow[tt] <- sum(is.finite(lp) & weight == 0)
    zero_weights[tt] <- sum(weight == 0)
    # Checkpoints precede optional resampling and never incorporate later data.
    if (tt %in% checkpoint_indices) checkpoints[[as.character(tt)]] <- list(
      observed_prefix_length = tt, parameter_id = parameter_id,
      mean = next_m, covariance = next_C, weights = weight,
      conditioning = "fixed_static_parameter_observed_prefix_auxiliary_mixture",
      future_outcomes_used = 0L, representation = "weighted_pre_resampling",
      approximation = "finite_auxiliary_particle_filter_not_exact_posterior",
      source_draw_inventory_authenticated = FALSE, production_authorized = FALSE)
    resampled[tt] <- ess[tt] < ess_fraction * N
    idx <- if (resampled[tt]) ind_caf_systematic_indices(weight, u_resample[tt]) else seq_len(N)
    ancestry[, tt] <- idx
    m <- next_m[, idx, drop = FALSE]; C <- next_C[, , idx, drop = FALSE]
    if (resampled[tt]) weight <- rep(1 / N, N)
  }
  structure(list(schema_version = "ind_conditional_auxiliary_filter_qualification_v1",
    parameter_id = parameter_id, proposal_role = proposal_role,
    observed_prefix_length = n, particle_count = N,
    checkpoints = checkpoints, ESS = ess, resampled = resampled, ancestry = ancestry,
    log_weight_underflow_count = weight_underflow, zero_weight_count = zero_weights,
    log_predictive_normalizers = log_evidence_increment,
    normalizers_are_for_within_parameter_filter_not_parameter_reweighting = TRUE,
    training_auxiliary_integration = "finite_particle_approximation_accuracy_unqualified",
    state_uncertainty_integrated_conditionally = TRUE,
    observed_prefix_only = TRUE, parameter_weights_updated = FALSE,
    numerical_accuracy_qualified = FALSE, iid_stream_authenticated = FALSE,
    new_model_fits = 0L, random_draws_generated = 0L,
    forecast_paths_generated = 0L, production_authorized = FALSE),
    class = c("ind_conditional_auxiliary_filter_qualification", "list"))
}

ind_caf_filter <- function(y, FF, GG, m0, C0, df_mat, auxiliary_design,
    observed_prefix_length, parameter_id, checkpoint_indices, u_resample,
    ess_fraction = .5, tolerance = 1e-10) {
  ind_cfr_require(inherits(auxiliary_design, "ind_native_prior_auxiliary_design") &&
    identical(auxiliary_design$proposal, "native_auxiliary_prior"),
    "authenticated-role native prior design required; general guided proposals are not implemented")
  ind_caf_filter_moments(y, FF, GG, m0, C0, df_mat,
    auxiliary_design$ex_f, auxiliary_design$ex_q, observed_prefix_length,
    parameter_id, "native_auxiliary_prior", checkpoint_indices, u_resample,
    ess_fraction = ess_fraction, tolerance = tolerance)
}
