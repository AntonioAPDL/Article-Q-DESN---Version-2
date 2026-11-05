# Generated-only conditional score integration for the full AL/RHS target.
# A narrow, locked affine/causal fixture proves the future dependency. This is
# not an arbitrary mask API, authentic-data reader or native qualification.
# Under diagonal q, RHS coordinates are independent of coefficients/scales;
# E[score_RHS * log Zhat | coefficients,scales,inner randomness] is zero.
# Their historical ELBO gradients remain untouched and must be added later.

gafsp_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS AL future-score projection: ", why), call. = FALSE)
  invisible(TRUE)
}
gafsp_hash <- function(x) {
  gafsp_require(requireNamespace("digest", quietly = TRUE), "digest is required")
  digest::digest(x, algo = "sha256", serialize = TRUE)
}
gafsp_sorted_values <- function(x, omit = character()) {
  x <- x[!names(x) %in% omit]
  x[sort(names(x))]
}
gafsp_sources <- function(source_root = ".") {
  expected <- c(
    "scripts/diagnostics/glofas_collapsed_al_target.R" =
      "515d10dde59575ab1db8b89b85f6ed8a522d2cd91e3ae3330795d9c61726a8d7",
    "scripts/diagnostics/glofas_collapsed_particle_vi.R" =
      "56ae2cdf9f30a98a183147624bdcc760bf320b4fa18d038eadf3b04996fc7753",
    "scripts/diagnostics/glofas_innovation_coordinates.R" =
      "b1bcc41929acbc020c1b2b5a96b0e7890762e0920ea3ad0e3a85a6e3949e5560")
  gafsp_require(is.character(source_root) && length(source_root) == 1L &&
    !is.na(source_root) && nzchar(source_root), "one source root required")
  root <- normalizePath(source_root, mustWork = TRUE)
  paths <- file.path(root, names(expected))
  actual <- vapply(paths, function(path) {
    gafsp_require(file.exists(path) && !dir.exists(path), "required text source is missing")
    digest::digest(file = path, algo = "sha256", serialize = FALSE)
  }, character(1L))
  names(actual) <- names(expected)
  gafsp_require(identical(actual, expected), "source fingerprint changed; independent review is required")
  list(root = root, paths = paths, sha256 = actual)
}
gafsp_function_code <- function(fn) list(formals = deparse(formals(fn)), body = deparse(body(fn)))
gafsp_private_code <- function(e) {
  gafsp_require(is.environment(e) && identical(parent.env(e), baseenv()), "private source environment changed")
  n <- sort(ls(e, all.names = TRUE))
  gafsp_require(all(vapply(n, function(k) is.function(get(k, e, inherits = FALSE)), logical(1L))),
    "unexpected private source binding")
  setNames(lapply(n, function(k) gafsp_function_code(get(k, e, inherits = FALSE))), n)
}
gafsp_locked <- function(e) is.environment(e) && environmentIsLocked(e) &&
  all(vapply(ls(e, all.names = TRUE), function(n) bindingIsLocked(n, e), logical(1L)))

