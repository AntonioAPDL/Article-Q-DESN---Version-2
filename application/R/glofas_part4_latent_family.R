# GloFAS Part 4 latent-path family execution and scoring helpers.

app_glofas_part4_fixed_window <- function() {
  list(
    cutoff = as.Date("2022-12-25"),
    forecast_start = as.Date("2022-12-26"),
    requested_forecast_end = as.Date("2023-01-24"),
    issued_forecast_end = as.Date("2023-01-22"),
    requested_horizon = 30L,
    issued_horizon = 28L,
    ensemble_members = 51L
  )
}

app_glofas_part4_build_panel <- function(cfg) {
  validated <- app_validate_input_manifest(
    app_config_path(cfg, "input_manifest"),
    app_config_path(cfg, "schema"),
    require_files = TRUE
  )
  if (!isTRUE(validated$ok)) {
    stop(
      sprintf("Part 4 input validation failed: %s", paste(validated$issues, collapse = " | ")),
      call. = FALSE
    )
  }
  panel <- app_build_application_panel(cfg, validated$manifest, validated$schema)
  app_validate_panel(panel, validated$schema)
  panel
}

app_glofas_part4_window_audit <- function(
    panel,
    cutoff_row,
    expected = app_glofas_part4_fixed_window(),
    strict_members = TRUE) {
  checks <- list(
    origin = identical(as.Date(cutoff_row$origin_date[[1L]]), expected$cutoff),
    train_end = identical(as.Date(cutoff_row$train_end[[1L]]), expected$cutoff),
    eval_start = identical(as.Date(cutoff_row$eval_start[[1L]]), expected$forecast_start),
    eval_end = identical(as.Date(cutoff_row$eval_end[[1L]]), expected$requested_forecast_end),
    requested_horizon = identical(as.integer(cutoff_row$horizon_max[[1L]]), expected$requested_horizon)
  )
  ens <- panel[
    panel$is_ensemble &
      as.Date(panel$origin_date) == expected$cutoff &
      is.finite(panel$g_transformed),
    ,
    drop = FALSE
  ]
  horizons <- sort(unique(as.integer(ens$horizon)))
  checks$issued_horizons <- identical(horizons, seq_len(expected$issued_horizon))
  checks$issued_dates <- nrow(ens) > 0L &&
    identical(min(as.Date(ens$target_date)), expected$forecast_start) &&
    identical(max(as.Date(ens$target_date)), expected$issued_forecast_end)
  counts <- if (nrow(ens)) table(as.Date(ens$target_date), as.integer(ens$horizon)) else integer()
  active_counts <- as.integer(counts[counts > 0])
  checks$member_count <- !isTRUE(strict_members) ||
    (length(active_counts) == expected$issued_horizon && all(active_counts == expected$ensemble_members))
  truth <- app_make_glofas_latent_path_scoring_truth(
    panel,
    data.frame(
      target_date = expected$forecast_start + 0:(expected$issued_horizon - 1L),
      horizon = seq_len(expected$issued_horizon)
    )
  )
  checks$scoring_truth_available <- all(is.finite(truth$y_reference))
  out <- data.frame(
    check = names(checks),
    status = ifelse(unlist(checks), "pass", "fail"),
    stringsAsFactors = FALSE
  )
  out$detail <- c(
    as.character(as.Date(cutoff_row$origin_date[[1L]])),
    as.character(as.Date(cutoff_row$train_end[[1L]])),
    as.character(as.Date(cutoff_row$eval_start[[1L]])),
    as.character(as.Date(cutoff_row$eval_end[[1L]])),
    as.character(as.integer(cutoff_row$horizon_max[[1L]])),
    if (length(horizons)) paste(range(horizons), collapse = ":") else "none",
    if (nrow(ens)) paste(range(as.Date(ens$target_date)), collapse = ":") else "none",
    if (length(active_counts)) paste(range(active_counts), collapse = ":") else "none",
    sprintf("%d/%d", sum(is.finite(truth$y_reference)), nrow(truth))
  )
  if (any(out$status != "pass")) {
    stop(
      sprintf("Part 4 fixed-window contract failed: %s", paste(out$check[out$status != "pass"], collapse = ", ")),
      call. = FALSE
    )
  }
  out
}

