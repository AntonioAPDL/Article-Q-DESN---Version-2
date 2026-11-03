# Purpose-bound numerical backend. It neither grants execution nor changes a
# canonical/generated default. The external guard authenticates each real use.
mqnk_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("MQ native qualification backend: ", why), call. = FALSE)
  invisible(TRUE)
}
mqnk_hash <- function(x) digest::digest(x, algo = "sha256", serialize = TRUE)
mqnk_frozen_sources <- function() c(
  "scripts/integrated_quantile_mq_batch.R" = "c3b6df5c2ef4f5d93eac124cfcc1c3aa9236be6c52713dcfb9938490bc6ab643",
  "scripts/mq_forecast_array_methods.R" = "76f585ff0daf4bbbaab9445d72b69a309783a097e8db2dec1a49a38021f48546",
  "application/R/integrated_quantile_forecast.R" = "0ee9df28badb06792f474739555d6ccb866de1f2d85703cbf1a22bc9ef88e0d3",
  "scripts/native/mq_key_hash.c" = "569a8c260d0d197464b7c2e8db7e6e6cf3be7c267c932d0e28a0c3b8cce6a26d",
  "scripts/native/mq_isoreg_batch.c" = "68e9f671a4384c9370b7249ed333b54e426fb2d6f20cb2d7a10acbbaa00eac28",
  "scripts/native/mq_event_inverse.c" = "81e9fe158874deaf3aafd70f0e49b4266a5f3021b104239d6509869d71164f52")
