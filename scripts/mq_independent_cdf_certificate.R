# Prospective held-out validation of a finite collection of future CDF values.
# This is not a particle-filter error bound, source authenticator or launcher.
mq_icc_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("MQ independent CDF certificate: ", why), call. = FALSE)
  invisible(TRUE)
}

mq_icc_candidates <- function(candidates, absolute_tolerance = .01, relative_tolerance = .01) {
  mq_icc_require(is.data.frame(candidates) &&
    identical(names(candidates), c("horizon", "probability", "quantile")) && nrow(candidates) >= 1L &&
    all(vapply(candidates, is.numeric, logical(1L))) &&
    all(is.finite(as.matrix(candidates))) &&
    all(candidates$horizon >= 1 & candidates$horizon == as.integer(candidates$horizon)) &&
    all(candidates$probability > 0 & candidates$probability < 1),
    "finite numeric horizon/probability/quantile candidates required")
  H <- max(candidates$horizon); probabilities <- sort(unique(candidates$probability))
  K <- length(probabilities)
  mq_icc_require(nrow(candidates) == H*K &&
    identical(as.integer(candidates$horizon), rep(seq_len(H), each = K)) &&
    identical(as.numeric(candidates$probability), rep(probabilities, H)),
    "complete ordered horizon-by-probability candidate grid required")
  mq_icc_require(is.numeric(absolute_tolerance) && length(absolute_tolerance) == 1L &&
    is.finite(absolute_tolerance) && absolute_tolerance > 0 && absolute_tolerance <= .01 &&
    is.numeric(relative_tolerance) && length(relative_tolerance) == 1L &&
    is.finite(relative_tolerance) && relative_tolerance > 0 && relative_tolerance <= .01,
    "prospective quantile tolerances cannot exceed the existing .01 bounds")
  for (h in seq_len(H)) mq_icc_require(all(diff(candidates$quantile[candidates$horizon == h]) >= 0),
    "candidate quantiles must be ordered within horizon")
  delta <- pmax(absolute_tolerance, relative_tolerance * abs(candidates$quantile))
  lower <- candidates$quantile - delta; upper <- candidates$quantile + delta
  mq_icc_require(all(is.finite(c(lower, upper, delta))) && all(lower < upper),
    "nonfinite or numerically unresolved candidate brackets")
  ids <- paste0("h", candidates$horizon, "_p", sprintf("%.17g", candidates$probability))
  endpoints <- data.frame(candidate = rep(seq_len(nrow(candidates)), each = 2L),
    horizon = rep(candidates$horizon, each = 2L),
    probability = rep(candidates$probability, each = 2L),
    side = rep(c("lower", "upper"), nrow(candidates)),
    y = as.vector(rbind(lower, upper)),
    endpoint_id = as.vector(rbind(paste0(ids, "_lower"), paste0(ids, "_upper"))),
    stringsAsFactors = FALSE)
  list(candidates = candidates, endpoints = endpoints, delta = delta,
    absolute_tolerance = absolute_tolerance, relative_tolerance = relative_tolerance,
    horizons = H, probabilities = probabilities, endpoint_count = nrow(endpoints))
}

mq_icc_stream_contract <- function(contract, validation_rows) {
  mq_icc_require(is.list(contract) &&
    identical(contract$schema_version, "mq_independent_cdf_certificate_contract_v1") &&
    identical(contract$method, "heldout_conditional_CDF_empirical_Bernstein") &&
    identical(contract$conditioning, "one_fixed_original_parameter_draw_and_observed_origin") &&
    identical(contract$validation_values, "iid_future_path_conditional_CDF_not_particle_filter") &&
    identical(contract$candidates_from_training_paths_only, TRUE),
    "explicit fixed-draw future-CDF scope and independent training-candidate declaration required")
  for (key in c("rng_namespace", "draw_id", "origin_id"))
    mq_icc_require(is.character(contract[[key]]) && length(contract[[key]]) == 1L &&
      !is.na(contract[[key]]) && nzchar(contract[[key]]), paste("missing scientific stream identity", key))
  indices <- function(x) is.numeric(x) && length(x) >= 1L && all(is.finite(x)) &&
    all(x >= 1 & x == as.integer(x)) && !anyDuplicated(x)
  mq_icc_require(indices(contract$training_path_indices) && indices(contract$validation_path_indices) &&
    length(contract$validation_path_indices) == validation_rows && validation_rows >= 2L &&
    length(intersect(contract$training_path_indices, contract$validation_path_indices)) == 0L,
    "training and validation scientific path indices must be unique and disjoint, including prefixes")
  mq_icc_require(is.numeric(contract$alpha) && length(contract$alpha) == 1L &&
    is.finite(contract$alpha) && contract$alpha > 0 && contract$alpha <= .05,
    "declared simultaneous error probability cannot exceed .05")
  invisible(TRUE)
}

