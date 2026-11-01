# Integrated multistep quantiles from retained posterior draws. Additive only:
# no fitting, discovery of runtime caches, or launch authority is supplied here.

app_iqf_fail <- function(message) stop(message, call. = FALSE)
app_iqf_require <- function(condition, message) {
  if (!isTRUE(condition)) app_iqf_fail(message)
  invisible(TRUE)
}
app_iqf_hash <- function(x, file = FALSE) {
  app_iqf_require(requireNamespace("digest", quietly = TRUE), "digest is required.")
  if (file) digest::digest(file = x, algo = "sha256", serialize = FALSE) else
    digest::digest(x, algo = "sha256", serialize = TRUE, serializeVersion = 2L)
}
app_iqf_contract <- function() list(
  schema_version = "integrated_quantile_forecast_v1",
  functional = "parameter_conditional_integrated_quantile",
  pooled_functional = "posterior_predictive_quantile",
  integration = "terminal_conditional_cdf",
  truth_policy = "observed_prefix_only_scoring_sidecar_separate",
  rng = "sha256_scientific_identity_draw_origin_inner_horizon_purpose_v1",
  mq_response_law = "equal_weight_isotonic_linear_grid_endpoint_atoms",
  allow_launch = FALSE
)

# Each stream is independent of task routing, host, draw block and requested L.
# Restoring RNGkind as well as .Random.seed leaves the caller's stream untouched.
app_iqf_seed <- function(rng_namespace, draw_id, origin_id, inner, horizon, purpose) {
  key <- list(version = 1L, scientific_identity = as.character(rng_namespace),
    draw = as.character(draw_id), origin = as.character(origin_id),
    inner = as.character(inner), horizon = as.character(horizon),
    purpose = as.character(purpose))
  app_iqf_require(all(lengths(key) == 1L) && all(nzchar(unlist(key))), "Invalid RNG identity.")
  # Use 168 hash bits to initialize all six valid CMRG state words. A single
  # 31-bit set.seed value would cause appreciable stream collisions in a large
  # nested calculation. These positive words lie inside both CMRG moduli.
  hex <- app_iqf_hash(key)
  vapply(seq_len(6L), function(j)
    as.integer(strtoi(substr(hex, 7L * (j - 1L) + 1L, 7L * j), 16L)) + 1L, integer(1L))
}
app_iqf_rng <- function(seed, fun) {
  old_kind <- RNGkind()
  had_seed <- exists(".Random.seed", .GlobalEnv, inherits = FALSE)
  old_seed <- if (had_seed) get(".Random.seed", .GlobalEnv) else NULL
  on.exit({
    do.call(RNGkind, as.list(old_kind))
    if (had_seed) assign(".Random.seed", old_seed, .GlobalEnv) else
      if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
  })
  RNGkind("L'Ecuyer-CMRG", "Inversion", "Rejection")
  app_iqf_require(length(seed) == 6L && all(is.finite(seed)) && all(seed > 0L), "Invalid CMRG state.")
  set.seed(1L)
  assign(".Random.seed", c(get(".Random.seed", .GlobalEnv)[1L], as.integer(seed)), .GlobalEnv)
  fun()
}

app_iqf_grid <- function(q, tau) {
  q <- as.numeric(q); tau <- as.numeric(tau)
  app_iqf_require(length(q) == length(tau) && length(q) >= 2L &&
    all(is.finite(c(q, tau))) && all(diff(tau) > 0) && min(tau) > 0 && max(tau) < 1,
    "Invalid MQ grid.")
  # This is the existing study's equal-weight isotonic action, not sorting or
  # score-weighted projection. Do not substitute another response law by model.
  if (any(diff(q) < 0)) q <- stats::isoreg(seq_along(q), q)$yf
  list(q = as.numeric(q), tau = tau)
}
app_iqf_mq_grid_inverse <- function(q, tau, u) {
  grid <- app_iqf_grid(q, tau); q <- grid$q; tau <- grid$tau
  app_iqf_require(all(is.finite(u)) && all(u >= 0 & u <= 1), "Invalid grid uniforms.")
  stats::approx(tau, q, xout = pmax(tau[1L], pmin(tail(tau, 1L), u)),
    ties = "ordered", rule = 2L)$y
}
app_iqf_mq_grid_cdf <- function(y, q, tau) {
  grid <- app_iqf_grid(q, tau); q <- grid$q; tau <- grid$tau
  vapply(as.numeric(y), function(value) {
    if (value < q[1L]) return(0)
    if (value >= tail(q, 1L)) return(1)
    # Largest equal knot includes all probability mass on a flat segment.
    k <- max(which(q <= value))
    if (value == q[k]) return(tau[k])
    tau[k] + (tau[k + 1L] - tau[k]) * (value - q[k]) / (q[k + 1L] - q[k])
  }, numeric(1L))
}

app_iqf_error_constants <- function(family, tau, gamma = 0) {
  family <- tolower(family)
  app_iqf_require(length(tau) == 1L && is.finite(tau) && tau > 0 && tau < 1,
    "Error probability must be scalar and interior.")
  if (family == "normal") return(list(A = 0, B = 1, lambda = 0, p_gamma = tau))
  if (family == "al") return(list(A = (1 - 2 * tau) / (tau * (1 - tau)),
    B = 2 / (tau * (1 - tau)), lambda = 0, p_gamma = tau))
  app_iqf_require(family == "exal" && exists("app_joint_exqdesn_constants", mode = "function"),
    "exAL requires the authenticated native scale-shape helper; no substitute is permitted.")
  as.list(app_joint_exqdesn_constants(tau, gamma)[1L, ])
}
app_iqf_error_noise <- function(family, tau, sigma, gamma, seed) {
  app_iqf_require(length(sigma) == 1L && is.finite(sigma) && sigma > 0,
    "A paired positive scale draw is required.")
  cst <- app_iqf_error_constants(family, tau, gamma)
  app_iqf_rng(seed, function() {
    if (tolower(family) == "normal") return(list(error = stats::rnorm(1L, sd = sigma)))
    s <- abs(stats::rnorm(1L)); v <- stats::rexp(1L, rate = 1 / sigma); z <- stats::rnorm(1L)
    list(error = sigma * cst$lambda * s + cst$A * v + sqrt(sigma * cst$B * v) * z,
      s = s, v = v, z = z)
  })
}
app_iqf_al_cdf <- function(y, mu, sigma, p) {
  z <- (y - mu) / sigma
  ifelse(z < 0, p * exp((1 - p) * z), 1 - (1 - p) * exp(-p * z))
}
app_iqf_error_cdf <- function(y, mu, sigma, family, tau, gamma = 0) {
  family <- tolower(family)
  if (family == "normal") return(stats::pnorm(y, mean = mu, sd = sigma))
  cst <- app_iqf_error_constants(family, tau, gamma)
  if (family == "al" || gamma == 0) return(app_iqf_al_cdf(y, mu, sigma, cst$p_gamma))
  # Integrate the *normalized* native half-normal augmentation. This is not
  # the fitted VB scale-shape quadrature and does not replace paired draws.
  vapply(as.numeric(y), function(value) stats::integrate(function(s)
    app_iqf_al_cdf(value, mu + sigma * cst$lambda * s, sigma, cst$p_gamma) *
      2 * stats::dnorm(s), lower = 0, upper = Inf, rel.tol = 1e-8,
      abs.tol = 1e-10, stop.on.error = TRUE)$value, numeric(1L))
}

