# Seed-robust, scenario-specific recalibration for the two difficult JOINT cases.

app_joint_pr2_contract_path <- function() {
  app_path("application/config/joint_qdesn_persistent_regime_recalibration_contract_v2.csv")
}

app_joint_pr2_axes_path <- function() {
  app_path("application/config/joint_qdesn_persistent_regime_recalibration_axes_v2.csv")
}

app_joint_pr2_default_root <- function() {
  app_path("application/cache/joint_qdesn_persistent_regime_recalibration_v2_20261120")
}

app_joint_pr2_read_contract <- function(path = app_joint_pr2_contract_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("section", "name", "value", "type", "description"), "targeted v2 contract")
  if (anyDuplicated(tab$name)) stop("Targeted v2 contract names must be unique.", call. = FALSE)
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
    parity_relative_tolerance = as.numeric(get("parity_relative_tolerance")),
    candidate_count = as.integer(get("candidate_count")), local_candidate_count = as.integer(get("local_candidate_count")),
    global_candidate_count = as.integer(get("global_candidate_count")),
    mechanism_candidate_count = as.integer(get("mechanism_candidate_count")),
    numerical_shortlist_count = as.integer(get("numerical_shortlist_count")),
    diversity_shortlist_count = as.integer(get("diversity_shortlist_count")),
    ridge_tau2 = as.numeric(get("ridge_tau2")), intercept_variance = as.numeric(get("intercept_variance")),
    sigma_shape = as.numeric(get("sigma_shape")), sigma_rate = as.numeric(get("sigma_rate")),
    calibration_replicates = as.integer(get("calibration_replicates")),
    canonical_reservoir_seed = as.integer(get("canonical_reservoir_seed")),
    robustness_reservoir_seeds = as.integer(numvec("robustness_reservoir_seeds")),
    seed_advance_count = as.integer(get("advance_count")), rhs_tau0_grid = numvec("coarse_tau0_grid"),
    refinement_factor = as.numeric(get("refinement_factor")), refinement_min_tau0 = as.numeric(get("refinement_min_tau0")),
    refinement_max_tau0 = as.numeric(get("refinement_max_tau0")),
    refinement_candidate_count = as.integer(get("refinement_candidate_count")),
    rhs_max_iter = as.integer(get("rhs_max_iter")), rhs_min_iter = as.integer(get("rhs_min_iter")),
    rhs_tolerance = as.numeric(get("rhs_tolerance")), median_candidate_count = as.integer(get("median_candidate_count")),
    median_tau = as.numeric(get("median_tau")), median_max_iter = as.integer(get("median_max_iter")),
    median_tolerance = as.numeric(get("median_tolerance")), rhs_vb_inner = as.integer(get("rhs_vb_inner")),
    rhs_freeze_iters = as.integer(get("rhs_freeze_iters")), a_sigma = as.numeric(get("a_sigma")),
    b_sigma = as.numeric(get("b_sigma")), alpha_prior_sd_multiplier = as.numeric(get("alpha_prior_sd_multiplier")),
    tail_candidate_count = as.integer(get("tail_candidate_count")), tail_quantiles = numvec("tail_quantiles"),
    proxy_weights = numvec("proxy_weights"), max_condition_number = as.numeric(get("max_condition_number")),
    max_state_saturation = as.numeric(get("max_state_saturation")),
    max_readout_dimension = as.integer(get("max_readout_dimension")),
    protected_selection_forbidden = identical(tolower(get("protected_selection_forbidden")), "true"),
    require_finite_scores = identical(tolower(get("require_finite_scores")), "true"),
    allow_max_iter_review = identical(tolower(get("allow_max_iter_review")), "true"),
    max_workers = as.integer(get("max_workers")), cpu_affinity = as.integer(numvec("cpu_affinity_list")),
    blas_threads = as.integer(get("blas_threads")), nice_level = as.integer(get("nice_level")),
    min_data_free_gib = as.numeric(get("min_data_free_gib")), automatic_stop_after = get("automatic_stop_after")
  )
  valid <- identical(out$version, "joint_qdesn_persistent_regime_recalibration_v2") &&
    identical(out$scenario_ids, c("persistent_heavy_tail", "regime_shift")) && out$scenario_count == 2L &&
    out$candidate_count == 1L + out$local_candidate_count + out$global_candidate_count + out$mechanism_candidate_count &&
    out$seed_advance_count == 1L + out$numerical_shortlist_count + out$diversity_shortlist_count &&
    identical(out$robustness_reservoir_seeds[[1L]], out$canonical_reservoir_seed) &&
    length(out$robustness_reservoir_seeds) == 3L && out$median_candidate_count == 12L &&
    identical(out$tail_quantiles, c(0.05, 0.95)) && length(out$proxy_weights) == 3L &&
    abs(sum(out$proxy_weights) - 1) < 1e-12 && length(out$cpu_affinity) == out$max_workers &&
    !anyDuplicated(out$cpu_affinity) && out$inner_training_rows + out$inner_calibration_rows == out$fit_rows &&
    out$protected_selection_forbidden && out$automatic_stop_after == "three_quantile_al_transfer_review"
  if (!valid) stop("Targeted v2 scientific contract is malformed.", call. = FALSE)
  out
}

app_joint_pr2_read_axes <- function(path = app_joint_pr2_axes_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("profile", "axis", "values", "role"), "targeted v2 axes")
  if (anyDuplicated(paste(tab$profile, tab$axis))) stop("Targeted v2 profile axes must be unique.", call. = FALSE)
  list(table = tab)
}

app_joint_pr2_axis <- function(axes, profile, axis, numeric = FALSE) {
  row <- axes$table[axes$table$profile %in% c(profile, "common") & axes$table$axis == axis, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("Targeted v2 axes require one %s/%s row.", profile, axis), call. = FALSE)
  out <- strsplit(as.character(row$values[[1L]]), ";", fixed = TRUE)[[1L]]
  if (numeric) as.numeric(out) else out
}

