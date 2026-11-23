# Protected score packet for the stronger-window challenger/parity confirmation.

app_joint_swscore_root <- function(root = app_joint_sw_default_root()) {
  file.path(app_joint_swcf_root(root), "score_packet")
}

app_joint_swscore_contract <- function() {
  data.frame(
    name = c("contract_version", "quantile_grid", "trapezoidal_weights",
      "primary_score", "canonical_forecast_policy", "sensitivity_forecast_policy",
      "independent_draw_coupling", "posterior_interval", "vb_score_draws",
      "vb_state_draws", "mcmc_state_draws_per_chain", "path_draws_per_chain",
      "oracle_shards_per_scenario", "oracle_paths_per_shard", "oracle_analytic_tolerance",
      "oracle_split_tolerance", "score_chunk_size", "inverse_cdf_tail_rule",
      "practical_noninferiority_margin", "promotion_unit"),
    value = c("joint_qdesn_stronger_window_score_v1",
      "0.05;0.10;0.25;0.50;0.75;0.90;0.95",
      "0.025;0.100;0.200;0.250;0.200;0.100;0.025",
      "origin_marginal_dgp_integrated_acrps", "recursive_mean_state", "recursive_path",
      "matched_draw_index_with_frozen_permutations", "equal_tailed_95_percent",
      "2000", "600", "200", "40", "8", "4096", "0.01", "0.005",
      "100", "endpoint_clamp", "0.01", "complete_four_model_scenario_packet"),
    stringsAsFactors = FALSE)
}

app_joint_swscore_value <- function(contract, name, numeric = FALSE) {
  row <- contract[contract$name == name, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("Score contract lacks '%s'.", name), call. = FALSE)
  value <- as.character(row$value[[1L]])
  if (numeric) as.numeric(value) else value
}

app_joint_swscore_numvec <- function(contract, name) {
  as.numeric(strsplit(app_joint_swscore_value(contract, name), ";", fixed = TRUE)[[1L]])
}

