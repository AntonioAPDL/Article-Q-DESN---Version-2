# Fit-first persistent-heavy-tail V4 super-screen.

app_joint_pht4_contract_path <- function() {
  app_path("application/config/joint_qdesn_persistent_tail_fitfirst_v4_contract.csv")
}

app_joint_pht4_axes_path <- function() {
  app_path("application/config/joint_qdesn_persistent_tail_fitfirst_v4_axes.csv")
}

app_joint_pht4_exclusion_path <- function() {
  app_path("application/config/joint_qdesn_persistent_tail_fitfirst_v4_exclusions.csv")
}

app_joint_pht4_controls_path <- function() {
  app_path("application/config/joint_qdesn_persistent_tail_fitfirst_v4_controls.csv")
}

app_joint_pht4_default_root <- function() {
  app_path("application/cache/joint_qdesn_persistent_tail_fitfirst_v4_20261125")
}

app_joint_pht4_value <- function(tab, name) {
  row <- tab[tab$name == name, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("V4 contract requires one '%s'.", name), call. = FALSE)
  as.character(row$value[[1L]])
}

app_joint_pht4_read_contract <- function(path = app_joint_pht4_contract_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("section", "name", "value", "type", "description"),
    "persistent-tail V4 contract")
  if (anyDuplicated(tab$name)) stop("V4 contract fields must be unique.", call. = FALSE)
  value <- function(name) app_joint_pht4_value(tab, name)
  numvec <- function(name) as.numeric(strsplit(value(name), ";", fixed = TRUE)[[1L]])
  intvec <- function(name) as.integer(numvec(name))
  bool <- function(name) identical(tolower(value(name)), "true")
  ints <- c("candidate_count", "control_count", "local_count", "layered_count",
    "long_memory_count", "supercritical_count", "high_capacity_count", "global_count",
    "r1_advance_count", "r2_advance_count", "r3_advance_count", "h1_advance_count",
    "h2_advance_count", "m1_advance_count", "t1_advance_count", "discovery_replicates",
    "tail_replicates", "sealed_replicates", "discovery_seed_offset", "tail_seed_offset",
    "sealed_seed_offset", "rhs_max_iter", "rhs_min_iter", "al_max_iter",
    "maximum_rhs_dimension", "maximum_joint_dense_dimension", "maximum_ridge_dimension",
    "max_physical_workers", "blas_threads", "nice_level")
  out <- list(table = tab, version = value("contract_version"), run_tag = value("run_tag"),
    parent_branch = value("parent_branch"), parent_head = value("parent_head"),
    scenario_id = value("scenario_id"), required_hostname = value("required_hostname"),
    candidate_signature_sha256 = value("candidate_signature_sha256"))
  for (name in ints) out[[name]] <- as.integer(value(name))
  out$r1_origins <- intvec("r1_origin_indices")
  out$full_origins <- intvec("full_origin_indices")
  out$reservoir_seed_offsets <- intvec("reservoir_seed_offsets")
  out$rhs_tau0_values <- numvec("rhs_tau0_values")
  out$rhs_zeta2_values <- strsplit(value("rhs_zeta2_values"), ";", fixed = TRUE)[[1L]]
  out$al_tau0_multipliers <- numvec("al_tau0_multipliers")
  for (name in c("rhs_tolerance", "al_tolerance", "median_fit_relative_margin",
      "median_fit_absolute_margin", "tail_fit_relative_margin", "tail_fit_absolute_margin",
      "horizon1_relative_margin", "horizon1_absolute_margin",
      "forecast_near_tie_relative_margin", "forecast_near_tie_absolute_margin",
      "max_initial_state_score_relative_change", "initial_state_perturbation_scale",
      "min_data_free_gib", "min_available_memory_gib")) {
    out[[name]] <- as.numeric(value(name))
  }
  out$protected_selection_forbidden <- bool("protected_selection_forbidden")
  out$automatic_downstream_launch <- bool("automatic_downstream_launch")
  out$require_finite_scores <- bool("require_finite_scores")
  allocation <- c(out$control_count, out$local_count, out$layered_count,
    out$long_memory_count, out$supercritical_count, out$high_capacity_count,
    out$global_count)
  valid <- identical(out$version, "joint_qdesn_persistent_tail_fitfirst_v4") &&
    identical(out$scenario_id, "persistent_heavy_tail") &&
    sum(allocation) == out$candidate_count && out$candidate_count == 8192L &&
    identical(out$r1_origins, c(1L, 5L, 10L)) && length(out$full_origins) == 10L &&
    length(out$rhs_tau0_values) == 10L && length(out$rhs_zeta2_values) == 8L &&
    length(out$al_tau0_multipliers) == 8L && out$rhs_max_iter == 500L &&
    out$al_max_iter == 500L && out$rhs_tolerance == 1e-3 && out$al_tolerance == 1e-3 &&
    grepl("^[a-f0-9]{64}$", out$candidate_signature_sha256) &&
    out$protected_selection_forbidden && !out$automatic_downstream_launch
  if (!valid) stop("Persistent-tail V4 contract is malformed.", call. = FALSE)
  out
}

app_joint_pht4_read_axes <- function(path = app_joint_pht4_axes_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("profile", "axis", "values", "role"),
    "persistent-tail V4 axes")
  get <- function(axis, numeric = FALSE) {
    row <- tab[tab$profile == "v4" & tab$axis == axis, , drop = FALSE]
    if (nrow(row) != 1L) stop(sprintf("Missing V4 axis '%s'.", axis), call. = FALSE)
    x <- strsplit(as.character(row$values[[1L]]), ";", fixed = TRUE)[[1L]]
    if (numeric) as.numeric(x) else x
  }
  out <- list(table = tab, depth = as.integer(get("depth", TRUE)),
    promotable_state_budget = as.integer(get("promotable_state_budget", TRUE)),
    diagnostic_state_budget = as.integer(get("diagnostic_state_budget", TRUE)),
    width_shape = get("width_shape"), response_lags = as.integer(get("response_lags", TRUE)),
    alpha_range = get("alpha_range", TRUE), rho_subcritical_range = get("rho_subcritical_range", TRUE),
    rho_supercritical = get("rho_supercritical", TRUE), schedule = get("schedule"),
    input_scale = get("input_scale", TRUE), pi_in = get("pi_in", TRUE),
    pi_w_fixed = get("pi_w_fixed", TRUE),
    recurrent_expected_degree = get("recurrent_expected_degree", TRUE),
    minimum_layer_width = as.integer(get("minimum_generated_layer_width", TRUE)))
  if (max(out$promotable_state_budget) > 84L || max(out$diagnostic_state_budget) > 2000L ||
      max(out$rho_supercritical) > 1.2 || min(out$alpha_range) <= 0 ||
      max(out$alpha_range) >= 1 || max(out$response_lags) != 360L) {
    stop("Persistent-tail V4 axes violate reviewed bounds.", call. = FALSE)
  }
  out
}

app_joint_pht4_base_contract <- function() {
  base <- app_joint_sw_read_contract()
  replacements <- c(rhs_max_iter = "500", rhs_min_iter = "50", rhs_tolerance = "0.001",
    median_max_iter = "500", quantile_max_iter = "500", vb_tolerance = "0.001",
    ordinary_promotion_dimension = "600", conditional_promotion_dimension = "600",
    maximum_ridge_dimension = "2000")
  for (name in names(replacements)) {
    hit <- base$table$name == name
    if (sum(hit) != 1L) stop(sprintf("Base contract lacks '%s'.", name), call. = FALSE)
    base$table$value[hit] <- replacements[[name]]
  }
  base$rhs_max_iter <- 500L
  base$rhs_min_iter <- 50L
  base$rhs_tolerance <- 1e-3
  base$median_max_iter <- 500L
  base$quantile_max_iter <- 500L
  base$vb_tolerance <- 1e-3
  base$ordinary_promotion_dimension <- 600L
  base$conditional_promotion_dimension <- 600L
  base$maximum_ridge_dimension <- 2000L
  base$max_readout_dimension <- 2000L
  base
}

app_joint_pht4_write_base_contract <- function(path) {
  base <- app_joint_sw_read_contract()
  replacements <- c(rhs_max_iter = "500", rhs_min_iter = "50", rhs_tolerance = "0.001",
    median_max_iter = "500", quantile_max_iter = "500", vb_tolerance = "0.001",
    ordinary_promotion_dimension = "600", conditional_promotion_dimension = "600",
    maximum_ridge_dimension = "2000")
  for (name in names(replacements)) base$table$value[base$table$name == name] <- replacements[[name]]
  app_write_csv(base$table, path)
}

app_joint_pht4_registry <- function(contract = app_joint_pht4_read_contract()) {
  x <- app_joint_sw_read_registry()
  x <- x[x$scenario_id == contract$scenario_id, , drop = FALSE]
  if (nrow(x) != 1L) stop("Persistent-heavy-tail registry row is missing.", call. = FALSE)
  x
}

app_joint_pht4_widths <- function(D, budget, shape, minimum = 2L, u = 0.5) {
  if (shape != "heterogeneous") return(app_joint_sw_widths(D, budget, shape, minimum))
  weights <- 0.25 + abs(sin(seq_len(D) * (1 + 5 * u)))
  available <- budget - D * minimum
  out <- rep(minimum, D)
  if (available > 0L) {
    add <- floor(available * weights / sum(weights))
    out <- out + add
    remainder <- budget - sum(out)
    if (remainder > 0L) out[seq_len(remainder)] <- out[seq_len(remainder)] + 1L
  }
  as.integer(out)
}

