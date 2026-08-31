# Controlled discrepancy-prior relaxation for the shared-input GloFAS p50 fit.

app_glofas_discrepancy_tau0_values <- function() c(0.3, 1, 3, 10)

app_glofas_discrepancy_tau0_authoritative_baseline <- function() {
  list(
    candidate_id = "fr09_authoritative_p50",
    forecast_p50_check_loss_mean = 0.798826956115941,
    observed_log1p_mae_all = 0.0624424466662982,
    observed_log1p_mae_last1000 = 0.0388437273850094,
    observed_log1p_mae_last200 = 0.05360828353558,
    observed_log1p_mae_last50 = 0.178787719773148
  )
}

app_glofas_discrepancy_tau0_guardrails <- function(max_history_regression = 0.03) {
  max_history_regression <- as.numeric(max_history_regression)
  if (!is.finite(max_history_regression) || max_history_regression < 0) {
    stop("max_history_regression must be finite and nonnegative.", call. = FALSE)
  }
  baseline <- app_glofas_discrepancy_tau0_authoritative_baseline()
  fields <- c("all", "last1000", "last200", "last50")
  values <- vapply(fields, function(window) {
    as.numeric(baseline[[paste0("observed_log1p_mae_", window)]]) * (1 + max_history_regression)
  }, numeric(1L))
  data.frame(
    window = fields,
    authoritative_log1p_mae = vapply(fields, function(window) {
      as.numeric(baseline[[paste0("observed_log1p_mae_", window)]])
    }, numeric(1L)),
    maximum_allowed_log1p_mae = unname(values),
    maximum_regression_fraction = max_history_regression,
    stringsAsFactors = FALSE
  )
}

app_glofas_discrepancy_tau0_label <- function(value) {
  value <- as.numeric(value)
  if (length(value) != 1L || !is.finite(value) || value <= 0) {
    stop("Discrepancy tau0 must be one positive finite number.", call. = FALSE)
  }
  text <- format(value, scientific = FALSE, trim = TRUE, digits = 15)
  text <- sub("[.]0+$", "", text)
  text <- sub("([.][0-9]*?)0+$", "\\1", text)
  gsub("[.]", "p", text)
}

app_glofas_discrepancy_tau0_candidate_id <- function(value, warm = TRUE) {
  paste0(
    "fr09_shared_reference_input_disctau",
    app_glofas_discrepancy_tau0_label(value),
    if (isTRUE(warm)) "_warm_p50" else "_cold_canary_p50"
  )
}

