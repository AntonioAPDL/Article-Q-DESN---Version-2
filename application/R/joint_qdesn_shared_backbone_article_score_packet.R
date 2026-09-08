# Deterministic score-packet closeout for the completed Jerez JOINT article lane.

app_joint_article_score_contract_path <- function() {
  app_path(
    "application/config",
    "joint_qdesn_shared_backbone_article_score_contract_v1.csv"
  )
}

app_joint_article_score_contract_value <- function(tab, name) {
  row <- tab[tab$name == name, , drop = FALSE]
  if (nrow(row) != 1L) {
    stop(sprintf("Jerez score contract requires one '%s' row.", name),
         call. = FALSE)
  }
  as.character(row$value[[1L]])
}

app_joint_article_score_split <- function(x) {
  trimws(strsplit(as.character(x)[[1L]], ";", fixed = TRUE)[[1L]])
}

app_joint_article_score_read_contract <- function(
  path = app_joint_article_score_contract_path()
) {
  tab <- app_read_csv(path)
  app_check_required_columns(
    tab, c("section", "name", "value", "type", "description"),
    "Jerez shared-backbone article score contract"
  )
  if (anyDuplicated(tab$name)) {
    stop("Jerez score contract names must be unique.", call. = FALSE)
  }
  get <- function(name) app_joint_article_score_contract_value(tab, name)
  int <- function(name) as.integer(get(name))
  num <- function(name) as.numeric(get(name))
  bool <- function(name) identical(tolower(get(name)), "true")
  nums <- function(name) as.numeric(app_joint_article_score_split(get(name)))
  ints <- function(name) as.integer(app_joint_article_score_split(get(name)))
  tau <- nums("tau_grid")
  weights <- nums("trapezoidal_weights")
  expected_weights <- c(
    (tau[[2L]] - tau[[1L]]) / 2,
    (tau[3:length(tau)] - tau[1:(length(tau) - 2L)]) / 2,
    (tau[[length(tau)]] - tau[[length(tau) - 1L]]) / 2
  )
  if (!identical(tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)) ||
      length(weights) != length(tau) ||
      max(abs(weights - expected_weights)) > 1e-12 ||
      bool("renormalize_weights")) {
    stop("Jerez score contract has malformed tau weights.", call. = FALSE)
  }
  list(
    table = tab,
    path = normalizePath(path, mustWork = TRUE),
    version = get("contract_version"),
    runtime_root = get("runtime_root"),
    expected_source_jobs = int("expected_source_jobs"),
    expected_source_failures = int("expected_source_failures"),
    expected_vb_components = int("expected_vb_components"),
    expected_initializers = int("expected_initializers"),
    expected_mcmc_workers = int("expected_mcmc_workers"),
    expected_scenarios = int("expected_scenarios"),
    expected_models = int("expected_models"),
    expected_model_cells = int("expected_model_cells"),
    expected_contrasts = int("expected_contrasts"),
    primary_metric = get("primary_metric"),
    tau = tau,
    weights_qs = weights,
    score_draws_per_chain = int("score_draws_per_chain"),
    sensitivity_draws_per_chain = int("sensitivity_draws_per_chain"),
    chunk_size = int("chunk_size"),
    primary_pairing_seed = int("primary_pairing_seed"),
    sensitivity_pairing_seeds = ints("sensitivity_pairing_seeds"),
    contrast_pairing_seed = int("contrast_pairing_seed"),
    qhat_equivalence_tolerance = num("qhat_equivalence_tolerance"),
    score_rank_rhat_ceiling = num("score_rank_rhat_ceiling"),
    score_bulk_ess_floor = num("score_bulk_ess_floor"),
    score_tail_ess_floor = num("score_tail_ess_floor"),
    raw_crossing_rate_review = num("raw_crossing_rate_review"),
    standardized_adjustment_review = num("standardized_adjustment_review"),
    regret_tolerance = num("regret_tolerance"),
    analytic_integration_tolerance = num("analytic_integration_tolerance"),
    monte_carlo_tolerance = num("monte_carlo_tolerance"),
    practical_relative_margin = num("practical_relative_margin"),
    posterior_probability_floor = num("posterior_probability_floor")
  )
}

app_joint_article_score_dirs <- function(
  root = app_joint_article_default_root()
) {
  root <- normalizePath(root, mustWork = TRUE)
  list(root = root, packet = file.path(root, "score_packet"))
}

app_joint_article_score_model_source_id <- function(model_id) {
  sub("_mcmc$", "_vb", model_id)
}

app_joint_article_score_pid_active <- function(pid) {
  pid <- as.integer(pid)[[1L]]
  if (is.na(pid) || pid <= 0L) return(FALSE)
  length(suppressWarnings(system2(
    "ps", c("-p", pid, "-o", "pid="), stdout = TRUE, stderr = FALSE
  ))) > 0L
}

app_joint_article_score_related_processes <- function() {
  lines <- tryCatch(system2("ps", c("-eo", "pid=,args="), stdout = TRUE),
                    error = function(e) character())
  if (!length(lines)) {
    return(data.frame(pid = integer(), command = character(),
                      stringsAsFactors = FALSE))
  }
  patterns <- c(
    "run_joint_qdesn_shared_backbone_article_vb",
    "run_joint_qdesn_shared_backbone_article_mcmc",
    "finalize_joint_qdesn_shared_backbone_article_confirmation"
  )
  keep <- Reduce(`|`, lapply(patterns, grepl, lines, fixed = TRUE))
  if (!any(keep)) {
    return(data.frame(pid = integer(), command = character(),
                      stringsAsFactors = FALSE))
  }
  out <- lines[keep]
  pid <- suppressWarnings(as.integer(sub("^\\s*([0-9]+).*$", "\\1", out)))
  keep_pid <- !is.na(pid) & pid != Sys.getpid()
  data.frame(
    pid = pid[keep_pid],
    command = trimws(sub("^\\s*[0-9]+\\s+", "", out[keep_pid])),
    stringsAsFactors = FALSE
  )
}

app_joint_article_score_tmp_dirs <- function(root) {
  paths <- list.files(root, recursive = TRUE, all.files = TRUE,
                      full.names = TRUE, no.. = TRUE)
  dirs <- paths[file.info(paths)$isdir %in% TRUE]
  dirs[grepl("[.](tmp|incomplete|superseded)[.]", basename(dirs))]
}

