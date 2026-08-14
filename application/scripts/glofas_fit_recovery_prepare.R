#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_fit_recovery.R"))

args <- app_parse_args(list(
  candidate_manifest = "application/config/glofas_fit_recovery_candidates_20260730.csv",
  historical_registry = "application/config/glofas_fit_recovery_historical_registry_20260730.csv",
  base_config = "application/config/glofas_latent_path_al_vb_dec25_memrefine16_d1n300_m360_a92_r95_w018_bt1em01_at3em02_skip_main1000_engine73c.yaml",
  base_model_grid = "application/config/model_grid_latent_path_al_vb_dec25_memrefine16_d1n300_m360_a92_r95_w018_bt1em01_at3em02_skip_main1000_engine73c.csv",
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_20260730",
  authoritative_root = "/data/jaguir26/local/src/Article-Q-DESN---Version-2",
  legacy_root = "/data/jaguir26/local/src/Article-Q-DESN",
  engine_root = "/data/jaguir26/local/src/exdqlm__wt__article_app_engine_73c043f"
))

resolve_repo <- function(path) {
  if (grepl("^/", path)) normalizePath(path, mustWork = FALSE) else app_path(path)
}

git_value <- function(root, command) {
  out <- system2("git", c("-C", root, command), stdout = TRUE, stderr = TRUE)
  if (!length(out) || any(grepl("^fatal:", out))) NA_character_ else out[[1L]]
}

rewrite_data_path <- function(x, data_root) {
  x <- as.character(x)
  prefix <- "application/data_local"
  hit <- startsWith(x, prefix)
  x[hit] <- paste0(data_root, substring(x[hit], nchar(prefix) + 1L))
  x
}

