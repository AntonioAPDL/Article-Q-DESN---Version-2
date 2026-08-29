#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))

args <- app_parse_args(list(
  baseline_registry = "application/config/glofas_constrained_median_baseline_fr09.yaml",
  output_root = "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_p50_20260829"
))

resolve_path <- function(path, base = repo_root, must_work = TRUE) {
  normalizePath(
    if (grepl("^/", path)) path else file.path(base, path),
    mustWork = must_work
  )
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
verify_declared <- function(entry, label) {
  path <- resolve_path(as.character(entry$path[[1L]]), must_work = TRUE)
  observed <- app_sha256_file(path)
  expected <- as.character(entry$sha256[[1L]])
  if (!identical(observed, expected)) {
    stop(sprintf("%s hash mismatch: expected %s, observed %s.", label, expected, observed), call. = FALSE)
  }
  path
}

registry_path <- resolve_path(args$baseline_registry)
registry <- app_read_yaml(registry_path)
if (!identical(registry$baseline_id, "glofas_fr09_authoritative_full7_20260811") ||
    !identical(registry$status, "promoted_authoritative")) {
  stop("The declared baseline registry is not the authoritative FR09 contract.", call. = FALSE)
}
base_config_path <- verify_declared(registry$artifacts$base_config, "FR09 base config")
base_model_grid_path <- verify_declared(registry$artifacts$base_model_grid, "FR09 model grid")
base_cfg <- app_read_yaml(base_config_path)

source_path <- function(path) {
  resolve_path(path, base = dirname(base_config_path), must_work = TRUE)
}
source_assets <- list(
  base_config = base_config_path,
  base_model_grid = base_model_grid_path,
  quantile_grid = source_path(base_cfg$paths$quantile_grid),
  input_bundle = source_path(base_cfg$paths$input_bundle),
  input_bundle_manifest = source_path(base_cfg$paths$input_bundle_manifest),
  input_manifest = source_path(base_cfg$paths$input_manifest),
  application_panel = source_path(file.path(base_cfg$paths$cache, "application_panel.rds"))
)

output_root <- resolve_path(args$output_root, must_work = FALSE)
for (dir in c("source", "candidate", "common_cache", "runs", "logs", "generated", "scores", "status", "tables", "manifest")) {
  app_ensure_dir(file.path(output_root, dir))
}
snapshots <- list(
  base_config = copy_verified(source_assets$base_config, file.path(output_root, "source", "fr09_config_p50.yaml")),
  base_model_grid = copy_verified(source_assets$base_model_grid, file.path(output_root, "source", "fr09_model_grid_p50.csv")),
  quantile_grid = copy_verified(source_assets$quantile_grid, file.path(output_root, "source", "quantile_grid_p50.csv")),
  input_bundle = copy_verified(source_assets$input_bundle, file.path(output_root, "source", "input_bundle.yaml")),
  input_bundle_manifest = copy_verified(
    source_assets$input_bundle_manifest,
    file.path(output_root, "source", "input_bundle_manifest.csv")
  ),
  input_manifest = copy_verified(source_assets$input_manifest, file.path(output_root, "source", "input_manifest.csv")),
  application_panel = copy_verified(
    source_assets$application_panel,
    file.path(output_root, "common_cache", "application_panel.rds")
  )
)

quantiles <- app_read_csv(snapshots$quantile_grid)
if (nrow(quantiles) != 1L || abs(as.numeric(quantiles$quantile_level[[1L]]) - 0.5) > 1e-12) {
  stop("The immutable source quantile grid is not p50-only.", call. = FALSE)
}
grid <- app_read_csv(snapshots$base_model_grid)
qrow <- grid$model_family == "qdesn_glofas_discrepancy"
rrow <- grid$model_family == "raw_glofas"
if (sum(qrow) != 1L || sum(rrow) != 1L) {
  stop("The FR09 source grid must contain one Q-DESN row and one raw comparator row.", call. = FALSE)
}

candidate_id <- "fr09_shared_reference_input_single_readout_p50"
fit_id <- paste0("qdesn_", candidate_id)
run_id <- paste0("glofas_", candidate_id, "_20260829")
grid$fit_id[qrow] <- fit_id
grid$model_id[qrow] <- fit_id
grid$fit_id[rrow] <- paste0("raw_glofas_", candidate_id)
grid$model_id[rrow] <- grid$fit_id[rrow]
grid$config_hash <- "RUNTIME_CONFIG_HASH_RECORDED_IN_MANIFEST"
grid$notes[qrow] <- paste(
  "FR09 p50 controlled input ablation: separate reservoirs receive the same reference/PPT/soil stream;",
  "the common direct input block appears only in the reference readout"
)
grid$notes[rrow] <- "Immutable raw GloFAS p50 comparator"
model_grid_path <- file.path(output_root, "candidate", "model_grid_p50.csv")
app_write_csv(grid, model_grid_path)

cfg <- base_cfg
cfg$application_name <- "glofas_fr09_shared_reference_input_single_readout_p50"
cfg$description <- paste(
  "Controlled FR09 p50 refit with two independently seeded DESNs driven by the same transformed",
  "reference streamflow/PPT/soil input and one common direct readout input block."
)
cfg$paths$input_bundle <- snapshots$input_bundle
cfg$paths$input_bundle_manifest <- snapshots$input_bundle_manifest
cfg$paths$input_manifest <- snapshots$input_manifest
cfg$paths$quantile_grid <- snapshots$quantile_grid
cfg$paths$model_grid <- model_grid_path
cfg$paths$cache <- file.path(output_root, "common_cache")
cfg$paths$runs <- file.path(output_root, "runs")
cfg$paths$logs <- file.path(output_root, "logs")
cfg$paths$generated_outputs <- file.path(output_root, "generated")
cfg$feature_contract$blocks <- list(
  reference = list(
    input_stream = "reference",
    reservoir_seed = 20260512L
  ),
  discrepancy = list(
    input_stream = "reference",
    reservoir_seed = 20261521L,
    readout = list(include_input_block = FALSE)
  )
)
cfg$inference$vb_ld$warm_start <- list(
  enabled = FALSE,
  reason = "FR09 has a different alpha-readout dimension and is not an exact-design warm start"
)
cfg$execution$final_launch$enabled <- TRUE
cfg$execution$final_launch$note <- paste(
  "Approved p50-only controlled input-stream ablation; no automatic promotion or full-seven launch"
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
app_qdesn_validate_block_configs(cfg)

if (!identical(app_qdesn_block_input_stream(cfg, "reference"), "reference") ||
    !identical(app_qdesn_block_input_stream(cfg, "discrepancy"), "reference")) {
  stop("Both candidate DESNs must resolve to the reference input stream.", call. = FALSE)
}
if (!isTRUE(app_feature_contract(app_qdesn_block_config(cfg, "reference"))$readout$include_input_block) ||
    isTRUE(app_feature_contract(app_qdesn_block_config(cfg, "discrepancy"))$readout$include_input_block)) {
  stop("The direct input block must occur in the reference readout only.", call. = FALSE)
}

config_path <- file.path(output_root, "candidate", "config_p50.yaml")
app_write_yaml(cfg, config_path)
config_sha256 <- app_sha256_file(config_path)

source_manifest <- do.call(rbind, lapply(names(source_assets), function(asset) {
  source <- source_assets[[asset]]
  snapshot <- snapshots[[asset]]
  data.frame(
    asset = asset,
    source_path = normalizePath(source, mustWork = TRUE),
    source_sha256 = app_sha256_file(source),
    snapshot_path = normalizePath(snapshot, mustWork = TRUE),
    snapshot_sha256 = app_sha256_file(snapshot),
    identical = identical(app_sha256_file(source), app_sha256_file(snapshot)),
    stringsAsFactors = FALSE
  )
}))
app_write_csv(source_manifest, file.path(output_root, "manifest", "source_snapshot_manifest.csv"))

contract <- data.frame(
  field = c(
    "baseline_id", "candidate_id", "quantile", "reference_input_stream", "discrepancy_input_stream",
    "reference_seed", "discrepancy_seed", "reference_direct_input_block", "discrepancy_direct_input_block",
    "reference_rhs_tau0", "discrepancy_rhs_tau0", "max_iter", "automatic_promotion", "automatic_full7"
  ),
  value = c(
    registry$baseline_id, candidate_id, "0.50", "reference", "reference", "20260512", "20261521",
    "true", "false", as.character(cfg$inference$vb_ld$rhs_tau0),
    as.character(cfg$inference$vb_ld$rhs_alpha_tau0), as.character(cfg$inference$vb_ld$max_iter),
    "false", "false"
  ),
  stringsAsFactors = FALSE
)
app_write_csv(contract, file.path(output_root, "manifest", "candidate_contract.csv"))

runtime <- data.frame(
  candidate_id = candidate_id,
  run_id = run_id,
  fit_id = fit_id,
  quantile_level = 0.5,
  config_path = normalizePath(config_path, mustWork = TRUE),
  config_sha256 = config_sha256,
  model_grid_path = normalizePath(model_grid_path, mustWork = TRUE),
  model_grid_sha256 = app_sha256_file(model_grid_path),
  output_root = output_root,
  run_dir = file.path(output_root, "runs", run_id),
  log_path = file.path(output_root, "logs", paste0(candidate_id, ".log")),
  status = "prepared",
  stringsAsFactors = FALSE
)
runtime_path <- file.path(output_root, "runtime_manifest.csv")
app_write_csv(runtime, runtime_path)

provenance <- data.frame(
  field = c(
    "prepared_at", "repo_head", "prepare_script_sha256", "baseline_registry_path",
    "baseline_registry_sha256", "base_config_sha256", "base_model_grid_sha256",
    "candidate_config_sha256", "selection_scope"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)[[1L]],
    app_sha256_file(app_path("application/scripts/glofas_shared_input_p50_prepare.R")),
    registry_path, app_sha256_file(registry_path), app_sha256_file(base_config_path),
    app_sha256_file(base_model_grid_path), config_sha256, "p50 controlled refit only"
  ),
  stringsAsFactors = FALSE
)
app_write_csv(provenance, file.path(output_root, "manifest", "preparation_provenance.csv"))
writeLines(c(
  "FR09 shared-reference-input p50 candidate prepared.",
  "The discrepancy likelihood target remains the persistence-anchored GloFAS-minus-reference innovation.",
  "Only the discrepancy feature input stream and duplicate direct readout block change.",
  "The two reservoirs remain separate and use seeds 20260512 and 20261521.",
  "No warm start, automatic promotion, or automatic seven-quantile launch is permitted."
), file.path(output_root, "README.txt"))
cat(normalizePath(runtime_path, mustWork = TRUE), "\n")
