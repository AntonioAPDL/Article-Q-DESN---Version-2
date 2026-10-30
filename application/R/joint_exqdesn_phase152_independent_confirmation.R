# Phase152 independent confirmation of the Phase151 case-specific feature maps.
#
# The stage has two sequential decision layers. First, fresh DGP replicates and
# independent reservoir seeds test whether the two Phase151 gains generalize.
# Only designs that clear those paired VB gates are eligible for an eight-chain
# MCMC confirmation on the original frozen article fixture.

app_joint_exqdesn_phase152_default_readiness_dir <- function() {
  app_path("application/cache/joint_qdesn_phase152_independent_confirmation_readiness_20260729")
}

app_joint_exqdesn_phase152_default_fixture_dir <- function() {
  app_path("application/cache/joint_qdesn_phase152_independent_confirmation_fixtures_20260729")
}

app_joint_exqdesn_phase152_default_vb_dir <- function() {
  app_path("application/cache/joint_qdesn_phase152_independent_confirmation_vb_20260729")
}

app_joint_exqdesn_phase152_default_mcmc_dir <- function() {
  app_path("application/cache/joint_qdesn_phase152_independent_confirmation_mcmc_20260729")
}

app_joint_exqdesn_phase152_default_orchestration_dir <- function() {
  app_path("application/cache/joint_qdesn_phase152_independent_confirmation_20260729_orchestration")
}

app_joint_exqdesn_phase152_default_phase151_dir <- function() {
  app_joint_exqdesn_phase151_default_dir()
}

app_joint_exqdesn_phase152_default_phase151_readiness_dir <- function() {
  app_joint_exqdesn_phase151_default_readiness_dir()
}

app_joint_exqdesn_phase152_target_scenarios <- function() {
  c("gaussian_mixture_bridge", "nonlinear_reservoir_friendly")
}

