# Pure Stage E qualification helpers. This module receives authenticated
# in-memory values. It cannot read payloads, fit a model, or publish results.

gnse_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS native Stage E: ", why), call. = FALSE)
  invisible(TRUE)
}
gnse_hash <- function(x) {
  gnse_require(requireNamespace("digest", quietly = TRUE), "digest is required")
  digest::digest(x, algo = "sha256", serialize = TRUE)
}
gnse_scalar <- function(x, positive = FALSE) is.numeric(x) && length(x) == 1L &&
  is.finite(x) && (!positive || x > 0)
gnse_int <- function(x, positive = FALSE) gnse_scalar(x, positive) && x == floor(x)

gnse_validate_budget <- function(x) {
  q <- gnse_require
  q(is.list(x) && identical(x$schema_version,
    "glofas_native_stage_e_acceptance_budget_v1") &&
    identical(x$stage, "E_NATIVE_OPERATIONS_PRECISION_COST_NO_FIT") &&
    identical(x$task_id, "gft-al-p050") &&
    identical(x$posterior_target_sha256,
      "72ef0550393106009b100636e1b11e8c21d4da31e77ed01a3dc2663439dbef03") &&
    identical(x$declared_prior_sha256,
      "d7549e8287c6bf37ee1dafbdc70b0fcc5921307484e9c9658a8140a1926ed65b") &&
    identical(x$effective_prior_sha256,
      "0f9d6ddbe7ddd2e7e9f8c4be151e135a82ae184b587e9d8153de3f3d05c45f71"),
    "exact median target and prior identities required")
  g <- x$application_geometry
  q(is.list(g) && g$coefficient_count == 2502L &&
    g$native_coordinate_count == 7510L &&
    g$reference_coefficient_count == 1501L &&
    g$discrepancy_coefficient_count == 1001L &&
    g$historical_rows_per_source == 12455L &&
    g$forecast_horizon == 28L && g$issued_members_per_horizon == 51L &&
    g$member_factors_per_path == 1428L &&
    identical(as.numeric(c(g$reference_input_gain,
      g$discrepancy_input_gain)), c(.5, .35)),
    "application geometry changed")
  parity <- x$continuation_parity
  q(identical(as.integer(unlist(parity$horizons)), c(2L, 28L)) &&
    identical(unlist(parity$path_rules), c("retained_mean",
      "retained_mean_minus_sd", "retained_mean_plus_sd")) &&
    identical(unlist(parity$parameter_sequence), c("A", "B", "A")) &&
    parity$absolute_tolerance == 1e-10 &&
    isTRUE(parity$require_feature_rows) &&
    isTRUE(parity$require_repeated_ancestor_cache_hit),
    "fixed H2/H28 continuation matrix required")
  derivative <- x$historical_derivatives
  roles <- c("beta_intercept", "beta_slopes", "alpha_intercept",
    "alpha_slopes", "sigma_Y", "sigma_G", "beta_tau", "beta_xi",
    "beta_lambda", "beta_nu", "beta_slab", "alpha_tau", "alpha_xi",
    "alpha_lambda", "alpha_nu", "alpha_slab")
  q(identical(unlist(derivative$roles), roles) &&
    identical(unlist(derivative$variational_coordinates), c("mean", "log_sd")) &&
    identical(as.numeric(unlist(derivative$central_steps)), c(1e-4, 3e-5)) &&
    derivative$scaled_error_tolerance == 5e-6 &&
    derivative$cross_step_scaled_difference_tolerance == 2e-5,
    "fixed sixteen-role derivative matrix required")
  grid <- x$particle_grid
  seeds <- as.integer(unlist(grid$replicate_seeds))
  q(identical(unlist(grid$contexts), c("retained_initializer",
      "coefficient_perturbation", "source_scale_perturbation")) &&
    identical(as.integer(unlist(grid$particle_counts)), c(64L, 128L, 256L)) &&
    grid$initial_replicates == 4L && grid$maximum_replicates == 16L &&
    length(seeds) == 16L && !anyDuplicated(seeds) &&
    grid$maximum_conditional_evaluations == 144L &&
    grid$inner_objective_mcse_allocation == .0025 &&
    grid$centered_particle_count_drift_budget == .01 &&
    grid$reporting_mcse_budget_log1p == .001 &&
    grid$cross_count_reporting_budget_log1p == .005,
    "fixed H28 precision grid required")
  grad <- x$frozen_q_gradient_assessment
  q(isTRUE(grad$enabled) &&
    identical(as.integer(unlist(grad$particle_counts)), c(64L, 128L)) &&
    grad$independent_batches == 4L && grad$outer_draws_per_batch == 2L &&
    length(unlist(grad$seeds)) == 16L &&
    isTRUE(grad$raw_and_batch_centered_scores) &&
    isTRUE(grad$qualification_only_not_optimizer_gradient),
    "fixed frozen-q gradient assessment required")
  q(all(vapply(x[c("stage_f_authorized", "native_fit_authorized",
    "production_authorized", "publication_authorized")],
    identical, logical(1L), FALSE)), "Stage E cannot authorize fitting or publication")
  invisible(TRUE)
}

gnse_spec <- function(design, prior_export, budget) {
  q <- gnse_require
  gnse_validate_budget(budget)
  q(is.list(design) && is.matrix(design$H_fixed) &&
    ncol(design$H_fixed) == budget$application_geometry$coefficient_count &&
    identical(as.integer(design$beta_index), seq_len(1501L)) &&
    identical(as.integer(design$alpha_index), 1501L + seq_len(1001L)) &&
    all(as.numeric(design$weight_fixed) == 1),
    "exact two-block unit-factor historical design required")
  q(is.list(prior_export) && identical(prior_export$schema_version,
    "glofas_native_prior_export_v1") &&
    identical(prior_export$task_id, budget$task_id) &&
    identical(prior_export$posterior_target_sha256,
      budget$posterior_target_sha256) &&
    identical(prior_export$declared_prior_sha256,
      budget$declared_prior_sha256) &&
    identical(prior_export$effective_prior_sha256,
      budget$effective_prior_sha256), "prior export identity differs")
  block <- function(index, x) list(index = as.integer(index),
    intercept_index = as.integer(index[[1L]]), tau0 = as.numeric(x$tau0),
    intercept_prec = as.numeric(x$intercept_prec),
    slab_shape = as.numeric(x$slab$a_zeta),
    slab_rate = as.numeric(x$slab$b_zeta),
    zeta2_fixed = x$slab$zeta2_fixed)
  effective <- prior_export$effective_prior
  spec <- gcat_spec(ncol(design$H_fixed),
    list(beta = block(design$beta_index, effective$beta),
      alpha = block(design$alpha_index, effective$alpha)), .5,
    list(Y = setNames(as.numeric(effective$source_scale$Y), c("shape", "rate")),
      G = setNames(as.numeric(effective$source_scale$G), c("shape", "rate"))))
  q(spec$dimension == budget$application_geometry$native_coordinate_count,
    "native coordinate count differs")
  spec
}

