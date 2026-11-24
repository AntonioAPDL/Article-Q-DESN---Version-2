# Persistent-heavy-tail v3 discovery and sealed internal confirmation.

app_joint_pht3_contract_path <- function() {
  app_path("application/config/joint_qdesn_persistent_tail_exploration_v3_contract.csv")
}

app_joint_pht3_axes_path <- function() {
  app_path("application/config/joint_qdesn_persistent_tail_exploration_v3_axes.csv")
}

app_joint_pht3_anchor_path <- function() {
  app_path("application/config/joint_qdesn_persistent_tail_exploration_v3_anchors.csv")
}

app_joint_pht3_default_root <- function() {
  app_path("application/cache/joint_qdesn_persistent_tail_exploration_v3_20261124")
}

app_joint_pht3_value <- function(tab, name) {
  row <- tab[tab$name == name, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("V3 contract requires one '%s'.", name), call. = FALSE)
  as.character(row$value[[1L]])
}

app_joint_pht3_read_contract <- function(
  path = app_joint_pht3_contract_path(),
  base_path = app_joint_sw_contract_path()
) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("section", "name", "value", "type", "description"),
    "persistent-tail v3 contract")
  if (anyDuplicated(tab$name)) stop("V3 contract fields must be unique.", call. = FALSE)
  value <- function(name) app_joint_pht3_value(tab, name)
  numvec <- function(name) as.numeric(strsplit(value(name), ";", fixed = TRUE)[[1L]])
  intvec <- function(name) as.integer(numvec(name))
  bool <- function(name) identical(tolower(value(name)), "true")
  out <- app_joint_sw_read_contract(base_path)
  out$v3_table <- tab
  out$version <- value("contract_version")
  out$run_tag <- value("run_tag")
  out$parent_branch <- value("parent_branch")
  out$parent_head <- value("parent_head")
  out$scenario_id <- value("scenario_id")
  out$scenario_count <- 1L
  for (name in c("candidate_count", "anchor_count", "low_rho_count", "supercritical_count",
      "layered_count", "global_count", "a1_advance_count", "a2_advance_count",
      "a3_advance_count", "discovery_replicates", "confirmation_replicates",
      "discovery_seed_offset", "confirmation_seed_offset", "h1_advance_count",
      "h2_advance_count", "q1_advance_count", "q2_advance_count",
      "maximum_rhs_dimension", "maximum_joint_dense_dimension", "max_physical_workers")) {
    out[[name]] <- as.integer(value(name))
  }
  out$a1_origins <- intvec("a1_origin_indices")
  out$full_origins <- intvec("full_origin_indices")
  out$reservoir_seed_offsets <- intvec("reservoir_seed_offsets")
  out$n0_tau0_values <- numvec("n0_tau0_values")
  out$n0_calibrated_fraction <- as.numeric(value("n0_calibrated_fraction"))
  out$n0_score_relative_tolerance <- as.numeric(value("n0_score_relative_tolerance"))
  out$n0_beta_relative_tolerance <- as.numeric(value("n0_beta_relative_tolerance"))
  out$h1_fixed_tau0_values <- numvec("h1_fixed_tau0_values")
  out$h1_calibrated_fractions <- numvec("h1_calibrated_fractions")
  out$h2_zeta2_values <- strsplit(value("h2_zeta2_values"), ";", fixed = TRUE)[[1L]]
  out$q1_tau0_multipliers <- numvec("q1_tau0_multipliers")
  out$tail_tau <- numvec("tail_tau")
  out$tail_score_weights <- numvec("tail_score_weights")
  out$tau <- numvec("quantile_grid")
  out$minimum_mean_improvement <- as.numeric(value("minimum_mean_improvement"))
  out$max_state_saturation <- as.numeric(value("max_state_saturation"))
  out$initial_state_perturbation_scale <- as.numeric(value("initial_state_perturbation_scale"))
  out$max_initial_state_score_relative_change <-
    as.numeric(value("max_initial_state_score_relative_change"))
  out$protected_selection_forbidden <- bool("protected_selection_forbidden")
  out$require_nonzero_input_connections <- bool("require_nonzero_input_connections")
  out$require_nonzero_recurrent_connections <- bool("require_nonzero_recurrent_connections")
  out$require_positive_realized_radius <- bool("require_positive_realized_radius")
  out$require_finite_scores <- bool("require_finite_scores")
  out$required_hostname <- value("required_hostname")
  out$min_data_free_gib <- as.numeric(value("min_data_free_gib"))
  out$min_available_memory_gib <- as.numeric(value("min_available_memory_gib"))
  out$host_reserve_memory_gib <- as.numeric(value("host_reserve_memory_gib"))
  out$blas_threads <- as.integer(value("blas_threads"))
  out$nice_level <- as.integer(value("nice_level"))
  out$automatic_downstream_launch <- bool("automatic_downstream_launch")
  out$ordinary_promotion_dimension <- out$maximum_rhs_dimension
  out$max_readout_dimension <- out$maximum_rhs_dimension
  valid <- identical(out$version, "joint_qdesn_persistent_tail_exploration_v3") &&
    identical(out$scenario_id, "persistent_heavy_tail") &&
    out$candidate_count == sum(c(out$anchor_count, out$low_rho_count,
      out$supercritical_count, out$layered_count, out$global_count)) &&
    out$a1_advance_count > out$a2_advance_count &&
    out$a2_advance_count > out$a3_advance_count &&
    out$a3_advance_count > out$h1_advance_count &&
    out$h1_advance_count > out$h2_advance_count &&
    out$h2_advance_count > out$q1_advance_count &&
    out$q1_advance_count > out$q2_advance_count &&
    identical(out$tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)) &&
    identical(out$tail_tau, c(0.05, 0.95)) &&
    length(out$h1_fixed_tau0_values) + length(out$h1_calibrated_fractions) == 7L &&
    length(out$h2_zeta2_values) == 5L &&
    length(out$q1_tau0_multipliers) == 6L &&
    out$protected_selection_forbidden && !out$automatic_downstream_launch &&
    out$max_physical_workers <= 30L
  if (!valid) stop("Persistent-tail v3 contract is malformed.", call. = FALSE)
  out
}

app_joint_pht3_read_axes <- function(path = app_joint_pht3_axes_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("profile", "axis", "values", "role"),
    "persistent-tail v3 axes")
  get <- function(axis, numeric = FALSE) {
    row <- tab[tab$profile == "v3" & tab$axis == axis, , drop = FALSE]
    if (nrow(row) != 1L) stop(sprintf("Missing v3 axis '%s'.", axis), call. = FALSE)
    x <- strsplit(as.character(row$values[[1L]]), ";", fixed = TRUE)[[1L]]
    if (numeric) as.numeric(x) else x
  }
  out <- list(
    table = tab,
    depth = as.integer(get("depth", TRUE)),
    state_budget = as.integer(get("state_budget", TRUE)),
    width_shape = get("width_shape"),
    response_lags = as.integer(get("response_lags", TRUE)),
    exogenous_lags = as.integer(get("exogenous_lags", TRUE)),
    alpha_global_range = get("alpha_global_range", TRUE),
    alpha_low_rho_range = get("alpha_low_rho_range", TRUE),
    alpha_supercritical_range = get("alpha_supercritical_range", TRUE),
    rho_low_range = get("rho_low_range", TRUE),
    rho_ordinary_range = get("rho_ordinary_range", TRUE),
    rho_supercritical = get("rho_supercritical", TRUE),
    schedule = get("schedule"),
    input_scale = get("input_scale", TRUE),
    pi_in = get("pi_in", TRUE),
    pi_w_fixed = get("pi_w_fixed", TRUE),
    recurrent_expected_degree = get("recurrent_expected_degree", TRUE),
    minimum_layer_width = as.integer(get("minimum_generated_layer_width", TRUE))
  )
  if (max(out$alpha_global_range) >= 1 || min(out$rho_low_range) <= 0 ||
      max(out$rho_supercritical) > 1.2 || max(out$state_budget) > 80L) {
    stop("V3 axes violate reviewed bounds.", call. = FALSE)
  }
  out
}

app_joint_pht3_registry <- function(contract = app_joint_pht3_read_contract()) {
  x <- app_joint_sw_read_registry()
  x <- x[x$scenario_id == contract$scenario_id, , drop = FALSE]
  if (nrow(x) != 1L) stop("Persistent-heavy-tail registry row is missing.", call. = FALSE)
  x
}

app_joint_pht3_logit_point <- function(range, u) {
  stats::plogis(stats::qlogis(range[[1L]]) + u * diff(stats::qlogis(range)))
}

app_joint_pht3_weighted_pick <- function(values, u) {
  app_joint_sw_pick(values, min(max(as.numeric(u), 0), 1 - .Machine$double.eps))
}

app_joint_pht3_candidate_from_point <- function(H, role, axes, seed) {
  depth_pool <- switch(role,
    low_rho_high_alpha = c(1L, 1L, 1L, 1L, 2L, 2L, 3L, 4L),
    compact_supercritical = c(1L, 1L, 1L, 2L, 2L, 3L, 4L),
    heterogeneous_layered = c(2L, 2L, 2L, 3L, 3L, 4L),
    global_compact = c(1L, 1L, 2L, 2L, 3L, 4L),
    stop("Unknown v3 candidate role.", call. = FALSE))
  budget_pool <- c(8L, 12L, 16L, 20L, 20L, 24L, 24L, 32L, 40L, 48L, 64L, 80L)
  lag_pool <- c(1L, 1L, 1L, 2L, 2L, 3L, 3L, 4L, 5L, 6L, 8L, 10L, 12L,
    15L, 24L, 30L, 45L, 60L)
  D <- as.integer(app_joint_pht3_weighted_pick(depth_pool, H[[1L]]))
  budget <- as.integer(app_joint_pht3_weighted_pick(budget_pool, H[[2L]]))
  budget <- max(budget, D * axes$minimum_layer_width)
  shape <- as.character(app_joint_pht3_weighted_pick(axes$width_shape, H[[3L]]))
  widths <- app_joint_sw_widths(D, budget, shape, axes$minimum_layer_width)
  response_lags <- as.integer(app_joint_pht3_weighted_pick(lag_pool, H[[4L]]))
  alpha_range <- switch(role,
    low_rho_high_alpha = axes$alpha_low_rho_range,
    compact_supercritical = axes$alpha_supercritical_range,
    heterogeneous_layered = axes$alpha_global_range,
    global_compact = axes$alpha_global_range)
  alpha_center <- app_joint_pht3_logit_point(alpha_range, H[[5L]])
  schedule <- if (D == 1L) "flat" else
    as.character(app_joint_pht3_weighted_pick(axes$schedule, H[[7L]]))
  alpha <- app_joint_sw_schedule(alpha_center, D, schedule, 0.35 * H[[9L]],
    axes$alpha_global_range[[1L]], axes$alpha_global_range[[2L]])
  if (identical(role, "compact_supercritical")) {
    rho <- rep(as.numeric(app_joint_pht3_weighted_pick(axes$rho_supercritical, H[[6L]])), D)
  } else {
    rho_range <- if (identical(role, "low_rho_high_alpha")) axes$rho_low_range else
      axes$rho_ordinary_range
    rho_center <- rho_range[[1L]] + H[[6L]] * diff(rho_range)
    rho <- app_joint_sw_schedule(rho_center, D, schedule, 0.25 * H[[10L]],
      if (identical(role, "low_rho_high_alpha")) 0.01 else 0.05, 0.999)
  }
  input_scale <- as.numeric(app_joint_pht3_weighted_pick(axes$input_scale, H[[11L]]))
  pi_in <- rep(as.numeric(app_joint_pht3_weighted_pick(axes$pi_in, H[[12L]])), D)
  if (H[[13L]] < 0.5) {
    pi_w <- rep(as.numeric(app_joint_pht3_weighted_pick(axes$pi_w_fixed, H[[14L]])), D)
    sparsity_mode <- "fixed_probability"
  } else {
    degree <- as.numeric(app_joint_pht3_weighted_pick(axes$recurrent_expected_degree, H[[14L]]))
    pi_w <- pmin(1, degree / widths)
    sparsity_mode <- paste0("expected_degree_", format(degree, trim = TRUE))
  }
  supercritical <- any(rho >= 1)
  out <- data.frame(
    scenario_id = "persistent_heavy_tail", candidate_role = role,
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
    enforce_leaky_radius = !supercritical, stringsAsFactors = FALSE)
  out$structural_signature <- app_joint_sw_structural_signature(out)
  out$architecture_signature <- app_joint_pure_architecture_signature(out)
  out
}

