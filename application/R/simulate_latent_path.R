# Synthetic data generator for the latent-path GloFAS application model.

app_latent_path_al_constants <- function(p0) {
  p0 <- as.numeric(p0)
  if (!is.finite(p0) || p0 <= 0 || p0 >= 1) stop("p0 must lie in (0, 1).", call. = FALSE)
  list(
    A = (1 - 2 * p0) / (p0 * (1 - p0)),
    B = 2 / (p0 * (1 - p0))
  )
}

app_ral_location <- function(n, location, sigma, p0) {
  n <- as.integer(n)
  location <- rep(as.numeric(location), length.out = n)
  sigma <- as.numeric(sigma)
  if (!is.finite(sigma) || sigma <= 0) stop("sigma must be positive.", call. = FALSE)
  con <- app_latent_path_al_constants(p0)
  v <- stats::rexp(n, rate = 1 / sigma)
  z <- stats::rnorm(n)
  location + con$A * v + sqrt(sigma * con$B * v) * z
}

app_latent_path_truth_features <- function(y, ppt, soil, t) {
  y_lag_1 <- if (t > 1L) y[[t - 1L]] else 0
  y_lag_2 <- if (t > 2L) y[[t - 2L]] else 0
  c(
    intercept = 1,
    y_lag_1 = y_lag_1,
    y_lag_2 = y_lag_2,
    ppt_lag_0 = ppt[[t]],
    soil_lag_0 = soil[[t]]
  )
}

app_simulate_glofas_latent_path_al <- function(
  n_history = 80L,
  horizon = 6L,
  n_members = 10L,
  p0 = 0.50,
  beta = c(0.2, 0.45, -0.10, 0.06, 0.12),
  alpha = c(0.15, -0.10, 0.04, 0.03, -0.08),
  sigma_y = 0.15,
  sigma_g = 0.20,
  origin_date = as.Date("2026-01-31"),
  seed = 20260513L
) {
  n_history <- as.integer(n_history)
  horizon <- as.integer(horizon)
  n_members <- as.integer(n_members)
  if (n_history < 3L) stop("n_history must be at least 3.", call. = FALSE)
  if (horizon < 1L) stop("horizon must be positive.", call. = FALSE)
  if (n_members < 1L) stop("n_members must be positive.", call. = FALSE)
  beta <- as.numeric(beta)
  alpha <- as.numeric(alpha)
  if (length(beta) != 5L || length(alpha) != 5L) {
    stop("Synthetic latent-path beta and alpha must have length five.", call. = FALSE)
  }

  old_seed <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) get(".Random.seed", envir = .GlobalEnv) else NULL
  on.exit({
    if (is.null(old_seed)) {
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
    } else {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(as.integer(seed))

  n_total <- n_history + horizon
  dates <- seq(as.Date(origin_date) - n_history + 1L, by = "day", length.out = n_total)
  tt <- seq_len(n_total)
  ppt <- pmax(0, 0.8 + 0.3 * sin(2 * pi * tt / 13) + stats::rnorm(n_total, 0, 0.15))
  soil <- numeric(n_total)
  soil[[1L]] <- 0.2 + stats::rnorm(1L, 0, 0.05)
  for (t in 2:n_total) soil[[t]] <- 0.75 * soil[[t - 1L]] + 0.08 * ppt[[t]] + stats::rnorm(1L, 0, 0.04)

  y <- numeric(n_total)
  q_y <- numeric(n_total)
  delta <- numeric(n_total)
  q_g <- numeric(n_total)
  X <- matrix(NA_real_, nrow = n_total, ncol = 5L)
  colnames(X) <- names(app_latent_path_truth_features(c(0, 0, 0), c(0, 0, 0), c(0, 0, 0), 1L))
  for (t in seq_len(n_total)) {
    x_t <- app_latent_path_truth_features(y, ppt, soil, t)
    X[t, ] <- x_t
    q_y[[t]] <- sum(x_t * beta)
    delta[[t]] <- sum(x_t * alpha)
    q_g[[t]] <- q_y[[t]] + delta[[t]]
    y[[t]] <- app_ral_location(1L, q_y[[t]], sigma_y, p0)
  }

  g_retro <- app_ral_location(n_history, q_g[seq_len(n_history)], sigma_g, p0)
  future_idx <- n_history + seq_len(horizon)
  g_ens <- matrix(NA_real_, nrow = horizon, ncol = n_members)
  for (h in seq_len(horizon)) {
    g_ens[h, ] <- app_ral_location(n_members, q_g[[future_idx[[h]]]], sigma_g, p0)
  }

  hist_panel <- data.frame(
    origin_date = rep(as.Date(origin_date), n_history),
    target_date = dates[seq_len(n_history)],
    horizon = rep(0L, n_history),
    member = NA_character_,
    is_retrospective = TRUE,
    is_ensemble = FALSE,
    y_transformed = y[seq_len(n_history)],
    g_transformed = g_retro,
    split = "train",
    cutoff_id = "synthetic",
    ppt = ppt[seq_len(n_history)],
    soil = soil[seq_len(n_history)],
    stringsAsFactors = FALSE
  )
  ens_panel <- do.call(rbind, lapply(seq_len(horizon), function(h) {
    data.frame(
      origin_date = rep(as.Date(origin_date), n_members),
      target_date = rep(dates[[future_idx[[h]]]], n_members),
      horizon = rep(h, n_members),
      member = sprintf("m%03d", seq_len(n_members)),
      is_retrospective = FALSE,
      is_ensemble = TRUE,
      y_transformed = rep(y[[future_idx[[h]]]], n_members),
      g_transformed = g_ens[h, ],
      split = "eval",
      cutoff_id = "synthetic",
      ppt = rep(ppt[[future_idx[[h]]]], n_members),
      soil = rep(soil[[future_idx[[h]]]], n_members),
      stringsAsFactors = FALSE
    )
  }))
  panel <- rbind(hist_panel, ens_panel)

  cutoff <- data.frame(
    cutoff_id = "synthetic",
    origin_date = as.Date(origin_date),
    train_start = dates[[1L]],
    train_end = dates[[n_history]],
    eval_start = dates[[n_history + 1L]],
    eval_end = dates[[n_total]],
    horizon_min = 1L,
    horizon_max = horizon,
    split = "synthetic",
    enabled = TRUE,
    notes = "Synthetic latent-path AL validation data.",
    stringsAsFactors = FALSE
  )
  model_row <- data.frame(
    fit_id = "synthetic_latent_path_al",
    model_id = "synthetic_latent_path_al",
    model_family = "qdesn_glofas_discrepancy",
    quantile_level = p0,
    inference_method = "vb",
    coefficient_prior = "rhs",
    reservoir_seed = seed,
    required = TRUE,
    enabled = TRUE,
    config_hash = "synthetic",
    notes = "",
    stringsAsFactors = FALSE
  )
  truth <- data.frame(
    target_date = dates,
    is_future = seq_len(n_total) > n_history,
    y = y,
    q_y = q_y,
    delta = delta,
    q_g = q_g,
    ppt = ppt,
    soil = soil,
    stringsAsFactors = FALSE
  )
  list(
    panel = panel,
    cutoff = cutoff,
    model_row = model_row,
    truth = truth,
    X_truth = X,
    beta = beta,
    alpha = alpha,
    sigma_y = sigma_y,
    sigma_g = sigma_g,
    p0 = p0,
    seed = seed
  )
}
