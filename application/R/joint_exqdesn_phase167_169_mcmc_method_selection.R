# Phase167 structured-VB freeze and Phase169 exact-MCMC method selection.

app_joint_exqdesn_phase167_169_dirs <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root()
) {
  base <- app_joint_exqdesn_phase164_dirs(cache_root)
  c(base, list(
    phase167 = file.path(cache_root, "joint_exqdesn_phase167_vb_method_freeze_20260807"),
    phase169_freeze = file.path(cache_root, "joint_exqdesn_phase169_exact_mcmc_method_selection_freeze_20260807"),
    phase169 = file.path(cache_root, "joint_exqdesn_phase169_exact_mcmc_method_selection_20260807"),
    phase169_orchestration = file.path(cache_root, "joint_exqdesn_phase169_exact_mcmc_method_selection_20260807_orchestration")
  ))
}

app_joint_exqdesn_phase167_source_snapshot <- function() {
  relative_path <- c(
    "application/config/joint_exqdesn_inference_method_registry_v1.csv",
    "application/R/joint_exqdesn_exact_structured_inference.R",
    "application/R/joint_exqdesn_inference_dispatch.R",
    "application/R/joint_exqdesn_phase164_165_readiness.R",
    "application/R/joint_exqdesn_phase166_168_structured_vb.R",
    "application/R/joint_exqdesn_phase167_169_mcmc_method_selection.R",
    "application/scripts/221_prepare_joint_exqdesn_phase167_169_mcmc_method_selection.R",
    "application/scripts/222_run_joint_exqdesn_phase169_chain.R",
    "application/scripts/223_finalize_joint_exqdesn_phase169_mcmc_method_selection.R",
    "application/scripts/224_check_joint_exqdesn_phase169_mcmc_method_selection.R",
    "application/scripts/225_launch_joint_exqdesn_phase169_mcmc_method_selection.sh",
    "application/tests/test_joint_exqdesn_phase167_169_mcmc_method_selection.R"
  )
  paths <- app_path(relative_path)
  if (any(!file.exists(paths))) {
    stop("Phase167/169 source snapshot is incomplete.", call. = FALSE)
  }
  data.frame(
    relative_path = relative_path,
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase167_method_audit <- function(candidate_summary) {
  required <- c(
    "base_scenario_id", "dgp_replicate_id", "fit_structure",
    "inference_method_id", "implementation_status", "gate_status",
    "vb_converged", "fit_truth_mae", "forecast_truth_mae",
    "fit_check_loss_mean", "forecast_check_loss_mean",
    "fit_crps_grid_mean", "forecast_crps_grid_mean",
    "fit_contract_crossing_pairs", "forecast_contract_crossing_pairs",
    "total_elapsed_seconds"
  )
  missing <- setdiff(required, names(candidate_summary))
  if (length(missing)) {
    stop(sprintf("Phase166 candidate summary is missing: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  expected_methods <- c("VB0_point_v", "VB1_structured_v", "VB2_structured_u")
  if (nrow(candidate_summary) != 480L ||
      !setequal(unique(candidate_summary$inference_method_id), expected_methods)) {
    stop("Phase166 candidate summary is not the complete 480-row method comparison.", call. = FALSE)
  }
  key <- paste(
    candidate_summary$base_scenario_id,
    candidate_summary$dgp_replicate_id,
    candidate_summary$fit_structure,
    sep = "::"
  )
  if (any(table(key) != 3L)) stop("Phase166 matched method cells are incomplete.", call. = FALSE)

  structure_method <- do.call(rbind, lapply(
    split(candidate_summary, interaction(
      candidate_summary$fit_structure,
      candidate_summary$inference_method_id,
      drop = TRUE, lex.order = TRUE
    )),
    function(x) data.frame(
      fit_structure = x$fit_structure[[1L]],
      inference_method_id = x$inference_method_id[[1L]],
      rows = nrow(x),
      implementation_failures = sum(x$implementation_status == "fail"),
      pass_rows = sum(x$gate_status == "pass"),
      review_rows = sum(x$gate_status == "review"),
      converged_rows = sum(x$vb_converged),
      convergence_rate = mean(x$vb_converged),
      contract_crossing_pairs = sum(
        x$fit_contract_crossing_pairs + x$forecast_contract_crossing_pairs
      ),
      mean_fit_truth_mae = mean(x$fit_truth_mae),
      mean_forecast_truth_mae = mean(x$forecast_truth_mae),
      mean_fit_check_loss = mean(x$fit_check_loss_mean),
      mean_forecast_check_loss = mean(x$forecast_check_loss_mean),
      mean_fit_crps_grid = mean(x$fit_crps_grid_mean),
      mean_forecast_crps_grid = mean(x$forecast_crps_grid_mean),
      median_runtime_seconds = stats::median(x$total_elapsed_seconds),
      stringsAsFactors = FALSE
    )
  ))
  rownames(structure_method) <- NULL

  keys <- c("base_scenario_id", "dgp_replicate_id", "fit_structure")
  v <- candidate_summary[candidate_summary$inference_method_id == "VB1_structured_v", ]
  u <- candidate_summary[candidate_summary$inference_method_id == "VB2_structured_u", ]
  paired <- merge(v, u, by = keys, suffixes = c("_v", "_u"), sort = FALSE)
  if (nrow(paired) != 160L) stop("Phase167 requires 160 paired VB1/VB2 cells.", call. = FALSE)
  metrics <- c(
    "fit_truth_mae", "forecast_truth_mae", "fit_check_loss_mean",
    "forecast_check_loss_mean", "fit_crps_grid_mean",
    "forecast_crps_grid_mean", "total_elapsed_seconds"
  )
  for (metric in metrics) {
    paired[[paste0(metric, "_delta_u_minus_v")]] <-
      paired[[paste0(metric, "_u")]] - paired[[paste0(metric, "_v")]]
  }
  scenario_paired <- do.call(rbind, lapply(
    split(paired, interaction(
      paired$base_scenario_id, paired$fit_structure,
      drop = TRUE, lex.order = TRUE
    )),
    function(x) data.frame(
      base_scenario_id = x$base_scenario_id[[1L]],
      fit_structure = x$fit_structure[[1L]],
      replicate_pairs = nrow(x),
      median_fit_mae_delta_u_minus_v = stats::median(x$fit_truth_mae_delta_u_minus_v),
      median_forecast_mae_delta_u_minus_v = stats::median(x$forecast_truth_mae_delta_u_minus_v),
      median_forecast_crps_delta_u_minus_v = stats::median(x$forecast_crps_grid_mean_delta_u_minus_v),
      u_forecast_mae_wins = sum(x$forecast_truth_mae_delta_u_minus_v < 0),
      median_runtime_delta_u_minus_v = stats::median(x$total_elapsed_seconds_delta_u_minus_v),
      stringsAsFactors = FALSE
    )
  ))
  rownames(scenario_paired) <- NULL

  decision <- do.call(rbind, lapply(c("joint", "independent"), function(structure) {
    rows <- structure_method[structure_method$fit_structure == structure, ]
    v_row <- rows[rows$inference_method_id == "VB1_structured_v", ]
    u_row <- rows[rows$inference_method_id == "VB2_structured_u", ]
    q <- paired[paired$fit_structure == structure, ]
    hard_pass <-
      v_row$implementation_failures[[1L]] == 0L &&
      u_row$implementation_failures[[1L]] == 0L &&
      v_row$contract_crossing_pairs[[1L]] == 0L &&
      u_row$contract_crossing_pairs[[1L]] == 0L
    v_stable <- v_row$convergence_rate[[1L]] >= 0.90
    v_noninferior <- mean(q$forecast_truth_mae_delta_u_minus_v) >= -1.0e-4 &&
      mean(q$forecast_crps_grid_mean_delta_u_minus_v) >= -1.0e-5
    v_faster <- stats::median(q$total_elapsed_seconds_delta_u_minus_v) > 0
    selected <- if (hard_pass && v_stable && v_noninferior && v_faster) {
      "VB1_structured_v"
    } else {
      NA_character_
    }
    data.frame(
      fit_structure = structure,
      selected_vb_method = selected,
      method_decision_status = if (!is.na(selected)) "pass" else "fail",
      implementation_gate = if (hard_pass) "pass" else "fail",
      selected_convergence_rate = v_row$convergence_rate[[1L]],
      selected_review_rows = v_row$review_rows[[1L]],
      mean_forecast_mae_delta_u_minus_v = mean(q$forecast_truth_mae_delta_u_minus_v),
      median_forecast_mae_delta_u_minus_v = stats::median(q$forecast_truth_mae_delta_u_minus_v),
      u_forecast_mae_win_fraction = mean(q$forecast_truth_mae_delta_u_minus_v < 0),
      median_runtime_delta_u_minus_v = stats::median(q$total_elapsed_seconds_delta_u_minus_v),
      rationale = paste(
        "VB1 preserves the exact implementation/contract gates, converges in at least 90% of rows,",
        "is noninferior in paired quantile metrics, and is materially faster than VB2."
      ),
      stringsAsFactors = FALSE
    )
  }))
  if (any(decision$method_decision_status != "pass")) {
    stop("Phase167 could not freeze one structured method per fit structure.", call. = FALSE)
  }
  list(
    structure_method = structure_method,
    paired = paired,
    scenario_paired = scenario_paired,
    decision = decision
  )
}

app_joint_exqdesn_phase167_tau_audit <- function(tau_summary, candidate_summary) {
  map <- unique(candidate_summary[, c("candidate_id", "fit_structure")])
  out <- merge(tau_summary, map, by = "candidate_id", all.x = TRUE, sort = FALSE)
  v <- out[out$inference_method_id == "VB1_structured_v", ]
  u <- out[out$inference_method_id == "VB2_structured_u", ]
  keys <- c(
    "base_scenario_id", "dgp_replicate_id", "fit_structure",
    "validation_window", "tau"
  )
  paired <- merge(v, u, by = keys, suffixes = c("_v", "_u"), sort = FALSE)
  paired$truth_mae_delta_u_minus_v <- paired$truth_mae_u - paired$truth_mae_v
  paired$check_loss_delta_u_minus_v <- paired$check_loss_mean_u - paired$check_loss_mean_v
  paired$abs_hit_error_delta_u_minus_v <- paired$abs_hit_rate_error_u - paired$abs_hit_rate_error_v
  aggregate(
    cbind(
      truth_mae_delta_u_minus_v,
      check_loss_delta_u_minus_v,
      abs_hit_error_delta_u_minus_v
    ) ~ fit_structure + validation_window + tau,
    paired,
    function(x) c(mean = mean(x), median = stats::median(x), u_wins = sum(x < 0))
  )
}

app_joint_exqdesn_phase167_write <- function(
  dirs = app_joint_exqdesn_phase167_169_dirs()
) {
  app_ensure_dir(dirs$phase167)
  verification <- do.call(rbind, list(
    app_joint_exqdesn_verify_manifest(dirs$phase164, "phase164"),
    app_joint_exqdesn_verify_manifest(dirs$phase165, "phase165"),
    app_joint_exqdesn_verify_manifest(dirs$phase166, "phase166")
  ))
  if (any(verification$status != "pass")) {
    stop("Phase167 source-manifest verification failed.", call. = FALSE)
  }
  assessment166 <- app_read_csv(file.path(dirs$phase166, "phase166_assessment.csv"))
  if (assessment166$completed_rows[[1L]] != 480L ||
      assessment166$implementation_failures[[1L]] != 0L ||
      assessment166$contract_crossing_pairs[[1L]] != 0L) {
    stop("Phase167 is blocked by the Phase166 hard gates.", call. = FALSE)
  }
  candidate <- app_read_csv(file.path(dirs$phase166, "phase166_candidate_summary.csv"))
  tau <- app_read_csv(file.path(dirs$phase166, "phase166_tau_summary.csv"))
  audit <- app_joint_exqdesn_phase167_method_audit(candidate)
  tau_audit <- app_joint_exqdesn_phase167_tau_audit(tau, candidate)
  review <- candidate[candidate$gate_status == "review", c(
    "candidate_id", "base_scenario_id", "dgp_replicate_id", "fit_structure",
    "inference_method_id", "vb_converged", "vb_reached_max_iter",
    "forecast_raw_crossing_pairs", "status_reason"
  ), drop = FALSE]
  assessment <- data.frame(
    gate_status = "pass",
    statistical_status = if (nrow(review)) "review" else "pass",
    phase166_rows = nrow(candidate),
    source_hash_failures = sum(verification$status != "pass"),
    implementation_failures = sum(candidate$implementation_status == "fail"),
    contract_crossing_pairs = sum(
      candidate$fit_contract_crossing_pairs + candidate$forecast_contract_crossing_pairs
    ),
    selected_joint_method = audit$decision$selected_vb_method[
      audit$decision$fit_structure == "joint"
    ],
    selected_independent_method = audit$decision$selected_vb_method[
      audit$decision$fit_structure == "independent"
    ],
    recalibration_decision = "defer_model_recalibration_during_sampler_method_isolation",
    recommendation = "prepare_phase169_exact_mcmc_method_selection",
    stringsAsFactors = FALSE
  )
  readme <- file.path(dirs$phase167, "README.md")
  writeLines(c(
    "# Phase167 structured-VB method freeze", "",
    "Phase167 freezes `VB1_structured_v` for both Joint and Independent exQDESN.",
    "The decision uses all 480 Phase166 rows and preserves the scenario-specific DESN/RHS controls.",
    "Finite max-iteration rows remain review evidence; there are no implementation failures or contract crossings.",
    "No model-control recalibration or article promotion is performed here.",
    "The next artifact is a five-scenario exact-MCMC sampler-method comparison."
  ), readme, useBytes = TRUE)
  paths <- c(
    method_decision = app_joint_qvp_write_csv(audit$decision, file.path(dirs$phase167, "method_decision.csv")),
    structure_method_summary = app_joint_qvp_write_csv(audit$structure_method, file.path(dirs$phase167, "structure_method_summary.csv")),
    paired_method_comparison = app_joint_qvp_write_csv(audit$paired, file.path(dirs$phase167, "paired_method_comparison.csv")),
    scenario_paired_summary = app_joint_qvp_write_csv(audit$scenario_paired, file.path(dirs$phase167, "scenario_paired_summary.csv")),
    tau_paired_summary = app_joint_qvp_write_csv(tau_audit, file.path(dirs$phase167, "tau_paired_summary.csv")),
    review_audit = app_joint_qvp_write_csv(review, file.path(dirs$phase167, "review_audit.csv")),
    source_manifest_verification = app_joint_qvp_write_csv(verification, file.path(dirs$phase167, "source_manifest_verification.csv")),
    phase167_assessment = app_joint_qvp_write_csv(assessment, file.path(dirs$phase167, "phase167_assessment.csv")),
    source_code_snapshot = app_joint_qvp_write_csv(app_joint_exqdesn_phase167_source_snapshot(), file.path(dirs$phase167, "source_code_snapshot.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(dirs$phase167, "provenance.csv")),
    README = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_write_manifest(paths, dirs$phase167)
  list(
    dirs = dirs,
    audit = audit,
    assessment = assessment,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}

app_joint_exqdesn_phase169_scenarios <- function() {
  c(
    "persistent_heavy_tail",
    "asymmetric_laplace_tail",
    "normal_bridge",
    "nonlinear_reservoir_friendly",
    "regime_shift"
  )
}

app_joint_exqdesn_phase169_selected_controls <- function(
  registry,
  scenarios = app_joint_exqdesn_phase169_scenarios()
) {
  selected <- registry[
    registry$base_scenario_id %in% scenarios &
      registry$dgp_replicate_id == "r001" &
      registry$inference_method_id == "VB1_structured_v",
    , drop = FALSE
  ]
  selected <- selected[order(
    match(selected$base_scenario_id, scenarios),
    match(selected$fit_structure, c("joint", "independent"))
  ), , drop = FALSE]
  key <- paste(selected$base_scenario_id, selected$fit_structure, sep = "::")
  if (nrow(selected) != length(scenarios) * 2L || anyDuplicated(key)) {
    stop("Phase169 requires one r001 control for each prespecified scenario/structure cell.", call. = FALSE)
  }
  selected$mcmc_case_id <- paste(
    selected$scenario_ids, selected$fit_structure, sep = "__"
  )
  selected$selection_role <- "exact_mcmc_method_development"
  selected$vb_initialization_method <- "VB1_structured_v"
  selected
}

app_joint_exqdesn_phase169_init_rows <- function(fit, row) {
  blocks <- list(
    beta = as.numeric(fit$beta_mean),
    alpha = as.numeric(fit$alpha_mean),
    sigma = as.numeric(fit$sigma_mean),
    gamma = as.numeric(fit$gamma_mean)
  )
  if (any(!is.finite(unlist(blocks, use.names = FALSE))) || any(blocks$sigma <= 0)) {
    stop("Phase169 VB initialization is nonfinite or has nonpositive scale.", call. = FALSE)
  }
  do.call(rbind, lapply(names(blocks), function(block) data.frame(
    mcmc_case_id = row$mcmc_case_id[[1L]],
    scenario_id = row$scenario_ids[[1L]],
    base_scenario_id = row$base_scenario_id[[1L]],
    fit_structure = row$fit_structure[[1L]],
    parameter_block = block,
    parameter_index = seq_along(blocks[[block]]),
    value = blocks[[block]],
    initialization_method_id = "VB1_structured_v",
    stringsAsFactors = FALSE
  )))
}

app_joint_exqdesn_phase169_fit_vb_initialization <- function(
  row,
  dirs = app_joint_exqdesn_phase167_169_dirs(),
  n_chains = 8L
) {
  artifacts <- app_joint_exqdesn_load_selected_fixture_artifacts(row$scenario_ids[[1L]], dirs)
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, row$scenario_ids[[1L]], role = "fit")
  args <- app_joint_exqdesn_phase166_control_args(row, fixture)
  warm <- app_joint_exqdesn_phase166_vb0_warm_start(row, fixture)
  fit <- if (row$fit_structure[[1L]] == "joint") {
    do.call(
      app_joint_exqdesn_fit_vb_dispatch,
      c(list(
        method_id = "VB1_structured_v", y = fixture$y, Z = fixture$Z,
        tau = fixture$tau, init = warm
      ), args)
    )
  } else {
    do.call(
      app_joint_exqdesn_fit_independent_vb_dispatch,
      c(list(
        method_id = "VB1_structured_v", y = fixture$y, Z = fixture$Z,
        tau = fixture$tau, init = warm
      ), args)
    )
  }
  init <- app_joint_exqdesn_phase169_init_rows(fit, row)
  start_fit <- list(sigma_mean = as.numeric(fit$sigma_mean), gamma_mean = as.numeric(fit$gamma_mean))
  starts <- app_joint_exqdesn_phase156_chain_starts(
    start_fit, fixture$tau, row$mcmc_case_id[[1L]], n_chains
  )
  names(starts)[names(starts) == "scenario_id"] <- "mcmc_case_id"
  starts$scenario_id <- row$scenario_ids[[1L]]
  starts$base_scenario_id <- row$base_scenario_id[[1L]]
  starts$fit_structure <- row$fit_structure[[1L]]
  convergence <- data.frame(
    mcmc_case_id = row$mcmc_case_id[[1L]],
    scenario_id = row$scenario_ids[[1L]],
    base_scenario_id = row$base_scenario_id[[1L]],
    fit_structure = row$fit_structure[[1L]],
    initialization_method_id = "VB1_structured_v",
    converged = isTRUE(fit$converged),
    finite_initialization = all(is.finite(init$value)),
    min_sigma = min(fit$sigma_mean),
    max_sigma = max(fit$sigma_mean),
    stringsAsFactors = FALSE
  )
  list(init = init, starts = starts, convergence = convergence)
}

app_joint_exqdesn_phase169_chain_plan <- function(
  controls,
  out_dir,
  n_chains = 8L,
  n_iter = 12000L,
  burn = 3000L,
  thin = 3L,
  seed_base = 202608070L,
  chain_seed_stride = 1009L,
  workers_per_wave = 32L
) {
  methods <- c(
    "M0_v_collapsed_support_logit",
    "M1b_u_collapsed_support_logit",
    "M1_u_collapsed_p_logit"
  )
  if (n_chains < 4L || n_iter <= burn || thin <= 0L ||
      ((n_iter - burn) %% thin) != 0L) {
    stop("Invalid Phase169 chain controls.", call. = FALSE)
  }
  rows <- list()
  worker_id <- 0L
  for (case_index in seq_len(nrow(controls))) {
    for (method_index in seq_along(methods)) {
      for (chain_id in seq_len(n_chains)) {
        worker_id <- worker_id + 1L
        method <- methods[[method_index]]
        rows[[worker_id]] <- data.frame(
          worker_id = worker_id,
          wave_id = ceiling(worker_id / workers_per_wave),
          case_index = case_index,
          mcmc_case_id = controls$mcmc_case_id[[case_index]],
          scenario_id = controls$scenario_ids[[case_index]],
          base_scenario_id = controls$base_scenario_id[[case_index]],
          fit_structure = controls$fit_structure[[case_index]],
          inference_method_id = method,
          chain_id = chain_id,
          chain_seed = as.integer(
            seed_base + case_index * 100000L + method_index * 10000L +
              (chain_id - 1L) * chain_seed_stride
          ),
          seed_role = "phase169_exact_mcmc_method_selection_chain",
          start_profile_id = sprintf("%s__chain_%02d", controls$mcmc_case_id[[case_index]], chain_id),
          n_iter = as.integer(n_iter),
          burn = as.integer(burn),
          thin = as.integer(thin),
          n_keep = as.integer((n_iter - burn) / thin),
          gamma_slice_width = if (method == "M1_u_collapsed_p_logit") 1 else 4,
          gamma_slice_max_steps = 250L,
          worker_output_dir = file.path(
            out_dir, "candidates", controls$mcmc_case_id[[case_index]], method,
            sprintf("chain_%02d", chain_id)
          ),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  plan <- do.call(rbind, rows)
  if (anyDuplicated(plan$chain_seed) || anyDuplicated(plan$worker_output_dir)) {
    stop("Phase169 chain seeds or output directories are duplicated.", call. = FALSE)
  }
  plan
}

app_joint_exqdesn_phase169_prepare <- function(
  dirs = app_joint_exqdesn_phase167_169_dirs(),
  n_chains = 8L,
  n_iter = 12000L,
  burn = 3000L,
  thin = 3L,
  seed_base = 202608070L,
  chain_seed_stride = 1009L,
  workers_per_wave = 32L,
  n_vb_cores = 10L
) {
  phase167 <- app_joint_exqdesn_phase167_write(dirs)
  app_ensure_dir(dirs$phase169_freeze)
  app_ensure_dir(dirs$phase169)
  verification <- do.call(rbind, list(
    app_joint_exqdesn_verify_manifest(dirs$phase167, "phase167"),
    app_joint_exqdesn_verify_manifest(dirs$selected_fixtures, "phase166_selected_fixtures")
  ))
  if (any(verification$status != "pass")) {
    stop("Phase169 source-manifest verification failed.", call. = FALSE)
  }
  registry <- app_read_csv(file.path(dirs$phase164, "method_development_registry.csv"))
  controls <- app_joint_exqdesn_phase169_selected_controls(registry)
  jobs <- lapply(seq_len(nrow(controls)), function(ii) controls[ii, , drop = FALSE])
  run_one <- function(row) app_joint_exqdesn_phase169_fit_vb_initialization(row, dirs, n_chains)
  vb_results <- if (.Platform$OS.type != "windows" && n_vb_cores > 1L) {
    parallel::mclapply(jobs, run_one, mc.cores = min(as.integer(n_vb_cores), length(jobs)))
  } else {
    lapply(jobs, run_one)
  }
  errors <- vapply(vb_results, inherits, logical(1L), "try-error")
  if (any(errors)) {
    stop(sprintf("Phase169 VB initialization failed for %d cells.", sum(errors)), call. = FALSE)
  }
  init <- app_joint_qdesn_bind_rows(lapply(vb_results, `[[`, "init"))
  starts <- app_joint_qdesn_bind_rows(lapply(vb_results, `[[`, "starts"))
  convergence <- app_joint_qdesn_bind_rows(lapply(vb_results, `[[`, "convergence"))
  if (any(!is.finite(init$value)) || any(init$value[init$parameter_block == "sigma"] <= 0)) {
    stop("Phase169 compact initialization failed its finiteness gate.", call. = FALSE)
  }
  plan <- app_joint_exqdesn_phase169_chain_plan(
    controls, dirs$phase169, n_chains, n_iter, burn, thin,
    seed_base, chain_seed_stride, workers_per_wave
  )
  if (nrow(plan) != 240L) stop("Phase169 must contain exactly 240 chains.", call. = FALSE)
  config <- data.frame(
    phase_id = "phase169_exact_mcmc_method_selection",
    source_phase166_dir = dirs$phase166,
    source_phase167_dir = dirs$phase167,
    fixture_dir = dirs$selected_fixtures,
    output_dir = dirs$phase169,
    scenarios = 5L,
    fit_structures = 2L,
    methods = 3L,
    n_chains = as.integer(n_chains),
    planned_workers = nrow(plan),
    n_iter = as.integer(n_iter),
    burn = as.integer(burn),
    thin = as.integer(thin),
    n_keep_per_chain = as.integer((n_iter - burn) / thin),
    workers_per_wave = as.integer(workers_per_wave),
    selected_vb_method = "VB1_structured_v",
    model_control_policy = "frozen_case_specific_no_recalibration",
    evidence_role = "exact_mcmc_method_development",
    article_assets_modified = FALSE,
    stringsAsFactors = FALSE
  )
  readiness <- data.frame(
    gate_status = if (
      all(phase167$assessment$gate_status == "pass") &&
        all(convergence$finite_initialization) &&
        nrow(plan) == 240L &&
        !anyDuplicated(plan$chain_seed)
    ) "pass" else "fail",
    selected_cells = nrow(controls),
    finite_vb_initializations = sum(convergence$finite_initialization),
    planned_workers = nrow(plan),
    unique_chain_seeds = length(unique(plan$chain_seed)),
    source_hash_failures = sum(verification$status != "pass"),
    recommendation = "launch_phase169_exact_mcmc_method_selection",
    stringsAsFactors = FALSE
  )
  if (readiness$gate_status[[1L]] != "pass") {
    stop("Phase169 readiness gate failed.", call. = FALSE)
  }
  readme <- file.path(dirs$phase169_freeze, "README.md")
  writeLines(c(
    "# Phase169 exact-MCMC method-selection freeze", "",
    "This freeze compares M0, M1b, and M1 on five prespecified scenarios and both fit structures.",
    "Every method uses the same frozen case-specific model controls and matched chain-start profile.",
    "VB1 structured-v supplies initialization only; all three MCMC methods target the exact exAL posterior.",
    "The campaign uses eight chains, 12,000 iterations, 3,000 burn-in iterations, and storage thinning by three.",
    "No article outputs are modified and this is not final article evidence."
  ), readme, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(config, file.path(dirs$phase169_freeze, "run_config.csv")),
    selected_case_controls = app_joint_qvp_write_csv(controls, file.path(dirs$phase169_freeze, "selected_case_controls.csv")),
    vb_initialization = app_joint_qvp_write_csv(init, file.path(dirs$phase169_freeze, "vb_initialization.csv")),
    vb_initialization_audit = app_joint_qvp_write_csv(convergence, file.path(dirs$phase169_freeze, "vb_initialization_audit.csv")),
    chain_start_values = app_joint_qvp_write_csv(starts, file.path(dirs$phase169_freeze, "chain_start_values.csv")),
    chain_plan = app_joint_qvp_write_csv(plan, file.path(dirs$phase169_freeze, "chain_plan.csv")),
    source_manifest_verification = app_joint_qvp_write_csv(verification, file.path(dirs$phase169_freeze, "source_manifest_verification.csv")),
    source_code_snapshot = app_joint_qvp_write_csv(app_joint_exqdesn_phase167_source_snapshot(), file.path(dirs$phase169_freeze, "source_code_snapshot.csv")),
    readiness_assessment = app_joint_qvp_write_csv(readiness, file.path(dirs$phase169_freeze, "readiness_assessment.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(dirs$phase169_freeze, "provenance.csv")),
    README = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_write_manifest(paths, dirs$phase169_freeze)
  list(
    dirs = dirs,
    phase167 = phase167,
    readiness = readiness,
    controls = controls,
    plan = plan,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}

app_joint_exqdesn_phase169_load_freeze <- function(
  freeze_dir = app_joint_exqdesn_phase167_169_dirs()$phase169_freeze
) {
  freeze_dir <- normalizePath(freeze_dir, mustWork = TRUE)
  verification <- app_joint_exqdesn_verify_manifest(freeze_dir, "phase169_freeze")
  if (any(verification$status != "pass")) stop("Phase169 freeze manifest failed.", call. = FALSE)
  list(
    dir = freeze_dir,
    verification = verification,
    config = app_read_csv(file.path(freeze_dir, "run_config.csv")),
    controls = app_read_csv(file.path(freeze_dir, "selected_case_controls.csv")),
    init = app_read_csv(file.path(freeze_dir, "vb_initialization.csv")),
    starts = app_read_csv(file.path(freeze_dir, "chain_start_values.csv")),
    plan = app_read_csv(file.path(freeze_dir, "chain_plan.csv")),
    readiness = app_read_csv(file.path(freeze_dir, "readiness_assessment.csv"))
  )
}

app_joint_exqdesn_phase169_init_from_rows <- function(rows, case_id, fit_structure, K, p) {
  block <- function(name) {
    x <- rows[rows$mcmc_case_id == case_id & rows$parameter_block == name, , drop = FALSE]
    as.numeric(x$value[order(x$parameter_index)])
  }
  combined <- list(
    beta_mean = block("beta"), alpha_mean = block("alpha"),
    sigma_mean = block("sigma"), gamma_mean = block("gamma")
  )
  if (length(combined$beta_mean) != K * p || length(combined$alpha_mean) != K ||
      length(combined$sigma_mean) != K || length(combined$gamma_mean) != K ||
      any(!is.finite(unlist(combined, use.names = FALSE))) || any(combined$sigma_mean <= 0)) {
    stop("Malformed Phase169 compact VB initialization.", call. = FALSE)
  }
  if (fit_structure == "joint") return(combined)
  combined$fits <- lapply(seq_len(K), function(k) {
    idx <- ((k - 1L) * p + 1L):(k * p)
    list(
      beta_mean = combined$beta_mean[idx],
      alpha_mean = combined$alpha_mean[[k]],
      sigma_mean = combined$sigma_mean[[k]],
      gamma_mean = combined$gamma_mean[[k]]
    )
  })
  combined
}

app_joint_exqdesn_phase169_apply_chain_start <- function(init, starts, job, K, p) {
  block <- starts[
    starts$mcmc_case_id == job$mcmc_case_id[[1L]] &
      starts$chain_id == job$chain_id[[1L]],
    , drop = FALSE
  ]
  gamma <- block$value[block$parameter == "gamma"][order(block$quantile_index[block$parameter == "gamma"])]
  sigma <- block$value[block$parameter == "sigma"][order(block$quantile_index[block$parameter == "sigma"])]
  if (length(gamma) != K || length(sigma) != K || any(!is.finite(c(gamma, sigma))) || any(sigma <= 0)) {
    stop("Malformed Phase169 matched chain start.", call. = FALSE)
  }
  init$gamma_mean <- gamma
  init$sigma_mean <- sigma
  if (!is.null(init$fits)) {
    init$fits <- lapply(seq_len(K), function(k) {
      idx <- ((k - 1L) * p + 1L):(k * p)
      list(
        beta_mean = init$beta_mean[idx], alpha_mean = init$alpha_mean[[k]],
        sigma_mean = sigma[[k]], gamma_mean = gamma[[k]]
      )
    })
  }
  init
}

app_joint_exqdesn_phase169_worker_complete <- function(worker_dir) {
  required <- c(
    "posterior_draws.csv.gz", "chain_summary.csv", "sampler_diagnostics.csv",
    "runtime.csv", "provenance.csv", "README.md", "artifact_manifest.csv"
  )
  if (!dir.exists(worker_dir) || any(!file.exists(file.path(worker_dir, required)))) return(FALSE)
  verified <- tryCatch(
    app_joint_exqdesn_verify_manifest(worker_dir, "phase169_chain"),
    error = function(e) NULL
  )
  !is.null(verified) && nrow(verified) > 0L && all(verified$status == "pass")
}

app_joint_exqdesn_phase169_density_evaluations <- function(fit, K) {
  if (!is.null(fit$gamma_collapsed_density_evaluations)) {
    return(rep(as.numeric(fit$gamma_collapsed_density_evaluations), length.out = K))
  }
  if (!is.null(fit$fits)) {
    return(vapply(fit$fits, function(x) {
      sum(as.numeric(x$gamma_collapsed_density_evaluations %||% 0))
    }, numeric(1L)))
  }
  rep(NA_real_, K)
}

app_joint_exqdesn_phase169_sampler_rows <- function(fit, fixture, job) {
  K <- length(fixture$tau)
  density <- app_joint_exqdesn_phase169_density_evaluations(fit, K)
  app_joint_qdesn_bind_rows(lapply(seq_len(K), function(k) {
    gamma <- fit$gamma_draws[, k]
    sigma <- fit$sigma_draws[, k]
    cst <- lapply(gamma, function(g) app_joint_exqdesn_constants(fixture$tau[[k]], g))
    p_gamma <- vapply(cst, function(x) x$p_gamma[[1L]], numeric(1L))
    actual_sd <- sigma * vapply(cst, function(x) x$sd_factor[[1L]], numeric(1L))
    sigma_lambda <- sigma * vapply(cst, function(x) x$lambda[[1L]], numeric(1L))
    data.frame(
      worker_id = job$worker_id[[1L]],
      mcmc_case_id = job$mcmc_case_id[[1L]],
      scenario_id = job$scenario_id[[1L]],
      fit_structure = job$fit_structure[[1L]],
      inference_method_id = job$inference_method_id[[1L]],
      chain_id = job$chain_id[[1L]],
      quantile_index = k,
      tau = fixture$tau[[k]],
      gamma_mean = mean(gamma), gamma_sd = stats::sd(gamma),
      sigma_mean = mean(sigma), sigma_sd = stats::sd(sigma),
      p_gamma_mean = mean(p_gamma), p_gamma_sd = stats::sd(p_gamma),
      actual_sd_mean = mean(actual_sd), actual_sd_sd = stats::sd(actual_sd),
      sigma_lambda_mean = mean(sigma_lambda), sigma_lambda_sd = stats::sd(sigma_lambda),
      gamma_sigma_correlation = stats::cor(gamma, sigma),
      gamma_actual_sd_correlation = stats::cor(gamma, actual_sd),
      gamma_rough_ess = app_joint_exqdesn_rough_ess_one_chain(gamma),
      sigma_rough_ess = app_joint_exqdesn_rough_ess_one_chain(sigma),
      p_gamma_rough_ess = app_joint_exqdesn_rough_ess_one_chain(p_gamma),
      actual_sd_rough_ess = app_joint_exqdesn_rough_ess_one_chain(actual_sd),
      branch_transitions = sum(diff(gamma < 0) != 0),
      collapsed_density_evaluations = density[[k]],
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase169_run_worker <- function(
  freeze_dir,
  worker_id,
  reuse_completed = TRUE,
  failure_dir = NULL
) {
  freeze <- app_joint_exqdesn_phase169_load_freeze(freeze_dir)
  worker_id <- as.integer(worker_id)[[1L]]
  job <- freeze$plan[freeze$plan$worker_id == worker_id, , drop = FALSE]
  if (nrow(job) != 1L) stop("Unknown Phase169 worker id.", call. = FALSE)
  worker_dir <- job$worker_output_dir[[1L]]
  if (reuse_completed && app_joint_exqdesn_phase169_worker_complete(worker_dir)) {
    return(list(worker_id = worker_id, status = "reused_verified", worker_dir = worker_dir))
  }
  if (dir.exists(worker_dir) && length(list.files(worker_dir, all.files = TRUE, no.. = TRUE))) {
    quarantine <- paste0(worker_dir, "_incomplete_", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(worker_dir, quarantine)) stop("Could not quarantine incomplete Phase169 worker.", call. = FALSE)
  }
  app_ensure_dir(worker_dir)
  tryCatch({
    row <- freeze$controls[freeze$controls$mcmc_case_id == job$mcmc_case_id[[1L]], , drop = FALSE]
    if (nrow(row) != 1L) stop("Phase169 worker could not resolve frozen controls.", call. = FALSE)
    dirs <- app_joint_exqdesn_phase167_169_dirs()
    artifacts <- app_joint_exqdesn_load_selected_fixture_artifacts(job$scenario_id[[1L]], dirs)
    fixture <- app_joint_qdesn_scenario_fixture(artifacts, job$scenario_id[[1L]], role = "fit")
    K <- length(fixture$tau)
    p <- ncol(fixture$Z)
    init <- app_joint_exqdesn_phase169_init_from_rows(
      freeze$init, job$mcmc_case_id[[1L]], job$fit_structure[[1L]], K, p
    )
    init <- app_joint_exqdesn_phase169_apply_chain_start(init, freeze$starts, job, K, p)
    alpha_prior_sd <- app_joint_qdesn_parse_numeric_vector(
      row$alpha_prior_sd[[1L]], "alpha_prior_sd", allow_inf = TRUE
    )
    common <- list(
      y = fixture$y, Z = fixture$Z, tau = fixture$tau,
      n_iter = as.integer(job$n_iter[[1L]]), burn = as.integer(job$burn[[1L]]),
      thin = as.integer(job$thin[[1L]]), seed = as.integer(job$chain_seed[[1L]]),
      kappa = 1, tau0 = as.numeric(row$tau0[[1L]]), zeta2 = as.numeric(row$zeta2[[1L]]),
      a_sigma = as.numeric(row$a_sigma[[1L]]), b_sigma = as.numeric(row$b_sigma[[1L]]),
      gamma_init = init$gamma_mean, init = init,
      alpha_prior_mean = "empirical_quantile", alpha_prior_sd = alpha_prior_sd,
      alpha_min_spacing = if (job$fit_structure[[1L]] == "joint") as.numeric(row$alpha_min_spacing[[1L]]) else 0,
      max_dense_dim = as.integer(row$max_dense_dim[[1L]]),
      gamma_slice_width = as.numeric(job$gamma_slice_width[[1L]]),
      gamma_slice_max_steps = as.integer(job$gamma_slice_max_steps[[1L]])
    )
    started <- proc.time()[["elapsed"]]
    fit <- if (job$fit_structure[[1L]] == "joint") {
      do.call(
        app_joint_exqdesn_fit_mcmc_dispatch,
        c(list(method_id = job$inference_method_id[[1L]]), common)
      )
    } else {
      do.call(
        app_joint_exqdesn_fit_independent_mcmc_dispatch,
        c(list(method_id = job$inference_method_id[[1L]]), common)
      )
    }
    elapsed <- proc.time()[["elapsed"]] - started
    draws <- app_joint_exqdesn_phase157_draw_frame(fit)
    if (any(!is.finite(as.matrix(draws[, -1L, drop = FALSE]))) || any(fit$sigma_draws <= 0)) {
      stop("Phase169 worker produced invalid posterior draws.", call. = FALSE)
    }
    meta <- data.frame(
      scenario_id = job$scenario_id[[1L]],
      base_scenario_id = job$base_scenario_id[[1L]],
      model_id = if (job$fit_structure[[1L]] == "joint") "joint_exqdesn_rhs_mcmc" else "independent_exqdesn_rhs_mcmc",
      fit_structure = job$fit_structure[[1L]],
      inference_method_id = job$inference_method_id[[1L]],
      stringsAsFactors = FALSE
    )
    fit_score <- app_joint_qdesn_phase122_score_qhat(
      meta, fixture, app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau),
      "qhat", "phase169_chain_fit"
    )
    forecast_score <- app_joint_qdesn_phase122_forecast_scores(
      meta, artifacts, job$scenario_id[[1L]], fixture, fit,
      "qhat", "phase169_chain_forecast"
    )
    contract_crossings <- sum(fit_score$contract_info$contract_crossing$n_crossing_pairs) +
      sum(forecast_score$contract_crossing$n_crossing_pairs)
    summary <- data.frame(
      worker_id = worker_id,
      mcmc_case_id = job$mcmc_case_id[[1L]],
      scenario_id = job$scenario_id[[1L]],
      base_scenario_id = job$base_scenario_id[[1L]],
      fit_structure = job$fit_structure[[1L]],
      inference_method_id = job$inference_method_id[[1L]],
      chain_id = job$chain_id[[1L]],
      chain_seed = job$chain_seed[[1L]],
      start_profile_id = job$start_profile_id[[1L]],
      n_iter = job$n_iter[[1L]], burn = job$burn[[1L]], thin = job$thin[[1L]],
      n_keep = nrow(draws), init_source = fit$init_source %||% "provided",
      fit_truth_mae = mean(fit_score$scored$truth_abs_error),
      forecast_truth_mae = mean(forecast_score$scored$truth_abs_error),
      fit_check_loss_mean = mean(fit_score$scored$check_loss),
      forecast_check_loss_mean = mean(forecast_score$scored$check_loss),
      fit_crps_grid_mean = app_joint_qdesn_crps_grid_summary(fit_score$scored)$crps_grid_mean[[1L]],
      forecast_crps_grid_mean = app_joint_qdesn_crps_grid_summary(forecast_score$scored)$crps_grid_mean[[1L]],
      raw_crossing_pairs = sum(fit_score$contract_info$raw_crossing$n_crossing_pairs) +
        sum(forecast_score$raw_crossing$n_crossing_pairs),
      contract_crossing_pairs = contract_crossings,
      draws_all_finite = TRUE,
      min_sigma = min(fit$sigma_draws), max_sigma = max(fit$sigma_draws),
      min_gamma = min(fit$gamma_draws), max_gamma = max(fit$gamma_draws),
      elapsed_seconds = elapsed,
      seconds_per_iteration = elapsed / job$n_iter[[1L]],
      stringsAsFactors = FALSE
    )
    if (summary$contract_crossing_pairs[[1L]] > 0L) {
      stop("Phase169 chain contract qhat crosses.", call. = FALSE)
    }
    sampler <- app_joint_exqdesn_phase169_sampler_rows(fit, fixture, job)
    runtime <- summary[, c(
      "worker_id", "mcmc_case_id", "scenario_id", "fit_structure",
      "inference_method_id", "chain_id", "chain_seed", "elapsed_seconds",
      "seconds_per_iteration"
    ), drop = FALSE]
    readme <- file.path(worker_dir, "README.md")
    writeLines(c(
      sprintf("# Phase169 worker %d", worker_id), "",
      sprintf("- Scenario: `%s`", job$scenario_id[[1L]]),
      sprintf("- Structure: `%s`", job$fit_structure[[1L]]),
      sprintf("- Method: `%s`", job$inference_method_id[[1L]]),
      sprintf("- Chain: %d", job$chain_id[[1L]]),
      sprintf("- Seed: %d", job$chain_seed[[1L]]),
      "- Initialization: matched VB1 structured-v profile.",
      "- Storage: compressed coefficient/scale/shape draws; no latent binary object."
    ), readme, useBytes = TRUE)
    paths <- c(
      posterior_draws = app_joint_exqdesn_phase157_write_gzip_csv(draws, file.path(worker_dir, "posterior_draws.csv.gz")),
      chain_summary = app_joint_qvp_write_csv(summary, file.path(worker_dir, "chain_summary.csv")),
      sampler_diagnostics = app_joint_qvp_write_csv(sampler, file.path(worker_dir, "sampler_diagnostics.csv")),
      runtime = app_joint_qvp_write_csv(runtime, file.path(worker_dir, "runtime.csv")),
      provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(worker_dir, "provenance.csv")),
      README = normalizePath(readme, mustWork = TRUE)
    )
    manifest <- app_joint_exqdesn_write_manifest(paths, worker_dir)
    if (!app_joint_exqdesn_phase169_worker_complete(worker_dir)) {
      stop("Phase169 worker manifest failed after publication.", call. = FALSE)
    }
    list(
      worker_id = worker_id,
      status = "completed",
      worker_dir = worker_dir,
      paths = c(paths, artifact_manifest = manifest$manifest_path)
    )
  }, error = function(e) {
    receipt <- data.frame(
      worker_id = worker_id,
      mcmc_case_id = job$mcmc_case_id[[1L]],
      inference_method_id = job$inference_method_id[[1L]],
      chain_id = job$chain_id[[1L]],
      message = conditionMessage(e),
      timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      stringsAsFactors = FALSE
    )
    app_joint_qvp_write_csv(receipt, file.path(worker_dir, "failure_receipt.csv"))
    if (!is.null(failure_dir) && nzchar(failure_dir)) {
      app_ensure_dir(failure_dir)
      app_joint_qvp_write_csv(receipt, file.path(failure_dir, sprintf("worker_%03d.csv", worker_id)))
    }
    stop(e)
  })
}

app_joint_exqdesn_phase169_read_fit <- function(worker_dir, tau, seed, chain_id) {
  app_joint_exqdesn_phase157_read_fit(worker_dir, tau, seed, chain_id)
}

app_joint_exqdesn_phase169_health <- function(
  freeze_dir = app_joint_exqdesn_phase167_169_dirs()$phase169_freeze
) {
  freeze <- app_joint_exqdesn_phase169_load_freeze(freeze_dir)
  complete <- vapply(freeze$plan$worker_output_dir, app_joint_exqdesn_phase169_worker_complete, logical(1L))
  data.frame(
    stage = "Phase169 exact-MCMC method selection",
    planned_workers = nrow(freeze$plan),
    complete_verified = sum(complete),
    remaining_workers = sum(!complete),
    percent_complete = 100 * mean(complete),
    complete_M0 = sum(complete & freeze$plan$inference_method_id == "M0_v_collapsed_support_logit"),
    complete_M1b = sum(complete & freeze$plan$inference_method_id == "M1b_u_collapsed_support_logit"),
    complete_M1 = sum(complete & freeze$plan$inference_method_id == "M1_u_collapsed_p_logit"),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase169_transformed_draw <- function(fit, tau, parameter, k) {
  gamma <- fit$gamma_draws[, k]
  sigma <- fit$sigma_draws[, k]
  if (parameter == "gamma") return(gamma)
  if (parameter == "sigma") return(sigma)
  constants <- lapply(gamma, function(g) app_joint_exqdesn_constants(tau[[k]], g))
  if (parameter == "p_gamma") {
    return(vapply(constants, function(x) x$p_gamma[[1L]], numeric(1L)))
  }
  if (parameter == "actual_sd") {
    return(sigma * vapply(constants, function(x) x$sd_factor[[1L]], numeric(1L)))
  }
  if (parameter == "sigma_lambda") {
    return(sigma * vapply(constants, function(x) x$lambda[[1L]], numeric(1L)))
  }
  stop("Unknown transformed Phase169 parameter.", call. = FALSE)
}

app_joint_exqdesn_phase169_diagnostic_rows <- function(fits, fixture, meta) {
  parameters <- c("gamma", "sigma", "p_gamma", "actual_sd", "sigma_lambda")
  rows <- list()
  for (parameter in parameters) {
    for (k in seq_along(fixture$tau)) {
      mat <- do.call(cbind, lapply(fits, function(fit) {
        app_joint_exqdesn_phase169_transformed_draw(fit, fixture$tau, parameter, k)
      }))
      modern <- app_joint_exqdesn_modern_diagnostics(mat)
      rows[[length(rows) + 1L]] <- cbind(
        meta,
        data.frame(
          parameter = parameter,
          quantile_index = k,
          tau = fixture$tau[[k]],
          posterior_mean = mean(mat),
          posterior_sd = stats::sd(as.numeric(mat)),
          q05 = as.numeric(stats::quantile(mat, 0.05, names = FALSE, type = 8)),
          median = stats::median(mat),
          q95 = as.numeric(stats::quantile(mat, 0.95, names = FALSE, type = 8)),
          stringsAsFactors = FALSE
        ),
        modern,
        stringsAsFactors = FALSE
      )
    }
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase169_group_stability <- function(fits, fixture, artifacts, meta) {
  groups <- list(first_four = fits[1:4], last_four = fits[5:8])
  app_joint_qdesn_bind_rows(lapply(names(groups), function(group_id) {
    pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(
      groups[[group_id]], fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau
    )
    fit_score <- app_joint_qdesn_phase122_score_qhat(
      meta, fixture, app_joint_qdesn_predict_fit(pooled, fixture$Z, fixture$tau),
      "qhat", paste0("phase169_", group_id, "_fit")
    )
    forecast_score <- app_joint_qdesn_phase122_forecast_scores(
      meta, artifacts, fixture$scenario_id, fixture, pooled,
      "qhat", paste0("phase169_", group_id, "_forecast")
    )
    data.frame(
      meta,
      chain_group = group_id,
      fit_truth_mae = mean(fit_score$scored$truth_abs_error),
      forecast_truth_mae = mean(forecast_score$scored$truth_abs_error),
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase169_finalize <- function(
  freeze_dir = app_joint_exqdesn_phase167_169_dirs()$phase169_freeze,
  out_dir = app_joint_exqdesn_phase167_169_dirs()$phase169
) {
  freeze <- app_joint_exqdesn_phase169_load_freeze(freeze_dir)
  health <- app_joint_exqdesn_phase169_health(freeze_dir)
  if (health$remaining_workers[[1L]] > 0L) {
    stop("Phase169 cannot finalize with incomplete workers.", call. = FALSE)
  }
  out_dir <- normalizePath(out_dir, mustWork = TRUE)
  cells <- split(freeze$plan, interaction(
    freeze$plan$mcmc_case_id, freeze$plan$inference_method_id,
    drop = TRUE, lex.order = TRUE
  ))
  results <- lapply(cells, function(jobs) {
    jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
    if (nrow(jobs) != 8L) stop("Phase169 finalized cell does not contain eight chains.", call. = FALSE)
    dirs <- app_joint_exqdesn_phase167_169_dirs()
    artifacts <- app_joint_exqdesn_load_selected_fixture_artifacts(jobs$scenario_id[[1L]], dirs)
    fixture <- app_joint_qdesn_scenario_fixture(artifacts, jobs$scenario_id[[1L]], role = "fit")
    fits <- lapply(seq_len(nrow(jobs)), function(ii) {
      app_joint_exqdesn_phase169_read_fit(
        jobs$worker_output_dir[[ii]], fixture$tau,
        jobs$chain_seed[[ii]], jobs$chain_id[[ii]]
      )
    })
    pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(
      fits, fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau
    )
    meta <- data.frame(
      scenario_id = jobs$scenario_id[[1L]],
      base_scenario_id = jobs$base_scenario_id[[1L]],
      fit_structure = jobs$fit_structure[[1L]],
      inference_method_id = jobs$inference_method_id[[1L]],
      stringsAsFactors = FALSE
    )
    fit_score <- app_joint_qdesn_phase122_score_qhat(
      meta, fixture, app_joint_qdesn_predict_fit(pooled, fixture$Z, fixture$tau),
      "qhat", "phase169_pooled_fit"
    )
    forecast_score <- app_joint_qdesn_phase122_forecast_scores(
      meta, artifacts, fixture$scenario_id, fixture, pooled,
      "qhat", "phase169_pooled_forecast"
    )
    diagnostics <- app_joint_exqdesn_phase169_diagnostic_rows(fits, fixture, meta)
    stability <- app_joint_exqdesn_phase169_group_stability(fits, fixture, artifacts, meta)
    chain_summary <- app_joint_qdesn_bind_rows(lapply(jobs$worker_output_dir, function(dir) {
      app_read_csv(file.path(dir, "chain_summary.csv"))
    }))
    summary <- cbind(meta, data.frame(
      n_chains = length(fits),
      n_keep_total = nrow(pooled$beta_draws),
      fit_truth_mae = mean(fit_score$scored$truth_abs_error),
      forecast_truth_mae = mean(forecast_score$scored$truth_abs_error),
      fit_check_loss_mean = mean(fit_score$scored$check_loss),
      forecast_check_loss_mean = mean(forecast_score$scored$check_loss),
      fit_crps_grid_mean = app_joint_qdesn_crps_grid_summary(fit_score$scored)$crps_grid_mean[[1L]],
      forecast_crps_grid_mean = app_joint_qdesn_crps_grid_summary(forecast_score$scored)$crps_grid_mean[[1L]],
      raw_crossing_pairs = sum(fit_score$contract_info$raw_crossing$n_crossing_pairs) +
        sum(forecast_score$raw_crossing$n_crossing_pairs),
      contract_crossing_pairs = sum(fit_score$contract_info$contract_crossing$n_crossing_pairs) +
        sum(forecast_score$contract_crossing$n_crossing_pairs),
      max_rank_rhat = max(diagnostics$rank_rhat, na.rm = TRUE),
      max_folded_rhat = max(diagnostics$folded_rhat, na.rm = TRUE),
      min_bulk_ess = min(diagnostics$bulk_ess, na.rm = TRUE),
      min_tail_ess = min(diagnostics$tail_ess, na.rm = TRUE),
      runtime_seconds_total = sum(chain_summary$elapsed_seconds),
      all_draws_finite = all(chain_summary$draws_all_finite),
      stringsAsFactors = FALSE
    ))
    list(summary = summary, diagnostics = diagnostics, stability = stability, chain_summary = chain_summary)
  })
  bind <- function(name) app_joint_qdesn_bind_rows(lapply(results, `[[`, name))
  summary <- bind("summary")
  diagnostics <- bind("diagnostics")
  stability <- bind("stability")
  chains <- bind("chain_summary")
  spread <- aggregate(
    cbind(fit_truth_mae, forecast_truth_mae) ~ scenario_id + fit_structure + inference_method_id,
    stability,
    function(x) diff(range(x))
  )
  names(spread)[4:5] <- c("chain_group_fit_mae_range", "chain_group_forecast_mae_range")
  assessment <- merge(
    summary, spread,
    by = c("scenario_id", "fit_structure", "inference_method_id"),
    all.x = TRUE, sort = FALSE
  )
  assessment$implementation_status <- ifelse(
    assessment$all_draws_finite & assessment$contract_crossing_pairs == 0L,
    "pass", "fail"
  )
  assessment$mixing_status <- ifelse(
    assessment$max_rank_rhat <= 1.05 & assessment$max_folded_rhat <= 1.05 &
      assessment$min_bulk_ess >= 400 & assessment$min_tail_ess >= 200,
    "pass", "review"
  )
  assessment$functional_stability_tolerance <- pmax(0.0025, 0.02 * assessment$forecast_truth_mae)
  assessment$functional_stability_status <- ifelse(
    assessment$chain_group_forecast_mae_range <= assessment$functional_stability_tolerance,
    "pass", "review"
  )
  baseline <- summary[summary$inference_method_id == "M0_v_collapsed_support_logit", ]
  comparison <- merge(
    summary, baseline[, c(
      "scenario_id", "fit_structure", "fit_truth_mae", "forecast_truth_mae",
      "fit_crps_grid_mean", "forecast_crps_grid_mean", "runtime_seconds_total",
      "max_rank_rhat", "min_bulk_ess"
    )],
    by = c("scenario_id", "fit_structure"), suffixes = c("", "_M0"),
    all.x = TRUE, sort = FALSE
  )
  for (metric in c(
    "fit_truth_mae", "forecast_truth_mae", "fit_crps_grid_mean",
    "forecast_crps_grid_mean", "runtime_seconds_total", "max_rank_rhat",
    "min_bulk_ess"
  )) {
    comparison[[paste0(metric, "_delta_vs_M0")]] <-
      comparison[[metric]] - comparison[[paste0(metric, "_M0")]]
  }
  overall <- data.frame(
    gate_status = if (any(assessment$implementation_status == "fail")) "fail" else if (
      any(assessment$mixing_status == "review") ||
        any(assessment$functional_stability_status == "review")
    ) "review" else "pass",
    completed_workers = health$complete_verified[[1L]],
    expected_workers = health$planned_workers[[1L]],
    implementation_failures = sum(assessment$implementation_status == "fail"),
    mixing_review_cells = sum(assessment$mixing_status == "review"),
    functional_review_cells = sum(assessment$functional_stability_status == "review"),
    contract_crossing_pairs = sum(assessment$contract_crossing_pairs),
    recommendation = "audit_target_invariance_then_freeze_one_exact_method",
    stringsAsFactors = FALSE
  )
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Phase169 exact-MCMC method selection", "",
    "This artifact compares M0, M1b, and M1 at equal eight-chain budgets.",
    "It is method-development evidence and does not alter article assets.",
    "Functional quantile stability is primary; scalar mixing diagnostics are supporting evidence."
  ), readme, useBytes = TRUE)
  paths <- c(
    case_method_summary = app_joint_qvp_write_csv(summary, file.path(out_dir, "phase169_case_method_summary.csv")),
    parameter_diagnostics = app_joint_qvp_write_csv(diagnostics, file.path(out_dir, "phase169_parameter_diagnostics.csv")),
    chain_group_stability = app_joint_qvp_write_csv(stability, file.path(out_dir, "phase169_chain_group_stability.csv")),
    chain_summary = app_joint_qvp_write_csv(chains, file.path(out_dir, "phase169_chain_summary.csv")),
    method_comparison = app_joint_qvp_write_csv(comparison, file.path(out_dir, "phase169_method_comparison.csv")),
    cell_assessment = app_joint_qvp_write_csv(assessment, file.path(out_dir, "phase169_cell_assessment.csv")),
    phase169_assessment = app_joint_qvp_write_csv(overall, file.path(out_dir, "phase169_assessment.csv")),
    health_summary = app_joint_qvp_write_csv(health, file.path(out_dir, "phase169_health_summary.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    README = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_write_manifest(paths, out_dir)
  list(
    assessment = overall,
    cell_assessment = assessment,
    comparison = comparison,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}