app_joint_pht3_exact_anchors <- function(contract, registry,
  path = app_joint_pht3_anchor_path()) {
  tab <- app_read_csv(path)
  required <- c("source_candidate_id", "anchor_role", "D", "n", "width_shape",
    "response_lags", "alpha", "rho", "pi_w", "pi_in", "input_scale",
    "recurrent_sparsity_mode", "source_rhs_tau0")
  app_check_required_columns(tab, required, "v3 anchor registry")
  rows <- lapply(seq_len(nrow(tab)), function(ii) {
    x <- tab[ii, , drop = FALSE]
    widths <- app_joint_shared_parse_num_vec(x$n[[1L]])
    D <- as.integer(x$D[[1L]])
    rho <- app_joint_shared_parse_num_vec(x$rho[[1L]])
    supercritical <- any(rho >= 1)
    out <- data.frame(
      scenario_id = contract$scenario_id, candidate_role = x$anchor_role[[1L]],
      source_candidate_id = x$source_candidate_id[[1L]],
      feature_contract = "pure_recursive_v1", design_class = "reservoir", D = D,
      n = x$n[[1L]], n_tilde = if (D > 1L) app_joint_sw_fmt(widths[seq_len(D - 1L)]) else "",
      retained_state_budget = sum(widths), width_shape = x$width_shape[[1L]],
      state_reduction = FALSE, response_lags = as.integer(x$response_lags[[1L]]),
      exogenous_lags = 0L, alpha = x$alpha[[1L]], rho = x$rho[[1L]],
      pi_w = x$pi_w[[1L]], pi_in = x$pi_in[[1L]],
      input_scale = as.numeric(x$input_scale[[1L]]),
      recurrent_sparsity_mode = x$recurrent_sparsity_mode[[1L]],
      reservoir_seed = as.integer(registry$canonical_reservoir_seed[[1L]]),
      raw_inputs_in_readout = FALSE, full_states_all_layers = TRUE,
      source_rhs_tau0 = as.numeric(x$source_rhs_tau0[[1L]]),
      rho_requested_max = max(rho),
      rho_regime = if (supercritical) "supercritical_opt_in" else "standard_subcritical",
      allow_supercritical_rho = supercritical, rho_upper_bound = 1.2,
      enforce_leaky_radius = !supercritical, stringsAsFactors = FALSE)
    out$structural_signature <- app_joint_sw_structural_signature(out)
    out$architecture_signature <- app_joint_pure_architecture_signature(out)
    out
  })
  out <- app_bind_rows_fill(rows)
  if (nrow(out) != 5L || anyDuplicated(out$source_candidate_id) ||
      any(out$retained_state_budget > 80L)) stop("V3 exact anchors are malformed.", call. = FALSE)
  out
}

app_joint_pht3_candidate_registry <- function(
  contract = app_joint_pht3_read_contract(),
  axes = app_joint_pht3_read_axes(),
  registry = app_joint_pht3_registry(contract)
) {
  seed <- as.integer(registry$canonical_reservoir_seed[[1L]])
  exact <- app_joint_pht3_exact_anchors(contract, registry)
  make_pool <- function(n, skip, role) {
    H <- app_joint_sw_halton(n, 14L, skip)
    app_bind_rows_fill(lapply(seq_len(n), function(ii) {
      app_joint_pht3_candidate_from_point(H[ii, ], role, axes, seed)
    }))
  }
  derived <- app_bind_rows_fill(list(
    make_pool(60L, 7100L, "low_rho_high_alpha"),
    make_pool(60L, 8100L, "compact_supercritical")))
  derived$candidate_role <- "anchor_derived"
  anchors <- app_bind_rows_fill(list(exact,
    app_joint_sw_take_unique(derived, contract$anchor_count - nrow(exact),
      exact$structural_signature)))
  used <- anchors$structural_signature
  low <- app_joint_sw_take_unique(
    make_pool(3L * contract$low_rho_count, 12000L, "low_rho_high_alpha"),
    contract$low_rho_count, used)
  used <- c(used, low$structural_signature)
  supercritical <- app_joint_sw_take_unique(
    make_pool(3L * contract$supercritical_count, 32000L, "compact_supercritical"),
    contract$supercritical_count, used)
  used <- c(used, supercritical$structural_signature)
  layered <- app_joint_sw_take_unique(
    make_pool(3L * contract$layered_count, 52000L, "heterogeneous_layered"),
    contract$layered_count, used)
  used <- c(used, layered$structural_signature)
  global <- app_joint_sw_take_unique(
    make_pool(3L * contract$global_count, 72000L, "global_compact"),
    contract$global_count, used)
  out <- app_bind_rows_fill(list(anchors, low, supercritical, layered, global))
  out$joint_dense_dimension <- length(contract$tau) * as.integer(out$retained_state_budget)
  out$joint_backend_eligible <- out$joint_dense_dimension <= contract$maximum_joint_dense_dimension
  out$candidate_id <- sprintf("persistent_heavy_tail__v3_%04d", seq_len(nrow(out)))
  out$execution_signature <- vapply(seq_len(nrow(out)), function(ii) {
    app_joint_qvp_sha256_text(paste(out$structural_signature[[ii]], out$reservoir_seed[[ii]],
      out$rho_regime[[ii]], out$enforce_leaky_radius[[ii]], sep = "|"))
  }, character(1L))
  role_counts <- table(out$candidate_role)
  valid <- nrow(out) == contract$candidate_count && !anyDuplicated(out$structural_signature) &&
    sum(grepl("^anchor_", out$candidate_role)) == contract$anchor_count &&
    unname(role_counts[["low_rho_high_alpha"]]) == contract$low_rho_count &&
    unname(role_counts[["compact_supercritical"]]) == contract$supercritical_count &&
    unname(role_counts[["heterogeneous_layered"]]) == contract$layered_count &&
    unname(role_counts[["global_compact"]]) == contract$global_count &&
    all(out$joint_backend_eligible) && all(out$retained_state_budget <= 80L) &&
    all(vapply(out$alpha, function(x) all(app_joint_shared_parse_num_vec(x) < 1), logical(1L)))
  if (!valid) stop("V3 candidate allocation failed.", call. = FALSE)
  out[, c("candidate_id", setdiff(names(out), "candidate_id")), drop = FALSE]
}

app_joint_pht3_prior_profiles <- function(contract) {
  fixed <- data.frame(
    prior_profile = paste0("fixed_tau0_", format(contract$h1_fixed_tau0_values,
      scientific = TRUE, trim = TRUE)),
    prior_mode = "fixed_tau0", rhs_tau0 = contract$h1_fixed_tau0_values,
    calibrated_fraction = NA_real_, stringsAsFactors = FALSE)
  calibrated <- data.frame(
    prior_profile = paste0("calibrated_fraction_", format(contract$h1_calibrated_fractions,
      scientific = FALSE, trim = TRUE)),
    prior_mode = "calibrated_fraction", rhs_tau0 = NA_real_,
    calibrated_fraction = contract$h1_calibrated_fractions, stringsAsFactors = FALSE)
  app_bind_rows_fill(list(fixed, calibrated))
}

app_joint_pht3_n0_profiles <- function(contract) {
  fixed <- data.frame(
    prior_profile = paste0("n0_fixed_", format(contract$n0_tau0_values,
      scientific = TRUE, trim = TRUE)),
    prior_mode = "fixed_tau0", rhs_tau0 = contract$n0_tau0_values,
    calibrated_fraction = NA_real_, stringsAsFactors = FALSE)
  calibrated <- data.frame(prior_profile = "n0_calibrated_fraction_0.10",
    prior_mode = "calibrated_fraction", rhs_tau0 = NA_real_,
    calibrated_fraction = contract$n0_calibrated_fraction, stringsAsFactors = FALSE)
  app_bind_rows_fill(list(fixed, calibrated))
}

app_joint_pht3_fixture_row <- function(sc, registry, contract, replicate_id, panel, root,
  materialize = identical(panel, "discovery")) {
  offset <- if (identical(panel, "discovery")) contract$discovery_seed_offset else
    contract$confirmation_seed_offset
  sc_rep <- sc
  sc_rep$seed <- as.integer(registry$selector_seed_base[[1L]]) + offset + replicate_id - 1L
  sc_rep$seed_role <- sprintf("persistent_tail_v3_%s_rep%02d", panel, replicate_id)
  if (!isTRUE(materialize)) {
    return(data.frame(scenario_id = contract$scenario_id, panel = panel,
      replicate_id = replicate_id, dgp_seed = sc_rep$seed[[1L]],
      seed_role = sc_rep$seed_role[[1L]], materialized = FALSE,
      fixture_path = NA_character_, size_bytes = NA_real_, sha256 = NA_character_,
      protected_rows_persisted = 0L, stringsAsFactors = FALSE))
  }
  fixture <- app_joint_qdesn_fixture_from_registry_row(sc_rep)
  fixture$registry_row <- sc_rep
  selector <- app_joint_pure_selector_fixture(fixture, contract)
  path <- file.path(root, "fixtures", sprintf("%s_rep%02d.rds", panel, replicate_id))
  saveRDS(selector, path, version = 3L, compress = "xz")
  data.frame(scenario_id = contract$scenario_id, panel = panel,
    replicate_id = replicate_id, dgp_seed = sc_rep$seed[[1L]],
    seed_role = sc_rep$seed_role[[1L]], materialized = TRUE,
    fixture_path = normalizePath(path, mustWork = TRUE), size_bytes = file.info(path)$size,
    sha256 = app_sha256_file(path),
    protected_rows_persisted = selector$protected_rows_persisted, stringsAsFactors = FALSE)
}

