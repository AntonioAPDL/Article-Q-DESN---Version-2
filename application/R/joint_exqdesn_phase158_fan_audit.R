# Phase158: draw-backed quantile-fan decomposition and Phase159 calibration plan.

app_joint_exqdesn_phase158_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase158_quantile_fan_decomposition_20260804")
}

app_joint_exqdesn_phase158_default_phase157_dir <- function() {
  app_path("application/cache/joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802")
}

app_joint_exqdesn_phase158_default_freeze_dir <- function() {
  app_path("application/cache/joint_qdesn_phase156b_collapsed_gamma_sigma_recovery_freeze_20260802")
}

app_joint_exqdesn_phase158_verify_source <- function(dir, source_id) {
  out <- app_joint_qdesn_phase108_manifest_verify(dir, source_id)
  if (!nrow(out) || any(out$status != "pass")) {
    stop(sprintf("Phase158 source manifest failed for '%s'.", source_id), call. = FALSE)
  }
  out
}

app_joint_exqdesn_phase158_forecast_fixture <- function(artifacts, scenario_id, fit_fixture) {
  plan <- artifacts$forecast_origin_plan
  plan <- plan[plan$scenario_id == scenario_id, , drop = FALSE]
  plan <- plan[order(plan$origin_index), , drop = FALSE]
  targets <- lapply(seq_len(nrow(plan)), function(ii) {
    target <- app_joint_qdesn_forecast_target_fixture(artifacts, scenario_id, plan[ii, , drop = FALSE])
    if (!identical(target$feature_cols, fit_fixture$feature_cols)) {
      stop(sprintf("Phase158 feature mismatch for '%s'.", scenario_id), call. = FALSE)
    }
    target
  })
  list(
    scenario_id = scenario_id,
    role = "forecast",
    y = unlist(lapply(targets, `[[`, "y"), use.names = FALSE),
    Z = do.call(rbind, lapply(targets, `[[`, "Z")),
    tau = fit_fixture$tau,
    true_q = do.call(rbind, lapply(targets, `[[`, "true_q")),
    row_meta = app_joint_qdesn_bind_rows(lapply(targets, `[[`, "row_meta")),
    feature_cols = fit_fixture$feature_cols
  )
}

app_joint_exqdesn_phase158_pooled_means <- function(freeze, scenario_id, tau) {
  jobs <- freeze$plan[freeze$plan$scenario_id == scenario_id, , drop = FALSE]
  jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
  fits <- lapply(seq_len(nrow(jobs)), function(ii) {
    app_joint_exqdesn_phase157_read_fit(
      jobs$worker_output_dir[[ii]], tau,
      jobs$chain_seed[[ii]], jobs$chain_id[[ii]]
    )
  })
  beta <- do.call(rbind, lapply(fits, `[[`, "beta_draws"))
  alpha <- do.call(rbind, lapply(fits, `[[`, "alpha_draws"))
  sigma <- do.call(rbind, lapply(fits, `[[`, "sigma_draws"))
  gamma <- do.call(rbind, lapply(fits, `[[`, "gamma_draws"))
  if (any(!is.finite(c(beta, alpha, sigma, gamma))) || any(sigma <= 0)) {
    stop(sprintf("Phase158 encountered invalid draws for '%s'.", scenario_id), call. = FALSE)
  }
  list(
    beta_mean = colMeans(beta), alpha_mean = colMeans(alpha),
    sigma_mean = colMeans(sigma), gamma_mean = colMeans(gamma),
    fits = fits, jobs = jobs, n_draws = nrow(beta)
  )
}

