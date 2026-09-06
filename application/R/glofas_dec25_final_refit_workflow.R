# Hard gates and reusable helpers for the Jerez Dec 25, 2022 GloFAS final-refit relaunch.

app_glofas_dec25_contract <- function() {
  list(
    cutoff_id = "dec25_2022",
    train_end = as.Date("2022-12-25"),
    origin_date = as.Date("2022-12-25"),
    forecast_start = as.Date("2022-12-26"),
    forecast_end = as.Date("2023-01-24"),
    horizon_days = 30L,
    horizons = seq_len(30L),
    part2_final_train_rows = 12495L,
    part3_final_dates = 12495L,
    part3_final_stacked_rows = 24990L,
    part2_discrepancy_sign = "retrospective_glofas_minus_usgs",
    part3_sign = "glofas = reference + discrepancy"
  )
}

app_glofas_dec25_expected_future_dates <- function() {
  c <- app_glofas_dec25_contract()
  seq.Date(c$forecast_start, c$forecast_end, by = "day")
}

app_glofas_dec25_assert_window <- function(
  origin_date,
  horizon_days,
  future_dates = NULL,
  cutoff_id = NULL,
  label = "GloFAS Dec 25 final-refit workflow"
) {
  c <- app_glofas_dec25_contract()
  origin_date <- as.Date(origin_date)
  horizon_days <- as.integer(horizon_days)
  if (length(origin_date) != 1L || is.na(origin_date) || origin_date != c$origin_date) {
    stop(sprintf("%s must use origin_date/train_end 2022-12-25.", label), call. = FALSE)
  }
  if (length(horizon_days) != 1L || !is.finite(horizon_days) || horizon_days != c$horizon_days) {
    stop(sprintf("%s must use horizon_days=30.", label), call. = FALSE)
  }
  if (!is.null(cutoff_id)) {
    cutoff_id <- as.character(cutoff_id[[1L]])
    if (!identical(cutoff_id, c$cutoff_id)) {
      stop(sprintf("%s must use cutoff_id=dec25_2022.", label), call. = FALSE)
    }
  }
  if (!is.null(future_dates)) {
    future_dates <- as.Date(future_dates)
    expected <- app_glofas_dec25_expected_future_dates()
    if (length(future_dates) != length(expected) || anyNA(future_dates) || any(future_dates != expected)) {
      stop(sprintf("%s must forecast exactly 2022-12-26 through 2023-01-24.", label), call. = FALSE)
    }
  }
  invisible(TRUE)
}

app_glofas_dec25_final_split <- function(
  dates,
  expected_n = NULL,
  label = "final design"
) {
  c <- app_glofas_dec25_contract()
  dates <- as.Date(dates)
  if (!length(dates) || anyNA(dates) || any(duplicated(dates))) {
    stop(sprintf("%s dates must be complete and unique.", label), call. = FALSE)
  }
  if (max(dates) != c$train_end) {
    stop(sprintf("%s must end exactly on 2022-12-25.", label), call. = FALSE)
  }
  if (any(dates > c$train_end)) {
    stop(sprintf("%s contains dates after the immutable train_end.", label), call. = FALSE)
  }
  if (!is.null(expected_n) && length(dates) != as.integer(expected_n)) {
    stop(sprintf("%s has %d rows; expected %d.", label, length(dates), as.integer(expected_n)), call. = FALSE)
  }
  list(train_idx = seq_along(dates), valid_idx = integer(0), validation_n = 0L, final_refit = TRUE)
}

app_glofas_dec25_validate_part2_design <- function(design) {
  c <- app_glofas_dec25_contract()
  split <- app_glofas_dec25_final_split(design$dates, c$part2_final_train_rows, "Part 2 final discrepancy design")
  gap <- max(abs(as.numeric(design$g_retrospective) - as.numeric(design$y_reference) - as.numeric(design$d_g)))
  if (!is.finite(gap) || gap > 1.0e-10) {
    stop("Part 2 final design violates d_t = retrospective GloFAS_t - USGS_t.", call. = FALSE)
  }
  if (nrow(design$discrepancy$X) != c$part2_final_train_rows ||
      length(design$discrepancy$y) != c$part2_final_train_rows) {
    stop("Part 2 discrepancy design does not have 12,495 final training rows.", call. = FALSE)
  }
  split
}

