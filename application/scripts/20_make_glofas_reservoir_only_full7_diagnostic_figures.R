#!/usr/bin/env Rscript
# Purpose: create a no-refit diagnostic bundle for the selected GloFAS
# reservoir-only m=360 full-seven quantile run.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/make_manuscript_outputs.R"))

args <- app_parse_args(list(
  config = "local_trackers/runtime_configs/glofas_reservoir_only_m360_full7_20260607/synthesis_config.yaml",
  source_manifest = "local_trackers/runtime_configs/glofas_reservoir_only_m360_full7_20260607/synthesis_source_manifest.csv",
  synthesis_run_id = "glofas_reservoir_only_m360_full7_20260607_synthesis_final",
  run_id = "glofas_reservoir_only_m360_full7_20260607_diagnostic_figures",
  figure_prefix = "glofas_reservoir_only_full7",
  discrepancy_history_days = "1000"
))

if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("This diagnostic script requires ggplot2.", call. = FALSE)
}

cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id)
app_stage_start("20_make_glofas_reservoir_only_full7_diagnostic_figures", run_dirs)
app_write_yaml(cfg, file.path(run_dirs$manifest, "run_config.yaml"))
app_write_json(cfg, file.path(run_dirs$manifest, "run_config.json"))
app_write_git_state(file.path(run_dirs$manifest, "git_state.txt"))
app_write_session_info(file.path(run_dirs$manifest, "session_info.txt"))

resolve_path <- function(path) {
  if (grepl("^/", path)) path else app_path(path)
}

read_required_csv <- function(path, label) {
  if (!file.exists(path)) stop(sprintf("Missing %s: %s", label, path), call. = FALSE)
  app_read_csv(path)
}

read_optional_csv <- function(path) {
  if (file.exists(path)) app_read_csv(path) else data.frame()
}

save_plot <- function(plot, name, width = 9, height = 5.5) {
  out <- file.path(fig_dir, name)
  ggplot2::ggsave(out, plot, width = width, height = height, units = "in", device = grDevices::cairo_pdf)
  out
}

safe_num <- function(x) suppressWarnings(as.numeric(x))

theme_diag <- function(base_size = 10) {
  ggplot2::theme_bw(base_size = base_size) +
    ggplot2::theme(
      plot.title.position = "plot",
      legend.position = "bottom",
      panel.grid.minor = ggplot2::element_blank(),
      strip.background = ggplot2::element_rect(fill = "gray94", color = "gray80")
    )
}

out_dir <- file.path(app_config_path(cfg, "generated_outputs"), basename(run_dirs$run_dir))
fig_dir <- file.path(out_dir, "figures")
app_ensure_dir(fig_dir)
figure_prefix <- gsub("[^A-Za-z0-9_\\-]+", "_", as.character(args$figure_prefix))
figure_name <- function(suffix) paste0(figure_prefix, "_", suffix, ".pdf")
discrepancy_history_days <- as.integer(args$discrepancy_history_days %||% 1000L)
if (!is.finite(discrepancy_history_days) || discrepancy_history_days < 1L) discrepancy_history_days <- 1000L

column_draw_summary <- function(x, level = 0.80) {
  lo <- (1 - level) / 2
  hi <- 1 - lo
  data.frame(
    estimate_lo = as.numeric(apply(x, 2L, stats::quantile, probs = lo, na.rm = TRUE, names = FALSE)),
    estimate_mid = as.numeric(apply(x, 2L, stats::quantile, probs = 0.50, na.rm = TRUE, names = FALSE)),
    estimate_hi = as.numeric(apply(x, 2L, stats::quantile, probs = hi, na.rm = TRUE, names = FALSE)),
    stringsAsFactors = FALSE
  )
}

summarize_draw_column <- function(block, value_col, level = 0.80) {
  if (!nrow(block) || !value_col %in% names(block)) return(data.frame())
  lo <- (1 - level) / 2
  hi <- 1 - lo
  x <- as.numeric(block[[value_col]])
  data.frame(
    estimate_lo = as.numeric(stats::quantile(x, probs = lo, na.rm = TRUE, names = FALSE)),
    estimate_mid = as.numeric(stats::quantile(x, probs = 0.50, na.rm = TRUE, names = FALSE)),
    estimate_hi = as.numeric(stats::quantile(x, probs = hi, na.rm = TRUE, names = FALSE)),
    stringsAsFactors = FALSE
  )
}

source_manifest <- read_required_csv(app_path(args$source_manifest), "source manifest")
if ("enabled" %in% names(source_manifest)) {
  source_manifest <- source_manifest[app_as_bool_vec(source_manifest$enabled), , drop = FALSE]
}
required_manifest_cols <- c("quantile_id", "quantile_level", "run_id", "run_dir", "raw_fit_id", "qdesn_fit_id")
app_check_required_columns(source_manifest, required_manifest_cols, "synthesis source manifest")
source_manifest$quantile_level <- safe_num(source_manifest$quantile_level)
source_manifest <- source_manifest[order(source_manifest$quantile_level), , drop = FALSE]

