# Phase 156/157: freeze case-specific VB initializations and run a resumable
# partially collapsed gamma-scale MCMC confirmation for Joint exQDESN.

app_joint_exqdesn_phase156_default_freeze_dir <- function() {
  app_path("application/cache/joint_qdesn_phase156_collapsed_gamma_sigma_freeze_20260731")
}

app_joint_exqdesn_phase157_default_output_dir <- function() {
  app_path("application/cache/joint_qdesn_phase157_collapsed_gamma_sigma_mcmc_20260731")
}

app_joint_exqdesn_phase156b_default_freeze_dir <- function() {
  app_path("application/cache/joint_qdesn_phase156b_collapsed_gamma_sigma_recovery_freeze_20260802")
}

app_joint_exqdesn_phase157b_default_output_dir <- function() {
  app_path("application/cache/joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802")
}

app_joint_exqdesn_phase156_required_freeze_files <- function() {
  c(
    "run_config.csv", "case_winner_controls.csv", "chain_plan.csv",
    "chain_start_values.csv", "vb_initialization.csv", "vb_convergence.csv",
    "source_manifest_verification.csv", "fixture_source_manifest.csv",
    "prior_contract_audit.csv", "kernel_contract_audit.csv", "provenance.csv",
    "source_code_snapshot.csv", "README.md", "artifact_manifest.csv"
  )
}

app_joint_exqdesn_phase156_read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

