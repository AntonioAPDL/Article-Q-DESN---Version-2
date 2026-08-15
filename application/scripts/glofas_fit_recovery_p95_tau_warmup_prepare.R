#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_fit_recovery.R"))

source_root_default <- "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_fit_recovery_20260730"
control_run_id <- "glofas_fit_recovery_transition_full7_20260808_fr09_persistence_innovation_p95"
args <- app_parse_args(list(
  base_config = file.path(
    source_root_default,
    "local_trackers/runtime_configs/glofas_fit_recovery_transition_full7_20260808/candidates/fr09_persistence_innovation/p95/config_p95.yaml"
  ),
  control_fit = file.path(
    source_root_default,
    "local_trackers/runtime_configs/glofas_fit_recovery_transition_full7_20260808/runs",
    control_run_id,
    "objects/qdesn_transition_full7_fr09_persistence_innovation_p95.rds"
  ),
  control_history = file.path(
    source_root_default,
    "local_trackers/runtime_configs/glofas_fit_recovery_transition_full7_20260808/runs",
    control_run_id,
    "tables/post_fit_quantile_history_summary.csv"
  ),
  expected_control_fit_sha256 = "e48130e8eac1a10880f8b37def0bd81142bae8f836ecf31350cf9db6520d3d1f",
  candidates = "application/config/glofas_fit_recovery_p95_tau_warmup_candidates_20260809.csv",
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_p95_tau_warmup_20260809"
))
resolve_repo <- function(path, must_work = FALSE) {
  normalizePath(if (grepl("^/", path)) path else app_path(path), mustWork = must_work)
}
copy_verified <- function(source, destination) {
  source <- normalizePath(source, mustWork = TRUE)
  app_ensure_dir(dirname(destination))
  if (file.exists(destination)) {
    if (!identical(app_sha256_file(source), app_sha256_file(destination))) {
      stop(sprintf("Existing snapshot differs from source: %s.", destination), call. = FALSE)
    }
  } else if (!file.copy(source, destination, copy.mode = TRUE, copy.date = TRUE)) {
    stop(sprintf("Could not snapshot %s.", source), call. = FALSE)
  }
  normalizePath(destination, mustWork = TRUE)
}

base_config_path <- resolve_repo(args$base_config, TRUE)
control_fit_path <- resolve_repo(args$control_fit, TRUE)
control_history_path <- resolve_repo(args$control_history, TRUE)
candidate_path <- resolve_repo(args$candidates, TRUE)
output_root <- resolve_repo(args$output_root, FALSE)
for (dir in c(
  "source", "candidates", "common_cache", "logs", "runs", "generated",
  "scores", "status", "tables", "figures", "manifest", "cleanup"
)) {
  app_ensure_dir(file.path(output_root, dir))
}

control_fit_sha256 <- app_sha256_file(control_fit_path)
if (!identical(control_fit_sha256, as.character(args$expected_control_fit_sha256))) {
  stop("The immutable p95 control fit hash does not match the declared source.", call. = FALSE)
}

base_cfg <- app_read_yaml(base_config_path)
source_path <- function(path) {
  normalizePath(if (grepl("^/", path)) path else file.path(dirname(base_config_path), path), mustWork = TRUE)
}
source_assets <- list(
  base_config = base_config_path,
  model_grid = source_path(base_cfg$paths$model_grid),
  quantile_grid = source_path(base_cfg$paths$quantile_grid),
  input_bundle = source_path(base_cfg$paths$input_bundle),
  input_bundle_manifest = source_path(base_cfg$paths$input_bundle_manifest),
  input_manifest = source_path(base_cfg$paths$input_manifest),
  application_panel = source_path(file.path(base_cfg$paths$cache, "application_panel.rds")),
  control_history = control_history_path
)
snapshot_paths <- list(
  base_config = copy_verified(source_assets$base_config, file.path(output_root, "source", "base_config_p95.yaml")),
  model_grid = copy_verified(source_assets$model_grid, file.path(output_root, "source", "model_grid_p95.csv")),
  quantile_grid = copy_verified(source_assets$quantile_grid, file.path(output_root, "source", "quantile_grid_p95.csv")),
  input_bundle = copy_verified(source_assets$input_bundle, file.path(output_root, "source", "input_bundle.yaml")),
  input_bundle_manifest = copy_verified(
    source_assets$input_bundle_manifest,
    file.path(output_root, "source", "input_bundle_manifest.csv")
  ),
  input_manifest = copy_verified(source_assets$input_manifest, file.path(output_root, "source", "input_manifest.csv")),
  application_panel = copy_verified(
    source_assets$application_panel,
    file.path(output_root, "common_cache", "application_panel.rds")
  ),
  control_history = copy_verified(
    source_assets$control_history,
    file.path(output_root, "source", "control_post_fit_quantile_history_summary.csv")
  )
)

