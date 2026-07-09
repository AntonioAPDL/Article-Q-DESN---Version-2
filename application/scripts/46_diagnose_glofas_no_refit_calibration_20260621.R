#!/usr/bin/env Rscript
# Purpose: no-refit calibration diagnostics for completed GloFAS full-seven
# Q-DESN syntheses. This script never refits models; it only audits and scores
# post-synthesis spread transforms of existing quantile grids.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/forecast_spread_calibration.R"))

args <- app_parse_args(list(
  out_dir = "local_trackers/runtime_configs/glofas_calibration_broad_grid_20260619/no_refit_calibration_20260621",
  current_run_dir = "application/runs/glofas_deep_identity_d4w100m300a050_full7_20260618_synthesis_final",
  cal07_run_dir = "application/runs/glofas_calibration_broad_grid_20260619_cal07_shared003_disc006_synthesis_final",
  factors = "1.00,1.05,1.10,1.15,1.20,1.30,1.40,1.50,1.75,2.00",
  additive_widths = "0,0.05,0.10,0.20,0.35,0.50"
))

parse_num_vec <- function(x) {
  as.numeric(trimws(strsplit(as.character(x), ",", fixed = TRUE)[[1L]]))
}

repo_rel <- function(path) app_prefer_repo_relative_path(path)

out_dir <- app_path(args$out_dir)
tables_dir <- file.path(out_dir, "tables")
fig_dir <- file.path(out_dir, "figures")
logs_dir <- file.path(out_dir, "logs")
app_ensure_dir(tables_dir)
app_ensure_dir(fig_dir)
app_ensure_dir(logs_dir)

factor_grid <- parse_num_vec(args$factors)
additive_grid <- parse_num_vec(args$additive_widths)

intervals <- list(
  list(lower = 0.05, upper = 0.95, nominal = 0.90),
  list(lower = 0.15, upper = 0.80, nominal = 0.65),
  list(lower = 0.35, upper = 0.65, nominal = 0.30)
)
cfg <- list(scoring = list(intervals = intervals))

sources <- data.frame(
  source_candidate = c("current_d4", "cal07_shared003_disc006"),
  source_role = c("current_authoritative_baseline", "stage_a_tiny_calibration_candidate"),
  run_dir = c(args$current_run_dir, args$cal07_run_dir),
  stringsAsFactors = FALSE
)

read_source <- function(row) {
  run_dir <- app_path(row$run_dir[[1L]])
  tables <- file.path(run_dir, "tables")
  pred_path <- file.path(tables, "prediction_quantiles_synthesized.csv")
  score_path <- file.path(tables, "score_summary.csv")
  interval_path <- file.path(tables, "score_by_interval.csv")
  draw_path <- file.path(tables, "posterior_draw_predictions.csv")
  readiness_path <- file.path(tables, "launch_readiness_report.csv")
  missing <- c(pred_path, score_path, interval_path)[!file.exists(c(pred_path, score_path, interval_path))]
  if (length(missing)) {
    stop(sprintf("Missing required source artifacts for %s: %s", row$source_candidate[[1L]], paste(missing, collapse = "; ")), call. = FALSE)
  }

  pred <- app_read_csv(pred_path)
  score <- app_read_csv(score_path)
  interval_score <- app_read_csv(interval_path)
  draws <- app_read_csv(draw_path, required = FALSE)
  readiness <- app_read_csv(readiness_path, required = FALSE)

  pred$source_candidate <- row$source_candidate[[1L]]
  score$source_candidate <- row$source_candidate[[1L]]
  interval_score$source_candidate <- row$source_candidate[[1L]]
  draws$source_candidate <- if (nrow(draws)) row$source_candidate[[1L]] else character()
  readiness$source_candidate <- if (nrow(readiness)) row$source_candidate[[1L]] else character()

  list(
    predictions = pred,
    score_summary = score,
    interval_score = interval_score,
    draws = draws,
    readiness = readiness
  )
}

source_payloads <- lapply(seq_len(nrow(sources)), function(i) read_source(sources[i, , drop = FALSE]))
names(source_payloads) <- sources$source_candidate

