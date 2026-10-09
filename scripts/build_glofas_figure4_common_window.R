#!/usr/bin/env Rscript
# Display frozen fitted and forecast quantiles on a common date window.
# No inference modules, model fitting, scoring, or quantile projection are used.
options(stringsAsFactors = FALSE, digits = 17)
script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))
root <- normalizePath(file.path(dirname(script), ".."))
setwd(root)
stopifnot(requireNamespace("ggplot2", quietly = TRUE), requireNamespace("jsonlite", quietly = TRUE))
sha <- function(path) strsplit(system2("sha256sum", shQuote(path), stdout = TRUE), " +")[[1L]][1L]
read_table <- function(name) read.csv(file.path("tables", name), check.names = FALSE)
inputs <- c("tables/glofas_search3_part1234_final_20261007_source_quantiles.csv",
            "tables/glofas_search3_review_history_plot_inputs.csv",
            "tables/glofas_search3_review_ensemble_plot_inputs.csv",
            "tables/glofas_search3_review_truth_plot_inputs.csv",
            "tables/glofas_search3_review_plot_input_provenance.json",
            "tables/glofas_search3_part4_history_fitted_quantiles.csv",
            "tables/glofas_search3_part4_history_fitted_quantile_provenance.json")
source_hashes <- stats::setNames(vapply(inputs, sha, character(1)), inputs)
stopifnot(source_hashes[[inputs[[1L]]]] == "d4a6c18eac599c66e9e95edda01e98d9f14c8f6a8efc6dd2a54f16544ae7181a")

families <- c("Independent AL", "Normal Ridge")
probabilities <- c(.05, .20, .35, .50, .65, .80, .95)
origin <- as.Date("2022-12-25")
history_dates <- seq(as.Date("2022-11-26"), origin, by = "day")
forecast_dates <- seq(origin + 1L, as.Date("2023-01-22"), by = "day")
common_dates <- c(history_dates[[1L]], tail(forecast_dates, 1L))
tick_dates <- as.Date(c("2022-11-26", "2022-12-10", "2022-12-25", "2023-01-08", "2023-01-22"))
history <- read_table("glofas_search3_review_history_plot_inputs.csv")
ensemble <- read_table("glofas_search3_review_ensemble_plot_inputs.csv")
truth <- read_table("glofas_search3_review_truth_plot_inputs.csv")
fitted <- read_table("glofas_search3_part4_history_fitted_quantiles.csv")
q <- read_table("glofas_search3_part1234_final_20261007_source_quantiles.csv")
for (name in c("history", "ensemble", "truth", "fitted", "q")) {
  value <- get(name)
  value$target_date <- as.Date(value$target_date)
  assign(name, value)
}
ensemble$origin_date <- as.Date(ensemble$origin_date)
forecast <- q[q$part == "Part 4" & q$family %in% families, ]
stopifnot(nrow(history) == 30L,
          identical(as.numeric(history$target_date), as.numeric(history_dates)),
          nrow(truth) == 28L,
          identical(as.numeric(truth$target_date), as.numeric(forecast_dates)),
          nrow(ensemble) == 1428L, length(unique(ensemble$member)) == 51L,
          all(ensemble$origin_date == origin), nrow(fitted) == 420L, nrow(forecast) == 392L)
validate_grid <- function(data, dates) {
  stopifnot(setequal(data$family, families), all(is.finite(data$qhat)),
            !anyDuplicated(data[c("family", "target_date", "quantile_level")]))
  for (family in families) {
    block <- data[data$family == family, ]
    stopifnot(nrow(block) == length(dates) * length(probabilities),
              setequal(block$target_date, dates), setequal(block$quantile_level, probabilities))
    for (date in dates) stopifnot(setequal(block$quantile_level[block$target_date == date], probabilities))
  }
}
validate_grid(fitted, history_dates)
validate_grid(forecast, forecast_dates)
stopifnot(max(abs(forecast$y_reference - truth$y_transformed[match(forecast$target_date, truth$target_date)])) < 1e-12)
if ("y_reference" %in% names(fitted)) {
  stopifnot(max(abs(fitted$y_reference - history$y_transformed[match(fitted$target_date, history$target_date)])) < 1e-12)
}
for (h in 1:28) {
  member_values <- ensemble$g_transformed[ensemble$horizon == h]
  retained <- q[q$part == "Part 4" & q$family == "Raw GloFAS" & q$horizon == h, ]
  retained <- retained[order(retained$quantile_level), ]
  stopifnot(length(member_values) == 51L, nrow(retained) == 7L,
    max(abs(stats::quantile(member_values, probabilities, type = 8, names = FALSE) - retained$qhat)) < 1e-12)
}
values <- c(history$y_transformed, history$g_transformed, ensemble$g_transformed,
            truth$y_transformed, fitted$qhat, forecast$qhat)