mqnk_sources_check <- function(root) {
  pins <- mqnk_frozen_sources(); paths <- file.path(root, names(pins))
  mqnk_require(all(file.exists(paths)) && !any(dir.exists(paths)) &&
    !any(nzchar(Sys.readlink(paths))) &&
    identical(unname(tools::sha256sum(paths)), unname(pins)), "frozen numerical source bytes changed")
  invisible(TRUE)
}
mqnk_context_check <- function(context, synthetic = FALSE) {
  mqnk_require(requireNamespace("digest", quietly = TRUE), "digest required")
  if (!synthetic) {
    mqnk_require(inherits(context, "mq_native_replay_context_v1") &&
      identical(context$schema_version, "mq_native_purpose_context_v1") &&
      identical(context$mode, "native_source_regression_qualification_v1") &&
      exists("mqns_context_check", mode = "function"), "sealed external replay context required")
    mqns_context_check(context)
    mqnk_require(identical(context$external_gate_verified, TRUE) &&
      identical(context$runtime_verified, TRUE), "external purpose and runtime gates required")
  } else {
    mqnk_require(inherits(context, "mq_native_synthetic_context_v1") &&
      identical(context$schema_version, "mq_native_synthetic_context_v1") &&
      identical(context$mode, "synthetic_backend_contract_test_v1") &&
      identical(context$unit_identity$rng_namespace, "synthetic_pure_MQ_batch_v1") &&
      identical(context$external_gate_verified, FALSE) && identical(context$runtime_verified, FALSE),
      "separate synthetic fixture context required; not an authentic execution route")
  }
  for (n in c("production_authorized", "refit_authorized", "scoring_authorized", "article_authorized", "C_ABI_qualified"))
    mqnk_require(identical(context[[n]], FALSE), paste(n, "must remain false"))
  root <- context$canonical_source_root
  mqnk_require(is.character(root) && length(root) == 1L && !is.na(root) && startsWith(root, "/") &&
    identical(root, normalizePath(root, mustWork = TRUE)), "canonical source root required")
  mqnk_sources_check(root)
  u <- context$unit_identity
  mqnk_require(is.list(u) && all(vapply(u[c("model_cell_id", "draw_id", "origin_id", "rng_namespace")],
    function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x), logical(1L))) &&
    length(u[c("model_cell_id", "draw_id", "origin_id", "rng_namespace")]) == 4L &&
    identical(as.numeric(u$H), 30) && identical(as.numeric(u$tau), c(.05,.10,.25,.50,.75,.90,.95)),
    "one fixed original draw/origin and seven-level H30 geometry required")
  for (n in c("training_path_range", "validation_path_range")) {
    z <- context[[n]]
    mqnk_require(typeof(z) %in% c("integer", "double") && length(z) == 2L &&
      all(is.finite(z)) && all(z == floor(z)) && z[1L] >= 1 && z[2L] >= z[1L] &&
      z[2L] <= .Machine$integer.max, "explicit positive bounded ID ranges required")
  }
  mqnk_require(context$training_path_range[2L] < context$validation_path_range[1L],
    "training and validation streams overlap")
  if (!synthetic) mqnk_require(identical(as.numeric(context$training_path_range), c(1,65536)) &&
    identical(as.numeric(context$validation_path_range), c(65537,327680)), "frozen replay ID ranges changed")
  invisible(TRUE)
}
mqnk_manifest_check <- function(manifest, context, synthetic) {
  if (!synthetic) {
    mqnk_require(is.list(manifest) &&
      identical(sort(names(attributes(manifest))), sort(c("names", "receipt_path", "receipt_sha256"))) &&
      is.character(names(manifest)) && length(names(manifest)) == length(manifest) &&
      !anyNA(names(manifest)) && all(nzchar(names(manifest))) && !anyDuplicated(names(manifest)),
      "only unique named receipt fields and the two pinned-file metadata attributes are permitted")
  }
  mqnk_require(is.list(manifest) && identical(manifest$schema_version, "mq_native_retained_build_receipt_v1") &&
    identical(sort(names(manifest$dlls)), c("inverse", "isotonic", "key")) &&
    identical(manifest$R_home, normalizePath(R.home(), mustWork = TRUE)) &&
    identical(manifest$R_libdir, normalizePath(R.home("lib"), mustWork = TRUE)), "three-DLL native-R retained build receipt required")
  if (!synthetic) {
    mqnk_require(identical(manifest$source_commit, context$source_commit) &&
      identical(manifest$source_tree, context$source_tree), "build/source identity differs from purpose")
    path <- attr(manifest, "receipt_path", exact = TRUE); sha <- attr(manifest, "receipt_sha256", exact = TRUE)
    mqnk_require(is.character(path) && length(path) == 1L && file.exists(path) && !dir.exists(path) &&
      !nzchar(Sys.readlink(path)) && identical(path, normalizePath(path, mustWork = TRUE)) &&
      identical(sha, context$retained_build_receipt_sha256) && identical(unname(tools::sha256sum(path)), sha),
      "retained build receipt file and purpose pin required")
    parsed <- jsonlite::fromJSON(path, simplifyVector = FALSE)
    plain <- manifest
    attr(plain, "receipt_path") <- NULL
    attr(plain, "receipt_sha256") <- NULL
    mqnk_require(identical(parsed, plain), "build receipt object differs from its pinned file")
  }
  source <- c(key = "scripts/native/mq_key_hash.c", isotonic = "scripts/native/mq_isoreg_batch.c",
    inverse = "scripts/native/mq_event_inverse.c")
  for (name in names(source)) {
    x <- manifest$dlls[[name]]; path <- x$path
    mqnk_require(is.list(x) && is.character(path) && length(path) == 1L && !is.na(path) && startsWith(path, "/") &&
      file.exists(path) && !dir.exists(path) && !nzchar(Sys.readlink(path)) &&
      identical(path, normalizePath(path, mustWork = TRUE)) && is.finite(x$size_bytes) &&
      x$size_bytes > 0 && x$size_bytes <= 8*1024^2 && identical(as.numeric(file.info(path)$size), as.numeric(x$size_bytes)) &&
      is.character(x$sha256) && length(x$sha256) == 1L && grepl("^[a-f0-9]{64}$", x$sha256) &&
      identical(unname(tools::sha256sum(path)), x$sha256) &&
      identical(x$source_path, source[[name]]) && identical(x$source_sha256, unname(mqnk_frozen_sources()[source[[name]]])),
      "DLL bytes, bounds or frozen C source binding changed")
  }
  mqnk_require(!anyDuplicated(vapply(manifest$dlls, `[[`, "", "path")), "distinct DLL paths required")
  invisible(TRUE)
}
mqnk_serialization_check <- function() {
  mqnk_require(identical(as.character(getRversion()), "4.6.0") &&
    identical(as.character(utils::packageVersion("digest")), "0.6.39") &&
    identical(get(".hasNoSharing", asNamespace("digest"))(), FALSE) &&
    identical(get("set_skip", asNamespace("digest"))(as.raw(1:20), FALSE), 14),
    "declared public R serialization/digest semantics required")
}
mqnk_registered_symbols <- function(build_manifest, may_load = FALSE) {
  spec <- list(key = c(mq_key_hash_batch = 4L), isotonic = c(mqi_project = 1L),
    inverse = c(mqe_first_indices = 2L, mqe_cdf_values = 3L))
  loaded <- getLoadedDLLs(); symbols <- list()
  for (name in names(spec)) {
    path <- build_manifest$dlls[[name]]$path
    matches <- which(vapply(loaded, function(x) identical(x[["path"]], path), logical(1L)))
    if (!length(matches) && may_load) {
      dyn.load(path, local = TRUE, now = TRUE); loaded <- getLoadedDLLs()
      matches <- which(vapply(loaded, function(x) identical(x[["path"]], path), logical(1L)))
    }
    mqnk_require(length(matches) == 1L, "all genuine DLLs must be uniquely preloaded before runtime authentication")
    dll <- loaded[[matches]]; entries <- getDLLRegisteredRoutines(dll)$.Call
    mqnk_require(identical(dll[["dynamicLookup"]], FALSE) && identical(names(entries), names(spec[[name]])) &&
      identical(vapply(entries, `[[`, integer(1L), "numParameters"), spec[[name]]), "frozen registered .Call signatures required")
    symbols[[name]] <- lapply(names(spec[[name]]), function(n) getNativeSymbolInfo(n, PACKAGE = dll))
    names(symbols[[name]]) <- names(spec[[name]])
  }
  symbols
}
# The only genuine dyn.load route. This object has no numerical methods and
# cannot be promoted in place. A new sealed context is required by mqnk_load.
mqnk_enroll <- function(build_manifest, enrollment_context) {
  ctx <- enrollment_context
  mqnk_require(inherits(ctx, "mq_native_runtime_enrollment_context_v1") &&
    identical(ctx$schema_version, "mq_native_runtime_enrollment_context_v1") &&
    identical(ctx$mode, "load_only_runtime_enrollment_v1") &&
    identical(ctx$runtime_verified, FALSE) && exists("mqns_enrollment_context_check", mode = "function"),
    "external load-only enrollment context required")
  mqns_enrollment_context_check(ctx)
  for (n in c("production_authorized", "refit_authorized", "scoring_authorized", "article_authorized", "C_ABI_qualified"))
    mqnk_require(identical(ctx[[n]], FALSE), "enrollment cannot grant numerical, model or publication permission")
  mqnk_sources_check(ctx$canonical_source_root); mqnk_serialization_check()
  mqnk_manifest_check(build_manifest, ctx, FALSE)
  symbols <- mqnk_registered_symbols(build_manifest, may_load = TRUE)
  mqnk_manifest_check(build_manifest, ctx, FALSE)
  out <- new.env(parent = emptyenv())
  out$context <- ctx; out$build_manifest <- build_manifest; out$symbols <- symbols
  out$numerical_execution_allowed <- FALSE; out$production_authorized <- FALSE; out$C_ABI_qualified <- FALSE
  class(out) <- "mq_native_load_only_v1"; lockEnvironment(out, bindings = TRUE)
  out
}
mqnk_load_internal <- function(build_manifest, purpose_context, synthetic) {
  mqnk_context_check(purpose_context, synthetic)
  mqnk_serialization_check()
  mqnk_manifest_check(build_manifest, purpose_context, synthetic)
  symbols <- mqnk_registered_symbols(build_manifest, may_load = synthetic)
  mqnk_manifest_check(build_manifest, purpose_context, synthetic)
  out <- new.env(parent = emptyenv())
  out$context <- purpose_context; out$context_hash <- mqnk_hash(purpose_context)
  out$build_manifest <- build_manifest; out$build_hash <- mqnk_hash(build_manifest); out$symbols <- symbols
  out$synthetic <- synthetic; out$production_authorized <- FALSE; out$C_ABI_qualified <- FALSE
  class(out) <- if (synthetic) "mq_native_synthetic_backend_v1" else "mq_native_purpose_backend_v1"
  lockEnvironment(out, bindings = TRUE)
  mqnk_body_check(root = purpose_context$canonical_source_root)
  out
}
mqnk_load <- function(build_manifest, purpose_context) mqnk_load_internal(build_manifest, purpose_context, FALSE)
mqnk_load_synthetic <- function(build_manifest, fixture_context) mqnk_load_internal(build_manifest, fixture_context, TRUE)
mqnk_handle_check <- function(handle) {
  mqnk_require(is.environment(handle) && environmentIsLocked(handle) &&
    ((inherits(handle, "mq_native_purpose_backend_v1") && identical(handle$synthetic, FALSE)) ||
     (inherits(handle, "mq_native_synthetic_backend_v1") && identical(handle$synthetic, TRUE))) &&
    identical(handle$production_authorized, FALSE) && identical(handle$C_ABI_qualified, FALSE) &&
    identical(handle$context_hash, mqnk_hash(handle$context)) &&
    identical(handle$build_hash, mqnk_hash(handle$build_manifest)), "immutable purpose-bound backend required")
  mqnk_context_check(handle$context, handle$synthetic)
  mqnk_manifest_check(handle$build_manifest, handle$context, handle$synthetic)
  invisible(TRUE)
}
mqnk_ids_check <- function(handle, context, draw_id, origin_id, inner_ids, phase) {
  mqnk_handle_check(handle); u <- handle$context$unit_identity
  mqnk_require(identical(draw_id, u$draw_id) && identical(origin_id, u$origin_id) &&
    identical(context$rng_namespace, u$rng_namespace) && identical(as.numeric(context$tau), as.numeric(u$tau)) &&
    identical(context$rng_mode, "r46_first_step_qualified") &&
    identical(as.numeric(context$origins[[origin_id]]$H), as.numeric(u$H)), "original draw/origin/namespace/geometry changed")
  mqnk_require(is.character(phase) && length(phase) == 1L && phase %in% c("training", "validation", "parity_training", "parity_validation") &&
    typeof(inner_ids) %in% c("integer", "double") && !is.object(inner_ids) && length(inner_ids) >= 1L &&
    all(is.finite(inner_ids)) && all(inner_ids == floor(inner_ids)) && !anyDuplicated(inner_ids), "explicit phase and distinct original integer IDs required")
  range <- handle$context[[if (phase %in% c("training", "parity_training")) "training_path_range" else "validation_path_range"]]
  mqnk_require(all(inner_ids >= range[1L] & inner_ids <= range[2L]), "path IDs outside the purpose phase")
  if (!handle$synthetic) {
    mqnk_require(exists("mqns_phase_check", mode = "function"), "external freeze/phase gate required")
    mqns_phase_check(handle$context, phase, inner_ids)
  }
  invisible(TRUE)
}
mqnk_uniforms <- function(handle, rng_namespace, draw_id, origin_id, inner_ids, H, rng_proof) {
  mqnk_handle_check(handle)
  app_iqf_mqb_rng_proof(rng_proof)
  mqnk_require(identical(rng_namespace, handle$context$unit_identity$rng_namespace) &&
    identical(draw_id, handle$context$unit_identity$draw_id) && identical(origin_id, handle$context$unit_identity$origin_id) &&
    identical(as.numeric(H), as.numeric(handle$context$unit_identity$H)), "uniform identity changed")
  range <- handle$context[[if (identical(handle$context$phase, "validation")) "validation_path_range" else "training_path_range"]]
  mqnk_require(typeof(inner_ids) %in% c("integer", "double") && !is.object(inner_ids) &&
    length(inner_ids) >= 1L && all(is.finite(inner_ids)) && all(inner_ids == floor(inner_ids)) &&
    !anyDuplicated(inner_ids) && all(inner_ids >= range[1L] & inner_ids <= range[2L]), "uniform path range changed")
  inner <- vapply(seq_along(inner_ids), function(i) as.character(inner_ids[i]), "")
  horizons <- vapply(seq_len(as.integer(H)), function(h) as.character(h), "")
  key <- list(version = 1L, scientific_identity = as.character(rng_namespace), draw = as.character(draw_id),
    origin = as.character(origin_id), inner = "", horizon = "", purpose = "response")
  value <- .Call(handle$symbols$key$mq_key_hash_batch, key, inner, horizons, FALSE)
  mqnk_require(identical(dim(value$uniforms), c(as.integer(length(inner_ids)), as.integer(H))) &&
    all(is.finite(value$uniforms)) && all(value$uniforms > 0 & value$uniforms < 1), "invalid native uniform matrix")
  value$uniforms
}
mqnk_project <- function(handle, q) {
  mqnk_require(is.environment(handle) && environmentIsLocked(handle) &&
    (inherits(handle, "mq_native_purpose_backend_v1") || inherits(handle, "mq_native_synthetic_backend_v1")),
    "load-only handles cannot project numerical inputs")
  mqnk_require(is.matrix(q) && typeof(q) %in% c("double", "integer"), "real readout matrix required")
  if (typeof(q) != "double") storage.mode(q) <- "double"
  .Call(handle$symbols$isotonic$mqi_project, q)
}
mqnk_language_equal <- function(a, b) identical(deparse(a, width.cutoff = 500L), deparse(b, width.cutoff = 500L))
mqnk_body_check <- function(reference = app_iqf_mqb_paths_context, variant = mqnk_paths_context, root = getwd()) {
  mqnk_sources_check(root)
  ast <- parse(file = file.path(root, "scripts/integrated_quantile_mq_batch.R"), keep.source = FALSE)
  at <- which(vapply(ast, function(x) is.call(x) && identical(x[[1L]], as.name("<-")) &&
    identical(x[[2L]], as.name("app_iqf_mqb_paths_context")), logical(1L)))
  mqnk_require(length(at) == 1L, "one canonical context definition required")
  expr <- ast[[at]][[3L]]
  mqnk_require(mqnk_language_equal(formals(reference), expr[[2L]]) && mqnk_language_equal(body(reference), expr[[3L]]),
    "canonical body/formals changed")
  vf <- formals(variant)
  mqnk_require(identical(names(vf), c(names(formals(reference)), "handle", "phase")) &&
    identical(vf$phase, "NOT_ADMITTED") && mqnk_language_equal(as.pairlist(vf[names(formals(reference))]), formals(reference)),
    "backend canonical formals changed")
  b <- as.list(body(variant)); original <- as.list(expr[[3L]])
  mqnk_require(mqnk_language_equal(b[[2L]], quote(mqnk_ready(handle, context, draw_id, origin_id, inner_ids, phase))), "entry gate changed")
  b <- b[-2L]
  assignment <- function(x, n) is.call(x) && identical(x[[1L]], as.name("<-")) && identical(x[[2L]], as.name(n))
  ui <- which(vapply(b, assignment, logical(1L), n = "uniforms")); oi <- which(vapply(original, assignment, logical(1L), n = "uniforms"))
  mqnk_require(length(ui) == 1L && length(oi) == 1L && mqnk_language_equal(b[[ui]], quote(uniforms <- mqnk_uniforms(handle,
    context$rng_namespace, draw_id, origin_id, inner_ids, H, context$rng_proof))), "uniform substitution changed")
  b[[ui]] <- original[[oi]]
  loop_at <- function(b) which(vapply(b, function(x) is.call(x) && identical(x[[1L]], as.name("for")), logical(1L)))
  fi <- loop_at(b); ofi <- loop_at(original)
  mqnk_require(length(fi) == 1L && length(ofi) == 1L, "one canonical horizon loop required")
  loop <- as.list(b[[fi]][[4L]]); old <- as.list(original[[ofi]][[4L]])
  qi <- which(vapply(loop, assignment, logical(1L), n = "q")); ci <- which(vapply(old, assignment, logical(1L), n = "crossed"))
  mqnk_require(length(qi) == 1L && length(ci) == 1L &&
    mqnk_language_equal(loop[[qi]], quote(q <- mqnk_project(handle, mu))), "projection substitution changed")
  loop <- append(loop[-qi], old[ci:(ci + 2L)], after = qi - 1L); b[[fi]][[4L]] <- as.call(loop)
  mqnk_require(mqnk_language_equal(as.call(b), expr[[3L]]), "unapproved recursive-body difference")
  invisible(TRUE)
}
mqnk_ready <- function(handle, context, draw_id, origin_id, inner_ids, phase) {
  mqnk_ids_check(handle, context, draw_id, origin_id, inner_ids, phase)
  mqnk_body_check(root = handle$context$canonical_source_root)
}

