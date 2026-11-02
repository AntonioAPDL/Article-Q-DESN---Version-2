# Qualification-only opt-in batched pure-DESN recursion. The scalar adapter,
# response law and scientific streams remain the reference; no fit or launch.

app_iqf_mqb_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste0("MQ batch: ", message), call. = FALSE)
  invisible(TRUE)
}

app_iqf_mqb_integer <- function(x, minimum = 1L) {
  is.numeric(x) && length(x) == 1L && is.finite(x) &&
    x >= minimum && x <= .Machine$integer.max && x == as.integer(x)
}

app_iqf_mqb_activation <- function(name, label) {
  app_iqf_mqb_require(is.character(name) && length(name) == 1L &&
    name %in% c("identity", "tanh", "relu"), paste("unsupported", label))
  fun <- switch(name, identity = function(x) x, tanh = base::tanh,
    relu = function(x) pmax(0, x))
  function(x) matrix(as.numeric(fun(x)), nrow(x), ncol(x))
}

app_iqf_mqb_validate_context <- function(design, snapshot, origin) {
  req <- app_iqf_mqb_require
  req(identical(design$feature_contract, "pure_recursive_v1") &&
    identical(design$design_class, "reservoir"),
    "only the native pure-recursive reservoir-only readout is supported")
  req(app_iqf_mqb_integer(design$response_lags) &&
    design$response_lags < origin$origin_time,
    "invalid pure-recursive response lags")
  sc <- design$dgp_row
  req(is.data.frame(sc) && nrow(sc) == 1L &&
    app_iqf_mqb_integer(sc$simulated_length) && app_iqf_mqb_integer(sc$period) &&
    is.character(sc$dynamics_class) && length(sc$dynamics_class) == 1L &&
    !is.na(sc$dynamics_class), "invalid deterministic pure-recursive feature contract")
  if (sc$dynamics_class == "regime_shift_location_scale")
    req(is.numeric(sc$regime_start_fraction) && length(sc$regime_start_fraction) == 1L &&
      is.finite(sc$regime_start_fraction), "invalid deterministic regime boundary")
  names_raw <- names(app_joint_pure_known_feature_row(origin$origin_time + 1L,
    origin$history, design$response_lags, sc))
  scale <- design$scale_params
  req(is.list(scale) && is.logical(scale$standardize) && length(scale$standardize) == 1L &&
    !is.na(scale$standardize) && identical(names(scale$center), names_raw) &&
    length(scale$scale) == length(names_raw) &&
    all(is.finite(c(scale$center, scale$scale))) && all(scale$scale > 0),
    "input scaling/order differs from the native pure feature map")
  r <- design$reservoir; D <- r$D
  req(app_iqf_mqb_integer(D) && length(r$n) == D &&
    all(is.finite(r$n)) && all(r$n >= 1 & r$n == as.integer(r$n)) &&
    length(r$alpha) == D && all(is.finite(r$alpha)) && all(r$alpha >= 0 & r$alpha <= 1) &&
    is.list(r$W) && length(r$W) == D && is.list(r$Win) && length(r$Win) == D,
    "invalid reservoir dimensions or leak parameters")
  act_f <- app_iqf_mqb_activation(r$act_f %||% "tanh", "state activation")
  act_k <- app_iqf_mqb_activation(r$act_k %||% "identity", "readout activation")
  req(length(snapshot$states[[1L]]) == D, "origin state depth differs")
  for (d in seq_len(D)) {
    req(is.numeric(r$W[[d]]) && is.matrix(r$W[[d]]) &&
      identical(dim(r$W[[d]]), rep(as.integer(r$n[d]), 2L)) &&
      all(is.finite(r$W[[d]])) && is.numeric(r$Win[[d]]) && is.matrix(r$Win[[d]]) &&
      nrow(r$Win[[d]]) == r$n[d] && all(is.finite(r$Win[[d]])) &&
      is.numeric(snapshot$states[[1L]][[d]]) && length(snapshot$states[[1L]][[d]]) == r$n[d] &&
      all(is.finite(snapshot$states[[1L]][[d]])), "invalid native reservoir weights/states")
    if (d == 1L) req(ncol(r$Win[[d]]) == length(names_raw) + 1L,
      "first-layer input dimension differs")
    if (d > 1L) {
      identity_Q <- isTRUE(r$Q_is_identity[[d - 1L]])
      if (identity_Q) req(ncol(r$Win[[d]]) == r$n[d - 1L],
        "identity lower-layer input dimension differs") else {
        Q <- r$Q[[d - 1L]]
        req(is.numeric(Q) && is.matrix(Q) && ncol(Q) == r$n[d - 1L] &&
          nrow(Q) == ncol(r$Win[[d]]) && all(is.finite(Q)),
          "lower-layer projection dimension differs")
      }
    }
  }
  p <- ncol(design$Z)
  state_width <- length(app_qdesn_readout_row_from_states(snapshot$states[[1L]], r))
  req(p == state_width && length(design$state_center) == p &&
    length(design$state_scale) == p && all(is.finite(c(design$state_center, design$state_scale))) &&
    all(design$state_scale > 0) && identical(colnames(design$Z),
      paste0("reservoir_", sprintf("%04d", seq_len(p)))),
    "readout must retain the native ordered reservoir columns only")
  meta <- snapshot$reservoir_meta
  req(is.list(meta) && identical(meta$standardize_inputs, FALSE) &&
    identical(meta$input_bound, "none") && is.null(meta$win_scale_lags) &&
    all(meta$lag_center == 0) && all(meta$lag_scale == 1) &&
    length(meta$win_scale_global) == 1L &&
    length(meta$win_scale_bias) == 1L &&
    all(is.finite(c(meta$win_scale_global, meta$win_scale_bias))) &&
    all(c(meta$win_scale_global, meta$win_scale_bias) > 0),
    "unsupported additional reservoir-input transformation")
  list(D = as.integer(D), p = p, names_raw = names_raw, act_f = act_f, act_k = act_k)
}