app_glofas_dec25_validate_part3_design <- function(design) {
  c <- app_glofas_dec25_contract()
  split <- app_glofas_dec25_final_split(design$dates, c$part3_final_dates, "Part 3 final joint design")
  if (nrow(design$H) != c$part3_final_stacked_rows || length(design$z) != c$part3_final_stacked_rows) {
    stop("Part 3 final stacked design must contain 24,990 Normal observations.", call. = FALSE)
  }
  gap <- max(abs(as.numeric(design$y_reference) + as.numeric(design$d_g) - as.numeric(design$g_retrospective)))
  if (!is.finite(gap) || gap > 1.0e-10) {
    stop("Part 3 final design violates GloFAS = reference + discrepancy.", call. = FALSE)
  }
  split
}

app_glofas_dec25_part2_design_cache <- function(
  base_cfg,
  rhs_row,
  panel_bundle = NULL,
  reference_cache = NULL,
  root_candidates = NULL
) {
  c <- app_glofas_dec25_contract()
  design <- app_glofas_normal_part2_build_design(
    base_cfg = base_cfg,
    candidate_row = rhs_row,
    panel_bundle = panel_bundle,
    reference_cache = reference_cache
  )
  split <- app_glofas_dec25_validate_part2_design(design)
  candidate <- app_glofas_part2_bridge_candidate_from_rhs_row(rhs_row)
  bundle <- app_glofas_oracle_prepare_panel_bundle(
    cfg = base_cfg,
    origin_date = c$origin_date,
    horizon_days = c$horizon_days,
    target = "discrepancy",
    root_candidates = root_candidates
  )
  forecast_design <- app_glofas_oracle_build_part1_design(
    base_cfg = base_cfg,
    candidate_row = candidate,
    panel_bundle = bundle
  )
  if (nrow(forecast_design$X) != c$part2_final_train_rows ||
      length(forecast_design$dates) != c$part2_final_train_rows ||
      max(as.Date(forecast_design$dates)) != c$train_end) {
    stop("Part 2 forecastable discrepancy design does not match the Dec 25 final cache contract.", call. = FALSE)
  }
  list(
    schema_version = "glofas_part2_final_dec25_2022_design_cache_v1",
    generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    contract = app_glofas_dec25_contract(),
    base_cfg = base_cfg,
    rhs_row = rhs_row[1L, , drop = FALSE],
    candidate_row = candidate,
    design = design,
    forecast_design = forecast_design,
    bundle = bundle,
    split = split,
    design_hash = design$design_hash,
    target = "observed_discrepancy_retrospective_glofas_minus_usgs"
  )
}

app_glofas_dec25_part3_design_cache <- function(base_cfg, candidate_row, panel_bundle = NULL, reference_cache = NULL) {
  design <- app_glofas_normal_part3_build_design(
    base_cfg = base_cfg,
    candidate_row = candidate_row,
    panel_bundle = panel_bundle,
    reference_cache = reference_cache
  )
  split <- app_glofas_dec25_validate_part3_design(design)
  list(
    schema_version = "glofas_part3_final_dec25_2022_design_cache_v1",
    generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    contract = app_glofas_dec25_contract(),
    candidate_row = candidate_row[1L, , drop = FALSE],
    design = design,
    split = split,
    design_hash = design$design_hash,
    target = "two_component_usgs_reference_and_glofas_discrepancy"
  )
}

