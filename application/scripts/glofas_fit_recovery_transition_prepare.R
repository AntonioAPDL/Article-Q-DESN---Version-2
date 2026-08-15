#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  source_root = "local_trackers/runtime_configs/glofas_fit_recovery_transition_base_20260807",
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_transition_repair_20260807",
  base_candidate_id = "fr09_direct180_alpha010",
  strategies = "recursive_level,persistence_anchored_innovation",
  discrepancy_tau0 = 0.001
))
resolve_repo <- function(path, must_work = FALSE) {
  normalizePath(if (grepl("^/", path)) path else app_path(path), mustWork = must_work)
}
source_root <- resolve_repo(args$source_root, TRUE)
output_root <- resolve_repo(args$output_root, FALSE)
base_candidate_id <- as.character(args$base_candidate_id)
strategies <- trimws(strsplit(as.character(args$strategies), ",", fixed = TRUE)[[1L]])
allowed_strategies <- c("recursive_level", "persistence_anchored_innovation")
if (!length(strategies) || any(!strategies %in% allowed_strategies) || anyDuplicated(strategies)) {
  stop("Transition strategies must be unique supported values.", call. = FALSE)
}
discrepancy_tau0 <- as.numeric(args$discrepancy_tau0)
if (!is.finite(discrepancy_tau0) || discrepancy_tau0 <= 0) {
  stop("The discrepancy RHS tau0 must be positive and finite.", call. = FALSE)
}

for (dir in c("candidates", "runs", "logs", "generated", "scores", "status", "tables", "figures", "cleanup")) {
  app_ensure_dir(file.path(output_root, dir))
}
source_manifest <- app_read_csv(file.path(source_root, "runtime_manifest.csv"))
source_manifest <- source_manifest[source_manifest$base_candidate_id == base_candidate_id, , drop = FALSE]
cutoff_snapshot <- app_read_csv(file.path(source_root, "cutoff_registry_snapshot.csv"))
cutoff_snapshot <- cutoff_snapshot[app_as_bool_vec(cutoff_snapshot$enabled), , drop = FALSE]
if (nrow(source_manifest) != nrow(cutoff_snapshot) || nrow(source_manifest) < 3L) {
  stop("Transition repair requires one prepared source row per enabled validation cutoff.", call. = FALSE)
}
if (any(source_manifest$cutoff_id == "dec25_2022")) {
  stop("The sealed 2022-12-25 application cutoff cannot enter transition repair.", call. = FALSE)
}

