# Targeted, observational-only recalibration for persistent tails and regime shifts.

app_joint_pr_contract_path <- function() {
  app_path("application/config/joint_qdesn_persistent_regime_recalibration_contract_v1.csv")
}

app_joint_pr_axes_path <- function() {
  app_path("application/config/joint_qdesn_persistent_regime_recalibration_axes_v1.csv")
}

app_joint_pr_registry_path <- function() {
  app_path("application/config/joint_qdesn_persistent_regime_recalibration_registry_v1.csv")
}

app_joint_pr_default_root <- function() {
  app_path("application/cache/joint_qdesn_persistent_regime_recalibration_20261120")
}

app_joint_pr_value <- function(tab, name) {
  row <- tab[tab$name == name, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("Targeted recalibration requires one '%s' field.", name), call. = FALSE)
  as.character(row$value[[1L]])
}

app_joint_pr_read_contract <- function(path = app_joint_pr_contract_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("section", "name", "value", "type", "description"),
    "targeted recalibration contract")
  if (anyDuplicated(tab$name)) stop("Targeted recalibration contract fields must be unique.", call. = FALSE)
  get <- function(name) app_joint_pr_value(tab, name)
  numvec <- function(name) as.numeric(strsplit(get(name), ";", fixed = TRUE)[[1L]])
  out <- list(
    table = tab, version = get("contract_version"), run_tag = get("run_tag"),
    scenario_ids = strsplit(get("scenario_ids"), ";", fixed = TRUE)[[1L]],
    scenario_count = as.integer(get("scenario_count")), desn_washout_rows = as.integer(get("desn_washout_rows")),
    fit_rows = as.integer(get("fit_rows")), inner_training_rows = as.integer(get("inner_training_rows")),
    inner_calibration_rows = as.integer(get("inner_calibration_rows")),
    protected_validation_rows = as.integer(get("protected_validation_rows")),
    calibration_origin_stride = as.integer(get("calibration_origin_stride")),
    calibration_max_lead = as.integer(get("calibration_max_lead")),
    candidate_count = as.integer(get("candidate_count")), advance_count = as.integer(get("ridge_advance_count")),
    ridge_tau2 = as.numeric(get("ridge_tau2")), intercept_variance = as.numeric(get("intercept_variance")),
    sigma_shape = as.numeric(get("sigma_shape")), sigma_rate = as.numeric(get("sigma_rate")),
    calibration_replicates = as.integer(get("calibration_replicates")), rhs_tau0_grid = numvec("tau0_grid"),
    rhs_max_iter = as.integer(get("rhs_max_iter")), rhs_min_iter = as.integer(get("rhs_min_iter")),
    rhs_tolerance = as.numeric(get("rhs_tolerance")), median_advance_count = as.integer(get("median_advance_count")),
    median_tau = as.numeric(get("median_tau")), median_max_iter = as.integer(get("median_max_iter")),
    median_tolerance = as.numeric(get("median_tolerance")), rhs_vb_inner = as.integer(get("rhs_vb_inner")),
    rhs_freeze_iters = as.integer(get("rhs_freeze_iters")), a_sigma = as.numeric(get("a_sigma")),
    b_sigma = as.numeric(get("b_sigma")), alpha_prior_sd_multiplier = as.numeric(get("alpha_prior_sd_multiplier")),
    max_condition_number = as.numeric(get("max_condition_number")),
    max_state_saturation = as.numeric(get("max_state_saturation")),
    max_readout_dimension = as.integer(get("max_readout_dimension")),
    protected_selection_forbidden = identical(tolower(get("protected_selection_forbidden")), "true"),
    require_finite_scores = identical(tolower(get("require_finite_scores")), "true"),
    allow_max_iter_review = identical(tolower(get("allow_max_iter_review")), "true"),
    max_workers = as.integer(get("max_workers")), blas_threads = as.integer(get("blas_threads")),
    nice_level = as.integer(get("nice_level")), min_data_free_gib = as.numeric(get("min_data_free_gib")),
    automatic_stop_after = get("automatic_stop_after")
  )
  valid <- identical(out$version, "joint_qdesn_persistent_regime_recalibration_v1") &&
    identical(out$scenario_ids, c("persistent_heavy_tail", "regime_shift")) && out$scenario_count == 2L &&
    out$candidate_count == 1024L && out$advance_count == 50L && out$median_advance_count == 8L &&
    out$calibration_replicates == 3L && out$inner_training_rows + out$inner_calibration_rows == out$fit_rows &&
    out$calibration_origin_stride == out$calibration_max_lead && out$max_readout_dimension == 600L &&
    out$protected_selection_forbidden && out$automatic_stop_after == "median_al_vb_review"
  if (!valid) stop("Targeted recalibration scientific contract is malformed.", call. = FALSE)
  out
}