app_glofas_dec25_part2_ridge_warm_start <- function(fit, design, split, candidate_row) {
  train_hash <- app_glofas_normal_part1_design_fingerprint(
    design$discrepancy$X[split$train_idx, , drop = FALSE],
    design$discrepancy$y[split$train_idx],
    design$dates[split$train_idx],
    design$discrepancy$feature_info
  )
  warm <- list(
    type = "glofas_normal_part1_ridge_warm_start",
    version = "0.2",
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    candidate_id = as.character(candidate_row$candidate_id[[1L]] %||% "part2_final_discrepancy"),
    target = "observed_discrepancy_retrospective_glofas_minus_usgs",
    design = list(
      n = length(split$train_idx),
      p = ncol(design$discrepancy$X),
      colnames = colnames(design$discrepancy$X),
      train_design_fingerprint = train_hash,
      full_design_fingerprint = as.character(design$design_hash$discrepancy_full)
    ),
    fit = list(
      beta_mean = as.numeric(fit$beta_mean),
      beta_var_diag = as.numeric(fit$beta_var_diag),
      sigma_a = as.numeric(fit$sigma_a),
      sigma_b = as.numeric(fit$sigma_b),
      sigma2_mean = as.numeric(fit$sigma2_mean),
      ridge_tau2 = as.numeric(fit$ridge_tau2),
      intercept_var = as.numeric(fit$intercept_var),
      n_train = as.integer(fit$n_train),
      p = as.integer(fit$p)
    )
  )
  class(warm) <- c("glofas_normal_part1_ridge_warm_start", "list")
  warm
}

app_glofas_dec25_fit_part2_normal_ridge <- function(cache) {
  design <- cache$design
  split <- cache$split
  row <- cache$rhs_row
  fit <- app_glofas_normal_ridge_fit(
    X = design$discrepancy$X[split$train_idx, , drop = FALSE],
    y = design$discrepancy$y[split$train_idx],
    ridge_tau2 = as.numeric(app_glofas_normal_part2_row_value(row, "ridge_tau2", app_glofas_normal_part2_default_values()$ridge_tau2)),
    intercept_var = as.numeric(app_glofas_normal_part2_row_value(row, "intercept_var", app_glofas_normal_part2_default_values()$intercept_var)),
    sigma_a = as.numeric(app_glofas_normal_part2_row_value(row, "sigma_a", app_glofas_normal_part2_default_values()$sigma_a)),
    sigma_b = as.numeric(app_glofas_normal_part2_row_value(row, "sigma_b", app_glofas_normal_part2_default_values()$sigma_b))
  )
  fit$type <- "normal_ridge_part2_discrepancy_final_dec25_2022"
  warm <- app_glofas_dec25_part2_ridge_warm_start(fit, design, split, row)
  list(fit = fit, warm_start = warm, design = design, split = split)
}

app_glofas_dec25_fit_part2_normal_rhs <- function(cache, warm_start) {
  design <- cache$design
  split <- cache$split
  row <- cache$rhs_row
  app_glofas_normal_part1_validate_ridge_warm_start(
    warm_start,
    candidate_row = data.frame(candidate_id = warm_start$candidate_id, stringsAsFactors = FALSE),
    design = list(X = design$discrepancy$X, y = design$discrepancy$y, dates = design$dates, feature_info = design$discrepancy$feature_info),
    train_idx = split$train_idx,
    strict_hash = TRUE
  )
  fit <- app_glofas_normal_rhs_fit(
    X = design$discrepancy$X[split$train_idx, , drop = FALSE],
    y = design$discrepancy$y[split$train_idx],
    ridge_warm_start = warm_start,
    tau0 = as.numeric(app_glofas_normal_part2_row_value(row, "rhs_tau0_discrepancy", 0.001)),
    max_iter = as.integer(app_glofas_normal_part2_row_value(row, "rhs_max_iter", 100L)),
    min_iter = as.integer(app_glofas_normal_part2_row_value(row, "rhs_min_iter", 30L)),
    tol = as.numeric(app_glofas_normal_part2_row_value(row, "rhs_tol", 1.0e-4)),
    rhs_update_every = as.integer(app_glofas_normal_part2_row_value(row, "rhs_update_every", 1L)),
    freeze_tau_warmup_iters = as.integer(app_glofas_normal_part2_row_value(row, "rhs_freeze_tau_warmup_iters", 0L)),
    min_tau_updates = as.integer(app_glofas_normal_part2_row_value(row, "rhs_min_tau_updates", 0L)),
    freeze_beta_warmup_iters = as.integer(app_glofas_normal_part2_row_value(row, "rhs_freeze_beta_warmup_iters", 20L)),
    min_beta_updates = as.integer(app_glofas_normal_part2_row_value(row, "rhs_min_beta_updates", 30L))
  )
  fit$type <- "normal_rhs_vb_part2_discrepancy_final_dec25_2022"
  list(fit = fit, warm_start = warm_start, design = design, split = split)
}

