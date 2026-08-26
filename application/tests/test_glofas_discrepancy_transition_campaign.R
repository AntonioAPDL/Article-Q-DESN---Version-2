# The causal transition campaign has a frozen, leakage-safe selection contract.

candidate_fixture <- data.frame(
  candidate_id = c("t01_last", "t10_last_gctx"),
  anchor_method = c("last", "last"),
  anchor_window = c(NA, NA),
  anchor_half_life = c(NA, NA),
  glofas_level = c(FALSE, TRUE),
  glofas_anomaly = c(FALSE, TRUE),
  anomaly_window = c(50L, 50L),
  context_in_reservoir = c(TRUE, TRUE),
  context_in_readout = c(TRUE, TRUE),
  context_lags = c("0", "0"),
  priority = 1:2,
  enabled = TRUE,
  role = c("legacy_mechanism_comparator", "context"),
  retain_heavy = c(TRUE, FALSE),
  stringsAsFactors = FALSE
)
candidate_fixture <- app_glofas_transition_validate_candidates(candidate_fixture)
stopifnot(nrow(candidate_fixture) == 2L)
missing_comparator_fixture <- candidate_fixture
missing_comparator_fixture$role[[1L]] <- "anchor_bridge"
stopifnot(inherits(try(
  app_glofas_transition_validate_candidates(missing_comparator_fixture),
  silent = TRUE
), "try-error"))
comparator_contract <- app_glofas_transition_contract_from_candidate(
  candidate_fixture[candidate_fixture$candidate_id == "t01_last", , drop = FALSE]
)
stopifnot(identical(comparator_contract$origin, "legacy_strategy"))
stopifnot(identical(
  comparator_contract$strategy_label,
  "persistence_anchored_innovation"
))
context_contract <- app_glofas_transition_contract_from_candidate(
  candidate_fixture[candidate_fixture$candidate_id == "t10_last_gctx", , drop = FALSE]
)
stopifnot(identical(
  app_glofas_discrepancy_context_variables(context_contract),
  c("glofas_level", "glofas_anomaly")
))

campaign_cfg <- list(
  prediction = list(discrepancy_transition_strategy = "persistence_anchored_innovation"),
  covariates = list(
    enabled = TRUE,
    variables = c("ppt", "soil"),
    forecast = list(handoff_root = "unused"),
    ppt = list(observed_blend = list(enabled = TRUE, observed_weight = 0.5)),
    soil = list(observed_blend = list(enabled = TRUE, observed_weight = 0.5))
  )
)
campaign_cfg <- app_glofas_transition_set_origin_persistence(campaign_cfg)
comparator_cfg <- app_glofas_transition_apply_candidate(
  campaign_cfg,
  candidate_fixture[candidate_fixture$candidate_id == "t01_last", , drop = FALSE]
)
stopifnot(is.null(comparator_cfg$prediction[["discrepancy_transition"]]))
stopifnot(identical(
  comparator_cfg$prediction$discrepancy_transition_strategy,
  "persistence_anchored_innovation"
))
campaign_cfg <- app_glofas_transition_apply_candidate(
  campaign_cfg,
  candidate_fixture[candidate_fixture$candidate_id == "t10_last_gctx", , drop = FALSE]
)
stopifnot(identical(
  app_covariate_future_policy(campaign_cfg)$future_policy,
  "origin_persistence"
))
stopifnot(!app_validate_covariate_source_policy(
  campaign_cfg,
  stop_on_failure = TRUE
)$uses_realized_future[[1L]])
stopifnot(identical(
  app_glofas_discrepancy_transition_contract(campaign_cfg)$contract_hash,
  context_contract$contract_hash
))

prediction_fixture <- data.frame(
  model_family = rep("qdesn_glofas_discrepancy", 3L),
  qhat = c(1, 2, 3),
  y_reference = c(1, 2.5, 2),
  q_g_hat = c(2, 3, 4),
  d_g_hat = c(1, 1, 1),
  raw_glofas_quantile = c(2, 3, 4),
  horizon = 1:3,
  target_date = as.Date("2022-01-01") + 1:3,
  stringsAsFactors = FALSE
)
prediction_score <- app_glofas_transition_score_prediction_table(
  prediction_fixture,
  candidate_id = "candidate",
  cutoff_id = "cutoff",
  selection_role = "primary_v31"
)
stopifnot(nrow(prediction_score$summary) == 1L)
stopifnot(nrow(prediction_score$horizon) == 3L)
stopifnot(abs(
  prediction_score$summary$future_p50_check_loss - mean(c(0, 0.25, 0.5))
) < 1e-12)