app_joint_pht3_prepare <- function(root = app_joint_pht3_default_root()) {
  contract <- app_joint_pht3_read_contract()
  base <- app_joint_sw_read_contract()
  axes <- app_joint_pht3_read_axes()
  registry <- app_joint_pht3_registry(contract)
  derived <- app_joint_sw_derived_dgp_registry(contract, registry)
  identity <- app_joint_sw_fixture_identity_audit(contract, registry)
  root <- normalizePath(root, mustWork = FALSE)
  if (dir.exists(root) && length(list.files(root, all.files = TRUE, no.. = TRUE))) {
    stop("Refusing to overwrite a nonempty v3 campaign root.", call. = FALSE)
  }
  app_ensure_dir(root)
  app_ensure_dir(file.path(root, "fixtures"))
  candidates <- app_joint_pht3_candidate_registry(contract, axes, registry)
  sc <- derived[derived$scenario_id == contract$scenario_id, , drop = FALSE]
  discovery <- app_bind_rows_fill(lapply(seq_len(contract$discovery_replicates), function(rep) {
    app_joint_pht3_fixture_row(sc, registry, contract, rep, "discovery", root)
  }))
  confirmation <- app_bind_rows_fill(lapply(seq_len(contract$confirmation_replicates), function(rep) {
    app_joint_pht3_fixture_row(sc, registry, contract, rep, "confirmation", root)
  }))
  fixtures <- app_bind_rows_fill(list(discovery, confirmation))
  discovery_plan <- discovery[, c("scenario_id", "replicate_id", "dgp_seed", "fixture_path"),
    drop = FALSE]
  a1 <- merge(candidates, discovery_plan, by = "scenario_id", all.x = TRUE, sort = FALSE)
  a1$origin_indices <- paste(contract$a1_origins, collapse = ";")
  a1$a1_worker_id <- seq_len(nrow(a1))
  exact <- candidates[!is.na(candidates$source_candidate_id), , drop = FALSE]
  n0 <- merge(merge(exact, app_joint_pht3_n0_profiles(contract), by = NULL),
    discovery_plan, by = "scenario_id", all.x = TRUE, sort = FALSE)
  n0$rhs_zeta2_fixed <- NA_real_
  n0$origin_indices <- paste(contract$full_origins, collapse = ";")
  n0$n0_worker_id <- seq_len(nrow(n0))
  app_ensure_dir(file.path(root, "n0_workers"))
  app_ensure_dir(file.path(root, "a1_workers"))
  files <- c(
    frozen_contract = app_write_csv(base$table, file.path(root, "frozen_contract.csv")),
    frozen_v3_contract = app_write_csv(contract$v3_table, file.path(root, "frozen_v3_contract.csv")),
    frozen_v3_axes = app_write_csv(axes$table, file.path(root, "frozen_v3_axes.csv")),
    frozen_registry = app_write_csv(registry, file.path(root, "frozen_registry.csv")),
    derived_dgp_registry = app_write_csv(derived, file.path(root, "derived_dgp_registry.csv")),
    protected_identity_audit = app_write_csv(identity, file.path(root, "protected_identity_audit.csv")),
    candidate_registry = app_write_csv(candidates, file.path(root, "candidate_registry.csv")),
    fixture_manifest = app_write_csv(fixtures, file.path(root, "fixture_manifest.csv")),
    n0_plan = app_write_csv(n0, file.path(root, "n0_worker_plan.csv")),
    a1_plan = app_write_csv(a1, file.path(root, "a1_worker_plan.csv")),
    source_git_state = app_write_csv(app_joint_shared_git_state(), file.path(root, "source_git_state.csv")))
  expected <- data.frame(
    scenarios = 1L, candidates = nrow(candidates), discovery_fixtures = nrow(discovery),
    sealed_confirmation_fixtures = nrow(confirmation), n0_workers = nrow(n0),
    a1_workers = nrow(a1), expected_a2_workers = contract$a1_advance_count * 3L,
    expected_a3_workers = contract$a2_advance_count * 3L * 3L,
    expected_h1_workers = contract$a3_advance_count * 7L * 3L,
    expected_h2_workers = contract$h1_advance_count * 5L * 3L,
    expected_m1_workers = contract$h2_advance_count * 6L * 3L,
    expected_t1_workers = contract$q1_advance_count * 2L * 3L,
    expected_q3_workers = (contract$q2_advance_count + 2L) * 3L,
    expected_q3_component_fits = (contract$q2_advance_count + 2L) * 3L * length(contract$tau),
    protected_rows_used_for_selection = 0L, stringsAsFactors = FALSE)
  readiness <- data.frame(
    status = "V3_PREPARED_NOT_LAUNCHED_N0_REVIEW_REQUIRED",
    required_hostname = contract$required_hostname,
    maximum_physical_workers = contract$max_physical_workers,
    downstream_auto_launch = FALSE,
    confirmation_materialized = any(app_as_bool_vec(confirmation$materialized)),
    protected_identity_verified = all(identity$verified), stringsAsFactors = FALSE)
  files <- c(files,
    expected_work = app_write_csv(expected, file.path(root, "expected_work.csv")),
    launch_readiness = app_write_csv(readiness, file.path(root, "launch_readiness.csv")))
  app_joint_shared_write_manifest(root, files, filename = "preparation_manifest.csv")
  verified <- app_joint_shared_verify_manifest(root, file.path(root, "preparation_manifest.csv"))
  if (!all(verified$verified) || nrow(n0) != 90L || nrow(a1) != 12288L ||
      any(discovery$protected_rows_persisted != 0L) || any(app_as_bool_vec(confirmation$materialized))) {
    stop("V3 preparation verification failed.", call. = FALSE)
  }
  app_write_csv(verified, file.path(root, "preparation_manifest_verification.csv"))
  list(root = root, expected = expected, readiness = readiness)
}

app_joint_pht3_stage_spec <- function(stage) {
  switch(as.character(stage),
    n0 = c(plan = "n0_worker_plan.csv", id = "n0_worker_id"),
    a1 = c(plan = "a1_worker_plan.csv", id = "a1_worker_id"),
    a2 = c(plan = "a2_worker_plan.csv", id = "a2_worker_id"),
    a3 = c(plan = "a3_worker_plan.csv", id = "a3_worker_id"),
    h1 = c(plan = "h1_worker_plan.csv", id = "h1_worker_id"),
    h2 = c(plan = "h2_worker_plan.csv", id = "h2_worker_id"),
    m1 = c(plan = "median_al_worker_plan.csv", id = "median_worker_id"),
    t1 = c(plan = "tail_al_worker_plan.csv", id = "tail_worker_id"),
    q3 = c(plan = "sealed_full7_worker_plan.csv", id = "q3_worker_id"),
    stop("Unknown persistent-tail v3 stage.", call. = FALSE))
}

app_joint_pht3_worker_dir <- function(root, stage, id) {
  file.path(root, paste0(stage, "_workers"), sprintf("worker_%05d", as.integer(id)))
}

app_joint_pht3_health <- function(root, stage) {
  spec <- app_joint_pht3_stage_spec(stage)
  path <- file.path(root, spec[["plan"]])
  if (!file.exists(path)) return(data.frame(stage = stage, expected = 0L, completed = 0L,
    failed = 0L, remaining = 0L, completion_fraction = 0, status = "not_prepared"))
  plan <- app_read_csv(path)
  dirs <- vapply(plan[[spec[["id"]]]], function(id) app_joint_pht3_worker_dir(root, stage, id),
    character(1L))
  done <- file.exists(file.path(dirs, "DONE")) & file.exists(file.path(dirs, "artifact_manifest.csv"))
  failed <- file.exists(file.path(dirs, "FAILED")) | file.exists(file.path(dirs, "failure.csv"))
  data.frame(stage = stage, expected = nrow(plan), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), completion_fraction = mean(done),
    status = if (any(failed)) "failed" else if (all(done)) "complete" else if (any(done)) "running" else "ready",
    stringsAsFactors = FALSE)
}

app_joint_pht3_collect <- function(root, stage) {
  health <- app_joint_pht3_health(root, stage)
  if (health$failed[[1L]] != 0L || health$completed[[1L]] != health$expected[[1L]]) {
    stop(sprintf("V3 stage %s is not complete and failure-free.", stage), call. = FALSE)
  }
  files <- list.files(file.path(root, paste0(stage, "_workers")), pattern = "^summary[.]csv$",
    recursive = TRUE, full.names = TRUE)
  out <- app_bind_rows_fill(lapply(files, app_read_csv))
  if (nrow(out) != health$expected[[1L]] || any(out$status != "completed")) {
    stop(sprintf("V3 stage %s summary collection failed.", stage), call. = FALSE)
  }
  out
}

app_joint_pht3_reservoir_diagnostics <- function(design) {
  base <- app_joint_pht_reservoir_diagnostics(design)
  W_nnz <- vapply(design$reservoir$W, function(x) sum(abs(x) > 0), integer(1L))
  Win_nnz <- vapply(design$reservoir$Win, function(x) sum(abs(x) > 0), integer(1L))
  W_rows <- vapply(design$reservoir$W, function(x) sum(rowSums(abs(x) > 0) > 0), integer(1L))
  Win_rows <- vapply(design$reservoir$Win, function(x) sum(rowSums(abs(x) > 0) > 0), integer(1L))
  cbind(base, data.frame(
    recurrent_nonzero_connections = sum(W_nnz), input_nonzero_connections = sum(Win_nnz),
    recurrent_connected_rows = sum(W_rows), input_connected_rows = sum(Win_rows),
    realized_connectivity_pass = all(W_nnz > 0) && all(Win_nnz > 0) &&
      all(base$realized_layer_spectral_radii != "") &&
      base$realized_max_layer_spectral_radius[[1L]] > 0,
    stringsAsFactors = FALSE))
}

app_joint_pht3_freeze_manifest <- function(root, files, filename) {
  path <- app_joint_shared_write_manifest(root, files, filename = filename)
  verified <- app_joint_shared_verify_manifest(root, path)
  if (!all(verified$verified)) stop(sprintf("V3 manifest failed: %s", filename), call. = FALSE)
  app_write_csv(verified, file.path(root, sub("[.]csv$", "_verification.csv", filename)))
  path
}

app_joint_pht3_effective_tau0 <- function(candidate, ridge, p_penalized, n_fit) {
  mode <- as.character(candidate$prior_mode[[1L]] %||% "fixed_tau0")
  if (identical(mode, "fixed_tau0")) {
    tau0 <- as.numeric(candidate$rhs_tau0[[1L]])
  } else if (identical(mode, "calibrated_fraction")) {
    fraction <- as.numeric(candidate$calibrated_fraction[[1L]])
    m0 <- max(1, min(p_penalized - 1, fraction * p_penalized))
    tau0 <- app_rhs_reference_tau0(m0 = m0, r = p_penalized,
      n_fit = n_fit, sigma_ref = sqrt(as.numeric(ridge$sigma2_mean)))
  } else {
    stop(sprintf("Unknown v3 prior mode: %s", mode), call. = FALSE)
  }
  if (!is.finite(tau0) || tau0 <= 0) stop("V3 effective tau0 is invalid.", call. = FALSE)
  tau0
}

app_joint_pht3_zeta2_fixed <- function(candidate) {
  value <- suppressWarnings(as.numeric(candidate$rhs_zeta2_fixed[[1L]] %||% NA_real_))
  if (is.finite(value) && value > 0) value else NULL
}

