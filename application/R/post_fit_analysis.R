# Post-fit analysis for the GloFAS discrepancy-calibration application.

app_post_analysis_defaults <- function() {
  list(
    enabled = FALSE,
    run_after_outputs = FALSE,
    trace_skip = 5L,
    credible_level = 0.95,
    recent_history_n = 200L,
    discrepancy_history_since = "2020-01-01",
    history_chunk_size = 500L,
    forecast_window = list(before_days = 30L, after_days = 30L),
    coefficient_forest = list(top_k = 50L),
    storage = list(write_history_draws_rds = FALSE, write_history_draws_csv = FALSE)
  )
}

app_merge_named_lists <- function(defaults, user) {
  out <- defaults
  if (is.null(user)) return(out)
  for (nm in names(user)) {
    if (is.list(out[[nm]]) && is.list(user[[nm]])) {
      out[[nm]] <- app_merge_named_lists(out[[nm]], user[[nm]])
    } else {
      out[[nm]] <- user[[nm]]
    }
  }
  out
}

app_parse_optional_date <- function(x) {
  if (is.null(x) || !length(x)) return(NULL)
  x <- as.character(x[[1L]])
  x <- trimws(x)
  if (is.na(x) || !nzchar(x) || identical(tolower(x), "null")) return(NULL)
  as.Date(x)
}

app_post_date_slug <- function(date) {
  if (is.null(date) || is.na(date)) return(NA_character_)
  if (identical(format(date, "%m-%d"), "01-01")) {
    format(date, "%Y")
  } else {
    gsub("-", "", as.character(date), fixed = TRUE)
  }
}

app_post_analysis_config <- function(cfg) {
  pcfg <- app_merge_named_lists(app_post_analysis_defaults(), cfg$post_analysis %||% list())
  pcfg$trace_skip <- as.integer(pcfg$trace_skip %||% 5L)
  pcfg$credible_level <- as.numeric(pcfg$credible_level %||% 0.95)
  pcfg$recent_history_n <- as.integer(pcfg$recent_history_n %||% 200L)
  pcfg$discrepancy_history_since <- app_parse_optional_date(pcfg$discrepancy_history_since %||% "2020-01-01")
  pcfg$history_chunk_size <- as.integer(pcfg$history_chunk_size %||% 500L)
  pcfg$forecast_window$before_days <- as.integer(pcfg$forecast_window$before_days %||% 30L)
  pcfg$forecast_window$after_days <- as.integer(pcfg$forecast_window$after_days %||% 30L)
  pcfg$coefficient_forest$top_k <- as.integer(pcfg$coefficient_forest$top_k %||% 50L)
  pcfg$storage$write_history_draws_rds <- app_as_bool(pcfg$storage$write_history_draws_rds %||% FALSE)
  pcfg$storage$write_history_draws_csv <- app_as_bool(pcfg$storage$write_history_draws_csv %||% FALSE)
  pcfg
}

app_ci_probs <- function(level) {
  alpha <- 1 - as.numeric(level)
  c(alpha / 2, 0.5, 1 - alpha / 2)
}

app_summary_stats <- function(x, level = 0.95) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (!length(x)) return(c(mean = NA_real_, lo = NA_real_, median = NA_real_, hi = NA_real_, sd = NA_real_))
  qs <- stats::quantile(x, app_ci_probs(level), na.rm = TRUE, names = FALSE)
  c(mean = mean(x), lo = qs[[1L]], median = qs[[2L]], hi = qs[[3L]], sd = stats::sd(x))
}

app_column_summary <- function(x, prefix, level = 0.95) {
  x <- as.matrix(x)
  probs <- app_ci_probs(level)
  data.frame(
    setNames(list(as.numeric(colMeans(x, na.rm = TRUE))), paste0(prefix, "_mean")),
    setNames(list(as.numeric(apply(x, 2L, stats::quantile, probs = probs[[1L]], na.rm = TRUE, names = FALSE))), paste0(prefix, "_lo")),
    setNames(list(as.numeric(apply(x, 2L, stats::quantile, probs = probs[[2L]], na.rm = TRUE, names = FALSE))), paste0(prefix, "_median")),
    setNames(list(as.numeric(apply(x, 2L, stats::quantile, probs = probs[[3L]], na.rm = TRUE, names = FALSE))), paste0(prefix, "_hi")),
    check.names = FALSE
  )
}

app_summary_row <- function(x, prefix, level = 0.95) {
  s <- app_summary_stats(x, level)
  data.frame(
    setNames(list(s[["mean"]]), paste0(prefix, "_mean")),
    setNames(list(s[["lo"]]), paste0(prefix, "_lo")),
    setNames(list(s[["median"]]), paste0(prefix, "_median")),
    setNames(list(s[["hi"]]), paste0(prefix, "_hi")),
    check.names = FALSE
  )
}

app_fit_row_value <- function(fit_row, name, default = NA) {
  if (!name %in% names(fit_row) || !length(fit_row[[name]])) return(default)
  value <- fit_row[[name]][[1L]]
  if (is.null(value) || length(value) == 0L) default else value
}

app_discrepancy_gamma_draws <- function(fit) {
  gamma <- fit$draws$gamma %||% fit$samp.gamma %||% NULL
  if (is.null(gamma)) return(NULL)
  gamma <- as.matrix(gamma)
  storage.mode(gamma) <- "double"
  if (!nrow(gamma) || !ncol(gamma) || any(!is.finite(gamma))) {
    stop("Discrepancy posterior gamma draws must be a finite numeric matrix.", call. = FALSE)
  }
  gamma
}

app_named_source_columns <- function(x, prefix) {
  if (is.null(x)) return(x)
  x <- as.matrix(x)
  if (is.null(colnames(x))) {
    if (ncol(x) == 2L) {
      colnames(x) <- paste0(prefix, c("_Y", "_G"))
    } else {
      colnames(x) <- paste0(prefix, "_", seq_len(ncol(x)))
    }
  }
  x
}

