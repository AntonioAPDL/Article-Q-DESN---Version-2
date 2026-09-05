# Fixed-origin historical forecasts for the GloFAS Part 3 two-component bridge.

.app_glofas_part3_forecast_env <- new.env(parent = emptyenv())

app_glofas_part3_load_forecast_cpp <- function(required = TRUE) {
  if (isTRUE(.app_glofas_part3_forecast_env$loaded %||% FALSE) &&
      exists("glofas_part3_d1_quantile_recursive_cpp", mode = "function") &&
      exists("glofas_part3_d1_normal_draw_recursive_cpp", mode = "function")) {
    return(TRUE)
  }
  source_path <- app_path("application/src/glofas_part3_two_component_forecast.cpp")
  if (!file.exists(source_path) || !requireNamespace("Rcpp", quietly = TRUE)) {
    if (isTRUE(required)) stop("Part 3 C++ forecast source or Rcpp is unavailable.", call. = FALSE)
    return(FALSE)
  }
  ok <- tryCatch({
    Rcpp::sourceCpp(source_path, rebuild = FALSE, showOutput = FALSE, verbose = FALSE)
    TRUE
  }, error = function(e) {
    if (isTRUE(required)) stop(e)
    FALSE
  })
  .app_glofas_part3_forecast_env$loaded <- ok
  ok
}

app_glofas_part3_forecast_origin <- function(design, split, horizon_days = 30L) {
  horizon_days <- as.integer(horizon_days)
  if (!is.finite(horizon_days) || horizon_days < 1L) stop("Part 3 horizon must be positive.", call. = FALSE)
  train_idx <- as.integer(split$train_idx)
  valid_idx <- as.integer(split$valid_idx)
  if (!length(train_idx) || !length(valid_idx) || max(train_idx) >= min(valid_idx)) {
    stop("Part 3 forecast requires an ordered training/validation split.", call. = FALSE)
  }
  future_idx <- utils::head(valid_idx, horizon_days)
  if (length(future_idx) < horizon_days) stop("Part 3 validation period is shorter than the requested horizon.", call. = FALSE)
  expected <- seq.Date(as.Date(design$dates[max(train_idx)]) + 1, by = "day", length.out = horizon_days)
  if (!identical(as.Date(design$dates[future_idx]), expected)) {
    stop("Part 3 fixed-origin forecast dates are not a contiguous daily horizon.", call. = FALSE)
  }
  list(
    origin_index = max(train_idx),
    origin_date = as.Date(design$dates[max(train_idx)]),
    future_index = future_idx,
    future_dates = expected,
    horizon_days = horizon_days
  )
}