app_joint_pht4_candidate_from_point <- function(H, role, axes, seed, anchors = NULL) {
  depth_pool <- switch(role,
    local_fit = c(1L, 1L, 2L, 2L, 3L, 4L, 5L, 6L),
    layered_fit = c(2L, 3L, 4L, 5L, 6L, 7L, 8L),
    long_memory = c(1L, 2L, 3L, 4L, 5L, 6L, 8L),
    supercritical = c(1L, 2L, 3L, 4L, 5L, 6L),
    high_capacity_diagnostic = c(1L, 2L, 3L, 4L, 6L, 8L),
    global_unseen = axes$depth,
    stop("Unknown V4 candidate role.", call. = FALSE))
  D <- as.integer(app_joint_sw_pick(depth_pool, H[[1L]]))
  budgets <- if (role == "high_capacity_diagnostic") axes$diagnostic_state_budget else
    axes$promotable_state_budget
  budget <- as.integer(app_joint_sw_pick(budgets, H[[2L]]))
  budget <- max(budget, D * axes$minimum_layer_width)
  shapes <- c(axes$width_shape, "heterogeneous")
  shape <- as.character(app_joint_sw_pick(shapes, H[[3L]]))
  widths <- app_joint_pht4_widths(D, budget, shape, axes$minimum_layer_width, H[[15L]])
  lags <- axes$response_lags
  if (role == "long_memory") lags <- lags[lags >= 24L]
  response_lags <- as.integer(app_joint_sw_pick(lags, H[[4L]]))
  alpha_center <- stats::plogis(stats::qlogis(axes$alpha_range[[1L]]) +
    H[[5L]] * diff(stats::qlogis(axes$alpha_range)))
  rho_center <- axes$rho_subcritical_range[[1L]] + H[[6L]] *
    diff(axes$rho_subcritical_range)
  if (role == "local_fit" && !is.null(anchors) && nrow(anchors)) {
    anchor <- anchors[min(nrow(anchors), floor(H[[16L]] * nrow(anchors)) + 1L), , drop = FALSE]
    alpha_center <- pmin(0.9995, pmax(0.001,
      mean(app_joint_shared_parse_num_vec(anchor$alpha[[1L]])) + (H[[5L]] - 0.5) * 0.5))
    rho_center <- pmin(0.999, pmax(0.01,
      mean(app_joint_shared_parse_num_vec(anchor$rho[[1L]])) + (H[[6L]] - 0.5) * 0.5))
  }
  schedule <- if (D == 1L) "flat" else as.character(app_joint_sw_pick(axes$schedule, H[[7L]]))
  alpha <- app_joint_sw_schedule(alpha_center, D, schedule, 0.45 * H[[8L]], 0.001, 0.9995)
  if (role == "supercritical") {
    rho <- rep(as.numeric(app_joint_sw_pick(axes$rho_supercritical, H[[6L]])), D)
  } else {
    rho <- app_joint_sw_schedule(rho_center, D, schedule, 0.35 * H[[9L]], 0.01, 0.999)
  }
  input_scale <- as.numeric(app_joint_sw_pick(axes$input_scale, H[[10L]]))
  pi_in <- rep(as.numeric(app_joint_sw_pick(axes$pi_in, H[[11L]])), D)
  if (H[[12L]] < 0.5) {
    pi_w <- rep(as.numeric(app_joint_sw_pick(axes$pi_w_fixed, H[[13L]])), D)
    sparsity_mode <- "fixed_probability"
  } else {
    degree <- as.numeric(app_joint_sw_pick(axes$recurrent_expected_degree, H[[14L]]))
    pi_w <- pmin(1, degree / widths)
    sparsity_mode <- paste0("expected_degree_", format(degree, trim = TRUE))
  }
  supercritical <- any(rho >= 1)
  out <- data.frame(scenario_id = "persistent_heavy_tail", candidate_role = role,
    source_candidate_id = NA_character_, feature_contract = "pure_recursive_v1",
    design_class = "reservoir", D = D, n = app_joint_sw_fmt(widths),
    n_tilde = if (D > 1L) app_joint_sw_fmt(widths[seq_len(D - 1L)]) else "",
    retained_state_budget = sum(widths), width_shape = shape, state_reduction = FALSE,
    response_lags = response_lags, exogenous_lags = 0L,
    alpha = app_joint_sw_fmt(alpha), rho = app_joint_sw_fmt(rho),
    pi_w = app_joint_sw_fmt(pi_w), pi_in = app_joint_sw_fmt(pi_in),
    input_scale = input_scale, recurrent_sparsity_mode = sparsity_mode,
    reservoir_seed = as.integer(seed), raw_inputs_in_readout = FALSE,
    full_states_all_layers = TRUE, source_rhs_tau0 = NA_real_,
    rho_requested_max = max(rho),
    rho_regime = if (supercritical) "supercritical_opt_in" else "standard_subcritical",
    allow_supercritical_rho = supercritical, rho_upper_bound = 1.2,
    enforce_leaky_radius = !supercritical, diagnostic_only = role == "high_capacity_diagnostic",
    stringsAsFactors = FALSE)
  out$structural_signature <- app_joint_sw_structural_signature(out)
  out$architecture_signature <- app_joint_pure_architecture_signature(out)
  out
}

app_joint_pht4_historical_signatures <- function(path = app_joint_pht4_exclusion_path()) {
  x <- app_read_csv(path)
  app_check_required_columns(x, c("structural_signature", "exclusion_role"),
    "V4 historical exclusion registry")
  valid <- nrow(x) == 9722L && !anyDuplicated(x$structural_signature) &&
    all(x$exclusion_role == "prior_screen") &&
    all(grepl("^[a-f0-9]{64}$", x$structural_signature))
  if (!valid) stop("V4 historical exclusion registry is malformed.", call. = FALSE)
  x$structural_signature
}

app_joint_pht4_candidate_registry <- function(
    contract = app_joint_pht4_read_contract(), axes = app_joint_pht4_read_axes(),
    registry = app_joint_pht4_registry(contract)) {
  seed <- as.integer(registry$canonical_reservoir_seed[[1L]])
  historical <- app_joint_pht4_historical_signatures()
  controls <- app_read_csv(app_joint_pht4_controls_path())
  if (nrow(controls) != contract$control_count || anyDuplicated(controls$structural_signature)) {
    stop("V4 frozen control registry is malformed.", call. = FALSE)
  }
  controls$candidate_role <- "named_control"
  controls$diagnostic_only <- FALSE
  controls$prior_signature_exception <- TRUE
  anchors <- controls[seq_len(min(5L, nrow(controls))), , drop = FALSE]
  make_pool <- function(n, skip, role) {
    H <- app_joint_sw_halton(n, 16L, skip)
    app_bind_rows_fill(lapply(seq_len(n), function(i) {
      app_joint_pht4_candidate_from_point(H[i, ], role, axes, seed, anchors)
    }))
  }
  take <- function(n, skip, role, used) {
    pool <- make_pool(n + max(256L, ceiling(0.10 * n)), skip, role)
    pool <- pool[!pool$structural_signature %in% c(historical, used), , drop = FALSE]
    pool <- pool[!duplicated(pool$structural_signature), , drop = FALSE]
    if (nrow(pool) < n) stop(sprintf("V4 %s pool is too small after exclusion.", role), call. = FALSE)
    pool <- pool[seq_len(n), , drop = FALSE]
    pool$prior_signature_exception <- FALSE
    pool
  }
  used <- controls$structural_signature
  local <- take(contract$local_count, 110000L, "local_fit", used)
  used <- c(used, local$structural_signature)
  layered <- take(contract$layered_count, 210000L, "layered_fit", used)
  used <- c(used, layered$structural_signature)
  long <- take(contract$long_memory_count, 310000L, "long_memory", used)
  used <- c(used, long$structural_signature)
  super <- take(contract$supercritical_count, 410000L, "supercritical", used)
  used <- c(used, super$structural_signature)
  high <- take(contract$high_capacity_count, 510000L, "high_capacity_diagnostic", used)
  used <- c(used, high$structural_signature)
  global <- take(contract$global_count, 610000L, "global_unseen", used)
  out <- app_bind_rows_fill(list(controls, local, layered, long, super, high, global))
  out$candidate_id <- sprintf("persistent_heavy_tail__fitfirst_v4_%04d", seq_len(nrow(out)))
  out$joint_dense_dimension <- 7L * as.integer(out$retained_state_budget)
  out$joint_backend_eligible <- !app_as_bool_vec(out$diagnostic_only) &
    out$joint_dense_dimension <= contract$maximum_joint_dense_dimension
  out$execution_signature <- vapply(seq_len(nrow(out)), function(i) {
    app_joint_qvp_sha256_text(paste(out$structural_signature[[i]], out$reservoir_seed[[i]],
      out$rho_regime[[i]], sep = "|"))
  }, character(1L))
  counts <- table(out$candidate_role)
  expected <- c(named_control = contract$control_count, local_fit = contract$local_count,
    layered_fit = contract$layered_count, long_memory = contract$long_memory_count,
    supercritical = contract$supercritical_count,
    high_capacity_diagnostic = contract$high_capacity_count,
    global_unseen = contract$global_count)
  generated <- !app_as_bool_vec(out$prior_signature_exception)
  valid <- nrow(out) == contract$candidate_count && !anyDuplicated(out$structural_signature) &&
    all(as.integer(counts[names(expected)]) == expected) &&
    !any(out$structural_signature[generated] %in% historical) &&
    all(out$retained_state_budget[!app_as_bool_vec(out$diagnostic_only)] <= 84L) &&
    all(out$retained_state_budget[app_as_bool_vec(out$diagnostic_only)] <= 2000L) &&
    all(out$joint_backend_eligible[!app_as_bool_vec(out$diagnostic_only)]) &&
    identical(app_joint_qvp_sha256_text(paste(out$structural_signature, collapse = "|")),
      contract$candidate_signature_sha256)
  if (!valid) stop("Persistent-tail V4 candidate allocation failed.", call. = FALSE)
  out[, c("candidate_id", setdiff(names(out), "candidate_id")), drop = FALSE]
}

app_joint_pht4_fixture_row <- function(sc, registry, contract, panel, replicate_id,
    root, materialize = identical(panel, "discovery")) {
  offset <- switch(panel, discovery = contract$discovery_seed_offset,
    tail = contract$tail_seed_offset, sealed = contract$sealed_seed_offset,
    stop("Unknown V4 fixture panel.", call. = FALSE))
  row <- sc
  row$seed <- as.integer(registry$selector_seed_base[[1L]]) + offset + replicate_id - 1L
  row$seed_role <- sprintf("persistent_tail_v4_%s_rep%02d", panel, replicate_id)
  if (!materialize) {
    return(data.frame(scenario_id = contract$scenario_id, panel = panel,
      replicate_id = replicate_id, dgp_seed = row$seed[[1L]], seed_role = row$seed_role[[1L]],
      materialized = FALSE, fixture_path = NA_character_, size_bytes = NA_real_,
      sha256 = NA_character_, protected_rows_persisted = 0L, stringsAsFactors = FALSE))
  }
  fixture <- app_joint_qdesn_fixture_from_registry_row(row)
  fixture$registry_row <- row
  selector <- app_joint_pure_selector_fixture(fixture,
    app_joint_sw_read_contract(file.path(root, "frozen_contract.csv")))
  keep <- fixture$detailed_split$role %in% c("desn_washout", "fit")
  selector$mu <- fixture$mu[keep]
  selector$sigma <- fixture$sigma[keep]
  path <- file.path(root, "fixtures", sprintf("%s_rep%02d.rds", panel, replicate_id))
  saveRDS(selector, path, version = 3L, compress = "xz")
  data.frame(scenario_id = contract$scenario_id, panel = panel,
    replicate_id = replicate_id, dgp_seed = row$seed[[1L]], seed_role = row$seed_role[[1L]],
    materialized = TRUE, fixture_path = normalizePath(path, mustWork = TRUE),
    size_bytes = file.info(path)$size, sha256 = app_sha256_file(path),
    protected_rows_persisted = selector$protected_rows_persisted, stringsAsFactors = FALSE)
}

app_joint_pht4_materialize_panel <- function(root, panel, contract) {
  manifest <- app_read_csv(file.path(root, "fixture_manifest.csv"))
  rows <- manifest$panel == panel
  expected <- if (panel == "tail") contract$tail_replicates else contract$sealed_replicates
  if (sum(rows) != expected || any(app_as_bool_vec(manifest$materialized[rows]))) {
    stop(sprintf("V4 %s panel is not sealed and unmaterialized.", panel), call. = FALSE)
  }
  registry <- app_read_csv(file.path(root, "frozen_registry.csv"))
  sc <- app_read_csv(file.path(root, "derived_dgp_registry.csv"))
  sc <- sc[sc$scenario_id == contract$scenario_id, , drop = FALSE]
  app_bind_rows_fill(lapply(seq_len(expected), function(rep) {
    app_joint_pht4_fixture_row(sc, registry, contract, panel, rep, root, TRUE)
  }))
}

app_joint_pht4_freeze_plan <- function(root, stage, plan) {
  spec <- app_joint_pht4_stage_spec(stage)
  path <- app_write_csv(plan, file.path(root, spec[["plan"]]))
  hash_path <- file.path(root, paste0(stage, "_worker_plan.sha256"))
  writeLines(app_sha256_file(path), hash_path)
  app_ensure_dir(file.path(root, paste0(stage, "_workers")))
  c(plan = path, plan_sha256 = hash_path)
}

