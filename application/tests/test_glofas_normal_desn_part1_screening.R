normal_part1_cfg <- list(
  data = list(transform = list(response = "identity", forecast = "identity")),
  covariates = list(enabled = TRUE, variables = c("ppt", "soil")),
  feature_contract = list(),
  reservoir = list()
)

normal_part1_candidate <- data.frame(
  candidate_id = "toy",
  n_vector = "3;4;5",
  m = 4L,
  output_lag_max = 4L,
  covariate_lag_max = 3L,
  washout = 4L,
  alpha = 0.1,
  rho = 0.95,
  seed = 1L,
  ridge_tau2 = 1.0e4,
  intercept_var = 1.0e6,
  sigma_a = 2,
  sigma_b = 1,
  validation_n = 5L,
  stringsAsFactors = FALSE
)
normal_part1_effective <- app_glofas_normal_part1_make_cfg(
  normal_part1_cfg,
  n = normal_part1_candidate$n_vector,
  m = normal_part1_candidate$m,
  output_lag_max = normal_part1_candidate$output_lag_max,
  covariate_lag_max = normal_part1_candidate$covariate_lag_max,
  alpha = normal_part1_candidate$alpha,
  rho = normal_part1_candidate$rho,
  seed = normal_part1_candidate$seed,
  washout = normal_part1_candidate$washout
)
stopifnot(identical(as.integer(normal_part1_effective$reservoir$n), c(3L, 4L, 5L)))
stopifnot(identical(as.integer(normal_part1_effective$reservoir$n_tilde), c(3L, 4L)))
normal_part1_contract <- app_feature_contract(normal_part1_effective)
stopifnot(identical(normal_part1_contract$reservoir_input$output_lags, 1:4))
stopifnot(identical(normal_part1_contract$reservoir_input$covariate_lags$ppt, 0:3))
stopifnot(!isTRUE(normal_part1_contract$readout$include_input_block))

normal_part1_manifest <- app_glofas_normal_part1_candidate_manifest()
stopifnot(nrow(normal_part1_manifest) > 100L)
stopifnot(any(normal_part1_manifest$n_vector == "1000"))
stopifnot(any(normal_part1_manifest$n_vector == "1000;1000"))
stopifnot(any(normal_part1_manifest$n_vector == "1000;1000;1000"))
stopifnot(any(normal_part1_manifest$n_vector == "1000;1000;1000;1000"))
stopifnot(all(app_glofas_normal_part1_as_int_vec(normal_part1_manifest$n_vector[[1L]], "n") >= 300L))

normal_part1_wide_manifest <- app_glofas_normal_part1_wide_frontier_manifest()
stopifnot(nrow(normal_part1_wide_manifest) == 690L)
stopifnot(any(normal_part1_wide_manifest$n_vector == "5000"))
stopifnot(any(normal_part1_wide_manifest$n_vector == "2500;2500"))
stopifnot(identical(sort(unique(normal_part1_wide_manifest$D)), c(1L, 2L)))
stopifnot(identical(
  sort(unique(normal_part1_wide_manifest$lag_id)),
  sort(c("L360", "Y360_X180", "Y360_X540", "Y540_X360", "Y720_X360"))
))
stopifnot(all(normal_part1_wide_manifest$covariate_lag_max >= 0L))
stopifnot(all(normal_part1_wide_manifest$output_lag_max >= 1L))
stopifnot(all(normal_part1_wide_manifest$m >= pmax(
  normal_part1_wide_manifest$output_lag_max,
  normal_part1_wide_manifest$covariate_lag_max
)))
stopifnot(all(normal_part1_wide_manifest$alpha %in% c(0.20, 0.30, 0.40, 0.50, 0.60)))
stopifnot(all(normal_part1_wide_manifest$rho %in% c(0.90, 0.95, 0.99)))
stopifnot(sum(normal_part1_wide_manifest$D == 1L) == 600L)
stopifnot(sum(normal_part1_wide_manifest$D == 2L) == 90L)