app_glofas_part3_component_context <- function(design, component, origin) {
  component <- match.arg(component, c("reference", "discrepancy"))
  block <- design[[component]]
  raw <- block$component_design
  meta <- raw$design_meta %||% list()
  reservoir <- raw$reservoir %||% list()
  spec <- meta$reservoir_input_spec %||% NULL
  if (is.null(spec)) stop(sprintf("Part 3 %s reservoir input contract is missing.", component), call. = FALSE)
  if (!identical(as.integer(reservoir$D %||% NA_integer_), 1L)) {
    stop(sprintf("Part 3 production forecast currently requires D=1 for %s.", component), call. = FALSE)
  }
  if (isTRUE(spec$uses_dlm_components %||% FALSE) || isTRUE(spec$uses_auxiliary_lags %||% FALSE)) {
    stop(sprintf("Part 3 %s winner uses unsupported future inputs.", component), call. = FALSE)
  }
  X <- as.matrix(block$X)
  state0 <- as.numeric(X[origin$origin_index, -1L, drop = TRUE])
  W <- as.matrix(reservoir$W[[1L]])
  Win <- as.matrix(reservoir$Win[[1L]])
  if (length(state0) != nrow(W) || ncol(X) != length(state0) + 1L) {
    stop(sprintf("Part 3 %s state/readout dimensions are inconsistent.", component), call. = FALSE)
  }
  history_dates <- as.Date(design$dates[seq_len(origin$origin_index)])
  history_response <- if (identical(component, "reference")) {
    as.numeric(design$y_reference[seq_len(origin$origin_index)])
  } else {
    as.numeric(design$d_g[seq_len(origin$origin_index)])
  }
  compiled <- app_qdesn_compile_future_input_contract(
    spec = spec,
    history_dates = history_dates,
    y_history = history_response,
    future_dates = origin$future_dates,
    covariate_timeline = meta$covariate_timeline %||% NULL
  )
  app_qdesn_validate_compiled_future_inputs(compiled, spec, origin$future_dates, verify_hash = TRUE)
  audit <- compiled$audit
  audit$part3_component <- component
  audit$response_semantics <- if (identical(component, "reference")) "usgs" else "glofas_minus_usgs"
  future_response <- as.character(audit$source) == "history" & as.Date(audit$input_date) > origin$origin_date
  if (any(future_response)) stop(sprintf("Part 3 %s forecast leaks future response values.", component), call. = FALSE)
  if (exists("app_glofas_oracle_validate_no_forbidden_sources", mode = "function")) {
    app_glofas_oracle_validate_no_forbidden_sources(audit, label = paste("Part 3", component, "forecast input audit"))
  }
  list(
    component = component,
    X = X,
    reservoir = reservoir,
    meta = meta,
    spec = spec,
    state0 = state0,
    compiled = compiled,
    history_dates = history_dates,
    history_response = history_response,
    audit = audit
  )
}

app_glofas_part3_component_cpp_args <- function(context, prefix) {
  reservoir <- context$reservoir
  meta <- context$meta
  compiled <- context$compiled
  out <- list(
    W = as.matrix(reservoir$W[[1L]]),
    Win = as.matrix(reservoir$Win[[1L]]),
    state0 = as.numeric(context$state0),
    static = as.matrix(compiled$static_values),
    future_index = matrix(as.integer(compiled$future_index), nrow = nrow(compiled$future_index)),
    center = as.numeric(meta$lag_center),
    scale = as.numeric(meta$lag_scale),
    standardize = isTRUE(meta$standardize_inputs %||% FALSE),
    input_bound = as.character(meta$input_bound %||% "none"),
    win_scale_global = as.numeric(meta$win_scale_global %||% 1),
    win_scale_bias = as.numeric(meta$win_scale_bias %||% 1),
    alpha = as.numeric(reservoir$alpha[[1L]]),
    activation = as.character(reservoir$act_f %||% "tanh")
  )
  names(out) <- paste0(names(out), "_", prefix)
  out
}

app_glofas_part3_advance_r <- function(context, state, row) {
  meta <- context$meta
  if (isTRUE(meta$standardize_inputs %||% FALSE)) {
    row <- (row - as.numeric(meta$lag_center)) / as.numeric(meta$lag_scale)
  }
  if (identical(as.character(meta$input_bound %||% "none"), "tanh")) row <- tanh(row)
  input <- c(as.numeric(meta$win_scale_bias %||% 1), as.numeric(meta$win_scale_global %||% 1) * row)
  proposal <- app_qdesn_activation(context$reservoir$act_f %||% "tanh")(
    as.numeric(context$reservoir$W[[1L]] %*% state + context$reservoir$Win[[1L]] %*% input)
  )
  alpha <- as.numeric(context$reservoir$alpha[[1L]])
  (1 - alpha) * state + alpha * proposal
}

