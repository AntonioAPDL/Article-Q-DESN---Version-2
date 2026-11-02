# Compact, independently checked numerical evidence for future MQ reconstruction.
# This is a distinct method, never a relabelled DKW or particle-filter bound.
# Source/stream authentication and production admission remain external gates.
iqr2_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste0("IQF_RECEIPT_V2: ", message), call. = FALSE)
}
iqr2_hash <- function(value) {
  iqr2_require(requireNamespace("digest", quietly = TRUE), "digest is required")
  digest::digest(value, algo = "sha256", serialize = TRUE, serializeVersion = 2L)
}
iqr2_identity <- function(identity) {
  sizes <- c(source_commit = 40L, source_tree = 40L,
    source_manifest_sha256 = 64L, posterior_target_sha256 = 64L,
    input_manifest_sha256 = 64L, task_manifest_sha256 = 64L)
  iqr2_require(is.list(identity) && all(names(sizes) %in% names(identity)),
    "complete immutable producer identity required")
  for (key in names(sizes)) iqr2_require(is.character(identity[[key]]) &&
    length(identity[[key]]) == 1L && !is.na(identity[[key]]) &&
    grepl(paste0("^[a-f0-9]{", sizes[[key]], "}$"), identity[[key]]),
    paste("invalid source/target/input identity", key))
  for (key in c("task_id", "rng_namespace")) iqr2_require(
    is.character(identity[[key]]) && length(identity[[key]]) == 1L &&
    !is.na(identity[[key]]) && nzchar(identity[[key]]),
    paste("missing scientific producer identity", key))
  invisible(TRUE)
}

# The original fixed-look contract remains unmodified. A smaller synthetic
# example can use a shorter quantile grid, not weaker probability/error gates.
iqr2_policy <- function(contract) {
  iqr2_require(is.list(contract) &&
    identical(contract$schema_version, "mq_streaming_cdf_certificate_contract_v1") &&
    identical(contract$method, "heldout_conditional_CDF_empirical_Bernstein_alpha_spending") &&
    identical(contract$conditioning, "one_fixed_original_parameter_draw_and_observed_origin") &&
    identical(contract$validation_values, "iid_future_path_conditional_CDF_not_particle_filter") &&
    identical(contract$candidates_from_training_paths_only, TRUE),
    "unsupported numerical method or conditioning")
  equal <- function(x, y) is.numeric(x) && length(x) == length(y) &&
    all(is.finite(x)) && all(x == y)
  iqr2_require(equal(contract$training_path_range, c(1, 65536)) &&
    equal(contract$validation_path_range, c(65537, 327680)) &&
    equal(contract$look_sizes, c(65536, 131072, 262144)) &&
    equal(contract$total_alpha, .05) &&
    equal(contract$absolute_quantile_tolerance, .01) &&
    equal(contract$relative_quantile_tolerance, .01),
    "frozen ranges, looks and quantile precision cannot change")
  a <- contract$alpha_per_look
  iqr2_require(is.numeric(a) && length(a) == 3L && all(is.finite(a)) &&
    all(abs(a - .05/3) <= 1e-16) && sum(a) <= .05 + 1e-16,
    "fixed-look alpha spending changed")
  for (flag in c("source_identity_authenticated", "independent_stream_generation_authenticated",
    "particle_filter_accuracy_certified", "origin_filter_accuracy_certified", "production_authorized"))
    iqr2_require(is.null(contract[[flag]]) || identical(contract[[flag]], FALSE),
      paste("a numerical contract cannot declare", flag))
  invisible(TRUE)
}

