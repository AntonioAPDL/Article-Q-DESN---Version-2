# Phase166 structured-VB method development and later freeze boundaries.

app_joint_exqdesn_phase166_candidate_dir <- function(out_dir, candidate_id) {
  file.path(out_dir, "candidates", candidate_id)
}

app_joint_exqdesn_phase166_worker_row_indices <- function(registry, worker_id, worker_count) {
  required <- c("scenario_ids", "fit_structure", "inference_method_id")
  missing <- setdiff(required, names(registry))
  if (length(missing)) stop("Phase166 worker registry is malformed.", call. = FALSE)
  worker_id <- as.integer(worker_id)[[1L]]
  worker_count <- as.integer(worker_count)[[1L]]
  if (!is.finite(worker_id) || !is.finite(worker_count) ||
      worker_count < 1L || worker_id < 1L || worker_id > worker_count) {
    stop("Phase166 worker id/count are invalid.", call. = FALSE)
  }
  group_key <- paste(registry$scenario_ids, registry$fit_structure, sep = "::")
  groups <- unique(group_key)
  worker_groups <- groups[(seq_along(groups) - 1L) %% worker_count == worker_id - 1L]
  which(group_key %in% worker_groups)
}

app_joint_exqdesn_phase166_verify_candidate <- function(candidate_dir) {
  manifest_path <- file.path(candidate_dir, "artifact_manifest.csv")
  if (!file.exists(manifest_path)) return(FALSE)
  tryCatch({
    manifest <- app_read_csv(manifest_path)
    required_labels <- c(
      "candidate_summary", "tau_summary", "interval_summary", "vb_diagnostics",
      "quadrature_summary", "scale_shape_summary", "runtime_summary", "README"
    )
    if (!all(required_labels %in% manifest$label)) return(FALSE)
    paths <- file.path(candidate_dir, manifest$relative_path)
    all(file.exists(paths)) &&
      all(as.numeric(file.info(paths)$size) == as.numeric(manifest$size_bytes)) &&
      all(tolower(vapply(paths, app_sha256_file, character(1L))) == tolower(manifest$sha256))
  }, error = function(e) FALSE)
}

app_joint_exqdesn_phase166_control_args <- function(candidate, fixture) {
  iter_grid <- app_joint_qdesn_phase153_parse_integer_grid(candidate$adaptive_vb_max_iter_grid[[1L]])
  max_iter <- max(c(as.integer(candidate$vb_max_iter[[1L]]), iter_grid))
  alpha_prior_sd <- app_joint_qdesn_parse_numeric_vector(
    candidate$alpha_prior_sd[[1L]], "alpha_prior_sd", allow_inf = TRUE
  )
  controls <- app_joint_qdesn_simulation_controls(
    vb_max_iter = max_iter,
    adaptive_vb_max_iter_grid = max_iter,
    vb_tol = as.numeric(candidate$vb_tol[[1L]]),
    rhs_vb_inner = as.integer(candidate$rhs_vb_inner[[1L]]),
    tau0 = as.numeric(candidate$tau0[[1L]]),
    zeta2 = as.numeric(candidate$zeta2[[1L]]),
    a_sigma = as.numeric(candidate$a_sigma[[1L]]),
    b_sigma = as.numeric(candidate$b_sigma[[1L]]),
    alpha_prior_sd = alpha_prior_sd,
    alpha_min_spacing = as.numeric(candidate$alpha_min_spacing[[1L]]),
    gamma_init_policy = candidate$gamma_init_policy[[1L]],
    review_adjustment_threshold = as.numeric(candidate$review_adjustment_threshold[[1L]]),
    max_dense_dim = as.integer(candidate$max_dense_dim[[1L]]),
    n_cores = 1L
  )
  list(
    max_iter = max_iter,
    tol = controls$vb_tol,
    kappa = 1,
    tau0 = controls$tau0,
    zeta2 = controls$zeta2,
    a_sigma = controls$a_sigma,
    b_sigma = controls$b_sigma,
    alpha_prior_mean = "empirical_quantile",
    alpha_prior_sd = controls$alpha_prior_sd,
    alpha_min_spacing = if (candidate$fit_structure[[1L]] == "joint") controls$alpha_min_spacing else 0,
    gamma_init = app_joint_qdesn_gamma_init_for_policy(fixture$tau, controls),
    max_dense_dim = controls$max_dense_dim,
    rhs_vb_inner = controls$rhs_vb_inner,
    quadrature_nodes = c(4L, 8L, 12L),
    quadrature_tolerance = 1.0e-5,
    diagnostic_stride = 20L
  )
}