app_glofas_part3_quantile_forecast_r <- function(reference, discrepancy, beta_reference, beta_discrepancy) {
  beta_reference <- as.matrix(beta_reference)
  beta_discrepancy <- as.matrix(beta_discrepancy)
  H <- nrow(reference$compiled$static_values)
  K <- nrow(beta_reference)
  out_reference <- out_discrepancy <- matrix(NA_real_, H, K)
  for (kk in seq_len(K)) {
    state_reference <- reference$state0
    state_discrepancy <- discrepancy$state0
    future_reference <- future_discrepancy <- numeric(H)
    for (hh in seq_len(H)) {
      input_reference <- reference$compiled$static_values[hh, ]
      input_discrepancy <- discrepancy$compiled$static_values[hh, ]
      idx_reference <- which(reference$compiled$future_index[hh, ] > 0L)
      idx_discrepancy <- which(discrepancy$compiled$future_index[hh, ] > 0L)
      if (length(idx_reference)) input_reference[idx_reference] <- future_reference[reference$compiled$future_index[hh, idx_reference]]
      if (length(idx_discrepancy)) input_discrepancy[idx_discrepancy] <- future_discrepancy[discrepancy$compiled$future_index[hh, idx_discrepancy]]
      state_reference <- app_glofas_part3_advance_r(reference, state_reference, input_reference)
      state_discrepancy <- app_glofas_part3_advance_r(discrepancy, state_discrepancy, input_discrepancy)
      future_reference[[hh]] <- sum(beta_reference[kk, ] * c(1, state_reference))
      future_discrepancy[[hh]] <- sum(beta_discrepancy[kk, ] * c(1, state_discrepancy))
      out_reference[hh, kk] <- future_reference[[hh]]
      out_discrepancy[hh, kk] <- future_discrepancy[[hh]]
    }
  }
  list(reference = out_reference, discrepancy = out_discrepancy, glofas = out_reference + out_discrepancy, backend = "r_part3_quantile_recursive")
}

app_glofas_part3_quantile_forecast <- function(
  design,
  split,
  fit,
  horizon_days = 30L,
  backend = c("auto", "cpp", "r")
) {
  backend <- match.arg(backend)
  if (!inherits(fit, "glofas_part3_quantile_fit")) stop("Expected a Part 3 quantile fit.", call. = FALSE)
  origin <- app_glofas_part3_forecast_origin(design, split, horizon_days)
  reference <- app_glofas_part3_component_context(design, "reference", origin)
  discrepancy <- app_glofas_part3_component_context(design, "discrepancy", origin)
  beta_reference <- t(as.matrix(fit$beta_reference_mean))
  beta_discrepancy <- t(as.matrix(fit$beta_discrepancy_mean))
  use_cpp <- identical(backend, "cpp") || (identical(backend, "auto") && app_glofas_part3_load_forecast_cpp(required = FALSE))
  if (identical(backend, "cpp") && !app_glofas_part3_load_forecast_cpp(required = TRUE)) stop("Part 3 C++ backend unavailable.", call. = FALSE)
  started <- Sys.time()
  result <- if (isTRUE(use_cpp)) {
    do.call(glofas_part3_d1_quantile_recursive_cpp, c(
      app_glofas_part3_component_cpp_args(reference, "reference"),
      list(beta_reference = beta_reference),
      app_glofas_part3_component_cpp_args(discrepancy, "discrepancy"),
      list(beta_discrepancy = beta_discrepancy)
    ))
  } else {
    app_glofas_part3_quantile_forecast_r(reference, discrepancy, beta_reference, beta_discrepancy)
  }
  result$tau <- as.numeric(fit$tau)
  historical <- app_glofas_part3_predict_components(fit, design)
  result$historical <- historical
  result$origin <- origin
  result$reference_input_audit <- reference$audit
  result$discrepancy_input_audit <- discrepancy$audit
  result$runtime_seconds <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  result
}

app_glofas_part3_normal_draws <- function(fit, method, n_draws, seed) {
  method <- match.arg(method, c("ridge", "rhs"))
  draws <- app_glofas_oracle_parameter_draws(fit, method = method, n_draws = n_draws, seed = seed)
  draws
}

