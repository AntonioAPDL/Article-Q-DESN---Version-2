# Phase137 post-Phase136 gamma-kernel readiness and launch planning.

app_joint_exqdesn_phase137_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase137_exal_gamma_kernel_readiness_20260716")
}

app_joint_exqdesn_phase137_default_phase136_dir <- function() {
  app_path("application/cache/joint_qdesn_phase136_exal_gamma_kernel_packet_20260715")
}

app_joint_exqdesn_phase137_required_phase136_files <- function() {
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

app_joint_exqdesn_phase137_mean_finite <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  mean(x)
}

app_joint_exqdesn_phase137_min_finite <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  min(x)
}

app_joint_exqdesn_phase137_max_finite <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  max(x)
}

app_joint_exqdesn_phase137_read_exit_code <- function(phase136_dir) {
  exit_path <- paste0(normalizePath(phase136_dir, mustWork = FALSE), ".exit")
  if (!file.exists(exit_path)) return(NA_integer_)
  out <- suppressWarnings(as.integer(trimws(readLines(exit_path, warn = FALSE)[1L])))
  if (is.na(out)) NA_integer_ else out
}

app_joint_exqdesn_phase137_verify_manifest_with_repairs <- function(dir, artifact_label = "phase136") {
  dir <- normalizePath(dir, mustWork = TRUE)
  manifest_path <- file.path(dir, "artifact_manifest.csv")
  if (!file.exists(manifest_path)) {
    return(data.frame(
      artifact_label = artifact_label,
      label = "artifact_manifest",
      relative_path = "artifact_manifest.csv",
      strict_path = normalizePath(manifest_path, mustWork = FALSE),
      strict_exists = FALSE,
      strict_status = "fail",
      repaired_relative_path = NA_character_,
      repaired_path = NA_character_,
      repaired_exists = FALSE,
      declared_size_bytes = NA_real_,
      actual_size_bytes = NA_real_,
      declared_sha256 = NA_character_,
      actual_sha256 = NA_character_,
      repair_action = "missing_manifest",
      status = "fail",
      stringsAsFactors = FALSE
    ))
  }
  manifest <- app_read_csv(manifest_path)
  app_check_required_columns(manifest, c("label", "relative_path", "size_bytes", "sha256"), artifact_label)
  app_joint_qdesn_bind_rows(lapply(seq_len(nrow(manifest)), function(ii) {
    rel <- as.character(manifest$relative_path[[ii]])
    strict_path <- file.path(dir, rel)
    strict_exists <- file.exists(strict_path)
    strict_sha <- if (strict_exists) app_sha256_file(strict_path) else NA_character_
    strict_size <- if (strict_exists) as.numeric(file.info(strict_path)$size) else NA_real_
    declared_sha <- as.character(manifest$sha256[[ii]])
    declared_size <- as.numeric(manifest$size_bytes[[ii]])
    strict_pass <- strict_exists &&
      identical(tolower(strict_sha), tolower(declared_sha)) &&
      identical(as.numeric(strict_size), declared_size)

    repaired_rel <- NA_character_
    repaired_path <- NA_character_
    repaired_exists <- FALSE
    repaired_sha <- NA_character_
    repaired_size <- NA_real_
    repair_action <- "none"
    repaired_pass <- FALSE
    if (!strict_pass) {
      candidate_rel <- file.path("figures", basename(rel))
      candidate_path <- file.path(dir, candidate_rel)
      repaired_exists <- file.exists(candidate_path)
      if (repaired_exists) {
        repaired_sha <- app_sha256_file(candidate_path)
        repaired_size <- as.numeric(file.info(candidate_path)$size)
        repaired_pass <- identical(tolower(repaired_sha), tolower(declared_sha)) &&
          identical(as.numeric(repaired_size), declared_size)
        repaired_rel <- candidate_rel
        repaired_path <- normalizePath(candidate_path, mustWork = FALSE)
        repair_action <- if (repaired_pass) "figures_subdir_path_repair" else "figures_subdir_hash_or_size_mismatch"
      } else {
        repair_action <- "no_repair_candidate"
      }
    }

    data.frame(
      artifact_label = artifact_label,
      label = as.character(manifest$label[[ii]]),
      relative_path = rel,
      strict_path = normalizePath(strict_path, mustWork = FALSE),
      strict_exists = strict_exists,
      strict_status = if (strict_pass) "pass" else "fail",
      repaired_relative_path = repaired_rel,
      repaired_path = repaired_path,
      repaired_exists = repaired_exists,
      declared_size_bytes = declared_size,
      actual_size_bytes = if (strict_pass) strict_size else if (repaired_pass) repaired_size else strict_size,
      declared_sha256 = declared_sha,
      actual_sha256 = if (strict_pass) strict_sha else if (repaired_pass) repaired_sha else strict_sha,
      repair_action = repair_action,
      status = if (strict_pass || repaired_pass) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase137_load_phase136 <- function(phase136_dir) {
  phase136_dir <- normalizePath(phase136_dir, mustWork = TRUE)
  required <- app_joint_exqdesn_phase137_required_phase136_files()
  missing <- required[!file.exists(file.path(phase136_dir, required))]
  if (length(missing)) {
    stop(sprintf("Phase136 artifact is missing required files: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  run_config <- app_read_csv(file.path(phase136_dir, "run_config.csv"))
  phase135_audit_dir <- if ("phase135_audit_dir" %in% names(run_config)) {
    as.character(run_config$phase135_audit_dir[[1L]])
  } else {
    NA_character_
  }
  phase135_comparison_path <- file.path(phase135_audit_dir, "phase135_matched_exal_vs_source_al_vb_comparison.csv")
  phase135_comparison <- if (!is.na(phase135_audit_dir) && file.exists(phase135_comparison_path)) {
    app_read_csv(phase135_comparison_path)
  } else {
    data.frame()
  }
  list(
    dir = phase136_dir,
    exit_code = app_joint_exqdesn_phase137_read_exit_code(phase136_dir),
    run_config = run_config,
    strict_manifest = app_joint_qdesn_phase108_manifest_verify(phase136_dir, "phase136_strict"),
    repaired_manifest = app_joint_exqdesn_phase137_verify_manifest_with_repairs(phase136_dir, "phase136_repaired"),
    selected_cases = app_read_csv(file.path(phase136_dir, "phase136_selected_cases.csv")),
    variant_registry = app_read_csv(file.path(phase136_dir, "phase136_variant_registry.csv")),
    chain_jobs = app_read_csv(file.path(phase136_dir, "phase136_chain_jobs.csv")),
    prep_failures = app_read_csv(file.path(phase136_dir, "phase136_case_variant_prep_failures.csv")),
    chain_failures = app_read_csv(file.path(phase136_dir, "phase136_chain_worker_failures.csv")),
    mcmc_summary = app_read_csv(file.path(phase136_dir, "phase136_mcmc_case_summary.csv")),
    assessment = app_read_csv(file.path(phase136_dir, "phase136_case_assessment.csv")),
    best_by_case = app_read_csv(file.path(phase136_dir, "phase136_best_variant_by_case.csv")),
    runtime = app_read_csv(file.path(phase136_dir, "runtime_summary.csv")),
    rhat = app_read_csv(file.path(phase136_dir, "mcmc_rhat_ess_summary.csv")),
    autocorrelation = app_read_csv(file.path(phase136_dir, "autocorrelation_summary.csv")),
    phase135_comparison = phase135_comparison
  )
}

app_joint_exqdesn_phase137_health_summary <- function(phase136) {
  a <- phase136$assessment
  strict <- phase136$strict_manifest
  repaired <- phase136$repaired_manifest
  chain_jobs <- phase136$chain_jobs
  prep_failures <- phase136$prep_failures
  chain_failures <- phase136$chain_failures
  raw_crossings <- sum(a$mcmc_fit_raw_crossing_pairs, a$mcmc_forecast_raw_crossing_pairs, na.rm = TRUE)
  contract_crossings <- sum(a$mcmc_fit_contract_crossing_pairs, a$mcmc_forecast_contract_crossing_pairs, na.rm = TRUE)
  gate_counts <- table(a$phase136_gate_status)
  gamma_review_rows <- sum(grepl("gamma lag-1 autocorrelation", a$status_reason, fixed = TRUE), na.rm = TRUE)
  rhat_review_rows <- sum(is.finite(a$max_rhat) & a$max_rhat > 1.2, na.rm = TRUE)
  rows <- list(
    data.frame(
      check = "Phase136 process exit",
      status = if (identical(as.integer(phase136$exit_code), 0L)) "pass" else "fail",
      observed = as.character(phase136$exit_code),
      implication = "The completed packet can be audited.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Strict artifact manifest",
      status = if (all(strict$status == "pass")) "pass" else "review",
      observed = sprintf("%s/%s pass", sum(strict$status == "pass"), nrow(strict)),
      implication = "Strict failures are reviewed before any downstream launch.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Path-repaired artifact manifest",
      status = if (all(repaired$status == "pass")) "pass" else "fail",
      observed = sprintf("%s/%s pass", sum(repaired$status == "pass"), nrow(repaired)),
      implication = "Repairs are limited to figure files stored under figures/.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Case and variant completion",
      status = if (nrow(a) == nrow(phase136$variant_registry)) "pass" else "fail",
      observed = sprintf("%s cases, %s case-variants", length(unique(a$case_id)), nrow(a)),
      implication = "All planned case-variants are available for selection.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "MCMC chain jobs",
      status = if (nrow(chain_failures) == 0L && nrow(chain_jobs) > 0L) "pass" else "fail",
      observed = sprintf("%s planned, %s worker failures", nrow(chain_jobs), nrow(chain_failures)),
      implication = "No chain-level rerun is needed before readiness planning.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Preparation workers",
      status = if (nrow(prep_failures) == 0L) "pass" else "fail",
      observed = sprintf("%s worker failures", nrow(prep_failures)),
      implication = "VB initialization/preparation completed for all case-variants.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Quantile contract crossings",
      status = if (contract_crossings == 0L) "pass" else "fail",
      observed = sprintf("%s contract crossing pairs", contract_crossings),
      implication = "Scored qhat grids are noncrossing.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Raw qhat crossings",
      status = if (raw_crossings == 0L) "pass" else "review",
      observed = sprintf("%s raw crossing pairs", raw_crossings),
      implication = "No raw monotone repair burden was observed in Phase136.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Phase136 gates",
      status = if (all(a$phase136_gate_status == "pass")) "pass" else if (any(a$phase136_gate_status == "fail")) "fail" else "review",
      observed = paste(sprintf("%s=%s", names(gate_counts), as.integer(gate_counts)), collapse = ", "),
      implication = "Review status prevents article promotion but allows targeted follow-up.",
      stringsAsFactors = FALSE
    ),
    data.frame(
      check = "Gamma diagnostics",
      status = if (gamma_review_rows == 0L && rhat_review_rows == 0L) "pass" else "review",
      observed = sprintf("%s gamma-autocorrelation review rows, %s Rhat review rows", gamma_review_rows, rhat_review_rows),
      implication = "Longer selected-chain confirmation is justified before broader MCMC.",
      stringsAsFactors = FALSE
    )
  )
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase137_variant_summary <- function(phase136) {
  a <- phase136$assessment
  runtime <- phase136$runtime
  rhat <- phase136$rhat
  ac <- phase136$autocorrelation
  best <- phase136$best_by_case
  variants <- sort(unique(a$phase136_variant_id))
  app_joint_qdesn_bind_rows(lapply(variants, function(variant) {
    block <- a[a$phase136_variant_id == variant, , drop = FALSE]
    rt <- runtime[runtime$phase136_variant_id == variant & runtime$runtime_component == "mcmc_chain", , drop = FALSE]
    rh <- rhat[rhat$phase136_variant_id == variant & rhat$parameter == "gamma", , drop = FALSE]
    ac1 <- ac[ac$variant_id == variant & ac$parameter == "gamma" & ac$lag == 1L, , drop = FALSE]
    data.frame(
      phase136_variant_id = variant,
      gamma_update = paste(unique(block$gamma_update), collapse = "|"),
      n_case_variants = nrow(block),
      n_selected_best = sum(best$phase136_variant_id == variant),
      mean_fit_truth_mae = app_joint_exqdesn_phase137_mean_finite(block$mcmc_fit_truth_mae),
      mean_forecast_truth_mae = app_joint_exqdesn_phase137_mean_finite(block$mcmc_forecast_truth_mae),
      median_forecast_truth_mae = stats::median(block$mcmc_forecast_truth_mae, na.rm = TRUE),
      mean_forecast_check_loss = app_joint_exqdesn_phase137_mean_finite(block$mcmc_forecast_check_loss_mean),
      total_raw_crossing_pairs = sum(block$mcmc_fit_raw_crossing_pairs, block$mcmc_forecast_raw_crossing_pairs, na.rm = TRUE),
      total_contract_crossing_pairs = sum(block$mcmc_fit_contract_crossing_pairs, block$mcmc_forecast_contract_crossing_pairs, na.rm = TRUE),
      mean_max_rhat = app_joint_exqdesn_phase137_mean_finite(block$max_rhat),
      max_rhat = app_joint_exqdesn_phase137_max_finite(block$max_rhat),
      mean_max_gamma_rhat = app_joint_exqdesn_phase137_mean_finite(block$max_gamma_rhat),
      max_gamma_rhat = app_joint_exqdesn_phase137_max_finite(block$max_gamma_rhat),
      min_gamma_rough_ess_total = app_joint_exqdesn_phase137_min_finite(block$min_gamma_rough_ess_total),
      median_gamma_rhat = stats::median(rh$rhat, na.rm = TRUE),
      median_gamma_rough_ess_total = stats::median(rh$rough_ess_total, na.rm = TRUE),
      mean_gamma_lag1_autocorrelation = app_joint_exqdesn_phase137_mean_finite(ac1$autocorrelation),
      mean_chain_hours = app_joint_exqdesn_phase137_mean_finite(rt$elapsed_seconds) / 3600,
      median_chain_hours = stats::median(rt$elapsed_seconds, na.rm = TRUE) / 3600,
      max_chain_hours = app_joint_exqdesn_phase137_max_finite(rt$elapsed_seconds) / 3600,
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase137_case_delta_summary <- function(phase136) {
  a <- phase136$assessment
  app_joint_qdesn_bind_rows(lapply(split(a, a$case_id), function(block) {
    bounded <- block[block$phase136_variant_id == "bounded_w4", , drop = FALSE]
    logit <- block[block$phase136_variant_id == "logit_w4", , drop = FALSE]
    selected <- phase136$best_by_case[phase136$best_by_case$case_id == block$case_id[[1L]], , drop = FALSE]
    if (!nrow(bounded) || !nrow(logit)) return(data.frame())
    data.frame(
      case_id = block$case_id[[1L]],
      scenario_id = block$scenario_id[[1L]],
      source_model_id = block$source_model_id[[1L]],
      selected_phase136_variant_id = selected$phase136_variant_id[[1L]],
      selected_gamma_update = selected$gamma_update[[1L]],
      bounded_forecast_truth_mae = bounded$mcmc_forecast_truth_mae[[1L]],
      logit_forecast_truth_mae = logit$mcmc_forecast_truth_mae[[1L]],
      forecast_delta_logit_minus_bounded = logit$mcmc_forecast_truth_mae[[1L]] - bounded$mcmc_forecast_truth_mae[[1L]],
      bounded_fit_truth_mae = bounded$mcmc_fit_truth_mae[[1L]],
      logit_fit_truth_mae = logit$mcmc_fit_truth_mae[[1L]],
      fit_delta_logit_minus_bounded = logit$mcmc_fit_truth_mae[[1L]] - bounded$mcmc_fit_truth_mae[[1L]],
      bounded_max_gamma_rhat = bounded$max_gamma_rhat[[1L]],
      logit_max_gamma_rhat = logit$max_gamma_rhat[[1L]],
      gamma_rhat_delta_logit_minus_bounded = logit$max_gamma_rhat[[1L]] - bounded$max_gamma_rhat[[1L]],
      bounded_min_gamma_rough_ess_total = bounded$min_gamma_rough_ess_total[[1L]],
      logit_min_gamma_rough_ess_total = logit$min_gamma_rough_ess_total[[1L]],
      gamma_ess_delta_logit_minus_bounded = logit$min_gamma_rough_ess_total[[1L]] - bounded$min_gamma_rough_ess_total[[1L]],
      interpretation = if (logit$mcmc_forecast_truth_mae[[1L]] < bounded$mcmc_forecast_truth_mae[[1L]]) {
        "logit improves forecast score in this case"
      } else {
        "bounded remains better on forecast score in this case"
      },
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase137_phase135_comparison <- function(phase136) {
  best <- phase136$best_by_case
  comp <- phase136$phase135_comparison
  if (!nrow(comp)) return(data.frame())
  app_joint_qdesn_bind_rows(lapply(seq_len(nrow(best)), function(ii) {
    row <- best[ii, , drop = FALSE]
    target <- row$source_model_id[[1L]]
    matched <- comp[comp$scenario_id == row$scenario_id[[1L]] & comp$target_exal_model_id == target, , drop = FALSE]
    if (!nrow(matched)) return(data.frame())
    matched <- matched[1L, , drop = FALSE]
    data.frame(
      case_id = row$case_id[[1L]],
      scenario_id = row$scenario_id[[1L]],
      source_model_id = row$source_model_id[[1L]],
      selected_phase136_variant_id = row$phase136_variant_id[[1L]],
      selected_gamma_update = row$gamma_update[[1L]],
      phase135_matched_exal_fit_mae = matched$exal_fit_mae[[1L]],
      phase135_matched_exal_forecast_mae = matched$exal_forecast_mae[[1L]],
      matched_al_fit_mae = matched$al_fit_mae[[1L]],
      matched_al_forecast_mae = matched$al_forecast_mae[[1L]],
      phase136_selected_mcmc_fit_mae = row$mcmc_fit_truth_mae[[1L]],
      phase136_selected_mcmc_forecast_mae = row$mcmc_forecast_truth_mae[[1L]],
      phase136_mcmc_minus_phase135_exal_vb_fit_mae = row$mcmc_fit_truth_mae[[1L]] - matched$exal_fit_mae[[1L]],
      phase136_mcmc_minus_phase135_exal_vb_forecast_mae = row$mcmc_forecast_truth_mae[[1L]] - matched$exal_forecast_mae[[1L]],
      phase136_mcmc_minus_matched_al_fit_mae = row$mcmc_fit_truth_mae[[1L]] - matched$al_fit_mae[[1L]],
      phase136_mcmc_minus_matched_al_forecast_mae = row$mcmc_forecast_truth_mae[[1L]] - matched$al_forecast_mae[[1L]],
      closes_vb_exal_forecast_gap = row$mcmc_forecast_truth_mae[[1L]] < matched$exal_forecast_mae[[1L]],
      matches_or_beats_al_forecast = row$mcmc_forecast_truth_mae[[1L]] <= matched$al_forecast_mae[[1L]],
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase137_selected_registry <- function(phase136, next_n_iter = 16000L,
                                                        next_burn = 4000L, next_thin = 1L,
                                                        next_seed_offset = 8600L) {
  best <- phase136$best_by_case
  best$phase137_selection_status <- "selected_for_long_chain_confirmation"
  best$phase137_article_status <- "not_article_ready"
  best$phase137_selection_basis <- "lowest Phase136 forecast MAE within case, with zero contract crossings and no worker failures"
  best$phase137_next_mcmc_n_iter <- as.integer(next_n_iter)
  best$phase137_next_mcmc_burn <- as.integer(next_burn)
  best$phase137_next_mcmc_thin <- as.integer(next_thin)
  best$phase137_next_mcmc_seed_offset <- as.integer(next_seed_offset)
  best$phase137_launch_group_id <- paste0("selected_", best$phase136_variant_id)
  best[order(best$phase137_launch_group_id, best$case_id), , drop = FALSE]
}

app_joint_exqdesn_phase137_build_command <- function(output_dir, case_ids, variant_id,
                                                     phase136, n_chains, mcmc_n_iter,
                                                     mcmc_burn, mcmc_thin, seed_offset,
                                                     n_cores, vb_n_cores) {
  rc <- phase136$run_config
  paste(
    "Rscript application/scripts/145_run_joint_exqdesn_phase136_gamma_kernel_packet.R",
    sprintf("--output-dir %s", shQuote(output_dir)),
    sprintf("--phase135-screening-dir %s", shQuote(rc$phase135_screening_dir[[1L]])),
    sprintf("--phase135-audit-dir %s", shQuote(rc$phase135_audit_dir[[1L]])),
    sprintf("--fixture-dir %s", shQuote(rc$fixture_dir[[1L]])),
    sprintf("--case-ids %s", shQuote(paste(case_ids, collapse = ","))),
    sprintf("--variant-ids %s", shQuote(variant_id)),
    sprintf("--bounded-width-multiplier %s", rc$bounded_width_multiplier[[1L]]),
    sprintf("--logit-eta-width %s", rc$logit_eta_width[[1L]]),
    sprintf("--gamma-slice-max-steps %s", rc$gamma_slice_max_steps[[1L]]),
    sprintf("--n-chains %s", as.integer(n_chains)),
    sprintf("--mcmc-n-iter %s", as.integer(mcmc_n_iter)),
    sprintf("--mcmc-burn %s", as.integer(mcmc_burn)),
    sprintf("--mcmc-thin %s", as.integer(mcmc_thin)),
    sprintf("--mcmc-seed-offset %s", as.integer(seed_offset)),
    sprintf("--chain-seed-stride %s", rc$chain_seed_stride[[1L]]),
    sprintf("--sigma-upper-multiplier %s", rc$sigma_upper_multiplier[[1L]]),
    sprintf("--distance-pass %s", 5),
    sprintf("--chain-pass %s", 5),
    sprintf("--n-cores %s", as.integer(n_cores)),
    sprintf("--vb-n-cores %s", as.integer(vb_n_cores)),
    sprintf("--gamma-init-mode %s", shQuote(rc$gamma_init_mode[[1L]])),
    sprintf("--gamma-jitter-fraction %s", rc$gamma_jitter_fraction[[1L]]),
    sprintf("--trace-write-stride %s", rc$trace_write_stride[[1L]]),
    "--save-rdata false",
    "--dry-run false",
    sep = " \\\n  "
  )
}

app_joint_exqdesn_phase137_launch_plan <- function(phase136, selected_registry,
                                                   launch_root = "application/cache",
                                                   next_phase_id = "phase138",
                                                   n_chains = 8L,
                                                   mcmc_n_iter = 16000L,
                                                   mcmc_burn = 4000L,
                                                   mcmc_thin = 1L,
                                                   seed_offset = 8600L) {
  groups <- split(selected_registry, selected_registry$phase136_variant_id)
  app_joint_qdesn_bind_rows(lapply(names(groups), function(variant) {
    block <- groups[[variant]]
    total_jobs <- nrow(block) * as.integer(n_chains)
    n_cores <- min(total_jobs, 32L)
    vb_n_cores <- min(nrow(block), 5L)
    suffix <- gsub("[^A-Za-z0-9]+", "_", variant)
    out_dir <- file.path(launch_root, sprintf("joint_qdesn_%s_exal_selected_long_chain_confirmation_20260716_%s", next_phase_id, suffix))
    data.frame(
      launch_group_id = paste0("selected_", variant),
      next_phase_id = next_phase_id,
      phase136_variant_id = variant,
      gamma_update = paste(unique(block$gamma_update), collapse = "|"),
      n_cases = nrow(block),
      case_ids = paste(block$case_id, collapse = ","),
      scenario_ids = paste(block$scenario_id, collapse = ","),
      n_chains = as.integer(n_chains),
      total_chain_jobs = total_jobs,
      mcmc_n_iter = as.integer(mcmc_n_iter),
      mcmc_burn = as.integer(mcmc_burn),
      mcmc_thin = as.integer(mcmc_thin),
      mcmc_seed_offset = as.integer(seed_offset),
      n_cores = as.integer(n_cores),
      vb_n_cores = as.integer(vb_n_cores),
      output_dir = out_dir,
      launched_in_phase137 = FALSE,
      execution_mode = "review_then_launch_selected_kernel_packet",
      rationale = "Rerun only the Phase136 winning gamma kernel for each case with twice the chain length; do not rerun losing kernels.",
      command = app_joint_exqdesn_phase137_build_command(
        output_dir = out_dir,
        case_ids = block$case_id,
        variant_id = variant,
        phase136 = phase136,
        n_chains = n_chains,
        mcmc_n_iter = mcmc_n_iter,
        mcmc_burn = mcmc_burn,
        mcmc_thin = mcmc_thin,
        seed_offset = seed_offset,
        n_cores = n_cores,
        vb_n_cores = vb_n_cores
      ),
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase137_decision_summary <- function(health, variant_summary, comparison, selected_registry) {
  hard_fail <- any(health$status == "fail")
  all_repaired_pass <- any(health$check == "Path-repaired artifact manifest" & health$status == "pass")
  all_contract_clean <- any(health$check == "Quantile contract crossings" & health$status == "pass")
  selected_n <- nrow(selected_registry)
  exal_improved_count <- if (nrow(comparison)) sum(comparison$closes_vb_exal_forecast_gap, na.rm = TRUE) else NA_integer_
  al_match_count <- if (nrow(comparison)) sum(comparison$matches_or_beats_al_forecast, na.rm = TRUE) else NA_integer_
  data.frame(
    phase137_decision = if (hard_fail) "blocked_fix_phase136_artifact_or_outputs" else "review_ready_for_selected_long_chain_confirmation",
    article_promotion_gate = "review",
    mcmc_launched_in_phase137 = FALSE,
    selected_case_kernel_pairs = selected_n,
    bounded_selected_cases = sum(selected_registry$phase136_variant_id == "bounded_w4"),
    logit_selected_cases = sum(selected_registry$phase136_variant_id == "logit_w4"),
    phase136_manifest_strict_status = if (any(health$check == "Strict artifact manifest")) health$status[health$check == "Strict artifact manifest"][[1L]] else NA_character_,
    phase136_manifest_repaired_status = if (all_repaired_pass) "pass" else "fail",
    contract_crossing_status = if (all_contract_clean) "pass" else "fail",
    phase136_cases_closing_exal_vb_forecast_gap = exal_improved_count,
    phase136_cases_matching_or_beating_matched_al_forecast = al_match_count,
    main_takeaway = paste(
      "Phase136 improves the matched exAL MCMC approximation in several high-priority cases and removes crossing concerns,",
      "but gamma autocorrelation/Rhat diagnostics remain review-level and the selected exAL MCMC rows still do not match the corresponding AL forecast MAE."
    ),
    recommended_next_stage = "Launch Phase138 selected long-chain confirmation after review; do not promote article tables yet.",
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase137_readme <- function(decision, health, launch_plan) {
  c(
    "# Joint exQDESN Phase137 Gamma-Kernel Readiness",
    "",
    "This directory audits the completed Phase136 gamma-kernel MCMC packet and prepares the next selected long-chain launch.",
    "No MCMC jobs are launched by Phase137.",
    "",
    sprintf("- Decision: `%s`", decision$phase137_decision[[1L]]),
    sprintf("- Article promotion gate: `%s`", decision$article_promotion_gate[[1L]]),
    sprintf("- Selected case-kernel pairs: `%s`", decision$selected_case_kernel_pairs[[1L]]),
    sprintf("- Launch groups prepared: `%s`", nrow(launch_plan)),
    "",
    "The key interpretation is performance-first but conservative: Phase136 identifies case-specific gamma kernels worth confirming,",
    "yet the evidence is still review-ready rather than article-ready because gamma autocorrelation/Rhat diagnostics remain nontrivial",
    "and matched AL rows remain stronger on forecast MAE.",
    "",
    "The strict Phase136 manifest has known figure-path failures caused by figure basenames being recorded while PDFs were written under `figures/`.",
    "This packet preserves that strict failure and writes a repaired-path verification table instead of mutating the Phase136 artifact.",
    "",
    "Health summary:",
    paste(capture.output(print(health[, c("check", "status", "observed")], row.names = FALSE)), collapse = "\n"),
    "",
    "Review `phase137_launch_commands.txt` before launching Phase138."
  )
}

app_joint_exqdesn_run_phase137_gamma_kernel_readiness <- function(
  out_dir = app_joint_exqdesn_phase137_default_dir(),
  phase136_dir = app_joint_exqdesn_phase137_default_phase136_dir(),
  next_n_chains = 8L,
  next_mcmc_n_iter = 16000L,
  next_mcmc_burn = 4000L,
  next_mcmc_thin = 1L,
  next_mcmc_seed_offset = 8600L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  phase136 <- app_joint_exqdesn_phase137_load_phase136(phase136_dir)
  health <- app_joint_exqdesn_phase137_health_summary(phase136)
  variant_summary <- app_joint_exqdesn_phase137_variant_summary(phase136)
  case_delta <- app_joint_exqdesn_phase137_case_delta_summary(phase136)
  comparison <- app_joint_exqdesn_phase137_phase135_comparison(phase136)
  selected_registry <- app_joint_exqdesn_phase137_selected_registry(
    phase136,
    next_n_iter = next_mcmc_n_iter,
    next_burn = next_mcmc_burn,
    next_thin = next_mcmc_thin,
    next_seed_offset = next_mcmc_seed_offset
  )
  launch_plan <- app_joint_exqdesn_phase137_launch_plan(
    phase136,
    selected_registry,
    n_chains = next_n_chains,
    mcmc_n_iter = next_mcmc_n_iter,
    mcmc_burn = next_mcmc_burn,
    mcmc_thin = next_mcmc_thin,
    seed_offset = next_mcmc_seed_offset
  )
  decision <- app_joint_exqdesn_phase137_decision_summary(health, variant_summary, comparison, selected_registry)
  repair_map <- phase136$repaired_manifest[
    phase136$repaired_manifest$strict_status != "pass" &
      phase136$repaired_manifest$status == "pass" &
      phase136$repaired_manifest$repair_action == "figures_subdir_path_repair",
    ,
    drop = FALSE
  ]
  run_config <- data.frame(
    run_id = "joint_qdesn_phase137_exal_gamma_kernel_readiness",
    out_dir = out_dir,
    phase136_dir = phase136$dir,
    phase136_exit_code = phase136$exit_code,
    next_n_chains = as.integer(next_n_chains),
    next_mcmc_n_iter = as.integer(next_mcmc_n_iter),
    next_mcmc_burn = as.integer(next_mcmc_burn),
    next_mcmc_thin = as.integer(next_mcmc_thin),
    next_mcmc_seed_offset = as.integer(next_mcmc_seed_offset),
    mcmc_launched = FALSE,
    article_tables_modified = FALSE,
    validation_contract = "quantile_grid_fit_and_forecast_scoring_with_raw_contract_qhat",
    scalar_predictive_density_claim = FALSE,
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_exqdesn_phase137_readme(decision, health, launch_plan), readme_path, useBytes = TRUE)
  command_path <- file.path(out_dir, "phase137_launch_commands.txt")
  writeLines(c(
    "# Phase138 selected long-chain confirmation commands",
    "# Review resource availability before running. Phase137 did not launch these commands.",
    "",
    paste(launch_plan$command, collapse = "\n\n")
  ), command_path, useBytes = TRUE)

  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    phase136_manifest_strict_verification = app_joint_qvp_write_csv(phase136$strict_manifest, file.path(out_dir, "phase136_manifest_strict_verification.csv")),
    phase136_manifest_repaired_verification = app_joint_qvp_write_csv(phase136$repaired_manifest, file.path(out_dir, "phase136_manifest_repaired_verification.csv")),
    phase136_manifest_repair_map = app_joint_qvp_write_csv(repair_map, file.path(out_dir, "phase136_manifest_repair_map.csv")),
    phase137_health_summary = app_joint_qvp_write_csv(health, file.path(out_dir, "phase137_health_summary.csv")),
    phase137_kernel_variant_summary = app_joint_qvp_write_csv(variant_summary, file.path(out_dir, "phase137_kernel_variant_summary.csv")),
    phase137_case_delta_summary = app_joint_qvp_write_csv(case_delta, file.path(out_dir, "phase137_case_delta_summary.csv")),
    phase137_phase136_vs_phase135_summary = app_joint_qvp_write_csv(comparison, file.path(out_dir, "phase137_phase136_vs_phase135_summary.csv")),
    phase137_selected_case_kernel_registry = app_joint_qvp_write_csv(selected_registry, file.path(out_dir, "phase137_selected_case_kernel_registry.csv")),
    phase137_next_launch_plan = app_joint_qvp_write_csv(launch_plan, file.path(out_dir, "phase137_next_launch_plan.csv")),
    phase137_decision_summary = app_joint_qvp_write_csv(decision, file.path(out_dir, "phase137_decision_summary.csv")),
    phase137_launch_commands = normalizePath(command_path, mustWork = TRUE),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    paths = c(paths, artifact_manifest = manifest_info$manifest_path),
    manifest = manifest_info$manifest,
    run_config = run_config,
    health = health,
    variant_summary = variant_summary,
    case_delta_summary = case_delta,
    comparison = comparison,
    selected_registry = selected_registry,
    launch_plan = launch_plan,
    decision = decision
  )
}
