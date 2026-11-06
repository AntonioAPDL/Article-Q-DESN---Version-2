# Changing-parameter two-DESN state backend for the experimental GloFAS SMC.
# The module consumes only caller-supplied in-memory objects. Native payload
# reads and scientific launches require a separate source-pinned purpose.

gtdpb_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS two-DESN particle backend: ", why), call. = FALSE)
  invisible(TRUE)
}
gtdpb_hash <- function(x) {
  gtdpb_require(requireNamespace("digest", quietly = TRUE), "digest is required")
  digest::digest(x, algo = "sha256", serialize = TRUE)
}

gtdpb_bind <- function(engine, context, spec, known_baseline = NULL,
    expected_gains = NULL, target_identity, member_policy = "unit_member_likelihood_v1") {
  q <- gtdpb_require
  q(exists("gnr_context", mode = "function", inherits = TRUE) &&
    exists("gcat_decode", mode = "function", inherits = TRUE),
    "load nonlinear replay and collapsed target helpers first")
  q(is.list(engine) && is.environment(engine$env) && is.environment(engine$audit),
    "fresh local evaluator engine required")
  context <- gnr_context(list(future_context = context), engine)
  q(identical(member_policy, "unit_member_likelihood_v1"),
    "ordinary unit-member likelihood policy is mandatory")
  q(is.list(target_identity) && all(c("posterior_target_sha256", "prior_sha256",
    "task_id") %in% names(target_identity)) &&
    all(vapply(target_identity[c("posterior_target_sha256", "prior_sha256")],
      function(x) is.character(x) && length(x) == 1L && grepl("^[a-f0-9]{64}$", x),
      logical(1L))) && identical(target_identity$task_id, "gft-al-p050"),
    "exact median task, target, and prior identities required")
  H <- nrow(context$latent_data$future_key)
  q(H >= 1L && H <= 28L, "bounded future horizon required")
  dates <- as.Date(context$latent_data$future_key$target_date)
  if (is.null(known_baseline)) known_baseline <- rep(0, H)
  q(is.numeric(known_baseline) && length(known_baseline) == H &&
    all(is.finite(known_baseline)), "one finite known baseline per horizon required")
  e <- engine$env
  contracts <- initial <- list(); widths <- integer(2L); names(widths) <- c("beta", "alpha")
  gains <- numeric(2L); names(gains) <- names(widths)
  metadata_start <- length(engine$audit$metadata)
  for (block in names(widths)) {
    fit <- context[[paste0("qfit_", block)]]
    history <- if (block == "beta") context$y_history_full else context$d_history_full
    contract <- e$app_qdesn_compile_future_input_contract(
      spec = fit$meta$reservoir_input_spec, history_dates = fit$meta$history_dates,
      y_history = history, future_dates = dates,
      covariate_timeline = context$covariate_timeline)
    e$app_qdesn_validate_compiled_future_inputs(contract,
      fit$meta$reservoir_input_spec, dates, verify_hash = FALSE)
    q(all(contract$future_index >= 0L) &&
      all(contract$future_index < row(contract$future_index)),
      "compiled inputs must be strictly causal")
    contracts[[block]] <- contract
    initial[[block]] <- e$app_qdesn_last_states(fit)
    widths[[block]] <- length(e$app_qdesn_readout_row_from_states(
      initial[[block]], fit$reservoir)) + 1L
    gains[[block]] <- as.numeric(fit$meta$win_scale_global)
  }
  q(spec$p == sum(widths) && identical(spec$blocks$beta$index,
    seq_len(widths[["beta"]])) && identical(spec$blocks$alpha$index,
    widths[["beta"]] + seq_len(widths[["alpha"]])),
    "collapsed coefficient blocks must match retained readout order exactly")
  if (!is.null(expected_gains)) {
    q(is.numeric(expected_gains) && setequal(names(expected_gains), names(gains)) &&
      max(abs(gains[names(expected_gains)] - expected_gains)) < 1e-14,
      "retained reference/discrepancy input gains differ from the declared task")
  }
  ensemble <- context$latent_data$g_ensemble
  q(all(as.numeric(ensemble$ensemble_weight) == 1),
    "fractional or non-unit ensemble factors are forbidden")
  members <- matrix(NA_real_, H, 51L)
  for (h in seq_len(H)) {
    rows <- as.integer(ensemble$horizon) == h
    q(sum(rows) == 51L, "exactly 51 issued members are required per horizon")
    members[h, ] <- as.numeric(ensemble$g_transformed[rows])
  }
  q(all(is.finite(members)), "all issued members must be finite")
  center <- as.numeric(context$glofas_future_center_path)
  q(length(center) == H && all(is.finite(center)), "finite issued-ensemble centre path required")
  binding <- list(schema_version = "glofas_two_desn_particle_binding_v1",
    engine = engine, context = context, spec = spec, horizon = H, dates = dates,
    contracts = contracts, initial_states = initial, widths = widths,
    known_baseline = as.numeric(known_baseline), members = members,
    ensemble_center = center, gains = gains, target_identity = target_identity,
    member_policy = member_policy, member_weights = rep(1, 51L),
    member_factors_per_path = H * 51L,
    metadata_serializations = length(engine$audit$metadata) - metadata_start,
    original_file_reads = 0L, future_truth_read = FALSE,
    production_qualified = FALSE, native_application_qualified = FALSE)
  binding$static_sha256 <- gtdpb_hash(binding[c("horizon", "dates", "contracts",
    "initial_states", "widths", "known_baseline", "members", "ensemble_center",
    "gains", "target_identity", "member_policy")])
  binding
}

