# Grouped-RHS mechanism campaign for the GloFAS p50 discrepancy readout.

app_glofas_grouped_rhs_validate_campaign <- function(campaign) {
  if (!is.list(campaign) || !nzchar(as.character(campaign$campaign_id %||% ""))) {
    stop("Grouped-RHS campaign requires a nonempty campaign_id.", call. = FALSE)
  }
  expected_inference <- c(
    max_iter = 200, max_iter_hard_cap = 200, min_iter_elbo = 20,
    tol = 1e-4, tol_par = 1e-4, n_draws = 1000, n_samp_xi = 500
  )
  observed_inference <- vapply(names(expected_inference), function(name) {
    as.numeric(campaign$inference[[name]] %||% NA_real_)
  }, numeric(1L))
  if (any(!is.finite(observed_inference)) ||
      any(abs(observed_inference - expected_inference) > 1.0e-15)) {
    stop("Campaign inference values disagree with the prospectively frozen Stage A contract.", call. = FALSE)
  }
  quantile_level <- as.numeric(campaign$quantile_level %||% NA_real_)
  if (!is.finite(quantile_level) || abs(quantile_level - 0.5) > 1.0e-15 ||
      as.integer(campaign$waves$A0$expected_candidates %||% NA_integer_) != 8L ||
      as.integer(campaign$waves$A1$expected_candidates %||% NA_integer_) != 10L) {
    stop("Campaign quantile or A0/A1 candidate counts changed after review.", call. = FALSE)
  }
  execution <- campaign$execution %||% list()
  if (as.integer(execution$max_workers %||% NA_integer_) != 20L ||
      as.integer(execution$a0_calibration_jobs %||% NA_integer_) != 4L ||
      as.integer(execution$calibration_iterations %||% NA_integer_) != 10L ||
      as.integer(execution$backend_threads %||% NA_integer_) != 1L ||
      !identical(as.character(execution$numerical_backend %||% ""), "openblas_serial")) {
    stop("Campaign execution values disagree with the reviewed resource contract.", call. = FALSE)
  }
  numerical <- execution$warm_start_numerical_equivalence %||% list()
  if (!isTRUE(all.equal(
    as.numeric(numerical$absolute_tolerance %||% NA_real_),
    1.0e-10,
    tolerance = 0
  )) || !isTRUE(all.equal(
    as.numeric(numerical$scaled_rmse_tolerance %||% NA_real_),
    1.0e-12,
    tolerance = 0
  )) || as.integer(numerical$chunk_elements %||% NA_integer_) != 1000000L) {
    stop("Campaign numerical warm-start tolerances disagree with the reviewed contract.", call. = FALSE)
  }
  decision <- unlist(campaign$decision %||% list(), use.names = TRUE)
  decision_numeric <- suppressWarnings(as.numeric(decision))
  if (!length(decision_numeric) || any(!is.finite(decision_numeric)) || any(decision_numeric < 0)) {
    stop("Campaign decision thresholds must be finite and nonnegative.", call. = FALSE)
  }
  invisible(campaign)
}

