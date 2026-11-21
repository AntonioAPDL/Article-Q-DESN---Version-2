# Stronger-window, case-specific pure-DESN screening and gated continuation.

app_joint_sw_contract_path <- function() {
  app_path("application/config/joint_qdesn_stronger_window_contract_v1.csv")
}

app_joint_sw_axes_path <- function() {
  app_path("application/config/joint_qdesn_stronger_window_axes_v1.csv")
}

app_joint_sw_registry_path <- function() {
  app_path("application/config/joint_qdesn_stronger_window_registry_v1.csv")
}

app_joint_sw_anchor_registry_path <- function() {
  app_path("application/config/joint_qdesn_stronger_window_anchor_registry_v1.csv")
}

app_joint_sw_default_root <- function() {
  app_path("application/cache/joint_qdesn_stronger_window_richer_screen_20261121")
}

app_joint_sw_value <- function(tab, name) {
  row <- tab[tab$name == name, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("Stronger-window contract requires one '%s'.", name), call. = FALSE)
  as.character(row$value[[1L]])
}

app_joint_sw_read_contract <- function(path = app_joint_sw_contract_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("section", "name", "value", "type", "description"),
    "stronger-window contract")
  if (anyDuplicated(tab$name)) stop("Stronger-window contract fields must be unique.", call. = FALSE)
  value <- function(name) app_joint_sw_value(tab, name)
  numvec <- function(name) as.numeric(strsplit(value(name), ";", fixed = TRUE)[[1L]])
  intvec <- function(name) as.integer(numvec(name))
  bool <- function(name) identical(tolower(value(name)), "true")
  out <- list(
    table = tab,
    version = value("contract_version"),
    run_tag = value("run_tag"),
    scenario_count = as.integer(value("scenario_count")),
    tau = numvec("quantile_grid"),
    desn_washout_rows = as.integer(value("desn_washout_rows")),
    fit_rows = as.integer(value("fit_rows")),
    inner_training_rows = as.integer(value("inner_training_rows")),
    inner_calibration_rows = as.integer(value("inner_calibration_rows")),
    protected_validation_rows = as.integer(value("protected_validation_rows")),
    calibration_origin_stride = as.integer(value("calibration_origin_stride")),
    calibration_max_lead = as.integer(value("calibration_max_lead")),
    r1a_origins = intvec("r1a_origin_indices"),
    r1b_origins = intvec("r1b_origin_indices"),
    full_origins = intvec("full_origin_indices"),
    origin_update_policy = value("origin_update_policy"),
    within_origin_policy = value("within_origin_policy"),
    canonical_posterior_policy = value("canonical_posterior_policy"),
    sensitivity_posterior_policy = value("sensitivity_posterior_policy"),
    candidate_count = as.integer(value("candidate_count")),
    anchor_count = as.integer(value("anchor_count")),
    local_count = as.integer(value("local_count")),
    global_count = as.integer(value("global_count")),
    mechanism_count = as.integer(value("mechanism_count")),
    high_capacity_count = as.integer(value("high_capacity_count")),
    r1a_advance_count = as.integer(value("r1a_advance_count")),
    r1b_advance_count = as.integer(value("r1b_advance_count")),
    r2_advance_count = as.integer(value("r2_advance_count")),
    r3_advance_count = as.integer(value("r3_advance_count")),
    r1a_high_capacity_quota = as.integer(value("r1a_high_capacity_quota")),
    r1a_diversity_quota = as.integer(value("r1a_diversity_quota")),
    r1b_high_capacity_quota = as.integer(value("r1b_high_capacity_quota")),
    r1b_diversity_quota = as.integer(value("r1b_diversity_quota")),
    r2_high_capacity_quota = as.integer(value("r2_high_capacity_quota")),
    r2_diversity_quota = as.integer(value("r2_diversity_quota")),
    ridge_tau2 = as.numeric(value("ridge_tau2")),
    intercept_variance = as.numeric(value("intercept_variance")),
    sigma_shape = as.numeric(value("sigma_shape")),
    sigma_rate = as.numeric(value("sigma_rate")),
    calibration_replicates = as.integer(value("calibration_replicates")),
    reservoir_seed_offsets = intvec("additional_reservoir_seed_offsets"),
    rhs_tau0_grid = numvec("coarse_tau0_grid"),
    h2_tau_per_architecture = as.integer(value("h2_tau_per_architecture")),
    h3_neighborhood_count = as.integer(value("h3_neighborhood_count")),
    refinement_factor = as.numeric(value("refinement_factor")),
    refinement_min_tau0 = as.numeric(value("refinement_min_tau0")),
    refinement_max_tau0 = as.numeric(value("refinement_max_tau0")),
    rhs_max_iter = as.integer(value("rhs_max_iter")),
    rhs_min_iter = as.integer(value("rhs_min_iter")),
    rhs_tolerance = as.numeric(value("rhs_tolerance")),
    median_advance_count = as.integer(value("median_advance_count")),
    seven_grid_advance_count = as.integer(value("seven_grid_advance_count")),
    median_max_iter = as.integer(value("median_max_iter")),
    quantile_max_iter = as.integer(value("quantile_max_iter")),
    vb_tolerance = as.numeric(value("vb_tolerance")),
    max_condition_number = as.numeric(value("max_condition_number")),
    max_state_saturation = as.numeric(value("max_state_saturation")),
    ordinary_promotion_dimension = as.integer(value("ordinary_promotion_dimension")),
    conditional_promotion_dimension = as.integer(value("conditional_promotion_dimension")),
    maximum_ridge_dimension = as.integer(value("maximum_ridge_dimension")),
    protected_selection_forbidden = bool("protected_selection_forbidden"),
    require_finite_scores = bool("require_finite_scores"),
    max_workers = as.integer(value("max_workers")),
    min_data_free_gib = as.numeric(value("min_data_free_gib")),
    min_available_memory_gib = as.numeric(value("min_available_memory_gib")),
    host_reserve_memory_gib = as.numeric(value("host_reserve_memory_gib")),
    blas_threads = as.integer(value("blas_threads")),
    nice_level = as.integer(value("nice_level")),
    automatic_stop_after = value("automatic_stop_after"),
    exal_mcmc_method = value("exal_mcmc_method"),
    max_readout_dimension = as.integer(value("maximum_ridge_dimension"))
  )
  valid <- identical(out$version, "joint_qdesn_stronger_window_richer_screen_v1") &&
    out$scenario_count == 8L && length(out$tau) == 7L &&
    out$desn_washout_rows + out$fit_rows + out$protected_validation_rows == 2800L &&
    out$inner_training_rows + out$inner_calibration_rows == out$fit_rows &&
    out$inner_calibration_rows == out$calibration_max_lead * length(out$full_origins) &&
    all(out$r1a_origins %in% out$r1b_origins) && all(out$r1b_origins %in% out$full_origins) &&
    out$candidate_count == out$anchor_count + out$local_count + out$global_count +
      out$mechanism_count + out$high_capacity_count &&
    out$r1a_advance_count > out$r1b_advance_count &&
    out$r1b_advance_count > out$r2_advance_count &&
    out$r2_advance_count > out$r3_advance_count &&
    out$r1a_high_capacity_quota + out$anchor_count < out$r1a_advance_count &&
    out$r1b_high_capacity_quota + out$anchor_count < out$r1b_advance_count &&
    out$r2_high_capacity_quota + out$anchor_count < out$r2_advance_count &&
    out$protected_selection_forbidden && identical(out$exal_mcmc_method, "exact_M0") &&
    identical(out$automatic_stop_after, "benchmark_review")
  if (!valid) stop("Stronger-window scientific contract is malformed.", call. = FALSE)
  out
}

app_joint_sw_read_axes <- function(path = app_joint_sw_axes_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("profile", "axis", "values", "role"), "stronger-window axes")
  if (anyDuplicated(paste(tab$profile, tab$axis))) stop("Stronger-window axes are duplicated.", call. = FALSE)
  get <- function(axis, numeric = FALSE) {
    row <- tab[tab$profile == "common" & tab$axis == axis, , drop = FALSE]
    if (nrow(row) != 1L) stop(sprintf("Missing stronger-window axis '%s'.", axis), call. = FALSE)
    x <- strsplit(as.character(row$values[[1L]]), ";", fixed = TRUE)[[1L]]
    if (numeric) as.numeric(x) else x
  }
  list(
    table = tab,
    depth = as.integer(get("depth", TRUE)),
    state_budget = as.integer(get("state_budget", TRUE)),
    width_shape = get("width_shape"),
    response_lags = as.integer(get("response_lags", TRUE)),
    exogenous_lags = as.integer(get("exogenous_lags", TRUE)),
    alpha_range = get("alpha_range", TRUE),
    rho_range = get("rho_range", TRUE),
    global_schedule = get("global_schedule"),
    special_schedule = get("special_schedule"),
    input_scale = get("input_scale", TRUE),
    pi_in = get("pi_in", TRUE),
    pi_w_fixed = get("pi_w_fixed", TRUE),
    recurrent_expected_degree = get("recurrent_expected_degree", TRUE),
    minimum_layer_width = as.integer(get("minimum_generated_layer_width", TRUE)),
    high_capacity_budget = as.integer(get("high_capacity_budget", TRUE))
  )
}