mqnk_paths_context <- function(context, draw_id, origin_id, inner_ids, include_trace = FALSE,
    include_paths = TRUE, collect_coherence = FALSE, crossing_tolerance = 0, handle, phase = "NOT_ADMITTED") {
  mqnk_ready(handle, context, draw_id, origin_id, inner_ids, phase)
  req <- app_iqf_mqb_require
  req(is.character(draw_id) && length(draw_id) == 1L && !is.na(draw_id) &&
    is.character(origin_id) && length(origin_id) == 1L && !is.na(origin_id) &&
    draw_id %in% context$posterior$draw_ids && origin_id %in% names(context$origins),
    "unknown original draw or observed origin")
  req(is.numeric(inner_ids) && length(inner_ids) >= 1L && all(is.finite(inner_ids)) &&
    all(inner_ids >= 1 & inner_ids <= .Machine$integer.max) &&
    all(inner_ids == as.integer(inner_ids)) && !anyDuplicated(inner_ids),
    "distinct positive original inner-path identities required")
  req(is.logical(include_trace) && length(include_trace) == 1L && !is.na(include_trace), "invalid trace setting")
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
  uniforms <- mqnk_uniforms(handle, context$rng_namespace, draw_id, origin_id, inner_ids, H, context$rng_proof)
  trace <- if (include_trace) vector("list", H) else NULL
  coherence <- NULL
  if (collect_coherence) {
    req(all(vapply(c("app_iqf_mqc_init", "app_iqf_mqc_update", "app_iqf_mqc_validate"),
      exists, logical(1L), mode = "function")), "load the explicit MQ array/coherence helpers first")
    coherence <- app_iqf_mqc_init(H, context$tau, inner_ids, draw_id, origin_id, context$rng_namespace, crossing_tolerance)
  }
  for (h in seq_len(H)) {
    raw <- app_iqf_mqb_raw(as.integer(origin$origin_time + h), response, origin, design, B)
    scaled <- if (isTRUE(design$scale_params$standardize))
      sweep(sweep(raw, 1L, as.numeric(design$scale_params$center), "-"), 1L, as.numeric(design$scale_params$scale), "/") else raw
    U <- rbind(rep(snapshot$reservoir_meta$win_scale_bias, B), scaled * snapshot$reservoir_meta$win_scale_global)
    previous <- states; next_states <- states
    pre <- r$W[[1L]] %*% previous[[1L]] + r$Win[[1L]] %*% U
    next_states[[1L]] <- (1 - r$alpha[1L]) * previous[[1L]] + r$alpha[1L] * v$act_f(pre)
    if (v$D > 1L) for (d in 2:v$D) {
      lower <- if (isTRUE(r$Q_is_identity[[d - 1L]])) next_states[[d - 1L]] else r$Q[[d - 1L]] %*% next_states[[d - 1L]]
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
    q <- mqnk_project(handle, mu)
    if (collect_coherence) coherence <- app_iqf_mqc_update(coherence, mu, q, h)
    u <- as.numeric(uniforms[, h])
    response[, h] <- app_iqf_mqb_inverse_rows(q, context$tau, u)
    req(all(is.finite(c(raw, z, mu, response[, h]))), "nonfinite batched recursive path")
    ordered[, , h] <- q
    if (include_trace) trace[[h]] <- list(raw = raw, scaled = scaled, states = states,
      readout = z, raw_quantiles = mu, ordered_quantiles = q, uniform = u)
  }
  paths <- if (include_paths) lapply(seq_len(B), function(i) list(kernels = lapply(seq_len(H), function(h)
    list(family = "mq_grid", q = as.numeric(ordered[i, , h]), tau = context$tau)), response = as.numeric(response[i, ]))) else NULL
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
mqnk_arrays <- function(handle, adapter, draw_id, origin_id, inner_ids, collect_coherence = TRUE,
    crossing_tolerance = 0, include_trace = FALSE, phase = "NOT_ADMITTED") {
  mqnk_handle_check(handle)
  mqnk_require(inherits(adapter, "app_iqf_mq_batch_adapter") && identical(adapter$rng_mode, "r46_first_step_qualified") &&
    all(inner_ids <= adapter$inner_paths), "bounded original first-step-mode batch adapter required")
  out <- mqnk_paths_context(adapter$batch_context, draw_id, origin_id, inner_ids, include_trace = include_trace,
    include_paths = FALSE, collect_coherence = collect_coherence, crossing_tolerance = crossing_tolerance,
    handle = handle, phase = phase)
  out$numerical_adapter <- "purpose_bound_native_source_regression_arrays_v1"
  out
}

mqnk_cdf_values_internal <- function(handle, y, q, tau) {
  # Pure arithmetic subordinate to a checked public CDF/inverse entry. Do not
  # reparse/rehash the entire build receipt for every endpoint a second time.
  mqnk_require(is.environment(handle) && environmentIsLocked(handle) &&
    (inherits(handle, "mq_native_purpose_backend_v1") || inherits(handle, "mq_native_synthetic_backend_v1")),
    "load-only handles cannot evaluate numerical CDFs")
  mqnk_require(is.matrix(q) && typeof(q) %in% c("double", "integer") &&
    typeof(tau) %in% c("double", "integer") && typeof(y) %in% c("double", "integer") &&
    identical(as.numeric(tau), as.numeric(handle$context$unit_identity$tau)), "real purpose-grid CDF arguments required")
  if (typeof(q) != "double") storage.mode(q) <- "double"
  .Call(handle$symbols$inverse$mqe_cdf_values, q, as.double(tau), as.double(y))
}
mqnk_cdf_values <- function(handle, y, q, tau) {
  mqnk_handle_check(handle)
  mqnk_require(handle$synthetic || identical(handle$context$phase, "validation"),
    "public endpoint CDF evaluation requires the sealed validation context")
  mqnk_cdf_values_internal(handle, y, q, tau)
}
mqnk_cdf_internal <- function(handle, y, q, tau) {
  values <- mqnk_cdf_values_internal(handle, y, q, tau)
  out <- vapply(seq_along(y), function(j) mean(values[, j]), numeric(1L)); names(out) <- names(y); out
}
mqnk_inverse <- function(handle, q, tau, probabilities, tolerance = 1e-8, return_receipt = FALSE) {
  mqnk_handle_check(handle); req <- mqnk_require
  req(is.logical(return_receipt) && length(return_receipt) == 1L && !is.na(return_receipt), "explicit receipt option required")
  req(is.matrix(q) && typeof(q) %in% c("double", "integer") && nrow(q) >= 1L && nrow(q) <= 262144L &&
    ncol(q) >= 2L && ncol(q) <= 64L && all(is.finite(q)) && typeof(tau) %in% c("double", "integer") &&
    identical(as.numeric(tau), as.numeric(handle$context$unit_identity$tau)) && length(tau) == ncol(q) &&
    typeof(probabilities) %in% c("double", "integer") && length(probabilities) >= 1L && length(probabilities) <= 64L &&
    all(is.finite(probabilities)) && all(probabilities > 0 & probabilities < 1) && identical(tolerance, 1e-8),
    "bounded original inverse geometry and fixed 1e-8 tolerance required")
  app_iqf_grid(rep(0, ncol(q)), tau)
  L <- nrow(q); K <- ncol(q); tau <- as.numeric(tau); original_q <- q
  crossed <- which(rowSums(q[, -1L, drop = FALSE] < q[, -K, drop = FALSE]) > 0L)
  for (i in crossed) q[i, ] <- stats::isoreg(seq_len(K), q[i, ])$yf
  finish <- function(answer, fallback, reason) if (return_receipt) list(quantile = answer, fallback = fallback,
    reason = reason, production_authorized = FALSE, C_ABI_qualified = FALSE) else answer
  fallback <- function(reason) {
    kernels <- lapply(seq_len(L), function(i) list(family = "mq_grid", q = as.numeric(original_q[i, ]), tau = tau))
    finish(app_iqf_invert_cdf_bisection(kernels, probabilities, tolerance), TRUE, reason)
  }
  # Keep canonical R event construction, grouping, both extended-precision
  # cumsums, interpolation and checked fallback. C moves no reductions.
  width <- q[, -1L, drop = FALSE] - q[, -K, drop = FALSE]
  mass <- matrix(rep(diff(tau), each = L), nrow = L); positive <- width > 0
  density <- matrix(0, nrow = L, ncol = K - 1L); density[positive] <- mass[positive] / width[positive]
  events <- cbind(position = c(q[, 1L], q[, K], q[, -K, drop = FALSE], q[, -1L, drop = FALSE]),
    slope_change = c(rep(0, 2L*L), density, -density) / L,
    atom = c(rep(tau[1L], L), rep(1-tau[K], L), ifelse(positive, 0, mass), rep(0, length(mass))) / L)
  if (any(!is.finite(events))) return(fallback("nonfinite_events"))
  knots <- sort(unique(events[, "position"]))
  grouped <- rowsum(events[, c("slope_change", "atom"), drop = FALSE], match(events[, "position"], knots), reorder = TRUE)
  slope <- cumsum(grouped[, "slope_change"])
  interval_mass <- if (length(knots) > 1L) head(slope, -1L) * diff(knots) else numeric()
  if (any(!is.finite(interval_mass)) || any(interval_mass < -1e-12)) return(fallback("interval_mass"))
  interval_mass <- pmax(0, interval_mass)
  right <- cumsum(grouped[, "atom"] + c(0, interval_mass)); left <- right - grouped[, "atom"]
  if (any(!is.finite(c(left,right))) || any(left < -1e-10) || any(right > 1+1e-10) ||
    abs(tail(right, 1L)-1) > 1e-10 || any(diff(right) < -1e-12)) return(fallback("cdf_event_mass"))
  right <- pmin(1, pmax(0, right)); right[length(right)] <- 1
  if (length(right) > 4000000L) return(fallback("candidate_scan_bound"))
  index <- .Call(handle$symbols$inverse$mqe_first_indices, as.double(right), as.double(probabilities))
  answer <- vapply(seq_along(probabilities), function(i) {
    p <- probabilities[i]; j <- index[i]
    if (is.na(j)) return(NA_real_)
    if (j == 1L || p > left[j]) return(knots[j])
    if (!is.finite(slope[j-1L]) || slope[j-1L] <= 0) return(NA_real_)
    value <- knots[j-1L] + (p-right[j-1L]) / slope[j-1L]
    max(knots[j-1L], min(knots[j], value))
  }, numeric(1L)); names(answer) <- names(probabilities)
  if (any(!is.finite(answer))) return(fallback("unresolved_inverse"))
  probe_y <- c(answer-tolerance, answer+tolerance)
  probe <- if (any(!is.finite(probe_y)) || as.double(L)*length(probe_y) > 8388608)
    app_iqf_mq_matrix_cdf(probe_y, q, tau) else mqnk_cdf_internal(handle, probe_y, q, tau)
  n <- length(answer)
  if (any(!is.finite(probe)) || any(probe[seq_len(n)] >= probabilities) || any(probe[n+seq_len(n)] < probabilities))
    return(fallback("checked_inverse_probe"))
  finish(answer, FALSE, "native_first_index_and_checked_pointwise_CDF")
}
