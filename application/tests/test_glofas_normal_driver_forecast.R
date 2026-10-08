if (!exists("app_glofas_normal_driver_bank", mode = "function")) {
  source(app_path("application/R/glofas_normal_driver_bank.R"))
}
if (!exists("app_glofas_external_driver_forecast", mode = "function")) {
  source(app_path("application/R/glofas_external_driver_forecast.R"))
}
if (!exists("app_glofas_part4_normal_driver_prior", mode = "function")) {
  source(app_path("application/R/glofas_part4_normal_driver_prior.R"))
}

dates <- as.Date("2023-01-01") + 0:2
source_fit <- tempfile(fileext = ".rds")
saveRDS(list(model = "toy_part3_rhs"), source_fit)
driver <- matrix(c(
  0.1, 0.2, 0.3,
  0.2, 0.1, 0.4,
  0.0, 0.3, 0.2,
  0.4, 0.2, 0.1,
  0.3, 0.4, 0.0
), nrow = 3L, ncol = 5L)
bank <- app_glofas_normal_driver_bank(
  dates, list(usgs = driver), as.Date("2022-12-31"), seed = 9L,
  source_fit_path = source_fit, source_model_id = "toy_part3_rhs", response_scale = "log1p"
)
stopifnot(app_validate_glofas_normal_driver_bank(bank, "usgs", 5L, dates))

context <- list(
  state0 = c(0.1, -0.1),
  reservoir = list(
    W = list(matrix(c(0.2, 0.1, -0.1, 0.3), 2L, 2L)),
    Win = list(matrix(c(0.1, 0.2, -0.2, 0.3, 0.15, -0.1), 2L, 3L)),
    alpha = 0.4,
    act_f = "tanh"
  ),
  meta = list(
    lag_center = c(0, 0), lag_scale = c(1, 1), standardize_inputs = TRUE,
    input_bound = "none", win_scale_global = 1, win_scale_bias = 1
  ),
  compiled = list(
    static_values = matrix(c(0, 1, 0, 2, 0, 3), 3L, 2L, byrow = TRUE),
    future_index = matrix(c(0L, 0L, 1L, 0L, 2L, 0L), 3L, 2L, byrow = TRUE)
  )
)
beta <- matrix(rep(c(0.1, 0.5, -0.2), 5L), 5L, 3L, byrow = TRUE)
reference <- app_glofas_external_driver_forecast(context, driver, beta, backend = "r")
compiled <- app_glofas_external_driver_forecast(context, driver, beta, backend = "cpp")
stopifnot(max(abs(reference$quantile_paths - compiled$quantile_paths)) < 1.0e-10)
stopifnot(max(abs(reference$input_mean - compiled$input_mean)) < 1.0e-10)

scaled_context <- context
scaled_context$readout_scaler <- structure(list(
  version = "glofas_normal_readout_scaler_v1", mode = "train_zscore",
  center = c(0, 1, -2), scale = c(1, 2, 4),
  columns = c("readout_intercept", "reservoir_0001", "reservoir_0002")
), class = c("glofas_normal_readout_scaler", "list"))
scaled_beta <- matrix(rep(c(0.7, 1.0, -0.8), 5L), 5L, 3L, byrow = TRUE)
raw_beta <- app_glofas_normal_readout_beta_draws_to_raw(scaled_beta, scaled_context$readout_scaler)
raw_context <- scaled_context
raw_context$readout_scaler <- NULL
scaled_result <- app_glofas_external_driver_forecast(scaled_context, driver, scaled_beta, backend = "cpp")
raw_result <- app_glofas_external_driver_forecast(raw_context, driver, raw_beta, backend = "cpp")
stopifnot(max(abs(scaled_result$quantile_paths - raw_result$quantile_paths)) < 1.0e-10)

fit <- list(
  beta_mean = c(0.2, -0.1, 0.3, 0.4),
  alpha_mean = c(-0.2, 0.2),
  beta_cov_blocks = list(diag(c(0.04, 0.01)), diag(c(0.02, 0.03)))
)
d1 <- app_glofas_quantile_beta_draws(fit, 1L, c(0.2, 0.8), 2L, 500L, 17L)
d2 <- app_glofas_quantile_beta_draws(fit, 1L, c(0.2, 0.8), 2L, 500L, 17L)
stopifnot(identical(d1, d2), nrow(d1) == 500L, ncol(d1) == 3L)

stopifnot(
  identical(app_glofas_part2_quantile_reversal_index(0.35), NA_integer_),
  identical(app_glofas_part2_quantile_reversal_index(c(0.2, 0.5, 0.8)), c(3L, 2L, 1L)),
  inherits(
    try(app_glofas_part2_quantile_reversal_index(0.35, require_complete = TRUE), silent = TRUE),
    "try-error"
  )
)
integer_dates <- structure(19352:19381, class = "Date")
double_dates <- as.Date(as.character(integer_dates))
stopifnot(!identical(integer_dates, double_dates))
stopifnot(app_glofas_daily_horizons_equal(integer_dates, double_dates))

prior <- app_glofas_part4_normal_driver_prior(bank, expected_paths = 5L)
stopifnot(app_validate_glofas_part4_normal_driver_prior(prior, dates, "log1p", 5L))
stopifnot(isTRUE(prior$replace_future_y_working_likelihood))
stopifnot(!isTRUE(prior$contract$ensemble_used_to_build_prior))
stopifnot(!isTRUE(prior$contract$future_truth_used_to_build_prior))

toy_prior <- list(
  mean = c(1, 2), precision = diag(c(2, 4)),
  replace_future_y_working_likelihood = TRUE,
  contract_hash = "toy"
)
toy_moments <- list(
  strategy = "streamed_grouped",
  fixed = list(n = 0L),
  future = list(
    n_y = 2L, n_g = 0L,
    H_y = matrix(0, 2L, 1L), H_g_key = matrix(0, 2L, 1L),
    J_y = list(matrix(0, 1L, 2L), matrix(0, 1L, 2L)),
    J_g_key = list(matrix(0, 1L, 2L), matrix(0, 1L, 2L)),
    weight_y = rep(1, 2L), weight_g = numeric(), z_g = numeric(),
    g_future_index = integer(), g_index_by_h = list(integer(), integer())
  )
)
prior_only <- app_latent_update_future_gaussian_delta(
  toy_moments, y_start = c(0, 0), theta_mean = 0, theta_cov = matrix(1, 1, 1),
  e_inv_v = rep(1, 2L), sigma_state = list(inv_mean = c(Y = 1, G = 1)),
  constants = list(A = 0, B = 1), jitter = 0,
  future_gaussian_prior = toy_prior,
  include_future_y_working_likelihood = FALSE
)
stopifnot(max(abs(prior_only$mean - c(1, 2))) < 1.0e-10)
stopifnot(max(abs(prior_only$cov - diag(c(0.5, 0.25)))) < 1.0e-10)
stopifnot(isTRUE(prior_only$future_gaussian_prior_used))
stopifnot(!isTRUE(prior_only$future_y_working_likelihood_used))
unlink(source_fit)

message("GloFAS Normal-driver forecast tests passed.")