quantile_grid <- app_read_csv(snapshot_paths$quantile_grid)
if (nrow(quantile_grid) != 1L || abs(as.numeric(quantile_grid$quantile_level[[1L]]) - 0.95) > 1.0e-12) {
  stop("The source quantile grid is not an exact p95 grid.", call. = FALSE)
}
base_grid <- app_read_csv(snapshot_paths$model_grid)
qrow <- base_grid$model_family == "qdesn_glofas_discrepancy"
rrow <- base_grid$model_family == "raw_glofas"
if (sum(qrow) != 1L || sum(rrow) != 1L) {
  stop("The source model grid must contain exactly one Q-DESN and one raw GloFAS row.", call. = FALSE)
}

candidates <- app_read_csv(candidate_path)
required <- c("candidate_id", "priority", "freeze_tau_warmup_iters", "role", "rationale")
missing <- setdiff(required, names(candidates))
if (!nrow(candidates) || length(missing)) {
  stop(sprintf("Warmup candidates are empty or missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
}
candidates$priority <- as.integer(candidates$priority)
candidates$freeze_tau_warmup_iters <- as.integer(candidates$freeze_tau_warmup_iters)
if (anyDuplicated(candidates$candidate_id) || anyDuplicated(candidates$priority) ||
    any(!is.finite(candidates$freeze_tau_warmup_iters) | candidates$freeze_tau_warmup_iters < 1L)) {
  stop("Warmup candidate identifiers, priorities, or iteration counts are invalid.", call. = FALSE)
}
candidates <- candidates[order(candidates$priority), , drop = FALSE]

runtime_rows <- list()
for (i in seq_len(nrow(candidates))) {
  candidate <- candidates[i, , drop = FALSE]
  candidate_id <- candidate$candidate_id[[1L]]
  freeze_iters <- candidate$freeze_tau_warmup_iters[[1L]]
  candidate_root <- file.path(output_root, "candidates", candidate_id)
  app_ensure_dir(candidate_root)

  grid <- base_grid
  fit_id <- paste0("qdesn_", candidate_id)
  grid$fit_id[qrow] <- fit_id
  grid$model_id[qrow] <- fit_id
  grid$fit_id[rrow] <- paste0("raw_glofas_", candidate_id)
  grid$model_id[rrow] <- grid$fit_id[rrow]
  grid$notes[qrow] <- candidate$rationale[[1L]]
  grid$notes[rrow] <- paste("Immutable raw GloFAS p95 comparator for", candidate_id)
  grid$config_hash <- "RUNTIME_CONFIG_HASH_RECORDED_IN_MANIFEST"
  model_grid_path <- file.path(candidate_root, "model_grid_p95.csv")
  app_write_csv(grid, model_grid_path)

  cfg <- base_cfg
  cfg$application_name <- paste0("glofas_p95_tau_warmup_", candidate_id)
  cfg$description <- paste("Cold-start p95 RHS global-scale warmup sensitivity:", candidate$rationale[[1L]])
  cfg$paths$input_bundle <- snapshot_paths$input_bundle
  cfg$paths$input_bundle_manifest <- snapshot_paths$input_bundle_manifest
  cfg$paths$input_manifest <- snapshot_paths$input_manifest
  cfg$paths$quantile_grid <- snapshot_paths$quantile_grid
  cfg$paths$model_grid <- model_grid_path
  cfg$paths$cache <- file.path(output_root, "common_cache")
  cfg$paths$runs <- file.path(output_root, "runs")
  cfg$paths$logs <- file.path(output_root, "logs")
  cfg$paths$generated_outputs <- file.path(output_root, "generated")
  cfg$inference$vb_ld$rhs_freeze_tau_warmup_iters <- freeze_iters
  cfg$inference$vb_ld$rhs_update_every <- 1L
  cfg$inference$vb_ld$rhs_min_tau_updates <- 1L
  cfg$inference$vb_ld$warm_start <- list(enabled = FALSE)
  cfg$execution$final_launch$enabled <- TRUE
  cfg$execution$final_launch$note <- paste(
    "Controlled p95-only global-scale warmup sensitivity; k =", freeze_iters,
    "; no forecast-window selection or automatic promotion"
  )
  cfg$execution$artifacts <- list(
    retain_fit_object = TRUE,
    retain_design_object = TRUE,
    retain_prediction_design_object = TRUE,
    retain_reference_fit_object = TRUE
  )
  cfg$post_analysis$run_after_outputs <- TRUE
  cfg$post_analysis$recent_history_n <- 200L
  cfg$post_analysis$storage$write_history_draws_rds <- FALSE
  cfg$post_analysis$storage$write_history_draws_csv <- FALSE
  config_path <- file.path(candidate_root, "config_p95.yaml")
  app_write_yaml(cfg, config_path)

  run_id <- paste0("glofas_fit_recovery_p95_tau_warmup_20260809_", candidate_id)
  runtime_rows[[length(runtime_rows) + 1L]] <- data.frame(
    candidate_id = candidate_id,
    priority = candidate$priority[[1L]],
    role = candidate$role[[1L]],
    rationale = candidate$rationale[[1L]],
    freeze_tau_warmup_iters = freeze_iters,
    expected_first_tau_update_iter = freeze_iters + 1L,
    expected_minimum_convergence_iter = freeze_iters + 2L,
    update_every = 1L,
    min_tau_updates = 1L,
    cold_start = TRUE,
    quantile_level = 0.95,
    config_path = normalizePath(config_path, mustWork = TRUE),
    config_sha256 = app_sha256_file(config_path),
    model_grid_path = normalizePath(model_grid_path, mustWork = TRUE),
    model_grid_sha256 = app_sha256_file(model_grid_path),
    run_id = run_id,
    run_dir = file.path(output_root, "runs", run_id),
    log_path = file.path(output_root, "logs", paste0(candidate_id, ".log")),
    source_kind = "new_cold_start_p95_global_scale_warmup_fit",
    status = "prepared",
    stringsAsFactors = FALSE
  )
}
runtime <- app_bind_rows_fill(runtime_rows)
runtime_path <- file.path(output_root, "runtime_manifest.csv")
app_write_csv(runtime, runtime_path)

source_manifest <- app_bind_rows_fill(lapply(names(source_assets), function(name) {
  source <- source_assets[[name]]
  snapshot <- snapshot_paths[[name]] %||% source
  data.frame(
    asset = name,
    source_path = normalizePath(source, mustWork = TRUE),
    source_sha256 = app_sha256_file(source),
    snapshot_path = normalizePath(snapshot, mustWork = TRUE),
    snapshot_sha256 = app_sha256_file(snapshot),
    identical = identical(app_sha256_file(source), app_sha256_file(snapshot)),
    stringsAsFactors = FALSE
  )
}))
app_write_csv(source_manifest, file.path(output_root, "manifest", "source_snapshot_manifest.csv"))
provenance <- data.frame(
  field = c(
    "prepared_at", "repo_head", "prepare_script_sha256", "candidate_manifest_path",
    "candidate_manifest_sha256", "base_config_source", "base_config_source_sha256",
    "control_fit_path", "control_fit_sha256", "selection_scope",
    "forecast_window_used_for_selection", "automatic_full7", "automatic_promotion"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)[[1L]],
    app_sha256_file(app_path("application/scripts/glofas_fit_recovery_p95_tau_warmup_prepare.R")),
    candidate_path,
    app_sha256_file(candidate_path),
    base_config_path,
    app_sha256_file(base_config_path),
    control_fit_path,
    control_fit_sha256,
    "observed_history_p95_only",
    "false", "false", "false"
  ),
  stringsAsFactors = FALSE
)
app_write_csv(provenance, file.path(output_root, "manifest", "preparation_provenance.csv"))
writeLines(c(
  "Controlled p95 RHS global-scale warmup batch prepared.",
  "Only the global tau/xi updates differ between k=25 and k=50.",
  "Coefficients, local RHS scales, slab scale, AL augmentation, sigma, and latent path update from iteration 1.",
  "Every source input is snapshotted and hash-verified in this runtime root.",
  "Selection is restricted to the observed history; no full-seven launch or promotion is automatic."
), file.path(output_root, "README.txt"))
cat(normalizePath(runtime_path, mustWork = TRUE), "\n")