app_post_fit_draw_bundle <- function(fit, design, meta = list()) {
  theta <- app_discrepancy_theta_draws(fit)
  max_idx <- max(c(design$beta_index, design$alpha_index))
  if (ncol(theta) < max_idx) stop("Post-fit theta draws are incompatible with design indices.", call. = FALSE)
  beta <- theta[, design$beta_index, drop = FALSE]
  alpha <- theta[, design$alpha_index, drop = FALSE]
  colnames(beta) <- app_discrepancy_beta_feature_names(design)
  colnames(alpha) <- app_discrepancy_alpha_feature_names(design)

  sigma <- app_named_source_columns(app_discrepancy_sigma_draws(fit), "sigma")
  gamma <- app_named_source_columns(app_discrepancy_gamma_draws(fit), "gamma")
  likelihood <- tolower(as.character(meta$likelihood_family %||% fit$likelihood_family %||% "unknown"))
  gamma_active <- identical(likelihood, "exal") && !is.null(gamma) && any(apply(gamma, 2L, stats::sd) > 0)

  list(
    theta = theta,
    beta = beta,
    alpha = alpha,
    sigma = sigma,
    gamma = gamma,
    gamma_active = gamma_active,
    likelihood_family = likelihood,
    method = tolower(as.character(meta$method %||% fit$method %||% "unknown"))
  )
}

app_post_fit_history_summary <- function(bundle, design, fit_row, pcfg) {
  X_beta <- app_discrepancy_beta_matrix(design)
  X_alpha <- app_discrepancy_alpha_matrix(design)
  beta <- bundle$beta
  alpha <- bundle$alpha
  if (ncol(X_beta) != ncol(beta) || ncol(X_alpha) != ncol(alpha)) {
    stop("History design matrix is incompatible with posterior coefficient draws.", call. = FALSE)
  }
  chunk_size <- max(25L, as.integer(pcfg$history_chunk_size %||% 500L))
  starts <- seq.int(1L, nrow(X_beta), by = chunk_size)
  out <- vector("list", length(starts))
  base <- design$base_panel
  base$target_date <- as.Date(base$target_date)
  for (i in seq_along(starts)) {
    idx <- starts[[i]]:min(nrow(X_beta), starts[[i]] + chunk_size - 1L)
    X_beta_i <- X_beta[idx, , drop = FALSE]
    X_alpha_i <- X_alpha[idx, , drop = FALSE]
    q_y <- beta %*% t(X_beta_i)
    d_g <- alpha %*% t(X_alpha_i)
    q_g <- q_y + d_g
    block <- data.frame(
      fit_id = app_fit_row_value(fit_row, "fit_id"),
      model_id = app_fit_row_value(fit_row, "model_id"),
      model_family = app_fit_row_value(fit_row, "model_family", "qdesn_glofas_discrepancy"),
      quantile_level = as.numeric(app_fit_row_value(fit_row, "quantile_level")),
      target_date = base$target_date[idx],
      origin_date = as.Date(base$origin_date[idx]),
      horizon = as.integer(base$horizon[idx]),
      y_reference = as.numeric(base$y_transformed[idx]),
      glofas_retrospective = as.numeric(base$g_transformed[idx]),
      observed_discrepancy = as.numeric(base$g_transformed[idx] - base$y_transformed[idx]),
      stringsAsFactors = FALSE
    )
    out[[i]] <- cbind(
      block,
      app_column_summary(q_y, "q_y", pcfg$credible_level),
      app_column_summary(q_g, "q_g", pcfg$credible_level),
      app_column_summary(d_g, "d_g", pcfg$credible_level)
    )
  }
  ans <- do.call(rbind, out)
  ans[order(ans$target_date), , drop = FALSE]
}

app_post_fit_recent_history <- function(history, n_recent = 200L) {
  history <- history[order(history$target_date), , drop = FALSE]
  n_recent <- min(as.integer(n_recent), nrow(history))
  if (!n_recent) return(history[FALSE, , drop = FALSE])
  history[(nrow(history) - n_recent + 1L):nrow(history), , drop = FALSE]
}

app_post_fit_since_history <- function(history, start_date) {
  if (is.null(start_date) || is.na(start_date)) return(history)
  history <- history[order(history$target_date), , drop = FALSE]
  history[as.Date(history$target_date) >= as.Date(start_date), , drop = FALSE]
}

app_post_fit_forecast_summary <- function(draws, pcfg) {
  app_validate_posterior_draw_prediction_table(draws)
  draws$origin_date <- as.Date(draws$origin_date)
  draws$target_date <- as.Date(draws$target_date)
  draws$horizon <- as.integer(draws$horizon)
  draws$quantile_level <- as.numeric(draws$quantile_level)
  key_cols <- c(
    "fit_id", "model_id", "model_family", "quantile_level", "origin_date",
    "target_date", "horizon", "discrepancy_feature_date", "prediction_contract",
    "contract_version", "forecast_scope", "q_g_source", "discrepancy_feature_strategy",
    "prediction_unit", "posterior_draw_contract", "posterior_predictive_sampling",
    "beyond_issued_horizon"
  )
  key <- interaction(draws[, key_cols, drop = FALSE], drop = TRUE)
  rows <- lapply(split(seq_len(nrow(draws)), key), function(idx) {
    block <- draws[idx, , drop = FALSE]
    base <- block[1L, key_cols, drop = FALSE]
    base$discrepancy_feature_date <- as.Date(base$discrepancy_feature_date)
    out <- data.frame(
      base,
      raw_glofas_quantile = mean(as.numeric(block$raw_glofas_quantile), na.rm = TRUE),
      y_reference = mean(as.numeric(block$y_reference), na.rm = TRUE),
      stringsAsFactors = FALSE
    )
    cbind(
      out,
      app_summary_row(block$q_y_draw, "q_y", pcfg$credible_level),
      app_summary_row(block$q_g_draw, "q_g", pcfg$credible_level),
      app_summary_row(block$d_g_draw, "d_g", pcfg$credible_level)
    )
  })
  out <- do.call(rbind, rows)
  out[order(out$origin_date, out$target_date, out$horizon), , drop = FALSE]
}