app_joint_pr2_profile_pool <- function(profile, n, axes, skip, canonical_seed) {
  H <- app_joint_pr_halton(n, 13L, skip)
  pick <- app_joint_pr_pick
  depth <- as.integer(app_joint_pr2_axis(axes, profile, "depth", TRUE))
  budgets <- as.integer(app_joint_pr2_axis(axes, profile, "state_budget", TRUE))
  shapes <- app_joint_pr2_axis(axes, profile, "width_shape")
  lags <- as.integer(app_joint_pr2_axis(axes, profile, "response_lags", TRUE))
  alpha_range <- app_joint_pr2_axis(axes, profile, "alpha_range", TRUE)
  alpha_kinds <- app_joint_pr2_axis(axes, profile, "alpha_schedule")
  alpha_span_max <- app_joint_pr2_axis(axes, profile, "alpha_span_max", TRUE)
  rho_range <- app_joint_pr2_axis(axes, profile, "rho_range", TRUE)
  rho_kinds <- app_joint_pr2_axis(axes, profile, "rho_schedule")
  rho_span_max <- app_joint_pr2_axis(axes, profile, "rho_span_max", TRUE)
  input_scale <- app_joint_pr2_axis(axes, profile, "input_scale", TRUE)
  pi_w <- app_joint_pr2_axis(axes, profile, "pi_w", TRUE)
  pi_in <- app_joint_pr2_axis(axes, profile, "pi_in", TRUE)
  rows <- lapply(seq_len(n), function(ii) {
    D <- as.integer(pick(depth, H[ii, 1L])); budget <- as.integer(pick(budgets, H[ii, 2L]))
    shape <- as.character(pick(shapes, H[ii, 3L])); widths <- app_joint_pr_widths(D, budget, shape)
    alpha_center <- stats::plogis(stats::qlogis(alpha_range[[1L]]) + H[ii, 5L] * diff(stats::qlogis(alpha_range)))
    alpha_kind <- as.character(pick(alpha_kinds, H[ii, 6L])); alpha_span <- H[ii, 7L] * alpha_span_max
    rho_center <- rho_range[[1L]] + H[ii, 8L] * diff(rho_range)
    rho_kind <- as.character(pick(rho_kinds, H[ii, 9L])); rho_span <- H[ii, 10L] * rho_span_max
    row <- data.frame(
      feature_contract = "pure_recursive_v1", design_class = "reservoir", D = D,
      n = paste(widths, collapse = ";"), n_tilde = if (D > 1L) paste(widths[seq_len(D - 1L)], collapse = ";") else "",
      retained_state_budget = sum(widths), width_shape = shape, state_reduction = FALSE,
      response_lags = as.integer(pick(lags, H[ii, 4L])), exogenous_lags = 0L,
      alpha = app_joint_pr_fmt_vec(app_joint_pr_layer_schedule(alpha_center, alpha_span, D, alpha_kind, 0.01, 0.99)),
      rho = app_joint_pr_fmt_vec(app_joint_pr_layer_schedule(rho_center, rho_span, D, rho_kind, 0.20, 0.995)),
      pi_w = app_joint_pr_fmt_vec(rep(pick(pi_w, H[ii, 11L]), D)),
      pi_in = app_joint_pr_fmt_vec(rep(pick(pi_in, H[ii, 12L]), D)),
      input_scale = as.numeric(pick(input_scale, H[ii, 13L])), reservoir_seed = as.integer(canonical_seed),
      raw_inputs_in_readout = FALSE, full_states_all_layers = TRUE,
      candidate_role = paste("targeted_v2", profile, alpha_kind, rho_kind, sep = "_"), stringsAsFactors = FALSE)
    row$architecture_signature <- app_joint_pure_architecture_signature(row)
    row
  })
  out <- app_bind_rows_fill(rows)
  out[!duplicated(out$architecture_signature), , drop = FALSE]
}

app_joint_pr2_take_unique <- function(pool, n, used = character()) {
  pool <- pool[!pool$architecture_signature %in% used, , drop = FALSE]
  if (nrow(pool) < n) stop("Targeted v2 candidate pool is too small after deduplication.", call. = FALSE)
  pool[seq_len(n), , drop = FALSE]
}

app_joint_pr2_candidates <- function(scenario_id, contract = app_joint_pr2_read_contract(), axes = app_joint_pr2_read_axes()) {
  authority <- app_joint_pr_authoritative_anchors()
  anchor <- authority[authority$scenario_id == scenario_id, , drop = FALSE]
  if (nrow(anchor) != 1L) stop("Targeted v2 parity anchor is not unique.", call. = FALSE)
  standard <- c("feature_contract", "design_class", "D", "n", "n_tilde", "retained_state_budget", "width_shape",
    "state_reduction", "response_lags", "exogenous_lags", "alpha", "rho", "pi_w", "pi_in", "input_scale",
    "reservoir_seed", "raw_inputs_in_readout", "full_states_all_layers", "architecture_signature")
  anchor <- anchor[, standard, drop = FALSE]; anchor$candidate_role <- "authoritative_v2_parity_anchor"
  local_profile <- if (scenario_id == "persistent_heavy_tail") "persistent_local" else "regime_local"
  mechanism_profile <- if (scenario_id == "persistent_heavy_tail") "persistent_mechanism" else "regime_mechanism"
  local_pool <- app_joint_pr2_profile_pool(local_profile, 4L * contract$local_candidate_count, axes,
    8000L + ifelse(scenario_id == "persistent_heavy_tail", 0L, 1000L), contract$canonical_reservoir_seed)
  local <- app_joint_pr2_take_unique(local_pool, contract$local_candidate_count, anchor$architecture_signature)
  used <- c(anchor$architecture_signature, local$architecture_signature)
  global_pool <- app_joint_pr2_profile_pool("global", 4L * contract$global_candidate_count, axes,
    12000L + ifelse(scenario_id == "persistent_heavy_tail", 0L, 1000L), contract$canonical_reservoir_seed)
  global <- app_joint_pr2_take_unique(global_pool, contract$global_candidate_count, used)
  used <- c(used, global$architecture_signature)
  mechanism_pool <- app_joint_pr2_profile_pool(mechanism_profile, 4L * contract$mechanism_candidate_count, axes,
    16000L + ifelse(scenario_id == "persistent_heavy_tail", 0L, 1000L), contract$canonical_reservoir_seed)
  mechanism <- app_joint_pr2_take_unique(mechanism_pool, contract$mechanism_candidate_count, used)
  out <- app_bind_rows_fill(list(anchor, local, global, mechanism))
  out$scenario_id <- scenario_id
  out$candidate_id <- sprintf("%s__targeted_v2_%04d", scenario_id, seq_len(nrow(out)))
  out <- out[, c("candidate_id", "candidate_role", "scenario_id", standard), drop = FALSE]
  if (nrow(out) != contract$candidate_count || anyDuplicated(out$architecture_signature) ||
      sum(out$candidate_role == "authoritative_v2_parity_anchor") != 1L ||
      any(out$reservoir_seed != contract$canonical_reservoir_seed)) {
    stop("Targeted v2 candidate allocation is malformed.", call. = FALSE)
  }
  out
}

app_joint_pr2_stage_spec <- function(stage) {
  switch(stage,
    parity = c(plan = "parity_worker_plan.csv", id = "parity_worker_id"),
    ridge = c(plan = "ridge_worker_plan.csv", id = "worker_id"),
    seed_ridge = c(plan = "seed_ridge_worker_plan.csv", id = "seed_worker_id"),
    rhs = c(plan = "rhs_worker_plan.csv", id = "rhs_worker_id"),
    rhs_refine = c(plan = "rhs_refine_worker_plan.csv", id = "rhs_refine_worker_id"),
    median_al = c(plan = "median_al_worker_plan.csv", id = "median_worker_id"),
    tail_al = c(plan = "tail_al_worker_plan.csv", id = "tail_worker_id"),
    stop("Unknown targeted v2 stage.", call. = FALSE))
}

app_joint_pr2_worker_dir <- function(root, stage, id) {
  file.path(root, paste0(stage, "_workers"), sprintf("worker_%05d", as.integer(id)))
}

