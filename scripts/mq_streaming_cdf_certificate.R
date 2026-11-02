# Streaming sufficient statistics for the separately declared prospective MQ
# precision qualification. This module generates no paths and authenticates no
# source. Its probability bound applies only conditional on the frozen training
# candidates and iid future-path CDF contributions, never to filter particles.
if (!exists("mq_icc_candidates", mode = "function"))
  source("scripts/mq_independent_cdf_certificate.R")

mq_scc_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("MQ streaming CDF certificate: ", why), call. = FALSE)
  invisible(TRUE)
}

mq_scc_hash <- function(x) {
  mq_scc_require(requireNamespace("digest", quietly = TRUE), "digest is required")
  digest::digest(x, algo = "sha256", serialize = TRUE, serializeVersion = 2L)
}

mq_scc_contract <- function(contract, candidates) {
  mq_scc_require(is.list(contract) &&
    identical(contract$schema_version, "mq_streaming_cdf_certificate_contract_v1") &&
    identical(contract$method, "heldout_conditional_CDF_empirical_Bernstein_alpha_spending") &&
    identical(contract$conditioning, "one_fixed_original_parameter_draw_and_observed_origin") &&
    identical(contract$validation_values, "iid_future_path_conditional_CDF_not_particle_filter") &&
    identical(contract$candidates_from_training_paths_only, TRUE),
    "explicit fixed-draw future-CDF scope and training-only candidates required")
  for (key in c("rng_namespace", "draw_id", "origin_id"))
    mq_scc_require(is.character(contract[[key]]) && length(contract[[key]]) == 1L &&
      !is.na(contract[[key]]) && nzchar(contract[[key]]), paste("missing stream identity", key))
  exact_numbers <- function(x, expected) is.numeric(x) &&
    length(x) == length(expected) && all(is.finite(x)) && all(x == expected)
  mq_scc_require(exact_numbers(contract$training_path_range, c(1, 65536)) &&
    exact_numbers(contract$validation_path_range, c(65537, 327680)) &&
    exact_numbers(contract$look_sizes, c(65536, 131072, 262144)),
    "the frozen training/validation ranges and three look sizes cannot change")
  mq_scc_require(exact_numbers(contract$total_alpha, .05) &&
    is.numeric(contract$alpha_per_look) && length(contract$alpha_per_look) == 3L &&
    all(is.finite(contract$alpha_per_look)) && all(contract$alpha_per_look > 0) &&
    all(abs(contract$alpha_per_look - .05/3) <= 1e-16) &&
    sum(contract$alpha_per_look) <= contract$total_alpha + 1e-16,
    "three prespecified .05/3 allocations with total error probability .05 required")
  mq_scc_require(exact_numbers(contract$absolute_quantile_tolerance, .01) &&
    exact_numbers(contract$relative_quantile_tolerance, .01),
    "the existing .01 absolute-OR-relative quantile tolerances cannot change")
  for (flag in c("source_identity_authenticated", "independent_stream_generation_authenticated",
    "particle_filter_accuracy_certified", "origin_filter_accuracy_certified", "production_authorized"))
    mq_scc_require(is.null(contract[[flag]]) || identical(contract[[flag]], FALSE),
      paste("this certificate cannot declare", flag))
  split <- contract$training_split_diagnostic
  keys <- c("horizon", "probability", "split_stream_absolute_difference", "split_stream_relative_difference")
  mq_scc_require(is.data.frame(split) && all(keys %in% names(split)) &&
    nrow(split) == nrow(candidates) && all(vapply(split[keys], is.numeric, logical(1L))) &&
    identical(as.numeric(split$horizon), as.numeric(candidates$horizon)) &&
    identical(as.numeric(split$probability), as.numeric(candidates$probability)) &&
    all(is.finite(split$split_stream_absolute_difference)) &&
    all(split$split_stream_absolute_difference >= 0) &&
    !anyNA(split$split_stream_relative_difference) &&
    all(split$split_stream_relative_difference >= 0),
    "frozen, keyed, nonnegative training split diagnostics are required")
  # +Inf is a permissible relative difference at a zero reference quantile;
  # the absolute branch of the unchanged OR criterion still has its meaning.
  invisible(TRUE)
}

mq_scc_seal <- function(state) {
  state$integrity_sha256 <- NULL
  state$integrity_sha256 <- mq_scc_hash(state)
  state
}

mq_scc_check_state <- function(state) {
  mq_scc_require(is.list(state) && identical(state$schema_version, "mq_streaming_cdf_state_v1") &&
    is.character(state$integrity_sha256) && length(state$integrity_sha256) == 1L,
    "a sealed streaming state is required")
  seal <- state$integrity_sha256; state$integrity_sha256 <- NULL
  mq_scc_require(identical(seal, mq_scc_hash(state)), "streaming state was modified outside the API")
  mq_scc_require(identical(state$candidates_sha256, mq_scc_hash(state$candidates)) &&
    identical(state$contract_sha256, mq_scc_hash(state$contract)) &&
    identical(state$endpoints_sha256, mq_scc_hash(state$grid$endpoints)),
    "frozen candidates, endpoint grid or prospective contract changed")
  invisible(TRUE)
}

