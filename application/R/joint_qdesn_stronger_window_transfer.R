# Stronger-window exAL and joint-VB transfer audit.

app_joint_swtx_worker_dir <- function(root, worker_id) {
  file.path(root, "transfer_workers", sprintf("worker_%05d", as.integer(worker_id)))
}

app_joint_swtx_parse_ids <- function(x) {
  as.integer(strsplit(as.character(x), ";", fixed = TRUE)[[1L]])
}

app_joint_swtx_prepare <- function(root = app_joint_sw_default_root()) {
  root <- normalizePath(root, mustWork = TRUE)
  q1_manifest <- app_joint_shared_verify_manifest(root, file.path(root, "seven_al_manifest.csv"))
  if (!all(q1_manifest$verified)) stop("Seven-grid AL manifest is not verified.", call. = FALSE)
  contract <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  specs <- app_read_csv(file.path(root, "frozen_challenger_parity_specifications.csv"))
  fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))[, c(
    "scenario_id", "replicate_id", "dgp_seed", "fixture_path"), drop = FALSE]
  q1 <- app_read_csv(file.path(root, "seven_al_worker_plan.csv"))
  if (nrow(specs) != 2L * contract$scenario_count ||
      any(!app_as_bool_vec(specs$joint_backend_eligible)) ||
      any(specs$joint_dense_dimension > contract$ordinary_promotion_dimension)) {
    stop("Frozen transfer specifications violate their joint-backend gate.", call. = FALSE)
  }
  base <- merge(specs, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
  rows <- lapply(seq_len(nrow(base)), function(ii) {
    one <- base[ii, , drop = FALSE]
    block <- q1[q1$scenario_id == one$scenario_id &
      q1$candidate_id == one$candidate_id &
      abs(q1$rhs_tau0 - one$rhs_tau0) < 1e-14 &
      q1$replicate_id == one$replicate_id, , drop = FALSE]
    block <- block[order(block$tau), , drop = FALSE]
    if (nrow(block) != length(contract$tau) ||
        !identical(as.numeric(block$tau), as.numeric(contract$tau)) ||
        any(!file.exists(file.path(app_joint_swq_worker_dir(root, "q1", block$q1_worker_id), "DONE")))) {
      stop("Frozen specification lacks a complete seven-AL source block.", call. = FALSE)
    }
    common <- one
    common$q1_al_worker_ids <- paste(block$q1_worker_id, collapse = ";")
    common$m1_worker_id <- unique(block$m1_worker_id)
    independent <- common[rep(1L, length(contract$tau)), , drop = FALSE]
    independent$model_id <- "independent_exqdesn_rhs"
    independent$tau <- contract$tau
    independent$source_al_worker_id <- block$q1_worker_id
    independent$transfer_stage <- 1L
    joint_al <- common
    joint_al$model_id <- "joint_qdesn_rhs"
    joint_al$tau <- NA_real_
    joint_al$source_al_worker_id <- NA_integer_
    joint_al$transfer_stage <- 2L
    joint_exal <- common
    joint_exal$model_id <- "joint_exqdesn_rhs"
    joint_exal$tau <- NA_real_
    joint_exal$source_al_worker_id <- NA_integer_
    joint_exal$transfer_stage <- 3L
    app_bind_rows_fill(list(independent, joint_al, joint_exal))
  })
  plan <- app_bind_rows_fill(rows)
  plan <- plan[order(plan$transfer_stage, plan$scenario_id, plan$specification_role,
    plan$replicate_id, plan$tau), , drop = FALSE]
  plan$transfer_worker_id <- seq_len(nrow(plan))
  key <- paste(plan$scenario_id, plan$candidate_id,
    format(plan$rhs_tau0, digits = 17L, scientific = TRUE), plan$replicate_id, sep = "::")
  plan$joint_al_worker_id <- NA_integer_
  plan$independent_exal_worker_ids <- NA_character_
  for (group in unique(key)) {
    index <- which(key == group)
    joint_id <- plan$transfer_worker_id[index[plan$model_id[index] == "joint_qdesn_rhs"]]
    exal_ids <- plan$transfer_worker_id[index[plan$model_id[index] == "independent_exqdesn_rhs"]]
    plan$joint_al_worker_id[index] <- joint_id
    plan$independent_exal_worker_ids[index] <- paste(exal_ids, collapse = ";")
  }
  expected <- nrow(specs) * contract$calibration_replicates * (length(contract$tau) + 2L)
  if (nrow(plan) != expected || anyNA(plan$m1_worker_id) ||
      anyNA(plan$joint_al_worker_id) || anyNA(plan$independent_exal_worker_ids)) {
    stop("Transfer plan violates its frozen cardinality/dependency contract.", call. = FALSE)
  }
  plan_path <- app_write_csv(plan, file.path(root, "transfer_worker_plan.csv"))
  controls_path <- app_write_csv(app_joint_swq_controls_frame(app_joint_swq_controls(contract)),
    file.path(root, "transfer_controls.csv"))
  decision <- data.frame(status = "TRANSFER_PLAN_READY_FOR_SENTINEL_REVIEW",
    expected_workers = nrow(plan), frozen_specifications = nrow(specs),
    protected_rows_used = 0L, launched = FALSE, stringsAsFactors = FALSE)
  decision_path <- app_write_csv(decision, file.path(root, "transfer_prepare_decision.csv"))
  app_ensure_dir(file.path(root, "transfer_workers"))
  app_joint_shared_write_manifest(root, c(plan = plan_path, controls = controls_path,
    frozen_specs = file.path(root, "frozen_challenger_parity_specifications.csv"),
    q1_manifest = file.path(root, "seven_al_manifest.csv"), decision = decision_path),
    filename = "transfer_prepare_manifest.csv")
  decision
}

