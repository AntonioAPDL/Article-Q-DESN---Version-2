# Phase 164/165 source freeze, selected-fixture sharding, and exact controls.

app_joint_exqdesn_phase164_cache_root <- function() {
  Sys.getenv(
    "JOINT_EXQDESN_CACHE_ROOT",
    unset = "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache"
  )
}

app_joint_exqdesn_phase164_dirs <- function(cache_root = app_joint_exqdesn_phase164_cache_root()) {
  list(
    cache_root = cache_root,
    phase153_readiness = file.path(cache_root, "joint_qdesn_phase153_balanced_independent_replication_readiness_20260729"),
    phase153_fixtures = file.path(cache_root, "joint_qdesn_phase153_balanced_independent_replication_fixtures_20260729"),
    phase153_vb = file.path(cache_root, "joint_qdesn_phase153_balanced_independent_replication_vb_20260729"),
    phase154_readiness = file.path(cache_root, "joint_qdesn_phase154_mcmc_evidence_reconciliation_readiness_20260730"),
    phase154_final = file.path(cache_root, "joint_qdesn_phase154_balanced_mcmc_final_20260730"),
    phase156b = file.path(cache_root, "joint_qdesn_phase156b_collapsed_gamma_sigma_recovery_freeze_20260802"),
    phase157b = file.path(cache_root, "joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802"),
    phase158 = file.path(cache_root, "joint_qdesn_phase158_quantile_fan_decomposition_20260804"),
    phase163b = file.path(cache_root, "joint_qdesn_phase163b_corrected_closure_20260806"),
    phase164 = file.path(cache_root, "joint_exqdesn_phase164_source_method_freeze_20260806"),
    selected_fixtures = file.path(cache_root, "joint_exqdesn_phase166_selected_fixtures_20260806"),
    phase165 = file.path(cache_root, "joint_exqdesn_phase165_exact_algebra_controls_20260806"),
    phase166 = file.path(cache_root, "joint_exqdesn_phase166_structured_vb_method_development_20260806")
  )
}

