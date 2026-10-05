# Recursive posterior-design reconstruction for the completed JOINT study.

app_joint_recursive_feature_row <- function(tt, lag_y, sc) {
  tt <- as.integer(tt)
  lag_y <- as.numeric(lag_y)
  simulated_length <- as.integer(sc$simulated_length[[1L]])
  period <- as.integer(sc$period[[1L]])
  angle <- 2 * pi * (tt - 1L) / period
  trend <- if (simulated_length > 1L) {
    -1 + 2 * (tt - 1L) / (simulated_length - 1L)
  } else 0
  regime_start <- max(1L, min(
    simulated_length,
    floor(as.numeric(sc$regime_start_fraction[[1L]]) * simulated_length)
  ))
  regime <- as.numeric(tt > regime_start)
  post_regime_trend <- if (tt > regime_start) {
    (tt - regime_start) / max(1L, simulated_length - regime_start)
  } else 0
  values <- c(
    lag_y = lag_y,
    trend = trend,
    sin_season = sin(angle),
    cos_season = cos(angle),
    abs_lag_scaled = abs(lag_y) / (1 + abs(lag_y)),
    regime = regime,
    post_regime_trend = post_regime_trend,
    lag_y_sq_scaled = lag_y^2 / (1 + lag_y^2),
    sin_lag = sin(lag_y),
    season_lag_interaction = sin(angle) * lag_y / (1 + abs(lag_y))
  )
  feature_names <- app_joint_qvp_registry_feature_names(
    as.character(sc$dynamics_class[[1L]])
  )
  out <- as.numeric(values[feature_names])
  names(out) <- feature_names
  out
}

app_joint_recursive_scale_row <- function(raw_row, scale_params) {
  raw_row <- as.numeric(raw_row)
  names(raw_row) <- names(scale_params$center)
  if (!isTRUE(scale_params$standardize)) return(raw_row)
  center <- as.numeric(scale_params$center)
  scale <- as.numeric(scale_params$scale)
  if (length(raw_row) != length(center) || length(scale) != length(center) ||
      any(!is.finite(c(raw_row, center, scale))) || any(scale <= 0)) {
    stop("Recursive reservoir scaling contract is malformed.", call. = FALSE)
  }
  (raw_row - center) / scale
}

app_joint_recursive_reservoir_meta <- function(design, selected) {
  if (identical(design$design_class, "direct")) return(NULL)
  input_scale <- as.numeric(selected$input_scale[[1L]])
  m <- length(design$scale_params$center)
  if (!is.finite(input_scale) || input_scale <= 0 || m <= 0L) {
    stop("Selected recursive reservoir input scale is invalid.", call. = FALSE)
  }
  list(
    standardize_inputs = FALSE,
    lag_center = rep(0, m),
    lag_scale = rep(1, m),
    input_bound = "none",
    win_scale_global = input_scale,
    win_scale_bias = input_scale
  )
}

app_joint_recursive_feature_from_history <- function(tt, history, design) {
  if (identical(design$feature_contract %||% "", "pure_recursive_v1")) {
    return(app_joint_pure_known_feature_row(
      tt, history, response_lags = design$response_lags, sc = design$dgp_row))
  }
  app_joint_recursive_feature_row(tt, history[[tt - 1L]], design$dgp_row)
}

app_joint_recursive_selected_row <- function(selected, scenario_id) {
  row <- selected[as.character(selected$scenario_id) == scenario_id, , drop = FALSE]
  if (nrow(row) != 1L) {
    stop(sprintf("Expected one selected backbone for '%s'.", scenario_id), call. = FALSE)
  }
  row
}

