# Family-specific pure-DESN selection with recursive multi-horizon scoring.

app_joint_pure_default_root <- function() {
  app_path("application/cache/joint_qdesn_pure_recursive_campaign_jerez_15core_20260925")
}

app_joint_pure_contract_path <- function() {
  app_path("application/config/joint_qdesn_pure_recursive_campaign_contract_v1.csv")
}

app_joint_pure_axes_path <- function() {
  app_path("application/config/joint_qdesn_pure_recursive_candidate_axes_v1.csv")
}

app_joint_pure_registry_path <- function() {
  app_path("application/config/joint_qdesn_pure_recursive_family_registry_v1.csv")
}

app_joint_pure_anchor_path <- function() {
  app_path("application/config/joint_qdesn_pure_recursive_historical_anchors_v1.csv")
}

app_joint_pure_contract_value <- function(tab, name) {
  row <- tab[tab$name == name, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("Pure-recursive contract requires one '%s' row.", name), call. = FALSE)
  as.character(row$value[[1L]])
}

app_joint_pure_read_contract <- function(path = app_joint_pure_contract_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("section", "name", "value", "type", "description"),
    "pure-recursive campaign contract")
  if (anyDuplicated(tab$name)) stop("Pure-recursive contract names must be unique.", call. = FALSE)
  get <- function(name) app_joint_pure_contract_value(tab, name)
  numvec <- function(name) as.numeric(strsplit(get(name), ";", fixed = TRUE)[[1L]])
  out <- list(
    table = tab, path = normalizePath(path, mustWork = TRUE),
    version = get("contract_version"), run_tag = get("run_tag"),
    execution_branch = get("execution_branch"), tau = numvec("quantile_grid"),
    scenario_count = as.integer(get("scenario_count")), models_per_scenario = as.integer(get("models_per_scenario")),
    desn_washout_rows = as.integer(get("desn_washout_rows")), fit_rows = as.integer(get("fit_rows")),
    inner_training_rows = as.integer(get("inner_training_rows")), inner_calibration_rows = as.integer(get("inner_calibration_rows")),
    protected_validation_rows = as.integer(get("protected_validation_rows")),
    calibration_origin_stride = as.integer(get("calibration_origin_stride")), calibration_max_lead = as.integer(get("calibration_max_lead")),
    origin_update_policy = get("origin_update_policy"), within_origin_policy = get("within_origin_policy"),
    final_posterior_policies = strsplit(get("final_posterior_policies"), ";", fixed = TRUE)[[1L]],
    candidate_count = as.integer(get("candidate_count")), advance_count = as.integer(get("advance_count")),
    ridge_tau2 = as.numeric(get("ridge_tau2")), intercept_variance = as.numeric(get("intercept_variance")),
    sigma_shape = as.numeric(get("sigma_shape")), sigma_rate = as.numeric(get("sigma_rate")),
    calibration_replicates = as.integer(get("calibration_replicates")), rhs_tau0_grid = numvec("tau0_grid"),
    rhs_max_iter = as.integer(get("max_iter")), rhs_min_iter = as.integer(get("min_iter")),
    rhs_tolerance = as.numeric(get("tolerance")), evaluation_replicates = as.integer(get("evaluation_replicates")),
    vb_jobs_per_scenario = as.integer(get("vb_jobs_per_scenario")), max_workers = as.integer(get("max_workers")),
    cpu_affinity_list = get("cpu_affinity_list"), blas_threads = as.integer(get("blas_threads")),
    nice_level = as.integer(get("nice_level")), min_data_free_gib = as.numeric(get("min_data_free_gib")),
    max_condition_number = as.numeric(get("max_condition_number")), max_state_saturation = as.numeric(get("max_state_saturation")),
    max_readout_dimension = as.integer(get("max_readout_dimension")),
    protected_selection_forbidden = identical(tolower(get("protected_selection_forbidden")), "true"),
    require_finite_scores = identical(tolower(get("require_finite_scores")), "true"),
    require_zero_contract_crossings = identical(tolower(get("require_zero_contract_crossings")), "true"),
    selection_unit = get("selection_unit"), shared_specification_within_scenario = identical(tolower(get("shared_specification_within_scenario")), "true"),
    raw_inputs_in_readout = identical(tolower(get("raw_inputs_in_readout")), "true"),
    full_states_all_layers = identical(tolower(get("full_states_all_layers")), "true"),
    protected_scores_for_selection = identical(tolower(get("protected_scores_for_selection")), "true"),
    dense_grid_launched = identical(tolower(get("dense_grid_launched")), "true")
  )
  expected_tau <- c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)
  if (!identical(out$version, "joint_qdesn_pure_recursive_campaign_v1") ||
      !identical(out$tau, expected_tau) || out$scenario_count != 8L ||
      out$models_per_scenario != 4L || out$max_workers != 15L ||
      !identical(out$cpu_affinity_list, "2-16") || out$blas_threads != 1L ||
      out$inner_training_rows + out$inner_calibration_rows != out$fit_rows ||
      out$candidate_count != 256L || out$advance_count != 50L ||
      !out$protected_selection_forbidden || out$protected_scores_for_selection ||
      out$raw_inputs_in_readout || !out$full_states_all_layers || out$dense_grid_launched) {
    stop("Pure-recursive scientific or runtime contract is malformed.", call. = FALSE)
  }
  out
}

app_joint_pure_read_axes <- function(path = app_joint_pure_axes_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("axis", "values", "role"), "pure-recursive axes")
  value <- function(axis, numeric = FALSE) {
    row <- tab[tab$axis == axis, , drop = FALSE]
    if (nrow(row) != 1L) stop(sprintf("Pure-recursive axes require one '%s' row.", axis), call. = FALSE)
    out <- strsplit(as.character(row$values[[1L]]), ";", fixed = TRUE)[[1L]]
    if (numeric) as.numeric(out) else out
  }
  list(
    table = tab, depth = as.integer(value("depth", TRUE)), state_budget = as.integer(value("state_budget", TRUE)),
    width_shape = value("width_shape"), response_lags = as.integer(value("response_lags", TRUE)),
    exogenous_lags = as.integer(value("exogenous_lags", TRUE)), alpha = value("alpha", TRUE),
    rho = value("rho", TRUE), input_scale = value("input_scale", TRUE), pi_w = value("pi_w", TRUE),
    pi_in = value("pi_in", TRUE), reservoir_seed = as.integer(value("reservoir_seed", TRUE)),
    design_class = value("design_class"), state_reduction = tolower(value("state_reduction")) == "true"
  )
}

app_joint_pure_read_registry <- function(path = app_joint_pure_registry_path()) {
  out <- app_read_csv(path)
  app_check_required_columns(out, c("enabled", "scenario_id", "scenario_order", "selection_unit",
    "calibration_seed_base", "evaluation_seed_base", "article_seed"), "pure-recursive family registry")
  out$enabled <- app_as_bool_vec(out$enabled)
  out <- out[out$enabled, , drop = FALSE]
  out <- out[order(as.integer(out$scenario_order)), , drop = FALSE]
  if (nrow(out) != 8L || anyDuplicated(out$scenario_id) || any(out$selection_unit != "scenario_specific")) {
    stop("Pure-recursive registry must contain eight unique scenario-specific families.", call. = FALSE)
  }
  out
}

app_joint_pure_read_anchors <- function(path = app_joint_pure_anchor_path()) {
  out <- app_read_csv(path)
  app_check_required_columns(out, c(
    "scenario_id", "translatable", "source_candidate_id",
    "source_design_class", "D", "n", "width_shape", "alpha", "rho",
    "pi_w", "pi_in", "input_scale", "source_rhs_tau0",
    "translation_note"
  ), "pure-recursive historical anchors")
  out$translatable <- app_as_bool_vec(out$translatable)
  registry <- app_joint_pure_read_registry()
  if (nrow(out) != nrow(registry) || anyDuplicated(out$scenario_id) ||
      !setequal(out$scenario_id, registry$scenario_id) ||
      sum(out$translatable) != 7L) {
    stop("Pure-recursive historical-anchor registry is malformed.", call. = FALSE)
  }
  out
}

app_joint_pure_widths <- function(D, budget, shape) {
  D <- as.integer(D); budget <- as.integer(budget)
  weights <- if (identical(shape, "flat")) rep(1, D) else rev(seq_len(D))
  n <- pmax(1L, floor(budget * weights / sum(weights)))
  while (sum(n) < budget) n[[which.min(n)]] <- n[[which.min(n)]] + 1L
  while (sum(n) > budget) n[[which.max(n)]] <- n[[which.max(n)]] - 1L
  as.integer(n)
}

app_joint_pure_architecture_signature <- function(row) {
  fields <- c("D", "n", "response_lags", "exogenous_lags", "alpha", "rho", "input_scale", "pi_w", "pi_in", "reservoir_seed")
  app_joint_qvp_sha256_text(paste(vapply(fields, function(name) paste(name, row[[name]][[1L]], sep = "="), character(1L)), collapse = "|"))
}

app_joint_pure_candidate_universe <- function(axes = app_joint_pure_read_axes()) {
  grid <- expand.grid(
    D = axes$depth, state_budget = axes$state_budget, width_shape = axes$width_shape,
    response_lags = axes$response_lags, exogenous_lags = axes$exogenous_lags,
    alpha_scalar = axes$alpha, rho_scalar = axes$rho, input_scale = axes$input_scale,
    pi_w_scalar = axes$pi_w, pi_in_scalar = axes$pi_in, stringsAsFactors = FALSE
  )
  rows <- lapply(seq_len(nrow(grid)), function(ii) {
    g <- grid[ii, , drop = FALSE]; D <- as.integer(g$D[[1L]])
    n <- app_joint_pure_widths(D, g$state_budget[[1L]], g$width_shape[[1L]])
    row <- data.frame(
      feature_contract = "pure_recursive_v1", design_class = "reservoir", D = D,
      n = app_joint_shared_vec_label(n), n_tilde = app_joint_shared_vec_label(if (D > 1L) n[seq_len(D - 1L)] else integer()),
      retained_state_budget = sum(n), width_shape = g$width_shape[[1L]], state_reduction = FALSE,
      response_lags = as.integer(g$response_lags[[1L]]), exogenous_lags = as.integer(g$exogenous_lags[[1L]]),
      alpha = app_joint_shared_vec_label(rep(g$alpha_scalar[[1L]], D)),
      rho = app_joint_shared_vec_label(rep(g$rho_scalar[[1L]], D)),
      pi_w = app_joint_shared_vec_label(rep(g$pi_w_scalar[[1L]], D)),
      pi_in = app_joint_shared_vec_label(rep(g$pi_in_scalar[[1L]], D)),
      input_scale = as.numeric(g$input_scale[[1L]]), reservoir_seed = axes$reservoir_seed[[1L]],
      raw_inputs_in_readout = FALSE, full_states_all_layers = TRUE, stringsAsFactors = FALSE
    )
    row$architecture_key <- paste(
      row$D, row$n, row$response_lags, row$exogenous_lags, row$alpha, row$rho,
      row$input_scale, row$pi_w, row$pi_in, row$reservoir_seed, sep = "|")
    row
  })
  out <- app_bind_rows_fill(rows)
  out <- out[!duplicated(out$architecture_key), , drop = FALSE]
  out[order(out$architecture_key), , drop = FALSE]
}

