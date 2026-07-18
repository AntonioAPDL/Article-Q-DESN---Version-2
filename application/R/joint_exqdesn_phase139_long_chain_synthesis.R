# Phase139 synthesis audit for selected long-chain exQDESN confirmation.

app_joint_exqdesn_phase139_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase139_exal_long_chain_synthesis_20260717")
}

app_joint_exqdesn_phase139_default_phase135_screening_dir <- function() {
  app_path("application/cache/joint_qdesn_phase135_matched_exal_screening_20260715")
}

app_joint_exqdesn_phase139_default_phase135_audit_dir <- function() {
  file.path(app_joint_exqdesn_phase139_default_phase135_screening_dir(), "phase135_result_audit")
}

app_joint_exqdesn_phase139_default_phase136_dir <- function() {
  app_path("application/cache/joint_qdesn_phase136_exal_gamma_kernel_packet_20260715")
}

app_joint_exqdesn_phase139_default_phase137_dir <- function() {
  app_path("application/cache/joint_qdesn_phase137_exal_gamma_kernel_readiness_20260716")
}

app_joint_exqdesn_phase139_default_phase138_orchestration_dir <- function() {
  app_path("application/cache/joint_qdesn_phase138_selected_long_chain_confirmation_20260716_orchestration")
}

app_joint_exqdesn_phase139_default_phase138_dirs <- function() {
  c(
    bounded_w4 = app_path("application/cache/joint_qdesn_phase138_exal_selected_long_chain_confirmation_20260716_bounded_w4"),
    logit_w4 = app_path("application/cache/joint_qdesn_phase138_exal_selected_long_chain_confirmation_20260716_logit_w4")
  )
}

app_joint_exqdesn_phase139_required_phase138_files <- function() {
  c(
    "run_config.csv",
    "artifact_manifest.csv",
    "phase136_selected_cases.csv",
    "phase136_variant_registry.csv",
    "phase136_chain_jobs.csv",
    "phase136_case_variant_prep_failures.csv",
    "phase136_chain_worker_failures.csv",
    "phase136_mcmc_case_summary.csv",
    "phase136_case_assessment.csv",
    "phase136_best_variant_by_case.csv",
    "runtime_summary.csv",
    "mcmc_rhat_ess_summary.csv",
    "autocorrelation_summary.csv"
  )
}

app_joint_exqdesn_phase139_status_rank <- function(x) {
  ranks <- c(pass = 1L, review = 2L, fail = 3L)
  vals <- ranks[as.character(x)]
  vals[is.na(vals)] <- 3L
  vals
}

app_joint_exqdesn_phase139_worst_status <- function(x) {
  x <- as.character(x)
  if (!length(x)) return("fail")
  x <- x[nzchar(x)]
  if (!length(x)) return("fail")
  c("pass", "review", "fail")[max(app_joint_exqdesn_phase139_status_rank(x))]
}

app_joint_exqdesn_phase139_numeric <- function(x) {
  suppressWarnings(as.numeric(x))
}

app_joint_exqdesn_phase139_finite_all <- function(x) {
  x <- app_joint_exqdesn_phase139_numeric(x)
  length(x) > 0L && all(is.finite(x))
}

