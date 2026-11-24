# Persistent-heavy-tail targeted DESN and RHS screening on the stronger window.

app_joint_pht_contract_path <- function() {
  app_path("application/config/joint_qdesn_persistent_tail_targeted_contract_v1.csv")
}

app_joint_pht_axes_path <- function() {
  app_path("application/config/joint_qdesn_persistent_tail_targeted_axes_v1.csv")
}

app_joint_pht_default_root <- function() {
  app_path("application/cache/joint_qdesn_persistent_tail_targeted_screen_20261124")
}

app_joint_pht_value <- function(tab, name) {
  row <- tab[tab$name == name, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("Targeted contract requires one '%s'.", name), call. = FALSE)
  as.character(row$value[[1L]])
}

app_joint_pht_read_contract <- function(
  path = app_joint_pht_contract_path(),
  base_path = app_joint_sw_contract_path()
) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("section", "name", "value", "type", "description"),
    "persistent-tail targeted contract")
  if (anyDuplicated(tab$name)) stop("Targeted contract fields must be unique.", call. = FALSE)
  value <- function(name) app_joint_pht_value(tab, name)
  numvec <- function(name) as.numeric(strsplit(value(name), ";", fixed = TRUE)[[1L]])
  intvec <- function(name) as.integer(numvec(name))
  bool <- function(name) identical(tolower(value(name)), "true")
  out <- app_joint_sw_read_contract(base_path)
  out$target_table <- tab
  out$version <- value("contract_version")
  out$run_tag <- value("run_tag")
  out$scenario_id <- value("scenario_id")
  out$scenario_count <- 1L
  out$candidate_count <- as.integer(value("candidate_count"))
  out$anchor_count <- as.integer(value("anchor_count"))
  out$local_count <- as.integer(value("local_count"))
  out$supercritical_count <- as.integer(value("supercritical_count"))
  out$global_count <- as.integer(value("global_count"))
  out$r1a_advance_count <- as.integer(value("r1a_advance_count"))
  out$r1a_supercritical_quota <- as.integer(value("r1a_supercritical_quota"))
  out$r1b_advance_count <- as.integer(value("r1b_advance_count"))
  out$r1b_supercritical_quota <- as.integer(value("r1b_supercritical_quota"))
  out$r2_advance_count <- as.integer(value("r2_advance_count"))
  out$r2_supercritical_quota <- as.integer(value("r2_supercritical_quota"))
  out$r1a_origins <- intvec("r1a_origin_indices")
  out$full_origins <- intvec("full_origin_indices")
  out$calibration_replicates <- as.integer(value("calibration_replicates"))
  out$reservoir_seed_offsets <- intvec("reservoir_seed_offsets")
  out$rhs_tau0_grid <- numvec("coarse_tau0_grid")
  out$h1_advance_count <- as.integer(value("h1_advance_count"))
  out$local_log10_offsets <- numvec("local_log10_offsets")
  out$refinement_min_tau0 <- as.numeric(value("refinement_min_tau0"))
  out$refinement_max_tau0 <- as.numeric(value("refinement_max_tau0"))
  out$h2_advance_count <- as.integer(value("h2_advance_count"))
  out$median_tau <- as.numeric(value("median_tau"))
  out$stop_after_median <- bool("stop_after_median")
  out$ordinary_promotion_dimension <- as.integer(value("maximum_rhs_dimension"))
  out$max_readout_dimension <- out$ordinary_promotion_dimension
  out$max_state_saturation <- as.numeric(value("max_state_saturation"))
  out$protected_selection_forbidden <- bool("protected_selection_forbidden")
  out$require_finite_scores <- bool("require_finite_scores")
  out$minimum_mean_improvement <- as.numeric(value("minimum_mean_improvement"))
  out$required_hostname <- value("required_hostname")
  out$max_workers <- as.integer(value("max_physical_workers"))
  out$min_data_free_gib <- as.numeric(value("min_data_free_gib"))
  out$min_available_memory_gib <- as.numeric(value("min_available_memory_gib"))
  out$host_reserve_memory_gib <- as.numeric(value("host_reserve_memory_gib"))
  out$blas_threads <- as.integer(value("blas_threads"))
  out$nice_level <- as.integer(value("nice_level"))
  out$automatic_downstream_launch <- bool("automatic_downstream_launch")
  valid <- identical(out$version, "joint_qdesn_persistent_tail_targeted_screen_v1") &&
    identical(out$scenario_id, "persistent_heavy_tail") &&
    out$candidate_count == out$anchor_count + out$local_count +
      out$supercritical_count + out$global_count &&
    out$r1a_advance_count > out$r1b_advance_count &&
    out$r1b_advance_count > out$r2_advance_count &&
    out$r2_advance_count > out$h1_advance_count &&
    out$h1_advance_count > out$h2_advance_count &&
    all(out$r1a_origins %in% out$full_origins) &&
    length(out$reservoir_seed_offsets) == 3L &&
    out$protected_selection_forbidden && out$stop_after_median &&
    !out$automatic_downstream_launch && out$max_workers <= 30L
  if (!valid) stop("Persistent-tail targeted contract is malformed.", call. = FALSE)
  out
}