app_glofas_discrepancy_tau0_apply_config <- function(
  source_cfg,
  candidate_id,
  model_grid_path,
  output_root,
  discrepancy_tau0,
  max_iter = 400L,
  warm_start_fit = NULL,
  warm_start_contract = NULL
) {
  if (!is.list(source_cfg)) stop("source_cfg must be a parsed configuration.", call. = FALSE)
  discrepancy_tau0 <- as.numeric(discrepancy_tau0)
  max_iter <- as.integer(max_iter)
  if (!is.finite(discrepancy_tau0) || discrepancy_tau0 <= 0) {
    stop("discrepancy_tau0 must be positive and finite.", call. = FALSE)
  }
  if (!is.finite(max_iter) || max_iter < 51L) {
    stop("max_iter must exceed the frozen 50-iteration RHS warmup.", call. = FALSE)
  }
  warm <- !is.null(warm_start_fit) && nzchar(as.character(warm_start_fit[[1L]]))
  cfg <- source_cfg
  cfg$application_name <- paste0("glofas_", candidate_id)
  cfg$description <- paste(
    "Exact-design p50 discrepancy RHS relaxation; shared tau0 remains 0.1 and discrepancy tau0 is",
    format(discrepancy_tau0, scientific = TRUE),
    if (warm) "with strict warm initialization." else "with a cold initialization canary."
  )
  cfg$paths$model_grid <- normalizePath(model_grid_path, mustWork = FALSE)
  cfg$paths$cache <- file.path(output_root, "common_cache")
  cfg$paths$runs <- file.path(output_root, "runs")
  cfg$paths$logs <- file.path(output_root, "logs")
  cfg$paths$generated_outputs <- file.path(output_root, "generated")

  source_reference_tau0 <- as.numeric(source_cfg$inference$vb_ld$rhs_tau0 %||% NA_real_)
  if (!isTRUE(all.equal(source_reference_tau0, 0.1, tolerance = 1.0e-15))) {
    stop("The frozen source reference tau0 is not 0.1.", call. = FALSE)
  }
  cfg$inference$vb_ld$rhs_tau0 <- source_reference_tau0
  cfg$inference$vb_ld$rhs_alpha_tau0 <- discrepancy_tau0
  cfg$inference$vb_ld$max_iter <- max_iter
  cfg$inference$vb_ld$max_iter_hard_cap <- max_iter
  cfg$inference$mcmc$rhs_tau0 <- source_reference_tau0
  cfg$inference$mcmc$rhs_alpha_tau0 <- discrepancy_tau0
  cfg$inference$vb_ld$warm_start <- if (warm) {
    list(
      enabled = TRUE,
      fit_object = normalizePath(warm_start_fit, mustWork = TRUE),
      source_contract = warm_start_contract,
      use_theta = TRUE,
      use_future = TRUE,
      use_sigma = TRUE,
      require_theta = TRUE,
      require_future = TRUE,
      require_sigma = FALSE,
      covariance_jitter = 1.0e-8,
      require_contract = TRUE,
      compatibility_mode = "exact_design"
    )
  } else {
    list(enabled = FALSE, reason = "Prospective cold canary for the exact-design warm-start comparison")
  }
  cfg$inference$vb_ld$checkpoint <- list(
    enabled = TRUE,
    resume = TRUE,
    path = "{fit_id}__vb_checkpoint.rds",
    every_iterations = 25L,
    every_minutes = 20,
    keep_previous = TRUE,
    keep_on_success = FALSE,
    compress = FALSE
  )
  cfg$execution$final_launch <- list(
    enabled = TRUE,
    note = "Approved p50-only discrepancy tau0 relaxation; no automatic promotion or full7 launch"
  )
  cfg$execution$artifacts <- list(
    retain_fit_object = TRUE,
    retain_design_object = TRUE,
    retain_prediction_design_object = TRUE,
    retain_reference_fit_object = TRUE
  )
  cfg$post_analysis$enabled <- TRUE
  cfg$post_analysis$run_after_outputs <- TRUE
  cfg$post_analysis$recent_history_n <- 200L
  cfg$post_analysis$storage$write_history_draws_rds <- FALSE
  cfg$post_analysis$storage$write_history_draws_csv <- FALSE
  cfg
}

app_glofas_discrepancy_tau0_scrub_config <- function(candidate, source) {
  out <- candidate
  out$.__config_path__ <- source$.__config_path__
  out$application_name <- source$application_name
  out$description <- source$description
  for (name in c("model_grid", "cache", "runs", "logs", "generated_outputs")) {
    out$paths[[name]] <- source$paths[[name]]
  }
  for (name in c("rhs_alpha_tau0", "max_iter", "max_iter_hard_cap", "warm_start", "checkpoint")) {
    out$inference$vb_ld[[name]] <- source$inference$vb_ld[[name]]
  }
  out$inference$mcmc$rhs_alpha_tau0 <- source$inference$mcmc$rhs_alpha_tau0
  out$execution$final_launch <- source$execution$final_launch
  out$execution$artifacts <- source$execution$artifacts
  out$post_analysis$enabled <- source$post_analysis$enabled
  out$post_analysis$run_after_outputs <- source$post_analysis$run_after_outputs
  out$post_analysis$recent_history_n <- source$post_analysis$recent_history_n
  out$post_analysis$storage <- source$post_analysis$storage
  out
}

