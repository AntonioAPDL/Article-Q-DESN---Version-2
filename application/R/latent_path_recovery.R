# Synthetic recovery helpers for the latent-path AL-VB implementation.
#
# The recovery gate uses the same posterior-draw contract as the real GloFAS
# application, but it replaces the DESN feature map with a small known linear
# feature map. This isolates the latent future-path algebra, source-specific
# AL likelihood rows, and VB update wiring before any full Dec. 25 fit is run.

app_latent_path_recovery_config <- function(cfg) {
  cfg$synthetic_recovery %||% list()
}

app_latent_path_recovery_simulate <- function(cfg) {
  rec <- app_latent_path_recovery_config(cfg)
  app_simulate_glofas_latent_path_al(
    n_history = as.integer(rec$n_history %||% 120L),
    horizon = as.integer(rec$horizon %||% 5L),
    n_members = as.integer(rec$n_members %||% 30L),
    p0 = as.numeric(rec$p0 %||% 0.50),
    beta = as.numeric(unlist(rec$beta %||% c(0.25, 0.35, -0.08, 0.04, 0.08), use.names = FALSE)),
    alpha = as.numeric(unlist(rec$alpha %||% c(0.15, -0.06, 0.03, 0.02, -0.05), use.names = FALSE)),
    sigma_y = as.numeric(rec$sigma_y %||% 0.18),
    sigma_g = as.numeric(rec$sigma_g %||% 0.22),
    origin_date = as.Date(rec$origin_date %||% "2026-01-31"),
    seed = as.integer(rec$seed %||% 20260513L)
  )
}

app_latent_path_recovery_feature_jacobian <- function(n_history, horizon, t_abs) {
  J <- matrix(0, nrow = 5L, ncol = horizon)
  lag1 <- t_abs - 1L
  lag2 <- t_abs - 2L
  if (lag1 > n_history) J[2L, lag1 - n_history] <- 1
  if (lag2 > n_history) J[3L, lag2 - n_history] <- 1
  rownames(J) <- c("intercept", "y_lag_1", "y_lag_2", "ppt_lag_0", "soil_lag_0")
  J
}