app_iqf_kernel_cdf <- function(y, kernel) {
  if (kernel$family == "mq_grid") return(app_iqf_mq_grid_cdf(y, kernel$q, kernel$tau))
  app_iqf_error_cdf(y, kernel$mu, kernel$sigma, kernel$family, kernel$tau, kernel$gamma)
}
app_iqf_mixture_cdf <- function(y, kernels) {
  app_iqf_require(length(kernels) > 0L, "Cannot average an empty CDF collection.")
  families <- vapply(kernels, `[[`, character(1L), "family")
  if (length(unique(families)) == 1L && families[1L] != "mq_grid") {
    mu <- vapply(kernels, `[[`, numeric(1L), "mu")
    sigma <- vapply(kernels, `[[`, numeric(1L), "sigma")
    tau <- vapply(kernels, `[[`, numeric(1L), "tau")
    gamma <- vapply(kernels, `[[`, numeric(1L), "gamma")
    app_iqf_require(all(is.finite(c(mu, sigma, tau, gamma))) && all(sigma > 0),
      "Invalid paired terminal kernels.")
    if (families[1L] == "normal") return(vapply(y, function(value)
      mean(stats::pnorm(value, mu, sigma)), numeric(1L)))
    if (families[1L] == "al") return(vapply(y, function(value)
      mean(app_iqf_al_cdf(value, mu, sigma, tau)), numeric(1L)))
    # One outer draw has one paired scale/shape. Exchange two integrals,
    # not feature averaging: integrate the mean of conditional AL CDFs once.
    if (length(unique(sigma)) == 1L && length(unique(gamma)) == 1L && length(unique(tau)) == 1L) {
      cst <- app_iqf_error_constants("exal", tau[1L], gamma[1L])
      if (gamma[1L] == 0) return(vapply(y, function(value)
        mean(app_iqf_al_cdf(value, mu, sigma, tau)), numeric(1L)))
      return(vapply(y, function(value) stats::integrate(function(s) vapply(s, function(one)
        mean(app_iqf_al_cdf(value, mu + sigma * cst$lambda * one, sigma, cst$p_gamma)),
        numeric(1L)) * 2 * stats::dnorm(s), 0, Inf, rel.tol = 1e-8, abs.tol = 1e-10,
        stop.on.error = TRUE)$value, numeric(1L)))
    }
  }
  Reduce(`+`, lapply(kernels, function(k) app_iqf_kernel_cdf(y, k))) / length(kernels)
}
app_iqf_invert_cdf <- function(kernels, probabilities, tolerance = 1e-8) {
  app_iqf_require(all(is.finite(probabilities)) && all(probabilities > 0 & probabilities < 1) &&
    is.finite(tolerance) && tolerance > 0, "Invalid inversion settings.")
  # Bracket with actual support for grids, expanding for unbounded errors.
  centers <- unlist(lapply(kernels, function(k) if (k$family == "mq_grid") k$q else k$mu))
  app_iqf_require(all(is.finite(centers)), "Nonfinite terminal CDF kernel.")
  scale <- max(1, diff(range(centers)), unlist(lapply(kernels, function(k)
    if (is.null(k$sigma)) 1 else k$sigma)))
  low <- min(centers) - scale; high <- max(centers) + scale
  for (i in seq_len(80L)) {
    if (app_iqf_mixture_cdf(low, kernels) < min(probabilities) &&
        app_iqf_mixture_cdf(high, kernels) >= max(probabilities)) break
    scale <- scale * 2; low <- min(centers) - scale; high <- max(centers) + scale
  }
  app_iqf_require(is.finite(low) && is.finite(high) &&
    app_iqf_mixture_cdf(low, kernels) < min(probabilities) &&
    app_iqf_mixture_cdf(high, kernels) >= max(probabilities), "CDF inversion did not bracket.")
  vapply(probabilities, function(p) {
    a <- low; b <- high
    # Generalized inverse inf{y:F(y)>=p}; uniroot is incorrect at atoms.
    for (i in seq_len(250L)) {
      mid <- a + (b - a) / 2
      if (app_iqf_mixture_cdf(mid, kernels) >= p) b <- mid else a <- mid
      if (b - a <= tolerance) return(b)
    }
    app_iqf_fail("CDF inversion exhausted its accuracy budget.")
  }, numeric(1L))
}

app_iqf_validate_origins <- function(origins) {
  app_iqf_require(is.list(origins) && length(origins) > 0L && !is.null(names(origins)) &&
    !anyDuplicated(names(origins)), "Named unique origin prefixes are required.")
  for (origin in origins) {
    forbidden <- c("future_y", "y_future", "y_future_obs", "observed_y", "truth", "q_true")
    app_iqf_require(!any(names(origin) %in% forbidden), "Future truth is forbidden in predictor origins.")
    app_iqf_require(length(origin$origin_time) == 1L && origin$origin_time > 0 &&
      length(origin$history) == origin$origin_time && all(is.finite(origin$history)),
      "Origin history must end exactly at the observed cutoff; future values are forbidden.")
    app_iqf_require(length(origin$H) == 1L && is.finite(origin$H) && origin$H >= 1L &&
      origin$H == as.integer(origin$H), "Origin horizon is invalid.")
  }
  invisible(TRUE)
}
app_iqf_validate_draws <- function(posterior) {
  ids <- posterior$draw_ids
  app_iqf_require(is.character(ids) && length(ids) > 0L && !anyNA(ids) &&
    all(nzchar(ids)) && !anyDuplicated(ids), "Stable, unique original chain/draw IDs are required.")
  app_iqf_require(length(posterior$chain_id) == length(ids) &&
    length(posterior$source_draw_index) == length(ids), "Original chain/draw provenance is required.")
  invisible(TRUE)
}

