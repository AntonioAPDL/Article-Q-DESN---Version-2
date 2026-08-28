#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/latent_path_checkpoint.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/fit_qdesn_discrepancy.R"))
source(app_path("application/R/fit_qdesn_latent_path.R"))
source(app_path("application/R/glofas_fit_recovery_mechanism_audit.R"))
source(app_path("application/R/glofas_discrepancy_equivalence_audit.R"))
source(app_path("application/R/glofas_discrepancy_grouped_rhs_campaign.R"))

args <- app_parse_args(list(output_root = "", wave = "A0"))
output_root <- normalizePath(args$output_root, mustWork = TRUE)
wave <- toupper(as.character(args$wave))
if (!wave %in% c("A0", "ALL")) stop("--wave must be A0 or ALL.", call. = FALSE)
campaign <- app_read_yaml(file.path(output_root, "campaign_snapshot.yaml"))
runtime <- app_read_csv(file.path(output_root, "runtime_manifest_all.csv"))
candidate_contracts <- app_read_csv(file.path(output_root, "candidate_contracts.csv"))
if (anyDuplicated(runtime$candidate_id) || anyDuplicated(candidate_contracts$candidate_id) ||
    !setequal(runtime$candidate_id, candidate_contracts$candidate_id)) {
  stop("Runtime and candidate contracts do not define the same unique candidates.", call. = FALSE)
}
selected <- if (wave == "A0") runtime$wave == "A0" else rep(TRUE, nrow(runtime))
manifest <- runtime[selected, , drop = FALSE]
complete <- file.exists(file.path(manifest$run_dir, ".fit_recovery_complete"))
if (!all(complete)) {
  stop(sprintf("Cannot finalize %s: %d of %d candidates are incomplete.", wave, sum(!complete), nrow(manifest)), call. = FALSE)
}

baseline_history <- app_read_csv(campaign$baselines$current_engine_fr09_observed_scores)
retained_forecast <- app_read_csv(campaign$source$forecast_summary)
retained_score <- app_glofas_grouped_rhs_score_identity(
  retained_forecast,
  campaign$source$candidate_id,
  tolerance = as.numeric(campaign$decision$score_identity_tolerance)
)
retained_all <- retained_score$summary[retained_score$summary$lead_group == "all", , drop = FALSE]

