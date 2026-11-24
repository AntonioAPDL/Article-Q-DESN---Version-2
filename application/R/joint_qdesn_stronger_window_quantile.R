# Stronger-window independent-AL selection continuation.

app_joint_swq_controls <- function(base_contract) {
  list(
    tau = base_contract$tau,
    ridge_tau2 = base_contract$ridge_tau2,
    intercept_variance = base_contract$intercept_variance,
    sigma_shape = base_contract$sigma_shape,
    sigma_rate = base_contract$sigma_rate,
    gaussian_rhs_max_iter = base_contract$rhs_max_iter,
    gaussian_rhs_min_iter = base_contract$rhs_min_iter,
    gaussian_rhs_tolerance = base_contract$rhs_tolerance,
    median_max_iter = base_contract$median_max_iter,
    quantile_max_iter = base_contract$quantile_max_iter,
    vb_tolerance = base_contract$vb_tolerance,
    rhs_vb_inner = 10L,
    rhs_freeze_iters = 0L,
    rhs_slab_fixed = FALSE,
    rhs_slab_variance = NA_real_,
    a_sigma = 2,
    b_sigma = 1,
    alpha_prior_sd_multiplier = 4,
    alpha_min_spacing = 0,
    max_dense_dim = base_contract$ordinary_promotion_dimension,
    exal_vb_method = "VB1_structured_v",
    gamma_init_policy = "default"
  )
}

app_joint_swq_controls_frame <- function(controls) {
  data.frame(
    name = c("quantile_grid", "rhs_vb_inner", "rhs_freeze_iters", "rhs_slab_fixed",
      "a_sigma", "b_sigma", "alpha_prior_sd_multiplier", "alpha_min_spacing",
      "max_dense_dim", "exal_vb_method", "gamma_init_policy"),
    value = c(paste(controls$tau, collapse = ";"), controls$rhs_vb_inner,
      controls$rhs_freeze_iters, controls$rhs_slab_fixed, controls$a_sigma,
      controls$b_sigma, controls$alpha_prior_sd_multiplier,
      controls$alpha_min_spacing, controls$max_dense_dim,
      controls$exal_vb_method, controls$gamma_init_policy),
    stringsAsFactors = FALSE
  )
}

app_joint_swq_stage_spec <- function(stage) {
  switch(as.character(stage),
    m1 = c(plan = "median_al_worker_plan.csv", id = "median_worker_id"),
    t1 = c(plan = "tail_al_worker_plan.csv", id = "tail_worker_id"),
    q1 = c(plan = "seven_al_worker_plan.csv", id = "q1_worker_id"),
    stop("Unknown stronger-window quantile stage.", call. = FALSE)
  )
}

app_joint_swq_worker_dir <- function(root, stage, id) {
  file.path(root, paste0(stage, "_workers"), sprintf("worker_%05d", as.integer(id)))
}

app_joint_swq_health <- function(root, stage) {
  root <- normalizePath(root, mustWork = TRUE)
  spec <- app_joint_swq_stage_spec(stage)
  path <- file.path(root, spec[["plan"]])
  if (!file.exists(path)) return(data.frame(stage = stage, expected = 0L, completed = 0L,
    failed = 0L, remaining = 0L, completion_fraction = 0, status = "not_prepared"))
  plan <- app_read_csv(path)
  dirs <- vapply(plan[[spec[["id"]]]], function(id) app_joint_swq_worker_dir(root, stage, id), character(1L))
  done <- file.exists(file.path(dirs, "DONE")) & file.exists(file.path(dirs, "artifact_manifest.csv"))
  failed <- file.exists(file.path(dirs, "FAILED")) | file.exists(file.path(dirs, "failure.csv"))
  data.frame(stage = stage, expected = nrow(plan), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), completion_fraction = mean(done),
    status = if (any(failed)) "failed" else if (all(done)) "complete" else if (any(done)) "running" else "ready",
    stringsAsFactors = FALSE)
}