app_joint_pht4_verify_plan <- function(root, stage) {
  spec <- app_joint_pht4_stage_spec(stage)
  plan <- file.path(root, spec[["plan"]])
  receipt <- file.path(root, paste0(stage, "_worker_plan.sha256"))
  if (!file.exists(plan) || !file.exists(receipt) ||
      !identical(app_sha256_file(plan), trimws(readLines(receipt, warn = FALSE)[[1L]]))) {
    stop(sprintf("V4 %s worker plan hash mismatch.", stage), call. = FALSE)
  }
  invisible(plan)
}

app_joint_pht4_stage_spec <- function(stage) {
  switch(as.character(stage),
    sentinel = c(plan = "sentinel_worker_plan.csv", id = "sentinel_worker_id"),
    r1 = c(plan = "r1_worker_plan.csv", id = "r1_worker_id"),
    r2 = c(plan = "r2_worker_plan.csv", id = "r2_worker_id"),
    r3 = c(plan = "r3_worker_plan.csv", id = "r3_worker_id"),
    h1 = c(plan = "h1_worker_plan.csv", id = "h1_worker_id"),
    h2 = c(plan = "h2_worker_plan.csv", id = "h2_worker_id"),
    m1 = c(plan = "m1_worker_plan.csv", id = "m1_worker_id"),
    t1 = c(plan = "t1_worker_plan.csv", id = "t1_worker_id"),
    s1 = c(plan = "s1_worker_plan.csv", id = "s1_worker_id"),
    stop("Unknown persistent-tail V4 stage.", call. = FALSE))
}

app_joint_pht4_worker_dir <- function(root, stage, id) {
  file.path(root, paste0(stage, "_workers"), sprintf("worker_%05d", as.integer(id)))
}