app_joint_swtx_health <- function(root) {
  plan_path <- file.path(root, "transfer_worker_plan.csv")
  if (!file.exists(plan_path)) return(data.frame(expected = 0L, completed = 0L,
    failed = 0L, remaining = 0L, status = "not_prepared"))
  plan <- app_read_csv(plan_path)
  dirs <- vapply(plan$transfer_worker_id, function(id) app_joint_swtx_worker_dir(root, id), character(1L))
  done <- file.exists(file.path(dirs, "DONE")) & file.exists(file.path(dirs, "artifact_manifest.csv"))
  failed <- file.exists(file.path(dirs, "FAILED")) | file.exists(file.path(dirs, "failure.csv"))
  data.frame(expected = nrow(plan), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), status = if (any(failed)) "failed" else if (all(done))
      "complete" else if (any(done)) "running" else "ready", stringsAsFactors = FALSE)
}

app_joint_swtx_load_q1_fits <- function(root, row) {
  ids <- app_joint_swtx_parse_ids(row$q1_al_worker_ids[[1L]])
  fits <- lapply(ids, function(id) readRDS(file.path(
    app_joint_swq_worker_dir(root, "q1", id), "fit_initializer.rds")))
  names(fits) <- format(app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))$tau,
    trim = TRUE)
  fits
}

app_joint_swtx_stack <- function(fits, normal, design, controls, rhs_state = NULL) {
  K <- length(fits); p <- ncol(design$Z)
  beta <- unlist(lapply(fits, `[[`, "beta_mean"), use.names = FALSE)
  covariance <- as.matrix(Matrix::bdiag(lapply(fits, function(x) as.matrix(x$beta_cov))))
  if (is.null(rhs_state)) {
    rhs_state <- app_joint_qvp_initialize_rhs_state(K, p, tau0 = normal$rhs_tau0,
      zeta2 = normal$initializer$zeta2, slab_fixed = controls$rhs_slab_fixed)
    rhs_state <- app_joint_qvp_update_rhs_vb_state(rhs_state, beta, covariance,
      K, p, n_inner = controls$rhs_vb_inner)$state
  }
  out <- list(beta_mean = beta, beta_cov = covariance,
    alpha_mean = vapply(fits, function(x) x$alpha_mean[[1L]], numeric(1L)),
    sigma_mean = vapply(fits, function(x) x$sigma_mean[[1L]], numeric(1L)),
    tau = design$tau, rhs_state = rhs_state, iterations_completed = 0L)
  if (all(vapply(fits, function(x) length(x$gamma_mean %||% numeric()) == 1L, logical(1L)))) {
    out$gamma_mean <- vapply(fits, function(x) x$gamma_mean[[1L]], numeric(1L))
  }
  out
}