app_joint_swq_fit_normal_initializer <- function(design, candidate, base_contract, controls) {
  tr <- design$train_local
  backend <- if (ncol(design$X) >= length(tr)) "dual" else "primal"
  ridge <- app_joint_ridge_fit_dispatch(
    design$X[tr, , drop = FALSE], design$y[tr],
    ridge_tau2 = base_contract$ridge_tau2,
    intercept_var = base_contract$intercept_variance,
    sigma_a = base_contract$sigma_shape,
    sigma_b = base_contract$sigma_rate,
    backend = backend
  )
  warm <- app_joint_shared_ridge_warm_start(ridge, candidate, design)
  rhs <- app_glofas_normal_rhs_fit(
    design$X[tr, , drop = FALSE], design$y[tr], warm,
    tau0 = as.numeric(candidate$rhs_tau0[[1L]]),
    max_iter = base_contract$rhs_max_iter,
    min_iter = base_contract$rhs_min_iter,
    tol = base_contract$rhs_tolerance
  )
  p <- ncol(design$Z)
  slopes <- as.numeric(rhs$beta_mean[-1L])
  slope_cov <- as.matrix(rhs$beta_cov[-1L, -1L, drop = FALSE])
  residual_sd <- sqrt(as.numeric(rhs$sigma2_mean))
  alpha <- as.numeric(rhs$beta_mean[[1L]] + residual_sd * stats::qnorm(controls$tau))
  fit_location <- as.numeric(design$Z[tr, , drop = FALSE] %*% slopes)
  fit_q <- matrix(fit_location, nrow = length(tr), ncol = length(controls$tau)) +
    matrix(alpha, nrow = length(tr), ncol = length(controls$tau), byrow = TRUE)
  sigma <- vapply(seq_along(controls$tau), function(k) {
    max(mean(app_check_loss(design$y[tr], fit_q[, k], controls$tau[[k]])),
      residual_sd * 1e-4, 1e-8)
  }, numeric(1L))
  zeta2 <- app_joint_shared_quantile_resolve_zeta2(rhs, controls)
  rhs_state <- app_joint_qvp_initialize_rhs_state(1L, p,
    tau0 = rhs$rhs_tau0, zeta2 = zeta2, slab_fixed = controls$rhs_slab_fixed)
  rhs_state <- app_joint_qvp_update_rhs_vb_state(rhs_state, slopes, slope_cov,
    K = 1L, p = p, n_inner = controls$rhs_vb_inner)$state
  initializer <- list(
    beta_mean = slopes, beta_cov = slope_cov, alpha_mean = alpha,
    sigma_mean = sigma, rhs_anchor = rhs_state$anchor, tau = controls$tau,
    residual_sd = residual_sd, zeta2 = zeta2,
    alpha_prior_sd = controls$alpha_prior_sd_multiplier * residual_sd,
    source = "compact_full_grid_normal_rhs_vb"
  )
  list(
    rhs_tau0 = rhs$rhs_tau0,
    rhs_converged = rhs$converged,
    rhs_iterations = rhs$iterations,
    rhs_final_delta = rhs$final_delta,
    rhs_trace = rhs$trace,
    ridge_backend = backend,
    initializer = initializer
  )
}

app_joint_swq_single_init <- function(normal, tau, design) {
  k <- match(tau, normal$initializer$tau)
  if (is.na(k)) stop("Requested quantile is absent from the normal initializer.", call. = FALSE)
  list(
    beta_mean = normal$initializer$beta_mean,
    beta_cov = normal$initializer$beta_cov,
    alpha_mean = normal$initializer$alpha_mean[[k]],
    sigma_mean = normal$initializer$sigma_mean[[k]],
    rhs_state = list(anchor = normal$initializer$rhs_anchor),
    iterations_completed = 0L
  )
}

app_joint_swq_fit_al <- function(design, normal, controls, tau, init, max_iter) {
  k <- match(tau, normal$initializer$tau)
  if (is.na(k)) stop("AL target is outside the frozen grid.", call. = FALSE)
  app_joint_qvp_fit_al_vb_tiny(
    y = design$y[design$train_local],
    Z = design$Z[design$train_local, , drop = FALSE],
    tau = tau, max_iter = max_iter, tol = controls$vb_tolerance, kappa = 1,
    tau0 = normal$rhs_tau0, zeta2 = normal$initializer$zeta2,
    slab_fixed = controls$rhs_slab_fixed,
    a_sigma = controls$a_sigma, b_sigma = controls$b_sigma,
    alpha_prior_mean = normal$initializer$alpha_mean[[k]],
    alpha_prior_sd = normal$initializer$alpha_prior_sd,
    alpha_min_spacing = 0,
    max_dense_dim = controls$max_dense_dim,
    rhs_vb_inner = controls$rhs_vb_inner,
    rhs_freeze_iters = controls$rhs_freeze_iters,
    init = app_joint_shared_quantile_reset_init(init)
  )
}

