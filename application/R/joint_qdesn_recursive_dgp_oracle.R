# Origin-marginal DGP oracle bank for recursive JOINT forecasts.

app_joint_recursive_dgp_feature_matrix <- function(tt, lag_y, sc) {
  lag_y <- as.numeric(lag_y)
  simulated_length <- as.integer(sc$simulated_length[[1L]])
  period <- as.integer(sc$period[[1L]])
  angle <- 2 * pi * (as.integer(tt) - 1L) / period
  trend <- if (simulated_length > 1L) {
    -1 + 2 * (as.integer(tt) - 1L) / (simulated_length - 1L)
  } else 0
  regime_start <- max(1L, min(
    simulated_length,
    floor(as.numeric(sc$regime_start_fraction[[1L]]) * simulated_length)
  ))
  regime <- as.numeric(as.integer(tt) > regime_start)
  post_regime_trend <- if (as.integer(tt) > regime_start) {
    (as.integer(tt) - regime_start) / max(1L, simulated_length - regime_start)
  } else 0
  values <- cbind(
    lag_y = lag_y,
    trend = rep(trend, length(lag_y)),
    sin_season = rep(sin(angle), length(lag_y)),
    cos_season = rep(cos(angle), length(lag_y)),
    abs_lag_scaled = abs(lag_y) / (1 + abs(lag_y)),
    regime = rep(regime, length(lag_y)),
    post_regime_trend = rep(post_regime_trend, length(lag_y)),
    lag_y_sq_scaled = lag_y^2 / (1 + lag_y^2),
    sin_lag = sin(lag_y),
    season_lag_interaction = sin(angle) * lag_y / (1 + abs(lag_y))
  )
  feature_names <- app_joint_qvp_registry_feature_names(
    as.character(sc$dynamics_class[[1L]])
  )
  values[, feature_names, drop = FALSE]
}

app_joint_recursive_dgp_shard <- function(
  fixture, forecast_map, n_paths = 2048L, seed
) {
  n_paths <- as.integer(n_paths)
  if (n_paths <= 0L || nrow(forecast_map) <= 0L) {
    stop("DGP oracle shard geometry is invalid.", call. = FALSE)
  }
  old_seed <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
    get(".Random.seed", envir = .GlobalEnv)
  } else NULL
  on.exit({
    if (is.null(old_seed)) {
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
        rm(".Random.seed", envir = .GlobalEnv)
      }
    } else assign(".Random.seed", old_seed, envir = .GlobalEnv)
  }, add = TRUE)
  set.seed(as.integer(seed))

  sc <- fixture$registry_row
  feature_default <- app_joint_qvp_registry_default_beta(sc$dynamics_class[[1L]])
  beta_location <- app_joint_qvp_parse_named_numeric_spec(
    sc$beta_location[[1L]], feature_default
  )
  beta_scale <- app_joint_qvp_parse_named_numeric_spec(
    sc$beta_scale[[1L]], feature_default
  )
  response <- matrix(NA_real_, nrow = n_paths, ncol = nrow(forecast_map))
  origins <- unique(forecast_map$origin_index)
  for (origin_id in origins) {
    rows <- which(forecast_map$origin_index == origin_id)
    origin_time <- min(forecast_map$full_time_index[rows]) - 1L
    previous <- rep(fixture$y[[origin_time]], n_paths)
    for (row_index in rows) {
      tt <- forecast_map$full_time_index[[row_index]]
      z <- app_joint_recursive_dgp_feature_matrix(tt, previous, sc)
      mu <- as.numeric(sc$location_intercept[[1L]]) + as.vector(z %*% beta_location)
      sigma <- as.numeric(sc$scale_intercept[[1L]]) + as.vector(z %*% beta_scale)
      if (any(!is.finite(sigma)) || any(sigma <= 0)) {
        stop("DGP oracle recursion produced a nonpositive scale.", call. = FALSE)
      }
      innovation <- app_joint_qvp_registry_standardized_innovation(n_paths, sc)$standardized
      previous <- mu + sigma * innovation
      response[, row_index] <- previous
    }
  }
  if (any(!is.finite(response))) stop("DGP oracle shard is nonfinite.", call. = FALSE)
  list(
    scenario_id = fixture$scenario_id,
    seed = as.integer(seed),
    n_paths = n_paths,
    forecast_map = forecast_map,
    response = response
  )
}

app_joint_recursive_empirical_expected_check <- function(
  q, tau, sorted_y, prefix_y
) {
  q <- as.numeric(q)
  sorted_y <- as.numeric(sorted_y)
  prefix_y <- as.numeric(prefix_y)
  n <- length(sorted_y)
  if (n <= 0L || length(prefix_y) != n || any(!is.finite(c(q, sorted_y, prefix_y)))) {
    stop("Empirical expected-check inputs are malformed.", call. = FALSE)
  }
  below <- findInterval(q, sorted_y)
  lower_sum <- ifelse(below > 0L, prefix_y[pmax(below, 1L)], 0)
  total <- prefix_y[[n]]
  lower <- (1 - tau) * (below * q - lower_sum)
  upper <- tau * ((total - lower_sum) - (n - below) * q)
  (lower + upper) / n
}

app_joint_recursive_oracle_expected_matrix <- function(
  oracle, q, tau
) {
  q <- as.matrix(q)
  if (nrow(q) != ncol(oracle$sorted_response)) {
    stop("Oracle and quantile rows differ.", call. = FALSE)
  }
  out <- matrix(NA_real_, nrow = nrow(q), ncol = ncol(q))
  for (row_index in seq_len(nrow(q))) {
    out[row_index, ] <- app_joint_recursive_empirical_expected_check(
      q[row_index, ], tau,
      oracle$sorted_response[, row_index],
      oracle$prefix_response[, row_index]
    )
  }
  out
}

