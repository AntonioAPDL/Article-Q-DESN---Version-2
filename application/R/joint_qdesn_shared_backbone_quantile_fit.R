# Quantile continuation from a frozen scenario-specific Gaussian RHS backbone.

app_joint_shared_quantile_contract_path <- function() {
  app_path("application/config/joint_qdesn_shared_backbone_quantile_contract_v1.csv")
}

app_joint_shared_quantile_default_root <- function() {
  app_path("application/cache/joint_qdesn_shared_backbone_quantile_pilot_20260906")
}

app_joint_shared_quantile_default_parent <- function() {
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_shared_backbone_pilot_20260906/application/cache/joint_qdesn_shared_backbone_pilot_20260906"
}

app_joint_shared_quantile_read_contract <- function(
  path = app_joint_shared_quantile_contract_path()
) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("section", "name", "value", "type", "description"),
    "shared-backbone quantile contract")
  if (anyDuplicated(tab$name)) stop("Quantile continuation contract names must be unique.", call. = FALSE)
  get <- function(name) {
    row <- tab[tab$name == name, , drop = FALSE]
    if (nrow(row) != 1L) stop(sprintf("Missing unique quantile contract field '%s'.", name), call. = FALSE)
    as.character(row$value[[1L]])
  }
  get_optional <- function(name, default = "") {
    row <- tab[tab$name == name, , drop = FALSE]
    if (!nrow(row)) return(default)
    if (nrow(row) != 1L) stop(sprintf("Non-unique optional quantile contract field '%s'.", name), call. = FALSE)
    as.character(row$value[[1L]])
  }
  tau <- as.numeric(strsplit(get("quantile_grid"), ";", fixed = TRUE)[[1L]])
  out <- list(
    table = tab, path = normalizePath(path, mustWork = TRUE), version = get("contract_version"),
    parent_head = get("parent_head"),
    parent_final_manifest_sha256 = get("parent_final_manifest_sha256"),
    parent_selected_sha256 = get("parent_selected_sha256"),
    parent_decision_sha256 = get("parent_decision_sha256"),
    parent_git_state_sha256 = get_optional("parent_git_state_sha256"),
    pilot_scenario = get("pilot_scenario"), tau = tau,
    evaluation_replicates = as.integer(get("evaluation_replicates")),
    evaluation_seed_base = as.integer(get("evaluation_seed_base")),
    selection_policy = get("selection_policy"),
    origin_stride = as.integer(get("origin_stride")), max_lead = as.integer(get("max_lead")),
    ridge_tau2 = as.numeric(get("ridge_tau2")), intercept_variance = as.numeric(get("intercept_variance")),
    sigma_shape = as.numeric(get("sigma_shape")), sigma_rate = as.numeric(get("sigma_rate")),
    gaussian_rhs_max_iter = as.integer(get("rhs_max_iter")),
    gaussian_rhs_min_iter = as.integer(get("rhs_min_iter")),
    gaussian_rhs_tolerance = as.numeric(get("rhs_tolerance")),
    al_max_iter = as.integer(get("al_max_iter")), exal_max_iter = as.integer(get("exal_max_iter")),
    vb_tolerance = as.numeric(get("vb_tolerance")), rhs_vb_inner = as.integer(get("rhs_vb_inner")),
    rhs_freeze_iters = as.integer(get("rhs_freeze_iters")),
    a_sigma = as.numeric(get("a_sigma")), b_sigma = as.numeric(get("b_sigma")),
    alpha_prior_sd_multiplier = as.numeric(get("alpha_prior_sd_multiplier")),
    alpha_min_spacing = as.numeric(get("alpha_min_spacing")),
    max_dense_dim = as.integer(get("max_dense_dim")), exal_vb_method = get("exal_vb_method"),
    gamma_init_policy = get("gamma_init_policy"), max_workers = as.integer(get("max_workers")),
    blas_threads = as.integer(get("blas_threads")), nice_level = as.integer(get("nice_level")),
    require_finite_outputs = identical(tolower(get("require_finite_outputs")), "true"),
    require_zero_contract_crossings = identical(tolower(get("require_zero_contract_crossings")), "true"),
    allow_max_iter_review = identical(tolower(get("allow_max_iter_review")), "true"),
    protected_selection_forbidden = identical(tolower(get("protected_selection_forbidden")), "true")
  )
  if (!identical(tau, sort(unique(tau))) || any(!is.finite(tau)) || any(tau <= 0 | tau >= 1)) {
    stop("Quantile continuation grid must be strictly increasing in (0,1).", call. = FALSE)
  }
  if (out$max_workers != 10L || out$evaluation_replicates < 1L || out$origin_stride != out$max_lead) {
    stop("Quantile continuation runtime or forecast geometry is malformed.", call. = FALSE)
  }
  out
}

app_joint_shared_quantile_parent_files <- function(parent_dir) {
  c(
    final_manifest = file.path(parent_dir, "final_artifact_manifest.csv"),
    selected_backbone = file.path(parent_dir, "selected_shared_backbone.csv"),
    selection_decision = file.path(parent_dir, "shared_backbone_selection_decision.csv"),
    source_git_state = file.path(parent_dir, "source_git_state.csv")
  )
}

app_joint_shared_quantile_verify_parent <- function(parent_dir, contract) {
  parent_dir <- normalizePath(parent_dir, mustWork = TRUE)
  files <- app_joint_shared_quantile_parent_files(parent_dir)
  if (any(!file.exists(files))) stop("Parent shared-backbone freeze is incomplete.", call. = FALSE)
  observed <- vapply(files, app_sha256_file, character(1L))
  expected <- c(
    final_manifest = contract$parent_final_manifest_sha256,
    selected_backbone = contract$parent_selected_sha256,
    selection_decision = contract$parent_decision_sha256,
    source_git_state = if (nzchar(contract$parent_git_state_sha256))
      contract$parent_git_state_sha256 else app_sha256_file(files[["source_git_state"]])
  )
  parent_manifest <- app_joint_shared_verify_manifest(parent_dir, files[["final_manifest"]])
  out <- data.frame(
    source = names(files), path = normalizePath(files, mustWork = TRUE),
    expected_sha256 = unname(expected[names(files)]), observed_sha256 = unname(observed),
    hash_verified = unname(observed) == unname(expected[names(files)]), stringsAsFactors = FALSE
  )
  out$nested_manifest_verified <- c(all(parent_manifest$verified), NA, NA, NA)
  if (any(!out$hash_verified) || !all(parent_manifest$verified)) {
    stop("Parent shared-backbone freeze failed hash verification.", call. = FALSE)
  }
  selected <- app_read_csv(files[["selected_backbone"]])
  decision <- app_read_csv(files[["selection_decision"]])
  source_git_state <- app_read_csv(files[["source_git_state"]])
  if (nrow(selected) != 1L || nrow(decision) != 1L ||
      selected$scenario_id[[1L]] != contract$pilot_scenario ||
      decision$status[[1L]] != "SHARED_BACKBONE_SELECTED_NOT_YET_QUANTILE_FIT" ||
      decision$selected_candidate_id[[1L]] != selected$candidate_id[[1L]]) {
    stop("Parent selected-backbone decision is internally inconsistent.", call. = FALSE)
  }
  if (nrow(source_git_state) != 1L ||
      !identical(as.character(source_git_state$head[[1L]]), contract$parent_head)) {
    stop("Parent source Git HEAD does not match the frozen quantile contract.", call. = FALSE)
  }
  list(verification = out, selected = selected, decision = decision)
}

