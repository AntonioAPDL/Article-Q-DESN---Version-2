# Deterministic replay of the frozen C++-fast conditional forward operator.
# This is a qualification component, not a marginal AL/exAL state filter.

ind_cfr_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste0("IND conditional replay: ", message), call. = FALSE)
  invisible(TRUE)
}

ind_cfr_policy <- function() {
  list(schema_version = "ind_cpp_fast_conditional_forward_policy_v1",
    source_file = "src/mcmc_ffbs.cpp",
    source_sha256 = "f6ccf41466ece60a3a63737bb434309e8bea59f5b254a086793e5cca0aba6065",
    native_backend = "C++", native_mode = "fast",
    propagation = "P=G*C*G_transpose;W=df_mat_elementwise_P;R=symmetrize(P+W)",
    covariance_regularization = "symmetrize_only_no_SVD_floor_or_cap",
    scalar_variance_rule = "nonfinite_or_nonpositive_Q_replaced_by_1e-12",
    first_observation = "G[,,1] propagates m0,C0 before observing y[1]",
    conditioning = "static_parameters_and_paired_training_augmentation",
    static_parameter_marginal = FALSE, native_execution_performed = FALSE,
    later_origin_filter_implemented = FALSE, production_authorized = FALSE)
}

ind_cfr_discount_matrix <- function(df, dim_df, p = sum(dim_df)) {
  ind_cfr_require(is.numeric(df) && length(df) > 0L && all(is.finite(df)) &&
    all(df > 0 & df <= 1) && is.numeric(dim_df) && length(dim_df) == length(df) &&
    all(is.finite(dim_df)) && all(dim_df >= 1 & dim_df == as.integer(dim_df)) &&
    is.numeric(p) && length(p) == 1L && is.finite(p) && p >= 1 && p == as.integer(p) &&
    sum(dim_df) == p, "invalid native discount blocks")
  out <- matrix(0, p, p)
  ends <- cumsum(as.integer(dim_df)); starts <- c(1L, head(ends, -1L) + 1L)
  for (j in seq_along(df)) out[starts[j]:ends[j], starts[j]:ends[j]] <- (1 - df[j]) / df[j]
  out
}

# The exact native p.fn/log_g parameterization, not p substituted for exAL r.
ind_cfr_augmentation <- function(family, p, sigma, v, s = NULL, gamma = 0) {
  ind_cfr_require(is.character(family) && length(family) == 1L && family %in% c("al", "exal") &&
    is.numeric(p) && length(p) == 1L && is.finite(p) && p > 0 && p < 1 &&
    is.numeric(sigma) && length(sigma) == 1L && is.finite(sigma) && sigma > 0 &&
    is.numeric(v) && length(v) > 0L && all(is.finite(v)) && all(v > 0) &&
    is.numeric(gamma) && length(gamma) == 1L && is.finite(gamma),
    "invalid paired scale/probability/augmentation support")
  if (family == "al") {
    ind_cfr_require(gamma == 0 && is.null(s), "AL cannot inherit an exAL shape or half-normal augmentation")
    r <- p; C <- 0
  } else {
    ind_cfr_require(is.numeric(s) && length(s) == length(v) && all(is.finite(s)) && all(s >= 0),
      "exAL requires its paired nonnegative half-normal augmentation")
    log_g <- log(2) + stats::pnorm(-abs(gamma), log.p = TRUE) + .5 * gamma^2
    r <- (p - as.numeric(gamma < 0)) / exp(log_g) + as.numeric(gamma < 0)
    ind_cfr_require(is.finite(r) && r > 0 && r < 1, "shape is outside native quantile-fixed support")
    C <- (as.numeric(gamma > 0) - r)^(-1)
  }
  A <- (1 - 2 * r) / (r * (1 - r)); B <- 2 / (r * (1 - r))
  ex_f <- A * v
  if (family == "exal") ex_f <- ex_f + sigma * C * abs(gamma) * s
  ex_q <- B * sigma * v
  ind_cfr_require(all(is.finite(c(ex_f, ex_q))) && all(ex_q > 0), "nonfinite conditional observation moments")
  list(ex_f = ex_f, ex_q = ex_q, family = family, p = p, native_r = r,
    sigma = sigma, gamma = gamma, conditioning = ind_cfr_policy()$conditioning,
    static_parameter_marginal = FALSE, random_draws_generated = 0L)
}