# Metadata-only conversion of authentic worker CSVs to the native matrix schema.
# Explicit level-to-source mapping preserves a frozen product-posterior recipe;
# no new coupling/permutation is chosen here and no forecast path is generated.
app_iqf_materialize_mq_draws <- function(root, manifest, draw_mapping, p, tau,
    coupling_method) {
  required <- c("draw_id", "quantile_index", "chain_id", "source_draw_index", "source_relative_path")
  app_iqf_require(all(required %in% names(draw_mapping)) && nrow(draw_mapping) > 0L &&
    exists("app_joint_recursive_select_block", mode = "function"),
    "An explicit source draw mapping and native posterior-block decoder are required.")
  app_iqf_require(coupling_method %in% c("native_joint_posterior", "frozen_product_posterior_assembly"),
    "Unsupported cross-level assembly; do not invent a new coupling.")
  K <- length(tau); ids <- unique(as.character(draw_mapping$draw_id))
  app_iqf_require(!anyDuplicated(paste(draw_mapping$draw_id, draw_mapping$quantile_index)) &&
    all(draw_mapping$quantile_index %in% seq_len(K)) &&
    all(is.finite(draw_mapping$source_draw_index)) && all(draw_mapping$source_draw_index > 0) &&
    all(draw_mapping$source_draw_index == as.integer(draw_mapping$source_draw_index)) &&
    nrow(draw_mapping) == length(ids) * K, "Source mapping is not one complete K-grid per outer draw.")
  sources <- unique(as.character(draw_mapping$source_relative_path))
  blocks <- lapply(sources, function(relative) {
    j <- match(relative, manifest$relative_path)
    app_iqf_require(!is.na(j) && manifest$role[j] == "retained_posterior",
      "Worker posterior is not authenticated with the retained-posterior role.")
    path <- app_iqf_safe_path(root, relative)
    app_iqf_require(file.info(path)$size == manifest$size_bytes[j] &&
      identical(app_iqf_hash(path, TRUE), manifest$sha256[j]), "Worker posterior hash/size changed.")
    data <- utils::read.csv(path, stringsAsFactors = FALSE)
    beta <- app_joint_recursive_select_block(data, "beta")
    alpha <- app_joint_recursive_select_block(data, "alpha")
    app_iqf_require(ncol(beta) == p * K && ncol(alpha) == K &&
      all(is.finite(c(beta, alpha))), "Worker posterior dimensions differ from the native retained design.")
    list(beta = beta, alpha = alpha)
  }); names(blocks) <- sources
  beta <- matrix(NA_real_, length(ids), p * K); alpha <- matrix(NA_real_, length(ids), K)
  chain <- index <- vector("list", length(ids))
  for (j in seq_along(ids)) {
    map <- draw_mapping[draw_mapping$draw_id == ids[j], , drop = FALSE]
    map <- map[order(map$quantile_index), , drop = FALSE]
    if (coupling_method == "native_joint_posterior") app_iqf_require(
      length(unique(map$source_relative_path)) == 1L && length(unique(map$source_draw_index)) == 1L &&
        length(unique(map$chain_id)) == 1L, "Joint posterior levels must share the original correlated source row.")
    for (k in seq_len(K)) {
      source <- blocks[[map$source_relative_path[k]]]; row <- map$source_draw_index[k]
      app_iqf_require(row <= nrow(source$beta), "Mapped source draw is unavailable.")
      columns <- ((k - 1L) * p + 1L):(k * p)
      beta[j, columns] <- source$beta[row, columns]
      alpha[j, k] <- source$alpha[row, k]
    }
    chain[[j]] <- map$chain_id; index[[j]] <- map$source_draw_index
  }
  list(beta = beta, alpha = alpha, draw_ids = ids, chain_id = chain,
    source_draw_index = index, level_source_mapping = draw_mapping,
    draw_mapping_sha256 = app_iqf_hash(draw_mapping), coupling_method = coupling_method)
}

# The native MQ design is truncated *before* calling the historical snapshot
# helper. Thus teacher forcing reconstructs only an observed prefix, never a
# held-out future row. The readout and reservoir helpers remain unchanged.
app_iqf_desn_adapter <- function(design, posterior, origins, tau,
    family = "mq_grid", coupling = NULL, rng_namespace) {
  app_iqf_validate_origins(origins); app_iqf_validate_draws(posterior)
  family <- tolower(family); K <- length(tau); p <- ncol(design$Z)
  app_iqf_require(all(is.finite(posterior$beta)) && all(is.finite(posterior$alpha)) &&
    identical(dim(as.matrix(posterior$beta)), c(length(posterior$draw_ids), as.integer(p * K))) &&
    identical(dim(as.matrix(posterior$alpha)), c(length(posterior$draw_ids), as.integer(K))),
    "Native beta/alpha matrices do not match retained design and grid.")
  if (family == "mq_grid") {
    app_iqf_grid(rep(0, K), tau)
    app_iqf_require(is.list(coupling) && is.character(coupling$method) &&
      coupling$method %in% c("native_joint_posterior", "frozen_product_posterior_assembly") &&
      grepl("^[a-f0-9]{64}$", coupling$recipe_sha256) &&
      grepl("^[a-f0-9]{64}$", coupling$draw_mapping_sha256),
      "MQ requires its authenticated original cross-level coupling recipe and draw mapping.")
    if (!is.null(posterior$draw_mapping_sha256)) app_iqf_require(
      identical(posterior$draw_mapping_sha256, coupling$draw_mapping_sha256),
      "MQ assembly mapping differs from the frozen original coupling.")
  } else {
    app_iqf_require(K == 1L && family %in% c("al", "exal", "normal"),
      "Single-level native DESN family is unsupported.")
    app_iqf_require(length(posterior$sigma) == length(posterior$draw_ids) &&
      all(is.finite(posterior$sigma)) && all(posterior$sigma > 0) &&
      (family != "exal" || (length(posterior$gamma) == length(posterior$draw_ids) &&
        all(is.finite(posterior$gamma)))), "Paired native scale/shape draws are incomplete.")
  }
  needed <- c("app_joint_recursive_origin_snapshots", "app_joint_recursive_feature_from_history",
    "app_joint_recursive_readout_row", "app_joint_recursive_predict_vector")
  app_iqf_require(all(vapply(needed, exists, logical(1L), mode = "function")),
    "Authenticated native recursive DESN helpers must be loaded.")
  snapshots <- lapply(origins, function(origin) {
    keep <- design$row_meta$full_time_index <= origin$origin_time
    app_iqf_require(any(keep), "Origin precedes the retained native design.")
    prefix <- design
    prefix$row_meta <- design$row_meta[keep, , drop = FALSE]
    prefix$Z <- design$Z[keep, , drop = FALSE]
    prefix$forecast_map <- data.frame(origin_index = 1L,
      full_time_index = as.integer(origin$origin_time + 1L))
    fixture <- list(scenario_id = design$scenario_id, y = origin$history)
    if (!identical(design$feature_contract, "pure_recursive_v1")) {
      app_iqf_require(is.matrix(origin$observed_input_features) &&
        nrow(origin$observed_input_features) == origin$origin_time,
        "Historical input features must be an authenticated observed prefix.")
      fixture$Z <- origin$observed_input_features
    }
    selected <- data.frame(input_scale = if (is.null(design$reservoir_meta$win_scale_global)) 1 else
      design$reservoir_meta$win_scale_global)
    out <- app_joint_recursive_origin_snapshots(prefix, fixture, selected)
    app_iqf_require(is.finite(out$teacher_forced_max_abs_diff) &&
      out$teacher_forced_max_abs_diff <= 1e-8, "Native origin-state reconstruction differs from retained states.")
    out
  })
  path <- function(draw_id, origin_id, inner) {
    j <- match(draw_id, posterior$draw_ids); origin <- origins[[origin_id]]
    snapshot <- snapshots[[origin_id]]; states <- snapshot$states[[1L]]
    history <- origin$history; kernels <- vector("list", origin$H)
    responses <- numeric(origin$H)
    for (h in seq_len(origin$H)) {
      tt <- as.integer(origin$origin_time + h)
      raw <- app_joint_recursive_feature_from_history(tt, history, design)
      step <- app_joint_recursive_readout_row(raw, states, design, snapshot$reservoir_meta)
      states <- step$states
      mu <- app_joint_recursive_predict_vector(step$z, posterior$beta[j, ], posterior$alpha[j, ], tau)
      seed <- app_iqf_seed(rng_namespace, draw_id, origin_id, inner, h, "response")
      if (family == "mq_grid") {
        grid <- app_iqf_grid(mu, tau)
        kernels[[h]] <- list(family = "mq_grid", q = grid$q, tau = tau)
        responses[h] <- app_iqf_mq_grid_inverse(grid$q, tau,
          app_iqf_rng(seed, function() stats::runif(1L)))
      } else {
        sigma <- posterior$sigma[j]; gamma <- if (family == "exal") posterior$gamma[j] else 0
        kernels[[h]] <- list(family = family, mu = mu, sigma = sigma, gamma = gamma, tau = tau)
        responses[h] <- mu + app_iqf_error_noise(family, tau, sigma, gamma, seed)$error
      }
      history <- c(history, responses[h])
    }
    list(kernels = kernels, response = responses)
  }
  structure(list(path = path, draw_ids = posterior$draw_ids, origins = origins,
    rng_namespace = rng_namespace, posterior = posterior, adapter = "mq_desn_native_v1",
    outer_conditioning = "parameters_and_observed_origin_reservoir_state",
    coupling = coupling), class = "app_iqf_adapter")
}

