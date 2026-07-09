#!/usr/bin/env Rscript
# Purpose: create a compact no-refit diagnostic figure bundle for a completed
# GloFAS multi-quantile application run and its hybrid synthesis evaluation.
# Inputs: completed per-quantile fit objects, synthesis predictions, and hybrid
# predictions. Outputs: ELBO/trace/convergence and dynamic-quantile figures.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/make_manuscript_outputs.R"))

args <- app_parse_args(list(
  config = "local_trackers/runtime_configs/glofas_multiquantile_dec25_20260603/synthesis_config.yaml",
  source_manifest = "local_trackers/runtime_configs/glofas_multiquantile_dec25_20260603/synthesis_source_manifest.csv",
  synthesis_run_id = "glofas_multiquantile_dec25_20260603_synthesis_final",
  hybrid_run_id = "glofas_multiquantile_dec25_20260603_hybrid_eval",
  run_id = "glofas_multiquantile_dec25_20260603_diagnostic_figures",
  hybrid_candidate = "qdesn_center_35_65_raw_tails"
))

cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id)
app_stage_start("12_make_glofas_multiquantile_diagnostic_figures", run_dirs)
app_write_yaml(cfg, file.path(run_dirs$manifest, "run_config.yaml"))
app_write_json(cfg, file.path(run_dirs$manifest, "run_config.json"))
app_write_git_state(file.path(run_dirs$manifest, "git_state.txt"))
app_write_session_info(file.path(run_dirs$manifest, "session_info.txt"))

resolve_path <- function(path) {
  if (grepl("^/", path)) path else app_path(path)
}

source_manifest <- app_read_csv(app_path(args$source_manifest))
if ("enabled" %in% names(source_manifest)) {
  source_manifest <- source_manifest[app_as_bool_vec(source_manifest$enabled), , drop = FALSE]
}
required_manifest_cols <- c("quantile_id", "quantile_level", "run_dir", "qdesn_fit_id")
app_check_required_columns(source_manifest, required_manifest_cols, "synthesis source manifest")
source_manifest$quantile_level <- as.numeric(source_manifest$quantile_level)

trace_rows <- list()
fit_summary_rows <- list()
timing_rows <- list()

for (i in seq_len(nrow(source_manifest))) {
  row <- source_manifest[i, , drop = FALSE]
  run_dir <- resolve_path(row$run_dir[[1L]])
  fit_id <- row$qdesn_fit_id[[1L]]
  fit_path <- file.path(run_dir, "objects", paste0(fit_id, ".rds"))
  if (!file.exists(fit_path)) {
    stop(sprintf("Missing saved Q-DESN fit object for %s: %s", row$quantile_id[[1L]], fit_path), call. = FALSE)
  }
  fit <- readRDS(fit_path)
  diag <- fit$vb_diagnostics %||% fit$diagnostics %||% list()
  elbo <- as.numeric(diag$elbo_trace %||% numeric())
  pchange <- as.numeric(diag$parameter_change_trace %||% diag$max_parameter_change_trace %||% numeric())
  n_iter <- max(length(elbo), length(pchange), as.integer(diag$iterations %||% 0L), na.rm = TRUE)
  if (!is.finite(n_iter)) n_iter <- 0L
  if (length(elbo)) {
    trace_rows[[length(trace_rows) + 1L]] <- data.frame(
      quantile_id = row$quantile_id[[1L]],
      quantile_level = row$quantile_level[[1L]],
      trace_name = "elbo",
      iteration = seq_along(elbo),
      value = elbo,
      stringsAsFactors = FALSE
    )
  }
  if (length(pchange)) {
    trace_rows[[length(trace_rows) + 1L]] <- data.frame(
      quantile_id = row$quantile_id[[1L]],
      quantile_level = row$quantile_level[[1L]],
      trace_name = "max_parameter_change",
      iteration = seq_along(pchange),
      value = pchange,
      stringsAsFactors = FALSE
    )
  }

  stage_path <- file.path(run_dir, "tables", "qdesn_discrepancy_fit_stage_timing.csv")
  stage <- if (file.exists(stage_path)) app_read_csv(stage_path) else data.frame()
  fit_core_sec <- if (nrow(stage) && "fit_latent_path_al_vb_core" %in% stage$stage) {
    sum(as.numeric(stage$elapsed_seconds[stage$stage == "fit_latent_path_al_vb_core"]), na.rm = TRUE)
  } else {
    NA_real_
  }
  total_sec <- if (nrow(stage) && "elapsed_seconds" %in% names(stage)) {
    sum(as.numeric(stage$elapsed_seconds), na.rm = TRUE)
  } else {
    NA_real_
  }
  fit_summary_rows[[length(fit_summary_rows) + 1L]] <- data.frame(
    quantile_id = row$quantile_id[[1L]],
    quantile_level = row$quantile_level[[1L]],
    fit_id = fit_id,
    converged = isTRUE(diag$converged %||% FALSE),
    iterations = as.integer(diag$iterations %||% n_iter),
    elbo_final = as.numeric(diag$elbo_final %||% if (length(elbo)) tail(elbo, 1L) else NA_real_),
    max_parameter_change = as.numeric(diag$max_parameter_change %||% if (length(pchange)) tail(pchange, 1L) else NA_real_),
    fit_core_hours = fit_core_sec / 3600,
    total_hours = total_sec / 3600,
    fit_path = fit_path,
    stringsAsFactors = FALSE
  )
  if (nrow(stage)) {
    stage$quantile_id <- row$quantile_id[[1L]]
    stage$quantile_level <- row$quantile_level[[1L]]
    timing_rows[[length(timing_rows) + 1L]] <- stage
  }
}