gnse_ig_log_moments_from_inverse_mean <- function(shape, inverse_mean) {
  gnse_require(gnse_scalar(shape, TRUE) && gnse_scalar(inverse_mean, TRUE),
    "positive inverse-gamma shape and inverse mean required")
  rate <- shape / inverse_mean
  c(mean = log(rate) - digamma(shape), sd = sqrt(trigamma(shape)))
}

gnse_initializer <- function(core, spec, design, budget) {
  q <- gnse_require
  v <- core$variational_state
  q(is.list(core) && identical(core$method, "vb") &&
    identical(core$likelihood_family, "al") && identical(core$prior, "rhs_ns") &&
    is.list(v) && is.numeric(v$theta_mean) && length(v$theta_mean) == spec$p &&
    is.matrix(v$theta_cov) && identical(dim(v$theta_cov), c(spec$p, spec$p)) &&
    all(is.finite(v$theta_mean)) && all(is.finite(diag(v$theta_cov))) &&
    all(diag(v$theta_cov) > 0), "retained median AL coefficient state required")
  mean <- log_sd <- numeric(spec$dimension)
  mean[seq_len(spec$p)] <- as.numeric(v$theta_mean)
  log_sd[seq_len(spec$p)] <- log(sqrt(diag(v$theta_cov)))
  sigma <- v$sigma
  q(is.list(sigma) && all(c("shape", "rate") %in% names(sigma)) &&
    all(c("Y", "G") %in% names(sigma$shape)) &&
    all(c("Y", "G") %in% names(sigma$rate)), "retained source-scale factors required")
  for (s in c("Y", "G")) {
    a <- as.numeric(sigma$shape[[s]]); b <- as.numeric(sigma$rate[[s]])
    q(gnse_scalar(a, TRUE) && gnse_scalar(b, TRUE), "valid source-scale factor required")
    mean[spec$scales[[s]]] <- log(b) - digamma(a)
    log_sd[spec$scales[[s]]] <- log(sqrt(trigamma(a)))
  }
  prior <- v$prior
  q(is.list(prior) && identical(prior$prior, "block_rhs_ns") &&
    identical(names(prior$blocks), c("beta", "alpha")) &&
    is.null(prior$prior_addition), "retained two-block RHS state without added prior required")
  for (name in c("beta", "alpha")) {
    target <- spec$blocks[[name]]; retained <- prior$blocks[[name]]
    q(identical(as.integer(retained$global_index), as.integer(target$index)),
      paste0(name, " retained RHS block index differs"))
    state <- retained$state
    local_penalized <- match(target$penalized, retained$global_index)
    q(!anyNA(local_penalized) && identical(as.integer(state$penalized),
      as.integer(local_penalized)) && isTRUE(state$update_zeta),
      paste0(name, " learned RHS state differs"))
    put <- function(index, shape, inverse_mean) {
      moments <- gnse_ig_log_moments_from_inverse_mean(shape, inverse_mean)
      mean[index] <<- moments[["mean"]]
      log_sd[index] <<- log(moments[["sd"]])
    }
    r <- length(target$penalized)
    put(target$tau, (r + 1) / 2, as.numeric(state$e_inv_tau2))
    put(target$xi, 1, as.numeric(state$e_inv_xi))
    for (j in seq_along(target$lambda))
      put(target$lambda[[j]], 1, as.numeric(state$e_inv_lambda2[local_penalized[j]]))
    for (j in seq_along(target$nu))
      put(target$nu[[j]], 1, as.numeric(state$e_inv_nu[local_penalized[j]]))
    put(target$slab, target$slab_shape + r / 2,
      as.numeric(state$e_inv_zeta2))
  }
  floor_sd <- as.numeric(budget$initializer$minimum_standard_deviation)
  q(all(is.finite(mean)) && all(is.finite(log_sd)) &&
    all(exp(log_sd) >= floor_sd), "finite nondegenerate native initializer required")
  names(mean) <- names(log_sd) <- spec$coordinate_names
  list(mean = mean, log_sd = log_sd,
    identity = list(mean_sha256 = gnse_hash(mean), log_sd_sha256 = gnse_hash(log_sd),
      coefficient_column_sha256 = gnse_hash(colnames(design$H_fixed)),
      initializer_is_prior_defining = FALSE))
}

gnse_role_indices <- function(spec) {
  b <- spec$blocks$beta; a <- spec$blocks$alpha
  list(beta_intercept = b$intercept_index, beta_slopes = b$penalized,
    alpha_intercept = a$intercept_index, alpha_slopes = a$penalized,
    sigma_Y = unname(spec$scales[["Y"]]), sigma_G = unname(spec$scales[["G"]]),
    beta_tau = b$tau, beta_xi = b$xi, beta_lambda = b$lambda,
    beta_nu = b$nu, beta_slab = b$slab,
    alpha_tau = a$tau, alpha_xi = a$xi, alpha_lambda = a$lambda,
    alpha_nu = a$nu, alpha_slab = a$slab)
}

gnse_direction <- function(index, dimension, salt = 0) {
  gnse_require(length(index) >= 1L && all(index %in% seq_len(dimension)),
    "nonempty valid direction index required")
  values <- sin(seq_along(index) * (sqrt(5) + salt)) +
    cos(seq_along(index) * (sqrt(3) + salt / 2))
  if (length(index) == 1L || sqrt(sum(values^2)) < .Machine$double.eps)
    values <- rep(1, length(index))
  out <- numeric(dimension); out[index] <- values / sqrt(sum(values^2)); out
}