app_joint_swscore_finalize_mcmc <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); confirmation <- app_joint_swcf_root(root)
  health <- app_joint_swcf_mcmc_health(root)
  if (health$completed[[1L]] != health$expected[[1L]] || health$failed[[1L]] != 0L) {
    stop("Full MCMC is not complete and failure-free.", call. = FALSE)
  }
  plan <- app_read_csv(file.path(confirmation, "mcmc_worker_plan.csv"))
  summaries <- lapply(plan$worker_id, function(id) {
    worker <- app_joint_swcf_worker_dir(root, "mcmc", id)
    verified <- app_joint_shared_verify_manifest(worker,
      file.path(worker, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified)) {
      stop(sprintf("MCMC worker %d manifest is not verified.", id), call. = FALSE)
    }
    app_read_csv(file.path(worker, "summary.csv"))
  })
  summary <- app_bind_rows_fill(summaries)
  if (nrow(summary) != 192L || any(!summary$finite_draws) ||
      any(summary$n_keep != plan$n_keep) ||
      any(app_as_bool_vec(summary$protected_scores_computed)) ||
      any(summary$likelihood_family == "exAL" &
        summary$inference_method_id != "M0_v_collapsed_support_logit")) {
    stop("Full MCMC summary violates the frozen chain contract.", call. = FALSE)
  }
  target_count <- aggregate(posterior_target_sha256 ~ model_cell_id, summary,
    function(x) length(unique(x)))
  if (any(target_count$posterior_target_sha256 != 1L)) {
    stop("Chains within a model cell do not share one posterior target.", call. = FALSE)
  }
  identity_audit <- app_joint_swcf_chain_identity_audit(summary,
    expected_chains = app_joint_swcf_value(app_joint_swcf_contract(),
      "chains_per_cell", TRUE))
  out <- app_joint_swscore_root(root); app_ensure_dir(out)
  contract_path <- app_write_csv(app_joint_swscore_contract(), file.path(out, "score_contract.csv"))
  summary_path <- app_write_csv(summary, file.path(out, "mcmc_worker_summary.csv"))
  target_path <- app_write_csv(target_count, file.path(out, "posterior_target_audit.csv"))
  identity_path <- app_write_csv(identity_audit,
    file.path(out, "complete_chain_identity_audit.csv"))
  cells <- app_read_csv(file.path(confirmation, "model_cell_plan.csv"))
  fixture_manifest <- app_read_csv(file.path(confirmation, "article_fixture_manifest.csv"))
  contract <- app_joint_swscore_contract()
  shards <- as.integer(app_joint_swscore_value(contract, "oracle_shards_per_scenario", TRUE))
  oracle <- app_bind_rows_fill(lapply(seq_len(nrow(fixture_manifest)), function(i) {
    row <- fixture_manifest[i, , drop = FALSE]
    block <- cells[cells$scenario_id == row$scenario_id[[1L]], , drop = FALSE]
    data.frame(scenario_id = row$scenario_id, fixture_path = row$fixture_path,
      design_path = block$design_path[[1L]], shard_id = seq_len(shards),
      oracle_seed = as.integer(903611220L + i * 100000L + seq_len(shards) * 1009L),
      stringsAsFactors = FALSE)
  }))
  oracle$oracle_worker_id <- seq_len(nrow(oracle))
  score <- app_bind_rows_fill(lapply(seq_len(nrow(cells)), function(i) {
    app_bind_rows_fill(lapply(c("vb", "mcmc"), function(method) {
      row <- cells[i, , drop = FALSE]
      row$inference_method <- method
      row$score_seed <- as.integer(1003611220L +
        match(row$scenario_id[[1L]], unique(cells$scenario_id)) * 1000000L +
        match(row$model_id[[1L]], unique(cells$model_id)) * 10000L +
        if (method == "mcmc") 5000L else 0L)
      row$state_seed <- row$score_seed + 1009L
      row$uniform_seed <- row$score_seed + 2018L
      row
    }))
  }))
  score$score_worker_id <- seq_len(nrow(score))
  if (nrow(oracle) != 64L || nrow(score) != 128L ||
      anyDuplicated(oracle$oracle_seed) ||
      anyDuplicated(score[, c("model_cell_id", "inference_method")])) {
    stop("Protected scoring plans are malformed.", call. = FALSE)
  }
  oracle_path <- app_write_csv(oracle, file.path(out, "oracle_worker_plan.csv"))
  score_path <- app_write_csv(score, file.path(out, "score_worker_plan.csv"))
  app_ensure_dir(file.path(out, "oracle_workers")); app_ensure_dir(file.path(out, "cells"))
  readiness <- data.frame(status = "MCMC_COMPLETE_SCORE_CONTRACT_FROZEN_ORACLE_READY",
    mcmc_workers = nrow(summary), oracle_workers = nrow(oracle), score_workers = nrow(score),
    protected_scores_computed = FALSE, stringsAsFactors = FALSE)
  readiness_path <- app_write_csv(readiness, file.path(out, "score_readiness.csv"))
  app_joint_shared_write_manifest(out, c(contract = contract_path, mcmc = summary_path,
    targets = target_path, complete_identities = identity_path,
    oracle_plan = oracle_path, score_plan = score_path,
    readiness = readiness_path), filename = "score_prepare_manifest.csv")
  readiness
}

app_joint_swscore_oracle_dir <- function(root, id) {
  file.path(app_joint_swscore_root(root), "oracle_workers", sprintf("worker_%04d", as.integer(id)))
}

app_joint_swscore_run_oracle <- function(root, worker_id) {
  root <- normalizePath(root, mustWork = TRUE); out_root <- app_joint_swscore_root(root)
  plan <- app_read_csv(file.path(out_root, "oracle_worker_plan.csv"))
  row <- plan[plan$oracle_worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("Oracle worker is not unique.", call. = FALSE)
  out <- app_joint_swscore_oracle_dir(root, worker_id)
  if (file.exists(file.path(out, "DONE"))) return(invisible(out))
  tmp <- paste0(out, ".tmp_", Sys.getpid()); unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp); contract <- app_read_csv(file.path(out_root, "score_contract.csv"))
  fixture <- readRDS(row$fixture_path[[1L]]); design <- readRDS(row$design_path[[1L]])
  shard <- app_joint_recursive_dgp_shard(fixture, design$forecast_map,
    n_paths = app_joint_swscore_value(contract, "oracle_paths_per_shard", TRUE),
    seed = row$oracle_seed[[1L]])
  path <- file.path(tmp, "oracle_shard.rds"); saveRDS(shard, path, version = 3L, compress = "xz")
  summary <- data.frame(oracle_worker_id = worker_id, scenario_id = row$scenario_id,
    shard_id = row$shard_id, oracle_seed = row$oracle_seed, n_paths = shard$n_paths,
    finite = all(is.finite(shard$response)), protected_score_computed = FALSE,
    stringsAsFactors = FALSE)
  files <- c(shard = path, summary = app_write_csv(summary, file.path(tmp, "summary.csv")))
  app_joint_shared_write_manifest(tmp, files)
  if (!all(app_joint_shared_verify_manifest(tmp, file.path(tmp, "artifact_manifest.csv"))$verified))
    stop("Oracle worker manifest failed verification.", call. = FALSE)
  writeLines("completed", file.path(tmp, "DONE")); if (dir.exists(out)) unlink(out, recursive = TRUE)
  if (!file.rename(tmp, out)) stop("Could not publish oracle worker.", call. = FALSE)
  invisible(out)
}