app_joint_recursive_origin_snapshots <- function(design, fixture, selected) {
  if (!identical(as.character(design$scenario_id), as.character(fixture$scenario_id))) {
    stop("Design and fixture scenario identifiers differ.", call. = FALSE)
  }
  origins <- unique(design$forecast_map[, c("origin_index"), drop = FALSE])
  origin_full <- vapply(origins$origin_index, function(index) {
    rows <- design$forecast_map$origin_index == index
    min(design$forecast_map$full_time_index[rows]) - 1L
  }, integer(1L))
  local_origin <- match(origin_full, design$row_meta$full_time_index)
  if (anyNA(local_origin)) stop("Forecast origins do not map to design history.", call. = FALSE)

  out <- list(
    origin_index = origins$origin_index,
    origin_full_time_index = origin_full,
    local_origin = local_origin,
    states = vector("list", length(local_origin)),
    reservoir_meta = app_joint_recursive_reservoir_meta(design, selected),
    teacher_forced_max_abs_diff = 0
  )
  if (identical(design$design_class, "direct")) return(out)

  full <- design$row_meta$full_time_index
  raw <- if (identical(design$feature_contract %||% "", "pure_recursive_v1")) {
    app_joint_pure_raw_matrix(full, fixture$y, data.frame(
      response_lags = design$response_lags, stringsAsFactors = FALSE), design$dgp_row)
  } else as.matrix(fixture$Z[full, , drop = FALSE])
  scaled <- app_qdesn_reservoir_scale_inputs(
    raw, scale_params = design$scale_params
  )$X
  rolled <- app_qdesn_roll_article_reservoir(
    scaled, design$reservoir, out$reservoir_meta
  )
  standardized <- sweep(
    sweep(rolled$X_all, 2L, design$state_center, "-"),
    2L, design$state_scale, "/"
  )
  reservoir_columns <- grep("^reservoir_", colnames(design$Z), value = TRUE)
  stored <- design$Z[, reservoir_columns, drop = FALSE]
  out$teacher_forced_max_abs_diff <- max(abs(standardized - stored))
  out$states <- lapply(local_origin, function(index) {
    lapply(rolled$H_all, function(layer) as.numeric(layer[index, ]))
  })
  out
}

app_joint_recursive_readout_row <- function(
  raw_row, states, design, reservoir_meta
) {
  state_row <- numeric(0)
  if (!identical(design$design_class, "direct")) {
    scaled <- app_joint_recursive_scale_row(raw_row, design$scale_params)
    states <- app_qdesn_continue_one_step(
      states, scaled, design$reservoir, reservoir_meta
    )
    state_raw <- app_qdesn_readout_row_from_states(states, design$reservoir)
    state_row <- (state_raw - design$state_center) / design$state_scale
    names(state_row) <- paste0(
      "reservoir_", sprintf("%04d", seq_along(state_row))
    )
  }
  raw_named <- as.numeric(raw_row)
  names(raw_named) <- names(raw_row)
  z <- switch(
    design$design_class,
    direct = raw_named,
    reservoir = state_row,
    hybrid = c(raw_named, state_row),
    stop("Unknown recursive design class.", call. = FALSE)
  )
  expected <- colnames(design$Z)
  if (!setequal(names(z), expected)) {
    stop("Recursive readout columns differ from the fitted design.", call. = FALSE)
  }
  list(z = as.numeric(z[expected]), states = states)
}

app_joint_recursive_contract_vector <- function(q, tau) {
  q <- as.numeric(q)
  if (length(q) != length(tau) || any(!is.finite(q))) {
    stop("Recursive quantile vector is malformed.", call. = FALSE)
  }
  if (all(diff(q) >= -1e-12)) q else app_isotonic_quantiles(tau, q)
}

app_joint_recursive_inverse_cdf <- function(
  q, tau, u, tail_rule = "endpoint_clamp"
) {
  q <- app_joint_recursive_contract_vector(q, tau)
  u <- as.numeric(u)
  if (length(u) != 1L || !is.finite(u) || u < 0 || u > 1) {
    stop("Inverse-CDF uniform must lie in [0,1].", call. = FALSE)
  }
  if (identical(tail_rule, "endpoint_clamp")) {
    if (u <= tau[[1L]]) return(q[[1L]])
    if (u >= tau[[length(tau)]]) return(q[[length(q)]])
  } else if (identical(tail_rule, "truncated_grid")) {
    u <- tau[[1L]] + u * (tau[[length(tau)]] - tau[[1L]])
  } else {
    stop(sprintf("Unknown inverse-CDF tail rule '%s'.", tail_rule), call. = FALSE)
  }
  as.numeric(stats::approx(tau, q, xout = u, method = "linear", ties = "ordered")$y)
}

