#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(
    dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])),
    "..", ".."
  ),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_application_panel.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/glofas_discrepancy_transition.R"))
source(app_path("application/R/glofas_discrepancy_transition_campaign.R"))
source(app_path("application/R/glofas_discrepancy_context_repair_campaign.R"))

args <- app_parse_args(list(
  campaign = "application/config/glofas_discrepancy_context_repair_campaign_20260825.yaml",
  output_root = "local_trackers/runtime_configs/glofas_discrepancy_context_repair_20260825",
  source_root = ""
))

resolve_repo <- function(path, must_work = FALSE) {
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

profile_manifest_row <- function(
  input_id,
  source_name,
  source_type,
  path,
  upstream_reference,
  required,
  notes
) {
  x <- app_read_csv(path)
  date_columns <- intersect(c("date", "origin_date", "target_date"), names(x))
  dates <- as.Date(character())
  for (name in date_columns) {
    dates <- c(dates, suppressWarnings(as.Date(x[[name]])))
  }
  dates <- dates[!is.na(dates)]
  data.frame(
    input_id = input_id,
    source_name = source_name,
    source_type = source_type,
    local_path = normalizePath(path, mustWork = TRUE),
    upstream_reference = upstream_reference,
    date_min = if (length(dates)) as.character(min(dates)) else NA_character_,
    date_max = if (length(dates)) as.character(max(dates)) else NA_character_,
    cutoff_date = NA_character_,
    row_count = nrow(x),
    column_count = ncol(x),
    sha256 = app_sha256_file(path),
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    notes = notes,
    required = required,
    stringsAsFactors = FALSE
  )
}

campaign_path <- resolve_repo(args$campaign, must_work = TRUE)
campaign <- app_read_yaml(campaign_path)
campaign_schema <- as.character(campaign$schema_version)
context_prior_campaign <- identical(
  campaign_schema,
  "glofas_context_prior_repair_campaign_v1"
)
if (!campaign_schema %in% c(
  "glofas_discrepancy_context_repair_campaign_v1",
  "glofas_context_prior_repair_campaign_v1"
)) {
  stop("Unsupported discrepancy-context repair campaign schema.", call. = FALSE)
}
output_root <- resolve_repo(args$output_root, must_work = FALSE)
batch_id <- basename(output_root)
if (!grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", batch_id)) {
  stop("The transition output-root basename is not a safe batch ID.", call. = FALSE)
}
if (dir.exists(output_root) && length(list.files(output_root, all.files = TRUE, no.. = TRUE))) {
  stop(sprintf("Refusing to overwrite nonempty transition root: %s.", output_root), call. = FALSE)
}

baseline_path <- resolve_repo(campaign$baseline_registry, must_work = TRUE)
baseline <- app_read_yaml(baseline_path)
base_config_path <- normalizePath(baseline$artifacts$base_config$path, mustWork = TRUE)
base_grid_path <- normalizePath(baseline$artifacts$base_model_grid$path, mustWork = TRUE)
if (!identical(app_sha256_file(base_config_path), baseline$artifacts$base_config$sha256)) {
  stop("The frozen FR09 base-config hash does not match its registry.", call. = FALSE)
}
if (!identical(app_sha256_file(base_grid_path), baseline$artifacts$base_model_grid$sha256)) {
  stop("The frozen FR09 model-grid hash does not match its registry.", call. = FALSE)
}

candidate_path <- resolve_repo(campaign$candidate_registry, must_work = TRUE)
cutoff_path <- resolve_repo(campaign$cutoff_registry, must_work = TRUE)
base_cfg <- app_read_config(base_config_path)
data_local_root <- as.character(base_cfg$paths$data_local %||% "")
if (!nzchar(data_local_root) || !dir.exists(data_local_root)) {
  stop(
    "The frozen FR09 config does not resolve to an existing data_local root.",
    call. = FALSE
  )
}
data_local_root <- normalizePath(data_local_root, mustWork = TRUE)
candidates <- if (isTRUE(context_prior_campaign)) {
  app_glofas_context_prior_validate_candidates(app_read_csv(candidate_path))
} else {
  app_glofas_context_repair_validate_candidates(app_read_csv(candidate_path))
}
cutoffs <- app_glofas_transition_validate_cutoffs(
  app_read_csv(cutoff_path),
  repo_root = repo_root,
  data_local_root = data_local_root
)
expected_count <- nrow(candidates) * nrow(cutoffs)
if (expected_count != as.integer(campaign$execution$expected_total_fits)) {
  stop(sprintf(
    "The repair campaign requires %d fits, observed %d.",
    as.integer(campaign$execution$expected_total_fits), expected_count
  ), call. = FALSE)
}
if (as.integer(campaign$inference$max_iter) != 300L ||
    as.integer(campaign$execution$max_parallel) < 1L ||
    as.integer(campaign$execution$max_parallel) > 20L ||
    as.integer(campaign$execution$backend_threads) != 1L) {
  stop("The repair campaign requires max_iter=300 and at most 20 one-thread workers.", call. = FALSE)
}

source_root <- if (nzchar(as.character(args$source_root))) {
  resolve_repo(args$source_root, must_work = TRUE)
} else {
  normalizePath(campaign$source_campaign$root, mustWork = TRUE)
}
source_evidence <- c(
  as.character(campaign$source_campaign$ranking_file %||%
    "tables/transition_candidate_ranking.csv"),
  as.character(campaign$source_campaign$decision_file %||%
    "tables/transition_decision.csv")
)
for (entry in source_evidence) {
  path <- file.path(source_root, "tables", entry)
  if (grepl("^tables/", entry)) path <- file.path(source_root, entry)
  expected_hash <- if (identical(entry, source_evidence[[1L]])) {
    campaign$source_campaign$ranking_sha256
  } else {
    campaign$source_campaign$decision_sha256
  }
  if (!file.exists(path) || !identical(app_sha256_file(path), expected_hash)) {
    stop(sprintf("Frozen source evidence changed: %s.", path), call. = FALSE)
  }
}
source_inventory <- app_glofas_context_repair_source_inventory(
  source_root = source_root,
  expected_manifest_sha256 = campaign$source_campaign$runtime_manifest_sha256,
  source_candidates = unique(candidates$warm_start_source_candidate),
  cutoff_ids = cutoffs$cutoff_id
)

for (dir in c(
  "inputs", "candidates", "common_cache", "runs", "logs", "generated",
  "scores", "status", "tables", "figures", "cleanup", "manifests"
)) {
  app_ensure_dir(file.path(output_root, dir))
}
schema_path <- app_path("application/manifests/expected_schema.yaml")
base_grid <- app_read_csv(base_grid_path)
if (sum(base_grid$model_family == "qdesn_glofas_discrepancy") != 1L ||
    sum(base_grid$model_family == "raw_glofas") != 1L) {
  stop("The FR09 base model grid must contain one raw and one Q-DESN row.", call. = FALSE)
}

cutoff_assets <- list()
panel_audit <- list()
baseline_scores <- list()
for (i in seq_len(nrow(cutoffs))) {
  cutoff <- cutoffs[i, , drop = FALSE]
  cutoff_id <- cutoff$cutoff_id[[1L]]
  origin <- as.Date(cutoff$origin_date[[1L]])
  bundle_dir <- cutoff$bundle_path[[1L]]
  input_root <- file.path(output_root, "inputs", cutoff_id)
  cache_dir <- file.path(output_root, "common_cache", cutoff_id)
  app_ensure_dir(input_root)
  app_ensure_dir(cache_dir)

  climate_path <- file.path(bundle_dir, "covariates", "climate_covariates.csv")
  climate <- app_read_csv(climate_path)
  required_climate <- c("date", "precipitation_mm", "soil_moisture")
  if (!all(required_climate %in% names(climate))) {
    stop(sprintf("Cutoff %s lacks required climate columns.", cutoff_id), call. = FALSE)
  }
  ppt_soil_path <- file.path(input_root, "ppt_soil_covariates.csv")
  app_write_csv(data.frame(
    date = as.Date(climate$date),
    ppt = as.numeric(climate$precipitation_mm),
    soil = as.numeric(climate$soil_moisture),
    stringsAsFactors = FALSE
  ), ppt_soil_path)
  paths <- list(
    reference_gauge = file.path(bundle_dir, "reference", "reference_gauge.csv"),
    glofas_retrospective = file.path(bundle_dir, "glofas", "glofas_retrospective.csv"),
    glofas_ensemble = file.path(bundle_dir, "glofas", "glofas_ensemble.csv"),
    climate_covariates = climate_path,
    ppt_soil_covariates = ppt_soil_path
  )
  if (!all(file.exists(unlist(paths)))) {
    stop(sprintf("Cutoff %s has missing input files.", cutoff_id), call. = FALSE)
  }
  input_manifest <- app_bind_rows_fill(list(
    profile_manifest_row(
      "reference_gauge", "reference gauge streamflow", "observation",
      paths$reference_gauge, bundle_dir, TRUE,
      "Frozen historical pseudo-cutoff reference series."
    ),
    profile_manifest_row(
      "glofas_retrospective", "GloFAS retrospective streamflow",
      "retrospective_forecast", paths$glofas_retrospective, bundle_dir, TRUE,
      "Frozen GloFAS retrospective series available through the origin."
    ),
    profile_manifest_row(
      "glofas_ensemble", "GloFAS issued ensemble", "ensemble_forecast",
      paths$glofas_ensemble, bundle_dir, TRUE,
      "Issued ensemble fixed at the historical forecast origin."
    ),
    profile_manifest_row(
      "climate_covariates", "archived climate covariates", "covariate",
      paths$climate_covariates, bundle_dir, FALSE,
      "Archived climate table retained for provenance; future rows are not used."
    ),
    profile_manifest_row(
      "ppt_soil_covariates", "precipitation and soil covariates", "covariate",
      paths$ppt_soil_covariates, climate_path, FALSE,
      "Historical values feed the model; future values are replaced by origin persistence."
    )
  ))
  input_manifest_path <- file.path(input_root, "input_manifest.csv")
  app_write_csv(
    input_manifest[, app_required_manifest_columns(), drop = FALSE],
    input_manifest_path
  )
  validation <- app_validate_input_manifest(
    input_manifest_path,
    schema_path,
    require_files = TRUE
  )
  if (!validation$ok) stop(paste(validation$issues, collapse = "\n"), call. = FALSE)

  bundle_manifest <- input_manifest
  bundle_manifest$bundle_id <- paste0("glofas_transition_", cutoff_id)
  bundle_manifest$bundle_root <- bundle_dir
  bundle_manifest$relative_path <- vapply(paths, function(path) {
    normalized <- normalizePath(path, mustWork = TRUE)
    if (startsWith(normalized, paste0(bundle_dir, .Platform$file.sep))) {
      substring(normalized, nchar(bundle_dir) + 2L)
    } else {
      normalized
    }
  }, character(1L))
  bundle_manifest$file_size_bytes <- as.numeric(file.info(input_manifest$local_path)$size)
  bundle_manifest$modified_time <- format(
    file.info(input_manifest$local_path)$mtime,
    "%Y-%m-%d %H:%M:%S %Z"
  )
  bundle_manifest$registered_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  bundle_manifest$status <- "ok"
  bundle_manifest$message <- NA_character_
  bundle_manifest_path <- file.path(input_root, "input_bundle_manifest.csv")
  app_write_csv(bundle_manifest, bundle_manifest_path)

  ensemble <- app_read_csv(paths$glofas_ensemble)
  horizon_max <- max(as.integer(ensemble$horizon), na.rm = TRUE)
  target_max <- max(as.Date(ensemble$target_date), na.rm = TRUE)
  cutoff_table_path <- file.path(input_root, "cutoffs.csv")
  app_write_csv(data.frame(
    cutoff_id = cutoff_id,
    origin_date = origin,
    train_start = as.Date("1979-02-01"),
    train_end = origin,
    eval_start = origin + 1L,
    eval_end = target_max,
    horizon_min = min(as.integer(ensemble$horizon), na.rm = TRUE),
    horizon_max = horizon_max,
    split = "causal_transition_development",
    enabled = TRUE,
    notes = paste(
      "Causal historical replay; future ppt/soil use origin persistence; role",
      cutoff$selection_role[[1L]]
    ),
    stringsAsFactors = FALSE
  ), cutoff_table_path)
  input_bundle_path <- file.path(input_root, "input_bundle.yaml")
  app_write_yaml(list(
    version = 0.1,
    bundle_id = paste0("glofas_transition_", cutoff_id),
    description = "Frozen causal historical pseudo-cutoff transition bundle.",
    bundle_root = bundle_dir,
    copy_files = FALSE,
    manifest_output = input_manifest_path,
    bundle_manifest_output = bundle_manifest_path
  ), input_bundle_path)

  panel_cfg <- app_glofas_transition_set_origin_persistence(base_cfg)
  panel_cfg$.__config_path__ <- NULL
  panel_cfg$paths$input_bundle <- input_bundle_path
  panel_cfg$paths$input_bundle_manifest <- bundle_manifest_path
  panel_cfg$paths$input_manifest <- input_manifest_path
  panel_cfg$paths$cutoffs <- cutoff_table_path
  panel_cfg$paths$cache <- cache_dir
  panel_cfg$forecast_protocol$default_horizon_max <- horizon_max
  panel_cfg$covariates$forecast$horizon_days <- horizon_max
  policy <- app_validate_covariate_source_policy(
    panel_cfg,
    cutoff_row = data.frame(origin_date = origin),
    stop_on_failure = FALSE
  )
  if (!identical(policy$status[[1L]], "PASS") ||
      !identical(policy$future_policy[[1L]], "origin_persistence") ||
      !isTRUE(policy$deployable_forecast_covariates[[1L]]) ||
      isTRUE(policy$uses_realized_future[[1L]])) {
    stop(sprintf("Cutoff %s failed the causal covariate-policy gate.", cutoff_id), call. = FALSE)
  }
  panel <- app_build_application_panel(panel_cfg, validation$manifest, validation$schema)
  app_validate_panel(panel, validation$schema)
  timeline <- app_panel_covariate_timeline(panel, required = TRUE)
  timeline_audit <- app_covariate_policy_audit(timeline)
  if (any(timeline_audit$n_uses_realized_future > 0, na.rm = TRUE)) {
    stop(sprintf("Cutoff %s leaked realized future covariates.", cutoff_id), call. = FALSE)
  }
  panel_path <- file.path(cache_dir, "application_panel.rds")
  saveRDS(panel, panel_path)
  panel_audit[[length(panel_audit) + 1L]] <- cbind(
    data.frame(
      cutoff_id = cutoff_id,
      selection_role = cutoff$selection_role[[1L]],
      panel_path = panel_path,
      panel_sha256 = app_sha256_file(panel_path),
      covariate_policy = policy$future_policy[[1L]],
      uses_realized_future = policy$uses_realized_future[[1L]],
      stringsAsFactors = FALSE
    ),
    app_panel_summary(panel)
  )
  baseline_scores[[length(baseline_scores) + 1L]] <-
    app_glofas_transition_causal_baseline_scores(
      panel = panel,
      cutoff_id = cutoff_id,
      origin_date = origin,
      selection_role = cutoff$selection_role[[1L]]
    )
  cutoff_assets[[cutoff_id]] <- list(
    origin = origin,
    selection_role = cutoff$selection_role[[1L]],
    input_manifest_path = input_manifest_path,
    bundle_manifest_path = bundle_manifest_path,
    input_bundle_path = input_bundle_path,
    cutoff_table_path = cutoff_table_path,
    cache_dir = cache_dir,
    horizon_max = horizon_max,
    target_max = target_max,
    panel_path = panel_path,
    panel_sha256 = app_sha256_file(panel_path)
  )
}

runtime_rows <- list()
priority <- 0L
reference_cache_root <- file.path(output_root, "common_cache", "reference_feature_cache")
app_ensure_dir(reference_cache_root)
for (i in seq_len(nrow(candidates))) {
  candidate <- candidates[i, , drop = FALSE]
  contract <- app_glofas_transition_contract_from_candidate(candidate)
  for (cutoff_id in names(cutoff_assets)) {
    asset <- cutoff_assets[[cutoff_id]]
    priority <- priority + 1L
    candidate_id <- candidate$candidate_id[[1L]]
    runtime_id <- paste(candidate_id, cutoff_id, sep = "__")
    run_id <- paste(batch_id, candidate_id, cutoff_id, sep = "_")
    run_dir <- file.path(output_root, "runs", run_id)
    candidate_root <- file.path(output_root, "candidates", candidate_id, cutoff_id)
    app_ensure_dir(candidate_root)
    quantile_grid_path <- file.path(candidate_root, "quantile_grid_p50.csv")
    app_write_csv(data.frame(
      quantile_id = "p50",
      quantile_level = 0.5,
      role = "median",
      enabled = TRUE,
      stringsAsFactors = FALSE
    ), quantile_grid_path)
    fit_id <- paste0("qdesn_transition_", candidate_id, "_", cutoff_id, "_p50")
    raw_fit_id <- paste0("raw_transition_", candidate_id, "_", cutoff_id, "_p50")
    model_grid <- base_grid
    raw_row <- model_grid$model_family == "raw_glofas"
    qdesn_row <- model_grid$model_family == "qdesn_glofas_discrepancy"
    model_grid$fit_id[raw_row] <- raw_fit_id
    model_grid$model_id[raw_row] <- raw_fit_id
    model_grid$fit_id[qdesn_row] <- fit_id
    model_grid$model_id[qdesn_row] <- fit_id
    model_grid$quantile_level <- 0.5
    model_grid$notes <- paste(
      "Causal transition bridge", candidate_id, "at", cutoff_id,
      "with FR09 DESN and RHS fixed"
    )
    model_grid_path <- file.path(candidate_root, "model_grid_p50.csv")
    app_write_csv(model_grid, model_grid_path)

    cfg <- app_glofas_transition_set_origin_persistence(base_cfg)
    cfg <- if (isTRUE(context_prior_campaign)) {
      app_glofas_context_prior_apply_candidate(cfg, candidate)
    } else {
      app_glofas_transition_apply_candidate(cfg, candidate)
    }
    cfg$.__config_path__ <- NULL
    cfg$application_name <- paste0("glofas_transition_", candidate_id, "_", cutoff_id)
    source <- source_inventory[
      source_inventory$source_candidate_id ==
        candidate$warm_start_source_candidate[[1L]] &
        source_inventory$cutoff_id == cutoff_id,
      ,
      drop = FALSE
    ]
    if (nrow(source) != 1L) {
      stop(sprintf("Candidate %s has no unique warm-start source.", runtime_id), call. = FALSE)
    }
    cfg$description <- paste(
      "Causal p50 discrepancy-context repair for", candidate_id,
      "at", asset$origin, "with FR09 geometry and priors frozen and",
      candidate$warm_start_compatibility_mode[[1L]], "initialization."
    )
    cfg$paths$input_bundle <- asset$input_bundle_path
    cfg$paths$input_bundle_manifest <- asset$bundle_manifest_path
    cfg$paths$input_manifest <- asset$input_manifest_path
    cfg$paths$cutoffs <- asset$cutoff_table_path
    cfg$paths$quantile_grid <- quantile_grid_path
    cfg$paths$model_grid <- model_grid_path
    if (is.null(cfg$paths$data_local) ||
        !dir.exists(as.character(cfg$paths$data_local))) {
      stop(
        "The frozen FR09 config does not resolve to an existing data_local root.",
        call. = FALSE
      )
    }
    cfg$paths$data_local <- normalizePath(
      as.character(cfg$paths$data_local),
      mustWork = TRUE
    )
    cfg$paths$cache <- asset$cache_dir
    cfg$paths$runs <- file.path(output_root, "runs")
    cfg$paths$logs <- file.path(output_root, "logs")
    cfg$paths$generated_outputs <- file.path(output_root, "generated")
    cfg$forecast_protocol$default_horizon_max <- asset$horizon_max
    cfg$covariates$forecast$horizon_days <- asset$horizon_max
    cfg$inference$vb_ld$max_iter <- as.integer(campaign$inference$max_iter)
    cfg$inference$vb_ld$max_iter_hard_cap <- as.integer(
      campaign$inference$max_iter_hard_cap
    )
    cfg$inference$vb_ld$min_iter_elbo <- as.integer(campaign$inference$min_iter_elbo)
    cfg$inference$vb_ld$tol <- as.numeric(campaign$inference$tol)
    cfg$inference$vb_ld$tol_par <- as.numeric(campaign$inference$tol_par)
    cfg$inference$vb_ld$n_samp_xi <- as.integer(campaign$inference$n_samp_xi)
    cfg$inference$vb_ld$n_draws <- as.integer(campaign$inference$n_draws)
    cfg$inference$vb_ld$warm_start <-
      app_glofas_context_repair_warm_start_config(candidate, source)
    checkpoint_path <- file.path(run_dir, "objects", paste0(fit_id, "__vb_checkpoint.rds"))
    cfg$inference$vb_ld$checkpoint <- list(
      enabled = TRUE,
      resume = FALSE,
      path = checkpoint_path,
      every_iterations = as.integer(campaign$inference$checkpoint$every_iterations),
      every_minutes = as.numeric(campaign$inference$checkpoint$every_minutes),
      keep_previous = app_as_bool(campaign$inference$checkpoint$keep_previous),
      keep_on_success = app_as_bool(campaign$inference$checkpoint$keep_on_success),
      compress = FALSE
    )
    cfg$runtime_optimization <- cfg$runtime_optimization %||% list()
    cfg$runtime_optimization$compiled_future_contract <- TRUE
    cfg$runtime_optimization$active_future_jacobian <- TRUE
    cfg$runtime_optimization$paired_fixed_stats <- TRUE
    cfg$runtime_optimization$reference_feature_cache <- list(
      enabled = TRUE,
      root = reference_cache_root,
      wait_seconds = 1200,
      poll_seconds = 0.25
    )
    cfg$post_analysis$run_after_outputs <- TRUE
    cfg$post_analysis$storage$write_history_draws_rds <- FALSE
    cfg$post_analysis$storage$write_history_draws_csv <- FALSE
    cfg$execution$artifacts <- list(
      retain_fit_object = TRUE,
      retain_design_object = TRUE,
      retain_prediction_design_object = TRUE,
      retain_reference_fit_object = TRUE,
      compact_latent_path_design = TRUE
    )
    cfg$execution$final_launch$enabled <- TRUE
    cfg$execution$final_launch$note <- paste(
      "Approved causal p50 transition bridge", candidate_id, cutoff_id
    )
    app_validate_application_model_contract(cfg)
    policy <- app_validate_covariate_source_policy(
      cfg,
      cutoff_row = data.frame(origin_date = asset$origin),
      stop_on_failure = TRUE
    )
    if (isTRUE(policy$uses_realized_future[[1L]])) {
      stop(sprintf("Candidate %s uses realized future covariates.", runtime_id), call. = FALSE)
    }
    observed_contract <- app_glofas_discrepancy_transition_contract(cfg)
    if (!identical(observed_contract$contract_hash, contract$contract_hash)) {
      stop(sprintf("Candidate %s transition contract changed during materialization.", runtime_id), call. = FALSE)
    }
    config_path <- file.path(candidate_root, "config_p50.yaml")
    app_write_yaml(cfg, config_path)
    runtime_rows[[length(runtime_rows) + 1L]] <- cbind(
      data.frame(
        candidate_id = runtime_id,
        base_candidate_id = candidate_id,
        cutoff_id = cutoff_id,
        origin_date = as.character(asset$origin),
        selection_role = asset$selection_role,
        execution_stage = candidate$execution_stage[[1L]],
        priority = priority,
        config_path = config_path,
        config_sha256 = app_sha256_file(config_path),
        model_grid_path = model_grid_path,
        model_grid_sha256 = app_sha256_file(model_grid_path),
        run_id = run_id,
        run_dir = run_dir,
        log_path = file.path(output_root, "logs", paste0(runtime_id, ".log")),
        checkpoint_path = checkpoint_path,
        checkpoint_resume_enabled = TRUE,
        retain_heavy = isTRUE(candidate$retain_heavy[[1L]]),
        future_policy = "origin_persistence",
        source_provider = "historical_origin",
        cold_start = FALSE,
        warm_start_source_candidate = source$source_candidate_id[[1L]],
        warm_start_source_fit_object = source$source_fit_object[[1L]],
        warm_start_source_sha256 = source$source_fit_sha256[[1L]],
        warm_start_source_design_hash = source$source_design_hash[[1L]],
        warm_start_compatibility_mode =
          candidate$warm_start_compatibility_mode[[1L]],
        warm_start_use_theta = candidate$warm_start_use_theta[[1L]],
        warm_start_use_future = candidate$warm_start_use_future[[1L]],
        warm_start_use_sigma = candidate$warm_start_use_sigma[[1L]],
        reservoir_preflight_enabled = FALSE,
        context_prior_sd = as.numeric((candidate$context_prior_sd %||% NA_real_)[[1L]]),
        status = "prepared_not_launched",
        stringsAsFactors = FALSE
      ),
      app_glofas_discrepancy_transition_contract_row(contract)
    )
  }
}

runtime_manifest <- app_bind_rows_fill(runtime_rows)
if (nrow(runtime_manifest) != expected_count || anyDuplicated(runtime_manifest$candidate_id)) {
  stop("The transition runtime manifest failed cardinality or uniqueness checks.", call. = FALSE)
}
app_write_csv(runtime_manifest, file.path(output_root, "runtime_manifest.csv"))
stage0_manifest <- runtime_manifest[
  runtime_manifest$execution_stage == "stage0", , drop = FALSE
]
stage1_manifest <- runtime_manifest[
  runtime_manifest$execution_stage == "stage1", , drop = FALSE
]
if (nrow(stage0_manifest) != as.integer(campaign$execution$expected_stage0_fits) ||
    nrow(stage1_manifest) != as.integer(campaign$execution$expected_stage1_fits)) {
  stop("Repair stage manifests failed their frozen cardinality checks.", call. = FALSE)
}
app_write_csv(stage0_manifest, file.path(output_root, "runtime_manifest_stage0.csv"))
app_write_csv(stage1_manifest, file.path(output_root, "runtime_manifest_stage1.csv"))
app_write_csv(candidates, file.path(output_root, "candidate_registry_snapshot.csv"))
app_write_csv(cutoffs, file.path(output_root, "cutoff_registry_snapshot.csv"))
app_write_csv(source_inventory, file.path(output_root, "source_fit_inventory.csv"))
app_write_csv(app_bind_rows_fill(panel_audit), file.path(output_root, "tables", "panel_audit.csv"))
app_write_csv(
  app_bind_rows_fill(baseline_scores),
  file.path(output_root, "tables", "causal_baseline_scores.csv")
)
app_write_yaml(campaign, file.path(output_root, "campaign_snapshot.yaml"))

provenance <- data.frame(
  field = c(
    "prepared_at", "repo_head", "repo_tree", "repo_branch", "campaign_path",
    "campaign_sha256", "baseline_registry_sha256", "base_config_sha256",
    "base_model_grid_sha256", "candidate_registry_sha256",
    "cutoff_registry_sha256", "source_runtime_manifest_sha256",
    "source_fit_inventory_sha256", "runtime_manifest_sha256",
    "stage0_manifest_sha256", "stage1_manifest_sha256", "fit_count",
    "primary_origin_count", "supplemental_origin_count", "launch_status"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)[[1L]],
    system2("git", c("-C", repo_root, "write-tree"), stdout = TRUE)[[1L]],
    system2("git", c("-C", repo_root, "branch", "--show-current"), stdout = TRUE)[[1L]],
    campaign_path,
    app_sha256_file(campaign_path),
    app_sha256_file(baseline_path),
    app_sha256_file(base_config_path),
    app_sha256_file(base_grid_path),
    app_sha256_file(candidate_path),
    app_sha256_file(cutoff_path),
    app_sha256_file(file.path(source_root, "runtime_manifest.csv")),
    app_sha256_file(file.path(output_root, "source_fit_inventory.csv")),
    app_sha256_file(file.path(output_root, "runtime_manifest.csv")),
    app_sha256_file(file.path(output_root, "runtime_manifest_stage0.csv")),
    app_sha256_file(file.path(output_root, "runtime_manifest_stage1.csv")),
    nrow(runtime_manifest),
    sum(cutoffs$selection_role == "primary_v31"),
    sum(cutoffs$selection_role == "supplemental_v21"),
    "prepared_not_launched"
  ),
  stringsAsFactors = FALSE
)
app_write_csv(provenance, file.path(output_root, "provenance.csv"))
writeLines(c(
  if (isTRUE(context_prior_campaign)) {
    "Causal GloFAS context-specific prior repair prepared but not launched."
  } else {
    "Causal GloFAS discrepancy-context repair prepared but not launched."
  },
  "FR09 DESN geometry, separate block seeds, and separate RHS priors are frozen.",
  if (isTRUE(context_prior_campaign)) {
    "The direct standardized GloFAS-level coefficient receives an isolated fixed Gaussian prior."
  } else {
    "Stage 0 strictly continues retained T01/T10 fits before Stage 1 can start."
  },
  if (isTRUE(context_prior_campaign)) {
    "Six prospective prior scales are evaluated over three primary origins."
  } else {
    "Stage 1 is a complete 3-by-3 context-variable and placement factorial."
  },
  "All historical replays use origin-persistence future PPT/soil and no realized future values.",
  "Three v3.1 origins determine ranking; no supplemental origin is run here.",
  "December 2022, full7, and article updates remain disabled."
), file.path(output_root, "README.txt"))
cat(file.path(output_root, "runtime_manifest.csv"), "\n")
