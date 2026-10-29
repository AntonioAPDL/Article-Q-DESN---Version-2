# Phase170 target-invariance audit and exAL MCMC default promotion.

app_joint_exqdesn_phase170_dirs <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root()
) {
  recovery <- app_joint_exqdesn_phase169r_dirs(cache_root)
  c(recovery, list(
    phase170 = file.path(
      cache_root, "joint_exqdesn_phase170_exact_mcmc_default_promotion_20260808"
    )
  ))
}

app_joint_exqdesn_phase170_methods <- function() {
  c(
    baseline = "M0_v_collapsed_support_logit",
    winner = "M1b_u_collapsed_support_logit",
    excluded = "M1_u_collapsed_p_logit"
  )
}

app_joint_exqdesn_phase170_validate_source <- function(dirs) {
  top <- app_joint_exqdesn_verify_manifest(dirs$phase169r, "phase169r")
  freeze <- app_joint_exqdesn_phase169_load_freeze(dirs$phase169r_freeze)
  freeze_check <- app_joint_exqdesn_verify_manifest(
    dirs$phase169r_freeze, "phase169r_freeze"
  )
  worker_checks <- lapply(seq_len(nrow(freeze$plan)), function(ii) {
    check <- app_joint_exqdesn_verify_manifest(
      freeze$plan$worker_output_dir[[ii]],
      sprintf("phase169r_worker_%03d", freeze$plan$worker_id[[ii]])
    )
    check$worker_id <- freeze$plan$worker_id[[ii]]
    check
  })
  verification <- app_joint_qdesn_bind_rows(c(list(top, freeze_check), worker_checks))
  if (any(verification$status != "pass")) {
    stop("Phase170 source manifest verification failed.", call. = FALSE)
  }
  list(freeze = freeze, verification = verification)
}

app_joint_exqdesn_phase170_parameter_invariance <- function(diagnostics) {
  methods <- app_joint_exqdesn_phase170_methods()
  keys <- c(
    "scenario_id", "base_scenario_id", "fit_structure", "parameter",
    "quantile_index", "tau"
  )
  values <- c(
    "posterior_mean", "posterior_sd", "q05", "median", "q95",
    "mcse_mean", "rank_rhat", "bulk_ess", "tail_ess"
  )
  select <- function(method, suffix) {
    out <- diagnostics[
      diagnostics$inference_method_id == method,
      c(keys, values), drop = FALSE
    ]
    names(out)[match(values, names(out))] <- paste0(values, suffix)
    out
  }
  out <- merge(
    select(methods[["baseline"]], "_M0"),
    select(methods[["winner"]], "_M1b"),
    by = keys, all = FALSE, sort = FALSE
  )
  if (nrow(out) != 350L) {
    stop(sprintf("Expected 350 M0/M1b parameter comparisons; found %d.", nrow(out)), call. = FALSE)
  }
  out$mean_delta <- out$posterior_mean_M1b - out$posterior_mean_M0
  out$median_delta <- out$median_M1b - out$median_M0
  pooled_sd <- sqrt((out$posterior_sd_M0^2 + out$posterior_sd_M1b^2) / 2)
  out$standardized_mean_delta <- abs(out$mean_delta) / pmax(pooled_sd, .Machine$double.eps)
  combined_mcse <- sqrt(out$mcse_mean_M0^2 + out$mcse_mean_M1b^2)
  out$mean_delta_mcse_ratio <- abs(out$mean_delta) / pmax(combined_mcse, .Machine$double.eps)
  overlap <- pmax(0, pmin(out$q95_M0, out$q95_M1b) - pmax(out$q05_M0, out$q05_M1b))
  union <- pmax(out$q95_M0, out$q95_M1b) - pmin(out$q05_M0, out$q05_M1b)
  out$central90_overlap_fraction <- overlap / pmax(union, .Machine$double.eps)
  out$target_invariance_status <- ifelse(
    out$standardized_mean_delta <= 0.25 & out$central90_overlap_fraction >= 0.80,
    "pass", "review"
  )
  out
}