app_joint_swscore_oracle_health <- function(root) {
  plan <- app_read_csv(file.path(app_joint_swscore_root(root), "oracle_worker_plan.csv"))
  dirs <- vapply(plan$oracle_worker_id, function(id) app_joint_swscore_oracle_dir(root, id), character(1L))
  done <- file.exists(file.path(dirs, "DONE")); failed <- file.exists(file.path(dirs, "FAILED"))
  data.frame(expected = nrow(plan), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), stringsAsFactors = FALSE)
}

app_joint_swscore_finalize_oracle <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); out <- app_joint_swscore_root(root)
  health <- app_joint_swscore_oracle_health(root)
  if (health$completed[[1L]] != health$expected[[1L]] || health$failed[[1L]] != 0L)
    stop("Oracle bank is not complete.", call. = FALSE)
  plan <- app_read_csv(file.path(out, "oracle_worker_plan.csv"))
  contract <- app_read_csv(file.path(out, "score_contract.csv"))
  tau <- app_joint_swscore_numvec(contract, "quantile_grid")
  weights <- app_joint_swscore_numvec(contract, "trapezoidal_weights")
  for (id in plan$oracle_worker_id) {
    worker <- app_joint_swscore_oracle_dir(root, id)
    verified <- app_joint_shared_verify_manifest(worker,
      file.path(worker, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified)) {
      stop(sprintf("Oracle worker %d manifest is not verified.", id), call. = FALSE)
    }
  }
  diagnostics <- paths <- list()
  for (scenario in unique(plan$scenario_id)) {
    block <- plan[plan$scenario_id == scenario, , drop = FALSE]
    shard_paths <- vapply(block$oracle_worker_id, function(id) file.path(
      app_joint_swscore_oracle_dir(root, id), "oracle_shard.rds"), character(1L))
    fixture <- readRDS(block$fixture_path[[1L]])
    oracle <- app_joint_recursive_combine_oracle_shards(shard_paths, fixture, tau, weights,
      analytic_tolerance = app_joint_swscore_value(contract, "oracle_analytic_tolerance", TRUE),
      split_half_tolerance = app_joint_swscore_value(contract, "oracle_split_tolerance", TRUE))
    path <- file.path(out, "oracle_banks", paste0(scenario, ".rds")); app_ensure_dir(dirname(path))
    saveRDS(oracle, path, version = 3L, compress = "xz")
    paths[[scenario]] <- path; diagnostics[[scenario]] <- oracle$diagnostics
  }
  diagnostic <- app_bind_rows_fill(diagnostics)
  if (any(diagnostic$status != "pass")) stop("Oracle convergence gate requires review.", call. = FALSE)
  diagnostic_path <- app_write_csv(diagnostic, file.path(out, "oracle_diagnostics.csv"))
  manifest <- data.frame(scenario_id = names(paths), relative_path = file.path("oracle_banks",
    basename(unlist(paths))), size_bytes = file.info(unlist(paths))$size,
    sha256 = vapply(unlist(paths), app_sha256_file, character(1L)), stringsAsFactors = FALSE)
  manifest_path <- app_write_csv(manifest, file.path(out, "oracle_bank_manifest.csv"))
  readiness <- data.frame(status = "ORACLE_COMPLETE_PROTECTED_SCORE_WORKERS_READY",
    oracle_banks = nrow(manifest), score_workers = nrow(app_read_csv(file.path(out,
      "score_worker_plan.csv"))), protected_scores_computed = FALSE, stringsAsFactors = FALSE)
  readiness_path <- app_write_csv(readiness, file.path(out, "score_launch_readiness.csv"))
  app_joint_shared_write_manifest(out, c(diagnostics = diagnostic_path,
    banks = manifest_path, readiness = readiness_path), filename = "oracle_final_manifest.csv")
  readiness
}

