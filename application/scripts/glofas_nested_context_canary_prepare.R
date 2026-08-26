#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(
  dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])),
  "..", ".."
), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  output_root = "local_trackers/runtime_configs/glofas_nested_context_canary_20260826"
))
output_root <- if (grepl("^/", args$output_root)) args$output_root else app_path(args$output_root)
output_root <- normalizePath(output_root, mustWork = FALSE)
if (dir.exists(output_root) && length(list.files(output_root, all.files = TRUE, no.. = TRUE))) {
  stop("Canary output root already exists and is nonempty.", call. = FALSE)
}
for (name in c("candidates", "runs", "logs", "scores", "status", "tables", "common_cache", "manifests")) {
  app_ensure_dir(file.path(output_root, name))
}

prior_root <- app_path("local_trackers/runtime_configs/glofas_context_prior_repair_20260826")
repair_root <- app_path("local_trackers/runtime_configs/glofas_discrepancy_context_repair_20260825")
augmented_config <- file.path(prior_root, "candidates/ctxsd_0100/may11_2022/config_p50.yaml")
baseline_config <- file.path(repair_root, "candidates/t01_last/may11_2022/config_p50.yaml")
source_fit <- file.path(
  repair_root,
  "runs/glofas_discrepancy_context_repair_20260825_t01_last_may11_2022/objects/qdesn_transition_t01_last_may11_2022_p50.rds"
)
required <- c(augmented_config, baseline_config, source_fit)
if (!all(file.exists(required))) {
  stop(sprintf("Required retained evidence is missing: %s", paste(required[!file.exists(required)], collapse = ", ")), call. = FALSE)
}
source_object <- readRDS(source_fit)
source_contract <- source_object$warm_start_contract %||% NULL
if (is.null(source_contract) || is.null(source_contract$theta_names)) {
  stop("The retained T01 source fit lacks named warm-start coordinates.", call. = FALSE)
}

arms <- data.frame(
  candidate_id = c("may_exact_t01", "may_nested_ctx0100", "may_state_ctx0100"),
  source_config = c(baseline_config, augmented_config, augmented_config),
  compatibility_mode = c("exact_design", "nested_coordinate_transfer", "state_only"),
  use_theta = c(TRUE, TRUE, FALSE),
  new_coordinate_sd = c(NA_real_, 0.1, NA_real_),
  priority = 1:3,
  stringsAsFactors = FALSE
)