gafsp_make_generated_al_binding <- function(spec, reference_features, discrepancy_features,
    members, reference_lag = 0, discrepancy_lag = 0, known_baseline = NULL,
    particles = 16L, source_root = ".") {
  q <- gafsp_require
  sources <- gafsp_sources(source_root)
  private <- new.env(parent = baseenv())
  # gcat_decode uses this one unqualified stats helper; no caller search path
  # is inherited by the locked target/particle implementation.
  private$setNames <- stats::setNames
  for (path in sources$paths) sys.source(path, envir = private, keep.source = FALSE)
  q(identical(gafsp_sources(sources$root)$sha256, sources$sha256), "source changed during loading")
  q(is.list(spec) && identical(spec$schema_version, "glofas_generated_collapsed_AL_target_v1"),
    "explicit full AL target specification required")
  raw_blocks <- lapply(spec$blocks, function(b) b[c("index", "intercept_index", "tau0",
    "intercept_prec", "slab_shape", "slab_rate", "zeta2_fixed")])
  rebuilt <- private$gcat_spec(spec$p, raw_blocks, spec$probability, spec$scale_prior)
  q(isTRUE(all.equal(spec, rebuilt, tolerance = 0)), "target roles, complete coefficients/scales or hierarchy changed")
  spec <- rebuilt
  H <- nrow(reference_features)
  q(is.matrix(reference_features) && is.numeric(reference_features) &&
    length(H) == 1L && H >= 1L && H <= 28L &&
    ncol(reference_features) == length(spec$blocks$beta$index) && all(is.finite(reference_features)) &&
    is.matrix(discrepancy_features) && is.numeric(discrepancy_features) &&
    nrow(discrepancy_features) == H && ncol(discrepancy_features) == length(spec$blocks$alpha$index) &&
    all(is.finite(discrepancy_features)), "finite complete generated feature blocks required")
  q(is.null(members) || (is.matrix(members) && is.numeric(members) &&
    identical(dim(members), c(as.integer(H), 51L)) && all(is.finite(members))),
    "all 51 ordinary member factors required")
  finite_scalar <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)
  q(finite_scalar(reference_lag) && finite_scalar(discrepancy_lag) &&
    finite_scalar(particles) && particles == floor(particles) && particles >= 2L && particles <= 4096L,
    "bounded explicit generated particle/lag controls required")
  if (is.null(known_baseline)) known_baseline <- rep(0, H)
  q(is.numeric(known_baseline) && length(known_baseline) == H && all(is.finite(known_baseline)),
    "finite aligned known baseline required")
  fixture <- list(reference_features = reference_features, discrepancy_features = discrepancy_features,
    members = members, reference_lag = reference_lag, discrepancy_lag = discrepancy_lag,
    known_baseline = known_baseline, horizon = as.integer(H), particles = as.integer(particles))
  callbacks <- new.env(parent = private)
  callbacks$spec <- spec; callbacks$fixture <- fixture
  callbacks$location <- eval(quote(function(h, past, parameters) {
    sum(fixture$reference_features[h, ] * parameters$coefficients[spec$blocks$beta$index]) +
      fixture$reference_lag * if (length(past)) past[length(past)] else 0
  }), envir = callbacks)
  callbacks$member_location <- eval(quote(function(h, past, parameters) {
    location(h, past, parameters) +
      sum(fixture$discrepancy_features[h, ] * parameters$coefficients[spec$blocks$alpha$index]) +
      fixture$known_baseline[h] +
      fixture$discrepancy_lag * if (length(past)) past[length(past)] else 0
  }), envir = callbacks)
  evidence <- private$gcat_make_evidence(spec, members, callbacks$location, callbacks$member_location,
    horizon = H, particles = as.integer(particles))
  # Everything the callback can see is verified value data or the pinned pure
  # source. An arbitrary user-supplied location closure is never admitted.
  lockEnvironment(callbacks, bindings = TRUE)
  lockEnvironment(environment(evidence), bindings = TRUE)
  lockEnvironment(private, bindings = TRUE)
  active <- as.integer(c(seq_len(spec$p), unname(spec$scales)))
  auxiliary <- as.integer(unlist(lapply(spec$blocks, function(b)
    c(b$tau, b$xi, b$lambda, b$nu, b$slab)), use.names = FALSE))
  q(!anyDuplicated(c(active, auxiliary)) &&
    identical(sort(c(active, auxiliary)), seq_len(spec$dimension)), "all parameter roles must be covered exactly once")
  roles <- rep(NA_character_, spec$dimension)
  roles[seq_len(spec$p)] <- "coefficient"; roles[spec$scales] <- c("scale_Y", "scale_G")
  roles[auxiliary] <- "RHS_auxiliary"
  b <- new.env(parent = emptyenv())
  values <- list(schema_version = "glofas_generated_AL_future_score_projection_v1", spec = spec,
    dimension = spec$dimension, coordinate_names = spec$coordinate_names, roles = roles,
    active = active, auxiliary = auxiliary, fixture = fixture, source_root = sources$root,
    source_sha256 = sources$sha256, private = private, callbacks = callbacks, evidence = evidence,
    private_code_sha256 = gafsp_hash(gafsp_private_code(private)),
    callback_code_sha256 = gafsp_hash(list(gafsp_function_code(callbacks$location),
      gafsp_function_code(callbacks$member_location), gafsp_function_code(evidence))),
    production_qualified = FALSE, authentic_reads_authorized = FALSE)
  list2env(values, envir = b)
  b$value_sha256 <- gafsp_hash(gafsp_sorted_values(values, c("private", "callbacks", "evidence")))
  lockEnvironment(b, bindings = TRUE)
  gafsp_assert(b)
  b
}

