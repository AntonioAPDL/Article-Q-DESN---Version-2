# Phase147 hybrid conditional-refresh plus ridge-MH sampler experiment.

app_joint_exqdesn_phase147_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase147_hybrid_geometry_student_t_20260726")
}

app_joint_exqdesn_phase147_variant_specs <- function() {
  data.frame(
    phase136_variant_id = c(
      "phase147_refresh3_sigma_s_control",
      "phase147_hybrid_tau_specific_balanced",
      "phase147_hybrid_tau_specific_conservative"
    ),
    gamma_update = c("logit_slice", "hybrid_refresh_joint_mh", "hybrid_refresh_joint_mh"),
    bounded_width_multiplier = NA_real_,
    logit_eta_width = 4,
    gamma_prior_type = "none",
    gamma_prior_center = NA_real_,
    gamma_prior_sd_eta = NA_real_,
    gamma_slice_max_steps = 500L,
    gamma_refresh_repeats = c(3L, 2L, 2L),
    gamma_refresh_block = c("sigma_s", "sigma_s", "sigma_s"),
    gamma_init_mode = "vb_jittered",
    gamma_jitter_fraction = 0.02,
    gamma_sigma_mh_eta_sd = c(0.25, 0.12, 0.09),
    gamma_sigma_mh_log_sigma_sd = c(0.05, 0.022, 0.016),
    gamma_sigma_mh_eta_sd_vector = c(
      "",
      "0.12,0.12,0.08,0.16,0.08,0.12,0.12",
      "0.09,0.09,0.06,0.12,0.06,0.09,0.09"
    ),
    gamma_sigma_mh_log_sigma_sd_vector = c(
      "",
      "0.022,0.022,0.014,0.028,0.014,0.022,0.022",
      "0.016,0.016,0.011,0.022,0.011,0.016,0.016"
    ),
    gamma_sigma_mh_rho_mode = c("zero", "tau_signed", "tau_signed"),
    gamma_sigma_mh_rho_abs = c(0, 0.90, 0.90),
    gamma_sigma_mh_repeats = c(1L, 3L, 4L),
    gamma_sigma_mh_scale_profile = c(
      "none",
      "tau_specific_balanced_tight_at_0p25_0p75",
      "tau_specific_conservative_tight_at_0p25_0p75"
    ),
    phase136_variant_role = c(
      "phase146_refresh_control",
      "hybrid_conditional_refresh_plus_balanced_ridge_mh",
      "hybrid_conditional_refresh_plus_conservative_ridge_mh"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase147_acceptance_audit <- function(out_dir) {
  path <- file.path(out_dir, "gamma_sigma_mh_acceptance_summary.csv")
  if (!file.exists(path)) return(data.frame())
  x <- app_read_csv(path)
  x <- x[x$gamma_update == "hybrid_refresh_joint_mh" &
           is.finite(x$gamma_sigma_mh_acceptance_rate), , drop = FALSE]
  if (!nrow(x)) return(data.frame())
  keys <- split(x, interaction(x$phase136_variant_id, x$tau, drop = TRUE))
  app_joint_qdesn_bind_rows(lapply(keys, function(block) {
    data.frame(
      phase136_variant_id = block$phase136_variant_id[[1L]],
      tau = block$tau[[1L]],
      n_chains = nrow(block),
      acceptance_mean = mean(block$gamma_sigma_mh_acceptance_rate),
      acceptance_min = min(block$gamma_sigma_mh_acceptance_rate),
      acceptance_max = max(block$gamma_sigma_mh_acceptance_rate),
      acceptance_in_review_band = mean(block$gamma_sigma_mh_acceptance_rate) >= 0.12 &&
        mean(block$gamma_sigma_mh_acceptance_rate) <= 0.60,
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase147_decision <- function(out_dir, acceptance) {
  assessment <- app_read_csv(file.path(out_dir, "phase136_case_assessment.csv"))
  stability <- app_read_csv(file.path(out_dir, "chain_group_qhat_stability.csv"))
  failures <- app_read_csv(file.path(out_dir, "phase136_chain_worker_failures.csv"))
  prep_failures <- app_read_csv(file.path(out_dir, "phase136_case_variant_prep_failures.csv"))
  hard_fail <- nrow(failures) > 0L || nrow(prep_failures) > 0L ||
    any(assessment$phase136_gate_status == "fail") ||
    any(assessment$mcmc_fit_contract_crossing_pairs > 0L) ||
    any(assessment$mcmc_forecast_contract_crossing_pairs > 0L)
  hybrid_acceptance_ok <- nrow(acceptance) > 0L &&
    all(acceptance$acceptance_in_review_band)
  stability_by_variant <- aggregate(
    cbind(fit_qhat_mean_abs_group_delta, forecast_qhat_mean_abs_group_delta) ~ phase136_variant_id,
    stability, max, na.rm = TRUE
  )
  assessment <- merge(assessment, stability_by_variant, by = "phase136_variant_id", all.x = TRUE, sort = FALSE)
  eligible <- assessment[assessment$phase136_gate_status != "fail", , drop = FALSE]
  eligible <- eligible[order(
    eligible$max_gamma_rhat,
    -eligible$min_gamma_rough_ess_total,
    eligible$forecast_qhat_mean_abs_group_delta,
    eligible$mcmc_forecast_truth_mae
  ), , drop = FALSE]
  best <- if (nrow(eligible)) eligible[1L, , drop = FALSE] else data.frame()
  data.frame(
    decision_id = "phase147_hybrid_geometry",
    gate_status = if (hard_fail) "fail" else "review",
    case_variant_rows = nrow(assessment),
    worker_failures = nrow(failures),
    prep_failures = nrow(prep_failures),
    all_hybrid_tau_acceptance_in_review_band = hybrid_acceptance_ok,
    selected_diagnostic_variant = if (nrow(best)) best$phase136_variant_id[[1L]] else NA_character_,
    selected_forecast_mae = if (nrow(best)) best$mcmc_forecast_truth_mae[[1L]] else NA_real_,
    selected_fit_mae = if (nrow(best)) best$mcmc_fit_truth_mae[[1L]] else NA_real_,
    selected_max_gamma_rhat = if (nrow(best)) best$max_gamma_rhat[[1L]] else NA_real_,
    selected_min_gamma_ess = if (nrow(best)) best$min_gamma_rough_ess_total[[1L]] else NA_real_,
    selected_max_forecast_chain_group_delta = if (nrow(best)) best$forecast_qhat_mean_abs_group_delta[[1L]] else NA_real_,
    recommendation = if (hard_fail) {
      "fix_phase147_implementation_failure"
    } else if (!hybrid_acceptance_ok) {
      "review_per_tau_acceptance_before_further_sampler_propagation"
    } else if (nrow(best) && best$gamma_update[[1L]] == "hybrid_refresh_joint_mh" &&
               best$max_gamma_rhat[[1L]] <= 1.10) {
      "hybrid_sampler_candidate_for_case_specific_confirmation"
    } else {
      "retain_refresh_control_and_do_not_propagate_hybrid_sampler"
    },
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_run_phase147_hybrid_geometry <- function(
  out_dir = app_joint_exqdesn_phase147_default_dir(),
  n_chains = 8L,
  mcmc_n_iter = 15000L,
  mcmc_burn = 3000L,
  mcmc_thin = 3L,
  n_cores = 24L,
  vb_n_cores = 6L,
  dry_run = FALSE
) {
  case_ids <- app_joint_exqdesn_phase145_default_case_ids()
  phase135 <- app_joint_exqdesn_phase136_load_phase135(
    app_joint_exqdesn_phase136_default_phase135_screening_dir(),
    app_joint_exqdesn_phase136_default_phase135_audit_dir()
  )
  selected <- app_joint_exqdesn_phase136_select_cases(phase135, case_ids = case_ids, case_limit = NULL)
  registry <- app_joint_exqdesn_phase145_variant_registry_for_specs(
    selected, app_joint_exqdesn_phase147_variant_specs()
  )
  phase136 <- app_joint_exqdesn_run_phase136_gamma_kernel_packet(
    out_dir = out_dir,
    case_ids = case_ids,
    case_limit = NULL,
    n_chains = n_chains,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin,
    mcmc_seed_offset = 14700L,
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
    run_id = "joint_qdesn_phase147_hybrid_geometry"
  )
  acceptance <- if (isTRUE(dry_run)) data.frame() else
    app_joint_exqdesn_phase147_acceptance_audit(out_dir)
  decision <- if (isTRUE(dry_run)) {
    data.frame(
      decision_id = "phase147_hybrid_geometry", gate_status = "dry_run",
      case_variant_rows = nrow(registry), worker_failures = 0L, prep_failures = 0L,
      all_hybrid_tau_acceptance_in_review_band = NA,
      selected_diagnostic_variant = NA_character_, selected_forecast_mae = NA_real_,
      selected_fit_mae = NA_real_, selected_max_gamma_rhat = NA_real_,
      selected_min_gamma_ess = NA_real_, selected_max_forecast_chain_group_delta = NA_real_,
      recommendation = "launch_phase147_after_validation", stringsAsFactors = FALSE
    )
  } else app_joint_exqdesn_phase147_decision(out_dir, acceptance)
  readme_path <- file.path(out_dir, "README_phase147.md")
  writeLines(c(
    "# Phase147 Hybrid Sigma-Gamma Geometry",
    "",
    "The exAL model, priors, DESN design, fixture, and scoring contract are fixed.",
    "This packet compares the Phase146 refresh control with two compositions of",
    "conditional refresh and quantile-specific ridge-aligned MH transitions.",
    "",
    sprintf("- Chains per variant: %s", n_chains),
    sprintf("- Iterations/burn/thin: %s/%s/%s", mcmc_n_iter, mcmc_burn, mcmc_thin),
    sprintf("- Gate: %s", decision$gate_status[[1L]]),
    sprintf("- Recommendation: %s", decision$recommendation[[1L]])
  ), readme_path, useBytes = TRUE)
  extra <- c(
    phase147_variant_registry = app_joint_qvp_write_csv(registry, file.path(out_dir, "phase147_variant_registry.csv")),
    phase147_acceptance_by_tau = app_joint_qvp_write_csv(acceptance, file.path(out_dir, "phase147_acceptance_by_tau.csv")),
    phase147_decision_summary = app_joint_qvp_write_csv(decision, file.path(out_dir, "phase147_decision_summary.csv")),
    phase147_readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_phase145_refresh_manifest(out_dir, extra)
  list(out_dir = out_dir, phase136 = phase136, registry = registry,
       acceptance = acceptance, decision = decision,
       paths = c(extra, artifact_manifest = manifest$manifest_path))
}