gnse_context_slice <- function(context, horizon) {
  q <- gnse_require
  q(is.list(context) && horizon %in% c(2L, 28L) &&
    nrow(context$latent_data$future_key) == 28L, "full native H28 context required")
  out <- context
  out$latent_data$future_key <- out$latent_data$future_key[seq_len(horizon), , drop = FALSE]
  keep <- as.integer(out$latent_data$g_ensemble$horizon) <= horizon
  out$latent_data$g_ensemble <- out$latent_data$g_ensemble[keep, , drop = FALSE]
  out$glofas_future_center_path <- out$glofas_future_center_path[seq_len(horizon)]
  out
}

gnse_parameter_contexts <- function(initializer, spec, budget) {
  q <- gnse_require
  A <- initializer$mean
  coefficient <- A
  index <- c(spec$blocks$beta$penalized, spec$blocks$alpha$penalized)
  d <- gnse_direction(index, spec$dimension, 1)
  coefficient <- coefficient + budget$continuation_parity$coefficient_perturbation * d
  scale <- A
  delta <- budget$continuation_parity$source_log_scale_perturbation
  scale[spec$scales[["Y"]]] <- scale[spec$scales[["Y"]]] + delta
  scale[spec$scales[["G"]]] <- scale[spec$scales[["G"]]] - delta
  list(retained_initializer = A, coefficient_perturbation = coefficient,
    source_scale_perturbation = scale)
}

gnse_binding <- function(engine, context, spec, known, budget) {
  id <- list(task_id = budget$task_id,
    posterior_target_sha256 = budget$posterior_target_sha256,
    prior_sha256 = budget$declared_prior_sha256)
  gtdpb_bind(engine, context, spec, known,
    c(beta = budget$application_geometry$reference_input_gain,
      alpha = budget$application_geometry$discrepancy_input_gain), id)
}

gnse_trace_path <- function(binding, path, eta, backend = NULL) {
  decoded <- gcat_decode(eta, binding$spec)
  parameters <- list(coefficients = decoded$coefficients, sigma = decoded$sigma)
  if (is.null(backend))
    backend <- gtdpb_state_backend(binding, retain_features = TRUE)
  state <- backend$initial(1L, parameters)
  paths <- matrix(NA_real_, 1L, binding$horizon)
  beta <- matrix(NA_real_, binding$horizon, binding$widths[["beta"]])
  alpha <- matrix(NA_real_, binding$horizon, binding$widths[["alpha"]])
  reference <- ensemble <- numeric(binding$horizon)
  for (h in seq_len(binding$horizon)) {
    stepped <- backend$step(state, h, paths, parameters)
    state <- stepped$state
    beta[h, ] <- stepped$beta_features[1L, ]
    alpha[h, ] <- stepped$alpha_features[1L, ]
    reference[h] <- stepped$reference[[1L]]
    ensemble[h] <- stepped$ensemble[[1L]]
    paths[1L, h] <- path[[h]]
  }
  list(beta = beta, alpha = alpha, reference = reference, ensemble = ensemble,
    diagnostics = backend$diagnostics())
}

gnse_continuation_parity <- function(engine, context, spec, initializer,
    core, known, budget) {
  q <- gnse_require
  contexts <- gnse_parameter_contexts(initializer, spec, budget)
  sequence <- unlist(budget$continuation_parity$parameter_sequence)
  eta_sequence <- list(contexts$retained_initializer,
    contexts$coefficient_perturbation, contexts$retained_initializer)
  m <- as.numeric(core$variational_state$y_future_mean)
  sd <- sqrt(diag(core$variational_state$y_future_cov))
  paths <- list(retained_mean = m, retained_mean_minus_sd = m - sd,
    retained_mean_plus_sd = m + sd)
  rows <- list(); at <- 0L
  for (H in as.integer(unlist(budget$continuation_parity$horizons))) {
    ctx <- gnse_context_slice(context, H)
    binding <- gnse_binding(engine, ctx, spec, known[seq_len(H)], budget)
    uncached <- gnr_make_value_builder(engine, ctx)
    for (path_name in names(paths)) {
      path <- paths[[path_name]][seq_len(H)]
      backend <- gtdpb_state_backend(binding, retain_features = TRUE)
      for (k in seq_along(sequence)) {
        eta <- eta_sequence[[k]]
        decoded <- gcat_decode(eta, spec)
        cached <- gnse_trace_path(binding, path, eta, backend)
        fresh <- uncached(path)
        beta_expected <- fresh$X_beta_future
        alpha_expected <- fresh$X_alpha_future
        reference_expected <- as.numeric(fresh$H_y %*% decoded$coefficients)
        ensemble_expected <- as.numeric(fresh$H_g_key %*% decoded$coefficients) +
          known[seq_len(H)]
        errors <- c(beta_features = max(abs(cached$beta - beta_expected)),
          alpha_features = max(abs(cached$alpha - alpha_expected)),
          reference_location = max(abs(cached$reference - reference_expected)),
          ensemble_location = max(abs(cached$ensemble - ensemble_expected)))
        for (quantity in names(errors)) {
          at <- at + 1L
          rows[[at]] <- data.frame(horizon = H, path = path_name,
            parameter_label = sequence[[k]], sequence_index = k,
            quantity = quantity, error = errors[[quantity]],
            tolerance = budget$continuation_parity$absolute_tolerance,
            pass = errors[[quantity]] <= budget$continuation_parity$absolute_tolerance,
            cache_hits = cached$diagnostics$cache_hits,
            cache_misses = cached$diagnostics$cache_misses,
            feature_rows_retained = cached$diagnostics$feature_rows_retained,
            stringsAsFactors = FALSE)
        }
      }
    }
  }
  out <- do.call(rbind, rows); rownames(out) <- NULL
  repeated <- out$sequence_index == 3L
  q(any(repeated) && all(out$cache_hits[repeated] >= out$horizon[repeated]),
    "A/B/A continuation did not prove repeated-ancestor cache reuse")
  out$cache_reuse_pass <- !repeated |
    out$cache_hits >= out$horizon
  out
}