app_post_forecast_window_band_check <- function(history, forecast, pcfg) {
  origin <- min(as.Date(forecast$origin_date), na.rm = TRUE)
  window_start <- origin - as.integer(pcfg$forecast_window$before_days)
  window_end <- origin + as.integer(pcfg$forecast_window$after_days)
  hist <- history[history$target_date >= window_start & history$target_date <= origin, , drop = FALSE]
  fc <- forecast[forecast$target_date > origin & forecast$target_date <= window_end, , drop = FALSE]
  count_band <- function(x) {
    if (!nrow(x)) return(0L)
    sum(is.finite(x$q_y_lo) & is.finite(x$q_y_hi) & x$q_y_lo <= x$q_y_hi)
  }
  n_hist_band <- count_band(hist)
  n_fc_band <- count_band(fc)
  data.frame(
    fit_id = forecast$fit_id[[1L]],
    model_id = forecast$model_id[[1L]],
    quantile_level = as.numeric(forecast$quantile_level[[1L]]),
    origin_date = origin,
    window_start = window_start,
    window_end = window_end,
    credible_level = as.numeric(pcfg$credible_level),
    n_history_window_rows = nrow(hist),
    n_history_band_rows = n_hist_band,
    history_band_ok = n_hist_band >= 2L,
    n_forecast_window_rows = nrow(fc),
    n_forecast_band_rows = n_fc_band,
    forecast_band_ok = n_fc_band >= 2L,
    stringsAsFactors = FALSE
  )
}

