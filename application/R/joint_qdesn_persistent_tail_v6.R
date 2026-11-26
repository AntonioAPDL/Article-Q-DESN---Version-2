# Targeted persistent-heavy-tail V6 tail-prior calibration.

app_joint_pht6_contract_path <- function() {
  app_path("application/config/joint_qdesn_persistent_tail_v6_contract.csv")
}

app_joint_pht6_default_root <- function() {
  app_path("application/cache/joint_qdesn_persistent_tail_v6_20261126")
}

app_joint_pht6_read_contract <- function(path = app_joint_pht6_contract_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("section", "name", "value", "type", "description"),
    "persistent-tail V6 contract")
  value <- function(name) {
    row <- tab[tab$name == name, , drop = FALSE]
    if (nrow(row) != 1L) stop(sprintf("V6 contract requires one '%s'.", name), call. = FALSE)
    as.character(row$value[[1L]])
  }
  numvec <- function(name) as.numeric(strsplit(value(name), ";", fixed = TRUE)[[1L]])
  intvec <- function(name) as.integer(numvec(name))
  bool <- function(name) identical(tolower(value(name)), "true")
  out <- list(table = tab, version = value("contract_version"), run_tag = value("run_tag"),
    v4_head = value("v4_head"), v5_head = value("v5_head"),
    v4_h2_sha256 = value("v4_h2_sha256"), v4_m1_sha256 = value("v4_m1_sha256"),
    v4_candidates_sha256 = value("v4_candidates_sha256"),
    v5_decision_sha256 = value("v5_decision_sha256"),
    v5_summary_sha256 = value("v5_summary_sha256"),
    v5_finalists_sha256 = value("v5_finalists_sha256"), scenario_id = value("scenario_id"),
    v5_winner_id = value("v5_winner_id"), v5_secondary_id = value("v5_secondary_id"),
    exact_candidate_id = value("exact_candidate_id"), tau3 = numvec("quantile_grid_three"),
    tau7 = numvec("quantile_grid_seven"), screen_origins = intvec("origin_indices_screen"),
    full_origins = intvec("origin_indices_full"),
    tail_multipliers = numvec("tail_multipliers"),
    median_multipliers = numvec("median_multipliers"),
    required_hostname = value("required_hostname"))
  integers <- c("profiles_per_architecture", "qualification_triplets",
    "qualification_replicates", "sealed_challengers", "sealed_replicates",
    "seven_replicates", "sentinel_seed_offset", "screen_seed_offset",
    "qualification_seed_offset", "sealed_seed_offset", "seven_seed_offset",
    "max_physical_workers", "blas_threads", "nice_level")
  for (name in integers) out[[name]] <- as.integer(value(name))
  numerics <- c("median_fit_relative_margin", "median_fit_absolute_margin",
    "horizon1_relative_margin", "horizon1_absolute_margin", "fit_frontier_improvement",
    "score_noninferiority_relative", "score_noninferiority_absolute",
    "min_data_free_gib", "min_available_memory_gib")
  for (name in numerics) out[[name]] <- as.numeric(value(name))
  for (name in c("protected_selection_forbidden", "automatic_downstream_launch",
      "promote_any_strict_mean_improvement", "interval_overlap_is_equivalence")) {
    out[[name]] <- bool(name)
  }
  hashes <- unlist(out[c("v4_h2_sha256", "v4_m1_sha256", "v4_candidates_sha256",
    "v5_decision_sha256", "v5_summary_sha256", "v5_finalists_sha256")])
  valid <- identical(out$version, "joint_qdesn_persistent_tail_v6") &&
    identical(out$tau3, c(0.05, 0.5, 0.95)) &&
    identical(out$tau7, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)) &&
    identical(out$screen_origins, c(1L, 5L, 10L)) &&
    identical(out$full_origins, seq_len(10L)) && length(out$tail_multipliers) == 15L &&
    length(out$median_multipliers) == 5L && all(grepl("^[a-f0-9]{64}$", hashes)) &&
    out$protected_selection_forbidden && !out$automatic_downstream_launch &&
    out$promote_any_strict_mean_improvement && !out$interval_overlap_is_equivalence
  if (!valid) stop("Persistent-tail V6 contract is malformed.", call. = FALSE)
  out
}

app_joint_pht6_stage_spec <- function(stage) {
  switch(as.character(stage),
    sentinel = c(plan = "sentinel_worker_plan.csv", id = "sentinel_worker_id"),
    screen = c(plan = "screen_worker_plan.csv", id = "screen_worker_id"),
    qualification = c(plan = "qualification_worker_plan.csv", id = "qualification_worker_id"),
    sealed = c(plan = "sealed_worker_plan.csv", id = "sealed_worker_id"),
    seven = c(plan = "seven_worker_plan.csv", id = "seven_worker_id"),
    stop("Unknown V6 stage.", call. = FALSE))
}

app_joint_pht6_worker_dir <- function(root, stage, id) {
  file.path(root, paste0(stage, "_workers"), sprintf("worker_%05d", as.integer(id)))
}

app_joint_pht6_freeze_plan <- function(root, stage, plan) {
  spec <- app_joint_pht6_stage_spec(stage)
  path <- app_write_csv(plan, file.path(root, spec[["plan"]]))
  receipt <- file.path(root, paste0(stage, "_worker_plan.sha256"))
  writeLines(app_sha256_file(path), receipt)
  app_ensure_dir(file.path(root, paste0(stage, "_workers")))
  c(plan = path, plan_sha256 = receipt)
}

app_joint_pht6_verify_plan <- function(root, stage) {
  spec <- app_joint_pht6_stage_spec(stage)
  path <- file.path(root, spec[["plan"]])
  receipt <- file.path(root, paste0(stage, "_worker_plan.sha256"))
  if (!file.exists(path) || !file.exists(receipt) ||
      app_sha256_file(path) != trimws(readLines(receipt, warn = FALSE)[[1L]])) {
    stop(sprintf("V6 %s plan hash failed.", stage), call. = FALSE)
  }
  invisible(path)
}

app_joint_pht6_health <- function(root, stage) {
  spec <- app_joint_pht6_stage_spec(stage)
  path <- file.path(root, spec[["plan"]])
  if (!file.exists(path)) return(data.frame(stage = stage, expected = 0L, completed = 0L,
    failed = 0L, remaining = 0L, status = "not_prepared", stringsAsFactors = FALSE))
  app_joint_pht6_verify_plan(root, stage)
  plan <- app_read_csv(path)
  dirs <- vapply(plan[[spec[["id"]]]], function(id) app_joint_pht6_worker_dir(root, stage, id),
    character(1L))
  done <- file.exists(file.path(dirs, "DONE")) & file.exists(file.path(dirs, "artifact_manifest.csv"))
  failed <- file.exists(file.path(dirs, "FAILED")) | file.exists(file.path(dirs, "failure.csv"))
  data.frame(stage = stage, expected = nrow(plan), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), status = if (any(failed)) "failed" else if (all(done))
      "complete" else if (any(done)) "running" else "ready", stringsAsFactors = FALSE)
}

app_joint_pht6_all_health <- function(root) {
  app_bind_rows_fill(lapply(c("sentinel", "screen", "qualification", "sealed", "seven"),
    function(stage) app_joint_pht6_health(root, stage)))
}

app_joint_pht6_collect <- function(root, stage) {
  health <- app_joint_pht6_health(root, stage)
  if (health$completed != health$expected || health$failed != 0L) {
    stop(sprintf("V6 %s is incomplete or failed.", stage), call. = FALSE)
  }
  spec <- app_joint_pht6_stage_spec(stage)
  plan <- app_read_csv(file.path(root, spec[["plan"]]))
  app_bind_rows_fill(lapply(plan[[spec[["id"]]]], function(id) {
    dir <- app_joint_pht6_worker_dir(root, stage, id)
    verified <- app_joint_shared_verify_manifest(dir, file.path(dir, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified)) stop("V6 worker manifest failed.", call. = FALSE)
    summary <- app_read_csv(file.path(dir, "summary.csv"))
    if (anyDuplicated(names(summary))) {
      summary <- summary[, !duplicated(names(summary), fromLast = TRUE), drop = FALSE]
    }
    summary
  }))
}

app_joint_pht6_source_pins <- function(contract = app_joint_pht6_read_contract()) {
  c(h2_aggregate.csv = contract$v4_h2_sha256, m1_aggregate.csv = contract$v4_m1_sha256,
    candidate_registry.csv = contract$v4_candidates_sha256)
}