app_joint_shared_quantile_full_design <- function(fixture, candidate, contract) {
  roles <- fixture$detailed_split$role
  keep <- roles %in% c("desn_washout", "fit", "validation")
  raw <- as.matrix(fixture$Z[keep, , drop = FALSE])
  storage.mode(raw) <- "double"
  meta <- fixture$detailed_split[keep, , drop = FALSE]
  fit_local <- which(meta$role == "fit")
  validation_local <- which(meta$role == "validation")
  washout_local <- which(meta$role == "desn_washout")
  if (length(washout_local) != 500L || length(fit_local) != 500L || length(validation_local) != 1000L ||
      any(!is.finite(raw))) stop("Full continuation fixture geometry is malformed.", call. = FALSE)

  scale_params <- app_joint_exqdesn_phase151_scale_params(raw, seq_len(nrow(raw)) %in% fit_local)
  raw_scaled <- app_qdesn_reservoir_scale_inputs(raw, scale_params = scale_params)$X
  cls <- as.character(candidate$design_class[[1L]])
  state_raw <- matrix(numeric(0), nrow(raw), 0L)
  reservoir <- NULL
  if (!identical(cls, "direct")) {
    D <- as.integer(candidate$D[[1L]])
    reservoir <- app_qdesn_generate_article_reservoir(
      list(reservoir = list(
        D = D, n = as.integer(app_joint_shared_parse_num_vec(candidate$n[[1L]])),
        n_tilde = as.integer(app_joint_shared_parse_num_vec(candidate$n_tilde[[1L]])),
        m = ncol(raw_scaled), alpha = app_joint_shared_parse_num_vec(candidate$alpha[[1L]]),
        rho = app_joint_shared_parse_num_vec(candidate$rho[[1L]]),
        pi_w = app_joint_shared_parse_num_vec(candidate$pi_w[[1L]]),
        pi_in = app_joint_shared_parse_num_vec(candidate$pi_in[[1L]]),
        w_dist = "uniform", in_dist = "uniform", act_f = "tanh", act_k = "identity"
      )), seed = as.integer(candidate$reservoir_seed[[1L]]), m_input = ncol(raw_scaled)
    )
    reservoir_meta <- list(
      standardize_inputs = FALSE, lag_center = rep(0, ncol(raw_scaled)),
      lag_scale = rep(1, ncol(raw_scaled)), input_bound = "none",
      win_scale_global = as.numeric(candidate$input_scale[[1L]]),
      win_scale_bias = as.numeric(candidate$input_scale[[1L]])
    )
    state_raw <- app_qdesn_roll_article_reservoir(raw_scaled, reservoir, reservoir_meta)$X_all
  }
  if (ncol(state_raw)) {
    center <- colMeans(state_raw[fit_local, , drop = FALSE])
    scale <- apply(state_raw[fit_local, , drop = FALSE], 2L, stats::sd)
    scale[!is.finite(scale) | scale <= 1e-10] <- 1
    states <- sweep(sweep(state_raw, 2L, center, "-"), 2L, scale, "/")
    colnames(states) <- paste0("reservoir_", sprintf("%04d", seq_len(ncol(states))))
  } else {
    center <- scale <- numeric(0)
    states <- state_raw
  }
  Z <- switch(cls, direct = raw, reservoir = states, hybrid = cbind(raw, states),
    stop(sprintf("Unknown selected design class '%s'.", cls), call. = FALSE))
  colnames(Z) <- make.unique(colnames(Z))
  X <- cbind(`(Intercept)` = 1, Z)

  origins <- app_joint_qdesn_forecast_origin_plan_rows(fixture)
  if (nrow(origins)) {
    forecast_map <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(origins)), function(ii) {
      row <- origins[ii, , drop = FALSE]
      full <- seq.int(row$target_start_full_time_index[[1L]], row$target_end_full_time_index[[1L]])
      data.frame(origin_index = row$origin_index[[1L]], horizon = seq_along(full),
        full_time_index = full, stringsAsFactors = FALSE)
    }))
  } else forecast_map <- data.frame()
  if (!nrow(forecast_map) || anyDuplicated(forecast_map$full_time_index)) {
    stop("No-refit forecast-origin map must contain unique scored targets.", call. = FALSE)
  }
  score_local <- match(forecast_map$full_time_index, meta$full_time_index)
  if (anyNA(score_local) || any(!score_local %in% validation_local)) {
    stop("Forecast-origin targets do not map to validation rows.", call. = FALSE)
  }
  y <- fixture$y[keep]
  true_q <- fixture$true_q[keep, , drop = FALSE]
  mu <- fixture$mu[keep]
  sigma <- fixture$sigma[keep]
  out <- list(
    scenario_id = fixture$scenario_id, seed = fixture$seed, seed_role = fixture$seed_role,
    candidate_id = candidate$candidate_id[[1L]], architecture_signature = candidate$architecture_signature[[1L]],
    design_class = cls, tau = fixture$tau, X = X, Z = Z, y = y, true_q = true_q,
    mu = mu, sigma = sigma, row_meta = meta, fit_local = fit_local,
    validation_local = validation_local, score_local = score_local, forecast_map = forecast_map,
    scale_params = scale_params, reservoir = reservoir, state_center = center, state_scale = scale,
    dgp_row = fixture$registry_row %||% NULL
  )
  out$design_fingerprint <- app_joint_qvp_sha256_text(paste(
    candidate$architecture_signature[[1L]], paste(colnames(Z), collapse = ";"),
    paste(format(Z[fit_local, , drop = FALSE], digits = 16), collapse = ";"), sep = "|"
  ))
  if (any(!is.finite(c(X, y, true_q, mu, sigma))) || any(sigma <= 0)) {
    stop("Full continuation design contains invalid values.", call. = FALSE)
  }
  out
}

app_joint_shared_quantile_compact_fit <- function(fit) {
  keep <- c(
    "beta_mean", "beta_cov", "alpha_mean", "sigma_mean", "gamma_mean",
    "sigma_shape", "sigma_rate", "rhs_state", "rhs_prior_summary", "tau",
    "converged", "iterations_completed", "inference_method_id", "fit_structure",
    "objective_diagnostics", "manifest"
  )
  out <- fit[intersect(keep, names(fit))]
  out$type <- "joint_shared_quantile_compact_v1"
  out
}

app_joint_shared_quantile_gaussian_init <- function(gaussian_fit, design, tau, contract) {
  tau <- app_joint_qvp_validate_tau_grid(tau)
  if (length(gaussian_fit$beta_mean) != ncol(design$X) || colnames(design$X)[[1L]] != "(Intercept)") {
    stop("Gaussian-to-quantile adapter requires one leading intercept.", call. = FALSE)
  }
  p <- ncol(design$Z)
  slopes <- as.numeric(gaussian_fit$beta_mean[-1L])
  slope_cov <- as.matrix(gaussian_fit$beta_cov[-1L, -1L, drop = FALSE])
  residual_sd <- sqrt(as.numeric(gaussian_fit$sigma2_mean))
  if (length(slopes) != p || !all(dim(slope_cov) == c(p, p)) ||
      !is.finite(residual_sd) || residual_sd <= 0) stop("Gaussian initializer is malformed.", call. = FALSE)
  alpha <- as.numeric(gaussian_fit$beta_mean[[1L]] + residual_sd * stats::qnorm(tau))
  beta <- rep(slopes, times = length(tau))
  beta_cov <- as.matrix(Matrix::bdiag(replicate(length(tau), slope_cov, simplify = FALSE)))
  fit_location <- as.numeric(design$Z[design$fit_local, , drop = FALSE] %*% slopes)
  fit_q <- matrix(fit_location, nrow = length(design$fit_local), ncol = length(tau)) +
    matrix(alpha, nrow = length(design$fit_local), ncol = length(tau), byrow = TRUE)
  y_fit <- design$y[design$fit_local]
  sigma <- vapply(seq_along(tau), function(k) {
    max(mean(app_check_loss(y_fit, fit_q[, k], tau[[k]])), residual_sd * 1e-4, 1e-8)
  }, numeric(1L))
  zeta2 <- if (!is.null(gaussian_fit$rhs_state$e_inv_zeta2) &&
      is.finite(gaussian_fit$rhs_state$e_inv_zeta2) && gaussian_fit$rhs_state$e_inv_zeta2 > 0) {
    1 / gaussian_fit$rhs_state$e_inv_zeta2
  } else Inf
  rhs_state <- app_joint_qvp_initialize_rhs_state(length(tau), p,
    tau0 = gaussian_fit$rhs_tau0, zeta2 = zeta2)
  rhs_state <- app_joint_qvp_update_rhs_vb_state(rhs_state, beta, beta_cov,
    K = length(tau), p = p, n_inner = contract$rhs_vb_inner)$state
  list(
    beta_mean = beta, beta_cov = beta_cov, alpha_mean = alpha, sigma_mean = sigma,
    rhs_state = rhs_state, tau = tau, residual_sd = residual_sd, zeta2 = zeta2,
    alpha_prior_sd = contract$alpha_prior_sd_multiplier * residual_sd,
    design_fingerprint = design$design_fingerprint, source = "full_window_gaussian_rhs_vb"
  )
}

