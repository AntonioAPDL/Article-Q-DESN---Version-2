#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_part123_closeout.R"))

args <- app_parse_args(list(
  runtime_root = "local_trackers/runtime_configs/glofas_part23_final_dec25_2022_relaunch_jerez_20260905",
  reference_path = "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/data_local/frozen_inputs/authoritative_cutoffs/cutoff_date=2022-12-25/reference/reference_gauge.csv",
  output_root = ""
))
runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
output_root <- if (nzchar(args$output_root)) app_resolve_path(args$output_root, must_work = FALSE) else file.path(runtime_root, "closeout")
dir.create(output_root, recursive = TRUE, showWarnings = FALSE)
expected_dates <- seq.Date(as.Date("2022-12-26"), as.Date("2023-01-24"), by = "day")
truth <- app_glofas_closeout_truth(app_resolve_path(args$reference_path, must_work = TRUE), expected_dates)

files <- sort(list.files(file.path(runtime_root, "forecasts"), pattern = "^part3_forecast_.*_forecast\\.rds$", full.names = TRUE))
if (length(files) != 18L) stop(sprintf("Expected 18 Part 3 forecast objects; found %d.", length(files)), call. = FALSE)
normal <- list(); quantile <- list()
for (path in files) {
  model_id <- sub("_forecast\\.rds$", "", basename(path))
  forecast <- readRDS(path)
  if (!is.null(forecast$reference_draws)) {
    normal[[length(normal) + 1L]] <- app_glofas_closeout_score_normal(forecast, truth, model_id)
  } else {
    quantile[[length(quantile) + 1L]] <- app_glofas_closeout_score_quantile(forecast, truth, model_id)
  }
}
normal <- do.call(rbind, normal)
quantile <- do.call(rbind, quantile)
unavailable <- data.frame(
  part = c("part2", "part3", "part3"), target = c("discrepancy_and_corrected_usgs", "discrepancy", "glofas"),
  status = "not_scoreable", reason = c(
    "future retrospective GloFAS is unavailable after 2022-12-25",
    "future retrospective GloFAS is unavailable after 2022-12-25",
    "future retrospective GloFAS is unavailable after 2022-12-25"
  ), stringsAsFactors = FALSE
)
utils::write.csv(truth, file.path(output_root, "part3_future_usgs_truth_log1p.csv"), row.names = FALSE)
utils::write.csv(normal, file.path(output_root, "part3_normal_future_usgs_scores.csv"), row.names = FALSE)
utils::write.csv(quantile, file.path(output_root, "part3_quantile_future_usgs_scores.csv"), row.names = FALSE)
utils::write.csv(unavailable, file.path(output_root, "unavailable_future_score_contracts.csv"), row.names = FALSE)
cat(sprintf("PART3_CLOSEOUT_SCORED normal=%d quantile_rows=%d output=%s\n", nrow(normal), nrow(quantile), output_root))