app_joint_pht_read_axes <- function(path = app_joint_pht_axes_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("profile", "axis", "values", "role"),
    "persistent-tail targeted axes")
  get <- function(axis, numeric = FALSE) {
    row <- tab[tab$profile == "targeted" & tab$axis == axis, , drop = FALSE]
    if (nrow(row) != 1L) stop(sprintf("Missing targeted axis '%s'.", axis), call. = FALSE)
    x <- strsplit(as.character(row$values[[1L]]), ";", fixed = TRUE)[[1L]]
    if (numeric) as.numeric(x) else x
  }
  out <- app_joint_sw_read_axes()
  out$table <- tab
  out$depth <- as.integer(get("depth", TRUE))
  out$state_budget <- as.integer(get("state_budget", TRUE))
  out$width_shape <- get("width_shape")
  out$response_lags <- as.integer(get("response_lags", TRUE))
  out$exogenous_lags <- as.integer(get("exogenous_lags", TRUE))
  out$alpha_range <- get("alpha_range", TRUE)
  out$rho_range <- get("rho_range", TRUE)
  out$supercritical_rho <- get("supercritical_rho", TRUE)
  out$global_schedule <- get("global_schedule")
  out$special_schedule <- get("special_schedule")
  out$input_scale <- get("input_scale", TRUE)
  out$pi_in <- get("pi_in", TRUE)
  out$pi_w_fixed <- get("pi_w_fixed", TRUE)
  out$recurrent_expected_degree <- get("recurrent_expected_degree", TRUE)
  out$minimum_layer_width <- as.integer(get("minimum_generated_layer_width", TRUE))
  out$high_capacity_budget <- integer()
  if (!identical(out$rho_range, c(0.1, 1.2)) || max(out$state_budget) > 600L ||
      any(out$supercritical_rho < 1 | out$supercritical_rho > 1.2)) {
    stop("Targeted axes violate the reviewed search boundary.", call. = FALSE)
  }
  out
}

app_joint_pht_registry <- function(contract = app_joint_pht_read_contract()) {
  x <- app_joint_sw_read_registry()
  x <- x[x$scenario_id == contract$scenario_id, , drop = FALSE]
  if (nrow(x) != 1L) stop("Persistent-tail scenario registry row is missing.", call. = FALSE)
  x
}

app_joint_pht_authority_anchor <- function(contract, registry) {
  tab <- app_read_csv(app_path("tables/joint_qdesn_corrected_v3_selected_backbones.csv"))
  row <- tab[tab$scenario_id == contract$scenario_id, , drop = FALSE]
  if (nrow(row) != 1L) stop("Corrected persistent-tail authority must be unique.", call. = FALSE)
  if (!"width_shape" %in% names(row)) row$width_shape <- "flat"
  out <- app_joint_sw_normalize_anchor(row, contract$scenario_id,
    registry$canonical_reservoir_seed[[1L]], "anchor_authoritative_v3")
  out$source_rhs_tau0 <- as.numeric(row$rhs_tau0[[1L]])
  out
}