app_joint_pr_axis_value <- function(tab, axis, numeric = FALSE) {
  row <- tab[tab$axis == axis, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("Targeted axes require one '%s' row.", axis), call. = FALSE)
  value <- strsplit(as.character(row$values[[1L]]), ";", fixed = TRUE)[[1L]]
  if (numeric) as.numeric(value) else value
}

app_joint_pr_read_axes <- function(path = app_joint_pr_axes_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("axis", "values", "role"), "targeted recalibration axes")
  value <- function(axis, numeric = FALSE) app_joint_pr_axis_value(tab, axis, numeric)
  out <- list(
    table = tab, depth = as.integer(value("depth", TRUE)), state_budget = as.integer(value("state_budget", TRUE)),
    width_shape = value("width_shape"), response_lags = as.integer(value("response_lags", TRUE)),
    exogenous_lags = as.integer(value("exogenous_lags", TRUE)), alpha_range = value("alpha_range", TRUE),
    alpha_schedule = value("alpha_schedule"), alpha_span_max = as.numeric(value("alpha_span_max", TRUE)),
    rho_range = value("rho_range", TRUE), rho_schedule = value("rho_schedule"),
    rho_span_max = as.numeric(value("rho_span_max", TRUE)), input_scale = value("input_scale", TRUE),
    pi_w = value("pi_w", TRUE), pi_in = value("pi_in", TRUE),
    reservoir_seed = as.integer(value("reservoir_seed", TRUE)), candidate_count = as.integer(value("candidate_count", TRUE)),
    halton_skip = as.integer(value("halton_skip", TRUE)), state_reduction = tolower(value("state_reduction")) == "true"
  )
  if (!identical(out$depth, 1:6) || max(out$state_budget) != 600L || max(out$response_lags) != 240L ||
      length(out$reservoir_seed) != 3L || out$candidate_count != 1024L || isTRUE(out$state_reduction)) {
    stop("Targeted recalibration axes violate the frozen search domain.", call. = FALSE)
  }
  out
}

app_joint_pr_read_registry <- function(path = app_joint_pr_registry_path()) {
  out <- app_read_csv(path)
  app_check_required_columns(out, c("enabled", "scenario_id", "scenario_order", "calibration_seed_base", "article_seed"),
    "targeted recalibration registry")
  out <- out[app_as_bool_vec(out$enabled), , drop = FALSE]
  out <- out[order(out$scenario_order), , drop = FALSE]
  if (!identical(out$scenario_id, c("persistent_heavy_tail", "regime_shift"))) {
    stop("Targeted recalibration registry must contain exactly the two frozen scenarios.", call. = FALSE)
  }
  out
}

app_joint_pr_halton <- function(n, d, skip) {
  primes <- c(2L, 3L, 5L, 7L, 11L, 13L, 17L, 19L, 23L, 29L, 31L, 37L, 41L, 43L, 47L)
  if (d > length(primes)) stop("Targeted Halton dimension is unsupported.", call. = FALSE)
  out <- matrix(NA_real_, nrow = n, ncol = d)
  for (jj in seq_len(d)) {
    out[, jj] <- vapply(skip + seq_len(n), app_joint_pure_expanded_radical_inverse,
      numeric(1L), base = primes[[jj]])
  }
  out
}

app_joint_pr_pick <- function(values, u) values[pmin(length(values), floor(u * length(values)) + 1L)]

app_joint_pr_widths <- function(D, budget, shape) {
  weights <- switch(shape, flat = rep(1, D), tapered = rev(seq_len(D)), expanding = seq_len(D),
    stop("Unknown targeted width shape.", call. = FALSE))
  n <- pmax(1L, floor(budget * weights / sum(weights)))
  while (sum(n) < budget) n[[which.min(n)]] <- n[[which.min(n)]] + 1L
  while (sum(n) > budget) n[[which.max(n)]] <- n[[which.max(n)]] - 1L
  as.integer(n)
}

app_joint_pr_layer_schedule <- function(center, span, D, kind, lower, upper) {
  if (D == 1L || kind == "flat") return(rep(min(upper, max(lower, center)), D))
  base <- switch(kind,
    increasing = seq(-1, 1, length.out = D),
    decreasing = seq(1, -1, length.out = D),
    u_shape = abs(seq(-1, 1, length.out = D)) * 2 - 1,
    stop("Unknown targeted layer schedule.", call. = FALSE))
  pmin(upper, pmax(lower, center + span * base))
}

app_joint_pr_fmt_vec <- function(x) paste(sub("[.]?0+$", "", sprintf("%.8f", x)), collapse = ";")