app_joint_swq_predict_one <- function(fit, state) {
  as.numeric(fit$alpha_mean[[1L]] + crossprod(as.numeric(fit$beta_mean), as.numeric(state)))
}

app_joint_swq_recursive_quantile <- function(
  design, fixture, target_fit, median_fit, base_contract, origin_indices
) {
  blocks <- app_joint_sw_origin_rows(design, origin_indices, base_contract$calibration_max_lead)
  n <- sum(lengths(blocks))
  qhat <- median_qhat <- numeric(n)
  full_time <- origin <- horizon <- integer(n)
  score_local <- integer(n)
  recursive_state_count <- recursive_saturated_count <- 0L
  recursive_state_max_abs <- 0
  recursive_state_finite <- TRUE
  cursor <- 0L
  for (position in seq_along(blocks)) {
    block <- blocks[[position]]
    origin_local <- min(block) - 1L
    origin_full <- design$row_meta$full_time_index[[origin_local]]
    states <- lapply(design$teacher_forced_states, function(H) as.numeric(H[origin_local, ]))
    history <- fixture$y_history[seq_len(origin_full)]
    for (hh in seq_along(block)) {
      local_target <- block[[hh]]
      tt <- design$row_meta$full_time_index[[local_target]]
      raw <- app_joint_pure_known_feature_row(tt, history,
        response_lags = design$response_lags, sc = design$dgp_row)
      scaled <- app_joint_recursive_scale_row(raw, design$scale_params)
      states <- app_qdesn_continue_one_step(states, scaled, design$reservoir, design$reservoir_meta)
      state_values <- unlist(states, use.names = FALSE)
      recursive_state_count <- recursive_state_count + length(state_values)
      recursive_saturated_count <- recursive_saturated_count + sum(abs(state_values) > 0.99)
      recursive_state_finite <- recursive_state_finite && all(is.finite(state_values))
      if (length(state_values)) {
        recursive_state_max_abs <- if (all(is.finite(state_values))) {
          max(recursive_state_max_abs, max(abs(state_values)))
        } else {
          Inf
        }
      }
      state_raw <- app_qdesn_readout_row_from_states(states, design$reservoir)
      state <- (state_raw - design$state_center) / design$state_scale
      cursor <- cursor + 1L
      qhat[[cursor]] <- app_joint_swq_predict_one(target_fit, state)
      median_qhat[[cursor]] <- app_joint_swq_predict_one(median_fit, state)
      full_time[[cursor]] <- tt
      origin[[cursor]] <- origin_indices[[position]]
      horizon[[cursor]] <- hh
      score_local[[cursor]] <- local_target
      history[[tt]] <- median_qhat[[cursor]]
    }
  }
  if (cursor != n || any(!is.finite(c(qhat, median_qhat)))) {
    stop("Recursive quantile forecast is incomplete.", call. = FALSE)
  }
  recursive_state_saturation_fraction <- if (recursive_state_count) {
    recursive_saturated_count / recursive_state_count
  } else {
    NA_real_
  }
  list(qhat = qhat, median_qhat = median_qhat, score_local = score_local,
    full_time_index = full_time, origin_index = origin, horizon = horizon,
    recursive_state_saturation_fraction = recursive_state_saturation_fraction,
    recursive_state_max_abs = recursive_state_max_abs,
    recursive_state_finite = recursive_state_finite)
}