gnse_historical_derivatives <- function(binding, initializer, budget) {
  roles <- gnse_role_indices(binding$spec)
  expected <- unlist(budget$historical_derivatives$roles)
  gnse_require(identical(names(roles), expected), "derivative roles differ")
  base <- gcat_historical_elbo(initializer$mean, initializer$log_sd, binding)
  rows <- list(); at <- 0L
  for (r in seq_along(roles)) {
    role <- names(roles)[r]
    d <- gnse_direction(roles[[r]], binding$spec$dimension, r / 10)
    for (coordinate in c("mean", "log_sd")) {
      analytic <- sum(d * base[[paste0("gradient_", coordinate)]])
      fds <- numeric()
      for (step in as.numeric(unlist(budget$historical_derivatives$central_steps))) {
        plus_mean <- minus_mean <- initializer$mean
        plus_sd <- minus_sd <- initializer$log_sd
        if (coordinate == "mean") {
          plus_mean <- plus_mean + step * d; minus_mean <- minus_mean - step * d
        } else {
          plus_sd <- plus_sd + step * d; minus_sd <- minus_sd - step * d
        }
        plus <- gcat_historical_elbo(plus_mean, plus_sd, binding)$value
        minus <- gcat_historical_elbo(minus_mean, minus_sd, binding)$value
        fd <- (plus - minus) / (2 * step); fds <- c(fds, fd)
        scaled <- abs(fd - analytic) / (1 + abs(fd) + abs(analytic))
        at <- at + 1L
        rows[[at]] <- data.frame(role = role, variational_coordinate = coordinate,
          step = step, analytic = analytic, finite_difference = fd,
          scaled_error = scaled,
          scaled_error_tolerance =
            budget$historical_derivatives$scaled_error_tolerance,
          pass = scaled <= budget$historical_derivatives$scaled_error_tolerance,
          stringsAsFactors = FALSE)
      }
      gap <- abs(diff(fds)) / (1 + sum(abs(fds)))
      for (j in (at - length(fds) + 1L):at) {
        rows[[j]]$cross_step_scaled_difference <- gap
        rows[[j]]$cross_step_tolerance <-
          budget$historical_derivatives$cross_step_scaled_difference_tolerance
        rows[[j]]$cross_step_pass <- gap <=
          budget$historical_derivatives$cross_step_scaled_difference_tolerance
      }
    }
  }
  out <- do.call(rbind, rows); rownames(out) <- NULL
  list(rows = out, objective = base$value,
    gradient_mean_norm = sqrt(sum(base$gradient_mean^2)),
    gradient_log_sd_norm = sqrt(sum(base$gradient_log_sd^2)))
}

gnse_log_member_potential <- function(values, location, probability, scale) {
  sum(gic_al_log_density(values, location, probability, scale))
}

gnse_h2_exact <- function(binding, eta, budget) {
  q <- gnse_require
  q(binding$horizon == 2L, "H2 binding required")
  decoded <- gcat_decode(eta, binding$spec)
  pars <- list(coefficients = decoded$coefficients, sigma = decoded$sigma)
  backend <- gtdpb_state_backend(binding)
  initial <- backend$initial(1L, pars)
  empty <- matrix(NA_real_, 1L, 2L)
  first <- backend$step(initial, 1L, empty, pars)
  log_g1 <- gnse_log_member_potential(binding$members[1L, ],
    first$ensemble[[1L]], binding$spec$probability, decoded$sigma[["G"]])
  log_integrand <- function(y) vapply(y, function(value) {
    paths <- empty; paths[1L, 1L] <- value
    second <- backend$step(first$state, 2L, paths, pars)
    gic_al_log_density(value, first$reference[[1L]],
      binding$spec$probability, decoded$sigma[["Y"]]) +
      gnse_log_member_potential(binding$members[2L, ],
        second$ensemble[[1L]], binding$spec$probability, decoded$sigma[["G"]])
  }, numeric(1L))
  mu <- first$reference[[1L]]; sd <- decoded$sigma[["Y"]]
  splits <- mu + sd * as.numeric(unlist(budget$nonlinear_h2$split_standard_deviations))
  probe <- unique(c(splits, mu + sd * seq(-12, 12, length.out = 97L)))
  peak <- max(log_integrand(probe))
  bounds <- c(-Inf, splits, Inf)
  pieces <- lapply(seq_len(length(bounds) - 1L), function(i) {
    value <- stats::integrate(function(y) exp(log_integrand(y) - peak),
      lower = bounds[[i]], upper = bounds[[i + 1L]],
      rel.tol = budget$nonlinear_h2$relative_tolerance,
      abs.tol = budget$nonlinear_h2$absolute_tolerance,
      subdivisions = 300L, stop.on.error = FALSE)
    data.frame(piece = i, lower = bounds[[i]], upper = bounds[[i + 1L]],
      value = value$value, abs_error = value$abs.error,
      message = value$message, stringsAsFactors = FALSE)
  })
  parts <- do.call(rbind, pieces)
  q(all(is.finite(parts$value)) && sum(parts$value) > 0,
    "nonlinear H2 split quadrature failed")
  list(log_evidence = log_g1 + peak + log(sum(parts$value)),
    scaled_integral = sum(parts$value), peak = peak, pieces = parts)
}

gnse_evidence_once <- function(binding, eta, particles, seed, budget,
    retain_particles = TRUE) {
  started <- proc.time()[["elapsed"]]
  evidence <- gtdpb_make_evidence(binding, particles = particles,
    ess_fraction = budget$particle_grid$ess_fraction,
    limits = list(max_horizon = 28L, max_particles = 4096L,
      max_calls = as.integer(budget$resource_caps$maximum_callback_calls_per_evidence)),
    gates = list(min_ess = budget$particle_grid$minimum_ess_diagnostic,
      min_unique_ancestors =
        as.integer(budget$particle_grid$minimum_unique_ancestors_diagnostic)),
    retain_particles = retain_particles)
  out <- evidence(eta, as.integer(seed))
  out$elapsed_seconds <- proc.time()[["elapsed"]] - started
  out
}

