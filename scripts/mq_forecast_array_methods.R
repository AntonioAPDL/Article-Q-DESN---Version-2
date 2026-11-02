# Explicit opt-in numerical helpers. No fitting, source authentication,
# scientific stream generation or production authority is supplied here.
app_iqf_mqa_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste0("MQ array methods: ", message), call. = FALSE)
  invisible(TRUE)
}

# The common-grid branch of the native event sweep, without allocating a
# per-path R kernel list. Exceptional numerical cases retain the exact native
# checked bisection; they do not change atoms, projection or the response law.
app_iqf_mq_matrix_inverse <- function(q, tau, probabilities, tolerance = 1e-8) {
  req <- app_iqf_mqa_require
  req(all(vapply(c("app_iqf_grid", "app_iqf_mq_matrix_cdf", "app_iqf_invert_cdf_bisection"),
    exists, logical(1L), mode = "function")), "load the authenticated native grid helpers first")
  req(is.matrix(q) && is.numeric(q) && nrow(q) >= 1L && ncol(q) >= 2L &&
    all(is.finite(q)) && is.numeric(tau) && length(tau) == ncol(q) &&
    is.numeric(probabilities) && length(probabilities) >= 1L && all(is.finite(probabilities)) &&
    all(probabilities > 0 & probabilities < 1) && is.numeric(tolerance) &&
    length(tolerance) == 1L && is.finite(tolerance) && tolerance > 0,
    "finite common-grid matrix, interior probabilities and positive inversion tolerance required")
  app_iqf_grid(rep(0, ncol(q)), tau)
  L <- nrow(q); K <- ncol(q); tau <- as.numeric(tau); original_q <- q
  crossed <- which(rowSums(q[, -1L, drop = FALSE] < q[, -K, drop = FALSE]) > 0L)
  for (i in crossed) q[i, ] <- stats::isoreg(seq_len(K), q[i, ])$yf
  fallback <- function() {
    # The reference bisection also uses unprojected endpoints for its initial
    # bracket. Preserve those bytes, not merely the same projected CDF.
    kernels <- lapply(seq_len(L), function(i) list(family = "mq_grid", q = as.numeric(original_q[i, ]), tau = tau))
    app_iqf_invert_cdf_bisection(kernels, probabilities, tolerance)
  }
  width <- q[, -1L, drop = FALSE] - q[, -K, drop = FALSE]
  mass <- matrix(rep(diff(tau), each = L), nrow = L)
  positive <- width > 0
  density <- matrix(0, nrow = L, ncol = K - 1L)
  density[positive] <- mass[positive] / width[positive]
  events <- cbind(position = c(q[, 1L], q[, K], q[, -K, drop = FALSE], q[, -1L, drop = FALSE]),
    slope_change = c(rep(0, 2L * L), density, -density) / L,
    atom = c(rep(tau[1L], L), rep(1 - tau[K], L),
      ifelse(positive, 0, mass), rep(0, length(mass))) / L)
  if (any(!is.finite(events))) return(fallback())
  knots <- sort(unique(events[, "position"]))
  grouped <- rowsum(events[, c("slope_change", "atom"), drop = FALSE],
    match(events[, "position"], knots), reorder = TRUE)
  slope <- cumsum(grouped[, "slope_change"])
  interval_mass <- if (length(knots) > 1L) head(slope, -1L) * diff(knots) else numeric()
  if (any(!is.finite(interval_mass)) || any(interval_mass < -1e-12)) return(fallback())
  interval_mass <- pmax(0, interval_mass)
  right <- cumsum(grouped[, "atom"] + c(0, interval_mass))
  left <- right - grouped[, "atom"]
  if (any(!is.finite(c(left, right))) || any(left < -1e-10) ||
      any(right > 1 + 1e-10) || abs(tail(right, 1L) - 1) > 1e-10 ||
      any(diff(right) < -1e-12)) return(fallback())
  right <- pmin(1, pmax(0, right)); right[length(right)] <- 1
  answer <- vapply(probabilities, function(p) {
    j <- which(right >= p)[1L]
    if (is.na(j)) return(NA_real_)
    if (j == 1L || p > left[j]) return(knots[j])
    if (!is.finite(slope[j - 1L]) || slope[j - 1L] <= 0) return(NA_real_)
    value <- knots[j - 1L] + (p - right[j - 1L]) / slope[j - 1L]
    max(knots[j - 1L], min(knots[j], value))
  }, numeric(1L))
  if (any(!is.finite(answer))) return(fallback())
  probe <- app_iqf_mq_matrix_cdf(c(answer - tolerance, answer + tolerance), q, tau)
  n <- length(answer)
  if (any(!is.finite(probe)) || any(probe[seq_len(n)] >= probabilities) ||
      any(probe[n + seq_len(n)] < probabilities)) return(fallback())
  answer
}