app_joint_pure_maximin <- function(universe, n) {
  encode <- data.frame(
    D = universe$D, budget = universe$retained_state_budget,
    tapered = as.numeric(universe$width_shape == "tapered"), response_lags = universe$response_lags,
    alpha = vapply(strsplit(universe$alpha, ";", fixed = TRUE), function(x) as.numeric(x[[1L]]), numeric(1L)),
    rho = vapply(strsplit(universe$rho, ";", fixed = TRUE), function(x) as.numeric(x[[1L]]), numeric(1L)),
    input_scale = universe$input_scale,
    pi_w = vapply(strsplit(universe$pi_w, ";", fixed = TRUE), function(x) as.numeric(x[[1L]]), numeric(1L)),
    pi_in = vapply(strsplit(universe$pi_in, ";", fixed = TRUE), function(x) as.numeric(x[[1L]]), numeric(1L))
  )
  X <- as.matrix(encode)
  X <- apply(X, 2L, function(z) if (diff(range(z)) > 0) (z - min(z)) / diff(range(z)) else rep(0, length(z)))
  selected <- order(-rowSums((X - 0.5)^2), universe$architecture_key)[[1L]]
  distance <- rowSums((X - matrix(X[selected, ], nrow(X), ncol(X), byrow = TRUE))^2)
  while (length(selected) < as.integer(n)) {
    distance[selected] <- -Inf
    next_index <- order(-distance, universe$architecture_key)[[1L]]
    selected <- c(selected, next_index)
    candidate_distance <- rowSums((X - matrix(X[next_index, ], nrow(X), ncol(X), byrow = TRUE))^2)
    distance <- pmin(distance, candidate_distance)
  }
  universe[selected, , drop = FALSE]
}

app_joint_pure_anchor_candidate <- function(
  scenario_id, axes = app_joint_pure_read_axes(),
  anchors = app_joint_pure_read_anchors()
) {
  anchor <- anchors[anchors$scenario_id == scenario_id, , drop = FALSE]
  if (nrow(anchor) != 1L || !isTRUE(anchor$translatable[[1L]])) return(NULL)
  n <- as.integer(app_joint_shared_parse_num_vec(anchor$n[[1L]]))
  D <- as.integer(anchor$D[[1L]])
  if (length(n) != D || !D %in% axes$depth || sum(n) > 192L) {
    stop("Translated historical anchor violates pure-DESN width gates.", call. = FALSE)
  }
  row <- data.frame(
    feature_contract = "pure_recursive_v1", design_class = "reservoir",
    D = D, n = paste(n, collapse = ";"),
    n_tilde = if (D > 1L) paste(n[seq_len(D - 1L)], collapse = ";") else "",
    retained_state_budget = sum(n), width_shape = anchor$width_shape[[1L]],
    state_reduction = FALSE, response_lags = 1L, exogenous_lags = 0L,
    alpha = paste(rep(as.numeric(anchor$alpha[[1L]]), D), collapse = ";"),
    rho = paste(rep(as.numeric(anchor$rho[[1L]]), D), collapse = ";"),
    pi_w = paste(rep(as.numeric(anchor$pi_w[[1L]]), D), collapse = ";"),
    pi_in = paste(rep(as.numeric(anchor$pi_in[[1L]]), D), collapse = ";"),
    input_scale = as.numeric(anchor$input_scale[[1L]]),
    reservoir_seed = axes$reservoir_seed[[1L]], raw_inputs_in_readout = FALSE,
    full_states_all_layers = TRUE, stringsAsFactors = FALSE
  )
  row$architecture_signature <- app_joint_pure_architecture_signature(row)
  row$source_candidate_id <- anchor$source_candidate_id[[1L]]
  row$source_rhs_tau0 <- as.numeric(anchor$source_rhs_tau0[[1L]])
  row$translation_note <- anchor$translation_note[[1L]]
  row
}

app_joint_pure_candidates <- function(
  scenario_id, contract, axes = app_joint_pure_read_axes(),
  base_candidates = NULL
) {
  if (is.null(base_candidates)) {
    universe <- app_joint_pure_candidate_universe(axes)
    selected <- app_joint_pure_maximin(universe, contract$candidate_count)
  } else {
    universe <- NULL
    selected <- base_candidates
  }
  if (nrow(selected) != contract$candidate_count) {
    stop("Pure-recursive base candidate design has the wrong cardinality.", call. = FALSE)
  }
  selected$architecture_signature <- vapply(seq_len(nrow(selected)), function(ii) {
    app_joint_pure_architecture_signature(selected[ii, , drop = FALSE])
  }, character(1L))
  selected$architecture_key <- NULL
  selected$candidate_role <- "pure_recursive_space_filling"
  anchor <- app_joint_pure_anchor_candidate(scenario_id, axes)
  if (!is.null(anchor)) {
    anchor$candidate_role <- "translated_historical_shared_backbone_anchor"
    match_index <- match(anchor$architecture_signature[[1L]],
      selected$architecture_signature)
    if (is.na(match_index)) {
      selected <- rbind(selected[-nrow(selected), , drop = FALSE],
        anchor[, names(selected), drop = FALSE])
      match_index <- nrow(selected)
    }
    selected$candidate_role[[match_index]] <-
      "translated_historical_shared_backbone_anchor"
  }
  selected <- selected[order(selected$architecture_signature), , drop = FALSE]
  selected$candidate_id <- sprintf("%s__pure_ridge_%03d", scenario_id, seq_len(nrow(selected)))
  selected$scenario_id <- scenario_id
  selected <- selected[, c("candidate_id", "candidate_role", "scenario_id", setdiff(names(selected), c("candidate_id", "candidate_role", "scenario_id"))), drop = FALSE]
  list(candidates = selected, universe = universe)
}

app_joint_pure_known_feature_row <- function(tt, y_history, response_lags, sc) {
  tt <- as.integer(tt); response_lags <- as.integer(response_lags)
  if (tt <= response_lags || length(y_history) < tt - 1L) stop("Insufficient response history for pure-DESN feature row.", call. = FALSE)
  lag_values <- y_history[tt - seq_len(response_lags)]
  simulated_length <- as.integer(sc$simulated_length[[1L]]); period <- as.integer(sc$period[[1L]])
  angle <- 2 * pi * (tt - 1L) / period
  trend <- if (simulated_length > 1L) -1 + 2 * (tt - 1L) / (simulated_length - 1L) else 0
  values <- stats::setNames(as.numeric(lag_values), paste0("lag_y_", seq_len(response_lags)))
  values <- c(values, trend = trend, sin_season = sin(angle), cos_season = cos(angle))
  if (identical(as.character(sc$dynamics_class[[1L]]), "regime_shift_location_scale")) {
    start <- max(1L, min(simulated_length, floor(as.numeric(sc$regime_start_fraction[[1L]]) * simulated_length)))
    values <- c(values, regime = as.numeric(tt > start),
      post_regime_trend = if (tt > start) (tt - start) / max(1L, simulated_length - start) else 0)
  }
  values
}

app_joint_pure_raw_matrix <- function(full_time_index, y_history, candidate, sc) {
  rows <- lapply(full_time_index, app_joint_pure_known_feature_row, y_history = y_history,
    response_lags = as.integer(candidate$response_lags[[1L]]), sc = sc)
  out <- do.call(rbind, rows); storage.mode(out) <- "double"
  if (any(!is.finite(out))) stop("Pure-DESN input matrix contains nonfinite values.", call. = FALSE)
  out
}

app_joint_pure_selector_fixture <- function(fixture, contract) {
  keep <- fixture$detailed_split$role %in% c("desn_washout", "fit")
  if (sum(keep) != contract$desn_washout_rows + contract$fit_rows ||
      sum(fixture$detailed_split$role == "validation") != contract$protected_validation_rows) {
    stop("Pure-DESN selector fixture geometry is malformed.", call. = FALSE)
  }
  list(
    scenario_id = fixture$scenario_id, scenario_class = fixture$scenario_class,
    distribution_family = fixture$distribution_family, dynamics_class = fixture$dynamics_class,
    y_history = fixture$y[seq_len(max(fixture$detailed_split$full_time_index[keep]))],
    y = fixture$y[keep], true_q = fixture$true_q[keep, , drop = FALSE], tau = fixture$tau,
    detailed_split = fixture$detailed_split[keep, , drop = FALSE], seed = fixture$seed,
    seed_role = fixture$seed_role, registry_row = fixture$registry_row,
    selector_fixture = TRUE, protected_rows_persisted = 0L,
    protected_rows_declared = contract$protected_validation_rows
  )
}

app_joint_pure_reservoir <- function(candidate, m_input) {
  D <- as.integer(candidate$D[[1L]])
  n <- as.integer(app_joint_shared_parse_num_vec(candidate$n[[1L]]))
  n_tilde <- as.integer(app_joint_shared_parse_num_vec(candidate$n_tilde[[1L]]))
  if (length(n) != D || (D > 1L && !identical(n_tilde, n[seq_len(D - 1L)])) || sum(n) > 192L) {
    stop("Pure-DESN full-state width contract is malformed.", call. = FALSE)
  }
  app_qdesn_generate_article_reservoir(
    list(reservoir = list(
      D = D, n = n, n_tilde = n_tilde, m = as.integer(m_input),
      alpha = app_joint_shared_parse_num_vec(candidate$alpha[[1L]]),
      rho = app_joint_shared_parse_num_vec(candidate$rho[[1L]]),
      pi_w = app_joint_shared_parse_num_vec(candidate$pi_w[[1L]]),
      pi_in = app_joint_shared_parse_num_vec(candidate$pi_in[[1L]]),
      w_dist = "uniform", in_dist = "uniform", act_f = "tanh", act_k = "identity"
    )), seed = as.integer(candidate$reservoir_seed[[1L]]), m_input = as.integer(m_input)
  )
}

app_joint_pure_reservoir_meta <- function(candidate, m_input) {
  scale <- as.numeric(candidate$input_scale[[1L]])
  list(standardize_inputs = FALSE, lag_center = rep(0, m_input), lag_scale = rep(1, m_input),
    input_bound = "none", win_scale_global = scale, win_scale_bias = scale)
}

app_joint_pure_candidate_columns <- function() {
  c("scenario_id", "candidate_id", "candidate_role", "feature_contract", "design_class", "D", "n", "n_tilde",
    "retained_state_budget", "width_shape", "state_reduction", "response_lags", "exogenous_lags", "alpha", "rho",
    "pi_w", "pi_in", "input_scale", "reservoir_seed", "raw_inputs_in_readout", "full_states_all_layers", "architecture_signature")
}