app_joint_pr2_health <- function(root, stage) {
  spec <- app_joint_pr2_stage_spec(stage); path <- file.path(root, spec[["plan"]])
  if (!file.exists(path)) return(data.frame(stage = stage, expected = 0L, completed = 0L, failed = 0L,
    remaining = 0L, completion_fraction = NA_real_, status = "pending", stringsAsFactors = FALSE))
  plan <- app_read_csv(path); ids <- plan[[spec[["id"]]]]
  dirs <- vapply(ids, function(id) app_joint_pr2_worker_dir(root, stage, id), character(1L))
  done <- file.exists(file.path(dirs, "DONE")) & file.exists(file.path(dirs, "artifact_manifest.csv"))
  failed <- file.exists(file.path(dirs, "FAILED")) | file.exists(file.path(dirs, "failure.csv"))
  status <- if (any(failed)) "failed" else if (all(done)) "complete" else if (!any(done)) "ready" else "running"
  data.frame(stage = stage, expected = length(ids), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), completion_fraction = mean(done), status = status, stringsAsFactors = FALSE)
}

app_joint_pr2_prepare <- function(root = app_joint_pr2_default_root()) {
  contract <- app_joint_pr2_read_contract(); axes <- app_joint_pr2_read_axes(); registry <- app_joint_pr_read_registry()
  root <- normalizePath(root, mustWork = FALSE)
  if (dir.exists(root) && length(list.files(root, all.files = TRUE, no.. = TRUE))) stop("Refusing to overwrite a nonempty v2 root.", call. = FALSE)
  app_ensure_dir(root); app_ensure_dir(file.path(root, "fixtures")); app_ensure_dir(file.path(root, "parity_workers")); app_ensure_dir(file.path(root, "ridge_workers"))
  dgp <- app_joint_qdesn_load_simulation_registry(); candidates <- fixtures <- ridge_plans <- parity_plans <- list()
  ridge_id <- parity_id <- 0L
  authority <- app_joint_pr_authoritative_anchors()
  for (ii in seq_len(nrow(registry))) {
    family <- registry[ii, , drop = FALSE]; scenario <- family$scenario_id[[1L]]
    candidate <- app_joint_pr2_candidates(scenario, contract, axes); candidates[[ii]] <- candidate
    parity <- candidate[candidate$candidate_role == "authoritative_v2_parity_anchor", , drop = FALSE]
    authority_row <- authority[authority$scenario_id == scenario, , drop = FALSE]
    sc <- dgp[dgp$scenario_id == scenario, , drop = FALSE]
    for (replicate_id in seq_len(contract$calibration_replicates)) {
      seed <- as.integer(family$calibration_seed_base[[1L]]) + replicate_id - 1L
      sc_rep <- sc; sc_rep$seed <- seed; sc_rep$seed_role <- sprintf("targeted_v2_selection_rep%02d", replicate_id)
      fixture <- app_joint_qdesn_fixture_from_registry_row(sc_rep); fixture$registry_row <- sc_rep
      selector <- app_joint_pure_selector_fixture(fixture, contract)
      path <- file.path(root, "fixtures", sprintf("%02d_%s_rep%02d.rds", ii, scenario, replicate_id))
      saveRDS(selector, path, version = 3L, compress = "xz")
      fixtures[[length(fixtures) + 1L]] <- data.frame(scenario_id = scenario, replicate_id = replicate_id,
        dgp_seed = seed, fixture_path = normalizePath(path, mustWork = TRUE), size_bytes = file.info(path)$size,
        sha256 = app_sha256_file(path), protected_rows_persisted = 0L, stringsAsFactors = FALSE)
      jobs <- candidate; jobs$replicate_id <- replicate_id; jobs$dgp_seed <- seed; jobs$fixture_path <- normalizePath(path, mustWork = TRUE)
      jobs$worker_id <- seq.int(ridge_id + 1L, ridge_id + nrow(jobs)); ridge_id <- ridge_id + nrow(jobs)
      ridge_plans[[length(ridge_plans) + 1L]] <- jobs
      parity$replicate_id <- replicate_id; parity$dgp_seed <- seed; parity$fixture_path <- normalizePath(path, mustWork = TRUE)
      parity$rhs_tau0 <- authority_row$rhs_tau0[[1L]]; parity$expected_calibration_acrps <- authority_row$calibration_acrps_mean[[1L]]
      parity$parity_worker_id <- parity_id <- parity_id + 1L
      parity_plans[[length(parity_plans) + 1L]] <- parity
    }
  }
  candidate <- app_bind_rows_fill(candidates); fixture <- app_bind_rows_fill(fixtures)
  ridge_plan <- app_bind_rows_fill(ridge_plans); parity_plan <- app_bind_rows_fill(parity_plans)
  expected <- data.frame(scenarios = 2L, parity_workers = 6L, ridge_candidates = nrow(candidate),
    ridge_workers = nrow(ridge_plan), seed_robustness_workers = 600L, coarse_rhs_workers = 2400L,
    maximum_refined_rhs_workers = 144L, median_al_workers = 72L, maximum_tail_al_workers = 60L,
    maximum_total_workers = 9426L, automatic_stop_after = contract$automatic_stop_after, stringsAsFactors = FALSE)
  if (nrow(candidate) != 2048L || nrow(ridge_plan) != 6144L || nrow(parity_plan) != 6L ||
      any(fixture$protected_rows_persisted != 0L)) stop("Targeted v2 preparation cardinality gate failed.", call. = FALSE)
  files <- c(
    frozen_contract = app_write_csv(contract$table, file.path(root, "frozen_contract.csv")),
    frozen_axes = app_write_csv(axes$table, file.path(root, "frozen_axes.csv")),
    frozen_registry = app_write_csv(registry, file.path(root, "frozen_registry.csv")),
    authoritative_anchors = app_write_csv(authority, file.path(root, "authoritative_anchors.csv")),
    candidate_registry = app_write_csv(candidate, file.path(root, "ridge_candidate_registry.csv")),
    fixture_manifest = app_write_csv(fixture, file.path(root, "fixture_manifest.csv")),
    parity_worker_plan = app_write_csv(parity_plan, file.path(root, "parity_worker_plan.csv")),
    ridge_worker_plan = app_write_csv(ridge_plan, file.path(root, "ridge_worker_plan.csv")),
    expected_work = app_write_csv(expected, file.path(root, "expected_work.csv")),
    source_git_state = app_write_csv(app_joint_shared_git_state(), file.path(root, "source_git_state.csv")))
  readiness <- data.frame(status = "READY_FOR_EXACT_PARITY_SENTINEL", expected_parity_workers = 6L,
    protected_rows_used_for_selection = 0L, article_fixture_used = FALSE, downstream_auto_launch = FALSE,
    stringsAsFactors = FALSE)
  files <- c(files, readiness = app_write_csv(readiness, file.path(root, "launch_readiness.csv")))
  app_joint_shared_write_manifest(root, files)
  list(root = root, expected = expected, readiness = readiness)
}

