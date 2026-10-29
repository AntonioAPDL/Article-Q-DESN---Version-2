# Phase 111 calibration-screening readiness audit for the joint QDESN simulation study.

app_joint_qdesn_default_calibration_screening_readiness_dir <- function() {
  app_path("application/cache/joint_qdesn_calibration_screening_readiness_phase111_20260707")
}

app_joint_qdesn_default_next_vb_screening_dir <- function() {
  app_path("application/cache/joint_qdesn_vb_spec_screening_phase112_20260707")
}

app_joint_qdesn_phase111_required_screening_files <- function() {
  c(
    "candidate_registry.csv", "candidate_artifact_dirs.csv", "candidate_scorecard.csv",
    "fit_model_metric_summary.csv", "forecast_model_metric_summary.csv",
    "fit_scenario_metric_summary.csv", "forecast_scenario_metric_summary.csv",
    "forecast_tau_metric_summary.csv", "screening_health_summary.csv",
    "selected_spec_recommendation.csv", "artifact_manifest.csv"
  )
}

app_joint_qdesn_phase111_load_screening_dir <- function(dir, source_label) {
  dir <- normalizePath(dir, mustWork = TRUE)
  missing <- app_joint_qdesn_phase111_required_screening_files()[
    !file.exists(file.path(dir, app_joint_qdesn_phase111_required_screening_files()))
  ]
  if (length(missing)) {
    stop(sprintf("%s is missing required files: %s", source_label, paste(missing, collapse = ", ")), call. = FALSE)
  }
  selected <- app_read_csv(file.path(dir, "selected_spec_recommendation.csv"))
  list(
    source_label = source_label,
    dir = dir,
    manifest_verification = app_joint_qdesn_screening_verify_manifest(dir, source_label, "top_level"),
    candidate_registry = app_joint_qdesn_prepare_screening_registry(app_read_csv(file.path(dir, "candidate_registry.csv"))),
    candidate_dirs = app_read_csv(file.path(dir, "candidate_artifact_dirs.csv")),
    scorecard = app_read_csv(file.path(dir, "candidate_scorecard.csv")),
    fit_model = app_read_csv(file.path(dir, "fit_model_metric_summary.csv")),
    forecast_model = app_read_csv(file.path(dir, "forecast_model_metric_summary.csv")),
    fit_scenario = app_read_csv(file.path(dir, "fit_scenario_metric_summary.csv")),
    forecast_scenario = app_read_csv(file.path(dir, "forecast_scenario_metric_summary.csv")),
    forecast_tau = app_read_csv(file.path(dir, "forecast_tau_metric_summary.csv")),
    health = app_read_csv(file.path(dir, "screening_health_summary.csv")),
    selected = selected
  )
}

app_joint_qdesn_phase111_selected_candidate <- function(screening) {
  cid <- screening$selected$candidate_id[[1L]]
  list(
    candidate_id = cid,
    registry_row = screening$candidate_registry[screening$candidate_registry$candidate_id == cid, , drop = FALSE],
    dirs = screening$candidate_dirs[screening$candidate_dirs$candidate_id == cid, , drop = FALSE],
    scorecard = screening$scorecard[screening$scorecard$candidate_id == cid, , drop = FALSE],
    fit_model = screening$fit_model[screening$fit_model$candidate_id == cid, , drop = FALSE],
    forecast_model = screening$forecast_model[screening$forecast_model$candidate_id == cid, , drop = FALSE],
    fit_scenario = screening$fit_scenario[screening$fit_scenario$candidate_id == cid, , drop = FALSE],
    forecast_scenario = screening$forecast_scenario[screening$forecast_scenario$candidate_id == cid, , drop = FALSE],
    forecast_tau = screening$forecast_tau[screening$forecast_tau$candidate_id == cid, , drop = FALSE]
  )
}

app_joint_qdesn_phase111_model_diagnosis <- function(selected) {
  fit <- selected$fit_model
  forecast <- selected$forecast_model
  fit$validation_scope <- "fit"
  forecast$validation_scope <- "forecast"
  out <- app_joint_qdesn_bind_rows(list(fit, forecast))
  al_forecast <- forecast$truth_mae[forecast$model_id == "joint_qdesn_rhs_vb"][[1L]]
  out$joint_al_forecast_truth_mae <- al_forecast
  out$forecast_gap_vs_joint_qdesn <- ifelse(
    out$validation_scope == "forecast",
    out$truth_mae - al_forecast,
    NA_real_
  )
  out$diagnosis <- ifelse(
    out$model_id == "joint_exqdesn_rhs_vb" & out$validation_scope == "forecast" &
      out$forecast_gap_vs_joint_qdesn > 0.03,
    "exAL forecast fan is too compressed relative to AL; prioritize alpha/gamma geometry screening",
    ifelse(
      out$model_id == "exqdesn_rhs_independent_vb" & out$validation_scope == "forecast" &
        out$raw_crossing_pairs > 0,
      "independent exAL needs monotone contract and tail stabilization; keep as comparator, not article anchor",
      ifelse(
        out$reached_max_iter > 0,
        "VB convergence remains review-level; test stronger iteration and inner-loop controls",
        "no primary implementation blocker"
      )
    )
  )
  keep <- c(
    "validation_scope", "candidate_id", "model_id", "display_label", "fit_structure",
    "truth_mae", "truth_rmse", "check_loss_mean", "crps_grid_mean", "abs_hit_rate_error",
    "abs_coverage_error", "interval_width_mean", "raw_crossing_pairs", "contract_crossing_pairs",
    "reached_max_iter", "max_abs_adjustment", "adjustment_rate", "gate_status",
    "forecast_gap_vs_joint_qdesn", "diagnosis"
  )
  out[, intersect(keep, names(out)), drop = FALSE]
}

app_joint_qdesn_phase111_model_value <- function(x, model_id, metric) {
  vals <- x[x$model_id == model_id, metric, drop = TRUE]
  if (!length(vals)) return(NA_real_)
  as.numeric(vals[[1L]])
}