# This holds path-specific lag values, not their mean. Known features remain
# deterministic at a horizon; only simulated response lags differ by path.
app_iqf_mqb_raw <- function(tt, responses, origin, design, B) {
  L <- as.integer(design$response_lags); sc <- design$dgp_row
  lagged <- vapply(seq_len(L), function(lag) {
    index <- tt - lag
    if (index <= origin$origin_time) rep(origin$history[index], B) else
      responses[, index - origin$origin_time]
  }, numeric(B))
  lagged <- matrix(lagged, nrow = B, ncol = L)
  angle <- 2 * pi * (tt - 1L) / as.integer(sc$period)
  n <- as.integer(sc$simulated_length)
  trend <- if (n > 1L) -1 + 2 * (tt - 1L) / (n - 1L) else 0
  raw <- cbind(lagged, trend = rep(trend, B), sin_season = rep(sin(angle), B),
    cos_season = rep(cos(angle), B))
  colnames(raw)[seq_len(L)] <- paste0("lag_y_", seq_len(L))
  if (identical(sc$dynamics_class, "regime_shift_location_scale")) {
    start <- max(1L, min(n, floor(sc$regime_start_fraction * n)))
    raw <- cbind(raw, regime = rep(as.numeric(tt > start), B),
      post_regime_trend = rep(if (tt > start) (tt - start) / max(1L, n - start) else 0, B))
  }
  t(raw)
}

app_iqf_mqb_inverse_rows <- function(q, tau, u) {
  B <- nrow(q); K <- length(tau)
  x <- pmax(tau[1L], pmin(tau[K], u))
  k <- findInterval(x, tau, all.inside = TRUE)
  low <- q[cbind(seq_len(B), k)]; high <- q[cbind(seq_len(B), k + 1L)]
  value <- low + (high - low) * ((x - tau[k]) / (tau[k + 1L] - tau[k]))
  left <- which(x <= tau[1L]); right <- which(x >= tau[K])
  if(length(left)) value[left] <- q[cbind(left,1L)]
  if(length(right)) value[right] <- q[cbind(right,K)]
  value
}

