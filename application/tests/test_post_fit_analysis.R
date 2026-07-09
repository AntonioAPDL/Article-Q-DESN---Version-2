tmp_post <- tempfile("qdesn_post_fit_")
dir.create(tmp_post, recursive = TRUE)

pcfg <- app_post_analysis_config(list(post_analysis = list(
  credible_level = 0.95,
  trace_skip = 2,
  recent_history_n = 2,
  history_chunk_size = 2,
  coefficient_forest = list(top_k = 2)
)))

theta <- matrix(
  c(
    1.0, 0.0, 0.20, 0.10,
    1.1, 0.1, 0.30, 0.00,
    0.9, 0.2, 0.10, 0.20,
    1.0, 0.1, 0.25, 0.05
  ),
  nrow = 4L,
  byrow = TRUE
)
fit_al <- list(
  method = "vb",
  likelihood_family = "al",
  draws = list(
    theta = theta,
    sigma = matrix(c(1.0, 1.2, 1.1, 1.3, 0.9, 1.1, 1.0, 1.0), ncol = 2L),
    gamma = matrix(0, nrow = 4L, ncol = 2L)
  ),
  diagnostics = list(
    elbo_trace = c(-10, -8, -7, -6),
    relative_change_trace = c(1, 0.4, 0.1, 0.01),
    max_parameter_change_trace = c(2, 1, 0.2, 0.02)
  ),
  beta_prior = list(state = list(tau2 = 1.0e-8, zeta2 = 4, lambda2 = c(1, 2, 3), iter = 4L))
)

design <- list(
  X_base = matrix(c(1, 0, 1, 1, 1, 2), ncol = 2L, byrow = TRUE),
  beta_index = 1:2,
  alpha_index = 3:4,
  base_panel = data.frame(
    origin_date = as.Date("2022-01-01") + 0:2,
    target_date = as.Date("2022-01-01") + 0:2,
    horizon = 0L,
    y_transformed = c(1.0, 1.5, 2.0),
    g_transformed = c(1.2, 1.7, 2.4),
    stringsAsFactors = FALSE
  )
)
colnames(design$X_base) <- c("bias", "lag1")
fit_row <- data.frame(
  fit_id = "fit_test",
  model_id = "model_test",
  model_family = "qdesn_glofas_discrepancy",
  quantile_level = 0.50,
  method = "vb",
  likelihood_family = "al",
  stringsAsFactors = FALSE
)

bundle <- app_post_fit_draw_bundle(fit_al, design, as.list(fit_row))
stopifnot(!isTRUE(bundle$gamma_active))
hist_sum <- app_post_fit_history_summary(bundle, design, fit_row, pcfg)
stopifnot(nrow(hist_sum) == 3L)
stopifnot(all.equal(hist_sum$observed_discrepancy, c(0.2, 0.2, 0.4)))
stopifnot(all(is.finite(hist_sum$q_y_median)))
stopifnot(all(is.finite(hist_sum$d_g_median)))
recent <- app_post_fit_recent_history(hist_sum, 2L)
stopifnot(nrow(recent) == 2L)
stopifnot(identical(as.character(recent$target_date[[1L]]), "2022-01-02"))
since_default <- app_post_fit_since_history(hist_sum, pcfg$discrepancy_history_since)
stopifnot(nrow(since_default) == 3L)
pcfg_since <- app_post_analysis_config(list(post_analysis = list(discrepancy_history_since = "2022-01-02")))
since_custom <- app_post_fit_since_history(hist_sum, pcfg_since$discrepancy_history_since)
stopifnot(nrow(since_custom) == 2L)
stopifnot(identical(app_post_date_slug(pcfg_since$discrepancy_history_since), "20220102"))
discrepancy_since_path <- file.path(tmp_post, "discrepancy_since.pdf")
app_post_plot_discrepancy(since_custom, discrepancy_since_path, "Discrepancy since test")
stopifnot(file.exists(discrepancy_since_path), file.info(discrepancy_since_path)$size > 1000)

fit_exal <- fit_al
fit_exal$likelihood_family <- "exal"
fit_exal$draws$gamma <- matrix(c(-0.2, 0.1, -0.1, 0.2, 0.0, 0.3, 0.1, 0.4), ncol = 2L)
bundle_exal <- app_post_fit_draw_bundle(fit_exal, design, list(likelihood_family = "exal", method = "mcmc"))
stopifnot(isTRUE(bundle_exal$gamma_active))

