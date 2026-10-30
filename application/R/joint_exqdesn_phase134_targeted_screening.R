# Phase134 targeted Joint exQDESN exAL specification/sampler screening.

app_joint_exqdesn_phase134_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase134_exal_targeted_screening_readiness_20260715")
}

app_joint_exqdesn_phase134_default_screening_dir <- function() {
  app_path("application/cache/joint_qdesn_phase134_exal_targeted_screening_20260715")
}

app_joint_exqdesn_phase134_default_phase133b_dir <- function() {
  app_path("application/cache/joint_qdesn_phase133b_qhat_summary_sensitivity_20260714")
}

app_joint_exqdesn_phase134_required_phase133b_files <- function() {
  c(
    "audit_assessment.csv",
    "qhat_summary_method_recommendation.csv",
    "posterior_qhat_summary_method_metrics.csv",
    "forecast_truth_distance_summary.csv",
    "forecast_hit_rate_summary.csv",
    "forecast_interval_summary.csv",
    "posterior_qhat_summary_forecast_uncertainty.csv",
    "source_manifest_verification.csv",
    "artifact_manifest.csv"
  )
}

app_joint_exqdesn_phase134_load_phase133b <- function(phase133b_dir) {
  phase133b_dir <- normalizePath(phase133b_dir, mustWork = TRUE)
  missing <- app_joint_exqdesn_phase134_required_phase133b_files()[
    !file.exists(file.path(phase133b_dir, app_joint_exqdesn_phase134_required_phase133b_files()))
  ]
  if (length(missing)) {
    stop(sprintf("Phase133B artifact is missing required files: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  manifest <- app_joint_qdesn_phase108_manifest_verify(phase133b_dir, "phase133b_qhat_summary_sensitivity")
  if (any(manifest$status != "pass")) {
    stop("Phase133B artifact manifest verification failed.", call. = FALSE)
  }
  list(
    dir = phase133b_dir,
    manifest = manifest,
    assessment = app_read_csv(file.path(phase133b_dir, "audit_assessment.csv")),
    recommendations = app_read_csv(file.path(phase133b_dir, "qhat_summary_method_recommendation.csv")),
    method_metrics = app_read_csv(file.path(phase133b_dir, "posterior_qhat_summary_method_metrics.csv")),
    forecast_truth = app_read_csv(file.path(phase133b_dir, "forecast_truth_distance_summary.csv")),
    hit_rate = app_read_csv(file.path(phase133b_dir, "forecast_hit_rate_summary.csv")),
    interval = app_read_csv(file.path(phase133b_dir, "forecast_interval_summary.csv")),
    uncertainty = app_read_csv(file.path(phase133b_dir, "posterior_qhat_summary_forecast_uncertainty.csv")),
    source_manifest = app_read_csv(file.path(phase133b_dir, "source_manifest_verification.csv"))
  )
}

app_joint_exqdesn_phase134_scenario_audit <- function(phase133b) {
  rec <- phase133b$recommendations
  met <- phase133b$method_metrics
  truth <- phase133b$forecast_truth
  hit <- phase133b$hit_rate
  interval <- phase133b$interval
  uncertainty <- phase133b$uncertainty
  spread <- app_joint_qdesn_bind_rows(lapply(split(met, met$scenario_id), function(block) {
    data.frame(
      scenario_id = block$scenario_id[[1L]],
      qhat_summary_mae_spread = max(block$forecast_truth_mae, na.rm = TRUE) -
        min(block$forecast_truth_mae, na.rm = TRUE),
      qhat_summary_best_method = block$qhat_summary_method[which.min(block$forecast_truth_mae)],
      stringsAsFactors = FALSE
    )
  }))
  tail_bias <- app_joint_qdesn_bind_rows(lapply(split(truth, truth$scenario_id), function(block) {
    mean_block <- block[block$qhat_summary_method == "mean", , drop = FALSE]
    lo <- mean_block[mean_block$tau %in% c(0.05, 0.10), , drop = FALSE]
    hi <- mean_block[mean_block$tau %in% c(0.90, 0.95), , drop = FALSE]
    data.frame(
      scenario_id = block$scenario_id[[1L]],
      lower_tail_mean_bias = mean(lo$truth_bias, na.rm = TRUE),
      upper_tail_mean_bias = mean(hi$truth_bias, na.rm = TRUE),
      lower_tail_mae = mean(lo$truth_mae, na.rm = TRUE),
      upper_tail_mae = mean(hi$truth_mae, na.rm = TRUE),
      tail_compression_signature = isTRUE(mean(lo$truth_bias, na.rm = TRUE) > 0) &&
        isTRUE(mean(hi$truth_bias, na.rm = TRUE) < 0),
      stringsAsFactors = FALSE
    )
  }))
  hit_agg <- app_joint_qdesn_bind_rows(lapply(split(hit[hit$qhat_summary_method == "mean", , drop = FALSE], hit$scenario_id[hit$qhat_summary_method == "mean"]), function(block) {
    data.frame(
      scenario_id = block$scenario_id[[1L]],
      mean_abs_hit_rate_error = mean(block$abs_hit_rate_error, na.rm = TRUE),
      max_abs_hit_rate_error = max(block$abs_hit_rate_error, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))
  interval_agg <- app_joint_qdesn_bind_rows(lapply(split(interval[interval$qhat_summary_method == "mean", , drop = FALSE], interval$scenario_id[interval$qhat_summary_method == "mean"]), function(block) {
    data.frame(
      scenario_id = block$scenario_id[[1L]],
      mean_abs_coverage_error = mean(block$abs_coverage_error, na.rm = TRUE),
      mean_interval_width = mean(block$interval_width_mean, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))
  uncertainty_agg <- app_joint_qdesn_bind_rows(lapply(split(uncertainty, uncertainty$scenario_id), function(block) {
    data.frame(
      scenario_id = block$scenario_id[[1L]],
      mean_qhat_iqr90_width = mean(block$qhat_iqr90_width, na.rm = TRUE),
      max_qhat_iqr90_width = max(block$qhat_iqr90_width, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))
  out <- Reduce(function(x, y) merge(x, y, by = "scenario_id", all.x = TRUE), list(rec, spread, tail_bias, hit_agg, interval_agg, uncertainty_agg))
  out$phase134_primary_diagnosis <- ifelse(
    out$recommended_next_action == "pair_exal_spec_screen_with_sampler_geometry",
    "specification_plus_sampler_geometry",
    ifelse(
      out$qhat_summary_mae_spread < 0.005 & out$tail_compression_signature,
      "specification_tail_compression",
      "specification_calibration"
    )
  )
  out$phase134_priority <- ifelse(
    out$best_method_gap_to_current_winner >= 0.045,
    "highest",
    ifelse(out$best_method_gap_to_current_winner >= 0.030, "high", "targeted")
  )
  out[order(match(out$phase134_priority, c("highest", "high", "targeted")), -out$best_method_gap_to_current_winner), , drop = FALSE]
}

app_joint_exqdesn_phase134_candidate_grid <- function(scenario_id, diagnosis, priority) {
  base <- data.frame(
    suffix = "phase121_selected_controls",
    candidate_label = "Phase121 selected controls rerun",
    vb_max_iter = 1440L,
    adaptive_vb_max_iter_grid = "1440,1920",
    vb_tol = 1.0e-4,
    rhs_vb_inner = 10L,
    tau0 = NA_real_,
    zeta2 = NA_real_,
    a_sigma = 2,
    b_sigma = 1,
    alpha_prior_sd = NA_character_,
    alpha_min_spacing = 0,
    gamma_init_policy = NA_character_,
    review_adjustment_threshold = 1.0e-3,
    max_dense_dim = 300L,
    candidate_role = "phase134_phase121_reference",
    notes = "Reruns the Phase121 selected controls as an internal reference for the targeted screen.",
    stringsAsFactors = FALSE
  )
  fan <- data.frame(
    suffix = c(
      "fan_tau0_0p50_alpha1p00_zeta2_32_gamma_zero",
      "fan_tau0_0p75_alpha1p00_zeta2_32_gamma_zero",
      "fan_tau0_0p75_alpha1p25_zeta2_32_gamma_zero",
      "fan_tau0_1p00_alpha1p25_zeta2_64_gamma_zero",
      "fan_tau0_0p50_alpha1p50_zeta2_64_gamma_zero",
      "fan_tau0_0p75_alpha1p50_zeta2_64_gamma_quarter",
      "fan_tau0_0p75_alpha1p25_zeta2_32_gamma_half",
      "fan_tau0_1p00_alpha1p00_zeta2_32_gamma_default",
      "fan_tau0_0p35_alpha1p00_zeta2_32_gamma_zero",
      "fan_tau0_0p25_alpha1p00_zeta2_64_gamma_zero"
    ),
    candidate_label = c(
      "Moderate fan widening: tau0 0.50, alpha 1.00, zeta2 32, zero gamma",
      "Looser RHS with moderate fan: tau0 0.75, alpha 1.00, zeta2 32",
      "Looser RHS and wider fan: tau0 0.75, alpha 1.25, zeta2 32",
      "Aggressive fan widening: tau0 1.00, alpha 1.25, zeta2 64",
      "Wide alpha and weak beta cap: tau0 0.50, alpha 1.50, zeta2 64",
      "Wide fan with quarter-default gamma initialization",
      "Wide fan with half-default gamma initialization",
      "Default gamma initialization under looser RHS",
      "Stronger RHS coupling with wider fan",
      "Strong RHS coupling with weak beta cap"
    ),
    vb_max_iter = rep(1920L, 10L),
    adaptive_vb_max_iter_grid = rep("1920,2400", 10L),
    vb_tol = rep(1.0e-4, 10L),
    rhs_vb_inner = rep(12L, 10L),
    tau0 = c(0.50, 0.75, 0.75, 1.00, 0.50, 0.75, 0.75, 1.00, 0.35, 0.25),
    zeta2 = c(32, 32, 32, 64, 64, 64, 32, 32, 32, 64),
    a_sigma = rep(2, 10L),
    b_sigma = rep(1, 10L),
    alpha_prior_sd = c("1.00", "1.00", "1.25", "1.25", "1.50", "1.50", "1.25", "1.00", "1.00", "1.00"),
    alpha_min_spacing = rep(0, 10L),
    gamma_init_policy = c("zero", "zero", "zero", "zero", "zero", "quarter_default", "half_default", "default", "zero", "zero"),
    review_adjustment_threshold = rep(1.0e-3, 10L),
    max_dense_dim = rep(300L, 10L),
    candidate_role = rep("phase134_exal_fan_specification_candidate", 10L),
    notes = rep("Tests whether Joint exQDESN exAL-RHS is tail-compressed because the fan/readout prior is too tight.", 10L),
    stringsAsFactors = FALSE
  )
  optimizer <- data.frame(
    suffix = c(
      "geom_inner14_iter2400_tau0_0p75_alpha1p25_zeta2_64_gamma_zero",
      "geom_inner16_iter2880_tau0_0p75_alpha1p25_zeta2_64_gamma_zero",
      "geom_inner16_iter2880_tau0_0p50_alpha1p50_zeta2_64_gamma_half",
      "geom_inner18_iter3360_tau0_0p75_alpha1p50_zeta2_64_gamma_quarter",
      "geom_tol5e5_inner16_iter2880_tau0_0p75_alpha1p25_zeta2_64_gamma_zero",
      "geom_inner16_iter2880_tau0_0p35_alpha1p25_zeta2_64_gamma_zero"
    ),
    candidate_label = c(
      "Geometry continuation: inner 14, VB 2400, wide fan",
      "Geometry continuation: inner 16, VB 2880, wide fan",
      "Geometry plus half-gamma: inner 16, VB 2880, alpha 1.50",
      "Aggressive geometry plus quarter-gamma: inner 18, VB 3360",
      "Tighter tolerance geometry continuation",
      "Stronger RHS coupling with high geometry budget"
    ),
    vb_max_iter = c(2400L, 2880L, 2880L, 3360L, 2880L, 2880L),
    adaptive_vb_max_iter_grid = c("2400,2880", "2880,3360", "2880,3360", "3360,3840", "2880,3360", "2880,3360"),
    vb_tol = c(1.0e-4, 1.0e-4, 1.0e-4, 1.0e-4, 5.0e-5, 1.0e-4),
    rhs_vb_inner = c(14L, 16L, 16L, 18L, 16L, 16L),
    tau0 = c(0.75, 0.75, 0.50, 0.75, 0.75, 0.35),
    zeta2 = rep(64, 6L),
    a_sigma = rep(2, 6L),
    b_sigma = rep(1, 6L),
    alpha_prior_sd = c("1.25", "1.25", "1.50", "1.50", "1.25", "1.25"),
    alpha_min_spacing = rep(0, 6L),
    gamma_init_policy = c("zero", "zero", "half_default", "quarter_default", "zero", "zero"),
    review_adjustment_threshold = rep(1.0e-3, 6L),
    max_dense_dim = rep(300L, 6L),
    candidate_role = rep("phase134_exal_sampler_geometry_candidate", 6L),
    notes = rep("Pairs exAL fan calibration with stronger VB coordinate/iteration geometry.", 6L),
    stringsAsFactors = FALSE
  )
  rows <- app_joint_qdesn_bind_rows(list(base, fan))
  if (identical(diagnosis, "specification_plus_sampler_geometry") || identical(priority, "highest")) {
    rows <- app_joint_qdesn_bind_rows(list(rows, optimizer))
  } else if (identical(priority, "high")) {
    rows <- app_joint_qdesn_bind_rows(list(rows, optimizer[seq_len(3L), , drop = FALSE]))
  }
  rows
}

app_joint_exqdesn_phase134_registry <- function(
  scenario_audit,
  phase121_controls,
  screening_output_dir = app_joint_exqdesn_phase134_default_screening_dir(),
  n_cores = 1L
) {
  screening_output_dir <- normalizePath(screening_output_dir, mustWork = FALSE)
  rows <- list()
  phase121_controls <- phase121_controls[phase121_controls$model_ids == "joint_exqdesn_rhs_vb", , drop = FALSE]
  for (ii in seq_len(nrow(scenario_audit))) {
    sc <- scenario_audit[ii, , drop = FALSE]
    source <- phase121_controls[phase121_controls$scenario_ids == sc$scenario_id[[1L]], , drop = FALSE]
    if (nrow(source) != 1L) stop(sprintf("Expected one Phase121 Joint exQDESN control row for '%s'.", sc$scenario_id[[1L]]), call. = FALSE)
    grid <- app_joint_exqdesn_phase134_candidate_grid(sc$scenario_id[[1L]], sc$phase134_primary_diagnosis[[1L]], sc$phase134_priority[[1L]])
    grid$tau0[is.na(grid$tau0)] <- as.numeric(source$tau0[[1L]])
    grid$zeta2[is.na(grid$zeta2)] <- as.numeric(source$zeta2[[1L]])
    grid$alpha_prior_sd[is.na(grid$alpha_prior_sd)] <- as.character(source$alpha_prior_sd[[1L]])
    grid$gamma_init_policy[is.na(grid$gamma_init_policy)] <- as.character(source$gamma_init_policy[[1L]])
    case_slug <- paste(sc$scenario_id[[1L]], "joint_exqdesn_rhs_vb", sep = "__")
    case_slug <- gsub("[^A-Za-z0-9_]+", "_", case_slug)
    for (jj in seq_len(nrow(grid))) {
      g <- grid[jj, , drop = FALSE]
      candidate_id <- paste(case_slug, "phase134", g$suffix[[1L]], sep = "__")
      rows[[length(rows) + 1L]] <- data.frame(
        candidate_id = candidate_id,
        candidate_label = paste(sc$scenario_id[[1L]], "Joint exQDESN RHS", g$candidate_label[[1L]], sep = " | "),
        use_existing_artifacts = FALSE,
        fit_dir = file.path(screening_output_dir, "cases", case_slug, "candidates", g$suffix[[1L]], "fit"),
        forecast_dir = file.path(screening_output_dir, "cases", case_slug, "candidates", g$suffix[[1L]], "forecast"),
        vb_max_iter = as.integer(g$vb_max_iter[[1L]]),
        adaptive_vb_max_iter_grid = g$adaptive_vb_max_iter_grid[[1L]],
        vb_tol = as.numeric(g$vb_tol[[1L]]),
        rhs_vb_inner = as.integer(g$rhs_vb_inner[[1L]]),
        tau0 = as.numeric(g$tau0[[1L]]),
        zeta2 = as.numeric(g$zeta2[[1L]]),
        a_sigma = as.numeric(g$a_sigma[[1L]]),
        b_sigma = as.numeric(g$b_sigma[[1L]]),
        alpha_prior_sd = as.character(g$alpha_prior_sd[[1L]]),
        alpha_min_spacing = as.numeric(g$alpha_min_spacing[[1L]]),
        gamma_init_policy = as.character(g$gamma_init_policy[[1L]]),
        review_adjustment_threshold = as.numeric(g$review_adjustment_threshold[[1L]]),
        max_dense_dim = as.integer(g$max_dense_dim[[1L]]),
        n_cores = as.integer(n_cores),
        candidate_role = g$candidate_role[[1L]],
        notes = g$notes[[1L]],
        scenario_ids = sc$scenario_id[[1L]],
        model_ids = "joint_exqdesn_rhs_vb",
        case_id = case_slug,
        phase134_priority = sc$phase134_priority[[1L]],
        phase134_primary_diagnosis = sc$phase134_primary_diagnosis[[1L]],
        phase133b_best_method = sc$best_qhat_summary_method[[1L]],
        phase133b_best_forecast_mae = sc$best_forecast_mae[[1L]],
        phase133b_gap_to_current_winner = sc$best_method_gap_to_current_winner[[1L]],
        phase121_source_candidate_id = source$candidate_id[[1L]],
        stringsAsFactors = FALSE
      )
    }
  }
  registry <- app_joint_qdesn_bind_rows(rows)
  app_joint_qdesn_validate_screening_registry(registry, allow_alpha_prior_vectors = FALSE)
  registry
}

app_joint_exqdesn_phase134_design_summary <- function(registry) {
  by_case <- aggregate(candidate_id ~ scenario_ids + phase134_priority + phase134_primary_diagnosis, registry, length)
  names(by_case)[names(by_case) == "candidate_id"] <- "n_candidates"
  by_role <- aggregate(candidate_id ~ candidate_role, registry, length)
  names(by_role)[names(by_role) == "candidate_id"] <- "n_candidates"
  list(by_case = by_case, by_role = by_role)
}

app_joint_exqdesn_phase134_assessment <- function(phase133b, scenario_audit, registry) {
  source_ok <- all(phase133b$manifest$status == "pass") && all(phase133b$source_manifest$status == "pass")
  hard_fail <- !source_ok || !nrow(registry)
  data.frame(
    audit_gate = if (hard_fail) "fail" else "pass",
    implementation_gate = if (hard_fail) "fail" else "pass",
    n_target_scenarios = length(unique(registry$scenario_ids)),
    n_candidate_rows = nrow(registry),
    n_highest_priority_scenarios = sum(scenario_audit$phase134_priority == "highest"),
    n_high_priority_scenarios = sum(scenario_audit$phase134_priority == "high"),
    n_targeted_priority_scenarios = sum(scenario_audit$phase134_priority == "targeted"),
    n_sampler_geometry_scenarios = sum(scenario_audit$phase134_primary_diagnosis == "specification_plus_sampler_geometry"),
    article_update_recommendation = "do_not_update_article_until_phase134_screen_and_mcmc_confirmation_pass",
    next_stage_recommendation = "launch_phase134_targeted_vb_screen_then_freeze_case_winners_for_mcmc",
    status_reason = if (hard_fail) {
      "Phase134 readiness failed source or registry gates."
    } else {
      "Phase134 targeted Joint exQDESN screen is ready to launch."
    },
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase134_launch_commands <- function(
  registry_path,
  screening_output_dir,
  fixture_dir,
  workers = 10L,
  n_cores_per_worker = 1L,
  run_id = "phase134_exal_targeted_20260715"
) {
  run_cmd <- sprintf(
    "bash application/scripts/123_launch_joint_qdesn_screening_parallel_chunks.sh --registry %s --canonical-output-dir %s --fixture-dir %s --workers %d --n-cores-per-worker %d --run-id %s --session-prefix joint_qdesn_phase134_exal",
    registry_path,
    screening_output_dir,
    fixture_dir,
    as.integer(workers),
    as.integer(n_cores_per_worker),
    run_id
  )
  audit_cmd <- sprintf(
    "Rscript application/scripts/106_run_joint_qdesn_vb_spec_screening.R --registry %s --output-dir %s --fixture-dir %s --n-cores %d --reuse-completed true --audit-only true",
    registry_path,
    screening_output_dir,
    fixture_dir,
    as.integer(n_cores_per_worker)
  )
  data.frame(
    command_id = c("launch_phase134_targeted_screen", "audit_phase134_targeted_screen"),
    command = c(run_cmd, audit_cmd),
    purpose = c(
      "Run the targeted Joint exQDESN exAL specification/sampler candidate rows with row-parallel workers.",
      "Build the canonical Phase134 audit after all worker chunks finish."
    ),
    run_condition = c(
      "Launch after the Phase134 readiness manifest passes.",
      "Run after every Phase134 worker session ends with EXIT_CODE=0."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase134_readme <- function(run_config, scenario_audit, design_summary, launch_commands) {
  c(
    "# Joint exQDESN Phase134 targeted exAL screening readiness",
    "",
    "Phase134 consumes the Phase133B posterior-qhat sensitivity result and prepares a targeted Joint exQDESN exAL-RHS screen.",
    "Phase133B showed that posterior mean/median/trimmed qhat summaries are nearly tied, so the remaining gap is treated primarily as specification calibration rather than summary instability.",
    "",
    sprintf("- Output directory: `%s`", run_config$out_dir[[1L]]),
    sprintf("- Screening output directory: `%s`", run_config$screening_output_dir[[1L]]),
    sprintf("- Target scenarios: %d", run_config$n_target_scenarios[[1L]]),
    sprintf("- Candidate rows: %d", run_config$n_candidate_rows[[1L]]),
    "",
    "Scenario priorities:",
    paste(sprintf("- `%s`: `%s`, diagnosis `%s`, gap %.4f", scenario_audit$scenario_id, scenario_audit$phase134_priority, scenario_audit$phase134_primary_diagnosis, scenario_audit$best_method_gap_to_current_winner), collapse = "\n"),
    "",
    "Candidate roles:",
    paste(sprintf("- `%s`: %d rows", design_summary$by_role$candidate_role, design_summary$by_role$n_candidates), collapse = "\n"),
    "",
    "Launch command:",
    "",
    launch_commands$command[launch_commands$command_id == "launch_phase134_targeted_screen"][[1L]],
    "",
    "Article policy:",
    "- Do not update manuscript tables from Phase134 directly.",
    "- Use Phase134 to choose improved VB/VB-LD case winners.",
    "- Promote only after balanced MCMC confirmation passes with manifests, finite scores, and zero contract crossings."
  )
}

app_joint_exqdesn_run_phase134_targeted_screening_readiness <- function(
  out_dir = app_joint_exqdesn_phase134_default_dir(),
  screening_output_dir = app_joint_exqdesn_phase134_default_screening_dir(),
  phase133b_dir = app_joint_exqdesn_phase134_default_phase133b_dir(),
  phase121_dir = app_joint_qdesn_default_phase121_case_vb_freeze_dir_fallback(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  workers = 10L,
  n_cores_per_worker = 1L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  screening_output_dir <- normalizePath(screening_output_dir, mustWork = FALSE)
  fixture_dir <- normalizePath(fixture_dir, mustWork = TRUE)
  app_ensure_dir(out_dir)
  phase133b <- app_joint_exqdesn_phase134_load_phase133b(phase133b_dir)
  phase121 <- app_joint_qdesn_phase122_load_phase121(phase121_dir)
  scenario_audit <- app_joint_exqdesn_phase134_scenario_audit(phase133b)
  registry <- app_joint_exqdesn_phase134_registry(
    scenario_audit,
    phase121$controls,
    screening_output_dir = screening_output_dir,
    n_cores = n_cores_per_worker
  )
  design_summary <- app_joint_exqdesn_phase134_design_summary(registry)
  registry_path <- file.path(out_dir, "phase134_targeted_exal_screening_registry.csv")
  launch_commands <- app_joint_exqdesn_phase134_launch_commands(
    registry_path = registry_path,
    screening_output_dir = screening_output_dir,
    fixture_dir = fixture_dir,
    workers = workers,
    n_cores_per_worker = n_cores_per_worker
  )
  assessment <- app_joint_exqdesn_phase134_assessment(phase133b, scenario_audit, registry)
  run_config <- data.frame(
    run_id = "joint_qdesn_phase134_exal_targeted_screening_readiness",
    out_dir = out_dir,
    screening_output_dir = screening_output_dir,
    phase133b_dir = phase133b$dir,
    phase121_dir = phase121$phase121_dir,
    fixture_dir = fixture_dir,
    workers = as.integer(workers),
    n_cores_per_worker = as.integer(n_cores_per_worker),
    n_target_scenarios = length(unique(registry$scenario_ids)),
    n_candidate_rows = nrow(registry),
    readiness_decision = if (assessment$audit_gate[[1L]] == "pass") "ready_to_launch_phase134_targeted_screen" else "blocked_before_launch",
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_exqdesn_phase134_readme(run_config, scenario_audit, design_summary, launch_commands), readme_path, useBytes = TRUE)
  paths <- c(
    phase134_run_config = app_joint_qdesn_screening_write_csv(run_config, file.path(out_dir, "phase134_run_config.csv")),
    phase133b_source_manifest_verification = app_joint_qdesn_screening_write_csv(phase133b$manifest, file.path(out_dir, "phase133b_source_manifest_verification.csv")),
    phase121_source_manifest_verification = app_joint_qdesn_screening_write_csv(phase121$manifest_verification, file.path(out_dir, "phase121_source_manifest_verification.csv")),
    phase133b_assessment = app_joint_qdesn_screening_write_csv(phase133b$assessment, file.path(out_dir, "phase133b_assessment.csv")),
    phase133b_recommendations = app_joint_qdesn_screening_write_csv(phase133b$recommendations, file.path(out_dir, "phase133b_recommendations.csv")),
    phase134_scenario_diagnosis = app_joint_qdesn_screening_write_csv(scenario_audit, file.path(out_dir, "phase134_scenario_diagnosis.csv")),
    phase134_candidate_design_by_case = app_joint_qdesn_screening_write_csv(design_summary$by_case, file.path(out_dir, "phase134_candidate_design_by_case.csv")),
    phase134_candidate_design_by_role = app_joint_qdesn_screening_write_csv(design_summary$by_role, file.path(out_dir, "phase134_candidate_design_by_role.csv")),
    phase134_targeted_exal_screening_registry = app_joint_qdesn_screening_write_csv(registry, registry_path),
    phase134_launch_commands = app_joint_qdesn_screening_write_csv(launch_commands, file.path(out_dir, "phase134_launch_commands.csv")),
    phase134_assessment = app_joint_qdesn_screening_write_csv(assessment, file.path(out_dir, "phase134_assessment.csv")),
    provenance = app_joint_qdesn_screening_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    screening_output_dir = screening_output_dir,
    run_config = run_config,
    phase133b = phase133b,
    phase121 = phase121,
    scenario_audit = scenario_audit,
    registry = registry,
    design_summary = design_summary,
    launch_commands = launch_commands,
    assessment = assessment,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path)
  )
}
