#!/usr/bin/env Rscript
# Purpose: create no-refit diagnostic figures for the GloFAS readout-refinement
# gate: VB traces, convergence summaries, and synthesized quantile paths.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/make_manuscript_outputs.R"))

args <- app_parse_args(list(
  config = "local_trackers/runtime_configs/glofas_multiquantile_dec25_20260603/synthesis_config.yaml",
  source_manifest = "local_trackers/runtime_configs/glofas_readout_refinement_gate_20260606/synthesis_source_manifest_gate.csv",
  run_id = "glofas_readout_refinement_gate_20260606_diagnostic_figures",
  focus_candidate = "reservoir_only_m360"
))

cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id)
app_stage_start("18_make_glofas_readout_gate_diagnostic_figures", run_dirs)
app_write_yaml(cfg, file.path(run_dirs$manifest, "run_config.yaml"))
app_write_json(cfg, file.path(run_dirs$manifest, "run_config.json"))
app_write_git_state(file.path(run_dirs$manifest, "git_state.txt"))
app_write_session_info(file.path(run_dirs$manifest, "session_info.txt"))

out_dir <- file.path(app_config_path(cfg, "generated_outputs"), basename(run_dirs$run_dir))
fig_dir <- file.path(out_dir, "figures")
app_ensure_dir(out_dir)
app_ensure_dir(fig_dir)

resolve_run_dir <- function(path) {
  if (grepl("^/", path)) path else app_path(path)
}

plot_pdf <- function(name, width = 9, height = 5, expr) {
  path <- file.path(fig_dir, name)
  grDevices::pdf(path, width = width, height = height)
  on.exit(grDevices::dev.off(), add = TRUE)
  force(expr)
  path
}

manifest <- app_read_csv(app_path(args$source_manifest))
if ("enabled" %in% names(manifest)) manifest <- manifest[app_as_bool_vec(manifest$enabled), , drop = FALSE]
required <- c("candidate_id", "quantile_id", "quantile_level", "run_id", "run_dir", "qdesn_fit_id")
app_check_required_columns(manifest, required, "readout gate source manifest")
manifest$quantile_level <- as.numeric(manifest$quantile_level)
manifest <- manifest[order(manifest$candidate_id, manifest$quantile_level), , drop = FALSE]

trace_rows <- list()
fit_summary_rows <- list()
prediction_rows <- list()
draw_summary_rows <- list()