mq_icc_certify <- function(candidates, validation_cdf, contract) {
  grid <- mq_icc_candidates(candidates, contract$absolute_quantile_tolerance,
    contract$relative_quantile_tolerance)
  mq_icc_require(is.numeric(validation_cdf) && is.matrix(validation_cdf) &&
    nrow(validation_cdf) >= 2L && ncol(validation_cdf) == grid$endpoint_count &&
    identical(colnames(validation_cdf), grid$endpoints$endpoint_id) &&
    all(is.finite(validation_cdf)) && all(validation_cdf >= 0 & validation_cdf <= 1),
    "bounded finite validation CDF matrix with exact endpoint identities required")
  mq_icc_stream_contract(contract, nrow(validation_cdf))
  # A finite union bound applies conditional on independently selected training
  # candidates. These endpoint checks cannot be selected on validation results.
  for (h in seq_len(grid$horizons)) {
    jj <- which(grid$endpoints$horizon == h)
    jj <- jj[order(grid$endpoints$y[jj])]
    if (length(jj) >= 2L) {
      left <- validation_cdf[, head(jj, -1L), drop = FALSE]
      right <- validation_cdf[, tail(jj, -1L), drop = FALSE]
      mq_icc_require(all(left <= right), "a validation path is not a monotone CDF")
      ties <- which(diff(grid$endpoints$y[jj]) == 0)
      if (length(ties)) mq_icc_require(all(left[, ties, drop = FALSE] == right[, ties, drop = FALSE]),
        "duplicate CDF arguments must have identical values")
    }
  }
  n <- nrow(validation_cdf); M <- grid$endpoint_count
  means <- colMeans(validation_cdf)
  sample_variance <- vapply(seq_len(M), function(j) stats::var(validation_cdf[,j]), numeric(1L))
  log_factor <- log(4*M / contract$alpha)
  radius <- sqrt(2 * sample_variance * log_factor / n) + 7 * log_factor / (3 * (n - 1))
  mq_icc_require(all(is.finite(c(means, sample_variance, radius))) && all(sample_variance >= 0),
    "nonfinite empirical Bernstein calculation")
  # Intersecting a confidence interval with [0,1] is valid; input CDF values
  # outside [0,1] are rejected above rather than clipped.
  LCB <- pmax(0, means - radius); UCB <- pmin(1, means + radius)
  lower_col <- seq.int(1L, M, by = 2L); upper_col <- lower_col + 1L
  result <- transform(candidates, lower = grid$endpoints$y[lower_col],
    upper = grid$endpoints$y[upper_col], allowed_quantile_error = grid$delta,
    lower_endpoint_cdf_UCB = UCB[lower_col], upper_endpoint_cdf_LCB = LCB[upper_col],
    pass = UCB[lower_col] < probability & LCB[upper_col] >= probability)
  evidence <- cbind(grid$endpoints, mean = means, sample_variance = sample_variance,
    radius = radius, CDF_LCB = LCB, CDF_UCB = UCB)
  list(schema_version = "mq_independent_cdf_certificate_v1",
    status = if (all(result$pass)) "PASS_HELDOUT_FUTURE_CDF_QUANTILE_BOUND_ONLY" else
      "REVIEW_HELDOUT_FUTURE_CDF_QUANTILE_BOUND",
    result = result, endpoint_evidence = evidence, alpha = contract$alpha,
    endpoint_count = M, training_paths = length(contract$training_path_indices), validation_paths = n,
    formula = "sqrt(2*s2*log(4*M/alpha)/n)+7*log(4*M/alpha)/(3*(n-1))",
    source = "Maurer and Pontil (2009), Theorem 4; two-sided finite union bound",
    source_url = "https://www.cs.mcgill.ca/~colt2009/papers/012.pdf",
    confidence_scope = "one_fixed_draw_origin_all_declared_horizon_probability_endpoints_conditional_on_training_candidates",
    no_campaign_wide_familywise_guarantee = TRUE,
    independence_basis = "declared_disjoint_scientific_future_path_indices",
    stream_contract = contract, source_identity_authenticated = FALSE,
    independent_stream_generation_authenticated = FALSE,
    particle_filter_accuracy_certified = FALSE, origin_filter_accuracy_certified = FALSE,
    observational_future_truth_used = FALSE, random_draws_generated = 0L,
    new_model_fits = 0L, production_authorized = FALSE)
}