origin <- as.Date("2022-01-10")
history_dates <- as.Date("2021-10-01") + 0:101
retrospective <- data.frame(
  origin_date = history_dates,
  target_date = history_dates,
  horizon = 0L,
  member = NA_character_,
  is_retrospective = TRUE,
  is_ensemble = FALSE,
  y_transformed = seq_along(history_dates) / 100,
  g_transformed = seq_along(history_dates) / 100 + 0.5,
  stringsAsFactors = FALSE
)
future_dates <- origin + 1:3
ensemble <- do.call(rbind, lapply(seq_along(future_dates), function(h) {
  data.frame(
    origin_date = origin,
    target_date = future_dates[[h]],
    horizon = h,
    member = paste0("m", 1:3),
    is_retrospective = FALSE,
    is_ensemble = TRUE,
    y_transformed = rep(1 + h / 10, 3L),
    g_transformed = rep(1.5 + h / 10, 3L) + c(-0.1, 0, 0.1),
    stringsAsFactors = FALSE
  )
}))
baseline_panel <- rbind(retrospective, ensemble)
baseline_scores <- app_glofas_transition_causal_baseline_scores(
  baseline_panel,
  cutoff_id = "toy",
  origin_date = origin,
  selection_role = "primary_v31"
)
stopifnot(nrow(baseline_scores) == 10L)
stopifnot(all(is.finite(baseline_scores$future_p50_check_loss)))
baseline_aggregate <- app_glofas_transition_equal_origin_aggregate(baseline_scores)
stopifnot(nrow(baseline_aggregate) == 10L)

cutoff_root <- tempfile("glofas_transition_cutoffs_")
dir.create(cutoff_root, recursive = TRUE)
cutoff_rows <- lapply(seq_len(4L), function(i) {
  bundle <- file.path(cutoff_root, paste0("cutoff_", i))
  for (relative in c(
    "reference/reference_gauge.csv",
    "glofas/glofas_retrospective.csv",
    "glofas/glofas_ensemble.csv",
    "covariates/climate_covariates.csv"
  )) {
    path <- file.path(bundle, relative)
    app_ensure_dir(dirname(path))
    app_write_csv(data.frame(date = as.Date("2021-01-01"), value = 1), path)
  }
  data.frame(
    cutoff_id = paste0("c", i),
    origin_date = as.Date("2021-01-01") + i,
    bundle_dir = bundle,
    glofas_source_id = if (i < 4L) "v31" else "v21",
    future_policy = "origin_persistence",
    selection_role = if (i < 4L) "primary_v31" else "supplemental_v21",
    priority = i,
    enabled = TRUE,
    stringsAsFactors = FALSE
  )
})
validated_cutoffs <- app_glofas_transition_validate_cutoffs(
  do.call(rbind, cutoff_rows),
  repo_root = app_repo_root()
)
stopifnot(nrow(validated_cutoffs) == 4L)
portable_cutoffs <- do.call(rbind, cutoff_rows)
portable_cutoffs$bundle_dir <- file.path(
  "application/data_local",
  basename(portable_cutoffs$bundle_dir)
)
portable_validated <- app_glofas_transition_validate_cutoffs(
  portable_cutoffs,
  repo_root = tempfile("absent_repo_root_"),
  data_local_root = cutoff_root
)
stopifnot(nrow(portable_validated) == 4L)
bad_cutoffs <- validated_cutoffs
bad_cutoffs$origin_date[[1L]] <- as.Date("2022-12-25")
stopifnot(inherits(try(
  app_glofas_transition_validate_cutoffs(bad_cutoffs, repo_root = app_repo_root()),
  silent = TRUE
), "try-error"))