app_joint_pr2_attach_metadata <- function(summary, row) {
  extra <- setdiff(names(row), names(summary))
  if (length(extra)) cbind(summary, row[, extra, drop = FALSE]) else summary
}

app_joint_pr2_recursive_pair <- function(design, fixture, median_fit, target_fit, target_tau, contract) {
  cal <- design$calibration_local; blocks <- split(cal, ceiling(seq_along(cal) / contract$calibration_max_lead))
  median_pred <- target_pred <- rep(NA_real_, length(cal)); cursor <- 0L
  for (block in blocks) {
    origin_local <- min(block) - 1L; origin_full <- design$row_meta$full_time_index[[origin_local]]
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
      median_pred[[cursor]] <- as.numeric(app_joint_qdesn_predict_fit(median_fit, z, contract$median_tau))[[1L]]
      target_pred[[cursor]] <- as.numeric(app_joint_qdesn_predict_fit(target_fit, z, target_tau))[[1L]]
      history[[tt]] <- median_pred[[cursor]]
    }
  }
  if (cursor != length(cal) || any(!is.finite(c(median_pred, target_pred)))) stop("Recursive AL pair is incomplete.", call. = FALSE)
  list(median = median_pred, target = target_pred, calibration_local = cal)
}

app_joint_pr2_gaussian_fit <- function(design, row, contract) {
  tr <- design$train_local
  ridge <- app_glofas_normal_ridge_fit(design$X[tr, , drop = FALSE], design$y[tr],
    ridge_tau2 = contract$ridge_tau2, intercept_var = contract$intercept_variance,
    sigma_a = contract$sigma_shape, sigma_b = contract$sigma_rate)
  warm <- app_joint_shared_ridge_warm_start(ridge, row, design)
  app_glofas_normal_rhs_fit(design$X[tr, , drop = FALSE], design$y[tr], warm,
    tau0 = as.numeric(row$rhs_tau0[[1L]]), max_iter = contract$rhs_max_iter,
    min_iter = contract$rhs_min_iter, tol = contract$rhs_tolerance)
}

app_joint_pr2_quantile_init <- function(gaussian, design, tau, contract) {
  qcontract <- list(alpha_prior_sd_multiplier = contract$alpha_prior_sd_multiplier,
    rhs_slab_variance = NA_real_, rhs_slab_fixed = FALSE, rhs_vb_inner = contract$rhs_vb_inner)
  app_joint_shared_quantile_gaussian_init(gaussian, design, tau, qcontract)
}

app_joint_pr2_fit_al <- function(design, gaussian, tau, contract, init) {
  app_joint_qvp_fit_al_vb_tiny(
    y = design$y[design$train_local], Z = design$Z[design$train_local, , drop = FALSE], tau = tau,
    max_iter = contract$median_max_iter, tol = contract$median_tolerance, kappa = 1,
    tau0 = gaussian$rhs_tau0, zeta2 = app_joint_shared_quantile_resolve_zeta2(gaussian,
      list(rhs_slab_variance = NA_real_)), slab_fixed = FALSE,
    a_sigma = contract$a_sigma, b_sigma = contract$b_sigma,
    alpha_prior_mean = init$alpha_mean, alpha_prior_sd = init$alpha_prior_sd,
    alpha_min_spacing = 0, max_dense_dim = contract$max_readout_dimension,
    rhs_vb_inner = contract$rhs_vb_inner, rhs_freeze_iters = contract$rhs_freeze_iters, init = init)
}