rows <- vector("list", nrow(arms))
for (i in seq_len(nrow(arms))) {
  arm <- arms[i, , drop = FALSE]
  id <- arm$candidate_id[[1L]]
  candidate_dir <- file.path(output_root, "candidates", id)
  app_ensure_dir(candidate_dir)
  cfg <- app_read_yaml(arm$source_config[[1L]])
  run_id <- paste0("glofas_nested_context_canary_20260826_", id)
  run_dir <- file.path(output_root, "runs", run_id)
  fit_id <- paste0("qdesn_nested_canary_", id, "_p50")
  raw_id <- paste0("raw_nested_canary_", id, "_p50")
  grid_path <- file.path(candidate_dir, "model_grid_p50.csv")
  config_path <- file.path(candidate_dir, "config_p50.yaml")
  checkpoint_path <- file.path(run_dir, "objects", paste0(fit_id, "__vb_checkpoint.rds"))

  cfg$application_name <- paste0("glofas_nested_context_canary_", id)
  cfg$description <- paste(
    "May-2022 GloFAS context initialization canary; fixed 150-iteration trajectory;",
    arm$compatibility_mode[[1L]]
  )
  cfg$paths$model_grid <- grid_path
  cfg$paths$quantile_grid <- file.path(candidate_dir, "quantile_grid_p50.csv")
  cfg$paths$runs <- file.path(output_root, "runs")
  cfg$paths$logs <- file.path(output_root, "logs")
  cfg$paths$cache <- file.path(output_root, "common_cache", id)
  cfg$paths$generated_outputs <- file.path(output_root, "generated")
  cfg$inference$vb_ld$max_iter <- 150L
  cfg$inference$vb_ld$max_iter_hard_cap <- 150L
  cfg$inference$vb_ld$diagnostics <- modifyList(
    cfg$inference$vb_ld$diagnostics %||% list(),
    list(fixed_iterations = TRUE, trace_iterations = TRUE)
  )
  cfg$inference$vb_ld$warm_start <- list(
    enabled = TRUE,
    fit_object = normalizePath(source_fit, mustWork = TRUE),
    use_theta = arm$use_theta[[1L]],
    use_future = TRUE,
    use_sigma = TRUE,
    require_theta = arm$use_theta[[1L]],
    require_future = TRUE,
    require_sigma = TRUE,
    require_contract = TRUE,
    compatibility_mode = arm$compatibility_mode[[1L]]
  )
  if (is.finite(arm$new_coordinate_sd[[1L]])) {
    cfg$inference$vb_ld$warm_start$new_coordinate_sd <- arm$new_coordinate_sd[[1L]]
  }
  cfg$inference$vb_ld$checkpoint <- list(
    enabled = TRUE, resume = FALSE, path = checkpoint_path,
    every_iterations = 25L, every_minutes = 20, keep_previous = TRUE,
    keep_on_success = FALSE, compress = FALSE
  )

  app_write_csv(data.frame(quantile_level = 0.5), cfg$paths$quantile_grid)
  grid <- data.frame(
    fit_id = c(raw_id, fit_id),
    model_id = c(raw_id, fit_id),
    model_family = c("raw_glofas", "qdesn_glofas_discrepancy"),
    quantile_level = c(0.5, 0.5),
    inference_method = c("none", "vb_ld"),
    coefficient_prior = c("none", "rhs"),
    reservoir_seed = c(NA, 20260512L),
    likelihood_family = c("none", "al"),
    required = TRUE,
    enabled = TRUE,
    config_hash = "RUNTIME_CONFIG_HASH_RECORDED_IN_MANIFEST",
    notes = paste("Nested context canary", id),
    stringsAsFactors = FALSE
  )
  app_write_csv(grid, grid_path)
  app_write_yaml(cfg, config_path)
  rows[[i]] <- data.frame(
    candidate_id = id,
    priority = arm$priority[[1L]],
    config_path = normalizePath(config_path, mustWork = TRUE),
    config_sha256 = app_sha256_file(config_path),
    model_grid_path = normalizePath(grid_path, mustWork = TRUE),
    model_grid_sha256 = app_sha256_file(grid_path),
    run_id = run_id,
    run_dir = normalizePath(run_dir, mustWork = FALSE),
    log_path = file.path(output_root, "logs", paste0(id, ".log")),
    checkpoint_path = checkpoint_path,
    checkpoint_resume_enabled = TRUE,
    warm_start_source_fit_object = normalizePath(source_fit, mustWork = TRUE),
    warm_start_source_sha256 = app_sha256_file(source_fit),
    warm_start_compatibility_mode = arm$compatibility_mode[[1L]],
    warm_start_use_theta = arm$use_theta[[1L]],
    reservoir_preflight_enabled = FALSE,
    status = "prepared_not_launched",
    stringsAsFactors = FALSE
  )
}
manifest <- do.call(rbind, rows)
app_write_csv(manifest, file.path(output_root, "runtime_manifest.csv"))
app_write_csv(arms, file.path(output_root, "candidate_registry_snapshot.csv"))
app_write_yaml(list(
  schema_version = "glofas_nested_context_canary_v1",
  campaign_id = "glofas_nested_context_canary_20260826",
  authoritative_result = "glofas_fr09_authoritative_full7_20260811",
  origin = "2022-05-11",
  expected_fits = 3L,
  fixed_iterations = 150L,
  source_fit = normalizePath(source_fit, mustWork = TRUE),
  source_fit_sha256 = app_sha256_file(source_fit),
  source_theta_names_hash = source_contract$theta_names_hash,
  continuation_policy = "fail_closed_after_may_canary",
  article_update_enabled = FALSE,
  full7_enabled = FALSE
), file.path(output_root, "campaign_snapshot.yaml"))
app_write_csv(data.frame(
  artifact = c("runtime_manifest.csv", "candidate_registry_snapshot.csv", "campaign_snapshot.yaml"),
  sha256 = vapply(c("runtime_manifest.csv", "candidate_registry_snapshot.csv", "campaign_snapshot.yaml"), function(x) {
    app_sha256_file(file.path(output_root, x))
  }, character(1L)),
  stringsAsFactors = FALSE
), file.path(output_root, "manifests", "packet_hashes.csv"))
cat(output_root, "\n")
