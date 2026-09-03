equivalence_X <- matrix(seq_len(48L) / 17, nrow = 8L, ncol = 6L)
equivalence_X[, 1L] <- 1
colnames(equivalence_X) <- c(
  "readout_intercept", "reservoir_0001", "reservoir_0002",
  "y_lag_001", "ppt_lag_000", "soil_lag_000"
)
equivalence_info <- data.frame(
  column_index = seq_len(6L),
  column_name = colnames(equivalence_X),
  block = c(
    "readout_intercept", "reservoir_state", "reservoir_state",
    "direct_output_lag", "direct_covariate_lag", "direct_covariate_lag"
  ),
  variable = c(NA, NA, NA, "y", "ppt", "soil"),
  lag = c(NA, NA, NA, 1L, 0L, 0L),
  anchor = c(
    "target_date", "reservoir_feature_date", "reservoir_feature_date",
    "target_date", "target_date", "target_date"
  ),
  is_intercept = c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE),
  is_internal_bias = FALSE,
  stringsAsFactors = FALSE
)
equivalence_cfg <- list(reservoir = list(n = c(1L, 1L)))

equivalence_layout <- app_glofas_equivalence_feature_layout(
  equivalence_X, equivalence_info, "alpha", equivalence_cfg
)
stopifnot(identical(
  equivalence_layout$feature_group[2:3],
  c("reservoir_layer_01", "reservoir_layer_02")
))
stopifnot(nzchar(app_glofas_equivalence_layout_hash(equivalence_layout, "alpha")))

equivalence_sentinel <- app_glofas_equivalence_sentinel_tests(
  equivalence_X, equivalence_info, equivalence_cfg
)
stopifnot(nrow(equivalence_sentinel) == 6L)
stopifnot(all(equivalence_sentinel$passed))

equivalence_permutation <- app_glofas_equivalence_permutation_tests(
  equivalence_X, equivalence_info
)
stopifnot(all(equivalence_permutation$passed))
stopifnot(isTRUE(app_glofas_equivalence_serialization_parity(
  equivalence_X, equivalence_info
)$passed[[1L]]))
stopifnot(all(app_glofas_equivalence_cache_mutation_tests()$passed))

equivalence_components <- app_latent_path_component_paths(
  equivalence_X[, 1:2, drop = FALSE],
  equivalence_X[, 3:6, drop = FALSE],
  beta = c(0.5, -0.2),
  alpha = c(0.1, 0.2, -0.3, 0.4),
  discrepancy_baseline = rep(-0.25, nrow(equivalence_X))
)
stopifnot(max(abs(
  equivalence_components$q_g - equivalence_components$q_y - equivalence_components$d_g
)) < 1e-12)

equivalence_hash_a <- app_latent_path_prediction_block_hash(
  equivalence_X, equivalence_info, data.frame(target_date = as.Date("2022-01-01") + 0:7, horizon = 1:8),
  "alpha", "config-a"
)
equivalence_hash_b <- app_latent_path_prediction_block_hash(
  equivalence_X, equivalence_info, data.frame(target_date = as.Date("2022-01-01") + 0:7, horizon = 1:8),
  "alpha", "config-b"
)
stopifnot(!identical(equivalence_hash_a, equivalence_hash_b))

equivalence_seed_cfg <- list(
  reservoir = list(seed = 10L),
  feature_contract = list(
    version = "0.3",
    two_block_design = TRUE,
    blocks = list(
      reference = list(reservoir_seed = 11L, reservoir = list(seed = 11L)),
      discrepancy = list(reservoir_seed = 22L, reservoir = list(seed = 33L))
    )
  )
)
equivalence_model_row <- data.frame(reservoir_seed = 10L)
equivalence_seed <- app_qdesn_block_seed_resolution(
  equivalence_model_row, equivalence_seed_cfg, "discrepancy"
)
stopifnot(equivalence_seed$effective_seed[[1L]] == 22L)
stopifnot(isTRUE(equivalence_seed$explicit_seed_conflict[[1L]]))
equivalence_seed_error <- tryCatch({
  app_validate_qdesn_block_seed_resolution(
    equivalence_seed_cfg, equivalence_model_row, conflict_action = "error"
  )
  NULL
}, error = function(e) e)
stopifnot(inherits(equivalence_seed_error, "error"))