app_joint_pr2_score_median <- function(fixture, row, contract) {
  started <- Sys.time(); design <- app_joint_pure_build_design(fixture, row, contract, selector = TRUE)
  gaussian <- app_joint_pr2_gaussian_fit(design, row, contract); init0 <- app_joint_pr2_quantile_init(gaussian, design, contract$median_tau, contract)
  init <- list(beta_mean = init0$beta_mean, beta_cov = init0$beta_cov, alpha_mean = init0$alpha_mean,
    sigma_mean = init0$sigma_mean, rhs_state = list(anchor = init0$rhs_state$anchor), iterations_completed = 0L,
    alpha_prior_sd = init0$alpha_prior_sd)
  fit <- app_joint_pr2_fit_al(design, gaussian, contract$median_tau, contract, init)
  forecast <- app_joint_pr_recursive_median(design, fixture, fit, contract); cal <- forecast$calibration_local
  error <- forecast$pred - design$y[cal]; oracle <- forecast$pred - design$true_q[cal, match(contract$median_tau, design$tau)]
  summary <- cbind(row, design$diagnostic, data.frame(status = "completed", method = "independent_median_al_vb",
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

app_joint_pr2_score_tail <- function(root, fixture, row, contract) {
  started <- Sys.time(); design <- app_joint_pure_build_design(fixture, row, contract, selector = TRUE)
  gaussian <- app_joint_pr2_gaussian_fit(design, row, contract); target_tau <- as.numeric(row$target_tau[[1L]])
  init0 <- app_joint_pr2_quantile_init(gaussian, design, target_tau, contract)
  median_plan <- app_read_csv(file.path(root, "median_al_worker_plan.csv"))
  median_row <- median_plan[median_plan$scenario_id == row$scenario_id[[1L]] &
    median_plan$candidate_id == row$candidate_id[[1L]] &
    abs(median_plan$rhs_tau0 - row$rhs_tau0[[1L]]) < 1e-14 &
    median_plan$replicate_id == row$replicate_id[[1L]], , drop = FALSE]
  if (nrow(median_row) != 1L) stop("Tail worker cannot identify its median parent.", call. = FALSE)
  median_path <- file.path(app_joint_pr2_worker_dir(root, "median_al", median_row$median_worker_id[[1L]]), "fit_initializer.rds")
  if (!file.exists(median_path)) stop("Tail worker median parent is incomplete.", call. = FALSE)
  median_fit <- readRDS(median_path)
  init <- median_fit; init$alpha_mean <- init0$alpha_mean
  init$sigma_mean <- pmax(as.numeric(init$sigma_mean), as.numeric(init0$sigma_mean))
  init$alpha_prior_sd <- init0$alpha_prior_sd; init$iterations_completed <- 0L
  fit <- app_joint_pr2_fit_al(design, gaussian, target_tau, contract, init)
  forecast <- app_joint_pr2_recursive_pair(design, fixture, median_fit, fit, target_tau, contract)
  cal <- forecast$calibration_local; error <- forecast$target - design$y[cal]
  oracle <- forecast$target - design$true_q[cal, match(target_tau, design$tau)]
  summary <- cbind(row, design$diagnostic, data.frame(status = "completed", method = "independent_tail_al_vb",
    hard_gate_status = if (all(is.finite(c(forecast$target, fit$beta_mean, fit$alpha_mean, fit$sigma_mean)))) "pass" else "fail",
    tail_check_loss_mean = mean(app_check_loss(design$y[cal], forecast$target, target_tau)),
    calibration_mae = mean(abs(error)), calibration_rmse = sqrt(mean(error^2)),
    calibration_oracle_tail_mae = mean(abs(oracle)), calibration_oracle_tail_rmse = sqrt(mean(oracle^2)),
    converged = isTRUE(fit$converged), convergence_status = if (isTRUE(fit$converged)) "pass" else "review_max_iter",
    iterations = as.integer(fit$iterations_completed %||% fit$iterations %||% NA_integer_),
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")), stringsAsFactors = FALSE))
  detail <- data.frame(calibration_row = seq_along(cal), full_time_index = design$row_meta$full_time_index[cal],
    y = design$y[cal], pred_median = forecast$median, pred_target = forecast$target,
    target_tau = target_tau, check_loss = app_check_loss(design$y[cal], forecast$target, target_tau),
    oracle_target = design$true_q[cal, match(target_tau, design$tau)], stringsAsFactors = FALSE)
  list(summary = summary, detail = detail, fit = app_joint_shared_quantile_compact_fit(fit))
}

app_joint_pr2_run_worker <- function(root, stage, id) {
  spec <- app_joint_pr2_stage_spec(stage); root <- normalizePath(root, mustWork = TRUE)
  plan <- app_read_csv(file.path(root, spec[["plan"]])); row <- plan[as.integer(plan[[spec[["id"]]]]) == as.integer(id), , drop = FALSE]
  if (nrow(row) != 1L) stop("Targeted v2 worker ID is not unique.", call. = FALSE)
  out <- app_joint_pr2_worker_dir(root, stage, id)
  if (file.exists(file.path(out, "DONE")) && file.exists(file.path(out, "artifact_manifest.csv"))) return(invisible(out))
  app_ensure_dir(out); contract <- app_joint_pr2_read_contract(file.path(root, "frozen_contract.csv")); fixture <- readRDS(row$fixture_path[[1L]])
  result <- tryCatch({
    if (stage == "median_al") app_joint_pr2_score_median(fixture, row, contract)
    else if (stage == "tail_al") app_joint_pr2_score_tail(root, fixture, row, contract)
    else app_joint_pure_score_fit(fixture, row, contract, method = if (stage %in% c("ridge", "seed_ridge")) "ridge" else "rhs")
  }, error = function(e) e)
  if (inherits(result, "error")) {
    app_write_csv(cbind(row, data.frame(status = "failed", error_message = conditionMessage(result), stringsAsFactors = FALSE)),
      file.path(out, "failure.csv")); writeLines("failed", file.path(out, "FAILED")); return(invisible(out))
  }
  result$summary <- app_joint_pr2_attach_metadata(result$summary, row)
  paths <- c(summary = app_write_csv(result$summary, file.path(out, "summary.csv")),
    calibration_detail = app_write_csv(result$detail, file.path(out, "calibration_detail.csv")))
  if (stage %in% c("median_al", "tail_al")) {
    fit_path <- file.path(out, "fit_initializer.rds"); saveRDS(result$fit, fit_path, version = 3L, compress = "xz")
    paths <- c(paths, fit_initializer = fit_path)
  } else if (nrow(result$trace)) paths <- c(paths, vb_trace = app_write_csv(result$trace, file.path(out, "vb_trace.csv")))
  app_joint_shared_write_manifest(out, paths); writeLines("completed", file.path(out, "DONE")); invisible(out)
}

app_joint_pr2_collect <- function(root, stage) {
  health <- app_joint_pr2_health(root, stage)
  if (health$completed[[1L]] != health$expected[[1L]] || health$failed[[1L]] != 0L) stop(sprintf("Targeted v2 %s is incomplete.", stage), call. = FALSE)
  paths <- list.files(file.path(root, paste0(stage, "_workers")), pattern = "summary[.]csv$", recursive = TRUE, full.names = TRUE)
  out <- app_bind_rows_fill(lapply(paths, app_read_csv))
  if (nrow(out) != health$expected[[1L]] || any(out$status != "completed")) stop("Targeted v2 summaries violate completion gates.", call. = FALSE)
  out
}

app_joint_pr2_finalize_parity <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); contract <- app_joint_pr2_read_contract(file.path(root, "frozen_contract.csv"))
  scores <- app_joint_pr2_collect(root, "parity")
  rows <- lapply(split(scores, scores$scenario_id), function(x) data.frame(scenario_id = x$scenario_id[[1L]],
    expected_calibration_acrps = x$expected_calibration_acrps[[1L]], observed_calibration_acrps = mean(x$calibration_acrps_mean),
    relative_difference = abs(mean(x$calibration_acrps_mean) - x$expected_calibration_acrps[[1L]]) /
      max(abs(x$expected_calibration_acrps[[1L]]), 1e-12), stringsAsFactors = FALSE))
  audit <- app_bind_rows_fill(rows); audit$status <- ifelse(audit$relative_difference <= contract$parity_relative_tolerance, "pass", "fail")
  if (any(audit$status != "pass")) stop("Exact authoritative parity sentinel failed.", call. = FALSE)
  paths <- c(scores = app_write_csv(scores, file.path(root, "parity_scores_by_replicate.csv")),
    audit = app_write_csv(audit, file.path(root, "parity_reproduction_audit.csv")))
  app_joint_shared_write_manifest(root, paths, filename = "parity_artifact_manifest.csv")
  audit
}

app_joint_pr2_diversity_key <- function(x) {
  lag_band <- cut(x$response_lags, c(-Inf, 12, 45, 120, Inf), labels = c("short", "medium", "long", "very_long"))
  budget_band <- cut(x$retained_state_budget, c(-Inf, 96, 300, Inf), labels = c("small", "medium", "large"))
  paste(x$D, lag_band, budget_band, sub("^targeted_v2_([^_]+).*$", "\\1", x$candidate_role), sep = "|")
}

app_joint_pr2_finalize_ridge <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); contract <- app_joint_pr2_read_contract(file.path(root, "frozen_contract.csv"))
  scores <- app_joint_pr2_collect(root, "ridge"); aggregate <- app_joint_pr_aggregate_gaussian(scores)
  frontier <- app_bind_rows_fill(lapply(split(aggregate, aggregate$scenario_id), function(x) {
    x <- x[x$hard_gate_status == "pass", , drop = FALSE]
    x <- x[order(x$calibration_acrps_mean, x$calibration_acrps_worst_rep, x$calibration_acrps_between_rep_sd, x$candidate_id), , drop = FALSE]
    parity <- x[x$candidate_role == "authoritative_v2_parity_anchor", , drop = FALSE]
    nonparity <- x[x$candidate_role != "authoritative_v2_parity_anchor", , drop = FALSE]
    numerical <- head(nonparity, contract$numerical_shortlist_count)
    remaining <- nonparity[!nonparity$candidate_id %in% numerical$candidate_id, , drop = FALSE]
    remaining$diversity_key <- app_joint_pr2_diversity_key(remaining)
    diverse <- app_bind_rows_fill(lapply(split(remaining, remaining$diversity_key), function(z) z[1L, , drop = FALSE]))
    diverse <- diverse[order(diverse$calibration_acrps_mean, diverse$candidate_id), , drop = FALSE]
    diverse <- head(diverse, contract$diversity_shortlist_count); diverse$diversity_key <- NULL
    out <- app_bind_rows_fill(list(parity, numerical, diverse)); out$ridge_advancement_rank <- seq_len(nrow(out))
    if (nrow(out) != contract$seed_advance_count || sum(out$candidate_role == "authoritative_v2_parity_anchor") != 1L) {
      stop("Targeted v2 diversified ridge frontier is malformed.", call. = FALSE)
    }
    out
  }))
  fixtures <- unique(app_read_csv(file.path(root, "ridge_worker_plan.csv"))[, c("scenario_id", "replicate_id", "dgp_seed", "fixture_path")])
  extra_seeds <- setdiff(contract$robustness_reservoir_seeds, contract$canonical_reservoir_seed)
  plan <- merge(frontier, data.frame(seed_resample = extra_seeds), by = NULL)
  plan$reservoir_seed <- as.integer(plan$seed_resample); plan$seed_resample <- NULL
  plan$base_candidate_id <- plan$candidate_id
  plan$candidate_id <- paste0(plan$base_candidate_id, "__seed_", plan$reservoir_seed)
  plan$architecture_signature <- vapply(seq_len(nrow(plan)), function(ii) app_joint_pure_architecture_signature(plan[ii, , drop = FALSE]), character(1L))
  plan <- merge(plan, fixtures, by = "scenario_id", all.x = TRUE)
  plan <- plan[order(plan$scenario_id, plan$ridge_advancement_rank, plan$reservoir_seed, plan$replicate_id), , drop = FALSE]
  plan$seed_worker_id <- seq_len(nrow(plan))
  if (nrow(plan) != 600L) stop("Targeted seed-robustness plan must contain 600 workers.", call. = FALSE)
  app_write_csv(scores, file.path(root, "ridge_scores_by_replicate.csv")); app_write_csv(aggregate, file.path(root, "ridge_candidate_aggregate.csv"))
  app_write_csv(frontier, file.path(root, "ridge_diverse_top50_by_scenario.csv")); app_write_csv(plan, file.path(root, "seed_ridge_worker_plan.csv"))
  app_ensure_dir(file.path(root, "seed_ridge_workers")); list(frontier = frontier, seed_plan = plan)
}

app_joint_pr2_finalize_seed <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); contract <- app_joint_pr2_read_contract(file.path(root, "frozen_contract.csv"))
  alternate <- app_joint_pr2_collect(root, "seed_ridge"); canonical <- app_read_csv(file.path(root, "ridge_scores_by_replicate.csv"))
  frontier <- app_read_csv(file.path(root, "ridge_diverse_top50_by_scenario.csv"))
  canonical <- canonical[canonical$candidate_id %in% frontier$candidate_id, , drop = FALSE]
  canonical$base_candidate_id <- canonical$candidate_id; alternate$base_candidate_id <- alternate$base_candidate_id
  seed_scores <- app_bind_rows_fill(list(canonical, alternate))
  seed_groups <- split(seed_scores, paste(seed_scores$scenario_id, seed_scores$base_candidate_id, seed_scores$reservoir_seed, sep = "::"))
  seed_aggregate <- app_bind_rows_fill(lapply(seed_groups, function(x) data.frame(
    scenario_id = x$scenario_id[[1L]], base_candidate_id = x$base_candidate_id[[1L]], reservoir_seed = x$reservoir_seed[[1L]],
    candidate_role = x$candidate_role[[1L]], calibration_acrps_mean = mean(x$calibration_acrps_mean),
    calibration_acrps_sd = stats::sd(x$calibration_acrps_mean), calibration_acrps_worst_rep = max(x$calibration_acrps_mean),
    stringsAsFactors = FALSE)))
  registry <- app_read_csv(file.path(root, "ridge_candidate_registry.csv"))
  robust <- app_bind_rows_fill(lapply(split(seed_aggregate, paste(seed_aggregate$scenario_id, seed_aggregate$base_candidate_id)), function(x) {
    base <- registry[registry$scenario_id == x$scenario_id[[1L]] & registry$candidate_id == x$base_candidate_id[[1L]], , drop = FALSE]
    x <- x[order(x$calibration_acrps_mean, x$reservoir_seed), , drop = FALSE]
    chosen <- if (base$candidate_role[[1L]] == "authoritative_v2_parity_anchor") {
      x[x$reservoir_seed == contract$canonical_reservoir_seed, , drop = FALSE]
    } else x[ceiling(nrow(x) / 2), , drop = FALSE]
    base$reservoir_seed <- chosen$reservoir_seed[[1L]]
    base$architecture_signature <- app_joint_pure_architecture_signature(base)
    cbind(base, data.frame(seed_panel_mean_acrps = mean(x$calibration_acrps_mean),
      seed_panel_sd_acrps = stats::sd(x$calibration_acrps_mean), seed_panel_worst_acrps = max(x$calibration_acrps_mean),
      chosen_seed_acrps = chosen$calibration_acrps_mean[[1L]], seed_selection_policy = if (base$candidate_role[[1L]] ==
        "authoritative_v2_parity_anchor") "exact_authority_seed" else "median_performing_seed", stringsAsFactors = FALSE))
  }))
  robust <- robust[order(robust$scenario_id, robust$seed_panel_mean_acrps, robust$seed_panel_worst_acrps, robust$candidate_id), , drop = FALSE]
  fixtures <- unique(app_read_csv(file.path(root, "ridge_worker_plan.csv"))[, c("scenario_id", "replicate_id", "dgp_seed", "fixture_path")])
  plan <- merge(robust, data.frame(rhs_tau0 = contract$rhs_tau0_grid), by = NULL)
  plan <- merge(plan, fixtures, by = "scenario_id", all.x = TRUE)
  plan <- plan[order(plan$scenario_id, plan$seed_panel_mean_acrps, -plan$rhs_tau0, plan$replicate_id), , drop = FALSE]
  plan$rhs_worker_id <- seq_len(nrow(plan)); plan$rhs_candidate_id <- paste(plan$candidate_id, plan$rhs_tau0, plan$replicate_id, sep = "__")
  if (nrow(plan) != 2400L) stop("Targeted coarse RHS plan must contain 2400 workers.", call. = FALSE)
  app_write_csv(seed_scores, file.path(root, "seed_robustness_scores_by_replicate.csv")); app_write_csv(seed_aggregate, file.path(root, "seed_robustness_aggregate.csv"))
  app_write_csv(robust, file.path(root, "seed_robust_top50_by_scenario.csv")); app_write_csv(plan, file.path(root, "rhs_worker_plan.csv"))
  app_ensure_dir(file.path(root, "rhs_workers")); list(robust = robust, rhs_plan = plan)
}

