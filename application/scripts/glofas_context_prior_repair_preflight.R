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
source(app_path("application/R/launch_control.R"))
source(app_path("application/R/artifact_hygiene.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/glofas_discrepancy_transition.R"))
source(app_path("application/R/build_qdesn_features.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/fit_qdesn_discrepancy.R"))
source(app_path("application/R/latent_path_runtime_backend.R"))
source(app_path("application/R/latent_path_checkpoint.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/fit_qdesn_latent_path.R"))
source(app_path("application/R/glofas_discrepancy_transition_campaign.R"))
source(app_path("application/R/glofas_discrepancy_context_repair_campaign.R"))

args <- app_parse_args(list(
  output_root = "local_trackers/runtime_configs/glofas_context_prior_repair_20260826"
))
resolve_repo <- function(path, must_work = FALSE) {
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

output_root <- resolve_repo(args$output_root, must_work = TRUE)
manifest_path <- file.path(output_root, "runtime_manifest.csv")
manifest <- app_read_csv(manifest_path)
if (nrow(manifest) != 18L || anyDuplicated(manifest$candidate_id)) {
  stop("Context-prior preflight requires exactly 18 unique runtime rows.", call. = FALSE)
}
if (any(file.exists(file.path(manifest$run_dir, ".fit_recovery_complete")))) {
  stop("Context-prior preflight must run before campaign fits complete.", call. = FALSE)
}
for (i in seq_len(nrow(manifest))) {
  if (!file.exists(manifest$config_path[[i]]) ||
      !identical(app_sha256_file(manifest$config_path[[i]]), manifest$config_sha256[[i]]) ||
      !file.exists(manifest$model_grid_path[[i]]) ||
      !identical(app_sha256_file(manifest$model_grid_path[[i]]), manifest$model_grid_sha256[[i]]) ||
      !file.exists(manifest$warm_start_source_fit_object[[i]]) ||
      !identical(
        app_sha256_file(manifest$warm_start_source_fit_object[[i]]),
        manifest$warm_start_source_sha256[[i]]
      )) {
    stop(sprintf("Runtime row %s failed its file/hash contract.", manifest$candidate_id[[i]]), call. = FALSE)
  }
}

canary_row <- manifest[order(manifest$priority), , drop = FALSE][1L, , drop = FALSE]
canary_cfg <- app_read_config(canary_row$config_path[[1L]])
canary_grid <- app_read_csv(canary_row$model_grid_path[[1L]])
model_row <- canary_grid[
  canary_grid$model_family == "qdesn_glofas_discrepancy",
  ,
  drop = FALSE
]
if (nrow(model_row) != 1L) stop("The canary model row is not unique.", call. = FALSE)
panel_path <- file.path(app_config_path(canary_cfg, "cache"), "application_panel.rds")
if (!file.exists(panel_path)) stop("The prepared canary panel is missing.", call. = FALSE)
panel <- readRDS(panel_path)
cutoff_row <- app_read_csv(app_config_path(canary_cfg, "cutoffs"))[1L, , drop = FALSE]
design <- app_make_glofas_latent_path_design(
  panel = panel,
  cfg = canary_cfg,
  model_row = model_row,
  cutoff_row = cutoff_row
)
app_validate_glofas_latent_path_design(design)
design_summary <- app_latent_path_design_summary(design)
if (isTRUE(design_summary$covariate_uses_realized_future[[1L]]) ||
    !identical(design_summary$covariate_future_policy[[1L]], "origin_persistence")) {
  stop("The real-design canary failed the future-covariate policy.", call. = FALSE)
}

candidate_rows <- manifest[!duplicated(manifest$base_candidate_id), , drop = FALSE]
candidate_rows <- candidate_rows[order(candidate_rows$context_prior_sd), , drop = FALSE]
preflight_rows <- lapply(seq_len(nrow(candidate_rows)), function(i) {
  row <- candidate_rows[i, , drop = FALSE]
  cfg <- app_read_config(row$config_path[[1L]])
  grid <- app_read_csv(row$model_grid_path[[1L]])
  qrow <- grid[grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  prior <- app_map_qdesn_prior(qrow$coefficient_prior[[1L]])
  seed <- suppressWarnings(as.integer(app_model_row_value(
    qrow,
    "reservoir_seed",
    cfg$reservoir$seed %||% 20260513L
  )))
  vb_args <- app_make_qdesn_discrepancy_vb_args(
    cfg,
    prior = prior,
    seed = seed,
    likelihood_family = app_model_row_likelihood_family(qrow, cfg)
  )
  fixed_contract <- app_latent_path_context_fixed_gaussian_contract(
    design,
    vb_args$context_fixed_gaussian %||% NULL
  )
  if (!isTRUE(fixed_contract$enabled) || length(fixed_contract$groups) != 1L) {
    stop(sprintf("Candidate %s lacks one fixed prior group.", row$base_candidate_id[[1L]]), call. = FALSE)
  }
  group <- fixed_contract$groups[[1L]]
  if (length(group$global_index) != 1L ||
      !identical(group$column_name, "glofas_level_lag_0") ||
      !group$global_index %in% design$alpha_index ||
      group$global_index %in% design$intercept_index ||
      !isTRUE(all.equal(group$sd, as.numeric(row$context_prior_sd[[1L]])))) {
    stop(sprintf("Candidate %s mapped the wrong prior coefficient.", row$base_candidate_id[[1L]]), call. = FALSE)
  }
  vb_args$fixed_gaussian_groups <- fixed_contract$groups
  checkpoint_contract <- app_latent_checkpoint_contract(
    design = design,
    p0 = as.numeric(qrow$quantile_level[[1L]]),
    coefficient_prior = prior,
    vb_args = vb_args,
    seed = seed,
    backend_fail_closed = FALSE
  )
  source_contract <- app_latent_path_warm_start_contract_from_fit(
    row$warm_start_source_fit_object[[1L]]
  )
  compatibility <- app_latent_path_warm_start_compatibility(
    source_contract,
    app_latent_path_warm_start_contract(design),
    mode = "state_only"
  )
  if (!isTRUE(compatibility$accepted) ||
      !identical(compatibility$class, "state_only") ||
      isTRUE(compatibility$theta_allowed)) {
    stop(sprintf("Candidate %s failed state-only compatibility.", row$base_candidate_id[[1L]]), call. = FALSE)
  }
  data.frame(
    candidate_id = row$base_candidate_id[[1L]],
    context_prior_sd = as.numeric(row$context_prior_sd[[1L]]),
    coefficient_name = group$column_name,
    global_index = group$global_index,
    prior_contract_hash = fixed_contract$contract_hash,
    checkpoint_contract_hash = checkpoint_contract$contract_hash,
    warm_start_class = compatibility$class,
    theta_transfer_allowed = compatibility$theta_allowed,
    design_hash = design_summary$design_hash[[1L]],
    future_policy = design_summary$covariate_future_policy[[1L]],
    uses_realized_future = design_summary$covariate_uses_realized_future[[1L]],
    stringsAsFactors = FALSE
  )
})
preflight <- app_bind_rows_fill(preflight_rows)
if (nrow(preflight) != 6L ||
    anyDuplicated(preflight$context_prior_sd) ||
    anyDuplicated(preflight$prior_contract_hash) ||
    anyDuplicated(preflight$checkpoint_contract_hash)) {
  stop("Context-prior preflight hashes are not unique across all six scales.", call. = FALSE)
}
preflight_path <- file.path(output_root, "manifests", "context_prior_preflight.csv")
app_write_csv(preflight, preflight_path)
writeLines(c(
  format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  paste0("repo_head=", system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)[[1L]]),
  paste0("runtime_manifest_sha256=", app_sha256_file(manifest_path)),
  paste0("preflight_sha256=", app_sha256_file(preflight_path))
), file.path(output_root, ".context_prior_preflight_passed"))
cat(preflight_path, "\n")
