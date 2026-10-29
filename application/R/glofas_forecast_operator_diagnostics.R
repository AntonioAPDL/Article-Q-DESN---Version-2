# Counterfactual forecast-operator diagnostics. Teacher forcing is diagnostic only.

app_glofas_operator_apply_endogenous_policy <- function(
  compiled_inputs,
  policy = c("stochastic_recursive", "conditional_mean_recursive", "frozen_last", "teacher_forced"),
  y_history,
  future_truth = NULL
) {
  policy <- match.arg(policy)
  static_values <- as.matrix(compiled_inputs$static_values)
  future_index <- matrix(
    as.integer(compiled_inputs$future_index),
    nrow = nrow(static_values), ncol = ncol(static_values)
  )
  y_history <- as.numeric(y_history)
  if (!length(y_history) || !is.finite(tail(y_history, 1L))) {
    stop("Forecast-operator diagnostics require a finite response history.", call. = FALSE)
  }
  positions <- which(future_index > 0L, arr.ind = TRUE)
  if (identical(policy, "frozen_last") && nrow(positions)) {
    static_values[positions] <- tail(y_history, 1L)
    future_index[positions] <- 0L
  }
  if (identical(policy, "teacher_forced")) {
    future_truth <- as.numeric(future_truth)
    if (length(future_truth) != nrow(static_values) || any(!is.finite(future_truth))) {
      stop("Teacher-forced diagnostics require finite truth for every forecast horizon.", call. = FALSE)
    }
    if (nrow(positions)) {
      indices <- future_index[positions]
      if (any(indices < 1L | indices > length(future_truth))) {
        stop("Teacher-forced future lag index is outside the supplied truth path.", call. = FALSE)
      }
      static_values[positions] <- future_truth[indices]
      future_index[positions] <- 0L
    }
  }
  list(
    static_values = static_values,
    future_index = future_index,
    policy = policy,
    deployable = !identical(policy, "teacher_forced"),
    truth_used_in_inputs = identical(policy, "teacher_forced"),
    innovation_policy = if (identical(policy, "conditional_mean_recursive")) "zero" else "shared_stochastic_draws"
  )
}

