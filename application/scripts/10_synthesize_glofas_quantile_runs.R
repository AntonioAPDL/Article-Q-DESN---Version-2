#!/usr/bin/env Rscript
# Purpose: synthesize separately fitted GloFAS quantile runs into one
# article-facing quantile grid, score it, and create manuscript diagnostics.
# This script consumes completed run artifacts and does not fit models.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/forecast_spread_calibration.R"))
source(app_path("application/R/make_manuscript_outputs.R"))
source(app_path("application/R/discrepancy_identity_audit.R"))
source(app_path("application/R/post_fit_analysis.R"))

args <- app_parse_args(list(
  config = "local_trackers/runtime_configs/glofas_multiquantile_dec25_20260603/synthesis_config.yaml",
  source_manifest = "local_trackers/runtime_configs/glofas_multiquantile_dec25_20260603/synthesis_source_manifest.csv",
  run_id = NULL,
  allow_incomplete = FALSE
))

cfg <- app_read_config(app_path(args$config))
run_id <- args$run_id %||% sprintf("%s_%s", cfg$application_name %||% "glofas_multiquantile_synthesis", format(Sys.time(), "%Y%m%d_%H%M%S"))
run_dirs <- app_create_run_dirs(cfg, run_id = run_id)
app_stage_start("10_synthesize_glofas_quantile_runs", run_dirs)

source_manifest_path <- app_path(args$source_manifest)
source_manifest <- app_read_csv(source_manifest_path)
if ("enabled" %in% names(source_manifest)) {
  source_manifest <- source_manifest[app_as_bool_vec(source_manifest$enabled), , drop = FALSE]
}
required_manifest_cols <- c("quantile_id", "quantile_level", "run_id", "run_dir", "raw_fit_id", "qdesn_fit_id")
app_check_required_columns(source_manifest, required_manifest_cols, "synthesis source manifest")

allow_incomplete <- app_as_bool(args$allow_incomplete)
app_write_yaml(cfg, file.path(run_dirs$manifest, "run_config.yaml"))
app_write_json(cfg, file.path(run_dirs$manifest, "run_config.json"))
app_write_csv(source_manifest, file.path(run_dirs$manifest, "synthesis_source_manifest_used.csv"))
app_write_git_state(file.path(run_dirs$manifest, "git_state.txt"))
app_write_session_info(file.path(run_dirs$manifest, "session_info.txt"))

resolve_run_dir <- function(path) {
  if (grepl("^/", path)) path else app_path(path)
}

read_optional_csv <- function(path) {
  if (file.exists(path)) app_read_csv(path) else data.frame()
}

status_is_completed <- function(status, fit_ids) {
  rows <- status[status$fit_id %in% fit_ids, , drop = FALSE]
  nrow(rows) == length(fit_ids) && all(as.character(rows$status) == "completed")
}

prediction_rows <- list()
draw_rows <- list()
fit_status_rows <- list()
diag_rows <- list()
timing_rows <- list()
readiness_rows <- vector("list", nrow(source_manifest))

for (i in seq_len(nrow(source_manifest))) {
  row <- source_manifest[i, , drop = FALSE]
  src_run_dir <- resolve_run_dir(row$run_dir[[1L]])
  tables_dir <- file.path(src_run_dir, "tables")
  fit_status_path <- file.path(tables_dir, "fit_status.csv")
  pred_path <- file.path(tables_dir, "prediction_quantiles.csv")
  fit_ids <- c(row$raw_fit_id[[1L]], row$qdesn_fit_id[[1L]])
  ok <- file.exists(fit_status_path) && file.exists(pred_path)
  status <- if (file.exists(fit_status_path)) app_read_csv(fit_status_path) else data.frame()
  complete <- ok && status_is_completed(status, fit_ids)
  readiness_rows[[i]] <- data.frame(
    quantile_id = row$quantile_id[[1L]],
    quantile_level = as.numeric(row$quantile_level[[1L]]),
    run_id = row$run_id[[1L]],
    fit_status_exists = file.exists(fit_status_path),
    prediction_table_exists = file.exists(pred_path),
    required_fit_rows_completed = complete,
    stringsAsFactors = FALSE
  )
  if (!complete && !allow_incomplete) {
    stop(sprintf("Source run for quantile '%s' is incomplete or missing required artifacts: %s", row$quantile_id[[1L]], src_run_dir), call. = FALSE)
  }
  if (!ok) next

  pred <- app_read_csv(pred_path)
  app_validate_prediction_table_contract(
    pred,
    final_launch = isTRUE(cfg$execution$final_launch$enabled %||% FALSE)
  )
  pred$source_run_id <- row$run_id[[1L]]
  pred$source_quantile_id <- row$quantile_id[[1L]]
  prediction_rows[[length(prediction_rows) + 1L]] <- pred

  draws <- read_optional_csv(file.path(tables_dir, "posterior_draw_predictions.csv"))
  if (nrow(draws)) {
    draws$source_run_id <- row$run_id[[1L]]
    draws$source_quantile_id <- row$quantile_id[[1L]]
    draw_rows[[length(draw_rows) + 1L]] <- draws
  }
  status$source_run_id <- row$run_id[[1L]]
  fit_status_rows[[length(fit_status_rows) + 1L]] <- status

  diag <- read_optional_csv(file.path(tables_dir, "qdesn_discrepancy_fit_diagnostics.csv"))
  if (nrow(diag)) {
    diag$source_run_id <- row$run_id[[1L]]
    diag_rows[[length(diag_rows) + 1L]] <- diag
  }
  timing <- read_optional_csv(file.path(tables_dir, "qdesn_discrepancy_vb_iteration_timing.csv"))
  if (nrow(timing)) {
    timing$source_run_id <- row$run_id[[1L]]
    timing_rows[[length(timing_rows) + 1L]] <- timing
  }
}

