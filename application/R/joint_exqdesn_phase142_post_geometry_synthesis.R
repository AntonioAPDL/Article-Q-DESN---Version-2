# Phase142 synthesis after sampled-gamma geometry screens.

app_joint_exqdesn_phase142_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase142_post_geometry_synthesis_20260722")
}

app_joint_exqdesn_phase142_default_regularized_dir <- function() {
  app_path("application/cache/joint_qdesn_phase142_regularized_gamma_screen_20260722")
}

app_joint_exqdesn_phase142_packet_files <- function() {
  c(
    "artifact_manifest.csv",
    "run_config.csv",
    "phase136_case_assessment.csv",
    "phase136_best_variant_by_case.csv",
    "phase136_chain_jobs.csv",
    "phase136_chain_worker_failures.csv",
    "phase136_case_variant_prep_failures.csv",
    "runtime_summary.csv"
  )
}

app_joint_exqdesn_phase142_load_packet <- function(dir, packet_id) {
  dir <- normalizePath(dir, mustWork = TRUE)
  required <- app_joint_exqdesn_phase142_packet_files()
  missing <- required[!file.exists(file.path(dir, required))]
  if (length(missing)) {
    stop(sprintf("Packet '%s' is missing required files: %s", packet_id, paste(missing, collapse = ", ")), call. = FALSE)
  }
  list(
    packet_id = packet_id,
    dir = dir,
    manifest = app_joint_qdesn_phase108_manifest_verify(dir, packet_id),
    run_config = app_read_csv(file.path(dir, "run_config.csv")),
    assessment = app_read_csv(file.path(dir, "phase136_case_assessment.csv")),
    best = app_read_csv(file.path(dir, "phase136_best_variant_by_case.csv")),
    chain_jobs = app_read_csv(file.path(dir, "phase136_chain_jobs.csv")),
    worker_failures = app_read_csv(file.path(dir, "phase136_chain_worker_failures.csv")),
    prep_failures = app_read_csv(file.path(dir, "phase136_case_variant_prep_failures.csv")),
    runtime = app_read_csv(file.path(dir, "runtime_summary.csv"))
  )
}