app_joint_pr2_best_unique <- function(aggregate, n, include_parity = TRUE, parity_tau0 = NULL) {
  x <- aggregate[order(aggregate$calibration_acrps_mean, aggregate$calibration_acrps_worst_rep,
    aggregate$calibration_acrps_between_rep_sd, -aggregate$convergence_fraction, aggregate$candidate_id), , drop = FALSE]
  parity <- x[x$candidate_role == "authoritative_v2_parity_anchor", , drop = FALSE]
  nonparity <- x[x$candidate_role != "authoritative_v2_parity_anchor", , drop = FALSE]
  nonparity <- nonparity[!duplicated(nonparity$candidate_id), , drop = FALSE]
  if (include_parity) {
    if (!is.null(parity_tau0) && "rhs_tau0" %in% names(parity)) {
      parity <- parity[abs(parity$rhs_tau0 - parity_tau0) <= 1e-14 * pmax(1, abs(parity_tau0)), , drop = FALSE]
    } else {
      parity <- parity[!duplicated(parity$candidate_id), , drop = FALSE]
    }
  }
  out <- if (include_parity) app_bind_rows_fill(list(parity, head(nonparity, n - 1L))) else head(x, n)
  if (nrow(out) != n || (include_parity && sum(out$candidate_role == "authoritative_v2_parity_anchor") != 1L)) {
    stop("Targeted unique shortlist is malformed.", call. = FALSE)
  }
  out
}

