#!/usr/bin/env Rscript
# Purpose: create manuscript-facing tables and provenance from scored outputs.
# Inputs: score_summary.csv from a completed run.
# Outputs: generated TeX table and manuscript_output_provenance.csv.
# Failure behavior: stops if score_summary.csv is missing.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/make_manuscript_outputs.R"))

args <- app_parse_args(list(config = "application/config/glofas_discrepancy_application.yaml", run_id = NULL))
cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id %||% app_run_id(cfg))
app_stage_start("05_make_outputs", run_dirs)

summary_path <- file.path(run_dirs$tables, "score_summary.csv")
if (!file.exists(summary_path)) stop(sprintf("Missing score summary: %s", summary_path), call. = FALSE)
summary <- app_read_csv(summary_path)

out_dir <- file.path(app_config_path(cfg, "generated_outputs"), basename(run_dirs$run_dir))
app_ensure_dir(out_dir)
score_tex <- file.path(out_dir, "glofas_application_score_summary.tex")
app_make_score_table_tex(summary, score_tex)
outputs <- c(score_summary_table = score_tex)

pred_path <- file.path(run_dirs$tables, "prediction_quantiles.csv")
if (file.exists(pred_path)) {
  predictions <- app_read_csv(pred_path)
  draw_path <- file.path(run_dirs$tables, "posterior_draw_predictions.csv")
  draws <- if (file.exists(draw_path)) app_read_csv(draw_path) else NULL
  fig_dir <- file.path(out_dir, "figures")
  model_figures <- app_make_model_diagnostic_figures(predictions, draws, fig_dir)
  outputs <- c(outputs, model_figures)
}
prov <- app_write_output_provenance(
  outputs = outputs,
  run_dirs = run_dirs,
  cfg = cfg,
  path = file.path(run_dirs$tables, "manuscript_output_provenance.csv")
)
app_write_csv(prov, file.path(out_dir, "manuscript_output_provenance.csv"))
app_stage_done("05_make_outputs", run_dirs)
cat(out_dir, "\n")
