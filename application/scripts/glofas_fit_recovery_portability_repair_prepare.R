#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_fit_recovery.R"))

args <- app_parse_args(list(
  source_root = "local_trackers/runtime_configs/glofas_fit_recovery_blocked_20260805_r1",
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_portability_repair_20260806",
  discrepancy_tau0 = "0.01,0.003,0.001"
))
resolve_repo <- function(path, must_work = FALSE) {
  normalizePath(if (grepl("^/", path)) path else app_path(path), mustWork = must_work)
}
source_root <- resolve_repo(args$source_root, TRUE)
output_root <- resolve_repo(args$output_root, FALSE)
tau0_values <- as.numeric(strsplit(as.character(args$discrepancy_tau0), ",", fixed = TRUE)[[1L]])
if (!length(tau0_values) || any(!is.finite(tau0_values) | tau0_values <= 0)) {
  stop("Discrepancy tau0 values must be positive finite numbers.", call. = FALSE)
}
for (dir in c("candidates", "runs", "logs", "generated", "scores", "status", "tables", "figures")) {
  app_ensure_dir(file.path(output_root, dir))
}
source_manifest <- app_read_csv(file.path(source_root, "runtime_manifest.csv"))
source_manifest <- source_manifest[source_manifest$base_candidate_id == "fr09_direct180_alpha010", , drop = FALSE]
if (nrow(source_manifest) != 2L || any(!file.exists(source_manifest$config_path))) {
  stop("Expected exactly two completed fr09 blocked-validation sources.", call. = FALSE)
}

rows <- list()
priority <- 0L
for (tau0 in tau0_values) {
  tau_slug <- sub("^0\\.", "", format(tau0, scientific = FALSE, trim = TRUE))
  repair_id <- paste0("fr09_dtau", tau_slug)
  for (i in seq_len(nrow(source_manifest))) {
    priority <- priority + 1L
    source_row <- source_manifest[i, , drop = FALSE]
    cutoff_id <- source_row$cutoff_id[[1L]]
    candidate_id <- paste(repair_id, cutoff_id, sep = "__")
    candidate_root <- file.path(output_root, "candidates", repair_id, cutoff_id)
    app_ensure_dir(candidate_root)
    grid <- app_read_csv(source_row$model_grid_path[[1L]])
    raw <- grid$model_family == "raw_glofas"
    qdesn <- grid$model_family == "qdesn_glofas_discrepancy"
    grid$fit_id[raw] <- paste0("raw_glofas_portability_repair_", repair_id, "_", cutoff_id, "_p50")
    grid$model_id[raw] <- grid$fit_id[raw]
    grid$fit_id[qdesn] <- paste0("qdesn_portability_repair_", repair_id, "_", cutoff_id, "_p50")
    grid$model_id[qdesn] <- grid$fit_id[qdesn]
    grid$notes <- paste("Cold-start discrepancy-shrinkage portability repair", repair_id, cutoff_id)
    grid_path <- file.path(candidate_root, "model_grid_p50.csv")
    app_write_csv(grid, grid_path)
    quantile_path <- file.path(candidate_root, "quantile_grid_p50.csv")
    app_write_csv(data.frame(quantile_id = "p50", quantile_level = 0.5, role = "median", enabled = TRUE), quantile_path)

    cfg <- app_read_config(source_row$config_path[[1L]])
    cfg$.__config_path__ <- NULL
    cfg$application_name <- paste0("glofas_portability_repair_", repair_id, "_", cutoff_id)
    cfg$description <- paste("Cold-start fr09 portability repair with discrepancy RHS tau0", tau0, "at", cutoff_id)
    cfg$paths$quantile_grid <- quantile_path
    cfg$paths$model_grid <- grid_path
    cfg$paths$runs <- file.path(output_root, "runs")
    cfg$paths$logs <- file.path(output_root, "logs")
    cfg$paths$generated_outputs <- file.path(output_root, "generated")
    cfg$inference$vb_ld$rhs_alpha_tau0 <- tau0
    cfg$inference$vb_ld$warm_start$enabled <- FALSE
    cfg$inference$mcmc$rhs_alpha_tau0 <- tau0
    config_path <- file.path(candidate_root, "config_p50.yaml")
    app_write_yaml(cfg, config_path)
    run_id <- paste0(basename(output_root), "_", repair_id, "_", cutoff_id)
    rows[[length(rows) + 1L]] <- data.frame(
      candidate_id = candidate_id,
      base_candidate_id = repair_id,
      cutoff_id = cutoff_id,
      origin_date = source_row$origin_date[[1L]],
      priority = priority,
      config_path = normalizePath(config_path, mustWork = TRUE),
      config_sha256 = app_sha256_file(config_path),
      model_grid_path = normalizePath(grid_path, mustWork = TRUE),
      model_grid_sha256 = app_sha256_file(grid_path),
      run_id = run_id,
      run_dir = file.path(output_root, "runs", run_id),
      log_path = file.path(output_root, "logs", paste0(candidate_id, ".log")),
      future_policy = "oracle_realized",
      source_provider = "realized_future_oracle",
      cold_start = TRUE,
      discrepancy_tau0 = tau0,
      status = "prepared_not_launched",
      stringsAsFactors = FALSE
    )
  }
}
manifest <- app_bind_rows_fill(rows)
app_write_csv(manifest, file.path(output_root, "runtime_manifest.csv"))
app_write_csv(data.frame(
  threshold = names(app_glofas_fit_recovery_portability_defaults()),
  value = unlist(app_glofas_fit_recovery_portability_defaults()),
  stringsAsFactors = FALSE
), file.path(output_root, "portability_thresholds.csv"))
writeLines(c(
  "Purpose: repair the fr09 discrepancy block after the December pseudo-cutoff failure.",
  "Scope: discrepancy RHS tau0 only; reference block, DESN, inputs, seeds, and protocol are unchanged.",
  "Evidence remains an oracle-covariate portability diagnostic, not operational forecast evidence."
), file.path(output_root, "README.txt"))
cat(file.path(output_root, "runtime_manifest.csv"), "\n")