app_joint_pht_candidate_from_point <- function(
  H, role, axes, canonical_seed, local_anchor = NULL
) {
  base_axes <- axes
  base_axes$rho_range <- c(0.10, 0.999)
  row <- app_joint_sw_candidate_from_point(
    "persistent_heavy_tail", H, role, base_axes, canonical_seed,
    local_anchor = local_anchor, high_capacity = FALSE,
    special_schedule = !identical(role, "global_targeted")
  )
  D <- as.integer(row$D[[1L]])
  if (identical(role, "supercritical_rho")) {
    rho <- rep(as.numeric(app_joint_sw_pick(axes$supercritical_rho, H[[6L]])), D)
  } else {
    center <- if (!is.null(local_anchor)) {
      mean(app_joint_shared_parse_num_vec(local_anchor$rho[[1L]])) + (H[[6L]] - 0.5) * 0.44
    } else {
      axes$rho_range[[1L]] + H[[6L]] * diff(axes$rho_range)
    }
    center <- pmin(1.2, pmax(0.10, center))
    schedule <- if (identical(role, "global_targeted")) "flat" else
      as.character(app_joint_sw_pick(axes$special_schedule, H[[8L]]))
    rho <- app_joint_sw_schedule(center, D, schedule, 0.12 * H[[10L]], 0.10, 1.20)
  }
  row$rho <- app_joint_sw_fmt(rho)
  row$rho_requested_max <- max(rho)
  row$rho_regime <- if (any(rho >= 1)) "supercritical_opt_in" else "standard_subcritical"
  row$allow_supercritical_rho <- any(rho >= 1)
  row$rho_upper_bound <- 1.2
  row$enforce_leaky_radius <- !any(rho >= 1)
  row$structural_signature <- app_joint_sw_structural_signature(row)
  row$architecture_signature <- app_joint_pure_architecture_signature(row)
  row
}

app_joint_pht_candidate_registry <- function(
  contract = app_joint_pht_read_contract(),
  axes = app_joint_pht_read_axes(),
  registry = app_joint_pht_registry(contract)
) {
  canonical_seed <- as.integer(registry$canonical_reservoir_seed[[1L]])
  authority <- app_joint_pht_authority_anchor(contract, registry)
  authority$rho_requested_max <- max(app_joint_shared_parse_num_vec(authority$rho[[1L]]))
  authority$rho_regime <- "standard_subcritical"
  authority$allow_supercritical_rho <- FALSE
  authority$rho_upper_bound <- 1.2
  authority$enforce_leaky_radius <- TRUE
  make_pool <- function(n, skip, role, anchor = NULL) {
    H <- app_joint_sw_halton(n, 14L, skip)
    app_bind_rows_fill(lapply(seq_len(n), function(ii) {
      app_joint_pht_candidate_from_point(H[ii, ], role, axes, canonical_seed, anchor)
    }))
  }
  anchor_pool <- app_bind_rows_fill(list(
    authority,
    make_pool(8L * contract$anchor_count, 6100L, "anchor_derived", authority)
  ))
  anchors <- app_joint_sw_take_unique(anchor_pool, contract$anchor_count)
  used <- anchors$structural_signature
  local <- app_joint_sw_take_unique(
    make_pool(3L * contract$local_count, 12000L, "local_authority_neighborhood", authority),
    contract$local_count, used)
  used <- c(used, local$structural_signature)
  supercritical <- app_joint_sw_take_unique(
    make_pool(3L * contract$supercritical_count, 32000L, "supercritical_rho", authority),
    contract$supercritical_count, used)
  used <- c(used, supercritical$structural_signature)
  global <- app_joint_sw_take_unique(
    make_pool(3L * contract$global_count, 52000L, "global_targeted"),
    contract$global_count, used)
  out <- app_bind_rows_fill(list(anchors, local, supercritical, global))
  out <- out[order(out$candidate_role, out$structural_signature), , drop = FALSE]
  out$candidate_id <- sprintf("persistent_heavy_tail__targeted_%04d", seq_len(nrow(out)))
  out$execution_signature <- vapply(seq_len(nrow(out)), function(ii) {
    app_joint_qvp_sha256_text(paste(out$structural_signature[[ii]], out$reservoir_seed[[ii]],
      out$rho_regime[[ii]], out$enforce_leaky_radius[[ii]], sep = "|"))
  }, character(1L))
  if (nrow(out) != contract$candidate_count || anyDuplicated(out$structural_signature) ||
      sum(out$candidate_role == "supercritical_rho") != contract$supercritical_count ||
      max(out$rho_requested_max) > 1.2 || !any(out$rho_requested_max > 1)) {
    stop("Targeted candidate allocation failed.", call. = FALSE)
  }
  out[, c("candidate_id", setdiff(names(out), "candidate_id")), drop = FALSE]
}

