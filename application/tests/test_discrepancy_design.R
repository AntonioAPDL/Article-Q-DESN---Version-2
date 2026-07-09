toy_panel_discrepancy <- data.frame(
  origin_date = as.Date(rep("2026-01-01", 5L)),
  target_date = as.Date("2026-01-01") + 0:4,
  horizon = rep(0L, 5L),
  member = NA_character_,
  is_retrospective = TRUE,
  is_ensemble = FALSE,
  y_reference = c(10, 11, 12, 13, 14),
  g_glofas = c(9, 12, 11, NA, 15),
  y_transformed = c(10, 11, 12, 13, 14),
  g_transformed = c(9, 12, 11, NA, 15),
  split = "train",
  cutoff_id = "toy",
  stringsAsFactors = FALSE
)
toy_cutoff <- data.frame(
  cutoff_id = "toy",
  origin_date = as.Date("2026-01-05"),
  train_start = as.Date("2026-01-01"),
  train_end = as.Date("2026-01-04"),
  eval_start = as.Date("2026-01-05"),
  eval_end = as.Date("2026-01-05"),
  horizon_min = 1L,
  horizon_max = 1L,
  split = "toy",
  enabled = TRUE,
  notes = "",
  stringsAsFactors = FALSE
)
toy_model_row <- data.frame(
  fit_id = "toy_fit",
  model_id = "toy_model",
  model_family = "qdesn_glofas_discrepancy",
  quantile_level = 0.5,
  inference_method = "vb_ld",
  coefficient_prior = "rhs",
  reservoir_seed = 1L,
  required = TRUE,
  enabled = TRUE,
  config_hash = "toy",
  notes = "",
  stringsAsFactors = FALSE
)

X_toy <- cbind(bias = 1, trend = seq_len(nrow(toy_panel_discrepancy)))
design <- app_make_glofas_discrepancy_data(
  panel = toy_panel_discrepancy,
  cfg = cfg,
  cutoff_row = toy_cutoff,
  model_row = toy_model_row,
  X_base = X_toy[seq_len(4L), , drop = FALSE]
)

app_validate_glofas_discrepancy_data(design)
stopifnot(inherits(design, "glofas_discrepancy_design"))
stopifnot(identical(as.numeric(design$p0), 0.5))
stopifnot(nrow(design$X_base) == 4L)
stopifnot(length(design$z) == 7L)
stopifnot(sum(design$source == "Y") == 4L)
stopifnot(sum(design$source == "G") == 3L)
stopifnot(all(design$intercept_index == c(1L, 3L)))

p <- ncol(design$X_base)
y_rows <- as.character(design$source) == "Y"
g_rows <- as.character(design$source) == "G"
stopifnot(all(design$H[y_rows, p + seq_len(p), drop = FALSE] == 0))
stopifnot(isTRUE(all.equal(
  design$H[g_rows, seq_len(p), drop = FALSE],
  design$H[g_rows, p + seq_len(p), drop = FALSE],
  check.attributes = FALSE
)))
summary_row <- app_discrepancy_design_summary(design)
stopifnot(summary_row$n_stacked_rows == length(design$z))
stopifnot(summary_row$n_augmented_features == ncol(design$H))
stopifnot(nchar(summary_row$design_hash) == 64L)