app_glofas_dec25_part2_fitted_from_fit <- function(cache, fit, method = c("ridge", "rhs")) {
  method <- match.arg(method)
  c <- app_glofas_dec25_contract()
  design <- cache$forecast_design
  if (ncol(design$X) != as.integer(fit$p %||% length(fit$beta_mean))) {
    stop("Part 2 final fit dimension does not match cached forecast design.", call. = FALSE)
  }
  names(fit$beta_mean) <- colnames(design$X)
  fitted <- list(
    method = method,
    candidate_row = cache$candidate_row,
    part2_rhs_row = cache$rhs_row,
    base_cfg = cache$base_cfg,
    bundle = cache$bundle,
    design = design,
    fit = fit,
    fit_object_path = as.character(fit$fit_object_path %||% NA_character_),
    ridge_fit = if (identical(method, "ridge")) fit else NULL,
    warm_start = NULL,
    fit_runtime_seconds = as.numeric(fit$fit_runtime_seconds %||% NA_real_),
    fit_reused = TRUE,
    fit_reuse_contract = sprintf("retained_final_dec25_2022_%s_discrepancy_fit_reused_without_refit", method)
  )
  app_glofas_dec25_assert_window(c$origin_date, c$horizon_days, fitted$bundle$future_dates, label = "Part 2 final fitted forecast")
  app_glofas_part2_bridge_validate_design_contract(fitted)
  fitted
}

app_glofas_dec25_forecast_part2_normal <- function(
  cache,
  fit,
  method = c("ridge", "rhs"),
  forecast_mode = c("plugin_mean_recursive", "draw_recursive"),
  n_draws = 500L,
  seed = 20260905L,
  forecast_backend = c("auto", "cpp", "r"),
  progress_every = NULL
) {
  method <- match.arg(method)
  forecast_mode <- match.arg(forecast_mode)
  forecast_backend <- match.arg(forecast_backend)
  fitted <- app_glofas_dec25_part2_fitted_from_fit(cache, fit, method = method)
  started <- Sys.time()
  cov_timeline <- attr(fitted$bundle$panel, "model_covariate_timeline", exact = TRUE)
  forecast <- if (identical(forecast_mode, "draw_recursive")) {
    app_glofas_oracle_draw_recursive_forecast(
      fitted = fitted,
      future_dates = fitted$bundle$future_dates,
      covariate_timeline = cov_timeline,
      n_draws = n_draws,
      seed = seed,
      forecast_backend = forecast_backend,
      progress_every = progress_every
    )
  } else {
    app_glofas_oracle_recursive_forecast(
      fitted = fitted,
      future_dates = fitted$bundle$future_dates,
      covariate_timeline = cov_timeline,
      forecast_backend = forecast_backend
    )
  }
  forecast$future_input_audit <- app_glofas_part2_bridge_relabel_audit(forecast$future_input_audit)
  app_glofas_part2_bridge_validate_no_future_usgs_leakage(forecast$future_input_audit)
  truth <- app_glofas_part2_bridge_reference_truth(cache$base_cfg %||% fitted$base_cfg, fitted$bundle)
  path_table <- app_glofas_part2_bridge_augment_normal_path(fitted, forecast, truth)
  scores <- app_glofas_part2_bridge_score_normal(path_table, forecast)
  list(
    target = "discrepancy",
    corrected_target = "usgs",
    diagnostic_type = "part2_final_dec25_2022_discrepancy_bridge_forecast",
    fitted = fitted,
    part2_rhs_row = cache$rhs_row,
    forecast = forecast,
    path_table = path_table,
    scores = scores,
    score_reproduction = data.frame(
      score_reproduction_contract = "not_applicable_final_dec25_refit",
      stringsAsFactors = FALSE
    ),
    origin_date = app_glofas_dec25_contract()$origin_date,
    effective_horizon = length(forecast$future_dates),
    future_retrospective_available = all(is.finite(path_table$retrospective_glofas[path_table$segment == "oracle_realized_forecast"])),
    future_scoring_status = if (nrow(scores$pointwise %||% data.frame())) "available" else "unavailable_missing_future_retrospective_glofas",
    forecast_runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    retain_draws = FALSE
  )
}