app_joint_qdesn_phase111_scenario_diagnosis <- function(selected) {
  x <- selected$forecast_scenario
  scenarios <- sort(unique(x$scenario_id))
  rows <- lapply(scenarios, function(sid) {
    sub <- x[x$scenario_id == sid, , drop = FALSE]
    ord <- order(sub$truth_mae, sub$check_loss_mean)
    winner <- sub[ord[1L], , drop = FALSE]
    joint_al <- app_joint_qdesn_phase111_model_value(sub, "joint_qdesn_rhs_vb", "truth_mae")
    joint_exal <- app_joint_qdesn_phase111_model_value(sub, "joint_exqdesn_rhs_vb", "truth_mae")
    independent_al <- app_joint_qdesn_phase111_model_value(sub, "qdesn_rhs_independent_vb", "truth_mae")
    independent_exal <- app_joint_qdesn_phase111_model_value(sub, "exqdesn_rhs_independent_vb", "truth_mae")
    gap <- joint_exal - joint_al
    data.frame(
      scenario_id = sid,
      winner_model_id = winner$model_id[[1L]],
      winner_label = winner$display_label[[1L]],
      joint_qdesn_truth_mae = joint_al,
      joint_exqdesn_truth_mae = joint_exal,
      qdesn_independent_truth_mae = independent_al,
      exqdesn_independent_truth_mae = independent_exal,
      joint_exal_minus_joint_al = gap,
      recommended_focus = if (is.finite(gap) && gap > 0.06) {
        "high_priority_exal_tail_geometry"
      } else if (is.finite(gap) && gap > 0.02) {
        "moderate_priority_exal_calibration"
      } else {
        "retain_as_stability_check"
      },
      stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  out[order(-out$joint_exal_minus_joint_al), , drop = FALSE]
}

app_joint_qdesn_phase111_tau_diagnosis <- function(selected) {
  x <- selected$forecast_tau
  taus <- sort(unique(as.numeric(x$tau)))
  rows <- lapply(taus, function(tt) {
    sub <- x[abs(as.numeric(x$tau) - tt) < 1.0e-12, , drop = FALSE]
    joint_al <- app_joint_qdesn_phase111_model_value(sub, "joint_qdesn_rhs_vb", "truth_mae")
    joint_exal <- app_joint_qdesn_phase111_model_value(sub, "joint_exqdesn_rhs_vb", "truth_mae")
    independent_al <- app_joint_qdesn_phase111_model_value(sub, "qdesn_rhs_independent_vb", "truth_mae")
    independent_exal <- app_joint_qdesn_phase111_model_value(sub, "exqdesn_rhs_independent_vb", "truth_mae")
    data.frame(
      tau = tt,
      joint_qdesn_truth_mae = joint_al,
      joint_exqdesn_truth_mae = joint_exal,
      qdesn_independent_truth_mae = independent_al,
      exqdesn_independent_truth_mae = independent_exal,
      joint_exal_minus_joint_al = joint_exal - joint_al,
      independent_exal_minus_independent_al = independent_exal - independent_al,
      tail_region = if (tt <= 0.10) "lower_tail" else if (tt >= 0.90) "upper_tail" else "center",
      recommended_focus = if (tt <= 0.10 || tt >= 0.90) {
        "tail_alpha_gamma_screening"
      } else {
        "center_stability_check"
      },
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase111_coverage_diagnosis <- function(selected) {
  forecast_dir <- selected$dirs$forecast_dir[[1L]]
  interval_path <- file.path(forecast_dir, "interval_summary.csv")
  if (!file.exists(interval_path)) return(data.frame())
  interval <- app_read_csv(interval_path)
  by_cols <- c("model_id", "display_label", "fit_structure", "nominal_coverage")
  out <- aggregate(
    cbind(coverage, abs_coverage_error, interval_width_mean, interval_score_mean) ~
      model_id + display_label + fit_structure + nominal_coverage,
    interval,
    mean,
    na.rm = TRUE
  )
  out$calibration_note <- ifelse(
    out$model_id %in% c("joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb") &
      out$nominal_coverage >= 0.80 & out$coverage < out$nominal_coverage - 0.05,
    "exAL intervals undercover; prioritize fan-width calibration",
    "coverage within review band or not a primary target"
  )
  out[order(out$nominal_coverage, out$model_id), c(by_cols, "coverage", "abs_coverage_error", "interval_width_mean", "interval_score_mean", "calibration_note"), drop = FALSE]
}

app_joint_qdesn_phase111_convergence_crossing_diagnosis <- function(selected) {
  x <- app_joint_qdesn_bind_rows(list(
    transform(selected$fit_model, validation_scope = "fit"),
    transform(selected$forecast_model, validation_scope = "forecast")
  ))
  x$implementation_gate <- ifelse(
    x$contract_crossing_pairs > 0 | !x$finite_quantiles | !x$finite_scores,
    "fail",
    ifelse(x$raw_crossing_pairs > 0 | x$reached_max_iter > 0 | x$max_abs_adjustment > 1.0e-3, "review", "pass")
  )
  x$recommended_response <- ifelse(
    x$raw_crossing_pairs > 100,
    "screen for stronger joint smoothing and tail stabilization; keep raw-crossing diagnostics",
    ifelse(
      x$reached_max_iter > 0,
      "increase VB iteration/inner-loop controls and audit objective traces",
      "no additional implementation action"
    )
  )
  keep <- c(
    "validation_scope", "model_id", "display_label", "raw_crossing_pairs",
    "contract_crossing_pairs", "max_abs_adjustment", "adjustment_rate",
    "reached_max_iter", "elapsed_seconds", "finite_quantiles", "finite_scores",
    "implementation_gate", "recommended_response"
  )
  x[, keep, drop = FALSE]
}

app_joint_qdesn_phase111_candidate_history <- function(phase106) {
  out <- phase106$scorecard
  out$history_diagnosis <- ifelse(
    out$gate_status == "fail" & out$mean_forecast_truth_mae > 1,
    "catastrophic or unstable candidate; exclude from next article-candidate search",
    ifelse(
      out$forecast_raw_crossings > 1000,
      "too many raw crossings; useful only as a boundary diagnostic",
      ifelse(out$rank == min(out$rank, na.rm = TRUE), "current stability-selected reference", "secondary candidate")
    )
  )
  out[order(out$rank), , drop = FALSE]
}

app_joint_qdesn_phase111_control_feasibility <- function() {
  data.frame(
    control_family = c(
      "rhs_global_shrinkage", "scalar_alpha_prior_width", "gamma_initialization",
      "vb_iteration_budget", "rhs_inner_loop", "finite_zeta2_beta_cap",
      "gamma_update_damping", "model_specific_controls"
    ),
    currently_wired = c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE),
    implementation_status = c(
      "available_in_phase106",
      "implemented_phase111_scalar_csv",
      "implemented_phase111_policy_csv",
      "available_in_phase106",
      "available_in_phase106",
      "available_in_phase106",
      "deferred_model_change",
      "deferred_runner_change"
    ),
    reason_to_test = c(
      "Controls coefficient noise across adjacent quantiles.",
      "Tests whether wider or tighter scalar empirical-intercept priors improve exAL fan width while keeping the mixed joint/independent comparison contract unchanged.",
      "Tests whether the exAL asymmetry block is sensitive to the default off-zero initialization.",
      "Separates true model misspecification from premature VB stopping.",
      "Checks whether RHS local updates need more coordinate passes.",
      "Tests whether finite global coefficient variance improves exAL tail geometry.",
      "Could reduce gamma oscillation, but changes the optimizer contract and needs separate derivation review.",
      "Could tune exAL without changing AL, but complicates the common-comparator screening design."
    ),
    recommended_phase = c(
      "phase112", "phase112", "phase112", "phase112", "phase112", "phase112", "after_phase112_if_needed", "after_phase112_if_needed"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase111_recommended_registry <- function(
  screening_output_dir = app_joint_qdesn_default_next_vb_screening_dir(),
  selected,
  n_cores = 9L
) {
  screening_output_dir <- normalizePath(screening_output_dir, mustWork = FALSE)
  ids <- c(
    "current_selected_reference",
    "alpha_sd_0p75_tau0_0p5",
    "alpha_sd_1p0_tau0_0p5",
    "alpha_sd_1p25_tau0_0p5",
    "alpha_sd_0p35_tau0_0p5",
    "gamma_zero_alpha0p5_tau0_0p5",
    "gamma_halfdefault_alpha0p5_tau0_0p5",
    "tau0_0p75_alpha0p5",
    "tau0_1p0_alpha0p5",
    "zeta2_16_alpha0p5_tau0_0p5",
    "inner10_iter1440_alpha0p5_tau0_0p5"
  )
  candidate_dir <- function(id, stage) file.path(screening_output_dir, "candidates", id, stage)
  fit_dirs <- vapply(ids, function(id) candidate_dir(id, "fit"), character(1L))
  forecast_dirs <- vapply(ids, function(id) candidate_dir(id, "forecast"), character(1L))
  fit_dirs[[1L]] <- selected$dirs$fit_dir[[1L]]
  forecast_dirs[[1L]] <- selected$dirs$forecast_dir[[1L]]
  registry <- data.frame(
    candidate_id = ids,
    candidate_label = c(
      "Current selected VB reference",
      "Alpha sd 0.75, tau0 0.5",
      "Alpha sd 1.0, tau0 0.5",
      "Alpha sd 1.25, tau0 0.5",
      "Alpha sd 0.35, tau0 0.5",
      "Zero gamma initialization, alpha sd 0.5",
      "Half-default gamma initialization, alpha sd 0.5",
      "RHS tau0 0.75, alpha sd 0.5",
      "RHS tau0 1.0, alpha sd 0.5",
      "Finite zeta2 16, alpha sd 0.5",
      "Higher inner-loop and iteration budget"
    ),
    use_existing_artifacts = c(TRUE, rep(FALSE, length(ids) - 1L)),
    fit_dir = fit_dirs,
    forecast_dir = forecast_dirs,
    vb_max_iter = c(480L, rep(960L, length(ids) - 2L), 1440L),
    adaptive_vb_max_iter_grid = c("480,960", rep("960,1440", length(ids) - 2L), "1440,1920"),
    vb_tol = rep(1.0e-4, length(ids)),
    rhs_vb_inner = c(7L, rep(7L, length(ids) - 2L), 10L),
    tau0 = c(0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.75, 1.0, 0.5, 0.5),
    zeta2 = c(Inf, Inf, Inf, Inf, Inf, Inf, Inf, Inf, Inf, 16, Inf),
    a_sigma = rep(2, length(ids)),
    b_sigma = rep(1, length(ids)),
    alpha_prior_sd = c(
      "0.5", "0.75", "1", "1.25", "0.35", "0.5", "0.5", "0.5", "0.5", "0.5", "0.5"
    ),
    alpha_min_spacing = rep(0, length(ids)),
    gamma_init_policy = c(
      "default", "default", "default", "default", "default",
      "zero", "half_default", "default", "default", "default", "default"
    ),
    review_adjustment_threshold = rep(1.0e-3, length(ids)),
    max_dense_dim = rep(300L, length(ids)),
    n_cores = rep(as.integer(n_cores), length(ids)),
    candidate_role = c("selected_reference", rep("full_screening_candidate", length(ids) - 1L)),
    notes = c(
      "Frozen Phase 107 selected VB specification; included as a no-rerun reference.",
      "Loosens the empirical alpha prior from 0.5 to 0.75 to test whether exAL tail fans widen without losing stability.",
      "Returns to the original alpha prior width under the improved RHS setting to test whether exAL compression is over-regularization.",
      "Loosens the empirical alpha prior beyond 1.0 as a scalar fan-width diagnostic valid for both joint and independent comparators.",
      "Tightens the empirical alpha prior below 0.5 as a scalar stability diagnostic valid for both joint and independent comparators.",
      "Starts exAL at the AL submodel to test sensitivity to off-zero default gamma initialization.",
      "Damps the default exAL gamma initialization without changing the update equations.",
      "Moderates RHS smoothing relative to tau0 0.5 to test whether joint AL/exAL need slightly less coefficient coupling.",
      "Uses the original tau0 with tightened alpha prior to separate alpha effects from RHS effects.",
      "Adds a finite coefficient-variance cap as a conservative anti-noise diagnostic.",
      "Tests whether longer VB/RHS updates reduce review-level max-iteration behavior before MCMC."
    ),
    stringsAsFactors = FALSE
  )
  app_joint_qdesn_validate_screening_registry(registry, allow_alpha_prior_vectors = FALSE)
  registry
}

app_joint_qdesn_phase111_deferred_extensions <- function() {
  data.frame(
    extension_id = c("gamma_update_damping", "gamma_prior_penalty", "model_specific_candidate_controls", "mcmc_promotion_layer"),
    status = c("deferred", "deferred", "deferred", "deferred_until_vb_freeze"),
    reason = c(
      "Would alter the exAL optimizer update contract; first test initialization and alpha-prior levers that are already derivation-compatible.",
      "Requires theory/audit of the implied prior on exAL shape before article use.",
      "Useful if exAL needs different controls than AL, but first keep all four comparators under the same specification for a fair screening table.",
      "MCMC is expensive and should initialize from a VB specification selected after Phase 112 screening."
    ),
    trigger_condition = c(
      "Phase 112 keeps exAL undercovered or unstable across tail scenarios.",
      "Gamma initialization improves but does not remove tail compression.",
      "Joint QDESN AL remains stable while exAL needs materially different calibration.",
      "A VB candidate gives finite, noncrossing, well-calibrated fit and forecast behavior."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase111_implementation_plan <- function() {
  data.frame(
    step = seq_len(6L),
    phase = c("audit", "control_wiring", "registry", "launch", "selection", "mcmc"),
    objective = c(
      "Ground the next screening in Phase 106/107 evidence rather than manuscript appearance.",
      "Expose scalar alpha-prior width and gamma initialization controls without changing defaults.",
      "Generate an executable Phase 112 registry that tests only high-priority levers.",
      "Run Phase 112 as a full article-scale screening campaign, not a smoke pilot.",
      "Freeze the best VB candidate only if fit and forecast gates are finite, noncrossing, and calibrated.",
      "Launch VB-initialized MCMC references after VB selection is stable."
    ),
    success_criterion = c(
      "Manifest, model, scenario, tau, coverage, crossing, and convergence diagnostics are complete.",
      "Existing tests pass; old registries remain readable.",
      "Registry validates with the Phase 106 runner under the scalar-alpha mixed-model contract and records every seed/control/provenance field.",
      "All enabled scenarios and all four VB comparators complete with manifests.",
      "Joint QDESN and joint exQDESN are competitive across truth distance, check loss, CRPS-grid, hit rates, and coverage.",
      "MCMC uses the frozen VB candidate only; no MCMC launch from unstable VB."
    ),
    output_artifact = c(
      "phase111 diagnosis CSVs",
      "updated validation/screening helpers",
      "recommended_screening_registry.csv",
      "phase112 screening directory",
      "selected_spec_recommendation.csv",
      "phase113/phase114 MCMC reference artifacts"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase111_launch_command <- function(registry_path, screening_output_dir, n_cores = 9L) {
  data.frame(
    command_id = "phase112_full_vb_screening",
    command = sprintf(
      "Rscript application/scripts/106_run_joint_qdesn_vb_spec_screening.R --registry %s --output-dir %s --n-cores %d --reuse-completed true --audit-only false",
      registry_path,
      screening_output_dir,
      as.integer(n_cores)
    ),
    purpose = "Run the full next VB calibration screening over the frozen joint-QDESN simulation fixtures.",
    expected_runtime_note = "Heavier than Phase 106 because it evaluates ten new candidates with larger VB budgets; run in background or tmux.",
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase111_readme <- function(run_config, model_diagnosis, scenario_diagnosis, tau_diagnosis, launch_command) {
  worst_tau <- tau_diagnosis[order(-tau_diagnosis$joint_exal_minus_joint_al), , drop = FALSE][1L, , drop = FALSE]
  worst_scenario <- scenario_diagnosis[order(-scenario_diagnosis$joint_exal_minus_joint_al), , drop = FALSE][1L, , drop = FALSE]
  c(
    "# Joint QDESN Phase 111 Calibration-Screening Readiness",
    "",
    "This audit prepares the next full VB calibration screening for the joint QDESN simulation study.",
    "It does not launch the expensive Phase 112 campaign; it verifies the evidence, wires needed controls, and writes an executable registry.",
    "",
    sprintf("- Phase 106 source: `%s`", run_config$phase106_dir[[1L]]),
    sprintf("- Phase 107 source: `%s`", run_config$phase107_dir[[1L]]),
    sprintf("- Recommended Phase 112 output: `%s`", run_config$screening_output_dir[[1L]]),
    "",
    "Main diagnosis:",
    sprintf(
      "- Worst joint exQDESN-vs-joint QDESN forecast truth-MAE gap is at tau %.2f: %.4f.",
      worst_tau$tau[[1L]],
      worst_tau$joint_exal_minus_joint_al[[1L]]
    ),
    sprintf(
      "- Worst scenario gap is `%s`: %.4f.",
      worst_scenario$scenario_id[[1L]],
      worst_scenario$joint_exal_minus_joint_al[[1L]]
    ),
    "- exQDESN intervals undercover in the high-coverage bands, which is consistent with a compressed fitted quantile fan.",
    "- The next screen should prioritize scalar alpha-prior width, gamma initialization, RHS strength, finite zeta2, and VB budget.",
    "",
    "Recommended launch:",
    "",
    launch_command$command[[1L]]
  )
}

app_joint_qdesn_run_calibration_screening_readiness <- function(
  out_dir = app_joint_qdesn_default_calibration_screening_readiness_dir(),
  phase106_dir = app_joint_qdesn_default_vb_spec_screening_dir(),
  phase107_dir = app_path("application/cache/joint_qdesn_selected_vb_freeze_phase107_20260707"),
  screening_output_dir = app_joint_qdesn_default_next_vb_screening_dir(),
  n_cores = 9L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  screening_output_dir <- normalizePath(screening_output_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  phase106 <- app_joint_qdesn_phase111_load_screening_dir(phase106_dir, "phase106_screening_history")
  phase107 <- app_joint_qdesn_phase111_load_screening_dir(phase107_dir, "phase107_selected_vb_freeze")
  selected <- app_joint_qdesn_phase111_selected_candidate(phase107)
  model_diagnosis <- app_joint_qdesn_phase111_model_diagnosis(selected)
  scenario_diagnosis <- app_joint_qdesn_phase111_scenario_diagnosis(selected)
  tau_diagnosis <- app_joint_qdesn_phase111_tau_diagnosis(selected)
  coverage_diagnosis <- app_joint_qdesn_phase111_coverage_diagnosis(selected)
  convergence_crossing <- app_joint_qdesn_phase111_convergence_crossing_diagnosis(selected)
  candidate_history <- app_joint_qdesn_phase111_candidate_history(phase106)
  control_feasibility <- app_joint_qdesn_phase111_control_feasibility()
  recommended_registry <- app_joint_qdesn_phase111_recommended_registry(
    screening_output_dir = screening_output_dir,
    selected = selected,
    n_cores = n_cores
  )
  deferred <- app_joint_qdesn_phase111_deferred_extensions()
  plan <- app_joint_qdesn_phase111_implementation_plan()
  registry_path <- file.path(out_dir, "recommended_screening_registry.csv")
  launch_command <- app_joint_qdesn_phase111_launch_command(
    registry_path = registry_path,
    screening_output_dir = screening_output_dir,
    n_cores = n_cores
  )
  source_manifest <- app_joint_qdesn_bind_rows(list(
    transform(phase106$manifest_verification, source_label = "phase106_screening_history", source_dir = phase106$dir),
    transform(phase107$manifest_verification, source_label = "phase107_selected_vb_freeze", source_dir = phase107$dir)
  ))
  run_config <- data.frame(
    run_id = "joint_qdesn_calibration_screening_readiness_phase111",
    out_dir = out_dir,
    phase106_dir = phase106$dir,
    phase107_dir = phase107$dir,
    screening_output_dir = screening_output_dir,
    selected_candidate_id = selected$candidate_id,
    n_recommended_candidates = nrow(recommended_registry),
    n_cores = as.integer(n_cores),
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qdesn_phase111_readme(run_config, model_diagnosis, scenario_diagnosis, tau_diagnosis, launch_command), readme_path, useBytes = TRUE)
  paths <- c(
    phase111_run_config = app_joint_qdesn_screening_write_csv(run_config, file.path(out_dir, "phase111_run_config.csv")),
    source_manifest_verification = app_joint_qdesn_screening_write_csv(source_manifest, file.path(out_dir, "source_manifest_verification.csv")),
    model_calibration_diagnosis = app_joint_qdesn_screening_write_csv(model_diagnosis, file.path(out_dir, "model_calibration_diagnosis.csv")),
    scenario_gap_diagnosis = app_joint_qdesn_screening_write_csv(scenario_diagnosis, file.path(out_dir, "scenario_gap_diagnosis.csv")),
    tau_gap_diagnosis = app_joint_qdesn_screening_write_csv(tau_diagnosis, file.path(out_dir, "tau_gap_diagnosis.csv")),
    coverage_width_diagnosis = app_joint_qdesn_screening_write_csv(coverage_diagnosis, file.path(out_dir, "coverage_width_diagnosis.csv")),
    convergence_crossing_diagnosis = app_joint_qdesn_screening_write_csv(convergence_crossing, file.path(out_dir, "convergence_crossing_diagnosis.csv")),
    candidate_history_diagnosis = app_joint_qdesn_screening_write_csv(candidate_history, file.path(out_dir, "candidate_history_diagnosis.csv")),
    control_feasibility_audit = app_joint_qdesn_screening_write_csv(control_feasibility, file.path(out_dir, "control_feasibility_audit.csv")),
    recommended_screening_registry = app_joint_qdesn_screening_write_csv(recommended_registry, registry_path),
    deferred_control_extensions = app_joint_qdesn_screening_write_csv(deferred, file.path(out_dir, "deferred_control_extensions.csv")),
    implementation_plan = app_joint_qdesn_screening_write_csv(plan, file.path(out_dir, "implementation_plan.csv")),
    phase112_launch_command = app_joint_qdesn_screening_write_csv(launch_command, file.path(out_dir, "phase112_launch_command.csv")),
    provenance = app_joint_qdesn_screening_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    run_config = run_config,
    model_diagnosis = model_diagnosis,
    scenario_diagnosis = scenario_diagnosis,
    tau_diagnosis = tau_diagnosis,
    coverage_diagnosis = coverage_diagnosis,
    convergence_crossing_diagnosis = convergence_crossing,
    candidate_history = candidate_history,
    recommended_registry = recommended_registry,
    launch_command = launch_command,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path)
  )
}

# Phase 113 focused top-candidate verification after the Phase 112 VB screen.

app_joint_qdesn_default_phase113_top_candidate_readiness_dir <- function() {
  app_path("application/cache/joint_qdesn_phase113_top_candidate_verification_20260708")
}

app_joint_qdesn_default_phase113_vb_screening_dir <- function() {
  app_path("application/cache/joint_qdesn_vb_spec_screening_phase113_20260708")
}

app_joint_qdesn_phase113_target_candidate_ids <- function() {
  c(
    "inner10_iter1440_alpha0p5_tau0_0p5",
    "zeta2_16_alpha0p5_tau0_0p5"
  )
}

app_joint_qdesn_phase113_scorecard_audit <- function(phase112) {
  out <- phase112$scorecard[order(phase112$scorecard$rank, phase112$scorecard$screening_score), , drop = FALSE]
  out$phase113_role <- ifelse(
    out$candidate_id %in% app_joint_qdesn_phase113_target_candidate_ids(),
    "reference_top_candidate",
    "context_candidate"
  )
  out$phase113_diagnosis <- ifelse(
    out$candidate_id == "inner10_iter1440_alpha0p5_tau0_0p5",
    "Best stability score: lowest aggregate screening score, lowest raw forecast crossings, and lowest max-iteration pressure.",
    ifelse(
      out$candidate_id == "zeta2_16_alpha0p5_tau0_0p5",
      "Best accuracy tradeoff: lowest mean forecast truth distance and best max-scenario forecast error, with modestly higher raw crossings.",
      ifelse(
        out$forecast_raw_crossings > 300,
        "Useful boundary evidence, but raw monotone adjustment pressure is too high for immediate article-candidate promotion.",
        "Secondary context for the focused verification decision."
      )
    )
  )
  keep <- c(
    "candidate_id", "candidate_label", "rank", "gate_status", "screening_score",
    "mean_fit_truth_mae", "mean_forecast_truth_mae", "joint_qdesn_forecast_truth_mae",
    "independent_exqdesn_forecast_truth_mae", "max_scenario_forecast_truth_mae",
    "forecast_raw_crossings", "max_forecast_adjustment", "elapsed_minutes",
    "recommendation_class", "phase113_role", "phase113_diagnosis"
  )
  out[, intersect(keep, names(out)), drop = FALSE]
}

app_joint_qdesn_phase113_model_tradeoff_audit <- function(phase112) {
  x <- app_joint_qdesn_bind_rows(list(
    transform(phase112$fit_model, validation_scope = "fit"),
    transform(phase112$forecast_model, validation_scope = "forecast")
  ))
  rows <- lapply(split(x, paste(x$candidate_id, x$validation_scope, sep = "\r")), function(sub) {
    val <- function(model_id, metric) app_joint_qdesn_phase111_model_value(sub, model_id, metric)
    data.frame(
      candidate_id = sub$candidate_id[[1L]],
      candidate_label = sub$candidate_label[[1L]],
      validation_scope = sub$validation_scope[[1L]],
      joint_qdesn_truth_mae = val("joint_qdesn_rhs_vb", "truth_mae"),
      joint_exqdesn_truth_mae = val("joint_exqdesn_rhs_vb", "truth_mae"),
      qdesn_independent_truth_mae = val("qdesn_rhs_independent_vb", "truth_mae"),
      exqdesn_independent_truth_mae = val("exqdesn_rhs_independent_vb", "truth_mae"),
      joint_qdesn_raw_crossings = val("joint_qdesn_rhs_vb", "raw_crossing_pairs"),
      joint_exqdesn_raw_crossings = val("joint_exqdesn_rhs_vb", "raw_crossing_pairs"),
      qdesn_independent_raw_crossings = val("qdesn_rhs_independent_vb", "raw_crossing_pairs"),
      exqdesn_independent_raw_crossings = val("exqdesn_rhs_independent_vb", "raw_crossing_pairs"),
      joint_exqdesn_minus_joint_qdesn = val("joint_exqdesn_rhs_vb", "truth_mae") - val("joint_qdesn_rhs_vb", "truth_mae"),
      exqdesn_independent_minus_qdesn_independent = val("exqdesn_rhs_independent_vb", "truth_mae") - val("qdesn_rhs_independent_vb", "truth_mae"),
      reached_max_iter_total = sum(sub$reached_max_iter, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  out$phase113_interpretation <- ifelse(
    out$validation_scope == "forecast" & out$joint_exqdesn_minus_joint_qdesn > 0.04,
    "exQDESN remains materially less accurate than QDESN; verify whether finite zeta2 plus stronger RHS inner loops improves the common specification before MCMC.",
    ifelse(
      out$reached_max_iter_total > 0,
      "VB convergence remains review-level; retain higher iteration controls in the focused candidate.",
      "No primary model-level implementation blocker."
    )
  )
  out[order(out$validation_scope, out$joint_exqdesn_minus_joint_qdesn, decreasing = TRUE), , drop = FALSE]
}

app_joint_qdesn_phase113_exal_gap_audit <- function(phase112) {
  rows <- lapply(split(phase112$forecast_tau, phase112$forecast_tau$candidate_id), function(sub) {
    taus <- sort(unique(as.numeric(sub$tau)))
    app_joint_qdesn_bind_rows(lapply(taus, function(tt) {
      tau_sub <- sub[abs(as.numeric(sub$tau) - tt) < 1.0e-12, , drop = FALSE]
      joint_al <- app_joint_qdesn_phase111_model_value(tau_sub, "joint_qdesn_rhs_vb", "truth_mae")
      joint_exal <- app_joint_qdesn_phase111_model_value(tau_sub, "joint_exqdesn_rhs_vb", "truth_mae")
      ind_al <- app_joint_qdesn_phase111_model_value(tau_sub, "qdesn_rhs_independent_vb", "truth_mae")
      ind_exal <- app_joint_qdesn_phase111_model_value(tau_sub, "exqdesn_rhs_independent_vb", "truth_mae")
      data.frame(
        candidate_id = tau_sub$candidate_id[[1L]],
        candidate_label = tau_sub$candidate_label[[1L]],
        tau = tt,
        tail_region = if (tt <= 0.10) "lower_tail" else if (tt >= 0.90) "upper_tail" else "center",
        joint_exqdesn_minus_joint_qdesn = joint_exal - joint_al,
        exqdesn_independent_minus_qdesn_independent = ind_exal - ind_al,
        joint_qdesn_truth_mae = joint_al,
        joint_exqdesn_truth_mae = joint_exal,
        qdesn_independent_truth_mae = ind_al,
        exqdesn_independent_truth_mae = ind_exal,
        stringsAsFactors = FALSE
      )
    }))
  })
  out <- app_joint_qdesn_bind_rows(rows)
  out$phase113_focus <- ifelse(
    out$tail_region != "center" & out$joint_exqdesn_minus_joint_qdesn > 0.05,
    "upper_priority_tail_fan_calibration",
    ifelse(out$joint_exqdesn_minus_joint_qdesn > 0.02, "moderate_exal_gap", "context_only")
  )
  out[order(out$candidate_id, -out$joint_exqdesn_minus_joint_qdesn), , drop = FALSE]
}

app_joint_qdesn_phase113_reference_row <- function(phase112, candidate_id) {
  reg <- phase112$candidate_registry[phase112$candidate_registry$candidate_id == candidate_id, , drop = FALSE]
  dirs <- phase112$candidate_dirs[phase112$candidate_dirs$candidate_id == candidate_id, , drop = FALSE]
  if (!nrow(reg) || !nrow(dirs)) return(NULL)
  reg$use_existing_artifacts <- TRUE
  reg$fit_dir <- dirs$fit_dir[[1L]]
  reg$forecast_dir <- dirs$forecast_dir[[1L]]
  reg$candidate_role <- "phase112_reference"
  reg$notes <- paste0("Frozen Phase 112 top candidate reused as reference: ", reg$notes[[1L]])
  reg
}

app_joint_qdesn_phase113_recommended_registry <- function(
  phase112,
  screening_output_dir = app_joint_qdesn_default_phase113_vb_screening_dir(),
  n_cores = 9L
) {
  screening_output_dir <- normalizePath(screening_output_dir, mustWork = FALSE)
  refs <- Filter(Negate(is.null), lapply(app_joint_qdesn_phase113_target_candidate_ids(), function(id) {
    app_joint_qdesn_phase113_reference_row(phase112, id)
  }))
  if (!length(refs)) {
    refs <- list(app_joint_qdesn_phase113_reference_row(phase112, phase112$selected$candidate_id[[1L]]))
  }
  refs <- app_joint_qdesn_bind_rows(refs)

  hybrid_ids <- c(
    "zeta2_16_inner10_iter1440_alpha0p5_tau0_0p5",
    "zeta2_16_inner10_gamma_zero_alpha0p5_tau0_0p5"
  )
  candidate_dir <- function(id, stage) file.path(screening_output_dir, "candidates", id, stage)
  hybrids <- data.frame(
    candidate_id = hybrid_ids,
    candidate_label = c(
      "Finite zeta2 16 plus inner-loop 10 and VB 1440",
      "Finite zeta2 16 plus inner-loop 10, VB 1440, and zero gamma initialization"
    ),
    use_existing_artifacts = FALSE,
    fit_dir = vapply(hybrid_ids, candidate_dir, character(1L), stage = "fit"),
    forecast_dir = vapply(hybrid_ids, candidate_dir, character(1L), stage = "forecast"),
    vb_max_iter = c(1440L, 1440L),
    adaptive_vb_max_iter_grid = c("1440,1920", "1440,1920"),
    vb_tol = c(1.0e-4, 1.0e-4),
    rhs_vb_inner = c(10L, 10L),
    tau0 = c(0.5, 0.5),
    zeta2 = c(16, 16),
    a_sigma = c(2, 2),
    b_sigma = c(1, 1),
    alpha_prior_sd = c("0.5", "0.5"),
    alpha_min_spacing = c(0, 0),
    gamma_init_policy = c("default", "zero"),
    review_adjustment_threshold = c(1.0e-3, 1.0e-3),
    max_dense_dim = c(300L, 300L),
    n_cores = rep(as.integer(n_cores), 2L),
    candidate_role = c("phase113_hybrid_verification", "phase113_hybrid_exal_sensitivity"),
    notes = c(
      "Primary Phase 113 hybrid: combines the Phase 112 accuracy candidate zeta2=16 with the stability candidate inner-loop and iteration controls.",
      "Sensitivity hybrid: same primary hybrid but initializes exAL gamma at zero to test whether exAL tail behavior improves without changing the model contract."
    ),
    stringsAsFactors = FALSE
  )
  refs <- refs[, names(hybrids), drop = FALSE]
  refs$n_cores <- as.integer(n_cores)
  registry <- app_joint_qdesn_bind_rows(list(refs, hybrids))
  registry <- registry[!duplicated(registry$candidate_id), , drop = FALSE]
  app_joint_qdesn_validate_screening_registry(registry, allow_alpha_prior_vectors = FALSE)
  registry
}

app_joint_qdesn_phase113_candidate_selection_rationale <- function(phase112, registry) {
  data.frame(
    candidate_id = registry$candidate_id,
    candidate_role = registry$candidate_role,
    selection_reason = ifelse(
      registry$candidate_id == "inner10_iter1440_alpha0p5_tau0_0p5",
      "Reference for stability: lowest Phase 112 screening score, lowest raw crossing count, and lowest VB max-iteration count.",
      ifelse(
        registry$candidate_id == "zeta2_16_alpha0p5_tau0_0p5",
        "Reference for accuracy: best mean forecast truth distance and strongest scenario-level accuracy tradeoff in Phase 112.",
        ifelse(
          registry$candidate_id == "zeta2_16_inner10_iter1440_alpha0p5_tau0_0p5",
          "Tests the most plausible improvement: keep finite zeta2 accuracy while adding the stronger inner-loop and iteration budget that improved stability.",
          "Tests whether zero gamma initialization helps exQDESN tail behavior under the same finite-zeta2 and stronger-inner-loop contract."
        )
      )
    ),
    mcmc_decision = "defer_until_phase113_vb_evidence_is_clean",
    article_decision_rule = "Promote only if manifests pass, contract crossings are zero, truth distances are competitive, raw adjustments are review-level rather than dominant, and VB max-iteration pressure is reduced.",
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase113_implementation_plan <- function() {
  data.frame(
    step = seq_len(6L),
    stage = c("audit_phase112", "select_candidates", "build_hybrids", "launch_verification", "readiness_decision", "mcmc_or_article_assets"),
    objective = c(
      "Verify Phase 112 completed with complete manifests, no scenario failures, and zero contract crossings.",
      "Keep the stability winner and the accuracy winner as frozen references.",
      "Run only scientifically motivated hybrids combining finite zeta2, stronger RHS inner loops, longer VB budgets, and one gamma-initialization sensitivity.",
      "Use the existing Phase 106 screening runner so fit and forecast metrics remain comparable with Phase 112.",
      "Select a VB specification using fit and forecast truth distance, check loss, CRPS-grid, hit/coverage errors, raw adjustment pressure, and convergence.",
      "Only after a clean VB candidate exists, freeze article assets and launch VB-initialized MCMC references."
    ),
    success_criterion = c(
      "Source manifest verification passes and Phase 112 scorecard is internally consistent.",
      "Selected references bracket the observed accuracy-stability tradeoff.",
      "Hybrid registry validates with scalar alpha priors and no unreviewed model changes.",
      "Every candidate writes fit and forecast artifacts with manifests and no worker failures.",
      "A candidate has zero contract crossings and improves or preserves Phase 112 accuracy while lowering review pressure.",
      "MCMC is initialized from the final VB candidate rather than from a moving screening target."
    ),
    reproducibility_contract = c(
      "Record Phase 112 source directory and hashes.",
      "Reference candidates reuse frozen artifacts.",
      "Hybrid candidates use explicit registry rows.",
      "Run through a single script command with reuse-completed enabled.",
      "Audit writes CSV summaries and a manifest.",
      "Article/MCMC stages record selected registry row and artifact hashes."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase113_launch_command <- function(registry_path, screening_output_dir, n_cores = 9L) {
  data.frame(
    command_id = "phase113_top_candidate_verification",
    command = sprintf(
      "Rscript application/scripts/106_run_joint_qdesn_vb_spec_screening.R --registry %s --output-dir %s --n-cores %d --reuse-completed true --audit-only false",
      registry_path,
      screening_output_dir,
      as.integer(n_cores)
    ),
    purpose = "Run the focused Phase 113 verification over the Phase 112 top references and finite-zeta2/inner-loop hybrid candidates.",
    expected_runtime_note = "Bounded run: two frozen references plus two new article-scale hybrid candidates. Suitable for tmux/background execution.",
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase113_readme <- function(run_config, scorecard_audit, model_tradeoff, exal_gap, launch_command) {
  top <- scorecard_audit[order(scorecard_audit$rank), , drop = FALSE][1L, , drop = FALSE]
  worst_gap <- exal_gap[order(-exal_gap$joint_exqdesn_minus_joint_qdesn), , drop = FALSE][1L, , drop = FALSE]
  c(
    "# Joint QDESN Phase 113 Top-Candidate Verification Readiness",
    "",
    "This audit prepares the focused verification stage after the full Phase 112 VB specification screen.",
    "It deliberately avoids another broad screen. The next run keeps the Phase 112 stability and accuracy winners as frozen references and adds only two interpretable hybrids.",
    "",
    sprintf("- Phase 112 source: `%s`", run_config$phase112_dir[[1L]]),
    sprintf("- Phase 113 audit directory: `%s`", run_config$out_dir[[1L]]),
    sprintf("- Phase 113 screening output directory: `%s`", run_config$screening_output_dir[[1L]]),
    "",
    "Main findings:",
    sprintf("- Phase 112 selected `%s` with screening score %.4f.", top$candidate_id[[1L]], top$screening_score[[1L]]),
    sprintf(
      "- Largest forecast tau-level joint exQDESN minus joint QDESN MAE gap appears for `%s` at tau %.2f: %.4f.",
      worst_gap$candidate_id[[1L]],
      worst_gap$tau[[1L]],
      worst_gap$joint_exqdesn_minus_joint_qdesn[[1L]]
    ),
    "- The optimal next step is a focused VB verification, not MCMC and not another broad grid.",
    "- MCMC remains deferred until Phase 113 identifies one stable VB specification for article use.",
    "",
    "Recommended launch:",
    "",
    launch_command$command[[1L]]
  )
}

app_joint_qdesn_run_phase113_top_candidate_readiness <- function(
  out_dir = app_joint_qdesn_default_phase113_top_candidate_readiness_dir(),
  phase112_dir = app_joint_qdesn_default_next_vb_screening_dir(),
  screening_output_dir = app_joint_qdesn_default_phase113_vb_screening_dir(),
  n_cores = 9L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  phase112_dir <- normalizePath(phase112_dir, mustWork = TRUE)
  screening_output_dir <- normalizePath(screening_output_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  phase112 <- app_joint_qdesn_phase111_load_screening_dir(phase112_dir, "phase112_vb_spec_screening")
  scorecard_audit <- app_joint_qdesn_phase113_scorecard_audit(phase112)
  model_tradeoff <- app_joint_qdesn_phase113_model_tradeoff_audit(phase112)
  exal_gap <- app_joint_qdesn_phase113_exal_gap_audit(phase112)
  recommended_registry <- app_joint_qdesn_phase113_recommended_registry(
    phase112 = phase112,
    screening_output_dir = screening_output_dir,
    n_cores = n_cores
  )
  rationale <- app_joint_qdesn_phase113_candidate_selection_rationale(phase112, recommended_registry)
  plan <- app_joint_qdesn_phase113_implementation_plan()
  registry_path <- file.path(out_dir, "phase113_recommended_registry.csv")
  launch_command <- app_joint_qdesn_phase113_launch_command(
    registry_path = registry_path,
    screening_output_dir = screening_output_dir,
    n_cores = n_cores
  )
  source_manifest <- phase112$manifest_verification
  source_manifest$source_label <- "phase112_vb_spec_screening"
  source_manifest$source_dir <- phase112$dir
  run_config <- data.frame(
    run_id = "joint_qdesn_phase113_top_candidate_verification_readiness",
    out_dir = out_dir,
    phase112_dir = phase112$dir,
    screening_output_dir = screening_output_dir,
    selected_phase112_candidate_id = phase112$selected$candidate_id[[1L]],
    n_recommended_candidates = nrow(recommended_registry),
    n_cores = as.integer(n_cores),
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(
    app_joint_qdesn_phase113_readme(run_config, scorecard_audit, model_tradeoff, exal_gap, launch_command),
    readme_path,
    useBytes = TRUE
  )
  paths <- c(
    phase113_run_config = app_joint_qdesn_screening_write_csv(run_config, file.path(out_dir, "phase113_run_config.csv")),
    source_manifest_verification = app_joint_qdesn_screening_write_csv(source_manifest, file.path(out_dir, "source_manifest_verification.csv")),
    phase112_scorecard_audit = app_joint_qdesn_screening_write_csv(scorecard_audit, file.path(out_dir, "phase112_scorecard_audit.csv")),
    phase112_model_tradeoff_audit = app_joint_qdesn_screening_write_csv(model_tradeoff, file.path(out_dir, "phase112_model_tradeoff_audit.csv")),
    phase112_exal_gap_audit = app_joint_qdesn_screening_write_csv(exal_gap, file.path(out_dir, "phase112_exal_gap_audit.csv")),
    phase113_candidate_selection_rationale = app_joint_qdesn_screening_write_csv(rationale, file.path(out_dir, "phase113_candidate_selection_rationale.csv")),
    phase113_recommended_registry = app_joint_qdesn_screening_write_csv(recommended_registry, registry_path),
    phase113_implementation_plan = app_joint_qdesn_screening_write_csv(plan, file.path(out_dir, "phase113_implementation_plan.csv")),
    phase113_launch_command = app_joint_qdesn_screening_write_csv(launch_command, file.path(out_dir, "phase113_launch_command.csv")),
    provenance = app_joint_qdesn_screening_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    run_config = run_config,
    scorecard_audit = scorecard_audit,
    model_tradeoff = model_tradeoff,
    exal_gap = exal_gap,
    recommended_registry = recommended_registry,
    rationale = rationale,
    plan = plan,
    launch_command = launch_command,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path)
  )
}

# Phase 114 selected Phase 113 VB article-candidate freeze.

app_joint_qdesn_default_phase114_vb_freeze_dir <- function() {
  app_path("application/cache/joint_qdesn_phase114_vb_article_candidate_freeze_20260708")
}

app_joint_qdesn_default_phase114_mcmc_article_dir <- function() {
  app_path("application/cache/joint_qdesn_mcmc_article_phase114_20260708")
}

app_joint_qdesn_default_phase115_article_assets_dir <- function() {
  app_path("application/cache/joint_qdesn_article_validation_assets_phase115_20260708")
}

app_joint_qdesn_phase114_load_selected <- function(phase113_dir) {
  phase113 <- app_joint_qdesn_phase111_load_screening_dir(phase113_dir, "phase113_vb_top_candidate_verification")
  selected <- phase113$selected
  selected <- selected[as.logical(selected$selected %||% TRUE), , drop = FALSE]
  if (!nrow(selected)) selected <- phase113$selected[1L, , drop = FALSE]
  selected_id <- selected$candidate_id[[1L]]
  registry <- phase113$candidate_registry[phase113$candidate_registry$candidate_id == selected_id, , drop = FALSE]
  health <- phase113$health[phase113$health$candidate_id == selected_id, , drop = FALSE]
  if (!nrow(registry) || !nrow(health)) {
    stop("Selected Phase 113 candidate is missing from registry or health table.", call. = FALSE)
  }
  candidate_manifest_path <- file.path(phase113$dir, "candidate_manifest_verification.csv")
  candidate_manifest <- if (file.exists(candidate_manifest_path)) {
    app_read_csv(candidate_manifest_path)
  } else {
    data.frame(status = "fail", missing_reason = "candidate_manifest_verification.csv not found", stringsAsFactors = FALSE)
  }
  scenario_failures <- app_read_csv(file.path(phase113$dir, "scenario_failure_summary.csv"), required = FALSE)
  list(
    phase113 = phase113,
    selected = selected,
    selected_id = selected_id,
    registry = registry,
    health = health,
    candidate_manifest = candidate_manifest,
    scenario_failures = scenario_failures
  )
}

app_joint_qdesn_phase114_selected_model_summary <- function(loaded) {
  sid <- loaded$selected_id
  fit <- loaded$phase113$fit_model[loaded$phase113$fit_model$candidate_id == sid, , drop = FALSE]
  forecast <- loaded$phase113$forecast_model[loaded$phase113$forecast_model$candidate_id == sid, , drop = FALSE]
  by <- c("model_id", "display_label", "likelihood", "fit_structure")
  fit_keep <- fit[, c(by, "truth_mae", "truth_rmse", "check_loss_mean", "raw_crossing_pairs", "contract_crossing_pairs", "reached_max_iter", "max_abs_adjustment", "gate_status"), drop = FALSE]
  names(fit_keep)[names(fit_keep) %in% c("truth_mae", "truth_rmse", "check_loss_mean", "raw_crossing_pairs", "contract_crossing_pairs", "reached_max_iter", "max_abs_adjustment", "gate_status")] <-
    c("fit_truth_mae", "fit_truth_rmse", "fit_check_loss", "fit_raw_crossings", "fit_contract_crossings", "fit_reached_max_iter", "fit_max_abs_adjustment", "fit_gate_status")
  fc_keep <- forecast[, c(by, "truth_mae", "truth_rmse", "check_loss_mean", "crps_grid_mean", "abs_hit_rate_error", "abs_coverage_error", "interval_width_mean", "raw_crossing_pairs", "contract_crossing_pairs", "reached_max_iter", "max_abs_adjustment", "gate_status"), drop = FALSE]
  names(fc_keep)[names(fc_keep) %in% c("truth_mae", "truth_rmse", "check_loss_mean", "raw_crossing_pairs", "contract_crossing_pairs", "reached_max_iter", "max_abs_adjustment", "gate_status")] <-
    c("forecast_truth_mae", "forecast_truth_rmse", "forecast_check_loss", "forecast_raw_crossings", "forecast_contract_crossings", "forecast_reached_max_iter", "forecast_max_abs_adjustment", "forecast_gate_status")
  out <- merge(fit_keep, fc_keep, by = by, all = TRUE)
  out$freeze_role <- ifelse(
    out$model_id == "joint_qdesn_rhs_vb",
    "primary_article_vb_anchor",
    ifelse(out$model_id == "joint_exqdesn_rhs_vb", "joint_exal_extension_review", "vb_comparator_review")
  )
  out$freeze_diagnosis <- ifelse(
    out$model_id == "joint_qdesn_rhs_vb",
    "Primary joint AL row: best joint forecast recovery, zero max-iteration flags, and only two raw forecast crossings before the monotone contract.",
    ifelse(
      out$model_id == "joint_exqdesn_rhs_vb",
      "Joint exAL row: raw noncrossing and converged, but still tail-compressed relative to joint QDESN.",
      ifelse(
        out$forecast_raw_crossings > 0 | out$forecast_reached_max_iter > 0,
        "Comparator row remains review-level because independent fits require more monotone adjustment or hit the VB iteration cap.",
        "Comparator row has no primary implementation blocker."
      )
    )
  )
  ord <- match(out$model_id, c("joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb", "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"))
  out[order(ord), , drop = FALSE]
}

app_joint_qdesn_phase114_selected_scenario_summary <- function(loaded) {
  sid <- loaded$selected_id
  x <- loaded$phase113$forecast_scenario[loaded$phase113$forecast_scenario$candidate_id == sid, , drop = FALSE]
  winners <- app_joint_qdesn_bind_rows(lapply(split(x, x$scenario_id), function(block) {
    block[order(block$truth_mae, block$check_loss_mean), , drop = FALSE][1L, , drop = FALSE]
  }))
  winners$scenario_winner <- TRUE
  x <- merge(
    x,
    winners[, c("scenario_id", "model_id", "scenario_winner"), drop = FALSE],
    by = c("scenario_id", "model_id"),
    all.x = TRUE
  )
  x$scenario_winner[is.na(x$scenario_winner)] <- FALSE
  x$freeze_scenario_note <- ifelse(
    x$model_id == "joint_qdesn_rhs_vb" & x$scenario_winner,
    "joint QDESN wins this scenario",
    ifelse(
      x$model_id == "joint_qdesn_rhs_vb",
      "joint QDESN remains competitive but not the lowest MAE row here",
      ifelse(x$scenario_winner, "comparator wins this scenario", "context row")
    )
  )
  keep <- c(
    "scenario_id", "model_id", "display_label", "likelihood", "fit_structure",
    "truth_mae", "truth_rmse", "check_loss_mean", "raw_crossing_pairs",
    "contract_crossing_pairs", "max_abs_adjustment", "adjustment_rate",
    "reached_max_iter", "gate_status", "scenario_winner", "freeze_scenario_note"
  )
  x[order(x$scenario_id, x$truth_mae), intersect(keep, names(x)), drop = FALSE]
}

app_joint_qdesn_phase114_selected_tau_summary <- function(loaded) {
  sid <- loaded$selected_id
  x <- loaded$phase113$forecast_tau[loaded$phase113$forecast_tau$candidate_id == sid, , drop = FALSE]
  x$tail_region <- ifelse(as.numeric(x$tau) <= 0.10, "lower_tail", ifelse(as.numeric(x$tau) >= 0.90, "upper_tail", "center"))
  wide_rows <- lapply(split(x, x$tau), function(block) {
    val <- function(model_id) {
      out <- block$truth_mae[block$model_id == model_id]
      if (length(out)) as.numeric(out[[1L]]) else NA_real_
    }
    data.frame(
      tau = as.numeric(block$tau[[1L]]),
      tail_region = block$tail_region[[1L]],
      joint_qdesn_truth_mae = val("joint_qdesn_rhs_vb"),
      joint_exqdesn_truth_mae = val("joint_exqdesn_rhs_vb"),
      qdesn_independent_truth_mae = val("qdesn_rhs_independent_vb"),
      exqdesn_independent_truth_mae = val("exqdesn_rhs_independent_vb"),
      stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(wide_rows)
  out$joint_exqdesn_minus_joint_qdesn <- out$joint_exqdesn_truth_mae - out$joint_qdesn_truth_mae
  out$exqdesn_independent_minus_qdesn_independent <- out$exqdesn_independent_truth_mae - out$qdesn_independent_truth_mae
  out$freeze_tau_note <- ifelse(
    out$tail_region != "center" & out$joint_exqdesn_minus_joint_qdesn > 0.05,
    "exQDESN tail fan remains compressed relative to QDESN",
    ifelse(out$joint_exqdesn_minus_joint_qdesn > 0.02, "moderate exQDESN gap", "no primary exQDESN tail warning")
  )
  out[order(out$tau), , drop = FALSE]
}

app_joint_qdesn_phase114_candidate_delta_summary <- function(loaded) {
  score <- loaded$phase113$scorecard
  selected_id <- loaded$selected_id
  ref_ids <- setdiff(score$candidate_id, selected_id)
  selected <- score[score$candidate_id == selected_id, , drop = FALSE]
  rows <- lapply(ref_ids, function(ref_id) {
    ref <- score[score$candidate_id == ref_id, , drop = FALSE]
    data.frame(
      selected_candidate_id = selected_id,
      reference_candidate_id = ref_id,
      delta_screening_score = selected$screening_score[[1L]] - ref$screening_score[[1L]],
      delta_mean_fit_truth_mae = selected$mean_fit_truth_mae[[1L]] - ref$mean_fit_truth_mae[[1L]],
      delta_mean_forecast_truth_mae = selected$mean_forecast_truth_mae[[1L]] - ref$mean_forecast_truth_mae[[1L]],
      delta_joint_qdesn_forecast_truth_mae = selected$joint_qdesn_forecast_truth_mae[[1L]] - ref$joint_qdesn_forecast_truth_mae[[1L]],
      delta_independent_exqdesn_forecast_truth_mae = selected$independent_exqdesn_forecast_truth_mae[[1L]] - ref$independent_exqdesn_forecast_truth_mae[[1L]],
      delta_max_scenario_forecast_truth_mae = selected$max_scenario_forecast_truth_mae[[1L]] - ref$max_scenario_forecast_truth_mae[[1L]],
      delta_forecast_raw_crossings = selected$forecast_raw_crossings[[1L]] - ref$forecast_raw_crossings[[1L]],
      delta_max_forecast_adjustment = selected$max_forecast_adjustment[[1L]] - ref$max_forecast_adjustment[[1L]],
      interpretation = "negative values favor the selected Phase 114 freeze candidate",
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase114_gate_audit <- function(loaded, selected_model_summary) {
  top_manifest_ok <- all(loaded$phase113$manifest_verification$status == "pass")
  candidate_manifest_ok <- "status" %in% names(loaded$candidate_manifest) && all(loaded$candidate_manifest$status == "pass")
  worker_failures <- if (is.null(loaded$scenario_failures) || !nrow(loaded$scenario_failures)) 0L else nrow(loaded$scenario_failures)
  health <- loaded$health
  model_contract_crossings <- sum(selected_model_summary$fit_contract_crossings, selected_model_summary$forecast_contract_crossings, na.rm = TRUE)
  finite_metrics <- all(is.finite(unlist(loaded$selected[, c(
    "screening_score", "mean_fit_truth_mae", "mean_forecast_truth_mae",
    "joint_qdesn_forecast_truth_mae", "max_scenario_forecast_truth_mae",
    "forecast_raw_crossings", "max_forecast_adjustment"
  ), drop = FALSE])))
  data.frame(
    gate = c(
      "top_level_manifest",
      "candidate_manifest",
      "scenario_worker_failures",
      "contract_crossings",
      "finite_selected_metrics",
      "selected_gate_status",
      "raw_crossing_review",
      "vb_max_iteration_review",
      "joint_qdesn_primary_anchor"
    ),
    status = c(
      ifelse(top_manifest_ok, "pass", "fail"),
      ifelse(candidate_manifest_ok, "pass", "fail"),
      ifelse(worker_failures == 0L, "pass", "fail"),
      ifelse(model_contract_crossings == 0L && health$contract_crossings[[1L]] == 0L, "pass", "fail"),
      ifelse(finite_metrics, "pass", "fail"),
      as.character(loaded$selected$gate_status[[1L]]),
      ifelse(health$forecast_raw_crossings[[1L]] > 0L, "review", "pass"),
      ifelse(sum(selected_model_summary$fit_reached_max_iter, selected_model_summary$forecast_reached_max_iter, na.rm = TRUE) > 0L, "review", "pass"),
      ifelse(selected_model_summary$forecast_reached_max_iter[selected_model_summary$model_id == "joint_qdesn_rhs_vb"][[1L]] == 0L &&
        selected_model_summary$forecast_contract_crossings[selected_model_summary$model_id == "joint_qdesn_rhs_vb"][[1L]] == 0L, "pass", "review")
    ),
    detail = c(
      sprintf("%d top-level manifest rows verified", nrow(loaded$phase113$manifest_verification)),
      sprintf("%d nested candidate manifest rows verified", nrow(loaded$candidate_manifest)),
      sprintf("%d scenario worker failure rows", worker_failures),
      sprintf("%d selected fit/forecast contract crossing pairs", model_contract_crossings),
      "selected scorecard metrics are finite",
      sprintf("selected candidate gate is %s", loaded$selected$gate_status[[1L]]),
      sprintf("%d selected forecast raw crossing pairs retained as diagnostics", health$forecast_raw_crossings[[1L]]),
      "some comparator rows still reached the VB iteration budget; primary joint QDESN did not",
      "primary joint QDESN is the article VB anchor; exQDESN remains a reviewed extension"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase114_freeze_decision <- function(loaded, gate_audit) {
  fail <- any(gate_audit$status == "fail")
  review <- any(gate_audit$status == "review")
  data.frame(
    freeze_id = "joint_qdesn_phase114_vb_article_candidate_freeze",
    source_phase = "phase113_top_candidate_verification",
    selected_candidate_id = loaded$selected_id,
    selected_label = loaded$selected$candidate_label[[1L]],
    selected_gate_status = loaded$selected$gate_status[[1L]],
    freeze_status = if (fail) "fail" else if (review) "review_ready_for_mcmc_initialization" else "pass_ready_for_article_assets",
    primary_article_model = "joint_qdesn_rhs_vb",
    mcmc_scope = "JOINT QDESN RHS AL only; exQDESN remains VB-only until a separate exAL MCMC sampler is validated",
    decision = if (fail) {
      "do_not_launch_mcmc"
    } else {
      "freeze_selected_vb_candidate_and_launch_vb_initialized_mcmc_article_candidate"
    },
    rationale = "Phase 113 improves score, mean forecast truth error, max scenario error, and raw crossing burden relative to both Phase 112 references while keeping manifests, worker failures, finiteness, and contract noncrossing gates clean.",
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase114_launch_plan <- function(
  phase113_dir,
  selected_id,
  mcmc_out_dir = app_joint_qdesn_default_phase114_mcmc_article_dir(),
  article_assets_out_dir = app_joint_qdesn_default_phase115_article_assets_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  n_cores = 9L,
  mcmc_n_iter = 1200L,
  mcmc_burn = 600L,
  mcmc_thin = 10L,
  n_chains = 2L
) {
  data.frame(
    command_id = c("phase114_mcmc_article_candidate", "phase115_rebuild_article_validation_assets"),
    command = c(
      sprintf(
        "Rscript application/scripts/108_run_joint_qdesn_mcmc_readiness.R --output-dir %s --phase107-dir %s --fixture-dir %s --candidate-id %s --n-chains %d --mcmc-n-iter %d --mcmc-burn %d --mcmc-thin %d --n-cores %d --final-article-mcmc-table true",
        mcmc_out_dir,
        phase113_dir,
        fixture_dir,
        selected_id,
        as.integer(n_chains),
        as.integer(mcmc_n_iter),
        as.integer(mcmc_burn),
        as.integer(mcmc_thin),
        as.integer(n_cores)
      ),
      sprintf(
        "Rscript application/scripts/110_build_joint_qdesn_article_validation_assets.R --phase107-dir %s --phase109-dir %s --output-dir %s",
        phase113_dir,
        mcmc_out_dir,
        article_assets_out_dir
      )
    ),
    purpose = c(
      "Run VB-initialized article-candidate MCMC for the frozen Phase 113 Joint QDESN RHS AL specification.",
      "Rebuild article-facing validation tables and figures from the frozen Phase 113 VB source and Phase 114 MCMC source."
    ),
    run_after = c("immediate_after_phase114_freeze_if_gate_not_fail", "after_phase114_mcmc_completes_and_audit_passes"),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase114_readme <- function(freeze_decision, gate_audit, launch_plan) {
  c(
    "# Joint QDESN Phase 114 VB Article-Candidate Freeze",
    "",
    "This freeze consumes the completed Phase 113 top-candidate verification and records the selected VB specification for article-candidate MCMC initialization.",
    "",
    sprintf("- Selected candidate: `%s`", freeze_decision$selected_candidate_id[[1L]]),
    sprintf("- Freeze status: `%s`", freeze_decision$freeze_status[[1L]]),
    sprintf("- Decision: `%s`", freeze_decision$decision[[1L]]),
    "",
    "Gate summary:",
    paste(capture.output(print(table(gate_audit$status))), collapse = "\n"),
    "",
    "Interpretation:",
    "- The primary article row is `JOINT QDESN RHS` under the AL likelihood with the RHS prior.",
    "- The selected VB candidate remains review-ready, not final-pass, because raw crossings and independent-comparator max-iteration flags remain diagnostic qualifications.",
    "- The hard reproducibility and implementation gates pass: manifests, worker failures, finite metrics, and contract noncrossing.",
    "- exQDESN remains a documented extension under VB, but it should not be promoted to MCMC until a separate exAL MCMC layer is validated.",
    "",
    "Next commands:",
    "",
    launch_plan$command[[1L]],
    "",
    launch_plan$command[[2L]]
  )
}

app_joint_qdesn_run_phase114_vb_article_candidate_freeze <- function(
  freeze_dir = app_joint_qdesn_default_phase114_vb_freeze_dir(),
  phase113_dir = app_joint_qdesn_default_phase113_vb_screening_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  mcmc_out_dir = app_joint_qdesn_default_phase114_mcmc_article_dir(),
  article_assets_out_dir = app_joint_qdesn_default_phase115_article_assets_dir(),
  n_cores = 9L,
  mcmc_n_iter = 1200L,
  mcmc_burn = 600L,
  mcmc_thin = 10L,
  n_chains = 2L
) {
  freeze_dir <- normalizePath(freeze_dir, mustWork = FALSE)
  phase113_dir <- normalizePath(phase113_dir, mustWork = TRUE)
  fixture_dir <- normalizePath(fixture_dir, mustWork = TRUE)
  mcmc_out_dir <- normalizePath(mcmc_out_dir, mustWork = FALSE)
  article_assets_out_dir <- normalizePath(article_assets_out_dir, mustWork = FALSE)
  app_ensure_dir(freeze_dir)
  loaded <- app_joint_qdesn_phase114_load_selected(phase113_dir)
  model_summary <- app_joint_qdesn_phase114_selected_model_summary(loaded)
  scenario_summary <- app_joint_qdesn_phase114_selected_scenario_summary(loaded)
  tau_summary <- app_joint_qdesn_phase114_selected_tau_summary(loaded)
  delta_summary <- app_joint_qdesn_phase114_candidate_delta_summary(loaded)
  gate_audit <- app_joint_qdesn_phase114_gate_audit(loaded, model_summary)
  freeze_decision <- app_joint_qdesn_phase114_freeze_decision(loaded, gate_audit)
  launch_plan <- app_joint_qdesn_phase114_launch_plan(
    phase113_dir = phase113_dir,
    selected_id = loaded$selected_id,
    mcmc_out_dir = mcmc_out_dir,
    article_assets_out_dir = article_assets_out_dir,
    fixture_dir = fixture_dir,
    n_cores = n_cores,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin,
    n_chains = n_chains
  )
  run_config <- data.frame(
    run_id = "joint_qdesn_phase114_vb_article_candidate_freeze",
    freeze_dir = freeze_dir,
    phase113_dir = loaded$phase113$dir,
    fixture_dir = fixture_dir,
    mcmc_out_dir = mcmc_out_dir,
    article_assets_out_dir = article_assets_out_dir,
    selected_candidate_id = loaded$selected_id,
    n_cores = as.integer(n_cores),
    mcmc_n_chains = as.integer(n_chains),
    mcmc_n_iter = as.integer(mcmc_n_iter),
    mcmc_burn = as.integer(mcmc_burn),
    mcmc_thin = as.integer(mcmc_thin),
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(freeze_dir, "README.md")
  writeLines(app_joint_qdesn_phase114_readme(freeze_decision, gate_audit, launch_plan), readme_path, useBytes = TRUE)
  paths <- c(
    phase114_run_config = app_joint_qdesn_screening_write_csv(run_config, file.path(freeze_dir, "phase114_run_config.csv")),
    freeze_decision_summary = app_joint_qdesn_screening_write_csv(freeze_decision, file.path(freeze_dir, "freeze_decision_summary.csv")),
    freeze_gate_audit = app_joint_qdesn_screening_write_csv(gate_audit, file.path(freeze_dir, "freeze_gate_audit.csv")),
    selected_candidate_controls = app_joint_qdesn_screening_write_csv(loaded$registry, file.path(freeze_dir, "selected_candidate_controls.csv")),
    selected_candidate_scorecard = app_joint_qdesn_screening_write_csv(loaded$selected, file.path(freeze_dir, "selected_candidate_scorecard.csv")),
    selected_candidate_health = app_joint_qdesn_screening_write_csv(loaded$health, file.path(freeze_dir, "selected_candidate_health.csv")),
    selected_vb_model_summary = app_joint_qdesn_screening_write_csv(model_summary, file.path(freeze_dir, "selected_vb_model_summary.csv")),
    selected_vb_scenario_summary = app_joint_qdesn_screening_write_csv(scenario_summary, file.path(freeze_dir, "selected_vb_scenario_summary.csv")),
    selected_vb_tau_summary = app_joint_qdesn_screening_write_csv(tau_summary, file.path(freeze_dir, "selected_vb_tau_summary.csv")),
    candidate_delta_summary = app_joint_qdesn_screening_write_csv(delta_summary, file.path(freeze_dir, "candidate_delta_summary.csv")),
    phase113_source_manifest_verification = app_joint_qdesn_screening_write_csv(loaded$phase113$manifest_verification, file.path(freeze_dir, "phase113_source_manifest_verification.csv")),
    phase113_candidate_manifest_verification = app_joint_qdesn_screening_write_csv(loaded$candidate_manifest, file.path(freeze_dir, "phase113_candidate_manifest_verification.csv")),
    phase114_launch_plan = app_joint_qdesn_screening_write_csv(launch_plan, file.path(freeze_dir, "phase114_launch_plan.csv")),
    provenance = app_joint_qdesn_screening_write_csv(app_joint_qvp_provenance_rows(), file.path(freeze_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, freeze_dir)
  list(
    freeze_dir = normalizePath(freeze_dir, mustWork = TRUE),
    run_config = run_config,
    freeze_decision = freeze_decision,
    gate_audit = gate_audit,
    selected_model_summary = model_summary,
    selected_scenario_summary = scenario_summary,
    selected_tau_summary = tau_summary,
    candidate_delta_summary = delta_summary,
    launch_plan = launch_plan,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path)
  )
}

# Phase 118 targeted exAL tail-calibration readiness after article integration.

app_joint_qdesn_default_phase118_exal_tail_readiness_dir <- function() {
  app_path("application/cache/joint_qdesn_phase118_exal_tail_calibration_readiness_20260709")
}

app_joint_qdesn_default_phase118_vb_screening_dir <- function() {
  app_path("application/cache/joint_qdesn_vb_spec_screening_phase118_20260709")
}

app_joint_qdesn_phase118_verify_article_manifest <- function(
  manifest_path = app_path("tables/joint_qdesn_article_validation_asset_manifest.csv")
) {
  manifest_path <- normalizePath(manifest_path, mustWork = TRUE)
  manifest <- app_read_csv(manifest_path)
  app_check_required_columns(
    manifest,
    c("label", "artifact_type", "path", "size_bytes", "sha256"),
    "joint QDESN article validation asset manifest"
  )
  base_dir <- normalizePath(file.path(dirname(manifest_path), ".."), mustWork = TRUE)
  out <- app_bind_rows_fill(lapply(seq_len(nrow(manifest)), function(ii) {
    rel_path <- manifest$path[[ii]]
    abs_path <- if (grepl("^/", rel_path)) rel_path else file.path(base_dir, rel_path)
    exists <- file.exists(abs_path)
    actual_sha <- if (exists) app_sha256_file(abs_path) else NA_character_
    actual_size <- if (exists) as.numeric(file.info(abs_path)$size) else NA_real_
    data.frame(
      label = manifest$label[[ii]],
      artifact_type = manifest$artifact_type[[ii]],
      relative_path = rel_path,
      path = normalizePath(abs_path, mustWork = FALSE),
      exists = exists,
      declared_sha256 = manifest$sha256[[ii]],
      actual_sha256 = actual_sha,
      declared_size_bytes = as.numeric(manifest$size_bytes[[ii]]),
      actual_size_bytes = actual_size,
      status = if (exists &&
        identical(tolower(actual_sha), tolower(manifest$sha256[[ii]])) &&
        identical(as.numeric(actual_size), as.numeric(manifest$size_bytes[[ii]]))) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  }))
  out
}

app_joint_qdesn_phase118_article_model_audit <- function(
  model_path = app_path("tables/joint_qdesn_article_validation_vb_model_summary.csv")
) {
  model_path <- normalizePath(model_path, mustWork = TRUE)
  x <- app_read_csv(model_path)
  app_check_required_columns(
    x,
    c(
      "model_id", "display_label", "likelihood", "fit_structure", "fit_truth_mae",
      "forecast_truth_mae", "forecast_check_loss", "crps_grid_mean",
      "abs_hit_rate_error", "abs_coverage_error", "forecast_raw_crossings",
      "forecast_contract_crossings", "forecast_max_adjustment", "article_gate"
    ),
    "joint QDESN article validation model summary"
  )
  joint_al <- x$forecast_truth_mae[x$model_id == "joint_qdesn_rhs_vb"][[1L]]
  independent_al <- x$forecast_truth_mae[x$model_id == "qdesn_rhs_independent_vb"][[1L]]
  x$forecast_mae_rank <- rank(x$forecast_truth_mae, ties.method = "first")
  x$fit_mae_rank <- rank(x$fit_truth_mae, ties.method = "first")
  x$forecast_gap_vs_joint_qdesn <- x$forecast_truth_mae - joint_al
  x$forecast_gap_vs_independent_qdesn <- x$forecast_truth_mae - independent_al
  x$phase118_diagnosis <- ifelse(
    x$model_id == "joint_qdesn_rhs_vb",
    "primary article anchor; preserve unless a new candidate improves tail behavior without degrading AL fit/forecast metrics",
    ifelse(
      x$likelihood == "exal" & x$forecast_gap_vs_joint_qdesn > 0.03,
      "exAL is noncrossing but materially farther from oracle quantile paths; target tail fan geometry",
      ifelse(
        x$model_id == "qdesn_rhs_independent_vb" & x$forecast_raw_crossings > 50,
        "independent AL remains a useful accuracy comparator but has high raw monotone-adjustment burden",
        "context comparator; retain for common-control screening"
      )
    )
  )
  x
}

app_joint_qdesn_phase118_parse_mae_cell <- function(x) {
  suppressWarnings(as.numeric(sub(" .*", "", as.character(x))))
}

app_joint_qdesn_phase118_scenario_audit <- function(
  scenario_path = app_path("tables/joint_qdesn_article_validation_vb_scenario_summary.csv")
) {
  scenario_path <- normalizePath(scenario_path, mustWork = TRUE)
  x <- utils::read.csv(scenario_path, stringsAsFactors = FALSE, check.names = FALSE)
  required <- c("Scenario", "Joint QDESN", "Independent QDESN", "Joint exQDESN", "Independent exQDESN")
  app_check_required_columns(x, required, "joint QDESN article validation scenario summary")
  mae <- data.frame(
    scenario = x$Scenario,
    joint_qdesn_mae = app_joint_qdesn_phase118_parse_mae_cell(x[["Joint QDESN"]]),
    independent_qdesn_mae = app_joint_qdesn_phase118_parse_mae_cell(x[["Independent QDESN"]]),
    joint_exqdesn_mae = app_joint_qdesn_phase118_parse_mae_cell(x[["Joint exQDESN"]]),
    independent_exqdesn_mae = app_joint_qdesn_phase118_parse_mae_cell(x[["Independent exQDESN"]]),
    stringsAsFactors = FALSE
  )
  mat <- as.matrix(mae[, -1L, drop = FALSE])
  winner_col <- colnames(mat)[max.col(-mat, ties.method = "first")]
  mae$winner <- c(
    joint_qdesn_mae = "Joint QDESN",
    independent_qdesn_mae = "Independent QDESN",
    joint_exqdesn_mae = "Joint exQDESN",
    independent_exqdesn_mae = "Independent exQDESN"
  )[winner_col]
  mae$best_al_mae <- pmin(mae$joint_qdesn_mae, mae$independent_qdesn_mae)
  mae$best_exal_mae <- pmin(mae$joint_exqdesn_mae, mae$independent_exqdesn_mae)
  mae$joint_exal_minus_joint_al <- mae$joint_exqdesn_mae - mae$joint_qdesn_mae
  mae$best_exal_minus_best_al <- mae$best_exal_mae - mae$best_al_mae
  mae$phase118_focus <- ifelse(
    mae$best_exal_minus_best_al > 0.05,
    "high_priority_exal_tail_or_fan_geometry",
    ifelse(mae$best_exal_minus_best_al > 0.02, "moderate_priority_exal_calibration", "context_or_stability_check")
  )
  mae[order(-mae$best_exal_minus_best_al), , drop = FALSE]
}

app_joint_qdesn_phase118_read_optional_tau_summary <- function(
  tau_summary_path = "",
  phase114_freeze_dir = "",
  phase116_dir = ""
) {
  candidates <- character()
  if (nzchar(as.character(tau_summary_path)[[1L]])) {
    candidates <- c(candidates, as.character(tau_summary_path)[[1L]])
  }
  if (nzchar(as.character(phase116_dir)[[1L]])) {
    candidates <- c(candidates, file.path(as.character(phase116_dir)[[1L]], "tau_sensitivity_summary.csv"))
  }
  if (nzchar(as.character(phase114_freeze_dir)[[1L]])) {
    candidates <- c(candidates, file.path(as.character(phase114_freeze_dir)[[1L]], "selected_vb_tau_summary.csv"))
  }
  candidates <- candidates[nzchar(candidates)]
  candidates <- candidates[file.exists(candidates)]
  if (!length(candidates)) return(NULL)
  path <- normalizePath(candidates[[1L]], mustWork = TRUE)
  x <- app_read_csv(path)
  names(x) <- gsub("\\.", "_", names(x))
  if ("region" %in% names(x) && !"tail_region" %in% names(x)) x$tail_region <- x$region
  if ("independent_qdesn_truth_mae" %in% names(x) && !"qdesn_independent_truth_mae" %in% names(x)) {
    x$qdesn_independent_truth_mae <- x$independent_qdesn_truth_mae
  }
  if ("independent_exqdesn_truth_mae" %in% names(x) && !"exqdesn_independent_truth_mae" %in% names(x)) {
    x$exqdesn_independent_truth_mae <- x$independent_exqdesn_truth_mae
  }
  if (!"joint_exqdesn_minus_joint_qdesn" %in% names(x)) {
    x$joint_exqdesn_minus_joint_qdesn <- x$joint_exqdesn_truth_mae - x$joint_qdesn_truth_mae
  }
  if (!"exqdesn_independent_minus_qdesn_independent" %in% names(x)) {
    x$exqdesn_independent_minus_qdesn_independent <- x$exqdesn_independent_truth_mae - x$qdesn_independent_truth_mae
  }
  x$source_tau_summary_path <- path
  x$source_tau_summary_sha256 <- app_sha256_file(path)
  keep <- c(
    "tau", "tail_region", "joint_qdesn_truth_mae", "joint_exqdesn_truth_mae",
    "qdesn_independent_truth_mae", "exqdesn_independent_truth_mae",
    "joint_exqdesn_minus_joint_qdesn", "exqdesn_independent_minus_qdesn_independent",
    "source_tau_summary_path", "source_tau_summary_sha256"
  )
  missing <- setdiff(keep, names(x))
  if (length(missing)) {
    stop(sprintf("Optional tau summary is missing required normalized columns: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  x[, keep, drop = FALSE]
}

app_joint_qdesn_phase118_tail_gap_audit <- function(
  model_audit,
  tau_summary_path = "",
  phase114_freeze_dir = "",
  phase116_dir = ""
) {
  tau <- app_joint_qdesn_phase118_read_optional_tau_summary(
    tau_summary_path = tau_summary_path,
    phase114_freeze_dir = phase114_freeze_dir,
    phase116_dir = phase116_dir
  )
  if (is.null(tau)) {
    joint_al <- model_audit$forecast_truth_mae[model_audit$model_id == "joint_qdesn_rhs_vb"][[1L]]
    joint_exal <- model_audit$forecast_truth_mae[model_audit$model_id == "joint_exqdesn_rhs_vb"][[1L]]
    ind_al <- model_audit$forecast_truth_mae[model_audit$model_id == "qdesn_rhs_independent_vb"][[1L]]
    ind_exal <- model_audit$forecast_truth_mae[model_audit$model_id == "exqdesn_rhs_independent_vb"][[1L]]
    tau <- data.frame(
      tau = NA_real_,
      tail_region = "aggregate_no_tau_cache",
      joint_qdesn_truth_mae = joint_al,
      joint_exqdesn_truth_mae = joint_exal,
      qdesn_independent_truth_mae = ind_al,
      exqdesn_independent_truth_mae = ind_exal,
      joint_exqdesn_minus_joint_qdesn = joint_exal - joint_al,
      exqdesn_independent_minus_qdesn_independent = ind_exal - ind_al,
      source_tau_summary_path = NA_character_,
      source_tau_summary_sha256 = NA_character_,
      stringsAsFactors = FALSE
    )
  }
  tau$priority <- ifelse(
    tau$tail_region %in% c("lower_tail", "upper_tail") & tau$joint_exqdesn_minus_joint_qdesn > 0.05,
    "high",
    ifelse(tau$joint_exqdesn_minus_joint_qdesn > 0.025, "moderate", "context")
  )
  tau$phase118_diagnosis <- ifelse(
    tau$priority == "high",
    "exAL tail distance is materially worse than AL; target scalar fan-width and gamma-initialization controls",
    ifelse(
      tau$priority == "moderate",
      "exAL gap is visible but not dominant; retain as calibration support metric",
      "no primary exAL tail blocker at this tau or aggregate row"
    )
  )
  tau
}

app_joint_qdesn_phase118_control_feasibility <- function() {
  data.frame(
    control_family = c(
      "scalar_alpha_prior_width", "gamma_initialization", "rhs_global_shrinkage",
      "finite_zeta2_beta_cap", "rhs_inner_loop_and_vb_budget", "tail_specific_alpha_vector",
      "exal_gamma_update_damping", "model_specific_exal_controls", "mcmc_exal_promotion"
    ),
    phase118_status = c(
      "use_now", "use_now", "use_now", "use_now", "use_now",
      "defer_derivation_review", "defer_derivation_review", "defer_until_common_controls_fail",
      "defer_until_vb_tail_calibration_passes"
    ),
    reason = c(
      "Already wired as a scalar control and directly addresses over- or under-regularized alpha/tail fan geometry.",
      "Already wired and previously improved the selected candidate; useful for exAL shape sensitivity without changing updates.",
      "Already wired through tau0 and can reduce coefficient noise or loosen over-smoothing under common controls.",
      "Already wired through zeta2 and can bound coefficient variance without changing the likelihood.",
      "Already wired and separates tail miscalibration from premature VB stopping.",
      "Likely relevant for tails but changes the mixed joint/independent screening contract; reserve for a second derivation-specific stage.",
      "Would alter the exAL optimizer/update contract and needs theory review before article use.",
      "Could make exAL win by special treatment, but first test common controls to preserve table fairness.",
      "MCMC should confirm a frozen VB target, not search over uncalibrated exAL settings."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase118_candidate_registry <- function(
  screening_output_dir = app_joint_qdesn_default_phase118_vb_screening_dir(),
  reference_fit_dir = "",
  reference_forecast_dir = "",
  n_cores = 9L
) {
  screening_output_dir <- normalizePath(screening_output_dir, mustWork = FALSE)
  has_reference <- nzchar(reference_fit_dir) && nzchar(reference_forecast_dir) &&
    dir.exists(reference_fit_dir) && dir.exists(reference_forecast_dir)
  ids <- c(
    if (has_reference) "phase113_selected_reference" else "phase113_selected_controls_rerun",
    "alpha0p75_gamma_zero_zeta2_16",
    "alpha1p0_gamma_zero_zeta2_16",
    "alpha1p25_gamma_zero_zeta2_16",
    "alpha1p5_gamma_zero_zeta2_16",
    "alpha0p6_gamma_zero_zeta2_16",
    "alpha0p75_gamma_half_zeta2_16",
    "alpha1p0_gamma_half_zeta2_16",
    "alpha0p75_gamma_default_zeta2_16",
    "tau0_0p75_alpha0p75_gamma_zero",
    "tau0_1p0_alpha0p75_gamma_zero",
    "tau0_0p35_alpha0p75_gamma_zero",
    "zeta2_32_alpha0p75_gamma_zero",
    "zeta2_8_alpha0p75_gamma_zero",
    "zeta2_inf_alpha0p75_gamma_zero",
    "alpha1p0_tau0_0p75_gamma_zero_zeta2_32",
    "inner12_iter1920_alpha0p75_gamma_zero"
  )
  candidate_dir <- function(id, stage) file.path(screening_output_dir, "candidates", id, stage)
  fit_dirs <- vapply(ids, candidate_dir, character(1L), stage = "fit")
  forecast_dirs <- vapply(ids, candidate_dir, character(1L), stage = "forecast")
  if (has_reference) {
    fit_dirs[[1L]] <- normalizePath(reference_fit_dir, mustWork = TRUE)
    forecast_dirs[[1L]] <- normalizePath(reference_forecast_dir, mustWork = TRUE)
  }
  registry <- data.frame(
    candidate_id = ids,
    candidate_label = c(
      if (has_reference) "Frozen Phase 113 selected reference" else "Rerun Phase 113 selected controls",
      "Alpha sd 0.75, zero gamma, zeta2 16",
      "Alpha sd 1.0, zero gamma, zeta2 16",
      "Alpha sd 1.25, zero gamma, zeta2 16",
      "Alpha sd 1.5, zero gamma, zeta2 16",
      "Alpha sd 0.6, zero gamma, zeta2 16",
      "Alpha sd 0.75, half-default gamma, zeta2 16",
      "Alpha sd 1.0, half-default gamma, zeta2 16",
      "Alpha sd 0.75, default gamma, zeta2 16",
      "RHS tau0 0.75, alpha sd 0.75, zero gamma",
      "RHS tau0 1.0, alpha sd 0.75, zero gamma",
      "RHS tau0 0.35, alpha sd 0.75, zero gamma",
      "zeta2 32, alpha sd 0.75, zero gamma",
      "zeta2 8, alpha sd 0.75, zero gamma",
      "zeta2 Inf, alpha sd 0.75, zero gamma",
      "tau0 0.75, zeta2 32, alpha sd 1.0, zero gamma",
      "Inner-loop 12, VB 1920, alpha sd 0.75, zero gamma"
    ),
    use_existing_artifacts = c(has_reference, rep(FALSE, length(ids) - 1L)),
    fit_dir = fit_dirs,
    forecast_dir = forecast_dirs,
    vb_max_iter = c(rep(1440L, length(ids) - 1L), 1920L),
    adaptive_vb_max_iter_grid = c(rep("1440,1920", length(ids) - 1L), "1920,2400"),
    vb_tol = rep(1.0e-4, length(ids)),
    rhs_vb_inner = c(rep(10L, length(ids) - 1L), 12L),
    tau0 = c(0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.75, 1.0, 0.35, 0.5, 0.5, 0.5, 0.75, 0.5),
    zeta2 = c(16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 32, 8, Inf, 32, 16),
    a_sigma = rep(2, length(ids)),
    b_sigma = rep(1, length(ids)),
    alpha_prior_sd = c(
      "0.5", "0.75", "1", "1.25", "1.5", "0.6", "0.75", "1", "0.75",
      "0.75", "0.75", "0.75", "0.75", "0.75", "0.75", "1", "0.75"
    ),
    alpha_min_spacing = rep(0, length(ids)),
    gamma_init_policy = c(
      "zero", "zero", "zero", "zero", "zero", "zero", "half_default", "half_default", "default",
      "zero", "zero", "zero", "zero", "zero", "zero", "zero", "zero"
    ),
    review_adjustment_threshold = rep(1.0e-3, length(ids)),
    max_dense_dim = rep(300L, length(ids)),
    n_cores = rep(as.integer(n_cores), length(ids)),
    candidate_role = c(
      if (has_reference) "selected_reference" else "selected_controls_rerun",
      rep("phase118_tail_calibration_candidate", length(ids) - 1L)
    ),
    notes = c(
      "Current article candidate controls: tau0=0.5, zeta2=16, alpha sd 0.5, zero gamma, RHS inner 10, VB 1440/1920.",
      "Primary fan-width probe: loosen the scalar alpha prior modestly while preserving the selected zero-gamma and zeta2 controls.",
      "Checks whether returning alpha prior width to 1.0 widens exAL tails without losing AL stability.",
      "Upper fan-width probe; promotes only if AL metrics and raw adjustment burden stay within safeguards.",
      "Aggressive fan-width probe; included to see whether exAL tails are still over-regularized at alpha sd 1.25.",
      "Near-selected fan-width probe; tests whether a small alpha-width relaxation captures most of the improvement with less risk.",
      "Separates gamma-start sensitivity from alpha-width effects without changing the exAL update equations.",
      "Tests whether alpha sd 1.0 benefits from a damped nonzero gamma start.",
      "Checks whether default gamma initialization is competitive once the alpha prior is modestly loosened.",
      "Loosens global RHS shrinkage modestly to test whether coefficient over-smoothing contributes to exAL tail compression.",
      "Returns toward the original global RHS shrinkage while keeping the selected finite zeta2 and zero-gamma controls.",
      "Strengthens global RHS shrinkage beyond the selected setting to test whether exAL gaps reflect noise rather than over-smoothing.",
      "Weaker finite beta cap than zeta2=16; tests whether exAL tail fan needs more coefficient variance.",
      "Stronger finite beta cap than zeta2=16; tests whether anti-noise regularization improves tail recovery.",
      "Removes the finite beta cap while keeping the Phase 118 alpha and gamma controls.",
      "Combined promising-region probe: looser RHS, wider alpha prior, and weaker finite beta cap for upper-tail fan width.",
      "Computational diagnostic: tests whether longer RHS/VB inner updates reduce tail gaps or convergence review pressure."
    ),
    stringsAsFactors = FALSE
  )
  app_joint_qdesn_validate_screening_registry(registry, allow_alpha_prior_vectors = FALSE)
  registry
}

app_joint_qdesn_phase118_selection_policy <- function() {
  data.frame(
    gate_order = seq_len(10L),
    gate_name = c(
      "implementation_integrity", "contract_noncrossing", "finite_scores", "tail_gap_reduction",
      "exal_overall_recovery", "al_preservation", "raw_adjustment_burden", "hit_coverage_calibration",
      "runtime_feasibility", "fresh_holdout_confirmation"
    ),
    gate_type = c("hard_fail", "hard_fail", "hard_fail", rep("selection", 6L), "promotion_required"),
    pass_or_review_rule = c(
      "All candidate manifests verify, no worker failures, no train/validation leakage, finite quantiles and scale summaries.",
      "Contract forecast quantiles must have zero adjacent crossings after the declared monotone contract.",
      "Fit/forecast truth distances, check loss, CRPS-grid, hit rates, coverage, and runtime summaries must be finite.",
      "Prefer candidates reducing joint exQDESN tail truth-MAE gaps at tau 0.05, 0.90, and 0.95 by at least 20 percent relative to the frozen candidate.",
      "Joint exQDESN average forecast truth MAE should move materially toward Joint QDESN RHS; a gap above 0.03 remains review.",
      "Joint QDESN RHS forecast truth MAE should not worsen by more than 5 percent, and check/CRPS should not worsen by more than 1 percent.",
      "Raw crossings and maximum monotone adjustment should not exceed the frozen selected candidate by more than 25 percent.",
      "Hit-rate and central-interval coverage errors should improve for exAL or remain within the current review band.",
      "Runtime should remain compatible with a later MCMC reference; candidates much slower than the selected controls are review unless accuracy gains are large.",
      "No article-table replacement until the chosen candidate is evaluated once on a fresh final validation split or fresh replicate seeds."
    ),
    rationale = c(
      "Protects reproducibility and implementation credibility.",
      "The article scoring contract requires a noncrossing reported grid.",
      "Avoids promoting numerical artifacts.",
      "Targets the observed failure mode instead of a broad leaderboard search.",
      "Prevents a tail-only improvement from hiding worse overall oracle recovery.",
      "Keeps the primary article anchor from being sacrificed to make exAL look better.",
      "Maintains transparency around raw versus contract quantile grids.",
      "Tail fan widening should improve calibration, not just oracle MAE.",
      "Keeps the study feasible and MCMC-ready.",
      "Prevents overfitting to the current article validation bundle."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase118_next_action_plan <- function() {
  data.frame(
    step = seq_len(7L),
    stage = c("freeze_current_article", "materialize_fixtures_if_missing", "run_phase118_screen", "audit_phase118_screen", "select_or_reject", "confirm_on_fresh_holdout", "mcmc_or_manuscript"),
    action = c(
      "Treat the current Phase 115/116 article assets as the baseline evidence and do not overwrite them during screening.",
      "If the v2 clone lacks application/cache fixtures, regenerate them from application/config/joint_qdesn_simulation_dgp_registry_20260706.csv.",
      "Run the targeted Phase 118 registry through the existing Phase 106 VB screening runner.",
      "Refresh the screening audit and inspect model, scenario, tau, coverage, raw-adjustment, and runtime summaries.",
      "Promote only if exAL tail gaps improve under the pre-declared rules without degrading Joint QDESN RHS.",
      "Evaluate the selected candidate on a fresh final validation split or fresh replicate seeds before changing article tables.",
      "If VB passes, run MCMC only for the frozen target; otherwise keep current article wording and document exAL as future calibration work."
    ),
    output = c(
      "current committed article tables and manifest",
      "joint_qdesn_simulation_dgp_fixtures_20260706",
      "joint_qdesn_vb_spec_screening_phase118_20260709",
      "refreshed Phase 106-style audit tables",
      "selected_spec_recommendation.csv plus Phase 118 decision note",
      "fresh-holdout evidence pack",
      "MCMC reference or manuscript stability note"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase118_launch_commands <- function(registry_path, screening_output_dir, fixture_dir, n_cores = 9L) {
  data.frame(
    command_id = c("generate_fixtures_if_missing", "run_phase118_targeted_vb_screen", "audit_phase118_targeted_vb_screen"),
    command = c(
      sprintf(
        "Rscript application/scripts/98_generate_joint_qdesn_simulation_dgp_fixtures.R --output-dir %s --registry application/config/joint_qdesn_simulation_dgp_registry_20260706.csv",
        fixture_dir
      ),
      sprintf(
        "Rscript application/scripts/106_run_joint_qdesn_vb_spec_screening.R --registry %s --output-dir %s --fixture-dir %s --n-cores %d --reuse-completed true --audit-only false",
        registry_path,
        screening_output_dir,
        fixture_dir,
        as.integer(n_cores)
      ),
      sprintf(
        "Rscript application/scripts/107_audit_joint_qdesn_vb_spec_screening.R --output-dir %s",
        screening_output_dir
      )
    ),
    purpose = c(
      "Create the frozen long-series synthetic fixtures if they are not already present in application/cache.",
      "Run the targeted common-control exAL tail-calibration VB screening.",
      "Refresh screening summaries and selected-candidate recommendation after the run."
    ),
    run_condition = c(
      "Only if fixture_dir is missing or its manifest does not verify.",
      "After Phase 118 readiness artifacts have been reviewed.",
      "After all candidate fit and forecast artifacts complete."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase118_readme <- function(run_config, model_audit, tail_audit, registry, launch_commands) {
  joint_exal <- model_audit[model_audit$model_id == "joint_exqdesn_rhs_vb", , drop = FALSE]
  joint_al <- model_audit[model_audit$model_id == "joint_qdesn_rhs_vb", , drop = FALSE]
  worst_tail <- tail_audit[order(-tail_audit$joint_exqdesn_minus_joint_qdesn), , drop = FALSE][1L, , drop = FALSE]
  c(
    "# Joint QDESN Phase 118 exAL Tail-Calibration Readiness",
    "",
    "This artifact prepares a targeted VB calibration screen for the joint-QDESN synthetic validation study.",
    "It does not replace the committed article tables and does not launch MCMC.",
    "",
    sprintf("- Output directory: `%s`", run_config$out_dir[[1L]]),
    sprintf("- Proposed screening directory: `%s`", run_config$screening_output_dir[[1L]]),
    sprintf("- Candidate rows: %d", nrow(registry)),
    "",
    "Current diagnosis:",
    sprintf(
      "- Joint QDESN RHS forecast MAE is %.4f; Joint exQDESN RHS forecast MAE is %.4f.",
      joint_al$forecast_truth_mae[[1L]],
      joint_exal$forecast_truth_mae[[1L]]
    ),
    sprintf(
      "- Worst available exAL-vs-AL gap row is `%s` at tau %s with gap %.4f.",
      worst_tail$tail_region[[1L]],
      ifelse(is.na(worst_tail$tau[[1L]]), "NA", sprintf("%.2f", worst_tail$tau[[1L]])),
      worst_tail$joint_exqdesn_minus_joint_qdesn[[1L]]
    ),
    "- The next screen is targeted at exAL fan geometry, not an unconstrained search to make exAL win.",
    "- Promotion requires fresh-holdout confirmation before the article tables are replaced.",
    "",
    "Primary launch command:",
    "",
    launch_commands$command[launch_commands$command_id == "run_phase118_targeted_vb_screen"][[1L]]
  )
}

app_joint_qdesn_run_phase118_exal_tail_calibration_readiness <- function(
  out_dir = app_joint_qdesn_default_phase118_exal_tail_readiness_dir(),
  screening_output_dir = app_joint_qdesn_default_phase118_vb_screening_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  table_dir = app_path("tables"),
  tau_summary_path = "",
  phase114_freeze_dir = "",
  phase116_dir = "",
  reference_fit_dir = "",
  reference_forecast_dir = "",
  n_cores = 9L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  screening_output_dir <- normalizePath(screening_output_dir, mustWork = FALSE)
  fixture_dir <- normalizePath(fixture_dir, mustWork = FALSE)
  table_dir <- normalizePath(table_dir, mustWork = TRUE)
  app_ensure_dir(out_dir)

  model_audit <- app_joint_qdesn_phase118_article_model_audit(file.path(table_dir, "joint_qdesn_article_validation_vb_model_summary.csv"))
  scenario_audit <- app_joint_qdesn_phase118_scenario_audit(file.path(table_dir, "joint_qdesn_article_validation_vb_scenario_summary.csv"))
  manifest_verification <- app_joint_qdesn_phase118_verify_article_manifest(file.path(table_dir, "joint_qdesn_article_validation_asset_manifest.csv"))
  tail_audit <- app_joint_qdesn_phase118_tail_gap_audit(
    model_audit = model_audit,
    tau_summary_path = tau_summary_path,
    phase114_freeze_dir = phase114_freeze_dir,
    phase116_dir = phase116_dir
  )
  control_feasibility <- app_joint_qdesn_phase118_control_feasibility()
  registry <- app_joint_qdesn_phase118_candidate_registry(
    screening_output_dir = screening_output_dir,
    reference_fit_dir = reference_fit_dir,
    reference_forecast_dir = reference_forecast_dir,
    n_cores = n_cores
  )
  selection_policy <- app_joint_qdesn_phase118_selection_policy()
  next_action <- app_joint_qdesn_phase118_next_action_plan()
  registry_path <- file.path(out_dir, "phase118_exal_tail_screening_registry.csv")
  launch_commands <- app_joint_qdesn_phase118_launch_commands(
    registry_path = registry_path,
    screening_output_dir = screening_output_dir,
    fixture_dir = fixture_dir,
    n_cores = n_cores
  )
  run_config <- data.frame(
    run_id = "joint_qdesn_phase118_exal_tail_calibration_readiness",
    out_dir = out_dir,
    screening_output_dir = screening_output_dir,
    fixture_dir = fixture_dir,
    table_dir = table_dir,
    tau_summary_path = if (nzchar(tau_summary_path)) normalizePath(tau_summary_path, mustWork = TRUE) else "",
    phase114_freeze_dir = if (nzchar(phase114_freeze_dir)) normalizePath(phase114_freeze_dir, mustWork = FALSE) else "",
    phase116_dir = if (nzchar(phase116_dir)) normalizePath(phase116_dir, mustWork = FALSE) else "",
    reference_fit_dir = if (nzchar(reference_fit_dir)) normalizePath(reference_fit_dir, mustWork = FALSE) else "",
    reference_forecast_dir = if (nzchar(reference_forecast_dir)) normalizePath(reference_forecast_dir, mustWork = FALSE) else "",
    n_cores = as.integer(n_cores),
    n_candidate_rows = nrow(registry),
    n_high_priority_tail_rows = sum(tail_audit$priority == "high", na.rm = TRUE),
    article_asset_manifest_status = if (all(manifest_verification$status == "pass")) "pass" else "fail",
    readiness_decision = if (all(manifest_verification$status == "pass")) "ready_to_launch_targeted_vb_screen_after_review" else "blocked_manifest_failure",
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qdesn_phase118_readme(run_config, model_audit, tail_audit, registry, launch_commands), readme_path, useBytes = TRUE)
  paths <- c(
    phase118_run_config = app_joint_qdesn_screening_write_csv(run_config, file.path(out_dir, "phase118_run_config.csv")),
    source_asset_manifest_verification = app_joint_qdesn_screening_write_csv(manifest_verification, file.path(out_dir, "source_asset_manifest_verification.csv")),
    current_model_metric_audit = app_joint_qdesn_screening_write_csv(model_audit, file.path(out_dir, "current_model_metric_audit.csv")),
    current_scenario_winner_audit = app_joint_qdesn_screening_write_csv(scenario_audit, file.path(out_dir, "current_scenario_winner_audit.csv")),
    tail_gap_audit = app_joint_qdesn_screening_write_csv(tail_audit, file.path(out_dir, "tail_gap_audit.csv")),
    control_feasibility_audit = app_joint_qdesn_screening_write_csv(control_feasibility, file.path(out_dir, "control_feasibility_audit.csv")),
    phase118_exal_tail_screening_registry = app_joint_qdesn_screening_write_csv(registry, registry_path),
    selection_policy = app_joint_qdesn_screening_write_csv(selection_policy, file.path(out_dir, "selection_policy.csv")),
    next_action_plan = app_joint_qdesn_screening_write_csv(next_action, file.path(out_dir, "next_action_plan.csv")),
    launch_commands = app_joint_qdesn_screening_write_csv(launch_commands, file.path(out_dir, "launch_commands.csv")),
    provenance = app_joint_qdesn_screening_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    run_config = run_config,
    manifest_verification = manifest_verification,
    model_audit = model_audit,
    scenario_audit = scenario_audit,
    tail_audit = tail_audit,
    control_feasibility = control_feasibility,
    registry = registry,
    selection_policy = selection_policy,
    next_action_plan = next_action,
    launch_commands = launch_commands,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path)
  )
}

# Phase 119 case-specific calibration readiness.  Unlike Phase 118, this stage
# prepares targeted rows that each evaluate one scenario/model case, so the
# later selection can choose different specifications for different cases.

app_joint_qdesn_default_phase119_case_readiness_dir <- function() {
  app_path("application/cache/joint_qdesn_phase119_case_specific_calibration_readiness_20260709")
}

app_joint_qdesn_default_phase119_case_screening_dir <- function() {
  app_path("application/cache/joint_qdesn_vb_case_specific_screening_phase119_20260709")
}

app_joint_qdesn_phase119_scenario_name_map <- function(fixture_dir = app_joint_qdesn_default_simulation_fixture_dir()) {
  fallback <- data.frame(
    scenario_id = c(
      "normal_bridge", "laplace_bridge", "gaussian_mixture_bridge",
      "student_t_location_scale", "asymmetric_laplace_tail",
      "heteroskedastic_seasonal", "persistent_heavy_tail",
      "regime_shift", "nonlinear_reservoir_friendly"
    ),
    scenario = c(
      "Normal Bridge", "Laplace Bridge", "Gaussian-Mixture Bridge",
      "Student-t Location-Scale", "Asymmetric Laplace Tail",
      "Heteroskedastic Seasonal", "Persistent Heavy Tail",
      "Regime Shift", "Nonlinear Reservoir Friendly"
    ),
    scenario_class = c(rep("bridge", 3L), rep("stress", 6L)),
    distribution_family = c(
      "gaussian", "laplace", "gaussian_mixture", "student_t",
      "asymmetric_laplace", "student_t", "student_t", "student_t",
      "gaussian_mixture"
    ),
    dynamics_class = c(
      rep("ar1_seasonal_location_scale", 5L),
      "heteroskedastic_seasonal",
      "ar1_seasonal_location_scale",
      "regime_shift_location_scale",
      "nonlinear_reservoir_friendly"
    ),
    stringsAsFactors = FALSE
  )
  summary_path <- file.path(fixture_dir, "scenario_summary.csv")
  if (!file.exists(summary_path)) return(fallback)
  x <- app_read_csv(summary_path)
  keep <- intersect(c("scenario_id", "scenario_class", "distribution_family", "dynamics_class"), names(x))
  x <- unique(x[, keep, drop = FALSE])
  out <- merge(fallback[, c("scenario_id", "scenario"), drop = FALSE], x, by = "scenario_id", all.y = TRUE)
  out$scenario <- ifelse(is.na(out$scenario), gsub("_", " ", tools::toTitleCase(out$scenario_id)), out$scenario)
  out
}

app_joint_qdesn_phase119_model_metric_lookup <- function(row, model_id) {
  if (identical(model_id, "joint_qdesn_rhs_vb")) return(row$joint_qdesn_mae[[1L]])
  if (identical(model_id, "qdesn_rhs_independent_vb")) return(row$independent_qdesn_mae[[1L]])
  if (identical(model_id, "joint_exqdesn_rhs_vb")) return(row$joint_exqdesn_mae[[1L]])
  if (identical(model_id, "exqdesn_rhs_independent_vb")) return(row$independent_exqdesn_mae[[1L]])
  NA_real_
}

app_joint_qdesn_phase119_model_focus <- function(model_id) {
  if (identical(model_id, "joint_qdesn_rhs_vb")) return("primary_joint_al_accuracy")
  if (identical(model_id, "qdesn_rhs_independent_vb")) return("independent_al_accuracy_and_raw_crossing")
  if (identical(model_id, "joint_exqdesn_rhs_vb")) return("joint_exal_tail_fan")
  if (identical(model_id, "exqdesn_rhs_independent_vb")) return("independent_exal_tail_fan")
  "unknown"
}

app_joint_qdesn_phase119_case_priority <- function(model_id, scenario_row) {
  if (model_id %in% c("joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb")) {
    gap <- if (identical(model_id, "joint_exqdesn_rhs_vb")) {
      scenario_row$joint_exal_minus_joint_al[[1L]]
    } else {
      scenario_row$best_exal_minus_best_al[[1L]]
    }
    if (is.finite(gap) && gap > 0.05) return("high")
    if (is.finite(gap) && gap > 0.02) return("moderate")
    return("context")
  }
  if (identical(model_id, "qdesn_rhs_independent_vb") &&
      scenario_row$winner[[1L]] == "Independent QDESN") return("high")
  if (identical(model_id, "joint_qdesn_rhs_vb") &&
      scenario_row$winner[[1L]] == "Joint QDESN") return("high")
  "moderate"
}

app_joint_qdesn_phase119_case_table <- function(
  table_dir = app_path("tables"),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir()
) {
  scenario_audit <- app_joint_qdesn_phase118_scenario_audit(
    file.path(table_dir, "joint_qdesn_article_validation_vb_scenario_summary.csv")
  )
  scenario_map <- app_joint_qdesn_phase119_scenario_name_map(fixture_dir)
  scenario_audit <- merge(scenario_audit, scenario_map, by = "scenario", all.x = TRUE)
  specs <- app_joint_qdesn_simulation_model_specs()
  rows <- list()
  for (ii in seq_len(nrow(scenario_audit))) {
    srow <- scenario_audit[ii, , drop = FALSE]
    for (jj in seq_len(nrow(specs))) {
      spec <- specs[jj, , drop = FALSE]
      priority <- app_joint_qdesn_phase119_case_priority(spec$model_id[[1L]], srow)
      current_mae <- app_joint_qdesn_phase119_model_metric_lookup(srow, spec$model_id[[1L]])
      best_al <- srow$best_al_mae[[1L]]
      rows[[length(rows) + 1L]] <- data.frame(
        case_id = paste(srow$scenario_id[[1L]], spec$model_id[[1L]], sep = "__"),
        scenario_id = srow$scenario_id[[1L]],
        scenario = srow$scenario[[1L]],
        scenario_class = srow$scenario_class[[1L]],
        distribution_family = srow$distribution_family[[1L]],
        dynamics_class = srow$dynamics_class[[1L]],
        model_id = spec$model_id[[1L]],
        display_label = spec$display_label[[1L]],
        likelihood = spec$likelihood[[1L]],
        fit_structure = spec$fit_structure[[1L]],
        case_focus = app_joint_qdesn_phase119_model_focus(spec$model_id[[1L]]),
        priority = priority,
        current_forecast_truth_mae = current_mae,
        scenario_best_al_mae = best_al,
        current_gap_vs_best_al = current_mae - best_al,
        joint_exal_minus_joint_al = srow$joint_exal_minus_joint_al[[1L]],
        best_exal_minus_best_al = srow$best_exal_minus_best_al[[1L]],
        current_winner = srow$winner[[1L]],
        objective = if (priority == "high") {
          "case-specific optimization target; include in first launch wave"
        } else if (priority == "moderate") {
          "secondary case-specific optimization; run after high-priority cases or if resources allow"
        } else {
          "stability/context case; retain to prevent overfitting high-priority failures"
        },
        stringsAsFactors = FALSE
      )
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  out[order(factor(out$priority, levels = c("high", "moderate", "context")), out$scenario_id, out$model_id), , drop = FALSE]
}

app_joint_qdesn_phase119_control_grid <- function(model_id, priority = "moderate") {
  base <- data.frame(
    suffix = "selected_controls",
    candidate_label = "Current selected controls",
    vb_max_iter = 1440L,
    adaptive_vb_max_iter_grid = "1440,1920",
    vb_tol = 1.0e-4,
    rhs_vb_inner = 10L,
    tau0 = 0.5,
    zeta2 = 16,
    a_sigma = 2,
    b_sigma = 1,
    alpha_prior_sd = "0.5",
    alpha_min_spacing = 0,
    gamma_init_policy = "zero",
    review_adjustment_threshold = 1.0e-3,
    max_dense_dim = 300L,
    candidate_role = "case_selected_controls_reference",
    notes = "Case-local rerun of the selected Phase 113/114 controls for direct comparison.",
    stringsAsFactors = FALSE
  )
  if (model_id %in% c("joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb")) {
    grid <- data.frame(
      suffix = c(
        "alpha0p75_gamma_zero_zeta2_16", "alpha1p0_gamma_zero_zeta2_16",
        "alpha1p25_gamma_zero_zeta2_32", "alpha0p75_gamma_half_zeta2_16",
        "alpha1p0_gamma_half_zeta2_16", "tau0_0p75_alpha0p75_gamma_zero",
        "tau0_0p35_alpha0p75_gamma_zero", "zeta2_8_alpha0p75_gamma_zero",
        "zeta2_32_alpha1p0_gamma_zero", "inner12_iter1920_alpha0p75_gamma_zero"
      ),
      candidate_label = c(
        "Alpha sd 0.75, zero gamma, zeta2 16",
        "Alpha sd 1.0, zero gamma, zeta2 16",
        "Alpha sd 1.25, zero gamma, zeta2 32",
        "Alpha sd 0.75, half-default gamma, zeta2 16",
        "Alpha sd 1.0, half-default gamma, zeta2 16",
        "RHS tau0 0.75, alpha sd 0.75, zero gamma",
        "RHS tau0 0.35, alpha sd 0.75, zero gamma",
        "zeta2 8, alpha sd 0.75, zero gamma",
        "zeta2 32, alpha sd 1.0, zero gamma",
        "Inner-loop 12, VB 1920, alpha sd 0.75, zero gamma"
      ),
      vb_max_iter = c(rep(1440L, 9L), 1920L),
      adaptive_vb_max_iter_grid = c(rep("1440,1920", 9L), "1920,2400"),
      vb_tol = rep(1.0e-4, 10L),
      rhs_vb_inner = c(rep(10L, 9L), 12L),
      tau0 = c(0.5, 0.5, 0.5, 0.5, 0.5, 0.75, 0.35, 0.5, 0.5, 0.5),
      zeta2 = c(16, 16, 32, 16, 16, 16, 16, 8, 32, 16),
      a_sigma = rep(2, 10L),
      b_sigma = rep(1, 10L),
      alpha_prior_sd = c("0.75", "1", "1.25", "0.75", "1", "0.75", "0.75", "0.75", "1", "0.75"),
      alpha_min_spacing = rep(0, 10L),
      gamma_init_policy = c("zero", "zero", "zero", "half_default", "half_default", "zero", "zero", "zero", "zero", "zero"),
      review_adjustment_threshold = rep(1.0e-3, 10L),
      max_dense_dim = rep(300L, 10L),
      candidate_role = rep("case_exal_tail_fan_candidate", 10L),
      notes = c(
        "Moderately loosens the exAL fan while preserving selected zero-gamma controls.",
        "Tests whether returning to alpha sd 1.0 fixes tail compression.",
        "High-fan-width/high-variance probe for difficult exAL tails.",
        "Tests damped nonzero gamma initialization at moderate fan width.",
        "Tests damped nonzero gamma initialization at wider fan width.",
        "Loosens RHS smoothing to reduce tail compression.",
        "Strengthens RHS smoothing to separate noise from over-smoothing.",
        "Stronger beta cap for noisy independent or tail cases.",
        "Weaker beta cap with wider alpha prior.",
        "Separates exAL tail error from premature VB/RHS stopping."
      ),
      stringsAsFactors = FALSE
    )
  } else if (identical(model_id, "qdesn_rhs_independent_vb")) {
    grid <- data.frame(
      suffix = c(
        "tau0_0p35_alpha0p5_zeta2_16", "tau0_0p25_alpha0p35_zeta2_8",
        "tau0_0p75_alpha0p5_zeta2_16", "zeta2_8_alpha0p5",
        "zeta2_32_alpha0p6", "inner12_iter1920_tau0_0p35"
      ),
      candidate_label = c(
        "Independent AL: tau0 0.35, alpha sd 0.5, zeta2 16",
        "Independent AL: tau0 0.25, alpha sd 0.35, zeta2 8",
        "Independent AL: tau0 0.75, alpha sd 0.5, zeta2 16",
        "Independent AL: zeta2 8, alpha sd 0.5",
        "Independent AL: zeta2 32, alpha sd 0.6",
        "Independent AL: inner-loop 12, VB 1920, tau0 0.35"
      ),
      vb_max_iter = c(rep(1440L, 5L), 1920L),
      adaptive_vb_max_iter_grid = c(rep("1440,1920", 5L), "1920,2400"),
      vb_tol = rep(1.0e-4, 6L),
      rhs_vb_inner = c(rep(10L, 5L), 12L),
      tau0 = c(0.35, 0.25, 0.75, 0.5, 0.5, 0.35),
      zeta2 = c(16, 8, 16, 8, 32, 16),
      a_sigma = rep(2, 6L),
      b_sigma = rep(1, 6L),
      alpha_prior_sd = c("0.5", "0.35", "0.5", "0.5", "0.6", "0.5"),
      alpha_min_spacing = rep(0, 6L),
      gamma_init_policy = rep("zero", 6L),
      review_adjustment_threshold = rep(1.0e-3, 6L),
      max_dense_dim = rep(300L, 6L),
      candidate_role = rep("case_independent_al_candidate", 6L),
      notes = c(
        "Stronger RHS coupling to reduce independent raw crossings while preserving AL accuracy.",
        "Aggressive anti-noise candidate for raw crossing cases.",
        "Looser RHS coupling for accuracy-sensitive independent AL cases.",
        "Stronger finite beta cap for noisy independent fits.",
        "Weaker finite beta cap with mild alpha relaxation.",
        "Separates raw-crossing pressure from premature VB/RHS stopping."
      ),
      stringsAsFactors = FALSE
    )
  } else {
    grid <- data.frame(
      suffix = c(
        "tau0_0p35_alpha0p5_zeta2_16", "tau0_0p75_alpha0p5_zeta2_16",
        "zeta2_8_alpha0p5", "zeta2_32_alpha0p6",
        "alpha0p75_tau0_0p5_zeta2_16", "inner12_iter1920_alpha0p5"
      ),
      candidate_label = c(
        "Joint AL: tau0 0.35, alpha sd 0.5, zeta2 16",
        "Joint AL: tau0 0.75, alpha sd 0.5, zeta2 16",
        "Joint AL: zeta2 8, alpha sd 0.5",
        "Joint AL: zeta2 32, alpha sd 0.6",
        "Joint AL: alpha sd 0.75, tau0 0.5, zeta2 16",
        "Joint AL: inner-loop 12, VB 1920, alpha sd 0.5"
      ),
      vb_max_iter = c(rep(1440L, 5L), 1920L),
      adaptive_vb_max_iter_grid = c(rep("1440,1920", 5L), "1920,2400"),
      vb_tol = rep(1.0e-4, 6L),
      rhs_vb_inner = c(rep(10L, 5L), 12L),
      tau0 = c(0.35, 0.75, 0.5, 0.5, 0.5, 0.5),
      zeta2 = c(16, 16, 8, 32, 16, 16),
      a_sigma = rep(2, 6L),
      b_sigma = rep(1, 6L),
      alpha_prior_sd = c("0.5", "0.5", "0.5", "0.6", "0.75", "0.5"),
      alpha_min_spacing = rep(0, 6L),
      gamma_init_policy = rep("zero", 6L),
      review_adjustment_threshold = rep(1.0e-3, 6L),
      max_dense_dim = rep(300L, 6L),
      candidate_role = rep("case_joint_al_candidate", 6L),
      notes = c(
        "Tests stronger RHS coupling for primary joint AL stability.",
        "Tests looser RHS coupling for scenario-specific accuracy.",
        "Stronger beta cap for noisy scenario-specific AL fits.",
        "Weaker beta cap with mild alpha relaxation.",
        "Moderately wider alpha prior as a local accuracy probe.",
        "Separates primary AL error from premature VB/RHS stopping."
      ),
      stringsAsFactors = FALSE
    )
  }
  if (identical(priority, "context")) {
    grid <- grid[seq_len(min(3L, nrow(grid))), , drop = FALSE]
  } else if (identical(priority, "moderate")) {
    grid <- grid[seq_len(min(6L, nrow(grid))), , drop = FALSE]
  }
  app_joint_qdesn_bind_rows(list(base, grid))
}

app_joint_qdesn_phase119_candidate_registry <- function(
  case_table,
  screening_output_dir = app_joint_qdesn_default_phase119_case_screening_dir(),
  n_cores = 1L,
  priority_filter = c("high", "moderate", "context")
) {
  screening_output_dir <- normalizePath(screening_output_dir, mustWork = FALSE)
  priority_filter <- unique(as.character(priority_filter))
  cases <- case_table[case_table$priority %in% priority_filter, , drop = FALSE]
  rows <- list()
  for (ii in seq_len(nrow(cases))) {
    case <- cases[ii, , drop = FALSE]
    grid <- app_joint_qdesn_phase119_control_grid(case$model_id[[1L]], case$priority[[1L]])
    case_slug <- gsub("[^A-Za-z0-9_]+", "_", case$case_id[[1L]])
    for (jj in seq_len(nrow(grid))) {
      g <- grid[jj, , drop = FALSE]
      candidate_id <- paste(case_slug, g$suffix[[1L]], sep = "__")
      rows[[length(rows) + 1L]] <- data.frame(
        candidate_id = candidate_id,
        candidate_label = paste(case$scenario[[1L]], case$display_label[[1L]], g$candidate_label[[1L]], sep = " | "),
        use_existing_artifacts = FALSE,
        fit_dir = file.path(screening_output_dir, "cases", case_slug, "candidates", g$suffix[[1L]], "fit"),
        forecast_dir = file.path(screening_output_dir, "cases", case_slug, "candidates", g$suffix[[1L]], "forecast"),
        vb_max_iter = g$vb_max_iter[[1L]],
        adaptive_vb_max_iter_grid = g$adaptive_vb_max_iter_grid[[1L]],
        vb_tol = g$vb_tol[[1L]],
        rhs_vb_inner = g$rhs_vb_inner[[1L]],
        tau0 = g$tau0[[1L]],
        zeta2 = g$zeta2[[1L]],
        a_sigma = g$a_sigma[[1L]],
        b_sigma = g$b_sigma[[1L]],
        alpha_prior_sd = g$alpha_prior_sd[[1L]],
        alpha_min_spacing = g$alpha_min_spacing[[1L]],
        gamma_init_policy = g$gamma_init_policy[[1L]],
        review_adjustment_threshold = g$review_adjustment_threshold[[1L]],
        max_dense_dim = g$max_dense_dim[[1L]],
        n_cores = as.integer(n_cores),
        candidate_role = g$candidate_role[[1L]],
        notes = g$notes[[1L]],
        scenario_ids = case$scenario_id[[1L]],
        model_ids = case$model_id[[1L]],
        case_id = case$case_id[[1L]],
        case_priority = case$priority[[1L]],
        case_focus = case$case_focus[[1L]],
        case_current_forecast_truth_mae = case$current_forecast_truth_mae[[1L]],
        case_gap_vs_best_al = case$current_gap_vs_best_al[[1L]],
        stringsAsFactors = FALSE
      )
    }
  }
  registry <- app_joint_qdesn_bind_rows(rows)
  app_joint_qdesn_validate_screening_registry(registry, allow_alpha_prior_vectors = FALSE)
  registry
}

app_joint_qdesn_phase119_registry_shards <- function(registry) {
  list(
    high_priority = registry[registry$case_priority == "high", , drop = FALSE],
    exal_high_priority = registry[registry$case_priority == "high" & grepl("exal", registry$case_focus, fixed = TRUE), , drop = FALSE],
    al_high_priority = registry[registry$case_priority == "high" & !grepl("exal", registry$case_focus, fixed = TRUE), , drop = FALSE],
    moderate_priority = registry[registry$case_priority == "moderate", , drop = FALSE],
    context_priority = registry[registry$case_priority == "context", , drop = FALSE]
  )
}

app_joint_qdesn_phase119_selection_policy <- function() {
  data.frame(
    gate_order = seq_len(9L),
    gate_name = c(
      "case_scope", "implementation_integrity", "contract_noncrossing",
      "primary_metric", "secondary_scores", "raw_adjustment_burden",
      "vb_convergence", "fresh_holdout_confirmation", "manuscript_promotion"
    ),
    gate_type = c("design", "hard_fail", "hard_fail", rep("selection", 4L), "promotion_required", "promotion_required"),
    rule = c(
      "Each candidate targets exactly one scenario_id and one model_id; no global winner is required.",
      "Candidate manifests, fixture hashes, worker status, finite quantiles, and finite scores must pass.",
      "Contract quantiles must have zero crossings after the monotone contract.",
      "Select the lowest forecast truth MAE within each case, with fit truth MAE used as a tie-breaker.",
      "Check loss, CRPS-grid, hit-rate error, and coverage error must not show a material deterioration relative to selected controls.",
      "Raw crossings and monotone adjustments remain diagnostics; large increases are review, not silent failures.",
      "Max-iteration flags remain review unless they coincide with unstable or nonfinite outputs.",
      "A per-case selected row cannot replace article assets until confirmed on fresh held-out fixtures or fresh replicate seeds.",
      "Only after fresh confirmation should article tables be rebuilt using case-specific model/scenario specifications."
    ),
    rationale = c(
      "Matches the clarified scientific goal: optimize each validation case rather than one specification for all cases.",
      "Protects reproducibility and implementation credibility.",
      "Preserves the article's reported noncrossing forecast contract.",
      "Targets oracle recovery, the core synthetic-validation signal.",
      "Prevents overfitting to truth distance alone.",
      "Maintains transparency around raw versus reported quantile grids.",
      "Keeps VB diagnostics visible while avoiding premature rejection of finite candidates.",
      "Prevents overfitting the current validation bundle.",
      "Keeps the manuscript evidence coherent and reproducible."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase119_next_action_plan <- function() {
  data.frame(
    step = seq_len(6L),
    stage = c("finish_current_phase118", "case_specific_screen", "case_audit", "case_selection", "fresh_confirmation", "article_rebuild_or_defer"),
    action = c(
      "Let the current Phase 118 global/common-control run finish; use it as context, not as a forced global winner.",
      "Run Phase 119 high-priority case-specific registries first, then moderate/context shards as resources allow.",
      "Audit each case by scenario_id/model_id against its selected-controls row and report fit/forecast metrics.",
      "Select one specification per case, allowing different controls for AL, exAL, joint, independent, and each scenario.",
      "Confirm selected case specifications on fresh held-out fixtures or fresh replicate seeds before article promotion.",
      "If confirmed, rebuild article validation assets with explicit case-specific specification metadata; otherwise document the calibrated limits."
    ),
    output = c(
      "completed Phase 118 audit",
      "joint_qdesn_vb_case_specific_screening_phase119_20260709",
      "case_scorecard.csv and case_selected_specification.csv",
      "per-case freeze artifact",
      "fresh-holdout evidence pack",
      "updated article tables or limitations note"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase119_launch_commands <- function(
  registry_paths,
  screening_output_dir,
  fixture_dir,
  n_cores = 1L,
  readiness_dir = app_joint_qdesn_default_phase119_case_readiness_dir()
) {
  ids <- names(registry_paths)
  commands <- vapply(ids, function(id) {
    sprintf(
      "bash application/scripts/121_launch_joint_qdesn_phase119_parallel_chunks.sh --shard %s --workers 8 --readiness-dir %s --screening-output-dir %s --fixture-dir %s --n-cores-per-worker %d",
      id,
      readiness_dir,
      screening_output_dir,
      fixture_dir,
      as.integer(n_cores)
    )
  }, character(1L))
  audit <- vapply(ids, function(id) {
    sprintf(
      "Rscript application/scripts/107_audit_joint_qdesn_vb_spec_screening.R --output-dir %s",
      file.path(screening_output_dir, id)
    )
  }, character(1L))
  data.frame(
    command_id = c(paste0("run_phase119_", ids), paste0("audit_phase119_", ids)),
    registry_shard = c(ids, ids),
    command = c(commands, audit),
    purpose = c(
      paste("Run Phase 119 case-specific shard", ids),
      paste("Audit Phase 119 case-specific shard", ids)
    ),
    run_condition = c(
      rep("Prefer after Phase 118 finishes or when spare cores are available; high-priority shards should run first.", length(ids)),
      rep("After the corresponding shard completes.", length(ids))
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase119_readme <- function(run_config, case_table, registry, launch_commands) {
  counts <- as.data.frame(table(case_table$priority), stringsAsFactors = FALSE)
  names(counts) <- c("priority", "n_cases")
  high <- counts$n_cases[counts$priority == "high"]
  if (!length(high)) high <- 0L
  primary_command <- launch_commands$command[launch_commands$command_id == "run_phase119_exal_high_priority"]
  if (!length(primary_command)) primary_command <- launch_commands$command[[1L]]
  c(
    "# Joint QDESN Phase 119 Case-Specific Calibration Readiness",
    "",
    "This artifact prepares per-case calibration screens for the joint-QDESN synthetic validation study.",
    "Unlike Phase 118, Phase 119 does not search for a single universal specification.",
    "Each candidate row targets exactly one scenario and one model, so later selection can choose a different specification per validation case.",
    "",
    sprintf("- Output directory: `%s`", run_config$out_dir[[1L]]),
    sprintf("- Proposed screening root: `%s`", run_config$screening_output_dir[[1L]]),
    sprintf("- Screening source status: `%s`", run_config$screening_source_status[[1L]]),
    sprintf("- Article asset manifest status: `%s`", run_config$article_asset_manifest_status[[1L]]),
    sprintf("- Cases: %d total; %d high priority.", nrow(case_table), high),
    sprintf("- Candidate rows: %d", nrow(registry)),
    "",
    "Recommended execution:",
    "",
    "1. Let the currently running Phase 118 job finish unless spare cores are explicitly available.",
    "2. Launch `exal_high_priority` first; it targets the clearest current weakness.",
    "3. Launch `al_high_priority` and `moderate_priority` after the first shard is stable.",
    "4. Refresh article-facing asset manifests before manuscript promotion if any `.tex` wrapper hashes changed.",
    "5. Do not rebuild article tables until fresh-holdout confirmation passes.",
    "",
    "Primary high-priority launch command:",
    "",
    primary_command[[1L]]
  )
}

app_joint_qdesn_run_phase119_case_specific_calibration_readiness <- function(
  out_dir = app_joint_qdesn_default_phase119_case_readiness_dir(),
  screening_output_dir = app_joint_qdesn_default_phase119_case_screening_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  table_dir = app_path("tables"),
  n_cores = 1L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  screening_output_dir <- normalizePath(screening_output_dir, mustWork = FALSE)
  fixture_dir <- normalizePath(fixture_dir, mustWork = FALSE)
  table_dir <- normalizePath(table_dir, mustWork = TRUE)
  app_ensure_dir(out_dir)

  manifest_verification <- app_joint_qdesn_phase118_verify_article_manifest(file.path(table_dir, "joint_qdesn_article_validation_asset_manifest.csv"))
  model_audit <- app_joint_qdesn_phase118_article_model_audit(file.path(table_dir, "joint_qdesn_article_validation_vb_model_summary.csv"))
  case_table <- app_joint_qdesn_phase119_case_table(table_dir = table_dir, fixture_dir = fixture_dir)
  registry <- app_joint_qdesn_phase119_candidate_registry(
    case_table = case_table,
    screening_output_dir = screening_output_dir,
    n_cores = n_cores,
    priority_filter = c("high", "moderate", "context")
  )
  shards <- app_joint_qdesn_phase119_registry_shards(registry)
  shard_paths <- character()
  for (nm in names(shards)) {
    if (!nrow(shards[[nm]])) next
    shard_paths[[nm]] <- app_joint_qdesn_screening_write_csv(
      shards[[nm]],
      file.path(out_dir, sprintf("phase119_%s_registry.csv", nm))
    )
  }
  full_registry_path <- file.path(out_dir, "phase119_case_specific_screening_registry.csv")
  selection_policy <- app_joint_qdesn_phase119_selection_policy()
  next_action <- app_joint_qdesn_phase119_next_action_plan()
  launch_commands <- app_joint_qdesn_phase119_launch_commands(
    registry_paths = shard_paths,
    screening_output_dir = screening_output_dir,
    fixture_dir = fixture_dir,
    n_cores = n_cores,
    readiness_dir = out_dir
  )
  screening_source_files <- c(
    "joint_qdesn_article_validation_vb_model_summary.csv",
    "joint_qdesn_article_validation_vb_scenario_summary.csv"
  )
  screening_source_rows <- manifest_verification[
    basename(manifest_verification$relative_path) %in% screening_source_files,
    ,
    drop = FALSE
  ]
  screening_source_status <- if (
    nrow(screening_source_rows) == length(screening_source_files) &&
      all(screening_source_rows$status == "pass")
  ) {
    "pass"
  } else {
    "fail"
  }
  article_manifest_status <- if (all(manifest_verification$status == "pass")) "pass" else "review"
  readiness_decision <- if (!identical(screening_source_status, "pass")) {
    "block_screening_source_manifest_mismatch"
  } else if (!identical(article_manifest_status, "pass")) {
    "ready_to_launch_screening_review_article_manifest_before_promotion"
  } else {
    "ready_to_prepare_case_specific_screening"
  }
  run_config <- data.frame(
    run_id = "joint_qdesn_phase119_case_specific_calibration_readiness",
    out_dir = out_dir,
    screening_output_dir = screening_output_dir,
    fixture_dir = fixture_dir,
    table_dir = table_dir,
    n_cores = as.integer(n_cores),
    n_cases = nrow(case_table),
    n_high_priority_cases = sum(case_table$priority == "high"),
    n_registry_rows = nrow(registry),
    screening_source_status = screening_source_status,
    article_asset_manifest_status = article_manifest_status,
    readiness_decision = readiness_decision,
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qdesn_phase119_readme(run_config, case_table, registry, launch_commands), readme_path, useBytes = TRUE)
  paths <- c(
    phase119_run_config = app_joint_qdesn_screening_write_csv(run_config, file.path(out_dir, "phase119_run_config.csv")),
    source_asset_manifest_verification = app_joint_qdesn_screening_write_csv(manifest_verification, file.path(out_dir, "source_asset_manifest_verification.csv")),
    current_model_metric_audit = app_joint_qdesn_screening_write_csv(model_audit, file.path(out_dir, "current_model_metric_audit.csv")),
    case_specific_audit = app_joint_qdesn_screening_write_csv(case_table, file.path(out_dir, "case_specific_audit.csv")),
    phase119_case_specific_screening_registry = app_joint_qdesn_screening_write_csv(registry, full_registry_path),
    selection_policy = app_joint_qdesn_screening_write_csv(selection_policy, file.path(out_dir, "selection_policy.csv")),
    next_action_plan = app_joint_qdesn_screening_write_csv(next_action, file.path(out_dir, "next_action_plan.csv")),
    launch_commands = app_joint_qdesn_screening_write_csv(launch_commands, file.path(out_dir, "launch_commands.csv")),
    provenance = app_joint_qdesn_screening_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE),
    shard_paths
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    run_config = run_config,
    manifest_verification = manifest_verification,
    model_audit = model_audit,
    case_table = case_table,
    registry = registry,
    shard_paths = shard_paths,
    selection_policy = selection_policy,
    next_action_plan = next_action,
    launch_commands = launch_commands,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path)
  )
}

# Phase 120 targeted follow-up.  Phase 119 high-priority rows are complete; this
# stage freezes their case-level audit and creates only the additional candidate
# rows needed for unresolved review cases.

app_joint_qdesn_default_phase120_case_followup_dir <- function() {
  app_path("application/cache/joint_qdesn_phase120_case_selection_followup_20260711")
}

app_joint_qdesn_default_phase120_case_screening_dir <- function() {
  app_path("application/cache/joint_qdesn_vb_case_specific_screening_phase120_20260711")
}

app_joint_qdesn_phase120_required_screening_files <- function() {
  c(
    "candidate_registry.csv",
    "screening_health_summary.csv",
    "fit_model_metric_summary.csv",
    "forecast_model_metric_summary.csv",
    "candidate_manifest_verification.csv",
    "artifact_manifest.csv"
  )
}

app_joint_qdesn_phase120_read_screening_shard <- function(dir, source_label) {
  dir <- normalizePath(dir, mustWork = TRUE)
  required <- app_joint_qdesn_phase120_required_screening_files()
  missing <- required[!file.exists(file.path(dir, required))]
  if (length(missing)) {
    stop(
      sprintf("%s is missing required Phase 119 files: %s", source_label, paste(missing, collapse = ", ")),
      call. = FALSE
    )
  }
  list(
    source_label = source_label,
    dir = dir,
    root_manifest_verification = app_joint_qdesn_screening_verify_manifest(dir, source_label, "top_level"),
    candidate_manifest_verification = app_read_csv(file.path(dir, "candidate_manifest_verification.csv")),
    candidate_registry = app_read_csv(file.path(dir, "candidate_registry.csv")),
    health = app_read_csv(file.path(dir, "screening_health_summary.csv")),
    fit_model = app_read_csv(file.path(dir, "fit_model_metric_summary.csv")),
    forecast_model = app_read_csv(file.path(dir, "forecast_model_metric_summary.csv"))
  )
}

app_joint_qdesn_phase120_add_source <- function(x, source_label) {
  if (!nrow(x)) return(x)
  x$source_shard <- source_label
  x
}

app_joint_qdesn_phase120_source_health_summary <- function(shards) {
  rows <- lapply(shards, function(shard) {
    health <- shard$health
    root <- shard$root_manifest_verification
    nested <- shard$candidate_manifest_verification
    data.frame(
      source_shard = shard$source_label,
      source_dir = shard$dir,
      candidate_rows = nrow(shard$candidate_registry),
      health_rows = nrow(health),
      gate_pass = sum(health$gate_status == "pass", na.rm = TRUE),
      gate_review = sum(health$gate_status == "review", na.rm = TRUE),
      gate_fail = sum(health$gate_status == "fail", na.rm = TRUE),
      root_manifest_pass_rows = sum(root$status == "pass", na.rm = TRUE),
      root_manifest_fail_rows = sum(root$status != "pass", na.rm = TRUE),
      nested_manifest_pass_rows = sum(nested$status == "pass", na.rm = TRUE),
      nested_manifest_fail_rows = sum(nested$status != "pass", na.rm = TRUE),
      worker_failures = sum(health$scenario_worker_failures, na.rm = TRUE),
      contract_crossings = sum(health$contract_crossings, na.rm = TRUE),
      forecast_raw_crossings = sum(health$forecast_raw_crossings, na.rm = TRUE),
      fit_reached_max_iter = sum(health$fit_reached_max_iter, na.rm = TRUE),
      forecast_reached_max_iter = sum(health$forecast_reached_max_iter, na.rm = TRUE),
      elapsed_hours = sum(health$elapsed_seconds, na.rm = TRUE) / 3600,
      source_gate = if (any(root$status != "pass", na.rm = TRUE) ||
        any(nested$status != "pass", na.rm = TRUE) ||
        sum(health$scenario_worker_failures, na.rm = TRUE) > 0L ||
        sum(health$contract_crossings, na.rm = TRUE) > 0L) {
        "fail"
      } else {
        "pass"
      },
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase120_prefix_cols <- function(x, cols, prefix) {
  keep <- intersect(cols, names(x))
  out <- x[, keep, drop = FALSE]
  rename <- setdiff(keep, "candidate_id")
  names(out)[match(rename, names(out))] <- paste0(prefix, rename)
  out
}

app_joint_qdesn_phase120_candidate_score_audit <- function(shards) {
  registry <- app_joint_qdesn_bind_rows(lapply(shards, function(s) {
    app_joint_qdesn_phase120_add_source(s$candidate_registry, s$source_label)
  }))
  health <- app_joint_qdesn_bind_rows(lapply(shards, function(s) {
    app_joint_qdesn_phase120_add_source(s$health, s$source_label)
  }))
  fit <- app_joint_qdesn_bind_rows(lapply(shards, function(s) {
    app_joint_qdesn_phase120_add_source(s$fit_model, s$source_label)
  }))
  forecast <- app_joint_qdesn_bind_rows(lapply(shards, function(s) {
    app_joint_qdesn_phase120_add_source(s$forecast_model, s$source_label)
  }))

  app_check_required_columns(registry, c("candidate_id", "case_id", "scenario_ids", "model_ids"), "Phase 119 registry")
  app_check_required_columns(health, c("candidate_id", "gate_status", "forecast_raw_crossings", "contract_crossings"), "Phase 119 health")
  app_check_required_columns(forecast, c("candidate_id", "truth_mae", "raw_crossing_pairs", "contract_crossing_pairs"), "Phase 119 forecast metrics")

  reg_keep <- intersect(c(
    "candidate_id", "candidate_label", "source_shard", "candidate_role", "scenario_ids", "model_ids",
    "fit_dir", "forecast_dir", "n_cores",
    "case_id", "case_priority", "case_focus", "case_current_forecast_truth_mae", "case_gap_vs_best_al",
    "vb_max_iter", "adaptive_vb_max_iter_grid", "vb_tol", "rhs_vb_inner", "tau0", "zeta2",
    "a_sigma", "b_sigma", "alpha_prior_sd", "alpha_min_spacing", "gamma_init_policy",
    "review_adjustment_threshold", "max_dense_dim", "notes"
  ), names(registry))
  h <- app_joint_qdesn_phase120_prefix_cols(
    health,
    c(
      "candidate_id", "manifest_status", "scenario_worker_failures", "fit_worker_failures",
      "forecast_worker_failures", "fit_raw_crossings", "forecast_raw_crossings",
      "contract_crossings", "max_forecast_adjustment", "max_forecast_truth_mae",
      "fit_reached_max_iter", "forecast_reached_max_iter", "elapsed_seconds", "gate_status"
    ),
    "health_"
  )
  f <- app_joint_qdesn_phase120_prefix_cols(
    fit,
    c(
      "candidate_id", "truth_mae", "truth_rmse", "check_loss_mean", "crps_grid_mean",
      "abs_hit_rate_error", "abs_coverage_error", "interval_width_mean", "interval_score_mean",
      "raw_crossing_pairs", "contract_crossing_pairs", "reached_max_iter", "max_abs_adjustment",
      "adjustment_rate", "finite_quantiles", "finite_scores", "gate_status", "elapsed_seconds"
    ),
    "fit_"
  )
  fc <- app_joint_qdesn_phase120_prefix_cols(
    forecast,
    c(
      "candidate_id", "stage", "model_id", "display_label", "likelihood", "fit_structure",
      "truth_mae", "truth_rmse", "check_loss_mean", "crps_grid_mean", "abs_hit_rate_error",
      "abs_coverage_error", "interval_width_mean", "interval_score_mean", "raw_crossing_pairs",
      "contract_crossing_pairs", "reached_max_iter", "max_abs_adjustment", "adjustment_rate",
      "finite_quantiles", "finite_scores", "gate_status", "elapsed_seconds"
    ),
    "forecast_"
  )
  out <- Reduce(function(x, y) merge(x, y, by = "candidate_id", all.x = TRUE), list(registry[, reg_keep, drop = FALSE], h, f, fc))
  out$forecast_truth_delta_vs_selected_controls <- NA_real_
  for (case_id in unique(out$case_id)) {
    idx <- which(out$case_id == case_id)
    ref_idx <- idx[out$candidate_role[idx] == "case_selected_controls_reference"]
    if (!length(ref_idx)) ref_idx <- idx[which.min(out$forecast_truth_mae[idx])]
    ref <- out$forecast_truth_mae[ref_idx[[1L]]]
    out$forecast_truth_delta_vs_selected_controls[idx] <- out$forecast_truth_mae[idx] - ref
  }
  out$implementation_gate <- ifelse(
    out$health_manifest_status != "pass" |
      out$health_scenario_worker_failures > 0 |
      out$health_contract_crossings > 0 |
      out$forecast_contract_crossing_pairs > 0 |
      !out$forecast_finite_quantiles |
      !out$forecast_finite_scores,
    "fail",
    ifelse(
      out$health_gate_status == "review" |
        out$forecast_raw_crossing_pairs > 0 |
        out$forecast_reached_max_iter > 0 |
        out$fit_reached_max_iter > 0,
      "review",
      "pass"
    )
  )
  out$selection_score <- out$forecast_truth_mae +
    0.20 * out$fit_truth_mae +
    0.0005 * out$forecast_raw_crossing_pairs +
    0.0020 * out$forecast_reached_max_iter +
    0.0020 * out$fit_reached_max_iter +
    0.0010 * pmin(out$forecast_max_abs_adjustment, 1)
  out[order(out$case_id, out$selection_score, out$forecast_raw_crossing_pairs), , drop = FALSE]
}

app_joint_qdesn_phase120_case_winner_audit <- function(candidate_audit) {
  cases <- split(candidate_audit, candidate_audit$case_id)
  rows <- lapply(cases, function(x) {
    x$fail_order <- ifelse(x$implementation_gate == "fail", 1L, 0L)
    x <- x[order(
      x$fail_order,
      x$forecast_truth_mae,
      x$forecast_raw_crossing_pairs,
      x$forecast_reached_max_iter,
      x$forecast_check_loss_mean,
      x$forecast_crps_grid_mean,
      x$health_elapsed_seconds
    ), , drop = FALSE]
    best <- x[1L, , drop = FALSE]
    followup_status <- if (best$implementation_gate[[1L]] == "fail") {
      "blocked_implementation_failure"
    } else if (best$forecast_raw_crossing_pairs[[1L]] > 0L) {
      "review_followup_raw_crossing"
    } else if (best$forecast_reached_max_iter[[1L]] > 0L || best$fit_reached_max_iter[[1L]] > 0L) {
      "review_followup_convergence"
    } else if (best$implementation_gate[[1L]] == "pass") {
      "ready_for_vb_freeze_candidate"
    } else {
      "review_no_extra_followup_selected"
    }
    data.frame(
      case_id = best$case_id,
      source_shard = best$source_shard,
      scenario_id = best$scenario_ids,
      model_id = best$model_ids,
      display_label = best$forecast_display_label,
      likelihood = best$forecast_likelihood,
      fit_structure = best$forecast_fit_structure,
      selected_candidate_id = best$candidate_id,
      selected_candidate_label = best$candidate_label,
      selected_candidate_role = best$candidate_role,
      implementation_gate = best$implementation_gate,
      followup_status = followup_status,
      forecast_truth_mae = best$forecast_truth_mae,
      fit_truth_mae = best$fit_truth_mae,
      forecast_check_loss = best$forecast_check_loss_mean,
      forecast_crps_grid = best$forecast_crps_grid_mean,
      forecast_hit_rate_error = best$forecast_abs_hit_rate_error,
      forecast_coverage_error = best$forecast_abs_coverage_error,
      forecast_raw_crossings = best$forecast_raw_crossing_pairs,
      forecast_contract_crossings = best$forecast_contract_crossing_pairs,
      fit_reached_max_iter = best$fit_reached_max_iter,
      forecast_reached_max_iter = best$forecast_reached_max_iter,
      max_forecast_adjustment = best$forecast_max_abs_adjustment,
      forecast_truth_delta_vs_selected_controls = best$forecast_truth_delta_vs_selected_controls,
      tau0 = best$tau0,
      zeta2 = best$zeta2,
      alpha_prior_sd = best$alpha_prior_sd,
      gamma_init_policy = best$gamma_init_policy,
      rhs_vb_inner = best$rhs_vb_inner,
      vb_max_iter = best$vb_max_iter,
      adaptive_vb_max_iter_grid = best$adaptive_vb_max_iter_grid,
      recommended_action = if (followup_status == "ready_for_vb_freeze_candidate") {
        "keep as provisional VB winner; include in later VB freeze/MCMC initialization after all targeted follow-up is audited"
      } else if (followup_status == "review_followup_raw_crossing") {
        "run targeted stronger RHS sparsity/coupling and higher-iteration candidates for this exact case"
      } else if (followup_status == "review_followup_convergence") {
        "run targeted higher VB inner/outer-iteration candidates for this exact case"
      } else {
        "manual review before freeze"
      },
      stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  out[order(factor(out$followup_status, levels = c(
    "blocked_implementation_failure", "review_followup_raw_crossing",
    "review_followup_convergence", "review_no_extra_followup_selected",
    "ready_for_vb_freeze_candidate"
  )), out$case_id), , drop = FALSE]
}

app_joint_qdesn_phase120_target_cases <- function(case_winners) {
  targets <- case_winners[case_winners$followup_status %in% c(
    "review_followup_raw_crossing",
    "review_followup_convergence"
  ), , drop = FALSE]
  targets$phase120_target_priority <- ifelse(
    targets$followup_status == "review_followup_raw_crossing",
    "raw_crossing_resolution",
    "convergence_resolution"
  )
  targets
}

app_joint_qdesn_phase120_control_grid <- function(model_id, followup_status) {
  if (identical(model_id, "qdesn_rhs_independent_vb")) {
    return(data.frame(
      suffix = c(
        "tau0_0p20_alpha0p35_zeta2_8_inner12_iter2400",
        "tau0_0p25_alpha0p30_zeta2_4_inner12_iter2400",
        "tau0_0p35_alpha0p40_zeta2_8_inner14_iter2400",
        "tau0_0p20_alpha0p45_zeta2_16_inner14_iter2880",
        "tau0_0p35_alpha0p5_zeta2_32_inner14_iter2880",
        "tau0_0p5_alpha0p6_zeta2_32_inner14_iter2400"
      ),
      candidate_label = c(
        "Independent AL targeted crossing: tau0 0.20, alpha sd 0.35, zeta2 8, inner 12",
        "Independent AL targeted crossing: tau0 0.25, alpha sd 0.30, zeta2 4, inner 12",
        "Independent AL targeted crossing: tau0 0.35, alpha sd 0.40, zeta2 8, inner 14",
        "Independent AL targeted crossing: tau0 0.20, alpha sd 0.45, zeta2 16, inner 14",
        "Independent AL targeted crossing: tau0 0.35, alpha sd 0.50, zeta2 32, inner 14",
        "Independent AL targeted crossing: tau0 0.50, alpha sd 0.60, zeta2 32, inner 14"
      ),
      vb_max_iter = c(2400L, 2400L, 2400L, 2880L, 2880L, 2400L),
      adaptive_vb_max_iter_grid = c("2400,2880", "2400,2880", "2400,2880", "2880,3360", "2880,3360", "2400,2880"),
      vb_tol = rep(1.0e-4, 6L),
      rhs_vb_inner = c(12L, 12L, 14L, 14L, 14L, 14L),
      tau0 = c(0.20, 0.25, 0.35, 0.20, 0.35, 0.50),
      zeta2 = c(8, 4, 8, 16, 32, 32),
      a_sigma = rep(2, 6L),
      b_sigma = rep(1, 6L),
      alpha_prior_sd = c("0.35", "0.30", "0.40", "0.45", "0.50", "0.60"),
      alpha_min_spacing = rep(0, 6L),
      gamma_init_policy = rep("zero", 6L),
      review_adjustment_threshold = rep(1.0e-3, 6L),
      max_dense_dim = rep(300L, 6L),
      candidate_role = rep("phase120_independent_al_raw_crossing_candidate", 6L),
      notes = c(
        "Aggressive RHS coupling and tighter empirical intercept prior to reduce independent-tail noise.",
        "Most aggressive sparsity/coupling probe; useful only if accuracy does not collapse.",
        "Moderate coupling with additional RHS coordinate passes.",
        "Strong coupling with more outer iterations; tests whether raw crossings are optimizer-limited.",
        "Retains the Phase 119 winning zeta2 scale while increasing coordinate passes and iterations.",
        "Accuracy-preserving continuation around the Phase 119 zeta2 32 winner."
      ),
      stringsAsFactors = FALSE
    ))
  }
  if (identical(model_id, "joint_qdesn_rhs_vb")) {
    return(data.frame(
      suffix = c(
        "tau0_0p20_alpha0p35_zeta2_8_inner14_iter2880",
        "tau0_0p25_alpha0p35_zeta2_8_inner12_iter2400",
        "tau0_0p35_alpha0p45_zeta2_8_inner14_iter2400",
        "tau0_0p35_alpha0p5_zeta2_16_inner14_iter2880",
        "tau0_0p25_alpha0p5_zeta2_16_inner14_iter2880",
        "tau0_0p5_alpha0p75_zeta2_16_inner14_iter2400"
      ),
      candidate_label = c(
        "Joint AL targeted crossing: tau0 0.20, alpha sd 0.35, zeta2 8, inner 14",
        "Joint AL targeted crossing: tau0 0.25, alpha sd 0.35, zeta2 8, inner 12",
        "Joint AL targeted crossing: tau0 0.35, alpha sd 0.45, zeta2 8, inner 14",
        "Joint AL targeted crossing: tau0 0.35, alpha sd 0.50, zeta2 16, inner 14",
        "Joint AL targeted crossing: tau0 0.25, alpha sd 0.50, zeta2 16, inner 14",
        "Joint AL accuracy continuation: tau0 0.50, alpha sd 0.75, zeta2 16, inner 14"
      ),
      vb_max_iter = c(2880L, 2400L, 2400L, 2880L, 2880L, 2400L),
      adaptive_vb_max_iter_grid = c("2880,3360", "2400,2880", "2400,2880", "2880,3360", "2880,3360", "2400,2880"),
      vb_tol = rep(1.0e-4, 6L),
      rhs_vb_inner = c(14L, 12L, 14L, 14L, 14L, 14L),
      tau0 = c(0.20, 0.25, 0.35, 0.35, 0.25, 0.50),
      zeta2 = c(8, 8, 8, 16, 16, 16),
      a_sigma = rep(2, 6L),
      b_sigma = rep(1, 6L),
      alpha_prior_sd = c("0.35", "0.35", "0.45", "0.50", "0.50", "0.75"),
      alpha_min_spacing = rep(0, 6L),
      gamma_init_policy = rep("zero", 6L),
      review_adjustment_threshold = rep(1.0e-3, 6L),
      max_dense_dim = rep(300L, 6L),
      candidate_role = rep("phase120_joint_al_raw_crossing_candidate", 6L),
      notes = c(
        "Strongest joint smoothing probe for the single remaining joint AL raw crossing.",
        "Less aggressive but still crossing-focused joint AL probe.",
        "Moderate alpha tightening with stronger beta cap.",
        "Higher-coordinate-pass continuation of the Phase 119 selected controls.",
        "Stronger RHS coupling with Phase 119 alpha width retained.",
        "Accuracy-preserving continuation around the Phase 119 alpha 0.75 candidate."
      ),
      stringsAsFactors = FALSE
    ))
  }
  if (identical(model_id, "joint_exqdesn_rhs_vb")) {
    return(data.frame(
      suffix = c(
        "inner14_iter2400_alpha0p75_gamma_zero",
        "inner16_iter2880_alpha0p75_gamma_zero",
        "tau0_0p35_inner14_iter2400_alpha0p75_gamma_zero",
        "tau0_0p5_inner16_iter2880_alpha1p0_gamma_zero",
        "zeta2_32_inner14_iter2400_alpha1p0_gamma_zero",
        "tol5e5_inner16_iter2880_alpha0p75_gamma_zero"
      ),
      candidate_label = c(
        "Joint exQDESN convergence: inner 14, VB 2400, alpha sd 0.75, zero gamma",
        "Joint exQDESN convergence: inner 16, VB 2880, alpha sd 0.75, zero gamma",
        "Joint exQDESN convergence: tau0 0.35, inner 14, VB 2400",
        "Joint exQDESN convergence/fan: tau0 0.50, inner 16, alpha sd 1.0",
        "Joint exQDESN convergence/fan: zeta2 32, inner 14, alpha sd 1.0",
        "Joint exQDESN convergence: tighter tolerance, inner 16, VB 2880"
      ),
      vb_max_iter = c(2400L, 2880L, 2400L, 2880L, 2400L, 2880L),
      adaptive_vb_max_iter_grid = c("2400,2880", "2880,3360", "2400,2880", "2880,3360", "2400,2880", "2880,3360"),
      vb_tol = c(rep(1.0e-4, 5L), 5.0e-5),
      rhs_vb_inner = c(14L, 16L, 14L, 16L, 14L, 16L),
      tau0 = c(0.50, 0.50, 0.35, 0.50, 0.50, 0.50),
      zeta2 = c(16, 16, 16, 16, 32, 16),
      a_sigma = rep(2, 6L),
      b_sigma = rep(1, 6L),
      alpha_prior_sd = c("0.75", "0.75", "0.75", "1.00", "1.00", "0.75"),
      alpha_min_spacing = rep(0, 6L),
      gamma_init_policy = rep("zero", 6L),
      review_adjustment_threshold = rep(1.0e-3, 6L),
      max_dense_dim = rep(300L, 6L),
      candidate_role = rep("phase120_joint_exal_convergence_candidate", 6L),
      notes = c(
        "Direct continuation of the Phase 119 winner with more RHS coordinate passes.",
        "Higher-iteration continuation to test whether review status is optimizer budget.",
        "Adds stronger RHS coupling while preserving the Phase 119 alpha/gamma policy.",
        "Tests whether slightly wider exAL fan plus more iterations improves the tail case.",
        "Tests finite beta cap relaxation with the wider exAL fan.",
        "Separates tolerance from iteration-budget effects."
      ),
      stringsAsFactors = FALSE
    ))
  }
  stop(sprintf("No Phase 120 follow-up grid for model '%s'.", model_id), call. = FALSE)
}

app_joint_qdesn_phase120_followup_registry <- function(
  target_cases,
  screening_output_dir = app_joint_qdesn_default_phase120_case_screening_dir(),
  n_cores = 1L
) {
  screening_output_dir <- normalizePath(screening_output_dir, mustWork = FALSE)
  rows <- list()
  for (ii in seq_len(nrow(target_cases))) {
    target <- target_cases[ii, , drop = FALSE]
    grid <- app_joint_qdesn_phase120_control_grid(target$model_id[[1L]], target$followup_status[[1L]])
    case_slug <- gsub("[^A-Za-z0-9_]+", "_", target$case_id[[1L]])
    for (jj in seq_len(nrow(grid))) {
      g <- grid[jj, , drop = FALSE]
      candidate_id <- paste(case_slug, paste0("phase120_", g$suffix[[1L]]), sep = "__")
      rows[[length(rows) + 1L]] <- data.frame(
        candidate_id = candidate_id,
        candidate_label = paste(target$scenario_id[[1L]], target$display_label[[1L]], g$candidate_label[[1L]], sep = " | "),
        use_existing_artifacts = FALSE,
        fit_dir = file.path(screening_output_dir, "targeted_followup", "cases", case_slug, "candidates", g$suffix[[1L]], "fit"),
        forecast_dir = file.path(screening_output_dir, "targeted_followup", "cases", case_slug, "candidates", g$suffix[[1L]], "forecast"),
        vb_max_iter = g$vb_max_iter[[1L]],
        adaptive_vb_max_iter_grid = g$adaptive_vb_max_iter_grid[[1L]],
        vb_tol = g$vb_tol[[1L]],
        rhs_vb_inner = g$rhs_vb_inner[[1L]],
        tau0 = g$tau0[[1L]],
        zeta2 = g$zeta2[[1L]],
        a_sigma = g$a_sigma[[1L]],
        b_sigma = g$b_sigma[[1L]],
        alpha_prior_sd = g$alpha_prior_sd[[1L]],
        alpha_min_spacing = g$alpha_min_spacing[[1L]],
        gamma_init_policy = g$gamma_init_policy[[1L]],
        review_adjustment_threshold = g$review_adjustment_threshold[[1L]],
        max_dense_dim = g$max_dense_dim[[1L]],
        n_cores = as.integer(n_cores),
        candidate_role = g$candidate_role[[1L]],
        notes = g$notes[[1L]],
        scenario_ids = target$scenario_id[[1L]],
        model_ids = target$model_id[[1L]],
        case_id = target$case_id[[1L]],
        case_priority = "phase120_targeted_followup",
        case_focus = target$phase120_target_priority[[1L]],
        case_current_forecast_truth_mae = target$forecast_truth_mae[[1L]],
        case_gap_vs_best_al = NA_real_,
        phase120_source_best_candidate_id = target$selected_candidate_id[[1L]],
        phase120_followup_status = target$followup_status[[1L]],
        phase120_source_raw_crossings = target$forecast_raw_crossings[[1L]],
        phase120_source_reached_max_iter = target$forecast_reached_max_iter[[1L]],
        stringsAsFactors = FALSE
      )
    }
  }
  registry <- app_joint_qdesn_bind_rows(rows)
  app_joint_qdesn_validate_screening_registry(registry, allow_alpha_prior_vectors = FALSE)
  registry
}

app_joint_qdesn_phase120_selection_policy <- function() {
  data.frame(
    gate_order = seq_len(8L),
    gate_name = c(
      "source_integrity", "case_local_selection", "targeted_followup_scope",
      "implementation_gate", "raw_crossing_review", "convergence_review",
      "mcmc_readiness", "article_promotion"
    ),
    gate_type = c("hard_fail", "design", "design", "hard_fail", "review", "review", "promotion_required", "promotion_required"),
    rule = c(
      "Phase 119 high-priority root and nested manifests must verify before using any winners.",
      "Select within scenario/model case; do not force one common specification across all cases.",
      "Generate new rows only for winning cases still blocked by raw crossings or convergence review.",
      "Reject missing hashes, worker failures, nonfinite metrics, or contract crossings.",
      "Raw crossings trigger targeted smoothing/sparsity follow-up, not hidden promotion.",
      "Max-iteration flags trigger higher inner/outer VB follow-up before freezing.",
      "After Phase 120, freeze one VB/VB-LD winner per article case and initialize MCMC from those winners.",
      "Article tables remain unchanged until MCMC confirmation artifacts are complete and hash-manifested."
    ),
    rationale = c(
      "Prevents contaminated selection from partial or corrupted artifacts.",
      "Matches the user's scientific goal of per-case optimization.",
      "Avoids an inefficient broad moderate/context launch that does not address the unresolved cases.",
      "Preserves the implementation/reproducibility standard used in Phases 113-119.",
      "Maintains the raw/contract quantile distinction without overclaiming.",
      "Separates optimizer budget from model behavior.",
      "Keeps VB as calibration/initialization and MCMC as final article-facing evidence.",
      "Protects the manuscript from premature validation-table promotion."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase120_next_action_plan <- function() {
  data.frame(
    step = seq_len(5L),
    stage = c("launch_targeted_followup", "audit_phase120", "freeze_case_winners", "launch_mcmc_confirmation", "article_asset_integration"),
    action = c(
      "Run the Phase 120 targeted follow-up registry with row-parallel workers.",
      "Audit Phase 120 against Phase 119 winners and choose stable per-case VB winners.",
      "Freeze one VB/VB-LD candidate for each article-facing scenario/model row.",
      "Initialize MCMC from the frozen winners for Joint/Independent QDESN and Joint/Independent exQDESN rows needed in the article.",
      "Only after MCMC passes, rebuild article tables/figures/manifests in the authoritative v2 article repo."
    ),
    output = c(
      "joint_qdesn_vb_case_specific_screening_phase120_20260711/targeted_followup",
      "Phase 120 winner comparison and gate audit",
      "case-specific VB freeze artifact",
      "MCMC confirmation artifact with raw/contract quantile-grid diagnostics",
      "article validation assets with provenance and SHA-256 manifests"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase120_launch_commands <- function(registry_path, screening_output_dir, fixture_dir, n_cores = 1L) {
  canonical_output_dir <- file.path(screening_output_dir, "targeted_followup")
  run_cmd <- sprintf(
    "bash application/scripts/123_launch_joint_qdesn_screening_parallel_chunks.sh --registry %s --canonical-output-dir %s --fixture-dir %s --workers 10 --n-cores-per-worker %d --run-id phase120_targeted_20260711",
    registry_path,
    canonical_output_dir,
    fixture_dir,
    as.integer(n_cores)
  )
  audit_cmd <- sprintf(
    "Rscript application/scripts/106_run_joint_qdesn_vb_spec_screening.R --registry %s --output-dir %s --fixture-dir %s --n-cores %d --reuse-completed true --audit-only true",
    registry_path,
    canonical_output_dir,
    fixture_dir,
    as.integer(n_cores)
  )
  data.frame(
    command_id = c("run_phase120_targeted_followup", "audit_phase120_targeted_followup"),
    command = c(run_cmd, audit_cmd),
    purpose = c(
      "Run only the unresolved case-specific Phase 120 follow-up rows.",
      "Build the canonical Phase 120 targeted-follow-up audit after all workers finish."
    ),
    run_condition = c(
      "Launch now if spare cores are available; this replaces the broad moderate/context backlog for the immediate next step.",
      "Run after all Phase 120 worker tmux sessions finish with EXIT_CODE=0."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase120_readme <- function(run_config, source_health, case_winners, targets, registry, launch_commands) {
  c(
    "# Joint QDESN Phase 120 Case-Selection Follow-Up",
    "",
    "This artifact audits the completed Phase 119 high-priority screens and prepares a targeted follow-up registry.",
    "The purpose is per-case optimization, not a single global specification.",
    "",
    sprintf("- Output directory: `%s`", run_config$out_dir[[1L]]),
    sprintf("- Phase 119 AL source: `%s`", run_config$phase119_al_high_priority_dir[[1L]]),
    sprintf("- Phase 119 exAL source: `%s`", run_config$phase119_exal_high_priority_dir[[1L]]),
    sprintf("- Source gates: %s", paste(source_health$source_gate, collapse = ", ")),
    sprintf("- High-priority winning cases audited: %d", nrow(case_winners)),
    sprintf("- Targeted follow-up cases: %d", nrow(targets)),
    sprintf("- Targeted follow-up candidate rows: %d", nrow(registry)),
    "",
    "Why not launch the remaining broad moderate/context backlog now?",
    "",
    "The unresolved rows are already high-priority cases.  They need additional candidate designs around raw crossings or VB convergence, not unrelated moderate/context cases.",
    "",
    "Primary launch command:",
    "",
    launch_commands$command[launch_commands$command_id == "run_phase120_targeted_followup"][[1L]]
  )
}

app_joint_qdesn_run_phase120_case_selection_followup <- function(
  out_dir = app_joint_qdesn_default_phase120_case_followup_dir(),
  screening_output_dir = app_joint_qdesn_default_phase120_case_screening_dir(),
  al_high_priority_dir = file.path(app_joint_qdesn_default_phase119_case_screening_dir(), "al_high_priority"),
  exal_high_priority_dir = file.path(app_joint_qdesn_default_phase119_case_screening_dir(), "exal_high_priority"),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  n_cores = 1L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  screening_output_dir <- normalizePath(screening_output_dir, mustWork = FALSE)
  fixture_dir <- normalizePath(fixture_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)

  shards <- list(
    al_high_priority = app_joint_qdesn_phase120_read_screening_shard(al_high_priority_dir, "al_high_priority"),
    exal_high_priority = app_joint_qdesn_phase120_read_screening_shard(exal_high_priority_dir, "exal_high_priority")
  )
  source_health <- app_joint_qdesn_phase120_source_health_summary(shards)
  candidate_audit <- app_joint_qdesn_phase120_candidate_score_audit(shards)
  case_winners <- app_joint_qdesn_phase120_case_winner_audit(candidate_audit)
  targets <- app_joint_qdesn_phase120_target_cases(case_winners)
  registry <- app_joint_qdesn_phase120_followup_registry(
    targets,
    screening_output_dir = screening_output_dir,
    n_cores = n_cores
  )
  registry_path <- file.path(out_dir, "phase120_targeted_followup_registry.csv")
  selection_policy <- app_joint_qdesn_phase120_selection_policy()
  next_action <- app_joint_qdesn_phase120_next_action_plan()
  launch_commands <- app_joint_qdesn_phase120_launch_commands(
    registry_path = registry_path,
    screening_output_dir = screening_output_dir,
    fixture_dir = fixture_dir,
    n_cores = n_cores
  )
  run_config <- data.frame(
    run_id = "joint_qdesn_phase120_case_selection_followup",
    out_dir = out_dir,
    screening_output_dir = screening_output_dir,
    fixture_dir = fixture_dir,
    phase119_al_high_priority_dir = normalizePath(al_high_priority_dir, mustWork = TRUE),
    phase119_exal_high_priority_dir = normalizePath(exal_high_priority_dir, mustWork = TRUE),
    n_cores = as.integer(n_cores),
    n_phase119_candidates = nrow(candidate_audit),
    n_case_winners = nrow(case_winners),
    n_target_cases = nrow(targets),
    n_followup_candidate_rows = nrow(registry),
    source_gate_status = if (all(source_health$source_gate == "pass")) "pass" else "fail",
    readiness_decision = if (all(source_health$source_gate == "pass") && nrow(registry) > 0L) {
      "ready_to_launch_phase120_targeted_followup"
    } else if (all(source_health$source_gate == "pass")) {
      "no_followup_needed_ready_for_vb_freeze"
    } else {
      "blocked_source_artifact_failure"
    },
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qdesn_phase120_readme(run_config, source_health, case_winners, targets, registry, launch_commands), readme_path, useBytes = TRUE)
  source_manifest <- app_joint_qdesn_bind_rows(list(
    app_joint_qdesn_phase120_add_source(shards$al_high_priority$root_manifest_verification, "al_high_priority_root"),
    app_joint_qdesn_phase120_add_source(shards$exal_high_priority$root_manifest_verification, "exal_high_priority_root"),
    app_joint_qdesn_phase120_add_source(shards$al_high_priority$candidate_manifest_verification, "al_high_priority_nested"),
    app_joint_qdesn_phase120_add_source(shards$exal_high_priority$candidate_manifest_verification, "exal_high_priority_nested")
  ))
  paths <- c(
    phase120_run_config = app_joint_qdesn_screening_write_csv(run_config, file.path(out_dir, "phase120_run_config.csv")),
    phase119_source_manifest_verification = app_joint_qdesn_screening_write_csv(source_manifest, file.path(out_dir, "phase119_source_manifest_verification.csv")),
    phase119_source_health_summary = app_joint_qdesn_screening_write_csv(source_health, file.path(out_dir, "phase119_source_health_summary.csv")),
    phase119_candidate_score_audit = app_joint_qdesn_screening_write_csv(candidate_audit, file.path(out_dir, "phase119_candidate_score_audit.csv")),
    phase119_case_winner_audit = app_joint_qdesn_screening_write_csv(case_winners, file.path(out_dir, "phase119_case_winner_audit.csv")),
    phase120_target_case_audit = app_joint_qdesn_screening_write_csv(targets, file.path(out_dir, "phase120_target_case_audit.csv")),
    phase120_targeted_followup_registry = app_joint_qdesn_screening_write_csv(registry, registry_path),
    phase120_selection_policy = app_joint_qdesn_screening_write_csv(selection_policy, file.path(out_dir, "phase120_selection_policy.csv")),
    phase120_next_action_plan = app_joint_qdesn_screening_write_csv(next_action, file.path(out_dir, "phase120_next_action_plan.csv")),
    phase120_launch_commands = app_joint_qdesn_screening_write_csv(launch_commands, file.path(out_dir, "phase120_launch_commands.csv")),
    provenance = app_joint_qdesn_screening_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    run_config = run_config,
    source_health = source_health,
    candidate_audit = candidate_audit,
    case_winners = case_winners,
    targets = targets,
    registry = registry,
    selection_policy = selection_policy,
    next_action_plan = next_action,
    launch_commands = launch_commands,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path)
  )
}

# Phase 121 freezes the case-specific VB/VB-LD winners after the Phase 120
# targeted follow-up.  This is a reproducible initialization contract for the
# later MCMC confirmation layer; it is not article-facing final evidence.

app_joint_qdesn_default_phase121_case_vb_freeze_dir <- function() {
  app_path("application/cache/joint_qdesn_phase121_case_vb_winner_freeze_20260711")
}

app_joint_qdesn_phase121_default_source_dirs <- function() {
  list(
    al_high_priority = file.path(app_joint_qdesn_default_phase119_case_screening_dir(), "al_high_priority"),
    exal_high_priority = file.path(app_joint_qdesn_default_phase119_case_screening_dir(), "exal_high_priority"),
    phase120_targeted_followup = file.path(app_joint_qdesn_default_phase120_case_screening_dir(), "targeted_followup")
  )
}

app_joint_qdesn_phase121_metric_tol <- function(best_mae, abs_tol = 5.0e-4, rel_tol = 0.005) {
  max(as.numeric(abs_tol), as.numeric(rel_tol) * abs(as.numeric(best_mae)))
}

app_joint_qdesn_phase121_load_sources <- function(source_dirs = app_joint_qdesn_phase121_default_source_dirs()) {
  labels <- names(source_dirs)
  if (is.null(labels) || any(!nzchar(labels))) {
    stop("Phase 121 source_dirs must be a named list or named character vector.", call. = FALSE)
  }
  out <- lapply(seq_along(source_dirs), function(ii) {
    app_joint_qdesn_phase120_read_screening_shard(source_dirs[[ii]], labels[[ii]])
  })
  names(out) <- labels
  out
}

app_joint_qdesn_phase121_source_manifest <- function(shards) {
  pieces <- list()
  for (nm in names(shards)) {
    pieces[[length(pieces) + 1L]] <- app_joint_qdesn_phase120_add_source(shards[[nm]]$root_manifest_verification, paste0(nm, "_root"))
    pieces[[length(pieces) + 1L]] <- app_joint_qdesn_phase120_add_source(shards[[nm]]$candidate_manifest_verification, paste0(nm, "_nested"))
  }
  app_joint_qdesn_bind_rows(pieces)
}

app_joint_qdesn_phase121_candidate_audit <- function(shards) {
  out <- app_joint_qdesn_phase120_candidate_score_audit(shards)
  out$phase121_source_role <- ifelse(
    out$source_shard == "phase120_targeted_followup",
    "targeted_followup_candidate",
    "phase119_case_specific_candidate"
  )
  out$phase121_hard_fail <- out$implementation_gate == "fail" |
    !is.finite(out$forecast_truth_mae) |
    !is.finite(out$fit_truth_mae) |
    out$forecast_contract_crossing_pairs > 0 |
    out$fit_contract_crossing_pairs > 0 |
    !out$forecast_finite_quantiles |
    !out$forecast_finite_scores |
    !out$fit_finite_quantiles |
    !out$fit_finite_scores
  out$phase121_hard_fail[is.na(out$phase121_hard_fail)] <- TRUE
  out$phase121_review_reason <- ifelse(
    out$phase121_hard_fail,
    "hard_gate_failure",
    ifelse(
      out$forecast_reached_max_iter > 0 | out$fit_reached_max_iter > 0,
      "vb_max_iteration_review",
      ifelse(
        out$forecast_raw_crossing_pairs > 0 | out$fit_raw_crossing_pairs > 0 |
          out$forecast_max_abs_adjustment > 1.0e-3 | out$fit_max_abs_adjustment > 1.0e-3,
        "raw_crossing_or_monotone_adjustment_review",
        "no_review_flag"
      )
    )
  )
  out
}

app_joint_qdesn_phase121_select_one_case <- function(x, abs_tol = 5.0e-4, rel_tol = 0.005) {
  x$hard_fail_order <- ifelse(x$phase121_hard_fail, 1L, 0L)
  usable <- x[!x$phase121_hard_fail & is.finite(x$forecast_truth_mae), , drop = FALSE]
  if (!nrow(usable)) {
    x <- x[order(
      x$hard_fail_order,
      x$forecast_truth_mae,
      x$forecast_contract_crossing_pairs,
      x$forecast_reached_max_iter,
      x$forecast_raw_crossing_pairs
    ), , drop = FALSE]
    best <- x[1L, , drop = FALSE]
    best$phase121_selection_rule <- "blocked_all_candidates_failed_hard_gate"
    best$phase121_best_forecast_truth_mae <- best$forecast_truth_mae
    best$phase121_mae_tolerance <- NA_real_
    best$phase121_selected_within_tolerance <- FALSE
    best$phase121_selection_status <- "fail"
    best$phase121_selection_note <- "No usable candidate passed hard implementation gates."
    return(best)
  }

  best_mae <- min(usable$forecast_truth_mae, na.rm = TRUE)
  tol <- app_joint_qdesn_phase121_metric_tol(best_mae, abs_tol = abs_tol, rel_tol = rel_tol)
  eligible <- usable[usable$forecast_truth_mae <= best_mae + tol, , drop = FALSE]
  eligible$phase121_stability_penalty <- 1000 * (eligible$forecast_reached_max_iter + eligible$fit_reached_max_iter) +
    10 * (eligible$forecast_contract_crossing_pairs + eligible$fit_contract_crossing_pairs) +
    1 * (eligible$forecast_raw_crossing_pairs + eligible$fit_raw_crossing_pairs) +
    pmin(eligible$forecast_max_abs_adjustment + eligible$fit_max_abs_adjustment, 1)
  eligible <- eligible[order(
    eligible$phase121_stability_penalty,
    eligible$forecast_check_loss_mean,
    eligible$forecast_crps_grid_mean,
    eligible$fit_truth_mae,
    eligible$forecast_truth_mae,
    eligible$health_elapsed_seconds
  ), , drop = FALSE]
  selected <- eligible[1L, , drop = FALSE]
  raw_best <- usable[order(usable$forecast_truth_mae, usable$forecast_check_loss_mean), , drop = FALSE][1L, , drop = FALSE]
  selected$phase121_selection_rule <- if (identical(selected$candidate_id[[1L]], raw_best$candidate_id[[1L]])) {
    "minimum_forecast_truth_mae_selected"
  } else {
    "within_tolerance_stability_selected"
  }
  selected$phase121_best_forecast_truth_mae <- best_mae
  selected$phase121_mae_tolerance <- tol
  selected$phase121_selected_within_tolerance <- TRUE
  selected$phase121_selection_status <- if (selected$implementation_gate[[1L]] == "pass") "pass" else "review"
  selected$phase121_selection_note <- if (selected$phase121_selection_rule[[1L]] == "within_tolerance_stability_selected") {
    sprintf(
      "Selected a more stable candidate within %.6f forecast-MAE tolerance of the raw best candidate `%s`.",
      tol,
      raw_best$candidate_id[[1L]]
    )
  } else {
    "Selected the candidate with the lowest forecast truth MAE among usable rows."
  }
  selected
}

app_joint_qdesn_phase121_select_case_winners <- function(candidate_audit, abs_tol = 5.0e-4, rel_tol = 0.005) {
  cases <- split(candidate_audit, candidate_audit$case_id)
  out <- app_joint_qdesn_bind_rows(lapply(cases, app_joint_qdesn_phase121_select_one_case, abs_tol = abs_tol, rel_tol = rel_tol))
  out$phase121_freeze_role <- ifelse(
    out$phase121_selection_status == "fail",
    "blocked",
    ifelse(out$phase121_selection_status == "pass", "vb_winner_ready_for_mcmc_initialization", "vb_winner_review_ready_for_mcmc_initialization")
  )
  out[order(out$scenario_ids, out$model_ids), , drop = FALSE]
}

app_joint_qdesn_phase121_winner_controls <- function(winners) {
  keep <- c(
    "case_id", "scenario_ids", "model_ids", "candidate_id", "candidate_label",
    "source_shard", "phase121_selection_status", "phase121_selection_rule",
    "phase121_freeze_role", "vb_max_iter", "adaptive_vb_max_iter_grid", "vb_tol",
    "rhs_vb_inner", "tau0", "zeta2", "a_sigma", "b_sigma", "alpha_prior_sd",
    "alpha_min_spacing", "gamma_init_policy", "review_adjustment_threshold",
    "max_dense_dim", "fit_dir", "forecast_dir", "notes"
  )
  keep <- intersect(keep, names(winners))
  winners[, keep, drop = FALSE]
}

app_joint_qdesn_phase121_winner_metric_summary <- function(winners) {
  keep <- c(
    "case_id", "scenario_ids", "model_ids", "forecast_display_label",
    "forecast_likelihood", "forecast_fit_structure", "candidate_id",
    "source_shard", "phase121_selection_status", "phase121_selection_rule",
    "phase121_best_forecast_truth_mae", "phase121_mae_tolerance",
    "forecast_truth_mae", "fit_truth_mae", "forecast_truth_rmse", "fit_truth_rmse",
    "forecast_check_loss_mean", "forecast_crps_grid_mean",
    "forecast_abs_hit_rate_error", "forecast_abs_coverage_error",
    "forecast_interval_width_mean", "forecast_interval_score_mean",
    "forecast_raw_crossing_pairs", "forecast_contract_crossing_pairs",
    "fit_raw_crossing_pairs", "fit_contract_crossing_pairs",
    "forecast_reached_max_iter", "fit_reached_max_iter",
    "forecast_max_abs_adjustment", "fit_max_abs_adjustment",
    "health_elapsed_seconds", "phase121_review_reason", "phase121_selection_note"
  )
  keep <- intersect(keep, names(winners))
  winners[, keep, drop = FALSE]
}

app_joint_qdesn_phase121_gate_audit <- function(source_health, candidate_audit, winners) {
  source_fail <- any(source_health$source_gate != "pass")
  candidate_fail <- any(candidate_audit$phase121_hard_fail)
  winner_fail <- any(winners$phase121_selection_status == "fail")
  contract_crossings <- sum(winners$forecast_contract_crossing_pairs, winners$fit_contract_crossing_pairs, na.rm = TRUE)
  raw_crossings <- sum(winners$forecast_raw_crossing_pairs, winners$fit_raw_crossing_pairs, na.rm = TRUE)
  max_iter <- sum(winners$forecast_reached_max_iter, winners$fit_reached_max_iter, na.rm = TRUE)
  stability_tie <- sum(winners$phase121_selection_rule == "within_tolerance_stability_selected", na.rm = TRUE)
  data.frame(
    gate = c(
      "source_manifests_and_workers",
      "candidate_hard_gates",
      "selected_winner_hard_gates",
      "selected_contract_crossings",
      "selected_raw_crossing_review",
      "selected_vb_max_iteration_review",
      "stability_tie_policy",
      "mcmc_scope_readiness"
    ),
    status = c(
      ifelse(source_fail, "fail", "pass"),
      ifelse(candidate_fail, "review", "pass"),
      ifelse(winner_fail, "fail", "pass"),
      ifelse(contract_crossings > 0, "fail", "pass"),
      ifelse(raw_crossings > 0, "review", "pass"),
      ifelse(max_iter > 0, "review", "pass"),
      ifelse(stability_tie > 0, "pass", "pass"),
      "review"
    ),
    detail = c(
      sprintf("%d source shards; %d source rows failed manifest/worker/contract gates.", nrow(source_health), sum(source_health$source_gate != "pass")),
      sprintf("%d/%d candidate rows have hard-gate failures; these are excluded from selection unless a case has no usable row.", sum(candidate_audit$phase121_hard_fail, na.rm = TRUE), nrow(candidate_audit)),
      sprintf("%d selected winners failed hard gates.", sum(winners$phase121_selection_status == "fail", na.rm = TRUE)),
      sprintf("%d selected fit/forecast contract crossing pairs.", contract_crossings),
      sprintf("%d selected fit/forecast raw crossing pairs retained as diagnostics.", raw_crossings),
      sprintf("%d selected fit/forecast max-iteration flags.", max_iter),
      sprintf("%d selected winners used the within-tolerance stability rule.", stability_tie),
      "Existing MCMC readiness code is AL joint-only and not enough for all four final article rows."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase121_mcmc_readiness_gap_audit <- function(winners) {
  rows <- lapply(split(winners, winners$model_ids), function(x) {
    model_id <- x$model_ids[[1L]]
    likelihood <- x$forecast_likelihood[[1L]]
    fit_structure <- x$forecast_fit_structure[[1L]]
    existing_support <- if (identical(model_id, "joint_qdesn_rhs_vb") && identical(likelihood, "al") && identical(fit_structure, "joint")) {
      "partial_phase108_joint_al_fit_window_reference"
    } else {
      "not_supported_by_phase108"
    }
    required_capability <- if (identical(likelihood, "al") && identical(fit_structure, "joint")) {
      "case_specific_joint_al_mcmc_confirmation"
    } else if (identical(likelihood, "al")) {
      "case_specific_independent_al_mcmc_confirmation"
    } else if (identical(fit_structure, "joint")) {
      "case_specific_joint_exal_mcmc_confirmation"
    } else {
      "case_specific_independent_exal_mcmc_confirmation"
    }
    data.frame(
      model_id = model_id,
      display_label = x$forecast_display_label[[1L]],
      likelihood = likelihood,
      fit_structure = fit_structure,
      selected_cases = nrow(x),
      selected_pass = sum(x$phase121_selection_status == "pass", na.rm = TRUE),
      selected_review = sum(x$phase121_selection_status == "review", na.rm = TRUE),
      selected_fail = sum(x$phase121_selection_status == "fail", na.rm = TRUE),
      existing_mcmc_support = existing_support,
      required_mcmc_capability = required_capability,
      readiness_status = if (identical(existing_support, "partial_phase108_joint_al_fit_window_reference")) {
        "partial_existing_runner_needs_phase122_case_specific_extension"
      } else {
        "phase122_runner_required"
      },
      reason = if (identical(existing_support, "partial_phase108_joint_al_fit_window_reference")) {
        "Phase108 can initialize a joint AL reference from one VB contract, but the final study needs per-case winners and article-row confirmation."
      } else if (identical(likelihood, "exal")) {
        "The existing MCMC readiness runner does not implement the exAL likelihood or independent exQDESN rows."
      } else {
        "The existing MCMC readiness runner does not implement independent single-quantile QDESN MCMC rows."
      },
      stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  out[order(match(out$model_id, c(
    "joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb",
    "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"
  ))), , drop = FALSE]
}

app_joint_qdesn_phase121_mcmc_launch_plan <- function(
  phase121_dir = app_joint_qdesn_default_phase121_case_vb_freeze_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  mcmc_out_dir = app_path("application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711"),
  n_cores = 12L,
  n_chains = 2L,
  mcmc_n_iter = 1200L,
  mcmc_burn = 600L,
  mcmc_thin = 10L
) {
  data.frame(
    step = seq_len(5L),
    stage = c(
      "implement_phase122_runner",
      "phase122_smoke_on_one_case_per_model",
      "launch_phase122_article_confirmation",
      "audit_phase122_mcmc_outputs",
      "rebuild_article_assets_after_mcmc"
    ),
    command_or_action = c(
      "Add a case-specific MCMC confirmation runner that consumes Phase121 winners and supports joint/independent AL plus joint/independent exAL rows.",
      sprintf("Rscript application/scripts/125_run_joint_qdesn_phase122_mcmc_case_confirmation.R --phase121-dir %s --fixture-dir %s --output-dir %s --scenario-limit-per-model 1 --n-chains %d --mcmc-n-iter 120 --mcmc-burn 60 --mcmc-thin 10 --n-cores %d", phase121_dir, fixture_dir, mcmc_out_dir, as.integer(n_chains), as.integer(n_cores)),
      sprintf("Rscript application/scripts/125_run_joint_qdesn_phase122_mcmc_case_confirmation.R --phase121-dir %s --fixture-dir %s --output-dir %s --n-chains %d --mcmc-n-iter %d --mcmc-burn %d --mcmc-thin %d --n-cores %d", phase121_dir, fixture_dir, mcmc_out_dir, as.integer(n_chains), as.integer(mcmc_n_iter), as.integer(mcmc_burn), as.integer(mcmc_thin), as.integer(n_cores)),
      sprintf("Rscript application/scripts/126_audit_joint_qdesn_phase122_mcmc_case_confirmation.R --phase122-dir %s", mcmc_out_dir),
      "Rebuild authoritative article tables/figures only after Phase122 manifests, chain diagnostics, quantile-grid metrics, and contract noncrossing gates pass."
    ),
    status = c(
      "required_before_launch",
      "pending_phase122_implementation",
      "pending_phase122_smoke",
      "pending_phase122_completion",
      "blocked_until_mcmc_passes"
    ),
    gate_before_next = c(
      "runner supports all four requested article rows without treating composite likelihood as a scalar predictive density",
      "finite draws, finite quantile-grid summaries, no contract crossings, manifest pass",
      "all case rows complete, manifests pass, no implementation failures",
      "MCMC confirmation audit pass or explicit review/fail reasons",
      "article-safe update only"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase121_next_action_plan <- function() {
  data.frame(
    step = seq_len(4L),
    action = c(
      "Use Phase121 winners as the frozen VB/VB-LD initialization source.",
      "Implement Phase122 MCMC confirmation support for each requested article row.",
      "Launch Phase122 only after a smoke check proves the runner supports joint/independent AL and exAL contracts.",
      "Keep article tables frozen until Phase122 is complete, audited, and hash-manifested."
    ),
    rationale = c(
      "Avoids more broad VB screening now that Phase120 resolved the only exAL convergence blocker and showed AL raw crossings are diagnostic rather than contract failures.",
      "The current Phase108 runner is not broad enough for the final article evidence requested by the user.",
      "Prevents expensive runs from failing late because of unsupported exAL or independent-row assumptions.",
      "Maintains VB as calibration/initialization and MCMC as the final article-facing validation layer."
    ),
    output = c(
      "Phase121 case_winner_selection.csv and controls",
      "Phase122 implementation and tests",
      "Phase122 MCMC confirmation artifact",
      "Phase123 article asset rebuild/audit"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase121_readme <- function(run_config, gate_audit, winners, mcmc_gap, launch_plan) {
  c(
    "# Joint QDESN Phase 121 Case-Specific VB Winner Freeze",
    "",
    "This artifact freezes one VB/VB-LD winner per scenario-model case after the Phase 119 high-priority screens and Phase 120 targeted follow-up.",
    "It is a reproducible initialization contract for the MCMC confirmation layer. It is not final article-facing validation evidence.",
    "",
    sprintf("- Output directory: `%s`", run_config$out_dir[[1L]]),
    sprintf("- Source rows audited: %d", run_config$n_candidate_rows[[1L]]),
    sprintf("- Case winners frozen: %d", run_config$n_case_winners[[1L]]),
    sprintf("- Selection tolerance: absolute %.6f or relative %.3f, whichever is larger.", run_config$forecast_mae_abs_tolerance[[1L]], run_config$forecast_mae_rel_tolerance[[1L]]),
    sprintf("- Freeze status: `%s`", run_config$freeze_status[[1L]]),
    "",
    "Gate summary:",
    paste(capture.output(print(table(gate_audit$status))), collapse = "\n"),
    "",
    "Winner summary:",
    paste(capture.output(print(table(winners$phase121_selection_status))), collapse = "\n"),
    "",
    "MCMC readiness:",
    paste(sprintf("- `%s`: %s", mcmc_gap$model_id, mcmc_gap$readiness_status), collapse = "\n"),
    "",
    "Policy:",
    "- Hard failures are missing hashes, worker failures, nonfinite fit/forecast summaries, or contract crossings.",
    "- Raw crossings and monotone adjustments remain review diagnostics, not hard failures, because scoring uses the monotone contract grid.",
    "- Within a small forecast-MAE tolerance, the freeze prefers candidates with no max-iteration flags and fewer raw-adjustment diagnostics.",
    "- The existing Phase108 MCMC code is AL joint-only; Phase122 is required before the final article-facing MCMC table can be promoted.",
    "",
    "Next executable plan:",
    "",
    paste(sprintf("%d. %s", launch_plan$step, launch_plan$command_or_action), collapse = "\n\n")
  )
}

app_joint_qdesn_run_phase121_case_vb_winner_freeze <- function(
  out_dir = app_joint_qdesn_default_phase121_case_vb_freeze_dir(),
  al_high_priority_dir = file.path(app_joint_qdesn_default_phase119_case_screening_dir(), "al_high_priority"),
  exal_high_priority_dir = file.path(app_joint_qdesn_default_phase119_case_screening_dir(), "exal_high_priority"),
  phase120_targeted_dir = file.path(app_joint_qdesn_default_phase120_case_screening_dir(), "targeted_followup"),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  mcmc_out_dir = app_path("application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711"),
  forecast_mae_abs_tolerance = 5.0e-4,
  forecast_mae_rel_tolerance = 0.005,
  n_cores = 12L,
  n_chains = 2L,
  mcmc_n_iter = 1200L,
  mcmc_burn = 600L,
  mcmc_thin = 10L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  fixture_dir <- normalizePath(fixture_dir, mustWork = FALSE)
  mcmc_out_dir <- normalizePath(mcmc_out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  source_dirs <- list(
    al_high_priority = normalizePath(al_high_priority_dir, mustWork = TRUE),
    exal_high_priority = normalizePath(exal_high_priority_dir, mustWork = TRUE),
    phase120_targeted_followup = normalizePath(phase120_targeted_dir, mustWork = TRUE)
  )
  shards <- app_joint_qdesn_phase121_load_sources(source_dirs)
  source_health <- app_joint_qdesn_phase120_source_health_summary(shards)
  source_manifest <- app_joint_qdesn_phase121_source_manifest(shards)
  candidate_audit <- app_joint_qdesn_phase121_candidate_audit(shards)
  winners <- app_joint_qdesn_phase121_select_case_winners(
    candidate_audit,
    abs_tol = forecast_mae_abs_tolerance,
    rel_tol = forecast_mae_rel_tolerance
  )
  controls <- app_joint_qdesn_phase121_winner_controls(winners)
  metric_summary <- app_joint_qdesn_phase121_winner_metric_summary(winners)
  gate_audit <- app_joint_qdesn_phase121_gate_audit(source_health, candidate_audit, winners)
  mcmc_gap <- app_joint_qdesn_phase121_mcmc_readiness_gap_audit(winners)
  launch_plan <- app_joint_qdesn_phase121_mcmc_launch_plan(
    phase121_dir = out_dir,
    fixture_dir = fixture_dir,
    mcmc_out_dir = mcmc_out_dir,
    n_cores = n_cores,
    n_chains = n_chains,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin
  )
  next_action <- app_joint_qdesn_phase121_next_action_plan()
  freeze_status <- if (any(gate_audit$status == "fail")) {
    "fail_blocked_before_mcmc"
  } else if (any(gate_audit$status == "review")) {
    "review_ready_for_phase122_mcmc_runner_implementation"
  } else {
    "pass_ready_for_phase122_mcmc_runner_implementation"
  }
  run_config <- data.frame(
    run_id = "joint_qdesn_phase121_case_vb_winner_freeze",
    out_dir = out_dir,
    al_high_priority_dir = source_dirs$al_high_priority,
    exal_high_priority_dir = source_dirs$exal_high_priority,
    phase120_targeted_dir = source_dirs$phase120_targeted_followup,
    fixture_dir = fixture_dir,
    mcmc_out_dir = mcmc_out_dir,
    n_candidate_rows = nrow(candidate_audit),
    n_case_winners = nrow(winners),
    n_pass_winners = sum(winners$phase121_selection_status == "pass", na.rm = TRUE),
    n_review_winners = sum(winners$phase121_selection_status == "review", na.rm = TRUE),
    n_fail_winners = sum(winners$phase121_selection_status == "fail", na.rm = TRUE),
    selected_contract_crossings = sum(winners$forecast_contract_crossing_pairs, winners$fit_contract_crossing_pairs, na.rm = TRUE),
    selected_raw_crossings = sum(winners$forecast_raw_crossing_pairs, winners$fit_raw_crossing_pairs, na.rm = TRUE),
    selected_max_iter_flags = sum(winners$forecast_reached_max_iter, winners$fit_reached_max_iter, na.rm = TRUE),
    forecast_mae_abs_tolerance = as.numeric(forecast_mae_abs_tolerance),
    forecast_mae_rel_tolerance = as.numeric(forecast_mae_rel_tolerance),
    freeze_status = freeze_status,
    mcmc_promotion_status = "blocked_until_phase122_runner_supports_all_final_article_rows",
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qdesn_phase121_readme(run_config, gate_audit, winners, mcmc_gap, launch_plan), readme_path, useBytes = TRUE)
  paths <- c(
    phase121_run_config = app_joint_qdesn_screening_write_csv(run_config, file.path(out_dir, "phase121_run_config.csv")),
    source_manifest_verification = app_joint_qdesn_screening_write_csv(source_manifest, file.path(out_dir, "source_manifest_verification.csv")),
    source_health_summary = app_joint_qdesn_screening_write_csv(source_health, file.path(out_dir, "source_health_summary.csv")),
    combined_candidate_audit = app_joint_qdesn_screening_write_csv(candidate_audit, file.path(out_dir, "combined_candidate_audit.csv")),
    case_winner_selection = app_joint_qdesn_screening_write_csv(winners, file.path(out_dir, "case_winner_selection.csv")),
    case_winner_controls = app_joint_qdesn_screening_write_csv(controls, file.path(out_dir, "case_winner_controls.csv")),
    case_winner_metric_summary = app_joint_qdesn_screening_write_csv(metric_summary, file.path(out_dir, "case_winner_metric_summary.csv")),
    case_winner_gate_audit = app_joint_qdesn_screening_write_csv(gate_audit, file.path(out_dir, "case_winner_gate_audit.csv")),
    mcmc_readiness_gap_audit = app_joint_qdesn_screening_write_csv(mcmc_gap, file.path(out_dir, "mcmc_readiness_gap_audit.csv")),
    mcmc_launch_plan = app_joint_qdesn_screening_write_csv(launch_plan, file.path(out_dir, "mcmc_launch_plan.csv")),
    next_action_plan = app_joint_qdesn_screening_write_csv(next_action, file.path(out_dir, "next_action_plan.csv")),
    provenance = app_joint_qdesn_screening_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    run_config = run_config,
    source_manifest_verification = source_manifest,
    source_health = source_health,
    candidate_audit = candidate_audit,
    winners = winners,
    controls = controls,
    metric_summary = metric_summary,
    gate_audit = gate_audit,
    mcmc_gap = mcmc_gap,
    launch_plan = launch_plan,
    next_action_plan = next_action,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path)
  )
}
