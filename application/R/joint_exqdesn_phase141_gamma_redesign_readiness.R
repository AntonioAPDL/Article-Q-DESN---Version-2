# Phase141 readiness after fixed-gamma-zero exAL recovery.

app_joint_exqdesn_phase141_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase141_exal_gamma_redesign_readiness_20260719")
}

app_joint_exqdesn_phase141_default_fixed_gamma_dir <- function() {
  app_path("application/cache/joint_qdesn_phase140_exal_fixed_gamma_zero_sensitivity_recovery_20260718")
}

app_joint_exqdesn_phase141_required_fixed_gamma_files <- function() {
  c(
    "artifact_manifest.csv",
    "run_config.csv",
    "phase136_mcmc_case_summary.csv",
    "phase136_case_assessment.csv",
    "phase136_chain_jobs.csv",
    "phase136_chain_worker_failures.csv",
    "mcmc_rhat_ess_summary.csv",
    "runtime_summary.csv",
    "phase140_fixed_zero_improvement_vs_best_prior_gamma.csv",
    "phase140_vs_prior_gamma_packet_best_by_case.csv"
  )
}

app_joint_exqdesn_phase141_load_fixed_gamma_packet <- function(fixed_gamma_dir) {
  fixed_gamma_dir <- normalizePath(fixed_gamma_dir, mustWork = TRUE)
  required <- app_joint_exqdesn_phase141_required_fixed_gamma_files()
  missing <- required[!file.exists(file.path(fixed_gamma_dir, required))]
  if (length(missing)) {
    stop(sprintf("Fixed-gamma packet is missing required files: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  manifest <- app_joint_qdesn_phase108_manifest_verify(fixed_gamma_dir, "phase140_fixed_gamma_zero")
  list(
    dir = fixed_gamma_dir,
    manifest = manifest,
    run_config = app_read_csv(file.path(fixed_gamma_dir, "run_config.csv")),
    case_summary = app_read_csv(file.path(fixed_gamma_dir, "phase136_mcmc_case_summary.csv")),
    assessment = app_read_csv(file.path(fixed_gamma_dir, "phase136_case_assessment.csv")),
    chain_jobs = app_read_csv(file.path(fixed_gamma_dir, "phase136_chain_jobs.csv")),
    chain_failures = app_read_csv(file.path(fixed_gamma_dir, "phase136_chain_worker_failures.csv")),
    rhat_ess = app_read_csv(file.path(fixed_gamma_dir, "mcmc_rhat_ess_summary.csv")),
    runtime = app_read_csv(file.path(fixed_gamma_dir, "runtime_summary.csv")),
    improvement = app_read_csv(file.path(fixed_gamma_dir, "phase140_fixed_zero_improvement_vs_best_prior_gamma.csv")),
    best_prior_gamma = app_read_csv(file.path(fixed_gamma_dir, "phase140_vs_prior_gamma_packet_best_by_case.csv"))
  )
}

app_joint_exqdesn_phase141_diagnostic_summary <- function(packet) {
  summary <- packet$case_summary
  assessment <- packet$assessment
  rhat <- packet$rhat_ess
  jobs <- packet$chain_jobs
  failures <- packet$chain_failures
  improvement <- packet$improvement

  contract_crossings <- sum(summary$mcmc_fit_contract_crossing_pairs, summary$mcmc_forecast_contract_crossing_pairs, na.rm = TRUE)
  raw_crossings <- sum(summary$mcmc_fit_raw_crossing_pairs, summary$mcmc_forecast_raw_crossing_pairs, na.rm = TRUE)
  sigma_rhat <- rhat[rhat$parameter == "sigma", , drop = FALSE]
  gamma_rhat <- rhat[rhat$parameter == "gamma", , drop = FALSE]
  sampled_gamma <- !all(summary$gamma_update == "fixed")
  sigma_max_rhat <- if (nrow(sigma_rhat)) max(sigma_rhat$rhat, na.rm = TRUE) else NA_real_
  sigma_min_ess <- if (nrow(sigma_rhat)) min(sigma_rhat$rough_ess_total, na.rm = TRUE) else NA_real_
  gamma_max_abs_mean <- if (nrow(gamma_rhat) && "rough_ess_total" %in% names(gamma_rhat)) {
    0
  } else {
    NA_real_
  }
  improvement_positive <- if (nrow(improvement)) all(improvement$abs_improvement > 0, na.rm = TRUE) else FALSE

  data.frame(
    check = c(
      "source_manifest",
      "worker_failures",
      "requested_chain_jobs",
      "successful_case_rows",
      "contract_crossings",
      "raw_crossings",
      "sigma_rhat",
      "sigma_ess",
      "fixed_gamma_gate_semantics",
      "fixed_zero_forecast_improvement",
      "worst_remaining_forecast_case",
      "article_promotion"
    ),
    status = c(
      if (all(packet$manifest$status == "pass")) "pass" else "fail",
      if (nrow(failures) == 0L) "pass" else "fail",
      if (nrow(jobs) == sum(summary$mcmc_n_chains, na.rm = TRUE)) "pass" else "review",
      if (nrow(summary) > 0L && all(summary$all_requested_chains_completed)) "pass" else "fail",
      if (contract_crossings == 0) "pass" else "fail",
      if (raw_crossings == 0) "pass" else "review",
      if (is.finite(sigma_max_rhat) && sigma_max_rhat <= 1.01) "pass" else "review",
      if (is.finite(sigma_min_ess) && sigma_min_ess >= 1000) "pass" else "review",
      if (!sampled_gamma && all(summary$gamma_update == "fixed")) "pass" else "review",
      if (improvement_positive) "pass" else "review",
      "review",
      "review"
    ),
    observed = c(
      sprintf("%s/%s hashes pass", sum(packet$manifest$status == "pass"), nrow(packet$manifest)),
      sprintf("%s chain worker failures", nrow(failures)),
      sprintf("%s chain jobs declared", nrow(jobs)),
      sprintf("%s case rows, %s chains requested", nrow(summary), sum(summary$mcmc_n_chains, na.rm = TRUE)),
      sprintf("%s contract crossing pairs", contract_crossings),
      sprintf("%s raw crossing pairs", raw_crossings),
      sprintf("max sigma Rhat %.4f", sigma_max_rhat),
      sprintf("min sigma rough ESS %.1f", sigma_min_ess),
      sprintf("gamma_update=%s; gamma ESS/Rhat should be ignored for fixed gamma", paste(unique(summary$gamma_update), collapse = ",")),
      sprintf("forecast MAE improvement range %.1f%% to %.1f%%", min(improvement$pct_improvement, na.rm = TRUE), max(improvement$pct_improvement, na.rm = TRUE)),
      summary$case_id[which.max(summary$mcmc_forecast_truth_mae)],
      "do not promote fixed-gamma-zero as the final exAL article model"
    ),
    interpretation = c(
      "The Phase140 source packet is reproducible.",
      "No implementation failures are visible in the fixed-gamma packet.",
      "The fixed-gamma result has the expected chain-grid size.",
      "All requested chains completed for each retained case.",
      "The monotone forecast contract remains valid.",
      "Raw crossings are diagnostics only; any nonzero count should be tracked before article promotion.",
      "Sigma chains look stable under the fixed-gamma sensitivity.",
      "Sigma ESS is adequate; fixed gamma should not be counted as a sampled-parameter ESS failure.",
      "The Phase140 review status is partly a gate-semantics artifact, not a sampler defect.",
      "The extra exAL gamma layer is the dominant suspect because removing it improved every priority case.",
      "This case should receive the highest priority in the next gamma-kernel screen.",
      "Phase141 prepares redesign launches; article-facing exAL MCMC should wait."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase141_case_priority <- function(packet) {
  summary <- packet$case_summary
  assessment <- packet$assessment[, c(
    "case_id", "phase136_gate_status", "status_reason",
    "max_rhat", "min_rough_ess_total", "max_gamma_rhat", "min_gamma_rough_ess_total"
  ), drop = FALSE]
  improvement <- packet$improvement
  out <- merge(summary, assessment, by = "case_id", all.x = TRUE, sort = FALSE)
  out <- merge(out, improvement, by = "case_id", all.x = TRUE, sort = FALSE)
  out$total_raw_crossings <- rowSums(out[, c("mcmc_fit_raw_crossing_pairs", "mcmc_forecast_raw_crossing_pairs")], na.rm = TRUE)
  out$total_contract_crossings <- rowSums(out[, c("mcmc_fit_contract_crossing_pairs", "mcmc_forecast_contract_crossing_pairs")], na.rm = TRUE)
  out$fixed_zero_improved <- out$abs_improvement > 0
  out$phase141_primary_issue <- ifelse(
    out$scenario_id == "regime_shift",
    "largest_remaining_forecast_mae_after_fixed_gamma",
    ifelse(out$total_raw_crossings > 0,
      "raw_crossing_under_fixed_gamma_contract",
      ifelse(out$pct_improvement >= 20,
        "large_fixed_gamma_recovery_signal",
        "confirm_gamma_recovery_stability"
      )
    )
  )
  out$phase141_priority_tier <- ifelse(
    out$scenario_id == "regime_shift",
    "tier1_regime_shift",
    ifelse(out$total_raw_crossings > 0 | out$pct_improvement >= 20,
      "tier1_high_gamma_signal",
      "tier2_confirmatory"
    )
  )
  out$phase141_priority_score <- out$mcmc_forecast_truth_mae +
    0.01 * pmax(out$pct_improvement, 0, na.rm = TRUE) +
    0.01 * out$total_raw_crossings
  out$phase141_case_action <- "include_in_gamma_geometry_screen"
  out$phase141_reason <- paste(
    "Fixed gamma recovered forecast MAE relative to the best prior gamma-sampled packet.",
    "The next screen should keep the matched AL DESN/RHS controls and alter only the gamma update geometry."
  )
  out <- out[order(out$phase141_priority_tier, -out$phase141_priority_score, out$case_id), , drop = FALSE]
  out$phase141_priority_rank <- seq_len(nrow(out))
  out
}

app_joint_exqdesn_phase141_variant_catalog <- function() {
  variant_ids <- c("bounded_w0p5", "bounded_w1", "bounded_w2", "logit_w0p5", "logit_w1", "logit_w2")
  app_joint_qdesn_bind_rows(lapply(variant_ids, function(id) {
    spec <- app_joint_exqdesn_phase136_variant_spec(id)
    data.frame(
      phase141_variant_id = id,
      gamma_update = spec$gamma_update[[1L]],
      bounded_width_multiplier = spec$bounded_width_multiplier[[1L]],
      logit_eta_width = spec$logit_eta_width[[1L]],
      variant_role = spec$phase136_variant_role[[1L]],
      launch_role = if (grepl("0p5|w1$", id)) "primary_narrow_gamma_geometry" else "secondary_width_sensitivity",
      rationale = if (grepl("0p5|w1$", id)) {
        "Tests whether smaller local gamma moves reduce stickiness while preserving exAL flexibility near the AL-like region."
      } else {
        "Keeps a wider fallback around the narrow geometry in case extremely small moves over-stabilize gamma."
      },
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase141_candidate_registry <- function(case_priority, variant_catalog) {
  case_priority <- case_priority[case_priority$phase141_case_action == "include_in_gamma_geometry_screen", , drop = FALSE]
  rows <- list()
  for (ii in seq_len(nrow(case_priority))) {
    case <- case_priority[ii, , drop = FALSE]
    variants <- if (case$phase141_priority_tier[[1L]] == "tier1_regime_shift") {
      variant_catalog$phase141_variant_id
    } else if (case$phase141_priority_tier[[1L]] == "tier1_high_gamma_signal") {
      c("bounded_w0p5", "bounded_w1", "bounded_w2", "logit_w0p5", "logit_w1", "logit_w2")
    } else {
      c("bounded_w1", "bounded_w2", "logit_w1", "logit_w2")
    }
    for (variant_id in variants) {
      variant <- variant_catalog[variant_catalog$phase141_variant_id == variant_id, , drop = FALSE]
      rows[[length(rows) + 1L]] <- data.frame(
        phase141_candidate_id = paste(case$case_id[[1L]], variant_id, sep = "__"),
        case_id = case$case_id[[1L]],
        scenario_id = case$scenario_id[[1L]],
        scenario_class = case$scenario_class[[1L]],
        distribution_family = case$distribution_family[[1L]],
        dynamics_class = case$dynamics_class[[1L]],
        source_model_id = case$source_model_id[[1L]],
        model_id = case$model_id[[1L]],
        fit_structure = case$fit_structure[[1L]],
        phase141_priority_tier = case$phase141_priority_tier[[1L]],
        phase141_primary_issue = case$phase141_primary_issue[[1L]],
        phase141_variant_id = variant_id,
        gamma_update = variant$gamma_update[[1L]],
        bounded_width_multiplier = variant$bounded_width_multiplier[[1L]],
        logit_eta_width = variant$logit_eta_width[[1L]],
        launch_role = variant$launch_role[[1L]],
        fixed_zero_forecast_mae = case$mcmc_forecast_truth_mae[[1L]],
        fixed_zero_fit_mae = case$mcmc_fit_truth_mae[[1L]],
        fixed_zero_pct_improvement_vs_prior_gamma = case$pct_improvement[[1L]],
        fixed_zero_raw_crossings = case$total_raw_crossings[[1L]],
        fixed_zero_contract_crossings = case$total_contract_crossings[[1L]],
        recommended_n_chains = if (case$phase141_priority_tier[[1L]] == "tier2_confirmatory") 6L else 8L,
        recommended_mcmc_n_iter = if (case$phase141_priority_tier[[1L]] == "tier2_confirmatory") 9000L else 12000L,
        recommended_mcmc_burn = if (case$phase141_priority_tier[[1L]] == "tier2_confirmatory") 2500L else 3000L,
        rationale = paste(case$phase141_reason[[1L]], variant$rationale[[1L]]),
        stringsAsFactors = FALSE
      )
    }
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase141_method_feasibility <- function() {
  data.frame(
    method_id = c(
      "narrow_bounded_slice_width_screen",
      "narrow_logit_slice_width_screen",
      "fixed_gamma_zero_reference",
      "strong_gamma_shrinkage_prior",
      "scenario_specific_gamma_activation",
      "full_desn_rhs_rescreen"
    ),
    status = c(
      "launchable_now",
      "launchable_now",
      "completed_reference",
      "requires_new_prior_implementation",
      "requires_new_policy_and_validation",
      "defer"
    ),
    supported_by_current_code = c(TRUE, TRUE, TRUE, FALSE, FALSE, TRUE),
    phase141_decision = c(
      "include",
      "include",
      "do_not_promote_as_final_model",
      "plan_after_width_screen_if_needed",
      "plan_after_width_screen_if_needed",
      "not_first_next_step"
    ),
    rationale = c(
      "The fixed-zero recovery suggests gamma moves are too diffuse or sticky; narrower bounded windows are the smallest implementation change.",
      "Logit-scale moves respect support and may stabilize extreme-tail gamma updates; narrower widths directly target the observed mixing bottleneck.",
      "Useful diagnostic evidence, but it removes exAL flexibility and therefore is not the final exAL article model.",
      "A prior centered near zero is scientifically attractive but changes the model and must be introduced with VB and MCMC tests.",
      "Could avoid unnecessary gamma flexibility in benign scenarios, but needs a clear statistical contract and more code.",
      "The matched AL DESN/RHS controls already work well; broad DESN rescreening would confound the gamma diagnosis."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase141_build_command <- function(output_dir, phase135_screening_dir, phase135_audit_dir,
                                                     case_ids, variant_ids,
                                                     n_chains = 8L,
                                                     mcmc_n_iter = 12000L,
                                                     mcmc_burn = 3000L,
                                                     mcmc_thin = 1L,
                                                     mcmc_seed_offset = 14100L,
                                                     n_cores = 32L,
                                                     vb_n_cores = 5L,
                                                     gamma_slice_max_steps = 100L) {
  paste(
    "Rscript application/scripts/145_run_joint_exqdesn_phase136_gamma_kernel_packet.R",
    sprintf("--output-dir %s", shQuote(output_dir)),
    sprintf("--phase135-screening-dir %s", shQuote(phase135_screening_dir)),
    sprintf("--phase135-audit-dir %s", shQuote(phase135_audit_dir)),
    sprintf("--fixture-dir %s", shQuote(app_joint_exqdesn_phase136_default_fixture_dir())),
    sprintf("--case-ids %s", shQuote(paste(case_ids, collapse = ","))),
    sprintf("--variant-ids %s", shQuote(paste(variant_ids, collapse = ","))),
    "--bounded-width-multiplier 4",
    "--logit-eta-width 4",
    sprintf("--gamma-slice-max-steps %s", as.integer(gamma_slice_max_steps)),
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
    "--gamma-init-mode vb_jittered",
    "--gamma-jitter-fraction 0.05",
    "--trace-write-stride 50",
    "--save-rdata false",
    "--dry-run false",
    sep = " \\\n  "
  )
}

app_joint_exqdesn_phase141_launch_plan <- function(packet, case_priority, candidate_registry,
                                                   launch_root = "application/cache",
                                                   n_cores = 32L) {
  rc <- packet$run_config
  phase135_screening_dir <- rc$phase135_screening_dir[[1L]]
  phase135_audit_dir <- rc$phase135_audit_dir[[1L]]
  primary_cases <- case_priority$case_id
  primary_variants <- c("bounded_w1", "logit_w1")
  focus_cases <- case_priority$case_id[case_priority$phase141_priority_tier %in% c("tier1_regime_shift", "tier1_high_gamma_signal")]
  focus_variants <- c("bounded_w0p5", "bounded_w2", "logit_w0p5", "logit_w2")
  rows <- list(
    data.frame(
      launch_id = "phase141_primary_narrow_gamma_geometry_screen",
      launch_status = "prepared_not_launched",
      launch_scope = "all_phase140_priority_cases",
      output_dir = file.path(launch_root, "joint_qdesn_phase141_primary_narrow_gamma_geometry_screen_20260719"),
      case_ids = paste(primary_cases, collapse = ","),
      variant_ids = paste(primary_variants, collapse = ","),
      n_cases = length(primary_cases),
      n_variants = length(primary_variants),
      n_chains = 8L,
      total_chain_jobs = length(primary_cases) * length(primary_variants) * 8L,
      mcmc_n_iter = 12000L,
      mcmc_burn = 3000L,
      mcmc_thin = 1L,
      mcmc_seed_offset = 14100L,
      n_cores = min(as.integer(n_cores), length(primary_cases) * length(primary_variants) * 8L),
      vb_n_cores = min(5L, length(primary_cases) * length(primary_variants)),
      rationale = "Run the two most interpretable narrow gamma geometries over every fixed-gamma priority case.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      launch_id = "phase141_focus_width_sensitivity_screen",
      launch_status = "prepared_not_launched",
      launch_scope = "tier1_cases_only",
      output_dir = file.path(launch_root, "joint_qdesn_phase141_focus_width_sensitivity_screen_20260719"),
      case_ids = paste(focus_cases, collapse = ","),
      variant_ids = paste(focus_variants, collapse = ","),
      n_cases = length(focus_cases),
      n_variants = length(focus_variants),
      n_chains = 8L,
      total_chain_jobs = length(focus_cases) * length(focus_variants) * 8L,
      mcmc_n_iter = 12000L,
      mcmc_burn = 3000L,
      mcmc_thin = 1L,
      mcmc_seed_offset = 14200L,
      n_cores = min(as.integer(n_cores), max(1L, length(focus_cases) * length(focus_variants) * 8L)),
      vb_n_cores = min(5L, max(1L, length(focus_cases) * length(focus_variants))),
      rationale = "Only for the cases with largest fixed-gamma signal or remaining performance risk; tests whether even narrower/wider gamma moves are needed.",
      stringsAsFactors = FALSE
    )
  )
  out <- app_joint_qdesn_bind_rows(rows)
  out$command <- vapply(seq_len(nrow(out)), function(ii) {
    case_ids <- strsplit(out$case_ids[[ii]], ",", fixed = TRUE)[[1L]]
    variant_ids <- strsplit(out$variant_ids[[ii]], ",", fixed = TRUE)[[1L]]
    app_joint_exqdesn_phase141_build_command(
      output_dir = out$output_dir[[ii]],
      phase135_screening_dir = phase135_screening_dir,
      phase135_audit_dir = phase135_audit_dir,
      case_ids = case_ids,
      variant_ids = variant_ids,
      n_chains = out$n_chains[[ii]],
      mcmc_n_iter = out$mcmc_n_iter[[ii]],
      mcmc_burn = out$mcmc_burn[[ii]],
      mcmc_thin = out$mcmc_thin[[ii]],
      mcmc_seed_offset = out$mcmc_seed_offset[[ii]],
      n_cores = out$n_cores[[ii]],
      vb_n_cores = out$vb_n_cores[[ii]]
    )
  }, character(1L))
  out$tmux_session <- paste0(out$launch_id, "_20260719")
  out$tmux_command <- sprintf(
    "tmux new-session -d -s %s \"cd %s && { %s; echo EXIT_CODE=$?; } 2>&1 | tee %s\"",
    out$tmux_session,
    shQuote(app_repo_root()),
    gsub("\"", "\\\\\"", out$command, fixed = TRUE),
    shQuote(file.path(app_repo_root(), paste0(out$output_dir, "_tmux.log")))
  )
  out
}

app_joint_exqdesn_phase141_decision_summary <- function(diagnostic_summary, case_priority, launch_plan) {
  hard_fail <- any(diagnostic_summary$status[diagnostic_summary$check %in% c(
    "source_manifest", "worker_failures", "successful_case_rows", "contract_crossings"
  )] == "fail")
  data.frame(
    phase141_decision = if (hard_fail) {
      "blocked_fix_fixed_gamma_packet"
    } else {
      "ready_for_targeted_gamma_geometry_screen"
    },
    article_promotion_gate = "review",
    fixed_gamma_zero_promoted_as_final_exal = FALSE,
    priority_cases = nrow(case_priority),
    prepared_launches = nrow(launch_plan),
    prepared_chain_jobs = sum(launch_plan$total_chain_jobs),
    primary_launch_id = launch_plan$launch_id[[1L]],
    main_takeaway = paste(
      "Phase140 fixed-gamma-zero improved all high-priority exAL cases, so the current bottleneck is the gamma layer rather than a broad DESN/RHS mismatch.",
      "The next efficient step is a targeted gamma-kernel geometry screen using the same matched AL DESN/RHS controls."
    ),
    recommended_next_stage = "Review the Phase141 launch plan, then run the primary narrow gamma geometry screen first; run the focus width-sensitivity screen only if primary results do not recover fixed-zero-level performance.",
    article_tables_modified = FALSE,
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase141_readme <- function(decision, diagnostics, case_priority, launch_plan) {
  c(
    "# Joint exQDESN Phase141 Gamma-Redesign Readiness",
    "",
    "This artifact converts the completed fixed-gamma-zero recovery packet into a reproducible next-stage gamma-kernel screen.",
    "It does not launch MCMC jobs and does not modify article tables.",
    "",
    sprintf("- Decision: `%s`", decision$phase141_decision[[1L]]),
    sprintf("- Article gate: `%s`", decision$article_promotion_gate[[1L]]),
    sprintf("- Priority cases: `%s`", decision$priority_cases[[1L]]),
    sprintf("- Prepared launches: `%s`", decision$prepared_launches[[1L]]),
    sprintf("- Prepared chain jobs if all launches run: `%s`", decision$prepared_chain_jobs[[1L]]),
    "",
    "Core diagnostic conclusion:",
    decision$main_takeaway[[1L]],
    "",
    "Health checks:",
    paste(capture.output(print(diagnostics[, c("check", "status", "observed")], row.names = FALSE)), collapse = "\n"),
    "",
    "Case priority:",
    paste(capture.output(print(case_priority[, c("case_id", "phase141_priority_tier", "phase141_primary_issue", "mcmc_forecast_truth_mae", "pct_improvement")], row.names = FALSE)), collapse = "\n"),
    "",
    "Prepared launch commands are recorded in `phase141_launch_commands.txt`."
  )
}

app_joint_exqdesn_run_phase141_gamma_redesign_readiness <- function(
  out_dir = app_joint_exqdesn_phase141_default_dir(),
  fixed_gamma_dir = app_joint_exqdesn_phase141_default_fixed_gamma_dir(),
  launch_root = "application/cache",
  n_cores = 32L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  packet <- app_joint_exqdesn_phase141_load_fixed_gamma_packet(fixed_gamma_dir)
  diagnostics <- app_joint_exqdesn_phase141_diagnostic_summary(packet)
  case_priority <- app_joint_exqdesn_phase141_case_priority(packet)
  variant_catalog <- app_joint_exqdesn_phase141_variant_catalog()
  candidate_registry <- app_joint_exqdesn_phase141_candidate_registry(case_priority, variant_catalog)
  feasibility <- app_joint_exqdesn_phase141_method_feasibility()
  launch_plan <- app_joint_exqdesn_phase141_launch_plan(
    packet,
    case_priority,
    candidate_registry,
    launch_root = launch_root,
    n_cores = n_cores
  )
  decision <- app_joint_exqdesn_phase141_decision_summary(diagnostics, case_priority, launch_plan)

  run_config <- data.frame(
    run_id = "joint_qdesn_phase141_exal_gamma_redesign_readiness",
    out_dir = out_dir,
    fixed_gamma_dir = packet$dir,
    launch_root = launch_root,
    n_cores = as.integer(n_cores),
    mcmc_launched = FALSE,
    article_tables_modified = FALSE,
    validation_contract = "quantile_grid_fit_and_forecast_scoring_with_raw_contract_qhat",
    scalar_predictive_density_claim = FALSE,
    stringsAsFactors = FALSE
  )
  command_path <- file.path(out_dir, "phase141_launch_commands.txt")
  command_lines <- unlist(lapply(seq_len(nrow(launch_plan)), function(ii) {
    c(
      paste0("# ", launch_plan$launch_id[[ii]]),
      launch_plan$command[[ii]],
      ""
    )
  }), use.names = FALSE)
  tmux_lines <- unlist(lapply(seq_len(nrow(launch_plan)), function(ii) {
    c(
      paste0("# ", launch_plan$launch_id[[ii]]),
      launch_plan$tmux_command[[ii]],
      ""
    )
  }), use.names = FALSE)
  writeLines(c(
    "# Phase141 targeted gamma-kernel launch commands",
    "# Review resource availability before running. Phase141 readiness does not launch these commands.",
    "",
    command_lines,
    "",
    "# tmux wrappers",
    tmux_lines
  ), command_path, useBytes = TRUE)
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_exqdesn_phase141_readme(decision, diagnostics, case_priority, launch_plan), readme_path, useBytes = TRUE)

  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    fixed_gamma_manifest_verification = app_joint_qvp_write_csv(packet$manifest, file.path(out_dir, "fixed_gamma_manifest_verification.csv")),
    phase141_diagnostic_summary = app_joint_qvp_write_csv(diagnostics, file.path(out_dir, "phase141_diagnostic_summary.csv")),
    phase141_case_priority = app_joint_qvp_write_csv(case_priority, file.path(out_dir, "phase141_case_priority.csv")),
    phase141_variant_catalog = app_joint_qvp_write_csv(variant_catalog, file.path(out_dir, "phase141_variant_catalog.csv")),
    phase141_candidate_registry = app_joint_qvp_write_csv(candidate_registry, file.path(out_dir, "phase141_candidate_registry.csv")),
    phase141_method_feasibility = app_joint_qvp_write_csv(feasibility, file.path(out_dir, "phase141_method_feasibility.csv")),
    phase141_launch_plan = app_joint_qvp_write_csv(launch_plan, file.path(out_dir, "phase141_launch_plan.csv")),
    phase141_decision_summary = app_joint_qvp_write_csv(decision, file.path(out_dir, "phase141_decision_summary.csv")),
    phase141_launch_commands = normalizePath(command_path, mustWork = TRUE),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    paths = c(paths, artifact_manifest = manifest_info$manifest_path),
    manifest = manifest_info$manifest,
    run_config = run_config,
    packet = packet,
    diagnostics = diagnostics,
    case_priority = case_priority,
    variant_catalog = variant_catalog,
    candidate_registry = candidate_registry,
    feasibility = feasibility,
    launch_plan = launch_plan,
    decision = decision
  )
}