app_joint_swq_score_fit <- function(fixture, candidate, base_contract, origin_indices, stage, root) {
  controls <- app_joint_swq_controls(base_contract)
  design <- app_joint_pure_build_design(fixture, candidate, base_contract, selector = TRUE)
  started <- proc.time()[[3L]]
  if (stage == "m1") {
    normal <- app_joint_swq_fit_normal_initializer(design, candidate, base_contract, controls)
    init <- app_joint_swq_single_init(normal, 0.5, design)
    fit <- app_joint_swq_fit_al(design, normal, controls, 0.5, init, controls$median_max_iter)
    median_fit <- fit
    initialization_source <- "matched_normal_rhs_vb"
  } else if (stage == "t1") {
    source_dir <- app_joint_swq_worker_dir(root, "m1", candidate$m1_worker_id[[1L]])
    normal <- readRDS(file.path(source_dir, "normal_initializer.rds"))
    median_fit <- readRDS(file.path(source_dir, "fit_initializer.rds"))
    tau <- as.numeric(candidate$tau[[1L]])
    init <- median_fit
    k <- match(tau, normal$initializer$tau)
    if (is.na(k) || !tau %in% c(0.05, 0.95)) {
      stop("Tail sentinel requires tau 0.05 or 0.95 from the normal initializer.", call. = FALSE)
    }
    init$alpha_mean <- normal$initializer$alpha_mean[[k]]
    init$sigma_mean <- max(median_fit$sigma_mean[[1L]], normal$initializer$sigma_mean[[k]])
    fit <- app_joint_swq_fit_al(design, normal, controls, tau, init, controls$quantile_max_iter)
    initialization_source <- "verified_matched_median_and_normal_initializer"
  } else {
    source_dir <- app_joint_swq_worker_dir(root, "m1", candidate$m1_worker_id[[1L]])
    normal <- readRDS(file.path(source_dir, "normal_initializer.rds"))
    median_fit <- readRDS(file.path(source_dir, "fit_initializer.rds"))
    tau <- as.numeric(candidate$tau[[1L]])
    if (abs(tau - 0.5) < 1e-12) {
      fit <- median_fit
      initialization_source <- "verified_m1_median_import"
    } else {
      parent_dir <- app_joint_swq_worker_dir(root, "q1", candidate$parent_worker_id[[1L]])
      parent <- readRDS(file.path(parent_dir, "fit_initializer.rds"))
      init <- parent
      k <- match(tau, normal$initializer$tau)
      init$alpha_mean <- normal$initializer$alpha_mean[[k]]
      init$sigma_mean <- max(parent$sigma_mean[[1L]], normal$initializer$sigma_mean[[k]])
      fit <- app_joint_swq_fit_al(design, normal, controls, tau, init, controls$quantile_max_iter)
      initialization_source <- sprintf("nested_al_parent_tau_%0.2f", candidate$parent_tau[[1L]])
    }
  }
  tau <- if (stage == "m1") 0.5 else as.numeric(candidate$tau[[1L]])
  pred <- app_joint_swq_recursive_quantile(
    design, fixture, fit, median_fit, base_contract, origin_indices)
  y <- design$y[pred$score_local]
  truth_index <- match(tau, design$tau)
  check <- app_check_loss(y, pred$qhat, tau)
  oracle <- pred$qhat - design$true_q[pred$score_local, truth_index]
  compact <- app_joint_shared_quantile_compact_fit(fit)
  identity <- candidate
  identity$tau <- tau
  summary <- cbind(identity, data.frame(
    status = "completed", method = "independent_al_rhs_vb",
    initialization_source = initialization_source,
    n_train = length(design$train_local), n_calibration_scored = length(y),
    protected_rows_loaded = design$diagnostic$protected_rows_loaded,
    calibration_median_quantile_score_mean = if (abs(tau - 0.5) < 1e-12) mean(2 * check) else NA_real_,
    calibration_check_loss_mean = mean(check),
    calibration_check_loss_sd = stats::sd(check),
    calibration_oracle_quantile_mae = mean(abs(oracle)),
    calibration_oracle_quantile_rmse = sqrt(mean(oracle^2)),
    recursive_state_saturation_fraction = pred$recursive_state_saturation_fraction,
    recursive_state_max_abs = pred$recursive_state_max_abs,
    recursive_state_finite = pred$recursive_state_finite,
    converged = isTRUE(fit$converged),
    convergence_status = if (isTRUE(fit$converged)) "pass" else "review_max_iter",
    iterations = as.integer(fit$iterations_completed %||% fit$iterations %||% NA_integer_),
    runtime_seconds = proc.time()[[3L]] - started,
    peak_rss_kib = app_joint_sw_vm_hwm_kib(),
    stringsAsFactors = FALSE
  ))
  detail <- data.frame(
    full_time_index = pred$full_time_index, origin_index = pred$origin_index,
    horizon = pred$horizon, tau = tau, y = y, qhat = pred$qhat,
    median_feedback = pred$median_qhat,
    true_quantile = design$true_q[pred$score_local, truth_index],
    check_loss = check, stringsAsFactors = FALSE
  )
  list(summary = summary, detail = detail,
    trace = app_joint_shared_quantile_trace_frame(fit), fit = compact,
    normal_initializer = if (stage == "m1") normal else NULL)
}