app_joint_exqdesn_phase166_meta <- function(candidate, fixture) {
  data.frame(
    scenario_id = fixture$scenario_id,
    scenario_class = fixture$scenario_meta$scenario_class[[1L]],
    distribution_family = fixture$scenario_meta$distribution_family[[1L]],
    dynamics_class = fixture$scenario_meta$dynamics_class[[1L]],
    model_id = candidate$model_id[[1L]],
    display_label = if (candidate$fit_structure[[1L]] == "joint") "Joint exQDESN RHS" else "Independent exQDESN RHS",
    likelihood = "exal",
    fit_structure = candidate$fit_structure[[1L]],
    inference = candidate$inference_method_id[[1L]],
    experiment_id = candidate$phase166_candidate_id[[1L]],
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase166_vb0_warm_start <- function(candidate, fixture) {
  args <- app_joint_exqdesn_phase166_control_args(candidate, fixture)
  if (candidate$fit_structure[[1L]] == "joint") {
    app_joint_exqdesn_fit_vb_dispatch(
      method_id = "VB0_point_v",
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      max_iter = args$max_iter,
      tol = args$tol,
      kappa = args$kappa,
      tau0 = args$tau0,
      zeta2 = args$zeta2,
      a_sigma = args$a_sigma,
      b_sigma = args$b_sigma,
      alpha_prior_mean = args$alpha_prior_mean,
      alpha_prior_sd = args$alpha_prior_sd,
      alpha_min_spacing = args$alpha_min_spacing,
      gamma_init = args$gamma_init,
      max_dense_dim = args$max_dense_dim,
      rhs_vb_inner = args$rhs_vb_inner
    )
  } else {
    app_joint_exqdesn_fit_independent_vb_dispatch(
      method_id = "VB0_point_v",
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      max_iter = args$max_iter,
      tol = args$tol,
      kappa = args$kappa,
      tau0 = args$tau0,
      zeta2 = args$zeta2,
      a_sigma = args$a_sigma,
      b_sigma = args$b_sigma,
      alpha_prior_mean = args$alpha_prior_mean,
      alpha_prior_sd = args$alpha_prior_sd,
      alpha_min_spacing = 0,
      gamma_init = args$gamma_init,
      max_dense_dim = args$max_dense_dim,
      rhs_vb_inner = args$rhs_vb_inner
    )
  }
}

app_joint_exqdesn_phase166_score_fit <- function(fit, fixture, candidate, artifacts) {
  meta <- app_joint_exqdesn_phase166_meta(candidate, fixture)
  fit_raw <- app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau)
  fit_contract <- app_joint_qdesn_apply_monotone_contract(fit_raw, fixture$tau)
  fit_rows <- app_joint_qdesn_quantile_long_rows(
    meta, fixture$row_meta, fixture$tau, fixture$y, fixture$true_q,
    fit_contract$qhat_contract, "qhat"
  )
  fit_scored <- app_joint_qdesn_quantile_scores(fit_rows, "qhat")
  fit_summary <- app_joint_qdesn_phase153_window_summary(
    fit_scored,
    sum(fit_contract$raw_crossing$n_crossing_pairs),
    sum(fit_contract$contract_crossing$n_crossing_pairs),
    as.numeric(fit_contract$adjustment),
    "fit"
  )
  origin_plan <- artifacts$forecast_origin_plan[
    artifacts$forecast_origin_plan$scenario_id == fixture$scenario_id,
    , drop = FALSE
  ]
  origin_plan <- origin_plan[order(origin_plan$origin_index), , drop = FALSE]
  forecast_rows <- vector("list", nrow(origin_plan))
  adjustments <- numeric()
  raw_crossings <- contract_crossings <- 0L
  forecast_start <- proc.time()[["elapsed"]]
  for (jj in seq_len(nrow(origin_plan))) {
    target <- app_joint_qdesn_forecast_target_fixture(
      artifacts, fixture$scenario_id, origin_plan[jj, , drop = FALSE]
    )
    raw <- app_joint_qdesn_predict_fit(fit, target$Z, target$tau)
    contract <- app_joint_qdesn_apply_monotone_contract(raw, target$tau)
    rows <- app_joint_qdesn_quantile_long_rows(
      meta, target$row_meta, target$tau, target$y, target$true_q,
      contract$qhat_contract, "qhat"
    )
    forecast_rows[[jj]] <- app_joint_qdesn_quantile_scores(rows, "qhat")
    adjustments <- c(adjustments, as.numeric(contract$adjustment))
    raw_crossings <- raw_crossings + sum(contract$raw_crossing$n_crossing_pairs)
    contract_crossings <- contract_crossings + sum(contract$contract_crossing$n_crossing_pairs)
  }
  forecast_seconds <- proc.time()[["elapsed"]] - forecast_start
  forecast_scored <- app_joint_qdesn_bind_rows(forecast_rows)
  forecast_summary <- app_joint_qdesn_phase153_window_summary(
    forecast_scored, raw_crossings, contract_crossings, adjustments, "forecast"
  )
  tau_summary <- rbind(
    app_joint_qdesn_phase153_tau_summary(fit_scored, candidate, "fit"),
    app_joint_qdesn_phase153_tau_summary(forecast_scored, candidate, "forecast")
  )
  tau_summary$candidate_id <- candidate$phase166_candidate_id[[1L]]
  tau_summary$inference_method_id <- candidate$inference_method_id[[1L]]
  interval_summary <- rbind(
    transform(
      app_joint_qdesn_interval_summary(fit_scored, "qhat"),
      candidate_id = candidate$phase166_candidate_id[[1L]],
      base_scenario_id = candidate$base_scenario_id[[1L]],
      dgp_replicate_id = candidate$dgp_replicate_id[[1L]],
      dgp_seed = as.integer(candidate$dgp_seed[[1L]]),
      validation_window = "fit",
      inference_method_id = candidate$inference_method_id[[1L]]
    ),
    transform(
      app_joint_qdesn_interval_summary(forecast_scored, "qhat"),
      candidate_id = candidate$phase166_candidate_id[[1L]],
      base_scenario_id = candidate$base_scenario_id[[1L]],
      dgp_replicate_id = candidate$dgp_replicate_id[[1L]],
      dgp_seed = as.integer(candidate$dgp_seed[[1L]]),
      validation_window = "forecast",
      inference_method_id = candidate$inference_method_id[[1L]]
    )
  )
  list(
    fit_summary = fit_summary,
    forecast_summary = forecast_summary,
    tau_summary = tau_summary,
    interval_summary = interval_summary,
    forecast_seconds = forecast_seconds,
    finite_scores = all(is.finite(c(
      fit_scored$qhat, fit_scored$check_loss, fit_scored$truth_abs_error,
      forecast_scored$qhat, forecast_scored$check_loss, forecast_scored$truth_abs_error
    )))
  )
}

app_joint_exqdesn_phase166_vb_diagnostics <- function(fit, candidate) {
  trace <- fit$trace %||% data.frame()
  numeric_trace <- trace[vapply(trace, is.numeric, logical(1L))]
  data.frame(
    candidate_id = candidate$phase166_candidate_id[[1L]],
    base_scenario_id = candidate$base_scenario_id[[1L]],
    dgp_replicate_id = candidate$dgp_replicate_id[[1L]],
    model_id = candidate$model_id[[1L]],
    fit_structure = candidate$fit_structure[[1L]],
    inference_method_id = candidate$inference_method_id[[1L]],
    converged = isTRUE(fit$converged),
    reached_max_iter = !isTRUE(fit$converged),
    trace_rows = nrow(trace),
    final_iter = if (nrow(trace) && "iter" %in% names(trace)) tail(trace$iter, 1L) else NA_integer_,
    final_monitor = if (nrow(trace) && "coordinate_monitor" %in% names(trace)) tail(trace$coordinate_monitor, 1L) else if (nrow(trace) && "monitor" %in% names(trace)) tail(trace$monitor, 1L) else NA_real_,
    sigma_min = min(fit$sigma_mean),
    sigma_median = stats::median(fit$sigma_mean),
    sigma_max = max(fit$sigma_mean),
    gamma_min = min(fit$gamma_mean),
    gamma_median = stats::median(fit$gamma_mean),
    gamma_max = max(fit$gamma_mean),
    finite_trace = nrow(trace) > 0L && all(is.finite(as.matrix(numeric_trace))),
    finite_rhs = !is.null(fit$rhs_prior_summary) && all(is.finite(as.matrix(fit$rhs_prior_summary[vapply(fit$rhs_prior_summary, is.numeric, logical(1L))]))),
    objective_accounting_status = fit$objective_accounting_status %||% "legacy_VB0_monitor",
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase166_compact_quadrature <- function(fit, candidate) {
  if (candidate$inference_method_id[[1L]] == "VB0_point_v") {
    return(data.frame(
      candidate_id = candidate$phase166_candidate_id[[1L]],
      inference_method_id = "VB0_point_v",
      quantile_index = seq_along(fit$tau), tau = fit$tau,
      nodes_per_panel = NA_integer_, relative_change = NA_real_,
      negative_branch_mass = NA_real_, positive_branch_mass = NA_real_,
      converged = NA, status = "not_applicable_point_gamma",
      stringsAsFactors = FALSE
    ))
  }
  x <- fit$scale_shape_summary
  data.frame(
    candidate_id = candidate$phase166_candidate_id[[1L]],
    inference_method_id = candidate$inference_method_id[[1L]],
    quantile_index = x$quantile_index,
    tau = x$tau,
    nodes_per_panel = x$quadrature_nodes_per_panel,
    relative_change = x$quadrature_relative_change,
    negative_branch_mass = x$negative_branch_mass,
    positive_branch_mass = x$positive_branch_mass,
    converged = x$quadrature_converged,
    status = ifelse(x$quadrature_converged, "pass", "review"),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase166_compact_scale_shape <- function(fit, candidate) {
  if (candidate$inference_method_id[[1L]] == "VB0_point_v") {
    return(data.frame(
      candidate_id = candidate$phase166_candidate_id[[1L]],
      inference_method_id = "VB0_point_v",
      quantile_index = seq_along(fit$tau), tau = fit$tau,
      gamma_mean = fit$gamma_mean, sigma_mean = fit$sigma_mean,
      p_gamma_mean = NA_real_, actual_sd_mean = NA_real_,
      negative_branch_mass = as.numeric(fit$gamma_mean < 0),
      stringsAsFactors = FALSE
    ))
  }
  x <- fit$scale_shape_summary
  data.frame(
    candidate_id = candidate$phase166_candidate_id[[1L]],
    inference_method_id = candidate$inference_method_id[[1L]],
    quantile_index = x$quantile_index,
    tau = x$tau,
    gamma_mean = x$gamma_mean,
    sigma_mean = x$sigma_mean,
    p_gamma_mean = x$p_gamma_mean,
    actual_sd_mean = x$actual_sd_mean,
    negative_branch_mass = x$negative_branch_mass,
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase166_write_candidate <- function(result, candidate, out_dir) {
  candidate_id <- candidate$phase166_candidate_id[[1L]]
  final_dir <- app_joint_exqdesn_phase166_candidate_dir(out_dir, candidate_id)
  if (app_joint_exqdesn_phase166_verify_candidate(final_dir)) return(final_dir)
  app_ensure_dir(dirname(final_dir))
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".invalid.", format(Sys.time(), "%Y%m%d%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine invalid Phase166 output.", call. = FALSE)
  }
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase166 Candidate Checkpoint",
    "",
    sprintf("- Candidate: `%s`", candidate_id),
    sprintf("- Scenario: `%s`", candidate$scenario_ids[[1L]]),
    sprintf("- Structure: `%s`", candidate$fit_structure[[1L]]),
    sprintf("- Method: `%s`", candidate$inference_method_id[[1L]]),
    "",
    "This checkpoint contains compact summaries only; no fitted R object is retained."
  ), readme, useBytes = TRUE)
  paths <- c(
    candidate_summary = app_joint_qvp_write_csv(result$candidate_summary, file.path(tmp, "candidate_summary.csv")),
    tau_summary = app_joint_qvp_write_csv(result$tau_summary, file.path(tmp, "tau_summary.csv")),
    interval_summary = app_joint_qvp_write_csv(result$interval_summary, file.path(tmp, "interval_summary.csv")),
    vb_diagnostics = app_joint_qvp_write_csv(result$vb_diagnostics, file.path(tmp, "vb_diagnostics.csv")),
    quadrature_summary = app_joint_qvp_write_csv(result$quadrature_summary, file.path(tmp, "quadrature_summary.csv")),
    scale_shape_summary = app_joint_qvp_write_csv(result$scale_shape_summary, file.path(tmp, "scale_shape_summary.csv")),
    runtime_summary = app_joint_qvp_write_csv(result$runtime_summary, file.path(tmp, "runtime_summary.csv")),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (!file.rename(tmp, final_dir) || !app_joint_exqdesn_phase166_verify_candidate(final_dir)) {
    stop(sprintf("Could not promote Phase166 checkpoint %s.", candidate_id), call. = FALSE)
  }
  final_dir
}

app_joint_exqdesn_phase166_import_vb0 <- function(candidate, dirs = app_joint_exqdesn_phase164_dirs()) {
  source_dir <- candidate$phase153_candidate_dir[[1L]]
  verification <- app_joint_exqdesn_verify_manifest(source_dir, "phase153_vb0_candidate")
  if (any(verification$status != "pass")) stop("Phase153 VB0 candidate verification failed.", call. = FALSE)
  summary <- app_read_csv(file.path(source_dir, "candidate_summary.csv"))
  tau_summary <- app_read_csv(file.path(source_dir, "tau_summary.csv"))
  interval <- app_read_csv(file.path(source_dir, "interval_summary.csv"))
  diagnostics <- app_read_csv(file.path(source_dir, "vb_diagnostics.csv"))
  for (xname in c("summary", "tau_summary", "interval", "diagnostics")) {
    x <- get(xname)
    x$source_phase153_candidate_id <- summary$candidate_id[[1L]]
    x$candidate_id <- candidate$phase166_candidate_id[[1L]]
    x$inference_method_id <- "VB0_point_v"
    assign(xname, x)
  }
  summary$phase166_candidate_id <- candidate$phase166_candidate_id[[1L]]
  summary$source_reused <- TRUE
  summary$source_manifest_verified <- TRUE
  summary$fit_structure <- candidate$fit_structure[[1L]]
  quadrature <- data.frame(
    candidate_id = candidate$phase166_candidate_id[[1L]], inference_method_id = "VB0_point_v",
    quantile_index = seq_len(7L), tau = c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95),
    nodes_per_panel = NA_integer_, relative_change = NA_real_, negative_branch_mass = NA_real_,
    positive_branch_mass = NA_real_, converged = NA, status = "not_applicable_point_gamma",
    stringsAsFactors = FALSE
  )
  scale_shape <- data.frame(
    candidate_id = candidate$phase166_candidate_id[[1L]], inference_method_id = "VB0_point_v",
    quantile_index = seq_len(7L), tau = c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95),
    gamma_mean = NA_real_, sigma_mean = NA_real_, p_gamma_mean = NA_real_,
    actual_sd_mean = NA_real_, negative_branch_mass = NA_real_, stringsAsFactors = FALSE
  )
  runtime <- data.frame(
    candidate_id = candidate$phase166_candidate_id[[1L]],
    inference_method_id = "VB0_point_v", runtime_component = "reused_phase153",
    elapsed_seconds = 0, source_reported_seconds = summary$total_elapsed_seconds[[1L]],
    stringsAsFactors = FALSE
  )
  list(
    candidate_summary = summary, tau_summary = tau_summary,
    interval_summary = interval, vb_diagnostics = diagnostics,
    quadrature_summary = quadrature, scale_shape_summary = scale_shape,
    runtime_summary = runtime
  )
}

app_joint_exqdesn_phase166_evaluate <- function(
  candidate,
  dirs = app_joint_exqdesn_phase164_dirs(),
  warm_start = NULL
) {
  if (isTRUE(as.logical(candidate$use_existing_phase153[[1L]]))) {
    return(app_joint_exqdesn_phase166_import_vb0(candidate, dirs))
  }
  artifacts <- app_joint_exqdesn_load_selected_fixture_artifacts(candidate$scenario_ids[[1L]], dirs)
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, candidate$scenario_ids[[1L]], role = "fit")
  args <- app_joint_exqdesn_phase166_control_args(candidate, fixture)
  if (is.null(warm_start)) {
    warm_start <- app_joint_exqdesn_phase166_vb0_warm_start(candidate, fixture)
  }
  start <- proc.time()[["elapsed"]]
  if (candidate$fit_structure[[1L]] == "joint") {
    fit <- do.call(
      app_joint_exqdesn_fit_vb_dispatch,
      c(list(method_id = candidate$inference_method_id[[1L]], y = fixture$y, Z = fixture$Z, tau = fixture$tau, init = warm_start), args)
    )
  } else {
    fit <- do.call(
      app_joint_exqdesn_fit_independent_vb_dispatch,
      c(list(method_id = candidate$inference_method_id[[1L]], y = fixture$y, Z = fixture$Z, tau = fixture$tau, init = warm_start), args)
    )
  }
  fit_seconds <- proc.time()[["elapsed"]] - start
  scored <- app_joint_exqdesn_phase166_score_fit(fit, fixture, candidate, artifacts)
  diagnostics <- if (candidate$fit_structure[[1L]] == "joint") {
    app_joint_exqdesn_phase166_vb_diagnostics(fit, candidate)
  } else {
    do.call(rbind, lapply(seq_along(fit$fits), function(k) {
      x <- app_joint_exqdesn_phase166_vb_diagnostics(fit$fits[[k]], candidate)
      x$quantile_index <- k
      x$tau <- fixture$tau[[k]]
      x
    }))
  }
  quadrature <- if (candidate$fit_structure[[1L]] == "joint") {
    app_joint_exqdesn_phase166_compact_quadrature(fit, candidate)
  } else {
    do.call(rbind, lapply(fit$fits, app_joint_exqdesn_phase166_compact_quadrature, candidate = candidate))
  }
  scale_shape <- if (candidate$fit_structure[[1L]] == "joint") {
    app_joint_exqdesn_phase166_compact_scale_shape(fit, candidate)
  } else {
    do.call(rbind, lapply(fit$fits, app_joint_exqdesn_phase166_compact_scale_shape, candidate = candidate))
  }
  finite_fit <- all(is.finite(c(fit$qhat_mean, fit$alpha_mean, fit$sigma_mean, fit$gamma_mean))) && all(fit$sigma_mean > 0)
  contract_crossings <- scored$fit_summary$contract_crossing_pairs + scored$forecast_summary$contract_crossing_pairs
  implementation_fail <- !finite_fit || !scored$finite_scores || contract_crossings > 0
  review <- any(!diagnostics$converged) || any(quadrature$status == "review", na.rm = TRUE)
  gate <- if (implementation_fail) "fail" else if (review) "review" else "pass"
  status_reason <- if (implementation_fail) {
    "nonfinite fit/score or contract crossing"
  } else if (review) {
    "finite implementation with max-iteration or quadrature review"
  } else {
    "all Phase166 implementation gates passed"
  }
  candidate_summary <- cbind(
    candidate[, c(
      "phase166_candidate_id", "base_scenario_id", "dgp_replicate_id", "dgp_seed",
      "scenario_ids", "model_id", "fit_structure", "inference_method_id",
      "tau0", "zeta2", "a_sigma", "b_sigma", "alpha_prior_sd", "gamma_init_policy"
    ), drop = FALSE],
    data.frame(
      candidate_id = candidate$phase166_candidate_id[[1L]],
      source_phase153_candidate_id = candidate$candidate_id[[1L]],
      source_reused = FALSE,
      source_manifest_verified = TRUE,
      initialization_method_id = "VB0_point_v",
      initialization_contract = "same_frozen_specification_in_memory",
      gate_status = gate,
      implementation_status = if (implementation_fail) "fail" else "pass",
      vb_converged = all(diagnostics$converged),
      vb_reached_max_iter = any(diagnostics$reached_max_iter),
      quadrature_converged = all(quadrature$converged, na.rm = TRUE),
      finite_fit = finite_fit,
      finite_scores = scored$finite_scores,
      fit_truth_mae = scored$fit_summary$truth_mae,
      fit_truth_rmse = scored$fit_summary$truth_rmse,
      fit_check_loss_mean = scored$fit_summary$check_loss_mean,
      fit_crps_grid_mean = scored$fit_summary$crps_grid_mean,
      fit_raw_crossing_pairs = scored$fit_summary$raw_crossing_pairs,
      fit_contract_crossing_pairs = scored$fit_summary$contract_crossing_pairs,
      forecast_truth_mae = scored$forecast_summary$truth_mae,
      forecast_truth_rmse = scored$forecast_summary$truth_rmse,
      forecast_check_loss_mean = scored$forecast_summary$check_loss_mean,
      forecast_crps_grid_mean = scored$forecast_summary$crps_grid_mean,
      forecast_raw_crossing_pairs = scored$forecast_summary$raw_crossing_pairs,
      forecast_contract_crossing_pairs = scored$forecast_summary$contract_crossing_pairs,
      fit_elapsed_seconds = fit_seconds,
      forecast_scoring_seconds = scored$forecast_seconds,
      total_elapsed_seconds = fit_seconds + scored$forecast_seconds,
      status_reason = status_reason,
      stringsAsFactors = FALSE
    )
  )
  runtime <- data.frame(
    candidate_id = candidate$phase166_candidate_id[[1L]],
    inference_method_id = candidate$inference_method_id[[1L]],
    runtime_component = c("fit", "forecast_scoring", "total"),
    elapsed_seconds = c(fit_seconds, scored$forecast_seconds, fit_seconds + scored$forecast_seconds),
    source_reported_seconds = NA_real_,
    stringsAsFactors = FALSE
  )
  list(
    candidate_summary = candidate_summary,
    tau_summary = scored$tau_summary,
    interval_summary = scored$interval_summary,
    vb_diagnostics = diagnostics,
    quadrature_summary = quadrature,
    scale_shape_summary = scale_shape,
    runtime_summary = runtime
  )
}

app_joint_exqdesn_phase166_run_rows <- function(
  row_indices,
  dirs = app_joint_exqdesn_phase164_dirs()
) {
  registry <- app_read_csv(file.path(dirs$phase164, "method_development_registry.csv"))
  row_indices <- as.integer(row_indices)
  if (any(!is.finite(row_indices)) || any(row_indices < 1L | row_indices > nrow(registry))) {
    stop("Phase166 row indices are invalid.", call. = FALSE)
  }
  results <- vector("list", length(row_indices))
  warm_starts <- new.env(parent = emptyenv())
  for (ii in seq_along(row_indices)) {
    row_id <- row_indices[[ii]]
    candidate <- registry[row_id, , drop = FALSE]
    final_dir <- app_joint_exqdesn_phase166_candidate_dir(dirs$phase166, candidate$phase166_candidate_id[[1L]])
    if (app_joint_exqdesn_phase166_verify_candidate(final_dir)) {
      results[[ii]] <- data.frame(row_index = row_id, candidate_id = candidate$phase166_candidate_id[[1L]], status = "reused", message = "verified checkpoint", stringsAsFactors = FALSE)
      next
    }
    result <- tryCatch({
      warm_start <- NULL
      if (candidate$inference_method_id[[1L]] != "VB0_point_v") {
        warm_key <- paste(candidate$scenario_ids[[1L]], candidate$fit_structure[[1L]], sep = "::")
        if (!exists(warm_key, envir = warm_starts, inherits = FALSE)) {
          artifacts <- app_joint_exqdesn_load_selected_fixture_artifacts(candidate$scenario_ids[[1L]], dirs)
          fixture <- app_joint_qdesn_scenario_fixture(artifacts, candidate$scenario_ids[[1L]], role = "fit")
          assign(
            warm_key,
            app_joint_exqdesn_phase166_vb0_warm_start(candidate, fixture),
            envir = warm_starts
          )
        }
        warm_start <- get(warm_key, envir = warm_starts, inherits = FALSE)
      }
      evaluated <- app_joint_exqdesn_phase166_evaluate(candidate, dirs, warm_start = warm_start)
      app_joint_exqdesn_phase166_write_candidate(evaluated, candidate, dirs$phase166)
      data.frame(row_index = row_id, candidate_id = candidate$phase166_candidate_id[[1L]], status = "completed", message = "", stringsAsFactors = FALSE)
    }, error = function(e) {
      data.frame(row_index = row_id, candidate_id = candidate$phase166_candidate_id[[1L]], status = "failed", message = conditionMessage(e), stringsAsFactors = FALSE)
    })
    results[[ii]] <- result
  }
  do.call(rbind, results)
}

app_joint_exqdesn_phase166_health <- function(dirs = app_joint_exqdesn_phase164_dirs()) {
  registry <- app_read_csv(file.path(dirs$phase164, "method_development_registry.csv"))
  complete <- vapply(registry$phase166_candidate_id, function(id) {
    app_joint_exqdesn_phase166_verify_candidate(app_joint_exqdesn_phase166_candidate_dir(dirs$phase166, id))
  }, logical(1L))
  data.frame(
    stage = "Phase166 structured-VB method development",
    total_rows = nrow(registry),
    completed_rows = sum(complete),
    remaining_rows = sum(!complete),
    percent_complete = 100 * mean(complete),
    vb0_rows = sum(registry$inference_method_id == "VB0_point_v"),
    structured_rows = sum(registry$inference_method_id != "VB0_point_v"),
    completed_vb0 = sum(complete & registry$inference_method_id == "VB0_point_v"),
    completed_structured = sum(complete & registry$inference_method_id != "VB0_point_v"),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase166_finalize <- function(dirs = app_joint_exqdesn_phase164_dirs()) {
  app_ensure_dir(dirs$phase166)
  registry <- app_read_csv(file.path(dirs$phase164, "method_development_registry.csv"))
  health <- app_joint_exqdesn_phase166_health(dirs)
  if (health$remaining_rows[[1L]] > 0L) stop("Phase166 cannot finalize with incomplete rows.", call. = FALSE)
  load_table <- function(filename) app_joint_qdesn_bind_rows(lapply(registry$phase166_candidate_id, function(id) {
    app_read_csv(file.path(app_joint_exqdesn_phase166_candidate_dir(dirs$phase166, id), filename))
  }))
  summary <- load_table("candidate_summary.csv")
  tau_summary <- load_table("tau_summary.csv")
  interval_summary <- load_table("interval_summary.csv")
  diagnostics <- load_table("vb_diagnostics.csv")
  quadrature <- load_table("quadrature_summary.csv")
  scale_shape <- load_table("scale_shape_summary.csv")
  runtime <- load_table("runtime_summary.csv")
  keys <- c("base_scenario_id", "dgp_replicate_id", "fit_structure")
  baseline <- summary[summary$inference_method_id == "VB0_point_v", c(keys, "fit_truth_mae", "forecast_truth_mae", "fit_check_loss_mean", "forecast_check_loss_mean", "fit_crps_grid_mean", "forecast_crps_grid_mean"), drop = FALSE]
  names(baseline)[-(seq_along(keys))] <- paste0(names(baseline)[-(seq_along(keys))], "_vb0")
  paired <- merge(summary, baseline, by = keys, all.x = TRUE, sort = FALSE)
  for (metric in c("fit_truth_mae", "forecast_truth_mae", "fit_check_loss_mean", "forecast_check_loss_mean", "fit_crps_grid_mean", "forecast_crps_grid_mean")) {
    paired[[paste0(metric, "_delta_vs_vb0")]] <- paired[[metric]] - paired[[paste0(metric, "_vb0")]]
  }
  method_summary <- aggregate(
    cbind(fit_truth_mae, forecast_truth_mae, fit_check_loss_mean, forecast_check_loss_mean, fit_crps_grid_mean, forecast_crps_grid_mean, total_elapsed_seconds) ~ fit_structure + inference_method_id,
    data = summary,
    FUN = mean
  )
  gate_summary <- aggregate(
    list(rows = summary$gate_status),
    by = list(fit_structure = summary$fit_structure, inference_method_id = summary$inference_method_id, gate_status = summary$gate_status),
    FUN = length
  )
  hard_failures <- sum(summary$implementation_status == "fail")
  assessment <- data.frame(
    gate_status = if (hard_failures > 0L) "fail" else if (any(summary$gate_status == "review")) "review" else "pass",
    completed_rows = nrow(summary),
    expected_rows = 480L,
    implementation_failures = hard_failures,
    contract_crossing_pairs = sum(summary$fit_contract_crossing_pairs + summary$forecast_contract_crossing_pairs),
    review_rows = sum(summary$gate_status == "review"),
    recommendation = if (hard_failures > 0L) "repair_before_method_selection" else "audit_and_freeze_one_structured_method_per_structure",
    stringsAsFactors = FALSE
  )
  readme <- file.path(dirs$phase166, "README.md")
  writeLines(c(
    "# Phase166 Structured-VB Method Development",
    "",
    "Phase166 compares VB0, VB1, and VB2 on 80 full-size Phase153 method-development replicates for Joint and Independent exQDESN.",
    "The 160 VB0 rows are verified reuse; 320 rows are newly fitted under frozen case-specific specifications.",
    "No article promotion or fresh-confirmation claim is made at this stage."
  ), readme, useBytes = TRUE)
  outputs <- list(
    phase166_candidate_summary = summary,
    phase166_tau_summary = tau_summary,
    phase166_interval_summary = interval_summary,
    phase166_vb_diagnostics = diagnostics,
    phase166_quadrature_summary = quadrature,
    phase166_scale_shape_summary = scale_shape,
    phase166_runtime_summary = runtime,
    phase166_paired_vs_vb0 = paired,
    phase166_method_summary = method_summary,
    phase166_gate_summary = gate_summary,
    phase166_health_summary = health,
    phase166_assessment = assessment,
    provenance = app_joint_qvp_provenance_rows()
  )
  paths <- vapply(names(outputs), function(name) app_joint_qvp_write_csv(outputs[[name]], file.path(dirs$phase166, paste0(name, ".csv"))), character(1L))
  paths <- c(paths, README = normalizePath(readme, mustWork = TRUE))
  app_joint_exqdesn_write_manifest(paths, dirs$phase166)
  list(dirs = dirs, assessment = assessment, method_summary = method_summary)
}