app_glofas_dec25_fit_part2_quantile <- function(
  cache,
  model_family = c("independent_al", "independent_exal", "joint_al", "joint_exal"),
  tau = NULL,
  controls = app_glofas_part1_quantile_default_controls(
    max_iter = 100L,
    min_iter = 30L,
    tol = 0.01,
    freeze_beta_warmup_iters = 20L,
    min_beta_updates = 30L,
    progress_every = 1L
  )
) {
  model_family <- match.arg(model_family)
  tau <- tau %||% if (startsWith(model_family, "joint")) app_glofas_part2_bridge_quantile_grid() else 0.5
  design <- cache$forecast_design
  fit <- app_glofas_part1_quantile_fit_readout(
    y = design$y,
    Z = as.matrix(design$X[, -1L, drop = FALSE]),
    tau = as.numeric(tau),
    model_family = model_family,
    controls = controls
  )
  fit$target <- "observed_discrepancy_retrospective_glofas_minus_usgs"
  fit$cutoff_id <- app_glofas_dec25_contract()$cutoff_id
  fit$train_end <- as.character(app_glofas_dec25_contract()$train_end)
  fit
}

app_glofas_dec25_forecast_part2_quantile <- function(
  cache,
  fit,
  tau,
  forecast_backend = c("auto", "cpp", "r")
) {
  forecast_backend <- match.arg(forecast_backend)
  fitted <- list(
    candidate_row = cache$candidate_row,
    bundle = cache$bundle,
    design = cache$forecast_design,
    Z = as.matrix(cache$forecast_design$X[, -1L, drop = FALSE])
  )
  forecast <- app_glofas_part1_quantile_recursive_forecast(
    fitted = fitted,
    fit = fit,
    tau = as.numeric(tau),
    future_dates = cache$bundle$future_dates,
    covariate_timeline = attr(cache$bundle$panel, "model_covariate_timeline", exact = TRUE),
    forecast_backend = forecast_backend
  )
  forecast$future_input_audit <- app_glofas_part2_bridge_relabel_audit(forecast$future_input_audit)
  app_glofas_part2_bridge_validate_no_future_usgs_leakage(forecast$future_input_audit)
  path_table <- app_glofas_part1_quantile_path_table(
    fitted = fitted,
    fit = fit,
    tau = as.numeric(tau),
    forecast = forecast,
    future_truth = cache$bundle$future_truth
  )
  result <- list(path_table = path_table, prepared = list(bundle = cache$bundle))
  path <- app_glofas_part2_bridge_quantile_transform_path(result, cache$base_cfg)
  model_family <- as.character(fit$model_family %||% if (!is.null(fit$gamma_mean)) "independent_exal" else "independent_al")
  likelihood <- if (grepl("exal", model_family, ignore.case = TRUE) || !is.null(fit$gamma_mean)) "exAL" else "AL"
  fit_structure <- if (length(tau) > 1L || grepl("^joint", model_family)) "joint" else "independent"
  list(
    target = "discrepancy",
    corrected_target = "usgs",
    diagnostic_type = "part2_final_dec25_2022_discrepancy_quantile_bridge_forecast",
    candidate_row = cache$candidate_row,
    part2_rhs_row = cache$rhs_row,
    model_family = model_family,
    likelihood = likelihood,
    fit_structure = fit_structure,
    tau = as.numeric(tau),
    origin_date = app_glofas_dec25_contract()$origin_date,
    controls = fit$part1_quantile_controls %||% list(),
    fit = fit,
    forecast = forecast,
    path_table = path_table,
    part2_path_table = path,
    trace = app_glofas_part1_quantile_trace_rows(fit, model_family, tau),
    coefficients = app_glofas_part1_quantile_coefficient_rows(
      fit,
      as.matrix(cache$forecast_design$X[, -1L, drop = FALSE]),
      tau
    ),
    part2_scores = app_glofas_part2_bridge_score_quantile(path),
    future_scoring_status = if (any(is.finite(path$retrospective_glofas[path$segment == "oracle_realized_forecast"]))) "available" else "unavailable_missing_future_retrospective_glofas"
  )
}

