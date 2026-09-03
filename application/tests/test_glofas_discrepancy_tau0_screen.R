stopifnot(identical(app_glofas_discrepancy_tau0_values(), c(0.3, 1, 3, 10)))
stopifnot(identical(
  vapply(c(0.3, 1, 3, 10), app_glofas_discrepancy_tau0_label, character(1L)),
  c("0p3", "1", "3", "10")
))
stopifnot(identical(
  app_glofas_discrepancy_tau0_candidate_id(1, warm = FALSE),
  "fr09_shared_reference_input_disctau1_cold_canary_p50"
))

tau0_guardrails <- app_glofas_discrepancy_tau0_guardrails()
stopifnot(
  identical(tau0_guardrails$window, c("all", "last1000", "last200", "last50")),
  isTRUE(all.equal(
    tau0_guardrails$maximum_allowed_log1p_mae,
    c(0.0643157200662871, 0.0400090392065597, 0.0552165320416474, 0.184151351366342),
    tolerance = 1.0e-12
  ))
)

tau0_source_cfg <- list(
  application_name = "source",
  description = "source",
  paths = list(model_grid = "grid", cache = "cache", runs = "runs", logs = "logs", generated_outputs = "generated"),
  inference = list(
    vb_ld = list(
      rhs_tau0 = 0.1, rhs_alpha_tau0 = 0.1, max_iter = 1000L,
      max_iter_hard_cap = 1000L, warm_start = list(enabled = FALSE),
      checkpoint = list(enabled = FALSE)
    ),
    mcmc = list(rhs_alpha_tau0 = 0.1)
  ),
  execution = list(final_launch = list(enabled = TRUE), artifacts = list(retain_fit_object = TRUE)),
  post_analysis = list(
    enabled = TRUE, run_after_outputs = TRUE, recent_history_n = 200L,
    storage = list(write_history_draws_rds = FALSE, write_history_draws_csv = FALSE)
  )
)
tau0_candidate_cfg <- tau0_source_cfg
tau0_candidate_cfg$application_name <- "candidate"
tau0_candidate_cfg$description <- "candidate"
tau0_candidate_cfg$paths <- lapply(tau0_candidate_cfg$paths, function(x) paste0(x, "_candidate"))
tau0_candidate_cfg$inference$vb_ld$rhs_alpha_tau0 <- 1
tau0_candidate_cfg$inference$vb_ld$max_iter <- 400L
tau0_candidate_cfg$inference$vb_ld$max_iter_hard_cap <- 400L
tau0_candidate_cfg$inference$vb_ld$warm_start <- list(enabled = TRUE)
tau0_candidate_cfg$inference$vb_ld$checkpoint <- list(enabled = TRUE, resume = FALSE)
tau0_candidate_cfg$inference$mcmc$rhs_alpha_tau0 <- 1
tau0_candidate_cfg$execution$final_launch <- list(enabled = TRUE, note = "screen")
tau0_candidate_cfg$execution$artifacts <- list(retain_fit_object = TRUE, retain_design_object = TRUE)
tau0_candidate_cfg$post_analysis$enabled <- TRUE
tau0_candidate_cfg$post_analysis$run_after_outputs <- TRUE
tau0_candidate_cfg$post_analysis$recent_history_n <- 200L
tau0_candidate_cfg$post_analysis$storage <- list(write_history_draws_rds = FALSE, write_history_draws_csv = FALSE)
stopifnot(all(app_glofas_discrepancy_tau0_assert_one_axis(
  tau0_source_cfg, tau0_candidate_cfg, expected_tau0 = 1, expected_max_iter = 400L, warm = TRUE
)))
tau0_bad_cfg <- tau0_candidate_cfg
tau0_bad_cfg$inference$vb_ld$rhs_tau0 <- 1
tau0_bad_message <- tryCatch(
  {
    app_glofas_discrepancy_tau0_assert_one_axis(tau0_source_cfg, tau0_bad_cfg, 1, 400L, TRUE)
    ""
  },
  error = function(e) conditionMessage(e)
)
stopifnot(grepl("outside the declared", tau0_bad_message, fixed = TRUE))

tau0_forecast <- data.frame(
  target_date = as.Date("2023-01-01") + 0:2,
  horizon = 1:3,
  raw_glofas_quantile = c(2, 3, 4),
  y_reference = c(1.0, 2.0, 2.5),
  q_y_median = c(1.1, 1.8, 2.6),
  d_g_median = c(0.9, 1.2, 1.4),
  stringsAsFactors = FALSE
)
tau0_metrics <- app_glofas_discrepancy_tau0_forecast_metrics(tau0_forecast, last_discrepancy = 1)
stopifnot(
  tau0_metrics$n_horizons == 3L,
  isTRUE(all.equal(tau0_metrics$forecast_check_loss, mean(c(0.05, 0.10, 0.05)))),
  isTRUE(all.equal(tau0_metrics$persistence_forecast_check_loss, mean(c(0, 0, 0.25))))
)

tau0_ranking_input <- data.frame(
  candidate_id = c("good", "bad_history", "no_gain"),
  discrepancy_tau0 = c(1, 3, 10),
  candidate_role = "warm_screen",
  technical_gate_pass = TRUE,
  forecast_check_loss = c(0.70, 0.68, 0.79),
  persistence_forecast_check_loss = 0.80,
  discrepancy_mae = c(1.40, 1.36, 1.58),
  persistence_discrepancy_mae = 1.60,
  observed_log1p_mae_all = c(0.063, 0.08, 0.063),
  observed_log1p_mae_last1000 = c(0.039, 0.06, 0.039),
  observed_log1p_mae_last200 = c(0.054, 0.08, 0.054),
  observed_log1p_mae_last50 = c(0.18, 0.25, 0.18),
  stringsAsFactors = FALSE
)
tau0_ranking <- app_glofas_discrepancy_tau0_rank(tau0_ranking_input)
stopifnot(
  identical(tau0_ranking$candidate_id[[1L]], "good"),
  isTRUE(tau0_ranking$eligible_for_cold_confirmation[[1L]]),
  identical(tau0_ranking$decision[tau0_ranking$candidate_id == "bad_history"], "reject_historical_fit_regression"),
  identical(tau0_ranking$decision[tau0_ranking$candidate_id == "no_gain"], "reject_insufficient_persistence_gain"),
  !any(tau0_ranking$automatic_promotion),
  !any(tau0_ranking$automatic_full7)
)

tau0_warm_forecast <- tau0_forecast
tau0_cold_forecast <- tau0_forecast
tau0_cold_forecast$q_y_median <- tau0_cold_forecast$q_y_median + 1.0e-5
tau0_cold_forecast$d_g_median <- tau0_cold_forecast$d_g_median + 1.0e-5
tau0_history_warm <- data.frame(
  window = c("all", "last1000", "last200", "last50"),
  log1p_mae = c(0.06, 0.04, 0.05, 0.18), stringsAsFactors = FALSE
)
tau0_history_cold <- tau0_history_warm
tau0_history_cold$log1p_mae <- tau0_history_cold$log1p_mae + 1.0e-5
tau0_canary <- app_glofas_discrepancy_tau0_canary(
  tau0_warm_forecast, tau0_cold_forecast, tau0_history_warm, tau0_history_cold
)
stopifnot(isTRUE(tau0_canary$equivalent[[1L]]))
tau0_cold_forecast$d_g_median <- tau0_cold_forecast$d_g_median + 0.1
stopifnot(!app_glofas_discrepancy_tau0_canary(
  tau0_warm_forecast, tau0_cold_forecast, tau0_history_warm, tau0_history_cold
)$equivalent[[1L]])