app_glofas_grouped_rhs_stage_a_candidates <- function() {
  a0 <- data.frame(
    candidate_id = sprintf("grhs_a0_%02d", seq_len(8L)),
    wave = "A0",
    priority = seq_len(8L),
    candidate_role = c(
      "ungrouped_d16_cold", "ungrouped_d16_warm", "grouped_equal_cold",
      "reverse_direction_warm", "direct_only_cold", "reservoir_only_cold",
      "directional_moderate_warm", "directional_strong_warm"
    ),
    readout_mode = c("complete", "complete", "complete", "complete", "direct_only", "reservoir_only", "complete", "complete"),
    grouping_enabled = c(FALSE, FALSE, TRUE, TRUE, FALSE, FALSE, TRUE, TRUE),
    tau0_direct = c(NA, NA, 1e-4, 1e-2, NA, NA, 1e-5, 1e-6),
    tau0_reservoir = c(NA, NA, 1e-4, 1e-4, NA, NA, 1e-2, 1e-1),
    warm_start_policy = c("cold", "warm", "cold", "warm", "cold", "cold", "warm", "warm"),
    replicate_group = c("ungrouped_d16", "ungrouped_d16", rep("", 6L)),
    stringsAsFactors = FALSE
  )
  support <- expand.grid(
    tau0_direct = c(1e-6, 1e-5, 1e-4, 1e-3),
    tau0_reservoir = c(1e-3, 1e-2, 1e-1),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  consumed <- (support$tau0_direct == 1e-5 & support$tau0_reservoir == 1e-2) |
    (support$tau0_direct == 1e-6 & support$tau0_reservoir == 1e-1)
  support <- support[!consumed, , drop = FALSE]
  support <- support[order(support$tau0_direct, support$tau0_reservoir), , drop = FALSE]
  a1 <- data.frame(
    candidate_id = sprintf("grhs_a1_%02d", seq_len(nrow(support))),
    wave = "A1",
    priority = 8L + seq_len(nrow(support)),
    candidate_role = "directional_grid_warm",
    readout_mode = "complete",
    grouping_enabled = TRUE,
    tau0_direct = support$tau0_direct,
    tau0_reservoir = support$tau0_reservoir,
    warm_start_policy = "warm",
    replicate_group = "",
    stringsAsFactors = FALSE
  )
  out <- rbind(a0, a1)
  out$model_label <- ifelse(
    out$grouping_enabled,
    sprintf("grouped_d%.0e_r%.0e", out$tau0_direct, out$tau0_reservoir),
    paste0("ungrouped_", out$readout_mode)
  )
  rownames(out) <- NULL
  app_glofas_grouped_rhs_validate_candidates(out)
  out
}

app_glofas_grouped_rhs_candidate_effective_spec <- function(row) {
  stopifnot(is.data.frame(row), nrow(row) == 1L)
  list(
    schema_version = "glofas_grouped_rhs_candidate_effective_v1",
    frozen_geometry = "reference_fr09__discrepancy_d16w64m1080_a075_r095_seed20261521",
    readout_mode = as.character(row$readout_mode[[1L]]),
    alpha_prior = if (isTRUE(as.logical(row$grouping_enabled[[1L]]))) {
      list(
        prior = "grouped_rhs_ns",
        tau0 = c(
          direct = as.numeric(row$tau0_direct[[1L]]),
          reservoir = as.numeric(row$tau0_reservoir[[1L]])
        ),
        shared_dynamic_zeta = c(a_zeta = 2, b_zeta = 4)
      )
    } else {
      list(
        prior = "rhs_ns", tau0 = 1e-4,
        shared_dynamic_zeta = c(a_zeta = 2, b_zeta = 4)
      )
    },
    beta_prior = list(prior = "rhs_ns", tau0 = 0.1, a_zeta = 2, b_zeta = 4),
    inference = list(max_iter = 200L, tol = 1e-4, tol_par = 1e-4, n_draws = 1000L, n_samp_xi = 500L),
    transition = "persistence_anchored_innovation",
    quantile = 0.5
  )
}

app_glofas_grouped_rhs_validate_candidates <- function(candidates) {
  required <- c(
    "candidate_id", "wave", "priority", "candidate_role", "readout_mode",
    "grouping_enabled", "tau0_direct", "tau0_reservoir", "warm_start_policy",
    "replicate_group"
  )
  missing <- setdiff(required, names(candidates))
  if (!is.data.frame(candidates) || length(missing)) {
    stop(sprintf("Grouped-RHS candidate manifest is missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  if (nrow(candidates) != 18L || sum(candidates$wave == "A0") != 8L || sum(candidates$wave == "A1") != 10L) {
    stop("Grouped-RHS Stage A must contain exactly 8 A0 and 10 A1 candidates.", call. = FALSE)
  }
  if (anyDuplicated(candidates$candidate_id) || anyDuplicated(candidates$priority)) {
    stop("Grouped-RHS candidate IDs and priorities must be unique.", call. = FALSE)
  }
  grouped <- app_as_bool_vec(candidates$grouping_enabled)
  if (any(!is.finite(candidates$tau0_direct[grouped]) | candidates$tau0_direct[grouped] <= 0) ||
      any(!is.finite(candidates$tau0_reservoir[grouped]) | candidates$tau0_reservoir[grouped] <= 0)) {
    stop("Every grouped candidate requires positive direct and reservoir tau0 values.", call. = FALSE)
  }
  if (any(!candidates$readout_mode %in% c("complete", "direct_only", "reservoir_only")) ||
      any(!candidates$warm_start_policy %in% c("cold", "warm"))) {
    stop("Grouped-RHS candidate readout or warm-start policy is invalid.", call. = FALSE)
  }
  hashes <- vapply(seq_len(nrow(candidates)), function(i) {
    app_qdesn_hash_object(
      app_glofas_grouped_rhs_candidate_effective_spec(candidates[i, , drop = FALSE]),
      prefix = "glofas_grouped_rhs_candidate_"
    )
  }, character(1L))
  duplicate_groups <- split(seq_along(hashes), hashes)
  for (index in duplicate_groups[vapply(duplicate_groups, length, integer(1L)) > 1L]) {
    allowed <- unique(candidates$replicate_group[index])
    treatments <- unique(candidates$warm_start_policy[index])
    if (length(allowed) != 1L || !nzchar(allowed) || length(treatments) != length(index)) {
      stop("Effective duplicate candidates are allowed only for declared initialization canaries.", call. = FALSE)
    }
  }
  invisible(candidates)
}

app_glofas_grouped_rhs_apply_candidate <- function(base_cfg, row) {
  stopifnot(is.data.frame(row), nrow(row) == 1L)
  cfg <- base_cfg
  mode <- as.character(row$readout_mode[[1L]])
  discrepancy <- app_qdesn_block_override(cfg, "discrepancy")
  discrepancy$readout <- discrepancy$readout %||% list()
  if (identical(mode, "direct_only")) {
    discrepancy$readout$include_reservoir_state <- FALSE
    discrepancy$readout$reservoir_state_lags <- integer()
    discrepancy$readout$include_input_block <- TRUE
  } else if (identical(mode, "reservoir_only")) {
    discrepancy$readout$include_reservoir_state <- TRUE
    discrepancy$readout$include_input_block <- FALSE
    discrepancy$readout$include_horizon_scaled <- FALSE
  }
  fc <- cfg$feature_contract %||% cfg$features %||% list()
  fc$two_block_design <- TRUE
  fc$blocks <- fc$blocks %||% list()
  fc$blocks$discrepancy <- discrepancy
  cfg$feature_contract <- fc

  vb <- cfg$inference$vb_ld %||% list()
  vb$max_iter <- 200L
  vb$max_iter_hard_cap <- 200L
  vb$min_iter_elbo <- 20L
  vb$tol <- 1e-4
  vb$tol_par <- 1e-4
  vb$n_draws <- 1000L
  vb$n_samp_xi <- 500L
  vb$rhs_tau0 <- 0.1
  vb$rhs_alpha_tau0 <- 1e-4
  vb$rhs_slab_s2 <- 1
  vb$rhs_alpha_slab_s2 <- 1
  vb$rhs_a_zeta <- 2
  vb$rhs_b_zeta <- 4
  vb$rhs_alpha_a_zeta <- 2
  vb$rhs_alpha_b_zeta <- 4
  vb$rhs_freeze_tau_warmup_iters <- 50L
  vb$rhs_update_every <- 1L
  vb$rhs_min_tau_updates <- 1L
  vb$rhs_alpha_grouping <- if (isTRUE(as.logical(row$grouping_enabled[[1L]]))) {
    list(
      enabled = TRUE,
      mode = "direct_reservoir",
      tau0 = list(
        direct = as.numeric(row$tau0_direct[[1L]]),
        reservoir = as.numeric(row$tau0_reservoir[[1L]])
      )
    )
  } else {
    list(enabled = FALSE, mode = "direct_reservoir")
  }
  vb$diagnostics <- app_qdesn_deep_merge(
    vb$diagnostics %||% list(),
    list(trace_iterations = TRUE, fixed_iterations = FALSE, profile_substeps = FALSE)
  )
  cfg$inference$vb_ld <- vb
  app_qdesn_validate_block_configs(cfg)
  cfg
}

app_glofas_grouped_rhs_candidate_hashes <- function(cfg, row) {
  vb_args <- app_make_qdesn_discrepancy_vb_args(
    cfg, prior = "rhs_ns", seed = 20260512L, likelihood_family = "al"
  )
  effective_spec <- app_glofas_grouped_rhs_candidate_effective_spec(row)
  list(
    scientific_model_hash = app_qdesn_hash_object(effective_spec, "glofas_grouped_rhs_model_"),
    treatment_hash = app_qdesn_hash_object(
      list(effective_spec = effective_spec, warm_start_policy = row$warm_start_policy[[1L]]),
      "glofas_grouped_rhs_treatment_"
    ),
    prior_declared_hash = vb_args$prior_contract$declared_hash,
    prior_effective_hash = vb_args$prior_contract$effective_hash
  )
}

app_glofas_grouped_rhs_score_identity <- function(forecast, candidate_id, tolerance = 1e-10) {
  required <- c("target_date", "horizon", "raw_glofas_quantile", "y_reference", "d_g_median", "q_y_median")
  missing <- setdiff(required, names(forecast))
  if (!is.data.frame(forecast) || !nrow(forecast) || length(missing)) {
    stop(sprintf("Forecast summary is empty or missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  observed_discrepancy <- as.numeric(forecast$raw_glofas_quantile) - as.numeric(forecast$y_reference)
  predicted_discrepancy <- as.numeric(forecast$d_g_median)
  corrected_reference <- as.numeric(forecast$raw_glofas_quantile) - predicted_discrepancy
  discrepancy_error <- predicted_discrepancy - observed_discrepancy
  corrected_error <- corrected_reference - as.numeric(forecast$y_reference)
  path <- data.frame(
    candidate_id = candidate_id,
    target_date = as.Date(forecast$target_date),
    horizon = as.integer(forecast$horizon),
    raw_glofas = as.numeric(forecast$raw_glofas_quantile),
    observed_reference = as.numeric(forecast$y_reference),
    observed_discrepancy = observed_discrepancy,
    predicted_discrepancy = predicted_discrepancy,
    corrected_reference = corrected_reference,
    model_q_y_median = as.numeric(forecast$q_y_median),
    discrepancy_error = discrepancy_error,
    corrected_reference_error = corrected_error,
    stringsAsFactors = FALSE
  )
  if (anyDuplicated(path$horizon) || !identical(sort(path$horizon), seq_len(28L))) {
    stop("Grouped-RHS scoring requires exactly one forecast row for each horizon 1:28.", call. = FALSE)
  }
  lead_group <- cut(
    path$horizon,
    breaks = c(0, 7, 14, Inf),
    labels = c("days_01_07", "days_08_14", "days_15_28"),
    right = TRUE
  )
  summarize <- function(index, label) {
    error <- path$discrepancy_error[index]
    corrected <- path$corrected_reference_error[index]
    algebra_error <- max(abs(abs(error) - abs(corrected)))
    model_identity_error <- max(abs(
      path$model_q_y_median[index] - path$corrected_reference[index]
    ))
    data.frame(
      candidate_id = candidate_id,
      lead_group = label,
      n = sum(index),
      discrepancy_mae = mean(abs(error)),
      discrepancy_rmse = sqrt(mean(error^2)),
      discrepancy_bias = mean(error),
      corrected_reference_mae = mean(abs(corrected)),
      corrected_reference_p50_check_loss = mean(0.5 * abs(corrected)),
      max_rowwise_absolute_error_identity = algebra_error,
      model_summary_vs_constructed_correction_max_abs = model_identity_error,
      identity_tolerance = tolerance,
      algebra_identity_passed = algebra_error <= tolerance,
      model_identity_passed = model_identity_error <= tolerance,
      identity_passed = algebra_error <= tolerance && model_identity_error <= tolerance,
      stringsAsFactors = FALSE
    )
  }
  rows <- list(summarize(rep(TRUE, nrow(path)), "all"))
  for (label in levels(lead_group)) {
    rows[[length(rows) + 1L]] <- summarize(lead_group == label, label)
  }
  list(path = path, summary = do.call(rbind, rows))
}

app_glofas_grouped_rhs_diagnostic_layout <- function(feature_info, intercept_index) {
  if (!is.data.frame(feature_info) || !nrow(feature_info)) {
    stop("Diagnostic grouped-RHS layout requires semantic alpha feature metadata.", call. = FALSE)
  }
  required <- c("column_index", "column_name", "block", "variable", "is_intercept")
  missing <- setdiff(required, names(feature_info))
  if (length(missing)) {
    stop(sprintf("Diagnostic alpha feature metadata is missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  p <- nrow(feature_info)
  if (!identical(as.integer(feature_info$column_index), seq_len(p)) || anyDuplicated(feature_info$column_name)) {
    stop("Diagnostic alpha feature metadata must be ordered, contiguous, and uniquely named.", call. = FALSE)
  }
  intercept_index <- sort(unique(as.integer(intercept_index %||% integer())))
  semantic_intercept <- which(
    app_as_bool_vec(feature_info$is_intercept) |
      as.character(feature_info$block) == "readout_intercept"
  )
  if (!identical(intercept_index, as.integer(semantic_intercept))) {
    stop("Diagnostic alpha intercept indices disagree with semantic feature metadata.", call. = FALSE)
  }
  block <- as.character(feature_info$block)
  groups <- list(
    direct = which(
      block %in% c("direct_output_lag", "direct_covariate_lag", "horizon") &
        !(seq_len(p) %in% intercept_index)
    ),
    reservoir = which(
      block %in% c("reservoir_state", "reservoir_state_lag") &
        !(seq_len(p) %in% intercept_index)
    )
  )
  groups <- groups[vapply(groups, length, integer(1L)) > 0L]
  penalized <- setdiff(seq_len(p), intercept_index)
  assigned <- unlist(groups, use.names = FALSE)
  if (!length(groups) || anyDuplicated(assigned) || !identical(sort(assigned), penalized)) {
    stop("Diagnostic alpha feature groups do not exactly partition the fitted readout.", call. = FALSE)
  }
  hash_input <- list(groups = groups, intercept_index = intercept_index, feature_info = feature_info)
  list(
    schema_version = "qdesn_rhs_alpha_diagnostic_layout_v1",
    enabled = FALSE,
    mode = "diagnostic_semantic_partition",
    p = p,
    penalized = penalized,
    intercept_index = intercept_index,
    groups = groups,
    layout_hash = app_qdesn_hash_object(hash_input, prefix = "qdesn_rhs_alpha_diagnostic_layout_")
  )
}

app_glofas_grouped_rhs_contributions <- function(fit, design, candidate_id) {
  layout <- fit$rhs_alpha_group_layout %||% NULL
  feature_info <- design$feature_info_alpha
  if (is.null(layout)) {
    intercept <- app_latent_prior_block_intercepts(design$alpha_index, design$intercept_index)
    layout <- app_glofas_grouped_rhs_diagnostic_layout(feature_info, intercept)
  }
  theta <- as.numeric(fit$variational_state$theta_mean)
  alpha <- theta[design$alpha_index]
  exact <- app_glofas_mechanism_exact_future_design(
    design,
    as.numeric(fit$variational_state$y_future_mean)
  )
  X <- as.matrix(exact$X_alpha_future)
  contribution_groups <- layout$groups
  if (length(layout$intercept_index %||% integer())) {
    contribution_groups$intercept <- as.integer(layout$intercept_index)
  }
  rows <- lapply(names(contribution_groups), function(group_name) {
    idx <- contribution_groups[[group_name]]
    value <- as.numeric(X[, idx, drop = FALSE] %*% alpha[idx])
    data.frame(
      candidate_id = candidate_id,
      horizon = as.integer(design$future_key$horizon),
      rhs_global_group = group_name,
      contribution = value,
      stringsAsFactors = FALSE
    )
  })
  paths <- do.call(rbind, rows)
  summary <- do.call(rbind, lapply(split(paths, paths$rhs_global_group), function(x) {
    data.frame(
      candidate_id = candidate_id,
      rhs_global_group = x$rhs_global_group[[1L]],
      contribution_mean = mean(x$contribution),
      contribution_sd = stats::sd(x$contribution),
      contribution_rms = sqrt(mean(x$contribution^2)),
      contribution_max_abs = max(abs(x$contribution)),
      stringsAsFactors = FALSE
    )
  }))
  penalized <- summary$rhs_global_group != "intercept"
  total_rms <- sum(summary$contribution_rms[penalized])
  summary$rms_share <- NA_real_
  summary$rms_share[penalized] <- if (total_rms > 0) {
    summary$contribution_rms[penalized] / total_rms
  } else {
    0
  }
  reconstructed <- aggregate(contribution ~ horizon, paths, sum)
  target <- as.numeric(X %*% alpha)
  reconstruction_error <- max(abs(
    reconstructed$contribution[match(design$future_key$horizon, reconstructed$horizon)] - target
  ))
  summary$innovation_reconstruction_max_abs <- reconstruction_error
  summary$discrepancy_baseline_rms <- sqrt(mean(
    as.numeric(exact$discrepancy_baseline_future %||% rep(0, nrow(X)))^2
  ))
  list(paths = paths, summary = summary, layout = layout)
}

app_glofas_grouped_rhs_historical_guards <- function(
  scores,
  baseline,
  repeat_envelope = 0,
  hard_limits = c(all = 0.02, last1000 = 0.02, last200 = 0.05),
  warning_limits = c(last50 = 0.10)
) {
  if (is.null(names(hard_limits)) || is.null(names(warning_limits)) ||
      any(!is.finite(c(hard_limits, warning_limits))) || any(c(hard_limits, warning_limits) < 0)) {
    stop("Historical guard limits must be nonnegative named values.", call. = FALSE)
  }
  limits <- c(hard_limits, warning_limits)
  rows <- lapply(names(limits), function(window) {
    value <- as.numeric(scores$log1p_mae[scores$window == window])
    reference <- as.numeric(baseline$log1p_mae[baseline$window == window])
    if (length(value) != 1L || length(reference) != 1L || any(!is.finite(c(value, reference)))) {
      stop(sprintf("Historical guard lacks one finite %s score.", window), call. = FALSE)
    }
    limit <- 1 + max(limits[[window]], 2 * repeat_envelope)
    is_hard_gate <- window %in% names(hard_limits)
    data.frame(
      window = window,
      candidate_mae = value,
      baseline_mae = reference,
      ratio = value / reference,
      hard_limit = limit,
      is_hard_gate = is_hard_gate,
      passed = !is_hard_gate || value / reference <= limit,
      warning_triggered = !is_hard_gate && value / reference > limit,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_glofas_grouped_rhs_effective_prior_duplicate_key <- function(vb_args, alpha_layout = NULL) {
  app_qdesn_latent_vb_prior_contract(vb_args, alpha_layout)$effective_hash
}

app_glofas_grouped_rhs_validate_fit_contract <- function(
  fit,
  design,
  runtime_row,
  candidate_row
) {
  if (!is.list(fit) || !is.list(design) || !is.data.frame(runtime_row) ||
      nrow(runtime_row) != 1L || !is.data.frame(candidate_row) || nrow(candidate_row) != 1L) {
    stop("Grouped-RHS fit-contract validation received malformed inputs.", call. = FALSE)
  }
  prior <- fit$prior_contract %||% NULL
  if (!is.list(prior) || !is.list(prior$declared) || !is.list(prior$effective)) {
    stop("Fitted object lacks the declared/effective prior contract.", call. = FALSE)
  }
  declared_hash <- app_qdesn_hash_object(
    prior$declared,
    prefix = "qdesn_prior_declared_"
  )
  effective_hash <- app_qdesn_hash_object(
    prior$effective,
    prefix = "qdesn_prior_effective_"
  )
  expected_grouped <- isTRUE(app_as_bool_vec(candidate_row$grouping_enabled)[[1L]])
  actual_grouping <- prior$declared$alpha$grouping %||% list(enabled = FALSE)
  actual_grouped <- isTRUE(actual_grouping$enabled)
  alpha_intercept <- app_latent_prior_block_intercepts(
    design$alpha_index,
    design$intercept_index
  )
  recomputed_layout <- app_qdesn_alpha_rhs_group_layout(
    feature_info = design$feature_info_alpha,
    intercept_index = alpha_intercept,
    grouping = actual_grouping
  )
  fitted_layout <- fit$rhs_alpha_group_layout %||% NULL

  pre_layout_effective <- prior$effective
  if (actual_grouped) {
    pre_layout_effective$alpha$group_layout_hash <- NA_character_
  }
  pre_layout_hash <- app_qdesn_hash_object(
    pre_layout_effective,
    prefix = "qdesn_prior_effective_"
  )
  expected_tau <- c(
    direct = suppressWarnings(as.numeric(candidate_row$tau0_direct[[1L]])),
    reservoir = suppressWarnings(as.numeric(candidate_row$tau0_reservoir[[1L]]))
  )
  actual_tau <- as.numeric(actual_grouping$tau0 %||% numeric())
  names(actual_tau) <- names(actual_grouping$tau0 %||% numeric())
  tau_match <- if (expected_grouped) {
    identical(names(actual_tau), names(expected_tau)) &&
      all(abs(actual_tau - expected_tau) <= 1.0e-15)
  } else {
    !actual_grouped
  }
  layout_match <- if (expected_grouped) {
    is.list(fitted_layout) && is.list(recomputed_layout) &&
      identical(fitted_layout$layout_hash, recomputed_layout$layout_hash) &&
      identical(fitted_layout$groups, recomputed_layout$groups)
  } else {
    is.null(fitted_layout) && is.null(recomputed_layout)
  }
  diagnostics <- fit$vb_diagnostics %||% list()
  checks <- data.frame(
    check = c(
      "declared_hash_internal", "effective_hash_internal",
      "declared_hash_manifest", "effective_hash_pre_layout_manifest",
      "grouping_enabled", "group_tau0", "semantic_layout",
      "diagnostic_declared_hash", "diagnostic_effective_hash",
      "diagnostic_layout_hash"
    ),
    passed = c(
      identical(as.character(prior$declared_hash), declared_hash),
      identical(as.character(prior$effective_hash), effective_hash),
      identical(as.character(runtime_row$prior_declared_hash[[1L]]), declared_hash),
      identical(as.character(runtime_row$prior_effective_hash_pre_layout[[1L]]), pre_layout_hash),
      identical(actual_grouped, expected_grouped),
      tau_match,
      layout_match,
      identical(as.character(diagnostics$prior_declared_hash %||% NA_character_), declared_hash),
      identical(as.character(diagnostics$prior_effective_hash %||% NA_character_), effective_hash),
      identical(
        as.character(diagnostics$rhs_alpha_group_layout_hash %||% NA_character_),
        as.character(if (expected_grouped) fitted_layout$layout_hash else NA_character_)
      )
    ),
    stringsAsFactors = FALSE
  )
  list(
    passed = all(checks$passed),
    checks = checks,
    declared_hash = declared_hash,
    effective_hash = effective_hash,
    layout_hash = if (expected_grouped) {
      as.character((fitted_layout %||% list())$layout_hash %||% NA_character_)
    } else {
      NA_character_
    }
  )
}
