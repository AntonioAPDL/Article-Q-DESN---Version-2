# Phase140 readiness for targeted exAL gamma/model redesign.

app_joint_exqdesn_phase140_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase140_exal_gamma_redesign_readiness_20260717")
}

app_joint_exqdesn_phase140_default_phase139_dir <- function() {
  app_path("application/cache/joint_qdesn_phase139_exal_long_chain_synthesis_20260717")
}

app_joint_exqdesn_phase140_required_phase139_files <- function() {
  c(
    "artifact_manifest.csv",
    "run_config.csv",
    "phase139_decision_summary.csv",
    "phase139_health_summary.csv",
    "phase139_exal_vs_matched_al.csv",
    "phase139_phase138_vs_phase136.csv",
    "phase139_sampler_diagnostic_summary.csv",
    "phase139_next_model_redesign_plan.csv"
  )
}

app_joint_exqdesn_phase140_load_phase139 <- function(phase139_dir) {
  phase139_dir <- normalizePath(phase139_dir, mustWork = TRUE)
  required <- app_joint_exqdesn_phase140_required_phase139_files()
  missing <- required[!file.exists(file.path(phase139_dir, required))]
  if (length(missing)) {
    stop(sprintf("Phase139 artifact is missing required files: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  list(
    dir = phase139_dir,
    manifest = app_joint_qdesn_phase108_manifest_verify(phase139_dir, "phase139"),
    run_config = app_read_csv(file.path(phase139_dir, "run_config.csv")),
    decision = app_read_csv(file.path(phase139_dir, "phase139_decision_summary.csv")),
    health = app_read_csv(file.path(phase139_dir, "phase139_health_summary.csv")),
    exal_vs_al = app_read_csv(file.path(phase139_dir, "phase139_exal_vs_matched_al.csv")),
    vs136 = app_read_csv(file.path(phase139_dir, "phase139_phase138_vs_phase136.csv")),
    sampler = app_read_csv(file.path(phase139_dir, "phase139_sampler_diagnostic_summary.csv")),
    redesign = app_read_csv(file.path(phase139_dir, "phase139_next_model_redesign_plan.csv"))
  )
}

app_joint_exqdesn_phase140_case_priority <- function(phase139) {
  exal <- phase139$exal_vs_al
  sampler <- phase139$sampler[, c(
    "case_id", "max_gamma_rhat", "min_gamma_rough_ess_total",
    "max_gamma_lag1_autocorrelation", "sampler_gate"
  ), drop = FALSE]
  out <- merge(exal, sampler, by = "case_id", all.x = TRUE, sort = FALSE)
  out$forecast_gap_to_matched_al <- out$phase138_mcmc_minus_matched_al_forecast_mae
  out$fit_gap_to_matched_al <- out$phase138_mcmc_minus_matched_al_fit_mae
  out$priority_score <- out$forecast_gap_to_matched_al +
    0.25 * pmax(out$fit_gap_to_matched_al, 0) +
    0.05 * pmax(out$max_gamma_rhat - 1, 0)
  out$phase140_priority_rank <- rank(-out$priority_score, ties.method = "first")
  out$phase140_case_action <- ifelse(
    out$forecast_gap_to_matched_al > 0,
    "include_in_fixed_gamma_zero_sensitivity",
    "monitor_only"
  )
  out$phase140_reason <- ifelse(
    out$forecast_gap_to_matched_al > 0,
    "Phase138 exAL MCMC remains worse than matched AL forecast MAE; test whether fixing gamma near the AL region recovers performance.",
    "Phase138 exAL MCMC is already competitive with matched AL forecast MAE."
  )
  out[order(out$phase140_priority_rank), , drop = FALSE]
}

app_joint_exqdesn_phase140_method_feasibility <- function() {
  data.frame(
    method_id = c(
      "fixed_zero_gamma_mcmc",
      "bounded_slice_reference",
      "logit_slice_reference",
      "strong_gamma_shrinkage_prior",
      "centered_or_constrained_gamma_parameterization",
      "case_specific_exal_spec_refinement"
    ),
    method_class = c(
      "immediate_sensitivity",
      "already_run_reference",
      "already_run_reference",
      "requires_new_model_prior",
      "requires_new_sampler_parameterization",
      "requires_new_screening_registry"
    ),
    supported_by_current_code = c(TRUE, TRUE, TRUE, FALSE, FALSE, TRUE),
    launch_now = c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE),
    rationale = c(
      "Directly tests whether exAL gamma flexibility, rather than DESN/RHS controls, causes the forecast gap.",
      "Phase136/138 already ran this reference; do not rerun without a new hypothesis.",
      "Phase136/138 already ran this reference; do not rerun without a new hypothesis.",
      "Would regularize gamma toward the AL-like region, but needs explicit prior support in VB and MCMC.",
      "Could reduce gamma stickiness, but needs a new parameterization and validation tests.",
      "Useful only after the fixed-gamma sensitivity shows exAL can recover AL-like performance."
    ),
    expected_decision_value = c(
      "high",
      "low",
      "low",
      "high_after_fixed_gamma",
      "medium_after_shrinkage",
      "medium_after_fixed_gamma"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase140_build_command <- function(output_dir, phase139, case_ids,
                                                     n_chains = 8L,
                                                     mcmc_n_iter = 12000L,
                                                     mcmc_burn = 3000L,
                                                     mcmc_thin = 1L,
                                                     mcmc_seed_offset = 9600L,
                                                     n_cores = 32L,
                                                     vb_n_cores = 5L) {
  rc <- phase139$run_config
  paste(
    "Rscript application/scripts/145_run_joint_exqdesn_phase136_gamma_kernel_packet.R",
    sprintf("--output-dir %s", shQuote(output_dir)),
    sprintf("--phase135-screening-dir %s", shQuote(rc$phase135_screening_dir[[1L]])),
    sprintf("--phase135-audit-dir %s", shQuote(rc$phase135_audit_dir[[1L]])),
    sprintf("--fixture-dir %s", shQuote(app_joint_exqdesn_phase136_default_fixture_dir())),
    sprintf("--case-ids %s", shQuote(paste(case_ids, collapse = ","))),
    "--variant-ids fixed_zero",
    "--bounded-width-multiplier 4",
    "--logit-eta-width 4",
    "--gamma-slice-max-steps 1",
    sprintf("--n-chains %s", as.integer(n_chains)),
    sprintf("--mcmc-n-iter %s", as.integer(mcmc_n_iter)),
    sprintf("--mcmc-burn %s", as.integer(mcmc_burn)),
    sprintf("--mcmc-thin %s", as.integer(mcmc_thin)),
    sprintf("--mcmc-seed-offset %s", as.integer(mcmc_seed_offset)),
    "--chain-seed-stride 100",
    "--sigma-upper-multiplier 50",
    "--distance-pass 5",
    "--chain-pass 5",
    sprintf("--n-cores %s", as.integer(n_cores)),
    sprintf("--vb-n-cores %s", as.integer(vb_n_cores)),
    "--gamma-init-mode vb",
    "--gamma-jitter-fraction 0",
    "--trace-write-stride 50",
    "--save-rdata false",
    "--dry-run false",
    sep = " \\\n  "
  )
}

app_joint_exqdesn_phase140_launch_plan <- function(phase139, case_priority,
                                                   launch_root = "application/cache",
                                                   launch_output_dir = NULL,
                                                   n_chains = 8L,
                                                   mcmc_n_iter = 12000L,
                                                   mcmc_burn = 3000L,
                                                   mcmc_thin = 1L,
                                                   mcmc_seed_offset = 9600L) {
  cases <- case_priority$case_id[case_priority$phase140_case_action == "include_in_fixed_gamma_zero_sensitivity"]
  out_dir <- if (!is.null(launch_output_dir) && nzchar(as.character(launch_output_dir[[1L]]))) {
    as.character(launch_output_dir[[1L]])
  } else {
    file.path(launch_root, "joint_qdesn_phase140_exal_fixed_gamma_zero_sensitivity_20260717")
  }
  data.frame(
    launch_id = "phase140_fixed_gamma_zero_sensitivity",
    launch_status = "prepared_not_launched",
    variant_ids = "fixed_zero",
    gamma_update = "fixed",
    gamma_fixed_policy = "zero_from_matched_phase135_controls",
    n_cases = length(cases),
    case_ids = paste(cases, collapse = ","),
    n_chains = as.integer(n_chains),
    total_chain_jobs = as.integer(length(cases) * n_chains),
    mcmc_n_iter = as.integer(mcmc_n_iter),
    mcmc_burn = as.integer(mcmc_burn),
    mcmc_thin = as.integer(mcmc_thin),
    mcmc_seed_offset = as.integer(mcmc_seed_offset),
    n_cores = min(as.integer(length(cases) * n_chains), 32L),
    vb_n_cores = min(length(cases), 5L),
    output_dir = out_dir,
    rationale = "Run only fixed-gamma-zero exAL MCMC for the Phase139 priority cases to test whether gamma flexibility is responsible for the matched-AL performance gap.",
    command = app_joint_exqdesn_phase140_build_command(
      output_dir = out_dir,
      phase139 = phase139,
      case_ids = cases,
      n_chains = n_chains,
      mcmc_n_iter = mcmc_n_iter,
      mcmc_burn = mcmc_burn,
      mcmc_thin = mcmc_thin,
      mcmc_seed_offset = mcmc_seed_offset,
      n_cores = min(as.integer(length(cases) * n_chains), 32L),
      vb_n_cores = min(length(cases), 5L)
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase140_decision_summary <- function(phase139, case_priority, feasibility, launch_plan) {
  phase139_ok <- all(phase139$manifest$status == "pass") &&
    !any(phase139$health$status == "fail")
  n_gap <- sum(case_priority$forecast_gap_to_matched_al > 0, na.rm = TRUE)
  data.frame(
    phase140_decision = if (phase139_ok && n_gap > 0L) {
      "ready_to_launch_fixed_gamma_zero_sensitivity"
    } else if (!phase139_ok) {
      "blocked_fix_phase139_artifact"
    } else {
      "no_fixed_gamma_sensitivity_needed"
    },
    article_promotion_gate = "review",
    phase139_decision = phase139$decision$phase139_decision[[1L]],
    phase139_article_gate = phase139$decision$article_promotion_gate[[1L]],
    priority_cases = nrow(case_priority),
    cases_with_exal_forecast_gap_to_matched_al = n_gap,
    immediate_launchable_methods = sum(feasibility$launch_now),
    fixed_gamma_chain_jobs = launch_plan$total_chain_jobs[[1L]],
    mcmc_launched_in_phase140 = FALSE,
    article_tables_modified = FALSE,
    main_takeaway = paste(
      "Phase139 shows brute-force longer chains do not make exAL competitive with matched AL.",
      "Phase140 therefore prepares a fixed-gamma-zero sensitivity to isolate whether the extra gamma flexibility is hurting quantile-grid performance."
    ),
    recommended_next_stage = "Review and, if approved, launch the prepared fixed-gamma-zero sensitivity packet; compare its forecast MAE against Phase138 exAL MCMC and matched AL before implementing stronger gamma priors.",
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase140_readme <- function(decision, launch_plan, feasibility) {
  c(
    "# Joint exQDESN Phase140 Gamma-Redesign Readiness",
    "",
    "This artifact prepares the next targeted exAL experiment after Phase139.",
    "It does not launch MCMC jobs and does not modify article tables.",
    "",
    sprintf("- Decision: `%s`", decision$phase140_decision[[1L]]),
    sprintf("- Article gate: `%s`", decision$article_promotion_gate[[1L]]),
    sprintf("- Prepared launch: `%s`", launch_plan$launch_id[[1L]]),
    sprintf("- Cases: `%s`", launch_plan$n_cases[[1L]]),
    sprintf("- Total chain jobs: `%s`", launch_plan$total_chain_jobs[[1L]]),
    "",
    "The fixed-gamma-zero packet is the immediate high-value test because it asks whether exAL underperformance is caused by gamma flexibility itself.",
    "Bounded and logit slice variants are already represented by Phase136/138 and should not be rerun without a new hypothesis.",
    "",
    "Method feasibility:",
    paste(capture.output(print(feasibility[, c("method_id", "supported_by_current_code", "launch_now")], row.names = FALSE)), collapse = "\n"),
    "",
    "Prepared command:",
    launch_plan$command[[1L]]
  )
}

app_joint_exqdesn_run_phase140_gamma_redesign_readiness <- function(
  out_dir = app_joint_exqdesn_phase140_default_dir(),
  phase139_dir = app_joint_exqdesn_phase140_default_phase139_dir(),
  launch_output_dir = NULL,
  n_chains = 8L,
  mcmc_n_iter = 12000L,
  mcmc_burn = 3000L,
  mcmc_thin = 1L,
  mcmc_seed_offset = 9600L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  phase139 <- app_joint_exqdesn_phase140_load_phase139(phase139_dir)
  case_priority <- app_joint_exqdesn_phase140_case_priority(phase139)
  feasibility <- app_joint_exqdesn_phase140_method_feasibility()
  launch_plan <- app_joint_exqdesn_phase140_launch_plan(
    phase139,
    case_priority,
    launch_output_dir = launch_output_dir,
    n_chains = n_chains,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin,
    mcmc_seed_offset = mcmc_seed_offset
  )
  decision <- app_joint_exqdesn_phase140_decision_summary(phase139, case_priority, feasibility, launch_plan)

  run_config <- data.frame(
    run_id = "joint_qdesn_phase140_exal_gamma_redesign_readiness",
    out_dir = out_dir,
    phase139_dir = phase139$dir,
    launch_output_dir = launch_plan$output_dir[[1L]],
    n_chains = as.integer(n_chains),
    mcmc_n_iter = as.integer(mcmc_n_iter),
    mcmc_burn = as.integer(mcmc_burn),
    mcmc_thin = as.integer(mcmc_thin),
    mcmc_seed_offset = as.integer(mcmc_seed_offset),
    mcmc_launched = FALSE,
    article_tables_modified = FALSE,
    validation_contract = "quantile_grid_fit_and_forecast_scoring_with_raw_contract_qhat",
    scalar_predictive_density_claim = FALSE,
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_exqdesn_phase140_readme(decision, launch_plan, feasibility), readme_path, useBytes = TRUE)
  command_path <- file.path(out_dir, "phase140_launch_commands.txt")
  writeLines(c(
    "# Phase140 fixed-gamma-zero sensitivity launch command",
    "# Review resource availability before running. Phase140 readiness does not launch this command.",
    "",
    launch_plan$command[[1L]]
  ), command_path, useBytes = TRUE)

  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    phase139_manifest_verification = app_joint_qvp_write_csv(phase139$manifest, file.path(out_dir, "phase139_manifest_verification.csv")),
    phase140_case_priority = app_joint_qvp_write_csv(case_priority, file.path(out_dir, "phase140_case_priority.csv")),
    phase140_method_feasibility = app_joint_qvp_write_csv(feasibility, file.path(out_dir, "phase140_method_feasibility.csv")),
    phase140_fixed_gamma_launch_plan = app_joint_qvp_write_csv(launch_plan, file.path(out_dir, "phase140_fixed_gamma_launch_plan.csv")),
    phase140_decision_summary = app_joint_qvp_write_csv(decision, file.path(out_dir, "phase140_decision_summary.csv")),
    phase140_launch_commands = normalizePath(command_path, mustWork = TRUE),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    paths = c(paths, artifact_manifest = manifest_info$manifest_path),
    manifest = manifest_info$manifest,
    run_config = run_config,
    phase139 = phase139,
    case_priority = case_priority,
    feasibility = feasibility,
    launch_plan = launch_plan,
    decision = decision
  )
}