app_joint_exqdesn_phase170_qhat_moments <- function(fits, Z, tau) {
  Z <- as.matrix(Z)
  K <- length(tau)
  p <- ncol(Z)
  beta <- do.call(rbind, lapply(fits, `[[`, "beta_draws"))
  alpha <- do.call(rbind, lapply(fits, `[[`, "alpha_draws"))
  if (ncol(beta) != K * p || ncol(alpha) != K) {
    stop("Phase170 qhat draw dimensions do not match the fixture.", call. = FALSE)
  }
  X <- cbind(intercept = 1, Z)
  rows <- lapply(seq_len(K), function(k) {
    idx <- ((k - 1L) * p + 1L):(k * p)
    theta <- cbind(alpha[, k], beta[, idx, drop = FALSE])
    theta_mean <- colMeans(theta)
    theta_cov <- stats::cov(theta)
    q_mean <- as.numeric(X %*% theta_mean)
    q_var <- rowSums((X %*% theta_cov) * X)
    q_sd <- sqrt(pmax(q_var, 0))
    data.frame(
      row_index = seq_len(nrow(Z)),
      quantile_index = k,
      tau = tau[[k]],
      posterior_mean = q_mean,
      posterior_sd = q_sd,
      q05 = q_mean - stats::qnorm(0.95) * q_sd,
      q95 = q_mean + stats::qnorm(0.95) * q_sd,
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase170_forecast_design <- function(
  artifacts, scenario_id, fit_fixture
) {
  plan <- artifacts$forecast_origin_plan[
    artifacts$forecast_origin_plan$scenario_id == scenario_id, , drop = FALSE
  ]
  plan <- plan[order(plan$origin_index), , drop = FALSE]
  targets <- lapply(seq_len(nrow(plan)), function(ii) {
    target <- app_joint_qdesn_forecast_target_fixture(
      artifacts, scenario_id, plan[ii, , drop = FALSE]
    )
    if (!identical(fit_fixture$feature_cols, target$feature_cols)) {
      stop("Phase170 forecast feature columns differ from fit columns.", call. = FALSE)
    }
    target$Z
  })
  do.call(rbind, targets)
}

app_joint_exqdesn_phase170_load_cell_fits <- function(
  freeze, jobs, fixture
) {
  jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
  if (nrow(jobs) != 8L) stop("Phase170 requires eight chains per method cell.", call. = FALSE)
  lapply(seq_len(nrow(jobs)), function(ii) {
    app_joint_exqdesn_phase169_read_fit(
      jobs$worker_output_dir[[ii]], fixture$tau,
      jobs$chain_seed[[ii]], jobs$chain_id[[ii]]
    )
  })
}

app_joint_exqdesn_phase170_qhat_invariance <- function(freeze, dirs) {
  methods <- app_joint_exqdesn_phase170_methods()
  cases <- unique(freeze$plan[, c(
    "mcmc_case_id", "scenario_id", "base_scenario_id", "fit_structure"
  )])
  details <- list()
  summaries <- list()
  for (ii in seq_len(nrow(cases))) {
    case <- cases[ii, , drop = FALSE]
    artifacts <- app_joint_exqdesn_load_selected_fixture_artifacts(
      case$scenario_id[[1L]], dirs
    )
    fixture <- app_joint_qdesn_scenario_fixture(
      artifacts, case$scenario_id[[1L]], role = "fit"
    )
    designs <- list(
      fit = fixture$Z,
      forecast = app_joint_exqdesn_phase170_forecast_design(
        artifacts, case$scenario_id[[1L]], fixture
      )
    )
    moments <- list()
    for (method in methods[c("baseline", "winner")]) {
      jobs <- freeze$plan[
        freeze$plan$mcmc_case_id == case$mcmc_case_id[[1L]] &
          freeze$plan$inference_method_id == method,
        , drop = FALSE
      ]
      fits <- app_joint_exqdesn_phase170_load_cell_fits(freeze, jobs, fixture)
      moments[[method]] <- lapply(designs, function(Z) {
        app_joint_exqdesn_phase170_qhat_moments(fits, Z, fixture$tau)
      })
      rm(fits)
      invisible(gc(FALSE))
    }
    for (window in names(designs)) {
      m0 <- moments[[methods[["baseline"]]]][[window]]
      m1b <- moments[[methods[["winner"]]]][[window]]
      keys <- c("row_index", "quantile_index", "tau")
      joined <- merge(m0, m1b, by = keys, suffixes = c("_M0", "_M1b"), sort = FALSE)
      joined$mean_delta <- joined$posterior_mean_M1b - joined$posterior_mean_M0
      pooled_sd <- sqrt((joined$posterior_sd_M0^2 + joined$posterior_sd_M1b^2) / 2)
      joined$standardized_mean_delta <- abs(joined$mean_delta) /
        pmax(pooled_sd, .Machine$double.eps)
      overlap <- pmax(0, pmin(joined$q95_M0, joined$q95_M1b) - pmax(joined$q05_M0, joined$q05_M1b))
      union <- pmax(joined$q95_M0, joined$q95_M1b) - pmin(joined$q05_M0, joined$q05_M1b)
      joined$central90_overlap_fraction <- overlap / pmax(union, .Machine$double.eps)
      joined$scenario_id <- case$scenario_id[[1L]]
      joined$base_scenario_id <- case$base_scenario_id[[1L]]
      joined$fit_structure <- case$fit_structure[[1L]]
      joined$window <- window
      details[[length(details) + 1L]] <- joined
      summaries[[length(summaries) + 1L]] <- data.frame(
        scenario_id = case$scenario_id[[1L]],
        base_scenario_id = case$base_scenario_id[[1L]],
        fit_structure = case$fit_structure[[1L]],
        window = window,
        n_quantile_path_points = nrow(joined),
        mean_abs_qhat_delta = mean(abs(joined$mean_delta)),
        max_abs_qhat_delta = max(abs(joined$mean_delta)),
        median_standardized_qhat_delta = stats::median(joined$standardized_mean_delta),
        q99_standardized_qhat_delta = as.numeric(stats::quantile(
          joined$standardized_mean_delta, 0.99, names = FALSE, type = 8
        )),
        max_standardized_qhat_delta = max(joined$standardized_mean_delta),
        min_central90_overlap_fraction = min(joined$central90_overlap_fraction),
        q01_central90_overlap_fraction = as.numeric(stats::quantile(
          joined$central90_overlap_fraction, 0.01, names = FALSE, type = 8
        )),
        stringsAsFactors = FALSE
      )
    }
  }
  detail <- app_joint_qdesn_bind_rows(details)
  summary <- app_joint_qdesn_bind_rows(summaries)
  summary$target_invariance_status <- ifelse(
    summary$q99_standardized_qhat_delta <= 0.25 &
      summary$q01_central90_overlap_fraction >= 0.80,
    "pass", "review"
  )
  list(detail = detail, summary = summary)
}

app_joint_exqdesn_phase170_method_evidence <- function(summary, diagnostics) {
  methods <- app_joint_exqdesn_phase170_methods()
  rows <- lapply(methods, function(method) {
    s <- summary[summary$inference_method_id == method, , drop = FALSE]
    gamma <- diagnostics[
      diagnostics$inference_method_id == method & diagnostics$parameter == "gamma",
      , drop = FALSE
    ]
    data.frame(
      inference_method_id = method,
      n_cells = nrow(s),
      mean_forecast_truth_mae = mean(s$forecast_truth_mae),
      median_forecast_truth_mae = stats::median(s$forecast_truth_mae),
      mean_forecast_crps_grid = mean(s$forecast_crps_grid_mean),
      forecast_mae_cell_wins = NA_integer_,
      median_gamma_bulk_ess = stats::median(gamma$bulk_ess),
      min_gamma_bulk_ess = min(gamma$bulk_ess),
      max_gamma_rank_rhat = max(gamma$rank_rhat),
      runtime_hours = sum(s$runtime_seconds_total) / 3600,
      raw_crossing_pairs = sum(s$raw_crossing_pairs),
      contract_crossing_pairs = sum(s$contract_crossing_pairs),
      all_draws_finite = all(s$all_draws_finite),
      stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  keys <- interaction(summary$scenario_id, summary$fit_structure, drop = TRUE)
  winners <- vapply(split(summary, keys), function(x) {
    x$inference_method_id[[which.min(x$forecast_truth_mae)]]
  }, character(1L))
  out$forecast_mae_cell_wins <- as.integer(table(factor(
    winners, levels = out$inference_method_id
  )))
  baseline <- out[out$inference_method_id == methods[["baseline"]], ]
  out$runtime_ratio_vs_M0 <- out$runtime_hours / baseline$runtime_hours[[1L]]
  out$mean_forecast_mae_delta_vs_M0 <-
    out$mean_forecast_truth_mae - baseline$mean_forecast_truth_mae[[1L]]
  out
}

app_joint_exqdesn_phase170_decision <- function(
  phase169_assessment, parameter_invariance, qhat_summary, method_evidence
) {
  methods <- app_joint_exqdesn_phase170_methods()
  m0 <- method_evidence[method_evidence$inference_method_id == methods[["baseline"]], ]
  m1b <- method_evidence[method_evidence$inference_method_id == methods[["winner"]], ]
  m1 <- method_evidence[method_evidence$inference_method_id == methods[["excluded"]], ]
  gates <- data.frame(
    gate_id = c(
      "phase169_complete", "implementation_integrity", "contract_noncrossing",
      "parameter_target_invariance", "qhat_target_invariance",
      "m1b_forecast_noninferiority", "m1b_runtime_overhead",
      "m1b_gamma_efficiency", "exclude_m1_cost_efficiency"
    ),
    observed = c(
      sprintf("%s/%s", phase169_assessment$completed_workers, phase169_assessment$expected_workers),
      as.character(phase169_assessment$implementation_failures),
      as.character(phase169_assessment$contract_crossing_pairs),
      sprintf("max_std=%.4f;min_overlap=%.4f",
        max(parameter_invariance$standardized_mean_delta),
        min(parameter_invariance$central90_overlap_fraction)),
      sprintf("max_q99_std=%.4f;min_q01_overlap=%.4f",
        max(qhat_summary$q99_standardized_qhat_delta),
        min(qhat_summary$q01_central90_overlap_fraction)),
      sprintf("delta=%.6f", m1b$mean_forecast_mae_delta_vs_M0),
      sprintf("ratio=%.4f", m1b$runtime_ratio_vs_M0),
      sprintf("median=%0.1f;min=%0.1f", m1b$median_gamma_bulk_ess, m1b$min_gamma_bulk_ess),
      sprintf("wins=%d;runtime_ratio=%.4f;min_gamma_ess=%.1f",
        m1$forecast_mae_cell_wins, m1$runtime_ratio_vs_M0, m1$min_gamma_bulk_ess)
    ),
    criterion = c(
      "240/240", "zero failures", "zero crossings",
      "max standardized difference <= 0.25 and minimum overlap >= 0.80",
      "all q99 standardized differences <= 0.25 and q01 overlaps >= 0.80",
      "mean forecast MAE no more than 0.0025 above M0",
      "runtime ratio no more than 1.05",
      "median gamma ESS at least M0 and minimum gamma ESS at least 200",
      "exclude when slower than 1.10 with no compensating cell wins or ESS gain"
    ),
    status = c(
      ifelse(phase169_assessment$completed_workers == 240L, "pass", "fail"),
      ifelse(phase169_assessment$implementation_failures == 0L, "pass", "fail"),
      ifelse(phase169_assessment$contract_crossing_pairs == 0L, "pass", "fail"),
      ifelse(max(parameter_invariance$standardized_mean_delta) <= 0.25 &&
        min(parameter_invariance$central90_overlap_fraction) >= 0.80, "pass", "review"),
      ifelse(all(qhat_summary$target_invariance_status == "pass"), "pass", "review"),
      ifelse(m1b$mean_forecast_mae_delta_vs_M0 <= 0.0025, "pass", "review"),
      ifelse(m1b$runtime_ratio_vs_M0 <= 1.05, "pass", "review"),
      ifelse(m1b$median_gamma_bulk_ess >= m0$median_gamma_bulk_ess &&
        m1b$min_gamma_bulk_ess >= 200, "pass", "review"),
      ifelse(m1$runtime_ratio_vs_M0 > 1.10 && m1$forecast_mae_cell_wins <= 1L, "pass", "review")
    ),
    stringsAsFactors = FALSE
  )
  hard_failure <- any(gates$status[seq_len(3L)] == "fail")
  challenger_pass <- !hard_failure && all(gates$status == "pass")
  selected <- if (hard_failure) {
    NA_character_
  } else if (challenger_pass) {
    methods[["winner"]]
  } else {
    methods[["baseline"]]
  }
  decision <- data.frame(
    decision_status = if (hard_failure) {
      "fail_no_promotion"
    } else if (challenger_pass) {
      "pass_promoted_M1b"
    } else {
      "pass_promoted_M0_with_M1b_review"
    },
    production_default_method_id = selected,
    baseline_method_id = methods[["baseline"]],
    excluded_method_id = methods[["excluded"]],
    scope = "joint_and_independent_exAL_MCMC_dispatch",
    evidence_role = "computational_default_not_model_specification",
    qualification = if (challenger_pass) paste(
      "M1b passed target-invariance tolerances and improved median gamma ESS at",
      "near-baseline runtime; scenario-specific mixing reviews remain visible."
    ) else paste(
      "M0 is the exact production baseline. M1b improved median gamma ESS at",
      "near-baseline runtime but retained quantile-path target-invariance reviews."
    ),
    explicit_override_supported = TRUE,
    article_assets_modified = FALSE,
    stringsAsFactors = FALSE
  )
  list(gates = gates, decision = decision)
}

app_joint_exqdesn_phase170_run <- function(
  dirs = app_joint_exqdesn_phase170_dirs()
) {
  app_ensure_dir(dirs$phase170)
  source <- app_joint_exqdesn_phase170_validate_source(dirs)
  phase169_summary <- app_read_csv(file.path(dirs$phase169r, "phase169_case_method_summary.csv"))
  phase169_diagnostics <- app_read_csv(file.path(dirs$phase169r, "phase169_parameter_diagnostics.csv"))
  phase169_assessment <- app_read_csv(file.path(dirs$phase169r, "phase169_assessment.csv"))
  if (nrow(phase169_summary) != 30L || sum(phase169_summary$n_chains) != 240L ||
      any(!phase169_summary$all_draws_finite)) {
    stop("Phase170 source summary is incomplete or nonfinite.", call. = FALSE)
  }
  parameter_invariance <- app_joint_exqdesn_phase170_parameter_invariance(phase169_diagnostics)
  qhat <- app_joint_exqdesn_phase170_qhat_invariance(source$freeze, dirs)
  method_evidence <- app_joint_exqdesn_phase170_method_evidence(
    phase169_summary, phase169_diagnostics
  )
  decision <- app_joint_exqdesn_phase170_decision(
    phase169_assessment, parameter_invariance, qhat$summary, method_evidence
  )
  policy <- app_joint_exqdesn_load_default_policy()
  if (!identical(
    decision$decision$production_default_method_id[[1L]],
    policy$default_method_id[policy$inference_family == "mcmc"][[1L]]
  )) {
    stop("The checked-in exAL default policy does not match the Phase170 decision.", call. = FALSE)
  }
  source_snapshot <- data.frame(
    relative_path = c(
      "application/config/joint_exqdesn_inference_default_policy_v1.csv",
      "application/config/joint_exqdesn_inference_method_registry_v1.csv",
      "application/R/joint_exqdesn_inference_dispatch.R",
      "application/R/joint_exqdesn_phase170_default_promotion.R"
    ),
    stringsAsFactors = FALSE
  )
  source_snapshot$size_bytes <- as.numeric(file.info(app_path(source_snapshot$relative_path))$size)
  source_snapshot$sha256 <- vapply(app_path(source_snapshot$relative_path), app_sha256_file, character(1L))
  provenance <- app_joint_qdesn_bind_rows(list(
    app_joint_qvp_provenance_rows(),
    data.frame(
      key = c(
        "phase170_implementation_commit",
        "phase169r_artifact_manifest_sha256",
        "phase170_default_policy_sha256"
      ),
      value = c(
        app_git_sha(short = FALSE),
        app_sha256_file(file.path(dirs$phase169r, "artifact_manifest.csv")),
        app_sha256_file(app_joint_exqdesn_default_policy_path())
      ),
      stringsAsFactors = FALSE
    )
  ))
  readme <- file.path(dirs$phase170, "README.md")
  writeLines(c(
    "# Phase170 exact exQDESN MCMC default promotion", "",
    "Phase170 audits M0/M1b equality of target summaries using the completed Phase169R evidence.",
    "The promotion changes only omitted-method dispatch for exAL MCMC. Explicit method identifiers remain available.",
    "M0 is the computational default; M1b remains an explicit review-level candidate.",
    "The selection is not a universal DESN specification and does not define a new posterior target.",
    "No article assets are modified by this artifact."
  ), readme, useBytes = TRUE)
  paths <- c(
    source_manifest_verification = app_joint_qvp_write_csv(
      source$verification, file.path(dirs$phase170, "source_manifest_verification.csv")
    ),
    parameter_target_invariance = app_joint_qvp_write_csv(
      parameter_invariance, file.path(dirs$phase170, "parameter_target_invariance.csv")
    ),
    qhat_target_invariance_summary = app_joint_qvp_write_csv(
      qhat$summary, file.path(dirs$phase170, "qhat_target_invariance_summary.csv")
    ),
    qhat_target_invariance_detail = app_joint_qvp_write_csv(
      qhat$detail, file.path(dirs$phase170, "qhat_target_invariance_detail.csv")
    ),
    method_evidence_summary = app_joint_qvp_write_csv(
      method_evidence, file.path(dirs$phase170, "method_evidence_summary.csv")
    ),
    promotion_gate_audit = app_joint_qvp_write_csv(
      decision$gates, file.path(dirs$phase170, "promotion_gate_audit.csv")
    ),
    default_decision = app_joint_qvp_write_csv(
      decision$decision, file.path(dirs$phase170, "default_decision.csv")
    ),
    default_policy_snapshot = app_joint_qvp_write_csv(
      policy, file.path(dirs$phase170, "default_policy_snapshot.csv")
    ),
    source_code_snapshot = app_joint_qvp_write_csv(
      source_snapshot, file.path(dirs$phase170, "source_code_snapshot.csv")
    ),
    provenance = app_joint_qvp_write_csv(
      provenance, file.path(dirs$phase170, "provenance.csv")
    ),
    README = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_write_manifest(paths, dirs$phase170)
  list(
    decision = decision$decision,
    gates = decision$gates,
    method_evidence = method_evidence,
    qhat_summary = qhat$summary,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}