app_glofas_normal_operator_diagnostic <- function(
  fitted,
  future_dates,
  future_truth,
  covariate_timeline = NULL,
  n_draws = 500L,
  seed = 20260920L
) {
  future_dates <- as.Date(future_dates)
  future_truth <- as.numeric(future_truth)
  n_draws <- as.integer(n_draws)
  if (length(future_dates) != length(future_truth) || any(!is.finite(future_truth))) {
    stop("Operator diagnostics require aligned, finite future dates and truth.", call. = FALSE)
  }
  if (!app_glofas_oracle_d1_cpp_supported(fitted) || !app_glofas_oracle_load_cpp(required = TRUE)) {
    stop("Operator diagnostics currently require the exact D=1 C++ forecast backend.", call. = FALSE)
  }
  design <- fitted$design
  fit <- fitted$fit
  method <- match.arg(fitted$method %||% "rhs", c("rhs", "ridge"))
  qfit <- list(reservoir = design$reservoir, states = design$states, meta = design$design_meta)
  compiled <- app_glofas_oracle_compiled_future_inputs(
    qfit, future_dates = future_dates,
    covariate_timeline = covariate_timeline %||% qfit$meta$covariate_timeline %||% NULL
  )
  payload <- app_glofas_oracle_with_seed(seed, {
    draws <- app_glofas_oracle_parameter_draws(fit, method = method, n_draws = n_draws, seed = NULL)
    list(draws = draws, z = matrix(stats::rnorm(length(future_dates) * n_draws), nrow = length(future_dates)))
  })
  beta_raw <- app_glofas_normal_readout_beta_draws_to_raw(
    payload$draws$beta, design$readout_scaler %||% NULL
  )
  states0 <- app_qdesn_last_states(qfit)[[1L]]
  policies <- c("stochastic_recursive", "conditional_mean_recursive", "frozen_last", "teacher_forced")
  results <- lapply(policies, function(policy) {
    contract <- app_glofas_operator_apply_endogenous_policy(
      compiled, policy, qfit$meta$y_history, future_truth
    )
    z <- if (identical(policy, "conditional_mean_recursive")) {
      matrix(0, nrow = length(future_dates), ncol = n_draws)
    } else payload$z
    cpp <- glofas_oracle_d1_draw_recursive_cpp(
      W = as.matrix(design$reservoir$W[[1L]]),
      Win = as.matrix(design$reservoir$Win[[1L]]),
      state0 = as.numeric(states0),
      static_values = contract$static_values,
      future_index = contract$future_index,
      lag_center = as.numeric(qfit$meta$lag_center),
      lag_scale = as.numeric(qfit$meta$lag_scale),
      standardize_inputs = isTRUE(qfit$meta$standardize_inputs %||% FALSE),
      input_bound = as.character(qfit$meta$input_bound %||% "none"),
      win_scale_global = as.numeric(qfit$meta$win_scale_global %||% 1),
      win_scale_bias = as.numeric(qfit$meta$win_scale_bias %||% 1),
      alpha = as.numeric(design$reservoir$alpha[[1L]]),
      beta_draws = beta_raw,
      sigma_draws = as.numeric(payload$draws$sigma),
      z_obs = z,
      act_f = as.character(design$reservoir$act_f %||% "tanh")
    )
    draws <- as.matrix(cpp$forecast_draws)
    mu <- as.matrix(cpp$conditional_mean_draws)
    input_mean <- as.matrix(cpp$input_mean)
    pred_mean <- rowMeans(draws)
    data.frame(
      policy = policy,
      deployable = contract$deployable,
      truth_used_in_inputs = contract$truth_used_in_inputs,
      target_date = future_dates,
      horizon = seq_along(future_dates),
      observed = future_truth,
      pred_mean = pred_mean,
      pred_median = apply(draws, 1L, stats::median),
      pred_q025 = apply(draws, 1L, stats::quantile, probs = 0.025, names = FALSE, type = 8),
      pred_q975 = apply(draws, 1L, stats::quantile, probs = 0.975, names = FALSE, type = 8),
      conditional_mean = rowMeans(mu),
      error = pred_mean - future_truth,
      absolute_error = abs(pred_mean - future_truth),
      covered_95 = future_truth >= apply(draws, 1L, stats::quantile, probs = 0.025, names = FALSE, type = 8) &
        future_truth <= apply(draws, 1L, stats::quantile, probs = 0.975, names = FALSE, type = 8),
      path_sd = apply(draws, 1L, stats::sd),
      state_norm_mean = as.numeric(cpp$state_norm_mean),
      state_saturation_fraction = as.numeric(cpp$state_saturation_mean),
      input_mean_min = apply(input_mean, 1L, min),
      input_mean_max = apply(input_mean, 1L, max),
      readout_reservoir_contribution = rowMeans(mu) - mean(beta_raw[, 1L]),
      stringsAsFactors = FALSE
    )
  })
  by_horizon <- app_bind_rows_fill(results)
  summary <- app_bind_rows_fill(lapply(split(by_horizon, by_horizon$policy), function(x) data.frame(
    policy = x$policy[[1L]], deployable = x$deployable[[1L]],
    truth_used_in_inputs = x$truth_used_in_inputs[[1L]],
    mae = mean(x$absolute_error), rmse = sqrt(mean(x$error^2)), bias = mean(x$error),
    coverage_95 = mean(x$covered_95), mean_path_sd = mean(x$path_sd),
    max_state_saturation = max(x$state_saturation_fraction),
    peak_observed_horizon = x$horizon[[which.max(x$observed)]],
    peak_predicted_horizon = x$horizon[[which.max(x$pred_mean)]],
    stringsAsFactors = FALSE
  )))
  list(
    schema_version = "glofas_forecast_operator_diagnostic_v1",
    method = method, seed = as.integer(seed), n_draws = n_draws,
    future_dates = future_dates, by_horizon = by_horizon, summary = summary,
    teacher_forced_role = "diagnostic_non_deployable_not_for_model_selection",
    parameter_draw_contract = "same_aligned_parameter_draws_across_policies",
    innovation_draw_contract = "same_aligned_innovations_except_zero_for_conditional_mean"
  )
}
