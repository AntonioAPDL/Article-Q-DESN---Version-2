# Phase169 failed-run closeout and corrected resumable campaign.

app_joint_exqdesn_phase169r_dirs <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root()
) {
  base <- app_joint_exqdesn_phase167_169_dirs(cache_root)
  c(base, list(
    phase169r_closeout = file.path(
      cache_root, "joint_exqdesn_phase169_failed_postfit_closeout_20260807"
    ),
    phase169r_freeze = file.path(
      cache_root, "joint_exqdesn_phase169r_corrected_mcmc_method_selection_freeze_20260807"
    ),
    phase169r = file.path(
      cache_root, "joint_exqdesn_phase169r_corrected_mcmc_method_selection_20260807"
    ),
    phase169r_orchestration = file.path(
      cache_root, "joint_exqdesn_phase169r_corrected_mcmc_method_selection_20260807_orchestration"
    )
  ))
}

app_joint_exqdesn_phase169r_source_snapshot <- function() {
  relative_path <- c(
    "application/config/joint_exqdesn_inference_method_registry_v1.csv",
    "application/R/joint_exqdesn_exact_structured_inference.R",
    "application/R/joint_exqdesn_inference_dispatch.R",
    "application/R/joint_exqdesn_phase167_169_mcmc_method_selection.R",
    "application/R/joint_exqdesn_phase169r_recovery.R",
    "application/scripts/226_prepare_joint_exqdesn_phase169r_recovery.R",
    "application/scripts/227_run_joint_exqdesn_phase169r_chain.R",
    "application/scripts/228_finalize_joint_exqdesn_phase169r_mcmc_method_selection.R",
    "application/scripts/229_check_joint_exqdesn_phase169r_mcmc_method_selection.R",
    "application/scripts/230_launch_joint_exqdesn_phase169r_mcmc_method_selection.sh",
    "application/tests/test_joint_exqdesn_phase169r_recovery.R",
    "docs/implementation_notes/joint_exqdesn_phase169r_recovery_20260807.md"
  )
  paths <- app_path(relative_path)
  if (any(!file.exists(paths))) {
    stop("Phase169R source snapshot is incomplete.", call. = FALSE)
  }
  data.frame(
    relative_path = relative_path,
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase169r_active_worker_ids <- function() {
  commands <- tryCatch(
    system("ps -eo args=", intern = TRUE),
    error = function(e) character()
  )
  commands <- commands[grepl(
    "222_run_joint_exqdesn_phase169_chain[.]R|227_run_joint_exqdesn_phase169r_chain[.]R",
    commands
  )]
  ids <- suppressWarnings(as.integer(sub(".*--worker-id ([0-9]+).*", "\\1", commands)))
  sort(unique(ids[is.finite(ids)]))
}

app_joint_exqdesn_phase169r_failure_receipts <- function(dirs) {
  failure_dir <- file.path(dirs$phase169_orchestration, "failures")
  paths <- list.files(
    failure_dir, pattern = "^worker_[0-9]+[.]csv$", full.names = TRUE
  )
  if (!length(paths)) return(data.frame())
  rows <- lapply(paths, function(path) {
    row <- app_read_csv(path)
    row$receipt_path <- normalizePath(path, mustWork = TRUE)
    row$receipt_sha256 <- app_sha256_file(path)
    row
  })
  out <- app_joint_qdesn_bind_rows(rows)
  out[order(out$worker_id), , drop = FALSE]
}

app_joint_exqdesn_phase169r_evidence_inventory <- function(dirs) {
  roots <- c(
    file.path(dirs$phase169_orchestration, "failures"),
    file.path(dirs$phase169_orchestration, "logs"),
    file.path(dirs$phase169_orchestration, "exits")
  )
  paths <- unlist(lapply(roots, function(root) {
    if (!dir.exists(root)) return(character())
    list.files(root, full.names = TRUE, recursive = TRUE)
  }), use.names = FALSE)
  paths <- paths[file.exists(paths) & !dir.exists(paths)]
  if (!length(paths)) return(data.frame())
  cache_root <- normalizePath(dirs$cache_root, mustWork = TRUE)
  prefix <- paste0(cache_root, .Platform$file.sep)
  data.frame(
    relative_path = ifelse(
      startsWith(normalizePath(paths, mustWork = TRUE), prefix),
      substring(normalizePath(paths, mustWork = TRUE), nchar(prefix) + 1L),
      basename(paths)
    ),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase169r_worker_state <- function(freeze, receipts) {
  failed <- if (nrow(receipts)) as.integer(receipts$worker_id) else integer()
  complete <- vapply(
    freeze$plan$worker_output_dir,
    app_joint_exqdesn_phase169_worker_complete,
    logical(1L)
  )
  materialized <- dir.exists(freeze$plan$worker_output_dir)
  state <- ifelse(
    complete, "complete",
    ifelse(
      freeze$plan$worker_id %in% failed, "failed_postfit_scoring",
      ifelse(materialized, "interrupted_after_stop", "not_started")
    )
  )
  data.frame(
    freeze$plan[, c(
      "worker_id", "mcmc_case_id", "scenario_id", "base_scenario_id",
      "fit_structure", "inference_method_id", "chain_id", "chain_seed"
    ), drop = FALSE],
    terminal_state = state,
    recoverable_posterior = complete,
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase169r_closeout_failed_campaign <- function(
  dirs = app_joint_exqdesn_phase169r_dirs()
) {
  app_ensure_dir(dirs$phase169r_closeout)
  freeze <- app_joint_exqdesn_phase169_load_freeze(dirs$phase169_freeze)
  receipts <- app_joint_exqdesn_phase169r_failure_receipts(dirs)
  inventory <- app_joint_exqdesn_phase169r_evidence_inventory(dirs)
  worker_state <- app_joint_exqdesn_phase169r_worker_state(freeze, receipts)
  messages <- if (nrow(receipts)) {
    as.data.frame(table(receipts$message), stringsAsFactors = FALSE)
  } else {
    data.frame(Var1 = character(), Freq = integer(), stringsAsFactors = FALSE)
  }
  names(messages) <- c("failure_message", "n_workers")
  root_cause <- data.frame(
    defect_id = "phase169_missing_score_metadata",
    failure_stage = "postfit_preserialization_crps_aggregation",
    missing_columns = "display_label;likelihood",
    observed_error = "undefined columns selected",
    sampler_target_impacted = FALSE,
    posterior_artifacts_recoverable = FALSE,
    remediation = paste(
      "validate complete score metadata before sampling; checkpoint posterior",
      "draws before score aggregation; relaunch from a corrected immutable freeze"
    ),
    stringsAsFactors = FALSE
  )
  counts <- table(factor(
    worker_state$terminal_state,
    levels = c(
      "complete", "failed_postfit_scoring", "interrupted_after_stop", "not_started"
    )
  ))
  active_ids <- app_joint_exqdesn_phase169r_active_worker_ids()
  assessment <- data.frame(
    closeout_status = if (!length(active_ids) &&
      counts[["failed_postfit_scoring"]] > 0L) "closed_failed" else "review",
    planned_workers = nrow(worker_state),
    complete_workers = unname(counts[["complete"]]),
    failed_postfit_workers = unname(counts[["failed_postfit_scoring"]]),
    interrupted_workers = unname(counts[["interrupted_after_stop"]]),
    not_started_workers = unname(counts[["not_started"]]),
    active_phase169_worker_processes = length(active_ids),
    unique_failure_messages = nrow(messages),
    recoverable_posterior_workers = sum(worker_state$recoverable_posterior),
    recommendation = "prepare_phase169r_corrected_relaunch",
    stringsAsFactors = FALSE
  )
  readme <- file.path(dirs$phase169r_closeout, "README.md")
  writeLines(c(
    "# Phase169 failed-campaign closeout", "",
    "The original Phase169 campaign was stopped after a deterministic post-fit scoring failure.",
    "All observed failures had one signature: required score metadata columns were absent.",
    "No completed posterior draw artifact was published before the failure, so no chain is recoverable.",
    "The sampler methods and scientific design are not rejected by this closeout.",
    "The original freeze, logs, receipts, and partial worker directories remain unchanged."
  ), readme, useBytes = TRUE)
  paths <- c(
    closeout_assessment = app_joint_qvp_write_csv(
      assessment, file.path(dirs$phase169r_closeout, "closeout_assessment.csv")
    ),
    worker_state = app_joint_qvp_write_csv(
      worker_state, file.path(dirs$phase169r_closeout, "worker_state.csv")
    ),
    failure_receipts = app_joint_qvp_write_csv(
      receipts, file.path(dirs$phase169r_closeout, "failure_receipts.csv")
    ),
    failure_message_summary = app_joint_qvp_write_csv(
      messages, file.path(dirs$phase169r_closeout, "failure_message_summary.csv")
    ),
    root_cause = app_joint_qvp_write_csv(
      root_cause, file.path(dirs$phase169r_closeout, "root_cause.csv")
    ),
    evidence_inventory = app_joint_qvp_write_csv(
      inventory, file.path(dirs$phase169r_closeout, "evidence_inventory.csv")
    ),
    original_freeze_verification = app_joint_qvp_write_csv(
      freeze$verification,
      file.path(dirs$phase169r_closeout, "original_freeze_verification.csv")
    ),
    provenance = app_joint_qvp_write_csv(
      app_joint_qvp_provenance_rows(),
      file.path(dirs$phase169r_closeout, "provenance.csv")
    ),
    README = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_write_manifest(paths, dirs$phase169r_closeout)
  list(
    assessment = assessment,
    worker_state = worker_state,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}

app_joint_exqdesn_phase169r_corrected_plan <- function(plan, out_dir) {
  corrected <- plan
  corrected$original_worker_output_dir <- corrected$worker_output_dir
  corrected$worker_output_dir <- file.path(
    out_dir, "candidates", corrected$mcmc_case_id,
    corrected$inference_method_id,
    sprintf("chain_%02d", corrected$chain_id)
  )
  corrected$repair_id <- "phase169r_score_contract_checkpoint"
  preserved <- setdiff(names(plan), "worker_output_dir")
  if (!identical(plan[, preserved, drop = FALSE], corrected[, preserved, drop = FALSE]) ||
      anyDuplicated(corrected$worker_output_dir)) {
    stop("Phase169R changed a frozen scientific chain-plan field.", call. = FALSE)
  }
  corrected
}

app_joint_exqdesn_phase169r_preflight_one <- function(
  job,
  freeze,
  dirs = app_joint_exqdesn_phase169r_dirs()
) {
  tryCatch({
    artifacts <- app_joint_exqdesn_load_selected_fixture_artifacts(
      job$scenario_id[[1L]], dirs
    )
    fixture <- app_joint_qdesn_scenario_fixture(
      artifacts, job$scenario_id[[1L]], role = "fit"
    )
    init <- app_joint_exqdesn_phase169_init_from_rows(
      freeze$init, job$mcmc_case_id[[1L]], job$fit_structure[[1L]],
      length(fixture$tau), ncol(fixture$Z)
    )
    meta <- app_joint_exqdesn_phase169_score_meta(job)
    app_joint_exqdesn_phase169_validate_score_meta(meta)
    fit_score <- app_joint_qdesn_phase122_score_qhat(
      meta, fixture,
      app_joint_qdesn_predict_fit(init, fixture$Z, fixture$tau),
      "qhat", "phase169r_preflight_fit"
    )
    forecast_score <- app_joint_qdesn_phase122_forecast_scores(
      meta, artifacts, job$scenario_id[[1L]], fixture, init,
      "qhat", "phase169r_preflight_forecast"
    )
    fit_crps <- app_joint_qdesn_crps_grid_summary(fit_score$scored)
    forecast_crps <- app_joint_qdesn_crps_grid_summary(forecast_score$scored)
    finite <- all(is.finite(c(
      fit_score$scored$check_loss,
      forecast_score$scored$check_loss,
      fit_crps$crps_grid_mean,
      forecast_crps$crps_grid_mean
    )))
    contract_crossings <- sum(
      fit_score$contract_info$contract_crossing$n_crossing_pairs
    ) + sum(forecast_score$contract_crossing$n_crossing_pairs)
    data.frame(
      mcmc_case_id = job$mcmc_case_id[[1L]],
      scenario_id = job$scenario_id[[1L]],
      fit_structure = job$fit_structure[[1L]],
      inference_method_id = job$inference_method_id[[1L]],
      score_metadata_status = "pass",
      finite_scores = finite,
      fit_crps_grid_mean = fit_crps$crps_grid_mean[[1L]],
      forecast_crps_grid_mean = forecast_crps$crps_grid_mean[[1L]],
      contract_crossing_pairs = contract_crossings,
      preflight_status = if (finite && contract_crossings == 0L) "pass" else "fail",
      message = "",
      stringsAsFactors = FALSE
    )
  }, error = function(e) data.frame(
    mcmc_case_id = job$mcmc_case_id[[1L]],
    scenario_id = job$scenario_id[[1L]],
    fit_structure = job$fit_structure[[1L]],
    inference_method_id = job$inference_method_id[[1L]],
    score_metadata_status = "fail",
    finite_scores = FALSE,
    fit_crps_grid_mean = NA_real_,
    forecast_crps_grid_mean = NA_real_,
    contract_crossing_pairs = NA_integer_,
    preflight_status = "fail",
    message = conditionMessage(e),
    stringsAsFactors = FALSE
  ))
}

app_joint_exqdesn_phase169r_prepare <- function(
  dirs = app_joint_exqdesn_phase169r_dirs()
) {
  closeout <- app_joint_exqdesn_phase169r_closeout_failed_campaign(dirs)
  if (closeout$assessment$closeout_status[[1L]] != "closed_failed") {
    stop("The original Phase169 campaign is not safely closed.", call. = FALSE)
  }
  original <- app_joint_exqdesn_phase169_load_freeze(dirs$phase169_freeze)
  closeout_verification <- app_joint_exqdesn_verify_manifest(
    dirs$phase169r_closeout, "phase169_failed_closeout"
  )
  if (any(closeout_verification$status != "pass")) {
    stop("Phase169 failed-closeout manifest verification failed.", call. = FALSE)
  }
  app_ensure_dir(dirs$phase169r_freeze)
  app_ensure_dir(dirs$phase169r)
  plan <- app_joint_exqdesn_phase169r_corrected_plan(original$plan, dirs$phase169r)
  cells <- unique(plan[, c(
    "mcmc_case_id", "scenario_id", "base_scenario_id", "fit_structure",
    "inference_method_id"
  ), drop = FALSE])
  preflight <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(cells)), function(ii) {
    app_joint_exqdesn_phase169r_preflight_one(cells[ii, , drop = FALSE], original, dirs)
  }))
  preserved_cols <- setdiff(names(original$plan), "worker_output_dir")
  invariance <- data.frame(
    check_id = c(
      "plan_rows", "scientific_columns", "chain_seeds", "initialization_rows",
      "start_rows", "preflight_cells", "preflight_status", "old_workers_stopped"
    ),
    expected = c(
      "240", "identical", "identical", as.character(nrow(original$init)),
      as.character(nrow(original$starts)), "30", "all_pass", "0"
    ),
    observed = c(
      as.character(nrow(plan)),
      if (identical(
        original$plan[, preserved_cols, drop = FALSE],
        plan[, preserved_cols, drop = FALSE]
      )) "identical" else "changed",
      if (identical(original$plan$chain_seed, plan$chain_seed)) "identical" else "changed",
      as.character(nrow(original$init)),
      as.character(nrow(original$starts)),
      as.character(nrow(preflight)),
      if (all(preflight$preflight_status == "pass")) "all_pass" else "failure",
      as.character(length(app_joint_exqdesn_phase169r_active_worker_ids()))
    ),
    stringsAsFactors = FALSE
  )
  invariance$status <- ifelse(invariance$expected == invariance$observed, "pass", "fail")
  config <- original$config
  config$phase_id <- "phase169r_corrected_mcmc_method_selection"
  config$output_dir <- dirs$phase169r
  config$repair_of_freeze <- dirs$phase169_freeze
  config$repair_closeout <- dirs$phase169r_closeout
  config$score_contract_preflight <- TRUE
  config$postfit_prescore_checkpoint <- TRUE
  config$scientific_design_changed <- FALSE
  readiness <- data.frame(
    gate_status = if (
      all(invariance$status == "pass") &&
        all(preflight$preflight_status == "pass") &&
        all(original$verification$status == "pass") &&
        all(closeout_verification$status == "pass")
    ) "pass" else "fail",
    planned_workers = nrow(plan),
    preserved_chain_seeds = identical(original$plan$chain_seed, plan$chain_seed),
    preflight_cells = nrow(preflight),
    preflight_failures = sum(preflight$preflight_status != "pass"),
    source_hash_failures = sum(original$verification$status != "pass") +
      sum(closeout_verification$status != "pass"),
    active_old_workers = length(app_joint_exqdesn_phase169r_active_worker_ids()),
    recommendation = "launch_phase169r_corrected_full_campaign",
    stringsAsFactors = FALSE
  )
  if (readiness$gate_status[[1L]] != "pass") {
    stop("Phase169R readiness gate failed.", call. = FALSE)
  }
  readme <- file.path(dirs$phase169r_freeze, "README.md")
  writeLines(c(
    "# Phase169R corrected exact-MCMC freeze", "",
    "This freeze repairs only the Phase169 score/publication contract.",
    "All scenario, structure, method, control, initialization, start, iteration, and seed fields are preserved.",
    "Every scenario/structure/method cell passed fit and forecast score-schema preflight.",
    "Posterior draws are hash-checkpointed before score aggregation and can be resumed without refitting.",
    "The original failed campaign remains preserved in a separate closeout artifact."
  ), readme, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(
      config, file.path(dirs$phase169r_freeze, "run_config.csv")
    ),
    selected_case_controls = app_joint_qvp_write_csv(
      original$controls, file.path(dirs$phase169r_freeze, "selected_case_controls.csv")
    ),
    vb_initialization = app_joint_qvp_write_csv(
      original$init, file.path(dirs$phase169r_freeze, "vb_initialization.csv")
    ),
    chain_start_values = app_joint_qvp_write_csv(
      original$starts, file.path(dirs$phase169r_freeze, "chain_start_values.csv")
    ),
    chain_plan = app_joint_qvp_write_csv(
      plan, file.path(dirs$phase169r_freeze, "chain_plan.csv")
    ),
    scoring_preflight = app_joint_qvp_write_csv(
      preflight, file.path(dirs$phase169r_freeze, "scoring_preflight.csv")
    ),
    design_invariance_audit = app_joint_qvp_write_csv(
      invariance, file.path(dirs$phase169r_freeze, "design_invariance_audit.csv")
    ),
    original_freeze_verification = app_joint_qvp_write_csv(
      original$verification,
      file.path(dirs$phase169r_freeze, "original_freeze_verification.csv")
    ),
    closeout_manifest_verification = app_joint_qvp_write_csv(
      closeout_verification,
      file.path(dirs$phase169r_freeze, "closeout_manifest_verification.csv")
    ),
    source_code_snapshot = app_joint_qvp_write_csv(
      app_joint_exqdesn_phase169r_source_snapshot(),
      file.path(dirs$phase169r_freeze, "source_code_snapshot.csv")
    ),
    readiness_assessment = app_joint_qvp_write_csv(
      readiness, file.path(dirs$phase169r_freeze, "readiness_assessment.csv")
    ),
    provenance = app_joint_qvp_write_csv(
      app_joint_qvp_provenance_rows(),
      file.path(dirs$phase169r_freeze, "provenance.csv")
    ),
    README = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_write_manifest(paths, dirs$phase169r_freeze)
  list(
    dirs = dirs,
    closeout = closeout,
    readiness = readiness,
    preflight = preflight,
    invariance = invariance,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}
