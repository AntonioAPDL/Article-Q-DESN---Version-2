grouped_feature_info <- data.frame(
  column_index = 1:6,
  column_name = c("intercept", "y_lag_1", "ppt_lag_0", "horizon", "state_1", "state_2"),
  block = c(
    "readout_intercept", "direct_output_lag", "direct_covariate_lag",
    "horizon", "reservoir_state", "reservoir_state"
  ),
  variable = c("intercept", "output", "ppt", "horizon", "state", "state"),
  is_intercept = c(TRUE, rep(FALSE, 5L)),
  stringsAsFactors = FALSE
)
grouped_cfg <- app_qdesn_normalize_rhs_alpha_grouping(list(
  rhs_alpha_grouping = list(
    enabled = TRUE,
    mode = "direct_reservoir",
    tau0 = list(direct = 0.1, reservoir = 0.2)
  )
))
stopifnot(!app_latent_checkpoint_apply_resume_override(
  list(enabled = TRUE, resume = TRUE),
  "false"
)$resume)
stopifnot(app_latent_checkpoint_apply_resume_override(
  list(enabled = TRUE, resume = FALSE),
  "true"
)$resume)
stopifnot(app_latent_checkpoint_apply_resume_override(
  list(enabled = TRUE, resume = FALSE),
  ""
)$resume == FALSE)
stopifnot(isTRUE(grouped_cfg$enabled))
stopifnot(identical(names(grouped_cfg$tau0), c("direct", "reservoir")))
stopifnot(identical(
  app_qdesn_normalize_rhs_alpha_grouping(list())$mode,
  "legacy_single"
))

grouped_unknown_error <- tryCatch({
  app_qdesn_normalize_rhs_alpha_grouping(list(
    rhs_alpha_grouping = list(enabled = TRUE, tau0 = list(direct = 0.1, reservoir = 0.2), typo = 1)
  ))
  FALSE
}, error = function(e) grepl("unsupported fields", conditionMessage(e), fixed = TRUE))
stopifnot(isTRUE(grouped_unknown_error))

grouped_layout <- app_qdesn_alpha_rhs_group_layout(
  grouped_feature_info,
  intercept_index = 1L,
  grouping = grouped_cfg
)
stopifnot(identical(grouped_layout$groups$direct, 2:4))
stopifnot(identical(grouped_layout$groups$reservoir, 5:6))
stopifnot(identical(grouped_layout$intercept_index, 1L))
stopifnot(identical(sort(unlist(grouped_layout$groups, use.names = FALSE)), 2:6))
stopifnot(nzchar(grouped_layout$layout_hash))

grouped_bad_partition <- grouped_feature_info
grouped_bad_partition$block[[6L]] <- "unknown_feature"
grouped_partition_error <- tryCatch({
  app_qdesn_alpha_rhs_group_layout(grouped_bad_partition, 1L, grouped_cfg)
  FALSE
}, error = function(e) grepl("not an exact partition", conditionMessage(e), fixed = TRUE))
stopifnot(isTRUE(grouped_partition_error))

direct_only_layout <- app_glofas_grouped_rhs_diagnostic_layout(
  grouped_feature_info[1:4, , drop = FALSE],
  1L
)
reservoir_only_info <- grouped_feature_info[c(1L, 5L, 6L), , drop = FALSE]
reservoir_only_info$column_index <- seq_len(nrow(reservoir_only_info))
reservoir_only_layout <- app_glofas_grouped_rhs_diagnostic_layout(reservoir_only_info, 1L)
stopifnot(identical(names(direct_only_layout$groups), "direct"))
stopifnot(identical(names(reservoir_only_layout$groups), "reservoir"))