app_glofas_dec25_fit_part3_normal_ridge <- function(cache) {
  design <- cache$design
  split <- cache$split
  row <- cache$candidate_row
  stack_split <- app_glofas_normal_part3_stack_split(design, split)
  fit <- app_glofas_normal_ridge_fit(
    X = design$H[stack_split$train_idx, , drop = FALSE],
    y = design$z[stack_split$train_idx],
    ridge_tau2 = as.numeric(app_glofas_normal_part2_row_value(row, "ridge_tau2", app_glofas_normal_part2_default_values()$ridge_tau2)),
    intercept_var = as.numeric(app_glofas_normal_part2_row_value(row, "intercept_var", app_glofas_normal_part2_default_values()$intercept_var)),
    sigma_a = as.numeric(app_glofas_normal_part2_row_value(row, "sigma_a", app_glofas_normal_part2_default_values()$sigma_a)),
    sigma_b = as.numeric(app_glofas_normal_part2_row_value(row, "sigma_b", app_glofas_normal_part2_default_values()$sigma_b))
  )
  fit$type <- "normal_ridge_part3_joint_final_dec25_2022"
  fit$iterations <- NA_integer_
  fit$converged <- TRUE
  warm <- app_glofas_normal_part3_make_ridge_warm_start(fit, design, split, row)
  list(fit = fit, warm_start = warm, design = design, split = split)
}

