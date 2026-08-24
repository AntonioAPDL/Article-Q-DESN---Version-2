# Phase160 independent confirmation of the two Phase159 split-RHS candidates.

app_joint_exqdesn_phase160_default_phase159_dir <- function() {
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase159_split_rhs_calibration_mcmc_20260804"
}

app_joint_exqdesn_phase160_default_phase159_freeze_dir <- function() {
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase159_split_rhs_calibration_freeze_20260804"
}

app_joint_exqdesn_phase160_default_phase157_dir <- function() {
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802"
}

app_joint_exqdesn_phase160_default_freeze_dir <- function() {
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase160_split_rhs_independent_confirmation_freeze_20260805"
}

app_joint_exqdesn_phase160_default_output_dir <- function() {
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase160_split_rhs_independent_confirmation_mcmc_20260805"
}

app_joint_exqdesn_phase160_source_snapshot <- function() {
  relative_path <- c(
    "application/R/joint_qvp_qdesn.R",
    "application/R/joint_exqdesn_phase156_collapsed_gamma_sigma.R",
    "application/R/joint_exqdesn_phase159_split_rhs_screening.R",
    "application/R/joint_exqdesn_phase160_independent_confirmation.R",
    "application/scripts/202_prepare_joint_exqdesn_phase160_confirmation.R",
    "application/scripts/203_run_joint_exqdesn_phase160_worker.R",
    "application/scripts/204_finalize_joint_exqdesn_phase160_confirmation.R",
    "application/scripts/205_check_joint_exqdesn_phase160_confirmation.R",
    "application/scripts/206_launch_joint_exqdesn_phase160_confirmation.sh",
    "application/tests/test_joint_exqdesn_phase160_confirmation.R"
  )
  full_path <- app_path(relative_path)
  data.frame(
    relative_path = relative_path,
    size_bytes = as.numeric(file.info(full_path)$size),
    sha256 = vapply(full_path, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase160_seed_plan <- function(registry, n_chains = 8L,
                                                  seed_base = 202608050L,
                                                  chain_seed_stride = 1009L) {
  rows <- list()
  worker_id <- 0L
  for (ii in seq_len(nrow(registry))) {
    for (chain_id in seq_len(as.integer(n_chains))) {
      worker_id <- worker_id + 1L
      rows[[worker_id]] <- data.frame(
        worker_id = worker_id,
        candidate_index = ii,
        candidate_id = registry$candidate_id[[ii]],
        scenario_id = registry$scenario_ids[[ii]],
        chain_id = chain_id,
        chain_seed = as.integer(seed_base + ii * 100000L + (chain_id - 1L) * chain_seed_stride),
        seed_role = "phase160_independent_mcmc_chain",
        stringsAsFactors = FALSE
      )
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  if (anyDuplicated(out$chain_seed)) stop("Phase160 chain seeds are not unique.", call. = FALSE)
  out
}

app_joint_exqdesn_phase160_read_optional_csv <- function(path) {
  if (!file.exists(path)) return(data.frame())
  app_joint_exqdesn_phase156_read_csv(path)
}

app_joint_exqdesn_phase160_prepare <- function(
  freeze_dir = app_joint_exqdesn_phase160_default_freeze_dir(),
  output_dir = app_joint_exqdesn_phase160_default_output_dir(),
  phase159_dir = app_joint_exqdesn_phase160_default_phase159_dir(),
  phase159_freeze_dir = app_joint_exqdesn_phase160_default_phase159_freeze_dir(),
  phase157_dir = app_joint_exqdesn_phase160_default_phase157_dir(),
  n_chains = 8L, n_iter = 12000L, burn = 3000L, thin = 3L,
  workers = 16L, seed_base = 202608050L, chain_seed_stride = 1009L
) {
  dirs <- lapply(c(phase159_dir, phase159_freeze_dir, phase157_dir), normalizePath, mustWork = TRUE)
  phase159_dir <- dirs[[1L]]; phase159_freeze_dir <- dirs[[2L]]; phase157_dir <- dirs[[3L]]
  freeze_dir <- normalizePath(freeze_dir, mustWork = FALSE)
  output_dir <- normalizePath(output_dir, mustWork = FALSE)
  app_ensure_dir(freeze_dir); app_ensure_dir(output_dir)
  verification <- app_joint_qdesn_bind_rows(list(
    app_joint_exqdesn_phase158_verify_source(phase159_dir, "phase159_results"),
    app_joint_exqdesn_phase158_verify_source(phase159_freeze_dir, "phase159_freeze"),
    app_joint_exqdesn_phase158_verify_source(phase157_dir, "phase157b_reference")
  ))
  if (any(verification$status != "pass")) stop("Phase160 source manifest verification failed.", call. = FALSE)
  assessment <- app_joint_exqdesn_phase156_read_csv(file.path(phase159_dir, "phase159_assessment.csv"))
  selection <- app_joint_exqdesn_phase156_read_csv(file.path(phase159_dir, "scenario_selection.csv"))
  if (assessment$gate_status[[1L]] != "pass") stop("Phase160 blocked by Phase159 implementation gate.", call. = FALSE)
  selected <- selection[selection$material_gain %in% TRUE, , drop = FALSE]
  if (nrow(selected) != 2L) stop("Phase160 requires exactly two prespecified Phase159 survivors.", call. = FALSE)
  parent <- app_joint_exqdesn_phase159_load_freeze(phase159_freeze_dir)
  registry <- parent$registry[parent$registry$candidate_id %in% selected$selected_candidate_id, , drop = FALSE]
  registry <- registry[match(selected$selected_candidate_id, registry$candidate_id), , drop = FALSE]
  if (nrow(registry) != 2L || anyNA(registry$candidate_id)) stop("Phase160 survivor registry mismatch.", call. = FALSE)
  registry$phase159_screen_forecast_truth_mae <- selected$selected_forecast_truth_mae
  registry$phase159_screen_material_gain <- selected$material_gain
  registry$confirmation_role <- "independent_eight_chain_candidate"
  registry$selection_source <- "phase159_case_specific_four_chain_screen"
  registry$worker_root <- file.path(output_dir, "candidates", registry$scenario_ids, registry$candidate_role)
  init <- parent$init[parent$init$candidate_id %in% registry$candidate_id, , drop = FALSE]
  if (!nrow(init) || any(!is.finite(init$value))) stop("Phase160 frozen VB initialization is invalid.", call. = FALSE)
  plan <- app_joint_exqdesn_phase160_seed_plan(registry, n_chains, seed_base, chain_seed_stride)
  plan$n_iter <- as.integer(n_iter); plan$burn <- as.integer(burn); plan$thin <- as.integer(thin)
  plan$n_keep <- as.integer((n_iter - burn) / thin)
  plan$worker_output_dir <- mapply(
    function(candidate_id, scenario_id, chain_id) {
      root <- registry$worker_root[match(candidate_id, registry$candidate_id)]
      file.path(root, sprintf("chain_%02d", chain_id))
    }, plan$candidate_id, plan$scenario_id, plan$chain_id, USE.NAMES = FALSE
  )
  fixture_dir <- parent$config$fixture_dir[[1L]]
  artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)
  starts <- list()
  for (ii in seq_len(nrow(registry))) {
    row <- registry[ii, , drop = FALSE]
    block <- function(name) {
      x <- init[init$candidate_id == row$candidate_id[[1L]] & init$parameter_block == name, , drop = FALSE]
      x$value[order(x$parameter_index)]
    }
    init_case <- list(beta_mean = block("beta"), alpha_mean = block("alpha"),
                      sigma_mean = block("sigma"), gamma_mean = block("gamma"))
    fixture <- app_joint_qdesn_scenario_fixture(artifacts, row$scenario_ids[[1L]], role = "fit")
    start <- app_joint_exqdesn_phase156_chain_starts(init_case, fixture$tau, row$candidate_id[[1L]], n_chains)
    start$candidate_id <- start$scenario_id
    start$scenario_id <- row$scenario_ids[[1L]]
    starts[[ii]] <- start
  }
  starts <- app_joint_qdesn_bind_rows(starts)
  historical <- unique(c(
    app_joint_exqdesn_phase160_read_optional_csv(file.path(phase159_freeze_dir, "chain_plan.csv"))$chain_seed,
    app_joint_exqdesn_phase160_read_optional_csv(file.path(dirname(phase157_dir), "joint_qdesn_phase156b_collapsed_gamma_sigma_recovery_freeze_20260802", "phase157_chain_plan.csv"))$chain_seed,
    app_joint_exqdesn_phase160_read_optional_csv(file.path(phase157_dir, "phase157_chain_inventory.csv"))$chain_seed
  ))
  historical <- historical[is.finite(historical)]
  seed_audit <- data.frame(
    planned_seeds = nrow(plan), unique_planned_seeds = length(unique(plan$chain_seed)),
    historical_seeds_checked = length(unique(historical)),
    overlaps_with_historical = sum(plan$chain_seed %in% historical),
    seed_base = as.integer(seed_base), chain_seed_stride = as.integer(chain_seed_stride),
    stringsAsFactors = FALSE
  )
  if (seed_audit$overlaps_with_historical[[1L]] > 0L) stop("Phase160 seeds overlap prior campaigns.", call. = FALSE)
  reference <- app_joint_exqdesn_phase156_read_csv(file.path(phase157_dir, "phase150_comparison.csv"))
  reference <- reference[reference$scenario_id %in% registry$scenario_ids, , drop = FALSE]
  if (nrow(reference) != 2L || any(reference$n_chains != 8L)) stop("Phase160 requires two eight-chain Phase157b references.", call. = FALSE)
  config <- data.frame(
    phase_id = "phase160_split_rhs_independent_confirmation",
    phase159_dir = phase159_dir, phase159_freeze_dir = phase159_freeze_dir,
    phase157_reference_dir = phase157_dir, fixture_dir = fixture_dir, output_dir = output_dir,
    scenarios = 2L, candidates = 2L, n_chains = as.integer(n_chains),
    n_iter = as.integer(n_iter), burn = as.integer(burn), thin = as.integer(thin),
    n_keep_per_chain = as.integer((n_iter - burn) / thin), workers = as.integer(workers),
    seed_base = as.integer(seed_base), chain_seed_stride = as.integer(chain_seed_stride),
    gamma_update = "collapsed_logit_slice", gamma_slice_width = 4,
    gamma_slice_max_steps = 250L, reference_reuse = "verified_phase157b_eight_chain",
    selection_scope = "scenario_specific", article_assets_modified = FALSE,
    stringsAsFactors = FALSE
  )
  readiness <- data.frame(
    gate_status = "pass", selected_candidates = nrow(registry), planned_workers = nrow(plan),
    source_hash_failures = sum(verification$status != "pass"),
    seed_overlaps = seed_audit$overlaps_with_historical[[1L]],
    finite_vb_initialization = all(is.finite(init$value)),
    reference_rows = nrow(reference),
    recommendation = "launch_phase160_independent_confirmation", stringsAsFactors = FALSE
  )
  readme <- file.path(freeze_dir, "README.md")
  writeLines(c(
    "# Phase160 independent split-RHS confirmation freeze", "",
    "This freeze confirms only the two prespecified Phase159 survivors with new seeds.",
    "It reuses the verified Phase157b eight-chain references and does not rerun baseline models.", "",
    sprintf("- Candidates: %d", nrow(registry)), sprintf("- New chains: %d", nrow(plan)),
    sprintf("- Iterations per chain: %d", n_iter), sprintf("- Retained draws per chain: %d", (n_iter - burn) / thin)
  ), readme, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(config, file.path(freeze_dir, "run_config.csv")),
    source_manifest_verification = app_joint_qvp_write_csv(verification, file.path(freeze_dir, "source_manifest_verification.csv")),
    selected_candidate_registry = app_joint_qvp_write_csv(registry, file.path(freeze_dir, "selected_candidate_registry.csv")),
    vb_initialization = app_joint_qvp_write_csv(init, file.path(freeze_dir, "vb_initialization.csv")),
    chain_start_values = app_joint_qvp_write_csv(starts, file.path(freeze_dir, "chain_start_values.csv")),
    chain_plan = app_joint_qvp_write_csv(plan, file.path(freeze_dir, "chain_plan.csv")),
    seed_independence_audit = app_joint_qvp_write_csv(seed_audit, file.path(freeze_dir, "seed_independence_audit.csv")),
    phase157b_reference = app_joint_qvp_write_csv(reference, file.path(freeze_dir, "phase157b_reference.csv")),
    readiness_assessment = app_joint_qvp_write_csv(readiness, file.path(freeze_dir, "readiness_assessment.csv")),
    source_code_snapshot = app_joint_qvp_write_csv(app_joint_exqdesn_phase160_source_snapshot(), file.path(freeze_dir, "source_code_snapshot.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(freeze_dir, "provenance.csv")),
    readme = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_trace_manifest(paths, freeze_dir)
  list(freeze_dir = freeze_dir, readiness = readiness, registry = registry, plan = plan,
       paths = c(paths, artifact_manifest = manifest$manifest_path))
}

app_joint_exqdesn_phase160_load_freeze <- function(freeze_dir) {
  freeze_dir <- normalizePath(freeze_dir, mustWork = TRUE)
  list(
    dir = freeze_dir,
    verification = app_joint_exqdesn_phase158_verify_source(freeze_dir, "phase160_freeze"),
    config = app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "run_config.csv")),
    registry = app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "selected_candidate_registry.csv")),
    init = app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "vb_initialization.csv")),
    starts = app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "chain_start_values.csv")),
    plan = app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "chain_plan.csv")),
    reference = app_joint_exqdesn_phase156_read_csv(file.path(freeze_dir, "phase157b_reference.csv"))
  )
}

