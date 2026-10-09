#!/usr/bin/env Rscript
# Presentation-only derivatives of frozen public summaries and plotting extracts.
# Does not source inference code, change fits, rescore, project quantiles, or select models.
options(stringsAsFactors = FALSE, digits = 17)
script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))
root <- normalizePath(file.path(dirname(script), ".."))
setwd(root)
stopifnot(requireNamespace("ggplot2", quietly = TRUE), requireNamespace("jsonlite", quietly = TRUE))
source("scripts/qdesn_evaluation_figure_style.R")
sha <- function(path) strsplit(system2("sha256sum", shQuote(path), stdout = TRUE), " +")[[1L]][1L]
read_table <- function(name) read.csv(file.path("tables", name), check.names = FALSE)
sources <- c("tables/qdesn_validation_500obs_dgp_oracle_figure_data_v14.csv",
             "tables/joint_qdesn_pure_desn_v1_forecast_score_summary.csv",
             "tables/joint_qdesn_pure_desn_v1_fit_oracle_diagnostics.csv",
             "tables/glofas_search3_part1234_final_20261007_source_quantiles.csv",
             "tables/glofas_search3_review_history_plot_inputs.csv",
             "tables/glofas_search3_review_ensemble_plot_inputs.csv",
             "tables/glofas_search3_review_truth_plot_inputs.csv",
             "tables/glofas_search3_review_plot_input_provenance.json",
             "tables/glofas_search3_part1234_final_20261007_part4_scores.csv",
             "tables/glofas_search3_part1234_final_20261007_part4_scores.tex",
             "tables/qdesn_validation_500obs_v14_mcmc_forecast_metric_interval_figures.tex",
             "tables/qdesn_validation_500obs_v14_mcmc_fit_metric_interval_figure.tex",
             "tables/qdesn_validation_500obs_v14_vb_metric_interval_figures.tex",
             "tables/joint_qdesn_pure_desn_v1_forecast_figure.tex",
             "tables/joint_qdesn_pure_desn_v1_fit_figure.tex")
source_hashes <- stats::setNames(vapply(sources, sha, character(1)), sources)
stopifnot(source_hashes[[sources[[4L]]]] == "d4a6c18eac599c66e9e95edda01e98d9f14c8f6a8efc6dd2a54f16544ae7181a")
output_paths <- character()
normalize_pdf_date <- function(path) {
  bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  marker <- charToRaw("/CreationDate (D:")
  candidates <- which(bytes == marker[[1L]])
  hits <- candidates[vapply(candidates, function(at) {
    end <- at + length(marker) - 1L
    end <= length(bytes) && identical(bytes[at:end], marker)
  }, logical(1L))]
  stopifnot(length(hits) == 1L)
  closing <- which(seq_along(bytes) > hits[[1L]] & bytes == charToRaw(")")[[1L]])[[1L]]
  replacement <- charToRaw("/CreationDate (D:20000101000000+00'00)")
  stopifnot(length(replacement) == closing - hits[[1L]] + 1L)
  bytes[hits[[1L]]:closing] <- replacement
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(bytes, con)
}
register <- function(path) {
  if (grepl("\\.pdf$", path)) normalize_pdf_date(path)
  output_paths <<- c(output_paths, path)
}
readable_theme <- ggplot2::theme(
  text = ggplot2::element_text(size = 10.4),
  strip.text = ggplot2::element_text(face = "bold", size = 10.4, lineheight = .98),
  axis.text.x = ggplot2::element_text(size = 10.4),
  axis.text.y = ggplot2::element_text(size = 10.4, colour = "#242424"),
  axis.title.x = ggplot2::element_text(size = 10.4),
  plot.margin = ggplot2::margin(7, 16, 7, 7), panel.spacing = grid::unit(1.0, "lines"))
independent <- read_table("qdesn_validation_500obs_dgp_oracle_figure_data_v14.csv")
stopifnot(nrow(independent) == 216L)
jobs <- data.frame(inference = c("mcmc", "mcmc", "mcmc", "vb"),
  metric_role = c("fit_rmse", "forecast_mae", "forecast_check", "fit_rmse"),
  suffix = c("mcmc_fit_rmse", "mcmc_forecast_mae", "mcmc_forecast_check_loss", "vb_fit_rmse"))