synth_dir <- file.path(app_config_path(cfg, "runs"), args$synthesis_run_id)
synth_tables <- file.path(synth_dir, "tables")
pred <- read_required_csv(file.path(synth_tables, "prediction_quantiles_synthesized.csv"), "synthesized predictions")
draws <- read_optional_csv(file.path(synth_tables, "posterior_draw_predictions.csv"))
score_q <- read_required_csv(file.path(synth_tables, "score_by_quantile.csv"), "score-by-quantile table")
score_i <- read_required_csv(file.path(synth_tables, "score_by_interval.csv"), "score-by-interval table")
score_c <- read_required_csv(file.path(synth_tables, "score_by_crps.csv"), "score-by-CRPS table")
score_s <- read_required_csv(file.path(synth_tables, "score_summary.csv"), "score summary")
cross_d <- read_required_csv(file.path(synth_tables, "quantile_synthesis_diagnostics.csv"), "crossing diagnostics")
cross_s <- read_required_csv(file.path(synth_tables, "quantile_synthesis_diagnostic_summary.csv"), "crossing summary")
readiness <- read_required_csv(file.path(synth_tables, "launch_readiness_report.csv"), "synthesis readiness report")

date_cols <- intersect(c("origin_date", "target_date"), names(pred))
for (nm in date_cols) pred[[nm]] <- as.Date(pred[[nm]])
for (nm in intersect(c("origin_date", "target_date"), names(score_q))) score_q[[nm]] <- as.Date(score_q[[nm]])
for (nm in intersect(c("origin_date", "target_date"), names(score_i))) score_i[[nm]] <- as.Date(score_i[[nm]])
for (nm in intersect(c("origin_date", "target_date"), names(score_c))) score_c[[nm]] <- as.Date(score_c[[nm]])
for (nm in c("quantile_level", "qhat", "qhat_monotone", "y_reference", "q_g_hat", "d_g_hat", "horizon")) {
  if (nm %in% names(pred)) pred[[nm]] <- safe_num(pred[[nm]])
}
for (nm in intersect(c("origin_date", "target_date", "discrepancy_feature_date"), names(draws))) {
  draws[[nm]] <- as.Date(draws[[nm]])
}
for (nm in intersect(c("horizon", "draw_index"), names(draws))) draws[[nm]] <- as.integer(draws[[nm]])
for (nm in intersect(c("quantile_level", "q_g_draw", "d_g_draw", "q_y_draw"), names(draws))) {
  draws[[nm]] <- safe_num(draws[[nm]])
}
for (nm in c("quantile_level", "check_loss", "check_loss_independent", "check_loss_monotone", "horizon")) {
  if (nm %in% names(score_q)) score_q[[nm]] <- safe_num(score_q[[nm]])
}
for (nm in c("horizon", "interval_score", "covered", "nominal")) {
  if (nm %in% names(score_i)) score_i[[nm]] <- safe_num(score_i[[nm]])
}
for (nm in c("horizon", "crps_quantile_grid")) {
  if (nm %in% names(score_c)) score_c[[nm]] <- safe_num(score_c[[nm]])
}

trace_rows <- list()
fit_summary_rows <- list()
stage_timing_rows <- list()
history_discrepancy_rows <- list()