app_joint_article_score_reaudit <- function(
  root = app_joint_article_default_root(),
  contract = app_joint_article_score_read_contract()
) {
  root <- normalizePath(root, mustWork = TRUE)
  out_path <- file.path(root, "computation_closeout_reaudit.csv")
  current_head <- app_joint_article_git_value(c("rev-parse", "HEAD"))
  if (file.exists(out_path)) {
    audit <- app_read_csv(out_path)
    if (nrow(audit) &&
        all(audit$status == "pass") &&
        "execution_code_commit" %in% names(audit) &&
        all(audit$execution_code_commit == current_head)) {
      return(audit)
    }
  }

  source <- app_read_csv(file.path(root, "source_final_health.csv"))
  vb <- app_read_csv(file.path(root, "vb_health_summary.csv"))
  init <- app_read_csv(file.path(root, "vb_initializer_manifest.csv"))
  vb_final <- app_read_csv(file.path(root, "vb_final_manifest_verification.csv"))
  mcmc <- app_read_csv(file.path(root, "mcmc_health_summary.csv"))
  worker_verify <- app_read_csv(file.path(root, "mcmc_worker_manifest_verification.csv"))
  mcmc_final <- app_read_csv(file.path(root, "mcmc_final_manifest_verification.csv"))
  plan <- app_read_csv(file.path(root, "mcmc_worker_plan.csv"))
  cells <- app_read_csv(file.path(root, "model_cell_plan.csv"))
  posterior <- app_read_csv(file.path(root, "mcmc_posterior_summary_registry.csv"))
  final <- app_read_csv(file.path(root, "final_confirmation_assessment.csv"))

  source_expected <- sum(as.integer(source$expected))
  source_complete <- sum(as.integer(source$completed))
  source_failed <- sum(as.integer(source$failed))
  init_paths <- file.path(root, init$relative_path)
  init_hash <- vapply(seq_len(nrow(init)), function(ii) {
    file.exists(init_paths[[ii]]) &&
      identical(app_sha256_file(init_paths[[ii]]), init$sha256[[ii]])
  }, logical(1L))
  worker_ids_verified <- unique(worker_verify$worker_id[
    app_as_bool_vec(worker_verify$verified)
  ])
  pid_files <- c("mcmc_queue_detached.pid", "setsid_sleep_test.pid")
  pid_rows <- lapply(pid_files, function(name) {
    path <- file.path(root, name)
    pid <- if (file.exists(path)) {
      suppressWarnings(as.integer(readLines(path, warn = FALSE)[[1L]]))
    } else NA_integer_
    data.frame(
      pid_file = name, pid = pid,
      active = if (is.na(pid)) FALSE else app_joint_article_score_pid_active(pid),
      stringsAsFactors = FALSE
    )
  })
  pids <- app_bind_rows_fill(pid_rows)
  related <- app_joint_article_score_related_processes()
  tmp_dirs <- app_joint_article_score_tmp_dirs(root)
  mcmc_dirs <- list.files(file.path(root, "mcmc_workers"),
                          pattern = "^worker_[0-9]{4}$", full.names = TRUE)
  vb_dirs <- list.files(file.path(root, "workers"),
                        pattern = "^worker_[0-9]{4}$", full.names = TRUE)

  rows <- list(
    data.frame(
      gate = "source_jobs", expected = contract$expected_source_jobs,
      observed = source_complete, failed = source_failed,
      status = if (source_expected == contract$expected_source_jobs &&
        source_complete == contract$expected_source_jobs &&
        source_failed == contract$expected_source_failures &&
        all(source$status == "complete")) "pass" else "fail",
      evidence_path = "source_final_health.csv",
      note = "imported source campaign remains screening provenance",
      stringsAsFactors = FALSE
    ),
    data.frame(
      gate = "vb_components", expected = contract$expected_vb_components,
      observed = vb$completed_vb_components[[1L]],
      failed = vb$failed_vb_components[[1L]],
      status = if (vb$expected_vb_components[[1L]] == contract$expected_vb_components &&
        vb$completed_vb_components[[1L]] == contract$expected_vb_components &&
        vb$failed_vb_components[[1L]] == 0L &&
        vb$gate_status[[1L]] == "pass") "pass" else "fail",
      evidence_path = "vb_health_summary.csv",
      note = "136 article-window VB components complete",
      stringsAsFactors = FALSE
    ),
    data.frame(
      gate = "compact_initializers", expected = contract$expected_initializers,
      observed = nrow(init), failed = sum(!init_hash),
      status = if (nrow(init) == contract$expected_initializers &&
        length(unique(init$model_cell_id)) == contract$expected_initializers &&
        all(app_as_bool_vec(init$finite_values)) && all(init_hash)) "pass" else "fail",
      evidence_path = "vb_initializer_manifest.csv",
      note = "32 compact initializer hashes verified",
      stringsAsFactors = FALSE
    ),
    data.frame(
      gate = "vb_final_manifest", expected = nrow(vb_final),
      observed = sum(app_as_bool_vec(vb_final$verified)),
      failed = sum(!app_as_bool_vec(vb_final$verified)),
      status = if (nrow(vb_final) > 0L &&
        all(app_as_bool_vec(vb_final$verified))) "pass" else "fail",
      evidence_path = "vb_final_manifest_verification.csv",
      note = "final VB manifest entries verified",
      stringsAsFactors = FALSE
    ),
    data.frame(
      gate = "mcmc_workers", expected = contract$expected_mcmc_workers,
      observed = mcmc$completed_workers[[1L]],
      failed = mcmc$failed_workers[[1L]],
      status = if (mcmc$expected_workers[[1L]] == contract$expected_mcmc_workers &&
        mcmc$completed_workers[[1L]] == contract$expected_mcmc_workers &&
        mcmc$failed_workers[[1L]] == 0L &&
        mcmc$gate_status[[1L]] == "pass") "pass" else "fail",
      evidence_path = "mcmc_health_summary.csv",
      note = "160 chain workers complete",
      stringsAsFactors = FALSE
    ),
    data.frame(
      gate = "worker_manifests", expected = contract$expected_mcmc_workers,
      observed = length(worker_ids_verified),
      failed = length(setdiff(unique(worker_verify$worker_id), worker_ids_verified)),
      status = if (length(worker_ids_verified) == contract$expected_mcmc_workers &&
        all(app_as_bool_vec(worker_verify$verified))) "pass" else "fail",
      evidence_path = "mcmc_worker_manifest_verification.csv",
      note = "all worker manifest entries verified",
      stringsAsFactors = FALSE
    ),
    data.frame(
      gate = "mcmc_final_manifest", expected = nrow(mcmc_final),
      observed = sum(app_as_bool_vec(mcmc_final$verified)),
      failed = sum(!app_as_bool_vec(mcmc_final$verified)),
      status = if (nrow(mcmc_final) > 0L &&
        all(app_as_bool_vec(mcmc_final$verified))) "pass" else "fail",
      evidence_path = "mcmc_final_manifest_verification.csv",
      note = "final MCMC manifest entries verified",
      stringsAsFactors = FALSE
    ),
    data.frame(
      gate = "model_cells", expected = contract$expected_model_cells,
      observed = length(unique(plan$model_cell_id)), failed = 0L,
      status = if (nrow(cells) == contract$expected_model_cells &&
        length(unique(cells$scenario_id)) == contract$expected_scenarios &&
        length(unique(cells$model_id)) == contract$expected_models &&
        length(unique(plan$model_cell_id)) == contract$expected_model_cells &&
        nrow(posterior) == contract$expected_mcmc_workers) "pass" else "fail",
      evidence_path = "model_cell_plan.csv;mcmc_posterior_summary_registry.csv",
      note = "32 cells equals 8 scenarios by 4 model families",
      stringsAsFactors = FALSE
    ),
    data.frame(
      gate = "inactive_processes", expected = 0L,
      observed = nrow(related) + sum(pids$active),
      failed = nrow(related) + sum(pids$active),
      status = if (nrow(related) == 0L && !any(pids$active)) "pass" else "fail",
      evidence_path = paste(pid_files, collapse = ";"),
      note = "no VB/MCMC queue launcher or finalizer process remains active",
      stringsAsFactors = FALSE
    ),
    data.frame(
      gate = "runtime_storage", expected = 0L,
      observed = length(tmp_dirs), failed = length(tmp_dirs),
      status = if (file.access(root, 4L) == 0L &&
        length(tmp_dirs) == 0L &&
        length(mcmc_dirs) == contract$expected_mcmc_workers &&
        length(vb_dirs) == contract$expected_vb_components &&
        identical(final$status[[1L]], "MCMC_COMPLETE_READY_FOR_SCORE_PACKET")) {
        "pass"
      } else "fail",
      evidence_path = ".",
      note = "active runtime is readable and has no incomplete temp worker dirs",
      stringsAsFactors = FALSE
    )
  )
  audit <- app_bind_rows_fill(rows)
  audit$created_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
  audit$execution_code_commit <- current_head
  app_write_csv(audit, out_path)
  if (any(audit$status != "pass")) {
    stop("Jerez computation closeout re-audit failed.", call. = FALSE)
  }
  audit
}

app_joint_article_score_select_block <- function(draws, block) {
  pattern <- paste0("^", block, "_[0-9]{4}$")
  cols <- grep(pattern, names(draws), value = TRUE)
  cols <- cols[order(as.integer(sub(sprintf("^%s_", block), "", cols)))]
  as.matrix(draws[, cols, drop = FALSE])
}

app_joint_article_score_complete_fit <- function(fit, fit_structure, tau, p) {
  if (identical(fit_structure, "independent")) {
    fit$fits <- lapply(seq_along(tau), function(k) {
      idx <- ((k - 1L) * p + 1L):(k * p)
      one <- list(
        beta_mean = fit$beta_mean[idx],
        alpha_mean = fit$alpha_mean[[k]],
        sigma_mean = fit$sigma_mean[[k]]
      )
      if (!is.null(fit$gamma_mean)) one$gamma_mean <- fit$gamma_mean[[k]]
      one
    })
  }
  fit
}

