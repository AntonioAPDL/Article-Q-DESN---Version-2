# Phase135 matched-spec exAL readiness after Phase134 targeted screening.

app_joint_exqdesn_phase135_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase135_matched_exal_readiness_20260715")
}

app_joint_exqdesn_phase135_default_screening_dir <- function() {
  app_path("application/cache/joint_qdesn_phase135_matched_exal_screening_20260715")
}

app_joint_exqdesn_phase135_default_result_audit_dir <- function() {
  app_path("application/cache/joint_qdesn_phase135_matched_exal_screening_20260715/phase135_result_audit")
}

app_joint_exqdesn_phase135_default_phase134_dir <- function() {
  app_path("application/cache/joint_qdesn_phase134_exal_targeted_screening_20260715")
}

app_joint_exqdesn_phase135_default_phase124c_dir <- function() {
  app_path("application/cache/joint_qdesn_phase124c_mcmc_balanced_completion_20260711")
}

app_joint_exqdesn_phase135_default_phase125_dir <- function() {
  app_path("application/cache/joint_qdesn_phase125_balanced_mcmc_audit_20260712")
}

app_joint_exqdesn_phase135_required_phase134_files <- function() {
  c(
    "candidate_registry.csv",
    "candidate_scorecard.csv",
    "screening_health_summary.csv",
    "candidate_manifest_verification.csv",
    "selected_spec_recommendation.csv",
    "artifact_manifest.csv"
  )
}

app_joint_exqdesn_phase135_required_phase125_files <- function() {
  c(
    "combined_mcmc_case_summary.csv",
    "scenario_winner_summary.csv",
    "artifact_manifest.csv"
  )
}