app_glofas_part4_state_contract_hash <- function(design) {
  probe <- app_latent_path_future_probe(design)
  app_latent_path_contract_hash(
    list(
      H_fixed_columns = colnames(design$H_fixed),
      H_fixed_dim = dim(design$H_fixed),
      beta_index = design$beta_index,
      alpha_index = design$alpha_index,
      future_key = transform(design$future_key, target_date = as.character(as.Date(target_date))),
      H_y_dim = dim(probe$H_y),
      H_g_key_dim = dim(app_latent_future_H_g_key(probe)),
      ensemble_index = app_latent_future_g_index(probe),
      weight_g = as.numeric(probe$weight_g),
      feature_strategy = design$feature_strategy,
      design_version = design$design_version
    ),
    prefix = "glofas_part4_state_"
  )
}

app_glofas_part4_design_for_quantile <- function(design, tau) {
  tau <- as.numeric(tau)
  if (length(tau) != 1L || !is.finite(tau) || tau <= 0 || tau >= 1) {
    stop("Part 4 quantile must be one finite value in (0, 1).", call. = FALSE)
  }
  out <- design
  out$p0 <- tau
  out
}

app_glofas_part4_extract_fit <- function(x) {
  fit <- x$fit %||% x
  if (!is.list(fit) || is.null(fit$summary$theta_mean) || is.null(fit$summary$y_future_mean)) {
    stop("Part 4 initializer is not a completed latent-path fit.", call. = FALSE)
  }
  fit
}

app_glofas_part4_initializer <- function(x, design, source_path = NA_character_) {
  fit <- app_glofas_part4_extract_fit(x)
  p <- ncol(design$H_fixed)
  H <- nrow(design$future_key)
  theta_mean <- as.numeric(fit$summary$theta_mean)
  theta_cov <- as.matrix(fit$summary$theta_cov)
  y_mean <- as.numeric(fit$summary$y_future_mean)
  y_cov <- as.matrix(fit$summary$y_future_cov)
  if (length(theta_mean) != p || !identical(dim(theta_cov), c(p, p)) ||
      length(y_mean) != H || !identical(dim(y_cov), c(H, H)) ||
      any(!is.finite(c(theta_mean, theta_cov, y_mean, y_cov)))) {
    stop("Part 4 dependency initializer is dimensionally incompatible with the target design.", call. = FALSE)
  }
  list(
    theta_mean = theta_mean,
    theta_cov = theta_cov,
    y_future_mean = y_mean,
    y_future_cov = y_cov,
    sigma_state = fit$variational_state$sigma %||% NULL,
    sigma_mean = fit$summary$sigma_mean %||% NULL,
    gamma = fit$summary$gamma_mean %||% NULL,
    provenance = list(
      type = "validated_dependency_fit",
      source_path = source_path,
      source_sha256 = if (is.character(source_path) && length(source_path) == 1L &&
        !is.na(source_path) && file.exists(source_path)) app_sha256_file(source_path) else NA_character_,
      state_contract_hash = app_glofas_part4_state_contract_hash(design)
    )
  )
}