mq_scc_init <- function(candidates, contract) {
  mq_scc_contract(contract, candidates)
  grid <- mq_icc_candidates(candidates, contract$absolute_quantile_tolerance,
    contract$relative_quantile_tolerance)
  orders <- lapply(seq_len(grid$horizons), function(h) {
    j <- which(grid$endpoints$horizon == h)
    j[order(grid$endpoints$y[j])]
  })
  ties <- lapply(orders, function(j) which(diff(grid$endpoints$y[j]) == 0))
  empty <- data.frame(block = integer(), count = integer(), first_path_id = integer(),
    last_path_id = integer(), data_sha256 = character(), previous_chain_sha256 = character(),
    chain_sha256 = character(), stringsAsFactors = FALSE)
  genesis <- mq_scc_hash(list(candidates = candidates, contract = contract))
  mq_scc_seal(list(schema_version = "mq_streaming_cdf_state_v1", candidates = candidates,
    contract = contract, grid = grid, candidates_sha256 = mq_scc_hash(candidates),
    endpoints_sha256 = mq_scc_hash(grid$endpoints), contract_sha256 = mq_scc_hash(contract),
    cdf_order_by_horizon = orders, cdf_ties_by_horizon = ties, count = 0L,
    mean = setNames(numeric(grid$endpoint_count), grid$endpoints$endpoint_id),
    M2 = setNames(numeric(grid$endpoint_count), grid$endpoints$endpoint_id),
    blocks = empty, genesis_chain_sha256 = genesis, last_chain_sha256 = genesis,
    next_look_index = 1L, look_history = list(), last_evaluation = NULL,
    terminal = FALSE, raw_validation_matrix_retained = FALSE,
    retention = "Welford count/means/M2; every block range and data SHA256; frozen candidates/contract; fixed-look evidence"))
}

mq_scc_update <- function(state, values, path_ids) {
  mq_scc_check_state(state)
  mq_scc_require(!state$terminal, "a terminal state cannot receive additional validation paths")
  mq_scc_require(is.matrix(values) && is.numeric(values) && nrow(values) >= 1L &&
    ncol(values) == state$grid$endpoint_count &&
    identical(colnames(values), state$grid$endpoints$endpoint_id) &&
    all(is.finite(values)) && all(values >= 0 & values <= 1),
    "finite, bounded CDF contributions with exact frozen endpoint columns required")
  n <- nrow(values)
  expected <- seq.int(as.integer(state$contract$validation_path_range[1L]) + state$count,
    length.out = n)
  mq_scc_require(is.numeric(path_ids) && length(path_ids) == n &&
    all(is.finite(path_ids)) && all(path_ids == expected),
    "validation IDs must be the next contiguous fresh prefix, disjoint from all training paths")
  next_look <- state$contract$look_sizes[state$next_look_index]
  mq_scc_require(state$count < next_look && state$count + n <= next_look &&
    tail(expected, 1L) <= state$contract$validation_path_range[2L],
    "an update cannot cross an unassessed prescribed look or exceed its validation range")
  for (h in seq_along(state$cdf_order_by_horizon)) {
    j <- state$cdf_order_by_horizon[[h]]
    if (length(j) < 2L) next
    a <- values[, head(j, -1L), drop = FALSE]
    b <- values[, tail(j, -1L), drop = FALSE]
    mq_scc_require(all(a <= b), "a validation path is not a monotone CDF")
    tied <- state$cdf_ties_by_horizon[[h]]
    if (length(tied)) mq_scc_require(all(a[, tied, drop = FALSE] == b[, tied, drop = FALSE]),
      "equal CDF arguments must have identical contributions")
  }
  # Parallel/Welford merge, using unbiased sample variance M2/(n-1).
  b_mean <- colMeans(values)
  b_M2 <- colSums(sweep(values, 2L, b_mean, "-")^2)
  old_n <- state$count; total <- old_n + n
  if (old_n == 0L) {
    state$mean <- b_mean; state$M2 <- b_M2
  } else {
    shift <- b_mean - state$mean
    state$mean <- state$mean + shift * (n / total)
    state$M2 <- state$M2 + b_M2 + shift^2 * (as.double(old_n) * n / total)
  }
  mq_scc_require(all(is.finite(c(state$mean, state$M2))) && all(state$M2 >= 0),
    "nonfinite or negative Welford moments")
  record <- list(block = nrow(state$blocks) + 1L, count = n,
    first_path_id = as.integer(expected[1L]), last_path_id = as.integer(tail(expected, 1L)),
    data_sha256 = mq_scc_hash(list(path_ids = as.integer(path_ids), values = values)),
    previous_chain_sha256 = state$last_chain_sha256)
  record$chain_sha256 <- mq_scc_hash(record)
  state$blocks <- rbind(state$blocks, as.data.frame(record, stringsAsFactors = FALSE))
  state$last_chain_sha256 <- record$chain_sha256
  state$count <- as.integer(total)
  mq_scc_seal(state)
}