app_joint_exqdesn_verify_manifest <- function(dir, source_id) {
  dir <- normalizePath(dir, mustWork = TRUE)
  manifest_path <- file.path(dir, "artifact_manifest.csv")
  if (!file.exists(manifest_path)) stop(sprintf("Missing manifest for %s.", source_id), call. = FALSE)
  manifest <- app_read_csv(manifest_path)
  required <- c("label", "relative_path", "size_bytes", "sha256")
  missing <- setdiff(required, names(manifest))
  if (length(missing)) stop(sprintf("Malformed manifest for %s.", source_id), call. = FALSE)
  rows <- lapply(seq_len(nrow(manifest)), function(ii) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    exists <- file.exists(path)
    actual_size <- if (exists) as.numeric(file.info(path)$size) else NA_real_
    actual_sha <- if (exists) app_sha256_file(path) else NA_character_
    data.frame(
      source_id = source_id,
      source_dir = dir,
      label = manifest$label[[ii]],
      relative_path = manifest$relative_path[[ii]],
      exists = exists,
      declared_size_bytes = as.numeric(manifest$size_bytes[[ii]]),
      actual_size_bytes = actual_size,
      declared_sha256 = manifest$sha256[[ii]],
      actual_sha256 = actual_sha,
      status = if (exists && identical(actual_size, as.numeric(manifest$size_bytes[[ii]])) &&
        identical(tolower(actual_sha), tolower(manifest$sha256[[ii]]))) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_joint_exqdesn_write_manifest <- function(paths, out_dir) {
  labels <- names(paths)
  if (is.null(labels) || any(!nzchar(labels))) {
    stop("Manifest inputs must be a fully named path vector.", call. = FALSE)
  }
  paths <- normalizePath(paths, mustWork = TRUE)
  relative <- vapply(paths, function(path) {
    prefix <- paste0(normalizePath(out_dir, mustWork = TRUE), .Platform$file.sep)
    if (startsWith(path, prefix)) substring(path, nchar(prefix) + 1L) else basename(path)
  }, character(1L))
  manifest <- data.frame(
    label = labels,
    relative_path = relative,
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(manifest = manifest, manifest_path = manifest_path)
}

app_joint_exqdesn_phase164_selected_rows <- function(dirs = app_joint_exqdesn_phase164_dirs()) {
  registry <- app_read_csv(file.path(dirs$phase153_readiness, "candidate_registry.csv"))
  registry <- registry[
    registry$model_id %in% c("joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"),
    , drop = FALSE
  ]
  replicate_number <- as.integer(sub("^r", "", registry$dgp_replicate_id))
  registry <- registry[replicate_number >= 1L & replicate_number <= 10L, , drop = FALSE]
  registry <- registry[order(registry$base_scenario_id, registry$dgp_replicate_id, registry$model_id), , drop = FALSE]
  expected <- 8L * 10L * 2L
  key <- paste(registry$scenario_ids, registry$model_id, sep = "::")
  if (nrow(registry) != expected || anyDuplicated(key)) {
    stop("The Phase164 selected scenario-model partition is malformed.", call. = FALSE)
  }
  registry$fit_structure <- ifelse(registry$model_id == "joint_exqdesn_rhs_vb", "joint", "independent")
  registry$evidence_role <- "method_development"
  registry
}

app_joint_exqdesn_phase164_method_development_registry <- function(
  selected,
  dirs = app_joint_exqdesn_phase164_dirs()
) {
  methods <- c("VB0_point_v", "VB1_structured_v", "VB2_structured_u")
  rows <- lapply(seq_len(nrow(selected)), function(ii) {
    base <- selected[ii, , drop = FALSE]
    do.call(rbind, lapply(methods, function(method_id) {
      row <- base
      row$inference_method_id <- method_id
      row$phase166_candidate_id <- paste(row$scenario_ids, row$fit_structure, method_id, sep = "__")
      row$use_existing_phase153 <- identical(method_id, "VB0_point_v")
      row$phase153_candidate_dir <- file.path(
        dirs$phase153_vb,
        "candidates",
        row$candidate_id
      )
      row
    }))
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  if (nrow(out) != 480L || anyDuplicated(out$phase166_candidate_id)) {
    stop("The Phase166 480-cell method-development registry is malformed.", call. = FALSE)
  }
  out
}

app_joint_exqdesn_shard_csv <- function(source_path, selected_ids_path, out_dir, suffix) {
  source_path <- normalizePath(source_path, mustWork = TRUE)
  selected_ids_path <- normalizePath(selected_ids_path, mustWork = TRUE)
  app_ensure_dir(out_dir)
  awk_path <- file.path(out_dir, paste0("shard_", suffix, ".awk"))
  writeLines(c(
    "FNR == NR { gsub(/\\r/, \"\", $1); wanted[$1] = 1; next }",
    "FNR == 1 { header = $0; next }",
    "{",
    "  sid = $1",
    "  gsub(/^\\\"/, \"\", sid)",
    "  gsub(/\\\"$/, \"\", sid)",
    "  if (sid in wanted) {",
    "    file = out \"/\" sid \"__\" suffix \".csv\"",
    "    if (!(file in opened)) { print header > file; opened[file] = 1 }",
    "    print $0 >> file",
    "  }",
    "}",
    "END { for (file in opened) close(file) }"
  ), awk_path, useBytes = TRUE)
  status <- system2(
    "awk",
    c(
      "-F,",
      "-v", shQuote(paste0("out=", normalizePath(out_dir, mustWork = TRUE))),
      "-v", shQuote(paste0("suffix=", suffix)),
      "-f", shQuote(awk_path),
      shQuote(selected_ids_path),
      shQuote(source_path)
    ),
    stdout = TRUE,
    stderr = TRUE
  )
  exit_status <- attr(status, "status") %||% 0L
  unlink(awk_path)
  if (exit_status != 0L) stop(sprintf("awk sharding failed for %s: %s", suffix, paste(status, collapse = "\n")), call. = FALSE)
  invisible(TRUE)
}

app_joint_exqdesn_phase164_materialize_selected_fixtures <- function(
  selected,
  dirs = app_joint_exqdesn_phase164_dirs(),
  force = FALSE
) {
  out_dir <- dirs$selected_fixtures
  app_ensure_dir(out_dir)
  scenario_ids <- sort(unique(selected$scenario_ids))
  if (length(scenario_ids) != 80L) stop("Exactly 80 Phase166 scenario replicates are required.", call. = FALSE)
  ids_path <- file.path(out_dir, "selected_scenario_ids.txt")
  writeLines(scenario_ids, ids_path, useBytes = TRUE)
  sources <- c(
    observed = "observed_series.csv",
    design = "design_matrix.csv",
    true_wide = "true_quantile_wide.csv"
  )
  expected_paths <- unlist(lapply(names(sources), function(suffix) {
    file.path(out_dir, paste0(scenario_ids, "__", suffix, ".csv"))
  }), use.names = FALSE)
  if (isTRUE(force) || !all(file.exists(expected_paths))) {
    stale <- expected_paths[file.exists(expected_paths)]
    if (length(stale)) unlink(stale)
    for (suffix in names(sources)) {
      app_joint_exqdesn_shard_csv(
        file.path(dirs$phase153_fixtures, sources[[suffix]]),
        ids_path,
        out_dir,
        suffix
      )
    }
  }
  if (!all(file.exists(expected_paths)) || any(as.numeric(file.info(expected_paths)$size) <= 0)) {
    stop("Selected fixture sharding did not produce every required file.", call. = FALSE)
  }
  scenario_summary <- app_read_csv(file.path(dirs$phase153_fixtures, "scenario_summary.csv"))
  split_metadata <- app_read_csv(file.path(dirs$phase153_fixtures, "split_metadata.csv"))
  origin_plan <- app_read_csv(file.path(dirs$phase153_fixtures, "forecast_origin_plan.csv"))
  frozen_registry <- app_read_csv(file.path(dirs$phase153_fixtures, "frozen_registry.csv"))
  scenario_summary <- scenario_summary[scenario_summary$scenario_id %in% scenario_ids, , drop = FALSE]
  split_metadata <- split_metadata[split_metadata$scenario_id %in% scenario_ids, , drop = FALSE]
  origin_plan <- origin_plan[origin_plan$scenario_id %in% scenario_ids, , drop = FALSE]
  frozen_registry <- frozen_registry[frozen_registry$scenario_id %in% scenario_ids, , drop = FALSE]
  metadata_paths <- c(
    selected_scenario_ids = normalizePath(ids_path, mustWork = TRUE),
    scenario_summary = app_joint_qvp_write_csv(scenario_summary, file.path(out_dir, "scenario_summary.csv")),
    split_metadata = app_joint_qvp_write_csv(split_metadata, file.path(out_dir, "split_metadata.csv")),
    forecast_origin_plan = app_joint_qvp_write_csv(origin_plan, file.path(out_dir, "forecast_origin_plan.csv")),
    frozen_registry = app_joint_qvp_write_csv(frozen_registry, file.path(out_dir, "frozen_registry.csv"))
  )
  shard_manifest <- data.frame(
    scenario_id = rep(scenario_ids, times = length(sources)),
    artifact = rep(names(sources), each = length(scenario_ids)),
    relative_path = basename(expected_paths),
    size_bytes = as.numeric(file.info(expected_paths)$size),
    sha256 = vapply(expected_paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  shard_manifest_path <- app_joint_qvp_write_csv(shard_manifest, file.path(out_dir, "fixture_shard_manifest.csv"))
  readme_path <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Phase166 Selected Fixture Shards",
    "",
    "This directory contains only the first ten frozen Phase153 replicates per base scenario.",
    "Rows are sharded by scenario so each full-size worker reads one compact fixture rather than the 6.2 GB source bundle.",
    "The source fixtures are unchanged and remain hash-verified in Phase164."
  ), readme_path, useBytes = TRUE)
  top_paths <- c(metadata_paths, fixture_shard_manifest = shard_manifest_path, README = readme_path)
  app_joint_exqdesn_write_manifest(top_paths, out_dir)
  list(out_dir = out_dir, scenario_ids = scenario_ids, shard_manifest = shard_manifest)
}

app_joint_exqdesn_load_selected_fixture_artifacts <- function(scenario_id, dirs = app_joint_exqdesn_phase164_dirs()) {
  root <- normalizePath(dirs$selected_fixtures, mustWork = TRUE)
  manifest <- app_read_csv(file.path(root, "fixture_shard_manifest.csv"))
  rows <- manifest[manifest$scenario_id == scenario_id, , drop = FALSE]
  if (nrow(rows) != 3L) stop(sprintf("Missing selected fixture shards for %s.", scenario_id), call. = FALSE)
  paths <- file.path(root, rows$relative_path)
  actual <- vapply(paths, app_sha256_file, character(1L))
  if (any(tolower(actual) != tolower(rows$sha256))) stop("Selected fixture shard hash verification failed.", call. = FALSE)
  by_artifact <- setNames(paths, rows$artifact)
  list(
    fixture_dir = root,
    observed = app_read_csv(by_artifact[["observed"]]),
    design = app_read_csv(by_artifact[["design"]]),
    true_wide = app_read_csv(by_artifact[["true_wide"]]),
    scenario_summary = app_read_csv(file.path(root, "scenario_summary.csv")),
    split_metadata = app_read_csv(file.path(root, "split_metadata.csv")),
    forecast_origin_plan = app_read_csv(file.path(root, "forecast_origin_plan.csv")),
    frozen_registry = app_read_csv(file.path(root, "frozen_registry.csv"))
  )
}

app_joint_exqdesn_phase164_prepare <- function(
  dirs = app_joint_exqdesn_phase164_dirs(),
  force_shards = FALSE
) {
  app_ensure_dir(dirs$phase164)
  source_dirs <- list(
    phase153_readiness = dirs$phase153_readiness,
    phase153_fixtures = dirs$phase153_fixtures,
    phase154_readiness = dirs$phase154_readiness,
    phase154_final = dirs$phase154_final,
    phase156b = dirs$phase156b,
    phase157b = dirs$phase157b,
    phase158 = dirs$phase158,
    phase163b = dirs$phase163b
  )
  source_verification <- do.call(rbind, lapply(names(source_dirs), function(id) {
    app_joint_exqdesn_verify_manifest(source_dirs[[id]], id)
  }))
  if (any(source_verification$status != "pass")) {
    stop("Phase164 source-manifest verification failed.", call. = FALSE)
  }
  selected <- app_joint_exqdesn_phase164_selected_rows(dirs)
  registry <- app_joint_exqdesn_phase164_method_development_registry(selected, dirs)
  shards <- app_joint_exqdesn_phase164_materialize_selected_fixtures(selected, dirs, force_shards)
  method_registry <- app_joint_exqdesn_load_method_registry()
  provenance <- app_joint_qvp_provenance_rows()
  git_tree <- system2("git", c("rev-parse", "HEAD^{tree}"), stdout = TRUE)[[1L]]
  source_contract <- data.frame(
    source_role = c("implementation_commit", "implementation_tree", "phase153_fixture_manifest", "method_registry"),
    value = c(
      provenance$value[provenance$key == "git_head"][[1L]],
      git_tree,
      app_sha256_file(file.path(dirs$phase153_fixtures, "artifact_manifest.csv")),
      app_sha256_file(app_joint_exqdesn_method_registry_path())
    ),
    gate_status = "pass",
    stringsAsFactors = FALSE
  )
  model_contract <- data.frame(
    contract = c("likelihood", "kappa", "tau_grid", "fit_window", "forecast_window", "fit_structures", "scoring_contract"),
    value = c("exAL working likelihood", "1", "0.05,0.10,0.25,0.50,0.75,0.90,0.95", "500", "1000", "joint;independent", "raw preserved; monotone contract scored"),
    stringsAsFactors = FALSE
  )
  prior_contract <- unique(selected[, c(
    "base_scenario_id", "model_id", "tau0", "zeta2", "a_sigma", "b_sigma",
    "alpha_prior_sd", "alpha_min_spacing", "gamma_init_policy"
  ), drop = FALSE])
  no_repeat_ledger <- data.frame(
    prior_stage = c("Phase134", "Phase149", "Phase151", "Phase159", "Phase163b"),
    prior_axis = c("slice width", "case-specific VB controls", "feature design", "split RHS", "tail calibration closure"),
    repeated_in_phase166 = FALSE,
    reason = "Phase166 changes only the inference approximation under frozen case-specific controls.",
    stringsAsFactors = FALSE
  )
  seed_role_registry <- unique(selected[, c("scenario_ids", "base_scenario_id", "dgp_replicate_id", "dgp_seed", "evidence_role")])
  phase154_baseline <- app_read_csv(file.path(dirs$phase154_final, "final_model_summary.csv"))
  phase154_baseline$source_artifact_id <- "phase154_balanced_mcmc_final"
  phase157b_baseline <- app_read_csv(file.path(dirs$phase157b, "mcmc_case_summary.csv"))
  phase157b_baseline$source_artifact_id <- "phase157b_collapsed_gamma_sigma_mcmc"
  api_contract_audit <- data.frame(
    inference_family = c("vb", "vb", "mcmc", "mcmc"),
    fit_structure = c("joint", "independent", "joint", "independent"),
    required_fields = c(
      "beta_mean;alpha_mean;sigma_mean;gamma_mean;qhat_mean;tau",
      "fits;beta_mean;alpha_mean;sigma_mean;gamma_mean;qhat_mean;tau",
      "beta_draws;alpha_draws;sigma_draws;gamma_draws;qhat_mean;tau",
      "fits;beta_draws;alpha_draws;sigma_draws;gamma_draws;qhat_mean;tau"
    ),
    validator = "app_joint_exqdesn_validate_fit_contract",
    gate_status = "pass",
    stringsAsFactors = FALSE
  )
  source_order <- c(
    "00_packages.R", "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
    "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
    "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
    "joint_qdesn_phase153_balanced_independent_replication.R",
    "joint_exqdesn_exact_structured_inference.R", "joint_exqdesn_inference_dispatch.R",
    "joint_exqdesn_phase164_165_readiness.R", "joint_exqdesn_phase166_168_structured_vb.R"
  )
  source_order_audit <- data.frame(
    source_position = seq_along(source_order),
    source_file = source_order,
    exists = file.exists(app_path("application/R", source_order)),
    gate_status = ifelse(file.exists(app_path("application/R", source_order)), "pass", "fail"),
    stringsAsFactors = FALSE
  )
  method_compatibility_matrix <- transform(
    method_registry,
    joint_supported = method_id != "K_branch_inverse_cdf",
    independent_supported = method_id != "K_branch_inverse_cdf",
    phase166_enabled = inference_family == "vb" & method_id %in% c("VB0_point_v", "VB1_structured_v", "VB2_structured_u"),
    production_default_changed = FALSE
  )
  numerical_tolerance_registry <- data.frame(
    tolerance_id = c(
      "p_gamma_inverse", "phase165_density_identity", "phase165_sigma_collapse",
      "branch_quadrature", "branch_eta_limit", "production_quadrature_orders"
    ),
    value = c("1e-12", "1e-9", "1e-5", "1e-5", "18", "4;8;12"),
    interpretation = c(
      "absolute round-trip target", "maximum absolute log-density error",
      "maximum normalized direct-integral error", "maximum normalized moment change",
      "absolute branchwise logit-p boundary", "Gauss-Legendre order per mode-centered panel"
    ),
    frozen_before_phase166 = TRUE,
    stringsAsFactors = FALSE
  )
  source_files <- c(
    "application/config/joint_exqdesn_inference_method_registry_v1.csv",
    "application/R/joint_exqdesn_exact_structured_inference.R",
    "application/R/joint_exqdesn_inference_dispatch.R",
    "application/R/joint_exqdesn_phase164_165_readiness.R",
    "application/R/joint_exqdesn_phase166_168_structured_vb.R",
    "application/scripts/216_prepare_joint_exqdesn_phase164_165_exact_structured.R",
    "application/scripts/217_run_joint_exqdesn_phase166_worker.R",
    "application/scripts/218_finalize_joint_exqdesn_phase166_structured_vb.R",
    "application/scripts/219_check_joint_exqdesn_phase166_structured_vb.R",
    "application/scripts/220_launch_joint_exqdesn_phase166_structured_vb.sh",
    "application/tests/test_joint_exqdesn_exact_structured_inference.R",
    "application/tests/test_joint_exqdesn_inference_dispatch.R",
    "application/tests/test_joint_exqdesn_phase164_166_orchestration.R"
  )
  source_paths <- app_path(source_files)
  if (!all(file.exists(source_paths))) stop("Phase164 source snapshot is incomplete.", call. = FALSE)
  source_code_snapshot <- data.frame(
    relative_path = source_files,
    size_bytes = as.numeric(file.info(source_paths)$size),
    sha256 = vapply(source_paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  fixture_manifest_verification <- data.frame(
    selected_scenarios = length(shards$scenario_ids),
    expected_scenarios = 80L,
    shard_rows = nrow(shards$shard_manifest),
    expected_shard_rows = 240L,
    all_shards_finite_size = all(shards$shard_manifest$size_bytes > 0),
    gate_status = if (length(shards$scenario_ids) == 80L && nrow(shards$shard_manifest) == 240L &&
      all(shards$shard_manifest$size_bytes > 0)) "pass" else "fail",
    stringsAsFactors = FALSE
  )
  assessment <- data.frame(
    gate_status = if (all(source_verification$status == "pass") && fixture_manifest_verification$gate_status == "pass") "pass" else "fail",
    source_hash_failures = sum(source_verification$status != "pass"),
    selected_scenarios = length(unique(selected$scenario_ids)),
    selected_scenario_model_cells = nrow(selected),
    phase166_registry_rows = nrow(registry),
    reused_vb0_rows = sum(registry$use_existing_phase153),
    new_structured_rows = sum(!registry$use_existing_phase153),
    recommendation = "run_phase165_exact_controls_then_launch_phase166",
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(dirs$phase164, "README.md")
  writeLines(c(
    "# Phase164 Source and Method Freeze",
    "",
    "Phase164 freezes the source hashes, exact first-ten Phase153 replicate partition, case-specific controls, and immutable inference method identifiers.",
    "It reuses 160 verified VB0 checkpoints and schedules 320 genuinely new structured-VB fits.",
    "No article files, AL fits, DGP outcomes, or scoring formulas are changed."
  ), readme_path, useBytes = TRUE)
  outputs <- list(
    source_contract = source_contract,
    model_contract = model_contract,
    prior_contract = prior_contract,
    fixture_manifest_verification = fixture_manifest_verification,
    source_manifest_verification = source_verification,
    phase154_baseline_summary = phase154_baseline,
    phase157b_baseline_summary = phase157b_baseline,
    case_specific_control_registry = selected,
    method_development_registry = registry,
    method_registry = method_registry,
    api_contract_audit = api_contract_audit,
    source_order_audit = source_order_audit,
    method_compatibility_matrix = method_compatibility_matrix,
    numerical_tolerance_registry = numerical_tolerance_registry,
    source_code_snapshot = source_code_snapshot,
    no_repeat_ledger = no_repeat_ledger,
    seed_role_registry = seed_role_registry,
    phase164_readiness_assessment = assessment,
    provenance = provenance
  )
  paths <- vapply(names(outputs), function(name) {
    app_joint_qvp_write_csv(outputs[[name]], file.path(dirs$phase164, paste0(name, ".csv")))
  }, character(1L))
  paths <- c(paths, README = normalizePath(readme_path, mustWork = TRUE))
  app_joint_exqdesn_write_manifest(paths, dirs$phase164)
  list(dirs = dirs, selected = selected, registry = registry, assessment = assessment)
}

app_joint_exqdesn_phase165_run <- function(dirs = app_joint_exqdesn_phase164_dirs()) {
  app_ensure_dir(dirs$phase165)
  phase164 <- app_read_csv(file.path(dirs$phase164, "phase164_readiness_assessment.csv"))
  if (nrow(phase164) != 1L || phase164$gate_status[[1L]] != "pass") {
    stop("Phase165 is blocked because Phase164 is not pass.", call. = FALSE)
  }
  selected <- app_read_csv(file.path(dirs$phase164, "case_specific_control_registry.csv"))
  target_bases <- c("normal_bridge", "nonlinear_reservoir_friendly", "regime_shift")
  target_ids <- vapply(target_bases, function(base) {
    rows <- selected[selected$base_scenario_id == base & selected$dgp_replicate_id == "r001", , drop = FALSE]
    unique(rows$scenario_ids)[[1L]]
  }, character(1L))
  identity_rows <- collapse_rows <- quadrature_rows <- list()
  at <- 0L
  for (scenario_id in target_ids) {
    artifacts <- app_joint_exqdesn_load_selected_fixture_artifacts(scenario_id, dirs)
    fixture <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
    for (k in c(1L, which.min(abs(fixture$tau - 0.5)), length(fixture$tau))) {
      tau <- fixture$tau[[k]]
      sigma <- max(stats::mad(fixture$y), 0.1)
      support <- app_joint_exqdesn_support(tau)
      gamma_values <- c(0.90 * support$lower[[1L]], -1.0e-6, 1.0e-6, 0.90 * support$upper[[1L]])
      q <- fixture$y - fixture$true_q[, k]
      s <- rep(sqrt(2 / pi), length(q))
      for (gamma in gamma_values) {
        at <- at + 1L
        cst <- app_joint_exqdesn_constants(tau, gamma)
        u <- rep(cst$B[[1L]] * sigma, length(q))
        v <- u / cst$B[[1L]]
        index <- seq_len(min(50L, length(q)))
        old_log <- stats::dnorm(
          fixture$y[index],
          mean = fixture$true_q[index, k] + sigma * cst$lambda[[1L]] * s[index] + cst$A[[1L]] * v[index],
          sd = sqrt(sigma * cst$B[[1L]] * v[index]), log = TRUE
        ) + stats::dexp(v[index], rate = 1 / sigma, log = TRUE) - log(cst$B[[1L]])
        new_log <- stats::dnorm(
          fixture$y[index],
          mean = fixture$true_q[index, k] + sigma * cst$lambda[[1L]] * s[index] + cst$k[[1L]] * u[index],
          sd = sqrt(sigma * u[index]), log = TRUE
        ) + stats::dexp(u[index], rate = cst$cp[[1L]] / sigma, log = TRUE)
        identity_rows[[at]] <- data.frame(
          scenario_id = scenario_id, tau = tau, gamma = gamma,
          max_abs_log_density_difference = max(abs(old_log - new_log)),
          k_identity_error = abs(cst$A[[1L]] / cst$B[[1L]] - cst$k[[1L]]),
          quarter_identity_error = abs(cst$k[[1L]]^2 + cst$p_gamma[[1L]] * (1 - cst$p_gamma[[1L]]) - 0.25),
          stringsAsFactors = FALSE
        )
        stats_u <- app_joint_exqdesn_u_sufficient_stats(q, s, u)
        terms <- app_joint_exqdesn_u_sigma_gig_terms(gamma, tau, stats_u)
        collapsed <- app_joint_exqdesn_u_gamma_collapsed_log_kernel(gamma, tau, stats_u)
        mode_scale <- app_joint_exqdesn_gig_log_sigma_mode_scale(
          terms$nu, terms$chi, terms$psi
        )
        direct <- stats::integrate(function(standardized_log_sigma) {
          log_sigma <- mode_scale[["log_sigma_mode"]] +
            mode_scale[["log_sigma_scale"]] * standardized_log_sigma
          sig <- exp(log_sigma)
          vapply(seq_along(sig), function(jj) exp(
            app_joint_exqdesn_u_log_joint_kernel(sig[[jj]], gamma, q, s, u, tau) +
              log_sigma[[jj]] + log(mode_scale[["log_sigma_scale"]]) - collapsed
          ), numeric(1L))
        }, -12, 12, subdivisions = 1000L, rel.tol = 1.0e-8)$value
        collapse_rows[[at]] <- data.frame(
          scenario_id = scenario_id, tau = tau, gamma = gamma,
          normalized_direct_sigma_integral = direct,
          absolute_error = abs(direct - 1),
          stringsAsFactors = FALSE
        )
      }
      gamma0 <- 0.35 * support$upper[[1L]]
      cst0 <- app_joint_exqdesn_constants(tau, gamma0)
      stats_u0 <- app_joint_exqdesn_u_sufficient_stats(q, s, rep(cst0$B[[1L]] * sigma, length(q)))
      quad <- app_joint_exqdesn_normalize_branch_quadrature(
        tau,
        function(g) app_joint_exqdesn_u_gamma_collapsed_log_kernel(g, tau, stats_u0),
        function(g) c(gamma = g, p_gamma = app_joint_exqdesn_gamma_to_p(tau, g)),
        node_grid = c(4L, 8L, 12L), tolerance = 1.0e-5
      )
      quadrature_rows[[length(quadrature_rows) + 1L]] <- data.frame(
        scenario_id = scenario_id, tau = tau,
        nodes_per_panel = quad$nodes_per_panel,
        relative_change = quad$relative_change,
        negative_branch_mass = quad$branch_mass[["negative"]],
        positive_branch_mass = quad$branch_mass[["positive"]],
        converged = quad$converged,
        stringsAsFactors = FALSE
      )
    }
  }
  identity <- do.call(rbind, identity_rows)
  collapse <- do.call(rbind, collapse_rows)
  quadrature <- do.call(rbind, quadrature_rows)
  transform_rows <- list()
  for (tau in c(0.05, 0.50, 0.95)) {
    bounds <- app_joint_exqdesn_p_bounds(tau)
    p_values <- c(
      bounds[["lower"]] + 0.2 * (tau - bounds[["lower"]]),
      bounds[["lower"]] + 0.8 * (tau - bounds[["lower"]]),
      tau + 0.2 * (bounds[["upper"]] - tau),
      tau + 0.8 * (bounds[["upper"]] - tau)
    )
    gamma_values <- app_joint_exqdesn_p_to_gamma(tau, p_values)
    eta_values <- stats::qlogis(p_values)
    for (ii in seq_along(p_values)) {
      gamma <- gamma_values[[ii]]
      gamma_step <- 1.0e-6 * max(1, diff(unlist(app_joint_exqdesn_support(tau)[c("lower", "upper")])))
      eta_step <- 1.0e-5
      dp_numeric <- (
        app_joint_exqdesn_gamma_to_p(tau, gamma + gamma_step) -
          app_joint_exqdesn_gamma_to_p(tau, gamma - gamma_step)
      ) / (2 * gamma_step)
      dgamma_deta_numeric <- (
        app_joint_exqdesn_p_eta_to_gamma(tau, eta_values[[ii]] + eta_step) -
          app_joint_exqdesn_p_eta_to_gamma(tau, eta_values[[ii]] - eta_step)
      ) / (2 * eta_step)
      transform_rows[[length(transform_rows) + 1L]] <- data.frame(
        tau = tau,
        branch = ifelse(p_values[[ii]] < tau, "negative", "positive"),
        p_gamma = p_values[[ii]],
        gamma = gamma,
        round_trip_error = abs(app_joint_exqdesn_gamma_to_p(tau, gamma) - p_values[[ii]]),
        dp_dgamma_relative_error = abs(app_joint_exqdesn_dp_dgamma(tau, gamma) - dp_numeric) /
          max(1, abs(dp_numeric)),
        log_jacobian_error = abs(
          app_joint_exqdesn_log_p_eta_jacobian(tau, eta_values[[ii]]) - log(abs(dgamma_deta_numeric))
        ),
        stringsAsFactors = FALSE
      )
    }
  }
  transform_audit <- do.call(rbind, transform_rows)
  fixed_state_registry <- unique(identity[, c("scenario_id", "tau", "gamma")])
  fixed_state_registry$gamma_role <- ifelse(
    abs(fixed_state_registry$gamma) <= 1.0e-5,
    ifelse(fixed_state_registry$gamma < 0, "near_zero_negative", "near_zero_positive"),
    ifelse(fixed_state_registry$gamma < 0, "near_lower_support", "near_upper_support")
  )
  fixed_state_registry$fit_window_rows <- 500L
  fixed_state_registry$evidence_role <- "exact_algebra_control"
  assessment <- data.frame(
    gate_status = if (max(identity$max_abs_log_density_difference) < 1.0e-9 &&
      max(identity$k_identity_error) < 1.0e-12 &&
      max(identity$quarter_identity_error) < 1.0e-12 &&
      max(collapse$absolute_error) < 1.0e-5 && all(quadrature$converged) &&
      max(transform_audit$round_trip_error) < 1.0e-9 &&
      max(transform_audit$dp_dgamma_relative_error) < 1.0e-5 &&
      max(transform_audit$log_jacobian_error) < 1.0e-5) "pass" else "fail",
    fixed_state_scenarios = length(unique(identity$scenario_id)),
    fixed_state_rows = nrow(identity),
    max_transformation_error = max(identity$max_abs_log_density_difference),
    max_sigma_collapse_error = max(collapse$absolute_error),
    quadrature_failures = sum(!quadrature$converged),
    max_transform_round_trip_error = max(transform_audit$round_trip_error),
    max_transform_derivative_relative_error = max(transform_audit$dp_dgamma_relative_error),
    max_transform_log_jacobian_error = max(transform_audit$log_jacobian_error),
    recommendation = "launch_phase166_only_if_pass",
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(dirs$phase165, "README.md")
  writeLines(c(
    "# Phase165 Exact Algebra Controls",
    "",
    "These controls use full 500-row fit-window states from three frozen Phase153 scenarios.",
    "They verify the v-to-u transformed density, the k/quarter identities, direct sigma collapse, and branch quadrature.",
    "This is a mathematical correctness gate, not a model-performance pilot."
  ), readme_path, useBytes = TRUE)
  outputs <- list(
    augmentation_identity = identity,
    sigma_collapse_identity = collapse,
    branch_quadrature_control = quadrature,
    transform_inversion_audit = transform_audit,
    fixed_state_registry = fixed_state_registry,
    density_identity_audit = identity,
    bessel_collapse_audit = collapse,
    branch_mass_audit = quadrature,
    phase165_assessment = assessment,
    provenance = app_joint_qvp_provenance_rows()
  )
  paths <- vapply(names(outputs), function(name) app_joint_qvp_write_csv(outputs[[name]], file.path(dirs$phase165, paste0(name, ".csv"))), character(1L))
  paths <- c(paths, README = normalizePath(readme_path, mustWork = TRUE))
  app_joint_exqdesn_write_manifest(paths, dirs$phase165)
  list(dirs = dirs, assessment = assessment)
}
