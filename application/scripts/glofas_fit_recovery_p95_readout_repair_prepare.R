#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_fit_recovery.R"))

args <- app_parse_args(list(
  base_config = "local_trackers/runtime_configs/glofas_fit_recovery_transition_full7_20260808/candidates/fr09_persistence_innovation/p95/config_p95.yaml",
  candidates = "application/config/glofas_fit_recovery_p95_readout_repair_candidates_20260809.csv",
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_p95_readout_repair_20260809"
))
resolve_repo <- function(path, must_work = FALSE) {
  normalizePath(if (grepl("^/", path)) path else app_path(path), mustWork = must_work)
}
base_config_path <- resolve_repo(args$base_config, TRUE)
candidate_path <- resolve_repo(args$candidates, TRUE)
output_root <- resolve_repo(args$output_root, FALSE)
for (dir in c("candidates", "logs", "runs", "generated", "scores", "status")) {
  app_ensure_dir(file.path(output_root, dir))
}

candidates <- app_read_csv(candidate_path)
required <- c(
  "candidate_id", "priority", "include_direct_covariates", "rhs_tau0",
  "rhs_alpha_tau0", "role", "rationale"
)
missing <- setdiff(required, names(candidates))
if (!nrow(candidates) || length(missing)) {
  stop(sprintf("P95 repair candidates are empty or missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
}
candidates$include_direct_covariates <- app_as_bool_vec(candidates$include_direct_covariates)
candidates$priority <- as.integer(candidates$priority)
candidates$rhs_tau0 <- as.numeric(candidates$rhs_tau0)
candidates$rhs_alpha_tau0 <- as.numeric(candidates$rhs_alpha_tau0)
if (anyDuplicated(candidates$candidate_id) || anyDuplicated(candidates$priority) ||
    any(!is.finite(candidates$rhs_tau0) | candidates$rhs_tau0 <= 0) ||
    any(!is.finite(candidates$rhs_alpha_tau0) | candidates$rhs_alpha_tau0 <= 0)) {
  stop("P95 repair candidate identifiers, priorities, or RHS scales are invalid.", call. = FALSE)
}
candidates <- candidates[order(candidates$priority), , drop = FALSE]

base_cfg <- app_read_yaml(base_config_path)
base_grid <- app_read_csv(resolve_repo(base_cfg$paths$model_grid, TRUE))
if (sum(base_grid$model_family == "qdesn_glofas_discrepancy") != 1L ||
    sum(base_grid$model_family == "raw_glofas") != 1L) {
  stop("The p95 base model grid must contain one Q-DESN and one raw GloFAS row.", call. = FALSE)
}
quantile_grid <- data.frame(
  quantile_id = "p95", quantile_level = 0.95, role = "upper_tail_repair",
  enabled = TRUE, stringsAsFactors = FALSE
)
quantile_grid_path <- file.path(output_root, "quantile_grid_p95.csv")
app_write_csv(quantile_grid, quantile_grid_path)

runtime_rows <- list()
for (i in seq_len(nrow(candidates))) {
  candidate <- candidates[i, , drop = FALSE]
  candidate_id <- candidate$candidate_id[[1L]]
  candidate_root <- file.path(output_root, "candidates", candidate_id)
  app_ensure_dir(candidate_root)
  cfg <- base_cfg
  cfg$application_name <- paste0("glofas_p95_readout_repair_", candidate_id)
  cfg$description <- paste("Observed-history p95 readout repair:", candidate$rationale[[1L]])
  cfg$paths$quantile_grid <- quantile_grid_path
  cfg$paths$model_grid <- file.path(candidate_root, "model_grid_p95.csv")
  cfg$paths$runs <- file.path(output_root, "runs")
  cfg$paths$logs <- file.path(output_root, "logs")
  cfg$paths$generated_outputs <- file.path(output_root, "generated")
  cfg$paths$cache <- file.path(dirname(base_config_path), "..", "..", "..", "common_cache")
  cfg$feature_contract$readout$include_input_block <- TRUE
  if (isTRUE(candidate$include_direct_covariates[[1L]])) {
    cfg$feature_contract$readout$input_block$covariates <- list(
      ppt = list(range = c(0L, 180L)),
      soil = list(range = c(0L, 180L))
    )
  } else {
    cfg$feature_contract$readout$input_block$covariates <- list()
  }
  cfg$inference$vb_ld$rhs_tau0 <- candidate$rhs_tau0[[1L]]
  cfg$inference$vb_ld$rhs_alpha_tau0 <- candidate$rhs_alpha_tau0[[1L]]
  cfg$inference$vb_ld$warm_start$enabled <- FALSE
  cfg$inference$mcmc$rhs_tau0 <- candidate$rhs_tau0[[1L]]
  cfg$inference$mcmc$rhs_alpha_tau0 <- candidate$rhs_alpha_tau0[[1L]]
  cfg$execution$final_launch$enabled <- TRUE
  cfg$execution$final_launch$note <- paste(
    "Explicit p95-only observed-history readout repair", candidate_id,
    "; no forecast-window selection and no automatic full7 launch"
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

  grid <- base_grid
  qrow <- grid$model_family == "qdesn_glofas_discrepancy"
  rrow <- grid$model_family == "raw_glofas"
  fit_id <- paste0("qdesn_p95_readout_repair_", candidate_id)
  grid$fit_id[qrow] <- fit_id
  grid$model_id[qrow] <- fit_id
  grid$fit_id[rrow] <- paste0("raw_glofas_p95_readout_repair_", candidate_id)
  grid$model_id[rrow] <- grid$fit_id[rrow]
  grid$notes[qrow] <- candidate$rationale[[1L]]
  grid$notes[rrow] <- paste("Raw GloFAS p95 comparator for", candidate_id)
  grid$config_hash <- "RUNTIME_CONFIG_HASH_RECORDED_IN_MANIFEST"
  app_write_csv(grid, cfg$paths$model_grid)
  config_path <- file.path(candidate_root, "config_p95.yaml")
  app_write_yaml(cfg, config_path)
  run_id <- paste0("glofas_fit_recovery_p95_readout_repair_20260809_", candidate_id)
  runtime_rows[[length(runtime_rows) + 1L]] <- data.frame(
    candidate_id = candidate_id,
    priority = candidate$priority[[1L]],
    role = candidate$role[[1L]],
    rationale = candidate$rationale[[1L]],
    include_direct_covariates = candidate$include_direct_covariates[[1L]],
    rhs_tau0 = candidate$rhs_tau0[[1L]],
    rhs_alpha_tau0 = candidate$rhs_alpha_tau0[[1L]],
    config_path = normalizePath(config_path, mustWork = TRUE),
    config_sha256 = app_sha256_file(config_path),
    model_grid_path = normalizePath(cfg$paths$model_grid, mustWork = TRUE),
    model_grid_sha256 = app_sha256_file(cfg$paths$model_grid),
    run_id = run_id,
    run_dir = file.path(output_root, "runs", run_id),
    log_path = file.path(output_root, "logs", paste0(candidate_id, ".log")),
    source_kind = "new_cold_start_tail_repair_fit",
    status = "prepared",
    stringsAsFactors = FALSE
  )
}
runtime <- app_bind_rows_fill(runtime_rows)
app_write_csv(runtime, file.path(output_root, "runtime_manifest.csv"))
provenance <- data.frame(
  field = c(
    "prepared_at", "repo_head", "prepare_script_sha256", "candidate_manifest_path",
    "candidate_manifest_sha256", "base_config_path", "base_config_sha256",
    "selection_target", "forecast_window_used_for_selection", "automatic_full7"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)[[1L]],
    app_sha256_file(app_path("application/scripts/glofas_fit_recovery_p95_readout_repair_prepare.R")),
    candidate_path, app_sha256_file(candidate_path), base_config_path,
    app_sha256_file(base_config_path),
    "observed_history_p95_check_loss_with_tail_and_discrepancy_support_gates",
    "false", "false"
  ),
  stringsAsFactors = FALSE
)
app_write_csv(provenance, file.path(output_root, "provenance.csv"))
writeLines(c(
  "P95 readout-repair batch prepared.",
  "The batch contains three cold-start, p95-only candidates.",
  "Precipitation and soil remain reservoir inputs in every candidate.",
  "Candidates marked without direct covariates remove them only from the readout skip block.",
  "Selection is restricted to observed-history p95 scores and predeclared tail/support gates.",
  "No full-seven launch, promotion, or article update is automatic."
), file.path(output_root, "README.txt"))
cat(normalizePath(file.path(output_root, "runtime_manifest.csv"), mustWork = TRUE), "\n")