# Single-quantile package fits use the native fitted model and recursion, with
# explicit paired draws and purpose-keyed noise. No fit is regenerated here.
app_iqf_load_native_kernels <- function(root, manifest, kernel_paths, native_version) {
  app_iqf_require(requireNamespace("exdqlm", quietly = TRUE) &&
    identical(as.character(utils::packageVersion("exdqlm")), native_version),
    "Authentic fitted-source exdqlm runtime version is unavailable; do not upgrade silently.")
  app_iqf_require(length(kernel_paths) > 0L && !anyDuplicated(kernel_paths),
    "An ordered authenticated native-kernel inventory is required.")
  environment <- new.env(parent = asNamespace("exdqlm"))
  hashes <- character(length(kernel_paths))
  for (j in seq_along(kernel_paths)) {
    row <- match(kernel_paths[j], manifest$relative_path)
    app_iqf_require(!is.na(row) && manifest$role[row] == "native_kernel",
      "Native kernel is not authenticated by the input manifest.")
    path <- app_iqf_safe_path(root, kernel_paths[j])
    app_iqf_require(file.info(path)$size == manifest$size_bytes[row] &&
      identical(app_iqf_hash(path, TRUE), manifest$sha256[row]), "Native kernel hash/size changed.")
    hashes[j] <- manifest$sha256[row]
    sys.source(path, envir = environment, keep.source = FALSE)
  }
  attr(environment, "iqf_native_version") <- native_version
  attr(environment, "iqf_native_kernels_sha256") <- app_iqf_hash(list(paths = kernel_paths, hashes = hashes))
  environment
}
app_iqf_single_desn_adapter <- function(object, posterior, origins, family, tau,
    rng_namespace, native_version, native_function_sha256, native_environment = NULL) {
  app_iqf_validate_origins(origins); app_iqf_validate_draws(posterior)
  app_iqf_require(requireNamespace("exdqlm", quietly = TRUE) &&
    identical(as.character(utils::packageVersion("exdqlm")), native_version),
    "Authentic fitted-source exdqlm version is unavailable; do not upgrade silently.")
  environment <- if (is.null(native_environment)) asNamespace("exdqlm") else native_environment
  if (!is.null(native_environment)) app_iqf_require(is.environment(native_environment) &&
    identical(attr(native_environment, "iqf_native_version"), native_version) &&
    grepl("^[a-f0-9]{64}$", attr(native_environment, "iqf_native_kernels_sha256")),
    "Sourced native helpers require a manifest-authenticated qualified environment.")
  fun <- get0("forecast_paths.qdesn_fit", envir = environment, mode = "function", inherits = TRUE)
  app_iqf_require(is.function(fun),
    "Authentic native forecast helper is unavailable; qualify the frozen sourced-kernel environment.")
  app_iqf_require(identical(app_iqf_hash(list(formals(fun), body(fun))), native_function_sha256) &&
    "noise_draws" %in% names(formals(fun)), "Native forecast helper hash or explicit-noise interface differs.")
  app_iqf_require(family %in% c("al", "exal") && length(tau) == 1L,
    "The native package single-level adapter supports authenticated AL/exAL fits only.")
  app_iqf_require(nrow(posterior$beta) == length(posterior$draw_ids) &&
    length(posterior$sigma) == length(posterior$draw_ids) &&
    (family != "exal" || length(posterior$gamma) == length(posterior$draw_ids)) &&
    all(is.finite(c(posterior$beta, posterior$sigma))) && all(posterior$sigma > 0) &&
    (family != "exal" || all(is.finite(posterior$gamma))) &&
    identical(as.numeric(object$fit$misc$p0), as.numeric(tau)),
    "Native paired beta/scale/shape draws are incomplete.")
  path <- function(draw_id, origin_id, inner) {
    j <- match(draw_id, posterior$draw_ids); o <- origins[[origin_id]]; H <- o$H
    app_iqf_require(!is.null(o$origin_state) && !is.null(o$readout_spec),
      "Authentic origin reservoir state and readout specification are required.")
    sigma <- posterior$sigma[j]; gamma <- if (family == "exal") posterior$gamma[j] else 0
    noise <- lapply(seq_len(H), function(h) app_iqf_error_noise(family, tau, sigma, gamma,
      app_iqf_seed(rng_namespace, draw_id, origin_id, inner, h, "response")))
    nd <- lapply(c("s", "v", "z"), function(nm) matrix(vapply(noise, `[[`, numeric(1L), nm), ncol = 1L))
    names(nd) <- c("s", "v", "z")
    old <- options(exdqlm.use_cpp_postpred = FALSE); on.exit(options(old))
    result <- fun(object, H = H, nd = 1L, method = "recursive", y_hist = o$history,
      xreg_hist = o$xreg_hist, xreg_future = o$xreg_future,
      y_future_obs = rep(NA_real_, H), origin_state = o$origin_state,
      readout_spec = o$readout_spec, res_lag_init = o$res_lag_init,
      origin_index = o$origin_time, draws = list(beta = posterior$beta[j, , drop = FALSE],
        sigma = sigma, gamma = gamma), noise_draws = nd, cpp_fallback_note = FALSE)
    app_iqf_require(all(is.finite(c(result$yrep, result$mu_draws))), "Native recursion returned nonfinite paths.")
    list(response = as.numeric(result$yrep), kernels = lapply(seq_len(H), function(h)
      list(family = family, mu = result$mu_draws[h, 1L], sigma = sigma, gamma = gamma, tau = tau)))
  }
  structure(list(path = path, draw_ids = posterior$draw_ids, origins = origins,
    rng_namespace = rng_namespace, posterior = posterior, adapter = "single_qdesn_fit_native_v1",
    outer_conditioning = "parameters_and_observed_origin_reservoir_state"),
    class = "app_iqf_adapter")
}