app_joint_pr_candidate_pool <- function(n = 4096L, axes = app_joint_pr_read_axes()) {
  H <- app_joint_pr_halton(n, 15L, axes$halton_skip)
  rows <- lapply(seq_len(n), function(ii) {
    D <- as.integer(app_joint_pr_pick(axes$depth, H[ii, 1L]))
    budget <- as.integer(app_joint_pr_pick(axes$state_budget, H[ii, 2L]))
    shape <- as.character(app_joint_pr_pick(axes$width_shape, H[ii, 3L]))
    alpha_center <- stats::plogis(stats::qlogis(axes$alpha_range[[1L]]) +
      H[ii, 5L] * diff(stats::qlogis(axes$alpha_range)))
    alpha_kind <- as.character(app_joint_pr_pick(axes$alpha_schedule, H[ii, 6L]))
    alpha_span <- H[ii, 7L] * axes$alpha_span_max
    rho_center <- axes$rho_range[[1L]] + H[ii, 8L] * diff(axes$rho_range)
    rho_kind <- as.character(app_joint_pr_pick(axes$rho_schedule, H[ii, 9L]))
    rho_span <- H[ii, 10L] * axes$rho_span_max
    widths <- app_joint_pr_widths(D, budget, shape)
    row <- data.frame(
      feature_contract = "pure_recursive_v1", design_class = "reservoir", D = D,
      n = paste(widths, collapse = ";"),
      n_tilde = if (D > 1L) paste(widths[seq_len(D - 1L)], collapse = ";") else "",
      retained_state_budget = sum(widths), width_shape = shape, state_reduction = FALSE,
      response_lags = as.integer(app_joint_pr_pick(axes$response_lags, H[ii, 4L])), exogenous_lags = 0L,
      alpha = app_joint_pr_fmt_vec(app_joint_pr_layer_schedule(alpha_center, alpha_span, D, alpha_kind, 0.01, 0.99)),
      rho = app_joint_pr_fmt_vec(app_joint_pr_layer_schedule(rho_center, rho_span, D, rho_kind, 0.20, 0.995)),
      pi_w = app_joint_pr_fmt_vec(rep(app_joint_pr_pick(axes$pi_w, H[ii, 11L]), D)),
      pi_in = app_joint_pr_fmt_vec(rep(app_joint_pr_pick(axes$pi_in, H[ii, 12L]), D)),
      input_scale = as.numeric(app_joint_pr_pick(axes$input_scale, H[ii, 13L])),
      reservoir_seed = as.integer(app_joint_pr_pick(axes$reservoir_seed, H[ii, 14L])),
      raw_inputs_in_readout = FALSE, full_states_all_layers = TRUE,
      candidate_role = paste0("targeted_halton_", alpha_kind, "_", rho_kind), stringsAsFactors = FALSE)
    row$architecture_signature <- app_joint_pure_architecture_signature(row)
    row
  })
  out <- app_bind_rows_fill(rows)
  out[!duplicated(out$architecture_signature), , drop = FALSE]
}

app_joint_pr_authoritative_anchors <- function() {
  path <- app_path("tables/joint_qdesn_pure_desn_v2_selected_backbones.csv")
  tab <- app_read_csv(path)
  tab <- tab[tab$scenario_id %in% c("persistent_heavy_tail", "regime_shift"), , drop = FALSE]
  if (nrow(tab) != 2L || anyDuplicated(tab$scenario_id)) stop("Authoritative parity anchors are unavailable.", call. = FALSE)
  tab
}

app_joint_pr_candidates <- function(scenario_id, contract = app_joint_pr_read_contract(),
  axes = app_joint_pr_read_axes(), pool = NULL) {
  if (is.null(pool)) pool <- app_joint_pr_candidate_pool(max(4096L, 4L * contract$candidate_count), axes)
  anchor <- app_joint_pr_authoritative_anchors()
  anchor <- anchor[anchor$scenario_id == scenario_id, , drop = FALSE]
  if (nrow(anchor) != 1L) stop("Scenario parity anchor is not unique.", call. = FALSE)
  pool <- pool[pool$architecture_signature != anchor$architecture_signature[[1L]], , drop = FALSE]
  keep <- pool[seq_len(contract$candidate_count - 1L), , drop = FALSE]
  anchor <- anchor[, intersect(names(keep), names(anchor)), drop = FALSE]
  missing <- setdiff(names(keep), names(anchor))
  for (name in missing) anchor[[name]] <- NA
  anchor <- anchor[, names(keep), drop = FALSE]
  anchor$candidate_role <- "authoritative_v2_parity_anchor"
  out <- rbind(anchor, keep)
  out$scenario_id <- scenario_id
  out$candidate_id <- sprintf("%s__targeted_%04d", scenario_id, seq_len(nrow(out)))
  out <- out[, c("candidate_id", "candidate_role", "scenario_id", setdiff(names(out), c("candidate_id", "candidate_role", "scenario_id"))), drop = FALSE]
  if (nrow(out) != contract$candidate_count || anyDuplicated(out$architecture_signature)) {
    stop("Targeted candidate registry has invalid cardinality or duplicate architectures.", call. = FALSE)
  }
  out
}

app_joint_pr_stage_id <- function(stage) switch(stage, ridge = "worker_id", rhs = "rhs_worker_id", median_al = "median_worker_id")