app_joint_exqdesn_phase156_init_rows <- function(fit, scenario_id) {
  blocks <- list(
    beta = as.numeric(fit$beta_mean),
    alpha = as.numeric(fit$alpha_mean),
    sigma = as.numeric(fit$sigma_mean),
    gamma = as.numeric(fit$gamma_mean)
  )
  app_joint_qdesn_bind_rows(lapply(names(blocks), function(block) {
    data.frame(
      scenario_id = scenario_id,
      parameter_block = block,
      parameter_index = seq_along(blocks[[block]]),
      value = blocks[[block]],
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase156_init_from_rows <- function(rows, scenario_id) {
  rows <- rows[rows$scenario_id == scenario_id, , drop = FALSE]
  get_block <- function(block) {
    x <- rows[rows$parameter_block == block, , drop = FALSE]
    x <- x[order(x$parameter_index), , drop = FALSE]
    as.numeric(x$value)
  }
  out <- list(
    beta_mean = get_block("beta"),
    alpha_mean = get_block("alpha"),
    sigma_mean = get_block("sigma"),
    gamma_mean = get_block("gamma")
  )
  if (!length(out$beta_mean) || !length(out$alpha_mean) ||
      !length(out$sigma_mean) || !length(out$gamma_mean) ||
      any(!is.finite(unlist(out, use.names = FALSE))) ||
      any(out$sigma_mean <= 0)) {
    stop(sprintf("Malformed Phase156 VB initialization for '%s'.", scenario_id), call. = FALSE)
  }
  out
}

app_joint_exqdesn_phase156_chain_starts <- function(vb_fit, tau, scenario_id, n_chains) {
  support <- app_joint_qvp_exal_support(tau)
  lower <- as.numeric(support$lower)
  upper <- as.numeric(support$upper)
  eta_base <- mapply(app_joint_qvp_gamma_to_eta, vb_fit$gamma_mean, lower, upper)
  centered <- if (n_chains == 1L) 0 else seq(-1.5, 1.5, length.out = n_chains)
  rows <- list()
  for (chain_id in seq_len(n_chains)) {
    phase <- 2 * pi * (seq_along(tau) - 1L) / length(tau)
    eta_offset <- 0.65 * centered[[chain_id]] * cos(phase + chain_id * pi / 4)
    eta <- eta_base + eta_offset
    gamma <- mapply(app_joint_qvp_eta_to_gamma, eta, lower, upper)
    log_sigma_offset <- -0.20 * centered[[chain_id]] * cos(phase + chain_id * pi / 4)
    sigma <- as.numeric(vb_fit$sigma_mean) * exp(log_sigma_offset)
    rows[[chain_id]] <- rbind(
      data.frame(
        scenario_id = scenario_id, chain_id = chain_id,
        parameter = "gamma", quantile_index = seq_along(tau), tau = tau,
        value = gamma, offset = eta_offset, offset_scale = "logit_gamma",
        stringsAsFactors = FALSE
      ),
      data.frame(
        scenario_id = scenario_id, chain_id = chain_id,
        parameter = "sigma", quantile_index = seq_along(tau), tau = tau,
        value = sigma, offset = log_sigma_offset, offset_scale = "log_sigma",
        stringsAsFactors = FALSE
      )
    )
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase156_kernel_audit <- function() {
  set.seed(156157L)
  n <- 18L
  y <- stats::rnorm(n)
  fitted <- seq(-0.2, 0.2, length.out = n)
  s <- abs(stats::rnorm(n)) + 0.05
  v <- abs(stats::rnorm(n)) + 0.05
  tau <- 0.1
  gamma <- 0
  terms <- app_joint_qvp_exal_sigma_gig_terms(
    gamma, y, fitted, -0.1, s, v, tau, 1, a_sigma = 2, b_sigma = 1
  )
  sigmas <- exp(seq(log(0.05), log(3), length.out = 11L))
  direct <- vapply(sigmas, function(sigma) {
    app_joint_qvp_exal_sigma_gamma_log_kernel(
      sigma, gamma, y, fitted, -0.1, s, v, tau, 1,
      a_sigma = 2, b_sigma = 1
    )
  }, numeric(1L))
  gig <- (terms$lambda - 1) * log(sigmas) -
    0.5 * (terms$chi / sigmas + terms$psi * sigmas)
  residual <- (direct - gig) - (direct[[1L]] - gig[[1L]])
  collapsed <- app_joint_qvp_exal_gamma_collapsed_log_kernel(
    gamma, y, fitted, -0.1, s, v, tau, 1, a_sigma = 2, b_sigma = 1
  )
  data.frame(
    audit_id = "collapsed_gamma_sigma_algebra",
    max_absolute_decomposition_residual = max(abs(residual)),
    collapsed_log_kernel_finite = is.finite(collapsed),
    gig_lambda = terms$lambda,
    gig_chi = terms$chi,
    gig_psi = terms$psi,
    status = if (max(abs(residual)) <= 1.0e-8 && is.finite(collapsed)) "pass" else "fail",
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase156_source_verification <- function(phase150_freeze_dir, fixture_dir) {
  freeze <- app_joint_qdesn_phase108_manifest_verify(phase150_freeze_dir, "phase150_case_specific_freeze")
  fixture <- app_joint_qdesn_phase108_manifest_verify(fixture_dir, "joint_simulation_fixture")
  if (any(freeze$status != "pass") || any(fixture$status != "pass")) {
    stop("Phase156 source manifest verification failed.", call. = FALSE)
  }
  list(freeze = freeze, fixture = fixture)
}

app_joint_exqdesn_phase156_attach_code_snapshot <- function(freeze_dir, repo_root = app_repo_root()) {
  freeze_dir <- normalizePath(freeze_dir, mustWork = TRUE)
  repo_root <- normalizePath(repo_root, mustWork = TRUE)
  relative <- c(
    "application/R/joint_qvp_qdesn.R",
    "application/R/joint_qdesn_mcmc_readiness.R",
    "application/R/joint_exqdesn_phase136_gamma_kernel_packet.R",
    "application/R/joint_exqdesn_trace_tools.R",
    "application/R/joint_exqdesn_phase156_collapsed_gamma_sigma.R",
    "application/scripts/189_prepare_joint_exqdesn_phase156_collapsed_gamma_sigma.R",
    "application/scripts/190_run_joint_exqdesn_phase157_chain.R",
    "application/scripts/191_launch_joint_exqdesn_phase157_collapsed_gamma_sigma.sh",
    "application/scripts/192_check_joint_exqdesn_phase157_collapsed_gamma_sigma.R",
    "application/scripts/193_finalize_joint_exqdesn_phase157_collapsed_gamma_sigma.R",
    "application/scripts/194_amend_joint_exqdesn_phase156b_collapsed_gamma_sigma.R",
    "application/scripts/195_preflight_joint_exqdesn_phase157b_worker_lifecycle.R",
    "application/tests/test_joint_qvp_qdesn_exal_mcmc.R",
    "application/tests/test_joint_exqdesn_phase156_collapsed_gamma_sigma.R"
  )
  full <- file.path(repo_root, relative)
  if (any(!file.exists(full))) {
    stop(sprintf("Cannot snapshot missing Phase156/157 source files: %s", paste(relative[!file.exists(full)], collapse = ", ")), call. = FALSE)
  }
  snapshot <- data.frame(
    relative_path = relative,
    size_bytes = as.numeric(file.info(full)$size),
    sha256 = vapply(full, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  snapshot_path <- app_joint_qvp_write_csv(snapshot, file.path(freeze_dir, "source_code_snapshot.csv"))
  artifact_files <- list.files(freeze_dir, full.names = TRUE, recursive = FALSE)
  artifact_files <- artifact_files[file.info(artifact_files)$isdir %in% FALSE & basename(artifact_files) != "artifact_manifest.csv"]
  labels <- tools::file_path_sans_ext(basename(artifact_files))
  labels <- gsub("[^A-Za-z0-9_]+", "_", labels)
  paths <- stats::setNames(artifact_files, make.unique(labels))
  manifest <- app_joint_exqdesn_trace_manifest(paths, freeze_dir)
  list(snapshot_path = snapshot_path, manifest_path = manifest$manifest_path, snapshot = snapshot)
}

app_joint_exqdesn_phase156_vb_one <- function(artifacts, row, n_chains = 8L) {
  scenario_id <- row$scenario_ids[[1L]]
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
  spec <- app_joint_qdesn_phase122_select_spec("joint_exqdesn_rhs_vb")
  controls <- app_joint_qdesn_phase122_controls_from_row(row, n_cores = 1L)
  start <- proc.time()[["elapsed"]]
  retained <- app_joint_exqdesn_fit_with_retained_init(fixture, controls)
  fit <- retained$vb_fit
  elapsed <- proc.time()[["elapsed"]] - start
  meta <- app_joint_qdesn_phase122_meta(fixture, spec, row, "VB-LD", "joint_exqdesn_rhs_vb")
  list(
    scenario_id = scenario_id,
    fit = fit,
    init = app_joint_exqdesn_phase156_init_rows(fit, scenario_id),
    convergence = cbind(
      app_joint_qdesn_vb_convergence_row(fit, meta, controls),
      data.frame(elapsed_seconds = elapsed, stringsAsFactors = FALSE)
    ),
    trace = if (nrow(fit$trace %||% data.frame())) cbind(meta, fit$trace, stringsAsFactors = FALSE) else data.frame(),
    shape_trace = app_joint_exqdesn_vb_trace_rows(fit, fixture$tau, cbind(meta, data.frame(experiment_id = "phase156_vb_initialization", stringsAsFactors = FALSE))),
    attempts = cbind(
      data.frame(scenario_id = scenario_id, stringsAsFactors = FALSE),
      retained$attempts,
      stringsAsFactors = FALSE
    ),
    starts = app_joint_exqdesn_phase156_chain_starts(fit, fixture$tau, scenario_id, n_chains)
  )
}

app_joint_exqdesn_run_phase156_freeze <- function(
  out_dir = app_joint_exqdesn_phase156_default_freeze_dir(),
  phase150_freeze_dir = app_path("application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_freeze_20260727"),
  phase150_mcmc_dir = app_path("application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727"),
  phase154_dir = app_path("application/cache/joint_qdesn_phase154_balanced_mcmc_final_20260730"),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  phase157_dir = app_joint_exqdesn_phase157_default_output_dir(),
  n_chains = 8L,
  n_iter = 12000L,
  burn = 3000L,
  thin = 3L,
  seed_offset = 15700L,
  chain_seed_stride = 101L,
  gamma_slice_width = 4,
  gamma_slice_max_steps = 250L,
  workers_per_wave = 32L,
  n_vb_cores = 8L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  phase150_freeze_dir <- normalizePath(phase150_freeze_dir, mustWork = TRUE)
  fixture_dir <- normalizePath(fixture_dir, mustWork = TRUE)
  phase157_dir <- normalizePath(phase157_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  source_verification <- app_joint_exqdesn_phase156_source_verification(phase150_freeze_dir, fixture_dir)
  controls <- app_joint_exqdesn_phase156_read_csv(file.path(phase150_freeze_dir, "case_winner_controls.csv"))
  controls <- controls[controls$model_ids == "joint_exqdesn_rhs_vb", , drop = FALSE]
  controls <- controls[order(controls$scenario_ids), , drop = FALSE]
  if (nrow(controls) != 8L || anyDuplicated(controls$scenario_ids)) {
    stop("Phase156 requires exactly eight unique case-specific Joint exQDESN controls.", call. = FALSE)
  }
  if (n_chains < 4L || n_iter <= burn || thin <= 0L || ((n_iter - burn) %% thin) != 0L) {
    stop("Invalid Phase157 MCMC controls.", call. = FALSE)
  }
  artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)
  vb_jobs <- lapply(seq_len(nrow(controls)), function(ii) controls[ii, , drop = FALSE])
  vb_results <- if (.Platform$OS.type != "windows" && n_vb_cores > 1L) {
    parallel::mclapply(vb_jobs, function(row) app_joint_exqdesn_phase156_vb_one(artifacts, row, n_chains), mc.cores = min(n_vb_cores, length(vb_jobs)))
  } else {
    lapply(vb_jobs, function(row) app_joint_exqdesn_phase156_vb_one(artifacts, row, n_chains))
  }
  init <- app_joint_qdesn_bind_rows(lapply(vb_results, `[[`, "init"))
  convergence <- app_joint_qdesn_bind_rows(lapply(vb_results, `[[`, "convergence"))
  vb_trace <- app_joint_qdesn_bind_rows(lapply(vb_results, `[[`, "trace"))
  vb_shape_trace <- app_joint_qdesn_bind_rows(lapply(vb_results, `[[`, "shape_trace"))
  vb_attempts <- app_joint_qdesn_bind_rows(lapply(vb_results, `[[`, "attempts"))
  starts <- app_joint_qdesn_bind_rows(lapply(vb_results, `[[`, "starts"))
  if (any(!is.finite(init$value)) || any(init$value[init$parameter_block == "sigma"] <= 0)) {
    stop("Phase156 VB initialization contains invalid values.", call. = FALSE)
  }
  plan_rows <- list()
  worker_id <- 0L
  for (scenario_index in seq_len(nrow(controls))) {
    scenario_id <- controls$scenario_ids[[scenario_index]]
    base_seed <- as.integer(artifacts$scenario_summary$seed[artifacts$scenario_summary$scenario_id == scenario_id][[1L]])
    for (chain_id in seq_len(n_chains)) {
      worker_id <- worker_id + 1L
      plan_rows[[worker_id]] <- data.frame(
        worker_id = worker_id,
        wave_id = ceiling(worker_id / workers_per_wave),
        scenario_index = scenario_index,
        scenario_id = scenario_id,
        case_id = controls$case_id[[scenario_index]],
        chain_id = chain_id,
        chain_seed = base_seed + seed_offset + scenario_index * 10000L + (chain_id - 1L) * chain_seed_stride,
        n_iter = as.integer(n_iter), burn = as.integer(burn), thin = as.integer(thin),
        n_keep = as.integer((n_iter - burn) / thin),
        gamma_update = "collapsed_logit_slice",
        gamma_slice_width = gamma_slice_width,
        gamma_slice_max_steps = as.integer(gamma_slice_max_steps),
        worker_output_dir = file.path(phase157_dir, "chains", sprintf("%02d_%s", scenario_index, scenario_id), sprintf("chain_%02d", chain_id)),
        stringsAsFactors = FALSE
      )
    }
  }
  chain_plan <- app_joint_qdesn_bind_rows(plan_rows)
  kernel_audit <- app_joint_exqdesn_phase156_kernel_audit()
  prior_audit <- data.frame(
    contract_item = c("scale_prior", "ordered_intercept_prior", "gamma_scale_transition", "validation_target"),
    historical_phase150 = c("prototype defaults a_sigma=b_sigma=0.1", "prototype zero/flat default", "conditional gamma then sigma", "quantile grid"),
    phase157 = c("case-specific frozen a_sigma/b_sigma", "empirical quantile center and frozen alpha_prior_sd", "gamma marginal over sigma then exact GIG sigma draw", "quantile grid"),
    status = c("corrected", "corrected", "new_kernel", "unchanged"),
    stringsAsFactors = FALSE
  )
  run_config <- data.frame(
    phase_id = "phase156_collapsed_gamma_sigma_freeze",
    phase150_freeze_dir = phase150_freeze_dir,
    phase150_mcmc_dir = normalizePath(phase150_mcmc_dir, mustWork = FALSE),
    phase154_dir = normalizePath(phase154_dir, mustWork = FALSE),
    fixture_dir = fixture_dir,
    phase157_dir = phase157_dir,
    n_scenarios = nrow(controls), n_chains = as.integer(n_chains),
    n_iter = as.integer(n_iter), burn = as.integer(burn), thin = as.integer(thin),
    n_keep_per_chain = as.integer((n_iter - burn) / thin),
    seed_offset = as.integer(seed_offset), chain_seed_stride = as.integer(chain_seed_stride),
    gamma_update = "collapsed_logit_slice", gamma_slice_width = gamma_slice_width,
    gamma_slice_max_steps = as.integer(gamma_slice_max_steps),
    workers_per_wave = as.integer(workers_per_wave), n_vb_cores = as.integer(n_vb_cores),
    retain_binary_objects = FALSE,
    validation_contract = "posterior_mean_quantile_grid_with_monotone_scoring_contract",
    stringsAsFactors = FALSE
  )
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Phase156 collapsed gamma-scale freeze",
    "",
    "This freeze retains the eight case-specific Phase150 VB-selected specifications and prepares eight independently resumable MCMC chains per scenario.",
    "Phase157 changes only the exAL MCMC prior implementation and gamma-scale transition: it uses the frozen scale/intercept priors and samples gamma after analytically integrating sigma, followed by an exact GIG scale draw.",
    "The historical Phase150 MCMC packet remains a useful benchmark, but it is not an exact same-prior target because the prototype MCMC path used legacy scale/intercept defaults.",
    "No RDS, RData, or latent-state object is part of the Phase157 storage contract.",
    "",
    sprintf("- Scenarios: %d", nrow(controls)),
    sprintf("- Chains per scenario: %d", n_chains),
    sprintf("- Iterations/burn/thin: %d/%d/%d", n_iter, burn, thin),
    sprintf("- Planned workers: %d in %d waves", nrow(chain_plan), max(chain_plan$wave_id)),
    sprintf("- Phase157 output: `%s`", phase157_dir)
  ), readme, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    case_winner_controls = app_joint_qvp_write_csv(controls, file.path(out_dir, "case_winner_controls.csv")),
    chain_plan = app_joint_qvp_write_csv(chain_plan, file.path(out_dir, "chain_plan.csv")),
    chain_start_values = app_joint_qvp_write_csv(starts, file.path(out_dir, "chain_start_values.csv")),
    vb_initialization = app_joint_qvp_write_csv(init, file.path(out_dir, "vb_initialization.csv")),
    vb_convergence = app_joint_qvp_write_csv(convergence, file.path(out_dir, "vb_convergence.csv")),
    vb_attempts = app_joint_qvp_write_csv(vb_attempts, file.path(out_dir, "vb_attempts.csv")),
    vb_objective_trace = app_joint_qvp_write_csv(vb_trace, file.path(out_dir, "vb_objective_trace.csv")),
    vb_gamma_sigma_trace = app_joint_qvp_write_csv(vb_shape_trace, file.path(out_dir, "vb_gamma_sigma_trace.csv")),
    source_manifest_verification = app_joint_qvp_write_csv(source_verification$freeze, file.path(out_dir, "source_manifest_verification.csv")),
    fixture_source_manifest = app_joint_qvp_write_csv(source_verification$fixture, file.path(out_dir, "fixture_source_manifest.csv")),
    prior_contract_audit = app_joint_qvp_write_csv(prior_audit, file.path(out_dir, "prior_contract_audit.csv")),
    kernel_contract_audit = app_joint_qvp_write_csv(kernel_audit, file.path(out_dir, "kernel_contract_audit.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_trace_manifest(paths, out_dir)
  code_snapshot <- app_joint_exqdesn_phase156_attach_code_snapshot(out_dir)
  list(out_dir = out_dir, chain_plan = chain_plan, controls = controls,
       convergence = convergence, kernel_audit = kernel_audit,
       code_snapshot = code_snapshot$snapshot,
       paths = c(paths, source_code_snapshot = code_snapshot$snapshot_path,
                 artifact_manifest = code_snapshot$manifest_path))
}

app_joint_exqdesn_phase157_load_freeze <- function(freeze_dir) {
  freeze_dir <- normalizePath(freeze_dir, mustWork = TRUE)
  missing <- app_joint_exqdesn_phase156_required_freeze_files()[
    !file.exists(file.path(freeze_dir, app_joint_exqdesn_phase156_required_freeze_files()))
  ]
  if (length(missing)) stop(sprintf("Phase156 freeze is missing: %s", paste(missing, collapse = ", ")), call. = FALSE)
  manifest <- app_joint_qdesn_phase108_manifest_verify(freeze_dir, "phase156_freeze")
  if (any(manifest$status != "pass")) stop("Phase156 freeze manifest verification failed.", call. = FALSE)
  list(
    freeze_dir = freeze_dir,
    manifest = manifest,
    config = app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "run_config.csv")),
    controls = app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "case_winner_controls.csv")),
    plan = app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "chain_plan.csv")),
    starts = app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "chain_start_values.csv")),
    init = app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "vb_initialization.csv"))
  )
}

app_joint_exqdesn_phase157_write_gzip_csv <- function(x, path) {
  tmp <- paste0(path, ".tmp-", Sys.getpid())
  con <- gzfile(tmp, open = "wt", compression = 6)
  on.exit(try(close(con), silent = TRUE), add = TRUE)
  utils::write.csv(x, con, row.names = FALSE, na = "")
  close(con)
  if (!file.rename(tmp, path)) stop(sprintf("Could not atomically publish '%s'.", path), call. = FALSE)
  normalizePath(path, mustWork = TRUE)
}

app_joint_exqdesn_phase157_draw_frame <- function(fit) {
  blocks <- list(
    beta = as.data.frame(fit$beta_draws, check.names = FALSE),
    alpha = as.data.frame(fit$alpha_draws, check.names = FALSE),
    sigma = as.data.frame(fit$sigma_draws, check.names = FALSE),
    gamma = as.data.frame(fit$gamma_draws, check.names = FALSE)
  )
  block_rows <- vapply(blocks, nrow, integer(1L))
  if (!length(block_rows) || any(block_rows <= 0L) || length(unique(block_rows)) != 1L) {
    stop("Phase157 posterior draw blocks must have one common positive row count.", call. = FALSE)
  }
  if (any(vapply(blocks, ncol, integer(1L)) <= 0L)) {
    stop("Phase157 posterior draw blocks must all contain columns.", call. = FALSE)
  }
  beta <- blocks$beta
  alpha <- blocks$alpha
  sigma <- blocks$sigma
  gamma <- blocks$gamma
  names(beta) <- sprintf("beta_%04d", seq_len(ncol(beta)))
  names(alpha) <- sprintf("alpha_%02d", seq_len(ncol(alpha)))
  names(sigma) <- sprintf("sigma_%02d", seq_len(ncol(sigma)))
  names(gamma) <- sprintf("gamma_%02d", seq_len(ncol(gamma)))
  out <- data.frame(draw_index = seq_len(nrow(beta)), stringsAsFactors = FALSE)
  for (block in list(beta, alpha, sigma, gamma)) {
    out[names(block)] <- block
  }
  if (anyDuplicated(names(out))) {
    stop("Phase157 posterior draw frame contains duplicate column names.", call. = FALSE)
  }
  expected_columns <- 1L + ncol(beta) + ncol(alpha) + ncol(sigma) + ncol(gamma)
  if (nrow(out) != nrow(beta) || ncol(out) != expected_columns) {
    stop("Phase157 posterior draw frame dimensions do not match the source blocks.", call. = FALSE)
  }
  out
}

app_joint_exqdesn_phase157_failure_receipt <- function(
  freeze_dir,
  worker_id,
  stage,
  condition,
  failure_dir = NULL
) {
  freeze_dir <- normalizePath(freeze_dir, mustWork = TRUE)
  worker_id <- as.integer(worker_id)[[1L]]
  plan_path <- file.path(freeze_dir, "chain_plan.csv")
  plan <- app_joint_exqdesn_phase156_read_csv(plan_path)
  job <- plan[plan$worker_id == worker_id, , drop = FALSE]
  worker_dir <- if (nrow(job) == 1L) job$worker_output_dir[[1L]] else NA_character_
  receipt <- data.frame(
    worker_id = worker_id,
    scenario_id = if (nrow(job) == 1L) job$scenario_id[[1L]] else NA_character_,
    chain_id = if (nrow(job) == 1L) job$chain_id[[1L]] else NA_integer_,
    chain_seed = if (nrow(job) == 1L) job$chain_seed[[1L]] else NA_integer_,
    stage = as.character(stage)[[1L]],
    condition_class = paste(class(condition), collapse = ";"),
    message = conditionMessage(condition),
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    source_sha256 = app_sha256_file(app_path("application/R/joint_exqdesn_phase156_collapsed_gamma_sigma.R")),
    stringsAsFactors = FALSE
  )
  paths <- character()
  if (!is.na(worker_dir) && nzchar(worker_dir)) {
    app_ensure_dir(worker_dir)
    paths <- c(paths, app_joint_qvp_write_csv(receipt, file.path(worker_dir, "failure_receipt.csv")))
  }
  if (!is.null(failure_dir) && nzchar(failure_dir)) {
    failure_dir <- normalizePath(failure_dir, mustWork = FALSE)
    app_ensure_dir(failure_dir)
    paths <- c(paths, app_joint_qvp_write_csv(
      receipt,
      file.path(failure_dir, sprintf("worker_%03d.csv", worker_id))
    ))
  }
  list(receipt = receipt, paths = paths)
}

app_joint_exqdesn_phase157_worker_complete <- function(worker_dir) {
  required <- c("posterior_draws.csv.gz", "chain_summary.csv", "sampler_diagnostics.csv", "runtime.csv", "provenance.csv", "README.md", "artifact_manifest.csv")
  if (!dir.exists(worker_dir) || any(!file.exists(file.path(worker_dir, required)))) return(FALSE)
  verified <- tryCatch(app_joint_qdesn_phase108_manifest_verify(worker_dir, "phase157_chain"), error = function(e) NULL)
  !is.null(verified) && nrow(verified) > 0L && all(verified$status == "pass")
}

app_joint_exqdesn_run_phase157_worker <- function(
  freeze_dir,
  worker_id,
  reuse_completed = TRUE,
  failure_dir = NULL
) {
  worker_id <- as.integer(worker_id)[[1L]]
  stage <- "load_freeze"
  tryCatch({
    freeze <- app_joint_exqdesn_phase157_load_freeze(freeze_dir)
    stage <- "resolve_job"
    job <- freeze$plan[freeze$plan$worker_id == worker_id, , drop = FALSE]
    if (nrow(job) != 1L) stop(sprintf("Unknown or duplicated Phase157 worker_id %s.", worker_id), call. = FALSE)
    worker_dir <- job$worker_output_dir[[1L]]
    if (reuse_completed && app_joint_exqdesn_phase157_worker_complete(worker_dir)) {
      return(list(worker_id = worker_id, worker_dir = worker_dir, status = "reused_verified"))
    }
    if (dir.exists(worker_dir) && length(list.files(worker_dir, all.files = TRUE, no.. = TRUE))) {
      quarantine <- paste0(worker_dir, "_incomplete_", format(Sys.time(), "%Y%m%dT%H%M%S"))
      if (!file.rename(worker_dir, quarantine)) {
        stop(sprintf("Could not quarantine incomplete worker directory '%s'.", worker_dir), call. = FALSE)
      }
    }
    app_ensure_dir(worker_dir)
    stage <- "load_fixture_and_initialization"
    scenario_id <- job$scenario_id[[1L]]
    control_row <- freeze$controls[freeze$controls$scenario_ids == scenario_id, , drop = FALSE]
    if (nrow(control_row) != 1L) stop("Phase157 worker could not resolve case controls.", call. = FALSE)
    controls <- app_joint_qdesn_phase122_controls_from_row(control_row, n_cores = 1L)
    artifacts <- app_joint_qdesn_load_fixture_artifacts(freeze$config$fixture_dir[[1L]])
    fixture <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
    init <- app_joint_exqdesn_phase156_init_from_rows(freeze$init, scenario_id)
    starts <- freeze$starts[freeze$starts$scenario_id == scenario_id & freeze$starts$chain_id == job$chain_id[[1L]], , drop = FALSE]
    init$gamma_mean <- starts$value[starts$parameter == "gamma"][order(starts$quantile_index[starts$parameter == "gamma"])]
    init$sigma_mean <- starts$value[starts$parameter == "sigma"][order(starts$quantile_index[starts$parameter == "sigma"])]
    sigma_upper <- max(1, 50 * max(init$sigma_mean, na.rm = TRUE))
    start <- proc.time()[["elapsed"]]
    stage <- "mcmc_sampling"
    fit <- app_joint_qvp_fit_exal_mcmc_tiny(
    y = fixture$y, Z = fixture$Z, tau = fixture$tau,
    n_iter = as.integer(job$n_iter[[1L]]), burn = as.integer(job$burn[[1L]]), thin = as.integer(job$thin[[1L]]),
    seed = as.integer(job$chain_seed[[1L]]), kappa = 1,
    tau0 = controls$tau0, zeta2 = controls$zeta2,
    a_sigma = controls$a_sigma, b_sigma = controls$b_sigma,
    gamma_init = init$gamma_mean, init = init,
    alpha_prior_mean = "empirical_quantile", alpha_prior_sd = controls$alpha_prior_sd,
    alpha_min_spacing = controls$alpha_min_spacing, max_dense_dim = controls$max_dense_dim,
    sigma_bounds = c(1.0e-8, sigma_upper),
    gamma_update = "collapsed_logit_slice",
    gamma_slice_width = as.numeric(job$gamma_slice_width[[1L]]),
    gamma_slice_max_steps = as.integer(job$gamma_slice_max_steps[[1L]]),
    gamma_refresh_repeats = 1L, gamma_refresh_block = "none"
    )
    elapsed <- proc.time()[["elapsed"]] - start
    stage <- "draw_frame"
    draws <- app_joint_exqdesn_phase157_draw_frame(fit)
    all_finite <- all(is.finite(as.matrix(draws[, -1L, drop = FALSE])))
    if (!all_finite || any(fit$sigma_draws <= 0)) stop("Phase157 worker produced invalid posterior draws.", call. = FALSE)
    summary <- data.frame(
    worker_id = worker_id, wave_id = job$wave_id[[1L]], scenario_id = scenario_id,
    case_id = job$case_id[[1L]], chain_id = job$chain_id[[1L]], chain_seed = job$chain_seed[[1L]],
    n_iter = job$n_iter[[1L]], burn = job$burn[[1L]], thin = job$thin[[1L]], n_keep = nrow(draws),
    p = ncol(fixture$Z), K = length(fixture$tau),
    tau0 = controls$tau0, zeta2 = controls$zeta2, a_sigma = controls$a_sigma, b_sigma = controls$b_sigma,
    alpha_prior_sd = paste(controls$alpha_prior_sd, collapse = ","),
    gamma_update = fit$gamma_update, gamma_slice_width = job$gamma_slice_width[[1L]],
    gamma_slice_max_steps = job$gamma_slice_max_steps[[1L]],
    init_source = fit$init_source, draws_all_finite = all_finite,
    min_sigma = min(fit$sigma_draws), max_sigma = max(fit$sigma_draws),
    min_gamma = min(fit$gamma_draws), max_gamma = max(fit$gamma_draws),
    collapsed_density_evaluations = sum(fit$gamma_collapsed_density_evaluations),
    elapsed_seconds = elapsed, seconds_per_iteration = elapsed / job$n_iter[[1L]],
    stringsAsFactors = FALSE
    )
    sampler <- app_joint_qdesn_bind_rows(lapply(seq_along(fixture$tau), function(kk) {
    data.frame(
      worker_id = worker_id, scenario_id = scenario_id, chain_id = job$chain_id[[1L]],
      quantile_index = kk, tau = fixture$tau[[kk]],
      sigma_mean = mean(fit$sigma_draws[, kk]), sigma_sd = stats::sd(fit$sigma_draws[, kk]),
      gamma_mean = mean(fit$gamma_draws[, kk]), gamma_sd = stats::sd(fit$gamma_draws[, kk]),
      gamma_sigma_correlation = stats::cor(fit$gamma_draws[, kk], fit$sigma_draws[, kk]),
      gamma_rough_ess = app_joint_exqdesn_rough_ess_one_chain(fit$gamma_draws[, kk]),
      sigma_rough_ess = app_joint_exqdesn_rough_ess_one_chain(fit$sigma_draws[, kk]),
      collapsed_density_evaluations = fit$gamma_collapsed_density_evaluations[[kk]],
      stringsAsFactors = FALSE
    )
    }))
    runtime <- summary[, c("worker_id", "wave_id", "scenario_id", "chain_id", "chain_seed", "elapsed_seconds", "seconds_per_iteration"), drop = FALSE]
    readme <- file.path(worker_dir, "README.md")
    writeLines(c(
    sprintf("# Phase157 worker %d", worker_id), "",
    sprintf("- Scenario: `%s`", scenario_id),
    sprintf("- Chain: %d", job$chain_id[[1L]]),
    sprintf("- Seed: %d", job$chain_seed[[1L]]),
    "- Kernel: partially collapsed logit-slice gamma update followed by exact GIG sigma draw.",
    "- Storage: compressed posterior draws plus CSV diagnostics; no latent-state binary object."
    ), readme, useBytes = TRUE)
    stage <- "write_artifacts"
    paths <- c(
      posterior_draws = app_joint_exqdesn_phase157_write_gzip_csv(draws, file.path(worker_dir, "posterior_draws.csv.gz")),
      chain_summary = app_joint_qvp_write_csv(summary, file.path(worker_dir, "chain_summary.csv")),
      sampler_diagnostics = app_joint_qvp_write_csv(sampler, file.path(worker_dir, "sampler_diagnostics.csv")),
      runtime = app_joint_qvp_write_csv(runtime, file.path(worker_dir, "runtime.csv")),
      provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(worker_dir, "provenance.csv")),
      readme = normalizePath(readme, mustWork = TRUE)
    )
    stage <- "write_and_verify_manifest"
    manifest <- app_joint_exqdesn_trace_manifest(paths, worker_dir)
    if (!app_joint_exqdesn_phase157_worker_complete(worker_dir)) {
      stop("Phase157 worker artifact manifest did not verify after publication.", call. = FALSE)
    }
    list(worker_id = worker_id, worker_dir = worker_dir, status = "completed",
         summary = summary, paths = c(paths, artifact_manifest = manifest$manifest_path))
  }, error = function(e) {
    receipt <- tryCatch(
      app_joint_exqdesn_phase157_failure_receipt(freeze_dir, worker_id, stage, e, failure_dir),
      error = function(receipt_error) NULL
    )
    wrapped <- simpleError(conditionMessage(e), call = conditionCall(e))
    class(wrapped) <- c("joint_exqdesn_phase157_worker_error", class(wrapped))
    attr(wrapped, "stage") <- stage
    attr(wrapped, "failure_receipt_paths") <- receipt$paths %||% character()
    stop(wrapped)
  })
}

app_joint_exqdesn_phase157_read_fit <- function(worker_dir, tau, seed, chain_id) {
  draws <- app_joint_exqdesn_phase156_read_csv(file.path(worker_dir, "posterior_draws.csv.gz"))
  if (!"draw_index" %in% names(draws) || nrow(draws) <= 0L || anyDuplicated(draws$draw_index)) {
    stop("Malformed Phase157 posterior draw index.", call. = FALSE)
  }
  select <- function(prefix) as.matrix(draws[, grepl(paste0("^", prefix, "_"), names(draws)), drop = FALSE])
  beta <- select("beta")
  alpha <- select("alpha")
  sigma <- select("sigma")
  gamma <- select("gamma")
  K <- length(tau)
  if (K <= 0L || ncol(beta) <= 0L || (ncol(beta) %% K) != 0L ||
      ncol(alpha) != K || ncol(sigma) != K || ncol(gamma) != K) {
    stop("Malformed Phase157 posterior draw block dimensions.", call. = FALSE)
  }
  if (any(!is.finite(c(beta, alpha, sigma, gamma))) || any(sigma <= 0)) {
    stop("Phase157 posterior draw file contains invalid values.", call. = FALSE)
  }
  p <- ncol(beta) / K
  out <- list(
    beta_draws = beta, alpha_draws = alpha, sigma_draws = sigma, gamma_draws = gamma,
    beta_mean = colMeans(beta), alpha_mean = colMeans(alpha), sigma_mean = colMeans(sigma), gamma_mean = colMeans(gamma),
    tau = tau, seed = as.integer(seed), chain_id = as.integer(chain_id), init_source = "provided"
  )
  out$qhat_mean <- NULL
  class(out) <- c("joint_qvp_qdesn_tiny_fit", "list")
  out
}

app_joint_exqdesn_phase157_running_ids <- function(orchestration_dir) {
  if (is.null(orchestration_dir) || !nzchar(orchestration_dir)) return(integer())
  running_dir <- file.path(orchestration_dir, "running")
  files <- list.files(running_dir, pattern = "^worker_[0-9]+[.]csv$", full.names = TRUE)
  if (!length(files)) return(integer())
  ids <- vapply(files, function(path) {
    row <- tryCatch(app_joint_exqdesn_phase156_read_csv(path), error = function(e) NULL)
    if (is.null(row) || nrow(row) != 1L || !all(c("worker_id", "pid") %in% names(row))) return(NA_integer_)
    pid <- as.integer(row$pid[[1L]])
    alive <- suppressWarnings(system2("kill", c("-0", pid), stdout = FALSE, stderr = FALSE)) == 0L
    command <- if (alive) {
      tryCatch(system2("ps", c("-p", pid, "-o", "args="), stdout = TRUE, stderr = FALSE), error = function(e) character())
    } else character()
    alive <- alive && length(command) > 0L &&
      any(grepl("190_run_joint_exqdesn_phase157_chain[.]R", command)) &&
      any(grepl(sprintf("--worker-id[ =]+%d([[:space:]]|$)", as.integer(row$worker_id[[1L]])), command))
    if (alive) as.integer(row$worker_id[[1L]]) else NA_integer_
  }, integer(1L))
  unique(ids[!is.na(ids)])
}

app_joint_exqdesn_phase157_health <- function(freeze_dir, orchestration_dir = NULL) {
  freeze <- app_joint_exqdesn_phase157_load_freeze(freeze_dir)
  orchestration_dir <- if (is.null(orchestration_dir) || !nzchar(orchestration_dir)) NULL else normalizePath(orchestration_dir, mustWork = FALSE)
  running_ids <- app_joint_exqdesn_phase157_running_ids(orchestration_dir)
  rows <- lapply(seq_len(nrow(freeze$plan)), function(ii) {
    job <- freeze$plan[ii, , drop = FALSE]
    dir <- job$worker_output_dir[[1L]]
    complete <- app_joint_exqdesn_phase157_worker_complete(dir)
    failure_paths <- c(
      file.path(dir, "failure_receipt.csv"),
      if (!is.null(orchestration_dir)) file.path(orchestration_dir, "failures", sprintf("worker_%03d.csv", job$worker_id[[1L]])) else character()
    )
    skipped_path <- if (!is.null(orchestration_dir)) file.path(orchestration_dir, "skipped", sprintf("worker_%03d.csv", job$worker_id[[1L]])) else ""
    state <- if (complete) {
      "complete_verified"
    } else if (job$worker_id[[1L]] %in% running_ids) {
      "running"
    } else if (any(file.exists(failure_paths))) {
      "failed"
    } else if (nzchar(skipped_path) && file.exists(skipped_path)) {
      "skipped_after_abort"
    } else if (dir.exists(dir) && length(list.files(dir, all.files = TRUE, no.. = TRUE))) {
      "incomplete"
    } else {
      "queued"
    }
    cbind(job[, c("worker_id", "wave_id", "scenario_id", "chain_id", "chain_seed")], data.frame(state = state, stringsAsFactors = FALSE))
  })
  inventory <- app_joint_qdesn_bind_rows(rows)
  summary <- data.frame(
    planned_workers = nrow(inventory),
    complete_verified = sum(inventory$state == "complete_verified"),
    running = sum(inventory$state == "running"),
    failed = sum(inventory$state == "failed"),
    skipped_after_abort = sum(inventory$state == "skipped_after_abort"),
    incomplete = sum(inventory$state == "incomplete"),
    queued = sum(inventory$state == "queued"),
    percent_complete = 100 * mean(inventory$state == "complete_verified"),
    all_complete = all(inventory$state == "complete_verified"),
    stringsAsFactors = FALSE
  )
  list(summary = summary, inventory = inventory)
}

app_joint_exqdesn_phase156b_git_state <- function(repo_root = app_repo_root()) {
  repo_root <- normalizePath(repo_root, mustWork = TRUE)
  head <- trimws(system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE))
  status <- system2("git", c("-C", repo_root, "status", "--porcelain", "--untracked-files=normal"), stdout = TRUE)
  data.frame(
    git_head = head[[1L]],
    worktree_clean = length(status) == 0L,
    dirty_path_count = length(status),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase156b_identity_audit <- function(parent_dir, child_dir) {
  exact_files <- c(
    "case_winner_controls.csv", "chain_start_values.csv", "vb_initialization.csv",
    "vb_convergence.csv", "vb_attempts.csv", "vb_objective_trace.csv",
    "vb_gamma_sigma_trace.csv", "source_manifest_verification.csv",
    "fixture_source_manifest.csv", "prior_contract_audit.csv", "kernel_contract_audit.csv"
  )
  file_rows <- lapply(exact_files, function(file) {
    parent_path <- file.path(parent_dir, file)
    child_path <- file.path(child_dir, file)
    parent_hash <- if (file.exists(parent_path)) app_sha256_file(parent_path) else NA_character_
    child_hash <- if (file.exists(child_path)) app_sha256_file(child_path) else NA_character_
    data.frame(
      audit_type = "byte_identical_file", item = file,
      parent_value = parent_hash, child_value = child_hash,
      status = if (!is.na(parent_hash) && identical(parent_hash, child_hash)) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  })
  parent_plan <- app_joint_exqdesn_phase156_read_csv(file.path(parent_dir, "chain_plan.csv"))
  child_plan <- app_joint_exqdesn_phase156_read_csv(file.path(child_dir, "chain_plan.csv"))
  stable_plan_columns <- setdiff(intersect(names(parent_plan), names(child_plan)), "worker_output_dir")
  plan_equal <- identical(parent_plan[, stable_plan_columns, drop = FALSE], child_plan[, stable_plan_columns, drop = FALSE])
  plan_paths_changed <- nrow(parent_plan) == nrow(child_plan) && all(parent_plan$worker_output_dir != child_plan$worker_output_dir)
  plan_rows <- list(
    data.frame(
      audit_type = "table_identity", item = "chain_plan_statistical_fields",
      parent_value = sprintf("%d rows; %d fields", nrow(parent_plan), length(stable_plan_columns)),
      child_value = sprintf("%d rows; %d fields", nrow(child_plan), length(stable_plan_columns)),
      status = if (plan_equal) "pass" else "fail", stringsAsFactors = FALSE
    ),
    data.frame(
      audit_type = "expected_difference", item = "chain_plan_worker_output_dir",
      parent_value = parent_plan$worker_output_dir[[1L]], child_value = child_plan$worker_output_dir[[1L]],
      status = if (plan_paths_changed) "pass" else "fail", stringsAsFactors = FALSE
    )
  )
  app_joint_qdesn_bind_rows(c(file_rows, plan_rows))
}

app_joint_exqdesn_run_phase156b_amendment <- function(
  parent_freeze_dir = app_joint_exqdesn_phase156_default_freeze_dir(),
  failed_phase157_dir = app_joint_exqdesn_phase157_default_output_dir(),
  failed_orchestration_dir = paste0(app_joint_exqdesn_phase157_default_output_dir(), "_orchestration"),
  out_dir = app_joint_exqdesn_phase156b_default_freeze_dir(),
  phase157b_dir = app_joint_exqdesn_phase157b_default_output_dir(),
  require_clean_source = TRUE
) {
  parent_freeze_dir <- normalizePath(parent_freeze_dir, mustWork = TRUE)
  failed_phase157_dir <- normalizePath(failed_phase157_dir, mustWork = TRUE)
  failed_orchestration_dir <- normalizePath(failed_orchestration_dir, mustWork = TRUE)
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  phase157b_dir <- normalizePath(phase157b_dir, mustWork = FALSE)
  if (dir.exists(out_dir) && length(list.files(out_dir, all.files = TRUE, no.. = TRUE))) {
    stop(sprintf("Phase156b output directory is not empty: %s", out_dir), call. = FALSE)
  }
  app_ensure_dir(out_dir)
  parent_verification <- app_joint_qdesn_phase108_manifest_verify(parent_freeze_dir, "phase156_parent")
  if (!nrow(parent_verification) || any(parent_verification$status != "pass")) {
    stop("Phase156b parent manifest verification failed.", call. = FALSE)
  }
  git_state <- app_joint_exqdesn_phase156b_git_state()
  if (isTRUE(require_clean_source) && !isTRUE(git_state$worktree_clean[[1L]])) {
    stop("Phase156b requires a clean committed source worktree.", call. = FALSE)
  }
  excluded <- c("artifact_manifest.csv", "source_code_snapshot.csv", "run_config.csv", "chain_plan.csv", "README.md", "provenance.csv")
  copy_files <- setdiff(list.files(parent_freeze_dir, recursive = FALSE), excluded)
  copied <- file.copy(file.path(parent_freeze_dir, copy_files), file.path(out_dir, copy_files), overwrite = FALSE)
  if (length(copied) != length(copy_files) || any(!copied)) {
    stop("Could not copy the immutable Phase156 parent tables.", call. = FALSE)
  }
  parent_plan <- app_joint_exqdesn_phase156_read_csv(file.path(parent_freeze_dir, "chain_plan.csv"))
  child_plan <- parent_plan
  child_plan$worker_output_dir <- file.path(
    phase157b_dir, "chains",
    sprintf("%02d_%s", child_plan$scenario_index, child_plan$scenario_id),
    sprintf("chain_%02d", child_plan$chain_id)
  )
  parent_config <- app_joint_exqdesn_phase156_read_csv(file.path(parent_freeze_dir, "run_config.csv"))
  child_config <- parent_config
  child_config$phase_id <- "phase156b_collapsed_gamma_sigma_recovery_freeze"
  child_config$phase157_dir <- phase157b_dir
  child_config$parent_phase156_freeze_dir <- parent_freeze_dir
  child_config$parent_phase156_manifest_sha256 <- app_sha256_file(file.path(parent_freeze_dir, "artifact_manifest.csv"))
  child_config$failed_phase157_dir <- failed_phase157_dir
  child_config$failed_orchestration_dir <- failed_orchestration_dir
  child_config$source_git_head <- git_state$git_head[[1L]]
  child_config$recovery_scope <- "serialization_observability_fail_fast_only"
  app_joint_qvp_write_csv(child_plan, file.path(out_dir, "chain_plan.csv"))
  app_joint_qvp_write_csv(child_config, file.path(out_dir, "run_config.csv"))
  identity <- app_joint_exqdesn_phase156b_identity_audit(parent_freeze_dir, out_dir)
  if (any(identity$status != "pass")) stop("Phase156b parent-child identity audit failed.", call. = FALSE)
  log_files <- list.files(file.path(failed_orchestration_dir, "worker_logs"), pattern = "^worker_[0-9]+[.]log$", full.names = TRUE)
  log_text <- lapply(log_files, readLines, warn = FALSE)
  signature <- 'formal argument "check.names" matched by multiple actual arguments'
  signature_match <- vapply(log_text, function(x) any(grepl(signature, x, fixed = TRUE)), logical(1L))
  exit_path <- file.path(failed_orchestration_dir, "phase157.exit")
  failed_audit <- data.frame(
    audit_id = "phase157_common_serialization_failure",
    planned_workers = nrow(parent_plan), worker_logs = length(log_files),
    common_signature_logs = sum(signature_match), verified_worker_manifests = sum(vapply(parent_plan$worker_output_dir, app_joint_exqdesn_phase157_worker_complete, logical(1L))),
    orchestrator_exit = if (file.exists(exit_path)) trimws(readLines(exit_path, warn = FALSE)[[1L]]) else NA_character_,
    failure_stage = "draw_frame", statistical_draws_recoverable = FALSE,
    status = if (length(log_files) == nrow(parent_plan) && all(signature_match)) "pass" else "fail",
    stringsAsFactors = FALSE
  )
  if (failed_audit$status[[1L]] != "pass") stop("Phase156b failed-run audit did not confirm one common failure signature.", call. = FALSE)
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Phase156b collapsed gamma-scale recovery freeze", "",
    "This parent-linked amendment reuses the verified Phase156 case controls, VB-LD initializations, starts, seeds, and statistical MCMC controls byte-for-byte.",
    "Only worker output paths, source hashes, serialization observability, and fail-fast orchestration are amended.",
    "The failed Phase157 packet is retained as provenance and contains no usable posterior draws.", "",
    sprintf("- Parent freeze: `%s`", parent_freeze_dir),
    sprintf("- Parent manifest SHA-256: `%s`", child_config$parent_phase156_manifest_sha256[[1L]]),
    sprintf("- Source commit: `%s`", git_state$git_head[[1L]]),
    sprintf("- Phase157b output: `%s`", phase157b_dir),
    sprintf("- Workers/scenarios: %d/%d", nrow(child_plan), length(unique(child_plan$scenario_id)))
  ), readme, useBytes = TRUE)
  app_joint_qvp_write_csv(parent_verification, file.path(out_dir, "parent_manifest_verification.csv"))
  app_joint_qvp_write_csv(identity, file.path(out_dir, "parent_identity_audit.csv"))
  app_joint_qvp_write_csv(failed_audit, file.path(out_dir, "failed_phase157_audit.csv"))
  app_joint_qvp_write_csv(git_state, file.path(out_dir, "source_commit.csv"))
  app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv"))
  snapshot <- app_joint_exqdesn_phase156_attach_code_snapshot(out_dir)
  verification <- app_joint_qdesn_phase108_manifest_verify(out_dir, "phase156b_recovery_freeze")
  if (any(verification$status != "pass")) stop("Phase156b amended freeze manifest failed verification.", call. = FALSE)
  list(
    out_dir = out_dir, config = child_config, chain_plan = child_plan,
    identity_audit = identity, failed_run_audit = failed_audit,
    source_snapshot = snapshot$snapshot, manifest_verification = verification
  )
}

app_joint_exqdesn_phase157b_make_preflight_freeze <- function(
  freeze_dir,
  out_dir,
  worker_output_dir,
  n_iter = 12L,
  burn = 4L,
  thin = 2L
) {
  freeze_dir <- normalizePath(freeze_dir, mustWork = TRUE)
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  worker_output_dir <- normalizePath(worker_output_dir, mustWork = FALSE)
  if (dir.exists(out_dir)) unlink(out_dir, recursive = TRUE, force = TRUE)
  app_ensure_dir(out_dir)
  source_verification <- app_joint_qdesn_phase108_manifest_verify(freeze_dir, "phase156b_preflight_source")
  if (any(source_verification$status != "pass")) stop("Preflight source freeze manifest failed.", call. = FALSE)
  files <- setdiff(list.files(freeze_dir, recursive = FALSE), c("artifact_manifest.csv", "chain_plan.csv", "run_config.csv", "README.md"))
  if (any(!file.copy(file.path(freeze_dir, files), file.path(out_dir, files), overwrite = FALSE))) {
    stop("Could not copy Phase157b preflight freeze files.", call. = FALSE)
  }
  plan <- app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "chain_plan.csv"))[1L, , drop = FALSE]
  plan$worker_id <- 1L
  plan$wave_id <- 1L
  plan$n_iter <- as.integer(n_iter)
  plan$burn <- as.integer(burn)
  plan$thin <- as.integer(thin)
  plan$n_keep <- as.integer((n_iter - burn) / thin)
  plan$worker_output_dir <- worker_output_dir
  config <- app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "run_config.csv"))
  config$phase_id <- "phase157b_worker_lifecycle_preflight"
  config$phase157_dir <- dirname(worker_output_dir)
  config$n_scenarios <- 1L
  config$n_chains <- 1L
  config$n_iter <- as.integer(n_iter)
  config$burn <- as.integer(burn)
  config$thin <- as.integer(thin)
  config$n_keep_per_chain <- as.integer((n_iter - burn) / thin)
  app_joint_qvp_write_csv(plan, file.path(out_dir, "chain_plan.csv"))
  app_joint_qvp_write_csv(config, file.path(out_dir, "run_config.csv"))
  writeLines(c(
    "# Phase157b worker lifecycle preflight freeze", "",
    "This implementation-only freeze contains one real fixture worker with shortened MCMC controls.",
    "It is not statistical validation evidence."
  ), file.path(out_dir, "README.md"), useBytes = TRUE)
  artifact_files <- list.files(out_dir, full.names = TRUE, recursive = FALSE)
  artifact_files <- artifact_files[file.info(artifact_files)$isdir %in% FALSE & basename(artifact_files) != "artifact_manifest.csv"]
  labels <- make.unique(gsub("[^A-Za-z0-9_]+", "_", tools::file_path_sans_ext(basename(artifact_files))))
  app_joint_exqdesn_trace_manifest(stats::setNames(artifact_files, labels), out_dir)
  out_dir
}