draws <- data.frame(
  draw_id = rep(sprintf("d%02d", 1:4), each = 2L),
  draw_index = rep(1:4, each = 2L),
  fit_id = "fit_test",
  model_id = "model_test",
  model_family = "qdesn_glofas_discrepancy",
  quantile_level = 0.50,
  origin_date = as.Date("2022-01-03"),
  target_date = rep(as.Date("2022-01-03") + 1:2, 4L),
  horizon = rep(1:2, 4L),
  discrepancy_feature_date = as.Date("2022-01-03"),
  q_y_draw = rep(c(1.0, 1.1), 4L),
  q_g_draw = rep(c(1.3, 1.5), 4L),
  d_g_draw = rep(c(0.3, 0.4), 4L),
  raw_glofas_quantile = rep(c(1.2, 1.4), 4L),
  y_reference = rep(c(0.9, 1.2), 4L),
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
fc_sum <- app_post_fit_forecast_summary(draws, pcfg)
stopifnot(nrow(fc_sum) == 2L)
stopifnot(all.equal(fc_sum$q_y_mean, c(1.0, 1.1)))
stopifnot(all.equal(fc_sum$q_g_mean - fc_sum$d_g_mean, fc_sum$q_y_mean))

trace <- app_post_fit_trace_table(fit_al, bundle, fit_row)
stopifnot(nrow(trace) == 12L)
stopifnot(all(c("elbo", "relative_change", "max_parameter_change") %in% trace$trace_name))
trace_path <- file.path(tmp_post, "trace.pdf")
app_post_plot_traces(trace, trace_path, pcfg, "VB test traces")
stopifnot(file.exists(trace_path), file.info(trace_path)$size > 1000)

param_sum <- app_post_fit_parameter_summary(bundle, fit_row, pcfg)
stopifnot(nrow(param_sum) == 2L)
stopifnot(!"asymmetry" %in% param_sum$parameter_family)
param_sum_exal <- app_post_fit_parameter_summary(bundle_exal, transform(fit_row, likelihood_family = "exal"), pcfg)
stopifnot("asymmetry" %in% param_sum_exal$parameter_family)

pred <- data.frame(
  fit_id = c("raw", "qdesn"),
  model_id = c("raw", "qdesn"),
  model_family = c("raw_glofas", "qdesn_glofas_discrepancy"),
  quantile_level = 0.50,
  origin_date = as.Date("2022-01-03"),
  target_date = as.Date("2022-01-04"),
  horizon = 1L,
  qhat = c(1.1, 1.0),
  y_reference = 1.2,
  q_g_hat = c(1.1, 1.3),
  d_g_hat = c(NA, 0.3),
  raw_glofas_quantile = c(1.1, 1.2),
  discrepancy_hat = c(NA, 0.3),
  discrepancy_feature_date = as.Date("2022-01-03"),
  prediction_contract = c("raw_glofas_ensemble_quantile", "posterior_draw_glofas_quantile_minus_discrepancy"),
  contract_version = "0.3",
  forecast_scope = "issued_glofas_only",
  q_g_source = c("ensemble_empirical_quantile", "posterior_model_quantile"),
  discrepancy_feature_strategy = c("none", "horizon_indexed_origin_state"),
  prediction_unit = c("raw_point_baseline", "posterior_draw"),
  posterior_draw_contract = c("not_applicable", "q_y_draw_equals_q_g_draw_minus_d_g_draw"),
  posterior_predictive_sampling = c("not_applicable", "disabled"),
  beyond_issued_horizon = "disabled",
  stringsAsFactors = FALSE
)
cfg_metrics <- list(scoring = list(intervals = list(list(lower = 0.10, upper = 0.90, nominal = 0.80))))
metrics <- app_post_fit_metrics(pred, cfg_metrics)
stopifnot(nrow(metrics$by_model) == 2L)
stopifnot(all(is.na(metrics$by_model$crps_quantile_grid_mean)))
stopifnot(all(is.na(metrics$by_model$interval_score_mean)))
stopifnot(all(is.finite(metrics$by_model$rmse_to_observation)))

forest_path <- file.path(tmp_post, "forest.pdf")
app_post_plot_coefficient_forest(bundle$beta, forest_path, "Coefficient forest", top_k = 2L)
stopifnot(file.exists(forest_path), file.info(forest_path)$size > 1000)