gafsp_assert <- function(binding, factor = NULL, evidence = NULL, surrogate = NULL) {
  q <- gafsp_require
  q(is.null(factor), "projection proves identity/diagonal q only; correlated factors are unsupported")
  q(gafsp_locked(binding) && identical(parent.env(binding), emptyenv()) &&
    identical(binding$schema_version, "glofas_generated_AL_future_score_projection_v1") &&
    identical(binding$production_qualified, FALSE) && identical(binding$authentic_reads_authorized, FALSE),
    "locked generated-only projection binding required")
  q(is.null(evidence) || identical(evidence, binding$evidence), "evidence adapter or captured dependency changed")
  q(gafsp_locked(binding$private) && gafsp_locked(binding$callbacks) &&
    gafsp_locked(environment(binding$evidence)) &&
    identical(parent.env(binding$callbacks), binding$private) &&
    identical(parent.env(environment(binding$evidence)), binding$private), "adapter/source closure is not locked")
  q(identical(gafsp_sources(binding$source_root)$sha256, binding$source_sha256) &&
    identical(gafsp_hash(gafsp_private_code(binding$private)), binding$private_code_sha256),
    "source implementation fingerprint changed")
  q(identical(binding$callbacks$spec, binding$spec) && identical(binding$callbacks$fixture, binding$fixture) &&
    identical(gafsp_hash(list(gafsp_function_code(binding$callbacks$location),
      gafsp_function_code(binding$callbacks$member_location), gafsp_function_code(binding$evidence))),
      binding$callback_code_sha256), "generated location dependency changed")
  values <- as.list.environment(binding, all.names = TRUE)
  q(identical(gafsp_hash(gafsp_sorted_values(values, c("private", "callbacks", "evidence", "value_sha256"))),
    binding$value_sha256), "parameter roles, active coefficients/scales or fixture seal changed")
  q(identical(binding$active, as.integer(c(seq_len(binding$spec$p), unname(binding$spec$scales)))) &&
    identical(sort(c(binding$active, binding$auxiliary)), seq_len(binding$dimension)) &&
    !anyDuplicated(c(binding$active, binding$auxiliary)), "incomplete or unknown parameter roles")
  if (!is.null(surrogate)) gafsp_assert_control(surrogate, binding)
  invisible(TRUE)
}