toy_ensemble <- data.frame(
  origin_date = as.Date(rep("2026-01-02", 4L)),
  target_date = as.Date(rep("2026-01-03", 4L)),
  horizon = rep(1L, 4L),
  member = sprintf("m%02d", 1:4),
  is_retrospective = FALSE,
  is_ensemble = TRUE,
  y_reference = rep(12, 4L),
  g_glofas = c(10, 11, 13, 14),
  y_transformed = rep(12, 4L),
  g_transformed = c(10, 11, 13, 14),
  split = "eval",
  cutoff_id = "toy",
  stringsAsFactors = FALSE
)
theta_known <- c(beta_1 = 0, beta_2 = 0, alpha_1 = 2, alpha_2 = 0.5)
fake_result <- list(
  fit_id = "toy_fit",
  model_id = "toy_model",
  model_family = "qdesn_glofas_discrepancy",
  quantile_level = 0.5,
  fit = list(summary = list(theta_mean = theta_known)),
  design = design
)
pred <- app_predict_qdesn_discrepancy(
  result = fake_result,
  panel = rbind(toy_panel_discrepancy, toy_ensemble),
  cfg = cfg,
  model_row = toy_model_row
)
expected_discrepancy <- as.numeric(X_toy[2L, , drop = FALSE] %*% theta_known[design$alpha_index])
stopifnot(nrow(pred) == 1L)
stopifnot(abs(pred$raw_glofas_quantile - 12) < 1.0e-12)
stopifnot(abs(pred$discrepancy_hat - expected_discrepancy) < 1.0e-12)
stopifnot(abs(pred$q_g_hat - 12) < 1.0e-12)
stopifnot(abs(pred$d_g_hat - expected_discrepancy) < 1.0e-12)
stopifnot(abs(pred$qhat - (12 - expected_discrepancy)) < 1.0e-12)
stopifnot(identical(pred$prediction_contract, "pilot_origin_state_glofas_quantile_minus_discrepancy"))
stopifnot(identical(pred$discrepancy_feature_strategy, "origin_state_pilot"))
stopifnot(identical(pred$prediction_unit, "point_bridge"))
stopifnot(identical(pred$posterior_draw_contract, "q_y_draw_equals_q_g_draw_minus_d_g_draw"))
stopifnot(identical(pred$discrepancy_feature_date, as.Date("2026-01-02")))

draw_cfg <- cfg
draw_cfg$prediction$prediction_unit <- "posterior_draw"
draw_cfg$prediction$q_g_source <- "ensemble_bayesian_bootstrap_quantile"
draw_cfg$prediction$discrepancy_feature_strategy <- "horizon_indexed_origin_state"
draw_cfg$prediction$contract_version <- "0.3"
draw_cfg$forecast_protocol$default_horizon_max <- 2L

toy_ensemble_leaky <- toy_ensemble
toy_ensemble_leaky$y_transformed <- 999
draw_design <- app_make_glofas_discrepancy_data(
  panel = rbind(toy_panel_discrepancy, toy_ensemble_leaky),
  cfg = draw_cfg,
  cutoff_row = toy_cutoff,
  model_row = toy_model_row,
  X_base = X_toy[seq_len(4L), , drop = FALSE],
  include_ensemble_training = FALSE,
  feature_strategy = "horizon_indexed_origin_state"
)
app_validate_glofas_discrepancy_data(draw_design)
stopifnot(identical(draw_design$feature_strategy, "horizon_indexed_origin_state"))
stopifnot(ncol(draw_design$X_base) == ncol(X_toy) + 1L)
stopifnot(sum(draw_design$row_info$is_ensemble) == 0L)
stopifnot(!any(draw_design$z == 999))
stopifnot(!any(draw_design$row_info$target_date > toy_cutoff$train_end[[1L]]))

