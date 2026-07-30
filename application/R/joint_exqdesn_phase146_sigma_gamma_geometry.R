# Phase146 target-preserving joint sigma-gamma sampler geometry experiment.

app_joint_exqdesn_phase146_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase146_sigma_gamma_geometry_student_t_20260725")
}

app_joint_exqdesn_phase146_variant_specs <- function() {
  data.frame(
    phase136_variant_id = c(
      "phase146_refresh3_sigma_s_control",
      "phase146_joint_mh_ridge_narrow",
      "phase146_joint_mh_ridge_moderate"
    ),
    gamma_update = c("logit_slice", "joint_rw_mh", "joint_rw_mh"),
    bounded_width_multiplier = NA_real_,
    logit_eta_width = c(4, NA_real_, NA_real_),
    gamma_prior_type = "none",
    gamma_prior_center = NA_real_,
    gamma_prior_sd_eta = NA_real_,
    gamma_slice_max_steps = c(500L, 100L, 100L),
    gamma_refresh_repeats = c(3L, 3L, 3L),
    gamma_refresh_block = c("sigma_s", "none", "none"),
    gamma_init_mode = "vb_jittered",
    gamma_jitter_fraction = 0.02,
    gamma_sigma_mh_eta_sd = c(0.25, 0.20, 0.30),
    gamma_sigma_mh_log_sigma_sd = c(0.05, 0.035, 0.050),
    gamma_sigma_mh_rho_mode = c("zero", "tau_signed", "tau_signed"),
    gamma_sigma_mh_rho_abs = c(0, 0.90, 0.90),
    phase136_variant_role = c(
      "phase145c_target_preserving_refresh_control",
      "joint_transformed_mh_ridge_aligned_narrow",
      "joint_transformed_mh_ridge_aligned_moderate"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase146_decision <- function(out_dir, memory, ridge) {
  assessment <- app_read_csv(file.path(out_dir, "phase136_case_assessment.csv"))
  case_summary <- app_read_csv(file.path(out_dir, "phase136_mcmc_case_summary.csv"))
  acceptance_cols <- intersect(
    c("phase136_variant_id", "gamma_sigma_mh_acceptance_mean", "gamma_sigma_mh_acceptance_min"),
    names(case_summary)
  )
  if (length(acceptance_cols) > 1L) {
    assessment <- merge(
      assessment,
      unique(case_summary[, acceptance_cols, drop = FALSE]),
      by = "phase136_variant_id",
      all.x = TRUE,
      sort = FALSE
    )
  }
  failures <- app_read_csv(file.path(out_dir, "phase136_chain_worker_failures.csv"))
  prep_failures <- app_read_csv(file.path(out_dir, "phase136_case_variant_prep_failures.csv"))
  mh <- assessment[assessment$gamma_update == "joint_rw_mh", , drop = FALSE]
  acceptance_ok <- nrow(mh) > 0L && all(
    is.finite(mh$gamma_sigma_mh_acceptance_mean) &
      mh$gamma_sigma_mh_acceptance_mean >= 0.10 &
      mh$gamma_sigma_mh_acceptance_mean <= 0.70
  )
  implementation_fail <- nrow(failures) > 0L || nrow(prep_failures) > 0L ||
    any(assessment$phase136_gate_status == "fail") ||
    any(assessment$mcmc_fit_contract_crossing_pairs > 0L) ||
    any(assessment$mcmc_forecast_contract_crossing_pairs > 0L)
  eligible <- assessment[assessment$phase136_gate_status != "fail", , drop = FALSE]
  best <- eligible[order(
    eligible$mcmc_forecast_truth_mae,
    eligible$max_gamma_rhat,
    -eligible$min_gamma_rough_ess_total
  ), , drop = FALSE]
  if (nrow(best)) best <- best[1L, , drop = FALSE]
  data.frame(
    decision_id = "phase146_sigma_gamma_geometry",
    gate_status = if (implementation_fail) "fail" else "review",
    case_variant_rows = nrow(assessment),
    worker_failures = nrow(failures),
    prep_failures = nrow(prep_failures),
    joint_mh_acceptance_in_review_band = acceptance_ok,
    best_variant_id = if (nrow(best)) best$phase136_variant_id[[1L]] else NA_character_,
    best_forecast_mae = if (nrow(best)) best$mcmc_forecast_truth_mae[[1L]] else NA_real_,
    best_fit_mae = if (nrow(best)) best$mcmc_fit_truth_mae[[1L]] else NA_real_,
    best_max_gamma_rhat = if (nrow(best)) best$max_gamma_rhat[[1L]] else NA_real_,
    best_min_gamma_ess = if (nrow(best)) best$min_gamma_rough_ess_total[[1L]] else NA_real_,
    max_abs_gamma_sigma_cor = if (nrow(ridge)) app_joint_exqdesn_phase145_safe_max_abs(ridge$gamma_sigma_chain_mean_cor) else NA_real_,
    recommendation = if (implementation_fail) {
      "fix_phase146_implementation_gate_before_sampler_interpretation"
    } else if (!acceptance_ok) {
      "retune_joint_mh_scale_before_any_propagation"
    } else if (nrow(best) && best$gamma_update[[1L]] == "joint_rw_mh") {
      "audit_joint_mh_predictive_and_geometry_gain_before_limited_propagation"
    } else {
      "retain_phase145c_refresh_control_and_do_not_propagate_joint_mh"
    },
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_run_phase146_sigma_gamma_geometry <- function(
  out_dir = app_joint_exqdesn_phase146_default_dir(),
  phase135_screening_dir = app_joint_exqdesn_phase136_default_phase135_screening_dir(),
  phase135_audit_dir = app_joint_exqdesn_phase136_default_phase135_audit_dir(),
  fixture_dir = app_joint_exqdesn_phase136_default_fixture_dir(),
  n_chains = 8L,
  mcmc_n_iter = 12000L,
  mcmc_burn = 3000L,
  mcmc_thin = 3L,
  n_cores = 24L,
  vb_n_cores = 6L,
  dry_run = FALSE
) {
  case_ids <- app_joint_exqdesn_phase145_default_case_ids()
  phase135 <- app_joint_exqdesn_phase136_load_phase135(phase135_screening_dir, phase135_audit_dir)
  selected <- app_joint_exqdesn_phase136_select_cases(phase135, case_ids = case_ids, case_limit = NULL)
  specs <- app_joint_exqdesn_phase146_variant_specs()
  registry <- app_joint_exqdesn_phase145_variant_registry_for_specs(selected, specs)
  phase136 <- app_joint_exqdesn_run_phase136_gamma_kernel_packet(
    out_dir = out_dir,
    phase135_screening_dir = phase135_screening_dir,
    phase135_audit_dir = phase135_audit_dir,
    fixture_dir = fixture_dir,
    case_ids = case_ids,
    case_limit = NULL,
    n_chains = n_chains,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin,
    mcmc_seed_offset = 14600L,
    chain_seed_stride = 100L,
    sigma_upper_multiplier = 50,
    distance_pass = 5,
    chain_pass = 5,
    n_cores = n_cores,
    vb_n_cores = vb_n_cores,
    gamma_init_mode = "vb_jittered",
    gamma_jitter_fraction = 0.02,
    trace_write_stride = 50L,
    save_rdata = FALSE,
    dry_run = dry_run,
    variant_registry_override = registry,
    run_id = "joint_qdesn_phase146_sigma_gamma_geometry"
  )
  trace <- if (file.exists(file.path(out_dir, "mcmc_trace_summary.csv"))) {
    app_read_csv(file.path(out_dir, "mcmc_trace_summary.csv"))
  } else {
    data.frame()
  }
  trace <- app_joint_exqdesn_phase145_trace_enrich(trace, registry)
  memory <- app_joint_exqdesn_phase145_gamma_chain_memory_summary(trace)
  ridge <- app_joint_exqdesn_phase145_gamma_sigma_ridge_summary(trace)
  decision <- if (isTRUE(dry_run)) {
    data.frame(
      decision_id = "phase146_sigma_gamma_geometry", gate_status = "dry_run",
      case_variant_rows = nrow(registry), worker_failures = 0L, prep_failures = 0L,
      joint_mh_acceptance_in_review_band = NA, best_variant_id = NA_character_,
      best_forecast_mae = NA_real_, best_fit_mae = NA_real_,
      best_max_gamma_rhat = NA_real_, best_min_gamma_ess = NA_real_,
      max_abs_gamma_sigma_cor = NA_real_,
      recommendation = "launch_phase146_after_dry_run_review",
      stringsAsFactors = FALSE
    )
  } else {
    app_joint_exqdesn_phase146_decision(out_dir, memory, ridge)
  }
  readme <- c(
    "# Phase146 Joint exQDESN Sigma-Gamma Geometry",
    "",
    "This experiment keeps the exAL likelihood and all priors fixed.",
    "It compares the Phase145C refresh control with target-preserving joint MH",
    "moves on transformed log-sigma and logit-gamma coordinates.",
    "",
    sprintf("- Variants: %s", nrow(registry)),
    sprintf("- Chains per variant: %s", n_chains),
    sprintf("- Iterations/burn/thin: %s/%s/%s", mcmc_n_iter, mcmc_burn, mcmc_thin),
    sprintf("- Gate: %s", decision$gate_status[[1L]]),
    sprintf("- Recommendation: %s", decision$recommendation[[1L]])
  )
  readme_path <- file.path(out_dir, "README_phase146.md")
  writeLines(readme, readme_path, useBytes = TRUE)
  extra <- c(
    phase146_variant_registry = app_joint_qvp_write_csv(registry, file.path(out_dir, "phase146_variant_registry.csv")),
    phase146_gamma_chain_memory = app_joint_qvp_write_csv(memory, file.path(out_dir, "phase146_gamma_chain_memory.csv")),
    phase146_gamma_sigma_ridge = app_joint_qvp_write_csv(ridge, file.path(out_dir, "phase146_gamma_sigma_ridge.csv")),
    phase146_decision_summary = app_joint_qvp_write_csv(decision, file.path(out_dir, "phase146_decision_summary.csv")),
    phase146_readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_phase145_refresh_manifest(out_dir, extra)
  list(out_dir = out_dir, phase136 = phase136, registry = registry, decision = decision,
       paths = c(extra, artifact_manifest = manifest$manifest_path))
}
