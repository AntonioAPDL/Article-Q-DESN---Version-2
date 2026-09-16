# Quantile DESN evaluation along aligned external Normal-response trajectories.

.app_glofas_external_driver_env <- new.env(parent = emptyenv())

app_glofas_external_driver_load_cpp <- function(required = TRUE) {
  if (isTRUE(.app_glofas_external_driver_env$loaded %||% FALSE) &&
      exists("glofas_d1_external_driver_forecast_cpp", mode = "function")) return(TRUE)
  path <- app_path("application/src/glofas_external_driver_forecast.cpp")
  if (!file.exists(path) || !requireNamespace("Rcpp", quietly = TRUE)) {
    if (isTRUE(required)) stop("External Normal-driver C++ backend is unavailable.", call. = FALSE)
    return(FALSE)
  }
  ok <- tryCatch({
    Rcpp::sourceCpp(path, rebuild = FALSE, showOutput = FALSE, verbose = FALSE)
    TRUE
  }, error = function(e) {
    if (isTRUE(required)) stop(e)
    FALSE
  })
  .app_glofas_external_driver_env$loaded <- ok
  ok
}

app_glofas_quantile_covariance_block <- function(fit, tau_index, p, K) {
  blocks <- fit$beta_cov_blocks %||% NULL
  if (!is.null(blocks)) {
    if (length(blocks) != K) stop("Quantile covariance block count does not match tau.", call. = FALSE)
    out <- as.matrix(blocks[[tau_index]])
  } else if (!is.null(fit$beta_cov)) {
    full <- as.matrix(fit$beta_cov)
    idx <- ((tau_index - 1L) * p + 1L):(tau_index * p)
    if (nrow(full) != K * p || ncol(full) != K * p) stop("Dense quantile covariance dimensions are invalid.", call. = FALSE)
    out <- full[idx, idx, drop = FALSE]
  } else {
    stop("Quantile fit does not retain a full within-quantile coefficient covariance.", call. = FALSE)
  }
  if (!identical(dim(out), c(p, p)) || any(!is.finite(out))) {
    stop("Quantile coefficient covariance block is malformed.", call. = FALSE)
  }
  (out + t(out)) / 2
}

app_glofas_quantile_beta_draws <- function(fit, tau_index, tau, p, n_draws = 500L, seed = 1L) {
  tau <- as.numeric(tau)
  K <- length(tau)
  tau_index <- as.integer(tau_index)
  if (tau_index < 1L || tau_index > K) stop("tau_index is out of range.", call. = FALSE)
  parts <- app_glofas_part1_quantile_beta_matrix(fit, p, tau)
  covariance <- app_glofas_quantile_covariance_block(fit, tau_index, p, K)
  draws <- app_latent_mvn_draws_exact(
    parts$beta[, tau_index], covariance, as.integer(n_draws),
    seed = as.integer(seed), backend = "chol_eigen_fallback"
  )
  cbind(intercept = rep(parts$alpha[[tau_index]], as.integer(n_draws)), draws)
}

app_glofas_external_driver_advance_r <- function(context, state, row) {
  meta <- context$meta
  if (isTRUE(meta$standardize_inputs %||% FALSE)) {
    row <- (row - as.numeric(meta$lag_center)) / as.numeric(meta$lag_scale)
  }
  if (identical(as.character(meta$input_bound %||% "none"), "tanh")) row <- tanh(row)
  input <- c(
    as.numeric(meta$win_scale_bias %||% 1),
    as.numeric(meta$win_scale_global %||% 1) * row
  )
  activation <- as.character(context$reservoir$act_f %||% "tanh")
  pre <- as.numeric(context$reservoir$W[[1L]] %*% state + context$reservoir$Win[[1L]] %*% input)
  proposal <- if (identical(activation, "tanh")) {
    tanh(pre)
  } else if (identical(activation, "identity")) {
    pre
  } else {
    stop(sprintf("Unsupported external-driver activation '%s'.", activation), call. = FALSE)
  }
  alpha <- as.numeric(context$reservoir$alpha[[1L]])
  (1 - alpha) * state + alpha * proposal
}