app_joint_sw_read_registry <- function(path = app_joint_sw_registry_path()) {
  x <- app_read_csv(path)
  app_check_required_columns(x, c("enabled", "scenario_id", "scenario_order", "selector_seed_base",
    "article_seed", "canonical_reservoir_seed"), "stronger-window registry")
  x$enabled <- app_as_bool_vec(x$enabled)
  x <- x[x$enabled, , drop = FALSE]
  if (nrow(x) != 8L || anyDuplicated(x$scenario_id) || anyDuplicated(x$scenario_order) ||
      anyDuplicated(x$selector_seed_base)) stop("Stronger-window registry is malformed.", call. = FALSE)
  x[order(x$scenario_order), , drop = FALSE]
}

app_joint_sw_derived_dgp_registry <- function(
  contract = app_joint_sw_read_contract(),
  registry = app_joint_sw_read_registry()
) {
  source <- app_joint_qdesn_load_simulation_registry()
  out <- source[match(registry$scenario_id, source$scenario_id), , drop = FALSE]
  if (anyNA(out$scenario_id)) stop("A stronger-window scenario is absent from the DGP registry.", call. = FALSE)
  out$registry_version <- "joint_qdesn_stronger_window_20261121"
  out$analysis_window_length <- 2800L
  out$washout_length <- 9700L
  out$desn_washout_length <- contract$desn_washout_rows
  out$train_length <- contract$fit_rows
  out$fit_length <- contract$fit_rows
  out$test_length <- contract$protected_validation_rows
  out$validation_length <- contract$protected_validation_rows
  out$forecast_origin_stride <- contract$calibration_origin_stride
  out$max_lead <- contract$calibration_max_lead
  out
}

app_joint_sw_fixture_identity_audit <- function(
  contract = app_joint_sw_read_contract(),
  registry = app_joint_sw_read_registry()
) {
  source <- app_joint_qdesn_load_simulation_registry()
  derived <- app_joint_sw_derived_dgp_registry(contract, registry)
  rows <- lapply(seq_len(nrow(registry)), function(ii) {
    scenario <- registry$scenario_id[[ii]]
    old_row <- source[source$scenario_id == scenario, , drop = FALSE]
    new_row <- derived[derived$scenario_id == scenario, , drop = FALSE]
    old_row$seed <- new_row$seed <- registry$article_seed[[ii]]
    old_fixture <- app_joint_qdesn_fixture_from_registry_row(old_row)
    new_fixture <- app_joint_qdesn_fixture_from_registry_row(new_row)
    old_idx <- which(old_fixture$detailed_split$role == "validation")
    new_idx <- which(new_fixture$detailed_split$role == "validation")
    same_index <- identical(old_fixture$detailed_split$full_time_index[old_idx],
      new_fixture$detailed_split$full_time_index[new_idx])
    same_y <- identical(old_fixture$y[old_idx], new_fixture$y[new_idx])
    same_q <- identical(old_fixture$true_q[old_idx, , drop = FALSE],
      new_fixture$true_q[new_idx, , drop = FALSE])
    data.frame(
      scenario_id = scenario,
      protected_rows = length(new_idx),
      protected_start = min(new_fixture$detailed_split$full_time_index[new_idx]),
      protected_end = max(new_fixture$detailed_split$full_time_index[new_idx]),
      index_identical = same_index,
      response_identical = same_y,
      oracle_quantiles_identical = same_q,
      response_sha256 = app_joint_qvp_sha256_text(paste(format(new_fixture$y[new_idx], digits = 17L), collapse = ";")),
      oracle_sha256 = app_joint_qvp_sha256_text(paste(format(new_fixture$true_q[new_idx, ], digits = 17L), collapse = ";")),
      verified = same_index && same_y && same_q && length(new_idx) == contract$protected_validation_rows,
      stringsAsFactors = FALSE
    )
  })
  out <- app_bind_rows_fill(rows)
  if (!all(out$verified)) stop("Protected-row identity audit failed.", call. = FALSE)
  out
}

app_joint_sw_widths <- function(D, budget, shape, minimum = 2L) {
  D <- as.integer(D)
  budget <- as.integer(budget)
  minimum <- as.integer(minimum)
  if (D < 1L || budget < D * minimum) stop("Infeasible stronger-window width request.", call. = FALSE)
  x <- seq_len(D)
  weights <- switch(as.character(shape),
    flat = rep(1, D),
    tapered = rev(x),
    expanding = x,
    bottleneck = abs(x - (D + 1) / 2) + 1,
    hourglass = max(abs(x - (D + 1) / 2)) + 1 - abs(x - (D + 1) / 2),
    stop("Unknown stronger-window width shape.", call. = FALSE)
  )
  remaining <- budget - D * minimum
  raw <- remaining * weights / sum(weights)
  extra <- floor(raw)
  remainder <- remaining - sum(extra)
  if (remainder > 0L) {
    order_index <- order(-(raw - extra), seq_len(D))
    extra[order_index[seq_len(remainder)]] <- extra[order_index[seq_len(remainder)]] + 1L
  }
  out <- as.integer(minimum + extra)
  if (length(out) != D || sum(out) != budget || any(out < minimum)) {
    stop("Stronger-window width allocation failed.", call. = FALSE)
  }
  out
}

app_joint_sw_primes <- function(n) {
  out <- integer()
  candidate <- 2L
  while (length(out) < n) {
    upper <- floor(sqrt(candidate))
    prime <- candidate == 2L || upper < 2L || all(candidate %% seq.int(2L, upper) != 0L)
    if (isTRUE(prime)) out <- c(out, candidate)
    candidate <- candidate + 1L
  }
  out
}

app_joint_sw_radical_inverse <- function(index, base) {
  value <- 0
  factor <- 1 / base
  x <- as.integer(index)
  while (x > 0L) {
    value <- value + factor * (x %% base)
    x <- x %/% base
    factor <- factor / base
  }
  value
}

app_joint_sw_halton <- function(n, d, skip = 0L) {
  bases <- app_joint_sw_primes(d)
  out <- matrix(0, nrow = n, ncol = d)
  for (jj in seq_len(d)) {
    out[, jj] <- vapply(seq_len(n) + as.integer(skip), app_joint_sw_radical_inverse,
      numeric(1L), base = bases[[jj]])
  }
  out
}

app_joint_sw_pick <- function(values, u) {
  values[[min(length(values), floor(u * length(values)) + 1L)]]
}

app_joint_sw_schedule <- function(center, D, kind, span, lower, upper) {
  if (D == 1L || identical(kind, "flat")) return(rep(pmin(upper, pmax(lower, center)), D))
  z <- seq(-1, 1, length.out = D)
  offset <- switch(as.character(kind),
    increasing = z,
    decreasing = -z,
    u_shape = 2 * abs(z) - 1,
    unconstrained = sin(seq(0, 2 * pi, length.out = D) + center),
    rep(0, D)
  )
  pmin(upper, pmax(lower, center + span * offset))
}

app_joint_sw_fmt <- function(x) paste(format(as.numeric(x), digits = 10L, trim = TRUE), collapse = ";")

app_joint_sw_structural_signature <- function(row) {
  fields <- c("D", "n", "response_lags", "exogenous_lags", "alpha", "rho",
    "input_scale", "pi_w", "pi_in", "width_shape")
  app_joint_qvp_sha256_text(paste(vapply(fields, function(nm) paste0(nm, "=", row[[nm]][[1L]]),
    character(1L)), collapse = "|"))
}