app_joint_recursive_predict_vector <- function(z, beta, alpha, tau) {
  p <- length(z)
  K <- length(tau)
  if (length(beta) != p * K || length(alpha) != K) {
    stop("Recursive coefficient draw has incompatible dimensions.", call. = FALSE)
  }
  B <- matrix(as.numeric(beta), nrow = p, ncol = K)
  as.numeric(alpha + crossprod(B, z))
}

app_joint_recursive_teacher_forced_audit <- function(
  design, fixture, selected, tolerance = 1e-10
) {
  snapshots <- app_joint_recursive_origin_snapshots(design, fixture, selected)
  rebuilt <- matrix(NA_real_, nrow = nrow(design$forecast_map), ncol = ncol(design$Z))
  colnames(rebuilt) <- colnames(design$Z)
  for (origin_pos in seq_along(snapshots$origin_index)) {
    origin_id <- snapshots$origin_index[[origin_pos]]
    map_rows <- which(design$forecast_map$origin_index == origin_id)
    states <- snapshots$states[[origin_pos]]
    for (row_index in map_rows) {
      tt <- design$forecast_map$full_time_index[[row_index]]
      raw <- app_joint_recursive_feature_from_history(tt, fixture$y, design)
      step <- app_joint_recursive_readout_row(
        raw, states, design, snapshots$reservoir_meta
      )
      states <- step$states
      rebuilt[row_index, ] <- step$z
    }
  }
  stored <- design$Z[design$score_local, , drop = FALSE]
  max_diff <- max(abs(rebuilt - stored))
  data.frame(
    scenario_id = design$scenario_id,
    design_class = design$design_class,
    rows = nrow(rebuilt),
    columns = ncol(rebuilt),
    origin_snapshot_design_max_abs_diff = snapshots$teacher_forced_max_abs_diff,
    teacher_forced_max_abs_diff = max_diff,
    tolerance = tolerance,
    status = if (is.finite(max_diff) && max_diff <= tolerance &&
      snapshots$teacher_forced_max_abs_diff <= tolerance) "pass" else "fail",
    stringsAsFactors = FALSE
  )
}

