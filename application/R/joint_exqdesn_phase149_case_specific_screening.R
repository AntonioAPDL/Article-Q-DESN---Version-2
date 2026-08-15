# Phase149 case-specific Joint exQDESN VB/VB-LD specification screening.

app_joint_exqdesn_phase149_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase149_case_specific_exal_screening_20260726")
}

app_joint_exqdesn_phase149_default_readiness_dir <- function() {
  app_path("application/cache/joint_qdesn_phase149_case_specific_exal_screening_readiness_20260726")
}

app_joint_exqdesn_phase149_default_phase121_dir <- function() {
  app_path("application/cache/joint_qdesn_phase121_case_vb_winner_freeze_20260711")
}

app_joint_exqdesn_phase149_default_phase134_dir <- function() {
  app_path("application/cache/joint_qdesn_phase134_exal_targeted_screening_20260715")
}

app_joint_exqdesn_phase149_default_phase124b_dir <- function() {
  app_path("application/cache/joint_qdesn_phase124b_missing_cell_vb_winner_freeze_20260711")
}

app_joint_exqdesn_phase149_default_phase148_dir <- function() {
  app_joint_exqdesn_phase148_default_dir()
}

app_joint_exqdesn_phase149_manifest_verification <- function(dir, source_id) {
  manifest_path <- file.path(dir, "artifact_manifest.csv")
  if (!file.exists(manifest_path)) {
    return(data.frame(
      source_id = source_id, label = "artifact_manifest", relative_path = "artifact_manifest.csv",
      exists = FALSE, hash_verified = FALSE, stringsAsFactors = FALSE
    ))
  }
  manifest <- app_read_csv(manifest_path)
  app_check_required_columns(manifest, c("label", "relative_path", "sha256"), paste(source_id, "manifest"))
  rows <- lapply(seq_len(nrow(manifest)), function(ii) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    exists <- file.exists(path)
    actual <- if (exists) app_sha256_file(path) else NA_character_
    data.frame(
      source_id = source_id,
      label = manifest$label[[ii]],
      relative_path = manifest$relative_path[[ii]],
      exists = exists,
      declared_sha256 = manifest$sha256[[ii]],
      actual_sha256 = actual,
      hash_verified = exists && identical(tolower(actual), tolower(manifest$sha256[[ii]])),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_joint_exqdesn_phase149_phase134_best <- function(phase134_dir) {
  path <- file.path(phase134_dir, "forecast_scenario_metric_summary.csv")
  if (!file.exists(path)) return(data.frame())
  x <- app_read_csv(path)
  x <- x[x$model_id == "joint_exqdesn_rhs_vb" & is.finite(x$truth_mae), , drop = FALSE]
  if (!nrow(x)) return(x)
  best <- do.call(rbind, lapply(split(x, x$scenario_id), function(block) {
    block[order(block$truth_mae, block$check_loss_mean, block$candidate_id), , drop = FALSE][1L, , drop = FALSE]
  }))
  registry_path <- file.path(
    dirname(phase134_dir),
    "joint_qdesn_phase134_exal_targeted_screening_readiness_20260715",
    "phase134_targeted_exal_screening_registry.csv"
  )
  if (!file.exists(registry_path)) return(best)
  registry <- app_read_csv(registry_path)
  out <- merge(
    best[, c("scenario_id", "candidate_id", "truth_mae", "check_loss_mean"), drop = FALSE],
    registry,
    by = "candidate_id",
    all.x = TRUE,
    sort = FALSE
  )
  out
}

app_joint_exqdesn_phase149_controls <- function(row) {
  list(
    tau0 = as.numeric(row$tau0[[1L]]),
    zeta2 = as.numeric(row$zeta2[[1L]]),
    alpha_prior_sd = as.numeric(row$alpha_prior_sd[[1L]]),
    alpha_min_spacing = as.numeric(row$alpha_min_spacing[[1L]]),
    gamma_init_policy = as.character(row$gamma_init_policy[[1L]]),
    vb_max_iter = max(2400L, as.integer(row$vb_max_iter[[1L]])),
    rhs_vb_inner = max(14L, as.integer(row$rhs_vb_inner[[1L]])),
    a_sigma = as.numeric(row$a_sigma[[1L]]),
    b_sigma = as.numeric(row$b_sigma[[1L]]),
    max_dense_dim = as.integer(row$max_dense_dim[[1L]])
  )
}

app_joint_exqdesn_phase149_clamp <- function(x, lower, upper) {
  pmin(pmax(as.numeric(x), lower), upper)
}

app_joint_exqdesn_phase149_candidate_specs <- function(center, phase121, al) {
  center_controls <- app_joint_exqdesn_phase149_controls(center)
  p121_controls <- app_joint_exqdesn_phase149_controls(phase121)
  al_controls <- app_joint_exqdesn_phase149_controls(al)
  values <- function(role, controls, note) {
    data.frame(
      phase149_role = role,
      tau0 = controls$tau0,
      zeta2 = controls$zeta2,
      alpha_prior_sd = controls$alpha_prior_sd,
      alpha_min_spacing = controls$alpha_min_spacing,
      gamma_init_policy = controls$gamma_init_policy,
      vb_max_iter = controls$vb_max_iter,
      rhs_vb_inner = controls$rhs_vb_inner,
      a_sigma = controls$a_sigma,
      b_sigma = controls$b_sigma,
      max_dense_dim = controls$max_dense_dim,
      notes = note,
      stringsAsFactors = FALSE
    )
  }
  modified <- function(role, ..., note) {
    controls <- center_controls
    changes <- list(...)
    for (nm in names(changes)) controls[[nm]] <- changes[[nm]]
    values(role, controls, note)
  }
  zeta_down <- max(8, center_controls$zeta2 / 2)
  zeta_up <- min(256, center_controls$zeta2 * 2)
  do.call(rbind, list(
    values("phase121_reference", p121_controls, "Frozen Phase121 case-specific exAL winner."),
    values("prior_best_reference", center_controls, "Best available Phase134 row when present; otherwise Phase121."),
    values("matched_al_reference", al_controls, "Corresponding case-specific AL controls applied to exAL."),
    modified(
      "tau0_lower", tau0 = app_joint_exqdesn_phase149_clamp(center_controls$tau0 * 0.60, 0.10, 1.50),
      note = "Scenario-local stronger RHS shrinkage."
    ),
    modified(
      "tau0_upper", tau0 = app_joint_exqdesn_phase149_clamp(center_controls$tau0 * 1.50, 0.10, 1.50),
      note = "Scenario-local weaker RHS shrinkage."
    ),
    modified("zeta2_lower", zeta2 = zeta_down, note = "Tighter finite readout cap around the case center."),
    modified("zeta2_upper", zeta2 = zeta_up, note = "Looser finite readout cap around the case center."),
    modified(
      "alpha_sd_lower",
      alpha_prior_sd = app_joint_exqdesn_phase149_clamp(center_controls$alpha_prior_sd * 0.67, 0.35, 2),
      note = "Tighter ordered-intercept fan around the case center."
    ),
    modified(
      "alpha_sd_upper",
      alpha_prior_sd = app_joint_exqdesn_phase149_clamp(center_controls$alpha_prior_sd * 1.50, 0.35, 2),
      note = "Wider ordered-intercept fan around the case center."
    ),
    modified("gamma_init_zero", gamma_init_policy = "zero", note = "Tests the AL-like gamma basin."),
    modified("gamma_init_half", gamma_init_policy = "half_default", note = "Tests an interior gamma basin."),
    modified("gamma_init_default", gamma_init_policy = "default", note = "Tests the default exAL gamma basin.")
  ))
}

app_joint_exqdesn_phase149_slug_num <- function(x) {
  gsub("-", "m", gsub("\\.", "p", format(as.numeric(x), trim = TRUE, scientific = FALSE)))
}

app_joint_exqdesn_phase149_build_registry <- function(
  phase121_dir = app_joint_exqdesn_phase149_default_phase121_dir(),
  phase124b_dir = app_joint_exqdesn_phase149_default_phase124b_dir(),
  phase134_dir = app_joint_exqdesn_phase149_default_phase134_dir(),
  screening_dir = app_joint_exqdesn_phase149_default_dir()
) {
  controls <- app_read_csv(file.path(phase121_dir, "case_winner_controls.csv"))
  supplemental <- app_read_csv(file.path(phase124b_dir, "case_winner_controls.csv"))
  supplemental <- supplemental[!supplemental$case_id %in% controls$case_id, names(controls), drop = FALSE]
  controls <- rbind(controls, supplemental)
  scenarios <- sort(unique(controls$scenario_ids))
  phase134_best <- app_joint_exqdesn_phase149_phase134_best(phase134_dir)
  rows <- list()
  for (scenario_id in scenarios) {
    exal <- controls[
      controls$scenario_ids == scenario_id & controls$model_ids == "joint_exqdesn_rhs_vb",
      , drop = FALSE
    ]
    al <- controls[
      controls$scenario_ids == scenario_id & controls$model_ids == "joint_qdesn_rhs_vb",
      , drop = FALSE
    ]
    if (nrow(exal) != 1L || nrow(al) != 1L) {
      stop(sprintf("Phase149 requires one Joint exQDESN and one Joint QDESN control row for '%s'.", scenario_id), call. = FALSE)
    }
    best <- phase134_best[phase134_best$scenario_id == scenario_id, , drop = FALSE]
    center <- if (nrow(best)) best[1L, , drop = FALSE] else exal
    specs <- app_joint_exqdesn_phase149_candidate_specs(center, exal, al)
    for (ii in seq_len(nrow(specs))) {
      role <- specs$phase149_role[[ii]]
      candidate_id <- paste(
        scenario_id, "joint_exqdesn_rhs_vb", "phase149", role,
        paste0("tau0_", app_joint_exqdesn_phase149_slug_num(specs$tau0[[ii]])),
        paste0("zeta2_", app_joint_exqdesn_phase149_slug_num(specs$zeta2[[ii]])),
        paste0("alpha_", app_joint_exqdesn_phase149_slug_num(specs$alpha_prior_sd[[ii]])),
        specs$gamma_init_policy[[ii]],
        sep = "__"
      )
      candidate_root <- file.path(
        screening_dir, "cases", paste0(scenario_id, "__joint_exqdesn_rhs_vb"),
        "candidates", role
      )
      rows[[length(rows) + 1L]] <- data.frame(
        candidate_id = candidate_id,
        candidate_label = sprintf("%s | Joint exQDESN RHS | %s", scenario_id, role),
        use_existing_artifacts = FALSE,
        fit_dir = file.path(candidate_root, "fit"),
        forecast_dir = file.path(candidate_root, "forecast"),
        vb_max_iter = specs$vb_max_iter[[ii]],
        adaptive_vb_max_iter_grid = paste(c(specs$vb_max_iter[[ii]], specs$vb_max_iter[[ii]] + 480L), collapse = ","),
        vb_tol = 1e-4,
        rhs_vb_inner = specs$rhs_vb_inner[[ii]],
        tau0 = specs$tau0[[ii]],
        zeta2 = specs$zeta2[[ii]],
        a_sigma = specs$a_sigma[[ii]],
        b_sigma = specs$b_sigma[[ii]],
        alpha_prior_sd = specs$alpha_prior_sd[[ii]],
        alpha_min_spacing = specs$alpha_min_spacing[[ii]],
        gamma_init_policy = specs$gamma_init_policy[[ii]],
        review_adjustment_threshold = 1e-3,
        max_dense_dim = specs$max_dense_dim[[ii]],
        n_cores = 1L,
        candidate_role = "phase149_case_specific_joint_exal",
        notes = specs$notes[[ii]],
        scenario_ids = scenario_id,
        model_ids = "joint_exqdesn_rhs_vb",
        case_id = paste0(scenario_id, "__joint_exqdesn_rhs_vb"),
        phase149_role = role,
        phase149_center_source = if (nrow(best)) "phase134_case_best" else "phase121_case_winner",
        phase149_no_global_specification = TRUE,
        stringsAsFactors = FALSE
      )
    }
  }
  registry <- do.call(rbind, rows)
  app_joint_qdesn_validate_screening_registry(registry)
  if (anyDuplicated(registry$candidate_id)) stop("Phase149 candidate ids are not unique.", call. = FALSE)
  registry
}

app_joint_exqdesn_run_phase149_readiness <- function(
  out_dir = app_joint_exqdesn_phase149_default_readiness_dir(),
  screening_dir = app_joint_exqdesn_phase149_default_dir(),
  phase121_dir = app_joint_exqdesn_phase149_default_phase121_dir(),
  phase124b_dir = app_joint_exqdesn_phase149_default_phase124b_dir(),
  phase134_dir = app_joint_exqdesn_phase149_default_phase134_dir(),
  phase148_dir = app_joint_exqdesn_phase149_default_phase148_dir()
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  source_verification <- do.call(rbind, list(
    app_joint_exqdesn_phase149_manifest_verification(phase121_dir, "phase121"),
    app_joint_exqdesn_phase149_manifest_verification(phase124b_dir, "phase124b"),
    app_joint_exqdesn_phase149_manifest_verification(phase134_dir, "phase134"),
    app_joint_exqdesn_phase149_manifest_verification(phase148_dir, "phase148")
  ))
  source_fail <- any(!source_verification$hash_verified)
  phase148_assessment <- app_read_csv(file.path(phase148_dir, "target_invariance_assessment.csv"))
  target_fail <- any(phase148_assessment$gate_status == "fail")
  registry <- app_joint_exqdesn_phase149_build_registry(
    phase121_dir = phase121_dir,
    phase124b_dir = phase124b_dir,
    phase134_dir = phase134_dir,
    screening_dir = screening_dir
  )
  scenario_plan <- aggregate(candidate_id ~ scenario_ids, registry, length)
  names(scenario_plan) <- c("scenario_id", "n_candidates")
  scenario_plan$model_id <- "joint_exqdesn_rhs_vb"
  scenario_plan$selection_scope <- "scenario_specific"
  assessment <- data.frame(
    readiness_id = "phase149_case_specific_joint_exal",
    gate_status = if (source_fail || target_fail) "fail" else "pass",
    n_scenarios = length(unique(registry$scenario_ids)),
    n_candidates = nrow(registry),
    candidates_per_scenario_min = min(scenario_plan$n_candidates),
    candidates_per_scenario_max = max(scenario_plan$n_candidates),
    source_hash_failures = sum(!source_verification$hash_verified),
    target_invariance_status = phase148_assessment$gate_status[[1L]],
    global_specification_selected = FALSE,
    design_matrix_policy = "frozen_formal_fixture_design",
    recommendation = if (source_fail || target_fail) {
      "block_launch_and_fix_readiness_gate"
    } else {
      "launch_parallel_case_specific_joint_exal_vb_screen"
    },
    stringsAsFactors = FALSE
  )
  run_config <- data.frame(
    screening_dir = app_prefer_repo_relative_path(screening_dir),
    phase121_dir = app_prefer_repo_relative_path(phase121_dir),
    phase124b_dir = app_prefer_repo_relative_path(phase124b_dir),
    phase134_dir = app_prefer_repo_relative_path(phase134_dir),
    phase148_dir = app_prefer_repo_relative_path(phase148_dir),
    fixture_dir = app_prefer_repo_relative_path(app_joint_exqdesn_phase136_default_fixture_dir()),
    candidate_count = nrow(registry),
    scenario_count = length(unique(registry$scenario_ids)),
    candidates_per_scenario = paste(sort(unique(scenario_plan$n_candidates)), collapse = ","),
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase149 case-specific screening readiness",
    "",
    "Phase149 prepares independent Joint exQDESN VB/VB-LD candidate sets for all eight formal synthetic scenarios.",
    "There is no global specification and no AL relaunch.",
    "The formal fixture design matrix is frozen; this stage screens the exAL readout, RHS, fan, initialization, and VB controls exposed by the validated pipeline.",
    "",
    sprintf("- Gate: `%s`", assessment$gate_status[[1L]]),
    sprintf("- Scenarios: %d", assessment$n_scenarios[[1L]]),
    sprintf("- Candidates: %d", assessment$n_candidates[[1L]])
  ), readme_path, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "phase149_run_config.csv")),
    source_manifest_verification = app_joint_qvp_write_csv(source_verification, file.path(out_dir, "source_manifest_verification.csv")),
    target_invariance_assessment = app_joint_qvp_write_csv(phase148_assessment, file.path(out_dir, "target_invariance_assessment.csv")),
    screening_registry = app_joint_qvp_write_csv(registry, file.path(out_dir, "phase149_case_specific_screening_registry.csv")),
    scenario_screening_plan = app_joint_qvp_write_csv(scenario_plan, file.path(out_dir, "scenario_screening_plan.csv")),
    readiness_assessment = app_joint_qvp_write_csv(assessment, file.path(out_dir, "phase149_readiness_assessment.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    registry = registry,
    assessment = assessment,
    paths = c(paths, artifact_manifest = manifest_path)
  )
}

app_joint_exqdesn_phase149_rank_candidates <- function(
  forecast_scenario,
  fit_scenario,
  forecast_model,
  practical_abs_tolerance = 0.002,
  practical_rel_tolerance = 0.02
) {
  f <- forecast_scenario
  names(f)[names(f) == "truth_mae"] <- "forecast_truth_mae"
  names(f)[names(f) == "truth_rmse"] <- "forecast_truth_rmse"
  names(f)[names(f) == "check_loss_mean"] <- "forecast_check_loss_mean"
  fit <- fit_scenario
  names(fit)[names(fit) == "truth_mae"] <- "fit_truth_mae"
  names(fit)[names(fit) == "truth_rmse"] <- "fit_truth_rmse"
  names(fit)[names(fit) == "check_loss_mean"] <- "fit_check_loss_mean"
  fit_keep <- intersect(
    c("candidate_id", "scenario_id", "fit_truth_mae", "fit_truth_rmse", "fit_check_loss_mean"),
    names(fit)
  )
  out <- merge(f, fit[, fit_keep, drop = FALSE], by = c("candidate_id", "scenario_id"), all.x = TRUE)
  model_keep <- intersect(
    c("candidate_id", "crps_grid_mean", "abs_hit_rate_error", "abs_coverage_error", "elapsed_seconds"),
    names(forecast_model)
  )
  model <- forecast_model[, model_keep, drop = FALSE]
  model <- model[!duplicated(model$candidate_id), , drop = FALSE]
  out <- merge(out, model, by = "candidate_id", all.x = TRUE)
  out$hard_fail <- out$gate_status == "fail" |
    !is.finite(out$forecast_truth_mae) |
    !is.finite(out$forecast_check_loss_mean) |
    out$contract_crossing_pairs > 0
  out$stability_penalty <- as.integer(out$reached_max_iter) +
    as.integer(out$raw_crossing_pairs > 0) +
    as.integer(out$max_abs_adjustment > 1e-3)
  rows <- lapply(split(out, out$scenario_id), function(block) {
    valid <- block[!block$hard_fail, , drop = FALSE]
    if (!nrow(valid)) {
      block$best_forecast_truth_mae <- NA_real_
      block$practical_tolerance <- NA_real_
      block$within_practical_tolerance <- FALSE
      block$phase149_rank <- seq_len(nrow(block))
      return(block)
    }
    best <- min(valid$forecast_truth_mae)
    tolerance <- max(practical_abs_tolerance, practical_rel_tolerance * best)
    block$best_forecast_truth_mae <- best
    block$practical_tolerance <- tolerance
    block$within_practical_tolerance <- !block$hard_fail &
      block$forecast_truth_mae <= best + tolerance
    ord <- order(
      block$hard_fail,
      !block$within_practical_tolerance,
      block$stability_penalty,
      block$forecast_truth_mae,
      block$forecast_check_loss_mean,
      block$candidate_id
    )
    block <- block[ord, , drop = FALSE]
    block$phase149_rank <- seq_len(nrow(block))
    block
  })
  do.call(rbind, rows)
}

app_joint_exqdesn_phase149_shortlist <- function(ranking, max_per_scenario = 3L) {
  rows <- lapply(split(ranking, ranking$scenario_id), function(block) {
    eligible <- block[!block$hard_fail & block$within_practical_tolerance, , drop = FALSE]
    if (!nrow(eligible)) return(block[FALSE, , drop = FALSE])
    stable <- eligible[order(
      eligible$stability_penalty,
      eligible$forecast_truth_mae,
      eligible$forecast_check_loss_mean
    ), , drop = FALSE]
    metric <- eligible[order(
      eligible$forecast_truth_mae,
      eligible$forecast_check_loss_mean,
      eligible$stability_penalty
    ), , drop = FALSE]
    selected_ids <- unique(c(stable$candidate_id[[1L]], metric$candidate_id[[1L]]))
    remaining <- stable[!stable$candidate_id %in% selected_ids, , drop = FALSE]
    if (length(selected_ids) < max_per_scenario && nrow(remaining)) {
      selected_ids <- c(selected_ids, remaining$candidate_id[[1L]])
    }
    selected_ids <- head(selected_ids, as.integer(max_per_scenario))
    out <- block[match(selected_ids, block$candidate_id), , drop = FALSE]
    out$shortlist_order <- seq_len(nrow(out))
    out$shortlist_role <- ifelse(
      out$candidate_id == stable$candidate_id[[1L]],
      "stability_primary",
      ifelse(out$candidate_id == metric$candidate_id[[1L]], "metric_primary", "within_tolerance_alternative")
    )
    out
  })
  do.call(rbind, rows)
}

app_joint_exqdesn_run_phase149_result_audit <- function(
  screening_dir = app_joint_exqdesn_phase149_default_dir(),
  readiness_dir = app_joint_exqdesn_phase149_default_readiness_dir(),
  out_dir = file.path(screening_dir, "phase149_result_audit")
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  registry <- app_read_csv(file.path(readiness_dir, "phase149_case_specific_screening_registry.csv"))
  forecast_scenario <- app_read_csv(file.path(screening_dir, "forecast_scenario_metric_summary.csv"))
  fit_scenario <- app_read_csv(file.path(screening_dir, "fit_scenario_metric_summary.csv"))
  forecast_model <- app_read_csv(file.path(screening_dir, "forecast_model_metric_summary.csv"))
  health <- app_read_csv(file.path(screening_dir, "screening_health_summary.csv"))
  ranking <- app_joint_exqdesn_phase149_rank_candidates(
    forecast_scenario, fit_scenario, forecast_model
  )
  ranking <- merge(
    ranking,
    registry[, c("candidate_id", "phase149_role", "phase149_center_source", "phase149_no_global_specification"), drop = FALSE],
    by = "candidate_id",
    all.x = TRUE,
    sort = FALSE
  )
  shortlist <- app_joint_exqdesn_phase149_shortlist(ranking)
  scenario_summary <- do.call(rbind, lapply(split(ranking, ranking$scenario_id), function(block) {
    short <- shortlist[shortlist$scenario_id == block$scenario_id[[1L]], , drop = FALSE]
    data.frame(
      scenario_id = block$scenario_id[[1L]],
      candidates = nrow(block),
      hard_fail_candidates = sum(block$hard_fail),
      within_tolerance_candidates = sum(block$within_practical_tolerance),
      shortlisted_candidates = nrow(short),
      best_forecast_truth_mae = suppressWarnings(min(block$forecast_truth_mae[!block$hard_fail], na.rm = TRUE)),
      selected_candidate_id = if (nrow(short)) short$candidate_id[[1L]] else NA_character_,
      selected_forecast_truth_mae = if (nrow(short)) short$forecast_truth_mae[[1L]] else NA_real_,
      stringsAsFactors = FALSE
    )
  }))
  scenario_summary$best_forecast_truth_mae[!is.finite(scenario_summary$best_forecast_truth_mae)] <- NA_real_
  health_fail <- any(health$gate_status == "fail") ||
    any(health$manifest_status == "fail") ||
    any(health$scenario_worker_failures > 0)
  coverage_fail <- nrow(ranking) != nrow(registry) ||
    length(unique(ranking$scenario_id)) != length(unique(registry$scenario_ids))
  shortlist_fail <- any(scenario_summary$shortlisted_candidates == 0L)
  assessment <- data.frame(
    audit_id = "phase149_case_specific_result_audit",
    gate_status = if (health_fail || coverage_fail || shortlist_fail) "fail" else "pass",
    expected_candidates = nrow(registry),
    observed_candidates = nrow(ranking),
    scenarios = nrow(scenario_summary),
    hard_fail_candidates = sum(ranking$hard_fail),
    shortlisted_candidates = nrow(shortlist),
    global_specification_selected = FALSE,
    recommendation = if (health_fail || coverage_fail || shortlist_fail) {
      "fix_phase149_result_integrity_before_mcmc"
    } else {
      "review_case_specific_shortlists_then_launch_eight_chain_mcmc_confirmation"
    },
    stringsAsFactors = FALSE
  )
  mcmc_plan <- shortlist[, intersect(c(
    "scenario_id", "candidate_id", "shortlist_order", "shortlist_role",
    "forecast_truth_mae", "fit_truth_mae", "gate_status", "raw_crossing_pairs",
    "contract_crossing_pairs", "phase149_role"
  ), names(shortlist)), drop = FALSE]
  mcmc_plan$n_chains <- 8L
  mcmc_plan$initialization <- "candidate_specific_vb_vbld"
  mcmc_plan$sampler <- "verified_conditional_refresh"
  mcmc_plan$launch_status <- "requires_user_review"
  readme_path <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase149 result audit",
    "",
    "Candidates are ranked and shortlisted within scenario. No global specification is selected.",
    sprintf("- Gate: `%s`", assessment$gate_status[[1L]]),
    sprintf("- Observed candidates: %d/%d", assessment$observed_candidates[[1L]], assessment$expected_candidates[[1L]]),
    sprintf("- Shortlisted candidates: %d", assessment$shortlisted_candidates[[1L]]),
    "",
    "MCMC is not launched automatically. The shortlist must be reviewed before eight-chain confirmation."
  ), readme_path, useBytes = TRUE)
  paths <- c(
    candidate_ranking = app_joint_qvp_write_csv(ranking, file.path(out_dir, "phase149_candidate_ranking.csv")),
    case_specific_shortlist = app_joint_qvp_write_csv(shortlist, file.path(out_dir, "phase149_case_specific_shortlist.csv")),
    scenario_summary = app_joint_qvp_write_csv(scenario_summary, file.path(out_dir, "phase149_scenario_summary.csv")),
    mcmc_confirmation_plan = app_joint_qvp_write_csv(mcmc_plan, file.path(out_dir, "phase149_mcmc_confirmation_plan.csv")),
    result_assessment = app_joint_qvp_write_csv(assessment, file.path(out_dir, "phase149_result_assessment.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(out_dir = out_dir, assessment = assessment, shortlist = shortlist, paths = c(paths, artifact_manifest = manifest_path))
}