stopifnot(all(is.finite(values)))
ylim <- c(min(0, floor(min(values))), max(6, ceiling(max(values))))
combined <- rbind(
  data.frame(family = fitted$family, target_date = fitted$target_date,
             quantile_level = fitted$quantile_level, qhat = fitted$qhat, role = "fitted"),
  data.frame(family = forecast$family, target_date = forecast$target_date,
             quantile_level = forecast$quantile_level, qhat = forecast$qhat, role = "forecast"))
combined <- combined[order(match(combined$family, families), combined$quantile_level, combined$target_date), ]
blue <- c("0.05" = "#214E75", "0.20" = "#4F7EA3", "0.35" = "#83A4BD", "0.50" = "#214E75",
          "0.65" = "#83A4BD", "0.80" = "#4F7EA3", "0.95" = "#214E75")
lines <- stats::setNames(c("22", "22", "22", "solid", "solid", "solid", "solid"), names(blue))
combined$probability <- factor(sprintf("%.2f", combined$quantile_level), levels = names(blue))
data_colors <- c("Historical USGS" = "#1B5E20", "Held-out USGS" = "#8B1A1A",
                 "Retrospective GloFAS" = "#C26A00", "Issued GloFAS ensemble" = "#C26A00")
historical_usgs <- data.frame(target_date = history$target_date, value = history$y_transformed, series = "Historical USGS")
historical_glofas <- data.frame(target_date = history$target_date, value = history$g_transformed, series = "Retrospective GloFAS")
future_usgs <- data.frame(target_date = truth$target_date, value = truth$y_transformed, series = "Held-out USGS")
base_theme <- ggplot2::theme_bw(base_size = 10.4, base_family = "sans") + ggplot2::theme(
  panel.grid.minor = ggplot2::element_blank(), panel.grid.major.x = ggplot2::element_blank(),
  panel.grid.major.y = ggplot2::element_line(colour = "#EBEBEB", linewidth = .2),
  axis.title = ggplot2::element_text(size = 10.4), axis.text = ggplot2::element_text(size = 10.4, colour = "#242424"),
  plot.title = ggplot2::element_text(size = 11, face = "bold"), plot.subtitle = ggplot2::element_text(size = 10.4),
  legend.position = "bottom", legend.title = ggplot2::element_blank(), legend.text = ggplot2::element_text(size = 9.8),
  legend.key.height = grid::unit(9, "pt"), legend.key.width = grid::unit(16, "pt"),
  legend.margin = ggplot2::margin(0, 0, 0, 0), plot.margin = ggplot2::margin(5, 22, 3, 5))
common_axes <- function(p) p +
  ggplot2::scale_x_date(limits = common_dates, breaks = tick_dates, date_labels = "%d %b", expand = c(0, 0)) +
  ggplot2::coord_cartesian(ylim = ylim, expand = FALSE, clip = "off") +
  ggplot2::geom_vline(xintercept = origin, colour = "#686868", linewidth = .22, linetype = "22") +
  base_theme
observation_layers <- function() list(
  ggplot2::geom_line(data = historical_usgs, ggplot2::aes(target_date, value), inherit.aes = FALSE, colour = "#1B5E20", linewidth = .22),
  ggplot2::geom_point(data = historical_usgs, ggplot2::aes(target_date, value), inherit.aes = FALSE, colour = "#1B5E20", shape = 16, size = 1.05),
  ggplot2::geom_line(data = future_usgs, ggplot2::aes(target_date, value), inherit.aes = FALSE, colour = "#8B1A1A", linewidth = .22),
  ggplot2::geom_point(data = future_usgs, ggplot2::aes(target_date, value), inherit.aes = FALSE, colour = "#8B1A1A", shape = 1, size = 1.3, stroke = .5))