theta_draws <- rbind(
  c(beta_1 = 1.0, beta_2 = 0.10, beta_3 = 0.00, alpha_1 = 2.0, alpha_2 = 0.50, alpha_3 = 1.00),
  c(beta_1 = 2.0, beta_2 = 0.20, beta_3 = 0.50, alpha_1 = -1.0, alpha_2 = 0.25, alpha_3 = -0.50)
)
fake_draw_result <- list(
  fit_id = "toy_draw_fit",
  model_id = "toy_draw_model",
  model_family = "qdesn_glofas_discrepancy",
  quantile_level = 0.5,
  fit = list(draws = list(theta = theta_draws)),
  design = draw_design
)
draw_pred <- app_predict_qdesn_discrepancy_draws(
  result = fake_draw_result,
  panel = rbind(toy_panel_discrepancy, toy_ensemble),
  cfg = draw_cfg,
  model_row = toy_model_row
)
stopifnot(nrow(draw_pred$draws) == nrow(theta_draws))
stopifnot(nrow(draw_pred$summary) == 1L)
stopifnot(identical(draw_pred$draws$q_g_source, rep("ensemble_bayesian_bootstrap_quantile", nrow(theta_draws))))
stopifnot(identical(draw_pred$draws$discrepancy_feature_strategy, rep("horizon_indexed_origin_state", nrow(theta_draws))))
stopifnot(all(abs(draw_pred$draws$q_y_draw - (draw_pred$draws$q_g_draw - draw_pred$draws$d_g_draw)) < 1.0e-12))
stopifnot(abs(draw_pred$summary$qhat - mean(draw_pred$draws$q_y_draw)) < 1.0e-12)
stopifnot(abs(draw_pred$summary$q_g_hat - mean(draw_pred$draws$q_g_draw)) < 1.0e-12)
stopifnot(abs(draw_pred$summary$d_g_hat - mean(draw_pred$draws$d_g_draw)) < 1.0e-12)
stopifnot(abs(draw_pred$summary$qhat - (draw_pred$summary$q_g_hat - draw_pred$summary$d_g_hat)) < 1.0e-12)
stopifnot(abs(draw_pred$summary$raw_glofas_quantile - 12) < 1.0e-12)
stopifnot(identical(draw_pred$summary$prediction_contract, "posterior_draw_glofas_quantile_minus_discrepancy"))
stopifnot(identical(draw_pred$summary$qhat_summary, "posterior_draw_mean"))
stopifnot(all(is.finite(draw_pred$draws$q_y_model_draw)))
stopifnot(all(is.finite(draw_pred$draws$q_g_model_draw)))
diag_row <- app_discrepancy_fit_diagnostics(fake_draw_result)
stopifnot(diag_row$n_draws == nrow(theta_draws))
stopifnot(diag_row$n_theta == ncol(theta_draws))
stopifnot(isTRUE(diag_row$finite_theta))
draw_check <- app_discrepancy_prediction_draw_checks(draw_pred$draws)
stopifnot(draw_check$n_draw_rows == nrow(draw_pred$draws))
stopifnot(isTRUE(draw_check$all_identity_errors_within_tolerance))

bad_design <- design
bad_design$H[g_rows, p + 1L] <- bad_design$H[g_rows, p + 1L] + 1
bad_msg <- tryCatch(
  {
    app_validate_glofas_discrepancy_data(bad_design)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("G-source rows", bad_msg, fixed = TRUE))

fit_cfg <- cfg
fit_cfg$inference$diagnostic_likelihood_family <- "al"
fit_cfg$inference$mcmc <- list(
  n_iter = 8L,
  burn_in = 4L,
  thin = 1L,
  rhs_tau0 = 1.0,
  rhs_slab_s2 = 4.0,
  rhs_a_zeta = 2.0,
  rhs_b_zeta = 4.0,
  rhs_n_inner = 1L,
  intercept_prec = 1.0e-9,
  sigma_a = 2.0,
  sigma_b = 1.0
)
fit_model_row <- toy_model_row
fit_model_row$inference_method <- "mcmc"
engine_report_for_fit <- app_check_qdesn_engine_api(
  fit_cfg,
  require_discrepancy = TRUE,
  stop_on_failure = FALSE
)
if (isTRUE(engine_report_for_fit$ok)) {
  fit_result <- app_fit_qdesn_discrepancy(
    panel = toy_panel_discrepancy,
    cfg = fit_cfg,
    model_row = fit_model_row,
    cutoff_row = toy_cutoff,
    X_base = X_toy[seq_len(4L), , drop = FALSE]
  )
  stopifnot(identical(fit_result$status, "completed"))
  stopifnot(inherits(fit_result$fit, "qdesn_discrepancy_fit"))
  stopifnot(identical(fit_result$method, "mcmc"))
  stopifnot(identical(fit_result$likelihood_family, "al"))
  stopifnot(isTRUE(all(is.finite(fit_result$fit$samp.theta))))
  stopifnot(isTRUE(all(is.finite(fit_result$fit$samp.sigma))))
  stopifnot(nrow(fit_result$fit$samp.theta) == fit_cfg$inference$mcmc$n_iter)
} else {
  message("Skipping discrepancy fit adapter test because the Q-DESN discrepancy engine is unavailable.")
}
