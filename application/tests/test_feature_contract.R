fc_cfg <- cfg
fc_cfg$covariates <- list(enabled = FALSE, variables = c("ppt", "soil"))
fc_cfg$reservoir$m <- 5L
fc_cfg$reservoir$add_bias <- TRUE
fc_cfg$feature_contract <- list(
  version = "test",
  reservoir_input = list(internal_bias = TRUE, output_lags = list(range = c(1L, 5L))),
  readout = list(
    add_intercept = TRUE,
    include_reservoir_state = TRUE,
    include_input_block = TRUE,
    input_block = list(
      output_lags = list(values = c(1L, 3L)),
      covariates = list(),
      include_internal_bias = FALSE
    ),
    include_horizon_scaled = TRUE,
    standardize_output_lags = FALSE
  ),
  forecast_alignment = list(
    output_lags_anchor = "origin_date",
    covariate_lags_anchor = "target_date"
  )
)

contract <- app_feature_contract(fc_cfg)
stopifnot(identical(contract$reservoir_input$output_lags, 1:5))
stopifnot(!length(contract$reservoir_input$covariate_lags))
stopifnot(identical(contract$readout$input_block$output_lags, c(1L, 3L)))
stopifnot(isTRUE(contract$readout$add_intercept))
stopifnot(isFALSE(contract$readout$input_block$include_internal_bias))

history_requirement <- app_feature_contract_history_requirement(fc_cfg, "reference")
stopifnot(history_requirement$required_history_drop[[1L]] == 5L)
stopifnot(history_requirement$reservoir_output_lag_max[[1L]] == 5L)
stopifnot(history_requirement$readout_output_lag_max[[1L]] == 3L)

history_disc_cfg <- fc_cfg
history_disc_cfg$reservoir$m <- 7L
history_disc_cfg$feature_contract$reservoir_input$output_lags <- list(range = c(1L, 7L))
history_disc_cfg$feature_contract$readout$input_block$output_lags <- list(values = c(1L, 6L))
history_alignment <- app_feature_contract_common_history_alignment(
  list(reference = fc_cfg, discrepancy = history_disc_cfg),
  requested_drop = 4L
)
stopifnot(identical(history_alignment$block, c("reference", "discrepancy")))
stopifnot(identical(history_alignment$required_history_drop, c(5L, 7L)))
stopifnot(identical(history_alignment$common_drop, c(7L, 7L)))
stopifnot(identical(history_alignment$additional_alignment_drop, c(2L, 0L)))

equal_alignment <- app_feature_contract_common_history_alignment(
  list(reference = fc_cfg, discrepancy = fc_cfg),
  requested_drop = 8L
)
stopifnot(identical(equal_alignment$common_drop, c(8L, 8L)))
stopifnot(all(equal_alignment$additional_alignment_drop == 0L))

no_direct_cfg <- fc_cfg
no_direct_cfg$feature_contract$readout$include_input_block <- FALSE
no_direct_cfg$feature_contract$readout$input_block$output_lags <- list(values = 99L)
stopifnot(
  app_feature_contract_history_requirement(no_direct_cfg)$required_history_drop[[1L]] == 5L
)

