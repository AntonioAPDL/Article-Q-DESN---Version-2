#!/usr/bin/env Rscript
# Purpose: build and validate Q-DESN discrepancy designs without launching the
# sampler. This is a prelaunch gate for large specifications where input and
# design dimensions should be checked before MCMC is started.
# Inputs: application panel, model grid, cutoff file, and application config.
# Outputs: discrepancy-design and prediction-design summaries in run tables.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_qdesn_features.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/fit_qdesn_latent_path.R"))

args <- app_parse_args(list(
  config = "application/config/glofas_discrepancy_application.yaml",
  run_id = NULL,
  fit_id = ""
))

cfg <- app_read_config(app_path(args$config))
app_validate_application_model_contract(cfg)
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id %||% app_run_id(cfg))
app_stage_start("03_check_model_design", run_dirs)

panel_path <- file.path(app_config_path(cfg, "cache"), "application_panel.rds")
if (!file.exists(panel_path)) stop(sprintf("Missing application panel: %s", panel_path), call. = FALSE)
panel <- readRDS(panel_path)
model_grid <- app_validate_model_grid(app_config_path(cfg, "model_grid"), app_config_path(cfg, "schema"))
cutoffs <- app_validate_cutoffs(app_config_path(cfg, "cutoffs"))
if (!nrow(cutoffs)) stop("No enabled cutoff rows are available.", call. = FALSE)
cutoff_row <- cutoffs[1L, , drop = FALSE]
engine_report <- app_check_qdesn_engine_api(
  cfg,
  require_discrepancy = app_qdesn_engine_requires_discrepancy_export(cfg, model_grid),
  stop_on_failure = FALSE
)
support_report <- app_qdesn_discrepancy_inference_support(cfg, model_grid, engine_report)
if (nrow(support_report)) {
  app_write_csv(support_report, file.path(run_dirs$tables, "qdesn_inference_support_preflight.csv"))
}

qrows <- model_grid[model_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
if (nzchar(args$fit_id)) {
  qrows <- qrows[qrows$fit_id == args$fit_id, , drop = FALSE]
}
if (!nrow(qrows)) stop("No enabled qdesn_glofas_discrepancy rows matched the design check.", call. = FALSE)

design_rows <- list()
prediction_design_rows <- list()
contract <- app_prediction_contract(cfg, model_family = "qdesn_glofas_discrepancy")
include_ensemble_training <- identical(contract$prediction_unit, "posterior_draw") &&
  identical(contract$q_g_source, "posterior_model_quantile")

for (i in seq_len(nrow(qrows))) {
  row <- qrows[i, , drop = FALSE]
  if (app_is_latent_path_contract(cfg, row)) {
    design <- app_make_glofas_latent_path_design(
      panel = panel,
      cfg = cfg,
      model_row = row,
      cutoff_row = cutoff_row
    )
    design_rows[[i]] <- app_latent_path_design_summary(design)
    rm(design)
    invisible(gc())
    next
  }
  design <- app_make_glofas_discrepancy_data(
    panel = panel,
    cfg = cfg,
    cutoff_row = cutoff_row,
    model_row = row,
    include_ensemble_training = include_ensemble_training,
    feature_strategy = contract$discrepancy_feature_strategy
  )
  dsum <- app_discrepancy_design_summary(design)
  design_rows[[i]] <- dsum

  if (identical(contract$prediction_unit, "posterior_draw")) {
    pdesign <- app_make_glofas_prediction_design(
      design = design,
      panel = panel,
      cfg = cfg,
      model_row = row,
      contract = contract
    )
    prediction_design_rows[[i]] <- app_prediction_design_summary(pdesign)
  }
  rm(design)
  if (exists("pdesign", inherits = FALSE)) rm(pdesign)
  invisible(gc())
}

app_write_csv(app_bind_rows_fill(design_rows), file.path(run_dirs$tables, "qdesn_discrepancy_design_preflight.csv"))
if (length(prediction_design_rows)) {
  app_write_csv(
    app_bind_rows_fill(prediction_design_rows),
    file.path(run_dirs$tables, "qdesn_discrepancy_prediction_design_preflight.csv")
  )
}

app_stage_done("03_check_model_design", run_dirs)
cat(file.path(run_dirs$tables, "qdesn_discrepancy_design_preflight.csv"), "\n")
