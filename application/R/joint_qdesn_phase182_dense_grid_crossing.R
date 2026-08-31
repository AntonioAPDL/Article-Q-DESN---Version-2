# Phase182 dense-grid crossing refit and DGP-score stress packet.

app_joint_qdesn_phase182_contract_path <- function() {
  app_path(
    "application/config",
    "joint_qdesn_phase182_dense_grid_crossing_contract_v1.csv"
  )
}

app_joint_qdesn_phase182_cache_root <- function() {
  Sys.getenv(
    "JOINT_QDESN_PHASE182_CACHE_ROOT",
    unset = app_path("application/cache")
  )
}

app_joint_qdesn_phase182_source_cache_root <- function() {
  Sys.getenv(
    "JOINT_QDESN_PHASE182_SOURCE_CACHE_ROOT",
    unset = "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache"
  )
}

app_joint_qdesn_phase182_dirs <- function(
  cache_root = app_joint_qdesn_phase182_cache_root(),
  source_cache_root = app_joint_qdesn_phase182_source_cache_root()
) {
  cache_root <- normalizePath(cache_root, mustWork = FALSE)
  source_cache_root <- normalizePath(source_cache_root, mustWork = FALSE)
  list(
    cache_root = cache_root,
    source_cache_root = source_cache_root,
    phase180_freeze_source = file.path(
      source_cache_root, "joint_qdesn_phase180_balanced_dgp_score_freeze_20260824"
    ),
    phase181_freeze_source = file.path(
      source_cache_root, "joint_qdesn_phase181_score_stability_extension_freeze_20260826"
    ),
    phase181_packet_source = file.path(
      source_cache_root, "joint_qdesn_phase181_score_stability_extension_packet_20260826"
    ),
    fixture_source = file.path(
      source_cache_root, "joint_qdesn_simulation_dgp_fixtures_20260706"
    ),
    dense_fixture_full = file.path(
      cache_root, "joint_qdesn_phase182_dense_grid_fixtures_20260831"
    ),
    fixtures = file.path(
      cache_root, "joint_qdesn_phase182_dense_grid_fixture_shards_20260831"
    ),
    freeze = file.path(
      cache_root, "joint_qdesn_phase182_dense_grid_crossing_freeze_20260831"
    ),
    initialization_work = file.path(
      cache_root, "joint_qdesn_phase182_dense_grid_initialization_work_20260831"
    ),
    chains = file.path(
      cache_root, "joint_qdesn_phase182_dense_grid_crossing_chains_20260831"
    ),
    orchestration = file.path(
      cache_root,
      "joint_qdesn_phase182_dense_grid_crossing_20260831_orchestration"
    ),
    score_work = file.path(
      cache_root, "joint_qdesn_phase182_dense_grid_score_work_20260831"
    ),
    packet = file.path(
      cache_root, "joint_qdesn_phase182_dense_grid_crossing_packet_20260831"
    )
  )
}

app_joint_qdesn_phase182_contract_value <- function(table, name) {
  row <- table[table$contract_name == name, , drop = FALSE]
  if (nrow(row) != 1L) {
    stop(sprintf("Phase182 contract requires one '%s' row.", name), call. = FALSE)
  }
  as.character(row$value[[1L]])
}

app_joint_qdesn_phase182_read_contract <- function(
  path = app_joint_qdesn_phase182_contract_path()
) {
  table <- app_read_csv(path)
  app_check_required_columns(
    table,
    c("contract_section", "contract_name", "value", "value_type", "rationale"),
    "Phase182 dense-grid crossing contract"
  )
  if (anyDuplicated(table$contract_name)) {
    stop("Phase182 contract names must be unique.", call. = FALSE)
  }
  get <- function(name) app_joint_qdesn_phase182_contract_value(table, name)
  num <- function(name) as.numeric(get(name))
  int <- function(name) as.integer(get(name))
  nums <- function(name) as.numeric(trimws(strsplit(get(name), ",", fixed = TRUE)[[1L]]))
  ints <- function(name) as.integer(trimws(strsplit(get(name), ",", fixed = TRUE)[[1L]]))
  bool <- function(name) identical(tolower(get(name)), "true")
  out <- list(
    table = table,
    path = normalizePath(path, mustWork = TRUE),
    version = get("contract_version"),
    expected_scenarios = int("expected_scenarios"),
    expected_models = int("expected_models"),
    expected_final_cells = int("expected_final_cells"),
    expected_reuse_cells = int("expected_reuse_cells"),
    expected_rerun_cells = int("expected_rerun_cells"),
    expected_new_workers = int("expected_new_workers"),
    current_tau = nums("current_tau_grid"),
    tau = nums("tau_grid"),
    weights_qs = nums("trapezoidal_weights"),
    weight_sum = num("weight_sum"),
    primary_metric = get("primary_metric"),
    article_label = get("article_label"),
    score_draws_per_chain = int("score_draws_per_chain"),
    sensitivity_draws_per_chain = int("sensitivity_draws_per_chain"),
    chunk_size = int("score_chunk_size"),
    primary_pairing_seed = int("primary_pairing_seed"),
    sensitivity_pairing_seeds = ints("sensitivity_pairing_seeds"),
    contrast_pairing_seed = int("contrast_pairing_seed"),
    credible_interval = num("credible_interval"),
    score_rank_rhat_ceiling = num("score_rank_rhat_ceiling"),
    score_bulk_ess_floor = num("score_bulk_ess_floor"),
    score_tail_ess_floor = num("score_tail_ess_floor"),
    raw_crossing_rate_review = num("raw_crossing_rate_review"),
    standardized_adjustment_review = num("standardized_adjustment_review"),
    regret_tolerance = num("regret_tolerance"),
    practical_relative_margin = num("practical_relative_margin"),
    posterior_probability_floor = num("posterior_probability_floor"),
    protected_replicate_direction_floor = num("protected_replicate_direction_floor"),
    oracle_recovery_ratio_ceiling = num("oracle_recovery_ratio_ceiling"),
    analytic_integration_tolerance = num("analytic_integration_tolerance"),
    monte_carlo_tolerance = num("monte_carlo_tolerance"),
    n_chains = int("n_chains_per_cell"),
    al_n_iter = int("al_n_iter"), al_burn = int("al_burn"),
    al_thin = int("al_thin"), exal_n_iter = int("exal_n_iter"),
    exal_burn = int("exal_burn"), exal_thin = int("exal_thin"),
    sigma_upper_multiplier = num("sigma_upper_multiplier"),
    chain_seed_base = int("chain_seed_base"),
    tau_seed_stride = int("tau_seed_stride"),
    default_concurrent_workers = int("default_concurrent_workers"),
    case_specific_controls_preserved = bool("case_specific_controls_preserved"),
    retuning_allowed = bool("desn_or_tau0_retuning_allowed"),
    article_fixture_selection_allowed = bool("article_fixture_selection_allowed"),
    global_specification_selected = bool("global_specification_selected"),
    partial_publication_allowed = bool("partial_publication_allowed"),
    draw_reuse_allowed_after_grid_change = bool("draw_reuse_allowed_after_grid_change"),
    article_assets_mutated_by_prepare_or_workers =
      bool("article_assets_mutated_by_prepare_or_workers"),
    dense_grid_authorized = bool("dense_grid_authorized"),
    claim_status = get("claim_status")
  )
  app_joint_qvp_validate_tau_grid(out$current_tau)
  app_joint_qvp_validate_tau_grid(out$tau)
  expected_tau <- seq(0.05, 0.95, by = 0.05)
  expected_weights <- c(
    (out$tau[[2L]] - out$tau[[1L]]) / 2,
    (out$tau[3:length(out$tau)] - out$tau[1:(length(out$tau) - 2L)]) / 2,
    (out$tau[[length(out$tau)]] - out$tau[[length(out$tau) - 1L]]) / 2
  )
  if (!isTRUE(all.equal(out$tau, expected_tau, tolerance = 1e-14)) ||
      !isTRUE(all.equal(out$weights_qs, expected_weights, tolerance = 1e-14)) ||
      abs(sum(out$weights_qs) - out$weight_sum) > 1e-14 ||
      out$expected_final_cells != out$expected_scenarios * out$expected_models ||
      out$expected_reuse_cells != 0L ||
      out$expected_rerun_cells != out$expected_final_cells ||
      out$expected_new_workers != out$expected_rerun_cells * out$n_chains ||
      !out$case_specific_controls_preserved || out$retuning_allowed ||
      out$article_fixture_selection_allowed || out$global_specification_selected ||
      out$partial_publication_allowed ||
      out$draw_reuse_allowed_after_grid_change ||
      out$article_assets_mutated_by_prepare_or_workers ||
      !out$dense_grid_authorized) {
    stop("Phase182 contract violates the dense-grid crossing design.", call. = FALSE)
  }
  out
}