equivalence_contributions <- app_glofas_equivalence_contribution_paths(
  equivalence_X,
  coefficients = seq_len(ncol(equivalence_X)) / 10,
  feature_info = equivalence_info,
  candidate_id = "fixture",
  period = "forecast",
  horizon = seq_len(nrow(equivalence_X)),
  block_cfg = equivalence_cfg
)
equivalence_reconstructed <- aggregate(contribution ~ horizon, equivalence_contributions, sum)
stopifnot(isTRUE(all.equal(
  equivalence_reconstructed$contribution,
  as.numeric(equivalence_X %*% (seq_len(ncol(equivalence_X)) / 10))
)))
equivalence_summary <- app_glofas_equivalence_contribution_summary(
  equivalence_contributions,
  seq_len(ncol(equivalence_X)) / 10,
  equivalence_info,
  equivalence_cfg
)
stopifnot(nrow(equivalence_summary) == 6L)

equivalence_ablation <- app_glofas_equivalence_ablation_paths(
  equivalence_contributions,
  discrepancy_baseline = rep(-0.2, 8L),
  observed_discrepancy = seq(-0.5, 0.2, length.out = 8L),
  raw_glofas = seq(1, 2, length.out = 8L),
  observed_y = seq(1.2, 1.7, length.out = 8L)
)
stopifnot(all(c("all_as_fitted", "direct_only", "reservoir_only") %in% equivalence_ablation$scenario))
stopifnot(all(equivalence_ablation$diagnostic_status == "post_fit_diagnostic_only"))

equivalence_state <- app_glofas_equivalence_state_summary(
  equivalence_X[, 2:3, drop = FALSE], "fixture", "history", equivalence_cfg
)
stopifnot(nrow(equivalence_state) == 2L)
stopifnot(all(equivalence_state$finite_fraction == 1))

equivalence_draws <- data.frame(
  q_y_draw = c(1, 2), q_g_draw = c(1.5, 2.25), d_g_draw = c(0.5, 0.25), horizon = 1:2
)
stopifnot(isTRUE(app_glofas_equivalence_prediction_identity(equivalence_draws)$passed[[1L]]))

equivalence_scores <- data.frame(
  model_family = "qdesn_glofas_discrepancy",
  quantile_level = 0.5,
  qhat = c(1, 3),
  y_reference = c(2, 1),
  check_loss = c(0.5, 1)
)
stopifnot(isTRUE(app_glofas_equivalence_independent_score(equivalence_scores)$passed[[1L]]))

equivalence_status_root <- tempfile("glofas_equivalence_status_")
dir.create(equivalence_status_root)
app_write_csv(data.frame(
  status = "strict_closeout_completed", timestamp = "2026-08-27T00:00:00Z", batch_complete = TRUE
), file.path(equivalence_status_root, "finalization_status.csv"))
app_write_csv(data.frame(
  candidate_id = c("a", "b"), state = c("completed", "preflight_rejected"),
  terminal_for_strict_closeout = TRUE
), file.path(equivalence_status_root, "candidate_state_census.csv"))
app_write_csv(data.frame(status = "running"), file.path(equivalence_status_root, "health_summary.csv"))
equivalence_precedence <- app_glofas_equivalence_status_precedence(equivalence_status_root)
stopifnot(equivalence_precedence$source[equivalence_precedence$selected] == "strict_finalization")
unlink(equivalence_status_root, recursive = TRUE)

equivalence_checks <- data.frame(check = "fixture", passed = TRUE)
equivalence_forecast_summary <- data.frame(
  feature_group = c("reservoir_layer_01", "direct_covariate_lag:ppt"),
  contribution_rms = c(0.01, 1)
)
equivalence_paths <- data.frame(observed_discrepancy = c(-2, -1), predicted_discrepancy = c(-0.1, -0.2))
equivalence_root_ablation <- data.frame(
  scenario = c("all_as_fitted", "direct_only"),
  discrepancy_mae = c(1, 1.005),
  reference_check_loss = c(0.5, 0.502)
)
equivalence_decision <- app_glofas_equivalence_root_cause_decision(
  equivalence_checks, equivalence_forecast_summary, equivalence_root_ablation, equivalence_paths
)
stopifnot(identical(
  equivalence_decision$primary_root_cause[[1L]],
  "rhs_readout_suppression_with_common_direct_feature_dominance"
))
stopifnot(!equivalence_decision$broad_screen_authorized[[1L]])