iqr2_geometry <- function(candidates) {
  iqr2_require(is.data.frame(candidates) &&
    identical(names(candidates), c("horizon", "probability", "quantile")) &&
    nrow(candidates) > 0L && all(vapply(candidates, is.numeric, logical(1L))) &&
    all(is.finite(as.matrix(candidates))), "finite keyed quantile candidates required")
  H <- max(candidates$horizon); p <- sort(unique(candidates$probability))
  iqr2_require(H >= 1L && H <= 30L && H == as.integer(H) &&
    min(p) > 0 && max(p) < 1 && nrow(candidates) == H * length(p) &&
    identical(as.numeric(candidates$horizon), as.numeric(rep(seq_len(H), each=length(p)))) &&
    identical(as.numeric(candidates$probability), rep(p, H)),
    "complete ordered horizon/probability geometry required")
  for (h in seq_len(H)) iqr2_require(
    all(diff(candidates$quantile[candidates$horizon == h]) >= 0),
    "ordered conditional-distribution quantiles required")
  delta <- pmax(.01, .01*abs(candidates$quantile))
  ends <- as.vector(rbind(candidates$quantile-delta, candidates$quantile+delta))
  iqr2_require(all(is.finite(ends)) && all(delta > 0), "unresolved endpoints")
  list(delta=delta, endpoints=ends, M=length(ends))
}
iqr2_candidate_hash <- function(candidates) {
  # Data-frame attribute order may change on column extraction even when
  # identical() is TRUE. Hash the explicit ordered numerical geometry.
  iqr2_geometry(candidates)
  iqr2_hash(list(horizon=as.integer(candidates$horizon),
    probability=as.double(candidates$probability), quantile=as.double(candidates$quantile)))
}

# Recompute endpoint locations, variance, radius and inequalities. No producer
# PASS/status/boolean participates in this decision. These are bounds for
# future iid paths conditional on a fixed parameter/origin, not PF accuracy.
iqr2_validate <- function(receipt, candidates, identity) {
  iqr2_identity(identity)
  iqr2_require(is.list(receipt) &&
    identical(receipt$schema_version, "integrated_quantile_compact_receipt_v2") &&
    identical(receipt$method, "mq_heldout_conditional_cdf_streaming_v1") &&
    identical(receipt$identity, identity),
    "receipt method or exact producer identity changed")
  original <- receipt$integrity_sha256; copy <- receipt; copy$integrity_sha256 <- NULL
  iqr2_require(is.character(original) && length(original) == 1L &&
    identical(original, iqr2_hash(copy)), "receipt integrity changed")
  iqr2_require(identical(receipt$candidates_sha256, iqr2_candidate_hash(candidates)),
    "candidate quantiles changed")
  contract <- receipt$stream_contract
  iqr2_policy(contract); geometry <- iqr2_geometry(candidates)
  for (key in c("draw_id", "origin_id", "rng_namespace")) iqr2_require(
    is.character(receipt[[key]]) && length(receipt[[key]]) == 1L &&
    !is.na(receipt[[key]]) && nzchar(receipt[[key]]) &&
    identical(receipt[[key]], contract[[key]]), paste("stream identity changed", key))
  iqr2_require(identical(receipt$rng_namespace, identity$rng_namespace),
    "stream namespace differs from producer")
  L <- receipt$look_index
  iqr2_require(is.numeric(L) && length(L) == 1L && is.finite(L) &&
    L %in% 1:3 && receipt$validation_count == contract$look_sizes[L],
    "unlisted look or incomplete validation prefix")
  n <- receipt$validation_count
  iqr2_require(is.numeric(n) && length(n) == 1L && is.finite(n) &&
    receipt$validation_first_path_id == 65537 &&
    receipt$validation_last_path_id == 65536+n &&
    receipt$validation_last_path_id <= 327680,
    "overlapping or noncontiguous validation path range")
  mean <- receipt$cdf_mean; M2 <- receipt$cdf_M2
  iqr2_require(is.numeric(mean) && is.numeric(M2) &&
    length(mean) == geometry$M && length(M2) == geometry$M &&
    all(is.finite(c(mean, M2))) && all(mean >= 0 & mean <= 1) &&
    all(M2 >= 0 & M2 <= n*mean*(1-mean) + 1e-8),
    "invalid bounded-CDF sufficient statistics")
  for (h in unique(candidates$horizon)) {
    j <- as.vector(rbind(2L*which(candidates$horizon == h)-1L,
      2L*which(candidates$horizon == h)))
    j <- j[order(geometry$endpoints[j])]
    iqr2_require(all(diff(mean[j]) >= -1e-12), "CDF means are not monotone")
    ties <- which(diff(geometry$endpoints[j]) == 0)
    if (length(ties)) iqr2_require(
      all(mean[j[ties]] == mean[j[ties+1L]]) &&
      all(M2[j[ties]] == M2[j[ties+1L]]), "equal endpoints have different moments")
  }
  split <- contract$training_split_diagnostic
  columns <- c("horizon", "probability", "split_stream_absolute_difference",
    "split_stream_relative_difference")
  iqr2_require(is.data.frame(split) && all(columns %in% names(split)) &&
    nrow(split) == nrow(candidates) &&
    identical(as.numeric(split$horizon), as.numeric(candidates$horizon)) &&
    identical(as.numeric(split$probability), as.numeric(candidates$probability)),
    "training split geometry changed")
  a <- split$split_stream_absolute_difference
  r <- split$split_stream_relative_difference
  iqr2_require(is.numeric(a) && is.numeric(r) && all(is.finite(a)) &&
    all(a >= 0) && !anyNA(r) && all(r >= 0) &&
    all(a <= .005 | r <= .005), "training split gate did not pass")
  chain <- receipt$validation_chain_sha256
  iqr2_require(is.character(chain) && length(chain) == 1L && !is.na(chain) &&
    grepl("^[a-f0-9]{64}$", chain), "missing validation replay-chain identity")
  variance <- M2/(n-1)
  log_factor <- log(4*geometry$M/contract$alpha_per_look[L])
  radius <- sqrt(2*variance*log_factor/n) + 7*log_factor/(3*(n-1))
  low <- seq.int(1L, geometry$M, 2L); high <- low+1L
  UCB <- pmin(1, mean+radius); LCB <- pmax(0, mean-radius)
  iqr2_require(all(UCB[low] < candidates$probability &
    LCB[high] >= candidates$probability), "independent future-CDF bound did not pass")
  invisible(list(status="VALIDATED_COMPACT_MQ_FUTURE_CDF_BOUND",
    radius=radius, quantile_error=geometry$delta,
    alpha=contract$total_alpha, look_index=L,
    confidence_scope="one_fixed_draw_origin_not_campaign_familywise",
    source_authentication_provided=FALSE, production_authorized=FALSE))
}

