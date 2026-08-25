# Phase180 balanced posterior-score completion and article-staging packet.

app_joint_qdesn_phase180_contract_path <- function() {
  app_path(
    "application/config",
    "joint_qdesn_phase180_balanced_dgp_score_contract_v1.csv"
  )
}

app_joint_qdesn_phase180_dirs <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root()
) {
  list(
    cache_root = normalizePath(cache_root, mustWork = FALSE),
    freeze = file.path(
      cache_root, "joint_qdesn_phase180_balanced_dgp_score_freeze_20260824"
    ),
    initialization_work = file.path(
      cache_root,
      "joint_qdesn_phase180_balanced_dgp_score_initialization_work_20260824"
    ),
    fixtures = file.path(
      cache_root, "joint_qdesn_phase180_article_fixture_shards_20260824"
    ),
    chains = file.path(
      cache_root, "joint_qdesn_phase180_balanced_dgp_score_chains_20260824"
    ),
    orchestration = file.path(
      cache_root,
      "joint_qdesn_phase180_balanced_dgp_score_chains_20260824_orchestration"
    ),
    score_work = file.path(
      cache_root, "joint_qdesn_phase180_balanced_dgp_score_work_20260824"
    ),
    packet = file.path(
      cache_root, "joint_qdesn_phase180_balanced_dgp_score_packet_20260824"
    ),
    article_staging = file.path(
      cache_root, "joint_qdesn_phase180_article_assets_staging_20260824"
    ),
    handoff = file.path(
      cache_root, "joint_qdesn_phase180_integration_handoff_20260824"
    ),
    phase171 = file.path(
      cache_root, "joint_exqdesn_phase171_m0_balanced_article_freeze_20260809"
    ),
    phase172 = file.path(
      cache_root,
      "joint_exqdesn_phase172_m0_balanced_article_confirmation_20260809"
    ),
    phase174 = file.path(
      cache_root, "joint_qdesn_phase174_balanced_mcmc_final_20260809"
    ),
    phase179 = file.path(
      cache_root,
      "joint_qdesn_phase179_dgp_score_confirmation_closeout_20260824"
    ),
    al_joint = file.path(
      cache_root, "joint_qdesn_phase154_mcmc_joint_al_20260730"
    ),
    al_independent = file.path(
      cache_root, "joint_qdesn_phase154_mcmc_independent_al_20260730"
    ),
    fixture_source = file.path(
      cache_root, "joint_qdesn_simulation_dgp_fixtures_20260706"
    )
  )
}

app_joint_qdesn_phase180_contract_value <- function(table, name) {
  row <- table[table$contract_name == name, , drop = FALSE]
  if (nrow(row) != 1L) {
    stop(sprintf("Phase180 contract requires one '%s' row.", name), call. = FALSE)
  }
  as.character(row$value[[1L]])
}

app_joint_qdesn_phase180_read_contract <- function(
  path = app_joint_qdesn_phase180_contract_path()
) {
  table <- app_read_csv(path)
  app_check_required_columns(
    table,
    c("contract_section", "contract_name", "value", "value_type", "rationale"),
    "Phase180 balanced score contract"
  )
  if (anyDuplicated(table$contract_name)) {
    stop("Phase180 contract names must be unique.", call. = FALSE)
  }
  get <- function(name) app_joint_qdesn_phase180_contract_value(table, name)
  num <- function(name) as.numeric(get(name))
  int <- function(name) as.integer(get(name))
  nums <- function(name) as.numeric(strsplit(get(name), ",", fixed = TRUE)[[1L]])
  ints <- function(name) as.integer(strsplit(get(name), ",", fixed = TRUE)[[1L]])
  bool <- function(name) identical(tolower(get(name)), "true")
  out <- list(
    table = table,
    path = normalizePath(path, mustWork = TRUE),
    version = get("contract_version"),
    expected_scenarios = int("expected_scenarios"),
    expected_models = int("expected_models"),
    expected_final_cells = int("expected_final_cells"),
    expected_reuse_cells = int("expected_phase172_reuse_cells"),
    expected_rerun_cells = int("expected_rerun_cells"),
    expected_new_workers = int("expected_new_workers"),
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
    article_fixture_selection_allowed = bool("article_fixture_selection_allowed"),
    global_specification_selected = bool("global_specification_selected"),
    partial_publication_allowed = bool("partial_publication_allowed"),
    dense_grid_authorized = bool("dense_grid_authorized")
  )
  app_joint_qvp_validate_tau_grid(out$tau)
  expected_weights <- c(
    (out$tau[[2L]] - out$tau[[1L]]) / 2,
    (out$tau[3:length(out$tau)] - out$tau[1:(length(out$tau) - 2L)]) / 2,
    (out$tau[[length(out$tau)]] - out$tau[[length(out$tau) - 1L]]) / 2
  )
  if (!isTRUE(all.equal(out$weights_qs, expected_weights, tolerance = 1e-14)) ||
      abs(sum(out$weights_qs) - out$weight_sum) > 1e-14 ||
      out$expected_final_cells != out$expected_scenarios * out$expected_models ||
      out$expected_reuse_cells + out$expected_rerun_cells != out$expected_final_cells ||
      out$expected_new_workers != out$expected_rerun_cells * out$n_chains ||
      out$article_fixture_selection_allowed || out$global_specification_selected ||
      out$partial_publication_allowed || out$dense_grid_authorized) {
    stop("Phase180 contract violates the frozen balanced-score design.", call. = FALSE)
  }
  out
}

app_joint_qdesn_phase180_verify_source <- function(path, source_id) {
  check <- app_joint_exqdesn_verify_manifest(path, source_id)
  if (!nrow(check) || any(check$status != "pass")) {
    stop(sprintf("Phase180 source '%s' failed manifest verification.", source_id),
         call. = FALSE)
  }
  cbind(source_id = source_id, source_dir = normalizePath(path), check,
        stringsAsFactors = FALSE)
}

app_joint_qdesn_phase180_model_label <- function(model_id) {
  labels <- c(
    joint_qdesn_rhs_vb = "Joint QDESN RHS",
    qdesn_rhs_independent_vb = "Independent QDESN RHS",
    joint_exqdesn_rhs_vb = "Joint exQDESN RHS",
    exqdesn_rhs_independent_vb = "Independent exQDESN RHS"
  )
  unname(labels[model_id])
}