app_iqf_psd_factor <- function(covariance) {
  covariance <- as.matrix(covariance)
  app_iqf_require(nrow(covariance) == ncol(covariance) && all(is.finite(covariance)) &&
    max(abs(covariance - t(covariance))) < 1e-10, "State covariance must be finite and symmetric.")
  e <- eigen(covariance, symmetric = TRUE)
  app_iqf_require(min(e$values) >= -1e-12 * max(1, max(abs(e$values))),
    "State covariance is not positive semidefinite.")
  e$vectors %*% diag(sqrt(pmax(0, e$values)), nrow = length(e$values))
}
# Conditional filtered distributions MUST be paired with retained parameter
# draws. Discount-derived W must be materialized by its authentic source filter,
# not replaced by a constant or reconstructed from a posterior point estimate.
app_iqf_state_conditioning <- function(model, origins) {
  kinds <- unlist(lapply(origins, function(o) vapply(o$conditional_state,
    function(s) if (is.null(s$kind)) "missing" else as.character(s$kind), character(1L))), use.names = FALSE)
  app_iqf_require(length(kinds) > 0L && all(kinds %in% c("conditional_gaussian", "joint_retained_draw")),
    "Point-state fallback is forbidden; authentic conditional Gaussian or joint retained states are required.")
  app_iqf_require(length(unique(kinds)) == 1L,
    "Cannot mix outer-conditioning conventions across retained draws or forecast origins.")
  convention <- if (kinds[1L] == "conditional_gaussian")
    "parameters_only_integrate_filtered_origin_state" else "parameters_and_joint_retained_origin_state"
  app_iqf_require(identical(model$outer_conditioning, convention),
    "Bundle model must freeze its explicit outer-conditioning convention before execution.")
  convention
}
app_iqf_state_space_adapter <- function(model, posterior, origins, rng_namespace) {
  app_iqf_validate_origins(origins); app_iqf_validate_draws(posterior)
  outer_conditioning <- app_iqf_state_conditioning(model, origins)
  app_iqf_require(model$family %in% c("normal", "al", "exal") &&
    identical(model$state_conditioning, "per_parameter_draw") &&
    model$state_evolution %in% c("known_G_W", "authenticated_discount_G_W"),
    "A source-authenticated parameter-conditional DQLM state law is required.")
  app_iqf_require(grepl("^[a-f0-9]{64}$", model$state_source_sha256) &&
    grepl("^[a-f0-9]{64}$", model$evolution_source_sha256),
    "Baseline filter/evolution evidence hashes are required.")
  n <- length(posterior$draw_ids)
  app_iqf_require(length(posterior$sigma) == n && all(is.finite(posterior$sigma)) &&
    all(posterior$sigma > 0) && (model$family != "exal" || (length(posterior$gamma) == n &&
      all(is.finite(posterior$gamma)))),
    "Paired baseline scale/shape draws are incomplete.")
  app_iqf_error_constants(model$family, model$tau,
    if (model$family == "exal") posterior$gamma[1L] else 0)
  for (o in origins) {
    app_iqf_require(length(o$conditional_state) == n && length(o$future_G) == n &&
      length(o$future_W) == n && length(o$future_F) == n,
      "Baseline origin states and future G/F/W are required for every original parameter draw.")
    for (j in seq_len(n)) {
      state <- o$conditional_state[[j]]
      if (identical(state$kind, "conditional_gaussian")) {
        app_iqf_require(length(state$mean) > 0 && all(is.finite(state$mean)), "Missing filtered state mean.")
        factor <- app_iqf_psd_factor(state$covariance)
        app_iqf_require(nrow(factor) == length(state$mean), "Filtered-state covariance dimension differs.")
      } else app_iqf_require(identical(state$kind, "joint_retained_draw") &&
        all(is.finite(state$value)) && length(state$value) > 0,
        "Point-state fallback is forbidden; supply authentic filtered covariance or joint state draw.")
      app_iqf_require(length(o$future_G[[j]]) == o$H && length(o$future_W[[j]]) == o$H &&
        length(o$future_F[[j]]) == o$H, "Baseline future evolution horizon differs.")
      for (h in seq_len(o$H)) app_iqf_psd_factor(o$future_W[[j]][[h]])
    }
  }
  path <- function(draw_id, origin_id, inner) {
    j <- match(draw_id, posterior$draw_ids); o <- origins[[origin_id]]; state <- o$conditional_state[[j]]
    seed <- function(h, purpose) app_iqf_seed(rng_namespace, draw_id, origin_id, inner, h, purpose)
    theta <- if (state$kind == "joint_retained_draw") state$value else
      state$mean + as.numeric(app_iqf_psd_factor(state$covariance) %*%
        app_iqf_rng(seed(0L, "origin_state"), function() stats::rnorm(length(state$mean))))
    kernels <- vector("list", o$H); responses <- numeric(o$H)
    for (h in seq_len(o$H)) {
      G <- as.matrix(o$future_G[[j]][[h]]); F <- as.numeric(o$future_F[[j]][[h]])
      W <- app_iqf_psd_factor(o$future_W[[j]][[h]])
      app_iqf_require(ncol(G) == length(theta) && nrow(G) == length(F) && nrow(W) == length(F),
        "Baseline G/F/W dimensions differ from retained state.")
      theta <- as.numeric(G %*% theta + W %*%
        app_iqf_rng(seed(h, "state_innovation"), function() stats::rnorm(nrow(W))))
      mu <- sum(F * theta); gamma <- if (model$family == "exal") posterior$gamma[j] else 0
      kernels[[h]] <- list(family = model$family, mu = mu, sigma = posterior$sigma[j],
        gamma = gamma, tau = model$tau)
      responses[h] <- mu + app_iqf_error_noise(model$family, model$tau, posterior$sigma[j],
        gamma, seed(h, "response"))$error
    }
    list(kernels = kernels, response = responses)
  }
  structure(list(path = path, draw_ids = posterior$draw_ids, origins = origins,
    rng_namespace = rng_namespace, posterior = posterior, adapter = "state_space_conditional_v1",
    outer_conditioning = outer_conditioning),
    class = "app_iqf_adapter")
}

