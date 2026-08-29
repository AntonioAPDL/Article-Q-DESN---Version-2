# Pre-screen diagnostics for GloFAS discrepancy transition and information contracts.

app_glofas_transition_require_columns <- function(x, required, label) {
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(sprintf("%s is missing columns: %s", label, paste(missing, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_transition_operator <- function(horizon, phi) {
  horizon <- suppressWarnings(as.integer(horizon))
  phi <- suppressWarnings(as.numeric(phi))
  if (!length(horizon) || any(!is.finite(horizon)) ||
      !identical(horizon, seq_len(length(horizon)))) {
    stop("Transition horizons must be ordered contiguous integers starting at one.", call. = FALSE)
  }
  if (length(phi) != 1L || !is.finite(phi) || phi < 0 || phi > 1) {
    stop("Transition damping phi must be one finite value in [0, 1].", call. = FALSE)
  }
  H <- length(horizon)
  out <- matrix(0, nrow = H, ncol = H)
  for (h in horizon) {
    index <- seq_len(h)
    out[h, index] <- phi^(h - index)
  }
  dimnames(out) <- list(sprintf("h%03d", horizon), sprintf("innovation_h%03d", horizon))
  out
}

app_glofas_transition_path <- function(last_discrepancy, innovation, phi) {
  last_discrepancy <- suppressWarnings(as.numeric(last_discrepancy))
  innovation <- as.numeric(innovation)
  if (length(last_discrepancy) != 1L || !is.finite(last_discrepancy) ||
      !length(innovation) || any(!is.finite(innovation))) {
    stop("Transition paths require a finite scalar anchor and finite innovations.", call. = FALSE)
  }
  as.numeric(last_discrepancy + app_glofas_transition_operator(seq_along(innovation), phi) %*% innovation)
}

app_glofas_transition_design <- function(X, phi) {
  X <- as.matrix(X)
  if (!nrow(X) || !ncol(X) || any(!is.finite(X))) {
    stop("Transition design transformation requires a finite non-empty matrix.", call. = FALSE)
  }
  app_glofas_transition_operator(seq_len(nrow(X)), phi) %*% X
}

app_glofas_transition_jacobians <- function(jacobians, phi) {
  if (!is.list(jacobians) || !length(jacobians)) {
    stop("Transition Jacobians must be a non-empty list.", call. = FALSE)
  }
  dims <- lapply(jacobians, dim)
  if (any(vapply(dims, is.null, logical(1L))) ||
      !all(vapply(dims, identical, logical(1L), dims[[1L]]))) {
    stop("Transition Jacobians must have one common matrix dimension.", call. = FALSE)
  }
  if (any(!vapply(jacobians, function(x) all(is.finite(x)), logical(1L)))) {
    stop("Transition Jacobians must be finite.", call. = FALSE)
  }
  L <- app_glofas_transition_operator(seq_along(jacobians), phi)
  lapply(seq_along(jacobians), function(h) {
    Reduce(`+`, Map(`*`, jacobians[seq_len(h)], as.numeric(L[h, seq_len(h)])))
  })
}

app_glofas_transition_matrix_rank <- function(X) {
  X <- as.matrix(X)
  if (!nrow(X) || !ncol(X) || any(!is.finite(X))) {
    stop("Rank diagnostics require a finite non-empty matrix.", call. = FALSE)
  }
  singular <- svd(X, nu = 0L, nv = 0L)$d
  tolerance <- max(dim(X)) * max(singular) * .Machine$double.eps
  retained <- singular[singular > tolerance]
  data.frame(
    rows = nrow(X),
    columns = ncol(X),
    rank = length(retained),
    full_row_rank = length(retained) == nrow(X),
    condition_number = if (length(retained)) max(retained) / min(retained) else Inf,
    smallest_singular_value = if (length(singular)) min(singular) else NA_real_,
    largest_singular_value = if (length(singular)) max(singular) else NA_real_,
    stringsAsFactors = FALSE
  )
}

app_glofas_transition_future_identifiability <- function(X_reference, X_discrepancy) {
  X_reference <- as.matrix(X_reference)
  X_discrepancy <- as.matrix(X_discrepancy)
  if (nrow(X_reference) != nrow(X_discrepancy)) {
    stop("Reference and discrepancy future designs must have the same row count.", call. = FALSE)
  }
  reference <- app_glofas_transition_matrix_rank(X_reference)
  discrepancy <- app_glofas_transition_matrix_rank(X_discrepancy)
  combined <- app_glofas_transition_matrix_rank(cbind(X_reference, X_discrepancy))
  basis <- function(X, rank) {
    if (!rank) return(matrix(numeric(), nrow = nrow(X), ncol = 0L))
    qr.Q(qr(X))[, seq_len(rank), drop = FALSE]
  }
  Q_reference <- basis(X_reference, reference$rank[[1L]])
  Q_discrepancy <- basis(X_discrepancy, discrepancy$rank[[1L]])
  canonical <- if (!ncol(Q_reference) || !ncol(Q_discrepancy)) {
    numeric()
  } else {
    svd(crossprod(Q_reference, Q_discrepancy), nu = 0L, nv = 0L)$d
  }
  data.frame(
    horizon_rows = nrow(X_reference),
    reference_columns = ncol(X_reference),
    discrepancy_columns = ncol(X_discrepancy),
    reference_rank = reference$rank,
    discrepancy_rank = discrepancy$rank,
    combined_rank = combined$rank,
    reference_full_row_rank = reference$full_row_rank,
    discrepancy_full_row_rank = discrepancy$full_row_rank,
    canonical_min = if (length(canonical)) min(canonical) else NA_real_,
    canonical_max = if (length(canonical)) max(canonical) else NA_real_,
    canonical_near_one = sum(canonical >= 1 - 1e-10),
    future_sum_identifies_components = !(
      isTRUE(reference$full_row_rank[[1L]]) &&
        isTRUE(discrepancy$full_row_rank[[1L]])
    ),
    interpretation = if (
      isTRUE(reference$full_row_rank[[1L]]) &&
        isTRUE(discrepancy$full_row_rank[[1L]])
    ) {
      "future GloFAS likelihood identifies the sum but not its reference/discrepancy allocation"
    } else {
      "future component allocation may be partially constrained by the design spaces"
    },
    stringsAsFactors = FALSE
  )
}

app_glofas_transition_historical_contract <- function(design, tolerance = 1e-10) {
  required <- c(
    "z_fixed", "source_fixed", "base_panel", "discrepancy_baseline_fixed",
    "discrepancy_baseline_future", "discrepancy_transition_strategy"
  )
  missing <- setdiff(required, names(design))
  if (length(missing)) {
    stop(sprintf("Design is missing transition fields: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  panel <- design$base_panel
  app_glofas_transition_require_columns(
    panel,
    c("g_transformed", "y_transformed", "horizon"),
    "design$base_panel"
  )
  g_index <- which(as.character(design$source_fixed) == "G")
  if (length(g_index) != nrow(panel)) {
    stop("Historical GloFAS response rows do not match the base panel.", call. = FALSE)
  }
  baseline <- as.numeric(design$discrepancy_baseline_fixed)
  if (length(baseline) != nrow(panel) || any(!is.finite(baseline))) {
    stop("Historical discrepancy baseline is not finite and row aligned.", call. = FALSE)
  }
  discrepancy <- as.numeric(panel$g_transformed) - as.numeric(panel$y_transformed)
  increment <- discrepancy - baseline
  expected_response <- as.numeric(panel$y_transformed) + increment
  observed_response <- as.numeric(design$z_fixed[g_index])
  response_error <- max(abs(observed_response - expected_response))
  future_baseline <- as.numeric(design$discrepancy_baseline_future)
  data.frame(
    transition_strategy = as.character(design$discrepancy_transition_strategy),
    history_rows = nrow(panel),
    history_horizons = paste(sort(unique(panel$horizon)), collapse = ";"),
    historical_target = "one_step_discrepancy_increment",
    historical_increment_mean = mean(increment),
    historical_increment_sd = stats::sd(increment),
    historical_increment_median = stats::median(increment),
    response_decomposition_max_abs_error = response_error,
    response_identity_passed = response_error <= tolerance,
    future_baseline_unique_values = length(unique(future_baseline)),
    future_baseline_value = if (length(unique(future_baseline)) == 1L) future_baseline[[1L]] else NA_real_,
    future_target = "horizon_specific_total_departure_from_one_origin_anchor",
    target_semantics_match = FALSE,
    stringsAsFactors = FALSE
  )
}

app_glofas_transition_prediction_rows <- function(prediction_quantiles) {
  app_glofas_transition_require_columns(
    prediction_quantiles,
    c(
      "target_date", "horizon", "qhat_summary", "y_reference",
      "raw_glofas_quantile", "discrepancy_hat"
    ),
    "prediction_quantiles"
  )
  out <- prediction_quantiles[
    as.character(prediction_quantiles$qhat_summary) == "posterior_draw_mean",
    ,
    drop = FALSE
  ]
  out <- out[order(as.integer(out$horizon)), , drop = FALSE]
  if (!nrow(out) || !identical(as.integer(out$horizon), seq_len(nrow(out)))) {
    stop("Prediction table must contain one ordered posterior mean per horizon.", call. = FALSE)
  }
  out$target_date <- as.Date(out$target_date)
  out
}

app_glofas_transition_counterfactual <- function(
  prediction_quantiles,
  last_discrepancy,
  phi = c(0, 0.25, 0.5, 0.75, 1)
) {
  prediction <- app_glofas_transition_prediction_rows(prediction_quantiles)
  observed <- as.numeric(prediction$raw_glofas_quantile) - as.numeric(prediction$y_reference)
  fitted <- as.numeric(prediction$discrepancy_hat)
  innovation <- fitted - as.numeric(last_discrepancy)
  paths <- lapply(phi, function(value) {
    estimate <- app_glofas_transition_path(last_discrepancy, innovation, value)
    error <- estimate - observed
    data.frame(
      phi = as.numeric(value),
      transition_label = if (value == 0) {
        "legacy_static_origin"
      } else if (value == 1) {
        "cumulative_innovation"
      } else {
        sprintf("damped_innovation_phi_%0.2f", value)
      },
      target_date = prediction$target_date,
      horizon = as.integer(prediction$horizon),
      last_discrepancy = as.numeric(last_discrepancy),
      fitted_innovation = innovation,
      observed_discrepancy = observed,
      estimated_discrepancy = estimate,
      error = error,
      diagnostic_status = "no_refit_counterfactual_not_model_evidence",
      stringsAsFactors = FALSE
    )
  })
  path_table <- do.call(rbind, paths)
  metrics <- do.call(rbind, lapply(split(path_table, path_table$phi), function(x) {
    data.frame(
      phi = x$phi[[1L]],
      transition_label = x$transition_label[[1L]],
      discrepancy_mae = mean(abs(x$error)),
      discrepancy_rmse = sqrt(mean(x$error^2)),
      discrepancy_bias = mean(x$error),
      p50_check_loss = mean(abs(x$error)) / 2,
      diagnostic_status = x$diagnostic_status[[1L]],
      stringsAsFactors = FALSE
    )
  }))
  rownames(metrics) <- NULL
  list(paths = path_table, metrics = metrics)
}

app_glofas_transition_signal_panel <- function(design, prediction_quantiles) {
  prediction <- app_glofas_transition_prediction_rows(prediction_quantiles)
  ensemble <- design$latent_data$g_ensemble
  app_glofas_transition_require_columns(
    ensemble,
    c("target_date", "horizon", "g_transformed"),
    "design$latent_data$g_ensemble"
  )
  key <- unique(ensemble[, c("target_date", "horizon"), drop = FALSE])
  key <- key[order(as.integer(key$horizon)), , drop = FALSE]
  ensemble_summary <- do.call(rbind, lapply(seq_len(nrow(key)), function(i) {
    index <- as.Date(ensemble$target_date) == as.Date(key$target_date[[i]]) &
      as.integer(ensemble$horizon) == as.integer(key$horizon[[i]])
    value <- as.numeric(ensemble$g_transformed[index])
    value <- value[is.finite(value)]
    data.frame(
      target_date = as.Date(key$target_date[[i]]),
      horizon = as.integer(key$horizon[[i]]),
      glofas_member_mean = mean(value),
      glofas_member_sd = stats::sd(value),
      glofas_member_i80 = unname(stats::quantile(value, 0.9) - stats::quantile(value, 0.1)),
      stringsAsFactors = FALSE
    )
  }))
  timeline <- design$future_context$covariate_timeline
  app_glofas_transition_require_columns(
    timeline,
    c(
      "date", "ppt", "ppt_realized_value", "ppt_gefs_reduced_value",
      "soil", "soil_realized_value", "soil_gefs_reduced_value"
    ),
    "forecast covariate timeline"
  )
  timeline <- timeline[
    as.Date(timeline$date) %in% prediction$target_date,
    c(
      "date", "ppt", "ppt_realized_value", "ppt_gefs_reduced_value",
      "soil", "soil_realized_value", "soil_gefs_reduced_value"
    ),
    drop = FALSE
  ]
  names(timeline)[names(timeline) == "date"] <- "target_date"
  timeline$target_date <- as.Date(timeline$target_date)
  panel <- merge(prediction, ensemble_summary, by = c("target_date", "horizon"), all.x = TRUE)
  panel <- merge(panel, timeline, by = "target_date", all.x = TRUE)
  panel <- panel[order(panel$horizon), , drop = FALSE]
  last_discrepancy <- as.numeric(design$discrepancy_baseline_future[[1L]])
  observed <- as.numeric(panel$raw_glofas_quantile) - as.numeric(panel$y_reference)
  historical_g <- design$latent_data$g_retro
  historical_g <- historical_g[order(as.Date(historical_g$target_date)), , drop = FALSE]
  last_glofas <- utils::tail(as.numeric(historical_g$g_transformed), 1L)
  panel$observed_discrepancy <- observed
  panel$required_departure <- observed - last_discrepancy
  panel$required_increment <- c(observed[[1L]] - last_discrepancy, diff(observed))
  panel$predicted_innovation <- as.numeric(panel$discrepancy_hat) - last_discrepancy
  panel$glofas_change <- c(
    as.numeric(panel$raw_glofas_quantile[[1L]]) - last_glofas,
    diff(as.numeric(panel$raw_glofas_quantile))
  )
  panel$cum_ppt <- cumsum(as.numeric(panel$ppt))
  panel$cum_ppt_realized <- cumsum(as.numeric(panel$ppt_realized_value))
  panel$cum_ppt_gefs <- cumsum(as.numeric(panel$ppt_gefs_reduced_value))
  panel
}

app_glofas_transition_signal_correlations <- function(signal_panel) {
  targets <- c("observed_discrepancy", "required_departure", "required_increment")
  signals <- c(
    "raw_glofas_quantile", "glofas_change", "glofas_member_mean",
    "glofas_member_sd", "glofas_member_i80", "ppt", "ppt_realized_value",
    "ppt_gefs_reduced_value", "cum_ppt", "cum_ppt_realized", "cum_ppt_gefs",
    "soil", "soil_realized_value", "soil_gefs_reduced_value",
    "predicted_innovation"
  )
  app_glofas_transition_require_columns(signal_panel, c(targets, signals), "signal panel")
  out <- do.call(rbind, lapply(targets, function(target) {
    data.frame(
      target = target,
      signal = signals,
      correlation = vapply(signals, function(signal) {
        stats::cor(signal_panel[[target]], signal_panel[[signal]], use = "complete.obs")
      }, numeric(1L)),
      n = vapply(signals, function(signal) {
        sum(stats::complete.cases(signal_panel[, c(target, signal), drop = FALSE]))
      }, integer(1L)),
      interpretation = "descriptive_current_event_only_not_causal",
      stringsAsFactors = FALSE
    )
  }))
  out[order(out$target, -abs(out$correlation)), , drop = FALSE]
}

app_glofas_transition_covariate_provenance <- function(design) {
  timeline <- design$future_context$covariate_timeline
  future <- as.Date(timeline$date) %in% as.Date(design$future_key$target_date)
  do.call(rbind, lapply(c("ppt", "soil"), function(variable) {
    required <- paste0(
      variable,
      c("_role", "_source_policy", "_leakage_status", "_uses_realized_future")
    )
    app_glofas_transition_require_columns(timeline, required, "forecast covariate timeline")
    data.frame(
      variable = variable,
      future_rows = sum(future),
      role = paste(sort(unique(as.character(timeline[[required[[1L]]]][future]))), collapse = ";"),
      source_policy = paste(sort(unique(as.character(timeline[[required[[2L]]]][future]))), collapse = ";"),
      leakage_status = paste(sort(unique(as.character(timeline[[required[[3L]]]][future]))), collapse = ";"),
      uses_realized_future = any(as.logical(timeline[[required[[4L]]]][future])),
      operationally_available = !any(as.logical(timeline[[required[[4L]]]][future])),
      stringsAsFactors = FALSE
    )
  }))
}

app_glofas_transition_draft_registry <- function() {
  data.frame(
    candidate_id = c("l0_legacy", "t1_phi050", "t2_phi075", "t3_phi090", "t4_phi100", "c1_context", "tc1_selected"),
    stage = c("control", rep("transition", 4L), "information", "conditional_combination"),
    phi = c(0, 0.5, 0.75, 0.9, 1, 0, NA_real_),
    transition = c(
      "legacy_static_origin", "damped_innovation", "damped_innovation",
      "damped_innovation", "cumulative_innovation", "legacy_static_origin",
      "selected_after_transition_review"
    ),
    discrepancy_context = c(rep("none", 5L), "glofas_level_anomaly_direct_only", "glofas_level_anomaly_direct_only"),
    geometry = "FR09_D1_mechanism_screen_then_conditional_D16_confirmation",
    depends_on = c("none", rep("approved_transition_contract", 4L), "approved_context_prior", "transition_and_context_signal"),
    launch_authorized = FALSE,
    approval_requirement = "explicit_user_scientific_review_and_frozen_score_gate",
    stringsAsFactors = FALSE
  )
}