gnse_h2_check <- function(engine, context, spec, contexts, known, budget,
    evidence_once = gnse_evidence_once) {
  gnse_require(is.function(evidence_once), "H2 evidence callback required")
  ctx <- gnse_context_slice(context, 2L)
  binding <- gnse_binding(engine, ctx, spec, known[1:2], budget)
  rows <- list(); pieces <- list(); at <- 0L
  for (name in unlist(budget$nonlinear_h2$contexts)) {
    exact <- gnse_h2_exact(binding, contexts[[name]], budget)
    pieces[[name]] <- transform(exact$pieces, context = name)
    estimates <- numeric()
    for (seed in as.integer(unlist(budget$nonlinear_h2$replicate_seeds))) {
      at <- at + 1L
      out <- evidence_once(binding, contexts[[name]],
        as.integer(budget$nonlinear_h2$particle_count), seed, budget, FALSE)
      estimates <- c(estimates, out$log_estimate)
      rows[[at]] <- data.frame(context = name, seed = seed,
        particles = budget$nonlinear_h2$particle_count,
        exact_log_evidence = exact$log_evidence,
        particle_log_evidence = out$log_estimate,
        difference = out$log_estimate - exact$log_evidence,
        complete = out$complete, min_ess = out$min_ess,
        min_unique_ancestors = out$min_unique_ancestors,
        elapsed_seconds = out$elapsed_seconds, stringsAsFactors = FALSE)
    }
  }
  result <- do.call(rbind, rows); rownames(result) <- NULL
  summary <- do.call(rbind, lapply(split(result, result$context), function(z) {
    se <- if (nrow(z) > 1L) stats::sd(z$difference) / sqrt(nrow(z)) else Inf
    data.frame(context = z$context[[1L]], mean_difference = mean(z$difference),
      mcse = se, upper_abs_difference = abs(mean(z$difference)) + 2 * se,
      tolerance =
        budget$nonlinear_h2$log_evidence_difference_plus_2mcse_tolerance,
      pass = all(z$complete) && abs(mean(z$difference)) + 2 * se <=
        budget$nonlinear_h2$log_evidence_difference_plus_2mcse_tolerance)
  }))
  list(rows = result, summary = summary, pieces = do.call(rbind, pieces))
}

gnse_particle_grid <- function(binding, contexts, budget, replicate_count,
    existing = NULL, evidence_once = gnse_evidence_once) {
  q <- gnse_require
  q(is.function(evidence_once), "particle-grid evidence callback required")
  q(replicate_count %in% c(budget$particle_grid$initial_replicates,
    budget$particle_grid$maximum_replicates), "declared replicate count required")
  context_names <- unlist(budget$particle_grid$contexts)
  counts <- as.integer(unlist(budget$particle_grid$particle_counts))
  seeds <- as.integer(unlist(budget$particle_grid$replicate_seeds))[seq_len(replicate_count)]
  done <- if (is.null(existing)) character() else
    paste(existing$rows$context, existing$rows$particles, existing$rows$replicate, sep = ":")
  rows <- list(); horizon <- list(); quantiles <- list(); outputs <- list()
  if (!is.null(existing)) {
    rows <- split(existing$rows, seq_len(nrow(existing$rows)))
    horizon <- split(existing$horizon, seq_len(nrow(existing$horizon)))
    quantiles <- split(existing$quantiles, seq_len(nrow(existing$quantiles)))
    outputs <- existing$outputs
  }
  for (name in context_names) for (N in counts) for (r in seq_len(replicate_count)) {
    key <- paste(name, N, r, sep = ":")
    if (key %in% done) next
    out <- evidence_once(binding, contexts[[name]], N, seeds[[r]], budget, TRUE)
    particle <- out$particle_output
    rows[[length(rows) + 1L]] <- data.frame(context = name, particles = N,
      replicate = r, seed = seeds[[r]], complete = out$complete,
      diagnostic_thresholds_passed = out$diagnostic_thresholds_passed,
      log_evidence = out$log_estimate, min_ess = out$min_ess,
      min_unique_ancestors = out$min_unique_ancestors,
      callback_calls = out$callback_calls,
      cache_entries = out$backend_diagnostics$cache_entries,
      cache_hits = out$backend_diagnostics$cache_hits,
      cache_misses = out$backend_diagnostics$cache_misses,
      normalizer_scale_status = particle$normalizer_scale_status,
      elapsed_seconds = out$elapsed_seconds,
      failure = if (is.null(out$failure)) NA_character_ else out$failure,
      stringsAsFactors = FALSE)
    if (isTRUE(out$complete)) {
      d <- particle$diagnostics
      d$context <- name; d$particles <- N; d$replicate <- r; d$seed <- seeds[[r]]
      horizon[[length(horizon) + 1L]] <- d
      probs <- as.numeric(unlist(budget$particle_grid$reporting_probabilities))
      qr <- do.call(rbind, lapply(seq_len(ncol(particle$paths)), function(h)
        data.frame(context = name, particles = N, replicate = r, seed = seeds[[r]],
          horizon = h, probability = probs,
          quantile = vapply(probs, function(p) gpmq_weighted_inverse_cdf(
            particle$paths[, h], particle$weights, p), numeric(1L)))))
      quantiles[[length(quantiles) + 1L]] <- qr
      outputs[[key]] <- particle
    }
  }
  list(rows = do.call(rbind, rows), horizon = do.call(rbind, horizon),
    quantiles = do.call(rbind, quantiles), outputs = outputs)
}