app_make_latent_path_recovery_future_builder <- function(sim, n_history) {
  truth <- sim$truth
  horizon <- sum(as.logical(truth$is_future))
  future_idx <- n_history + seq_len(horizon)
  future_dates <- as.Date(truth$target_date[future_idx])
  ens <- sim$panel[sim$panel$is_ensemble, , drop = FALSE]
  key <- data.frame(
    target_date = future_dates,
    horizon = seq_len(horizon),
    stringsAsFactors = FALSE
  )
  key_id <- paste(key$target_date, key$horizon)
  ens_id <- paste(as.Date(ens$target_date), as.integer(ens$horizon))
  ens_future_index <- match(ens_id, key_id)
  if (any(is.na(ens_future_index))) {
    stop("Synthetic ensemble rows do not match the recovery future key.", call. = FALSE)
  }

  force(truth)
  force(n_history)
  function(y_future) {
    y_future <- as.numeric(y_future)
    if (length(y_future) != horizon) {
      stop("Synthetic recovery future path has the wrong length.", call. = FALSE)
    }
    y_work <- truth$y
    y_work[future_idx] <- y_future
    X_future <- t(vapply(future_idx, function(t_abs) {
      app_latent_path_truth_features(y_work, truth$ppt, truth$soil, t_abs)
    }, numeric(5L)))
    colnames(X_future) <- colnames(sim$X_truth)

    p_x <- ncol(X_future)
    H_y <- cbind(X_future, matrix(0, nrow = horizon, ncol = p_x))
    H_g_key <- cbind(X_future, X_future)
    colnames(H_y) <- c(paste0("beta__", colnames(X_future)), paste0("alpha__", colnames(X_future)))
    colnames(H_g_key) <- colnames(H_y)

    J_x <- lapply(future_idx, function(t_abs) {
      app_latent_path_recovery_feature_jacobian(n_history, horizon, t_abs)
    })
    J_y <- lapply(J_x, function(Jh) rbind(Jh, matrix(0, nrow = p_x, ncol = ncol(Jh))))
    J_g_key <- lapply(J_x, function(Jh) rbind(Jh, Jh))

    H_g <- H_g_key[ens_future_index, , drop = FALSE]
    J_g <- lapply(ens_future_index, function(i) J_g_key[[i]])
    row_info_y <- data.frame(
      source = "Y",
      row_role = "latent_future_usgs",
      future_index = seq_len(horizon),
      origin_date = as.Date(sim$cutoff$origin_date[[1L]]),
      target_date = key$target_date,
      horizon = key$horizon,
      member = NA_character_,
      stringsAsFactors = FALSE
    )
    row_info_g <- data.frame(
      source = "G",
      row_role = "synthetic_glofas_ensemble",
      future_index = ens_future_index,
      origin_date = as.Date(ens$origin_date),
      target_date = as.Date(ens$target_date),
      horizon = as.integer(ens$horizon),
      member = ens$member,
      stringsAsFactors = FALSE
    )
    row_info_g_key <- data.frame(
      source = "G",
      row_role = "synthetic_glofas_ensemble_key",
      future_index = seq_len(horizon),
      origin_date = as.Date(sim$cutoff$origin_date[[1L]]),
      target_date = key$target_date,
      horizon = key$horizon,
      member = NA_character_,
      stringsAsFactors = FALSE
    )
    list(
      X_future = X_future,
      H_y = H_y,
      H_g = H_g,
      H_g_key = H_g_key,
      g_future_index = ens_future_index,
      J_y = J_y,
      J_g = J_g,
      J_g_key = J_g_key,
      z_g = as.numeric(ens$g_transformed),
      row_info_y = row_info_y,
      row_info_g_key = row_info_g_key,
      row_info_g = row_info_g,
      feature_info = data.frame(
        column_name = colnames(X_future),
        block = c("intercept", "direct_output_lag", "direct_output_lag", "direct_covariate_lag", "direct_covariate_lag"),
        variable = c(NA, "y", "y", "ppt", "soil"),
        lag = c(NA, 1L, 2L, 0L, 0L),
        stringsAsFactors = FALSE
      )
    )
  }
}