ind_cfr_cpp_forward <- function(y, FF, GG, m0, C0, ex_f, ex_q, df_mat,
    observed_prefix_length, tolerance = 1e-10) {
  ind_cfr_require(!missing(observed_prefix_length) && is.numeric(observed_prefix_length) &&
    length(observed_prefix_length) == 1L && is.finite(observed_prefix_length) &&
    observed_prefix_length >= 1 && observed_prefix_length == as.integer(observed_prefix_length),
    "explicit observed-prefix length is required")
  n <- as.integer(observed_prefix_length); p <- length(m0)
  ind_cfr_require(is.numeric(tolerance) && length(tolerance) == 1L && is.finite(tolerance) &&
    tolerance > 0 && is.numeric(y) && length(y) == n && all(is.finite(y)) &&
    is.numeric(m0) && p >= 1L && all(is.finite(m0)), "invalid observed prefix or initial mean")
  if (is.matrix(GG)) {
    ind_cfr_require(is.numeric(GG) && identical(dim(GG), c(p, p)), "invalid constant evolution matrix")
    GG <- array(rep(GG, n), c(p, p, n))
  }
  ind_cfr_require(is.numeric(FF) && is.matrix(FF) && identical(dim(FF), c(p, n)) &&
    is.numeric(GG) && identical(dim(GG), c(p, p, n)) && all(is.finite(c(FF, GG))) &&
    is.numeric(C0) && is.matrix(C0) && identical(dim(C0), c(p, p)) &&
    is.numeric(df_mat) && is.matrix(df_mat) && identical(dim(df_mat), c(p, p)) &&
    all(is.finite(c(C0, df_mat))) && is.numeric(ex_f) && length(ex_f) == n &&
    is.numeric(ex_q) && length(ex_q) == n && all(is.finite(c(ex_f, ex_q))) && all(ex_q >= 0),
    "incompatible training-only dimensions or conditional observation moments")
  psd <- function(M, label) {
    ind_cfr_require(all(is.finite(M)) && max(abs(M - t(M))) <= tolerance * max(1, max(abs(M))),
      paste("nonfinite or nonsymmetric", label))
    vals <- eigen((M + t(M)) / 2, symmetric = TRUE, only.values = TRUE)$values
    ind_cfr_require(min(vals) >= -tolerance * max(1, max(abs(vals))), paste("indefinite", label))
  }
  psd(C0, "initial covariance"); psd(df_mat, "discount matrix")
  ind_cfr_require(all(df_mat >= 0), "negative discount inflation is not supported")
  sym <- function(M) .5 * (M + t(M))
  fm <- a <- matrix(0, p, n)
  fC <- P <- W <- R <- array(0, c(p, p, n))
  f <- Q <- Q_raw <- sfe <- log_weight <- numeric(n)
  q_floor <- logical(n)
  for (tt in seq_len(n)) {
    Gt <- matrix(GG[, , tt], p, p); Ft <- as.numeric(FF[, tt])
    previous_m <- if (tt == 1L) m0 else fm[, tt - 1L]
    previous_C <- if (tt == 1L) C0 else matrix(fC[, , tt - 1L], p, p)
    a[, tt] <- as.numeric(Gt %*% previous_m)
    Pt <- Gt %*% previous_C %*% t(Gt)
    Wt <- df_mat * Pt
    Rt <- sym(Pt + Wt)
    psd(Rt, "native prior covariance")
    f[tt] <- sum(Ft * a[, tt]) + ex_f[tt]
    fB <- as.numeric(t(Ft) %*% Rt)
    Q_raw[tt] <- sum(fB * Ft) + ex_q[tt]
    q_floor[tt] <- !is.finite(Q_raw[tt]) || Q_raw[tt] <= 0
    Q[tt] <- if (q_floor[tt]) 1e-12 else Q_raw[tt]
    fm[, tt] <- a[, tt] + as.numeric(Rt %*% Ft) * ((y[tt] - f[tt]) / Q[tt])
    Ct <- sym(Rt - (Rt %*% Ft %*% t(Ft) %*% Rt) / Q[tt])
    psd(Ct, "native filtered covariance")
    ind_cfr_require(all(is.finite(c(a[, tt], fm[, tt], f[tt], Q[tt]))), "nonfinite native forward update")
    fC[, , tt] <- Ct; P[, , tt] <- Pt; W[, , tt] <- Wt; R[, , tt] <- Rt
    sfe[tt] <- (y[tt] - f[tt]) / sqrt(Q[tt])
    log_weight[tt] <- stats::dnorm(y[tt], f[tt], sqrt(Q[tt]), log = TRUE)
  }
  structure(list(schema_version = "ind_conditional_cpp_forward_replay_v1",
    fm = fm, fC = fC, standard.forecast.errors = sfe,
    lineage = list(local_training_index = seq_len(n), a = a, P = P, W = W, R = R,
      f = f, Q_raw = Q_raw, Q = Q, native_Q_floor_applied = q_floor,
      Gaussian_log_predictive_weight = log_weight),
    policy = ind_cfr_policy(), observed_prefix_length = n,
    conditioning = ind_cfr_policy()$conditioning, state_uncertainty_integrated_conditionally = TRUE,
    training_augmentation_integrated = FALSE, static_parameter_marginal = FALSE,
    later_origin_filter_implemented = FALSE, random_draws_generated = 0L,
    new_model_fits = 0L, forecasts_generated = 0L, production_authorized = FALSE),
    class = c("ind_conditional_cpp_forward_replay", "list"))
}

ind_cfr_compare_native <- function(replay, native, absolute_tolerance, relative_tolerance) {
  ind_cfr_require(inherits(replay, "ind_conditional_cpp_forward_replay") && is.list(native) &&
    is.numeric(absolute_tolerance) && length(absolute_tolerance) == 1L &&
    is.finite(absolute_tolerance) && absolute_tolerance > 0 &&
    is.numeric(relative_tolerance) && length(relative_tolerance) == 1L &&
    is.finite(relative_tolerance) && relative_tolerance > 0,
    "declared native comparison and numerical tolerances required")
  rows <- lapply(c("fm", "fC", "standard.forecast.errors"), function(key) {
    x <- replay[[key]]; z <- native[[key]]
    ind_cfr_require(is.numeric(z) && identical(dim(x), dim(z)) && length(x) == length(z) &&
      length(z) > 0L && all(is.finite(c(x, z))), paste("native output structure differs:", key))
    d <- abs(x - z)
    data.frame(field = key, values = length(d), max_absolute_difference = max(d),
      max_scaled_difference = max(d / pmax(1, abs(z))),
      pass = all(d <= absolute_tolerance + relative_tolerance * pmax(abs(x), abs(z))))
  })
  out <- do.call(rbind, rows)
  list(status = if (all(out$pass)) "NATIVE_FORWARD_PARITY_PASS" else "NATIVE_FORWARD_PARITY_FAIL",
    fields = out, absolute_tolerance = absolute_tolerance, relative_tolerance = relative_tolerance,
    scope = "full_time_indexed_forward_moments_only_not_marginal_filter_or_campaign",
    production_authorized = FALSE)
}