app_joint_swtx_fit <- function(root, row) {
  contract <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  controls <- app_joint_swq_controls(contract)
  fixture <- readRDS(row$fixture_path[[1L]])
  design <- app_joint_pure_build_design(fixture, row, contract, selector = TRUE)
  normal <- readRDS(file.path(app_joint_swq_worker_dir(root, "m1", row$m1_worker_id[[1L]]),
    "normal_initializer.rds"))
  model <- row$model_id[[1L]]
  if (model == "independent_exqdesn_rhs") {
    al <- readRDS(file.path(app_joint_swq_worker_dir(root, "q1", row$source_al_worker_id[[1L]]),
      "fit_initializer.rds"))
    k <- match(row$tau[[1L]], design$tau)
    fit <- app_joint_exqdesn_fit_vb_dispatch(
      method_id = controls$exal_vb_method,
      y = design$y[design$train_local], Z = design$Z[design$train_local, , drop = FALSE],
      tau = row$tau[[1L]], max_iter = controls$quantile_max_iter,
      tol = controls$vb_tolerance, kappa = 1, tau0 = normal$rhs_tau0,
      zeta2 = normal$initializer$zeta2, slab_fixed = controls$rhs_slab_fixed,
      a_sigma = controls$a_sigma, b_sigma = controls$b_sigma,
      alpha_prior_mean = normal$initializer$alpha_mean[[k]],
      alpha_prior_sd = normal$initializer$alpha_prior_sd, alpha_min_spacing = 0,
      gamma_init = app_joint_qdesn_gamma_init_for_policy(row$tau[[1L]],
        list(gamma_init_policy = controls$gamma_init_policy)),
      max_dense_dim = controls$max_dense_dim, rhs_vb_inner = controls$rhs_vb_inner,
      rhs_freeze_iters = controls$rhs_freeze_iters, diagnostic_stride = 20L,
      quadrature_nodes = c(4L, 8L, 12L), quadrature_tolerance = 1e-5,
      init = app_joint_shared_quantile_reset_init(al))
  } else if (model == "joint_qdesn_rhs") {
    init <- app_joint_swtx_stack(app_joint_swtx_load_q1_fits(root, row), normal,
      design, controls)
    fit <- app_joint_qvp_fit_al_vb_tiny(
      y = design$y[design$train_local], Z = design$Z[design$train_local, , drop = FALSE],
      tau = design$tau, max_iter = controls$quantile_max_iter,
      tol = controls$vb_tolerance, kappa = 1, tau0 = normal$rhs_tau0,
      zeta2 = normal$initializer$zeta2, slab_fixed = controls$rhs_slab_fixed,
      a_sigma = controls$a_sigma, b_sigma = controls$b_sigma,
      alpha_prior_mean = normal$initializer$alpha_mean,
      alpha_prior_sd = normal$initializer$alpha_prior_sd,
      alpha_min_spacing = controls$alpha_min_spacing,
      max_dense_dim = controls$max_dense_dim, rhs_vb_inner = controls$rhs_vb_inner,
      rhs_freeze_iters = controls$rhs_freeze_iters, init = init)
  } else if (model == "joint_exqdesn_rhs") {
    joint_al <- readRDS(file.path(app_joint_swtx_worker_dir(root, row$joint_al_worker_id[[1L]]),
      "fit_initializer.rds"))
    exal_ids <- app_joint_swtx_parse_ids(row$independent_exal_worker_ids[[1L]])
    exal <- lapply(exal_ids, function(id) readRDS(file.path(app_joint_swtx_worker_dir(root, id),
      "fit_initializer.rds")))
    init <- app_joint_swtx_stack(exal, normal, design, controls, rhs_state = joint_al$rhs_state)
    fit <- app_joint_exqdesn_fit_vb_dispatch(
      method_id = controls$exal_vb_method,
      y = design$y[design$train_local], Z = design$Z[design$train_local, , drop = FALSE],
      tau = design$tau, max_iter = controls$quantile_max_iter,
      tol = controls$vb_tolerance, kappa = 1, tau0 = normal$rhs_tau0,
      zeta2 = normal$initializer$zeta2, slab_fixed = controls$rhs_slab_fixed,
      a_sigma = controls$a_sigma, b_sigma = controls$b_sigma,
      alpha_prior_mean = normal$initializer$alpha_mean,
      alpha_prior_sd = normal$initializer$alpha_prior_sd,
      alpha_min_spacing = controls$alpha_min_spacing,
      gamma_init = app_joint_qdesn_gamma_init_for_policy(design$tau,
        list(gamma_init_policy = controls$gamma_init_policy)),
      max_dense_dim = controls$max_dense_dim, rhs_vb_inner = controls$rhs_vb_inner,
      rhs_freeze_iters = controls$rhs_freeze_iters, diagnostic_stride = 20L,
      quadrature_nodes = c(4L, 8L, 12L), quadrature_tolerance = 1e-5, init = init)
  } else stop("Unknown stronger-window transfer model.", call. = FALSE)
  list(fit = fit, design = design)
}