gnse_grid_precision <- function(grid, budget) {
  q <- gnse_require
  rows <- grid$rows
  counts <- as.integer(unlist(budget$particle_grid$particle_counts))
  contexts <- unlist(budget$particle_grid$contexts)
  reps <- max(rows$replicate)
  summary <- do.call(rbind, lapply(contexts, function(name)
    do.call(rbind, lapply(counts, function(N) {
      z <- rows[rows$context == name & rows$particles == N, , drop = FALSE]
      se <- if (nrow(z) > 1L) stats::sd(z$log_evidence) / sqrt(nrow(z)) else Inf
      data.frame(context = name, particles = N, replicates = nrow(z),
        complete = all(z$complete) && all(is.finite(z$log_evidence)),
        mean_log_evidence = mean(z$log_evidence), mcse = se,
        inner_mcse_pass = se <= budget$particle_grid$inner_objective_mcse_allocation,
        mean_elapsed_seconds = mean(z$elapsed_seconds),
        max_elapsed_seconds = max(z$elapsed_seconds), stringsAsFactors = FALSE)
    }))))
  reference <- contexts[[1L]]
  drift <- list(); at <- 0L
  for (left in counts[-length(counts)]) {
    right <- counts[match(left, counts) + 1L]
    ref_l <- rows[rows$context == reference & rows$particles == left, ]
    ref_r <- rows[rows$context == reference & rows$particles == right, ]
    ref <- ref_r$log_evidence[match(seq_len(reps), ref_r$replicate)] -
      ref_l$log_evidence[match(seq_len(reps), ref_l$replicate)]
    for (name in contexts) {
      l <- rows[rows$context == name & rows$particles == left, ]
      r <- rows[rows$context == name & rows$particles == right, ]
      delta <- r$log_evidence[match(seq_len(reps), r$replicate)] -
        l$log_evidence[match(seq_len(reps), l$replicate)] - ref
      se <- if (length(delta) > 1L) stats::sd(delta) / sqrt(length(delta)) else Inf
      at <- at + 1L
      drift[[at]] <- data.frame(context = name, particles_left = left,
        particles_right = right, replicates = length(delta),
        centered_mean_drift = mean(delta), mcse = se,
        upper_abs_drift = abs(mean(delta)) +
          budget$particle_grid$two_mcse_multiplier * se,
        budget = budget$particle_grid$centered_particle_count_drift_budget,
        pass = abs(mean(delta)) +
          budget$particle_grid$two_mcse_multiplier * se <=
          budget$particle_grid$centered_particle_count_drift_budget)
    }
  }
  qrows <- grid$quantiles
  reporting <- do.call(rbind, lapply(split(qrows,
    interaction(qrows$context, qrows$particles, qrows$horizon,
      qrows$probability, drop = TRUE)), function(z) {
    se <- if (nrow(z) > 1L) stats::sd(z$quantile) / sqrt(nrow(z)) else Inf
    data.frame(context = z$context[[1L]], particles = z$particles[[1L]],
      horizon = z$horizon[[1L]], probability = z$probability[[1L]],
      replicates = nrow(z), mean_quantile = mean(z$quantile), mcse = se,
      mcse_pass = se <= budget$particle_grid$reporting_mcse_budget_log1p)
  }))
  stability <- list(); at <- 0L
  pairs <- rbind(c(64L, 128L), c(128L, 256L), c(64L, 256L))
  for (name in contexts) for (h in sort(unique(qrows$horizon)))
    for (probability in sort(unique(qrows$probability))) for (pair in seq_len(nrow(pairs))) {
      left <- pairs[pair, 1L]; right <- pairs[pair, 2L]
      a <- qrows[qrows$context == name & qrows$particles == left &
        qrows$horizon == h & qrows$probability == probability, , drop = FALSE]
      b <- qrows[qrows$context == name & qrows$particles == right &
        qrows$horizon == h & qrows$probability == probability, , drop = FALSE]
      common <- intersect(a$replicate, b$replicate)
      delta <- b$quantile[match(common, b$replicate)] -
        a$quantile[match(common, a$replicate)]
      se <- if (length(delta) > 1L) stats::sd(delta) / sqrt(length(delta)) else Inf
      at <- at + 1L
      stability[[at]] <- data.frame(context = name, horizon = h,
        probability = probability, particles_left = left,
        particles_right = right, replicates = length(delta),
        mean_difference = mean(delta), mcse = se,
        upper_abs_difference = abs(mean(delta)) +
          budget$particle_grid$two_mcse_multiplier * se,
        budget = budget$particle_grid$cross_count_reporting_budget_log1p,
        pass = abs(mean(delta)) +
          budget$particle_grid$two_mcse_multiplier * se <=
          budget$particle_grid$cross_count_reporting_budget_log1p,
        stringsAsFactors = FALSE)
    }
  stability <- do.call(rbind, stability)
  adjacent <- do.call(rbind, lapply(c(64L, 128L), function(left) {
    right <- counts[match(left, counts) + 1L]
    objective_ok <- all(do.call(rbind, drift)$pass[
      do.call(rbind, drift)$particles_left == left &
        do.call(rbind, drift)$particles_right == right])
    reporting_ok <- all(stability$pass[stability$particles_left == left &
      stability$particles_right == right])
    larger_ok <- if (right == max(counts)) TRUE else
      all(stability$pass[stability$particles_left == left &
        stability$particles_right == max(counts)])
    inner_ok <- all(summary$inner_mcse_pass[summary$particles %in% c(left, right)])
    data.frame(particles_left = left, particles_right = right,
      inner_mcse_pass = inner_ok, objective_drift_pass = objective_ok,
      reporting_stability_pass = reporting_ok,
      agrees_with_all_larger_assessed_counts = larger_ok,
      admissible = inner_ok && objective_ok && reporting_ok && larger_ok,
      stringsAsFactors = FALSE)
  }))
  selected <- adjacent$particles_left[which(adjacent$admissible)[1L]]
  if (!length(selected)) selected <- NA_integer_
  list(summary = summary, drift = do.call(rbind, drift), reporting = reporting,
    reporting_stability = stability, adjacent_pair_decisions = adjacent,
    selected_N_fit = selected,
    all_complete = all(summary$complete),
    all_inner_mcse_pass = all(summary$inner_mcse_pass),
    all_drift_pass = all(do.call(rbind, drift)$pass),
    all_reporting_mcse_pass = all(reporting$mcse_pass),
    all_reporting_stability_pass = all(stability$pass),
    particle_count_selected = is.finite(selected))
}