app_joint_pht_prepare <- function(root = app_joint_pht_default_root()) {
  target <- app_joint_pht_read_contract()
  base <- app_joint_sw_read_contract()
  axes <- app_joint_pht_read_axes()
  registry <- app_joint_pht_registry(target)
  derived <- app_joint_sw_derived_dgp_registry(target, registry)
  identity <- app_joint_sw_fixture_identity_audit(target, registry)
  root <- normalizePath(root, mustWork = FALSE)
  if (dir.exists(root) && length(list.files(root, all.files = TRUE, no.. = TRUE))) {
    stop("Refusing to overwrite a nonempty targeted campaign root.", call. = FALSE)
  }
  app_ensure_dir(root)
  app_ensure_dir(file.path(root, "fixtures"))
  app_ensure_dir(file.path(root, "r1a_workers"))
  candidates <- app_joint_pht_candidate_registry(target, axes, registry)
  fixture_rows <- list()
  sc <- derived[derived$scenario_id == target$scenario_id, , drop = FALSE]
  for (replicate_id in seq_len(target$calibration_replicates)) {
    sc_rep <- sc
    sc_rep$seed <- as.integer(registry$selector_seed_base[[1L]]) + replicate_id - 1L
    sc_rep$seed_role <- sprintf("persistent_tail_targeted_selector_rep%02d", replicate_id)
    fixture <- app_joint_qdesn_fixture_from_registry_row(sc_rep)
    fixture$registry_row <- sc_rep
    selector <- app_joint_pure_selector_fixture(fixture, target)
    path <- file.path(root, "fixtures", sprintf("persistent_heavy_tail_rep%02d.rds", replicate_id))
    saveRDS(selector, path, version = 3L, compress = "xz")
    fixture_rows[[replicate_id]] <- data.frame(
      scenario_id = target$scenario_id, replicate_id = replicate_id,
      dgp_seed = sc_rep$seed[[1L]], seed_role = sc_rep$seed_role[[1L]],
      fixture_path = normalizePath(path, mustWork = TRUE), size_bytes = file.info(path)$size,
      sha256 = app_sha256_file(path), protected_rows_persisted = selector$protected_rows_persisted,
      stringsAsFactors = FALSE)
  }
  fixtures <- app_bind_rows_fill(fixture_rows)
  rep1 <- fixtures[fixtures$replicate_id == 1L,
    c("scenario_id", "replicate_id", "dgp_seed", "fixture_path"), drop = FALSE]
  r1a <- merge(candidates, rep1, by = "scenario_id", all.x = TRUE, sort = FALSE)
  r1a$origin_indices <- paste(target$r1a_origins, collapse = ";")
  r1a$r1a_worker_id <- seq_len(nrow(r1a))
  files <- c(
    frozen_contract = app_write_csv(base$table, file.path(root, "frozen_contract.csv")),
    frozen_target_contract = app_write_csv(target$target_table, file.path(root, "frozen_target_contract.csv")),
    frozen_target_axes = app_write_csv(axes$table, file.path(root, "frozen_target_axes.csv")),
    frozen_registry = app_write_csv(registry, file.path(root, "frozen_registry.csv")),
    derived_dgp_registry = app_write_csv(derived, file.path(root, "derived_dgp_registry.csv")),
    protected_identity_audit = app_write_csv(identity, file.path(root, "protected_identity_audit.csv")),
    candidate_registry = app_write_csv(candidates, file.path(root, "candidate_registry.csv")),
    fixture_manifest = app_write_csv(fixtures, file.path(root, "fixture_manifest.csv")),
    r1a_plan = app_write_csv(r1a, file.path(root, "r1a_worker_plan.csv")),
    source_git_state = app_write_csv(app_joint_shared_git_state(), file.path(root, "source_git_state.csv"))
  )
  expected <- data.frame(
    scenarios = 1L, candidates = nrow(candidates), selector_fixtures = nrow(fixtures),
    r1a_workers = nrow(r1a), expected_r1b_workers = target$r1a_advance_count * 3L,
    expected_r2_workers = target$r1b_advance_count * 3L * 3L,
    expected_h1_workers = target$r2_advance_count * length(target$rhs_tau0_grid) * 3L,
    maximum_expected_h2_workers = target$h1_advance_count *
      (length(target$local_log10_offsets) - 1L) * 3L,
    expected_median_workers = target$h2_advance_count * 3L,
    protected_rows_used_for_selection = 0L, stringsAsFactors = FALSE)
  readiness <- data.frame(
    status = "PREPARED_NOT_LAUNCHED_JEREZ_R1A_REVIEW_REQUIRED",
    required_hostname = target$required_hostname,
    maximum_physical_workers = target$max_workers,
    min_data_free_gib = target$min_data_free_gib,
    min_available_memory_gib = target$min_available_memory_gib,
    downstream_auto_launch = FALSE, protected_identity_verified = all(identity$verified),
    stringsAsFactors = FALSE)
  files <- c(files,
    expected_work = app_write_csv(expected, file.path(root, "expected_work.csv")),
    launch_readiness = app_write_csv(readiness, file.path(root, "launch_readiness.csv")))
  app_joint_shared_write_manifest(root, files, filename = "preparation_manifest.csv")
  verified <- app_joint_shared_verify_manifest(root, file.path(root, "preparation_manifest.csv"))
  if (!all(verified$verified) || nrow(r1a) != target$candidate_count ||
      any(fixtures$protected_rows_persisted != 0L)) {
    stop("Targeted campaign preparation verification failed.", call. = FALSE)
  }
  app_write_csv(verified, file.path(root, "preparation_manifest_verification.csv"))
  list(root = root, expected = expected, readiness = readiness)
}