stopifnot(identical(app_glofas_normal_part1_distribute_state_budget(5000L, 10L), rep(500L, 10L)))
stopifnot(sum(app_glofas_normal_part1_distribute_state_budget(5000L, 3L)) == 5000L)
stopifnot(max(app_glofas_normal_part1_distribute_state_budget(5000L, 3L)) -
  min(app_glofas_normal_part1_distribute_state_budget(5000L, 3L)) <= 1L)
normal_part1_depth_geometries <- app_glofas_normal_part1_depth_budget_geometries()
stopifnot(length(normal_part1_depth_geometries) == 19L)
stopifnot(identical(normal_part1_depth_geometries$D01_anchor3000_reference, 3000L))
depth_budget_ids <- grep("_budget5000_equal$", names(normal_part1_depth_geometries), value = TRUE)
depth_anchor_ids <- grep("_anchor3000_extra3000$", names(normal_part1_depth_geometries), value = TRUE)
stopifnot(length(depth_budget_ids) == 9L)
stopifnot(length(depth_anchor_ids) == 9L)
stopifnot(all(vapply(normal_part1_depth_geometries[depth_budget_ids], sum, integer(1)) == 5000L))
stopifnot(all(vapply(normal_part1_depth_geometries[depth_anchor_ids], function(n) n[[1L]], integer(1)) == 3000L))
stopifnot(all(vapply(normal_part1_depth_geometries[depth_anchor_ids], sum, integer(1)) == 6000L))
stopifnot(identical(unname(lengths(normal_part1_depth_geometries[depth_budget_ids])), 2:10))
stopifnot(identical(unname(lengths(normal_part1_depth_geometries[depth_anchor_ids])), 2:10))

set.seed(2)
X <- cbind(1, matrix(rnorm(80), nrow = 20))
beta <- c(0.5, -0.2, 0.1, 0.3, -0.1)
y <- as.numeric(X %*% beta + rnorm(20, sd = 0.05))
fit <- app_glofas_normal_ridge_fit(X, y)
pred <- app_glofas_normal_predict(fit, X[1:3, , drop = FALSE])
stopifnot(length(pred$mean) == 3L)
stopifnot(all(is.finite(pred$mean)))
stopifnot(all(is.finite(pred$sd)), all(pred$sd > 0))
crps <- app_glofas_normal_crps(y[1:3], pred$mean, pred$sd)
stopifnot(all(is.finite(crps)), all(crps >= 0))

toy_panel <- data.frame(
  origin_date = as.Date("2020-01-01") + 0:79,
  target_date = as.Date("2020-01-01") + 0:79,
  horizon = 0L,
  member = NA_character_,
  is_retrospective = TRUE,
  is_ensemble = FALSE,
  y_reference = sin(seq_len(80) / 5) + seq_len(80) / 100,
  g_glofas = sin(seq_len(80) / 5),
  y_transformed = sin(seq_len(80) / 5) + seq_len(80) / 100,
  g_transformed = sin(seq_len(80) / 5),
  split = "train",
  cutoff_id = "toy",
  ppt = cos(seq_len(80) / 6),
  soil = sin(seq_len(80) / 9),
  stringsAsFactors = FALSE
)
toy_panel$ppt_role <- "realized_history"
toy_panel$soil_role <- "realized_history"
toy_timeline <- data.frame(
  date = toy_panel$target_date,
  ppt = toy_panel$ppt,
  soil = toy_panel$soil,
  ppt_role = toy_panel$ppt_role,
  soil_role = toy_panel$soil_role,
  stringsAsFactors = FALSE
)
attr(toy_timeline, "covariate_future_policy") <- "historical_screen"
attr(toy_timeline, "covariate_source_provider") <- "toy_fixture"
attr(toy_panel, "model_covariate_timeline") <- toy_timeline
toy_bundle <- list(
  panel = toy_panel,
  cutoff = data.frame(train_start = min(toy_panel$target_date), train_end = max(toy_panel$target_date))
)
toy_candidate <- normal_part1_candidate
toy_candidate$n_vector <- "5"
toy_candidate$output_lag_max <- 3L
toy_candidate$covariate_lag_max <- 2L
toy_candidate$m <- 3L
toy_candidate$washout <- 5L
toy_candidate$validation_n <- 10L
toy_result <- app_glofas_normal_part1_score_candidate(
  normal_part1_cfg,
  toy_candidate,
  panel_bundle = toy_bundle
)
stopifnot(identical(toy_result$summary$status[[1L]], "completed"))
stopifnot(is.finite(toy_result$summary$valid_mean_crps[[1L]]))
stopifnot(toy_result$summary$n_readout_features_actual[[1L]] == 6L)
stopifnot(!any(grepl(
  "^y_lag_|^ppt_lag_|^soil_lag_",
  toy_result$design$feature_info$column_name
)))