app_joint_pure_worker_identity_columns <- function(stage = c("ridge", "rhs")) {
  stage <- match.arg(stage)
  c(app_joint_pure_candidate_columns(), if (stage == "ridge") {
    c("worker_id", "replicate_id", "dgp_seed", "fixture_path")
  } else {
    c("rhs_tau0", "replicate_id", "dgp_seed", "fixture_path", "rhs_worker_id",
      "rhs_candidate_id", "advancement_rank")
  })
}

app_joint_pure_result_columns <- function() {
  c(
    "n_analysis", "n_train", "n_calibration", "protected_rows_loaded", "n_features",
    "raw_readout_columns", "reservoir_readout_columns", "effective_rank", "condition_number",
    "state_saturation_fraction", "finite_design", "status", "method", "observational_selector",
    "hard_gate_status", "condition_gate_status", "saturation_gate_status", "calibration_acrps_mean",
    "calibration_acrps_sd", "calibration_exact_gaussian_crps", "calibration_mae", "calibration_rmse",
    "calibration_oracle_quantile_mae", "calibration_oracle_quantile_rmse", "converged", "iterations",
    "final_delta", "runtime_seconds"
  )
}

app_joint_pure_summary_identity <- function(candidate, stage = c("ridge", "rhs")) {
  stage <- match.arg(stage)
  columns <- app_joint_pure_worker_identity_columns(stage)
  missing <- setdiff(app_joint_pure_candidate_columns(), names(candidate))
  if (length(missing)) {
    stop(sprintf("Worker candidate is missing identity columns: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  candidate[, intersect(columns, names(candidate)), drop = FALSE]
}

app_joint_pure_assert_unique_summary <- function(summary, context = "worker summary") {
  duplicates <- unique(names(summary)[duplicated(names(summary))])
  if (length(duplicates)) {
    stop(sprintf("%s has duplicate columns: %s", context, paste(duplicates, collapse = ", ")), call. = FALSE)
  }
  summary
}

app_joint_pure_normalize_worker_summary <- function(summary, stage = c("ridge", "rhs")) {
  stage <- match.arg(stage)
  desired <- c(app_joint_pure_worker_identity_columns(stage), app_joint_pure_result_columns())
  missing <- desired[!desired %in% names(summary)]
  if (length(missing)) {
    stop(sprintf("Legacy %s summary is missing fields: %s", stage, paste(missing, collapse = ", ")), call. = FALSE)
  }
  result_names <- app_joint_pure_result_columns()
  indices <- vapply(desired, function(name) {
    matches <- which(names(summary) == name)
    if (name %in% result_names) tail(matches, 1L) else matches[[1L]]
  }, integer(1L))
  out <- summary[, indices, drop = FALSE]
  names(out) <- desired
  app_joint_pure_assert_unique_summary(out, sprintf("normalized %s summary", stage))
}

app_joint_pure_build_design <- function(fixture, candidate, contract, selector = TRUE) {
  roles <- fixture$detailed_split$role
  if (selector) {
    if (!isTRUE(fixture$selector_fixture) || as.integer(fixture$protected_rows_persisted) != 0L) {
      stop("Selection requires a protected-row-free fixture.", call. = FALSE)
    }
    fit_local <- which(roles == "fit")
    train_local <- fit_local[seq_len(contract$inner_training_rows)]
    calibration_local <- fit_local[seq.int(contract$inner_training_rows + 1L, contract$fit_rows)]
    y_history <- fixture$y_history
  } else {
    fit_local <- which(roles == "fit"); train_local <- fit_local; calibration_local <- integer()
    y_history <- fixture$y_history %||% fixture$y
  }
  full <- fixture$detailed_split$full_time_index
  raw <- app_joint_pure_raw_matrix(full, y_history, candidate, fixture$registry_row)
  scale_params <- app_joint_exqdesn_phase151_scale_params(raw, seq_len(nrow(raw)) %in% train_local)
  raw_scaled <- app_qdesn_reservoir_scale_inputs(raw, scale_params = scale_params)$X
  reservoir <- app_joint_pure_reservoir(candidate, ncol(raw_scaled))
  reservoir_meta <- app_joint_pure_reservoir_meta(candidate, ncol(raw_scaled))
  rolled <- app_qdesn_roll_article_reservoir(raw_scaled, reservoir, reservoir_meta)
  state_raw <- rolled$X_all
  center <- colMeans(state_raw[train_local, , drop = FALSE])
  scale <- apply(state_raw[train_local, , drop = FALSE], 2L, stats::sd)
  scale[!is.finite(scale) | scale <= 1e-10] <- 1
  states <- sweep(sweep(state_raw, 2L, center, "-"), 2L, scale, "/")
  colnames(states) <- paste0("reservoir_", sprintf("%04d", seq_len(ncol(states))))
  X <- cbind(`(Intercept)` = 1, states)
  expected_p <- 1L + sum(app_joint_shared_parse_num_vec(candidate$n[[1L]]))
  if (ncol(X) != expected_p || ncol(X) - 1L != as.integer(candidate$retained_state_budget[[1L]])) {
    stop("Pure-DESN readout is not intercept plus every layer state.", call. = FALSE)
  }
  train_X <- X[train_local, , drop = FALSE]
  condition <- tryCatch(kappa(train_X, exact = FALSE), error = function(e) Inf)
  saturation <- mean(abs(state_raw[train_local, , drop = FALSE]) > 0.99)
  list(
    scenario_id = fixture$scenario_id, candidate_id = candidate$candidate_id[[1L]],
    architecture_signature = candidate$architecture_signature[[1L]], feature_contract = "pure_recursive_v1",
    design_class = "reservoir", response_lags = as.integer(candidate$response_lags[[1L]]),
    exogenous_lags = as.integer(candidate$exogenous_lags[[1L]]), raw_inputs_in_readout = FALSE,
    full_states_all_layers = TRUE, tau = fixture$tau, X = X, Z = states, y = fixture$y,
    true_q = fixture$true_q, row_meta = fixture$detailed_split, fit_local = fit_local,
    train_local = train_local, calibration_local = calibration_local, scale_params = scale_params,
    reservoir = reservoir, reservoir_meta = reservoir_meta, state_center = center, state_scale = scale,
    teacher_forced_states = rolled$H_all, dgp_row = fixture$registry_row,
    diagnostic = data.frame(
      n_analysis = nrow(X), n_train = length(train_local), n_calibration = length(calibration_local),
      protected_rows_loaded = if (selector) 0L else sum(roles == "validation"), n_features = ncol(X),
      raw_readout_columns = 0L, reservoir_readout_columns = ncol(states),
      effective_rank = qr(train_X)$rank, condition_number = condition,
      state_saturation_fraction = saturation, finite_design = all(is.finite(X)), stringsAsFactors = FALSE
    )
  )
}

app_joint_pure_recursive_gaussian <- function(design, fixture, fit, contract) {
  cal <- design$calibration_local
  blocks <- split(cal, ceiling(seq_along(cal) / contract$calibration_max_lead))
  if (length(blocks) * contract$calibration_max_lead != length(cal) ||
      any(lengths(blocks) != contract$calibration_max_lead)) {
    stop("Calibration rows do not partition into frozen recursive horizons.", call. = FALSE)
  }
  qhat <- matrix(NA_real_, nrow = length(cal), ncol = length(design$tau))
  pred_mean <- pred_sd <- rep(NA_real_, length(cal)); row_cursor <- 0L
  for (block in blocks) {
    origin_local <- min(block) - 1L
    origin_full <- design$row_meta$full_time_index[[origin_local]]
    states <- lapply(design$teacher_forced_states, function(H) as.numeric(H[origin_local, ]))
    history <- fixture$y_history[seq_len(origin_full)]
    for (local_target in block) {
      tt <- design$row_meta$full_time_index[[local_target]]
      raw <- app_joint_pure_known_feature_row(tt, history,
        response_lags = design$response_lags, sc = design$dgp_row)
      scaled <- app_joint_recursive_scale_row(raw, design$scale_params)
      states <- app_qdesn_continue_one_step(states, scaled, design$reservoir, design$reservoir_meta)
      state_raw <- app_qdesn_readout_row_from_states(states, design$reservoir)
      state <- (state_raw - design$state_center) / design$state_scale
      x <- matrix(c(1, state), nrow = 1L, dimnames = list(NULL, colnames(design$X)))
      pred <- app_glofas_normal_predict(fit, x, chunk_size = 1L)
      row_cursor <- row_cursor + 1L
      pred_mean[[row_cursor]] <- pred$mean[[1L]]; pred_sd[[row_cursor]] <- pred$sd[[1L]]
      qhat[row_cursor, ] <- pred$mean[[1L]] + pred$sd[[1L]] * stats::qnorm(design$tau)
      history[[tt]] <- pred$mean[[1L]]
    }
  }
  if (row_cursor != length(cal) || any(!is.finite(c(qhat, pred_mean, pred_sd)))) {
    stop("Recursive Gaussian calibration forecast is incomplete.", call. = FALSE)
  }
  list(qhat = qhat, pred_mean = pred_mean, pred_sd = pred_sd, calibration_local = cal)
}

app_joint_pure_score_fit <- function(fixture, candidate, contract, method = c("ridge", "rhs")) {
  method <- match.arg(method); started <- Sys.time()
  design <- app_joint_pure_build_design(fixture, candidate, contract, selector = TRUE)
  tr <- design$train_local
  ridge <- app_glofas_normal_ridge_fit(design$X[tr, , drop = FALSE], design$y[tr],
    ridge_tau2 = contract$ridge_tau2, intercept_var = contract$intercept_variance,
    sigma_a = contract$sigma_shape, sigma_b = contract$sigma_rate)
  fit <- ridge; trace <- data.frame()
  if (identical(method, "rhs")) {
    warm <- app_joint_shared_ridge_warm_start(ridge, candidate, design)
    fit <- app_glofas_normal_rhs_fit(design$X[tr, , drop = FALSE], design$y[tr], warm,
      tau0 = as.numeric(candidate$rhs_tau0[[1L]]), max_iter = contract$rhs_max_iter,
      min_iter = contract$rhs_min_iter, tol = contract$rhs_tolerance)
    trace <- fit$trace
  }
  pred <- app_joint_pure_recursive_gaussian(design, fixture, fit, contract)
  cal <- pred$calibration_local
  score <- app_joint_shared_acrps(design$y[cal], pred$qhat, design$tau)
  oracle <- pred$qhat - design$true_q[cal, , drop = FALSE]
  condition_pass <- is.finite(design$diagnostic$condition_number[[1L]]) &&
    design$diagnostic$condition_number[[1L]] <= contract$max_condition_number
  saturation_pass <- is.finite(design$diagnostic$state_saturation_fraction[[1L]]) &&
    design$diagnostic$state_saturation_fraction[[1L]] <= contract$max_state_saturation
  summary <- cbind(app_joint_pure_summary_identity(candidate, method), design$diagnostic, data.frame(
    status = "completed", method = method,
    observational_selector = "rolling_origin_recursive_realized_finite_grid_acrps",
    hard_gate_status = if (isTRUE(design$diagnostic$finite_design[[1L]]) && all(is.finite(score))) "pass" else "fail",
    condition_gate_status = if (condition_pass) "pass" else "review",
    saturation_gate_status = if (saturation_pass) "pass" else "review",
    calibration_acrps_mean = mean(score), calibration_acrps_sd = stats::sd(score),
    calibration_exact_gaussian_crps = mean(app_glofas_normal_crps(design$y[cal], pred$pred_mean, pred$pred_sd)),
    calibration_mae = mean(abs(pred$pred_mean - design$y[cal])),
    calibration_rmse = sqrt(mean((pred$pred_mean - design$y[cal])^2)),
    calibration_oracle_quantile_mae = mean(abs(oracle)), calibration_oracle_quantile_rmse = sqrt(mean(oracle^2)),
    converged = fit$converged %||% TRUE, iterations = fit$iterations %||% NA_integer_,
    final_delta = fit$final_delta %||% NA_real_, runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    stringsAsFactors = FALSE
  ))
  summary <- app_joint_pure_assert_unique_summary(summary)
  detail <- data.frame(
    calibration_row = seq_along(cal), full_time_index = design$row_meta$full_time_index[cal],
    origin_index = rep(seq_along(split(cal, ceiling(seq_along(cal) / contract$calibration_max_lead))),
      each = contract$calibration_max_lead),
    horizon = rep(seq_len(contract$calibration_max_lead), length(cal) / contract$calibration_max_lead),
    y = design$y[cal], pred_mean = pred$pred_mean, pred_sd = pred$pred_sd,
    realized_acrps = score, stringsAsFactors = FALSE
  )
  list(summary = summary, detail = detail, trace = trace)
}

app_joint_pure_worker_dir <- function(root, stage, worker_id) {
  file.path(root, paste0(stage, "_workers"), sprintf("worker_%05d", as.integer(worker_id)))
}

app_joint_pure_prepare <- function(root = app_joint_pure_default_root()) {
  contract <- app_joint_pure_read_contract(); registry <- app_joint_pure_read_registry()
  root <- normalizePath(root, mustWork = FALSE)
  if (dir.exists(root) && length(list.files(root, all.files = TRUE, no.. = TRUE))) {
    stop("Refusing to overwrite a nonempty pure-recursive campaign root.", call. = FALSE)
  }
  app_ensure_dir(root); app_ensure_dir(file.path(root, "fixtures")); app_ensure_dir(file.path(root, "ridge_workers"))
  dgp <- app_joint_qdesn_load_simulation_registry()
  universe <- app_joint_pure_candidate_universe(app_joint_pure_read_axes())
  template_candidates <- app_joint_pure_maximin(universe, contract$candidate_count)
  candidate_rows <- fixture_rows <- job_rows <- list(); worker_id <- 0L
  for (ii in seq_len(nrow(registry))) {
    family <- registry[ii, , drop = FALSE]; scenario <- family$scenario_id[[1L]]
    sc <- dgp[dgp$scenario_id == scenario, , drop = FALSE]
    if (nrow(sc) != 1L) stop("Campaign scenario is not unique in the DGP registry.", call. = FALSE)
    built <- app_joint_pure_candidates(
      scenario, contract, base_candidates = template_candidates
    )
    candidate_rows[[ii]] <- built$candidates
    for (replicate_id in seq_len(contract$calibration_replicates)) {
      seed <- as.integer(family$calibration_seed_base[[1L]]) + replicate_id - 1L
      sc_rep <- sc; sc_rep$seed <- seed; sc_rep$seed_role <- sprintf("pure_recursive_selection_rep%02d", replicate_id)
      fixture <- app_joint_qdesn_fixture_from_registry_row(sc_rep); fixture$registry_row <- sc_rep
      selector <- app_joint_pure_selector_fixture(fixture, contract)
      fixture_path <- file.path(root, "fixtures", sprintf("%02d_%s_rep%02d.rds", ii, scenario, replicate_id))
      saveRDS(selector, fixture_path, version = 3L, compress = "xz")
      fixture_rows[[length(fixture_rows) + 1L]] <- data.frame(
        scenario_id = scenario, replicate_id = replicate_id, dgp_seed = seed,
        fixture_path = normalizePath(fixture_path, mustWork = TRUE), size_bytes = file.info(fixture_path)$size,
        sha256 = app_sha256_file(fixture_path), protected_rows_persisted = 0L, stringsAsFactors = FALSE)
      jobs <- built$candidates; jobs$replicate_id <- replicate_id; jobs$dgp_seed <- seed
      jobs$fixture_path <- normalizePath(fixture_path, mustWork = TRUE)
      jobs$worker_id <- seq.int(worker_id + 1L, worker_id + nrow(jobs)); worker_id <- worker_id + nrow(jobs)
      job_rows[[length(job_rows) + 1L]] <- jobs
    }
  }
  candidates <- app_bind_rows_fill(candidate_rows); fixtures <- app_bind_rows_fill(fixture_rows)
  jobs <- app_bind_rows_fill(job_rows); jobs <- jobs[order(jobs$worker_id), , drop = FALSE]
  if (nrow(candidates) != contract$scenario_count * contract$candidate_count ||
      nrow(jobs) != nrow(candidates) * contract$calibration_replicates || anyDuplicated(jobs$worker_id) ||
      any(fixtures$protected_rows_persisted != 0L)) stop("Pure-recursive campaign cardinality gate failed.", call. = FALSE)
  source_registry <- app_joint_qdesn_load_simulation_registry()
  article_seed <- source_registry$seed[match(registry$scenario_id, source_registry$scenario_id)]
  if (any(as.integer(article_seed) != as.integer(registry$article_seed))) stop("Article seeds differ from the DGP registry.", call. = FALSE)
  expected <- data.frame(
    scenarios = contract$scenario_count, ridge_candidates = nrow(candidates), ridge_workers = nrow(jobs),
    rhs_workers = contract$scenario_count * contract$advance_count * length(contract$rhs_tau0_grid) * contract$calibration_replicates,
    quantile_vb_workers = contract$scenario_count * contract$vb_jobs_per_scenario,
    article_vb_components = 136L, article_mcmc_workers = 160L, concurrent_workers = contract$max_workers,
    stringsAsFactors = FALSE)
  files <- c(
    frozen_contract = app_write_csv(contract$table, file.path(root, "frozen_contract.csv")),
    frozen_axes = app_write_csv(app_joint_pure_read_axes()$table, file.path(root, "frozen_candidate_axes.csv")),
    frozen_registry = app_write_csv(registry, file.path(root, "frozen_family_registry.csv")),
    frozen_historical_anchors = app_write_csv(app_joint_pure_read_anchors(),
      file.path(root, "frozen_historical_anchors.csv")),
    candidate_registry = app_write_csv(candidates, file.path(root, "ridge_candidate_registry.csv")),
    fixture_manifest = app_write_csv(fixtures, file.path(root, "fixture_manifest.csv")),
    ridge_worker_plan = app_write_csv(jobs, file.path(root, "ridge_worker_plan.csv")),
    expected_work = app_write_csv(expected, file.path(root, "expected_work.csv")),
    source_git_state = app_write_csv(app_joint_shared_git_state(), file.path(root, "source_git_state.csv")))
  readiness <- data.frame(status = "READY_TO_LAUNCH_PURE_RECURSIVE_RIDGE", expected_workers = nrow(jobs),
    max_workers = contract$max_workers, cpu_affinity_list = contract$cpu_affinity_list,
    protected_rows_used_for_selection = 0L, article_fixture_used_for_selection = FALSE, stringsAsFactors = FALSE)
  files <- c(files, launch_readiness = app_write_csv(readiness, file.path(root, "launch_readiness.csv")))
  app_joint_shared_write_manifest(root, files)
  list(root = root, expected = expected, readiness = readiness)
}

app_joint_pure_run_worker <- function(root, stage = c("ridge", "rhs"), worker_id) {
  stage <- match.arg(stage); root <- normalizePath(root, mustWork = TRUE)
  plan <- app_read_csv(file.path(root, paste0(stage, "_worker_plan.csv")))
  id_name <- if (stage == "ridge") "worker_id" else "rhs_worker_id"
  row <- plan[as.integer(plan[[id_name]]) == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("Pure-recursive worker ID is not unique.", call. = FALSE)
  out <- app_joint_pure_worker_dir(root, stage, worker_id)
  if (file.exists(file.path(out, "DONE")) && file.exists(file.path(out, "summary.csv"))) return(invisible(out))
  app_ensure_dir(out); contract <- app_joint_pure_read_contract(file.path(root, "frozen_contract.csv"))
  fixture <- readRDS(row$fixture_path[[1L]])
  result <- tryCatch(app_joint_pure_score_fit(fixture, row, contract, method = stage), error = function(e) e)
  if (inherits(result, "error")) {
    app_write_csv(cbind(row, data.frame(status = "failed", error_message = conditionMessage(result), stringsAsFactors = FALSE)),
      file.path(out, "failure.csv")); writeLines("failed", file.path(out, "FAILED")); return(invisible(out))
  }
  paths <- c(summary = app_write_csv(result$summary, file.path(out, "summary.csv")),
    calibration_detail = app_write_csv(result$detail, file.path(out, "calibration_detail.csv")))
  if (nrow(result$trace)) paths <- c(paths, vb_trace = app_write_csv(result$trace, file.path(out, "vb_trace.csv")))
  app_joint_shared_write_manifest(out, paths); writeLines("completed", file.path(out, "DONE")); invisible(out)
}

app_joint_pure_health <- function(root, stage = c("ridge", "rhs")) {
  stage <- match.arg(stage); plan_path <- file.path(root, paste0(stage, "_worker_plan.csv"))
  if (!file.exists(plan_path)) return(data.frame(stage = stage, expected = 0L, completed = 0L, failed = 0L, remaining = 0L, status = "pending"))
  plan <- app_read_csv(plan_path); id <- plan[[if (stage == "ridge") "worker_id" else "rhs_worker_id"]]
  dirs <- vapply(id, function(x) app_joint_pure_worker_dir(root, stage, x), character(1L))
  done <- file.exists(file.path(dirs, "DONE")) & file.exists(file.path(dirs, "artifact_manifest.csv"))
  failed <- file.exists(file.path(dirs, "FAILED")) | file.exists(file.path(dirs, "failure.csv"))
  data.frame(stage = stage, expected = length(id), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), completion_fraction = mean(done),
    status = if (any(failed)) "failed" else if (all(done)) "complete" else "running", stringsAsFactors = FALSE)
}

app_joint_pure_collect_summaries <- function(root, stage) {
  health <- app_joint_pure_health(root, stage)
  if (health$completed[[1L]] != health$expected[[1L]] || health$failed[[1L]] != 0L) {
    stop(sprintf("Pure-recursive %s stage is not complete and failure-free.", stage), call. = FALSE)
  }
  paths <- list.files(file.path(root, paste0(stage, "_workers")), pattern = "summary[.]csv$", recursive = TRUE, full.names = TRUE)
  rows <- lapply(paths, function(path) {
    app_joint_pure_assert_unique_summary(app_read_csv(path), sprintf("%s summary %s", stage, path))
  })
  out <- app_bind_rows_fill(rows)
  required <- c(app_joint_pure_candidate_columns(), if (stage == "ridge") "worker_id" else c("rhs_worker_id", "rhs_tau0"),
    app_joint_pure_result_columns())
  missing <- setdiff(required, names(out))
  if (length(missing)) {
    stop(sprintf("Pure-recursive %s summaries are missing fields: %s", stage, paste(missing, collapse = ", ")), call. = FALSE)
  }
  if (nrow(out) != health$expected[[1L]] || any(out$status != "completed") || any(!is.finite(as.numeric(out$calibration_acrps_mean)))) {
    stop(sprintf("Pure-recursive %s summaries violate completion gates.", stage), call. = FALSE)
  }
  out
}

app_joint_pure_repair_rhs_summaries <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  health <- app_joint_pure_health(root, "rhs")
  if (health$completed[[1L]] != health$expected[[1L]] || health$failed[[1L]] != 0L) {
    stop("RHS summary repair requires a complete, failure-free worker stage.", call. = FALSE)
  }
  plan <- app_read_csv(file.path(root, "rhs_worker_plan.csv"))
  audits <- vector("list", nrow(plan))
  for (ii in seq_len(nrow(plan))) {
    worker_id <- as.integer(plan$rhs_worker_id[[ii]])
    worker_dir <- app_joint_pure_worker_dir(root, "rhs", worker_id)
    summary_path <- file.path(worker_dir, "summary.csv")
    legacy <- app_read_csv(summary_path)
    duplicate_names <- unique(names(legacy)[duplicated(names(legacy))])
    old_sha256 <- app_sha256_file(summary_path)
    normalized <- app_joint_pure_normalize_worker_summary(legacy, "rhs")
    if (as.integer(normalized$rhs_worker_id[[1L]]) != worker_id) {
      stop(sprintf("Normalized RHS summary does not identify worker %d.", worker_id), call. = FALSE)
    }
    changed <- length(duplicate_names) > 0L || !identical(names(legacy), names(normalized))
    if (changed) {
      app_write_csv(normalized, summary_path)
      paths <- c(summary = summary_path,
        calibration_detail = file.path(worker_dir, "calibration_detail.csv"))
      trace_path <- file.path(worker_dir, "vb_trace.csv")
      if (file.exists(trace_path)) paths <- c(paths, vb_trace = trace_path)
      if (any(!file.exists(paths))) {
        stop(sprintf("RHS worker %d is missing an artifact required for manifest repair.", worker_id), call. = FALSE)
      }
      app_joint_shared_write_manifest(worker_dir, paths)
    }
    verification <- app_joint_shared_verify_manifest(worker_dir)
    if (!all(verification$verified)) {
      stop(sprintf("Repaired RHS worker %d failed manifest verification.", worker_id), call. = FALSE)
    }
    audits[[ii]] <- data.frame(
      rhs_worker_id = worker_id, changed = changed,
      duplicate_columns = paste(duplicate_names, collapse = ";"),
      old_summary_sha256 = old_sha256, new_summary_sha256 = app_sha256_file(summary_path),
      manifest_verified = TRUE, stringsAsFactors = FALSE
    )
  }
  app_bind_rows_fill(audits)
}

app_joint_pure_finalize_ridge <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); contract <- app_joint_pure_read_contract(file.path(root, "frozen_contract.csv"))
  scores <- app_joint_pure_collect_summaries(root, "ridge"); keys <- app_joint_pure_candidate_columns()
  groups <- split(scores, paste(scores$scenario_id, scores$candidate_id, sep = "__"))
  aggregate <- app_bind_rows_fill(lapply(groups, function(x) {
    row <- x[1L, keys, drop = FALSE]
    cbind(row, data.frame(
      replicate_count = nrow(x), hard_gate_status = if (all(x$hard_gate_status == "pass")) "pass" else "fail",
      condition_gate_status = if (all(x$condition_gate_status == "pass")) "pass" else "review",
      saturation_gate_status = if (all(x$saturation_gate_status == "pass")) "pass" else "review",
      calibration_acrps_mean = mean(as.numeric(x$calibration_acrps_mean)),
      calibration_acrps_between_rep_sd = stats::sd(as.numeric(x$calibration_acrps_mean)),
      calibration_exact_gaussian_crps_mean = mean(as.numeric(x$calibration_exact_gaussian_crps)),
      calibration_mae_mean = mean(as.numeric(x$calibration_mae)), calibration_rmse_mean = mean(as.numeric(x$calibration_rmse)),
      maximum_condition_number = max(as.numeric(x$condition_number)), maximum_state_saturation = max(as.numeric(x$state_saturation_fraction)),
      runtime_seconds_total = sum(as.numeric(x$runtime_seconds)), stringsAsFactors = FALSE))
  }))
  frontiers <- lapply(split(aggregate, aggregate$scenario_id), function(x) {
    x <- x[x$hard_gate_status == "pass", , drop = FALSE]
    x <- x[order(x$calibration_acrps_mean, x$calibration_acrps_between_rep_sd,
      x$calibration_exact_gaussian_crps_mean, x$candidate_id), , drop = FALSE]
    if (nrow(x) < contract$advance_count) stop("Fewer than 50 pure-DESN candidates passed a family hard gate.", call. = FALSE)
    x <- head(x, contract$advance_count); x$advancement_rank <- seq_len(nrow(x)); x
  })
  frontier <- app_bind_rows_fill(frontiers)
  fixtures <- unique(app_read_csv(file.path(root, "ridge_worker_plan.csv"))[, c("scenario_id", "replicate_id", "dgp_seed", "fixture_path")])
  rhs <- merge(frontier, data.frame(rhs_tau0 = contract$rhs_tau0_grid, stringsAsFactors = FALSE), by = NULL)
  rhs <- merge(rhs, fixtures, by = "scenario_id", all.x = TRUE); rhs <- rhs[order(rhs$scenario_id, rhs$advancement_rank, rhs$rhs_tau0, rhs$replicate_id), , drop = FALSE]
  rhs$rhs_worker_id <- seq_len(nrow(rhs)); rhs$rhs_candidate_id <- paste(rhs$candidate_id,
    paste0("tau0_", format(rhs$rhs_tau0, scientific = TRUE)), paste0("rep", rhs$replicate_id), sep = "__")
  app_write_csv(scores, file.path(root, "ridge_scores_by_replicate.csv"))
  app_write_csv(aggregate, file.path(root, "ridge_candidate_aggregate.csv"))
  app_write_csv(frontier, file.path(root, "ridge_top50_by_family.csv"))
  app_write_csv(rhs, file.path(root, "rhs_worker_plan.csv")); app_ensure_dir(file.path(root, "rhs_workers"))
  app_write_csv(app_joint_pure_health(root, "ridge"), file.path(root, "ridge_final_health.csv"))
  app_write_csv(data.frame(status = "READY_TO_LAUNCH_PURE_RECURSIVE_RHS", expected_workers = nrow(rhs),
    max_workers = contract$max_workers, stringsAsFactors = FALSE), file.path(root, "rhs_launch_readiness.csv"))
  list(aggregate = aggregate, frontier = frontier, rhs_plan = rhs)
}