app_joint_pht_aggregate <- function(scores, keys) {
  out <- app_joint_sw_aggregate_scores(scores, keys)
  group <- interaction(scores[, keys, drop = FALSE], drop = TRUE, lex.order = TRUE)
  diagnostic <- app_bind_rows_fill(lapply(split(scores, group), function(x) {
    row <- x[1L, keys, drop = FALSE]
    cbind(row, data.frame(
      max_state_saturation = if ("state_saturation_fraction" %in% names(x))
        max(as.numeric(x$state_saturation_fraction), na.rm = TRUE) else NA_real_,
      protected_rows_loaded_max = max(as.integer(x$protected_rows_loaded), na.rm = TRUE),
      warning_count_total = if ("warning_count" %in% names(x))
        sum(as.integer(x$warning_count), na.rm = TRUE) else 0L,
      stringsAsFactors = FALSE))
  }))
  merge(out, diagnostic, by = keys, all.x = TRUE, sort = FALSE)
}

app_joint_pht_freeze_manifest <- function(root, files, filename) {
  path <- app_joint_shared_write_manifest(root, files, filename = filename)
  verification <- app_joint_shared_verify_manifest(root, path)
  if (!all(verification$verified)) {
    stop(sprintf("Targeted manifest verification failed: %s", filename), call. = FALSE)
  }
  app_write_csv(verification, file.path(root,
    sub("[.]csv$", "_verification.csv", filename)))
  path
}

app_joint_pht_select_candidates <- function(x, n, supercritical_quota, saturation_limit) {
  x <- x[x$finite_fraction == 1 & x$protected_rows_loaded_max == 0L &
    is.finite(x$calibration_acrps_mean) &
    (is.na(x$max_state_saturation) | x$max_state_saturation <= saturation_limit), , drop = FALSE]
  x <- x[order(x$calibration_acrps_mean, x$calibration_acrps_worst,
    x$calibration_acrps_sd, x$retained_state_budget, x$candidate_id), , drop = FALSE]
  anchors <- x[grepl("^anchor_", x$candidate_role), , drop = FALSE]
  anchors <- anchors[!duplicated(anchors$candidate_id), , drop = FALSE]
  supercritical <- x[x$rho_requested_max >= 1, , drop = FALSE]
  supercritical <- supercritical[!supercritical$candidate_id %in% anchors$candidate_id, , drop = FALSE]
  selected <- app_bind_rows_fill(list(anchors, head(supercritical, supercritical_quota)))
  diversity_pool <- x[!x$candidate_id %in% selected$candidate_id, , drop = FALSE]
  if (nrow(diversity_pool)) {
    key <- app_joint_sw_diversity_key(diversity_pool)
    diverse <- diversity_pool[!duplicated(key), , drop = FALSE]
    selected <- app_bind_rows_fill(list(selected, head(diverse, floor(n / 4L))))
  }
  fill <- x[!x$candidate_id %in% selected$candidate_id, , drop = FALSE]
  selected <- head(app_bind_rows_fill(list(selected, fill)), n)
  if (nrow(selected) != n || sum(selected$rho_requested_max >= 1) < supercritical_quota ||
      !any(grepl("anchor_authoritative_v3", selected$candidate_role))) {
    stop("Targeted frontier violates its authority or supercritical quota.", call. = FALSE)
  }
  selected
}