app_joint_sw_candidate_from_point <- function(
  scenario_id,
  H,
  role,
  axes,
  canonical_seed,
  local_anchor = NULL,
  high_capacity = FALSE,
  special_schedule = FALSE
) {
  D <- as.integer(app_joint_sw_pick(axes$depth, H[[1L]]))
  budgets <- if (high_capacity) axes$high_capacity_budget else {
    setdiff(axes$state_budget, axes$high_capacity_budget)
  }
  budget <- as.integer(app_joint_sw_pick(budgets, H[[2L]]))
  shape <- as.character(app_joint_sw_pick(axes$width_shape, H[[3L]]))
  if (!is.null(local_anchor)) {
    anchor_D <- as.integer(local_anchor$D[[1L]])
    D <- max(1L, min(8L, anchor_D + c(-1L, 0L, 1L)[min(3L, floor(H[[1L]] * 3) + 1L)]))
    anchor_budget <- as.integer(local_anchor$retained_state_budget[[1L]])
    candidates <- axes$state_budget[order(abs(log(axes$state_budget) - log(anchor_budget)))]
    budget <- as.integer(app_joint_sw_pick(head(candidates, min(6L, length(candidates))), H[[2L]]))
    shape <- as.character(app_joint_sw_pick(unique(c(as.character(local_anchor$width_shape[[1L]]), axes$width_shape)), H[[3L]]))
  }
  budget <- max(budget, D * axes$minimum_layer_width)
  widths <- app_joint_sw_widths(D, budget, shape, axes$minimum_layer_width)
  response_lags <- as.integer(app_joint_sw_pick(axes$response_lags, H[[4L]]))
  if (!is.null(local_anchor)) {
    anchor_lag <- as.integer(local_anchor$response_lags[[1L]])
    lag_near <- axes$response_lags[order(abs(log1p(axes$response_lags) - log1p(anchor_lag)))]
    response_lags <- as.integer(app_joint_sw_pick(head(lag_near, min(8L, length(lag_near))), H[[4L]]))
  }
  alpha_center <- stats::plogis(stats::qlogis(axes$alpha_range[[1L]]) +
    H[[5L]] * diff(stats::qlogis(axes$alpha_range)))
  rho_center <- axes$rho_range[[1L]] + H[[6L]] * diff(axes$rho_range)
  if (!is.null(local_anchor)) {
    alpha_center <- pmin(0.995, pmax(0.005,
      mean(app_joint_shared_parse_num_vec(local_anchor$alpha[[1L]])) + (H[[5L]] - 0.5) * 0.30))
    rho_center <- pmin(0.999, pmax(0.10,
      mean(app_joint_shared_parse_num_vec(local_anchor$rho[[1L]])) + (H[[6L]] - 0.5) * 0.24))
  }
  schedules <- if (special_schedule) axes$special_schedule else axes$global_schedule
  alpha_kind <- as.character(app_joint_sw_pick(schedules, H[[7L]]))
  rho_kind <- as.character(app_joint_sw_pick(schedules, H[[8L]]))
  alpha <- app_joint_sw_schedule(alpha_center, D, alpha_kind, 0.30 * H[[9L]], 0.005, 0.995)
  rho <- app_joint_sw_schedule(rho_center, D, rho_kind, 0.20 * H[[10L]], 0.10, 0.999)
  input_scale <- as.numeric(app_joint_sw_pick(axes$input_scale, H[[11L]]))
  pi_in <- rep(as.numeric(app_joint_sw_pick(axes$pi_in, H[[12L]])), D)
  if (H[[13L]] < 0.5) {
    pi_w <- rep(as.numeric(app_joint_sw_pick(axes$pi_w_fixed, H[[14L]])), D)
    sparsity_mode <- "fixed_probability"
  } else {
    degree <- as.numeric(app_joint_sw_pick(axes$recurrent_expected_degree, H[[14L]]))
    pi_w <- pmin(1, degree / widths)
    sparsity_mode <- paste0("expected_degree_", format(degree, trim = TRUE))
  }
  row <- data.frame(
    scenario_id = scenario_id,
    candidate_role = role,
    feature_contract = "pure_recursive_v1",
    design_class = "reservoir",
    D = D,
    n = app_joint_sw_fmt(widths),
    n_tilde = if (D > 1L) app_joint_sw_fmt(widths[seq_len(D - 1L)]) else "",
    retained_state_budget = sum(widths),
    width_shape = shape,
    state_reduction = FALSE,
    response_lags = response_lags,
    exogenous_lags = 0L,
    alpha = app_joint_sw_fmt(alpha),
    rho = app_joint_sw_fmt(rho),
    pi_w = app_joint_sw_fmt(pi_w),
    pi_in = app_joint_sw_fmt(pi_in),
    input_scale = input_scale,
    recurrent_sparsity_mode = sparsity_mode,
    reservoir_seed = as.integer(canonical_seed),
    raw_inputs_in_readout = FALSE,
    full_states_all_layers = TRUE,
    source_rhs_tau0 = NA_real_,
    stringsAsFactors = FALSE
  )
  row$structural_signature <- app_joint_sw_structural_signature(row)
  row$architecture_signature <- app_joint_pure_architecture_signature(row)
  row
}

app_joint_sw_normalize_anchor <- function(row, scenario_id, canonical_seed, role) {
  row <- row[1L, , drop = FALSE]
  needed <- c("D", "n", "n_tilde", "retained_state_budget", "width_shape", "response_lags",
    "exogenous_lags", "alpha", "rho", "pi_w", "pi_in", "input_scale")
  if (!all(needed %in% names(row))) stop("Anchor row lacks pure-DESN fields.", call. = FALSE)
  out <- row[, needed, drop = FALSE]
  out$scenario_id <- scenario_id
  out$candidate_role <- role
  out$feature_contract <- "pure_recursive_v1"
  out$design_class <- "reservoir"
  out$state_reduction <- FALSE
  out$recurrent_sparsity_mode <- "historical_exact"
  out$reservoir_seed <- as.integer(canonical_seed)
  out$raw_inputs_in_readout <- FALSE
  out$full_states_all_layers <- TRUE
  out$source_rhs_tau0 <- if ("rhs_tau0" %in% names(row)) as.numeric(row$rhs_tau0[[1L]]) else NA_real_
  out$structural_signature <- app_joint_sw_structural_signature(out)
  out$architecture_signature <- app_joint_pure_architecture_signature(out)
  out
}

app_joint_sw_exact_anchors <- function(scenario_id, canonical_seed) {
  rows <- list()
  for (source in c("tables/joint_qdesn_pure_desn_v2_selected_backbones.csv",
      "tables/joint_qdesn_pure_desn_v1_selected_backbones.csv")) {
    tab <- app_read_csv(app_path(source))
    row <- tab[tab$scenario_id == scenario_id, , drop = FALSE]
    if (nrow(row) == 1L) rows[[length(rows) + 1L]] <- app_joint_sw_normalize_anchor(
      row, scenario_id, canonical_seed,
      if (grepl("v2", source, fixed = TRUE)) "anchor_authoritative_v2" else "anchor_pure_v1")
  }
  old_axes <- app_joint_pure_read_axes()
  old_axes$depth <- 1:8
  old_axes$reservoir_seed <- as.integer(canonical_seed)
  historical <- app_joint_pure_anchor_candidate(scenario_id, axes = old_axes,
    anchors = app_joint_pure_read_anchors())
  if (!is.null(historical)) rows[[length(rows) + 1L]] <- app_joint_sw_normalize_anchor(
    historical, scenario_id, canonical_seed, "anchor_historical_translation")
  app_bind_rows_fill(rows)
}

app_joint_sw_take_unique <- function(pool, n, used = character()) {
  pool <- pool[!pool$structural_signature %in% used, , drop = FALSE]
  pool <- pool[!duplicated(pool$structural_signature), , drop = FALSE]
  if (nrow(pool) < n) stop("Candidate pool is too small after deterministic deduplication.", call. = FALSE)
  pool[seq_len(n), , drop = FALSE]
}

app_joint_sw_candidate_registry <- function(
  scenario_id,
  contract = app_joint_sw_read_contract(),
  axes = app_joint_sw_read_axes(),
  registry = app_joint_sw_read_registry()
) {
  rr <- registry[registry$scenario_id == scenario_id, , drop = FALSE]
  if (nrow(rr) != 1L) stop("Unknown stronger-window scenario.", call. = FALSE)
  canonical_seed <- as.integer(rr$canonical_reservoir_seed[[1L]])
  exact <- app_joint_sw_exact_anchors(scenario_id, canonical_seed)
  parity <- exact[exact$candidate_role == "anchor_authoritative_v2", , drop = FALSE]
  if (nrow(parity) != 1L) stop("Each scenario requires one authoritative v2 anchor.", call. = FALSE)

  make_pool <- function(n, skip, role, local = NULL, high = FALSE, special = FALSE) {
    H <- app_joint_sw_halton(n, 14L, skip)
    app_bind_rows_fill(lapply(seq_len(n), function(ii) app_joint_sw_candidate_from_point(
      scenario_id, H[ii, ], role, axes, canonical_seed,
      local_anchor = local, high_capacity = high, special_schedule = special)))
  }

  anchor_pool <- app_bind_rows_fill(list(
    exact,
    make_pool(8L * contract$anchor_count, 1000L + rr$scenario_order[[1L]] * 100L,
      "anchor_derived", local = parity, special = TRUE)
  ))
  anchors <- app_joint_sw_take_unique(anchor_pool, contract$anchor_count)
  used <- anchors$structural_signature
  local_pool <- make_pool(3L * contract$local_count, 10000L + rr$scenario_order[[1L]] * 1000L,
    "learned_local", local = parity, special = TRUE)
  local <- app_joint_sw_take_unique(local_pool, contract$local_count, used)
  used <- c(used, local$structural_signature)
  global_pool <- make_pool(2L * contract$global_count, 30000L + rr$scenario_order[[1L]] * 2000L,
    "global_low_discrepancy", special = FALSE)
  global <- app_joint_sw_take_unique(global_pool, contract$global_count, used)
  used <- c(used, global$structural_signature)
  mechanism_pool <- make_pool(3L * contract$mechanism_count, 60000L + rr$scenario_order[[1L]] * 2000L,
    "mechanism_specific", local = parity, special = TRUE)
  mechanism <- app_joint_sw_take_unique(mechanism_pool, contract$mechanism_count, used)
  used <- c(used, mechanism$structural_signature)
  high_pool <- make_pool(4L * contract$high_capacity_count, 90000L + rr$scenario_order[[1L]] * 2000L,
    "high_capacity_sentinel", high = TRUE, special = TRUE)
  high <- app_joint_sw_take_unique(high_pool, contract$high_capacity_count, used)
  out <- app_bind_rows_fill(list(anchors, local, global, mechanism, high))
  out <- out[order(out$candidate_role, out$structural_signature), , drop = FALSE]
  out$candidate_id <- sprintf("%s__stronger_%04d", scenario_id, seq_len(nrow(out)))
  out$execution_signature <- vapply(seq_len(nrow(out)), function(ii) {
    app_joint_qvp_sha256_text(paste(out$structural_signature[[ii]], out$reservoir_seed[[ii]], sep = "|"))
  }, character(1L))
  if (nrow(out) != contract$candidate_count || anyDuplicated(out$structural_signature) ||
      sum(out$candidate_role == "high_capacity_sentinel") != contract$high_capacity_count ||
      sum(grepl("^anchor_", out$candidate_role)) != contract$anchor_count) {
    stop("Stronger-window candidate allocation failed.", call. = FALSE)
  }
  out[, c("candidate_id", setdiff(names(out), "candidate_id")), drop = FALSE]
}