for (i in seq_len(nrow(source_manifest))) {
  row <- source_manifest[i, , drop = FALSE]
  qid <- row$quantile_id[[1L]]
  qlev <- row$quantile_level[[1L]]
  src_run_dir <- resolve_path(row$run_dir[[1L]])
  fit_id <- row$qdesn_fit_id[[1L]]
  fit_path <- file.path(src_run_dir, "objects", paste0(fit_id, ".rds"))
  if (!file.exists(fit_path)) stop(sprintf("Missing saved Q-DESN fit object for %s: %s", qid, fit_path), call. = FALSE)
  fit <- readRDS(fit_path)
  diag <- fit$vb_diagnostics %||% fit$diagnostics %||% list()
  elbo <- safe_num(diag$elbo_trace %||% numeric())
  pchange <- safe_num(diag$parameter_change_trace %||% diag$max_parameter_change_trace %||% numeric())

  if (length(elbo)) {
    trace_rows[[length(trace_rows) + 1L]] <- data.frame(
      quantile_id = qid,
      quantile_level = qlev,
      trace_name = "ELBO",
      iteration = seq_along(elbo),
      value = elbo,
      stringsAsFactors = FALSE
    )
  }
  if (length(pchange)) {
    trace_rows[[length(trace_rows) + 1L]] <- data.frame(
      quantile_id = qid,
      quantile_level = qlev,
      trace_name = "Max parameter change",
      iteration = seq_along(pchange),
      value = pchange,
      stringsAsFactors = FALSE
    )
  }

  fit_diag_path <- file.path(src_run_dir, "tables", "qdesn_discrepancy_fit_diagnostics.csv")
  fit_diag <- if (file.exists(fit_diag_path)) app_read_csv(fit_diag_path) else data.frame()
  d <- if (nrow(fit_diag)) fit_diag[1L, , drop = FALSE] else data.frame()
  stage_path <- file.path(src_run_dir, "tables", "qdesn_discrepancy_fit_stage_timing.csv")
  stage <- if (file.exists(stage_path)) app_read_csv(stage_path) else data.frame()
  if (nrow(stage)) {
    stage$quantile_id <- qid
    stage$quantile_level <- qlev
    stage_timing_rows[[length(stage_timing_rows) + 1L]] <- stage
  }
  design_path <- file.path(src_run_dir, "objects", paste0(fit_id, "__design.rds"))
  if (file.exists(design_path)) {
    design <- readRDS(design_path)
    theta_mean <- safe_num(fit$summary$theta_mean %||% fit$variational_state$theta_mean %||% numeric())
    alpha_idx <- as.integer(design$alpha_index %||% integer())
    X_alpha <- design$X_alpha %||% NULL
    base <- design$base_panel %||% data.frame()
    if (length(alpha_idx) && !is.null(X_alpha) && nrow(base) == nrow(X_alpha) && length(theta_mean) >= max(alpha_idx)) {
      base$target_date <- as.Date(base$target_date)
      origin_date <- as.Date((design$latent_data %||% list())$origin_date %||% max(base$target_date, na.rm = TRUE))
      keep <- which(
        base$target_date >= origin_date - discrepancy_history_days &
          base$target_date <= origin_date
      )
      if (length(keep)) {
        alpha_mean <- theta_mean[alpha_idx]
        X_keep <- as.matrix(X_alpha[keep, , drop = FALSE])
        d_mean <- as.numeric(X_keep %*% alpha_mean)
        hist <- data.frame(
          quantile_id = qid,
          quantile_level = qlev,
          target_date = base$target_date[keep],
          horizon = 0L,
          phase = "pre_cutoff_history",
          correction = "independent_fit",
          observed_discrepancy = safe_num(base$g_transformed[keep]) - safe_num(base$y_transformed[keep]),
          estimate = d_mean,
          stringsAsFactors = FALSE
        )
        theta_draw <- fit$draws$theta %||% NULL
        if (!is.null(theta_draw) && ncol(theta_draw) >= max(alpha_idx)) {
          alpha_draw <- theta_draw[, alpha_idx, drop = FALSE]
          d_draw <- alpha_draw %*% t(X_keep)
          hist <- cbind(hist, column_draw_summary(d_draw, level = 0.80))
        } else {
          hist$estimate_lo <- NA_real_
          hist$estimate_mid <- NA_real_
          hist$estimate_hi <- NA_real_
        }
        history_discrepancy_rows[[length(history_discrepancy_rows) + 1L]] <- hist
        rm(X_keep)
      }
    }
    rm(design)
    gc(verbose = FALSE)
  }
  fit_core_sec <- if (nrow(stage) && "fit_latent_path_al_vb_core" %in% stage$stage) {
    sum(safe_num(stage$elapsed_seconds[stage$stage == "fit_latent_path_al_vb_core"]), na.rm = TRUE)
  } else {
    runtime <- safe_num(d$vb_runtime_seconds %||% NA_real_)
    if (is.finite(runtime)) runtime else NA_real_
  }
  fit_summary_rows[[length(fit_summary_rows) + 1L]] <- data.frame(
    quantile_id = qid,
    quantile_level = qlev,
    fit_id = fit_id,
    converged = app_as_bool(d$vb_converged %||% diag$converged %||% FALSE),
    iterations = as.integer(d$vb_iterations %||% diag$iterations %||% max(length(elbo), length(pchange), 0L)),
    final_parameter_change = safe_num(d$vb_max_parameter_change %||% diag$max_parameter_change %||% if (length(pchange)) tail(pchange, 1L) else NA_real_),
    final_elbo = safe_num(d$vb_elbo_final %||% diag$elbo_final %||% if (length(elbo)) tail(elbo, 1L) else NA_real_),
    beta_norm_mean = safe_num(d$beta_norm_mean %||% NA_real_),
    alpha_norm_mean = safe_num(d$alpha_norm_mean %||% NA_real_),
    sigma_Y_mean = safe_num(d$sigma_Y_mean %||% NA_real_),
    sigma_G_mean = safe_num(d$sigma_G_mean %||% NA_real_),
    max_abs_theta = safe_num(d$max_abs_theta %||% NA_real_),
    fit_core_hours = fit_core_sec / 3600,
    fit_path = fit_path,
    stringsAsFactors = FALSE
  )
}

trace_table <- app_bind_rows_fill(trace_rows)
fit_summary <- app_bind_rows_fill(fit_summary_rows)
stage_timing <- app_bind_rows_fill(stage_timing_rows)
app_write_csv(trace_table, file.path(run_dirs$tables, "vb_trace_long.csv"))
app_write_csv(fit_summary, file.path(run_dirs$tables, "vb_convergence_runtime_summary.csv"))
if (nrow(stage_timing)) app_write_csv(stage_timing, file.path(run_dirs$tables, "vb_stage_timing_long.csv"))

model_label <- function(x) {
  ifelse(grepl("^raw_glofas", x), "Raw GloFAS", "Q-DESN")
}
pred$model_label <- model_label(pred$model_id)
score_q$model_label <- model_label(score_q$model_id)
score_i$model_label <- model_label(score_i$model_id)
score_c$model_label <- model_label(score_c$model_id)
score_s$model_label <- model_label(score_s$model_id)
cross_d$model_label <- model_label(cross_d$model_id)
cross_s$model_label <- model_label(cross_s$model_id)