score_rows <- list()
path_rows <- list()
lead_rows <- list()
history_rows <- list()
contribution_rows <- list()
contribution_path_rows <- list()
rhs_rows <- list()
objective_rows <- list()
artifact_rows <- list()
contract_check_rows <- list()
for (i in seq_len(nrow(manifest))) {
  row <- manifest[i, , drop = FALSE]
  candidate_id <- row$candidate_id[[1L]]
  candidate_row <- candidate_contracts[
    candidate_contracts$candidate_id == candidate_id,
    ,
    drop = FALSE
  ]
  if (nrow(candidate_row) != 1L) {
    stop(sprintf("Candidate %s lacks one frozen contract row.", candidate_id), call. = FALSE)
  }
  run_dir <- row$run_dir[[1L]]
  forecast_path <- file.path(run_dir, "tables", "post_fit_forecast_window_summary.csv")
  observed_path <- file.path(output_root, "scores", paste0(candidate_id, "_observed_fit_scores.csv"))
  fit_manifest_path <- file.path(run_dir, "manifest", "qdesn_discrepancy_fit_manifest.csv")
  diagnostics_path <- file.path(run_dir, "tables", "qdesn_discrepancy_fit_diagnostics.csv")
  draw_checks_path <- file.path(run_dir, "tables", "qdesn_discrepancy_draw_checks.csv")
  fit_status_path <- file.path(run_dir, "tables", "fit_status.csv")
  required_paths <- c(
    forecast_path, observed_path, fit_manifest_path, diagnostics_path,
    draw_checks_path, fit_status_path
  )
  if (any(!file.exists(required_paths))) {
    stop(sprintf("Completed candidate %s lacks required compact evidence.", candidate_id), call. = FALSE)
  }
  score <- app_glofas_grouped_rhs_score_identity(
    app_read_csv(forecast_path),
    candidate_id,
    tolerance = as.numeric(campaign$decision$score_identity_tolerance)
  )
  all_score <- score$summary[score$summary$lead_group == "all", , drop = FALSE]
  path_rows[[i]] <- score$path
  lead_rows[[i]] <- score$summary

  observed <- app_read_csv(observed_path)
  history_guard <- app_glofas_grouped_rhs_historical_guards(
    observed,
    baseline_history,
    repeat_envelope = 0,
    hard_limits = c(
      all = as.numeric(campaign$decision$historical_all_relative_degradation_max),
      last1000 = as.numeric(campaign$decision$historical_last1000_relative_degradation_max),
      last200 = as.numeric(campaign$decision$historical_last200_relative_degradation_max)
    ),
    warning_limits = c(
      last50 = as.numeric(campaign$decision$historical_last50_warning_relative_degradation)
    )
  )
  history_guard$candidate_id <- candidate_id
  history_rows[[i]] <- history_guard
  diagnostics <- app_read_csv(diagnostics_path)
  draw_checks <- app_read_csv(draw_checks_path)
  fit_status <- app_read_csv(fit_status_path)
  fit_manifest <- app_read_csv(fit_manifest_path)
  fit_path <- app_resolve_path(fit_manifest$fit_object[[1L]], must_work = TRUE)
  design_path <- app_resolve_path(fit_manifest$design_object[[1L]], must_work = TRUE)
  fit <- readRDS(fit_path)
  design <- readRDS(design_path)
  fit_contract <- app_glofas_grouped_rhs_validate_fit_contract(
    fit,
    design,
    row,
    candidate_row
  )
  fit_contract$checks$candidate_id <- candidate_id
  contract_check_rows[[i]] <- fit_contract$checks
  contribution <- app_glofas_grouped_rhs_contributions(fit, design, candidate_id)
  contribution_identity_pass <- all(
    is.finite(contribution$summary$innovation_reconstruction_max_abs) &
      contribution$summary$innovation_reconstruction_max_abs <=
        as.numeric(campaign$decision$score_identity_tolerance)
  )
  contribution_rows[[i]] <- contribution$summary
  contribution_path_rows[[i]] <- contribution$paths
  rhs_diag <- fit$vb_diagnostics$rhs_global_scale$blocks %||% data.frame()
  if (nrow(rhs_diag)) {
    rhs_diag$candidate_id <- candidate_id
    rhs_rows[[i]] <- rhs_diag
  }
  objective_rows[[i]] <- data.frame(
    candidate_id = candidate_id,
    iteration = seq_along(fit$vb_diagnostics$elbo_trace),
    objective = as.numeric(fit$vb_diagnostics$elbo_trace),
    parameter_change = as.numeric(fit$vb_diagnostics$parameter_change_trace),
    stringsAsFactors = FALSE
  )
  q_status <- fit_status[
    fit_status$model_family == "qdesn_glofas_discrepancy" &
      abs(as.numeric(fit_status$quantile_level) - 0.5) < 1.0e-12,
    ,
    drop = FALSE
  ]
  fit_status_pass <- nrow(q_status) == 1L &&
    identical(as.character(q_status$status[[1L]]), "completed")
  warm_expected <- identical(as.character(candidate_row$warm_start_policy[[1L]]), "warm")
  warm_flags <- c(
    enabled = app_as_bool(diagnostics$vb_warm_start_enabled[[1L]]),
    used = app_as_bool(diagnostics$vb_warm_start_used[[1L]]),
    theta = app_as_bool(diagnostics$vb_warm_start_theta_used[[1L]]),
    future = app_as_bool(diagnostics$vb_warm_start_future_used[[1L]])
  )
  warm_start_contract_pass <- if (warm_expected) {
    expected_certificate_sha <- as.character(
      candidate_row$numerical_certificate_sha256[[1L]]
    )
    all(warm_flags) &&
      identical(
        as.character(diagnostics$vb_warm_start_compatibility_mode[[1L]]),
        "numerical_design"
      ) &&
      identical(
        as.character(diagnostics$vb_warm_start_compatibility_class[[1L]]),
        "numerically_equivalent_design"
      ) &&
      nzchar(expected_certificate_sha) &&
      identical(
        tolower(as.character(
          diagnostics$vb_warm_start_numerical_certificate_sha256[[1L]]
        )),
        tolower(expected_certificate_sha)
      ) &&
      is.finite(as.numeric(diagnostics$vb_warm_start_numerical_max_abs[[1L]])) &&
      as.numeric(diagnostics$vb_warm_start_numerical_max_abs[[1L]]) <=
        as.numeric(candidate_row$numerical_absolute_tolerance[[1L]]) &&
      is.finite(as.numeric(
        diagnostics$vb_warm_start_numerical_max_scaled_rmse[[1L]]
      )) &&
      as.numeric(diagnostics$vb_warm_start_numerical_max_scaled_rmse[[1L]]) <=
        as.numeric(candidate_row$numerical_scaled_rmse_tolerance[[1L]])
  } else {
    !any(warm_flags)
  }
  technical_gate <- fit_status_pass && fit_contract$passed && warm_start_contract_pass &&
    contribution_identity_pass &&
    isTRUE(app_as_bool(diagnostics$finite_theta[[1L]])) &&
    isTRUE(app_as_bool(diagnostics$finite_sigma[[1L]])) &&
    isTRUE(app_as_bool(diagnostics$vb_converged[[1L]])) &&
    isTRUE(app_as_bool(diagnostics$rhs_beta_gate_passed[[1L]])) &&
    isTRUE(app_as_bool(diagnostics$rhs_alpha_gate_passed[[1L]])) &&
    all(app_as_bool_vec(draw_checks$all_identity_errors_within_tolerance)) &&
    all(score$summary$identity_passed)
  score_rows[[i]] <- data.frame(
    candidate_id = candidate_id,
    wave = row$wave[[1L]],
    scientific_model_hash = row$scientific_model_hash[[1L]],
    treatment_hash = row$treatment_hash[[1L]],
    discrepancy_mae = all_score$discrepancy_mae,
    discrepancy_rmse = all_score$discrepancy_rmse,
    discrepancy_bias = all_score$discrepancy_bias,
    p50_check_loss = all_score$corrected_reference_p50_check_loss,
    identity_passed = all_score$identity_passed,
    technical_gate_pass = technical_gate,
    fit_status_pass = fit_status_pass,
    prior_contract_pass = fit_contract$passed,
    warm_start_contract_pass = warm_start_contract_pass,
    contribution_identity_pass = contribution_identity_pass,
    historical_gate_pass = all(history_guard$passed[history_guard$is_hard_gate]),
    historical_last50_warning = any(history_guard$warning_triggered),
    vb_iterations = as.integer(diagnostics$vb_iterations[[1L]]),
    vb_converged = app_as_bool(diagnostics$vb_converged[[1L]]),
    runtime_seconds = sum(as.numeric(fit_status$runtime_seconds), na.rm = TRUE),
    prior_effective_hash = fit$prior_contract$effective_hash %||% NA_character_,
    alpha_group_layout_hash = fit$rhs_alpha_group_layout$layout_hash %||% NA_character_,
    fit_object = fit_path,
    design_object = design_path,
    stringsAsFactors = FALSE
  )
  artifact_rows[[i]] <- data.frame(
    candidate_id = candidate_id,
    artifact = c("fit", "design"),
    path = c(fit_path, design_path),
    bytes = c(file.info(fit_path)$size, file.info(design_path)$size),
    sha256 = c(app_sha256_file(fit_path), app_sha256_file(design_path)),
    stringsAsFactors = FALSE
  )
  rm(fit, design)
  gc(FALSE)
}