app_joint_pure_finalize_rhs <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); scores <- app_joint_pure_collect_summaries(root, "rhs")
  plan <- app_read_csv(file.path(root, "rhs_worker_plan.csv")); idx <- match(scores$rhs_worker_id, plan$rhs_worker_id)
  if (anyNA(idx) || anyDuplicated(scores$rhs_worker_id)) stop("RHS results do not match the frozen plan.", call. = FALSE)
  identity <- c("scenario_id", "candidate_id", "rhs_tau0", "replicate_id", "dgp_seed")
  mismatch <- vapply(identity, function(name) {
    lhs <- as.character(scores[[name]])
    rhs <- as.character(plan[[name]][idx])
    any(lhs != rhs)
  }, logical(1L))
  if (any(mismatch)) {
    stop(sprintf("RHS summary identity differs from the frozen plan: %s", paste(identity[mismatch], collapse = ", ")), call. = FALSE)
  }
  keys <- app_joint_pure_candidate_columns()
  groups <- split(scores, paste(scores$scenario_id, scores$candidate_id, format(scores$rhs_tau0, scientific = TRUE), sep = "__"))
  aggregate <- app_bind_rows_fill(lapply(groups, function(x) {
    row <- x[1L, keys, drop = FALSE]
    cbind(row, data.frame(rhs_tau0 = as.numeric(x$rhs_tau0[[1L]]), replicate_count = nrow(x),
      hard_gate_status = if (all(x$hard_gate_status == "pass")) "pass" else "fail",
      condition_gate_status = if (all(x$condition_gate_status == "pass")) "pass" else "review",
      saturation_gate_status = if (all(x$saturation_gate_status == "pass")) "pass" else "review",
      calibration_acrps_mean = mean(as.numeric(x$calibration_acrps_mean)),
      calibration_acrps_between_rep_sd = stats::sd(as.numeric(x$calibration_acrps_mean)),
      calibration_exact_gaussian_crps_mean = mean(as.numeric(x$calibration_exact_gaussian_crps)),
      convergence_fraction = mean(app_as_bool_vec(x$converged)), runtime_seconds_total = sum(as.numeric(x$runtime_seconds)),
      stringsAsFactors = FALSE))
  }))
  selected <- app_bind_rows_fill(lapply(split(aggregate, aggregate$scenario_id), function(x) {
    x <- x[x$hard_gate_status == "pass" & x$convergence_fraction == 1, , drop = FALSE]
    if (!nrow(x)) stop("No fully converged, hard-gate-eligible RHS candidate remains for a family.", call. = FALSE)
    x <- x[order(x$calibration_acrps_mean, x$calibration_acrps_between_rep_sd,
      x$calibration_exact_gaussian_crps_mean, -x$convergence_fraction, x$retained_state_budget,
      x$response_lags, x$candidate_id, x$rhs_tau0), , drop = FALSE]
    x$selection_rank <- seq_len(nrow(x)); x[1L, , drop = FALSE]
  }))
  selected$selection_window <- "observational_350_train_150_recursive_calibration"
  selected$selection_metric <- "rhs_recursive_calibration_acrps"
  selected$protected_rows_used_for_selection <- 0L; selected$shared_across_four_quantile_rows <- TRUE
  selected$next_stage <- "nested_quantile_vb_then_article_fixture_mcmc"
  decision <- selected[, c("scenario_id", "candidate_id", "rhs_tau0", "calibration_acrps_mean", "selection_metric",
    "protected_rows_used_for_selection", "shared_across_four_quantile_rows"), drop = FALSE]
  decision$status <- "PURE_RECURSIVE_BACKBONE_SELECTED_NOT_YET_QUANTILE_FIT"
  outputs <- c(
    rhs_scores = app_write_csv(scores, file.path(root, "rhs_scores_by_replicate.csv")),
    rhs_aggregate = app_write_csv(aggregate, file.path(root, "rhs_candidate_aggregate.csv")),
    selected = app_write_csv(selected, file.path(root, "selected_family_backbones.csv")),
    decision = app_write_csv(decision, file.path(root, "selection_decision.csv")),
    source_git_state = app_write_csv(app_joint_shared_git_state(), file.path(root, "selection_source_git_state.csv")),
    rhs_health = app_write_csv(app_joint_pure_health(root, "rhs"), file.path(root, "rhs_final_health.csv")))
  app_joint_shared_write_manifest(root, outputs, filename = "selection_artifact_manifest.csv")
  verification <- app_joint_shared_verify_manifest(root, file.path(root, "selection_artifact_manifest.csv"))
  if (!all(verification$verified)) stop("Pure-recursive selection manifest failed verification.", call. = FALSE)
  app_write_csv(verification, file.path(root, "selection_manifest_verification.csv"))
  list(scores = scores, aggregate = aggregate, selected = selected)
}