p_data <- common_axes(ggplot2::ggplot() +
  ggplot2::geom_line(data = ensemble, ggplot2::aes(target_date, g_transformed, group = member, colour = "Issued GloFAS ensemble"), linewidth = .13, alpha = .13) +
  ggplot2::geom_line(data = historical_glofas, ggplot2::aes(target_date, value, colour = series), linewidth = .28, linetype = "22") +
  ggplot2::geom_line(data = historical_usgs, ggplot2::aes(target_date, value, colour = series), linewidth = .22) +
  ggplot2::geom_point(data = historical_usgs, ggplot2::aes(target_date, value, colour = series), shape = 16, size = 1.05) +
  ggplot2::geom_line(data = future_usgs, ggplot2::aes(target_date, value, colour = series), linewidth = .22) +
  ggplot2::geom_point(data = future_usgs, ggplot2::aes(target_date, value, colour = series), shape = 1, size = 1.3, stroke = .5) +
  ggplot2::scale_colour_manual(values = data_colors, breaks = names(data_colors)) +
  ggplot2::labs(title = "(a) Data and issued ensemble", subtitle = "26 Nov 2022–22 Jan 2023; origin 25 Dec", x = "Date", y = "log(1 + flow)") +
  ggplot2::guides(colour = ggplot2::guide_legend(nrow = 2, byrow = TRUE,
    override.aes = list(alpha = 1, linetype = c(1, 1, 2, 1), shape = c(16, 1, NA, NA), linewidth = c(.22, .22, .28, .18)))))
model_panel <- function(family, heading, show_key) {
  block <- combined[combined$family == family, ]
  p <- common_axes(ggplot2::ggplot(block,
      ggplot2::aes(target_date, qhat, colour = probability, linetype = probability, group = interaction(probability, role))) +
    ggplot2::geom_line(linewidth = .17) +
    ggplot2::geom_line(data = block[block$quantile_level == .50, ], linewidth = .35) +
    observation_layers() +
    ggplot2::scale_colour_manual(values = blue, drop = FALSE) +
    ggplot2::scale_linetype_manual(values = lines, drop = FALSE) +
    ggplot2::labs(title = heading, subtitle = "Fitted quantiles before cutoff; forecasts after cutoff", x = "Date", y = "log(1 + flow)") +
    ggplot2::guides(colour = ggplot2::guide_legend(nrow = 1, title = "Quantile"),
                    linetype = ggplot2::guide_legend(nrow = 1, title = "Quantile")))
  if (!show_key) p <- p + ggplot2::theme(legend.position = "none")
  p
}
plots <- list(p_data, model_panel("Independent AL", "(b) Independent AL", FALSE),
              model_panel("Normal Ridge", "(c) Normal Ridge", TRUE))
builds <- lapply(plots, ggplot2::ggplot_build)
for (built in builds) {
  panel <- built$layout$panel_params[[1L]]
  stopifnot(identical(as.numeric(panel$x.range), as.numeric(common_dates)),
            identical(as.numeric(panel$y.range), ylim),
            identical(as.numeric(panel$x$breaks), as.numeric(tick_dates)))
}
figure <- "figures/glofas_application/glofas_search3_part4_common_window_three_panel_review.pdf"
alias <- "tables/glofas_figure4_common_window_outputs.tex"
# Establish the intended font metrics before gtable construction; otherwise
# grid can silently open an unrelated default Rplots.pdf device.
grDevices::cairo_pdf(figure, width = 6.5, height = 6.625, family = "sans", bg = "white")
grid::grid.newpage()
grobs <- lapply(plots, ggplot2::ggplotGrob)
stopifnot(length(unique(vapply(grobs, function(g) length(g$widths), integer(1)))) == 1L)
shared_widths <- do.call(grid::unit.pmax, lapply(grobs, function(g) g$widths))
for (i in seq_along(grobs)) {
  grobs[[i]]$widths <- shared_widths
  grobs[[i]]$layout$name[grobs[[i]]$layout$name == "panel"] <- paste0("panel_common_window_", i)
}
grid::pushViewport(grid::viewport(name = "common_window_layout", layout = grid::grid.layout(3, 1, heights = c(2.55, 2.05, 2.40))))
for (i in seq_along(grobs)) {
  grid::pushViewport(grid::viewport(name = paste0("common_window_row_", i), layout.pos.row = i, layout.pos.col = 1))
  grid::grid.draw(grobs[[i]])
  grid::upViewport()
}
grid::upViewport()
grid::grid.force()
viewport_names <- grid::grid.ls(viewports = TRUE, grobs = FALSE, print = FALSE)$name
panel_positions <- lapply(seq_along(grobs), function(i) {
  name <- grep(paste0("^panel_common_window_", i, "[.]"), viewport_names, value = TRUE)
  stopifnot(length(name) == 1L)
  grid::seekViewport(name)
  loc <- grid::deviceLoc(x = grid::unit(c(0, 1), "npc"), y = grid::unit(0, "npc"), valueOnly = TRUE)
  grid::upViewport(0)
  list(panel = i, x_left_mm = loc$x[[1L]] * 25.4, x_right_mm = loc$x[[2L]] * 25.4)
})
stopifnot(diff(range(vapply(panel_positions, function(p) p$x_left_mm, numeric(1)))) < 1e-8,
          diff(range(vapply(panel_positions, function(p) p$x_right_mm, numeric(1)))) < 1e-8)