toy_split <- app_glofas_normal_part1_validation_split(80L, 10L)
stopifnot(length(toy_split$train_idx) == 70L)
stopifnot(length(toy_split$valid_idx) == 10L)
toy_hash_1 <- app_glofas_normal_part1_design_fingerprint(
  toy_result$design$X,
  toy_result$design$y,
  toy_result$design$dates,
  toy_result$design$feature_info
)
toy_hash_2 <- app_glofas_normal_part1_design_fingerprint(
  toy_result$design$X,
  toy_result$design$y,
  toy_result$design$dates,
  toy_result$design$feature_info
)
stopifnot(identical(toy_hash_1, toy_hash_2), nchar(toy_hash_1) == 64L)

toy_warm <- app_glofas_normal_part1_rebuild_ridge_warm_start(
  normal_part1_cfg,
  toy_candidate,
  panel_bundle = toy_bundle
)
stopifnot(inherits(toy_warm, "glofas_normal_part1_ridge_warm_start"))
stopifnot(length(toy_warm$fit$beta_mean) == 6L)
stopifnot(length(toy_warm$fit$beta_var_diag) == 6L)
app_glofas_normal_part1_validate_ridge_warm_start(
  toy_warm,
  candidate_row = toy_candidate,
  design = toy_result$design,
  train_idx = seq_len(nrow(toy_result$design$X) - 10L)
)

