#!/usr/bin/env Rscript
# Purpose: score fitted quantile predictions under the shared forecast-origin
# protocol.
# Inputs: prediction_quantiles.csv from a run directory.
# Outputs: score_by_quantile.csv, score_by_interval.csv, score_by_crps.csv,
# and score_summary.csv.
# Failure behavior: stops if prediction_quantiles.csv is missing.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))

args <- app_parse_args(list(config = "application/config/glofas_discrepancy_application.yaml", run_id = NULL))
cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id %||% app_run_id(cfg))
app_stage_start("04_score_models", run_dirs)

pred_path <- file.path(run_dirs$tables, "prediction_quantiles.csv")
if (!file.exists(pred_path)) stop(sprintf("Missing prediction table: %s", pred_path), call. = FALSE)
pred <- app_read_csv(pred_path)
app_validate_prediction_table_contract(
  pred,
  final_launch = isTRUE(cfg$execution$final_launch$enabled %||% FALSE)
)
pred$origin_date <- as.Date(pred$origin_date)
pred$target_date <- as.Date(pred$target_date)
pred$horizon <- as.integer(pred$horizon)
pred$quantile_level <- as.numeric(pred$quantile_level)
pred$qhat <- as.numeric(pred$qhat)
pred$y_reference <- as.numeric(pred$y_reference)

pred_mono <- app_synthesize_quantile_grid(pred)
score_q <- app_score_quantile_predictions(pred_mono, cfg)
score_i <- app_score_intervals(score_q, cfg)
score_c <- app_score_crps_grid(score_q)
summary <- app_score_summary(score_q, score_i, score_c)

app_write_csv(score_q, file.path(run_dirs$tables, "score_by_quantile.csv"))
app_write_csv(score_i, file.path(run_dirs$tables, "score_by_interval.csv"))
app_write_csv(score_c, file.path(run_dirs$tables, "score_by_crps.csv"))
app_write_csv(summary, file.path(run_dirs$tables, "score_summary.csv"))
app_stage_done("04_score_models", run_dirs)
cat(file.path(run_dirs$tables, "score_summary.csv"), "\n")