bad_history_drop_message <- tryCatch(
  {
    app_feature_contract_common_history_alignment(list(reference = fc_cfg), -1L)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("nonnegative integer", bad_history_drop_message, fixed = TRUE))

res_cov_cfg <- fc_cfg
res_cov_cfg$covariates$enabled <- TRUE
res_cov_cfg$feature_contract$reservoir_input$covariates <- list(
  ppt = list(range = c(0L, 2L)),
  soil = list(values = c(0L, 3L))
)
res_cov_contract <- app_feature_contract(res_cov_cfg)
stopifnot(identical(res_cov_contract$reservoir_input$covariate_lags$ppt, 0:2))
stopifnot(identical(res_cov_contract$reservoir_input$covariate_lags$soil, c(0L, 3L)))
stopifnot(identical(
  app_feature_contract_reservoir_covariate_lag_columns(res_cov_cfg),
  c("ppt_lag_0", "ppt_lag_1", "ppt_lag_2", "soil_lag_0", "soil_lag_3")
))

aux_cfg <- res_cov_cfg
aux_cfg$feature_contract$reservoir_input$auxiliary_lags <- list(
  usgs = list(values = c(1L, 3L)),
  glofas = list(range = c(1L, 2L))
)
aux_contract <- app_feature_contract(aux_cfg)
stopifnot(identical(aux_contract$reservoir_input$auxiliary_lags$usgs, c(1L, 3L)))
stopifnot(identical(aux_contract$reservoir_input$auxiliary_lags$glofas, 1:2))
stopifnot(identical(
  app_feature_contract_reservoir_auxiliary_lag_columns(aux_cfg),
  c("usgs_lag_1", "usgs_lag_3", "glofas_lag_1", "glofas_lag_2")
))
aux_history <- app_feature_contract_history_requirement(aux_cfg)
stopifnot(aux_history$reservoir_auxiliary_lag_max[[1L]] == 3L)

bad_aux_cfg <- aux_cfg
bad_aux_cfg$feature_contract$reservoir_input$auxiliary_lags <- list(usgs = list(values = c(0L, 1L)))
bad_aux_msg <- tryCatch(
  {
    app_feature_contract(bad_aux_cfg)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("cannot include lag 0", bad_aux_msg, fixed = TRUE))

dlm_fc_cfg <- res_cov_cfg
dlm_fc_cfg$feature_contract$reservoir_input$dlm_components <- list(
  enabled = TRUE,
  timing = "filtered",
  feature_families = c("dlm_level", "dlm_mean"),
  lags = list(values = c(1L, 2L)),
  source = "structural_normal_dlm",
  covariate_mode = "transfer_plus_readout",
  backend = "cpp"
)
dlm_contract <- app_feature_contract(dlm_fc_cfg)
stopifnot(isTRUE(dlm_contract$reservoir_input$dlm_components$enabled))
stopifnot(identical(dlm_contract$reservoir_input$dlm_components$lags, 1:2))
stopifnot(identical(
  app_feature_contract_reservoir_dlm_component_lag_columns(dlm_fc_cfg),
  c("dlm_level_lag_1", "dlm_level_lag_2", "dlm_mean_lag_1", "dlm_mean_lag_2")
))
stopifnot(app_feature_contract_history_requirement(dlm_fc_cfg)$reservoir_dlm_component_lag_max[[1L]] == 2L)

dlm_smoothed_cfg <- dlm_fc_cfg
dlm_smoothed_cfg$feature_contract$reservoir_input$dlm_components$timing <- "smoothed"
dlm_smoothed_msg <- tryCatch(
  {
    app_feature_contract(dlm_smoothed_cfg)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("Smoothed DLM components", dlm_smoothed_msg, fixed = TRUE))
dlm_smoothed_cfg$feature_contract$reservoir_input$dlm_components$allow_smoothed_predictive <- TRUE
stopifnot(identical(app_feature_contract(dlm_smoothed_cfg)$reservoir_input$dlm_components$timing, "smoothed"))

bad_fc_cfg <- fc_cfg
bad_fc_cfg$feature_contract$readout$input_block$include_internal_bias <- TRUE
bad_msg <- tryCatch(
  {
    app_feature_contract(bad_fc_cfg)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("direct readout input block", bad_msg, fixed = TRUE))

bad_zero_msg <- tryCatch(
  {
    app_parse_lag_spec(list(values = c(0L, 1L)), allow_zero = FALSE, label = "output lags")
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("cannot include lag 0", bad_zero_msg, fixed = TRUE))

dates <- as.Date("2026-01-01") + 0:10
leak_panel <- data.frame(
  origin_date = dates,
  target_date = dates,
  horizon = 0L,
  y_transformed = seq_along(dates),
  stringsAsFactors = FALSE
)
leak_panel$y_transformed[leak_panel$target_date == as.Date("2026-01-10")] <- 9999
assembled <- app_build_readout_feature_matrix(
  reservoir_X = matrix(0.25, nrow = 1L, ncol = 1L),
  panel = leak_panel,
  cfg = fc_cfg,
  output_anchor_dates = as.Date("2026-01-08"),
  covariate_target_dates = as.Date("2026-01-10"),
  horizon = 2L,
  feature_strategy = "horizon_indexed_origin_state",
  horizon_scale = 10,
  fit_scale = TRUE
)
app_validate_readout_feature_design(assembled$X, assembled$feature_info, assembled$contract)
stopifnot("readout_intercept" %in% colnames(assembled$X))
stopifnot("reservoir_0001" %in% colnames(assembled$X))
stopifnot("y_lag_1" %in% colnames(assembled$X))
stopifnot("y_lag_3" %in% colnames(assembled$X))
stopifnot("horizon_scaled" %in% colnames(assembled$X))
stopifnot(assembled$X[, "y_lag_1"] == 7)
stopifnot(assembled$X[, "y_lag_3"] == 5)
stopifnot(assembled$X[, "horizon_scaled"] == 0.2)
stopifnot(!any(assembled$X == 9999))

future <- app_build_readout_feature_matrix(
  reservoir_X = matrix(0.50, nrow = 1L, ncol = 1L),
  panel = leak_panel,
  cfg = fc_cfg,
  output_anchor_dates = as.Date("2026-01-08"),
  covariate_target_dates = as.Date("2026-01-10"),
  horizon = 2L,
  feature_strategy = "horizon_indexed_origin_state",
  horizon_scale = 10,
  feature_meta = list(readout_scale_info = assembled$readout_scale_info),
  fit_scale = FALSE
)
stopifnot(identical(colnames(future$X), colnames(assembled$X)))
stopifnot(future$X[, "y_lag_1"] == 7)

reserved_cfg <- fc_cfg
reserved_cfg$feature_contract$readout$reservoir_state_lags <- list(values = 1L)
reserved_msg <- tryCatch(
  {
    app_build_readout_feature_matrix(
      reservoir_X = matrix(0.25, nrow = 1L, ncol = 1L),
      panel = leak_panel,
      cfg = reserved_cfg,
      output_anchor_dates = as.Date("2026-01-08"),
      covariate_target_dates = as.Date("2026-01-10"),
      horizon = 2L,
      feature_strategy = "horizon_indexed_origin_state",
      horizon_scale = 10
    )
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("reservoir_state_lags is reserved", reserved_msg, fixed = TRUE))