had_exact_rebuild <- exists("app_glofas_mechanism_exact_future_design", inherits = TRUE)
if (had_exact_rebuild) old_exact_rebuild <- get("app_glofas_mechanism_exact_future_design", inherits = TRUE)
assign(
  "app_glofas_mechanism_exact_future_design",
  function(design, y_future) list(
    X_alpha_future = matrix(1:12, nrow = 2L, byrow = TRUE),
    discrepancy_baseline_future = c(2, 2)
  ),
  envir = .GlobalEnv
)
contribution_fixture <- app_glofas_grouped_rhs_contributions(
  fit = list(
    rhs_alpha_group_layout = grouped_layout,
    variational_state = list(theta_mean = seq(0.1, 0.6, by = 0.1), y_future_mean = c(1, 1))
  ),
  design = list(
    alpha_index = 1:6,
    intercept_index = 1L,
    feature_info_alpha = grouped_feature_info,
    future_key = data.frame(horizon = 1:2)
  ),
  candidate_id = "contribution_fixture"
)
if (had_exact_rebuild) {
  assign("app_glofas_mechanism_exact_future_design", old_exact_rebuild, envir = .GlobalEnv)
} else {
  rm("app_glofas_mechanism_exact_future_design", envir = .GlobalEnv)
}
stopifnot(setequal(
  contribution_fixture$summary$rhs_global_group,
  c("direct", "reservoir", "intercept")
))
stopifnot(max(contribution_fixture$summary$innovation_reconstruction_max_abs) < 1.0e-14)
stopifnot(abs(sum(
  contribution_fixture$summary$rms_share[
    contribution_fixture$summary$rhs_global_group != "intercept"
  ]
) - 1) < 1.0e-14)
stopifnot(is.na(
  contribution_fixture$summary$rms_share[
    contribution_fixture$summary$rhs_global_group == "intercept"
  ]
))

rhs_args <- list(tau0 = 0.1, a_zeta = 2, b_zeta = 4, intercept_prec = 1.0e-9)
legacy_direct <- app_latent_rhs_state_init(
  p = 6L,
  intercept_index = 1L,
  args = rhs_args,
  rhs_control = list(freeze_tau_warmup_iters = 50L, update_every = 1L, min_tau_updates = 1L)
)
legacy_dispatch <- app_latent_rhs_state_init_dispatch(
  p = 6L,
  intercept_index = 1L,
  args = rhs_args,
  rhs_control = list(freeze_tau_warmup_iters = 50L, update_every = 1L, min_tau_updates = 1L)
)
stopifnot(identical(legacy_direct, legacy_dispatch))

grouped_args <- modifyList(rhs_args, list(global_groups = grouped_layout))
grouped_state <- app_latent_grouped_rhs_state_init(
  p = 6L,
  intercept_index = 1L,
  args = grouped_args,
  rhs_control = list(freeze_tau_warmup_iters = 0L, update_every = 1L, min_tau_updates = 1L)
)
stopifnot(identical(grouped_state$prior, "grouped_rhs_ns"))
stopifnot(identical(grouped_state$prior_precision[[1L]], 1.0e-9))
stopifnot(all(grouped_state$prior_precision[2:4] == 1 / grouped_cfg$tau0[["direct"]]^2 + 0.5))
stopifnot(all(grouped_state$prior_precision[5:6] == 1 / grouped_cfg$tau0[["reservoir"]]^2 + 0.5))

grouped_mean <- c(0.5, 0.2, -0.4, 0.7, 1.1, -1.6)
grouped_cov <- diag(c(0.05, 0.03, 0.04, 0.02, 0.06, 0.08))
e_theta2 <- grouped_mean^2 + diag(grouped_cov)
expected_lambda <- rep(1, 6L)
expected_nu <- rep(1, 6L)
expected_tau <- expected_xi <- c(direct = NA_real_, reservoir = NA_real_)
for (group_name in names(grouped_layout$groups)) {
  idx <- grouped_layout$groups[[group_name]]
  expected_lambda[idx] <- 1 / (
    1 + 0.5 * e_theta2[idx] * grouped_state$e_inv_tau2[[group_name]]
  )
  expected_nu[idx] <- 1 / (1 + expected_lambda[idx])
  expected_tau[[group_name]] <- ((length(idx) + 1) / 2) / (
    1 + 0.5 * sum(e_theta2[idx] * expected_lambda[idx])
  )
  expected_xi[[group_name]] <- 1 / (
    1 / grouped_state$tau0[[group_name]]^2 + expected_tau[[group_name]]
  )
}
expected_zeta <- (2 + 5 / 2) / (4 + 0.5 * sum(e_theta2[2:6]))
grouped_state <- app_latent_grouped_rhs_state_update(
  grouped_state,
  grouped_mean,
  grouped_cov,
  iter = 1L
)
stopifnot(max(abs(grouped_state$e_inv_lambda2 - expected_lambda)) < 1.0e-14)
stopifnot(max(abs(grouped_state$e_inv_nu - expected_nu)) < 1.0e-14)
stopifnot(max(abs(grouped_state$e_inv_tau2 - expected_tau)) < 1.0e-14)
stopifnot(max(abs(grouped_state$e_inv_xi - expected_xi)) < 1.0e-14)
stopifnot(abs(grouped_state$e_inv_zeta2 - expected_zeta) < 1.0e-14)
stopifnot(grouped_state$e_inv_tau2[["direct"]] != grouped_state$e_inv_tau2[["reservoir"]])
stopifnot(identical(unname(grouped_state$group_tau_update_count), c(1L, 1L)))