app_joint_pr_worker_dir <- function(root, stage, id) {
  file.path(root, paste0(stage, "_workers"), sprintf("worker_%05d", as.integer(id)))
}

app_joint_pr_prepare <- function(root = app_joint_pr_default_root()) {
  contract <- app_joint_pr_read_contract(); axes <- app_joint_pr_read_axes(); registry <- app_joint_pr_read_registry()
  root <- normalizePath(root, mustWork = FALSE)
  if (dir.exists(root) && length(list.files(root, all.files = TRUE, no.. = TRUE))) {
    stop("Refusing to overwrite a nonempty targeted recalibration root.", call. = FALSE)
  }
  app_ensure_dir(root); app_ensure_dir(file.path(root, "fixtures")); app_ensure_dir(file.path(root, "ridge_workers"))
  dgp <- app_joint_qdesn_load_simulation_registry()
  pool <- app_joint_pr_candidate_pool(max(4096L, 4L * contract$candidate_count), axes)
  candidates <- fixtures <- plans <- list(); worker_id <- 0L
  for (ii in seq_len(nrow(registry))) {
    family <- registry[ii, , drop = FALSE]; scenario <- family$scenario_id[[1L]]
    candidate <- app_joint_pr_candidates(scenario, contract, axes, pool)
    candidates[[ii]] <- candidate
    sc <- dgp[dgp$scenario_id == scenario, , drop = FALSE]
    if (nrow(sc) != 1L) stop("Targeted scenario is not unique in the DGP registry.", call. = FALSE)
    for (replicate_id in seq_len(contract$calibration_replicates)) {
      seed <- as.integer(family$calibration_seed_base[[1L]]) + replicate_id - 1L
      sc_rep <- sc; sc_rep$seed <- seed; sc_rep$seed_role <- sprintf("targeted_recalibration_rep%02d", replicate_id)
      fixture <- app_joint_qdesn_fixture_from_registry_row(sc_rep); fixture$registry_row <- sc_rep
      selector <- app_joint_pure_selector_fixture(fixture, contract)
      path <- file.path(root, "fixtures", sprintf("%02d_%s_rep%02d.rds", ii, scenario, replicate_id))
      saveRDS(selector, path, version = 3L, compress = "xz")
      fixtures[[length(fixtures) + 1L]] <- data.frame(
        scenario_id = scenario, replicate_id = replicate_id, dgp_seed = seed,
        fixture_path = normalizePath(path, mustWork = TRUE), size_bytes = file.info(path)$size,
        sha256 = app_sha256_file(path), protected_rows_persisted = 0L, stringsAsFactors = FALSE)
      jobs <- candidate; jobs$replicate_id <- replicate_id; jobs$dgp_seed <- seed
      jobs$fixture_path <- normalizePath(path, mustWork = TRUE)
      jobs$worker_id <- seq.int(worker_id + 1L, worker_id + nrow(jobs)); worker_id <- worker_id + nrow(jobs)
      plans[[length(plans) + 1L]] <- jobs
    }
  }
  candidate <- app_bind_rows_fill(candidates); fixture <- app_bind_rows_fill(fixtures); plan <- app_bind_rows_fill(plans)
  if (nrow(candidate) != contract$scenario_count * contract$candidate_count ||
      nrow(plan) != nrow(candidate) * contract$calibration_replicates || any(fixture$protected_rows_persisted != 0L)) {
    stop("Targeted recalibration preparation cardinality gate failed.", call. = FALSE)
  }
  expected <- data.frame(
    scenarios = 2L, ridge_candidates = nrow(candidate), ridge_workers = nrow(plan),
    maximum_rhs_workers = 2L * contract$advance_count * length(contract$rhs_tau0_grid) * contract$calibration_replicates,
    maximum_median_al_workers = 2L * contract$median_advance_count * contract$calibration_replicates,
    automatic_stop_after = contract$automatic_stop_after, stringsAsFactors = FALSE)
  files <- c(
    frozen_contract = app_write_csv(contract$table, file.path(root, "frozen_contract.csv")),
    frozen_axes = app_write_csv(axes$table, file.path(root, "frozen_axes.csv")),
    frozen_registry = app_write_csv(registry, file.path(root, "frozen_registry.csv")),
    authoritative_anchors = app_write_csv(app_joint_pr_authoritative_anchors(), file.path(root, "authoritative_anchors.csv")),
    candidate_registry = app_write_csv(candidate, file.path(root, "ridge_candidate_registry.csv")),
    fixture_manifest = app_write_csv(fixture, file.path(root, "fixture_manifest.csv")),
    ridge_worker_plan = app_write_csv(plan, file.path(root, "ridge_worker_plan.csv")),
    expected_work = app_write_csv(expected, file.path(root, "expected_work.csv")),
    source_git_state = app_write_csv(app_joint_shared_git_state(), file.path(root, "source_git_state.csv")))
  readiness <- data.frame(status = "READY_TO_LAUNCH_TARGETED_RIDGE", expected_workers = nrow(plan),
    max_workers = contract$max_workers, protected_rows_used_for_selection = 0L,
    article_fixture_used_for_selection = FALSE, downstream_auto_launch = FALSE, stringsAsFactors = FALSE)
  files <- c(files, launch_readiness = app_write_csv(readiness, file.path(root, "launch_readiness.csv")))
  app_joint_shared_write_manifest(root, files)
  list(root = root, expected = expected, readiness = readiness)
}