readiness <- do.call(rbind, readiness_rows)
app_write_csv(readiness, file.path(run_dirs$tables, "synthesis_source_readiness.csv"))

predictions <- app_bind_rows_fill(prediction_rows)
if (!nrow(predictions)) stop("No prediction rows were available for synthesis.", call. = FALSE)
predictions$origin_date <- as.Date(predictions$origin_date)
predictions$target_date <- as.Date(predictions$target_date)
predictions$horizon <- as.integer(predictions$horizon)
predictions$quantile_level <- as.numeric(predictions$quantile_level)
predictions$qhat <- as.numeric(predictions$qhat)
predictions$y_reference <- as.numeric(predictions$y_reference)

duplicate_key <- duplicated(predictions[, c("model_id", "origin_date", "target_date", "horizon", "quantile_level"), drop = FALSE])
if (any(duplicate_key)) {
  dup <- predictions[duplicate_key, c("model_id", "origin_date", "target_date", "horizon", "quantile_level"), drop = FALSE]
  app_write_csv(dup, file.path(run_dirs$logs, "duplicate_prediction_keys.csv"))
  stop("Synthesis prediction table has duplicate model/origin/target/horizon/quantile keys.", call. = FALSE)
}

pred_mono <- app_synthesize_quantile_grid(predictions)
spread_calibration <- app_spread_calibration_config(cfg)
spread_calibration_result <- app_apply_spread_calibration_to_predictions(pred_mono, spread_calibration)
pred_mono_uncalibrated <- pred_mono
pred_mono <- spread_calibration_result$predictions
spread_calibration_manifest <- spread_calibration_result$manifest
cross_before <- app_quantile_crossing_diagnostics(pred_mono, "qhat", "before_isotonic")
cross_after <- app_quantile_crossing_diagnostics(pred_mono, "qhat_monotone", "after_isotonic")
cross_diag <- rbind(cross_before, cross_after)
cross_summary <- app_quantile_crossing_summary(cross_diag)

score_q <- app_score_quantile_predictions_dual(pred_mono, cfg)
score_i <- app_score_intervals(score_q, cfg)
score_c <- app_score_crps_grid(score_q)
summary <- app_score_summary(score_q, score_i, score_c)
metrics <- app_post_fit_metrics(predictions, cfg)