app_joint_swscore_select_rows <- function(n, target) {
  app_joint_qdesn_postscore_even_indices(as.integer(n), min(as.integer(n), as.integer(target)))
}

app_joint_swscore_vb_draws <- function(packet, model_id, n, seed) {
  init <- app_joint_swcf_packet_init(packet, model_id)
  K <- length(init$alpha_mean); p <- length(init$beta_mean) / K
  if (startsWith(model_id, "independent_")) {
    beta <- matrix(NA_real_, nrow = n, ncol = p * K)
    for (k in seq_len(K)) {
      cols <- ((k - 1L) * p + 1L):(k * p)
      beta[, cols] <- app_joint_recursive_mvn_draws(init$fits[[k]]$beta_mean,
        init$fits[[k]]$beta_cov, n, seed + 7919L * k)
    }
  } else {
    beta <- app_joint_recursive_mvn_draws(init$beta_mean, init$beta_cov, n, seed)
  }
  list(beta = beta, alpha = matrix(rep(init$alpha_mean, each = n), nrow = n),
    chain_id = rep(NA_integer_, n), source_draw_index = seq_len(n))
}

app_joint_swscore_mcmc_draws <- function(root, cell, seed) {
  plan <- app_read_csv(file.path(app_joint_swcf_root(root), "mcmc_worker_plan.csv"))
  jobs <- plan[plan$model_cell_id == cell$model_cell_id[[1L]], , drop = FALSE]
  jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
  if (nrow(jobs) != 3L) stop("Score adapter requires three MCMC chains.", call. = FALSE)
  blocks <- lapply(seq_len(nrow(jobs)), function(i) {
    draws <- app_read_csv(file.path(app_joint_swcf_worker_dir(root, "mcmc",
      jobs$worker_id[[i]]), "posterior_draws.csv.gz"))
    beta <- app_joint_recursive_select_block(draws, "beta")
    alpha <- app_joint_recursive_select_block(draws, "alpha")
    if (identical(cell$fit_structure[[1L]], "independent")) {
      coupled <- app_joint_recursive_couple_independent(beta, alpha,
        ncol(readRDS(cell$design_path[[1L]])$Z), seed + 1009L * i)
      beta <- coupled$beta; alpha <- coupled$alpha
    }
    list(beta = beta, alpha = alpha, chain_id = rep(jobs$chain_id[[i]], nrow(beta)),
      source_draw_index = seq_len(nrow(beta)))
  })
  values <- setNames(lapply(c("beta", "alpha"), function(name) {
    do.call(rbind, lapply(blocks, `[[`, name))
  }), c("beta", "alpha"))
  values$chain_id <- unlist(lapply(blocks, `[[`, "chain_id"), use.names = FALSE)
  values$source_draw_index <- unlist(lapply(blocks, `[[`, "source_draw_index"), use.names = FALSE)
  values
}

app_joint_swscore_subset <- function(draws, per_chain) {
  if (all(is.na(draws$chain_id))) {
    index <- app_joint_swscore_select_rows(nrow(draws$beta), per_chain)
  } else {
    index <- unlist(lapply(split(seq_len(nrow(draws$beta)), draws$chain_id), function(rows) {
      rows[app_joint_swscore_select_rows(length(rows), per_chain)]
    }), use.names = FALSE)
  }
  lapply(draws, function(x) if (is.matrix(x)) x[index, , drop = FALSE] else x[index])
}

app_joint_swscore_cell_dir <- function(root, id) {
  file.path(app_joint_swscore_root(root), "cells", sprintf("worker_%04d", as.integer(id)))
}