source_readiness <- do.call(rbind, lapply(names(source_payloads), function(nm) {
  x <- source_payloads[[nm]]
  data.frame(
    source_candidate = nm,
    prediction_rows = nrow(x$predictions),
    score_rows = nrow(x$score_summary),
    interval_score_rows = nrow(x$interval_score),
    posterior_draw_rows = nrow(x$draws),
    launch_readiness_all_passed = if (nrow(x$readiness) && "passed" %in% names(x$readiness)) all(app_as_bool_vec(x$readiness$passed)) else NA,
    stringsAsFactors = FALSE
  )
}))
app_write_csv(sources, file.path(tables_dir, "source_manifest.csv"))
app_write_csv(source_readiness, file.path(tables_dir, "source_readiness.csv"))

original_summaries <- app_bind_rows_fill(lapply(source_payloads, `[[`, "score_summary"))
original_summaries <- original_summaries[grepl("^qdesn_", original_summaries$model_id), , drop = FALSE]
original_summaries$calibration_id <- "original"
original_summaries$spread_calibration_factor <- 1
original_summaries$spread_calibration_additive_width <- 0
app_write_csv(original_summaries, file.path(tables_dir, "original_qdesn_score_summary.csv"))

calibration_results <- lapply(names(source_payloads), function(source_candidate) {
  pred <- source_payloads[[source_candidate]]$predictions
  res <- app_score_spread_calibration_grid(
    pred,
    cfg,
    factors = factor_grid,
    additive_widths = additive_grid,
    model_family = "qdesn_glofas_discrepancy"
  )
  for (nm in names(res)) {
    if (is.data.frame(res[[nm]]) && nrow(res[[nm]])) res[[nm]]$source_candidate <- source_candidate
  }
  res
})
names(calibration_results) <- names(source_payloads)

calibrated_summary <- app_bind_rows_fill(lapply(calibration_results, `[[`, "score_summary"))
calibrated_interval <- app_bind_rows_fill(lapply(calibration_results, `[[`, "score_by_interval"))
calibrated_crps <- app_bind_rows_fill(lapply(calibration_results, `[[`, "score_by_crps"))
calibrated_predictions <- app_bind_rows_fill(lapply(calibration_results, `[[`, "predictions"))

baseline_by_source <- original_summaries[, c(
  "source_candidate", "check_loss_mean", "interval_score_mean",
  "interval_coverage_mean", "crps_quantile_grid_mean"
), drop = FALSE]
names(baseline_by_source) <- c(
  "source_candidate", "baseline_check_loss_mean", "baseline_interval_score_mean",
  "baseline_interval_coverage_mean", "baseline_crps_quantile_grid_mean"
)
calibrated_summary <- merge(calibrated_summary, baseline_by_source, by = "source_candidate", all.x = TRUE, sort = FALSE)
calibrated_summary$delta_check_loss_mean <- calibrated_summary$check_loss_mean - calibrated_summary$baseline_check_loss_mean
calibrated_summary$delta_interval_score_mean <- calibrated_summary$interval_score_mean - calibrated_summary$baseline_interval_score_mean
calibrated_summary$delta_interval_coverage_mean <- calibrated_summary$interval_coverage_mean - calibrated_summary$baseline_interval_coverage_mean
calibrated_summary$delta_crps_quantile_grid_mean <- calibrated_summary$crps_quantile_grid_mean - calibrated_summary$baseline_crps_quantile_grid_mean

calibrated_summary <- calibrated_summary[order(
  calibrated_summary$source_candidate,
  -calibrated_summary$interval_coverage_mean,
  calibrated_summary$check_loss_mean,
  calibrated_summary$interval_score_mean,
  calibrated_summary$crps_quantile_grid_mean
), , drop = FALSE]

app_write_csv(calibrated_summary, file.path(tables_dir, "no_refit_calibration_score_summary.csv"))
app_write_csv(calibrated_interval, file.path(tables_dir, "no_refit_calibration_score_by_interval.csv"))
app_write_csv(calibrated_crps, file.path(tables_dir, "no_refit_calibration_score_by_crps.csv"))
app_write_csv(calibrated_predictions, file.path(tables_dir, "no_refit_calibration_prediction_quantiles.csv"))