mq_scc_evaluate <- function(state) {
  mq_scc_check_state(state)
  mq_scc_require(!state$terminal, "a terminal state cannot be evaluated again")
  look <- state$next_look_index
  mq_scc_require(state$count == state$contract$look_sizes[look],
    "evaluation is permitted only at the next prespecified validation count")
  # Recheck the compact block receipt chain at each authorized look. These
  # hashes detect receipt changes, not independently authenticate raw paths.
  previous <- state$genesis_chain_sha256
  next_id <- as.integer(state$contract$validation_path_range[1L])
  for (i in seq_len(nrow(state$blocks))) {
    rec <- as.list(state$blocks[i, , drop = FALSE]); chain <- rec$chain_sha256
    rec$chain_sha256 <- NULL
    mq_scc_require(rec$block == i && rec$count >= 1L && rec$first_path_id == next_id &&
      rec$last_path_id == rec$first_path_id + rec$count - 1L &&
      identical(rec$previous_chain_sha256, previous) && identical(chain, mq_scc_hash(rec)),
      "block range or data-hash receipt chain changed")
    next_id <- rec$last_path_id + 1L; previous <- chain
  }
  mq_scc_require(sum(state$blocks$count) == state$count &&
    identical(previous, state$last_chain_sha256), "block receipts do not match streaming counts")
  n <- state$count; M <- state$grid$endpoint_count
  alpha <- state$contract$alpha_per_look[look]
  variance <- state$M2 / (n - 1)
  log_factor <- log(4*M / alpha)
  radius <- sqrt(2 * variance * log_factor / n) + 7 * log_factor / (3 * (n - 1))
  LCB <- pmax(0, state$mean - radius); UCB <- pmin(1, state$mean + radius)
  low <- seq.int(1L, M, by = 2L); high <- low + 1L
  split <- state$contract$training_split_diagnostic
  split_pass <- split$split_stream_absolute_difference <= .005 |
    split$split_stream_relative_difference <= .005
  result <- transform(state$candidates, lower = state$grid$endpoints$y[low],
    upper = state$grid$endpoints$y[high], allowed_quantile_error = state$grid$delta,
    lower_endpoint_cdf_UCB = UCB[low], upper_endpoint_cdf_LCB = LCB[high],
    pass = UCB[low] < probability & LCB[high] >= probability,
    training_split_gate_pass = split_pass)
  all_bounds <- all(result$pass); all_split <- all(split_pass)
  passed <- all_bounds && all_split
  evidence <- cbind(state$grid$endpoints, mean = as.numeric(state$mean),
    sample_variance = as.numeric(variance), radius = as.numeric(radius),
    CDF_LCB = as.numeric(LCB), CDF_UCB = as.numeric(UCB))
  state$last_evaluation <- list(schema_version = "mq_streaming_cdf_certificate_v1",
    status = if (passed) "PASS_STREAMING_HELDOUT_FUTURE_CDF_QUANTILE_BOUND_ONLY" else
      "REVIEW_STREAMING_HELDOUT_FUTURE_CDF_QUANTILE_BOUND",
    result = result, endpoint_evidence = evidence, alpha = alpha,
    alpha_per_look = state$contract$alpha_per_look, total_alpha = state$contract$total_alpha,
    alpha_spent = sum(state$contract$alpha_per_look[seq_len(look)]),
    look_index = look, validation_paths = n, endpoint_count = M,
    all_quantile_bounds_pass = all_bounds, training_split_gate_pass = all_split,
    all_required_gates_pass = passed,
    formula = "sqrt(2*s2*log(4*M/alpha_look)/n)+7*log(4*M/alpha_look)/(3*(n-1))",
    source = "Maurer and Pontil (2009), Theorem 4; endpoint/side union within look and fixed-look alpha spending",
    source_url = "https://www.cs.mcgill.ca/~colt2009/papers/012.pdf",
    confidence_scope = "one_fixed_draw_origin_all_frozen_endpoints_and_prespecified_looks_conditional_on_training_candidates",
    no_campaign_wide_familywise_guarantee = TRUE,
    independence_basis = "declared_disjoint_scientific_future_path_ranges",
    candidates_sha256 = state$candidates_sha256, endpoints_sha256 = state$endpoints_sha256,
    contract_sha256 = state$contract_sha256, last_block_chain_sha256 = state$last_chain_sha256,
    stream_contract = state$contract, source_identity_authenticated = FALSE,
    independent_stream_generation_authenticated = FALSE,
    particle_filter_accuracy_certified = FALSE, origin_filter_accuracy_certified = FALSE,
    observational_future_truth_used = FALSE, raw_validation_matrix_retained = FALSE,
    random_draws_generated = 0L, new_model_fits = 0L, production_authorized = FALSE)
  state$look_history[[length(state$look_history) + 1L]] <- state$last_evaluation
  state$terminal <- passed || look == length(state$contract$look_sizes)
  state$next_look_index <- as.integer(look + 1L)
  mq_scc_seal(state)
}