app_joint_pht3_score_rhs <- function(fixture, candidate, contract, origin_indices) {
  total_started <- proc.time()[[3L]]
  design <- app_joint_pure_build_design(fixture, candidate, contract, selector = TRUE)
  tr <- design$train_local
  if (ncol(design$X) - 1L > contract$ordinary_promotion_dimension) {
    stop("V3 RHS candidate exceeds the frozen dimension ceiling.", call. = FALSE)
  }
  backend <- if (ncol(design$X) >= length(tr)) "dual" else "primal"
  ridge <- app_joint_ridge_fit_dispatch(
    design$X[tr, , drop = FALSE], design$y[tr],
    ridge_tau2 = contract$ridge_tau2, intercept_var = contract$intercept_variance,
    sigma_a = contract$sigma_shape, sigma_b = contract$sigma_rate, backend = backend)
  tau0 <- app_joint_pht3_effective_tau0(candidate, ridge,
    p_penalized = ncol(design$X) - 1L, n_fit = length(tr))
  zeta2_fixed <- app_joint_pht3_zeta2_fixed(candidate)
  warm <- app_joint_shared_ridge_warm_start(ridge, candidate, design)
  fit_started <- proc.time()[[3L]]
  fit <- app_glofas_normal_rhs_fit(
    design$X[tr, , drop = FALSE], design$y[tr], warm,
    tau0 = tau0, zeta2_fixed = zeta2_fixed,
    max_iter = contract$rhs_max_iter, min_iter = contract$rhs_min_iter,
    tol = contract$rhs_tolerance)
  fit_seconds <- proc.time()[[3L]] - fit_started
  pred <- app_joint_sw_recursive_gaussian(design, fixture, fit, contract, origin_indices)
  score <- app_joint_shared_acrps(design$y[pred$score_local], pred$qhat, design$tau)
  oracle <- pred$qhat - design$true_q[pred$score_local, , drop = FALSE]
  identity <- candidate
  identity$requested_rhs_tau0 <- as.numeric(candidate$rhs_tau0[[1L]] %||% NA_real_)
  identity$rhs_tau0 <- tau0
  state <- fit$rhs_state
  trace <- fit$trace
  final_elbo <- if (nrow(trace) && "normal_rhs_partial_elbo" %in% names(trace)) {
    utils::tail(trace$normal_rhs_partial_elbo, 1L)
  } else NA_real_
  summary <- cbind(identity, data.frame(
    status = "completed", method = "normal_rhs_vb", ridge_backend = backend,
    n_analysis = nrow(design$X), n_train = length(tr),
    n_calibration_scored = length(pred$score_local),
    protected_rows_loaded = design$diagnostic$protected_rows_loaded,
    n_features = ncol(design$X), effective_rank = design$diagnostic$effective_rank,
    condition_number = design$diagnostic$condition_number,
    state_saturation_fraction = design$diagnostic$state_saturation_fraction,
    recursive_state_saturation_fraction = pred$recursive_state_saturation_fraction,
    recursive_state_max_abs = pred$recursive_state_max_abs,
    recursive_state_finite = pred$recursive_state_finite,
    calibration_acrps_mean = mean(score), calibration_acrps_sd = stats::sd(score),
    calibration_exact_gaussian_crps = mean(app_glofas_normal_crps(
      design$y[pred$score_local], pred$pred_mean, pred$pred_sd)),
    calibration_mae = mean(abs(pred$pred_mean - design$y[pred$score_local])),
    calibration_rmse = sqrt(mean((pred$pred_mean - design$y[pred$score_local])^2)),
    calibration_oracle_quantile_mae = mean(abs(oracle)),
    beta_l2 = sqrt(sum(fit$beta_mean[-1L]^2)),
    beta_max_abs = max(abs(fit$beta_mean[-1L])),
    e_inv_tau2 = as.numeric(state$e_inv_tau2), e_inv_xi = as.numeric(state$e_inv_xi),
    e_inv_zeta2 = as.numeric(state$e_inv_zeta2),
    prior_precision_min = min(state$prior_precision[state$penalized]),
    prior_precision_max = max(state$prior_precision[state$penalized]),
    final_partial_elbo = as.numeric(final_elbo),
    converged = isTRUE(fit$converged),
    convergence_status = if (isTRUE(fit$converged)) "pass" else "review_max_iter",
    iterations = as.integer(fit$iterations), final_delta = as.numeric(fit$final_delta),
    fit_seconds = fit_seconds, runtime_seconds = proc.time()[[3L]] - total_started,
    peak_rss_kib = app_joint_sw_vm_hwm_kib(), stringsAsFactors = FALSE))
  detail <- data.frame(full_time_index = pred$full_time_index,
    origin_index = pred$origin_index, horizon = pred$horizon,
    y = design$y[pred$score_local], pred_mean = pred$pred_mean,
    pred_sd = pred$pred_sd, realized_acrps = score, stringsAsFactors = FALSE)
  list(summary = summary, detail = detail, trace = trace, fit = fit, design = design)
}

app_joint_pht3_quantile_controls <- function(base_contract, candidate) {
  controls <- app_joint_swq_controls(base_contract)
  zeta2 <- app_joint_pht3_zeta2_fixed(candidate)
  controls$rhs_slab_fixed <- !is.null(zeta2)
  controls$rhs_slab_variance <- if (is.null(zeta2)) NA_real_ else zeta2
  controls
}

app_joint_pht3_fit_normal_initializer <- function(design, candidate, base_contract, controls) {
  tr <- design$train_local
  backend <- if (ncol(design$X) >= length(tr)) "dual" else "primal"
  ridge <- app_joint_ridge_fit_dispatch(
    design$X[tr, , drop = FALSE], design$y[tr],
    ridge_tau2 = base_contract$ridge_tau2, intercept_var = base_contract$intercept_variance,
    sigma_a = base_contract$sigma_shape, sigma_b = base_contract$sigma_rate,
    backend = backend)
  warm <- app_joint_shared_ridge_warm_start(ridge, candidate, design)
  zeta2_fixed <- app_joint_pht3_zeta2_fixed(candidate)
  rhs <- app_glofas_normal_rhs_fit(
    design$X[tr, , drop = FALSE], design$y[tr], warm,
    tau0 = as.numeric(candidate$rhs_tau0[[1L]]), zeta2_fixed = zeta2_fixed,
    max_iter = base_contract$rhs_max_iter, min_iter = base_contract$rhs_min_iter,
    tol = base_contract$rhs_tolerance)
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
  list(rhs_tau0 = rhs$rhs_tau0, rhs_converged = rhs$converged,
    rhs_iterations = rhs$iterations, rhs_final_delta = rhs$final_delta,
    rhs_trace = rhs$trace, ridge_backend = backend,
    initializer = list(beta_mean = slopes, beta_cov = slope_cov,
      alpha_mean = alpha, sigma_mean = sigma, rhs_anchor = rhs_state$anchor,
      tau = controls$tau, residual_sd = residual_sd, zeta2 = zeta2,
      alpha_prior_sd = controls$alpha_prior_sd_multiplier * residual_sd,
      source = "v3_compact_full_grid_normal_rhs_vb"))
}

app_joint_pht3_score_quantile <- function(fixture, candidate, base_contract,
  origin_indices, stage, root) {
  controls <- app_joint_pht3_quantile_controls(base_contract, candidate)
  design <- app_joint_pure_build_design(fixture, candidate, base_contract, selector = TRUE)
  started <- proc.time()[[3L]]
  if (identical(stage, "m1")) {
    normal <- app_joint_pht3_fit_normal_initializer(design, candidate, base_contract, controls)
    init <- app_joint_swq_single_init(normal, 0.5, design)
    fit <- app_joint_swq_fit_al(design, normal, controls, 0.5, init, controls$median_max_iter)
    median_fit <- fit
    tau <- 0.5
    source <- "matched_v3_normal_rhs_vb"
  } else {
    source_dir <- app_joint_pht3_worker_dir(root, "m1", candidate$m1_worker_id[[1L]])
    normal <- readRDS(file.path(source_dir, "normal_initializer.rds"))
    median_fit <- readRDS(file.path(source_dir, "fit_initializer.rds"))
    tau <- as.numeric(candidate$tau[[1L]])
    init <- median_fit
    k <- match(tau, normal$initializer$tau)
    if (is.na(k) || !tau %in% c(0.05, 0.95)) stop("V3 tail tau is invalid.", call. = FALSE)
    init$alpha_mean <- normal$initializer$alpha_mean[[k]]
    init$sigma_mean <- max(median_fit$sigma_mean[[1L]], normal$initializer$sigma_mean[[k]])
    fit <- app_joint_swq_fit_al(design, normal, controls, tau, init,
      controls$quantile_max_iter)
    source <- "v3_matched_median_and_normal_initializer"
  }
  pred <- app_joint_swq_recursive_quantile(
    design, fixture, fit, median_fit, base_contract, origin_indices)
  y <- design$y[pred$score_local]
  truth_index <- match(tau, design$tau)
  check <- app_check_loss(y, pred$qhat, tau)
  oracle <- pred$qhat - design$true_q[pred$score_local, truth_index]
  summary <- cbind(candidate, data.frame(
    status = "completed", method = "independent_al_rhs_vb",
    initialization_source = source, tau = tau,
    n_train = length(design$train_local), n_calibration_scored = length(y),
    protected_rows_loaded = design$diagnostic$protected_rows_loaded,
    calibration_median_quantile_score_mean = if (tau == 0.5) mean(2 * check) else NA_real_,
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
    peak_rss_kib = app_joint_sw_vm_hwm_kib(), stringsAsFactors = FALSE))
  detail <- data.frame(full_time_index = pred$full_time_index,
    origin_index = pred$origin_index, horizon = pred$horizon, tau = tau, y = y,
    qhat = pred$qhat, median_feedback = pred$median_qhat,
    true_quantile = design$true_q[pred$score_local, truth_index],
    check_loss = check, stringsAsFactors = FALSE)
  list(summary = summary, detail = detail,
    trace = app_joint_shared_quantile_trace_frame(fit),
    fit = app_joint_shared_quantile_compact_fit(fit),
    normal_initializer = if (stage == "m1") normal else NULL,
    design = design)
}