app_joint_qdesn_phase182_verify_manifest <- function(path, source_id) {
  check <- app_joint_exqdesn_verify_manifest(path, source_id)
  if (!nrow(check) || any(check$status != "pass")) {
    stop(sprintf("Phase182 source '%s' failed manifest verification.", source_id),
         call. = FALSE)
  }
  cbind(
    source_id = source_id, source_dir = normalizePath(path, mustWork = TRUE),
    check, stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase182_cell_hash <- function(row) {
  row <- row[, setdiff(names(row), "source_control_row_sha256"), drop = FALSE]
  app_joint_exqdesn_phase171_row_hash(row)
}

app_joint_qdesn_phase182_source_audit <- function(dirs, contract) {
  source_checks <- app_joint_qdesn_bind_rows(list(
    app_joint_qdesn_phase182_verify_manifest(
      dirs$phase180_freeze_source, "phase182_source_phase180_freeze"
    ),
    app_joint_qdesn_phase182_verify_manifest(
      dirs$phase181_freeze_source, "phase182_source_phase181_freeze"
    ),
    app_joint_qdesn_phase182_verify_manifest(
      dirs$phase181_packet_source, "phase182_source_phase181_packet"
    ),
    app_joint_qdesn_phase182_verify_manifest(
      dirs$fixture_source, "phase182_source_fixtures"
    )
  ))
  phase181_gate <- app_read_csv(file.path(
    dirs$phase181_packet_source, "final_gate_assessment.csv"
  ))
  phase181_summary <- app_read_csv(file.path(
    dirs$phase181_packet_source, "posterior_dgp_integrated_acrps_summary.csv"
  ))
  phase181_source <- app_read_csv(file.path(
    dirs$phase181_packet_source, "final_selected_source_registry.csv"
  ))
  phase180_freeze <- app_joint_qdesn_phase180_load_freeze(
    dirs$phase180_freeze_source
  )
  if (nrow(phase181_gate) != 1L ||
      phase181_gate$implementation_hard_gates[[1L]] != "pass" ||
      phase181_gate$final_cells[[1L]] != contract$expected_final_cells ||
      phase181_gate$contract_crossing_pairs[[1L]] != 0L ||
      !isTRUE(as.logical(phase181_gate$case_specific_controls_preserved[[1L]])) ||
      nrow(phase181_summary) != contract$expected_final_cells ||
      nrow(phase180_freeze$registry) != contract$expected_final_cells) {
    stop("Phase182 source authority failed the current-grid hard gates.", call. = FALSE)
  }
  cells <- phase180_freeze$registry
  if (nrow(cells) != contract$expected_final_cells ||
      anyNA(cells$case_id) || anyDuplicated(cells$case_id) ||
      length(unique(cells$scenario_id)) != contract$expected_scenarios ||
      length(unique(cells$source_model_id)) != contract$expected_models ||
      any(!is.finite(cells$tau0)) || any(!is.finite(cells$zeta2))) {
    stop("Phase182 could not recover 32 complete case-specific controls.",
         call. = FALSE)
  }
  phase181_cases <- phase181_source[!duplicated(phase181_source$case_id), , drop = FALSE]
  phase181_cases <- phase181_cases[match(cells$case_id, phase181_cases$case_id), , drop = FALSE]
  phase181_summary_match <- phase181_summary[
    match(cells$case_id, phase181_summary$case_id), , drop = FALSE
  ]
  if (anyNA(phase181_cases$case_id) || anyNA(phase181_summary_match$case_id)) {
    stop("Phase182 could not match Phase181 authority to Phase180 controls.",
         call. = FALSE)
  }
  cells$phase181_selected_source_kind <- phase181_cases$source_kind
  cells$phase181_selected_source_role <- phase181_cases$selection_source_role
  cells$phase181_source_control_row_sha256 <- phase181_cases$source_control_row_sha256
  parent_control_hash <- cells$source_control_row_sha256
  cells$source_action <- "dense_grid_refit"
  cells$source_phase <- "phase182_dense_grid_from_phase181_selected_controls"
  cells$source_kind <- "phase182_dense_grid_refit"
  cells$source_dir <- dirs$phase180_freeze_source
  cells$dgp_replicate_id <- "article_fixture_dense_grid"
  cells$validation_partition <- "dense_grid_crossing_evaluation"
  cells$article_fixture_used_for_selection <- FALSE
  cells$global_specification_selected <- FALSE
  cells$source_control_file_sha256 <- app_sha256_file(file.path(
    dirs$phase180_freeze_source, "artifact_manifest.csv"
  ))
  cells$source_control_row_sha256 <- NA_character_
  cells$source_control_row_sha256 <- vapply(
    seq_len(nrow(cells)), function(ii) {
      app_joint_qdesn_phase182_cell_hash(cells[ii, , drop = FALSE])
    }, character(1L)
  )
  cells$cell_index <- seq_len(nrow(cells))
  cells$mcmc_case_id <- cells$case_id
  cells$phase182_tau_grid <- app_joint_qdesn_format_tau(contract$tau)
  control_audit <- data.frame(
    case_id = cells$case_id,
    scenario_id = cells$scenario_id,
    source_model_id = cells$source_model_id,
    phase180_control_row_sha256 = parent_control_hash,
    phase181_source_control_row_sha256 = cells$phase181_source_control_row_sha256,
    phase182_control_row_sha256 = cells$source_control_row_sha256,
    tau0 = cells$tau0,
    zeta2 = cells$zeta2,
    alpha_prior_sd = cells$alpha_prior_sd,
    gamma_slice_width = cells$gamma_slice_width,
    gamma_slice_max_steps = cells$gamma_slice_max_steps,
    desn_or_tau0_changed = FALSE,
    phase181_materialized_control_hash_available =
      !is.na(cells$phase181_source_control_row_sha256),
    source_control_match = ifelse(
      is.na(cells$phase181_source_control_row_sha256),
      NA,
      cells$phase181_source_control_row_sha256 == parent_control_hash
    ),
    status = "pass",
    stringsAsFactors = FALSE
  )
  list(
    source_checks = source_checks,
    phase181_gate = phase181_gate,
    phase181_summary = phase181_summary,
    phase181_source_registry = phase181_source,
    phase180_registry = phase180_freeze$registry,
    registry = cells,
    control_audit = control_audit
  )
}

app_joint_qdesn_phase182_dense_registry_rows <- function(registry, tau) {
  registry <- registry[app_as_bool_vec(registry$enabled), , drop = FALSE]
  registry$tau_grid <- paste(
    format(as.numeric(tau), nsmall = 2L, trim = TRUE, scientific = FALSE),
    collapse = ","
  )
  registry
}

app_joint_qdesn_phase182_dense_fixture_full_complete <- function(
  path, scenario_ids, tau
) {
  required <- c(
    "run_config.csv", "frozen_registry.csv", "scenario_summary.csv",
    "observed_series.csv", "design_matrix.csv", "true_quantile_wide.csv",
    "true_quantile_long.csv", "split_metadata.csv", "dgp_parameters.csv",
    "forecast_origin_plan.csv", "oracle_policy.csv", "crossing_summary.csv",
    "fixture_validation.csv", "provenance.csv", "README.md",
    "artifact_manifest.csv"
  )
  if (!dir.exists(path) || any(!file.exists(file.path(path, required)))) return(FALSE)
  artifacts <- tryCatch(
    app_joint_qdesn_load_fixture_artifacts(path),
    error = function(e) NULL
  )
  if (is.null(artifacts) ||
      any(artifacts$manifest_verification$status != "pass") ||
      any(artifacts$fixture_validation$status != "pass")) return(FALSE)
  summary <- artifacts$scenario_summary
  truth <- artifacts$true_long
  !is.null(summary) && !is.null(truth) &&
    identical(sort(unique(summary$scenario_id)), sort(unique(scenario_ids))) &&
    all(vapply(summary$tau_grid, function(x) {
      identical(
        app_joint_qvp_parse_tau_spec(x),
        as.numeric(tau)
      )
    }, logical(1L))) &&
    length(unique(round(as.numeric(truth$tau), 12L))) == length(tau)
}

app_joint_qdesn_phase182_compare_table <- function(source, dense, scenario_ids, table_name) {
  source <- source[source$scenario_id %in% scenario_ids, , drop = FALSE]
  dense <- dense[dense$scenario_id %in% scenario_ids, , drop = FALSE]
  if (!identical(names(source), names(dense))) {
    if (!setequal(names(source), names(dense))) {
      return(data.frame(
        table_name = table_name, source_rows = nrow(source), dense_rows = nrow(dense),
        identical_columns = FALSE, max_numeric_abs_diff = NA_real_,
        status = "fail", stringsAsFactors = FALSE
      ))
    }
    dense <- dense[names(source)]
  }
  key <- intersect(c("scenario_id", "full_time_index", "time_index", "role_index"), names(source))
  if (length(key)) {
    source <- source[do.call(order, source[key]), , drop = FALSE]
    dense <- dense[do.call(order, dense[key]), , drop = FALSE]
  }
  numeric_cols <- names(source)[vapply(source, is.numeric, logical(1L))]
  char_cols <- setdiff(names(source), numeric_cols)
  max_diff <- if (length(numeric_cols)) {
    max(abs(as.matrix(source[numeric_cols]) - as.matrix(dense[numeric_cols])), na.rm = TRUE)
  } else 0
  char_equal <- if (length(char_cols)) {
    identical(
      lapply(source[char_cols], as.character),
      lapply(dense[char_cols], as.character)
    )
  } else TRUE
  pass <- nrow(source) == nrow(dense) && char_equal &&
    is.finite(max_diff) && max_diff <= 1e-10
  data.frame(
    table_name = table_name, source_rows = nrow(source), dense_rows = nrow(dense),
    identical_columns = TRUE, max_numeric_abs_diff = max_diff,
    status = if (pass) "pass" else "fail", stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase182_dense_fixture_audit <- function(
  source_dir, dense_dir, scenario_ids, tau
) {
  source <- app_joint_qdesn_load_fixture_artifacts(source_dir)
  dense <- app_joint_qdesn_load_fixture_artifacts(dense_dir)
  identity <- app_joint_qdesn_bind_rows(list(
    app_joint_qdesn_phase182_compare_table(
      source$observed, dense$observed, scenario_ids, "observed_series"
    ),
    app_joint_qdesn_phase182_compare_table(
      source$design, dense$design, scenario_ids, "design_matrix"
    )
  ))
  truth <- dense$true_wide[dense$true_wide$scenario_id %in% scenario_ids, , drop = FALSE]
  q_cols <- grep("^q_tau_", names(truth), value = TRUE)
  truth_matrix <- as.matrix(truth[q_cols])
  truth_audit <- data.frame(
    scenario_count = length(unique(truth$scenario_id)),
    tau_count = length(tau),
    true_quantile_columns = length(q_cols),
    true_quantile_rows = nrow(truth),
    all_finite = all(is.finite(truth_matrix)),
    all_monotone = all(apply(truth_matrix, 1L, function(x) {
      all(diff(x) >= -1e-10)
    })),
    source_observed_manifest_sha256 = app_sha256_file(file.path(
      source_dir, "artifact_manifest.csv"
    )),
    dense_observed_manifest_sha256 = app_sha256_file(file.path(
      dense_dir, "artifact_manifest.csv"
    )),
    status = "pass",
    stringsAsFactors = FALSE
  )
  if (any(identity$status != "pass") || truth_audit$true_quantile_columns != length(tau) ||
      !truth_audit$all_finite || !truth_audit$all_monotone) {
    truth_audit$status <- "fail"
  }
  list(identity = identity, truth = truth_audit)
}

app_joint_qdesn_phase182_materialize_dense_fixture_full <- function(
  source_dir, out_dir, scenario_ids, tau, force = FALSE
) {
  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  if (!force && app_joint_qdesn_phase182_dense_fixture_full_complete(
    final_dir, scenario_ids, tau
  )) {
    audit <- app_joint_qdesn_phase182_dense_fixture_audit(
      source_dir, final_dir, scenario_ids, tau
    )
    if (all(audit$identity$status == "pass") && all(audit$truth$status == "pass")) {
      return(list(out_dir = final_dir, audit = audit, reused = TRUE))
    }
  }
  source_check <- app_joint_qdesn_phase182_verify_manifest(
    source_dir, "phase182_dense_fixture_source"
  )
  registry <- app_read_csv(file.path(source_dir, "frozen_registry.csv"))
  registry <- registry[registry$scenario_id %in% scenario_ids, , drop = FALSE]
  registry <- app_joint_qdesn_phase182_dense_registry_rows(registry, tau)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_joint_qdesn_materialize_simulation_fixtures(
    out_dir = tmp, registry = registry, scenario_ids = scenario_ids
  )
  audit <- app_joint_qdesn_phase182_dense_fixture_audit(
    source_dir, tmp, scenario_ids, tau
  )
  if (any(source_check$status != "pass") ||
      any(audit$identity$status != "pass") || any(audit$truth$status != "pass")) {
    stop("Phase182 dense fixture materialization failed source identity checks.",
         call. = FALSE)
  }
  if (dir.exists(final_dir)) {
    quarantine <- paste0(
      final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S")
    )
    if (!file.rename(final_dir, quarantine)) {
      stop("Could not quarantine prior Phase182 dense fixture.", call. = FALSE)
    }
  }
  if (!file.rename(tmp, final_dir)) {
    stop("Could not publish Phase182 dense fixture.", call. = FALSE)
  }
  list(out_dir = final_dir, audit = audit, reused = FALSE)
}

app_joint_qdesn_phase182_fixture_shards_complete <- function(path, scenario_ids) {
  required <- c(
    "fixture_shard_manifest.csv", "scenario_summary.csv", "split_metadata.csv",
    "forecast_origin_plan.csv", "frozen_registry.csv", "source_identity.csv",
    "README.md", "artifact_manifest.csv"
  )
  if (!dir.exists(path) || any(!file.exists(file.path(path, required)))) return(FALSE)
  check <- tryCatch(
    app_joint_exqdesn_verify_manifest(path, "phase182_fixture_shards"),
    error = function(e) NULL
  )
  if (is.null(check) || any(check$status != "pass")) return(FALSE)
  manifest <- app_read_csv(file.path(path, "fixture_shard_manifest.csv"))
  paths <- file.path(path, manifest$relative_path)
  identical(sort(unique(manifest$scenario_id)), sort(scenario_ids)) &&
    nrow(manifest) == 3L * length(scenario_ids) && all(file.exists(paths)) &&
    all(tolower(vapply(paths, app_sha256_file, character(1L))) ==
          tolower(manifest$sha256))
}

app_joint_qdesn_phase182_materialize_fixture_shards <- function(
  source_dir, out_dir, scenario_ids, force = FALSE
) {
  scenario_ids <- sort(unique(as.character(scenario_ids)))
  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  if (!force && app_joint_qdesn_phase182_fixture_shards_complete(
    final_dir, scenario_ids
  )) {
    return(list(
      out_dir = final_dir,
      shard_manifest = app_read_csv(file.path(final_dir, "fixture_shard_manifest.csv")),
      reused = TRUE
    ))
  }
  source_check <- app_joint_qdesn_phase182_verify_manifest(
    source_dir, "phase182_fixture_shard_source"
  )
  artifacts <- app_joint_qdesn_load_fixture_artifacts(source_dir)
  absent <- setdiff(scenario_ids, artifacts$scenario_summary$scenario_id)
  if (length(absent)) {
    stop(sprintf("Dense fixture lacks scenarios: %s", paste(absent, collapse = ", ")),
         call. = FALSE)
  }
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  shard_rows <- list()
  cursor <- 1L
  sources <- list(
    observed = artifacts$observed,
    design = artifacts$design,
    true_wide = artifacts$true_wide
  )
  for (scenario_id in scenario_ids) {
    for (artifact in names(sources)) {
      table <- sources[[artifact]]
      table <- table[table$scenario_id == scenario_id, , drop = FALSE]
      if (!nrow(table)) {
        stop("Phase182 fixture sharding produced an empty table.", call. = FALSE)
      }
      relative <- paste0(scenario_id, "__", artifact, ".csv")
      path <- app_joint_qvp_write_csv(table, file.path(tmp, relative))
      shard_rows[[cursor]] <- data.frame(
        scenario_id = scenario_id, artifact = artifact,
        relative_path = relative, size_bytes = as.numeric(file.info(path)$size),
        sha256 = app_sha256_file(path), stringsAsFactors = FALSE
      )
      cursor <- cursor + 1L
    }
  }
  subset_rows <- function(x) x[x$scenario_id %in% scenario_ids, , drop = FALSE]
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase182 dense-grid fixture shards", "",
    "These are row-preserving shards of the Phase182 dense-grid oracle fixture.",
    "The observed response and DESN design rows are verified against the frozen",
    "current-grid article fixture; only the oracle quantile grid is denser.",
    "The article fixture is evaluation-only and cannot select DESN or RHS controls."
  ), readme, useBytes = TRUE)
  shard_manifest <- app_joint_qdesn_bind_rows(shard_rows)
  source_identity <- data.frame(
    source_dir = normalizePath(source_dir),
    source_manifest_sha256 = app_sha256_file(file.path(source_dir, "artifact_manifest.csv")),
    scenario_count = length(scenario_ids), row_preserving_shards = TRUE,
    dense_grid_refit = TRUE, stringsAsFactors = FALSE
  )
  paths <- c(
    source_manifest_verification = write(
      source_check, "source_manifest_verification.csv"
    ),
    source_identity = write(source_identity, "source_identity.csv"),
    fixture_shard_manifest = write(shard_manifest, "fixture_shard_manifest.csv"),
    scenario_summary = write(
      subset_rows(artifacts$scenario_summary), "scenario_summary.csv"
    ),
    split_metadata = write(
      subset_rows(artifacts$split_metadata), "split_metadata.csv"
    ),
    forecast_origin_plan = write(
      subset_rows(artifacts$forecast_origin_plan), "forecast_origin_plan.csv"
    ),
    frozen_registry = write(
      subset_rows(artifacts$frozen_registry), "frozen_registry.csv"
    ),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(
      final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S")
    )
    if (!file.rename(final_dir, quarantine)) {
      stop("Could not quarantine prior Phase182 fixture shards.", call. = FALSE)
    }
  }
  if (!file.rename(tmp, final_dir)) {
    stop("Could not publish Phase182 fixture shards.", call. = FALSE)
  }
  if (!app_joint_qdesn_phase182_fixture_shards_complete(final_dir, scenario_ids)) {
    stop("Phase182 fixture shard manifest failed.", call. = FALSE)
  }
  list(out_dir = final_dir, shard_manifest = shard_manifest, reused = FALSE)
}

app_joint_qdesn_phase182_init_rows <- function(fit, cell, method_id) {
  likelihood <- as.character(cell$likelihood_family[[1L]])
  fit_for_init <- fit
  if (identical(likelihood, "AL")) {
    # Independent AL fits expose an NA gamma placeholder for table alignment.
    # Gamma is not part of the AL parameter contract and must not enter MCMC.
    fit_for_init$gamma_mean <- NULL
  } else if (!identical(likelihood, "exAL")) {
    stop("Phase182 initialization has an unknown likelihood family.", call. = FALSE)
  } else if (is.null(fit_for_init$gamma_mean) ||
             any(!is.finite(as.numeric(fit_for_init$gamma_mean)))) {
    stop("Phase182 exAL initialization requires finite gamma values.", call. = FALSE)
  }
  app_joint_qdesn_phase180_init_rows(fit_for_init, cell, method_id)
}

app_joint_qdesn_phase182_strict_order_alpha <- function(
  alpha, alpha_min_spacing = 0, y = NULL
) {
  alpha <- as.numeric(alpha)
  alpha_min_spacing <- as.numeric(alpha_min_spacing)[[1L]]
  if (!length(alpha) || any(!is.finite(alpha)) ||
      !is.finite(alpha_min_spacing) || alpha_min_spacing < 0) {
    stop("Phase182 ordered-alpha inputs are invalid.", call. = FALSE)
  }
  scale_candidates <- c(1, max(abs(alpha)))
  if (!is.null(y)) {
    y <- as.numeric(y)
    y <- y[is.finite(y)]
    if (length(y)) {
      scale_candidates <- c(
        scale_candidates, stats::mad(y), stats::IQR(y), stats::sd(y)
      )
    }
  }
  data_scale <- max(scale_candidates[is.finite(scale_candidates)], na.rm = TRUE)
  numerical_gap <- max(sqrt(.Machine$double.eps) * data_scale, 1.0e-10)
  required_gap <- alpha_min_spacing + numerical_gap
  ordered <- sort(alpha)
  repaired <- ordered
  if (length(repaired) > 1L) {
    for (k in 2:length(repaired)) {
      repaired[[k]] <- max(repaired[[k]], repaired[[k - 1L]] + required_gap)
    }
  }
  repaired <- repaired + mean(ordered) - mean(repaired)
  if (length(repaired) > 1L && any(diff(repaired) <= alpha_min_spacing)) {
    stop("Phase182 could not construct strictly feasible ordered intercepts.",
         call. = FALSE)
  }
  attr(repaired, "max_abs_adjustment") <- max(abs(repaired - alpha))
  attr(repaired, "numerical_gap") <- numerical_gap
  repaired
}

app_joint_qdesn_phase182_repair_joint_warm_start <- function(
  warm, cell, fixture
) {
  K <- length(fixture$tau)
  p <- ncol(fixture$Z)
  required <- c("beta_mean", "alpha_mean", "sigma_mean")
  if (!is.list(warm) || any(!required %in% names(warm)) ||
      length(warm$beta_mean) != K * p || length(warm$alpha_mean) != K ||
      length(warm$sigma_mean) != K ||
      any(!is.finite(c(warm$beta_mean, warm$alpha_mean, warm$sigma_mean))) ||
      any(warm$sigma_mean <= 0)) {
    stop("Phase182 joint exAL warm start is malformed.", call. = FALSE)
  }
  repaired <- app_joint_qdesn_phase182_strict_order_alpha(
    warm$alpha_mean,
    alpha_min_spacing = as.numeric(cell$alpha_min_spacing[[1L]]),
    y = fixture$y
  )
  adjustment <- attr(repaired, "max_abs_adjustment")
  warm$alpha_mean <- as.numeric(repaired)
  warm$alpha <- NULL
  attr(warm, "phase182_alpha_adjustment") <- adjustment
  warm
}

app_joint_qdesn_phase182_independent_al_warm_start <- function(cell, fixture) {
  controls <- app_joint_qdesn_phase122_controls_from_row(cell, n_cores = 1L)
  warm <- app_joint_qdesn_fit_independent_readiness(
    fixture, controls, likelihood = "al"
  )
  warm$gamma_mean <- app_joint_qdesn_gamma_init_for_policy(
    fixture$tau, controls
  )
  warm
}

app_joint_qdesn_phase182_is_ordering_error <- function(error) {
  inherits(error, "error") && grepl(
    "Ordered intercept bounds collapsed", conditionMessage(error), fixed = TRUE
  )
}

app_joint_qdesn_phase182_fit_exal_initialization <- function(cell, fixture) {
  candidate <- cell
  candidate$inference_method_id <- "VB1_structured_v"
  args <- app_joint_exqdesn_phase166_control_args(candidate, fixture)
  fallback_reason <- NA_character_
  warm_source <- "phase166_vb0_point_v"
  warm <- tryCatch(
    app_joint_exqdesn_phase166_vb0_warm_start(candidate, fixture),
    error = function(e) e
  )
  if (inherits(warm, "error")) {
    if (!app_joint_qdesn_phase182_is_ordering_error(warm)) stop(warm)
    fallback_reason <- conditionMessage(warm)
    warm_source <- "dense_grid_independent_al_ordering_fallback"
    warm <- app_joint_qdesn_phase182_independent_al_warm_start(cell, fixture)
  }
  warm <- if (identical(cell$fit_structure[[1L]], "joint")) {
    app_joint_qdesn_phase182_repair_joint_warm_start(warm, cell, fixture)
  } else warm
  alpha_adjustment <- attr(warm, "phase182_alpha_adjustment") %||% 0
  fit <- do.call(
    if (identical(cell$fit_structure[[1L]], "joint")) {
      app_joint_exqdesn_fit_vb_dispatch
    } else app_joint_exqdesn_fit_independent_vb_dispatch,
    c(list(
      method_id = "VB1_structured_v", y = fixture$y, Z = fixture$Z,
      tau = fixture$tau, init = warm
    ), args)
  )
  attr(fit, "phase182_warm_start_source") <- warm_source
  attr(fit, "phase182_warm_start_fallback_reason") <- fallback_reason
  attr(fit, "phase182_warm_start_alpha_adjustment") <- alpha_adjustment
  fit
}

app_joint_qdesn_phase182_initialize_cell <- function(cell, fixture_dir) {
  loaded <- app_joint_qdesn_phase180_load_fixture(cell$scenario_id[[1L]], fixture_dir)
  fixture <- loaded$fixture
  started <- proc.time()[["elapsed"]]
  if (cell$likelihood_family[[1L]] == "exAL") {
    fit <- app_joint_qdesn_phase182_fit_exal_initialization(cell, fixture)
    method_id <- "VB1_structured_v_dense_grid"
  } else {
    spec <- app_joint_qdesn_phase122_select_spec(cell$source_model_id[[1L]])
    controls <- app_joint_qdesn_phase122_controls_from_row(cell, n_cores = 1L)
    fit <- app_joint_qdesn_fit_model_adaptive(fixture, spec, controls)
    method_id <- if (cell$fit_structure[[1L]] == "independent") {
      "dense_grid_independent_al_vb"
    } else "dense_grid_joint_al_vb"
  }
  elapsed <- proc.time()[["elapsed"]] - started
  init <- app_joint_qdesn_phase182_init_rows(fit, cell, method_id)
  qhat <- app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau)
  contract <- app_joint_qdesn_apply_monotone_contract(qhat, fixture$tau)
  finite <- all(is.finite(c(
    fit$beta_mean, fit$alpha_mean, fit$sigma_mean,
    if (!is.null(fit$gamma_mean)) fit$gamma_mean else numeric(), qhat
  ))) && all(fit$sigma_mean > 0)
  vb_converged <- if (!is.null(fit$converged)) {
    isTRUE(fit$converged)
  } else if (!is.null(fit$fits) && length(fit$fits)) {
    all(vapply(fit$fits, function(x) isTRUE(x$converged), logical(1L)))
  } else {
    NA
  }
  audit <- data.frame(
    phase_id = "joint_qdesn_phase182_dense_grid_crossing_v1",
    mcmc_case_id = cell$mcmc_case_id[[1L]], case_id = cell$case_id[[1L]],
    scenario_id = cell$scenario_id[[1L]],
    source_model_id = cell$source_model_id[[1L]],
    likelihood_family = cell$likelihood_family[[1L]],
    fit_structure = cell$fit_structure[[1L]],
    initialization_method_id = method_id,
    dense_tau_count = length(fixture$tau),
    finite_initialization = finite,
    vb_converged = vb_converged,
    fit_raw_crossing_pairs = sum(contract$raw_crossing$n_crossing_pairs),
    fit_contract_crossing_pairs = sum(contract$contract_crossing$n_crossing_pairs),
    warm_start_source = attr(fit, "phase182_warm_start_source") %||% NA_character_,
    warm_start_fallback_reason = attr(
      fit, "phase182_warm_start_fallback_reason"
    ) %||% NA_character_,
    warm_start_alpha_adjustment = attr(
      fit, "phase182_warm_start_alpha_adjustment"
    ) %||% NA_real_,
    elapsed_seconds = elapsed,
    status = if (finite && sum(contract$contract_crossing$n_crossing_pairs) == 0L) {
      "pass"
    } else "fail",
    stringsAsFactors = FALSE
  )
  list(init = init, audit = audit)
}

app_joint_qdesn_phase182_init_cache_complete <- function(path, identity) {
  if (!file.exists(file.path(path, "artifact_manifest.csv"))) return(FALSE)
  check <- tryCatch(
    app_joint_exqdesn_verify_manifest(path, "phase182_initialization_cache"),
    error = function(e) NULL
  )
  if (is.null(check) || any(check$status != "pass")) return(FALSE)
  actual <- tryCatch(
    app_read_csv(file.path(path, "cache_identity.csv")),
    error = function(e) NULL
  )
  if (is.null(actual) || nrow(actual) != 1L) return(FALSE)
  fields <- names(identity)
  if (!all(fields %in% names(actual))) return(FALSE)
  identical(
    vapply(actual[1L, fields, drop = FALSE], as.character, character(1L)),
    vapply(identity[1L, fields, drop = FALSE], as.character, character(1L))
  )
}

app_joint_qdesn_phase182_initialize_cached <- function(
  cell, fixture_dir, work_dir, force = FALSE
) {
  path <- file.path(work_dir, cell$mcmc_case_id[[1L]])
  identity <- data.frame(
    mcmc_case_id = cell$mcmc_case_id[[1L]],
    source_control_row_sha256 = cell$source_control_row_sha256[[1L]],
    fixture_manifest_sha256 = app_sha256_file(file.path(
      fixture_dir, "artifact_manifest.csv"
    )),
    code_commit = app_joint_exqdesn_phase171_git_value(c("rev-parse", "HEAD")),
    dense_tau_count = length(app_joint_qvp_parse_tau_spec(
      app_read_csv(file.path(fixture_dir, "scenario_summary.csv"))$tau_grid[[1L]]
    )),
    stringsAsFactors = FALSE
  )
  if (!force && app_joint_qdesn_phase182_init_cache_complete(path, identity)) {
    return(list(
      init = app_read_csv(file.path(path, "vb_initialization.csv")),
      audit = app_read_csv(file.path(path, "vb_initialization_audit.csv")),
      cache_status = "reused_verified"
    ))
  }
  result <- app_joint_qdesn_phase182_initialize_cell(cell, fixture_dir)
  tmp <- paste0(path, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase182 compact VB initialization cache", "",
    "This cache is keyed by code commit, dense-grid fixture manifest,",
    "and frozen case-specific control-row hash.",
    "It retains compact initialization values and diagnostics, not fitted R objects."
  ), readme, useBytes = TRUE)
  paths <- c(
    vb_initialization = app_joint_qvp_write_csv(
      result$init, file.path(tmp, "vb_initialization.csv")
    ),
    vb_initialization_audit = app_joint_qvp_write_csv(
      result$audit, file.path(tmp, "vb_initialization_audit.csv")
    ),
    cache_identity = app_joint_qvp_write_csv(
      identity, file.path(tmp, "cache_identity.csv")
    ),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(path)) {
    quarantine <- paste0(
      path, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S")
    )
    if (!file.rename(path, quarantine)) {
      stop("Could not quarantine stale Phase182 initialization cache.", call. = FALSE)
    }
  }
  if (!file.rename(tmp, path) ||
      !app_joint_qdesn_phase182_init_cache_complete(path, identity)) {
    stop("Phase182 initialization cache failed atomic publication.", call. = FALSE)
  }
  result$cache_status <- "computed"
  result
}

