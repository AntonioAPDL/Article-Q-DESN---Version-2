# Phase133B posterior qhat summary sensitivity for Joint exQDESN.

app_joint_exqdesn_phase133b_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase133b_qhat_summary_sensitivity_20260714")
}

app_joint_exqdesn_phase133b_default_phase133_dir <- function() {
  app_path("application/cache/joint_qdesn_phase133_performance_first_audit_20260714")
}

app_joint_exqdesn_phase133b_target_scenarios <- function(phase133_dir, n = 5L) {
  priority_path <- file.path(phase133_dir, "joint_exqdesn_scenario_priority_table.csv")
  priority <- app_read_csv(priority_path)
  app_check_required_columns(priority, c("scenario_id", "performance_priority"), "Phase133 priority table")
  priority <- priority[priority$performance_priority == "high", , drop = FALSE]
  out <- head(priority$scenario_id, n)
  if (!length(out)) stop("Phase133 priority table has no high-priority scenarios for Phase133B.", call. = FALSE)
  out
}

app_joint_exqdesn_qhat_draw_plan <- function(fits, max_draws = 2000L, seed = 133020L) {
  if (!length(fits)) stop("At least one MCMC fit is required.", call. = FALSE)
  n_by_chain <- vapply(fits, function(fit) nrow(fit$beta_draws), integer(1L))
  if (any(n_by_chain <= 0L)) stop("Each fit must contain at least one retained draw.", call. = FALSE)
  total <- sum(n_by_chain)
  max_draws <- as.integer(max_draws)
  if (!is.finite(max_draws) || max_draws <= 0L) stop("max_draws must be a positive integer.", call. = FALSE)
  seed <- as.integer(seed)
  if (!is.finite(seed)) stop("seed must be a finite integer.", call. = FALSE)
  old_seed <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) get(".Random.seed", envir = .GlobalEnv) else NULL
  on.exit({
    if (is.null(old_seed)) {
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
    } else {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(seed)
  rows <- list()
  if (total <= max_draws) {
    for (chain_id in seq_along(fits)) {
      rows[[length(rows) + 1L]] <- data.frame(
        chain_id = chain_id,
        draw_index = seq_len(n_by_chain[[chain_id]]),
        selected = TRUE,
        stringsAsFactors = FALSE
      )
    }
  } else {
    base <- floor(max_draws / length(fits))
    remainder <- max_draws - base * length(fits)
    for (chain_id in seq_along(fits)) {
      n_take <- min(n_by_chain[[chain_id]], base + as.integer(chain_id <= remainder))
      if (n_take <= 0L) next
      draw_index <- sort(sample.int(n_by_chain[[chain_id]], n_take, replace = FALSE))
      rows[[length(rows) + 1L]] <- data.frame(
        chain_id = chain_id,
        draw_index = draw_index,
        selected = TRUE,
        stringsAsFactors = FALSE
      )
    }
  }
  plan <- app_joint_qdesn_bind_rows(rows)
  if (!nrow(plan)) stop("Draw plan selected no retained MCMC draws.", call. = FALSE)
  plan$global_draw_id <- seq_len(nrow(plan))
  plan$n_available_draws_total <- total
  plan$max_draws_requested <- max_draws
  plan$draw_sampling_seed <- seed
  plan
}

app_joint_exqdesn_fit_draw_qhat <- function(fit, Z_eval, tau, draw_index) {
  Z_eval <- as.matrix(Z_eval)
  K <- length(tau)
  p <- ncol(Z_eval)
  beta <- fit$beta_draws[draw_index, , drop = FALSE]
  alpha <- fit$alpha_draws[draw_index, , drop = FALSE]
  out <- array(NA_real_, dim = c(nrow(Z_eval), K, nrow(beta)))
  for (jj in seq_len(nrow(beta))) {
    beta_mat <- app_joint_qvp_beta_matrix(as.numeric(beta[jj, ]), K, p)
    out[, , jj] <- Z_eval %*% beta_mat + matrix(as.numeric(alpha[jj, ]), nrow = nrow(Z_eval), ncol = K, byrow = TRUE)
  }
  out
}

app_joint_exqdesn_qhat_summary_matrix <- function(fits, Z_eval, tau, draw_plan, trim_fraction = 0.10) {
  q_arrays <- lapply(seq_along(fits), function(chain_id) {
    idx <- draw_plan$draw_index[draw_plan$chain_id == chain_id]
    if (!length(idx)) return(NULL)
    app_joint_exqdesn_fit_draw_qhat(fits[[chain_id]], Z_eval, tau, idx)
  })
  q_arrays <- q_arrays[!vapply(q_arrays, is.null, logical(1L))]
  if (!length(q_arrays)) stop("Draw plan selected no qhat draws.", call. = FALSE)
  dims <- dim(q_arrays[[1L]])
  n_draw_total <- sum(vapply(q_arrays, function(x) dim(x)[[3L]], integer(1L)))
  q <- array(NA_real_, dim = c(dims[[1L]], dims[[2L]], n_draw_total))
  pos <- 0L
  for (arr in q_arrays) {
    idx <- seq.int(pos + 1L, pos + dim(arr)[[3L]])
    q[, , idx] <- arr
    pos <- tail(idx, 1L)
  }
  trim_fraction <- as.numeric(trim_fraction)
  if (!is.finite(trim_fraction) || trim_fraction < 0 || trim_fraction >= 0.5) {
    stop("trim_fraction must be in [0, 0.5).", call. = FALSE)
  }
  list(
    mean = apply(q, c(1L, 2L), mean, na.rm = TRUE),
    median = apply(q, c(1L, 2L), stats::median, na.rm = TRUE),
    trimmed_mean = apply(q, c(1L, 2L), mean, trim = trim_fraction, na.rm = TRUE),
    q05 = apply(q, c(1L, 2L), stats::quantile, probs = 0.05, names = FALSE, type = 8, na.rm = TRUE),
    q95 = apply(q, c(1L, 2L), stats::quantile, probs = 0.95, names = FALSE, type = 8, na.rm = TRUE),
    n_draws_used = dim(q)[[3L]],
    finite = all(is.finite(q))
  )
}

app_joint_exqdesn_qhat_uncertainty_rows <- function(meta, fixture_like, summary, summary_family, window_label) {
  rows <- vector("list", length(fixture_like$tau))
  for (kk in seq_along(fixture_like$tau)) {
    rows[[kk]] <- cbind(
      meta,
      fixture_like$row_meta,
      data.frame(
        validation_window = window_label,
        qhat_summary_family = summary_family,
        quantile_index = kk,
        tau = fixture_like$tau[[kk]],
        qhat_q05 = as.numeric(summary$q05[, kk]),
        qhat_q95 = as.numeric(summary$q95[, kk]),
        qhat_iqr90_width = as.numeric(summary$q95[, kk] - summary$q05[, kk]),
        n_draws_used = summary$n_draws_used,
        all_qhat_draws_finite = summary$finite,
        stringsAsFactors = FALSE
      )
    )
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_score_summary_qhat <- function(meta, fixture_like, summary_matrix, method, window_label) {
  raw_meta <- meta
  raw_meta$qhat_summary_method <- method
  raw_meta$validation_window <- window_label
  raw <- summary_matrix
  contract <- app_joint_qdesn_apply_monotone_contract(raw, fixture_like$tau)
  raw_rows <- app_joint_qdesn_quantile_long_rows(raw_meta, fixture_like$row_meta, fixture_like$tau, fixture_like$y, fixture_like$true_q, raw, "qhat_raw")
  contract_rows <- app_joint_qdesn_quantile_long_rows(raw_meta, fixture_like$row_meta, fixture_like$tau, fixture_like$y, fixture_like$true_q, contract$qhat_contract, "qhat")
  scored <- app_joint_qdesn_quantile_scores(contract_rows, "qhat")
  list(
    raw = raw_rows,
    scored = scored,
    adjustment = app_joint_qdesn_adjustment_rows(raw_meta, fixture_like$row_meta, fixture_like$tau, raw, contract$qhat_contract),
    raw_crossing = app_joint_qdesn_crossing_rows(raw_meta, fixture_like$row_meta, fixture_like$tau, raw, paste0("raw_", window_label, "_", method)),
    contract_crossing = app_joint_qdesn_crossing_rows(raw_meta, fixture_like$row_meta, fixture_like$tau, contract$qhat_contract, paste0("contract_", window_label, "_", method))
  )
}

app_joint_exqdesn_score_summary_family <- function(meta, fixture_like, summary, summary_family, window_label) {
  scored <- lapply(c("mean", "median", "trimmed_mean"), function(method) {
    app_joint_exqdesn_score_summary_qhat(meta, fixture_like, summary[[method]], method, window_label)
  })
  list(
    raw = app_joint_qdesn_bind_rows(lapply(scored, `[[`, "raw")),
    scored = app_joint_qdesn_bind_rows(lapply(scored, `[[`, "scored")),
    adjustment = app_joint_qdesn_bind_rows(lapply(scored, `[[`, "adjustment")),
    raw_crossing = app_joint_qdesn_bind_rows(lapply(scored, `[[`, "raw_crossing")),
    contract_crossing = app_joint_qdesn_bind_rows(lapply(scored, `[[`, "contract_crossing")),
    uncertainty = app_joint_exqdesn_qhat_uncertainty_rows(meta, fixture_like, summary, summary_family, window_label)
  )
}

app_joint_exqdesn_phase133b_summary_by_qhat_method <- function(scored, summary_fun, ...) {
  if (!"qhat_summary_method" %in% names(scored)) return(summary_fun(scored, ...))
  rows <- lapply(split(scored, scored$qhat_summary_method), function(block) {
    method <- unique(block$qhat_summary_method)
    out <- summary_fun(block, ...)
    if (!nrow(out)) return(out)
    out$qhat_summary_method <- method[[1L]]
    out
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase133b_forecast_scores <- function(meta, artifacts, scenario_id, fit_fixture, fits, draw_plan, trim_fraction) {
  origin_plan <- artifacts$forecast_origin_plan[artifacts$forecast_origin_plan$scenario_id == scenario_id, , drop = FALSE]
  origin_plan <- origin_plan[order(origin_plan$origin_index), , drop = FALSE]
  rows <- lapply(seq_len(nrow(origin_plan)), function(ii) {
    target <- app_joint_qdesn_forecast_target_fixture(artifacts, scenario_id, origin_plan[ii, , drop = FALSE])
    if (!identical(fit_fixture$feature_cols, target$feature_cols)) {
      stop(sprintf("Feature columns changed between fit and forecast for '%s'.", scenario_id), call. = FALSE)
    }
    summary <- app_joint_exqdesn_qhat_summary_matrix(fits, target$Z, target$tau, draw_plan, trim_fraction)
    app_joint_exqdesn_score_summary_family(meta, target, summary, "mcmc_posterior_qhat", "forecast")
  })
  list(
    raw = app_joint_qdesn_bind_rows(lapply(rows, `[[`, "raw")),
    scored = app_joint_qdesn_bind_rows(lapply(rows, `[[`, "scored")),
    adjustment = app_joint_qdesn_bind_rows(lapply(rows, `[[`, "adjustment")),
    raw_crossing = app_joint_qdesn_bind_rows(lapply(rows, `[[`, "raw_crossing")),
    contract_crossing = app_joint_qdesn_bind_rows(lapply(rows, `[[`, "contract_crossing")),
    uncertainty = app_joint_qdesn_bind_rows(lapply(rows, `[[`, "uncertainty"))
  )
}

app_joint_exqdesn_phase133b_one_case <- function(artifacts, row, mcmc_controls, qhat_controls) {
  scenario_id <- row$scenario_ids[[1L]]
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
  spec <- app_joint_qdesn_phase122_select_spec(row$model_ids[[1L]])
  controls <- app_joint_qdesn_phase122_controls_from_row(row, n_cores = 1L)
  vb_start <- proc.time()[["elapsed"]]
  vb_fit <- app_joint_qdesn_fit_model_adaptive(fixture, spec, controls)
  vb_elapsed <- proc.time()[["elapsed"]] - vb_start
  mcmc_result <- app_joint_qdesn_phase122_run_mcmc_chains(fixture, spec, vb_fit, controls, mcmc_controls, row)
  meta <- app_joint_qdesn_phase122_meta(
    fixture,
    spec,
    row,
    "MCMC",
    app_joint_qdesn_phase122_mcmc_model_id(spec$model_id[[1L]])
  )
  draw_plan <- app_joint_exqdesn_qhat_draw_plan(
    mcmc_result$fits,
    max_draws = qhat_controls$max_draws,
    seed = qhat_controls$draw_seed + sum(utf8ToInt(row$case_id[[1L]])) %% 100000L
  )
  draw_plan <- cbind(meta, draw_plan, stringsAsFactors = FALSE)
  fit_summary <- app_joint_exqdesn_qhat_summary_matrix(
    mcmc_result$fits,
    fixture$Z,
    fixture$tau,
    draw_plan,
    qhat_controls$trim_fraction
  )
  fit_scores <- app_joint_exqdesn_score_summary_family(meta, fixture, fit_summary, "mcmc_posterior_qhat", "fit")
  forecast_scores <- app_joint_exqdesn_phase133b_forecast_scores(
    meta,
    artifacts,
    scenario_id,
    fixture,
    mcmc_result$fits,
    draw_plan,
    qhat_controls$trim_fraction
  )
  runtime <- app_joint_qdesn_bind_rows(list(
    cbind(meta, data.frame(runtime_component = "vb_fit", chain_id = NA_integer_, chain_seed = NA_integer_, elapsed_seconds = vb_elapsed, sec_per_iter = NA_real_, stringsAsFactors = FALSE)),
    cbind(meta, mcmc_result$runtime, stringsAsFactors = FALSE),
    cbind(meta, data.frame(runtime_component = "mcmc_total", chain_id = NA_integer_, chain_seed = NA_integer_, elapsed_seconds = mcmc_result$elapsed_seconds, sec_per_iter = mcmc_result$elapsed_seconds / max(1L, mcmc_controls$mcmc_n_iter * mcmc_controls$n_chains), stringsAsFactors = FALSE))
  ))
  list(
    draw_plan = draw_plan,
    fit_raw = fit_scores$raw,
    fit_scored = fit_scores$scored,
    fit_adjustment = fit_scores$adjustment,
    fit_raw_crossing = fit_scores$raw_crossing,
    fit_contract_crossing = fit_scores$contract_crossing,
    fit_uncertainty = fit_scores$uncertainty,
    forecast_raw = forecast_scores$raw,
    forecast_scored = forecast_scores$scored,
    forecast_adjustment = forecast_scores$adjustment,
    forecast_raw_crossing = forecast_scores$raw_crossing,
    forecast_contract_crossing = forecast_scores$contract_crossing,
    forecast_uncertainty = forecast_scores$uncertainty,
    vb_convergence = app_joint_qdesn_vb_convergence_row(vb_fit, meta, controls),
    objective = app_joint_qdesn_objective_row(vb_fit, meta),
    draw_summary = cbind(meta, mcmc_result$draw_summary, stringsAsFactors = FALSE),
    distance = cbind(meta, mcmc_result$distance, stringsAsFactors = FALSE),
    chain_distance = cbind(meta, mcmc_result$chain_distance, stringsAsFactors = FALSE),
    runtime = runtime
  )
}

app_joint_exqdesn_summary_method_metrics <- function(
  fit_scored,
  forecast_scored,
  fit_raw_crossing,
  forecast_raw_crossing,
  fit_contract_crossing,
  forecast_contract_crossing,
  fit_adjustment,
  forecast_adjustment
) {
  keys <- unique(forecast_scored[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "qhat_summary_method"), drop = FALSE])
  rows <- lapply(seq_len(nrow(keys)), function(ii) {
    key <- keys[ii, , drop = FALSE]
    key_idx_forecast <- forecast_scored$scenario_id == key$scenario_id[[1L]] &
      forecast_scored$model_id == key$model_id[[1L]] &
      forecast_scored$qhat_summary_method == key$qhat_summary_method[[1L]]
    key_idx_fit <- fit_scored$scenario_id == key$scenario_id[[1L]] &
      fit_scored$model_id == key$model_id[[1L]] &
      fit_scored$qhat_summary_method == key$qhat_summary_method[[1L]]
    raw_cross_fit <- fit_raw_crossing$scenario_id == key$scenario_id[[1L]] &
      fit_raw_crossing$model_id == key$model_id[[1L]] &
      fit_raw_crossing$qhat_summary_method == key$qhat_summary_method[[1L]]
    raw_cross_forecast <- forecast_raw_crossing$scenario_id == key$scenario_id[[1L]] &
      forecast_raw_crossing$model_id == key$model_id[[1L]] &
      forecast_raw_crossing$qhat_summary_method == key$qhat_summary_method[[1L]]
    contract_cross_fit <- fit_contract_crossing$scenario_id == key$scenario_id[[1L]] &
      fit_contract_crossing$model_id == key$model_id[[1L]] &
      fit_contract_crossing$qhat_summary_method == key$qhat_summary_method[[1L]]
    contract_cross_forecast <- forecast_contract_crossing$scenario_id == key$scenario_id[[1L]] &
      forecast_contract_crossing$model_id == key$model_id[[1L]] &
      forecast_contract_crossing$qhat_summary_method == key$qhat_summary_method[[1L]]
    adj_fit <- fit_adjustment$scenario_id == key$scenario_id[[1L]] &
      fit_adjustment$model_id == key$model_id[[1L]] &
      fit_adjustment$qhat_summary_method == key$qhat_summary_method[[1L]]
    adj_forecast <- forecast_adjustment$scenario_id == key$scenario_id[[1L]] &
      forecast_adjustment$model_id == key$model_id[[1L]] &
      forecast_adjustment$qhat_summary_method == key$qhat_summary_method[[1L]]
    cbind(key, data.frame(
      fit_truth_mae = mean(fit_scored$truth_abs_error[key_idx_fit], na.rm = TRUE),
      fit_truth_rmse = sqrt(mean(fit_scored$truth_sq_error[key_idx_fit], na.rm = TRUE)),
      fit_check_loss = mean(fit_scored$check_loss[key_idx_fit], na.rm = TRUE),
      forecast_truth_mae = mean(forecast_scored$truth_abs_error[key_idx_forecast], na.rm = TRUE),
      forecast_truth_rmse = sqrt(mean(forecast_scored$truth_sq_error[key_idx_forecast], na.rm = TRUE)),
      forecast_check_loss = mean(forecast_scored$check_loss[key_idx_forecast], na.rm = TRUE),
      fit_raw_crossing_pairs = sum(fit_raw_crossing$n_crossing_pairs[raw_cross_fit], na.rm = TRUE),
      forecast_raw_crossing_pairs = sum(forecast_raw_crossing$n_crossing_pairs[raw_cross_forecast], na.rm = TRUE),
      fit_contract_crossing_pairs = sum(fit_contract_crossing$n_crossing_pairs[contract_cross_fit], na.rm = TRUE),
      forecast_contract_crossing_pairs = sum(forecast_contract_crossing$n_crossing_pairs[contract_cross_forecast], na.rm = TRUE),
      fit_max_abs_adjustment = if (any(adj_fit)) max(fit_adjustment$abs_adjustment[adj_fit], na.rm = TRUE) else 0,
      forecast_max_abs_adjustment = if (any(adj_forecast)) max(forecast_adjustment$abs_adjustment[adj_forecast], na.rm = TRUE) else 0,
      stringsAsFactors = FALSE
    ))
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase133b_recommendations <- function(method_metrics, phase133_dir) {
  priority <- app_read_csv(file.path(phase133_dir, "joint_exqdesn_scenario_priority_table.csv"))
  base <- priority[, c("scenario_id", "mcmc_forecast_truth_mae", "forecast_mae_winner", "forecast_mae_winner_value", "forecast_mae_gap_to_best", "sampler_priority"), drop = FALSE]
  names(base)[names(base) == "mcmc_forecast_truth_mae"] <- "phase125_mean_forecast_mae"
  rows <- lapply(split(method_metrics, method_metrics$scenario_id), function(block) {
    block <- block[order(block$forecast_truth_mae, block$forecast_check_loss), , drop = FALSE]
    best <- block[1L, , drop = FALSE]
    b <- base[base$scenario_id == best$scenario_id[[1L]], , drop = FALSE]
    if (!nrow(b)) b <- data.frame(phase125_mean_forecast_mae = NA_real_, forecast_mae_winner = NA_character_, forecast_mae_winner_value = NA_real_, forecast_mae_gap_to_best = NA_real_, sampler_priority = NA_character_)
    phase125_delta <- best$forecast_truth_mae[[1L]] - b$phase125_mean_forecast_mae[[1L]]
    winner_gap <- best$forecast_truth_mae[[1L]] - b$forecast_mae_winner_value[[1L]]
    action <- if (is.finite(phase125_delta) && phase125_delta <= -0.005 && is.finite(winner_gap) && winner_gap <= 0.010) {
      "promote_robust_qhat_summary_for_confirmation"
    } else if (identical(b$sampler_priority[[1L]], "high")) {
      "pair_exal_spec_screen_with_sampler_geometry"
    } else {
      "run_targeted_exal_specification_screen"
    }
    data.frame(
      scenario_id = best$scenario_id[[1L]],
      best_qhat_summary_method = best$qhat_summary_method[[1L]],
      best_forecast_mae = best$forecast_truth_mae[[1L]],
      best_forecast_rmse = best$forecast_truth_rmse[[1L]],
      best_forecast_check_loss = best$forecast_check_loss[[1L]],
      phase125_mean_forecast_mae = b$phase125_mean_forecast_mae[[1L]],
      best_method_delta_vs_phase125_mean = phase125_delta,
      current_winner = b$forecast_mae_winner[[1L]],
      current_winner_forecast_mae = b$forecast_mae_winner_value[[1L]],
      best_method_gap_to_current_winner = winner_gap,
      raw_crossing_pairs = best$forecast_raw_crossing_pairs[[1L]],
      contract_crossing_pairs = best$forecast_contract_crossing_pairs[[1L]],
      qhat_method_sensitivity_class = if (diff(range(block$forecast_truth_mae, na.rm = TRUE)) >= 0.005) "material" else "small",
      recommended_next_action = action,
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase133b_assessment <- function(worker_failures, source_manifest, method_metrics, recommendations) {
  hard_fail <- nrow(worker_failures) > 0L ||
    any(source_manifest$status != "pass") ||
    !nrow(method_metrics) ||
    any(!is.finite(method_metrics$forecast_truth_mae)) ||
    any(method_metrics$forecast_contract_crossing_pairs > 0L, na.rm = TRUE)
  review <- !hard_fail && any(recommendations$recommended_next_action != "promote_robust_qhat_summary_for_confirmation")
  data.frame(
    audit_gate = if (hard_fail) "fail" else if (review) "review" else "pass",
    implementation_gate = if (hard_fail) "fail" else "pass",
    n_scenarios = length(unique(method_metrics$scenario_id)),
    n_summary_methods = length(unique(method_metrics$qhat_summary_method)),
    n_worker_failures = nrow(worker_failures),
    n_contract_crossing_pairs = sum(method_metrics$forecast_contract_crossing_pairs, na.rm = TRUE),
    n_promote_robust_summary = sum(recommendations$recommended_next_action == "promote_robust_qhat_summary_for_confirmation"),
    n_spec_screen_needed = sum(recommendations$recommended_next_action == "run_targeted_exal_specification_screen"),
    n_sampler_geometry_needed = sum(recommendations$recommended_next_action == "pair_exal_spec_screen_with_sampler_geometry"),
    article_update_recommendation = "do_not_update_article_until_scored_balanced_confirmation_exists",
    next_stage_recommendation = "use_phase133b_recommendations_to_launch_targeted_exal_specification_and_sampler_screens",
    status_reason = if (hard_fail) {
      "Phase133B implementation gate failed."
    } else if (review) {
      "Qhat summary sensitivity completed, but at least one scenario still needs targeted calibration before article promotion."
    } else {
      "All high-priority scenarios are ready for robust qhat summary confirmation."
    },
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_run_phase133b_qhat_sensitivity <- function(
  out_dir = app_joint_exqdesn_phase133b_default_dir(),
  phase133_dir = app_joint_exqdesn_phase133b_default_phase133_dir(),
  phase121_dir = app_joint_qdesn_default_phase121_case_vb_freeze_dir_fallback(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  scenario_ids = NULL,
  model_ids = "joint_exqdesn_rhs_vb",
  n_chains = 2L,
  mcmc_n_iter = 1200L,
  mcmc_burn = 600L,
  mcmc_thin = 10L,
  mcmc_seed_offset = 13320L,
  chain_seed_stride = 100L,
  sigma_upper_multiplier = 50,
  distance_pass = 5,
  chain_pass = 5,
  n_cores = 1L,
  qhat_max_draws = 2000L,
  qhat_draw_seed = 133020L,
  qhat_trim_fraction = 0.10
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  phase133_dir <- normalizePath(phase133_dir, mustWork = TRUE)
  phase121 <- app_joint_qdesn_phase122_load_phase121(phase121_dir)
  artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)
  if (is.null(scenario_ids) || !length(scenario_ids)) {
    scenario_ids <- app_joint_exqdesn_phase133b_target_scenarios(phase133_dir)
  }
  controls <- app_joint_qdesn_phase122_filter_controls(
    phase121$controls,
    scenario_ids = scenario_ids,
    model_ids = model_ids
  )
  mcmc_controls <- app_joint_qdesn_mcmc_readiness_controls(
    n_chains = n_chains,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin,
    mcmc_seed_offset = mcmc_seed_offset,
    chain_seed_stride = chain_seed_stride,
    sigma_upper_multiplier = sigma_upper_multiplier,
    distance_pass = distance_pass,
    chain_pass = chain_pass,
    n_cores = n_cores
  )
  qhat_controls <- list(
    max_draws = as.integer(qhat_max_draws),
    draw_seed = as.integer(qhat_draw_seed),
    trim_fraction = as.numeric(qhat_trim_fraction)
  )
  row_by_case <- split(controls, controls$case_id)
  results <- app_joint_qdesn_parallel_lapply(
    names(row_by_case),
    function(cid) app_joint_exqdesn_phase133b_one_case(artifacts, row_by_case[[cid]], mcmc_controls, qhat_controls),
    mcmc_controls$n_cores
  )
  worker_failures <- app_joint_qdesn_worker_failure_rows(results, "phase133b_qhat_summary_sensitivity")
  successful <- app_joint_qdesn_successful_worker_results(results, "phase133b_qhat_summary_sensitivity")
  if (!length(successful)) {
    stop("Phase133B produced no successful worker results; inspect worker_failures.", call. = FALSE)
  }

  draw_plan <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "draw_plan"))
  fit_raw <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "fit_raw"))
  fit_scored <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "fit_scored"))
  fit_adjustment <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "fit_adjustment"))
  fit_raw_crossing <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "fit_raw_crossing"))
  fit_contract_crossing <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "fit_contract_crossing"))
  fit_uncertainty <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "fit_uncertainty"))
  forecast_raw <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "forecast_raw"))
  forecast_scored <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "forecast_scored"))
  forecast_adjustment <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "forecast_adjustment"))
  forecast_raw_crossing <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "forecast_raw_crossing"))
  forecast_contract_crossing <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "forecast_contract_crossing"))
  forecast_uncertainty <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "forecast_uncertainty"))
  vb_convergence <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "vb_convergence"))
  objective <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "objective"))
  draw_summary <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "draw_summary"))
  distance <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "distance"))
  chain_distance <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "chain_distance"))
  runtime <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "runtime"))

  method_metrics <- app_joint_exqdesn_summary_method_metrics(
    fit_scored,
    forecast_scored,
    fit_raw_crossing,
    forecast_raw_crossing,
    fit_contract_crossing,
    forecast_contract_crossing,
    fit_adjustment,
    forecast_adjustment
  )
  fit_truth_summary <- app_joint_exqdesn_phase133b_summary_by_qhat_method(fit_scored, app_joint_qdesn_truth_summary)
  forecast_truth_summary <- app_joint_exqdesn_phase133b_summary_by_qhat_method(forecast_scored, app_joint_qdesn_truth_summary)
  fit_check_loss_summary <- app_joint_exqdesn_phase133b_summary_by_qhat_method(fit_scored, app_joint_qdesn_check_loss_summary)
  forecast_check_loss_summary <- app_joint_exqdesn_phase133b_summary_by_qhat_method(forecast_scored, app_joint_qdesn_check_loss_summary)
  fit_hit_rate_summary <- app_joint_exqdesn_phase133b_summary_by_qhat_method(fit_scored, app_joint_qdesn_hit_rate_summary)
  forecast_hit_rate_summary <- app_joint_exqdesn_phase133b_summary_by_qhat_method(forecast_scored, app_joint_qdesn_hit_rate_summary)
  fit_crps_summary <- app_joint_exqdesn_phase133b_summary_by_qhat_method(fit_scored, app_joint_qdesn_crps_grid_summary, "qhat")
  forecast_crps_summary <- app_joint_exqdesn_phase133b_summary_by_qhat_method(forecast_scored, app_joint_qdesn_crps_grid_summary, "qhat")
  fit_interval_summary <- app_joint_exqdesn_phase133b_summary_by_qhat_method(fit_scored, app_joint_qdesn_interval_summary, "qhat")
  forecast_interval_summary <- app_joint_exqdesn_phase133b_summary_by_qhat_method(forecast_scored, app_joint_qdesn_interval_summary, "qhat")
  recommendations <- app_joint_exqdesn_phase133b_recommendations(method_metrics, phase133_dir)

  phase133_manifest <- app_joint_qdesn_phase108_manifest_verify(phase133_dir, "phase133_performance_first_audit")
  phase121_manifest <- phase121$manifest_verification
  fixture_manifest <- artifacts$manifest_verification
  source_manifest <- app_joint_qdesn_bind_rows(list(phase133_manifest, phase121_manifest, fixture_manifest))
  assessment <- app_joint_exqdesn_phase133b_assessment(worker_failures, source_manifest, method_metrics, recommendations)

  run_config <- data.frame(
    run_id = "joint_qdesn_phase133b_qhat_summary_sensitivity",
    out_dir = out_dir,
    phase133_dir = phase133_dir,
    phase121_dir = phase121$phase121_dir,
    fixture_dir = artifacts$fixture_dir,
    scenario_ids = paste(scenario_ids, collapse = ","),
    model_ids = paste(model_ids, collapse = ","),
    n_cases = nrow(controls),
    mcmc_n_chains = mcmc_controls$n_chains,
    mcmc_n_iter = mcmc_controls$mcmc_n_iter,
    mcmc_burn = mcmc_controls$mcmc_burn,
    mcmc_thin = mcmc_controls$mcmc_thin,
    mcmc_seed_offset = mcmc_controls$mcmc_seed_offset,
    chain_seed_stride = mcmc_controls$chain_seed_stride,
    sigma_upper_multiplier = mcmc_controls$sigma_upper_multiplier,
    n_cores = mcmc_controls$n_cores,
    qhat_max_draws = qhat_controls$max_draws,
    qhat_draw_seed = qhat_controls$draw_seed,
    qhat_trim_fraction = qhat_controls$trim_fraction,
    qhat_summary_methods = "mean,median,trimmed_mean",
    validation_contract = "posterior_quantile_grid_summary_sensitivity_no_article_mutation",
    scalar_predictive_density_claim = FALSE,
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase133B qhat summary sensitivity",
    "",
    "This artifact compares posterior mean, median, and trimmed-mean qhat summaries for high-priority Joint exQDESN exAL-RHS scenarios.",
    "It is a quantile-grid sensitivity layer and does not update article assets.",
    "",
    sprintf("- Scenarios: `%s`", paste(scenario_ids, collapse = ",")),
    sprintf("- MCMC chains/iterations/burn/thin: `%s/%s/%s/%s`", mcmc_controls$n_chains, mcmc_controls$mcmc_n_iter, mcmc_controls$mcmc_burn, mcmc_controls$mcmc_thin),
    sprintf("- Qhat max draws: `%s`", qhat_controls$max_draws),
    sprintf("- Audit gate: `%s`", assessment$audit_gate[[1L]]),
    "",
    "Scoring uses monotone contract qhat summaries. Raw crossing and adjustment diagnostics are preserved."
  ), readme_path)
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    source_manifest_verification = app_joint_qvp_write_csv(source_manifest, file.path(out_dir, "source_manifest_verification.csv")),
    posterior_qhat_draw_sampling_plan = app_joint_qvp_write_csv(draw_plan, file.path(out_dir, "posterior_qhat_draw_sampling_plan.csv")),
    posterior_qhat_summary_fit_raw = app_joint_qvp_write_csv(fit_raw, file.path(out_dir, "posterior_qhat_summary_fit_raw.csv")),
    posterior_qhat_summary_fit = app_joint_qvp_write_csv(fit_scored, file.path(out_dir, "posterior_qhat_summary_fit.csv")),
    posterior_qhat_summary_fit_adjustment = app_joint_qvp_write_csv(fit_adjustment, file.path(out_dir, "posterior_qhat_summary_fit_adjustment.csv")),
    posterior_qhat_summary_fit_uncertainty = app_joint_qvp_write_csv(fit_uncertainty, file.path(out_dir, "posterior_qhat_summary_fit_uncertainty.csv")),
    posterior_qhat_summary_forecast_raw = app_joint_qvp_write_csv(forecast_raw, file.path(out_dir, "posterior_qhat_summary_forecast_raw.csv")),
    posterior_qhat_summary_forecast = app_joint_qvp_write_csv(forecast_scored, file.path(out_dir, "posterior_qhat_summary_forecast.csv")),
    posterior_qhat_summary_forecast_adjustment = app_joint_qvp_write_csv(forecast_adjustment, file.path(out_dir, "posterior_qhat_summary_forecast_adjustment.csv")),
    posterior_qhat_summary_forecast_uncertainty = app_joint_qvp_write_csv(forecast_uncertainty, file.path(out_dir, "posterior_qhat_summary_forecast_uncertainty.csv")),
    posterior_qhat_summary_fit_crossing = app_joint_qvp_write_csv(fit_contract_crossing, file.path(out_dir, "posterior_qhat_summary_fit_crossing.csv")),
    posterior_qhat_summary_forecast_crossing = app_joint_qvp_write_csv(forecast_contract_crossing, file.path(out_dir, "posterior_qhat_summary_forecast_crossing.csv")),
    posterior_qhat_summary_fit_raw_crossing = app_joint_qvp_write_csv(fit_raw_crossing, file.path(out_dir, "posterior_qhat_summary_fit_raw_crossing.csv")),
    posterior_qhat_summary_forecast_raw_crossing = app_joint_qvp_write_csv(forecast_raw_crossing, file.path(out_dir, "posterior_qhat_summary_forecast_raw_crossing.csv")),
    posterior_qhat_summary_method_metrics = app_joint_qvp_write_csv(method_metrics, file.path(out_dir, "posterior_qhat_summary_method_metrics.csv")),
    fit_truth_distance_summary = app_joint_qvp_write_csv(fit_truth_summary, file.path(out_dir, "fit_truth_distance_summary.csv")),
    forecast_truth_distance_summary = app_joint_qvp_write_csv(forecast_truth_summary, file.path(out_dir, "forecast_truth_distance_summary.csv")),
    fit_check_loss_summary = app_joint_qvp_write_csv(fit_check_loss_summary, file.path(out_dir, "fit_check_loss_summary.csv")),
    forecast_check_loss_summary = app_joint_qvp_write_csv(forecast_check_loss_summary, file.path(out_dir, "forecast_check_loss_summary.csv")),
    fit_hit_rate_summary = app_joint_qvp_write_csv(fit_hit_rate_summary, file.path(out_dir, "fit_hit_rate_summary.csv")),
    forecast_hit_rate_summary = app_joint_qvp_write_csv(forecast_hit_rate_summary, file.path(out_dir, "forecast_hit_rate_summary.csv")),
    fit_crps_grid_summary = app_joint_qvp_write_csv(fit_crps_summary, file.path(out_dir, "fit_crps_grid_summary.csv")),
    forecast_crps_grid_summary = app_joint_qvp_write_csv(forecast_crps_summary, file.path(out_dir, "forecast_crps_grid_summary.csv")),
    fit_interval_summary = app_joint_qvp_write_csv(fit_interval_summary, file.path(out_dir, "fit_interval_summary.csv")),
    forecast_interval_summary = app_joint_qvp_write_csv(forecast_interval_summary, file.path(out_dir, "forecast_interval_summary.csv")),
    qhat_summary_method_recommendation = app_joint_qvp_write_csv(recommendations, file.path(out_dir, "qhat_summary_method_recommendation.csv")),
    vb_convergence_audit = app_joint_qvp_write_csv(vb_convergence, file.path(out_dir, "vb_convergence_audit.csv")),
    objective_diagnostics = app_joint_qvp_write_csv(objective, file.path(out_dir, "objective_diagnostics.csv")),
    mcmc_draw_summary = app_joint_qvp_write_csv(draw_summary, file.path(out_dir, "mcmc_draw_summary.csv")),
    vb_mcmc_distance_summary = app_joint_qvp_write_csv(distance, file.path(out_dir, "vb_mcmc_distance_summary.csv")),
    chain_to_pooled_distance_summary = app_joint_qvp_write_csv(chain_distance, file.path(out_dir, "chain_to_pooled_distance_summary.csv")),
    runtime_summary = app_joint_qvp_write_csv(runtime, file.path(out_dir, "runtime_summary.csv")),
    audit_assessment = app_joint_qvp_write_csv(assessment, file.path(out_dir, "audit_assessment.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    paths = c(paths, artifact_manifest = manifest_info$manifest_path),
    manifest = manifest_info$manifest,
    run_config = run_config,
    method_metrics = method_metrics,
    recommendations = recommendations,
    assessment = assessment,
    worker_failures = worker_failures
  )
}