# Each tuple still starts from exactly the original six-word scientific seed.
# The native wrapper establishes/restores CMRG once per batch; reassigning its
# same header plus each unchanged seed avoids repeatedly changing RNGkind and
# running administrative set.seed(1). This is not a different RNG or stream.
app_iqf_mqb_rng_reference <- function() list(
  R_version = "4.6.0", source_file = "src/main/RNG.c", source_lines = "145-178",
  RNG_c_sha256 = "6ef2c5d552c087cd57e0ef49386e01e0174b40433e4ad8d572461b20c958450e",
  scope = "first_CMRG_uniform_only_from_original_positive_28bit_purpose_seed_words",
  production_authorized = FALSE)

app_iqf_mqb_rng_proof <- function(proof) {
  ref <- app_iqf_mqb_rng_reference()
  app_iqf_mqb_require(is.list(proof) && identical(proof$R_version, ref$R_version) &&
    identical(as.character(getRversion()), ref$R_version) &&
    identical(proof$RNG_c_sha256, ref$RNG_c_sha256),
    "fast first-step mode requires an explicit matching R4.6 source declaration")
  # This is a declaration check, not file/source/compute admission. The external
  # qualifier must authenticate the actual RNG.c bytes and native comparisons.
  invisible(TRUE)
}

# For these purpose seeds the integer products are below 2^53. The modulo
# results are therefore the exact positive integer remainders of R4.6's
# int_least64_t recurrence. No later state, normal, or multivariate stream is
# implemented or authorized here.
app_iqf_mqb_first_uniform_core <- function(seed_rows) {
  p1 <- (1403580 * seed_rows[, 2L] - 810728 * seed_rows[, 1L]) %% 4294967087
  p2 <- (527612 * seed_rows[, 6L] - 1370589 * seed_rows[, 4L]) %% 4294944443
  (ifelse(p1 > p2, p1 - p2, p1 - p2 + 4294967087)) * 2.328306549295727688e-10
}

app_iqf_mqb_first_uniform <- function(seed_rows, rng_proof) {
  app_iqf_mqb_rng_proof(rng_proof)
  if (is.numeric(seed_rows) && is.null(dim(seed_rows)) && length(seed_rows) == 6L)
    seed_rows <- matrix(seed_rows, 1L, 6L)
  app_iqf_mqb_require(is.numeric(seed_rows) && is.matrix(seed_rows) && nrow(seed_rows) >= 1L &&
    ncol(seed_rows) == 6L && all(is.finite(seed_rows)) &&
    all(seed_rows >= 1 & seed_rows <= 2^28) && all(seed_rows == floor(seed_rows)),
    "first-step recurrence only accepts the native six positive 28-bit purpose words")
  app_iqf_mqb_first_uniform_core(seed_rows)
}

# Byte-identical serialization, names, list order and scalar types to
# app_iqf_seed. Only the six substr/strtoi operations are vectorized.
app_iqf_mqb_fast_seed <- function(rng_namespace, draw_id, origin_id, inner, horizon) {
  key <- list(version = 1L, scientific_identity = as.character(rng_namespace),
    draw = as.character(draw_id), origin = as.character(origin_id),
    inner = as.character(inner), horizon = as.character(horizon), purpose = "response")
  app_iqf_mqb_require(all(lengths(key) == 1L) && !anyNA(unlist(key)) &&
    all(nzchar(unlist(key))) && requireNamespace("digest", quietly = TRUE),
    "invalid purpose-key identity or unavailable digest implementation")
  hex <- digest::digest(key, algo = "sha256", serialize = TRUE, serializeVersion = 2L)
  strtoi(substr(rep.int(hex, 6L), 7L*(0:5)+1L, 7L*(1:6)), 16L) + 1L
}