# Compact final sufficient statistics replace duplicated qualification arrays.
# The original, full qualification packet is retained separately. Original
# block/data hashes enter the final chain, enabling source-bound RNG replay;
# raw validation matrices are NOT claimed to have been retained here.
iqr2_from_stream_state <- function(state, identity) {
  iqr2_require(exists("mq_scc_check_state", mode="function"),
    "load the unchanged streaming-certificate module")
  mq_scc_check_state(state); iqr2_identity(identity)
  iqr2_require(isTRUE(state$terminal) && is.list(state$last_evaluation) &&
    isTRUE(state$last_evaluation$all_required_gates_pass),
    "only a completed eligible stream may be compacted")
  out <- list(schema_version="integrated_quantile_compact_receipt_v2",
    method="mq_heldout_conditional_cdf_streaming_v1", identity=identity,
    candidates_sha256=iqr2_candidate_hash(state$candidates),
    stream_contract=state$contract,
    draw_id=state$contract$draw_id, origin_id=state$contract$origin_id,
    rng_namespace=state$contract$rng_namespace,
    look_index=state$last_evaluation$look_index,
    validation_count=state$count, validation_first_path_id=65537L,
    validation_last_path_id=65536+state$count,
    cdf_mean=as.numeric(state$mean), cdf_M2=as.numeric(state$M2),
    validation_chain_sha256=state$last_chain_sha256,
    retention="final_Welford_moments_and_chain_root_source_bound_replay_not_raw_validation_matrix")
  out$integrity_sha256 <- iqr2_hash(out)
  iqr2_validate(out, state$candidates, identity)
  out
}

