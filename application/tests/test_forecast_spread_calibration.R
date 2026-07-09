toy_spread_predictions <- data.frame(
  model_id = "qdesn_toy",
  model_family = "qdesn_glofas_discrepancy",
  origin_date = as.Date("2026-01-01"),
  target_date = rep(as.Date("2026-01-01") + 1:2, each = 5L),
  horizon = rep(1:2, each = 5L),
  quantile_level = rep(c(0.05, 0.15, 0.50, 0.80, 0.95), 2L),
  qhat = c(4.0, 4.2, 5.0, 5.6, 6.0, 4.5, 4.8, 5.5, 6.0, 6.5),
  qhat_monotone = c(4.0, 4.2, 5.0, 5.6, 6.0, 4.5, 4.8, 5.5, 6.0, 6.5),
  y_reference = rep(c(6.4, 4.3), each = 5L),
  stringsAsFactors = FALSE
)

toy_intervals <- list(
  list(lower = 0.05, upper = 0.95, nominal = 0.90),
  list(lower = 0.15, upper = 0.80, nominal = 0.65)
)
toy_cfg <- list(scoring = list(intervals = toy_intervals))

miss <- app_interval_miss_rows(toy_spread_predictions, toy_intervals)
stopifnot(nrow(miss) == 4L)
stopifnot(any(miss$miss_direction == "above_upper"))
stopifnot(any(miss$miss_direction == "below_lower"))

cal <- app_centered_spread_calibrate(
  toy_spread_predictions,
  factor = 2,
  additive_width = 0,
  calibration_id = "toy_x2"
)
stopifnot(all(cal$spread_calibration_id == "toy_x2"))
stopifnot(all(cal$qhat_monotone[cal$quantile_level == 0.50] == toy_spread_predictions$qhat_monotone[toy_spread_predictions$quantile_level == 0.50]))
stopifnot(all(diff(cal$qhat_monotone[cal$horizon == 1L]) >= -1e-12))
stopifnot(max(cal$qhat_monotone[cal$horizon == 1L]) > max(toy_spread_predictions$qhat_monotone[toy_spread_predictions$horizon == 1L]))

grid <- app_score_spread_calibration_grid(
  toy_spread_predictions,
  toy_cfg,
  factors = c(1, 2),
  additive_widths = 0
)
stopifnot(nrow(grid$score_summary) == 2L)
stopifnot(all(c("spread_calibration_factor", "spread_calibration_additive_width") %in% names(grid$score_summary)))
stopifnot(any(grid$score_summary$spread_calibration_factor == 2))

noop <- app_apply_spread_calibration_to_predictions(
  app_synthesize_quantile_grid(toy_spread_predictions),
  list(enabled = FALSE)
)
stopifnot(identical(noop$predictions$qhat_monotone, app_synthesize_quantile_grid(toy_spread_predictions)$qhat_monotone))
stopifnot(!noop$manifest$enabled[[1L]])

enabled_cfg <- app_spread_calibration_config(list(
  synthesis = list(
    spread_calibration = list(
      enabled = TRUE,
      factor = 2,
      additive_width = 0,
      calibration_id = "toy_enabled"
    )
  )
))
applied <- app_apply_spread_calibration_to_predictions(
  app_synthesize_quantile_grid(toy_spread_predictions),
  enabled_cfg
)
stopifnot(applied$manifest$enabled[[1L]])
stopifnot(applied$manifest$n_rows_calibrated == nrow(toy_spread_predictions))
stopifnot("qhat_monotone_uncalibrated" %in% names(applied$predictions))
stopifnot(max(applied$predictions$qhat_monotone) > max(applied$predictions$qhat_monotone_uncalibrated))

toy_draws <- data.frame(
  model_id = "qdesn_toy",
  model_family = "qdesn_glofas_discrepancy",
  quantile_level = rep(c(0.05, 0.50), each = 4L),
  horizon = rep(rep(1:2, each = 2L), 2L),
  q_y_draw = c(1.0, 1.2, 2.0, 2.4, 1.5, 1.7, 2.5, 2.9),
  q_g_draw = c(1.4, 1.5, 2.3, 2.6, 1.8, 2.0, 2.8, 3.1),
  d_g_draw = c(0.4, 0.3, 0.3, 0.2, 0.3, 0.3, 0.3, 0.2),
  stringsAsFactors = FALSE
)
draw_summary <- app_posterior_draw_spread_summary(toy_draws)
stopifnot(nrow(draw_summary) == 4L)
stopifnot(all(draw_summary$n_draws == 2L))
stopifnot(all(is.finite(draw_summary$q_y_draw_sd)))