app_joint_pht4_prepare <- function(root = app_joint_pht4_default_root()) {
  contract <- app_joint_pht4_read_contract()
  axes <- app_joint_pht4_read_axes()
  registry <- app_joint_pht4_registry(contract)
  root <- normalizePath(root, mustWork = FALSE)
  if (dir.exists(root) && length(list.files(root, all.files = TRUE, no.. = TRUE))) {
    stop("Refusing to overwrite a nonempty V4 campaign root.", call. = FALSE)
  }
  app_ensure_dir(root)
  app_ensure_dir(file.path(root, "fixtures"))
  base_path <- app_joint_pht4_write_base_contract(file.path(root, "frozen_contract.csv"))
  base <- app_joint_sw_read_contract(base_path)
  if (base$rhs_max_iter != 500L || base$quantile_max_iter != 500L ||
      base$rhs_tolerance != 1e-3 || base$vb_tolerance != 1e-3) {
    stop("V4 numerical controls did not reach the fitting APIs.", call. = FALSE)
  }
  candidates <- app_joint_pht4_candidate_registry(contract, axes, registry)
  historical <- data.frame(structural_signature = app_joint_pht4_historical_signatures(),
    exclusion_role = "prior_screen", stringsAsFactors = FALSE)
  derived <- app_joint_sw_derived_dgp_registry(base, registry)
  sc <- derived[derived$scenario_id == contract$scenario_id, , drop = FALSE]
  discovery <- app_bind_rows_fill(lapply(seq_len(contract$discovery_replicates), function(rep) {
    app_joint_pht4_fixture_row(sc, registry, contract, "discovery", rep, root, TRUE)
  }))
  tail <- app_bind_rows_fill(lapply(seq_len(contract$tail_replicates), function(rep) {
    app_joint_pht4_fixture_row(sc, registry, contract, "tail", rep, root, FALSE)
  }))
  sealed <- app_bind_rows_fill(lapply(seq_len(contract$sealed_replicates), function(rep) {
    app_joint_pht4_fixture_row(sc, registry, contract, "sealed", rep, root, FALSE)
  }))
  fixtures <- app_bind_rows_fill(list(discovery, tail, sealed))
  discovery_plan <- discovery[, c("scenario_id", "replicate_id", "dgp_seed", "fixture_path"),
    drop = FALSE]
  r1 <- merge(candidates, discovery_plan, by = "scenario_id", all.x = TRUE, sort = FALSE)
  r1$origin_indices <- paste(contract$r1_origins, collapse = ";")
  r1$r1_worker_id <- seq_len(nrow(r1))
  if (nrow(r1) != contract$candidate_count * contract$discovery_replicates ||
      anyNA(r1$fixture_path)) stop("V4 R1 plan cardinality failed.", call. = FALSE)
  low <- candidates[candidates$candidate_role == "local_fit" &
    candidates$retained_state_budget <= 24L, , drop = FALSE][1L, , drop = FALSE]
  high <- candidates[candidates$candidate_role == "high_capacity_diagnostic" &
    candidates$retained_state_budget >= 1500L, , drop = FALSE][1L, , drop = FALSE]
  exact <- candidates[!is.na(candidates$source_candidate_id) &
    candidates$source_candidate_id == "persistent_heavy_tail__targeted_0209", , drop = FALSE]
  if (nrow(low) != 1L || nrow(high) != 1L || nrow(exact) != 1L) {
    stop("V4 sentinel candidates are unavailable.", call. = FALSE)
  }
  sentinel <- app_bind_rows_fill(list(low, high, exact, exact, exact, exact))
  sentinel$sentinel_method <- c("ridge_low", "ridge_high", "normal_rhs", "median_al",
    "lower_al", "upper_al")
  sentinel$rhs_tau0 <- c(NA, NA, 1000, 1000, 1000, 1000)
  sentinel$normal_rhs_tau0 <- sentinel$rhs_tau0
  sentinel$rhs_zeta2_profile <- "learned"
  sentinel$rhs_zeta2_fixed <- NA_real_
  sentinel$prior_mode <- "fixed_tau0"
  sentinel$tau <- c(NA, NA, NA, 0.5, 0.05, 0.95)
  sentinel$replicate_id <- discovery$replicate_id[[1L]]
  sentinel$dgp_seed <- discovery$dgp_seed[[1L]]
  sentinel$fixture_path <- discovery$fixture_path[[1L]]
  sentinel$origin_indices <- paste(contract$r1_origins, collapse = ";")
  sentinel$sentinel_worker_id <- seq_len(nrow(sentinel))
  files <- c(frozen_contract = base_path,
    frozen_v4_contract = app_write_csv(contract$table, file.path(root, "frozen_v4_contract.csv")),
    frozen_v4_axes = app_write_csv(axes$table, file.path(root, "frozen_v4_axes.csv")),
    frozen_registry = app_write_csv(registry, file.path(root, "frozen_registry.csv")),
    derived_dgp_registry = app_write_csv(derived, file.path(root, "derived_dgp_registry.csv")),
    historical_signatures = app_write_csv(historical,
      file.path(root, "historical_signature_exclusion_registry.csv")),
    candidates = app_write_csv(candidates, file.path(root, "candidate_registry.csv")),
    fixtures = app_write_csv(fixtures, file.path(root, "fixture_manifest.csv")),
    app_joint_pht4_freeze_plan(root, "sentinel", sentinel),
    app_joint_pht4_freeze_plan(root, "r1", r1),
    source_git_state = app_write_csv(app_joint_shared_git_state(),
      file.path(root, "source_git_state.csv")))
  expected <- data.frame(r1_workers = 24576L, r2_workers = 3072L, r3_workers = 1152L,
    h1_workers = 1920L, h2_workers_max = 576L, m1_workers = 480L,
    t1_workers = 120L, s1_workers = 35L, maximum_atomic_workers = 31931L,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  readiness <- data.frame(status = "V4_PREPARED_SENTINELS_NOT_LAUNCHED",
    parent_head = contract$parent_head, required_hostname = contract$required_hostname,
    downstream_auto_launch = FALSE, tail_materialized = FALSE, sealed_materialized = FALSE,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  files <- c(files,
    expected = app_write_csv(expected, file.path(root, "expected_work.csv")),
    readiness = app_write_csv(readiness, file.path(root, "launch_readiness.csv")))
  app_joint_shared_write_manifest(root, files, filename = "preparation_manifest.csv")
  verified <- app_joint_shared_verify_manifest(root, file.path(root, "preparation_manifest.csv"))
  if (!all(verified$verified) || any(discovery$protected_rows_persisted != 0L) ||
      any(app_as_bool_vec(tail$materialized)) || any(app_as_bool_vec(sealed$materialized))) {
    stop("V4 preparation manifest or protected-data gate failed.", call. = FALSE)
  }
  app_write_csv(verified, file.path(root, "preparation_manifest_verification.csv"))
  list(root = root, expected = expected, readiness = readiness)
}

app_joint_pht4_health <- function(root, stage) {
  spec <- app_joint_pht4_stage_spec(stage)
  path <- file.path(root, spec[["plan"]])
  if (!file.exists(path)) return(data.frame(stage = stage, expected = 0L, completed = 0L,
    failed = 0L, remaining = 0L, status = "not_prepared", stringsAsFactors = FALSE))
  app_joint_pht4_verify_plan(root, stage)
  plan <- app_read_csv(path)
  dirs <- vapply(plan[[spec[["id"]]]], function(id) app_joint_pht4_worker_dir(root, stage, id),
    character(1L))
  done <- file.exists(file.path(dirs, "DONE")) & file.exists(file.path(dirs, "artifact_manifest.csv"))
  failed <- file.exists(file.path(dirs, "FAILED")) | file.exists(file.path(dirs, "failure.csv"))
  data.frame(stage = stage, expected = nrow(plan), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), status = if (any(failed)) "failed" else if (all(done))
      "complete" else if (any(done)) "running" else "ready", stringsAsFactors = FALSE)
}

app_joint_pht4_all_health <- function(root) {
  app_bind_rows_fill(lapply(c("sentinel", "r1", "r2", "r3", "h1", "h2", "m1", "t1", "s1"),
    function(stage) app_joint_pht4_health(root, stage)))
}

app_joint_pht4_collect <- function(root, stage) {
  health <- app_joint_pht4_health(root, stage)
  if (health$completed[[1L]] != health$expected[[1L]] || health$failed[[1L]] != 0L) {
    stop(sprintf("V4 %s is not complete and failure-free.", stage), call. = FALSE)
  }
  spec <- app_joint_pht4_stage_spec(stage)
  plan <- app_read_csv(file.path(root, spec[["plan"]]))
  rows <- lapply(plan[[spec[["id"]]]], function(id) {
    worker <- app_joint_pht4_worker_dir(root, stage, id)
    verified <- app_joint_shared_verify_manifest(worker, file.path(worker, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified)) {
      stop(sprintf("V4 %s worker %d manifest failed.", stage, id), call. = FALSE)
    }
    app_read_csv(file.path(worker, "summary.csv"))
  })
  app_bind_rows_fill(rows)
}

app_joint_pht4_location_metrics <- function(result) {
  design <- result$design
  tr <- design$train_local
  beta <- as.numeric(result$fit$beta_mean)
  if (length(beta) != ncol(design$X)) stop("V4 Gaussian coefficient dimension mismatch.", call. = FALSE)
  fit_hat <- as.numeric(design$X[tr, , drop = FALSE] %*% beta)
  median_index <- match(0.5, design$tau)
  fit_truth <- design$true_q[tr, median_index]
  detail <- result$detail
  local <- match(detail$full_time_index, design$row_meta$full_time_index)
  if (anyNA(local)) stop("V4 Gaussian forecast rows do not map to the design.", call. = FALSE)
  forecast_truth <- design$true_q[local, median_index]
  h1 <- detail$horizon == 1L
  data.frame(
    training_location_mae = mean(abs(fit_hat - fit_truth)),
    training_location_rmse = sqrt(mean((fit_hat - fit_truth)^2)),
    horizon1_location_mae = mean(abs(detail$pred_mean[h1] - forecast_truth[h1])),
    recursive_location_mae = mean(abs(detail$pred_mean - forecast_truth)),
    location_functionals_finite = all(is.finite(c(fit_hat, fit_truth, detail$pred_mean,
      forecast_truth))), stringsAsFactors = FALSE)
}

app_joint_pht4_quantile_metrics <- function(result, tau) {
  design <- result$design
  fit <- result$fit
  tr <- design$train_local
  k <- match(tau, design$tau)
  if (is.na(k)) stop("V4 quantile metric tau is outside the grid.", call. = FALSE)
  fit_hat <- as.numeric(fit$alpha_mean[[1L]] + design$Z[tr, , drop = FALSE] %*%
    as.numeric(fit$beta_mean))
  fit_truth <- design$true_q[tr, k]
  detail <- result$detail
  h1 <- detail$horizon == 1L
  data.frame(
    training_quantile_mae = mean(abs(fit_hat - fit_truth)),
    training_quantile_rmse = sqrt(mean((fit_hat - fit_truth)^2)),
    horizon1_quantile_mae = mean(abs(detail$qhat[h1] - detail$true_quantile[h1])),
    horizon1_5_quantile_mae = mean(abs(detail$qhat[detail$horizon <= 5L] -
      detail$true_quantile[detail$horizon <= 5L])),
    recursive_quantile_mae = mean(abs(detail$qhat - detail$true_quantile)),
    quantile_functionals_finite = all(is.finite(c(fit_hat, fit_truth, detail$qhat,
      detail$true_quantile))), stringsAsFactors = FALSE)
}

app_joint_pht4_score_quantile <- function(fixture, candidate, base_contract,
    origin_indices, tau) {
  controls <- app_joint_pht3_quantile_controls(base_contract, candidate)
  design <- app_joint_pure_build_design(fixture, candidate, base_contract, selector = TRUE)
  started <- proc.time()[[3L]]
  normal <- app_joint_pht3_fit_normal_initializer(design, candidate, base_contract, controls)
  median_init <- app_joint_swq_single_init(normal, 0.5, design)
  median_fit <- app_joint_swq_fit_al(design, normal, controls, 0.5, median_init,
    controls$median_max_iter)
  if (tau == 0.5) {
    fit <- median_fit
  } else {
    init <- median_fit
    k <- match(tau, normal$initializer$tau)
    if (is.na(k) || !tau %in% c(0.05, 0.95)) stop("V4 tail tau is invalid.", call. = FALSE)
    init$alpha_mean <- normal$initializer$alpha_mean[[k]]
    init$sigma_mean <- max(median_fit$sigma_mean[[1L]], normal$initializer$sigma_mean[[k]])
    fit <- app_joint_swq_fit_al(design, normal, controls, tau, init,
      controls$quantile_max_iter)
  }
  pred <- app_joint_swq_recursive_quantile(design, fixture, fit, median_fit,
    base_contract, origin_indices)
  y <- design$y[pred$score_local]
  truth_index <- match(tau, design$tau)
  check <- app_check_loss(y, pred$qhat, tau)
  detail <- data.frame(full_time_index = pred$full_time_index,
    origin_index = pred$origin_index, horizon = pred$horizon, tau = tau, y = y,
    qhat = pred$qhat, median_feedback = pred$median_qhat,
    true_quantile = design$true_q[pred$score_local, truth_index],
    check_loss = check, stringsAsFactors = FALSE)
  local <- match(detail$full_time_index, design$row_meta$full_time_index)
  expected_check <- if (!is.null(fixture$mu) && !is.null(fixture$sigma)) {
    app_joint_qdesn_postscore_expected_check(detail$qhat, tau, fixture$mu[local],
      fixture$sigma[local], fixture$registry_row)
  } else rep(NA_real_, nrow(detail))
  companion <- list(fit_mae = NA_real_, horizon1_mae = NA_real_, recursive_mae = NA_real_,
    dgp_score = NA_real_)
  if (tau == 0.5) {
    median_fit_hat <- as.numeric(median_fit$alpha_mean[[1L]] +
      design$Z[design$train_local, , drop = FALSE] %*% as.numeric(median_fit$beta_mean))
    median_truth <- design$true_q[design$train_local, truth_index]
    companion <- list(fit_mae = mean(abs(median_fit_hat - median_truth)),
      horizon1_mae = mean(abs(detail$qhat[detail$horizon == 1L] -
        detail$true_quantile[detail$horizon == 1L])),
      recursive_mae = mean(abs(detail$qhat - detail$true_quantile)),
      dgp_score = mean(2 * expected_check))
  } else {
    median_pred <- app_joint_swq_recursive_quantile(design, fixture, median_fit, median_fit,
      base_contract, origin_indices)
    median_k <- match(0.5, design$tau)
    median_fit_hat <- as.numeric(median_fit$alpha_mean[[1L]] +
      design$Z[design$train_local, , drop = FALSE] %*% as.numeric(median_fit$beta_mean))
    median_truth <- design$true_q[design$train_local, median_k]
    median_local <- match(median_pred$full_time_index, design$row_meta$full_time_index)
    median_forecast_truth <- design$true_q[median_pred$score_local, median_k]
    median_expected <- app_joint_qdesn_postscore_expected_check(median_pred$qhat, 0.5,
      fixture$mu[median_local], fixture$sigma[median_local], fixture$registry_row)
    companion <- list(
      fit_mae = mean(abs(median_fit_hat - median_truth)),
      horizon1_mae = mean(abs(median_pred$qhat[median_pred$horizon == 1L] -
        median_forecast_truth[median_pred$horizon == 1L])),
      recursive_mae = mean(abs(median_pred$qhat - median_forecast_truth)),
      dgp_score = mean(2 * median_expected))
  }
  compact <- app_joint_shared_quantile_compact_fit(fit)
  summary <- cbind(candidate, data.frame(status = "completed",
    method = "independent_al_rhs_vb_fit_first", tau = tau,
    n_train = length(design$train_local), n_calibration_scored = length(y),
    protected_rows_loaded = design$diagnostic$protected_rows_loaded,
    calibration_check_loss_mean = mean(check), calibration_check_loss_sd = stats::sd(check),
    dgp_expected_quantile_score = mean(2 * expected_check),
    companion_median_fit_mae = companion$fit_mae,
    companion_median_horizon1_mae = companion$horizon1_mae,
    companion_median_recursive_mae = companion$recursive_mae,
    companion_median_dgp_expected_quantile_score = companion$dgp_score,
    calibration_oracle_quantile_mae = mean(abs(detail$qhat - detail$true_quantile)),
    calibration_oracle_quantile_rmse = sqrt(mean((detail$qhat - detail$true_quantile)^2)),
    recursive_state_saturation_fraction = pred$recursive_state_saturation_fraction,
    recursive_state_max_abs = pred$recursive_state_max_abs,
    recursive_state_finite = pred$recursive_state_finite,
    median_converged = isTRUE(median_fit$converged), converged = isTRUE(fit$converged),
    convergence_status = if (isTRUE(fit$converged)) "pass" else "review_max_iter",
    iterations = as.integer(fit$iterations_completed %||% fit$iterations %||% NA_integer_),
    runtime_seconds = proc.time()[[3L]] - started,
    peak_rss_kib = app_joint_sw_vm_hwm_kib(), stringsAsFactors = FALSE))
  out <- list(summary = summary, detail = detail,
    trace = app_joint_shared_quantile_trace_frame(fit), fit = compact,
    median_fit = app_joint_shared_quantile_compact_fit(median_fit),
    normal_initializer = normal, design = design)
  out$summary <- cbind(out$summary, app_joint_pht4_quantile_metrics(out, tau))
  out
}

app_joint_pht4_fit_three <- function(fixture, candidate, base_contract, origin_indices) {
  controls <- app_joint_pht3_quantile_controls(base_contract, candidate)
  design <- app_joint_pure_build_design(fixture, candidate, base_contract, selector = TRUE)
  normal <- app_joint_pht3_fit_normal_initializer(design, candidate, base_contract, controls)
  fits <- list()
  details <- list()
  median_fit <- app_joint_swq_fit_al(design, normal, controls, 0.5,
    app_joint_swq_single_init(normal, 0.5, design), controls$median_max_iter)
  fits[["0.50"]] <- median_fit
  for (tau in c(0.05, 0.50, 0.95)) {
    key <- sprintf("%.2f", tau)
    if (tau == 0.5) {
      fit <- median_fit
    } else {
      init <- median_fit
      k <- match(tau, normal$initializer$tau)
      init$alpha_mean <- normal$initializer$alpha_mean[[k]]
      init$sigma_mean <- max(median_fit$sigma_mean[[1L]], normal$initializer$sigma_mean[[k]])
      fit <- app_joint_swq_fit_al(design, normal, controls, tau, init,
        controls$quantile_max_iter)
      fits[[key]] <- fit
    }
    pred <- app_joint_swq_recursive_quantile(design, fixture, fit, median_fit,
      base_contract, origin_indices)
    k <- match(tau, design$tau)
    tr <- design$train_local
    fit_hat <- as.numeric(fit$alpha_mean[[1L]] + design$Z[tr, , drop = FALSE] %*%
      as.numeric(fit$beta_mean))
    details[[key]] <- data.frame(full_time_index = pred$full_time_index,
      origin_index = pred$origin_index, horizon = pred$horizon, tau = tau,
      y = design$y[pred$score_local], qhat = pred$qhat,
      true_quantile = design$true_q[pred$score_local, k],
      training_quantile_mae = mean(abs(fit_hat - design$true_q[tr, k])),
      training_quantile_rmse = sqrt(mean((fit_hat - design$true_q[tr, k])^2)),
      recursive_state_finite = pred$recursive_state_finite,
      stringsAsFactors = FALSE)
  }
  detail <- app_bind_rows_fill(details)
  by_tau <- split(detail, detail$tau)
  metric <- function(tau, field) unique(by_tau[[as.character(tau)]][[field]])[[1L]]
  h1_mae <- vapply(by_tau, function(x) mean(abs(x$qhat[x$horizon == 1L] -
    x$true_quantile[x$horizon == 1L])), numeric(1L))
  rec_mae <- vapply(by_tau, function(x) mean(abs(x$qhat - x$true_quantile)), numeric(1L))
  fit_mae <- vapply(by_tau, function(x) unique(x$training_quantile_mae)[[1L]], numeric(1L))
  wide <- do.call(cbind, lapply(c(0.05, 0.50, 0.95), function(tau) {
    x <- by_tau[[as.character(tau)]]
    x$qhat
  }))
  reference <- by_tau[["0.5"]]
  score <- app_joint_shared_acrps(reference$y, wide, c(0.05, 0.50, 0.95))
  local <- match(reference$full_time_index, design$row_meta$full_time_index)
  dgp_score <- app_joint_qdesn_postscore_score_matrix(wide, reference$y,
    fixture$mu[local], fixture$sigma[local], fixture$registry_row,
    c(0.05, 0.50, 0.95), app_joint_shared_weights(c(0.05, 0.50, 0.95)))
  crossing <- app_joint_qdesn_apply_monotone_contract(wide, c(0.05, 0.50, 0.95))
  summary <- cbind(candidate, data.frame(status = "completed",
    method = "independent_al_rhs_vb_three_level_sealed",
    lower_fit_mae = unname(fit_mae[["0.05"]]), median_fit_mae = unname(fit_mae[["0.5"]]),
    upper_fit_mae = unname(fit_mae[["0.95"]]),
    lower_horizon1_mae = unname(h1_mae[["0.05"]]),
    median_horizon1_mae = unname(h1_mae[["0.5"]]),
    upper_horizon1_mae = unname(h1_mae[["0.95"]]),
    lower_recursive_mae = unname(rec_mae[["0.05"]]),
    median_recursive_mae = unname(rec_mae[["0.5"]]),
    upper_recursive_mae = unname(rec_mae[["0.95"]]),
    realized_three_level_score = mean(score),
    dgp_integrated_three_level_score = dgp_score$dgp_integrated_acrps,
    raw_crossing_pairs = sum(crossing$raw_crossing$n_crossing_pairs),
    contract_crossing_pairs = sum(crossing$contract_crossing$n_crossing_pairs),
    all_components_converged = all(vapply(fits, function(x) isTRUE(x$converged), logical(1L))),
    convergence_status = if (all(vapply(fits, function(x) isTRUE(x$converged), logical(1L))))
      "pass" else "review_max_iter",
    recursive_state_finite = all(vapply(by_tau, function(x)
      all(app_as_bool_vec(x$recursive_state_finite)), logical(1L))),
    protected_rows_loaded = design$diagnostic$protected_rows_loaded,
    functionals_finite = all(is.finite(c(fit_mae, h1_mae, rec_mae, score))),
    stringsAsFactors = FALSE))
  list(summary = summary, detail = detail,
    fit = lapply(fits, app_joint_shared_quantile_compact_fit),
    normal_initializer = normal, design = design)
}

app_joint_pht4_run_worker <- function(root, stage, worker_id) {
  root <- normalizePath(root, mustWork = TRUE)
  app_joint_pht4_verify_plan(root, stage)
  spec <- app_joint_pht4_stage_spec(stage)
  plan <- app_read_csv(file.path(root, spec[["plan"]]))
  row <- plan[plan[[spec[["id"]]]] == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("V4 worker ID is not unique.", call. = FALSE)
  out <- app_joint_pht4_worker_dir(root, stage, worker_id)
  if (file.exists(file.path(out, "DONE")) && file.exists(file.path(out, "artifact_manifest.csv"))) {
    verified <- app_joint_shared_verify_manifest(out, file.path(out, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified)) {
      stop("V4 completed worker has an incompatible artifact manifest.", call. = FALSE)
    }
    return(invisible(out))
  }
  tmp <- paste0(out, ".tmp_", Sys.getpid())
  unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  base <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  contract <- app_joint_pht4_read_contract(file.path(root, "frozen_v4_contract.csv"))
  fixture <- readRDS(row$fixture_path[[1L]])
  origins <- as.integer(strsplit(as.character(row$origin_indices[[1L]]), ";", fixed = TRUE)[[1L]])
  started <- Sys.time()
  captured <- tryCatch(app_joint_sw_capture_warnings(function() {
    if (stage == "sentinel") {
      method <- as.character(row$sentinel_method[[1L]])
      if (method %in% c("ridge_low", "ridge_high")) {
        result <- app_joint_sw_score_ridge(fixture, row, base, origins)
        result$summary <- cbind(result$summary, app_joint_pht4_location_metrics(result))
        result
      } else if (method == "normal_rhs") {
        result <- app_joint_pht3_score_rhs(fixture, row, base, origins)
        result$summary <- cbind(result$summary, app_joint_pht4_location_metrics(result))
        result
      } else {
        tau <- c(median_al = 0.5, lower_al = 0.05, upper_al = 0.95)[[method]]
        app_joint_pht4_score_quantile(fixture, row, base, origins, tau)
      }
    } else if (stage %in% c("r1", "r2", "r3")) {
      result <- app_joint_sw_score_ridge(fixture, row, base, origins)
      result$summary <- cbind(result$summary, app_joint_pht4_location_metrics(result))
      result
    } else if (stage %in% c("h1", "h2")) {
      result <- app_joint_pht3_score_rhs(fixture, row, base, origins)
      result$summary <- cbind(result$summary, app_joint_pht4_location_metrics(result))
      result
    } else if (stage == "m1") {
      app_joint_pht4_score_quantile(fixture, row, base, origins, 0.5)
    } else if (stage == "t1") {
      app_joint_pht4_score_quantile(fixture, row, base, origins, as.numeric(row$tau[[1L]]))
    } else if (stage == "s1") {
      app_joint_pht4_fit_three(fixture, row, base, origins)
    } else stop("Unsupported V4 stage.", call. = FALSE)
  }), error = function(e) e)
  if (inherits(captured, "error")) {
    app_ensure_dir(out)
    app_write_csv(cbind(row, data.frame(status = "failed", error_message = conditionMessage(captured),
      runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      stringsAsFactors = FALSE)), file.path(out, "failure.csv"))
    writeLines("failed", file.path(out, "FAILED"))
    unlink(tmp, recursive = TRUE, force = TRUE)
    stop(conditionMessage(captured), call. = FALSE)
  }
  result <- captured$value
  reservoir <- app_joint_pht3_reservoir_diagnostics(result$design)
  result$summary <- cbind(result$summary, reservoir)
  supercritical <- as.numeric(row$rho_requested_max[[1L]] %||% 0) >= 1
  perturbation_change <- NA_real_
  perturbation_pass <- TRUE
  if (stage == "r3" && supercritical) {
    perturbed <- app_joint_sw_recursive_gaussian(result$design, fixture, result$fit, base,
      origins, state_perturbation = contract$initial_state_perturbation_scale)
    perturbed_score <- mean(abs(perturbed$pred_mean - result$design$true_q[
      perturbed$score_local, match(0.5, result$design$tau)]))
    reference_score <- result$summary$recursive_location_mae[[1L]]
    perturbation_change <- abs(perturbed_score - reference_score) /
      max(abs(reference_score), sqrt(.Machine$double.eps))
    perturbation_pass <- isTRUE(perturbed$recursive_state_finite) &&
      is.finite(perturbation_change) &&
      perturbation_change <= contract$max_initial_state_score_relative_change
  }
  result$summary$initial_state_score_relative_change <- perturbation_change
  result$summary$initial_state_perturbation_pass <- perturbation_pass
  finite_columns <- grep("(mae|rmse|score|finite)$", names(result$summary), value = TRUE)
  functional_finite <- all(vapply(result$summary[finite_columns], function(x) {
    if (is.logical(x)) all(!is.na(x) & x) else all(is.finite(as.numeric(x)))
  }, logical(1L)))
  recursive_finite <- isTRUE(app_as_bool_vec(result$summary$recursive_state_finite %||% TRUE)[[1L]])
  result$summary$convergence_review_only <- any(grepl("review", as.character(
    result$summary$convergence_status %||% "pass")))
  result$summary$hard_functional_pass <- functional_finite && recursive_finite &&
    isTRUE(reservoir$realized_connectivity_pass[[1L]]) && perturbation_pass &&
    result$summary$protected_rows_loaded[[1L]] == 0L
  result$summary$screening_eligible <- result$summary$hard_functional_pass
  result$summary$warning_count <- length(captured$warnings)
  result$summary$warning_messages <- paste(captured$warnings, collapse = " | ")
  result$summary$runtime_seconds_total <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  files <- c(summary = app_write_csv(result$summary, file.path(tmp, "summary.csv")),
    detail = app_write_csv(result$detail, file.path(tmp, "detail.csv")))
  if (!is.null(result$trace) && nrow(result$trace)) {
    files <- c(files, trace = app_write_csv(result$trace, file.path(tmp, "vb_trace.csv")))
  }
  save_quantile <- stage %in% c("m1", "t1", "s1") ||
    (stage == "sentinel" && row$sentinel_method[[1L]] %in% c("median_al", "lower_al", "upper_al"))
  if (save_quantile) {
    fit_path <- file.path(tmp, "fit_initializer.rds")
    saveRDS(result$fit, fit_path, version = 3L, compress = "xz")
    files <- c(files, fit_initializer = fit_path)
    normal_path <- file.path(tmp, "normal_initializer.rds")
    saveRDS(result$normal_initializer, normal_path, version = 3L, compress = "xz")
    files <- c(files, normal_initializer = normal_path)
  }
  if (length(captured$warnings)) files <- c(files, warnings = app_write_csv(data.frame(
    warning_index = seq_along(captured$warnings), warning_message = captured$warnings,
    stringsAsFactors = FALSE), file.path(tmp, "warnings.csv")))
  app_joint_shared_write_manifest(tmp, files)
  verified <- app_joint_shared_verify_manifest(tmp, file.path(tmp, "artifact_manifest.csv"))
  if (!all(verified$verified)) stop("V4 worker manifest verification failed.", call. = FALSE)
  writeLines("completed", file.path(tmp, "DONE"))
  if (dir.exists(out)) unlink(out, recursive = TRUE, force = TRUE)
  if (!file.rename(tmp, out)) stop("Could not atomically publish V4 worker.", call. = FALSE)
  invisible(out)
}

app_joint_pht4_freeze_manifest <- function(root, files, filename) {
  path <- app_joint_shared_write_manifest(root, files, filename = filename)
  verified <- app_joint_shared_verify_manifest(root, path)
  if (!nrow(verified) || any(!verified$verified)) {
    stop(sprintf("V4 manifest failed: %s", filename), call. = FALSE)
  }
  app_write_csv(verified, file.path(root, sub("[.]csv$", "_verification.csv", filename)))
  path
}

app_joint_pht4_location_aggregate <- function(scores, extra_keys = character()) {
  keys <- c("candidate_id", extra_keys)
  group <- interaction(scores[, keys, drop = FALSE], drop = TRUE, lex.order = TRUE)
  app_bind_rows_fill(lapply(split(scores, group), function(x) {
    meta <- x[1L, intersect(c("scenario_id", "candidate_id", "candidate_role",
      "source_candidate_id", "structural_signature", "architecture_signature", "D", "n",
      "retained_state_budget", "response_lags", "alpha", "rho", "pi_w", "pi_in",
      "input_scale", "recurrent_sparsity_mode", "reservoir_seed", "rho_requested_max",
      "diagnostic_only", "joint_backend_eligible", extra_keys, "rhs_tau0",
      "rhs_zeta2_profile", "rhs_zeta2_fixed", "prior_spec_id"), names(x)), drop = FALSE]
    cbind(meta, data.frame(replicates = nrow(x),
      training_location_mae_mean = mean(x$training_location_mae),
      training_location_mae_worst = max(x$training_location_mae),
      training_location_rmse_mean = mean(x$training_location_rmse),
      horizon1_location_mae_mean = mean(x$horizon1_location_mae),
      horizon1_location_mae_worst = max(x$horizon1_location_mae),
      recursive_location_mae_mean = mean(x$recursive_location_mae),
      recursive_location_mae_worst = max(x$recursive_location_mae),
      hard_functional_pass_all = all(app_as_bool_vec(x$hard_functional_pass)),
      convergence_review_any = any(app_as_bool_vec(x$convergence_review_only)),
      warning_count_sum = sum(as.integer(x$warning_count)),
      runtime_seconds_mean = mean(x$runtime_seconds_total), stringsAsFactors = FALSE))
  }))
}

app_joint_pht4_exact_id <- function(x) {
  hit <- !is.na(x$source_candidate_id) &
    x$source_candidate_id == "persistent_heavy_tail__targeted_0209"
  ids <- unique(x$candidate_id[hit])
  if (length(ids) != 1L) stop("V4 exact V2 control is not unique.", call. = FALSE)
  ids[[1L]]
}

app_joint_pht4_select_quota <- function(x, n, quotas, allow_diagnostic = TRUE) {
  eligible <- x[app_as_bool_vec(x$hard_functional_pass_all), , drop = FALSE]
  if (!allow_diagnostic) eligible <- eligible[!app_as_bool_vec(eligible$diagnostic_only), , drop = FALSE]
  eligible <- eligible[order(eligible$training_location_mae_mean,
    eligible$horizon1_location_mae_mean, eligible$recursive_location_mae_mean,
    eligible$candidate_id), , drop = FALSE]
  if (nrow(eligible) < n) stop("Too few V4 fit-capable candidates for the frozen frontier.", call. = FALSE)
  selected <- character()
  for (role in names(quotas)) {
    block <- eligible[eligible$candidate_role == role & !eligible$candidate_id %in% selected, , drop = FALSE]
    selected <- c(selected, head(block$candidate_id, quotas[[role]]))
  }
  exact <- app_joint_pht4_exact_id(x)
  if (exact %in% eligible$candidate_id && !exact %in% selected) selected <- c(exact, selected)
  selected <- unique(selected)
  if (length(selected) > n) selected <- selected[seq_len(n)]
  if (length(selected) < n) {
    selected <- c(selected, head(eligible$candidate_id[!eligible$candidate_id %in% selected],
      n - length(selected)))
  }
  out <- eligible[match(selected, eligible$candidate_id), , drop = FALSE]
  out$advancement_rank <- seq_len(nrow(out))
  if (nrow(out) != n || anyNA(out$candidate_id) || !exact %in% out$candidate_id) {
    stop("V4 quota selection failed or dropped the exact control.", call. = FALSE)
  }
  out
}

app_joint_pht4_stage_files <- function(root, stage, scores, aggregate, selected,
    decision, plan_files = c()) {
  files <- c(scores = app_write_csv(scores, file.path(root, paste0(stage, "_scores.csv"))),
    aggregate = app_write_csv(aggregate, file.path(root, paste0(stage, "_aggregate.csv"))),
    selected = app_write_csv(selected, file.path(root, paste0(stage, "_selected.csv"))),
    decision = app_write_csv(decision, file.path(root, paste0(stage, "_decision.csv"))),
    plan_files, app_joint_sw_stage_receipts(root, stage))
  app_joint_pht4_freeze_manifest(root, files, paste0(stage, "_manifest.csv"))
  decision
}

app_joint_pht4_finalize_ridge <- function(root, stage) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_pht4_read_contract(file.path(root, "frozen_v4_contract.csv"))
  scores <- app_joint_pht4_collect(root, stage)
  aggregate <- app_joint_pht4_location_aggregate(scores)
  if (stage == "r1") {
    selected <- app_joint_pht4_select_quota(aggregate, contract$r1_advance_count,
      c(named_control = 4L, local_fit = 256L, layered_fit = 256L, long_memory = 192L,
        supercritical = 128L, high_capacity_diagnostic = 128L, global_unseen = 60L), TRUE)
    fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))
    fixtures <- fixtures[fixtures$panel == "discovery", c("scenario_id", "replicate_id",
      "dgp_seed", "fixture_path"), drop = FALSE]
    registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
    candidates <- registry[match(selected$candidate_id, registry$candidate_id), , drop = FALSE]
    plan <- merge(candidates, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
    plan$origin_indices <- paste(contract$full_origins, collapse = ";")
    plan$r2_worker_id <- seq_len(nrow(plan))
    if (nrow(plan) != 3072L) stop("V4 R2 plan cardinality failed.", call. = FALSE)
    plan_files <- app_joint_pht4_freeze_plan(root, "r2", plan)
    decision <- data.frame(status = "R1_COMPLETE_R2_PREPARED_FOR_REVIEW",
      selected_candidates = nrow(selected), next_workers = nrow(plan), next_launched = FALSE,
      protected_rows_used = 0L, stringsAsFactors = FALSE)
  } else if (stage == "r2") {
    selected <- app_joint_pht4_select_quota(aggregate, contract$r2_advance_count,
      c(named_control = 3L, local_fit = 32L, layered_fit = 32L, long_memory = 24L,
        supercritical = 16L, high_capacity_diagnostic = 8L, global_unseen = 13L), TRUE)
    fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))
    fixtures <- fixtures[fixtures$panel == "discovery", c("scenario_id", "replicate_id",
      "dgp_seed", "fixture_path"), drop = FALSE]
    registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
    candidates <- registry[match(selected$candidate_id, registry$candidate_id), , drop = FALSE]
    seeded <- app_bind_rows_fill(lapply(contract$reservoir_seed_offsets, function(offset) {
      out <- candidates
      out$reservoir_seed <- as.integer(out$reservoir_seed) + offset
      out$reservoir_seed_offset <- offset
      out
    }))
    plan <- merge(seeded, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
    plan$origin_indices <- paste(contract$full_origins, collapse = ";")
    plan$r3_worker_id <- seq_len(nrow(plan))
    if (nrow(plan) != 1152L) stop("V4 R3 plan cardinality failed.", call. = FALSE)
    plan_files <- app_joint_pht4_freeze_plan(root, "r3", plan)
    decision <- data.frame(status = "R2_COMPLETE_R3_PREPARED_FOR_REVIEW",
      selected_candidates = nrow(selected), next_workers = nrow(plan), next_launched = FALSE,
      protected_rows_used = 0L, stringsAsFactors = FALSE)
  } else {
    selected <- app_joint_pht4_select_quota(aggregate, contract$r3_advance_count,
      c(named_control = 3L, local_fit = 18L, layered_fit = 18L, long_memory = 12L,
        supercritical = 7L, global_unseen = 6L), FALSE)
    fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))
    fixtures <- fixtures[fixtures$panel == "discovery", c("scenario_id", "replicate_id",
      "dgp_seed", "fixture_path"), drop = FALSE]
    registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
    candidates <- registry[match(selected$candidate_id, registry$candidate_id), , drop = FALSE]
    profiles <- merge(candidates, data.frame(prior_mode = "fixed_tau0",
      rhs_tau0 = contract$rhs_tau0_values,
      prior_spec_id = sprintf("h1_tau_%02d", seq_along(contract$rhs_tau0_values)),
      stringsAsFactors = FALSE), by = NULL)
    plan <- merge(profiles, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
    plan$rhs_zeta2_profile <- "learned"
    plan$rhs_zeta2_fixed <- NA_real_
    plan$origin_indices <- paste(contract$full_origins, collapse = ";")
    plan$h1_worker_id <- seq_len(nrow(plan))
    if (nrow(plan) != 1920L) stop("V4 H1 plan cardinality failed.", call. = FALSE)
    plan_files <- app_joint_pht4_freeze_plan(root, "h1", plan)
    decision <- data.frame(status = "R3_COMPLETE_H1_PREPARED_FOR_REVIEW",
      selected_candidates = nrow(selected), high_capacity_diagnostics_advanced = 0L,
      next_workers = nrow(plan), next_launched = FALSE, protected_rows_used = 0L,
      stringsAsFactors = FALSE)
  }
  app_joint_pht4_stage_files(root, stage, scores, aggregate, selected, decision, plan_files)
}