app_joint_qdesn_phase180_control_row <- function(x, source_model_id) {
  scenario_id <- as.character(x$scenario_ids[[1L]] %||% x$scenario_id[[1L]])
  fit_structure <- if (grepl("independent", source_model_id, fixed = TRUE)) {
    "independent"
  } else "joint"
  likelihood <- if (grepl("exqdesn", source_model_id, fixed = TRUE)) "exAL" else "AL"
  value <- function(name, default = NA) {
    if (name %in% names(x) && length(x[[name]]) && !is.na(x[[name]][[1L]])) {
      x[[name]][[1L]]
    } else default
  }
  data.frame(
    case_id = paste(scenario_id, source_model_id, sep = "__"),
    scenario_id = scenario_id, scenario_ids = scenario_id,
    base_scenario_id = scenario_id, source_model_id = source_model_id,
    model_id = sub("_vb$", "_mcmc", source_model_id),
    display_label = app_joint_qdesn_phase180_model_label(source_model_id),
    likelihood_family = likelihood, fit_structure = fit_structure,
    candidate_id = as.character(value("candidate_id", paste0(scenario_id, "__", source_model_id))),
    phase178_template_id = as.character(value(
      "phase178_template_id", paste0(scenario_id, "__", source_model_id, "__article")
    )),
    variant_id = likelihood, candidate_role = "frozen_article_control",
    design_role = "frozen_base_fixture", design_class = "frozen_base_fixture",
    vb_max_iter = as.integer(value("vb_max_iter", 1440L)),
    adaptive_vb_max_iter_grid = as.character(value("adaptive_vb_max_iter_grid", "1440,1920")),
    vb_tol = as.numeric(value("vb_tol", 1e-4)),
    rhs_vb_inner = as.integer(value("rhs_vb_inner", 10L)),
    tau0 = as.numeric(value("tau0")), zeta2 = as.numeric(value("zeta2")),
    a_sigma = as.numeric(value("a_sigma", 2)),
    b_sigma = as.numeric(value("b_sigma", 1)),
    alpha_prior_sd = as.character(value("alpha_prior_sd", "0.5")),
    alpha_min_spacing = as.numeric(value("alpha_min_spacing", 0)),
    gamma_init_policy = as.character(value("gamma_init_policy", "zero")),
    review_adjustment_threshold = as.numeric(value("review_adjustment_threshold", 0.001)),
    max_dense_dim = as.integer(value("max_dense_dim", 300L)),
    gamma_slice_width = as.numeric(value("gamma_slice_width", 1)),
    gamma_slice_max_steps = as.integer(value("gamma_slice_max_steps", 100L)),
    source_control_path = as.character(value("source_control_path", NA_character_)),
    source_control_file_sha256 = as.character(value(
      "source_control_file_sha256", NA_character_
    )),
    source_control_row_sha256 = as.character(value(
      "source_control_row_sha256", NA_character_
    )),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase180_build_cell_registry <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  contract = app_joint_qdesn_phase180_read_contract()
) {
  dirs <- app_joint_qdesn_phase180_dirs(cache_root)
  source_checks <- app_joint_qdesn_bind_rows(list(
    app_joint_qdesn_phase180_verify_source(dirs$phase174, "phase174_authority"),
    app_joint_qdesn_phase180_verify_source(dirs$phase171, "phase171_exal_freeze"),
    app_joint_qdesn_phase180_verify_source(dirs$phase172, "phase172_exal_draws"),
    app_joint_qdesn_phase180_verify_source(dirs$phase179, "phase179_final_controls"),
    app_joint_qdesn_phase180_verify_source(dirs$al_joint, "phase154_joint_al"),
    app_joint_qdesn_phase180_verify_source(
      dirs$al_independent, "phase154_independent_al"
    ),
    app_joint_qdesn_phase180_verify_source(dirs$fixture_source, "article_fixture")
  ))
  authority <- app_read_csv(file.path(dirs$phase174, "final_mcmc_case_summary.csv"))
  if (nrow(authority) != contract$expected_final_cells ||
      anyDuplicated(paste(authority$scenario_id, authority$source_model_id)) ||
      length(unique(authority$scenario_id)) != contract$expected_scenarios ||
      length(unique(authority$source_model_id)) != contract$expected_models) {
    stop("Phase174 is not the expected balanced 32-cell authority.", call. = FALSE)
  }

  al_joint <- app_read_csv(file.path(dirs$al_joint, "case_winner_controls.csv"))
  al_ind <- app_read_csv(file.path(dirs$al_independent, "case_winner_controls.csv"))
  al <- app_joint_qdesn_bind_rows(c(
    lapply(seq_len(nrow(al_joint)), function(ii) {
      app_joint_qdesn_phase180_control_row(al_joint[ii, , drop = FALSE], "joint_qdesn_rhs_vb")
    }),
    lapply(seq_len(nrow(al_ind)), function(ii) {
      app_joint_qdesn_phase180_control_row(
        al_ind[ii, , drop = FALSE], "qdesn_rhs_independent_vb"
      )
    })
  ))
  al$source_action <- "rerun_retained_draws"
  al$source_phase <- "phase154_controls_phase180_rerun"
  al$source_dir <- ifelse(
    al$fit_structure == "joint", dirs$al_joint, dirs$al_independent
  )

  phase171 <- app_read_csv(file.path(dirs$phase171, "model_control_freeze.csv"))
  final179 <- app_read_csv(file.path(dirs$phase179, "final_case_specific_controls.csv"))
  if (nrow(phase171) != 16L || nrow(final179) != 5L ||
      anyDuplicated(phase171$case_id) || anyDuplicated(final179$case_id)) {
    stop("Phase171/179 exAL control inventory is malformed.", call. = FALSE)
  }
  exal_rows <- lapply(seq_len(nrow(phase171)), function(ii) {
    base <- phase171[ii, , drop = FALSE]
    selected <- final179[final179$case_id == base$case_id[[1L]], , drop = FALSE]
    if (nrow(selected) == 1L) {
      overlay <- intersect(c(
        "candidate_id", "phase178_template_id", "variant_id", "tau0", "zeta2",
        "a_sigma", "b_sigma", "alpha_prior_sd", "alpha_min_spacing",
        "gamma_init_policy", "max_dense_dim", "gamma_slice_width",
        "gamma_slice_max_steps", "source_control_path",
        "source_control_file_sha256", "source_control_row_sha256"
      ), intersect(names(base), names(selected)))
      for (name in overlay) base[[name]] <- selected[[name]]
    }
    model <- if (base$fit_structure[[1L]] == "joint") {
      "joint_exqdesn_rhs_vb"
    } else "exqdesn_rhs_independent_vb"
    out <- app_joint_qdesn_phase180_control_row(base, model)
    out$phase178_template_id <- if (nrow(selected) == 1L) {
      selected$phase178_template_id[[1L]]
    } else paste0(out$case_id[[1L]], "__phase172_retained")
    out$variant_id <- "exAL"
    out$candidate_role <- if (nrow(selected) == 1L) {
      "phase179_final_case_specific_control"
    } else "phase172_retained_final_control"
    out$source_action <- if (nrow(selected) == 1L) {
      "rerun_phase179_final_control"
    } else "reuse_phase172_verified_draws"
    out$source_phase <- if (nrow(selected) == 1L) "phase179" else "phase172"
    out$source_dir <- dirs$phase172
    out
  })
  exal <- app_joint_qdesn_bind_rows(exal_rows)
  registry <- app_joint_qdesn_bind_rows(list(al, exal))
  registry <- registry[order(
    match(registry$scenario_id, unique(authority$scenario_id)),
    match(registry$source_model_id, unique(authority$source_model_id))
  ), , drop = FALSE]
  registry$cell_index <- seq_len(nrow(registry))
  registry$mcmc_case_id <- registry$case_id
  registry$dgp_replicate_id <- "article_fixture"
  registry$validation_partition <- "article_evaluation"
  registry$article_fixture_used_for_selection <- FALSE
  registry$global_specification_selected <- FALSE
  registry$source_control_row_sha256 <- vapply(
    seq_len(nrow(registry)), function(ii) {
      app_joint_exqdesn_phase171_row_hash(registry[ii, , drop = FALSE])
    }, character(1L)
  )

  reuse <- registry$source_action == "reuse_phase172_verified_draws"
  rerun <- !reuse
  if (nrow(registry) != contract$expected_final_cells ||
      sum(reuse) != contract$expected_reuse_cells ||
      sum(rerun) != contract$expected_rerun_cells ||
      anyDuplicated(registry$case_id) || any(!is.finite(registry$tau0)) ||
      any(!is.finite(registry$zeta2)) ||
      any(registry$article_fixture_used_for_selection) ||
      any(registry$global_specification_selected)) {
    stop("Phase180 final cell registry violates the frozen source policy.", call. = FALSE)
  }
  phase172_dirs <- file.path(
    dirs$phase172, "candidates",
    paste0(registry$scenario_id, "__", registry$fit_structure)
  )
  registry$phase172_case_dir <- ifelse(reuse, phase172_dirs, NA_character_)
  reuse_checks <- app_joint_qdesn_bind_rows(lapply(which(reuse), function(ii) {
    case_dir <- phase172_dirs[[ii]]
    chain_dirs <- file.path(case_dir, sprintf("chain_%02d", seq_len(contract$n_chains)))
    verified <- vapply(
      chain_dirs, app_joint_exqdesn_phase172_worker_complete, logical(1L)
    )
    data.frame(
      case_id = registry$case_id[[ii]], chain_id = seq_len(contract$n_chains),
      worker_dir = normalizePath(chain_dirs, mustWork = FALSE),
      manifest_sha256 = ifelse(
        file.exists(file.path(chain_dirs, "artifact_manifest.csv")),
        vapply(file.path(chain_dirs, "artifact_manifest.csv"), function(path) {
          if (file.exists(path)) app_sha256_file(path) else NA_character_
        }, character(1L)), NA_character_
      ),
      verified = verified, stringsAsFactors = FALSE
    )
  }))
  if (nrow(reuse_checks) != contract$expected_reuse_cells * contract$n_chains ||
      any(!reuse_checks$verified)) {
    stop("Phase180 retained Phase172 worker inventory failed closed.", call. = FALSE)
  }
  list(
    registry = registry, source_checks = source_checks,
    phase172_reuse_checks = reuse_checks, authority = authority
  )
}

app_joint_qdesn_phase180_fixture_shards_complete <- function(path, scenario_ids) {
  required <- c(
    "fixture_shard_manifest.csv", "scenario_summary.csv", "split_metadata.csv",
    "forecast_origin_plan.csv", "frozen_registry.csv", "source_identity.csv",
    "README.md", "artifact_manifest.csv"
  )
  if (!dir.exists(path) || any(!file.exists(file.path(path, required)))) return(FALSE)
  check <- tryCatch(
    app_joint_exqdesn_verify_manifest(path, "phase180_fixture_shards"),
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

app_joint_qdesn_phase180_materialize_fixture_shards <- function(
  source_dir, out_dir, scenario_ids, force = FALSE
) {
  scenario_ids <- sort(unique(as.character(scenario_ids)))
  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  if (!force && app_joint_qdesn_phase180_fixture_shards_complete(
    final_dir, scenario_ids
  )) {
    return(list(
      out_dir = final_dir,
      shard_manifest = app_read_csv(file.path(final_dir, "fixture_shard_manifest.csv")),
      reused = TRUE
    ))
  }
  source_check <- app_joint_qdesn_phase180_verify_source(
    source_dir, "phase180_fixture_source"
  )
  artifacts <- app_joint_qdesn_load_fixture_artifacts(source_dir)
  absent <- setdiff(scenario_ids, artifacts$scenario_summary$scenario_id)
  if (length(absent)) {
    stop(sprintf("Article fixture lacks scenarios: %s", paste(absent, collapse = ", ")),
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
      if (!nrow(table)) stop("Phase180 fixture sharding produced an empty table.", call. = FALSE)
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
    "# Phase180 frozen article-fixture shards", "",
    "These files are row-preserving shards of the hash-verified Phase1 article fixture.",
    "They reduce per-worker I/O and do not regenerate or alter any DGP observation.",
    "The article fixture is evaluation-only and cannot select DESN or RHS controls."
  ), readme, useBytes = TRUE)
  shard_manifest <- app_joint_qdesn_bind_rows(shard_rows)
  source_identity <- data.frame(
    source_dir = normalizePath(source_dir),
    source_manifest_sha256 = app_sha256_file(file.path(source_dir, "artifact_manifest.csv")),
    scenario_count = length(scenario_ids), row_preserving_shards = TRUE,
    stringsAsFactors = FALSE
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
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) {
      stop("Could not quarantine prior Phase180 fixture shards.", call. = FALSE)
    }
  }
  if (!file.rename(tmp, final_dir)) {
    stop("Could not publish Phase180 fixture shards.", call. = FALSE)
  }
  if (!app_joint_qdesn_phase180_fixture_shards_complete(final_dir, scenario_ids)) {
    stop("Phase180 fixture shard manifest failed.", call. = FALSE)
  }
  list(out_dir = final_dir, shard_manifest = shard_manifest, reused = FALSE)
}

app_joint_qdesn_phase180_load_fixture <- function(scenario_id, fixture_dir) {
  dirs <- app_joint_exqdesn_phase164_dirs()
  dirs$selected_fixtures <- fixture_dir
  artifacts <- app_joint_exqdesn_load_selected_fixture_artifacts(scenario_id, dirs)
  list(
    artifacts = artifacts,
    fixture = app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
  )
}

app_joint_qdesn_phase180_init_rows <- function(fit, cell, method_id) {
  blocks <- list(
    beta = as.numeric(fit$beta_mean), alpha = as.numeric(fit$alpha_mean),
    sigma = as.numeric(fit$sigma_mean)
  )
  if (!is.null(fit$gamma_mean)) blocks$gamma <- as.numeric(fit$gamma_mean)
  if (any(!is.finite(unlist(blocks, use.names = FALSE))) || any(blocks$sigma <= 0)) {
    stop("Phase180 VB initialization contains invalid values.", call. = FALSE)
  }
  app_joint_qdesn_bind_rows(lapply(names(blocks), function(block) {
    data.frame(
      mcmc_case_id = cell$mcmc_case_id[[1L]], case_id = cell$case_id[[1L]],
      scenario_id = cell$scenario_id[[1L]],
      likelihood_family = cell$likelihood_family[[1L]],
      fit_structure = cell$fit_structure[[1L]], parameter_block = block,
      parameter_index = seq_along(blocks[[block]]), value = blocks[[block]],
      initialization_method_id = method_id, stringsAsFactors = FALSE
    )
  }))
}

app_joint_qdesn_phase180_reconstruct_init <- function(
  rows, case_id, likelihood_family, fit_structure, K, p
) {
  get <- function(block, required = TRUE) {
    x <- rows[rows$mcmc_case_id == case_id & rows$parameter_block == block, , drop = FALSE]
    value <- as.numeric(x$value[order(x$parameter_index)])
    if (required && !length(value)) stop("Phase180 initialization block is missing.", call. = FALSE)
    value
  }
  combined <- list(
    beta_mean = get("beta"), alpha_mean = get("alpha"),
    sigma_mean = get("sigma"), gamma_mean = get("gamma", likelihood_family == "exAL")
  )
  if (length(combined$beta_mean) != K * p || length(combined$alpha_mean) != K ||
      length(combined$sigma_mean) != K || any(!is.finite(c(
        combined$beta_mean, combined$alpha_mean, combined$sigma_mean
      ))) || any(combined$sigma_mean <= 0) ||
      (likelihood_family == "exAL" &&
       (length(combined$gamma_mean) != K || any(!is.finite(combined$gamma_mean))))) {
    stop("Malformed Phase180 compact VB initialization.", call. = FALSE)
  }
  if (fit_structure == "joint") return(combined)
  combined$fits <- lapply(seq_len(K), function(k) {
    index <- ((k - 1L) * p + 1L):(k * p)
    out <- list(
      beta_mean = combined$beta_mean[index], alpha_mean = combined$alpha_mean[[k]],
      sigma_mean = combined$sigma_mean[[k]]
    )
    if (likelihood_family == "exAL") out$gamma_mean <- combined$gamma_mean[[k]]
    out
  })
  combined
}

app_joint_qdesn_phase180_chain_starts <- function(init_rows, rerun, contract) {
  factors <- exp(seq(log(0.70), log(1.30), length.out = contract$n_chains))
  rows <- list(); cursor <- 1L
  for (ii in seq_len(nrow(rerun))) {
    cell <- rerun[ii, , drop = FALSE]
    sigma <- init_rows$value[
      init_rows$mcmc_case_id == cell$mcmc_case_id[[1L]] &
        init_rows$parameter_block == "sigma"
    ]
    gamma <- init_rows$value[
      init_rows$mcmc_case_id == cell$mcmc_case_id[[1L]] &
        init_rows$parameter_block == "gamma"
    ]
    for (chain_id in seq_len(contract$n_chains)) {
      rows[[cursor]] <- data.frame(
        mcmc_case_id = cell$mcmc_case_id[[1L]], chain_id = chain_id,
        parameter = "sigma", quantile_index = seq_along(sigma),
        value = pmax(sigma * factors[[chain_id]], 1e-8),
        start_role = "deterministic_scale_dispersion", stringsAsFactors = FALSE
      )
      cursor <- cursor + 1L
      if (length(gamma)) {
        bounds <- t(vapply(seq_along(gamma), function(k) {
          support <- app_joint_exqdesn_support(contract$tau[[k]])
          c(support$lower[[1L]], support$upper[[1L]])
        }, numeric(2L)))
        offset <- seq(-0.30, 0.30, length.out = contract$n_chains)[[chain_id]]
        width <- bounds[, 2L] - bounds[, 1L]
        value <- pmin(pmax(gamma + offset * width, bounds[, 1L] + 1e-6),
                      bounds[, 2L] - 1e-6)
        rows[[cursor]] <- data.frame(
          mcmc_case_id = cell$mcmc_case_id[[1L]], chain_id = chain_id,
          parameter = "gamma", quantile_index = seq_along(gamma), value = value,
          start_role = "deterministic_support_dispersion", stringsAsFactors = FALSE
        )
        cursor <- cursor + 1L
      }
    }
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase180_apply_chain_start <- function(
  init, starts, job, K, p
) {
  block <- starts[
    starts$mcmc_case_id == job$mcmc_case_id[[1L]] &
      starts$chain_id == job$chain_id[[1L]], , drop = FALSE
  ]
  sigma <- block$value[block$parameter == "sigma"]
  sigma_index <- block$quantile_index[block$parameter == "sigma"]
  sigma <- sigma[order(sigma_index)]
  if (length(sigma) != K || any(!is.finite(sigma)) || any(sigma <= 0)) {
    stop("Malformed Phase180 sigma chain start.", call. = FALSE)
  }
  init$sigma_mean <- sigma
  gamma <- block$value[block$parameter == "gamma"]
  gamma_index <- block$quantile_index[block$parameter == "gamma"]
  if (length(gamma)) init$gamma_mean <- gamma[order(gamma_index)]
  if (!is.null(init$fits)) {
    init$fits <- lapply(seq_len(K), function(k) {
      index <- ((k - 1L) * p + 1L):(k * p)
      out <- list(
        beta_mean = init$beta_mean[index], alpha_mean = init$alpha_mean[[k]],
        sigma_mean = init$sigma_mean[[k]]
      )
      if (length(init$gamma_mean)) out$gamma_mean <- init$gamma_mean[[k]]
      out
    })
  }
  init
}

app_joint_qdesn_phase180_phase154_independent_al_init <- function(cell, fixture) {
  source_dir <- cell$source_dir[[1L]]
  check <- app_joint_exqdesn_verify_manifest(
    source_dir, "phase154_independent_al_initialization_source"
  )
  if (any(check$status != "pass")) {
    stop("Phase154 independent-AL initialization source failed its manifest.",
         call. = FALSE)
  }
  scale <- app_read_csv(file.path(source_dir, "scale_parameter_summary.csv"))
  qhat_rows <- app_read_csv(file.path(source_dir, "fit_quantiles_raw.csv"))
  convergence <- app_read_csv(file.path(source_dir, "vb_convergence_audit.csv"))
  keep <- function(x) {
    x$scenario_id == cell$scenario_id[[1L]] &
      x$source_model_id == cell$source_model_id[[1L]] &
      x$inference == "VB"
  }
  scale <- scale[keep(scale), , drop = FALSE]
  qhat_rows <- qhat_rows[keep(qhat_rows), , drop = FALSE]
  convergence <- convergence[keep(convergence), , drop = FALSE]
  K <- length(fixture$tau); p <- ncol(fixture$Z)
  if (nrow(scale) != K || nrow(convergence) != 1L ||
      anyDuplicated(scale$quantile_index) ||
      !identical(sort(as.numeric(scale$tau)), sort(as.numeric(fixture$tau)))) {
    stop("Phase154 independent-AL VB summary is incomplete.", call. = FALSE)
  }
  scale <- scale[order(scale$quantile_index), , drop = FALSE]
  qhat <- matrix(NA_real_, nrow(fixture$Z), K)
  beta <- matrix(NA_real_, p, K)
  for (k in seq_len(K)) {
    block <- qhat_rows[qhat_rows$quantile_index == k, , drop = FALSE]
    index <- match(fixture$row_meta$full_time_index, block$full_time_index)
    if (nrow(block) != nrow(fixture$Z) || anyNA(index)) {
      stop("Phase154 independent-AL quantile path does not match the fixture.",
           call. = FALSE)
    }
    qhat[, k] <- as.numeric(block$qhat_raw[index])
    least_squares <- stats::lm.fit(
      fixture$Z, qhat[, k] - as.numeric(scale$alpha_mean[[k]])
    )
    coefficient <- as.numeric(least_squares$coefficients)
    coefficient[is.na(coefficient)] <- 0
    beta[, k] <- coefficient
  }
  reconstructed <- fixture$Z %*% beta + matrix(
    as.numeric(scale$alpha_mean), nrow(fixture$Z), K, byrow = TRUE
  )
  tolerance <- 1e-8 * max(1, max(abs(qhat)))
  if (any(!is.finite(c(beta, scale$alpha_mean, scale$sigma_mean))) ||
      any(scale$sigma_mean <= 0) ||
      max(abs(reconstructed - qhat)) > tolerance) {
    stop("Phase154 independent-AL VB coefficient reconstruction failed.",
         call. = FALSE)
  }
  beta_mean <- as.numeric(beta)
  fits <- lapply(seq_len(K), function(k) {
    list(
      beta_mean = beta[, k], alpha_mean = scale$alpha_mean[[k]],
      sigma_mean = scale$sigma_mean[[k]], converged = convergence$converged[[1L]]
    )
  })
  list(
    beta_mean = beta_mean, alpha_mean = as.numeric(scale$alpha_mean),
    sigma_mean = as.numeric(scale$sigma_mean), qhat_mean = reconstructed,
    fits = fits, converged = isTRUE(convergence$converged[[1L]]),
    initialization_source_manifest_sha256 = app_sha256_file(file.path(
      source_dir, "artifact_manifest.csv"
    )),
    initialization_source_role = "phase154_verified_vb_path_reconstruction"
  )
}

app_joint_qdesn_phase180_initialize_cell <- function(cell, fixture_dir) {
  loaded <- app_joint_qdesn_phase180_load_fixture(cell$scenario_id[[1L]], fixture_dir)
  fixture <- loaded$fixture
  started <- proc.time()[["elapsed"]]
  if (cell$likelihood_family[[1L]] == "exAL") {
    candidate <- cell
    candidate$inference_method_id <- "VB1_structured_v"
    fit <- app_joint_exqdesn_phase178_fit_structured_v(candidate, fixture)
    method_id <- "VB1_structured_v"
  } else if (cell$fit_structure[[1L]] == "independent") {
    fit <- app_joint_qdesn_phase180_phase154_independent_al_init(cell, fixture)
    method_id <- "phase154_verified_vb_path_reconstruction"
  } else {
    spec <- app_joint_qdesn_phase122_select_spec(cell$source_model_id[[1L]])
    controls <- app_joint_qdesn_phase122_controls_from_row(cell, n_cores = 1L)
    fit <- app_joint_qdesn_fit_model_adaptive(fixture, spec, controls)
    method_id <- "legacy_mean_field_vb"
  }
  elapsed <- proc.time()[["elapsed"]] - started
  init <- app_joint_qdesn_phase180_init_rows(fit, cell, method_id)
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
    mcmc_case_id = cell$mcmc_case_id[[1L]], case_id = cell$case_id[[1L]],
    scenario_id = cell$scenario_id[[1L]],
    source_model_id = cell$source_model_id[[1L]],
    likelihood_family = cell$likelihood_family[[1L]],
    fit_structure = cell$fit_structure[[1L]], initialization_method_id = method_id,
    finite_initialization = finite,
    vb_converged = vb_converged,
    fit_raw_crossing_pairs = sum(contract$raw_crossing$n_crossing_pairs),
    fit_contract_crossing_pairs = sum(contract$contract_crossing$n_crossing_pairs),
    elapsed_seconds = elapsed,
    status = if (finite && sum(contract$contract_crossing$n_crossing_pairs) == 0L) {
      "pass"
    } else "fail",
    stringsAsFactors = FALSE
  )
  list(init = init, audit = audit)
}

app_joint_qdesn_phase180_init_cache_complete <- function(path, identity) {
  if (!file.exists(file.path(path, "artifact_manifest.csv"))) return(FALSE)
  check <- tryCatch(
    app_joint_exqdesn_verify_manifest(path, "phase180_initialization_cache"),
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

app_joint_qdesn_phase180_initialize_cached <- function(
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
    stringsAsFactors = FALSE
  )
  if (!force && app_joint_qdesn_phase180_init_cache_complete(path, identity)) {
    return(list(
      init = app_read_csv(file.path(path, "vb_initialization.csv")),
      audit = app_read_csv(file.path(path, "vb_initialization_audit.csv")),
      cache_status = "reused_verified"
    ))
  }
  result <- app_joint_qdesn_phase180_initialize_cell(cell, fixture_dir)
  tmp <- paste0(path, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase180 compact VB initialization cache", "",
    "This cache is keyed by code commit, frozen control-row hash, and fixture manifest.",
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
      stop("Could not quarantine stale Phase180 initialization cache.", call. = FALSE)
    }
  }
  if (!file.rename(tmp, path) ||
      !app_joint_qdesn_phase180_init_cache_complete(path, identity)) {
    stop("Phase180 initialization cache failed atomic publication.", call. = FALSE)
  }
  result$cache_status <- "computed"
  result
}

app_joint_qdesn_phase180_worker_plan <- function(rerun, dirs, contract) {
  rows <- list(); worker_id <- 0L
  for (ii in seq_len(nrow(rerun))) {
    for (chain_id in seq_len(contract$n_chains)) {
      worker_id <- worker_id + 1L
      row <- rerun[ii, , drop = FALSE]
      row$worker_id <- worker_id
      row$chain_id <- chain_id
      row$wave_id <- as.integer(ceiling(worker_id / contract$default_concurrent_workers))
      row$chain_seed <- as.integer(
        contract$chain_seed_base + ii * 250000L + chain_id * 10000L
      )
      row$tau_seed_stride <- contract$tau_seed_stride
      row$sigma_upper_multiplier <- contract$sigma_upper_multiplier
      row$seed_role <- "phase180_balanced_article_completion_chain"
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
      any(out$chain_seed >= .Machine$integer.max)) {
    stop("Phase180 worker plan has invalid counts or seed collisions.", call. = FALSE)
  }
  out
}

app_joint_qdesn_phase180_component_seed_plan <- function(plan, tau) {
  rows <- lapply(seq_len(nrow(plan)), function(ii) {
    job <- plan[ii, , drop = FALSE]
    if (job$fit_structure[[1L]] == "joint") {
      return(data.frame(
        worker_id = job$worker_id[[1L]], mcmc_case_id = job$mcmc_case_id[[1L]],
        chain_id = job$chain_id[[1L]], quantile_index = NA_integer_,
        tau = NA_real_, component_seed = job$chain_seed[[1L]],
        seed_role = "joint_multiquantile_component", stringsAsFactors = FALSE
      ))
    }
    data.frame(
      worker_id = job$worker_id[[1L]], mcmc_case_id = job$mcmc_case_id[[1L]],
      chain_id = job$chain_id[[1L]], quantile_index = seq_along(tau), tau = tau,
      component_seed = as.integer(
        job$chain_seed[[1L]] + seq_along(tau) * job$tau_seed_stride[[1L]]
      ),
      seed_role = "independent_quantile_component", stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  if (anyDuplicated(out$component_seed) ||
      any(out$component_seed >= .Machine$integer.max)) {
    stop("Phase180 component seed plan has collisions or overflow.", call. = FALSE)
  }
  out
}

app_joint_qdesn_phase180_load_freeze <- function(freeze_dir) {
  check <- app_joint_exqdesn_verify_manifest(freeze_dir, "phase180_freeze")
  if (any(check$status != "pass")) stop("Phase180 freeze manifest failed.", call. = FALSE)
  list(
    dir = normalizePath(freeze_dir), verification = check,
    contract = app_joint_qdesn_phase180_read_contract(
      file.path(freeze_dir, "phase180_score_contract.csv")
    ),
    config = app_read_csv(file.path(freeze_dir, "run_config.csv")),
    registry = app_read_csv(file.path(freeze_dir, "final_selected_cell_registry.csv")),
    controls = app_read_csv(file.path(freeze_dir, "rerun_cell_plan.csv")),
    plan = app_read_csv(file.path(freeze_dir, "worker_plan.csv")),
    components = app_read_csv(file.path(freeze_dir, "component_seed_plan.csv")),
    init = app_read_csv(file.path(freeze_dir, "vb_initialization.csv")),
    starts = app_read_csv(file.path(freeze_dir, "chain_start_values.csv")),
    readiness = app_read_csv(file.path(freeze_dir, "readiness_assessment.csv"))
  )
}

app_joint_qdesn_phase180_prepare <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  out_dir = NULL, fixture_dir = NULL, n_vb_cores = 8L, force = FALSE
) {
  dirs <- app_joint_qdesn_phase180_dirs(cache_root)
  out_dir <- out_dir %||% dirs$freeze
  fixture_dir <- fixture_dir %||% dirs$fixtures
  contract <- app_joint_qdesn_phase180_read_contract()
  if (!force && file.exists(file.path(out_dir, "artifact_manifest.csv"))) {
    check <- tryCatch(
      app_joint_exqdesn_verify_manifest(out_dir, "phase180_freeze"),
      error = function(e) NULL
    )
    if (!is.null(check) && all(check$status == "pass")) {
      freeze <- app_joint_qdesn_phase180_load_freeze(out_dir)
      return(list(
        out_dir = freeze$dir, plan = freeze$plan,
        readiness = freeze$readiness, reused = TRUE
      ))
    }
  }
  source <- app_joint_qdesn_phase180_build_cell_registry(cache_root, contract)
  shards <- app_joint_qdesn_phase180_materialize_fixture_shards(
    dirs$fixture_source, fixture_dir, source$registry$scenario_id, force = force
  )
  rerun <- source$registry[
    source$registry$source_action != "reuse_phase172_verified_draws", , drop = FALSE
  ]
  plan <- app_joint_qdesn_phase180_worker_plan(rerun, dirs, contract)
  components <- app_joint_qdesn_phase180_component_seed_plan(plan, contract$tau)
  cases <- rerun[order(rerun$cell_index), , drop = FALSE]
  initialize <- function(ii) try(
    app_joint_qdesn_phase180_initialize_cached(
      cases[ii, , drop = FALSE], fixture_dir, dirs$initialization_work,
      force = force
    ), silent = TRUE
  )
  initialization <- if (.Platform$OS.type != "windows" && n_vb_cores > 1L) {
    parallel::mclapply(
      seq_len(nrow(cases)), initialize,
      mc.cores = min(as.integer(n_vb_cores), nrow(cases)), mc.preschedule = FALSE
    )
  } else lapply(seq_len(nrow(cases)), initialize)
  failed <- vapply(initialization, inherits, logical(1L), "try-error")
  if (any(failed)) {
    stop(sprintf(
      "Phase180 VB initialization failed: %s",
      paste(vapply(initialization[failed], as.character, character(1L)), collapse = " | ")
    ), call. = FALSE)
  }
  init <- app_joint_qdesn_bind_rows(lapply(initialization, `[[`, "init"))
  init_audit <- app_joint_qdesn_bind_rows(lapply(initialization, `[[`, "audit"))
  starts <- app_joint_qdesn_phase180_chain_starts(init, rerun, contract)
  if (any(init_audit$status != "pass") ||
      length(unique(init$mcmc_case_id)) != contract$expected_rerun_cells ||
      anyDuplicated(components$component_seed)) {
    stop("Phase180 initialization or seed gate failed.", call. = FALSE)
  }
  source_hash <- function(path) app_sha256_file(file.path(path, "artifact_manifest.csv"))
  plan$fixture_manifest_sha256 <- source_hash(fixture_dir)
  plan$code_commit <- app_joint_exqdesn_phase171_git_value(c("rev-parse", "HEAD"))
  plan$source_control_file_sha256 <- NA_character_
  plan$source_control_row_sha256 <- rerun$source_control_row_sha256[
    match(plan$mcmc_case_id, rerun$mcmc_case_id)
  ]
  source_inventory <- source$registry[, c(
    "cell_index", "case_id", "scenario_id", "source_model_id",
    "likelihood_family", "fit_structure", "source_action", "source_phase",
    "source_dir", "phase172_case_dir", "source_control_row_sha256"
  ), drop = FALSE]
  control_hash <- data.frame(
    case_id = source$registry$case_id,
    source_action = source$registry$source_action,
    control_row_sha256 = source$registry$source_control_row_sha256,
    phase179_final_control = source$registry$case_id %in%
      app_read_csv(file.path(dirs$phase179, "final_case_specific_controls.csv"))$case_id,
    status = "pass", stringsAsFactors = FALSE
  )
  fixture_identity <- app_read_csv(file.path(fixture_dir, "fixture_shard_manifest.csv"))
  fixture_identity$status <- "pass"
  compute <- data.frame(
    likelihood_family = c("AL", "exAL"),
    rerun_cells = c(sum(rerun$likelihood_family == "AL"),
                    sum(rerun$likelihood_family == "exAL")),
    chains_per_cell = contract$n_chains,
    workers = c(sum(plan$likelihood_family == "AL"),
                sum(plan$likelihood_family == "exAL")),
    n_iter = c(contract$al_n_iter, contract$exal_n_iter),
    burn = c(contract$al_burn, contract$exal_burn),
    thin = c(contract$al_thin, contract$exal_thin),
    score_draws_per_chain = contract$score_draws_per_chain,
    stringsAsFactors = FALSE
  )
  readiness <- data.frame(
    phase_id = contract$version, gate_status = "pass",
    final_cells = nrow(source$registry), phase172_reuse_cells = sum(
      source$registry$source_action == "reuse_phase172_verified_draws"
    ),
    rerun_cells = nrow(rerun), planned_workers = nrow(plan),
    planned_components = nrow(components),
    unique_chain_seeds = length(unique(plan$chain_seed)),
    unique_component_seeds = length(unique(components$component_seed)),
    article_fixture_used_for_selection = FALSE,
    global_specification_selected = FALSE, article_assets_modified = FALSE,
    recommendation = "launch_balanced_retained_draw_completion",
    stringsAsFactors = FALSE
  )
  if (readiness$final_cells != contract$expected_final_cells ||
      readiness$phase172_reuse_cells != contract$expected_reuse_cells ||
      readiness$rerun_cells != contract$expected_rerun_cells ||
      readiness$planned_workers != contract$expected_new_workers) {
    stop("Phase180 readiness counts differ from the frozen contract.", call. = FALSE)
  }

  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase180 balanced DGP-score completion freeze", "",
    "The final registry contains 32 scenario-model cells.",
    "Eleven hash-verified exact-M0 exAL cells reuse retained Phase172 draws.",
    "Five Phase179-resolved exAL cells and all sixteen AL cells are rerun.",
    "Controls remain scenario/readout specific; the article fixture cannot retune them.",
    "Every new worker writes one compact compressed posterior checkpoint.",
    "No article asset or historical runtime artifact is modified by this freeze."
  ), readme, useBytes = TRUE)
  contract_path <- file.path(tmp, "phase180_score_contract.csv")
  file.copy(contract$path, contract_path, overwrite = TRUE)
  paths <- c(
    phase180_score_contract = normalizePath(contract_path, mustWork = TRUE),
    final_selected_cell_registry = write(
      source$registry, "final_selected_cell_registry.csv"
    ),
    source_reuse_inventory = write(source_inventory, "source_reuse_inventory.csv"),
    rerun_cell_plan = write(rerun, "rerun_cell_plan.csv"),
    worker_plan = write(plan, "worker_plan.csv"),
    chain_seed_plan = write(
      plan[, c("worker_id", "mcmc_case_id", "chain_id", "chain_seed", "seed_role")],
      "chain_seed_plan.csv"
    ),
    component_seed_plan = write(components, "component_seed_plan.csv"),
    fixture_identity_audit = write(fixture_identity, "fixture_identity_audit.csv"),
    control_hash_audit = write(control_hash, "control_hash_audit.csv"),
    source_manifest_verification = write(
      source$source_checks, "source_manifest_verification.csv"
    ),
    phase172_worker_manifest_verification = write(
      source$phase172_reuse_checks, "phase172_worker_manifest_verification.csv"
    ),
    vb_initialization = write(init, "vb_initialization.csv"),
    chain_start_values = write(starts, "chain_start_values.csv"),
    vb_initialization_audit = write(init_audit, "vb_initialization_audit.csv"),
    compute_budget = write(compute, "compute_budget.csv"),
    readiness_assessment = write(readiness, "readiness_assessment.csv"),
    run_config = write(data.frame(
      phase_id = contract$version, cache_root = normalizePath(cache_root),
      fixture_source_dir = normalizePath(dirs$fixture_source),
      fixture_dir = normalizePath(fixture_dir), result_dir = dirs$chains,
      code_commit = unique(plan$code_commit),
      primary_metric = contract$primary_metric,
      article_fixture_selection_allowed = FALSE,
      article_assets_modified = FALSE, stringsAsFactors = FALSE
    ), "run_config.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine prior Phase180 freeze.", call. = FALSE)
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish Phase180 freeze.", call. = FALSE)
  freeze <- app_joint_qdesn_phase180_load_freeze(final_dir)
  list(out_dir = freeze$dir, plan = freeze$plan, readiness = readiness, reused = FALSE)
}

app_joint_qdesn_phase180_checkpoint_dir <- function(worker_dir) {
  file.path(worker_dir, "checkpoint")
}

app_joint_qdesn_phase180_checkpoint_complete <- function(worker_dir) {
  path <- app_joint_qdesn_phase180_checkpoint_dir(worker_dir)
  required <- c(
    "posterior_draws.csv.gz", "sampler_diagnostics.csv",
    "checkpoint_metadata.csv", "artifact_manifest.csv"
  )
  if (!dir.exists(path) || any(!file.exists(file.path(path, required)))) return(FALSE)
  check <- tryCatch(
    app_joint_exqdesn_verify_manifest(path, "phase180_checkpoint"),
    error = function(e) NULL
  )
  !is.null(check) && nrow(check) == 3L && all(check$status == "pass")
}

app_joint_qdesn_phase180_worker_complete <- function(worker_dir) {
  required <- c(
    file.path("checkpoint", "posterior_draws.csv.gz"),
    file.path("checkpoint", "sampler_diagnostics.csv"),
    file.path("checkpoint", "checkpoint_metadata.csv"),
    file.path("checkpoint", "artifact_manifest.csv"),
    "chain_summary.csv", "runtime.csv", "provenance.csv", "README.md",
    "artifact_manifest.csv"
  )
  if (!dir.exists(worker_dir) || any(!file.exists(file.path(worker_dir, required)))) {
    return(FALSE)
  }
  check <- tryCatch(
    app_joint_exqdesn_verify_manifest(worker_dir, "phase180_worker"),
    error = function(e) NULL
  )
  !is.null(check) && nrow(check) > 0L && all(check$status == "pass") &&
    app_joint_qdesn_phase180_checkpoint_complete(worker_dir)
}

app_joint_qdesn_phase180_draw_frame <- function(fit) {
  blocks <- list(
    beta = as.data.frame(fit$beta_draws, check.names = FALSE),
    alpha = as.data.frame(fit$alpha_draws, check.names = FALSE),
    sigma = as.data.frame(fit$sigma_draws, check.names = FALSE)
  )
  if (!is.null(fit$gamma_draws)) {
    blocks$gamma <- as.data.frame(fit$gamma_draws, check.names = FALSE)
  }
  n <- vapply(blocks, nrow, integer(1L))
  if (!length(n) || length(unique(n)) != 1L || any(n <= 0L) ||
      any(vapply(blocks, ncol, integer(1L)) <= 0L)) {
    stop("Phase180 posterior draw blocks are malformed.", call. = FALSE)
  }
  digits <- c(beta = 4L, alpha = 2L, sigma = 2L, gamma = 2L)
  out <- data.frame(draw_index = seq_len(n[[1L]]), stringsAsFactors = FALSE)
  for (name in names(blocks)) {
    block <- blocks[[name]]
    names(block) <- sprintf(paste0(name, "_%0", digits[[name]], "d"), seq_len(ncol(block)))
    out[names(block)] <- block
  }
  numeric_block <- as.matrix(out[, -1L, drop = FALSE])
  if (any(!is.finite(numeric_block)) || any(fit$sigma_draws <= 0)) {
    stop("Phase180 posterior draw frame contains invalid values.", call. = FALSE)
  }
  out
}

app_joint_qdesn_phase180_read_fit <- function(worker_dir, tau, seed, chain_id) {
  checkpoint <- app_joint_qdesn_phase180_checkpoint_dir(worker_dir)
  draws <- app_joint_exqdesn_phase156_read_csv(
    file.path(checkpoint, "posterior_draws.csv.gz")
  )
  select <- function(prefix) {
    as.matrix(draws[, grepl(paste0("^", prefix, "_"), names(draws)), drop = FALSE])
  }
  beta <- select("beta"); alpha <- select("alpha"); sigma <- select("sigma")
  gamma <- select("gamma")
  K <- length(tau)
  if (!nrow(draws) || ncol(beta) <= 0L || ncol(beta) %% K != 0L ||
      ncol(alpha) != K || ncol(sigma) != K ||
      (!ncol(gamma) %in% c(0L, K)) || any(!is.finite(c(beta, alpha, sigma))) ||
      any(sigma <= 0) || (ncol(gamma) && any(!is.finite(gamma)))) {
    stop("Malformed Phase180 posterior checkpoint dimensions.", call. = FALSE)
  }
  out <- list(
    beta_draws = beta, alpha_draws = alpha, sigma_draws = sigma,
    beta_mean = colMeans(beta), alpha_mean = colMeans(alpha),
    sigma_mean = colMeans(sigma), tau = tau, seed = as.integer(seed),
    chain_id = as.integer(chain_id), init_source = "provided"
  )
  if (ncol(gamma)) {
    out$gamma_draws <- gamma
    out$gamma_mean <- colMeans(gamma)
  }
  out$qhat_mean <- NULL
  class(out) <- c("joint_qvp_qdesn_tiny_fit", "list")
  out
}

app_joint_qdesn_phase180_sampler_rows <- function(fit, fixture, job) {
  if (!is.null(fit$gamma_draws)) {
    return(app_joint_exqdesn_phase169_sampler_rows(fit, fixture, job))
  }
  app_joint_qdesn_bind_rows(lapply(seq_along(fixture$tau), function(k) {
    sigma <- fit$sigma_draws[, k]
    data.frame(
      worker_id = job$worker_id[[1L]], mcmc_case_id = job$mcmc_case_id[[1L]],
      scenario_id = job$scenario_id[[1L]], fit_structure = job$fit_structure[[1L]],
      inference_method_id = job$inference_method_id[[1L]],
      chain_id = job$chain_id[[1L]], quantile_index = k,
      tau = fixture$tau[[k]], sigma_mean = mean(sigma),
      sigma_sd = stats::sd(sigma),
      sigma_rough_ess = app_joint_exqdesn_rough_ess_one_chain(sigma),
      gamma_mean = NA_real_, gamma_sd = NA_real_, gamma_rough_ess = NA_real_,
      branch_transitions = NA_integer_,
      sampler_block = "AL_scale_only", stringsAsFactors = FALSE
    )
  }))
}

app_joint_qdesn_phase180_write_checkpoint <- function(
  fit, fixture, job, component, elapsed_seconds, freeze_dir, worker_dir
) {
  path <- app_joint_qdesn_phase180_checkpoint_dir(worker_dir)
  if (dir.exists(path)) {
    quarantine <- paste0(path, ".invalid.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(path, quarantine)) {
      stop("Could not quarantine an incomplete Phase180 checkpoint.", call. = FALSE)
    }
  }
  app_ensure_dir(path)
  draws <- app_joint_qdesn_phase180_draw_frame(fit)
  sampler <- app_joint_qdesn_phase180_sampler_rows(fit, fixture, job)
  component_hash <- app_joint_exqdesn_phase172_table_hash(component)
  metadata <- data.frame(
    worker_id = job$worker_id[[1L]], mcmc_case_id = job$mcmc_case_id[[1L]],
    case_id = job$case_id[[1L]], scenario_id = job$scenario_id[[1L]],
    source_model_id = job$source_model_id[[1L]],
    likelihood_family = job$likelihood_family[[1L]],
    fit_structure = job$fit_structure[[1L]],
    inference_method_id = job$inference_method_id[[1L]],
    chain_id = job$chain_id[[1L]], chain_seed = job$chain_seed[[1L]],
    component_seed_count = nrow(component),
    component_seed_table_sha256 = component_hash,
    source_control_row_sha256 = job$source_control_row_sha256[[1L]],
    fixture_manifest_sha256 = job$fixture_manifest_sha256[[1L]],
    code_commit = job$code_commit[[1L]], n_iter = job$n_iter[[1L]],
    burn = job$burn[[1L]], thin = job$thin[[1L]], n_keep = nrow(draws),
    init_source = fit$init_source %||% "provided",
    elapsed_seconds = as.numeric(elapsed_seconds),
    freeze_manifest_sha256 = app_sha256_file(file.path(freeze_dir, "artifact_manifest.csv")),
    checkpoint_role = "phase180_balanced_postfit_prescore",
    stringsAsFactors = FALSE
  )
  paths <- c(
    posterior_draws = app_joint_exqdesn_phase157_write_gzip_csv(
      draws, file.path(path, "posterior_draws.csv.gz")
    ),
    sampler_diagnostics = app_joint_qvp_write_csv(
      sampler, file.path(path, "sampler_diagnostics.csv")
    ),
    checkpoint_metadata = app_joint_qvp_write_csv(
      metadata, file.path(path, "checkpoint_metadata.csv")
    )
  )
  manifest <- app_joint_exqdesn_write_manifest(paths, path)
  if (!app_joint_qdesn_phase180_checkpoint_complete(worker_dir)) {
    stop("Phase180 checkpoint manifest failed.", call. = FALSE)
  }
  list(
    fit = fit, draws = draws, sampler = sampler, metadata = metadata,
    paths = c(paths, checkpoint_manifest = manifest$manifest_path)
  )
}

app_joint_qdesn_phase180_load_checkpoint <- function(
  worker_dir, fixture, job, component, freeze_dir
) {
  if (!app_joint_qdesn_phase180_checkpoint_complete(worker_dir)) {
    stop("Phase180 checkpoint is incomplete.", call. = FALSE)
  }
  path <- app_joint_qdesn_phase180_checkpoint_dir(worker_dir)
  metadata <- app_read_csv(file.path(path, "checkpoint_metadata.csv"))
  expected <- c(
    worker_id = as.character(job$worker_id[[1L]]),
    chain_seed = as.character(job$chain_seed[[1L]]),
    source_control_row_sha256 = as.character(job$source_control_row_sha256[[1L]]),
    fixture_manifest_sha256 = as.character(job$fixture_manifest_sha256[[1L]]),
    code_commit = as.character(job$code_commit[[1L]]),
    component_seed_table_sha256 = app_joint_exqdesn_phase172_table_hash(component),
    freeze_manifest_sha256 = app_sha256_file(file.path(freeze_dir, "artifact_manifest.csv"))
  )
  actual <- vapply(names(expected), function(name) {
    as.character(metadata[[name]][[1L]])
  }, character(1L))
  if (nrow(metadata) != 1L || !identical(unname(actual), unname(expected))) {
    stop("Phase180 checkpoint identity differs from its freeze.", call. = FALSE)
  }
  list(
    fit = app_joint_qdesn_phase180_read_fit(
      worker_dir, fixture$tau, job$chain_seed[[1L]], job$chain_id[[1L]]
    ),
    draws = app_joint_exqdesn_phase156_read_csv(
      file.path(path, "posterior_draws.csv.gz")
    ),
    sampler = app_read_csv(file.path(path, "sampler_diagnostics.csv")),
    metadata = metadata,
    paths = c(
      posterior_draws = file.path(path, "posterior_draws.csv.gz"),
      sampler_diagnostics = file.path(path, "sampler_diagnostics.csv"),
      checkpoint_metadata = file.path(path, "checkpoint_metadata.csv"),
      checkpoint_manifest = file.path(path, "artifact_manifest.csv")
    )
  )
}

app_joint_qdesn_phase180_fit_chain <- function(job, control, fixture, init) {
  K <- length(fixture$tau)
  alpha_prior_sd <- app_joint_qdesn_parse_numeric_vector(
    control$alpha_prior_sd[[1L]], "alpha_prior_sd", allow_inf = TRUE
  )
  sigma_upper <- max(
    1, as.numeric(job$sigma_upper_multiplier[[1L]]) *
      max(init$sigma_mean, na.rm = TRUE)
  )
  common <- list(
    y = fixture$y, Z = fixture$Z, tau = fixture$tau,
    n_iter = as.integer(job$n_iter[[1L]]), burn = as.integer(job$burn[[1L]]),
    thin = as.integer(job$thin[[1L]]), seed = as.integer(job$chain_seed[[1L]]),
    kappa = 1, tau0 = as.numeric(control$tau0[[1L]]),
    zeta2 = as.numeric(control$zeta2[[1L]]),
    a_sigma = as.numeric(control$a_sigma[[1L]]),
    b_sigma = as.numeric(control$b_sigma[[1L]]),
    alpha_prior_mean = "empirical_quantile", alpha_prior_sd = alpha_prior_sd,
    alpha_min_spacing = if (job$fit_structure[[1L]] == "joint") {
      as.numeric(control$alpha_min_spacing[[1L]])
    } else 0,
    max_dense_dim = as.integer(control$max_dense_dim[[1L]]),
    sigma_bounds = c(1e-8, sigma_upper), init = init
  )
  if (job$likelihood_family[[1L]] == "exAL") {
    common$gamma_init <- init$gamma_mean
    common$gamma_slice_width <- as.numeric(control$gamma_slice_width[[1L]])
    common$gamma_slice_max_steps <- as.integer(control$gamma_slice_max_steps[[1L]])
    if (job$fit_structure[[1L]] == "joint") {
      return(do.call(app_joint_exqdesn_fit_mcmc_dispatch, c(
        list(method_id = "M0_v_collapsed_support_logit"), common
      )))
    }
    common$tau_seed_stride <- as.integer(job$tau_seed_stride[[1L]])
    return(do.call(app_joint_exqdesn_fit_independent_mcmc_dispatch, c(
      list(method_id = "M0_v_collapsed_support_logit"), common
    )))
  }
  if (job$fit_structure[[1L]] == "joint") {
    return(do.call(app_joint_qvp_fit_al_mcmc_tiny, common))
  }
  fits <- lapply(seq_len(K), function(k) {
    one <- common
    one$tau <- fixture$tau[[k]]
    one$seed <- as.integer(job$chain_seed[[1L]] + k * job$tau_seed_stride[[1L]])
    one$alpha_prior_sd <- app_joint_qdesn_alpha_prior_sd_for_tau(
      alpha_prior_sd, k, K
    )
    one$alpha_min_spacing <- 0
    one$init <- init$fits[[k]]
    do.call(app_joint_qvp_fit_al_mcmc_tiny, one)
  })
  app_joint_qdesn_phase122_combine_independent_chain(
    fits, fixture$Z, fixture$tau, job$chain_id[[1L]], job$chain_seed[[1L]]
  )
}

app_joint_qdesn_phase180_score_meta <- function(job) {
  data.frame(
    case_id = job$case_id[[1L]], scenario_id = job$scenario_id[[1L]],
    base_scenario_id = job$base_scenario_id[[1L]],
    source_model_id = job$source_model_id[[1L]], model_id = job$model_id[[1L]],
    display_label = job$display_label[[1L]],
    likelihood = job$likelihood_family[[1L]],
    fit_structure = job$fit_structure[[1L]], inference = "MCMC",
    inference_method_id = job$inference_method_id[[1L]],
    source_candidate_id = job$candidate_id[[1L]], stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase180_run_worker <- function(
  freeze_dir, worker_id, reuse_completed = TRUE, failure_dir = NULL
) {
  freeze <- app_joint_qdesn_phase180_load_freeze(freeze_dir)
  worker_id <- as.integer(worker_id)[[1L]]
  job <- freeze$plan[freeze$plan$worker_id == worker_id, , drop = FALSE]
  if (nrow(job) != 1L) stop("Unknown Phase180 worker id.", call. = FALSE)
  worker_dir <- job$worker_output_dir[[1L]]
  if (reuse_completed && app_joint_qdesn_phase180_worker_complete(worker_dir)) {
    return(list(worker_id = worker_id, status = "reused_verified", worker_dir = worker_dir))
  }
  component <- freeze$components[freeze$components$worker_id == worker_id, , drop = FALSE]
  expected <- if (job$fit_structure[[1L]] == "joint") 1L else length(freeze$contract$tau)
  if (nrow(component) != expected || anyDuplicated(component$component_seed)) {
    stop("Malformed Phase180 component seed plan.", call. = FALSE)
  }
  has_checkpoint <- app_joint_qdesn_phase180_checkpoint_complete(worker_dir)
  if (!has_checkpoint && dir.exists(worker_dir) &&
      length(list.files(worker_dir, all.files = TRUE, no.. = TRUE))) {
    quarantine <- paste0(worker_dir, ".incomplete.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(worker_dir, quarantine)) {
      stop("Could not quarantine incomplete Phase180 worker.", call. = FALSE)
    }
  }
  app_ensure_dir(worker_dir)
  tryCatch({
    control <- freeze$controls[
      freeze$controls$mcmc_case_id == job$mcmc_case_id[[1L]], , drop = FALSE
    ]
    if (nrow(control) != 1L ||
        control$source_control_row_sha256[[1L]] != job$source_control_row_sha256[[1L]]) {
      stop("Phase180 worker could not resolve its frozen control.", call. = FALSE)
    }
    loaded <- app_joint_qdesn_phase180_load_fixture(
      job$scenario_id[[1L]], freeze$config$fixture_dir[[1L]]
    )
    fixture <- loaded$fixture; K <- length(fixture$tau); p <- ncol(fixture$Z)
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
        fit, fixture, job, component, elapsed, freeze$dir, worker_dir
      )
    }
    fit <- checkpoint$fit; draws <- checkpoint$draws
    meta <- app_joint_qdesn_phase180_score_meta(job)
    fit_score <- app_joint_qdesn_phase122_score_qhat(
      meta, fixture, app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau),
      "qhat", "phase180_chain_fit"
    )
    forecast_score <- app_joint_qdesn_phase122_forecast_scores(
      meta, loaded$artifacts, job$scenario_id[[1L]], fixture, fit,
      "qhat", "phase180_chain_forecast"
    )
    contract_crossings <- sum(fit_score$contract_crossing$n_crossing_pairs) +
      sum(forecast_score$contract_crossing$n_crossing_pairs)
    summary <- data.frame(
      worker_id = worker_id, mcmc_case_id = job$mcmc_case_id[[1L]],
      case_id = job$case_id[[1L]], scenario_id = job$scenario_id[[1L]],
      source_model_id = job$source_model_id[[1L]],
      likelihood_family = job$likelihood_family[[1L]],
      fit_structure = job$fit_structure[[1L]],
      inference_method_id = job$inference_method_id[[1L]],
      chain_id = job$chain_id[[1L]], chain_seed = job$chain_seed[[1L]],
      n_iter = job$n_iter[[1L]], burn = job$burn[[1L]], thin = job$thin[[1L]],
      n_keep = nrow(draws), draws_all_finite = all(is.finite(as.matrix(
        draws[, -1L, drop = FALSE]
      ))),
      fit_truth_mae = mean(fit_score$scored$truth_abs_error),
      forecast_truth_mae = mean(forecast_score$scored$truth_abs_error),
      fit_check_loss_mean = mean(fit_score$scored$check_loss),
      forecast_check_loss_mean = mean(forecast_score$scored$check_loss),
      fit_raw_crossing_pairs = sum(fit_score$raw_crossing$n_crossing_pairs),
      forecast_raw_crossing_pairs = sum(forecast_score$raw_crossing$n_crossing_pairs),
      contract_crossing_pairs = contract_crossings,
      min_sigma = min(fit$sigma_draws), max_sigma = max(fit$sigma_draws),
      min_gamma = if (!is.null(fit$gamma_draws)) min(fit$gamma_draws) else NA_real_,
      max_gamma = if (!is.null(fit$gamma_draws)) max(fit$gamma_draws) else NA_real_,
      elapsed_seconds = checkpoint$metadata$elapsed_seconds[[1L]],
      stringsAsFactors = FALSE
    )
    if (!summary$draws_all_finite[[1L]] || contract_crossings != 0L) {
      stop("Phase180 worker failed the finite/noncrossing contract.", call. = FALSE)
    }
    readme <- file.path(worker_dir, "README.md")
    writeLines(c(
      sprintf("# Phase180 worker %d", worker_id), "",
      sprintf("- Cell: `%s`", job$mcmc_case_id[[1L]]),
      sprintf("- Chain: %d", job$chain_id[[1L]]),
      sprintf("- Likelihood/sampler: `%s` / `%s`", job$likelihood_family[[1L]],
              job$inference_method_id[[1L]]),
      "- This worker is evaluation-only and cannot change a frozen model control.",
      "- Posterior draws use compressed CSV; no serialized R workspace is retained."
    ), readme, useBytes = TRUE)
    runtime <- summary[, c(
      "worker_id", "mcmc_case_id", "case_id", "chain_id", "chain_seed",
      "elapsed_seconds"
    ), drop = FALSE]
    paths <- c(
      checkpoint$paths,
      chain_summary = app_joint_qvp_write_csv(
        summary, file.path(worker_dir, "chain_summary.csv")
      ),
      runtime = app_joint_qvp_write_csv(runtime, file.path(worker_dir, "runtime.csv")),
      provenance = app_joint_qvp_write_csv(
        app_joint_qvp_provenance_rows(), file.path(worker_dir, "provenance.csv")
      ),
      README = normalizePath(readme, mustWork = TRUE)
    )
    app_joint_exqdesn_write_manifest(paths, worker_dir)
    if (!app_joint_qdesn_phase180_worker_complete(worker_dir)) {
      stop("Phase180 worker manifest failed.", call. = FALSE)
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

app_joint_qdesn_phase180_health <- function(
  freeze_dir, orchestration_dir = NULL
) {
  freeze <- app_joint_qdesn_phase180_load_freeze(freeze_dir)
  complete <- vapply(
    freeze$plan$worker_output_dir,
    app_joint_qdesn_phase180_worker_complete, logical(1L)
  )
  exits <- if (!is.null(orchestration_dir)) {
    file.path(
      orchestration_dir, "exits", sprintf("worker_%04d.exit", freeze$plan$worker_id)
    )
  } else rep("", nrow(freeze$plan))
  failed <- vapply(exits, function(path) {
    if (!nzchar(path) || !file.exists(path)) return(FALSE)
    value <- suppressWarnings(as.integer(readLines(path, warn = FALSE)[[1L]]))
    is.finite(value) && value != 0L
  }, logical(1L))
  state <- ifelse(complete, "complete", ifelse(failed, "failed", "remaining"))
  plan <- freeze$plan; plan$state <- state
  by_case <- app_joint_qdesn_bind_rows(lapply(split(plan, plan$mcmc_case_id), function(x) {
    data.frame(
      mcmc_case_id = x$mcmc_case_id[[1L]], case_id = x$case_id[[1L]],
      scenario_id = x$scenario_id[[1L]], source_model_id = x$source_model_id[[1L]],
      planned = nrow(x), complete = sum(x$state == "complete"),
      failed = sum(x$state == "failed"), remaining = sum(x$state == "remaining"),
      stringsAsFactors = FALSE
    )
  }))
  list(
    summary = data.frame(
      stage = "phase180_balanced_posterior_completion",
      planned = nrow(plan), complete = sum(complete),
      failed = sum(failed & !complete), remaining = sum(!complete & !failed),
      percent_complete = 100 * mean(complete), stringsAsFactors = FALSE
    ),
    by_case = by_case, plan = plan
  )
}

app_joint_qdesn_phase180_final_source_plan <- function(freeze) {
  contract <- freeze$contract
  reuse_cells <- freeze$registry[
    freeze$registry$source_action == "reuse_phase172_verified_draws", , drop = FALSE
  ]
  phase171_dir <- app_joint_qdesn_phase180_dirs(
    freeze$config$cache_root[[1L]]
  )$phase171
  phase171 <- app_read_csv(file.path(phase171_dir, "chain_plan.csv"))
  reuse <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(reuse_cells)), function(ii) {
    cell <- reuse_cells[ii, , drop = FALSE]
    block <- phase171[
      phase171$scenario_id == cell$scenario_id[[1L]] &
        phase171$fit_structure == cell$fit_structure[[1L]], , drop = FALSE
    ]
    if (nrow(block) != contract$n_chains ||
        !identical(sort(as.integer(block$chain_id)), seq_len(contract$n_chains))) {
      stop("Phase180 could not resolve eight retained Phase172 chains.", call. = FALSE)
    }
    block$case_id <- cell$case_id[[1L]]
    block$mcmc_case_id <- cell$mcmc_case_id[[1L]]
    block$scenario_ids <- cell$scenario_id[[1L]]
    block$base_scenario_id <- cell$base_scenario_id[[1L]]
    block$source_model_id <- cell$source_model_id[[1L]]
    block$likelihood_family <- "exAL"
    block$model_id <- cell$model_id[[1L]]
    block$display_label <- cell$display_label[[1L]]
    block$phase178_template_id <- cell$phase178_template_id[[1L]]
    block$variant_id <- "exAL"
    block$candidate_role <- "phase172_retained_final_control"
    block$design_role <- "frozen_base_fixture"
    block$design_class <- "frozen_base_fixture"
    block$dgp_replicate_id <- "article_fixture"
    block$validation_partition <- "article_evaluation"
    block$n_chains <- contract$n_chains
    block$source_kind <- "phase172_reuse"
    block$source_worker_id <- block$worker_id
    block
  }))
  rerun <- freeze$plan
  rerun$source_kind <- "phase180_rerun"
  rerun$source_worker_id <- rerun$worker_id
  fields <- union(names(reuse), names(rerun))
  add_missing <- function(x) {
    for (name in setdiff(fields, names(x))) x[[name]] <- NA
    x[, fields, drop = FALSE]
  }
  out <- rbind(add_missing(reuse), add_missing(rerun))
  out <- out[order(
    match(out$case_id, freeze$registry$case_id), as.integer(out$chain_id)
  ), , drop = FALSE]
  out$worker_id <- seq_len(nrow(out))
  complete <- vapply(seq_len(nrow(out)), function(ii) {
    if (out$source_kind[[ii]] == "phase172_reuse") {
      app_joint_exqdesn_phase172_worker_complete(out$worker_output_dir[[ii]])
    } else app_joint_qdesn_phase180_worker_complete(out$worker_output_dir[[ii]])
  }, logical(1L))
  out$worker_manifest_verified <- complete
  out$worker_manifest_sha256 <- vapply(out$worker_output_dir, function(path) {
    manifest <- file.path(path, "artifact_manifest.csv")
    if (file.exists(manifest)) app_sha256_file(manifest) else NA_character_
  }, character(1L))
  if (nrow(out) != contract$expected_final_cells * contract$n_chains ||
      length(unique(out$case_id)) != contract$expected_final_cells ||
      any(table(out$case_id) != contract$n_chains) || any(!complete) ||
      anyDuplicated(paste(out$case_id, out$chain_id))) {
    stop("Phase180 final source plan is incomplete or unverifiable.", call. = FALSE)
  }
  out
}

app_joint_qdesn_phase180_score_fixture_loader <- function(jobs, freeze) {
  app_joint_qdesn_phase180_load_fixture(
    jobs$scenario_id[[1L]], freeze$config$fixture_dir[[1L]]
  )
}

app_joint_qdesn_phase180_score_fit_loader <- function(jobs, fixture, freeze) {
  jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
  lapply(seq_len(nrow(jobs)), function(ii) {
    job <- jobs[ii, , drop = FALSE]
    if (job$source_kind[[1L]] == "phase172_reuse") {
      return(app_joint_exqdesn_phase157_read_fit(
        app_joint_exqdesn_phase172_checkpoint_dir(job$worker_output_dir[[1L]]),
        fixture$tau, job$chain_seed[[1L]], job$chain_id[[1L]]
      ))
    }
    app_joint_qdesn_phase180_read_fit(
      job$worker_output_dir[[1L]], fixture$tau,
      job$chain_seed[[1L]], job$chain_id[[1L]]
    )
  })
}

app_joint_qdesn_phase180_score_cell <- function(
  jobs, freeze, contract, work_dir
) {
  path <- app_joint_qdesn_postscore_cell_dir(work_dir, jobs$mcmc_case_id[[1L]])
  if (app_joint_qdesn_postscore_cell_complete(path)) return(normalizePath(path))
  result <- app_joint_qdesn_postscore_case(
    jobs, freeze, contract,
    fixture_loader = app_joint_qdesn_phase180_score_fixture_loader,
    fit_loader = app_joint_qdesn_phase180_score_fit_loader
  )
  app_joint_qdesn_postscore_write_cell(result, path)
  normalizePath(path)
}

app_joint_qdesn_phase180_run_score_cells <- function(
  groups, freeze, contract, work_dir, cores = 8L
) {
  run <- function(index) try(
    app_joint_qdesn_phase180_score_cell(
      groups[[index]], freeze, contract, work_dir
    ), silent = TRUE
  )
  result <- if (.Platform$OS.type != "windows" && cores > 1L) {
    parallel::mclapply(
      seq_along(groups), run, mc.cores = min(as.integer(cores), length(groups)),
      mc.preschedule = FALSE
    )
  } else lapply(seq_along(groups), run)
  failed <- vapply(result, inherits, logical(1L), "try-error")
  if (any(failed)) {
    stop(sprintf(
      "Phase180 score reconstruction failed: %s",
      paste(vapply(result[failed], as.character, character(1L)), collapse = " | ")
    ), call. = FALSE)
  }
  paths <- unlist(result, use.names = FALSE)
  names(paths) <- names(groups)
  paths
}

app_joint_qdesn_phase180_parameter_diagnostics <- function(fits, jobs) {
  blocks <- c("alpha", "sigma")
  if (all(vapply(fits, function(x) !is.null(x$gamma_draws), logical(1L)))) {
    blocks <- c(blocks, "gamma")
  }
  app_joint_qdesn_bind_rows(lapply(blocks, function(block) {
    matrices <- lapply(fits, `[[`, paste0(block, "_draws"))
    K <- ncol(matrices[[1L]])
    app_joint_qdesn_bind_rows(lapply(seq_len(K), function(k) {
      matrix_draw <- do.call(cbind, lapply(matrices, function(x) x[, k]))
      diagnostics <- app_joint_exqdesn_modern_diagnostics(matrix_draw)
      data.frame(
        case_id = jobs$case_id[[1L]], scenario_id = jobs$scenario_id[[1L]],
        source_model_id = jobs$source_model_id[[1L]],
        likelihood_family = jobs$likelihood_family[[1L]],
        fit_structure = jobs$fit_structure[[1L]], parameter = block,
        quantile_index = k, rank_rhat = diagnostics$rank_rhat,
        folded_rhat = diagnostics$folded_rhat,
        bulk_ess = diagnostics$bulk_ess, tail_ess = diagnostics$tail_ess,
        mcse_mean = diagnostics$mcse_mean, stringsAsFactors = FALSE
      )
    }))
  }))
}

app_joint_qdesn_phase180_case_supplement <- function(jobs, freeze) {
  loaded <- app_joint_qdesn_phase180_score_fixture_loader(jobs, freeze)
  fixture <- loaded$fixture
  context <- app_joint_qdesn_postscore_forecast_context(loaded, fixture)
  fits <- app_joint_qdesn_phase180_score_fit_loader(jobs, fixture, freeze)
  pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(
    fits, fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau
  )
  fit_raw <- app_joint_qdesn_predict_fit(pooled, fixture$Z, fixture$tau)
  forecast_raw <- app_joint_qdesn_predict_fit(
    pooled, context$forecast$Z, fixture$tau
  )
  fit_contract <- app_joint_qdesn_apply_monotone_contract(fit_raw, fixture$tau)
  forecast_contract <- app_joint_qdesn_apply_monotone_contract(
    forecast_raw, fixture$tau
  )
  metrics <- function(qhat, truth, contract, window) {
    error <- as.numeric(qhat - truth)
    data.frame(
      case_id = jobs$case_id[[1L]], scenario_id = jobs$scenario_id[[1L]],
      source_model_id = jobs$source_model_id[[1L]],
      likelihood_family = jobs$likelihood_family[[1L]],
      fit_structure = jobs$fit_structure[[1L]], window = window,
      oracle_quantile_mae = mean(abs(error)),
      oracle_quantile_rmse = sqrt(mean(error^2)),
      oracle_quantile_bias = mean(error),
      raw_crossing_pairs = sum(contract$raw_crossing$n_crossing_pairs),
      contract_crossing_pairs = sum(contract$contract_crossing$n_crossing_pairs),
      mean_abs_monotone_adjustment = contract$mean_abs_adjustment,
      max_abs_monotone_adjustment = contract$max_abs_adjustment,
      stringsAsFactors = FALSE
    )
  }
  list(
    oracle = app_joint_qdesn_bind_rows(list(
      metrics(
        fit_contract$qhat_contract, fixture$true_q, fit_contract, "fit"
      ),
      metrics(
        forecast_contract$qhat_contract, context$forecast$true_q,
        forecast_contract, "forecast"
      )
    )),
    parameters = app_joint_qdesn_phase180_parameter_diagnostics(fits, jobs)
  )
}

app_joint_qdesn_phase180_collect_runtime <- function(plan) {
  app_joint_qdesn_bind_rows(lapply(seq_len(nrow(plan)), function(ii) {
    path <- file.path(plan$worker_output_dir[[ii]], "runtime.csv")
    row <- app_read_csv(path)
    row$source_kind <- plan$source_kind[[ii]]
    row$source_model_id <- plan$source_model_id[[ii]]
    row$likelihood_family <- plan$likelihood_family[[ii]]
    row
  }))
}

app_joint_qdesn_phase180_finalize <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  freeze_dir = NULL, out_dir = NULL, score_cores = 8L, force = FALSE
) {
  dirs <- app_joint_qdesn_phase180_dirs(cache_root)
  freeze_dir <- freeze_dir %||% dirs$freeze
  out_dir <- out_dir %||% dirs$packet
  freeze <- app_joint_qdesn_phase180_load_freeze(freeze_dir)
  health <- app_joint_qdesn_phase180_health(freeze_dir, dirs$orchestration)
  if (health$summary$failed[[1L]] > 0L || health$summary$remaining[[1L]] > 0L) {
    stop("Phase180 cannot finalize before all 168 new workers pass.", call. = FALSE)
  }
  if (!force && file.exists(file.path(out_dir, "artifact_manifest.csv"))) {
    check <- tryCatch(
      app_joint_exqdesn_verify_manifest(out_dir, "phase180_packet"),
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
  plan <- app_joint_qdesn_phase180_final_source_plan(freeze)
  groups <- split(plan, factor(plan$case_id, levels = freeze$registry$case_id))
  if (length(groups) != freeze$contract$expected_final_cells) {
    stop("Phase180 final source grouping is incomplete.", call. = FALSE)
  }
  cell_paths <- app_joint_qdesn_phase180_run_score_cells(
    groups, freeze, freeze$contract, dirs$score_work, as.integer(score_cores)
  )
  score <- app_joint_qdesn_postscore_collect_cells(cell_paths)
  if (nrow(score$diagnostics) != freeze$contract$expected_final_cells ||
      any(score$diagnostics$contract_crossing_pairs != 0L) ||
      any(score$previsibility$status != "pass") ||
      any(score$source$worker_manifest_status != "pass")) {
    stop("Phase180 score cells failed source or implementation gates.", call. = FALSE)
  }
  formula <- app_joint_qdesn_postscore_formula_audit(freeze$contract)
  oracle_minimum <- app_joint_qdesn_postscore_oracle_minimum_audit(freeze$contract)
  if (any(formula$analytic_status != "pass") ||
      any(formula$monte_carlo_status != "pass") ||
      any(oracle_minimum$status != "pass")) {
    stop("Phase180 DGP-score formula audit failed.", call. = FALSE)
  }
  pairing <- app_joint_qdesn_postscore_pairing_stability(
    score$pairing_sensitivity, freeze$contract
  )
  score_summary <- merge(
    score$diagnostics, score$canonical,
    by = c(
      "mcmc_case_id", "phase178_template_id", "case_id", "scenario_id",
      "base_scenario_id", "dgp_replicate_id", "validation_partition",
      "fit_structure", "variant_id", "candidate_role", "design_role",
      "distribution_family", "dynamics_class"
    ), all = FALSE, sort = FALSE
  )
  score_summary <- score_summary[match(freeze$registry$case_id, score_summary$case_id), , drop = FALSE]
  if (anyNA(score_summary$case_id)) stop("Phase180 score summary lost a final cell.", call. = FALSE)
  score_summary <- merge(
    score_summary,
    freeze$registry[, c(
      "case_id", "source_model_id", "model_id", "display_label",
      "likelihood_family", "source_action", "source_phase"
    ), drop = FALSE],
    by = "case_id", all.x = TRUE, sort = FALSE
  )
  contrast <- app_joint_qdesn_postscore_joint_independent_contrasts(
    score$draws, freeze$contract
  )
  if (nrow(contrast$summary) != 16L) {
    stop("Phase180 must produce 16 within-likelihood joint/independent contrasts.",
         call. = FALSE)
  }
  supplements <- if (.Platform$OS.type != "windows" && score_cores > 1L) {
    parallel::mclapply(
      groups, app_joint_qdesn_phase180_case_supplement, freeze = freeze,
      mc.cores = min(as.integer(score_cores), length(groups)), mc.preschedule = FALSE
    )
  } else lapply(groups, app_joint_qdesn_phase180_case_supplement, freeze = freeze)
  oracle <- app_joint_qdesn_bind_rows(lapply(supplements, `[[`, "oracle"))
  parameters <- app_joint_qdesn_bind_rows(lapply(supplements, `[[`, "parameters"))
  runtime <- app_joint_qdesn_phase180_collect_runtime(plan)
  compatibility <- score_summary[, c(
    "case_id", "scenario_id", "source_model_id", "likelihood_family",
    "posterior_realized_acrps_mean", "canonical_action_realized_acrps",
    "posterior_score_mean", "canonical_action_dgp_integrated_acrps"
  ), drop = FALSE]
  phase174 <- app_read_csv(file.path(dirs$phase174, "final_mcmc_case_summary.csv"))
  compatibility <- merge(
    compatibility,
    phase174[, c("scenario_id", "source_model_id", "mcmc_forecast_crps_grid")],
    by = c("scenario_id", "source_model_id"), all.x = TRUE, sort = FALSE
  )
  compatibility$canonical_realized_minus_phase174 <-
    compatibility$canonical_action_realized_acrps -
    compatibility$mcmc_forecast_crps_grid
  compatibility$comparison_role <-
    "secondary_realized_score_compatibility_not_primary_ranking"
  crossing <- merge(
    oracle[, c(
      "case_id", "window", "raw_crossing_pairs", "contract_crossing_pairs",
      "mean_abs_monotone_adjustment", "max_abs_monotone_adjustment"
    ), drop = FALSE],
    score_summary[, c(
      "case_id", "raw_crossing_rate", "coherence_status"
    ), drop = FALSE], by = "case_id", all.x = TRUE, sort = FALSE
  )
  inventory <- data.frame(
    case_id = names(cell_paths), cell_dir = normalizePath(cell_paths),
    manifest_sha256 = vapply(cell_paths, function(path) {
      app_sha256_file(file.path(path, "artifact_manifest.csv"))
    }, character(1L)), status = "pass", stringsAsFactors = FALSE
  )
  hard_fail <- any(score_summary$contract_crossing_pairs != 0L) ||
    any(!is.finite(score_summary$posterior_score_mean)) ||
    any(!is.finite(score_summary$canonical_action_dgp_integrated_acrps)) ||
    any(!plan$worker_manifest_verified)
  functional_review <- any(score_summary$score_functional_status != "pass") ||
    any(pairing$pairing_status == "review")
  coherence_review <- any(score_summary$coherence_status == "review")
  gate <- if (hard_fail) "fail" else if (functional_review || coherence_review) {
    "review"
  } else "pass"
  assessment <- data.frame(
    phase_id = freeze$contract$version, gate_status = gate,
    implementation_hard_gates = if (hard_fail) "fail" else "pass",
    final_cells = nrow(score_summary), phase172_reuse_cells = sum(
      freeze$registry$source_action == "reuse_phase172_verified_draws"
    ),
    rerun_cells = sum(
      freeze$registry$source_action != "reuse_phase172_verified_draws"
    ),
    new_workers_complete = health$summary$complete[[1L]],
    new_workers_failed = health$summary$failed[[1L]],
    score_functional_pass = sum(score_summary$score_functional_status == "pass"),
    score_functional_review = sum(score_summary$score_functional_status != "pass"),
    coherence_review = sum(score_summary$coherence_status == "review"),
    contract_crossing_pairs = sum(score_summary$contract_crossing_pairs),
    joint_independent_contrasts = nrow(contrast$summary),
    case_specific_controls_preserved = TRUE,
    article_fixture_used_for_selection = FALSE,
    article_assets_modified = FALSE,
    recommendation = if (hard_fail) {
      "repair_hard_packet_failure"
    } else if (functional_review) {
      "same_specification_chain_extension_before_article_promotion"
    } else "stage_phase180_article_assets",
    stringsAsFactors = FALSE
  )

  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase180 balanced DGP-integrated score packet", "",
    "This packet contains all 32 article scenario-model cells under frozen controls.",
    "The primary metric is the known-DGP expected finite-grid quantile score.",
    "Posterior mean, median, equal-tailed 95% interval, and canonical action are retained.",
    "Realized aCRPS and oracle quantile MAE/RMSE remain supporting diagnostics.",
    "No scalar posterior predictive density is claimed for the joint composite likelihood.",
    "Raw crossings remain visible; reported contract quantile grids must be noncrossing."
  ), readme, useBytes = TRUE)
  paths <- c(
    final_source_registry = write(plan, "final_source_registry.csv"),
    source_manifest_verification = write(
      freeze$verification, "source_manifest_verification.csv"
    ),
    worker_health_summary = write(health$summary, "worker_health_summary.csv"),
    worker_health_by_case = write(health$by_case, "worker_health_by_case.csv"),
    score_contract = write(freeze$contract$table, "phase180_score_contract.csv"),
    dgp_family_parameterization_audit = write(
      formula, "dgp_family_parameterization_audit.csv"
    ),
    oracle_minimum_audit = write(oracle_minimum, "oracle_minimum_audit.csv"),
    forecast_previsibility_audit = write(
      score$previsibility, "forecast_previsibility_audit.csv"
    ),
    posterior_dgp_integrated_acrps_draws = app_joint_qdesn_postscore_write_gzip_csv(
      score$draws, file.path(tmp, "posterior_dgp_integrated_acrps_draws.csv.gz")
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
    joint_independent_score_contrast_draws = app_joint_qdesn_postscore_write_gzip_csv(
      contrast$draws, file.path(tmp, "joint_independent_score_contrast_draws.csv.gz")
    ),
    joint_independent_score_contrast_summary = write(
      contrast$summary, "joint_independent_score_contrast_summary.csv"
    ),
    realized_expected_score_comparison = write(
      compatibility, "realized_expected_score_comparison.csv"
    ),
    oracle_recovery_diagnostics = write(
      oracle, "oracle_recovery_diagnostics.csv"
    ),
    raw_contract_crossing_summary = write(
      crossing, "raw_contract_crossing_summary.csv"
    ),
    monotone_adjustment_summary = write(
      crossing[, c(
        "case_id", "window", "mean_abs_monotone_adjustment",
        "max_abs_monotone_adjustment", "coherence_status"
      ), drop = FALSE], "monotone_adjustment_summary.csv"
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
    parameter_block_diagnostics = write(
      parameters, "parameter_block_diagnostics.csv"
    ),
    runtime_summary = write(runtime, "runtime_summary.csv"),
    score_cell_inventory = write(inventory, "score_cell_inventory.csv"),
    final_gate_assessment = write(assessment, "final_gate_assessment.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine prior Phase180 packet.", call. = FALSE)
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish Phase180 packet.", call. = FALSE)
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase180_packet")
  if (any(check$status != "pass")) stop("Phase180 packet manifest failed.", call. = FALSE)
  list(out_dir = final_dir, assessment = assessment, reused = FALSE)
}

app_joint_qdesn_phase180_article_table_lines <- function(table) {
  scenarios <- unique(table$scenario_id)
  models <- c(
    "joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb",
    "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"
  )
  header <- c(
    "% Phase180 article-facing table staged from a hash-verified score packet.",
    "\\begin{table}[!htbp]", "\\centering", "\\scriptsize",
    "\\resizebox{\\textwidth}{!}{%",
    "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.23\\textwidth}rrrr@{}}",
    "\\toprule",
    paste0(
      "Scenario & \\shortstack{Joint QDESN\\\\AL--RHS} & ",
      "\\shortstack{Independent QDESN\\\\AL--RHS} & ",
      "\\shortstack{Joint exQDESN\\\\exAL--RHS} & ",
      "\\shortstack{Independent exQDESN\\\\exAL--RHS} \\\\"
    ),
    "\\midrule"
  )
  body <- vapply(scenarios, function(scenario_id) {
    block <- table[table$scenario_id == scenario_id, , drop = FALSE]
    block <- block[match(models, block$source_model_id), , drop = FALSE]
    if (anyNA(block$source_model_id)) stop("Phase180 article table lost a model cell.", call. = FALSE)
    entries <- sprintf(
      "%.4f [%.4f, %.4f]",
      block$posterior_score_mean, block$posterior_score_q025,
      block$posterior_score_q975
    )
    entries[block$numerical_winner] <- paste0("\\textbf{", entries[block$numerical_winner], "}")
    label <- block$scenario_label[[1L]]
    paste0(paste(c(label, entries), collapse = " & "), " \\\\")
  }, character(1L))
  footer <- c(
    "\\bottomrule", "\\end{tabular}", "}%",
    paste0(
      "\\caption{Balanced MCMC comparison under the current seven-level quantile grid. ",
      "Entries are posterior means of the DGP-integrated finite-grid quantile score ",
      "with equal-tailed 95\\% credible intervals. Lower values are better, and ",
      "boldface marks the numerical minimum within each scenario. The score evaluates ",
      "the reported quantile action under the known synthetic DGP; it is not a scalar ",
      "posterior predictive-density score. Numerical winners remain descriptive when ",
      "their posterior contrasts do not establish practical separation.}"
    ),
    "\\label{tab:joint-qdesn-phase180-dgp-integrated-score}",
    "\\end{table}"
  )
  c(header, body, footer)
}

app_joint_qdesn_phase180_stage_article_assets <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  packet_dir = NULL, out_dir = NULL, force = FALSE
) {
  dirs <- app_joint_qdesn_phase180_dirs(cache_root)
  packet_dir <- packet_dir %||% dirs$packet
  out_dir <- out_dir %||% dirs$article_staging
  packet_check <- app_joint_exqdesn_verify_manifest(packet_dir, "phase180_packet")
  if (any(packet_check$status != "pass")) stop("Phase180 packet manifest failed.", call. = FALSE)
  assessment <- app_read_csv(file.path(packet_dir, "final_gate_assessment.csv"))
  if (assessment$implementation_hard_gates[[1L]] != "pass" ||
      assessment$score_functional_review[[1L]] != 0L ||
      assessment$contract_crossing_pairs[[1L]] != 0L) {
    stop("Phase180 article staging requires clean implementation and score-functional gates.",
         call. = FALSE)
  }
  if (!force && file.exists(file.path(out_dir, "artifact_manifest.csv"))) {
    check <- tryCatch(
      app_joint_exqdesn_verify_manifest(out_dir, "phase180_article_staging"),
      error = function(e) NULL
    )
    if (!is.null(check) && all(check$status == "pass")) {
      return(list(out_dir = normalizePath(out_dir), reused = TRUE))
    }
  }
  score <- app_read_csv(file.path(
    packet_dir, "posterior_dgp_integrated_acrps_summary.csv"
  ))
  oracle <- app_read_csv(file.path(packet_dir, "oracle_recovery_diagnostics.csv"))
  contrast <- app_read_csv(file.path(
    packet_dir, "joint_independent_score_contrast_summary.csv"
  ))
  crossing <- app_read_csv(file.path(
    packet_dir, "raw_contract_crossing_summary.csv"
  ))
  phase174 <- app_read_csv(file.path(dirs$phase174, "final_mcmc_case_summary.csv"))
  labels <- unique(phase174[, c(
    "scenario_id", "scenario_label", "mechanism_detail", "scenario_order"
  ), drop = FALSE])
  table <- merge(score, labels, by = "scenario_id", all.x = TRUE, sort = FALSE)
  table <- table[order(table$scenario_order, table$source_model_id), , drop = FALSE]
  table$numerical_winner <- ave(
    table$posterior_score_mean, table$scenario_id,
    FUN = function(x) x == min(x)
  ) > 0
  table$headline_metric <- "DGP-integrated finite-grid quantile score"
  table$winner_interpretation <- "descriptive_numerical_minimum"
  table$scalar_predictive_density_claim <- FALSE
  if (nrow(table) != 32L || sum(table$numerical_winner) < 8L ||
      any(!is.finite(unlist(table[, c(
        "posterior_score_mean", "posterior_score_q025", "posterior_score_q975",
        "canonical_action_dgp_integrated_acrps"
      ), drop = FALSE])))) {
    stop("Phase180 article table data failed its 32-row finite gate.", call. = FALSE)
  }
  winner <- table[table$numerical_winner, c(
    "scenario_id", "scenario_label", "source_model_id", "display_label",
    "posterior_score_mean", "posterior_score_q025", "posterior_score_q975",
    "canonical_action_dgp_integrated_acrps", "winner_interpretation"
  ), drop = FALSE]
  oracle_forecast <- oracle[oracle$window == "forecast", , drop = FALSE]
  supplemental <- merge(
    table[, c(
      "case_id", "scenario_id", "source_model_id", "display_label",
      "posterior_realized_acrps_mean", "canonical_action_realized_acrps"
    ), drop = FALSE],
    oracle_forecast[, c(
      "case_id", "oracle_quantile_mae", "oracle_quantile_rmse",
      "raw_crossing_pairs", "contract_crossing_pairs"
    ), drop = FALSE], by = "case_id", all.x = TRUE, sort = FALSE
  )
  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  tex <- file.path(tmp, "joint_qdesn_phase180_dgp_integrated_score_table.tex")
  writeLines(app_joint_qdesn_phase180_article_table_lines(table), tex, useBytes = TRUE)
  guidance <- data.frame(
    topic = c(
      "headline_metric", "posterior_summary", "realized_score", "oracle_recovery",
      "crossings", "predictive_contract", "winner_language"
    ),
    required_wording = c(
      "DGP-integrated finite-grid quantile score is the main forecast comparison.",
      "Report posterior mean and equal-tailed 95% credible interval; retain median and canonical action in provenance.",
      "Realized aCRPS is secondary sample-dependent compatibility evidence.",
      "Fit and forecast MAE/RMSE compare the issued paths with known oracle quantiles.",
      "Raw crossings diagnose pre-contract coherence; reported contract crossings must be zero.",
      "The joint composite likelihood is a working likelihood for quantile paths and is not asserted to be a scalar predictive density.",
      "Numerical minima are descriptive when posterior contrasts do not establish practical separation."
    ), stringsAsFactors = FALSE
  )
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase180 article-safe staging", "",
    "This directory is a staging packet only; it does not edit the manuscript.",
    "The main table contains 32 finite scenario-model cells and is bolded by posterior mean DGP-integrated score.",
    "Oracle recovery, realized aCRPS, and crossing diagnostics remain supplemental.",
    "An integration coordinator must review and project these files into the article repository."
  ), readme, useBytes = TRUE)
  paths <- c(
    source_packet_manifest_verification = write(
      packet_check, "source_packet_manifest_verification.csv"
    ),
    article_scenario_model_summary = write(
      table, "joint_qdesn_phase180_article_scenario_model_summary.csv"
    ),
    numerical_winner_summary = write(
      winner, "joint_qdesn_phase180_numerical_winner_summary.csv"
    ),
    joint_independent_contrast_summary = write(
      contrast, "joint_qdesn_phase180_joint_independent_contrast_summary.csv"
    ),
    supplemental_oracle_realized_summary = write(
      supplemental, "joint_qdesn_phase180_supplemental_oracle_realized_summary.csv"
    ),
    crossing_provenance = write(
      crossing, "joint_qdesn_phase180_crossing_provenance.csv"
    ),
    manuscript_wording_guidance = write(
      guidance, "joint_qdesn_phase180_manuscript_wording_guidance.csv"
    ),
    article_table = normalizePath(tex, mustWork = TRUE),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine prior Phase180 staging.", call. = FALSE)
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish Phase180 article staging.", call. = FALSE)
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase180_article_staging")
  if (any(check$status != "pass")) stop("Phase180 article staging manifest failed.", call. = FALSE)
  list(out_dir = final_dir, table = table, reused = FALSE)
}

app_joint_qdesn_phase180_git_output <- function(args) {
  out <- tryCatch(
    system2("git", args, stdout = TRUE, stderr = TRUE),
    error = function(e) character()
  )
  if (!length(out)) NA_character_ else paste(out, collapse = "\n")
}

app_joint_qdesn_phase180_freeze_handoff <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(), out_dir = NULL,
  force = FALSE
) {
  dirs <- app_joint_qdesn_phase180_dirs(cache_root)
  out_dir <- out_dir %||% dirs$handoff
  packet_check <- app_joint_exqdesn_verify_manifest(dirs$packet, "phase180_packet")
  stage_check <- app_joint_exqdesn_verify_manifest(
    dirs$article_staging, "phase180_article_staging"
  )
  if (any(packet_check$status != "pass") || any(stage_check$status != "pass")) {
    stop("Phase180 handoff sources failed manifest verification.", call. = FALSE)
  }
  assessment <- app_read_csv(file.path(dirs$packet, "final_gate_assessment.csv"))
  article <- app_read_csv(file.path(
    dirs$article_staging, "joint_qdesn_phase180_article_scenario_model_summary.csv"
  ))
  readiness <- data.frame(
    lane = "JOINT", status = "READY_FOR_INTEGRATION",
    branch = app_joint_qdesn_phase180_git_output(c("branch", "--show-current")),
    upstream = app_joint_qdesn_phase180_git_output(c(
      "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"
    )),
    head = app_joint_qdesn_phase180_git_output(c("rev-parse", "HEAD")),
    origin_main = app_joint_qdesn_phase180_git_output(c("rev-parse", "origin/main")),
    worktree_status = app_joint_qdesn_phase180_git_output(c("status", "--short")),
    final_cells = nrow(article), packet_gate = assessment$gate_status[[1L]],
    implementation_hard_gates = assessment$implementation_hard_gates[[1L]],
    contract_crossing_pairs = assessment$contract_crossing_pairs[[1L]],
    article_files_are_staged_not_published = TRUE,
    overleaf_modified = FALSE, stringsAsFactors = FALSE
  )
  if (nrow(article) != 32L || readiness$implementation_hard_gates != "pass" ||
      readiness$contract_crossing_pairs != 0L) {
    stop("Phase180 integration handoff is not ready.", call. = FALSE)
  }
  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  exclusions <- data.frame(
    path = c(dirs$chains, dirs$orchestration, dirs$score_work),
    role = c("posterior_chain_runtime", "launch_runtime", "score_cell_runtime"),
    integration_action = "keep_gitignored_do_not_project_to_article",
    stringsAsFactors = FALSE
  )
  article_files <- data.frame(
    path = normalizePath(list.files(
      dirs$article_staging, full.names = TRUE, recursive = FALSE
    )),
    sha256 = vapply(list.files(
      dirs$article_staging, full.names = TRUE, recursive = FALSE
    ), app_sha256_file, character(1L)),
    integration_action = "review_then_project_article_safe_subset",
    stringsAsFactors = FALSE
  )
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase180 frozen integration handoff", "",
    "Status: READY_FOR_INTEGRATION", "",
    "The balanced 32-cell DGP-integrated score packet and article-safe staging manifest verify.",
    "This JOINT branch must be merged by the integration coordinator; this lane does not merge main or publish Overleaf.",
    "Runtime chain/checkpoint directories remain ignored and must not be projected into the article repository."
  ), readme, useBytes = TRUE)
  paths <- c(
    readiness = write(readiness, "integration_readiness.csv"),
    packet_manifest_verification = write(
      packet_check, "packet_manifest_verification.csv"
    ),
    article_staging_manifest_verification = write(
      stage_check, "article_staging_manifest_verification.csv"
    ),
    article_file_inventory = write(article_files, "article_file_inventory.csv"),
    runtime_exclusions = write(exclusions, "runtime_exclusions.csv"),
    final_gate_assessment = write(assessment, "final_gate_assessment.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine prior Phase180 handoff.", call. = FALSE)
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish Phase180 handoff.", call. = FALSE)
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase180_handoff")
  if (any(check$status != "pass")) stop("Phase180 handoff manifest failed.", call. = FALSE)
  list(out_dir = final_dir, readiness = readiness)
}
