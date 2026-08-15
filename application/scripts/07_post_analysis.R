#!/usr/bin/env Rscript
# Purpose: generate post-fit Bayesian diagnostics, path summaries, figures, and
# forecast metrics from completed discrepancy Q-DESN fit artifacts.
# Inputs: completed run directory with fit objects, design objects,
# prediction_quantiles.csv, and posterior_draw_predictions.csv.
# Outputs: post_fit_* tables, post-analysis figures, and post_analysis_manifest.csv.
# Failure behavior: stops if required fit or posterior-draw artifacts are absent.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/fit_qdesn_discrepancy.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/fit_qdesn_latent_path.R"))
source(app_path("application/R/post_fit_analysis.R"))

args <- app_parse_args(list(config = "application/config/glofas_discrepancy_application.yaml", run_id = NULL))
cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id %||% app_run_id(cfg))
app_stage_start("07_post_analysis", run_dirs)

result <- tryCatch(
  app_run_post_fit_analysis(cfg, run_dirs),
  error = function(e) {
    msg <- conditionMessage(e)
    app_stage_done("07_post_analysis", run_dirs, status = "failed", message = msg)
    stop(msg, call. = FALSE)
  }
)

app_stage_done("07_post_analysis", run_dirs)
cat(file.path(run_dirs$tables, "post_analysis_manifest.csv"), "\n")
