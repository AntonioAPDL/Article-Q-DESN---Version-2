# Phase 124 balanced-completion preparation.
#
# Phase 123 confirmed the available case-specific MCMC rows, but the article
# comparison is not balanced until every scenario has all four model rows:
# Joint/Independent QDESN and Joint/Independent exQDESN.  This module prepares
# only the missing cells using the already-versioned Phase 119 candidate grid.

app_joint_qdesn_default_phase124_balanced_completion_dir <- function() {
  app_path("application/cache/joint_qdesn_phase124_balanced_completion_20260711")
}

app_joint_qdesn_default_phase124_vb_completion_dir <- function() {
  app_path("application/cache/joint_qdesn_vb_balanced_completion_phase124_20260711")
}

app_joint_qdesn_phase124_write_csv <- function(x, path) {
  app_ensure_dir(dirname(path))
  utils::write.csv(x, path, row.names = FALSE, na = "")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

app_joint_qdesn_phase124_manifest_verify <- function(dir, source_label) {
  dir <- normalizePath(dir, winslash = "/", mustWork = TRUE)
  manifest_path <- file.path(dir, "artifact_manifest.csv")
  if (!file.exists(manifest_path)) {
    return(data.frame(
      source_label = source_label,
      label = "artifact_manifest",
      relative_path = "artifact_manifest.csv",
      path = normalizePath(manifest_path, winslash = "/", mustWork = FALSE),
      exists = FALSE,
      declared_size_bytes = NA_real_,
      actual_size_bytes = NA_real_,
      declared_sha256 = NA_character_,
      actual_sha256 = NA_character_,
      status = "fail",
      stringsAsFactors = FALSE
    ))
  }
  manifest <- app_read_csv(manifest_path)
  app_check_required_columns(manifest, c("label", "relative_path", "size_bytes", "sha256"), source_label)
  rows <- lapply(seq_len(nrow(manifest)), function(ii) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    exists <- file.exists(path)
    actual_sha <- if (exists) app_sha256_file(path) else NA_character_
    actual_size <- if (exists) as.numeric(file.info(path)$size) else NA_real_
    data.frame(
      source_label = source_label,
      label = manifest$label[[ii]],
      relative_path = manifest$relative_path[[ii]],
      path = normalizePath(path, winslash = "/", mustWork = FALSE),
      exists = exists,
      declared_size_bytes = as.numeric(manifest$size_bytes[[ii]]),
      actual_size_bytes = actual_size,
      declared_sha256 = manifest$sha256[[ii]],
      actual_sha256 = actual_sha,
      status = if (exists &&
        identical(tolower(actual_sha), tolower(manifest$sha256[[ii]])) &&
        identical(as.numeric(actual_size), as.numeric(manifest$size_bytes[[ii]]))) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase124_load_sources <- function(phase123_dir, phase119_readiness_dir) {
  phase123_dir <- normalizePath(phase123_dir, winslash = "/", mustWork = TRUE)
  phase119_readiness_dir <- normalizePath(phase119_readiness_dir, winslash = "/", mustWork = TRUE)
  phase123_manifest <- app_joint_qdesn_phase124_manifest_verify(phase123_dir, "phase123_mcmc_article_freeze")
  phase119_manifest <- app_joint_qdesn_phase124_manifest_verify(phase119_readiness_dir, "phase119_case_readiness")

  scope_path <- file.path(phase123_dir, "article_scope_matrix.csv")
  registry_path <- file.path(phase119_readiness_dir, "phase119_case_specific_screening_registry.csv")
  if (!file.exists(scope_path)) stop(sprintf("Missing Phase 123 scope matrix: %s", scope_path), call. = FALSE)
  if (!file.exists(registry_path)) stop(sprintf("Missing Phase 119 full registry: %s", registry_path), call. = FALSE)

  scope <- app_read_csv(scope_path)
  registry <- app_read_csv(registry_path)
  app_check_required_columns(scope, c("scenario_id", "source_model_id", "present_in_phase122"), "Phase 123 article scope matrix")
  app_check_required_columns(registry, c("candidate_id", "case_id", "scenario_ids", "model_ids", "fit_dir", "forecast_dir"), "Phase 119 full registry")

  list(
    phase123_dir = phase123_dir,
    phase119_readiness_dir = phase119_readiness_dir,
    phase123_manifest = phase123_manifest,
    phase119_manifest = phase119_manifest,
    article_scope = scope,
    source_registry = registry
  )
}

app_joint_qdesn_phase124_missing_cells <- function(article_scope) {
  app_check_required_columns(article_scope, c("scenario_id", "source_model_id", "present_in_phase122"), "Phase 123 article scope matrix")
  present <- as.logical(article_scope$present_in_phase122)
  missing <- article_scope[!present, , drop = FALSE]
  if (!nrow(missing)) {
    missing$case_id <- character()
    return(missing)
  }
  missing$case_id <- paste(missing$scenario_id, missing$source_model_id, sep = "__")
  missing$missing_reason <- "not_present_in_phase122_balanced_mcmc_scope"
  missing[order(missing$source_model_id, missing$scenario_id), , drop = FALSE]
}

app_joint_qdesn_phase124_slug <- function(x) {
  gsub("[^A-Za-z0-9_.-]+", "_", as.character(x))
}

app_joint_qdesn_phase124_candidate_suffix <- function(candidate_id, case_id) {
  candidate_id <- as.character(candidate_id)
  case_id <- as.character(case_id)
  prefix <- paste0(case_id, "__")
  out <- ifelse(startsWith(candidate_id, prefix), substring(candidate_id, nchar(prefix) + 1L), candidate_id)
  app_joint_qdesn_phase124_slug(out)
}

app_joint_qdesn_phase124_rewrite_registry_paths <- function(registry, vb_output_dir) {
  vb_output_dir <- normalizePath(vb_output_dir, winslash = "/", mustWork = FALSE)
  registry$phase124_source_candidate_id <- registry$candidate_id
  registry$phase124_source_fit_dir <- registry$fit_dir
  registry$phase124_source_forecast_dir <- registry$forecast_dir
  suffix <- app_joint_qdesn_phase124_candidate_suffix(registry$candidate_id, registry$case_id)
  case_slug <- app_joint_qdesn_phase124_slug(registry$case_id)
  registry$use_existing_artifacts <- FALSE
  registry$fit_dir <- file.path(vb_output_dir, "cases", case_slug, "candidates", suffix, "fit")
  registry$forecast_dir <- file.path(vb_output_dir, "cases", case_slug, "candidates", suffix, "forecast")
  registry$phase124_candidate_suffix <- suffix
  registry$phase124_case_slug <- case_slug
  registry$phase124_completion_role <- "balanced_missing_cell_vb_screening"
  registry
}

app_joint_qdesn_phase124_build_registry <- function(
  missing_cells,
  source_registry,
  vb_output_dir = app_joint_qdesn_default_phase124_vb_completion_dir(),
  n_cores = 1L
) {
  if (!nrow(missing_cells)) return(source_registry[FALSE, , drop = FALSE])
  app_check_required_columns(missing_cells, c("case_id", "scenario_id", "source_model_id"), "Phase 124 missing cells")
  app_check_required_columns(source_registry, c("candidate_id", "case_id", "scenario_ids", "model_ids"), "Phase 119 source registry")

  source <- source_registry[source_registry$case_id %in% missing_cells$case_id, , drop = FALSE]
  coverage <- aggregate(candidate_id ~ case_id, source, length)
  names(coverage)[names(coverage) == "candidate_id"] <- "source_candidate_rows"
  coverage <- merge(missing_cells[, c("case_id", "scenario_id", "source_model_id"), drop = FALSE], coverage, by = "case_id", all.x = TRUE)
  coverage$source_candidate_rows[is.na(coverage$source_candidate_rows)] <- 0L
  missing_coverage <- coverage$case_id[coverage$source_candidate_rows <= 0L]
  if (length(missing_coverage)) {
    stop(sprintf("Phase 119 registry has no candidate rows for missing cells: %s", paste(missing_coverage, collapse = ", ")), call. = FALSE)
  }

  source$phase124_case_order <- match(source$case_id, missing_cells$case_id)
  source <- source[order(source$phase124_case_order, source$candidate_id), , drop = FALSE]
  source <- app_joint_qdesn_phase124_rewrite_registry_paths(source, vb_output_dir = vb_output_dir)
  source$n_cores <- as.integer(n_cores)
  source$case_priority <- "phase124_balanced_completion"
  source$case_focus <- "fill_missing_balanced_mcmc_cell"
  source$phase124_missing_reason <- "not_present_in_phase122_balanced_mcmc_scope"
  app_joint_qdesn_validate_screening_registry(source, allow_alpha_prior_vectors = FALSE)
  source
}

app_joint_qdesn_phase124_candidate_source_map <- function(registry) {
  keep <- intersect(c(
    "candidate_id", "phase124_source_candidate_id", "case_id", "scenario_ids", "model_ids",
    "candidate_role", "phase124_candidate_suffix", "phase124_source_fit_dir",
    "fit_dir", "phase124_source_forecast_dir", "forecast_dir",
    "vb_max_iter", "adaptive_vb_max_iter_grid", "rhs_vb_inner", "tau0", "zeta2",
    "alpha_prior_sd", "gamma_init_policy", "notes"
  ), names(registry))
  out <- registry[, keep, drop = FALSE]
  names(out)[names(out) == "fit_dir"] <- "phase124_fit_dir"
  names(out)[names(out) == "forecast_dir"] <- "phase124_forecast_dir"
  out
}

app_joint_qdesn_phase124_screening_progress <- function(registry) {
  if (!nrow(registry)) {
    return(data.frame(
      total_candidate_rows = 0L,
      fit_manifest_exists = 0L,
      forecast_manifest_exists = 0L,
      complete_candidate_rows = 0L,
      incomplete_candidate_rows = 0L,
      stringsAsFactors = FALSE
    ))
  }
  fit_done <- file.exists(file.path(registry$fit_dir, "artifact_manifest.csv"))
  forecast_done <- file.exists(file.path(registry$forecast_dir, "artifact_manifest.csv"))
  data.frame(
    total_candidate_rows = nrow(registry),
    fit_manifest_exists = sum(fit_done),
    forecast_manifest_exists = sum(forecast_done),
    complete_candidate_rows = sum(fit_done & forecast_done),
    incomplete_candidate_rows = sum(!(fit_done & forecast_done)),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase124_gate_summary <- function(
  sources,
  missing_cells,
  registry,
  progress,
  expected_missing_cells = 15L
) {
  manifest_status <- function(x) if (nrow(x) && all(x$status == "pass")) "pass" else "fail"
  registry_cases <- unique(registry$case_id)
  source_coverage_ok <- nrow(missing_cells) > 0L && setequal(missing_cells$case_id, registry_cases)
  no_duplicate_candidates <- !anyDuplicated(registry$candidate_id)
  output_isolated <- !any(grepl("joint_qdesn_vb_case_specific_screening_phase119", registry$fit_dir, fixed = TRUE) |
    grepl("joint_qdesn_vb_case_specific_screening_phase119", registry$forecast_dir, fixed = TRUE))
  schema_status <- tryCatch({
    app_joint_qdesn_validate_screening_registry(registry, allow_alpha_prior_vectors = FALSE)
    "pass"
  }, error = function(e) "fail")

  data.frame(
    gate = c(
      "phase123_freeze_manifest",
      "phase119_readiness_manifest",
      "balanced_scope_gap_detected",
      "source_registry_coverage",
      "phase124_registry_schema",
      "phase124_output_isolation",
      "phase124_vb_launch_readiness",
      "phase124_mcmc_launch_readiness"
    ),
    status = c(
      manifest_status(sources$phase123_manifest),
      manifest_status(sources$phase119_manifest),
      if (nrow(missing_cells) == expected_missing_cells) "pass" else "review",
      if (source_coverage_ok) "pass" else "fail",
      schema_status,
      if (output_isolated) "pass" else "fail",
      if (manifest_status(sources$phase123_manifest) == "pass" &&
        manifest_status(sources$phase119_manifest) == "pass" &&
        source_coverage_ok && no_duplicate_candidates &&
        schema_status == "pass" && output_isolated && nrow(registry) > 0L) "pass" else "fail",
      if (progress$complete_candidate_rows[[1L]] == nrow(registry) && nrow(registry) > 0L) "review" else "review"
    ),
    detail = c(
      sprintf("%d/%d Phase 123 manifest rows pass.", sum(sources$phase123_manifest$status == "pass"), nrow(sources$phase123_manifest)),
      sprintf("%d/%d Phase 119 manifest rows pass.", sum(sources$phase119_manifest$status == "pass"), nrow(sources$phase119_manifest)),
      sprintf("%d missing balanced cells detected; expected %d from Phase 123.", nrow(missing_cells), as.integer(expected_missing_cells)),
      sprintf("%d missing cells covered by %d Phase 119 candidate rows.", length(registry_cases), nrow(registry)),
      if (schema_status == "pass") "Registry validates against the Phase 106 screening schema." else "Registry schema validation failed.",
      if (output_isolated) "All fit/forecast paths point to the Phase 124 completion output root." else "At least one fit/forecast path still points to a source screening root.",
      sprintf("%d candidate rows are ready for VB screening launch.", nrow(registry)),
      "MCMC completion is intentionally blocked until Phase 124 VB screening finishes and missing-cell winners are frozen."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase124_health <- function(missing_cells, registry, progress, gates) {
  data.frame(
    component = c("balanced_mcmc_scope", "phase124_vb_registry", "phase124_vb_progress", "phase124_mcmc_readiness"),
    status = c(
      if (nrow(missing_cells) > 0L) "review" else "pass",
      if (any(gates$status == "fail")) "fail" else "pass",
      if (progress$complete_candidate_rows[[1L]] == nrow(registry) && nrow(registry) > 0L) "complete" else "running_needed",
      "blocked_until_vb_winner_freeze"
    ),
    progress = c(
      sprintf("%d missing model-scenario cells", nrow(missing_cells)),
      sprintf("%d candidate rows across %d cells", nrow(registry), length(unique(registry$case_id))),
      sprintf("%d/%d candidate rows complete", progress$complete_candidate_rows[[1L]], nrow(registry)),
      "0 missing-cell MCMC rows launched by Phase 124 preparation"
    ),
    detail = c(
      "Phase 123 confirms existing rows but cannot support a balanced four-model comparison by itself.",
      "Candidate rows are inherited from the Phase 119 full case-specific registry and use fresh Phase 124 artifact paths.",
      "Run the recorded chunked VB screening command, then execute the recorded audit command.",
      "Freeze one missing-cell VB/VB-LD winner per case before launching the balanced MCMC completion."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase124_launch_plan <- function(
  registry_path,
  canonical_output_dir,
  fixture_dir,
  workers = 12L,
  n_cores_per_worker = 1L,
  run_id = "phase124_20260711",
  session_prefix = "joint_qdesn_phase124_vb_20260711"
) {
  registry_path <- normalizePath(registry_path, winslash = "/", mustWork = FALSE)
  canonical_output_dir <- normalizePath(canonical_output_dir, winslash = "/", mustWork = FALSE)
  fixture_dir <- normalizePath(fixture_dir, winslash = "/", mustWork = FALSE)
  launch <- sprintf(
    paste(
      "bash application/scripts/123_launch_joint_qdesn_screening_parallel_chunks.sh",
      "--registry %s",
      "--canonical-output-dir %s",
      "--fixture-dir %s",
      "--workers %d",
      "--n-cores-per-worker %d",
      "--session-prefix %s",
      "--run-id %s",
      "--incomplete-only true",
      "--dry-run false"
    ),
    shQuote(registry_path),
    shQuote(canonical_output_dir),
    shQuote(fixture_dir),
    as.integer(workers),
    as.integer(n_cores_per_worker),
    shQuote(session_prefix),
    shQuote(run_id)
  )
  dry_run <- sub("--dry-run false", "--dry-run true", launch, fixed = TRUE)
  audit <- sprintf(
    paste(
      "Rscript application/scripts/106_run_joint_qdesn_vb_spec_screening.R",
      "--registry %s",
      "--output-dir %s",
      "--fixture-dir %s",
      "--n-cores %d",
      "--reuse-completed true",
      "--audit-only true"
    ),
    shQuote(registry_path),
    shQuote(canonical_output_dir),
    shQuote(fixture_dir),
    as.integer(n_cores_per_worker)
  )
  data.frame(
    step = seq_len(4L),
    command_id = c(
      "dry_run_phase124_vb_completion",
      "launch_phase124_vb_completion",
      "audit_phase124_vb_completion",
      "prepare_phase124_mcmc_completion"
    ),
    command = c(
      dry_run,
      launch,
      audit,
      "After the VB audit passes, freeze the best missing-cell winners and run a Phase122-style MCMC completion only for those frozen rows."
    ),
    purpose = c(
      "Inspect chunk assignment without launching work.",
      "Launch the missing balanced-cell VB screening rows in tmux chunks.",
      "Build the canonical Phase124 VB screening summary after all chunks exit with EXIT_CODE=0.",
      "Do not launch MCMC from Phase124 until the missing-cell VB winners are frozen and manifest-verified."
    ),
    run_condition = c(
      "Optional sanity check before launch.",
      "Run now if enough compute is available and no duplicate sessions exist.",
      "Run only after all Phase124 worker logs show EXIT_CODE=0.",
      "Run in the next stage, not during preparation."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase124_mcmc_completion_plan <- function(missing_cells) {
  data.frame(
    step = seq_len(5L),
    stage = c("vb_screen", "vb_audit", "winner_freeze", "mcmc_completion", "balanced_article_freeze"),
    action = c(
      "Run the Phase124 registry produced from the missing balanced cells.",
      "Audit fit and forecast metrics, raw/contract crossings, convergence, runtimes, and manifests.",
      "Freeze one VB/VB-LD winner for each missing model-scenario cell under the existing per-case selection policy.",
      "Run a Phase122-style VB-initialized MCMC confirmation for the frozen missing-cell winners.",
      "Merge Phase122 existing MCMC rows with Phase124 MCMC completion rows into one balanced 32-cell article-candidate artifact."
    ),
    required_input = c(
      "phase124_vb_completion_registry.csv",
      "completed Phase124 fit/forecast manifests",
      "canonical Phase124 VB audit",
      "Phase124 missing-cell winner freeze",
      "Phase122 MCMC artifact plus Phase124 MCMC completion artifact"
    ),
    completion_gate = c(
      "all workers EXIT_CODE=0",
      "no implementation fail; contract crossings zero",
      "one finite candidate selected per missing cell",
      "chains finite; contract crossings zero; MCMC summaries finite",
      "all 32 scenario-model cells present and hash-manifested"
    ),
    n_missing_cells = nrow(missing_cells),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase124_readme <- function(run_config, health, gates) {
  c(
    "# Joint QDESN Phase 124 Balanced Completion",
    "",
    "This artifact prepares the missing model-scenario cells needed before promoting the final article validation table.",
    "Phase 123 confirmed the available MCMC rows, but it did not yield a balanced comparison of Joint QDESN, Independent QDESN, Joint exQDESN, and Independent exQDESN for every scenario.",
    "",
    sprintf("- Output directory: `%s`", run_config$out_dir[[1L]]),
    sprintf("- VB completion root: `%s`", run_config$vb_completion_dir[[1L]]),
    sprintf("- Missing cells: %d", run_config$n_missing_cells[[1L]]),
    sprintf("- Candidate rows: %d", run_config$n_candidate_rows[[1L]]),
    sprintf("- Proposed workers: %d", run_config$workers[[1L]]),
    "",
    "Decision:",
    "",
    sprintf("- Readiness decision: `%s`", run_config$readiness_decision[[1L]]),
    sprintf("- MCMC launch readiness: `%s`", health$status[health$component == "phase124_mcmc_readiness"][[1L]]),
    "",
    "Interpretation:",
    "",
    "Phase 124 should launch VB completion first.  MCMC is not launched from this preparation artifact because the missing cells do not yet have frozen VB/VB-LD winners.",
    "Once the VB completion audit passes, freeze the missing-cell winners and run a Phase122-style MCMC completion only for those rows.",
    "",
    "Gate summary:",
    "",
    paste(sprintf("- `%s`: `%s` - %s", gates$gate, gates$status, gates$detail), collapse = "\n")
  )
}

app_joint_qdesn_run_phase124_balanced_completion_prepare <- function(
  out_dir = app_joint_qdesn_default_phase124_balanced_completion_dir(),
  phase123_dir = app_joint_qdesn_default_phase123_mcmc_article_freeze_dir(),
  phase119_readiness_dir = app_joint_qdesn_default_phase119_case_readiness_dir(),
  vb_completion_dir = app_joint_qdesn_default_phase124_vb_completion_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  workers = 12L,
  n_cores_per_worker = 1L,
  run_id = "phase124_20260711",
  session_prefix = "joint_qdesn_phase124_vb_20260711"
) {
  out_dir <- normalizePath(out_dir, winslash = "/", mustWork = FALSE)
  vb_completion_dir <- normalizePath(vb_completion_dir, winslash = "/", mustWork = FALSE)
  fixture_dir <- normalizePath(fixture_dir, winslash = "/", mustWork = FALSE)
  app_ensure_dir(out_dir)
  app_ensure_dir(vb_completion_dir)

  sources <- app_joint_qdesn_phase124_load_sources(phase123_dir, phase119_readiness_dir)
  missing_cells <- app_joint_qdesn_phase124_missing_cells(sources$article_scope)
  registry <- app_joint_qdesn_phase124_build_registry(
    missing_cells,
    sources$source_registry,
    vb_output_dir = vb_completion_dir,
    n_cores = n_cores_per_worker
  )
  source_map <- app_joint_qdesn_phase124_candidate_source_map(registry)
  progress <- app_joint_qdesn_phase124_screening_progress(registry)
  gates <- app_joint_qdesn_phase124_gate_summary(sources, missing_cells, registry, progress)
  health <- app_joint_qdesn_phase124_health(missing_cells, registry, progress, gates)
  readiness_decision <- if (any(gates$status == "fail")) {
    "blocked_phase124_preparation_gate_failure"
  } else if (progress$incomplete_candidate_rows[[1L]] > 0L) {
    "ready_to_launch_phase124_vb_balanced_completion"
  } else {
    "phase124_vb_outputs_already_complete_ready_for_audit"
  }

  registry_path <- file.path(out_dir, "phase124_vb_completion_registry.csv")
  launch_plan <- app_joint_qdesn_phase124_launch_plan(
    registry_path = registry_path,
    canonical_output_dir = vb_completion_dir,
    fixture_dir = fixture_dir,
    workers = workers,
    n_cores_per_worker = n_cores_per_worker,
    run_id = run_id,
    session_prefix = session_prefix
  )
  mcmc_plan <- app_joint_qdesn_phase124_mcmc_completion_plan(missing_cells)
  run_config <- data.frame(
    run_id = "joint_qdesn_phase124_balanced_completion",
    out_dir = out_dir,
    phase123_dir = sources$phase123_dir,
    phase119_readiness_dir = sources$phase119_readiness_dir,
    vb_completion_dir = vb_completion_dir,
    fixture_dir = fixture_dir,
    workers = as.integer(workers),
    n_cores_per_worker = as.integer(n_cores_per_worker),
    worker_run_id = run_id,
    session_prefix = session_prefix,
    n_missing_cells = nrow(missing_cells),
    n_candidate_rows = nrow(registry),
    n_complete_candidate_rows = progress$complete_candidate_rows[[1L]],
    readiness_decision = readiness_decision,
    stringsAsFactors = FALSE
  )

  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qdesn_phase124_readme(run_config, health, gates), readme_path, useBytes = TRUE)
  source_manifest <- app_joint_qdesn_bind_rows(list(
    sources$phase123_manifest,
    sources$phase119_manifest
  ))
  paths <- c(
    run_config = app_joint_qdesn_phase124_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    source_manifest_verification = app_joint_qdesn_phase124_write_csv(source_manifest, file.path(out_dir, "source_manifest_verification.csv")),
    phase124_missing_cells = app_joint_qdesn_phase124_write_csv(missing_cells, file.path(out_dir, "phase124_missing_cells.csv")),
    phase124_vb_completion_registry = app_joint_qdesn_phase124_write_csv(registry, registry_path),
    phase124_candidate_source_map = app_joint_qdesn_phase124_write_csv(source_map, file.path(out_dir, "phase124_candidate_source_map.csv")),
    phase124_screening_progress = app_joint_qdesn_phase124_write_csv(progress, file.path(out_dir, "phase124_screening_progress.csv")),
    phase124_readiness_gate_summary = app_joint_qdesn_phase124_write_csv(gates, file.path(out_dir, "phase124_readiness_gate_summary.csv")),
    health_check_summary = app_joint_qdesn_phase124_write_csv(health, file.path(out_dir, "health_check_summary.csv")),
    phase124_screening_launch_plan = app_joint_qdesn_phase124_write_csv(launch_plan, file.path(out_dir, "phase124_screening_launch_plan.csv")),
    phase124_mcmc_completion_plan = app_joint_qdesn_phase124_write_csv(mcmc_plan, file.path(out_dir, "phase124_mcmc_completion_plan.csv")),
    provenance = app_joint_qdesn_phase124_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, winslash = "/", mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, winslash = "/", mustWork = TRUE),
    run_config = run_config,
    source_manifest = source_manifest,
    missing_cells = missing_cells,
    registry = registry,
    source_map = source_map,
    progress = progress,
    gates = gates,
    health = health,
    launch_plan = launch_plan,
    mcmc_plan = mcmc_plan,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path)
  )
}

# Phase 124b freezes one VB/VB-LD winner for each Phase 124 missing balanced
# cell.  The output intentionally follows the Phase 121 freeze contract so the
# existing Phase 122 MCMC confirmation runner can consume it unchanged.

app_joint_qdesn_default_phase124b_missing_cell_vb_freeze_dir <- function() {
  app_path("application/cache/joint_qdesn_phase124b_missing_cell_vb_winner_freeze_20260711")
}

app_joint_qdesn_default_phase124c_mcmc_completion_dir <- function() {
  app_path("application/cache/joint_qdesn_phase124c_mcmc_balanced_completion_20260711")
}

app_joint_qdesn_phase124b_source_dirs <- function(
  phase124_prepare_dir = app_joint_qdesn_default_phase124_balanced_completion_dir(),
  phase124_vb_dir = app_joint_qdesn_default_phase124_vb_completion_dir()
) {
  list(
    phase124_prepare_dir = normalizePath(phase124_prepare_dir, winslash = "/", mustWork = TRUE),
    phase124_vb_dir = normalizePath(phase124_vb_dir, winslash = "/", mustWork = TRUE)
  )
}

app_joint_qdesn_phase124b_missing_cell_coverage <- function(missing_cells, candidate_audit, winners) {
  app_check_required_columns(missing_cells, c("case_id", "scenario_id", "source_model_id"), "Phase 124 missing cells")
  candidate_cases <- unique(candidate_audit$case_id)
  winner_cases <- unique(winners$case_id)
  out <- missing_cells[, c("case_id", "scenario_id", "source_model_id"), drop = FALSE]
  out$n_candidate_rows <- as.integer(table(factor(candidate_audit$case_id, levels = out$case_id)))
  out$winner_selected <- out$case_id %in% winner_cases
  out$coverage_status <- ifelse(out$n_candidate_rows > 0 & out$winner_selected, "pass", "fail")
  out
}

app_joint_qdesn_phase124b_gate_audit <- function(
  prepare_manifest,
  source_health,
  candidate_audit,
  winners,
  coverage
) {
  base <- app_joint_qdesn_phase121_gate_audit(source_health, candidate_audit, winners)
  prepare_manifest_status <- if (nrow(prepare_manifest) && all(prepare_manifest$status == "pass")) "pass" else "fail"
  coverage_status <- if (nrow(coverage) && all(coverage$coverage_status == "pass")) "pass" else "fail"
  n_winners <- nrow(winners)
  n_missing <- nrow(coverage)
  extra <- data.frame(
    gate = c(
      "phase124_prepare_manifest",
      "missing_cell_coverage",
      "phase124c_mcmc_launch_readiness",
      "balanced_article_promotion"
    ),
    status = c(
      prepare_manifest_status,
      coverage_status,
      if (prepare_manifest_status == "pass" &&
        coverage_status == "pass" &&
        n_winners == n_missing &&
        !any(winners$phase121_selection_status == "fail", na.rm = TRUE) &&
        sum(winners$forecast_contract_crossing_pairs, winners$fit_contract_crossing_pairs, na.rm = TRUE) == 0L) "review" else "fail",
      "review"
    ),
    detail = c(
      sprintf("%d/%d Phase 124 preparation manifest rows pass.", sum(prepare_manifest$status == "pass"), nrow(prepare_manifest)),
      sprintf("%d/%d missing balanced cells have candidate rows and a selected winner.", sum(coverage$coverage_status == "pass"), nrow(coverage)),
      "Ready to launch Phase124c MCMC for frozen missing-cell winners; selected raw crossings and max-iteration flags remain review diagnostics.",
      "Article promotion remains blocked until Phase122 and Phase124c MCMC rows are merged into a balanced 32-cell artifact."
    ),
    stringsAsFactors = FALSE
  )
  app_joint_qdesn_bind_rows(list(extra, base))
}

app_joint_qdesn_phase124b_mcmc_launch_plan <- function(
  phase124b_dir = app_joint_qdesn_default_phase124b_missing_cell_vb_freeze_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  mcmc_out_dir = app_joint_qdesn_default_phase124c_mcmc_completion_dir(),
  n_cores = 12L,
  n_chains = 2L,
  mcmc_n_iter = 1200L,
  mcmc_burn = 600L,
  mcmc_thin = 10L
) {
  launch_cmd <- sprintf(
    paste(
      "Rscript application/scripts/125_run_joint_qdesn_phase122_mcmc_case_confirmation.R",
      "--phase121-dir %s",
      "--fixture-dir %s",
      "--output-dir %s",
      "--n-chains %d",
      "--mcmc-n-iter %d",
      "--mcmc-burn %d",
      "--mcmc-thin %d",
      "--n-cores %d"
    ),
    shQuote(normalizePath(phase124b_dir, winslash = "/", mustWork = FALSE)),
    shQuote(normalizePath(fixture_dir, winslash = "/", mustWork = FALSE)),
    shQuote(normalizePath(mcmc_out_dir, winslash = "/", mustWork = FALSE)),
    as.integer(n_chains),
    as.integer(mcmc_n_iter),
    as.integer(mcmc_burn),
    as.integer(mcmc_thin),
    as.integer(n_cores)
  )
  tmux_log <- paste0(normalizePath(mcmc_out_dir, winslash = "/", mustWork = FALSE), "_tmux.log")
  tmux_cmd <- sprintf(
    "tmux new-session -d -s %s %s",
    shQuote("joint_qdesn_phase124c_mcmc_20260711"),
    shQuote(sprintf(
      "cd %s && { echo START $(date -Is); %s; ec=$?; echo EXIT_CODE=${ec}; echo END $(date -Is); exit ${ec}; } > %s 2>&1",
      shQuote(app_repo_root()),
      launch_cmd,
      shQuote(tmux_log)
    ))
  )
  audit_cmd <- sprintf(
    "Rscript application/scripts/126_freeze_joint_qdesn_phase123_mcmc_article_candidate.R --phase122-dir %s --output-dir %s",
    shQuote(normalizePath(mcmc_out_dir, winslash = "/", mustWork = FALSE)),
    shQuote(app_path("application/cache/joint_qdesn_phase124d_mcmc_completion_audit_20260711"))
  )
  data.frame(
    step = seq_len(4L),
    command_id = c(
      "launch_phase124c_mcmc_completion",
      "launch_phase124c_mcmc_completion_tmux",
      "audit_phase124c_mcmc_completion",
      "merge_phase122_phase124c_balanced_grid"
    ),
    command = c(
      launch_cmd,
      tmux_cmd,
      audit_cmd,
      "After Phase124c passes, merge Phase122's 17 rows and Phase124c's 15 rows into a balanced 32-cell article-candidate artifact."
    ),
    purpose = c(
      "Run MCMC confirmation for only the 15 missing balanced cells.",
      "Detached version of the same MCMC launch with START/EXIT_CODE/END logging.",
      "Produce an MCMC confirmation audit for the Phase124c completion artifact.",
      "Create final balanced article evidence before manuscript table promotion."
    ),
    run_condition = c(
      "Run after Phase124b freeze manifest verifies.",
      "Use this for long-running background execution.",
      "Run after the Phase124c log ends with EXIT_CODE=0.",
      "Run only after Phase124c MCMC gate has no fail rows."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase124b_next_action_plan <- function() {
  data.frame(
    step = seq_len(5L),
    stage = c(
      "phase124c_mcmc_completion",
      "phase124c_health_audit",
      "balanced_grid_merge",
      "article_asset_rebuild",
      "manuscript_promotion"
    ),
    action = c(
      "Initialize MCMC from the 15 frozen Phase124b missing-cell VB/VB-LD winners.",
      "Audit chains, VB-to-MCMC distances, raw/contract crossings, quantile-grid metrics, and manifests.",
      "Merge Phase122's existing 17 MCMC rows with the 15 Phase124c rows.",
      "Rebuild article validation tables and figures from the balanced 32-cell MCMC artifact.",
      "Update the manuscript only after the balanced artifact passes implementation gates and review diagnostics are documented."
    ),
    gate = c(
      "Phase124b manifest pass and no selected hard failures.",
      "No worker failures, finite draws/scores, zero contract crossings, source manifests pass.",
      "Every scenario-model cell present exactly once.",
      "Generated tables/figures hash-manifested and checked against predictive-contract wording.",
      "Article-safe diff only; no application refactors."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase124b_readme <- function(run_config, gate_audit, winners, coverage, launch_plan) {
  c(
    "# Joint QDESN Phase 124b Missing-Cell VB Winner Freeze",
    "",
    "This artifact freezes one VB/VB-LD winner for each missing model-scenario cell from the Phase 124 balanced-completion screen.",
    "It intentionally writes a Phase121-compatible `case_winner_controls.csv` so the existing Phase122 MCMC confirmation runner can consume the artifact unchanged.",
    "",
    sprintf("- Output directory: `%s`", run_config$out_dir[[1L]]),
    sprintf("- Phase124 preparation source: `%s`", run_config$phase124_prepare_dir[[1L]]),
    sprintf("- Phase124 VB source: `%s`", run_config$phase124_vb_dir[[1L]]),
    sprintf("- Missing cells covered: %d/%d", sum(coverage$coverage_status == "pass"), nrow(coverage)),
    sprintf("- Winners frozen: %d", nrow(winners)),
    sprintf("- Winner gates: %d pass, %d review, %d fail.", run_config$n_pass_winners[[1L]], run_config$n_review_winners[[1L]], run_config$n_fail_winners[[1L]]),
    sprintf("- Freeze status: `%s`", run_config$freeze_status[[1L]]),
    "",
    "Interpretation:",
    "",
    "The Phase124b winners are suitable as VB initializers for MCMC completion.  They are not final article evidence.",
    "Review flags are retained for raw crossings and VB max-iteration diagnostics.  Contract quantiles remain noncrossing.",
    "",
    "Gate summary:",
    paste(sprintf("- `%s`: `%s` - %s", gate_audit$gate, gate_audit$status, gate_audit$detail), collapse = "\n"),
    "",
    "Next executable command:",
    "",
    launch_plan$command[launch_plan$command_id == "launch_phase124c_mcmc_completion_tmux"][[1L]]
  )
}

app_joint_qdesn_run_phase124b_missing_cell_vb_winner_freeze <- function(
  out_dir = app_joint_qdesn_default_phase124b_missing_cell_vb_freeze_dir(),
  phase124_prepare_dir = app_joint_qdesn_default_phase124_balanced_completion_dir(),
  phase124_vb_dir = app_joint_qdesn_default_phase124_vb_completion_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  mcmc_out_dir = app_joint_qdesn_default_phase124c_mcmc_completion_dir(),
  forecast_mae_abs_tolerance = 5.0e-4,
  forecast_mae_rel_tolerance = 0.005,
  n_cores = 12L,
  n_chains = 2L,
  mcmc_n_iter = 1200L,
  mcmc_burn = 600L,
  mcmc_thin = 10L
) {
  out_dir <- normalizePath(out_dir, winslash = "/", mustWork = FALSE)
  app_ensure_dir(out_dir)
  dirs <- app_joint_qdesn_phase124b_source_dirs(phase124_prepare_dir, phase124_vb_dir)
  fixture_dir <- normalizePath(fixture_dir, winslash = "/", mustWork = FALSE)
  mcmc_out_dir <- normalizePath(mcmc_out_dir, winslash = "/", mustWork = FALSE)

  prepare_manifest <- app_joint_qdesn_phase124_manifest_verify(dirs$phase124_prepare_dir, "phase124_balanced_completion_prepare")
  missing_cells <- app_read_csv(file.path(dirs$phase124_prepare_dir, "phase124_missing_cells.csv"))
  shard <- app_joint_qdesn_phase120_read_screening_shard(dirs$phase124_vb_dir, "phase124_vb_completion")
  shards <- list(phase124_vb_completion = shard)
  source_health <- app_joint_qdesn_phase120_source_health_summary(shards)
  source_manifest <- app_joint_qdesn_bind_rows(list(
    app_joint_qdesn_phase120_add_source(shard$root_manifest_verification, "phase124_vb_completion_root"),
    app_joint_qdesn_phase120_add_source(shard$candidate_manifest_verification, "phase124_vb_completion_nested"),
    app_joint_qdesn_phase120_add_source(prepare_manifest, "phase124_prepare")
  ))
  candidate_audit <- app_joint_qdesn_phase121_candidate_audit(shards)
  candidate_audit <- candidate_audit[candidate_audit$case_id %in% missing_cells$case_id, , drop = FALSE]
  winners <- app_joint_qdesn_phase121_select_case_winners(
    candidate_audit,
    abs_tol = forecast_mae_abs_tolerance,
    rel_tol = forecast_mae_rel_tolerance
  )
  winners$phase124b_selection_status <- winners$phase121_selection_status
  winners$phase124b_selection_rule <- winners$phase121_selection_rule
  winners$phase124b_freeze_role <- ifelse(
    winners$phase121_selection_status == "fail",
    "blocked",
    ifelse(winners$phase121_selection_status == "pass", "missing_cell_vb_winner_ready_for_mcmc", "missing_cell_vb_winner_review_ready_for_mcmc")
  )
  coverage <- app_joint_qdesn_phase124b_missing_cell_coverage(missing_cells, candidate_audit, winners)
  controls <- app_joint_qdesn_phase121_winner_controls(winners)
  metric_summary <- app_joint_qdesn_phase121_winner_metric_summary(winners)
  gate_audit <- app_joint_qdesn_phase124b_gate_audit(prepare_manifest, source_health, candidate_audit, winners, coverage)
  launch_plan <- app_joint_qdesn_phase124b_mcmc_launch_plan(
    phase124b_dir = out_dir,
    fixture_dir = fixture_dir,
    mcmc_out_dir = mcmc_out_dir,
    n_cores = n_cores,
    n_chains = n_chains,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin
  )
  next_action <- app_joint_qdesn_phase124b_next_action_plan()
  selected_contract_crossings <- sum(winners$forecast_contract_crossing_pairs, winners$fit_contract_crossing_pairs, na.rm = TRUE)
  selected_raw_crossings <- sum(winners$forecast_raw_crossing_pairs, winners$fit_raw_crossing_pairs, na.rm = TRUE)
  selected_max_iter <- sum(winners$forecast_reached_max_iter, winners$fit_reached_max_iter, na.rm = TRUE)
  freeze_status <- if (any(gate_audit$status == "fail")) {
    "fail_blocked_before_phase124c_mcmc"
  } else if (any(gate_audit$status == "review")) {
    "review_ready_for_phase124c_mcmc_completion"
  } else {
    "pass_ready_for_phase124c_mcmc_completion"
  }
  run_config <- data.frame(
    run_id = "joint_qdesn_phase124b_missing_cell_vb_winner_freeze",
    out_dir = out_dir,
    phase124_prepare_dir = dirs$phase124_prepare_dir,
    phase124_vb_dir = dirs$phase124_vb_dir,
    fixture_dir = fixture_dir,
    mcmc_out_dir = mcmc_out_dir,
    n_candidate_rows = nrow(candidate_audit),
    n_missing_cells = nrow(missing_cells),
    n_case_winners = nrow(winners),
    n_pass_winners = sum(winners$phase121_selection_status == "pass", na.rm = TRUE),
    n_review_winners = sum(winners$phase121_selection_status == "review", na.rm = TRUE),
    n_fail_winners = sum(winners$phase121_selection_status == "fail", na.rm = TRUE),
    selected_contract_crossings = selected_contract_crossings,
    selected_raw_crossings = selected_raw_crossings,
    selected_max_iter_flags = selected_max_iter,
    forecast_mae_abs_tolerance = as.numeric(forecast_mae_abs_tolerance),
    forecast_mae_rel_tolerance = as.numeric(forecast_mae_rel_tolerance),
    freeze_status = freeze_status,
    mcmc_promotion_status = "ready_to_launch_phase124c_missing_cell_mcmc_completion_review",
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qdesn_phase124b_readme(run_config, gate_audit, winners, coverage, launch_plan), readme_path, useBytes = TRUE)
  paths <- c(
    phase124b_run_config = app_joint_qdesn_phase124_write_csv(run_config, file.path(out_dir, "phase124b_run_config.csv")),
    source_manifest_verification = app_joint_qdesn_phase124_write_csv(source_manifest, file.path(out_dir, "source_manifest_verification.csv")),
    source_health_summary = app_joint_qdesn_phase124_write_csv(source_health, file.path(out_dir, "source_health_summary.csv")),
    phase124_missing_cell_coverage = app_joint_qdesn_phase124_write_csv(coverage, file.path(out_dir, "phase124_missing_cell_coverage.csv")),
    combined_candidate_audit = app_joint_qdesn_phase124_write_csv(candidate_audit, file.path(out_dir, "combined_candidate_audit.csv")),
    case_winner_selection = app_joint_qdesn_phase124_write_csv(winners, file.path(out_dir, "case_winner_selection.csv")),
    case_winner_controls = app_joint_qdesn_phase124_write_csv(controls, file.path(out_dir, "case_winner_controls.csv")),
    case_winner_metric_summary = app_joint_qdesn_phase124_write_csv(metric_summary, file.path(out_dir, "case_winner_metric_summary.csv")),
    case_winner_gate_audit = app_joint_qdesn_phase124_write_csv(gate_audit, file.path(out_dir, "case_winner_gate_audit.csv")),
    mcmc_completion_launch_plan = app_joint_qdesn_phase124_write_csv(launch_plan, file.path(out_dir, "mcmc_completion_launch_plan.csv")),
    next_action_plan = app_joint_qdesn_phase124_write_csv(next_action, file.path(out_dir, "next_action_plan.csv")),
    provenance = app_joint_qdesn_phase124_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, winslash = "/", mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, winslash = "/", mustWork = TRUE),
    run_config = run_config,
    source_manifest_verification = source_manifest,
    source_health = source_health,
    coverage = coverage,
    candidate_audit = candidate_audit,
    winners = winners,
    controls = controls,
    metric_summary = metric_summary,
    gate_audit = gate_audit,
    launch_plan = launch_plan,
    next_action_plan = next_action,
    paths = c(paths, artifact_manifest = manifest_info$manifest_path)
  )
}