gtdpb_clone_states <- function(states, n) lapply(states, function(x) rep(list(x), n))

gtdpb_state_backend <- function(binding, max_cache_entries = 100000L,
    retain_features = FALSE) {
  q <- gtdpb_require
  q(is.list(binding) && identical(binding$schema_version,
    "glofas_two_desn_particle_binding_v1") && identical(binding$production_qualified, FALSE),
    "experimental two-DESN binding required")
  q(is.numeric(max_cache_entries) && length(max_cache_entries) == 1L &&
    is.finite(max_cache_entries) && max_cache_entries == floor(max_cache_entries) &&
    max_cache_entries >= binding$horizon && max_cache_entries <= 1000000L,
    "bounded exact-prefix cache size required")
  q(is.logical(retain_features) && length(retain_features) == 1L &&
    !is.na(retain_features), "one explicit feature-retention flag required")
  e <- binding$engine$env
  cache <- list(); hits <- misses <- steps <- resamples <- 0L
  initial <- function(n, parameters) {
    q(is.numeric(n) && length(n) == 1L && n == floor(n) && n >= 1L && n <= 4096L,
      "bounded particle count required")
    q(is.list(parameters) && length(parameters$coefficients) == binding$spec$p,
      "all coefficient coordinates required")
    list(states = gtdpb_clone_states(binding$initial_states, as.integer(n)),
      ancestor_ids = seq_len(as.integer(n)))
  }
  lookup <- function(h, prefix, parameter_key) {
    if (!length(cache)) return(NULL)
    at <- which(vapply(cache, function(x) x$h == h &&
      identical(x$prefix, prefix) && identical(x$parameter_key, parameter_key),
      logical(1L)))
    if (!length(at)) NULL else cache[[at[[1L]]]]
  }
  step <- function(state, h, paths, parameters) {
    q(is.list(state) && is.list(state$states) && is.matrix(paths) &&
      nrow(paths) == length(state$ancestor_ids) && h >= 1L && h <= binding$horizon,
      "aligned particle states, paths, and horizon required")
    beta <- parameters$coefficients[binding$spec$blocks$beta$index]
    alpha <- parameters$coefficients[binding$spec$blocks$alpha$index]
    parameter_key <- gtdpb_hash(list(coefficients = parameters$coefficients,
      sigma = parameters$sigma))
    N <- nrow(paths); mu_y <- mu_g <- numeric(N)
    beta_rows <- if (isTRUE(retain_features)) matrix(NA_real_, N, binding$widths[["beta"]]) else NULL
    alpha_rows <- if (isTRUE(retain_features)) matrix(NA_real_, N, binding$widths[["alpha"]]) else NULL
    next_states <- state$states
    for (i in seq_len(N)) {
      prefix <- if (h == 1L) numeric() else as.numeric(paths[i, seq_len(h - 1L)])
      q(all(is.finite(prefix)), "complete finite response prefix required")
      found <- lookup(h, prefix, parameter_key)
      if (!is.null(found)) {
        hits <<- hits + 1L
        next_states$beta[[i]] <- found$beta_state
        next_states$alpha[[i]] <- found$alpha_state
        mu_y[[i]] <- found$reference
        mu_g[[i]] <- found$ensemble
        if (isTRUE(retain_features)) {
          beta_rows[i, ] <- found$beta_row
          alpha_rows[i, ] <- found$alpha_row
        }
        next
      }
      misses <<- misses + 1L
      rows <- list()
      for (block in c("beta", "alpha")) {
        fit <- binding$context[[paste0("qfit_", block)]]
        input <- binding$contracts[[block]]$static_values[h, ]
        idx <- binding$contracts[[block]]$future_index[h, ]
        dynamic <- which(idx > 0L)
        if (length(dynamic)) {
          q(all(idx[dynamic] < h), "current/future responses cannot enter the input")
          input[dynamic] <- if (block == "beta") prefix[idx[dynamic]] else
            binding$ensemble_center[idx[dynamic]] - prefix[idx[dynamic]]
        }
        next_states[[block]][[i]] <- e$app_qdesn_continue_one_step(
          state$states[[block]][[i]], input, fit$reservoir, fit$meta)
        rows[[block]] <- c(1, e$app_qdesn_readout_row_from_states(
          next_states[[block]][[i]], fit$reservoir))
      }
      mu_y[[i]] <- sum(rows$beta * beta)
      mu_g[[i]] <- mu_y[[i]] + sum(rows$alpha * alpha) + binding$known_baseline[[h]]
      q(all(is.finite(c(mu_y[[i]], mu_g[[i]]))), "nonfinite retained-DESN location")
      q(length(cache) < max_cache_entries, "exact-prefix cache budget exhausted")
      entry <- list(h = h, prefix = prefix, parameter_key = parameter_key,
        beta_state = next_states$beta[[i]], alpha_state = next_states$alpha[[i]],
        reference = mu_y[[i]], ensemble = mu_g[[i]])
      if (isTRUE(retain_features)) {
        beta_rows[i, ] <- rows$beta
        alpha_rows[i, ] <- rows$alpha
        entry$beta_row <- rows$beta
        entry$alpha_row <- rows$alpha
      }
      cache[[length(cache) + 1L]] <<- entry
    }
    steps <<- steps + 1L
    list(state = list(states = next_states, ancestor_ids = state$ancestor_ids),
      reference = mu_y, ensemble = mu_g,
      beta_features = beta_rows, alpha_features = alpha_rows)
  }
  resample <- function(state, selected) {
    q(is.numeric(selected) && length(selected) == length(state$ancestor_ids) &&
      all(selected == floor(selected)) && all(selected %in% seq_along(state$ancestor_ids)),
      "valid resampling ancestry required")
    resamples <<- resamples + 1L
    list(states = lapply(state$states, function(x) x[selected]),
      ancestor_ids = state$ancestor_ids[selected])
  }
  diagnostics <- function() list(schema_version = "glofas_two_desn_particle_backend_diagnostics_v1",
    cache_entries = length(cache), cache_hits = hits, cache_misses = misses,
    step_calls = steps, resample_calls = resamples,
    exact_complete_prefix_comparison = TRUE, rounded_keys = FALSE,
    cache_parameter_identity = "exact_coefficients_and_source_scales_sha256",
    cache_reset_scope = "one_parameter_evaluation", both_desn_states_carried = TRUE,
    feature_rows_retained = isTRUE(retain_features),
    original_file_reads = 0L, future_truth_read = FALSE,
    production_qualified = FALSE)
  list(schema_version = "glofas_two_desn_particle_state_backend_v1",
    initial = initial, step = step, resample = resample, diagnostics = diagnostics,
    production_qualified = FALSE)
}

