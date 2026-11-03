# Explicit generated-only composition; canonical functions/defaults are unchanged.
mqc_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("MQ composed candidate: ", why), call. = FALSE)
  invisible(TRUE)
}
mqc_scope <- function(scope) mqc_require(identical(scope, "generated_fixture_only"),
  "source/ABI/runtime qualification and production execution remain unapproved")
mqc_source_pins <- function() c(
  "scripts/integrated_quantile_mq_batch.R" = "c3b6df5c2ef4f5d93eac124cfcc1c3aa9236be6c52713dcfb9938490bc6ab643",
  "scripts/mq_forecast_array_methods.R" = "76f585ff0daf4bbbaab9445d72b69a309783a097e8db2dec1a49a38021f48546",
  "application/R/integrated_quantile_forecast.R" = "0ee9df28badb06792f474739555d6ccb866de1f2d85703cbf1a22bc9ef88e0d3",
  "scripts/mq_native_key_hash.R" = "a3cd5e47be08573fcf031fd2e011279a2b1505bc05c4f8e60a0192d69be8da16",
  "scripts/native/mq_key_hash.c" = "569a8c260d0d197464b7c2e8db7e6e6cf3be7c267c932d0e28a0c3b8cce6a26d",
  "scripts/mq_isoreg_batch.R" = "f67c69dc1d633e5dea910762a636726f73805ecf6f2b89fa8e6929f60104a665",
  "scripts/native/mq_isoreg_batch.c" = "68e9f671a4384c9370b7249ed333b54e426fb2d6f20cb2d7a10acbbaa00eac28",
  "scripts/mq_native_event_inverse.R" = "a117b04ec6809563164f23e5bd0bdc159bee271048a797c8e03d4e9c6a541ef4",
  "scripts/native/mq_event_inverse.c" = "81e9fe158874deaf3aafd70f0e49b4266a5f3021b104239d6509869d71164f52")
mqc_reference_expression <- function() {
  pins <- mqc_source_pins()
  mqc_require(identical(unname(tools::sha256sum(names(pins))), unname(pins)),
    "frozen reference/candidate source bytes changed")
  ast <- parse(file = names(pins)[1L], keep.source = FALSE)
  at <- which(vapply(ast, function(x) is.call(x) && identical(x[[1L]], as.name("<-")) &&
    identical(x[[2L]], as.name("app_iqf_mqb_paths_context")), logical(1L)))
  mqc_require(length(at) == 1L, "one canonical context definition required")
  ast[[at]][[3L]]
}
mqc_language_equal <- function(a, b) identical(deparse(a, width.cutoff = 500L),
  deparse(b, width.cutoff = 500L))
