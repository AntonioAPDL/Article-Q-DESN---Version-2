#!/usr/bin/env Rscript
# Purpose: screen D-ESN reservoir features without launching VB or MCMC.
# Inputs: application config, cached panel, model grid, cutoffs, and optional
# seed list. Outputs: reservoir screening CSV/JSON reports in a fresh run dir.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/launch_control.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_qdesn_features.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/fit_qdesn_latent_path.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/reservoir_screening.R"))

app_parse_seed_arg <- function(x, fallback) {
  if (is.null(x) || !nzchar(as.character(x)[[1L]])) return(as.integer(fallback))
  x <- gsub("[[:space:]]+", "", as.character(x)[[1L]])
  if (grepl("^[0-9]+:[0-9]+$", x)) {
    parts <- as.integer(strsplit(x, ":", fixed = FALSE)[[1L]])
    return(seq.int(parts[[1L]], parts[[2L]]))
  }
  seeds <- as.integer(strsplit(x, ",", fixed = TRUE)[[1L]])
  seeds[is.finite(seeds)]
}

args <- app_parse_args(list(
  config = "application/config/glofas_latent_path_al_vb_dec25_smoke.yaml",
  run_id = NULL,
  fit_id = "",
  seeds = "",
  diagnostic_target = "reservoir",
  cheap_validation = "false",
  baseline_score = "",
  save_state_summary = "false",
  max_corr_features_full = "",
  corr_block_size = "",
  spectral_radius_exact_max_n = "512",
  pruning_threshold = "",
  reject_on_cheap_validation = "false"
))

cfg <- app_read_config(app_path(args$config))
app_validate_application_model_contract(cfg)
run_id <- args$run_id %||% app_run_id(cfg)
app_validate_run_id_for_launch(cfg, run_id)
app_validate_run_directory_for_workflow(cfg, run_id = run_id, allow_existing_run_dir = FALSE)
run_dirs <- app_create_run_dirs(cfg, run_id = run_id)
app_stage_start("03_screen_reservoir_design", run_dirs)

tryCatch({
  panel_path <- file.path(app_config_path(cfg, "cache"), "application_panel.rds")
  if (!file.exists(panel_path)) {
    stop(sprintf("Missing application panel: %s. Run 01_build_panel.R first.", panel_path), call. = FALSE)
  }
  panel <- readRDS(panel_path)
  model_grid <- app_validate_model_grid(app_config_path(cfg, "model_grid"), app_config_path(cfg, "schema"))
  cutoffs <- app_validate_cutoffs(app_config_path(cfg, "cutoffs"))
  if (!nrow(cutoffs)) stop("No enabled cutoff rows are available.", call. = FALSE)
  cutoff_row <- cutoffs[1L, , drop = FALSE]

  qrows <- model_grid[model_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  if (nzchar(args$fit_id)) qrows <- qrows[qrows$fit_id == args$fit_id, , drop = FALSE]
  if (!nrow(qrows)) stop("No enabled Q-DESN model rows matched the reservoir screening request.", call. = FALSE)

  cfg_overrides <- list()
  if (nzchar(args$max_corr_features_full)) cfg_overrides$max_corr_features_full <- as.integer(args$max_corr_features_full)
  if (nzchar(args$corr_block_size)) cfg_overrides$corr_block_size <- as.integer(args$corr_block_size)
  if (nzchar(args$spectral_radius_exact_max_n)) {
    options(app_qdesn_spectral_radius_exact_max_n = as.integer(args$spectral_radius_exact_max_n))
  }
  if (nzchar(args$pruning_threshold)) cfg_overrides$pruning_threshold <- as.numeric(args$pruning_threshold)
  cfg_overrides$reject_on_cheap_validation <- app_as_bool(args$reject_on_cheap_validation)
  if (!app_as_bool(args$cheap_validation)) {
    cfg_overrides$validation_metric <- "none"
  }
  diag_cfg <- do.call(app_reservoir_diagnostic_config, cfg_overrides)
  matrix_role <- match.arg(
    as.character(args$diagnostic_target %||% "reservoir")[[1L]],
    c("layers", "reservoir", "readout", "both")
  )
  baseline_score <- suppressWarnings(as.numeric(args$baseline_score))
  if (!is.finite(baseline_score)) baseline_score <- NULL

  architecture_reports <- list()
  seed_rows <- list()
  state_rows <- list()
  layer_rows <- list()
  suggestion_rows <- list()

  for (i in seq_len(nrow(qrows))) {
    row <- qrows[i, , drop = FALSE]
    fallback_seed <- suppressWarnings(as.integer(row$reservoir_seed[[1L]] %||% cfg$reservoir$seed %||% 20260513L))
    seeds <- app_parse_seed_arg(args$seeds, fallback = fallback_seed)
    if (!length(seeds)) stop("Reservoir screening seed list is empty.", call. = FALSE)
    report <- app_screen_reservoir_architecture(
      cfg = cfg,
      panel = panel,
      model_row = row,
      cutoff_row = cutoff_row,
      seeds = seeds,
      config = diag_cfg,
      baseline_score = baseline_score,
      metadata = list(
        spec_id = row$fit_id[[1L]],
        fit_id = row$fit_id[[1L]],
        model_id = row$model_id[[1L]],
        matrix_role = matrix_role,
        config_path = args$config,
        run_id = run_id
      )
    )
    architecture_reports[[length(architecture_reports) + 1L]] <- report
    seed_rows[[length(seed_rows) + 1L]] <- app_bind_rows_fill(lapply(report$per_seed_reports, app_seed_report_row))
    state_rows[[length(state_rows) + 1L]] <- app_bind_rows_fill(lapply(report$per_seed_reports, app_state_report_rows))
    layer_rows[[length(layer_rows) + 1L]] <- app_bind_rows_fill(lapply(report$per_seed_reports, app_layer_report_rows))
    suggestion_rows[[length(suggestion_rows) + 1L]] <- app_bind_rows_fill(lapply(report$per_seed_reports, app_repair_suggestion_rows))
  }

  architecture_table <- app_bind_rows_fill(lapply(architecture_reports, app_architecture_summary_row))
  app_write_csv(architecture_table, file.path(run_dirs$tables, "reservoir_screening_architecture_summary.csv"))
  app_write_csv(app_bind_rows_fill(seed_rows), file.path(run_dirs$tables, "reservoir_screening_seed_reports.csv"))
  app_write_csv(app_bind_rows_fill(state_rows), file.path(run_dirs$tables, "reservoir_screening_state_diagnostics.csv"))
  app_write_csv(app_bind_rows_fill(layer_rows), file.path(run_dirs$tables, "reservoir_screening_layer_stability.csv"))
  app_write_csv(app_bind_rows_fill(suggestion_rows), file.path(run_dirs$tables, "reservoir_screening_repair_suggestions.csv"))

  manifest <- list(
    run_id = run_id,
    config = args$config,
    fit_id = args$fit_id,
    diagnostic_target = matrix_role,
    seeds = args$seeds,
    spectral_radius_exact_max_n = args$spectral_radius_exact_max_n,
    reports = lapply(architecture_reports, app_reservoir_report_to_list)
  )
  app_write_json(manifest, file.path(run_dirs$manifest, "reservoir_screening_report.json"))

  app_stage_done("03_screen_reservoir_design", run_dirs)
  cat(file.path(run_dirs$tables, "reservoir_screening_architecture_summary.csv"), "\n")
}, error = function(e) {
  app_stage_done("03_screen_reservoir_design", run_dirs, status = "failed", message = conditionMessage(e))
  stop(e)
})