app_joint_sw_origin_rows <- function(design, origin_indices, max_lead) {
  cal <- design$calibration_local
  blocks <- split(cal, ceiling(seq_along(cal) / max_lead))
  if (any(!origin_indices %in% seq_along(blocks)) || any(lengths(blocks) != max_lead)) {
    stop("Requested calibration origins are incompatible with the design.", call. = FALSE)
  }
  blocks[origin_indices]
}

app_joint_sw_recursive_gaussian <- function(design, fixture, fit, contract, origin_indices) {
  blocks <- app_joint_sw_origin_rows(design, origin_indices, contract$calibration_max_lead)
  score_local <- unlist(blocks, use.names = FALSE)
  qhat <- matrix(NA_real_, nrow = length(score_local), ncol = length(design$tau))
  pred_mean <- pred_sd <- numeric(length(score_local))
  full_time <- origin <- horizon <- integer(length(score_local))
  cursor <- 0L
  for (block_position in seq_along(blocks)) {
    block <- blocks[[block_position]]
    origin_id <- origin_indices[[block_position]]
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
      state_raw <- app_qdesn_readout_row_from_states(states, design$reservoir)
      state <- (state_raw - design$state_center) / design$state_scale
      x <- matrix(c(1, state), nrow = 1L, dimnames = list(NULL, colnames(design$X)))
      pred <- app_joint_ridge_predict_dispatch(fit, x, chunk_size = 1L)
      cursor <- cursor + 1L
      pred_mean[[cursor]] <- pred$mean[[1L]]
      pred_sd[[cursor]] <- pred$sd[[1L]]
      qhat[cursor, ] <- pred$mean[[1L]] + pred$sd[[1L]] * stats::qnorm(design$tau)
      full_time[[cursor]] <- tt
      origin[[cursor]] <- origin_id
      horizon[[cursor]] <- hh
      history[[tt]] <- pred$mean[[1L]]
    }
  }
  list(qhat = qhat, pred_mean = pred_mean, pred_sd = pred_sd,
    score_local = score_local, full_time_index = full_time, origin_index = origin, horizon = horizon)
}

app_joint_sw_vm_hwm_kib <- function() {
  path <- "/proc/self/status"
  if (!file.exists(path)) return(NA_real_)
  line <- grep("^VmHWM:", readLines(path, warn = FALSE), value = TRUE)
  if (!length(line)) return(NA_real_)
  as.numeric(sub("^VmHWM:[[:space:]]*([0-9]+).*", "\\1", line[[1L]]))
}

app_joint_sw_score_ridge <- function(fixture, candidate, contract, origin_indices) {
  total_started <- proc.time()[[3L]]
  design_started <- proc.time()[[3L]]
  design <- app_joint_pure_build_design(fixture, candidate, contract, selector = TRUE)
  design_seconds <- proc.time()[[3L]] - design_started
  tr <- design$train_local
  backend <- if (ncol(design$X) >= length(tr)) "dual" else "primal"
  fit_started <- proc.time()[[3L]]
  fit <- app_joint_ridge_fit_dispatch(
    design$X[tr, , drop = FALSE], design$y[tr],
    ridge_tau2 = contract$ridge_tau2,
    intercept_var = contract$intercept_variance,
    sigma_a = contract$sigma_shape,
    sigma_b = contract$sigma_rate,
    backend = backend
  )
  fit_seconds <- proc.time()[[3L]] - fit_started
  forecast_started <- proc.time()[[3L]]
  pred <- app_joint_sw_recursive_gaussian(design, fixture, fit, contract, origin_indices)
  forecast_seconds <- proc.time()[[3L]] - forecast_started
  score <- app_joint_shared_acrps(design$y[pred$score_local], pred$qhat, design$tau)
  oracle <- pred$qhat - design$true_q[pred$score_local, , drop = FALSE]
  summary <- cbind(candidate, data.frame(
    status = "completed",
    ridge_backend = backend,
    covariance_representation = fit$covariance_representation,
    materialized_parameter_covariance = isTRUE(fit$materialized_parameter_covariance),
    n_analysis = nrow(design$X),
    n_train = length(tr),
    n_calibration_scored = length(pred$score_local),
    origin_indices = paste(origin_indices, collapse = ";"),
    protected_rows_loaded = design$diagnostic$protected_rows_loaded,
    n_features = ncol(design$X),
    effective_rank = design$diagnostic$effective_rank,
    condition_number = design$diagnostic$condition_number,
    state_saturation_fraction = design$diagnostic$state_saturation_fraction,
    calibration_acrps_mean = mean(score),
    calibration_acrps_sd = stats::sd(score),
    calibration_exact_gaussian_crps = mean(app_glofas_normal_crps(
      design$y[pred$score_local], pred$pred_mean, pred$pred_sd)),
    calibration_mae = mean(abs(pred$pred_mean - design$y[pred$score_local])),
    calibration_rmse = sqrt(mean((pred$pred_mean - design$y[pred$score_local])^2)),
    calibration_oracle_quantile_mae = mean(abs(oracle)),
    design_seconds = design_seconds,
    fit_seconds = fit_seconds,
    forecast_seconds = forecast_seconds,
    runtime_seconds = proc.time()[[3L]] - total_started,
    peak_rss_kib = app_joint_sw_vm_hwm_kib(),
    stringsAsFactors = FALSE
  ))
  detail <- data.frame(
    full_time_index = pred$full_time_index,
    origin_index = pred$origin_index,
    horizon = pred$horizon,
    y = design$y[pred$score_local],
    pred_mean = pred$pred_mean,
    pred_sd = pred$pred_sd,
    realized_acrps = score,
    stringsAsFactors = FALSE
  )
  list(summary = summary, detail = detail, fit = fit, design = design)
}

app_joint_sw_score_rhs <- function(fixture, candidate, contract, origin_indices) {
  total_started <- proc.time()[[3L]]
  design <- app_joint_pure_build_design(fixture, candidate, contract, selector = TRUE)
  tr <- design$train_local
  if (ncol(design$X) - 1L > contract$ordinary_promotion_dimension) {
    stop("RHS candidate exceeds the frozen ordinary-promotion dimension.", call. = FALSE)
  }
  ridge_backend <- if (ncol(design$X) >= length(tr)) "dual" else "primal"
  ridge <- app_joint_ridge_fit_dispatch(
    design$X[tr, , drop = FALSE], design$y[tr],
    ridge_tau2 = contract$ridge_tau2,
    intercept_var = contract$intercept_variance,
    sigma_a = contract$sigma_shape,
    sigma_b = contract$sigma_rate,
    backend = ridge_backend
  )
  warm <- app_joint_shared_ridge_warm_start(ridge, candidate, design)
  fit_started <- proc.time()[[3L]]
  fit <- app_glofas_normal_rhs_fit(
    design$X[tr, , drop = FALSE], design$y[tr], warm,
    tau0 = as.numeric(candidate$rhs_tau0[[1L]]),
    max_iter = contract$rhs_max_iter,
    min_iter = contract$rhs_min_iter,
    tol = contract$rhs_tolerance
  )
  fit_seconds <- proc.time()[[3L]] - fit_started
  forecast_started <- proc.time()[[3L]]
  pred <- app_joint_sw_recursive_gaussian(design, fixture, fit, contract, origin_indices)
  forecast_seconds <- proc.time()[[3L]] - forecast_started
  score <- app_joint_shared_acrps(design$y[pred$score_local], pred$qhat, design$tau)
  oracle <- pred$qhat - design$true_q[pred$score_local, , drop = FALSE]
  summary <- cbind(candidate, data.frame(
    status = "completed",
    method = "normal_rhs_vb",
    ridge_backend = ridge_backend,
    n_analysis = nrow(design$X),
    n_train = length(tr),
    n_calibration_scored = length(pred$score_local),
    origin_indices = paste(origin_indices, collapse = ";"),
    protected_rows_loaded = design$diagnostic$protected_rows_loaded,
    n_features = ncol(design$X),
    effective_rank = design$diagnostic$effective_rank,
    condition_number = design$diagnostic$condition_number,
    state_saturation_fraction = design$diagnostic$state_saturation_fraction,
    calibration_acrps_mean = mean(score),
    calibration_acrps_sd = stats::sd(score),
    calibration_exact_gaussian_crps = mean(app_glofas_normal_crps(
      design$y[pred$score_local], pred$pred_mean, pred$pred_sd)),
    calibration_mae = mean(abs(pred$pred_mean - design$y[pred$score_local])),
    calibration_rmse = sqrt(mean((pred$pred_mean - design$y[pred$score_local])^2)),
    calibration_oracle_quantile_mae = mean(abs(oracle)),
    converged = isTRUE(fit$converged),
    convergence_status = if (isTRUE(fit$converged)) "pass" else "review_max_iter",
    iterations = as.integer(fit$iterations),
    final_delta = as.numeric(fit$final_delta),
    fit_seconds = fit_seconds,
    forecast_seconds = forecast_seconds,
    runtime_seconds = proc.time()[[3L]] - total_started,
    peak_rss_kib = app_joint_sw_vm_hwm_kib(),
    stringsAsFactors = FALSE
  ))
  detail <- data.frame(
    full_time_index = pred$full_time_index,
    origin_index = pred$origin_index,
    horizon = pred$horizon,
    y = design$y[pred$score_local],
    pred_mean = pred$pred_mean,
    pred_sd = pred$pred_sd,
    realized_acrps = score,
    stringsAsFactors = FALSE
  )
  list(summary = summary, detail = detail, trace = fit$trace)
}