copy_evidence <- function(registry, legacy_root, evidence_root) {
  allowlist <- c(
    "manifest/run_config.yaml",
    "manifest/git_state.txt",
    "manifest/qdesn_discrepancy_fit_manifest.csv",
    "tables/qdesn_discrepancy_design_summary.csv",
    "tables/qdesn_discrepancy_fit_diagnostics.csv",
    "tables/post_fit_quantile_history_summary.csv",
    "tables/post_fit_trace_summary.csv",
    "tables/score_summary.csv",
    "figures/post_fit_analysis"
  )
  rows <- list()
  for (i in seq_len(nrow(registry))) {
    candidate_id <- registry$candidate_id[[i]]
    run_id <- registry$legacy_run_id[[i]]
    run_dir <- file.path(legacy_root, "application", "runs", run_id)
    if (!dir.exists(run_dir)) {
      stop(sprintf("Historical evidence run is missing: %s.", run_dir), call. = FALSE)
    }
    candidate_root <- file.path(evidence_root, candidate_id)
    app_ensure_dir(candidate_root)
    paths <- character()
    for (relative in allowlist) {
      source <- file.path(run_dir, relative)
      if (dir.exists(source)) {
        paths <- c(paths, list.files(source, recursive = TRUE, full.names = TRUE))
      } else if (file.exists(source)) {
        paths <- c(paths, source)
      }
    }
    paths <- unique(paths[file.exists(paths) & !dir.exists(paths)])
    for (source in paths) {
      relative <- substring(source, nchar(run_dir) + 2L)
      target <- file.path(candidate_root, relative)
      app_ensure_dir(dirname(target))
      if (!file.copy(source, target, overwrite = TRUE, copy.mode = TRUE, copy.date = TRUE)) {
        stop(sprintf("Could not copy historical evidence: %s.", source), call. = FALSE)
      }
      rows[[length(rows) + 1L]] <- data.frame(
        candidate_id = candidate_id,
        legacy_run_id = run_id,
        source_path = source,
        copied_path = target,
        size_bytes = as.numeric(file.info(target)$size),
        sha256 = app_sha256_file(target),
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

output_root <- resolve_repo(args$output_root)
authoritative_root <- normalizePath(args$authoritative_root, mustWork = TRUE)
legacy_root <- normalizePath(args$legacy_root, mustWork = TRUE)
engine_root <- normalizePath(args$engine_root, mustWork = TRUE)
data_root <- file.path(authoritative_root, "application", "data_local")
if (!dir.exists(data_root)) stop(sprintf("Authoritative data root is missing: %s.", data_root), call. = FALSE)

app_ensure_dir(output_root)
app_ensure_dir(file.path(output_root, "candidates"))
app_ensure_dir(file.path(output_root, "common_cache"))
app_ensure_dir(file.path(output_root, "runs"))
app_ensure_dir(file.path(output_root, "logs"))
app_ensure_dir(file.path(output_root, "generated"))
app_ensure_dir(file.path(output_root, "evidence"))
app_ensure_dir(file.path(output_root, "scores"))
app_ensure_dir(file.path(output_root, "status"))
app_ensure_dir(file.path(output_root, "cleanup"))

candidates <- app_read_csv(resolve_repo(args$candidate_manifest))
candidates <- app_glofas_fit_recovery_validate_candidates(candidates)
registry <- app_read_csv(resolve_repo(args$historical_registry))
base_cfg <- app_read_config(resolve_repo(args$base_config))
base_model_grid <- app_read_csv(resolve_repo(args$base_model_grid))
if (sum(base_model_grid$model_family == "qdesn_glofas_discrepancy") != 1L) {
  stop("The base model grid must contain exactly one Q-DESN row.", call. = FALSE)
}

source_manifest_root <- file.path(authoritative_root, "application", "manifests")
input_manifest <- app_read_csv(file.path(source_manifest_root, "input_manifest.csv"))
bundle_manifest <- app_read_csv(file.path(source_manifest_root, "input_bundle_manifest.csv"))
input_manifest$local_path <- rewrite_data_path(input_manifest$local_path, data_root)
for (field in intersect(c("bundle_root", "local_path"), names(bundle_manifest))) {
  bundle_manifest[[field]] <- rewrite_data_path(bundle_manifest[[field]], data_root)
}
input_manifest_path <- file.path(output_root, "input_manifest_absolute.csv")
bundle_manifest_path <- file.path(output_root, "input_bundle_manifest_absolute.csv")
app_write_csv(input_manifest, input_manifest_path)
app_write_csv(bundle_manifest, bundle_manifest_path)

input_bundle <- app_read_yaml(resolve_repo(base_cfg$paths$input_bundle))
input_bundle$bundle_root <- file.path(
  data_root,
  "frozen_inputs",
  "authoritative_cutoffs",
  "cutoff_date=2022-12-25"
)
input_bundle$manifest_output <- input_manifest_path
input_bundle$bundle_manifest_output <- bundle_manifest_path
input_bundle_path <- file.path(output_root, "input_bundle_absolute.yaml")
app_write_yaml(input_bundle, input_bundle_path)

quantile_grid <- data.frame(
  quantile_id = "p50",
  quantile_level = 0.5,
  role = "median",
  enabled = TRUE,
  stringsAsFactors = FALSE
)
quantile_grid_path <- file.path(output_root, "quantile_grid_p50.csv")
app_write_csv(quantile_grid, quantile_grid_path)

runtime_rows <- list()
for (i in seq_len(nrow(candidates))) {
  candidate <- candidates[i, , drop = FALSE]
  candidate_id <- candidate$candidate_id[[1L]]
  candidate_root <- file.path(output_root, "candidates", candidate_id)
  app_ensure_dir(candidate_root)

  cfg <- base_cfg
  cfg$application_name <- paste0("glofas_fit_recovery_", candidate_id)
  cfg$description <- paste(
    "Historical-fit recovery candidate", candidate_id, "-",
    candidate$description[[1L]]
  )
  cfg$paths$input_bundle <- input_bundle_path
  cfg$paths$input_bundle_manifest <- bundle_manifest_path
  cfg$paths$input_manifest <- input_manifest_path
  cfg$paths$model_grid <- file.path(candidate_root, "model_grid_p50.csv")
  cfg$paths$quantile_grid <- quantile_grid_path
  cfg$paths$data_local <- data_root
  cfg$paths$cache <- file.path(output_root, "common_cache")
  cfg$paths$runs <- file.path(output_root, "runs")
  cfg$paths$logs <- file.path(output_root, "logs")
  cfg$paths$generated_outputs <- file.path(output_root, "generated")
  cfg$dependencies$qdesn_engine_repo_hint <- engine_root
  cfg$dependencies$qdesn_engine_expected_repo_hint <- engine_root
  cfg$covariates$forecast$handoff_root <- rewrite_data_path(
    cfg$covariates$forecast$handoff_root,
    data_root
  )
  cfg$reservoir$alpha <- as.numeric(candidate$alpha[[1L]])
  cfg$feature_contract$readout$include_input_block <- isTRUE(candidate$include_input_block[[1L]])
  if (isTRUE(candidate$include_input_block[[1L]])) {
    cfg$feature_contract$readout$input_block$output_lags <- list(
      range = c(1L, as.integer(candidate$direct_output_lag_max[[1L]]))
    )
    covariate_max <- as.integer(candidate$direct_covariate_lag_max[[1L]])
    cfg$feature_contract$readout$input_block$covariates$ppt <- list(range = c(0L, covariate_max))
    cfg$feature_contract$readout$input_block$covariates$soil <- list(range = c(0L, covariate_max))
  }
  cfg$inference$vb_ld$rhs_tau0 <- as.numeric(candidate$rhs_tau0[[1L]])
  cfg$inference$vb_ld$rhs_alpha_tau0 <- as.numeric(candidate$rhs_alpha_tau0[[1L]])
  cfg$post_analysis$run_after_outputs <- TRUE
  cfg$post_analysis$recent_history_n <- 200L
  cfg$post_analysis$storage$write_history_draws_rds <- FALSE
  cfg$post_analysis$storage$write_history_draws_csv <- FALSE
  cfg$execution$artifacts <- list(
    retain_fit_object = TRUE,
    retain_design_object = TRUE,
    retain_prediction_design_object = TRUE,
    retain_reference_fit_object = TRUE
  )
  cfg$execution$final_launch$enabled <- TRUE
  cfg$execution$final_launch$note <- paste(
    "Explicitly authorized historical-fit recovery candidate", candidate_id
  )

  fit_id <- paste0("qdesn_latent_path_fit_recovery_", candidate_id, "_p50")
  raw_fit_id <- paste0("raw_glofas_fit_recovery_", candidate_id, "_p50")
  model_grid <- base_model_grid
  raw_row <- model_grid$model_family == "raw_glofas"
  qdesn_row <- model_grid$model_family == "qdesn_glofas_discrepancy"
  model_grid$fit_id[raw_row] <- raw_fit_id
  model_grid$model_id[raw_row] <- raw_fit_id
  model_grid$fit_id[qdesn_row] <- fit_id
  model_grid$model_id[qdesn_row] <- fit_id
  model_grid$notes[qdesn_row] <- candidate$description[[1L]]
  model_grid$notes[raw_row] <- paste("Raw GloFAS p50 baseline for", candidate_id)
  model_grid$config_hash <- "RUNTIME_CONFIG_HASH_RECORDED_IN_MANIFEST"
  app_write_csv(model_grid, cfg$paths$model_grid)

  config_path <- file.path(candidate_root, "config_p50.yaml")
  app_write_yaml(cfg, config_path)
  run_id <- paste0("glofas_fit_recovery_20260730_", candidate_id)
  runtime_rows[[length(runtime_rows) + 1L]] <- data.frame(
    candidate_id = candidate_id,
    role = candidate$role[[1L]],
    priority = as.integer(candidate$priority[[1L]]),
    config_path = config_path,
    config_sha256 = app_sha256_file(config_path),
    model_grid_path = cfg$paths$model_grid,
    model_grid_sha256 = app_sha256_file(cfg$paths$model_grid),
    run_id = run_id,
    run_dir = file.path(cfg$paths$runs, run_id),
    log_path = file.path(output_root, "logs", paste0(candidate_id, ".log")),
    include_input_block = isTRUE(candidate$include_input_block[[1L]]),
    direct_output_lag_max = candidate$direct_output_lag_max[[1L]],
    direct_covariate_lag_max = candidate$direct_covariate_lag_max[[1L]],
    alpha = candidate$alpha[[1L]],
    rhs_tau0 = candidate$rhs_tau0[[1L]],
    rhs_alpha_tau0 = candidate$rhs_alpha_tau0[[1L]],
    expected_n_block_features = candidate$expected_n_block_features[[1L]],
    expected_design_hash = candidate$expected_design_hash[[1L]],
    retain_heavy = isTRUE(candidate$retain_heavy[[1L]]),
    status = "prepared",
    stringsAsFactors = FALSE
  )
}
runtime_manifest <- do.call(rbind, runtime_rows)
runtime_manifest_path <- file.path(output_root, "runtime_manifest.csv")
app_write_csv(runtime_manifest, runtime_manifest_path)

evidence_manifest <- copy_evidence(
  registry,
  legacy_root = legacy_root,
  evidence_root = file.path(output_root, "evidence")
)
app_write_csv(evidence_manifest, file.path(output_root, "evidence_manifest.csv"))

data_rows <- lapply(seq_len(nrow(input_manifest)), function(i) {
  path <- input_manifest$local_path[[i]]
  data.frame(
    input_id = input_manifest$input_id[[i]],
    path = path,
    size_bytes = as.numeric(file.info(path)$size),
    declared_sha256 = input_manifest$sha256[[i]],
    observed_sha256 = app_sha256_file(path),
    hash_match = identical(input_manifest$sha256[[i]], app_sha256_file(path)),
    stringsAsFactors = FALSE
  )
})
data_provenance <- do.call(rbind, data_rows)
if (!all(data_provenance$hash_match)) stop("One or more authoritative input hashes changed.", call. = FALSE)
app_write_csv(data_provenance, file.path(output_root, "input_provenance.csv"))

provenance <- data.frame(
  field = c(
    "prepared_at", "article_repo", "article_branch", "article_head",
    "origin_main", "engine_repo", "engine_branch", "engine_head",
    "authoritative_data_root", "candidate_manifest_sha256"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    repo_root,
    git_value(repo_root, "rev-parse --abbrev-ref HEAD"),
    git_value(repo_root, "rev-parse HEAD"),
    git_value(repo_root, "rev-parse origin/main"),
    engine_root,
    git_value(engine_root, "rev-parse --abbrev-ref HEAD"),
    git_value(engine_root, "rev-parse HEAD"),
    data_root,
    app_sha256_file(resolve_repo(args$candidate_manifest))
  ),
  stringsAsFactors = FALSE
)
app_write_csv(provenance, file.path(output_root, "provenance.csv"))

cat(runtime_manifest_path, "\n")