app_glofas_part4_historical_initializer <- function(
    path,
    expected_sha256,
    design,
    source_design_hash = NA_character_) {
  path <- normalizePath(app_resolve_path(path, must_work = TRUE), mustWork = TRUE)
  expected_sha256 <- tolower(trimws(as.character(expected_sha256 %||% "")[[1L]]))
  if (!grepl("^[0-9a-f]{64}$", expected_sha256)) {
    stop("Part 4 historical initializer requires an explicit SHA256 digest.", call. = FALSE)
  }
  observed_sha256 <- tolower(app_sha256_file(path))
  if (!identical(observed_sha256, expected_sha256)) {
    stop("Part 4 historical initializer SHA256 mismatch.", call. = FALSE)
  }
  object <- readRDS(path)
  fit <- object$fit %||% object
  theta_mean <- as.numeric(fit$beta_mean %||% fit$summary$theta_mean %||% numeric())
  theta_cov <- fit$beta_cov %||% fit$summary$theta_cov %||% NULL
  if (is.null(theta_cov)) {
    variance <- as.numeric(fit$beta_var_diag %||% numeric())
    if (length(variance)) theta_cov <- diag(pmax(variance, 1.0e-12), length(variance))
  }
  theta_cov <- as.matrix(theta_cov %||% matrix(numeric(), 0L, 0L))
  p <- ncol(design$H_fixed)
  if (length(theta_mean) != p || !identical(dim(theta_cov), c(p, p)) ||
      any(!is.finite(c(theta_mean, theta_cov)))) {
    stop("Part 4 historical initializer is not coefficient-compatible with the latent-path design.", call. = FALSE)
  }
  coefficient_names <- names(fit$beta_mean %||% fit$summary$theta_mean %||% numeric())
  if (length(coefficient_names) && !identical(coefficient_names, colnames(design$H_fixed))) {
    stop("Part 4 historical initializer coefficient names do not match the latent-path design.", call. = FALSE)
  }
  horizon <- nrow(design$future_key)
  future_variance <- max(stats::var(design$z_fixed), 1.0e-3)
  list(
    theta_mean = theta_mean,
    theta_cov = (theta_cov + t(theta_cov)) / 2,
    y_future_mean = as.numeric(design$y_future_init),
    y_future_cov = diag(future_variance, horizon),
    provenance = list(
      type = "validated_part3_historical_coefficient_initializer",
      source_path = path,
      source_sha256 = observed_sha256,
      source_design_hash = as.character(source_design_hash %||% NA_character_),
      state_contract_hash = app_glofas_part4_state_contract_hash(design),
      transferred = "coefficient_mean_and_covariance",
      newly_initialized = "future_latent_path"
    )
  )
}

app_glofas_part4_root_initializer_from_manifest <- function(anchor_manifest, design) {
  if (!is.data.frame(anchor_manifest) || !nrow(anchor_manifest)) return(NULL)
  row <- app_glofas_part4_optional_anchor_row(anchor_manifest, "historical_joint_anchor")
  if (!nrow(row)) return(NULL)
  path <- as.character(app_glofas_part4_row_value(row, "fit_object_path", ""))
  sha <- as.character(app_glofas_part4_row_value(row, "fit_object_sha256", ""))
  if (!nzchar(path) && !nzchar(sha)) return(NULL)
  if (!nzchar(path) || !nzchar(sha)) {
    stop("Part 4 historical initializer path and SHA256 must be supplied together.", call. = FALSE)
  }
  app_glofas_part4_historical_initializer(
    path = path,
    expected_sha256 = sha,
    design = design,
    source_design_hash = app_glofas_part4_row_value(row, "design_hash", NA_character_)
  )
}

app_glofas_part4_empirical_crps <- function(y, draws) {
  x <- sort(as.numeric(draws[is.finite(draws)]))
  if (!is.finite(y) || !length(x)) return(NA_real_)
  n <- length(x)
  pair_term <- sum((2 * seq_len(n) - n - 1) * x) / n^2
  mean(abs(x - y)) - pair_term
}

app_glofas_part4_check_loss <- function(y, q, tau) {
  residual <- as.numeric(y) - as.numeric(q)
  residual * (as.numeric(tau) - (residual < 0))
}

app_glofas_part4_inverse_response <- function(x, inverse_response = "expm1") {
  inverse_response <- tolower(as.character(inverse_response %||% "expm1")[[1L]])
  switch(
    inverse_response,
    expm1 = expm1(x),
    identity = x,
    stop(sprintf("Unsupported Part 4 inverse response transform '%s'.", inverse_response), call. = FALSE)
  )
}