app_joint_pr2_finalize_rhs <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); contract <- app_joint_pr2_read_contract(file.path(root, "frozen_contract.csv"))
  scores <- app_joint_pr2_collect(root, "rhs"); aggregate <- app_joint_pr_aggregate_gaussian(scores)
  authority <- app_read_csv(file.path(root, "authoritative_anchors.csv"))
  shortlist <- app_bind_rows_fill(lapply(split(aggregate, aggregate$scenario_id), function(x) {
    parity_tau0 <- authority$rhs_tau0[authority$scenario_id == x$scenario_id[[1L]]]
    app_joint_pr2_best_unique(x, n = contract$refinement_candidate_count, include_parity = TRUE,
      parity_tau0 = parity_tau0)
  }))
  neighbors <- app_bind_rows_fill(lapply(seq_len(nrow(shortlist)), function(ii) {
    row <- shortlist[ii, , drop = FALSE]; tau <- as.numeric(row$rhs_tau0[[1L]])
    values <- unique(pmin(contract$refinement_max_tau0, pmax(contract$refinement_min_tau0,
      c(tau / contract$refinement_factor, tau * contract$refinement_factor))))
    values <- values[!values %in% contract$rhs_tau0_grid]
    if (!length(values)) return(NULL)
    app_bind_rows_fill(lapply(values, function(value) {
      candidate <- row
      candidate$rhs_tau0 <- value
      candidate
    }))
  }))
  fixtures <- unique(app_read_csv(file.path(root, "rhs_worker_plan.csv"))[, c("scenario_id", "replicate_id", "dgp_seed", "fixture_path")])
  plan <- merge(neighbors, fixtures, by = "scenario_id", all.x = TRUE)
  plan <- plan[order(plan$scenario_id, plan$candidate_id, plan$rhs_tau0, plan$replicate_id), , drop = FALSE]
  plan$rhs_refine_worker_id <- seq_len(nrow(plan)); plan$rhs_candidate_id <- paste(plan$candidate_id, plan$rhs_tau0, plan$replicate_id, sep = "__")
  if (nrow(plan) > 144L) stop("Targeted adaptive RHS plan exceeds its bound.", call. = FALSE)
  app_write_csv(scores, file.path(root, "rhs_scores_by_replicate.csv")); app_write_csv(aggregate, file.path(root, "rhs_coarse_candidate_aggregate.csv"))
  app_write_csv(shortlist, file.path(root, "rhs_refinement_shortlist.csv")); app_write_csv(plan, file.path(root, "rhs_refine_worker_plan.csv"))
  app_ensure_dir(file.path(root, "rhs_refine_workers")); list(shortlist = shortlist, refinement_plan = plan)
}

app_joint_pr2_finalize_rhs_refine <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); contract <- app_joint_pr2_read_contract(file.path(root, "frozen_contract.csv"))
  coarse_scores <- app_read_csv(file.path(root, "rhs_scores_by_replicate.csv")); refine_scores <- app_joint_pr2_collect(root, "rhs_refine")
  scores <- app_bind_rows_fill(list(coarse_scores, refine_scores)); aggregate <- app_joint_pr_aggregate_gaussian(scores)
  authority <- app_read_csv(file.path(root, "authoritative_anchors.csv"))
  selected <- app_bind_rows_fill(lapply(split(aggregate, aggregate$scenario_id), function(x) {
    parity_tau0 <- authority$rhs_tau0[authority$scenario_id == x$scenario_id[[1L]]]
    app_joint_pr2_best_unique(x, n = contract$median_candidate_count, include_parity = TRUE,
      parity_tau0 = parity_tau0)
  }))
  selected$rhs_selection_rank <- ave(selected$calibration_acrps_mean, selected$scenario_id,
    FUN = function(z) rank(z, ties.method = "first"))
  fixtures <- unique(app_read_csv(file.path(root, "rhs_worker_plan.csv"))[, c("scenario_id", "replicate_id", "dgp_seed", "fixture_path")])
  plan <- merge(selected, fixtures, by = "scenario_id", all.x = TRUE)
  plan <- plan[order(plan$scenario_id, plan$rhs_selection_rank, plan$replicate_id), , drop = FALSE]
  plan$median_worker_id <- seq_len(nrow(plan)); plan$median_tau <- contract$median_tau
  if (nrow(plan) != 72L) stop("Targeted median AL plan must contain 72 workers.", call. = FALSE)
  app_write_csv(scores, file.path(root, "rhs_all_scores_by_replicate.csv")); app_write_csv(aggregate, file.path(root, "rhs_all_candidate_aggregate.csv"))
  app_write_csv(selected, file.path(root, "rhs_diverse_top12_for_median_al.csv")); app_write_csv(plan, file.path(root, "median_al_worker_plan.csv"))
  app_ensure_dir(file.path(root, "median_al_workers")); list(selected = selected, median_plan = plan)
}

app_joint_pr2_median_aggregate <- function(scores) {
  keys <- c(app_joint_pure_candidate_columns(), "rhs_tau0", "rhs_selection_rank")
  groups <- split(scores, paste(scores$scenario_id, scores$candidate_id, format(scores$rhs_tau0, scientific = TRUE), sep = "::"))
  app_bind_rows_fill(lapply(groups, function(x) cbind(x[1L, keys, drop = FALSE], data.frame(
    replicate_count = nrow(x), finite_fraction = mean(x$hard_gate_status == "pass"),
    convergence_fraction = mean(app_as_bool_vec(x$converged)), median_check_loss_mean = mean(x$median_check_loss_mean),
    median_check_loss_between_rep_sd = stats::sd(x$median_check_loss_mean),
    median_check_loss_worst_rep = max(x$median_check_loss_mean), calibration_mae_mean = mean(x$calibration_mae),
    calibration_oracle_median_mae_mean = mean(x$calibration_oracle_median_mae), stringsAsFactors = FALSE))))
}