app_joint_article_score_read_fit <- function(root, job, contract) {
  worker_dir <- app_joint_article_mcmc_worker_dir(root, job$worker_id[[1L]])
  design <- readRDS(job$design_path[[1L]])
  if (!identical(design$design_fingerprint, job$design_fingerprint[[1L]])) {
    stop("Jerez score adapter found a design fingerprint mismatch.",
         call. = FALSE)
  }
  draws <- app_read_csv(file.path(worker_dir, "posterior_draws.csv.gz"))
  beta <- app_joint_article_score_select_block(draws, "beta")
  alpha <- app_joint_article_score_select_block(draws, "alpha")
  sigma <- app_joint_article_score_select_block(draws, "sigma")
  gamma <- app_joint_article_score_select_block(draws, "gamma")
  K <- length(design$tau)
  p <- ncol(design$Z)
  if (nrow(beta) <= 0L || ncol(beta) != K * p ||
      ncol(alpha) != K || ncol(sigma) != K ||
      (!ncol(gamma) %in% c(0L, K)) ||
      any(!is.finite(c(beta, alpha, sigma))) || any(sigma <= 0) ||
      (ncol(gamma) && any(!is.finite(gamma)))) {
    stop("Jerez posterior draw reconstruction produced malformed blocks.",
         call. = FALSE)
  }
  fit <- list(
    beta_draws = beta, alpha_draws = alpha, sigma_draws = sigma,
    beta_mean = colMeans(beta), alpha_mean = colMeans(alpha),
    sigma_mean = colMeans(sigma), tau = design$tau,
    seed = as.integer(job$chain_seed[[1L]]),
    chain_id = as.integer(job$chain_id[[1L]]),
    init_source = "jerez_verified_posterior_draws"
  )
  if (ncol(gamma)) {
    fit$gamma_draws <- gamma
    fit$gamma_mean <- colMeans(gamma)
  }
  fit <- app_joint_article_score_complete_fit(
    fit, job$fit_structure[[1L]], design$tau, p
  )
  qhat_fit <- app_joint_qdesn_predict_fit(
    fit, design$Z[design$fit_local, , drop = FALSE], design$tau
  )
  qhat_validation <- app_joint_qdesn_predict_fit(
    fit, design$Z[design$validation_local, , drop = FALSE], design$tau
  )
  stored_fit <- as.matrix(app_read_csv(file.path(worker_dir, "qhat_fit_mean.csv")))
  stored_validation <- as.matrix(app_read_csv(file.path(
    worker_dir, "qhat_validation_mean.csv"
  )))
  fit_max <- max(abs(qhat_fit - stored_fit))
  validation_max <- max(abs(qhat_validation - stored_validation))
  if (!is.finite(fit_max) || !is.finite(validation_max) ||
      fit_max > contract$qhat_equivalence_tolerance ||
      validation_max > contract$qhat_equivalence_tolerance) {
    stop(sprintf(
      "Jerez qhat equivalence failed for worker %d: fit=%0.4g validation=%0.4g.",
      job$worker_id[[1L]], fit_max, validation_max
    ), call. = FALSE)
  }
  attr(fit, "qhat_equivalence") <- data.frame(
    worker_id = job$worker_id[[1L]],
    model_cell_id = job$model_cell_id[[1L]],
    chain_id = job$chain_id[[1L]],
    fit_max_abs_diff = fit_max,
    validation_max_abs_diff = validation_max,
    tolerance = contract$qhat_equivalence_tolerance,
    status = "pass",
    stringsAsFactors = FALSE
  )
  fit
}

app_joint_article_score_meta <- function(job, design) {
  data.frame(
    mcmc_case_id = job$model_cell_id[[1L]],
    phase178_template_id = job$candidate_id[[1L]],
    case_id = job$model_cell_id[[1L]],
    scenario_id = job$scenario_id[[1L]],
    base_scenario_id = job$scenario_id[[1L]],
    dgp_replicate_id = "article_fixture",
    validation_partition = "article_evaluation",
    fit_structure = job$fit_structure[[1L]],
    variant_id = if (job$likelihood_family[[1L]] == "exAL") "exAL" else "AL",
    candidate_role = job$vb_role[[1L]],
    design_role = job$design_class[[1L]],
    distribution_family = design$dgp_row$distribution_family[[1L]],
    dynamics_class = design$dgp_row$dynamics_class[[1L]],
    source_model_id = app_joint_article_score_model_source_id(job$model_id[[1L]]),
    model_id = job$model_id[[1L]],
    display_label = job$display_label[[1L]],
    likelihood_family = job$likelihood_family[[1L]],
    article_seed = job$article_seed[[1L]],
    selected_candidate_id = job$candidate_id[[1L]],
    design_fingerprint = job$design_fingerprint[[1L]],
    stringsAsFactors = FALSE
  )
}

app_joint_article_score_context <- function(design, rows) {
  list(
    Z = design$Z[rows, , drop = FALSE],
    y = design$y[rows],
    true_q = design$true_q[rows, , drop = FALSE],
    mu = design$mu[rows],
    sigma = design$sigma[rows],
    sc = design$dgp_row
  )
}

app_joint_article_score_average_check_loss <- function(y, qhat, tau) {
  values <- unlist(lapply(seq_along(tau), function(k) {
    app_joint_qdesn_postscore_check_loss(y, qhat[, k], tau[[k]])
  }), use.names = FALSE)
  mean(values)
}

app_joint_article_score_window_metrics <- function(
  meta, qhat_raw, context, tau, weights, window
) {
  contract <- app_joint_qdesn_apply_monotone_contract(qhat_raw, tau)
  score <- app_joint_qdesn_postscore_score_matrix(
    contract$qhat_contract, context$y, context$mu, context$sigma,
    context$sc, tau, weights
  )
  err <- as.numeric(contract$qhat_contract - context$true_q)
  raw_crossing <- sum(contract$raw_crossing$n_crossing_pairs)
  contract_crossing <- sum(contract$contract_crossing$n_crossing_pairs)
  opportunities <- nrow(qhat_raw) * (length(tau) - 1L)
  data.frame(
    meta,
    window = window,
    rows = nrow(qhat_raw),
    dgp_integrated_acrps = score$dgp_integrated_acrps,
    realized_acrps = score$realized_acrps,
    average_quantile_loss = app_joint_article_score_average_check_loss(
      context$y, contract$qhat_contract, tau
    ),
    oracle_quantile_mae = mean(abs(err)),
    oracle_quantile_rmse = sqrt(mean(err^2)),
    oracle_quantile_bias = mean(err),
    raw_crossing_pairs = raw_crossing,
    contract_crossing_pairs = contract_crossing,
    raw_crossing_opportunities = opportunities,
    raw_crossing_rate = raw_crossing / opportunities,
    mean_abs_monotone_adjustment = contract$mean_abs_adjustment,
    max_abs_monotone_adjustment = contract$max_abs_adjustment,
    stringsAsFactors = FALSE
  )
}

