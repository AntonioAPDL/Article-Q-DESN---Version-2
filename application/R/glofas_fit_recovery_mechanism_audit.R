# Mechanism diagnostics for completed GloFAS fit-recovery runs.

app_glofas_mechanism_safe_sd <- function(x, tolerance = 1e-10) {
  value <- stats::sd(as.numeric(x), na.rm = TRUE)
  if (!is.finite(value) || value < tolerance) 1 else value
}

app_glofas_mechanism_draw_indices <- function(n_draws, n_subset = 5L) {
  n_draws <- as.integer(n_draws)
  n_subset <- as.integer(n_subset)
  if (!is.finite(n_draws) || n_draws < 1L || !is.finite(n_subset) || n_subset < 1L) {
    return(integer())
  }
  unique(as.integer(round(seq(1L, n_draws, length.out = min(n_draws, n_subset)))))
}

app_glofas_mechanism_linearized_design <- function(linearization, y_future, block = c("beta", "alpha")) {
  block <- match.arg(block)
  X <- as.matrix(if (identical(block, "beta")) {
    linearization$X_beta_future %||% linearization$X_future
  } else {
    linearization$X_alpha_future %||% linearization$X_future
  })
  J <- if (identical(block, "beta")) {
    linearization$J_beta %||% linearization$J_x
  } else {
    linearization$J_alpha %||% linearization$J_x
  }
  delta <- as.numeric(y_future) - as.numeric(linearization$y_mean)
  if (length(J) != nrow(X)) stop("Future Jacobian rows do not match the future design.", call. = FALSE)
  for (h in seq_len(nrow(X))) {
    X[h, ] <- X[h, ] + as.numeric(as.matrix(J[[h]]) %*% delta)
  }
  X
}

app_glofas_mechanism_exact_future_design <- function(design, y_future) {
  context <- design$future_context
  y_future <- as.numeric(y_future)
  if (length(y_future) != nrow(context$latent_data$future_key)) {
    stop("Latent future path length does not match future_key.", call. = FALSE)
  }
  qfit_beta <- context$qfit_beta %||% context$qfit
  qfit_alpha <- context$qfit_alpha %||% context$qfit
  feature_meta_beta <- context$feature_meta_beta %||% context$feature_meta
  feature_meta_alpha <- context$feature_meta_alpha %||% context$feature_meta
  continuation_beta <- app_qdesn_continue_latent_path(
    qfit = qfit_beta,
    y_history = context$y_history_full,
    y_future = y_future,
    future_dates = context$latent_data$future_key$target_date,
    covariate_timeline = context$covariate_timeline,
    return_jacobian = FALSE
  )
  panel_beta <- app_latent_path_combined_panel(
    base_panel = context$base_panel_full,
    latent_data = context$latent_data,
    y_future = y_future
  )
  readout_beta <- app_build_readout_feature_matrix(
    reservoir_X = continuation_beta$X_future_core,
    panel = panel_beta,
    cfg = context$cfg,
    output_anchor_dates = context$latent_data$future_key$target_date,
    covariate_target_dates = context$latent_data$future_key$target_date,
    horizon = context$latent_data$future_key$horizon,
    feature_strategy = context$feature_strategy,
    horizon_scale = context$horizon_scale,
    feature_meta = feature_meta_beta,
    fit_scale = FALSE
  )
  if (!isTRUE(context$two_block_design %||% FALSE)) {
    return(list(
      X_beta_future = readout_beta$X,
      X_alpha_future = readout_beta$X,
      continuation_beta = continuation_beta,
      continuation_alpha = continuation_beta,
      discrepancy_future = NULL,
      discrepancy_baseline_future = rep(0, length(y_future))
    ))
  }
  q_g <- as.numeric(context$glofas_future_quantile_path)
  if (length(q_g) != length(y_future) || any(!is.finite(q_g))) {
    stop("The two-block exact rebuild requires a finite GloFAS quantile path.", call. = FALSE)
  }
  transition_strategy <- context$discrepancy_transition_strategy %||% "recursive_level"
  if (identical(transition_strategy, "persistence_anchored_innovation")) {
    discrepancy_baseline_future <- rep(
      utils::tail(as.numeric(context$d_history_full), 1L),
      length(y_future)
    )
    discrepancy_future <- discrepancy_baseline_future
  } else {
    discrepancy_baseline_future <- rep(0, length(y_future))
    discrepancy_future <- q_g - y_future
  }
  continuation_alpha <- app_qdesn_continue_latent_path(
    qfit = qfit_alpha,
    y_history = context$d_history_full,
    y_future = discrepancy_future,
    future_dates = context$latent_data$future_key$target_date,
    covariate_timeline = context$covariate_timeline,
    return_jacobian = FALSE
  )
  panel_alpha <- app_latent_path_combined_panel(
    base_panel = context$base_panel_disc_full,
    latent_data = context$latent_data,
    y_future = discrepancy_future
  )
  readout_alpha <- app_build_readout_feature_matrix(
    reservoir_X = continuation_alpha$X_future_core,
    panel = panel_alpha,
    cfg = context$cfg,
    output_anchor_dates = context$latent_data$future_key$target_date,
    covariate_target_dates = context$latent_data$future_key$target_date,
    horizon = context$latent_data$future_key$horizon,
    feature_strategy = context$feature_strategy,
    horizon_scale = context$horizon_scale,
    feature_meta = feature_meta_alpha,
    fit_scale = FALSE
  )
  list(
    X_beta_future = readout_beta$X,
    X_alpha_future = readout_alpha$X,
    continuation_beta = continuation_beta,
    continuation_alpha = continuation_alpha,
    discrepancy_future = discrepancy_future,
    discrepancy_baseline_future = discrepancy_baseline_future,
    discrepancy_transition_strategy = transition_strategy
  )
}

