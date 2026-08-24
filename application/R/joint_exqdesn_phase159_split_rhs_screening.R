# Phase159: case-specific split anchor/innovation RHS MCMC calibration.

app_joint_exqdesn_phase159_default_freeze_dir <- function() {
  app_path("application/cache/joint_qdesn_phase159_split_rhs_calibration_freeze_20260804")
}

app_joint_exqdesn_phase159_default_output_dir <- function() {
  app_path("application/cache/joint_qdesn_phase159_split_rhs_calibration_mcmc_20260804")
}

app_joint_exqdesn_phase159_source_snapshot <- function() {
  relative_path <- c(
    "application/R/joint_qvp_qdesn.R",
    "application/R/joint_exqdesn_phase156_collapsed_gamma_sigma.R",
    "application/R/joint_exqdesn_phase158_fan_audit.R",
    "application/R/joint_exqdesn_phase159_split_rhs_screening.R",
    "application/scripts/197_prepare_joint_exqdesn_phase159_split_rhs.R",
    "application/scripts/198_run_joint_exqdesn_phase159_worker.R",
    "application/scripts/199_finalize_joint_exqdesn_phase159_split_rhs.R",
    "application/scripts/200_check_joint_exqdesn_phase159_split_rhs.R",
    "application/scripts/201_launch_joint_exqdesn_phase159_split_rhs.sh",
    "application/tests/test_joint_exqdesn_phase158_159.R"
  )
  full_path <- app_path(relative_path)
  data.frame(
    relative_path = relative_path,
    size_bytes = as.numeric(file.info(full_path)$size),
    sha256 = vapply(full_path, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase159_default_orchestration_dir <- function() {
  app_path("application/cache/joint_qdesn_phase159_split_rhs_calibration_mcmc_20260804_orchestration")
}

app_joint_exqdesn_phase159_slug <- function(x) {
  gsub("\\.", "p", format(as.numeric(x), trim = TRUE, scientific = FALSE))
}

app_joint_exqdesn_phase159_registry <- function(phase158_dir, phase156b_dir, output_dir) {
  diagnosis <- app_joint_exqdesn_phase156_read_csv(file.path(phase158_dir, "scenario_diagnosis.csv"))
  base <- app_joint_exqdesn_phase156_read_csv(file.path(phase156b_dir, "case_winner_controls.csv"))
  diagnosis <- diagnosis[diagnosis$decision == "target_split_rhs_calibration", , drop = FALSE]
  if (nrow(diagnosis) != 6L || anyDuplicated(diagnosis$scenario_id)) {
    stop("Phase159 requires exactly six unique split-RHS calibration scenarios.", call. = FALSE)
  }
  rows <- list()
  for (ii in seq_len(nrow(diagnosis))) {
    scenario_id <- diagnosis$scenario_id[[ii]]
    control <- base[base$scenario_ids == scenario_id, , drop = FALSE]
    if (nrow(control) != 1L) stop(sprintf("Missing Phase159 base control for '%s'.", scenario_id), call. = FALSE)
    multipliers <- as.numeric(strsplit(diagnosis$recommended_innovation_tau0_multipliers[[ii]], ",", fixed = TRUE)[[1L]])
    multipliers <- unique(multipliers[is.finite(multipliers) & multipliers >= 1])
    if (length(multipliers) != 3L || multipliers[[1L]] != 1) {
      stop(sprintf("Malformed Phase159 multiplier recommendation for '%s'.", scenario_id), call. = FALSE)
    }
    candidate <- data.frame(
      candidate_role = c("same_contract_reference", paste0("innovation_tau0_x", app_joint_exqdesn_phase159_slug(multipliers[2:3])), "innovation_tau0_mid_zeta2_x2"),
      innovation_tau0_multiplier = c(1, multipliers[[2L]], multipliers[[3L]], multipliers[[2L]]),
      innovation_zeta2_multiplier = c(1, 1, 1, 2),
      stringsAsFactors = FALSE
    )
    for (jj in seq_len(nrow(candidate))) {
      row <- control
      row$anchor_tau0 <- as.numeric(control$tau0[[1L]])
      row$innovation_tau0 <- as.numeric(control$tau0[[1L]]) * candidate$innovation_tau0_multiplier[[jj]]
      row$anchor_zeta2 <- as.numeric(control$zeta2[[1L]])
      row$innovation_zeta2 <- as.numeric(control$zeta2[[1L]]) * candidate$innovation_zeta2_multiplier[[jj]]
      row$candidate_role <- candidate$candidate_role[[jj]]
      row$innovation_tau0_multiplier <- candidate$innovation_tau0_multiplier[[jj]]
      row$innovation_zeta2_multiplier <- candidate$innovation_zeta2_multiplier[[jj]]
      row$candidate_id <- paste(
        scenario_id, "phase159", row$candidate_role,
        paste0("anchor_tau0_", app_joint_exqdesn_phase159_slug(row$anchor_tau0)),
        paste0("innovation_tau0_", app_joint_exqdesn_phase159_slug(row$innovation_tau0)),
        paste0("anchor_zeta2_", app_joint_exqdesn_phase159_slug(row$anchor_zeta2)),
        paste0("innovation_zeta2_", app_joint_exqdesn_phase159_slug(row$innovation_zeta2)),
        sep = "__"
      )
      row$worker_root <- file.path(output_dir, "candidates", scenario_id, row$candidate_role)
      row$phase159_diagnosis <- diagnosis$diagnosis[[ii]]
      rows[[length(rows) + 1L]] <- row
    }
  }
  registry <- app_joint_qdesn_bind_rows(rows)
  if (nrow(registry) != 24L || anyDuplicated(registry$candidate_id)) {
    stop("Phase159 registry must contain 24 unique case-specific candidates.", call. = FALSE)
  }
  numeric_positive <- c("anchor_tau0", "innovation_tau0", "anchor_zeta2", "innovation_zeta2")
  if (any(!vapply(registry[numeric_positive], function(x) all(is.finite(x) & x > 0), logical(1L)))) {
    stop("Phase159 split RHS controls must be positive and finite.", call. = FALSE)
  }
  registry
}

app_joint_exqdesn_phase159_vb_fit <- function(artifacts, row, frozen_init) {
  scenario_id <- row$scenario_ids[[1L]]
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
  init <- app_joint_exqdesn_phase156_init_from_rows(frozen_init, scenario_id)
  init <- list(beta = init$beta_mean, alpha = init$alpha_mean, sigma = init$sigma_mean, gamma = init$gamma_mean)
  max_iter <- max(1200L, as.integer(row$vb_max_iter[[1L]]))
  start <- proc.time()[["elapsed"]]
  fit <- app_joint_qvp_fit_exal_vb_ld_tiny(
    y = fixture$y, Z = fixture$Z, tau = fixture$tau,
    max_iter = max_iter, tol = as.numeric(row$vb_tol[[1L]]), kappa = 1,
    tau0 = as.numeric(row$tau0[[1L]]), zeta2 = as.numeric(row$zeta2[[1L]]),
    anchor_tau0 = as.numeric(row$anchor_tau0[[1L]]),
    innovation_tau0 = as.numeric(row$innovation_tau0[[1L]]),
    anchor_zeta2 = as.numeric(row$anchor_zeta2[[1L]]),
    innovation_zeta2 = as.numeric(row$innovation_zeta2[[1L]]),
    a_sigma = as.numeric(row$a_sigma[[1L]]), b_sigma = as.numeric(row$b_sigma[[1L]]),
    alpha_prior_mean = "empirical_quantile", alpha_prior_sd = as.numeric(row$alpha_prior_sd[[1L]]),
    alpha_min_spacing = as.numeric(row$alpha_min_spacing[[1L]]),
    max_dense_dim = as.integer(row$max_dense_dim[[1L]]),
    init = init, rhs_vb_inner = as.integer(row$rhs_vb_inner[[1L]])
  )
  elapsed <- proc.time()[["elapsed"]] - start
  blocks <- list(beta = fit$beta_mean, alpha = fit$alpha_mean, sigma = fit$sigma_mean, gamma = fit$gamma_mean)
  init_rows <- app_joint_qdesn_bind_rows(lapply(names(blocks), function(block) {
    data.frame(candidate_id = row$candidate_id[[1L]], scenario_id = scenario_id,
               parameter_block = block, parameter_index = seq_along(blocks[[block]]),
               value = as.numeric(blocks[[block]]), stringsAsFactors = FALSE)
  }))
  qhat <- app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau)
  score <- app_joint_qdesn_phase122_score_qhat(
    data.frame(scenario_id = scenario_id, candidate_id = row$candidate_id[[1L]], stringsAsFactors = FALSE),
    fixture, qhat, "qhat", "phase159_vb_fit"
  )
  list(
    init = init_rows,
    convergence = data.frame(
      candidate_id = row$candidate_id[[1L]], scenario_id = scenario_id,
      converged = isTRUE(fit$converged), reached_max_iter = !isTRUE(fit$converged),
      iterations = nrow(fit$trace), elapsed_seconds = elapsed,
      fit_truth_mae = mean(score$scored$truth_abs_error),
      fit_contract_crossing_pairs = sum(score$contract_info$contract_crossing$n_crossing_pairs),
      all_finite = all(is.finite(unlist(blocks, use.names = FALSE))),
      sigma_positive = all(fit$sigma_mean > 0), stringsAsFactors = FALSE
    )
  )
}

app_joint_exqdesn_phase159_prepare <- function(
  freeze_dir = app_joint_exqdesn_phase159_default_freeze_dir(),
  output_dir = app_joint_exqdesn_phase159_default_output_dir(),
  phase158_dir = app_joint_exqdesn_phase158_default_dir(),
  phase156b_dir = app_joint_exqdesn_phase158_default_freeze_dir(),
  n_chains = 4L, n_iter = 6000L, burn = 1500L, thin = 3L,
  workers = 24L, n_vb_cores = 12L
) {
  freeze_dir <- normalizePath(freeze_dir, mustWork = FALSE)
  output_dir <- normalizePath(output_dir, mustWork = FALSE)
  phase158_dir <- normalizePath(phase158_dir, mustWork = TRUE)
  phase156b_dir <- normalizePath(phase156b_dir, mustWork = TRUE)
  app_ensure_dir(freeze_dir)
  source_verification <- app_joint_qdesn_bind_rows(list(
    app_joint_exqdesn_phase158_verify_source(phase158_dir, "phase158"),
    app_joint_exqdesn_phase158_verify_source(phase156b_dir, "phase156b")
  ))
  phase158_assessment <- app_joint_exqdesn_phase156_read_csv(file.path(phase158_dir, "phase158_assessment.csv"))
  if (phase158_assessment$gate_status[[1L]] != "pass") stop("Phase159 blocked by Phase158 gate.", call. = FALSE)
  parent <- app_joint_exqdesn_phase157_load_freeze(phase156b_dir)
  registry <- app_joint_exqdesn_phase159_registry(phase158_dir, phase156b_dir, output_dir)
  artifacts <- app_joint_qdesn_load_fixture_artifacts(parent$config$fixture_dir[[1L]])
  jobs <- lapply(seq_len(nrow(registry)), function(ii) registry[ii, , drop = FALSE])
  fit_one <- function(row) app_joint_exqdesn_phase159_vb_fit(artifacts, row, parent$init)
  vb <- if (.Platform$OS.type != "windows" && n_vb_cores > 1L) {
    parallel::mclapply(jobs, fit_one, mc.cores = min(as.integer(n_vb_cores), length(jobs)), mc.preschedule = FALSE)
  } else lapply(jobs, fit_one)
  init <- app_joint_qdesn_bind_rows(lapply(vb, `[[`, "init"))
  convergence <- app_joint_qdesn_bind_rows(lapply(vb, `[[`, "convergence"))
  if (any(!convergence$all_finite) || any(!convergence$sigma_positive) || any(convergence$fit_contract_crossing_pairs > 0L)) {
    stop("Phase159 VB initialization failed implementation gates.", call. = FALSE)
  }
  plan <- list()
  worker_id <- 0L
  starts <- list()
  for (ii in seq_len(nrow(registry))) {
    row <- registry[ii, , drop = FALSE]
    scenario_id <- row$scenario_ids[[1L]]
    fixture <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
    get_init_block <- function(block) {
      x <- init[init$candidate_id == row$candidate_id[[1L]] & init$parameter_block == block, , drop = FALSE]
      x$value[order(x$parameter_index)]
    }
    init_case <- list(
      beta_mean = get_init_block("beta"), alpha_mean = get_init_block("alpha"),
      sigma_mean = get_init_block("sigma"), gamma_mean = get_init_block("gamma")
    )
    starts_case <- app_joint_exqdesn_phase156_chain_starts(init_case, fixture$tau, row$candidate_id[[1L]], n_chains)
    starts_case$candidate_id <- starts_case$scenario_id
    starts_case$scenario_id <- scenario_id
    starts[[ii]] <- starts_case
    base_seed <- as.integer(artifacts$scenario_summary$seed[artifacts$scenario_summary$scenario_id == scenario_id][[1L]])
    for (chain_id in seq_len(n_chains)) {
      worker_id <- worker_id + 1L
      plan[[worker_id]] <- data.frame(
        worker_id = worker_id, candidate_index = ii, candidate_id = row$candidate_id[[1L]],
        scenario_id = scenario_id, chain_id = chain_id,
        chain_seed = base_seed + 159000L + ii * 1000L + chain_id * 101L,
        n_iter = as.integer(n_iter), burn = as.integer(burn), thin = as.integer(thin),
        n_keep = as.integer((n_iter - burn) / thin),
        worker_output_dir = file.path(row$worker_root[[1L]], sprintf("chain_%02d", chain_id)),
        stringsAsFactors = FALSE
      )
    }
  }
  plan <- app_joint_qdesn_bind_rows(plan)
  starts <- app_joint_qdesn_bind_rows(starts)
  run_config <- data.frame(
    phase_id = "phase159_case_specific_split_rhs_calibration",
    phase158_dir = phase158_dir, phase156b_dir = phase156b_dir,
    fixture_dir = parent$config$fixture_dir[[1L]], output_dir = output_dir,
    scenarios = length(unique(registry$scenario_ids)), candidates = nrow(registry),
    candidates_per_scenario = 4L, n_chains = as.integer(n_chains),
    n_iter = as.integer(n_iter), burn = as.integer(burn), thin = as.integer(thin),
    workers = as.integer(workers), n_vb_cores = as.integer(n_vb_cores),
    gamma_update = "collapsed_logit_slice", gamma_slice_width = 4,
    gamma_slice_max_steps = 250L, retain_binary_objects = FALSE,
    selection_scope = "scenario_specific", article_assets_modified = FALSE,
    stringsAsFactors = FALSE
  )
  readiness <- data.frame(
    gate_status = "pass", scenarios = length(unique(registry$scenario_ids)),
    candidates = nrow(registry), planned_workers = nrow(plan),
    vb_initializations_finite = all(convergence$all_finite),
    source_hash_failures = sum(source_verification$status != "pass"),
    recommendation = "launch_phase159_parallel_mcmc_calibration", stringsAsFactors = FALSE
  )
  readme <- file.path(freeze_dir, "README.md")
  writeLines(c(
    "# Phase159 split-RHS calibration freeze", "",
    "This freeze contains four case-specific candidates for each of six underperforming Joint exQDESN scenarios.",
    "The anchor RHS controls remain frozen. Only the cross-quantile innovation tau0 and finite slab scale vary according to Phase158 compression severity.",
    "The campaign uses the validated collapsed gamma-sigma kernel. Persistent Heavy Tail and Asymmetric-Laplace Tail are not recalibrated.", "",
    sprintf("- Candidates: %d", nrow(registry)), sprintf("- Planned chains: %d", nrow(plan))
  ), readme, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(freeze_dir, "run_config.csv")),
    source_manifest_verification = app_joint_qvp_write_csv(source_verification, file.path(freeze_dir, "source_manifest_verification.csv")),
    candidate_registry = app_joint_qvp_write_csv(registry, file.path(freeze_dir, "candidate_registry.csv")),
    vb_initialization = app_joint_qvp_write_csv(init, file.path(freeze_dir, "vb_initialization.csv")),
    vb_convergence = app_joint_qvp_write_csv(convergence, file.path(freeze_dir, "vb_convergence.csv")),
    chain_start_values = app_joint_qvp_write_csv(starts, file.path(freeze_dir, "chain_start_values.csv")),
    chain_plan = app_joint_qvp_write_csv(plan, file.path(freeze_dir, "chain_plan.csv")),
    readiness_assessment = app_joint_qvp_write_csv(readiness, file.path(freeze_dir, "readiness_assessment.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(freeze_dir, "provenance.csv")),
    readme = normalizePath(readme, mustWork = TRUE)
  )
  paths <- c(paths, source_code_snapshot = app_joint_qvp_write_csv(
    app_joint_exqdesn_phase159_source_snapshot(), file.path(freeze_dir, "source_code_snapshot.csv")
  ))
  manifest <- app_joint_exqdesn_trace_manifest(paths, freeze_dir)
  list(freeze_dir = freeze_dir, registry = registry, plan = plan, readiness = readiness,
       paths = c(paths, artifact_manifest = manifest$manifest_path))
}

app_joint_exqdesn_phase159_load_freeze <- function(freeze_dir) {
  freeze_dir <- normalizePath(freeze_dir, mustWork = TRUE)
  verification <- app_joint_exqdesn_phase158_verify_source(freeze_dir, "phase159_freeze")
  list(
    dir = freeze_dir, verification = verification,
    config = app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "run_config.csv")),
    registry = app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "candidate_registry.csv")),
    init = app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "vb_initialization.csv")),
    starts = app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "chain_start_values.csv")),
    plan = app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "chain_plan.csv"))
  )
}

