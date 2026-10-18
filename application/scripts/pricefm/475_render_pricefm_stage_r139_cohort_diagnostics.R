#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("usage: 475_render_pricefm_stage_r139_cohort_diagnostics.R OUTPUT PRIMARY_OPERATOR")
}

output_dir <- normalizePath(args[[1L]], mustWork = TRUE)
primary_operator <- args[[2L]]
read_output <- function(name) {
  read.csv(file.path(output_dir, name), stringsAsFactors = FALSE, check.names = FALSE)
}

comparison <- read_output("region_comparison.csv")
horizon <- read_output("horizon_metrics.csv")
blocks <- read_output("horizon_block_metrics.csv")
summary <- read_output("report_summary.csv")[1L, ]
regions <- comparison$region

pdf(
  file.path(output_dir, "pricefm_stage_r139_cohort_diagnostics.pdf"),
  width = 11,
  height = 8.5,
  onefile = TRUE,
  useDingbats = FALSE
)
on.exit(dev.off(), add = TRUE)

palette <- c("#2364AA", "#D1495B", "#2A9D8F", "#6C757D")
values <- rbind(
  comparison$r137_AQL,
  comparison$qdesn_AQL,
  comparison$pricefm_AQL,
  comparison$operational_pricefm_AQL
)
rownames(values) <- c("R137 primary", "Authoritative QDESN", "Local PriceFM", "Operational PriceFM")

layout(matrix(c(1, 2), nrow = 2L), heights = c(2.0, 1.0))
par(mar = c(4.5, 5, 4.5, 1.2), family = "sans")
positions <- barplot(
  values,
  beside = TRUE,
  names.arg = regions,
  col = palette,
  border = NA,
  ylab = "Average quantile loss (lower is better)",
  main = "R137 four-region pilot: matched three-fold comparison",
  ylim = c(0, max(values) * 1.2),
  las = 1
)
grid(nx = NA, ny = NULL, col = "#E6E9ED", lty = 1)
text(positions, values, labels = sprintf("%.2f", values), pos = 3, cex = 0.68)
legend("topright", legend = rownames(values), fill = palette, border = NA, bty = "n", ncol = 2, cex = 0.82)
mtext(sprintf("Decision: %s", summary$decision), side = 3, line = 2.7, adj = 0, cex = 0.82)

par(mar = c(0.5, 0.8, 0.5, 0.8))
plot.new()
table_rows <- rbind(
  data.frame(
    Region = comparison$region,
    R137 = sprintf("%.3f", comparison$r137_AQL),
    vs_QDESN = sprintf("%+.1f%%", comparison$delta_vs_qdesn_pct),
    vs_local_PriceFM = sprintf("%+.1f%%", comparison$delta_vs_local_pricefm_pct),
    vs_operational_PriceFM = sprintf("%+.1f%%", comparison$delta_vs_operational_pricefm_pct)
  ),
  data.frame(
    Region = "Equal-region mean",
    R137 = sprintf("%.3f", summary$cohort_AQL),
    vs_QDESN = sprintf("%+.1f%%", summary$delta_vs_qdesn_pct),
    vs_local_PriceFM = sprintf("%+.1f%%", summary$delta_vs_local_pricefm_pct),
    vs_operational_PriceFM = sprintf("%+.1f%%", summary$delta_vs_operational_pricefm_pct)
  )
)
headers <- c("Region", "R137", "vs QDESN", "vs local PriceFM", "vs operational PriceFM")
x <- c(0.08, 0.32, 0.49, 0.69, 0.9)
y <- seq(0.88, 0.1, length.out = nrow(table_rows) + 1L)
rect(0.01, y[1L] - 0.055, 0.99, y[1L] + 0.06, col = "#EAF2F8", border = NA)
text(x, y[1L], headers, font = 2, cex = 0.86)
for (i in seq_len(nrow(table_rows))) {
  if (i == nrow(table_rows)) {
    rect(0.01, y[i + 1L] - 0.055, 0.99, y[i + 1L] + 0.055, col = "#F3F5F7", border = NA)
  }
  text(x, y[i + 1L], as.character(table_rows[i, ]), cex = 0.83)
}
text(0.01, 0.01, "Negative percentages indicate lower AQL than the comparator.", adj = c(0, 0), cex = 0.73, col = "#444444")

layout(matrix(seq_len(4L), nrow = 2L, byrow = TRUE))
primary_horizon <- horizon[horizon$operator == primary_operator, ]
for (region in regions) {
  selected <- primary_horizon[primary_horizon$region == region, ]
  mean_by_horizon <- aggregate(AQL ~ horizon, data = selected, FUN = mean)
  smooth <- stats::filter(mean_by_horizon$AQL, rep(1 / 6, 6), sides = 2)
  par(mar = c(4, 4.5, 3, 1), family = "sans")
  plot(
    mean_by_horizon$horizon,
    mean_by_horizon$AQL,
    type = "l",
    col = "#9AC0DC",
    lwd = 1,
    xlab = "Forecast horizon (hours)",
    ylab = "AQL",
    main = region,
    las = 1
  )
  grid(col = "#E6E9ED")
  lines(mean_by_horizon$horizon, smooth, col = "#2364AA", lwd = 2.5)
}
mtext("Hourly loss and six-hour moving mean; folds averaged equally", outer = TRUE, side = 3, line = -1.5, cex = 0.9)