app_joint_pr2_finalize_median <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); contract <- app_joint_pr2_read_contract(file.path(root, "frozen_contract.csv"))
  scores <- app_joint_pr2_collect(root, "median_al"); aggregate <- app_joint_pr2_median_aggregate(scores)
  finalists <- app_bind_rows_fill(lapply(split(aggregate, aggregate$scenario_id), function(x) {
    x <- x[x$finite_fraction == 1, , drop = FALSE]
    x <- x[order(x$median_check_loss_mean, x$median_check_loss_worst_rep, x$median_check_loss_between_rep_sd,
      -x$convergence_fraction, x$candidate_id), , drop = FALSE]
    best <- head(x, contract$tail_candidate_count); parity <- x[x$candidate_role == "authoritative_v2_parity_anchor", , drop = FALSE]
    out <- app_bind_rows_fill(list(best, parity[!parity$candidate_id %in% best$candidate_id, , drop = FALSE]))
    out$tail_advancement_rank <- seq_len(nrow(out)); out
  }))
  fixtures <- unique(app_read_csv(file.path(root, "median_al_worker_plan.csv"))[, c("scenario_id", "replicate_id", "dgp_seed", "fixture_path")])
  plan <- merge(finalists, data.frame(target_tau = contract$tail_quantiles), by = NULL)
  plan <- merge(plan, fixtures, by = "scenario_id", all.x = TRUE)
  plan <- plan[order(plan$scenario_id, plan$tail_advancement_rank, plan$target_tau, plan$replicate_id), , drop = FALSE]
  plan$tail_worker_id <- seq_len(nrow(plan))
  if (nrow(plan) > 60L || nrow(plan) < 48L) stop("Targeted tail AL plan cardinality is outside its frozen bound.", call. = FALSE)
  app_write_csv(scores, file.path(root, "median_al_scores_by_replicate.csv")); app_write_csv(aggregate, file.path(root, "median_al_candidate_aggregate.csv"))
  app_write_csv(finalists, file.path(root, "median_al_tail_finalists.csv")); app_write_csv(plan, file.path(root, "tail_al_worker_plan.csv"))
  app_ensure_dir(file.path(root, "tail_al_workers")); list(finalists = finalists, tail_plan = plan)
}

app_joint_pr2_finalize_tail <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); contract <- app_joint_pr2_read_contract(file.path(root, "frozen_contract.csv"))
  median_scores <- app_read_csv(file.path(root, "median_al_scores_by_replicate.csv")); tail_scores <- app_joint_pr2_collect(root, "tail_al")
  finalists <- app_read_csv(file.path(root, "median_al_tail_finalists.csv"))
  keys <- c("scenario_id", "candidate_id", "rhs_tau0", "replicate_id")
  median_scores <- median_scores[median_scores$candidate_id %in% finalists$candidate_id, c(keys, "median_check_loss_mean"), drop = FALSE]
  lower <- tail_scores[abs(tail_scores$target_tau - contract$tail_quantiles[[1L]]) < 1e-12, c(keys, "tail_check_loss_mean"), drop = FALSE]
  upper <- tail_scores[abs(tail_scores$target_tau - contract$tail_quantiles[[2L]]) < 1e-12, c(keys, "tail_check_loss_mean"), drop = FALSE]
  names(lower)[names(lower) == "tail_check_loss_mean"] <- "lower_check_loss_mean"
  names(upper)[names(upper) == "tail_check_loss_mean"] <- "upper_check_loss_mean"
  matched <- merge(merge(median_scores, lower, by = keys), upper, by = keys)
  matched$three_quantile_weighted_check_score <- contract$proxy_weights[[1L]] * matched$lower_check_loss_mean +
    contract$proxy_weights[[2L]] * matched$median_check_loss_mean + contract$proxy_weights[[3L]] * matched$upper_check_loss_mean
  groups <- split(matched, paste(matched$scenario_id, matched$candidate_id, format(matched$rhs_tau0, scientific = TRUE), sep = "::"))
  aggregate <- app_bind_rows_fill(lapply(groups, function(x) data.frame(scenario_id = x$scenario_id[[1L]],
    candidate_id = x$candidate_id[[1L]], rhs_tau0 = x$rhs_tau0[[1L]], replicate_count = nrow(x),
    score_mean = mean(x$three_quantile_weighted_check_score), score_sd = stats::sd(x$three_quantile_weighted_check_score),
    score_worst_rep = max(x$three_quantile_weighted_check_score), lower_check_loss_mean = mean(x$lower_check_loss_mean),
    median_check_loss_mean = mean(x$median_check_loss_mean), upper_check_loss_mean = mean(x$upper_check_loss_mean),
    stringsAsFactors = FALSE)))
  aggregate <- merge(aggregate, finalists[, c("scenario_id", "candidate_id", "candidate_role", "architecture_signature")],
    by = c("scenario_id", "candidate_id"), all.x = TRUE)
  decision <- app_bind_rows_fill(lapply(split(aggregate, aggregate$scenario_id), function(x) {
    x <- x[order(x$score_mean, x$score_worst_rep, x$score_sd, x$candidate_id), , drop = FALSE]
    parity <- x[x$candidate_role == "authoritative_v2_parity_anchor", , drop = FALSE]
    winner <- x[1L, , drop = FALSE]
    winner$parity_score_mean <- parity$score_mean[[1L]]
    winner$mean_gain_vs_parity <- parity$score_mean[[1L]] - winner$score_mean[[1L]]
    winner$promotion_eligible <- winner$mean_gain_vs_parity > 0
    winner$decision <- if (winner$promotion_eligible) "RETAIN_FOR_SEVEN_QUANTILE_CONFIRMATION" else "KEEP_CURRENT_AUTHORITY"
    winner
  }))
  files <- c(
    tail_scores = app_write_csv(tail_scores, file.path(root, "tail_al_scores_by_replicate.csv")),
    matched = app_write_csv(matched, file.path(root, "three_quantile_matched_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "three_quantile_candidate_aggregate.csv")),
    decision = app_write_csv(decision, file.path(root, "three_quantile_selection_decision.csv")))
  status <- data.frame(status = "THREE_QUANTILE_AL_TRANSFER_REVIEW_COMPLETE_NO_AUTOMATIC_PROMOTION",
    scenarios = nrow(decision), promotion_eligible_scenarios = sum(app_as_bool_vec(decision$promotion_eligible)),
    protected_rows_used_for_selection = 0L, seven_quantile_launched = FALSE, joint_launched = FALSE,
    exal_launched = FALSE, mcmc_launched = FALSE, completed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    stringsAsFactors = FALSE)
  files <- c(files, status = app_write_csv(status, file.path(root, "final_status.csv")))
  manifest <- app_joint_shared_write_manifest(root, files, filename = "final_artifact_manifest.csv")
  verification <- app_joint_shared_verify_manifest(root, manifest)
  if (!all(verification$verified)) stop("Targeted v2 final manifest failed verification.", call. = FALSE)
  app_write_csv(verification, file.path(root, "final_artifact_manifest_verification.csv"))
  list(status = status, decision = decision, aggregate = aggregate)
}