gnse_rhs_invariance <- function(binding, eta, spec, budget,
    evidence_once = gnse_evidence_once) {
  gnse_require(is.function(evidence_once), "RHS-invariance evidence callback required")
  changed <- eta
  rhs <- unlist(lapply(spec$blocks, function(b)
    c(b$tau, b$xi, b$lambda, b$nu, b$slab)), use.names = FALSE)
  changed[rhs] <- changed[rhs] + budget$rhs_only_invariance$log_coordinate_perturbation *
    gnse_direction(rhs, spec$dimension, 4)[rhs]
  seed <- as.integer(budget$rhs_only_invariance$seed)
  N <- as.integer(budget$rhs_only_invariance$particle_count)
  a <- evidence_once(binding, eta, N, seed, budget, FALSE)
  b <- evidence_once(binding, changed, N, seed, budget, FALSE)
  gap <- abs(a$log_estimate - b$log_estimate)
  data.frame(particles = N, seed = seed, original_log_evidence = a$log_estimate,
    perturbed_log_evidence = b$log_estimate, absolute_difference = gap,
    tolerance = budget$rhs_only_invariance$absolute_tolerance,
    pass = isTRUE(a$complete) && isTRUE(b$complete) &&
      gap <= budget$rhs_only_invariance$absolute_tolerance,
    historical_prior_changed =
      abs(gcat_log_prior(eta, spec) - gcat_log_prior(changed, spec)) > 0,
    future_parameter_values_changed = FALSE, stringsAsFactors = FALSE)
}

gnse_gradient_assessment <- function(binding, initializer, budget,
    evidence_once = gnse_evidence_once) {
  gnse_require(is.function(evidence_once), "gradient evidence callback required")
  cfg <- budget$frozen_q_gradient_assessment
  if (!isTRUE(cfg$enabled)) return(data.frame())
  roles <- gnse_role_indices(binding$spec)
  counts <- as.integer(unlist(cfg$particle_counts))
  seeds <- as.integer(unlist(cfg$seeds))
  at_seed <- 0L; records <- list(); at <- 0L
  sd <- exp(initializer$log_sd)
  old <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE))
    get(".Random.seed", .GlobalEnv) else NULL
  on.exit(if (is.null(old)) {
    if (exists(".Random.seed", .GlobalEnv, inherits = FALSE))
      rm(".Random.seed", envir = .GlobalEnv)
  } else assign(".Random.seed", old, .GlobalEnv), add = TRUE)
  for (N in counts) for (batch in seq_len(cfg$independent_batches)) {
    draws <- vector("list", cfg$outer_draws_per_batch)
    logs <- numeric(cfg$outer_draws_per_batch)
    for (draw in seq_len(cfg$outer_draws_per_batch)) {
      at_seed <- at_seed + 1L; seed <- seeds[[at_seed]]
      set.seed(seed); z <- stats::rnorm(binding$spec$dimension)
      eta <- initializer$mean + sd * z
      ev <- evidence_once(binding, eta, N, seed, budget, FALSE)
      draws[[draw]] <- list(z = z, log_evidence = ev$log_estimate,
        complete = ev$complete, seed = seed)
      logs[[draw]] <- ev$log_estimate
    }
    centered <- logs - mean(logs)
    for (role_i in seq_along(roles)) {
      role <- names(roles)[role_i]
      d <- gnse_direction(roles[[role_i]], binding$spec$dimension, role_i / 10)
      for (coordinate in c("mean", "log_sd")) for (controlled in c(FALSE, TRUE)) {
        value <- vapply(seq_along(draws), function(j) {
          score <- if (coordinate == "mean") draws[[j]]$z / sd else
            draws[[j]]$z^2 - 1
          sum(d * score) * if (controlled) centered[[j]] else logs[[j]]
        }, numeric(1L))
        at <- at + 1L
        records[[at]] <- data.frame(particles = N, batch = batch,
          role = role, variational_coordinate = coordinate,
          estimator = if (controlled) "batch_centered" else "raw",
          estimate = mean(value),
          within_batch_mcse = if (length(value) > 1L)
            stats::sd(value) / sqrt(length(value)) else NA_real_,
          complete = all(vapply(draws, function(x) isTRUE(x$complete), logical(1L))),
          stringsAsFactors = FALSE)
      }
    }
  }
  do.call(rbind, records)
}

gnse_mem_available <- function() {
  x <- readLines("/proc/meminfo", warn = FALSE)
  line <- grep("^MemAvailable:", x, value = TRUE)
  if (!length(line)) return(NA_real_)
  as.numeric(strsplit(trimws(line), "[[:space:]]+")[[1L]][2L]) * 1024
}
gnse_peak_rss <- function() {
  x <- readLines("/proc/self/status", warn = FALSE)
  line <- grep("^VmHWM:", x, value = TRUE)
  if (!length(line)) return(NA_real_)
  as.numeric(strsplit(trimws(line), "[[:space:]]+")[[1L]][2L]) * 1024
}

gnse_extension_admission <- function(initial, elapsed, remaining, budget) {
  q <- gnse_require
  rows <- initial$rows
  remaining_evaluations <- length(unlist(budget$particle_grid$contexts)) *
    length(unlist(budget$particle_grid$particle_counts)) *
    (budget$particle_grid$maximum_replicates -
      budget$particle_grid$initial_replicates)
  projected <- max(rows$elapsed_seconds) *
    budget$particle_grid$initial_cost_safety_factor * remaining_evaluations
  available <- gnse_mem_available(); peak <- gnse_peak_rss()
  memory_ok <- is.finite(available) && is.finite(peak) &&
    available >= budget$particle_grid$memory_headroom_bytes + peak
  time_ok <- projected + budget$particle_grid$minimum_remaining_wall_seconds <= remaining
  data.frame(initial_elapsed_seconds = elapsed,
    maximum_complete_evaluation_seconds = max(rows$elapsed_seconds),
    remaining_evaluations = remaining_evaluations,
    projected_remaining_seconds = projected, admitted_remaining_seconds = remaining,
    peak_rss_bytes = peak, mem_available_bytes = available,
    required_memory_headroom_bytes = budget$particle_grid$memory_headroom_bytes,
    time_pass = time_ok, memory_pass = memory_ok,
    admitted = all(rows$complete) && time_ok && memory_ok,
    stringsAsFactors = FALSE)
}