app_glofas_part3_normal_forecast_r <- function(
  reference,
  discrepancy,
  beta_reference,
  beta_discrepancy,
  sigma,
  z_reference,
  z_glofas
) {
  H <- nrow(reference$compiled$static_values)
  S <- nrow(beta_reference)
  ref_mean <- disc_mean <- glofas_mean <- ref_draw <- disc_draw <- glofas_draw <- matrix(NA_real_, H, S)
  for (ss in seq_len(S)) {
    state_reference <- reference$state0
    state_discrepancy <- discrepancy$state0
    future_reference <- future_discrepancy <- numeric(H)
    for (hh in seq_len(H)) {
      input_reference <- reference$compiled$static_values[hh, ]
      input_discrepancy <- discrepancy$compiled$static_values[hh, ]
      idx_reference <- which(reference$compiled$future_index[hh, ] > 0L)
      idx_discrepancy <- which(discrepancy$compiled$future_index[hh, ] > 0L)
      if (length(idx_reference)) input_reference[idx_reference] <- future_reference[reference$compiled$future_index[hh, idx_reference]]
      if (length(idx_discrepancy)) input_discrepancy[idx_discrepancy] <- future_discrepancy[discrepancy$compiled$future_index[hh, idx_discrepancy]]
      state_reference <- app_glofas_part3_advance_r(reference, state_reference, input_reference)
      state_discrepancy <- app_glofas_part3_advance_r(discrepancy, state_discrepancy, input_discrepancy)
      q <- sum(beta_reference[ss, ] * c(1, state_reference))
      d <- sum(beta_discrepancy[ss, ] * c(1, state_discrepancy))
      y <- q + sigma[[ss]] * z_reference[hh, ss]
      g <- q + d + sigma[[ss]] * z_glofas[hh, ss]
      observed_d <- g - y
      ref_mean[hh, ss] <- q
      disc_mean[hh, ss] <- d
      glofas_mean[hh, ss] <- q + d
      ref_draw[hh, ss] <- y
      disc_draw[hh, ss] <- observed_d
      glofas_draw[hh, ss] <- g
      future_reference[[hh]] <- y
      future_discrepancy[[hh]] <- observed_d
    }
  }
  list(
    reference_mean_draws = ref_mean,
    discrepancy_mean_draws = disc_mean,
    glofas_mean_draws = glofas_mean,
    reference_draws = ref_draw,
    discrepancy_draws = disc_draw,
    glofas_draws = glofas_draw,
    backend = "r_part3_normal_draw_recursive"
  )
}

app_glofas_part3_normal_forecast <- function(
  design,
  split,
  fit,
  method = c("rhs", "ridge"),
  horizon_days = 30L,
  n_draws = 500L,
  seed = 20260904L,
  backend = c("auto", "cpp", "r")
) {
  method <- match.arg(method)
  backend <- match.arg(backend)
  n_draws <- as.integer(n_draws)
  if (!is.finite(n_draws) || n_draws < 2L) stop("Part 3 Normal forecast needs at least two draws.", call. = FALSE)
  origin <- app_glofas_part3_forecast_origin(design, split, horizon_days)
  reference <- app_glofas_part3_component_context(design, "reference", origin)
  discrepancy <- app_glofas_part3_component_context(design, "discrepancy", origin)
  draws <- app_glofas_part3_normal_draws(fit, method, n_draws, seed)
  beta_reference <- draws$beta[, design$beta_index, drop = FALSE]
  beta_discrepancy <- draws$beta[, design$alpha_index, drop = FALSE]
  random <- app_glofas_oracle_with_seed(as.integer(seed) + 1L, list(
    reference = matrix(stats::rnorm(origin$horizon_days * n_draws), origin$horizon_days, n_draws),
    glofas = matrix(stats::rnorm(origin$horizon_days * n_draws), origin$horizon_days, n_draws)
  ))
  use_cpp <- identical(backend, "cpp") || (identical(backend, "auto") && app_glofas_part3_load_forecast_cpp(required = FALSE))
  if (identical(backend, "cpp") && !app_glofas_part3_load_forecast_cpp(required = TRUE)) stop("Part 3 C++ backend unavailable.", call. = FALSE)
  started <- Sys.time()
  result <- if (isTRUE(use_cpp)) {
    do.call(glofas_part3_d1_normal_draw_recursive_cpp, c(
      app_glofas_part3_component_cpp_args(reference, "reference"),
      list(beta_reference_draws = beta_reference),
      app_glofas_part3_component_cpp_args(discrepancy, "discrepancy"),
      list(
        beta_discrepancy_draws = beta_discrepancy,
        sigma_draws = as.numeric(draws$sigma),
        z_reference = random$reference,
        z_glofas = random$glofas
      )
    ))
  } else {
    app_glofas_part3_normal_forecast_r(
      reference, discrepancy, beta_reference, beta_discrepancy,
      draws$sigma, random$reference, random$glofas
    )
  }
  result$origin <- origin
  beta_mean <- as.numeric(fit$beta_mean)
  historical_reference <- as.numeric(design$reference$X %*% beta_mean[design$beta_index])
  historical_discrepancy <- as.numeric(design$discrepancy$X %*% beta_mean[design$alpha_index])
  result$historical <- list(
    reference = matrix(historical_reference, ncol = 1L),
    discrepancy = matrix(historical_discrepancy, ncol = 1L),
    glofas = matrix(historical_reference + historical_discrepancy, ncol = 1L)
  )
  result$reference_input_audit <- reference$audit
  result$discrepancy_input_audit <- discrepancy$audit
  result$n_draws <- n_draws
  result$seed <- as.integer(seed)
  result$parameter_draw_backend <- draws$beta_draw_backend
  result$runtime_seconds <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  result
}