app_glofas_external_driver_forecast_r <- function(context, driver_paths, beta_draws) {
  driver_paths <- as.matrix(driver_paths)
  beta_draws <- as.matrix(beta_draws)
  H <- nrow(driver_paths)
  S <- ncol(driver_paths)
  if (nrow(beta_draws) != S || ncol(beta_draws) != length(context$state0) + 1L) {
    stop("External-driver beta/path dimensions do not match.", call. = FALSE)
  }
  out <- matrix(NA_real_, H, S)
  input_sum <- matrix(0, H, ncol(context$compiled$static_values))
  for (s in seq_len(S)) {
    state <- context$state0
    for (h in seq_len(H)) {
      row <- context$compiled$static_values[h, ]
      idx <- which(context$compiled$future_index[h, ] > 0L)
      if (length(idx)) row[idx] <- driver_paths[context$compiled$future_index[h, idx], s]
      input_sum[h, ] <- input_sum[h, ] + row
      state <- app_glofas_external_driver_advance_r(context, state, row)
      out[h, s] <- sum(beta_draws[s, ] * c(1, state))
    }
  }
  list(quantile_paths = out, input_mean = input_sum / S, backend = "r_d1_external_normal_driver")
}

app_glofas_external_driver_forecast <- function(
  context,
  driver_paths,
  beta_draws,
  backend = c("auto", "cpp", "r")
) {
  backend <- match.arg(backend)
  driver_paths <- as.matrix(driver_paths)
  beta_draws <- as.matrix(beta_draws)
  beta_draws <- app_glofas_normal_readout_beta_draws_to_raw(
    beta_draws,
    context$readout_scaler %||% NULL
  )
  H <- nrow(context$compiled$static_values)
  if (nrow(driver_paths) != H || nrow(beta_draws) != ncol(driver_paths)) {
    stop("External Normal-driver forecast dimensions are inconsistent.", call. = FALSE)
  }
  use_cpp <- identical(backend, "cpp") ||
    (identical(backend, "auto") && app_glofas_external_driver_load_cpp(required = FALSE))
  if (identical(backend, "cpp")) app_glofas_external_driver_load_cpp(required = TRUE)
  if (!use_cpp) return(app_glofas_external_driver_forecast_r(context, driver_paths, beta_draws))
  reservoir <- context$reservoir
  meta <- context$meta
  compiled <- context$compiled
  out <- glofas_d1_external_driver_forecast_cpp(
    W = as.matrix(reservoir$W[[1L]]),
    Win = as.matrix(reservoir$Win[[1L]]),
    state0 = as.numeric(context$state0),
    static_values = as.matrix(compiled$static_values),
    future_index = matrix(as.integer(compiled$future_index), nrow = H),
    driver_paths = driver_paths,
    beta_draws = beta_draws,
    lag_center = as.numeric(meta$lag_center),
    lag_scale = as.numeric(meta$lag_scale),
    standardize_inputs = isTRUE(meta$standardize_inputs %||% FALSE),
    input_bound = as.character(meta$input_bound %||% "none"),
    win_scale_global = as.numeric(meta$win_scale_global %||% 1),
    win_scale_bias = as.numeric(meta$win_scale_bias %||% 1),
    alpha = as.numeric(reservoir$alpha[[1L]]),
    activation = as.character(reservoir$act_f %||% "tanh")
  )
  list(
    quantile_paths = as.matrix(out$quantile_paths),
    input_mean = as.matrix(out$input_mean),
    backend = as.character(out$backend)
  )
}

app_glofas_part1_external_driver_context <- function(fitted, future_dates, covariate_timeline = NULL) {
  design <- fitted$design
  qfit <- list(reservoir = design$reservoir, states = design$states, meta = design$design_meta)
  app_glofas_oracle_validate_forecastable_qfit(qfit)
  compiled <- app_glofas_oracle_compiled_future_inputs(
    qfit,
    future_dates = as.Date(future_dates),
    covariate_timeline = covariate_timeline %||% qfit$meta$covariate_timeline %||% NULL
  )
  app_glofas_oracle_validate_no_forbidden_sources(compiled$audit, "Part 1 external Normal-driver audit")
  list(
    component = "usgs",
    state0 = as.numeric(app_qdesn_last_states(qfit)[[1L]]),
    reservoir = design$reservoir,
    meta = qfit$meta,
    compiled = compiled,
    readout_scaler = design$readout_scaler %||% NULL,
    audit = compiled$audit
  )
}

app_glofas_external_driver_summary <- function(paths, future_dates, tau, component, backend) {
  paths <- as.matrix(paths)
  data.frame(
    target_date = as.Date(future_dates),
    horizon = seq_len(nrow(paths)),
    tau = as.numeric(tau),
    component = as.character(component),
    qhat = rowMeans(paths),
    qhat_median = apply(paths, 1L, stats::median),
    qhat_sd = apply(paths, 1L, stats::sd),
    qhat_q025 = apply(paths, 1L, stats::quantile, probs = 0.025, names = FALSE, type = 8),
    qhat_q975 = apply(paths, 1L, stats::quantile, probs = 0.975, names = FALSE, type = 8),
    forecast_backend = as.character(backend),
    driver_model = "normal_rhs",
    stringsAsFactors = FALSE
  )
}