app_joint_sw_stage_spec <- function(stage) {
  switch(as.character(stage),
    benchmark = c(plan = "benchmark_worker_plan.csv", id = "benchmark_worker_id"),
    r1a = c(plan = "r1a_worker_plan.csv", id = "r1a_worker_id"),
    r1b = c(plan = "r1b_worker_plan.csv", id = "r1b_worker_id"),
    r2 = c(plan = "r2_worker_plan.csv", id = "r2_worker_id"),
    r3 = c(plan = "r3_worker_plan.csv", id = "r3_worker_id"),
    h1 = c(plan = "h1_worker_plan.csv", id = "h1_worker_id"),
    h2 = c(plan = "h2_worker_plan.csv", id = "h2_worker_id"),
    h3 = c(plan = "h3_worker_plan.csv", id = "h3_worker_id"),
    stop("Unknown stronger-window stage.", call. = FALSE)
  )
}

app_joint_sw_worker_dir <- function(root, stage, id) {
  file.path(root, paste0(stage, "_workers"), sprintf("worker_%05d", as.integer(id)))
}

app_joint_sw_prepare <- function(root = app_joint_sw_default_root()) {
  contract <- app_joint_sw_read_contract()
  axes <- app_joint_sw_read_axes()
  registry <- app_joint_sw_read_registry()
  derived <- app_joint_sw_derived_dgp_registry(contract, registry)
  identity <- app_joint_sw_fixture_identity_audit(contract, registry)
  root <- normalizePath(root, mustWork = FALSE)
  if (dir.exists(root) && length(list.files(root, all.files = TRUE, no.. = TRUE))) {
    stop("Refusing to overwrite a nonempty stronger-window campaign root.", call. = FALSE)
  }
  app_ensure_dir(root)
  app_ensure_dir(file.path(root, "fixtures"))
  app_ensure_dir(file.path(root, "benchmark_workers"))
  app_ensure_dir(file.path(root, "r1a_workers"))

  candidate_rows <- fixture_rows <- list()
  for (ii in seq_len(nrow(registry))) {
    rr <- registry[ii, , drop = FALSE]
    scenario <- rr$scenario_id[[1L]]
    candidate_rows[[ii]] <- app_joint_sw_candidate_registry(scenario, contract, axes, registry)
    sc <- derived[derived$scenario_id == scenario, , drop = FALSE]
    for (replicate_id in seq_len(contract$calibration_replicates)) {
      sc_rep <- sc
      sc_rep$seed <- as.integer(rr$selector_seed_base[[1L]]) + replicate_id - 1L
      sc_rep$seed_role <- sprintf("stronger_window_selector_rep%02d", replicate_id)
      fixture <- app_joint_qdesn_fixture_from_registry_row(sc_rep)
      fixture$registry_row <- sc_rep
      selector <- app_joint_pure_selector_fixture(fixture, contract)
      path <- file.path(root, "fixtures", sprintf("%02d_%s_rep%02d.rds", ii, scenario, replicate_id))
      saveRDS(selector, path, version = 3L, compress = "xz")
      fixture_rows[[length(fixture_rows) + 1L]] <- data.frame(
        scenario_id = scenario,
        replicate_id = replicate_id,
        dgp_seed = sc_rep$seed[[1L]],
        seed_role = sc_rep$seed_role[[1L]],
        fixture_path = normalizePath(path, mustWork = TRUE),
        size_bytes = file.info(path)$size,
        sha256 = app_sha256_file(path),
        protected_rows_persisted = selector$protected_rows_persisted,
        stringsAsFactors = FALSE
      )
    }
  }
  candidates <- app_bind_rows_fill(candidate_rows)
  fixtures <- app_bind_rows_fill(fixture_rows)
  rep1 <- fixtures[fixtures$replicate_id == 1L, c("scenario_id", "replicate_id", "dgp_seed", "fixture_path")]
  r1a <- merge(candidates, rep1, by = "scenario_id", all.x = TRUE, sort = FALSE)
  r1a <- r1a[order(match(r1a$scenario_id, registry$scenario_id), r1a$candidate_id), , drop = FALSE]
  r1a$r1a_worker_id <- seq_len(nrow(r1a))
  r1a$origin_indices <- paste(contract$r1a_origins, collapse = ";")

  benchmark_dims <- c(24L, 300L, 600L, 1200L, 1500L, 2000L)
  benchmark_base <- candidates[candidates$scenario_id == "normal_bridge", , drop = FALSE]
  benchmark <- app_bind_rows_fill(lapply(benchmark_dims, function(p) {
    rows <- benchmark_base[benchmark_base$retained_state_budget == p, , drop = FALSE]
    if (!nrow(rows)) stop(sprintf("No benchmark candidate exists at dimension %d.", p), call. = FALSE)
    rows[order(rows$structural_signature), , drop = FALSE][1L, , drop = FALSE]
  }))
  benchmark <- merge(benchmark, rep1[rep1$scenario_id == "normal_bridge", ], by = "scenario_id", all.x = TRUE)
  benchmark$benchmark_worker_id <- seq_len(nrow(benchmark))
  benchmark$origin_indices <- paste(contract$r1a_origins, collapse = ";")

  files <- c(
    frozen_contract = app_write_csv(contract$table, file.path(root, "frozen_contract.csv")),
    frozen_axes = app_write_csv(axes$table, file.path(root, "frozen_axes.csv")),
    frozen_registry = app_write_csv(registry, file.path(root, "frozen_registry.csv")),
    derived_dgp_registry = app_write_csv(derived, file.path(root, "derived_dgp_registry.csv")),
    protected_identity_audit = app_write_csv(identity, file.path(root, "protected_identity_audit.csv")),
    candidate_registry = app_write_csv(candidates, file.path(root, "candidate_registry.csv")),
    fixture_manifest = app_write_csv(fixtures, file.path(root, "fixture_manifest.csv")),
    benchmark_plan = app_write_csv(benchmark, file.path(root, "benchmark_worker_plan.csv")),
    r1a_plan = app_write_csv(r1a, file.path(root, "r1a_worker_plan.csv")),
    source_git_state = app_write_csv(app_joint_shared_git_state(), file.path(root, "source_git_state.csv"))
  )
  expected <- data.frame(
    scenarios = nrow(registry),
    candidates_per_scenario = contract$candidate_count,
    candidates_total = nrow(candidates),
    selector_fixtures = nrow(fixtures),
    benchmark_workers = nrow(benchmark),
    r1a_workers = nrow(r1a),
    protected_rows_used_for_selection = 0L,
    stringsAsFactors = FALSE
  )
  files <- c(files, expected_work = app_write_csv(expected, file.path(root, "expected_work.csv")))
  readiness <- data.frame(
    status = "READY_FOR_BENCHMARK_ONLY",
    protected_identity_verified = all(identity$verified),
    expected_benchmark_workers = nrow(benchmark),
    broad_screen_authorized = FALSE,
    downstream_auto_launch = FALSE,
    stringsAsFactors = FALSE
  )
  files <- c(files, launch_readiness = app_write_csv(readiness, file.path(root, "launch_readiness.csv")))
  app_joint_shared_write_manifest(root, files, filename = "preparation_manifest.csv")
  verification <- app_joint_shared_verify_manifest(root, file.path(root, "preparation_manifest.csv"))
  if (!all(verification$verified) || nrow(candidates) != contract$candidate_count * contract$scenario_count ||
      nrow(r1a) != contract$candidate_count * contract$scenario_count ||
      any(fixtures$protected_rows_persisted != 0L)) {
    stop("Stronger-window preparation verification failed.", call. = FALSE)
  }
  app_write_csv(verification, file.path(root, "preparation_manifest_verification.csv"))
  list(root = root, expected = expected, readiness = readiness)
}