draw_heatmap <- function(matrix_value, title, formatter, colors, limits = range(matrix_value)) {
  nr <- nrow(matrix_value)
  nc <- ncol(matrix_value)
  plot(c(0, nc), c(0, nr), type = "n", axes = FALSE, xlab = "", ylab = "", main = title)
  scaled <- (matrix_value - limits[1L]) / max(diff(limits), 1e-12)
  scaled <- pmin(1, pmax(0, scaled))
  color_index <- matrix(
    1L + floor(scaled * (length(colors) - 1L)),
    nrow = nr,
    ncol = nc
  )
  for (i in seq_len(nr)) {
    for (j in seq_len(nc)) {
      y0 <- nr - i
      rect(j - 1, y0, j, y0 + 1, col = colors[color_index[i, j]], border = "white")
      text(j - 0.5, y0 + 0.5, formatter(matrix_value[i, j]), cex = 0.88)
    }
  }
  axis(1, at = seq_len(nc) - 0.5, labels = c("1-24", "25-48", "49-72", "73-96"), tick = FALSE)
  axis(2, at = rev(seq_len(nr) - 0.5), labels = rownames(matrix_value), tick = FALSE, las = 1)
  box(col = "#D8DEE4")
}

primary_blocks <- blocks[blocks$operator == primary_operator, ]
block_names <- c("h01_24", "h25_48", "h49_72", "h73_96")
aql_matrix <- coverage_matrix <- matrix(NA_real_, nrow = length(regions), ncol = length(block_names), dimnames = list(regions, block_names))
for (i in seq_along(regions)) {
  for (j in seq_along(block_names)) {
    selected <- primary_blocks[
      primary_blocks$region == regions[i] & primary_blocks$horizon_block == block_names[j],
    ]
    aql_matrix[i, j] <- mean(selected$AQL)
    coverage_matrix[i, j] <- mean(selected$coverage_80)
  }
}
layout(matrix(c(1, 2), nrow = 1L))
par(mar = c(5, 5, 4, 1), family = "sans")
draw_heatmap(aql_matrix, "AQL by 24-hour block", function(x) sprintf("%.2f", x), colorRampPalette(c("#F7FBFF", "#2171B5"))(100))
draw_heatmap(coverage_matrix, "80% interval coverage", function(x) sprintf("%.0f%%", 100 * x), colorRampPalette(c("#D73027", "#FFF2B2", "#1A9850"))(100), c(0, 1))

layout(1)
par(mar = c(1, 1, 1, 1), family = "sans")
plot.new()
paragraph <- function(y, heading, text_value) {
  text(0.04, y, heading, adj = c(0, 1), font = 2, cex = 1.15)
  wrapped <- paste(strwrap(text_value, width = 118), collapse = "\n")
  text(0.04, y - 0.045, wrapped, adj = c(0, 1), cex = 0.92)
}
text(0.04, 0.97, "Interpretation", adj = c(0, 1), font = 2, cex = 1.45)
paragraph(
  0.88,
  "Primary result",
  sprintf(
    "Equal-region AQL %.3f versus authoritative QDESN %.3f (%+.1f%%). R137 wins in %d/4 regions and %d/%d folds.",
    summary$cohort_AQL, summary$qdesn_AQL, summary$delta_vs_qdesn_pct,
    summary$region_wins_vs_qdesn, summary$fold_wins_vs_qdesn, summary$fold_count
  )
)
paragraph(
  0.69,
  "What this supports",
  "The family is promising enough to freeze and evaluate prospectively across the remaining regions if the objective is to improve on the current QDESN authority."
)
paragraph(
  0.53,
  "What this does not support",
  "These folds have been inspected during development. They do not establish a confirmatory all-region result, and R139 does not promote or modify any authority or article result."
)
paragraph(
  0.36,
  "R138/DK_1 context",
  sprintf(
    "The separate targeted %s follow-up obtained AQL %.3f versus its authority %.3f. It is excluded from the R137 cohort mean and argues against more test-guided DK_1 tuning.",
    summary$negative_control_region, summary$negative_control_AQL, summary$negative_control_qdesn_AQL
  )
)
paragraph(
  0.18,
  "Remaining limitation",
  "The frozen packets contain operator forecasts but not raw Normal-RHS driver paths. Horizon loss is diagnosed exactly; raw driver-path error cannot be reconstructed without a later scoring-only replay."
)