app_glofas_part1_quantile_external_driver_forecast <- function(
  fitted,
  fit,
  tau,
  driver_bank,
  covariate_timeline = NULL,
  n_draws = 500L,
  seed = 20260916L,
  backend = c("auto", "cpp", "r")
) {
  backend <- match.arg(backend)
  tau <- as.numeric(tau)
  future_dates <- as.Date(driver_bank$contract$future_dates)
  app_validate_glofas_normal_driver_bank(
    driver_bank, "usgs", expected_paths = n_draws, expected_dates = future_dates
  )
  context <- app_glofas_part1_external_driver_context(fitted, future_dates, covariate_timeline)
  rows <- paths <- vector("list", length(tau))
  for (kk in seq_along(tau)) {
    beta <- app_glofas_quantile_beta_draws(
      fit, kk, tau, ncol(fitted$Z), n_draws = n_draws, seed = as.integer(seed) + kk - 1L
    )
    one <- app_glofas_external_driver_forecast(
      context, driver_bank$components$usgs, beta, backend = backend
    )
    paths[[kk]] <- one$quantile_paths
    rows[[kk]] <- app_glofas_external_driver_summary(
      one$quantile_paths, future_dates, tau[[kk]], "usgs", one$backend
    )
  }
  names(paths) <- app_glofas_part1_quantile_slug(tau)
  list(
    forecast = app_bind_rows_fill(rows),
    quantile_paths = paths,
    driver_contract = driver_bank$contract,
    future_input_audit = context$audit,
    forecast_mode = "normal_rhs_external_driver",
    n_paths = as.integer(n_draws),
    seed = as.integer(seed)
  )
}

app_glofas_part2_quantile_external_driver_forecast <- function(
  fitted,
  fit,
  tau,
  driver_bank,
  future_glofas = NULL,
  covariate_timeline = NULL,
  n_draws = 500L,
  seed = 20260916L,
  backend = c("auto", "cpp", "r")
) {
  backend <- match.arg(backend)
  tau <- as.numeric(tau)
  future_dates <- as.Date(driver_bank$contract$future_dates)
  app_validate_glofas_normal_driver_bank(
    driver_bank, "discrepancy", expected_paths = n_draws, expected_dates = future_dates
  )
  context <- app_glofas_part1_external_driver_context(fitted, future_dates, covariate_timeline)
  context$component <- "discrepancy"
  paths <- vector("list", length(tau))
  rows <- vector("list", length(tau))
  for (kk in seq_along(tau)) {
    beta <- app_glofas_quantile_beta_draws(
      fit, kk, tau, ncol(fitted$Z), n_draws = n_draws, seed = as.integer(seed) + kk - 1L
    )
    one <- app_glofas_external_driver_forecast(
      context, driver_bank$components$discrepancy, beta, backend = backend
    )
    paths[[kk]] <- one$quantile_paths
    rows[[kk]] <- app_glofas_external_driver_summary(
      one$quantile_paths, future_dates, tau[[kk]], "discrepancy", one$backend
    )
  }
  names(paths) <- app_glofas_part1_quantile_slug(tau)
  reversed <- match(1 - tau, tau)
  if (anyNA(reversed) || any(abs(tau[reversed] - (1 - tau)) > 1.0e-12)) {
    stop("Part 2 USGS quantiles require an exactly symmetric discrepancy grid.", call. = FALSE)
  }
  usgs_paths <- NULL
  usgs_rows <- list()
  corrected_status <- "unavailable_without_future_glofas_reference"
  if (!is.null(future_glofas)) {
    future_glofas <- as.numeric(future_glofas)
    if (length(future_glofas) != length(future_dates) || any(!is.finite(future_glofas))) {
      stop("Part 2 fixed future GloFAS path is not aligned with the driver horizon.", call. = FALSE)
    }
    usgs_paths <- lapply(reversed, function(index) future_glofas - paths[[index]])
    usgs_rows <- lapply(seq_along(tau), function(kk) {
      app_glofas_external_driver_summary(
        usgs_paths[[kk]], future_dates, tau[[kk]], "corrected_usgs",
        "normal_rhs_external_discrepancy_driver"
      )
    })
    names(usgs_paths) <- names(paths)
    corrected_status <- "available_from_declared_fixed_future_glofas_reference"
  }
  list(
    discrepancy_forecast = app_bind_rows_fill(rows),
    corrected_usgs_forecast = if (length(usgs_rows)) app_bind_rows_fill(usgs_rows) else data.frame(),
    discrepancy_quantile_paths = paths,
    corrected_usgs_quantile_paths = usgs_paths,
    quantile_reversal_index = reversed,
    corrected_usgs_status = corrected_status,
    driver_contract = driver_bank$contract,
    future_input_audit = context$audit,
    forecast_mode = "normal_rhs_external_driver",
    n_paths = as.integer(n_draws),
    seed = as.integer(seed)
  )
}

