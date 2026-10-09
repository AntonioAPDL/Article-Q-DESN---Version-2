#!/usr/bin/env Rscript
# Deterministic presentation derivatives of the validated joint v2 summaries.
# No inference code, model fitting, score recalculation, or quantile projection.
options(stringsAsFactors = FALSE, digits = 17)
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
stopifnot(length(script_arg) == 1L)
script <- normalizePath(sub("^--file=", "", script_arg))
root <- normalizePath(file.path(dirname(script), ".."))
setwd(root)
stopifnot(requireNamespace("ggplot2", quietly = TRUE))
source("scripts/qdesn_evaluation_figure_style.R")

prefix <- "joint_qdesn_pure_desn_v2_"
score_path <- file.path("tables", paste0(prefix, "forecast_score_summary.csv"))
fit_path <- file.path("tables", paste0(prefix, "fit_oracle_diagnostics.csv"))
sha <- function(path) strsplit(system2("sha256sum", shQuote(path), stdout = TRUE), " +")[[1L]][1L]
source_paths <- c(score_path, fit_path, "scripts/qdesn_evaluation_figure_style.R")
source_hashes <- stats::setNames(vapply(source_paths, sha, character(1)), source_paths)
score <- read.csv(score_path, check.names = FALSE)
fit <- read.csv(fit_path, check.names = FALSE)
score <- score[score$inference_method == "mcmc", , drop = FALSE]
fit <- fit[fit$inference_method == "mcmc", , drop = FALSE]
stopifnot(nrow(score) == 32L, nrow(fit) == 32L,
  !anyDuplicated(score$model_cell_id), !anyDuplicated(fit$model_cell_id),
  setequal(score$model_cell_id, fit$model_cell_id))
fit <- fit[match(score$model_cell_id, fit$model_cell_id), , drop = FALSE]
stopifnot(identical(score$model_cell_id, fit$model_cell_id),
  identical(score$scenario_id, fit$scenario_id),
  setequal(score$scenario_id, qdesn_scenario_order),
  all(table(score$scenario_id) == 4L),
  all(is.finite(score$posterior_score_mean)),
  all(is.finite(score$posterior_score_q025)),
  all(is.finite(score$posterior_score_q975)),
  all(score$posterior_score_q025 <= score$posterior_score_q975),
  all(is.finite(fit$fit_oracle_rmse)), all(fit$fit_oracle_rmse >= 0),
  all(score$canonical_contract_crossing_pairs == 0L),
  all(fit$fit_contract_crossing_pairs == 0L))

# The annotations summarize the raw posterior-mean grid, not pooled draw grids.
# Its denominator is 990 forecast rows x 6 adjacent pairs, or 500 fit rows x 6.
forecast_opportunities <- 33L * 30L * (7L - 1L)
fit_opportunities <- 500L * (7L - 1L)
valid_crossing <- function(x, denominator) {
  all(is.finite(x)) && all(x >= 0) && all(x <= denominator) && all(x == floor(x))
}
stopifnot(valid_crossing(score$canonical_raw_crossing_pairs, forecast_opportunities),
  valid_crossing(fit$fit_raw_crossing_pairs, fit_opportunities))
model_style <- stats::setNames(qdesn_joint_model_order,
  sub("_vb$", "_mcmc", qdesn_joint_model_order))
style_ids <- unname(model_style[score$model_id])
stopifnot(!anyNA(style_ids),
  setequal(style_ids, qdesn_joint_model_order),
  all(score$likelihood_family %in% names(qdesn_figure_palette)))
joint_data <- data.frame(
  scenario_id = score$scenario_id, source_model_id = style_ids,
  likelihood_family = score$likelihood_family,
  mean = score$posterior_score_mean,
  lo = score$posterior_score_q025, hi = score$posterior_score_q975,
  crossing = sprintf("%.2f%%", 100 * score$canonical_raw_crossing_pairs /
    forecast_opportunities))

readable_theme <- ggplot2::theme(
  text = ggplot2::element_text(size = 10.4),
  strip.text = ggplot2::element_text(face = "bold", size = 10.4, lineheight = .98),
  axis.text.x = ggplot2::element_text(size = 10.4),
  axis.text.y = ggplot2::element_text(size = 10.4, colour = "#242424"),
  axis.title.x = ggplot2::element_text(size = 10.4),
  plot.margin = ggplot2::margin(7, 16, 7, 7),
  panel.spacing = grid::unit(1.0, "lines"))
joint_plot <- function(data, xlab, point_only = FALSE) {
  p <- qdesn_joint_interval_plot(data, xlab) + readable_theme
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
forecast_pdf <- file.path("figures", "joint_qdesn_simulation",
  paste0(prefix, "forecast_dgp_acrps.pdf"))
fit_pdf <- file.path("figures", "joint_qdesn_simulation",
  paste0(prefix, "fit_oracle_rmse.pdf"))
qdesn_save_vector_pdf(forecast_pdf,
  joint_plot(joint_data, "DGP-integrated aCRPS"), 7.0, 8.1)
normalize_pdf_date(forecast_pdf)
fit_data <- joint_data
fit_data$mean <- fit_data$lo <- fit_data$hi <- fit$fit_oracle_rmse
fit_data$crossing <- sprintf("%.2f%%", 100 * fit$fit_raw_crossing_pairs /
  fit_opportunities)
qdesn_save_vector_pdf(fit_pdf,
  joint_plot(fit_data, "Fitting-sample quantile-path RMSE", TRUE), 7.0, 8.1)
normalize_pdf_date(fit_pdf)
stopifnot(identical(source_hashes,
  stats::setNames(vapply(source_paths, sha, character(1)), source_paths)))
cat("JOINT_V2_FIGURES_PASS cells=32 scenario_panels=8 forecast_intervals=95_percent",
  "fit_point_rmse=TRUE canonical_score_marks=FALSE native_label_pt=10.4\n")
for (path in c(forecast_pdf, fit_pdf)) cat(path, sha(path), "\n")