app_iqf_mqc_ranges <- function(ids) {
  req <- app_iqf_mqa_require
  req(is.numeric(ids) && length(ids) >= 1L && all(is.finite(ids)) &&
    all(ids >= 1 & ids <= .Machine$integer.max & ids == floor(ids)) && !anyDuplicated(ids),
    "distinct positive scientific inner-path IDs required")
  ids <- sort(as.integer(ids)); start <- c(TRUE, diff(ids) != 1L)
  data.frame(first = ids[start], last = ids[c(tail(which(start), -1L) - 1L, length(ids))])
}

app_iqf_mqc_init <- function(H, tau, inner_ids, draw_id, origin_id, rng_namespace, tolerance = 0) {
  req <- app_iqf_mqa_require
  req(is.numeric(H) && length(H) == 1L && is.finite(H) && H >= 1L && H == as.integer(H) &&
    is.numeric(tau) && length(tau) >= 2L && all(is.finite(tau)) && all(diff(tau) > 0) &&
    min(tau) > 0 && max(tau) < 1 && is.numeric(tolerance) && length(tolerance) == 1L &&
    is.finite(tolerance) && tolerance >= 0, "finite coherence geometry/tolerance required")
  for (x in list(draw_id, origin_id, rng_namespace)) req(is.character(x) && length(x) == 1L &&
    !is.na(x) && nzchar(x), "original draw/origin/RNG identity required")
  ranges <- app_iqf_mqc_ranges(inner_ids); H <- as.integer(H); K <- length(tau)
  pair <- matrix(0, H, K - 1L); level <- matrix(0, H, K)
  list(schema_version = "mq_raw_kernel_coherence_v1",
    definition = "raw_adjacent_readout_before_equal_weight_isotonic_projection",
    scale = "native_response_readout", tolerance = tolerance,
    draw_id = draw_id, origin_id = origin_id, rng_namespace = rng_namespace,
    tau = as.numeric(tau), horizons = H, path_count = as.double(length(inner_ids)),
    path_ranges = ranges, updated_horizons = rep(FALSE, H),
    crossing_count = pair, exposure_count = pair, positive_gap_sum = pair,
    maximum_positive_gap = pair, adjustment_absolute_sum = level,
    adjustment_squared_sum = level, maximum_absolute_adjustment = level,
    production_authorized = FALSE, source_identity_authenticated = FALSE)
}

app_iqf_mqc_update <- function(state, raw, ordered, horizon) {
  req <- app_iqf_mqa_require
  req(is.list(state) && identical(state$schema_version, "mq_raw_kernel_coherence_v1") &&
    is.numeric(horizon) && length(horizon) == 1L && is.finite(horizon) &&
    horizon == as.integer(horizon) && horizon >= 1L && horizon <= state$horizons &&
    !state$updated_horizons[horizon], "a previously unprocessed valid coherence horizon required")
  K <- length(state$tau); B <- state$path_count
  req(is.matrix(raw) && is.matrix(ordered) && is.numeric(raw) && is.numeric(ordered) &&
    identical(dim(raw), c(as.integer(B), as.integer(K))) && identical(dim(raw), dim(ordered)) &&
    all(is.finite(raw)) && all(is.finite(ordered)) &&
    all(ordered[, -1L, drop = FALSE] >= ordered[, -K, drop = FALSE]),
    "finite complete raw and already projected grids required")
  gap <- raw[, -K, drop = FALSE] - raw[, -1L, drop = FALSE]
  positive <- pmax(gap, 0); adjustment <- ordered - raw
  req(all(is.finite(c(positive, adjustment, adjustment^2))), "coherence magnitude overflow")
  state$crossing_count[horizon, ] <- colSums(gap > state$tolerance)
  state$exposure_count[horizon, ] <- B
  state$positive_gap_sum[horizon, ] <- colSums(positive)
  state$maximum_positive_gap[horizon, ] <- apply(positive, 2L, max)
  state$adjustment_absolute_sum[horizon, ] <- colSums(abs(adjustment))
  state$adjustment_squared_sum[horizon, ] <- colSums(adjustment^2)
  state$maximum_absolute_adjustment[horizon, ] <- apply(abs(adjustment), 2L, max)
  state$updated_horizons[horizon] <- TRUE
  state
}

