shared_cfg <- list(
  feature_contract = list(
    version = "latent_path_v0.3",
    two_block_design = TRUE,
    reservoir_input = list(
      internal_bias = TRUE,
      output_lags = list(range = c(1L, 2L)),
      covariates = list(ppt = list(range = c(0L, 1L)), soil = list(range = c(0L, 1L))),
      standardize = TRUE
    ),
    readout = list(
      add_intercept = TRUE,
      include_reservoir_state = TRUE,
      reservoir_state_lags = list(),
      include_input_block = TRUE,
      input_block = list(
        output_lags = list(range = c(1L, 2L)),
        covariates = list(ppt = list(range = c(0L, 1L)), soil = list(range = c(0L, 1L))),
        include_internal_bias = FALSE
      ),
      include_horizon_scaled = FALSE
    ),
    forecast_alignment = list(
      output_lags_anchor = "target_date",
      covariate_lags_anchor = "target_date"
    ),
    blocks = list(
      reference = list(input_stream = "reference", reservoir_seed = 101L),
      discrepancy = list(
        input_stream = "reference",
        reservoir_seed = 202L,
        readout = list(include_input_block = FALSE)
      )
    )
  ),
  reservoir = list(
    D = 1L, n = 3L, n_tilde = integer(), m = 2L, washout = 2L,
    alpha = 0.1, rho = 0.95, pi_w = 0.03, pi_in = 1,
    seed = 101L
  )
)

stopifnot(identical(app_qdesn_block_input_stream(shared_cfg, "reference"), "reference"))
stopifnot(identical(app_qdesn_block_input_stream(shared_cfg, "discrepancy"), "reference"))
stopifnot(isTRUE(app_feature_contract(app_qdesn_block_config(shared_cfg, "reference"))$readout$include_input_block))
stopifnot(!isTRUE(app_feature_contract(app_qdesn_block_config(shared_cfg, "discrepancy"))$readout$include_input_block))
stopifnot(!identical(
  app_qdesn_block_config_hash(shared_cfg, "reference"),
  app_qdesn_block_config_hash(shared_cfg, "discrepancy")
))

default_cfg <- shared_cfg
default_cfg$feature_contract$blocks$discrepancy$input_stream <- NULL
stopifnot(identical(app_qdesn_block_input_stream(default_cfg, "discrepancy"), "discrepancy"))
alias_cfg <- shared_cfg
alias_cfg$feature_contract$blocks$discrepancy$input_stream <- "transformed_reference_streamflow_history"
stopifnot(identical(app_qdesn_block_input_stream(alias_cfg, "discrepancy"), "reference"))

bad_cfg <- shared_cfg
bad_cfg$feature_contract$blocks$discrepancy$input_stream <- "glofas_ensemble_mean"
bad_message <- tryCatch(
  {
    app_qdesn_validate_block_configs(bad_cfg)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("input_stream", bad_message, fixed = TRUE))

bad_reference_cfg <- shared_cfg
bad_reference_cfg$feature_contract$blocks$reference$input_stream <- "discrepancy"
bad_reference_message <- tryCatch(
  {
    app_qdesn_validate_block_configs(bad_reference_cfg)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("reference Q-DESN", bad_reference_message, fixed = TRUE))

app_qdesn_validate_block_configs(shared_cfg)