# Stream exactly one complete outer draw/origin at a time. The terminal CDF
# components are retained so pooled posterior predictive quantiles are formed
# by pooling CDFs, never by averaging the parameter-conditional quantiles.
app_iqf_run_task <- function(adapter, draw_id, origin_id, inner_paths, probabilities,
    model_id, tolerance = 1e-8, include_paths = FALSE, diagnose_integration = FALSE,
    max_kernel_bytes = Inf, mc_confidence_alpha = NULL) {
  app_iqf_require(inherits(adapter, "app_iqf_adapter") && draw_id %in% adapter$draw_ids &&
    origin_id %in% names(adapter$origins), "Task draw/origin is absent from authenticated adapter.")
  app_iqf_require(length(inner_paths) == 1L && is.finite(inner_paths) && inner_paths >= 1L &&
    inner_paths == as.integer(inner_paths), "Inner integration resolution is invalid.")
  inner_paths <- as.integer(inner_paths)
  app_iqf_require(length(probabilities) > 0L && all(diff(probabilities) > 0),
    "Quantile probabilities must be unique and strictly increasing.")
  if (diagnose_integration) app_iqf_require(inner_paths >= 2L,
    "Split-stream integration assessment needs at least two paths.")
  if (!is.null(mc_confidence_alpha)) app_iqf_require(
    length(mc_confidence_alpha) == 1L && is.finite(mc_confidence_alpha) &&
      mc_confidence_alpha > 0 && mc_confidence_alpha < 1, "DKW confidence budget is invalid.")
  H <- adapter$origins[[origin_id]]$H
  # Conservative R-list allocation estimate; measured RSS qualification remains
  # mandatory in the external controller. Do not treat this as a memory grant.
  estimated_kernel_bytes <- as.double(H) * inner_paths * (2048 + 8 * length(probabilities))
  app_iqf_require(estimated_kernel_bytes <= max_kernel_bytes,
    "Terminal CDF collection exceeds the admitted kernel-memory budget.")
  kernels <- lapply(seq_len(H), function(h) vector("list", inner_paths))
  paths <- if (include_paths || !is.null(mc_confidence_alpha)) matrix(NA_real_, inner_paths, H) else NULL
  for (inner in seq_len(inner_paths)) {
    result <- adapter$path(draw_id, origin_id, inner)
    app_iqf_require(length(result$kernels) == H && length(result$response) == H &&
      all(is.finite(result$response)), "Adapter returned an incomplete or nonfinite trajectory.")
    for (h in seq_len(H)) kernels[[h]][[inner]] <- result$kernels[[h]]
    if (!is.null(paths)) paths[inner, ] <- result$response
  }
  rows <- do.call(rbind, lapply(seq_len(H), function(h) data.frame(model_id = model_id,
    draw_id = draw_id, origin_id = origin_id, horizon = h, probability = probabilities,
    quantile = app_iqf_invert_cdf(kernels[[h]], probabilities, tolerance),
    functional = app_iqf_contract()$functional, inner_paths = inner_paths,
    outer_conditioning = adapter$outer_conditioning,
    rng_namespace = adapter$rng_namespace, stringsAsFactors = FALSE)))
  diagnostic <- NULL
  if (diagnose_integration) {
    half <- floor(inner_paths / 2L)
    diagnostic <- do.call(rbind, lapply(seq_len(H), function(h) {
      left <- app_iqf_invert_cdf(kernels[[h]][seq_len(half)], probabilities, tolerance)
      right <- app_iqf_invert_cdf(kernels[[h]][seq.int(half + 1L, inner_paths)], probabilities, tolerance)
      data.frame(horizon = h, probability = probabilities,
        split_stream_absolute_difference = abs(left - right),
        split_stream_relative_difference = abs(left - right) / pmax(1, abs((left + right) / 2)),
        left_paths = half, right_paths = inner_paths - half, inversion_tolerance = tolerance)
    }))
  }
  dkw <- NULL
  if (!is.null(mc_confidence_alpha)) {
    epsilon <- sqrt(log(2 * H / mc_confidence_alpha) / (2 * inner_paths))
    dkw <- do.call(rbind, lapply(seq_len(H), function(h) {
      lower <- vapply(probabilities, function(p) if (p - epsilon <= 0) -Inf else
        stats::quantile(paths[, h], p - epsilon, type = 1L, names = FALSE), numeric(1L))
      upper <- vapply(probabilities, function(p) if (p + epsilon >= 1) Inf else
        stats::quantile(paths[, h], p + epsilon, type = 1L, names = FALSE), numeric(1L))
      estimate <- rows$quantile[rows$horizon == h]
      data.frame(horizon = h, probability = probabilities, lower = lower, upper = upper,
        max_estimate_error_bound = pmax(abs(estimate - lower), abs(upper - estimate)),
        empirical_cdf_epsilon = epsilon, alpha_per_draw_origin = mc_confidence_alpha,
        scope = "one_parameter_draw_origin_simultaneous_horizons_and_probabilities")
    }))
  }
  j <- match(draw_id, adapter$posterior$draw_ids)
  list(schema_version = "integrated_quantile_forecast_shard_v1", quantiles = rows,
    cdf_components = kernels, paths = if (include_paths) paths else NULL,
    identity = list(outer_conditioning = adapter$outer_conditioning),
    original_draw = list(chain_id = adapter$posterior$chain_id[j],
      source_draw_index = adapter$posterior$source_draw_index[j]),
    draw_id = draw_id, origin_id = origin_id,
    model_id = model_id, rng_namespace = adapter$rng_namespace,
    outer_conditioning = adapter$outer_conditioning,
    integration_resolution = inner_paths, integration_diagnostic = diagnostic,
    integration_dkw = dkw, estimated_kernel_bytes = estimated_kernel_bytes)
}
app_iqf_posterior_predictive <- function(shards, probabilities, tolerance = 1e-8) {
  app_iqf_require(length(shards) > 0L &&
    length(unique(vapply(shards, `[[`, character(1L), "origin_id"))) == 1L &&
    length(unique(vapply(shards, `[[`, character(1L), "model_id"))) == 1L &&
    !anyDuplicated(vapply(shards, `[[`, character(1L), "draw_id")) &&
    length(unique(vapply(shards, `[[`, integer(1L), "integration_resolution"))) == 1L,
    "Pooled CDF requires unique outer draws, one model/origin and equal inner resolution.")
  fields <- c("source_commit", "source_tree", "source_manifest_sha256", "posterior_target_sha256",
    "input_manifest_sha256", "task_manifest_sha256", "rng_namespace", "outer_conditioning")
  reference_identity <- shards[[1L]]$identity[fields]
  app_iqf_require(length(reference_identity) == length(fields) &&
    identical(names(reference_identity), fields) && all(vapply(reference_identity,
      function(x) is.character(x) && length(x) == 1L && nzchar(x), logical(1L))),
    "Pooled CDF requires complete immutable source/target/input/RNG identity.")
  H <- length(shards[[1L]]$cdf_components)
  L <- shards[[1L]]$integration_resolution
  app_iqf_require(H >= 1L && is.finite(L) && L >= 1L && L == as.integer(L),
    "CDF components are absent; quantiles-only shards require a separate bounded pooled-CDF workflow.")
  reference_operator <- NULL
  for (shard in shards) {
    app_iqf_require(identical(shard$schema_version, "integrated_quantile_forecast_shard_v1") &&
      identical(shard$identity[fields], reference_identity) &&
      identical(shard$rng_namespace, reference_identity$rng_namespace) &&
      identical(shard$outer_conditioning, reference_identity$outer_conditioning),
      "Cannot pool mixed scientific source/target/input/RNG operators.")
    app_iqf_require(is.list(shard$cdf_components) && length(shard$cdf_components) == H &&
      all(lengths(shard$cdf_components) == L) &&
      setequal(unique(shard$quantiles$horizon), seq_len(H)),
      "Pooled CDF shard has incomplete horizon or inner-kernel membership.")
    for (h in seq_len(H)) for (kernel in shard$cdf_components[[h]]) {
      app_iqf_require(is.list(kernel) && is.character(kernel$family) && length(kernel$family) == 1L &&
        kernel$family %in% c("mq_grid", "normal", "al", "exal"), "Malformed pooled CDF kernel.")
      if (kernel$family == "mq_grid") {
        grid <- app_iqf_grid(kernel$q, kernel$tau)
        app_iqf_require(identical(grid$q, as.numeric(kernel$q)),
          "Stored grid kernel is not the already-ordered frozen response law.")
        operator <- list(family = kernel$family, tau = as.numeric(kernel$tau))
      } else {
        app_iqf_require(all(lengths(kernel[c("mu", "sigma", "gamma", "tau")]) == 1L) &&
          all(is.finite(unlist(kernel[c("mu", "sigma", "gamma", "tau")]))) && kernel$sigma > 0,
          "Nonfinite or incomplete pooled likelihood kernel.")
        app_iqf_error_constants(kernel$family, kernel$tau, kernel$gamma)
        operator <- list(family = kernel$family, tau = as.numeric(kernel$tau))
      }
      if (is.null(reference_operator)) reference_operator <- operator
      app_iqf_require(identical(operator, reference_operator),
        "Pooled CDF components mix response laws or probability grids.")
    }
  }
  do.call(rbind, lapply(seq_len(H), function(h) data.frame(horizon = h,
    probability = probabilities, quantile = app_iqf_invert_cdf(
      unlist(lapply(shards, function(s) s$cdf_components[[h]]), recursive = FALSE),
      probabilities, tolerance), functional = app_iqf_contract()$pooled_functional,
    numerical_accuracy = "requires_separate_pooled_quantile_accuracy_contract")))
}