score_improvement <- score_s
raw_row <- score_s[score_s$model_label == "Raw GloFAS", , drop = FALSE]
qdesn_row <- score_s[score_s$model_label == "Q-DESN", , drop = FALSE]
improvement <- data.frame(
  metric = c("check_loss_mean", "interval_score_mean", "crps_quantile_grid_mean"),
  raw = c(raw_row$check_loss_mean, raw_row$interval_score_mean, raw_row$crps_quantile_grid_mean),
  qdesn = c(qdesn_row$check_loss_mean, qdesn_row$interval_score_mean, qdesn_row$crps_quantile_grid_mean),
  stringsAsFactors = FALSE
)
improvement$relative_improvement <- (improvement$raw - improvement$qdesn) / improvement$raw
app_write_csv(improvement, file.path(run_dirs$tables, "score_relative_improvement.csv"))

qdesn_pred <- pred[pred$model_label == "Q-DESN", , drop = FALSE]
raw_pred <- pred[pred$model_label == "Raw GloFAS", , drop = FALSE]

wide_quantiles <- function(x, value_col) {
  keys <- unique(x[, c("model_id", "model_label", "origin_date", "target_date", "horizon", "y_reference"), drop = FALSE])
  rows <- lapply(seq_len(nrow(keys)), function(i) {
    key <- keys[i, , drop = FALSE]
    idx <- x$model_id == key$model_id[[1L]] &
      x$target_date == key$target_date[[1L]] &
      x$horizon == key$horizon[[1L]]
    b <- x[idx, , drop = FALSE]
    val <- function(q) {
      z <- b[[value_col]][abs(b$quantile_level - q) < 1e-12]
      if (length(z)) z[[1L]] else NA_real_
    }
    data.frame(
      key,
      q05 = val(0.05), q15 = val(0.15), q35 = val(0.35), q50 = val(0.50),
      q65 = val(0.65), q80 = val(0.80), q95 = val(0.95),
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

widths <- wide_quantiles(pred, "qhat_monotone")
widths$width_90 <- widths$q95 - widths$q05
widths$width_65 <- widths$q80 - widths$q15
widths$width_30 <- widths$q65 - widths$q35
app_write_csv(widths, file.path(run_dirs$tables, "interval_widths_by_horizon.csv"))

adjust <- pred
adjust$isotonic_adjustment <- adjust$qhat_monotone - adjust$qhat
adjust$abs_isotonic_adjustment <- abs(adjust$isotonic_adjustment)
adjust_summary <- aggregate(abs_isotonic_adjustment ~ model_label, adjust, function(x) c(mean = mean(x), max = max(x), sum = sum(x)))
adjust_summary <- do.call(data.frame, adjust_summary)
names(adjust_summary) <- c("model_label", "mean_abs_adjustment", "max_abs_adjustment", "sum_abs_adjustment")
app_write_csv(adjust, file.path(run_dirs$tables, "isotonic_adjustment_by_prediction.csv"))
app_write_csv(adjust_summary, file.path(run_dirs$tables, "isotonic_adjustment_summary.csv"))

figures <- c()
q_palette <- grDevices::hcl.colors(length(unique(pred$quantile_level)), "Dark 3")
names(q_palette) <- sort(unique(pred$quantile_level))
model_palette <- c("Q-DESN" = "#2563eb", "Raw GloFAS" = "#666666")

figures <- c(figures, vb_elbo_traces = save_plot(
  ggplot2::ggplot(trace_table[trace_table$trace_name == "ELBO", ], ggplot2::aes(iteration, value, color = factor(quantile_level))) +
    ggplot2::geom_line(linewidth = 0.65) +
    ggplot2::scale_color_manual(values = q_palette) +
    ggplot2::labs(
      title = "VB ELBO Traces Across Quantile Fits",
      x = "VB iteration", y = "ELBO", color = "Quantile"
    ) +
    theme_diag(),
  figure_name("vb_elbo_traces"), 8.8, 5.2
))

figures <- c(figures, vb_parameter_change_traces = save_plot(
  ggplot2::ggplot(trace_table[trace_table$trace_name == "Max parameter change" & trace_table$value > 0, ],
    ggplot2::aes(iteration, value, color = factor(quantile_level))) +
    ggplot2::geom_line(linewidth = 0.65) +
    ggplot2::geom_hline(yintercept = 1e-4, linetype = 2, color = "gray25") +
    ggplot2::scale_y_log10() +
    ggplot2::scale_color_manual(values = q_palette) +
    ggplot2::labs(
      title = "VB Parameter-Change Traces Across Quantile Fits",
      x = "VB iteration", y = "Maximum parameter change", color = "Quantile"
    ) +
    theme_diag(),
  figure_name("vb_parameter_change_traces"), 8.8, 5.2
))

figures <- c(figures, vb_runtime_convergence = save_plot(
  ggplot2::ggplot(fit_summary, ggplot2::aes(factor(quantile_level), fit_core_hours, fill = converged)) +
    ggplot2::geom_col(width = 0.72) +
    ggplot2::geom_text(ggplot2::aes(label = paste0(iterations, " it.")), vjust = -0.25, size = 3) +
    ggplot2::scale_fill_manual(values = c("TRUE" = "#2563eb", "FALSE" = "#b91c1c")) +
    ggplot2::labs(
      title = "VB Runtime and Convergence by Quantile",
      x = "Quantile", y = "VB fit runtime (hours)", fill = "Converged"
    ) +
    theme_diag(),
  figure_name("vb_runtime_convergence"), 8.2, 4.8
))

figures <- c(figures, vb_parameter_summary = save_plot(
  ggplot2::ggplot(fit_summary, ggplot2::aes(quantile_level)) +
    ggplot2::geom_line(ggplot2::aes(y = beta_norm_mean, color = "beta norm"), linewidth = 0.75) +
    ggplot2::geom_point(ggplot2::aes(y = beta_norm_mean, color = "beta norm"), size = 2) +
    ggplot2::geom_line(ggplot2::aes(y = alpha_norm_mean, color = "alpha norm"), linewidth = 0.75) +
    ggplot2::geom_point(ggplot2::aes(y = alpha_norm_mean, color = "alpha norm"), size = 2) +
    ggplot2::labs(
      title = "Posterior Readout-Norm Summaries by Quantile",
      x = "Quantile", y = "Posterior mean norm", color = "Block"
    ) +
    theme_diag(),
  figure_name("readout_norm_summary"), 8.2, 4.8
))

score_plot_data <- rbind(
  data.frame(model_label = score_s$model_label, metric = "Check loss", value = score_s$check_loss_mean),
  data.frame(model_label = score_s$model_label, metric = "Interval score", value = score_s$interval_score_mean),
  data.frame(model_label = score_s$model_label, metric = "CRPS grid", value = score_s$crps_quantile_grid_mean)
)
figures <- c(figures, score_summary = save_plot(
  ggplot2::ggplot(score_plot_data, ggplot2::aes(model_label, value, fill = model_label)) +
    ggplot2::geom_col(width = 0.68, show.legend = FALSE) +
    ggplot2::facet_wrap(~ metric, scales = "free_y", nrow = 1) +
    ggplot2::scale_fill_manual(values = model_palette) +
    ggplot2::labs(title = "Distributional Score Summary", x = "", y = "Mean score") +
    theme_diag(),
  figure_name("score_summary"), 9.2, 4.4
))

figures <- c(figures, check_loss_by_quantile = save_plot(
  ggplot2::ggplot(score_q, ggplot2::aes(quantile_level, check_loss, color = model_label)) +
    ggplot2::stat_summary(fun = mean, geom = "line", linewidth = 0.8) +
    ggplot2::stat_summary(fun = mean, geom = "point", size = 2) +
    ggplot2::scale_color_manual(values = model_palette) +
    ggplot2::labs(
      title = "Mean Check Loss by Target Quantile",
      x = "Target quantile", y = "Mean check loss", color = "Model"
    ) +
    theme_diag(),
  figure_name("check_loss_by_quantile"), 8.2, 4.8
))

figures <- c(figures, crps_by_horizon = save_plot(
  ggplot2::ggplot(score_c, ggplot2::aes(horizon, crps_quantile_grid, color = model_label)) +
    ggplot2::geom_line(linewidth = 0.75) +
    ggplot2::geom_point(size = 1.5) +
    ggplot2::scale_color_manual(values = model_palette) +
    ggplot2::labs(
      title = "Quantile-Grid CRPS by Forecast Horizon",
      x = "Horizon (days)", y = "CRPS grid", color = "Model"
    ) +
    theme_diag(),
  figure_name("crps_by_horizon"), 8.6, 4.8
))

interval_summary <- aggregate(cbind(interval_score, covered) ~ model_label + nominal, score_i, mean, na.rm = TRUE)
app_write_csv(interval_summary, file.path(run_dirs$tables, "interval_score_coverage_summary.csv"))
figures <- c(figures, interval_coverage_score = save_plot(
  ggplot2::ggplot(interval_summary, ggplot2::aes(factor(nominal), covered, fill = model_label)) +
    ggplot2::geom_col(position = "dodge", width = 0.68) +
    ggplot2::geom_hline(ggplot2::aes(yintercept = nominal), data = unique(interval_summary["nominal"]), linetype = 2, color = "gray35") +
    ggplot2::scale_fill_manual(values = model_palette) +
    ggplot2::labs(
      title = "Empirical Interval Coverage by Nominal Level",
      x = "Nominal interval", y = "Empirical coverage", fill = "Model"
    ) +
    theme_diag(),
  figure_name("interval_coverage"), 8.2, 4.8
))

figures <- c(figures, interval_widths = save_plot(
  ggplot2::ggplot(widths[widths$model_label == "Q-DESN", ], ggplot2::aes(horizon)) +
    ggplot2::geom_line(ggplot2::aes(y = width_90, color = "90% interval"), linewidth = 0.75) +
    ggplot2::geom_line(ggplot2::aes(y = width_65, color = "65% interval"), linewidth = 0.75) +
    ggplot2::geom_line(ggplot2::aes(y = width_30, color = "30% interval"), linewidth = 0.75) +
    ggplot2::labs(
      title = "Q-DESN Synthesized Interval Widths by Horizon",
      x = "Horizon (days)", y = "Width on transformed scale", color = ""
    ) +
    theme_diag(),
  figure_name("qdesn_interval_widths"), 8.5, 4.8
))

figures <- c(figures, qdesn_ribbon_paths = save_plot(
  ggplot2::ggplot(widths[widths$model_label == "Q-DESN", ], ggplot2::aes(target_date)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = q05, ymax = q95), fill = "#93c5fd", alpha = 0.35) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = q15, ymax = q80), fill = "#60a5fa", alpha = 0.35) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = q35, ymax = q65), fill = "#2563eb", alpha = 0.30) +
    ggplot2::geom_line(ggplot2::aes(y = q50), color = "#1d4ed8", linewidth = 0.8) +
    ggplot2::geom_line(ggplot2::aes(y = y_reference), color = "black", linewidth = 0.7) +
    ggplot2::geom_point(ggplot2::aes(y = y_reference), color = "black", size = 1) +
    ggplot2::labs(
      title = "Q-DESN Synthesized Predictive Quantile Bands",
      x = "Target date", y = "Transformed streamflow"
    ) +
    theme_diag(),
  figure_name("qdesn_synthesized_bands"), 8.8, 5.0
))