app_joint_sw_run_worker <- function(root, stage, worker_id) {
  root <- normalizePath(root, mustWork = TRUE)
  spec <- app_joint_sw_stage_spec(stage)
  plan <- app_read_csv(file.path(root, spec[["plan"]]))
  row <- plan[plan[[spec[["id"]]]] == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("Stronger-window worker ID is not unique.", call. = FALSE)
  out <- app_joint_sw_worker_dir(root, stage, worker_id)
  app_ensure_dir(out)
  if (file.exists(file.path(out, "DONE")) && file.exists(file.path(out, "artifact_manifest.csv"))) {
    return(invisible(out))
  }
  contract <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  fixture <- readRDS(row$fixture_path[[1L]])
  origin_indices <- as.integer(strsplit(as.character(row$origin_indices[[1L]]), ";", fixed = TRUE)[[1L]])
  started <- Sys.time()
  score_fun <- if (stage %in% c("h1", "h2", "h3")) app_joint_sw_score_rhs else app_joint_sw_score_ridge
  result <- tryCatch(score_fun(fixture, row, contract, origin_indices), error = function(e) e)
  if (inherits(result, "error")) {
    failure <- cbind(row, data.frame(status = "failed", error_message = conditionMessage(result),
      runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")), stringsAsFactors = FALSE))
    app_write_csv(failure, file.path(out, "failure.csv"))
    writeLines("failed", file.path(out, "FAILED"))
    return(invisible(out))
  }
  files <- c(
    summary = app_write_csv(result$summary, file.path(out, "summary.csv")),
    detail = app_write_csv(result$detail, file.path(out, "calibration_detail.csv"))
  )
  if (!is.null(result$trace) && nrow(result$trace)) {
    files <- c(files, vb_trace = app_write_csv(result$trace, file.path(out, "vb_trace.csv")))
  }
  app_joint_shared_write_manifest(out, files)
  check <- app_joint_shared_verify_manifest(out, file.path(out, "artifact_manifest.csv"))
  if (!all(check$verified)) stop("Worker artifact verification failed.", call. = FALSE)
  writeLines("completed", file.path(out, "DONE"))
  invisible(out)
}

app_joint_sw_run_ridge_worker <- app_joint_sw_run_worker

app_joint_sw_health <- function(root, stage) {
  root <- normalizePath(root, mustWork = TRUE)
  spec <- app_joint_sw_stage_spec(stage)
  plan_path <- file.path(root, spec[["plan"]])
  if (!file.exists(plan_path)) return(data.frame(stage = stage, expected = 0L, completed = 0L,
    failed = 0L, remaining = 0L, status = "not_prepared", stringsAsFactors = FALSE))
  plan <- app_read_csv(plan_path)
  ids <- plan[[spec[["id"]]]]
  dirs <- vapply(ids, function(id) app_joint_sw_worker_dir(root, stage, id), character(1L))
  complete <- file.exists(file.path(dirs, "DONE")) & file.exists(file.path(dirs, "artifact_manifest.csv"))
  failed <- file.exists(file.path(dirs, "FAILED")) | file.exists(file.path(dirs, "failure.csv"))
  data.frame(
    stage = stage,
    expected = length(ids),
    completed = sum(complete),
    failed = sum(failed),
    remaining = sum(!complete & !failed),
    completion_fraction = mean(complete),
    status = if (any(failed)) "failed" else if (all(complete)) "complete" else if (any(complete)) "running" else "ready",
    stringsAsFactors = FALSE
  )
}

app_joint_sw_collect_stage <- function(root, stage) {
  health <- app_joint_sw_health(root, stage)
  if (health$failed[[1L]] != 0L || health$completed[[1L]] != health$expected[[1L]]) {
    stop(sprintf("Stronger-window stage '%s' is not complete and failure-free.", stage), call. = FALSE)
  }
  files <- list.files(file.path(root, paste0(stage, "_workers")), pattern = "^summary[.]csv$",
    recursive = TRUE, full.names = TRUE)
  scores <- app_bind_rows_fill(lapply(files, app_read_csv))
  if (nrow(scores) != health$expected[[1L]] || any(scores$status != "completed") ||
      any(!is.finite(scores$calibration_acrps_mean))) {
    stop("Collected stronger-window scores violate completion gates.", call. = FALSE)
  }
  scores
}

app_joint_sw_finalize_benchmark <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  scores <- app_joint_sw_collect_stage(root, "benchmark")
  scores <- scores[order(scores$retained_state_budget), , drop = FALSE]
  required <- c(24L, 300L, 600L, 1200L, 1500L, 2000L)
  pass <- identical(as.integer(scores$retained_state_budget), required) &&
    all(is.finite(scores$runtime_seconds)) && all(is.finite(scores$peak_rss_kib)) &&
    all(scores$protected_rows_loaded == 0L) &&
    all(scores$covariance_representation[scores$retained_state_budget >= 1200L] == "dual_woodbury_exact") &&
    !any(app_as_bool_vec(scores$materialized_parameter_covariance[scores$retained_state_budget >= 1200L]))
  out <- c(
    benchmark_scores = app_write_csv(scores, file.path(root, "benchmark_scores.csv")),
    benchmark_health = app_write_csv(app_joint_sw_health(root, "benchmark"), file.path(root, "benchmark_health.csv"))
  )
  capacity_receipt <- file.path(root, "benchmark_capacity_receipt.csv")
  if (file.exists(capacity_receipt)) out <- c(out, capacity_receipt = capacity_receipt)
  r1a <- app_read_csv(file.path(root, "r1a_worker_plan.csv"))
  nearest <- vapply(r1a$retained_state_budget, function(z) {
    which.min(abs(log(z) - log(scores$retained_state_budget)))
  }, integer(1L))
  projected_cpu_seconds <- sum(scores$runtime_seconds[nearest])
  rss_per_worker_gib <- max(scores$peak_rss_kib) / 1024^2
  memory_worker_cap <- floor((contract$min_available_memory_gib -
    contract$host_reserve_memory_gib) / rss_per_worker_gib)
  recommended_workers <- max(1L, min(contract$max_workers, memory_worker_cap))
  capacity_class <- cut(r1a$retained_state_budget, c(-Inf, 600, 1200, Inf),
    labels = c("ordinary_le600", "conditional_601_1200", "sentinel_1500_2000"))
  class_count <- as.data.frame(table(capacity_class), stringsAsFactors = FALSE)
  names(class_count) <- c("capacity_class", "worker_count")
  projection <- data.frame(
    r1a_workers = nrow(r1a),
    projected_cpu_hours = projected_cpu_seconds / 3600,
    recommended_physical_workers = recommended_workers,
    projected_wall_hours = projected_cpu_seconds / 3600 / recommended_workers,
    conservative_wall_hours = 1.5 * projected_cpu_seconds / 3600 / recommended_workers,
    max_observed_worker_rss_gib = rss_per_worker_gib,
    projected_peak_rss_gib = rss_per_worker_gib * recommended_workers,
    memory_worker_cap = memory_worker_cap,
    stringsAsFactors = FALSE
  )
  out <- c(out,
    r1a_capacity_classes = app_write_csv(class_count, file.path(root, "r1a_capacity_class_counts.csv")),
    r1a_resource_projection = app_write_csv(projection, file.path(root, "r1a_resource_projection.csv")),
    analysis_git_state = app_write_csv(app_joint_shared_git_state(),
      file.path(root, "benchmark_analysis_git_state.csv")))
  decision <- data.frame(
    status = if (pass) "BENCHMARK_COMPLETE_READY_FOR_R1A_REVIEW" else "BENCHMARK_FAILED_BLOCK_R1A",
    benchmark_pass = pass,
    recommended_physical_workers = recommended_workers,
    conservative_r1a_wall_hours = projection$conservative_wall_hours,
    broad_screen_launched = FALSE,
    downstream_auto_launch = FALSE,
    stringsAsFactors = FALSE
  )
  out <- c(out, benchmark_decision = app_write_csv(decision, file.path(root, "benchmark_decision.csv")))
  app_joint_shared_write_manifest(root, out, filename = "benchmark_manifest.csv")
  if (!pass) stop("Stronger-window benchmark gate failed.", call. = FALSE)
  decision
}

app_joint_sw_aggregate_scores <- function(scores, keys) {
  app_check_required_columns(scores, c(keys, "calibration_acrps_mean", "status"),
    "stronger-window stage scores")
  group <- interaction(scores[, keys, drop = FALSE], drop = TRUE, lex.order = TRUE)
  out <- app_bind_rows_fill(lapply(split(scores, group), function(x) {
    row <- x[1L, keys, drop = FALSE]
    score <- as.numeric(x$calibration_acrps_mean)
    convergence <- if ("converged" %in% names(x)) mean(app_as_bool_vec(x$converged)) else NA_real_
    cbind(row, data.frame(
      evaluation_count = nrow(x),
      finite_fraction = mean(is.finite(score)),
      calibration_acrps_mean = mean(score),
      calibration_acrps_worst = max(score),
      calibration_acrps_sd = if (length(score) > 1L) stats::sd(score) else 0,
      convergence_fraction = convergence,
      runtime_seconds_total = sum(as.numeric(x$runtime_seconds), na.rm = TRUE),
      peak_rss_kib_max = max(as.numeric(x$peak_rss_kib), na.rm = TRUE),
      stringsAsFactors = FALSE
    ))
  }))
  out[do.call(order, out[keys]), , drop = FALSE]
}

app_joint_sw_attach_candidate_metadata <- function(root, aggregate) {
  registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
  by <- c("scenario_id", "candidate_id")
  if ("rhs_tau0" %in% names(aggregate)) {
    plan_paths <- file.path(root, c("h1_worker_plan.csv", "h2_worker_plan.csv", "h3_worker_plan.csv"))
    plan_paths <- plan_paths[file.exists(plan_paths)]
    if (!length(plan_paths)) stop("RHS aggregate has no source worker plan.", call. = FALSE)
    pairs <- unique(app_bind_rows_fill(lapply(plan_paths, app_read_csv))[, c(by, "rhs_tau0"), drop = FALSE])
    registry <- merge(registry, pairs, by = by, all.y = TRUE, sort = FALSE)
    by <- c(by, "rhs_tau0")
  }
  out <- merge(registry, aggregate, by = by, all.y = TRUE, sort = FALSE)
  if (nrow(out) != nrow(aggregate) || anyNA(out$candidate_role)) {
    stop("Candidate metadata could not be attached one-to-one.", call. = FALSE)
  }
  out
}

app_joint_sw_diversity_key <- function(x) {
  lag_band <- cut(x$response_lags, c(-Inf, 5, 15, 45, 120, 240, Inf),
    labels = c("lag_very_short", "lag_short", "lag_medium", "lag_long", "lag_very_long", "lag_extreme"))
  budget_band <- cut(x$retained_state_budget, c(-Inf, 48, 150, 450, 800, 1200, Inf),
    labels = c("tiny", "small", "medium", "large", "conditional", "sentinel"))
  paste(x$D, x$width_shape, lag_band, budget_band, x$recurrent_sparsity_mode, sep = "|")
}

app_joint_sw_frontier <- function(x, n, high_quota, diversity_quota) {
  x <- x[is.finite(x$calibration_acrps_mean) & x$finite_fraction == 1, , drop = FALSE]
  x <- x[order(x$calibration_acrps_mean, x$calibration_acrps_worst,
    x$calibration_acrps_sd, x$retained_state_budget, x$candidate_id), , drop = FALSE]
  if (nrow(x) < n) stop("Too few finite candidates for the frozen frontier size.", call. = FALSE)
  selected <- character()
  append_ids <- function(ids, limit = length(ids)) {
    ids <- ids[!ids %in% selected]
    selected <<- c(selected, head(ids, limit))
  }
  append_ids(x$candidate_id[grepl("^anchor_", x$candidate_role)])
  append_ids(x$candidate_id[x$retained_state_budget >= 1500L], high_quota)
  remainder <- x[!x$candidate_id %in% selected, , drop = FALSE]
  remainder$diversity_key <- app_joint_sw_diversity_key(remainder)
  diverse <- app_bind_rows_fill(lapply(split(remainder, remainder$diversity_key), function(z) z[1L, , drop = FALSE]))
  if (nrow(diverse)) {
    diverse <- diverse[order(diverse$calibration_acrps_mean, diverse$candidate_id), , drop = FALSE]
    append_ids(diverse$candidate_id, diversity_quota)
  }
  append_ids(x$candidate_id, n - length(selected))
  if (length(selected) != n || anyDuplicated(selected)) {
    stop("Frozen ridge frontier allocation failed.", call. = FALSE)
  }
  out <- x[match(selected, x$candidate_id), , drop = FALSE]
  out$advancement_rank <- seq_len(nrow(out))
  out
}

app_joint_sw_registry_subset <- function(root, selected) {
  registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
  key <- paste(registry$scenario_id, registry$candidate_id, sep = "::")
  wanted <- paste(selected$scenario_id, selected$candidate_id, sep = "::")
  out <- registry[match(wanted, key), , drop = FALSE]
  if (anyNA(out$candidate_id)) stop("Selected candidates are absent from the frozen registry.", call. = FALSE)
  out$advancement_rank <- selected$advancement_rank
  out
}

app_joint_sw_make_ridge_plan <- function(root, selected, stage, origin_indices, all_replicates, seed_robust = FALSE) {
  candidates <- app_joint_sw_registry_subset(root, selected)
  fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))
  if (!all_replicates) fixtures <- fixtures[fixtures$replicate_id == 1L, , drop = FALSE]
  fixtures <- fixtures[, c("scenario_id", "replicate_id", "dgp_seed", "fixture_path"), drop = FALSE]
  if (seed_robust) {
    contract <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
    registry <- app_joint_sw_read_registry(file.path(root, "frozen_registry.csv"))
    seeds <- app_bind_rows_fill(lapply(seq_len(nrow(registry)), function(ii) {
      base <- as.integer(registry$canonical_reservoir_seed[[ii]])
      data.frame(scenario_id = registry$scenario_id[[ii]],
        reservoir_seed = c(base, base + contract$reservoir_seed_offsets), stringsAsFactors = FALSE)
    }))
    candidates$base_candidate_id <- candidates$candidate_id
    candidates <- merge(candidates[, setdiff(names(candidates), "reservoir_seed"), drop = FALSE],
      seeds, by = "scenario_id", all.x = TRUE, sort = FALSE)
    candidates$execution_signature <- vapply(seq_len(nrow(candidates)), function(ii) {
      app_joint_qvp_sha256_text(paste(candidates$structural_signature[[ii]],
        candidates$reservoir_seed[[ii]], sep = "|"))
    }, character(1L))
  }
  plan <- merge(candidates, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan$origin_indices <- paste(origin_indices, collapse = ";")
  id <- paste0(stage, "_worker_id")
  plan[[id]] <- seq_len(nrow(plan))
  plan <- plan[order(plan[[id]]), , drop = FALSE]
  path <- app_write_csv(plan, file.path(root, paste0(stage, "_worker_plan.csv")))
  app_ensure_dir(file.path(root, paste0(stage, "_workers")))
  path
}

app_joint_sw_finalize_ridge_stage <- function(root, stage) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  spec <- switch(stage,
    r1a = list(next_stage = "r1b", n = contract$r1a_advance_count,
      high = contract$r1a_high_capacity_quota, diverse = contract$r1a_diversity_quota,
      origins = contract$r1b_origins, all_replicates = FALSE, seed_robust = FALSE),
    r1b = list(next_stage = "r2", n = contract$r1b_advance_count,
      high = contract$r1b_high_capacity_quota, diverse = contract$r1b_diversity_quota,
      origins = contract$full_origins, all_replicates = TRUE, seed_robust = FALSE),
    r2 = list(next_stage = "r3", n = contract$r2_advance_count,
      high = contract$r2_high_capacity_quota, diverse = contract$r2_diversity_quota,
      origins = contract$full_origins, all_replicates = TRUE, seed_robust = TRUE),
    stop("Only R1a, R1b, and R2 use the ridge-stage finalizer.", call. = FALSE)
  )
  scores <- app_joint_sw_collect_stage(root, stage)
  aggregate <- app_joint_sw_attach_candidate_metadata(root,
    app_joint_sw_aggregate_scores(scores, c("scenario_id", "candidate_id")))
  frontier <- app_bind_rows_fill(lapply(split(aggregate, aggregate$scenario_id), function(x) {
    app_joint_sw_frontier(x, spec$n, spec$high, spec$diverse)
  }))
  expected <- contract$scenario_count * spec$n
  if (nrow(frontier) != expected) stop("Ridge frontier cardinality gate failed.", call. = FALSE)
  files <- c(
    scores = app_write_csv(scores, file.path(root, paste0(stage, "_scores.csv"))),
    aggregate = app_write_csv(aggregate, file.path(root, paste0(stage, "_aggregate.csv"))),
    frontier = app_write_csv(frontier, file.path(root, paste0(stage, "_frontier.csv"))),
    next_plan = app_joint_sw_make_ridge_plan(root, frontier, spec$next_stage, spec$origins,
      spec$all_replicates, spec$seed_robust)
  )
  decision <- data.frame(stage = stage, status = paste0(toupper(stage), "_COMPLETE_READY_FOR_", toupper(spec$next_stage), "_REVIEW"),
    selected = nrow(frontier), next_stage_launched = FALSE, protected_rows_used = 0L,
    stringsAsFactors = FALSE)
  files <- c(files, decision = app_write_csv(decision, file.path(root, paste0(stage, "_decision.csv"))))
  app_joint_shared_write_manifest(root, files, filename = paste0(stage, "_manifest.csv"))
  decision
}