app_joint_swscore_run_cell <- function(root, worker_id) {
  root <- normalizePath(root, mustWork = TRUE); out_root <- app_joint_swscore_root(root)
  if (!file.exists(file.path(out_root, "score_launch_readiness.csv")))
    stop("Oracle finalization has not authorized protected scoring.", call. = FALSE)
  plan <- app_read_csv(file.path(out_root, "score_worker_plan.csv"))
  row <- plan[plan$score_worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("Score worker is not unique.", call. = FALSE)
  out <- app_joint_swscore_cell_dir(root, worker_id)
  if (file.exists(file.path(out, "DONE"))) return(invisible(out))
  tmp <- paste0(out, ".tmp_", Sys.getpid()); unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp); contract <- app_read_csv(file.path(out_root, "score_contract.csv"))
  tau <- app_joint_swscore_numvec(contract, "quantile_grid")
  weights <- app_joint_swscore_numvec(contract, "trapezoidal_weights")
  design <- readRDS(row$design_path[[1L]]); fixture <- readRDS(row$fixture_path[[1L]])
  packet <- readRDS(row$vb_packet_path[[1L]])
  draws <- if (row$inference_method[[1L]] == "vb") {
    app_joint_swscore_vb_draws(packet, row$model_id[[1L]],
      app_joint_swscore_value(contract, "vb_score_draws", TRUE), row$score_seed[[1L]])
  } else app_joint_swscore_mcmc_draws(root, row, row$score_seed[[1L]])
  state_n <- if (row$inference_method[[1L]] == "vb") {
    app_joint_swscore_value(contract, "vb_state_draws", TRUE)
  } else app_joint_swscore_value(contract, "mcmc_state_draws_per_chain", TRUE)
  state <- app_joint_swscore_subset(draws, state_n)
  set.seed(row$uniform_seed[[1L]])
  uniforms <- matrix(stats::runif(nrow(state$beta) * nrow(design$forecast_map)),
    nrow = nrow(state$beta))
  half <- if (all(is.na(state$chain_id))) rep(c(1L, 2L), length.out = nrow(state$beta)) else
    app_joint_recursive_half_assignment(state$chain_id, "within_chain_alternating")
  mean_result <- app_joint_recursive_mean_design(design, fixture, row, state$beta,
    state$alpha, uniforms, app_joint_swscore_value(contract, "inverse_cdf_tail_rule"),
    half_assignment = half,
    diagnostic_group = if (all(is.na(state$chain_id))) NULL else state$chain_id)
  if (!isTRUE(mean_result$diagnostics$finite[[1L]]))
    stop("Canonical recursive mean design is nonfinite.", call. = FALSE)
  oracle <- readRDS(file.path(out_root, "oracle_banks", paste0(row$scenario_id[[1L]], ".rds")))
  score_draws <- app_joint_recursive_score_draws(mean_result$mean_design, draws$beta,
    draws$alpha, oracle, tau, weights,
    app_joint_swscore_value(contract, "score_chunk_size", TRUE), draws$chain_id,
    draws$source_draw_index)
  beta_mean <- colMeans(draws$beta); alpha_mean <- colMeans(draws$alpha)
  canonical <- app_joint_recursive_canonical_metrics(mean_result$mean_design,
    beta_mean, alpha_mean, oracle, tau, weights)
  summary <- app_joint_recursive_draw_summary(score_draws, row$inference_method[[1L]])
  if (row$inference_method[[1L]] == "mcmc") {
    split_score <- split(score_draws$origin_marginal_dgp_integrated_acrps,
      score_draws$chain_id)
    diagnostic <- app_joint_exqdesn_modern_diagnostics(do.call(cbind, split_score))
    summary$score_rank_rhat <- diagnostic$rank_rhat
    summary$score_folded_rhat <- diagnostic$folded_rhat
    summary$score_bulk_ess <- diagnostic$bulk_ess
    summary$score_tail_ess <- diagnostic$tail_ess
    summary$score_mcse_mean <- diagnostic$mcse_mean
  }
  fit_q <- app_joint_qdesn_predict_fit(list(beta_mean = beta_mean, alpha_mean = alpha_mean),
    design$Z[design$train_local, , drop = FALSE], tau)
  fit_contract <- app_joint_qdesn_apply_monotone_contract(fit_q, tau)
  fit_error <- fit_contract$qhat_contract - design$true_q[design$train_local, , drop = FALSE]
  path_state <- app_joint_swscore_subset(draws,
    app_joint_swscore_value(contract, "path_draws_per_chain", TRUE))
  set.seed(row$uniform_seed[[1L]] + 313L)
  path_uniforms <- matrix(stats::runif(nrow(path_state$beta) * nrow(design$forecast_map)),
    nrow = nrow(path_state$beta))
  path_draws <- app_joint_pure_recursive_path_score_draws(design, fixture,
    path_state$beta, path_state$alpha, path_uniforms, oracle, tau, weights,
    path_state$chain_id, path_state$source_draw_index,
    app_joint_swscore_value(contract, "inverse_cdf_tail_rule"))
  path_summary <- app_joint_recursive_draw_summary(path_draws, row$inference_method[[1L]])
  names(path_summary) <- paste0("path_", names(path_summary))
  output <- cbind(row[, c("score_worker_id", "scenario_id", "specification_role",
    "model_cell_id", "model_id", "fit_structure", "likelihood_family",
    "inference_method"), drop = FALSE], summary,
    setNames(canonical, paste0("canonical_", names(canonical))), path_summary,
    data.frame(fit_oracle_quantile_mae = mean(abs(fit_error)),
      fit_oracle_quantile_rmse = sqrt(mean(fit_error^2)),
      state_half_standardized_rms = mean_result$diagnostics$standardized_rms_half_difference,
      interval_scope = if (row$inference_method[[1L]] == "vb")
        "partial_vb_readout_uncertainty_conditional_on_point_intercepts_and_mean_design" else
        "mcmc_readout_uncertainty_conditional_on_mean_design",
      stringsAsFactors = FALSE))
  teacher <- app_joint_recursive_teacher_forced_audit(design, fixture, row)
  if (teacher$status[[1L]] != "pass") stop("Teacher-forced origin audit failed.", call. = FALSE)
  write_gz <- function(x, path) {
    con <- gzfile(path, "wt", compression = 9); on.exit(close(con), add = TRUE)
    utils::write.csv(x, con, row.names = FALSE, na = ""); path
  }
  files <- c(summary = app_write_csv(output, file.path(tmp, "summary.csv")),
    score_draws = write_gz(score_draws, file.path(tmp, "posterior_score_draws.csv.gz")),
    path_draws = write_gz(path_draws, file.path(tmp, "path_posterior_score_draws.csv.gz")),
    canonical = app_write_csv(canonical, file.path(tmp, "canonical_action.csv")),
    mean_design_diagnostics = app_write_csv(mean_result$diagnostics,
      file.path(tmp, "mean_design_diagnostics.csv")),
    teacher_audit = app_write_csv(teacher, file.path(tmp, "teacher_forced_audit.csv")))
  app_joint_shared_write_manifest(tmp, files)
  if (!all(app_joint_shared_verify_manifest(tmp, file.path(tmp, "artifact_manifest.csv"))$verified))
    stop("Protected score worker manifest failed verification.", call. = FALSE)
  writeLines("completed", file.path(tmp, "DONE")); if (dir.exists(out)) unlink(out, recursive = TRUE)
  if (!file.rename(tmp, out)) stop("Could not publish protected score worker.", call. = FALSE)
  invisible(out)
}

