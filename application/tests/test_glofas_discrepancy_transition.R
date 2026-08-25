# Factorized GloFAS discrepancy-transition contracts are causal and compatible.

legacy_recursive_cfg <- list(
  prediction = list(discrepancy_transition_strategy = "recursive_level")
)
legacy_recursive_contract <-
  app_glofas_discrepancy_transition_contract(legacy_recursive_cfg)
stopifnot(identical(
  legacy_recursive_contract$strategy_label,
  "recursive_level"
))
stopifnot(!app_glofas_discrepancy_transition_is_static(
  legacy_recursive_contract
))

legacy_persistence_cfg <- list(
  prediction = list(
    discrepancy_transition_strategy = "persistence_anchored_innovation"
  )
)
legacy_persistence_contract <-
  app_glofas_discrepancy_transition_contract(legacy_persistence_cfg)
stopifnot(identical(
  legacy_persistence_contract$strategy_label,
  "persistence_anchored_innovation"
))
stopifnot(identical(
  legacy_persistence_contract$anchor$method,
  "last"
))
stopifnot(app_glofas_discrepancy_transition_is_static(
  legacy_persistence_contract
))

transition_dates <- as.Date("2022-01-01") + 0:11
transition_panel <- data.frame(
  target_date = transition_dates,
  y_transformed = seq_along(transition_dates),
  stringsAsFactors = FALSE
)
anchor_dates <- transition_dates[6:12]
legacy_anchor <- app_glofas_discrepancy_historical_anchor(
  transition_panel,
  anchor_dates,
  legacy_persistence_contract
)
legacy_lag_one <- as.numeric(app_y_lag_matrix(
  panel = transition_panel,
  anchor_dates = anchor_dates,
  lags = 1L,
  standardize = FALSE
)$X[, 1L])
stopifnot(identical(legacy_anchor, legacy_lag_one))
stopifnot(identical(
  app_glofas_discrepancy_future_anchor(
    transition_panel,
    max(transition_dates),
    3L,
    legacy_persistence_contract
  ),
  rep(12, 3L)
))

rolling_cfg <- list(
  prediction = list(
    discrepancy_transition = list(
      anchor = list(method = "rolling_mean", window = 3L),
      evolution = list(method = "static_anchor_innovation"),
      context = list(
        glofas_level = TRUE,
        glofas_anomaly = TRUE,
        anomaly_window = 4L,
        lags = 0L
      )
    )
  )
)
rolling_contract <- app_glofas_discrepancy_transition_contract(rolling_cfg)
stopifnot(identical(rolling_contract$strategy_label, "anchored_innovation"))
stopifnot(identical(
  app_glofas_discrepancy_historical_anchor(
    transition_panel,
    transition_dates[[8L]],
    rolling_contract
  ),
  mean(5:7)
))
stopifnot(identical(
  app_glofas_discrepancy_future_anchor(
    transition_panel,
    max(transition_dates),
    2L,
    rolling_contract
  ),
  rep(mean(10:12), 2L)
))

ewma_cfg <- rolling_cfg
ewma_cfg$prediction$discrepancy_transition$anchor <- list(
  method = "ewma",
  half_life = 2
)
ewma_contract <- app_glofas_discrepancy_transition_contract(ewma_cfg)
ewma_value <- app_glofas_discrepancy_historical_anchor(
  transition_panel,
  transition_dates[[8L]],
  ewma_contract
)
ewma_weights <- exp(log(0.5) * 7:1 / 2)
stopifnot(abs(ewma_value - sum(ewma_weights * 1:7) / sum(ewma_weights)) < 1e-12)

bad_transition_cfg <- rolling_cfg
bad_transition_cfg$prediction$discrepancy_transition$anchor$method <- "none"
stopifnot(inherits(try(
  app_glofas_discrepancy_transition_contract(bad_transition_cfg),
  silent = TRUE
), "try-error"))

block_cfg <- list(
  covariates = list(enabled = TRUE, variables = c("ppt", "soil")),
  feature_contract = list(
    version = "0.3",
    blocks = list(
      discrepancy = list(
        covariates = list(variables = c("ppt", "soil"))
      )
    )
  ),
  reservoir = list(m = 3L)
)
discrepancy_block_cfg <- app_qdesn_block_config(block_cfg, "discrepancy")
discrepancy_block_cfg <- app_glofas_discrepancy_context_block_config(
  discrepancy_block_cfg,
  rolling_contract
)
stopifnot(all(
  c("ppt", "soil", "glofas_level", "glofas_anomaly") %in%
    app_covariate_variables(discrepancy_block_cfg)
))
stopifnot(all(
  c("glofas_level", "glofas_anomaly") %in%
    names(app_feature_contract(discrepancy_block_cfg)$reservoir_input$covariate_lags)
))
stopifnot(inherits(try(
  app_glofas_discrepancy_context_block_config(
    app_qdesn_block_config(block_cfg, "reference"),
    rolling_contract
  ),
  silent = TRUE
), "try-error"))

context_origin <- as.Date("2022-01-10")
context_hist_dates <- as.Date("2022-01-01") + 0:9
context_future_dates <- context_origin + 1:3
context_members <- do.call(rbind, lapply(seq_along(context_future_dates), function(h) {
  data.frame(
    origin_date = context_origin,
    target_date = context_future_dates[[h]],
    horizon = h,
    member = sprintf("member_%02d", 1:3),
    g_transformed = c(20, 21, 22) + h,
    stringsAsFactors = FALSE
  )
}))
context_latent_data <- list(
  origin_date = context_origin,
  g_retro = data.frame(
    target_date = context_hist_dates,
    g_transformed = 1:10,
    stringsAsFactors = FALSE
  ),
  g_ensemble = context_members,
  future_key = data.frame(
    target_date = context_future_dates,
    horizon = 1:3,
    stringsAsFactors = FALSE
  )
)
base_timeline <- data.frame(
  date = c(context_hist_dates, context_future_dates),
  ppt = 0,
  ppt_scaled = 0,
  soil = 0,
  soil_scaled = 0,
  stringsAsFactors = FALSE
)
attr(base_timeline, "variables") <- c("ppt", "soil")
attr(base_timeline, "scale_params") <- list(
  ppt = list(center = 0, scale = 1),
  soil = list(center = 0, scale = 1)
)
context_timeline <- app_glofas_discrepancy_context_timeline(
  base_timeline,
  context_latent_data,
  0.5,
  rolling_contract
)
stopifnot(all(c("glofas_level", "glofas_anomaly") %in%
  attr(context_timeline, "variables")))
stopifnot(identical(
  context_timeline$glofas_level[
    context_timeline$date == context_future_dates[[1L]]
  ],
  22
))
stopifnot(!any(
  context_timeline$glofas_level_uses_realized_future,
  na.rm = TRUE
))
stopifnot(identical(
  attr(context_timeline, "glofas_context_contract_hash"),
  rolling_contract$contract_hash
))
stopifnot(all(is.finite(
  context_timeline$glofas_level[
    context_timeline$date >= min(context_hist_dates)
  ]
)))

ensemble_context <- app_glofas_discrepancy_ensemble_context_summary(
  context_latent_data,
  0.5
)
stopifnot(nrow(ensemble_context) == 3L)
stopifnot(all(ensemble_context$n_members == 3L))
stopifnot(all(is.finite(ensemble_context$glofas_member_sd)))

causal_baselines <- app_glofas_discrepancy_causal_baselines(
  transition_panel,
  max(transition_dates),
  3L
)
stopifnot(length(unique(causal_baselines$baseline_id)) == 9L)
stopifnot(all(causal_baselines$horizon %in% 1:3))