scores <- app_bind_rows_fill(score_rows)
paths <- app_bind_rows_fill(path_rows)
leads <- app_bind_rows_fill(lead_rows)
history <- app_bind_rows_fill(history_rows)
contributions <- app_bind_rows_fill(contribution_rows)
contribution_paths <- app_bind_rows_fill(contribution_path_rows)
rhs <- app_bind_rows_fill(rhs_rows)
objectives <- app_bind_rows_fill(objective_rows)
artifacts <- app_bind_rows_fill(artifact_rows)
contract_checks <- app_bind_rows_fill(contract_check_rows)

scores <- merge(scores, candidate_contracts[, c(
  "candidate_id", "candidate_role", "readout_mode", "grouping_enabled",
  "tau0_direct", "tau0_reservoir", "warm_start_policy"
)], by = "candidate_id", all.x = TRUE, sort = FALSE)
scores$grouping_enabled <- app_as_bool_vec(scores$grouping_enabled)
scores$identity_passed <- app_as_bool_vec(scores$identity_passed)
scores$technical_gate_pass <- app_as_bool_vec(scores$technical_gate_pass)
scores$historical_gate_pass <- app_as_bool_vec(scores$historical_gate_pass)
hist_wide <- reshape(
  history[, c("candidate_id", "window", "ratio")],
  idvar = "candidate_id", timevar = "window", direction = "wide"
)
scores <- merge(scores, hist_wide, by = "candidate_id", all.x = TRUE, sort = FALSE)
control_id <- "grhs_a0_01"
control <- scores[scores$candidate_id == control_id, , drop = FALSE]
if (nrow(control) != 1L) stop("A0 ungrouped cold control is absent from finalization.", call. = FALSE)
repeat_relative <- abs(control$discrepancy_mae - retained_all$discrepancy_mae) / retained_all$discrepancy_mae
control_path <- paths[paths$candidate_id == control_id, , drop = FALSE]
retained_path <- retained_score$path
repeat_path_rmse <- sqrt(mean((
  control_path$predicted_discrepancy[match(retained_path$horizon, control_path$horizon)] -
    retained_path$predicted_discrepancy
)^2))
relative_envelope <- max(
  2 * repeat_relative,
  as.numeric(campaign$decision$practical_equivalence_relative)
)
absolute_envelope <- max(
  2 * repeat_path_rmse,
  as.numeric(campaign$decision$practical_equivalence_relative) * control$discrepancy_mae,
  as.numeric(campaign$decision$practical_equivalence_absolute)
)