app_glofas_part4_score_prediction <- function(
    prediction,
    likelihood_family,
    inverse_response = "expm1") {
  draws <- prediction$draws
  summary <- prediction$summary
  dates <- sort(unique(as.Date(draws$target_date)))
  rows <- lapply(dates, function(date) {
    block <- draws[as.Date(draws$target_date) == date, , drop = FALSE]
    truth <- unique(as.numeric(block$y_reference[is.finite(block$y_reference)]))
    if (length(truth) != 1L) stop(sprintf("Scoring truth is missing or ambiguous on %s.", date), call. = FALSE)
    y <- truth[[1L]]
    tau <- unique(as.numeric(block$quantile_level))[[1L]]
    qhat <- mean(as.numeric(block$q_y_draw))
    latent <- as.numeric(block$latent_y_draw)
    normal <- identical(likelihood_family, "normal")
    y_original <- app_glofas_part4_inverse_response(y, inverse_response)
    qhat_original <- app_glofas_part4_inverse_response(qhat, inverse_response)
    latent_original <- app_glofas_part4_inverse_response(latent, inverse_response)
    data.frame(
      target_date = date,
      horizon = unique(as.integer(block$horizon))[[1L]],
      quantile_level = tau,
      likelihood_family = likelihood_family,
      y_reference = y,
      qhat = qhat,
      mae = abs(y - if (normal) mean(latent) else qhat),
      squared_error = (y - if (normal) mean(latent) else qhat)^2,
      check_loss = if (normal) NA_real_ else app_glofas_part4_check_loss(y, qhat, tau),
      empirical_crps = if (normal) app_glofas_part4_empirical_crps(y, latent) else NA_real_,
      y_reference_original = y_original,
      qhat_original = qhat_original,
      check_loss_original = if (normal) NA_real_ else app_glofas_part4_check_loss(y_original, qhat_original, tau),
      empirical_crps_original = if (normal) app_glofas_part4_empirical_crps(y_original, latent_original) else NA_real_,
      stringsAsFactors = FALSE
    )
  })
  by_horizon <- do.call(rbind, rows)
  mean_or_na <- function(x) if (any(is.finite(x))) mean(x[is.finite(x)]) else NA_real_
  summary_row <- data.frame(
    likelihood_family = likelihood_family,
    quantile_level = unique(by_horizon$quantile_level)[[1L]],
    n_horizons = nrow(by_horizon),
    mean_mae = mean(by_horizon$mae),
    rmse = sqrt(mean(by_horizon$squared_error)),
    mean_check_loss = mean_or_na(by_horizon$check_loss),
    mean_empirical_crps = mean_or_na(by_horizon$empirical_crps),
    mean_check_loss_original = mean_or_na(by_horizon$check_loss_original),
    mean_empirical_crps_original = mean_or_na(by_horizon$empirical_crps_original),
    stringsAsFactors = FALSE
  )
  list(by_horizon = by_horizon, summary = summary_row, prediction_summary = summary)
}