app_joint_qdesn_phase182_worker_plan <- function(cells, dirs, contract) {
  rows <- list(); worker_id <- 0L
  for (ii in seq_len(nrow(cells))) {
    for (chain_id in seq_len(contract$n_chains)) {
      worker_id <- worker_id + 1L
      row <- cells[ii, , drop = FALSE]
      row$worker_id <- worker_id
      row$chain_id <- chain_id
      row$wave_id <- as.integer(ceiling(
        worker_id / contract$default_concurrent_workers
      ))
      row$chain_seed <- as.integer(
        contract$chain_seed_base + ii * 250000L + chain_id * 10000L
      )
      row$tau_seed_stride <- contract$tau_seed_stride
      row$sigma_upper_multiplier <- contract$sigma_upper_multiplier
      row$seed_role <- "phase182_dense_grid_crossing_chain"
      row$n_chains <- contract$n_chains
      row$n_iter <- if (row$likelihood_family[[1L]] == "exAL") {
        contract$exal_n_iter
      } else contract$al_n_iter
      row$burn <- if (row$likelihood_family[[1L]] == "exAL") {
        contract$exal_burn
      } else contract$al_burn
      row$thin <- if (row$likelihood_family[[1L]] == "exAL") {
        contract$exal_thin
      } else contract$al_thin
      row$n_keep <- as.integer((row$n_iter - row$burn) / row$thin)
      row$inference_method_id <- if (row$likelihood_family[[1L]] == "exAL") {
        "M0_v_collapsed_support_logit"
      } else "AL_latent_GIG_Gibbs"
      row$worker_output_dir <- file.path(
        dirs$chains, "cases", row$mcmc_case_id[[1L]],
        sprintf("chain_%02d", chain_id)
      )
      rows[[worker_id]] <- row
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  if (nrow(out) != contract$expected_new_workers ||
      anyDuplicated(out$worker_id) || anyDuplicated(out$chain_seed) ||
      anyDuplicated(paste(out$mcmc_case_id, out$chain_id)) ||
      any(out$chain_seed >= .Machine$integer.max) ||
      any(table(out$mcmc_case_id) != contract$n_chains) ||
      any(out$n_keep != 5000L)) {
    stop("Phase182 worker plan has invalid counts, budgets, or seeds.", call. = FALSE)
  }
  out
}

app_joint_qdesn_phase182_load_freeze <- function(freeze_dir) {
  check <- app_joint_exqdesn_verify_manifest(freeze_dir, "phase182_freeze")
  if (any(check$status != "pass")) stop("Phase182 freeze manifest failed.", call. = FALSE)
  contract <- app_joint_qdesn_phase182_read_contract(
    file.path(freeze_dir, "phase182_dense_grid_contract.csv")
  )
  out <- list(
    dir = normalizePath(freeze_dir), verification = check,
    contract = contract,
    config = app_read_csv(file.path(freeze_dir, "run_config.csv")),
    registry = app_read_csv(file.path(freeze_dir, "final_selected_cell_registry.csv")),
    controls = app_read_csv(file.path(freeze_dir, "rerun_cell_plan.csv")),
    plan = app_read_csv(file.path(freeze_dir, "worker_plan.csv")),
    components = app_read_csv(file.path(freeze_dir, "component_seed_plan.csv")),
    init = app_read_csv(file.path(freeze_dir, "vb_initialization.csv")),
    starts = app_read_csv(file.path(freeze_dir, "chain_start_values.csv")),
    readiness = app_read_csv(file.path(freeze_dir, "readiness_assessment.csv"))
  )
  if (nrow(out$registry) != contract$expected_final_cells ||
      nrow(out$controls) != contract$expected_rerun_cells ||
      nrow(out$plan) != contract$expected_new_workers ||
      any(out$readiness$gate_status != "pass")) {
    stop("Phase182 freeze contents differ from the dense-grid contract.", call. = FALSE)
  }
  out
}

app_joint_qdesn_phase182_prepare <- function(
  cache_root = app_joint_qdesn_phase182_cache_root(),
  source_cache_root = app_joint_qdesn_phase182_source_cache_root(),
  out_dir = NULL, fixture_dir = NULL, n_vb_cores = 8L, force = FALSE
) {
  dirs <- app_joint_qdesn_phase182_dirs(cache_root, source_cache_root)
  out_dir <- out_dir %||% dirs$freeze
  fixture_dir <- fixture_dir %||% dirs$fixtures
  contract <- app_joint_qdesn_phase182_read_contract()
  if (!force && file.exists(file.path(out_dir, "artifact_manifest.csv"))) {
    check <- tryCatch(
      app_joint_exqdesn_verify_manifest(out_dir, "phase182_freeze"),
      error = function(e) NULL
    )
    if (!is.null(check) && all(check$status == "pass")) {
      freeze <- app_joint_qdesn_phase182_load_freeze(out_dir)
      return(list(
        out_dir = freeze$dir, plan = freeze$plan,
        readiness = freeze$readiness, reused = TRUE
      ))
    }
  }
  source <- app_joint_qdesn_phase182_source_audit(dirs, contract)
  scenario_ids <- sort(unique(source$registry$scenario_id))
  dense <- app_joint_qdesn_phase182_materialize_dense_fixture_full(
    dirs$fixture_source, dirs$dense_fixture_full, scenario_ids, contract$tau,
    force = force
  )
  shards <- app_joint_qdesn_phase182_materialize_fixture_shards(
    dense$out_dir, fixture_dir, scenario_ids, force = force
  )
  cells <- source$registry[order(source$registry$cell_index), , drop = FALSE]
  plan <- app_joint_qdesn_phase182_worker_plan(cells, dirs, contract)
  components <- app_joint_qdesn_phase180_component_seed_plan(plan, contract$tau)
  if (anyDuplicated(components$component_seed)) {
    stop("Phase182 component seed plan has collisions.", call. = FALSE)
  }
  initialize <- function(ii) try(
    app_joint_qdesn_phase182_initialize_cached(
      cells[ii, , drop = FALSE], fixture_dir, dirs$initialization_work,
      force = force
    ), silent = TRUE
  )
  initialization <- if (.Platform$OS.type != "windows" && n_vb_cores > 1L) {
    parallel::mclapply(
      seq_len(nrow(cells)), initialize,
      mc.cores = min(as.integer(n_vb_cores), nrow(cells)),
      mc.preschedule = FALSE
    )
  } else lapply(seq_len(nrow(cells)), initialize)
  failed <- vapply(initialization, inherits, logical(1L), "try-error")
  if (any(failed)) {
    stop(sprintf(
      "Phase182 VB initialization failed: %s",
      paste(vapply(initialization[failed], as.character, character(1L)),
            collapse = " | ")
    ), call. = FALSE)
  }
  init <- app_joint_qdesn_bind_rows(lapply(initialization, `[[`, "init"))
  init_audit <- app_joint_qdesn_bind_rows(lapply(initialization, `[[`, "audit"))
  starts <- app_joint_qdesn_phase180_chain_starts(init, cells, contract)
  start_preflight <- app_joint_qdesn_phase180_m0_start_preflight(
    starts, plan, contract$tau
  )
  if (any(init_audit$status != "pass") ||
      length(unique(init$mcmc_case_id)) != contract$expected_final_cells ||
      any(start_preflight$status != "pass")) {
    stop("Phase182 initialization or exAL start preflight failed.", call. = FALSE)
  }
  fixture_manifest <- app_sha256_file(file.path(fixture_dir, "artifact_manifest.csv"))
  plan$fixture_manifest_sha256 <- fixture_manifest
  plan$code_commit <- app_joint_exqdesn_phase171_git_value(c("rev-parse", "HEAD"))
  plan$source_control_file_sha256 <- cells$source_control_file_sha256[
    match(plan$mcmc_case_id, cells$mcmc_case_id)
  ]
  plan$source_control_row_sha256 <- cells$source_control_row_sha256[
    match(plan$mcmc_case_id, cells$mcmc_case_id)
  ]
  compute <- data.frame(
    likelihood_family = c("AL", "exAL"),
    rerun_cells = c(sum(cells$likelihood_family == "AL"),
                    sum(cells$likelihood_family == "exAL")),
    chains_per_cell = contract$n_chains,
    workers = c(sum(plan$likelihood_family == "AL"),
                sum(plan$likelihood_family == "exAL")),
    n_iter = c(contract$al_n_iter, contract$exal_n_iter),
    burn = c(contract$al_burn, contract$exal_burn),
    thin = c(contract$al_thin, contract$exal_thin),
    retained_draws_per_chain = c(
      (contract$al_n_iter - contract$al_burn) / contract$al_thin,
      (contract$exal_n_iter - contract$exal_burn) / contract$exal_thin
    ),
    score_draws_per_chain = contract$score_draws_per_chain,
    stringsAsFactors = FALSE
  )
  readiness <- data.frame(
    phase_id = contract$version, gate_status = "pass",
    current_tau_count = length(contract$current_tau),
    dense_tau_count = length(contract$tau),
    final_cells = nrow(cells), rerun_cells = nrow(cells),
    planned_workers = nrow(plan), planned_components = nrow(components),
    unique_chain_seeds = length(unique(plan$chain_seed)),
    unique_component_seeds = length(unique(components$component_seed)),
    dense_fixture_identity_status = paste(unique(dense$audit$identity$status), collapse = ";"),
    dense_truth_status = dense$audit$truth$status[[1L]],
    article_fixture_used_for_selection = FALSE,
    global_specification_selected = FALSE, desn_or_tau0_retuning_allowed = FALSE,
    article_assets_modified = FALSE,
    recommendation = "launch_dense_grid_crossing_refit",
    stringsAsFactors = FALSE
  )
  if (readiness$final_cells != contract$expected_final_cells ||
      readiness$rerun_cells != contract$expected_rerun_cells ||
      readiness$planned_workers != contract$expected_new_workers ||
      any(!is.finite(init$value)) || any(init_audit$status != "pass")) {
    stop("Phase182 readiness counts differ from the frozen contract.", call. = FALSE)
  }

  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase182 dense-grid crossing freeze", "",
    "This freeze refits all 32 balanced scenario-model cells on a 19-level grid.",
    "It preserves Phase181 case-specific DESN, RHS, and tau0 controls.",
    "No current-grid posterior draws are reused or interpolated after changing tau.",
    "The dense fixture preserves the original observed responses and design matrix.",
    "Workers write compact compressed posterior checkpoints; no R workspace is retained.",
    "Article assets are not modified by this preparation or by the workers."
  ), readme, useBytes = TRUE)
  contract_path <- file.path(tmp, "phase182_dense_grid_contract.csv")
  file.copy(contract$path, contract_path, overwrite = TRUE)
  paths <- c(
    phase182_dense_grid_contract = normalizePath(contract_path, mustWork = TRUE),
    final_selected_cell_registry = write(cells, "final_selected_cell_registry.csv"),
    rerun_cell_plan = write(cells, "rerun_cell_plan.csv"),
    worker_plan = write(plan, "worker_plan.csv"),
    chain_seed_plan = write(
      plan[, c("worker_id", "mcmc_case_id", "chain_id", "chain_seed", "seed_role")],
      "chain_seed_plan.csv"
    ),
    component_seed_plan = write(components, "component_seed_plan.csv"),
    source_manifest_verification = write(
      source$source_checks, "source_manifest_verification.csv"
    ),
    phase181_gate_source = write(source$phase181_gate, "phase181_gate_source.csv"),
    phase181_current_grid_summary = write(
      source$phase181_summary, "phase181_current_grid_summary.csv"
    ),
    phase181_final_source_registry = write(
      source$phase181_source_registry, "phase181_final_source_registry.csv"
    ),
    case_specific_control_audit = write(
      source$control_audit, "case_specific_control_audit.csv"
    ),
    dense_fixture_identity_audit = write(
      dense$audit$identity, "dense_fixture_identity_audit.csv"
    ),
    dense_true_quantile_audit = write(
      dense$audit$truth, "dense_true_quantile_audit.csv"
    ),
    fixture_shard_manifest = write(
      shards$shard_manifest, "fixture_shard_manifest.csv"
    ),
    vb_initialization = write(init, "vb_initialization.csv"),
    vb_initialization_audit = write(init_audit, "vb_initialization_audit.csv"),
    chain_start_values = write(starts, "chain_start_values.csv"),
    chain_start_preflight = write(
      start_preflight, "chain_start_preflight.csv"
    ),
    compute_budget = write(compute, "compute_budget.csv"),
    readiness_assessment = write(readiness, "readiness_assessment.csv"),
    run_config = write(data.frame(
      phase_id = contract$version,
      cache_root = normalizePath(cache_root, mustWork = FALSE),
      source_cache_root = normalizePath(source_cache_root, mustWork = TRUE),
      fixture_source_dir = normalizePath(dirs$fixture_source, mustWork = TRUE),
      dense_fixture_full_dir = normalizePath(dense$out_dir, mustWork = TRUE),
      fixture_dir = normalizePath(fixture_dir, mustWork = TRUE),
      result_dir = dirs$chains,
      score_work_dir = dirs$score_work,
      code_commit = unique(plan$code_commit),
      primary_metric = contract$primary_metric,
      dense_tau_grid = app_joint_qdesn_format_tau(contract$tau),
      article_fixture_selection_allowed = FALSE,
      article_assets_modified = FALSE,
      stringsAsFactors = FALSE
    ), "run_config.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(
      final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S")
    )
    if (!file.rename(final_dir, quarantine)) {
      stop("Could not quarantine prior Phase182 freeze.", call. = FALSE)
    }
  }
  if (!file.rename(tmp, final_dir)) {
    stop("Could not publish Phase182 freeze.", call. = FALSE)
  }
  freeze <- app_joint_qdesn_phase182_load_freeze(final_dir)
  list(out_dir = freeze$dir, plan = freeze$plan, readiness = readiness, reused = FALSE)
}