app_joint_shared_quantile_continuation_order <- function(tau) {
  tau <- app_joint_qvp_validate_tau_grid(tau)
  expected <- c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)
  if (!identical(tau, expected)) stop("Pilot continuation graph requires the frozen seven-level grid.", call. = FALSE)
  data.frame(
    tau = expected,
    parent_tau = c(0.10, 0.25, 0.50, NA, 0.50, 0.75, 0.90),
    continuation_stage = c(4L, 3L, 2L, 1L, 2L, 3L, 4L),
    stringsAsFactors = FALSE
  )
}

app_joint_shared_quantile_job_plan <- function(contract) {
  reps <- seq_len(contract$evaluation_replicates)
  jobs <- list()
  add <- function(stage_order, stage_id, replicate_id, model_id, tau = NA_real_, parent_tau = NA_real_) {
    jobs[[length(jobs) + 1L]] <<- data.frame(
      stage_order = as.integer(stage_order), stage_id = stage_id,
      replicate_id = as.integer(replicate_id), model_id = model_id,
      tau = as.numeric(tau), parent_tau = as.numeric(parent_tau), stringsAsFactors = FALSE
    )
  }
  for (r in reps) add(1L, "gaussian_refit", r, "gaussian_rhs_initializer")
  continuation <- app_joint_shared_quantile_continuation_order(contract$tau)
  for (stage in sort(unique(continuation$continuation_stage))) {
    block <- continuation[continuation$continuation_stage == stage, , drop = FALSE]
    for (r in reps) for (k in seq_len(nrow(block))) {
      add(1L + stage, sprintf("independent_al_%02d", stage), r, "independent_qdesn_rhs",
        block$tau[[k]], block$parent_tau[[k]])
    }
  }
  for (r in reps) for (tau in contract$tau) add(6L, "independent_exal", r, "independent_exqdesn_rhs", tau, tau)
  for (r in reps) add(7L, "joint_al", r, "joint_qdesn_rhs")
  for (r in reps) add(8L, "joint_exal", r, "joint_exqdesn_rhs")
  out <- app_joint_qdesn_bind_rows(jobs)
  out$job_id <- seq_len(nrow(out))
  out <- out[, c("job_id", setdiff(names(out), "job_id")), drop = FALSE]
  if (nrow(out) != contract$evaluation_replicates * 17L) {
    stop("Quantile continuation job plan must contain 17 jobs per replicate.", call. = FALSE)
  }
  out
}

app_joint_shared_quantile_worker_dir <- function(root, job_id) {
  file.path(root, "workers", sprintf("worker_%04d", as.integer(job_id)))
}

app_joint_shared_quantile_find_job <- function(plan, replicate_id, model_id, tau = NA_real_) {
  keep <- plan$replicate_id == as.integer(replicate_id) & plan$model_id == model_id
  if (is.finite(tau)) keep <- keep & is.finite(plan$tau) & abs(plan$tau - tau) < 1e-12
  row <- plan[keep, , drop = FALSE]
  if (nrow(row) != 1L) stop("Could not resolve a unique continuation dependency.", call. = FALSE)
  row
}

app_joint_shared_quantile_dependency_rows <- function(plan, job) {
  r <- job$replicate_id[[1L]]
  model <- job$model_id[[1L]]
  if (model == "gaussian_rhs_initializer") return(plan[FALSE, , drop = FALSE])
  if (model == "independent_qdesn_rhs") {
    if (is.finite(job$parent_tau[[1L]])) {
      return(app_joint_shared_quantile_find_job(plan, r, model, job$parent_tau[[1L]]))
    }
    return(app_joint_shared_quantile_find_job(plan, r, "gaussian_rhs_initializer"))
  }
  if (model == "independent_exqdesn_rhs") {
    return(app_joint_shared_quantile_find_job(plan, r, "independent_qdesn_rhs", job$tau[[1L]]))
  }
  if (model == "joint_qdesn_rhs") {
    return(plan[plan$replicate_id == r & plan$model_id == "independent_qdesn_rhs", , drop = FALSE])
  }
  if (model == "joint_exqdesn_rhs") {
    return(plan[plan$replicate_id == r & plan$model_id %in% c("independent_exqdesn_rhs", "joint_qdesn_rhs"), , drop = FALSE])
  }
  stop("Unknown continuation model dependency.", call. = FALSE)
}

