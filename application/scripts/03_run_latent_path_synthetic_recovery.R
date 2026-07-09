#!/usr/bin/env Rscript
# Purpose: run the synthetic recovery gate for the latent-path AL-VB engine.
# Inputs: application config with a synthetic_recovery block.
# Outputs: truth, recovery metrics, path summaries, draw checks, and fit object.
# Failure behavior: stops when required recovery tolerances are not satisfied.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_qdesn_features.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/fit_qdesn_discrepancy.R"))
source(app_path("application/R/fit_qdesn_latent_path.R"))
source(app_path("application/R/simulate_latent_path.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/latent_path_recovery.R"))

args <- app_parse_args(list(
  config = "application/config/glofas_latent_path_al_vb_synthetic_recovery.yaml",
  run_id = NULL
))

cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id %||% app_run_id(cfg))
app_stage_start("03_run_latent_path_synthetic_recovery", run_dirs)
tryCatch({
  if (isTRUE(cfg$execution$write_git_state %||% TRUE)) {
    app_write_git_state(file.path(run_dirs$manifest, "git_state.txt"))
  }
  if (isTRUE(cfg$execution$write_session_info %||% TRUE)) {
    app_write_session_info(file.path(run_dirs$manifest, "session_info.txt"))
  }
  app_write_json(cfg, file.path(run_dirs$manifest, "synthetic_recovery_config.json"))

  sim <- app_latent_path_recovery_simulate(cfg)
  design <- app_make_latent_path_recovery_design(sim, cfg)
  prior <- app_map_qdesn_prior(sim$model_row$coefficient_prior[[1L]])
  vb_args <- app_make_qdesn_discrepancy_vb_args(
    cfg,
    prior = prior,
    seed = as.integer(sim$seed),
    likelihood_family = "al"
  )
  vb_args$likelihood_family <- "al"
  fit <- app_fit_latent_path_al_vb_core(
    design = design,
    p0 = sim$p0,
    coefficient_prior = prior,
    vb_args = vb_args,
    seed = as.integer(sim$seed)
  )

  rec <- app_latent_path_recovery_config(cfg)
  metrics <- app_latent_path_recovery_metrics(
    fit = fit,
    design = design,
    tolerances = rec$tolerances %||% list()
  )
  path_summary <- app_latent_path_recovery_path_summary(fit, design)
  draw_table <- app_latent_path_recovery_draw_table(fit, design)
  draw_checks <- data.frame(
    n_draw_rows = nrow(draw_table),
    n_unique_draws = length(unique(draw_table$draw_index)),
    n_future_dates = nrow(unique(draw_table[, c("target_date", "horizon"), drop = FALSE])),
    max_identity_error = max(draw_table$identity_error),
    all_identity_errors_within_tolerance = all(draw_table$identity_error <= as.numeric((rec$tolerances %||% list())$max_draw_identity_error %||% 1.0e-8)),
    finite_draws = all(is.finite(as.matrix(draw_table[, c("q_y_draw", "q_g_draw", "d_g_draw", "latent_y_draw")]))),
    stringsAsFactors = FALSE
  )

  app_write_csv(sim$truth, file.path(run_dirs$tables, "synthetic_truth.csv"))
  app_write_csv(metrics, file.path(run_dirs$tables, "synthetic_recovery_metrics.csv"))
  app_write_csv(path_summary, file.path(run_dirs$tables, "synthetic_recovery_path.csv"))
  app_write_csv(draw_checks, file.path(run_dirs$tables, "synthetic_recovery_draw_checks.csv"))
  app_write_csv(utils::head(draw_table, 2000L), file.path(run_dirs$tables, "synthetic_recovery_draws_preview.csv"))
  saveRDS(fit, file.path(run_dirs$objects, "synthetic_latent_path_fit.rds"))
  saveRDS(design, file.path(run_dirs$objects, "synthetic_latent_path_design.rds"))
  saveRDS(sim, file.path(run_dirs$objects, "synthetic_latent_path_simulation.rds"))

  if (!isTRUE(metrics$passed[[1L]])) {
    msg <- sprintf(
      "Synthetic recovery gate failed: q_y_rmse=%.4f, q_g_rmse=%.4f, discrepancy_rmse=%.4f, y_future_rmse=%.4f, max_identity_error=%.3g",
      metrics$q_y_rmse[[1L]],
      metrics$q_g_rmse[[1L]],
      metrics$discrepancy_rmse[[1L]],
      metrics$y_future_rmse[[1L]],
      metrics$max_draw_identity_error[[1L]]
    )
    app_stage_done("03_run_latent_path_synthetic_recovery", run_dirs, status = "failed", message = msg)
    stop(msg, call. = FALSE)
  }
  app_stage_done(
    "03_run_latent_path_synthetic_recovery",
    run_dirs,
    message = sprintf("Synthetic recovery gate passed with %d VB iterations.", metrics$vb_iterations[[1L]])
  )
  cat(file.path(run_dirs$tables, "synthetic_recovery_metrics.csv"), "\n")
}, error = function(e) {
  msg <- conditionMessage(e)
  app_stage_done("03_run_latent_path_synthetic_recovery", run_dirs, status = "failed", message = msg)
  stop(msg, call. = FALSE)
})