app_iqf_mqc_validate <- function(state) {
  req <- app_iqf_mqa_require
  req(is.list(state) && identical(state$schema_version, "mq_raw_kernel_coherence_v1") &&
    identical(state$definition, "raw_adjacent_readout_before_equal_weight_isotonic_projection") &&
    identical(state$scale, "native_response_readout") &&
    identical(state$production_authorized, FALSE) && identical(state$source_identity_authenticated, FALSE) &&
    is.numeric(state$tolerance) && length(state$tolerance) == 1L && is.finite(state$tolerance) &&
    state$tolerance >= 0 && is.numeric(state$path_count) && length(state$path_count) == 1L &&
    is.finite(state$path_count) && state$path_count >= 1 && state$path_count == floor(state$path_count) &&
    state$path_count <= .Machine$integer.max, "complete non-authorizing coherence state required")
  H <- state$horizons; tau <- state$tau; K <- length(tau)
  req(is.numeric(H) && length(H) == 1L && is.finite(H) && H >= 1 && H == as.integer(H) &&
    is.numeric(tau) && K >= 2 && all(is.finite(tau)) && all(diff(tau) > 0) &&
    min(tau) > 0 && max(tau) < 1 && is.logical(state$updated_horizons) &&
    length(state$updated_horizons) == H && all(state$updated_horizons), "all coherence horizons required")
  for (name in c("draw_id", "origin_id", "rng_namespace")) req(is.character(state[[name]]) &&
    length(state[[name]]) == 1L && !is.na(state[[name]]) && nzchar(state[[name]]), "coherence identity missing")
  r <- state$path_ranges
  req(is.data.frame(r) && identical(names(r), c("first", "last")) && nrow(r) >= 1L &&
    all(vapply(r, is.numeric, logical(1L))) && all(is.finite(as.matrix(r))) &&
    all(r$first >= 1 & r$last >= r$first & r$last <= .Machine$integer.max &
      r$first == floor(r$first) & r$last == floor(r$last)) &&
    (nrow(r) == 1L || all(r$first[-1L] > r$last[-nrow(r)])) &&
    sum(as.double(r$last) - r$first + 1) == state$path_count, "coherence path ranges changed")
  pair <- c("crossing_count", "exposure_count", "positive_gap_sum", "maximum_positive_gap")
  level <- c("adjustment_absolute_sum", "adjustment_squared_sum", "maximum_absolute_adjustment")
  for (name in c(pair, level)) req(is.matrix(state[[name]]) && is.numeric(state[[name]]) &&
    identical(dim(state[[name]]), c(as.integer(H), as.integer(if (name %in% pair) K - 1L else K))) &&
    all(is.finite(state[[name]])) && all(state[[name]] >= 0), "invalid compact coherence matrix")
  req(all(state$exposure_count == state$path_count) &&
    all(state$crossing_count == floor(state$crossing_count)) &&
    all(state$crossing_count <= state$exposure_count) &&
    all(state$maximum_positive_gap <= state$positive_gap_sum + 1e-12) &&
    all(state$maximum_absolute_adjustment <= state$adjustment_absolute_sum + 1e-12),
    "invalid coherence counts, exposures or magnitude sums")
  invisible(TRUE)
}