app_joint_qdesn_phase182_worker_complete <- function(worker_dir) {
  app_joint_qdesn_phase180_worker_complete(worker_dir)
}

app_joint_qdesn_phase182_run_worker <- function(
  freeze_dir, worker_id, reuse_completed = TRUE, failure_dir = NULL
) {
  freeze <- app_joint_qdesn_phase182_load_freeze(freeze_dir)
  worker_id <- as.integer(worker_id)[[1L]]
  job <- freeze$plan[freeze$plan$worker_id == worker_id, , drop = FALSE]
  if (nrow(job) != 1L) stop("Unknown Phase182 worker id.", call. = FALSE)
  current_commit <- app_joint_qdesn_phase180_git_output(c("rev-parse", "HEAD"))
  worktree_status <- app_joint_qdesn_phase180_git_output(c("status", "--porcelain"))
  if (is.na(current_commit) || current_commit != job$code_commit[[1L]] ||
      (!is.na(worktree_status) && nzchar(worktree_status))) {
    stop("Phase182 workers require the clean commit frozen by preparation.",
         call. = FALSE)
  }
  worker_dir <- job$worker_output_dir[[1L]]
  if (reuse_completed && app_joint_qdesn_phase182_worker_complete(worker_dir)) {
    return(list(
      worker_id = worker_id, status = "reused_verified", worker_dir = worker_dir
    ))
  }
  component <- freeze$components[
    freeze$components$worker_id == worker_id, , drop = FALSE
  ]
  expected <- if (job$fit_structure[[1L]] == "joint") {
    1L
  } else length(freeze$contract$tau)
  if (nrow(component) != expected || anyDuplicated(component$component_seed)) {
    stop("Malformed Phase182 component seed plan.", call. = FALSE)
  }
  has_checkpoint <- app_joint_qdesn_phase180_checkpoint_complete(worker_dir)
  if (!has_checkpoint && dir.exists(worker_dir) &&
      length(list.files(worker_dir, all.files = TRUE, no.. = TRUE))) {
    quarantine <- paste0(
      worker_dir, ".incomplete.", format(Sys.time(), "%Y%m%dT%H%M%S")
    )
    if (!file.rename(worker_dir, quarantine)) {
      stop("Could not quarantine incomplete Phase182 worker.", call. = FALSE)
    }
  }
  app_ensure_dir(worker_dir)
  tryCatch({
    control <- freeze$controls[
      freeze$controls$mcmc_case_id == job$mcmc_case_id[[1L]], , drop = FALSE
    ]
    if (nrow(control) != 1L ||
        control$source_control_row_sha256[[1L]] !=
          job$source_control_row_sha256[[1L]]) {
      stop("Phase182 worker could not resolve its frozen control.", call. = FALSE)
    }
    loaded <- app_joint_qdesn_phase180_load_fixture(
      job$scenario_id[[1L]], freeze$config$fixture_dir[[1L]]
    )
    fixture <- loaded$fixture
    K <- length(fixture$tau); p <- ncol(fixture$Z)
    init <- app_joint_qdesn_phase180_reconstruct_init(
      freeze$init, job$mcmc_case_id[[1L]], job$likelihood_family[[1L]],
      job$fit_structure[[1L]], K, p
    )
    init <- app_joint_qdesn_phase180_apply_chain_start(
      init, freeze$starts, job, K, p
    )
    checkpoint <- if (has_checkpoint) {
      app_joint_qdesn_phase180_load_checkpoint(
        worker_dir, fixture, job, component, freeze$dir
      )
    } else {
      started <- proc.time()[["elapsed"]]
      fit <- app_joint_qdesn_phase180_fit_chain(job, control, fixture, init)
      elapsed <- proc.time()[["elapsed"]] - started
      app_joint_qdesn_phase180_write_checkpoint(
        fit, fixture, job, component, elapsed, freeze$dir, worker_dir,
        checkpoint_role = "phase182_dense_grid_crossing_postfit_prescore"
      )
    }
    fit <- checkpoint$fit; draws <- checkpoint$draws
    meta <- app_joint_qdesn_phase180_score_meta(job)
    fit_score <- app_joint_qdesn_phase122_score_qhat(
      meta, fixture, app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau),
      "qhat", "phase182_chain_fit"
    )
    forecast_score <- app_joint_qdesn_phase122_forecast_scores(
      meta, loaded$artifacts, job$scenario_id[[1L]], fixture, fit,
      "qhat", "phase182_chain_forecast"
    )
    contract_crossings <- sum(fit_score$contract_crossing$n_crossing_pairs) +
      sum(forecast_score$contract_crossing$n_crossing_pairs)
    summary <- data.frame(
      phase_id = freeze$contract$version,
      worker_id = worker_id, mcmc_case_id = job$mcmc_case_id[[1L]],
      case_id = job$case_id[[1L]], scenario_id = job$scenario_id[[1L]],
      source_model_id = job$source_model_id[[1L]],
      likelihood_family = job$likelihood_family[[1L]],
      fit_structure = job$fit_structure[[1L]],
      inference_method_id = job$inference_method_id[[1L]],
      chain_id = job$chain_id[[1L]], chain_seed = job$chain_seed[[1L]],
      n_iter = job$n_iter[[1L]], burn = job$burn[[1L]], thin = job$thin[[1L]],
      n_keep = nrow(draws), dense_tau_count = length(fixture$tau),
      draws_all_finite = all(is.finite(as.matrix(draws[, -1L, drop = FALSE]))),
      fit_truth_mae = mean(fit_score$scored$truth_abs_error),
      forecast_truth_mae = mean(forecast_score$scored$truth_abs_error),
      fit_check_loss_mean = mean(fit_score$scored$check_loss),
      forecast_check_loss_mean = mean(forecast_score$scored$check_loss),
      fit_raw_crossing_pairs = sum(fit_score$raw_crossing$n_crossing_pairs),
      forecast_raw_crossing_pairs = sum(
        forecast_score$raw_crossing$n_crossing_pairs
      ),
      contract_crossing_pairs = contract_crossings,
      min_sigma = min(fit$sigma_draws), max_sigma = max(fit$sigma_draws),
      min_gamma = if (!is.null(fit$gamma_draws)) min(fit$gamma_draws) else NA_real_,
      max_gamma = if (!is.null(fit$gamma_draws)) max(fit$gamma_draws) else NA_real_,
      elapsed_seconds = checkpoint$metadata$elapsed_seconds[[1L]],
      stringsAsFactors = FALSE
    )
    if (!summary$draws_all_finite[[1L]] || contract_crossings != 0L) {
      stop("Phase182 worker failed the finite/noncrossing contract.", call. = FALSE)
    }
    readme <- file.path(worker_dir, "README.md")
    writeLines(c(
      sprintf("# Phase182 worker %d", worker_id), "",
      sprintf("- Cell: `%s`", job$mcmc_case_id[[1L]]),
      sprintf("- Chain: %d", job$chain_id[[1L]]),
      sprintf("- Dense tau count: %d", length(fixture$tau)),
      sprintf("- Likelihood/sampler: `%s` / `%s`",
              job$likelihood_family[[1L]], job$inference_method_id[[1L]]),
      "- DESN, tau0, prior, fixture rows, forecast design, and seed roles are frozen.",
      "- Posterior draws use compressed CSV; no serialized R workspace is retained."
    ), readme, useBytes = TRUE)
    runtime <- summary[, c(
      "phase_id", "worker_id", "mcmc_case_id", "case_id", "chain_id",
      "chain_seed", "elapsed_seconds"
    ), drop = FALSE]
    paths <- c(
      checkpoint$paths,
      chain_summary = app_joint_qvp_write_csv(
        summary, file.path(worker_dir, "chain_summary.csv")
      ),
      runtime = app_joint_qvp_write_csv(
        runtime, file.path(worker_dir, "runtime.csv")
      ),
      provenance = app_joint_qvp_write_csv(
        app_joint_qvp_provenance_rows(), file.path(worker_dir, "provenance.csv")
      ),
      README = normalizePath(readme, mustWork = TRUE)
    )
    app_joint_exqdesn_write_manifest(paths, worker_dir)
    if (!app_joint_qdesn_phase182_worker_complete(worker_dir)) {
      stop("Phase182 worker manifest failed.", call. = FALSE)
    }
    stale <- c(
      file.path(worker_dir, "failure_receipt.csv"),
      if (!is.null(failure_dir) && nzchar(failure_dir)) {
        file.path(failure_dir, sprintf("worker_%04d.csv", worker_id))
      } else character()
    )
    if (any(file.exists(stale))) unlink(stale[file.exists(stale)], force = TRUE)
    list(worker_id = worker_id, status = "completed", worker_dir = worker_dir)
  }, error = function(e) {
    receipt <- data.frame(
      worker_id = worker_id, mcmc_case_id = job$mcmc_case_id[[1L]],
      case_id = job$case_id[[1L]], chain_id = job$chain_id[[1L]],
      message = conditionMessage(e),
      timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      stringsAsFactors = FALSE
    )
    app_joint_qvp_write_csv(receipt, file.path(worker_dir, "failure_receipt.csv"))
    if (!is.null(failure_dir) && nzchar(failure_dir)) {
      app_ensure_dir(failure_dir)
      app_joint_qvp_write_csv(
        receipt, file.path(failure_dir, sprintf("worker_%04d.csv", worker_id))
      )
    }
    stop(e)
  })
}