app_joint_pht_plan_from_candidates <- function(root, selected, stage, origins,
  seed_robust = FALSE) {
  registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
  candidates <- registry[registry$candidate_id %in% selected$candidate_id, , drop = FALSE]
  fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))[, c(
    "scenario_id", "replicate_id", "dgp_seed", "fixture_path"), drop = FALSE]
  if (seed_robust) {
    target <- app_joint_pht_read_contract(file.path(root, "frozen_target_contract.csv"))
    candidates <- merge(candidates,
      data.frame(reservoir_seed_offset = target$reservoir_seed_offsets), by = NULL)
    candidates$canonical_reservoir_seed <- candidates$reservoir_seed
    candidates$reservoir_seed <- candidates$canonical_reservoir_seed + candidates$reservoir_seed_offset
    candidates$execution_signature <- vapply(seq_len(nrow(candidates)), function(ii) {
      app_joint_qvp_sha256_text(paste(candidates$structural_signature[[ii]],
        candidates$reservoir_seed[[ii]], candidates$rho_regime[[ii]], sep = "|"))
    }, character(1L))
  }
  plan <- merge(candidates, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan$origin_indices <- paste(origins, collapse = ";")
  id <- paste0(stage, "_worker_id")
  plan[[id]] <- seq_len(nrow(plan))
  app_ensure_dir(file.path(root, paste0(stage, "_workers")))
  app_write_csv(plan, file.path(root, paste0(stage, "_worker_plan.csv")))
}

app_joint_pht_finalize_ridge <- function(root, stage) {
  root <- normalizePath(root, mustWork = TRUE)
  target <- app_joint_pht_read_contract(file.path(root, "frozen_target_contract.csv"))
  spec <- switch(stage,
    r1a = list(n = target$r1a_advance_count, super = target$r1a_supercritical_quota,
      next_stage = "r1b", origins = target$full_origins, seed_robust = FALSE),
    r1b = list(n = target$r1b_advance_count, super = target$r1b_supercritical_quota,
      next_stage = "r2", origins = target$full_origins, seed_robust = TRUE),
    r2 = list(n = target$r2_advance_count, super = target$r2_supercritical_quota,
      next_stage = "h1", origins = target$full_origins, seed_robust = FALSE),
    stop("Targeted ridge finalizer accepts r1a, r1b, or r2.", call. = FALSE))
  scores <- app_joint_sw_collect_stage(root, stage)
  aggregate <- app_joint_sw_attach_candidate_metadata(root,
    app_joint_pht_aggregate(scores, c("scenario_id", "candidate_id")))
  frontier <- app_joint_pht_select_candidates(aggregate, spec$n, spec$super,
    target$max_state_saturation)
  if (stage == "r2") {
    registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
    candidates <- registry[registry$candidate_id %in% frontier$candidate_id, , drop = FALSE]
    candidates <- merge(candidates, data.frame(rhs_tau0 = target$rhs_tau0_grid), by = NULL)
    fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))[, c(
      "scenario_id", "replicate_id", "dgp_seed", "fixture_path"), drop = FALSE]
    plan <- merge(candidates, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
    plan$origin_indices <- paste(target$full_origins, collapse = ";")
    plan$h1_worker_id <- seq_len(nrow(plan))
    next_path <- app_write_csv(plan, file.path(root, "h1_worker_plan.csv"))
    app_ensure_dir(file.path(root, "h1_workers"))
  } else {
    next_path <- app_joint_pht_plan_from_candidates(root, frontier, spec$next_stage,
      spec$origins, spec$seed_robust)
  }
  files <- c(
    scores = app_write_csv(scores, file.path(root, paste0(stage, "_scores.csv"))),
    aggregate = app_write_csv(aggregate, file.path(root, paste0(stage, "_aggregate.csv"))),
    frontier = app_write_csv(frontier, file.path(root, paste0(stage, "_frontier.csv"))),
    next_plan = next_path,
    app_joint_sw_stage_receipts(root, stage))
  decision <- data.frame(stage = stage,
    status = paste0(toupper(stage), "_COMPLETE_READY_FOR_", toupper(spec$next_stage), "_REVIEW"),
    selected = nrow(frontier), next_stage_launched = FALSE,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  files <- c(files, decision = app_write_csv(decision,
    file.path(root, paste0(stage, "_decision.csv"))))
  app_joint_pht_freeze_manifest(root, files, filename = paste0(stage, "_manifest.csv"))
  decision
}