app_joint_exqdesn_phase139_source_row <- function(source_label, dir, manifest, kind = "artifact") {
  strict_vec <- if ("strict_status" %in% names(manifest)) manifest$strict_status else manifest$status
  strict_status <- if (identical(kind, "strict_manifest")) {
    if (all(strict_vec == "pass")) "pass" else "review"
  } else if ("strict_status" %in% names(manifest)) {
    if (all(manifest$strict_status == "pass")) "pass" else "review"
  } else {
    if (all(manifest$status == "pass")) "pass" else "fail"
  }
  repaired_status <- if (identical(kind, "strict_manifest")) {
    "not_applicable"
  } else {
    if (all(manifest$status == "pass")) "pass" else "fail"
  }
  data.frame(
    source_label = source_label,
    source_kind = kind,
    source_dir = normalizePath(dir, mustWork = FALSE),
    manifest_rows = nrow(manifest),
    strict_pass = sum(strict_vec == "pass", na.rm = TRUE),
    repaired_pass = sum(manifest$status == "pass", na.rm = TRUE),
    strict_status = strict_status,
    repaired_status = repaired_status,
    repair_rows = if ("repair_action" %in% names(manifest)) sum(manifest$repair_action != "none", na.rm = TRUE) else 0L,
    figure_path_repair_rows = if ("repair_action" %in% names(manifest)) {
      sum(manifest$repair_action == "figures_subdir_path_repair", na.rm = TRUE)
    } else {
      0L
    },
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase139_read_exit_file <- function(path) {
  if (!file.exists(path)) return(NA_integer_)
  value <- suppressWarnings(as.integer(trimws(readLines(path, warn = FALSE)[1L])))
  if (is.na(value)) NA_integer_ else value
}

app_joint_exqdesn_phase139_check_required <- function(dir, required, label) {
  missing <- required[!file.exists(file.path(dir, required))]
  if (length(missing)) {
    stop(sprintf("%s artifact is missing required files: %s", label, paste(missing, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}

app_joint_exqdesn_phase139_load_group <- function(dir, group_id) {
  dir <- normalizePath(dir, mustWork = TRUE)
  app_joint_exqdesn_phase139_check_required(
    dir,
    app_joint_exqdesn_phase139_required_phase138_files(),
    sprintf("Phase138 group '%s'", group_id)
  )
  list(
    group_id = group_id,
    dir = dir,
    strict_manifest = app_joint_qdesn_phase108_manifest_verify(dir, paste0("phase138_", group_id, "_strict")),
    repaired_manifest = app_joint_exqdesn_phase137_verify_manifest_with_repairs(dir, paste0("phase138_", group_id, "_repaired")),
    run_config = app_read_csv(file.path(dir, "run_config.csv")),
    selected_cases = app_read_csv(file.path(dir, "phase136_selected_cases.csv")),
    variant_registry = app_read_csv(file.path(dir, "phase136_variant_registry.csv")),
    chain_jobs = app_read_csv(file.path(dir, "phase136_chain_jobs.csv")),
    prep_failures = app_read_csv(file.path(dir, "phase136_case_variant_prep_failures.csv")),
    chain_failures = app_read_csv(file.path(dir, "phase136_chain_worker_failures.csv")),
    mcmc_summary = app_read_csv(file.path(dir, "phase136_mcmc_case_summary.csv")),
    assessment = app_read_csv(file.path(dir, "phase136_case_assessment.csv")),
    best_by_case = app_read_csv(file.path(dir, "phase136_best_variant_by_case.csv")),
    runtime = app_read_csv(file.path(dir, "runtime_summary.csv")),
    rhat = app_read_csv(file.path(dir, "mcmc_rhat_ess_summary.csv")),
    autocorrelation = app_read_csv(file.path(dir, "autocorrelation_summary.csv"))
  )
}

app_joint_exqdesn_phase139_load_sources <- function(
  phase135_screening_dir = app_joint_exqdesn_phase139_default_phase135_screening_dir(),
  phase135_audit_dir = app_joint_exqdesn_phase139_default_phase135_audit_dir(),
  phase136_dir = app_joint_exqdesn_phase139_default_phase136_dir(),
  phase137_dir = app_joint_exqdesn_phase139_default_phase137_dir(),
  phase138_dirs = app_joint_exqdesn_phase139_default_phase138_dirs(),
  phase138_orchestration_dir = app_joint_exqdesn_phase139_default_phase138_orchestration_dir()
) {
  phase135_screening_dir <- normalizePath(phase135_screening_dir, mustWork = TRUE)
  phase135_audit_dir <- normalizePath(phase135_audit_dir, mustWork = TRUE)
  phase136_dir <- normalizePath(phase136_dir, mustWork = TRUE)
  phase137_dir <- normalizePath(phase137_dir, mustWork = TRUE)
  phase138_orchestration_dir <- normalizePath(phase138_orchestration_dir, mustWork = TRUE)
  phase138_dirs <- vapply(phase138_dirs, normalizePath, character(1L), mustWork = TRUE)

  required_phase135_audit <- c(
    "artifact_manifest.csv",
    "phase135_matched_exal_vs_source_al_vb_comparison.csv",
    "phase135_result_decision.csv"
  )
  app_joint_exqdesn_phase139_check_required(phase135_audit_dir, required_phase135_audit, "Phase135 audit")
  app_joint_exqdesn_phase139_check_required(phase137_dir, c(
    "artifact_manifest.csv",
    "phase137_selected_case_kernel_registry.csv",
    "phase137_next_launch_plan.csv",
    "phase137_decision_summary.csv"
  ), "Phase137 readiness")

  phase136 <- app_joint_exqdesn_phase137_load_phase136(phase136_dir)
  phase138_groups <- Map(app_joint_exqdesn_phase139_load_group, phase138_dirs, names(phase138_dirs))

  list(
    phase135_screening_dir = phase135_screening_dir,
    phase135_audit_dir = phase135_audit_dir,
    phase136 = phase136,
    phase137_dir = phase137_dir,
    phase137_selected_registry = app_read_csv(file.path(phase137_dir, "phase137_selected_case_kernel_registry.csv")),
    phase137_launch_plan = app_read_csv(file.path(phase137_dir, "phase137_next_launch_plan.csv")),
    phase137_decision = app_read_csv(file.path(phase137_dir, "phase137_decision_summary.csv")),
    phase137_manifest = app_joint_qdesn_phase108_manifest_verify(phase137_dir, "phase137"),
    phase138_orchestration_dir = phase138_orchestration_dir,
    phase138_orchestration_manifest = app_joint_qdesn_phase108_manifest_verify(phase138_orchestration_dir, "phase138_orchestration"),
    phase138_scheduler_exit = app_joint_exqdesn_phase139_read_exit_file(file.path(phase138_orchestration_dir, "phase138_scheduler.exit")),
    phase138_group_exits = app_joint_qdesn_bind_rows(lapply(names(phase138_dirs), function(group_id) {
      idx <- match(group_id, names(phase138_dirs))
      exit_path <- file.path(phase138_orchestration_dir, sprintf("%02d_selected_%s.exit", idx, group_id))
      data.frame(
        group_id = group_id,
        exit_path = normalizePath(exit_path, mustWork = FALSE),
        exit_code = app_joint_exqdesn_phase139_read_exit_file(exit_path),
        stringsAsFactors = FALSE
      )
    })),
    phase138_groups = phase138_groups,
    phase135_screening_manifest = app_joint_qdesn_phase108_manifest_verify(phase135_screening_dir, "phase135_screening"),
    phase135_audit_manifest = app_joint_qdesn_phase108_manifest_verify(phase135_audit_dir, "phase135_audit"),
    phase135_comparison = app_read_csv(file.path(phase135_audit_dir, "phase135_matched_exal_vs_source_al_vb_comparison.csv")),
    phase135_decision = app_read_csv(file.path(phase135_audit_dir, "phase135_result_decision.csv"))
  )
}

app_joint_exqdesn_phase139_combined_phase138_assessment <- function(sources) {
  app_joint_qdesn_bind_rows(lapply(sources$phase138_groups, function(group) {
    out <- group$assessment
    out$phase138_group_id <- group$group_id
    out$phase138_dir <- group$dir
    out
  }))
}

app_joint_exqdesn_phase139_source_manifest_audit <- function(sources) {
  rows <- list(
    app_joint_exqdesn_phase139_source_row("phase135_screening", sources$phase135_screening_dir, sources$phase135_screening_manifest),
    app_joint_exqdesn_phase139_source_row("phase135_audit", sources$phase135_audit_dir, sources$phase135_audit_manifest),
    app_joint_exqdesn_phase139_source_row("phase136_strict", sources$phase136$dir, sources$phase136$strict_manifest, kind = "strict_manifest"),
    app_joint_exqdesn_phase139_source_row("phase136_repaired", sources$phase136$dir, sources$phase136$repaired_manifest, kind = "repaired_manifest"),
    app_joint_exqdesn_phase139_source_row("phase137", sources$phase137_dir, sources$phase137_manifest),
    app_joint_exqdesn_phase139_source_row("phase138_orchestration", sources$phase138_orchestration_dir, sources$phase138_orchestration_manifest)
  )
  for (group in sources$phase138_groups) {
    rows[[length(rows) + 1L]] <- app_joint_exqdesn_phase139_source_row(
      paste0("phase138_", group$group_id, "_strict"),
      group$dir,
      group$strict_manifest,
      kind = "strict_manifest"
    )
    rows[[length(rows) + 1L]] <- app_joint_exqdesn_phase139_source_row(
      paste0("phase138_", group$group_id, "_repaired"),
      group$dir,
      group$repaired_manifest,
      kind = "repaired_manifest"
    )
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase139_health_summary <- function(sources, phase138_assessment, manifest_audit) {
  expected_cases <- unique(sources$phase137_selected_registry$case_id)
  observed_cases <- unique(phase138_assessment$case_id)
  group_exit_pass <- all(sources$phase138_group_exits$exit_code == 0L)
  chain_jobs <- app_joint_qdesn_bind_rows(lapply(sources$phase138_groups, function(group) {
    group$chain_jobs
  }))
  prep_failures <- app_joint_qdesn_bind_rows(lapply(sources$phase138_groups, function(group) {
    group$prep_failures
  }))
  chain_failures <- app_joint_qdesn_bind_rows(lapply(sources$phase138_groups, function(group) {
    group$chain_failures
  }))
  raw_crossings <- sum(
    phase138_assessment$mcmc_fit_raw_crossing_pairs,
    phase138_assessment$mcmc_forecast_raw_crossing_pairs,
    na.rm = TRUE
  )
  contract_crossings <- sum(
    phase138_assessment$mcmc_fit_contract_crossing_pairs,
    phase138_assessment$mcmc_forecast_contract_crossing_pairs,
    na.rm = TRUE
  )
  finite_metrics <- all(vapply(c(
    "mcmc_fit_truth_mae",
    "mcmc_forecast_truth_mae",
    "mcmc_fit_check_loss_mean",
    "mcmc_forecast_check_loss_mean",
    "max_rhat",
    "min_rough_ess_total",
    "max_gamma_rhat",
    "min_gamma_rough_ess_total"
  ), function(col) app_joint_exqdesn_phase139_finite_all(phase138_assessment[[col]]), logical(1L)))
  gate_counts <- table(phase138_assessment$phase136_gate_status)
  gamma_review_rows <- sum(grepl("gamma lag-1 autocorrelation", phase138_assessment$status_reason, fixed = TRUE), na.rm = TRUE)
  rhat_review_rows <- sum(is.finite(phase138_assessment$max_rhat) & phase138_assessment$max_rhat > 1.2, na.rm = TRUE)
  manifest_repaired_failures <- sum(manifest_audit$repaired_status == "fail")
  manifest_strict_reviews <- sum(manifest_audit$strict_status == "review")

  app_joint_qdesn_bind_rows(list(
    data.frame(
      check = "Phase138 scheduler exit",
      status = if (identical(as.integer(sources$phase138_scheduler_exit), 0L)) "pass" else "fail",
      observed = as.character(sources$phase138_scheduler_exit),
      implication = "The selected long-chain scheduler completed.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Phase138 group exits",
      status = if (group_exit_pass) "pass" else "fail",
      observed = paste(sprintf("%s=%s", sources$phase138_group_exits$group_id, sources$phase138_group_exits$exit_code), collapse = ", "),
      implication = "Both selected kernel groups must finish cleanly.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Selected case completion",
      status = if (setequal(expected_cases, observed_cases)) "pass" else "fail",
      observed = sprintf("%s/%s selected cases observed", length(intersect(expected_cases, observed_cases)), length(expected_cases)),
      implication = "Phase138 covers the complete Phase137 selected registry.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Worker failures",
      status = if (nrow(prep_failures) == 0L && nrow(chain_failures) == 0L) "pass" else "fail",
      observed = sprintf("%s prep failures, %s chain failures, %s chain jobs", nrow(prep_failures), nrow(chain_failures), nrow(chain_jobs)),
      implication = "No rerun is needed for failed workers.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Manifest verification",
      status = if (manifest_repaired_failures == 0L) {
        if (manifest_strict_reviews == 0L) "pass" else "review"
      } else {
        "fail"
      },
      observed = sprintf("%s repaired failures, %s strict review sources", manifest_repaired_failures, manifest_strict_reviews),
      implication = "Figure-path repairs are recorded instead of mutating source artifacts.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Finite metrics",
      status = if (finite_metrics) "pass" else "fail",
      observed = if (finite_metrics) "all required scalar metrics finite" else "one or more required scalar metrics nonfinite",
      implication = "The Phase138 packet can be compared against prior stages.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Raw qhat crossings",
      status = if (raw_crossings == 0L) "pass" else "review",
      observed = sprintf("%s raw crossing pairs", raw_crossings),
      implication = "Raw crossings remain diagnostic; contract qhat is used for scores.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Contract qhat crossings",
      status = if (contract_crossings == 0L) "pass" else "fail",
      observed = sprintf("%s contract crossing pairs", contract_crossings),
      implication = "Scored forecast and fit grids must be noncrossing.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Phase138 case gates",
      status = if (all(phase138_assessment$phase136_gate_status == "pass")) "pass" else if (any(phase138_assessment$phase136_gate_status == "fail")) "fail" else "review",
      observed = paste(sprintf("%s=%s", names(gate_counts), as.integer(gate_counts)), collapse = ", "),
      implication = "Review gates prevent article promotion without further interpretation.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Gamma diagnostics",
      status = if (gamma_review_rows == 0L && rhat_review_rows == 0L) "pass" else "review",
      observed = sprintf("%s gamma-autocorrelation review rows, %s Rhat review rows", gamma_review_rows, rhat_review_rows),
      implication = "Longer chains improved ESS but gamma stickiness remains visible.",
      stringsAsFactors = FALSE
    )
  ))
}

app_joint_exqdesn_phase139_phase138_vs_phase136 <- function(sources, phase138_assessment) {
  base <- sources$phase136$best_by_case
  app_joint_qdesn_bind_rows(lapply(seq_len(nrow(phase138_assessment)), function(ii) {
    row <- phase138_assessment[ii, , drop = FALSE]
    matched <- base[base$case_id == row$case_id[[1L]] &
      base$phase136_variant_id == row$phase136_variant_id[[1L]], , drop = FALSE]
    if (!nrow(matched)) return(data.frame())
    matched <- matched[1L, , drop = FALSE]
    data.frame(
      case_id = row$case_id[[1L]],
      scenario_id = row$scenario_id[[1L]],
      source_model_id = row$source_model_id[[1L]],
      phase138_group_id = row$phase138_group_id[[1L]],
      gamma_update = row$gamma_update[[1L]],
      phase136_forecast_mae = matched$mcmc_forecast_truth_mae[[1L]],
      phase138_forecast_mae = row$mcmc_forecast_truth_mae[[1L]],
      delta_forecast_mae_phase138_minus_phase136 = row$mcmc_forecast_truth_mae[[1L]] - matched$mcmc_forecast_truth_mae[[1L]],
      phase136_fit_mae = matched$mcmc_fit_truth_mae[[1L]],
      phase138_fit_mae = row$mcmc_fit_truth_mae[[1L]],
      delta_fit_mae_phase138_minus_phase136 = row$mcmc_fit_truth_mae[[1L]] - matched$mcmc_fit_truth_mae[[1L]],
      phase136_max_gamma_rhat = matched$max_gamma_rhat[[1L]],
      phase138_max_gamma_rhat = row$max_gamma_rhat[[1L]],
      delta_gamma_rhat_phase138_minus_phase136 = row$max_gamma_rhat[[1L]] - matched$max_gamma_rhat[[1L]],
      phase136_min_gamma_ess = matched$min_gamma_rough_ess_total[[1L]],
      phase138_min_gamma_ess = row$min_gamma_rough_ess_total[[1L]],
      delta_gamma_ess_phase138_minus_phase136 = row$min_gamma_rough_ess_total[[1L]] - matched$min_gamma_rough_ess_total[[1L]],
      phase136_gamma_lag1 = matched$max_gamma_lag1_autocorrelation[[1L]],
      phase138_gamma_lag1 = row$max_gamma_lag1_autocorrelation[[1L]],
      delta_gamma_lag1_phase138_minus_phase136 = row$max_gamma_lag1_autocorrelation[[1L]] - matched$max_gamma_lag1_autocorrelation[[1L]],
      forecast_improved = row$mcmc_forecast_truth_mae[[1L]] < matched$mcmc_forecast_truth_mae[[1L]],
      gamma_rhat_improved = row$max_gamma_rhat[[1L]] < matched$max_gamma_rhat[[1L]],
      gamma_ess_improved = row$min_gamma_rough_ess_total[[1L]] > matched$min_gamma_rough_ess_total[[1L]],
      interpretation = if (row$mcmc_forecast_truth_mae[[1L]] < matched$mcmc_forecast_truth_mae[[1L]]) {
        "longer_chain_improves_forecast_mae"
      } else {
        "longer_chain_does_not_improve_forecast_mae"
      },
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase139_exal_vs_matched_al <- function(sources, phase138_assessment) {
  comp <- sources$phase135_comparison
  app_joint_qdesn_bind_rows(lapply(seq_len(nrow(phase138_assessment)), function(ii) {
    row <- phase138_assessment[ii, , drop = FALSE]
    matched <- comp[comp$scenario_id == row$scenario_id[[1L]] &
      comp$target_exal_model_id == row$source_model_id[[1L]], , drop = FALSE]
    if (!nrow(matched)) return(data.frame())
    matched <- matched[1L, , drop = FALSE]
    data.frame(
      case_id = row$case_id[[1L]],
      scenario_id = row$scenario_id[[1L]],
      comparison_class = matched$comparison_class[[1L]],
      source_model_id = row$source_model_id[[1L]],
      phase138_model_id = row$model_id[[1L]],
      phase138_group_id = row$phase138_group_id[[1L]],
      gamma_update = row$gamma_update[[1L]],
      matched_al_fit_mae = matched$al_fit_mae[[1L]],
      phase135_exal_vb_fit_mae = matched$exal_fit_mae[[1L]],
      phase138_exal_mcmc_fit_mae = row$mcmc_fit_truth_mae[[1L]],
      phase138_mcmc_minus_phase135_exal_vb_fit_mae = row$mcmc_fit_truth_mae[[1L]] - matched$exal_fit_mae[[1L]],
      phase138_mcmc_minus_matched_al_fit_mae = row$mcmc_fit_truth_mae[[1L]] - matched$al_fit_mae[[1L]],
      matched_al_forecast_mae = matched$al_forecast_mae[[1L]],
      phase135_exal_vb_forecast_mae = matched$exal_forecast_mae[[1L]],
      phase138_exal_mcmc_forecast_mae = row$mcmc_forecast_truth_mae[[1L]],
      phase138_mcmc_minus_phase135_exal_vb_forecast_mae = row$mcmc_forecast_truth_mae[[1L]] - matched$exal_forecast_mae[[1L]],
      phase138_mcmc_minus_matched_al_forecast_mae = row$mcmc_forecast_truth_mae[[1L]] - matched$al_forecast_mae[[1L]],
      improves_over_phase135_exal_vb_forecast = row$mcmc_forecast_truth_mae[[1L]] < matched$exal_forecast_mae[[1L]],
      matches_or_beats_matched_al_forecast = row$mcmc_forecast_truth_mae[[1L]] <= matched$al_forecast_mae[[1L]],
      matched_al_forecast_raw_crossings = matched$al_forecast_raw_crossings[[1L]],
      phase135_exal_forecast_raw_crossings = matched$exal_forecast_raw_crossings[[1L]],
      phase138_exal_forecast_raw_crossings = row$mcmc_forecast_raw_crossing_pairs[[1L]],
      phase138_exal_forecast_contract_crossings = row$mcmc_forecast_contract_crossing_pairs[[1L]],
      interpretation = if (row$mcmc_forecast_truth_mae[[1L]] <= matched$al_forecast_mae[[1L]]) {
        "exal_mcmc_matches_or_beats_matched_al_forecast"
      } else if (row$mcmc_forecast_truth_mae[[1L]] < matched$exal_forecast_mae[[1L]]) {
        "exal_mcmc_improves_over_exal_vb_but_remains_worse_than_matched_al"
      } else {
        "exal_mcmc_remains_worse_than_matched_al_and_phase135_exal_vb"
      },
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase139_sampler_diagnostic_summary <- function(sources, phase138_assessment) {
  app_joint_qdesn_bind_rows(lapply(sources$phase138_groups, function(group) {
    rt <- group$runtime[group$runtime$runtime_component == "mcmc_chain", , drop = FALSE]
    rh <- group$rhat[group$rhat$parameter == "gamma", , drop = FALSE]
    ac <- group$autocorrelation[group$autocorrelation$parameter == "gamma" & group$autocorrelation$lag == 1L, , drop = FALSE]
    app_joint_qdesn_bind_rows(lapply(split(group$assessment, group$assessment$case_id), function(row) {
      rti <- rt[rt$case_id == row$case_id[[1L]], , drop = FALSE]
      rhi <- rh[rh$case_id == row$case_id[[1L]], , drop = FALSE]
      aci <- ac[ac$case_id == row$case_id[[1L]], , drop = FALSE]
      data.frame(
        case_id = row$case_id[[1L]],
        scenario_id = row$scenario_id[[1L]],
        source_model_id = row$source_model_id[[1L]],
        phase138_group_id = group$group_id,
        gamma_update = row$gamma_update[[1L]],
        n_chains = length(unique(rti$chain_id)),
        n_gamma_parameters = nrow(rhi),
        mean_chain_hours = app_joint_exqdesn_phase137_mean_finite(rti$elapsed_seconds) / 3600,
        median_chain_hours = stats::median(rti$elapsed_seconds, na.rm = TRUE) / 3600,
        max_chain_hours = app_joint_exqdesn_phase137_max_finite(rti$elapsed_seconds) / 3600,
        max_case_rhat = row$max_rhat[[1L]],
        min_case_rough_ess_total = row$min_rough_ess_total[[1L]],
        max_gamma_rhat = row$max_gamma_rhat[[1L]],
        median_gamma_rhat = stats::median(rhi$rhat, na.rm = TRUE),
        min_gamma_rough_ess_total = row$min_gamma_rough_ess_total[[1L]],
        median_gamma_rough_ess_total = stats::median(rhi$rough_ess_total, na.rm = TRUE),
        max_gamma_lag1_autocorrelation = row$max_gamma_lag1_autocorrelation[[1L]],
        median_gamma_lag1_autocorrelation = stats::median(aci$autocorrelation, na.rm = TRUE),
        sampler_gate = if (row$max_rhat[[1L]] <= 1.2 && row$max_gamma_lag1_autocorrelation[[1L]] < 0.995) "pass" else "review",
        sampler_interpretation = if (row$max_rhat[[1L]] <= 1.2 && row$max_gamma_lag1_autocorrelation[[1L]] >= 0.995) {
          "Rhat acceptable or near-acceptable, but gamma lag-1 autocorrelation remains high"
        } else if (row$max_rhat[[1L]] > 1.2) {
          "Rhat remains review-level and gamma stickiness is still visible"
        } else {
          "Sampler diagnostics are acceptable under current review thresholds"
        },
        stringsAsFactors = FALSE
      )
    }))
  }))
}

app_joint_exqdesn_phase139_next_model_redesign_plan <- function(decision_status) {
  data.frame(
    priority = c(1L, 2L, 3L, 4L, 5L),
    experiment = c(
      "gamma_fixed_or_near_al_sensitivity",
      "strong_gamma_shrinkage_prior",
      "centered_or_constrained_gamma_parameterization",
      "case_specific_exal_spec_refinement",
      "posterior_qhat_summary_reporting"
    ),
    rationale = c(
      "Tests whether extra exAL gamma flexibility is hurting forecast quantile recovery relative to the matched AL rows.",
      "Keeps the exAL extension but regularizes gamma toward the AL-like region when data do not strongly support asymmetry.",
      "Targets the posterior geometry that creates high gamma autocorrelation without only increasing chain length.",
      "Uses Phase139 case-level gaps to refine only the scenarios where exAL remains scientifically useful.",
      "Preserves median/trimmed qhat sensitivity as a reporting diagnostic, not as a substitute for fixing model performance."
    ),
    launch_now = FALSE,
    article_role = c(
      "diagnostic_model_redesign_before_article_promotion",
      "diagnostic_model_redesign_before_article_promotion",
      "sampler_and_model_geometry_development",
      "optional_after_model_redesign",
      "appendix_or_robustness_diagnostic"
    ),
    dependency = c(
      "Phase139 confirms exAL MCMC still trails matched AL.",
      "Run after fixed or near-AL sensitivity identifies whether gamma is the source of performance loss.",
      "Run only if gamma shrinkage does not recover performance sufficiently.",
      "Run only if exAL remains a priority after stronger shrinkage.",
      "Already available from Phase133B; do not relaunch unless table policy changes."
    ),
    phase139_decision_status = decision_status,
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase139_decision_summary <- function(health, vs136, exal_vs_al, sampler) {
  hard_fail <- any(health$status == "fail")
  manifest_review <- any(health$check == "Manifest verification" & health$status == "review")
  all_contract_clean <- any(health$check == "Contract qhat crossings" & health$status == "pass")
  all_worker_clean <- any(health$check == "Worker failures" & health$status == "pass")
  forecast_improved_n <- sum(vs136$forecast_improved, na.rm = TRUE)
  gamma_ess_improved_n <- sum(vs136$gamma_ess_improved, na.rm = TRUE)
  exal_improved_vb_n <- sum(exal_vs_al$improves_over_phase135_exal_vb_forecast, na.rm = TRUE)
  exal_matches_al_n <- sum(exal_vs_al$matches_or_beats_matched_al_forecast, na.rm = TRUE)
  sampler_review_n <- sum(sampler$sampler_gate == "review", na.rm = TRUE)
  decision <- if (hard_fail) {
    "blocked_fix_phase138_artifact_or_outputs"
  } else if (exal_matches_al_n == nrow(exal_vs_al) && sampler_review_n == 0L) {
    "pass_article_candidate_exal_supported"
  } else {
    "review_do_not_promote_exal_as_article_winner"
  }
  data.frame(
    phase139_decision = decision,
    article_promotion_gate = if (identical(decision, "pass_article_candidate_exal_supported")) "pass" else if (hard_fail) "fail" else "review",
    phase138_cases = nrow(exal_vs_al),
    phase138_forecast_improved_vs_phase136_cases = forecast_improved_n,
    phase138_gamma_ess_improved_vs_phase136_cases = gamma_ess_improved_n,
    phase138_improves_over_phase135_exal_vb_forecast_cases = exal_improved_vb_n,
    phase138_matches_or_beats_matched_al_forecast_cases = exal_matches_al_n,
    sampler_review_cases = sampler_review_n,
    implementation_status = if (hard_fail) "fail" else if (all_contract_clean && all_worker_clean) "pass" else "review",
    manifest_status = if (manifest_review) "review_figure_path_repairs_recorded" else "pass",
    primary_article_anchor = "Joint QDESN RHS under AL remains the stronger article-facing anchor.",
    exal_article_role = if (hard_fail) {
      "blocked until artifact failures are fixed"
    } else {
      "extension or diagnostic evidence unless targeted model redesign closes the matched-AL performance gap"
    },
    main_takeaway = paste(
      "Phase138 is computationally complete and noncrossing, and longer chains improve gamma ESS in all selected cases.",
      "However, forecast MAE does not materially improve versus Phase136 and the exAL MCMC rows remain worse than their matched AL counterparts.",
      "This points away from another brute-force longer-chain repeat and toward targeted exAL gamma/model redesign."
    ),
    recommended_next_stage = "Freeze Phase139 as the completed long-chain synthesis; if exAL remains a priority, run a small model-redesign experiment with gamma fixed/near-AL or stronger gamma shrinkage before any article promotion.",
    article_tables_modified = FALSE,
    mcmc_launched_in_phase139 = FALSE,
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase139_readme <- function(decision, health, vs136, exal_vs_al) {
  c(
    "# Joint exQDESN Phase139 Long-Chain Synthesis",
    "",
    "This directory audits the completed Phase138 selected long-chain confirmation against Phase135 matched exAL/AL VB evidence and the Phase136 gamma-kernel packet.",
    "No MCMC jobs are launched by Phase139 and no article tables are modified.",
    "",
    sprintf("- Decision: `%s`", decision$phase139_decision[[1L]]),
    sprintf("- Article promotion gate: `%s`", decision$article_promotion_gate[[1L]]),
    sprintf("- Phase138 cases audited: `%s`", decision$phase138_cases[[1L]]),
    sprintf("- Forecast improvements versus Phase136: `%s`", decision$phase138_forecast_improved_vs_phase136_cases[[1L]]),
    sprintf("- Gamma ESS improvements versus Phase136: `%s`", decision$phase138_gamma_ess_improved_vs_phase136_cases[[1L]]),
    sprintf("- Matches or beats matched AL forecast: `%s`", decision$phase138_matches_or_beats_matched_al_forecast_cases[[1L]]),
    "",
    "Health summary:",
    paste(capture.output(print(health[, c("check", "status", "observed")], row.names = FALSE)), collapse = "\n"),
    "",
    "Phase138 versus Phase136 forecast deltas:",
    paste(capture.output(print(vs136[, c("scenario_id", "source_model_id", "gamma_update", "delta_forecast_mae_phase138_minus_phase136")], row.names = FALSE)), collapse = "\n"),
    "",
    "Phase138 exAL MCMC versus matched AL forecast deltas:",
    paste(capture.output(print(exal_vs_al[, c("scenario_id", "source_model_id", "phase138_mcmc_minus_matched_al_forecast_mae", "interpretation")], row.names = FALSE)), collapse = "\n"),
    "",
    "Interpretation: the implementation is clean enough to study, but the current exAL MCMC evidence should not be promoted as an article winner.",
    "The next useful work is targeted gamma/model redesign, not another brute-force longer-chain repeat of the same specifications."
  )
}

app_joint_exqdesn_run_phase139_long_chain_synthesis <- function(
  out_dir = app_joint_exqdesn_phase139_default_dir(),
  phase135_screening_dir = app_joint_exqdesn_phase139_default_phase135_screening_dir(),
  phase135_audit_dir = app_joint_exqdesn_phase139_default_phase135_audit_dir(),
  phase136_dir = app_joint_exqdesn_phase139_default_phase136_dir(),
  phase137_dir = app_joint_exqdesn_phase139_default_phase137_dir(),
  phase138_dirs = app_joint_exqdesn_phase139_default_phase138_dirs(),
  phase138_orchestration_dir = app_joint_exqdesn_phase139_default_phase138_orchestration_dir()
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  sources <- app_joint_exqdesn_phase139_load_sources(
    phase135_screening_dir = phase135_screening_dir,
    phase135_audit_dir = phase135_audit_dir,
    phase136_dir = phase136_dir,
    phase137_dir = phase137_dir,
    phase138_dirs = phase138_dirs,
    phase138_orchestration_dir = phase138_orchestration_dir
  )
  phase138_assessment <- app_joint_exqdesn_phase139_combined_phase138_assessment(sources)
  manifest_audit <- app_joint_exqdesn_phase139_source_manifest_audit(sources)
  health <- app_joint_exqdesn_phase139_health_summary(sources, phase138_assessment, manifest_audit)
  vs136 <- app_joint_exqdesn_phase139_phase138_vs_phase136(sources, phase138_assessment)
  exal_vs_al <- app_joint_exqdesn_phase139_exal_vs_matched_al(sources, phase138_assessment)
  sampler <- app_joint_exqdesn_phase139_sampler_diagnostic_summary(sources, phase138_assessment)
  decision <- app_joint_exqdesn_phase139_decision_summary(health, vs136, exal_vs_al, sampler)
  redesign <- app_joint_exqdesn_phase139_next_model_redesign_plan(decision$phase139_decision[[1L]])

  run_config <- data.frame(
    run_id = "joint_qdesn_phase139_exal_long_chain_synthesis",
    out_dir = out_dir,
    phase135_screening_dir = normalizePath(phase135_screening_dir, mustWork = FALSE),
    phase135_audit_dir = normalizePath(phase135_audit_dir, mustWork = FALSE),
    phase136_dir = normalizePath(phase136_dir, mustWork = FALSE),
    phase137_dir = normalizePath(phase137_dir, mustWork = FALSE),
    phase138_orchestration_dir = normalizePath(phase138_orchestration_dir, mustWork = FALSE),
    phase138_dirs = paste(vapply(phase138_dirs, normalizePath, character(1L), mustWork = FALSE), collapse = "|"),
    mcmc_launched = FALSE,
    article_tables_modified = FALSE,
    validation_contract = "quantile_grid_fit_and_forecast_scoring_with_raw_contract_qhat",
    scalar_predictive_density_claim = FALSE,
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_exqdesn_phase139_readme(decision, health, vs136, exal_vs_al), readme_path, useBytes = TRUE)

  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    phase139_source_manifest_audit = app_joint_qvp_write_csv(manifest_audit, file.path(out_dir, "phase139_source_manifest_audit.csv")),
    phase139_health_summary = app_joint_qvp_write_csv(health, file.path(out_dir, "phase139_health_summary.csv")),
    phase139_phase138_case_summary = app_joint_qvp_write_csv(phase138_assessment, file.path(out_dir, "phase139_phase138_case_summary.csv")),
    phase139_phase138_vs_phase136 = app_joint_qvp_write_csv(vs136, file.path(out_dir, "phase139_phase138_vs_phase136.csv")),
    phase139_exal_vs_matched_al = app_joint_qvp_write_csv(exal_vs_al, file.path(out_dir, "phase139_exal_vs_matched_al.csv")),
    phase139_sampler_diagnostic_summary = app_joint_qvp_write_csv(sampler, file.path(out_dir, "phase139_sampler_diagnostic_summary.csv")),
    phase139_next_model_redesign_plan = app_joint_qvp_write_csv(redesign, file.path(out_dir, "phase139_next_model_redesign_plan.csv")),
    phase139_decision_summary = app_joint_qvp_write_csv(decision, file.path(out_dir, "phase139_decision_summary.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    paths = c(paths, artifact_manifest = manifest_info$manifest_path),
    manifest = manifest_info$manifest,
    run_config = run_config,
    manifest_audit = manifest_audit,
    health = health,
    phase138_assessment = phase138_assessment,
    vs136 = vs136,
    exal_vs_al = exal_vs_al,
    sampler = sampler,
    redesign = redesign,
    decision = decision
  )
}