app_joint_qdesn_phase182_health <- function(
  freeze_dir, orchestration_dir = NULL
) {
  freeze <- app_joint_qdesn_phase182_load_freeze(freeze_dir)
  complete <- vapply(
    freeze$plan$worker_output_dir,
    app_joint_qdesn_phase182_worker_complete, logical(1L)
  )
  exits <- if (!is.null(orchestration_dir)) {
    file.path(
      orchestration_dir, "exits",
      sprintf("worker_%04d.exit", freeze$plan$worker_id)
    )
  } else rep("", nrow(freeze$plan))
  failed <- vapply(exits, function(path) {
    if (!nzchar(path) || !file.exists(path)) return(FALSE)
    value <- suppressWarnings(as.integer(readLines(path, warn = FALSE)[[1L]]))
    is.finite(value) && value != 0L
  }, logical(1L))
  state <- ifelse(complete, "complete", ifelse(failed, "failed", "remaining"))
  plan <- freeze$plan; plan$state <- state
  by_case <- app_joint_qdesn_bind_rows(lapply(
    split(plan, plan$mcmc_case_id), function(x) {
      data.frame(
        mcmc_case_id = x$mcmc_case_id[[1L]], case_id = x$case_id[[1L]],
        scenario_id = x$scenario_id[[1L]],
        source_model_id = x$source_model_id[[1L]],
        likelihood_family = x$likelihood_family[[1L]],
        fit_structure = x$fit_structure[[1L]],
        planned = nrow(x), complete = sum(x$state == "complete"),
        failed = sum(x$state == "failed"),
        remaining = sum(x$state == "remaining"),
        stringsAsFactors = FALSE
      )
    }
  ))
  list(
    summary = data.frame(
      stage = "phase182_dense_grid_crossing_refit",
      planned = nrow(plan), complete = sum(complete),
      failed = sum(failed & !complete), remaining = sum(!complete & !failed),
      percent_complete = 100 * mean(complete),
      cells_complete = sum(by_case$complete == by_case$planned),
      cells_planned = nrow(by_case), stringsAsFactors = FALSE
    ),
    by_case = by_case, plan = plan
  )
}