best_by_source <- do.call(rbind, lapply(split(calibrated_summary, calibrated_summary$source_candidate), function(x) {
  feasible <- x[x$check_loss_mean <= x$baseline_check_loss_mean * 1.02, , drop = FALSE]
  if (!nrow(feasible)) feasible <- x
  feasible <- feasible[order(
    -feasible$interval_coverage_mean,
    feasible$interval_score_mean,
    feasible$crps_quantile_grid_mean
  ), , drop = FALSE]
  feasible[1L, , drop = FALSE]
}))
app_write_csv(best_by_source, file.path(tables_dir, "no_refit_calibration_best_by_source.csv"))

original_interval_rows <- app_bind_rows_fill(lapply(names(source_payloads), function(source_candidate) {
  pred <- source_payloads[[source_candidate]]$predictions
  qpred <- pred[pred$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  rows <- app_interval_miss_rows(qpred, intervals, value_col = "qhat_monotone")
  rows$source_candidate <- source_candidate
  rows$calibration_id <- "original"
  rows
}))
best_interval_rows <- app_bind_rows_fill(lapply(seq_len(nrow(best_by_source)), function(i) {
  row <- best_by_source[i, , drop = FALSE]
  pred <- calibrated_predictions[
    calibrated_predictions$source_candidate == row$source_candidate[[1L]] &
      calibrated_predictions$spread_calibration_id == row$spread_calibration_id[[1L]],
    ,
    drop = FALSE
  ]
  rows <- app_interval_miss_rows(pred, intervals, value_col = "qhat_monotone")
  rows$source_candidate <- row$source_candidate[[1L]]
  rows$calibration_id <- row$spread_calibration_id[[1L]]
  rows
}))
miss_rows <- rbind(original_interval_rows, best_interval_rows)
miss_summary <- app_interval_miss_summary(miss_rows, c("source_candidate", "calibration_id", "nominal", "miss_direction"))
miss_horizon <- app_interval_miss_summary(miss_rows, c("source_candidate", "calibration_id", "nominal", "horizon", "miss_direction"))
app_write_csv(miss_rows, file.path(tables_dir, "interval_miss_rows_original_and_best.csv"))
app_write_csv(miss_summary, file.path(tables_dir, "interval_miss_summary_original_and_best.csv"))
app_write_csv(miss_horizon, file.path(tables_dir, "interval_miss_by_horizon_original_and_best.csv"))

draw_summary <- app_bind_rows_fill(lapply(names(source_payloads), function(source_candidate) {
  draws <- source_payloads[[source_candidate]]$draws
  if (!nrow(draws)) return(data.frame())
  out <- app_posterior_draw_spread_summary(draws)
  out$source_candidate <- source_candidate
  out
}))
if (nrow(draw_summary)) {
  app_write_csv(draw_summary, file.path(tables_dir, "posterior_draw_spread_summary.csv"))
  draw_horizon_summary <- do.call(rbind, lapply(split(draw_summary, list(draw_summary$source_candidate, draw_summary$horizon), drop = TRUE), function(x) {
    data.frame(
      source_candidate = x$source_candidate[[1L]],
      horizon = x$horizon[[1L]],
      q_y_draw_sd_mean = mean(x$q_y_draw_sd, na.rm = TRUE),
      d_g_draw_sd_mean = mean(x$d_g_draw_sd, na.rm = TRUE),
      q_g_draw_sd_mean = mean(x$q_g_draw_sd, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))
  app_write_csv(draw_horizon_summary, file.path(tables_dir, "posterior_draw_spread_by_horizon.csv"))
}

if (requireNamespace("ggplot2", quietly = TRUE)) {
  cairo_png <- function(filename, width, height, units, res, ...) {
    grDevices::png(filename, width = width, height = height, units = units, res = res, type = "cairo")
  }
  theme_diag <- ggplot2::theme_bw(base_size = 9) +
    ggplot2::theme(
      legend.position = "bottom",
      panel.grid.minor = ggplot2::element_blank(),
      strip.background = ggplot2::element_rect(fill = "gray94", color = "gray80")
    )

  p_tradeoff <- ggplot2::ggplot(
    calibrated_summary,
    ggplot2::aes(interval_coverage_mean, interval_score_mean, color = source_candidate)
  ) +
    ggplot2::geom_point(ggplot2::aes(size = crps_quantile_grid_mean), alpha = 0.74) +
    ggplot2::geom_point(
      data = original_summaries,
      ggplot2::aes(interval_coverage_mean, interval_score_mean, color = source_candidate),
      inherit.aes = FALSE,
      shape = 4,
      size = 3,
      stroke = 1.1
    ) +
    ggplot2::labs(
      x = "Mean empirical interval coverage",
      y = "Mean interval score",
      size = "Mean CRPS grid",
      color = "Source",
      title = "No-refit spread calibration tradeoff"
    ) +
    theme_diag
  ggplot2::ggsave(file.path(fig_dir, "no_refit_calibration_tradeoff.pdf"), p_tradeoff, width = 7.6, height = 5.0, units = "in", device = grDevices::cairo_pdf)
  ggplot2::ggsave(file.path(fig_dir, "no_refit_calibration_tradeoff.png"), p_tradeoff, width = 7.6, height = 5.0, units = "in", dpi = 180, device = cairo_png)

  best_ids <- best_by_source[, c("source_candidate", "spread_calibration_id"), drop = FALSE]
  interval_plot_rows <- merge(
    calibrated_interval,
    best_ids,
    by = c("source_candidate", "spread_calibration_id"),
    all = FALSE
  )
  interval_plot_rows$calibration_label <- "best_no_refit"
  original_interval_score <- app_bind_rows_fill(lapply(names(source_payloads), function(source_candidate) {
    x <- source_payloads[[source_candidate]]$interval_score
    if ("model_family" %in% names(x)) {
      x <- x[x$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
    } else {
      x <- x[grepl("^qdesn_", x$model_id), , drop = FALSE]
    }
    x$source_candidate <- source_candidate
    x$calibration_label <- "original"
    x
  }))
  interval_plot <- app_bind_rows_fill(list(original_interval_score, interval_plot_rows))
  interval_nominal <- aggregate(
    covered ~ source_candidate + calibration_label + nominal,
    interval_plot,
    mean,
    na.rm = TRUE
  )
  p_cov <- ggplot2::ggplot(interval_nominal, ggplot2::aes(factor(nominal), covered, fill = calibration_label)) +
    ggplot2::geom_col(position = "dodge", width = 0.65) +
    ggplot2::geom_hline(ggplot2::aes(yintercept = nominal), data = unique(interval_nominal["nominal"]), linetype = 2, color = "gray35") +
    ggplot2::facet_wrap(~ source_candidate) +
    ggplot2::labs(x = "Nominal interval", y = "Empirical coverage", fill = "Scenario", title = "Original versus no-refit calibrated coverage") +
    theme_diag
  ggplot2::ggsave(file.path(fig_dir, "no_refit_calibration_coverage_by_nominal.pdf"), p_cov, width = 7.4, height = 4.4, units = "in", device = grDevices::cairo_pdf)
  ggplot2::ggsave(file.path(fig_dir, "no_refit_calibration_coverage_by_nominal.png"), p_cov, width = 7.4, height = 4.4, units = "in", dpi = 180, device = cairo_png)

  p_miss <- ggplot2::ggplot(miss_horizon, ggplot2::aes(horizon, fraction, color = miss_direction)) +
    ggplot2::geom_line(linewidth = 0.6) +
    ggplot2::facet_grid(source_candidate + calibration_id ~ nominal) +
    ggplot2::labs(x = "Forecast horizon", y = "Fraction within interval rows", color = "Outcome", title = "Interval miss direction by horizon") +
    theme_diag
  ggplot2::ggsave(file.path(fig_dir, "interval_miss_direction_by_horizon.pdf"), p_miss, width = 10.0, height = 7.2, units = "in", device = grDevices::cairo_pdf)
  ggplot2::ggsave(file.path(fig_dir, "interval_miss_direction_by_horizon.png"), p_miss, width = 10.0, height = 7.2, units = "in", dpi = 180, device = cairo_png)

  if (nrow(draw_summary)) {
    p_draw <- ggplot2::ggplot(draw_summary, ggplot2::aes(horizon, q_y_draw_sd, color = factor(quantile_level))) +
      ggplot2::geom_line(linewidth = 0.55) +
      ggplot2::facet_wrap(~ source_candidate, ncol = 1) +
      ggplot2::labs(x = "Forecast horizon", y = "Posterior draw sd of q_y", color = "Quantile", title = "Posterior draw spread by horizon") +
      theme_diag
    ggplot2::ggsave(file.path(fig_dir, "posterior_draw_spread_by_horizon.pdf"), p_draw, width = 8.2, height = 5.8, units = "in", device = grDevices::cairo_pdf)
    ggplot2::ggsave(file.path(fig_dir, "posterior_draw_spread_by_horizon.png"), p_draw, width = 8.2, height = 5.8, units = "in", dpi = 180, device = cairo_png)
  }
} else {
  writeLines("ggplot2 is not installed; CSV diagnostics were written but figures were skipped.", file.path(logs_dir, "figure_warning.txt"))
}

readiness <- data.frame(
  check = c(
    "source_prediction_tables_available",
    "source_launch_readiness_passed",
    "calibration_grid_scored",
    "best_candidate_table_written",
    "no_refit_only"
  ),
  passed = c(
    all(source_readiness$prediction_rows > 0),
    all(is.na(source_readiness$launch_readiness_all_passed) | source_readiness$launch_readiness_all_passed),
    nrow(calibrated_summary) == length(factor_grid) * length(additive_grid) * nrow(sources),
    file.exists(file.path(tables_dir, "no_refit_calibration_best_by_source.csv")),
    TRUE
  ),
  detail = c(
    paste(source_readiness$source_candidate, source_readiness$prediction_rows, sep = " rows=", collapse = "; "),
    paste(source_readiness$source_candidate, source_readiness$launch_readiness_all_passed, sep = "=", collapse = "; "),
    sprintf("%d scenarios", nrow(calibrated_summary)),
    repo_rel(file.path(tables_dir, "no_refit_calibration_best_by_source.csv")),
    "This diagnostic uses completed prediction tables only; no Q-DESN fits are launched."
  ),
  stringsAsFactors = FALSE
)
app_write_csv(readiness, file.path(tables_dir, "no_refit_calibration_readiness.csv"))

summary_lines <- c(
  "# GloFAS No-Refit Calibration Diagnostics",
  "",
  sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "This runtime package scores median-centered spread transformations of completed full-seven Q-DESN quantile grids.",
  "It does not refit any model and is intended as a diagnostic gate before deciding whether synthesis-time calibration is worth formalizing.",
  "",
  "## Sources",
  paste(sprintf("- `%s`: `%s`", sources$source_candidate, sources$run_dir), collapse = "\n"),
  "",
  "## Key Outputs",
  sprintf("- `%s`", repo_rel(file.path(tables_dir, "no_refit_calibration_score_summary.csv"))),
  sprintf("- `%s`", repo_rel(file.path(tables_dir, "no_refit_calibration_best_by_source.csv"))),
  sprintf("- `%s`", repo_rel(file.path(tables_dir, "interval_miss_summary_original_and_best.csv"))),
  sprintf("- `%s`", repo_rel(file.path(fig_dir, "no_refit_calibration_tradeoff.pdf"))),
  sprintf("- `%s`", repo_rel(file.path(fig_dir, "no_refit_calibration_coverage_by_nominal.pdf"))),
  sprintf("- `%s`", repo_rel(file.path(fig_dir, "interval_miss_direction_by_horizon.pdf"))),
  "",
  "## Best Diagnostic Scenarios",
  paste(capture.output(print(best_by_source[, c(
    "source_candidate", "spread_calibration_id", "check_loss_mean",
    "interval_coverage_mean", "interval_score_mean", "crps_quantile_grid_mean",
    "delta_check_loss_mean", "delta_interval_coverage_mean"
  ), drop = FALSE], row.names = FALSE)), collapse = "\n")
)
writeLines(summary_lines, file.path(out_dir, "README.md"))
app_write_git_state(file.path(logs_dir, "git_state.txt"))
app_write_session_info(file.path(logs_dir, "session_info.txt"))

cat(sprintf("wrote=%s\n", repo_rel(out_dir)))
cat("best diagnostic scenarios:\n")
print(best_by_source[, c(
  "source_candidate", "spread_calibration_id", "check_loss_mean",
  "interval_coverage_mean", "interval_score_mean", "crps_quantile_grid_mean",
  "delta_check_loss_mean", "delta_interval_coverage_mean"
), drop = FALSE], row.names = FALSE)