trace_table <- app_bind_rows_fill(trace_rows)
fit_summary <- app_bind_rows_fill(fit_summary_rows)
timing_table <- app_bind_rows_fill(timing_rows)
fit_summary <- fit_summary[order(fit_summary$quantile_level), , drop = FALSE]
app_write_csv(trace_table, file.path(run_dirs$tables, "vb_trace_long.csv"))
app_write_csv(fit_summary, file.path(run_dirs$tables, "vb_convergence_runtime_summary.csv"))
if (nrow(timing_table)) app_write_csv(timing_table, file.path(run_dirs$tables, "vb_stage_timing_long.csv"))

synthesis_pred_path <- file.path(app_config_path(cfg, "runs"), args$synthesis_run_id, "tables", "prediction_quantiles_synthesized.csv")
hybrid_pred_path <- file.path(app_config_path(cfg, "runs"), args$hybrid_run_id, "tables", "hybrid_candidate_predictions_synthesized.csv")
if (!file.exists(synthesis_pred_path)) stop(sprintf("Missing synthesis prediction table: %s", synthesis_pred_path), call. = FALSE)
if (!file.exists(hybrid_pred_path)) stop(sprintf("Missing hybrid prediction table: %s", hybrid_pred_path), call. = FALSE)
synthesis_pred <- app_read_csv(synthesis_pred_path)
hybrid_pred <- app_read_csv(hybrid_pred_path)
hybrid_candidate <- as.character(args$hybrid_candidate)
if (!hybrid_candidate %in% hybrid_pred$model_id) {
  stop(sprintf("Hybrid candidate '%s' is absent from %s.", hybrid_candidate, hybrid_pred_path), call. = FALSE)
}

out_dir <- file.path(app_config_path(cfg, "generated_outputs"), basename(run_dirs$run_dir))
fig_dir <- file.path(out_dir, "figures")
app_ensure_dir(fig_dir)

plot_pdf <- function(name, width = 8, height = 4.8, expr) {
  path <- file.path(fig_dir, name)
  grDevices::pdf(path, width = width, height = height)
  on.exit(grDevices::dev.off(), add = TRUE)
  force(expr)
  path
}

q_cols <- grDevices::hcl.colors(nrow(fit_summary), "Dark 3")
names(q_cols) <- fit_summary$quantile_id
figures <- c()