app_glofas_part3_component_beta_draws <- function(
  fit, component, tau_index, n_draws = 500L, seed = 1L
) {
  component <- match.arg(component, c("reference", "discrepancy"))
  mean_name <- paste0("beta_", component, "_mean")
  cov_name <- paste0("beta_", component, "_cov_blocks")
  means <- as.matrix(fit[[mean_name]])
  blocks <- fit[[cov_name]] %||% NULL
  if (is.null(blocks) || length(blocks) != ncol(means)) {
    stop(sprintf("Part 3 %s fit lacks full coefficient covariance blocks.", component), call. = FALSE)
  }
  app_latent_mvn_draws_exact(
    means[, tau_index], as.matrix(blocks[[tau_index]]), as.integer(n_draws),
    seed = as.integer(seed), backend = "chol_eigen_fallback"
  )
}

app_glofas_part3_quantile_external_driver_forecast <- function(
  design,
  fit,
  driver_bank,
  origin_date,
  n_draws = 500L,
  seed = 20260916L,
  backend = c("auto", "cpp", "r")
) {
  backend <- match.arg(backend)
  tau <- as.numeric(fit$tau)
  dates <- as.Date(driver_bank$contract$future_dates)
  app_validate_glofas_normal_driver_bank(
    driver_bank, c("usgs", "discrepancy", "glofas"), n_draws, dates
  )
  origin <- app_glofas_part3_forecast_origin(
    design, horizon_days = length(dates), origin_date = origin_date,
    allow_missing_future_indices = TRUE
  )
  if (!identical(origin$future_dates, dates)) stop("Part 3 driver dates do not match the requested origin.", call. = FALSE)
  reference <- app_glofas_part3_component_context(design, "reference", origin)
  discrepancy <- app_glofas_part3_component_context(design, "discrepancy", origin)
  ref_paths <- disc_paths <- glofas_paths <- vector("list", length(tau))
  rows <- list()
  for (kk in seq_along(tau)) {
    beta_ref <- app_glofas_part3_component_beta_draws(
      fit, "reference", kk, n_draws, as.integer(seed) + 2L * kk - 2L
    )
    beta_disc <- app_glofas_part3_component_beta_draws(
      fit, "discrepancy", kk, n_draws, as.integer(seed) + 2L * kk - 1L
    )
    ref <- app_glofas_external_driver_forecast(
      reference, driver_bank$components$usgs, beta_ref, backend
    )
    disc <- app_glofas_external_driver_forecast(
      discrepancy, driver_bank$components$discrepancy, beta_disc, backend
    )
    ref_paths[[kk]] <- ref$quantile_paths
    disc_paths[[kk]] <- disc$quantile_paths
    glofas_paths[[kk]] <- ref$quantile_paths + disc$quantile_paths
    rows[[length(rows) + 1L]] <- app_glofas_external_driver_summary(
      ref_paths[[kk]], dates, tau[[kk]], "usgs", ref$backend
    )
    rows[[length(rows) + 1L]] <- app_glofas_external_driver_summary(
      disc_paths[[kk]], dates, tau[[kk]], "discrepancy", disc$backend
    )
    rows[[length(rows) + 1L]] <- app_glofas_external_driver_summary(
      glofas_paths[[kk]], dates, tau[[kk]], "glofas", paste(ref$backend, disc$backend, sep = "+")
    )
  }
  names(ref_paths) <- names(disc_paths) <- names(glofas_paths) <- app_glofas_part1_quantile_slug(tau)
  list(
    forecast = app_bind_rows_fill(rows),
    quantile_paths = list(usgs = ref_paths, discrepancy = disc_paths, glofas = glofas_paths),
    driver_contract = driver_bank$contract,
    reference_input_audit = reference$audit,
    discrepancy_input_audit = discrepancy$audit,
    forecast_mode = "matched_part3_normal_rhs_external_driver",
    n_paths = as.integer(n_draws),
    seed = as.integer(seed)
  )
}