control_contrib <- contributions[contributions$candidate_id == control_id & contributions$rhs_global_group == "reservoir", , drop = FALSE]
control_reservoir_share <- if (nrow(control_contrib) == 1L) control_contrib$rms_share[[1L]] else NA_real_
scores$reservoir_rms_share <- vapply(scores$candidate_id, function(id) {
  value <- contributions$rms_share[contributions$candidate_id == id & contributions$rhs_global_group == "reservoir"]
  if (length(value) == 1L) value else NA_real_
}, numeric(1L))
scores$direct_effective_tau <- vapply(scores$candidate_id, function(id) {
  value <- rhs$effective_tau[rhs$candidate_id == id & rhs$block == "alpha.direct"]
  if (length(value) == 1L) value else NA_real_
}, numeric(1L))
scores$reservoir_effective_tau <- vapply(scores$candidate_id, function(id) {
  value <- rhs$effective_tau[rhs$candidate_id == id & rhs$block == "alpha.reservoir"]
  if (length(value) == 1L) value else NA_real_
}, numeric(1L))
scores$scale_separation_ratio <- pmax(
  scores$direct_effective_tau / scores$reservoir_effective_tau,
  scores$reservoir_effective_tau / scores$direct_effective_tau
)
scores$path_rmse_vs_ungrouped <- vapply(scores$candidate_id, function(id) {
  candidate <- paths[paths$candidate_id == id, , drop = FALSE]
  aligned <- control_path$predicted_discrepancy[match(candidate$horizon, control_path$horizon)]
  sqrt(mean((candidate$predicted_discrepancy - aligned)^2))
}, numeric(1L))
scores$gain_vs_ungrouped <- 1 - scores$discrepancy_mae / control$discrepancy_mae
fr09_score <- app_glofas_grouped_rhs_score_identity(
  app_read_csv(campaign$baselines$current_engine_fr09_forecast_summary),
  campaign$baselines$current_engine_fr09_candidate_id
)
fr09_all <- fr09_score$summary[fr09_score$summary$lead_group == "all", , drop = FALSE]
scores$gain_vs_fr09 <- 1 - scores$discrepancy_mae / fr09_all$discrepancy_mae[[1L]]
scores$eligible <- scores$technical_gate_pass & scores$historical_gate_pass & scores$identity_passed
scores$eligible[is.na(scores$eligible)] <- FALSE
scores <- scores[order(!scores$eligible, scores$discrepancy_mae, scores$discrepancy_rmse, abs(scores$discrepancy_bias), scores$runtime_seconds), , drop = FALSE]
scores$rank <- seq_len(nrow(scores))