app_joint_pht4_best_per_candidate <- function(x) {
  x <- x[app_as_bool_vec(x$hard_functional_pass_all), , drop = FALSE]
  x <- x[order(x$training_location_mae_mean, x$horizon1_location_mae_mean,
    x$recursive_location_mae_mean, x$prior_spec_id), , drop = FALSE]
  x[!duplicated(x$candidate_id), , drop = FALSE]
}

app_joint_pht4_force_exact <- function(selected, pool, n) {
  exact <- app_joint_pht4_exact_id(pool)
  if (!exact %in% selected$candidate_id) {
    anchor <- pool[pool$candidate_id == exact, , drop = FALSE]
    anchor <- anchor[order(anchor$training_location_mae_mean,
      anchor$horizon1_location_mae_mean), , drop = FALSE][1L, , drop = FALSE]
    selected <- app_bind_rows_fill(list(anchor, selected))
  }
  selected <- selected[!duplicated(selected$candidate_id), , drop = FALSE]
  head(selected, n)
}

app_joint_pht4_finalize_h1 <- function(root) {
  contract <- app_joint_pht4_read_contract(file.path(root, "frozen_v4_contract.csv"))
  scores <- app_joint_pht4_collect(root, "h1")
  aggregate <- app_joint_pht4_location_aggregate(scores, "prior_spec_id")
  selected <- head(app_joint_pht4_best_per_candidate(aggregate), contract$h1_advance_count)
  selected <- app_joint_pht4_force_exact(selected, aggregate, contract$h1_advance_count)
  registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
  candidates <- registry[match(selected$candidate_id, registry$candidate_id), , drop = FALSE]
  base_profiles <- selected[, c("candidate_id", "rhs_tau0", "prior_spec_id"), drop = FALSE]
  candidates <- merge(candidates, base_profiles, by = "candidate_id", all.y = TRUE, sort = FALSE)
  slabs <- data.frame(rhs_zeta2_profile = contract$rhs_zeta2_values,
    rhs_zeta2_fixed = suppressWarnings(as.numeric(contract$rhs_zeta2_values)),
    stringsAsFactors = FALSE)
  profiles <- merge(candidates, slabs, by = NULL)
  profiles$rhs_zeta2_fixed[profiles$rhs_zeta2_profile == "learned"] <- NA_real_
  profiles$prior_mode <- "fixed_tau0"
  profiles$prior_spec_id <- sprintf("h2_spec_%04d", seq_len(nrow(profiles)))
  fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))
  fixtures <- fixtures[fixtures$panel == "discovery", c("scenario_id", "replicate_id",
    "dgp_seed", "fixture_path"), drop = FALSE]
  plan <- merge(profiles, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan$origin_indices <- paste(contract$full_origins, collapse = ";")
  plan$h2_worker_id <- seq_len(nrow(plan))
  if (nrow(plan) != 576L) stop("V4 H2 plan cardinality failed.", call. = FALSE)
  plan_files <- app_joint_pht4_freeze_plan(root, "h2", plan)
  decision <- data.frame(status = "H1_COMPLETE_H2_PREPARED_FOR_REVIEW",
    selected_profiles = nrow(selected), next_workers = nrow(plan), next_launched = FALSE,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  app_joint_pht4_stage_files(root, "h1", scores, aggregate, selected, decision, plan_files)
}

app_joint_pht4_finalize_h2 <- function(root) {
  contract <- app_joint_pht4_read_contract(file.path(root, "frozen_v4_contract.csv"))
  scores <- app_joint_pht4_collect(root, "h2")
  aggregate <- app_joint_pht4_location_aggregate(scores, "prior_spec_id")
  selected <- head(app_joint_pht4_best_per_candidate(aggregate), contract$h2_advance_count)
  selected <- app_joint_pht4_force_exact(selected, aggregate, contract$h2_advance_count)
  registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
  candidates <- registry[match(selected$candidate_id, registry$candidate_id), , drop = FALSE]
  selected_profiles <- selected[, c("candidate_id", "rhs_tau0", "rhs_zeta2_profile",
    "rhs_zeta2_fixed", "prior_spec_id"), drop = FALSE]
  candidates <- merge(candidates, selected_profiles, by = "candidate_id", all.y = TRUE, sort = FALSE)
  profiles <- merge(candidates, data.frame(al_tau0_multiplier = contract$al_tau0_multipliers,
    stringsAsFactors = FALSE), by = NULL)
  profiles$normal_rhs_tau0 <- profiles$rhs_tau0
  profiles$rhs_tau0 <- profiles$normal_rhs_tau0 * profiles$al_tau0_multiplier
  profiles$prior_mode <- "fixed_tau0"
  profiles$quantile_spec_id <- sprintf("m1_spec_%04d", seq_len(nrow(profiles)))
  fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))
  fixtures <- fixtures[fixtures$panel == "discovery", c("scenario_id", "replicate_id",
    "dgp_seed", "fixture_path"), drop = FALSE]
  plan <- merge(profiles, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan$origin_indices <- paste(contract$full_origins, collapse = ";")
  plan$m1_worker_id <- seq_len(nrow(plan))
  if (nrow(plan) != 480L) stop("V4 M1 plan cardinality failed.", call. = FALSE)
  plan_files <- app_joint_pht4_freeze_plan(root, "m1", plan)
  decision <- data.frame(status = "H2_COMPLETE_M1_PREPARED_FOR_REVIEW",
    selected_profiles = nrow(selected), next_workers = nrow(plan), next_launched = FALSE,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  app_joint_pht4_stage_files(root, "h2", scores, aggregate, selected, decision, plan_files)
}

app_joint_pht4_quantile_aggregate <- function(scores, keys) {
  group <- interaction(scores[, keys, drop = FALSE], drop = TRUE, lex.order = TRUE)
  app_bind_rows_fill(lapply(split(scores, group), function(x) {
    meta <- x[1L, intersect(c("scenario_id", "candidate_id", "candidate_role",
      "source_candidate_id", "structural_signature", "architecture_signature", "D", "n",
      "retained_state_budget", "response_lags", "alpha", "rho", "pi_w", "pi_in",
      "input_scale", "recurrent_sparsity_mode", "rho_requested_max", "diagnostic_only",
      "joint_backend_eligible", "rhs_tau0", "normal_rhs_tau0", "rhs_zeta2_profile",
      "rhs_zeta2_fixed", "prior_spec_id", "quantile_spec_id", "al_tau0_multiplier", "tau"),
      names(x)), drop = FALSE]
    cbind(meta, data.frame(replicates = nrow(x),
      training_quantile_mae_mean = mean(x$training_quantile_mae),
      training_quantile_mae_worst = max(x$training_quantile_mae),
      training_quantile_rmse_mean = mean(x$training_quantile_rmse),
      horizon1_quantile_mae_mean = mean(x$horizon1_quantile_mae),
      horizon1_quantile_mae_worst = max(x$horizon1_quantile_mae),
      horizon1_5_quantile_mae_mean = mean(x$horizon1_5_quantile_mae),
      recursive_quantile_mae_mean = mean(x$recursive_quantile_mae),
      dgp_expected_quantile_score_mean = mean(x$dgp_expected_quantile_score),
      companion_median_fit_mae_mean = mean(x$companion_median_fit_mae),
      companion_median_horizon1_mae_mean = mean(x$companion_median_horizon1_mae),
      companion_median_recursive_mae_mean = mean(x$companion_median_recursive_mae),
      companion_median_dgp_score_mean = mean(x$companion_median_dgp_expected_quantile_score),
      hard_functional_pass_all = all(app_as_bool_vec(x$hard_functional_pass)),
      convergence_review_any = any(app_as_bool_vec(x$convergence_review_only)),
      warning_count_sum = sum(as.integer(x$warning_count)), stringsAsFactors = FALSE))
  }))
}

app_joint_pht4_force_exact_quantile <- function(selected, pool, n) {
  exact <- app_joint_pht4_exact_id(pool)
  if (!exact %in% selected$candidate_id) {
    anchor <- pool[pool$candidate_id == exact & app_as_bool_vec(pool$hard_functional_pass_all), ,
      drop = FALSE]
    anchor <- anchor[order(anchor$training_quantile_mae_mean,
      anchor$horizon1_quantile_mae_mean), , drop = FALSE][1L, , drop = FALSE]
    selected <- app_bind_rows_fill(list(anchor, selected))
  }
  selected <- selected[!duplicated(selected$candidate_id), , drop = FALSE]
  head(selected, n)
}

app_joint_pht4_finalize_m1 <- function(root) {
  contract <- app_joint_pht4_read_contract(file.path(root, "frozen_v4_contract.csv"))
  scores <- app_joint_pht4_collect(root, "m1")
  aggregate <- app_joint_pht4_quantile_aggregate(scores, c("candidate_id", "quantile_spec_id"))
  eligible <- aggregate[app_as_bool_vec(aggregate$hard_functional_pass_all), , drop = FALSE]
  eligible <- eligible[order(eligible$training_quantile_mae_mean,
    eligible$horizon1_quantile_mae_mean, eligible$recursive_quantile_mae_mean,
    eligible$dgp_expected_quantile_score_mean, eligible$quantile_spec_id), , drop = FALSE]
  best <- eligible[!duplicated(eligible$candidate_id), , drop = FALSE]
  selected <- head(best, contract$m1_advance_count)
  selected <- app_joint_pht4_force_exact_quantile(selected, aggregate, contract$m1_advance_count)
  if (nrow(selected) != contract$m1_advance_count) stop("V4 M1 shortlist is incomplete.", call. = FALSE)
  tail_fixtures <- app_joint_pht4_materialize_panel(root, "tail", contract)
  registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
  candidates <- registry[match(selected$candidate_id, registry$candidate_id), , drop = FALSE]
  profiles <- selected[, c("candidate_id", "rhs_tau0", "normal_rhs_tau0",
    "rhs_zeta2_profile", "rhs_zeta2_fixed", "prior_spec_id", "quantile_spec_id",
    "al_tau0_multiplier"), drop = FALSE]
  candidates <- merge(candidates, profiles, by = "candidate_id", all.y = TRUE, sort = FALSE)
  plan <- merge(merge(candidates, data.frame(tau = c(0.05, 0.95)), by = NULL),
    tail_fixtures[, c("scenario_id", "replicate_id", "dgp_seed", "fixture_path")],
    by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan$prior_mode <- "fixed_tau0"
  plan$origin_indices <- paste(contract$full_origins, collapse = ";")
  plan$t1_worker_id <- seq_len(nrow(plan))
  if (nrow(plan) != 120L || anyNA(plan$fixture_path)) {
    stop("V4 T1 plan cardinality failed.", call. = FALSE)
  }
  plan_files <- c(app_joint_pht4_freeze_plan(root, "t1", plan),
    tail_fixtures = app_write_csv(tail_fixtures, file.path(root, "tail_fixture_manifest.csv")))
  decision <- data.frame(status = "M1_COMPLETE_T1_PREPARED_FOR_REVIEW",
    selected_profiles = nrow(selected), next_workers = nrow(plan), next_launched = FALSE,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  app_joint_pht4_stage_files(root, "m1", scores, aggregate, selected, decision, plan_files)
}

app_joint_pht4_tail_pair_table <- function(scores) {
  aggregate <- app_joint_pht4_quantile_aggregate(scores,
    c("candidate_id", "quantile_spec_id", "tau"))
  lower <- aggregate[aggregate$tau == 0.05, , drop = FALSE]
  upper <- aggregate[aggregate$tau == 0.95, , drop = FALSE]
  keep <- c("candidate_id", "quantile_spec_id", "training_quantile_mae_mean",
    "horizon1_quantile_mae_mean", "recursive_quantile_mae_mean",
    "dgp_expected_quantile_score_mean", "companion_median_fit_mae_mean",
    "companion_median_horizon1_mae_mean", "companion_median_recursive_mae_mean",
    "companion_median_dgp_score_mean", "hard_functional_pass_all",
    "convergence_review_any")
  paired <- merge(lower[, keep, drop = FALSE], upper[, keep, drop = FALSE],
    by = c("candidate_id", "quantile_spec_id"), suffixes = c("_lower", "_upper"),
    all = TRUE, sort = FALSE)
  meta <- lower[, setdiff(names(lower), c("tau", grep("^(training|horizon|recursive|dgp|companion|hard|convergence)",
    names(lower), value = TRUE))), drop = FALSE]
  meta <- meta[!duplicated(meta[, c("candidate_id", "quantile_spec_id")]), , drop = FALSE]
  paired <- merge(meta, paired, by = c("candidate_id", "quantile_spec_id"), all.y = TRUE,
    sort = FALSE)
  weights <- app_joint_shared_weights(c(0.05, 0.50, 0.95))
  paired$median_fit_mae <- rowMeans(cbind(paired$companion_median_fit_mae_mean_lower,
    paired$companion_median_fit_mae_mean_upper))
  paired$median_horizon1_mae <- rowMeans(cbind(
    paired$companion_median_horizon1_mae_mean_lower,
    paired$companion_median_horizon1_mae_mean_upper))
  paired$median_recursive_mae <- rowMeans(cbind(
    paired$companion_median_recursive_mae_mean_lower,
    paired$companion_median_recursive_mae_mean_upper))
  paired$median_dgp_score <- rowMeans(cbind(paired$companion_median_dgp_score_mean_lower,
    paired$companion_median_dgp_score_mean_upper))
  paired$three_level_dgp_score <- weights[[1L]] * paired$dgp_expected_quantile_score_mean_lower +
    weights[[2L]] * paired$median_dgp_score +
    weights[[3L]] * paired$dgp_expected_quantile_score_mean_upper
  paired$worst_tail_fit_mae <- pmax(paired$training_quantile_mae_mean_lower,
    paired$training_quantile_mae_mean_upper)
  paired$hard_functional_pass_all <- app_as_bool_vec(paired$hard_functional_pass_all_lower) &
    app_as_bool_vec(paired$hard_functional_pass_all_upper)
  paired$convergence_review_any <- app_as_bool_vec(paired$convergence_review_any_lower) |
    app_as_bool_vec(paired$convergence_review_any_upper)
  paired
}

app_joint_pht4_apply_tail_gates <- function(paired, contract) {
  exact <- app_joint_pht4_exact_id(paired)
  anchor <- paired[paired$candidate_id == exact, , drop = FALSE]
  if (nrow(anchor) != 1L || !anchor$hard_functional_pass_all[[1L]]) {
    stop("V4 exact V2 tail anchor is unavailable.", call. = FALSE)
  }
  limit <- function(value, rel, abs) value + max(rel * abs(value), abs)
  limits <- data.frame(
    median_fit = limit(anchor$median_fit_mae, contract$median_fit_relative_margin,
      contract$median_fit_absolute_margin),
    lower_fit = limit(anchor$training_quantile_mae_mean_lower,
      contract$tail_fit_relative_margin, contract$tail_fit_absolute_margin),
    upper_fit = limit(anchor$training_quantile_mae_mean_upper,
      contract$tail_fit_relative_margin, contract$tail_fit_absolute_margin),
    median_h1 = limit(anchor$median_horizon1_mae, contract$horizon1_relative_margin,
      contract$horizon1_absolute_margin),
    lower_h1 = limit(anchor$horizon1_quantile_mae_mean_lower,
      contract$horizon1_relative_margin, contract$horizon1_absolute_margin),
    upper_h1 = limit(anchor$horizon1_quantile_mae_mean_upper,
      contract$horizon1_relative_margin, contract$horizon1_absolute_margin),
    stringsAsFactors = FALSE)
  paired$median_fit_gate <- paired$median_fit_mae <= limits$median_fit
  paired$lower_fit_gate <- paired$training_quantile_mae_mean_lower <= limits$lower_fit
  paired$upper_fit_gate <- paired$training_quantile_mae_mean_upper <= limits$upper_fit
  paired$median_h1_gate <- paired$median_horizon1_mae <= limits$median_h1
  paired$lower_h1_gate <- paired$horizon1_quantile_mae_mean_lower <= limits$lower_h1
  paired$upper_h1_gate <- paired$horizon1_quantile_mae_mean_upper <= limits$upper_h1
  paired$fit_capable <- paired$hard_functional_pass_all & paired$median_fit_gate &
    paired$lower_fit_gate & paired$upper_fit_gate & paired$median_h1_gate &
    paired$lower_h1_gate & paired$upper_h1_gate
  list(table = paired, limits = limits, exact_id = exact)
}

app_joint_pht4_finalize_t1 <- function(root) {
  contract <- app_joint_pht4_read_contract(file.path(root, "frozen_v4_contract.csv"))
  scores <- app_joint_pht4_collect(root, "t1")
  paired <- app_joint_pht4_tail_pair_table(scores)
  gated <- app_joint_pht4_apply_tail_gates(paired, contract)
  challengers <- gated$table[gated$table$fit_capable &
    gated$table$candidate_id != gated$exact_id, , drop = FALSE]
  challengers <- challengers[order(challengers$three_level_dgp_score,
    challengers$worst_tail_fit_mae, challengers$median_fit_mae,
    challengers$candidate_id), , drop = FALSE]
  selected <- head(challengers, contract$t1_advance_count)
  if (nrow(selected) != contract$t1_advance_count) {
    stop("V4 tail stage produced fewer than six fit-capable challengers.", call. = FALSE)
  }
  exact <- gated$table[gated$table$candidate_id == gated$exact_id, , drop = FALSE]
  finalists <- app_bind_rows_fill(list(selected, exact))
  finalist_path <- app_write_csv(finalists, file.path(root, "s1_frozen_finalists.csv"))
  finalist_hash <- app_sha256_file(finalist_path)
  sealed <- app_joint_pht4_materialize_panel(root, "sealed", contract)
  registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
  specs <- finalists[, c("candidate_id", "rhs_tau0", "normal_rhs_tau0",
    "rhs_zeta2_profile", "rhs_zeta2_fixed", "prior_spec_id", "quantile_spec_id",
    "al_tau0_multiplier"), drop = FALSE]
  candidates <- merge(registry, specs, by = "candidate_id", all.y = TRUE, sort = FALSE)
  candidates$qualification_role <- ifelse(candidates$candidate_id == gated$exact_id,
    "exact_v2_control", "new_challenger")
  plan <- merge(candidates, sealed[, c("scenario_id", "replicate_id", "dgp_seed",
    "fixture_path")], by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan$prior_mode <- "fixed_tau0"
  plan$origin_indices <- paste(contract$full_origins, collapse = ";")
  plan$finalists_sha256 <- finalist_hash
  plan$s1_worker_id <- seq_len(nrow(plan))
  if (nrow(plan) != 35L || anyNA(plan$fixture_path)) {
    stop("V4 S1 plan cardinality failed.", call. = FALSE)
  }
  plan_files <- c(finalists = finalist_path,
    limits = app_write_csv(gated$limits, file.path(root, "t1_fit_gate_limits.csv")),
    sealed_fixtures = app_write_csv(sealed, file.path(root, "sealed_fixture_manifest.csv")),
    app_joint_pht4_freeze_plan(root, "s1", plan))
  decision <- data.frame(status = "T1_COMPLETE_S1_PREPARED_FOR_REVIEW",
    fit_capable_challengers = nrow(challengers), frozen_challengers = nrow(selected),
    exact_controls = 1L, next_workers = nrow(plan), finalists_sha256 = finalist_hash,
    next_launched = FALSE, protected_rows_used = 0L, stringsAsFactors = FALSE)
  app_joint_pht4_stage_files(root, "t1", scores, gated$table, selected, decision, plan_files)
}

app_joint_pht4_finalize_s1 <- function(root) {
  contract <- app_joint_pht4_read_contract(file.path(root, "frozen_v4_contract.csv"))
  scores <- app_joint_pht4_collect(root, "s1")
  group <- split(scores, interaction(scores$candidate_id, drop = TRUE))
  aggregate <- app_bind_rows_fill(lapply(group, function(x) {
    meta <- x[1L, intersect(c("scenario_id", "candidate_id", "candidate_role",
      "source_candidate_id", "qualification_role", "D", "n", "response_lags", "alpha",
      "rho", "input_scale", "rhs_tau0", "rhs_zeta2_profile", "rhs_zeta2_fixed",
      "quantile_spec_id"), names(x)), drop = FALSE]
    cbind(meta, data.frame(replicates = nrow(x),
      lower_fit_mae_mean = mean(x$lower_fit_mae), median_fit_mae_mean = mean(x$median_fit_mae),
      upper_fit_mae_mean = mean(x$upper_fit_mae),
      lower_horizon1_mae_mean = mean(x$lower_horizon1_mae),
      median_horizon1_mae_mean = mean(x$median_horizon1_mae),
      upper_horizon1_mae_mean = mean(x$upper_horizon1_mae),
      lower_recursive_mae_mean = mean(x$lower_recursive_mae),
      median_recursive_mae_mean = mean(x$median_recursive_mae),
      upper_recursive_mae_mean = mean(x$upper_recursive_mae),
      dgp_integrated_three_level_score_mean = mean(x$dgp_integrated_three_level_score),
      dgp_integrated_three_level_score_sd = stats::sd(x$dgp_integrated_three_level_score),
      realized_three_level_score_mean = mean(x$realized_three_level_score),
      fixtures_favoring_vs_placeholder = 0L,
      hard_functional_pass_all = all(app_as_bool_vec(x$hard_functional_pass)),
      convergence_review_any = any(app_as_bool_vec(x$convergence_review_only)),
      contract_crossing_pairs_sum = sum(x$contract_crossing_pairs),
      stringsAsFactors = FALSE))
  }))
  exact_id <- app_joint_pht4_exact_id(aggregate)
  anchor <- aggregate[aggregate$candidate_id == exact_id, , drop = FALSE]
  challengers <- aggregate[aggregate$candidate_id != exact_id &
    app_as_bool_vec(aggregate$hard_functional_pass_all) &
    aggregate$contract_crossing_pairs_sum == 0L, , drop = FALSE]
  limit <- function(value, rel, abs) value + max(rel * abs(value), abs)
  challengers$median_fit_gate <- challengers$median_fit_mae_mean <= limit(
    anchor$median_fit_mae_mean, contract$median_fit_relative_margin,
    contract$median_fit_absolute_margin)
  challengers$lower_fit_gate <- challengers$lower_fit_mae_mean <= limit(
    anchor$lower_fit_mae_mean, contract$tail_fit_relative_margin,
    contract$tail_fit_absolute_margin)
  challengers$upper_fit_gate <- challengers$upper_fit_mae_mean <= limit(
    anchor$upper_fit_mae_mean, contract$tail_fit_relative_margin,
    contract$tail_fit_absolute_margin)
  challengers$fit_capable <- challengers$median_fit_gate & challengers$lower_fit_gate &
    challengers$upper_fit_gate
  qualified <- challengers[challengers$fit_capable, , drop = FALSE]
  qualified <- qualified[order(qualified$dgp_integrated_three_level_score_mean,
    pmax(qualified$lower_fit_mae_mean, qualified$upper_fit_mae_mean),
    qualified$median_fit_mae_mean), , drop = FALSE]
  if (nrow(qualified)) {
    best <- qualified[1L, , drop = FALSE]
    near_limit <- anchor$dgp_integrated_three_level_score_mean +
      max(contract$forecast_near_tie_absolute_margin,
        contract$forecast_near_tie_relative_margin *
          abs(anchor$dgp_integrated_three_level_score_mean))
    recommend <- best$dgp_integrated_three_level_score_mean <= near_limit &&
      (best$median_fit_mae_mean < anchor$median_fit_mae_mean ||
       best$lower_fit_mae_mean < anchor$lower_fit_mae_mean ||
       best$upper_fit_mae_mean < anchor$upper_fit_mae_mean)
  } else {
    best <- anchor
    near_limit <- anchor$dgp_integrated_three_level_score_mean
    recommend <- FALSE
  }
  decision <- data.frame(
    status = if (recommend) "S1_COMPLETE_SEVEN_LEVEL_CONTINUATION_AUTHORIZED" else
      "S1_COMPLETE_RETAIN_EXACT_V2_STOP_SEARCH",
    selected_candidate_id = best$candidate_id,
    exact_v2_candidate_id = exact_id,
    fit_capable_challengers = nrow(qualified),
    selected_dgp_score = best$dgp_integrated_three_level_score_mean,
    exact_v2_dgp_score = anchor$dgp_integrated_three_level_score_mean,
    forecast_noninferiority_limit = near_limit,
    seven_level_continuation_authorized = recommend,
    joint_exal_mcmc_launched = FALSE, article_updated = FALSE, protected_rows_used = 0L,
    stringsAsFactors = FALSE)
  selected <- best
  app_joint_pht4_stage_files(root, "s1", scores, aggregate, selected, decision)
}

app_joint_pht4_finalize_stage <- function(root, stage) {
  switch(as.character(stage),
    sentinel = {
      scores <- app_joint_pht4_collect(root, "sentinel")
      methods <- c("ridge_low", "ridge_high", "normal_rhs", "median_al", "lower_al", "upper_al")
      pass <- nrow(scores) == 6L && setequal(scores$sentinel_method, methods) &&
        all(app_as_bool_vec(scores$hard_functional_pass)) &&
        all(as.integer(scores$protected_rows_loaded) == 0L)
      if (!pass) stop("V4 sentinels failed their hard gates.", call. = FALSE)
      decision <- data.frame(status = "SENTINELS_COMPLETE_R1_AUTHORIZED",
        sentinel_workers = nrow(scores), failed = 0L, r1_launched = FALSE,
        protected_rows_used = 0L, stringsAsFactors = FALSE)
      files <- c(scores = app_write_csv(scores, file.path(root, "sentinel_scores.csv")),
        decision = app_write_csv(decision, file.path(root, "sentinel_decision.csv")),
        app_joint_sw_stage_receipts(root, "sentinel"))
      app_joint_pht4_freeze_manifest(root, files, "sentinel_manifest.csv")
      decision
    },
    r1 = app_joint_pht4_finalize_ridge(root, "r1"),
    r2 = app_joint_pht4_finalize_ridge(root, "r2"),
    r3 = app_joint_pht4_finalize_ridge(root, "r3"),
    h1 = app_joint_pht4_finalize_h1(root),
    h2 = app_joint_pht4_finalize_h2(root),
    m1 = app_joint_pht4_finalize_m1(root),
    t1 = app_joint_pht4_finalize_t1(root),
    s1 = app_joint_pht4_finalize_s1(root),
    stop("Unknown persistent-tail V4 finalization stage.", call. = FALSE))
}