mqc_body_check <- function(reference = app_iqf_mqb_paths_context, variant = mqc_paths_context) {
  expr <- mqc_reference_expression()
  mqc_require(mqc_language_equal(formals(reference), expr[[2L]]) &&
    mqc_language_equal(body(reference), expr[[3L]]), "canonical function body/formals changed")
  vf <- formals(variant)
  mqc_require(identical(names(vf), c(names(formals(reference)), "candidate", "scope")) &&
    identical(vf$scope, "NOT_ADMITTED"), "explicit candidate/scope formals changed")
  vf <- as.pairlist(vf[setdiff(names(vf), c("candidate", "scope"))])
  mqc_require(mqc_language_equal(vf, formals(reference)), "candidate changed canonical formals")
  # Restore only the two declared numeric substitutions and remove the single
  # entry guard; every other parsed expression must equal the frozen source.
  b <- as.list(body(variant))
  mqc_require(mqc_language_equal(b[[2L]], quote(mqc_ready(candidate, context, scope))),
    "candidate entry guard missing")
  b <- b[-2L]; original <- as.list(expr[[3L]])
  assignment <- function(x, name) is.call(x) && identical(x[[1L]], as.name("<-")) &&
    identical(x[[2L]], as.name(name))
  ui <- which(vapply(b, assignment, logical(1L), name = "uniforms"))
  oi <- which(vapply(original, assignment, logical(1L), name = "uniforms"))
  mqc_require(length(ui) == 1L && length(oi) == 1L &&
    mqc_language_equal(b[[ui]], quote(uniforms <- mqk_candidate_uniforms(candidate$key,
      context$rng_namespace, draw_id, origin_id, inner_ids, H, context$rng_proof))),
    "uniform substitution differs")
  b[[ui]] <- original[[oi]]
  fi <- which(vapply(b, function(x) is.call(x) && identical(x[[1L]], as.name("for")), logical(1L)))
  ofi <- which(vapply(original, function(x) is.call(x) && identical(x[[1L]], as.name("for")), logical(1L)))
  mqc_require(length(fi) == 1L && length(ofi) == 1L, "one canonical horizon loop required")
  loop <- as.list(b[[fi]][[4L]]); orig_loop <- as.list(original[[ofi]][[4L]])
  qi <- which(vapply(loop, assignment, logical(1L), name = "q"))
  ci <- which(vapply(orig_loop, assignment, logical(1L), name = "crossed"))
  mqc_require(length(qi) == 1L && length(ci) == 1L &&
    mqc_language_equal(loop[[qi]], quote(q <- mqi_project(mu, candidate$isotonic,
      "generated_fixture_only"))), "projection substitution differs")
  loop <- append(loop[-qi], orig_loop[ci:(ci + 2L)], after = qi - 1L)
  b[[fi]][[4L]] <- as.call(loop)
  mqc_require(mqc_language_equal(as.call(b), expr[[3L]]), "unapproved recursive-body difference")
  invisible(TRUE)
}
mqc_load <- function(dlls, scope = "NOT_ADMITTED") {
  mqc_scope(scope); mqc_body_check()
  mqc_require(is.list(dlls) && identical(sort(names(dlls)), c("inverse", "isotonic", "key")) &&
    all(vapply(dlls, function(x) is.list(x) && identical(sort(names(x)), c("path", "sha256")), logical(1L))),
    "three explicitly pinned generated DLLs required")
  key <- mqk_load_candidate(dlls$key$path, dlls$key$sha256)
  iso <- mqi_load(dlls$isotonic$path, dlls$isotonic$sha256, scope)
  inverse <- mqe_load(dlls$inverse$path, dlls$inverse$sha256, scope)
  structure(list(key = key, isotonic = iso, inverse = inverse, dlls = dlls,
    source_pins = mqc_source_pins(), frozen_commits = c(
      key = "0ba50f4367b423406b5df07cf8543b9fc45d0fa6",
      isotonic = "13fe9ea77052358e883c87a6b30d70c321fc3292",
      inverse = "f194f413ecff1f44552087ad8dcc142f6e1c38b1"),
    scope = scope, source_runtime_authenticated = FALSE, C_ABI_qualified = FALSE,
    production_authorized = FALSE), class = "mq_composed_generated_candidate_v1")
}
mqc_handle <- function(candidate, scope) {
  mqc_scope(scope)
  mqc_require(inherits(candidate, "mq_composed_generated_candidate_v1") &&
    identical(candidate$scope, "generated_fixture_only") &&
    identical(candidate$production_authorized, FALSE) &&
    identical(candidate$source_runtime_authenticated, FALSE) &&
    identical(candidate$C_ABI_qualified, FALSE), "explicit nonauthorizing composed handle required")
}
mqc_ready <- function(candidate, context, scope) {
  mqc_handle(candidate, scope); mqc_body_check()
  mqc_require(identical(context$rng_mode, "r46_first_step_qualified"),
    "no substitution for a different canonical RNG mode")
}