app_joint_exqdesn_phase158_component_tables <- function(window, posterior, scenario_id) {
  K <- length(window$tau)
  p <- ncol(window$Z)
  beta <- app_joint_qvp_beta_matrix(posterior$beta_mean, K, p)
  dynamic <- window$Z %*% beta
  intercept <- matrix(posterior$alpha_mean, nrow(window$Z), K, byrow = TRUE)
  qhat <- dynamic + intercept
  quantile <- app_joint_qdesn_bind_rows(lapply(seq_len(K), function(kk) {
    err <- qhat[, kk] - window$true_q[, kk]
    data.frame(
      scenario_id = scenario_id, validation_window = window$role,
      quantile_index = kk, tau = window$tau[[kk]], n_rows = nrow(qhat),
      mean_true_quantile = mean(window$true_q[, kk]),
      mean_fitted_quantile = mean(qhat[, kk]),
      mean_intercept_component = posterior$alpha_mean[[kk]],
      mean_dynamic_component = mean(dynamic[, kk]),
      truth_bias = mean(err), truth_mae = mean(abs(err)),
      truth_rmse = sqrt(mean(err^2)),
      stringsAsFactors = FALSE
    )
  }))
  adjacent <- app_joint_qdesn_bind_rows(lapply(seq_len(K - 1L), function(kk) {
    true_gap <- window$true_q[, kk + 1L] - window$true_q[, kk]
    dynamic_gap <- dynamic[, kk + 1L] - dynamic[, kk]
    alpha_gap <- posterior$alpha_mean[[kk + 1L]] - posterior$alpha_mean[[kk]]
    fitted_gap <- alpha_gap + dynamic_gap
    data.frame(
      scenario_id = scenario_id, validation_window = window$role,
      lower_tau = window$tau[[kk]], upper_tau = window$tau[[kk + 1L]],
      n_rows = length(true_gap), mean_true_gap = mean(true_gap),
      mean_fitted_gap = mean(fitted_gap), mean_alpha_gap = alpha_gap,
      mean_dynamic_gap = mean(dynamic_gap),
      mean_abs_dynamic_gap = mean(abs(dynamic_gap)),
      gap_bias = mean(fitted_gap - true_gap),
      gap_mae = mean(abs(fitted_gap - true_gap)),
      fitted_to_true_gap_ratio = mean(fitted_gap) / mean(true_gap),
      nonpositive_fitted_gap_count = sum(fitted_gap <= 0),
      stringsAsFactors = FALSE
    )
  }))
  interval_pairs <- which(outer(window$tau, window$tau, function(a, b) abs((a + b) - 1) < 1.0e-10) &
                            outer(window$tau, window$tau, `<`), arr.ind = TRUE)
  interval <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(interval_pairs)), function(ii) {
    lo <- interval_pairs[ii, 1L]
    hi <- interval_pairs[ii, 2L]
    true_width <- window$true_q[, hi] - window$true_q[, lo]
    dynamic_width <- dynamic[, hi] - dynamic[, lo]
    alpha_width <- posterior$alpha_mean[[hi]] - posterior$alpha_mean[[lo]]
    fitted_width <- alpha_width + dynamic_width
    data.frame(
      scenario_id = scenario_id, validation_window = window$role,
      lower_tau = window$tau[[lo]], upper_tau = window$tau[[hi]],
      nominal_coverage = window$tau[[hi]] - window$tau[[lo]],
      mean_true_width = mean(true_width), mean_fitted_width = mean(fitted_width),
      mean_alpha_width = alpha_width, mean_dynamic_width = mean(dynamic_width),
      fitted_to_true_width_ratio = mean(fitted_width) / mean(true_width),
      width_bias = mean(fitted_width - true_width),
      width_mae = mean(abs(fitted_width - true_width)),
      stringsAsFactors = FALSE
    )
  }))
  list(quantile = quantile, adjacent = adjacent, interval = interval)
}