app_glofas_discrepancy_tau0_assert_one_axis <- function(
  source_cfg,
  candidate_cfg,
  expected_tau0,
  expected_max_iter = 400L,
  warm = TRUE
) {
  if (!identical(
    app_glofas_discrepancy_tau0_scrub_config(candidate_cfg, source_cfg),
    source_cfg
  )) {
    stop("Candidate configuration differs from the source outside the declared runtime/tau0 fields.", call. = FALSE)
  }
  checks <- c(
    reference_tau0 = isTRUE(all.equal(
      as.numeric(candidate_cfg$inference$vb_ld$rhs_tau0),
      as.numeric(source_cfg$inference$vb_ld$rhs_tau0), tolerance = 1.0e-15
    )),
    discrepancy_tau0 = isTRUE(all.equal(
      as.numeric(candidate_cfg$inference$vb_ld$rhs_alpha_tau0),
      as.numeric(expected_tau0), tolerance = 1.0e-15
    )),
    max_iter = identical(as.integer(candidate_cfg$inference$vb_ld$max_iter), as.integer(expected_max_iter)),
    hard_cap = identical(as.integer(candidate_cfg$inference$vb_ld$max_iter_hard_cap), as.integer(expected_max_iter)),
    warm_start = identical(app_as_bool(candidate_cfg$inference$vb_ld$warm_start$enabled), isTRUE(warm)),
    checkpoint = app_as_bool(candidate_cfg$inference$vb_ld$checkpoint$enabled),
    checkpoint_resume = app_as_bool(candidate_cfg$inference$vb_ld$checkpoint$resume),
    p50 = TRUE
  )
  if (!all(checks)) {
    stop(sprintf("Candidate contract checks failed: %s.", paste(names(checks)[!checks], collapse = ", ")), call. = FALSE)
  }
  invisible(checks)
}

app_glofas_discrepancy_tau0_prior_reset_summary <- function(design, cfg, theta_mean, theta_cov) {
  vb_args <- app_make_qdesn_discrepancy_vb_args(
    cfg,
    prior = "rhs_ns",
    seed = as.integer(cfg$reservoir$seed),
    likelihood_family = "al"
  )
  state <- app_latent_prior_state_init(
    p = ncol(design$H_fixed),
    prior = "rhs_ns",
    intercept_index = design$intercept_index %||% integer(0),
    vb_args = vb_args,
    beta_index = design$beta_index,
    alpha_index = design$alpha_index
  )
  before <- state$blocks$alpha$state
  state <- app_latent_prior_state_update(
    state,
    theta_mean = theta_mean,
    theta_cov = theta_cov,
    iter = 0L
  )
  after <- state$blocks$alpha$state
  data.frame(
    discrepancy_tau0 = as.numeric(after$tau0),
    expected_initial_e_inv_tau2 = 1 / as.numeric(after$tau0)^2,
    initial_e_inv_tau2 = as.numeric(before$e_inv_tau2),
    post_transfer_e_inv_tau2 = as.numeric(after$e_inv_tau2),
    global_update_performed = isTRUE(after$last_global_update_performed),
    tau_update_count = as.integer(after$tau_update_count),
    local_state_changed = !isTRUE(all.equal(before$e_inv_lambda2, after$e_inv_lambda2, tolerance = 0)),
    prior_reset_passed = isTRUE(all.equal(
      as.numeric(after$e_inv_tau2), 1 / as.numeric(after$tau0)^2, tolerance = 1.0e-12
    )) && !isTRUE(after$last_global_update_performed),
    stringsAsFactors = FALSE
  )
}

app_glofas_discrepancy_tau0_check_loss <- function(observed, predicted, p = 0.5) {
  error <- as.numeric(observed) - as.numeric(predicted)
  mean(error * (as.numeric(p) - (error < 0)), na.rm = TRUE)
}