app_glofas_part4_quantile_grid_crps <- function(score_rows) {
  tau <- sort(unique(as.numeric(score_rows$quantile_level)))
  if (!identical(tau, app_glofas_part4_quantile_grid())) {
    stop("Part 4 quantile-grid CRPS requires the exact frozen seven-quantile grid.", call. = FALSE)
  }
  dates <- sort(unique(as.Date(score_rows$target_date)))
  per_date <- lapply(dates, function(date) {
    block <- score_rows[as.Date(score_rows$target_date) == date, , drop = FALSE]
    block <- block[order(block$quantile_level), , drop = FALSE]
    integrate <- function(loss) {
      2 * sum(diff(tau) * (head(loss, -1L) + tail(loss, -1L)) / 2)
    }
    data.frame(
      target_date = date,
      crps_grid = integrate(block$check_loss),
      crps_grid_original = integrate(block$check_loss_original),
      crossing_pairs = sum(diff(block$qhat) < 0),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, per_date)
  list(
    by_date = out,
    summary = data.frame(
      n_dates = nrow(out),
      mean_crps_grid = mean(out$crps_grid),
      mean_crps_grid_original = mean(out$crps_grid_original),
      raw_crossing_pairs = sum(out$crossing_pairs),
      crossing_fix_applied = FALSE,
      stringsAsFactors = FALSE
    )
  )
}

app_glofas_part4_atomic_save_rds <- function(x, path, compress = FALSE) {
  app_ensure_dir(dirname(path))
  tmp <- tempfile(paste0(basename(path), "."), tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(x, tmp, compress = compress)
  if (!file.rename(tmp, path)) stop(sprintf("Could not atomically publish %s.", path), call. = FALSE)
  normalizePath(path, mustWork = TRUE)
}

app_glofas_part4_result_from_core <- function(core_fit, design, model_row) {
  summary <- app_latent_path_design_summary(design)
  core_fit$warm_start_contract <- app_latent_path_warm_start_contract(
    design,
    design_hash = summary$design_hash[[1L]]
  )
  list(
    fit_id = model_row$fit_id[[1L]],
    model_id = model_row$model_id[[1L]],
    model_family = model_row$model_family[[1L]],
    quantile_level = as.numeric(model_row$quantile_level[[1L]]),
    method = "vb",
    likelihood_family = as.character(model_row$likelihood_family[[1L]]),
    coefficient_prior = app_map_qdesn_prior(model_row$coefficient_prior[[1L]]),
    fit = core_fit,
    design = design,
    design_summary = summary,
    state_contract_hash = app_glofas_part4_state_contract_hash(design),
    status = "completed"
  )
}

app_glofas_part4_fit_side_artifact <- function(result, design_path) {
  out <- result
  if (!is.null(out$design)) out$design <- NULL
  out$shared_design_reference <- list(
    path = normalizePath(design_path, mustWork = TRUE),
    sha256 = app_sha256_file(design_path),
    state_contract_hash = result$state_contract_hash %||%
      if (!is.null(result$design)) app_glofas_part4_state_contract_hash(result$design) else NA_character_,
    storage_contract = "single_shared_truth_free_design_not_duplicated_per_fit"
  )
  out
}

app_glofas_part4_vb_args_for_initializer <- function(vb_args, initializer = NULL) {
  if (!is.null(initializer)) {
    vb_args$initial_state <- initializer
  } else {
    vb_args$initial_state <- NULL
    vb_args$freeze_beta_warmup_iters <- 0L
  }
  vb_args
}

app_glofas_part4_fit_independent <- function(design, model_row, vb_args, initializer = NULL, seed = NULL) {
  likelihood <- tolower(as.character(model_row$likelihood_family[[1L]]))
  prior <- app_map_qdesn_prior(model_row$coefficient_prior[[1L]])
  tau <- as.numeric(model_row$quantile_level[[1L]])
  design <- app_glofas_part4_design_for_quantile(design, tau)
  vb_args <- app_glofas_part4_vb_args_for_initializer(vb_args, initializer)
  vb_args$likelihood_family <- likelihood
  fit <- if (identical(likelihood, "normal")) {
    app_fit_latent_path_normal_vb_core(design, prior, vb_args, seed = seed)
  } else if (identical(likelihood, "al")) {
    app_fit_latent_path_al_vb_core(design, tau, prior, vb_args, seed = seed)
  } else if (identical(likelihood, "exal")) {
    app_fit_latent_path_exal_vb_core(design, tau, prior, vb_args, seed = seed)
  } else {
    stop(sprintf("Unsupported independent Part 4 likelihood '%s'.", likelihood), call. = FALSE)
  }
  app_glofas_part4_result_from_core(fit, design, model_row)
}

app_glofas_part4_fit_joint <- function(design, model_rows, likelihood, independent_results, vb_args, seed = NULL) {
  tau <- as.numeric(model_rows$quantile_level)
  ord <- order(tau)
  tau <- tau[ord]
  model_rows <- model_rows[ord, , drop = FALSE]
  independent_results <- independent_results[ord]
  designs <- lapply(tau, function(q) app_glofas_part4_design_for_quantile(design, q))
  app_fit_latent_path_joint_vb_core(
    designs = designs,
    tau = tau,
    likelihood = likelihood,
    independent_fits = independent_results,
    vb_args = vb_args,
    seed = seed
  )
}

app_glofas_part4_coefficient_summary <- function(result) {
  fit <- app_glofas_part4_extract_fit(result)
  mean <- as.numeric(fit$summary$theta_mean)
  sd <- sqrt(pmax(diag(as.matrix(fit$summary$theta_cov)), 0))
  data.frame(
    coefficient = names(fit$summary$theta_mean) %||% colnames(result$design$H_fixed),
    mean = mean,
    sd = sd,
    lower_95 = mean - stats::qnorm(0.975) * sd,
    upper_95 = mean + stats::qnorm(0.975) * sd,
    stringsAsFactors = FALSE
  )
}

app_glofas_part4_artifact_manifest <- function(paths, root) {
  paths <- normalizePath(paths[file.exists(paths)], mustWork = TRUE)
  root <- normalizePath(root, mustWork = TRUE)
  data.frame(
    relative_path = substring(paths, nchar(root) + 2L),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
}