for (i in seq_len(nrow(jobs))) {
  p <- qdesn_independent_interval_plot(independent, jobs$inference[i], jobs$metric_role[i]) + readable_theme
  path <- paste0("figures/independent_simulation/qdesn_pro_review_", jobs$suffix[i], ".pdf")
  qdesn_save_vector_pdf(path, p, 7.2, 6.6)
  register(path)
}
score <- read_table("joint_qdesn_pure_desn_v1_forecast_score_summary.csv")
score <- score[score$inference_method == "mcmc", ]
fit <- read_table("joint_qdesn_pure_desn_v1_fit_oracle_diagnostics.csv")
fit <- fit[fit$inference_method == "mcmc", ]
fit <- fit[match(score$model_cell_id, fit$model_cell_id), ]
stopifnot(nrow(score) == 32L, nrow(fit) == 32L, identical(score$model_cell_id, fit$model_cell_id))
model_style <- stats::setNames(qdesn_joint_model_order, sub("_vb$", "_mcmc", qdesn_joint_model_order))
joint_data <- data.frame(scenario_id = score$scenario_id, source_model_id = unname(model_style[score$model_id]),
  likelihood_family = score$likelihood_family, mean = score$posterior_score_mean,
  lo = score$posterior_score_q025, hi = score$posterior_score_q975,
  crossing = sprintf("%.2f%%", 100 * score$canonical_raw_crossing_pairs / (33 * 30 * 6)))
joint_plot <- function(data, xlab, point_only = FALSE) {
  p <- qdesn_joint_interval_plot(data, xlab) + readable_theme
  # Same annotation estimator; only its font and reserved column change.
  p$layers[[3L]]$aes_params$size <- 3.7
  for (scenario in levels(p$data$scenario_id)) {
    at <- which(p$data$scenario_id == scenario)
    span <- max(p$data$hi[at]) - min(p$data$lo[at])
    if (!is.finite(span) || span <= 0) span <- max(abs(p$data$hi[at]), 1) * .1
    p$data$label_x[at] <- max(p$data$hi[at]) + .72 * span
  }
  xscale <- p$scales$get_scales("x")
  xscale$labels <- function(x) {
    digits <- if (length(x) > 1L && diff(range(x, na.rm = TRUE)) < .04) 3L else 2L
    formatC(x, format = "f", digits = digits)
  }
  if (point_only) p$layers <- p$layers[-1L]
  p
}
path <- "figures/joint_qdesn_simulation/joint_qdesn_pro_review_forecast_dgp_acrps.pdf"
qdesn_save_vector_pdf(path, joint_plot(joint_data, "DGP-integrated aCRPS"), 7.0, 8.1)
register(path)
fit_data <- joint_data
fit_data$mean <- fit_data$lo <- fit_data$hi <- fit$fit_oracle_rmse
fit_data$crossing <- sprintf("%.2f%%", 100 * fit$fit_raw_crossing_pairs / (500 * 6))
path <- "figures/joint_qdesn_simulation/joint_qdesn_pro_review_fit_oracle_rmse.pdf"
qdesn_save_vector_pdf(path, joint_plot(fit_data, "Fitting-sample quantile-path RMSE", TRUE), 7.0, 8.1)
register(path)

