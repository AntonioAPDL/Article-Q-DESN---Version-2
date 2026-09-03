structural_dlm_cfg <- app_glofas_structural_dlm_make_cfg()
stopifnot(identical(structural_dlm_cfg$covariate_mode, "transfer_only"))
stopifnot(identical(as.numeric(structural_dlm_cfg$lambda), 0.97))
stopifnot(all(vapply(
  structural_dlm_cfg[c("df_level", "df_seasonal_1", "df_seasonal_2", "df_seasonal_67",
                       "df_transfer", "df_covariate_coefficients", "df_readout_coefficients")],
  as.numeric,
  numeric(1L)
) == 1))

G_base <- app_glofas_structural_dlm_base_G(structural_dlm_cfg)
stopifnot(identical(dim(G_base), c(7L, 7L)))
stopifnot(abs(G_base[1L, 1L] - 1) < 1.0e-12)
expected_freq <- 2 * pi / structural_dlm_cfg$period
stopifnot(abs(G_base[2L, 2L] - cos(expected_freq)) < 1.0e-12)
stopifnot(abs(G_base[2L, 3L] - sin(expected_freq)) < 1.0e-12)

mode_dims <- c(
  none = app_glofas_structural_dlm_state_map(app_glofas_structural_dlm_make_cfg(covariate_mode = "none"))$p,
  transfer_only = app_glofas_structural_dlm_state_map(app_glofas_structural_dlm_make_cfg(covariate_mode = "transfer_only"))$p,
  readout_only = app_glofas_structural_dlm_state_map(app_glofas_structural_dlm_make_cfg(covariate_mode = "readout_only"))$p,
  transfer_plus_readout = app_glofas_structural_dlm_state_map(app_glofas_structural_dlm_make_cfg(covariate_mode = "transfer_plus_readout"))$p
)
stopifnot(identical(as.integer(mode_dims), c(7L, 10L, 9L, 12L)))

set.seed(14)
toy_dates <- as.Date("2020-01-01") + 0:79
toy_cov <- data.frame(
  date = toy_dates,
  ppt = sin(seq_along(toy_dates) / 6),
  soil = cos(seq_along(toy_dates) / 9),
  stringsAsFactors = FALSE
)
toy_y <- 0.7 +
  0.4 * sin(2 * pi * seq_along(toy_dates) / 30) +
  0.2 * scale(toy_cov$ppt)[, 1] -
  0.1 * scale(toy_cov$soil)[, 1] +
  stats::rnorm(length(toy_dates), sd = 0.05)

seq_transfer <- app_glofas_structural_dlm_build_sequences(
  y = toy_y,
  dates = toy_dates,
  covariates = toy_cov,
  cfg = structural_dlm_cfg
)
stopifnot(identical(dim(seq_transfer$F_mat), c(length(toy_dates), 10L)))
stopifnot(identical(dim(seq_transfer$G_array), c(10L, 10L, length(toy_dates))))
stopifnot(all(seq_transfer$discount_scale_mat == 0))
stopifnot(abs(seq_transfer$G_array[8L, 8L, 1L] - 0.97) < 1.0e-12)
stopifnot(all(abs(seq_transfer$G_array[8L, 9:10, 1L] - seq_transfer$covariates_scaled[1L, ]) < 1.0e-12))

fit_r <- app_glofas_structural_dlm_fit(
  y = toy_y,
  dates = toy_dates,
  covariates = toy_cov,
  cfg = app_glofas_structural_dlm_make_cfg(covariate_mode = "transfer_plus_readout", backend = "r"),
  backend = "r"
)
stopifnot(inherits(fit_r, "glofas_structural_normal_dlm_fit"))
stopifnot(!is.null(fit_r$smoother))
stopifnot(is.finite(fit_r$score$one_step_mean_crps[[1L]]))
stopifnot(is.finite(fit_r$score$filtered_mean_crps[[1L]]))
stopifnot(is.finite(fit_r$score$smoothed_mean_crps[[1L]]))

comp_filtered <- app_glofas_structural_dlm_components(fit_r, timing = "filtered")
comp_smoothed <- app_glofas_structural_dlm_components(fit_r, timing = "smoothed")
need_cols <- c(
  "dlm_level", "dlm_seasonal_1", "dlm_seasonal_2", "dlm_seasonal_67",
  "dlm_transfer", "dlm_direct_covariate", "dlm_mean", "dlm_residual"
)
stopifnot(all(need_cols %in% names(comp_filtered)))
stopifnot(all(is.finite(comp_filtered$dlm_mean)))
stopifnot(all(is.finite(comp_filtered$dlm_residual)))
stopifnot(all(need_cols %in% names(comp_smoothed)))
stopifnot(all(is.finite(comp_smoothed$dlm_mean)))
stopifnot(max(abs(fit_r$smoother$s[, ncol(fit_r$smoother$s)] - fit_r$filter$m[, ncol(fit_r$filter$m)]), na.rm = TRUE) < 1.0e-8)
stopifnot(max(abs(fit_r$smoother$smoothed_mean[[length(fit_r$smoother$smoothed_mean)]] -
                  fit_r$filter$fitted_mean[[length(fit_r$filter$fitted_mean)]]), na.rm = TRUE) < 1.0e-8)

