# Phase 108 VB-initialized MCMC readiness for the joint QDESN simulation study.

app_joint_qdesn_default_mcmc_readiness_dir <- function() {
  app_path("application/cache/joint_qdesn_mcmc_readiness_phase108_20260707")
}

app_joint_qdesn_default_phase107_dir <- function() {
  app_path("application/cache/joint_qdesn_selected_vb_freeze_phase107_20260707")
}

app_joint_qdesn_phase108_manifest_verify <- function(dir, artifact_label = "artifact") {
  dir <- normalizePath(dir, mustWork = TRUE)
  manifest_path <- file.path(dir, "artifact_manifest.csv")
  if (!file.exists(manifest_path)) {
    return(data.frame(
      artifact_label = artifact_label,
      label = "artifact_manifest",
      relative_path = "artifact_manifest.csv",
      path = normalizePath(manifest_path, mustWork = FALSE),
      exists = FALSE,
      declared_size_bytes = NA_real_,
      actual_size_bytes = NA_real_,
      declared_sha256 = NA_character_,
      actual_sha256 = NA_character_,
      status = "fail",
      stringsAsFactors = FALSE
    ))
  }
  manifest <- app_read_csv(manifest_path)
  app_check_required_columns(manifest, c("label", "relative_path", "size_bytes", "sha256"), artifact_label)
  app_joint_qdesn_bind_rows(lapply(seq_len(nrow(manifest)), function(ii) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    exists <- file.exists(path)
    actual_sha <- if (exists) app_sha256_file(path) else NA_character_
    actual_size <- if (exists) as.numeric(file.info(path)$size) else NA_real_
    data.frame(
      artifact_label = artifact_label,
      label = manifest$label[[ii]],
      relative_path = manifest$relative_path[[ii]],
      path = normalizePath(path, mustWork = FALSE),
      exists = exists,
      declared_size_bytes = as.numeric(manifest$size_bytes[[ii]]),
      actual_size_bytes = actual_size,
      declared_sha256 = manifest$sha256[[ii]],
      actual_sha256 = actual_sha,
      status = if (exists &&
        identical(tolower(actual_sha), tolower(manifest$sha256[[ii]])) &&
        identical(as.numeric(actual_size), as.numeric(manifest$size_bytes[[ii]]))) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_qdesn_load_phase107_contract <- function(
  phase107_dir = app_joint_qdesn_default_phase107_dir(),
  candidate_id = "rhs_tau0_0p5_alpha0p5"
) {
  phase107_dir <- normalizePath(phase107_dir, mustWork = TRUE)
  registry <- app_read_csv(file.path(phase107_dir, "candidate_registry.csv"))
  selected <- app_read_csv(file.path(phase107_dir, "selected_spec_recommendation.csv"))
  app_check_required_columns(registry, c(
    "candidate_id", "vb_max_iter", "adaptive_vb_max_iter_grid", "vb_tol",
    "rhs_vb_inner", "tau0", "zeta2", "a_sigma", "b_sigma", "alpha_prior_sd",
    "alpha_min_spacing", "review_adjustment_threshold", "max_dense_dim"
  ), "Phase 107 candidate registry")
  app_check_required_columns(selected, c("candidate_id", "selected", "gate_status"), "Phase 107 selected recommendation")
  if (!candidate_id %in% registry$candidate_id) {
    stop(sprintf("Phase 107 candidate '%s' is not present.", candidate_id), call. = FALSE)
  }
  row <- registry[registry$candidate_id == candidate_id, , drop = FALSE]
  sel <- selected[selected$candidate_id == candidate_id, , drop = FALSE]
  if (!nrow(sel) || !isTRUE(as.logical(sel$selected[[1L]]))) {
    stop(sprintf("Phase 107 candidate '%s' is not marked selected.", candidate_id), call. = FALSE)
  }
  top_manifest <- app_joint_qdesn_phase108_manifest_verify(phase107_dir, "phase107_top")
  nested_path <- file.path(phase107_dir, "candidate_manifest_verification.csv")
  nested <- if (file.exists(nested_path)) {
    nested0 <- app_read_csv(nested_path)
    nested0$artifact_label <- "phase107_nested"
    nested0
  } else {
    data.frame(artifact_label = "phase107_nested", status = "fail", stringsAsFactors = FALSE)
  }
  if (any(top_manifest$status != "pass") || any(nested$status != "pass")) {
    stop("Phase 107 artifact verification failed; refusing to initialize MCMC from an unfrozen VB contract.", call. = FALSE)
  }
  list(
    phase107_dir = phase107_dir,
    candidate_registry = row,
    selected_recommendation = sel,
    phase107_top_manifest_verification = top_manifest,
    phase107_nested_manifest_verification = nested,
    vb_controls = app_joint_qdesn_simulation_controls(
      vb_max_iter = as.integer(row$vb_max_iter[[1L]]),
      adaptive_vb_max_iter_grid = app_joint_qdesn_parse_iter_grid(row$adaptive_vb_max_iter_grid[[1L]]),
      vb_tol = as.numeric(row$vb_tol[[1L]]),
      rhs_vb_inner = as.integer(row$rhs_vb_inner[[1L]]),
      tau0 = as.numeric(row$tau0[[1L]]),
      zeta2 = as.numeric(row$zeta2[[1L]]),
      a_sigma = as.numeric(row$a_sigma[[1L]]),
      b_sigma = as.numeric(row$b_sigma[[1L]]),
      alpha_prior_sd = as.numeric(row$alpha_prior_sd[[1L]]),
      alpha_min_spacing = as.numeric(row$alpha_min_spacing[[1L]]),
      review_adjustment_threshold = as.numeric(row$review_adjustment_threshold[[1L]]),
      max_dense_dim = as.integer(row$max_dense_dim[[1L]]),
      n_cores = as.integer(row$n_cores[[1L]] %||% 1L)
    )
  )
}

app_joint_qdesn_mcmc_readiness_controls <- function(
  n_chains = 2L,
  mcmc_n_iter = 80L,
  mcmc_burn = 40L,
  mcmc_thin = 5L,
  mcmc_seed_offset = 3100L,
  chain_seed_stride = 100L,
  sigma_upper_multiplier = 50,
  distance_pass = 5,
  chain_pass = 5,
  n_cores = 1L
) {
  list(
    n_chains = as.integer(n_chains),
    mcmc_n_iter = as.integer(mcmc_n_iter),
    mcmc_burn = as.integer(mcmc_burn),
    mcmc_thin = as.integer(mcmc_thin),
    mcmc_seed_offset = as.integer(mcmc_seed_offset),
    chain_seed_stride = as.integer(chain_seed_stride),
    sigma_upper_multiplier = as.numeric(sigma_upper_multiplier),
    distance_pass = as.numeric(distance_pass),
    chain_pass = as.numeric(chain_pass),
    n_cores = as.integer(n_cores)
  )
}

app_joint_qdesn_phase108_model_meta <- function(fixture, model_id, display_label, inference) {
  data.frame(
    scenario_id = fixture$scenario_id,
    scenario_class = fixture$scenario_meta$scenario_class[[1L]],
    distribution_family = fixture$scenario_meta$distribution_family[[1L]],
    dynamics_class = fixture$scenario_meta$dynamics_class[[1L]],
    model_id = model_id,
    display_label = display_label,
    likelihood = "al",
    fit_structure = "joint",
    inference = inference,
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase108_score_block <- function(meta, fixture, qhat, value_name = "qhat") {
  rows <- app_joint_qdesn_quantile_long_rows(meta, fixture$row_meta, fixture$tau, fixture$y, fixture$true_q, qhat, value_name)
  if (identical(value_name, "qhat")) app_joint_qdesn_quantile_scores(rows, "qhat") else rows
}

app_joint_qdesn_phase108_one_scenario <- function(artifacts, scenario_id, vb_controls, mcmc_controls) {
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
  spec <- app_joint_qdesn_simulation_model_specs()
  spec <- spec[spec$model_id == "joint_qdesn_rhs_vb", , drop = FALSE]
  if (nrow(spec) != 1L) stop("Could not identify JOINT QDESN RHS VB spec.", call. = FALSE)

  vb_meta <- app_joint_qdesn_phase108_model_meta(fixture, "joint_qdesn_rhs_vb", "JOINT QDESN RHS", "VB")
  mcmc_meta <- app_joint_qdesn_phase108_model_meta(fixture, "joint_qdesn_rhs_mcmc", "JOINT QDESN RHS MCMC", "MCMC")

  vb_start <- proc.time()[["elapsed"]]
  vb_fit <- app_joint_qdesn_fit_model_adaptive(fixture, spec, vb_controls)
  vb_elapsed <- proc.time()[["elapsed"]] - vb_start
  vb_raw <- app_joint_qdesn_predict_fit(vb_fit, fixture$Z, fixture$tau)
  vb_contract <- app_joint_qdesn_apply_monotone_contract(vb_raw, fixture$tau)

  sigma_upper <- max(1, mcmc_controls$sigma_upper_multiplier * max(vb_fit$sigma_mean, na.rm = TRUE))
  sigma_bounds <- c(1.0e-8, sigma_upper)
  base_seed <- as.integer(fixture$scenario_meta$seed[[1L]])
  fits <- vector("list", mcmc_controls$n_chains)
  draw_rows <- chain_runtime_rows <- list()
  mcmc_start <- proc.time()[["elapsed"]]
  for (chain_id in seq_len(mcmc_controls$n_chains)) {
    chain_seed <- base_seed + mcmc_controls$mcmc_seed_offset + (chain_id - 1L) * mcmc_controls$chain_seed_stride
    chain_start <- proc.time()[["elapsed"]]
    fits[[chain_id]] <- app_joint_qvp_fit_al_mcmc_tiny(
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      n_iter = mcmc_controls$mcmc_n_iter,
      burn = mcmc_controls$mcmc_burn,
      thin = mcmc_controls$mcmc_thin,
      seed = chain_seed,
      kappa = 1,
      tau0 = vb_controls$tau0,
      zeta2 = vb_controls$zeta2,
      a_sigma = vb_controls$a_sigma,
      b_sigma = vb_controls$b_sigma,
      alpha_prior_mean = "empirical_quantile",
      alpha_prior_sd = vb_controls$alpha_prior_sd,
      alpha_min_spacing = vb_controls$alpha_min_spacing,
      max_dense_dim = vb_controls$max_dense_dim,
      sigma_bounds = sigma_bounds,
      init = vb_fit
    )
    chain_elapsed <- proc.time()[["elapsed"]] - chain_start
    draw_rows[[chain_id]] <- cbind(
      app_joint_qdesn_phase108_model_meta(fixture, "joint_qdesn_rhs_mcmc", "JOINT QDESN RHS MCMC", "MCMC"),
      data.frame(chain_id = chain_id, chain_seed = chain_seed, stringsAsFactors = FALSE),
      app_joint_qvp_mcmc_draw_summary(fits[[chain_id]], scenario_id, "joint_qdesn_phase108", scenario_id, sigma_bounds = sigma_bounds),
      stringsAsFactors = FALSE
    )
    chain_runtime_rows[[chain_id]] <- cbind(
      mcmc_meta,
      data.frame(
        runtime_component = "mcmc_chain",
        chain_id = chain_id,
        chain_seed = chain_seed,
        elapsed_seconds = chain_elapsed,
        sec_per_iter = chain_elapsed / max(1L, mcmc_controls$mcmc_n_iter),
        stringsAsFactors = FALSE
      )
    )
  }
  pooled <- app_joint_qvp_pool_mcmc_chains(fits, fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau)
  mcmc_elapsed <- proc.time()[["elapsed"]] - mcmc_start
  mcmc_contract <- app_joint_qdesn_apply_monotone_contract(pooled$qhat_mean, fixture$tau)
  distance <- cbind(
    mcmc_meta,
    app_joint_qvp_vb_mcmc_distance_summary(vb_fit, pooled, scenario_id, "joint_qdesn_phase108", scenario_id, length(fixture$y), ncol(fixture$Z), length(fixture$tau)),
    stringsAsFactors = FALSE
  )
  chain_distance <- cbind(
    mcmc_meta,
    app_joint_qvp_chain_to_pooled_summary(fits, pooled, fixture$Z, scenario_id, "joint_qdesn_phase108", scenario_id, length(fixture$y), ncol(fixture$Z), length(fixture$tau)),
    stringsAsFactors = FALSE
  )

  vb_scored <- app_joint_qdesn_phase108_score_block(vb_meta, fixture, vb_contract$qhat_contract, "qhat")
  mcmc_scored <- app_joint_qdesn_phase108_score_block(mcmc_meta, fixture, mcmc_contract$qhat_contract, "qhat")
  scored <- rbind(vb_scored, mcmc_scored)
  vb_raw_rows <- app_joint_qdesn_phase108_score_block(vb_meta, fixture, vb_raw, "qhat_raw")
  mcmc_raw_rows <- app_joint_qdesn_phase108_score_block(mcmc_meta, fixture, pooled$qhat_mean, "qhat_raw")
  adjustment <- rbind(
    app_joint_qdesn_adjustment_rows(vb_meta, fixture$row_meta, fixture$tau, vb_raw, vb_contract$qhat_contract),
    app_joint_qdesn_adjustment_rows(mcmc_meta, fixture$row_meta, fixture$tau, pooled$qhat_mean, mcmc_contract$qhat_contract)
  )
  raw_crossing <- rbind(
    app_joint_qdesn_crossing_rows(vb_meta, fixture$row_meta, fixture$tau, vb_raw, "raw_vb_fit_quantiles"),
    app_joint_qdesn_crossing_rows(mcmc_meta, fixture$row_meta, fixture$tau, pooled$qhat_mean, "raw_pooled_mcmc_fit_quantiles")
  )
  contract_crossing <- rbind(
    app_joint_qdesn_crossing_rows(vb_meta, fixture$row_meta, fixture$tau, vb_contract$qhat_contract, "contract_vb_fit_quantiles"),
    app_joint_qdesn_crossing_rows(mcmc_meta, fixture$row_meta, fixture$tau, mcmc_contract$qhat_contract, "contract_pooled_mcmc_fit_quantiles")
  )
  draw_summary <- app_joint_qdesn_bind_rows(draw_rows)
  max_sigma_upper_hit <- max(draw_summary$upper_bound_hit_fraction[draw_summary$block == "sigma"], na.rm = TRUE)
  max_sigma_lower_hit <- max(draw_summary$lower_bound_hit_fraction[draw_summary$block == "sigma"], na.rm = TRUE)
  chain_max <- max(chain_distance$max_normalized_to_pooled, na.rm = TRUE)

  summary <- cbind(
    mcmc_meta,
    data.frame(
      n_train = length(fixture$y),
      p = ncol(fixture$Z),
      K = length(fixture$tau),
      tau_grid = app_joint_qdesn_format_tau(fixture$tau),
      vb_converged = isTRUE(vb_fit$converged),
      vb_reached_max_iter = !isTRUE(vb_fit$converged),
      vb_max_iter_used = as.integer(attr(vb_fit, "adaptive_vb_max_iter_used") %||% vb_controls$vb_max_iter),
      vb_adaptive_attempts = attr(vb_fit, "adaptive_vb_attempts") %||% as.character(vb_controls$vb_max_iter),
      mcmc_n_chains = mcmc_controls$n_chains,
      mcmc_n_iter = mcmc_controls$mcmc_n_iter,
      mcmc_burn = mcmc_controls$mcmc_burn,
      mcmc_thin = mcmc_controls$mcmc_thin,
      mcmc_n_keep_total = nrow(pooled$beta_draws),
      mcmc_init_source = pooled$init_source,
      all_chain_init_source_provided = all(vapply(fits, function(x) identical(x$init_source, "provided"), logical(1L))),
      mcmc_draws_all_finite = all(is.finite(pooled$beta_draws)) && all(is.finite(pooled$alpha_draws)) && all(is.finite(pooled$sigma_draws)),
      sigma_lower_bound = sigma_bounds[[1L]],
      sigma_upper_bound = sigma_bounds[[2L]],
      max_sigma_lower_bound_hit_fraction = max_sigma_lower_hit,
      max_sigma_upper_bound_hit_fraction = max_sigma_upper_hit,
      vb_raw_crossing_pairs = sum(vb_contract$raw_crossing$n_crossing_pairs),
      vb_contract_crossing_pairs = sum(vb_contract$contract_crossing$n_crossing_pairs),
      mcmc_raw_crossing_pairs = sum(mcmc_contract$raw_crossing$n_crossing_pairs),
      mcmc_contract_crossing_pairs = sum(mcmc_contract$contract_crossing$n_crossing_pairs),
      vb_max_abs_adjustment = vb_contract$max_abs_adjustment,
      mcmc_max_abs_adjustment = mcmc_contract$max_abs_adjustment,
      vb_truth_mae = mean(vb_scored$truth_abs_error, na.rm = TRUE),
      mcmc_truth_mae = mean(mcmc_scored$truth_abs_error, na.rm = TRUE),
      vb_check_loss_mean = mean(vb_scored$check_loss, na.rm = TRUE),
      mcmc_check_loss_mean = mean(mcmc_scored$check_loss, na.rm = TRUE),
      vb_mcmc_max_normalized_distance = distance$max_normalized_distance[[1L]],
      max_chain_to_pooled_normalized_distance = chain_max,
      vb_elapsed_seconds = vb_elapsed,
      mcmc_elapsed_seconds = mcmc_elapsed,
      total_elapsed_seconds = vb_elapsed + mcmc_elapsed,
      stringsAsFactors = FALSE
    )
  )
  runtime <- rbind(
    cbind(vb_meta, data.frame(runtime_component = "vb_fit", chain_id = NA_integer_, chain_seed = NA_integer_, elapsed_seconds = vb_elapsed, sec_per_iter = NA_real_, stringsAsFactors = FALSE)),
    cbind(mcmc_meta, data.frame(runtime_component = "mcmc_pooled", chain_id = NA_integer_, chain_seed = NA_integer_, elapsed_seconds = mcmc_elapsed, sec_per_iter = mcmc_elapsed / max(1L, mcmc_controls$mcmc_n_iter * mcmc_controls$n_chains), stringsAsFactors = FALSE)),
    app_joint_qdesn_bind_rows(chain_runtime_rows)
  )
  list(
    summary = summary,
    quantiles_raw = rbind(vb_raw_rows, mcmc_raw_rows),
    quantiles = scored,
    adjustment = adjustment,
    raw_crossing = raw_crossing,
    contract_crossing = contract_crossing,
    vb_convergence = app_joint_qdesn_vb_convergence_row(vb_fit, vb_meta, vb_controls),
    rhs = app_joint_qdesn_rhs_rows(vb_fit, vb_meta),
    objective = app_joint_qdesn_objective_row(vb_fit, vb_meta),
    scale = app_joint_qdesn_scale_summary_rows(vb_fit, fixture, vb_meta),
    distance = distance,
    chain_distance = chain_distance,
    draw_summary = draw_summary,
    runtime = runtime
  )
}

app_joint_qdesn_phase108_empty_worker_failure_rows <- function() {
  data.frame(
    validation_label = character(),
    scenario_id = character(),
    worker_index = integer(),
    worker_status = character(),
    error_class = character(),
    error_message = character(),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_mcmc_readiness_assessment <- function(summary, worker_failures, phase107_manifest, fixture_manifest, distance_pass, chain_pass) {
  if (!nrow(summary)) {
    return(data.frame(
      scenario_id = character(),
      gate_status = character(),
      status_reason = character(),
      stringsAsFactors = FALSE
    ))
  }
  phase107_ok <- all(phase107_manifest$status == "pass")
  fixture_ok <- all(fixture_manifest$status == "pass")
  worker_ok <- !nrow(worker_failures)
  rows <- lapply(seq_len(nrow(summary)), function(ii) {
    x <- summary[ii, , drop = FALSE]
    finite_required <- all(is.finite(c(
      x$mcmc_n_keep_total,
      x$sigma_upper_bound,
      x$vb_truth_mae,
      x$mcmc_truth_mae,
      x$vb_mcmc_max_normalized_distance,
      x$max_chain_to_pooled_normalized_distance,
      x$total_elapsed_seconds
    )))
    implementation_fail <- !phase107_ok || !fixture_ok || !worker_ok || !finite_required ||
      !isTRUE(x$all_chain_init_source_provided[[1L]]) ||
      !isTRUE(x$mcmc_draws_all_finite[[1L]]) ||
      x$vb_contract_crossing_pairs[[1L]] > 0L ||
      x$mcmc_contract_crossing_pairs[[1L]] > 0L
    review <- !implementation_fail && (
      isTRUE(x$vb_reached_max_iter[[1L]]) ||
        x$vb_raw_crossing_pairs[[1L]] > 0L ||
        x$mcmc_raw_crossing_pairs[[1L]] > 0L ||
        x$mcmc_max_abs_adjustment[[1L]] > 1.0e-3 ||
        x$max_sigma_lower_bound_hit_fraction[[1L]] > 0 ||
        x$max_sigma_upper_bound_hit_fraction[[1L]] > 0 ||
        x$vb_mcmc_max_normalized_distance[[1L]] > distance_pass ||
        x$max_chain_to_pooled_normalized_distance[[1L]] > chain_pass
    )
    reasons <- c(
      if (!phase107_ok) "Phase 107 source manifest failed",
      if (!fixture_ok) "fixture manifest failed",
      if (!worker_ok) "one or more scenario workers failed",
      if (!finite_required) "nonfinite MCMC readiness metric",
      if (!isTRUE(x$all_chain_init_source_provided[[1L]])) "MCMC did not use provided VB initialization",
      if (!isTRUE(x$mcmc_draws_all_finite[[1L]])) "nonfinite MCMC draws",
      if (x$vb_contract_crossing_pairs[[1L]] > 0L) "VB contract quantiles crossed",
      if (x$mcmc_contract_crossing_pairs[[1L]] > 0L) "MCMC contract quantiles crossed",
      if (!implementation_fail && isTRUE(x$vb_reached_max_iter[[1L]])) "VB reached max iterations",
      if (!implementation_fail && x$vb_raw_crossing_pairs[[1L]] > 0L) "VB raw quantiles crossed before contract step",
      if (!implementation_fail && x$mcmc_raw_crossing_pairs[[1L]] > 0L) "MCMC raw quantiles crossed before contract step",
      if (!implementation_fail && x$mcmc_max_abs_adjustment[[1L]] > 1.0e-3) "MCMC monotone adjustment requires review",
      if (!implementation_fail && (x$max_sigma_lower_bound_hit_fraction[[1L]] > 0 || x$max_sigma_upper_bound_hit_fraction[[1L]] > 0)) "MCMC sigma bound hit requires review",
      if (!implementation_fail && x$vb_mcmc_max_normalized_distance[[1L]] > distance_pass) "VB/MCMC distance requires review",
      if (!implementation_fail && x$max_chain_to_pooled_normalized_distance[[1L]] > chain_pass) "chain-to-pooled distance requires review"
    )
    cbind(x[, c("scenario_id", "scenario_class", "distribution_family", "dynamics_class", "model_id", "display_label"), drop = FALSE], data.frame(
      implementation_status = if (implementation_fail) "fail" else "pass",
      distance_status = if (is.finite(x$vb_mcmc_max_normalized_distance[[1L]]) && x$vb_mcmc_max_normalized_distance[[1L]] <= distance_pass) "pass" else "review",
      chain_status = if (is.finite(x$max_chain_to_pooled_normalized_distance[[1L]]) && x$max_chain_to_pooled_normalized_distance[[1L]] <= chain_pass) "pass" else "review",
      gate_status = if (implementation_fail) "fail" else if (review) "review" else "pass",
      status_reason = if (length(reasons)) paste(reasons, collapse = "; ") else "all readiness gates passed",
      stringsAsFactors = FALSE
    ))
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_mcmc_readiness_readme <- function(run_config, assessment) {
  launch_label <- if (isTRUE(run_config$final_article_mcmc_table[[1L]])) {
    "article-scale MCMC launch"
  } else {
    "VB-initialized AL-MCMC readiness artifacts"
  }
  c(
    "# Joint QDESN Phase 108 MCMC Readiness",
    "",
    sprintf("This directory contains %s for the frozen joint QDESN simulation specification.", launch_label),
    if (isTRUE(run_config$final_article_mcmc_table[[1L]])) {
      "It uses the Phase 108-validated launch contract and is intended as an article-candidate MCMC artifact."
    } else {
      "It is a reference/readiness layer, not the final article-scale MCMC table."
    },
    "",
    sprintf("- Phase 107 source: `%s`", run_config$phase107_dir[[1L]]),
    sprintf("- Fixture directory: `%s`", run_config$fixture_dir[[1L]]),
    sprintf("- Scenarios: %s", run_config$n_scenarios[[1L]]),
    sprintf("- MCMC chains: %s", run_config$mcmc_n_chains[[1L]]),
    sprintf("- MCMC iterations/burn/thin: %s/%s/%s", run_config$mcmc_n_iter[[1L]], run_config$mcmc_burn[[1L]], run_config$mcmc_thin[[1L]]),
    "",
    "The runner refits `JOINT QDESN RHS` under the frozen Phase 107 VB controls, then initializes AL-MCMC from that VB state.",
    "Raw and monotone-contract quantiles are both preserved; scoring uses the contract quantiles.",
    "",
    "Gate counts:",
    paste(capture.output(print(table(assessment$gate_status))), collapse = "\n")
  )
}

app_joint_qdesn_run_mcmc_readiness <- function(
  out_dir = app_joint_qdesn_default_mcmc_readiness_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  phase107_dir = app_joint_qdesn_default_phase107_dir(),
  scenario_ids = NULL,
  candidate_id = "rhs_tau0_0p5_alpha0p5",
  n_chains = 2L,
  mcmc_n_iter = 80L,
  mcmc_burn = 40L,
  mcmc_thin = 5L,
  mcmc_seed_offset = 3100L,
  chain_seed_stride = 100L,
  sigma_upper_multiplier = 50,
  distance_pass = 5,
  chain_pass = 5,
  n_cores = 1L,
  final_article_mcmc_table = FALSE
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  contract <- app_joint_qdesn_load_phase107_contract(phase107_dir, candidate_id)
  artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)
  available <- artifacts$scenario_summary$scenario_id
  if (is.null(scenario_ids) || !length(scenario_ids)) scenario_ids <- available
  missing <- setdiff(scenario_ids, available)
  if (length(missing)) stop("Unknown scenario_ids: ", paste(missing, collapse = ", "), call. = FALSE)
  scenario_ids <- scenario_ids[scenario_ids %in% available]
  mcmc_controls <- app_joint_qdesn_mcmc_readiness_controls(
    n_chains = n_chains,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin,
    mcmc_seed_offset = mcmc_seed_offset,
    chain_seed_stride = chain_seed_stride,
    sigma_upper_multiplier = sigma_upper_multiplier,
    distance_pass = distance_pass,
    chain_pass = chain_pass,
    n_cores = n_cores
  )
  results <- app_joint_qdesn_parallel_lapply(
    scenario_ids,
    function(sid) app_joint_qdesn_phase108_one_scenario(artifacts, sid, contract$vb_controls, mcmc_controls),
    mcmc_controls$n_cores
  )
  worker_failures <- app_joint_qdesn_worker_failure_rows(results, "mcmc_readiness")
  successful <- app_joint_qdesn_successful_worker_results(results, "mcmc_readiness")
  summary <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "summary"))
  quantiles_raw <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "quantiles_raw"))
  quantiles <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "quantiles"))
  adjustment <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "adjustment"))
  raw_crossing <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "raw_crossing"))
  contract_crossing <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "contract_crossing"))
  vb_convergence <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "vb_convergence"))
  rhs <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "rhs"))
  objective <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "objective"))
  scale <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "scale"))
  distance <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "distance"))
  chain_distance <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "chain_distance"))
  draw_summary <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "draw_summary"))
  runtime <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "runtime"))

  phase107_manifest <- app_joint_qdesn_bind_rows(list(
    contract$phase107_top_manifest_verification,
    contract$phase107_nested_manifest_verification
  ))
  assessment <- app_joint_qdesn_mcmc_readiness_assessment(
    summary = summary,
    worker_failures = worker_failures,
    phase107_manifest = phase107_manifest,
    fixture_manifest = artifacts$manifest_verification,
    distance_pass = distance_pass,
    chain_pass = chain_pass
  )
  check_loss_summary <- app_joint_qdesn_check_loss_summary(quantiles)
  hit_rate_summary <- app_joint_qdesn_hit_rate_summary(quantiles)
  truth_summary <- app_joint_qdesn_truth_summary(quantiles)
  crps_summary <- app_joint_qdesn_crps_grid_summary(quantiles, "qhat")
  interval_summary <- app_joint_qdesn_interval_summary(quantiles, "qhat")
  run_config <- data.frame(
    run_id = "joint_qdesn_mcmc_readiness_phase108",
    out_dir = out_dir,
    fixture_dir = artifacts$fixture_dir,
    phase107_dir = contract$phase107_dir,
    candidate_id = candidate_id,
    scenario_ids = paste(scenario_ids, collapse = ","),
    n_scenarios = length(scenario_ids),
    model_scope = "JOINT QDESN RHS only",
    likelihood_scope = "AL only",
    exal_mcmc_scope = "not_implemented_in_phase108",
    vb_max_iter = contract$vb_controls$vb_max_iter,
    adaptive_vb_max_iter_grid = paste(contract$vb_controls$adaptive_vb_max_iter_grid, collapse = ","),
    vb_tol = contract$vb_controls$vb_tol,
    rhs_vb_inner = contract$vb_controls$rhs_vb_inner,
    tau0 = contract$vb_controls$tau0,
    zeta2 = contract$vb_controls$zeta2,
    a_sigma = contract$vb_controls$a_sigma,
    b_sigma = contract$vb_controls$b_sigma,
    alpha_prior_sd = contract$vb_controls$alpha_prior_sd,
    alpha_min_spacing = contract$vb_controls$alpha_min_spacing,
    mcmc_n_chains = mcmc_controls$n_chains,
    mcmc_n_iter = mcmc_controls$mcmc_n_iter,
    mcmc_burn = mcmc_controls$mcmc_burn,
    mcmc_thin = mcmc_controls$mcmc_thin,
    mcmc_seed_offset = mcmc_controls$mcmc_seed_offset,
    chain_seed_stride = mcmc_controls$chain_seed_stride,
    sigma_upper_multiplier = mcmc_controls$sigma_upper_multiplier,
    distance_pass = distance_pass,
    chain_pass = chain_pass,
    n_cores = mcmc_controls$n_cores,
    mcmc_launched = TRUE,
    final_article_mcmc_table = isTRUE(final_article_mcmc_table),
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qdesn_mcmc_readiness_readme(run_config, assessment), readme_path, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    phase107_source_manifest_verification = app_joint_qvp_write_csv(phase107_manifest, file.path(out_dir, "phase107_source_manifest_verification.csv")),
    fixture_source_manifest = app_joint_qvp_write_csv(artifacts$manifest_verification, file.path(out_dir, "fixture_source_manifest.csv")),
    scenario_worker_failures = app_joint_qvp_write_csv(worker_failures, file.path(out_dir, "scenario_worker_failures.csv")),
    mcmc_readiness_summary = app_joint_qvp_write_csv(summary, file.path(out_dir, "mcmc_readiness_summary.csv")),
    mcmc_readiness_assessment = app_joint_qvp_write_csv(assessment, file.path(out_dir, "mcmc_readiness_assessment.csv")),
    fit_quantiles_raw = app_joint_qvp_write_csv(quantiles_raw, file.path(out_dir, "fit_quantiles_raw.csv")),
    fit_quantiles = app_joint_qvp_write_csv(quantiles, file.path(out_dir, "fit_quantiles.csv")),
    fit_monotone_adjustment = app_joint_qvp_write_csv(adjustment, file.path(out_dir, "fit_monotone_adjustment.csv")),
    fit_truth_comparison = app_joint_qvp_write_csv(quantiles, file.path(out_dir, "fit_truth_comparison.csv")),
    truth_distance_summary = app_joint_qvp_write_csv(truth_summary, file.path(out_dir, "truth_distance_summary.csv")),
    check_loss_summary = app_joint_qvp_write_csv(check_loss_summary, file.path(out_dir, "check_loss_summary.csv")),
    hit_rate_summary = app_joint_qvp_write_csv(hit_rate_summary, file.path(out_dir, "hit_rate_summary.csv")),
    crps_grid_summary = app_joint_qvp_write_csv(crps_summary, file.path(out_dir, "crps_grid_summary.csv")),
    interval_summary = app_joint_qvp_write_csv(interval_summary, file.path(out_dir, "interval_summary.csv")),
    crossing_summary = app_joint_qvp_write_csv(contract_crossing, file.path(out_dir, "crossing_summary.csv")),
    raw_crossing_summary = app_joint_qvp_write_csv(raw_crossing, file.path(out_dir, "raw_crossing_summary.csv")),
    vb_convergence_audit = app_joint_qvp_write_csv(vb_convergence, file.path(out_dir, "vb_convergence_audit.csv")),
    objective_diagnostics = app_joint_qvp_write_csv(objective, file.path(out_dir, "objective_diagnostics.csv")),
    rhs_prior_summary = app_joint_qvp_write_csv(rhs, file.path(out_dir, "rhs_prior_summary.csv")),
    scale_parameter_summary = app_joint_qvp_write_csv(scale, file.path(out_dir, "scale_parameter_summary.csv")),
    mcmc_draw_summary = app_joint_qvp_write_csv(draw_summary, file.path(out_dir, "mcmc_draw_summary.csv")),
    vb_mcmc_distance_summary = app_joint_qvp_write_csv(distance, file.path(out_dir, "vb_mcmc_distance_summary.csv")),
    chain_to_pooled_distance_summary = app_joint_qvp_write_csv(chain_distance, file.path(out_dir, "chain_to_pooled_distance_summary.csv")),
    runtime_summary = app_joint_qvp_write_csv(runtime, file.path(out_dir, "runtime_summary.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    paths = c(paths, artifact_manifest = manifest_info$manifest_path),
    manifest = manifest_info$manifest,
    run_config = run_config,
    assessment = assessment,
    summary = summary,
    worker_failures = worker_failures
  )
}

# Phase 122 case-specific MCMC confirmation.  This stage consumes the Phase 121
# per-case VB/VB-LD freeze and confirms the requested article rows with
# VB-initialized MCMC on quantile readout paths.  It evaluates both fit rows and
# the frozen no-refit validation-origin forecast rows.

app_joint_qdesn_default_phase122_mcmc_case_confirmation_dir <- function() {
  app_path("application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711")
}

app_joint_qdesn_default_phase121_case_vb_freeze_dir_fallback <- function() {
  if (exists("app_joint_qdesn_default_phase121_case_vb_freeze_dir", mode = "function")) {
    return(app_joint_qdesn_default_phase121_case_vb_freeze_dir())
  }
  app_path("application/cache/joint_qdesn_phase121_case_vb_winner_freeze_20260711")
}

app_joint_qdesn_phase122_required_phase121_files <- function() {
  c(
    "case_winner_controls.csv",
    "case_winner_metric_summary.csv",
    "case_winner_gate_audit.csv",
    "artifact_manifest.csv"
  )
}

app_joint_qdesn_phase122_load_phase121 <- function(phase121_dir) {
  phase121_dir <- normalizePath(phase121_dir, mustWork = TRUE)
  missing <- app_joint_qdesn_phase122_required_phase121_files()[
    !file.exists(file.path(phase121_dir, app_joint_qdesn_phase122_required_phase121_files()))
  ]
  if (length(missing)) {
    stop(sprintf("Phase 121 freeze is missing required files: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  manifest <- app_joint_qdesn_phase108_manifest_verify(phase121_dir, "phase121_case_vb_winner_freeze")
  if (any(manifest$status != "pass")) {
    stop("Phase 121 manifest verification failed; refusing MCMC confirmation.", call. = FALSE)
  }
  controls <- app_read_csv(file.path(phase121_dir, "case_winner_controls.csv"))
  metrics <- app_read_csv(file.path(phase121_dir, "case_winner_metric_summary.csv"))
  gate <- app_read_csv(file.path(phase121_dir, "case_winner_gate_audit.csv"))
  app_check_required_columns(controls, c(
    "case_id", "scenario_ids", "model_ids", "candidate_id", "phase121_selection_status",
    "vb_max_iter", "adaptive_vb_max_iter_grid", "vb_tol", "rhs_vb_inner", "tau0",
    "zeta2", "a_sigma", "b_sigma", "alpha_prior_sd", "alpha_min_spacing",
    "gamma_init_policy", "review_adjustment_threshold", "max_dense_dim"
  ), "Phase 121 case winner controls")
  list(
    phase121_dir = phase121_dir,
    manifest_verification = manifest,
    controls = controls,
    metrics = metrics,
    gate_audit = gate
  )
}

app_joint_qdesn_phase122_filter_controls <- function(
  controls,
  case_ids = NULL,
  scenario_ids = NULL,
  model_ids = NULL,
  scenario_limit_per_model = NULL
) {
  out <- controls
  if (!is.null(case_ids) && length(case_ids)) out <- out[out$case_id %in% case_ids, , drop = FALSE]
  if (!is.null(scenario_ids) && length(scenario_ids)) out <- out[out$scenario_ids %in% scenario_ids, , drop = FALSE]
  if (!is.null(model_ids) && length(model_ids)) out <- out[out$model_ids %in% model_ids, , drop = FALSE]
  if (!is.null(scenario_limit_per_model) && is.finite(scenario_limit_per_model) && scenario_limit_per_model > 0L) {
    keep <- unlist(lapply(split(seq_len(nrow(out)), out$model_ids), function(idx) {
      head(idx, as.integer(scenario_limit_per_model))
    }), use.names = FALSE)
    out <- out[sort(keep), , drop = FALSE]
  }
  if (!nrow(out)) stop("No Phase 121 winner rows remain after filtering.", call. = FALSE)
  out
}

app_joint_qdesn_phase122_controls_from_row <- function(row, n_cores = 1L) {
  app_joint_qdesn_simulation_controls(
    vb_max_iter = as.integer(row$vb_max_iter[[1L]]),
    adaptive_vb_max_iter_grid = app_joint_qdesn_parse_iter_grid(row$adaptive_vb_max_iter_grid[[1L]]),
    vb_tol = as.numeric(row$vb_tol[[1L]]),
    rhs_vb_inner = as.integer(row$rhs_vb_inner[[1L]]),
    tau0 = as.numeric(row$tau0[[1L]]),
    zeta2 = as.numeric(row$zeta2[[1L]]),
    a_sigma = as.numeric(row$a_sigma[[1L]]),
    b_sigma = as.numeric(row$b_sigma[[1L]]),
    alpha_prior_sd = row$alpha_prior_sd[[1L]],
    alpha_min_spacing = as.numeric(row$alpha_min_spacing[[1L]]),
    gamma_init_policy = row$gamma_init_policy[[1L]],
    review_adjustment_threshold = as.numeric(row$review_adjustment_threshold[[1L]]),
    max_dense_dim = as.integer(row$max_dense_dim[[1L]]),
    n_cores = as.integer(n_cores)
  )
}

app_joint_qdesn_phase122_mcmc_model_id <- function(model_id) {
  sub("_vb$", "_mcmc", model_id)
}

app_joint_qdesn_phase122_meta <- function(fixture, spec, row, inference, validation_model_id = NULL) {
  model_id <- validation_model_id %||% spec$model_id[[1L]]
  data.frame(
    case_id = row$case_id[[1L]],
    scenario_id = fixture$scenario_id,
    scenario_class = fixture$scenario_meta$scenario_class[[1L]],
    distribution_family = fixture$scenario_meta$distribution_family[[1L]],
    dynamics_class = fixture$scenario_meta$dynamics_class[[1L]],
    source_candidate_id = row$candidate_id[[1L]],
    source_model_id = spec$model_id[[1L]],
    model_id = model_id,
    display_label = if (identical(inference, "MCMC")) paste(spec$display_label[[1L]], "MCMC") else spec$display_label[[1L]],
    likelihood = spec$likelihood[[1L]],
    fit_structure = spec$fit_structure[[1L]],
    inference = inference,
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase122_select_spec <- function(model_id) {
  spec <- app_joint_qdesn_simulation_model_specs()
  spec <- spec[spec$model_id == model_id, , drop = FALSE]
  if (nrow(spec) != 1L) stop(sprintf("Unknown Phase 122 model_id '%s'.", model_id), call. = FALSE)
  spec
}

app_joint_qdesn_phase122_draw_summary <- function(fit, case_id, stress_case, scenario, sigma_bounds = c(NA_real_, NA_real_)) {
  out <- app_joint_qvp_mcmc_draw_summary(fit, case_id, stress_case, scenario, sigma_bounds = sigma_bounds)
  if (!is.null(fit$gamma_draws)) {
    x <- fit$gamma_draws
    gamma_row <- data.frame(
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      block = "gamma",
      n_draws = nrow(x),
      n_parameters = ncol(x),
      all_finite = all(is.finite(x)),
      mean_abs_draw_mean = mean(abs(colMeans(x))),
      mean_draw_sd = mean(apply(x, 2L, stats::sd)),
      min_value = min(x),
      max_value = max(x),
      lower_bound = NA_real_,
      upper_bound = NA_real_,
      lower_bound_hit_fraction = NA_real_,
      upper_bound_hit_fraction = NA_real_,
      stringsAsFactors = FALSE
    )
    out <- rbind(out, gamma_row)
  }
  out
}

app_joint_qdesn_phase122_pool_mcmc_chains <- function(fits, Z, K, p, tau) {
  pooled <- app_joint_qvp_pool_mcmc_chains(fits, Z, K, p, tau)
  has_gamma <- all(vapply(fits, function(x) !is.null(x$gamma_draws), logical(1L)))
  if (has_gamma) {
    pooled$gamma_draws <- do.call(rbind, lapply(fits, `[[`, "gamma_draws"))
    pooled$gamma_mean <- colMeans(pooled$gamma_draws)
  }
  pooled
}

app_joint_qdesn_phase122_combine_independent_chain <- function(fits_by_tau, Z, tau, chain_id, seed) {
  K <- length(tau)
  p <- ncol(Z)
  n_keep <- nrow(fits_by_tau[[1L]]$beta_draws)
  beta_draws <- matrix(NA_real_, nrow = n_keep, ncol = K * p)
  alpha_draws <- sigma_draws <- matrix(NA_real_, nrow = n_keep, ncol = K)
  has_gamma <- all(vapply(fits_by_tau, function(x) !is.null(x$gamma_draws), logical(1L)))
  gamma_draws <- if (has_gamma) matrix(NA_real_, nrow = n_keep, ncol = K) else NULL
  for (kk in seq_len(K)) {
    idx <- ((kk - 1L) * p + 1L):(kk * p)
    beta_draws[, idx] <- fits_by_tau[[kk]]$beta_draws
    alpha_draws[, kk] <- fits_by_tau[[kk]]$alpha_draws[, 1L]
    sigma_draws[, kk] <- fits_by_tau[[kk]]$sigma_draws[, 1L]
    if (has_gamma) gamma_draws[, kk] <- fits_by_tau[[kk]]$gamma_draws[, 1L]
  }
  beta_mean <- colMeans(beta_draws)
  alpha_mean <- colMeans(alpha_draws)
  qhat_mean <- Z %*% app_joint_qvp_beta_matrix(beta_mean, K, p) +
    matrix(alpha_mean, nrow = nrow(Z), ncol = K, byrow = TRUE)
  out <- list(
    beta_draws = beta_draws,
    alpha_draws = alpha_draws,
    sigma_draws = sigma_draws,
    beta_mean = beta_mean,
    alpha_mean = alpha_mean,
    sigma_mean = colMeans(sigma_draws),
    qhat_mean = qhat_mean,
    crossing_diagnostics = app_joint_qvp_crossing_diagnostics(qhat_mean, tau),
    tau = tau,
    seed = seed,
    chain_id = chain_id,
    init_source = paste(sort(unique(vapply(fits_by_tau, function(x) x$init_source %||% NA_character_, character(1L)))), collapse = ";")
  )
  if (has_gamma) {
    out$gamma_draws <- gamma_draws
    out$gamma_mean <- colMeans(gamma_draws)
  }
  class(out) <- c("joint_qvp_qdesn_tiny_fit", "list")
  out
}

app_joint_qdesn_phase122_run_mcmc_chains <- function(fixture, spec, vb_fit, controls, mcmc_controls, row) {
  K <- length(fixture$tau)
  p <- ncol(fixture$Z)
  sigma_upper <- max(1, mcmc_controls$sigma_upper_multiplier * max(vb_fit$sigma_mean, na.rm = TRUE))
  sigma_bounds <- c(1.0e-8, sigma_upper)
  base_seed <- as.integer(fixture$scenario_meta$seed[[1L]])
  case_offset <- sum(utf8ToInt(row$case_id[[1L]])) %% 100000L
  fits <- vector("list", mcmc_controls$n_chains)
  draw_rows <- chain_runtime_rows <- list()
  start <- proc.time()[["elapsed"]]
  for (chain_id in seq_len(mcmc_controls$n_chains)) {
    chain_seed <- base_seed + mcmc_controls$mcmc_seed_offset + case_offset + (chain_id - 1L) * mcmc_controls$chain_seed_stride
    chain_start <- proc.time()[["elapsed"]]
    if (identical(spec$fit_structure[[1L]], "joint")) {
      if (identical(spec$likelihood[[1L]], "al")) {
        fits[[chain_id]] <- app_joint_qvp_fit_al_mcmc_tiny(
          y = fixture$y,
          Z = fixture$Z,
          tau = fixture$tau,
          n_iter = mcmc_controls$mcmc_n_iter,
          burn = mcmc_controls$mcmc_burn,
          thin = mcmc_controls$mcmc_thin,
          seed = chain_seed,
          kappa = 1,
          tau0 = controls$tau0,
          zeta2 = controls$zeta2,
          a_sigma = controls$a_sigma,
          b_sigma = controls$b_sigma,
          alpha_prior_mean = "empirical_quantile",
          alpha_prior_sd = controls$alpha_prior_sd,
          alpha_min_spacing = controls$alpha_min_spacing,
          max_dense_dim = controls$max_dense_dim,
          sigma_bounds = sigma_bounds,
          init = vb_fit
        )
      } else {
        fits[[chain_id]] <- app_joint_qvp_fit_exal_mcmc_tiny(
          y = fixture$y,
          Z = fixture$Z,
          tau = fixture$tau,
          n_iter = mcmc_controls$mcmc_n_iter,
          burn = mcmc_controls$mcmc_burn,
          thin = mcmc_controls$mcmc_thin,
          seed = chain_seed,
          kappa = 1,
          tau0 = controls$tau0,
          zeta2 = controls$zeta2,
          gamma_init = app_joint_qdesn_gamma_init_for_policy(fixture$tau, controls),
          alpha_min_spacing = controls$alpha_min_spacing,
          max_dense_dim = controls$max_dense_dim,
          sigma_bounds = sigma_bounds,
          init = vb_fit
        )
      }
    } else {
      one_tau_fits <- vector("list", K)
      for (kk in seq_len(K)) {
        one_seed <- chain_seed + kk * 1009L
        alpha_prior_sd_kk <- app_joint_qdesn_alpha_prior_sd_for_tau(controls$alpha_prior_sd, kk, K)
        if (identical(spec$likelihood[[1L]], "al")) {
          one_tau_fits[[kk]] <- app_joint_qvp_fit_al_mcmc_tiny(
            y = fixture$y,
            Z = fixture$Z,
            tau = fixture$tau[[kk]],
            n_iter = mcmc_controls$mcmc_n_iter,
            burn = mcmc_controls$mcmc_burn,
            thin = mcmc_controls$mcmc_thin,
            seed = one_seed,
            kappa = 1,
            tau0 = controls$tau0,
            zeta2 = controls$zeta2,
            a_sigma = controls$a_sigma,
            b_sigma = controls$b_sigma,
            alpha_prior_mean = "empirical_quantile",
            alpha_prior_sd = alpha_prior_sd_kk,
            alpha_min_spacing = 0,
            max_dense_dim = controls$max_dense_dim,
            sigma_bounds = sigma_bounds,
            init = vb_fit$fits[[kk]]
          )
        } else {
          one_tau_fits[[kk]] <- app_joint_qvp_fit_exal_mcmc_tiny(
            y = fixture$y,
            Z = fixture$Z,
            tau = fixture$tau[[kk]],
            n_iter = mcmc_controls$mcmc_n_iter,
            burn = mcmc_controls$mcmc_burn,
            thin = mcmc_controls$mcmc_thin,
            seed = one_seed,
            kappa = 1,
            tau0 = controls$tau0,
            zeta2 = controls$zeta2,
            gamma_init = app_joint_qdesn_gamma_init_for_policy(fixture$tau[[kk]], controls),
            alpha_min_spacing = 0,
            max_dense_dim = controls$max_dense_dim,
            sigma_bounds = sigma_bounds,
            init = vb_fit$fits[[kk]]
          )
        }
      }
      fits[[chain_id]] <- app_joint_qdesn_phase122_combine_independent_chain(
        fits_by_tau = one_tau_fits,
        Z = fixture$Z,
        tau = fixture$tau,
        chain_id = chain_id,
        seed = chain_seed
      )
    }
    chain_elapsed <- proc.time()[["elapsed"]] - chain_start
    draw_rows[[chain_id]] <- cbind(
      data.frame(chain_id = chain_id, chain_seed = chain_seed, stringsAsFactors = FALSE),
      app_joint_qdesn_phase122_draw_summary(fits[[chain_id]], row$case_id[[1L]], "joint_qdesn_phase122", fixture$scenario_id, sigma_bounds = sigma_bounds),
      stringsAsFactors = FALSE
    )
    chain_runtime_rows[[chain_id]] <- data.frame(
      case_id = row$case_id[[1L]],
      scenario_id = fixture$scenario_id,
      model_id = app_joint_qdesn_phase122_mcmc_model_id(spec$model_id[[1L]]),
      runtime_component = "mcmc_chain",
      chain_id = chain_id,
      chain_seed = chain_seed,
      elapsed_seconds = chain_elapsed,
      sec_per_iter = chain_elapsed / max(1L, mcmc_controls$mcmc_n_iter),
      stringsAsFactors = FALSE
    )
  }
  pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(fits, fixture$Z, K, p, fixture$tau)
  distance <- app_joint_qvp_vb_mcmc_distance_summary(vb_fit, pooled, row$case_id[[1L]], "joint_qdesn_phase122", fixture$scenario_id, length(fixture$y), p, K)
  if (!is.null(vb_fit$gamma_mean) && !is.null(pooled$gamma_mean)) {
    gamma_l2 <- app_joint_qvp_l2_distance(vb_fit$gamma_mean, pooled$gamma_mean)
    distance$gamma_l2_to_mcmc <- gamma_l2
    distance$gamma_normalized_distance <- gamma_l2 / (sqrt(K) * (1 + sqrt(mean(vb_fit$gamma_mean^2))))
    distance$max_normalized_distance <- pmax(distance$max_normalized_distance, distance$gamma_normalized_distance, na.rm = TRUE)
  } else {
    distance$gamma_l2_to_mcmc <- NA_real_
    distance$gamma_normalized_distance <- NA_real_
  }
  chain_distance <- app_joint_qvp_chain_to_pooled_summary(fits, pooled, fixture$Z, row$case_id[[1L]], "joint_qdesn_phase122", fixture$scenario_id, length(fixture$y), p, K)
  list(
    fits = fits,
    pooled = pooled,
    draw_summary = app_joint_qdesn_bind_rows(draw_rows),
    distance = distance,
    chain_distance = chain_distance,
    runtime = app_joint_qdesn_bind_rows(chain_runtime_rows),
    sigma_bounds = sigma_bounds,
    elapsed_seconds = proc.time()[["elapsed"]] - start
  )
}

app_joint_qdesn_phase122_score_qhat <- function(meta, fixture_like, qhat, value_name, crossing_label) {
  contract <- app_joint_qdesn_apply_monotone_contract(qhat, fixture_like$tau)
  raw_rows <- app_joint_qdesn_quantile_long_rows(meta, fixture_like$row_meta, fixture_like$tau, fixture_like$y, fixture_like$true_q, qhat, paste0(value_name, "_raw"))
  contract_rows <- app_joint_qdesn_quantile_long_rows(meta, fixture_like$row_meta, fixture_like$tau, fixture_like$y, fixture_like$true_q, contract$qhat_contract, value_name)
  scored <- app_joint_qdesn_quantile_scores(contract_rows, value_name)
  list(
    raw = raw_rows,
    contract_rows = contract_rows,
    scored = scored,
    adjustment = app_joint_qdesn_adjustment_rows(meta, fixture_like$row_meta, fixture_like$tau, qhat, contract$qhat_contract),
    raw_crossing = app_joint_qdesn_crossing_rows(meta, fixture_like$row_meta, fixture_like$tau, qhat, paste0("raw_", crossing_label)),
    contract_crossing = app_joint_qdesn_crossing_rows(meta, fixture_like$row_meta, fixture_like$tau, contract$qhat_contract, paste0("contract_", crossing_label)),
    contract_info = contract
  )
}

app_joint_qdesn_phase122_forecast_scores <- function(meta, artifacts, scenario_id, fit_fixture, fit_obj, value_name, crossing_label) {
  origin_plan <- artifacts$forecast_origin_plan[artifacts$forecast_origin_plan$scenario_id == scenario_id, , drop = FALSE]
  origin_plan <- origin_plan[order(origin_plan$origin_index), , drop = FALSE]
  rows <- lapply(seq_len(nrow(origin_plan)), function(ii) {
    target <- app_joint_qdesn_forecast_target_fixture(artifacts, scenario_id, origin_plan[ii, , drop = FALSE])
    if (!identical(fit_fixture$feature_cols, target$feature_cols)) {
      stop(sprintf("Feature columns changed between fit and forecast for '%s'.", scenario_id), call. = FALSE)
    }
    qhat <- app_joint_qdesn_predict_fit(fit_obj, target$Z, target$tau)
    app_joint_qdesn_phase122_score_qhat(meta, target, qhat, value_name, crossing_label)
  })
  list(
    raw = app_joint_qdesn_bind_rows(lapply(rows, `[[`, "raw")),
    contract = app_joint_qdesn_bind_rows(lapply(rows, `[[`, "contract_rows")),
    scored = app_joint_qdesn_bind_rows(lapply(rows, `[[`, "scored")),
    adjustment = app_joint_qdesn_bind_rows(lapply(rows, `[[`, "adjustment")),
    raw_crossing = app_joint_qdesn_bind_rows(lapply(rows, `[[`, "raw_crossing")),
    contract_crossing = app_joint_qdesn_bind_rows(lapply(rows, `[[`, "contract_crossing"))
  )
}

app_joint_qdesn_phase122_one_case <- function(artifacts, row, mcmc_controls) {
  scenario_id <- row$scenario_ids[[1L]]
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
  spec <- app_joint_qdesn_phase122_select_spec(row$model_ids[[1L]])
  controls <- app_joint_qdesn_phase122_controls_from_row(row, n_cores = 1L)
  vb_start <- proc.time()[["elapsed"]]
  vb_fit <- app_joint_qdesn_fit_model_adaptive(fixture, spec, controls)
  vb_elapsed <- proc.time()[["elapsed"]] - vb_start
  mcmc_result <- app_joint_qdesn_phase122_run_mcmc_chains(fixture, spec, vb_fit, controls, mcmc_controls, row)

  vb_meta <- app_joint_qdesn_phase122_meta(fixture, spec, row, spec$inference[[1L]], spec$model_id[[1L]])
  mcmc_meta <- app_joint_qdesn_phase122_meta(
    fixture,
    spec,
    row,
    "MCMC",
    app_joint_qdesn_phase122_mcmc_model_id(spec$model_id[[1L]])
  )

  vb_fit_scores <- app_joint_qdesn_phase122_score_qhat(
    vb_meta,
    fixture,
    app_joint_qdesn_predict_fit(vb_fit, fixture$Z, fixture$tau),
    "qhat",
    "vb_fit_quantiles"
  )
  mcmc_fit_scores <- app_joint_qdesn_phase122_score_qhat(
    mcmc_meta,
    fixture,
    app_joint_qdesn_predict_fit(mcmc_result$pooled, fixture$Z, fixture$tau),
    "qhat",
    "mcmc_fit_quantiles"
  )
  vb_forecast_scores <- app_joint_qdesn_phase122_forecast_scores(vb_meta, artifacts, scenario_id, fixture, vb_fit, "qhat", "vb_forecast_quantiles")
  mcmc_forecast_scores <- app_joint_qdesn_phase122_forecast_scores(mcmc_meta, artifacts, scenario_id, fixture, mcmc_result$pooled, "qhat", "mcmc_forecast_quantiles")

  fit_scored <- app_joint_qdesn_bind_rows(list(vb_fit_scores$scored, mcmc_fit_scores$scored))
  forecast_scored <- app_joint_qdesn_bind_rows(list(vb_forecast_scores$scored, mcmc_forecast_scores$scored))
  fit_raw_crossing <- app_joint_qdesn_bind_rows(list(vb_fit_scores$raw_crossing, mcmc_fit_scores$raw_crossing))
  forecast_raw_crossing <- app_joint_qdesn_bind_rows(list(vb_forecast_scores$raw_crossing, mcmc_forecast_scores$raw_crossing))
  fit_contract_crossing <- app_joint_qdesn_bind_rows(list(vb_fit_scores$contract_crossing, mcmc_fit_scores$contract_crossing))
  forecast_contract_crossing <- app_joint_qdesn_bind_rows(list(vb_forecast_scores$contract_crossing, mcmc_forecast_scores$contract_crossing))
  fit_adjustment <- app_joint_qdesn_bind_rows(list(vb_fit_scores$adjustment, mcmc_fit_scores$adjustment))
  forecast_adjustment <- app_joint_qdesn_bind_rows(list(vb_forecast_scores$adjustment, mcmc_forecast_scores$adjustment))

  max_sigma_upper_hit <- max(mcmc_result$draw_summary$upper_bound_hit_fraction[mcmc_result$draw_summary$block == "sigma"], na.rm = TRUE)
  max_sigma_lower_hit <- max(mcmc_result$draw_summary$lower_bound_hit_fraction[mcmc_result$draw_summary$block == "sigma"], na.rm = TRUE)
  summary <- cbind(
    mcmc_meta,
    data.frame(
      phase121_candidate_id = row$candidate_id[[1L]],
      phase121_selection_status = row$phase121_selection_status[[1L]],
      n_train = length(fixture$y),
      p = ncol(fixture$Z),
      K = length(fixture$tau),
      tau_grid = app_joint_qdesn_format_tau(fixture$tau),
      vb_converged = isTRUE(vb_fit$converged),
      vb_reached_max_iter = !isTRUE(vb_fit$converged),
      vb_adaptive_attempts = attr(vb_fit, "adaptive_vb_attempts") %||% as.character(controls$vb_max_iter),
      mcmc_n_chains = mcmc_controls$n_chains,
      mcmc_n_iter = mcmc_controls$mcmc_n_iter,
      mcmc_burn = mcmc_controls$mcmc_burn,
      mcmc_thin = mcmc_controls$mcmc_thin,
      mcmc_n_keep_total = nrow(mcmc_result$pooled$beta_draws),
      mcmc_init_source = mcmc_result$pooled$init_source,
      all_chain_init_source_provided = all(vapply(mcmc_result$fits, function(x) identical(x$init_source, "provided"), logical(1L))),
      mcmc_draws_all_finite = all(mcmc_result$draw_summary$all_finite),
      sigma_lower_bound = mcmc_result$sigma_bounds[[1L]],
      sigma_upper_bound = mcmc_result$sigma_bounds[[2L]],
      max_sigma_lower_bound_hit_fraction = max_sigma_lower_hit,
      max_sigma_upper_bound_hit_fraction = max_sigma_upper_hit,
      vb_fit_truth_mae = mean(vb_fit_scores$scored$truth_abs_error, na.rm = TRUE),
      mcmc_fit_truth_mae = mean(mcmc_fit_scores$scored$truth_abs_error, na.rm = TRUE),
      vb_forecast_truth_mae = mean(vb_forecast_scores$scored$truth_abs_error, na.rm = TRUE),
      mcmc_forecast_truth_mae = mean(mcmc_forecast_scores$scored$truth_abs_error, na.rm = TRUE),
      vb_fit_check_loss_mean = mean(vb_fit_scores$scored$check_loss, na.rm = TRUE),
      mcmc_fit_check_loss_mean = mean(mcmc_fit_scores$scored$check_loss, na.rm = TRUE),
      vb_forecast_check_loss_mean = mean(vb_forecast_scores$scored$check_loss, na.rm = TRUE),
      mcmc_forecast_check_loss_mean = mean(mcmc_forecast_scores$scored$check_loss, na.rm = TRUE),
      vb_fit_raw_crossing_pairs = sum(vb_fit_scores$contract_info$raw_crossing$n_crossing_pairs),
      mcmc_fit_raw_crossing_pairs = sum(mcmc_fit_scores$contract_info$raw_crossing$n_crossing_pairs),
      vb_forecast_raw_crossing_pairs = sum(forecast_raw_crossing$n_crossing_pairs[forecast_raw_crossing$inference != "MCMC"], na.rm = TRUE),
      mcmc_forecast_raw_crossing_pairs = sum(forecast_raw_crossing$n_crossing_pairs[forecast_raw_crossing$inference == "MCMC"], na.rm = TRUE),
      vb_fit_contract_crossing_pairs = sum(vb_fit_scores$contract_info$contract_crossing$n_crossing_pairs),
      mcmc_fit_contract_crossing_pairs = sum(mcmc_fit_scores$contract_info$contract_crossing$n_crossing_pairs),
      vb_forecast_contract_crossing_pairs = sum(forecast_contract_crossing$n_crossing_pairs[forecast_contract_crossing$inference != "MCMC"], na.rm = TRUE),
      mcmc_forecast_contract_crossing_pairs = sum(forecast_contract_crossing$n_crossing_pairs[forecast_contract_crossing$inference == "MCMC"], na.rm = TRUE),
      vb_fit_max_abs_adjustment = max(abs(vb_fit_scores$adjustment$adjustment), na.rm = TRUE),
      mcmc_fit_max_abs_adjustment = max(abs(mcmc_fit_scores$adjustment$adjustment), na.rm = TRUE),
      vb_forecast_max_abs_adjustment = max(abs(vb_forecast_scores$adjustment$adjustment), na.rm = TRUE),
      mcmc_forecast_max_abs_adjustment = max(abs(mcmc_forecast_scores$adjustment$adjustment), na.rm = TRUE),
      vb_mcmc_max_normalized_distance = mcmc_result$distance$max_normalized_distance[[1L]],
      max_chain_to_pooled_normalized_distance = max(mcmc_result$chain_distance$max_normalized_to_pooled, na.rm = TRUE),
      vb_elapsed_seconds = vb_elapsed,
      mcmc_elapsed_seconds = mcmc_result$elapsed_seconds,
      total_elapsed_seconds = vb_elapsed + mcmc_result$elapsed_seconds,
      stringsAsFactors = FALSE
    )
  )

  list(
    summary = summary,
    fit_quantiles_raw = app_joint_qdesn_bind_rows(list(vb_fit_scores$raw, mcmc_fit_scores$raw)),
    fit_quantiles = fit_scored,
    fit_adjustment = fit_adjustment,
    forecast_quantiles_raw = app_joint_qdesn_bind_rows(list(vb_forecast_scores$raw, mcmc_forecast_scores$raw)),
    forecast_quantiles = forecast_scored,
    forecast_adjustment = forecast_adjustment,
    crossing = app_joint_qdesn_bind_rows(list(fit_contract_crossing, forecast_contract_crossing)),
    raw_crossing = app_joint_qdesn_bind_rows(list(fit_raw_crossing, forecast_raw_crossing)),
    vb_convergence = app_joint_qdesn_vb_convergence_row(vb_fit, vb_meta, controls),
    objective = app_joint_qdesn_objective_row(vb_fit, vb_meta),
    rhs = app_joint_qdesn_rhs_rows(vb_fit, vb_meta),
    scale = app_joint_qdesn_scale_summary_rows(vb_fit, fixture, vb_meta),
    draw_summary = cbind(mcmc_meta, mcmc_result$draw_summary, stringsAsFactors = FALSE),
    distance = cbind(mcmc_meta, mcmc_result$distance, stringsAsFactors = FALSE),
    chain_distance = cbind(mcmc_meta, mcmc_result$chain_distance, stringsAsFactors = FALSE),
    runtime = app_joint_qdesn_bind_rows(list(
      cbind(vb_meta, data.frame(runtime_component = "vb_fit", chain_id = NA_integer_, chain_seed = NA_integer_, elapsed_seconds = vb_elapsed, sec_per_iter = NA_real_, stringsAsFactors = FALSE)),
      cbind(mcmc_meta, mcmc_result$runtime, stringsAsFactors = FALSE),
      cbind(mcmc_meta, data.frame(runtime_component = "mcmc_total", chain_id = NA_integer_, chain_seed = NA_integer_, elapsed_seconds = mcmc_result$elapsed_seconds, sec_per_iter = mcmc_result$elapsed_seconds / max(1L, mcmc_controls$mcmc_n_iter * mcmc_controls$n_chains), stringsAsFactors = FALSE))
    ))
  )
}

app_joint_qdesn_phase122_assessment <- function(summary, worker_failures, phase121_manifest, fixture_manifest, distance_pass, chain_pass, adjustment_review = 1.0e-3) {
  if (!nrow(summary)) return(data.frame())
  source_ok <- all(phase121_manifest$status == "pass") && all(fixture_manifest$status == "pass")
  worker_ok <- !nrow(worker_failures)
  rows <- lapply(seq_len(nrow(summary)), function(ii) {
    x <- summary[ii, , drop = FALSE]
    contract_crossings <- sum(
      x$vb_fit_contract_crossing_pairs,
      x$mcmc_fit_contract_crossing_pairs,
      x$vb_forecast_contract_crossing_pairs,
      x$mcmc_forecast_contract_crossing_pairs,
      na.rm = TRUE
    )
    raw_crossings <- sum(
      x$vb_fit_raw_crossing_pairs,
      x$mcmc_fit_raw_crossing_pairs,
      x$vb_forecast_raw_crossing_pairs,
      x$mcmc_forecast_raw_crossing_pairs,
      na.rm = TRUE
    )
    max_adjustment <- max(
      x$vb_fit_max_abs_adjustment,
      x$mcmc_fit_max_abs_adjustment,
      x$vb_forecast_max_abs_adjustment,
      x$mcmc_forecast_max_abs_adjustment,
      na.rm = TRUE
    )
    finite_required <- all(is.finite(c(
      x$mcmc_n_keep_total,
      x$vb_fit_truth_mae,
      x$mcmc_fit_truth_mae,
      x$vb_forecast_truth_mae,
      x$mcmc_forecast_truth_mae,
      x$vb_mcmc_max_normalized_distance,
      x$max_chain_to_pooled_normalized_distance,
      x$total_elapsed_seconds
    )))
    hard_fail <- !source_ok || !worker_ok || !finite_required ||
      !isTRUE(x$all_chain_init_source_provided[[1L]]) ||
      !isTRUE(x$mcmc_draws_all_finite[[1L]]) ||
      contract_crossings > 0L
    review <- !hard_fail && (
      isTRUE(x$vb_reached_max_iter[[1L]]) ||
        raw_crossings > 0L ||
        max_adjustment > adjustment_review ||
        x$max_sigma_lower_bound_hit_fraction[[1L]] > 0 ||
        x$max_sigma_upper_bound_hit_fraction[[1L]] > 0 ||
        x$vb_mcmc_max_normalized_distance[[1L]] > distance_pass ||
        x$max_chain_to_pooled_normalized_distance[[1L]] > chain_pass
    )
    reasons <- c(
      if (!source_ok) "source manifest verification failed",
      if (!worker_ok) "one or more case workers failed",
      if (!finite_required) "nonfinite required MCMC metric",
      if (!isTRUE(x$all_chain_init_source_provided[[1L]])) "MCMC did not use provided VB initialization",
      if (!isTRUE(x$mcmc_draws_all_finite[[1L]])) "nonfinite MCMC draws",
      if (contract_crossings > 0L) "contract quantiles crossed",
      if (!hard_fail && isTRUE(x$vb_reached_max_iter[[1L]])) "VB initialization reached max iterations",
      if (!hard_fail && raw_crossings > 0L) "raw quantiles crossed before monotone contract",
      if (!hard_fail && max_adjustment > adjustment_review) "monotone adjustment exceeds review threshold",
      if (!hard_fail && (x$max_sigma_lower_bound_hit_fraction[[1L]] > 0 || x$max_sigma_upper_bound_hit_fraction[[1L]] > 0)) "sigma bound hit requires review",
      if (!hard_fail && x$vb_mcmc_max_normalized_distance[[1L]] > distance_pass) "VB/MCMC distance requires review",
      if (!hard_fail && x$max_chain_to_pooled_normalized_distance[[1L]] > chain_pass) "chain-to-pooled distance requires review"
    )
    cbind(x[, c("case_id", "scenario_id", "scenario_class", "distribution_family", "dynamics_class", "source_model_id", "model_id", "display_label", "likelihood", "fit_structure"), drop = FALSE], data.frame(
      implementation_status = if (hard_fail) "fail" else "pass",
      distance_status = if (is.finite(x$vb_mcmc_max_normalized_distance[[1L]]) && x$vb_mcmc_max_normalized_distance[[1L]] <= distance_pass) "pass" else "review",
      chain_status = if (is.finite(x$max_chain_to_pooled_normalized_distance[[1L]]) && x$max_chain_to_pooled_normalized_distance[[1L]] <= chain_pass) "pass" else "review",
      raw_crossing_status = if (raw_crossings > 0L) "review" else "pass",
      gate_status = if (hard_fail) "fail" else if (review) "review" else "pass",
      contract_crossing_pairs = contract_crossings,
      raw_crossing_pairs = raw_crossings,
      max_abs_adjustment = max_adjustment,
      status_reason = if (length(reasons)) paste(reasons, collapse = "; ") else "all Phase 122 gates passed",
      stringsAsFactors = FALSE
    ))
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase122_readme <- function(run_config, assessment) {
  c(
    "# Joint QDESN Phase 122 MCMC Case Confirmation",
    "",
    "This directory contains case-specific MCMC confirmation artifacts initialized from the Phase 121 VB/VB-LD winners.",
    "The validation target is the posterior quantile/readout grid, not a scalar posterior predictive density.",
    "",
    sprintf("- Phase 121 source: `%s`", run_config$phase121_dir[[1L]]),
    sprintf("- Fixture directory: `%s`", run_config$fixture_dir[[1L]]),
    sprintf("- Cases: %s", run_config$n_cases[[1L]]),
    sprintf("- MCMC chains: %s", run_config$mcmc_n_chains[[1L]]),
    sprintf("- MCMC iterations/burn/thin: %s/%s/%s", run_config$mcmc_n_iter[[1L]], run_config$mcmc_burn[[1L]], run_config$mcmc_thin[[1L]]),
    "",
    "Raw MCMC quantiles are preserved. Scoring uses monotone contract quantiles.",
    "Independent rows are sampled one quantile at a time and stitched into a quantile grid for scoring, matching their independent single-quantile model contract.",
    "",
    "Gate counts:",
    paste(capture.output(print(table(assessment$gate_status))), collapse = "\n")
  )
}

app_joint_qdesn_run_phase122_mcmc_case_confirmation <- function(
  out_dir = app_joint_qdesn_default_phase122_mcmc_case_confirmation_dir(),
  phase121_dir = app_joint_qdesn_default_phase121_case_vb_freeze_dir_fallback(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  case_ids = NULL,
  scenario_ids = NULL,
  model_ids = NULL,
  scenario_limit_per_model = NULL,
  n_chains = 2L,
  mcmc_n_iter = 80L,
  mcmc_burn = 40L,
  mcmc_thin = 5L,
  mcmc_seed_offset = 4100L,
  chain_seed_stride = 100L,
  sigma_upper_multiplier = 50,
  distance_pass = 5,
  chain_pass = 5,
  n_cores = 1L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  phase121 <- app_joint_qdesn_phase122_load_phase121(phase121_dir)
  artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)
  controls <- app_joint_qdesn_phase122_filter_controls(
    phase121$controls,
    case_ids = case_ids,
    scenario_ids = scenario_ids,
    model_ids = model_ids,
    scenario_limit_per_model = scenario_limit_per_model
  )
  mcmc_controls <- app_joint_qdesn_mcmc_readiness_controls(
    n_chains = n_chains,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin,
    mcmc_seed_offset = mcmc_seed_offset,
    chain_seed_stride = chain_seed_stride,
    sigma_upper_multiplier = sigma_upper_multiplier,
    distance_pass = distance_pass,
    chain_pass = chain_pass,
    n_cores = n_cores
  )
  row_by_case <- split(controls, controls$case_id)
  results <- app_joint_qdesn_parallel_lapply(
    names(row_by_case),
    function(cid) app_joint_qdesn_phase122_one_case(artifacts, row_by_case[[cid]], mcmc_controls),
    mcmc_controls$n_cores
  )
  worker_failures <- app_joint_qdesn_worker_failure_rows(results, "phase122_mcmc_case_confirmation")
  successful <- app_joint_qdesn_successful_worker_results(results, "phase122_mcmc_case_confirmation")

  summary <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "summary"))
  fit_raw <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "fit_quantiles_raw"))
  fit_quantiles <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "fit_quantiles"))
  fit_adjustment <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "fit_adjustment"))
  forecast_raw <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "forecast_quantiles_raw"))
  forecast_quantiles <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "forecast_quantiles"))
  forecast_adjustment <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "forecast_adjustment"))
  crossing <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "crossing"))
  raw_crossing <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "raw_crossing"))
  vb_convergence <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "vb_convergence"))
  objective <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "objective"))
  rhs <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "rhs"))
  scale <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "scale"))
  draw_summary <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "draw_summary"))
  distance <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "distance"))
  chain_distance <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "chain_distance"))
  runtime <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "runtime"))

  assessment <- app_joint_qdesn_phase122_assessment(
    summary = summary,
    worker_failures = worker_failures,
    phase121_manifest = phase121$manifest_verification,
    fixture_manifest = artifacts$manifest_verification,
    distance_pass = distance_pass,
    chain_pass = chain_pass
  )
  fit_truth_summary <- app_joint_qdesn_truth_summary(fit_quantiles)
  forecast_truth_summary <- app_joint_qdesn_truth_summary(forecast_quantiles)
  fit_check_loss_summary <- app_joint_qdesn_check_loss_summary(fit_quantiles)
  forecast_check_loss_summary <- app_joint_qdesn_check_loss_summary(forecast_quantiles)
  fit_hit_rate_summary <- app_joint_qdesn_hit_rate_summary(fit_quantiles)
  forecast_hit_rate_summary <- app_joint_qdesn_hit_rate_summary(forecast_quantiles)
  fit_crps_summary <- app_joint_qdesn_crps_grid_summary(fit_quantiles, "qhat")
  forecast_crps_summary <- app_joint_qdesn_crps_grid_summary(forecast_quantiles, "qhat")
  fit_interval_summary <- app_joint_qdesn_interval_summary(fit_quantiles, "qhat")
  forecast_interval_summary <- app_joint_qdesn_interval_summary(forecast_quantiles, "qhat")

  run_config <- data.frame(
    run_id = "joint_qdesn_phase122_mcmc_case_confirmation",
    out_dir = out_dir,
    phase121_dir = phase121$phase121_dir,
    fixture_dir = artifacts$fixture_dir,
    case_ids = paste(controls$case_id, collapse = ","),
    scenario_ids = paste(unique(controls$scenario_ids), collapse = ","),
    model_ids = paste(unique(controls$model_ids), collapse = ","),
    n_cases = nrow(controls),
    scenario_limit_per_model = scenario_limit_per_model %||% NA_integer_,
    mcmc_n_chains = mcmc_controls$n_chains,
    mcmc_n_iter = mcmc_controls$mcmc_n_iter,
    mcmc_burn = mcmc_controls$mcmc_burn,
    mcmc_thin = mcmc_controls$mcmc_thin,
    mcmc_seed_offset = mcmc_controls$mcmc_seed_offset,
    chain_seed_stride = mcmc_controls$chain_seed_stride,
    sigma_upper_multiplier = mcmc_controls$sigma_upper_multiplier,
    distance_pass = distance_pass,
    chain_pass = chain_pass,
    n_cores = mcmc_controls$n_cores,
    validation_contract = "quantile_grid_readout_fit_and_no_refit_forecast",
    scalar_predictive_density_claim = FALSE,
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qdesn_phase122_readme(run_config, assessment), readme_path, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    phase121_source_manifest_verification = app_joint_qvp_write_csv(phase121$manifest_verification, file.path(out_dir, "phase121_source_manifest_verification.csv")),
    fixture_source_manifest = app_joint_qvp_write_csv(artifacts$manifest_verification, file.path(out_dir, "fixture_source_manifest.csv")),
    case_winner_controls = app_joint_qvp_write_csv(controls, file.path(out_dir, "case_winner_controls.csv")),
    scenario_worker_failures = app_joint_qvp_write_csv(worker_failures, file.path(out_dir, "scenario_worker_failures.csv")),
    mcmc_case_summary = app_joint_qvp_write_csv(summary, file.path(out_dir, "mcmc_case_summary.csv")),
    mcmc_case_assessment = app_joint_qvp_write_csv(assessment, file.path(out_dir, "mcmc_case_assessment.csv")),
    fit_quantiles_raw = app_joint_qvp_write_csv(fit_raw, file.path(out_dir, "fit_quantiles_raw.csv")),
    fit_quantiles = app_joint_qvp_write_csv(fit_quantiles, file.path(out_dir, "fit_quantiles.csv")),
    fit_monotone_adjustment = app_joint_qvp_write_csv(fit_adjustment, file.path(out_dir, "fit_monotone_adjustment.csv")),
    fit_truth_comparison = app_joint_qvp_write_csv(fit_quantiles, file.path(out_dir, "fit_truth_comparison.csv")),
    forecast_quantiles_raw = app_joint_qvp_write_csv(forecast_raw, file.path(out_dir, "forecast_quantiles_raw.csv")),
    forecast_quantiles = app_joint_qvp_write_csv(forecast_quantiles, file.path(out_dir, "forecast_quantiles.csv")),
    forecast_monotone_adjustment = app_joint_qvp_write_csv(forecast_adjustment, file.path(out_dir, "forecast_monotone_adjustment.csv")),
    forecast_truth_comparison = app_joint_qvp_write_csv(forecast_quantiles, file.path(out_dir, "forecast_truth_comparison.csv")),
    fit_truth_distance_summary = app_joint_qvp_write_csv(fit_truth_summary, file.path(out_dir, "fit_truth_distance_summary.csv")),
    forecast_truth_distance_summary = app_joint_qvp_write_csv(forecast_truth_summary, file.path(out_dir, "forecast_truth_distance_summary.csv")),
    fit_check_loss_summary = app_joint_qvp_write_csv(fit_check_loss_summary, file.path(out_dir, "fit_check_loss_summary.csv")),
    forecast_check_loss_summary = app_joint_qvp_write_csv(forecast_check_loss_summary, file.path(out_dir, "forecast_check_loss_summary.csv")),
    fit_hit_rate_summary = app_joint_qvp_write_csv(fit_hit_rate_summary, file.path(out_dir, "fit_hit_rate_summary.csv")),
    forecast_hit_rate_summary = app_joint_qvp_write_csv(forecast_hit_rate_summary, file.path(out_dir, "forecast_hit_rate_summary.csv")),
    fit_crps_grid_summary = app_joint_qvp_write_csv(fit_crps_summary, file.path(out_dir, "fit_crps_grid_summary.csv")),
    forecast_crps_grid_summary = app_joint_qvp_write_csv(forecast_crps_summary, file.path(out_dir, "forecast_crps_grid_summary.csv")),
    fit_interval_summary = app_joint_qvp_write_csv(fit_interval_summary, file.path(out_dir, "fit_interval_summary.csv")),
    forecast_interval_summary = app_joint_qvp_write_csv(forecast_interval_summary, file.path(out_dir, "forecast_interval_summary.csv")),
    crossing_summary = app_joint_qvp_write_csv(crossing, file.path(out_dir, "crossing_summary.csv")),
    raw_crossing_summary = app_joint_qvp_write_csv(raw_crossing, file.path(out_dir, "raw_crossing_summary.csv")),
    vb_convergence_audit = app_joint_qvp_write_csv(vb_convergence, file.path(out_dir, "vb_convergence_audit.csv")),
    objective_diagnostics = app_joint_qvp_write_csv(objective, file.path(out_dir, "objective_diagnostics.csv")),
    rhs_prior_summary = app_joint_qvp_write_csv(rhs, file.path(out_dir, "rhs_prior_summary.csv")),
    scale_parameter_summary = app_joint_qvp_write_csv(scale, file.path(out_dir, "scale_parameter_summary.csv")),
    mcmc_draw_summary = app_joint_qvp_write_csv(draw_summary, file.path(out_dir, "mcmc_draw_summary.csv")),
    vb_mcmc_distance_summary = app_joint_qvp_write_csv(distance, file.path(out_dir, "vb_mcmc_distance_summary.csv")),
    chain_to_pooled_distance_summary = app_joint_qvp_write_csv(chain_distance, file.path(out_dir, "chain_to_pooled_distance_summary.csv")),
    runtime_summary = app_joint_qvp_write_csv(runtime, file.path(out_dir, "runtime_summary.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    paths = c(paths, artifact_manifest = manifest_info$manifest_path),
    manifest = manifest_info$manifest,
    run_config = run_config,
    summary = summary,
    assessment = assessment,
    worker_failures = worker_failures
  )
}