app_joint_pr_health <- function(root, stage = c("ridge", "rhs", "median_al")) {
  stage <- match.arg(stage); path <- file.path(root, paste0(stage, "_worker_plan.csv"))
  if (!file.exists(path)) return(data.frame(stage = stage, expected = 0L, completed = 0L, failed = 0L, remaining = 0L, status = "pending"))
  plan <- app_read_csv(path); id <- plan[[app_joint_pr_stage_id(stage)]]
  dirs <- vapply(id, function(x) app_joint_pr_worker_dir(root, stage, x), character(1L))
  done <- file.exists(file.path(dirs, "DONE")) & file.exists(file.path(dirs, "artifact_manifest.csv"))
  failed <- file.exists(file.path(dirs, "FAILED")) | file.exists(file.path(dirs, "failure.csv"))
  data.frame(stage = stage, expected = length(id), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), completion_fraction = mean(done),
    status = if (any(failed)) "failed" else if (all(done)) "complete" else "running", stringsAsFactors = FALSE)
}

app_joint_pr_recursive_median <- function(design, fixture, fit, contract) {
  cal <- design$calibration_local
  blocks <- split(cal, ceiling(seq_along(cal) / contract$calibration_max_lead))
  pred <- rep(NA_real_, length(cal)); cursor <- 0L
  for (block in blocks) {
    origin_local <- min(block) - 1L
    origin_full <- design$row_meta$full_time_index[[origin_local]]
    states <- lapply(design$teacher_forced_states, function(H) as.numeric(H[origin_local, ]))
    history <- fixture$y_history[seq_len(origin_full)]
    for (local_target in block) {
      tt <- design$row_meta$full_time_index[[local_target]]
      raw <- app_joint_pure_known_feature_row(tt, history, design$response_lags, design$dgp_row)
      scaled <- app_joint_recursive_scale_row(raw, design$scale_params)
      states <- app_qdesn_continue_one_step(states, scaled, design$reservoir, design$reservoir_meta)
      state_raw <- app_qdesn_readout_row_from_states(states, design$reservoir)
      z <- matrix((state_raw - design$state_center) / design$state_scale, nrow = 1L,
        dimnames = list(NULL, colnames(design$Z)))
      cursor <- cursor + 1L
      pred[[cursor]] <- as.numeric(app_joint_qdesn_predict_fit(fit, z, contract$median_tau))[[1L]]
      history[[tt]] <- pred[[cursor]]
    }
  }
  if (cursor != length(cal) || any(!is.finite(pred))) stop("Recursive median forecast is incomplete.", call. = FALSE)
  list(pred = pred, calibration_local = cal)
}