app_iqf_mqb_fast_uniforms <- function(rng_namespace, draw_id, origin_id, inner_ids, H, rng_proof) {
  app_iqf_mqb_rng_proof(rng_proof)
  app_iqf_mqb_require(app_iqf_mqb_integer(H) && is.numeric(inner_ids) &&
    length(inner_ids) >= 1L && all(is.finite(inner_ids)) &&
    all(inner_ids >= 1 & inner_ids <= .Machine$integer.max) &&
    all(inner_ids == as.integer(inner_ids)), "invalid fast-uniform path/horizon identities")
  # Validate the same scalar fields before the amortized template construction.
  app_iqf_mqb_fast_seed(rng_namespace, draw_id, origin_id, inner_ids[1L], 1L)
  key <- list(version = 1L, scientific_identity = as.character(rng_namespace),
    draw = as.character(draw_id), origin = as.character(origin_id),
    inner = "", horizon = "", purpose = "response")
  out <- matrix(NA_real_, length(inner_ids), H)
  seeds <- matrix(0L, length(inner_ids), 6L)
  starts <- 7L*(0:5)+1L; ends <- 7L*(1:6)
  digest_key <- digest::digest
  for(h in seq_len(H)) {
    key$horizon <- as.character(h)
    for(i in seq_along(inner_ids)) {
      key$inner <- as.character(inner_ids[i])
      hex <- digest_key(key, algo = "sha256", serialize = TRUE, serializeVersion = 2L)
      seeds[i, ] <- strtoi(substr(rep.int(hex, 6L), starts, ends), 16L) + 1L
    }
    out[, h] <- app_iqf_mqb_first_uniform_core(seeds)
  }
  out
}

app_iqf_mqb_uniforms <- function(rng_namespace, draw_id, origin_id, inner_ids, H,
    rng_mode = "native_scoped", rng_proof = NULL) {
  app_iqf_mqb_require(is.character(rng_mode) && length(rng_mode) == 1L &&
    rng_mode %in% c("native_scoped", "r46_first_step_qualified"), "unsupported MQ RNG mode")
  if (rng_mode == "r46_first_step_qualified") return(app_iqf_mqb_fast_uniforms(
    rng_namespace, draw_id, origin_id, inner_ids, H, rng_proof))
  first_seed <- app_iqf_seed(rng_namespace, draw_id, origin_id, inner_ids[1L], 1L, "response")
  app_iqf_rng(first_seed, function() {
    header <- get(".Random.seed", .GlobalEnv, inherits = FALSE)[1L]
    out <- matrix(NA_real_, length(inner_ids), H)
    for (h in seq_len(H)) for (i in seq_along(inner_ids)) {
      seed <- app_iqf_seed(rng_namespace, draw_id, origin_id, inner_ids[i], h, "response")
      assign(".Random.seed", c(header, as.integer(seed)), .GlobalEnv)
      out[i, h] <- stats::runif(1L)
    }
    out
  })
}