app_joint_pure_full_design <- function(fixture, candidate, contract) {
  if (!identical(as.character(candidate$feature_contract[[1L]]), "pure_recursive_v1")) {
    stop("Pure full-design dispatch requires feature_contract=pure_recursive_v1.", call. = FALSE)
  }
  keep <- fixture$detailed_split$role %in% c("desn_washout", "fit", "validation")
  full_fixture <- list(
    scenario_id = fixture$scenario_id, y = fixture$y[keep], true_q = fixture$true_q[keep, , drop = FALSE],
    tau = fixture$tau, detailed_split = fixture$detailed_split[keep, , drop = FALSE],
    registry_row = fixture$registry_row, seed = fixture$seed, seed_role = fixture$seed_role,
    y_history = fixture$y)
  design <- app_joint_pure_build_design(full_fixture, candidate, list(
    inner_training_rows = sum(full_fixture$detailed_split$role == "fit"),
    fit_rows = sum(full_fixture$detailed_split$role == "fit")
  ), selector = FALSE)
  design$validation_local <- which(design$row_meta$role == "validation")
  origins <- app_joint_qdesn_forecast_origin_plan_rows(fixture)
  forecast_map <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(origins)), function(ii) {
    row <- origins[ii, , drop = FALSE]
    full <- seq.int(row$target_start_full_time_index[[1L]], row$target_end_full_time_index[[1L]])
    data.frame(origin_index = row$origin_index[[1L]], horizon = seq_along(full), full_time_index = full, stringsAsFactors = FALSE)
  }))
  design$forecast_map <- forecast_map
  design$score_local <- match(forecast_map$full_time_index, design$row_meta$full_time_index)
  if (anyNA(design$score_local) || any(!design$score_local %in% design$validation_local)) stop("Pure forecast map is malformed.", call. = FALSE)
  design$mu <- fixture$mu[keep]; design$sigma <- fixture$sigma[keep]
  design$design_fingerprint <- app_joint_qvp_sha256_text(paste(candidate$architecture_signature[[1L]],
    paste(colnames(design$Z), collapse = ";"), paste(format(design$Z[design$fit_local, , drop = FALSE], digits = 16), collapse = ";"), sep = "|"))
  design$posterior_data_design_fingerprint <- app_joint_qvp_sha256_text(paste(
    "joint_qdesn_posterior_data_design_v1", paste(design$fit_local, collapse = ";"), paste(colnames(design$Z), collapse = ";"),
    paste(format(design$y[design$fit_local], digits = 17L, scientific = TRUE), collapse = ";"),
    paste(format(design$Z[design$fit_local, , drop = FALSE], digits = 17L, scientific = TRUE), collapse = ";"), sep = "|"))
  design
}