app_joint_pr_score_median_al <- function(fixture, row, contract) {
  started <- Sys.time(); design <- app_joint_pure_build_design(fixture, row, contract, selector = TRUE)
  tr <- design$train_local
  ridge <- app_glofas_normal_ridge_fit(design$X[tr, , drop = FALSE], design$y[tr],
    ridge_tau2 = contract$ridge_tau2, intercept_var = contract$intercept_variance,
    sigma_a = contract$sigma_shape, sigma_b = contract$sigma_rate)
  warm <- app_joint_shared_ridge_warm_start(ridge, row, design)
  gaussian <- app_glofas_normal_rhs_fit(design$X[tr, , drop = FALSE], design$y[tr], warm,
    tau0 = as.numeric(row$rhs_tau0[[1L]]), max_iter = contract$rhs_max_iter,
    min_iter = contract$rhs_min_iter, tol = contract$rhs_tolerance)
  qcontract <- list(alpha_prior_sd_multiplier = contract$alpha_prior_sd_multiplier,
    rhs_slab_variance = NA_real_, rhs_slab_fixed = FALSE, rhs_vb_inner = contract$rhs_vb_inner)
  init0 <- app_joint_shared_quantile_gaussian_init(gaussian, design, contract$median_tau, qcontract)
  init <- list(beta_mean = init0$beta_mean, beta_cov = init0$beta_cov,
    alpha_mean = init0$alpha_mean, sigma_mean = init0$sigma_mean,
    rhs_state = list(anchor = init0$rhs_state$anchor), iterations_completed = 0L)
  fit <- app_joint_qvp_fit_al_vb_tiny(
    y = design$y[tr], Z = design$Z[tr, , drop = FALSE], tau = contract$median_tau,
    max_iter = contract$median_max_iter, tol = contract$median_tolerance, kappa = 1,
    tau0 = as.numeric(row$rhs_tau0[[1L]]), zeta2 = init0$zeta2, slab_fixed = FALSE,
    a_sigma = contract$a_sigma, b_sigma = contract$b_sigma,
    alpha_prior_mean = init0$alpha_mean, alpha_prior_sd = init0$alpha_prior_sd,
    alpha_min_spacing = 0, max_dense_dim = contract$max_readout_dimension,
    rhs_vb_inner = contract$rhs_vb_inner, rhs_freeze_iters = contract$rhs_freeze_iters, init = init)
  forecast <- app_joint_pr_recursive_median(design, fixture, fit, contract)
  cal <- forecast$calibration_local; error <- forecast$pred - design$y[cal]
  oracle <- forecast$pred - design$true_q[cal, match(contract$median_tau, design$tau)]
  summary <- cbind(row, design$diagnostic, data.frame(
    status = "completed", method = "independent_median_al_vb",
    observational_selector = "rolling_origin_recursive_median_check_loss",
    hard_gate_status = if (all(is.finite(c(forecast$pred, fit$beta_mean, fit$alpha_mean, fit$sigma_mean)))) "pass" else "fail",
    median_check_loss_mean = mean(app_check_loss(design$y[cal], forecast$pred, contract$median_tau)),
    calibration_mae = mean(abs(error)), calibration_rmse = sqrt(mean(error^2)),
    calibration_oracle_median_mae = mean(abs(oracle)), calibration_oracle_median_rmse = sqrt(mean(oracle^2)),
    converged = isTRUE(fit$converged), convergence_status = if (isTRUE(fit$converged)) "pass" else "review_max_iter",
    iterations = as.integer(fit$iterations_completed %||% fit$iterations %||% NA_integer_),
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")), stringsAsFactors = FALSE))
  detail <- data.frame(calibration_row = seq_along(cal), full_time_index = design$row_meta$full_time_index[cal],
    y = design$y[cal], pred_median = forecast$pred, check_loss = app_check_loss(design$y[cal], forecast$pred, contract$median_tau),
    oracle_median = design$true_q[cal, match(contract$median_tau, design$tau)], stringsAsFactors = FALSE)
  list(summary = summary, detail = detail, fit = app_joint_shared_quantile_compact_fit(fit))
}

app_joint_pr_run_worker <- function(root, stage = c("ridge", "rhs", "median_al"), id) {
  stage <- match.arg(stage); root <- normalizePath(root, mustWork = TRUE)
  plan <- app_read_csv(file.path(root, paste0(stage, "_worker_plan.csv")))
  id_name <- app_joint_pr_stage_id(stage); row <- plan[as.integer(plan[[id_name]]) == as.integer(id), , drop = FALSE]
  if (nrow(row) != 1L) stop("Targeted worker ID is not unique.", call. = FALSE)
  out <- app_joint_pr_worker_dir(root, stage, id)
  if (file.exists(file.path(out, "DONE")) && file.exists(file.path(out, "artifact_manifest.csv"))) return(invisible(out))
  app_ensure_dir(out); contract <- app_joint_pr_read_contract(file.path(root, "frozen_contract.csv")); fixture <- readRDS(row$fixture_path[[1L]])
  result <- tryCatch(if (stage == "median_al") app_joint_pr_score_median_al(fixture, row, contract) else
    app_joint_pure_score_fit(fixture, row, contract, method = stage), error = function(e) e)
  if (inherits(result, "error")) {
    app_write_csv(cbind(row, data.frame(status = "failed", error_message = conditionMessage(result), stringsAsFactors = FALSE)),
      file.path(out, "failure.csv")); writeLines("failed", file.path(out, "FAILED")); return(invisible(out))
  }
  paths <- c(summary = app_write_csv(result$summary, file.path(out, "summary.csv")),
    calibration_detail = app_write_csv(result$detail, file.path(out, "calibration_detail.csv")))
  if (stage == "median_al") {
    fit_path <- file.path(out, "fit_initializer.rds"); saveRDS(result$fit, fit_path, version = 3L, compress = "xz")
    paths <- c(paths, fit_initializer = fit_path)
  } else if (nrow(result$trace)) paths <- c(paths, vb_trace = app_write_csv(result$trace, file.path(out, "vb_trace.csv")))
  app_joint_shared_write_manifest(out, paths); writeLines("completed", file.path(out, "DONE")); invisible(out)
}

app_joint_pr_collect <- function(root, stage) {
  health <- app_joint_pr_health(root, stage)
  if (health$completed[[1L]] != health$expected[[1L]] || health$failed[[1L]] != 0L) {
    stop(sprintf("Targeted %s stage is not complete and failure-free.", stage), call. = FALSE)
  }
  paths <- list.files(file.path(root, paste0(stage, "_workers")), pattern = "summary[.]csv$", recursive = TRUE, full.names = TRUE)
  out <- app_bind_rows_fill(lapply(paths, app_read_csv))
  if (nrow(out) != health$expected[[1L]] || any(out$status != "completed")) stop("Targeted summaries violate completion gates.", call. = FALSE)
  out
}

app_joint_pr_aggregate_gaussian <- function(scores) {
  keys <- c(app_joint_pure_candidate_columns(), if ("rhs_tau0" %in% names(scores)) "rhs_tau0")
  group_key <- paste(scores$scenario_id, scores$candidate_id,
    if ("rhs_tau0" %in% names(scores)) format(scores$rhs_tau0, scientific = TRUE) else "ridge", sep = "::")
  app_bind_rows_fill(lapply(split(scores, group_key), function(x) {
    row <- x[1L, keys, drop = FALSE]
    cbind(row, data.frame(replicate_count = nrow(x),
      hard_gate_status = if (all(x$hard_gate_status == "pass")) "pass" else "fail",
      calibration_acrps_mean = mean(as.numeric(x$calibration_acrps_mean)),
      calibration_acrps_between_rep_sd = stats::sd(as.numeric(x$calibration_acrps_mean)),
      calibration_acrps_worst_rep = max(as.numeric(x$calibration_acrps_mean)),
      calibration_exact_gaussian_crps_mean = mean(as.numeric(x$calibration_exact_gaussian_crps)),
      convergence_fraction = mean(app_as_bool_vec(x$converged)), stringsAsFactors = FALSE))
  }))
}

app_joint_pr_finalize_ridge <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); contract <- app_joint_pr_read_contract(file.path(root, "frozen_contract.csv"))
  scores <- app_joint_pr_collect(root, "ridge"); aggregate <- app_joint_pr_aggregate_gaussian(scores)
  frontier <- app_bind_rows_fill(lapply(split(aggregate, aggregate$scenario_id), function(x) {
    x <- x[x$hard_gate_status == "pass", , drop = FALSE]
    x <- x[order(x$calibration_acrps_mean, x$calibration_acrps_worst_rep,
      x$calibration_acrps_between_rep_sd, x$candidate_id), , drop = FALSE]
    if (nrow(x) < contract$advance_count) stop("Too few targeted ridge candidates passed.", call. = FALSE)
    x <- head(x, contract$advance_count); x$advancement_rank <- seq_len(nrow(x)); x
  }))
  fixtures <- unique(app_read_csv(file.path(root, "ridge_worker_plan.csv"))[, c("scenario_id", "replicate_id", "dgp_seed", "fixture_path")])
  rhs <- merge(frontier, data.frame(rhs_tau0 = contract$rhs_tau0_grid, stringsAsFactors = FALSE), by = NULL)
  rhs <- merge(rhs, fixtures, by = "scenario_id", all.x = TRUE)
  rhs <- rhs[order(rhs$scenario_id, rhs$advancement_rank, -rhs$rhs_tau0, rhs$replicate_id), , drop = FALSE]
  rhs$rhs_worker_id <- seq_len(nrow(rhs)); rhs$rhs_candidate_id <- paste(rhs$candidate_id, rhs$rhs_tau0, rhs$replicate_id, sep = "__")
  app_write_csv(scores, file.path(root, "ridge_scores_by_replicate.csv")); app_write_csv(aggregate, file.path(root, "ridge_candidate_aggregate.csv"))
  app_write_csv(frontier, file.path(root, "ridge_top50_by_scenario.csv")); app_write_csv(rhs, file.path(root, "rhs_worker_plan.csv"))
  app_ensure_dir(file.path(root, "rhs_workers")); app_write_csv(app_joint_pr_health(root, "ridge"), file.path(root, "ridge_final_health.csv"))
  list(frontier = frontier, rhs_plan = rhs)
}