app_joint_qdesn_phase182_score_cell_matches <- function(path, jobs) {
  if (!app_joint_qdesn_postscore_cell_complete(path)) return(FALSE)
  source_path <- file.path(path, "source_inventory.csv")
  if (!file.exists(source_path)) return(FALSE)
  actual <- tryCatch(app_read_csv(source_path), error = function(e) NULL)
  if (is.null(actual) || nrow(actual) != nrow(jobs)) return(FALSE)
  expected <- data.frame(
    chain_id = as.integer(jobs$chain_id),
    worker_output_dir = normalizePath(jobs$worker_output_dir),
    worker_manifest_sha256 = vapply(jobs$worker_output_dir, function(worker_dir) {
      app_sha256_file(file.path(worker_dir, "artifact_manifest.csv"))
    }, character(1L)), stringsAsFactors = FALSE
  )
  actual <- actual[order(actual$chain_id), c(
    "chain_id", "worker_output_dir", "worker_manifest_sha256"
  ), drop = FALSE]
  expected <- expected[order(expected$chain_id), , drop = FALSE]
  identical(
    lapply(actual, as.character),
    lapply(expected, as.character)
  )
}

app_joint_qdesn_phase182_score_cell <- function(
  jobs, freeze, contract, work_dir
) {
  path <- app_joint_qdesn_postscore_cell_dir(
    work_dir, jobs$mcmc_case_id[[1L]]
  )
  if (app_joint_qdesn_phase182_score_cell_matches(path, jobs)) {
    return(normalizePath(path))
  }
  if (dir.exists(path)) unlink(path, recursive = TRUE, force = TRUE)
  result <- app_joint_qdesn_postscore_case(
    jobs, freeze, contract,
    fixture_loader = app_joint_qdesn_phase180_score_fixture_loader,
    fit_loader = app_joint_qdesn_phase180_score_fit_loader
  )
  app_joint_qdesn_postscore_write_cell(result, path)
  normalizePath(path)
}