app_joint_shared_quantile_prepare <- function(
  out_dir = app_joint_shared_quantile_default_root(),
  parent_dir = app_joint_shared_quantile_default_parent(),
  contract_path = app_joint_shared_quantile_contract_path()
) {
  contract <- app_joint_shared_quantile_read_contract(contract_path)
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  if (dir.exists(out_dir) && length(list.files(out_dir, all.files = TRUE, no.. = TRUE))) {
    stop("Refusing to overwrite a nonempty quantile continuation output directory.", call. = FALSE)
  }
  app_ensure_dir(out_dir); app_ensure_dir(file.path(out_dir, "fixtures"));
  app_ensure_dir(file.path(out_dir, "designs")); app_ensure_dir(file.path(out_dir, "workers"))
  parent <- app_joint_shared_quantile_verify_parent(parent_dir, contract)
  selected <- parent$selected
  if (identical(contract$version, "joint_shared_backbone_quantile_v1") &&
      (abs(selected$rhs_tau0[[1L]] - 1) > 1e-12 || selected$design_class[[1L]] != "direct")) {
    stop("The frozen Regime Shift parent winner no longer matches the audited direct/tau0=1 package.", call. = FALSE)
  }
  if (!is.finite(selected$rhs_tau0[[1L]]) || selected$rhs_tau0[[1L]] <= 0 ||
      !selected$design_class[[1L]] %in% c("direct", "reservoir", "hybrid")) {
    stop("The selected family backbone has an invalid design class or RHS control.", call. = FALSE)
  }
  registry <- app_joint_qdesn_load_simulation_registry()
  sc <- registry[registry$scenario_id == contract$pilot_scenario, , drop = FALSE]
  if (nrow(sc) != 1L) stop("Pilot scenario is not unique in the simulation registry.", call. = FALSE)
  if (!identical(app_joint_qvp_parse_tau_spec(sc$tau_grid[[1L]]), contract$tau)) {
    stop("Simulation registry and continuation quantile grids differ.", call. = FALSE)
  }
  seeds <- contract$evaluation_seed_base + seq_len(contract$evaluation_replicates) - 1L
  fixture_rows <- design_rows <- list()
  for (r in seq_along(seeds)) {
    row <- sc
    row$seed <- seeds[[r]]
    row$seed_role <- sprintf("shared_backbone_quantile_protected_rep%02d", r)
    fixture <- app_joint_qdesn_fixture_from_registry_row(row)
    fixture$registry_row <- row
    design <- app_joint_shared_quantile_full_design(fixture, selected, contract)
    fixture_path <- file.path(out_dir, "fixtures", sprintf("rep_%02d.rds", r))
    design_path <- file.path(out_dir, "designs", sprintf("rep_%02d.rds", r))
    saveRDS(fixture, fixture_path, version = 3L, compress = "xz")
    saveRDS(design, design_path, version = 3L, compress = "xz")
    fixture_rows[[r]] <- data.frame(
      replicate_id = r, dgp_seed = seeds[[r]], fixture_path = normalizePath(fixture_path),
      size_bytes = as.numeric(file.info(fixture_path)$size), sha256 = app_sha256_file(fixture_path),
      selection_rows = 0L, protected_scoring_rows = length(design$score_local), stringsAsFactors = FALSE
    )
    design_rows[[r]] <- data.frame(
      replicate_id = r, design_path = normalizePath(design_path),
      design_fingerprint = design$design_fingerprint, design_class = design$design_class,
      p = ncol(design$Z), fit_rows = length(design$fit_local), validation_rows = length(design$validation_local),
      scored_forecast_rows = length(design$score_local), size_bytes = as.numeric(file.info(design_path)$size),
      sha256 = app_sha256_file(design_path), stringsAsFactors = FALSE
    )
  }
  plan <- app_joint_shared_quantile_job_plan(contract)
  fixture_manifest <- app_joint_qdesn_bind_rows(fixture_rows)
  design_manifest <- app_joint_qdesn_bind_rows(design_rows)
  plan <- merge(plan, fixture_manifest[, c("replicate_id", "dgp_seed", "fixture_path")], by = "replicate_id", all.x = TRUE)
  plan <- merge(plan, design_manifest[, c("replicate_id", "design_path", "design_fingerprint")], by = "replicate_id", all.x = TRUE)
  plan <- plan[order(plan$stage_order, plan$job_id), , drop = FALSE]
  plan <- plan[, c(
    "job_id", "stage_order", "stage_id", "replicate_id", "model_id", "tau", "parent_tau",
    "dgp_seed", "fixture_path", "design_path", "design_fingerprint"
  ), drop = FALSE]
  selected_snapshot <- file.path(out_dir, "selected_shared_backbone.csv")
  app_write_csv(selected, selected_snapshot)
  decision_snapshot <- file.path(out_dir, "parent_selection_decision.csv")
  app_write_csv(parent$decision, decision_snapshot)
  files <- c(
    frozen_contract = app_write_csv(contract$table, file.path(out_dir, "frozen_contract.csv")),
    parent_verification = app_write_csv(parent$verification, file.path(out_dir, "parent_source_verification.csv")),
    selected_backbone = selected_snapshot, parent_decision = decision_snapshot,
    fixture_manifest = app_write_csv(fixture_manifest, file.path(out_dir, "fixture_manifest.csv")),
    design_manifest = app_write_csv(design_manifest, file.path(out_dir, "design_manifest.csv")),
    worker_plan = app_write_csv(plan, file.path(out_dir, "worker_plan.csv")),
    source_git_state = app_write_csv(app_joint_shared_git_state(), file.path(out_dir, "source_git_state.csv"))
  )
  readiness <- data.frame(
    status = "READY_TO_LAUNCH_QUANTILE_CONTINUATION", scenario_id = contract$pilot_scenario,
    selected_candidate_id = selected$candidate_id[[1L]], selected_design_class = selected$design_class[[1L]],
    selected_gaussian_rhs_tau0 = selected$rhs_tau0[[1L]], evaluation_replicates = contract$evaluation_replicates,
    expected_jobs = nrow(plan), gaussian_jobs = sum(plan$model_id == "gaussian_rhs_initializer"),
    quantile_vb_jobs = sum(plan$model_id != "gaussian_rhs_initializer"), max_concurrent_workers = contract$max_workers,
    protected_rows_used_for_selection = 0L, article_fixture_used = FALSE, mcmc_launched = FALSE,
    stringsAsFactors = FALSE
  )
  files <- c(files, launch_readiness = app_write_csv(readiness, file.path(out_dir, "launch_readiness.csv")))
  writeLines(c(
    "# JOINT shared-backbone quantile continuation pilot", "",
    "This packet refits the frozen Regime Shift Gaussian RHS winner and uses it only to initialize four quantile VB models.",
    "Protected forecasts are evaluation-only. The pipeline does not tune, run MCMC, or modify article assets."
  ), file.path(out_dir, "README.md"))
  files <- c(files, readme = file.path(out_dir, "README.md"))
  app_joint_shared_write_manifest(out_dir, files)
  list(out_dir = out_dir, readiness = readiness, plan = plan)
}

app_joint_shared_quantile_gaussian_worker <- function(job, design, selected, contract) {
  fit_idx <- design$fit_local
  ridge <- app_glofas_normal_ridge_fit(
    design$X[fit_idx, , drop = FALSE], design$y[fit_idx],
    ridge_tau2 = contract$ridge_tau2, intercept_var = contract$intercept_variance,
    sigma_a = contract$sigma_shape, sigma_b = contract$sigma_rate
  )
  warm <- app_joint_shared_ridge_warm_start(ridge, selected, design)
  rhs <- app_glofas_normal_rhs_fit(
    design$X[fit_idx, , drop = FALSE], design$y[fit_idx], warm,
    tau0 = selected$rhs_tau0[[1L]], max_iter = contract$gaussian_rhs_max_iter,
    min_iter = contract$gaussian_rhs_min_iter, tol = contract$gaussian_rhs_tolerance
  )
  initializer <- app_joint_shared_quantile_gaussian_init(rhs, design, design$tau, contract)
  fit <- list(
    type = rhs$type, beta_mean = rhs$beta_mean, beta_cov = rhs$beta_cov,
    beta_var_diag = rhs$beta_var_diag, sigma_a = rhs$sigma_a, sigma_b = rhs$sigma_b,
    sigma2_mean = rhs$sigma2_mean, rhs_state = rhs$rhs_state, rhs_tau0 = rhs$rhs_tau0,
    converged = rhs$converged, iterations = rhs$iterations, final_delta = rhs$final_delta,
    trace = rhs$trace, initializer = initializer
  )
  pred <- list(
    tau = design$tau,
    qhat_fit = app_joint_qdesn_predict_fit(initializer, design$Z[fit_idx, , drop = FALSE], design$tau),
    qhat_validation = app_joint_qdesn_predict_fit(initializer, design$Z[design$validation_local, , drop = FALSE], design$tau)
  )
  list(fit = fit, prediction = pred, trace = rhs$trace,
    summary = data.frame(converged = rhs$converged, iterations = rhs$iterations,
      final_delta = rhs$final_delta, tau0 = rhs$rhs_tau0, zeta2_initializer = initializer$zeta2,
      alpha_prior_sd = initializer$alpha_prior_sd, stringsAsFactors = FALSE))
}

app_joint_shared_quantile_load_fit <- function(root, job) {
  path <- file.path(app_joint_shared_quantile_worker_dir(root, job$job_id[[1L]]), "fit_initializer.rds")
  if (!file.exists(path)) stop("Required continuation fit initializer is missing.", call. = FALSE)
  readRDS(path)
}