figures <- c(figures, raw_vs_qdesn_paths = save_plot(
  ggplot2::ggplot(pred, ggplot2::aes(target_date, qhat_monotone, color = factor(quantile_level))) +
    ggplot2::geom_line(linewidth = 0.62) +
    ggplot2::geom_line(
      data = pred[!duplicated(pred[, c("model_label", "target_date")]), ],
      ggplot2::aes(target_date, y_reference),
      inherit.aes = FALSE, color = "black", linewidth = 0.65
    ) +
    ggplot2::geom_point(
      data = pred[!duplicated(pred[, c("model_label", "target_date")]), ],
      ggplot2::aes(target_date, y_reference),
      inherit.aes = FALSE, color = "black", size = 0.8
    ) +
    ggplot2::facet_wrap(~ model_label, ncol = 1) +
    ggplot2::scale_color_manual(values = q_palette) +
    ggplot2::labs(
      title = "Monotone Synthesized Quantile Paths",
      x = "Target date", y = "Transformed streamflow", color = "Quantile"
    ) +
    theme_diag(),
  figure_name("raw_vs_qdesn_monotone_paths"), 9.0, 7.0
))

component_data <- qdesn_pred[, c("target_date", "horizon", "quantile_level", "qhat_monotone", "q_g_hat", "d_g_hat", "y_reference"), drop = FALSE]
component_long <- rbind(
  data.frame(component_data[, c("target_date", "horizon", "quantile_level")], component = "Q-DESN corrected quantile", value = component_data$qhat_monotone),
  data.frame(component_data[, c("target_date", "horizon", "quantile_level")], component = "GloFAS model quantile", value = component_data$q_g_hat),
  data.frame(component_data[, c("target_date", "horizon", "quantile_level")], component = "Estimated discrepancy", value = component_data$d_g_hat)
)
app_write_csv(component_long, file.path(run_dirs$tables, "qdesn_component_paths_long.csv"))
figures <- c(figures, component_paths = save_plot(
  ggplot2::ggplot(component_long, ggplot2::aes(target_date, value, color = factor(quantile_level))) +
    ggplot2::geom_line(linewidth = 0.58) +
    ggplot2::facet_wrap(~ component, scales = "free_y", ncol = 1) +
    ggplot2::scale_color_manual(values = q_palette) +
    ggplot2::labs(
      title = "Q-DESN Forecast Components by Quantile",
      x = "Target date", y = "Component value", color = "Quantile"
    ) +
    theme_diag(),
  figure_name("qdesn_component_paths"), 9.0, 7.2
))