grouped_trace <- app_latent_prior_rhs_trace(grouped_state, 1L)
grouped_gate <- app_latent_prior_rhs_gate(grouped_state, 2L)
grouped_diagnostics <- app_latent_prior_rhs_diagnostics(grouped_state, 2L)
stopifnot(identical(grouped_trace$block, c("all", "all.direct", "all.reservoir")))
stopifnot(all(grouped_gate$blocks$passed))
stopifnot(all(grouped_diagnostics$blocks$gate_passed))

warm_grouped <- app_latent_grouped_rhs_state_init(
  p = 6L,
  intercept_index = 1L,
  args = grouped_args,
  rhs_control = list(freeze_tau_warmup_iters = 50L, update_every = 1L, min_tau_updates = 1L)
)
warm_tau <- warm_grouped$e_inv_tau2
warm_grouped <- app_latent_grouped_rhs_state_update(
  warm_grouped,
  grouped_mean,
  grouped_cov,
  iter = 0L,
  update_global = FALSE
)
stopifnot(identical(warm_grouped$e_inv_tau2, warm_tau))
stopifnot(!identical(warm_grouped$e_inv_lambda2, rep(1, 6L)))

prior_args <- list(
  beta_rhs = list(tau0 = 0.1, s2 = 1, a_zeta = 2, b_zeta = 4, intercept_prec = 1.0e-9),
  alpha_rhs = list(
    tau0 = 1.0e-4, s2 = 1, a_zeta = 2, b_zeta = 4,
    intercept_prec = 1.0e-9, global_grouping = grouped_cfg
  )
)
prior_contract <- app_qdesn_latent_vb_prior_contract(prior_args, grouped_layout)
prior_contract_pre_layout <- app_qdesn_latent_vb_prior_contract(prior_args)
prior_args_inert <- prior_args
prior_args_inert$beta_rhs$s2 <- 99
prior_args_inert$alpha_rhs$s2 <- 123
prior_contract_inert <- app_qdesn_latent_vb_prior_contract(prior_args_inert, grouped_layout)
stopifnot(!identical(prior_contract$declared_hash, prior_contract_inert$declared_hash))
stopifnot(identical(prior_contract$effective_hash, prior_contract_inert$effective_hash))
stopifnot(all(!prior_contract$field_ledger$operative[grepl("slab_s2", prior_contract$field_ledger$field)]))

fit_contract_fixture <- list(
  prior_contract = prior_contract,
  rhs_alpha_group_layout = grouped_layout,
  vb_diagnostics = list(
    prior_declared_hash = prior_contract$declared_hash,
    prior_effective_hash = prior_contract$effective_hash,
    rhs_alpha_group_layout_hash = grouped_layout$layout_hash
  )
)
design_contract_fixture <- list(
  alpha_index = 1:6,
  intercept_index = 1L,
  feature_info_alpha = grouped_feature_info
)
runtime_contract_fixture <- data.frame(
  prior_declared_hash = prior_contract$declared_hash,
  prior_effective_hash_pre_layout = prior_contract_pre_layout$effective_hash,
  stringsAsFactors = FALSE
)
candidate_contract_fixture <- data.frame(
  grouping_enabled = TRUE,
  tau0_direct = 0.1,
  tau0_reservoir = 0.2,
  stringsAsFactors = FALSE
)
fit_contract_check <- app_glofas_grouped_rhs_validate_fit_contract(
  fit_contract_fixture,
  design_contract_fixture,
  runtime_contract_fixture,
  candidate_contract_fixture
)
stopifnot(fit_contract_check$passed)
candidate_contract_fixture$tau0_reservoir <- 0.3
fit_contract_bad_tau <- app_glofas_grouped_rhs_validate_fit_contract(
  fit_contract_fixture,
  design_contract_fixture,
  runtime_contract_fixture,
  candidate_contract_fixture
)
stopifnot(!fit_contract_bad_tau$passed)