# All H*51 path-independent AL normalizers plus the first-horizon check-loss
# contribution are integrated analytically. For H>1 this is a partial control.
gafsp_control_point <- function(eta) {
  decoded <- gcat_decode(eta, spec)
  if (is.null(fixture$members)) return(0)
  parameters <- list(coefficients = decoded$coefficients, sigma = decoded$sigma)
  mu <- member_location(1L, numeric(), parameters)
  sum(gic_al_log_density(fixture$members[1L, ], mu, spec$probability, decoded$sigma["G"])) +
    (fixture$horizon - 1L) * ncol(fixture$members) *
      (log(spec$probability) + log1p(-spec$probability) - eta[spec$scales["G"]])
}
gafsp_h1_moments <- function(binding, mean, log_sd) {
  spec <- binding$spec; p <- spec$dimension
  binding$private$gcat_vector(mean, spec); binding$private$gcat_vector(log_sd, spec)
  v <- exp(2 * log_sd)
  gafsp_require(all(is.finite(v)) && all(v > 0), "finite representable diagonal-q variances required")
  gm <- gs <- numeric(p); fixture <- binding$fixture
  if (is.null(fixture$members)) return(list(expected_value = 0, score_mean = gm, score_log_sd = gs))
  row <- numeric(spec$p)
  row[spec$blocks$beta$index] <- fixture$reference_features[1L, ]
  row[spec$blocks$alpha$index] <- fixture$discrepancy_features[1L, ]
  location <- sum(row * mean[seq_len(spec$p)]) + fixture$known_baseline[1L]
  variance <- sum(row^2 * v[seq_len(spec$p)])
  residual <- fixture$members[1L, ] - location
  if (variance > 0) {
    sd <- sqrt(variance); a <- residual / sd
    phi <- stats::dnorm(a); tail <- stats::pnorm(a, lower.tail = FALSE)
    loss <- sum(sd * phi + residual * (spec$probability - tail))
    D <- sum(spec$probability - tail)
    V <- sum(phi) / sd
  } else {
    gafsp_require(all(row == 0), "nonzero readout variance underflowed; no deterministic substitution permitted")
    loss <- sum(residual * (spec$probability - (residual < 0)))
    D <- V <- 0 # all feature coefficients are exactly zero in this case
  }
  si <- spec$scales["G"]; e <- exp(-mean[si] + .5 * v[si])
  M <- fixture$horizon * ncol(fixture$members)
  value <- M * (log(spec$probability) + log1p(-spec$probability) - mean[si]) - e * loss
  ci <- seq_len(spec$p)
  gm[ci] <- e * row * D; gs[ci] <- -v[ci] * row^2 * e * V
  gm[si] <- -M + e * loss; gs[si] <- -v[si] * e * loss
  gafsp_require(all(is.finite(c(value, gm, gs))), "nonfinite analytic control moments")
  list(expected_value = unname(value), score_mean = gm, score_log_sd = gs)
}
gafsp_full_control_point <- function(eta) {
  decoded <- gcat_decode(eta, spec)
  if (is.null(fixture$members)) return(0)
  parameters <- list(coefficients = decoded$coefficients, sigma = decoded$sigma)
  sum(vapply(seq_len(fixture$horizon), function(h) {
    past <- if (h == 1L) numeric() else anchor_path[seq_len(h - 1L)]
    mu <- member_location(h, past, parameters)
    sum(gic_al_log_density(fixture$members[h, ], mu, spec$probability, decoded$sigma["G"]))
  }, numeric(1L)))
}
gafsp_full_h_moments <- function(binding, mean, log_sd, anchor_path) {
  fixture <- binding$fixture
  value <- 0; gm <- gs <- numeric(binding$dimension)
  for (h in seq_len(fixture$horizon)) {
    # Source-controlled affine continuation gives exactly this deterministic
    # offset when evaluated at the separately declared frozen control path.
    offset <- fixture$known_baseline[h] + if (h == 1L) 0 else
      (fixture$reference_lag + fixture$discrepancy_lag) * anchor_path[h - 1L]
    single <- list(spec = binding$spec, private = binding$private,
      fixture = list(reference_features = fixture$reference_features[h, , drop = FALSE],
        discrepancy_features = fixture$discrepancy_features[h, , drop = FALSE],
        known_baseline = offset, members = if (is.null(fixture$members)) NULL else
          fixture$members[h, , drop = FALSE], horizon = 1L))
    moments <- gafsp_h1_moments(single, mean, log_sd)
    value <- value + moments$expected_value
    gm <- gm + moments$score_mean; gs <- gs + moments$score_log_sd
  }
  list(expected_value = value, score_mean = gm, score_log_sd = gs)
}
gafsp_control_code_guard <- function() {
  # Reviewed template identities are independent of a factory's mutable
  # caller namespace. A rebound evaluator/moment helper cannot self-certify.
  expected <- c(point = "e9ff022868bee2cf5a0452469b44d02b23f8bb148d38e03eaf559f43c8c53175",
    moments = "bf57aeb374f699db17c8ac4cff8d47b39d944d2a859508a24c71cd15c9727e67",
    full_point = "0d5aed103997cd29be129810ecf07fd4a480884e008fd10d74da299fbeda2bcc",
    full_moments = "aeeacc80badc814d6b2aaac6bdd14b1c9e540fdb20b99695b298bf1b807e5e69")
  actual <- c(point = gafsp_hash(gafsp_function_code(gafsp_control_point)),
    moments = gafsp_hash(gafsp_function_code(gafsp_h1_moments)),
    full_point = gafsp_hash(gafsp_function_code(gafsp_full_control_point)),
    full_moments = gafsp_hash(gafsp_function_code(gafsp_full_h_moments)))
  gafsp_require(identical(actual, expected), "reviewed control evaluator/moment source fingerprint changed")
  invisible(TRUE)
}
gafsp_control_identity <- function(binding, kind = "first_horizon", anchor_path = NULL) gafsp_hash(list(
  type = kind, frozen_control_path = anchor_path,
  target_value_sha256 = binding$value_sha256,
  evaluate_code = gafsp_function_code(if (kind == "first_horizon") gafsp_control_point else gafsp_full_control_point)))