app_joint_exqdesn_phase158_chain_stability <- function(window, posterior, scenario_id) {
  K <- length(window$tau)
  p <- ncol(window$Z)
  app_joint_qdesn_bind_rows(lapply(seq_along(posterior$fits), function(ii) {
    fit <- posterior$fits[[ii]]
    beta <- app_joint_qvp_beta_matrix(colMeans(fit$beta_draws), K, p)
    alpha <- colMeans(fit$alpha_draws)
    qhat <- window$Z %*% beta + matrix(alpha, nrow(window$Z), K, byrow = TRUE)
    err <- qhat - window$true_q
    data.frame(
      scenario_id = scenario_id, validation_window = window$role,
      chain_id = posterior$jobs$chain_id[[ii]],
      chain_seed = posterior$jobs$chain_seed[[ii]],
      truth_mae = mean(abs(err)),
      lower_tail_mae = mean(abs(err[, window$tau <= 0.10, drop = FALSE])),
      center_mae = mean(abs(err[, abs(window$tau - 0.50) < 1.0e-10, drop = FALSE])),
      upper_tail_mae = mean(abs(err[, window$tau >= 0.90, drop = FALSE])),
      outer_width = mean(qhat[, K] - qhat[, 1L]),
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase158_decisions <- function(assessment, comparison, interval, adjacent) {
  forecast_interval <- interval[interval$validation_window == "forecast", , drop = FALSE]
  outer <- forecast_interval[forecast_interval$lower_tau == min(forecast_interval$lower_tau) &
                               forecast_interval$upper_tau == max(forecast_interval$upper_tau), , drop = FALSE]
  upper <- adjacent[adjacent$validation_window == "forecast" & adjacent$upper_tau == max(adjacent$upper_tau), , drop = FALSE]
  x <- merge(
    assessment[, c("scenario_id", "mixing_status", "chain_group_stability_status", "gate_status")],
    comparison[, c("scenario_id", "delta_forecast_mae_vs_matched_al", "performance_status")],
    by = "scenario_id", all = TRUE, sort = FALSE
  )
  x <- merge(x, outer[, c("scenario_id", "fitted_to_true_width_ratio")], by = "scenario_id", all.x = TRUE, sort = FALSE)
  names(x)[names(x) == "fitted_to_true_width_ratio"] <- "outer_width_ratio"
  x <- merge(x, upper[, c("scenario_id", "fitted_to_true_gap_ratio", "mean_alpha_gap", "mean_dynamic_gap")], by = "scenario_id", all.x = TRUE, sort = FALSE)
  x$decision <- ifelse(
    x$scenario_id == "persistent_heavy_tail", "freeze_confirmed_success",
    ifelse(x$scenario_id == "asymmetric_laplace_tail", "stabilize_same_specification",
           "target_split_rhs_calibration")
  )
  x$diagnosis <- ifelse(
    x$decision == "freeze_confirmed_success", "collapsed MCMC is competitive and all declared gates pass",
    ifelse(x$decision == "stabilize_same_specification",
           "material improvement is present but chain-group and mixing diagnostics remain review-level",
           ifelse(x$outer_width_ratio < 0.9,
                  "forecast quantile fan is compressed; separate innovation shrinkage from anchor shrinkage",
                  "tail error remains material despite adequate global width; inspect adjacent innovation allocation"))
  )
  severity <- pmax(0, x$delta_forecast_mae_vs_matched_al) / pmax(0.0025, abs(x$delta_forecast_mae_vs_matched_al) + 0.05)
  x$recommended_innovation_tau0_multipliers <- ifelse(
    x$decision != "target_split_rhs_calibration", "1",
    ifelse(severity > 0.45, "1,2,3", ifelse(severity > 0.25, "1,1.5,2", "1,1.25,1.5"))
  )
  x$recommended_innovation_zeta2_multipliers <- ifelse(x$decision == "target_split_rhs_calibration", "1,2", "1")
  x$article_promotion <- FALSE
  x
}

app_joint_exqdesn_run_phase158 <- function(
  out_dir = app_joint_exqdesn_phase158_default_dir(),
  phase157_dir = app_joint_exqdesn_phase158_default_phase157_dir(),
  freeze_dir = app_joint_exqdesn_phase158_default_freeze_dir()
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  phase157_dir <- normalizePath(phase157_dir, mustWork = TRUE)
  freeze_dir <- normalizePath(freeze_dir, mustWork = TRUE)
  app_ensure_dir(out_dir)
  source_verification <- app_joint_qdesn_bind_rows(list(
    app_joint_exqdesn_phase158_verify_source(phase157_dir, "phase157b"),
    app_joint_exqdesn_phase158_verify_source(freeze_dir, "phase156b")
  ))
  freeze <- app_joint_exqdesn_phase157_load_freeze(freeze_dir)
  artifacts <- app_joint_qdesn_load_fixture_artifacts(freeze$config$fixture_dir[[1L]])
  assessment <- app_joint_exqdesn_phase156_read_csv(file.path(phase157_dir, "mcmc_case_assessment.csv"))
  comparison <- app_joint_exqdesn_phase156_read_csv(file.path(phase157_dir, "phase150_comparison.csv"))
  scenario_ids <- sort(unique(freeze$plan$scenario_id))
  results <- lapply(scenario_ids, function(scenario_id) {
    fit_window <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
    forecast_window <- app_joint_exqdesn_phase158_forecast_fixture(artifacts, scenario_id, fit_window)
    posterior <- app_joint_exqdesn_phase158_pooled_means(freeze, scenario_id, fit_window$tau)
    components <- lapply(list(fit_window, forecast_window), function(window) {
      app_joint_exqdesn_phase158_component_tables(window, posterior, scenario_id)
    })
    list(
      posterior = data.frame(
        scenario_id = scenario_id, n_chains = length(posterior$fits), n_draws = posterior$n_draws,
        beta_l2 = sqrt(sum(posterior$beta_mean^2)),
        alpha_min = min(posterior$alpha_mean), alpha_max = max(posterior$alpha_mean),
        sigma_min = min(posterior$sigma_mean), sigma_max = max(posterior$sigma_mean),
        gamma_min = min(posterior$gamma_mean), gamma_max = max(posterior$gamma_mean),
        stringsAsFactors = FALSE
      ),
      quantile = app_joint_qdesn_bind_rows(lapply(components, `[[`, "quantile")),
      adjacent = app_joint_qdesn_bind_rows(lapply(components, `[[`, "adjacent")),
      interval = app_joint_qdesn_bind_rows(lapply(components, `[[`, "interval")),
      stability = app_joint_qdesn_bind_rows(lapply(list(fit_window, forecast_window), function(window) {
        app_joint_exqdesn_phase158_chain_stability(window, posterior, scenario_id)
      }))
    )
  })
  bind <- function(name) app_joint_qdesn_bind_rows(lapply(results, `[[`, name))
  posterior <- bind("posterior")
  quantile <- bind("quantile")
  adjacent <- bind("adjacent")
  interval <- bind("interval")
  stability <- bind("stability")
  decisions <- app_joint_exqdesn_phase158_decisions(assessment, comparison, interval, adjacent)
  implementation_fail <- any(!is.finite(quantile$truth_mae)) || any(!is.finite(adjacent$fitted_to_true_gap_ratio)) ||
    any(adjacent$nonpositive_fitted_gap_count > 0L) || any(assessment$contract_crossing_pairs > 0L)
  audit <- data.frame(
    audit_id = "phase158_quantile_fan_decomposition",
    gate_status = if (implementation_fail) "fail" else "pass",
    scenarios = length(scenario_ids), posterior_draws = sum(posterior$n_draws),
    source_hash_failures = sum(source_verification$status != "pass"),
    nonpositive_gap_rows = sum(adjacent$nonpositive_fitted_gap_count),
    confirmed_successes = sum(decisions$decision == "freeze_confirmed_success"),
    stabilization_cases = sum(decisions$decision == "stabilize_same_specification"),
    calibration_cases = sum(decisions$decision == "target_split_rhs_calibration"),
    recommendation = if (implementation_fail) "repair_phase158_before_calibration" else "prepare_case_specific_phase159_split_rhs_screen",
    stringsAsFactors = FALSE
  )
  run_config <- data.frame(
    phase_id = "phase158_quantile_fan_decomposition",
    phase157_dir = phase157_dir, freeze_dir = freeze_dir,
    fixture_dir = freeze$config$fixture_dir[[1L]],
    posterior_summary = "pooled_posterior_mean_from_verified_draws",
    validation_contract = "raw_decomposition_with_existing_monotone_scoring_contract",
    stringsAsFactors = FALSE
  )
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Phase158 quantile-fan decomposition", "",
    "This packet diagnoses the completed Phase157b Joint exQDESN posterior without refitting the model.",
    "It decomposes fitted quantile gaps into ordered-intercept and dynamic readout contributions and freezes scenario-specific next actions.",
    "Phase159 is allowed to vary anchor and innovation RHS controls separately; it must not repeat prior gamma-width, posterior-summary, or reservoir screens.", "",
    sprintf("- Gate: `%s`", audit$gate_status[[1L]]),
    sprintf("- Draws audited: %d", audit$posterior_draws[[1L]]),
    sprintf("- Phase159 calibration cases: %d", audit$calibration_cases[[1L]])
  ), readme, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    source_manifest_verification = app_joint_qvp_write_csv(source_verification, file.path(out_dir, "source_manifest_verification.csv")),
    posterior_block_summary = app_joint_qvp_write_csv(posterior, file.path(out_dir, "posterior_block_summary.csv")),
    quantile_component_summary = app_joint_qvp_write_csv(quantile, file.path(out_dir, "quantile_component_summary.csv")),
    adjacent_gap_summary = app_joint_qvp_write_csv(adjacent, file.path(out_dir, "adjacent_gap_summary.csv")),
    interval_width_summary = app_joint_qvp_write_csv(interval, file.path(out_dir, "interval_width_summary.csv")),
    chain_component_stability = app_joint_qvp_write_csv(stability, file.path(out_dir, "chain_component_stability.csv")),
    scenario_diagnosis = app_joint_qvp_write_csv(decisions, file.path(out_dir, "scenario_diagnosis.csv")),
    phase158_assessment = app_joint_qvp_write_csv(audit, file.path(out_dir, "phase158_assessment.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_trace_manifest(paths, out_dir)
  list(out_dir = out_dir, assessment = audit, decisions = decisions,
       paths = c(paths, artifact_manifest = manifest$manifest_path))
}