app_joint_pr_finalize_rhs <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); contract <- app_joint_pr_read_contract(file.path(root, "frozen_contract.csv"))
  scores <- app_joint_pr_collect(root, "rhs"); aggregate <- app_joint_pr_aggregate_gaussian(scores)
  advanced <- app_bind_rows_fill(lapply(split(aggregate, aggregate$scenario_id), function(x) {
    x <- x[x$hard_gate_status == "pass" & is.finite(x$calibration_acrps_mean), , drop = FALSE]
    x <- x[order(x$calibration_acrps_mean, x$calibration_acrps_worst_rep,
      x$calibration_acrps_between_rep_sd, -x$convergence_fraction, x$retained_state_budget, x$candidate_id, x$rhs_tau0), , drop = FALSE]
    if (nrow(x) < contract$median_advance_count) stop("Too few targeted RHS candidates passed.", call. = FALSE)
    x <- head(x, contract$median_advance_count); x$rhs_selection_rank <- seq_len(nrow(x)); x
  }))
  fixtures <- unique(app_read_csv(file.path(root, "rhs_worker_plan.csv"))[, c("scenario_id", "replicate_id", "dgp_seed", "fixture_path")])
  plan <- merge(advanced, fixtures, by = "scenario_id", all.x = TRUE)
  plan <- plan[order(plan$scenario_id, plan$rhs_selection_rank, plan$replicate_id), , drop = FALSE]
  plan$median_worker_id <- seq_len(nrow(plan)); plan$median_tau <- contract$median_tau
  app_write_csv(scores, file.path(root, "rhs_scores_by_replicate.csv")); app_write_csv(aggregate, file.path(root, "rhs_candidate_aggregate.csv"))
  app_write_csv(advanced, file.path(root, "rhs_top8_for_median_al.csv")); app_write_csv(plan, file.path(root, "median_al_worker_plan.csv"))
  app_ensure_dir(file.path(root, "median_al_workers")); app_write_csv(app_joint_pr_health(root, "rhs"), file.path(root, "rhs_final_health.csv"))
  list(advanced = advanced, median_plan = plan)
}