app_joint_exqdesn_phase135_load_phase134 <- function(phase134_dir) {
  phase134_dir <- normalizePath(phase134_dir, mustWork = TRUE)
  missing <- app_joint_exqdesn_phase135_required_phase134_files()[
    !file.exists(file.path(phase134_dir, app_joint_exqdesn_phase135_required_phase134_files()))
  ]
  if (length(missing)) {
    stop(sprintf("Phase134 artifact is missing required files: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  manifest <- app_joint_qdesn_phase108_manifest_verify(phase134_dir, "phase134_targeted_exal_screening")
  if (any(manifest$status != "pass")) stop("Phase134 artifact manifest verification failed.", call. = FALSE)
  list(
    dir = phase134_dir,
    manifest = manifest,
    registry = app_read_csv(file.path(phase134_dir, "candidate_registry.csv")),
    scorecard = app_read_csv(file.path(phase134_dir, "candidate_scorecard.csv")),
    health = app_read_csv(file.path(phase134_dir, "screening_health_summary.csv")),
    candidate_manifest = app_read_csv(file.path(phase134_dir, "candidate_manifest_verification.csv")),
    selected = app_read_csv(file.path(phase134_dir, "selected_spec_recommendation.csv"))
  )
}

app_joint_exqdesn_phase135_load_phase125 <- function(phase125_dir) {
  phase125_dir <- normalizePath(phase125_dir, mustWork = TRUE)
  missing <- app_joint_exqdesn_phase135_required_phase125_files()[
    !file.exists(file.path(phase125_dir, app_joint_exqdesn_phase135_required_phase125_files()))
  ]
  if (length(missing)) {
    stop(sprintf("Phase125 artifact is missing required files: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  manifest <- app_joint_qdesn_phase108_manifest_verify(phase125_dir, "phase125_balanced_mcmc_audit")
  if (any(manifest$status != "pass")) stop("Phase125 artifact manifest verification failed.", call. = FALSE)
  list(
    dir = phase125_dir,
    manifest = manifest,
    combined_summary = app_read_csv(file.path(phase125_dir, "combined_mcmc_case_summary.csv")),
    scenario_winners = app_read_csv(file.path(phase125_dir, "scenario_winner_summary.csv"))
  )
}

app_joint_exqdesn_phase135_read_controls <- function(phase121_dir, phase124c_dir) {
  phase121_dir <- normalizePath(phase121_dir, mustWork = TRUE)
  phase124c_dir <- normalizePath(phase124c_dir, mustWork = TRUE)
  phase121_manifest <- app_joint_qdesn_phase108_manifest_verify(phase121_dir, "phase121_case_vb_winner_freeze")
  phase124c_manifest <- app_joint_qdesn_phase108_manifest_verify(phase124c_dir, "phase124c_mcmc_balanced_completion")
  if (any(phase121_manifest$status != "pass")) stop("Phase121 manifest verification failed.", call. = FALSE)
  if (any(phase124c_manifest$status != "pass")) stop("Phase124c manifest verification failed.", call. = FALSE)
  required <- "case_winner_controls.csv"
  if (!file.exists(file.path(phase121_dir, required))) stop("Phase121 controls file is missing.", call. = FALSE)
  if (!file.exists(file.path(phase124c_dir, required))) stop("Phase124c controls file is missing.", call. = FALSE)
  controls <- app_joint_qdesn_bind_rows(list(
    transform(app_read_csv(file.path(phase121_dir, required)), phase135_control_source = "phase121"),
    transform(app_read_csv(file.path(phase124c_dir, required)), phase135_control_source = "phase124c")
  ))
  controls <- controls[!duplicated(paste(controls$scenario_ids, controls$model_ids, sep = "||")), , drop = FALSE]
  list(
    phase121_dir = phase121_dir,
    phase124c_dir = phase124c_dir,
    phase121_manifest = phase121_manifest,
    phase124c_manifest = phase124c_manifest,
    controls = controls
  )
}

app_joint_exqdesn_phase135_current_mcmc_context <- function(phase125) {
  x <- phase125$combined_summary
  keep <- x[x$source_model_id %in% c(
    "joint_qdesn_rhs_vb",
    "qdesn_rhs_independent_vb",
    "joint_exqdesn_rhs_vb",
    "exqdesn_rhs_independent_vb"
  ), , drop = FALSE]
  rows <- lapply(split(keep, keep$scenario_id), function(block) {
    ord <- order(block$mcmc_forecast_truth_mae)
    best <- block[ord[1L], , drop = FALSE]
    joint_ex <- block[block$source_model_id == "joint_exqdesn_rhs_vb", , drop = FALSE]
    joint_al <- block[block$source_model_id == "joint_qdesn_rhs_vb", , drop = FALSE]
    indep_ex <- block[block$source_model_id == "exqdesn_rhs_independent_vb", , drop = FALSE]
    indep_al <- block[block$source_model_id == "qdesn_rhs_independent_vb", , drop = FALSE]
    data.frame(
      scenario_id = block$scenario_id[[1L]],
      n_article_models = nrow(block),
      feature_p = paste(sort(unique(block$p)), collapse = "|"),
      tau_grid_unique = length(unique(block$tau_grid)),
      current_mcmc_winner_model_id = best$source_model_id[[1L]],
      current_mcmc_winner_label = best$display_label[[1L]],
      current_mcmc_winner_forecast_mae = best$mcmc_forecast_truth_mae[[1L]],
      joint_qdesn_mcmc_forecast_mae = joint_al$mcmc_forecast_truth_mae[[1L]],
      joint_exqdesn_mcmc_forecast_mae = joint_ex$mcmc_forecast_truth_mae[[1L]],
      independent_qdesn_mcmc_forecast_mae = indep_al$mcmc_forecast_truth_mae[[1L]],
      independent_exqdesn_mcmc_forecast_mae = indep_ex$mcmc_forecast_truth_mae[[1L]],
      joint_exqdesn_gap_to_current_winner = joint_ex$mcmc_forecast_truth_mae[[1L]] - best$mcmc_forecast_truth_mae[[1L]],
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase135_phase134_winners <- function(phase134, phase125) {
  score <- phase134$scorecard
  registry <- phase134$registry
  health <- phase134$health
  m <- merge(
    score,
    registry[, c(
      "candidate_id", "scenario_ids", "candidate_role", "tau0", "zeta2",
      "alpha_prior_sd", "gamma_init_policy", "rhs_vb_inner", "vb_max_iter",
      "adaptive_vb_max_iter_grid", "phase121_source_candidate_id"
    ), drop = FALSE],
    by = "candidate_id",
    all.x = TRUE
  )
  m <- merge(
    m,
    health[, c(
      "candidate_id", "fit_raw_crossings", "forecast_raw_crossings",
      "contract_crossings", "fit_reached_max_iter", "forecast_reached_max_iter",
      "elapsed_seconds"
    ), drop = FALSE],
    by = "candidate_id",
    all.x = TRUE,
    suffixes = c("_score", "_health")
  )
  if ("forecast_raw_crossings_health" %in% names(m)) {
    m$forecast_raw_crossings <- m$forecast_raw_crossings_health
  }
  if (!"forecast_raw_crossings" %in% names(m)) {
    stop("Phase134 winner audit could not resolve forecast raw crossing diagnostics.", call. = FALSE)
  }
  winners <- app_joint_qdesn_bind_rows(lapply(split(m, m$scenario_ids), function(block) {
    block[order(block$screening_score, block$max_scenario_forecast_truth_mae), , drop = FALSE][1L, , drop = FALSE]
  }))
  refs <- app_joint_qdesn_bind_rows(lapply(split(m, m$scenario_ids), function(block) {
    ref <- block[block$candidate_role == "phase134_phase121_reference", , drop = FALSE]
    if (!nrow(ref)) ref <- block[grepl("phase121_selected_controls", block$candidate_id), , drop = FALSE]
    ref[1L, , drop = FALSE]
  }))
  refs <- refs[, c("scenario_ids", "candidate_id", "screening_score", "max_scenario_forecast_truth_mae"), drop = FALSE]
  names(refs) <- c("scenario_ids", "phase121_reference_candidate_id", "phase121_reference_score", "phase121_reference_forecast_mae")
  out <- merge(winners, refs, by = "scenario_ids", all.x = TRUE)
  out$phase134_score_improvement <- out$phase121_reference_score - out$screening_score
  out$phase134_forecast_mae_improvement <- out$phase121_reference_forecast_mae - out$max_scenario_forecast_truth_mae
  out$phase134_forecast_mae_rel_improvement <- out$phase134_forecast_mae_improvement / out$phase121_reference_forecast_mae
  context <- app_joint_exqdesn_phase135_current_mcmc_context(phase125)
  out <- merge(out, context, by.x = "scenario_ids", by.y = "scenario_id", all.x = TRUE)
  hard_clean <- out$forecast_raw_crossings == 0 & out$contract_crossings == 0 &
    out$fit_reached_max_iter == 0 & out$forecast_reached_max_iter == 0
  out$phase135_decision_class <- ifelse(
    hard_clean & out$phase134_forecast_mae_improvement >= 0.0025,
    "promote_to_mcmc_candidate",
    ifelse(
      abs(out$phase134_forecast_mae_improvement) <= 5.0e-4,
      "retain_reference",
      "needs_model_redesign_or_matched_spec_diagnostic"
    )
  )
  out$phase135_next_action <- ifelse(
    out$phase135_decision_class == "promote_to_mcmc_candidate",
    "keep as VB candidate, but run matched AL-spec exAL screen before launching MCMC",
    ifelse(
      out$phase135_decision_class == "retain_reference",
      "retain current reference unless matched-spec exAL screen shows material gains",
      "do not spend MCMC budget until matched-spec diagnostic or model redesign explains the gap"
    )
  )
  out[order(match(out$phase135_decision_class, c(
    "promote_to_mcmc_candidate",
    "needs_model_redesign_or_matched_spec_diagnostic",
    "retain_reference"
  )), out$scenario_ids), , drop = FALSE]
}

app_joint_exqdesn_phase135_pair_map <- function() {
  data.frame(
    pair_id = c("joint_matched_to_joint_al", "independent_matched_to_independent_al"),
    source_al_model_id = c("joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb"),
    target_exal_model_id = c("joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"),
    candidate_role = c(
      "phase135_matched_joint_al_spec_exal_candidate",
      "phase135_matched_independent_al_spec_exal_candidate"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase135_matched_spec_parity_audit <- function(controls, phase125) {
  pair_map <- app_joint_exqdesn_phase135_pair_map()
  context <- app_joint_exqdesn_phase135_current_mcmc_context(phase125)
  rows <- list()
  scenarios <- sort(unique(controls$scenario_ids))
  compare_cols <- c("tau0", "zeta2", "alpha_prior_sd", "rhs_vb_inner", "vb_max_iter", "adaptive_vb_max_iter_grid")
  for (sid in scenarios) {
    for (ii in seq_len(nrow(pair_map))) {
      src <- controls[controls$scenario_ids == sid & controls$model_ids == pair_map$source_al_model_id[[ii]], , drop = FALSE]
      tgt <- controls[controls$scenario_ids == sid & controls$model_ids == pair_map$target_exal_model_id[[ii]], , drop = FALSE]
      if (nrow(src) != 1L || nrow(tgt) != 1L) next
      same <- vapply(compare_cols, function(nm) identical(as.character(src[[nm]][[1L]]), as.character(tgt[[nm]][[1L]])), logical(1L))
      ctx <- context[context$scenario_id == sid, , drop = FALSE]
      rows[[length(rows) + 1L]] <- data.frame(
        scenario_id = sid,
        pair_id = pair_map$pair_id[[ii]],
        source_al_model_id = pair_map$source_al_model_id[[ii]],
        current_exal_model_id = pair_map$target_exal_model_id[[ii]],
        same_design_fixture = TRUE,
        feature_p = if (nrow(ctx)) ctx$feature_p[[1L]] else NA_character_,
        tau_grid_unique = if (nrow(ctx)) ctx$tau_grid_unique[[1L]] else NA_integer_,
        current_tau0_same = same[["tau0"]],
        current_zeta2_same = same[["zeta2"]],
        current_alpha_prior_sd_same = same[["alpha_prior_sd"]],
        current_rhs_vb_inner_same = same[["rhs_vb_inner"]],
        current_vb_budget_same = same[["vb_max_iter"]] && same[["adaptive_vb_max_iter_grid"]],
        current_all_compared_controls_same = all(same),
        source_al_tau0 = as.character(src$tau0[[1L]]),
        current_exal_tau0 = as.character(tgt$tau0[[1L]]),
        source_al_zeta2 = as.character(src$zeta2[[1L]]),
        current_exal_zeta2 = as.character(tgt$zeta2[[1L]]),
        source_al_alpha_prior_sd = as.character(src$alpha_prior_sd[[1L]]),
        current_exal_alpha_prior_sd = as.character(tgt$alpha_prior_sd[[1L]]),
        source_al_candidate_id = src$candidate_id[[1L]],
        current_exal_candidate_id = tgt$candidate_id[[1L]],
        phase135_matched_registry_will_copy_al_controls = TRUE,
        stringsAsFactors = FALSE
      )
    }
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase135_matched_exal_registry <- function(
  controls,
  screening_output_dir = app_joint_exqdesn_phase135_default_screening_dir(),
  n_cores = 1L
) {
  screening_output_dir <- normalizePath(screening_output_dir, mustWork = FALSE)
  pair_map <- app_joint_exqdesn_phase135_pair_map()
  scenarios <- sort(unique(controls$scenario_ids))
  rows <- list()
  for (sid in scenarios) {
    for (ii in seq_len(nrow(pair_map))) {
      src <- controls[controls$scenario_ids == sid & controls$model_ids == pair_map$source_al_model_id[[ii]], , drop = FALSE]
      tgt <- controls[controls$scenario_ids == sid & controls$model_ids == pair_map$target_exal_model_id[[ii]], , drop = FALSE]
      if (nrow(src) != 1L || nrow(tgt) != 1L) {
        stop(sprintf("Missing matched source/target controls for scenario '%s' and pair '%s'.", sid, pair_map$pair_id[[ii]]), call. = FALSE)
      }
      case_slug <- paste(sid, pair_map$target_exal_model_id[[ii]], sep = "__")
      case_slug <- gsub("[^A-Za-z0-9_]+", "_", case_slug)
      suffix <- paste0("phase135_match_", pair_map$source_al_model_id[[ii]], "_controls")
      suffix <- gsub("[^A-Za-z0-9_]+", "_", suffix)
      candidate_id <- paste(case_slug, suffix, sep = "__")
      rows[[length(rows) + 1L]] <- data.frame(
        candidate_id = candidate_id,
        candidate_label = paste(
          sid,
          pair_map$target_exal_model_id[[ii]],
          sprintf("exAL matched to %s controls", pair_map$source_al_model_id[[ii]]),
          sep = " | "
        ),
        use_existing_artifacts = FALSE,
        fit_dir = file.path(screening_output_dir, "cases", case_slug, "candidates", suffix, "fit"),
        forecast_dir = file.path(screening_output_dir, "cases", case_slug, "candidates", suffix, "forecast"),
        vb_max_iter = as.integer(src$vb_max_iter[[1L]]),
        adaptive_vb_max_iter_grid = as.character(src$adaptive_vb_max_iter_grid[[1L]]),
        vb_tol = as.numeric(src$vb_tol[[1L]]),
        rhs_vb_inner = as.integer(src$rhs_vb_inner[[1L]]),
        tau0 = as.numeric(src$tau0[[1L]]),
        zeta2 = as.numeric(src$zeta2[[1L]]),
        a_sigma = as.numeric(src$a_sigma[[1L]]),
        b_sigma = as.numeric(src$b_sigma[[1L]]),
        alpha_prior_sd = as.character(src$alpha_prior_sd[[1L]]),
        alpha_min_spacing = as.numeric(src$alpha_min_spacing[[1L]]),
        gamma_init_policy = as.character(src$gamma_init_policy[[1L]]),
        review_adjustment_threshold = as.numeric(src$review_adjustment_threshold[[1L]]),
        max_dense_dim = as.integer(src$max_dense_dim[[1L]]),
        n_cores = as.integer(n_cores),
        candidate_role = pair_map$candidate_role[[ii]],
        notes = "Phase135 exAL-only matched-spec diagnostic: copies the corresponding AL RHS/readout controls; AL rows are not rerun.",
        scenario_ids = sid,
        model_ids = pair_map$target_exal_model_id[[ii]],
        case_id = case_slug,
        phase135_pair_id = pair_map$pair_id[[ii]],
        matched_source_al_model_id = pair_map$source_al_model_id[[ii]],
        matched_source_al_candidate_id = src$candidate_id[[1L]],
        current_exal_candidate_id = tgt$candidate_id[[1L]],
        phase135_matched_controls = "tau0,zeta2,alpha_prior_sd,rhs_vb_inner,vb_max_iter,adaptive_vb_max_iter_grid,vb_tol,a_sigma,b_sigma,alpha_min_spacing,max_dense_dim",
        stringsAsFactors = FALSE
      )
    }
  }
  registry <- app_joint_qdesn_bind_rows(rows)
  app_joint_qdesn_validate_screening_registry(registry, allow_alpha_prior_vectors = FALSE)
  registry
}

app_joint_exqdesn_phase135_launch_commands <- function(
  registry_path,
  screening_output_dir,
  fixture_dir,
  workers = 8L,
  n_cores_per_worker = 1L,
  run_id = "phase135_matched_exal_20260715"
) {
  run_cmd <- sprintf(
    "bash application/scripts/123_launch_joint_qdesn_screening_parallel_chunks.sh --registry %s --canonical-output-dir %s --fixture-dir %s --workers %d --n-cores-per-worker %d --run-id %s --session-prefix joint_qdesn_phase135_matched_exal",
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
    command_id = c("launch_phase135_matched_exal_screen", "audit_phase135_matched_exal_screen"),
    command = c(run_cmd, audit_cmd),
    purpose = c(
      "Run exAL-only matched-spec rows using the corresponding AL controls; do not rerun AL rows.",
      "Build the canonical Phase135 matched-spec audit after all worker chunks finish."
    ),
    run_condition = c(
      "Launch after the Phase135 readiness manifest passes.",
      "Run after every Phase135 worker session has ended cleanly."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase135_assessment <- function(phase134, phase125, controls, registry, parity_audit, phase134_winners) {
  source_ok <- all(phase134$manifest$status == "pass") && all(phase125$manifest$status == "pass") &&
    all(controls$phase121_manifest$status == "pass") && all(controls$phase124c_manifest$status == "pass")
  registry_ok <- nrow(registry) == 16L &&
    all(registry$model_ids %in% c("joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb")) &&
    !any(registry$model_ids %in% c("joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb"))
  parity_need <- any(!parity_audit$current_tau0_same) || any(!parity_audit$current_all_compared_controls_same)
  hard_fail <- !source_ok || !registry_ok || !nrow(phase134_winners)
  data.frame(
    audit_gate = if (hard_fail) "fail" else "pass",
    implementation_gate = if (hard_fail) "fail" else "pass",
    n_phase134_winner_rows = nrow(phase134_winners),
    n_matched_exal_registry_rows = nrow(registry),
    n_matched_joint_rows = sum(registry$model_ids == "joint_exqdesn_rhs_vb"),
    n_matched_independent_rows = sum(registry$model_ids == "exqdesn_rhs_independent_vb"),
    n_current_tau0_mismatches = sum(!parity_audit$current_tau0_same),
    n_current_full_control_mismatches = sum(!parity_audit$current_all_compared_controls_same),
    matched_spec_diagnostic_needed = parity_need,
    article_update_recommendation = "do_not_update_article_until_matched_exal_screen_and_mcmc_confirmation_pass",
    next_stage_recommendation = "launch_phase135_matched_exal_screen_then_compare_to_existing_al_rows",
    status_reason = if (hard_fail) {
      "Phase135 readiness failed source or registry gates."
    } else if (parity_need) {
      "Current AL/exAL controls are not matched; Phase135 exAL-only matched-spec screen is ready."
    } else {
      "Current controls are already matched; matched-spec launch is optional."
    },
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase135_readme <- function(run_config, assessment, phase134_winners, parity_audit, launch_commands) {
  c(
    "# Joint exQDESN Phase135 matched AL-spec exAL readiness",
    "",
    "Phase135 freezes the Phase134 per-scenario Joint exQDESN findings and prepares an exAL-only matched-spec diagnostic screen.",
    "The scientific question is whether exAL behaves similarly to AL when it is run with the same RHS/readout controls used by the corresponding AL model.",
    "",
    sprintf("- Output directory: `%s`", run_config$out_dir[[1L]]),
    sprintf("- Screening output directory: `%s`", run_config$screening_output_dir[[1L]]),
    sprintf("- Phase134 winner rows: %d", nrow(phase134_winners)),
    sprintf("- Matched exAL candidate rows: %d", run_config$n_matched_exal_registry_rows[[1L]]),
    sprintf("- Current tau0 mismatches: %d", assessment$n_current_tau0_mismatches[[1L]]),
    sprintf("- Current full-control mismatches: %d", assessment$n_current_full_control_mismatches[[1L]]),
    "",
    "Current parity summary:",
    paste(sprintf(
      "- `%s` / `%s`: tau0 same = `%s`, all compared controls same = `%s`",
      parity_audit$scenario_id,
      parity_audit$pair_id,
      parity_audit$current_tau0_same,
      parity_audit$current_all_compared_controls_same
    ), collapse = "\n"),
    "",
    "Launch command:",
    "",
    launch_commands$command[launch_commands$command_id == "launch_phase135_matched_exal_screen"][[1L]],
    "",
    "Article policy:",
    "- Do not update article tables from Phase135 readiness.",
    "- Do not rerun AL rows for this diagnostic; existing AL rows are the matched reference.",
    "- Promote exAL only after matched-spec VB evidence is audited and any article-facing rows are confirmed by MCMC."
  )
}

app_joint_exqdesn_run_phase135_matched_spec_readiness <- function(
  out_dir = app_joint_exqdesn_phase135_default_dir(),
  screening_output_dir = app_joint_exqdesn_phase135_default_screening_dir(),
  phase134_dir = app_joint_exqdesn_phase135_default_phase134_dir(),
  phase121_dir = app_joint_qdesn_default_phase121_case_vb_freeze_dir_fallback(),
  phase124c_dir = app_joint_exqdesn_phase135_default_phase124c_dir(),
  phase125_dir = app_joint_exqdesn_phase135_default_phase125_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  workers = 8L,
  n_cores_per_worker = 1L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  screening_output_dir <- normalizePath(screening_output_dir, mustWork = FALSE)
  fixture_dir <- normalizePath(fixture_dir, mustWork = TRUE)
  app_ensure_dir(out_dir)
  phase134 <- app_joint_exqdesn_phase135_load_phase134(phase134_dir)
  phase125 <- app_joint_exqdesn_phase135_load_phase125(phase125_dir)
  controls <- app_joint_exqdesn_phase135_read_controls(phase121_dir, phase124c_dir)
  phase134_winners <- app_joint_exqdesn_phase135_phase134_winners(phase134, phase125)
  parity_audit <- app_joint_exqdesn_phase135_matched_spec_parity_audit(controls$controls, phase125)
  registry <- app_joint_exqdesn_phase135_matched_exal_registry(
    controls$controls,
    screening_output_dir = screening_output_dir,
    n_cores = n_cores_per_worker
  )
  registry_path <- file.path(out_dir, "phase135_matched_exal_screening_registry.csv")
  launch_commands <- app_joint_exqdesn_phase135_launch_commands(
    registry_path = registry_path,
    screening_output_dir = screening_output_dir,
    fixture_dir = fixture_dir,
    workers = workers,
    n_cores_per_worker = n_cores_per_worker
  )
  assessment <- app_joint_exqdesn_phase135_assessment(phase134, phase125, controls, registry, parity_audit, phase134_winners)
  run_config <- data.frame(
    run_id = "joint_qdesn_phase135_matched_exal_readiness",
    out_dir = out_dir,
    screening_output_dir = screening_output_dir,
    phase134_dir = phase134$dir,
    phase121_dir = controls$phase121_dir,
    phase124c_dir = controls$phase124c_dir,
    phase125_dir = phase125$dir,
    fixture_dir = fixture_dir,
    workers = as.integer(workers),
    n_cores_per_worker = as.integer(n_cores_per_worker),
    n_phase134_winner_rows = nrow(phase134_winners),
    n_matched_exal_registry_rows = nrow(registry),
    readiness_decision = if (assessment$audit_gate[[1L]] == "pass") "ready_to_launch_phase135_matched_exal_screen" else "blocked_before_launch",
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_exqdesn_phase135_readme(run_config, assessment, phase134_winners, parity_audit, launch_commands), readme_path, useBytes = TRUE)
  paths <- c(
    phase135_run_config = app_joint_qdesn_screening_write_csv(run_config, file.path(out_dir, "phase135_run_config.csv")),
    phase134_source_manifest_verification = app_joint_qdesn_screening_write_csv(phase134$manifest, file.path(out_dir, "phase134_source_manifest_verification.csv")),
    phase121_source_manifest_verification = app_joint_qdesn_screening_write_csv(controls$phase121_manifest, file.path(out_dir, "phase121_source_manifest_verification.csv")),
    phase124c_source_manifest_verification = app_joint_qdesn_screening_write_csv(controls$phase124c_manifest, file.path(out_dir, "phase124c_source_manifest_verification.csv")),
    phase125_source_manifest_verification = app_joint_qdesn_screening_write_csv(phase125$manifest, file.path(out_dir, "phase125_source_manifest_verification.csv")),
    phase134_per_scenario_winners = app_joint_qdesn_screening_write_csv(phase134_winners, file.path(out_dir, "phase134_per_scenario_winners.csv")),
    phase135_matched_spec_parity_audit = app_joint_qdesn_screening_write_csv(parity_audit, file.path(out_dir, "phase135_matched_spec_parity_audit.csv")),
    phase135_matched_exal_screening_registry = app_joint_qdesn_screening_write_csv(registry, registry_path),
    phase135_launch_commands = app_joint_qdesn_screening_write_csv(launch_commands, file.path(out_dir, "phase135_launch_commands.csv")),
    phase135_assessment = app_joint_qdesn_screening_write_csv(assessment, file.path(out_dir, "phase135_assessment.csv")),
    provenance = app_joint_qdesn_screening_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    screening_output_dir = screening_output_dir,
    run_config = run_config,
    phase134 = phase134,
    phase125 = phase125,
    controls = controls,
    phase134_winners = phase134_winners,
    parity_audit = parity_audit,
    registry = registry,
    launch_commands = launch_commands,
    assessment = assessment,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path)
  )
}

app_joint_exqdesn_phase135_required_screening_files <- function() {
  c(
    "candidate_registry.csv",
    "candidate_scorecard.csv",
    "candidate_manifest_verification.csv",
    "fit_scenario_metric_summary.csv",
    "forecast_scenario_metric_summary.csv",
    "forecast_tau_metric_summary.csv",
    "screening_health_summary.csv",
    "scenario_failure_summary.csv",
    "selected_spec_recommendation.csv",
    "artifact_manifest.csv"
  )
}

app_joint_exqdesn_phase135_load_screening_results <- function(screening_dir) {
  screening_dir <- normalizePath(screening_dir, mustWork = TRUE)
  required <- app_joint_exqdesn_phase135_required_screening_files()
  missing <- required[!file.exists(file.path(screening_dir, required))]
  if (length(missing)) {
    stop(sprintf("Phase135 screening artifact is missing required files: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  manifest <- app_joint_qdesn_phase108_manifest_verify(screening_dir, "phase135_matched_exal_screening")
  if (any(manifest$status != "pass")) stop("Phase135 screening artifact manifest verification failed.", call. = FALSE)
  candidate_manifest <- app_read_csv(file.path(screening_dir, "candidate_manifest_verification.csv"))
  app_check_required_columns(candidate_manifest, c("candidate_id", "stage", "exists", "status"), "Phase135 candidate manifest verification")
  list(
    dir = screening_dir,
    manifest = manifest,
    registry = app_read_csv(file.path(screening_dir, "candidate_registry.csv")),
    scorecard = app_read_csv(file.path(screening_dir, "candidate_scorecard.csv")),
    candidate_manifest = candidate_manifest,
    fit_scenario = app_read_csv(file.path(screening_dir, "fit_scenario_metric_summary.csv")),
    forecast_scenario = app_read_csv(file.path(screening_dir, "forecast_scenario_metric_summary.csv")),
    forecast_tau = app_read_csv(file.path(screening_dir, "forecast_tau_metric_summary.csv")),
    health = app_read_csv(file.path(screening_dir, "screening_health_summary.csv")),
    failures = app_read_csv(file.path(screening_dir, "scenario_failure_summary.csv")),
    selected = app_read_csv(file.path(screening_dir, "selected_spec_recommendation.csv"))
  )
}

app_joint_exqdesn_phase135_mean_column <- function(path, column, label) {
  if (!file.exists(path)) stop(sprintf("Required %s file is missing: %s", label, path), call. = FALSE)
  x <- app_read_csv(path)
  app_check_required_columns(x, column, label)
  mean(x[[column]], na.rm = TRUE)
}

app_joint_exqdesn_phase135_single_assessment <- function(dir, file_name, label) {
  path <- file.path(dir, file_name)
  if (!file.exists(path)) stop(sprintf("Required %s assessment is missing: %s", label, path), call. = FALSE)
  x <- app_read_csv(path)
  app_check_required_columns(x, c(
    "gate_status", "raw_crossing_pairs", "contract_crossing_pairs",
    "max_abs_adjustment", "reached_max_iter", "elapsed_seconds"
  ), label)
  x[1L, , drop = FALSE]
}

app_joint_exqdesn_phase135_matched_al_comparison <- function(screening, controls) {
  registry <- screening$registry
  app_check_required_columns(registry, c(
    "candidate_id", "scenario_ids", "model_ids", "phase135_pair_id",
    "matched_source_al_model_id", "matched_source_al_candidate_id",
    "tau0", "zeta2", "alpha_prior_sd", "rhs_vb_inner", "vb_max_iter",
    "adaptive_vb_max_iter_grid"
  ), "Phase135 screening registry")
  app_check_required_columns(controls, c(
    "candidate_id", "scenario_ids", "model_ids", "fit_dir", "forecast_dir",
    "tau0", "zeta2", "alpha_prior_sd", "rhs_vb_inner", "vb_max_iter",
    "adaptive_vb_max_iter_grid"
  ), "Phase135 source AL controls")
  rows <- vector("list", nrow(registry))
  for (ii in seq_len(nrow(registry))) {
    row <- registry[ii, , drop = FALSE]
    source <- controls[
      controls$candidate_id == row$matched_source_al_candidate_id[[1L]] &
        controls$model_ids == row$matched_source_al_model_id[[1L]],
      ,
      drop = FALSE
    ]
    if (nrow(source) != 1L) {
      stop(
        sprintf(
          "Could not resolve exact matched AL source row for Phase135 candidate '%s' (%d rows).",
          row$candidate_id[[1L]],
          nrow(source)
        ),
        call. = FALSE
      )
    }
    ex_fit <- screening$fit_scenario[screening$fit_scenario$candidate_id == row$candidate_id[[1L]], , drop = FALSE]
    ex_forecast <- screening$forecast_scenario[screening$forecast_scenario$candidate_id == row$candidate_id[[1L]], , drop = FALSE]
    ex_health <- screening$health[screening$health$candidate_id == row$candidate_id[[1L]], , drop = FALSE]
    if (nrow(ex_fit) != 1L || nrow(ex_forecast) != 1L || nrow(ex_health) != 1L) {
      stop(sprintf("Phase135 candidate '%s' does not have exactly one fit/forecast/health row.", row$candidate_id[[1L]]), call. = FALSE)
    }
    al_fit_assessment <- app_joint_exqdesn_phase135_single_assessment(source$fit_dir[[1L]], "fit_validation_assessment.csv", "matched AL fit")
    al_forecast_assessment <- app_joint_exqdesn_phase135_single_assessment(source$forecast_dir[[1L]], "forecast_validation_assessment.csv", "matched AL forecast")
    al_fit_mae <- app_joint_exqdesn_phase135_mean_column(
      file.path(source$fit_dir[[1L]], "fit_truth_comparison.csv"),
      "truth_abs_error",
      "matched AL fit truth comparison"
    )
    al_forecast_mae <- app_joint_exqdesn_phase135_mean_column(
      file.path(source$forecast_dir[[1L]], "forecast_truth_comparison.csv"),
      "truth_abs_error",
      "matched AL forecast truth comparison"
    )
    al_fit_check <- app_joint_exqdesn_phase135_mean_column(
      file.path(source$fit_dir[[1L]], "fit_truth_comparison.csv"),
      "check_loss",
      "matched AL fit truth comparison"
    )
    al_forecast_check <- app_joint_exqdesn_phase135_mean_column(
      file.path(source$forecast_dir[[1L]], "forecast_truth_comparison.csv"),
      "check_loss",
      "matched AL forecast truth comparison"
    )
    forecast_delta <- ex_forecast$truth_mae[[1L]] - al_forecast_mae
    fit_delta <- ex_fit$truth_mae[[1L]] - al_fit_mae
    rows[[ii]] <- data.frame(
      scenario_id = row$scenario_ids[[1L]],
      pair_id = row$phase135_pair_id[[1L]],
      comparison_class = if (row$model_ids[[1L]] == "joint_exqdesn_rhs_vb") "joint" else "independent",
      source_al_model_id = row$matched_source_al_model_id[[1L]],
      target_exal_model_id = row$model_ids[[1L]],
      source_al_candidate_id = row$matched_source_al_candidate_id[[1L]],
      target_exal_candidate_id = row$candidate_id[[1L]],
      tau0 = as.numeric(row$tau0[[1L]]),
      zeta2 = as.numeric(row$zeta2[[1L]]),
      alpha_prior_sd = as.character(row$alpha_prior_sd[[1L]]),
      rhs_vb_inner = as.integer(row$rhs_vb_inner[[1L]]),
      vb_max_iter = as.integer(row$vb_max_iter[[1L]]),
      adaptive_vb_max_iter_grid = as.character(row$adaptive_vb_max_iter_grid[[1L]]),
      al_fit_mae = al_fit_mae,
      exal_fit_mae = ex_fit$truth_mae[[1L]],
      fit_delta_exal_minus_al = fit_delta,
      fit_relative_delta_exal_minus_al = fit_delta / pmax(al_fit_mae, 1.0e-12),
      al_forecast_mae = al_forecast_mae,
      exal_forecast_mae = ex_forecast$truth_mae[[1L]],
      forecast_delta_exal_minus_al = forecast_delta,
      forecast_relative_delta_exal_minus_al = forecast_delta / pmax(al_forecast_mae, 1.0e-12),
      al_fit_check_loss = al_fit_check,
      exal_fit_check_loss = ex_fit$check_loss_mean[[1L]],
      al_forecast_check_loss = al_forecast_check,
      exal_forecast_check_loss = ex_forecast$check_loss_mean[[1L]],
      al_fit_gate_status = al_fit_assessment$gate_status[[1L]],
      al_forecast_gate_status = al_forecast_assessment$gate_status[[1L]],
      exal_gate_status = ex_health$gate_status[[1L]],
      al_forecast_raw_crossings = as.integer(al_forecast_assessment$raw_crossing_pairs[[1L]]),
      exal_forecast_raw_crossings = as.integer(ex_health$forecast_raw_crossings[[1L]]),
      al_forecast_contract_crossings = as.integer(al_forecast_assessment$contract_crossing_pairs[[1L]]),
      exal_forecast_contract_crossings = as.integer(ex_health$contract_crossings[[1L]]),
      al_forecast_max_adjustment = as.numeric(al_forecast_assessment$max_abs_adjustment[[1L]]),
      exal_forecast_max_adjustment = as.numeric(ex_health$max_forecast_adjustment[[1L]]),
      al_fit_reached_max_iter = as.logical(al_fit_assessment$reached_max_iter[[1L]]),
      al_forecast_reached_max_iter = as.logical(al_forecast_assessment$reached_max_iter[[1L]]),
      exal_fit_reached_max_iter = as.logical(ex_health$fit_reached_max_iter[[1L]]),
      exal_forecast_reached_max_iter = as.logical(ex_health$forecast_reached_max_iter[[1L]]),
      exal_underperforms_al_fit = fit_delta > 0,
      exal_underperforms_al_forecast = forecast_delta > 0,
      phase135_result_class = if (forecast_delta <= 0) "exal_matched_spec_improves_on_al" else "exal_matched_spec_underperforms_al",
      article_mcmc_promotion_status = if (forecast_delta <= 0) {
        "eligible_for_later_mcmc_confirmation"
      } else {
        "hold_until_gamma_mixing_mcmc_protocol"
      },
      stringsAsFactors = FALSE
    )
  }
  out <- app_joint_qdesn_bind_rows(rows)
  out[order(out$comparison_class, out$scenario_id), , drop = FALSE]
}

app_joint_exqdesn_phase135_model_summary <- function(comparison) {
  rows <- lapply(split(comparison, comparison$comparison_class), function(block) {
    data.frame(
      comparison_class = block$comparison_class[[1L]],
      n_rows = nrow(block),
      n_exal_worse_fit = sum(block$exal_underperforms_al_fit),
      n_exal_worse_forecast = sum(block$exal_underperforms_al_forecast),
      mean_al_fit_mae = mean(block$al_fit_mae),
      mean_exal_fit_mae = mean(block$exal_fit_mae),
      mean_fit_delta_exal_minus_al = mean(block$fit_delta_exal_minus_al),
      mean_fit_relative_delta_exal_minus_al = mean(block$fit_relative_delta_exal_minus_al),
      mean_al_forecast_mae = mean(block$al_forecast_mae),
      mean_exal_forecast_mae = mean(block$exal_forecast_mae),
      mean_forecast_delta_exal_minus_al = mean(block$forecast_delta_exal_minus_al),
      mean_forecast_relative_delta_exal_minus_al = mean(block$forecast_relative_delta_exal_minus_al),
      exal_raw_crossings = sum(block$exal_forecast_raw_crossings),
      exal_contract_crossings = sum(block$exal_forecast_contract_crossings),
      exal_max_iter_rows = sum(block$exal_fit_reached_max_iter | block$exal_forecast_reached_max_iter),
      decision = if (all(block$exal_underperforms_al_forecast)) {
        "do_not_promote_matched_exal_vb_to_article_mcmc_yet"
      } else {
        "review_case_level_mcmc_eligibility"
      },
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase135_result_decision <- function(screening, comparison, model_summary) {
  manifests_ok <- all(screening$manifest$status == "pass") && all(screening$candidate_manifest$status == "pass")
  implementation_ok <- manifests_ok && nrow(screening$failures) == 0L &&
    all(screening$health$forecast_raw_crossings == 0) &&
    all(screening$health$contract_crossings == 0)
  all_exal_worse <- all(comparison$exal_underperforms_al_fit) && all(comparison$exal_underperforms_al_forecast)
  data.frame(
    audit_gate = if (implementation_ok) "pass" else "fail",
    article_promotion_gate = "review",
    n_phase135_rows = nrow(comparison),
    n_completed_rows = nrow(screening$health),
    n_worker_failures = nrow(screening$failures),
    n_manifest_rows = nrow(screening$manifest),
    n_candidate_manifest_rows = nrow(screening$candidate_manifest),
    n_candidate_manifest_failures = sum(screening$candidate_manifest$status != "pass"),
    n_pass_rows = sum(screening$health$gate_status == "pass"),
    n_review_rows = sum(screening$health$gate_status == "review"),
    n_fail_rows = sum(screening$health$gate_status == "fail"),
    n_exal_worse_fit = sum(comparison$exal_underperforms_al_fit),
    n_exal_worse_forecast = sum(comparison$exal_underperforms_al_forecast),
    total_exal_raw_crossings = sum(comparison$exal_forecast_raw_crossings),
    total_exal_contract_crossings = sum(comparison$exal_forecast_contract_crossings),
    max_exal_forecast_adjustment = max(comparison$exal_forecast_max_adjustment),
    mean_joint_forecast_delta_exal_minus_al = model_summary$mean_forecast_delta_exal_minus_al[
      model_summary$comparison_class == "joint"
    ][[1L]],
    mean_independent_forecast_delta_exal_minus_al = model_summary$mean_forecast_delta_exal_minus_al[
      model_summary$comparison_class == "independent"
    ][[1L]],
    conclusion = if (implementation_ok && all_exal_worse) {
      "same_desn_rhs_tau0_controls_do_not_rescue_exal_vb_performance"
    } else if (implementation_ok) {
      "matched_exal_vb_evidence_is_mixed"
    } else {
      "implementation_gate_failed"
    },
    article_update_recommendation = "do_not_update_article_tables_from_phase135_vb",
    mcmc_promotion_recommendation = "do_not_promote_phase135_exal_vb_rows_to_article_mcmc_until_gamma_mixing_mcmc_protocol_is_prepared",
    next_step = "prepare_exal_mcmc_confirmation_with_matched_desn_rhs_tau0_controls_large_parallel_chains_and_gamma_slice_tuning_when_user_authorizes_launch",
    status_reason = if (implementation_ok && all_exal_worse) {
      "Phase135 is reproducible and crossing-clean, but matched exAL underperforms the exact same-control AL rows in every fit and forecast case."
    } else if (implementation_ok) {
      "Phase135 implementation gates passed; case-level exAL promotion needs review."
    } else {
      "Phase135 implementation gates did not pass."
    },
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase135_mcmc_policy <- function() {
  data.frame(
    step = c(
      "freeze_matched_controls",
      "initialize_from_matched_exal_vb",
      "use_large_parallel_chains",
      "tune_gamma_slice_kernel",
      "assess_posterior_quality",
      "promote_only_after_mcmc_audit"
    ),
    policy = c(
      "Use the same DESN, RHS, and tau0 controls as the corresponding AL rows for exAL MCMC confirmation.",
      "Use Phase135 matched exAL VB outputs as initialization where available; do not change AL references.",
      "Prefer several independent chains, e.g. eight chains per case, before increasing chain length further.",
      "Treat gamma mixing as the primary MCMC approximation target; tune slice-width/kernel controls before declaring exAL weak.",
      "Judge adequacy by article-facing quantile-grid performance, finite qhat summaries, zero contract crossings, and acceptable gamma/sigma/tau trace behavior; perfect gamma ESS is not required.",
      "Do not update article tables from Phase135 VB alone; promote exAL rows only after MCMC confirmation is reproducible and hash-manifested."
    ),
    launched_in_phase135 = FALSE,
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase135_result_readme <- function(run_config, decision, model_summary) {
  c(
    "# Joint exQDESN Phase135 matched-spec result audit",
    "",
    "This audit formalizes the completed Phase135 matched-spec exAL screen.",
    "Phase135 copied the corresponding AL DESN/RHS/tau0 controls into the exAL rows and reran only exAL.",
    "",
    sprintf("- Output directory: `%s`", run_config$out_dir[[1L]]),
    sprintf("- Screening directory: `%s`", run_config$screening_dir[[1L]]),
    sprintf("- Completed rows: %d / %d", decision$n_completed_rows[[1L]], decision$n_phase135_rows[[1L]]),
    sprintf("- Candidate manifest failures: %d", decision$n_candidate_manifest_failures[[1L]]),
    sprintf("- exAL raw crossings: %d", decision$total_exal_raw_crossings[[1L]]),
    sprintf("- exAL contract crossings: %d", decision$total_exal_contract_crossings[[1L]]),
    sprintf("- exAL worse in fit rows: %d", decision$n_exal_worse_fit[[1L]]),
    sprintf("- exAL worse in forecast rows: %d", decision$n_exal_worse_forecast[[1L]]),
    "",
    "Model-level matched-control forecast deltas:",
    paste(sprintf(
      "- `%s`: AL MAE = %.4f, matched exAL MAE = %.4f, exAL-minus-AL = %.4f",
      model_summary$comparison_class,
      model_summary$mean_al_forecast_mae,
      model_summary$mean_exal_forecast_mae,
      model_summary$mean_forecast_delta_exal_minus_al
    ), collapse = "\n"),
    "",
    "Decision:",
    sprintf("- Audit gate: `%s`", decision$audit_gate[[1L]]),
    sprintf("- Article promotion gate: `%s`", decision$article_promotion_gate[[1L]]),
    sprintf("- Conclusion: `%s`", decision$conclusion[[1L]]),
    sprintf("- Article recommendation: `%s`", decision$article_update_recommendation[[1L]]),
    sprintf("- MCMC recommendation: `%s`", decision$mcmc_promotion_recommendation[[1L]]),
    "",
    "Interpretation:",
    "Matching the AL DESN/RHS/tau0 controls did not rescue exAL at the VB layer.",
    "The artifact is numerically clean, so the next exAL article-evidence attempt should focus on MCMC posterior approximation for the gamma layer, using the same matched controls rather than another broad VB screen."
  )
}

app_joint_exqdesn_run_phase135_matched_spec_result_audit <- function(
  out_dir = app_joint_exqdesn_phase135_default_result_audit_dir(),
  screening_dir = app_joint_exqdesn_phase135_default_screening_dir(),
  phase121_dir = app_joint_qdesn_default_phase121_case_vb_freeze_dir_fallback(),
  phase124c_dir = app_joint_exqdesn_phase135_default_phase124c_dir()
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  screening <- app_joint_exqdesn_phase135_load_screening_results(screening_dir)
  controls <- app_joint_exqdesn_phase135_read_controls(phase121_dir, phase124c_dir)
  comparison <- app_joint_exqdesn_phase135_matched_al_comparison(screening, controls$controls)
  model_summary <- app_joint_exqdesn_phase135_model_summary(comparison)
  decision <- app_joint_exqdesn_phase135_result_decision(screening, comparison, model_summary)
  mcmc_policy <- app_joint_exqdesn_phase135_mcmc_policy()
  run_config <- data.frame(
    run_id = "joint_qdesn_phase135_matched_exal_result_audit",
    out_dir = out_dir,
    screening_dir = screening$dir,
    phase121_dir = controls$phase121_dir,
    phase124c_dir = controls$phase124c_dir,
    n_phase135_rows = nrow(comparison),
    n_matched_joint_rows = sum(comparison$comparison_class == "joint"),
    n_matched_independent_rows = sum(comparison$comparison_class == "independent"),
    analysis_role = "formal_result_audit_no_article_promotion",
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_exqdesn_phase135_result_readme(run_config, decision, model_summary), readme_path, useBytes = TRUE)
  paths <- c(
    phase135_result_run_config = app_joint_qdesn_screening_write_csv(run_config, file.path(out_dir, "phase135_result_run_config.csv")),
    phase135_screening_manifest_verification = app_joint_qdesn_screening_write_csv(screening$manifest, file.path(out_dir, "phase135_screening_manifest_verification.csv")),
    phase135_candidate_manifest_verification = app_joint_qdesn_screening_write_csv(screening$candidate_manifest, file.path(out_dir, "phase135_candidate_manifest_verification.csv")),
    phase121_source_manifest_verification = app_joint_qdesn_screening_write_csv(controls$phase121_manifest, file.path(out_dir, "phase121_source_manifest_verification.csv")),
    phase124c_source_manifest_verification = app_joint_qdesn_screening_write_csv(controls$phase124c_manifest, file.path(out_dir, "phase124c_source_manifest_verification.csv")),
    phase135_matched_exal_vs_source_al_vb_comparison = app_joint_qdesn_screening_write_csv(comparison, file.path(out_dir, "phase135_matched_exal_vs_source_al_vb_comparison.csv")),
    phase135_matched_exal_model_summary = app_joint_qdesn_screening_write_csv(model_summary, file.path(out_dir, "phase135_matched_exal_model_summary.csv")),
    phase135_result_decision = app_joint_qdesn_screening_write_csv(decision, file.path(out_dir, "phase135_result_decision.csv")),
    phase135_gamma_mcmc_policy = app_joint_qdesn_screening_write_csv(mcmc_policy, file.path(out_dir, "phase135_gamma_mcmc_policy.csv")),
    provenance = app_joint_qdesn_screening_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    screening = screening,
    controls = controls,
    comparison = comparison,
    model_summary = model_summary,
    decision = decision,
    mcmc_policy = mcmc_policy,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path)
  )
}