toy_components <- data.frame(
  date = toy_panel$target_date,
  timing = "filtered",
  dlm_level = 0.1 + seq_along(toy_panel$target_date) / 100,
  dlm_seasonal_1 = sin(seq_along(toy_panel$target_date) / 8),
  dlm_seasonal_2 = cos(seq_along(toy_panel$target_date) / 11),
  dlm_seasonal_67 = sin(seq_along(toy_panel$target_date) / 17),
  dlm_transfer = 0.05 * toy_panel$ppt,
  dlm_direct_covariate = -0.03 * toy_panel$soil,
  dlm_mean = toy_panel$y_transformed + 0.01,
  dlm_residual = -0.01,
  stringsAsFactors = FALSE
)
toy_components_path <- tempfile("toy_dlm_components_", fileext = ".csv")
app_write_csv(toy_components, toy_components_path)
dlm_candidate <- toy_candidate
dlm_candidate$n_vector <- "5"
dlm_candidate$output_lag_max <- 2L
dlm_candidate$covariate_lag_max <- 1L
dlm_candidate$m <- 2L
dlm_candidate$washout <- 5L
dlm_candidate$validation_n <- 10L
dlm_candidate$dlm_extension_enabled <- TRUE
dlm_candidate$dlm_timing <- "filtered"
dlm_candidate$dlm_feature_families <- paste(app_glofas_normal_part1_default_dlm_families(), collapse = ";")
dlm_candidate$dlm_lag_min <- 1L
dlm_candidate$dlm_lag_max <- 2L
dlm_candidate$dlm_components_path <- toy_components_path
dlm_candidate$dlm_covariate_mode <- "transfer_plus_readout"
dlm_candidate$dlm_backend <- "r"
dlm_candidate$dlm_allow_smoothed_predictive <- FALSE
dlm_design <- app_glofas_normal_part1_build_design(
  normal_part1_cfg,
  dlm_candidate,
  panel_bundle = toy_bundle
)
stopifnot(isTRUE(dlm_design$dlm_extension$enabled))
stopifnot(dlm_design$design_meta$m_input == 20L)
stopifnot(length(dlm_design$design_meta$reservoir_dlm_component_columns) == 14L)
stopifnot(dlm_design$design_meta$input_lag_warmup == 2L)
stopifnot(ncol(dlm_design$X) == 6L)
stopifnot(!any(grepl("^dlm_", dlm_design$feature_info$column_name)))
stopifnot(any(grepl("^dlm_level_lag_1$", dlm_design$design_meta$reservoir_input_columns)))
dlm_warm <- app_glofas_normal_part1_rebuild_ridge_warm_start(
  normal_part1_cfg,
  dlm_candidate,
  panel_bundle = toy_bundle
)
stopifnot(identical(dlm_warm$version, "0.2"))
app_glofas_normal_part1_validate_ridge_warm_start(
  dlm_warm,
  candidate_row = dlm_candidate,
  design = dlm_design,
  train_idx = seq_len(nrow(dlm_design$X) - 10L)
)
dlm_bad_smoothed <- dlm_candidate
dlm_bad_smoothed$dlm_timing <- "smoothed"
dlm_bad_smoothed$dlm_allow_smoothed_predictive <- FALSE
dlm_bad_msg <- tryCatch(
  {
    app_glofas_normal_part1_build_design(normal_part1_cfg, dlm_bad_smoothed, panel_bundle = toy_bundle)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("Smoothed DLM components", dlm_bad_msg, fixed = TRUE))

toy_rhs_row <- cbind(
  data.frame(
    rhs_candidate_id = "toy_rhs_tau0p1",
    rhs_tau0 = 0.1,
    rhs_max_iter = 5L,
    rhs_min_iter = 2L,
    rhs_tol = 0,
    rhs_update_every = 1L,
    rhs_freeze_tau_warmup_iters = 0L,
    rhs_min_tau_updates = 0L,
    stringsAsFactors = FALSE
  ),
  toy_candidate
)
toy_rhs <- app_glofas_normal_part1_score_rhs_candidate(
  normal_part1_cfg,
  toy_rhs_row,
  panel_bundle = toy_bundle,
  warm_start = toy_warm,
  score_train = FALSE
)
stopifnot(identical(toy_rhs$summary$status[[1L]], "completed"))
stopifnot(is.finite(toy_rhs$summary$valid_mean_crps[[1L]]))
stopifnot(toy_rhs$summary$iterations[[1L]] == 5L)
stopifnot(nrow(toy_rhs$trace) == 5L)
stopifnot(all(is.finite(toy_rhs$trace$sigma2_mean)))
stopifnot("normal_rhs_partial_elbo" %in% names(toy_rhs$trace))
stopifnot(all(is.finite(toy_rhs$trace$normal_rhs_partial_elbo)))
stopifnot(is.finite(toy_rhs$summary$normal_rhs_partial_elbo[[1L]]))
stopifnot(all(is.finite(toy_rhs$coefficients$beta_mean)))
stopifnot(any(toy_rhs$coefficients$is_intercept))
stopifnot(!any(grepl(
  "^y_lag_|^ppt_lag_|^soil_lag_",
  toy_rhs$coefficients$column_name
)))

prefixed <- app_glofas_normal_part1_prefix_existing_score_columns(data.frame(
  candidate_id = "x",
  status = "completed",
  valid_mean_crps = 1,
  train_mae = 2,
  runtime_seconds = 3,
  stringsAsFactors = FALSE
))
stopifnot("ridge_status" %in% names(prefixed))
stopifnot("ridge_valid_mean_crps" %in% names(prefixed))
stopifnot("ridge_runtime_seconds" %in% names(prefixed))