history_disc <- app_bind_rows_fill(history_discrepancy_rows)
future_disc <- data.frame()
if (nrow(qdesn_pred) && all(c("q_g_hat", "d_g_hat", "qhat", "qhat_monotone", "y_reference") %in% names(qdesn_pred))) {
  future_ind <- qdesn_pred[, c("source_quantile_id", "quantile_level", "target_date", "horizon", "q_g_hat", "d_g_hat", "qhat", "qhat_monotone", "y_reference"), drop = FALSE]
  names(future_ind)[names(future_ind) == "source_quantile_id"] <- "quantile_id"
  future_ind$phase <- "post_cutoff_forecast"
  future_ind$correction <- "independent_fit"
  future_ind$observed_discrepancy <- safe_num(future_ind$q_g_hat) - safe_num(future_ind$y_reference)
  future_ind$estimate <- safe_num(future_ind$d_g_hat)
  future_ind$estimate_lo <- NA_real_
  future_ind$estimate_mid <- NA_real_
  future_ind$estimate_hi <- NA_real_

  future_mono <- future_ind
  future_mono$correction <- "monotone_implied"
  future_mono$estimate <- safe_num(future_mono$q_g_hat) - safe_num(future_mono$qhat_monotone)

  if (nrow(draws) && "d_g_draw" %in% names(draws)) {
    draw_key <- split(seq_len(nrow(draws)), interaction(draws$quantile_level, draws$target_date, draws$horizon, drop = TRUE))
    for (i in seq_len(nrow(future_ind))) {
      key <- interaction(future_ind$quantile_level[[i]], future_ind$target_date[[i]], future_ind$horizon[[i]], drop = TRUE)
      idx <- draw_key[[as.character(key)]]
      if (length(idx)) {
        s <- summarize_draw_column(draws[idx, , drop = FALSE], "d_g_draw", level = 0.80)
        future_ind$estimate_lo[[i]] <- s$estimate_lo[[1L]]
        future_ind$estimate_mid[[i]] <- s$estimate_mid[[1L]]
        future_ind$estimate_hi[[i]] <- s$estimate_hi[[1L]]
      }
    }
  }
  future_disc <- rbind(
    future_ind[, c("quantile_id", "quantile_level", "target_date", "horizon", "phase", "correction", "observed_discrepancy", "estimate", "estimate_lo", "estimate_mid", "estimate_hi"), drop = FALSE],
    future_mono[, c("quantile_id", "quantile_level", "target_date", "horizon", "phase", "correction", "observed_discrepancy", "estimate", "estimate_lo", "estimate_mid", "estimate_hi"), drop = FALSE]
  )
}