app_joint_article_score_case <- function(root, jobs, contract) {
  jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
  design <- readRDS(jobs$design_path[[1L]])
  if (!identical(as.numeric(design$tau), contract$tau)) {
    stop("Jerez design tau grid does not match the score contract.",
         call. = FALSE)
  }
  meta <- app_joint_article_score_meta(jobs[1L, , drop = FALSE], design)
  fits <- lapply(seq_len(nrow(jobs)), function(ii) {
    app_joint_article_score_read_fit(root, jobs[ii, , drop = FALSE], contract)
  })
  qhat_equivalence <- app_bind_rows_fill(lapply(fits, function(x) {
    attr(x, "qhat_equivalence")
  }))
  forecast_rows <- design$score_local
  if (!length(forecast_rows) ||
      any(!forecast_rows %in% design$validation_local)) {
    stop("Forecast score rows must be a nonempty subset of design$validation_local.",
         call. = FALSE)
  }
  forecast <- app_joint_article_score_context(design, forecast_rows)
  fit_context <- app_joint_article_score_context(design, design$fit_local)
  oracle <- app_joint_qdesn_postscore_score_matrix(
    forecast$true_q, forecast$y, forecast$mu, forecast$sigma,
    forecast$sc, design$tau, contract$weights_qs
  )
  draws <- app_joint_qdesn_bind_rows(lapply(seq_along(fits), function(ii) {
    app_joint_qdesn_postscore_chain_draws(
      fit = fits[[ii]], forecast = forecast, y = forecast$y,
      mu = forecast$mu, sigma = forecast$sigma, sc = forecast$sc,
      tau = design$tau, weights = contract$weights_qs,
      fit_structure = jobs$fit_structure[[1L]],
      chain_id = jobs$chain_id[[ii]],
      pairing_seed = contract$primary_pairing_seed,
      draws_per_chain = contract$score_draws_per_chain,
      chunk_size = contract$chunk_size,
      oracle_score = oracle$dgp_integrated_acrps
    )
  }))
  if (any(!is.finite(as.matrix(draws[vapply(draws, is.numeric, logical(1L))]))) ||
      any(draws$contract_crossing_pairs != 0L) ||
      min(draws$expected_regret) < -contract$regret_tolerance) {
    stop(sprintf("Jerez draw-level score contract failed for '%s'.",
                 meta$mcmc_case_id), call. = FALSE)
  }
  draws <- cbind(meta[rep(1L, nrow(draws)), , drop = FALSE], draws)
  pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(
    fits, design$Z[design$fit_local, , drop = FALSE],
    length(design$tau), ncol(design$Z), design$tau
  )
  pooled <- app_joint_article_score_complete_fit(
    pooled, jobs$fit_structure[[1L]], design$tau, ncol(design$Z)
  )
  fit_raw <- app_joint_qdesn_predict_fit(
    pooled, design$Z[design$fit_local, , drop = FALSE], design$tau
  )
  forecast_raw <- app_joint_qdesn_predict_fit(
    pooled, design$Z[forecast_rows, , drop = FALSE], design$tau
  )
  fit_metric <- app_joint_article_score_window_metrics(
    meta, fit_raw, fit_context, design$tau, contract$weights_qs, "fit"
  )
  forecast_metric <- app_joint_article_score_window_metrics(
    meta, forecast_raw, forecast, design$tau, contract$weights_qs, "forecast"
  )
  diagnostics <- cbind(
    meta, app_joint_qdesn_postscore_draw_diagnostics(draws, contract)
  )
  diagnostics$raw_crossing_opportunities <-
    nrow(draws) * nrow(forecast$Z) * (length(design$tau) - 1L)
  diagnostics$raw_crossing_rate <-
    diagnostics$raw_crossing_pairs / diagnostics$raw_crossing_opportunities
  diagnostics$coherence_status <- if (
    diagnostics$contract_crossing_pairs != 0L
  ) "fail" else if (
    diagnostics$raw_crossing_rate > contract$raw_crossing_rate_review ||
      diagnostics$mean_abs_adjustment_over_sigma >
        contract$standardized_adjustment_review
  ) "review" else "pass"
  allocation <- app_joint_qdesn_postscore_chain_allocation(draws)
  if (nrow(allocation)) {
    allocation <- cbind(meta[rep(1L, nrow(allocation)), , drop = FALSE],
                        allocation)
  }
  seeds <- if (identical(jobs$fit_structure[[1L]], "independent")) {
    c(contract$primary_pairing_seed, contract$sensitivity_pairing_seeds)
  } else contract$primary_pairing_seed
  sensitivity <- app_joint_qdesn_bind_rows(lapply(seeds, function(seed) {
    seeded <- app_joint_qdesn_bind_rows(lapply(seq_along(fits), function(ii) {
      app_joint_qdesn_postscore_chain_draws(
        fit = fits[[ii]], forecast = forecast, y = forecast$y,
        mu = forecast$mu, sigma = forecast$sigma, sc = forecast$sc,
        tau = design$tau, weights = contract$weights_qs,
        fit_structure = jobs$fit_structure[[1L]],
        chain_id = jobs$chain_id[[ii]], pairing_seed = seed,
        draws_per_chain = contract$sensitivity_draws_per_chain,
        chunk_size = contract$chunk_size,
        oracle_score = oracle$dgp_integrated_acrps
      )
    }))
    data.frame(
      pairing_seed = if (identical(jobs$fit_structure[[1L]], "independent")) {
        seed
      } else NA_integer_,
      n_draws = nrow(seeded),
      posterior_score_mean = mean(seeded$dgp_integrated_acrps),
      posterior_score_median = stats::median(seeded$dgp_integrated_acrps),
      posterior_score_q025 = as.numeric(stats::quantile(
        seeded$dgp_integrated_acrps, 0.025, names = FALSE, type = 8
      )),
      posterior_score_q975 = as.numeric(stats::quantile(
        seeded$dgp_integrated_acrps, 0.975, names = FALSE, type = 8
      )),
      raw_crossing_rate = sum(seeded$raw_crossing_pairs) /
        (nrow(seeded) * nrow(forecast$Z) * (length(design$tau) - 1L)),
      stringsAsFactors = FALSE
    )
  }))
  sensitivity <- cbind(meta[rep(1L, nrow(sensitivity)), , drop = FALSE],
                       sensitivity)
  source <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(jobs)), function(ii) {
    worker_dir <- app_joint_article_mcmc_worker_dir(root, jobs$worker_id[[ii]])
    check <- app_joint_shared_verify_manifest(
      worker_dir, file.path(worker_dir, "artifact_manifest.csv")
    )
    data.frame(
      meta, worker_id = jobs$worker_id[[ii]], chain_id = jobs$chain_id[[ii]],
      worker_output_dir = normalizePath(worker_dir, mustWork = TRUE),
      worker_manifest_entries = nrow(check),
      worker_manifest_status = if (all(check$verified)) "pass" else "fail",
      retained_draws = nrow(fits[[ii]]$beta_draws),
      score_draws_selected = min(nrow(fits[[ii]]$beta_draws),
                                 contract$score_draws_per_chain),
      stringsAsFactors = FALSE
    )
  }))
  list(
    draws = draws,
    diagnostics = diagnostics,
    canonical = forecast_metric,
    metrics = app_joint_qdesn_bind_rows(list(fit_metric, forecast_metric)),
    allocation = allocation,
    pairing_sensitivity = sensitivity,
    qhat_equivalence = qhat_equivalence,
    source = source
  )
}

app_joint_article_score_cell_dir <- function(work_dir, model_cell_id) {
  file.path(work_dir, "cells", model_cell_id)
}

app_joint_article_score_cell_complete <- function(path) {
  manifest <- file.path(path, "artifact_manifest.csv")
  if (!file.exists(manifest)) return(FALSE)
  check <- tryCatch(app_joint_shared_verify_manifest(path, manifest),
                    error = function(e) NULL)
  !is.null(check) && nrow(check) > 0L && all(check$verified)
}

app_joint_article_score_write_gzip_csv <- function(x, path) {
  app_ensure_dir(dirname(path))
  con <- gzfile(path, open = "wt", compression = 9)
  on.exit(close(con), add = TRUE)
  utils::write.csv(x, con, row.names = FALSE, na = "")
  normalizePath(path, mustWork = TRUE)
}