app_joint_recursive_mean_design <- function(
  design, fixture, selected, beta_draws, alpha_draws, uniforms,
  tail_rule = "endpoint_clamp", half_assignment = NULL,
  diagnostic_group = NULL
) {
  beta_draws <- as.matrix(beta_draws)
  alpha_draws <- as.matrix(alpha_draws)
  uniforms <- as.matrix(uniforms)
  n_draw <- nrow(beta_draws)
  n_score <- nrow(design$forecast_map)
  p <- ncol(design$Z)
  K <- length(design$tau)
  if (n_draw < 2L || nrow(alpha_draws) != n_draw || nrow(uniforms) != n_draw ||
      ncol(beta_draws) != p * K || ncol(alpha_draws) != K ||
      ncol(uniforms) != n_score) {
    stop("Recursive mean-design draw inputs do not align.", call. = FALSE)
  }
  snapshots <- app_joint_recursive_origin_snapshots(design, fixture, selected)
  total <- total_sq <- matrix(0, nrow = n_score, ncol = p)
  path_min <- matrix(Inf, nrow = n_score, ncol = p)
  path_max <- matrix(-Inf, nrow = n_score, ncol = p)
  if (is.null(half_assignment)) {
    half_assignment <- rep(c(1L, 2L), length.out = n_draw)
  }
  half_assignment <- as.integer(half_assignment)
  if (length(half_assignment) != n_draw ||
      !all(half_assignment %in% c(1L, 2L)) ||
      length(unique(half_assignment)) != 2L) {
    stop("Recursive mean-design half assignment is malformed.", call. = FALSE)
  }
  half_sum <- list(matrix(0, n_score, p), matrix(0, n_score, p))
  half_n <- tabulate(half_assignment, nbins = 2L)
  if (is.null(diagnostic_group) || all(is.na(diagnostic_group))) {
    group_index <- rep(NA_integer_, n_draw)
    group_labels <- character()
  } else {
    diagnostic_group <- as.character(diagnostic_group)
    if (length(diagnostic_group) != n_draw || anyNA(diagnostic_group)) {
      stop("Recursive mean-design diagnostic groups are malformed.", call. = FALSE)
    }
    group_labels <- unique(diagnostic_group)
    group_index <- match(diagnostic_group, group_labels)
  }
  group_sum <- lapply(group_labels, function(x) matrix(0, n_score, p))
  group_n <- if (length(group_labels)) {
    tabulate(group_index, nbins = length(group_labels))
  } else integer()

  for (draw_index in seq_len(n_draw)) {
    path <- matrix(NA_real_, nrow = n_score, ncol = p)
    for (origin_pos in seq_along(snapshots$origin_index)) {
      origin_id <- snapshots$origin_index[[origin_pos]]
      map_rows <- which(design$forecast_map$origin_index == origin_id)
      states <- snapshots$states[[origin_pos]]
      history <- fixture$y[seq_len(snapshots$origin_full_time_index[[origin_pos]])]
      for (row_index in map_rows) {
        tt <- design$forecast_map$full_time_index[[row_index]]
        raw <- app_joint_recursive_feature_from_history(tt, history, design)
        step <- app_joint_recursive_readout_row(
          raw, states, design, snapshots$reservoir_meta
        )
        states <- step$states
        path[row_index, ] <- step$z
        q <- app_joint_recursive_predict_vector(
          step$z, beta_draws[draw_index, ], alpha_draws[draw_index, ], design$tau
        )
        history[[tt]] <- app_joint_recursive_inverse_cdf(
          q, design$tau, uniforms[draw_index, row_index], tail_rule
        )
      }
    }
    if (any(!is.finite(path))) stop("Recursive path produced a nonfinite design.", call. = FALSE)
    total <- total + path
    total_sq <- total_sq + path^2
    path_min <- pmin(path_min, path)
    path_max <- pmax(path_max, path)
    half <- half_assignment[[draw_index]]
    half_sum[[half]] <- half_sum[[half]] + path
    if (!is.na(group_index[[draw_index]])) {
      group <- group_index[[draw_index]]
      group_sum[[group]] <- group_sum[[group]] + path
    }
  }
  mean_design <- total / n_draw
  variance <- pmax((total_sq - total^2 / n_draw) / (n_draw - 1L), 0)
  half_mean <- Map(`/`, half_sum, half_n)
  coordinate_sd <- sqrt(variance)
  stable_scale <- coordinate_sd
  stable_scale[!is.finite(stable_scale) | stable_scale < 1e-8] <- 1
  standardized_difference <- (half_mean[[1L]] - half_mean[[2L]]) / stable_scale
  colnames(mean_design) <- colnames(variance) <- colnames(design$Z)
  colnames(path_min) <- colnames(path_max) <- colnames(design$Z)
  colnames(half_mean[[1L]]) <- colnames(half_mean[[2L]]) <- colnames(design$Z)
  group_mean <- Map(`/`, group_sum, group_n)
  names(group_mean) <- group_labels
  group_mean <- lapply(group_mean, function(x) {
    colnames(x) <- colnames(design$Z)
    x
  })
  list(
    mean_design = mean_design,
    variance = variance,
    minimum = path_min,
    maximum = path_max,
    half_mean = half_mean,
    group_mean = group_mean,
    diagnostics = data.frame(
      scenario_id = design$scenario_id,
      inference_draws = n_draw,
      rows = n_score,
      columns = p,
      standardized_rms_half_difference = sqrt(mean(standardized_difference^2)),
      max_abs_half_difference = max(abs(half_mean[[1L]] - half_mean[[2L]])),
      finite = all(is.finite(c(mean_design, variance, half_mean[[1L]], half_mean[[2L]]))),
      stringsAsFactors = FALSE
    )
  )
}