app_post_fit_parameter_summary <- function(bundle, fit_row, pcfg) {
  rows <- list()
  k <- 1L
  add_matrix <- function(mat, family) {
    if (is.null(mat)) return()
    for (j in seq_len(ncol(mat))) {
      s <- app_summary_stats(mat[, j], pcfg$credible_level)
      rows[[k]] <<- data.frame(
        fit_id = fit_row$fit_id,
        model_id = fit_row$model_id,
        quantile_level = as.numeric(fit_row$quantile_level),
        method = app_fit_row_value(fit_row, "method"),
        likelihood_family = app_fit_row_value(fit_row, "likelihood_family"),
        parameter_family = family,
        parameter = colnames(mat)[[j]],
        mean = s[["mean"]],
        lo = s[["lo"]],
        median = s[["median"]],
        hi = s[["hi"]],
        sd = s[["sd"]],
        stringsAsFactors = FALSE
      )
      k <<- k + 1L
    }
  }
  add_matrix(bundle$sigma, "scale")
  if (isTRUE(bundle$gamma_active)) add_matrix(bundle$gamma, "asymmetry")
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

app_post_fit_trace_table <- function(fit, bundle, fit_row) {
  rows <- list()
  k <- 1L
  add_trace <- function(trace_name, values, source = "vb_diagnostic") {
    values <- as.numeric(values)
    if (!length(values) || all(!is.finite(values))) return()
    rows[[k]] <<- data.frame(
      fit_id = fit_row$fit_id,
      model_id = fit_row$model_id,
      quantile_level = as.numeric(fit_row$quantile_level),
      method = app_fit_row_value(fit_row, "method"),
      likelihood_family = app_fit_row_value(fit_row, "likelihood_family"),
      trace_source = source,
      trace_name = trace_name,
      iteration = seq_along(values),
      value = values,
      stringsAsFactors = FALSE
    )
    k <<- k + 1L
  }
  method <- tolower(as.character(app_fit_row_value(fit_row, "method")))
  if (identical(method, "vb")) {
    diag <- fit$diagnostics %||% fit$vb_diagnostics %||% list()
    add_trace("elbo", diag$elbo_trace %||% numeric(), "vb_diagnostic")
    add_trace("relative_change", diag$relative_change_trace %||% numeric(), "vb_diagnostic")
    add_trace("max_parameter_change", diag$max_parameter_change_trace %||% numeric(), "vb_diagnostic")
  } else if (identical(method, "mcmc")) {
    if (!is.null(bundle$sigma)) {
      for (j in seq_len(ncol(bundle$sigma))) add_trace(colnames(bundle$sigma)[[j]], bundle$sigma[, j], "mcmc_draw")
    }
    if (isTRUE(bundle$gamma_active) && !is.null(bundle$gamma)) {
      for (j in seq_len(ncol(bundle$gamma))) add_trace(colnames(bundle$gamma)[[j]], bundle$gamma[, j], "mcmc_draw")
    }
  }
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

app_post_fit_rhs_summary <- function(fit, fit_row) {
  state <- fit$beta_prior$state %||% NULL
  if (!is.list(state)) return(data.frame())
  scalar <- function(x) if (length(x) && is.finite(as.numeric(x[[1L]]))) as.numeric(x[[1L]]) else NA_real_
  data.frame(
    fit_id = fit_row$fit_id,
    model_id = fit_row$model_id,
    quantile_level = as.numeric(fit_row$quantile_level),
    method = app_fit_row_value(fit_row, "method"),
    likelihood_family = app_fit_row_value(fit_row, "likelihood_family"),
    tau2 = scalar(state$tau2),
    zeta2 = scalar(state$zeta2),
    E_inv_tau2 = scalar(state$E_inv_tau2),
    E_inv_zeta2 = scalar(state$E_inv_zeta2),
    lambda2_min = if (!is.null(state$lambda2)) min(state$lambda2, na.rm = TRUE) else NA_real_,
    lambda2_median = if (!is.null(state$lambda2)) stats::median(state$lambda2, na.rm = TRUE) else NA_real_,
    lambda2_max = if (!is.null(state$lambda2)) max(state$lambda2, na.rm = TRUE) else NA_real_,
    iter = if (length(state$iter)) as.integer(state$iter[[1L]]) else NA_integer_,
    stringsAsFactors = FALSE
  )
}

app_post_fit_metrics <- function(predictions, cfg) {
  pred_mono <- app_synthesize_quantile_grid(predictions)
  scored <- app_score_quantile_predictions_dual(pred_mono, cfg)
  eval_qhat <- if ("qhat_monotone" %in% names(scored)) scored$qhat_monotone else scored$qhat
  scored$error <- scored$y_reference - eval_qhat
  scored$absolute_error <- abs(scored$error)
  scored$squared_error <- scored$error^2
  scored$bias_error <- eval_qhat - scored$y_reference
  intervals <- app_score_intervals(scored, cfg)
  crps <- app_score_crps_grid(scored)
  key <- c("model_id", "model_family")
  model_rows <- lapply(split(scored, interaction(scored[, key], drop = TRUE)), function(block) {
    q_levels <- sort(unique(as.numeric(block$quantile_level)))
    data.frame(
      model_id = block$model_id[[1L]],
      model_family = block$model_family[[1L]],
      n_quantile_levels = length(q_levels),
      quantile_levels = paste(format(q_levels, trim = TRUE), collapse = ";"),
      n = sum(is.finite(block$check_loss)),
      check_loss_mean = mean(block$check_loss, na.rm = TRUE),
      mae_to_observation = mean(block$absolute_error, na.rm = TRUE),
      rmse_to_observation = sqrt(mean(block$squared_error, na.rm = TRUE)),
      bias_to_observation = mean(block$bias_error, na.rm = TRUE),
      interval_score_mean = NA_real_,
      interval_coverage_mean = NA_real_,
      crps_quantile_grid_mean = NA_real_,
      stringsAsFactors = FALSE
    )
  })
  by_model <- do.call(rbind, model_rows)
  if (nrow(intervals)) {
    i_summary <- aggregate(cbind(interval_score, covered) ~ model_id, intervals, mean, na.rm = TRUE)
    for (i in seq_len(nrow(i_summary))) {
      idx <- by_model$model_id == i_summary$model_id[[i]]
      by_model$interval_score_mean[idx] <- i_summary$interval_score[[i]]
      by_model$interval_coverage_mean[idx] <- i_summary$covered[[i]]
    }
  }
  if (nrow(crps) && any(is.finite(crps$crps_quantile_grid))) {
    c_summary <- aggregate(crps_quantile_grid ~ model_id, crps, mean, na.rm = TRUE)
    for (i in seq_len(nrow(c_summary))) {
      idx <- by_model$model_id == c_summary$model_id[[i]]
      value <- c_summary$crps_quantile_grid[[i]]
      by_model$crps_quantile_grid_mean[idx] <- if (is.nan(value)) NA_real_ else value
    }
  }
  horizon_rows <- lapply(split(scored, interaction(scored$model_id, scored$horizon, drop = TRUE)), function(block) {
    q_levels <- sort(unique(as.numeric(block$quantile_level)))
    data.frame(
      model_id = block$model_id[[1L]],
      model_family = block$model_family[[1L]],
      n_quantile_levels = length(q_levels),
      quantile_levels = paste(format(q_levels, trim = TRUE), collapse = ";"),
      horizon = as.integer(block$horizon[[1L]]),
      n = sum(is.finite(block$check_loss)),
      check_loss_mean = mean(block$check_loss, na.rm = TRUE),
      mae_to_observation = mean(block$absolute_error, na.rm = TRUE),
      rmse_to_observation = sqrt(mean(block$squared_error, na.rm = TRUE)),
      bias_to_observation = mean(block$bias_error, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  list(
    scored_predictions = scored,
    intervals = intervals,
    crps = crps,
    by_model = by_model[order(by_model$model_id), , drop = FALSE],
    by_horizon = do.call(rbind, horizon_rows)
  )
}

app_post_safe_range <- function(...) {
  x <- unlist(list(...), use.names = FALSE)
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (!length(x)) return(c(0, 1))
  r <- range(x)
  if (diff(r) <= 0) r <- r + c(-0.5, 0.5)
  r + c(-0.05, 0.05) * diff(r)
}

app_post_pdf_plot <- function(path, width = 8, height = 4.8, expr) {
  app_ensure_dir(dirname(path))
  grDevices::pdf(path, width = width, height = height)
  on.exit(grDevices::dev.off(), add = TRUE)
  force(expr)
  invisible(path)
}

app_plot_band <- function(x, lo, hi, col) {
  ok <- is.finite(lo) & is.finite(hi) & !is.na(x)
  if (sum(ok) < 2L) return(invisible(FALSE))
  polygon(c(x[ok], rev(x[ok])), c(lo[ok], rev(hi[ok])), border = NA, col = col)
  invisible(TRUE)
}

app_post_plot_history_quantile <- function(summary, path, title, level_label = "p") {
  summary <- summary[order(summary$target_date), , drop = FALSE]
  app_post_pdf_plot(path, 8.5, 4.8, {
    yr <- app_post_safe_range(summary$y_reference, summary$q_y_lo, summary$q_y_hi, summary$q_y_median)
    plot(summary$target_date, summary$y_reference, type = "n", ylim = yr,
      xlab = "Date", ylab = "Transformed streamflow", main = title)
    grid(col = "gray90")
    app_plot_band(summary$target_date, summary$q_y_lo, summary$q_y_hi, grDevices::adjustcolor("#2f6f9f", 0.18))
    lines(summary$target_date, summary$q_y_median, col = "#2f6f9f", lwd = 1.8)
    lines(summary$target_date, summary$y_reference, col = "#111111", lwd = 1.0)
    legend("topleft",
      legend = c(sprintf("Q-DESN %s posterior median", level_label), "95% posterior interval", "USGS"),
      col = c("#2f6f9f", grDevices::adjustcolor("#2f6f9f", 0.35), "#111111"),
      lty = c(1, NA, 1), lwd = c(1.8, NA, 1), pch = c(NA, 15, NA), bty = "n", cex = 0.78
    )
  })
}

app_post_plot_discrepancy <- function(summary, path, title) {
  summary <- summary[order(summary$target_date), , drop = FALSE]
  app_post_pdf_plot(path, 8.5, 4.8, {
    yr <- app_post_safe_range(summary$observed_discrepancy, summary$d_g_lo, summary$d_g_hi, summary$d_g_median)
    plot(summary$target_date, summary$observed_discrepancy, type = "n", ylim = yr,
      xlab = "Date", ylab = "Transformed discrepancy", main = title)
    grid(col = "gray90")
    abline(h = 0, lty = 2, col = "gray60")
    app_plot_band(summary$target_date, summary$d_g_lo, summary$d_g_hi, grDevices::adjustcolor("#8f3d56", 0.18))
    lines(summary$target_date, summary$d_g_median, col = "#8f3d56", lwd = 1.8)
    lines(summary$target_date, summary$observed_discrepancy, col = "#111111", lwd = 1.0)
    legend("topleft",
      legend = c("Fitted discrepancy posterior median", "95% posterior interval", "Observed GloFAS - USGS"),
      col = c("#8f3d56", grDevices::adjustcolor("#8f3d56", 0.35), "#111111"),
      lty = c(1, NA, 1), lwd = c(1.8, NA, 1), pch = c(NA, 15, NA), bty = "n", cex = 0.78
    )
  })
}

app_post_plot_forecast_window <- function(history, forecast, panel, path, pcfg, title) {
  origin <- min(as.Date(forecast$origin_date), na.rm = TRUE)
  window_start <- origin - as.integer(pcfg$forecast_window$before_days)
  window_end <- origin + as.integer(pcfg$forecast_window$after_days)
  hist <- history[history$target_date >= window_start & history$target_date <= origin, , drop = FALSE]
  fc <- forecast[forecast$target_date > origin & forecast$target_date <= window_end, , drop = FALSE]
  ens <- panel[panel$is_ensemble & as.Date(panel$origin_date) == origin &
    as.Date(panel$target_date) > origin & as.Date(panel$target_date) <= window_end, , drop = FALSE]
  ret <- panel[panel$is_retrospective & as.Date(panel$target_date) >= window_start &
    as.Date(panel$target_date) <= origin, , drop = FALSE]
  app_post_pdf_plot(path, 8.8, 5.2, {
    yr <- app_post_safe_range(hist$y_reference, hist$q_y_lo, hist$q_y_hi, fc$y_reference,
      fc$q_y_lo, fc$q_y_hi, ens$g_transformed, ret$g_transformed)
    plot(c(window_start, window_end), yr, type = "n", xlab = "Date",
      ylab = "Transformed streamflow", main = title)
    grid(col = "gray90")
    if (nrow(ens)) {
      members <- unique(ens$member)
      for (m in members) {
        one <- ens[ens$member == m, , drop = FALSE]
        one <- one[order(one$target_date), , drop = FALSE]
        lines(one$target_date, one$g_transformed, col = grDevices::adjustcolor("#b8b8b8", 0.45), lwd = 0.7)
      }
    }
    if (nrow(ret)) lines(ret$target_date, ret$g_transformed, col = "#b03a2e", lwd = 1.0, lty = 3)
    app_plot_band(hist$target_date, hist$q_y_lo, hist$q_y_hi, grDevices::adjustcolor("#2f6f9f", 0.15))
    lines(hist$target_date, hist$q_y_median, col = "#2f6f9f", lwd = 1.8)
    app_plot_band(fc$target_date, fc$q_y_lo, fc$q_y_hi, grDevices::adjustcolor("#2f6f9f", 0.22))
    lines(fc$target_date, fc$q_y_median, col = "#2f6f9f", lwd = 2.0)
    lines(hist$target_date, hist$y_reference, col = "#111111", lwd = 1.0)
    points(fc$target_date, fc$y_reference, col = "#111111", pch = 19, cex = 0.45)
    lines(fc$target_date, fc$raw_glofas_quantile, col = "#727272", lty = 2, lwd = 1.5)
    abline(v = origin, col = "#333333", lwd = 1.2)
    legend("topleft",
      legend = c(
        "USGS observed/reference",
        "Corrected Q-DESN quantile",
        "95% posterior interval, observed window",
        "95% posterior interval, forecast window",
        "Raw GloFAS quantile",
        "GloFAS retrospective",
        "GloFAS ensemble members"
      ),
      col = c(
        "#111111",
        "#2f6f9f",
        grDevices::adjustcolor("#2f6f9f", 0.30),
        grDevices::adjustcolor("#2f6f9f", 0.42),
        "#727272",
        "#b03a2e",
        "#b8b8b8"
      ),
      lty = c(1, 1, NA, NA, 2, 3, 1),
      lwd = c(1, 2, NA, NA, 1.5, 1, 0.7),
      pch = c(NA, NA, 15, 15, NA, NA, NA),
      bty = "n",
      cex = 0.70
    )
  })
}

app_post_plot_discrepancy_window <- function(history, forecast, path, pcfg, title) {
  origin <- min(as.Date(forecast$origin_date), na.rm = TRUE)
  window_start <- origin - as.integer(pcfg$forecast_window$before_days)
  window_end <- origin + as.integer(pcfg$forecast_window$after_days)
  hist <- history[history$target_date >= window_start & history$target_date <= origin, , drop = FALSE]
  fc <- forecast[forecast$target_date > origin & forecast$target_date <= window_end, , drop = FALSE]
  heldout_raw_disc <- fc$raw_glofas_quantile - fc$y_reference
  app_post_pdf_plot(path, 8.8, 5.0, {
    yr <- app_post_safe_range(hist$observed_discrepancy, fc$d_g_lo, fc$d_g_hi, heldout_raw_disc)
    plot(c(window_start, window_end), yr, type = "n", xlab = "Date",
      ylab = "Transformed discrepancy", main = title)
    grid(col = "gray90")
    abline(h = 0, lty = 2, col = "gray60")
    lines(hist$target_date, hist$observed_discrepancy, col = "#111111", lwd = 1.0)
    app_plot_band(hist$target_date, hist$d_g_lo, hist$d_g_hi, grDevices::adjustcolor("#8f3d56", 0.15))
    lines(hist$target_date, hist$d_g_median, col = "#8f3d56", lwd = 1.8)
    app_plot_band(fc$target_date, fc$d_g_lo, fc$d_g_hi, grDevices::adjustcolor("#8f3d56", 0.22))
    lines(fc$target_date, fc$d_g_median, col = "#8f3d56", lwd = 2.0)
    points(fc$target_date, heldout_raw_disc, col = "#444444", pch = 19, cex = 0.45)
    abline(v = origin, col = "#333333", lwd = 1.2)
    legend("topleft",
      legend = c("Observed GloFAS - USGS", "Fitted discrepancy", "Held-out raw p-level GloFAS - USGS"),
      col = c("#111111", "#8f3d56", "#444444"),
      lty = c(1, 1, NA), pch = c(NA, NA, 19), lwd = c(1, 2, NA), bty = "n", cex = 0.74
    )
  })
}

app_post_plot_parameter_histograms <- function(bundle, path, fit_row, pcfg) {
  mats <- list(scale = bundle$sigma)
  if (isTRUE(bundle$gamma_active)) mats$asymmetry <- bundle$gamma
  mats <- mats[!vapply(mats, is.null, logical(1L))]
  if (!length(mats)) return(NULL)
  n_panels <- sum(vapply(mats, ncol, integer(1L)))
  app_post_pdf_plot(path, width = 8.5, height = max(3.5, 2.4 * ceiling(n_panels / 2)), {
    old <- par(mfrow = c(ceiling(n_panels / 2), 2), mar = c(4, 4, 2.2, 1))
    on.exit(par(old), add = TRUE)
    for (family in names(mats)) {
      mat <- mats[[family]]
      for (j in seq_len(ncol(mat))) {
        x <- mat[, j]
        s <- app_summary_stats(x, pcfg$credible_level)
        hist(x, breaks = 35, col = "#d7e4ee", border = "white",
          main = sprintf("%s: %s", fit_row$fit_id, colnames(mat)[[j]]), xlab = family)
        abline(v = c(s[["lo"]], s[["median"]], s[["hi"]]), col = c("#2f6f9f", "#111111", "#2f6f9f"),
          lwd = c(1.5, 2, 1.5), lty = c(2, 1, 2))
      }
    }
  })
  path
}

app_post_plot_traces <- function(trace_table, path, pcfg, title) {
  if (!nrow(trace_table)) return(NULL)
  skip <- max(0L, as.integer(pcfg$trace_skip %||% 0L))
  tr <- trace_table[trace_table$iteration > skip, , drop = FALSE]
  if (!nrow(tr)) return(NULL)
  keys <- unique(tr[, c("trace_source", "trace_name"), drop = FALSE])
  n_panels <- nrow(keys)
  app_post_pdf_plot(path, width = 8.5, height = max(3.4, 2.2 * n_panels), {
    old <- par(mfrow = c(n_panels, 1), mar = c(3.5, 4, 2.2, 1))
    on.exit(par(old), add = TRUE)
    for (i in seq_len(nrow(keys))) {
      idx <- tr$trace_source == keys$trace_source[[i]] & tr$trace_name == keys$trace_name[[i]]
      one <- tr[idx, , drop = FALSE]
      plot(one$iteration, one$value, type = "l", col = "#2f6f9f",
        xlab = "Iteration", ylab = keys$trace_name[[i]],
        main = sprintf("%s: %s", title, keys$trace_name[[i]]))
      grid(col = "gray90")
    }
  })
  path
}

app_post_plot_coefficient_forest <- function(draws, path, title, top_k = 50L) {
  draws <- as.matrix(draws)
  top_k <- min(as.integer(top_k), ncol(draws))
  if (!top_k) return(NULL)
  means <- colMeans(draws, na.rm = TRUE)
  lo <- apply(draws, 2L, stats::quantile, probs = 0.025, na.rm = TRUE, names = FALSE)
  hi <- apply(draws, 2L, stats::quantile, probs = 0.975, na.rm = TRUE, names = FALSE)
  ord <- order(abs(means), decreasing = TRUE)[seq_len(top_k)]
  labels <- colnames(draws)[ord] %||% paste0("feature_", ord)
  labels <- rev(labels)
  y <- seq_along(ord)
  app_post_pdf_plot(path, width = 8.5, height = max(5, 0.16 * top_k + 2.5), {
    old <- par(mar = c(4.2, 10.5, 2.5, 1))
    on.exit(par(old), add = TRUE)
    plot(range(c(lo[ord], hi[ord], 0), na.rm = TRUE), range(y), type = "n",
      yaxt = "n", xlab = "Coefficient", ylab = "", main = title)
    grid(nx = NULL, ny = NA, col = "gray90")
    abline(v = 0, col = "gray60", lty = 2)
    segments(lo[rev(ord)], y, hi[rev(ord)], y, col = "#2f6f9f", lwd = 1.4)
    points(means[rev(ord)], y, pch = 19, col = "#111111", cex = 0.55)
    axis(2, at = y, labels = labels, las = 1, cex.axis = 0.58)
  })
  path
}

app_post_fit_make_figures <- function(history, recent, forecast, bundle, fit, fit_row, panel, pcfg, fig_dir) {
  app_ensure_dir(fig_dir)
  p_label <- sprintf("p=%s", format(as.numeric(fit_row$quantile_level), trim = TRUE))
  stem <- gsub("[^A-Za-z0-9_=-]+", "_", fit_row$fit_id)
  figs <- list()
  figs[[paste0(stem, "_history_full")]] <- file.path(fig_dir, paste0(stem, "__quantile_history_full.pdf"))
  app_post_plot_history_quantile(history, figs[[length(figs)]], sprintf("Fitted USGS quantile path, %s", p_label), p_label)
  figs[[paste0(stem, "_history_recent")]] <- file.path(fig_dir, paste0(stem, "__quantile_history_recent.pdf"))
  app_post_plot_history_quantile(recent, figs[[length(figs)]], sprintf("Recent fitted USGS quantile path, %s", p_label), p_label)
  figs[[paste0(stem, "_forecast_window")]] <- file.path(fig_dir, paste0(stem, "__forecast_window_pm30.pdf"))
  app_post_plot_forecast_window(history, forecast, panel, figs[[length(figs)]], pcfg, sprintf("Forecast-window quantile correction, %s", p_label))
  figs[[paste0(stem, "_discrepancy_full")]] <- file.path(fig_dir, paste0(stem, "__discrepancy_history_full.pdf"))
  app_post_plot_discrepancy(history, figs[[length(figs)]], sprintf("Fitted GloFAS discrepancy path, %s", p_label))
  since_history <- app_post_fit_since_history(history, pcfg$discrepancy_history_since)
  if (!is.null(pcfg$discrepancy_history_since) && !is.na(pcfg$discrepancy_history_since) && nrow(since_history)) {
    since_slug <- app_post_date_slug(pcfg$discrepancy_history_since)
    figs[[paste0(stem, "_discrepancy_since_", since_slug)]] <- file.path(fig_dir, paste0(stem, "__discrepancy_history_since_", since_slug, ".pdf"))
    app_post_plot_discrepancy(
      since_history,
      figs[[length(figs)]],
      sprintf("Fitted GloFAS discrepancy path since %s, %s", since_slug, p_label)
    )
  }
  figs[[paste0(stem, "_discrepancy_recent")]] <- file.path(fig_dir, paste0(stem, "__discrepancy_history_recent.pdf"))
  app_post_plot_discrepancy(recent, figs[[length(figs)]], sprintf("Recent fitted GloFAS discrepancy path, %s", p_label))
  figs[[paste0(stem, "_discrepancy_window")]] <- file.path(fig_dir, paste0(stem, "__discrepancy_forecast_window_pm30.pdf"))
  app_post_plot_discrepancy_window(history, forecast, figs[[length(figs)]], pcfg, sprintf("Forecast-window discrepancy, %s", p_label))
  param_path <- file.path(fig_dir, paste0(stem, "__parameter_histograms.pdf"))
  if (!is.null(app_post_plot_parameter_histograms(bundle, param_path, fit_row, pcfg))) figs[[paste0(stem, "_parameter_histograms")]] <- param_path
  trace <- app_post_fit_trace_table(fit, bundle, fit_row)
  trace_path <- file.path(fig_dir, paste0(stem, "__diagnostic_traces.pdf"))
  if (!is.null(app_post_plot_traces(trace, trace_path, pcfg, sprintf("Diagnostic traces, %s", p_label)))) figs[[paste0(stem, "_diagnostic_traces")]] <- trace_path
  beta_path <- file.path(fig_dir, paste0(stem, "__readout_forest_beta_top", pcfg$coefficient_forest$top_k, ".pdf"))
  app_post_plot_coefficient_forest(bundle$beta, beta_path, sprintf("Shared-quantile readout coefficients, %s", p_label), pcfg$coefficient_forest$top_k)
  figs[[paste0(stem, "_beta_forest")]] <- beta_path
  alpha_path <- file.path(fig_dir, paste0(stem, "__readout_forest_alpha_top", pcfg$coefficient_forest$top_k, ".pdf"))
  app_post_plot_coefficient_forest(bundle$alpha, alpha_path, sprintf("Discrepancy readout coefficients, %s", p_label), pcfg$coefficient_forest$top_k)
  figs[[paste0(stem, "_alpha_forest")]] <- alpha_path
  figs
}

app_post_read_completed_fit_manifest <- function(run_dirs) {
  path <- file.path(run_dirs$manifest, "qdesn_discrepancy_fit_manifest.csv")
  if (!file.exists(path)) stop(sprintf("Missing discrepancy fit manifest: %s", path), call. = FALSE)
  manifest <- app_read_csv(path)
  required <- c("fit_id", "model_id", "quantile_level", "method", "likelihood_family", "fit_object", "design_object", "status")
  app_check_required_columns(manifest, required, "Q-DESN discrepancy fit manifest")
  manifest[manifest$status == "completed", , drop = FALSE]
}

app_post_resolve_artifact_path <- function(path) {
  if (is.na(path) || !nzchar(as.character(path))) return(NA_character_)
  if (grepl("^/", path)) path else app_path(path)
}

app_git_dirty_flag <- function() {
  out <- tryCatch(app_system2_repo("git", c("status", "--short"), stdout = TRUE, stderr = TRUE), error = function(e) character())
  length(out) > 0L
}

app_write_post_analysis_manifest <- function(outputs, run_dirs, cfg, path, provenance = list()) {
  rows <- lapply(names(outputs), function(nm) {
    p <- outputs[[nm]]
    data.frame(
      output_role = nm,
      output_path = app_prefer_repo_relative_path(p),
      exists = file.exists(p),
      file_size_bytes = if (file.exists(p)) as.numeric(file.info(p)$size) else NA_real_,
      run_id = basename(run_dirs$run_dir),
      config_path = cfg$.__config_path__,
      article_git_sha = app_git_sha(short = FALSE),
      article_git_dirty = app_git_dirty_flag(),
      config_hash = provenance$config_hash %||% if (file.exists(cfg$.__config_path__)) app_sha256_file(cfg$.__config_path__) else NA_character_,
      input_manifest_hash = provenance$input_manifest_hash %||% NA_character_,
      fit_manifest_hash = provenance$fit_manifest_hash %||% NA_character_,
      prediction_table_hash = provenance$prediction_table_hash %||% NA_character_,
      posterior_draw_table_hash = provenance$posterior_draw_table_hash %||% NA_character_,
      engine_repo_sha = provenance$engine_repo_sha %||% NA_character_,
      created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  app_write_csv(out, path)
  out
}

app_run_post_fit_analysis <- function(cfg, run_dirs) {
  pcfg <- app_post_analysis_config(cfg)
  fit_rows <- app_post_read_completed_fit_manifest(run_dirs)
  if (!nrow(fit_rows)) stop("No completed discrepancy fits are available for post-analysis.", call. = FALSE)

  panel_path <- file.path(app_config_path(cfg, "cache"), "application_panel.rds")
  if (!file.exists(panel_path)) stop(sprintf("Missing application panel: %s", panel_path), call. = FALSE)
  panel <- readRDS(panel_path)
  pred_path <- file.path(run_dirs$tables, "prediction_quantiles.csv")
  draw_path <- file.path(run_dirs$tables, "posterior_draw_predictions.csv")
  if (!file.exists(pred_path)) stop(sprintf("Missing prediction table: %s", pred_path), call. = FALSE)
  if (!file.exists(draw_path)) stop(sprintf("Missing posterior draw predictions: %s", draw_path), call. = FALSE)
  predictions <- app_read_csv(pred_path)
  draws_all <- app_read_csv(draw_path)
  fit_manifest_path <- file.path(run_dirs$manifest, "qdesn_discrepancy_fit_manifest.csv")
  input_manifest_path <- app_config_path(cfg, "input_manifest")
  provenance <- list(
    config_hash = app_sha256_file(cfg$.__config_path__),
    input_manifest_hash = if (file.exists(input_manifest_path)) app_sha256_file(input_manifest_path) else NA_character_,
    fit_manifest_hash = app_sha256_file(fit_manifest_path),
    prediction_table_hash = app_sha256_file(pred_path),
    posterior_draw_table_hash = app_sha256_file(draw_path),
    engine_repo_sha = if ("engine_repo_sha" %in% names(fit_rows)) {
      paste(sort(unique(na.omit(fit_rows$engine_repo_sha))), collapse = ";")
    } else {
      NA_character_
    }
  )

  table_outputs <- list()
  figure_outputs <- list()
  history_rows <- list()
  recent_rows <- list()
  forecast_rows <- list()
  param_rows <- list()
  trace_rows <- list()
  rhs_rows <- list()
  band_check_rows <- list()
  fig_dir <- file.path(run_dirs$figures, "post_fit_analysis")
  app_ensure_dir(fig_dir)

  for (i in seq_len(nrow(fit_rows))) {
    fit_row <- fit_rows[i, , drop = FALSE]
    fit <- readRDS(app_post_resolve_artifact_path(fit_row$fit_object[[1L]]))
    design <- readRDS(app_post_resolve_artifact_path(fit_row$design_object[[1L]]))
    bundle <- app_post_fit_draw_bundle(fit, design, meta = as.list(fit_row))
    history <- app_post_fit_history_summary(bundle, design, fit_row, pcfg)
    recent <- app_post_fit_recent_history(history, pcfg$recent_history_n)
    fdraws <- draws_all[draws_all$fit_id == fit_row$fit_id[[1L]], , drop = FALSE]
    if (!nrow(fdraws)) stop(sprintf("No posterior forecast draws found for fit_id '%s'.", fit_row$fit_id[[1L]]), call. = FALSE)
    forecast <- app_post_fit_forecast_summary(fdraws, pcfg)
    band_check <- app_post_forecast_window_band_check(history, forecast, pcfg)
    if (!isTRUE(band_check$history_band_ok[[1L]]) || !isTRUE(band_check$forecast_band_ok[[1L]])) {
      stop(sprintf(
        "Forecast-window uncertainty bands are incomplete for fit_id '%s'. History band rows: %d; forecast band rows: %d.",
        fit_row$fit_id[[1L]],
        band_check$n_history_band_rows[[1L]],
        band_check$n_forecast_band_rows[[1L]]
      ), call. = FALSE)
    }
    history_rows[[i]] <- history
    recent_rows[[i]] <- recent
    forecast_rows[[i]] <- forecast
    band_check_rows[[i]] <- band_check
    param_rows[[i]] <- app_post_fit_parameter_summary(bundle, fit_row, pcfg)
    trace_rows[[i]] <- app_post_fit_trace_table(fit, bundle, fit_row)
    rhs_rows[[i]] <- app_post_fit_rhs_summary(fit, fit_row)
    figs <- app_post_fit_make_figures(history, recent, forecast, bundle, fit, fit_row, panel, pcfg, fig_dir)
    figure_outputs <- c(figure_outputs, figs)
  }

  history_all <- app_bind_rows_fill(history_rows)
  recent_all <- app_bind_rows_fill(recent_rows)
  forecast_all <- app_bind_rows_fill(forecast_rows)
  params_all <- app_bind_rows_fill(param_rows)
  traces_all <- app_bind_rows_fill(trace_rows)
  rhs_all <- app_bind_rows_fill(rhs_rows)
  band_checks_all <- app_bind_rows_fill(band_check_rows)
  metrics <- app_post_fit_metrics(predictions, cfg)

  table_outputs$post_fit_quantile_history_summary <- file.path(run_dirs$tables, "post_fit_quantile_history_summary.csv")
  app_write_csv(history_all, table_outputs$post_fit_quantile_history_summary)
  table_outputs$post_fit_quantile_recent_summary <- file.path(run_dirs$tables, "post_fit_quantile_recent_summary.csv")
  app_write_csv(recent_all, table_outputs$post_fit_quantile_recent_summary)
  table_outputs$post_fit_forecast_window_summary <- file.path(run_dirs$tables, "post_fit_forecast_window_summary.csv")
  app_write_csv(forecast_all, table_outputs$post_fit_forecast_window_summary)
  table_outputs$post_fit_forecast_window_band_check <- file.path(run_dirs$tables, "post_fit_forecast_window_band_check.csv")
  app_write_csv(band_checks_all, table_outputs$post_fit_forecast_window_band_check)
  table_outputs$post_fit_discrepancy_history_summary <- file.path(run_dirs$tables, "post_fit_discrepancy_history_summary.csv")
  app_write_csv(history_all[, c("fit_id", "model_id", "quantile_level", "target_date", "observed_discrepancy", "d_g_mean", "d_g_lo", "d_g_median", "d_g_hi"), drop = FALSE], table_outputs$post_fit_discrepancy_history_summary)
  table_outputs$post_fit_parameter_summary <- file.path(run_dirs$tables, "post_fit_parameter_summary.csv")
  app_write_csv(params_all, table_outputs$post_fit_parameter_summary)
  table_outputs$post_fit_trace_summary <- file.path(run_dirs$tables, "post_fit_trace_summary.csv")
  app_write_csv(traces_all, table_outputs$post_fit_trace_summary)
  table_outputs$post_fit_rhs_summary <- file.path(run_dirs$tables, "post_fit_rhs_summary.csv")
  app_write_csv(rhs_all, table_outputs$post_fit_rhs_summary)
  table_outputs$post_fit_metrics_by_model <- file.path(run_dirs$tables, "post_fit_metrics_by_model.csv")
  app_write_csv(metrics$by_model, table_outputs$post_fit_metrics_by_model)
  table_outputs$post_fit_metrics_by_horizon <- file.path(run_dirs$tables, "post_fit_metrics_by_horizon.csv")
  app_write_csv(metrics$by_horizon, table_outputs$post_fit_metrics_by_horizon)

  outputs <- c(table_outputs, figure_outputs)
  manifest_path <- file.path(run_dirs$tables, "post_analysis_manifest.csv")
  manifest <- app_write_post_analysis_manifest(outputs, run_dirs, cfg, manifest_path, provenance = provenance)
  list(outputs = outputs, manifest = manifest)
}