app_joint_qdesn_phase182_run_score_cells <- function(
  groups, freeze, contract, work_dir, cores = 8L
) {
  run <- function(index) try(
    app_joint_qdesn_phase182_score_cell(
      groups[[index]], freeze, contract, work_dir
    ), silent = TRUE
  )
  result <- if (.Platform$OS.type != "windows" && cores > 1L) {
    parallel::mclapply(
      seq_along(groups), run,
      mc.cores = min(as.integer(cores), length(groups)),
      mc.preschedule = FALSE
    )
  } else lapply(seq_along(groups), run)
  failed <- vapply(result, inherits, logical(1L), "try-error")
  if (any(failed)) {
    stop(sprintf(
      "Phase182 score reconstruction failed: %s",
      paste(vapply(result[failed], as.character, character(1L)), collapse = " | ")
    ), call. = FALSE)
  }
  paths <- unlist(result, use.names = FALSE)
  names(paths) <- names(groups)
  paths
}

app_joint_qdesn_phase182_final_source_plan <- function(freeze) {
  out <- freeze$plan
  out$source_kind <- "phase182_dense_grid_refit"
  out$source_worker_id <- out$worker_id
  out$selection_source_role <- "phase182_dense_grid_all_cell_refit"
  out$worker_manifest_verified <- vapply(
    out$worker_output_dir, app_joint_qdesn_phase182_worker_complete, logical(1L)
  )
  out$worker_manifest_sha256 <- vapply(out$worker_output_dir, function(path) {
    manifest <- file.path(path, "artifact_manifest.csv")
    if (file.exists(manifest)) app_sha256_file(manifest) else NA_character_
  }, character(1L))
  if (nrow(out) != freeze$contract$expected_final_cells * freeze$contract$n_chains ||
      length(unique(out$case_id)) != freeze$contract$expected_final_cells ||
      any(table(out$case_id) != freeze$contract$n_chains) ||
      any(!out$worker_manifest_verified) ||
      anyDuplicated(paste(out$case_id, out$chain_id))) {
    stop("Phase182 final source plan is incomplete or unverifiable.", call. = FALSE)
  }
  out[order(
    match(out$case_id, freeze$registry$case_id), as.integer(out$chain_id)
  ), , drop = FALSE]
}

app_joint_qdesn_phase182_case_crossing_pairs <- function(jobs, freeze) {
  loaded <- app_joint_qdesn_phase180_score_fixture_loader(jobs, freeze)
  fixture <- loaded$fixture
  context <- app_joint_qdesn_postscore_forecast_context(loaded, fixture)
  fits <- app_joint_qdesn_phase180_score_fit_loader(jobs, fixture, freeze)
  pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(
    fits, fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau
  )
  blocks <- list(
    fit = list(
      qhat = app_joint_qdesn_predict_fit(pooled, fixture$Z, fixture$tau),
      true_q = fixture$true_q
    ),
    forecast = list(
      qhat = app_joint_qdesn_predict_fit(pooled, context$forecast$Z, fixture$tau),
      true_q = context$forecast$true_q
    )
  )
  app_joint_qdesn_bind_rows(lapply(names(blocks), function(window) {
    qhat <- as.matrix(blocks[[window]]$qhat)
    true_q <- as.matrix(blocks[[window]]$true_q)
    tau <- fixture$tau
    rows <- list(); cursor <- 1L
    for (ii in seq_len(nrow(qhat))) {
      diffs <- diff(qhat[ii, ])
      crossed <- which(diffs < -1e-10)
      if (!length(crossed)) next
      for (jj in crossed) {
        rows[[cursor]] <- data.frame(
          case_id = jobs$case_id[[1L]], mcmc_case_id = jobs$mcmc_case_id[[1L]],
          scenario_id = jobs$scenario_id[[1L]],
          source_model_id = jobs$source_model_id[[1L]],
          likelihood_family = jobs$likelihood_family[[1L]],
          fit_structure = jobs$fit_structure[[1L]], window = window,
          row_index = ii, lower_tau = tau[[jj]], upper_tau = tau[[jj + 1L]],
          lower_qhat = qhat[ii, jj], upper_qhat = qhat[ii, jj + 1L],
          crossing_magnitude = -diffs[[jj]],
          lower_true_quantile = true_q[ii, jj],
          upper_true_quantile = true_q[ii, jj + 1L],
          true_gap = true_q[ii, jj + 1L] - true_q[ii, jj],
          stringsAsFactors = FALSE
        )
        cursor <- cursor + 1L
      }
    }
    if (!length(rows)) {
      return(data.frame(
        case_id = jobs$case_id[[1L]], mcmc_case_id = jobs$mcmc_case_id[[1L]],
        scenario_id = jobs$scenario_id[[1L]],
        source_model_id = jobs$source_model_id[[1L]],
        likelihood_family = jobs$likelihood_family[[1L]],
        fit_structure = jobs$fit_structure[[1L]], window = window,
        row_index = integer(), lower_tau = numeric(), upper_tau = numeric(),
        lower_qhat = numeric(), upper_qhat = numeric(),
        crossing_magnitude = numeric(), lower_true_quantile = numeric(),
        upper_true_quantile = numeric(), true_gap = numeric(),
        stringsAsFactors = FALSE
      ))
    }
    app_joint_qdesn_bind_rows(rows)
  }))
}

