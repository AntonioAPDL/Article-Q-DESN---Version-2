# Frozen-specification independent replication for the balanced joint QDESN grid.

app_joint_qdesn_phase153_default_readiness_dir <- function() {
  app_path("application/cache/joint_qdesn_phase153_balanced_independent_replication_readiness_20260729")
}

app_joint_qdesn_phase153_default_fixture_dir <- function() {
  app_path("application/cache/joint_qdesn_phase153_balanced_independent_replication_fixtures_20260729")
}

app_joint_qdesn_phase153_default_vb_dir <- function() {
  app_path("application/cache/joint_qdesn_phase153_balanced_independent_replication_vb_20260729")
}

app_joint_qdesn_phase153_default_orchestration_dir <- function() {
  app_path("application/cache/joint_qdesn_phase153_balanced_independent_replication_20260729_orchestration")
}

app_joint_qdesn_phase153_default_phase121_dir <- function() {
  app_path("application/cache/joint_qdesn_phase121_case_vb_winner_freeze_20260711")
}

app_joint_qdesn_phase153_default_phase124b_dir <- function() {
  app_path("application/cache/joint_qdesn_phase124b_missing_cell_vb_winner_freeze_20260711")
}

app_joint_qdesn_phase153_default_phase125_dir <- function() {
  app_path("application/cache/joint_qdesn_phase125_balanced_mcmc_audit_20260712")
}

app_joint_qdesn_phase153_default_phase150_freeze_dir <- function() {
  app_path("application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_freeze_20260727")
}

app_joint_qdesn_phase153_default_phase150_mcmc_dir <- function() {
  app_path("application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727")
}

app_joint_qdesn_phase153_default_phase152_readiness_dir <- function() {
  app_path("application/cache/joint_qdesn_phase152_independent_confirmation_readiness_20260729")
}

app_joint_qdesn_phase153_target_scenarios <- function() {
  c(
    "asymmetric_laplace_tail",
    "gaussian_mixture_bridge",
    "laplace_bridge",
    "nonlinear_reservoir_friendly",
    "normal_bridge",
    "persistent_heavy_tail",
    "regime_shift",
    "student_t_location_scale"
  )
}

app_joint_qdesn_phase153_model_order <- function() {
  c(
    "joint_qdesn_rhs_vb",
    "qdesn_rhs_independent_vb",
    "joint_exqdesn_rhs_vb",
    "exqdesn_rhs_independent_vb"
  )
}

app_joint_qdesn_phase153_control_columns <- function() {
  c(
    "case_id", "scenario_ids", "model_ids", "candidate_id",
    "vb_max_iter", "adaptive_vb_max_iter_grid", "vb_tol",
    "rhs_vb_inner", "tau0", "zeta2", "a_sigma", "b_sigma",
    "alpha_prior_sd", "alpha_min_spacing", "gamma_init_policy",
    "review_adjustment_threshold", "max_dense_dim"
  )
}