checkpoint_payload <- list(
  schema_version = "latent_path_vb_checkpoint_v1",
  contract = list(contract_hash = "old_group_contract"),
  iteration_completed = 0L,
  state = list(
    theta_mean = numeric(), theta_cov = matrix(numeric(), 0L, 0L),
    y_mean = numeric(), y_cov = matrix(numeric(), 0L, 0L),
    sigma_state = list(), v_state = list(), prior_state = list()
  ),
  traces = list(
    objective = numeric(), par_change = numeric(), repaired_theta = logical(),
    rhs_gate_trace = logical(), rhs_trace = list(), iteration_timing = list(),
    substep_timing = list()
  ),
  rng_state = integer(),
  written_at = "2026-08-28 UTC"
)
checkpoint_mismatch <- tryCatch({
  app_latent_checkpoint_validate_payload(
    checkpoint_payload,
    expected_contract = list(contract_hash = "new_group_contract")
  )
  FALSE
}, error = function(e) grepl("Checkpoint contract mismatch", conditionMessage(e), fixed = TRUE))
stopifnot(isTRUE(checkpoint_mismatch))

score_fixture <- data.frame(
  target_date = as.Date("2022-12-26") + 0:27,
  horizon = 1:28,
  raw_glofas_quantile = seq(5, 32),
  y_reference = seq(3, 30),
  d_g_median = rep(c(1, 3), 14L),
  q_y_median = seq(5, 32) - rep(c(1, 3), 14L),
  stringsAsFactors = FALSE
)
score_identity <- app_glofas_grouped_rhs_score_identity(score_fixture, "fixture")
score_all <- score_identity$summary[score_identity$summary$lead_group == "all", , drop = FALSE]
stopifnot(score_all$identity_passed)
stopifnot(score_all$algebra_identity_passed)
stopifnot(score_all$model_identity_passed)
stopifnot(abs(score_all$discrepancy_mae - score_all$corrected_reference_mae) < 1.0e-14)
stopifnot(abs(score_all$corrected_reference_p50_check_loss - 0.5 * score_all$discrepancy_mae) < 1.0e-14)
score_fixture$q_y_median[[1L]] <- score_fixture$q_y_median[[1L]] + 0.1
score_identity_bad <- app_glofas_grouped_rhs_score_identity(score_fixture, "fixture_bad")
stopifnot(!score_identity_bad$summary$identity_passed[score_identity_bad$summary$lead_group == "all"])

history_baseline <- data.frame(
  window = c("all", "last1000", "last200", "last50"),
  log1p_mae = rep(1, 4L),
  stringsAsFactors = FALSE
)
history_candidate <- history_baseline
history_candidate$log1p_mae <- c(1.01, 1.01, 1.04, 1.20)
history_gate <- app_glofas_grouped_rhs_historical_guards(history_candidate, history_baseline)
stopifnot(all(history_gate$passed[history_gate$is_hard_gate]))
stopifnot(history_gate$warning_triggered[history_gate$window == "last50"])

stage_a_candidates <- app_glofas_grouped_rhs_stage_a_candidates()
stopifnot(nrow(stage_a_candidates) == 18L)
stopifnot(sum(stage_a_candidates$wave == "A0") == 8L)
stopifnot(sum(stage_a_candidates$wave == "A1") == 10L)
stopifnot(!anyDuplicated(stage_a_candidates$candidate_id))
stopifnot(!anyDuplicated(stage_a_candidates$priority))
stage_a_campaign <- app_read_yaml(app_path(
  "application/config/glofas_discrepancy_grouped_rhs_stage_a_20260827.yaml"
))
app_glofas_grouped_rhs_validate_campaign(stage_a_campaign)
stage_a_campaign_bad <- stage_a_campaign
stage_a_campaign_bad$inference$max_iter <- 201L
campaign_contract_error <- tryCatch({
  app_glofas_grouped_rhs_validate_campaign(stage_a_campaign_bad)
  FALSE
}, error = function(e) grepl("inference values disagree", conditionMessage(e), fixed = TRUE))
stopifnot(isTRUE(campaign_contract_error))

cat("Latent-path grouped-RHS and GloFAS campaign tests passed.\n")