app_glofas_discrepancy_tau0_forecast_metrics <- function(forecast, last_discrepancy) {
  required <- c("horizon", "raw_glofas_quantile", "y_reference", "q_y_median", "d_g_median")
  missing <- setdiff(required, names(forecast))
  if (length(missing) || !nrow(forecast)) {
    stop(sprintf("Forecast table is empty or missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  forecast <- forecast[order(as.integer(forecast$horizon)), , drop = FALSE]
  observed_y <- as.numeric(forecast$y_reference)
  predicted_y <- as.numeric(forecast$q_y_median)
  observed_discrepancy <- as.numeric(forecast$raw_glofas_quantile) - observed_y
  predicted_discrepancy <- as.numeric(forecast$d_g_median)
  persistence <- rep(as.numeric(last_discrepancy), nrow(forecast))
  persistence_y <- as.numeric(forecast$raw_glofas_quantile) - persistence
  finite <- is.finite(observed_y) & is.finite(predicted_y) &
    is.finite(observed_discrepancy) & is.finite(predicted_discrepancy)
  if (!all(finite)) stop("Forecast diagnostic table contains non-finite values.", call. = FALSE)
  data.frame(
    n_horizons = nrow(forecast),
    forecast_check_loss = app_glofas_discrepancy_tau0_check_loss(observed_y, predicted_y),
    persistence_forecast_check_loss = app_glofas_discrepancy_tau0_check_loss(observed_y, persistence_y),
    discrepancy_mae = mean(abs(predicted_discrepancy - observed_discrepancy)),
    discrepancy_rmse = sqrt(mean((predicted_discrepancy - observed_discrepancy)^2)),
    discrepancy_bias = mean(predicted_discrepancy - observed_discrepancy),
    discrepancy_correlation = if (stats::sd(predicted_discrepancy) > 0) {
      stats::cor(predicted_discrepancy, observed_discrepancy)
    } else NA_real_,
    predicted_discrepancy_sd = stats::sd(predicted_discrepancy),
    predicted_discrepancy_range = diff(range(predicted_discrepancy)),
    persistence_discrepancy_mae = mean(abs(persistence - observed_discrepancy)),
    persistence_discrepancy_rmse = sqrt(mean((persistence - observed_discrepancy)^2)),
    stringsAsFactors = FALSE
  )
}

app_glofas_discrepancy_tau0_rank <- function(
  metrics,
  min_persistence_improvement = 0.03,
  max_history_regression = 0.03
) {
  required <- c(
    "candidate_id", "discrepancy_tau0", "candidate_role", "technical_gate_pass",
    "forecast_check_loss", "persistence_forecast_check_loss", "discrepancy_mae",
    "persistence_discrepancy_mae", "observed_log1p_mae_all",
    "observed_log1p_mae_last1000", "observed_log1p_mae_last200",
    "observed_log1p_mae_last50"
  )
  missing <- setdiff(required, names(metrics))
  if (!is.data.frame(metrics) || !nrow(metrics) || length(missing)) {
    stop(sprintf("Candidate metrics are empty or missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  min_persistence_improvement <- as.numeric(min_persistence_improvement)
  if (!is.finite(min_persistence_improvement) || min_persistence_improvement < 0) {
    stop("min_persistence_improvement must be finite and nonnegative.", call. = FALSE)
  }
  out <- metrics
  numeric_required <- setdiff(required, c("candidate_id", "candidate_role", "technical_gate_pass"))
  if (any(!vapply(out[numeric_required], function(x) all(is.finite(as.numeric(x))), logical(1L)))) {
    stop("Candidate ranking requires finite scientific metrics.", call. = FALSE)
  }
  out$technical_gate_pass <- app_as_bool_vec(out$technical_gate_pass)
  if (any(is.na(out$technical_gate_pass))) {
    stop("Candidate ranking requires a finite technical gate.", call. = FALSE)
  }
  guardrails <- app_glofas_discrepancy_tau0_guardrails(max_history_regression)
  for (window in guardrails$window) {
    field <- paste0("observed_log1p_mae_", window)
    threshold <- guardrails$maximum_allowed_log1p_mae[guardrails$window == window]
    out[[paste0("history_gate_", window)]] <- as.numeric(out[[field]]) <= threshold
  }
  history_fields <- paste0("history_gate_", guardrails$window)
  out$historical_gate_pass <- Reduce(`&`, out[history_fields])
  out$forecast_improvement_vs_persistence_fraction <- (
    as.numeric(out$persistence_forecast_check_loss) - as.numeric(out$forecast_check_loss)
  ) / as.numeric(out$persistence_forecast_check_loss)
  out$discrepancy_improvement_vs_persistence_fraction <- (
    as.numeric(out$persistence_discrepancy_mae) - as.numeric(out$discrepancy_mae)
  ) / as.numeric(out$persistence_discrepancy_mae)
  out$persistence_gate_pass <- out$forecast_improvement_vs_persistence_fraction >= min_persistence_improvement &
    out$discrepancy_improvement_vs_persistence_fraction >= min_persistence_improvement
  out$eligible_for_cold_confirmation <- out$technical_gate_pass &
    out$historical_gate_pass & out$persistence_gate_pass
  out$automatic_promotion <- FALSE
  out$automatic_full7 <- FALSE
  out$decision <- ifelse(
    out$eligible_for_cold_confirmation,
    "eligible_for_diagnostic_review_then_cold_confirmation",
    ifelse(
      !out$technical_gate_pass,
      "reject_technical_gate",
      ifelse(!out$historical_gate_pass, "reject_historical_fit_regression", "reject_insufficient_persistence_gain")
    )
  )
  out <- out[order(
    !out$eligible_for_cold_confirmation,
    as.numeric(out$forecast_check_loss),
    as.numeric(out$discrepancy_mae),
    as.numeric(out$observed_log1p_mae_all),
    as.character(out$candidate_id)
  ), , drop = FALSE]
  out$screen_rank <- seq_len(nrow(out))
  rownames(out) <- NULL
  out
}

app_glofas_discrepancy_tau0_canary <- function(warm_forecast, cold_forecast, warm_history, cold_history) {
  merge_key <- c("target_date", "horizon")
  warm_forecast$target_date <- as.character(as.Date(warm_forecast$target_date))
  cold_forecast$target_date <- as.character(as.Date(cold_forecast$target_date))
  paired <- merge(
    warm_forecast[, c(merge_key, "q_y_median", "d_g_median")],
    cold_forecast[, c(merge_key, "q_y_median", "d_g_median")],
    by = merge_key, suffixes = c("_warm", "_cold"), sort = TRUE
  )
  warm_all <- warm_history[as.character(warm_history$window) %in% c("all", "last1000", "last200", "last50"), ]
  cold_all <- cold_history[as.character(cold_history$window) %in% c("all", "last1000", "last200", "last50"), ]
  history <- merge(
    warm_all[, c("window", "log1p_mae")], cold_all[, c("window", "log1p_mae")],
    by = "window", suffixes = c("_warm", "_cold"), sort = TRUE
  )
  warm_loss <- app_glofas_discrepancy_tau0_check_loss(warm_forecast$y_reference, warm_forecast$q_y_median)
  cold_loss <- app_glofas_discrepancy_tau0_check_loss(cold_forecast$y_reference, cold_forecast$q_y_median)
  loss_tolerance <- max(1.0e-4, 0.001 * abs(cold_loss))
  data.frame(
    warm_check_loss = warm_loss,
    cold_check_loss = cold_loss,
    check_loss_abs_difference = abs(warm_loss - cold_loss),
    check_loss_tolerance = loss_tolerance,
    q_y_path_rmse = sqrt(mean((paired$q_y_median_warm - paired$q_y_median_cold)^2)),
    discrepancy_path_rmse = sqrt(mean((paired$d_g_median_warm - paired$d_g_median_cold)^2)),
    discrepancy_path_rmse_tolerance = 0.01,
    max_history_mae_abs_difference = max(abs(history$log1p_mae_warm - history$log1p_mae_cold)),
    history_mae_tolerance = 0.001,
    equivalent = abs(warm_loss - cold_loss) <= loss_tolerance &&
      sqrt(mean((paired$d_g_median_warm - paired$d_g_median_cold)^2)) <= 0.01 &&
      max(abs(history$log1p_mae_warm - history$log1p_mae_cold)) <= 0.001,
    stringsAsFactors = FALSE
  )
}