app_joint_pht3_fit_full7 <- function(fixture, candidate, base_contract, origin_indices) {
  started <- proc.time()[[3L]]
  controls <- app_joint_pht3_quantile_controls(base_contract, candidate)
  design <- app_joint_pure_build_design(fixture, candidate, base_contract, selector = TRUE)
  normal <- app_joint_pht3_fit_normal_initializer(design, candidate, base_contract, controls)
  order <- app_joint_swq_continuation_order()
  fits <- list()
  details <- list()
  median_fit <- NULL
  for (ii in seq_len(nrow(order))) {
    tau <- order$tau[[ii]]
    key <- sprintf("%.2f", tau)
    if (tau == 0.5) {
      init <- app_joint_swq_single_init(normal, tau, design)
      fit <- app_joint_swq_fit_al(design, normal, controls, tau, init,
        controls$median_max_iter)
      median_fit <- fit
    } else {
      parent <- fits[[sprintf("%.2f", order$parent_tau[[ii]])]]
      init <- parent
      k <- match(tau, normal$initializer$tau)
      init$alpha_mean <- normal$initializer$alpha_mean[[k]]
      init$sigma_mean <- max(parent$sigma_mean[[1L]], normal$initializer$sigma_mean[[k]])
      fit <- app_joint_swq_fit_al(design, normal, controls, tau, init,
        controls$quantile_max_iter)
    }
    fits[[key]] <- fit
    pred <- app_joint_swq_recursive_quantile(
      design, fixture, fit, median_fit, base_contract, origin_indices)
    truth_index <- match(tau, design$tau)
    details[[key]] <- data.frame(full_time_index = pred$full_time_index,
      origin_index = pred$origin_index, horizon = pred$horizon, tau = tau,
      y = design$y[pred$score_local], qhat = pred$qhat,
      true_quantile = design$true_q[pred$score_local, truth_index],
      recursive_state_saturation_fraction = pred$recursive_state_saturation_fraction,
      recursive_state_max_abs = pred$recursive_state_max_abs,
      recursive_state_finite = pred$recursive_state_finite,
      stringsAsFactors = FALSE)
  }
  ordered <- lapply(base_contract$tau, function(tau) details[[sprintf("%.2f", tau)]])
  reference <- ordered[[1L]]
  if (any(vapply(ordered, function(x) !identical(x$full_time_index,
      reference$full_time_index), logical(1L)))) {
    stop("V3 sealed seven-grid rows do not align.", call. = FALSE)
  }
  qhat <- do.call(cbind, lapply(ordered, `[[`, "qhat"))
  truth <- do.call(cbind, lapply(ordered, `[[`, "true_quantile"))
  realized <- app_joint_shared_acrps(reference$y, qhat, base_contract$tau)
  crossing <- app_joint_qdesn_apply_monotone_contract(qhat, base_contract$tau)
  summary <- cbind(candidate, data.frame(
    status = "completed", method = "independent_al_rhs_vb_full7_sealed",
    component_fits = length(fits), protected_rows_loaded = 0L,
    calibration_acrps_mean = mean(realized), calibration_acrps_sd = stats::sd(realized),
    calibration_oracle_quantile_mae = mean(abs(qhat - truth)),
    calibration_oracle_quantile_rmse = sqrt(mean((qhat - truth)^2)),
    raw_crossing_pairs = sum(crossing$raw_crossing$n_crossing_pairs),
    contract_crossing_pairs = sum(crossing$contract_crossing$n_crossing_pairs),
    all_components_converged = all(vapply(fits, function(x) isTRUE(x$converged), logical(1L))),
    recursive_state_finite = all(vapply(ordered,
      function(x) all(app_as_bool_vec(x$recursive_state_finite)), logical(1L))),
    recursive_state_saturation_fraction = max(vapply(ordered,
      function(x) max(x$recursive_state_saturation_fraction), numeric(1L))),
    recursive_state_max_abs = max(vapply(ordered,
      function(x) max(x$recursive_state_max_abs), numeric(1L))),
    runtime_seconds = proc.time()[[3L]] - started,
    peak_rss_kib = app_joint_sw_vm_hwm_kib(), stringsAsFactors = FALSE))
  detail <- data.frame(full_time_index = rep(reference$full_time_index,
      times = length(base_contract$tau)),
    origin_index = rep(reference$origin_index, times = length(base_contract$tau)),
    horizon = rep(reference$horizon, times = length(base_contract$tau)),
    tau = rep(base_contract$tau, each = nrow(reference)),
    y = rep(reference$y, times = length(base_contract$tau)),
    qhat = as.numeric(qhat), true_quantile = as.numeric(truth), stringsAsFactors = FALSE)
  list(summary = summary, detail = detail,
    fit = lapply(fits, app_joint_shared_quantile_compact_fit),
    normal_initializer = normal, design = design)
}

