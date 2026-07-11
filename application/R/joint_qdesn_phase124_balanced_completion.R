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