if (wave == "A0") {
  grouped <- scores$grouping_enabled & scores$eligible
  scale_activation <- any(
    grouped & is.finite(scores$scale_separation_ratio) &
      scores$scale_separation_ratio >= as.numeric(campaign$decision$scale_separation_ratio_min) &
      is.finite(scores$reservoir_rms_share) &
      scores$reservoir_rms_share >= as.numeric(campaign$decision$reservoir_share_absolute_min) &
      scores$reservoir_rms_share >= as.numeric(campaign$decision$reservoir_share_multiplier_over_control) * control_reservoir_share
  )
  reverse_mae <- scores$discrepancy_mae[scores$candidate_id == "grhs_a0_04"]
  directional <- scores$candidate_id %in% c("grhs_a0_07", "grhs_a0_08") & scores$eligible
  directional_activation <- any(
    directional & scores$path_rmse_vs_ungrouped > absolute_envelope & scores$discrepancy_mae < reverse_mae
  )
  reservoir_only_mae <- scores$discrepancy_mae[scores$candidate_id == "grhs_a0_06"]
  direct_only_mae <- scores$discrepancy_mae[scores$candidate_id == "grhs_a0_05"]
  reservoir_canary_activation <- length(reservoir_only_mae) == 1L && length(direct_only_mae) == 1L &&
    reservoir_only_mae <= (1 - as.numeric(campaign$decision$reservoir_only_relative_gain_min)) *
      min(direct_only_mae, control$discrepancy_mae)
  mechanism_active <- isTRUE(scale_activation || directional_activation || reservoir_canary_activation)
  severe_failure <- sum(scores$technical_gate_pass) < 6L || sum(scores$historical_gate_pass) < 6L
  proceed <- mechanism_active && !severe_failure
  decision <- data.frame(
    campaign_id = campaign$campaign_id,
    wave = "A0",
    finalized_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    completed = nrow(scores),
    failed = 0L,
    repeat_relative_envelope = repeat_relative,
    repeat_path_rmse = repeat_path_rmse,
    practical_relative_envelope = relative_envelope,
    practical_absolute_envelope = absolute_envelope,
    scale_activation = scale_activation,
    directional_activation = directional_activation,
    reservoir_canary_activation = reservoir_canary_activation,
    severe_numerical_or_historical_failure = severe_failure,
    mechanism_active = mechanism_active,
    proceed_to_a1 = proceed,
    reason = if (proceed) "At least one frozen mechanism-activation condition passed." else if (severe_failure) "Systematic numerical or historical failure." else "Grouped mechanism did not activate under the frozen A0 rules.",
    automatic_promotion = FALSE,
    article_update = FALSE,
    stringsAsFactors = FALSE
  )
  decision_path <- file.path(output_root, "decisions", "a0_mechanism_decision.csv")
} else {
  scientific <- scores$eligible &
    scores$gain_vs_ungrouped >= as.numeric(campaign$decision$scientific_gain_over_ungrouped_min) &
    scores$discrepancy_mae < as.numeric(campaign$baselines$persistence_discrepancy_mae)
  decision <- data.frame(
    campaign_id = campaign$campaign_id,
    wave = "ALL",
    finalized_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    completed = nrow(scores),
    failed = 0L,
    scientific_success_count = sum(scientific),
    best_candidate_id = scores$candidate_id[[1L]],
    best_discrepancy_mae = scores$discrepancy_mae[[1L]],
    best_gain_vs_ungrouped = scores$gain_vs_ungrouped[[1L]],
    proceed_to_stage_b = any(scientific),
    automatic_promotion = FALSE,
    article_update = FALSE,
    reason = if (any(scientific)) "At least one candidate passed the frozen scientific-success gate; Stage B confirmation is required." else "No candidate passed the frozen scientific-success gate; stop grouped-RHS architecture expansion.",
    stringsAsFactors = FALSE
  )
  decision_path <- file.path(output_root, "decisions", "stage_a_scientific_decision.csv")
}