app_joint_qdesn_phase182_crossing_pair_summary <- function(pair_detail) {
  if (!nrow(pair_detail)) {
    return(data.frame(
      case_id = character(), scenario_id = character(), source_model_id = character(),
      likelihood_family = character(), fit_structure = character(), window = character(),
      lower_tau = numeric(), upper_tau = numeric(), crossing_pairs = integer(),
      max_crossing_magnitude = numeric(), mean_crossing_magnitude = numeric(),
      min_true_gap = numeric(), stringsAsFactors = FALSE
    ))
  }
  groups <- split(
    pair_detail,
    interaction(
      pair_detail$case_id, pair_detail$window, pair_detail$lower_tau,
      pair_detail$upper_tau, drop = TRUE, lex.order = TRUE
    )
  )
  app_joint_qdesn_bind_rows(lapply(groups, function(x) {
    data.frame(
      case_id = x$case_id[[1L]], scenario_id = x$scenario_id[[1L]],
      source_model_id = x$source_model_id[[1L]],
      likelihood_family = x$likelihood_family[[1L]],
      fit_structure = x$fit_structure[[1L]], window = x$window[[1L]],
      lower_tau = x$lower_tau[[1L]], upper_tau = x$upper_tau[[1L]],
      crossing_pairs = nrow(x),
      max_crossing_magnitude = max(x$crossing_magnitude),
      mean_crossing_magnitude = mean(x$crossing_magnitude),
      min_true_gap = min(x$true_gap),
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_qdesn_phase182_finalize <- function(
  cache_root = app_joint_qdesn_phase182_cache_root(),
  source_cache_root = app_joint_qdesn_phase182_source_cache_root(),
  freeze_dir = NULL, out_dir = NULL, score_cores = 8L, force = FALSE
) {
  dirs <- app_joint_qdesn_phase182_dirs(cache_root, source_cache_root)
  freeze_dir <- freeze_dir %||% dirs$freeze
  out_dir <- out_dir %||% dirs$packet
  freeze <- app_joint_qdesn_phase182_load_freeze(freeze_dir)
  health <- app_joint_qdesn_phase182_health(freeze_dir, dirs$orchestration)
  if (health$summary$failed[[1L]] > 0L ||
      health$summary$remaining[[1L]] > 0L ||
      health$summary$complete[[1L]] != freeze$contract$expected_new_workers) {
    stop("Phase182 cannot finalize before all 256 workers pass.", call. = FALSE)
  }
  if (!force && file.exists(file.path(out_dir, "artifact_manifest.csv"))) {
    check <- tryCatch(
      app_joint_exqdesn_verify_manifest(out_dir, "phase182_packet"),
      error = function(e) NULL
    )
    if (!is.null(check) && all(check$status == "pass")) {
      return(list(
        out_dir = normalizePath(out_dir),
        assessment = app_read_csv(file.path(out_dir, "final_gate_assessment.csv")),
        reused = TRUE
      ))
    }
  }
  plan <- app_joint_qdesn_phase182_final_source_plan(freeze)
  groups <- split(
    plan, factor(plan$case_id, levels = freeze$registry$case_id)
  )
  if (length(groups) != freeze$contract$expected_final_cells) {
    stop("Phase182 final source grouping is incomplete.", call. = FALSE)
  }
  cell_paths <- app_joint_qdesn_phase182_run_score_cells(
    groups, freeze, freeze$contract, dirs$score_work, as.integer(score_cores)
  )
  score <- app_joint_qdesn_postscore_collect_cells(cell_paths)
  if (nrow(score$diagnostics) != freeze$contract$expected_final_cells ||
      any(score$diagnostics$contract_crossing_pairs != 0L) ||
      any(score$previsibility$status != "pass") ||
      any(score$source$worker_manifest_status != "pass")) {
    stop("Phase182 score cells failed source or implementation gates.", call. = FALSE)
  }
  score_summary <- app_joint_qdesn_phase181_merge_score_summary(
    score, freeze$registry, freeze$registry$case_id
  )
  score_summary$claim_status <- ifelse(
    score_summary$score_functional_status == "pass" &
      score_summary$coherence_status == "pass",
    "diagnostic_hard_gates_pass", "diagnostic_review"
  )
  formula <- app_joint_qdesn_postscore_formula_audit(freeze$contract)
  oracle_minimum <- app_joint_qdesn_postscore_oracle_minimum_audit(freeze$contract)
  if (any(formula$analytic_status != "pass") ||
      any(formula$monte_carlo_status != "pass") ||
      any(oracle_minimum$status != "pass")) {
    stop("Phase182 DGP-score formula audit failed.", call. = FALSE)
  }
  pairing <- app_joint_qdesn_postscore_pairing_stability(
    score$pairing_sensitivity, freeze$contract
  )
  contrast <- app_joint_qdesn_postscore_joint_independent_contrasts(
    score$draws, freeze$contract
  )
  supplements <- if (.Platform$OS.type != "windows" && score_cores > 1L) {
    parallel::mclapply(
      groups, app_joint_qdesn_phase180_case_supplement, freeze = freeze,
      mc.cores = min(as.integer(score_cores), length(groups)),
      mc.preschedule = FALSE
    )
  } else lapply(groups, app_joint_qdesn_phase180_case_supplement, freeze = freeze)
  oracle <- app_joint_qdesn_bind_rows(lapply(supplements, `[[`, "oracle"))
  parameters <- app_joint_qdesn_bind_rows(lapply(supplements, `[[`, "parameters"))
  pair_detail <- if (.Platform$OS.type != "windows" && score_cores > 1L) {
    app_joint_qdesn_bind_rows(parallel::mclapply(
      groups, app_joint_qdesn_phase182_case_crossing_pairs, freeze = freeze,
      mc.cores = min(as.integer(score_cores), length(groups)),
      mc.preschedule = FALSE
    ))
  } else {
    app_joint_qdesn_bind_rows(lapply(
      groups, app_joint_qdesn_phase182_case_crossing_pairs, freeze = freeze
    ))
  }
  pair_summary <- app_joint_qdesn_phase182_crossing_pair_summary(pair_detail)
  runtime <- app_joint_qdesn_phase180_collect_runtime(plan)
  crossing <- merge(
    oracle[, c(
      "case_id", "window", "raw_crossing_pairs", "contract_crossing_pairs",
      "mean_abs_monotone_adjustment", "max_abs_monotone_adjustment"
    ), drop = FALSE],
    score_summary[, c(
      "case_id", "raw_crossing_rate", "coherence_status"
    ), drop = FALSE],
    by = "case_id", all.x = TRUE, sort = FALSE
  )
  current_grid <- app_read_csv(file.path(
    dirs$phase181_packet_source, "posterior_dgp_integrated_acrps_summary.csv"
  ))
  compatibility <- merge(
    score_summary[, c(
      "case_id", "scenario_id", "source_model_id", "likelihood_family",
      "posterior_score_mean", "canonical_action_dgp_integrated_acrps",
      "raw_crossing_rate", "coherence_status"
    ), drop = FALSE],
    current_grid[, c(
      "case_id", "posterior_score_mean",
      "canonical_action_dgp_integrated_acrps", "raw_crossing_rate"
    ), drop = FALSE],
    by = "case_id", all.x = TRUE, sort = FALSE,
    suffixes = c("_dense_grid", "_current_grid")
  )
  compatibility$posterior_score_mean_dense_minus_current <-
    compatibility$posterior_score_mean_dense_grid -
      compatibility$posterior_score_mean_current_grid
  compatibility$raw_crossing_rate_dense_minus_current <-
    compatibility$raw_crossing_rate_dense_grid -
      compatibility$raw_crossing_rate_current_grid
  inventory <- data.frame(
    case_id = names(cell_paths), cell_dir = normalizePath(cell_paths),
    manifest_sha256 = vapply(cell_paths, function(path) {
      app_sha256_file(file.path(path, "artifact_manifest.csv"))
    }, character(1L)), status = "pass", stringsAsFactors = FALSE
  )
  hard_fail <- any(score_summary$contract_crossing_pairs != 0L) ||
    any(!is.finite(score_summary$posterior_score_mean)) ||
    any(!is.finite(score_summary$canonical_action_dgp_integrated_acrps)) ||
    any(!plan$worker_manifest_verified) ||
    any(score$previsibility$status != "pass")
  diagnostic_review <- any(score_summary$score_functional_status != "pass") ||
    any(score_summary$coherence_status != "pass") ||
    any(pairing$pairing_status == "review")
  gate <- if (hard_fail) "fail" else if (diagnostic_review) "review" else "pass"
  assessment <- data.frame(
    phase_id = freeze$contract$version, gate_status = gate,
    implementation_hard_gates = if (hard_fail) "fail" else "pass",
    current_tau_count = length(freeze$contract$current_tau),
    dense_tau_count = length(freeze$contract$tau),
    final_cells = nrow(score_summary),
    new_workers_complete = health$summary$complete[[1L]],
    new_workers_failed = health$summary$failed[[1L]],
    score_functional_pass = sum(score_summary$score_functional_status == "pass"),
    score_functional_review = sum(score_summary$score_functional_status != "pass"),
    coherence_review = sum(score_summary$coherence_status != "pass"),
    canonical_fit_raw_crossing_pairs =
      sum(crossing$raw_crossing_pairs[crossing$window == "fit"]),
    canonical_forecast_raw_crossing_pairs =
      sum(crossing$raw_crossing_pairs[crossing$window == "forecast"]),
    contract_crossing_pairs = sum(score_summary$contract_crossing_pairs),
    joint_independent_contrasts = nrow(contrast$summary),
    case_specific_controls_preserved = TRUE,
    article_fixture_used_for_selection = FALSE,
    article_assets_modified = FALSE,
    claim_status = freeze$contract$claim_status,
    recommendation = if (hard_fail) {
      "repair_phase182_hard_failure"
    } else if (diagnostic_review) {
      "review_dense_grid_crossings_before_article_promotion"
    } else "eligible_for_dense_grid_article_discussion_after_integration_review",
    stringsAsFactors = FALSE
  )

  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase182 dense-grid crossing score packet", "",
    "This packet refits all 32 balanced cells on a 19-level quantile grid.",
    "The dense grid is a crossing stress test and does not retune DESN or tau0 controls.",
    "The primary score remains the known-DGP expected finite-grid quantile score.",
    "Raw crossings and monotone adjustments are retained as coherence diagnostics.",
    "Reported contract quantile grids must remain noncrossing.",
    "No manuscript assets are modified by this scientific packet."
  ), readme, useBytes = TRUE)
  paths <- c(
    final_source_registry = write(plan, "final_source_registry.csv"),
    source_manifest_verification = write(
      freeze$verification, "source_manifest_verification.csv"
    ),
    worker_health_summary = write(health$summary, "worker_health_summary.csv"),
    worker_health_by_case = write(health$by_case, "worker_health_by_case.csv"),
    score_contract = write(freeze$contract$table, "phase182_dense_grid_contract.csv"),
    dgp_family_parameterization_audit = write(
      formula, "dgp_family_parameterization_audit.csv"
    ),
    oracle_minimum_audit = write(oracle_minimum, "oracle_minimum_audit.csv"),
    forecast_previsibility_audit = write(
      score$previsibility, "forecast_previsibility_audit.csv"
    ),
    posterior_dgp_integrated_acrps_draws =
      app_joint_qdesn_postscore_write_gzip_csv(
        score$draws,
        file.path(tmp, "posterior_dgp_integrated_acrps_draws.csv.gz")
      ),
    posterior_dgp_integrated_acrps_summary = write(
      score_summary, "posterior_dgp_integrated_acrps_summary.csv"
    ),
    canonical_action_dgp_integrated_acrps = write(
      score$canonical, "canonical_action_dgp_integrated_acrps.csv"
    ),
    dgp_integrated_score_by_tau = write(
      score$canonical_tau, "dgp_integrated_score_by_tau.csv"
    ),
    joint_independent_score_contrast_draws =
      app_joint_qdesn_postscore_write_gzip_csv(
        contrast$draws,
        file.path(tmp, "joint_independent_score_contrast_draws.csv.gz")
      ),
    joint_independent_score_contrast_summary = write(
      contrast$summary, "joint_independent_score_contrast_summary.csv"
    ),
    current_vs_dense_score_comparison = write(
      compatibility, "current_vs_dense_score_comparison.csv"
    ),
    oracle_recovery_diagnostics = write(
      oracle, "oracle_recovery_diagnostics.csv"
    ),
    raw_contract_crossing_summary = write(
      crossing, "raw_contract_crossing_summary.csv"
    ),
    dense_grid_raw_crossing_pair_detail = write(
      pair_detail, "dense_grid_raw_crossing_pair_detail.csv"
    ),
    dense_grid_raw_crossing_pair_summary = write(
      pair_summary, "dense_grid_raw_crossing_pair_summary.csv"
    ),
    parameter_block_diagnostics = write(
      parameters, "parameter_block_diagnostics.csv"
    ),
    score_functional_mcmc_diagnostics = write(
      score$diagnostics, "score_functional_mcmc_diagnostics.csv"
    ),
    chain_allocation_sensitivity = write(
      score$allocation, "chain_allocation_sensitivity.csv"
    ),
    independent_pairing_seed_sensitivity = write(
      pairing, "independent_pairing_seed_sensitivity.csv"
    ),
    runtime_summary = write(runtime, "runtime_summary.csv"),
    score_cell_inventory = write(inventory, "score_cell_inventory.csv"),
    final_gate_assessment = write(assessment, "final_gate_assessment.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(
      final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S")
    )
    if (!file.rename(final_dir, quarantine)) {
      stop("Could not quarantine prior Phase182 packet.", call. = FALSE)
    }
  }
  if (!file.rename(tmp, final_dir)) {
    stop("Could not publish Phase182 packet.", call. = FALSE)
  }
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase182_packet")
  if (any(check$status != "pass")) {
    stop("Phase182 packet manifest failed.", call. = FALSE)
  }
  list(out_dir = final_dir, assessment = assessment, reused = FALSE)
}