app_joint_exqdesn_phase159_worker_complete <- function(dir) {
  app_joint_exqdesn_phase157_worker_complete(dir)
}

app_joint_exqdesn_phase159_run_worker <- function(freeze_dir, worker_id) {
  freeze <- app_joint_exqdesn_phase159_load_freeze(freeze_dir)
  job <- freeze$plan[freeze$plan$worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(job) != 1L) stop("Unknown Phase159 worker.", call. = FALSE)
  out_dir <- job$worker_output_dir[[1L]]
  if (app_joint_exqdesn_phase159_worker_complete(out_dir)) return(list(status = "reused_verified", out_dir = out_dir))
  if (dir.exists(out_dir) && length(list.files(out_dir, all.files = TRUE, no.. = TRUE))) {
    quarantine <- paste0(out_dir, "_incomplete_", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(out_dir, quarantine)) stop("Could not quarantine incomplete Phase159 worker output.", call. = FALSE)
  }
  app_ensure_dir(out_dir)
  row <- freeze$registry[freeze$registry$candidate_id == job$candidate_id[[1L]], , drop = FALSE]
  artifacts <- app_joint_qdesn_load_fixture_artifacts(freeze$config$fixture_dir[[1L]])
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, job$scenario_id[[1L]], role = "fit")
  block <- function(name) {
    x <- freeze$init[freeze$init$candidate_id == job$candidate_id[[1L]] & freeze$init$parameter_block == name, , drop = FALSE]
    x$value[order(x$parameter_index)]
  }
  init <- list(beta_mean = block("beta"), alpha_mean = block("alpha"), sigma_mean = block("sigma"), gamma_mean = block("gamma"))
  starts <- freeze$starts[freeze$starts$candidate_id == job$candidate_id[[1L]] & freeze$starts$chain_id == job$chain_id[[1L]], , drop = FALSE]
  init$gamma_mean <- starts$value[starts$parameter == "gamma"][order(starts$quantile_index[starts$parameter == "gamma"])]
  init$sigma_mean <- starts$value[starts$parameter == "sigma"][order(starts$quantile_index[starts$parameter == "sigma"])]
  start <- proc.time()[["elapsed"]]
  fit <- app_joint_qvp_fit_exal_mcmc_tiny(
    y = fixture$y, Z = fixture$Z, tau = fixture$tau,
    n_iter = job$n_iter[[1L]], burn = job$burn[[1L]], thin = job$thin[[1L]], seed = job$chain_seed[[1L]],
    tau0 = row$tau0[[1L]], zeta2 = row$zeta2[[1L]],
    anchor_tau0 = row$anchor_tau0[[1L]], innovation_tau0 = row$innovation_tau0[[1L]],
    anchor_zeta2 = row$anchor_zeta2[[1L]], innovation_zeta2 = row$innovation_zeta2[[1L]],
    a_sigma = row$a_sigma[[1L]], b_sigma = row$b_sigma[[1L]],
    gamma_init = init$gamma_mean, init = init,
    alpha_prior_mean = "empirical_quantile", alpha_prior_sd = row$alpha_prior_sd[[1L]],
    alpha_min_spacing = row$alpha_min_spacing[[1L]], max_dense_dim = row$max_dense_dim[[1L]],
    sigma_bounds = c(1.0e-8, max(1, 50 * max(init$sigma_mean))),
    gamma_update = "collapsed_logit_slice", gamma_slice_width = 4,
    gamma_slice_max_steps = 250L, gamma_refresh_repeats = 1L, gamma_refresh_block = "none"
  )
  elapsed <- proc.time()[["elapsed"]] - start
  draws <- app_joint_exqdesn_phase157_draw_frame(fit)
  if (any(!is.finite(as.matrix(draws[, -1L, drop = FALSE]))) || any(fit$sigma_draws <= 0)) stop("Invalid Phase159 draws.", call. = FALSE)
  summary <- data.frame(
    worker_id = job$worker_id[[1L]], candidate_id = job$candidate_id[[1L]], scenario_id = job$scenario_id[[1L]],
    chain_id = job$chain_id[[1L]], chain_seed = job$chain_seed[[1L]], n_keep = nrow(draws),
    anchor_tau0 = row$anchor_tau0[[1L]], innovation_tau0 = row$innovation_tau0[[1L]],
    anchor_zeta2 = row$anchor_zeta2[[1L]], innovation_zeta2 = row$innovation_zeta2[[1L]],
    elapsed_seconds = elapsed, draws_all_finite = TRUE, stringsAsFactors = FALSE
  )
  sampler <- app_joint_qdesn_bind_rows(lapply(seq_along(fixture$tau), function(kk) data.frame(
    worker_id = job$worker_id[[1L]], candidate_id = job$candidate_id[[1L]], scenario_id = job$scenario_id[[1L]],
    chain_id = job$chain_id[[1L]], quantile_index = kk, tau = fixture$tau[[kk]],
    sigma_mean = mean(fit$sigma_draws[, kk]), gamma_mean = mean(fit$gamma_draws[, kk]),
    gamma_sigma_correlation = stats::cor(fit$gamma_draws[, kk], fit$sigma_draws[, kk]),
    gamma_rough_ess = app_joint_exqdesn_rough_ess_one_chain(fit$gamma_draws[, kk]),
    sigma_rough_ess = app_joint_exqdesn_rough_ess_one_chain(fit$sigma_draws[, kk]), stringsAsFactors = FALSE
  )))
  readme <- file.path(out_dir, "README.md")
  writeLines(c("# Phase159 chain", "", sprintf("- Candidate: `%s`", job$candidate_id[[1L]]), sprintf("- Chain: %d", job$chain_id[[1L]])), readme)
  paths <- c(
    posterior_draws = app_joint_exqdesn_phase157_write_gzip_csv(draws, file.path(out_dir, "posterior_draws.csv.gz")),
    chain_summary = app_joint_qvp_write_csv(summary, file.path(out_dir, "chain_summary.csv")),
    sampler_diagnostics = app_joint_qvp_write_csv(sampler, file.path(out_dir, "sampler_diagnostics.csv")),
    runtime = app_joint_qvp_write_csv(summary[, c("worker_id", "candidate_id", "scenario_id", "chain_id", "elapsed_seconds")], file.path(out_dir, "runtime.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_trace_manifest(paths, out_dir)
  list(status = "completed", out_dir = out_dir, paths = c(paths, artifact_manifest = manifest$manifest_path))
}

app_joint_exqdesn_phase159_health <- function(freeze_dir) {
  freeze <- app_joint_exqdesn_phase159_load_freeze(freeze_dir)
  state <- vapply(freeze$plan$worker_output_dir, function(dir) if (app_joint_exqdesn_phase159_worker_complete(dir)) "complete_verified" else "remaining", character(1L))
  inventory <- cbind(freeze$plan, state = state, stringsAsFactors = FALSE)
  summary <- data.frame(
    planned_workers = nrow(inventory), complete_verified = sum(state == "complete_verified"),
    remaining = sum(state == "remaining"), percent_complete = 100 * mean(state == "complete_verified"),
    all_complete = all(state == "complete_verified"), stringsAsFactors = FALSE
  )
  list(summary = summary, inventory = inventory)
}

app_joint_exqdesn_phase159_finalize <- function(freeze_dir, output_dir) {
  freeze <- app_joint_exqdesn_phase159_load_freeze(freeze_dir)
  health <- app_joint_exqdesn_phase159_health(freeze_dir)
  if (!health$summary$all_complete[[1L]]) stop("Phase159 cannot finalize before all workers verify.", call. = FALSE)
  output_dir <- normalizePath(output_dir, mustWork = TRUE)
  artifacts <- app_joint_qdesn_load_fixture_artifacts(freeze$config$fixture_dir[[1L]])
  results <- lapply(seq_len(nrow(freeze$registry)), function(ii) {
    row <- freeze$registry[ii, , drop = FALSE]
    jobs <- freeze$plan[freeze$plan$candidate_id == row$candidate_id[[1L]], , drop = FALSE]
    fixture <- app_joint_qdesn_scenario_fixture(artifacts, row$scenario_ids[[1L]], role = "fit")
    fits <- lapply(seq_len(nrow(jobs)), function(jj) app_joint_exqdesn_phase157_read_fit(
      jobs$worker_output_dir[[jj]], fixture$tau, jobs$chain_seed[[jj]], jobs$chain_id[[jj]]
    ))
    pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(fits, fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau)
    spec <- app_joint_qdesn_phase122_select_spec("joint_exqdesn_rhs_vb")
    meta <- app_joint_qdesn_phase122_meta(
      fixture, spec, row, "MCMC", "joint_exqdesn_rhs_mcmc_phase159"
    )
    fit <- app_joint_qdesn_phase122_score_qhat(meta, fixture, app_joint_qdesn_predict_fit(pooled, fixture$Z, fixture$tau), "qhat", "phase159_fit")
    forecast <- app_joint_qdesn_phase122_forecast_scores(meta, artifacts, row$scenario_ids[[1L]], fixture, pooled, "qhat", "phase159_forecast")
    modern <- app_joint_exqdesn_modern_diagnostic_rows(fits, fixture$tau, meta)
    data.frame(
      scenario_id = row$scenario_ids[[1L]], candidate_id = row$candidate_id[[1L]], candidate_role = row$candidate_role[[1L]],
      anchor_tau0 = row$anchor_tau0[[1L]], innovation_tau0 = row$innovation_tau0[[1L]],
      anchor_zeta2 = row$anchor_zeta2[[1L]], innovation_zeta2 = row$innovation_zeta2[[1L]],
      n_chains = length(fits), n_keep_total = nrow(pooled$beta_draws),
      fit_truth_mae = mean(fit$scored$truth_abs_error), forecast_truth_mae = mean(forecast$scored$truth_abs_error),
      forecast_check_loss = mean(forecast$scored$check_loss),
      forecast_crps_grid = app_joint_qdesn_crps_grid_summary(forecast$scored)$crps_grid_mean[[1L]],
      lower_tail_mae = mean(forecast$scored$truth_abs_error[forecast$scored$tau <= 0.10]),
      upper_tail_mae = mean(forecast$scored$truth_abs_error[forecast$scored$tau >= 0.90]),
      raw_crossing_pairs = sum(forecast$raw_crossing$n_crossing_pairs),
      contract_crossing_pairs = sum(forecast$contract_crossing$n_crossing_pairs),
      max_rank_rhat = max(modern$rank_rhat, na.rm = TRUE), min_bulk_ess = min(modern$bulk_ess, na.rm = TRUE),
      all_finite = all(is.finite(c(fit$scored$truth_abs_error, forecast$scored$truth_abs_error))),
      stringsAsFactors = FALSE
    )
  })
  summary <- app_joint_qdesn_bind_rows(results)
  ranking <- app_joint_qdesn_bind_rows(lapply(split(summary, summary$scenario_id), function(block) {
    ref <- block[block$candidate_role == "same_contract_reference", , drop = FALSE]
    block$delta_forecast_mae_vs_reference <- block$forecast_truth_mae - ref$forecast_truth_mae[[1L]]
    block$fit_guard_pass <- block$fit_truth_mae <= 1.05 * ref$fit_truth_mae[[1L]]
    block$score_guard_pass <- block$forecast_check_loss <= 1.02 * ref$forecast_check_loss[[1L]] & block$forecast_crps_grid <= 1.02 * ref$forecast_crps_grid[[1L]]
    block$implementation_status <- ifelse(block$all_finite & block$contract_crossing_pairs == 0L, "pass", "fail")
    block$eligible <- block$implementation_status == "pass" & block$fit_guard_pass & block$score_guard_pass &
      block$delta_forecast_mae_vs_reference <= -pmax(0.0025, 0.02 * ref$forecast_truth_mae[[1L]])
    block <- block[order(!block$eligible, block$forecast_truth_mae, block$upper_tail_mae), , drop = FALSE]
    block$scenario_rank <- seq_len(nrow(block))
    block
  }))
  selection <- app_joint_qdesn_bind_rows(lapply(split(ranking, ranking$scenario_id), function(block) {
    winner <- block[1L, , drop = FALSE]
    data.frame(
      scenario_id = winner$scenario_id, selected_candidate_id = winner$candidate_id,
      selected_role = winner$candidate_role, selected_forecast_truth_mae = winner$forecast_truth_mae,
      material_gain = isTRUE(winner$eligible),
      decision = if (isTRUE(winner$eligible)) "promote_to_full_eight_chain_confirmation" else "retain_phase157_specification",
      stringsAsFactors = FALSE
    )
  }))
  assessment <- data.frame(
    gate_status = if (all(summary$all_finite) && sum(summary$contract_crossing_pairs) == 0L) "pass" else "fail",
    scenarios = length(unique(summary$scenario_id)), candidates = nrow(summary), workers = nrow(freeze$plan),
    selected_for_confirmation = sum(selection$material_gain),
    recommendation = if (any(selection$material_gain)) "freeze_case_winners_and_run_eight_chain_confirmation" else "retain_phase157_and_stop_split_rhs_branch",
    stringsAsFactors = FALSE
  )
  worker_verification <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(freeze$plan)), function(ii) {
    app_joint_qdesn_phase108_manifest_verify(freeze$plan$worker_output_dir[[ii]], sprintf("worker_%03d", freeze$plan$worker_id[[ii]]))
  }))
  readme <- file.path(output_dir, "README.md")
  writeLines(c("# Phase159 split-RHS calibration results", "", "Candidates are ranked within scenario. This is calibration evidence, not article promotion."), readme)
  paths <- c(
    run_config = app_joint_qvp_write_csv(freeze$config, file.path(output_dir, "run_config.csv")),
    freeze_manifest_verification = app_joint_qvp_write_csv(freeze$verification, file.path(output_dir, "freeze_manifest_verification.csv")),
    worker_manifest_verification = app_joint_qvp_write_csv(worker_verification, file.path(output_dir, "worker_manifest_verification.csv")),
    chain_inventory = app_joint_qvp_write_csv(health$inventory, file.path(output_dir, "chain_inventory.csv")),
    candidate_summary = app_joint_qvp_write_csv(summary, file.path(output_dir, "candidate_summary.csv")),
    candidate_ranking = app_joint_qvp_write_csv(ranking, file.path(output_dir, "candidate_ranking.csv")),
    scenario_selection = app_joint_qvp_write_csv(selection, file.path(output_dir, "scenario_selection.csv")),
    phase159_assessment = app_joint_qvp_write_csv(assessment, file.path(output_dir, "phase159_assessment.csv")),
    finalizer_source_code_snapshot = app_joint_qvp_write_csv(
      app_joint_exqdesn_phase159_source_snapshot(),
      file.path(output_dir, "finalizer_source_code_snapshot.csv")
    ),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(output_dir, "provenance.csv")),
    readme = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_trace_manifest(paths, output_dir)
  list(assessment = assessment, selection = selection, paths = c(paths, artifact_manifest = manifest$manifest_path))
}