app_joint_pht_select_pairs <- function(x, n) {
  x <- x[x$finite_fraction == 1 & x$protected_rows_loaded_max == 0L &
    is.finite(x$calibration_acrps_mean) &
    (is.na(x$max_state_saturation) | x$max_state_saturation <= 0.25), , drop = FALSE]
  x <- x[order(x$calibration_acrps_mean, x$calibration_acrps_worst,
    x$calibration_acrps_sd, x$retained_state_budget, x$candidate_id, x$rhs_tau0), , drop = FALSE]
  authority <- x[grepl("anchor_authoritative_v3", x$candidate_role), , drop = FALSE]
  if (!nrow(authority)) stop("Targeted RHS selection lost the authority anchor.", call. = FALSE)
  authority <- authority[which.min(abs(log(authority$rhs_tau0) - log(authority$source_rhs_tau0))), , drop = FALSE]
  out <- app_bind_rows_fill(list(authority,
    x[!paste(x$candidate_id, x$rhs_tau0) %in% paste(authority$candidate_id, authority$rhs_tau0), , drop = FALSE]))
  head(out, n)
}

app_joint_pht_finalize_h1 <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  target <- app_joint_pht_read_contract(file.path(root, "frozen_target_contract.csv"))
  scores <- app_joint_sw_collect_stage(root, "h1")
  aggregate <- app_joint_sw_attach_candidate_metadata(root,
    app_joint_pht_aggregate(scores, c("scenario_id", "candidate_id", "rhs_tau0")))
  selected <- app_joint_pht_select_pairs(aggregate, target$h1_advance_count)
  neighbors <- app_bind_rows_fill(lapply(seq_len(nrow(selected)), function(ii) {
    center <- selected$rhs_tau0[[ii]]
    values <- pmin(target$refinement_max_tau0, pmax(target$refinement_min_tau0,
      center * 10^target$local_log10_offsets))
    values <- unique(values)
    values <- values[!vapply(values, function(z) any(abs(log(z) - log(target$rhs_tau0_grid)) < 1e-10), logical(1L))]
    data.frame(scenario_id = target$scenario_id, candidate_id = selected$candidate_id[[ii]],
      rhs_tau0 = values, stringsAsFactors = FALSE)
  }))
  registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
  candidates <- merge(registry, neighbors, by = c("scenario_id", "candidate_id"), all.y = TRUE)
  fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))[, c(
    "scenario_id", "replicate_id", "dgp_seed", "fixture_path"), drop = FALSE]
  plan <- merge(candidates, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan$origin_indices <- paste(target$full_origins, collapse = ";")
  plan$h2_worker_id <- seq_len(nrow(plan))
  files <- c(
    scores = app_write_csv(scores, file.path(root, "h1_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "h1_aggregate.csv")),
    selected = app_write_csv(selected, file.path(root, "h1_refinement_shortlist.csv")),
    h2_plan = app_write_csv(plan, file.path(root, "h2_worker_plan.csv")),
    app_joint_sw_stage_receipts(root, "h1"))
  app_ensure_dir(file.path(root, "h2_workers"))
  decision <- data.frame(status = "H1_COMPLETE_READY_FOR_LOCAL_TAU0_REFINEMENT_REVIEW",
    selected_pairs = nrow(selected), h2_workers = nrow(plan), h2_launched = FALSE,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  files <- c(files, decision = app_write_csv(decision, file.path(root, "h1_decision.csv")))
  app_joint_pht_freeze_manifest(root, files, filename = "h1_manifest.csv")
  decision
}

app_joint_pht_finalize_h2 <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  target <- app_joint_pht_read_contract(file.path(root, "frozen_target_contract.csv"))
  h1 <- app_read_csv(file.path(root, "h1_scores.csv"))
  h2 <- app_joint_sw_collect_stage(root, "h2")
  scores <- app_bind_rows_fill(list(h1, h2))
  aggregate <- app_joint_sw_attach_candidate_metadata(root,
    app_joint_pht_aggregate(scores, c("scenario_id", "candidate_id", "rhs_tau0")))
  selected <- app_joint_pht_select_pairs(aggregate, target$h2_advance_count)
  registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
  candidates <- merge(registry,
    selected[, c("scenario_id", "candidate_id", "rhs_tau0"), drop = FALSE],
    by = c("scenario_id", "candidate_id"), all.y = TRUE, sort = FALSE)
  fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))[, c(
    "scenario_id", "replicate_id", "dgp_seed", "fixture_path"), drop = FALSE]
  plan <- merge(candidates, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan$median_tau <- target$median_tau
  plan$origin_indices <- paste(target$full_origins, collapse = ";")
  plan$median_worker_id <- seq_len(nrow(plan))
  files <- c(
    h2_scores = app_write_csv(h2, file.path(root, "h2_scores.csv")),
    all_scores = app_write_csv(scores, file.path(root, "rhs_all_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "rhs_all_aggregate.csv")),
    selected = app_write_csv(selected, file.path(root, "rhs_selected_top8.csv")),
    median_plan = app_write_csv(plan, file.path(root, "median_al_worker_plan.csv")),
    app_joint_sw_stage_receipts(root, "h2"))
  app_ensure_dir(file.path(root, "m1_workers"))
  decision <- data.frame(status = "NORMAL_RHS_TARGETED_SCREEN_COMPLETE_READY_FOR_MEDIAN_AL_REVIEW",
    selected_pairs = nrow(selected), median_workers = nrow(plan), median_launched = FALSE,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  files <- c(files, decision = app_write_csv(decision, file.path(root, "h2_decision.csv")))
  app_joint_pht_freeze_manifest(root, files, filename = "h2_manifest.csv")
  decision
}

app_joint_pht_finalize_median <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  scores <- app_joint_swq_collect(root, "m1")
  proxy <- scores
  proxy$calibration_acrps_mean <- proxy$calibration_median_quantile_score_mean
  aggregate <- app_joint_sw_attach_candidate_metadata(root,
    app_joint_sw_aggregate_scores(proxy, c("scenario_id", "candidate_id", "rhs_tau0")))
  aggregate <- aggregate[order(aggregate$calibration_acrps_mean,
    aggregate$calibration_acrps_worst, aggregate$calibration_acrps_sd), , drop = FALSE]
  aggregate$median_selection_rank <- seq_len(nrow(aggregate))
  best <- aggregate[1L, , drop = FALSE]
  authority <- aggregate[grepl("anchor_authoritative_v3", aggregate$candidate_role), , drop = FALSE]
  if (nrow(authority) != 1L) stop("Median AL closeout requires one authority pair.", call. = FALSE)
  improvement <- authority$calibration_acrps_mean[[1L]] - best$calibration_acrps_mean[[1L]]
  files <- c(
    scores = app_write_csv(scores, file.path(root, "median_al_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "median_al_aggregate.csv")),
    app_joint_sw_stage_receipts(root, "m1"))
  decision <- data.frame(
    status = "TARGETED_MEDIAN_AL_COMPLETE_STOP_FOR_SCIENTIFIC_REVIEW",
    best_candidate_id = best$candidate_id[[1L]], best_rhs_tau0 = best$rhs_tau0[[1L]],
    best_score = best$calibration_acrps_mean[[1L]], authority_score = authority$calibration_acrps_mean[[1L]],
    mean_improvement = improvement,
    recommend_seven_grid_confirmation = is.finite(improvement) && improvement > 0,
    seven_grid_launched = FALSE, mcmc_launched = FALSE, protected_rows_used = 0L,
    stringsAsFactors = FALSE)
  files <- c(files, decision = app_write_csv(decision, file.path(root, "median_al_decision.csv")))
  app_joint_pht_freeze_manifest(root, files, filename = "median_al_manifest.csv")
  decision
}

app_joint_pht_finalize_stage <- function(root, stage) {
  switch(as.character(stage),
    r1a = app_joint_pht_finalize_ridge(root, "r1a"),
    r1b = app_joint_pht_finalize_ridge(root, "r1b"),
    r2 = app_joint_pht_finalize_ridge(root, "r2"),
    h1 = app_joint_pht_finalize_h1(root),
    h2 = app_joint_pht_finalize_h2(root),
    m1 = app_joint_pht_finalize_median(root),
    stop("Unknown targeted stage.", call. = FALSE))
}

app_joint_pht_health <- function(root) {
  stages <- c("r1a", "r1b", "r2", "h1", "h2")
  ridge <- app_bind_rows_fill(lapply(stages, function(stage) app_joint_sw_health(root, stage)))
  median <- app_joint_swq_health(root, "m1")
  app_bind_rows_fill(list(ridge, median))
}