# The main GloFAS comparison uses authentic history, all issued members, and
# the two retained seven-quantile forecasts; it does not infer credible limits.
q <- read_table("glofas_search3_part1234_final_20261007_source_quantiles.csv")
q <- q[q$part == "Part 4", ]
q$target_date <- as.Date(q$target_date)
history <- read_table("glofas_search3_review_history_plot_inputs.csv")
history$target_date <- as.Date(history$target_date)
ensemble <- read_table("glofas_search3_review_ensemble_plot_inputs.csv")
ensemble$origin_date <- as.Date(ensemble$origin_date)
ensemble$target_date <- as.Date(ensemble$target_date)
truth <- read_table("glofas_search3_review_truth_plot_inputs.csv")
truth$target_date <- as.Date(truth$target_date)
origin <- as.Date("2022-12-25")
probabilities <- c(.05, .20, .35, .50, .65, .80, .95)
stopifnot(nrow(history) == 30L, nrow(ensemble) == 1428L, length(unique(ensemble$member)) == 51L, nrow(truth) == 28L)
raw <- q[q$family == "Raw GloFAS", ]
for (h in 1:28) {
  e <- ensemble$g_transformed[ensemble$horizon == h]
  retained <- raw[raw$horizon == h, ]
  retained <- retained[order(retained$quantile_level), ]
  stopifnot(max(abs(stats::quantile(e, probabilities, type = 8, names = FALSE) - retained$qhat)) < 1e-12)
}
for (family in c("Independent AL", "Normal Ridge")) {
  block <- q[q$family == family, ]
  stopifnot(nrow(block) == 196L, setequal(block$quantile_level, probabilities),
    max(abs(block$y_reference - truth$y_transformed[match(block$target_date, truth$target_date)])) < 1e-12)
}
selected <- q[q$family %in% c("Independent AL", "Normal Ridge"), ]
values <- c(history$y_transformed, history$g_transformed, ensemble$g_transformed, truth$y_transformed, selected$qhat)
ylim <- c(min(0, floor(min(values))), max(6, ceiling(max(values))))
base_theme <- ggplot2::theme_bw(base_size = 10.4, base_family = "sans") + ggplot2::theme(
  panel.grid.minor = ggplot2::element_blank(), panel.grid.major.x = ggplot2::element_blank(),
  panel.grid.major.y = ggplot2::element_line(colour = "#EBEBEB", linewidth = .2),
  axis.title = ggplot2::element_text(size = 10.4), axis.text = ggplot2::element_text(size = 10.4, colour = "#242424"),
  plot.title = ggplot2::element_text(size = 11, face = "bold"), plot.subtitle = ggplot2::element_text(size = 10.4),
  legend.position = "bottom", legend.title = ggplot2::element_blank(), legend.text = ggplot2::element_text(size = 9.8),
  legend.key.height = grid::unit(9, "pt"), legend.key.width = grid::unit(16, "pt"),
  legend.margin = ggplot2::margin(0, 0, 0, 0), plot.margin = ggplot2::margin(5, 7, 3, 5))
data_colors <- c("Historical USGS" = "#1B5E20", "Held-out USGS" = "#8B1A1A",
                 "Retrospective GloFAS" = "#C26A00", "Issued GloFAS ensemble" = "#C26A00")
historical_usgs <- data.frame(target_date = history$target_date, value = history$y_transformed, series = "Historical USGS")
historical_glofas <- data.frame(target_date = history$target_date, value = history$g_transformed, series = "Retrospective GloFAS")
future_usgs <- data.frame(target_date = truth$target_date, value = truth$y_transformed, series = "Held-out USGS")
p_data <- ggplot2::ggplot() +
  ggplot2::geom_line(data = ensemble, ggplot2::aes(target_date, g_transformed, group = member, colour = "Issued GloFAS ensemble"), linewidth = .13, alpha = .13) +
  ggplot2::geom_line(data = historical_glofas, ggplot2::aes(target_date, value, colour = series), linewidth = .28, linetype = "22") +
  ggplot2::geom_line(data = historical_usgs, ggplot2::aes(target_date, value, colour = series), linewidth = .22) +
  ggplot2::geom_point(data = historical_usgs, ggplot2::aes(target_date, value, colour = series), shape = 16, size = 1.05) +
  ggplot2::geom_line(data = future_usgs, ggplot2::aes(target_date, value, colour = series), linewidth = .22) +
  ggplot2::geom_point(data = future_usgs, ggplot2::aes(target_date, value, colour = series), shape = 1, size = 1.3, stroke = .5) +
  ggplot2::geom_vline(xintercept = origin, colour = "#686868", linewidth = .22, linetype = "22") +
  ggplot2::scale_colour_manual(values = data_colors, breaks = names(data_colors)) +
  ggplot2::scale_x_date(date_breaks = "2 weeks", date_labels = "%d %b", expand = ggplot2::expansion(mult = c(.01, .01))) +
  ggplot2::coord_cartesian(ylim = ylim) +
  ggplot2::labs(title = "(a) Data and issued ensemble", subtitle = "26 Nov 2022–22 Jan 2023; origin 25 Dec", x = "Date", y = "log(1 + flow)") + base_theme +
  ggplot2::guides(colour = ggplot2::guide_legend(nrow = 2, byrow = TRUE,
    override.aes = list(alpha = 1, linetype = c(1, 1, 2, 1), shape = c(16, 1, NA, NA), linewidth = c(.22, .22, .28, .18))))
