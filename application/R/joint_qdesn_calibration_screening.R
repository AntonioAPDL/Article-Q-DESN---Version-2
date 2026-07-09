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
