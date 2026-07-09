#!/usr/bin/env Rscript
# Purpose: regenerate all-cutoff GloFAS/NWS source-context and Q-DESN
# forecast-quantile figures from storage-light authoritative inputs.

repo_root <- {
  args_all <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args_all, value = TRUE)
  if (length(file_arg)) {
    normalizePath(file.path(dirname(sub("^--file=", "", file_arg[[1L]])), "..", ".."), mustWork = TRUE)
  } else {
    normalizePath(getwd(), mustWork = TRUE)
  }
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/cutoff_multivariate_figures.R"))

args <- app_parse_args(list(
  run_id = "glofas_multivariate_cutoff_figures_20260619_deep_identity_d4w100m300a050",
  source_root = "application/data_local/upstream_jerez/frozen_shared_inputs/exalm_t1_authoritative_20260505",
  prediction_run_id = "glofas_deep_identity_d4w100m300a050_full7_20260618_synthesis_final",
  window_before_days = "60",
  window_after_days = "30",
  transform = "log1p"
))

run_id <- as.character(args$run_id)
if (!nzchar(run_id)) {
  run_id <- sprintf("glofas_multivariate_cutoff_figures_%s", format(Sys.time(), "%Y%m%d_%H%M%S"))
}

output_root <- app_path("application", "outputs", "generated", run_id)
source_root <- app_resolve_path(as.character(args$source_root), must_work = TRUE)
prediction_run_id <- as.character(args$prediction_run_id %||% "")
before_days <- as.integer(args$window_before_days %||% 60L)
after_days <- as.integer(args$window_after_days %||% 30L)

result <- app_make_glofas_multivariate_cutoff_figures(
  source_root = source_root,
  output_root = output_root,
  prediction_run_id = prediction_run_id,
  before_days = before_days,
  after_days = after_days,
  transform = as.character(args$transform %||% "log1p")
)

cat("Output root:", result$output_root, "\n")
cat("Figure manifest:", file.path(result$output_root, "tables", "cutoff_figure_manifest.csv"), "\n")
cat("Validation table:", file.path(result$output_root, "tables", "cutoff_figure_validation.csv"), "\n")
cat("Figures:", nrow(result$manifest), "\n")
