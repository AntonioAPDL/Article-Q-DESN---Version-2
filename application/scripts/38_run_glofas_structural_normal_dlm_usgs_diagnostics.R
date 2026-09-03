#!/usr/bin/env Rscript

repo_root <- app_script_repo_root <- NULL
args0 <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args0, value = TRUE)
if (length(file_arg)) {
  script_file <- normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE)
  repo_root <- normalizePath(file.path(dirname(script_file), "..", ".."), mustWork = TRUE)
} else {
  repo_root <- normalizePath(getwd(), mustWork = TRUE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_application_panel.R"))
source(app_path("application/R/glofas_structural_normal_dlm.R"))

args <- app_parse_args(list(
  base_config = "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml",
  run_label = paste0("glofas_structural_normal_dlm_usgs_", format(Sys.time(), "%Y%m%d_%H%M%S")),
  modes = "none,transfer_only,readout_only,transfer_plus_readout",
  backend = "cpp",
  last_n = "200"
))

base_config <- app_resolve_path(args$base_config, must_work = TRUE)
base_cfg <- app_read_config(base_config)
run_label <- as.character(args$run_label)[[1L]]
if (!nzchar(run_label) || grepl("[^A-Za-z0-9_.-]", run_label)) {
  stop("run_label must be path-safe.", call. = FALSE)
}
modes <- strsplit(gsub("[[:space:]]+", "", as.character(args$modes)[[1L]]), ",", fixed = TRUE)[[1L]]
modes <- modes[nzchar(modes)]
if (!length(modes)) stop("At least one mode is required.", call. = FALSE)
modes <- vapply(modes, app_glofas_structural_dlm_mode, character(1L))
backend <- app_glofas_structural_dlm_backend(args$backend)
last_n <- suppressWarnings(as.integer(args$last_n))
if (!is.finite(last_n) || last_n < 1L) last_n <- 200L

root <- app_path("local_trackers", "runtime_configs", run_label)
dirs <- file.path(root, c("configs", "logs", "tables", "figures", "components", "objects"))
invisible(lapply(dirs, app_ensure_dir))

app_write_yaml(
  list(
    run_label = run_label,
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    repo_root = app_repo_root(),
    git_head = app_git_sha(short = FALSE),
    base_config = base_config,
    base_config_sha256 = app_sha256_file(base_config),
    input_manifest = app_config_path(base_cfg, "input_manifest"),
    input_manifest_sha256 = app_sha256_file(app_config_path(base_cfg, "input_manifest")),
    cutoff_path = app_config_path(base_cfg, "cutoffs"),
    cutoff_sha256 = app_sha256_file(app_config_path(base_cfg, "cutoffs")),
    stage = "glofas_structural_normal_dlm_usgs_diagnostics",
    likelihood = "normal",
    modes = as.list(modes),
    backend = backend,
    last_n = last_n,
    feature_intent = list(
      role = "screening_feature_generator",
      qdesn_launch = "not_launched",
      leakage_policy = "residual_lag0_forbidden; smoothed_components_diagnostics_only",
      state_timings = "one_step_forecast, filtered, smoothed"
    )
  ),
  file.path(root, "configs", "run_manifest.yaml")
)
app_write_git_state(file.path(root, "configs", "git_state.txt"))
app_write_session_info(file.path(root, "configs", "session_info.txt"))

panel_bundle <- app_glofas_structural_dlm_prepare_usgs_panel(base_cfg)
score_rows <- list()
figure_rows <- list()

for (mode in modes) {
  started <- Sys.time()
  status <- "completed"
  error_message <- ""
  fit <- NULL
  tryCatch({
    fit <- app_glofas_structural_dlm_fit_from_glofas_config(
      base_cfg = base_cfg,
      mode = mode,
      backend = backend,
      panel_bundle = panel_bundle
    )
    comp_filtered <- app_glofas_structural_dlm_components(fit, timing = "filtered")
    comp_one_step <- app_glofas_structural_dlm_components(fit, timing = "one_step_forecast")
    comp_smoothed <- app_glofas_structural_dlm_components(fit, timing = "smoothed")
    app_write_csv(comp_filtered, file.path(root, "components", sprintf("%s_components_filtered.csv", mode)))
    app_write_csv(comp_one_step, file.path(root, "components", sprintf("%s_components_one_step.csv", mode)))
    app_write_csv(comp_smoothed, file.path(root, "components", sprintf("%s_components_smoothed.csv", mode)))

    fit_pdf <- file.path(root, "figures", sprintf("%s_full_and_last%d_fit_filtered.pdf", mode, last_n))
    one_step_pdf <- file.path(root, "figures", sprintf("%s_full_and_last%d_fit_one_step.pdf", mode, last_n))
    smoothed_pdf <- file.path(root, "figures", sprintf("%s_full_and_last%d_fit_smoothed.pdf", mode, last_n))
    comp_pdf <- file.path(root, "figures", sprintf("%s_last%d_components_and_residuals_filtered.pdf", mode, last_n))
    smoothed_comp_pdf <- file.path(root, "figures", sprintf("%s_last%d_components_and_residuals_smoothed.pdf", mode, last_n))
    app_glofas_structural_dlm_plot_fit(fit, fit_pdf, last_n = last_n, timing = "filtered")
    app_glofas_structural_dlm_plot_fit(fit, one_step_pdf, last_n = last_n, timing = "one_step_forecast")
    app_glofas_structural_dlm_plot_fit(fit, smoothed_pdf, last_n = last_n, timing = "smoothed")
    app_glofas_structural_dlm_plot_components(fit, comp_pdf, last_n = last_n, timing = "filtered")
    app_glofas_structural_dlm_plot_components(fit, smoothed_comp_pdf, last_n = last_n, timing = "smoothed")
    figure_rows[[length(figure_rows) + 1L]] <- data.frame(
      covariate_mode = mode,
      filtered_fit_pdf = fit_pdf,
      one_step_fit_pdf = one_step_pdf,
      smoothed_fit_pdf = smoothed_pdf,
      filtered_components_pdf = comp_pdf,
      smoothed_components_pdf = smoothed_comp_pdf,
      stringsAsFactors = FALSE
    )

    compact <- list(
      type = fit$type,
      version = fit$version,
      created_at = fit$created_at,
      cfg = fit$cfg,
      score = fit$score,
      state_labels = fit$sequences$state_map$labels,
      dates = fit$sequences$dates,
      one_step_mean = fit$filter$f,
      filtered_mean = fit$filter$fitted_mean,
      smoothed_mean = fit$smoother$smoothed_mean,
      one_step_residual = fit$filter$e,
      smoothed_residual = fit$sequences$y - fit$smoother$smoothed_mean,
      final_state_mean = fit$filter$m[, ncol(fit$filter$m)],
      final_state_cov = fit$filter$C_star[, , dim(fit$filter$C_star)[3L]],
      final_smoothed_state_mean = fit$smoother$s[, ncol(fit$smoother$s)],
      final_smoothed_state_cov = fit$smoother$D_star[, , dim(fit$smoother$D_star)[3L]],
      final_n = utils::tail(fit$filter$n, 1L),
      final_S = utils::tail(fit$filter$S, 1L),
      covariate_scale_params = fit$sequences$covariate_scale_params,
      filter_stabilization = fit$filter$stabilization,
      smoother_stabilization = fit$smoother$stabilization
    )
    saveRDS(compact, file.path(root, "objects", sprintf("%s_fit_compact.rds", mode)), version = 2L)
  }, error = function(e) {
    status <<- "failed"
    error_message <<- conditionMessage(e)
  })

  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  if (!is.null(fit)) {
    score <- fit$score
  } else {
    score <- data.frame(
      covariate_mode = mode,
      n_rows = NA_integer_,
      state_dim = NA_integer_,
      lambda = NA_real_,
      period = NA_real_,
      one_step_mean_crps = NA_real_,
      one_step_mae = NA_real_,
      one_step_rmse = NA_real_,
      one_step_mean_sd = NA_real_,
      filtered_mean_crps = NA_real_,
      filtered_mae = NA_real_,
      filtered_rmse = NA_real_,
      filtered_mean_sd = NA_real_,
      stringsAsFactors = FALSE
    )
  }
  score$status <- status
  score$error_message <- error_message
  score$runtime_seconds <- elapsed
  score_rows[[length(score_rows) + 1L]] <- score
}

scores <- app_bind_rows_fill(score_rows)
if (nrow(scores)) {
  scores <- scores[order(scores$status != "completed", scores$one_step_mean_crps), , drop = FALSE]
  scores$rank_one_step_crps <- seq_len(nrow(scores))
}
figures <- app_bind_rows_fill(figure_rows)
app_write_csv(scores, file.path(root, "tables", "structural_dlm_scores_latest.csv"))
app_write_csv(figures, file.path(root, "tables", "structural_dlm_figure_paths_latest.csv"))

cat("Structural Normal DLM diagnostics root:\n")
cat(root, "\n")
cat("\nScores:\n")
print(scores)
cat("\nFigure paths:\n")
print(figures)