mq_coherence_merge <- function(states) {
  req <- app_iqf_mqa_require
  req(is.list(states) && length(states) >= 1L, "nonempty coherence batches required")
  invisible(lapply(states, app_iqf_mqc_validate))
  fixed <- c("schema_version", "definition", "scale", "tolerance", "draw_id", "origin_id",
    "rng_namespace", "tau", "horizons", "updated_horizons", "production_authorized", "source_identity_authenticated")
  req(all(vapply(states, function(s) identical(s[fixed], states[[1L]][fixed]), logical(1L))),
    "only one original draw/origin/response scale and coherence definition may be merged")
  states <- states[order(vapply(states, function(s) s$path_ranges$first[1L], numeric(1L)))]
  ranges <- do.call(rbind, lapply(states, `[[`, "path_ranges")); ranges <- ranges[order(ranges$first), , drop = FALSE]
  rownames(ranges) <- NULL
  req(nrow(ranges) == 1L || all(ranges$first[-1L] > ranges$last[-nrow(ranges)]),
    "duplicate or overlapping scientific paths in coherence merge")
  # Coalesce adjacent ranges without expanding all inner IDs.
  starts <- c(TRUE, ranges$first[-1L] != ranges$last[-nrow(ranges)] + 1)
  groups <- cumsum(starts)
  out <- states[[1L]]
  out$path_ranges <- data.frame(first = as.integer(tapply(ranges$first, groups, min)),
    last = as.integer(tapply(ranges$last, groups, max)))
  out$path_count <- sum(vapply(states, `[[`, numeric(1L), "path_count"))
  for (name in c("crossing_count", "exposure_count", "positive_gap_sum", "adjustment_absolute_sum", "adjustment_squared_sum"))
    out[[name]] <- Reduce(`+`, lapply(states, `[[`, name))
  for (name in c("maximum_positive_gap", "maximum_absolute_adjustment"))
    out[[name]] <- Reduce(pmax, lapply(states, `[[`, name))
  app_iqf_mqc_validate(out)
  out
}

mq_coherence_weighted_summary <- function(states, weights) {
  req <- app_iqf_mqa_require
  req(is.list(states) && length(states) >= 1L && is.numeric(weights) &&
    length(weights) == length(states) && all(is.finite(weights)) && all(weights > 0) &&
    abs(sum(weights) - 1) <= 1e-12, "explicit positive normalized outer member weights required")
  invisible(lapply(states, app_iqf_mqc_validate))
  fixed <- c("schema_version", "definition", "scale", "tolerance", "tau", "horizons")
  req(all(vapply(states, function(s) identical(s[fixed], states[[1L]][fixed]), logical(1L))),
    "weighted summaries require the same horizon/probability geometry and definition")
  req(exists("app_iqf_hash", mode = "function"), "native identity hashing helper required")
  identities <- lapply(states, function(s) s[c("rng_namespace", "draw_id", "origin_id")])
  ids <- vapply(identities, app_iqf_hash, "")
  req(!anyDuplicated(ids), "merge disjoint batches within each original member before outer weighting")
  weighted <- function(name, level = FALSE) Reduce(`+`, lapply(seq_along(states), function(i)
    weights[i] * states[[i]][[name]] / if (level) states[[i]]$path_count else states[[i]]$exposure_count))
  rate <- weighted("crossing_count")
  list(schema_version = "mq_weighted_raw_coherence_summary_v1", definition = states[[1L]]$definition,
    scale = states[[1L]]$scale, tolerance = states[[1L]]$tolerance,
    tau = states[[1L]]$tau, horizons = states[[1L]]$horizons,
    member_ids = ids, member_identity = identities, member_weights = weights, members = length(states),
    member_path_counts = vapply(states, `[[`, numeric(1L), "path_count"),
    weighted_adjacent_crossing_rate = rate, overall_weighted_crossing_rate = mean(rate),
    weighted_positive_gap = weighted("positive_gap_sum"),
    weighted_absolute_adjustment = weighted("adjustment_absolute_sum", TRUE),
    weighted_squared_adjustment = weighted("adjustment_squared_sum", TRUE),
    interpretation = "average_each_member_path_rate_then_apply_explicit_outer_weights_not_pooled_inner_counts",
    production_authorized = FALSE, source_identity_authenticated = FALSE)
}