app_joint_exqdesn_phase152_verify_manifest <- function(dir, source_id) {
  dir <- normalizePath(dir, mustWork = TRUE)
  path <- file.path(dir, "artifact_manifest.csv")
  if (!file.exists(path)) {
    return(data.frame(
      source_id = source_id, label = "artifact_manifest",
      relative_path = "artifact_manifest.csv", exists = FALSE,
      declared_sha256 = NA_character_, actual_sha256 = NA_character_,
      verified = FALSE, stringsAsFactors = FALSE
    ))
  }
  manifest <- app_read_csv(path)
  app_check_required_columns(
    manifest, c("label", "relative_path", "size_bytes", "sha256"),
    sprintf("%s manifest", source_id)
  )
  app_joint_qdesn_bind_rows(lapply(seq_len(nrow(manifest)), function(ii) {
    file <- file.path(dir, manifest$relative_path[[ii]])
    exists <- file.exists(file)
    actual_sha <- if (exists) app_sha256_file(file) else NA_character_
    actual_size <- if (exists) as.numeric(file.info(file)$size) else NA_real_
    data.frame(
      source_id = source_id,
      label = manifest$label[[ii]],
      relative_path = manifest$relative_path[[ii]],
      exists = exists,
      declared_sha256 = manifest$sha256[[ii]],
      actual_sha256 = actual_sha,
      verified = exists &&
        identical(actual_size, as.numeric(manifest$size_bytes[[ii]])) &&
        identical(tolower(actual_sha), tolower(manifest$sha256[[ii]])),
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase152_load_phase151_freeze <- function(
  phase151_dir = app_joint_exqdesn_phase152_default_phase151_dir(),
  phase151_readiness_dir = app_joint_exqdesn_phase152_default_phase151_readiness_dir()
) {
  required_result <- c(
    "mcmc_confirmation_plan.csv", "candidate_ranking.csv",
    "phase151_result_assessment.csv", "artifact_manifest.csv"
  )
  required_readiness <- c(
    "phase151_candidate_registry.csv", "phase151_readiness_assessment.csv",
    "artifact_manifest.csv"
  )
  missing <- c(
    file.path(phase151_dir, required_result[
      !file.exists(file.path(phase151_dir, required_result))
    ]),
    file.path(phase151_readiness_dir, required_readiness[
      !file.exists(file.path(phase151_readiness_dir, required_readiness))
    ])
  )
  if (length(missing)) {
    stop("Phase152 source files are missing: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  source_manifest <- app_joint_qdesn_bind_rows(list(
    app_joint_exqdesn_phase152_verify_manifest(phase151_dir, "phase151_result"),
    app_joint_exqdesn_phase152_verify_manifest(
      phase151_readiness_dir, "phase151_readiness"
    )
  ))
  plan <- app_read_csv(file.path(phase151_dir, "mcmc_confirmation_plan.csv"))
  ranking <- app_read_csv(file.path(phase151_dir, "candidate_ranking.csv"))
  registry <- app_read_csv(file.path(
    phase151_readiness_dir, "phase151_candidate_registry.csv"
  ))
  assessment <- app_read_csv(file.path(
    phase151_dir, "phase151_result_assessment.csv"
  ))
  readiness <- app_read_csv(file.path(
    phase151_readiness_dir, "phase151_readiness_assessment.csv"
  ))
  app_check_required_columns(
    plan,
    c("scenario_id", "candidate_id", "design_role", "design_class"),
    "Phase151 MCMC plan"
  )
  expected <- app_joint_exqdesn_phase152_target_scenarios()
  if (!setequal(plan$scenario_id, expected) || nrow(plan) != length(expected)) {
    stop("Phase152 requires exactly the two frozen Phase151 feature-map winners.", call. = FALSE)
  }
  selected <- registry[match(plan$candidate_id, registry$candidate_id), , drop = FALSE]
  direct <- registry[
    registry$scenario_id %in% expected &
      registry$design_role == "direct_phase150_parity",
    ,
    drop = FALSE
  ]
  direct <- direct[match(expected, direct$scenario_id), , drop = FALSE]
  if (any(is.na(selected$candidate_id)) || nrow(direct) != length(expected)) {
    stop("Phase152 could not freeze the selected and direct Phase151 rows.", call. = FALSE)
  }
  selected$phase152_role <- "selected_feature_map"
  direct$phase152_role <- "direct_parity"
  frozen <- rbind(selected, direct)
  frozen$source_phase151_candidate_id <- frozen$candidate_id
  nested <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(selected)), function(ii) {
    candidate_dir <- app_joint_exqdesn_phase151_candidate_dir(
      phase151_dir, selected$candidate_id[[ii]]
    )
    app_joint_exqdesn_phase152_verify_manifest(
      candidate_dir,
      paste0("phase151_candidate_", selected$scenario_id[[ii]])
    )
  }))
  source_manifest <- app_joint_qdesn_bind_rows(list(source_manifest, nested))
  if (any(!source_manifest$verified) ||
      assessment$gate_status[[1L]] == "fail" ||
      readiness$gate_status[[1L]] == "fail") {
    stop("Phase151 source verification failed; Phase152 preparation is blocked.", call. = FALSE)
  }
  list(
    frozen = frozen,
    selected = selected,
    direct = direct,
    plan = plan,
    ranking = ranking,
    source_manifest = source_manifest
  )
}

app_joint_exqdesn_phase152_build_dgp_registry <- function(
  base_registry,
  n_dgp_replicates = 10L,
  seed_base = 202607290L
) {
  scenarios <- app_joint_exqdesn_phase152_target_scenarios()
  base <- base_registry[match(scenarios, base_registry$scenario_id), , drop = FALSE]
  if (any(is.na(base$scenario_id))) {
    stop("The formal registry is missing a Phase152 target scenario.", call. = FALSE)
  }
  rows <- list()
  for (ss in seq_along(scenarios)) {
    for (rr in seq_len(as.integer(n_dgp_replicates))) {
      x <- base[ss, , drop = FALSE]
      x$base_scenario_id <- scenarios[[ss]]
      x$dgp_replicate_id <- sprintf("r%02d", rr)
      x$base_seed <- as.integer(base$seed[[ss]])
      x$seed <- as.integer(seed_base + ss * 1000L + rr)
      x$seed_role <- "phase152_independent_dgp_innovation"
      x$scenario_id <- paste0(
        scenarios[[ss]], "__phase152_dgp_", x$dgp_replicate_id
      )
      x$registry_version <- "joint_exqdesn_phase152_independent_confirmation_20260729"
      x$notes <- paste(
        base$notes[[ss]],
        "Independent Phase152 confirmation replicate; no Phase151 observation is reused."
      )
      rows[[length(rows) + 1L]] <- x
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  rownames(out) <- NULL
  app_joint_qdesn_validate_simulation_registry(out)
  if (anyDuplicated(out$seed) || anyDuplicated(out$scenario_id)) {
    stop("Phase152 DGP seeds and scenario ids must be unique.", call. = FALSE)
  }
  out
}

app_joint_exqdesn_phase152_build_vb_registry <- function(
  frozen,
  dgp_registry,
  n_reservoir_replicates = 3L,
  reservoir_seed_base = 202607500L
) {
  scenarios <- app_joint_exqdesn_phase152_target_scenarios()
  rows <- list()
  for (ss in seq_along(scenarios)) {
    base_id <- scenarios[[ss]]
    selected <- frozen[
      frozen$scenario_id == base_id &
        frozen$phase152_role == "selected_feature_map",
      ,
      drop = FALSE
    ]
    direct <- frozen[
      frozen$scenario_id == base_id & frozen$phase152_role == "direct_parity",
      ,
      drop = FALSE
    ]
    reps <- dgp_registry[dgp_registry$base_scenario_id == base_id, , drop = FALSE]
    if (nrow(selected) != 1L || nrow(direct) != 1L || !nrow(reps)) {
      stop(sprintf("Malformed Phase152 freeze for '%s'.", base_id), call. = FALSE)
    }
    for (rr in seq_len(nrow(reps))) {
      direct_row <- direct
      direct_row$scenario_id <- reps$scenario_id[[rr]]
      direct_row$case_id <- paste0(reps$scenario_id[[rr]], "__direct")
      direct_row$source_phase151_candidate_id <- direct$candidate_id[[1L]]
      direct_row$candidate_id <- paste0(
        reps$scenario_id[[rr]], "__phase152__direct"
      )
      direct_row$design_role <- "direct_confirmation"
      direct_row$design_purpose <- "paired direct-feature control on a fresh DGP replicate"
      direct_row$base_scenario_id <- base_id
      direct_row$dgp_replicate_id <- reps$dgp_replicate_id[[rr]]
      direct_row$dgp_seed <- as.integer(reps$seed[[rr]])
      direct_row$reservoir_replicate_id <- "none"
      direct_row$reservoir_seed <- NA_integer_
      direct_row$confirmation_role <- "direct_control"
      rows[[length(rows) + 1L]] <- direct_row

      for (kk in seq_len(as.integer(n_reservoir_replicates))) {
        candidate <- selected
        candidate$scenario_id <- reps$scenario_id[[rr]]
        candidate$case_id <- paste0(reps$scenario_id[[rr]], "__selected")
        candidate$source_phase151_candidate_id <- selected$candidate_id[[1L]]
        candidate$reservoir_replicate_id <- sprintf("r%02d", kk)
        candidate$reservoir_seed <- as.integer(
          reservoir_seed_base + ss * 10000L + rr * 100L + kk
        )
        candidate$candidate_id <- paste0(
          reps$scenario_id[[rr]], "__phase152__",
          selected$design_role[[1L]], "__reservoir_", candidate$reservoir_replicate_id
        )
        candidate$base_scenario_id <- base_id
        candidate$dgp_replicate_id <- reps$dgp_replicate_id[[rr]]
        candidate$dgp_seed <- as.integer(reps$seed[[rr]])
        candidate$confirmation_role <- "selected_feature_map"
        candidate$design_purpose <- paste(
          "frozen Phase151 feature-map geometry with an independent reservoir seed"
        )
        rows[[length(rows) + 1L]] <- candidate
      }
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  rownames(out) <- NULL
  expected <- nrow(dgp_registry) * (1L + as.integer(n_reservoir_replicates))
  if (nrow(out) != expected || anyDuplicated(out$candidate_id)) {
    stop("Phase152 VB registry does not have the expected unique candidate rows.", call. = FALSE)
  }
  reservoir_seeds <- out$reservoir_seed[out$confirmation_role == "selected_feature_map"]
  if (anyDuplicated(reservoir_seeds)) {
    stop("Phase152 reservoir seeds must be unique across confirmation rows.", call. = FALSE)
  }
  out
}

app_joint_exqdesn_phase152_chain_seed_plan <- function(
  frozen,
  n_chains = 8L,
  seed_base = 202607900L,
  chain_seed_stride = 1009L
) {
  selected <- frozen[frozen$phase152_role == "selected_feature_map", , drop = FALSE]
  rows <- lapply(seq_len(nrow(selected)), function(ii) {
    data.frame(
      base_scenario_id = selected$scenario_id[[ii]],
      source_phase151_candidate_id = selected$candidate_id[[ii]],
      chain_id = seq_len(as.integer(n_chains)),
      chain_seed = as.integer(
        seed_base + ii * 100000L +
          (seq_len(as.integer(n_chains)) - 1L) * as.integer(chain_seed_stride)
      ),
      seed_role = "phase152_mcmc_chain",
      stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  if (anyDuplicated(out$chain_seed)) stop("Phase152 MCMC chain seeds are not unique.", call. = FALSE)
  out
}

app_joint_exqdesn_phase152_dimension_audit <- function() {
  data.frame(
    prior_stage = c(
      "Phases128-132", "Phase133B", "Phases134-143", "Phases144-150", "Phase151"
    ),
    dimension = c(
      "gamma update widths, stepping, chain length, thinning, and chain count",
      "posterior mean, median, and trimmed quantile summaries",
      "RHS/readout controls and alternative gamma kernels or priors",
      "root-cause, target-invariance, case-specific VB, and eight-chain MCMC",
      "case-specific deterministic reservoir feature maps"
    ),
    phase152_action = c(
      rep("hold fixed; do not rescreen", 4L),
      "freeze two selected maps and test independent DGP/reservoir seeds"
    ),
    repeated = FALSE,
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase152_fixture_is_current <- function(fixture_dir, dgp_registry) {
  if (!file.exists(file.path(fixture_dir, "artifact_manifest.csv")) ||
      !file.exists(file.path(fixture_dir, "frozen_registry.csv"))) return(FALSE)
  ok <- tryCatch({
    verification <- app_joint_qdesn_verify_artifact_manifest(fixture_dir)
    frozen <- app_read_csv(file.path(fixture_dir, "frozen_registry.csv"))
    all(verification$status == "pass") &&
      identical(as.character(frozen$scenario_id), as.character(dgp_registry$scenario_id)) &&
      identical(as.integer(frozen$seed), as.integer(dgp_registry$seed))
  }, error = function(e) FALSE)
  isTRUE(ok)
}

app_joint_exqdesn_run_phase152_readiness <- function(
  out_dir = app_joint_exqdesn_phase152_default_readiness_dir(),
  fixture_dir = app_joint_exqdesn_phase152_default_fixture_dir(),
  phase151_dir = app_joint_exqdesn_phase152_default_phase151_dir(),
  phase151_readiness_dir = app_joint_exqdesn_phase152_default_phase151_readiness_dir(),
  base_registry_path = app_joint_qdesn_default_simulation_registry_path(),
  n_dgp_replicates = 10L,
  n_reservoir_replicates = 3L,
  n_chains = 8L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  fixture_dir <- normalizePath(fixture_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  source <- app_joint_exqdesn_phase152_load_phase151_freeze(
    phase151_dir, phase151_readiness_dir
  )
  base_registry <- app_joint_qdesn_load_simulation_registry(base_registry_path)
  dgp_registry <- app_joint_exqdesn_phase152_build_dgp_registry(
    base_registry, n_dgp_replicates
  )
  vb_registry <- app_joint_exqdesn_phase152_build_vb_registry(
    source$frozen, dgp_registry, n_reservoir_replicates
  )
  chain_plan <- app_joint_exqdesn_phase152_chain_seed_plan(
    source$frozen, n_chains
  )

  if (!app_joint_exqdesn_phase152_fixture_is_current(fixture_dir, dgp_registry)) {
    if (dir.exists(fixture_dir) && length(list.files(fixture_dir, all.files = TRUE)) > 2L) {
      quarantine <- paste0(
        fixture_dir, ".invalid.", format(Sys.time(), "%Y%m%d%H%M%S")
      )
      if (!file.rename(fixture_dir, quarantine)) {
        stop("Could not quarantine a stale Phase152 fixture directory.", call. = FALSE)
      }
    }
    app_joint_qdesn_materialize_simulation_fixtures(
      out_dir = fixture_dir,
      registry_path = base_registry_path,
      registry = dgp_registry
    )
  }
  fixture_verification <- app_joint_qdesn_verify_artifact_manifest(fixture_dir)
  source_manifest <- app_joint_qdesn_bind_rows(list(
    source$source_manifest,
    data.frame(
      source_id = "phase152_fresh_fixtures",
      label = fixture_verification$label,
      relative_path = fixture_verification$relative_path,
      exists = fixture_verification$exists,
      declared_sha256 = fixture_verification$declared_sha256,
      actual_sha256 = fixture_verification$actual_sha256,
      verified = fixture_verification$status == "pass",
      stringsAsFactors = FALSE
    )
  ))
  geometry_ok <- all(dgp_registry$simulated_length == 12000L) &&
    all(dgp_registry$dgp_warmup_length == 2000L) &&
    all(dgp_registry$desn_washout_length == 500L) &&
    all(dgp_registry$fit_length == 500L) &&
    all(dgp_registry$validation_length == 1000L) &&
    all(dgp_registry$forecast_origin_stride == 30L) &&
    all(dgp_registry$max_lead == 30L)
  expected_vb <- length(app_joint_exqdesn_phase152_target_scenarios()) *
    as.integer(n_dgp_replicates) * (1L + as.integer(n_reservoir_replicates))
  hard_fail <- any(!source_manifest$verified) || !geometry_ok ||
    nrow(dgp_registry) != 2L * as.integer(n_dgp_replicates) ||
    nrow(vb_registry) != expected_vb ||
    anyDuplicated(dgp_registry$seed) || anyDuplicated(vb_registry$candidate_id)
  assessment <- data.frame(
    audit_id = "phase152_independent_confirmation_readiness",
    gate_status = if (hard_fail) "fail" else "pass",
    target_scenarios = length(unique(dgp_registry$base_scenario_id)),
    dgp_replicates_per_scenario = as.integer(n_dgp_replicates),
    reservoir_replicates_per_dgp = as.integer(n_reservoir_replicates),
    fresh_fixture_rows = nrow(dgp_registry),
    vb_jobs_expected = expected_vb,
    mcmc_chains_per_survivor = as.integer(n_chains),
    source_hash_failures = sum(!source_manifest$verified),
    formal_geometry_verified = geometry_ok,
    recommendation = if (hard_fail) {
      "fix_phase152_readiness_before_launch"
    } else {
      "launch_paired_vb_confirmation_then_conditionally_run_mcmc"
    },
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase152 Independent Confirmation",
    "",
    "This readiness packet freezes the two Phase151 feature maps without retuning them.",
    "The VB layer uses ten fresh DGP replicates per scenario, one paired direct control,",
    "and three independent reservoir seeds per DGP replicate. The original Phase151",
    "window is excluded from promotion gates. MCMC is conditional on those gates.",
    "",
    sprintf("- Gate: `%s`", assessment$gate_status[[1L]]),
    sprintf("- Fresh DGP fixtures: %d", nrow(dgp_registry)),
    sprintf("- Planned VB jobs: %d", nrow(vb_registry)),
    sprintf("- Planned MCMC chains per survivor: %d", n_chains)
  ), readme_path, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(data.frame(
      run_id = "joint_exqdesn_phase152_independent_confirmation",
      phase151_dir = app_prefer_repo_relative_path(phase151_dir),
      phase151_readiness_dir = app_prefer_repo_relative_path(phase151_readiness_dir),
      fixture_dir = app_prefer_repo_relative_path(fixture_dir),
      base_registry_path = app_prefer_repo_relative_path(base_registry_path),
      independent_confirmation_only = TRUE,
      article_assets_modified = FALSE,
      stringsAsFactors = FALSE
    ), file.path(out_dir, "run_config.csv")),
    source_manifest_verification = app_joint_qvp_write_csv(
      source_manifest, file.path(out_dir, "phase152_source_manifest_verification.csv")
    ),
    frozen_phase151_candidates = app_joint_qvp_write_csv(
      source$frozen, file.path(out_dir, "phase152_frozen_phase151_candidates.csv")
    ),
    fresh_dgp_registry = app_joint_qvp_write_csv(
      dgp_registry, file.path(out_dir, "phase152_fresh_dgp_registry.csv")
    ),
    vb_candidate_registry = app_joint_qvp_write_csv(
      vb_registry, file.path(out_dir, "phase152_vb_candidate_registry.csv")
    ),
    mcmc_chain_seed_plan = app_joint_qvp_write_csv(
      chain_plan, file.path(out_dir, "phase152_mcmc_chain_seed_plan.csv")
    ),
    exhausted_dimension_audit = app_joint_qvp_write_csv(
      app_joint_exqdesn_phase152_dimension_audit(),
      file.path(out_dir, "phase152_exhausted_dimension_audit.csv")
    ),
    readiness_assessment = app_joint_qvp_write_csv(
      assessment, file.path(out_dir, "phase152_readiness_assessment.csv")
    ),
    provenance = app_joint_qvp_write_csv(
      app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")
    ),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = out_dir,
    fixture_dir = fixture_dir,
    assessment = assessment,
    dgp_registry = dgp_registry,
    vb_registry = vb_registry,
    chain_plan = chain_plan,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}

app_joint_exqdesn_phase152_annotate_result <- function(result, candidate) {
  extra <- candidate[, c(
    "base_scenario_id", "dgp_replicate_id", "dgp_seed",
    "reservoir_replicate_id", "confirmation_role",
    "source_phase151_candidate_id"
  ), drop = FALSE]
  for (name in names(result)) {
    if (!is.data.frame(result[[name]]) || !nrow(result[[name]])) next
    add <- extra[rep(1L, nrow(result[[name]])), , drop = FALSE]
    add <- add[, setdiff(names(add), names(result[[name]])), drop = FALSE]
    result[[name]] <- cbind(result[[name]], add, stringsAsFactors = FALSE)
  }
  result
}

app_joint_exqdesn_phase152_candidate_dir <- function(out_dir, candidate_id) {
  file.path(out_dir, "candidates", candidate_id)
}

app_joint_exqdesn_phase152_verify_candidate_dir <- function(candidate_dir) {
  app_joint_exqdesn_phase151_verify_candidate_dir(candidate_dir)
}

app_joint_exqdesn_phase152_write_candidate <- function(result, out_dir, candidate_id) {
  final_dir <- app_joint_exqdesn_phase152_candidate_dir(out_dir, candidate_id)
  app_ensure_dir(dirname(final_dir))
  if (app_joint_exqdesn_phase152_verify_candidate_dir(final_dir)) return(final_dir)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".invalid.", format(Sys.time(), "%Y%m%d%H%M%S"))
    if (!file.rename(final_dir, quarantine)) {
      stop("Could not quarantine an invalid Phase152 candidate checkpoint.", call. = FALSE)
    }
  }
  tmp_dir <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp_dir)) unlink(tmp_dir, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp_dir)
  readme <- file.path(tmp_dir, "README.md")
  writeLines(c(
    "# Phase152 VB Candidate Checkpoint",
    "",
    sprintf("- Candidate: `%s`", candidate_id),
    sprintf("- Scenario: `%s`", result$candidate_summary$base_scenario_id[[1L]]),
    sprintf("- DGP replicate: `%s`", result$candidate_summary$dgp_replicate_id[[1L]]),
    sprintf("- Confirmation role: `%s`", result$candidate_summary$confirmation_role[[1L]]),
    "",
    "This resumable checkpoint stores summaries only; no fitted VB object is retained."
  ), readme, useBytes = TRUE)
  paths <- c(
    candidate_summary = app_joint_qvp_write_csv(
      result$candidate_summary, file.path(tmp_dir, "candidate_summary.csv")
    ),
    tau_summary = app_joint_qvp_write_csv(
      result$tau_summary, file.path(tmp_dir, "tau_summary.csv")
    ),
    interval_summary = app_joint_qvp_write_csv(
      result$interval_summary, file.path(tmp_dir, "interval_summary.csv")
    ),
    design_diagnostics = app_joint_qvp_write_csv(
      result$design_diagnostics, file.path(tmp_dir, "design_diagnostics.csv")
    ),
    vb_diagnostics = app_joint_qvp_write_csv(
      result$vb_diagnostics, file.path(tmp_dir, "vb_diagnostics.csv")
    ),
    readme = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  app_joint_qvp_write_csv(manifest, file.path(tmp_dir, "artifact_manifest.csv"))
  if (!file.rename(tmp_dir, final_dir) ||
      !app_joint_exqdesn_phase152_verify_candidate_dir(final_dir)) {
    stop(sprintf("Could not promote Phase152 checkpoint '%s'.", candidate_id), call. = FALSE)
  }
  final_dir
}

app_joint_exqdesn_phase152_load_completed <- function(out_dir, registry) {
  rows <- lapply(seq_len(nrow(registry)), function(ii) {
    dir <- app_joint_exqdesn_phase152_candidate_dir(
      out_dir, registry$candidate_id[[ii]]
    )
    if (!app_joint_exqdesn_phase152_verify_candidate_dir(dir)) return(NULL)
    list(
      candidate_summary = app_read_csv(file.path(dir, "candidate_summary.csv")),
      tau_summary = app_read_csv(file.path(dir, "tau_summary.csv")),
      interval_summary = app_read_csv(file.path(dir, "interval_summary.csv")),
      design_diagnostics = app_read_csv(file.path(dir, "design_diagnostics.csv")),
      vb_diagnostics = app_read_csv(file.path(dir, "vb_diagnostics.csv"))
    )
  })
  rows[!vapply(rows, is.null, logical(1L))]
}

app_joint_exqdesn_phase152_metric_names <- function() {
  c(
    "fit_truth_mae", "fit_truth_rmse", "fit_check_loss_mean",
    "fit_crps_grid_mean", "fit_max_abs_hit_rate_error",
    "forecast_truth_mae", "forecast_truth_rmse",
    "forecast_check_loss_mean", "forecast_crps_grid_mean",
    "forecast_max_abs_hit_rate_error"
  )
}

app_joint_exqdesn_phase152_paired_rows <- function(candidate_summary) {
  metrics <- app_joint_exqdesn_phase152_metric_names()
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
    direct <- block[block$confirmation_role == "direct_control", , drop = FALSE]
    selected <- block[
      block$confirmation_role == "selected_feature_map", ,
      drop = FALSE
    ]
    if (nrow(direct) != 1L || !nrow(selected)) {
      stop("Every Phase152 DGP replicate requires one direct and at least one selected row.", call. = FALSE)
    }
    out <- data.frame(
      base_scenario_id = block$base_scenario_id[[1L]],
      dgp_replicate_id = block$dgp_replicate_id[[1L]],
      dgp_seed = as.integer(block$dgp_seed[[1L]]),
      direct_candidate_id = direct$candidate_id[[1L]],
      reservoir_replicates = nrow(selected),
      reservoir_forecast_mae_min = min(selected$forecast_truth_mae),
      reservoir_forecast_mae_max = max(selected$forecast_truth_mae),
      reservoir_forecast_mae_sd = stats::sd(selected$forecast_truth_mae),
      stringsAsFactors = FALSE
    )
    for (metric in metrics) {
      direct_value <- as.numeric(direct[[metric]][[1L]])
      selected_value <- stats::median(as.numeric(selected[[metric]]))
      out[[paste0("direct_", metric)]] <- direct_value
      out[[paste0("selected_median_", metric)]] <- selected_value
      out[[paste0("gain_", metric)]] <- direct_value - selected_value
      out[[paste0("ratio_", metric)]] <- selected_value / direct_value
    }
    out$selected_forecast_mae_win <- out$gain_forecast_truth_mae > 0
    out
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase152_seed_comparison <- function(candidate_summary) {
  metrics <- app_joint_exqdesn_phase152_metric_names()
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
    direct <- block[block$confirmation_role == "direct_control", , drop = FALSE]
    selected <- block[
      block$confirmation_role == "selected_feature_map", ,
      drop = FALSE
    ]
    out <- selected[, c(
      "candidate_id", "base_scenario_id", "dgp_replicate_id", "dgp_seed",
      "reservoir_replicate_id", "reservoir_seed"
    ), drop = FALSE]
    for (metric in metrics) {
      out[[paste0("direct_", metric)]] <- direct[[metric]][[1L]]
      out[[paste0("selected_", metric)]] <- selected[[metric]]
      out[[paste0("gain_", metric)]] <- direct[[metric]][[1L]] - selected[[metric]]
      out[[paste0("ratio_", metric)]] <- selected[[metric]] / direct[[metric]][[1L]]
    }
    out$forecast_mae_win <- out$gain_forecast_truth_mae > 0
    out
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase152_tau_paired_rows <- function(tau_summary) {
  forecast <- tau_summary[tau_summary$validation_window == "forecast", , drop = FALSE]
  groups <- split(
    forecast,
    interaction(
      forecast$base_scenario_id, forecast$dgp_replicate_id, forecast$tau,
      drop = TRUE, lex.order = TRUE
    )
  )
  rows <- lapply(groups, function(block) {
    direct <- block[block$confirmation_role == "direct_control", , drop = FALSE]
    selected <- block[
      block$confirmation_role == "selected_feature_map", ,
      drop = FALSE
    ]
    data.frame(
      base_scenario_id = block$base_scenario_id[[1L]],
      dgp_replicate_id = block$dgp_replicate_id[[1L]],
      dgp_seed = as.integer(block$dgp_seed[[1L]]),
      tau = block$tau[[1L]],
      direct_truth_mae = direct$truth_mae[[1L]],
      selected_median_truth_mae = stats::median(selected$truth_mae),
      gain_truth_mae = direct$truth_mae[[1L]] - stats::median(selected$truth_mae),
      ratio_truth_mae = stats::median(selected$truth_mae) / direct$truth_mae[[1L]],
      direct_check_loss = direct$check_loss_mean[[1L]],
      selected_median_check_loss = stats::median(selected$check_loss_mean),
      direct_hit_error = direct$abs_hit_rate_error[[1L]],
      selected_median_hit_error = stats::median(selected$abs_hit_rate_error),
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase152_promotion_decision <- function(
  candidate_summary,
  paired,
  seed_comparison,
  tau_paired,
  min_dgp_wins = 8L,
  min_relative_gain = 0.02,
  min_absolute_gain = 0.0025,
  max_fit_ratio = 1.05,
  max_score_ratio = 1.02,
  min_seed_win_fraction = 0.70,
  min_tau_nonworse = 5L
) {
  scenarios <- sort(unique(paired$base_scenario_id))
  rows <- lapply(scenarios, function(scenario_id) {
    block <- paired[paired$base_scenario_id == scenario_id, , drop = FALSE]
    seeds <- seed_comparison[
      seed_comparison$base_scenario_id == scenario_id, , drop = FALSE
    ]
    tau_block <- tau_paired[tau_paired$base_scenario_id == scenario_id, , drop = FALSE]
    tau_agg <- app_joint_qdesn_bind_rows(lapply(split(tau_block, tau_block$tau), function(x) {
      data.frame(
        tau = x$tau[[1L]],
        direct_truth_mae = stats::median(x$direct_truth_mae),
        selected_truth_mae = stats::median(x$selected_median_truth_mae),
        stringsAsFactors = FALSE
      )
    }))
    tau_deterioration <- tau_agg$selected_truth_mae - tau_agg$direct_truth_mae
    tau_limit <- pmax(0.01, 0.10 * tau_agg$direct_truth_mae)
    implementation <- candidate_summary[
      candidate_summary$base_scenario_id == scenario_id, , drop = FALSE
    ]
    implementation_failures <- sum(implementation$implementation_status == "fail")
    contract_crossings <- sum(
      implementation$fit_contract_crossing_pairs,
      implementation$forecast_contract_crossing_pairs
    )
    dgp_wins <- sum(block$selected_forecast_mae_win)
    median_direct <- stats::median(block$direct_forecast_truth_mae)
    median_selected <- stats::median(block$selected_median_forecast_truth_mae)
    median_gain <- median_direct - median_selected
    relative_gain <- median_gain / median_direct
    fit_ratio <- stats::median(block$ratio_fit_truth_mae)
    check_ratio <- stats::median(block$ratio_forecast_check_loss_mean)
    crps_ratio <- stats::median(block$ratio_forecast_crps_grid_mean)
    seed_win_fraction <- mean(seeds$forecast_mae_win)
    tau_nonworse <- sum(tau_agg$selected_truth_mae <= tau_agg$direct_truth_mae)
    tau_violation_count <- sum(tau_deterioration > tau_limit)
    hard_fail <- implementation_failures > 0L || contract_crossings > 0L ||
      !all(is.finite(c(
        median_direct, median_selected, median_gain, relative_gain,
        fit_ratio, check_ratio, crps_ratio, seed_win_fraction
      )))
    statistical_pass <- !hard_fail &&
      dgp_wins >= as.integer(min_dgp_wins) &&
      median_gain >= max(min_absolute_gain, min_relative_gain * median_direct) &&
      fit_ratio <= max_fit_ratio &&
      check_ratio <= max_score_ratio &&
      crps_ratio <= max_score_ratio &&
      seed_win_fraction >= min_seed_win_fraction &&
      tau_nonworse >= as.integer(min_tau_nonworse) &&
      tau_violation_count == 0L
    reasons <- c(
      if (implementation_failures > 0L) "one or more VB candidate implementation gates failed",
      if (contract_crossings > 0L) "contract quantiles crossed",
      if (!hard_fail && dgp_wins < min_dgp_wins) "fewer than eight of ten DGP medians improved forecast MAE",
      if (!hard_fail && median_gain < max(min_absolute_gain, min_relative_gain * median_direct)) "median forecast MAE gain was not material",
      if (!hard_fail && fit_ratio > max_fit_ratio) "fit-window MAE guard exceeded 1.05",
      if (!hard_fail && check_ratio > max_score_ratio) "forecast check-loss guard exceeded 1.02",
      if (!hard_fail && crps_ratio > max_score_ratio) "forecast grid-CRPS guard exceeded 1.02",
      if (!hard_fail && seed_win_fraction < min_seed_win_fraction) "fewer than 70 percent of reservoir-seed comparisons improved forecast MAE",
      if (!hard_fail && tau_nonworse < min_tau_nonworse) "fewer than five of seven tau levels were nonworse",
      if (!hard_fail && tau_violation_count > 0L) "at least one tau level deteriorated beyond its guard"
    )
    data.frame(
      base_scenario_id = scenario_id,
      implementation_status = if (hard_fail) "fail" else "pass",
      promotion_status = if (hard_fail) {
        "blocked_integrity_failure"
      } else if (statistical_pass) {
        "promote_to_mcmc"
      } else {
        "reject_after_independent_confirmation"
      },
      dgp_replicates = nrow(block),
      dgp_forecast_mae_wins = dgp_wins,
      reservoir_seed_comparisons = nrow(seeds),
      reservoir_seed_win_fraction = seed_win_fraction,
      median_direct_forecast_truth_mae = median_direct,
      median_selected_forecast_truth_mae = median_selected,
      median_absolute_forecast_mae_gain = median_gain,
      median_relative_forecast_mae_gain = relative_gain,
      median_fit_mae_ratio = fit_ratio,
      median_forecast_check_loss_ratio = check_ratio,
      median_forecast_crps_ratio = crps_ratio,
      tau_levels_nonworse = tau_nonworse,
      tau_guard_violations = tau_violation_count,
      vb_max_iteration_fraction = mean(implementation$vb_reached_max_iter),
      implementation_failures = implementation_failures,
      contract_crossing_pairs = contract_crossings,
      decision_reason = if (length(reasons)) paste(reasons, collapse = "; ") else {
        "all independent confirmation promotion gates passed"
      },
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase152_candidate_manifest_rows <- function(out_dir, registry) {
  rows <- lapply(seq_len(nrow(registry)), function(ii) {
    id <- registry$candidate_id[[ii]]
    dir <- app_joint_exqdesn_phase152_candidate_dir(out_dir, id)
    data.frame(
      candidate_id = id,
      base_scenario_id = registry$base_scenario_id[[ii]],
      dgp_replicate_id = registry$dgp_replicate_id[[ii]],
      confirmation_role = registry$confirmation_role[[ii]],
      checkpoint_dir = app_prefer_repo_relative_path(dir),
      status = if (app_joint_exqdesn_phase152_verify_candidate_dir(dir)) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase152_aggregate_vb <- function(
  out_dir,
  readiness_dir = app_joint_exqdesn_phase152_default_readiness_dir()
) {
  registry <- app_read_csv(file.path(
    readiness_dir, "phase152_vb_candidate_registry.csv"
  ))
  completed <- app_joint_exqdesn_phase152_load_completed(out_dir, registry)
  if (!length(completed)) stop("No complete Phase152 VB checkpoints are available.", call. = FALSE)
  candidate_summary <- app_joint_qdesn_bind_rows(lapply(completed, `[[`, "candidate_summary"))
  tau_summary <- app_joint_qdesn_bind_rows(lapply(completed, `[[`, "tau_summary"))
  interval_summary <- app_joint_qdesn_bind_rows(lapply(completed, `[[`, "interval_summary"))
  design_diagnostics <- app_joint_qdesn_bind_rows(lapply(completed, `[[`, "design_diagnostics"))
  vb_diagnostics <- app_joint_qdesn_bind_rows(lapply(completed, `[[`, "vb_diagnostics"))
  paired <- app_joint_exqdesn_phase152_paired_rows(candidate_summary)
  seed_comparison <- app_joint_exqdesn_phase152_seed_comparison(candidate_summary)
  tau_paired <- app_joint_exqdesn_phase152_tau_paired_rows(tau_summary)
  decision <- app_joint_exqdesn_phase152_promotion_decision(
    candidate_summary, paired, seed_comparison, tau_paired
  )
  candidate_manifest <- app_joint_exqdesn_phase152_candidate_manifest_rows(
    out_dir, registry
  )
  source_manifest <- app_read_csv(file.path(
    readiness_dir, "phase152_source_manifest_verification.csv"
  ))
  source_manifest <- app_joint_qdesn_bind_rows(list(
    source_manifest,
    app_joint_exqdesn_phase152_verify_manifest(
      readiness_dir, "phase152_readiness_packet"
    )
  ))
  expected <- nrow(registry)
  hard_fail <- nrow(candidate_summary) != expected ||
    any(candidate_manifest$status != "pass") ||
    any(!source_manifest$verified) ||
    any(decision$implementation_status == "fail")
  survivors <- decision$base_scenario_id[
    decision$promotion_status == "promote_to_mcmc"
  ]
  assessment <- data.frame(
    audit_id = "phase152_independent_vb_confirmation",
    gate_status = if (hard_fail) "fail" else "pass",
    expected_candidates = expected,
    completed_candidates = nrow(candidate_summary),
    remaining_candidates = expected - nrow(candidate_summary),
    worker_failures = if (file.exists(file.path(out_dir, "worker_failures.csv"))) {
      nrow(app_read_csv(file.path(out_dir, "worker_failures.csv")))
    } else 0L,
    source_hash_failures = sum(!source_manifest$verified),
    candidate_manifest_failures = sum(candidate_manifest$status != "pass"),
    scenarios_evaluated = nrow(decision),
    scenarios_promoted_to_mcmc = length(survivors),
    promoted_scenario_ids = paste(survivors, collapse = ","),
    article_assets_modified = FALSE,
    recommendation = if (hard_fail) {
      "fix_phase152_vb_integrity_before_interpretation"
    } else if (length(survivors)) {
      "run_eight_chain_mcmc_only_for_independent_confirmation_survivors"
    } else {
      "stop_feature_map_promotion_and_retain_phase150_article_rows"
    },
    stringsAsFactors = FALSE
  )
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase152 Independent VB Confirmation",
    "",
    "This packet evaluates the frozen Phase151 feature maps on fresh DGP replicates",
    "and independent reservoir seeds. Candidate selection is paired within each DGP.",
    "The original Phase151 realization is descriptive only and is not part of the gate.",
    "",
    sprintf("- Gate: `%s`", assessment$gate_status[[1L]]),
    sprintf("- Completed VB jobs: %d/%d", nrow(candidate_summary), expected),
    sprintf("- Scenarios promoted to MCMC: %d", length(survivors)),
    "",
    "A rejected feature map ends this branch; it does not trigger another broad screen."
  ), readme, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(data.frame(
      run_id = "joint_exqdesn_phase152_independent_vb_confirmation",
      readiness_dir = app_prefer_repo_relative_path(readiness_dir),
      paired_dgp_comparison = TRUE,
      reservoir_seed_aggregation = "median_within_dgp",
      original_phase151_window_in_gate = FALSE,
      article_assets_modified = FALSE,
      stringsAsFactors = FALSE
    ), file.path(out_dir, "run_config.csv")),
    source_manifest_verification = app_joint_qvp_write_csv(
      source_manifest, file.path(out_dir, "source_manifest_verification.csv")
    ),
    candidate_manifest_verification = app_joint_qvp_write_csv(
      candidate_manifest, file.path(out_dir, "candidate_manifest_verification.csv")
    ),
    candidate_summary = app_joint_qvp_write_csv(
      candidate_summary, file.path(out_dir, "candidate_summary.csv")
    ),
    candidate_tau_summary = app_joint_qvp_write_csv(
      tau_summary, file.path(out_dir, "candidate_tau_summary.csv")
    ),
    candidate_interval_summary = app_joint_qvp_write_csv(
      interval_summary, file.path(out_dir, "candidate_interval_summary.csv")
    ),
    design_diagnostics = app_joint_qvp_write_csv(
      design_diagnostics, file.path(out_dir, "design_diagnostics.csv")
    ),
    vb_diagnostics = app_joint_qvp_write_csv(
      vb_diagnostics, file.path(out_dir, "vb_diagnostics.csv")
    ),
    paired_dgp_summary = app_joint_qvp_write_csv(
      paired, file.path(out_dir, "paired_dgp_summary.csv")
    ),
    reservoir_seed_comparison = app_joint_qvp_write_csv(
      seed_comparison, file.path(out_dir, "reservoir_seed_comparison.csv")
    ),
    paired_tau_summary = app_joint_qvp_write_csv(
      tau_paired, file.path(out_dir, "paired_tau_summary.csv")
    ),
    survivor_decision = app_joint_qvp_write_csv(
      decision, file.path(out_dir, "phase152_survivor_decision.csv")
    ),
    result_assessment = app_joint_qvp_write_csv(
      assessment, file.path(out_dir, "phase152_vb_result_assessment.csv")
    ),
    provenance = app_joint_qvp_write_csv(
      app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")
    ),
    readme = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = out_dir,
    assessment = assessment,
    decision = decision,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}

app_joint_exqdesn_run_phase152_vb <- function(
  out_dir = app_joint_exqdesn_phase152_default_vb_dir(),
  readiness_dir = app_joint_exqdesn_phase152_default_readiness_dir(),
  fixture_dir = app_joint_exqdesn_phase152_default_fixture_dir(),
  n_cores = 16L,
  incomplete_only = TRUE
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  readiness <- app_read_csv(file.path(
    readiness_dir, "phase152_readiness_assessment.csv"
  ))
  if (nrow(readiness) != 1L || readiness$gate_status[[1L]] != "pass") {
    stop("Phase152 VB launch is blocked because readiness is not pass.", call. = FALSE)
  }
  registry <- app_read_csv(file.path(
    readiness_dir, "phase152_vb_candidate_registry.csv"
  ))
  complete <- vapply(registry$candidate_id, function(id) {
    app_joint_exqdesn_phase152_verify_candidate_dir(
      app_joint_exqdesn_phase152_candidate_dir(out_dir, id)
    )
  }, logical(1L))
  registry_run <- if (isTRUE(incomplete_only)) registry[!complete, , drop = FALSE] else registry
  artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)
  if (nrow(registry_run)) {
    jobs <- split(registry_run, seq_len(nrow(registry_run)))
    results <- app_joint_qdesn_parallel_lapply(
      jobs,
      function(candidate) {
        result <- app_joint_exqdesn_phase151_evaluate_candidate(artifacts, candidate)
        result <- app_joint_exqdesn_phase152_annotate_result(result, candidate)
        dir <- app_joint_exqdesn_phase152_write_candidate(
          result, out_dir, candidate$candidate_id[[1L]]
        )
        list(candidate_id = candidate$candidate_id[[1L]], candidate_dir = dir)
      },
      n_cores = as.integer(n_cores)
    )
    failures <- app_joint_qdesn_worker_failure_rows(
      results, "phase152_independent_vb_confirmation"
    )
  } else {
    failures <- app_joint_qdesn_worker_failure_rows(
      list(), "phase152_independent_vb_confirmation"
    )
  }
  app_joint_qvp_write_csv(failures, file.path(out_dir, "worker_failures.csv"))
  complete_all <- vapply(registry$candidate_id, function(id) {
    app_joint_exqdesn_phase152_verify_candidate_dir(
      app_joint_exqdesn_phase152_candidate_dir(out_dir, id)
    )
  }, logical(1L))
  progress <- data.frame(
    expected_candidates = nrow(registry),
    completed_candidates = sum(complete_all),
    remaining_candidates = sum(!complete_all),
    worker_failures_this_invocation = nrow(failures),
    n_cores = as.integer(n_cores),
    status = if (all(complete_all) && !nrow(failures)) "complete" else "incomplete",
    stringsAsFactors = FALSE
  )
  app_joint_qvp_write_csv(progress, file.path(out_dir, "progress_summary.csv"))
  if (nrow(failures)) {
    stop(sprintf("Phase152 VB encountered %d worker failure(s).", nrow(failures)), call. = FALSE)
  }
  if (!all(complete_all)) {
    stop(sprintf(
      "Phase152 VB remains incomplete: %d/%d checkpoints are complete.",
      sum(complete_all), length(complete_all)
    ), call. = FALSE)
  }
  app_joint_exqdesn_phase152_aggregate_vb(out_dir, readiness_dir)
}

app_joint_exqdesn_phase152_verify_compact_checkpoint <- function(dir) {
  if (!dir.exists(dir) || !file.exists(file.path(dir, "artifact_manifest.csv"))) {
    return(FALSE)
  }
  tryCatch(
    all(app_joint_exqdesn_phase152_verify_manifest(dir, "checkpoint")$verified),
    error = function(e) FALSE
  )
}

app_joint_exqdesn_phase152_vb_init_dir <- function(out_dir, scenario_id) {
  file.path(out_dir, "vb_initializations", scenario_id)
}

app_joint_exqdesn_phase152_chain_dir <- function(out_dir, scenario_id, chain_id) {
  file.path(out_dir, "chains", scenario_id, sprintf("chain_%02d", chain_id))
}

app_joint_exqdesn_phase152_atomic_checkpoint <- function(
  final_dir,
  writer
) {
  app_ensure_dir(dirname(final_dir))
  if (app_joint_exqdesn_phase152_verify_compact_checkpoint(final_dir)) {
    return(final_dir)
  }
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".invalid.", format(Sys.time(), "%Y%m%d%H%M%S"))
    if (!file.rename(final_dir, quarantine)) {
      stop(sprintf("Could not quarantine invalid checkpoint: %s", final_dir), call. = FALSE)
    }
  }
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  paths <- writer(tmp)
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  app_joint_qvp_write_csv(manifest, file.path(tmp, "artifact_manifest.csv"))
  if (!file.rename(tmp, final_dir) ||
      !app_joint_exqdesn_phase152_verify_compact_checkpoint(final_dir)) {
    stop(sprintf("Could not promote checkpoint: %s", final_dir), call. = FALSE)
  }
  final_dir
}

app_joint_exqdesn_phase152_prepare_mcmc_case <- function(
  artifacts,
  candidate,
  out_dir
) {
  transformed <- app_joint_exqdesn_phase151_transform_design(artifacts, candidate)
  local_artifacts <- artifacts
  local_artifacts$design <- transformed$design
  fixture <- app_joint_qdesn_scenario_fixture(
    local_artifacts, candidate$scenario_id[[1L]], role = "fit"
  )
  controls <- app_joint_exqdesn_phase151_controls(candidate)
  spec <- app_joint_qdesn_phase122_select_spec("joint_exqdesn_rhs_vb")
  checkpoint <- app_joint_exqdesn_phase152_vb_init_dir(
    out_dir, candidate$scenario_id[[1L]]
  )
  if (app_joint_exqdesn_phase152_verify_compact_checkpoint(checkpoint)) {
    vb_fit <- readRDS(file.path(checkpoint, "vb_fit.rds"))
    vb_meta <- app_read_csv(file.path(checkpoint, "vb_initialization_summary.csv"))
  } else {
    start <- proc.time()[["elapsed"]]
    vb_fit <- app_joint_qdesn_fit_model_adaptive(fixture, spec, controls)
    elapsed <- proc.time()[["elapsed"]] - start
    vb_meta <- data.frame(
      scenario_id = candidate$scenario_id[[1L]],
      source_phase151_candidate_id = candidate$candidate_id[[1L]],
      design_role = candidate$design_role[[1L]],
      reservoir_seed = as.integer(candidate$reservoir_seed[[1L]]),
      n_train = length(fixture$y),
      p = ncol(fixture$Z),
      K = length(fixture$tau),
      converged = isTRUE(vb_fit$converged),
      reached_max_iter = !isTRUE(vb_fit$converged),
      elapsed_seconds = elapsed,
      finite_sigma = all(is.finite(vb_fit$sigma_mean)) &&
        all(vb_fit$sigma_mean > 0),
      finite_gamma = !is.null(vb_fit$gamma_mean) &&
        all(is.finite(vb_fit$gamma_mean)),
      stringsAsFactors = FALSE
    )
    app_joint_exqdesn_phase152_atomic_checkpoint(checkpoint, function(tmp) {
      fit_path <- file.path(tmp, "vb_fit.rds")
      saveRDS(vb_fit, fit_path, compress = "xz")
      summary_path <- app_joint_qvp_write_csv(
        vb_meta, file.path(tmp, "vb_initialization_summary.csv")
      )
      readme <- file.path(tmp, "README.md")
      writeLines(c(
        "# Phase152 MCMC VB Initialization",
        "",
        sprintf("- Scenario: `%s`", candidate$scenario_id[[1L]]),
        sprintf("- Source candidate: `%s`", candidate$candidate_id[[1L]]),
        "",
        "This compact object is retained only to initialize resumable MCMC chains."
      ), readme, useBytes = TRUE)
      c(
        vb_fit = normalizePath(fit_path, mustWork = TRUE),
        vb_initialization_summary = summary_path,
        readme = normalizePath(readme, mustWork = TRUE)
      )
    })
  }
  if (!all(is.finite(vb_fit$sigma_mean)) ||
      is.null(vb_fit$gamma_mean) ||
      !all(is.finite(vb_fit$gamma_mean))) {
    stop(sprintf(
      "Phase152 VB initialization is invalid for '%s'.",
      candidate$scenario_id[[1L]]
    ), call. = FALSE)
  }
  row <- candidate
  row$scenario_ids <- candidate$scenario_id[[1L]]
  row$model_ids <- "joint_exqdesn_rhs_vb"
  row$phase121_selection_status <- "phase152_survived_independent_vb_confirmation"
  row$case_id <- paste0(candidate$scenario_id[[1L]], "__phase152_feature_mcmc")
  list(
    candidate = candidate,
    artifacts = local_artifacts,
    fixture = fixture,
    controls = controls,
    spec = spec,
    vb_fit = vb_fit,
    vb_meta = vb_meta,
    row = row,
    design_diagnostics = transformed$diagnostic
  )
}

app_joint_exqdesn_phase152_run_chain <- function(
  case,
  chain_id,
  chain_seed,
  out_dir,
  mcmc_n_iter = 8000L,
  mcmc_burn = 2000L,
  mcmc_thin = 4L,
  sigma_upper_multiplier = 50
) {
  final_dir <- app_joint_exqdesn_phase152_chain_dir(
    out_dir, case$candidate$scenario_id[[1L]], chain_id
  )
  if (app_joint_exqdesn_phase152_verify_compact_checkpoint(final_dir)) {
    return(list(
      scenario_id = case$candidate$scenario_id[[1L]],
      chain_id = as.integer(chain_id),
      chain_dir = final_dir,
      status = "already_complete"
    ))
  }
  base_seed <- as.integer(case$fixture$scenario_meta$seed[[1L]])
  case_offset <- sum(utf8ToInt(case$row$case_id[[1L]])) %% 100000L
  seed_offset <- as.integer(chain_seed - base_seed - case_offset)
  controls <- app_joint_qdesn_mcmc_readiness_controls(
    n_chains = 1L,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin,
    mcmc_seed_offset = seed_offset,
    chain_seed_stride = 1L,
    sigma_upper_multiplier = sigma_upper_multiplier,
    n_cores = 1L
  )
  start <- proc.time()[["elapsed"]]
  result <- app_joint_qdesn_phase122_run_mcmc_chains(
    case$fixture, case$spec, case$vb_fit, case$controls, controls, case$row
  )
  elapsed <- proc.time()[["elapsed"]] - start
  fit <- result$fits[[1L]]
  fit$chain_id <- as.integer(chain_id)
  fit$seed <- as.integer(chain_seed)
  if (!identical(as.integer(result$runtime$chain_seed[[1L]]), as.integer(chain_seed))) {
    stop("Phase152 chain seed contract was not honored.", call. = FALSE)
  }
  summary <- data.frame(
    scenario_id = case$candidate$scenario_id[[1L]],
    source_phase151_candidate_id = case$candidate$candidate_id[[1L]],
    chain_id = as.integer(chain_id),
    chain_seed = as.integer(chain_seed),
    n_iter = as.integer(mcmc_n_iter),
    burn = as.integer(mcmc_burn),
    thin = as.integer(mcmc_thin),
    retained_draws = nrow(fit$beta_draws),
    init_source = fit$init_source %||% NA_character_,
    finite_beta = all(is.finite(fit$beta_draws)),
    finite_alpha = all(is.finite(fit$alpha_draws)),
    finite_sigma = all(is.finite(fit$sigma_draws)) &&
      all(fit$sigma_draws > 0),
    finite_gamma = !is.null(fit$gamma_draws) &&
      all(is.finite(fit$gamma_draws)),
    elapsed_seconds = elapsed,
    stringsAsFactors = FALSE
  )
  app_joint_exqdesn_phase152_atomic_checkpoint(final_dir, function(tmp) {
    fit_path <- file.path(tmp, "chain_fit.rds")
    saveRDS(fit, fit_path, compress = "xz")
    summary_path <- app_joint_qvp_write_csv(
      summary, file.path(tmp, "chain_summary.csv")
    )
    draw_path <- app_joint_qvp_write_csv(
      transform(result$draw_summary, chain_id = as.integer(chain_id),
                chain_seed = as.integer(chain_seed)),
      file.path(tmp, "draw_summary.csv")
    )
    readme <- file.path(tmp, "README.md")
    writeLines(c(
      "# Phase152 MCMC Chain Checkpoint",
      "",
      sprintf("- Scenario: `%s`", case$candidate$scenario_id[[1L]]),
      sprintf("- Chain: %d", chain_id),
      sprintf("- Seed: %d", chain_seed),
      "",
      "The retained object contains one VB-initialized chain and supports exact resume."
    ), readme, useBytes = TRUE)
    c(
      chain_fit = normalizePath(fit_path, mustWork = TRUE),
      chain_summary = summary_path,
      draw_summary = draw_path,
      readme = normalizePath(readme, mustWork = TRUE)
    )
  })
  list(
    scenario_id = case$candidate$scenario_id[[1L]],
    chain_id = as.integer(chain_id),
    chain_dir = final_dir,
    status = "completed"
  )
}

app_joint_exqdesn_phase152_window_from_scores <- function(
  scored,
  raw_crossing,
  contract_crossing,
  adjustment,
  prefix
) {
  crps <- app_joint_qdesn_crps_grid_summary(scored, "qhat")
  hit <- aggregate(hit ~ tau, scored, mean)
  values <- list(
    truth_mae = mean(scored$truth_abs_error),
    truth_rmse = sqrt(mean(scored$truth_sq_error)),
    truth_bias = mean(scored$truth_error),
    check_loss_mean = mean(scored$check_loss),
    crps_grid_mean = crps$crps_grid_mean[[1L]],
    max_abs_hit_rate_error = max(abs(hit$hit - hit$tau)),
    raw_crossing_pairs = sum(raw_crossing$n_crossing_pairs),
    contract_crossing_pairs = sum(contract_crossing$n_crossing_pairs),
    max_abs_adjustment = max(abs(adjustment$adjustment))
  )
  names(values) <- paste0(prefix, "_", names(values))
  as.data.frame(values, stringsAsFactors = FALSE)
}

app_joint_exqdesn_phase152_load_phase150_reference <- function(
  phase150_dir = app_joint_exqdesn_phase150_default_mcmc_dir()
) {
  summary <- app_read_csv(file.path(phase150_dir, "mcmc_case_summary.csv"))
  crps <- app_read_csv(file.path(phase150_dir, "forecast_crps_grid_summary.csv"))
  crps <- crps[
    crps$model_id == "joint_exqdesn_rhs_mcmc" & crps$inference == "MCMC",
    c("scenario_id", "crps_grid_mean"),
    drop = FALSE
  ]
  summary <- merge(summary, crps, by = "scenario_id", all.x = TRUE, sort = FALSE)
  comparison <- app_read_csv(file.path(
    app_joint_exqdesn_phase150_default_audit_dir(phase150_dir),
    "phase150_mcmc_article_comparison.csv"
  ))
  summary <- merge(
    summary,
    comparison[, c(
      "scenario_id", "article_joint_al_forecast_truth_mae",
      "article_joint_al_fit_truth_mae"
    ), drop = FALSE],
    by = "scenario_id",
    all.x = TRUE,
    sort = FALSE
  )
  summary
}

app_joint_exqdesn_phase152_aggregate_mcmc_case <- function(
  case,
  out_dir,
  n_chains,
  mcmc_n_iter,
  mcmc_burn,
  mcmc_thin,
  phase150_reference
) {
  scenario_id <- case$candidate$scenario_id[[1L]]
  chain_dirs <- vapply(seq_len(n_chains), function(chain_id) {
    app_joint_exqdesn_phase152_chain_dir(out_dir, scenario_id, chain_id)
  }, character(1L))
  if (!all(vapply(chain_dirs, app_joint_exqdesn_phase152_verify_compact_checkpoint, logical(1L)))) {
    stop(sprintf("Phase152 MCMC chains are incomplete for '%s'.", scenario_id), call. = FALSE)
  }
  fits <- lapply(chain_dirs, function(dir) readRDS(file.path(dir, "chain_fit.rds")))
  chain_summary <- app_joint_qdesn_bind_rows(lapply(chain_dirs, function(dir) {
    app_read_csv(file.path(dir, "chain_summary.csv"))
  }))
  pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(
    fits, case$fixture$Z, length(case$fixture$tau),
    ncol(case$fixture$Z), case$fixture$tau
  )
  meta <- data.frame(
    case_id = case$row$case_id[[1L]],
    scenario_id = scenario_id,
    model_id = "joint_exqdesn_rhs_mcmc",
    experiment_id = "phase152_independent_confirmation",
    variant_id = case$candidate$design_role[[1L]],
    width_multiplier = NA_real_,
    stringsAsFactors = FALSE
  )
  trace_rows <- app_joint_exqdesn_mcmc_chain_trace_rows(
    fits, case$fixture$tau, meta, mcmc_n_iter, mcmc_burn, mcmc_thin
  )
  trace_summary <- app_joint_exqdesn_mcmc_trace_summary_rows(trace_rows)
  rhat_ess <- app_joint_exqdesn_mcmc_rhat_ess_rows(
    fits, case$fixture$tau, meta
  )
  chain_gap <- app_joint_exqdesn_chain_mean_gap_rows(trace_rows)
  autocorrelation <- app_joint_exqdesn_autocorrelation_rows(trace_rows)
  score_meta <- app_joint_qdesn_phase122_meta(
    case$fixture, case$spec, case$row, "MCMC", "joint_exqdesn_rhs_mcmc"
  )
  fit_scores <- app_joint_qdesn_phase122_score_qhat(
    score_meta, case$fixture,
    app_joint_qdesn_predict_fit(pooled, case$fixture$Z, case$fixture$tau),
    "qhat", "phase152_mcmc_fit"
  )
  forecast_scores <- app_joint_qdesn_phase122_forecast_scores(
    score_meta, case$artifacts, scenario_id, case$fixture, pooled,
    "qhat", "phase152_mcmc_forecast"
  )
  fit_summary <- app_joint_exqdesn_phase152_window_from_scores(
    fit_scores$scored, fit_scores$raw_crossing,
    fit_scores$contract_crossing, fit_scores$adjustment, "fit"
  )
  forecast_summary <- app_joint_exqdesn_phase152_window_from_scores(
    forecast_scores$scored, forecast_scores$raw_crossing,
    forecast_scores$contract_crossing, forecast_scores$adjustment, "forecast"
  )
  reference <- phase150_reference[
    phase150_reference$scenario_id == scenario_id, , drop = FALSE
  ]
  if (nrow(reference) != 1L) {
    stop(sprintf("Missing Phase150 MCMC reference for '%s'.", scenario_id), call. = FALSE)
  }
  gamma_diag <- rhat_ess[rhat_ess$parameter == "gamma", , drop = FALSE]
  sigma_diag <- rhat_ess[rhat_ess$parameter == "sigma", , drop = FALSE]
  summary <- cbind(
    data.frame(
      scenario_id = scenario_id,
      source_phase151_candidate_id = case$candidate$candidate_id[[1L]],
      design_role = case$candidate$design_role[[1L]],
      reservoir_seed = as.integer(case$candidate$reservoir_seed[[1L]]),
      n_chains = as.integer(n_chains),
      n_iter = as.integer(mcmc_n_iter),
      burn = as.integer(mcmc_burn),
      thin = as.integer(mcmc_thin),
      retained_draws_total = sum(chain_summary$retained_draws),
      all_init_source_provided = all(chain_summary$init_source == "provided"),
      all_draws_finite = all(
        chain_summary$finite_beta & chain_summary$finite_alpha &
          chain_summary$finite_sigma & chain_summary$finite_gamma
      ),
      max_gamma_rhat = max(gamma_diag$rhat, na.rm = TRUE),
      min_gamma_rough_ess = min(gamma_diag$rough_ess_total, na.rm = TRUE),
      max_sigma_rhat = max(sigma_diag$rhat, na.rm = TRUE),
      min_sigma_rough_ess = min(sigma_diag$rough_ess_total, na.rm = TRUE),
      elapsed_seconds = sum(chain_summary$elapsed_seconds),
      stringsAsFactors = FALSE
    ),
    fit_summary,
    forecast_summary,
    data.frame(
      phase150_direct_mcmc_fit_truth_mae = reference$mcmc_fit_truth_mae[[1L]],
      phase150_direct_mcmc_forecast_truth_mae =
        reference$mcmc_forecast_truth_mae[[1L]],
      phase150_direct_mcmc_forecast_check_loss =
        reference$mcmc_forecast_check_loss_mean[[1L]],
      phase150_direct_mcmc_forecast_crps = reference$crps_grid_mean[[1L]],
      article_joint_al_fit_truth_mae =
        reference$article_joint_al_fit_truth_mae[[1L]],
      article_joint_al_forecast_truth_mae =
        reference$article_joint_al_forecast_truth_mae[[1L]],
      stringsAsFactors = FALSE
    )
  )
  summary$delta_forecast_mae_vs_phase150_direct <-
    summary$forecast_truth_mae - summary$phase150_direct_mcmc_forecast_truth_mae
  summary$ratio_fit_mae_vs_phase150_direct <-
    summary$fit_truth_mae / summary$phase150_direct_mcmc_fit_truth_mae
  summary$ratio_check_loss_vs_phase150_direct <-
    summary$forecast_check_loss_mean /
    summary$phase150_direct_mcmc_forecast_check_loss
  summary$ratio_crps_vs_phase150_direct <-
    summary$forecast_crps_grid_mean / summary$phase150_direct_mcmc_forecast_crps
  summary$delta_forecast_mae_vs_article_joint_al <-
    summary$forecast_truth_mae - summary$article_joint_al_forecast_truth_mae
  list(
    summary = summary,
    chain_summary = chain_summary,
    trace_rows = trace_rows,
    trace_summary = trace_summary,
    rhat_ess = rhat_ess,
    chain_gap = chain_gap,
    autocorrelation = autocorrelation,
    fit_scores = fit_scores$scored,
    forecast_scores = forecast_scores$scored,
    raw_crossing = app_joint_qdesn_bind_rows(list(
      fit_scores$raw_crossing, forecast_scores$raw_crossing
    )),
    contract_crossing = app_joint_qdesn_bind_rows(list(
      fit_scores$contract_crossing, forecast_scores$contract_crossing
    )),
    adjustment = app_joint_qdesn_bind_rows(list(
      fit_scores$adjustment, forecast_scores$adjustment
    ))
  )
}

app_joint_exqdesn_phase152_mcmc_assessment <- function(summary) {
  app_joint_qdesn_bind_rows(lapply(seq_len(nrow(summary)), function(ii) {
    x <- summary[ii, , drop = FALSE]
    hard_fail <- !isTRUE(x$all_init_source_provided[[1L]]) ||
      !isTRUE(x$all_draws_finite[[1L]]) ||
      !all(is.finite(as.numeric(unlist(x[, c(
        "fit_truth_mae", "forecast_truth_mae", "forecast_check_loss_mean",
        "forecast_crps_grid_mean", "max_gamma_rhat", "min_gamma_rough_ess"
      ), drop = FALSE])))) ||
      x$fit_contract_crossing_pairs[[1L]] > 0L ||
      x$forecast_contract_crossing_pairs[[1L]] > 0L
    performance_pass <- !hard_fail &&
      x$delta_forecast_mae_vs_phase150_direct[[1L]] < 0 &&
      x$ratio_fit_mae_vs_phase150_direct[[1L]] <= 1.05 &&
      x$ratio_check_loss_vs_phase150_direct[[1L]] <= 1.02 &&
      x$ratio_crps_vs_phase150_direct[[1L]] <= 1.02
    mixing_review <- !hard_fail && (
      x$max_gamma_rhat[[1L]] > 1.20 ||
        x$min_gamma_rough_ess[[1L]] < 400 ||
        x$max_sigma_rhat[[1L]] > 1.10 ||
        x$min_sigma_rough_ess[[1L]] < 400
    )
    reasons <- c(
      if (!isTRUE(x$all_init_source_provided[[1L]])) "one or more chains did not use provided VB initialization",
      if (!isTRUE(x$all_draws_finite[[1L]])) "one or more retained chains contain nonfinite draws",
      if (x$fit_contract_crossing_pairs[[1L]] > 0L ||
          x$forecast_contract_crossing_pairs[[1L]] > 0L) "contract quantiles crossed",
      if (!hard_fail && x$delta_forecast_mae_vs_phase150_direct[[1L]] >= 0) "feature-map MCMC did not improve forecast MAE over Phase150 direct exAL",
      if (!hard_fail && x$ratio_fit_mae_vs_phase150_direct[[1L]] > 1.05) "fit MAE guard exceeded 1.05",
      if (!hard_fail && x$ratio_check_loss_vs_phase150_direct[[1L]] > 1.02) "check-loss guard exceeded 1.02",
      if (!hard_fail && x$ratio_crps_vs_phase150_direct[[1L]] > 1.02) "grid-CRPS guard exceeded 1.02",
      if (mixing_review) "gamma or sigma mixing remains review-level"
    )
    data.frame(
      scenario_id = x$scenario_id[[1L]],
      implementation_status = if (hard_fail) "fail" else "pass",
      performance_status = if (performance_pass) "pass" else "review",
      mixing_status = if (hard_fail) "fail" else if (mixing_review) "review" else "pass",
      article_candidate_status = if (hard_fail) {
        "blocked"
      } else if (performance_pass) {
        "candidate_pending_article_safe_review"
      } else {
        "retain_phase150_direct_exal_row"
      },
      gate_status = if (hard_fail) "fail" else if (performance_pass && !mixing_review) {
        "pass"
      } else {
        "review"
      },
      status_reason = if (length(reasons)) paste(reasons, collapse = "; ") else {
        "implementation, performance, and diagnostic gates passed"
      },
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase152_write_no_survivor_mcmc <- function(
  out_dir,
  decision,
  vb_dir,
  source_manifest
) {
  app_ensure_dir(out_dir)
  assessment <- data.frame(
    audit_id = "phase152_conditional_mcmc_confirmation",
    gate_status = "pass",
    scenarios_eligible = 0L,
    chains_expected = 0L,
    chains_completed = 0L,
    recommendation = "stop_feature_map_branch_and_retain_phase150_article_rows",
    article_assets_modified = FALSE,
    stringsAsFactors = FALSE
  )
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase152 Conditional MCMC Confirmation",
    "",
    "No feature map cleared the independent VB promotion gates. Therefore no MCMC",
    "chains were launched. This is the intended stopping rule, not a run failure."
  ), readme, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(data.frame(
      run_id = "joint_exqdesn_phase152_conditional_mcmc_confirmation",
      vb_dir = app_prefer_repo_relative_path(vb_dir),
      conditional_launch = TRUE,
      stringsAsFactors = FALSE
    ), file.path(out_dir, "run_config.csv")),
    survivor_decision = app_joint_qvp_write_csv(
      decision, file.path(out_dir, "phase152_survivor_decision.csv")
    ),
    source_manifest_verification = app_joint_qvp_write_csv(
      source_manifest, file.path(out_dir, "source_manifest_verification.csv")
    ),
    result_assessment = app_joint_qvp_write_csv(
      assessment, file.path(out_dir, "phase152_mcmc_result_assessment.csv")
    ),
    provenance = app_joint_qvp_write_csv(
      app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")
    ),
    readme = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = out_dir,
    assessment = assessment,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}

app_joint_exqdesn_run_phase152_mcmc <- function(
  out_dir = app_joint_exqdesn_phase152_default_mcmc_dir(),
  vb_dir = app_joint_exqdesn_phase152_default_vb_dir(),
  readiness_dir = app_joint_exqdesn_phase152_default_readiness_dir(),
  fixture_dir = app_joint_exqdesn_phase151_default_fixture_dir(),
  phase150_dir = app_joint_exqdesn_phase150_default_mcmc_dir(),
  n_chains = 8L,
  mcmc_n_iter = 8000L,
  mcmc_burn = 2000L,
  mcmc_thin = 4L,
  n_cores = 16L,
  sigma_upper_multiplier = 50
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  vb_assessment <- app_read_csv(file.path(
    vb_dir, "phase152_vb_result_assessment.csv"
  ))
  if (vb_assessment$gate_status[[1L]] != "pass") {
    stop("Phase152 MCMC is blocked because the VB packet failed.", call. = FALSE)
  }
  source_manifest <- app_joint_qdesn_bind_rows(list(
    app_joint_exqdesn_phase152_verify_manifest(vb_dir, "phase152_vb_packet"),
    app_joint_exqdesn_phase152_verify_manifest(
      readiness_dir, "phase152_readiness_packet"
    ),
    app_joint_exqdesn_phase152_verify_manifest(
      fixture_dir, "phase151_formal_fixture"
    ),
    app_joint_exqdesn_phase152_verify_manifest(
      phase150_dir, "phase150_direct_mcmc_reference"
    ),
    app_joint_exqdesn_phase152_verify_manifest(
      app_joint_exqdesn_phase150_default_audit_dir(phase150_dir),
      "phase150_result_audit"
    )
  ))
  if (any(!source_manifest$verified)) {
    stop("Phase152 MCMC source manifest verification failed.", call. = FALSE)
  }
  decision <- app_read_csv(file.path(vb_dir, "phase152_survivor_decision.csv"))
  survivors <- decision$base_scenario_id[
    decision$promotion_status == "promote_to_mcmc"
  ]
  if (!length(survivors)) {
    return(app_joint_exqdesn_phase152_write_no_survivor_mcmc(
      out_dir, decision, vb_dir, source_manifest
    ))
  }
  frozen <- app_read_csv(file.path(
    readiness_dir, "phase152_frozen_phase151_candidates.csv"
  ))
  selected <- frozen[
    frozen$phase152_role == "selected_feature_map" &
      frozen$scenario_id %in% survivors,
    ,
    drop = FALSE
  ]
  selected <- selected[match(survivors, selected$scenario_id), , drop = FALSE]
  chain_plan <- app_read_csv(file.path(
    readiness_dir, "phase152_mcmc_chain_seed_plan.csv"
  ))
  chain_plan <- chain_plan[
    chain_plan$base_scenario_id %in% survivors &
      chain_plan$chain_id <= as.integer(n_chains),
    ,
    drop = FALSE
  ]
  if (nrow(chain_plan) != length(survivors) * as.integer(n_chains)) {
    stop("Phase152 chain seed plan does not cover every survivor and chain.", call. = FALSE)
  }
  artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)
  cases <- lapply(seq_len(nrow(selected)), function(ii) {
    app_joint_exqdesn_phase152_prepare_mcmc_case(
      artifacts, selected[ii, , drop = FALSE], out_dir
    )
  })
  names(cases) <- selected$scenario_id
  jobs <- lapply(seq_len(nrow(chain_plan)), function(ii) {
    list(
      scenario_id = chain_plan$base_scenario_id[[ii]],
      chain_id = as.integer(chain_plan$chain_id[[ii]]),
      chain_seed = as.integer(chain_plan$chain_seed[[ii]])
    )
  })
  complete <- vapply(jobs, function(job) {
    app_joint_exqdesn_phase152_verify_compact_checkpoint(
      app_joint_exqdesn_phase152_chain_dir(
        out_dir, job$scenario_id, job$chain_id
      )
    )
  }, logical(1L))
  jobs_run <- jobs[!complete]
  if (length(jobs_run)) {
    results <- app_joint_qdesn_parallel_lapply(
      jobs_run,
      function(job) {
        app_joint_exqdesn_phase152_run_chain(
          cases[[job$scenario_id]], job$chain_id, job$chain_seed, out_dir,
          mcmc_n_iter, mcmc_burn, mcmc_thin, sigma_upper_multiplier
        )
      },
      n_cores = min(as.integer(n_cores), length(jobs_run))
    )
    failures <- app_joint_qdesn_worker_failure_rows(
      results, "phase152_flat_mcmc_chain"
    )
  } else {
    failures <- app_joint_qdesn_worker_failure_rows(
      list(), "phase152_flat_mcmc_chain"
    )
  }
  app_joint_qvp_write_csv(failures, file.path(out_dir, "worker_failures.csv"))
  complete_all <- vapply(jobs, function(job) {
    app_joint_exqdesn_phase152_verify_compact_checkpoint(
      app_joint_exqdesn_phase152_chain_dir(
        out_dir, job$scenario_id, job$chain_id
      )
    )
  }, logical(1L))
  app_joint_qvp_write_csv(data.frame(
    scenarios_eligible = length(survivors),
    chains_expected = length(jobs),
    chains_completed = sum(complete_all),
    chains_remaining = sum(!complete_all),
    worker_failures_this_invocation = nrow(failures),
    n_cores = as.integer(n_cores),
    status = if (all(complete_all) && !nrow(failures)) "complete" else "incomplete",
    stringsAsFactors = FALSE
  ), file.path(out_dir, "progress_summary.csv"))
  if (nrow(failures)) {
    stop(sprintf("Phase152 MCMC encountered %d chain failure(s).", nrow(failures)), call. = FALSE)
  }
  if (!all(complete_all)) {
    stop(sprintf(
      "Phase152 MCMC remains incomplete: %d/%d chains are complete.",
      sum(complete_all), length(complete_all)
    ), call. = FALSE)
  }
  chain_manifest <- app_joint_qdesn_bind_rows(lapply(jobs, function(job) {
    verification <- app_joint_exqdesn_phase152_verify_manifest(
      app_joint_exqdesn_phase152_chain_dir(
        out_dir, job$scenario_id, job$chain_id
      ),
      paste0(job$scenario_id, "_chain_", sprintf("%02d", job$chain_id))
    )
    cbind(
      data.frame(
        scenario_id = job$scenario_id,
        chain_id = as.integer(job$chain_id),
        stringsAsFactors = FALSE
      ),
      verification,
      stringsAsFactors = FALSE
    )
  }))
  if (any(!chain_manifest$verified)) {
    stop("Phase152 MCMC chain checkpoint verification failed.", call. = FALSE)
  }

  reference <- app_joint_exqdesn_phase152_load_phase150_reference(phase150_dir)
  case_results <- lapply(cases, function(case) {
    app_joint_exqdesn_phase152_aggregate_mcmc_case(
      case, out_dir, n_chains, mcmc_n_iter, mcmc_burn, mcmc_thin, reference
    )
  })
  summary <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "summary"))
  assessment <- app_joint_exqdesn_phase152_mcmc_assessment(summary)
  chain_summary <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "chain_summary"))
  trace_rows <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "trace_rows"))
  trace_summary <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "trace_summary"))
  rhat_ess <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "rhat_ess"))
  chain_gap <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "chain_gap"))
  autocorrelation <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "autocorrelation"))
  fit_scores <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "fit_scores"))
  forecast_scores <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "forecast_scores"))
  raw_crossing <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "raw_crossing"))
  contract_crossing <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "contract_crossing"))
  adjustment <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "adjustment"))
  root_gate <- if (any(assessment$gate_status == "fail")) {
    "fail"
  } else if (any(assessment$gate_status == "review")) {
    "review"
  } else {
    "pass"
  }
  root_assessment <- data.frame(
    audit_id = "phase152_conditional_mcmc_confirmation",
    gate_status = root_gate,
    scenarios_eligible = length(survivors),
    chains_expected = length(jobs),
    chains_completed = sum(complete_all),
    implementation_failures = sum(assessment$implementation_status == "fail"),
    performance_passes = sum(assessment$performance_status == "pass"),
    article_candidates = sum(grepl(
      "^candidate_", assessment$article_candidate_status
    )),
    recommendation = if (root_gate == "fail") {
      "fix_phase152_mcmc_integrity_before_interpretation"
    } else if (any(grepl("^candidate_", assessment$article_candidate_status))) {
      "conduct_separate_article_safe_review_of_confirmed_feature_map_rows"
    } else {
      "retain_phase150_direct_exal_rows_and_close_feature_map_branch"
    },
    article_assets_modified = FALSE,
    stringsAsFactors = FALSE
  )
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase152 Conditional MCMC Confirmation",
    "",
    "This packet contains only feature maps that survived the independent paired VB gate.",
    "Chains are VB-initialized, checkpointed separately, and pooled only after all hashes pass.",
    "Mixing is a diagnostic gate; quantile-grid performance remains the primary decision target.",
    "",
    sprintf("- Gate: `%s`", root_gate),
    sprintf("- Survivors: %d", length(survivors)),
    sprintf("- Complete chains: %d/%d", sum(complete_all), length(jobs)),
    "",
    "No article file is modified by this runner."
  ), readme, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(data.frame(
      run_id = "joint_exqdesn_phase152_conditional_mcmc_confirmation",
      vb_dir = app_prefer_repo_relative_path(vb_dir),
      readiness_dir = app_prefer_repo_relative_path(readiness_dir),
      fixture_dir = app_prefer_repo_relative_path(fixture_dir),
      phase150_reference_dir = app_prefer_repo_relative_path(phase150_dir),
      n_chains = as.integer(n_chains),
      mcmc_n_iter = as.integer(mcmc_n_iter),
      mcmc_burn = as.integer(mcmc_burn),
      mcmc_thin = as.integer(mcmc_thin),
      chain_parallelism = TRUE,
      article_assets_modified = FALSE,
      stringsAsFactors = FALSE
    ), file.path(out_dir, "run_config.csv")),
    survivor_decision = app_joint_qvp_write_csv(
      decision, file.path(out_dir, "phase152_survivor_decision.csv")
    ),
    source_manifest_verification = app_joint_qvp_write_csv(
      source_manifest, file.path(out_dir, "source_manifest_verification.csv")
    ),
    chain_manifest_verification = app_joint_qvp_write_csv(
      chain_manifest, file.path(out_dir, "chain_manifest_verification.csv")
    ),
    design_diagnostics = app_joint_qvp_write_csv(
      app_joint_qdesn_bind_rows(lapply(cases, `[[`, "design_diagnostics")),
      file.path(out_dir, "design_diagnostics.csv")
    ),
    vb_initialization_summary = app_joint_qvp_write_csv(
      app_joint_qdesn_bind_rows(lapply(cases, `[[`, "vb_meta")),
      file.path(out_dir, "vb_initialization_summary.csv")
    ),
    mcmc_case_summary = app_joint_qvp_write_csv(
      summary, file.path(out_dir, "mcmc_case_summary.csv")
    ),
    mcmc_case_assessment = app_joint_qvp_write_csv(
      assessment, file.path(out_dir, "mcmc_case_assessment.csv")
    ),
    chain_summary = app_joint_qvp_write_csv(
      chain_summary, file.path(out_dir, "chain_summary.csv")
    ),
    mcmc_trace = app_joint_qvp_write_csv(
      trace_rows, file.path(out_dir, "mcmc_gamma_sigma_lambda_trace.csv")
    ),
    mcmc_trace_summary = app_joint_qvp_write_csv(
      trace_summary, file.path(out_dir, "mcmc_trace_summary.csv")
    ),
    mcmc_rhat_ess = app_joint_qvp_write_csv(
      rhat_ess, file.path(out_dir, "mcmc_rhat_ess_summary.csv")
    ),
    mcmc_chain_gap = app_joint_qvp_write_csv(
      chain_gap, file.path(out_dir, "mcmc_chain_mean_gap_summary.csv")
    ),
    mcmc_autocorrelation = app_joint_qvp_write_csv(
      autocorrelation, file.path(out_dir, "mcmc_autocorrelation_summary.csv")
    ),
    fit_score_summary = app_joint_qvp_write_csv(
      fit_scores, file.path(out_dir, "fit_quantile_score_rows.csv")
    ),
    forecast_score_summary = app_joint_qvp_write_csv(
      forecast_scores, file.path(out_dir, "forecast_quantile_score_rows.csv")
    ),
    raw_crossing_summary = app_joint_qvp_write_csv(
      raw_crossing, file.path(out_dir, "raw_crossing_summary.csv")
    ),
    crossing_summary = app_joint_qvp_write_csv(
      contract_crossing, file.path(out_dir, "crossing_summary.csv")
    ),
    monotone_adjustment = app_joint_qvp_write_csv(
      adjustment, file.path(out_dir, "monotone_adjustment.csv")
    ),
    result_assessment = app_joint_qvp_write_csv(
      root_assessment, file.path(out_dir, "phase152_mcmc_result_assessment.csv")
    ),
    provenance = app_joint_qvp_write_csv(
      app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")
    ),
    readme = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = out_dir,
    assessment = root_assessment,
    case_assessment = assessment,
    summary = summary,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}