iqr2_validate_shard <- function(shard) {
  iqr2_require(is.list(shard) &&
    identical(shard$schema_version, "integrated_quantile_forecast_shard_v2") &&
    identical(shard$forecast_functional, "parameter_conditional_integrated_quantile") &&
    identical(shard$outer_conditioning, "parameters_and_observed_origin_reservoir_state") &&
    is.character(shard$model_id) && length(shard$model_id) == 1L &&
    !is.na(shard$model_id) && nzchar(shard$model_id) &&
    is.data.frame(shard$quantiles) && all(c("model_id", "draw_id", "origin_id", "horizon",
      "probability", "quantile", "functional", "outer_conditioning", "rng_namespace") %in% names(shard$quantiles)),
    "unsupported shard, functional or uncertainty conditioning")
  candidates <- shard$quantiles[c("horizon", "probability", "quantile")]
  iqr2_require(identical(shard$draw_id, shard$numerical_receipt$draw_id) &&
    identical(shard$origin_id, shard$numerical_receipt$origin_id) &&
    all(shard$quantiles$draw_id == shard$draw_id) &&
    all(shard$quantiles$origin_id == shard$origin_id) &&
    !anyNA(shard$quantiles$draw_id) && !anyNA(shard$quantiles$origin_id) &&
    all(shard$quantiles$model_id == shard$model_id) &&
    all(shard$quantiles$functional == shard$forecast_functional) &&
    all(shard$quantiles$outer_conditioning == shard$outer_conditioning) &&
    identical(shard$identity$outer_conditioning, shard$outer_conditioning) &&
    all(shard$quantiles$rng_namespace == shard$identity$rng_namespace),
    "member identities differ from their numerical receipt")
  iqr2_validate(shard$numerical_receipt, candidates, shard$identity)
}

# A v2 container cannot be interpreted by the legacy DKW codec. Validate before
# packing AND after unpacking, retaining complete source/draw/origin identity.
iqr2_member_key <- function(draw_id, origin_id) {
  valid <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
  iqr2_require(valid(draw_id) && valid(origin_id), "explicit member identity required")
  paste0("draw-origin:", iqr2_hash(list(draw_id=draw_id, origin_id=origin_id)))
}
iqr2_common_members <- function(shards) {
  first <- shards[[1L]]
  iqr2_require(all(vapply(shards, function(x) identical(x$identity, first$identity) &&
    identical(x$model_id, first$model_id) &&
    identical(x$quantiles[c("horizon", "probability")],
      first$quantiles[c("horizon", "probability")]), logical(1L))),
    "one block cannot mix sources, targets, models or numerical geometry")
  invisible(TRUE)
}
iqr2_pack <- function(shards) {
  iqr2_require(is.list(shards) && length(shards) >= 1L && length(shards) <= 1000L,
    "a block contains 1-1000 complete members")
  invisible(lapply(shards, iqr2_validate_shard))
  iqr2_common_members(shards)
  keys <- vapply(shards, function(x) iqr2_member_key(x$draw_id,x$origin_id), "")
  iqr2_require(!anyDuplicated(keys), "duplicate member in block")
  out <- list(schema_version="integrated_quantile_forecast_block_v2",
    member_keys=keys, members=shards,
    storage_interpretation="lossless_v2_reference_codec_no_thinning_no_averaging")
  out$integrity_sha256 <- iqr2_hash(out)
  out
}
iqr2_unpack <- function(block, index) {
  iqr2_require(is.list(block) &&
    identical(block$schema_version, "integrated_quantile_forecast_block_v2"),
    "unsupported typed block")
  copy <- block; seal <- copy$integrity_sha256; copy$integrity_sha256 <- NULL
  iqr2_require(identical(seal, iqr2_hash(copy)), "block integrity changed")
  iqr2_require(is.numeric(index) && length(index) == 1L && is.finite(index) &&
    index == as.integer(index) && index >= 1 && index <= length(block$members) &&
    length(block$member_keys) == length(block$members) &&
    length(block$members) >= 1L && length(block$members) <= 1000L &&
    !anyDuplicated(block$member_keys), "invalid block member index")
  iqr2_common_members(block$members)
  iqr2_require(identical(unname(block$member_keys), unname(vapply(block$members,
    function(x) iqr2_member_key(x$draw_id,x$origin_id), ""))),
    "block contains a relabelled member key")
  shard <- block$members[[index]]
  iqr2_require(identical(block$member_keys[index],
    iqr2_member_key(shard$draw_id,shard$origin_id)),
    "block member key changed")
  iqr2_validate_shard(shard)
  shard
}