app_make_latent_path_recovery_design <- function(sim, cfg = list()) {
  n_history <- sum(!as.logical(sim$truth$is_future))
  horizon <- sum(as.logical(sim$truth$is_future))
  hist_idx <- seq_len(n_history)
  X_hist <- as.matrix(sim$X_truth[hist_idx, , drop = FALSE])
  source <- factor(c(rep("Y", n_history), rep("G", n_history)), levels = c("Y", "G"))
  H_fixed <- app_make_augmented_discrepancy_design(rbind(X_hist, X_hist), source, rbind(X_hist, X_hist))
  hist_panel <- sim$panel[sim$panel$is_retrospective, , drop = FALSE]
  z_fixed <- c(sim$truth$y[hist_idx], hist_panel$g_transformed)
  row_info_fixed <- rbind(
    data.frame(
      source = "Y",
      row_role = "synthetic_historical_usgs",
      feature_row = hist_idx,
      origin_date = as.Date(hist_panel$origin_date),
      target_date = as.Date(hist_panel$target_date),
      horizon = 0L,
      member = NA_character_,
      is_future = FALSE,
      stringsAsFactors = FALSE
    ),
    data.frame(
      source = "G",
      row_role = "synthetic_historical_glofas_retrospective",
      feature_row = hist_idx,
      origin_date = as.Date(hist_panel$origin_date),
      target_date = as.Date(hist_panel$target_date),
      horizon = 0L,
      member = NA_character_,
      is_future = FALSE,
      stringsAsFactors = FALSE
    )
  )
  future_key <- data.frame(
    target_date = as.Date(sim$truth$target_date[n_history + seq_len(horizon)]),
    horizon = seq_len(horizon),
    stringsAsFactors = FALSE
  )
  y_future_init <- vapply(seq_len(horizon), function(h) {
    block <- sim$panel[sim$panel$is_ensemble & as.integer(sim$panel$horizon) == h, , drop = FALSE]
    stats::median(block$g_transformed, na.rm = TRUE) -
      stats::median(hist_panel$g_transformed - sim$truth$y[hist_idx], na.rm = TRUE)
  }, numeric(1L))
  y_future_init[!is.finite(y_future_init)] <- tail(sim$truth$y[hist_idx], 1L)

  p_x <- ncol(X_hist)
  out <- list(
    z_fixed = as.numeric(z_fixed),
    H_fixed = H_fixed,
    source_fixed = source,
    row_info_fixed = row_info_fixed,
    X_beta = X_hist,
    X_alpha = X_hist,
    X_base = X_hist,
    feature_info = data.frame(
      column_name = colnames(X_hist),
      block = c("intercept", "direct_output_lag", "direct_output_lag", "direct_covariate_lag", "direct_covariate_lag"),
      variable = c(NA, "y", "y", "ppt", "soil"),
      lag = c(NA, 1L, 2L, 0L, 0L),
      stringsAsFactors = FALSE
    ),
    future_key = future_key,
    y_future_init = y_future_init,
    y_future_oracle = sim$truth$y[n_history + seq_len(horizon)],
    future_builder = app_make_latent_path_recovery_future_builder(sim, n_history),
    beta_index = seq_len(p_x),
    alpha_index = p_x + seq_len(p_x),
    intercept_index = c(1L, p_x + 1L),
    p0 = sim$p0,
    design_version = "synthetic_latent_path_recovery_v0.1",
    application_model_contract = "latent_path_ensemble_likelihood",
    fit_id = sim$model_row$fit_id[[1L]],
    model_id = sim$model_row$model_id[[1L]],
    truth = list(
      beta = sim$beta,
      alpha = sim$alpha,
      sigma_y = sim$sigma_y,
      sigma_g = sim$sigma_g,
      q_y = sim$truth$q_y[n_history + seq_len(horizon)],
      q_g = sim$truth$q_g[n_history + seq_len(horizon)],
      delta = sim$truth$delta[n_history + seq_len(horizon)],
      y_future = sim$truth$y[n_history + seq_len(horizon)]
    )
  )
  class(out) <- "glofas_latent_path_design"
  app_validate_glofas_latent_path_design(out)
  out
}

app_latent_path_recovery_draw_table <- function(fit, design) {
  theta <- app_discrepancy_theta_draws(fit)
  y_draws <- as.matrix(fit$draws$y_future)
  H <- nrow(design$future_key)
  n_draw <- nrow(theta)
  rows <- vector("list", n_draw * H)
  k <- 1L
  for (s in seq_len(n_draw)) {
    future <- design$future_builder(y_draws[s, ])
    beta <- theta[s, design$beta_index]
    alpha <- theta[s, design$alpha_index]
    q_y <- as.numeric(future$X_future %*% beta)
    d_g <- as.numeric(future$X_future %*% alpha)
    q_g <- q_y + d_g
    for (h in seq_len(H)) {
      rows[[k]] <- data.frame(
        draw_index = s,
        target_date = design$future_key$target_date[[h]],
        horizon = design$future_key$horizon[[h]],
        q_y_draw = q_y[[h]],
        q_g_draw = q_g[[h]],
        d_g_draw = d_g[[h]],
        latent_y_draw = y_draws[s, h],
        identity_error = abs(q_y[[h]] - (q_g[[h]] - d_g[[h]])),
        stringsAsFactors = FALSE
      )
      k <- k + 1L
    }
  }
  do.call(rbind, rows)
}

