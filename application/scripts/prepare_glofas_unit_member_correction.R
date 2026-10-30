#!/usr/bin/env Rscript
# Preparation only: authenticate and materialize a new target; never fit here.
source("application/scripts/_glofas_unit_member_bootstrap.R")
args <- app_parse_args(list(source_root = "", output_root =
  "local_trackers/runtime_configs/glofas_unit_member_correction_20261029"))
source_root <- app_resolve_path(args$source_root, must_work = TRUE)
runtime <- app_resolve_path(args$output_root)
if (dir.exists(runtime) && length(list.files(runtime, all.files = TRUE, no.. = TRUE))) {
  stop("Refusing to overwrite a nonempty correction runtime.", call. = FALSE)
}
contract <- app_read_csv("application/config/glofas_unit_member_source_contract_v1.csv")
sources <- file.path(source_root, contract$relative_path)
observed <- vapply(sources, app_sha256_file, character(1L))
if (any(observed != contract$sha256)) stop("Frozen source SHA256 mismatch.", call. = FALSE)
old_runtime <- file.path(source_root, "glofas_part4_search3_dependency_closure_20260930_r4")
old_repo <- normalizePath(file.path(source_root, "..", ".."), mustWork = TRUE)
resolve_old <- function(path) {
  if (grepl("^/", path)) normalizePath(path, mustWork = TRUE) else
    normalizePath(file.path(old_repo, path), mustWork = TRUE)
}
for (dir in c("objects", "configs", "manifests", "status", "logs", "traces",
    "scores", "predictions", "coefficients")) app_ensure_dir(file.path(runtime, dir))
frozen <- readRDS(sources[[1L]])
app_qdesn_engine_function <- function(...) stop(
  "Frozen-design materialization must not load a moving external feature engine.", call. = FALSE)
message("Building the new unit-member design from authenticated frozen geometry...")
design <- app_glofas_unit_member_materialize_design(frozen)
app_glofas_unit_member_validate_design(design)
prior <- readRDS(sources[[2L]])
bank <- readRDS(sources[[3L]])
bank_source_fit <- as.character(bank$contract$source_fit_path)
if (!file.exists(bank_source_fit)) {
  bank_source_fit <- file.path(source_root,
    "glofas_search3_full_dependency_closure_20260930_r4/objects", basename(bank_source_fit))
}
if (!file.exists(bank_source_fit) ||
    !identical(app_sha256_file(bank_source_fit), bank$contract$source_fit_sha256)) {
  stop("The historical bank source fit is missing or has the wrong hash.", call. = FALSE)
}
app_validate_glofas_part4_normal_driver_prior(prior, as.Date(design$future_key$target_date), "log1p", 500L)
keep <- seq_len(28L)
short_bank <- app_glofas_normal_driver_bank(
  future_dates = as.Date(bank$contract$future_dates)[keep],
  components = lapply(bank$components, function(x) as.matrix(x)[keep, , drop = FALSE]),
  cutoff_date = bank$contract$cutoff_date, seed = bank$contract$seed,
  source_fit_path = bank$contract$source_fit_path,
  source_fit_sha256 = bank$contract$source_fit_sha256,
  source_model_id = bank$contract$source_model_id,
  response_scale = bank$contract$response_scale,
  exogenous_policy = bank$contract$exogenous_policy,
  observed_sources = bank$contract$observed_sources,
  forbidden_sources = bank$contract$forbidden_sources)
rebuilt_prior <- app_glofas_part4_normal_driver_prior(short_bank)
if (!identical(prior$contract_hash, rebuilt_prior$contract_hash) ||
    !isTRUE(all.equal(prior$mean, rebuilt_prior$mean, tolerance = 1e-12)) ||
    !isTRUE(all.equal(prior$covariance, rebuilt_prior$covariance, tolerance = 1e-12))) {
  stop("Frozen Gaussian path prior does not reconstruct from the historical bank.", call. = FALSE)
}
design_path <- file.path(runtime, "objects/part4_shared_design_truth_free.rds")
app_glofas_part4_atomic_save_rds(app_latent_path_drop_runtime_cache(design, compact = FALSE), design_path)
for (name in c("part4_normal_driver_prior.rds", "part4_scoring_panel_sidecar.rds")) {
  if (!file.copy(file.path(old_runtime, "objects", name), file.path(runtime, "objects", name))) {
    stop("Could not copy authenticated reused input: ", name, call. = FALSE)
  }
}
old_manifest_path <- file.path(old_runtime, "configs/part4_model_manifest.csv")
manifest <- app_read_csv(old_manifest_path)
if (nrow(manifest) != 18L || anyDuplicated(manifest$run_id)) stop("Expected exactly 18 frozen initial fits.")
old_ids <- manifest$run_id
label <- basename(runtime)
manifest$run_id <- sub(basename(old_runtime), label, old_ids, fixed = TRUE)
manifest$run_label <- label
manifest$source_job_id <- old_ids
manifest$target_schema <- "glofas_unit_member_part4_v1"
manifest$worker_slots <- 1L
manifest$status <- "pending_new_target"
manifest$dependencies <- vapply(manifest$dependencies, function(value) {
  deps <- strsplit(as.character(value), "|", fixed = TRUE)[[1L]]
  if (!length(deps) || !nzchar(deps[[1L]])) return("")
  mapped <- manifest$run_id[match(deps, old_ids)]
  if (anyNA(mapped)) stop("Unknown dependency in frozen Part 4 DAG.")
  paste(mapped, collapse = "|")
}, character(1L))
reused <- c(sources, bank_source_fit, old_manifest_path,
  file.path(old_runtime, "configs/selected_anchor_manifest.csv"),
  file.path(old_runtime, "objects/part4_scoring_panel_sidecar.rds"))