gnse_run <- function(engine, design, object, prior_export, budget,
    wall_seconds, source_sha256, evidence_once = gnse_evidence_once,
    extension_admission = gnse_extension_admission) {
  q <- gnse_require; gnse_validate_budget(budget)
  q(is.function(evidence_once) && is.function(extension_admission),
    "evidence and extension-admission callbacks required")
  started <- proc.time()[["elapsed"]]
  core <- object$fit
  spec <- gnse_spec(design, prior_export, budget)
  q(nrow(design$H_fixed) == 2L *
    budget$application_geometry$historical_rows_per_source &&
    all(table(as.character(design$source_fixed)) == c(G = 12455L, Y = 12455L)),
    "historical source counts changed")
  historical <- gcat_bind_historical(spec, design$H_fixed,
    as.numeric(design$z_fixed), as.character(design$source_fixed),
    as.numeric(design$weight_fixed))
  initializer <- gnse_initializer(core, spec, design, budget)
  context <- gnr_context(design, engine)
  known <- if (is.null(design$discrepancy_baseline_future)) rep(0, 28L) else
    as.numeric(design$discrepancy_baseline_future)
  q(length(known) == 28L && all(is.finite(known)), "finite H28 known baseline required")
  contexts <- gnse_parameter_contexts(initializer, spec, budget)
  parity <- gnse_continuation_parity(engine, context, spec, initializer,
    core, known, budget)
  tick <- proc.time()[["elapsed"]]
  derivatives <- gnse_historical_derivatives(historical, initializer, budget)
  historical_seconds <- proc.time()[["elapsed"]] - tick
  h2 <- gnse_h2_check(engine, context, spec, contexts, known, budget,
    evidence_once)
  binding <- gnse_binding(engine, context, spec, known, budget)
  native_contract <- gnpo_contract(spec, binding, prior_export,
    source_sha256 = source_sha256, fixture_only = FALSE)
  gnpo_validate_contract(native_contract, spec$dimension)
  rhs <- gnse_rhs_invariance(binding, initializer$mean, spec, budget,
    evidence_once)
  initial <- gnse_particle_grid(binding, contexts, budget,
    budget$particle_grid$initial_replicates, evidence_once = evidence_once)
  elapsed <- proc.time()[["elapsed"]] - started
  extension <- extension_admission(initial, elapsed,
    wall_seconds - elapsed, budget)
  grid <- initial
  if (isTRUE(extension$admitted[[1L]])) {
    grid <- gnse_particle_grid(binding, contexts, budget,
      budget$particle_grid$maximum_replicates, initial, evidence_once)
  }
  precision <- gnse_grid_precision(grid, budget)
  gradient <- gnse_gradient_assessment(binding, initializer, budget,
    evidence_once)
  h2_pass <- all(h2$summary$pass)
  derivative_pass <- all(derivatives$rows$pass) &&
    all(derivatives$rows$cross_step_pass)
  complete_replicates <- max(grid$rows$replicate) ==
    budget$particle_grid$maximum_replicates
  source_pass <- all(parity$pass) && all(parity$cache_reuse_pass) &&
    derivative_pass && all(rhs$pass) && all(rhs$historical_prior_changed)
  numeric_pass <- source_pass && h2_pass && precision$all_complete
  precision_pass <- precision$all_inner_mcse_pass &&
    precision$all_drift_pass && precision$all_reporting_mcse_pass &&
    precision$all_reporting_stability_pass && precision$particle_count_selected
  decision <- if (!source_pass) "REVISE_SOURCE" else if (!h2_pass ||
    !precision$all_complete) "REJECT" else if (!complete_replicates)
    "INCONCLUSIVE" else if (!precision_pass) "REJECT" else
      "ADMIT_STAGE_F_PROPOSAL"
  summary <- list(schema_version = "glofas_native_stage_e_summary_v1",
    decision = decision, task_id = budget$task_id,
    posterior_target_sha256 = budget$posterior_target_sha256,
    declared_prior_sha256 = budget$declared_prior_sha256,
    effective_prior_sha256 = budget$effective_prior_sha256,
    coordinate_count = spec$dimension, coefficient_count = spec$p,
    historical_rows = nrow(design$H_fixed),
    initializer = initializer$identity,
    continuation_parity_pass = all(parity$pass),
    historical_derivative_pass = derivative_pass,
    nonlinear_h2_pass = h2_pass, rhs_only_invariance_pass = all(rhs$pass),
    initial_grid_evaluations = 3L * 3L * 4L,
    final_grid_evaluations = nrow(grid$rows),
    extension_admitted = isTRUE(extension$admitted[[1L]]),
    precision = precision[c("all_complete", "all_inner_mcse_pass",
      "all_drift_pass", "all_reporting_mcse_pass",
      "all_reporting_stability_pass", "particle_count_selected",
      "selected_N_fit")],
    frozen_q_gradient_rows = nrow(gradient),
    historical_objective_seconds = historical_seconds,
    elapsed_seconds = proc.time()[["elapsed"]] - started,
    peak_rss_bytes = gnse_peak_rss(), future_truth_read = FALSE,
    model_fits = 0L, optimizer_iterations = 0L,
    stage_f_authorized = FALSE, native_fit_authorized = FALSE,
    production_authorized = FALSE, publication_authorized = FALSE)
  list(summary = summary, parity = parity,
    derivatives = derivatives$rows,
    derivative_summary = data.frame(objective = derivatives$objective,
      gradient_mean_norm = derivatives$gradient_mean_norm,
      gradient_log_sd_norm = derivatives$gradient_log_sd_norm,
      elapsed_seconds = historical_seconds),
    h2 = h2$rows, h2_summary = h2$summary, h2_pieces = h2$pieces,
    rhs_invariance = rhs, extension = extension,
    particle_grid = grid$rows, particle_horizon = grid$horizon,
    particle_quantiles = grid$quantiles,
    precision_summary = precision$summary, precision_drift = precision$drift,
    reporting_precision = precision$reporting,
    reporting_stability = precision$reporting_stability,
    adjacent_pair_decisions = precision$adjacent_pair_decisions,
    gradient_assessment = gradient,
    binding = list(schema_version = binding$schema_version,
      static_sha256 = binding$static_sha256, target_identity = binding$target_identity,
      member_policy = binding$member_policy, horizon = binding$horizon,
      member_factors_per_path = binding$member_factors_per_path,
      gains = binding$gains, original_file_reads = binding$original_file_reads,
      future_truth_read = binding$future_truth_read),
    native_contract = native_contract)
}