blue <- c("0.05" = "#214E75", "0.20" = "#4F7EA3", "0.35" = "#83A4BD", "0.50" = "#214E75",
          "0.65" = "#83A4BD", "0.80" = "#4F7EA3", "0.95" = "#214E75")
lines <- stats::setNames(c("22", "22", "22", "solid", "solid", "solid", "solid"), names(blue))
q$probability <- factor(sprintf("%.2f", q$quantile_level), levels = names(blue))
model_panel <- function(family, heading, show_key) {
  block <- q[q$family == family, ]
  p <- ggplot2::ggplot(block, ggplot2::aes(target_date, qhat, colour = probability, linetype = probability)) +
    ggplot2::geom_line(linewidth = .17) +
    ggplot2::geom_line(data = block[block$quantile_level == .50, ], linewidth = .35) +
    ggplot2::geom_line(data = future_usgs, ggplot2::aes(target_date, value), inherit.aes = FALSE, colour = "#8B1A1A", linewidth = .22) +
    ggplot2::geom_point(data = future_usgs, ggplot2::aes(target_date, value), inherit.aes = FALSE, colour = "#8B1A1A", shape = 1, size = 1.3, stroke = .5) +
    ggplot2::scale_colour_manual(values = blue, drop = FALSE) + ggplot2::scale_linetype_manual(values = lines, drop = FALSE) +
    ggplot2::scale_x_date(date_breaks = "1 week", date_labels = "%d %b", expand = ggplot2::expansion(mult = c(.01, .01))) +
    ggplot2::coord_cartesian(ylim = ylim) +
    ggplot2::labs(title = heading, subtitle = "26 Dec 2022–22 Jan 2023; held-out USGS shown by open points", x = "Date", y = "log(1 + flow)") +
    base_theme + ggplot2::guides(colour = ggplot2::guide_legend(nrow = 1, title = "Quantile"), linetype = ggplot2::guide_legend(nrow = 1, title = "Quantile"))
  if (!show_key) p <- p + ggplot2::theme(legend.position = "none")
  p
}
p_al <- model_panel("Independent AL", "(b) Independent AL", FALSE)
p_ridge <- model_panel("Normal Ridge", "(c) Normal Ridge", TRUE)
path <- "figures/glofas_application/glofas_search3_part4_three_panel_review.pdf"
grDevices::cairo_pdf(path, width = 6.5, height = 6.6, family = "sans", bg = "white")
grid::grid.newpage()
grid::pushViewport(grid::viewport(layout = grid::grid.layout(3, 1, heights = c(2.55, 2.05, 2.40))))
for (i in 1:3) print(list(p_data, p_al, p_ridge)[[i]], vp = grid::viewport(layout.pos.row = i, layout.pos.col = 1))
invisible(grDevices::dev.off())
register(path)
# Remove only the internal status column from a presentation derivative.
# Frozen status-bearing scientific table and all numeric values are retained.
scores <- read_table("glofas_search3_part1234_final_20261007_part4_scores.csv")
scores <- scores[order(scores$descriptive_rank), ]
stopifnot(nrow(scores) == 7L, all(scores$n_scored_horizons == 28L))
table_rows <- sprintf("%s & %.4f & %.4f & %.3f & %.2f\\%% \\\\",
  scores$family, scores$mean_check_loss, scores$crps_grid_log1p, scores$coverage90,
  100 * scores$crps_reduction_vs_raw)