app_iqf_mqb_paths_context <- function(context, draw_id, origin_id, inner_ids, include_trace = FALSE) {
  req <- app_iqf_mqb_require
  req(is.character(draw_id) && length(draw_id) == 1L && !is.na(draw_id) &&
    is.character(origin_id) && length(origin_id) == 1L && !is.na(origin_id) &&
    draw_id %in% context$posterior$draw_ids && origin_id %in% names(context$origins),
    "unknown original draw or observed origin")
  req(is.numeric(inner_ids) && length(inner_ids) >= 1L && all(is.finite(inner_ids)) &&
    all(inner_ids >= 1 & inner_ids <= .Machine$integer.max) &&
    all(inner_ids == as.integer(inner_ids)) && !anyDuplicated(inner_ids),
    "distinct positive original inner-path identities required")
  req(is.logical(include_trace) && length(include_trace) == 1L && !is.na(include_trace),
    "invalid trace setting")
  B <- length(inner_ids); design <- context$design; r <- design$reservoir
  origin <- context$origins[[origin_id]]; snapshot <- context$snapshots[[origin_id]]
  v <- context$validated[[origin_id]]; H <- origin$H; K <- length(context$tau)
  j <- match(draw_id, context$posterior$draw_ids)
  beta <- matrix(as.numeric(context$posterior$beta[j, ]), v$p, K)
  alpha <- as.numeric(context$posterior$alpha[j, ])
  states <- lapply(snapshot$states[[1L]], function(s) matrix(rep(s, B), length(s), B))
  response <- matrix(NA_real_, B, H); ordered <- array(NA_real_, c(B, K, H))
  uniforms <- app_iqf_mqb_uniforms(context$rng_namespace, draw_id, origin_id, inner_ids, H,
    context$rng_mode, context$rng_proof)
  trace <- if (include_trace) vector("list", H) else NULL
  for (h in seq_len(H)) {
    raw <- app_iqf_mqb_raw(as.integer(origin$origin_time + h), response, origin, design, B)
    scaled <- if (isTRUE(design$scale_params$standardize))
      sweep(sweep(raw, 1L, as.numeric(design$scale_params$center), "-"),
        1L, as.numeric(design$scale_params$scale), "/") else raw
    U <- rbind(rep(snapshot$reservoir_meta$win_scale_bias, B),
      scaled * snapshot$reservoir_meta$win_scale_global)
    previous <- states; next_states <- states
    pre <- r$W[[1L]] %*% previous[[1L]] + r$Win[[1L]] %*% U
    next_states[[1L]] <- (1 - r$alpha[1L]) * previous[[1L]] + r$alpha[1L] * v$act_f(pre)
    if (v$D > 1L) for (d in 2:v$D) {
      lower <- if (isTRUE(r$Q_is_identity[[d - 1L]])) next_states[[d - 1L]] else
        r$Q[[d - 1L]] %*% next_states[[d - 1L]]
      pre <- r$W[[d]] %*% previous[[d]] + r$Win[[d]] %*% lower
      next_states[[d]] <- (1 - r$alpha[d]) * previous[[d]] + r$alpha[d] * v$act_f(pre)
    }
    states <- next_states
    lower_readout <- if (v$D > 1L) lapply(seq_len(v$D - 1L), function(d) {
      x <- if (isTRUE(r$Q_is_identity[[d]])) states[[d]] else r$Q[[d]] %*% states[[d]]
      v$act_k(x)
    }) else list()
    core <- do.call(rbind, c(list(states[[v$D]]), lower_readout))
    z <- sweep(sweep(core, 1L, design$state_center, "-"), 1L, design$state_scale, "/")
    mu <- sweep(t(crossprod(beta, z)), 2L, alpha, "+")
    crossed <- which(rowSums(mu[, -1L, drop = FALSE] < mu[, -K, drop = FALSE]) > 0L)
    q <- mu
    if (length(crossed)) for (i in crossed) q[i, ] <- app_iqf_grid(mu[i, ], context$tau)$q
    u <- as.numeric(uniforms[, h])
    response[, h] <- app_iqf_mqb_inverse_rows(q, context$tau, u)
    req(all(is.finite(c(raw, z, mu, response[, h]))), "nonfinite batched recursive path")
    ordered[, , h] <- q
    if (include_trace) trace[[h]] <- list(raw = raw, scaled = scaled, states = states,
      readout = z, raw_quantiles = mu, ordered_quantiles = q, uniform = u)
  }
  paths <- lapply(seq_len(B), function(i) list(kernels = lapply(seq_len(H), function(h)
    list(family = "mq_grid", q = as.numeric(ordered[i, , h]), tau = context$tau)),
    response = as.numeric(response[i, ])))
  list(paths = paths, response = response, ordered_quantiles = ordered, trace = trace,
    inner_ids = as.integer(inner_ids), draw_id = draw_id, origin_id = origin_id,
    coupling = context$coupling, rng_namespace = context$rng_namespace,
    outer_conditioning = "parameters_and_observed_origin_reservoir_state",
    production_authorized = FALSE, numerical_accuracy_qualified = FALSE)
}

app_iqf_mq_batch_paths <- function(adapter, draw_id, origin_id, inner_ids, include_trace = FALSE) {
  app_iqf_mqb_require(inherits(adapter, "app_iqf_mq_batch_adapter"), "an explicit MQ batch adapter is required")
  app_iqf_mqb_require(is.numeric(inner_ids) && all(is.finite(inner_ids)) &&
    all(inner_ids <= adapter$inner_paths), "batch path exceeds the declared task resolution")
  app_iqf_mqb_paths_context(adapter$batch_context, draw_id, origin_id, inner_ids, include_trace)
}