app_joint_qdesn_phase153_verify_manifest <- function(dir, source_id) {
  dir <- normalizePath(dir, mustWork = TRUE)
  manifest_path <- file.path(dir, "artifact_manifest.csv")
  if (!file.exists(manifest_path)) {
    stop(sprintf("Missing artifact manifest for '%s': %s", source_id, dir), call. = FALSE)
  }
  manifest <- app_read_csv(manifest_path)
  app_check_required_columns(
    manifest,
    c("label", "relative_path", "size_bytes", "sha256"),
    sprintf("%s artifact manifest", source_id)
  )
  rows <- lapply(seq_len(nrow(manifest)), function(ii) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    exists <- file.exists(path)
    actual_sha <- if (exists) app_sha256_file(path) else NA_character_
    actual_size <- if (exists) as.numeric(file.info(path)$size) else NA_real_
    data.frame(
      source_id = source_id,
      source_dir = app_prefer_repo_relative_path(dir),
      label = manifest$label[[ii]],
      relative_path = manifest$relative_path[[ii]],
      exists = exists,
      declared_size_bytes = as.numeric(manifest$size_bytes[[ii]]),
      actual_size_bytes = actual_size,
      declared_sha256 = manifest$sha256[[ii]],
      actual_sha256 = actual_sha,
      verified = exists &&
        identical(tolower(actual_sha), tolower(manifest$sha256[[ii]])) &&
        identical(actual_size, as.numeric(manifest$size_bytes[[ii]])),
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase153_standardize_controls <- function(
  controls,
  source_freeze_id,
  source_dir
) {
  required <- app_joint_qdesn_phase153_control_columns()
  app_check_required_columns(controls, required, sprintf("%s controls", source_freeze_id))
  out <- controls[, required, drop = FALSE]
  out$base_scenario_id <- as.character(out$scenario_ids)
  out$model_id <- as.character(out$model_ids)
  out$source_candidate_id <- as.character(out$candidate_id)
  out$source_freeze_id <- source_freeze_id
  out$source_freeze_dir <- app_prefer_repo_relative_path(source_dir)
  out$source_control_file_sha256 <- app_sha256_file(file.path(source_dir, "case_winner_controls.csv"))
  out
}

app_joint_qdesn_phase153_load_control_freeze <- function(
  phase121_dir = app_joint_qdesn_phase153_default_phase121_dir(),
  phase124b_dir = app_joint_qdesn_phase153_default_phase124b_dir(),
  phase125_dir = app_joint_qdesn_phase153_default_phase125_dir(),
  phase150_freeze_dir = app_joint_qdesn_phase153_default_phase150_freeze_dir(),
  phase150_mcmc_dir = app_joint_qdesn_phase153_default_phase150_mcmc_dir()
) {
  dirs <- list(
    phase121_case_winners = phase121_dir,
    phase124b_missing_cell_winners = phase124b_dir,
    phase125_balanced_mcmc_audit = phase125_dir,
    phase150_joint_exal_winners = phase150_freeze_dir,
    phase150_joint_exal_mcmc = phase150_mcmc_dir
  )
  source_manifest <- app_joint_qdesn_bind_rows(lapply(names(dirs), function(id) {
    app_joint_qdesn_phase153_verify_manifest(dirs[[id]], id)
  }))
  if (any(!source_manifest$verified)) {
    stop("A Phase 153 control-freeze source manifest failed verification.", call. = FALSE)
  }

  phase121 <- app_joint_qdesn_phase153_standardize_controls(
    app_read_csv(file.path(phase121_dir, "case_winner_controls.csv")),
    "phase121_case_winners",
    phase121_dir
  )
  phase124b <- app_joint_qdesn_phase153_standardize_controls(
    app_read_csv(file.path(phase124b_dir, "case_winner_controls.csv")),
    "phase124b_missing_cell_winners",
    phase124b_dir
  )
  phase150 <- app_joint_qdesn_phase153_standardize_controls(
    app_read_csv(file.path(phase150_freeze_dir, "case_winner_controls.csv")),
    "phase150_joint_exal_winners",
    phase150_freeze_dir
  )

  earlier <- rbind(phase121, phase124b)
  earlier <- earlier[earlier$model_id != "joint_exqdesn_rhs_vb", , drop = FALSE]
  phase150 <- phase150[phase150$model_id == "joint_exqdesn_rhs_vb", , drop = FALSE]
  frozen <- rbind(earlier, phase150)

  scenarios <- app_joint_qdesn_phase153_target_scenarios()
  models <- app_joint_qdesn_phase153_model_order()
  frozen <- frozen[
    frozen$base_scenario_id %in% scenarios & frozen$model_id %in% models,
    ,
    drop = FALSE
  ]
  scenario_order <- match(frozen$base_scenario_id, scenarios)
  model_order <- match(frozen$model_id, models)
  frozen <- frozen[order(scenario_order, model_order), , drop = FALSE]
  rownames(frozen) <- NULL

  cell_id <- paste(frozen$base_scenario_id, frozen$model_id, sep = "::")
  expected_cells <- as.vector(outer(scenarios, models, paste, sep = "::"))
  model_counts <- table(factor(frozen$model_id, levels = models))
  scenario_counts <- table(factor(frozen$base_scenario_id, levels = scenarios))
  hard_fail <- nrow(frozen) != 32L ||
    anyDuplicated(cell_id) ||
    !setequal(cell_id, expected_cells) ||
    any(model_counts != 8L) ||
    any(scenario_counts != 4L) ||
    sum(frozen$source_freeze_id == "phase150_joint_exal_winners") != 8L ||
    any(frozen$model_id[frozen$source_freeze_id == "phase150_joint_exal_winners"] !=
      "joint_exqdesn_rhs_vb")
  if (hard_fail) {
    stop("The Phase 153 frozen scenario-model control grid is malformed.", call. = FALSE)
  }

  audit <- data.frame(
    audit_id = "phase153_frozen_case_model_controls",
    gate_status = "pass",
    frozen_rows = nrow(frozen),
    target_scenarios = length(unique(frozen$base_scenario_id)),
    target_models = length(unique(frozen$model_id)),
    duplicate_cells = sum(duplicated(cell_id)),
    missing_cells = length(setdiff(expected_cells, cell_id)),
    phase150_joint_exal_rows = sum(frozen$source_freeze_id == "phase150_joint_exal_winners"),
    global_specification_selected = FALSE,
    article_assets_modified = FALSE,
    stringsAsFactors = FALSE
  )
  list(
    frozen = frozen,
    audit = audit,
    source_manifest = source_manifest
  )
}

app_joint_qdesn_phase153_build_dgp_registry <- function(
  base_registry,
  n_dgp_replicates = 50L,
  seed_base = 153000000L,
  excluded_seeds = integer()
) {
  n_dgp_replicates <- as.integer(n_dgp_replicates)
  seed_base <- as.integer(seed_base)
  if (!is.finite(n_dgp_replicates) || n_dgp_replicates < 1L) {
    stop("n_dgp_replicates must be a positive integer.", call. = FALSE)
  }
  scenarios <- app_joint_qdesn_phase153_target_scenarios()
  base <- base_registry[match(scenarios, base_registry$scenario_id), , drop = FALSE]
  if (any(is.na(base$scenario_id))) {
    stop("The formal registry is missing a Phase 153 target scenario.", call. = FALSE)
  }
  rows <- vector("list", length(scenarios) * n_dgp_replicates)
  at <- 0L
  for (ss in seq_along(scenarios)) {
    for (rr in seq_len(n_dgp_replicates)) {
      at <- at + 1L
      x <- base[ss, , drop = FALSE]
      x$base_scenario_id <- scenarios[[ss]]
      x$dgp_replicate_id <- sprintf("r%03d", rr)
      x$base_seed <- as.integer(base$seed[[ss]])
      x$seed <- as.integer(seed_base + ss * 1000L + rr)
      x$seed_role <- "phase153_external_confirmation_dgp"
      x$scenario_id <- paste0(
        scenarios[[ss]], "__phase153_dgp_", x$dgp_replicate_id
      )
      x$registry_version <- "joint_qdesn_phase153_balanced_independent_replication_20260729"
      x$notes <- paste(
        base$notes[[ss]],
        "Fresh Phase153 external-confirmation replicate; no prior validation outcome is reused."
      )
      rows[[at]] <- x
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  rownames(out) <- NULL
  app_joint_qdesn_validate_simulation_registry(out)
  if (anyDuplicated(out$scenario_id) || anyDuplicated(out$seed)) {
    stop("Phase 153 DGP scenario ids and seeds must be unique.", call. = FALSE)
  }
  excluded_seeds <- unique(as.integer(excluded_seeds[is.finite(excluded_seeds)]))
  if (length(intersect(out$seed, excluded_seeds))) {
    stop("A Phase 153 DGP seed collides with an excluded prior seed.", call. = FALSE)
  }
  out
}

app_joint_qdesn_phase153_seed_collision_audit <- function(
  dgp_registry,
  original_seeds,
  phase152_seeds
) {
  data.frame(
    scenario_id = dgp_registry$scenario_id,
    base_scenario_id = dgp_registry$base_scenario_id,
    dgp_replicate_id = dgp_registry$dgp_replicate_id,
    dgp_seed = as.integer(dgp_registry$seed),
    collides_original_registry = dgp_registry$seed %in% as.integer(original_seeds),
    collides_phase152 = dgp_registry$seed %in% as.integer(phase152_seeds),
    duplicated_within_phase153 = duplicated(dgp_registry$seed) |
      duplicated(dgp_registry$seed, fromLast = TRUE),
    seed_status = ifelse(
      dgp_registry$seed %in% c(as.integer(original_seeds), as.integer(phase152_seeds)) |
        duplicated(dgp_registry$seed) |
        duplicated(dgp_registry$seed, fromLast = TRUE),
      "fail",
      "pass"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase153_build_candidate_registry <- function(
  frozen_controls,
  dgp_registry
) {
  scenarios <- app_joint_qdesn_phase153_target_scenarios()
  models <- app_joint_qdesn_phase153_model_order()
  rows <- vector("list", nrow(dgp_registry) * length(models))
  at <- 0L
  for (rr in seq_len(nrow(dgp_registry))) {
    dgp <- dgp_registry[rr, , drop = FALSE]
    controls <- frozen_controls[
      frozen_controls$base_scenario_id == dgp$base_scenario_id[[1L]],
      ,
      drop = FALSE
    ]
    controls <- controls[match(models, controls$model_id), , drop = FALSE]
    if (nrow(controls) != length(models) || any(is.na(controls$model_id))) {
      stop(sprintf(
        "Phase 153 controls are incomplete for '%s'.",
        dgp$base_scenario_id[[1L]]
      ), call. = FALSE)
    }
    for (mm in seq_len(nrow(controls))) {
      at <- at + 1L
      x <- controls[mm, , drop = FALSE]
      x$scenario_ids <- dgp$scenario_id[[1L]]
      x$model_ids <- x$model_id
      x$case_id <- paste(dgp$scenario_id[[1L]], x$model_id, sep = "__")
      x$candidate_id <- paste0(
        dgp$scenario_id[[1L]], "__phase153__", x$model_id[[1L]]
      )
      x$dgp_replicate_id <- dgp$dgp_replicate_id[[1L]]
      x$dgp_seed <- as.integer(dgp$seed[[1L]])
      x$confirmation_role <- "frozen_case_model_external_confirmation"
      x$replication_tier <- "full_50_replicate_campaign"
      rows[[at]] <- x
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  rownames(out) <- NULL
  expected <- nrow(dgp_registry) * length(models)
  cells <- paste(
    out$base_scenario_id,
    out$dgp_replicate_id,
    out$model_id,
    sep = "::"
  )
  if (nrow(out) != expected || anyDuplicated(out$candidate_id) ||
      anyDuplicated(cells) ||
      !all(out$base_scenario_id %in% scenarios) ||
      !all(out$model_id %in% models)) {
    stop("The Phase 153 candidate registry is malformed.", call. = FALSE)
  }
  out
}

app_joint_qdesn_phase153_exhausted_dimension_audit <- function() {
  data.frame(
    prior_stage = c(
      "Phases128-132",
      "Phase133B",
      "Phases134-143",
      "Phases144-150",
      "Phases151-152"
    ),
    exhausted_dimension = c(
      "gamma widths, step-out, chain count, chain length, and thinning",
      "posterior mean, median, and trimmed quantile summaries",
      "matched AL controls, RHS/readout controls, gamma kernels, and gamma priors",
      "initialization, conditional refreshes, joint geometry, target invariance, and case-specific MCMC",
      "deterministic reservoir feature-map selection and independent confirmation"
    ),
    phase153_action = c(
      rep("freeze; do not rescreen", 4L),
      "close feature-map branch; use direct frozen designs"
    ),
    repeated_in_phase153 = FALSE,
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase153_comparison_contract <- function() {
  data.frame(
    contrast_id = c(
      "joint_vs_independent_al",
      "joint_vs_independent_exal",
      "joint_exal_vs_joint_al",
      "independent_exal_vs_independent_al"
    ),
    model_a = c(
      "joint_qdesn_rhs_vb",
      "joint_exqdesn_rhs_vb",
      "joint_exqdesn_rhs_vb",
      "exqdesn_rhs_independent_vb"
    ),
    model_b = c(
      "qdesn_rhs_independent_vb",
      "exqdesn_rhs_independent_vb",
      "joint_qdesn_rhs_vb",
      "qdesn_rhs_independent_vb"
    ),
    delta_definition = "model_a_minus_model_b",
    negative_delta_favors = "model_a",
    primary_metric = "forecast_truth_mae",
    practical_margin = "max(0.0025, 0.02 * median_model_b)",
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase153_all_pair_contract <- function() {
  models <- app_joint_qdesn_phase153_model_order()
  pairs <- utils::combn(models, 2L)
  data.frame(
    contrast_id = paste(pairs[1L, ], "vs", pairs[2L, ], sep = "__"),
    model_a = pairs[1L, ],
    model_b = pairs[2L, ],
    delta_definition = "model_a_minus_model_b",
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase153_fixture_is_current <- function(fixture_dir, dgp_registry) {
  if (!file.exists(file.path(fixture_dir, "artifact_manifest.csv")) ||
      !file.exists(file.path(fixture_dir, "frozen_registry.csv"))) return(FALSE)
  tryCatch({
    verification <- app_joint_qdesn_verify_artifact_manifest(fixture_dir)
    frozen <- app_read_csv(file.path(fixture_dir, "frozen_registry.csv"))
    all(verification$status == "pass") &&
      identical(as.character(frozen$scenario_id), as.character(dgp_registry$scenario_id)) &&
      identical(as.integer(frozen$seed), as.integer(dgp_registry$seed))
  }, error = function(e) FALSE)
}

app_joint_qdesn_run_phase153_readiness <- function(
  out_dir = app_joint_qdesn_phase153_default_readiness_dir(),
  fixture_dir = app_joint_qdesn_phase153_default_fixture_dir(),
  base_registry_path = app_joint_qdesn_default_simulation_registry_path(),
  phase121_dir = app_joint_qdesn_phase153_default_phase121_dir(),
  phase124b_dir = app_joint_qdesn_phase153_default_phase124b_dir(),
  phase125_dir = app_joint_qdesn_phase153_default_phase125_dir(),
  phase150_freeze_dir = app_joint_qdesn_phase153_default_phase150_freeze_dir(),
  phase150_mcmc_dir = app_joint_qdesn_phase153_default_phase150_mcmc_dir(),
  phase152_readiness_dir = app_joint_qdesn_phase153_default_phase152_readiness_dir(),
  n_dgp_replicates = 50L,
  seed_base = 153000000L,
  materialize_fixtures = TRUE
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  fixture_dir <- normalizePath(fixture_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)

  freeze <- app_joint_qdesn_phase153_load_control_freeze(
    phase121_dir = phase121_dir,
    phase124b_dir = phase124b_dir,
    phase125_dir = phase125_dir,
    phase150_freeze_dir = phase150_freeze_dir,
    phase150_mcmc_dir = phase150_mcmc_dir
  )
  phase152_manifest <- app_joint_qdesn_phase153_verify_manifest(
    phase152_readiness_dir,
    "phase152_independent_confirmation_readiness"
  )
  phase152_registry_path <- file.path(
    phase152_readiness_dir,
    "phase152_fresh_dgp_registry.csv"
  )
  if (!file.exists(phase152_registry_path)) {
    stop("Missing Phase 152 seed registry.", call. = FALSE)
  }
  phase152_registry <- app_read_csv(phase152_registry_path)
  base_registry <- app_joint_qdesn_load_simulation_registry(base_registry_path)
  excluded <- unique(c(as.integer(base_registry$seed), as.integer(phase152_registry$seed)))
  dgp_registry <- app_joint_qdesn_phase153_build_dgp_registry(
    base_registry = base_registry,
    n_dgp_replicates = n_dgp_replicates,
    seed_base = seed_base,
    excluded_seeds = excluded
  )
  seed_audit <- app_joint_qdesn_phase153_seed_collision_audit(
    dgp_registry,
    original_seeds = base_registry$seed,
    phase152_seeds = phase152_registry$seed
  )
  candidate_registry <- app_joint_qdesn_phase153_build_candidate_registry(
    freeze$frozen,
    dgp_registry
  )

  if (isTRUE(materialize_fixtures) &&
      !app_joint_qdesn_phase153_fixture_is_current(fixture_dir, dgp_registry)) {
    if (dir.exists(fixture_dir) && length(list.files(fixture_dir, all.files = TRUE)) > 2L) {
      quarantine <- paste0(
        fixture_dir,
        ".invalid.",
        format(Sys.time(), "%Y%m%d%H%M%S")
      )
      if (!file.rename(fixture_dir, quarantine)) {
        stop("Could not quarantine a stale Phase 153 fixture directory.", call. = FALSE)
      }
    }
    app_joint_qdesn_materialize_simulation_fixtures(
      out_dir = fixture_dir,
      registry_path = base_registry_path,
      registry = dgp_registry
    )
  }
  fixture_verification <- if (isTRUE(materialize_fixtures)) {
    app_joint_qdesn_verify_artifact_manifest(fixture_dir)
  } else {
    data.frame(status = "pass", stringsAsFactors = FALSE)
  }
  source_manifest <- app_joint_qdesn_bind_rows(list(
    freeze$source_manifest,
    phase152_manifest,
    if (isTRUE(materialize_fixtures)) {
      data.frame(
        source_id = "phase153_fresh_fixtures",
        source_dir = app_prefer_repo_relative_path(fixture_dir),
        label = fixture_verification$label,
        relative_path = fixture_verification$relative_path,
        exists = fixture_verification$exists,
        declared_size_bytes = fixture_verification$declared_size_bytes,
        actual_size_bytes = fixture_verification$actual_size_bytes,
        declared_sha256 = fixture_verification$declared_sha256,
        actual_sha256 = fixture_verification$actual_sha256,
        verified = fixture_verification$status == "pass",
        stringsAsFactors = FALSE
      )
    } else NULL
  ))

  geometry_ok <- all(dgp_registry$simulated_length == 12000L) &&
    all(dgp_registry$dgp_warmup_length == 2000L) &&
    all(dgp_registry$desn_washout_length == 500L) &&
    all(dgp_registry$fit_length == 500L) &&
    all(dgp_registry$validation_length == 1000L) &&
    all(dgp_registry$forecast_origin_stride == 30L) &&
    all(dgp_registry$max_lead == 30L)
  expected_fixtures <- 8L * as.integer(n_dgp_replicates)
  expected_candidates <- expected_fixtures * 4L
  hard_fail <- any(!source_manifest$verified) ||
    freeze$audit$gate_status[[1L]] != "pass" ||
    any(seed_audit$seed_status != "pass") ||
    !geometry_ok ||
    nrow(dgp_registry) != expected_fixtures ||
    nrow(candidate_registry) != expected_candidates ||
    anyDuplicated(candidate_registry$candidate_id)
  assessment <- data.frame(
    audit_id = "phase153_balanced_independent_replication_readiness",
    gate_status = if (hard_fail) "fail" else "pass",
    target_scenarios = 8L,
    target_models = 4L,
    dgp_replicates_per_scenario = as.integer(n_dgp_replicates),
    fresh_fixture_rows = nrow(dgp_registry),
    vb_jobs_expected = nrow(candidate_registry),
    source_hash_failures = sum(!source_manifest$verified),
    seed_collisions = sum(seed_audit$seed_status != "pass"),
    formal_geometry_verified = geometry_ok,
    per_case_controls = TRUE,
    global_specification_selected = FALSE,
    mcmc_launched = FALSE,
    article_assets_modified = FALSE,
    recommendation = if (hard_fail) {
      "fix_phase153_readiness_before_launch"
    } else {
      "launch_full_frozen_specification_replication"
    },
    stringsAsFactors = FALSE
  )

  replication_design <- data.frame(
    design_id = "phase153_full_balanced_independent_replication",
    scenarios = 8L,
    models = 4L,
    dgp_replicates_per_scenario = as.integer(n_dgp_replicates),
    fixtures = nrow(dgp_registry),
    candidate_fits = nrow(candidate_registry),
    fit_once_score_fit_and_forecast = TRUE,
    forecast_refit_policy = "single_fit_no_refit_across_validation_blocks",
    original_realization_excluded = TRUE,
    phase152_seeds_excluded = TRUE,
    validation_outcome_retuning = FALSE,
    stringsAsFactors = FALSE
  )
  run_config <- data.frame(
    run_id = "joint_qdesn_phase153_balanced_independent_replication",
    repository_head = tryCatch(
      system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)[[1L]],
      error = function(e) NA_character_
    ),
    base_registry_path = app_prefer_repo_relative_path(base_registry_path),
    base_registry_sha256 = app_sha256_file(base_registry_path),
    fixture_dir = app_prefer_repo_relative_path(fixture_dir),
    n_dgp_replicates = as.integer(n_dgp_replicates),
    seed_base = as.integer(seed_base),
    bootstrap_seed_base = 153900000L,
    bootstrap_replicates = 2000L,
    planned_workers = 20L,
    article_assets_modified = FALSE,
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Joint QDESN Phase 153 Balanced Independent Replication",
    "",
    "This readiness packet freezes one scenario-specific specification for each",
    "of the 32 balanced model-mechanism cells before evaluating fifty new DGP",
    "replicates per mechanism. It is a confirmation campaign, not a new screen.",
    "",
    sprintf("- Gate: `%s`", assessment$gate_status[[1L]]),
    sprintf("- Fresh fixtures: %d", nrow(dgp_registry)),
    sprintf("- Planned VB fits: %d", nrow(candidate_registry)),
    "- Models: Joint/Independent QDESN and exQDESN",
    "- Article files modified: no",
    "- MCMC launched: no"
  ), readme_path, useBytes = TRUE)

  paths <- c(
    run_config = app_joint_qvp_write_csv(
      run_config,
      file.path(out_dir, "run_config.csv")
    ),
    source_manifest_verification = app_joint_qvp_write_csv(
      source_manifest,
      file.path(out_dir, "source_manifest_verification.csv")
    ),
    frozen_case_model_controls = app_joint_qvp_write_csv(
      freeze$frozen,
      file.path(out_dir, "frozen_case_model_controls.csv")
    ),
    frozen_case_model_control_audit = app_joint_qvp_write_csv(
      freeze$audit,
      file.path(out_dir, "frozen_case_model_control_audit.csv")
    ),
    fresh_dgp_registry = app_joint_qvp_write_csv(
      dgp_registry,
      file.path(out_dir, "fresh_dgp_registry.csv")
    ),
    seed_collision_audit = app_joint_qvp_write_csv(
      seed_audit,
      file.path(out_dir, "seed_collision_audit.csv")
    ),
    candidate_registry = app_joint_qvp_write_csv(
      candidate_registry,
      file.path(out_dir, "candidate_registry.csv")
    ),
    replication_design = app_joint_qvp_write_csv(
      replication_design,
      file.path(out_dir, "replication_design.csv")
    ),
    comparison_contract = app_joint_qvp_write_csv(
      app_joint_qdesn_phase153_comparison_contract(),
      file.path(out_dir, "comparison_contract.csv")
    ),
    exhausted_dimension_audit = app_joint_qvp_write_csv(
      app_joint_qdesn_phase153_exhausted_dimension_audit(),
      file.path(out_dir, "exhausted_dimension_audit.csv")
    ),
    readiness_assessment = app_joint_qvp_write_csv(
      assessment,
      file.path(out_dir, "readiness_assessment.csv")
    ),
    provenance = app_joint_qvp_write_csv(
      app_joint_qvp_provenance_rows(),
      file.path(out_dir, "provenance.csv")
    ),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = out_dir,
    fixture_dir = fixture_dir,
    assessment = assessment,
    frozen_controls = freeze$frozen,
    dgp_registry = dgp_registry,
    candidate_registry = candidate_registry,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}

app_joint_qdesn_phase153_parse_integer_grid <- function(x) {
  values <- trimws(strsplit(as.character(x)[[1L]], ",", fixed = TRUE)[[1L]])
  values <- suppressWarnings(as.integer(values[nzchar(values)]))
  values <- values[is.finite(values) & values > 0L]
  if (!length(values)) stop("Malformed adaptive VB iteration grid.", call. = FALSE)
  values
}

app_joint_qdesn_phase153_controls <- function(candidate) {
  app_joint_qdesn_simulation_controls(
    vb_max_iter = as.integer(candidate$vb_max_iter[[1L]]),
    adaptive_vb_max_iter_grid = app_joint_qdesn_phase153_parse_integer_grid(
      candidate$adaptive_vb_max_iter_grid[[1L]]
    ),
    vb_tol = as.numeric(candidate$vb_tol[[1L]]),
    rhs_vb_inner = as.integer(candidate$rhs_vb_inner[[1L]]),
    tau0 = as.numeric(candidate$tau0[[1L]]),
    zeta2 = as.numeric(candidate$zeta2[[1L]]),
    a_sigma = as.numeric(candidate$a_sigma[[1L]]),
    b_sigma = as.numeric(candidate$b_sigma[[1L]]),
    alpha_prior_sd = app_joint_qdesn_parse_numeric_vector(
      candidate$alpha_prior_sd[[1L]],
      "alpha_prior_sd",
      allow_inf = TRUE
    ),
    alpha_min_spacing = as.numeric(candidate$alpha_min_spacing[[1L]]),
    gamma_init_policy = candidate$gamma_init_policy[[1L]],
    review_adjustment_threshold = as.numeric(
      candidate$review_adjustment_threshold[[1L]]
    ),
    max_dense_dim = as.integer(candidate$max_dense_dim[[1L]]),
    n_cores = 1L
  )
}

app_joint_qdesn_phase153_window_summary <- function(
  scored,
  raw_crossing_pairs,
  contract_crossing_pairs,
  adjustments,
  validation_window
) {
  hit <- aggregate(hit ~ tau, scored, mean)
  crps <- app_joint_qdesn_crps_grid_summary(scored, "qhat")
  data.frame(
    validation_window = validation_window,
    n_quantile_scores = nrow(scored),
    truth_mae = mean(scored$truth_abs_error),
    truth_rmse = sqrt(mean(scored$truth_sq_error)),
    truth_bias = mean(scored$truth_error),
    check_loss_mean = mean(scored$check_loss),
    crps_grid_mean = if (nrow(crps)) crps$crps_grid_mean[[1L]] else NA_real_,
    max_abs_hit_rate_error = max(abs(hit$hit - hit$tau)),
    raw_crossing_pairs = as.integer(raw_crossing_pairs),
    contract_crossing_pairs = as.integer(contract_crossing_pairs),
    max_abs_adjustment = if (length(adjustments)) max(abs(adjustments)) else 0,
    adjustment_rate = if (length(adjustments)) {
      mean(abs(adjustments) > 1.0e-10)
    } else {
      0
    },
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase153_tau_summary <- function(
  scored,
  candidate,
  validation_window
) {
  rows <- lapply(split(scored, scored$tau), function(block) {
    data.frame(
      candidate_id = candidate$candidate_id[[1L]],
      base_scenario_id = candidate$base_scenario_id[[1L]],
      dgp_replicate_id = candidate$dgp_replicate_id[[1L]],
      dgp_seed = as.integer(candidate$dgp_seed[[1L]]),
      model_id = candidate$model_id[[1L]],
      validation_window = validation_window,
      tau = block$tau[[1L]],
      n_scores = nrow(block),
      truth_mae = mean(block$truth_abs_error),
      truth_rmse = sqrt(mean(block$truth_sq_error)),
      truth_bias = mean(block$truth_error),
      check_loss_mean = mean(block$check_loss),
      hit_rate = mean(block$hit),
      hit_rate_error = mean(block$hit) - block$tau[[1L]],
      abs_hit_rate_error = abs(mean(block$hit) - block$tau[[1L]]),
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase153_evaluate_candidate <- function(artifacts, candidate) {
  scenario_id <- candidate$scenario_ids[[1L]]
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
  controls <- app_joint_qdesn_phase153_controls(candidate)
  spec <- app_joint_qdesn_filter_model_specs(candidate$model_id[[1L]])
  meta <- data.frame(
    scenario_id = scenario_id,
    scenario_class = fixture$scenario_meta$scenario_class[[1L]],
    distribution_family = fixture$scenario_meta$distribution_family[[1L]],
    dynamics_class = fixture$scenario_meta$dynamics_class[[1L]],
    model_id = spec$model_id[[1L]],
    display_label = spec$display_label[[1L]],
    likelihood = spec$likelihood[[1L]],
    fit_structure = spec$fit_structure[[1L]],
    inference = spec$inference[[1L]],
    experiment_id = candidate$candidate_id[[1L]],
    stringsAsFactors = FALSE
  )

  start <- proc.time()[["elapsed"]]
  fit <- app_joint_qdesn_fit_model_adaptive(fixture, spec, controls)
  fit_seconds <- proc.time()[["elapsed"]] - start

  fit_raw <- app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau)
  fit_contract <- app_joint_qdesn_apply_monotone_contract(fit_raw, fixture$tau)
  fit_rows <- app_joint_qdesn_quantile_long_rows(
    meta,
    fixture$row_meta,
    fixture$tau,
    fixture$y,
    fixture$true_q,
    fit_contract$qhat_contract,
    "qhat"
  )
  fit_scored <- app_joint_qdesn_quantile_scores(fit_rows, "qhat")
  fit_summary <- app_joint_qdesn_phase153_window_summary(
    fit_scored,
    sum(fit_contract$raw_crossing$n_crossing_pairs),
    sum(fit_contract$contract_crossing$n_crossing_pairs),
    as.numeric(fit_contract$adjustment),
    "fit"
  )

  origin_plan <- artifacts$forecast_origin_plan[
    artifacts$forecast_origin_plan$scenario_id == scenario_id,
    ,
    drop = FALSE
  ]
  origin_plan <- origin_plan[order(origin_plan$origin_index), , drop = FALSE]
  forecast_scored <- vector("list", nrow(origin_plan))
  forecast_adjustments <- numeric()
  forecast_raw_pairs <- 0L
  forecast_contract_pairs <- 0L
  forecast_start <- proc.time()[["elapsed"]]
  for (jj in seq_len(nrow(origin_plan))) {
    target <- app_joint_qdesn_forecast_target_fixture(
      artifacts,
      scenario_id,
      origin_plan[jj, , drop = FALSE]
    )
    if (!identical(fixture$feature_cols, target$feature_cols)) {
      stop("Phase 153 feature columns changed between fit and forecast.", call. = FALSE)
    }
    raw <- app_joint_qdesn_predict_fit(fit, target$Z, target$tau)
    contract <- app_joint_qdesn_apply_monotone_contract(raw, target$tau)
    rows <- app_joint_qdesn_quantile_long_rows(
      meta,
      target$row_meta,
      target$tau,
      target$y,
      target$true_q,
      contract$qhat_contract,
      "qhat"
    )
    forecast_scored[[jj]] <- app_joint_qdesn_quantile_scores(rows, "qhat")
    forecast_adjustments <- c(
      forecast_adjustments,
      as.numeric(contract$adjustment)
    )
    forecast_raw_pairs <- forecast_raw_pairs +
      sum(contract$raw_crossing$n_crossing_pairs)
    forecast_contract_pairs <- forecast_contract_pairs +
      sum(contract$contract_crossing$n_crossing_pairs)
  }
  forecast_seconds <- proc.time()[["elapsed"]] - forecast_start
  forecast_scored <- app_joint_qdesn_bind_rows(forecast_scored)
  forecast_summary <- app_joint_qdesn_phase153_window_summary(
    forecast_scored,
    forecast_raw_pairs,
    forecast_contract_pairs,
    forecast_adjustments,
    "forecast"
  )

  trace <- fit$trace %||% data.frame()
  rhs <- fit$rhs_prior_summary %||% data.frame()
  trace_numeric <- trace[vapply(trace, is.numeric, logical(1L))]
  rhs_numeric <- rhs[vapply(rhs, is.numeric, logical(1L))]
  finite_trace <- nrow(trace) > 0L &&
    all(is.finite(as.matrix(trace_numeric)))
  finite_rhs <- nrow(rhs) > 0L &&
    all(is.finite(as.matrix(rhs_numeric)))
  finite_alpha <- !is.null(fit$alpha_mean) && all(is.finite(fit$alpha_mean))
  finite_sigma <- !is.null(fit$sigma_mean) &&
    all(is.finite(fit$sigma_mean)) &&
    all(as.numeric(fit$sigma_mean) > 0)
  finite_gamma <- if (identical(spec$likelihood[[1L]], "exal")) {
    !is.null(fit$gamma_mean) && all(is.finite(fit$gamma_mean))
  } else {
    TRUE
  }
  finite_scores <- all(is.finite(c(
    fit_scored$qhat,
    fit_scored$check_loss,
    fit_scored$truth_error,
    forecast_scored$qhat,
    forecast_scored$check_loss,
    forecast_scored$truth_error
  )))
  reached_max <- !isTRUE(fit$converged)
  hard_fail <- !finite_trace || !finite_rhs || !finite_alpha ||
    !finite_sigma || !finite_gamma || !finite_scores ||
    fit_summary$contract_crossing_pairs[[1L]] > 0L ||
    forecast_summary$contract_crossing_pairs[[1L]] > 0L
  max_adjustment <- max(
    fit_summary$max_abs_adjustment[[1L]],
    forecast_summary$max_abs_adjustment[[1L]]
  )
  review <- !hard_fail && (
    reached_max ||
      fit_summary$raw_crossing_pairs[[1L]] > 0L ||
      forecast_summary$raw_crossing_pairs[[1L]] > 0L ||
      max_adjustment > controls$review_adjustment_threshold
  )
  reasons <- c(
    if (!finite_trace) "nonfinite or missing VB trace",
    if (!finite_rhs) "nonfinite or missing RHS summary",
    if (!finite_alpha) "nonfinite intercept summary",
    if (!finite_sigma) "nonfinite or nonpositive scale summary",
    if (!finite_gamma) "nonfinite exAL gamma summary",
    if (!finite_scores) "nonfinite quantiles or scores",
    if (fit_summary$contract_crossing_pairs[[1L]] > 0L) {
      "fit contract quantiles cross"
    },
    if (forecast_summary$contract_crossing_pairs[[1L]] > 0L) {
      "forecast contract quantiles cross"
    },
    if (!hard_fail && reached_max) "VB reached its adaptive iteration limit",
    if (!hard_fail &&
      fit_summary$raw_crossing_pairs[[1L]] +
        forecast_summary$raw_crossing_pairs[[1L]] > 0L) {
      "raw quantiles required monotone repair"
    },
    if (!hard_fail && max_adjustment > controls$review_adjustment_threshold) {
      "monotone adjustment exceeded the review threshold"
    }
  )

  names(fit_summary)[-1L] <- paste0("fit_", names(fit_summary)[-1L])
  names(forecast_summary)[-1L] <- paste0(
    "forecast_",
    names(forecast_summary)[-1L]
  )
  candidate_summary <- cbind(
    candidate[, c(
      "candidate_id", "base_scenario_id", "dgp_replicate_id", "dgp_seed",
      "model_id", "source_candidate_id", "source_freeze_id",
      "vb_max_iter", "adaptive_vb_max_iter_grid", "vb_tol",
      "rhs_vb_inner", "tau0", "zeta2", "alpha_prior_sd",
      "gamma_init_policy"
    ), drop = FALSE],
    data.frame(
      scenario_id = scenario_id,
      scenario_class = meta$scenario_class[[1L]],
      distribution_family = meta$distribution_family[[1L]],
      dynamics_class = meta$dynamics_class[[1L]],
      display_label = spec$display_label[[1L]],
      likelihood = spec$likelihood[[1L]],
      fit_structure = spec$fit_structure[[1L]],
      inference = spec$inference[[1L]],
      readout_feature_count = ncol(fixture$Z),
      quantile_count = length(fixture$tau),
      dense_dimension = ncol(fixture$Z) * length(fixture$tau),
      gate_status = if (hard_fail) "fail" else if (review) "review" else "pass",
      implementation_status = if (hard_fail) "fail" else "pass",
      vb_converged = isTRUE(fit$converged),
      vb_reached_max_iter = reached_max,
      finite_trace = finite_trace,
      finite_rhs = finite_rhs,
      finite_alpha = finite_alpha,
      finite_sigma = finite_sigma,
      finite_gamma = finite_gamma,
      finite_scores = finite_scores,
      stringsAsFactors = FALSE
    ),
    fit_summary[, setdiff(names(fit_summary), "validation_window"), drop = FALSE],
    forecast_summary[
      ,
      setdiff(names(forecast_summary), "validation_window"),
      drop = FALSE
    ],
    data.frame(
      fit_elapsed_seconds = fit_seconds,
      forecast_scoring_seconds = forecast_seconds,
      total_elapsed_seconds = fit_seconds + forecast_seconds,
      status_reason = if (length(reasons)) {
        paste(unique(reasons), collapse = "; ")
      } else {
        "all Phase 153 candidate gates passed"
      },
      stringsAsFactors = FALSE
    )
  )

  gamma_values <- if (identical(spec$likelihood[[1L]], "exal")) {
    as.numeric(fit$gamma_mean)
  } else {
    numeric()
  }
  vb_diagnostics <- data.frame(
    candidate_id = candidate$candidate_id[[1L]],
    base_scenario_id = candidate$base_scenario_id[[1L]],
    dgp_replicate_id = candidate$dgp_replicate_id[[1L]],
    model_id = candidate$model_id[[1L]],
    converged = isTRUE(fit$converged),
    reached_max_iter = reached_max,
    adaptive_vb_attempts = attr(fit, "adaptive_vb_attempts") %||%
      as.character(controls$vb_max_iter),
    adaptive_vb_max_iter_used = attr(fit, "adaptive_vb_max_iter_used") %||%
      controls$vb_max_iter,
    trace_rows = nrow(trace),
    final_iter = if (nrow(trace) && "iter" %in% names(trace)) {
      max(trace$iter, na.rm = TRUE)
    } else {
      NA_integer_
    },
    final_monitor = if (nrow(trace) && "monitor" %in% names(trace)) {
      tail(trace$monitor, 1L)
    } else {
      NA_real_
    },
    sigma_min = min(as.numeric(fit$sigma_mean)),
    sigma_median = stats::median(as.numeric(fit$sigma_mean)),
    sigma_max = max(as.numeric(fit$sigma_mean)),
    gamma_min = if (length(gamma_values)) min(gamma_values) else NA_real_,
    gamma_median = if (length(gamma_values)) {
      stats::median(gamma_values)
    } else {
      NA_real_
    },
    gamma_max = if (length(gamma_values)) max(gamma_values) else NA_real_,
    finite_trace = finite_trace,
    finite_rhs = finite_rhs,
    stringsAsFactors = FALSE
  )
  tau_summary <- rbind(
    app_joint_qdesn_phase153_tau_summary(fit_scored, candidate, "fit"),
    app_joint_qdesn_phase153_tau_summary(
      forecast_scored,
      candidate,
      "forecast"
    )
  )
  interval_summary <- app_joint_qdesn_bind_rows(list(
    transform(
      app_joint_qdesn_interval_summary(fit_scored, "qhat"),
      candidate_id = candidate$candidate_id[[1L]],
      base_scenario_id = candidate$base_scenario_id[[1L]],
      dgp_replicate_id = candidate$dgp_replicate_id[[1L]],
      dgp_seed = as.integer(candidate$dgp_seed[[1L]]),
      validation_window = "fit"
    ),
    transform(
      app_joint_qdesn_interval_summary(forecast_scored, "qhat"),
      candidate_id = candidate$candidate_id[[1L]],
      base_scenario_id = candidate$base_scenario_id[[1L]],
      dgp_replicate_id = candidate$dgp_replicate_id[[1L]],
      dgp_seed = as.integer(candidate$dgp_seed[[1L]]),
      validation_window = "forecast"
    )
  ))
  list(
    candidate_summary = candidate_summary,
    tau_summary = tau_summary,
    interval_summary = interval_summary,
    vb_diagnostics = vb_diagnostics
  )
}

app_joint_qdesn_phase153_candidate_dir <- function(out_dir, candidate_id) {
  file.path(out_dir, "candidates", candidate_id)
}

app_joint_qdesn_phase153_verify_candidate_dir <- function(candidate_dir) {
  manifest_path <- file.path(candidate_dir, "artifact_manifest.csv")
  if (!file.exists(manifest_path)) return(FALSE)
  tryCatch({
    manifest <- app_read_csv(manifest_path)
    required <- c(
      "candidate_summary",
      "tau_summary",
      "interval_summary",
      "vb_diagnostics",
      "readme"
    )
    if (!all(required %in% manifest$label)) return(FALSE)
    paths <- file.path(candidate_dir, manifest$relative_path)
    actual <- vapply(paths, app_sha256_file, character(1L))
    sizes <- as.numeric(file.info(paths)$size)
    all(file.exists(paths)) &&
      all(tolower(actual) == tolower(manifest$sha256)) &&
      all(sizes == as.numeric(manifest$size_bytes))
  }, error = function(e) FALSE)
}

app_joint_qdesn_phase153_write_candidate <- function(
  result,
  out_dir,
  candidate_id
) {
  final_dir <- app_joint_qdesn_phase153_candidate_dir(out_dir, candidate_id)
  app_ensure_dir(dirname(final_dir))
  if (app_joint_qdesn_phase153_verify_candidate_dir(final_dir)) {
    return(final_dir)
  }
  if (dir.exists(final_dir)) {
    quarantine <- paste0(
      final_dir,
      ".invalid.",
      format(Sys.time(), "%Y%m%d%H%M%S")
    )
    if (!file.rename(final_dir, quarantine)) {
      stop("Could not quarantine an invalid Phase 153 checkpoint.", call. = FALSE)
    }
  }
  tmp_dir <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp_dir)) unlink(tmp_dir, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp_dir)
  readme_path <- file.path(tmp_dir, "README.md")
  writeLines(c(
    "# Phase 153 Candidate Checkpoint",
    "",
    sprintf("- Candidate: `%s`", candidate_id),
    sprintf(
      "- Base scenario: `%s`",
      result$candidate_summary$base_scenario_id[[1L]]
    ),
    sprintf(
      "- DGP replicate: `%s`",
      result$candidate_summary$dgp_replicate_id[[1L]]
    ),
    sprintf("- Model: `%s`", result$candidate_summary$model_id[[1L]]),
    "",
    "This atomic checkpoint stores compact summaries only. No fitted object is retained."
  ), readme_path, useBytes = TRUE)
  paths <- c(
    candidate_summary = app_joint_qvp_write_csv(
      result$candidate_summary,
      file.path(tmp_dir, "candidate_summary.csv")
    ),
    tau_summary = app_joint_qvp_write_csv(
      result$tau_summary,
      file.path(tmp_dir, "tau_summary.csv")
    ),
    interval_summary = app_joint_qvp_write_csv(
      result$interval_summary,
      file.path(tmp_dir, "interval_summary.csv")
    ),
    vb_diagnostics = app_joint_qvp_write_csv(
      result$vb_diagnostics,
      file.path(tmp_dir, "vb_diagnostics.csv")
    ),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  app_joint_qvp_write_csv(
    manifest,
    file.path(tmp_dir, "artifact_manifest.csv")
  )
  if (!file.rename(tmp_dir, final_dir) ||
      !app_joint_qdesn_phase153_verify_candidate_dir(final_dir)) {
    stop(sprintf(
      "Could not promote Phase 153 checkpoint '%s'.",
      candidate_id
    ), call. = FALSE)
  }
  final_dir
}

app_joint_qdesn_phase153_load_completed <- function(out_dir, registry) {
  rows <- lapply(seq_len(nrow(registry)), function(ii) {
    candidate_id <- registry$candidate_id[[ii]]
    dir <- app_joint_qdesn_phase153_candidate_dir(out_dir, candidate_id)
    if (!app_joint_qdesn_phase153_verify_candidate_dir(dir)) return(NULL)
    list(
      candidate_summary = app_read_csv(
        file.path(dir, "candidate_summary.csv")
      ),
      tau_summary = app_read_csv(file.path(dir, "tau_summary.csv")),
      interval_summary = app_read_csv(
        file.path(dir, "interval_summary.csv")
      ),
      vb_diagnostics = app_read_csv(
        file.path(dir, "vb_diagnostics.csv")
      )
    )
  })
  rows[!vapply(rows, is.null, logical(1L))]
}

app_joint_qdesn_phase153_candidate_manifest_rows <- function(
  out_dir,
  registry
) {
  rows <- lapply(seq_len(nrow(registry)), function(ii) {
    candidate_id <- registry$candidate_id[[ii]]
    dir <- app_joint_qdesn_phase153_candidate_dir(out_dir, candidate_id)
    verified <- app_joint_qdesn_phase153_verify_candidate_dir(dir)
    data.frame(
      candidate_id = candidate_id,
      base_scenario_id = registry$base_scenario_id[[ii]],
      dgp_replicate_id = registry$dgp_replicate_id[[ii]],
      model_id = registry$model_id[[ii]],
      candidate_dir = app_prefer_repo_relative_path(dir),
      manifest_verified = verified,
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase153_metric_names <- function() {
  c(
    "fit_truth_mae",
    "fit_truth_rmse",
    "fit_check_loss_mean",
    "fit_crps_grid_mean",
    "fit_max_abs_hit_rate_error",
    "forecast_truth_mae",
    "forecast_truth_rmse",
    "forecast_check_loss_mean",
    "forecast_crps_grid_mean",
    "forecast_max_abs_hit_rate_error"
  )
}

app_joint_qdesn_phase153_distribution_summary <- function(candidate_summary) {
  metrics <- app_joint_qdesn_phase153_metric_names()
  groups <- split(
    candidate_summary,
    interaction(
      candidate_summary$base_scenario_id,
      candidate_summary$model_id,
      drop = TRUE,
      lex.order = TRUE
    )
  )
  rows <- list()
  for (block in groups) {
    for (metric in metrics) {
      values <- as.numeric(block[[metric]])
      rows[[length(rows) + 1L]] <- data.frame(
        base_scenario_id = block$base_scenario_id[[1L]],
        model_id = block$model_id[[1L]],
        metric = metric,
        n = sum(is.finite(values)),
        mean = mean(values, na.rm = TRUE),
        sd = stats::sd(values, na.rm = TRUE),
        median = stats::median(values, na.rm = TRUE),
        q10 = as.numeric(stats::quantile(values, 0.10, na.rm = TRUE)),
        q90 = as.numeric(stats::quantile(values, 0.90, na.rm = TRUE)),
        minimum = min(values, na.rm = TRUE),
        maximum = max(values, na.rm = TRUE),
        stringsAsFactors = FALSE
      )
    }
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase153_paired_contrast_rows <- function(candidate_summary) {
  contracts <- app_joint_qdesn_phase153_all_pair_contract()
  metrics <- app_joint_qdesn_phase153_metric_names()
  groups <- split(
    candidate_summary,
    interaction(
      candidate_summary$base_scenario_id,
      candidate_summary$dgp_replicate_id,
      drop = TRUE,
      lex.order = TRUE
    )
  )
  rows <- list()
  for (block in groups) {
    if (!setequal(block$model_id, app_joint_qdesn_phase153_model_order())) next
    for (cc in seq_len(nrow(contracts))) {
      a <- block[block$model_id == contracts$model_a[[cc]], , drop = FALSE]
      b <- block[block$model_id == contracts$model_b[[cc]], , drop = FALSE]
      for (metric in metrics) {
        av <- as.numeric(a[[metric]][[1L]])
        bv <- as.numeric(b[[metric]][[1L]])
        rows[[length(rows) + 1L]] <- data.frame(
          base_scenario_id = block$base_scenario_id[[1L]],
          dgp_replicate_id = block$dgp_replicate_id[[1L]],
          dgp_seed = as.integer(block$dgp_seed[[1L]]),
          contrast_id = contracts$contrast_id[[cc]],
          model_a = contracts$model_a[[cc]],
          model_b = contracts$model_b[[cc]],
          metric = metric,
          model_a_value = av,
          model_b_value = bv,
          delta_model_a_minus_b = av - bv,
          relative_delta = if (is.finite(bv) && abs(bv) > .Machine$double.eps) {
            (av - bv) / bv
          } else {
            NA_real_
          },
          model_a_wins = is.finite(av) && is.finite(bv) && av < bv,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase153_wilson_interval <- function(wins, n, level = 0.95) {
  if (!is.finite(n) || n <= 0L) return(c(NA_real_, NA_real_))
  z <- stats::qnorm(1 - (1 - level) / 2)
  p <- wins / n
  denom <- 1 + z^2 / n
  center <- (p + z^2 / (2 * n)) / denom
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / denom
  c(max(0, center - half), min(1, center + half))
}

app_joint_qdesn_phase153_contrast_classification <- function(
  metric,
  median_delta,
  ci_lower,
  ci_upper,
  reference_median
) {
  if (!identical(metric, "forecast_truth_mae")) return("descriptive_secondary")
  margin <- max(0.0025, 0.02 * abs(reference_median))
  if (is.finite(ci_upper) && ci_upper < -margin) return("supported_better")
  if (is.finite(ci_lower) && ci_lower > margin) return("supported_worse")
  if (is.finite(ci_lower) && is.finite(ci_upper) &&
      ci_lower >= -margin && ci_upper <= margin) {
    return("practically_equivalent")
  }
  "inconclusive"
}

app_joint_qdesn_phase153_paired_contrast_summary <- function(
  paired_rows,
  bootstrap_replicates = 2000L,
  seed_base = 153900000L
) {
  keys <- unique(paired_rows[, c(
    "base_scenario_id", "contrast_id", "model_a", "model_b", "metric"
  ), drop = FALSE])
  keys <- keys[order(
    keys$base_scenario_id,
    keys$contrast_id,
    keys$metric
  ), , drop = FALSE]
  rows <- vector("list", nrow(keys))
  for (ii in seq_len(nrow(keys))) {
    key <- keys[ii, , drop = FALSE]
    idx <- paired_rows$base_scenario_id == key$base_scenario_id[[1L]] &
      paired_rows$contrast_id == key$contrast_id[[1L]] &
      paired_rows$metric == key$metric[[1L]]
    block <- paired_rows[idx, , drop = FALSE]
    delta <- as.numeric(block$delta_model_a_minus_b)
    delta <- delta[is.finite(delta)]
    wins <- sum(block$model_a_wins, na.rm = TRUE)
    n <- length(delta)
    set.seed(as.integer(seed_base) + ii)
    boot <- if (n && as.integer(bootstrap_replicates) > 0L) {
      replicate(
        as.integer(bootstrap_replicates),
        stats::median(sample(delta, size = n, replace = TRUE))
      )
    } else {
      NA_real_
    }
    ci <- if (all(is.finite(boot))) {
      as.numeric(stats::quantile(boot, c(0.025, 0.975), names = FALSE))
    } else {
      c(NA_real_, NA_real_)
    }
    wilson <- app_joint_qdesn_phase153_wilson_interval(wins, n)
    reference_median <- stats::median(block$model_b_value, na.rm = TRUE)
    median_delta <- stats::median(delta, na.rm = TRUE)
    rows[[ii]] <- cbind(
      key,
      data.frame(
        n_replicates = n,
        mean_delta = mean(delta, na.rm = TRUE),
        median_delta = median_delta,
        mean_relative_delta = mean(block$relative_delta, na.rm = TRUE),
        median_relative_delta = stats::median(
          block$relative_delta,
          na.rm = TRUE
        ),
        model_a_wins = wins,
        model_a_win_fraction = wins / n,
        win_fraction_ci_lower = wilson[[1L]],
        win_fraction_ci_upper = wilson[[2L]],
        bootstrap_median_ci_lower = ci[[1L]],
        bootstrap_median_ci_upper = ci[[2L]],
        reference_median = reference_median,
        practical_margin = max(0.0025, 0.02 * abs(reference_median)),
        contrast_classification = app_joint_qdesn_phase153_contrast_classification(
          key$metric[[1L]],
          median_delta,
          ci[[1L]],
          ci[[2L]],
          reference_median
        ),
        bootstrap_replicates = as.integer(bootstrap_replicates),
        bootstrap_seed = as.integer(seed_base) + ii,
        stringsAsFactors = FALSE
      )
    )
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase153_rank_rows <- function(candidate_summary) {
  groups <- split(
    candidate_summary,
    interaction(
      candidate_summary$base_scenario_id,
      candidate_summary$dgp_replicate_id,
      drop = TRUE,
      lex.order = TRUE
    )
  )
  rows <- lapply(groups, function(block) {
    values <- block$forecast_truth_mae
    block$forecast_mae_rank <- rank(values, ties.method = "average")
    block$replicate_winner <- values == min(values, na.rm = TRUE)
    block[, c(
      "base_scenario_id", "dgp_replicate_id", "dgp_seed",
      "model_id", "forecast_truth_mae", "forecast_mae_rank",
      "replicate_winner"
    ), drop = FALSE]
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase153_rank_summary <- function(rank_rows) {
  groups <- split(
    rank_rows,
    interaction(
      rank_rows$base_scenario_id,
      rank_rows$model_id,
      drop = TRUE,
      lex.order = TRUE
    )
  )
  rows <- lapply(groups, function(block) {
    data.frame(
      base_scenario_id = block$base_scenario_id[[1L]],
      model_id = block$model_id[[1L]],
      n_replicates = nrow(block),
      mean_rank = mean(block$forecast_mae_rank),
      median_rank = stats::median(block$forecast_mae_rank),
      winner_count = sum(block$replicate_winner),
      winner_fraction = mean(block$replicate_winner),
      median_forecast_truth_mae = stats::median(block$forecast_truth_mae),
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase153_tau_contrast_summary <- function(tau_summary) {
  contract <- app_joint_qdesn_phase153_comparison_contract()
  metrics <- c("truth_mae", "check_loss_mean", "abs_hit_rate_error")
  groups <- split(
    tau_summary,
    interaction(
      tau_summary$base_scenario_id,
      tau_summary$dgp_replicate_id,
      tau_summary$validation_window,
      tau_summary$tau,
      drop = TRUE,
      lex.order = TRUE
    )
  )
  replicate_rows <- list()
  for (block in groups) {
    if (!setequal(block$model_id, app_joint_qdesn_phase153_model_order())) next
    for (cc in seq_len(nrow(contract))) {
      a <- block[block$model_id == contract$model_a[[cc]], , drop = FALSE]
      b <- block[block$model_id == contract$model_b[[cc]], , drop = FALSE]
      for (metric in metrics) {
        replicate_rows[[length(replicate_rows) + 1L]] <- data.frame(
          base_scenario_id = block$base_scenario_id[[1L]],
          dgp_replicate_id = block$dgp_replicate_id[[1L]],
          validation_window = block$validation_window[[1L]],
          tau = block$tau[[1L]],
          contrast_id = contract$contrast_id[[cc]],
          model_a = contract$model_a[[cc]],
          model_b = contract$model_b[[cc]],
          metric = metric,
          delta_model_a_minus_b = as.numeric(a[[metric]][[1L]]) -
            as.numeric(b[[metric]][[1L]]),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  replicate_rows <- app_joint_qdesn_bind_rows(replicate_rows)
  groups <- split(
    replicate_rows,
    interaction(
      replicate_rows$base_scenario_id,
      replicate_rows$validation_window,
      replicate_rows$tau,
      replicate_rows$contrast_id,
      replicate_rows$metric,
      drop = TRUE,
      lex.order = TRUE
    )
  )
  summary <- lapply(groups, function(block) {
    x <- block$delta_model_a_minus_b
    data.frame(
      base_scenario_id = block$base_scenario_id[[1L]],
      validation_window = block$validation_window[[1L]],
      tau = block$tau[[1L]],
      contrast_id = block$contrast_id[[1L]],
      model_a = block$model_a[[1L]],
      model_b = block$model_b[[1L]],
      metric = block$metric[[1L]],
      n_replicates = sum(is.finite(x)),
      mean_delta = mean(x, na.rm = TRUE),
      median_delta = stats::median(x, na.rm = TRUE),
      model_a_win_fraction = mean(x < 0, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  list(
    replicate_rows = replicate_rows,
    summary = app_joint_qdesn_bind_rows(summary)
  )
}

app_joint_qdesn_phase153_group_diagnostic_summary <- function(candidate_summary) {
  groups <- split(
    candidate_summary,
    interaction(
      candidate_summary$base_scenario_id,
      candidate_summary$model_id,
      drop = TRUE,
      lex.order = TRUE
    )
  )
  rows <- lapply(groups, function(block) {
    data.frame(
      base_scenario_id = block$base_scenario_id[[1L]],
      model_id = block$model_id[[1L]],
      candidates = nrow(block),
      implementation_failures = sum(block$implementation_status == "fail"),
      review_candidates = sum(block$gate_status == "review"),
      vb_max_iteration_cases = sum(block$vb_reached_max_iter),
      fit_raw_crossing_pairs = sum(block$fit_raw_crossing_pairs),
      forecast_raw_crossing_pairs = sum(block$forecast_raw_crossing_pairs),
      fit_contract_crossing_pairs = sum(block$fit_contract_crossing_pairs),
      forecast_contract_crossing_pairs = sum(
        block$forecast_contract_crossing_pairs
      ),
      max_fit_adjustment = max(block$fit_max_abs_adjustment),
      max_forecast_adjustment = max(block$forecast_max_abs_adjustment),
      total_elapsed_seconds = sum(block$total_elapsed_seconds),
      median_elapsed_seconds = stats::median(block$total_elapsed_seconds),
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase153_aggregate <- function(
  out_dir,
  readiness_dir = app_joint_qdesn_phase153_default_readiness_dir(),
  bootstrap_replicates = 2000L,
  bootstrap_seed_base = 153900000L
) {
  out_dir <- normalizePath(out_dir, mustWork = TRUE)
  registry <- app_read_csv(file.path(readiness_dir, "candidate_registry.csv"))
  completed <- app_joint_qdesn_phase153_load_completed(out_dir, registry)
  if (length(completed) != nrow(registry)) {
    stop(sprintf(
      "Phase 153 aggregation requires %d checkpoints; found %d.",
      nrow(registry),
      length(completed)
    ), call. = FALSE)
  }
  candidate_summary <- app_joint_qdesn_bind_rows(lapply(
    completed,
    `[[`,
    "candidate_summary"
  ))
  tau_summary <- app_joint_qdesn_bind_rows(lapply(
    completed,
    `[[`,
    "tau_summary"
  ))
  interval_summary <- app_joint_qdesn_bind_rows(lapply(
    completed,
    `[[`,
    "interval_summary"
  ))
  vb_diagnostics <- app_joint_qdesn_bind_rows(lapply(
    completed,
    `[[`,
    "vb_diagnostics"
  ))
  candidate_summary <- candidate_summary[order(
    candidate_summary$base_scenario_id,
    candidate_summary$dgp_replicate_id,
    match(candidate_summary$model_id, app_joint_qdesn_phase153_model_order())
  ), , drop = FALSE]
  tau_summary <- tau_summary[order(
    tau_summary$base_scenario_id,
    tau_summary$dgp_replicate_id,
    match(tau_summary$model_id, app_joint_qdesn_phase153_model_order()),
    tau_summary$validation_window,
    tau_summary$tau
  ), , drop = FALSE]
  candidate_manifest <- app_joint_qdesn_phase153_candidate_manifest_rows(
    out_dir,
    registry
  )
  distribution <- app_joint_qdesn_phase153_distribution_summary(
    candidate_summary
  )
  paired_rows <- app_joint_qdesn_phase153_paired_contrast_rows(
    candidate_summary
  )
  paired_summary <- app_joint_qdesn_phase153_paired_contrast_summary(
    paired_rows,
    bootstrap_replicates = bootstrap_replicates,
    seed_base = bootstrap_seed_base
  )
  rank_rows <- app_joint_qdesn_phase153_rank_rows(candidate_summary)
  rank_summary <- app_joint_qdesn_phase153_rank_summary(rank_rows)
  tau_contrast <- app_joint_qdesn_phase153_tau_contrast_summary(tau_summary)
  diagnostics <- app_joint_qdesn_phase153_group_diagnostic_summary(
    candidate_summary
  )
  worker_failures_path <- file.path(out_dir, "worker_failures.csv")
  worker_failures <- if (file.exists(worker_failures_path)) {
    app_read_csv(worker_failures_path)
  } else {
    data.frame()
  }
  expected <- nrow(registry)
  expected_group_rows <- 8L * 50L * 4L
  if (length(unique(registry$dgp_replicate_id)) != 50L) {
    expected_group_rows <- nrow(registry)
  }
  complete_grid <- nrow(candidate_summary) == expected &&
    !anyDuplicated(paste(
      candidate_summary$base_scenario_id,
      candidate_summary$dgp_replicate_id,
      candidate_summary$model_id,
      sep = "::"
    ))
  hard_fail <- !complete_grid ||
    any(!candidate_manifest$manifest_verified) ||
    nrow(worker_failures) > 0L ||
    any(candidate_summary$implementation_status == "fail") ||
    any(!candidate_summary$finite_scores) ||
    any(candidate_summary$fit_contract_crossing_pairs > 0L) ||
    any(candidate_summary$forecast_contract_crossing_pairs > 0L)
  review <- !hard_fail && (
    any(candidate_summary$gate_status == "review") ||
      any(candidate_summary$vb_reached_max_iter)
  )
  assessment <- data.frame(
    audit_id = "phase153_balanced_independent_replication",
    gate_status = if (hard_fail) "fail" else if (review) "review" else "pass",
    expected_candidates = expected,
    completed_candidates = nrow(candidate_summary),
    remaining_candidates = expected - nrow(candidate_summary),
    candidate_manifest_failures = sum(!candidate_manifest$manifest_verified),
    worker_failures = nrow(worker_failures),
    implementation_failures = sum(
      candidate_summary$implementation_status == "fail"
    ),
    vb_max_iteration_cases = sum(candidate_summary$vb_reached_max_iter),
    raw_crossing_pairs = sum(
      candidate_summary$fit_raw_crossing_pairs +
        candidate_summary$forecast_raw_crossing_pairs
    ),
    contract_crossing_pairs = sum(
      candidate_summary$fit_contract_crossing_pairs +
        candidate_summary$forecast_contract_crossing_pairs
    ),
    paired_grid_complete = complete_grid,
    expected_grid_rows = expected_group_rows,
    mcmc_launched = FALSE,
    article_assets_modified = FALSE,
    recommendation = if (hard_fail) {
      "repair_phase153_before_scientific_interpretation"
    } else {
      "audit_replicated_contrasts_then_decide_phase154_mcmc"
    },
    stringsAsFactors = FALSE
  )
  article_recommendation <- data.frame(
    decision_id = "phase153_article_readiness",
    implementation_gate = assessment$gate_status[[1L]],
    article_update_now = FALSE,
    mcmc_launch_now = FALSE,
    next_action = assessment$recommendation[[1L]],
    interpretation = paste(
      "Phase153 is independent VB confirmation of frozen per-case controls.",
      "Article promotion requires a separate audit and, if warranted,",
      "predeclared fresh-root MCMC confirmation."
    ),
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Joint QDESN Phase 153 Replication Results",
    "",
    sprintf("- Gate: `%s`", assessment$gate_status[[1L]]),
    sprintf(
      "- Candidate checkpoints: %d/%d",
      nrow(candidate_summary),
      expected
    ),
    sprintf(
      "- Contract crossings: %d",
      assessment$contract_crossing_pairs[[1L]]
    ),
    "",
    "Model performance is interpreted from paired fresh-DGP contrasts.",
    "Underperformance is scientific evidence, not an implementation failure.",
    "No article asset or MCMC result is modified by this packet."
  ), readme_path, useBytes = TRUE)

  paths <- c(
    candidate_manifest_verification = app_joint_qvp_write_csv(
      candidate_manifest,
      file.path(out_dir, "candidate_manifest_verification.csv")
    ),
    candidate_summary = app_joint_qvp_write_csv(
      candidate_summary,
      file.path(out_dir, "candidate_summary.csv")
    ),
    candidate_tau_summary = app_joint_qvp_write_csv(
      tau_summary,
      file.path(out_dir, "candidate_tau_summary.csv")
    ),
    candidate_interval_summary = app_joint_qvp_write_csv(
      interval_summary,
      file.path(out_dir, "candidate_interval_summary.csv")
    ),
    vb_diagnostics = app_joint_qvp_write_csv(
      vb_diagnostics,
      file.path(out_dir, "vb_diagnostics.csv")
    ),
    scenario_model_distribution_summary = app_joint_qvp_write_csv(
      distribution,
      file.path(out_dir, "scenario_model_distribution_summary.csv")
    ),
    paired_contrast_replicate_rows = app_joint_qvp_write_csv(
      paired_rows,
      file.path(out_dir, "paired_contrast_replicate_rows.csv")
    ),
    paired_contrast_summary = app_joint_qvp_write_csv(
      paired_summary,
      file.path(out_dir, "paired_contrast_summary.csv")
    ),
    scenario_model_rank_replicate_rows = app_joint_qvp_write_csv(
      rank_rows,
      file.path(out_dir, "scenario_model_rank_replicate_rows.csv")
    ),
    scenario_model_rank_summary = app_joint_qvp_write_csv(
      rank_summary,
      file.path(out_dir, "scenario_model_rank_summary.csv")
    ),
    paired_tau_contrast_replicate_rows = app_joint_qvp_write_csv(
      tau_contrast$replicate_rows,
      file.path(out_dir, "paired_tau_contrast_replicate_rows.csv")
    ),
    paired_tau_contrast_summary = app_joint_qvp_write_csv(
      tau_contrast$summary,
      file.path(out_dir, "paired_tau_contrast_summary.csv")
    ),
    diagnostic_summary = app_joint_qvp_write_csv(
      diagnostics,
      file.path(out_dir, "diagnostic_summary.csv")
    ),
    replication_assessment = app_joint_qvp_write_csv(
      assessment,
      file.path(out_dir, "replication_assessment.csv")
    ),
    article_readiness_recommendation = app_joint_qvp_write_csv(
      article_recommendation,
      file.path(out_dir, "article_readiness_recommendation.csv")
    ),
    provenance = app_joint_qvp_write_csv(
      app_joint_qvp_provenance_rows(),
      file.path(out_dir, "provenance.csv")
    ),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  old_manifest <- file.path(out_dir, "artifact_manifest.csv")
  if (file.exists(old_manifest)) unlink(old_manifest)
  manifest <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = out_dir,
    assessment = assessment,
    candidate_summary = candidate_summary,
    paired_contrast_summary = paired_summary,
    rank_summary = rank_summary,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}

app_joint_qdesn_run_phase153 <- function(
  out_dir = app_joint_qdesn_phase153_default_vb_dir(),
  readiness_dir = app_joint_qdesn_phase153_default_readiness_dir(),
  fixture_dir = app_joint_qdesn_phase153_default_fixture_dir(),
  n_cores = 20L,
  incomplete_only = TRUE,
  bootstrap_replicates = 2000L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  readiness <- app_read_csv(file.path(
    readiness_dir,
    "readiness_assessment.csv"
  ))
  if (nrow(readiness) != 1L || readiness$gate_status[[1L]] != "pass") {
    stop("Phase 153 launch is blocked because readiness is not pass.", call. = FALSE)
  }
  registry <- app_read_csv(file.path(readiness_dir, "candidate_registry.csv"))
  dgp_registry <- app_read_csv(file.path(readiness_dir, "fresh_dgp_registry.csv"))
  if (!app_joint_qdesn_phase153_fixture_is_current(fixture_dir, dgp_registry)) {
    stop("Phase 153 fixture directory is missing, stale, or hash-invalid.", call. = FALSE)
  }
  complete <- vapply(registry$candidate_id, function(id) {
    app_joint_qdesn_phase153_verify_candidate_dir(
      app_joint_qdesn_phase153_candidate_dir(out_dir, id)
    )
  }, logical(1L))
  registry_run <- if (isTRUE(incomplete_only)) {
    registry[!complete, , drop = FALSE]
  } else {
    registry
  }
  artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)
  if (nrow(registry_run)) {
    jobs <- split(registry_run, seq_len(nrow(registry_run)))
    results <- app_joint_qdesn_parallel_lapply(
      jobs,
      function(candidate) {
        result <- app_joint_qdesn_phase153_evaluate_candidate(
          artifacts,
          candidate
        )
        dir <- app_joint_qdesn_phase153_write_candidate(
          result,
          out_dir,
          candidate$candidate_id[[1L]]
        )
        list(
          candidate_id = candidate$candidate_id[[1L]],
          candidate_dir = dir
        )
      },
      n_cores = as.integer(n_cores)
    )
    failures <- app_joint_qdesn_worker_failure_rows(
      results,
      "phase153_balanced_independent_replication"
    )
  } else {
    failures <- app_joint_qdesn_worker_failure_rows(
      list(),
      "phase153_balanced_independent_replication"
    )
  }
  app_joint_qvp_write_csv(
    failures,
    file.path(out_dir, "worker_failures.csv")
  )
  complete_all <- vapply(registry$candidate_id, function(id) {
    app_joint_qdesn_phase153_verify_candidate_dir(
      app_joint_qdesn_phase153_candidate_dir(out_dir, id)
    )
  }, logical(1L))
  progress <- data.frame(
    expected_candidates = nrow(registry),
    completed_candidates = sum(complete_all),
    remaining_candidates = sum(!complete_all),
    worker_failures_this_invocation = nrow(failures),
    n_cores = as.integer(n_cores),
    status = if (all(complete_all) && !nrow(failures)) {
      "complete"
    } else {
      "incomplete"
    },
    stringsAsFactors = FALSE
  )
  app_joint_qvp_write_csv(
    progress,
    file.path(out_dir, "progress_summary.csv")
  )
  if (nrow(failures)) {
    stop(sprintf(
      "Phase 153 encountered %d worker failure(s).",
      nrow(failures)
    ), call. = FALSE)
  }
  if (!all(complete_all)) {
    stop(sprintf(
      "Phase 153 remains incomplete: %d/%d checkpoints are complete.",
      sum(complete_all),
      length(complete_all)
    ), call. = FALSE)
  }
  app_joint_qdesn_phase153_aggregate(
    out_dir = out_dir,
    readiness_dir = readiness_dir,
    bootstrap_replicates = bootstrap_replicates
  )
}

app_joint_qdesn_phase153_process_count <- function() {
  out <- tryCatch(
    suppressWarnings(system2(
      "ps",
      c("-eo", "pid=,args="),
      stdout = TRUE,
      stderr = FALSE
    )),
    error = function(e) character()
  )
  if (!length(out)) return(0L)
  is_phase153_runner <- grepl(
    paste0(
      "Rscript( --vanilla)? application/scripts/",
      "(178_prepare|179_run|180_audit)_joint_qdesn_phase153_"
    ),
    out
  ) | grepl(
    "bash application/cache/.*/run_phase153[.]sh",
    out
  )
  sum(is_phase153_runner)
}

app_joint_qdesn_phase153_session_alive <- function(
  session_name = "joint_qdesn_phase153_balanced_replication_20260729"
) {
  identical(
    suppressWarnings(system2(
      "tmux",
      c("has-session", "-t", session_name),
      stdout = FALSE,
      stderr = FALSE
    )),
    0L
  )
}

app_joint_qdesn_phase153_health <- function(
  readiness_dir = app_joint_qdesn_phase153_default_readiness_dir(),
  out_dir = app_joint_qdesn_phase153_default_vb_dir(),
  orchestration_dir = app_joint_qdesn_phase153_default_orchestration_dir(),
  session_name = "joint_qdesn_phase153_balanced_replication_20260729"
) {
  readiness_path <- file.path(readiness_dir, "readiness_assessment.csv")
  registry_path <- file.path(readiness_dir, "candidate_registry.csv")
  readiness_status <- if (file.exists(readiness_path)) {
    app_read_csv(readiness_path)$gate_status[[1L]]
  } else {
    "missing"
  }
  registry <- if (file.exists(registry_path)) {
    app_read_csv(registry_path)
  } else {
    data.frame(candidate_id = character())
  }
  complete <- if (nrow(registry)) {
    vapply(registry$candidate_id, function(id) {
      app_joint_qdesn_phase153_verify_candidate_dir(
        app_joint_qdesn_phase153_candidate_dir(out_dir, id)
      )
    }, logical(1L))
  } else {
    logical()
  }
  process_count <- app_joint_qdesn_phase153_process_count()
  session_alive <- app_joint_qdesn_phase153_session_alive(session_name)
  aggregate_complete <- file.exists(file.path(out_dir, "artifact_manifest.csv")) &&
    file.exists(file.path(out_dir, "replication_assessment.csv"))
  lifecycle <- if (aggregate_complete && length(complete) && all(complete)) {
    "complete"
  } else if (process_count > 0L || session_alive) {
    "running"
  } else if (!nrow(registry)) {
    "not_prepared"
  } else if (any(complete)) {
    "incomplete_not_running"
  } else {
    "prepared_not_running"
  }
  health <- data.frame(
    phase_id = "phase153_balanced_independent_replication",
    lifecycle_state = lifecycle,
    readiness_status = readiness_status,
    expected_candidates = nrow(registry),
    completed_candidates = sum(complete),
    remaining_candidates = nrow(registry) - sum(complete),
    completion_fraction = if (nrow(registry)) sum(complete) / nrow(registry) else 0,
    aggregate_complete = aggregate_complete,
    session_alive = session_alive,
    runner_process_count = process_count,
    recommendation = switch(
      lifecycle,
      complete = "audit_phase153_before_any_mcmc_or_article_change",
      running = "preserve_healthy_phase153_computation",
      incomplete_not_running = "resume_missing_phase153_checkpoints",
      prepared_not_running = "launch_full_phase153_campaign",
      "prepare_phase153_readiness"
    ),
    stringsAsFactors = FALSE
  )
  app_ensure_dir(orchestration_dir)
  app_joint_qvp_write_csv(
    health,
    file.path(orchestration_dir, "phase153_health_summary.csv")
  )
  health
}