gafsp_first_horizon_control <- function(binding) {
  gafsp_control_code_guard()
  gafsp_assert(binding)
  state <- new.env(parent = binding$private)
  state$spec <- binding$spec; state$fixture <- binding$fixture
  state$member_location <- binding$callbacks$member_location
  point <- gafsp_control_point; environment(point) <- state
  lockEnvironment(state, bindings = TRUE)
  factory_state <- new.env(parent = environment(gafsp_first_horizon_control))
  factory_state$binding <- binding; factory_state$point <- point
  factory <- eval(quote(function(mean, log_sd, factor = NULL) {
    gafsp_control_code_guard()
    gafsp_assert(binding, factor = factor)
    moments <- gafsp_h1_moments(binding, mean, log_sd)
    cv <- c(list(evaluate = point), moments, list(freeze_policy = "exact_control",
      moment_scope = "partial_outer_score_holding_control_fixed",
      source_identity = gafsp_control_identity(binding)))
    token <- new.env(parent = emptyenv())
    list2env(list(binding = binding, evaluate = point, mean = mean, log_sd = log_sd,
      kind = "first_horizon", anchor_path = NULL), token)
    lockEnvironment(token, bindings = TRUE)
    attr(cv, "gafsp_control_token") <- token
    cv
  }), envir = factory_state)
  lockEnvironment(factory_state, bindings = TRUE)
  factory
}
gafsp_full_frozen_design_control <- function(binding, anchor_path = rep(0, binding$fixture$horizon)) {
  gafsp_control_code_guard(); gafsp_assert(binding)
  gafsp_require(is.numeric(anchor_path) && length(anchor_path) == binding$fixture$horizon &&
    all(is.finite(anchor_path)) && is.null(attributes(anchor_path)),
    "plain finite generated control path must be frozen before the evaluation batch")
  state <- new.env(parent = binding$private)
  state$spec <- binding$spec; state$fixture <- binding$fixture
  state$member_location <- binding$callbacks$member_location; state$anchor_path <- anchor_path
  point <- gafsp_full_control_point; environment(point) <- state
  lockEnvironment(state, bindings = TRUE)
  factory_state <- new.env(parent = environment(gafsp_full_frozen_design_control))
  factory_state$binding <- binding; factory_state$point <- point; factory_state$anchor_path <- anchor_path
  factory <- eval(quote(function(mean, log_sd, factor = NULL) {
    gafsp_control_code_guard(); gafsp_assert(binding, factor = factor)
    moments <- gafsp_full_h_moments(binding, mean, log_sd, anchor_path)
    cv <- c(list(evaluate = point), moments, list(freeze_policy = "independent_frozen_control",
      moment_scope = "partial_outer_score_holding_control_fixed",
      source_identity = gafsp_control_identity(binding, "full_frozen_design", anchor_path)))
    token <- new.env(parent = emptyenv())
    list2env(list(binding = binding, evaluate = point, mean = mean, log_sd = log_sd,
      kind = "full_frozen_design", anchor_path = anchor_path), token)
    lockEnvironment(token, bindings = TRUE)
    attr(cv, "gafsp_control_token") <- token
    cv
  }), envir = factory_state)
  lockEnvironment(factory_state, bindings = TRUE)
  factory
}
gafsp_assert_control <- function(cv, binding) {
  gafsp_control_code_guard()
  q <- gafsp_require
  keys <- c("evaluate", "expected_value", "score_mean", "score_log_sd", "freeze_policy", "moment_scope", "source_identity")
  token <- attr(cv, "gafsp_control_token", exact = TRUE)
  q(is.list(cv) && identical(names(cv), keys) && gafsp_locked(token) &&
    identical(parent.env(token), emptyenv()) && identical(token$binding, binding) &&
    identical(token$evaluate, cv$evaluate) && is.function(cv$evaluate),
    "surrogate dependency is not authenticated by the bound first-horizon factory")
  kind <- token$kind
  q(identical(kind, "first_horizon") || identical(kind, "full_frozen_design"), "unknown control dependency role")
  full <- identical(kind, "full_frozen_design")
  expected_keys <- c("spec", "fixture", "member_location", if (full) "anchor_path")
  state <- environment(cv$evaluate)
  q(gafsp_locked(state) && identical(parent.env(state), binding$private) &&
    identical(sort(ls(state, all.names = TRUE)), sort(expected_keys)) &&
    identical(state$spec, binding$spec) && identical(state$fixture, binding$fixture) &&
    identical(state$member_location, binding$callbacks$member_location) &&
    identical(gafsp_function_code(cv$evaluate), gafsp_function_code(if (full) gafsp_full_control_point else gafsp_control_point)),
    "surrogate code, captured values or active-only dependency changed")
  if (full) q(is.numeric(token$anchor_path) && length(token$anchor_path) == binding$fixture$horizon &&
    all(is.finite(token$anchor_path)) && is.null(attributes(token$anchor_path)) &&
    identical(state$anchor_path, token$anchor_path), "frozen control path changed")
  expected <- if (full) gafsp_full_h_moments(binding, token$mean, token$log_sd, token$anchor_path) else
    gafsp_h1_moments(binding, token$mean, token$log_sd)
  q(identical(cv$freeze_policy, if (full) "independent_frozen_control" else "exact_control") &&
    identical(cv$moment_scope, "partial_outer_score_holding_control_fixed") &&
    identical(cv$source_identity, gafsp_control_identity(binding, kind, token$anchor_path)) &&
    identical(cv$expected_value, expected$expected_value) &&
    identical(cv$score_mean, expected$score_mean) && identical(cv$score_log_sd, expected$score_log_sd) &&
    all(cv$score_mean[binding$auxiliary] == 0) && all(cv$score_log_sd[binding$auxiliary] == 0),
    "surrogate moments, source identity or RHS independence changed")
  invisible(TRUE)
}

