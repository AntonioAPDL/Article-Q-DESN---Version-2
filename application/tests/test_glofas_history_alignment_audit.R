alignment_dates_full <- as.Date("2022-12-31") + 0:5
alignment_dates <- alignment_dates_full[-1L]
alignment_y_full <- c(0.9, 1.0, 1.3, 1.1, 1.8, 1.4)
alignment_d_full <- c(-0.1, -0.2, -0.4, -0.3, -0.8, -0.5)
alignment_y <- alignment_y_full[-1L]
alignment_d <- alignment_d_full[-1L]
alignment_g <- alignment_y + alignment_d
alignment_baseline <- alignment_d_full[-length(alignment_d_full)]
alignment_center <- mean(alignment_y_full)
alignment_scale <- stats::sd(alignment_y_full)
alignment_y_lag1 <- alignment_y_full[-length(alignment_y_full)]
alignment_X_beta <- cbind(intercept = 1, y_lag_1 = (alignment_y_lag1 - alignment_center) / alignment_scale)
alignment_X_alpha <- matrix(1, nrow = length(alignment_dates), ncol = 1L, dimnames = list(NULL, "intercept"))
alignment_n <- length(alignment_dates)

alignment_source_panel <- data.frame(
  origin_date = alignment_dates_full,
  target_date = alignment_dates_full,
  horizon = 0L,
  is_retrospective = TRUE,
  is_ensemble = FALSE,
  y_reference = expm1(alignment_y_full),
  g_glofas = expm1(alignment_y_full + alignment_d_full),
  y_transformed = alignment_y_full,
  g_transformed = alignment_y_full + alignment_d_full,
  stringsAsFactors = FALSE
)

alignment_design <- list(
  base_panel = data.frame(
    target_date = alignment_dates,
    y_transformed = alignment_y,
    g_transformed = alignment_g,
    stringsAsFactors = FALSE
  ),
  base_panel_full = data.frame(
    target_date = alignment_dates_full,
    y_transformed = alignment_y_full,
    g_transformed = alignment_y_full + alignment_d_full,
    stringsAsFactors = FALSE
  ),
  base_panel_disc_full = data.frame(
    target_date = alignment_dates_full,
    y_transformed = alignment_d_full,
    stringsAsFactors = FALSE
  ),
  row_info_fixed = data.frame(
    target_date = c(alignment_dates, alignment_dates),
    stringsAsFactors = FALSE
  ),
  z_fixed = c(alignment_y, alignment_g - alignment_baseline),
  X_beta = alignment_X_beta,
  X_alpha = alignment_X_alpha,
  feature_info_beta = data.frame(
    column_index = 1:2,
    column_name = c("intercept", "y_lag_1"),
    block = c("intercept", "direct_output_lag"),
    variable = c("intercept", "y"),
    lag = c(NA_integer_, 1L),
    stringsAsFactors = FALSE
  ),
  readout_scale_info = list(output_lags = list(
    columns = "y_lag_1",
    center = c(y_lag_1 = alignment_center),
    scale = c(y_lag_1 = alignment_scale)
  )),
  discrepancy_baseline_fixed = alignment_baseline,
  discrepancy_transition_strategy = "persistence_anchored_innovation",
  beta_index = 1:2,
  alpha_index = 3L
)

alignment_fit <- list(draws = list(theta = matrix(
  c(
    0.2, 0.7, 0.01,
    0.3, 0.6, 0.02,
    0.1, 0.8, 0.00,
    0.2, 0.7, 0.01
  ),
  nrow = 4L,
  byrow = TRUE
)))
alignment_theta <- alignment_fit$draws$theta
alignment_qy <- alignment_theta[, 1:2, drop = FALSE] %*% t(alignment_X_beta)
alignment_dg <- sweep(
  alignment_theta[, 3L, drop = FALSE] %*% t(alignment_X_alpha),
  2L,
  alignment_baseline,
  "+"
)
alignment_history <- data.frame(
  target_date = alignment_dates,
  y_reference = alignment_y,
  glofas_retrospective = alignment_g,
  observed_discrepancy = alignment_d,
  q_y_mean = colMeans(alignment_qy),
  q_y_median = apply(alignment_qy, 2L, stats::median),
  d_g_mean = colMeans(alignment_dg),
  d_g_median = apply(alignment_dg, 2L, stats::median),
  stringsAsFactors = FALSE
)

alignment_design_audit <- app_glofas_history_design_alignment_audit(alignment_design, alignment_history)
stopifnot(nrow(alignment_design_audit) >= 10L, all(alignment_design_audit$passed))

alignment_source_audit <- app_glofas_source_panel_alignment_audit(alignment_source_panel, alignment_design)
stopifnot(nrow(alignment_source_audit) == 12L, all(alignment_source_audit$passed))

alignment_export_audit <- app_glofas_history_export_reconstruction_audit(
  alignment_fit,
  alignment_design,
  alignment_history,
  recent_n = 4L
)
stopifnot(nrow(alignment_export_audit) == 4L, all(alignment_export_audit$passed))

persistence_history <- alignment_history
persistence_history$q_y_median <- app_glofas_alignment_lag_by_date(
  persistence_history$y_reference,
  persistence_history$target_date,
  1L
)
persistence_history$d_g_median <- app_glofas_alignment_lag_by_date(
  persistence_history$observed_discrepancy,
  persistence_history$target_date,
  1L
)
persistence_metrics <- app_glofas_history_alignment_metrics(
  persistence_history,
  windows = c(all = Inf)
)
stopifnot(all(persistence_metrics$closest_observed_alignment == "previous_day"))
stopifnot(all(abs(persistence_metrics$improvement_over_persistence_fraction) < 1.0e-12))

persistence_offsets <- app_glofas_history_offset_profile(persistence_history)
best_offsets <- vapply(
  split(persistence_offsets, persistence_offsets$series),
  function(x) x$observed_date_offset_days[[which.min(x$mae)]],
  integer(1L)
)
stopifnot(all(best_offsets == -1L))

innovation_diagnostics <- app_glofas_history_innovation_diagnostics(persistence_history)
stopifnot(all(abs(innovation_diagnostics$fitted_innovation_mean) < 1.0e-12))
stopifnot(all(abs(innovation_diagnostics$fitted_innovation_sd) < 1.0e-12))

shifted_history <- alignment_history
shifted_history$target_date <- shifted_history$target_date + 1L
shifted_audit <- app_glofas_history_design_alignment_audit(alignment_design, shifted_history)
stopifnot(!all(shifted_audit$passed))

shifted_source <- alignment_source_panel
shifted_source$target_date <- shifted_source$target_date + 1L
shifted_source_audit <- app_glofas_source_panel_alignment_audit(shifted_source, alignment_design)
stopifnot(!all(shifted_source_audit$passed))

altered_history <- alignment_history
altered_history$q_y_median[[nrow(altered_history)]] <- altered_history$q_y_median[[nrow(altered_history)]] + 0.1
altered_export <- app_glofas_history_export_reconstruction_audit(
  alignment_fit,
  alignment_design,
  altered_history,
  recent_n = 4L
)
stopifnot(!all(altered_export$passed))

alignment_plot <- tempfile("glofas_history_alignment_", fileext = ".pdf")
app_plot_glofas_history_alignment(alignment_history, alignment_plot, recent_n = 5L)
stopifnot(file.exists(alignment_plot), file.info(alignment_plot)$size > 1000)
