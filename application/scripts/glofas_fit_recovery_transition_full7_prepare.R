#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_fit_recovery.R"))

args <- app_parse_args(list(
  transition_root = "local_trackers/runtime_configs/glofas_fit_recovery_transition_repair_20260807",
  source_config = "local_trackers/runtime_configs/glofas_fit_recovery_20260730/candidates/fr09_direct180_alpha010/config_p50.yaml",
  source_model_grid = "local_trackers/runtime_configs/glofas_fit_recovery_20260730/candidates/fr09_direct180_alpha010/model_grid_p50.csv",
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_transition_full7_20260808",
  candidate_id = "fr09_persistence_innovation",
  require_eligible = TRUE
))
resolve_repo <- function(path, must_work = FALSE) {
  normalizePath(if (grepl("^/", path)) path else app_path(path), mustWork = must_work)
}

transition_root <- resolve_repo(args$transition_root, TRUE)
source_config_path <- resolve_repo(args$source_config, TRUE)
source_model_grid_path <- resolve_repo(args$source_model_grid, TRUE)
output_root <- resolve_repo(args$output_root, FALSE)
candidate_id <- as.character(args$candidate_id)
batch_id <- basename(output_root)
if (!grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", batch_id)) {
  stop("The output-root basename is not a safe batch ID.", call. = FALSE)
}

ranking_path <- file.path(transition_root, "tables", "transition_validation_ranking.csv")
complete_path <- file.path(transition_root, "TRANSITION_FINALIZATION_COMPLETE.txt")
if (!file.exists(complete_path)) stop("Transition validation is not finalized.", call. = FALSE)
ranking <- app_read_csv(ranking_path)
selected <- ranking[ranking$candidate_id == candidate_id, , drop = FALSE]
if (nrow(selected) != 1L) stop("The requested transition candidate is not unique in the ranking.", call. = FALSE)
if (app_as_bool(args$require_eligible) && !app_as_bool(selected$eligible_for_full7_review[[1L]])) {
  stop("The requested transition candidate is not eligible for full-seven review.", call. = FALSE)
}
if (!identical(as.character(selected$discrepancy_transition_strategy[[1L]]), "persistence_anchored_innovation")) {
  stop("Only the validated persistence-anchored innovation strategy can advance.", call. = FALSE)
}

for (dir in c("candidates", "common_cache", "runs", "logs", "generated", "scores", "status", "tables", "figures", "cleanup")) {
  app_ensure_dir(file.path(output_root, dir))
}
source_cfg <- app_read_config(source_config_path)
source_cfg$.__config_path__ <- NULL
source_grid <- app_read_csv(source_model_grid_path)
raw_row <- source_grid$model_family == "raw_glofas"
qdesn_row <- source_grid$model_family == "qdesn_glofas_discrepancy"
if (sum(raw_row) != 1L || sum(qdesn_row) != 1L) {
  stop("The source model grid must contain exactly one raw and one Q-DESN model.", call. = FALSE)
}
if (!identical(basename(source_cfg$paths$cutoffs), "cutoffs_dec25_authoritative.csv")) {
  stop("The source config is not tied to the sealed December 25 cutoff registry.", call. = FALSE)
}

source_panel <- file.path(dirname(dirname(source_config_path)), "..", "common_cache", "application_panel.rds")
source_panel <- normalizePath(source_panel, mustWork = TRUE)
full7_panel <- file.path(output_root, "common_cache", "application_panel.rds")
if (!file.copy(source_panel, full7_panel, overwrite = FALSE, copy.mode = TRUE, copy.date = TRUE) && !file.exists(full7_panel)) {
  stop("Could not copy the audited application panel.", call. = FALSE)
}
if (!identical(app_sha256_file(source_panel), app_sha256_file(full7_panel))) {
  stop("The copied application panel does not match its source hash.", call. = FALSE)
}