app_write_csv(predictions, file.path(run_dirs$tables, "prediction_quantiles_raw_combined.csv"))
if (isTRUE(spread_calibration_manifest$enabled[[1L]])) {
  app_write_csv(pred_mono_uncalibrated, file.path(run_dirs$tables, "prediction_quantiles_synthesized_uncalibrated.csv"))
}
app_write_csv(pred_mono, file.path(run_dirs$tables, "prediction_quantiles.csv"))
app_write_csv(pred_mono, file.path(run_dirs$tables, "prediction_quantiles_synthesized.csv"))
app_write_csv(spread_calibration_manifest, file.path(run_dirs$tables, "spread_calibration_manifest.csv"))
app_write_csv(score_q, file.path(run_dirs$tables, "score_by_quantile.csv"))
app_write_csv(score_i, file.path(run_dirs$tables, "score_by_interval.csv"))
app_write_csv(score_c, file.path(run_dirs$tables, "score_by_crps.csv"))
app_write_csv(summary, file.path(run_dirs$tables, "score_summary.csv"))
app_write_csv(cross_diag, file.path(run_dirs$tables, "quantile_synthesis_diagnostics.csv"))
app_write_csv(cross_summary, file.path(run_dirs$tables, "quantile_synthesis_diagnostic_summary.csv"))
app_write_csv(metrics$by_model, file.path(run_dirs$tables, "post_fit_metrics_by_model.csv"))
app_write_csv(metrics$by_horizon, file.path(run_dirs$tables, "post_fit_metrics_by_horizon.csv"))
if (length(fit_status_rows)) app_write_csv(app_bind_rows_fill(fit_status_rows), file.path(run_dirs$tables, "fit_status.csv"))
if (length(diag_rows)) app_write_csv(app_bind_rows_fill(diag_rows), file.path(run_dirs$tables, "qdesn_discrepancy_fit_diagnostics.csv"))
if (length(timing_rows)) app_write_csv(app_bind_rows_fill(timing_rows), file.path(run_dirs$tables, "qdesn_discrepancy_vb_iteration_timing.csv"))

draws <- app_bind_rows_fill(draw_rows)
if (nrow(draws)) {
  app_write_csv(draws, file.path(run_dirs$tables, "posterior_draw_predictions.csv"))
}

out_dir <- file.path(app_config_path(cfg, "generated_outputs"), basename(run_dirs$run_dir))
app_ensure_dir(out_dir)
score_tex <- file.path(out_dir, "glofas_application_score_summary.tex")
app_make_score_table_tex(summary, score_tex)
fig_dir <- file.path(out_dir, "figures")
identity_figures <- app_write_discrepancy_identity_audit(pred_mono, draws, run_dirs$tables, fig_dir)
figures <- c(app_make_model_diagnostic_figures(pred_mono, draws, fig_dir), identity_figures)
outputs <- c(score_summary_table = score_tex, figures)
prov <- app_write_output_provenance(
  outputs = outputs,
  run_dirs = run_dirs,
  cfg = cfg,
  path = file.path(run_dirs$tables, "manuscript_output_provenance.csv")
)
app_write_csv(prov, file.path(out_dir, "manuscript_output_provenance.csv"))

readiness_report <- data.frame(
  category = c("sources", "sources", "predictions", "synthesis", "metrics", "figures"),
  check = c(
    "all_required_source_runs_complete",
    "all_target_quantiles_available",
    "duplicate_prediction_keys_absent",
    "post_synthesis_crossings_absent",
    "score_summary_exists",
    "manuscript_figures_exist"
  ),
  passed = c(
    all(readiness$required_fit_rows_completed),
    all(sort(unique(as.numeric(source_manifest$quantile_level))) %in% sort(unique(predictions$quantile_level))),
    !any(duplicate_key),
    sum(cross_after$n_crossing_pairs, na.rm = TRUE) == 0,
    file.exists(file.path(run_dirs$tables, "score_summary.csv")),
    all(file.exists(unname(figures)))
  ),
  detail = c(
    paste(readiness$run_id, readiness$required_fit_rows_completed, sep = "=", collapse = "; "),
    paste(sort(unique(predictions$quantile_level)), collapse = ", "),
    "key: model_id, origin_date, target_date, horizon, quantile_level",
    sprintf("crossing_pairs_after=%d", sum(cross_after$n_crossing_pairs, na.rm = TRUE)),
    file.path(run_dirs$tables, "score_summary.csv"),
    paste(unname(figures), collapse = "; ")
  ),
  stringsAsFactors = FALSE
)
app_write_csv(readiness_report, file.path(run_dirs$tables, "launch_readiness_report.csv"))
summary_lines <- c(
  sprintf("run_id: %s", basename(run_dirs$run_dir)),
  sprintf("all_checks_passed: %s", all(readiness_report$passed)),
  sprintf("target_quantiles: %s", paste(sort(unique(predictions$quantile_level)), collapse = ", ")),
  sprintf("score_summary: %s", file.path(run_dirs$tables, "score_summary.csv")),
  sprintf("generated_outputs: %s", out_dir)
)
writeLines(summary_lines, file.path(run_dirs$tables, "launch_readiness_summary.txt"))

app_stage_done("10_synthesize_glofas_quantile_runs", run_dirs)
cat(run_dirs$run_dir, "\n")