app_joint_pht6_verify_sources <- function(v4_root, v5_root,
    contract = app_joint_pht6_read_contract()) {
  v4_root <- normalizePath(v4_root, mustWork = TRUE)
  v5_root <- normalizePath(v5_root, mustWork = TRUE)
  pins4 <- app_joint_pht6_source_pins(contract)
  observed4 <- unname(tools::sha256sum(file.path(v4_root, names(pins4))))
  if (!identical(observed4, unname(pins4))) stop("V6 V4 source hash failed.", call. = FALSE)
  pins5 <- c(v5_decision.csv = contract$v5_decision_sha256,
    v5_profile_summary.csv = contract$v5_summary_sha256,
    v5_frozen_finalists.csv = contract$v5_finalists_sha256)
  observed5 <- unname(tools::sha256sum(file.path(v5_root, names(pins5))))
  if (!identical(observed5, unname(pins5))) stop("V6 V5 source hash failed.", call. = FALSE)
  decision <- app_read_csv(file.path(v5_root, "v5_decision.csv"))
  if (nrow(decision) != 1L || decision$status !=
      "V5_COMPLETE_SEVEN_LEVEL_CONTINUATION_AUTHORIZED" ||
      decision$selected_candidate_id != contract$v5_winner_id) {
    stop("V6 V5 authority is incompatible.", call. = FALSE)
  }
  list(v4_root = v4_root, v5_root = v5_root,
    h2 = app_read_csv(file.path(v4_root, "h2_aggregate.csv")),
    m1 = app_read_csv(file.path(v4_root, "m1_aggregate.csv")),
    candidates = app_read_csv(file.path(v4_root, "candidate_registry.csv")),
    finalists = app_read_csv(file.path(v5_root, "v5_frozen_finalists.csv")))
}

app_joint_pht6_profile_library <- function(source,
    contract = app_joint_pht6_read_contract()) {
  h2 <- source$h2[app_as_bool_vec(source$h2$hard_functional_pass_all), , drop = FALSE]
  split_h2 <- split(h2, h2$candidate_id)
  base <- app_bind_rows_fill(lapply(split_h2, function(x) {
    x <- x[order(x$training_location_mae_mean, x$horizon1_location_mae_mean,
      x$recursive_location_mae_mean, x$prior_spec_id), , drop = FALSE]
    head(x, contract$profiles_per_architecture)
  }))
  base$base_normal_rhs_tau0 <- base$rhs_tau0
  base$profile_role <- "v4_h2_replay"
  force <- source$finalists[source$finalists$candidate_id %in%
    c(contract$v5_winner_id, contract$v5_secondary_id, contract$exact_candidate_id), , drop = FALSE]
  forced <- source$candidates[match(force$candidate_id, source$candidates$candidate_id), , drop = FALSE]
  forced$base_normal_rhs_tau0 <- force$normal_rhs_tau0
  forced$rhs_tau0 <- force$normal_rhs_tau0
  forced$rhs_zeta2_profile <- force$rhs_zeta2_profile
  forced$rhs_zeta2_fixed <- force$rhs_zeta2_fixed
  forced$profile_role <- "v5_frozen_control"
  forced$prior_spec_id <- paste0("v5_control_", seq_len(nrow(forced)))
  extras <- list()
  make_extra <- function(id, tau0, zeta) {
    x <- source$candidates[source$candidates$candidate_id == id, , drop = FALSE]
    x <- x[rep(1L, length(zeta)), , drop = FALSE]
    x$base_normal_rhs_tau0 <- tau0; x$rhs_tau0 <- tau0
    x$rhs_zeta2_profile <- format(zeta, trim = TRUE, scientific = FALSE)
    x$rhs_zeta2_fixed <- zeta; x$profile_role <- "v6_boundary_extension"
    x$prior_spec_id <- paste0("v6_extension_", id, "_", seq_along(zeta)); x
  }
  extras[[1L]] <- make_extra(contract$v5_winner_id, 1, c(128, 256, 512))
  extras[[2L]] <- make_extra(contract$v5_secondary_id, 1e-10, c(0.0001, 0.001, 0.03, 0.1))
  keep <- intersect(names(base), names(forced))
  library <- app_bind_rows_fill(list(base[, keep, drop = FALSE], forced[, keep, drop = FALSE],
    extras[[1L]][, keep, drop = FALSE], extras[[2L]][, keep, drop = FALSE]))
  canonical_zeta <- ifelse(is.na(library$rhs_zeta2_fixed),
    as.character(library$rhs_zeta2_profile),
    format(library$rhs_zeta2_fixed, digits = 17, scientific = TRUE))
  key <- paste(library$candidate_id, format(library$base_normal_rhs_tau0, digits = 17),
    canonical_zeta, sep = "|")
  library <- library[!duplicated(key), , drop = FALSE]
  library <- library[order(library$candidate_id, library$base_normal_rhs_tau0,
    library$rhs_zeta2_profile), , drop = FALSE]
  architecture <- source$candidates[match(library$candidate_id,
    source$candidates$candidate_id), , drop = FALSE]
  for (name in setdiff(names(architecture), names(library))) library[[name]] <- architecture[[name]]
  library$profile_id <- sprintf("v6_profile_%03d", seq_len(nrow(library)))
  if (length(unique(library$candidate_id)) != 24L || nrow(library) > 55L ||
      !all(c(contract$v5_winner_id, contract$v5_secondary_id, contract$exact_candidate_id) %in%
        library$candidate_id)) stop("V6 profile library is malformed.", call. = FALSE)
  library
}

app_joint_pht6_fixture <- function(root, panel, replicate_id, offset, source,
    contract = app_joint_pht6_read_contract(), materialize = TRUE) {
  registry <- app_read_csv(file.path(root, "frozen_registry.csv"))
  derived <- app_read_csv(file.path(root, "derived_dgp_registry.csv"))
  row <- derived[derived$scenario_id == contract$scenario_id, , drop = FALSE]
  row$seed <- as.integer(registry$selector_seed_base[[1L]]) + offset + replicate_id - 1L
  row$seed_role <- sprintf("persistent_tail_v6_%s_rep%02d", panel, replicate_id)
  if (!materialize) return(data.frame(scenario_id = contract$scenario_id, panel = panel,
    replicate_id = replicate_id, dgp_seed = row$seed, materialized = FALSE,
    fixture_path = NA_character_, size_bytes = NA_real_, sha256 = NA_character_,
    protected_rows_persisted = 0L, stringsAsFactors = FALSE))
  fixture <- app_joint_qdesn_fixture_from_registry_row(row)
  fixture$registry_row <- row
  selector <- app_joint_pure_selector_fixture(fixture,
    app_joint_sw_read_contract(file.path(root, "frozen_contract.csv")))
  keep <- fixture$detailed_split$role %in% c("desn_washout", "fit")
  selector$mu <- fixture$mu[keep]; selector$sigma <- fixture$sigma[keep]
  path <- file.path(root, "fixtures", sprintf("%s_rep%02d.rds", panel, replicate_id))
  saveRDS(selector, path, version = 3L, compress = "xz")
  data.frame(scenario_id = contract$scenario_id, panel = panel, replicate_id = replicate_id,
    dgp_seed = row$seed, materialized = TRUE, fixture_path = normalizePath(path),
    size_bytes = file.info(path)$size, sha256 = app_sha256_file(path),
    protected_rows_persisted = selector$protected_rows_persisted, stringsAsFactors = FALSE)
}