invisible(grDevices::dev.off())
# Cairo has one fixed-width creation date. Normalize it without altering content.
bytes <- readBin(figure, what = "raw", n = file.info(figure)$size)
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
writeBin(bytes, figure)
writeLines(c("% Presentation-only common-window Figure 4; frozen forecast values unchanged.",
  paste0("\\renewcommand{\\GlofasApplicationCurrentForecastWindowFigure}{", figure, "}")), alias)
stopifnot(identical(source_hashes, stats::setNames(vapply(inputs, sha, character(1)), inputs)))
manifest <- list(schema = "glofas-figure4-common-window-v1", source_script = "scripts/build_glofas_figure4_common_window.R",
  script_sha256 = sha(script), purpose = "Presentation only; authentic historical fitted quantiles and unchanged retained forecasts",
  sources = as.list(source_hashes), families = families, quantile_levels = probabilities, origin_date = as.character(origin),
  history_dates = as.character(range(history_dates)), forecast_dates = as.character(range(forecast_dates)),
  common_x_limits = as.character(common_dates), common_x_tick_dates = as.character(tick_dates),
  common_y_limits = ylim, historical_days = 30L, forecast_days = 28L,
  historical_fitted_quantile_rows = 420L, unchanged_forecast_quantile_rows = 392L,
  total_model_quantile_rows = 812L, historical_usgs_rows = 30L, heldout_usgs_rows = 28L,
  issued_members = 51L, issued_member_rows = 1428L, historical_usgs_repeated_panels = 3L,
  heldout_usgs_repeated_panels = 3L, plot_panel_geometry = panel_positions,
  width_alignment = "gtable widths aligned with grid::unit.pmax; panel edges measured on PDF device",
  figure_width_inches = 6.5, figure_height_inches = 6.625, minimum_native_ordinary_label_pt = 9.8,
  main_insertion_width = "0.94 textwidth", effective_ordinary_label_pt_at_6p5in_textwidth = 9.8 * .94,
  quantile_linewidth_mm = .17, median_linewidth_mm = .35, credible_ribbons = FALSE,
  smoothing = FALSE, quantile_projection = FALSE, rescoring = FALSE, fitting = FALSE,
  historical_quantile_interpretation = "Fitted conditional quantile estimates from the frozen Part 4 fits; not coefficient credible intervals",
  forecast_quantile_interpretation = "Retained Part 4 forecast quantile summaries; ordinates unchanged from the frozen public source",
  forecast_summary_by_family = list(
    independent_al = "Retained posterior means of q_y_draw at each fitted level",
    normal_ridge = "Retained empirical quantiles of latent_y_draw, quantile type 8"),
  outputs = lapply(c(figure, alias), function(p) list(file = p, sha256 = sha(p))))
jsonlite::write_json(manifest, "tables/glofas_figure4_common_window_manifest.json", pretty = TRUE, auto_unbox = TRUE, digits = 17)
cat("GLOFAS_FIGURE4_COMMON_WINDOW_PASS panels=3 historical_quantiles=420 unchanged_forecast_quantiles=392 aligned_panel_widths=TRUE no_fit_or_score_change\n")