app_write_csv(scores, file.path(output_root, "tables", paste0(tolower(wave), "_ranking.csv")))
app_write_csv(paths, file.path(output_root, "tables", paste0(tolower(wave), "_discrepancy_paths.csv")))
app_write_csv(leads, file.path(output_root, "tables", paste0(tolower(wave), "_lead_scores.csv")))
app_write_csv(history, file.path(output_root, "tables", paste0(tolower(wave), "_historical_guards.csv")))
app_write_csv(contributions, file.path(output_root, "tables", paste0(tolower(wave), "_contribution_summary.csv")))
app_write_csv(contribution_paths, file.path(output_root, "tables", paste0(tolower(wave), "_contribution_paths.csv")))
app_write_csv(rhs, file.path(output_root, "tables", paste0(tolower(wave), "_rhs_summary.csv")))
app_write_csv(objectives, file.path(output_root, "tables", paste0(tolower(wave), "_objective_traces.csv")))
app_write_csv(artifacts, file.path(output_root, "tables", paste0(tolower(wave), "_heavy_artifact_manifest.csv")))
app_write_csv(contract_checks, file.path(output_root, "tables", paste0(tolower(wave), "_fit_contract_checks.csv")))
app_write_csv(decision, decision_path)
app_write_csv(data.frame(
  artifact = c("ranking", "decision"),
  path = c(file.path(output_root, "tables", paste0(tolower(wave), "_ranking.csv")), decision_path),
  sha256 = c(
    app_sha256_file(file.path(output_root, "tables", paste0(tolower(wave), "_ranking.csv"))),
    app_sha256_file(decision_path)
  ),
  stringsAsFactors = FALSE
), file.path(output_root, "decisions", paste0(tolower(wave), "_decision_inputs_and_hashes.csv")))

if (requireNamespace("ggplot2", quietly = TRUE)) {
  observed <- unique(paths[, c("horizon", "observed_discrepancy")])
  p_paths <- ggplot2::ggplot(paths, ggplot2::aes(horizon, predicted_discrepancy, group = candidate_id, color = candidate_id)) +
    ggplot2::geom_line(linewidth = 0.45, alpha = 0.8) +
    ggplot2::geom_line(data = observed, ggplot2::aes(horizon, observed_discrepancy), inherit.aes = FALSE, color = "black", linewidth = 0.9) +
    ggplot2::labs(x = "Forecast lead (days)", y = "Transformed discrepancy", color = "Candidate") +
    ggplot2::theme_bw(base_size = 9) + ggplot2::theme(legend.position = "bottom")
  ggplot2::ggsave(file.path(output_root, "figures", paste0(tolower(wave), "_discrepancy_paths.pdf")), p_paths, width = 10, height = 6)

  grouped_rhs <- rhs[grepl("^alpha[.]", rhs$block), , drop = FALSE]
  if (nrow(grouped_rhs)) {
    p_tau <- ggplot2::ggplot(grouped_rhs, ggplot2::aes(candidate_id, effective_tau, color = global_group)) +
      ggplot2::geom_point(size = 2) + ggplot2::scale_y_log10() +
      ggplot2::labs(x = NULL, y = "Final effective global tau", color = "Alpha group") +
      ggplot2::theme_bw(base_size = 9) +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 60, hjust = 1), legend.position = "bottom")
    ggplot2::ggsave(file.path(output_root, "figures", paste0(tolower(wave), "_effective_group_tau.pdf")), p_tau, width = 10, height = 5)
  }
  p_contrib <- ggplot2::ggplot(contribution_paths, ggplot2::aes(horizon, contribution, color = rhs_global_group)) +
    ggplot2::geom_line() + ggplot2::facet_wrap(~candidate_id, scales = "free_y") +
    ggplot2::labs(x = "Forecast lead (days)", y = "Readout contribution", color = "Feature group") +
    ggplot2::theme_bw(base_size = 8) + ggplot2::theme(legend.position = "bottom")
  ggplot2::ggsave(file.path(output_root, "figures", paste0(tolower(wave), "_group_contribution_paths.pdf")), p_contrib, width = 12, height = 8)

  p_objective <- ggplot2::ggplot(objectives, ggplot2::aes(iteration, objective, color = candidate_id)) +
    ggplot2::geom_line(linewidth = 0.45) +
    ggplot2::labs(x = "VB iteration", y = "Approximate objective", color = "Candidate") +
    ggplot2::theme_bw(base_size = 9) + ggplot2::theme(legend.position = "bottom")
  ggplot2::ggsave(file.path(output_root, "figures", paste0(tolower(wave), "_objective_traces.pdf")), p_objective, width = 10, height = 6)
}

protected <- unique(c(control_id, head(scores$candidate_id[scores$eligible], 3L)))
cleanup <- artifacts
cleanup$protected <- cleanup$candidate_id %in% protected
cleanup$action <- ifelse(cleanup$protected, "keep", "delete_candidate_after_scientific_closeout")
cleanup$dry_run <- TRUE
app_write_csv(cleanup, file.path(output_root, "cleanup", paste0(tolower(wave), "_heavy_artifact_cleanup_dry_run.csv")))
cat(decision_path, "\n")