app_joint_pht6_expand_profiles <- function(library, fixture, contract, sentinel = FALSE) {
  rows <- list(); at <- 0L
  add <- function(profile, tau, multiplier) {
    at <<- at + 1L; x <- profile
    x$tau <- tau; x$al_tau0_multiplier <- multiplier
    x$normal_rhs_tau0 <- x$base_normal_rhs_tau0
    x$rhs_tau0 <- x$base_normal_rhs_tau0 * multiplier
    x$prior_mode <- "fixed_tau0"
    x$quantile_spec_id <- sprintf("v6_%s_%06d", if (sentinel) "sentinel" else "screen", at)
    rows[[at]] <<- x
  }
  if (sentinel) {
    subset_profile <- function(id, zeta) library[library$candidate_id == id &
      !is.na(library$rhs_zeta2_fixed) & library$rhs_zeta2_fixed %in% zeta, , drop = FALSE]
    p1 <- subset_profile(contract$v5_winner_id, c(64, 128))
    p2 <- subset_profile(contract$v5_secondary_id, c(0.01, 0.001))
    for (i in seq_len(nrow(p1))) for (tau in c(0.05, 0.95)) for (m in c(0.03, 0.1, 0.3))
      add(p1[i, , drop = FALSE], tau, m)
    for (i in seq_len(nrow(p2))) for (tau in c(0.05, 0.95)) for (m in c(0.0003, 0.001, 0.003))
      add(p2[i, , drop = FALSE], tau, m)
    base1 <- p1[p1$rhs_zeta2_fixed == 64, , drop = FALSE][1L, , drop = FALSE]
    base2 <- p2[p2$rhs_zeta2_fixed == 0.01, , drop = FALSE][1L, , drop = FALSE]
    add(base1, 0.5, 0.1); add(base2, 0.5, 0.001)
  } else {
    for (i in seq_len(nrow(library))) {
      for (tau in c(0.05, 0.95)) for (m in contract$tail_multipliers)
        add(library[i, , drop = FALSE], tau, m)
      for (m in contract$median_multipliers) add(library[i, , drop = FALSE], 0.5, m)
    }
  }
  profiles <- app_bind_rows_fill(rows)
  plan <- merge(profiles, fixture[, c("scenario_id", "replicate_id", "dgp_seed", "fixture_path")],
    by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan$origin_indices <- paste(if (sentinel) contract$screen_origins else contract$screen_origins,
    collapse = ";")
  plan
}

app_joint_pht6_prepare <- function(v4_root, v5_root, root = app_joint_pht6_default_root()) {
  contract <- app_joint_pht6_read_contract()
  source <- app_joint_pht6_verify_sources(v4_root, v5_root, contract)
  root <- normalizePath(root, mustWork = FALSE)
  if (dir.exists(root) && length(list.files(root, all.files = TRUE, no.. = TRUE))) {
    stop("Refusing to overwrite a nonempty V6 root.", call. = FALSE)
  }
  app_ensure_dir(root); app_ensure_dir(file.path(root, "fixtures"))
  foundational <- c("frozen_contract.csv", "frozen_v4_contract.csv", "frozen_registry.csv",
    "derived_dgp_registry.csv", "candidate_registry.csv")
  if (!all(file.copy(file.path(source$v4_root, foundational), file.path(root, foundational)))) {
    stop("Could not freeze V4 foundations.", call. = FALSE)
  }
  evidence <- c("h2_aggregate.csv", "m1_aggregate.csv")
  file.copy(file.path(source$v4_root, evidence), file.path(root, paste0("v4_", evidence)))
  evidence5 <- c("v5_decision.csv", "v5_profile_summary.csv", "v5_frozen_finalists.csv")
  file.copy(file.path(source$v5_root, evidence5), file.path(root, evidence5))
  frozen_contract <- app_write_csv(contract$table, file.path(root, "frozen_v6_contract.csv"))
  library <- app_joint_pht6_profile_library(source, contract)
  library_path <- app_write_csv(library, file.path(root, "frozen_profile_library.csv"))
  fixtures <- app_bind_rows_fill(c(
    list(app_joint_pht6_fixture(root, "sentinel", 1L, contract$sentinel_seed_offset, source,
      contract, TRUE)),
    list(app_joint_pht6_fixture(root, "screen", 1L, contract$screen_seed_offset, source,
      contract, TRUE)),
    lapply(seq_len(contract$qualification_replicates), function(i)
      app_joint_pht6_fixture(root, "qualification", i, contract$qualification_seed_offset,
        source, contract, FALSE)),
    lapply(seq_len(contract$sealed_replicates), function(i)
      app_joint_pht6_fixture(root, "sealed", i, contract$sealed_seed_offset,
        source, contract, FALSE)),
    lapply(seq_len(contract$seven_replicates), function(i)
      app_joint_pht6_fixture(root, "seven", i, contract$seven_seed_offset,
        source, contract, FALSE))))
  fixtures_path <- app_write_csv(fixtures, file.path(root, "frozen_fixture_seed_plan.csv"))
  app_write_csv(fixtures, file.path(root, "fixture_seed_registry.csv"))
  sentinel_fixture <- fixtures[fixtures$panel == "sentinel", , drop = FALSE]
  screen_fixture <- fixtures[fixtures$panel == "screen", , drop = FALSE]
  sentinel <- app_joint_pht6_expand_profiles(library, sentinel_fixture, contract, TRUE)
  sentinel$sentinel_worker_id <- seq_len(nrow(sentinel))
  screen <- app_joint_pht6_expand_profiles(library, screen_fixture, contract, FALSE)
  screen$screen_worker_id <- seq_len(nrow(screen))
  if (nrow(sentinel) != 26L || nrow(screen) > 1925L || anyNA(screen$fixture_path)) {
    stop("V6 initial plan cardinality failed.", call. = FALSE)
  }
  files <- c(frozen_v6_contract = frozen_contract, profile_library = library_path,
    fixture_seed_registry = fixtures_path,
    app_joint_pht6_freeze_plan(root, "sentinel", sentinel),
    app_joint_pht6_freeze_plan(root, "screen", screen),
    source_git_state = app_write_csv(app_joint_shared_git_state(),
      file.path(root, "source_git_state.csv")))
  readiness <- data.frame(status = "V6_PREPARED_SENTINEL_NOT_LAUNCHED",
    profiles = nrow(library), sentinel_workers = nrow(sentinel), screen_workers = nrow(screen),
    qualification_materialized = FALSE, sealed_materialized = FALSE,
    seven_materialized = FALSE, protected_rows_used = 0L, stringsAsFactors = FALSE)
  files <- c(files, readiness = app_write_csv(readiness, file.path(root, "launch_readiness.csv")))
  manifest <- app_joint_shared_write_manifest(root, files, filename = "preparation_manifest.csv")
  verified <- app_joint_shared_verify_manifest(root, manifest)
  if (!nrow(verified) || any(!verified$verified) || any(fixtures$protected_rows_persisted != 0L)) {
    stop("V6 preparation verification failed.", call. = FALSE)
  }
  app_write_csv(verified, file.path(root, "preparation_manifest_verification.csv"))
  list(root = root, readiness = readiness, library = library, sentinel = sentinel, screen = screen)
}

app_joint_pht6_profile_columns <- function() {
  c("candidate_id", "profile_id", "prior_spec_id", "quantile_spec_id",
    "normal_rhs_tau0", "rhs_tau0", "rhs_zeta2_profile", "rhs_zeta2_fixed",
    "al_tau0_multiplier")
}

app_joint_pht6_triplet_id <- function(lower_id, median_id, upper_id) {
  paste0("v6_triplet_", gsub("[^A-Za-z0-9]+", "_",
    paste(lower_id, median_id, upper_id, sep = "__")))
}

app_joint_pht6_run_component <- function(fixture, row, base, origins) {
  tau <- as.numeric(row$tau[[1L]])
  if ("triplet_id" %in% names(row)) {
    result <- app_joint_pht6_score_triplet_component(fixture, row, base, origins, tau)
  } else {
    result <- app_joint_pht4_score_quantile(fixture, row, base, origins, tau)
  }
  reservoir <- app_joint_pht3_reservoir_diagnostics(result$design)
  result$summary <- cbind(result$summary, reservoir)
  connectivity <- reservoir$recurrent_nonzero_connections[[1L]] > 0L &&
    reservoir$input_nonzero_connections[[1L]] > 0L
  finite <- all(is.finite(c(result$summary$training_quantile_mae,
    result$summary$horizon1_quantile_mae, result$summary$recursive_quantile_mae,
    result$summary$dgp_expected_quantile_score)))
  result$summary$connectivity_hard_pass <- connectivity
  result$summary$convergence_review_only <- !isTRUE(result$summary$converged[[1L]])
  result$summary$hard_functional_pass <- finite && connectivity &&
    isTRUE(result$summary$recursive_state_finite[[1L]]) &&
    result$summary$protected_rows_loaded[[1L]] == 0L
  result$summary$screening_eligible <- result$summary$hard_functional_pass
  result
}

app_joint_pht6_score_triplet_component <- function(fixture, candidate, base, origins, tau) {
  candidate <- app_joint_pht6_drop_stale_metrics(candidate)
  design <- app_joint_pure_build_design(fixture, candidate, base, selector = TRUE)
  median_prior <- app_joint_pht6_prior_row(candidate, 0.5)
  median_controls <- app_joint_pht3_quantile_controls(base, median_prior)
  median_normal <- app_joint_pht3_fit_normal_initializer(design, median_prior, base, median_controls)
  median_fit <- app_joint_swq_fit_al(design, median_normal, median_controls, 0.5,
    app_joint_swq_single_init(median_normal, 0.5, design), median_controls$median_max_iter)
  target_prior <- app_joint_pht6_prior_row(candidate, tau)
  target_controls <- app_joint_pht3_quantile_controls(base, target_prior)
  target_normal <- if (tau == 0.5) median_normal else
    app_joint_pht3_fit_normal_initializer(design, target_prior, base, target_controls)
  if (tau == 0.5) {
    fit <- median_fit
  } else {
    init <- app_joint_swq_single_init(target_normal, tau, design)
    init$beta_mean <- median_fit$beta_mean
    init$beta_cov <- median_fit$beta_cov
    fit <- app_joint_swq_fit_al(design, target_normal, target_controls, tau, init,
      target_controls$quantile_max_iter)
  }
  pred <- app_joint_swq_recursive_quantile(design, fixture, fit, median_fit, base, origins)
  k <- match(tau, design$tau)
  tr <- design$train_local
  fit_hat <- as.numeric(fit$alpha_mean[[1L]] + design$Z[tr, , drop = FALSE] %*%
    as.numeric(fit$beta_mean))
  y <- design$y[pred$score_local]
  detail <- data.frame(full_time_index = pred$full_time_index,
    origin_index = pred$origin_index, horizon = pred$horizon, tau = tau, y = y,
    qhat = pred$qhat, median_feedback = pred$median_qhat,
    true_quantile = design$true_q[pred$score_local, k],
    check_loss = app_check_loss(y, pred$qhat, tau), stringsAsFactors = FALSE)
  local <- match(detail$full_time_index, design$row_meta$full_time_index)
  expected <- app_joint_qdesn_postscore_expected_check(detail$qhat, tau,
    fixture$mu[local], fixture$sigma[local], fixture$registry_row)
  summary <- cbind(candidate, data.frame(status = "completed",
    method = "independent_al_rhs_vb_tail_mapped_triplet", tau = tau,
    n_train = length(tr), n_calibration_scored = nrow(detail),
    protected_rows_loaded = design$diagnostic$protected_rows_loaded,
    training_quantile_mae = mean(abs(fit_hat - design$true_q[tr, k])),
    training_quantile_rmse = sqrt(mean((fit_hat - design$true_q[tr, k])^2)),
    horizon1_quantile_mae = mean(abs(detail$qhat[detail$horizon == 1L] -
      detail$true_quantile[detail$horizon == 1L])),
    horizon1_5_quantile_mae = mean(abs(detail$qhat[detail$horizon <= 5L] -
      detail$true_quantile[detail$horizon <= 5L])),
    recursive_quantile_mae = mean(abs(detail$qhat - detail$true_quantile)),
    calibration_check_loss_mean = mean(detail$check_loss),
    dgp_expected_quantile_score = mean(2 * expected),
    recursive_state_finite = pred$recursive_state_finite,
    recursive_state_saturation_fraction = pred$recursive_state_saturation_fraction,
    recursive_state_max_abs = pred$recursive_state_max_abs,
    median_converged = isTRUE(median_fit$converged), converged = isTRUE(fit$converged),
    convergence_status = if (isTRUE(fit$converged)) "pass" else "review_max_iter",
    iterations = as.integer(fit$iterations_completed %||% fit$iterations %||% NA_integer_),
    stringsAsFactors = FALSE))
  list(summary = summary, detail = detail,
    trace = app_joint_shared_quantile_trace_frame(fit),
    fit = app_joint_shared_quantile_compact_fit(fit),
    median_fit = app_joint_shared_quantile_compact_fit(median_fit),
    normal_initializer = list(target = target_normal, median = median_normal), design = design)
}

app_joint_pht6_drop_stale_metrics <- function(x) {
  stale <- c("status", "method", "tau", "n_train", "n_calibration_scored",
    "protected_rows_loaded", "calibration_check_loss_mean", "calibration_check_loss_sd",
    "dgp_expected_quantile_score", "companion_median_fit_mae",
    "companion_median_horizon1_mae", "companion_median_recursive_mae",
    "companion_median_dgp_expected_quantile_score", "calibration_oracle_quantile_mae",
    "calibration_oracle_quantile_rmse", "training_quantile_mae",
    "training_quantile_rmse", "horizon1_quantile_mae", "horizon1_5_quantile_mae",
    "recursive_quantile_mae", "quantile_functionals_finite", "recursive_state_finite",
    "recursive_state_saturation_fraction", "recursive_state_max_abs", "median_converged",
    "converged", "convergence_status", "iterations", "runtime_seconds", "peak_rss_kib",
    "connectivity_hard_pass", "convergence_review_only", "hard_functional_pass",
    "screening_eligible", "warning_count", "warning_messages", "runtime_seconds_total")
  x[, setdiff(names(x), stale), drop = FALSE]
}

app_joint_pht6_prior_row <- function(candidate, tau) {
  band <- if (tau <= 0.10) "lower" else if (tau >= 0.90) "upper" else "median"
  prefix <- paste0(band, "_")
  out <- candidate
  for (name in app_joint_pht6_profile_columns()) {
    mapped <- paste0(prefix, name)
    if (mapped %in% names(candidate)) out[[name]] <- candidate[[mapped]]
  }
  out$tau <- tau
  out$prior_band <- band
  out
}

app_joint_pht6_fit_full7 <- function(fixture, candidate, base, origins) {
  started <- proc.time()[[3L]]
  design <- app_joint_pure_build_design(fixture, candidate, base, selector = TRUE)
  order <- app_joint_swq_continuation_order()
  fits <- normals <- details <- list()
  median_fit <- NULL
  for (ii in seq_len(nrow(order))) {
    tau <- order$tau[[ii]]
    key <- sprintf("%.2f", tau)
    prior <- app_joint_pht6_prior_row(candidate, tau)
    controls <- app_joint_pht3_quantile_controls(base, prior)
    normal <- app_joint_pht3_fit_normal_initializer(design, prior, base, controls)
    init <- app_joint_swq_single_init(normal, tau, design)
    parent_tau <- order$parent_tau[[ii]]
    if (!is.na(parent_tau)) {
      parent <- fits[[sprintf("%.2f", parent_tau)]]
      init$beta_mean <- parent$beta_mean
      init$beta_cov <- parent$beta_cov
    }
    fit <- app_joint_swq_fit_al(design, normal, controls, tau, init,
      if (tau == 0.5) controls$median_max_iter else controls$quantile_max_iter)
    fits[[key]] <- fit
    normals[[key]] <- normal
    if (tau == 0.5) median_fit <- fit
    if (is.null(median_fit)) stop("V6 continuation order must begin at the median.", call. = FALSE)
    pred <- app_joint_swq_recursive_quantile(design, fixture, fit, median_fit, base, origins)
    k <- match(tau, design$tau)
    tr <- design$train_local
    fit_hat <- as.numeric(fit$alpha_mean[[1L]] +
      design$Z[tr, , drop = FALSE] %*% as.numeric(fit$beta_mean))
    details[[key]] <- data.frame(full_time_index = pred$full_time_index,
      origin_index = pred$origin_index, horizon = pred$horizon, tau = tau,
      y = design$y[pred$score_local], qhat = pred$qhat,
      true_quantile = design$true_q[pred$score_local, k],
      training_quantile_mae = mean(abs(fit_hat - design$true_q[tr, k])),
      recursive_state_finite = pred$recursive_state_finite,
      stringsAsFactors = FALSE)
  }
  ordered <- lapply(base$tau, function(tau) details[[sprintf("%.2f", tau)]])
  reference <- ordered[[1L]]
  aligned <- vapply(ordered, function(x) identical(x$full_time_index,
    reference$full_time_index), logical(1L))
  if (!all(aligned)) stop("V6 seven-level rows do not align.", call. = FALSE)
  qhat <- do.call(cbind, lapply(ordered, `[[`, "qhat"))
  truth <- do.call(cbind, lapply(ordered, `[[`, "true_quantile"))
  fit_mae <- vapply(ordered, function(x) unique(x$training_quantile_mae)[[1L]], numeric(1L))
  h1_mae <- vapply(ordered, function(x) mean(abs(x$qhat[x$horizon == 1L] -
    x$true_quantile[x$horizon == 1L])), numeric(1L))
  rec_mae <- vapply(ordered, function(x) mean(abs(x$qhat - x$true_quantile)), numeric(1L))
  realized <- app_joint_shared_acrps(reference$y, qhat, base$tau)
  local <- match(reference$full_time_index, design$row_meta$full_time_index)
  dgp <- app_joint_qdesn_postscore_score_matrix(qhat, reference$y, fixture$mu[local],
    fixture$sigma[local], fixture$registry_row, base$tau, app_joint_shared_weights(base$tau))
  crossing <- app_joint_qdesn_apply_monotone_contract(qhat, base$tau)
  summary <- cbind(candidate, data.frame(status = "completed",
    method = "independent_al_rhs_vb_full7_tail_mapped",
    lower_fit_mae = fit_mae[[1L]], median_fit_mae = fit_mae[[4L]],
    upper_fit_mae = fit_mae[[7L]], lower_horizon1_mae = h1_mae[[1L]],
    median_horizon1_mae = h1_mae[[4L]], upper_horizon1_mae = h1_mae[[7L]],
    lower_recursive_mae = rec_mae[[1L]], median_recursive_mae = rec_mae[[4L]],
    upper_recursive_mae = rec_mae[[7L]], calibration_acrps_mean = mean(realized),
    dgp_integrated_acrps = dgp$dgp_integrated_acrps,
    raw_crossing_pairs = sum(crossing$raw_crossing$n_crossing_pairs),
    contract_crossing_pairs = sum(crossing$contract_crossing$n_crossing_pairs),
    all_components_converged = all(vapply(fits, function(x) isTRUE(x$converged), logical(1L))),
    recursive_state_finite = all(vapply(ordered, function(x)
      all(app_as_bool_vec(x$recursive_state_finite)), logical(1L))),
    protected_rows_loaded = design$diagnostic$protected_rows_loaded,
    functionals_finite = all(is.finite(c(qhat, truth, fit_mae, h1_mae, rec_mae, realized,
      dgp$dgp_integrated_acrps))), runtime_seconds = proc.time()[[3L]] - started,
    peak_rss_kib = app_joint_sw_vm_hwm_kib(), stringsAsFactors = FALSE))
  detail <- data.frame(full_time_index = rep(reference$full_time_index, times = length(base$tau)),
    origin_index = rep(reference$origin_index, times = length(base$tau)),
    horizon = rep(reference$horizon, times = length(base$tau)),
    tau = rep(base$tau, each = nrow(reference)), y = rep(reference$y, times = length(base$tau)),
    qhat = as.numeric(qhat), true_quantile = as.numeric(truth), stringsAsFactors = FALSE)
  list(summary = summary, detail = detail,
    fit = lapply(fits, app_joint_shared_quantile_compact_fit),
    normal_initializer = normals, design = design)
}

app_joint_pht6_run_worker <- function(root, stage, worker_id) {
  root <- normalizePath(root, mustWork = TRUE)
  app_joint_pht6_verify_plan(root, stage)
  spec <- app_joint_pht6_stage_spec(stage)
  plan <- app_read_csv(file.path(root, spec[["plan"]]))
  row <- plan[plan[[spec[["id"]]]] == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("V6 worker ID is not unique.", call. = FALSE)
  out <- app_joint_pht6_worker_dir(root, stage, worker_id)
  if (file.exists(file.path(out, "DONE")) && file.exists(file.path(out, "artifact_manifest.csv"))) {
    verified <- app_joint_shared_verify_manifest(out, file.path(out, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified)) stop("V6 completed worker manifest failed.", call. = FALSE)
    return(invisible(out))
  }
  tmp <- paste0(out, ".tmp_", Sys.getpid())
  unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  fixture <- readRDS(row$fixture_path[[1L]])
  base <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  origins <- as.integer(strsplit(as.character(row$origin_indices[[1L]]), ";", fixed = TRUE)[[1L]])
  started <- Sys.time()
  captured <- tryCatch(app_joint_sw_capture_warnings(function() {
    if (stage == "seven") app_joint_pht6_fit_full7(fixture, row, base, origins) else
      app_joint_pht6_run_component(fixture, row, base, origins)
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
  if (stage == "seven") {
    reservoir <- app_joint_pht3_reservoir_diagnostics(result$design)
    result$summary <- cbind(result$summary, reservoir)
    result$summary$convergence_review_only <- !isTRUE(result$summary$all_components_converged[[1L]])
    result$summary$hard_functional_pass <- isTRUE(result$summary$functionals_finite[[1L]]) &&
      isTRUE(result$summary$recursive_state_finite[[1L]]) &&
      result$summary$protected_rows_loaded[[1L]] == 0L &&
      reservoir$recurrent_nonzero_connections[[1L]] > 0L &&
      reservoir$input_nonzero_connections[[1L]] > 0L
  }
  result$summary$warning_count <- length(captured$warnings)
  result$summary$warning_messages <- paste(captured$warnings, collapse = " | ")
  result$summary$runtime_seconds_total <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  files <- c(summary = app_write_csv(result$summary, file.path(tmp, "summary.csv")),
    detail = app_write_csv(result$detail, file.path(tmp, "detail.csv")))
  if (!is.null(result$trace) && nrow(result$trace))
    files <- c(files, trace = app_write_csv(result$trace, file.path(tmp, "vb_trace.csv")))
  fit_path <- file.path(tmp, "fit_initializer.rds")
  saveRDS(result$fit, fit_path, version = 3L, compress = "xz")
  files <- c(files, fit_initializer = fit_path)
  normal_path <- file.path(tmp, "normal_initializer.rds")
  saveRDS(result$normal_initializer, normal_path, version = 3L, compress = "xz")
  files <- c(files, normal_initializer = normal_path)
  if (length(captured$warnings)) files <- c(files, warnings = app_write_csv(data.frame(
    warning_index = seq_along(captured$warnings), warning_message = captured$warnings,
    stringsAsFactors = FALSE), file.path(tmp, "warnings.csv")))
  app_joint_shared_write_manifest(tmp, files)
  verified <- app_joint_shared_verify_manifest(tmp, file.path(tmp, "artifact_manifest.csv"))
  if (!nrow(verified) || any(!verified$verified)) stop("V6 worker manifest failed.", call. = FALSE)
  writeLines("completed", file.path(tmp, "DONE"))
  if (dir.exists(out)) unlink(out, recursive = TRUE, force = TRUE)
  if (!file.rename(tmp, out)) stop("Could not atomically publish V6 worker.", call. = FALSE)
  invisible(out)
}

app_joint_pht6_materialize_panel <- function(root, panel, contract = app_joint_pht6_read_contract()) {
  registry <- app_read_csv(file.path(root, "fixture_seed_registry.csv"))
  rows <- registry[registry$panel == panel, , drop = FALSE]
  if (!nrow(rows)) stop("V6 fixture panel is absent.", call. = FALSE)
  offset <- contract[[paste0(panel, "_seed_offset")]]
  materialized <- app_bind_rows_fill(lapply(rows$replicate_id, function(i)
    app_joint_pht6_fixture(root, panel, i, offset, NULL, contract, TRUE)))
  registry <- registry[registry$panel != panel, , drop = FALSE]
  registry <- app_bind_rows_fill(list(registry, materialized))
  registry <- registry[order(match(registry$panel,
    c("sentinel", "screen", "qualification", "sealed", "seven")),
    registry$replicate_id), , drop = FALSE]
  app_write_csv(registry, file.path(root, "fixture_seed_registry.csv"))
  materialized
}

app_joint_pht6_best_components <- function(scores) {
  eligible <- scores[app_as_bool_vec(scores$hard_functional_pass), , drop = FALSE]
  if (!nrow(eligible)) stop("V6 screen has no functionally eligible components.", call. = FALSE)
  key <- paste(eligible$candidate_id, eligible$tau, sep = "|")
  out <- lapply(split(eligible, key), function(x) x[order(x$training_quantile_mae,
    x$horizon1_quantile_mae, x$recursive_quantile_mae,
    x$dgp_expected_quantile_score, x$quantile_spec_id), , drop = FALSE][1L, , drop = FALSE])
  app_bind_rows_fill(out)
}

app_joint_pht6_triplet_from_components <- function(lower, median, upper, role) {
  x <- lower
  cols <- app_joint_pht6_profile_columns()
  for (band in c("lower", "median", "upper")) {
    row <- get(band)
    for (name in cols) x[[paste0(band, "_", name)]] <- row[[name]]
  }
  x$triplet_role <- role
  x$triplet_id <- app_joint_pht6_triplet_id(lower$quantile_spec_id,
    median$quantile_spec_id, upper$quantile_spec_id)
  x$screen_lower_fit_mae <- lower$training_quantile_mae
  x$screen_median_fit_mae <- median$training_quantile_mae
  x$screen_upper_fit_mae <- upper$training_quantile_mae
  x$screen_lower_horizon1_mae <- lower$horizon1_quantile_mae
  x$screen_median_horizon1_mae <- median$horizon1_quantile_mae
  x$screen_upper_horizon1_mae <- upper$horizon1_quantile_mae
  x$screen_dgp_score <- sum(app_joint_shared_weights(c(0.05, 0.5, 0.95)) *
    c(lower$dgp_expected_quantile_score, median$dgp_expected_quantile_score,
      upper$dgp_expected_quantile_score))
  x
}

app_joint_pht6_screen_triplets <- function(scores, root,
    contract = app_joint_pht6_read_contract()) {
  best <- app_joint_pht6_best_components(scores)
  triplets <- lapply(split(best, best$candidate_id), function(x) {
    if (!all(contract$tau3 %in% x$tau)) return(NULL)
    app_joint_pht6_triplet_from_components(x[x$tau == 0.05, , drop = FALSE],
      x[x$tau == 0.5, , drop = FALSE], x[x$tau == 0.95, , drop = FALSE],
      "screen_best_by_architecture")
  })
  triplets <- app_bind_rows_fill(Filter(Negate(is.null), triplets))
  finalists <- app_read_csv(file.path(root, "v5_frozen_finalists.csv"))
  control <- lapply(seq_len(nrow(finalists)), function(i) {
    ref <- finalists[i, , drop = FALSE]
    matches <- scores[scores$candidate_id == ref$candidate_id &
      abs(scores$normal_rhs_tau0 - ref$normal_rhs_tau0) <=
        .Machine$double.eps * max(1, abs(ref$normal_rhs_tau0)) &
      abs(scores$rhs_zeta2_fixed - ref$rhs_zeta2_fixed) <=
        .Machine$double.eps * max(1, abs(ref$rhs_zeta2_fixed)) &
      abs(scores$al_tau0_multiplier - ref$al_tau0_multiplier) <=
        .Machine$double.eps * max(1, abs(ref$al_tau0_multiplier)), , drop = FALSE]
    if (!all(contract$tau3 %in% matches$tau))
      stop("V6 screen did not reproduce a frozen V5 control.", call. = FALSE)
    app_joint_pht6_triplet_from_components(matches[matches$tau == 0.05, , drop = FALSE][1L, , drop = FALSE],
      matches[matches$tau == 0.5, , drop = FALSE][1L, , drop = FALSE],
      matches[matches$tau == 0.95, , drop = FALSE][1L, , drop = FALSE],
      "v5_frozen_control")
  })
  all <- app_bind_rows_fill(c(list(triplets), control))
  all <- all[!duplicated(all$triplet_id), , drop = FALSE]
  all[order(all$screen_dgp_score,
    pmax(all$screen_lower_fit_mae, all$screen_upper_fit_mae), all$triplet_id), , drop = FALSE]
}

app_joint_pht6_select_qualification <- function(triplets,
    contract = app_joint_pht6_read_contract()) {
  controls <- triplets[triplets$triplet_role == "v5_frozen_control", , drop = FALSE]
  pool <- triplets[triplets$triplet_role != "v5_frozen_control", , drop = FALSE]
  slots <- max(0L, contract$qualification_triplets - nrow(controls))
  quota <- floor(slots / 3L)
  forecast <- pool[order(pool$screen_dgp_score,
    pmax(pool$screen_lower_fit_mae, pool$screen_upper_fit_mae), pool$triplet_id), , drop = FALSE]
  fit <- pool[order(pmax(pool$screen_lower_fit_mae, pool$screen_upper_fit_mae),
    pool$screen_dgp_score, pool$triplet_id), , drop = FALSE]
  h1 <- pool[order(pmax(pool$screen_lower_horizon1_mae, pool$screen_upper_horizon1_mae),
    pool$screen_dgp_score, pool$triplet_id), , drop = FALSE]
  selected <- app_bind_rows_fill(list(head(forecast, quota), head(fit, quota), head(h1, quota)))
  selected <- selected[!duplicated(selected$triplet_id), , drop = FALSE]
  if (nrow(selected) < slots) {
    rank_score <- rank(pool$screen_dgp_score, ties.method = "min") +
      rank(pmax(pool$screen_lower_fit_mae, pool$screen_upper_fit_mae), ties.method = "min") +
      rank(pmax(pool$screen_lower_horizon1_mae, pool$screen_upper_horizon1_mae), ties.method = "min")
    fill <- pool[order(rank_score, pool$triplet_id), , drop = FALSE]
    fill <- fill[!fill$triplet_id %in% selected$triplet_id, , drop = FALSE]
    selected <- app_bind_rows_fill(list(selected, head(fill, slots - nrow(selected))))
  }
  selected$qualification_selection_role <- "balanced_forecast_fit_horizon1_quota"
  controls$qualification_selection_role <- "frozen_v5_control"
  out <- app_bind_rows_fill(list(selected, controls))
  out <- out[!duplicated(out$triplet_id), , drop = FALSE]
  head(out, contract$qualification_triplets)
}

app_joint_pht6_component_plan <- function(triplets, fixtures, stage, origins) {
  rows <- list(); at <- 0L
  for (i in seq_len(nrow(triplets))) for (j in seq_len(nrow(fixtures))) for (tau in c(0.05, 0.5, 0.95)) {
    at <- at + 1L
    x <- app_joint_pht6_prior_row(app_joint_pht6_drop_stale_metrics(
      triplets[i, , drop = FALSE]), tau)
    x$replicate_id <- fixtures$replicate_id[[j]]
    x$dgp_seed <- fixtures$dgp_seed[[j]]
    x$fixture_path <- fixtures$fixture_path[[j]]
    x$origin_indices <- paste(origins, collapse = ";")
    rows[[at]] <- x
  }
  plan <- app_bind_rows_fill(rows)
  id <- paste0(stage, "_worker_id")
  plan[[id]] <- seq_len(nrow(plan))
  plan
}

app_joint_pht6_read_worker_detail <- function(root, stage, id) {
  app_read_csv(file.path(app_joint_pht6_worker_dir(root, stage, id), "detail.csv"))
}

app_joint_pht6_triplet_replicates <- function(root, stage, scores) {
  spec <- app_joint_pht6_stage_spec(stage)
  id <- spec[["id"]]
  groups <- split(scores, paste(scores$triplet_id, scores$replicate_id, sep = "|"))
  app_bind_rows_fill(lapply(groups, function(x) {
    if (!all(c(0.05, 0.5, 0.95) %in% x$tau)) stop("Incomplete V6 triplet replicate.", call. = FALSE)
    x <- x[match(c(0.05, 0.5, 0.95), x$tau), , drop = FALSE]
    details <- lapply(x[[id]], function(worker) app_joint_pht6_read_worker_detail(root, stage, worker))
    reference <- details[[1L]]
    if (any(vapply(details, function(z) !identical(z$full_time_index,
      reference$full_time_index), logical(1L)))) stop("V6 triplet detail mismatch.", call. = FALSE)
    qhat <- do.call(cbind, lapply(details, `[[`, "qhat"))
    crossing <- app_joint_qdesn_apply_monotone_contract(qhat, c(0.05, 0.5, 0.95))
    w <- app_joint_shared_weights(c(0.05, 0.5, 0.95))
    data.frame(triplet_id = x$triplet_id[[1L]], candidate_id = x$candidate_id[[1L]],
      triplet_role = x$triplet_role[[1L]], replicate_id = x$replicate_id[[1L]],
      lower_fit_mae = x$training_quantile_mae[[1L]],
      median_fit_mae = x$training_quantile_mae[[2L]],
      upper_fit_mae = x$training_quantile_mae[[3L]],
      lower_horizon1_mae = x$horizon1_quantile_mae[[1L]],
      median_horizon1_mae = x$horizon1_quantile_mae[[2L]],
      upper_horizon1_mae = x$horizon1_quantile_mae[[3L]],
      lower_recursive_mae = x$recursive_quantile_mae[[1L]],
      median_recursive_mae = x$recursive_quantile_mae[[2L]],
      upper_recursive_mae = x$recursive_quantile_mae[[3L]],
      dgp_score = sum(w * x$dgp_expected_quantile_score),
      realized_score = sum(w * 2 * x$calibration_check_loss_mean),
      raw_crossing_pairs = sum(crossing$raw_crossing$n_crossing_pairs),
      contract_crossing_pairs = sum(crossing$contract_crossing$n_crossing_pairs),
      hard_functional_pass = all(app_as_bool_vec(x$hard_functional_pass)),
      convergence_review = any(app_as_bool_vec(x$convergence_review_only)),
      stringsAsFactors = FALSE)
  }))
}

app_joint_pht6_triplet_aggregate <- function(replicates) {
  app_bind_rows_fill(lapply(split(replicates, replicates$triplet_id), function(x) data.frame(
    triplet_id = x$triplet_id[[1L]], candidate_id = x$candidate_id[[1L]],
    triplet_role = x$triplet_role[[1L]], replicates = nrow(x),
    lower_fit_mae_mean = mean(x$lower_fit_mae), median_fit_mae_mean = mean(x$median_fit_mae),
    upper_fit_mae_mean = mean(x$upper_fit_mae),
    lower_horizon1_mae_mean = mean(x$lower_horizon1_mae),
    median_horizon1_mae_mean = mean(x$median_horizon1_mae),
    upper_horizon1_mae_mean = mean(x$upper_horizon1_mae),
    lower_recursive_mae_mean = mean(x$lower_recursive_mae),
    median_recursive_mae_mean = mean(x$median_recursive_mae),
    upper_recursive_mae_mean = mean(x$upper_recursive_mae),
    dgp_score_mean = mean(x$dgp_score), dgp_score_sd = stats::sd(x$dgp_score),
    dgp_score_q025 = unname(stats::quantile(x$dgp_score, 0.025)),
    dgp_score_q975 = unname(stats::quantile(x$dgp_score, 0.975)),
    realized_score_mean = mean(x$realized_score),
    contract_crossing_pairs_sum = sum(x$contract_crossing_pairs),
    hard_functional_pass_all = all(x$hard_functional_pass),
    convergence_review_any = any(x$convergence_review), stringsAsFactors = FALSE)))
}

app_joint_pht6_write_receipt <- function(path) {
  receipt <- paste0(path, ".sha256")
  writeLines(app_sha256_file(path), receipt)
  receipt
}

app_joint_pht6_stage_manifest <- function(root, stage, files) {
  manifest <- app_joint_shared_write_manifest(root, files,
    filename = paste0(stage, "_finalization_manifest.csv"))
  verified <- app_joint_shared_verify_manifest(root, manifest)
  if (!nrow(verified) || any(!verified$verified)) stop("V6 finalization manifest failed.", call. = FALSE)
  app_write_csv(verified, file.path(root, paste0(stage, "_finalization_verification.csv")))
  invisible(verified)
}

app_joint_pht6_finalize_sentinel <- function(root) {
  scores <- app_joint_pht6_collect(root, "sentinel")
  pass <- nrow(scores) == 26L && all(app_as_bool_vec(scores$hard_functional_pass)) &&
    all(scores$protected_rows_loaded == 0L) && all(scores$tau %in% c(0.05, 0.5, 0.95))
  decision <- data.frame(status = if (pass) "SENTINEL_COMPLETE_SCREEN_AUTHORIZED" else
      "SENTINEL_FAILED_STOP", workers = nrow(scores), failed_functionals =
      sum(!app_as_bool_vec(scores$hard_functional_pass)), protected_rows_used =
      sum(scores$protected_rows_loaded), automatic_launch = FALSE, stringsAsFactors = FALSE)
  files <- c(scores = app_write_csv(scores, file.path(root, "sentinel_scores.csv")),
    decision = app_write_csv(decision, file.path(root, "sentinel_decision.csv")))
  app_joint_pht6_stage_manifest(root, "sentinel", files)
  decision
}

app_joint_pht6_finalize_screen <- function(root) {
  contract <- app_joint_pht6_read_contract(file.path(root, "frozen_v6_contract.csv"))
  sentinel <- app_read_csv(file.path(root, "sentinel_decision.csv"))
  if (sentinel$status != "SENTINEL_COMPLETE_SCREEN_AUTHORIZED")
    stop("V6 screen is not authorized by the sentinel.", call. = FALSE)
  scores <- app_joint_pht6_collect(root, "screen")
  triplets <- app_joint_pht6_screen_triplets(scores, root, contract)
  selected <- app_joint_pht6_select_qualification(triplets, contract)
  selected_path <- app_write_csv(selected, file.path(root, "frozen_qualification_triplets.csv"))
  selected_receipt <- app_joint_pht6_write_receipt(selected_path)
  fixtures <- app_joint_pht6_materialize_panel(root, "qualification", contract)
  plan <- app_joint_pht6_component_plan(selected, fixtures, "qualification", contract$full_origins)
  if (nrow(selected) > contract$qualification_triplets || nrow(plan) != nrow(selected) *
      contract$qualification_replicates * 3L || anyNA(plan$fixture_path)) {
    stop("V6 qualification plan cardinality failed.", call. = FALSE)
  }
  plan_files <- app_joint_pht6_freeze_plan(root, "qualification", plan)
  decision <- data.frame(status = "SCREEN_COMPLETE_QUALIFICATION_AUTHORIZED",
    screen_workers = nrow(scores), eligible_components = sum(app_as_bool_vec(scores$hard_functional_pass)),
    architecture_triplets = nrow(triplets), selected_triplets = nrow(selected),
    qualification_workers = nrow(plan), automatic_launch = FALSE, stringsAsFactors = FALSE)
  files <- c(scores = app_write_csv(scores, file.path(root, "screen_scores.csv")),
    triplets = app_write_csv(triplets, file.path(root, "screen_triplets.csv")),
    frozen_triplets = selected_path, frozen_triplets_sha256 = selected_receipt,
    qualification_plan = plan_files,
    qualification_fixtures = app_write_csv(fixtures,
      file.path(root, "qualification_fixtures.csv")),
    decision = app_write_csv(decision, file.path(root, "screen_decision.csv")))
  app_joint_pht6_stage_manifest(root, "screen", files)
  decision
}

app_joint_pht6_qualification_gates <- function(aggregate, contract) {
  baseline <- aggregate[aggregate$candidate_id == contract$v5_winner_id &
    aggregate$triplet_role == "v5_frozen_control", , drop = FALSE]
  if (nrow(baseline) != 1L) stop("V6 qualification baseline is not unique.", call. = FALSE)
  relative_cap <- function(ref, relative, absolute) ref * (1 + relative) + absolute
  aggregate$median_fit_gate <- aggregate$median_fit_mae_mean <= relative_cap(
    baseline$median_fit_mae_mean, contract$median_fit_relative_margin,
    contract$median_fit_absolute_margin)
  for (band in c("lower", "median", "upper")) {
    field <- paste0(band, "_horizon1_mae_mean")
    aggregate[[paste0(band, "_h1_gate")]] <- aggregate[[field]] <= relative_cap(
      baseline[[field]], contract$horizon1_relative_margin, contract$horizon1_absolute_margin)
  }
  aggregate$hard_eligible <- app_as_bool_vec(aggregate$hard_functional_pass_all) &
    aggregate$contract_crossing_pairs_sum == 0L & aggregate$median_fit_gate &
    aggregate$lower_h1_gate & aggregate$median_h1_gate & aggregate$upper_h1_gate
  aggregate$strict_forecast_improvement <- aggregate$dgp_score_mean < baseline$dgp_score_mean
  worst_fit <- pmax(aggregate$lower_fit_mae_mean, aggregate$upper_fit_mae_mean)
  baseline_worst <- max(baseline$lower_fit_mae_mean, baseline$upper_fit_mae_mean)
  aggregate$fit_frontier <- worst_fit <= baseline_worst * (1 - contract$fit_frontier_improvement)
  aggregate$score_noninferior <- aggregate$dgp_score_mean <= baseline$dgp_score_mean *
    (1 + contract$score_noninferiority_relative) + contract$score_noninferiority_absolute
  aggregate$advancement_eligible <- aggregate$hard_eligible &
    (aggregate$strict_forecast_improvement | (aggregate$fit_frontier & aggregate$score_noninferior))
  aggregate
}

app_joint_pht6_finalize_qualification <- function(root) {
  contract <- app_joint_pht6_read_contract(file.path(root, "frozen_v6_contract.csv"))
  scores <- app_joint_pht6_collect(root, "qualification")
  replicates <- app_joint_pht6_triplet_replicates(root, "qualification", scores)
  aggregate <- app_joint_pht6_qualification_gates(app_joint_pht6_triplet_aggregate(replicates), contract)
  challengers <- aggregate[aggregate$advancement_eligible &
    aggregate$triplet_role != "v5_frozen_control", , drop = FALSE]
  forecast <- challengers[challengers$strict_forecast_improvement, , drop = FALSE]
  forecast <- forecast[order(forecast$dgp_score_mean, forecast$triplet_id), , drop = FALSE]
  fit <- challengers[challengers$fit_frontier & challengers$score_noninferior, , drop = FALSE]
  fit <- fit[order(pmax(fit$lower_fit_mae_mean, fit$upper_fit_mae_mean),
    fit$dgp_score_mean, fit$triplet_id), , drop = FALSE]
  selected_ids <- unique(c(head(forecast$triplet_id, 1L), head(fit$triplet_id, 1L)))
  selected_ids <- head(selected_ids, contract$sealed_challengers)
  frozen <- app_read_csv(file.path(root, "frozen_qualification_triplets.csv"))
  controls <- frozen[frozen$candidate_id %in% c(contract$v5_winner_id,
    contract$exact_candidate_id) & frozen$triplet_role == "v5_frozen_control", , drop = FALSE]
  selected <- frozen[frozen$triplet_id %in% selected_ids, , drop = FALSE]
  finalists <- app_bind_rows_fill(list(selected, controls))
  finalists <- finalists[!duplicated(finalists$triplet_id), , drop = FALSE]
  files <- c(scores = app_write_csv(scores, file.path(root, "qualification_scores.csv")),
    replicates = app_write_csv(replicates, file.path(root, "qualification_replicates.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "qualification_aggregate.csv")))
  if (!length(selected_ids)) {
    decision <- data.frame(status = "QUALIFICATION_COMPLETE_NO_CHALLENGER_STOP",
      qualification_workers = nrow(scores), selected_challengers = 0L,
      automatic_launch = FALSE, stringsAsFactors = FALSE)
    files <- c(files, decision = app_write_csv(decision, file.path(root, "qualification_decision.csv")))
    app_joint_pht6_stage_manifest(root, "qualification", files)
    return(decision)
  }
  finalists_path <- app_write_csv(finalists, file.path(root, "frozen_sealed_finalists.csv"))
  finalists_receipt <- app_joint_pht6_write_receipt(finalists_path)
  fixtures <- app_joint_pht6_materialize_panel(root, "sealed", contract)
  plan <- app_joint_pht6_component_plan(finalists, fixtures, "sealed", contract$full_origins)
  plan_files <- app_joint_pht6_freeze_plan(root, "sealed", plan)
  decision <- data.frame(status = "QUALIFICATION_COMPLETE_SEALED_AUTHORIZED",
    qualification_workers = nrow(scores), selected_challengers = length(selected_ids),
    sealed_profiles = nrow(finalists), sealed_workers = nrow(plan), automatic_launch = FALSE,
    stringsAsFactors = FALSE)
  files <- c(files, finalists = finalists_path, finalists_sha256 = finalists_receipt,
    sealed_plan = plan_files,
    sealed_fixtures = app_write_csv(fixtures, file.path(root, "sealed_fixtures.csv")),
    decision = app_write_csv(decision, file.path(root, "qualification_decision.csv")))
  app_joint_pht6_stage_manifest(root, "qualification", files)
  decision
}

app_joint_pht6_seven_plan <- function(finalists, fixtures, origins) {
  rows <- list(); at <- 0L
  for (i in seq_len(nrow(finalists))) for (j in seq_len(nrow(fixtures))) {
    at <- at + 1L
    x <- finalists[i, , drop = FALSE]
    x$replicate_id <- fixtures$replicate_id[[j]]
    x$dgp_seed <- fixtures$dgp_seed[[j]]
    x$fixture_path <- fixtures$fixture_path[[j]]
    x$origin_indices <- paste(origins, collapse = ";")
    rows[[at]] <- x
  }
  plan <- app_bind_rows_fill(rows)
  plan$seven_worker_id <- seq_len(nrow(plan))
  plan
}

app_joint_pht6_finalize_sealed <- function(root) {
  contract <- app_joint_pht6_read_contract(file.path(root, "frozen_v6_contract.csv"))
  scores <- app_joint_pht6_collect(root, "sealed")
  replicates <- app_joint_pht6_triplet_replicates(root, "sealed", scores)
  aggregate <- app_joint_pht6_qualification_gates(app_joint_pht6_triplet_aggregate(replicates), contract)
  baseline <- aggregate[aggregate$candidate_id == contract$v5_winner_id &
    aggregate$triplet_role == "v5_frozen_control", , drop = FALSE]
  challenger <- aggregate[aggregate$triplet_role != "v5_frozen_control" &
    aggregate$hard_eligible & aggregate$dgp_score_mean < baseline$dgp_score_mean, , drop = FALSE]
  challenger <- challenger[order(challenger$dgp_score_mean, challenger$triplet_id), , drop = FALSE]
  files <- c(scores = app_write_csv(scores, file.path(root, "sealed_scores.csv")),
    replicates = app_write_csv(replicates, file.path(root, "sealed_replicates.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "sealed_aggregate.csv")))
  if (!nrow(challenger)) {
    decision <- data.frame(status = "SEALED_COMPLETE_NO_STRICT_IMPROVEMENT_STOP",
      sealed_workers = nrow(scores), selected_challengers = 0L, automatic_launch = FALSE,
      stringsAsFactors = FALSE)
    files <- c(files, decision = app_write_csv(decision, file.path(root, "sealed_decision.csv")))
    app_joint_pht6_stage_manifest(root, "sealed", files)
    return(decision)
  }
  finalist_source <- app_read_csv(file.path(root, "frozen_sealed_finalists.csv"))
  winner <- finalist_source[finalist_source$triplet_id == challenger$triplet_id[[1L]], , drop = FALSE]
  controls <- finalist_source[finalist_source$candidate_id %in% c(contract$v5_winner_id,
    contract$exact_candidate_id) & finalist_source$triplet_role == "v5_frozen_control", , drop = FALSE]
  finalists <- app_bind_rows_fill(list(winner, controls))
  finalists <- finalists[!duplicated(finalists$triplet_id), , drop = FALSE]
  finalists_path <- app_write_csv(finalists, file.path(root, "frozen_seven_finalists.csv"))
  finalists_receipt <- app_joint_pht6_write_receipt(finalists_path)
  fixtures <- app_joint_pht6_materialize_panel(root, "seven", contract)
  plan <- app_joint_pht6_seven_plan(finalists, fixtures, contract$full_origins)
  plan_files <- app_joint_pht6_freeze_plan(root, "seven", plan)
  decision <- data.frame(status = "SEALED_COMPLETE_SEVEN_AUTHORIZED",
    sealed_workers = nrow(scores), selected_challenger = challenger$triplet_id[[1L]],
    seven_profiles = nrow(finalists), seven_workers = nrow(plan), automatic_launch = FALSE,
    stringsAsFactors = FALSE)
  files <- c(files, finalists = finalists_path, finalists_sha256 = finalists_receipt,
    seven_plan = plan_files,
    seven_fixtures = app_write_csv(fixtures, file.path(root, "seven_fixtures.csv")),
    decision = app_write_csv(decision, file.path(root, "sealed_decision.csv")))
  app_joint_pht6_stage_manifest(root, "sealed", files)
  decision
}

app_joint_pht6_seven_aggregate <- function(scores) {
  app_bind_rows_fill(lapply(split(scores, scores$triplet_id), function(x) data.frame(
    triplet_id = x$triplet_id[[1L]], candidate_id = x$candidate_id[[1L]],
    triplet_role = x$triplet_role[[1L]], replicates = nrow(x),
    lower_fit_mae_mean = mean(x$lower_fit_mae), median_fit_mae_mean = mean(x$median_fit_mae),
    upper_fit_mae_mean = mean(x$upper_fit_mae),
    lower_horizon1_mae_mean = mean(x$lower_horizon1_mae),
    median_horizon1_mae_mean = mean(x$median_horizon1_mae),
    upper_horizon1_mae_mean = mean(x$upper_horizon1_mae),
    dgp_score_mean = mean(x$dgp_integrated_acrps), dgp_score_sd = stats::sd(x$dgp_integrated_acrps),
    dgp_score_q025 = unname(stats::quantile(x$dgp_integrated_acrps, 0.025)),
    dgp_score_q975 = unname(stats::quantile(x$dgp_integrated_acrps, 0.975)),
    realized_score_mean = mean(x$calibration_acrps_mean),
    raw_crossing_pairs_sum = sum(x$raw_crossing_pairs),
    contract_crossing_pairs_sum = sum(x$contract_crossing_pairs),
    hard_functional_pass_all = all(app_as_bool_vec(x$hard_functional_pass)),
    convergence_review_any = any(app_as_bool_vec(x$convergence_review_only)),
    stringsAsFactors = FALSE)))
}

app_joint_pht6_finalize_seven <- function(root) {
  contract <- app_joint_pht6_read_contract(file.path(root, "frozen_v6_contract.csv"))
  scores <- app_joint_pht6_collect(root, "seven")
  aggregate <- app_joint_pht6_seven_aggregate(scores)
  baseline <- aggregate[aggregate$candidate_id == contract$v5_winner_id &
    aggregate$triplet_role == "v5_frozen_control", , drop = FALSE]
  challenger <- aggregate[aggregate$triplet_role != "v5_frozen_control" &
    aggregate$hard_functional_pass_all & aggregate$contract_crossing_pairs_sum == 0L &
    aggregate$dgp_score_mean < baseline$dgp_score_mean, , drop = FALSE]
  challenger <- challenger[order(challenger$dgp_score_mean, challenger$triplet_id), , drop = FALSE]
  selected <- if (nrow(challenger)) challenger$triplet_id[[1L]] else contract$v5_winner_id
  decision <- data.frame(status = if (nrow(challenger))
      "V6_COMPLETE_NEW_SEVEN_LEVEL_CANDIDATE_CONFIRMED" else
      "V6_COMPLETE_V5_REMAINS_AUTHORITY", selected_id = selected,
    seven_workers = nrow(scores), new_candidate_confirmed = nrow(challenger) > 0L,
    downstream_joint_exal_mcmc_not_run = TRUE, article_unchanged = TRUE,
    stringsAsFactors = FALSE)
  files <- c(scores = app_write_csv(scores, file.path(root, "seven_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "seven_aggregate.csv")),
    decision = app_write_csv(decision, file.path(root, "v6_decision.csv")))
  app_joint_pht6_stage_manifest(root, "seven", files)
  decision
}

app_joint_pht6_finalize_stage <- function(root, stage) {
  switch(as.character(stage), sentinel = app_joint_pht6_finalize_sentinel(root),
    screen = app_joint_pht6_finalize_screen(root),
    qualification = app_joint_pht6_finalize_qualification(root),
    sealed = app_joint_pht6_finalize_sealed(root),
    seven = app_joint_pht6_finalize_seven(root),
    stop("Unknown V6 finalization stage.", call. = FALSE))
}

app_joint_pht6_check <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_pht6_read_contract(file.path(root, "frozen_v6_contract.csv"))
  fixtures <- app_read_csv(file.path(root, "fixture_seed_registry.csv"))
  materialized <- fixtures[app_as_bool_vec(fixtures$materialized), , drop = FALSE]
  fixture_ok <- !nrow(materialized) || all(file.exists(materialized$fixture_path) &
    unname(tools::sha256sum(materialized$fixture_path)) == materialized$sha256 &
    materialized$protected_rows_persisted == 0L)
  prepared <- app_joint_shared_verify_manifest(root, file.path(root, "preparation_manifest.csv"))
  plans <- c("sentinel", "screen", "qualification", "sealed", "seven")
  plan_ok <- vapply(plans, function(stage) {
    spec <- app_joint_pht6_stage_spec(stage)
    path <- file.path(root, spec[["plan"]])
    if (!file.exists(path)) return(TRUE)
    tryCatch({app_joint_pht6_verify_plan(root, stage); TRUE}, error = function(e) FALSE)
  }, logical(1L))
  health <- app_joint_pht6_all_health(root)
  data.frame(contract = contract$version, preparation_manifest_ok = nrow(prepared) > 0L &&
      all(prepared$verified), fixture_hashes_ok = fixture_ok, all_plan_hashes_ok = all(plan_ok),
    any_worker_failure = any(health$failed > 0L), protected_rows_used =
      sum(fixtures$protected_rows_persisted), status = if (nrow(prepared) && all(prepared$verified) &&
      fixture_ok && all(plan_ok) && !any(health$failed > 0L) &&
      sum(fixtures$protected_rows_persisted) == 0L) "PASS" else "FAIL",
    stringsAsFactors = FALSE)
}