app_joint_swq_run_worker <- function(root, stage, worker_id) {
  root <- normalizePath(root, mustWork = TRUE)
  spec <- app_joint_swq_stage_spec(stage)
  plan <- app_read_csv(file.path(root, spec[["plan"]]))
  row <- plan[plan[[spec[["id"]]]] == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("Quantile worker ID is not unique.", call. = FALSE)
  out <- app_joint_swq_worker_dir(root, stage, worker_id)
  if (file.exists(file.path(out, "DONE")) && file.exists(file.path(out, "artifact_manifest.csv"))) {
    return(invisible(out))
  }
  tmp <- paste0(out, ".tmp_", Sys.getpid())
  unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  base_contract <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  fixture <- readRDS(row$fixture_path[[1L]])
  origins <- as.integer(strsplit(row$origin_indices[[1L]], ";", fixed = TRUE)[[1L]])
  started <- Sys.time()
  captured <- tryCatch(app_joint_sw_capture_warnings(function() {
    app_joint_swq_score_fit(fixture, row, base_contract, origins, stage, root)
  }), error = function(e) e)
  if (inherits(captured, "error")) {
    app_ensure_dir(out)
    app_write_csv(cbind(row, data.frame(status = "failed",
      error_message = conditionMessage(captured),
      runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      stringsAsFactors = FALSE)), file.path(out, "failure.csv"))
    writeLines("failed", file.path(out, "FAILED"))
    unlink(tmp, recursive = TRUE, force = TRUE)
    stop(conditionMessage(captured), call. = FALSE)
  }
  result <- captured$value
  result$summary$warning_count <- length(captured$warnings)
  result$summary$warning_messages <- paste(captured$warnings, collapse = " | ")
  files <- c(
    summary = app_write_csv(result$summary, file.path(tmp, "summary.csv")),
    detail = app_write_csv(result$detail, file.path(tmp, "calibration_detail.csv"))
  )
  fit_path <- file.path(tmp, "fit_initializer.rds")
  saveRDS(result$fit, fit_path, version = 3L, compress = "xz")
  files <- c(files, fit_initializer = fit_path)
  if (!is.null(result$normal_initializer)) {
    normal_path <- file.path(tmp, "normal_initializer.rds")
    saveRDS(result$normal_initializer, normal_path, version = 3L, compress = "xz")
    files <- c(files, normal_initializer = normal_path)
  }
  if (!is.null(result$trace) && nrow(result$trace)) {
    files <- c(files, vb_trace = app_write_csv(result$trace, file.path(tmp, "vb_trace.csv")))
  }
  if (length(captured$warnings)) {
    files <- c(files, warnings = app_write_csv(data.frame(
      warning_index = seq_along(captured$warnings), warning_message = captured$warnings,
      stringsAsFactors = FALSE), file.path(tmp, "warnings.csv")))
  }
  app_joint_shared_write_manifest(tmp, files)
  verified <- app_joint_shared_verify_manifest(tmp, file.path(tmp, "artifact_manifest.csv"))
  if (!all(verified$verified)) stop("Quantile worker manifest failed verification.", call. = FALSE)
  writeLines("completed", file.path(tmp, "DONE"))
  if (dir.exists(out)) unlink(out, recursive = TRUE, force = TRUE)
  if (!file.rename(tmp, out)) stop("Could not atomically publish quantile worker.", call. = FALSE)
  invisible(out)
}

app_joint_swq_collect <- function(root, stage) {
  health <- app_joint_swq_health(root, stage)
  if (health$failed[[1L]] != 0L || health$completed[[1L]] != health$expected[[1L]]) {
    stop("Quantile stage is not complete and failure-free.", call. = FALSE)
  }
  files <- list.files(file.path(root, paste0(stage, "_workers")), pattern = "^summary[.]csv$",
    recursive = TRUE, full.names = TRUE)
  out <- app_bind_rows_fill(lapply(files, app_read_csv))
  if (nrow(out) != health$expected[[1L]] || any(out$status != "completed") ||
      any(!is.finite(out$calibration_check_loss_mean))) {
    stop("Quantile summary collection failed its finite/cardinality gate.", call. = FALSE)
  }
  out
}

app_joint_swq_continuation_order <- function() {
  data.frame(
    tau = c(0.50, 0.25, 0.75, 0.10, 0.90, 0.05, 0.95),
    parent_tau = c(NA, 0.50, 0.50, 0.25, 0.75, 0.10, 0.90),
    continuation_stage = c(1L, 2L, 2L, 3L, 3L, 4L, 4L),
    stringsAsFactors = FALSE
  )
}

app_joint_swq_key <- function(scenario, candidate, tau0, replicate, tau = NULL) {
  base <- paste(scenario, candidate, format(tau0, digits = 17L, scientific = TRUE), replicate, sep = "::")
  if (is.null(tau)) base else paste(base, format(tau, digits = 17L, scientific = TRUE), sep = "::")
}

app_joint_swq_select_joint_eligible_specs <- function(aggregate, base_contract) {
  aggregate$joint_dense_dimension <- length(base_contract$tau) *
    as.integer(aggregate$retained_state_budget)
  aggregate$joint_backend_eligible <- aggregate$joint_dense_dimension <=
    as.integer(base_contract$ordinary_promotion_dimension)
  selected <- app_bind_rows_fill(lapply(split(aggregate, aggregate$scenario_id), function(x) {
    eligible <- x[app_as_bool_vec(x$joint_backend_eligible), , drop = FALSE]
    parity <- eligible[grepl("anchor_authoritative_v2", eligible$candidate_role), , drop = FALSE]
    if (!nrow(eligible) || !nrow(parity)) {
      stop("Seven-grid selection lacks a joint-backend-eligible candidate or parity anchor.", call. = FALSE)
    }
    eligible <- eligible[order(eligible$calibration_acrps_mean,
      eligible$calibration_acrps_worst, eligible$calibration_acrps_sd,
      eligible$retained_state_budget, eligible$candidate_id), , drop = FALSE]
    challenger <- eligible[1L, , drop = FALSE]
    parity <- parity[which.min(parity$calibration_acrps_mean), , drop = FALSE]
    challenger$specification_role <- "challenger"
    parity$specification_role <- "new_geometry_parity"
    out <- app_bind_rows_fill(list(challenger, parity))
    out[!duplicated(paste(out$scenario_id, out$candidate_id, out$rhs_tau0)), , drop = FALSE]
  }))
  list(aggregate = aggregate, selected = selected)
}

app_joint_swq_finalize_m1 <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  base_contract <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  scores <- app_joint_swq_collect(root, "m1")
  proxy <- scores
  proxy$calibration_acrps_mean <- proxy$calibration_median_quantile_score_mean
  aggregate <- app_joint_sw_attach_candidate_metadata(root,
    app_joint_sw_aggregate_scores(proxy, c("scenario_id", "candidate_id", "rhs_tau0")))
  names(aggregate)[names(aggregate) == "calibration_acrps_mean"] <- "median_quantile_score_mean"
  names(aggregate)[names(aggregate) == "calibration_acrps_worst"] <- "median_quantile_score_worst"
  names(aggregate)[names(aggregate) == "calibration_acrps_sd"] <- "median_quantile_score_sd"
  selected <- app_bind_rows_fill(lapply(split(aggregate, aggregate$scenario_id), function(x) {
    y <- x
    y$calibration_acrps_mean <- y$median_quantile_score_mean
    y$calibration_acrps_worst <- y$median_quantile_score_worst
    y$calibration_acrps_sd <- y$median_quantile_score_sd
    app_joint_sw_select_parity_pair(y, base_contract$seven_grid_advance_count)
  }))
  fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))[, c(
    "scenario_id", "replicate_id", "dgp_seed", "fixture_path"), drop = FALSE]
  selected_base <- selected[, intersect(names(selected), names(app_read_csv(file.path(root,
    "median_al_worker_plan.csv")))), drop = FALSE]
  selected_base <- selected_base[!duplicated(app_joint_swq_key(selected_base$scenario_id,
    selected_base$candidate_id, selected_base$rhs_tau0, rep(1L, nrow(selected_base)))), , drop = FALSE]
  base <- merge(selected_base, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
  order <- app_joint_swq_continuation_order()
  plan <- merge(base, order, by = NULL)
  plan <- plan[order(plan$continuation_stage, plan$scenario_id, plan$candidate_id,
    plan$replicate_id, plan$tau), , drop = FALSE]
  plan$q1_worker_id <- seq_len(nrow(plan))
  m1_plan <- app_read_csv(file.path(root, "median_al_worker_plan.csv"))
  m1_key <- app_joint_swq_key(m1_plan$scenario_id, m1_plan$candidate_id,
    m1_plan$rhs_tau0, m1_plan$replicate_id)
  plan$m1_worker_id <- m1_plan$median_worker_id[match(app_joint_swq_key(plan$scenario_id,
    plan$candidate_id, plan$rhs_tau0, plan$replicate_id), m1_key)]
  qkey <- app_joint_swq_key(plan$scenario_id, plan$candidate_id, plan$rhs_tau0,
    plan$replicate_id, plan$tau)
  plan$parent_worker_id <- NA_integer_
  parent <- is.finite(plan$parent_tau)
  plan$parent_worker_id[parent] <- plan$q1_worker_id[match(app_joint_swq_key(
    plan$scenario_id[parent], plan$candidate_id[parent], plan$rhs_tau0[parent],
    plan$replicate_id[parent], plan$parent_tau[parent]), qkey)]
  plan$origin_indices <- paste(base_contract$full_origins, collapse = ";")
  if (nrow(selected) != base_contract$scenario_count * base_contract$seven_grid_advance_count ||
      nrow(plan) != base_contract$scenario_count * base_contract$seven_grid_advance_count *
        base_contract$calibration_replicates * length(base_contract$tau) ||
      anyNA(plan$m1_worker_id) || anyNA(plan$parent_worker_id[parent])) {
    stop("Median-to-seven-grid plan violates its frozen cardinality/dependency contract.", call. = FALSE)
  }
  files <- c(
    scores = app_write_csv(scores, file.path(root, "median_al_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "median_al_aggregate.csv")),
    selected = app_write_csv(selected, file.path(root, "median_al_selected_top8_by_scenario.csv")),
    q1_plan = app_write_csv(plan, file.path(root, "seven_al_worker_plan.csv")),
    controls = app_write_csv(app_joint_swq_controls_frame(app_joint_swq_controls(base_contract)),
      file.path(root, "quantile_continuation_controls.csv"))
  )
  app_ensure_dir(file.path(root, "q1_workers"))
  decision <- data.frame(status = "MEDIAN_AL_COMPLETE_READY_FOR_SEVEN_AL_REVIEW",
    selected_pairs = nrow(selected), q1_workers = nrow(plan), q1_launched = FALSE,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  files <- c(files, decision = app_write_csv(decision, file.path(root, "median_al_decision.csv")),
    app_joint_sw_stage_receipts(root, "m1"))
  app_joint_shared_write_manifest(root, files, filename = "median_al_manifest.csv")
  decision
}

app_joint_swq_finalize_q1 <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  base_contract <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  scores <- app_joint_swq_collect(root, "q1")
  plan <- app_read_csv(file.path(root, "seven_al_worker_plan.csv"))
  group_key <- app_joint_swq_key(plan$scenario_id, plan$candidate_id, plan$rhs_tau0, plan$replicate_id)
  rows <- lapply(split(seq_len(nrow(plan)), group_key), function(index) {
    block <- plan[index, , drop = FALSE]
    block <- block[order(block$tau), , drop = FALSE]
    details <- lapply(block$q1_worker_id, function(id) app_read_csv(file.path(
      app_joint_swq_worker_dir(root, "q1", id), "calibration_detail.csv")))
    reference <- details[[1L]]
    if (length(details) != length(base_contract$tau) ||
        !identical(as.numeric(block$tau), as.numeric(base_contract$tau)) ||
        any(vapply(details, function(x) !identical(x$full_time_index,
          reference$full_time_index), logical(1L)))) {
      stop("Seven-grid recursive prediction rows do not align.", call. = FALSE)
    }
    qhat <- do.call(cbind, lapply(details, `[[`, "qhat"))
    truth <- do.call(cbind, lapply(details, `[[`, "true_quantile"))
    realized <- app_joint_shared_acrps(reference$y, qhat, base_contract$tau)
    crossing <- app_joint_qdesn_apply_monotone_contract(qhat, base_contract$tau)
    data.frame(scenario_id = block$scenario_id[[1L]], candidate_id = block$candidate_id[[1L]],
      rhs_tau0 = block$rhs_tau0[[1L]], replicate_id = block$replicate_id[[1L]],
      calibration_acrps_mean = mean(realized), calibration_acrps_sd = stats::sd(realized),
      calibration_oracle_quantile_mae = mean(abs(qhat - truth)),
      calibration_oracle_quantile_rmse = sqrt(mean((qhat - truth)^2)),
      raw_crossing_pairs = sum(crossing$raw_crossing$n_crossing_pairs),
      contract_crossing_pairs = sum(crossing$contract_crossing$n_crossing_pairs),
      protected_rows_loaded = 0L, stringsAsFactors = FALSE)
  })
  replicate_scores <- app_bind_rows_fill(rows)
  aggregate <- app_joint_sw_attach_candidate_metadata(root,
    app_joint_sw_aggregate_scores(transform(replicate_scores,
      status = "completed", runtime_seconds = 0, peak_rss_kib = 0),
      c("scenario_id", "candidate_id", "rhs_tau0")))
  selection <- app_joint_swq_select_joint_eligible_specs(aggregate, base_contract)
  aggregate <- selection$aggregate
  selected <- selection$selected
  if (nrow(replicate_scores) != base_contract$scenario_count *
      base_contract$seven_grid_advance_count * base_contract$calibration_replicates ||
      any(replicate_scores$contract_crossing_pairs != 0L) ||
      any(!is.finite(replicate_scores$calibration_acrps_mean))) {
    stop("Seven-grid AL closeout failed cardinality, finiteness, or contract crossings.", call. = FALSE)
  }
  files <- c(
    worker_summary = app_write_csv(scores, file.path(root, "seven_al_worker_summary.csv")),
    replicate_scores = app_write_csv(replicate_scores, file.path(root, "seven_al_score_by_replicate.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "seven_al_aggregate.csv")),
    frozen_specs = app_write_csv(selected, file.path(root, "frozen_challenger_parity_specifications.csv"))
  )
  decision <- data.frame(status = "SEVEN_AL_COMPLETE_READY_FOR_EXAL_JOINT_IMPLEMENTATION_REVIEW",
    candidate_pairs = nrow(aggregate), frozen_specifications = nrow(selected),
    downstream_launched = FALSE, protected_rows_used = 0L, stringsAsFactors = FALSE)
  files <- c(files, decision = app_write_csv(decision, file.path(root, "seven_al_decision.csv")),
    app_joint_sw_stage_receipts(root, "q1"))
  app_joint_shared_write_manifest(root, files, filename = "seven_al_manifest.csv")
  decision
}

app_joint_swq_finalize <- function(root, stage) {
  switch(as.character(stage),
    m1 = app_joint_swq_finalize_m1(root),
    q1 = app_joint_swq_finalize_q1(root),
    stop("Unknown stronger-window quantile finalization stage.", call. = FALSE)
  )
}
