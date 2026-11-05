# Single-pass causal AL innovation coordinates for retained two-DESN contexts.
# This optional conditional-reference adapter performs no original-file reads,
# parameter updates, sampling, resource admission or publication. Authentic use
# requires its own source-pinned read purpose and bounded native allocation.
# The complete issued ensemble enters through 51 ordinary likelihood factors.

giv_state_factory <- function(engine, context, theta, known = NULL, scales,
    max_eval, probability = .5) {
  q <- gnr_require
  q(is.list(engine) && is.environment(engine$env) && is.environment(engine$audit),
    "fresh local evaluator environment required")
  q(is.numeric(max_eval) && length(max_eval) == 1L && is.finite(max_eval) &&
    max_eval == floor(max_eval) && max_eval >= 1L && max_eval <= 1e7,
    "explicit finite streaming evaluation cap required")
  q(identical(as.numeric(gic_probability(probability)), .5),
    "initial streaming admission supports AL median only")
  context <- gnr_context(list(future_context = context), engine)
  e <- engine$env
  H <- nrow(context$latent_data$future_key)
  dates <- context$latent_data$future_key$target_date
  gnr_number(theta)
  q(is.null(dim(theta)), "fixed coefficient vector required")
  if (is.null(known)) known <- rep(0, H)
  gnr_number(known, H)
  known <- as.numeric(known)
  q((is.list(scales) || is.numeric(scales)) && length(scales) == 2L &&
    !is.null(names(scales)) && !anyDuplicated(names(scales)) &&
    (setequal(names(scales), c("reference", "ensemble")) ||
      setequal(names(scales), c("Y", "G"))),
    "exact named fixed reference/ensemble or Y/G scale pair required")
  pick_scale <- function(primary, alias) {
    supplied <- if (primary %in% names(scales)) scales[[primary]] else NULL
    if (is.null(supplied) && alias %in% names(scales)) supplied <- scales[[alias]]
    q(is.numeric(supplied) && length(supplied) %in% c(1L, H) &&
      all(is.finite(supplied)) && all(supplied > 0),
      paste0("positive fixed ", primary, " scale required"))
    rep_len(supplied, H)
  }
  sigma_y <- pick_scale("reference", "Y")
  sigma_g <- pick_scale("ensemble", "G")
  metadata_start <- length(engine$audit$metadata)
  contracts <- initial <- list()
  widths <- integer(2L); names(widths) <- c("beta", "alpha")
  for (block in names(widths)) {
    fit <- context[[paste0("qfit_", block)]]
    history <- if (block == "beta") context$y_history_full else context$d_history_full
    contract <- e$app_qdesn_compile_future_input_contract(
      spec = fit$meta$reservoir_input_spec, history_dates = fit$meta$history_dates,
      y_history = history, future_dates = dates,
      covariate_timeline = context$covariate_timeline)
    e$app_qdesn_validate_compiled_future_inputs(contract,
      fit$meta$reservoir_input_spec, dates, verify_hash = FALSE)
    # A newly created contract must be strictly causal, even when production
    # validation changes later. No caller-supplied compiled cache is accepted.
    q(all(contract$future_index >= 0L) &&
      all(contract$future_index < row(contract$future_index)),
      "streaming input contract contains a current or future response")
    contracts[[block]] <- contract
    initial[[block]] <- e$app_qdesn_last_states(fit)
    widths[[block]] <- length(e$app_qdesn_readout_row_from_states(
      initial[[block]], fit$reservoir)) + 1L
  }
  columns <- function(n) c("readout_intercept",
    paste0("reservoir_", sprintf("%04d", seq_len(n - 1L))))
  coefficient_names <- c(paste0("beta__", columns(widths[["beta"]])),
    paste0("alpha__", columns(widths[["alpha"]])))
  q(length(theta) == sum(widths), "fixed coefficient/feature dimension mismatch")
  if (!is.null(names(theta))) q(identical(names(theta), coefficient_names),
    "fixed coefficient order differs from retained readout order")
  beta <- as.numeric(theta[seq_len(widths[["beta"]])])
  alpha <- as.numeric(theta[widths[["beta"]] + seq_len(widths[["alpha"]])])
  members <- matrix(NA_real_, nrow = H, ncol = 51L)
  for (h in seq_len(H)) {
    rows <- as.integer(context$latent_data$g_ensemble$horizon) == h
    members[h, ] <- context$latent_data$g_ensemble$g_transformed[rows]
  }
  q(all(is.finite(members)), "all 51 finite members are required")
  oracle <- gcv_make_value_builder(engine, context, max_evaluations = max_eval)
  audit <- new.env(parent = emptyenv())
  audit$calls <- 0L; audit$forward_calls <- 0L; audit$inverse_calls <- 0L
  audit$reference_calls <- 0L; audit$production_one_step_calls <- 0L
  admit <- function(role, x) {
    q(audit$calls < max_eval, "streaming evaluation cap reached")
    gnr_number(x, H)
    q(is.null(dim(x)), "one finite horizon-length coordinate vector required")
    audit$calls <- audit$calls + 1L
    audit[[paste0(role, "_calls")]] <- audit[[paste0(role, "_calls")]] + 1L
    as.numeric(x)
  }
  assemble <- function(X) {
    for (block in names(X)) colnames(X[[block]]) <- columns(ncol(X[[block]]))
    H_y <- cbind(X$beta, matrix(0, nrow = H, ncol = ncol(X$alpha)))
    H_g_key <- cbind(X$beta, X$alpha)
    colnames(H_y) <- colnames(H_g_key) <- coefficient_names
    list(X_beta_future = X$beta, X_alpha_future = X$alpha,
      H_y = H_y, H_g_key = H_g_key)
  }
  finish <- function(path, z, reference_location, ensemble_location, design) {
    innovation <- (path - reference_location) / sigma_y
    log_reference <- sum(gic_al_log_density(path, reference_location,
      probability, sigma_y))
    log_likelihood <- sum(gic_al_log_density(as.numeric(members),
      rep(ensemble_location, times = 51L), probability, rep(sigma_g, times = 51L)))
    log_base <- sum(stats::dnorm(z, log = TRUE))
    log_jacobian <- sum(log(sigma_y) - gic_al_log_density(innovation,
      probability = probability) + stats::dnorm(z, log = TRUE))
    q(all(is.finite(c(log_reference, log_likelihood, log_base, log_jacobian))),
      "nonrepresentable streaming density or Jacobian")
    list(path = path, base = z, reference_location = reference_location,
      ensemble_location = ensemble_location, log_likelihood = log_likelihood,
      log_base = log_base, log_jacobian = log_jacobian,
      log_reference = log_reference, log_target = log_base + log_likelihood,
      log_path_target = log_reference + log_likelihood,
      identity_residual = log_reference + log_jacobian - log_base,
      design = design, probability = probability,
      parameter_scope = "fixed_parameter_conditional_AL_median_reference",
      member_factors = H * 51L, member_weights = 1,
      original_file_reads = 0L, future_truth_read = FALSE,
      production_default_changed = FALSE)
  }
  forward <- function(z) {
    z <- admit("forward", z)
    innovation <- gic_al_standardized_from_normal(z, probability)
    # Local copies begin at the same retained cutoff states for every call.
    states <- initial
    path <- mu_y <- mu_g <- numeric(H)
    X <- list(beta = matrix(NA_real_, H, widths[["beta"]]),
      alpha = matrix(NA_real_, H, widths[["alpha"]]))
    for (h in seq_len(H)) {
      for (block in names(widths)) {
        fit <- context[[paste0("qfit_", block)]]
        input <- contracts[[block]]$static_values[h, ]
        idx <- contracts[[block]]$future_index[h, ]
        dynamic <- which(idx > 0L)
        if (length(dynamic)) {
          q(all(idx[dynamic] < h), "noncausal response encountered in streaming continuation")
          input[dynamic] <- if (block == "beta") path[idx[dynamic]] else
            context$glofas_future_center_path[idx[dynamic]] - path[idx[dynamic]]
        }
        states[[block]] <- e$app_qdesn_continue_one_step(states[[block]],
          input, fit$reservoir, fit$meta)
        audit$production_one_step_calls <- audit$production_one_step_calls + 1L
        X[[block]][h, ] <- c(1, e$app_qdesn_readout_row_from_states(
          states[[block]], fit$reservoir))
      }
      # Both feature blocks use only previously generated responses. In
      # particular, the current y_h is not used to obtain either location.
      mu_y[h] <- sum(X$beta[h, ] * beta)
      mu_g[h] <- mu_y[h] + sum(X$alpha[h, ] * alpha) + known[h]
      path[h] <- mu_y[h] + sigma_y[h] * innovation[h]
      q(is.finite(path[h]), "nonrepresentable generated response")
    }
    finish(path, z, mu_y, mu_g, assemble(X))
  }
  reference_value <- function(y, role) {
    y <- admit(role, y)
    design <- oracle(y)
    mu_y <- as.numeric(design$H_y %*% theta)
    mu_g <- as.numeric(design$H_g_key %*% theta) + known
    z <- gic_al_normal_from_standardized((y - mu_y) / sigma_y, probability)
    finish(y, z, mu_y, mu_g, design)
  }
  diagnostics <- function() list(schema_version = "glofas_innovation_streaming_v1",
    calls = audit$calls, max_eval = max_eval, forward_calls = audit$forward_calls,
    inverse_calls = audit$inverse_calls, reference_calls = audit$reference_calls,
    forward_whole_path_callbacks = 0L,
    production_one_step_calls = audit$production_one_step_calls,
    oracle = gcv_diagnostics(oracle), static_contracts = 2L,
    context_sha256 = gnr_hash(context), coefficient_sha256 = gnr_hash(theta),
    scales_sha256 = gnr_hash(list(reference = sigma_y, ensemble = sigma_g)),
    known_baseline_sha256 = gnr_hash(known),
    generated_metadata_serializations = length(engine$audit$metadata) - metadata_start,
    original_file_reads = 0L, parameter_updates = 0L, saved_callback_calls = 0L,
    random_weight_generations = 0L, future_truth_read = FALSE,
    parameter_scope = "fixed_parameter_conditional_AL_median_reference",
    native_read_or_launch_authorized = FALSE, production_default_changed = FALSE)
  list(forward = forward, inverse = function(y) reference_value(y, "inverse"),
    reference = function(y) reference_value(y, "reference"), diagnostics = diagnostics)
}