gafsp_project_future <- function(gradient, binding, factor = NULL, evidence = NULL, surrogate = NULL) {
  gafsp_require(is.function(evidence), "actual evidence adapter must be supplied explicitly")
  gafsp_assert(binding, factor, evidence, surrogate)
  q <- gafsp_require; p <- binding$dimension; ix <- binding$auxiliary
  fields <- c(gradient_mean = p, gradient_log_sd = p, standardized_gradient_mean = p,
    mcse = 2L * p, standardized_mcse_mean = p)
  q(is.list(gradient) && all(names(fields) %in% names(gradient)) &&
    all(vapply(names(fields), function(n) is.numeric(gradient[[n]]) &&
      length(gradient[[n]]) == fields[[n]] && all(is.finite(gradient[[n]])), logical(1L))),
    "finite future-only gradients and Monte Carlo errors required")
  q(all(gradient$mcse >= 0) && all(gradient$standardized_mcse_mean >= 0), "nonnegative Monte Carlo errors required")
  gradient$gradient_mean[ix] <- gradient$gradient_log_sd[ix] <- 0
  gradient$standardized_gradient_mean[ix] <- gradient$standardized_mcse_mean[ix] <- 0
  gradient$mcse[c(ix, p + ix)] <- 0
  gradient$gradient <- c(gradient$gradient_mean, gradient$gradient_log_sd)
  if ("standardized_gradient" %in% names(gradient))
    gradient$standardized_gradient <- c(gradient$standardized_gradient_mean, gradient$gradient_log_sd)
  if ("standardized_mcse" %in% names(gradient))
    gradient$standardized_mcse <- c(gradient$standardized_mcse_mean, gradient$mcse[p + seq_len(p)])
  gradient$future_projection <- list(schema_version = binding$schema_version,
    active_dimensions = length(binding$active), integrated_dimensions = length(ix),
    future_only = TRUE, historical_gradients_untouched = TRUE,
    all_historical_parameters_remain_random = TRUE, production_qualified = FALSE)
  gradient
}