app_joint_exqdesn_phase160_worker_complete <- function(dir) app_joint_exqdesn_phase157_worker_complete(dir)

app_joint_exqdesn_phase160_run_worker <- function(freeze_dir, worker_id) {
  freeze <- app_joint_exqdesn_phase160_load_freeze(freeze_dir)
  job <- freeze$plan[freeze$plan$worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(job) != 1L) stop("Unknown Phase160 worker.", call. = FALSE)
  out_dir <- job$worker_output_dir[[1L]]
  if (app_joint_exqdesn_phase160_worker_complete(out_dir)) return(list(status = "reused_verified", out_dir = out_dir))
  if (dir.exists(out_dir) && length(list.files(out_dir, all.files = TRUE, no.. = TRUE))) {
    quarantine <- paste0(out_dir, "_incomplete_", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(out_dir, quarantine)) stop("Could not quarantine incomplete Phase160 worker output.", call. = FALSE)
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
    a_sigma = row$a_sigma[[1L]], b_sigma = row$b_sigma[[1L]], gamma_init = init$gamma_mean, init = init,
    alpha_prior_mean = "empirical_quantile", alpha_prior_sd = row$alpha_prior_sd[[1L]],
    alpha_min_spacing = row$alpha_min_spacing[[1L]], max_dense_dim = row$max_dense_dim[[1L]],
    sigma_bounds = c(1.0e-8, max(1, 50 * max(init$sigma_mean))),
    gamma_update = "collapsed_logit_slice", gamma_slice_width = 4,
    gamma_slice_max_steps = 250L, gamma_refresh_repeats = 1L, gamma_refresh_block = "none"
  )
  elapsed <- proc.time()[["elapsed"]] - start
  draws <- app_joint_exqdesn_phase157_draw_frame(fit)
  if (any(!is.finite(as.matrix(draws[, -1L, drop = FALSE]))) || any(fit$sigma_draws <= 0)) stop("Invalid Phase160 draws.", call. = FALSE)
  summary <- data.frame(
    worker_id = job$worker_id[[1L]], candidate_id = job$candidate_id[[1L]], scenario_id = job$scenario_id[[1L]],
    chain_id = job$chain_id[[1L]], chain_seed = job$chain_seed[[1L]], seed_role = job$seed_role[[1L]],
    n_keep = nrow(draws), anchor_tau0 = row$anchor_tau0[[1L]], innovation_tau0 = row$innovation_tau0[[1L]],
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
  writeLines(c("# Phase160 confirmation chain", "", sprintf("- Candidate: `%s`", job$candidate_id[[1L]]),
               sprintf("- Chain: %d", job$chain_id[[1L]]), sprintf("- Independent seed: %d", job$chain_seed[[1L]])), readme)
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

app_joint_exqdesn_phase160_health <- function(freeze_dir) {
  freeze <- app_joint_exqdesn_phase160_load_freeze(freeze_dir)
  state <- vapply(freeze$plan$worker_output_dir, function(dir) {
    if (app_joint_exqdesn_phase160_worker_complete(dir)) "complete_verified" else "remaining"
  }, character(1L))
  inventory <- cbind(freeze$plan, state = state, stringsAsFactors = FALSE)
  summary <- data.frame(
    planned_workers = nrow(inventory), complete_verified = sum(state == "complete_verified"),
    remaining = sum(state == "remaining"), percent_complete = 100 * mean(state == "complete_verified"),
    all_complete = all(state == "complete_verified"), stringsAsFactors = FALSE
  )
  list(summary = summary, inventory = inventory)
}

app_joint_exqdesn_phase160_finalize <- function(freeze_dir, output_dir) {
  freeze <- app_joint_exqdesn_phase160_load_freeze(freeze_dir)
  health <- app_joint_exqdesn_phase160_health(freeze_dir)
  if (!health$summary$all_complete[[1L]]) stop("Phase160 cannot finalize before all workers verify.", call. = FALSE)
  output_dir <- normalizePath(output_dir, mustWork = TRUE)
  artifacts <- app_joint_qdesn_load_fixture_artifacts(freeze$config$fixture_dir[[1L]])
  tau_rows <- list(); summaries <- list(); diagnostics <- list(); runtimes <- list()
  for (ii in seq_len(nrow(freeze$registry))) {
    row <- freeze$registry[ii, , drop = FALSE]
    jobs <- freeze$plan[freeze$plan$candidate_id == row$candidate_id[[1L]], , drop = FALSE]
    fixture <- app_joint_qdesn_scenario_fixture(artifacts, row$scenario_ids[[1L]], role = "fit")
    fits <- lapply(seq_len(nrow(jobs)), function(jj) app_joint_exqdesn_phase157_read_fit(
      jobs$worker_output_dir[[jj]], fixture$tau, jobs$chain_seed[[jj]], jobs$chain_id[[jj]]
    ))
    pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(fits, fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau)
    spec <- app_joint_qdesn_phase122_select_spec("joint_exqdesn_rhs_vb")
    meta <- app_joint_qdesn_phase122_meta(fixture, spec, row, "MCMC", "joint_exqdesn_rhs_mcmc_phase160")
    fit <- app_joint_qdesn_phase122_score_qhat(meta, fixture, app_joint_qdesn_predict_fit(pooled, fixture$Z, fixture$tau), "qhat", "phase160_fit")
    forecast <- app_joint_qdesn_phase122_forecast_scores(meta, artifacts, row$scenario_ids[[1L]], fixture, pooled, "qhat", "phase160_forecast")
    modern <- app_joint_exqdesn_modern_diagnostic_rows(fits, fixture$tau, meta)
    tau_summary <- aggregate(
      cbind(truth_abs_error, check_loss) ~ scenario_id + tau,
      forecast$scored, mean, na.rm = TRUE
    )
    names(tau_summary)[names(tau_summary) == "truth_abs_error"] <- "forecast_truth_mae"
    names(tau_summary)[names(tau_summary) == "check_loss"] <- "forecast_check_loss"
    tau_summary$candidate_id <- row$candidate_id[[1L]]
    tau_rows[[ii]] <- tau_summary
    summaries[[ii]] <- data.frame(
      scenario_id = row$scenario_ids[[1L]], candidate_id = row$candidate_id[[1L]],
      candidate_role = row$candidate_role[[1L]], anchor_tau0 = row$anchor_tau0[[1L]],
      innovation_tau0 = row$innovation_tau0[[1L]], anchor_zeta2 = row$anchor_zeta2[[1L]],
      innovation_zeta2 = row$innovation_zeta2[[1L]], n_chains = length(fits),
      n_keep_total = nrow(pooled$beta_draws), fit_truth_mae = mean(fit$scored$truth_abs_error),
      forecast_truth_mae = mean(forecast$scored$truth_abs_error),
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
    diagnostics[[ii]] <- modern
    runtimes[[ii]] <- app_joint_qdesn_bind_rows(lapply(jobs$worker_output_dir, function(dir) {
      app_joint_exqdesn_phase156_read_csv(file.path(dir, "chain_summary.csv"))
    }))
  }
  summary <- app_joint_qdesn_bind_rows(summaries)
  reference <- freeze$reference
  comparison <- merge(summary, reference[, c(
    "scenario_id", "fit_truth_mae", "forecast_truth_mae", "forecast_check_loss_mean",
    "forecast_crps_grid_mean", "matched_al_fit_truth_mae", "matched_al_forecast_truth_mae",
    "matched_al_forecast_check_loss_mean"
  )], by = "scenario_id", suffixes = c("_candidate", "_phase157b"), all.x = TRUE)
  comparison$delta_forecast_mae_vs_phase157b <- comparison$forecast_truth_mae_candidate - comparison$forecast_truth_mae_phase157b
  comparison$relative_forecast_mae_change_pct <- 100 * comparison$delta_forecast_mae_vs_phase157b / comparison$forecast_truth_mae_phase157b
  comparison$delta_fit_mae_vs_phase157b <- comparison$fit_truth_mae_candidate - comparison$fit_truth_mae_phase157b
  comparison$delta_check_loss_vs_phase157b <- comparison$forecast_check_loss - comparison$forecast_check_loss_mean
  comparison$delta_crps_vs_phase157b <- comparison$forecast_crps_grid - comparison$forecast_crps_grid_mean
  comparison$delta_forecast_mae_vs_matched_al <- comparison$forecast_truth_mae_candidate - comparison$matched_al_forecast_truth_mae
  threshold <- pmax(0.0025, 0.02 * comparison$forecast_truth_mae_phase157b)
  comparison$implementation_pass <- comparison$all_finite & comparison$contract_crossing_pairs == 0L
  comparison$performance_pass <- comparison$delta_forecast_mae_vs_phase157b <= -threshold &
    comparison$fit_truth_mae_candidate <= 1.05 * comparison$fit_truth_mae_phase157b &
    comparison$forecast_check_loss <= 1.02 * comparison$forecast_check_loss_mean &
    comparison$forecast_crps_grid <= 1.02 * comparison$forecast_crps_grid_mean
  comparison$mixing_pass <- comparison$max_rank_rhat <= 1.10 & comparison$min_bulk_ess >= 100
  comparison$mixing_review <- comparison$max_rank_rhat <= 1.10 & comparison$min_bulk_ess >= 50
  comparison$decision <- ifelse(
    !comparison$implementation_pass, "fail_implementation",
    ifelse(comparison$performance_pass & comparison$mixing_pass, "confirmed_for_article_candidate_review",
      ifelse(comparison$performance_pass & comparison$mixing_review, "performance_confirmed_mixing_review", "not_confirmed_retain_phase157b"))
  )
  assessment <- data.frame(
    gate_status = if (all(comparison$implementation_pass)) "pass" else "fail",
    scenarios = nrow(comparison), workers = nrow(freeze$plan),
    confirmed = sum(comparison$decision == "confirmed_for_article_candidate_review"),
    mixing_review = sum(comparison$decision == "performance_confirmed_mixing_review"),
    not_confirmed = sum(comparison$decision == "not_confirmed_retain_phase157b"),
    recommendation = if (any(grepl("confirmed", comparison$decision))) "audit_confirmed_case_winners_before_article_integration" else "retain_phase157b_and_close_split_rhs_branch",
    stringsAsFactors = FALSE
  )
  worker_verification <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(freeze$plan)), function(ii) {
    app_joint_qdesn_phase108_manifest_verify(freeze$plan$worker_output_dir[[ii]], sprintf("worker_%03d", freeze$plan$worker_id[[ii]]))
  }))
  readme <- file.path(output_dir, "README.md")
  writeLines(c(
    "# Phase160 independent split-RHS confirmation", "",
    "Two Phase159 survivors are evaluated with eight new chains and new seeds.",
    "The comparator is the frozen Phase157b eight-chain reference. No article asset is modified."
  ), readme, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(freeze$config, file.path(output_dir, "run_config.csv")),
    freeze_manifest_verification = app_joint_qvp_write_csv(freeze$verification, file.path(output_dir, "freeze_manifest_verification.csv")),
    worker_manifest_verification = app_joint_qvp_write_csv(worker_verification, file.path(output_dir, "worker_manifest_verification.csv")),
    chain_inventory = app_joint_qvp_write_csv(health$inventory, file.path(output_dir, "chain_inventory.csv")),
    confirmation_summary = app_joint_qvp_write_csv(summary, file.path(output_dir, "confirmation_summary.csv")),
    phase157b_comparison = app_joint_qvp_write_csv(comparison, file.path(output_dir, "phase157b_comparison.csv")),
    tau_summary = app_joint_qvp_write_csv(app_joint_qdesn_bind_rows(tau_rows), file.path(output_dir, "tau_summary.csv")),
    modern_mcmc_diagnostics = app_joint_qvp_write_csv(app_joint_qdesn_bind_rows(diagnostics), file.path(output_dir, "modern_mcmc_diagnostics.csv")),
    runtime_summary = app_joint_qvp_write_csv(app_joint_qdesn_bind_rows(runtimes), file.path(output_dir, "runtime_summary.csv")),
    phase160_assessment = app_joint_qvp_write_csv(assessment, file.path(output_dir, "phase160_assessment.csv")),
    finalizer_source_code_snapshot = app_joint_qvp_write_csv(app_joint_exqdesn_phase160_source_snapshot(), file.path(output_dir, "finalizer_source_code_snapshot.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(output_dir, "provenance.csv")),
    readme = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_trace_manifest(paths, output_dir)
  list(assessment = assessment, comparison = comparison, paths = c(paths, artifact_manifest = manifest$manifest_path))
}