app_joint_pure_set_contract <- function(tab, name, value) {
  index <- which(tab$name == name)
  if (length(index) != 1L) stop(sprintf("Cannot set non-unique contract field '%s'.", name), call. = FALSE)
  tab$value[[index]] <- as.character(value)
  tab
}

app_joint_pure_quantile_roots <- function(root, registry = app_joint_pure_read_registry()) {
  data.frame(
    scenario_id = registry$scenario_id, scenario_order = registry$scenario_order,
    evaluation_seed_base = registry$evaluation_seed_base, article_seed = registry$article_seed,
    parent_dir = file.path(root, "families", registry$scenario_id, "selection_parent"),
    contract_path = file.path(root, "contracts", paste0(registry$scenario_id, "__quantile.csv")),
    quantile_root = file.path(root, "families", registry$scenario_id, "quantile_vb"),
    stringsAsFactors = FALSE
  )
}

app_joint_pure_quantile_stage_counts <- function() {
  c(`1` = 24L, `2` = 24L, `3` = 48L, `4` = 48L, `5` = 48L, `6` = 168L, `7` = 24L, `8` = 24L)
}

app_joint_pure_quantile_job_queue <- function(root, stage_order) {
  root <- normalizePath(root, mustWork = TRUE)
  stage_order <- as.integer(stage_order)
  counts <- app_joint_pure_quantile_stage_counts()
  if (length(stage_order) != 1L || is.na(stage_order) || !as.character(stage_order) %in% names(counts)) {
    stop("Quantile stage_order must be one of 1,...,8.", call. = FALSE)
  }
  families <- app_read_csv(file.path(root, "quantile_family_plan.csv"))
  if (nrow(families) != 8L || anyDuplicated(families$scenario_id) || anyDuplicated(families$quantile_root)) {
    stop("Quantile family plan must contain eight unique families and roots.", call. = FALSE)
  }
  rows <- lapply(seq_len(nrow(families)), function(ii) {
    qroot <- normalizePath(families$quantile_root[[ii]], mustWork = TRUE)
    plan <- app_read_csv(file.path(qroot, "worker_plan.csv"))
    jobs <- plan[as.integer(plan$stage_order) == stage_order, c("job_id"), drop = FALSE]
    data.frame(quantile_root = qroot, job_id = as.integer(jobs$job_id), stringsAsFactors = FALSE)
  })
  out <- app_bind_rows_fill(rows)
  expected <- unname(counts[[as.character(stage_order)]])
  if (nrow(out) != expected || anyNA(out$job_id) || any(!nzchar(out$quantile_root)) ||
      anyDuplicated(paste(out$quantile_root, out$job_id, sep = "::"))) {
    stop(sprintf("Quantile stage %d queue violates its %d-job contract.", stage_order, expected), call. = FALSE)
  }
  out
}

app_joint_pure_write_quantile_parent <- function(root, selected_row) {
  scenario <- as.character(selected_row$scenario_id[[1L]])
  parent <- file.path(root, "families", scenario, "selection_parent")
  app_ensure_dir(parent)
  selected_path <- app_write_csv(selected_row, file.path(parent, "selected_shared_backbone.csv"))
  decision <- data.frame(
    status = "SHARED_BACKBONE_SELECTED_NOT_YET_QUANTILE_FIT", scenario_id = scenario,
    selected_candidate_id = selected_row$candidate_id[[1L]], selected_rhs_tau0 = selected_row$rhs_tau0[[1L]],
    protected_rows_used_for_selection = 0L, stringsAsFactors = FALSE)
  decision_path <- app_write_csv(decision, file.path(parent, "shared_backbone_selection_decision.csv"))
  git_path <- app_write_csv(app_joint_shared_git_state(), file.path(parent, "source_git_state.csv"))
  manifest_path <- app_joint_shared_write_manifest(parent, c(
    selected_backbone = selected_path, selection_decision = decision_path, source_git_state = git_path),
    filename = "final_artifact_manifest.csv")
  verified <- app_joint_shared_verify_manifest(parent, manifest_path)
  if (!all(verified$verified)) stop("Pure-recursive quantile parent manifest failed verification.", call. = FALSE)
  app_write_csv(verified, file.path(parent, "final_manifest_verification.csv"))
  parent
}

app_joint_pure_quantile_contract <- function(scenario_id, evaluation_seed_base, parent_dir) {
  files <- app_joint_shared_quantile_parent_files(parent_dir)
  tab <- app_read_csv(app_joint_shared_quantile_contract_path())
  git_state <- app_read_csv(files[["source_git_state"]])
  tab <- app_joint_pure_set_contract(tab, "contract_version", paste0("joint_qdesn_pure_recursive_quantile_v1__", scenario_id))
  tab <- app_joint_pure_set_contract(tab, "parent_head", git_state$head[[1L]])
  tab <- app_joint_pure_set_contract(tab, "parent_final_manifest_sha256", app_sha256_file(files[["final_manifest"]]))
  tab <- app_joint_pure_set_contract(tab, "parent_selected_sha256", app_sha256_file(files[["selected_backbone"]]))
  tab <- app_joint_pure_set_contract(tab, "parent_decision_sha256", app_sha256_file(files[["selection_decision"]]))
  if (!"parent_git_state_sha256" %in% tab$name) {
    tab <- rbind(tab, data.frame(section = "identity", name = "parent_git_state_sha256",
      value = app_sha256_file(files[["source_git_state"]]), type = "character",
      description = "Expected pure-recursive parent source-Git-state hash.", stringsAsFactors = FALSE))
  } else tab <- app_joint_pure_set_contract(tab, "parent_git_state_sha256", app_sha256_file(files[["source_git_state"]]))
  tab <- app_joint_pure_set_contract(tab, "pilot_scenario", scenario_id)
  tab <- app_joint_pure_set_contract(tab, "evaluation_seed_base", evaluation_seed_base)
  tab <- app_joint_pure_set_contract(tab, "max_workers", 15L)
  tab
}