figures <- c(figures, vb_elbo_traces = plot_pdf("glofas_multiquantile_vb_elbo_traces.pdf", 8.5, 5.2, {
  dat <- trace_table[trace_table$trace_name == "elbo" & is.finite(trace_table$value), , drop = FALSE]
  yr <- range(dat$value, na.rm = TRUE)
  plot(range(dat$iteration), yr + c(-0.04, 0.04) * diff(yr), type = "n",
    xlab = "VB iteration", ylab = "ELBO", main = "ELBO traces by target quantile")
  grid(col = "gray90")
  for (qid in fit_summary$quantile_id) {
    block <- dat[dat$quantile_id == qid, , drop = FALSE]
    lines(block$iteration, block$value, col = q_cols[[qid]], lwd = 1.7)
  }
  legend("bottomright", legend = paste0(fit_summary$quantile_id, " (p=", fit_summary$quantile_level, ")"),
    col = q_cols, lty = 1, lwd = 1.7, bty = "n", cex = 0.78)
}))

figures <- c(figures, vb_parameter_change = plot_pdf("glofas_multiquantile_vb_parameter_change_traces.pdf", 8.5, 5.2, {
  dat <- trace_table[trace_table$trace_name == "max_parameter_change" & is.finite(trace_table$value) & trace_table$value > 0, , drop = FALSE]
  plot(range(dat$iteration), range(dat$value, na.rm = TRUE), type = "n", log = "y",
    xlab = "VB iteration", ylab = "Maximum parameter change",
    main = "VB parameter-change traces by target quantile")
  grid(col = "gray90")
  abline(h = 1e-4, col = "#111111", lty = 2, lwd = 1.2)
  for (qid in fit_summary$quantile_id) {
    block <- dat[dat$quantile_id == qid, , drop = FALSE]
    lines(block$iteration, block$value, col = q_cols[[qid]], lwd = 1.7)
  }
  legend("topright", legend = c(paste0(fit_summary$quantile_id, " (p=", fit_summary$quantile_level, ")"), "tol=1e-4"),
    col = c(q_cols, "#111111"), lty = c(rep(1, length(q_cols)), 2), lwd = c(rep(1.7, length(q_cols)), 1.2),
    bty = "n", cex = 0.76)
}))

figures <- c(figures, vb_runtime_convergence = plot_pdf("glofas_multiquantile_vb_runtime_convergence.pdf", 8.2, 4.8, {
  par(mar = c(5, 4.2, 2.2, 4.2))
  vals <- fit_summary$fit_core_hours
  cols <- ifelse(fit_summary$converged, "#2563eb", "#b91c1c")
  bp <- barplot(vals, names.arg = paste0("p=", fit_summary$quantile_level), col = cols, border = NA,
    ylab = "VB core runtime (hours)", main = "Runtime and convergence by quantile")
  grid(nx = NA, ny = NULL, col = "gray88")
  text(bp, vals, labels = paste0(fit_summary$iterations, " it."), pos = 3, cex = 0.78)
  par(new = TRUE)
  plot(bp, fit_summary$max_parameter_change, type = "b", pch = 19, axes = FALSE, xlab = "", ylab = "",
    col = "#111111", log = "y")
  axis(4)
  mtext("Final max parameter change", side = 4, line = 2.6)
  abline(h = 1e-4, lty = 2, col = "#111111")
  legend("topleft", legend = c("converged", "hit iteration cap", "final change"),
    fill = c("#2563eb", "#b91c1c", NA), border = NA, lty = c(NA, NA, 1),
    col = c(NA, NA, "#111111"), pch = c(NA, NA, 19), bty = "n", cex = 0.78)
}))

