# VB fit and no-refit forecast validation for the joint QDESN simulation study.

app_joint_qdesn_default_vb_fit_validation_dir <- function() {
  app_path("application/cache/joint_qdesn_simulation_vb_fit_validation_article_20260706")
}

app_joint_qdesn_default_vb_forecast_validation_dir <- function() {
  app_path("application/cache/joint_qdesn_simulation_vb_forecast_validation_article_20260706")
}

app_joint_qdesn_simulation_model_specs <- function() {
  data.frame(
    model_id = c(
      "joint_qdesn_rhs_vb",
      "joint_exqdesn_rhs_vb",
      "qdesn_rhs_independent_vb",
      "exqdesn_rhs_independent_vb"
    ),
    display_label = c(
      "JOINT QDESN RHS",
      "JOINT exQDESN RHS",
      "QDESN RHS",
      "exQDESN RHS"
    ),
    likelihood = c("al", "exal", "al", "exal"),
    fit_structure = c("joint", "joint", "independent_single_tau", "independent_single_tau"),
    inference = c("VB", "VB-LD", "VB", "VB-LD"),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_parse_id_csv <- function(x) {
  if (is.null(x) || !length(x)) return(character())
  x <- as.character(x)[[1L]]
  if (is.na(x) || !nzchar(trimws(x))) return(character())
  vals <- trimws(strsplit(x, ",", fixed = TRUE)[[1L]])
  vals[nzchar(vals)]
}

app_joint_qdesn_filter_model_specs <- function(model_ids = NULL) {
  specs <- app_joint_qdesn_simulation_model_specs()
  if (is.null(model_ids) || !length(model_ids)) return(specs)
  model_ids <- unique(as.character(model_ids))
  model_ids <- model_ids[nzchar(model_ids)]
  if (!length(model_ids)) return(specs)
  missing <- setdiff(model_ids, specs$model_id)
  if (length(missing)) stop("Unknown model_ids: ", paste(missing, collapse = ", "), call. = FALSE)
  specs[match(model_ids, specs$model_id), , drop = FALSE]
}

app_joint_qdesn_simulation_controls <- function(
  vb_max_iter = 240L,
  adaptive_vb_max_iter_grid = c(240L, 480L),
  vb_tol = 1.0e-4,
  rhs_vb_inner = 5L,
  tau0 = 1,
  zeta2 = Inf,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_sd = 1,
  alpha_min_spacing = 0,
  gamma_init_policy = "default",
  review_adjustment_threshold = 1.0e-3,
  max_dense_dim = 300L,
  n_cores = 1L
) {
  gamma_init_policy <- as.character(gamma_init_policy)[[1L]]
  if (!gamma_init_policy %in% app_joint_qdesn_gamma_init_policy_choices()) {
    stop(sprintf("Unknown gamma_init_policy '%s'.", gamma_init_policy), call. = FALSE)
  }
  alpha_prior_sd <- app_joint_qdesn_parse_numeric_vector(alpha_prior_sd, "alpha_prior_sd", allow_inf = TRUE)
  list(
    vb_max_iter = as.integer(vb_max_iter),
    adaptive_vb_max_iter_grid = as.integer(adaptive_vb_max_iter_grid),
    vb_tol = as.numeric(vb_tol),
    rhs_vb_inner = as.integer(rhs_vb_inner),
    tau0 = as.numeric(tau0),
    zeta2 = as.numeric(zeta2),
    a_sigma = as.numeric(a_sigma),
    b_sigma = as.numeric(b_sigma),
    alpha_prior_sd = alpha_prior_sd,
    alpha_min_spacing = as.numeric(alpha_min_spacing),
    gamma_init_policy = gamma_init_policy,
    review_adjustment_threshold = as.numeric(review_adjustment_threshold),
    max_dense_dim = as.integer(max_dense_dim),
    n_cores = as.integer(n_cores)
  )
}

app_joint_qdesn_fixture_required_labels <- function() {
  c(
    "run_config", "frozen_registry", "scenario_summary", "observed_series",
    "design_matrix", "true_quantile_wide", "true_quantile_long",
    "split_metadata", "dgp_parameters", "forecast_origin_plan",
    "oracle_policy", "crossing_summary", "fixture_validation",
    "provenance", "readme"
  )
}

app_joint_qdesn_verify_artifact_manifest <- function(dir) {
  manifest_path <- file.path(dir, "artifact_manifest.csv")
  if (!file.exists(manifest_path)) {
    stop(sprintf("Missing artifact manifest: %s", manifest_path), call. = FALSE)
  }
  manifest <- app_read_csv(manifest_path)
  app_check_required_columns(
    manifest,
    c("label", "relative_path", "size_bytes", "sha256"),
    "joint QDESN artifact manifest"
  )
  rows <- lapply(seq_len(nrow(manifest)), function(ii) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    exists <- file.exists(path)
    actual_sha <- if (exists) app_sha256_file(path) else NA_character_
    actual_size <- if (exists) as.numeric(file.info(path)$size) else NA_real_
    data.frame(
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
  })
  out <- app_joint_qdesn_bind_rows(rows)
  required <- app_joint_qdesn_fixture_required_labels()
  missing <- setdiff(required, out$label)
  if (length(missing)) {
    out <- rbind(
      out,
      data.frame(
        label = missing,
        relative_path = NA_character_,
        path = NA_character_,
        exists = FALSE,
        declared_size_bytes = NA_real_,
        actual_size_bytes = NA_real_,
        declared_sha256 = NA_character_,
        actual_sha256 = NA_character_,
        status = "fail",
        stringsAsFactors = FALSE
      )
    )
  }
  out
}

app_joint_qdesn_stop_if_manifest_failed <- function(verification) {
  bad <- verification[verification$status != "pass", , drop = FALSE]
  if (nrow(bad)) {
    stop(
      sprintf(
        "Fixture manifest verification failed for labels: %s",
        paste(bad$label, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

app_joint_qdesn_load_fixture_artifacts <- function(fixture_dir = app_joint_qdesn_default_simulation_fixture_dir()) {
  fixture_dir <- normalizePath(fixture_dir, mustWork = TRUE)
  manifest_verification <- app_joint_qdesn_verify_artifact_manifest(fixture_dir)
  app_joint_qdesn_stop_if_manifest_failed(manifest_verification)
  artifacts <- list(
    fixture_dir = fixture_dir,
    manifest_verification = manifest_verification,
    run_config = app_read_csv(file.path(fixture_dir, "run_config.csv")),
    frozen_registry = app_read_csv(file.path(fixture_dir, "frozen_registry.csv")),
    scenario_summary = app_read_csv(file.path(fixture_dir, "scenario_summary.csv")),
    observed = app_read_csv(file.path(fixture_dir, "observed_series.csv")),
    design = app_read_csv(file.path(fixture_dir, "design_matrix.csv")),
    true_wide = app_read_csv(file.path(fixture_dir, "true_quantile_wide.csv")),
    true_long = app_read_csv(file.path(fixture_dir, "true_quantile_long.csv")),
    split_metadata = app_read_csv(file.path(fixture_dir, "split_metadata.csv")),
    forecast_origin_plan = app_read_csv(file.path(fixture_dir, "forecast_origin_plan.csv")),
    fixture_validation = app_read_csv(file.path(fixture_dir, "fixture_validation.csv"))
  )
  if (!all(artifacts$fixture_validation$status == "pass")) {
    stop("Fixture validation table contains non-pass rows.", call. = FALSE)
  }
  artifacts
}

app_joint_qdesn_metadata_columns <- function() {
  c(
    "scenario_id", "full_time_index", "effective_index", "analysis_window_index",
    "role", "role_index", "retained_after_desn_index"
  )
}

app_joint_qdesn_qcols <- function(true_wide) {
  cols <- grep("^q_tau_", names(true_wide), value = TRUE)
  if (!length(cols)) stop("Could not identify q_tau_* columns.", call. = FALSE)
  cols
}

app_joint_qdesn_tau_from_qcols <- function(q_cols) {
  tau <- as.numeric(gsub("p", ".", sub("^q_tau_", "", q_cols), fixed = TRUE))
  app_joint_qvp_validate_tau_grid(tau)
}

app_joint_qdesn_feature_cols <- function(design_block) {
  candidates <- setdiff(names(design_block), app_joint_qdesn_metadata_columns())
  keep <- vapply(candidates, function(nm) {
    x <- design_block[[nm]]
    is.numeric(x) && all(is.finite(x))
  }, logical(1L))
  candidates[keep]
}

app_joint_qdesn_scenario_fixture <- function(artifacts, scenario_id, role = "fit") {
  observed <- artifacts$observed[artifacts$observed$scenario_id == scenario_id & artifacts$observed$role == role, , drop = FALSE]
  design <- artifacts$design[artifacts$design$scenario_id == scenario_id & artifacts$design$role == role, , drop = FALSE]
  true_wide <- artifacts$true_wide[artifacts$true_wide$scenario_id == scenario_id & artifacts$true_wide$role == role, , drop = FALSE]
  if (!nrow(observed) || nrow(observed) != nrow(design) || nrow(observed) != nrow(true_wide)) {
    stop(sprintf("Malformed %s fixture rows for scenario '%s'.", role, scenario_id), call. = FALSE)
  }
  ord <- order(observed$full_time_index)
  observed <- observed[ord, , drop = FALSE]
  design <- design[order(design$full_time_index), , drop = FALSE]
  true_wide <- true_wide[order(true_wide$full_time_index), , drop = FALSE]
  if (!identical(observed$full_time_index, design$full_time_index) ||
      !identical(observed$full_time_index, true_wide$full_time_index)) {
    stop(sprintf("Fixture row alignment failed for scenario '%s' role '%s'.", scenario_id, role), call. = FALSE)
  }
  feature_cols <- app_joint_qdesn_feature_cols(design)
  q_cols <- app_joint_qdesn_qcols(true_wide)
  tau <- app_joint_qdesn_tau_from_qcols(q_cols)
  Z <- as.matrix(design[, feature_cols, drop = FALSE])
  true_q <- as.matrix(true_wide[, q_cols, drop = FALSE])
  colnames(true_q) <- app_joint_qdesn_quantile_slug(tau)
  colnames(Z) <- feature_cols
  if (!all(is.finite(observed$y)) || !all(is.finite(Z)) || !all(is.finite(true_q))) {
    stop(sprintf("Nonfinite fixture values for scenario '%s' role '%s'.", scenario_id, role), call. = FALSE)
  }
  scenario_meta <- artifacts$scenario_summary[artifacts$scenario_summary$scenario_id == scenario_id, , drop = FALSE]
  split_meta <- artifacts$split_metadata[artifacts$split_metadata$scenario_id == scenario_id, , drop = FALSE]
  list(
    scenario_id = scenario_id,
    role = role,
    y = as.numeric(observed$y),
    Z = Z,
    tau = tau,
    true_q = true_q,
    row_meta = observed[, app_joint_qdesn_metadata_columns(), drop = FALSE],
    observed = observed,
    design = design,
    true_wide = true_wide,
    feature_cols = feature_cols,
    q_cols = q_cols,
    scenario_meta = scenario_meta,
    split_meta = split_meta
  )
}

app_joint_qdesn_fit_model <- function(fixture, spec, controls) {
  if (identical(spec$model_id, "joint_qdesn_rhs_vb")) {
    return(app_joint_qdesn_fit_joint_al_readiness(fixture, controls))
  }
  if (identical(spec$model_id, "joint_exqdesn_rhs_vb")) {
    al_init <- app_joint_qdesn_fit_joint_al_readiness(fixture, controls)
    return(app_joint_qdesn_fit_joint_exal_readiness(fixture, controls, init = al_init))
  }
  if (identical(spec$model_id, "qdesn_rhs_independent_vb")) {
    return(app_joint_qdesn_fit_independent_readiness(fixture, controls, likelihood = "al"))
  }
  if (identical(spec$model_id, "exqdesn_rhs_independent_vb")) {
    return(app_joint_qdesn_fit_independent_readiness(fixture, controls, likelihood = "exal"))
  }
  stop(sprintf("Unknown model_id '%s'.", spec$model_id), call. = FALSE)
}

app_joint_qdesn_fit_model_adaptive <- function(fixture, spec, controls) {
  grid <- unique(as.integer(c(controls$vb_max_iter, controls$adaptive_vb_max_iter_grid)))
  grid <- grid[is.finite(grid) & grid > 0L]
  if (!length(grid)) grid <- as.integer(controls$vb_max_iter)
  grid <- sort(grid)
  attempts <- integer()
  fit <- NULL
  for (iter in grid) {
    attempt_controls <- controls
    attempt_controls$vb_max_iter <- iter
    attempts <- c(attempts, iter)
    fit <- app_joint_qdesn_fit_model(fixture, spec, attempt_controls)
    if (isTRUE(fit$converged)) break
  }
  attr(fit, "adaptive_vb_attempts") <- paste(attempts, collapse = ",")
  attr(fit, "adaptive_vb_max_iter_used") <- tail(attempts, 1L)
  fit
}

app_joint_qdesn_predict_fit <- function(fit, Z_new, tau) {
  Z_new <- as.matrix(Z_new)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  K <- length(tau)
  p <- ncol(Z_new)
  if (!is.null(fit$fits)) {
    qhat <- matrix(NA_real_, nrow = nrow(Z_new), ncol = K)
    for (kk in seq_len(K)) {
      one <- fit$fits[[kk]]
      beta <- as.numeric(one$beta_mean)
      alpha <- as.numeric(one$alpha_mean)[[1L]]
      beta_mat <- app_joint_qvp_beta_matrix(beta, 1L, p)
      qhat[, kk] <- as.numeric(Z_new %*% beta_mat[, 1L] + alpha)
    }
  } else {
    beta_mat <- app_joint_qvp_beta_matrix(fit$beta_mean, K, p)
    alpha <- as.numeric(fit$alpha_mean)
    qhat <- Z_new %*% beta_mat + matrix(alpha, nrow = nrow(Z_new), ncol = K, byrow = TRUE)
  }
  colnames(qhat) <- app_joint_qdesn_quantile_slug(tau)
  qhat
}

app_joint_qdesn_trace_rows <- function(fit, meta) {
  trace <- fit$trace %||% data.frame()
  if (!nrow(trace)) return(data.frame())
  cbind(meta, trace, stringsAsFactors = FALSE)
}

app_joint_qdesn_rhs_rows <- function(fit, meta) {
  rhs <- fit$rhs_prior_summary %||% data.frame()
  if (!nrow(rhs)) return(data.frame())
  cbind(meta, rhs, stringsAsFactors = FALSE)
}

app_joint_qdesn_objective_row <- function(fit, meta) {
  trace <- fit$trace %||% data.frame()
  if (!nrow(trace)) {
    return(cbind(meta, data.frame(
      n_trace_rows = 0L,
      finite_trace = FALSE,
      final_iter = NA_integer_,
      final_monitor = NA_real_,
      final_partial_elbo = NA_real_,
      monitor_nonmonotone_steps = NA_integer_,
      objective_status = "missing_trace",
      stringsAsFactors = FALSE
    )))
  }
  monitor <- if ("monitor" %in% names(trace)) as.numeric(trace$monitor) else rep(NA_real_, nrow(trace))
  partial_elbo <- if ("partial_elbo" %in% names(trace)) as.numeric(trace$partial_elbo) else rep(NA_real_, nrow(trace))
  finite_trace <- all(is.finite(as.matrix(trace[vapply(trace, is.numeric, logical(1L))])))
  cbind(meta, data.frame(
    n_trace_rows = nrow(trace),
    finite_trace = finite_trace,
    final_iter = if ("iter" %in% names(trace)) max(trace$iter, na.rm = TRUE) else nrow(trace),
    final_monitor = tail(monitor, 1L),
    final_partial_elbo = tail(partial_elbo, 1L),
    monitor_nonmonotone_steps = if (sum(is.finite(monitor)) >= 2L) sum(diff(monitor[is.finite(monitor)]) < -1.0e-8) else 0L,
    objective_status = if (finite_trace) "finite" else "nonfinite",
    stringsAsFactors = FALSE
  ))
}

app_joint_qdesn_vb_convergence_row <- function(fit, meta, controls) {
  trace <- fit$trace %||% data.frame()
  used_iter <- attr(fit, "adaptive_vb_max_iter_used") %||% controls$vb_max_iter
  attempts <- attr(fit, "adaptive_vb_attempts") %||% as.character(controls$vb_max_iter)
  cbind(meta, data.frame(
    vb_max_iter_requested = controls$vb_max_iter,
    adaptive_vb_max_iter_grid = paste(controls$adaptive_vb_max_iter_grid, collapse = ","),
    adaptive_vb_attempts = attempts,
    vb_max_iter_used = as.integer(used_iter),
    vb_tol = controls$vb_tol,
    rhs_vb_inner = controls$rhs_vb_inner,
    converged = isTRUE(fit$converged),
    reached_max_iter = !isTRUE(fit$converged),
    trace_rows = nrow(trace),
    final_iter = if (nrow(trace) && "iter" %in% names(trace)) max(trace$iter, na.rm = TRUE) else NA_integer_,
    final_monitor = if (nrow(trace) && "monitor" %in% names(trace)) tail(trace$monitor, 1L) else NA_real_,
    finite_trace = nrow(trace) > 0L && all(is.finite(as.matrix(trace[vapply(trace, is.numeric, logical(1L))]))),
    stringsAsFactors = FALSE
  ))
}

app_joint_qdesn_scale_summary_rows <- function(fit, fixture, meta) {
  tau <- fixture$tau
  data.frame(
    meta,
    quantile_index = seq_along(tau),
    tau = tau,
    alpha_mean = as.numeric(fit$alpha_mean),
    sigma_mean = as.numeric(fit$sigma_mean),
    gamma_mean = if (!is.null(fit$gamma_mean)) as.numeric(fit$gamma_mean) else NA_real_,
    finite_alpha = all(is.finite(fit$alpha_mean)),
    finite_sigma = all(is.finite(fit$sigma_mean)),
    positive_sigma = all(as.numeric(fit$sigma_mean) > 0),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_quantile_long_rows <- function(meta, row_meta, tau, y, true_q, qhat, value_name) {
  rows <- vector("list", length(tau))
  for (kk in seq_along(tau)) {
    rows[[kk]] <- cbind(
      meta,
      row_meta,
      data.frame(
        quantile_index = kk,
        tau = tau[[kk]],
        y = as.numeric(y),
        true_quantile = as.numeric(true_q[, kk]),
        stringsAsFactors = FALSE
      )
    )
    rows[[kk]][[value_name]] <- as.numeric(qhat[, kk])
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_adjustment_rows <- function(meta, row_meta, tau, raw, contract) {
  rows <- vector("list", length(tau))
  for (kk in seq_along(tau)) {
    adj <- as.numeric(contract[, kk] - raw[, kk])
    rows[[kk]] <- cbind(
      meta,
      row_meta,
      data.frame(
        quantile_index = kk,
        tau = tau[[kk]],
        qhat_raw = as.numeric(raw[, kk]),
        qhat_contract = as.numeric(contract[, kk]),
        adjustment = adj,
        abs_adjustment = abs(adj),
        adjusted = abs(adj) > 1.0e-10,
        stringsAsFactors = FALSE
      )
    )
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_crossing_rows <- function(meta, row_meta, tau, qhat, diagnostic) {
  out <- app_joint_qvp_crossing_diagnostics(qhat, tau)
  cbind(
    meta,
    row_meta[out$row_index, , drop = FALSE],
    data.frame(diagnostic = diagnostic, stringsAsFactors = FALSE),
    out,
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_quantile_scores <- function(contract_rows, qhat_col = "qhat") {
  out <- contract_rows
  out$check_loss <- app_check_loss(out$y, out[[qhat_col]], out$tau)
  out$hit <- out$y <= out[[qhat_col]]
  out$truth_error <- out[[qhat_col]] - out$true_quantile
  out$truth_abs_error <- abs(out$truth_error)
  out$truth_sq_error <- out$truth_error^2
  out
}

app_joint_qdesn_check_loss_summary <- function(scored) {
  by <- c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "tau")
  mean_loss <- aggregate(check_loss ~ ., scored[, c(by, "check_loss"), drop = FALSE], mean, na.rm = TRUE)
  names(mean_loss)[names(mean_loss) == "check_loss"] <- "check_loss_mean"
  n_loss <- aggregate(check_loss ~ ., scored[, c(by, "check_loss"), drop = FALSE], function(x) sum(is.finite(x)))
  names(n_loss)[names(n_loss) == "check_loss"] <- "n_scores"
  merge(mean_loss, n_loss, by = by, all = TRUE)
}

app_joint_qdesn_hit_rate_summary <- function(scored) {
  by <- c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "tau")
  hit <- aggregate(hit ~ ., scored[, c(by, "hit"), drop = FALSE], mean, na.rm = TRUE)
  names(hit)[names(hit) == "hit"] <- "hit_rate"
  n <- aggregate(hit ~ ., scored[, c(by, "hit"), drop = FALSE], function(x) sum(!is.na(x)))
  names(n)[names(n) == "hit"] <- "n_scores"
  out <- merge(hit, n, by = by, all = TRUE)
  out$hit_rate_error <- out$hit_rate - out$tau
  out$abs_hit_rate_error <- abs(out$hit_rate_error)
  out
}

app_joint_qdesn_truth_summary <- function(scored) {
  by <- c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "tau")
  mae <- aggregate(truth_abs_error ~ ., scored[, c(by, "truth_abs_error"), drop = FALSE], mean, na.rm = TRUE)
  names(mae)[names(mae) == "truth_abs_error"] <- "truth_mae"
  rmse <- aggregate(truth_sq_error ~ ., scored[, c(by, "truth_sq_error"), drop = FALSE], function(x) sqrt(mean(x, na.rm = TRUE)))
  names(rmse)[names(rmse) == "truth_sq_error"] <- "truth_rmse"
  bias <- aggregate(truth_error ~ ., scored[, c(by, "truth_error"), drop = FALSE], mean, na.rm = TRUE)
  names(bias)[names(bias) == "truth_error"] <- "truth_bias"
  Reduce(function(x, y) merge(x, y, by = by, all = TRUE), list(mae, rmse, bias))
}

app_joint_qdesn_group_key_columns <- function(scored) {
  base <- c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "full_time_index")
  extra <- intersect(c("origin_index", "horizon"), names(scored))
  c(base, extra)
}

app_joint_qdesn_crps_grid_summary <- function(scored, qhat_col = "qhat") {
  key_cols <- app_joint_qdesn_group_key_columns(scored)
  groups <- split(scored, interaction(scored[, key_cols, drop = FALSE], drop = TRUE, lex.order = TRUE))
  rows <- lapply(groups, function(block) {
    block <- block[order(block$tau), , drop = FALSE]
    tau <- block$tau
    loss <- app_check_loss(block$y[[1L]], block[[qhat_col]], tau)
    crps <- if (length(tau) >= 2L) 2 * sum(diff(tau) * (head(loss, -1L) + tail(loss, -1L)) / 2) else NA_real_
    cbind(block[1L, key_cols, drop = FALSE], data.frame(crps_grid = crps, stringsAsFactors = FALSE))
  })
  point <- app_joint_qdesn_bind_rows(rows)
  by <- c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure")
  mean_crps <- aggregate(crps_grid ~ ., point[, c(by, "crps_grid"), drop = FALSE], mean, na.rm = TRUE)
  names(mean_crps)[names(mean_crps) == "crps_grid"] <- "crps_grid_mean"
  n_crps <- aggregate(crps_grid ~ ., point[, c(by, "crps_grid"), drop = FALSE], function(x) sum(is.finite(x)))
  names(n_crps)[names(n_crps) == "crps_grid"] <- "n_crps"
  merge(mean_crps, n_crps, by = by, all = TRUE)
}

app_joint_qdesn_interval_summary <- function(scored, qhat_col = "qhat") {
  taus <- sort(unique(scored$tau))
  pairs <- list(c(0.05, 0.95), c(0.10, 0.90), c(0.25, 0.75))
  pairs <- pairs[vapply(pairs, function(x) all(round(x, 8) %in% round(taus, 8)), logical(1L))]
  if (!length(pairs)) return(data.frame())
  key_cols <- app_joint_qdesn_group_key_columns(scored)
  groups <- split(scored, interaction(scored[, key_cols, drop = FALSE], drop = TRUE, lex.order = TRUE))
  rows <- list()
  for (block in groups) {
    block <- block[order(block$tau), , drop = FALSE]
    for (pair in pairs) {
      lo_idx <- match(round(pair[[1L]], 8), round(block$tau, 8))
      hi_idx <- match(round(pair[[2L]], 8), round(block$tau, 8))
      if (is.na(lo_idx) || is.na(hi_idx)) next
      lo <- block[[qhat_col]][[lo_idx]]
      hi <- block[[qhat_col]][[hi_idx]]
      y <- block$y[[1L]]
      alpha <- 1 - (pair[[2L]] - pair[[1L]])
      rows[[length(rows) + 1L]] <- cbind(
        block[1L, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure"), drop = FALSE],
        data.frame(
          lower_tau = pair[[1L]],
          upper_tau = pair[[2L]],
          nominal_coverage = pair[[2L]] - pair[[1L]],
          covered = y >= lo && y <= hi,
          interval_width = hi - lo,
          interval_score = app_interval_score(y, lo, hi, alpha),
          stringsAsFactors = FALSE
        )
      )
    }
  }
  point <- app_joint_qdesn_bind_rows(rows)
  by <- c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "lower_tau", "upper_tau", "nominal_coverage")
  coverage <- aggregate(covered ~ ., point[, c(by, "covered"), drop = FALSE], mean, na.rm = TRUE)
  names(coverage)[names(coverage) == "covered"] <- "coverage"
  width <- aggregate(interval_width ~ ., point[, c(by, "interval_width"), drop = FALSE], mean, na.rm = TRUE)
  names(width)[names(width) == "interval_width"] <- "interval_width_mean"
  score <- aggregate(interval_score ~ ., point[, c(by, "interval_score"), drop = FALSE], mean, na.rm = TRUE)
  names(score)[names(score) == "interval_score"] <- "interval_score_mean"
  n <- aggregate(covered ~ ., point[, c(by, "covered"), drop = FALSE], function(x) sum(!is.na(x)))
  names(n)[names(n) == "covered"] <- "n_intervals"
  out <- Reduce(function(x, y) merge(x, y, by = by, all = TRUE), list(coverage, width, score, n))
  out$coverage_error <- out$coverage - out$nominal_coverage
  out$abs_coverage_error <- abs(out$coverage_error)
  out
}

app_joint_qdesn_assessment_rows <- function(
  scored,
  raw_crossing,
  contract_crossing,
  adjustment,
  vb_convergence,
  runtime_summary,
  controls,
  validation_label
) {
  keys <- unique(scored[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure"), drop = FALSE])
  rows <- lapply(seq_len(nrow(keys)), function(ii) {
    key <- keys[ii, , drop = FALSE]
    idx <- scored$scenario_id == key$scenario_id & scored$model_id == key$model_id
    raw_idx <- raw_crossing$scenario_id == key$scenario_id & raw_crossing$model_id == key$model_id
    contract_idx <- contract_crossing$scenario_id == key$scenario_id & contract_crossing$model_id == key$model_id
    adj_idx <- adjustment$scenario_id == key$scenario_id & adjustment$model_id == key$model_id
    vb_idx <- vb_convergence$scenario_id == key$scenario_id & vb_convergence$model_id == key$model_id
    rt_idx <- runtime_summary$scenario_id == key$scenario_id & runtime_summary$model_id == key$model_id
    finite_quantiles <- all(is.finite(scored$qhat[idx]))
    finite_scores <- all(is.finite(scored$check_loss[idx])) && all(is.finite(scored$truth_error[idx]))
    raw_pairs <- sum(raw_crossing$n_crossing_pairs[raw_idx], na.rm = TRUE)
    contract_pairs <- sum(contract_crossing$n_crossing_pairs[contract_idx], na.rm = TRUE)
    max_adj <- if (any(adj_idx)) max(adjustment$abs_adjustment[adj_idx], na.rm = TRUE) else 0
    adj_rate <- if (any(adj_idx)) mean(adjustment$adjusted[adj_idx], na.rm = TRUE) else 0
    reached_max <- any(vb_convergence$reached_max_iter[vb_idx], na.rm = TRUE)
    runtime <- if (any(rt_idx)) sum(runtime_summary$elapsed_seconds[rt_idx], na.rm = TRUE) else NA_real_
    hard_fail <- !finite_quantiles || !finite_scores || contract_pairs > 0L || !is.finite(runtime)
    review <- !hard_fail && (reached_max || raw_pairs > 0L || max_adj > controls$review_adjustment_threshold)
    reasons <- c(
      if (!finite_quantiles) "nonfinite contract quantiles",
      if (!finite_scores) "nonfinite scores or truth errors",
      if (contract_pairs > 0L) "contract quantiles cross",
      if (!is.finite(runtime)) "missing runtime",
      if (!hard_fail && reached_max) "VB reached max iterations",
      if (!hard_fail && raw_pairs > 0L) "raw quantiles crossed before contract step",
      if (!hard_fail && max_adj > controls$review_adjustment_threshold) "large monotone adjustment"
    )
    cbind(key, data.frame(
      validation_label = validation_label,
      gate_status = if (hard_fail) "fail" else if (review) "review" else "pass",
      finite_quantiles = finite_quantiles,
      finite_scores = finite_scores,
      raw_crossing_pairs = raw_pairs,
      contract_crossing_pairs = contract_pairs,
      max_abs_adjustment = max_adj,
      adjustment_rate = adj_rate,
      reached_max_iter = reached_max,
      elapsed_seconds = runtime,
      status_reason = if (length(reasons)) paste(reasons, collapse = "; ") else "all gates passed",
      stringsAsFactors = FALSE
    ))
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_fit_one_scenario <- function(artifacts, scenario_id, controls, model_ids = NULL) {
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
  specs <- app_joint_qdesn_filter_model_specs(model_ids)
  rows <- list()
  for (ii in seq_len(nrow(specs))) {
    spec <- specs[ii, , drop = FALSE]
    meta <- data.frame(
      scenario_id = scenario_id,
      scenario_class = fixture$scenario_meta$scenario_class[[1L]],
      distribution_family = fixture$scenario_meta$distribution_family[[1L]],
      dynamics_class = fixture$scenario_meta$dynamics_class[[1L]],
      model_id = spec$model_id,
      display_label = spec$display_label,
      likelihood = spec$likelihood,
      fit_structure = spec$fit_structure,
      inference = spec$inference,
      stringsAsFactors = FALSE
    )
    start <- proc.time()[["elapsed"]]
    fit <- app_joint_qdesn_fit_model_adaptive(fixture, spec, controls)
    elapsed <- proc.time()[["elapsed"]] - start
    raw <- app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau)
    contract <- app_joint_qdesn_apply_monotone_contract(raw, fixture$tau)
    raw_rows <- app_joint_qdesn_quantile_long_rows(meta, fixture$row_meta, fixture$tau, fixture$y, fixture$true_q, raw, "qhat_raw")
    contract_rows <- app_joint_qdesn_quantile_long_rows(meta, fixture$row_meta, fixture$tau, fixture$y, fixture$true_q, contract$qhat_contract, "qhat")
    adj_rows <- app_joint_qdesn_adjustment_rows(meta, fixture$row_meta, fixture$tau, raw, contract$qhat_contract)
    scored <- app_joint_qdesn_quantile_scores(contract_rows, "qhat")
    rows[[ii]] <- list(
      raw = raw_rows,
      contract = contract_rows,
      adjustment = adj_rows,
      scored = scored,
      raw_crossing = app_joint_qdesn_crossing_rows(meta, fixture$row_meta, fixture$tau, raw, "raw_fit_quantiles"),
      contract_crossing = app_joint_qdesn_crossing_rows(meta, fixture$row_meta, fixture$tau, contract$qhat_contract, "contract_fit_quantiles"),
      vb_convergence = app_joint_qdesn_vb_convergence_row(fit, meta, controls),
      objective = app_joint_qdesn_objective_row(fit, meta),
      rhs = app_joint_qdesn_rhs_rows(fit, meta),
      trace = app_joint_qdesn_trace_rows(fit, meta),
      scale = app_joint_qdesn_scale_summary_rows(fit, fixture, meta),
      runtime = cbind(meta, data.frame(elapsed_seconds = elapsed, stringsAsFactors = FALSE))
    )
  }
  rows
}

app_joint_qdesn_worker_error <- function(input, error) {
  structure(
    list(
      input = as.character(input)[[1L]],
      error_class = paste(class(error), collapse = ";"),
      error_message = conditionMessage(error)
    ),
    class = "app_joint_qdesn_worker_error"
  )
}

app_joint_qdesn_is_worker_error <- function(x) {
  inherits(x, "app_joint_qdesn_worker_error")
}

app_joint_qdesn_worker_failure_rows <- function(results, validation_label) {
  rows <- lapply(seq_along(results), function(ii) {
    result <- results[[ii]]
    if (!app_joint_qdesn_is_worker_error(result)) return(NULL)
    data.frame(
      validation_label = validation_label,
      scenario_id = result$input,
      worker_index = ii,
      worker_status = "fail",
      error_class = result$error_class,
      error_message = result$error_message,
      stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  if (nrow(out)) return(out)
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

app_joint_qdesn_successful_worker_results <- function(results, validation_label) {
  ok <- !vapply(results, app_joint_qdesn_is_worker_error, logical(1L))
  if (any(ok)) return(results[ok])
  first_error <- results[[which(!ok)[[1L]]]]
  stop(
    sprintf(
      "All %s scenario workers failed; first failure for '%s': %s",
      validation_label,
      first_error$input,
      first_error$error_message
    ),
    call. = FALSE
  )
}

app_joint_qdesn_parallel_lapply <- function(X, FUN, n_cores) {
  n_cores <- max(1L, min(as.integer(n_cores), length(X)))
  safe_fun <- function(x) {
    tryCatch(
      FUN(x),
      error = function(e) app_joint_qdesn_worker_error(x, e)
    )
  }
  if (n_cores <= 1L || .Platform$OS.type == "windows") {
    return(lapply(X, safe_fun))
  }
  parallel::mclapply(X, safe_fun, mc.cores = n_cores, mc.preschedule = FALSE)
}

app_joint_qdesn_make_run_config <- function(run_id, out_dir, fixture_dir, controls, scenario_ids, extra = list()) {
  base <- data.frame(
    run_id = run_id,
    out_dir = normalizePath(out_dir, mustWork = FALSE),
    fixture_dir = normalizePath(fixture_dir, mustWork = FALSE),
    scenario_ids = paste(scenario_ids, collapse = ","),
    n_scenarios = length(scenario_ids),
    vb_max_iter = controls$vb_max_iter,
    adaptive_vb_max_iter_grid = paste(controls$adaptive_vb_max_iter_grid, collapse = ","),
    vb_tol = controls$vb_tol,
    rhs_vb_inner = controls$rhs_vb_inner,
    tau0 = controls$tau0,
    zeta2 = controls$zeta2,
    a_sigma = controls$a_sigma,
    b_sigma = controls$b_sigma,
    alpha_prior_sd = app_joint_qdesn_format_numeric_vector(controls$alpha_prior_sd),
    alpha_min_spacing = controls$alpha_min_spacing,
    gamma_init_policy = controls$gamma_init_policy %||% "default",
    review_adjustment_threshold = controls$review_adjustment_threshold,
    max_dense_dim = controls$max_dense_dim,
    n_cores = controls$n_cores,
    mcmc_launched = FALSE,
    stringsAsFactors = FALSE
  )
  if (!length(extra)) return(base)
  for (nm in names(extra)) base[[nm]] <- extra[[nm]]
  base
}

app_joint_qdesn_write_manifest <- function(paths, out_dir) {
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(manifest = manifest, manifest_path = manifest_path)
}

app_joint_qdesn_fit_validation_readme <- function(run_config, assessment) {
  c(
    "# Joint QDESN VB Fit Validation",
    "",
    "This directory contains article-scale VB fit-validation artifacts for the new joint QDESN simulation study.",
    "It consumes the frozen long-series fixture directory and fits only the declared fit rows.",
    "",
    sprintf("- Fixture directory: `%s`", run_config$fixture_dir[[1L]]),
    sprintf("- Scenarios: %s", run_config$n_scenarios[[1L]]),
    sprintf("- Cores requested: %s", run_config$n_cores[[1L]]),
    sprintf("- VB max iterations: %s", run_config$vb_max_iter[[1L]]),
    "",
    "Raw fitted quantiles are preserved in `fit_quantiles_raw.csv`.",
    "Scoring uses the monotone contract quantiles in `fit_quantiles.csv`.",
    "",
    "Gate counts:",
    paste(capture.output(print(table(assessment$gate_status))), collapse = "\n")
  )
}

app_joint_qdesn_run_vb_fit_validation <- function(
  out_dir = app_joint_qdesn_default_vb_fit_validation_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  scenario_ids = NULL,
  model_ids = NULL,
  vb_max_iter = 240L,
  adaptive_vb_max_iter_grid = c(240L, 480L),
  vb_tol = 1.0e-4,
  rhs_vb_inner = 5L,
  tau0 = 1,
  zeta2 = Inf,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_sd = 1,
  alpha_min_spacing = 0,
  gamma_init_policy = "default",
  review_adjustment_threshold = 1.0e-3,
  max_dense_dim = 300L,
  n_cores = 1L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)
  available <- artifacts$scenario_summary$scenario_id
  if (is.null(scenario_ids) || !length(scenario_ids)) scenario_ids <- available
  missing <- setdiff(scenario_ids, available)
  if (length(missing)) stop("Unknown scenario_ids: ", paste(missing, collapse = ", "), call. = FALSE)
  scenario_ids <- scenario_ids[scenario_ids %in% available]
  model_specs <- app_joint_qdesn_filter_model_specs(model_ids)
  model_ids <- model_specs$model_id
  controls <- app_joint_qdesn_simulation_controls(
    vb_max_iter = vb_max_iter,
    adaptive_vb_max_iter_grid = adaptive_vb_max_iter_grid,
    vb_tol = vb_tol,
    rhs_vb_inner = rhs_vb_inner,
    tau0 = tau0,
    zeta2 = zeta2,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_sd = alpha_prior_sd,
    alpha_min_spacing = alpha_min_spacing,
    gamma_init_policy = gamma_init_policy,
    review_adjustment_threshold = review_adjustment_threshold,
    max_dense_dim = max_dense_dim,
    n_cores = n_cores
  )
  results <- app_joint_qdesn_parallel_lapply(
    scenario_ids,
    function(sid) app_joint_qdesn_fit_one_scenario(artifacts, sid, controls, model_ids = model_ids),
    controls$n_cores
  )
  scenario_failure <- app_joint_qdesn_worker_failure_rows(results, "fit")
  flat <- unlist(app_joint_qdesn_successful_worker_results(results, "fit"), recursive = FALSE)
  fit_raw <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "raw"))
  fit_contract <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "contract"))
  fit_adjustment <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "adjustment"))
  scored <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "scored"))
  raw_crossing <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "raw_crossing"))
  contract_crossing <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "contract_crossing"))
  vb_convergence <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "vb_convergence"))
  objective <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "objective"))
  rhs <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "rhs"))
  scale <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "scale"))
  runtime <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "runtime"))
  assessment <- app_joint_qdesn_assessment_rows(
    scored = scored,
    raw_crossing = raw_crossing,
    contract_crossing = contract_crossing,
    adjustment = fit_adjustment,
    vb_convergence = vb_convergence,
    runtime_summary = runtime,
    controls = controls,
    validation_label = "fit"
  )
  truth_summary <- app_joint_qdesn_truth_summary(scored)
  check_loss_summary <- app_joint_qdesn_check_loss_summary(scored)
  hit_rate_summary <- app_joint_qdesn_hit_rate_summary(scored)
  crps_summary <- app_joint_qdesn_crps_grid_summary(scored, "qhat")
  interval_summary <- app_joint_qdesn_interval_summary(scored, "qhat")
  model_fit_summary <- Reduce(
    function(x, y) merge(x, y, by = c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure"), all = TRUE),
    list(
      assessment,
      aggregate(truth_abs_error ~ scenario_id + model_id + display_label + likelihood + fit_structure, scored, mean, na.rm = TRUE),
      aggregate(check_loss ~ scenario_id + model_id + display_label + likelihood + fit_structure, scored, mean, na.rm = TRUE)
    )
  )
  names(model_fit_summary)[names(model_fit_summary) == "truth_abs_error"] <- "truth_mae_mean"
  names(model_fit_summary)[names(model_fit_summary) == "check_loss"] <- "check_loss_mean"
  run_config <- app_joint_qdesn_make_run_config(
    run_id = "joint_qdesn_simulation_vb_fit_validation",
    out_dir = out_dir,
    fixture_dir = artifacts$fixture_dir,
    controls = controls,
    scenario_ids = scenario_ids,
    extra = list(
      validation_scope = "fit_rows_only",
      forecast_launched = FALSE,
      model_ids = paste(model_ids, collapse = ","),
      n_models = length(model_ids)
    )
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qdesn_fit_validation_readme(run_config, assessment), readme_path, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    fixture_source_manifest = app_joint_qvp_write_csv(artifacts$manifest_verification, file.path(out_dir, "fixture_source_manifest.csv")),
    model_fit_summary = app_joint_qvp_write_csv(model_fit_summary, file.path(out_dir, "model_fit_summary.csv")),
    fit_quantiles_raw = app_joint_qvp_write_csv(fit_raw, file.path(out_dir, "fit_quantiles_raw.csv")),
    fit_quantiles = app_joint_qvp_write_csv(scored, file.path(out_dir, "fit_quantiles.csv")),
    fit_monotone_adjustment = app_joint_qvp_write_csv(fit_adjustment, file.path(out_dir, "fit_monotone_adjustment.csv")),
    fit_truth_comparison = app_joint_qvp_write_csv(scored, file.path(out_dir, "fit_truth_comparison.csv")),
    check_loss_summary = app_joint_qvp_write_csv(check_loss_summary, file.path(out_dir, "check_loss_summary.csv")),
    crps_grid_summary = app_joint_qvp_write_csv(crps_summary, file.path(out_dir, "crps_grid_summary.csv")),
    hit_rate_summary = app_joint_qvp_write_csv(hit_rate_summary, file.path(out_dir, "hit_rate_summary.csv")),
    interval_summary = app_joint_qvp_write_csv(interval_summary, file.path(out_dir, "interval_summary.csv")),
    crossing_summary = app_joint_qvp_write_csv(contract_crossing, file.path(out_dir, "crossing_summary.csv")),
    raw_crossing_summary = app_joint_qvp_write_csv(raw_crossing, file.path(out_dir, "raw_crossing_summary.csv")),
    scenario_failure = app_joint_qvp_write_csv(scenario_failure, file.path(out_dir, "scenario_failure.csv")),
    vb_convergence_audit = app_joint_qvp_write_csv(vb_convergence, file.path(out_dir, "vb_convergence_audit.csv")),
    objective_diagnostics = app_joint_qvp_write_csv(objective, file.path(out_dir, "objective_diagnostics.csv")),
    rhs_prior_summary = app_joint_qvp_write_csv(rhs, file.path(out_dir, "rhs_prior_summary.csv")),
    scale_parameter_summary = app_joint_qvp_write_csv(scale, file.path(out_dir, "scale_parameter_summary.csv")),
    runtime_summary = app_joint_qvp_write_csv(runtime, file.path(out_dir, "runtime_summary.csv")),
    fit_validation_assessment = app_joint_qvp_write_csv(assessment, file.path(out_dir, "fit_validation_assessment.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    fixture_dir = artifacts$fixture_dir,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path),
    manifest = manifest_info$manifest,
    run_config = run_config,
    model_fit_summary = model_fit_summary,
    fit_validation_assessment = assessment,
    vb_convergence_audit = vb_convergence,
    runtime_summary = runtime
  )
}

app_joint_qdesn_forecast_target_fixture <- function(artifacts, scenario_id, origin_row) {
  target_idx <- seq.int(origin_row$target_start_full_time_index[[1L]], origin_row$target_end_full_time_index[[1L]])
  observed <- artifacts$observed[artifacts$observed$scenario_id == scenario_id & artifacts$observed$full_time_index %in% target_idx, , drop = FALSE]
  design <- artifacts$design[artifacts$design$scenario_id == scenario_id & artifacts$design$full_time_index %in% target_idx, , drop = FALSE]
  true_wide <- artifacts$true_wide[artifacts$true_wide$scenario_id == scenario_id & artifacts$true_wide$full_time_index %in% target_idx, , drop = FALSE]
  observed <- observed[order(observed$full_time_index), , drop = FALSE]
  design <- design[order(design$full_time_index), , drop = FALSE]
  true_wide <- true_wide[order(true_wide$full_time_index), , drop = FALSE]
  if (!nrow(observed) || !all(observed$role == "validation")) {
    stop(sprintf("Forecast target rows are malformed for scenario '%s' origin %s.", scenario_id, origin_row$origin_index[[1L]]), call. = FALSE)
  }
  feature_cols <- app_joint_qdesn_feature_cols(design)
  q_cols <- app_joint_qdesn_qcols(true_wide)
  tau <- app_joint_qdesn_tau_from_qcols(q_cols)
  row_meta <- observed[, app_joint_qdesn_metadata_columns(), drop = FALSE]
  row_meta$origin_index <- origin_row$origin_index[[1L]]
  row_meta$origin_full_time_index <- origin_row$origin_full_time_index[[1L]]
  row_meta$origin_effective_index <- origin_row$origin_effective_index[[1L]]
  row_meta$horizon <- seq_len(nrow(observed))
  row_meta$fit_window_start_full_time_index <- origin_row$fit_window_start_full_time_index[[1L]]
  row_meta$fit_window_end_full_time_index <- origin_row$fit_window_end_full_time_index[[1L]]
  list(
    y = as.numeric(observed$y),
    Z = as.matrix(design[, feature_cols, drop = FALSE]),
    true_q = as.matrix(true_wide[, q_cols, drop = FALSE]),
    tau = tau,
    row_meta = row_meta,
    feature_cols = feature_cols
  )
}

app_joint_qdesn_forecast_one_scenario <- function(artifacts, scenario_id, controls, model_ids = NULL) {
  fit_fixture <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
  origin_plan <- artifacts$forecast_origin_plan[artifacts$forecast_origin_plan$scenario_id == scenario_id, , drop = FALSE]
  origin_plan <- origin_plan[order(origin_plan$origin_index), , drop = FALSE]
  specs <- app_joint_qdesn_filter_model_specs(model_ids)
  rows <- list()
  for (ii in seq_len(nrow(specs))) {
    spec <- specs[ii, , drop = FALSE]
    meta <- data.frame(
      scenario_id = scenario_id,
      scenario_class = fit_fixture$scenario_meta$scenario_class[[1L]],
      distribution_family = fit_fixture$scenario_meta$distribution_family[[1L]],
      dynamics_class = fit_fixture$scenario_meta$dynamics_class[[1L]],
      model_id = spec$model_id,
      display_label = spec$display_label,
      likelihood = spec$likelihood,
      fit_structure = spec$fit_structure,
      inference = spec$inference,
      stringsAsFactors = FALSE
    )
    start <- proc.time()[["elapsed"]]
    fit <- app_joint_qdesn_fit_model_adaptive(fit_fixture, spec, controls)
    elapsed_fit <- proc.time()[["elapsed"]] - start
    origin_rows <- list()
    for (jj in seq_len(nrow(origin_plan))) {
      target <- app_joint_qdesn_forecast_target_fixture(artifacts, scenario_id, origin_plan[jj, , drop = FALSE])
      if (!identical(fit_fixture$feature_cols, target$feature_cols)) {
        stop(sprintf("Feature columns changed between fit and forecast for '%s'.", scenario_id), call. = FALSE)
      }
      raw <- app_joint_qdesn_predict_fit(fit, target$Z, target$tau)
      contract <- app_joint_qdesn_apply_monotone_contract(raw, target$tau)
      raw_rows <- app_joint_qdesn_quantile_long_rows(meta, target$row_meta, target$tau, target$y, target$true_q, raw, "qhat_raw")
      contract_rows <- app_joint_qdesn_quantile_long_rows(meta, target$row_meta, target$tau, target$y, target$true_q, contract$qhat_contract, "qhat")
      adj_rows <- app_joint_qdesn_adjustment_rows(meta, target$row_meta, target$tau, raw, contract$qhat_contract)
      scored <- app_joint_qdesn_quantile_scores(contract_rows, "qhat")
      origin_rows[[jj]] <- list(
        raw = raw_rows,
        contract = contract_rows,
        adjustment = adj_rows,
        scored = scored,
        raw_crossing = app_joint_qdesn_crossing_rows(meta, target$row_meta, target$tau, raw, "raw_forecast_quantiles"),
        contract_crossing = app_joint_qdesn_crossing_rows(meta, target$row_meta, target$tau, contract$qhat_contract, "contract_forecast_quantiles")
      )
    }
    flat_origin <- origin_rows
    rows[[ii]] <- list(
      raw = app_joint_qdesn_bind_rows(lapply(flat_origin, `[[`, "raw")),
      contract = app_joint_qdesn_bind_rows(lapply(flat_origin, `[[`, "contract")),
      adjustment = app_joint_qdesn_bind_rows(lapply(flat_origin, `[[`, "adjustment")),
      scored = app_joint_qdesn_bind_rows(lapply(flat_origin, `[[`, "scored")),
      raw_crossing = app_joint_qdesn_bind_rows(lapply(flat_origin, `[[`, "raw_crossing")),
      contract_crossing = app_joint_qdesn_bind_rows(lapply(flat_origin, `[[`, "contract_crossing")),
      vb_convergence = app_joint_qdesn_vb_convergence_row(fit, meta, controls),
      objective = app_joint_qdesn_objective_row(fit, meta),
      rhs = app_joint_qdesn_rhs_rows(fit, meta),
      runtime = cbind(meta, data.frame(elapsed_seconds = elapsed_fit, n_origins = nrow(origin_plan), stringsAsFactors = FALSE))
    )
  }
  rows
}

app_joint_qdesn_forecast_validation_readme <- function(run_config, assessment) {
  c(
    "# Joint QDESN VB No-Refit Forecast Validation",
    "",
    "This directory contains article-scale no-refit forecast-validation artifacts for the new joint QDESN simulation study.",
    "Each model is fitted once on the declared fit rows, then evaluated on the frozen validation-origin plan.",
    "",
    sprintf("- Fixture directory: `%s`", run_config$fixture_dir[[1L]]),
    sprintf("- Scenarios: %s", run_config$n_scenarios[[1L]]),
    sprintf("- Cores requested: %s", run_config$n_cores[[1L]]),
    sprintf("- VB max iterations: %s", run_config$vb_max_iter[[1L]]),
    "",
    "Raw forecast quantiles are preserved in `forecast_quantiles_raw.csv`.",
    "Scoring uses the monotone contract quantiles in `forecast_quantiles.csv`.",
    "Target-row design features are read from the frozen synthetic fixture; target responses are not used for fitting.",
    "",
    "Gate counts:",
    paste(capture.output(print(table(assessment$gate_status))), collapse = "\n")
  )
}

app_joint_qdesn_run_vb_forecast_validation <- function(
  out_dir = app_joint_qdesn_default_vb_forecast_validation_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  scenario_ids = NULL,
  model_ids = NULL,
  vb_max_iter = 240L,
  adaptive_vb_max_iter_grid = c(240L, 480L),
  vb_tol = 1.0e-4,
  rhs_vb_inner = 5L,
  tau0 = 1,
  zeta2 = Inf,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_sd = 1,
  alpha_min_spacing = 0,
  gamma_init_policy = "default",
  review_adjustment_threshold = 1.0e-3,
  max_dense_dim = 300L,
  n_cores = 1L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)
  available <- artifacts$scenario_summary$scenario_id
  if (is.null(scenario_ids) || !length(scenario_ids)) scenario_ids <- available
  missing <- setdiff(scenario_ids, available)
  if (length(missing)) stop("Unknown scenario_ids: ", paste(missing, collapse = ", "), call. = FALSE)
  scenario_ids <- scenario_ids[scenario_ids %in% available]
  model_specs <- app_joint_qdesn_filter_model_specs(model_ids)
  model_ids <- model_specs$model_id
  controls <- app_joint_qdesn_simulation_controls(
    vb_max_iter = vb_max_iter,
    adaptive_vb_max_iter_grid = adaptive_vb_max_iter_grid,
    vb_tol = vb_tol,
    rhs_vb_inner = rhs_vb_inner,
    tau0 = tau0,
    zeta2 = zeta2,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_sd = alpha_prior_sd,
    alpha_min_spacing = alpha_min_spacing,
    gamma_init_policy = gamma_init_policy,
    review_adjustment_threshold = review_adjustment_threshold,
    max_dense_dim = max_dense_dim,
    n_cores = n_cores
  )
  results <- app_joint_qdesn_parallel_lapply(
    scenario_ids,
    function(sid) app_joint_qdesn_forecast_one_scenario(artifacts, sid, controls, model_ids = model_ids),
    controls$n_cores
  )
  scenario_failure <- app_joint_qdesn_worker_failure_rows(results, "forecast")
  flat <- unlist(app_joint_qdesn_successful_worker_results(results, "forecast"), recursive = FALSE)
  forecast_raw <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "raw"))
  forecast_contract <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "contract"))
  forecast_adjustment <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "adjustment"))
  scored <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "scored"))
  raw_crossing <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "raw_crossing"))
  contract_crossing <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "contract_crossing"))
  vb_convergence <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "vb_convergence"))
  objective <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "objective"))
  rhs <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "rhs"))
  runtime <- app_joint_qdesn_bind_rows(lapply(flat, `[[`, "runtime"))
  assessment <- app_joint_qdesn_assessment_rows(
    scored = scored,
    raw_crossing = raw_crossing,
    contract_crossing = contract_crossing,
    adjustment = forecast_adjustment,
    vb_convergence = vb_convergence,
    runtime_summary = runtime,
    controls = controls,
    validation_label = "forecast"
  )
  check_loss_summary <- app_joint_qdesn_check_loss_summary(scored)
  hit_rate_summary <- app_joint_qdesn_hit_rate_summary(scored)
  crps_summary <- app_joint_qdesn_crps_grid_summary(scored, "qhat")
  interval_summary <- app_joint_qdesn_interval_summary(scored, "qhat")
  truth_summary <- app_joint_qdesn_truth_summary(scored)
  origin_plan <- artifacts$forecast_origin_plan[artifacts$forecast_origin_plan$scenario_id %in% scenario_ids, , drop = FALSE]
  run_config <- app_joint_qdesn_make_run_config(
    run_id = "joint_qdesn_simulation_vb_no_refit_forecast_validation",
    out_dir = out_dir,
    fixture_dir = artifacts$fixture_dir,
    controls = controls,
    scenario_ids = scenario_ids,
    extra = list(
      validation_scope = "validation_origin_leads",
      coefficient_refit_policy = "single_fit_no_refit_across_validation_blocks",
      uses_frozen_target_design = TRUE,
      model_ids = paste(model_ids, collapse = ","),
      n_models = length(model_ids)
    )
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qdesn_forecast_validation_readme(run_config, assessment), readme_path, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    fixture_source_manifest = app_joint_qvp_write_csv(artifacts$manifest_verification, file.path(out_dir, "fixture_source_manifest.csv")),
    forecast_origin_plan = app_joint_qvp_write_csv(origin_plan, file.path(out_dir, "forecast_origin_plan.csv")),
    forecast_quantiles_raw = app_joint_qvp_write_csv(forecast_raw, file.path(out_dir, "forecast_quantiles_raw.csv")),
    forecast_quantiles = app_joint_qvp_write_csv(scored, file.path(out_dir, "forecast_quantiles.csv")),
    forecast_monotone_adjustment = app_joint_qvp_write_csv(forecast_adjustment, file.path(out_dir, "forecast_monotone_adjustment.csv")),
    forecast_truth_comparison = app_joint_qvp_write_csv(scored, file.path(out_dir, "forecast_truth_comparison.csv")),
    truth_distance_summary = app_joint_qvp_write_csv(truth_summary, file.path(out_dir, "truth_distance_summary.csv")),
    check_loss_summary = app_joint_qvp_write_csv(check_loss_summary, file.path(out_dir, "check_loss_summary.csv")),
    crps_grid_summary = app_joint_qvp_write_csv(crps_summary, file.path(out_dir, "crps_grid_summary.csv")),
    hit_rate_summary = app_joint_qvp_write_csv(hit_rate_summary, file.path(out_dir, "hit_rate_summary.csv")),
    interval_summary = app_joint_qvp_write_csv(interval_summary, file.path(out_dir, "interval_summary.csv")),
    crossing_summary = app_joint_qvp_write_csv(contract_crossing, file.path(out_dir, "crossing_summary.csv")),
    raw_crossing_summary = app_joint_qvp_write_csv(raw_crossing, file.path(out_dir, "raw_crossing_summary.csv")),
    scenario_failure = app_joint_qvp_write_csv(scenario_failure, file.path(out_dir, "scenario_failure.csv")),
    vb_convergence_audit = app_joint_qvp_write_csv(vb_convergence, file.path(out_dir, "vb_convergence_audit.csv")),
    objective_diagnostics = app_joint_qvp_write_csv(objective, file.path(out_dir, "objective_diagnostics.csv")),
    rhs_prior_summary = app_joint_qvp_write_csv(rhs, file.path(out_dir, "rhs_prior_summary.csv")),
    runtime_summary = app_joint_qvp_write_csv(runtime, file.path(out_dir, "runtime_summary.csv")),
    forecast_validation_assessment = app_joint_qvp_write_csv(assessment, file.path(out_dir, "forecast_validation_assessment.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    fixture_dir = artifacts$fixture_dir,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path),
    manifest = manifest_info$manifest,
    run_config = run_config,
    forecast_validation_assessment = assessment,
    vb_convergence_audit = vb_convergence,
    runtime_summary = runtime
  )
}