gtdpb_reference_locations <- function(binding, path, parameters) {
  q <- gtdpb_require
  q(is.numeric(path) && length(path) == binding$horizon && all(is.finite(path)),
    "one complete finite response path required")
  backend <- gtdpb_state_backend(binding)
  state <- backend$initial(1L, parameters)
  paths <- matrix(NA_real_, 1L, binding$horizon)
  reference <- ensemble <- numeric(binding$horizon)
  for (h in seq_len(binding$horizon)) {
    stepped <- backend$step(state, h, paths, parameters)
    state <- stepped$state; reference[[h]] <- stepped$reference
    ensemble[[h]] <- stepped$ensemble; paths[1L, h] <- path[[h]]
  }
  list(reference = reference, ensemble = ensemble,
    diagnostics = backend$diagnostics())
}

gtdpb_make_evidence <- function(binding, particles = 128L, ess_fraction = .5,
    limits = list(max_horizon = 28L, max_particles = 4096L, max_calls = 1000000L),
    gates = list(min_ess = 2, min_unique_ancestors = 2L), guide = NULL,
    retain_particles = FALSE) {
  q <- gtdpb_require
  force(binding); force(particles); force(ess_fraction); force(limits); force(gates)
  force(guide); force(retain_particles)
  function(eta, seed) {
    decoded <- gcat_decode(eta, binding$spec)
    parameters <- list(coefficients = decoded$coefficients, sigma = decoded$sigma)
    backend <- gtdpb_state_backend(binding)
    out <- gpg_smc(parameters = parameters, location = NULL,
      scale = unname(parameters$sigma[["Y"]]), member_location = NULL,
      member_scale = unname(parameters$sigma[["G"]]), members = binding$members,
      horizon = binding$horizon, probability = binding$spec$probability,
      particles = particles, ess_fraction = ess_fraction, seed = seed,
      guide = guide, limits = limits, gates = gates, state_backend = backend)
    answer <- list(log_estimate = out$log_normalizer_estimate,
      complete = out$complete,
      diagnostic_thresholds_passed = out$diagnostic_thresholds_passed,
      callback_calls = out$callback_calls, failure = out$failure,
      min_ess = if (nrow(out$diagnostics)) min(out$diagnostics$effective_sample_size) else NA_real_,
      min_unique_ancestors = if (nrow(out$diagnostics))
        min(out$diagnostics$unique_initial_ancestors) else NA_integer_,
      member_factors_per_path = binding$member_factors_per_path,
      member_weights = rep(1, 51L), parameter_dimensions = binding$spec$dimension,
      target_identity = binding$target_identity,
      backend_diagnostics = out$state_backend_diagnostics,
      production_qualified = FALSE, native_application_qualified = FALSE)
    if (isTRUE(retain_particles)) answer$particle_output <- out
    answer
  }
}