app_latent_path_recovery_metrics <- function(fit, design, tolerances = list()) {
  theta_mean <- as.numeric(fit$summary$theta_mean)
  y_mean <- as.numeric(fit$summary$y_future_mean)
  future <- design$future_builder(y_mean)
  beta_hat <- theta_mean[design$beta_index]
  alpha_hat <- theta_mean[design$alpha_index]
  q_y_hat <- as.numeric(future$X_future %*% beta_hat)
  d_hat <- as.numeric(future$X_future %*% alpha_hat)
  q_g_hat <- q_y_hat + d_hat
  truth <- design$truth
  sigma_mean <- fit$summary$sigma_mean
  draw_table <- app_latent_path_recovery_draw_table(fit, design)
  rmse <- function(x) sqrt(mean(x^2, na.rm = TRUE))
  relerr <- function(est, ref) abs(est - ref) / max(abs(ref), 1.0e-8)
  metrics <- data.frame(
    n_history = nrow(design$X_base),
    n_future_dates = nrow(design$future_key),
    n_draws = nrow(fit$draws$theta),
    vb_converged = isTRUE(fit$vb_diagnostics$converged),
    vb_iterations = as.integer(fit$vb_diagnostics$iterations),
    q_y_rmse = rmse(q_y_hat - truth$q_y),
    q_g_rmse = rmse(q_g_hat - truth$q_g),
    discrepancy_rmse = rmse(d_hat - truth$delta),
    y_future_rmse = rmse(y_mean - truth$y_future),
    beta_l2_error = sqrt(sum((beta_hat - truth$beta)^2)),
    alpha_l2_error = sqrt(sum((alpha_hat - truth$alpha)^2)),
    sigma_y_relative_error = relerr(as.numeric(sigma_mean[["Y"]]), truth$sigma_y),
    sigma_g_relative_error = relerr(as.numeric(sigma_mean[["G"]]), truth$sigma_g),
    max_draw_identity_error = max(draw_table$identity_error),
    finite_draws = all(is.finite(as.matrix(draw_table[, c("q_y_draw", "q_g_draw", "d_g_draw", "latent_y_draw")]))),
    stringsAsFactors = FALSE
  )
  tol <- list(
    q_y_rmse = as.numeric(tolerances$q_y_rmse %||% Inf),
    q_g_rmse = as.numeric(tolerances$q_g_rmse %||% Inf),
    discrepancy_rmse = as.numeric(tolerances$discrepancy_rmse %||% Inf),
    y_future_rmse = as.numeric(tolerances$y_future_rmse %||% Inf),
    max_draw_identity_error = as.numeric(tolerances$max_draw_identity_error %||% 1.0e-8)
  )
  metrics$pass_q_y_rmse <- metrics$q_y_rmse <= tol$q_y_rmse
  metrics$pass_q_g_rmse <- metrics$q_g_rmse <= tol$q_g_rmse
  metrics$pass_discrepancy_rmse <- metrics$discrepancy_rmse <= tol$discrepancy_rmse
  metrics$pass_y_future_rmse <- metrics$y_future_rmse <= tol$y_future_rmse
  metrics$pass_draw_identity <- metrics$max_draw_identity_error <= tol$max_draw_identity_error
  metrics$passed <- with(metrics, finite_draws && pass_q_y_rmse && pass_q_g_rmse &&
    pass_discrepancy_rmse && pass_y_future_rmse && pass_draw_identity)
  metrics
}

app_latent_path_recovery_path_summary <- function(fit, design) {
  theta_mean <- as.numeric(fit$summary$theta_mean)
  y_mean <- as.numeric(fit$summary$y_future_mean)
  future <- design$future_builder(y_mean)
  beta_hat <- theta_mean[design$beta_index]
  alpha_hat <- theta_mean[design$alpha_index]
  q_y_hat <- as.numeric(future$X_future %*% beta_hat)
  d_hat <- as.numeric(future$X_future %*% alpha_hat)
  data.frame(
    target_date = design$future_key$target_date,
    horizon = design$future_key$horizon,
    y_future_mean = y_mean,
    y_future_truth = design$truth$y_future,
    q_y_hat = q_y_hat,
    q_y_truth = design$truth$q_y,
    q_g_hat = q_y_hat + d_hat,
    q_g_truth = design$truth$q_g,
    discrepancy_hat = d_hat,
    discrepancy_truth = design$truth$delta,
    stringsAsFactors = FALSE
  )
}