if (nrow(history_disc) && nrow(future_disc)) {
  history_for_plot <- rbind(
    transform(history_disc, correction = "independent_fit"),
    transform(history_disc, correction = "monotone_implied")
  )
  discrepancy_window <- app_bind_rows_fill(list(history_for_plot, future_disc))
  discrepancy_window$correction_label <- ifelse(
    discrepancy_window$correction == "monotone_implied",
    "Post-correction: implied by monotone synthesis",
    "Pre-correction: independent fitted discrepancy"
  )
  discrepancy_window$quantile_label <- paste0("p=", format(discrepancy_window$quantile_level, trim = TRUE))
  discrepancy_window$target_date <- as.Date(discrepancy_window$target_date)
  app_write_csv(discrepancy_window, file.path(run_dirs$tables, "discrepancy_prepost_cutoff_window.csv"))

  cutoff_date <- max(history_disc$target_date, na.rm = TRUE)
  forecast_shade <- data.frame(
    xmin = cutoff_date,
    xmax = max(discrepancy_window$target_date, na.rm = TRUE),
    ymin = -Inf,
    ymax = Inf
  )
  cutoff_segment <- data.frame(
    x = cutoff_date,
    xend = cutoff_date,
    y = -Inf,
    yend = Inf
  )
  figures <- c(figures, discrepancy_cutoff_window = save_plot(
    ggplot2::ggplot(discrepancy_window, ggplot2::aes(target_date)) +
      ggplot2::geom_rect(
        data = forecast_shade,
        ggplot2::aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
        inherit.aes = FALSE,
        fill = "#f3f4f6", alpha = 0.55
      ) +
      ggplot2::geom_ribbon(
        data = discrepancy_window[is.finite(discrepancy_window$estimate_lo) & is.finite(discrepancy_window$estimate_hi), ],
        ggplot2::aes(ymin = estimate_lo, ymax = estimate_hi),
        fill = "#93c5fd", alpha = 0.22
      ) +
      ggplot2::geom_line(ggplot2::aes(y = observed_discrepancy), color = "#111111", linewidth = 0.42, alpha = 0.78) +
      ggplot2::geom_line(ggplot2::aes(y = estimate, color = phase), linewidth = 0.62) +
      ggplot2::geom_segment(
        data = cutoff_segment,
        ggplot2::aes(x = x, xend = xend, y = y, yend = yend),
        inherit.aes = FALSE,
        linetype = 2, color = "gray35", linewidth = 0.35
      ) +
      ggplot2::facet_grid(correction_label ~ quantile_label, scales = "free_y") +
      ggplot2::scale_color_manual(values = c("pre_cutoff_history" = "#2563eb", "post_cutoff_forecast" = "#dc2626")) +
      ggplot2::labs(
        title = sprintf("Discrepancy Fit Around the Cutoff (%d Historical Days)", discrepancy_history_days),
        subtitle = "Black: realized GloFAS-minus-USGS discrepancy; blue/red: fitted history and forecast discrepancy. Shaded area marks the forecast window.",
        x = "Date", y = "Discrepancy on transformed scale", color = "Segment"
      ) +
      theme_diag(8) +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 30, hjust = 1), legend.position = "bottom"),
    figure_name("discrepancy_prepost_cutoff_window"), 15.5, 7.5
  ))

  forecast_compare <- future_disc
  forecast_compare$correction_label <- ifelse(
    forecast_compare$correction == "monotone_implied",
    "post-correction implied discrepancy",
    "pre-correction independent discrepancy"
  )
  forecast_compare$quantile_label <- paste0("p=", format(forecast_compare$quantile_level, trim = TRUE))
  app_write_csv(forecast_compare, file.path(run_dirs$tables, "discrepancy_forecast_correction_comparison.csv"))
  figures <- c(figures, discrepancy_forecast_correction = save_plot(
    ggplot2::ggplot(forecast_compare, ggplot2::aes(horizon)) +
      ggplot2::geom_ribbon(
        data = forecast_compare[forecast_compare$correction == "independent_fit" & is.finite(forecast_compare$estimate_lo) & is.finite(forecast_compare$estimate_hi), ],
        ggplot2::aes(ymin = estimate_lo, ymax = estimate_hi),
        fill = "#93c5fd", alpha = 0.24
      ) +
      ggplot2::geom_line(ggplot2::aes(y = observed_discrepancy), color = "#111111", linewidth = 0.7) +
      ggplot2::geom_point(ggplot2::aes(y = observed_discrepancy), color = "#111111", size = 0.95) +
      ggplot2::geom_line(ggplot2::aes(y = estimate, color = correction_label, linetype = correction_label), linewidth = 0.82) +
      ggplot2::facet_wrap(~ quantile_label, scales = "free_y", ncol = 4) +
      ggplot2::scale_color_manual(values = c(
        "pre-correction independent discrepancy" = "#2563eb",
        "post-correction implied discrepancy" = "#dc2626"
      )) +
      ggplot2::scale_linetype_manual(values = c(
        "pre-correction independent discrepancy" = 1,
        "post-correction implied discrepancy" = 2
      )) +
      ggplot2::labs(
        title = "Forecast Discrepancy Before and After Monotone Synthesis",
        subtitle = "Black: realized forecast-window GloFAS-minus-USGS discrepancy. Blue: independently fitted discrepancy. Red dashed: discrepancy implied by monotone-corrected Q-DESN quantiles.",
        x = "Forecast horizon (days)", y = "Discrepancy on transformed scale", color = "", linetype = ""
      ) +
      theme_diag(9),
    figure_name("discrepancy_forecast_correction_comparison"), 12.2, 7.0
  ))
}

