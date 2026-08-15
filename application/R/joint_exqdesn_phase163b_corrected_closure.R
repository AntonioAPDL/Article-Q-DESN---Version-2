# Phase163b inference-matched correction and no-promotion closure.

app_joint_exqdesn_phase163b_cache_root <- function() {
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache"
}

app_joint_exqdesn_phase163b_dirs <- function() {
  root <- app_joint_exqdesn_phase163b_cache_root()
  list(
    phase150 = file.path(root, "joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727"),
    phase163_readiness = file.path(root, "joint_qdesn_phase163_tail_calibration_readiness_20260806"),
    phase163 = file.path(root, "joint_qdesn_phase163_tail_calibration_vb_20260806"),
    output = file.path(root, "joint_qdesn_phase163b_corrected_closure_20260806")
  )
}

app_joint_exqdesn_phase163b_thresholds <- function() {
  list(
    forecast_gain_floor = 0.0025,
    forecast_gain_fraction = 0.025,
    tau095_gain_floor = 0.0025,
    tau095_gain_fraction = 0.025,
    fit_relative_guard = 0.05,
    check_loss_relative_guard = 0.01,
    crps_relative_guard = 0.01
  )
}

app_joint_exqdesn_phase163b_require_columns <- function(x, columns, label) {
  missing <- setdiff(columns, names(x))
  if (length(missing)) {
    stop(sprintf("%s is missing required columns: %s.", label, paste(missing, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}

app_joint_exqdesn_phase163b_unique_rows <- function(x, key, label) {
  if (anyDuplicated(x[[key]])) stop(sprintf("%s has duplicated %s values.", label, key), call. = FALSE)
  x
}

app_joint_exqdesn_phase163b_vb_benchmarks <- function(phase150_dir) {
  cases <- app_read_csv(file.path(phase150_dir, "mcmc_case_summary.csv"))
  forecast_truth <- app_read_csv(file.path(phase150_dir, "forecast_truth_distance_summary.csv"))
  fit_truth <- app_read_csv(file.path(phase150_dir, "fit_truth_distance_summary.csv"))
  forecast_crps <- app_read_csv(file.path(phase150_dir, "forecast_crps_grid_summary.csv"))
  fit_crps <- app_read_csv(file.path(phase150_dir, "fit_crps_grid_summary.csv"))

  app_joint_exqdesn_phase163b_require_columns(
    cases,
    c(
      "scenario_id", "source_candidate_id", "source_model_id", "vb_fit_truth_mae",
      "vb_forecast_truth_mae", "vb_fit_check_loss_mean", "vb_forecast_check_loss_mean",
      "vb_fit_contract_crossing_pairs", "vb_forecast_contract_crossing_pairs"
    ),
    "Phase150 case summary"
  )
  app_joint_exqdesn_phase163b_require_columns(
    forecast_truth, c("scenario_id", "source_candidate_id", "source_model_id", "inference", "tau", "truth_mae"),
    "Phase150 forecast truth summary"
  )
  app_joint_exqdesn_phase163b_require_columns(
    fit_truth, c("scenario_id", "source_candidate_id", "source_model_id", "inference", "tau", "truth_mae"),
    "Phase150 fit truth summary"
  )
  app_joint_exqdesn_phase163b_require_columns(
    forecast_crps, c("scenario_id", "source_candidate_id", "source_model_id", "inference", "crps_grid_mean"),
    "Phase150 forecast CRPS summary"
  )
  app_joint_exqdesn_phase163b_require_columns(
    fit_crps, c("scenario_id", "source_candidate_id", "source_model_id", "inference", "crps_grid_mean"),
    "Phase150 fit CRPS summary"
  )

  cases <- cases[cases$source_model_id == "joint_exqdesn_rhs_vb", , drop = FALSE]
  base <- cases[, c(
    "scenario_id", "source_candidate_id", "source_model_id", "vb_fit_truth_mae",
    "vb_forecast_truth_mae", "vb_fit_check_loss_mean", "vb_forecast_check_loss_mean",
    "vb_fit_contract_crossing_pairs", "vb_forecast_contract_crossing_pairs"
  ), drop = FALSE]
  names(base)[names(base) == "source_candidate_id"] <- "phase150_vb_candidate_id"
  names(base)[names(base) == "source_model_id"] <- "phase150_vb_model_id"
  base <- app_joint_exqdesn_phase163b_unique_rows(base, "scenario_id", "Phase150 VB case summary")

  select_tau095 <- function(x, prefix) {
    out <- x[
      x$inference == "VB-LD" & x$source_model_id == "joint_exqdesn_rhs_vb" & abs(x$tau - 0.95) < 1e-8,
      c("scenario_id", "source_candidate_id", "truth_mae"),
      drop = FALSE
    ]
    names(out)[2:3] <- c(paste0(prefix, "_tau095_candidate_id"), paste0(prefix, "_tau095_truth_mae"))
    app_joint_exqdesn_phase163b_unique_rows(out, "scenario_id", paste(prefix, "tau=.95 benchmark"))
  }
  select_crps <- function(x, prefix) {
    out <- x[
      x$inference == "VB-LD" & x$source_model_id == "joint_exqdesn_rhs_vb",
      c("scenario_id", "source_candidate_id", "crps_grid_mean"),
      drop = FALSE
    ]
    names(out)[2:3] <- c(paste0(prefix, "_crps_candidate_id"), paste0(prefix, "_crps_grid"))
    app_joint_exqdesn_phase163b_unique_rows(out, "scenario_id", paste(prefix, "CRPS benchmark"))
  }

  base <- Reduce(
    function(x, y) merge(x, y, by = "scenario_id", all = FALSE),
    list(
      base,
      select_tau095(forecast_truth, "vb_forecast"),
      select_tau095(fit_truth, "vb_fit"),
      select_crps(forecast_crps, "vb_forecast"),
      select_crps(fit_crps, "vb_fit")
    )
  )
  candidate_columns <- grep("_candidate_id$", names(base), value = TRUE)
  candidate_match <- vapply(seq_len(nrow(base)), function(ii) {
    length(unique(as.character(base[ii, candidate_columns, drop = TRUE]))) == 1L
  }, logical(1L))
  if (!all(candidate_match)) stop("Phase150 VB benchmark candidate provenance is inconsistent.", call. = FALSE)
  base$benchmark_inference <- "VB-LD"
  base$benchmark_role <- "inference_matched_phase150_vb"
  base[order(base$scenario_id), , drop = FALSE]
}

app_joint_exqdesn_phase163b_candidate_metrics <- function(phase163_dir) {
  registry <- app_read_csv(file.path(phase163_dir, "candidate_registry.csv"))
  fit <- app_read_csv(file.path(phase163_dir, "fit_model_metric_summary.csv"))
  forecast <- app_read_csv(file.path(phase163_dir, "forecast_model_metric_summary.csv"))
  forecast_tau <- app_read_csv(file.path(phase163_dir, "forecast_tau_metric_summary.csv"))
  manifest_rows <- app_read_csv(file.path(phase163_dir, "candidate_manifest_verification.csv"))
  failures <- app_read_csv(file.path(phase163_dir, "scenario_failure_summary.csv"))

  app_joint_exqdesn_phase163b_require_columns(
    registry,
    c(
      "candidate_id", "candidate_label", "scenario_ids", "source_phase150_candidate_id",
      "phase163_role", "tau0", "zeta2", "alpha_prior_sd", "gamma_init_policy"
    ),
    "Phase163 candidate registry"
  )
  metric_columns <- c(
    "candidate_id", "truth_mae", "check_loss_mean", "crps_grid_mean", "contract_crossing_pairs",
    "finite_quantiles", "finite_scores", "gate_status", "reached_max_iter"
  )
  app_joint_exqdesn_phase163b_require_columns(fit, metric_columns, "Phase163 fit summary")
  app_joint_exqdesn_phase163b_require_columns(forecast, metric_columns, "Phase163 forecast summary")
  app_joint_exqdesn_phase163b_require_columns(
    forecast_tau, c("candidate_id", "tau", "truth_mae", "truth_rmse", "check_loss_mean"),
    "Phase163 forecast tau summary"
  )
  app_joint_exqdesn_phase163b_require_columns(manifest_rows, c("candidate_id", "stage", "status"), "Phase163 nested manifest verification")

  keep_registry <- c(
    "candidate_id", "candidate_label", "scenario_ids", "source_phase150_candidate_id",
    "phase163_role", "tau0", "zeta2", "alpha_prior_sd", "gamma_init_policy"
  )
  out <- registry[, keep_registry, drop = FALSE]
  names(out)[names(out) == "scenario_ids"] <- "scenario_id"

  stage_metrics <- function(x, stage) {
    z <- x[x$model_id == "joint_exqdesn_rhs_vb", metric_columns, drop = FALSE]
    names(z)[-1L] <- paste0(names(z)[-1L], "_", stage)
    app_joint_exqdesn_phase163b_unique_rows(z, "candidate_id", paste("Phase163", stage, "summary"))
  }
  out <- merge(out, stage_metrics(fit, "fit"), by = "candidate_id", all = FALSE)
  out <- merge(out, stage_metrics(forecast, "forecast"), by = "candidate_id", all = FALSE)

  tau095 <- forecast_tau[
    forecast_tau$model_id == "joint_exqdesn_rhs_vb" & abs(forecast_tau$tau - 0.95) < 1e-8,
    c("candidate_id", "truth_mae", "truth_rmse", "check_loss_mean"),
    drop = FALSE
  ]
  names(tau095)[-1L] <- paste0("forecast_tau095_", names(tau095)[-1L])
  tau095 <- app_joint_exqdesn_phase163b_unique_rows(tau095, "candidate_id", "Phase163 forecast tau=.95 summary")
  out <- merge(out, tau095, by = "candidate_id", all = FALSE)

  manifest_ok <- aggregate(
    manifest_rows$status == "pass",
    by = list(candidate_id = manifest_rows$candidate_id),
    FUN = all
  )
  names(manifest_ok)[2L] <- "nested_manifests_verified"
  out <- merge(out, manifest_ok, by = "candidate_id", all = FALSE)
  out$worker_failure_count <- vapply(out$candidate_id, function(id) sum(failures$candidate_id == id), integer(1L))

  if (nrow(out) != nrow(registry)) stop("Phase163 candidate summaries do not cover the full registry.", call. = FALSE)
  if (anyDuplicated(out$candidate_id)) stop("Phase163 candidate summaries are not unique.", call. = FALSE)
  out
}

app_joint_exqdesn_phase163b_failure_reason <- function(x) {
  labels <- c(
    gate_source_candidate_match = "phase150_candidate_mismatch",
    gate_implementation = "implementation_or_manifest_gate",
    gate_fit_guard = "fit_mae_guard",
    gate_check_loss_guard = "forecast_check_loss_guard",
    gate_crps_guard = "forecast_crps_guard",
    gate_forecast_improvement = "aggregate_forecast_mae_improvement",
    gate_tau095_improvement = "tau095_forecast_mae_improvement"
  )
  apply(x[, names(labels), drop = FALSE], 1L, function(row) {
    failed <- labels[!as.logical(row)]
    if (length(failed)) paste(failed, collapse = ";") else "all_gates_passed"
  })
}

app_joint_exqdesn_phase163b_rank <- function(candidates, benchmarks,
  thresholds = app_joint_exqdesn_phase163b_thresholds()) {
  out <- merge(candidates, benchmarks, by = "scenario_id", all = FALSE)
  if (nrow(out) != nrow(candidates)) stop("Inference-matched benchmarks do not cover every Phase163 candidate.", call. = FALSE)

  numeric_metrics <- c(
    "truth_mae_fit", "truth_mae_forecast", "check_loss_mean_fit", "check_loss_mean_forecast",
    "crps_grid_mean_fit", "crps_grid_mean_forecast", "forecast_tau095_truth_mae",
    "vb_fit_truth_mae", "vb_forecast_truth_mae", "vb_fit_check_loss_mean",
    "vb_forecast_check_loss_mean", "vb_fit_crps_grid", "vb_forecast_crps_grid",
    "vb_forecast_tau095_truth_mae"
  )
  app_joint_exqdesn_phase163b_require_columns(out, numeric_metrics, "Phase163b joined candidate table")
  finite_matrix <- is.finite(as.matrix(out[, numeric_metrics, drop = FALSE]))
  out$all_metrics_finite <- apply(finite_matrix, 1L, all)

  out$forecast_mae_gain <- out$vb_forecast_truth_mae - out$truth_mae_forecast
  out$forecast_mae_gain_required <- pmax(
    thresholds$forecast_gain_floor,
    thresholds$forecast_gain_fraction * out$vb_forecast_truth_mae
  )
  out$tau095_mae_gain <- out$vb_forecast_tau095_truth_mae - out$forecast_tau095_truth_mae
  out$tau095_mae_gain_required <- pmax(
    thresholds$tau095_gain_floor,
    thresholds$tau095_gain_fraction * out$vb_forecast_tau095_truth_mae
  )
  out$fit_mae_relative_change <- out$truth_mae_fit / out$vb_fit_truth_mae - 1
  out$forecast_check_loss_relative_change <- out$check_loss_mean_forecast / out$vb_forecast_check_loss_mean - 1
  out$forecast_crps_relative_change <- out$crps_grid_mean_forecast / out$vb_forecast_crps_grid - 1

  out$gate_source_candidate_match <- out$source_phase150_candidate_id == out$phase150_vb_candidate_id
  out$gate_implementation <- out$all_metrics_finite & out$nested_manifests_verified & out$worker_failure_count == 0L &
    out$finite_quantiles_fit & out$finite_scores_fit & out$finite_quantiles_forecast & out$finite_scores_forecast &
    out$gate_status_fit == "pass" & out$gate_status_forecast == "pass" &
    out$contract_crossing_pairs_fit == 0 & out$contract_crossing_pairs_forecast == 0
  out$gate_fit_guard <- out$fit_mae_relative_change <= thresholds$fit_relative_guard
  out$gate_check_loss_guard <- out$forecast_check_loss_relative_change <= thresholds$check_loss_relative_guard
  out$gate_crps_guard <- out$forecast_crps_relative_change <= thresholds$crps_relative_guard
  out$gate_forecast_improvement <- out$forecast_mae_gain >= out$forecast_mae_gain_required
  out$gate_tau095_improvement <- out$tau095_mae_gain >= out$tau095_mae_gain_required
  out$eligible_for_mcmc_confirmation <- out$gate_source_candidate_match & out$gate_implementation &
    out$gate_fit_guard & out$gate_check_loss_guard & out$gate_crps_guard &
    out$gate_forecast_improvement & out$gate_tau095_improvement
  out$promotion_status <- ifelse(
    out$eligible_for_mcmc_confirmation,
    "eligible_for_independent_mcmc_confirmation",
    "not_eligible"
  )
  out$failed_gates <- app_joint_exqdesn_phase163b_failure_reason(out)

  out <- out[order(
    out$scenario_id,
    -as.integer(out$eligible_for_mcmc_confirmation),
    out$truth_mae_forecast,
    out$forecast_tau095_truth_mae,
    out$candidate_id
  ), , drop = FALSE]
  out$scenario_rank <- ave(seq_len(nrow(out)), out$scenario_id, FUN = seq_along)
  rownames(out) <- NULL
  out
}

app_joint_exqdesn_phase163b_complete_phase163_manifest <- function(phase163_dir) {
  declared <- app_read_csv(file.path(phase163_dir, "artifact_manifest.csv"))
  app_joint_exqdesn_phase163b_require_columns(declared, c("label", "relative_path", "size_bytes", "sha256"), "Phase163 manifest")
  extras <- c("phase163_candidate_ranking.csv", "phase163_scenario_winners.csv", "phase163_result_assessment.csv")
  extra_present <- extras[file.exists(file.path(phase163_dir, extras))]
  inventory <- data.frame(
    label = c(as.character(declared$label), sub("\\.csv$", "", extra_present)),
    relative_path = c(as.character(declared$relative_path), extra_present),
    source_role = c(rep("canonical_phase163_manifest", nrow(declared)), rep("legacy_audit_superseded_by_phase163b", length(extra_present))),
    stringsAsFactors = FALSE
  )
  paths <- file.path(phase163_dir, inventory$relative_path)
  inventory$file_exists <- file.exists(paths)
  inventory$size_bytes <- ifelse(inventory$file_exists, as.numeric(file.info(paths)$size), NA_real_)
  inventory$sha256 <- NA_character_
  inventory$sha256[inventory$file_exists] <- vapply(paths[inventory$file_exists], app_sha256_file, character(1L))
  inventory$status <- ifelse(inventory$file_exists & nzchar(inventory$sha256), "pass", "fail")
  inventory
}

app_joint_exqdesn_phase163b_closed_directions <- function() {
  data.frame(
    direction = c(
      "phase163_scalar_tau0_shrink_with_wider_alpha",
      "phase163_scalar_tau0_relax_with_wider_alpha",
      "phase163_tighter_rhs_slab_with_wider_alpha",
      "phase163_wider_rhs_slab_with_wider_alpha",
      "phase163_candidates_to_mcmc"
    ),
    status = c(rep("closed_no_promotion", 4L), "not_authorized"),
    evidence = c(
      rep("No candidate improved inference-matched Phase150 VB aggregate forecast MAE and tau=.95 MAE jointly.", 4L),
      "Zero of twenty candidates satisfies the corrected VB promotion contract."
    ),
    scope = "five_case_specific_joint_exqdesn_scenarios",
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase163b_next_methodology <- function() {
  data.frame(
    direction = c(
      "retain_phase150_article_rows",
      "quantile_specific_alpha_prior_scale",
      "sampled_gamma_regularization_contract",
      "quantile_specific_composite_weighting"
    ),
    readiness = c("ready", "design_audit_required", "design_audit_required", "theory_and_design_audit_required"),
    automatic_launch = FALSE,
    rationale = c(
      "Phase163 provides no inference-matched VB replacement.",
      "Phase163 changed only scalar alpha spread; a tau-specific prior is a distinct model control and needs identifiability and implementation tests.",
      "Any gamma regularization must define the same posterior target in VB-LD and MCMC before screening.",
      "Changing quantile weights changes the composite objective and should not be introduced as an unregistered tuning shortcut."
    ),
    required_before_compute = c(
      "none",
      "prior schema, equations, deterministic fixture test, VB-LD/MCMC parity test",
      "prior definition, constrained support, sampler test, posterior-target parity test",
      "estimand rationale, score alignment, registry schema, sensitivity design"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase163b_run <- function(
  dirs = app_joint_exqdesn_phase163b_dirs(),
  thresholds = app_joint_exqdesn_phase163b_thresholds()) {
  for (name in c("phase150", "phase163_readiness", "phase163")) {
    dirs[[name]] <- normalizePath(dirs[[name]], mustWork = TRUE)
  }
  app_ensure_dir(dirs$output)

  verification <- do.call(rbind, list(
    app_joint_exqdesn_phase162_verify_manifest(dirs$phase150, "phase150_confirmation"),
    app_joint_exqdesn_phase162_verify_manifest(dirs$phase163_readiness, "phase163_readiness"),
    app_joint_exqdesn_phase162_verify_manifest(dirs$phase163, "phase163_screening")
  ))
  if (any(verification$status != "pass")) stop("Phase163b source manifest verification failed.", call. = FALSE)

  benchmarks <- app_joint_exqdesn_phase163b_vb_benchmarks(dirs$phase150)
  candidates <- app_joint_exqdesn_phase163b_candidate_metrics(dirs$phase163)
  benchmarks <- benchmarks[benchmarks$scenario_id %in% candidates$scenario_id, , drop = FALSE]
  ranking <- app_joint_exqdesn_phase163b_rank(candidates, benchmarks, thresholds)
  winners <- ranking[ranking$scenario_rank == 1L, , drop = FALSE]
  complete_manifest <- app_joint_exqdesn_phase163b_complete_phase163_manifest(dirs$phase163)
  if (any(complete_manifest$status != "pass")) stop("Phase163 complete source inventory is not finite and complete.", call. = FALSE)

  legacy_path <- file.path(dirs$phase163, "phase163_result_assessment.csv")
  legacy <- if (file.exists(legacy_path)) app_read_csv(legacy_path) else data.frame(eligible = NA_integer_)
  legacy_eligible <- if ("eligible" %in% names(legacy) && nrow(legacy)) as.integer(legacy$eligible[[1L]]) else NA_integer_
  corrected_eligible <- sum(ranking$eligible_for_mcmc_confirmation)
  legacy_correction <- data.frame(
    legacy_eligible_candidates = legacy_eligible,
    corrected_eligible_candidates = corrected_eligible,
    correction_status = if (!is.na(legacy_eligible) && legacy_eligible != corrected_eligible) "legacy_decision_superseded" else "consistent",
    root_cause = "legacy audit compared Phase163 VB with Phase150 MCMC and omitted the documented tau=.95 gate",
    authoritative_decision_source = "phase163b_assessment.csv",
    stringsAsFactors = FALSE
  )

  implementation_clean <- all(ranking$gate_implementation) && all(ranking$gate_source_candidate_match)
  assessment <- data.frame(
    gate_status = if (implementation_clean && all(verification$status == "pass")) "pass" else "fail",
    scenarios = length(unique(ranking$scenario_id)),
    candidates = nrow(ranking),
    source_hash_failures = sum(verification$status != "pass"),
    nested_manifest_failures = sum(!ranking$nested_manifests_verified),
    worker_failures = sum(ranking$worker_failure_count),
    nonfinite_candidates = sum(!ranking$all_metrics_finite),
    contract_crossing_pairs = sum(ranking$contract_crossing_pairs_fit + ranking$contract_crossing_pairs_forecast),
    legacy_eligible_candidates = legacy_eligible,
    corrected_eligible_candidates = corrected_eligible,
    new_sampling_performed = FALSE,
    mcmc_authorized = corrected_eligible > 0L,
    scientific_decision = if (corrected_eligible > 0L) "review_eligible_candidates" else "no_promotion_close_phase163_region",
    recommendation = if (corrected_eligible > 0L) {
      "independent_mcmc_only_for_corrected_eligible_candidates"
    } else {
      "retain_phase150_article_rows_and_require_methodology_audit_before_new_compute"
    },
    stringsAsFactors = FALSE
  )
  if (assessment$gate_status != "pass") stop("Phase163b implementation closure gates failed.", call. = FALSE)

  threshold_table <- data.frame(
    threshold_name = names(thresholds),
    value = as.numeric(unlist(thresholds, use.names = FALSE)),
    role = c(
      "minimum absolute aggregate forecast-MAE gain",
      "minimum relative aggregate forecast-MAE gain",
      "minimum absolute tau=.95 forecast-MAE gain",
      "minimum relative tau=.95 forecast-MAE gain",
      "maximum relative fit-MAE deterioration",
      "maximum relative forecast check-loss deterioration",
      "maximum relative forecast grid-CRPS deterioration"
    ),
    stringsAsFactors = FALSE
  )
  closed <- app_joint_exqdesn_phase163b_closed_directions()
  next_methodology <- app_joint_exqdesn_phase163b_next_methodology()

  readme <- c(
    "# Phase163b corrected closure",
    "",
    "This stage performs no new fitting or sampling. It corrects the Phase163 promotion audit by comparing VB/VB-LD candidates with the inference-matched Phase150 VB-LD baselines.",
    "",
    sprintf("All %d candidates are finite, hash-verified, and contract-noncrossing; %d satisfy the corrected promotion contract.", nrow(ranking), corrected_eligible),
    "The contract requires simultaneous aggregate forecast-MAE and tau=.95 forecast-MAE gains, fit-MAE preservation, check-loss and grid-CRPS guards, exact Phase150 candidate provenance, and clean implementation gates.",
    "",
    "The legacy Phase163 result is superseded because it compared VB candidates with MCMC article rows and did not implement its documented tau=.95 gate.",
    "No Phase163 candidate is authorized for MCMC confirmation. Phase150 remains the article source of truth pending a separately reviewed methodology extension."
  )
  writeLines(readme, file.path(dirs$output, "README.md"))

  outputs <- list(
    source_manifest_verification = verification,
    phase163_complete_manifest = complete_manifest,
    inference_matched_vb_benchmarks = benchmarks,
    corrected_candidate_ranking = ranking,
    corrected_scenario_winners = winners,
    promotion_thresholds = threshold_table,
    legacy_gate_correction = legacy_correction,
    closed_direction_registry = closed,
    next_methodology_readiness = next_methodology,
    phase163b_assessment = assessment,
    provenance = app_joint_qvp_provenance_rows()
  )
  paths <- vapply(names(outputs), function(name) {
    app_joint_qvp_write_csv(outputs[[name]], file.path(dirs$output, paste0(name, ".csv")))
  }, character(1L))
  paths <- c(paths, README = file.path(dirs$output, "README.md"))
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  app_joint_qvp_write_csv(manifest, file.path(dirs$output, "artifact_manifest.csv"))

  list(
    output_dir = normalizePath(dirs$output, mustWork = TRUE),
    assessment = assessment,
    ranking = ranking,
    winners = winners,
    legacy_correction = legacy_correction
  )
}