app_joint_article_score_write_cell <- function(result, path) {
  final_dir <- normalizePath(path, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_write_csv(x, file.path(tmp, name))
  paths <- c(
    posterior_dgp_integrated_acrps_draws =
      app_joint_article_score_write_gzip_csv(
        result$draws, file.path(tmp, "posterior_dgp_integrated_acrps_draws.csv.gz")
      ),
    score_functional_diagnostics =
      write(result$diagnostics, "score_functional_diagnostics.csv"),
    canonical_action = write(result$canonical, "canonical_action.csv"),
    window_metric_summary = write(result$metrics, "window_metric_summary.csv"),
    chain_allocation_sensitivity =
      write(result$allocation, "chain_allocation_sensitivity.csv"),
    pairing_sensitivity = write(result$pairing_sensitivity, "pairing_sensitivity.csv"),
    qhat_equivalence = write(result$qhat_equivalence, "qhat_equivalence.csv"),
    source_inventory = write(result$source, "source_inventory.csv")
  )
  app_joint_shared_write_manifest(tmp, paths)
  unlink(final_dir, recursive = TRUE, force = TRUE)
  app_ensure_dir(dirname(final_dir))
  if (!file.rename(tmp, final_dir)) {
    stop("Could not publish Jerez score cell checkpoint.", call. = FALSE)
  }
  if (!app_joint_article_score_cell_complete(final_dir)) {
    stop("Jerez score cell checkpoint manifest failed.", call. = FALSE)
  }
  invisible(final_dir)
}

app_joint_article_score_read_cell <- function(path) {
  if (!app_joint_article_score_cell_complete(path)) {
    stop(sprintf("Incomplete Jerez score cell checkpoint: %s", path),
         call. = FALSE)
  }
  list(
    draws = app_read_csv(file.path(path, "posterior_dgp_integrated_acrps_draws.csv.gz")),
    diagnostics = app_read_csv(file.path(path, "score_functional_diagnostics.csv")),
    canonical = app_read_csv(file.path(path, "canonical_action.csv")),
    metrics = app_read_csv(file.path(path, "window_metric_summary.csv")),
    allocation = app_read_csv(file.path(path, "chain_allocation_sensitivity.csv")),
    pairing_sensitivity = app_read_csv(file.path(path, "pairing_sensitivity.csv")),
    qhat_equivalence = app_read_csv(file.path(path, "qhat_equivalence.csv")),
    source = app_read_csv(file.path(path, "source_inventory.csv"))
  )
}

app_joint_article_score_run_cells <- function(
  groups, root, contract, work_dir, cores = 4L
) {
  app_ensure_dir(work_dir)
  run <- function(index) {
    tryCatch({
      path <- app_joint_article_score_cell_dir(
        work_dir, groups[[index]]$model_cell_id[[1L]]
      )
      if (!app_joint_article_score_cell_complete(path)) {
        result <- app_joint_article_score_case(root, groups[[index]], contract)
        app_joint_article_score_write_cell(result, path)
      }
      normalizePath(path, mustWork = TRUE)
    }, error = function(e) structure(conditionMessage(e), class = "try-error"))
  }
  result <- if (.Platform$OS.type != "windows" && cores > 1L) {
    parallel::mclapply(seq_along(groups), run,
                       mc.cores = min(as.integer(cores), length(groups)),
                       mc.preschedule = FALSE)
  } else lapply(seq_along(groups), run)
  failed <- vapply(result, inherits, logical(1L), "try-error")
  if (any(failed)) {
    stop(sprintf(
      "Jerez score reconstruction failed: %s",
      paste(unlist(result[failed], use.names = FALSE), collapse = " | ")
    ), call. = FALSE)
  }
  paths <- unlist(result, use.names = FALSE)
  names(paths) <- names(groups)
  paths
}

app_joint_article_score_collect_cells <- function(paths) {
  cells <- lapply(paths, app_joint_article_score_read_cell)
  list(
    draws = app_joint_qdesn_bind_rows(lapply(cells, `[[`, "draws")),
    diagnostics = app_joint_qdesn_bind_rows(lapply(cells, `[[`, "diagnostics")),
    canonical = app_joint_qdesn_bind_rows(lapply(cells, `[[`, "canonical")),
    metrics = app_joint_qdesn_bind_rows(lapply(cells, `[[`, "metrics")),
    allocation = app_joint_qdesn_bind_rows(lapply(cells, `[[`, "allocation")),
    pairing_sensitivity = app_joint_qdesn_bind_rows(lapply(cells, `[[`, "pairing_sensitivity")),
    qhat_equivalence = app_joint_qdesn_bind_rows(lapply(cells, `[[`, "qhat_equivalence")),
    source = app_joint_qdesn_bind_rows(lapply(cells, `[[`, "source"))
  )
}

app_joint_article_score_canonical_table <- function(canonical) {
  names(canonical)[names(canonical) == "dgp_integrated_acrps"] <-
    "canonical_action_dgp_integrated_acrps"
  names(canonical)[names(canonical) == "realized_acrps"] <-
    "canonical_action_realized_acrps"
  names(canonical)[names(canonical) == "average_quantile_loss"] <-
    "canonical_action_average_quantile_loss"
  names(canonical)[names(canonical) == "raw_crossing_pairs"] <-
    "canonical_raw_crossing_pairs"
  names(canonical)[names(canonical) == "contract_crossing_pairs"] <-
    "canonical_contract_crossing_pairs"
  names(canonical)[names(canonical) == "mean_abs_monotone_adjustment"] <-
    "canonical_mean_abs_adjustment"
  names(canonical)[names(canonical) == "max_abs_monotone_adjustment"] <-
    "canonical_max_abs_adjustment"
  canonical
}

app_joint_article_score_join_summary <- function(score) {
  canonical <- app_joint_article_score_canonical_table(score$canonical)
  keep <- c(
    "mcmc_case_id", "canonical_action_dgp_integrated_acrps",
    "canonical_action_realized_acrps",
    "canonical_action_average_quantile_loss",
    "canonical_raw_crossing_pairs", "canonical_contract_crossing_pairs",
    "canonical_mean_abs_adjustment", "canonical_max_abs_adjustment"
  )
  out <- merge(score$diagnostics, canonical[, keep, drop = FALSE],
               by = "mcmc_case_id", all.x = TRUE, sort = FALSE)
  out <- out[order(out$scenario_id, out$likelihood_family, out$fit_structure), ,
             drop = FALSE]
  rownames(out) <- NULL
  out
}

app_joint_article_score_forecast_metric_summary <- function(metrics) {
  metrics[metrics$window == "forecast", , drop = FALSE]
}

app_joint_article_score_oracle_recovery_summary <- function(metrics) {
  metrics[, c(
    "mcmc_case_id", "case_id", "scenario_id", "base_scenario_id",
    "source_model_id", "model_id", "display_label", "likelihood_family",
    "fit_structure", "window", "rows", "oracle_quantile_mae",
    "oracle_quantile_rmse", "oracle_quantile_bias"
  ), drop = FALSE]
}

app_joint_article_score_crossing_summary <- function(metrics, diagnostics) {
  out <- metrics[, c(
    "mcmc_case_id", "case_id", "scenario_id", "source_model_id",
    "model_id", "display_label", "likelihood_family", "fit_structure",
    "window", "rows", "raw_crossing_pairs", "contract_crossing_pairs",
    "raw_crossing_opportunities", "raw_crossing_rate",
    "mean_abs_monotone_adjustment", "max_abs_monotone_adjustment"
  ), drop = FALSE]
  status <- diagnostics[, c("mcmc_case_id", "coherence_status"), drop = FALSE]
  merge(out, status, by = "mcmc_case_id", all.x = TRUE, sort = FALSE)
}

app_joint_article_score_gamma_sigma_diagnostics <- function(root, plan) {
  exal <- plan[plan$likelihood_family == "exAL", , drop = FALSE]
  groups <- split(exal, factor(exal$model_cell_id, levels = unique(exal$model_cell_id)))
  app_joint_qdesn_bind_rows(lapply(groups, function(jobs) {
    jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
    design <- readRDS(jobs$design_path[[1L]])
    fits <- lapply(seq_len(nrow(jobs)), function(ii) {
      draws <- app_read_csv(file.path(
        app_joint_article_mcmc_worker_dir(root, jobs$worker_id[[ii]]),
        "posterior_draws.csv.gz"
      ))
      list(
        sigma_draws = app_joint_article_score_select_block(draws, "sigma"),
        gamma_draws = app_joint_article_score_select_block(draws, "gamma")
      )
    })
    summarize <- function(param) {
      mats <- lapply(fits, `[[`, paste0(param, "_draws"))
      diag_rows <- lapply(seq_along(design$tau), function(k) {
        m <- do.call(cbind, lapply(mats, function(x) x[, k]))
        d <- app_joint_exqdesn_modern_diagnostics(m)
        data.frame(
          parameter = param, tau = design$tau[[k]],
          rank_rhat = d$rank_rhat, folded_rhat = d$folded_rhat,
          bulk_ess = d$bulk_ess, tail_ess = d$tail_ess,
          mcse_mean = d$mcse_mean, stringsAsFactors = FALSE
        )
      })
      diag <- app_bind_rows_fill(diag_rows)
      values <- unlist(mats, use.names = FALSE)
      data.frame(
        min_value = min(values), max_value = max(values),
        mean_value = mean(values),
        mean_draw_sd = mean(vapply(mats, function(x) {
          mean(apply(x, 2L, stats::sd))
        }, numeric(1L))),
        max_rank_rhat = max(diag$rank_rhat),
        max_folded_rhat = max(diag$folded_rhat),
        min_bulk_ess = min(diag$bulk_ess),
        min_tail_ess = min(diag$tail_ess),
        max_mcse_mean = max(diag$mcse_mean),
        stringsAsFactors = FALSE
      )
    }
    sigma <- summarize("sigma")
    gamma <- summarize("gamma")
    data.frame(
      model_cell_id = jobs$model_cell_id[[1L]],
      scenario_id = jobs$scenario_id[[1L]],
      source_model_id = app_joint_article_score_model_source_id(jobs$model_id[[1L]]),
      model_id = jobs$model_id[[1L]],
      display_label = jobs$display_label[[1L]],
      likelihood_family = jobs$likelihood_family[[1L]],
      fit_structure = jobs$fit_structure[[1L]],
      n_chains = nrow(jobs),
      retained_draws_per_chain = unique(jobs$n_keep)[[1L]],
      sigma_min = sigma$min_value,
      sigma_max = sigma$max_value,
      sigma_mean = sigma$mean_value,
      sigma_mean_draw_sd = sigma$mean_draw_sd,
      sigma_max_rank_rhat = sigma$max_rank_rhat,
      sigma_min_bulk_ess = sigma$min_bulk_ess,
      sigma_min_tail_ess = sigma$min_tail_ess,
      gamma_min = gamma$min_value,
      gamma_max = gamma$max_value,
      gamma_mean = gamma$mean_value,
      gamma_mean_draw_sd = gamma$mean_draw_sd,
      gamma_max_rank_rhat = gamma$max_rank_rhat,
      gamma_min_bulk_ess = gamma$min_bulk_ess,
      gamma_min_tail_ess = gamma$min_tail_ess,
      diagnostic_status = if (all(is.finite(c(
        sigma$max_rank_rhat, sigma$min_bulk_ess, sigma$min_tail_ess,
        gamma$max_rank_rhat, gamma$min_bulk_ess, gamma$min_tail_ess
      )))) "review_level_retained" else "fail",
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_article_score_precision_repair_summary <- function(root, plan) {
  rows <- lapply(seq_len(nrow(plan)), function(ii) {
    job <- plan[ii, , drop = FALSE]
    worker_dir <- app_joint_article_mcmc_worker_dir(root, job$worker_id[[1L]])
    summary <- app_read_csv(file.path(worker_dir, "posterior_summary.csv"))
    diag <- app_read_csv(file.path(worker_dir, "precision_repair_diagnostics.csv"))
    cbind(job[, c(
      "worker_id", "model_cell_id", "scenario_id", "model_id",
      "likelihood_family", "fit_structure", "chain_id"
    ), drop = FALSE], data.frame(
      precision_repair_enabled = app_as_bool(summary$precision_repair_enabled[[1L]]),
      precision_repair_count = as.integer(summary$precision_repair_count[[1L]]),
      precision_repair_diagnostic_rows = nrow(diag),
      precision_repair_max_relative_jitter =
        as.numeric(summary$precision_repair_max_relative_jitter[[1L]]),
      stringsAsFactors = FALSE
    ))
  })
  worker <- app_joint_qdesn_bind_rows(rows)
  app_joint_qdesn_bind_rows(lapply(split(worker, worker$model_cell_id), function(x) {
    data.frame(
      model_cell_id = x$model_cell_id[[1L]],
      scenario_id = x$scenario_id[[1L]],
      source_model_id = app_joint_article_score_model_source_id(x$model_id[[1L]]),
      model_id = x$model_id[[1L]],
      likelihood_family = x$likelihood_family[[1L]],
      fit_structure = x$fit_structure[[1L]],
      workers = nrow(x),
      repair_enabled_workers = sum(x$precision_repair_enabled),
      repaired_workers = sum(x$precision_repair_count > 0L),
      total_precision_repair_count = sum(x$precision_repair_count),
      max_relative_jitter = max(x$precision_repair_max_relative_jitter),
      diagnostic_rows = sum(x$precision_repair_diagnostic_rows),
      status = if (all(is.finite(x$precision_repair_max_relative_jitter)) &&
        max(x$precision_repair_max_relative_jitter) <= 1e-8) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_article_score_contrast_summary <- function(draws, contract, crossing) {
  contrast <- app_joint_qdesn_postscore_joint_independent_contrasts(draws, contract)
  summary <- contrast$summary
  summary$numerical_winner <- ifelse(
    summary$score_delta_mean < 0, "joint", "independent"
  )
  summary$evidence_strength <- ifelse(
    summary$score_delta_q975 < 0 &
      summary$probability_lower_score >= contract$posterior_probability_floor,
    "directional_interval_favors_joint",
    ifelse(
      summary$score_delta_q025 > 0 &
        (1 - summary$probability_lower_score) >= contract$posterior_probability_floor,
      "directional_interval_favors_independent",
      "overlapping_interval_descriptive_order_only"
    )
  )
  cx <- crossing[crossing$window == "forecast", c(
    "mcmc_case_id", "raw_crossing_pairs", "contract_crossing_pairs"
  ), drop = FALSE]
  joint <- cx
  names(joint) <- c(
    "joint_mcmc_case_id", "joint_raw_crossing_pairs",
    "joint_contract_crossing_pairs"
  )
  independent <- cx
  names(independent) <- c(
    "independent_mcmc_case_id", "independent_raw_crossing_pairs",
    "independent_contract_crossing_pairs"
  )
  summary <- merge(summary, joint, by = "joint_mcmc_case_id",
                   all.x = TRUE, sort = FALSE)
  summary <- merge(summary, independent, by = "independent_mcmc_case_id",
                   all.x = TRUE, sort = FALSE)
  summary$crossing_comparison <- ifelse(
    summary$joint_contract_crossing_pairs == 0L &
      summary$independent_contract_crossing_pairs == 0L,
    "both_contract_zero", "contract_crossing_failure"
  )
  list(draws = contrast$draws, summary = summary)
}

app_joint_article_score_winner_summary <- function(summary) {
  groups <- split(summary, factor(summary$scenario_id, levels = unique(summary$scenario_id)))
  app_joint_qdesn_bind_rows(lapply(groups, function(x) {
    x <- x[order(x$posterior_score_mean, x$model_id), , drop = FALSE]
    winner <- x[1L, , drop = FALSE]
    runner <- x[2L, , drop = FALSE]
    data.frame(
      scenario_id = winner$scenario_id,
      winner_model_id = winner$model_id,
      winner_source_model_id = winner$source_model_id,
      winner_display_label = winner$display_label,
      winner_likelihood_family = winner$likelihood_family,
      winner_fit_structure = winner$fit_structure,
      winner_posterior_score_mean = winner$posterior_score_mean,
      winner_posterior_score_median = winner$posterior_score_median,
      winner_posterior_score_q025 = winner$posterior_score_q025,
      winner_posterior_score_q975 = winner$posterior_score_q975,
      runner_up_model_id = runner$model_id,
      runner_up_display_label = runner$display_label,
      runner_up_posterior_score_mean = runner$posterior_score_mean,
      winner_minus_runner_up_mean =
        winner$posterior_score_mean - runner$posterior_score_mean,
      intervals_overlap_runner_up =
        winner$posterior_score_q975 >= runner$posterior_score_q025 &&
          runner$posterior_score_q975 >= winner$posterior_score_q025,
      winner_score_functional_status = winner$score_functional_status,
      winner_coherence_status = winner$coherence_status,
      interpretation = if (
        winner$posterior_score_q975 < runner$posterior_score_q025
      ) "interval_separated_numerical_minimum" else
        "descriptive_numerical_minimum_with_interval_overlap_or_review",
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_article_score_formula_quadrature_audit <- function(contract) {
  formula <- app_joint_qdesn_postscore_formula_audit(contract)
  oracle <- app_joint_qdesn_postscore_oracle_minimum_audit(contract)
  quadrature <- data.frame(
    audit_section = "quadrature",
    quantile_index = seq_along(contract$tau),
    tau = contract$tau,
    weight_on_twice_check_loss = contract$weights_qs,
    coefficient_on_check_loss = 2 * contract$weights_qs,
    weight_sum = sum(contract$weights_qs),
    renormalized = FALSE,
    status = "pass",
    stringsAsFactors = FALSE
  )
  formula$audit_section <- "formula_expected_check_loss"
  formula$status <- ifelse(
    formula$analytic_status == "pass" & formula$monte_carlo_status == "pass",
    "pass", "fail"
  )
  oracle$audit_section <- "oracle_minimum"
  app_bind_rows_fill(list(formula, oracle, quadrature))
}

app_joint_article_score_source_completeness_audit <- function(
  reaudit, score, contract
) {
  observed_forecast_cells <- length(unique(score$metrics$mcmc_case_id[
    score$metrics$window == "forecast"
  ]))
  data.frame(
    source = c(
      "source_jobs", "vb_components", "compact_initializers",
      "mcmc_workers", "worker_manifests", "score_cells",
      "qhat_equivalence", "forecast_rows"
    ),
    expected = c(
      contract$expected_source_jobs, contract$expected_vb_components,
      contract$expected_initializers, contract$expected_mcmc_workers,
      contract$expected_mcmc_workers, contract$expected_model_cells,
      contract$expected_mcmc_workers, contract$expected_model_cells
    ),
    observed = c(
      reaudit$observed[reaudit$gate == "source_jobs"],
      reaudit$observed[reaudit$gate == "vb_components"],
      reaudit$observed[reaudit$gate == "compact_initializers"],
      reaudit$observed[reaudit$gate == "mcmc_workers"],
      reaudit$observed[reaudit$gate == "worker_manifests"],
      nrow(score$diagnostics), nrow(score$qhat_equivalence),
      observed_forecast_cells
    ),
    failed = c(
      reaudit$failed[reaudit$gate == "source_jobs"],
      reaudit$failed[reaudit$gate == "vb_components"],
      reaudit$failed[reaudit$gate == "compact_initializers"],
      reaudit$failed[reaudit$gate == "mcmc_workers"],
      reaudit$failed[reaudit$gate == "worker_manifests"],
      sum(score$diagnostics$contract_crossing_pairs != 0L),
      sum(score$qhat_equivalence$status != "pass"), 0L
    ),
    status = c(rep("pass", 5L),
      if (nrow(score$diagnostics) == contract$expected_model_cells) "pass" else "fail",
      if (all(score$qhat_equivalence$status == "pass")) "pass" else "fail",
      if (observed_forecast_cells == contract$expected_model_cells) "pass" else "fail"
    ),
    note = c(
      "source campaign evidence complete",
      "article-window VB components complete",
      "initializer manifests verified",
      "MCMC chain workers complete",
      "MCMC worker manifests verified",
      "one score cell per model cell",
      "reconstructed qhat paths match worker-stored means",
      "forecast scoring uses design$score_local"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_article_score_plan_status_supersession <- function(root) {
  plans <- list(
    model_cell_plan = app_read_csv(file.path(root, "model_cell_plan.csv")),
    mcmc_worker_plan = app_read_csv(file.path(root, "mcmc_worker_plan.csv")),
    source_future_article_fixture_mcmc_plan = app_read_csv(file.path(
      root, "source_future_article_fixture_mcmc_plan.csv"
    ))
  )
  rows <- list()
  cursor <- 1L
  for (file in names(plans)) {
    x <- plans[[file]]
    for (field in intersect(
      c("mcmc_status", "initializer_status", "launch_status"), names(x)
    )) {
      tab <- as.data.frame(table(x[[field]]), stringsAsFactors = FALSE)
      names(tab) <- c("frozen_value", "row_count")
      for (ii in seq_len(nrow(tab))) {
        rows[[cursor]] <- data.frame(
          source_file = paste0(file, ".csv"),
          field = field,
          frozen_value = tab$frozen_value[[ii]],
          row_count = tab$row_count[[ii]],
          superseded_by = "final_health_and_manifest_evidence",
          superseding_files = paste(c(
            "vb_health_summary.csv", "vb_final_manifest_verification.csv",
            "mcmc_health_summary.csv", "mcmc_worker_manifest_verification.csv",
            "final_confirmation_assessment.csv",
            "computation_closeout_reaudit.csv"
          ), collapse = ";"),
          action = "preserve_frozen_plan_field_do_not_rewrite",
          status = "superseded",
          stringsAsFactors = FALSE
        )
        cursor <- cursor + 1L
      }
    }
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_article_score_phase181_reconciliation <- function(summary, contract) {
  phase181 <- app_read_csv(app_path(
    "tables/joint_qdesn_phase181_article_scenario_model_summary.csv"
  ))
  phase181$model_key <- app_joint_article_score_model_source_id(phase181$model_id)
  left <- summary
  left$model_key <- app_joint_article_score_model_source_id(left$model_id)
  right <- phase181[, c(
    "scenario_id", "model_key", "posterior_score_mean",
    "posterior_score_q025", "posterior_score_q975",
    "canonical_action_dgp_integrated_acrps", "claim_status",
    "source_action", "source_phase"
  ), drop = FALSE]
  names(right) <- c(
    "scenario_id", "model_key", "phase181_posterior_score_mean",
    "phase181_posterior_score_q025", "phase181_posterior_score_q975",
    "phase181_canonical_action_dgp_integrated_acrps",
    "phase181_claim_status", "phase181_source_action", "phase181_source_phase"
  )
  out <- merge(left[, c(
    "scenario_id", "model_key", "mcmc_case_id", "model_id",
    "source_model_id", "display_label", "posterior_score_mean",
    "posterior_score_q025", "posterior_score_q975",
    "canonical_action_dgp_integrated_acrps", "selected_candidate_id",
    "article_seed"
  ), drop = FALSE], right,
  by = c("scenario_id", "model_key"), all.x = TRUE, sort = FALSE)
  matched <- !is.na(out$phase181_posterior_score_mean)
  out$comparability_label <- ifelse(matched, "descriptively_comparable",
                                    "not_comparable")
  out$comparability_reason <- ifelse(
    matched,
    paste(
      "scenario, model family, seven-level tau grid, score definition, and posterior action align;",
      "Jerez uses separately selected shared-backbone controls and score_local rows;",
      "tracked Phase181 tables do not carry article_seed/forecast-row hashes, so this lane does not supersede article authority"
    ),
    "no matching Phase181 scenario-model row found"
  )
  out$jerez_minus_phase181_mean <-
    out$posterior_score_mean - out$phase181_posterior_score_mean
  out$score_contract_version <- contract$version
  out
}

app_joint_article_score_article_staging_inventory <- function(packet_dir) {
  candidates <- c(
    "posterior_dgp_integrated_acrps_summary.csv",
    "scenario_winner_summary.csv",
    "joint_independent_contrast_summary.csv",
    "forecast_metric_summary.csv",
    "oracle_recovery_summary.csv",
    "crossing_and_adjustment_summary.csv",
    "phase181_reconciliation.csv"
  )
  existing <- file.path(packet_dir, candidates)
  data.frame(
    artifact_class = c(rep("candidate_csv", length(candidates)),
      "deferred_tex", "deferred_figure"),
    relative_path = c(file.path("score_packet", candidates),
      "tables/joint_qdesn_shared_backbone_article_score_table.tex",
      "figures/joint_qdesn_simulation/joint_qdesn_shared_backbone_article_score_intervals.pdf"),
    exists_now = c(file.exists(existing), FALSE, FALSE),
    article_role = c(
      "32-cell posterior score table",
      "eight-scenario numerical winner table",
      "16 paired joint-minus-independent contrasts",
      "forecast secondary metrics",
      "fit and forecast oracle recovery diagnostics",
      "raw and contract crossing diagnostics",
      "comparison to current Phase181 article authority",
      "future integration-pass table, not generated in Jerez",
      "future integration-pass interval figure, not generated in Jerez"
    ),
    article_safe_status = c(rep("candidate_for_later_review", length(candidates)),
      "deferred_to_integration_coordinator",
      "deferred_to_integration_coordinator"),
    stringsAsFactors = FALSE
  )
}

app_joint_article_score_transfer_inventory <- function(root, out_path) {
  root <- normalizePath(root, mustWork = TRUE)
  all_files <- list.files(root, recursive = TRUE, all.files = TRUE,
                          full.names = TRUE, no.. = TRUE)
  all_files <- all_files[file.info(all_files)$isdir %in% FALSE]
  excluded <- normalizePath(c(
    out_path,
    file.path(dirname(out_path), "transfer_storage_summary.csv")
  ), mustWork = FALSE)
  all_files <- all_files[
    !(normalizePath(all_files, mustWork = TRUE) %in% excluded)
  ]
  rel <- substring(normalizePath(all_files, mustWork = TRUE), nchar(root) + 2L)
  role <- ifelse(grepl("^mcmc_workers/", rel), "mcmc_worker_output",
    ifelse(grepl("^workers/", rel), "vb_worker_output",
      ifelse(grepl("^score_packet/", rel), "score_packet",
        ifelse(grepl("^fixtures/|^designs/|^initializers/", rel),
          "runtime_fixture_design_initializer", "runtime_manifest_or_audit"))))
  classification <- ifelse(
    grepl("(^logs/|[.]pid$|queue_batch|queue_launch|queue_completion)", rel),
    "optional", "required"
  )
  out <- data.frame(
    relative_path = rel,
    size_bytes = as.numeric(file.info(all_files)$size),
    sha256 = vapply(all_files, app_sha256_file, character(1L)),
    classification = classification,
    artifact_role = role,
    stringsAsFactors = FALSE
  )
  out <- out[order(out$relative_path), , drop = FALSE]
  app_write_csv(out, out_path)
  out
}

app_joint_article_score_packet_health <- function(
  summary, contrast, winners, reaudit, packet_paths
) {
  data.frame(
    status = if (
      nrow(summary) == 32L && nrow(contrast) == 16L && nrow(winners) == 8L &&
        all(reaudit$status == "pass") &&
        all(summary$contract_crossing_pairs == 0L) &&
        all(is.finite(summary$posterior_score_mean))
    ) "READY_FOR_MUSCAT_TRANSFER_AND_INTEGRATION_REVIEW" else
      "NOT_READY_FOR_MUSCAT_TRANSFER_AND_INTEGRATION_REVIEW",
    posterior_score_rows = nrow(summary),
    joint_independent_contrasts = nrow(contrast),
    scenario_winners = nrow(winners),
    computation_reaudit_gates = nrow(reaudit),
    computation_reaudit_pass = sum(reaudit$status == "pass"),
    contract_crossing_pairs = sum(summary$contract_crossing_pairs),
    score_functional_pass = sum(summary$score_functional_status == "pass"),
    score_functional_review = sum(summary$score_functional_status != "pass"),
    coherence_pass = sum(summary$coherence_status == "pass"),
    coherence_review = sum(summary$coherence_status != "pass"),
    artifact_count = length(packet_paths),
    created_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    execution_code_commit = app_joint_article_git_value(c("rev-parse", "HEAD")),
    stringsAsFactors = FALSE
  )
}

app_joint_article_score_finalize <- function(
  root = app_joint_article_default_root(),
  out_dir = NULL,
  contract_path = app_joint_article_score_contract_path(),
  score_cores = 4L,
  force = FALSE
) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_article_score_read_contract(contract_path)
  dirs <- app_joint_article_score_dirs(root)
  out_dir <- normalizePath(out_dir %||% dirs$packet, mustWork = FALSE)
  if (dir.exists(out_dir) &&
      file.exists(file.path(out_dir, "artifact_manifest.csv")) &&
      !isTRUE(force)) {
    check <- app_joint_shared_verify_manifest(
      out_dir, file.path(out_dir, "artifact_manifest.csv")
    )
    health <- app_read_csv(file.path(out_dir, "packet_health_summary.csv"))
    current_head <- app_joint_article_git_value(c("rev-parse", "HEAD"))
    current_health <- "execution_code_commit" %in% names(health) &&
      all(health$execution_code_commit == current_head)
    if (all(check$verified) && current_health) {
      return(list(out_dir = out_dir, health = health, reused = TRUE))
    }
  }
  reaudit <- app_joint_article_score_reaudit(root, contract)
  plan <- app_read_csv(file.path(root, "mcmc_worker_plan.csv"))
  plan <- plan[order(plan$cell_index, plan$chain_id), , drop = FALSE]
  groups <- split(plan, factor(plan$model_cell_id, levels = unique(plan$model_cell_id)))
  if (length(groups) != contract$expected_model_cells) {
    stop("Jerez score grouping did not produce 32 model cells.", call. = FALSE)
  }
  app_ensure_dir(out_dir)
  cell_paths <- app_joint_article_score_run_cells(
    groups, root, contract, out_dir, cores = as.integer(score_cores)
  )
  score <- app_joint_article_score_collect_cells(cell_paths)
  summary <- app_joint_article_score_join_summary(score)
  if (nrow(summary) != contract$expected_model_cells ||
      any(!is.finite(summary$posterior_score_mean)) ||
      any(summary$contract_crossing_pairs != 0L) ||
      any(score$source$worker_manifest_status != "pass") ||
      any(score$qhat_equivalence$status != "pass")) {
    stop("Jerez collected score cells failed hard gates.", call. = FALSE)
  }
  formula <- app_joint_article_score_formula_quadrature_audit(contract)
  if (any(formula$status == "fail")) {
    stop("Jerez score formula/quadrature audit failed.", call. = FALSE)
  }
  canonical <- app_joint_article_score_canonical_table(score$canonical)
  forecast_metric <- app_joint_article_score_forecast_metric_summary(score$metrics)
  oracle <- app_joint_article_score_oracle_recovery_summary(score$metrics)
  crossing <- app_joint_article_score_crossing_summary(score$metrics, score$diagnostics)
  pairing <- app_joint_qdesn_postscore_pairing_stability(
    score$pairing_sensitivity, contract
  )
  contrast <- app_joint_article_score_contrast_summary(
    score$draws, contract, crossing
  )
  if (nrow(contrast$summary) != contract$expected_contrasts) {
    stop("Jerez score packet did not produce 16 contrasts.", call. = FALSE)
  }
  winners <- app_joint_article_score_winner_summary(summary)
  if (nrow(winners) != contract$expected_scenarios) {
    stop("Jerez score packet did not produce 8 scenario winners.", call. = FALSE)
  }
  source_audit <- app_joint_article_score_source_completeness_audit(
    reaudit, score, contract
  )
  gamma_sigma <- app_joint_article_score_gamma_sigma_diagnostics(root, plan)
  precision <- app_joint_article_score_precision_repair_summary(root, plan)
  plan_supersession <- app_joint_article_score_plan_status_supersession(root)
  phase181 <- app_joint_article_score_phase181_reconciliation(summary, contract)
  score_contract_out <- file.path(out_dir, "score_contract.csv")
  file.copy(contract$path, score_contract_out, overwrite = TRUE)
  score_contract_sha <- data.frame(
    file = "score_contract.csv",
    sha256 = app_sha256_file(score_contract_out),
    stringsAsFactors = FALSE
  )
  reaudit_out <- file.path(out_dir, "computation_closeout_reaudit.csv")
  file.copy(file.path(root, "computation_closeout_reaudit.csv"),
            reaudit_out, overwrite = TRUE)
  write <- function(x, name) app_write_csv(x, file.path(out_dir, name))
  paths <- c(
    score_contract = normalizePath(score_contract_out, mustWork = TRUE),
    score_contract_sha256 = write(score_contract_sha, "score_contract_sha256.csv"),
    computation_closeout_reaudit = normalizePath(reaudit_out, mustWork = TRUE),
    formula_and_quadrature_audit = write(formula, "formula_and_quadrature_audit.csv"),
    source_completeness_audit = write(source_audit, "source_completeness_audit.csv"),
    posterior_dgp_integrated_acrps_draws =
      app_joint_article_score_write_gzip_csv(
        score$draws, file.path(out_dir, "posterior_dgp_integrated_acrps_draws.csv.gz")
      ),
    posterior_dgp_integrated_acrps_summary =
      write(summary, "posterior_dgp_integrated_acrps_summary.csv"),
    canonical_action_dgp_integrated_acrps =
      write(canonical, "canonical_action_dgp_integrated_acrps.csv"),
    forecast_metric_summary = write(forecast_metric, "forecast_metric_summary.csv"),
    oracle_recovery_summary = write(oracle, "oracle_recovery_summary.csv"),
    crossing_and_adjustment_summary =
      write(crossing, "crossing_and_adjustment_summary.csv"),
    score_functional_diagnostics =
      write(score$diagnostics, "score_functional_diagnostics.csv"),
    chain_allocation_sensitivity =
      write(score$allocation, "chain_allocation_sensitivity.csv"),
    gamma_sigma_diagnostics = write(gamma_sigma, "gamma_sigma_diagnostics.csv"),
    precision_repair_summary = write(precision, "precision_repair_summary.csv"),
    independent_coupling_sensitivity =
      write(pairing, "independent_coupling_sensitivity.csv"),
    qhat_reconstruction_equivalence =
      write(score$qhat_equivalence, "qhat_reconstruction_equivalence.csv"),
    score_source_inventory = write(score$source, "score_source_inventory.csv"),
    joint_independent_contrast_draws =
      app_joint_article_score_write_gzip_csv(
        contrast$draws, file.path(out_dir, "joint_independent_contrast_draws.csv.gz")
      ),
    joint_independent_contrast_summary =
      write(contrast$summary, "joint_independent_contrast_summary.csv"),
    scenario_winner_summary = write(winners, "scenario_winner_summary.csv"),
    plan_status_supersession_audit =
      write(plan_supersession, "plan_status_supersession_audit.csv"),
    phase181_reconciliation = write(phase181, "phase181_reconciliation.csv"),
    article_staging_inventory =
      write(app_joint_article_score_article_staging_inventory(out_dir),
            "article_staging_inventory.csv")
  )
  health <- app_joint_article_score_packet_health(
    summary, contrast$summary, winners, reaudit, paths
  )
  paths <- c(paths, packet_health_summary = write(health, "packet_health_summary.csv"))
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Jerez JOINT shared-backbone score packet", "",
    "This ignored packet deterministically reconstructs posterior scores from",
    "the completed seven-level article-fixture MCMC workers. It does not rerun",
    "VB or MCMC and it does not modify article assets. Phase182 dense-grid",
    "crossing evidence is separate and excluded."
  ), readme, useBytes = TRUE)
  paths <- c(paths, README = readme)
  app_joint_shared_write_manifest(out_dir, paths)
  verification <- app_joint_shared_verify_manifest(
    out_dir, file.path(out_dir, "artifact_manifest.csv")
  )
  app_write_csv(verification, file.path(out_dir, "artifact_manifest_verification.csv"))
  if (any(!verification$verified)) {
    stop("Jerez score packet manifest verification failed.", call. = FALSE)
  }
  transfer <- app_joint_article_score_transfer_inventory(
    root, file.path(out_dir, "transfer_inventory.csv")
  )
  storage <- data.frame(
    runtime_root = root,
    inventory_path = file.path(out_dir, "transfer_inventory.csv"),
    total_files = nrow(transfer),
    total_bytes = sum(transfer$size_bytes),
    required_files = sum(transfer$classification == "required"),
    optional_files = sum(transfer$classification == "optional"),
    inventory_sha256 = app_sha256_file(file.path(out_dir, "transfer_inventory.csv")),
    stringsAsFactors = FALSE
  )
  app_write_csv(storage, file.path(out_dir, "transfer_storage_summary.csv"))
  list(out_dir = out_dir, health = health, reused = FALSE)
}