app_glofas_dec25_fit_part3_normal_rhs <- function(cache, warm_start) {
  design <- cache$design
  split <- cache$split
  row <- cache$candidate_row
  stack_split <- app_glofas_normal_part3_stack_split(design, split)
  app_glofas_normal_part3_validate_warm_start(warm_start, design = design, split = split)
  fit <- app_glofas_normal_part3_rhs_fit_blocked(
    X = design$H[stack_split$train_idx, , drop = FALSE],
    y = design$z[stack_split$train_idx],
    ridge_warm_start = warm_start,
    p_beta = design$p_beta,
    p_alpha = design$p_alpha,
    reference_intercept_index = 1L,
    discrepancy_intercept_index = 1L,
    tau0_reference = as.numeric(app_glofas_normal_part2_row_value(row, "rhs_tau0_reference", 1)),
    tau0_discrepancy = as.numeric(app_glofas_normal_part2_row_value(row, "rhs_tau0_discrepancy", 0.001)),
    max_iter = as.integer(app_glofas_normal_part2_row_value(row, "rhs_max_iter", 100L)),
    min_iter = as.integer(app_glofas_normal_part2_row_value(row, "rhs_min_iter", 30L)),
    tol = as.numeric(app_glofas_normal_part2_row_value(row, "rhs_tol", 1.0e-4)),
    rhs_update_every = as.integer(app_glofas_normal_part2_row_value(row, "rhs_update_every", 1L)),
    freeze_tau_warmup_iters = as.integer(app_glofas_normal_part2_row_value(row, "rhs_freeze_tau_warmup_iters", 0L)),
    min_tau_updates = as.integer(app_glofas_normal_part2_row_value(row, "rhs_min_tau_updates", 0L)),
    freeze_beta_warmup_iters = as.integer(app_glofas_normal_part2_row_value(row, "rhs_freeze_beta_warmup_iters", 20L)),
    min_beta_updates = as.integer(app_glofas_normal_part2_row_value(row, "rhs_min_beta_updates", 30L))
  )
  fit$type <- "normal_rhs_vb_part3_joint_final_dec25_2022"
  list(fit = fit, warm_start = warm_start, design = design, split = split)
}

app_glofas_dec25_affine_remap_coefficients <- function(
  beta,
  old_center,
  old_scale,
  new_center,
  new_scale,
  intercept_index = 1L
) {
  beta <- as.numeric(beta)
  intercept_index <- as.integer(intercept_index)
  feature_idx <- setdiff(seq_along(beta), intercept_index)
  old_center <- rep(as.numeric(old_center), length.out = length(feature_idx))
  old_scale <- rep(as.numeric(old_scale), length.out = length(feature_idx))
  new_center <- rep(as.numeric(new_center), length.out = length(feature_idx))
  new_scale <- rep(as.numeric(new_scale), length.out = length(feature_idx))
  if (any(!is.finite(old_scale) | old_scale == 0 | !is.finite(new_scale) | new_scale == 0)) {
    stop("Affine coefficient remapping requires finite nonzero scales.", call. = FALSE)
  }
  out <- beta
  out[feature_idx] <- beta[feature_idx] * new_scale / old_scale
  out[[intercept_index]] <- beta[[intercept_index]] + sum(beta[feature_idx] * (new_center - old_center) / old_scale)
  out
}

app_glofas_dec25_assert_affine_prediction_equivalence <- function(
  beta_old,
  beta_new,
  x_raw,
  old_center,
  old_scale,
  new_center,
  new_scale,
  tol = 1.0e-10
) {
  x_raw <- as.matrix(x_raw)
  old_x <- scale(x_raw, center = old_center, scale = old_scale)
  new_x <- scale(x_raw, center = new_center, scale = new_scale)
  pred_old <- as.numeric(cbind(1, old_x) %*% as.numeric(beta_old))
  pred_new <- as.numeric(cbind(1, new_x) %*% as.numeric(beta_new))
  gap <- max(abs(pred_old - pred_new))
  if (!is.finite(gap) || gap > tol) stop("Affine coefficient remapping failed predictor equivalence.", call. = FALSE)
  invisible(gap)
}

app_glofas_dec25_initializer_row <- function(
  part,
  model_id,
  parameter_block,
  source_path = NA_character_,
  source_sha256 = NA_character_,
  compatibility = "pending_audit",
  reason = "",
  objective = NA_real_
) {
  data.frame(
    part = part,
    model_id = model_id,
    parameter_block = parameter_block,
    source_path = as.character(source_path),
    source_sha256 = as.character(source_sha256),
    compatibility = compatibility,
    reason = reason,
    initial_objective_on_final_design = as.numeric(objective),
    required_checks = paste(
      c("target_sign", "feature_order", "intercept", "geometry", "seed", "lags",
        "state_transform", "standardization", "prior", "likelihood", "quantile", "source_sha256"),
      collapse = "|"
    ),
    stringsAsFactors = FALSE
  )
}