app_joint_exqdesn_phase157b_canonical_draw_hash <- function(path) {
  draws <- app_joint_exqdesn_phase156_read_csv(path)
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  utils::write.csv(draws, tmp, row.names = FALSE, na = "")
  app_sha256_file(tmp)
}

app_joint_exqdesn_phase157b_preflight_score <- function(freeze_dir) {
  freeze <- app_joint_exqdesn_phase157_load_freeze(freeze_dir)
  job <- freeze$plan[1L, , drop = FALSE]
  artifacts <- app_joint_qdesn_load_fixture_artifacts(freeze$config$fixture_dir[[1L]])
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, job$scenario_id[[1L]], role = "fit")
  control <- freeze$controls[freeze$controls$scenario_ids == job$scenario_id[[1L]], , drop = FALSE]
  spec <- app_joint_qdesn_phase122_select_spec("joint_exqdesn_rhs_vb")
  meta <- app_joint_qdesn_phase122_meta(fixture, spec, control, "MCMC-preflight", "joint_exqdesn_rhs_mcmc_collapsed_preflight")
  fit <- app_joint_exqdesn_phase157_read_fit(job$worker_output_dir[[1L]], fixture$tau, job$chain_seed[[1L]], job$chain_id[[1L]])
  qhat <- app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau)
  scored <- app_joint_qdesn_phase122_score_qhat(meta, fixture, qhat, "qhat", "phase157b_preflight_fit")
  data.frame(
    scenario_id = job$scenario_id[[1L]], n_keep = nrow(fit$beta_draws),
    draw_columns = ncol(app_joint_exqdesn_phase156_read_csv(file.path(job$worker_output_dir[[1L]], "posterior_draws.csv.gz"))),
    all_finite = all(is.finite(c(fit$beta_draws, fit$alpha_draws, fit$sigma_draws, fit$gamma_draws))),
    sigma_positive = all(fit$sigma_draws > 0),
    fit_truth_mae = mean(scored$scored$truth_abs_error),
    contract_crossing_pairs = sum(scored$contract_info$contract_crossing$n_crossing_pairs),
    worker_manifest_verified = app_joint_exqdesn_phase157_worker_complete(job$worker_output_dir[[1L]]),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase157_chain_group_stability <- function(fits, fixture, artifacts, meta) {
  split_at <- floor(length(fits) / 2L)
  groups <- list(first_half = fits[seq_len(split_at)], second_half = fits[seq.int(split_at + 1L, length(fits))])
  rows <- lapply(names(groups), function(group_id) {
    pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(groups[[group_id]], fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau)
    fit_score <- app_joint_qdesn_phase122_score_qhat(meta, fixture, app_joint_qdesn_predict_fit(pooled, fixture$Z, fixture$tau), "qhat", paste0(group_id, "_fit"))
    forecast_score <- app_joint_qdesn_phase122_forecast_scores(meta, artifacts, fixture$scenario_id, fixture, pooled, "qhat", paste0(group_id, "_forecast"))
    data.frame(
      meta, chain_group = group_id, n_chains = length(groups[[group_id]]),
      fit_truth_mae = mean(fit_score$scored$truth_abs_error),
      forecast_truth_mae = mean(forecast_score$scored$truth_abs_error),
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_finalize_phase157 <- function(
  freeze_dir = app_joint_exqdesn_phase156_default_freeze_dir(),
  out_dir = app_joint_exqdesn_phase157_default_output_dir()
) {
  freeze <- app_joint_exqdesn_phase157_load_freeze(freeze_dir)
  health <- app_joint_exqdesn_phase157_health(freeze_dir)
  if (!isTRUE(health$summary$all_complete[[1L]])) {
    stop(sprintf("Phase157 is incomplete: %d/%d verified workers.", health$summary$complete_verified[[1L]], health$summary$planned_workers[[1L]]), call. = FALSE)
  }
  out_dir <- normalizePath(out_dir, mustWork = TRUE)
  artifacts <- app_joint_qdesn_load_fixture_artifacts(freeze$config$fixture_dir[[1L]])
  scenario_rows <- split(freeze$plan, freeze$plan$scenario_id)
  results <- lapply(names(scenario_rows), function(scenario_id) {
    jobs <- scenario_rows[[scenario_id]][order(scenario_rows[[scenario_id]]$chain_id), , drop = FALSE]
    fixture <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
    control <- freeze$controls[freeze$controls$scenario_ids == scenario_id, , drop = FALSE]
    spec <- app_joint_qdesn_phase122_select_spec("joint_exqdesn_rhs_vb")
    meta <- app_joint_qdesn_phase122_meta(fixture, spec, control, "MCMC", "joint_exqdesn_rhs_mcmc_collapsed")
    fits <- lapply(seq_len(nrow(jobs)), function(ii) {
      app_joint_exqdesn_phase157_read_fit(jobs$worker_output_dir[[ii]], fixture$tau, jobs$chain_seed[[ii]], jobs$chain_id[[ii]])
    })
    pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(fits, fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau)
    fit_score <- app_joint_qdesn_phase122_score_qhat(meta, fixture, app_joint_qdesn_predict_fit(pooled, fixture$Z, fixture$tau), "qhat", "phase157_fit")
    forecast_score <- app_joint_qdesn_phase122_forecast_scores(meta, artifacts, scenario_id, fixture, pooled, "qhat", "phase157_forecast")
    modern <- app_joint_exqdesn_modern_diagnostic_rows(fits, fixture$tau, meta)
    classic <- app_joint_exqdesn_mcmc_rhat_ess_rows(fits, fixture$tau, cbind(meta, data.frame(experiment_id = "phase157_collapsed", stringsAsFactors = FALSE)))
    trace <- app_joint_exqdesn_mcmc_chain_trace_rows(
      fits, fixture$tau,
      cbind(meta, data.frame(experiment_id = "phase157_collapsed", variant_id = "collapsed_logit_slice", width_multiplier = 1, stringsAsFactors = FALSE)),
      freeze$config$n_iter[[1L]], freeze$config$burn[[1L]], freeze$config$thin[[1L]]
    )
    rank_hist <- app_joint_qdesn_bind_rows(lapply(c("sigma", "gamma", "exal_lambda"), function(parameter) {
      app_joint_qdesn_bind_rows(lapply(seq_along(fixture$tau), function(kk) {
        mat <- do.call(cbind, lapply(fits, function(fit) {
          if (parameter == "sigma") return(fit$sigma_draws[, kk])
          if (parameter == "gamma") return(fit$gamma_draws[, kk])
          vapply(fit$gamma_draws[, kk], function(g) app_joint_qvp_exal_constants(fixture$tau[[kk]], g)$lambda[[1L]], numeric(1L))
        }))
        cbind(meta, data.frame(parameter = parameter, quantile_index = kk, tau = fixture$tau[[kk]], stringsAsFactors = FALSE), app_joint_exqdesn_rank_histogram(mat), stringsAsFactors = FALSE)
      }))
    }))
    corr_rows <- app_joint_qdesn_bind_rows(lapply(split(trace, interaction(trace$chain_id, trace$quantile_index, drop = TRUE)), function(block) {
      cbind(meta, block[1L, c("chain_id", "chain_seed", "quantile_index", "tau")], data.frame(gamma_sigma_correlation = stats::cor(block$gamma, block$sigma), stringsAsFactors = FALSE))
    }))
    contract_cross <- sum(fit_score$contract_info$contract_crossing$n_crossing_pairs) + sum(forecast_score$contract_crossing$n_crossing_pairs)
    raw_cross <- sum(fit_score$contract_info$raw_crossing$n_crossing_pairs) + sum(forecast_score$raw_crossing$n_crossing_pairs)
    summary <- cbind(meta, data.frame(
      n_chains = length(fits), n_keep_total = nrow(pooled$beta_draws),
      fit_truth_mae = mean(fit_score$scored$truth_abs_error),
      fit_truth_rmse = sqrt(mean(fit_score$scored$truth_sq_error)),
      fit_truth_bias = mean(fit_score$scored$truth_error),
      forecast_truth_mae = mean(forecast_score$scored$truth_abs_error),
      forecast_truth_rmse = sqrt(mean(forecast_score$scored$truth_sq_error)),
      forecast_truth_bias = mean(forecast_score$scored$truth_error),
      fit_check_loss_mean = mean(fit_score$scored$check_loss),
      forecast_check_loss_mean = mean(forecast_score$scored$check_loss),
      fit_crps_grid_mean = app_joint_qdesn_crps_grid_summary(fit_score$scored)$crps_grid_mean[[1L]],
      forecast_crps_grid_mean = app_joint_qdesn_crps_grid_summary(forecast_score$scored)$crps_grid_mean[[1L]],
      fit_max_abs_hit_rate_error = max(app_joint_qdesn_hit_rate_summary(fit_score$scored)$abs_hit_rate_error),
      forecast_max_abs_hit_rate_error = max(app_joint_qdesn_hit_rate_summary(forecast_score$scored)$abs_hit_rate_error),
      raw_crossing_pairs = raw_cross, contract_crossing_pairs = contract_cross,
      max_abs_monotone_adjustment = max(c(fit_score$adjustment$abs_adjustment, forecast_score$adjustment$abs_adjustment)),
      max_gamma_rank_rhat = max(modern$rank_rhat[modern$parameter == "gamma"], na.rm = TRUE),
      max_sigma_rank_rhat = max(modern$rank_rhat[modern$parameter == "sigma"], na.rm = TRUE),
      min_gamma_bulk_ess = min(modern$bulk_ess[modern$parameter == "gamma"], na.rm = TRUE),
      min_sigma_bulk_ess = min(modern$bulk_ess[modern$parameter == "sigma"], na.rm = TRUE),
      max_abs_gamma_sigma_correlation = max(abs(corr_rows$gamma_sigma_correlation), na.rm = TRUE),
      all_draws_finite = all(vapply(fits, function(x) all(is.finite(x$beta_draws)) && all(is.finite(x$alpha_draws)) && all(is.finite(x$sigma_draws)) && all(is.finite(x$gamma_draws)), logical(1L))),
      stringsAsFactors = FALSE
    ))
    list(
      summary = summary, modern = modern, classic = classic, trace_summary = app_joint_exqdesn_mcmc_trace_summary_rows(trace),
      autocorrelation = app_joint_exqdesn_autocorrelation_rows(trace), rank_histogram = rank_hist,
      correlation = corr_rows, stability = app_joint_exqdesn_phase157_chain_group_stability(fits, fixture, artifacts, meta),
      fit = fit_score$scored, forecast = forecast_score$scored,
      adjustment = app_joint_qdesn_bind_rows(list(fit_score$adjustment, forecast_score$adjustment)),
      raw_crossing = app_joint_qdesn_bind_rows(list(fit_score$raw_crossing, forecast_score$raw_crossing)),
      contract_crossing = app_joint_qdesn_bind_rows(list(fit_score$contract_crossing, forecast_score$contract_crossing))
    )
  })
  bind <- function(name) app_joint_qdesn_bind_rows(lapply(results, `[[`, name))
  summary <- bind("summary")
  modern <- bind("modern")
  stability <- bind("stability")
  group_spread <- stats::aggregate(cbind(fit_truth_mae, forecast_truth_mae) ~ scenario_id, stability, function(x) diff(range(x)))
  names(group_spread)[2:3] <- c("chain_group_fit_mae_range", "chain_group_forecast_mae_range")
  assessment <- merge(summary, group_spread, by = "scenario_id", all.x = TRUE, sort = FALSE)
  assessment$chain_group_practical_tolerance <- pmax(0.0025, 0.02 * assessment$forecast_truth_mae)
  assessment$chain_group_stability_status <- ifelse(
    assessment$chain_group_forecast_mae_range <= assessment$chain_group_practical_tolerance,
    "pass", "review"
  )
  assessment$implementation_status <- ifelse(
    assessment$all_draws_finite & assessment$contract_crossing_pairs == 0L, "pass", "fail"
  )
  assessment$mixing_status <- ifelse(
    pmax(assessment$max_gamma_rank_rhat, assessment$max_sigma_rank_rhat) <= 1.05 &
      pmin(assessment$min_gamma_bulk_ess, assessment$min_sigma_bulk_ess) >= 400, "pass", "review"
  )
  baseline_path <- file.path(freeze$config$phase150_mcmc_dir[[1L]], "mcmc_case_summary.csv")
  comparison <- summary
  if (file.exists(baseline_path)) {
    baseline <- app_joint_exqdesn_phase156_read_csv(baseline_path)
    baseline <- baseline[, intersect(c("scenario_id", "mcmc_fit_truth_mae", "mcmc_forecast_truth_mae"), names(baseline)), drop = FALSE]
    names(baseline)[names(baseline) == "mcmc_fit_truth_mae"] <- "phase150_fit_truth_mae"
    names(baseline)[names(baseline) == "mcmc_forecast_truth_mae"] <- "phase150_forecast_truth_mae"
    comparison <- merge(summary, baseline, by = "scenario_id", all.x = TRUE, sort = FALSE)
    comparison$delta_fit_mae_vs_phase150 <- comparison$fit_truth_mae - comparison$phase150_fit_truth_mae
    comparison$delta_forecast_mae_vs_phase150 <- comparison$forecast_truth_mae - comparison$phase150_forecast_truth_mae
  }
  phase154_path <- file.path(freeze$config$phase154_dir[[1L]], "final_case_audit.csv")
  if (file.exists(phase154_path)) {
    al <- app_joint_exqdesn_phase156_read_csv(phase154_path)
    al <- al[al$source_model_id == "joint_qdesn_rhs_vb", , drop = FALSE]
    al <- al[, intersect(c(
      "scenario_id", "mcmc_fit_truth_mae", "mcmc_forecast_truth_mae",
      "mcmc_forecast_check_loss_mean"
    ), names(al)), drop = FALSE]
    names(al)[names(al) == "mcmc_fit_truth_mae"] <- "matched_al_fit_truth_mae"
    names(al)[names(al) == "mcmc_forecast_truth_mae"] <- "matched_al_forecast_truth_mae"
    names(al)[names(al) == "mcmc_forecast_check_loss_mean"] <- "matched_al_forecast_check_loss_mean"
    comparison <- merge(comparison, al, by = "scenario_id", all.x = TRUE, sort = FALSE)
    comparison$delta_fit_mae_vs_matched_al <- comparison$fit_truth_mae - comparison$matched_al_fit_truth_mae
    comparison$delta_forecast_mae_vs_matched_al <- comparison$forecast_truth_mae - comparison$matched_al_forecast_truth_mae
    comparison$delta_forecast_check_loss_vs_matched_al <- comparison$forecast_check_loss_mean - comparison$matched_al_forecast_check_loss_mean
    comparison$practical_forecast_mae_tolerance <- pmax(0.0025, 0.02 * comparison$matched_al_forecast_truth_mae)
    comparison$fit_guard_pass <- comparison$fit_truth_mae <= 1.05 * comparison$matched_al_fit_truth_mae
    comparison$check_loss_guard_pass <- comparison$forecast_check_loss_mean <= 1.02 * comparison$matched_al_forecast_check_loss_mean
    benchmark_complete <- is.finite(comparison$matched_al_fit_truth_mae) &
      is.finite(comparison$matched_al_forecast_truth_mae) &
      is.finite(comparison$matched_al_forecast_check_loss_mean)
    comparison$performance_status <- ifelse(
      !benchmark_complete,
      "benchmark_unavailable_review",
      ifelse(comparison$delta_forecast_mae_vs_matched_al <= -comparison$practical_forecast_mae_tolerance &
        comparison$fit_guard_pass & comparison$check_loss_guard_pass,
      "material_improvement",
      ifelse(
        comparison$delta_forecast_mae_vs_matched_al <= comparison$practical_forecast_mae_tolerance &
          comparison$fit_guard_pass & comparison$check_loss_guard_pass,
        "competitive", "underperformance_review"
      ))
    )
    performance <- comparison[, c("scenario_id", "performance_status"), drop = FALSE]
    assessment <- merge(assessment, performance, by = "scenario_id", all.x = TRUE, sort = FALSE)
  } else {
    assessment$performance_status <- "benchmark_unavailable_review"
  }
  assessment$gate_status <- ifelse(assessment$implementation_status == "fail", "fail", ifelse(
    assessment$mixing_status == "review" | assessment$raw_crossing_pairs > 0L |
      assessment$chain_group_stability_status == "review" |
      assessment$performance_status %in% c("underperformance_review", "benchmark_unavailable_review"),
    "review", "pass"
  ))
  assessment$gate_reason <- ifelse(
    assessment$implementation_status == "fail", "nonfinite draws or contract crossing",
    ifelse(assessment$chain_group_stability_status == "review", "four-chain posterior score groups differ beyond the scale-aware practical tolerance", ifelse(
      assessment$performance_status == "underperformance_review", "quantile-grid performance is materially worse than the matched AL benchmark", ifelse(
        assessment$performance_status == "benchmark_unavailable_review", "matched AL benchmark is missing or incomplete", ifelse(
          assessment$mixing_status == "review", "parameter mixing remains review-level; interpret with MCSE and qhat stability", ifelse(
            assessment$raw_crossing_pairs > 0L, "raw grid required the declared monotone contract", "all declared gates pass"
          )
        )
      )
    ))
  )
  fit_scored <- bind("fit")
  forecast_scored <- bind("forecast")
  fit_truth_summary <- app_joint_qdesn_truth_summary(fit_scored)
  forecast_truth_summary <- app_joint_qdesn_truth_summary(forecast_scored)
  fit_check_summary <- app_joint_qdesn_check_loss_summary(fit_scored)
  forecast_check_summary <- app_joint_qdesn_check_loss_summary(forecast_scored)
  fit_hit_summary <- app_joint_qdesn_hit_rate_summary(fit_scored)
  forecast_hit_summary <- app_joint_qdesn_hit_rate_summary(forecast_scored)
  fit_crps_summary <- app_joint_qdesn_crps_grid_summary(fit_scored)
  forecast_crps_summary <- app_joint_qdesn_crps_grid_summary(forecast_scored)
  fit_interval_summary <- app_joint_qdesn_interval_summary(fit_scored)
  forecast_interval_summary <- app_joint_qdesn_interval_summary(forecast_scored)
  worker_manifest_verification <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(freeze$plan)), function(ii) {
    app_joint_qdesn_phase108_manifest_verify(
      freeze$plan$worker_output_dir[[ii]],
      sprintf("worker_%03d", freeze$plan$worker_id[[ii]])
    )
  }))
  if (!nrow(worker_manifest_verification) || any(worker_manifest_verification$status != "pass")) {
    stop("Phase157 worker manifest verification failed during finalization.", call. = FALSE)
  }
  final_config <- freeze$config
  final_config$finalizer <- "app_joint_exqdesn_finalize_phase157"
  final_config$posterior_summary <- "pooled_posterior_mean_quantile_grid"
  final_config$scoring_contract <- "monotone_quantile_grid_with_raw_diagnostics_preserved"
  final_config$finalized_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Phase157 collapsed gamma-scale MCMC confirmation", "",
    "This artifact pools eight independently resumable chains for each of the eight case-specific Joint exQDESN specifications frozen in Phase156.",
    "Reported fit and forecast scores use posterior-mean quantile grids after the declared monotone contract. Raw crossings remain visible diagnostics.",
    "Mixing is a review gate rather than an automatic performance failure: rank-normalized split R-hat, folded R-hat, bulk/tail ESS, MCSE, rank histograms, and chain-group score stability are all retained.",
    "Phase150 comparisons must be interpreted with the prior-contract audit because the older prototype MCMC path used legacy scale/intercept defaults."
  ), readme, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(final_config, file.path(out_dir, "run_config.csv")),
    freeze_manifest_verification = app_joint_qvp_write_csv(freeze$manifest, file.path(out_dir, "freeze_manifest_verification.csv")),
    worker_manifest_verification = app_joint_qvp_write_csv(worker_manifest_verification, file.path(out_dir, "worker_manifest_verification.csv")),
    chain_inventory = app_joint_qvp_write_csv(health$inventory, file.path(out_dir, "phase157_chain_inventory.csv")),
    mcmc_case_summary = app_joint_qvp_write_csv(summary, file.path(out_dir, "mcmc_case_summary.csv")),
    mcmc_case_assessment = app_joint_qvp_write_csv(assessment, file.path(out_dir, "mcmc_case_assessment.csv")),
    phase150_comparison = app_joint_qvp_write_csv(comparison, file.path(out_dir, "phase150_comparison.csv")),
    fit_truth_summary = app_joint_qvp_write_csv(fit_truth_summary, file.path(out_dir, "fit_truth_summary.csv")),
    forecast_truth_summary = app_joint_qvp_write_csv(forecast_truth_summary, file.path(out_dir, "forecast_truth_summary.csv")),
    fit_check_loss_summary = app_joint_qvp_write_csv(fit_check_summary, file.path(out_dir, "fit_check_loss_summary.csv")),
    forecast_check_loss_summary = app_joint_qvp_write_csv(forecast_check_summary, file.path(out_dir, "forecast_check_loss_summary.csv")),
    fit_hit_rate_summary = app_joint_qvp_write_csv(fit_hit_summary, file.path(out_dir, "fit_hit_rate_summary.csv")),
    forecast_hit_rate_summary = app_joint_qvp_write_csv(forecast_hit_summary, file.path(out_dir, "forecast_hit_rate_summary.csv")),
    fit_crps_grid_summary = app_joint_qvp_write_csv(fit_crps_summary, file.path(out_dir, "fit_crps_grid_summary.csv")),
    forecast_crps_grid_summary = app_joint_qvp_write_csv(forecast_crps_summary, file.path(out_dir, "forecast_crps_grid_summary.csv")),
    fit_interval_summary = app_joint_qvp_write_csv(fit_interval_summary, file.path(out_dir, "fit_interval_summary.csv")),
    forecast_interval_summary = app_joint_qvp_write_csv(forecast_interval_summary, file.path(out_dir, "forecast_interval_summary.csv")),
    modern_diagnostics = app_joint_qvp_write_csv(modern, file.path(out_dir, "modern_mcmc_diagnostics.csv")),
    classic_diagnostics = app_joint_qvp_write_csv(bind("classic"), file.path(out_dir, "classic_mcmc_diagnostics.csv")),
    trace_summary = app_joint_qvp_write_csv(bind("trace_summary"), file.path(out_dir, "mcmc_trace_summary.csv")),
    autocorrelation = app_joint_qvp_write_csv(bind("autocorrelation"), file.path(out_dir, "mcmc_autocorrelation.csv")),
    rank_histogram = app_joint_qvp_write_csv(bind("rank_histogram"), file.path(out_dir, "mcmc_rank_histogram.csv")),
    gamma_sigma_correlation = app_joint_qvp_write_csv(bind("correlation"), file.path(out_dir, "gamma_sigma_correlation.csv")),
    chain_group_stability = app_joint_qvp_write_csv(stability, file.path(out_dir, "chain_group_qhat_stability.csv")),
    fit_quantiles = app_joint_qvp_write_csv(bind("fit"), file.path(out_dir, "mcmc_fit_quantiles.csv")),
    forecast_quantiles = app_joint_qvp_write_csv(bind("forecast"), file.path(out_dir, "mcmc_forecast_quantiles.csv")),
    monotone_adjustment = app_joint_qvp_write_csv(bind("adjustment"), file.path(out_dir, "mcmc_monotone_adjustment.csv")),
    raw_crossing = app_joint_qvp_write_csv(bind("raw_crossing"), file.path(out_dir, "raw_crossing_summary.csv")),
    contract_crossing = app_joint_qvp_write_csv(bind("contract_crossing"), file.path(out_dir, "crossing_summary.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_trace_manifest(paths, out_dir)
  list(out_dir = out_dir, summary = summary, assessment = assessment,
       comparison = comparison, paths = c(paths, artifact_manifest = manifest$manifest_path))
}