app_joint_sw_select_parity_pair <- function(x, n, preserve_exact_tau = TRUE) {
  x <- x[order(x$calibration_acrps_mean, x$calibration_acrps_worst,
    x$calibration_acrps_sd, x$rhs_tau0), , drop = FALSE]
  parity <- x[grepl("anchor_authoritative_v2", x$candidate_role), , drop = FALSE]
  exact <- parity[0, , drop = FALSE]
  if (preserve_exact_tau && nrow(parity) && is.finite(parity$source_rhs_tau0[[1L]])) {
    exact <- parity[which.min(abs(log(parity$rhs_tau0) - log(parity$source_rhs_tau0))), , drop = FALSE]
  }
  out <- app_bind_rows_fill(list(exact, x[!paste(x$candidate_id, x$rhs_tau0) %in%
    paste(exact$candidate_id, exact$rhs_tau0), , drop = FALSE]))
  head(out, n)
}

app_joint_sw_finalize_r3 <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  scores <- app_joint_sw_collect_stage(root, "r3")
  aggregate <- app_joint_sw_attach_candidate_metadata(root,
    app_joint_sw_aggregate_scores(scores, c("scenario_id", "candidate_id")))
  aggregate$backend_status <- ifelse(aggregate$retained_state_budget <= contract$ordinary_promotion_dimension,
    "rhs_supported_ordinary", "ridge_only_capacity_evidence")
  blocked <- aggregate[aggregate$backend_status != "rhs_supported_ordinary", , drop = FALSE]
  supported <- aggregate[aggregate$backend_status == "rhs_supported_ordinary", , drop = FALSE]
  frontier <- app_bind_rows_fill(lapply(split(supported, supported$scenario_id), function(x) {
    app_joint_sw_frontier(x, contract$r3_advance_count, 0L,
      min(contract$r3_advance_count, contract$r2_diversity_quota))
  }))
  candidates <- app_joint_sw_registry_subset(root, frontier)
  candidates$backend_status <- "rhs_supported_ordinary"
  candidates <- merge(candidates, data.frame(rhs_tau0 = contract$rhs_tau0_grid), by = NULL)
  fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))
  fixtures <- fixtures[fixtures$replicate_id == 1L,
    c("scenario_id", "replicate_id", "dgp_seed", "fixture_path"), drop = FALSE]
  plan <- merge(candidates, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan$origin_indices <- paste(contract$full_origins, collapse = ";")
  plan$h1_worker_id <- seq_len(nrow(plan))
  files <- c(
    scores = app_write_csv(scores, file.path(root, "r3_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "r3_seed_robustness_aggregate.csv")),
    blocked = app_write_csv(blocked, file.path(root, "r3_capacity_bound_evidence.csv")),
    frontier = app_write_csv(frontier, file.path(root, "r3_rhs_frontier.csv")),
    h1_plan = app_write_csv(plan, file.path(root, "h1_worker_plan.csv"))
  )
  app_ensure_dir(file.path(root, "h1_workers"))
  decision <- data.frame(status = "R3_COMPLETE_READY_FOR_H1_REVIEW", selected = nrow(frontier),
    capacity_bound = nrow(blocked), h1_workers = nrow(plan), h1_launched = FALSE,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  files <- c(files, decision = app_write_csv(decision, file.path(root, "r3_decision.csv")))
  app_joint_shared_write_manifest(root, files, filename = "r3_manifest.csv")
  decision
}

app_joint_sw_finalize_h1 <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  scores <- app_joint_sw_collect_stage(root, "h1")
  aggregate <- app_joint_sw_attach_candidate_metadata(root,
    app_joint_sw_aggregate_scores(scores, c("scenario_id", "candidate_id", "rhs_tau0")))
  retained <- app_bind_rows_fill(lapply(split(aggregate,
    paste(aggregate$scenario_id, aggregate$candidate_id, sep = "::")), function(x) {
      app_joint_sw_select_parity_pair(x, contract$h2_tau_per_architecture)
    }))
  fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))[, c("scenario_id", "replicate_id",
    "dgp_seed", "fixture_path"), drop = FALSE]
  unique_candidates <- retained[!duplicated(paste(retained$scenario_id, retained$candidate_id)), , drop = FALSE]
  candidates <- merge(app_joint_sw_registry_subset(root, unique_candidates),
    unique(retained[, c("scenario_id", "candidate_id", "rhs_tau0"), drop = FALSE]),
    by = c("scenario_id", "candidate_id"), all.y = TRUE, sort = FALSE)
  plan <- merge(candidates, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan$origin_indices <- paste(contract$full_origins, collapse = ";")
  plan$h2_worker_id <- seq_len(nrow(plan))
  files <- c(
    scores = app_write_csv(scores, file.path(root, "h1_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "h1_aggregate.csv")),
    retained = app_write_csv(retained, file.path(root, "h1_retained_tau_pairs.csv")),
    h2_plan = app_write_csv(plan, file.path(root, "h2_worker_plan.csv"))
  )
  app_ensure_dir(file.path(root, "h2_workers"))
  app_joint_shared_write_manifest(root, files, filename = "h1_manifest.csv")
  data.frame(status = "H1_COMPLETE_READY_FOR_H2_REVIEW", h2_workers = nrow(plan), stringsAsFactors = FALSE)
}

app_joint_sw_finalize_h2 <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  scores <- app_joint_sw_collect_stage(root, "h2")
  aggregate <- app_joint_sw_attach_candidate_metadata(root,
    app_joint_sw_aggregate_scores(scores, c("scenario_id", "candidate_id", "rhs_tau0")))
  best_per_arch <- app_bind_rows_fill(lapply(split(aggregate,
    paste(aggregate$scenario_id, aggregate$candidate_id, sep = "::")), function(x) {
      app_joint_sw_select_parity_pair(x, 1L)
    }))
  shortlist <- app_bind_rows_fill(lapply(split(best_per_arch, best_per_arch$scenario_id), function(x) {
    app_joint_sw_select_parity_pair(x, contract$h3_neighborhood_count)
  }))
  neighbors <- app_bind_rows_fill(lapply(seq_len(nrow(shortlist)), function(ii) {
    row <- shortlist[ii, , drop = FALSE]
    values <- unique(pmin(contract$refinement_max_tau0, pmax(contract$refinement_min_tau0,
      c(row$rhs_tau0 / contract$refinement_factor, row$rhs_tau0 * contract$refinement_factor))))
    values <- values[!vapply(values, function(z) any(abs(log(z) - log(contract$rhs_tau0_grid)) < 1e-12), logical(1L))]
    if (!length(values)) return(NULL)
    data.frame(scenario_id = row$scenario_id, candidate_id = row$candidate_id,
      rhs_tau0 = values, stringsAsFactors = FALSE)
  }))
  fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))[, c("scenario_id", "replicate_id",
    "dgp_seed", "fixture_path"), drop = FALSE]
  unique_candidates <- neighbors[!duplicated(paste(neighbors$scenario_id, neighbors$candidate_id)), , drop = FALSE]
  candidates <- merge(app_joint_sw_registry_subset(root, unique_candidates), neighbors,
    by = c("scenario_id", "candidate_id"), all.y = TRUE, sort = FALSE)
  plan <- merge(candidates, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan$origin_indices <- paste(contract$full_origins, collapse = ";")
  plan$h3_worker_id <- seq_len(nrow(plan))
  files <- c(
    scores = app_write_csv(scores, file.path(root, "h2_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "h2_aggregate.csv")),
    shortlist = app_write_csv(shortlist, file.path(root, "h2_refinement_shortlist.csv")),
    h3_plan = app_write_csv(plan, file.path(root, "h3_worker_plan.csv"))
  )
  app_ensure_dir(file.path(root, "h3_workers"))
  app_joint_shared_write_manifest(root, files, filename = "h2_manifest.csv")
  data.frame(status = "H2_COMPLETE_READY_FOR_H3_REVIEW", h3_workers = nrow(plan), stringsAsFactors = FALSE)
}

app_joint_sw_finalize_h3 <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  h2 <- app_read_csv(file.path(root, "h2_scores.csv"))
  h3 <- app_joint_sw_collect_stage(root, "h3")
  scores <- app_bind_rows_fill(list(h2, h3))
  aggregate <- app_joint_sw_attach_candidate_metadata(root,
    app_joint_sw_aggregate_scores(scores, c("scenario_id", "candidate_id", "rhs_tau0")))
  selected <- app_bind_rows_fill(lapply(split(aggregate, aggregate$scenario_id), function(x) {
    x <- x[order(x$calibration_acrps_mean, x$calibration_acrps_worst,
      x$calibration_acrps_sd, x$retained_state_budget, x$candidate_id), , drop = FALSE]
    app_joint_sw_select_parity_pair(x, contract$median_advance_count)
  }))
  selected$rhs_selection_rank <- ave(selected$calibration_acrps_mean, selected$scenario_id,
    FUN = function(z) rank(z, ties.method = "first"))
  fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))[, c("scenario_id", "replicate_id",
    "dgp_seed", "fixture_path"), drop = FALSE]
  unique_candidates <- selected[!duplicated(paste(selected$scenario_id, selected$candidate_id)), , drop = FALSE]
  candidates <- merge(app_joint_sw_registry_subset(root, unique_candidates),
    selected[, c("scenario_id", "candidate_id", "rhs_tau0", "rhs_selection_rank"), drop = FALSE],
    by = c("scenario_id", "candidate_id"), all.y = TRUE, sort = FALSE)
  median_plan <- merge(candidates, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
  median_plan$median_tau <- 0.5
  median_plan$origin_indices <- paste(contract$full_origins, collapse = ";")
  median_plan$median_worker_id <- seq_len(nrow(median_plan))
  files <- c(
    scores = app_write_csv(scores, file.path(root, "rhs_all_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "rhs_all_aggregate.csv")),
    selected = app_write_csv(selected, file.path(root, "rhs_selected_top20_by_scenario.csv")),
    median_plan = app_write_csv(median_plan, file.path(root, "median_al_worker_plan.csv"))
  )
  readiness <- data.frame(status = "NORMAL_RHS_FUNNEL_COMPLETE_READY_FOR_MEDIAN_AL_IMPLEMENTATION_REVIEW",
    selected_pairs = nrow(selected), median_workers = nrow(median_plan), median_launched = FALSE,
    seven_grid_launched = FALSE, protected_rows_used = 0L, stringsAsFactors = FALSE)
  files <- c(files, readiness = app_write_csv(readiness, file.path(root, "quantile_vb_readiness.csv")))
  app_joint_shared_write_manifest(root, files, filename = "h3_manifest.csv")
  readiness
}

app_joint_sw_finalize_stage <- function(root, stage) {
  switch(as.character(stage),
    benchmark = app_joint_sw_finalize_benchmark(root),
    r1a = app_joint_sw_finalize_ridge_stage(root, "r1a"),
    r1b = app_joint_sw_finalize_ridge_stage(root, "r1b"),
    r2 = app_joint_sw_finalize_ridge_stage(root, "r2"),
    r3 = app_joint_sw_finalize_r3(root),
    h1 = app_joint_sw_finalize_h1(root),
    h2 = app_joint_sw_finalize_h2(root),
    h3 = app_joint_sw_finalize_h3(root),
    stop("Unknown stronger-window finalization stage.", call. = FALSE)
  )
}