app_joint_exqdesn_phase142_packet_summary <- function(packet) {
  d <- packet$assessment
  data.frame(
    packet_id = packet$packet_id,
    packet_dir = packet$dir,
    manifest_rows = nrow(packet$manifest),
    manifest_hash_pass = sum(packet$manifest$status == "pass"),
    case_variant_rows = nrow(d),
    chain_jobs = nrow(packet$chain_jobs),
    worker_failures = nrow(packet$worker_failures),
    prep_failures = nrow(packet$prep_failures),
    gate_pass = sum(d$phase136_gate_status == "pass", na.rm = TRUE),
    gate_review = sum(d$phase136_gate_status == "review", na.rm = TRUE),
    gate_fail = sum(d$phase136_gate_status == "fail", na.rm = TRUE),
    fit_raw_crossings = sum(d$mcmc_fit_raw_crossing_pairs, na.rm = TRUE),
    forecast_raw_crossings = sum(d$mcmc_forecast_raw_crossing_pairs, na.rm = TRUE),
    fit_contract_crossings = sum(d$mcmc_fit_contract_crossing_pairs, na.rm = TRUE),
    forecast_contract_crossings = sum(d$mcmc_forecast_contract_crossing_pairs, na.rm = TRUE),
    max_gamma_rhat = if ("max_gamma_rhat" %in% names(d)) suppressWarnings(max(d$max_gamma_rhat, na.rm = TRUE)) else NA_real_,
    min_gamma_rough_ess_total = if ("min_gamma_rough_ess_total" %in% names(d)) suppressWarnings(min(d$min_gamma_rough_ess_total, na.rm = TRUE)) else NA_real_,
    max_gamma_lag1_autocorrelation = if ("max_gamma_lag1_autocorrelation" %in% names(d)) suppressWarnings(max(d$max_gamma_lag1_autocorrelation, na.rm = TRUE)) else NA_real_,
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase142_compare_packets <- function(fixed, primary, focus) {
  common <- Reduce(intersect, list(fixed$assessment$case_id, primary$best$case_id, focus$best$case_id))
  if (!length(common)) stop("No common case ids across fixed, primary, and focus packets.", call. = FALSE)
  mk <- function(d, suffix) {
    cols <- c(
      "case_id", "scenario_id", "scenario_class", "distribution_family", "dynamics_class",
      "source_model_id", "model_id", "fit_structure", "variant_id",
      "mcmc_forecast_truth_mae", "mcmc_fit_truth_mae",
      "mcmc_forecast_check_loss_mean", "mcmc_fit_check_loss_mean",
      "mcmc_forecast_raw_crossing_pairs", "mcmc_fit_raw_crossing_pairs",
      "mcmc_forecast_contract_crossing_pairs", "mcmc_fit_contract_crossing_pairs",
      "max_rhat", "max_gamma_rhat", "min_gamma_rough_ess_total",
      "max_gamma_lag1_autocorrelation", "phase136_gate_status"
    )
    d <- d[d$case_id %in% common, intersect(cols, names(d)), drop = FALSE]
    names(d)[names(d) != "case_id"] <- paste0(names(d)[names(d) != "case_id"], suffix)
    d
  }
  out <- Reduce(function(x, y) merge(x, y, by = "case_id", all = TRUE, sort = FALSE), list(
    mk(fixed$assessment, "_fixed"),
    mk(primary$best, "_primary"),
    mk(focus$best, "_focus")
  ))
  out$focus_minus_fixed_forecast_mae <- out$mcmc_forecast_truth_mae_focus - out$mcmc_forecast_truth_mae_fixed
  out$focus_minus_primary_forecast_mae <- out$mcmc_forecast_truth_mae_focus - out$mcmc_forecast_truth_mae_primary
  out$focus_minus_fixed_fit_mae <- out$mcmc_fit_truth_mae_focus - out$mcmc_fit_truth_mae_fixed
  out$focus_minus_fixed_forecast_check <- out$mcmc_forecast_check_loss_mean_focus - out$mcmc_forecast_check_loss_mean_fixed
  out$focus_beats_fixed_forecast_mae <- out$focus_minus_fixed_forecast_mae < 0
  out$focus_beats_primary_forecast_mae <- out$focus_minus_primary_forecast_mae < 0
  out$focus_beats_fixed_fit_mae <- out$focus_minus_fixed_fit_mae < 0
  out$focus_beats_fixed_forecast_check <- out$focus_minus_fixed_forecast_check < 0
  out
}

app_joint_exqdesn_phase142_decision_summary <- function(packet_summary, comparison) {
  hard_fail <- any(packet_summary$manifest_hash_pass != packet_summary$manifest_rows) ||
    any(packet_summary$worker_failures > 0) ||
    any(packet_summary$prep_failures > 0) ||
    any(packet_summary$fit_contract_crossings + packet_summary$forecast_contract_crossings > 0)
  focus_beats_fixed <- sum(comparison$focus_beats_fixed_forecast_mae, na.rm = TRUE)
  focus_beats_primary <- sum(comparison$focus_beats_primary_forecast_mae, na.rm = TRUE)
  data.frame(
    decision_id = "phase142_post_geometry_synthesis",
    gate_status = if (hard_fail) "fail" else "review",
    sampled_gamma_geometry_decision = if (hard_fail) "blocked_by_implementation_gate" else "reject_geometry_only_for_article_promotion",
    fixed_gamma_zero_decision = if (hard_fail) "blocked" else "current_strongest_exal_reference",
    next_stage_decision = if (hard_fail) "repair_artifacts_before_new_launch" else "prepare_regularized_gamma_screen",
    focus_beats_fixed_forecast_cases = focus_beats_fixed,
    focus_common_cases = nrow(comparison),
    focus_beats_primary_forecast_cases = focus_beats_primary,
    interpretation = paste(
      "Phase141 geometry screens completed cleanly and removed crossings,",
      "but best sampled-gamma focus variants do not beat fixed-gamma-zero on any common forecast MAE case.",
      "The next useful experiment is gamma shrinkage/regularization, not another slice-width rerun."
    ),
    article_action = "do_not_touch_article_tables_until_regularized_gamma_or_final_fixed_gamma_decision_is_audited",
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase142_regularized_registry <- function(comparison) {
  cases <- comparison[, c(
    "case_id", "scenario_id_fixed", "scenario_class_fixed", "distribution_family_fixed",
    "dynamics_class_fixed", "source_model_id_fixed", "fit_structure_fixed",
    "mcmc_forecast_truth_mae_fixed", "mcmc_forecast_truth_mae_focus",
    "variant_id_focus"
  ), drop = FALSE]
  names(cases) <- sub("_fixed$", "", names(cases))
  variants <- data.frame(
    phase142_variant_id = c("logit_prior_sd_0p25", "logit_prior_sd_0p5", "logit_prior_sd_1p0"),
    gamma_update = "logit_slice",
    gamma_prior_type = "logit_normal",
    gamma_prior_center = 0,
    gamma_prior_sd_eta = c(0.25, 0.5, 1.0),
    logit_eta_width = 1,
    rationale = c(
      "Aggressive shrinkage around the AL-like gamma-zero reference.",
      "Moderate shrinkage around the AL-like gamma-zero reference.",
      "Weak shrinkage; checks whether regularization can retain flexibility without fixed gamma."
    ),
    stringsAsFactors = FALSE
  )
  rows <- list()
  for (ii in seq_len(nrow(cases))) {
    for (jj in seq_len(nrow(variants))) {
      rows[[length(rows) + 1L]] <- cbind(
        data.frame(
          phase142_candidate_id = paste(cases$case_id[[ii]], variants$phase142_variant_id[[jj]], sep = "__"),
          cases[ii, , drop = FALSE],
          stringsAsFactors = FALSE
        ),
        variants[jj, , drop = FALSE],
        stringsAsFactors = FALSE
      )
    }
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase142_launch_plan <- function(registry, out_dir_regularized, n_cores = 24L) {
  case_ids <- paste(unique(registry$case_id), collapse = ",")
  variant_ids <- paste(unique(registry$phase142_variant_id), collapse = ",")
  cmd <- paste(
    "Rscript application/scripts/145_run_joint_exqdesn_phase136_gamma_kernel_packet.R",
    sprintf("--output-dir '%s'", out_dir_regularized),
    "--phase135-screening-dir 'application/cache/joint_qdesn_phase135_matched_exal_screening_20260715'",
    "--phase135-audit-dir 'application/cache/joint_qdesn_phase135_matched_exal_screening_20260715/phase135_result_audit'",
    "--fixture-dir 'application/cache/joint_qdesn_simulation_dgp_fixtures_20260706'",
    sprintf("--case-ids '%s'", case_ids),
    sprintf("--variant-ids '%s'", variant_ids),
    "--bounded-width-multiplier 4",
    "--logit-eta-width 1",
    "--gamma-slice-max-steps 100",
    "--n-chains 8",
    "--mcmc-n-iter 12000",
    "--mcmc-burn 3000",
    "--mcmc-thin 1",
    "--mcmc-seed-offset 15200",
    "--chain-seed-stride 100",
    "--sigma-upper-multiplier 50",
    "--distance-pass 5",
    "--chain-pass 5",
    sprintf("--n-cores %s", as.integer(n_cores)),
    "--vb-n-cores 5",
    "--gamma-init-mode vb_jittered",
    "--gamma-jitter-fraction 0.05",
    "--trace-write-stride 50",
    "--save-rdata false",
    "--dry-run false"
  )
  data.frame(
    launch_id = "phase142_regularized_gamma_screen",
    out_dir = out_dir_regularized,
    case_ids = case_ids,
    variant_ids = variant_ids,
    n_cases = length(unique(registry$case_id)),
    n_variants = length(unique(registry$phase142_variant_id)),
    total_chain_jobs = length(unique(registry$case_id)) * length(unique(registry$phase142_variant_id)) * 8L,
    n_cores = as.integer(n_cores),
    command = cmd,
    tmux_session = "joint_qdesn_phase142_regularized_gamma_screen_20260722",
    log_path = paste0(out_dir_regularized, "_tmux.log"),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase142_readme <- function(decision, launch_plan) {
  c(
    "# Joint exQDESN Phase142 Post-Geometry Synthesis",
    "",
    "This artifact freezes the evidence from the Phase140 fixed-gamma-zero reference and the Phase141 sampled-gamma geometry screens.",
    "",
    sprintf("Decision: `%s`.", decision$sampled_gamma_geometry_decision[[1L]]),
    sprintf("Next stage: `%s`.", decision$next_stage_decision[[1L]]),
    "",
    "The regularized-gamma launch plan is included for the next overnight packet.",
    "",
    "```bash",
    launch_plan$command[[1L]],
    "```"
  )
}

app_joint_exqdesn_run_phase142_post_geometry_synthesis <- function(
  out_dir = app_joint_exqdesn_phase142_default_dir(),
  phase135_dir = app_joint_exqdesn_phase136_default_phase135_screening_dir(),
  fixed_dir = app_path("application/cache/joint_qdesn_phase140_exal_fixed_gamma_zero_sensitivity_recovery_20260718"),
  primary_dir = app_path("application/cache/joint_qdesn_phase141_primary_narrow_gamma_geometry_screen_20260719"),
  focus_dir = app_path("application/cache/joint_qdesn_phase141_focus_width_sensitivity_screen_20260719"),
  regularized_out_dir = app_joint_exqdesn_phase142_default_regularized_dir(),
  n_cores = 24L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  regularized_out_dir <- normalizePath(regularized_out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  phase135_manifest <- app_joint_qdesn_phase108_manifest_verify(phase135_dir, "phase135_matched_exal")
  fixed <- app_joint_exqdesn_phase142_load_packet(fixed_dir, "phase140_fixed_gamma_zero")
  primary <- app_joint_exqdesn_phase142_load_packet(primary_dir, "phase141_primary_geometry")
  focus <- app_joint_exqdesn_phase142_load_packet(focus_dir, "phase141_focus_width")
  packet_summary <- app_joint_qdesn_bind_rows(lapply(list(fixed, primary, focus), app_joint_exqdesn_phase142_packet_summary))
  comparison <- app_joint_exqdesn_phase142_compare_packets(fixed, primary, focus)
  decision <- app_joint_exqdesn_phase142_decision_summary(packet_summary, comparison)
  registry <- app_joint_exqdesn_phase142_regularized_registry(comparison)
  launch_plan <- app_joint_exqdesn_phase142_launch_plan(registry, regularized_out_dir, n_cores = n_cores)
  run_config <- data.frame(
    run_id = "joint_qdesn_phase142_post_geometry_synthesis",
    out_dir = out_dir,
    phase135_dir = normalizePath(phase135_dir, mustWork = TRUE),
    fixed_dir = fixed$dir,
    primary_dir = primary$dir,
    focus_dir = focus$dir,
    regularized_out_dir = regularized_out_dir,
    n_cores = as.integer(n_cores),
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_exqdesn_phase142_readme(decision, launch_plan), readme_path, useBytes = TRUE)
  launch_cmd_path <- file.path(out_dir, "phase142_regularized_gamma_launch_command.txt")
  writeLines(launch_plan$command, launch_cmd_path, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    phase135_manifest_verification = app_joint_qvp_write_csv(phase135_manifest, file.path(out_dir, "phase135_manifest_verification.csv")),
    packet_summary = app_joint_qvp_write_csv(packet_summary, file.path(out_dir, "phase140_141_packet_summary.csv")),
    geometry_decision_table = app_joint_qvp_write_csv(comparison, file.path(out_dir, "gamma_geometry_decision_table.csv")),
    decision_summary = app_joint_qvp_write_csv(decision, file.path(out_dir, "phase142_decision_summary.csv")),
    regularized_gamma_registry = app_joint_qvp_write_csv(registry, file.path(out_dir, "phase142_regularized_gamma_registry.csv")),
    regularized_gamma_launch_plan = app_joint_qvp_write_csv(launch_plan, file.path(out_dir, "phase142_regularized_gamma_launch_plan.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    launch_command = normalizePath(launch_cmd_path, mustWork = TRUE),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = out_dir,
    regularized_out_dir = regularized_out_dir,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path),
    manifest = manifest_info$manifest,
    packet_summary = packet_summary,
    comparison = comparison,
    decision = decision,
    registry = registry,
    launch_plan = launch_plan
  )
}