app_iqf_aggregate_scores <- function(blocks, expected_keys) {
  x <- do.call(rbind, blocks)
  key_fields <- c("model_id", "draw_id", "origin_id", "horizon")
  required <- c(key_fields, "source_manifest_sha256", "posterior_target_sha256", "outer_conditioning",
    "score_sum", "score_count")
  app_iqf_require(all(required %in% names(x)) && nrow(x) > 0L, "Score block schema is incomplete.")
  keys <- do.call(paste, c(x[key_fields], sep = "|"))
  app_iqf_require(!anyDuplicated(keys) && !anyDuplicated(expected_keys) &&
    setequal(keys, expected_keys), "Duplicate/missing/unexpected origin-horizon score blocks.")
  app_iqf_require(all(is.finite(x$score_sum)) && all(is.finite(x$score_count)) &&
    all(x$score_count > 0), "Score sum/count must be finite with positive counts.")
  app_iqf_require(length(unique(x$source_manifest_sha256)) == 1L,
    "Cannot aggregate mixed source manifests.")
  # Deterministic summation order is independent of shard arrival/host routing.
  x <- x[do.call(order, x[key_fields]), , drop = FALSE]
  by_model <- split(x, x$model_id)
  app_iqf_require(all(vapply(by_model, function(z) length(unique(z$posterior_target_sha256)) == 1L,
    logical(1L))), "Cannot aggregate mixed posterior targets within a model.")
  app_iqf_require(is.character(x$outer_conditioning) && !anyNA(x$outer_conditioning) &&
    all(nzchar(x$outer_conditioning)) && all(vapply(by_model,
      function(z) length(unique(z$outer_conditioning)) == 1L, logical(1L))),
    "Cannot aggregate mixed outer-conditioning conventions within a model.")
  totals <- stats::aggregate(x[c("score_sum", "score_count")],
    x[c("model_id", "draw_id", "outer_conditioning")], sum)
  totals$score <- totals$score_sum / totals$score_count
  summaries <- do.call(rbind, lapply(split(totals, totals$model_id), function(z) data.frame(
    model_id = z$model_id[1L], outer_conditioning = z$outer_conditioning[1L],
    mean = mean(z$score), median = stats::median(z$score),
    lower = stats::quantile(z$score, .025, names = FALSE),
    upper = stats::quantile(z$score, .975, names = FALSE), n_outer_draws = nrow(z))))
  list(draw_scores = totals, summary = summaries)
}
app_iqf_contrasts <- function(draw_scores, pairing) {
  app_iqf_require(is.data.frame(pairing) && all(c("pair_id", "left_model", "left_draw_id",
    "right_model", "right_draw_id", "pairing_contract_sha256") %in% names(pairing)) &&
    nrow(pairing) > 0L && !anyDuplicated(pairing$pair_id) &&
    length(unique(pairing$pairing_contract_sha256)) == 1L &&
    grepl("^[a-f0-9]{64}$", pairing$pairing_contract_sha256[1L]),
    "Explicit unique between-model pairing contract is required.")
  key <- paste(draw_scores$model_id, draw_scores$draw_id, sep = "|")
  app_iqf_require(!anyDuplicated(key), "Draw score keys are duplicated.")
  left <- match(paste(pairing$left_model, pairing$left_draw_id, sep = "|"), key)
  right <- match(paste(pairing$right_model, pairing$right_draw_id, sep = "|"), key)
  app_iqf_require(!anyNA(c(left, right)), "Contrast pairing refers to an unavailable draw.")
  data.frame(pairing, contrast = draw_scores$score[left] - draw_scores$score[right],
    stringsAsFactors = FALSE)
}

app_iqf_output_envelope <- function(request, claim, output_table, output_root) {
  app_iqf_require(!anyDuplicated(output_table$artifact_key) &&
    setequal(output_table$artifact_key, unlist(request$expected_output_keys, use.names = FALSE)),
    "Completion envelope has missing/duplicate/unexpected scientific shard keys.")
  shards <- lapply(seq_len(nrow(output_table)), function(j) {
    path <- app_iqf_safe_path(output_root, output_table$relative_path[j])
    app_iqf_require(file.info(path)$size == output_table$size_bytes[j] &&
      identical(app_iqf_hash(path, TRUE), output_table$sha256[j]), "Output shard changed before sealing.")
    list(key = output_table$artifact_key[j], relative_path = output_table$relative_path[j],
      sha256 = output_table$sha256[j], bytes = output_table$size_bytes[j],
      posterior_target_sha256 = request$posterior_target_sha256)
  })
  csv <- app_iqf_safe_path(output_root, "output_manifest.csv")
  artifacts <- c(lapply(shards, function(s) s[c("relative_path", "sha256", "bytes")]),
    list(list(relative_path = "output_manifest.csv", sha256 = app_iqf_hash(csv, TRUE),
      bytes = file.info(csv)$size)))
  app_iqf_require(setequal(vapply(artifacts, `[[`, character(1L), "relative_path"),
    list.files(output_root, all.files = TRUE, recursive = TRUE, no.. = TRUE)),
    "Uninventoried artifact exists in the fresh output directory.")
  fields <- c("task_id", "source_commit", "source_tree", "source_manifest_sha256",
    "posterior_target_sha256", "input_manifest_sha256", "task_manifest_sha256", "rng_namespace")
  app_iqf_require(all(fields %in% names(request)) && isTRUE(claim$verified) &&
    identical(claim$task_id, request$task_id) && identical(claim$routing_id, request$routing_id),
    "Completion claim/request identity is incomplete.")
  c(list(schema_version = "forecast_transition_output_v1", claim_nonce = claim$claim_nonce,
    routing_id = request$routing_id), request[fields],
    list(expected_output_keys_sha256 = request$expected_output_keys_sha256,
      numerical_gates_pass = all(output_table$integration_status == "PASS_PREDECLARED_DKW_QUANTILE_ACCURACY_GATE"),
      shards = shards, artifacts = artifacts))
}