app_joint_pht3_run_worker <- function(root, stage, worker_id) {
  root <- normalizePath(root, mustWork = TRUE)
  spec <- app_joint_pht3_stage_spec(stage)
  plan <- app_read_csv(file.path(root, spec[["plan"]]))
  row <- plan[plan[[spec[["id"]]]] == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("V3 worker ID is not unique.", call. = FALSE)
  out <- app_joint_pht3_worker_dir(root, stage, worker_id)
  if (file.exists(file.path(out, "DONE")) && file.exists(file.path(out, "artifact_manifest.csv"))) {
    return(invisible(out))
  }
  tmp <- paste0(out, ".tmp_", Sys.getpid())
  unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  base_contract <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  v3_contract <- app_joint_pht3_read_contract(file.path(root, "frozen_v3_contract.csv"))
  fixture <- readRDS(row$fixture_path[[1L]])
  origins <- as.integer(strsplit(as.character(row$origin_indices[[1L]]), ";",
    fixed = TRUE)[[1L]])
  started <- Sys.time()
  captured <- tryCatch(app_joint_sw_capture_warnings(function() {
    if (stage %in% c("n0", "h1", "h2")) {
      app_joint_pht3_score_rhs(fixture, row, base_contract, origins)
    } else if (stage %in% c("a1", "a2", "a3")) {
      app_joint_sw_score_ridge(fixture, row, base_contract, origins)
    } else if (stage %in% c("m1", "t1")) {
      app_joint_pht3_score_quantile(fixture, row, base_contract, origins, stage, root)
    } else if (identical(stage, "q3")) {
      app_joint_pht3_fit_full7(fixture, row, base_contract, origins)
    } else stop("Unsupported v3 worker stage.", call. = FALSE)
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
  reservoir_diag <- app_joint_pht3_reservoir_diagnostics(result$design)
  result$summary <- cbind(result$summary, reservoir_diag)
  is_supercritical <- as.numeric(row$rho_requested_max[[1L]]) >= 1
  perturbation_change <- NA_real_
  perturbation_pass <- TRUE
  if (identical(stage, "a3") && is_supercritical) {
    perturbed <- app_joint_sw_recursive_gaussian(result$design, fixture, result$fit,
      base_contract, origins, state_perturbation = v3_contract$initial_state_perturbation_scale)
    perturbed_score <- mean(app_joint_shared_acrps(
      result$design$y[perturbed$score_local], perturbed$qhat, result$design$tau))
    reference_score <- as.numeric(result$summary$calibration_acrps_mean[[1L]])
    perturbation_change <- abs(perturbed_score - reference_score) /
      max(abs(reference_score), sqrt(.Machine$double.eps))
    perturbation_pass <- isTRUE(perturbed$recursive_state_finite) &&
      is.finite(perturbation_change) &&
      perturbation_change <= v3_contract$max_initial_state_score_relative_change
  }
  result$summary$initial_state_perturbation_scale <-
    if (identical(stage, "a3") && is_supercritical) {
      v3_contract$initial_state_perturbation_scale
    } else 0
  result$summary$initial_state_score_relative_change <- perturbation_change
  result$summary$initial_state_perturbation_pass <- perturbation_pass
  result$summary$screening_eligible <- app_as_bool_vec(
    result$summary$realized_connectivity_pass) && perturbation_pass &&
    isTRUE(result$summary$recursive_state_finite[[1L]] %||% TRUE) &&
    result$summary$protected_rows_loaded[[1L]] == 0L
  result$summary$warning_count <- length(captured$warnings)
  result$summary$warning_messages <- paste(captured$warnings, collapse = " | ")
  files <- c(
    summary = app_write_csv(result$summary, file.path(tmp, "summary.csv")),
    detail = app_write_csv(result$detail, file.path(tmp, "calibration_detail.csv")))
  if (!is.null(result$trace) && nrow(result$trace)) {
    files <- c(files, vb_trace = app_write_csv(result$trace, file.path(tmp, "vb_trace.csv")))
  }
  if (stage %in% c("m1", "t1", "q3")) {
    fit_path <- file.path(tmp, "fit_initializer.rds")
    saveRDS(result$fit, fit_path, version = 3L, compress = "xz")
    files <- c(files, fit_initializer = fit_path)
    if (!is.null(result$normal_initializer)) {
      normal_path <- file.path(tmp, "normal_initializer.rds")
      saveRDS(result$normal_initializer, normal_path, version = 3L, compress = "xz")
      files <- c(files, normal_initializer = normal_path)
    }
  }
  if (length(captured$warnings)) {
    files <- c(files, warnings = app_write_csv(data.frame(
      warning_index = seq_along(captured$warnings), warning_message = captured$warnings,
      stringsAsFactors = FALSE), file.path(tmp, "warnings.csv")))
  }
  app_joint_shared_write_manifest(tmp, files)
  verified <- app_joint_shared_verify_manifest(tmp, file.path(tmp, "artifact_manifest.csv"))
  if (!all(verified$verified)) stop("V3 worker manifest verification failed.", call. = FALSE)
  writeLines("completed", file.path(tmp, "DONE"))
  if (dir.exists(out)) unlink(out, recursive = TRUE, force = TRUE)
  if (!file.rename(tmp, out)) stop("Could not atomically publish v3 worker.", call. = FALSE)
  invisible(out)
}

app_joint_pht3_aggregate <- function(scores, keys) {
  out <- app_joint_pht_aggregate(scores, keys)
  group <- interaction(scores[, keys, drop = FALSE], drop = TRUE, lex.order = TRUE)
  gates <- app_bind_rows_fill(lapply(split(scores, group), function(x) {
    row <- x[1L, keys, drop = FALSE]
    cbind(row, data.frame(
      screening_eligible_all = all(app_as_bool_vec(x$screening_eligible)),
      realized_connectivity_pass_all = all(app_as_bool_vec(x$realized_connectivity_pass)),
      recurrent_nonzero_connections_min = min(x$recurrent_nonzero_connections),
      input_nonzero_connections_min = min(x$input_nonzero_connections),
      stringsAsFactors = FALSE))
  }))
  merge(out, gates, by = keys, all.x = TRUE, sort = FALSE)
}

app_joint_pht3_eligible <- function(x, contract, require_joint = FALSE) {
  defaults <- list(max_recursive_state_saturation = NA_real_, recursive_state_finite_all = NA,
    perturbation_pass_all = NA, screening_eligible_all = FALSE,
    realized_connectivity_pass_all = FALSE, joint_backend_eligible = TRUE)
  for (name in names(defaults)) if (!name %in% names(x)) x[[name]] <- defaults[[name]]
  keep <- x$finite_fraction == 1 & x$protected_rows_loaded_max == 0L &
    is.finite(x$calibration_acrps_mean) & app_as_bool_vec(x$screening_eligible_all) &
    app_as_bool_vec(x$realized_connectivity_pass_all) &
    (is.na(x$max_state_saturation) | x$max_state_saturation <= contract$max_state_saturation) &
    (is.na(x$max_recursive_state_saturation) |
      x$max_recursive_state_saturation <= contract$max_state_saturation) &
    (is.na(x$recursive_state_finite_all) | app_as_bool_vec(x$recursive_state_finite_all)) &
    (is.na(x$perturbation_pass_all) | app_as_bool_vec(x$perturbation_pass_all))
  if (require_joint) keep <- keep & app_as_bool_vec(x$joint_backend_eligible)
  x[keep, , drop = FALSE]
}

app_joint_pht3_has_source_id <- function(x) {
  !is.na(x) & nzchar(trimws(as.character(x)))
}

app_joint_pht3_select_architectures <- function(x, n, stage, contract) {
  all_x <- x
  x <- app_joint_pht3_eligible(all_x, contract, require_joint = identical(stage, "a3"))
  order_rows <- function(z) z[order(z$calibration_acrps_mean,
    z$calibration_acrps_worst, z$calibration_acrps_sd,
    z$retained_state_budget, z$candidate_id), , drop = FALSE]
  x <- order_rows(x)
  exact <- order_rows(all_x[app_joint_pht3_has_source_id(all_x$source_candidate_id) &
    all_x$finite_fraction == 1 & all_x$protected_rows_loaded_max == 0L &
    is.finite(all_x$calibration_acrps_mean) &
    app_as_bool_vec(all_x$recursive_state_finite_all), , drop = FALSE])
  exact$selection_eligibility <- ifelse(exact$candidate_id %in% x$candidate_id,
    "eligible", "reference_control_only")
  x$selection_eligibility <- "eligible"
  quota <- switch(stage,
    a1 = c(low_rho_high_alpha = 384L, compact_supercritical = 256L,
      heterogeneous_layered = 192L, global_compact = 96L),
    a2 = c(low_rho_high_alpha = 48L, compact_supercritical = 32L,
      heterogeneous_layered = 24L, global_compact = 12L),
    a3 = c(low_rho_high_alpha = 24L, compact_supercritical = 16L,
      heterogeneous_layered = 12L, global_compact = 6L),
    stop("Unknown v3 selection stage.", call. = FALSE))
  selected <- exact
  for (role in names(quota)) {
    pool <- x[x$candidate_role == role & !x$candidate_id %in% selected$candidate_id, , drop = FALSE]
    selected <- app_bind_rows_fill(list(selected, head(pool, quota[[role]])))
  }
  fill <- x[!x$candidate_id %in% selected$candidate_id, , drop = FALSE]
  selected <- head(app_bind_rows_fill(list(selected, fill)), n)
  if (nrow(selected) != n || anyDuplicated(selected$candidate_id) ||
      !all(app_joint_pht3_exact_anchors(contract,
        app_joint_pht3_registry(contract))$source_candidate_id %in%
        selected$source_candidate_id) ||
      any(selected$selection_eligibility != "eligible" &
        !app_joint_pht3_has_source_id(selected$source_candidate_id))) {
    stop(sprintf("V3 %s frontier violates cardinality or anchor preservation.", stage), call. = FALSE)
  }
  selected
}

app_joint_pht3_discovery_fixtures <- function(root) {
  x <- app_read_csv(file.path(root, "fixture_manifest.csv"))
  x <- x[x$panel == "discovery" & app_as_bool_vec(x$materialized), , drop = FALSE]
  x[, c("scenario_id", "replicate_id", "dgp_seed", "fixture_path"), drop = FALSE]
}

app_joint_pht3_write_plan <- function(root, candidates, stage, origins,
  seed_robust = FALSE) {
  fixtures <- app_joint_pht3_discovery_fixtures(root)
  if (seed_robust) {
    contract <- app_joint_pht3_read_contract(file.path(root, "frozen_v3_contract.csv"))
    candidates <- merge(candidates,
      data.frame(reservoir_seed_offset = contract$reservoir_seed_offsets), by = NULL)
    candidates$canonical_reservoir_seed <- candidates$reservoir_seed
    candidates$reservoir_seed <- candidates$canonical_reservoir_seed + candidates$reservoir_seed_offset
  }
  plan <- merge(candidates, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan$origin_indices <- paste(origins, collapse = ";")
  id <- paste0(stage, "_worker_id")
  plan[[id]] <- seq_len(nrow(plan))
  app_ensure_dir(file.path(root, paste0(stage, "_workers")))
  app_write_csv(plan, file.path(root, paste0(stage, "_worker_plan.csv")))
}

app_joint_pht3_finalize_n0 <- function(root) {
  contract <- app_joint_pht3_read_contract(file.path(root, "frozen_v3_contract.csv"))
  scores <- app_joint_pht3_collect(root, "n0")
  aggregate <- app_joint_pht3_aggregate(scores, c("scenario_id", "candidate_id", "prior_profile"))
  tiny <- scores[scores$prior_mode == "fixed_tau0" & scores$rhs_tau0 <= 1e-6, , drop = FALSE]
  checks <- app_bind_rows_fill(lapply(split(tiny, tiny$candidate_id), function(x) {
    matched <- app_bind_rows_fill(lapply(split(x, x$replicate_id), function(y) {
      data.frame(replicate_id = y$replicate_id[[1L]],
        tau0_profiles = nrow(y),
        score_relative_range = diff(range(y$calibration_acrps_mean)) /
          max(abs(mean(y$calibration_acrps_mean)), sqrt(.Machine$double.eps)),
        beta_l2_relative_range = diff(range(y$beta_l2)) /
          max(abs(mean(y$beta_l2)), sqrt(.Machine$double.eps)),
        finite_all = all(is.finite(c(y$calibration_acrps_mean, y$beta_l2,
          y$e_inv_tau2, y$e_inv_xi))), stringsAsFactors = FALSE)
    }))
    data.frame(candidate_id = x$candidate_id[[1L]],
      matched_replicates = nrow(matched),
      tau0_profiles_per_replicate_min = min(matched$tau0_profiles),
      score_relative_range = max(matched$score_relative_range),
      beta_l2_relative_range = max(matched$beta_l2_relative_range),
      finite_all = all(matched$finite_all), stringsAsFactors = FALSE)
  }))
  equivalent <- nrow(checks) == 5L && all(checks$matched_replicates ==
      contract$discovery_replicates) && all(checks$tau0_profiles_per_replicate_min == 4L) &&
    all(checks$finite_all) &&
    all(checks$score_relative_range <= contract$n0_score_relative_tolerance) &&
    all(checks$beta_l2_relative_range <= contract$n0_beta_relative_tolerance)
  profiles <- app_joint_pht3_prior_profiles(contract)
  decision <- data.frame(
    status = if (equivalent) "N0_COMPLETE_TINY_TAU_EQUIVALENT_READY_FOR_A1" else
      "N0_REVIEW_REQUIRED_TINY_TAU_NOT_EQUIVALENT",
    tiny_scale_equivalent = equivalent, profiles_frozen = nrow(profiles),
    tau0_1e20_retained_as_broad_axis = FALSE, next_stage_launched = FALSE,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  files <- c(scores = app_write_csv(scores, file.path(root, "n0_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "n0_aggregate.csv")),
    equivalence = app_write_csv(checks, file.path(root, "n0_equivalence_audit.csv")),
    profiles = app_write_csv(profiles, file.path(root, "h1_prior_profiles.csv")),
    decision = app_write_csv(decision, file.path(root, "n0_decision.csv")),
    app_joint_sw_stage_receipts(root, "n0"))
  app_joint_pht3_freeze_manifest(root, files, "n0_manifest.csv")
  decision
}

app_joint_pht3_finalize_architecture <- function(root, stage) {
  contract <- app_joint_pht3_read_contract(file.path(root, "frozen_v3_contract.csv"))
  spec <- switch(stage,
    a1 = list(n = contract$a1_advance_count, next_stage = "a2", origins = contract$full_origins,
      seed_robust = FALSE),
    a2 = list(n = contract$a2_advance_count, next_stage = "a3", origins = contract$full_origins,
      seed_robust = TRUE),
    a3 = list(n = contract$a3_advance_count, next_stage = "h1", origins = contract$full_origins,
      seed_robust = FALSE),
    stop("Invalid architecture stage.", call. = FALSE))
  scores <- app_joint_pht3_collect(root, stage)
  aggregate <- app_joint_sw_attach_candidate_metadata(root,
    app_joint_pht3_aggregate(scores, c("scenario_id", "candidate_id")))
  selected <- app_joint_pht3_select_architectures(aggregate, spec$n, stage, contract)
  registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
  candidates <- registry[registry$candidate_id %in% selected$candidate_id, , drop = FALSE]
  if (identical(stage, "a3")) {
    n0 <- app_read_csv(file.path(root, "n0_decision.csv"))
    if (!isTRUE(app_as_bool_vec(n0$tiny_scale_equivalent)[[1L]])) {
      stop("A3 cannot prepare H1 until N0 identifies a stable tiny-scale equivalence class.",
        call. = FALSE)
    }
    profiles <- app_read_csv(file.path(root, "h1_prior_profiles.csv"))
    candidates <- merge(candidates, profiles, by = NULL)
    next_path <- app_joint_pht3_write_plan(root, candidates, "h1", contract$full_origins)
  } else {
    next_path <- app_joint_pht3_write_plan(root, candidates, spec$next_stage,
      spec$origins, spec$seed_robust)
  }
  decision <- data.frame(stage = stage,
    status = paste0(toupper(stage), "_COMPLETE_READY_FOR_", toupper(spec$next_stage), "_REVIEW"),
    selected = nrow(selected), next_stage_launched = FALSE,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  files <- c(scores = app_write_csv(scores, file.path(root, paste0(stage, "_scores.csv"))),
    aggregate = app_write_csv(aggregate, file.path(root, paste0(stage, "_aggregate.csv"))),
    frontier = app_write_csv(selected, file.path(root, paste0(stage, "_frontier.csv"))),
    next_plan = next_path,
    decision = app_write_csv(decision, file.path(root, paste0(stage, "_decision.csv"))),
    app_joint_sw_stage_receipts(root, stage))
  app_joint_pht3_freeze_manifest(root, files, paste0(stage, "_manifest.csv"))
  decision
}

app_joint_pht3_exact_source_ids <- function(root) {
  x <- app_read_csv(file.path(root, "candidate_registry.csv"))
  as.character(x$source_candidate_id[app_joint_pht3_has_source_id(x$source_candidate_id)])
}

app_joint_pht3_rank_distinct_profiles <- function(x, n, score,
  root, preserve_all_anchors = FALSE) {
  if (!score %in% names(x)) stop("V3 profile score column is absent.", call. = FALSE)
  all_x <- x[is.finite(x[[score]]) & x$finite_fraction == 1 &
    x$protected_rows_loaded_max == 0L &
    app_as_bool_vec(x$recursive_state_finite_all), , drop = FALSE]
  all_x <- all_x[order(all_x[[score]], all_x$calibration_acrps_worst,
    all_x$calibration_acrps_sd, all_x$retained_state_budget,
    all_x$candidate_id), , drop = FALSE]
  eligible <- all_x[app_as_bool_vec(all_x$screening_eligible_all), , drop = FALSE]
  eligible <- eligible[order(eligible[[score]], eligible$calibration_acrps_worst,
    eligible$calibration_acrps_sd, eligible$retained_state_budget,
    eligible$candidate_id), , drop = FALSE]
  best <- eligible[!duplicated(eligible$candidate_id), , drop = FALSE]
  preserve <- if (preserve_all_anchors) app_joint_pht3_exact_source_ids(root) else
    c("persistent_heavy_tail__targeted_0001", "persistent_heavy_tail__targeted_0209")
  controls <- all_x[all_x$source_candidate_id %in% preserve, , drop = FALSE]
  controls <- controls[!duplicated(controls$candidate_id), , drop = FALSE]
  if (nrow(controls) != length(preserve)) {
    stop("V3 profile selection lost a required exact control.", call. = FALSE)
  }
  controls$selection_eligibility <- ifelse(controls$candidate_id %in% best$candidate_id,
    "eligible", "reference_control_only")
  best$selection_eligibility <- "eligible"
  fill <- best[!best$candidate_id %in% controls$candidate_id, , drop = FALSE]
  selected <- head(app_bind_rows_fill(list(controls, fill)), n)
  if (nrow(selected) != n || anyDuplicated(selected$candidate_id)) {
    stop("V3 distinct-profile selection violated its cardinality contract.", call. = FALSE)
  }
  selected
}

app_joint_pht3_attach_plan_metadata <- function(root, aggregate, plan_file, keys) {
  plan <- app_read_csv(file.path(root, plan_file))
  metadata_names <- c(keys, setdiff(names(plan), names(aggregate)))
  metadata <- plan[!duplicated(plan[, keys, drop = FALSE]), metadata_names, drop = FALSE]
  out <- merge(metadata, aggregate, by = keys, all.y = TRUE, sort = FALSE)
  if (nrow(out) != nrow(aggregate) || anyNA(out$candidate_id)) {
    stop(sprintf("V3 metadata join failed for %s.", plan_file), call. = FALSE)
  }
  out
}

app_joint_pht3_finalize_h1 <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_pht3_read_contract(file.path(root, "frozen_v3_contract.csv"))
  scores <- app_joint_pht3_collect(root, "h1")
  aggregate <- app_joint_pht3_aggregate(scores,
    c("scenario_id", "candidate_id", "prior_profile"))
  effective <- app_bind_rows_fill(lapply(split(scores,
    interaction(scores$candidate_id, scores$prior_profile, drop = TRUE)), function(x) {
      data.frame(scenario_id = x$scenario_id[[1L]], candidate_id = x$candidate_id[[1L]],
        prior_profile = x$prior_profile[[1L]],
        effective_rhs_tau0 = exp(mean(log(as.numeric(x$rhs_tau0)))),
        effective_rhs_tau0_min = min(as.numeric(x$rhs_tau0)),
        effective_rhs_tau0_max = max(as.numeric(x$rhs_tau0)), stringsAsFactors = FALSE)
    }))
  aggregate <- merge(aggregate, effective,
    by = c("scenario_id", "candidate_id", "prior_profile"), all.x = TRUE, sort = FALSE)
  aggregate <- app_joint_pht3_attach_plan_metadata(root, aggregate,
    "h1_worker_plan.csv", c("scenario_id", "candidate_id", "prior_profile"))
  selected <- app_joint_pht3_rank_distinct_profiles(aggregate,
    contract$h1_advance_count, "calibration_acrps_mean", root)
  registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
  profiles <- app_bind_rows_fill(lapply(seq_len(nrow(selected)), function(ii) {
    app_bind_rows_fill(lapply(contract$h2_zeta2_values, function(zeta) {
      row <- registry[registry$candidate_id == selected$candidate_id[[ii]], , drop = FALSE]
      row$h1_prior_profile <- selected$prior_profile[[ii]]
      row$h1_prior_mode <- selected$prior_mode[[ii]]
      row$h1_requested_rhs_tau0 <- selected$rhs_tau0[[ii]]
      row$prior_mode <- "fixed_tau0"
      row$rhs_tau0 <- selected$effective_rhs_tau0[[ii]]
      row$calibrated_fraction <- NA_real_
      row$rhs_zeta2_profile <- zeta
      row$rhs_zeta2_fixed <- if (identical(zeta, "learned")) NA_real_ else as.numeric(zeta)
      row$prior_profile <- paste(row$h1_prior_profile, "zeta2", zeta, sep = "__")
      row$spec_id <- paste0("h2_spec_", sprintf("%03d", ii), "_",
        sprintf("%02d", match(zeta, contract$h2_zeta2_values)))
      row
    }))
  }))
  fixtures <- app_joint_pht3_discovery_fixtures(root)
  plan <- merge(profiles, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan$origin_indices <- paste(contract$full_origins, collapse = ";")
  plan$h2_worker_id <- seq_len(nrow(plan))
  if (nrow(plan) != contract$h1_advance_count * length(contract$h2_zeta2_values) *
      contract$discovery_replicates || anyNA(plan$fixture_path)) {
    stop("V3 H2 plan violates its frozen cardinality contract.", call. = FALSE)
  }
  app_ensure_dir(file.path(root, "h2_workers"))
  decision <- data.frame(status = "H1_COMPLETE_READY_FOR_H2_SLAB_REVIEW",
    selected_profiles = nrow(selected), h2_workers = nrow(plan), h2_launched = FALSE,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  files <- c(scores = app_write_csv(scores, file.path(root, "h1_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "h1_aggregate.csv")),
    selected = app_write_csv(selected, file.path(root, "h1_selected_profiles.csv")),
    h2_plan = app_write_csv(plan, file.path(root, "h2_worker_plan.csv")),
    decision = app_write_csv(decision, file.path(root, "h1_decision.csv")),
    app_joint_sw_stage_receipts(root, "h1"))
  app_joint_pht3_freeze_manifest(root, files, "h1_manifest.csv")
  decision
}

app_joint_pht3_finalize_h2 <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_pht3_read_contract(file.path(root, "frozen_v3_contract.csv"))
  scores <- app_joint_pht3_collect(root, "h2")
  aggregate <- app_joint_pht3_aggregate(scores,
    c("scenario_id", "candidate_id", "spec_id"))
  aggregate <- app_joint_pht3_attach_plan_metadata(root, aggregate,
    "h2_worker_plan.csv", c("scenario_id", "candidate_id", "spec_id"))
  selected <- app_joint_pht3_rank_distinct_profiles(aggregate,
    contract$h2_advance_count, "calibration_acrps_mean", root)
  registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
  profiles <- app_bind_rows_fill(lapply(seq_len(nrow(selected)), function(ii) {
    app_bind_rows_fill(lapply(contract$q1_tau0_multipliers, function(multiplier) {
      row <- registry[registry$candidate_id == selected$candidate_id[[ii]], , drop = FALSE]
      row$selection_spec_id <- selected$spec_id[[ii]]
      row$normal_rhs_tau0 <- selected$rhs_tau0[[ii]]
      row$rhs_zeta2_profile <- selected$rhs_zeta2_profile[[ii]]
      row$rhs_zeta2_fixed <- selected$rhs_zeta2_fixed[[ii]]
      row$q1_tau0_multiplier <- multiplier
      row$rhs_tau0 <- row$normal_rhs_tau0 * multiplier
      row$prior_mode <- "fixed_tau0"
      row$quantile_prior_profile <- paste0("tau_multiplier_",
        format(multiplier, scientific = TRUE, trim = TRUE))
      row$quantile_spec_id <- paste0("m1_spec_", sprintf("%03d", ii), "_",
        sprintf("%02d", match(multiplier, contract$q1_tau0_multipliers)))
      row
    }))
  }))
  fixtures <- app_joint_pht3_discovery_fixtures(root)
  plan <- merge(profiles, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan$median_tau <- 0.5
  plan$origin_indices <- paste(contract$full_origins, collapse = ";")
  plan$median_worker_id <- seq_len(nrow(plan))
  if (nrow(plan) != contract$h2_advance_count * length(contract$q1_tau0_multipliers) *
      contract$discovery_replicates || anyNA(plan$fixture_path)) {
    stop("V3 median plan violates its frozen cardinality contract.", call. = FALSE)
  }
  app_ensure_dir(file.path(root, "m1_workers"))
  decision <- data.frame(status = "H2_COMPLETE_READY_FOR_MEDIAN_AL_REVIEW",
    selected_profiles = nrow(selected), median_workers = nrow(plan), median_launched = FALSE,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  files <- c(scores = app_write_csv(scores, file.path(root, "h2_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "h2_aggregate.csv")),
    selected = app_write_csv(selected, file.path(root, "h2_selected_profiles.csv")),
    median_plan = app_write_csv(plan, file.path(root, "median_al_worker_plan.csv")),
    decision = app_write_csv(decision, file.path(root, "h2_decision.csv")),
    app_joint_sw_stage_receipts(root, "h2"))
  app_joint_pht3_freeze_manifest(root, files, "h2_manifest.csv")
  decision
}

app_joint_pht3_finalize_m1 <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_pht3_read_contract(file.path(root, "frozen_v3_contract.csv"))
  scores <- app_joint_pht3_collect(root, "m1")
  proxy <- scores
  proxy$calibration_acrps_mean <- proxy$calibration_median_quantile_score_mean
  aggregate <- app_joint_pht3_aggregate(proxy,
    c("scenario_id", "candidate_id", "quantile_spec_id"))
  aggregate <- app_joint_pht3_attach_plan_metadata(root, aggregate,
    "median_al_worker_plan.csv", c("scenario_id", "candidate_id", "quantile_spec_id"))
  selected <- app_joint_pht3_rank_distinct_profiles(aggregate,
    contract$q1_advance_count, "calibration_acrps_mean", root)
  plan <- app_read_csv(file.path(root, "median_al_worker_plan.csv"))
  base <- plan[plan$quantile_spec_id %in% selected$quantile_spec_id, , drop = FALSE]
  tail <- merge(base, data.frame(tau = contract$tail_tau), by = NULL)
  tail$m1_worker_id <- tail$median_worker_id
  tail$tail_worker_id <- seq_len(nrow(tail))
  if (nrow(tail) != contract$q1_advance_count * contract$discovery_replicates *
      length(contract$tail_tau) || anyNA(tail$m1_worker_id)) {
    stop("V3 tail plan violates its frozen cardinality contract.", call. = FALSE)
  }
  app_ensure_dir(file.path(root, "t1_workers"))
  decision <- data.frame(status = "M1_COMPLETE_READY_FOR_TAIL_SENTINEL_REVIEW",
    selected_profiles = nrow(selected), tail_workers = nrow(tail), tail_launched = FALSE,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  files <- c(scores = app_write_csv(scores, file.path(root, "median_al_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "median_al_aggregate.csv")),
    selected = app_write_csv(selected, file.path(root, "median_al_selected_profiles.csv")),
    tail_plan = app_write_csv(tail, file.path(root, "tail_al_worker_plan.csv")),
    decision = app_write_csv(decision, file.path(root, "median_al_decision.csv")),
    app_joint_sw_stage_receipts(root, "m1"))
  app_joint_pht3_freeze_manifest(root, files, "median_al_manifest.csv")
  decision
}

app_joint_pht3_three_level_scores <- function(median, tail, contract) {
  selected <- unique(tail$quantile_spec_id)
  all_scores <- app_bind_rows_fill(list(
    median[median$quantile_spec_id %in% selected, , drop = FALSE], tail))
  keys <- c("scenario_id", "candidate_id", "quantile_spec_id", "replicate_id")
  group <- interaction(all_scores[, keys, drop = FALSE], drop = TRUE, lex.order = TRUE)
  app_bind_rows_fill(lapply(split(all_scores, group), function(x) {
    x <- x[order(as.numeric(x$tau)), , drop = FALSE]
    if (!identical(as.numeric(x$tau), c(0.05, 0.50, 0.95))) {
      stop("V3 tail sentinel requires tau 0.05, 0.50, and 0.95.", call. = FALSE)
    }
    raw <- as.numeric(x$calibration_check_loss_mean)
    cbind(x[1L, keys, drop = FALSE], data.frame(
      lower_tail_quantile_score = 2 * raw[[1L]],
      median_quantile_score = 2 * raw[[2L]],
      upper_tail_quantile_score = 2 * raw[[3L]],
      calibration_acrps_mean = app_joint_pht_tail_sentinel_score(raw,
        contract$tail_score_weights),
      protected_rows_loaded = max(as.integer(x$protected_rows_loaded)),
      status = "completed", runtime_seconds = 0, peak_rss_kib = 0,
      screening_eligible = all(app_as_bool_vec(x$screening_eligible)),
      realized_connectivity_pass = all(app_as_bool_vec(x$realized_connectivity_pass)),
      recurrent_nonzero_connections = min(x$recurrent_nonzero_connections),
      input_nonzero_connections = min(x$input_nonzero_connections),
      stringsAsFactors = FALSE))
  }))
}

app_joint_pht3_materialize_confirmation <- function(root, contract) {
  manifest <- app_read_csv(file.path(root, "fixture_manifest.csv"))
  rows <- which(manifest$panel == "confirmation")
  if (length(rows) != contract$confirmation_replicates) {
    stop("V3 sealed fixture registry is malformed.", call. = FALSE)
  }
  if (any(app_as_bool_vec(manifest$materialized[rows]))) {
    stop("V3 confirmation fixtures were materialized before finalist freeze.", call. = FALSE)
  }
  registry <- app_read_csv(file.path(root, "frozen_registry.csv"))
  sc <- app_read_csv(file.path(root, "derived_dgp_registry.csv"))
  sc <- sc[sc$scenario_id == contract$scenario_id, , drop = FALSE]
  generated <- app_bind_rows_fill(lapply(seq_len(contract$confirmation_replicates), function(rep) {
    app_joint_pht3_fixture_row(sc, registry, contract, rep, "confirmation", root,
      materialize = TRUE)
  }))
  if (any(generated$protected_rows_persisted != 0L)) {
    stop("V3 sealed fixtures contain protected rows.", call. = FALSE)
  }
  generated
}

app_joint_pht3_reference_specs <- function(root) {
  registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
  ids <- c("persistent_heavy_tail__targeted_0001", "persistent_heavy_tail__targeted_0209")
  out <- registry[registry$source_candidate_id %in% ids, , drop = FALSE]
  out <- out[match(ids, out$source_candidate_id), , drop = FALSE]
  if (nrow(out) != 2L || anyNA(out$candidate_id)) {
    stop("V3 exact reference specifications are absent.", call. = FALSE)
  }
  out$prior_mode <- "fixed_tau0"
  out$rhs_tau0 <- out$source_rhs_tau0
  out$rhs_zeta2_profile <- "learned"
  out$rhs_zeta2_fixed <- NA_real_
  out$confirmation_role <- c("exact_authority", "exact_v2_winner")
  out$confirmation_spec_id <- c("q3_exact_authority", "q3_exact_v2_winner")
  out
}

app_joint_pht3_finalize_t1 <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_pht3_read_contract(file.path(root, "frozen_v3_contract.csv"))
  median <- app_joint_pht3_collect(root, "m1")
  tail <- app_joint_pht3_collect(root, "t1")
  replicate_scores <- app_joint_pht3_three_level_scores(median, tail, contract)
  aggregate <- app_joint_pht3_aggregate(replicate_scores,
    c("scenario_id", "candidate_id", "quantile_spec_id"))
  aggregate <- app_joint_pht3_attach_plan_metadata(root, aggregate,
    "tail_al_worker_plan.csv", c("scenario_id", "candidate_id", "quantile_spec_id"))
  excluded <- c("persistent_heavy_tail__targeted_0001", "persistent_heavy_tail__targeted_0209")
  challengers <- aggregate[!aggregate$source_candidate_id %in% excluded &
    app_as_bool_vec(aggregate$screening_eligible_all), , drop = FALSE]
  challengers <- challengers[order(challengers$calibration_acrps_mean,
    challengers$calibration_acrps_worst, challengers$calibration_acrps_sd,
    challengers$candidate_id), , drop = FALSE]
  challengers <- head(challengers[!duplicated(challengers$candidate_id), , drop = FALSE],
    contract$q2_advance_count)
  if (nrow(challengers) != contract$q2_advance_count) {
    stop("V3 tail sentinel produced too few eligible new challengers.", call. = FALSE)
  }
  keep <- app_read_csv(file.path(root, "median_al_worker_plan.csv"))
  chosen <- keep[match(challengers$quantile_spec_id, keep$quantile_spec_id), , drop = FALSE]
  registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
  fields <- c("candidate_id", "selection_spec_id", "quantile_spec_id",
    "normal_rhs_tau0", "q1_tau0_multiplier", "rhs_tau0", "prior_mode",
    "rhs_zeta2_profile", "rhs_zeta2_fixed", "quantile_prior_profile")
  challenger_specs <- merge(registry, chosen[, fields, drop = FALSE],
    by = "candidate_id", all.y = TRUE, sort = FALSE)
  challenger_specs$confirmation_role <- "new_challenger"
  challenger_specs$confirmation_spec_id <- sprintf("q3_challenger_%02d",
    seq_len(nrow(challenger_specs)))
  references <- app_joint_pht3_reference_specs(root)
  finalists <- app_bind_rows_fill(list(challenger_specs, references))
  finalists <- finalists[!duplicated(finalists$confirmation_spec_id), , drop = FALSE]
  finalist_path <- app_write_csv(finalists, file.path(root, "q3_frozen_finalists.csv"))
  finalist_hash <- app_sha256_file(finalist_path)
  sealed <- app_joint_pht3_materialize_confirmation(root, contract)
  plan <- merge(finalists, sealed[, c("scenario_id", "replicate_id", "dgp_seed", "fixture_path")],
    by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan$origin_indices <- paste(contract$full_origins, collapse = ";")
  plan$q3_worker_id <- seq_len(nrow(plan))
  plan$finalists_sha256_before_fixture_materialization <- finalist_hash
  if (nrow(plan) != (contract$q2_advance_count + 2L) * contract$confirmation_replicates ||
      anyNA(plan$fixture_path)) {
    stop("V3 sealed full-grid plan violates its cardinality contract.", call. = FALSE)
  }
  app_ensure_dir(file.path(root, "q3_workers"))
  decision <- data.frame(status = "TAIL_SENTINEL_COMPLETE_SEALED_Q3_PREPARED_FOR_REVIEW",
    new_challengers = nrow(challengers), exact_controls = nrow(references),
    q3_workers = nrow(plan), q3_component_fits = nrow(plan) * length(contract$tau),
    finalists_sha256 = finalist_hash, q3_launched = FALSE, protected_rows_used = 0L,
    stringsAsFactors = FALSE)
  files <- c(median_scores = app_write_csv(median, file.path(root, "tail_median_scores.csv")),
    tail_scores = app_write_csv(tail, file.path(root, "tail_worker_scores.csv")),
    replicate_scores = app_write_csv(replicate_scores,
      file.path(root, "tail_sentinel_score_by_replicate.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "tail_sentinel_aggregate.csv")),
    finalists = finalist_path,
    sealed_fixtures = app_write_csv(sealed, file.path(root, "sealed_fixture_manifest.csv")),
    q3_plan = app_write_csv(plan, file.path(root, "sealed_full7_worker_plan.csv")),
    decision = app_write_csv(decision, file.path(root, "tail_sentinel_decision.csv")),
    app_joint_sw_stage_receipts(root, "t1"))
  app_joint_pht3_freeze_manifest(root, files, "tail_sentinel_manifest.csv")
  decision
}

app_joint_pht3_finalize_q3 <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_pht3_read_contract(file.path(root, "frozen_v3_contract.csv"))
  scores <- app_joint_pht3_collect(root, "q3")
  aggregate <- app_joint_pht3_aggregate(scores,
    c("scenario_id", "candidate_id", "confirmation_spec_id"))
  aggregate <- app_joint_pht3_attach_plan_metadata(root, aggregate,
    "sealed_full7_worker_plan.csv", c("scenario_id", "candidate_id", "confirmation_spec_id"))
  eligible <- aggregate[app_as_bool_vec(aggregate$screening_eligible_all) &
    aggregate$finite_fraction == 1, , drop = FALSE]
  eligible <- eligible[order(eligible$calibration_acrps_mean,
    eligible$calibration_acrps_worst, eligible$calibration_acrps_sd), , drop = FALSE]
  challenger <- eligible[eligible$confirmation_role == "new_challenger", , drop = FALSE]
  controls <- aggregate[aggregate$confirmation_role %in%
      c("exact_v2_winner", "exact_authority") & aggregate$finite_fraction == 1 &
    aggregate$protected_rows_loaded_max == 0L &
    app_as_bool_vec(aggregate$recursive_state_finite_all), , drop = FALSE]
  reference <- controls[controls$confirmation_role == "exact_v2_winner", , drop = FALSE]
  authority <- controls[controls$confirmation_role == "exact_authority", , drop = FALSE]
  if (!nrow(challenger) || nrow(reference) != 1L || nrow(authority) != 1L ||
      any(as.integer(scores$contract_crossing_pairs) != 0L) ||
      any(as.integer(scores$protected_rows_loaded) != 0L)) {
    stop("V3 sealed confirmation failed its hard scientific gates.", call. = FALSE)
  }
  best <- challenger[1L, , drop = FALSE]
  improvement <- reference$calibration_acrps_mean[[1L]] -
    best$calibration_acrps_mean[[1L]]
  by_rep <- scores[, c("confirmation_spec_id", "replicate_id", "calibration_acrps_mean"),
    drop = FALSE]
  best_rep <- by_rep[by_rep$confirmation_spec_id == best$confirmation_spec_id[[1L]], ]
  ref_rep <- by_rep[by_rep$confirmation_spec_id == "q3_exact_v2_winner", ]
  matched <- merge(best_rep, ref_rep, by = "replicate_id", suffixes = c("_challenger", "_v2"))
  matched$v2_minus_challenger <- matched$calibration_acrps_mean_v2 -
    matched$calibration_acrps_mean_challenger
  recommend <- is.finite(improvement) && improvement > contract$minimum_mean_improvement
  decision <- data.frame(
    status = if (recommend) "SEALED_Q3_COMPLETE_RECOMMEND_CASE_LEVEL_CONTINUATION" else
      "SEALED_Q3_COMPLETE_RETAIN_V2_WINNER",
    best_challenger_spec_id = best$confirmation_spec_id[[1L]],
    best_challenger_candidate_id = best$candidate_id[[1L]],
    best_challenger_score = best$calibration_acrps_mean[[1L]],
    exact_v2_winner_score = reference$calibration_acrps_mean[[1L]],
    exact_authority_score = authority$calibration_acrps_mean[[1L]],
    matched_mean_improvement = improvement,
    matched_replicates_favoring_challenger = sum(matched$v2_minus_challenger > 0),
    recommend_case_level_four_model_vb_mcmc = recommend,
    downstream_launched = FALSE, protected_rows_used = 0L, stringsAsFactors = FALSE)
  files <- c(scores = app_write_csv(scores, file.path(root, "sealed_full7_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "sealed_full7_aggregate.csv")),
    matched = app_write_csv(matched, file.path(root, "sealed_full7_matched_contrast.csv")),
    decision = app_write_csv(decision, file.path(root, "sealed_full7_decision.csv")),
    app_joint_sw_stage_receipts(root, "q3"))
  app_joint_pht3_freeze_manifest(root, files, "sealed_full7_manifest.csv")
  decision
}

app_joint_pht3_finalize_stage <- function(root, stage) {
  switch(as.character(stage),
    n0 = app_joint_pht3_finalize_n0(root),
    a1 = app_joint_pht3_finalize_architecture(root, "a1"),
    a2 = app_joint_pht3_finalize_architecture(root, "a2"),
    a3 = app_joint_pht3_finalize_architecture(root, "a3"),
    h1 = app_joint_pht3_finalize_h1(root),
    h2 = app_joint_pht3_finalize_h2(root),
    m1 = app_joint_pht3_finalize_m1(root),
    t1 = app_joint_pht3_finalize_t1(root),
    q3 = app_joint_pht3_finalize_q3(root),
    stop("Unknown persistent-tail v3 finalization stage.", call. = FALSE))
}

app_joint_pht3_all_health <- function(root) {
  app_bind_rows_fill(lapply(c("n0", "a1", "a2", "a3", "h1", "h2", "m1", "t1", "q3"),
    function(stage) app_joint_pht3_health(root, stage)))
}