app_joint_exqdesn_phase152_health <- function(
  readiness_dir = app_joint_exqdesn_phase152_default_readiness_dir(),
  vb_dir = app_joint_exqdesn_phase152_default_vb_dir(),
  mcmc_dir = app_joint_exqdesn_phase152_default_mcmc_dir(),
  session_alive = FALSE,
  runner_process_count = 0L
) {
  vb_registry_path <- file.path(readiness_dir, "phase152_vb_candidate_registry.csv")
  if (!file.exists(vb_registry_path)) {
    return(data.frame(
      phase_id = "phase152_independent_confirmation",
      lifecycle_state = "not_prepared",
      vb_expected = NA_integer_, vb_completed = 0L, vb_remaining = NA_integer_,
      mcmc_expected = NA_integer_, mcmc_completed = 0L, mcmc_remaining = NA_integer_,
      session_alive = isTRUE(session_alive),
      runner_process_count = as.integer(runner_process_count),
      recommendation = "run_phase152_readiness",
      stringsAsFactors = FALSE
    ))
  }
  registry <- app_read_csv(vb_registry_path)
  vb_complete <- vapply(registry$candidate_id, function(id) {
    app_joint_exqdesn_phase152_verify_candidate_dir(
      app_joint_exqdesn_phase152_candidate_dir(vb_dir, id)
    )
  }, logical(1L))
  decision_path <- file.path(vb_dir, "phase152_survivor_decision.csv")
  survivors <- if (file.exists(decision_path)) {
    d <- app_read_csv(decision_path)
    d$base_scenario_id[d$promotion_status == "promote_to_mcmc"]
  } else character()
  chain_plan_path <- file.path(readiness_dir, "phase152_mcmc_chain_seed_plan.csv")
  chain_plan <- if (file.exists(chain_plan_path)) app_read_csv(chain_plan_path) else data.frame()
  if (length(survivors) && nrow(chain_plan)) {
    jobs <- chain_plan[chain_plan$base_scenario_id %in% survivors, , drop = FALSE]
    mcmc_complete <- vapply(seq_len(nrow(jobs)), function(ii) {
      app_joint_exqdesn_phase152_verify_compact_checkpoint(
        app_joint_exqdesn_phase152_chain_dir(
          mcmc_dir, jobs$base_scenario_id[[ii]], jobs$chain_id[[ii]]
        )
      )
    }, logical(1L))
  } else {
    jobs <- data.frame()
    mcmc_complete <- logical()
  }
  active <- isTRUE(session_alive) || as.integer(runner_process_count) > 0L
  final_complete <- file.exists(file.path(mcmc_dir, "artifact_manifest.csv")) &&
    file.exists(file.path(mcmc_dir, "phase152_mcmc_result_assessment.csv"))
  state <- if (active) {
    "running"
  } else if (final_complete) {
    "complete"
  } else if (all(vb_complete) && file.exists(decision_path)) {
    "vb_complete_mcmc_pending_or_interrupted"
  } else if (any(vb_complete)) {
    "vb_interrupted_resumable"
  } else {
    "prepared_not_started"
  }
  data.frame(
    phase_id = "phase152_independent_confirmation",
    lifecycle_state = state,
    vb_expected = nrow(registry),
    vb_completed = sum(vb_complete),
    vb_remaining = sum(!vb_complete),
    mcmc_expected = nrow(jobs),
    mcmc_completed = sum(mcmc_complete),
    mcmc_remaining = nrow(jobs) - sum(mcmc_complete),
    session_alive = active,
    runner_process_count = as.integer(runner_process_count),
    recommendation = switch(
      state,
      running = "preserve_active_phase152_run",
      complete = "audit_phase152_results_before_any_article_change",
      vb_complete_mcmc_pending_or_interrupted = "resume_conditional_mcmc_only",
      vb_interrupted_resumable = "resume_incomplete_vb_candidates_only",
      prepared_not_started = "launch_phase152_workflow"
    ),
    stringsAsFactors = FALSE
  )
}