for (i in seq_len(nrow(manifest))) {
  row <- manifest[i, , drop = FALSE]
  run_dir <- resolve_run_dir(row$run_dir[[1L]])
  fit_id <- row$qdesn_fit_id[[1L]]
  fit_path <- file.path(run_dir, "objects", paste0(fit_id, ".rds"))
  diag_path <- file.path(run_dir, "tables", "qdesn_discrepancy_fit_diagnostics.csv")
  pred_path <- file.path(run_dir, "tables", "prediction_quantiles.csv")
  draw_path <- file.path(run_dir, "tables", "qdesn_discrepancy_draw_checks.csv")
  if (!file.exists(fit_path)) stop(sprintf("Missing fit object: %s", fit_path), call. = FALSE)
  if (!file.exists(pred_path)) stop(sprintf("Missing prediction table: %s", pred_path), call. = FALSE)

  fit <- readRDS(fit_path)
  diag <- fit$vb_diagnostics %||% fit$diagnostics %||% list()
  elbo <- as.numeric(diag$elbo_trace %||% numeric())
  pchange <- as.numeric(diag$parameter_change_trace %||% diag$max_parameter_change_trace %||% numeric())
  rel_change <- as.numeric(diag$relative_change_trace %||% numeric())

  add_trace <- function(trace_name, values) {
    if (!length(values)) return(NULL)
    data.frame(
      candidate_id = row$candidate_id[[1L]],
      quantile_id = row$quantile_id[[1L]],
      quantile_level = row$quantile_level[[1L]],
      trace_name = trace_name,
      iteration = seq_along(values),
      value = as.numeric(values),
      stringsAsFactors = FALSE
    )
  }
  trace_rows[[length(trace_rows) + 1L]] <- add_trace("elbo", elbo)
  trace_rows[[length(trace_rows) + 1L]] <- add_trace("max_parameter_change", pchange)
  trace_rows[[length(trace_rows) + 1L]] <- add_trace("relative_change", rel_change)

  diag_table <- if (file.exists(diag_path)) app_read_csv(diag_path) else data.frame()
  d <- if (nrow(diag_table)) diag_table[1L, , drop = FALSE] else data.frame()
  fit_summary_rows[[length(fit_summary_rows) + 1L]] <- data.frame(
    candidate_id = row$candidate_id[[1L]],
    quantile_id = row$quantile_id[[1L]],
    quantile_level = row$quantile_level[[1L]],
    fit_id = fit_id,
    vb_converged = app_as_bool(d$vb_converged %||% diag$converged %||% FALSE),
    vb_iterations = as.integer(d$vb_iterations %||% diag$iterations %||% max(length(elbo), length(pchange), 0L)),
    vb_elbo_final = as.numeric(d$vb_elbo_final %||% diag$elbo_final %||% if (length(elbo)) tail(elbo, 1L) else NA_real_),
    vb_max_parameter_change = as.numeric(d$vb_max_parameter_change %||% diag$max_parameter_change %||% if (length(pchange)) tail(pchange, 1L) else NA_real_),
    sigma_Y_mean = as.numeric(d$sigma_Y_mean %||% NA_real_),
    sigma_G_mean = as.numeric(d$sigma_G_mean %||% NA_real_),
    beta_norm_mean = as.numeric(d$beta_norm_mean %||% NA_real_),
    alpha_norm_mean = as.numeric(d$alpha_norm_mean %||% NA_real_),
    fit_path = fit_path,
    stringsAsFactors = FALSE
  )

  pred <- app_read_csv(pred_path)
  pred$candidate_id <- row$candidate_id[[1L]]
  pred$source_run_id <- row$run_id[[1L]]
  pred$source_quantile_id <- row$quantile_id[[1L]]
  prediction_rows[[length(prediction_rows) + 1L]] <- pred

  if (file.exists(draw_path)) {
    dc <- app_read_csv(draw_path)
    if (nrow(dc)) {
      dc$candidate_id <- row$candidate_id[[1L]]
      dc$quantile_id <- row$quantile_id[[1L]]
      dc$quantile_level <- row$quantile_level[[1L]]
      draw_summary_rows[[length(draw_summary_rows) + 1L]] <- dc
    }
  }
}

trace_table <- app_bind_rows_fill(Filter(Negate(is.null), trace_rows))
fit_summary <- app_bind_rows_fill(fit_summary_rows)
predictions <- app_bind_rows_fill(prediction_rows)
draw_summary <- app_bind_rows_fill(draw_summary_rows)

app_write_csv(trace_table, file.path(run_dirs$tables, "gate_vb_trace_long.csv"))
app_write_csv(fit_summary, file.path(run_dirs$tables, "gate_vb_convergence_summary.csv"))
app_write_csv(draw_summary, file.path(run_dirs$tables, "gate_draw_check_summary.csv"))