app_glofas_mechanism_feature_group <- function(feature_info) {
  group <- as.character(feature_info$block)
  covariate <- group == "direct_covariate_lag" & !is.na(feature_info$variable)
  group[covariate] <- paste(group[covariate], feature_info$variable[covariate], sep = ":")
  group
}

app_glofas_mechanism_contributions <- function(X, coefficients, feature_info, component, path_name, horizon) {
  X <- as.matrix(X)
  coefficients <- as.numeric(coefficients)
  if (ncol(X) != length(coefficients) || nrow(feature_info) != ncol(X)) {
    stop("Feature contributions require aligned design, coefficient, and metadata dimensions.", call. = FALSE)
  }
  groups <- app_glofas_mechanism_feature_group(feature_info)
  rows <- lapply(split(seq_len(ncol(X)), groups), function(index) {
    data.frame(
      component = component,
      path_name = path_name,
      horizon = as.integer(horizon),
      feature_group = groups[index[[1L]]],
      contribution = as.numeric(X[, index, drop = FALSE] %*% coefficients[index]),
      stringsAsFactors = FALSE
    )
  })
  out <- app_bind_rows_fill(rows)
  out[order(out$horizon, out$feature_group), , drop = FALSE]
}

app_glofas_mechanism_shift <- function(X_history, X_future, feature_info, block, path_name, horizon) {
  X_history <- as.matrix(X_history)
  X_future <- as.matrix(X_future)
  if (ncol(X_history) != ncol(X_future) || nrow(feature_info) != ncol(X_history)) {
    stop("Feature-shift diagnostics require aligned matrices and feature metadata.", call. = FALSE)
  }
  groups <- app_glofas_mechanism_feature_group(feature_info)
  rows <- lapply(split(seq_len(ncol(X_history)), groups), function(index) {
    history <- X_history[, index, drop = FALSE]
    future <- X_future[, index, drop = FALSE]
    center <- colMeans(history, na.rm = TRUE)
    scale <- apply(history, 2L, app_glofas_mechanism_safe_sd)
    lower <- apply(history, 2L, min, na.rm = TRUE)
    upper <- apply(history, 2L, max, na.rm = TRUE)
    z <- sweep(sweep(future, 2L, center, "-"), 2L, scale, "/")
    outside <- sweep(future, 2L, lower, "<") | sweep(future, 2L, upper, ">")
    data.frame(
      block = block,
      path_name = path_name,
      horizon = as.integer(horizon),
      feature_group = groups[index[[1L]]],
      n_features = length(index),
      max_abs_z = apply(abs(z), 1L, max, na.rm = TRUE),
      mean_abs_z = rowMeans(abs(z), na.rm = TRUE),
      fraction_abs_z_gt_3 = rowMeans(abs(z) > 3, na.rm = TRUE),
      fraction_abs_z_gt_5 = rowMeans(abs(z) > 5, na.rm = TRUE),
      fraction_outside_history_range = rowMeans(outside, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_glofas_mechanism_state_shift <- function(X_history, X_future, block, path_name, horizon) {
  X_history <- as.matrix(X_history)
  X_future <- as.matrix(X_future)
  center <- colMeans(X_history, na.rm = TRUE)
  scale <- apply(X_history, 2L, app_glofas_mechanism_safe_sd)
  lower <- apply(X_history, 2L, min, na.rm = TRUE)
  upper <- apply(X_history, 2L, max, na.rm = TRUE)
  z <- sweep(sweep(X_future, 2L, center, "-"), 2L, scale, "/")
  outside <- sweep(X_future, 2L, lower, "<") | sweep(X_future, 2L, upper, ">")
  data.frame(
    block = block,
    path_name = path_name,
    horizon = as.integer(horizon),
    max_abs_z = apply(abs(z), 1L, max, na.rm = TRUE),
    mean_abs_z = rowMeans(abs(z), na.rm = TRUE),
    fraction_abs_z_gt_3 = rowMeans(abs(z) > 3, na.rm = TRUE),
    fraction_abs_z_gt_5 = rowMeans(abs(z) > 5, na.rm = TRUE),
    fraction_outside_history_range = rowMeans(outside, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}

app_glofas_mechanism_jacobian <- function(linearization, block = c("beta", "alpha"), horizon) {
  block <- match.arg(block)
  matrices <- if (identical(block, "beta")) {
    linearization$J_beta %||% linearization$J_x
  } else {
    linearization$J_alpha %||% linearization$J_x
  }
  rows <- lapply(seq_along(matrices), function(i) {
    J <- as.matrix(matrices[[i]])
    singular_values <- base::svd(J, nu = 0L, nv = 0L)$d
    data.frame(
      block = block,
      horizon = as.integer(horizon[[i]]),
      max_abs_jacobian = max(abs(J), na.rm = TRUE),
      frobenius_norm = sqrt(sum(J^2, na.rm = TRUE)),
      operator_norm = if (length(singular_values)) max(singular_values) else 0,
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_glofas_mechanism_score_paths <- function(y, raw, q_g, q_y, last_discrepancy, tau = 0.5) {
  paths <- list(
    raw_glofas = as.numeric(raw),
    reference_only = as.numeric(q_g),
    discrepancy_persistence = as.numeric(q_g) - as.numeric(last_discrepancy),
    learned_discrepancy = as.numeric(q_y)
  )
  rows <- lapply(names(paths), function(name) {
    prediction <- paths[[name]]
    data.frame(
      path = name,
      check_loss_mean = app_glofas_fit_recovery_check_loss(y, prediction, tau),
      log1p_mae = mean(abs(prediction - y)),
      log1p_rmse = sqrt(mean((prediction - y)^2)),
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_glofas_mechanism_decision <- function(
  exact_draw_summary,
  state_shift,
  feature_shift,
  counterfactual_scores,
  exact_difference_tolerance = 0.05,
  shift_tolerance = 5
) {
  max_exact_difference <- if (nrow(exact_draw_summary)) {
    max(exact_draw_summary$max_abs_q_y_diff, exact_draw_summary$max_abs_d_g_diff, na.rm = TRUE)
  } else NA_real_
  alpha_state <- state_shift[state_shift$block == "alpha_reservoir", , drop = FALSE]
  alpha_feature <- feature_shift[feature_shift$block == "alpha_readout", , drop = FALSE]
  max_alpha_state_shift <- if (nrow(alpha_state)) max(alpha_state$max_abs_z, na.rm = TRUE) else NA_real_
  max_alpha_feature_shift <- if (nrow(alpha_feature)) max(alpha_feature$max_abs_z, na.rm = TRUE) else NA_real_
  learned <- counterfactual_scores$check_loss_mean[counterfactual_scores$path == "learned_discrepancy"]
  persistence <- counterfactual_scores$check_loss_mean[counterfactual_scores$path == "discrepancy_persistence"]
  loss_ratio <- if (length(learned) && length(persistence)) {
    max(learned / persistence, na.rm = TRUE)
  } else NA_real_
  mechanism <- if (is.finite(max_exact_difference) && max_exact_difference > exact_difference_tolerance) {
    "prediction_linearization"
  } else if ((is.finite(max_alpha_state_shift) && max_alpha_state_shift > shift_tolerance) ||
             (is.finite(max_alpha_feature_shift) && max_alpha_feature_shift > shift_tolerance)) {
    "discrepancy_state_or_readout_extrapolation"
  } else if (is.finite(loss_ratio) && loss_ratio > 1) {
    "discrepancy_transition_misspecification"
  } else {
    "no_single_mechanism_isolated"
  }
  data.frame(
    max_exact_vs_linearized_component_difference = max_exact_difference,
    max_alpha_reservoir_shift_z = max_alpha_state_shift,
    max_alpha_readout_shift_z = max_alpha_feature_shift,
    learned_to_persistence_loss_ratio = loss_ratio,
    primary_mechanism = mechanism,
    authorize_broad_grid = FALSE,
    authorize_full7 = FALSE,
    stringsAsFactors = FALSE
  )
}