app_joint_shared_quantile_gaussian_job <- function(plan, replicate_id) {
  app_joint_shared_quantile_find_job(plan, replicate_id, "gaussian_rhs_initializer")
}

app_joint_shared_quantile_reset_init <- function(init) {
  init$iterations_completed <- 0L
  init
}

app_joint_shared_quantile_independent_al_worker <- function(root, job, plan, design, contract) {
  gaussian_job <- app_joint_shared_quantile_gaussian_job(plan, job$replicate_id[[1L]])
  gaussian <- app_joint_shared_quantile_load_fit(root, gaussian_job)
  target <- job$tau[[1L]]
  k <- match(target, design$tau)
  if (is.na(k)) stop("Independent AL target tau is outside the frozen grid.", call. = FALSE)
  if (is.finite(job$parent_tau[[1L]])) {
    parent_job <- app_joint_shared_quantile_find_job(plan, job$replicate_id[[1L]],
      "independent_qdesn_rhs", job$parent_tau[[1L]])
    init <- app_joint_shared_quantile_load_fit(root, parent_job)
    init$alpha_mean <- gaussian$initializer$alpha_mean[[k]]
    init$sigma_mean <- max(init$sigma_mean[[1L]], gaussian$initializer$sigma_mean[[k]])
  } else {
    init <- list(
      beta_mean = gaussian$initializer$beta_mean[((k - 1L) * ncol(design$Z) + 1L):(k * ncol(design$Z))],
      beta_cov = gaussian$initializer$beta_cov[((k - 1L) * ncol(design$Z) + 1L):(k * ncol(design$Z)),
        ((k - 1L) * ncol(design$Z) + 1L):(k * ncol(design$Z)), drop = FALSE],
      alpha_mean = gaussian$initializer$alpha_mean[[k]], sigma_mean = gaussian$initializer$sigma_mean[[k]],
      rhs_state = gaussian$initializer$rhs_state$anchor
    )
    init$rhs_state <- list(anchor = init$rhs_state)
  }
  init <- app_joint_shared_quantile_reset_init(init)
  fit <- app_joint_qvp_fit_al_vb_tiny(
    y = design$y[design$fit_local], Z = design$Z[design$fit_local, , drop = FALSE], tau = target,
    max_iter = contract$al_max_iter, tol = contract$vb_tolerance, kappa = 1,
    tau0 = gaussian$rhs_tau0, zeta2 = gaussian$initializer$zeta2,
    a_sigma = contract$a_sigma, b_sigma = contract$b_sigma,
    alpha_prior_mean = gaussian$initializer$alpha_mean[[k]],
    alpha_prior_sd = gaussian$initializer$alpha_prior_sd, alpha_min_spacing = 0,
    max_dense_dim = contract$max_dense_dim, rhs_vb_inner = contract$rhs_vb_inner,
    rhs_freeze_iters = contract$rhs_freeze_iters, init = init
  )
  list(fit = fit)
}

app_joint_shared_quantile_independent_exal_worker <- function(root, job, plan, design, contract) {
  al_job <- app_joint_shared_quantile_find_job(plan, job$replicate_id[[1L]],
    "independent_qdesn_rhs", job$tau[[1L]])
  al <- app_joint_shared_quantile_load_fit(root, al_job)
  gaussian <- app_joint_shared_quantile_load_fit(root,
    app_joint_shared_quantile_gaussian_job(plan, job$replicate_id[[1L]]))
  k <- match(job$tau[[1L]], design$tau)
  fit <- app_joint_exqdesn_fit_vb_dispatch(
    method_id = contract$exal_vb_method,
    y = design$y[design$fit_local], Z = design$Z[design$fit_local, , drop = FALSE], tau = job$tau[[1L]],
    max_iter = contract$exal_max_iter, tol = contract$vb_tolerance, kappa = 1,
    tau0 = gaussian$rhs_tau0, zeta2 = gaussian$initializer$zeta2,
    a_sigma = contract$a_sigma, b_sigma = contract$b_sigma,
    alpha_prior_mean = gaussian$initializer$alpha_mean[[k]],
    alpha_prior_sd = gaussian$initializer$alpha_prior_sd, alpha_min_spacing = 0,
    gamma_init = app_joint_qdesn_gamma_init_for_policy(job$tau[[1L]], list(gamma_init_policy = contract$gamma_init_policy)),
    max_dense_dim = contract$max_dense_dim, rhs_vb_inner = contract$rhs_vb_inner,
    rhs_freeze_iters = contract$rhs_freeze_iters, diagnostic_stride = 20L,
    quadrature_nodes = c(4L, 8L, 12L), quadrature_tolerance = 1e-5,
    init = app_joint_shared_quantile_reset_init(al)
  )
  list(fit = fit)
}

app_joint_shared_quantile_stack_independent <- function(
  root, plan, replicate_id, model_id, design, rhs_state = NULL, rhs_vb_inner = 10L
) {
  jobs <- plan[plan$replicate_id == replicate_id & plan$model_id == model_id, , drop = FALSE]
  jobs <- jobs[order(jobs$tau), , drop = FALSE]
  if (nrow(jobs) != length(design$tau) || !identical(as.numeric(jobs$tau), as.numeric(design$tau))) {
    stop("Independent component set is incomplete.", call. = FALSE)
  }
  fits <- lapply(seq_len(nrow(jobs)), function(ii) app_joint_shared_quantile_load_fit(root, jobs[ii, , drop = FALSE]))
  p <- ncol(design$Z); K <- length(design$tau)
  beta <- unlist(lapply(fits, `[[`, "beta_mean"), use.names = FALSE)
  cov <- as.matrix(Matrix::bdiag(lapply(fits, function(x) as.matrix(x$beta_cov))))
  out <- list(
    beta_mean = beta, beta_cov = cov,
    alpha_mean = vapply(fits, function(x) x$alpha_mean[[1L]], numeric(1L)),
    sigma_mean = vapply(fits, function(x) x$sigma_mean[[1L]], numeric(1L)),
    tau = design$tau, fits = fits
  )
  if (all(vapply(fits, function(x) length(x$gamma_mean %||% numeric()) == 1L, logical(1L)))) {
    out$gamma_mean <- vapply(fits, function(x) x$gamma_mean[[1L]], numeric(1L))
  }
  if (is.null(rhs_state)) {
    gaussian <- app_joint_shared_quantile_load_fit(root,
      app_joint_shared_quantile_gaussian_job(plan, replicate_id))
    rhs_state <- app_joint_qvp_initialize_rhs_state(K, p,
      tau0 = gaussian$rhs_tau0, zeta2 = gaussian$initializer$zeta2)
    rhs_state <- app_joint_qvp_update_rhs_vb_state(
      rhs_state, beta, cov, K, p, n_inner = as.integer(rhs_vb_inner)
    )$state
  }
  out$rhs_state <- rhs_state
  out$iterations_completed <- 0L
  out
}