prep_pred <- function(x, label, value_col = "qhat_monotone") {
  x$origin_date <- as.Date(x$origin_date)
  x$target_date <- as.Date(x$target_date)
  x$horizon <- as.integer(x$horizon)
  x$quantile_level <- as.numeric(x$quantile_level)
  x$q_plot <- as.numeric(x[[value_col]])
  x$panel <- label
  x
}
raw_pred <- synthesis_pred[synthesis_pred$model_family == "raw_glofas", , drop = FALSE]
qdesn_pred <- synthesis_pred[synthesis_pred$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
hyb_pred <- hybrid_pred[hybrid_pred$model_id == hybrid_candidate, , drop = FALSE]
plot_pred <- app_bind_rows_fill(list(
  prep_pred(raw_pred, "Raw GloFAS"),
  prep_pred(qdesn_pred, "All Q-DESN"),
  prep_pred(hyb_pred, sprintf("Hybrid: %s", hybrid_candidate))
))
app_write_csv(plot_pred, file.path(run_dirs$tables, "dynamic_quantile_plot_data.csv"))

figures <- c(figures, dynamic_quantile_paths = plot_pdf("glofas_multiquantile_raw_qdesn_hybrid_paths.pdf", 9, 8.2, {
  panels <- unique(plot_pred$panel)
  qs <- sort(unique(plot_pred$quantile_level))
  cols <- grDevices::hcl.colors(length(qs), "Dark 3")
  names(cols) <- as.character(qs)
  y_ref <- plot_pred[!duplicated(plot_pred$target_date), c("target_date", "y_reference"), drop = FALSE]
  y_ref <- y_ref[order(y_ref$target_date), , drop = FALSE]
  ylim <- range(c(plot_pred$q_plot, y_ref$y_reference), na.rm = TRUE)
  par(mfrow = c(length(panels), 1), mar = c(3.2, 4.2, 2.0, 1), oma = c(1, 0, 0, 0))
  for (panel in panels) {
    block_all <- plot_pred[plot_pred$panel == panel, , drop = FALSE]
    plot(range(block_all$target_date), ylim + c(-0.05, 0.05) * diff(ylim), type = "n",
      xlab = "", ylab = "Transformed streamflow", main = panel)
    grid(col = "gray90")
    for (q in qs) {
      block <- block_all[abs(block_all$quantile_level - q) < 1e-12, , drop = FALSE]
      block <- block[order(block$target_date), , drop = FALSE]
      lines(block$target_date, block$q_plot, col = cols[[as.character(q)]], lwd = if (abs(q - 0.5) < 1e-12) 2.2 else 1.4)
    }
    lines(y_ref$target_date, y_ref$y_reference, col = "#111111", lwd = 1.9)
    points(y_ref$target_date, y_ref$y_reference, col = "#111111", pch = 19, cex = 0.42)
  }
  legend("bottom", inset = -0.06, xpd = NA,
    legend = c(paste0("p=", qs), "observed"), col = c(cols, "#111111"),
    lty = 1, lwd = c(rep(1.5, length(qs)), 1.9), bty = "n", cex = 0.78, ncol = 4)
}))

outputs <- figures
prov <- app_write_output_provenance(
  outputs = outputs,
  run_dirs = run_dirs,
  cfg = cfg,
  path = file.path(run_dirs$tables, "diagnostic_figure_provenance.csv")
)
app_write_csv(prov, file.path(out_dir, "diagnostic_figure_provenance.csv"))

readiness <- data.frame(
  category = c("sources", "traces", "predictions", "figures"),
  check = c(
    "all_fit_objects_exist",
    "all_quantile_traces_loaded",
    "synthesis_and_hybrid_prediction_tables_exist",
    "diagnostic_figures_exist"
  ),
  passed = c(
    all(file.exists(fit_summary$fit_path)),
    length(unique(trace_table$quantile_id)) == nrow(source_manifest),
    file.exists(synthesis_pred_path) && file.exists(hybrid_pred_path),
    all(file.exists(unname(figures)))
  ),
  detail = c(
    paste(source_manifest$quantile_id, basename(fit_summary$fit_path), sep = "=", collapse = "; "),
    paste(sort(unique(trace_table$quantile_id)), collapse = ", "),
    paste(synthesis_pred_path, hybrid_pred_path, sep = "; "),
    paste(unname(figures), collapse = "; ")
  ),
  stringsAsFactors = FALSE
)
app_write_csv(readiness, file.path(run_dirs$tables, "diagnostic_readiness_report.csv"))
writeLines(
  c(
    sprintf("run_id: %s", basename(run_dirs$run_dir)),
    sprintf("synthesis_run_id: %s", args$synthesis_run_id),
    sprintf("hybrid_run_id: %s", args$hybrid_run_id),
    sprintf("hybrid_candidate: %s", hybrid_candidate),
    sprintf("all_checks_passed: %s", all(readiness$passed)),
    sprintf("generated_outputs: %s", out_dir)
  ),
  file.path(run_dirs$tables, "diagnostic_readiness_summary.txt")
)

app_stage_done("12_make_glofas_multiquantile_diagnostic_figures", run_dirs)
cat(run_dirs$run_dir, "\n")