# inner_paths is explicit so the compatible scalar $path interface never
# precomputes unrequested paths beyond the task's admitted integration count.
app_iqf_mq_batch_adapter <- function(design, posterior, origins, tau, coupling,
    rng_namespace, inner_paths, batch_size = 64L, rng_mode = "native_scoped", rng_proof = NULL) {
  req <- app_iqf_mqb_require
  req(app_iqf_mqb_integer(inner_paths) && app_iqf_mqb_integer(batch_size),
    "positive integer task resolution and batch size required")
  req(is.character(rng_mode) && length(rng_mode) == 1L &&
    rng_mode %in% c("native_scoped", "r46_first_step_qualified"), "unsupported MQ RNG mode")
  if (rng_mode == "r46_first_step_qualified") app_iqf_mqb_rng_proof(rng_proof)
  req(all(vapply(c("app_iqf_desn_adapter", "app_joint_pure_known_feature_row",
    "app_qdesn_readout_row_from_states"), exists, logical(1L), mode = "function")),
    "authenticated scalar and pure-recursive helpers must be loaded")
  req(identical(design$feature_contract, "pure_recursive_v1") &&
    identical(design$design_class, "reservoir"), "unsupported design; no silent scalar fallback")
  # Reject arbitrary activation callbacks before native origin replay.
  app_iqf_mqb_activation(design$reservoir$act_f %||% "tanh", "state activation")
  app_iqf_mqb_activation(design$reservoir$act_k %||% "identity", "readout activation")
  reference <- app_iqf_desn_adapter(design, posterior, origins, tau, "mq_grid", coupling, rng_namespace)
  native_environment <- environment(reference$path)
  req(exists("snapshots", native_environment, inherits = FALSE),
    "native scalar adapter no longer exposes its validated origin snapshots")
  snapshots <- get("snapshots", native_environment, inherits = FALSE)
  validated <- lapply(names(origins), function(id) app_iqf_mqb_validate_context(design, snapshots[[id]], origins[[id]]))
  names(validated) <- names(origins)
  context <- list(design = design, posterior = posterior, origins = origins,
    tau = tau, coupling = coupling, rng_namespace = rng_namespace,
    rng_mode = rng_mode, rng_proof = rng_proof,
    snapshots = snapshots, validated = validated)
  cache <- new.env(parent = emptyenv())
  cache$key <- NULL; cache$ids <- integer(); cache$paths <- list()
  path <- function(draw_id, origin_id, inner) {
    req(app_iqf_mqb_integer(inner) && inner <= inner_paths,
      "requested path exceeds the explicitly declared task resolution")
    key <- list(draw_id = draw_id, origin_id = origin_id)
    if (!identical(cache$key, key) || !inner %in% cache$ids) {
      first <- ((as.integer(inner) - 1L) %/% as.integer(batch_size)) * as.integer(batch_size) + 1L
      ids <- seq.int(first, min(inner_paths, first + batch_size - 1L))
      batch <- app_iqf_mqb_paths_context(context, draw_id, origin_id, ids)
      cache$key <- key; cache$ids <- ids; cache$paths <- batch$paths
    }
    cache$paths[[match(as.integer(inner), cache$ids)]]
  }
  structure(list(path = path, draw_ids = posterior$draw_ids, origins = origins,
    rng_namespace = rng_namespace, posterior = posterior, adapter = "mq_desn_native_v1",
    outer_conditioning = reference$outer_conditioning, coupling = coupling,
    numerical_adapter = "opt_in_pure_MQ_batch_qualification_v1",
    rng_implementation = if (rng_mode == "native_scoped")
      "original_tuple_CMRG_states_one_scoped_wrapper_per_batch" else
      "exact_R46_first_CMRG_step_original_28bit_purpose_keys",
    rng_mode = rng_mode, rng_reference = if(rng_mode == "native_scoped") NULL else app_iqf_mqb_rng_reference(),
    rng_source_binding_authenticated = FALSE,
    batch_context = context, inner_paths = as.integer(inner_paths), batch_size = as.integer(batch_size),
    numerical_backend_qualification_required = TRUE,
    production_authorized = FALSE, numerical_accuracy_qualified = FALSE),
    class = c("app_iqf_mq_batch_adapter", "app_iqf_adapter"))
}
