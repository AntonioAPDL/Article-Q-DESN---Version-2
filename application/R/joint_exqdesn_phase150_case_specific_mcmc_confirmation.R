# Phase150 case-specific Joint exQDESN MCMC confirmation.
#
# This stage freezes the Phase149 per-scenario VB winners into the Phase121
# case-winner schema so the existing Phase122 MCMC confirmation runner can be
# reused without changing its sampling/scoring contract.

app_joint_exqdesn_phase150_default_freeze_dir <- function() {
  app_path("application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_freeze_20260727")
}

app_joint_exqdesn_phase150_default_mcmc_dir <- function() {
  app_path("application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727")
}

app_joint_exqdesn_phase150_default_audit_dir <- function(mcmc_dir = app_joint_exqdesn_phase150_default_mcmc_dir()) {
  file.path(mcmc_dir, "phase150_result_audit")
}

app_joint_exqdesn_phase150_default_orchestration_dir <- function() {
  app_path("application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727_orchestration")
}

app_joint_exqdesn_phase150_lifecycle_status <- function(
  mcmc_dir = app_joint_exqdesn_phase150_default_mcmc_dir(),
  freeze_dir = app_joint_exqdesn_phase150_default_freeze_dir(),
  orchestration_dir = app_joint_exqdesn_phase150_default_orchestration_dir(),
  session_alive = FALSE,
  runner_process_count = 0L
) {
  mcmc_dir <- normalizePath(mcmc_dir, mustWork = FALSE)
  freeze_dir <- normalizePath(freeze_dir, mustWork = FALSE)
  orchestration_dir <- normalizePath(orchestration_dir, mustWork = FALSE)
  exit_path <- file.path(orchestration_dir, "phase150_mcmc.exit")
  exit_code <- NA_integer_
  if (file.exists(exit_path)) {
    exit_text <- trimws(readLines(exit_path, warn = FALSE, n = 1L))
    exit_code <- suppressWarnings(as.integer(exit_text))
  }

  required_mcmc <- c("mcmc_case_summary.csv", "mcmc_case_assessment.csv", "artifact_manifest.csv")
  required_audit <- c(
    "phase150_mcmc_manifest_verification.csv",
    "phase150_freeze_manifest_verification.csv",
    "phase150_mcmc_article_comparison.csv",
    "phase150_mcmc_result_assessment.csv",
    "artifact_manifest.csv"
  )
  audit_dir <- app_joint_exqdesn_phase150_default_audit_dir(mcmc_dir)
  mcmc_present <- file.exists(file.path(mcmc_dir, required_mcmc))
  audit_present <- file.exists(file.path(audit_dir, required_audit))
  summary_rows <- if (mcmc_present[[1L]]) {
    nrow(app_read_csv(file.path(mcmc_dir, "mcmc_case_summary.csv")))
  } else {
    0L
  }

  active <- isTRUE(session_alive) || as.integer(runner_process_count) > 0L
  state <- if (is.na(exit_code) && active) {
    "running"
  } else if (is.na(exit_code)) {
    "interrupted_or_stale"
  } else if (exit_code != 0L) {
    "failed"
  } else if (!all(mcmc_present)) {
    "completed_missing_mcmc_artifacts"
  } else if (!all(audit_present) && active) {
    "completed_audit_in_progress"
  } else if (!all(audit_present)) {
    "completed_pending_audit"
  } else {
    "complete"
  }
  recommendation <- switch(
    state,
    running = "preserve_active_run_and_recheck_later",
    interrupted_or_stale = "inspect_logs_before_any_explicit_resume",
    failed = "diagnose_nonzero_exit_before_any_resume",
    completed_missing_mcmc_artifacts = "treat_as_incomplete_and_diagnose_output_contract",
    completed_audit_in_progress = "preserve_automatic_post_run_audit",
    completed_pending_audit = "run_phase150_post_mcmc_audit_only",
    complete = "verify_manifests_and_review_article_comparison"
  )

  data.frame(
    phase_id = "phase150_case_specific_exal_mcmc_confirmation",
    lifecycle_state = state,
    recommendation = recommendation,
    session_alive = isTRUE(session_alive),
    runner_process_count = as.integer(runner_process_count),
    exit_marker_present = file.exists(exit_path),
    exit_code = exit_code,
    expected_cases = 8L,
    finalized_case_rows = as.integer(summary_rows),
    required_mcmc_files_present = sum(mcmc_present),
    required_mcmc_files_expected = length(required_mcmc),
    required_audit_files_present = sum(audit_present),
    required_audit_files_expected = length(required_audit),
    freeze_manifest_present = file.exists(file.path(freeze_dir, "artifact_manifest.csv")),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase150_required_source_files <- function() {
  c(
    "candidate_registry.csv",
    "candidate_scorecard.csv",
    "screening_health_summary.csv",
    "candidate_manifest_verification.csv",
    "artifact_manifest.csv"
  )
}

app_joint_exqdesn_phase150_required_audit_files <- function() {
  c(
    "phase149_result_assessment.csv",
    "phase149_candidate_ranking.csv",
    "phase149_case_specific_shortlist.csv",
    "phase149_scenario_summary.csv",
    "phase149_mcmc_confirmation_plan.csv",
    "artifact_manifest.csv"
  )
}

app_joint_exqdesn_phase150_source_verification <- function(phase149_dir, readiness_dir, phase149_audit_dir) {
  missing_phase149 <- app_joint_exqdesn_phase150_required_source_files()[
    !file.exists(file.path(phase149_dir, app_joint_exqdesn_phase150_required_source_files()))
  ]
  missing_audit <- app_joint_exqdesn_phase150_required_audit_files()[
    !file.exists(file.path(phase149_audit_dir, app_joint_exqdesn_phase150_required_audit_files()))
  ]
  missing_readiness <- setdiff(
    c("phase149_case_specific_screening_registry.csv", "artifact_manifest.csv"),
    list.files(readiness_dir)
  )
  if (length(c(missing_phase149, missing_audit, missing_readiness))) {
    stop(sprintf(
      "Phase150 source is missing required files: %s",
      paste(c(missing_phase149, missing_audit, missing_readiness), collapse = ", ")
    ), call. = FALSE)
  }
  top <- app_joint_qdesn_phase108_manifest_verify(phase149_dir, "phase149_screening")
  readiness <- app_joint_qdesn_phase108_manifest_verify(readiness_dir, "phase149_readiness")
  audit <- app_joint_qdesn_phase108_manifest_verify(phase149_audit_dir, "phase149_result_audit")
  nested <- app_read_csv(file.path(phase149_dir, "candidate_manifest_verification.csv"))
  app_check_required_columns(nested, c("candidate_id", "status"), "Phase149 nested manifest verification")
  nested_status <- data.frame(
    artifact_label = "phase149_nested_candidate_artifacts",
    label = "candidate_manifest_verification",
    relative_path = "candidate_manifest_verification.csv",
    path = normalizePath(file.path(phase149_dir, "candidate_manifest_verification.csv"), mustWork = TRUE),
    exists = TRUE,
    declared_size_bytes = as.numeric(file.info(file.path(phase149_dir, "candidate_manifest_verification.csv"))$size),
    actual_size_bytes = as.numeric(file.info(file.path(phase149_dir, "candidate_manifest_verification.csv"))$size),
    declared_sha256 = app_sha256_file(file.path(phase149_dir, "candidate_manifest_verification.csv")),
    actual_sha256 = app_sha256_file(file.path(phase149_dir, "candidate_manifest_verification.csv")),
    status = if (all(nested$status == "pass")) "pass" else "fail",
    stringsAsFactors = FALSE
  )
  app_joint_qdesn_bind_rows(list(top, readiness, audit, nested_status))
}

app_joint_exqdesn_phase150_selected_winners <- function(phase149_dir, readiness_dir, phase149_audit_dir) {
  assessment <- app_read_csv(file.path(phase149_audit_dir, "phase149_result_assessment.csv"))
  scenario_summary <- app_read_csv(file.path(phase149_audit_dir, "phase149_scenario_summary.csv"))
  ranking <- app_read_csv(file.path(phase149_audit_dir, "phase149_candidate_ranking.csv"))
  shortlist <- app_read_csv(file.path(phase149_audit_dir, "phase149_case_specific_shortlist.csv"))
  registry <- app_read_csv(file.path(readiness_dir, "phase149_case_specific_screening_registry.csv"))

  app_check_required_columns(assessment, c("gate_status", "observed_candidates", "expected_candidates", "global_specification_selected"), "Phase149 result assessment")
  app_check_required_columns(scenario_summary, c("scenario_id", "selected_candidate_id", "selected_forecast_truth_mae"), "Phase149 scenario summary")
  app_check_required_columns(ranking, c("candidate_id", "scenario_id", "forecast_truth_mae", "fit_truth_mae", "gate_status", "contract_crossing_pairs", "raw_crossing_pairs", "reached_max_iter"), "Phase149 candidate ranking")
  app_check_required_columns(registry, c(
    "candidate_id", "case_id", "scenario_ids", "model_ids", "vb_max_iter",
    "adaptive_vb_max_iter_grid", "vb_tol", "rhs_vb_inner", "tau0", "zeta2",
    "a_sigma", "b_sigma", "alpha_prior_sd", "alpha_min_spacing",
    "gamma_init_policy", "review_adjustment_threshold", "max_dense_dim",
    "phase149_role"
  ), "Phase149 screening registry")

  selected_ids <- scenario_summary$selected_candidate_id
  if (any(!nzchar(selected_ids)) || any(is.na(selected_ids))) {
    stop("Phase149 scenario summary contains empty selected candidate ids.", call. = FALSE)
  }
  if (anyDuplicated(selected_ids)) stop("Phase149 selected candidate ids are not unique.", call. = FALSE)

  rank_sel <- ranking[match(selected_ids, ranking$candidate_id), , drop = FALSE]
  reg_sel <- registry[match(selected_ids, registry$candidate_id), , drop = FALSE]
  short_sel <- shortlist[match(selected_ids, shortlist$candidate_id), , drop = FALSE]
  if (any(is.na(rank_sel$candidate_id)) || any(is.na(reg_sel$candidate_id))) {
    stop("Phase150 could not match all selected Phase149 candidate ids.", call. = FALSE)
  }
  winners <- merge(
    reg_sel,
    rank_sel,
    by = "candidate_id",
    all.x = TRUE,
    suffixes = c("", "_rank"),
    sort = FALSE
  )
  keep_order <- match(selected_ids, winners$candidate_id)
  winners <- winners[keep_order, , drop = FALSE]
  winners$shortlist_order <- short_sel$shortlist_order
  winners$shortlist_role <- short_sel$shortlist_role
  winners$phase150_selection <- "primary_case_specific_phase149_winner"
  winners
}

app_joint_exqdesn_phase150_controls_from_winners <- function(winners) {
  controls <- data.frame(
    case_id = winners$case_id,
    scenario_ids = winners$scenario_ids,
    model_ids = winners$model_ids,
    candidate_id = winners$candidate_id,
    phase121_selection_status = "phase150_selected_from_phase149_case_specific_vb",
    vb_max_iter = as.integer(winners$vb_max_iter),
    adaptive_vb_max_iter_grid = winners$adaptive_vb_max_iter_grid,
    vb_tol = as.numeric(winners$vb_tol),
    rhs_vb_inner = as.integer(winners$rhs_vb_inner),
    tau0 = as.numeric(winners$tau0),
    zeta2 = as.numeric(winners$zeta2),
    a_sigma = as.numeric(winners$a_sigma),
    b_sigma = as.numeric(winners$b_sigma),
    alpha_prior_sd = winners$alpha_prior_sd,
    alpha_min_spacing = as.numeric(winners$alpha_min_spacing),
    gamma_init_policy = winners$gamma_init_policy,
    review_adjustment_threshold = as.numeric(winners$review_adjustment_threshold),
    max_dense_dim = as.integer(winners$max_dense_dim),
    phase149_role = winners$phase149_role,
    phase150_selection = winners$phase150_selection,
    selected_forecast_truth_mae = as.numeric(winners$forecast_truth_mae),
    selected_fit_truth_mae = as.numeric(winners$fit_truth_mae),
    phase149_gate_status = winners$gate_status,
    phase149_raw_crossing_pairs = as.integer(winners$raw_crossing_pairs),
    phase149_contract_crossing_pairs = as.integer(winners$contract_crossing_pairs),
    phase149_reached_max_iter = as.logical(winners$reached_max_iter),
    stringsAsFactors = FALSE
  )
  app_check_required_columns(
    controls,
    c(
      "case_id", "scenario_ids", "model_ids", "candidate_id", "phase121_selection_status",
      "vb_max_iter", "adaptive_vb_max_iter_grid", "vb_tol", "rhs_vb_inner", "tau0",
      "zeta2", "a_sigma", "b_sigma", "alpha_prior_sd", "alpha_min_spacing",
      "gamma_init_policy", "review_adjustment_threshold", "max_dense_dim"
    ),
    "Phase150 case winner controls"
  )
  controls
}

app_joint_exqdesn_phase150_gate_audit <- function(winners, source_manifest) {
  source_fail <- any(source_manifest$status != "pass")
  rows <- lapply(seq_len(nrow(winners)), function(ii) {
    x <- winners[ii, , drop = FALSE]
    finite_metric <- is.finite(x$forecast_truth_mae[[1L]]) && is.finite(x$fit_truth_mae[[1L]])
    implementation_fail <- source_fail ||
      !finite_metric ||
      identical(x$gate_status[[1L]], "fail") ||
      as.integer(x$contract_crossing_pairs[[1L]]) > 0L
    review <- !implementation_fail && (
      !identical(x$gate_status[[1L]], "pass") ||
        as.integer(x$raw_crossing_pairs[[1L]]) > 0L ||
        isTRUE(as.logical(x$reached_max_iter[[1L]]))
    )
    reasons <- c(
      if (source_fail) "Phase149 source manifest verification failed",
      if (!finite_metric) "selected Phase149 metrics are nonfinite",
      if (identical(x$gate_status[[1L]], "fail")) "selected Phase149 candidate failed",
      if (as.integer(x$contract_crossing_pairs[[1L]]) > 0L) "selected Phase149 contract quantiles crossed",
      if (!implementation_fail && !identical(x$gate_status[[1L]], "pass")) "selected Phase149 candidate is review-level",
      if (!implementation_fail && as.integer(x$raw_crossing_pairs[[1L]]) > 0L) "selected Phase149 raw quantiles crossed before contract",
      if (!implementation_fail && isTRUE(as.logical(x$reached_max_iter[[1L]]))) "selected Phase149 VB reached max iterations"
    )
    data.frame(
      case_id = x$case_id[[1L]],
      scenario_id = x$scenario_id[[1L]],
      candidate_id = x$candidate_id[[1L]],
      phase149_role = x$phase149_role[[1L]],
      gate_status = if (implementation_fail) "fail" else if (review) "review" else "pass",
      implementation_status = if (implementation_fail) "fail" else "pass",
      raw_crossing_status = if (as.integer(x$raw_crossing_pairs[[1L]]) > 0L) "review" else "pass",
      phase149_forecast_truth_mae = as.numeric(x$forecast_truth_mae[[1L]]),
      phase149_fit_truth_mae = as.numeric(x$fit_truth_mae[[1L]]),
      phase149_raw_crossing_pairs = as.integer(x$raw_crossing_pairs[[1L]]),
      phase149_contract_crossing_pairs = as.integer(x$contract_crossing_pairs[[1L]]),
      phase149_reached_max_iter = as.logical(x$reached_max_iter[[1L]]),
      status_reason = if (length(reasons)) paste(reasons, collapse = "; ") else "selected Phase149 winner passed freeze gates",
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase150_launch_command <- function(
  freeze_dir,
  mcmc_dir = app_joint_exqdesn_phase150_default_mcmc_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  n_chains = 8L,
  mcmc_n_iter = 8000L,
  mcmc_burn = 2000L,
  mcmc_thin = 4L,
  mcmc_seed_offset = 9500L,
  chain_seed_stride = 100L,
  sigma_upper_multiplier = 50,
  distance_pass = 5,
  chain_pass = 5,
  n_cores = 8L
) {
  args <- c(
    "application/scripts/125_run_joint_qdesn_phase122_mcmc_case_confirmation.R",
    "--output-dir", app_prefer_repo_relative_path(mcmc_dir),
    "--phase121-dir", app_prefer_repo_relative_path(freeze_dir),
    "--fixture-dir", app_prefer_repo_relative_path(fixture_dir),
    "--model-ids", "joint_exqdesn_rhs_vb",
    "--n-chains", as.character(as.integer(n_chains)),
    "--mcmc-n-iter", as.character(as.integer(mcmc_n_iter)),
    "--mcmc-burn", as.character(as.integer(mcmc_burn)),
    "--mcmc-thin", as.character(as.integer(mcmc_thin)),
    "--mcmc-seed-offset", as.character(as.integer(mcmc_seed_offset)),
    "--chain-seed-stride", as.character(as.integer(chain_seed_stride)),
    "--sigma-upper-multiplier", as.character(sigma_upper_multiplier),
    "--distance-pass", as.character(distance_pass),
    "--chain-pass", as.character(chain_pass),
    "--n-cores", as.character(as.integer(n_cores))
  )
  paste("Rscript", paste(shQuote(args), collapse = " "))
}

app_joint_exqdesn_phase150_readme <- function(assessment, run_config, gate_audit) {
  c(
    "# Joint exQDESN Phase150 case-specific MCMC freeze",
    "",
    "This directory freezes the eight primary Phase149 case-specific Joint exQDESN VB winners for MCMC confirmation.",
    "It is intentionally written in the Phase121 case-winner schema so the existing Phase122 MCMC engine can be reused without changing the sampler or scoring contract.",
    "",
    sprintf("- Freeze gate: `%s`", assessment$gate_status[[1L]]),
    sprintf("- Selected cases: %s", assessment$n_cases[[1L]]),
    sprintf("- Source Phase149 directory: `%s`", run_config$phase149_dir[[1L]]),
    sprintf("- Planned MCMC chains/iter/burn/thin: %s/%s/%s/%s", run_config$n_chains[[1L]], run_config$mcmc_n_iter[[1L]], run_config$mcmc_burn[[1L]], run_config$mcmc_thin[[1L]]),
    "",
    "Scoring remains a quantile-grid validation: raw quantile outputs are preserved, while reported scores use the monotone contract grid.",
    "This freeze does not update article tables. Article integration should wait for the MCMC confirmation audit.",
    "",
    "Freeze gate counts:",
    paste(capture.output(print(table(gate_audit$gate_status))), collapse = "\n")
  )
}

app_joint_exqdesn_run_phase150_mcmc_freeze <- function(
  out_dir = app_joint_exqdesn_phase150_default_freeze_dir(),
  phase149_dir = app_joint_exqdesn_phase149_default_dir(),
  readiness_dir = app_joint_exqdesn_phase149_default_readiness_dir(),
  phase149_audit_dir = file.path(phase149_dir, "phase149_result_audit"),
  mcmc_dir = app_joint_exqdesn_phase150_default_mcmc_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  n_chains = 8L,
  mcmc_n_iter = 8000L,
  mcmc_burn = 2000L,
  mcmc_thin = 4L,
  mcmc_seed_offset = 9500L,
  chain_seed_stride = 100L,
  sigma_upper_multiplier = 50,
  distance_pass = 5,
  chain_pass = 5,
  n_cores = 8L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  phase149_dir <- normalizePath(phase149_dir, mustWork = TRUE)
  readiness_dir <- normalizePath(readiness_dir, mustWork = TRUE)
  phase149_audit_dir <- normalizePath(phase149_audit_dir, mustWork = TRUE)
  fixture_dir <- normalizePath(fixture_dir, mustWork = TRUE)
  mcmc_dir <- normalizePath(mcmc_dir, mustWork = FALSE)

  source_manifest <- app_joint_exqdesn_phase150_source_verification(phase149_dir, readiness_dir, phase149_audit_dir)
  winners <- app_joint_exqdesn_phase150_selected_winners(phase149_dir, readiness_dir, phase149_audit_dir)
  controls <- app_joint_exqdesn_phase150_controls_from_winners(winners)
  gate_audit <- app_joint_exqdesn_phase150_gate_audit(winners, source_manifest)
  source_fail <- any(source_manifest$status != "pass")
  coverage_fail <- nrow(controls) != 8L ||
    length(unique(controls$scenario_ids)) != 8L ||
    any(controls$model_ids != "joint_exqdesn_rhs_vb") ||
    anyDuplicated(controls$case_id)
  gate_fail <- any(gate_audit$gate_status == "fail")
  gate_review <- any(gate_audit$gate_status == "review")
  assessment <- data.frame(
    freeze_id = "phase150_case_specific_exal_mcmc_freeze",
    gate_status = if (source_fail || coverage_fail || gate_fail) "fail" else if (gate_review) "review" else "pass",
    n_cases = nrow(controls),
    n_scenarios = length(unique(controls$scenario_ids)),
    n_models = length(unique(controls$model_ids)),
    source_manifest_failures = sum(source_manifest$status != "pass"),
    selected_gate_failures = sum(gate_audit$gate_status == "fail"),
    selected_gate_reviews = sum(gate_audit$gate_status == "review"),
    global_specification_selected = FALSE,
    freeze_policy = "one_primary_case_specific_phase149_winner_per_scenario",
    recommendation = if (source_fail || coverage_fail || gate_fail) {
      "block_mcmc_launch_and_fix_freeze_inputs"
    } else {
      "launch_eight_chain_phase150_mcmc_confirmation"
    },
    stringsAsFactors = FALSE
  )
  launch_command <- app_joint_exqdesn_phase150_launch_command(
    freeze_dir = out_dir,
    mcmc_dir = mcmc_dir,
    fixture_dir = fixture_dir,
    n_chains = n_chains,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin,
    mcmc_seed_offset = mcmc_seed_offset,
    chain_seed_stride = chain_seed_stride,
    sigma_upper_multiplier = sigma_upper_multiplier,
    distance_pass = distance_pass,
    chain_pass = chain_pass,
    n_cores = n_cores
  )
  launch_plan <- data.frame(
    launch_id = "phase150_case_specific_joint_exal_mcmc",
    launch_status = if (assessment$gate_status[[1L]] == "fail") "blocked" else "ready_for_background_launch",
    freeze_dir = app_prefer_repo_relative_path(out_dir),
    mcmc_output_dir = app_prefer_repo_relative_path(mcmc_dir),
    fixture_dir = app_prefer_repo_relative_path(fixture_dir),
    n_cases = nrow(controls),
    n_chains = as.integer(n_chains),
    mcmc_n_iter = as.integer(mcmc_n_iter),
    mcmc_burn = as.integer(mcmc_burn),
    mcmc_thin = as.integer(mcmc_thin),
    n_cores = as.integer(n_cores),
    command = launch_command,
    stringsAsFactors = FALSE
  )
  metric_summary <- winners[, intersect(c(
    "candidate_id", "case_id", "scenario_id", "phase149_role", "shortlist_order",
    "shortlist_role", "forecast_truth_mae", "fit_truth_mae", "forecast_check_loss_mean",
    "crps_grid_mean", "abs_hit_rate_error", "abs_coverage_error", "gate_status",
    "raw_crossing_pairs", "contract_crossing_pairs", "reached_max_iter"
  ), names(winners)), drop = FALSE]
  readme_path <- file.path(out_dir, "README.md")
  run_config <- data.frame(
    run_id = "joint_exqdesn_phase150_case_specific_mcmc_freeze",
    phase149_dir = app_prefer_repo_relative_path(phase149_dir),
    readiness_dir = app_prefer_repo_relative_path(readiness_dir),
    phase149_audit_dir = app_prefer_repo_relative_path(phase149_audit_dir),
    fixture_dir = app_prefer_repo_relative_path(fixture_dir),
    mcmc_dir = app_prefer_repo_relative_path(mcmc_dir),
    n_chains = as.integer(n_chains),
    mcmc_n_iter = as.integer(mcmc_n_iter),
    mcmc_burn = as.integer(mcmc_burn),
    mcmc_thin = as.integer(mcmc_thin),
    mcmc_seed_offset = as.integer(mcmc_seed_offset),
    chain_seed_stride = as.integer(chain_seed_stride),
    sigma_upper_multiplier = sigma_upper_multiplier,
    distance_pass = distance_pass,
    chain_pass = chain_pass,
    n_cores = as.integer(n_cores),
    validation_contract = "quantile_grid_readout_fit_and_no_refit_forecast",
    scalar_predictive_density_claim = FALSE,
    stringsAsFactors = FALSE
  )
  writeLines(app_joint_exqdesn_phase150_readme(assessment, run_config, gate_audit), readme_path, useBytes = TRUE)
  paths <- c(
    phase150_run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "phase150_run_config.csv")),
    phase150_freeze_assessment = app_joint_qvp_write_csv(assessment, file.path(out_dir, "phase150_freeze_assessment.csv")),
    phase149_source_manifest_verification = app_joint_qvp_write_csv(source_manifest, file.path(out_dir, "phase149_source_manifest_verification.csv")),
    case_winner_controls = app_joint_qvp_write_csv(controls, file.path(out_dir, "case_winner_controls.csv")),
    case_winner_metric_summary = app_joint_qvp_write_csv(metric_summary, file.path(out_dir, "case_winner_metric_summary.csv")),
    case_winner_gate_audit = app_joint_qvp_write_csv(gate_audit, file.path(out_dir, "case_winner_gate_audit.csv")),
    phase150_selected_winner_summary = app_joint_qvp_write_csv(winners, file.path(out_dir, "phase150_selected_winner_summary.csv")),
    phase150_mcmc_launch_plan = app_joint_qvp_write_csv(launch_plan, file.path(out_dir, "phase150_mcmc_launch_plan.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    assessment = assessment,
    controls = controls,
    gate_audit = gate_audit,
    launch_plan = launch_plan,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path)
  )
}

app_joint_exqdesn_phase150_audit_mcmc_output <- function(
  mcmc_dir = app_joint_exqdesn_phase150_default_mcmc_dir(),
  freeze_dir = app_joint_exqdesn_phase150_default_freeze_dir(),
  out_dir = app_joint_exqdesn_phase150_default_audit_dir(mcmc_dir),
  article_scenario_table = app_path("tables/joint_qdesn_article_validation_mcmc_balanced_scenario_summary.csv")
) {
  mcmc_dir <- normalizePath(mcmc_dir, mustWork = TRUE)
  freeze_dir <- normalizePath(freeze_dir, mustWork = TRUE)
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  required <- c("mcmc_case_summary.csv", "mcmc_case_assessment.csv", "artifact_manifest.csv")
  missing <- required[!file.exists(file.path(mcmc_dir, required))]
  if (length(missing)) stop(sprintf("Phase150 MCMC output is missing required files: %s", paste(missing, collapse = ", ")), call. = FALSE)
  mcmc_manifest <- app_joint_qdesn_phase108_manifest_verify(mcmc_dir, "phase150_mcmc_output")
  freeze_manifest <- app_joint_qdesn_phase108_manifest_verify(freeze_dir, "phase150_freeze")
  summary <- app_read_csv(file.path(mcmc_dir, "mcmc_case_summary.csv"))
  assessment <- app_read_csv(file.path(mcmc_dir, "mcmc_case_assessment.csv"))
  controls <- app_read_csv(file.path(freeze_dir, "case_winner_controls.csv"))
  article <- if (file.exists(article_scenario_table)) app_read_csv(article_scenario_table) else data.frame()
  comparison <- summary
  if (nrow(article)) {
    joint_al <- article[article$model_id == "joint_qdesn_rhs_mcmc", c("scenario_id", "mcmc_forecast_truth_mae", "mcmc_fit_truth_mae"), drop = FALSE]
    names(joint_al) <- c("scenario_id", "article_joint_al_forecast_truth_mae", "article_joint_al_fit_truth_mae")
    old_exal <- article[article$model_id == "joint_exqdesn_rhs_mcmc", c("scenario_id", "mcmc_forecast_truth_mae", "mcmc_fit_truth_mae"), drop = FALSE]
    names(old_exal) <- c("scenario_id", "article_joint_exal_forecast_truth_mae", "article_joint_exal_fit_truth_mae")
    comparison <- merge(comparison, joint_al, by = "scenario_id", all.x = TRUE, sort = FALSE)
    comparison <- merge(comparison, old_exal, by = "scenario_id", all.x = TRUE, sort = FALSE)
    comparison$delta_vs_article_joint_al_forecast_mae <- comparison$mcmc_forecast_truth_mae - comparison$article_joint_al_forecast_truth_mae
    comparison$delta_vs_article_joint_exal_forecast_mae <- comparison$mcmc_forecast_truth_mae - comparison$article_joint_exal_forecast_truth_mae
  }
  gate <- data.frame(
    audit_id = "phase150_case_specific_exal_mcmc_result_audit",
    gate_status = if (any(mcmc_manifest$status != "pass") || any(freeze_manifest$status != "pass") || any(assessment$gate_status == "fail")) "fail" else if (any(assessment$gate_status == "review")) "review" else "pass",
    n_cases = nrow(summary),
    mcmc_manifest_failures = sum(mcmc_manifest$status != "pass"),
    freeze_manifest_failures = sum(freeze_manifest$status != "pass"),
    mcmc_gate_failures = sum(assessment$gate_status == "fail"),
    mcmc_gate_reviews = sum(assessment$gate_status == "review"),
    contract_crossing_pairs = sum(assessment$contract_crossing_pairs, na.rm = TRUE),
    raw_crossing_pairs = sum(assessment$raw_crossing_pairs, na.rm = TRUE),
    scenarios_beating_article_joint_al = if ("delta_vs_article_joint_al_forecast_mae" %in% names(comparison)) sum(comparison$delta_vs_article_joint_al_forecast_mae < 0, na.rm = TRUE) else NA_integer_,
    recommendation = "review_phase150_comparison_before_any_article_promotion",
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase150 MCMC result audit",
    "",
    "This audit compares the Phase150 case-specific Joint exQDESN MCMC confirmation output with the current article balanced MCMC scenario table when available.",
    sprintf("- Gate: `%s`", gate$gate_status[[1L]]),
    sprintf("- Cases: `%s`", gate$n_cases[[1L]]),
    sprintf("- Raw crossing pairs: `%s`", gate$raw_crossing_pairs[[1L]]),
    "",
    "No article assets are updated by this audit."
  ), readme_path, useBytes = TRUE)
  paths <- c(
    phase150_mcmc_manifest_verification = app_joint_qvp_write_csv(mcmc_manifest, file.path(out_dir, "phase150_mcmc_manifest_verification.csv")),
    phase150_freeze_manifest_verification = app_joint_qvp_write_csv(freeze_manifest, file.path(out_dir, "phase150_freeze_manifest_verification.csv")),
    phase150_mcmc_article_comparison = app_joint_qvp_write_csv(comparison, file.path(out_dir, "phase150_mcmc_article_comparison.csv")),
    phase150_mcmc_result_assessment = app_joint_qvp_write_csv(gate, file.path(out_dir, "phase150_mcmc_result_assessment.csv")),
    phase150_case_winner_controls = app_joint_qvp_write_csv(controls, file.path(out_dir, "phase150_case_winner_controls.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(out_dir = normalizePath(out_dir, mustWork = TRUE), assessment = gate, comparison = comparison, paths = c(paths, artifact_manifest = manifest_info$manifest_path))
}