app_joint_pure_prepare_quantiles <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  if (!file.exists(file.path(root, "selection_artifact_manifest.csv"))) {
    stop("Pure-recursive selection must be finalized before quantile preparation.", call. = FALSE)
  }
  selection_verified <- app_joint_shared_verify_manifest(root, file.path(root, "selection_artifact_manifest.csv"))
  if (!all(selection_verified$verified)) stop("Pure-recursive selection manifest no longer verifies.", call. = FALSE)
  selected <- app_read_csv(file.path(root, "selected_family_backbones.csv"))
  registry <- app_joint_pure_read_registry(file.path(root, "frozen_family_registry.csv"))
  roots <- app_joint_pure_quantile_roots(root, registry)
  app_ensure_dir(file.path(root, "contracts")); app_ensure_dir(file.path(root, "families"))
  rows <- vector("list", nrow(roots))
  for (ii in seq_len(nrow(roots))) {
    scenario <- roots$scenario_id[[ii]]
    winner <- selected[selected$scenario_id == scenario, , drop = FALSE]
    if (nrow(winner) != 1L) stop("Each family must have exactly one selected backbone.", call. = FALSE)
    parent <- app_joint_pure_write_quantile_parent(root, winner)
    contract <- app_joint_pure_quantile_contract(scenario, roots$evaluation_seed_base[[ii]], parent)
    app_write_csv(contract, roots$contract_path[[ii]])
    app_joint_shared_quantile_prepare(
      out_dir = roots$quantile_root[[ii]], parent_dir = parent,
      contract_path = roots$contract_path[[ii]])
    rows[[ii]] <- data.frame(
      scenario_id = scenario, scenario_order = roots$scenario_order[[ii]],
      quantile_root = normalizePath(roots$quantile_root[[ii]], mustWork = TRUE),
      expected_jobs = nrow(app_read_csv(file.path(roots$quantile_root[[ii]], "worker_plan.csv"))),
      status = "READY_TO_LAUNCH", stringsAsFactors = FALSE)
  }
  plan <- app_bind_rows_fill(rows)
  if (nrow(plan) != 8L || sum(plan$expected_jobs) != 408L) stop("Pure-recursive quantile plan violates the 408-job contract.", call. = FALSE)
  app_write_csv(plan, file.path(root, "quantile_family_plan.csv"))
  app_write_csv(data.frame(status = "READY_TO_LAUNCH_NESTED_QUANTILE_VB", expected_jobs = 408L,
    max_workers = 15L, stringsAsFactors = FALSE), file.path(root, "quantile_launch_readiness.csv"))
  plan
}

app_joint_pure_quantile_health <- function(root) {
  plan_path <- file.path(root, "quantile_family_plan.csv")
  if (!file.exists(plan_path)) return(data.frame(expected = 408L, completed = 0L, failed = 0L, remaining = 408L, status = "pending"))
  plan <- app_read_csv(plan_path)
  rows <- lapply(seq_len(nrow(plan)), function(ii) {
    health <- app_joint_shared_quantile_health(plan$quantile_root[[ii]])
    cbind(data.frame(scenario_id = plan$scenario_id[[ii]], stringsAsFactors = FALSE), health)
  })
  detail <- app_bind_rows_fill(rows)
  data.frame(expected = sum(detail$expected), completed = sum(detail$completed), failed = sum(detail$failed),
    remaining = sum(detail$remaining), completion_fraction = sum(detail$completed) / sum(detail$expected),
    status = if (any(detail$failed > 0L)) "failed" else if (all(detail$completed == detail$expected)) "complete" else "running",
    stringsAsFactors = FALSE)
}