mqc_paths_context <- function(context, draw_id, origin_id, inner_ids, include_trace = FALSE,
    include_paths = TRUE, collect_coherence = FALSE, crossing_tolerance = 0,
    candidate, scope = "NOT_ADMITTED") {
  mqc_ready(candidate, context, scope)
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
  req(is.logical(include_paths) && length(include_paths) == 1L && !is.na(include_paths) &&
    is.logical(collect_coherence) && length(collect_coherence) == 1L && !is.na(collect_coherence) &&
    is.numeric(crossing_tolerance) && length(crossing_tolerance) == 1L &&
    is.finite(crossing_tolerance) && crossing_tolerance >= 0, "invalid array/coherence settings")
  B <- length(inner_ids); design <- context$design; r <- design$reservoir
  origin <- context$origins[[origin_id]]; snapshot <- context$snapshots[[origin_id]]
  v <- context$validated[[origin_id]]; H <- origin$H; K <- length(context$tau)
  j <- match(draw_id, context$posterior$draw_ids)
  beta <- matrix(as.numeric(context$posterior$beta[j, ]), v$p, K)
  alpha <- as.numeric(context$posterior$alpha[j, ])
  states <- lapply(snapshot$states[[1L]], function(s) matrix(rep(s, B), length(s), B))
  response <- matrix(NA_real_, B, H); ordered <- array(NA_real_, c(B, K, H))
  uniforms <- mqk_candidate_uniforms(candidate$key, context$rng_namespace, draw_id, origin_id,
    inner_ids, H, context$rng_proof)
  trace <- if (include_trace) vector("list", H) else NULL
  coherence <- NULL
  if (collect_coherence) {
    req(all(vapply(c("app_iqf_mqc_init", "app_iqf_mqc_update", "app_iqf_mqc_validate"),
      exists, logical(1L), mode = "function")), "load the explicit MQ array/coherence helpers first")
    coherence <- app_iqf_mqc_init(H, context$tau, inner_ids, draw_id, origin_id,
      context$rng_namespace, crossing_tolerance)
  }
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
    q <- mqi_project(mu, candidate$isotonic, "generated_fixture_only")
    if (collect_coherence) coherence <- app_iqf_mqc_update(coherence, mu, q, h)
    u <- as.numeric(uniforms[, h])
    response[, h] <- app_iqf_mqb_inverse_rows(q, context$tau, u)
    req(all(is.finite(c(raw, z, mu, response[, h]))), "nonfinite batched recursive path")
    ordered[, , h] <- q
    if (include_trace) trace[[h]] <- list(raw = raw, scaled = scaled, states = states,
      readout = z, raw_quantiles = mu, ordered_quantiles = q, uniform = u)
  }
  paths <- if (include_paths) lapply(seq_len(B), function(i) list(kernels = lapply(seq_len(H), function(h)
    list(family = "mq_grid", q = as.numeric(ordered[i, , h]), tau = context$tau)),
    response = as.numeric(response[i, ]))) else NULL
  out <- list(paths = paths, response = response, ordered_quantiles = ordered, trace = trace,
    inner_ids = as.integer(inner_ids), draw_id = draw_id, origin_id = origin_id,
    coupling = context$coupling, rng_namespace = context$rng_namespace,
    outer_conditioning = "parameters_and_observed_origin_reservoir_state",
    production_authorized = FALSE, numerical_accuracy_qualified = FALSE)
  if (collect_coherence) {
    app_iqf_mqc_validate(coherence)
    out$raw_coherence <- coherence
  }
  out
}

mqc_arrays <- function(candidate, adapter, draw_id, origin_id, inner_ids,
    collect_coherence = TRUE, crossing_tolerance = 0, include_trace = FALSE, scope = "NOT_ADMITTED") {
  mqc_handle(candidate, scope)
  mqc_require(inherits(adapter, "app_iqf_mq_batch_adapter") &&
    identical(adapter$rng_mode, "r46_first_step_qualified") &&
    is.numeric(inner_ids) && all(is.finite(inner_ids)) && all(inner_ids <= adapter$inner_paths),
    "explicit bounded first-step-mode batch adapter required")
  out <- mqc_paths_context(adapter$batch_context, draw_id, origin_id, inner_ids,
    include_trace = include_trace, include_paths = FALSE, collect_coherence = collect_coherence,
    crossing_tolerance = crossing_tolerance, candidate = candidate, scope = scope)
  out$numerical_adapter <- "opt_in_composed_generated_native_arrays_v1"
  out
}
mqc_inverse <- function(candidate, q, tau, probabilities, tolerance = 1e-8, scope = "NOT_ADMITTED") {
  mqc_handle(candidate, scope)
  mqe_inverse(q, tau, probabilities, candidate$inverse, tolerance = tolerance, scope = scope)
}
mqc_cdf <- function(candidate, y, q, tau, scope = "NOT_ADMITTED") {
  mqc_handle(candidate, scope)
  mqe_cdf(y, q, tau, candidate$inverse, scope)
}