app_joint_shared_quantile_joint_al_worker <- function(root, job, plan, design, contract) {
  gaussian <- app_joint_shared_quantile_load_fit(root,
    app_joint_shared_quantile_gaussian_job(plan, job$replicate_id[[1L]]))
  init <- app_joint_shared_quantile_stack_independent(root, plan, job$replicate_id[[1L]],
    "independent_qdesn_rhs", design, rhs_vb_inner = contract$rhs_vb_inner)
  fit <- app_joint_qvp_fit_al_vb_tiny(
    y = design$y[design$fit_local], Z = design$Z[design$fit_local, , drop = FALSE], tau = design$tau,
    max_iter = contract$al_max_iter, tol = contract$vb_tolerance, kappa = 1,
    tau0 = gaussian$rhs_tau0, zeta2 = gaussian$initializer$zeta2,
    a_sigma = contract$a_sigma, b_sigma = contract$b_sigma,
    alpha_prior_mean = gaussian$initializer$alpha_mean,
    alpha_prior_sd = gaussian$initializer$alpha_prior_sd,
    alpha_min_spacing = contract$alpha_min_spacing,
    max_dense_dim = contract$max_dense_dim, rhs_vb_inner = contract$rhs_vb_inner,
    rhs_freeze_iters = contract$rhs_freeze_iters, init = init
  )
  list(fit = fit)
}

app_joint_shared_quantile_joint_exal_worker <- function(root, job, plan, design, contract) {
  gaussian <- app_joint_shared_quantile_load_fit(root,
    app_joint_shared_quantile_gaussian_job(plan, job$replicate_id[[1L]]))
  joint_al_job <- app_joint_shared_quantile_find_job(plan, job$replicate_id[[1L]], "joint_qdesn_rhs")
  joint_al <- app_joint_shared_quantile_load_fit(root, joint_al_job)
  init <- app_joint_shared_quantile_stack_independent(root, plan, job$replicate_id[[1L]],
    "independent_exqdesn_rhs", design, rhs_state = joint_al$rhs_state,
    rhs_vb_inner = contract$rhs_vb_inner)
  fit <- app_joint_exqdesn_fit_vb_dispatch(
    method_id = contract$exal_vb_method,
    y = design$y[design$fit_local], Z = design$Z[design$fit_local, , drop = FALSE], tau = design$tau,
    max_iter = contract$exal_max_iter, tol = contract$vb_tolerance, kappa = 1,
    tau0 = gaussian$rhs_tau0, zeta2 = gaussian$initializer$zeta2,
    a_sigma = contract$a_sigma, b_sigma = contract$b_sigma,
    alpha_prior_mean = gaussian$initializer$alpha_mean,
    alpha_prior_sd = gaussian$initializer$alpha_prior_sd,
    alpha_min_spacing = contract$alpha_min_spacing,
    gamma_init = app_joint_qdesn_gamma_init_for_policy(design$tau, list(gamma_init_policy = contract$gamma_init_policy)),
    max_dense_dim = contract$max_dense_dim, rhs_vb_inner = contract$rhs_vb_inner,
    rhs_freeze_iters = contract$rhs_freeze_iters, diagnostic_stride = 20L,
    quadrature_nodes = c(4L, 8L, 12L), quadrature_tolerance = 1e-5, init = init
  )
  list(fit = fit)
}

app_joint_shared_quantile_trace_frame <- function(fit) {
  trace <- fit$trace %||% data.frame()
  if (!is.data.frame(trace)) trace <- as.data.frame(trace)
  trace
}