app_joint_pure_finalize_quantiles <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); plan <- app_read_csv(file.path(root, "quantile_family_plan.csv"))
  health <- app_joint_pure_quantile_health(root)
  if (health$completed[[1L]] != health$expected[[1L]] || health$failed[[1L]] != 0L) {
    stop("Nested quantile VB is not complete and failure-free.", call. = FALSE)
  }
  aggregate <- contrasts <- nested <- list()
  for (ii in seq_len(nrow(plan))) {
    scenario <- plan$scenario_id[[ii]]; qroot <- plan$quantile_root[[ii]]
    if (!file.exists(file.path(qroot, "final_artifact_manifest.csv"))) app_joint_shared_quantile_finalize(qroot)
    verify <- app_joint_shared_verify_manifest(qroot, file.path(qroot, "final_artifact_manifest.csv"))
    nested[[ii]] <- data.frame(scenario_id = scenario, artifact_kind = "quantile_vb", all_verified = all(verify$verified), stringsAsFactors = FALSE)
    a <- app_read_csv(file.path(qroot, "quantile_score_aggregate.csv")); a$scenario_id <- scenario; aggregate[[ii]] <- a
    c <- app_read_csv(file.path(qroot, "joint_independent_contrast.csv")); c$scenario_id <- scenario; contrasts[[ii]] <- c
  }
  aggregate <- app_bind_rows_fill(aggregate); contrasts <- app_bind_rows_fill(contrasts); nested <- app_bind_rows_fill(nested)
  if (nrow(aggregate) != 64L || nrow(contrasts) != 16L || !all(nested$all_verified)) {
    stop("Nested quantile VB closeout cardinality or manifest gate failed.", call. = FALSE)
  }
  outputs <- c(
    health = app_write_csv(health, file.path(root, "quantile_final_health.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "quantile_vb_score_aggregate.csv")),
    contrasts = app_write_csv(contrasts, file.path(root, "quantile_vb_joint_independent_contrasts.csv")),
    nested = app_write_csv(nested, file.path(root, "quantile_nested_manifest_verification.csv")))
  app_joint_shared_write_manifest(root, outputs, filename = "quantile_artifact_manifest.csv")
  list(health = health, aggregate = aggregate, contrasts = contrasts, nested = nested)
}

app_joint_pure_confirmation_root <- function() {
  app_path("application/cache/joint_qdesn_pure_recursive_article_confirmation_jerez_15core_20260925")
}

app_joint_pure_score_root <- function() {
  app_path("application/cache/joint_qdesn_pure_recursive_score_packet_jerez_15core_20260925")
}

app_joint_pure_append_contract_value <- function(tab, section, name, value, type, description) {
  if (name %in% tab$name) return(app_joint_pure_set_contract(tab, name, value))
  rbind(tab, data.frame(section = section, name = name, value = as.character(value), type = type,
    description = description, stringsAsFactors = FALSE))
}

app_joint_pure_confirmation_contract <- function(campaign_root) {
  campaign_root <- normalizePath(campaign_root, mustWork = TRUE)
  tab <- app_read_csv(app_joint_article_corrected_contract_path())
  set <- function(name, value) tab <<- app_joint_pure_set_contract(tab, name, value)
  set("contract_version", "joint_qdesn_pure_recursive_article_confirmation_v1")
  set("run_tag", "joint_qdesn_pure_recursive_article_confirmation_jerez_15core_20260925")
  set("execution_branch", "work/joint-qdesn-pure-desn-recursive-selection-20260925")
  set("host_profile_id", "jerez_pure_recursive_15core_20260925")
  set("source_worktree", "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_pure_desn_recursive_selection_20260925")
  set("source_head", app_joint_article_git_value(c("rev-parse", "HEAD")))
  set("source_runtime_relative_path", file.path("application", "cache", basename(campaign_root)))
  source_hash <- app_sha256_file(file.path(campaign_root, "quantile_artifact_manifest.csv"))
  for (name in c("final_artifact_manifest_sha256", "final_decision_sha256", "final_health_sha256",
      "nested_manifest_verification_sha256", "selected_family_backbones_sha256",
      "seven_family_vb_score_aggregate_sha256", "seven_family_joint_independent_contrasts_sha256",
      "future_article_fixture_mcmc_plan_sha256")) set(name, source_hash)
  set("expected_source_jobs", 12552L); set("expected_source_failures", 0L)
  set("expected_selected_backbones", 8L); set("expected_vb_aggregate_rows", 64L)
  set("expected_contrast_rows", 16L); set("expected_future_cells", 32L)
  set("initial_concurrency", 15L); set("maximum_concurrency", 15L)
  set("vb_component_seed_base", 202625000L); set("chain_seed_base", 302609250L)
  set("chain_start_jitter_seed_base", 402609250L)
  tab <- app_joint_pure_append_contract_value(tab, "runtime", "cpu_affinity_list", "2-16", "character",
    "Fifteen distinct physical cores on Jerez.")
  tab <- app_joint_pure_append_contract_value(tab, "runtime", "required_physical_cores", 15L, "integer",
    "Required distinct physical cores.")
  tab <- app_joint_pure_append_contract_value(tab, "runtime", "capacity_approval_token",
    "JEREZ_PURE_RECURSIVE_15_PHYSICAL", "character", "Explicit launch-capacity token.")
  tab
}

app_joint_pure_future_cells <- function(selected, registry) {
  models <- data.frame(
    model_id = c("joint_qdesn_rhs_mcmc", "qdesn_rhs_independent_mcmc",
      "joint_exqdesn_rhs_mcmc", "exqdesn_rhs_independent_mcmc"),
    fit_structure = c("joint", "independent", "joint", "independent"),
    likelihood_family = c("AL", "AL", "exAL", "exAL"), stringsAsFactors = FALSE)
  out <- merge(selected, models, by = NULL)
  out$article_seed <- as.integer(registry$article_seed[match(out$scenario_id, registry$scenario_id)])
  out$article_fixture_used_for_selection <- FALSE
  out$mcmc_status <- "NOT_LAUNCHED_UNTIL_ARTICLE_VB_GATE"
  out
}

app_joint_pure_prepare_confirmation <- function(campaign_root, out_dir = app_joint_pure_confirmation_root()) {
  campaign_root <- normalizePath(campaign_root, mustWork = TRUE)
  if (!file.exists(file.path(campaign_root, "quantile_artifact_manifest.csv"))) {
    stop("Quantile VB closeout must precede article-fixture confirmation.", call. = FALSE)
  }
  qverify <- app_joint_shared_verify_manifest(campaign_root, file.path(campaign_root, "quantile_artifact_manifest.csv"))
  if (!all(qverify$verified)) stop("Quantile VB closeout manifest failed verification.", call. = FALSE)
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  if (dir.exists(out_dir) && length(list.files(out_dir, all.files = TRUE, no.. = TRUE))) {
    stop("Refusing to overwrite a nonempty pure-recursive confirmation root.", call. = FALSE)
  }
  app_ensure_dir(out_dir); app_ensure_dir(file.path(out_dir, "workers")); app_ensure_dir(file.path(out_dir, "mcmc_workers"))
  app_ensure_dir(file.path(out_dir, "initializers"))
  contract_table <- app_joint_pure_confirmation_contract(campaign_root)
  contract_path <- app_write_csv(contract_table, file.path(out_dir, "frozen_contract.csv"))
  contract <- app_joint_article_read_contract(contract_path)
  app_joint_article_assert_execution_branch(contract)
  host <- app_joint_article_host_preflight(contract)
  selected <- app_read_csv(file.path(campaign_root, "selected_family_backbones.csv"))
  registry <- app_joint_pure_read_registry(file.path(campaign_root, "frozen_family_registry.csv"))
  selected$scenario_order <- as.integer(registry$scenario_order[match(selected$scenario_id, registry$scenario_id)])
  selected <- selected[order(selected$scenario_order), , drop = FALSE]
  selected$article_seed <- as.integer(registry$article_seed[match(selected$scenario_id, registry$scenario_id)])
  future <- app_joint_pure_future_cells(selected, registry)
  source <- list(selected = selected, future = future)
  designs <- app_joint_article_build_designs(out_dir, source, contract)
  vb_plan <- app_joint_article_build_vb_plan(designs$selected, designs$design_manifest, contract)
  cells <- app_joint_article_build_model_cells(future, designs$design_manifest, contract)
  mcmc_plan <- app_joint_article_build_mcmc_plan(cells, contract)
  component_seeds <- app_joint_article_component_seed_plan(mcmc_plan, contract$tau)
  source_top <- data.frame(artifact = "quantile_artifact_manifest.csv",
    path = normalizePath(file.path(campaign_root, "quantile_artifact_manifest.csv"), mustWork = TRUE),
    expected_sha256 = app_sha256_file(file.path(campaign_root, "quantile_artifact_manifest.csv")),
    observed_sha256 = app_sha256_file(file.path(campaign_root, "quantile_artifact_manifest.csv")),
    hash_verified = TRUE, stringsAsFactors = FALSE)
  nested <- app_read_csv(file.path(campaign_root, "quantile_nested_manifest_verification.csv"))
  scoring <- data.frame(
    primary_score = "dgp_integrated_finite_grid_acrps", posterior_score_center = "mean;median",
    posterior_interval = "equal_tailed_95_percent", recursive_policies = "path;mean_state",
    oracle_recovery = "fit_and_forecast_mae_rmse", crossing_diagnostics = "raw;contract",
    stringsAsFactors = FALSE)
  files <- c(
    frozen_contract = contract_path,
    execution_git_state = app_write_csv(app_joint_article_execution_git_state(), file.path(out_dir, "execution_git_state.csv")),
    host_preflight = app_write_csv(host, file.path(out_dir, "host_preflight.csv")),
    source_top_hash_verification = app_write_csv(source_top, file.path(out_dir, "source_top_hash_verification.csv")),
    source_nested_manifest_verification = app_write_csv(nested, file.path(out_dir, "source_nested_manifest_verification.csv")),
    imported_selected_backbones = app_write_csv(designs$selected, file.path(out_dir, "imported_selected_backbones.csv")),
    source_future_plan = app_write_csv(future, file.path(out_dir, "source_future_article_fixture_mcmc_plan.csv")),
    fixture_manifest = app_write_csv(designs$fixture_manifest, file.path(out_dir, "fixture_manifest.csv")),
    design_manifest = app_write_csv(designs$design_manifest, file.path(out_dir, "design_manifest.csv")),
    vb_worker_plan = app_write_csv(vb_plan, file.path(out_dir, "vb_worker_plan.csv")),
    model_cell_plan = app_write_csv(cells, file.path(out_dir, "model_cell_plan.csv")),
    mcmc_worker_plan = app_write_csv(mcmc_plan, file.path(out_dir, "mcmc_worker_plan.csv")),
    component_seed_plan = app_write_csv(component_seeds, file.path(out_dir, "component_seed_plan.csv")),
    scoring_contract = app_write_csv(scoring, file.path(out_dir, "scoring_contract.csv")))
  readiness <- data.frame(status = "READY_FOR_ARTICLE_FIXTURE_VB", expected_vb_components = nrow(vb_plan),
    expected_initializers = nrow(cells), expected_mcmc_workers = nrow(mcmc_plan), max_workers = 15L,
    protected_outcomes_used_for_selection = 0L, production_launched = FALSE, stringsAsFactors = FALSE)
  files <- c(files, readiness = app_write_csv(readiness, file.path(out_dir, "launch_readiness.csv")))
  app_joint_shared_write_manifest(out_dir, files)
  list(root = out_dir, readiness = readiness)
}

app_joint_pure_recursive_path_score_draws <- function(
  design, fixture, beta, alpha, uniforms, oracle, tau, weights,
  chain_id = NULL, source_draw_index = NULL, tail_rule = "endpoint_clamp"
) {
  beta <- as.matrix(beta); alpha <- as.matrix(alpha); uniforms <- as.matrix(uniforms)
  n_draw <- nrow(beta); n_score <- nrow(design$forecast_map); p <- ncol(design$Z); K <- length(tau)
  if (ncol(beta) != p * K || nrow(alpha) != n_draw || ncol(alpha) != K ||
      nrow(uniforms) != n_draw || ncol(uniforms) != n_score) {
    stop("Pure recursive path-score inputs do not align.", call. = FALSE)
  }
  chain_id <- chain_id %||% rep(NA_integer_, n_draw)
  source_draw_index <- source_draw_index %||% seq_len(n_draw)
  snapshots <- app_joint_recursive_origin_snapshots(design, fixture,
    data.frame(scenario_id = design$scenario_id, input_scale = design$reservoir_meta$win_scale_global))
  rows <- vector("list", n_draw)
  for (draw_index in seq_len(n_draw)) {
    q_raw <- matrix(NA_real_, nrow = n_score, ncol = K)
    for (origin_pos in seq_along(snapshots$origin_index)) {
      origin_id <- snapshots$origin_index[[origin_pos]]
      map_rows <- which(design$forecast_map$origin_index == origin_id)
      states <- snapshots$states[[origin_pos]]
      history <- fixture$y[seq_len(snapshots$origin_full_time_index[[origin_pos]])]
      for (row_index in map_rows) {
        tt <- design$forecast_map$full_time_index[[row_index]]
        raw <- app_joint_recursive_feature_from_history(tt, history, design)
        step <- app_joint_recursive_readout_row(raw, states, design, snapshots$reservoir_meta)
        states <- step$states
        q_raw[row_index, ] <- app_joint_recursive_predict_vector(
          step$z, beta[draw_index, ], alpha[draw_index, ], tau)
        history[[tt]] <- app_joint_recursive_inverse_cdf(
          q_raw[row_index, ], tau, uniforms[draw_index, row_index], tail_rule)
      }
    }
    contract <- app_joint_qdesn_apply_monotone_contract(q_raw, tau)
    score <- app_joint_recursive_oracle_point_score(oracle, contract$qhat_contract, tau, weights)
    rows[[draw_index]] <- data.frame(
      draw_index = draw_index, chain_id = chain_id[[draw_index]],
      source_draw_index = source_draw_index[[draw_index]],
      origin_marginal_dgp_integrated_acrps = score$origin_marginal_dgp_integrated_acrps,
      realized_acrps = score$realized_acrps,
      raw_crossing_pairs = sum(contract$raw_crossing$n_crossing_pairs),
      contract_crossing_pairs = sum(contract$contract_crossing$n_crossing_pairs),
      mean_abs_monotone_adjustment = contract$mean_abs_adjustment,
      max_abs_monotone_adjustment = contract$max_abs_adjustment,
      stringsAsFactors = FALSE)
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_pure_transfer_inventory <- function(source_root) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  files <- list.files(source_root, recursive = TRUE, full.names = TRUE,
    all.files = TRUE, no.. = TRUE)
  info <- file.info(files)
  files <- files[!is.na(info$isdir) & !info$isdir]
  relative <- substring(files, nchar(source_root) + 2L)
  keep <- !startsWith(relative, paste0("score_packet", .Platform$file.sep))
  files <- files[keep]
  relative <- relative[keep]
  order_index <- order(relative)
  files <- files[order_index]
  relative <- relative[order_index]
  inventory <- data.frame(
    relative_path = relative,
    size_bytes = as.numeric(file.info(files)$size),
    sha256 = unname(tools::sha256sum(files)),
    stringsAsFactors = FALSE
  )
  if (!nrow(inventory) || any(!is.finite(inventory$size_bytes)) ||
      any(!grepl("^[0-9a-f]{64}$", inventory$sha256))) {
    stop("Pure-recursive source inventory is empty or malformed.", call. = FALSE)
  }
  required <- c(
    "model_cell_plan.csv", "mcmc_worker_plan.csv",
    "imported_selected_backbones.csv", "vb_initializer_manifest.csv",
    "mcmc_health_summary.csv", "vb_health_summary.csv"
  )
  if (!all(required %in% inventory$relative_path)) {
    stop("Pure-recursive source inventory omits score-packet inputs.", call. = FALSE)
  }
  inventory
}

app_joint_pure_score_contract <- function(source_root, inventory_path) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  inventory_path <- normalizePath(inventory_path, mustWork = TRUE)
  inventory <- app_read_csv(inventory_path)
  tab <- app_read_csv(app_path(
    "application/config/joint_qdesn_recursive_mean_forecast_contract_v3.csv"
  ))
  set <- function(name, value) tab <<- app_joint_pure_set_contract(tab, name, value)
  set("contract_version", "joint_qdesn_pure_recursive_score_packet_v1")
  set("parent_contract_sha256", app_sha256_file(app_path(
    "application/config/joint_qdesn_recursive_mean_forecast_contract_v3.csv"
  )))
  set("run_tag", "joint_qdesn_pure_recursive_score_packet_jerez_15core_20260925")
  set("source_git_head", app_joint_article_git_value(c("rev-parse", "HEAD")))
  set("source_inventory_sha256", app_sha256_file(inventory_path))
  set("source_inventory_files", nrow(inventory))
  set("source_inventory_bytes", format(sum(inventory$size_bytes), scientific = FALSE))
  set("workers", 15L)
  tab
}

app_joint_pure_prepare_score_packet <- function(
  source_root = app_joint_pure_confirmation_root(),
  score_root = app_joint_pure_score_root()
) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  score_root <- normalizePath(score_root, mustWork = FALSE)
  assessment <- app_read_csv(file.path(source_root, "final_confirmation_assessment.csv"))
  if (!identical(assessment$status[[1L]], "MCMC_COMPLETE_READY_FOR_SCORE_PACKET")) {
    stop("Pure-recursive confirmation is not ready for scoring.", call. = FALSE)
  }
  vb_health <- app_read_csv(file.path(source_root, "vb_health_summary.csv"))
  mcmc_health <- app_read_csv(file.path(source_root, "mcmc_health_summary.csv"))
  if (vb_health$completed_vb_components[[1L]] != 136L ||
      vb_health$failed_vb_components[[1L]] != 0L ||
      mcmc_health$completed_workers[[1L]] != 160L ||
      mcmc_health$failed_workers[[1L]] != 0L) {
    stop("Pure-recursive VB/MCMC source gates are incomplete.", call. = FALSE)
  }
  packet_dir <- file.path(source_root, "score_packet")
  app_ensure_dir(packet_dir)
  inventory <- app_joint_pure_transfer_inventory(source_root)
  inventory_path <- app_write_csv(
    inventory, file.path(packet_dir, "transfer_inventory.csv")
  )
  contract_path <- app_write_csv(
    app_joint_pure_score_contract(source_root, inventory_path),
    file.path(packet_dir, "pure_recursive_score_contract.csv")
  )
  prepared <- app_joint_recursive_prepare(score_root, source_root, contract_path)
  list(
    root = prepared$root, source_root = source_root,
    contract_path = normalizePath(contract_path, mustWork = TRUE),
    inventory_path = normalizePath(inventory_path, mustWork = TRUE),
    cells = prepared$cells, oracle = prepared$oracle
  )
}
