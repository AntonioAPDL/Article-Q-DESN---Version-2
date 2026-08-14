contract <- app_prediction_contract(cfg, model_family = "qdesn_glofas_discrepancy")
stopifnot(identical(contract$target, "reference_quantile_from_glofas_discrepancy"))
stopifnot(identical(contract$horizon_scope, "issued_glofas_only"))
stopifnot(identical(contract$q_g_source, "ensemble_empirical_quantile"))
stopifnot(identical(contract$discrepancy_feature_strategy, "origin_state_pilot"))
stopifnot(identical(contract$prediction_unit, "point_bridge"))
stopifnot(identical(contract$posterior_draw_contract, "q_y_draw_equals_q_g_draw_minus_d_g_draw"))
stopifnot(identical(app_prediction_contract_name(contract, "qdesn_glofas_discrepancy"),
  "pilot_origin_state_glofas_quantile_minus_discrepancy"
))

bad_cfg <- cfg
bad_cfg$prediction <- contract
bad_cfg$prediction$beyond_issued_horizon <- "recursive"
bad_msg <- tryCatch({
  app_prediction_contract(bad_cfg, model_family = "qdesn_glofas_discrepancy")
  NA_character_
}, error = function(e) conditionMessage(e))
stopifnot(grepl("Unsupported prediction contract value", bad_msg))

block <- data.frame(
  g_transformed = c(8, 10, 12),
  y_transformed = c(9, 9, 9),
  stringsAsFactors = FALSE
)
key <- data.frame(
  origin_date = as.Date("2026-01-01"),
  target_date = as.Date("2026-01-02"),
  horizon = 1L,
  stringsAsFactors = FALSE
)
raw_row <- data.frame(
  fit_id = "raw_fit",
  model_id = "raw_glofas",
  model_family = "raw_glofas",
  stringsAsFactors = FALSE
)
raw_pred <- app_make_raw_glofas_prediction_row(raw_row, key, block, p0 = 0.5, cfg = cfg)
stopifnot(identical(raw_pred$prediction_contract, "raw_glofas_ensemble_quantile"))
stopifnot(identical(raw_pred$discrepancy_feature_strategy, "none"))
stopifnot(identical(raw_pred$prediction_unit, "raw_point_baseline"))
stopifnot(is.na(raw_pred$d_g_hat))
stopifnot(abs(raw_pred$qhat - 10) < 1.0e-12)

disc_result <- list(
  fit_id = "disc_fit",
  model_id = "qdesn_discrepancy",
  model_family = "qdesn_glofas_discrepancy"
)
disc_pred <- app_make_discrepancy_prediction_row(
  result = disc_result,
  key_row = key,
  block = block,
  p0 = 0.5,
  q_g_hat = 10,
  d_g_hat = -2,
  feature_date = as.Date("2026-01-01"),
  cfg = cfg
)
stopifnot(abs(disc_pred$qhat - 12) < 1.0e-12)
stopifnot(abs(disc_pred$qhat - (disc_pred$q_g_hat - disc_pred$d_g_hat)) < 1.0e-12)
stopifnot(identical(disc_pred$prediction_unit, "point_bridge"))
stopifnot(identical(disc_pred$discrepancy_feature_date, as.Date("2026-01-01")))

pred <- rbind(raw_pred, disc_pred)
app_validate_prediction_table_contract(pred, final_launch = FALSE)

final_msg <- tryCatch({
  app_validate_prediction_table_contract(pred, final_launch = TRUE)
  NA_character_
}, error = function(e) conditionMessage(e))
stopifnot(grepl("Final launches cannot use prediction contracts", final_msg))

draw_cfg <- cfg
draw_cfg$prediction$prediction_unit <- "posterior_draw"
draw_cfg$prediction$q_g_source <- "ensemble_bayesian_bootstrap_quantile"
draw_cfg$prediction$discrepancy_feature_strategy <- "horizon_indexed_origin_state"
draw_contract <- app_prediction_contract(draw_cfg, model_family = "qdesn_glofas_discrepancy")
stopifnot(identical(app_prediction_contract_name(draw_contract, "qdesn_glofas_discrepancy"),
  "posterior_draw_glofas_quantile_minus_discrepancy"
))
raw_under_draw_contract <- app_prediction_contract(draw_cfg, model_family = "raw_glofas")
stopifnot(identical(raw_under_draw_contract$q_g_source, "ensemble_empirical_quantile"))
stopifnot(identical(raw_under_draw_contract$prediction_unit, "raw_point_baseline"))

bb <- app_ensemble_bayesian_bootstrap_quantiles(c(8, 10, 12, 14), 0.5, 20L, seed = 123)
stopifnot(length(bb) == 20L)
stopifnot(all(is.finite(bb)))
stopifnot(identical(bb, app_ensemble_bayesian_bootstrap_quantiles(c(8, 10, 12, 14), 0.5, 20L, seed = 123)))

draw_pred <- data.frame(
  draw_id = c("1", "2"),
  fit_id = "disc_fit",
  model_id = "qdesn_discrepancy",
  model_family = "qdesn_glofas_discrepancy",
  quantile_level = 0.5,
  origin_date = as.Date("2026-01-01"),
  target_date = as.Date("2026-01-02"),
  horizon = 1L,
  q_y_draw = c(11, 12),
  q_g_draw = c(10, 14),
  d_g_draw = c(-1, 2),
  prediction_contract = "posterior_draw_glofas_quantile_minus_discrepancy",
  contract_version = "0.2",
  q_g_source = "ensemble_bayesian_bootstrap_quantile",
  discrepancy_feature_strategy = "horizon_indexed_origin_state",
  prediction_unit = "posterior_draw",
  posterior_draw_contract = "q_y_draw_equals_q_g_draw_minus_d_g_draw",
  stringsAsFactors = FALSE
)
app_validate_posterior_draw_prediction_table(draw_pred)

recursive_draw_pred <- draw_pred
recursive_draw_pred$q_g_source <- "posterior_model_quantile"
recursive_draw_pred$discrepancy_feature_strategy <- "recursive_latent_path"
app_validate_posterior_draw_prediction_table(recursive_draw_pred)

bad_draw_pred <- draw_pred
bad_draw_pred$q_y_draw[[1L]] <- 99
draw_msg <- tryCatch({
  app_validate_posterior_draw_prediction_table(bad_draw_pred)
  NA_character_
}, error = function(e) conditionMessage(e))
stopifnot(grepl("q_y_draw = q_g_draw - d_g_draw", draw_msg, fixed = TRUE))