app_joint_shared_quantile_scale_trace_frame <- function(fit) {
  gamma <- fit$gamma_trace %||% NULL
  sigma <- fit$sigma_trace %||% NULL
  n <- max(if (is.null(gamma)) 0L else nrow(as.matrix(gamma)), if (is.null(sigma)) 0L else nrow(as.matrix(sigma)))
  if (!n) return(data.frame())
  rows <- list()
  if (!is.null(gamma)) {
    x <- as.matrix(gamma)
    rows[[length(rows) + 1L]] <- data.frame(iter = rep(seq_len(nrow(x)), ncol(x)),
      parameter = "gamma", quantile_index = rep(seq_len(ncol(x)), each = nrow(x)),
      value = as.numeric(x), stringsAsFactors = FALSE)
  }
  if (!is.null(sigma)) {
    x <- as.matrix(sigma)
    rows[[length(rows) + 1L]] <- data.frame(iter = rep(seq_len(nrow(x)), ncol(x)),
      parameter = "sigma", quantile_index = rep(seq_len(ncol(x)), each = nrow(x)),
      value = as.numeric(x), stringsAsFactors = FALSE)
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_shared_quantile_run_worker <- function(root, job_id) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_shared_quantile_read_contract(file.path(root, "frozen_contract.csv"))
  plan <- app_read_csv(file.path(root, "worker_plan.csv"))
  job <- plan[plan$job_id == as.integer(job_id), , drop = FALSE]
  if (nrow(job) != 1L) stop("Quantile continuation job_id is not unique.", call. = FALSE)
  out <- app_joint_shared_quantile_worker_dir(root, job_id)
  if (file.exists(file.path(out, "DONE")) && file.exists(file.path(out, "artifact_manifest.csv"))) return(invisible(out))
  dependencies <- app_joint_shared_quantile_dependency_rows(plan, job)
  if (nrow(dependencies)) {
    ready <- vapply(dependencies$job_id, function(id) file.exists(file.path(
      app_joint_shared_quantile_worker_dir(root, id), "DONE")), logical(1L))
    if (!all(ready)) stop("Quantile continuation dependency is not complete.", call. = FALSE)
  }
  selected <- app_read_csv(file.path(root, "selected_shared_backbone.csv"))
  design <- readRDS(job$design_path[[1L]])
  if (!identical(design$design_fingerprint, job$design_fingerprint[[1L]])) {
    stop("Worker design fingerprint does not match the frozen plan.", call. = FALSE)
  }
  tmp <- paste0(out, ".tmp_", Sys.getpid())
  unlink(tmp, recursive = TRUE, force = TRUE); dir.create(tmp, recursive = TRUE)
  started <- Sys.time()
  result <- tryCatch({
    if (job$model_id[[1L]] == "gaussian_rhs_initializer") {
      app_joint_shared_quantile_gaussian_worker(job, design, selected, contract)
    } else if (job$model_id[[1L]] == "independent_qdesn_rhs") {
      app_joint_shared_quantile_independent_al_worker(root, job, plan, design, contract)
    } else if (job$model_id[[1L]] == "independent_exqdesn_rhs") {
      app_joint_shared_quantile_independent_exal_worker(root, job, plan, design, contract)
    } else if (job$model_id[[1L]] == "joint_qdesn_rhs") {
      app_joint_shared_quantile_joint_al_worker(root, job, plan, design, contract)
    } else if (job$model_id[[1L]] == "joint_exqdesn_rhs") {
      app_joint_shared_quantile_joint_exal_worker(root, job, plan, design, contract)
    } else stop("Unknown quantile continuation model_id.", call. = FALSE)
  }, error = function(e) e)
  if (inherits(result, "error")) {
    app_ensure_dir(out)
    app_write_csv(cbind(job, data.frame(status = "failed", error_message = conditionMessage(result),
      runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")), stringsAsFactors = FALSE)),
      file.path(out, "failure.csv"))
    writeLines("failed", file.path(out, "FAILED")); unlink(tmp, recursive = TRUE, force = TRUE)
    stop(conditionMessage(result), call. = FALSE)
  }
  fit <- result$fit
  compact <- if (job$model_id[[1L]] == "gaussian_rhs_initializer") fit else app_joint_shared_quantile_compact_fit(fit)
  if (job$model_id[[1L]] == "gaussian_rhs_initializer") {
    prediction <- result$prediction
  } else {
    prediction <- list(
      tau = fit$tau,
      qhat_fit = app_joint_qdesn_predict_fit(fit, design$Z[design$fit_local, , drop = FALSE], fit$tau),
      qhat_validation = app_joint_qdesn_predict_fit(fit, design$Z[design$validation_local, , drop = FALSE], fit$tau)
    )
  }
  finite <- all(is.finite(c(compact$beta_mean, compact$alpha_mean, compact$sigma_mean,
    compact$gamma_mean %||% numeric(), prediction$qhat_fit, prediction$qhat_validation))) &&
    all(compact$sigma_mean > 0)
  if (!finite && contract$require_finite_outputs) stop("Worker produced nonfinite quantile output.", call. = FALSE)
  fit_path <- file.path(tmp, "fit_initializer.rds")
  prediction_path <- file.path(tmp, "prediction.rds")
  saveRDS(compact, fit_path, version = 3L, compress = "xz")
  saveRDS(prediction, prediction_path, version = 3L, compress = "xz")
  trace <- if (!is.null(result$trace)) result$trace else app_joint_shared_quantile_trace_frame(fit)
  trace_path <- file.path(tmp, "vb_trace.csv")
  app_write_csv(trace, trace_path)
  scale_trace <- app_joint_shared_quantile_scale_trace_frame(fit)
  scale_trace_path <- file.path(tmp, "scale_shape_trace.csv")
  app_write_csv(scale_trace, scale_trace_path)
  converged <- isTRUE(compact$converged %||% fit$converged)
  iterations <- as.integer(compact$iterations_completed %||% fit$iterations %||% nrow(trace))
  summary <- cbind(job[, c("job_id", "stage_order", "stage_id", "replicate_id", "model_id", "tau", "parent_tau")],
    data.frame(status = "completed", finite_output = finite, converged = converged,
      convergence_status = if (converged) "pass" else "review_max_iter",
      iterations = iterations, runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      design_fingerprint = design$design_fingerprint,
      initialization_source = if (job$model_id[[1L]] == "gaussian_rhs_initializer") "gaussian_ridge_full_window" else
        paste(unique(dependencies$model_id), collapse = ";"), stringsAsFactors = FALSE))
  if (!is.null(result$summary)) {
    extra <- result$summary[, setdiff(names(result$summary), names(summary)), drop = FALSE]
    summary <- cbind(summary, extra)
  }
  summary_path <- file.path(tmp, "summary.csv")
  app_write_csv(summary, summary_path)
  manifest <- data.frame(
    label = c("summary", "fit_initializer", "prediction", "vb_trace", "scale_shape_trace"),
    relative_path = c("summary.csv", "fit_initializer.rds", "prediction.rds", "vb_trace.csv", "scale_shape_trace.csv"),
    size_bytes = as.numeric(file.info(c(summary_path, fit_path, prediction_path, trace_path, scale_trace_path))$size),
    sha256 = vapply(c(summary_path, fit_path, prediction_path, trace_path, scale_trace_path), app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  app_write_csv(manifest, file.path(tmp, "artifact_manifest.csv"))
  writeLines("completed", file.path(tmp, "DONE"))
  if (dir.exists(out)) unlink(out, recursive = TRUE, force = TRUE)
  if (!file.rename(tmp, out)) stop("Could not atomically publish quantile worker output.", call. = FALSE)
  invisible(out)
}

app_joint_shared_quantile_health <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  plan <- app_read_csv(file.path(root, "worker_plan.csv"))
  dirs <- vapply(plan$job_id, function(id) app_joint_shared_quantile_worker_dir(root, id), character(1L))
  done <- file.exists(file.path(dirs, "DONE")) & file.exists(file.path(dirs, "artifact_manifest.csv"))
  failed <- file.exists(file.path(dirs, "FAILED")) | file.exists(file.path(dirs, "failure.csv"))
  data.frame(
    expected = nrow(plan), completed = sum(done), failed = sum(failed), remaining = sum(!done & !failed),
    completion_fraction = mean(done), status = if (all(done)) "complete" else if (any(failed)) "failed" else "running",
    stringsAsFactors = FALSE
  )
}

app_joint_shared_quantile_health_by_stage <- function(root) {
  plan <- app_read_csv(file.path(root, "worker_plan.csv"))
  rows <- lapply(split(plan, plan$stage_id), function(x) {
    dirs <- vapply(x$job_id, function(id) app_joint_shared_quantile_worker_dir(root, id), character(1L))
    done <- file.exists(file.path(dirs, "DONE")); failed <- file.exists(file.path(dirs, "FAILED"))
    data.frame(stage_order = x$stage_order[[1L]], stage_id = x$stage_id[[1L]], expected = nrow(x),
      completed = sum(done), failed = sum(failed), remaining = sum(!done & !failed), stringsAsFactors = FALSE)
  })
  out <- app_joint_qdesn_bind_rows(rows)
  out[order(out$stage_order, out$stage_id), , drop = FALSE]
}

app_joint_shared_quantile_prediction_matrix <- function(root, plan, replicate_id, model_id, window) {
  jobs <- plan[plan$replicate_id == replicate_id & plan$model_id == model_id, , drop = FALSE]
  if (!nrow(jobs)) stop("Prediction model jobs are absent.", call. = FALSE)
  if (model_id %in% c("independent_qdesn_rhs", "independent_exqdesn_rhs")) jobs <- jobs[order(jobs$tau), , drop = FALSE]
  predictions <- lapply(jobs$job_id, function(id) readRDS(file.path(
    app_joint_shared_quantile_worker_dir(root, id), "prediction.rds"))[[paste0("qhat_", window)]])
  if (length(predictions) == 1L) return(as.matrix(predictions[[1L]]))
  do.call(cbind, lapply(predictions, function(x) as.numeric(as.matrix(x)[, 1L])))
}

app_joint_shared_quantile_window_score <- function(design, qhat, idx, model_id, replicate_id, window) {
  qhat <- as.matrix(qhat)
  if (nrow(qhat) != length(idx) || ncol(qhat) != length(design$tau)) stop("Prediction matrix does not match scoring window.", call. = FALSE)
  contract_q <- app_joint_qdesn_apply_monotone_contract(qhat, design$tau)
  sc <- design$dgp_row
  if (is.null(sc) || nrow(sc) != 1L) stop("DGP registry row is missing from the frozen design.", call. = FALSE)
  score <- app_joint_qdesn_postscore_score_matrix(
    contract_q$qhat_contract, design$y[idx], design$mu[idx], design$sigma[idx],
    sc, design$tau, app_joint_shared_weights(design$tau)
  )
  truth_error <- contract_q$qhat_contract - design$true_q[idx, , drop = FALSE]
  check <- vapply(seq_along(design$tau), function(k) app_check_loss(
    design$y[idx], contract_q$qhat_contract[, k], design$tau[[k]]), numeric(length(idx)))
  data.frame(
    scenario_id = design$scenario_id, replicate_id = replicate_id, dgp_seed = design$seed,
    model_id = model_id, window = window, n_scored_rows = length(idx),
    dgp_integrated_acrps = score$dgp_integrated_acrps, realized_acrps = score$realized_acrps,
    check_loss_mean = mean(check), oracle_quantile_mae = mean(abs(truth_error)),
    oracle_quantile_rmse = sqrt(mean(truth_error^2)),
    raw_crossing_pairs = sum(contract_q$raw_crossing$n_crossing_pairs),
    contract_crossing_pairs = sum(contract_q$contract_crossing$n_crossing_pairs),
    n_adjusted_quantiles = contract_q$n_adjusted_quantiles,
    mean_abs_adjustment = contract_q$mean_abs_adjustment,
    max_abs_adjustment = contract_q$max_abs_adjustment, stringsAsFactors = FALSE
  )
}

app_joint_shared_quantile_finalize <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  health <- app_joint_shared_quantile_health(root)
  if (health$completed[[1L]] != health$expected[[1L]] || health$failed[[1L]] != 0L) {
    stop("Quantile continuation is not complete and failure-free.", call. = FALSE)
  }
  contract <- app_joint_shared_quantile_read_contract(file.path(root, "frozen_contract.csv"))
  plan <- app_read_csv(file.path(root, "worker_plan.csv"))
  summaries <- app_joint_qdesn_bind_rows(lapply(plan$job_id, function(id) app_read_csv(file.path(
    app_joint_shared_quantile_worker_dir(root, id), "summary.csv"))))
  if (nrow(summaries) != nrow(plan) || any(summaries$status != "completed") || any(!app_as_bool_vec(summaries$finite_output))) {
    stop("Worker summaries violate completion or finite-output gates.", call. = FALSE)
  }
  models <- c("independent_qdesn_rhs", "joint_qdesn_rhs", "independent_exqdesn_rhs", "joint_exqdesn_rhs")
  score_rows <- list()
  tau_rows <- list()
  for (r in seq_len(contract$evaluation_replicates)) {
    design <- readRDS(plan$design_path[plan$replicate_id == r][[1L]])
    for (model in models) {
      fit_q <- app_joint_shared_quantile_prediction_matrix(root, plan, r, model, "fit")
      validation_all <- app_joint_shared_quantile_prediction_matrix(root, plan, r, model, "validation")
      validation_position <- match(design$score_local, design$validation_local)
      forecast_q <- validation_all[validation_position, , drop = FALSE]
      score_rows[[length(score_rows) + 1L]] <- app_joint_shared_quantile_window_score(
        design, fit_q, design$fit_local, model, r, "fit")
      score_rows[[length(score_rows) + 1L]] <- app_joint_shared_quantile_window_score(
        design, forecast_q, design$score_local, model, r, "forecast")
      contract_forecast <- app_joint_qdesn_apply_monotone_contract(forecast_q, design$tau)$qhat_contract
      tau_rows[[length(tau_rows) + 1L]] <- app_joint_qdesn_bind_rows(lapply(seq_along(design$tau), function(k) {
        err <- contract_forecast[, k] - design$true_q[design$score_local, k]
        data.frame(scenario_id = design$scenario_id, replicate_id = r, model_id = model,
          tau = design$tau[[k]], check_loss_mean = mean(app_check_loss(design$y[design$score_local], contract_forecast[, k], design$tau[[k]])),
          oracle_quantile_mae = mean(abs(err)), oracle_quantile_rmse = sqrt(mean(err^2)), stringsAsFactors = FALSE)
      }))
    }
  }
  scores <- app_joint_qdesn_bind_rows(score_rows)
  by_tau <- app_joint_qdesn_bind_rows(tau_rows)
  groups <- split(scores, paste(scores$model_id, scores$window, sep = "__"))
  aggregate <- app_joint_qdesn_bind_rows(lapply(groups, function(x) data.frame(
    scenario_id = x$scenario_id[[1L]], model_id = x$model_id[[1L]], window = x$window[[1L]],
    replicates = nrow(x), dgp_integrated_acrps_mean = mean(x$dgp_integrated_acrps),
    dgp_integrated_acrps_sd = stats::sd(x$dgp_integrated_acrps), realized_acrps_mean = mean(x$realized_acrps),
    check_loss_mean = mean(x$check_loss_mean), oracle_quantile_mae_mean = mean(x$oracle_quantile_mae),
    oracle_quantile_rmse_mean = mean(x$oracle_quantile_rmse), raw_crossing_pairs = sum(x$raw_crossing_pairs),
    contract_crossing_pairs = sum(x$contract_crossing_pairs), max_abs_adjustment = max(x$max_abs_adjustment),
    stringsAsFactors = FALSE
  )))
  forecast <- aggregate[aggregate$window == "forecast", , drop = FALSE]
  contrasts <- app_joint_qdesn_bind_rows(lapply(c("al", "exal"), function(likelihood) {
    joint_id <- if (likelihood == "al") "joint_qdesn_rhs" else "joint_exqdesn_rhs"
    independent_id <- if (likelihood == "al") "independent_qdesn_rhs" else "independent_exqdesn_rhs"
    joint <- forecast[forecast$model_id == joint_id, , drop = FALSE]
    independent <- forecast[forecast$model_id == independent_id, , drop = FALSE]
    data.frame(likelihood = likelihood, joint_model_id = joint_id, independent_model_id = independent_id,
      joint_dgp_integrated_acrps = joint$dgp_integrated_acrps_mean,
      independent_dgp_integrated_acrps = independent$dgp_integrated_acrps_mean,
      joint_minus_independent = joint$dgp_integrated_acrps_mean - independent$dgp_integrated_acrps_mean,
      joint_improves = joint$dgp_integrated_acrps_mean < independent$dgp_integrated_acrps_mean,
      joint_raw_crossings = joint$raw_crossing_pairs, independent_raw_crossings = independent$raw_crossing_pairs,
      stringsAsFactors = FALSE)
  }))
  hard_fail <- any(!is.finite(scores$dgp_integrated_acrps)) ||
    (contract$require_zero_contract_crossings && any(scores$contract_crossing_pairs != 0L))
  decision <- data.frame(
    status = if (hard_fail) "VB_CONTINUATION_FAIL" else if (any(contrasts$joint_improves))
      "VB_COMPLETE_TARGETED_MCMC_REVIEW" else "VB_COMPLETE_NO_JOINT_GAIN_REVIEW",
    scenario_id = contract$pilot_scenario, selected_backbone_id = app_read_csv(file.path(root, "selected_shared_backbone.csv"))$candidate_id[[1L]],
    normal_models_are_article_comparators = FALSE, protected_rows_used_for_selection = 0L,
    quantile_models_completed = 4L, mcmc_launched = FALSE, article_assets_modified = FALSE,
    notes = "Gaussian ridge/RHS are initialization only; protected quantile scores are evaluation evidence.", stringsAsFactors = FALSE
  )
  worker_registry <- app_joint_qdesn_bind_rows(lapply(plan$job_id, function(id) {
    path <- file.path(app_joint_shared_quantile_worker_dir(root, id), "artifact_manifest.csv")
    data.frame(job_id = id, relative_path = file.path("workers", sprintf("worker_%04d", id), "artifact_manifest.csv"),
      size_bytes = as.numeric(file.info(path)$size), sha256 = app_sha256_file(path), stringsAsFactors = FALSE)
  }))
  files <- c(
    final_health = app_write_csv(health, file.path(root, "final_health.csv")),
    health_by_stage = app_write_csv(app_joint_shared_quantile_health_by_stage(root), file.path(root, "health_by_stage.csv")),
    worker_summary = app_write_csv(summaries, file.path(root, "worker_summary.csv")),
    score_by_replicate = app_write_csv(scores, file.path(root, "quantile_score_by_replicate.csv")),
    score_aggregate = app_write_csv(aggregate, file.path(root, "quantile_score_aggregate.csv")),
    forecast_by_tau = app_write_csv(by_tau, file.path(root, "forecast_score_by_tau.csv")),
    joint_independent_contrast = app_write_csv(contrasts, file.path(root, "joint_independent_contrast.csv")),
    decision = app_write_csv(decision, file.path(root, "quantile_continuation_decision.csv")),
    worker_artifact_registry = app_write_csv(worker_registry, file.path(root, "worker_artifact_registry.csv"))
  )
  app_joint_shared_write_manifest(root, files, filename = "final_artifact_manifest.csv")
  verification <- app_joint_shared_verify_manifest(root, file.path(root, "final_artifact_manifest.csv"))
  if (!all(verification$verified)) stop("Final quantile continuation manifest failed verification.", call. = FALSE)
  app_write_csv(verification, file.path(root, "final_manifest_verification.csv"))
  list(health = health, aggregate = aggregate, contrasts = contrasts, decision = decision)
}