levels <- c(0.05, 0.15, 0.35, 0.50, 0.65, 0.80, 0.95)
runtime_rows <- list()
source_rows <- list()
for (i in seq_along(levels)) {
  quantile_level <- levels[[i]]
  quantile_id <- sprintf("p%02d", as.integer(round(100 * quantile_level)))
  worker_id <- paste(candidate_id, quantile_id, sep = "__")
  candidate_root <- file.path(output_root, "candidates", candidate_id, quantile_id)
  app_ensure_dir(candidate_root)
  quantile_path <- file.path(candidate_root, paste0("quantile_grid_", quantile_id, ".csv"))
  app_write_csv(data.frame(
    quantile_id = quantile_id,
    quantile_level = quantile_level,
    role = if (quantile_level == 0.5) "median" else "distributional_quantile",
    enabled = TRUE,
    stringsAsFactors = FALSE
  ), quantile_path)

  grid <- source_grid
  raw_fit_id <- paste0("raw_glofas_transition_full7_", quantile_id)
  fit_id <- paste0("qdesn_transition_full7_", candidate_id, "_", quantile_id)
  grid$fit_id[raw_row] <- raw_fit_id
  grid$model_id[raw_row] <- raw_fit_id
  grid$fit_id[qdesn_row] <- fit_id
  grid$model_id[qdesn_row] <- fit_id
  grid$quantile_level <- quantile_level
  grid$notes <- paste("Cold-start transition-confirmation fit", quantile_id, "for", candidate_id)
  model_grid_path <- file.path(candidate_root, paste0("model_grid_", quantile_id, ".csv"))
  app_write_csv(grid, model_grid_path)

  cfg <- source_cfg
  cfg$application_name <- paste0("glofas_transition_full7_", candidate_id, "_", quantile_id)
  cfg$description <- paste(
    "Cold-start full-seven confirmation of persistence-anchored discrepancy innovations at quantile",
    format(quantile_level, nsmall = 2)
  )
  cfg$paths$quantile_grid <- quantile_path
  cfg$paths$model_grid <- model_grid_path
  cfg$paths$cache <- file.path(output_root, "common_cache")
  cfg$paths$runs <- file.path(output_root, "runs")
  cfg$paths$logs <- file.path(output_root, "logs")
  cfg$paths$generated_outputs <- file.path(output_root, "generated")
  cfg$prediction$discrepancy_transition_strategy <- "persistence_anchored_innovation"
  cfg$inference$vb_ld$rhs_alpha_tau0 <- as.numeric(selected$discrepancy_tau0[[1L]])
  cfg$inference$vb_ld$warm_start <- list(enabled = FALSE)
  cfg$inference$mcmc$rhs_alpha_tau0 <- as.numeric(selected$discrepancy_tau0[[1L]])
  cfg$post_analysis$run_after_outputs <- TRUE
  cfg$execution$artifacts <- list(
    retain_fit_object = TRUE,
    retain_design_object = TRUE,
    retain_prediction_design_object = TRUE,
    retain_reference_fit_object = TRUE
  )
  cfg$execution$final_launch$enabled <- TRUE
  cfg$execution$final_launch$note <- paste("Approved cold-start transition full-seven confirmation", worker_id)
  config_path <- file.path(candidate_root, paste0("config_", quantile_id, ".yaml"))
  app_write_yaml(cfg, config_path)

  run_id <- paste(batch_id, candidate_id, quantile_id, sep = "_")
  run_dir <- file.path(output_root, "runs", run_id)
  fit_object <- file.path(run_dir, "objects", paste0(fit_id, ".rds"))
  runtime_rows[[i]] <- data.frame(
    candidate_id = worker_id,
    base_candidate_id = candidate_id,
    priority = i,
    quantile_id = quantile_id,
    quantile_level = quantile_level,
    config_path = normalizePath(config_path, mustWork = TRUE),
    config_sha256 = app_sha256_file(config_path),
    model_grid_path = normalizePath(model_grid_path, mustWork = TRUE),
    model_grid_sha256 = app_sha256_file(model_grid_path),
    run_id = run_id,
    run_dir = run_dir,
    log_path = file.path(output_root, "logs", paste0(worker_id, ".log")),
    discrepancy_transition_strategy = "persistence_anchored_innovation",
    discrepancy_tau0 = as.numeric(selected$discrepancy_tau0[[1L]]),
    cutoff_id = "dec25_2022",
    cold_start = TRUE,
    retain_heavy = TRUE,
    status = "prepared_not_launched",
    stringsAsFactors = FALSE
  )
  source_rows[[i]] <- data.frame(
    candidate_id = candidate_id,
    role = "transition_full7_confirmation",
    quantile_id = quantile_id,
    quantile_level = quantile_level,
    source_kind = "new_cold_start_transition_full7_fit",
    run_id = run_id,
    run_dir = run_dir,
    config_path = normalizePath(config_path, mustWork = TRUE),
    config_sha256 = app_sha256_file(config_path),
    model_grid_path = normalizePath(model_grid_path, mustWork = TRUE),
    model_grid_sha256 = app_sha256_file(model_grid_path),
    history_path = file.path(run_dir, "tables", "post_fit_quantile_history_summary.csv"),
    fit_object = fit_object,
    fit_object_sha256 = NA_character_,
    expected_n_theta = NA_integer_,
    status = "prepared",
    stringsAsFactors = FALSE
  )
}

runtime_manifest <- app_bind_rows_fill(runtime_rows)
source_manifest <- app_bind_rows_fill(source_rows)
app_write_csv(runtime_manifest, file.path(output_root, "runtime_manifest.csv"))
app_write_csv(source_manifest, file.path(output_root, "quantile_source_manifest_prepared.csv"))
app_write_csv(selected, file.path(output_root, "selected_transition_snapshot.csv"))
app_write_csv(data.frame(
  field = c(
    "prepared_at", "repo_head", "transition_ranking_sha256", "transition_completion_sha256",
    "source_config_sha256", "source_model_grid_sha256", "panel_sha256", "cutoff_id",
    "transition_strategy", "cold_start", "launch_status"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)[[1L]],
    app_sha256_file(ranking_path), app_sha256_file(complete_path), app_sha256_file(source_config_path),
    app_sha256_file(source_model_grid_path), app_sha256_file(full7_panel), "dec25_2022",
    "persistence_anchored_innovation", "true", "prepared_not_launched"
  ),
  stringsAsFactors = FALSE
), file.path(output_root, "provenance.csv"))
writeLines(c(
  "Purpose: cold-start seven-quantile confirmation of the transition mechanism selected by blocked pseudo-cutoff validation.",
  "The DESN, two-block design, seeds, priors, inference controls, and December 25 cutoff are inherited unchanged from fr09.",
  "The only model-contract change is persistence-anchored discrepancy-innovation prediction.",
  "All seven quantile models are fitted independently; monotonicity is imposed only in post-hoc synthesis.",
  "No article promotion or authoritative replacement is automatic. Human diagnostic and comparative review remains required."
), file.path(output_root, "README.txt"))
cat(file.path(output_root, "runtime_manifest.csv"), "\n")