app_glofas_part3_empirical_crps <- function(observed, draws) {
  draws <- as.matrix(draws)
  vapply(seq_len(nrow(draws)), function(ii) {
    x <- draws[ii, ]
    mean(abs(x - observed[[ii]])) - 0.5 * mean(abs(outer(x, x, "-")))
  }, numeric(1L))
}

app_glofas_part3_forecast_summary <- function(forecast, design) {
  idx <- forecast$origin$future_index
  truth <- list(
    reference = design$y_reference[idx],
    discrepancy = design$d_g[idx],
    glofas = design$g_retrospective[idx]
  )
  draw_names <- c(reference = "reference_draws", discrepancy = "discrepancy_draws", glofas = "glofas_draws")
  rows <- lapply(names(draw_names), function(target) {
    draws <- as.matrix(forecast[[draw_names[[target]]]])
    centre <- rowMeans(draws)
    error <- centre - truth[[target]]
    data.frame(
      target = target,
      n = length(error),
      mean_crps = mean(app_glofas_part3_empirical_crps(truth[[target]], draws)),
      mae = mean(abs(error)),
      rmse = sqrt(mean(error^2)),
      bias = mean(error),
      coverage_95 = mean(truth[[target]] >= apply(draws, 1L, stats::quantile, 0.025) & truth[[target]] <= apply(draws, 1L, stats::quantile, 0.975)),
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_glofas_part3_quantile_forecast_summary <- function(forecast, design) {
  idx <- forecast$origin$future_index
  paths <- list(reference = forecast$reference, discrepancy = forecast$discrepancy, glofas = forecast$glofas)
  truth <- list(reference = design$y_reference[idx], discrepancy = design$d_g[idx], glofas = design$g_retrospective[idx])
  rows <- lapply(names(paths), function(target) {
    app_glofas_part3_quantile_score_block(truth[[target]], paths[[target]], forecast$tau, paste0(target, "_forecast"))
  })
  app_bind_rows_fill(rows)
}

app_glofas_part3_forecast_path_table <- function(forecast, design) {
  idx <- forecast$origin$future_index
  if (!is.null(forecast$reference_draws)) {
    summarize <- function(draws, truth, target) data.frame(
      date = forecast$origin$future_dates,
      segment = "forecast",
      horizon = seq_along(idx),
      target = target,
      observed = truth,
      mean = rowMeans(draws),
      median = apply(draws, 1L, stats::median),
      lower_95 = apply(draws, 1L, stats::quantile, 0.025),
      upper_95 = apply(draws, 1L, stats::quantile, 0.975),
      stringsAsFactors = FALSE
    )
    future <- app_bind_rows_fill(list(
      summarize(forecast$reference_draws, design$y_reference[idx], "reference"),
      summarize(forecast$discrepancy_draws, design$d_g[idx], "discrepancy"),
      summarize(forecast$glofas_draws, design$g_retrospective[idx], "glofas")
    ))
    historical_truth <- list(reference = design$y_reference, discrepancy = design$d_g, glofas = design$g_retrospective)
    historical <- app_bind_rows_fill(lapply(names(historical_truth), function(target) data.frame(
      date = as.Date(design$dates), segment = "historical_fit", horizon = NA_integer_, target = target,
      observed = historical_truth[[target]], mean = as.numeric(forecast$historical[[target]][, 1L]),
      median = NA_real_, lower_95 = NA_real_, upper_95 = NA_real_, stringsAsFactors = FALSE
    )))
    return(app_bind_rows_fill(list(historical, future)))
  }
  paths <- list(reference = forecast$reference, discrepancy = forecast$discrepancy, glofas = forecast$glofas)
  truth <- list(reference = design$y_reference[idx], discrepancy = design$d_g[idx], glofas = design$g_retrospective[idx])
  future <- app_bind_rows_fill(lapply(names(paths), function(target) {
    values <- as.matrix(paths[[target]])
    app_bind_rows_fill(lapply(seq_along(forecast$tau), function(kk) data.frame(
      date = forecast$origin$future_dates,
      segment = "forecast",
      horizon = seq_along(idx),
      target = target,
      tau = forecast$tau[[kk]],
      observed = truth[[target]],
      qhat = values[, kk],
      stringsAsFactors = FALSE
    )))
  }))
  historical_truth <- list(reference = design$y_reference, discrepancy = design$d_g, glofas = design$g_retrospective)
  historical <- app_bind_rows_fill(lapply(names(historical_truth), function(target) {
    values <- as.matrix(forecast$historical[[target]])
    app_bind_rows_fill(lapply(seq_along(forecast$tau), function(kk) data.frame(
      date = as.Date(design$dates), segment = "historical_fit", horizon = NA_integer_, target = target,
      tau = forecast$tau[[kk]], observed = historical_truth[[target]], qhat = values[, kk], stringsAsFactors = FALSE
    )))
  }))
  app_bind_rows_fill(list(historical, future))
}

app_glofas_part3_plot_forecast <- function(forecast, design, pdf_path, last_history = 200L) {
  last_history <- as.integer(last_history)
  origin_idx <- forecast$origin$origin_index
  hist_idx <- utils::tail(seq_len(origin_idx), min(last_history, origin_idx))
  future_idx <- forecast$origin$future_index
  targets <- c("reference", "glofas", "discrepancy")
  truth <- list(reference = design$y_reference, glofas = design$g_retrospective, discrepancy = design$d_g)
  labels <- c(reference = "USGS reference", glofas = "Retrospective GloFAS", discrepancy = "GloFAS - USGS discrepancy")
  dir.create(dirname(pdf_path), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(pdf_path, width = 11, height = 8.5, onefile = TRUE)
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)
  graphics::par(mfrow = c(3, 1), mar = c(3.2, 4.2, 2.5, 1.2), oma = c(0, 0, 2, 0), las = 1)
  palette <- c("#7A0019", "#BC5090", "#5B8C5A", "#0072B2", "#E69F00", "#8C6D31", "#6A3D9A")
  for (target in targets) {
    dates <- c(as.Date(design$dates[hist_idx]), forecast$origin$future_dates)
    observed <- c(truth[[target]][hist_idx], truth[[target]][future_idx])
    ylim <- range(observed, na.rm = TRUE)
    if (!is.null(forecast$reference_draws)) {
      draws <- as.matrix(forecast[[paste0(target, "_draws")]])
      lower <- apply(draws, 1L, stats::quantile, 0.025)
      upper <- apply(draws, 1L, stats::quantile, 0.975)
      ylim <- range(ylim, lower, upper, as.numeric(forecast$historical[[target]][hist_idx, 1L]), na.rm = TRUE)
    } else {
      ylim <- range(ylim, as.matrix(forecast$historical[[target]])[hist_idx, ], as.matrix(forecast[[target]]), na.rm = TRUE)
    }
    graphics::plot(dates, observed, type = "l", col = "#202020", lwd = 1.2, xlab = "", ylab = labels[[target]], ylim = ylim, main = labels[[target]])
    if (!is.null(forecast$reference_draws)) {
      graphics::lines(as.Date(design$dates[hist_idx]), as.numeric(forecast$historical[[target]][hist_idx, 1L]), col = "#0072B2", lwd = 1.4)
      xpoly <- c(forecast$origin$future_dates, rev(forecast$origin$future_dates))
      graphics::polygon(xpoly, c(lower, rev(upper)), col = grDevices::adjustcolor("#E69F00", alpha.f = 0.22), border = NA)
      graphics::lines(forecast$origin$future_dates, apply(draws, 1L, stats::median), col = "#D55E00", lwd = 1.8)
    } else {
      hist_values <- as.matrix(forecast$historical[[target]])
      future_values <- as.matrix(forecast[[target]])
      for (kk in seq_along(forecast$tau)) {
        graphics::lines(as.Date(design$dates[hist_idx]), hist_values[hist_idx, kk], col = grDevices::adjustcolor(palette[[kk]], 0.65), lwd = 0.8)
        graphics::lines(forecast$origin$future_dates, future_values[, kk], col = palette[[kk]], lwd = 1.5)
      }
    }
    graphics::abline(v = forecast$origin$origin_date, col = "#555555", lty = 3)
    graphics::grid(col = "#E5E5E5")
  }
  if (!is.null(forecast$tau)) {
    graphics::mtext(paste0("Quantiles: ", paste(sprintf("%.2f", forecast$tau), collapse = ", ")), side = 3, outer = TRUE, line = 0.4, cex = 0.8)
  } else {
    graphics::mtext("Posterior predictive median and 95% interval", side = 3, outer = TRUE, line = 0.4, cex = 0.8)
  }
  invisible(pdf_path)
}

app_glofas_part3_write_forecast <- function(forecast, design, runtime_root, run_label) {
  dirs <- file.path(runtime_root, c("forecasts", "scores", "logs", "tables", "status", "figures"))
  invisible(lapply(dirs, app_ensure_dir))
  is_normal <- !is.null(forecast$reference_draws)
  paths <- c(
    forecast = file.path(runtime_root, "forecasts", paste0(run_label, "_forecast.rds")),
    path = file.path(runtime_root, "forecasts", paste0(run_label, "_path.csv")),
    scores = file.path(runtime_root, "scores", paste0(run_label, "_forecast_scores.csv")),
    reference_audit = file.path(runtime_root, "logs", paste0(run_label, "_reference_input_audit.csv")),
    discrepancy_audit = file.path(runtime_root, "logs", paste0(run_label, "_discrepancy_input_audit.csv")),
    figure = file.path(runtime_root, "figures", paste0(run_label, "_last200_plus_forecast.pdf"))
  )
  saveRDS(forecast, paths[["forecast"]], version = 2L)
  app_write_csv(app_glofas_part3_forecast_path_table(forecast, design), paths[["path"]])
  score <- if (is_normal) app_glofas_part3_forecast_summary(forecast, design) else app_glofas_part3_quantile_forecast_summary(forecast, design)
  app_write_csv(score, paths[["scores"]])
  app_write_csv(forecast$reference_input_audit, paths[["reference_audit"]])
  app_write_csv(forecast$discrepancy_input_audit, paths[["discrepancy_audit"]])
  app_glofas_part3_plot_forecast(forecast, design, paths[["figure"]])
  manifest <- data.frame(
    artifact = names(paths),
    path = unname(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_write_csv(manifest, file.path(runtime_root, "tables", paste0(run_label, "_forecast_manifest.csv")))
  list(paths = c(paths, manifest = manifest_path), scores = score)
}