strategy_id <- c(
  recursive_level = "fr09_recursive_level",
  persistence_anchored_innovation = "fr09_persistence_innovation"
)
rows <- list()
priority <- 0L
for (strategy in strategies) {
  candidate_id <- unname(strategy_id[[strategy]])
  for (i in seq_len(nrow(source_manifest))) {
    priority <- priority + 1L
    source_row <- source_manifest[i, , drop = FALSE]
    cutoff_id <- source_row$cutoff_id[[1L]]
    cutoff <- cutoff_snapshot[cutoff_snapshot$cutoff_id == cutoff_id, , drop = FALSE]
    if (nrow(cutoff) != 1L) stop(sprintf("Cutoff metadata is missing for %s.", cutoff_id), call. = FALSE)
    candidate_root <- file.path(output_root, "candidates", candidate_id, cutoff_id)
    app_ensure_dir(candidate_root)

    grid <- app_read_csv(source_row$model_grid_path[[1L]])
    raw <- grid$model_family == "raw_glofas"
    qdesn <- grid$model_family == "qdesn_glofas_discrepancy"
    if (sum(raw) != 1L || sum(qdesn) != 1L) stop("Transition repair requires a one-pair model grid.", call. = FALSE)
    grid$fit_id[raw] <- paste0("raw_glofas_transition_", candidate_id, "_", cutoff_id, "_p50")
    grid$model_id[raw] <- grid$fit_id[raw]
    grid$fit_id[qdesn] <- paste0("qdesn_transition_", candidate_id, "_", cutoff_id, "_p50")
    grid$model_id[qdesn] <- grid$fit_id[qdesn]
    grid$notes <- paste("Cold-start discrepancy-transition comparison", candidate_id, cutoff_id)
    grid_path <- file.path(candidate_root, "model_grid_p50.csv")
    app_write_csv(grid, grid_path)
    quantile_path <- file.path(candidate_root, "quantile_grid_p50.csv")
    app_write_csv(data.frame(
      quantile_id = "p50", quantile_level = 0.5, role = "median", enabled = TRUE
    ), quantile_path)

    cfg <- app_read_config(source_row$config_path[[1L]])
    cfg$.__config_path__ <- NULL
    cfg$application_name <- paste0("glofas_transition_repair_", candidate_id, "_", cutoff_id)
    cfg$description <- paste(
      "Cold-start p50 comparison of discrepancy transition", strategy,
      "at", cutoff_id, "using diagnostic oracle-realized ppt/soil covariates."
    )
    cfg$paths$quantile_grid <- quantile_path
    cfg$paths$model_grid <- grid_path
    cfg$paths$runs <- file.path(output_root, "runs")
    cfg$paths$logs <- file.path(output_root, "logs")
    cfg$paths$generated_outputs <- file.path(output_root, "generated")
    cfg$prediction$discrepancy_transition_strategy <- strategy
    cfg$inference$vb_ld$rhs_alpha_tau0 <- discrepancy_tau0
    cfg$inference$vb_ld$warm_start <- list(enabled = FALSE)
    cfg$inference$mcmc$rhs_alpha_tau0 <- discrepancy_tau0
    cfg$post_analysis$run_after_outputs <- TRUE
    cfg$execution$artifacts <- list(
      retain_fit_object = TRUE,
      retain_design_object = TRUE,
      retain_prediction_design_object = TRUE,
      retain_reference_fit_object = TRUE
    )
    cfg$execution$final_launch$enabled <- TRUE
    cfg$execution$final_launch$note <- paste(
      "Approved cold-start discrepancy-transition diagnostic for", candidate_id, cutoff_id
    )
    config_path <- file.path(candidate_root, "config_p50.yaml")
    app_write_yaml(cfg, config_path)
    run_id <- paste0(basename(output_root), "_", candidate_id, "_", cutoff_id)
    rows[[length(rows) + 1L]] <- data.frame(
      candidate_id = paste(candidate_id, cutoff_id, sep = "__"),
      base_candidate_id = candidate_id,
      source_candidate_id = base_candidate_id,
      cutoff_id = cutoff_id,
      origin_date = as.character(cutoff$origin_date[[1L]]),
      priority = priority,
      config_path = normalizePath(config_path, mustWork = TRUE),
      config_sha256 = app_sha256_file(config_path),
      model_grid_path = normalizePath(grid_path, mustWork = TRUE),
      model_grid_sha256 = app_sha256_file(grid_path),
      run_id = run_id,
      run_dir = file.path(output_root, "runs", run_id),
      log_path = file.path(output_root, "logs", paste0(candidate_id, "__", cutoff_id, ".log")),
      future_policy = "oracle_realized",
      source_provider = "realized_future_oracle",
      glofas_source_id = cutoff$glofas_source_id[[1L]],
      validation_role = cutoff$validation_role[[1L]],
      discrepancy_transition_strategy = strategy,
      discrepancy_tau0 = discrepancy_tau0,
      cold_start = TRUE,
      status = "prepared_not_launched",
      stringsAsFactors = FALSE
    )
  }
}
manifest <- app_bind_rows_fill(rows)
app_write_csv(manifest, file.path(output_root, "runtime_manifest.csv"))
app_write_csv(cutoff_snapshot, file.path(output_root, "cutoff_registry_snapshot.csv"))
app_write_csv(data.frame(
  strategy = allowed_strategies,
  statistical_target = c(
    "discrepancy level with recursive future discrepancy features",
    "discrepancy innovation around the preceding observed discrepancy with a last-observation future anchor"
  ),
  reference_block_changed = FALSE,
  post_hoc_clipping = FALSE,
  stringsAsFactors = FALSE
), file.path(output_root, "transition_contract.csv"))
app_write_csv(data.frame(
  field = c(
    "prepared_at", "repo_head", "source_manifest_sha256", "cutoff_registry_sha256",
    "discrepancy_tau0", "launch_status"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)[[1L]],
    app_sha256_file(file.path(source_root, "runtime_manifest.csv")),
    app_sha256_file(file.path(source_root, "cutoff_registry_snapshot.csv")),
    format(discrepancy_tau0, scientific = TRUE),
    "prepared_not_launched"
  ),
  stringsAsFactors = FALSE
), file.path(output_root, "provenance.csv"))
writeLines(c(
  "Purpose: compare the current recursive discrepancy-level model with a persistence-anchored innovation model.",
  "Scope: p50 only; the reference block, DESN, inputs, seeds, RHS priors, and inference controls are fixed.",
  "Primary evidence uses the three GloFAS v3.1 cutoffs; the v2.1 cutoff is a labeled source-vintage sensitivity check.",
  "All future ppt/soil values are oracle-realized diagnostics and do not constitute deployable forecast evidence.",
  "The 2022-12-25 application cutoff remains sealed and is not used for repair selection."
), file.path(output_root, "README.txt"))
cat(file.path(output_root, "runtime_manifest.csv"), "\n")
