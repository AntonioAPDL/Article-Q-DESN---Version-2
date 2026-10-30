# Phase162 eight-scenario exAL evidence classification without new sampling.

app_joint_exqdesn_phase162_cache_root <- function() {
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache"
}

app_joint_exqdesn_phase162_default_dirs <- function() {
  root <- app_joint_exqdesn_phase162_cache_root()
  list(
    phase150 = file.path(root, "joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727"),
    phase154_al = file.path(root, "joint_qdesn_phase154_mcmc_joint_al_20260730"),
    phase160 = file.path(root, "joint_qdesn_phase160_split_rhs_independent_confirmation_mcmc_20260805"),
    phase161 = file.path(root, "joint_qdesn_phase161_split_rhs_decision_gamma_audit_20260805"),
    output = file.path(root, "joint_qdesn_phase162_exal_scenario_classification_20260805")
  )
}

app_joint_exqdesn_phase162_read <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

app_joint_exqdesn_phase162_verify_manifest <- function(dir, source_id) {
  manifest_path <- file.path(dir, "artifact_manifest.csv")
  if (!file.exists(manifest_path)) stop(sprintf("Missing manifest for %s.", source_id), call. = FALSE)
  manifest <- app_joint_exqdesn_phase162_read(manifest_path)
  rows <- lapply(seq_len(nrow(manifest)), function(ii) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    actual <- if (file.exists(path)) app_sha256_file(path) else NA_character_
    data.frame(source_id = source_id, relative_path = manifest$relative_path[[ii]],
      expected_sha256 = manifest$sha256[[ii]], actual_sha256 = actual,
      status = if (!is.na(actual) && identical(actual, manifest$sha256[[ii]])) "pass" else "fail",
      stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

app_joint_exqdesn_phase162_article_comparison <- function(article_table) {
  x <- app_joint_exqdesn_phase162_read(article_table)
  take <- function(label, suffix) {
    z <- x[x$model_label == label, c("scenario_id", "scenario_class", "distribution_family", "dynamics_class",
      "mcmc_fit_truth_mae", "mcmc_forecast_truth_mae", "mcmc_forecast_check_loss_mean",
      "mcmc_forecast_crps_grid", "mcmc_forecast_raw_crossing_pairs",
      "mcmc_forecast_contract_crossing_pairs", "max_chain_to_pooled_normalized_distance",
      "vb_mcmc_max_normalized_distance", "gate_status", "source_candidate_id"), drop = FALSE]
    names(z)[-(1:4)] <- paste0(names(z)[-(1:4)], "_", suffix)
    z
  }
  out <- merge(take("Joint exQDESN RHS", "exal"), take("Joint QDESN RHS", "al"),
    by = c("scenario_id", "scenario_class", "distribution_family", "dynamics_class"))
  for (metric in c("fit_truth_mae", "forecast_truth_mae", "forecast_check_loss_mean", "forecast_crps_grid")) {
    out[[paste0(metric, "_ratio")]] <- out[[paste0("mcmc_", metric, "_exal")]] / out[[paste0("mcmc_", metric, "_al")]]
    out[[paste0(metric, "_delta")]] <- out[[paste0("mcmc_", metric, "_exal")]] - out[[paste0("mcmc_", metric, "_al")]]
  }
  out
}

app_joint_exqdesn_phase162_tau_comparison <- function(phase150, phase154_al) {
  e <- app_joint_exqdesn_phase162_read(file.path(phase150, "forecast_truth_distance_summary.csv"))
  a <- app_joint_exqdesn_phase162_read(file.path(phase154_al, "forecast_truth_distance_summary.csv"))
  e <- e[e$inference == "MCMC", c("scenario_id", "tau", "truth_mae", "truth_rmse", "truth_bias")]
  a <- a[a$inference == "MCMC", c("scenario_id", "tau", "truth_mae", "truth_rmse", "truth_bias")]
  out <- merge(e, a, by = c("scenario_id", "tau"), suffixes = c("_exal", "_al"))
  out$truth_mae_ratio <- out$truth_mae_exal / out$truth_mae_al
  out$truth_mae_delta <- out$truth_mae_exal - out$truth_mae_al
  out$abs_bias_delta <- abs(out$truth_bias_exal) - abs(out$truth_bias_al)
  out$tail_role <- ifelse(out$tau <= .1, "lower_tail", ifelse(out$tau >= .9, "upper_tail", "interior"))
  out
}

app_joint_exqdesn_phase162_classify <- function(comparison, phase160_summary) {
  out <- comparison
  detailed <- out$scenario_id %in% phase160_summary$scenario_id
  out$evidence_grade <- ifelse(detailed, "high_draw_level_confirmation", "moderate_compact_chain_summary")
  out$implementation_clean <- out$gate_status_exal %in% c("pass", "review") &
    out$mcmc_forecast_contract_crossing_pairs_exal == 0
  out$performance_class <- ifelse(out$forecast_truth_mae_ratio <= 1.05 & out$fit_truth_mae_ratio <= 1.10,
    "competitive_or_better", ifelse(out$forecast_truth_mae_ratio <= 1.10, "near_competitive", "material_oracle_path_gap"))
  out$sampler_evidence <- ifelse(detailed,
    ifelse(out$scenario_id == "nonlinear_reservoir_friendly", "modern_diagnostics_adequate_min_ess_174",
      "modern_diagnostics_adequate_min_ess_464"),
    "compact_chain_distances_only_no_modern_rhat_ess")
  out$limitation_class <- ifelse(!out$implementation_clean, "implementation_limited",
    ifelse(out$performance_class == "competitive_or_better", "already_adequate",
      ifelse(detailed, "specification_limited_with_sampler_ruled_out",
        "specification_priority_sampler_not_fully_identified")))
  priority <- c(asymmetric_laplace_tail = 4L, gaussian_mixture_bridge = 3L, laplace_bridge = 2L,
    nonlinear_reservoir_friendly = 1L, normal_bridge = 2L, persistent_heavy_tail = 4L,
    regime_shift = 2L, student_t_location_scale = 1L)
  out$next_priority <- unname(priority[out$scenario_id])
  out$recommended_action <- ifelse(out$limitation_class == "already_adequate", "freeze_no_new_screen",
    ifelse(detailed, "case_specific_desn_gamma_prior_calibration_not_longer_chains",
      "recover_or_generate_modern_chain_diagnostics_then_case_specific_calibration"))
  out[order(out$next_priority, out$scenario_id), ]
}

app_joint_exqdesn_phase162_run <- function(dirs = app_joint_exqdesn_phase162_default_dirs(),
  article_table = app_path("tables/joint_qdesn_article_validation_mcmc_balanced_scenario_summary.csv")) {
  for (name in c("phase150", "phase154_al", "phase160", "phase161")) dirs[[name]] <- normalizePath(dirs[[name]], mustWork = TRUE)
  app_ensure_dir(dirs$output)
  verification <- do.call(rbind, list(
    app_joint_exqdesn_phase162_verify_manifest(dirs$phase150, "phase150_article_exal"),
    app_joint_exqdesn_phase162_verify_manifest(dirs$phase154_al, "phase154_article_al"),
    app_joint_exqdesn_phase162_verify_manifest(dirs$phase161, "phase161_decision")))
  if (any(verification$status != "pass")) stop("Phase162 source verification failed.", call. = FALSE)
  comparison <- app_joint_exqdesn_phase162_article_comparison(article_table)
  tau <- app_joint_exqdesn_phase162_tau_comparison(dirs$phase150, dirs$phase154_al)
  phase160 <- app_joint_exqdesn_phase162_read(file.path(dirs$phase160, "confirmation_summary.csv"))
  classification <- app_joint_exqdesn_phase162_classify(comparison, phase160)
  experiments <- classification[classification$next_priority <= 2L & classification$limitation_class != "already_adequate",
    c("scenario_id", "next_priority", "limitation_class", "evidence_grade", "recommended_action")]
  experiments$selection_scope <- "scenario_specific"
  experiments$stage_1 <- ifelse(grepl("sampler_not", experiments$limitation_class),
    "modern_diagnostic_recovery_or_short_kernel_qualification", "case_specific_vb_vbld_local_calibration")
  experiments$stage_2 <- "independent_mcmc_only_if_vb_candidate_beats_current_article_row"
  experiments$prohibited_shortcut <- "do_not_assume_more_chains_changes_the_posterior_target"
  closed <- data.frame(direction = c("global_one_specification_screen", "split_rhs_rescreen",
      "longer_chains_as_predictive_remedy", "repeat_slice_width_only_screen", "fixed_gamma_zero_as_article_model"),
    status = "closed", rationale = c("study requires scenario-specific optimization",
      "Phase159-161 did not yield an article replacement", "mixing was adequate in detailed confirmations",
      "prior kernel experiments already tested this axis", "sensitivity reference changes the intended sampled-gamma model"),
    stringsAsFactors = FALSE)
  assessment <- data.frame(gate_status = "pass", scenarios = nrow(classification), tau_rows = nrow(tau),
    source_hash_failures = sum(verification$status != "pass"),
    already_adequate = sum(classification$limitation_class == "already_adequate"),
    high_priority = nrow(experiments), new_sampling_performed = FALSE,
    recommendation = "case_specific_calibration_only_after_evidence_grade_review", stringsAsFactors = FALSE)
  writeLines(c("# Phase162 exAL scenario classification", "",
    "This no-new-sampling audit compares article-facing Joint exQDESN and Joint QDESN evidence by scenario and tau.",
    "It separates oracle quantile-path recovery from check-loss/grid-CRPS behavior and grades diagnostic depth explicitly.",
    "Only nonlinear-reservoir and Student-t cases currently have retained draw-level modern diagnostics; other cases have compact chain summaries.",
    "The audit does not alter article assets or promote a new model."), file.path(dirs$output, "README.md"))
  outputs <- list(source_manifest_verification = verification, scenario_classification = classification,
    tau_performance_comparison = tau, next_experiment_registry = experiments,
    closed_direction_registry = closed, phase162_assessment = assessment,
    provenance = app_joint_qvp_provenance_rows())
  paths <- vapply(names(outputs), function(n) app_joint_qvp_write_csv(outputs[[n]], file.path(dirs$output, paste0(n, ".csv"))), character(1L))
  paths <- c(paths, README = file.path(dirs$output, "README.md"))
  manifest <- data.frame(label = names(paths), relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size), sha256 = vapply(paths, app_sha256_file, character(1L)), stringsAsFactors = FALSE)
  app_joint_qvp_write_csv(manifest, file.path(dirs$output, "artifact_manifest.csv"))
  list(output_dir = dirs$output, assessment = assessment, classification = classification, experiments = experiments)
}