app_joint_recursive_oracle_point_score <- function(
  oracle, qhat, tau, weights
) {
  qhat <- as.matrix(qhat)
  if (ncol(qhat) != length(tau)) stop("Oracle point-score grid differs.", call. = FALSE)
  expected <- realized <- numeric(length(tau))
  for (k in seq_along(tau)) {
    expected[[k]] <- mean(app_joint_recursive_oracle_expected_matrix(
      oracle, matrix(qhat[, k], ncol = 1L), tau[[k]]
    ))
    realized[[k]] <- mean(app_joint_qdesn_postscore_check_loss(
      oracle$observed_y, qhat[, k], tau[[k]]
    ))
  }
  list(
    origin_marginal_dgp_integrated_acrps = sum(2 * weights * expected),
    realized_acrps = sum(2 * weights * realized),
    expected_check_loss_by_tau = expected,
    realized_check_loss_by_tau = realized
  )
}

app_joint_recursive_combine_oracle_shards <- function(
  shard_paths, fixture, tau, weights, analytic_tolerance = 0.01,
  split_half_tolerance = 0.0025
) {
  shards <- lapply(shard_paths, readRDS)
  if (length(shards) < 2L ||
      length(unique(vapply(shards, `[[`, character(1L), "scenario_id"))) != 1L) {
    stop("Oracle aggregation requires at least two same-scenario shards.", call. = FALSE)
  }
  reference_map <- shards[[1L]]$forecast_map
  if (any(!vapply(shards, function(x) identical(x$forecast_map, reference_map), logical(1L)))) {
    stop("Oracle shard forecast maps differ.", call. = FALSE)
  }
  response <- do.call(rbind, lapply(shards, `[[`, "response"))
  sorted <- apply(response, 2L, sort)
  prefix <- apply(sorted, 2L, cumsum)
  if (is.null(dim(prefix))) prefix <- matrix(prefix, ncol = 1L)
  probabilities <- as.numeric(tau)
  empirical_q <- t(apply(response, 2L, stats::quantile,
    probs = probabilities, names = FALSE, type = 8
  ))
  observed_y <- fixture$y[reference_map$full_time_index]
  oracle <- list(
    scenario_id = fixture$scenario_id,
    n_paths = nrow(response),
    shard_seeds = vapply(shards, `[[`, integer(1L), "seed"),
    forecast_map = reference_map,
    sorted_response = sorted,
    prefix_response = prefix,
    true_q = empirical_q,
    observed_y = observed_y,
    tau = tau,
    weights = weights
  )
  full_score <- app_joint_recursive_oracle_point_score(
    oracle, empirical_q, tau, weights
  )$origin_marginal_dgp_integrated_acrps

  split_groups <- split(seq_along(shards), rep(1:2, length.out = length(shards)))
  shard_scores <- vapply(split_groups, function(indices) {
    split_response <- do.call(rbind, lapply(shards[indices], `[[`, "response"))
    shard_sorted <- apply(split_response, 2L, sort)
    shard_prefix <- apply(shard_sorted, 2L, cumsum)
    if (is.null(dim(shard_prefix))) shard_prefix <- matrix(shard_prefix, ncol = 1L)
    shard_oracle <- oracle
    shard_oracle$sorted_response <- shard_sorted
    shard_oracle$prefix_response <- shard_prefix
    app_joint_recursive_oracle_point_score(
      shard_oracle, empirical_q, tau, weights
    )$origin_marginal_dgp_integrated_acrps
  }, numeric(1L))
  split_relative <- abs(diff(shard_scores)) / max(abs(mean(shard_scores)), 1e-12)

  h1 <- which(reference_map$horizon == 1L)
  q_h1 <- fixture$true_q[reference_map$full_time_index[h1], , drop = FALSE]
  empirical_h1 <- app_joint_recursive_oracle_point_score(
    within(oracle, {
      sorted_response <- sorted_response[, h1, drop = FALSE]
      prefix_response <- prefix_response[, h1, drop = FALSE]
      observed_y <- observed_y[h1]
    }), q_h1, tau, weights
  )$origin_marginal_dgp_integrated_acrps
  analytic_h1 <- app_joint_qdesn_postscore_score_matrix(
    q_h1,
    fixture$y[reference_map$full_time_index[h1]],
    fixture$mu[reference_map$full_time_index[h1]],
    fixture$sigma[reference_map$full_time_index[h1]],
    fixture$registry_row, tau, weights
  )$dgp_integrated_acrps
  analytic_relative <- abs(empirical_h1 - analytic_h1) / max(abs(analytic_h1), 1e-12)
  oracle$diagnostics <- data.frame(
    scenario_id = fixture$scenario_id,
    n_shards = length(shards),
    n_paths = nrow(response),
    oracle_score = full_score,
    split_half_score_1 = shard_scores[[1L]],
    split_half_score_2 = shard_scores[[2L]],
    split_half_relative_difference = split_relative,
    split_half_tolerance = split_half_tolerance,
    horizon1_empirical_score = empirical_h1,
    horizon1_analytic_score = analytic_h1,
    horizon1_relative_difference = analytic_relative,
    horizon1_tolerance = analytic_tolerance,
    status = if (split_relative <= split_half_tolerance &&
      analytic_relative <= analytic_tolerance) "pass" else "extend",
    stringsAsFactors = FALSE
  )
  oracle
}