app_joint_swtx_run_worker <- function(root, worker_id) {
  root <- normalizePath(root, mustWork = TRUE)
  plan <- app_read_csv(file.path(root, "transfer_worker_plan.csv"))
  row <- plan[plan$transfer_worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("Transfer worker ID is not unique.", call. = FALSE)
  out <- app_joint_swtx_worker_dir(root, worker_id)
  if (file.exists(file.path(out, "DONE")) && file.exists(file.path(out, "artifact_manifest.csv"))) {
    return(invisible(out))
  }
  tmp <- paste0(out, ".tmp_", Sys.getpid()); unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp); started <- Sys.time()
  captured <- tryCatch(app_joint_sw_capture_warnings(function() app_joint_swtx_fit(root, row)),
    error = function(e) e)
  if (inherits(captured, "error")) {
    app_ensure_dir(out)
    app_write_csv(cbind(row, data.frame(status = "failed",
      error_message = conditionMessage(captured),
      runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")))),
      file.path(out, "failure.csv"))
    writeLines("failed", file.path(out, "FAILED")); unlink(tmp, recursive = TRUE, force = TRUE)
    stop(conditionMessage(captured), call. = FALSE)
  }
  fit <- captured$value$fit
  compact <- app_joint_shared_quantile_compact_fit(fit)
  finite <- all(is.finite(c(compact$beta_mean, compact$alpha_mean, compact$sigma_mean,
    compact$gamma_mean %||% numeric()))) && all(compact$sigma_mean > 0)
  if (!finite) stop("Transfer worker produced a nonfinite fit.", call. = FALSE)
  summary <- row[, c("transfer_worker_id", "transfer_stage", "scenario_id",
    "specification_role", "candidate_id", "rhs_tau0", "replicate_id", "model_id", "tau")]
  summary$status <- "completed"; summary$finite_output <- TRUE
  summary$converged <- isTRUE(compact$converged %||% fit$converged)
  summary$convergence_status <- if (summary$converged) "pass" else "review_max_iter"
  summary$iterations <- as.integer(compact$iterations_completed %||% fit$iterations %||% NA_integer_)
  summary$runtime_seconds <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  summary$peak_rss_kib <- app_joint_sw_vm_hwm_kib()
  summary$warning_count <- length(captured$warnings)
  summary$warning_messages <- paste(captured$warnings, collapse = " | ")
  summary$protected_rows_loaded <- captured$value$design$diagnostic$protected_rows_loaded
  files <- c(summary = app_write_csv(summary, file.path(tmp, "summary.csv")))
  fit_path <- file.path(tmp, "fit_initializer.rds")
  saveRDS(compact, fit_path, version = 3L, compress = "xz")
  files <- c(files, fit_initializer = fit_path)
  trace <- app_joint_shared_quantile_trace_frame(fit)
  if (nrow(trace)) files <- c(files, vb_trace = app_write_csv(trace, file.path(tmp, "vb_trace.csv")))
  scale <- app_joint_shared_quantile_scale_trace_frame(fit)
  if (nrow(scale)) files <- c(files, scale_shape_trace = app_write_csv(scale,
    file.path(tmp, "scale_shape_trace.csv")))
  if (length(captured$warnings)) files <- c(files, warnings = app_write_csv(data.frame(
    warning_index = seq_along(captured$warnings), warning_message = captured$warnings),
    file.path(tmp, "warnings.csv")))
  app_joint_shared_write_manifest(tmp, files)
  verified <- app_joint_shared_verify_manifest(tmp, file.path(tmp, "artifact_manifest.csv"))
  if (!all(verified$verified)) stop("Transfer worker manifest failed verification.", call. = FALSE)
  writeLines("completed", file.path(tmp, "DONE"))
  if (dir.exists(out)) unlink(out, recursive = TRUE, force = TRUE)
  if (!file.rename(tmp, out)) stop("Could not publish transfer worker atomically.", call. = FALSE)
  invisible(out)
}

app_joint_swtx_predict_grid <- function(fits, state, tau) {
  if (is.list(fits) && is.null(fits$beta_mean)) {
    return(vapply(fits, app_joint_swq_predict_one, numeric(1L), state = state))
  }
  as.numeric(app_joint_qdesn_predict_fit(fits, matrix(state, nrow = 1L), tau))
}

app_joint_swtx_recursive_grid <- function(design, fixture, fits, contract) {
  blocks <- app_joint_sw_origin_rows(design, contract$full_origins, contract$calibration_max_lead)
  qhat <- matrix(NA_real_, nrow = sum(lengths(blocks)), ncol = length(design$tau))
  score_local <- full_time <- origin <- horizon <- integer(nrow(qhat)); cursor <- 0L
  median_index <- match(0.5, design$tau)
  for (position in seq_along(blocks)) {
    block <- blocks[[position]]; origin_local <- min(block) - 1L
    origin_full <- design$row_meta$full_time_index[[origin_local]]
    states <- lapply(design$teacher_forced_states, function(H) as.numeric(H[origin_local, ]))
    history <- fixture$y_history[seq_len(origin_full)]
    for (hh in seq_along(block)) {
      local_target <- block[[hh]]; tt <- design$row_meta$full_time_index[[local_target]]
      raw <- app_joint_pure_known_feature_row(tt, history, design$response_lags, design$dgp_row)
      scaled <- app_joint_recursive_scale_row(raw, design$scale_params)
      states <- app_qdesn_continue_one_step(states, scaled, design$reservoir, design$reservoir_meta)
      state_raw <- app_qdesn_readout_row_from_states(states, design$reservoir)
      state <- (state_raw - design$state_center) / design$state_scale
      cursor <- cursor + 1L; qhat[cursor, ] <- app_joint_swtx_predict_grid(fits, state, design$tau)
      score_local[[cursor]] <- local_target; full_time[[cursor]] <- tt
      origin[[cursor]] <- contract$full_origins[[position]]; horizon[[cursor]] <- hh
      history[[tt]] <- qhat[cursor, median_index]
    }
  }
  if (any(!is.finite(qhat))) stop("Transfer recursive grid is incomplete.", call. = FALSE)
  list(qhat = qhat, score_local = score_local, full_time_index = full_time,
    origin_index = origin, horizon = horizon)
}

app_joint_swtx_location_scale <- function(design, tolerance = 1.0e-8) {
  true_q <- as.matrix(design$true_q)
  tau <- as.numeric(design$tau)
  if (ncol(true_q) != length(tau) || length(tau) < 2L ||
      any(!is.finite(true_q)) || is.null(design$dgp_row)) {
    stop("Location-scale reconstruction requires finite oracle quantiles and a DGP row.",
      call. = FALSE)
  }
  standardized_q <- app_joint_qvp_registry_standardized_quantile(tau, design$dgp_row)
  centered_q <- standardized_q - mean(standardized_q)
  denominator <- sum(centered_q^2)
  if (!is.finite(denominator) || denominator <= .Machine$double.eps) {
    stop("Standardized DGP quantiles do not identify location and scale.", call. = FALSE)
  }
  sigma <- as.numeric(true_q %*% centered_q / denominator)
  mu <- rowMeans(true_q) - sigma * mean(standardized_q)
  reconstructed <- outer(mu, rep(1, length(tau))) + outer(sigma, standardized_q)
  row_tolerance <- tolerance * pmax(1, apply(abs(true_q), 1L, max))
  row_error <- apply(abs(reconstructed - true_q), 1L, max)
  if (any(!is.finite(mu)) || any(!is.finite(sigma)) || any(sigma <= 0) ||
      any(row_error > row_tolerance)) {
    stop("Oracle quantiles do not satisfy the frozen DGP location-scale contract.",
      call. = FALSE)
  }
  list(mu = mu, sigma = sigma, standardized_q = standardized_q,
    max_reconstruction_error = max(row_error))
}

app_joint_swtx_score_window <- function(design, qhat, index, model_id, window) {
  contract <- app_joint_qdesn_apply_monotone_contract(qhat, design$tau)
  location_scale <- app_joint_swtx_location_scale(design)
  score <- app_joint_qdesn_postscore_score_matrix(contract$qhat_contract,
    design$y[index], location_scale$mu[index], location_scale$sigma[index], design$dgp_row,
    design$tau, app_joint_shared_weights(design$tau))
  truth_error <- contract$qhat_contract - design$true_q[index, , drop = FALSE]
  data.frame(model_id = model_id, window = window, n_scored_rows = length(index),
    dgp_integrated_acrps = score$dgp_integrated_acrps,
    realized_acrps = score$realized_acrps,
    oracle_quantile_mae = mean(abs(truth_error)),
    oracle_quantile_rmse = sqrt(mean(truth_error^2)),
    raw_crossing_pairs = sum(contract$raw_crossing$n_crossing_pairs),
    contract_crossing_pairs = sum(contract$contract_crossing$n_crossing_pairs),
    n_adjusted_quantiles = contract$n_adjusted_quantiles,
    mean_abs_adjustment = contract$mean_abs_adjustment,
    max_abs_adjustment = contract$max_abs_adjustment, stringsAsFactors = FALSE)
}

app_joint_swtx_finalize <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); health <- app_joint_swtx_health(root)
  if (health$failed[[1L]] || health$completed[[1L]] != health$expected[[1L]]) {
    stop("Transfer stage is not complete and failure-free.", call. = FALSE)
  }
  contract <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  plan <- app_read_csv(file.path(root, "transfer_worker_plan.csv"))
  summaries <- app_bind_rows_fill(lapply(plan$transfer_worker_id, function(id) app_read_csv(file.path(
    app_joint_swtx_worker_dir(root, id), "summary.csv"))))
  if (nrow(summaries) != nrow(plan) || any(summaries$status != "completed") ||
      any(!app_as_bool_vec(summaries$finite_output)) || any(summaries$protected_rows_loaded != 0L)) {
    stop("Transfer summaries violate completion, finiteness, or protection gates.", call. = FALSE)
  }
  base_key <- paste(plan$scenario_id, plan$candidate_id,
    format(plan$rhs_tau0, digits = 17L, scientific = TRUE), plan$replicate_id, sep = "::")
  score_rows <- lapply(split(seq_len(nrow(plan)), base_key), function(index) {
    block <- plan[index, , drop = FALSE]; row <- block[1L, , drop = FALSE]
    fixture <- readRDS(row$fixture_path[[1L]])
    design <- app_joint_pure_build_design(fixture, row, contract, selector = TRUE)
    q1_fits <- app_joint_swtx_load_q1_fits(root, row)
    exal_rows <- block[block$model_id == "independent_exqdesn_rhs", , drop = FALSE]
    exal_rows <- exal_rows[order(exal_rows$tau), , drop = FALSE]
    exal_fits <- lapply(exal_rows$transfer_worker_id, function(id) readRDS(file.path(
      app_joint_swtx_worker_dir(root, id), "fit_initializer.rds")))
    joint_al_row <- block[block$model_id == "joint_qdesn_rhs", , drop = FALSE]
    joint_exal_row <- block[block$model_id == "joint_exqdesn_rhs", , drop = FALSE]
    models <- list(independent_qdesn_rhs = q1_fits,
      independent_exqdesn_rhs = exal_fits,
      joint_qdesn_rhs = readRDS(file.path(app_joint_swtx_worker_dir(root,
        joint_al_row$transfer_worker_id), "fit_initializer.rds")),
      joint_exqdesn_rhs = readRDS(file.path(app_joint_swtx_worker_dir(root,
        joint_exal_row$transfer_worker_id), "fit_initializer.rds")))
    app_bind_rows_fill(lapply(names(models), function(model) {
      fits <- models[[model]]
      fit_q <- if (is.list(fits) && is.null(fits$beta_mean)) do.call(cbind,
        lapply(fits, function(x) app_joint_qdesn_predict_fit(x,
          design$Z[design$train_local, , drop = FALSE], x$tau))) else
        app_joint_qdesn_predict_fit(fits, design$Z[design$train_local, , drop = FALSE], design$tau)
      recursive <- app_joint_swtx_recursive_grid(design, fixture, fits, contract)
      fit_score <- app_joint_swtx_score_window(design, fit_q, design$train_local, model, "fit")
      forecast_score <- app_joint_swtx_score_window(design, recursive$qhat,
        recursive$score_local, model, "calibration")
      out <- app_bind_rows_fill(list(fit_score, forecast_score))
      cbind(data.frame(scenario_id = row$scenario_id, specification_role = row$specification_role,
        candidate_id = row$candidate_id, rhs_tau0 = row$rhs_tau0,
        replicate_id = row$replicate_id, dgp_seed = row$dgp_seed,
        protected_rows_loaded = 0L, stringsAsFactors = FALSE), out)
    }))
  })
  scores <- app_bind_rows_fill(score_rows)
  if (nrow(scores) != 2L * 8L * contract$calibration_replicates * 4L * 2L ||
      any(!is.finite(scores$dgp_integrated_acrps)) ||
      any(!is.finite(scores$realized_acrps)) || any(scores$contract_crossing_pairs != 0L)) {
    stop("Transfer score packet violates cardinality, finiteness, or crossing gates.", call. = FALSE)
  }
  aggregate <- stats::aggregate(cbind(dgp_integrated_acrps, realized_acrps,
    oracle_quantile_mae, oracle_quantile_rmse, raw_crossing_pairs,
    contract_crossing_pairs) ~ scenario_id + specification_role + candidate_id +
    rhs_tau0 + model_id + window, data = scores, FUN = mean)
  files <- c(worker_summary = app_write_csv(summaries, file.path(root, "transfer_worker_summary.csv")),
    scores = app_write_csv(scores, file.path(root, "transfer_score_by_replicate.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "transfer_score_aggregate.csv")))
  decision <- data.frame(status = "TRANSFER_COMPLETE_READY_FOR_FULL_DEVELOPMENT_IMPLEMENTATION_REVIEW",
    workers = nrow(plan), score_rows = nrow(scores), downstream_launched = FALSE,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  files <- c(files, decision = app_write_csv(decision, file.path(root, "transfer_decision.csv")),
    app_joint_sw_stage_receipts(root, "transfer"))
  app_joint_shared_write_manifest(root, files, filename = "transfer_manifest.csv")
  decision
}