# Exact first-horizon MQ response law is a structural source property, not
# a conclusion drawn from zero empirical variance. The external coordinator
# must authenticate the supplied proof and its source before admission.
mq_icc_exact_first_horizon <- function(q, tau, probabilities, proof) {
  mq_icc_require(exists("app_iqf_grid", mode = "function") &&
    exists("app_iqf_hash", mode = "function") && exists("app_iqf_mq_grid_inverse", mode = "function"),
    "source-native MQ grid helpers are required")
  mq_icc_require(is.list(proof) && identical(proof$schema_version, "mq_identical_first_kernel_source_proof_v1") &&
    identical(proof$horizon, 1L) &&
    identical(proof$construction, "deterministic_observed_prefix_no_future_response_in_first_features") &&
    identical(proof$all_first_path_kernels_identical_by_source, TRUE),
    "explicit source-derived identical-first-kernel proof required, not zero sample variance")
  hex <- function(x, n) is.character(x) && length(x) == 1L && !is.na(x) &&
    grepl(paste0("^[a-f0-9]{", n, "}$"), x)
  mq_icc_require(hex(proof$source_commit, 40L) && hex(proof$source_manifest_sha256, 64L) &&
    hex(proof$posterior_target_sha256, 64L) && hex(proof$kernel_sha256, 64L),
    "full source, target and exact kernel hashes required")
  for (key in c("draw_id", "origin_id")) mq_icc_require(is.character(proof[[key]]) &&
    length(proof[[key]]) == 1L && !is.na(proof[[key]]) && nzchar(proof[[key]]),
    "first-horizon original draw/origin identity required")
  grid <- app_iqf_grid(q, tau)
  mq_icc_require(identical(app_iqf_hash(list(family = "mq_grid", q = grid$q, tau = grid$tau)),
    proof$kernel_sha256), "first-horizon kernel content differs from its proof")
  mq_icc_require(is.numeric(probabilities) && length(probabilities) >= 1L &&
    all(is.finite(probabilities)) && all(probabilities > 0 & probabilities < 1),
    "interior first-horizon probabilities required")
  list(status = "EXACT_FIRST_HORIZON_CONDITIONAL_ON_AUTHENTICATED_SOURCE_PROOF",
    horizon = 1L, probability = probabilities,
    quantile = app_iqf_mq_grid_inverse(grid$q, grid$tau, probabilities),
    future_Monte_Carlo_error = 0, proof = proof,
    accuracy_scope = "deterministic_first_horizon_response_law_only_not_origin_filter",
    source_identity_authenticated = FALSE, origin_filter_accuracy_certified = FALSE,
    particle_filter_accuracy_certified = FALSE, random_draws_generated = 0L,
    new_model_fits = 0L, production_authorized = FALSE)
}