qdesn <- predictions[predictions$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
raw <- predictions[predictions$model_family == "raw_glofas", , drop = FALSE]
qdesn$origin_date <- as.Date(qdesn$origin_date)
qdesn$target_date <- as.Date(qdesn$target_date)
qdesn$horizon <- as.integer(qdesn$horizon)
qdesn$quantile_level <- as.numeric(qdesn$quantile_level)
qdesn$qhat <- as.numeric(qdesn$qhat)
qdesn$y_reference <- as.numeric(qdesn$y_reference)
raw$origin_date <- as.Date(raw$origin_date)
raw$target_date <- as.Date(raw$target_date)
raw$horizon <- as.integer(raw$horizon)
raw$quantile_level <- as.numeric(raw$quantile_level)
raw$qhat <- as.numeric(raw$qhat)
raw$y_reference <- as.numeric(raw$y_reference)

synth_rows <- list()
score_rows <- list()
cross_rows <- list()
width_rows <- list()
cfg_gate <- list(scoring = list(intervals = list(list(lower = 0.05, upper = 0.95, nominal = 0.90))))
for (cand in sort(unique(qdesn$candidate_id))) {
  block <- qdesn[qdesn$candidate_id == cand, , drop = FALSE]
  block$model_id <- paste0("qdesn_", cand, "_gate")
  mono <- app_synthesize_quantile_grid(block)
  mono$candidate_id <- cand
  synth_rows[[cand]] <- mono
  scored <- app_score_quantile_predictions_dual(mono, cfg_gate)
  intervals <- app_score_intervals(scored, cfg_gate)
  crps <- app_score_crps_grid(scored)
  ss <- app_score_summary(scored, intervals, crps)
  ss$candidate_id <- cand
  score_rows[[cand]] <- ss
  cb <- app_quantile_crossing_diagnostics(mono, "qhat", "before")
  ca <- app_quantile_crossing_diagnostics(mono, "qhat_monotone", "after")
  cross <- app_quantile_crossing_summary(rbind(cb, ca))
  cross$candidate_id <- cand
  cross_rows[[cand]] <- cross
  keys <- unique(mono[, c("model_id", "origin_date", "target_date", "horizon"), drop = FALSE])
  w <- lapply(seq_len(nrow(keys)), function(j) {
    idx <- mono$model_id == keys$model_id[[j]] &
      mono$origin_date == keys$origin_date[[j]] &
      mono$target_date == keys$target_date[[j]] &
      mono$horizon == keys$horizon[[j]]
    b <- mono[idx, , drop = FALSE]
    data.frame(
      candidate_id = cand,
      origin_date = keys$origin_date[[j]],
      target_date = keys$target_date[[j]],
      horizon = keys$horizon[[j]],
      width_raw_90 = b$qhat[b$quantile_level == 0.95] - b$qhat[b$quantile_level == 0.05],
      width_monotone_90 = b$qhat_monotone[b$quantile_level == 0.95] - b$qhat_monotone[b$quantile_level == 0.05],
      y_reference = b$y_reference[[1L]],
      stringsAsFactors = FALSE
    )
  })
  width_rows[[cand]] <- do.call(rbind, w)
}
synth <- app_bind_rows_fill(synth_rows)
score_summary <- app_bind_rows_fill(score_rows)
cross_summary <- app_bind_rows_fill(cross_rows)
width_summary <- app_bind_rows_fill(width_rows)

raw_gate <- raw[raw$source_run_id %in% manifest$run_id[manifest$candidate_id == "current_m360_direct360"], , drop = FALSE]
raw_gate$model_id <- "raw_glofas_gate_baseline"
raw_mono <- app_synthesize_quantile_grid(raw_gate)
raw_mono$candidate_id <- "raw_glofas_baseline"

app_write_csv(synth, file.path(run_dirs$tables, "gate_candidate_predictions_synthesized.csv"))
app_write_csv(score_summary, file.path(run_dirs$tables, "gate_candidate_score_summary.csv"))
app_write_csv(cross_summary, file.path(run_dirs$tables, "gate_candidate_crossing_summary.csv"))
app_write_csv(width_summary, file.path(run_dirs$tables, "gate_candidate_width_by_horizon.csv"))

figures <- c()
if (!requireNamespace("ggplot2", quietly = TRUE)) stop("ggplot2 is required for gate diagnostic figures.", call. = FALSE)

trace_elbo <- trace_table[trace_table$trace_name == "elbo" & is.finite(trace_table$value), , drop = FALSE]
figures <- c(figures, elbo_traces = {
  p <- ggplot2::ggplot(trace_elbo, ggplot2::aes(iteration, value, color = quantile_id)) +
    ggplot2::geom_line(linewidth = 0.55) +
    ggplot2::facet_wrap(~ candidate_id, scales = "free_y", ncol = 2) +
    ggplot2::labs(x = "VB iteration", y = "ELBO", color = "Quantile", title = "Readout-gate ELBO traces") +
    ggplot2::theme_bw(base_size = 9) +
    ggplot2::theme(legend.position = "bottom")
  path <- file.path(fig_dir, "glofas_gate_vb_elbo_traces_all_candidates.pdf")
  ggplot2::ggsave(path, p, width = 10.5, height = 8.5)
  path
})

trace_param <- trace_table[trace_table$trace_name == "max_parameter_change" & is.finite(trace_table$value) & trace_table$value > 0, , drop = FALSE]
figures <- c(figures, parameter_change_traces = {
  p <- ggplot2::ggplot(trace_param, ggplot2::aes(iteration, value, color = quantile_id)) +
    ggplot2::geom_line(linewidth = 0.55) +
    ggplot2::geom_hline(yintercept = 1e-4, linetype = 2, color = "gray25") +
    ggplot2::scale_y_log10() +
    ggplot2::facet_wrap(~ candidate_id, scales = "free_y", ncol = 2) +
    ggplot2::labs(x = "VB iteration", y = "Maximum parameter change", color = "Quantile", title = "Readout-gate VB parameter-change traces") +
    ggplot2::theme_bw(base_size = 9) +
    ggplot2::theme(legend.position = "bottom")
  path <- file.path(fig_dir, "glofas_gate_vb_parameter_change_traces_all_candidates.pdf")
  ggplot2::ggsave(path, p, width = 10.5, height = 8.5)
  path
})

figures <- c(figures, convergence_summary = {
  p <- ggplot2::ggplot(fit_summary, ggplot2::aes(quantile_id, vb_max_parameter_change, fill = vb_converged)) +
    ggplot2::geom_col(width = 0.72) +
    ggplot2::geom_hline(yintercept = 1e-4, linetype = 2, color = "gray25") +
    ggplot2::scale_y_log10() +
    ggplot2::facet_wrap(~ candidate_id, ncol = 2) +
    ggplot2::labs(x = "Quantile", y = "Final max parameter change", fill = "Converged", title = "Readout-gate VB convergence summary") +
    ggplot2::theme_bw(base_size = 9) +
    ggplot2::theme(legend.position = "bottom")
  path <- file.path(fig_dir, "glofas_gate_vb_convergence_summary.pdf")
  ggplot2::ggsave(path, p, width = 10.5, height = 8.5)
  path
})

plot_synth <- synth
plot_synth$path_value_independent <- plot_synth$qhat
plot_synth$path_value_monotone <- plot_synth$qhat_monotone
obs <- plot_synth[!duplicated(plot_synth$target_date), c("target_date", "y_reference"), drop = FALSE]
figures <- c(figures, independent_paths = {
  p <- ggplot2::ggplot(plot_synth, ggplot2::aes(target_date, path_value_independent, color = factor(quantile_level))) +
    ggplot2::geom_line(linewidth = 0.65) +
    ggplot2::geom_line(data = obs, ggplot2::aes(target_date, y_reference), inherit.aes = FALSE, color = "black", linewidth = 0.75) +
    ggplot2::geom_point(data = obs, ggplot2::aes(target_date, y_reference), inherit.aes = FALSE, color = "black", size = 0.9) +
    ggplot2::facet_wrap(~ candidate_id, scales = "free_y", ncol = 2) +
    ggplot2::labs(x = "Target date", y = "Transformed streamflow", color = "Quantile", title = "Independent Q-DESN gate quantile paths") +
    ggplot2::theme_bw(base_size = 9) +
    ggplot2::theme(legend.position = "bottom")
  path <- file.path(fig_dir, "glofas_gate_independent_quantile_paths_all_candidates.pdf")
  ggplot2::ggsave(path, p, width = 11, height = 8.5)
  path
})

figures <- c(figures, monotone_paths = {
  p <- ggplot2::ggplot(plot_synth, ggplot2::aes(target_date, path_value_monotone, color = factor(quantile_level))) +
    ggplot2::geom_line(linewidth = 0.65) +
    ggplot2::geom_line(data = obs, ggplot2::aes(target_date, y_reference), inherit.aes = FALSE, color = "black", linewidth = 0.75) +
    ggplot2::geom_point(data = obs, ggplot2::aes(target_date, y_reference), inherit.aes = FALSE, color = "black", size = 0.9) +
    ggplot2::facet_wrap(~ candidate_id, scales = "free_y", ncol = 2) +
    ggplot2::labs(x = "Target date", y = "Transformed streamflow", color = "Quantile", title = "Post-hoc monotone Q-DESN gate quantile paths") +
    ggplot2::theme_bw(base_size = 9) +
    ggplot2::theme(legend.position = "bottom")
  path <- file.path(fig_dir, "glofas_gate_monotone_quantile_paths_all_candidates.pdf")
  ggplot2::ggsave(path, p, width = 11, height = 8.5)
  path
})

figures <- c(figures, width_paths = {
  p <- ggplot2::ggplot(width_summary, ggplot2::aes(horizon, width_monotone_90, color = candidate_id)) +
    ggplot2::geom_line(linewidth = 0.75) +
    ggplot2::labs(x = "Forecast horizon", y = "Post-hoc monotone 90% interval width", color = "Candidate", title = "Readout-gate 90% interval width by horizon") +
    ggplot2::theme_bw(base_size = 9) +
    ggplot2::theme(legend.position = "bottom")
  path <- file.path(fig_dir, "glofas_gate_monotone_interval_widths.pdf")
  ggplot2::ggsave(path, p, width = 9, height = 5.5)
  path
})

focus <- as.character(args$focus_candidate)
focus_q <- plot_synth[plot_synth$candidate_id == focus, , drop = FALSE]
focus_raw <- raw_mono
focus_raw$path_value_monotone <- focus_raw$qhat_monotone
figures <- c(figures, focus_reservoir_only = {
  focus_q$panel <- paste0("Q-DESN: ", focus)
  focus_raw$panel <- "Raw GloFAS baseline"
  focus_plot <- app_bind_rows_fill(list(
    data.frame(panel = focus_q$panel, target_date = focus_q$target_date, quantile_level = focus_q$quantile_level, q_plot = focus_q$qhat_monotone, y_reference = focus_q$y_reference),
    data.frame(panel = focus_raw$panel, target_date = focus_raw$target_date, quantile_level = focus_raw$quantile_level, q_plot = focus_raw$path_value_monotone, y_reference = focus_raw$y_reference)
  ))
  p <- ggplot2::ggplot(focus_plot, ggplot2::aes(target_date, q_plot, color = factor(quantile_level))) +
    ggplot2::geom_line(linewidth = 0.85) +
    ggplot2::geom_line(data = obs, ggplot2::aes(target_date, y_reference), inherit.aes = FALSE, color = "black", linewidth = 0.8) +
    ggplot2::geom_point(data = obs, ggplot2::aes(target_date, y_reference), inherit.aes = FALSE, color = "black", size = 1) +
    ggplot2::facet_wrap(~ panel, ncol = 1, scales = "free_y") +
    ggplot2::labs(x = "Target date", y = "Transformed streamflow", color = "Quantile", title = "Gate winner versus raw GloFAS around the cutoff") +
    ggplot2::theme_bw(base_size = 10) +
    ggplot2::theme(legend.position = "bottom")
  path <- file.path(fig_dir, paste0("glofas_gate_", focus, "_focus_vs_raw.pdf"))
  ggplot2::ggsave(path, p, width = 8.5, height = 6.8)
  path
})

prov <- app_write_output_provenance(
  outputs = figures,
  run_dirs = run_dirs,
  cfg = cfg,
  path = file.path(run_dirs$tables, "gate_diagnostic_figure_provenance.csv")
)
app_write_csv(prov, file.path(out_dir, "gate_diagnostic_figure_provenance.csv"))
readiness <- data.frame(
  category = c("sources", "traces", "synthesis", "figures"),
  check = c(
    "all_fit_objects_exist",
    "all_quantile_traces_loaded",
    "candidate_synthesis_tables_written",
    "diagnostic_figures_exist"
  ),
  passed = c(
    all(file.exists(fit_summary$fit_path)),
    all(c("elbo", "max_parameter_change") %in% unique(trace_table$trace_name)),
    file.exists(file.path(run_dirs$tables, "gate_candidate_predictions_synthesized.csv")),
    all(file.exists(unname(figures)))
  ),
  detail = c(
    paste(manifest$run_id, basename(fit_summary$fit_path), sep = "=", collapse = "; "),
    paste(sort(unique(trace_table$trace_name)), collapse = ", "),
    file.path(run_dirs$tables, "gate_candidate_predictions_synthesized.csv"),
    paste(unname(figures), collapse = "; ")
  ),
  stringsAsFactors = FALSE
)
app_write_csv(readiness, file.path(run_dirs$tables, "gate_diagnostic_readiness_report.csv"))
app_stage_done("18_make_glofas_readout_gate_diagnostic_figures", run_dirs)
cat(run_dirs$run_dir, "\n")