app_joint_pr_finalize_median_al <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); contract <- app_joint_pr_read_contract(file.path(root, "frozen_contract.csv"))
  scores <- app_joint_pr_collect(root, "median_al")
  group_key <- paste(scores$scenario_id, scores$candidate_id, format(scores$rhs_tau0, scientific = TRUE), sep = "::")
  keys <- c(app_joint_pure_candidate_columns(), "rhs_tau0", "rhs_selection_rank")
  aggregate <- app_bind_rows_fill(lapply(split(scores, group_key), function(x) {
    row <- x[1L, keys, drop = FALSE]
    cbind(row, data.frame(replicate_count = nrow(x), finite_fraction = mean(x$hard_gate_status == "pass"),
      convergence_fraction = mean(app_as_bool_vec(x$converged)),
      median_check_loss_mean = mean(as.numeric(x$median_check_loss_mean)),
      median_check_loss_between_rep_sd = stats::sd(as.numeric(x$median_check_loss_mean)),
      median_check_loss_worst_rep = max(as.numeric(x$median_check_loss_mean)),
      calibration_mae_mean = mean(as.numeric(x$calibration_mae)),
      calibration_oracle_median_mae_mean = mean(as.numeric(x$calibration_oracle_median_mae)), stringsAsFactors = FALSE))
  }))
  selected <- app_bind_rows_fill(lapply(split(aggregate, aggregate$scenario_id), function(x) {
    x <- x[x$finite_fraction == 1, , drop = FALSE]
    x <- x[order(x$median_check_loss_mean, x$median_check_loss_worst_rep,
      x$median_check_loss_between_rep_sd, -x$convergence_fraction, x$retained_state_budget, x$candidate_id), , drop = FALSE]
    if (!nrow(x)) stop("No finite median-AL candidate remains.", call. = FALSE)
    x$selection_rank <- seq_len(nrow(x)); x[1L, , drop = FALSE]
  }))
  selected$selection_window <- "observational_350_train_150_recursive_calibration"
  selected$selection_metric <- "independent_median_al_recursive_check_loss"
  selected$protected_rows_used_for_selection <- 0L
  selected$promotion_status <- "REVIEW_BEFORE_SEVEN_QUANTILE_CONFIRMATION"
  files <- c(
    scores = app_write_csv(scores, file.path(root, "median_al_scores_by_replicate.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "median_al_candidate_aggregate.csv")),
    selected = app_write_csv(selected, file.path(root, "selected_targeted_backbones.csv")),
    ridge_health = app_write_csv(app_joint_pr_health(root, "ridge"), file.path(root, "ridge_final_health.csv")),
    rhs_health = app_write_csv(app_joint_pr_health(root, "rhs"), file.path(root, "rhs_final_health.csv")),
    median_health = app_write_csv(app_joint_pr_health(root, "median_al"), file.path(root, "median_al_final_health.csv")))
  status <- data.frame(status = "MEDIAN_AL_REVIEW_COMPLETE_NO_AUTOMATIC_PROMOTION", scenarios = nrow(selected),
    protected_rows_used_for_selection = 0L, joint_launched = FALSE, exal_launched = FALSE, mcmc_launched = FALSE,
    completed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE), stringsAsFactors = FALSE)
  files <- c(files, status = app_write_csv(status, file.path(root, "final_status.csv")))
  manifest <- app_joint_shared_write_manifest(root, files, filename = "final_artifact_manifest.csv")
  verification <- app_joint_shared_verify_manifest(root, manifest)
  if (!all(verification$verified)) stop("Targeted final manifest failed verification.", call. = FALSE)
  app_write_csv(verification, file.path(root, "final_artifact_manifest_verification.csv"))
  list(status = status, selected = selected, aggregate = aggregate)
}