app_iqf_safe_path <- function(root, relative) {
  app_iqf_require(length(relative) == 1L && is.character(relative) && nzchar(relative) &&
    !grepl("^(/|[A-Za-z]:)|(^|/)\\.\\.(/|$)|[\\\\\r\n]", relative),
    "Bundle paths must be relative and confined to the source root.")
  app_iqf_require(!nzchar(Sys.readlink(root)), "Symbolic-link bundle root is forbidden.")
  root <- normalizePath(root, mustWork = TRUE)
  components <- strsplit(relative, "/", fixed = TRUE)[[1L]]
  for (j in seq_along(components)) app_iqf_require(!nzchar(Sys.readlink(
    file.path(root, paste(components[seq_len(j)], collapse = "/")))),
    "Symbolic-link bundle paths/ancestors are forbidden.")
  path <- normalizePath(file.path(root, relative), mustWork = TRUE)
  app_iqf_require(startsWith(path, paste0(root, .Platform$file.sep)), "Bundle path escapes root.")
  path
}
app_iqf_verify_output_root <- function(requested, claimed) {
  app_iqf_require(is.character(requested) && length(requested) == 1L && nzchar(requested) &&
    identical(requested, claimed) && startsWith(requested, "/") &&
    !grepl("(^|/)\\.\\.(/|$)|[\\\\\r\n]", requested) && !grepl("/$", requested),
    "Output root must exactly match the canonical path reserved by this live claim.")
  parts <- strsplit(requested, "/", fixed = TRUE)[[1L]]
  current <- "/"
  for (part in parts[nzchar(parts)]) {
    current <- file.path(current, part)
    link <- Sys.readlink(current)
    app_iqf_require(is.na(link) || !nzchar(link), "Symbolic-link output ancestry is forbidden.")
  }
  app_iqf_require(!file.exists(requested), "Refusing to overwrite an existing claimed output directory.")
  invisible(TRUE)
}
app_iqf_validate_bundle <- function(root, manifest_path, expected_input_manifest_sha256) {
  app_iqf_require(identical(app_iqf_hash(manifest_path, TRUE), expected_input_manifest_sha256),
    "Input manifest SHA-256 differs.")
  manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
  app_iqf_require(all(c("relative_path", "size_bytes", "sha256", "role") %in% names(manifest)) &&
    nrow(manifest) > 0L && !anyDuplicated(manifest$relative_path) &&
    all(grepl("^[a-f0-9]{64}$", manifest$sha256)), "Input manifest schema is invalid.")
  for (j in seq_len(nrow(manifest))) {
    path <- app_iqf_safe_path(root, manifest$relative_path[j])
    app_iqf_require(file.info(path)$size == manifest$size_bytes[j] &&
      identical(app_iqf_hash(path, TRUE), manifest$sha256[j]),
      paste("Source artifact changed:", manifest$relative_path[j]))
  }
  app_iqf_require(all(c("retained_posterior", "retained_design", "observed_prefix", "bundle_spec") %in%
    manifest$role), "Authentic posterior, design, observed-prefix and spec roles are required.")
  manifest
}
app_iqf_prepare_bundle <- function(root, manifest_path, spec_path, expected_input_manifest_sha256) {
  manifest <- app_iqf_validate_bundle(root, manifest_path, expected_input_manifest_sha256)
  spec_full <- app_iqf_safe_path(root, spec_path)
  app_iqf_require(spec_path %in% manifest$relative_path[manifest$role == "bundle_spec"],
    "Bundle specification is not authenticated by the manifest.")
  spec <- if (grepl("[.]json$", spec_path)) jsonlite::fromJSON(spec_full, simplifyVector = FALSE) else readRDS(spec_full)
  app_iqf_require(identical(spec$schema_version, "integrated_quantile_forecast_bundle_v1") &&
    spec$adapter %in% c("mq_desn_native_v1", "single_qdesn_fit_native_v1", "state_space_conditional_v1"),
    "Unsupported bundle schema/adapter.")
  expected <- switch(spec$adapter, mq_desn_native_v1 = c("design", "posterior", "origins"),
    single_qdesn_fit_native_v1 = c("object", "posterior", "origins"),
    state_space_conditional_v1 = c("model", "posterior", "origins"))
  app_iqf_require(setequal(names(spec$payloads), expected) && !anyDuplicated(names(spec$payloads)),
    "Bundle payloads differ from the exact adapter schema; keep truth in a scoring sidecar.")
  roles <- c(design = "retained_design", object = "retained_design", model = "retained_design",
    posterior = "retained_posterior", origins = "observed_prefix")
  payloads <- lapply(names(spec$payloads), function(name) {
    path <- spec$payloads[[name]]
    j <- match(path, manifest$relative_path)
    app_iqf_require(!is.na(j) && manifest$role[j] == roles[[name]],
      "Payload is not manifest-listed with its required source role.")
    readRDS(app_iqf_safe_path(root, path))
  }); names(payloads) <- names(spec$payloads)
  if (!is.null(spec$supporting_evidence)) for (path in unlist(spec$supporting_evidence, use.names = FALSE)) {
    j <- match(path, manifest$relative_path)
    app_iqf_require(!is.na(j) && grepl("^(draw_mapping|retained_posterior|posterior_source_.*|native_kernel|source_contract)$",
      manifest$role[j]), "Supporting source evidence is missing or has an unapproved provenance role.")
  }
  app_iqf_require(!any(c("truth", "future_y", "observed_y", "q_true") %in% names(payloads)),
    "Scoring truth must be a separate authenticated sidecar, not a predictor payload.")
  app_iqf_validate_origins(payloads$origins); app_iqf_validate_draws(payloads$posterior)
  if (spec$adapter == "state_space_conditional_v1")
    app_iqf_state_conditioning(payloads$model, payloads$origins)
  list(spec = spec, payloads = payloads, manifest = manifest,
    input_manifest_sha256 = expected_input_manifest_sha256)
}