toy_panel <- data.frame(
  target_date = toy_dates,
  is_retrospective = TRUE,
  y_transformed = toy_y,
  stringsAsFactors = FALSE
)
aug <- app_glofas_structural_dlm_augment_panel(toy_panel, comp_filtered, timing = "filtered")
stopifnot(nrow(aug) == nrow(toy_panel))
stopifnot(identical(as.Date(aug$target_date), toy_dates))
stopifnot("dlm_mean" %in% names(aug))

lagged <- app_glofas_structural_dlm_lag_matrix(
  aug,
  anchor_dates = toy_dates[4:20],
  lags = 1:3
)
stopifnot(!is.null(lagged$X))
stopifnot(nrow(lagged$X) == 17L)
stopifnot(any(grepl("^dlm_level_lag_", colnames(lagged$X))))
stopifnot(any(grepl("^dlm_residual_lag_", colnames(lagged$X))))

lag0_error <- tryCatch(
  app_glofas_structural_dlm_lag_matrix(aug, anchor_dates = toy_dates[4:20], lags = 0:1),
  error = function(e) e
)
stopifnot(inherits(lag0_error, "error"))
stopifnot(grepl("dlm_residual_lag_0", conditionMessage(lag0_error)))

feat_contract <- app_glofas_structural_dlm_feature_contract(1:5)
stopifnot(identical(feat_contract$lags, 1:5))
stopifnot(isTRUE(feat_contract$leakage_rules$residual_lag0_forbidden))
feat_contract_smoothed <- app_glofas_structural_dlm_feature_contract(1:5, timing = "smoothed", placement = "diagnostic")
stopifnot(identical(feat_contract_smoothed$timing, "smoothed"))
smoothed_predictive_error <- tryCatch(
  app_glofas_structural_dlm_feature_contract(1:5, timing = "smoothed", placement = "reservoir_input"),
  error = function(e) e
)
stopifnot(inherits(smoothed_predictive_error, "error"))
stopifnot(grepl("diagnostic-only", conditionMessage(smoothed_predictive_error)))

plot_path <- tempfile("glofas_structural_dlm_fit_", fileext = ".pdf")
app_glofas_structural_dlm_plot_fit(fit_r, plot_path, last_n = 20)
stopifnot(file.exists(plot_path), file.info(plot_path)$size > 0)
smooth_plot_path <- tempfile("glofas_structural_dlm_smoothed_fit_", fileext = ".pdf")
app_glofas_structural_dlm_plot_fit(fit_r, smooth_plot_path, last_n = 20, timing = "smoothed")
stopifnot(file.exists(smooth_plot_path), file.info(smooth_plot_path)$size > 0)
comp_plot_path <- tempfile("glofas_structural_dlm_components_", fileext = ".pdf")
app_glofas_structural_dlm_plot_components(fit_r, comp_plot_path, last_n = 20, timing = "smoothed")
stopifnot(file.exists(comp_plot_path), file.info(comp_plot_path)$size > 0)

if (requireNamespace("Rcpp", quietly = TRUE) && requireNamespace("RcppArmadillo", quietly = TRUE)) {
  fit_cpp <- app_glofas_structural_dlm_fit(
    y = toy_y,
    dates = toy_dates,
    covariates = toy_cov,
    cfg = app_glofas_structural_dlm_make_cfg(covariate_mode = "transfer_plus_readout", backend = "cpp"),
    backend = "cpp"
  )
  stopifnot(max(abs(fit_cpp$filter$f - fit_r$filter$f), na.rm = TRUE) < 1.0e-7)
  stopifnot(max(abs(fit_cpp$filter$fitted_mean - fit_r$filter$fitted_mean), na.rm = TRUE) < 1.0e-7)
  stopifnot(max(abs(fit_cpp$smoother$s - fit_r$smoother$s), na.rm = TRUE) < 1.0e-6)
  stopifnot(max(abs(fit_cpp$smoother$smoothed_mean - fit_r$smoother$smoothed_mean), na.rm = TRUE) < 1.0e-6)
  inv_out <- glofas_structural_dlm_safe_inv_cpp(matrix(c(1, 1, 1, 1), 2L, 2L))
  stopifnot(all(is.finite(inv_out$inverse)))
}
