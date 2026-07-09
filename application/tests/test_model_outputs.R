tmp_out <- tempfile("qdesn_model_outputs_")
dir.create(tmp_out, recursive = TRUE)

pred <- data.frame(
  fit_id = rep(c("raw_p10", "raw_p50", "raw_p90", "disc_p10", "disc_p50", "disc_p90"), each = 3L),
  model_id = rep(c("raw_glofas", "raw_glofas", "raw_glofas", "qdesn_diag", "qdesn_diag", "qdesn_diag"), each = 3L),
  model_family = rep(c("raw_glofas", "raw_glofas", "raw_glofas", "qdesn_glofas_discrepancy", "qdesn_glofas_discrepancy", "qdesn_glofas_discrepancy"), each = 3L),
  quantile_level = rep(c(0.10, 0.50, 0.90, 0.10, 0.50, 0.90), each = 3L),
  origin_date = as.Date("2026-01-01"),
  target_date = rep(as.Date("2026-01-01") + 1:3, 6L),
  horizon = rep(1:3, 6L),
  qhat = c(
    0.8, 0.9, 1.0,
    1.0, 1.1, 1.2,
    1.2, 1.3, 1.4,
    0.7, 0.8, 0.9,
    1.0, 1.1, 1.2,
    1.3, 1.4, 1.5
  ),
  y_reference = rep(c(1.05, 1.00, 1.35), 6L),
  stringsAsFactors = FALSE
)
draws <- data.frame(
  draw_id = rep(sprintf("draw_%02d", 1:4), each = 3L),
  fit_id = "disc_p50",
  model_id = "qdesn_diag",
  model_family = "qdesn_glofas_discrepancy",
  quantile_level = 0.50,
  origin_date = as.Date("2026-01-01"),
  target_date = rep(as.Date("2026-01-01") + 1:3, 4L),
  horizon = rep(1:3, 4L),
  q_y_draw = rep(c(1.0, 1.1, 1.2), 4L),
  q_g_draw = rep(c(1.2, 1.4, 1.5), 4L),
  d_g_draw = rep(c(0.2, 0.3, 0.3), 4L),
  prediction_contract = "posterior_draw_glofas_quantile_minus_discrepancy",
  contract_version = "0.3",
  forecast_scope = "issued_glofas_only",
  q_g_source = "posterior_model_quantile",
  discrepancy_feature_strategy = "horizon_indexed_origin_state",
  prediction_unit = "posterior_draw",
  posterior_draw_contract = "q_y_draw_equals_q_g_draw_minus_d_g_draw",
  posterior_predictive_sampling = "disabled",
  beyond_issued_horizon = "disabled",
  stringsAsFactors = FALSE
)
figs <- app_make_model_diagnostic_figures(pred, draws, tmp_out)
stopifnot(length(figs) == 2L)
stopifnot(all(file.exists(figs)))
stopifnot(all(file.info(figs)$size > 1000))