for (i in seq_len(nrow(manifest))) {
  old_config <- resolve_old(manifest$config_path[[i]])
  cfg <- app_read_config(old_config)
  folder <- file.path(runtime, "configs", manifest$run_id[[i]])
  app_ensure_dir(folder)
  for (field in c("model_grid_path", "quantile_grid_path")) {
    src <- resolve_old(manifest[[field]][[i]])
    dest <- file.path(folder, basename(src))
    if (!file.copy(src, dest)) stop("Config asset copy failed.")
    manifest[[field]][[i]] <- dest
    reused <- c(reused, src)
  }
  # Resolve preserved, read-only inputs; redirect only output directories.
  for (key in intersect(c("schema", "cutoffs", "source_registry", "figure_specs",
      "input_bundle", "input_bundle_manifest", "input_manifest"), names(cfg$paths))) {
    cfg$paths[[key]] <- resolve_old(cfg$paths[[key]])
    reused <- c(reused, cfg$paths[[key]])
  }
  for (key in c("cache", "runs", "logs", "generated_outputs")) {
    cfg$paths[[key]] <- file.path(runtime, key)
  }
  cfg$paths$model_grid <- manifest$model_grid_path[[i]]
  cfg$paths$quantile_grid <- manifest$quantile_grid_path[[i]]
  cfg$application_model$ensemble_member_weight_policy <- "unit_member_likelihood_v1"
  cfg$unit_member_execution <- app_glofas_unit_member_default_controls()
  cfg$application_name <- manifest$run_id[[i]]
  cfg$description <- "Unit-member Part 4 corrective fit; frozen historical features and priors; future truth scoring-only."
  dest <- file.path(folder, basename(old_config))
  app_write_yaml(cfg, dest)
  manifest$config_path[[i]] <- dest
  manifest$launch_command[[i]] <- "managed_by_launch_glofas_unit_member_correction.py"
  reused <- c(reused, old_config)
}
input_path <- resolve_old(app_read_config(resolve_old(app_read_csv(old_manifest_path)$config_path[[1L]]))$paths$input_manifest)
input_rows <- app_read_csv(input_path)
for (j in seq_len(nrow(input_rows))) {
  path <- resolve_old(input_rows$local_path[[j]])
  if (!identical(app_sha256_file(path), as.character(input_rows$sha256[[j]]))) {
    stop("Authoritative input manifest hash mismatch: ", path, call. = FALSE)
  }
  reused <- c(reused, path)
}
file.copy(file.path(old_runtime, "configs/selected_anchor_manifest.csv"),
  file.path(runtime, "configs/selected_anchor_manifest.csv"))
app_write_csv(manifest, file.path(runtime, "configs/part4_model_manifest.csv"))
reused <- unique(normalizePath(reused, mustWork = TRUE))
reuse_manifest <- data.frame(path = reused,
  size_bytes = as.numeric(file.info(reused)$size),
  sha256 = vapply(reused, app_sha256_file, character(1L)), stringsAsFactors = FALSE)
app_write_csv(reuse_manifest, file.path(runtime, "manifests/reused_source_manifest.csv"))
receipt <- c(app_glofas_unit_member_contract(), list(
  status = "prepared_pending_tests_commit_and_parent_launch_review",
  source_root = source_root, runtime_root = runtime,
  old_design_sha256 = contract$sha256[[1L]],
  new_design_sha256 = app_sha256_file(design_path),
  old_state_hash = app_glofas_part4_state_contract_hash(frozen),
  new_state_hash = app_glofas_part4_state_contract_hash(design),
  historical_geometry_identical = TRUE, driver_prior_reconstruction_verified = TRUE,
  historical_bank_recorded_source_fit = bank$contract$source_fit_path,
  historical_bank_verified_retained_copy = bank_source_fit,
  external_feature_engine_lookup_blocked = TRUE,
  feature_provenance = list(
    discrepancy_input_stream = design$discrepancy_input_stream,
    reference_feature_count_including_intercept = length(design$beta_index),
    discrepancy_feature_count_including_intercept = length(design$alpha_index),
    historical_rows = nrow(design$H_fixed),
    reference_feature_contract = design$feature_meta_beta$feature_contract,
    discrepancy_feature_contract = design$feature_meta_alpha$feature_contract,
    reference_block_config = design$block_config_beta$feature_contract,
    discrepancy_block_config = design$block_config_alpha$feature_contract),
  initial_fit_units = 18L, new_completed_fit_units = 0L,
  runs_launched = FALSE, cpu_pool = 48:55, max_workers = 8L,
  joint_inner_workers = 1L, blas_threads = 1L,
  continuation_policy = "none_automatic_cap_requires_scientific_review",
  controls = app_glofas_unit_member_default_controls()))
app_write_json(receipt, file.path(runtime, "PREFLIGHT.json"))
cat("PREPARED_NO_PRODUCTION_LAUNCH\n", normalizePath(file.path(runtime, "PREFLIGHT.json")), "\n")