# Use native table typography; no resizebox reduction of ordinary labels.
table_path <- "tables/glofas_search3_part4_main_scores_review.tex"
writeLines(c("% Presentation derivative; all seven frozen rows and rounding retained.",
  "\\begin{tabular*}{\\linewidth}{@{\\extracolsep{\\fill}}lrrrr@{}}", "\\toprule",
  "Model & \\shortstack{Mean check\\\\loss} & \\shortstack{Grid\\\\aCRPS} & \\shortstack{Central 90\\%\\\\coverage} & \\shortstack{Reduction\\\\vs raw} \\\\",
  "\\midrule", table_rows, "\\bottomrule", "\\end{tabular*}"), table_path)
register(table_path)
# Keep original scientific wrappers byte-identical; publish new wrappers with
# their stable figure labels and caption estimator definitions preserved.
wrapper_sources <- sources[11:15]
wrapper_outputs <- c("tables/qdesn_pro_review_mcmc_forecast_figures.tex",
  "tables/qdesn_pro_review_mcmc_fit_figure.tex", "tables/qdesn_pro_review_vb_fit_figure.tex",
  "tables/joint_qdesn_pro_review_forecast_figure.tex", "tables/joint_qdesn_pro_review_fit_figure.tex")
old_pdf <- c("qdesn_validation_500obs_v14_mcmc_fit_rmse_intervals.pdf",
  "qdesn_validation_500obs_v14_mcmc_forecast_mae_intervals.pdf",
  "qdesn_validation_500obs_v14_mcmc_forecast_check_loss_intervals.pdf",
  "qdesn_validation_500obs_v14_vb_fit_rmse_intervals.pdf",
  "joint_qdesn_pure_desn_v1_forecast_dgp_acrps.pdf", "joint_qdesn_pure_desn_v1_fit_oracle_rmse.pdf")
new_pdf <- c("qdesn_pro_review_mcmc_fit_rmse.pdf", "qdesn_pro_review_mcmc_forecast_mae.pdf",
  "qdesn_pro_review_mcmc_forecast_check_loss.pdf", "qdesn_pro_review_vb_fit_rmse.pdf",
  "joint_qdesn_pro_review_forecast_dgp_acrps.pdf", "joint_qdesn_pro_review_fit_oracle_rmse.pdf")
for (i in seq_along(wrapper_sources)) {
  text <- readLines(wrapper_sources[[i]], warn = FALSE)
  for (j in seq_along(old_pdf)) text <- gsub(old_pdf[[j]], new_pdf[[j]], text, fixed = TRUE)
  writeLines(text, wrapper_outputs[[i]])
  register(wrapper_outputs[[i]])
}
stopifnot(identical(source_hashes, stats::setNames(vapply(sources, sha, character(1)), sources)))
manifest <- list(schema = "qdesn-pro-review-presentation-v1", source_script = "scripts/build_qdesn_pro_review_presentation.R",
  script_sha256 = sha(script), shared_style_sha256 = sha("scripts/qdesn_evaluation_figure_style.R"),
  purpose = "Presentation only; unchanged scientific estimators and summaries", sources = as.list(source_hashes),
  simulation_minimum_native_ordinary_label_pt = 10.4,
  glofas_minimum_native_ordinary_label_pt = 9.8, final_main_insertion_width = "0.94 textwidth",
  glofas_history_rows = 30L, glofas_ensemble_rows = 1428L, glofas_members = 51L,
  glofas_model_quantile_rows = 392L, glofas_shared_y_limits = ylim, credible_ribbons = FALSE,
  authentic_raw_quantile_reconstruction = "R quantile(type=8), all 28 dates, maximum error < 1e-12",
  outputs = lapply(output_paths, function(p) list(file = p, sha256 = sha(p))))
jsonlite::write_json(manifest, "tables/qdesn_pro_review_presentation_manifest.json", pretty = TRUE, auto_unbox = TRUE, digits = 17)
cat("QDESN_PRO_PRESENTATION_PASS simulation=6 glofas_panels=3 authentic_members=51 no_rescoring\n")