app_joint_swscore_health <- function(root) {
  plan <- app_read_csv(file.path(app_joint_swscore_root(root), "score_worker_plan.csv"))
  dirs <- vapply(plan$score_worker_id, function(id) app_joint_swscore_cell_dir(root, id), character(1L))
  done <- file.exists(file.path(dirs, "DONE")); failed <- file.exists(file.path(dirs, "FAILED"))
  data.frame(expected = nrow(plan), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), stringsAsFactors = FALSE)
}

app_joint_swscore_finalize <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); out <- app_joint_swscore_root(root)
  health <- app_joint_swscore_health(root)
  if (health$completed[[1L]] != health$expected[[1L]] || health$failed[[1L]] != 0L)
    stop("Protected score packet is not complete.", call. = FALSE)
  plan <- app_read_csv(file.path(out, "score_worker_plan.csv"))
  summaries <- app_bind_rows_fill(lapply(plan$score_worker_id, function(id) {
    worker <- app_joint_swscore_cell_dir(root, id)
    verified <- app_joint_shared_verify_manifest(worker, file.path(worker, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified)) stop("Score worker manifest failed.", call. = FALSE)
    app_read_csv(file.path(worker, "summary.csv"))
  }))
  numeric_required <- c("posterior_score_mean", "posterior_score_median",
    "posterior_score_q025", "posterior_score_q975",
    "canonical_origin_marginal_dgp_integrated_acrps")
  if (nrow(summaries) != 128L || any(!is.finite(as.matrix(summaries[numeric_required]))) ||
      any(summaries$canonical_contract_crossing_pairs != 0L)) {
    stop("Protected score summary violates the final gate.", call. = FALSE)
  }
  summary_path <- app_write_csv(summaries, file.path(out, "score_summary.csv"))
  mcmc <- summaries[summaries$inference_method == "mcmc", , drop = FALSE]
  contrasts <- app_bind_rows_fill(lapply(split(mcmc,
    interaction(mcmc$scenario_id, mcmc$model_id, drop = TRUE)), function(block) {
    challenger <- block[block$specification_role == "challenger", , drop = FALSE]
    parity <- block[block$specification_role == "new_geometry_parity", , drop = FALSE]
    if (nrow(challenger) != 1L || nrow(parity) != 1L) stop("Contrast pair is malformed.", call. = FALSE)
    left <- app_read_csv(file.path(app_joint_swscore_cell_dir(root,
      challenger$score_worker_id[[1L]]), "posterior_score_draws.csv.gz"))
    right <- app_read_csv(file.path(app_joint_swscore_cell_dir(root,
      parity$score_worker_id[[1L]]), "posterior_score_draws.csv.gz"))
    delta <- left$origin_marginal_dgp_integrated_acrps -
      right$origin_marginal_dgp_integrated_acrps
    data.frame(scenario_id = challenger$scenario_id, model_id = challenger$model_id,
      challenger_mean = challenger$posterior_score_mean, parity_mean = parity$posterior_score_mean,
      challenger_minus_parity_mean = mean(delta),
      challenger_minus_parity_q025 = as.numeric(stats::quantile(delta, 0.025, type = 8)),
      challenger_minus_parity_q975 = as.numeric(stats::quantile(delta, 0.975, type = 8)),
      relative_improvement = (parity$posterior_score_mean - challenger$posterior_score_mean) /
        parity$posterior_score_mean,
      interval_overlap = challenger$posterior_score_q025 <= parity$posterior_score_q975 &&
        parity$posterior_score_q025 <= challenger$posterior_score_q975,
      stringsAsFactors = FALSE)
  }))
  margin <- app_joint_swscore_value(app_read_csv(file.path(out, "score_contract.csv")),
    "practical_noninferiority_margin", TRUE)
  decision <- app_bind_rows_fill(lapply(split(contrasts, contrasts$scenario_id), function(block) {
    any_improvement <- any(block$challenger_minus_parity_mean < 0)
    all_noninferior <- all(block$challenger_mean <= block$parity_mean * (1 + margin))
    data.frame(scenario_id = block$scenario_id[[1L]], target_rows_improved =
      sum(block$challenger_minus_parity_mean < 0), all_rows_practically_noninferior = all_noninferior,
      promote_complete_challenger_packet = any_improvement && all_noninferior,
      decision = if (any_improvement && all_noninferior) "promote_challenger_packet" else
        "retain_new_geometry_parity", stringsAsFactors = FALSE)
  }))
  contrast_path <- app_write_csv(contrasts, file.path(out, "challenger_parity_contrasts.csv"))
  decision_path <- app_write_csv(decision, file.path(out, "scenario_packet_decisions.csv"))
  final <- data.frame(status = "PROTECTED_SCORE_PACKET_READY_FOR_INTEGRATION_REVIEW",
    score_rows = nrow(summaries), mcmc_contrasts = nrow(contrasts),
    scenario_decisions = nrow(decision), promoted_scenarios = sum(decision$promote_complete_challenger_packet),
    interval_overlap_is_equivalence = FALSE, article_assets_modified = FALSE,
    stringsAsFactors = FALSE)
  final_path <- app_write_csv(final, file.path(out, "final_decision.csv"))
  app_joint_shared_write_manifest(out, c(summary = summary_path, contrasts = contrast_path,
    decisions = decision_path, final = final_path), filename = "score_final_manifest.csv")
  final
}