figures <- c(figures, isotonic_adjustment = save_plot(
  ggplot2::ggplot(adjust[adjust$model_label == "Q-DESN", ], ggplot2::aes(horizon, abs_isotonic_adjustment, color = factor(quantile_level))) +
    ggplot2::geom_line(linewidth = 0.62) +
    ggplot2::geom_point(size = 1.2) +
    ggplot2::scale_color_manual(values = q_palette) +
    ggplot2::labs(
      title = "Post-Hoc Monotone Synthesis Adjustment for Q-DESN",
      x = "Horizon (days)", y = "Absolute adjustment", color = "Quantile"
    ) +
    theme_diag(),
  figure_name("isotonic_adjustment"), 8.5, 4.8
))

figures <- c(figures, crossing_summary = save_plot(
  ggplot2::ggplot(cross_s, ggplot2::aes(diagnostic, n_crossing_pairs, fill = model_label)) +
    ggplot2::geom_col(position = "dodge", width = 0.65) +
    ggplot2::scale_fill_manual(values = model_palette) +
    ggplot2::labs(
      title = "Quantile Crossing Count Before and After Synthesis",
      x = "", y = "Crossing pairs", fill = "Model"
    ) +
    theme_diag(),
  figure_name("crossing_summary"), 7.5, 4.5
))

readiness_out <- data.frame(
  category = c("source", "source", "synthesis", "synthesis", "figures", "figures"),
  check = c(
    "all_component_fits_completed",
    "synthesis_readiness_passed",
    "post_synthesis_crossings_absent",
    "score_summary_available",
    "diagnostic_figures_written",
    "diagnostic_tables_written"
  ),
  passed = c(
    all(readiness$passed[readiness$category == "sources"]),
    all(readiness$passed),
    sum(cross_s$n_crossing_pairs[cross_s$diagnostic == "after_isotonic"], na.rm = TRUE) == 0,
    nrow(score_s) > 0L,
    all(file.exists(unname(figures))),
    all(file.exists(c(
      file.path(run_dirs$tables, "vb_trace_long.csv"),
      file.path(run_dirs$tables, "score_relative_improvement.csv"),
      file.path(run_dirs$tables, "interval_widths_by_horizon.csv")
    )))
  ),
  detail = c(
    paste(source_manifest$quantile_id, "completed", collapse = "; "),
    paste(readiness$check, readiness$passed, sep = "=", collapse = "; "),
    paste(cross_s$model_label, cross_s$diagnostic, cross_s$n_crossing_pairs, sep = ":", collapse = "; "),
    file.path(synth_tables, "score_summary.csv"),
    paste(basename(unname(figures)), collapse = "; "),
    run_dirs$tables
  ),
  stringsAsFactors = FALSE
)
app_write_csv(readiness_out, file.path(run_dirs$tables, "diagnostic_readiness_report.csv"))

prov <- app_write_output_provenance(
  outputs = figures,
  run_dirs = run_dirs,
  cfg = cfg,
  path = file.path(run_dirs$tables, "diagnostic_figure_provenance.csv")
)
app_write_csv(prov, file.path(out_dir, "diagnostic_figure_provenance.csv"))

summary_lines <- c(
  sprintf("run_id: %s", basename(run_dirs$run_dir)),
  sprintf("all_checks_passed: %s", all(readiness_out$passed)),
  sprintf("figures: %s", fig_dir),
  sprintf("tables: %s", run_dirs$tables),
  sprintf("qdesn_check_loss_mean: %.6f", qdesn_row$check_loss_mean),
  sprintf("raw_check_loss_mean: %.6f", raw_row$check_loss_mean),
  sprintf("qdesn_crps_grid_mean: %.6f", qdesn_row$crps_quantile_grid_mean),
  sprintf("raw_crps_grid_mean: %.6f", raw_row$crps_quantile_grid_mean),
  sprintf("post_synthesis_crossing_pairs: %d", sum(cross_s$n_crossing_pairs[cross_s$diagnostic == "after_isotonic"], na.rm = TRUE))
)
writeLines(summary_lines, file.path(run_dirs$tables, "diagnostic_readiness_summary.txt"))

app_stage_done("20_make_glofas_reservoir_only_full7_diagnostic_figures", run_dirs)
cat(fig_dir, "\n")
