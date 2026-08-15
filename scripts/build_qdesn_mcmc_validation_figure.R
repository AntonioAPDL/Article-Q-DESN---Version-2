#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, digits = 17)

script_path <- {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg)) {
    normalizePath(sub("^--file=", "", file_arg[[1L]]), winslash = "/", mustWork = TRUE)
  } else {
    normalizePath(
      "scripts/build_qdesn_mcmc_validation_figure.R",
      winslash = "/",
      mustWork = TRUE
    )
  }
}
repo_root <- normalizePath(
  file.path(dirname(script_path), ".."),
  winslash = "/",
  mustWork = TRUE
)

relative_to_repo <- function(path) {
  normalized <- normalizePath(path, winslash = "/", mustWork = TRUE)
  prefix <- paste0(repo_root, "/")
  if (!startsWith(normalized, prefix)) {
    stop("Article artifact path escapes the repository root.", call. = FALSE)
  }
  substring(normalized, nchar(prefix) + 1L)
}

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) {
  index <- which(args == flag)
  if (!length(index) || index[[1L]] >= length(args)) return(default)
  args[[index[[1L]] + 1L]]
}

validation_root <- normalizePath(
  get_arg(
    "--validation-root",
    "/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0"
  ),
  winslash = "/",
  mustWork = TRUE
)
promotion_id <- "qdesn_dqlm_500obs_mcmc_metric_envelope_20260804"
source_csv <- normalizePath(
  get_arg(
    "--source-csv",
    file.path(
      validation_root,
      "validation",
      "fitforecast_v2",
      "promotions",
      promotion_id,
      paste0(promotion_id, "_article_envelope.csv")
    )
  ),
  winslash = "/",
  mustWork = TRUE
)
article_manifest <- normalizePath(
  file.path(
    repo_root,
    "tables",
    "qdesn_validation_tt500_mcmc_current_best_manifest.txt"
  ),
  winslash = "/",
  mustWork = TRUE
)

output_pdf <- get_arg(
  "--output-pdf",
  file.path(
    repo_root,
    "figures",
    "independent_simulation",
    "qdesn_mcmc_metric_envelope_heatmap.pdf"
  )
)
output_data <- get_arg(
  "--output-data",
  file.path(
    repo_root,
    "tables",
    "qdesn_validation_mcmc_figure_data.csv"
  )
)
output_manifest <- get_arg(
  "--output-manifest",
  file.path(
    repo_root,
    "tables",
    "qdesn_validation_mcmc_figure_manifest.txt"
  )
)

for (package in c("ggplot2", "scales")) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop(sprintf("Required package is unavailable: %s", package), call. = FALSE)
  }
}

sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
manifest_value <- function(lines, key) {
  hits <- grep(paste0("^", key, ": "), lines, value = TRUE)
  if (length(hits) != 1L) {
    stop(sprintf("Expected exactly one '%s' entry in article manifest.", key), call. = FALSE)
  }
  sub(paste0("^", key, ": "), "", hits[[1L]])
}

manifest_lines <- readLines(article_manifest, warn = FALSE)
expected_source <- normalizePath(
  manifest_value(manifest_lines, "source_csv"),
  winslash = "/",
  mustWork = TRUE
)
if (!identical(source_csv, expected_source)) {
  stop("Requested source CSV differs from the frozen article source.", call. = FALSE)
}
if (!identical(sha256(source_csv), manifest_value(manifest_lines, "source_csv_sha256"))) {
  stop("Authoritative source CSV hash does not match the article manifest.", call. = FALSE)
}

source <- read.csv(source_csv, check.names = FALSE, stringsAsFactors = FALSE)
required <- c(
  "model_variant",
  "family",
  "tau",
  "fit_size",
  "comparison_eligible",
  "status",
  "signoff_grade",
  "metric_source_mixed",
  "fit_qtrue_rmse",
  "forecast_qtrue_mae_H1000",
  "forecast_check_loss_H1000",
  "fit_source_candidate_id",
  "fit_source_run_tag",
  "fit_source_signoff_grade",
  "fit_source_path",
  "fit_source_sha256",
  "forecast_mae_source_candidate_id",
  "forecast_mae_source_run_tag",
  "forecast_mae_source_signoff_grade",
  "forecast_mae_source_path",
  "forecast_mae_source_sha256",
  "forecast_check_source_candidate_id",
  "forecast_check_source_run_tag",
  "forecast_check_source_signoff_grade",
  "forecast_check_source_path",
  "forecast_check_source_sha256",
  "source_promotion_id",
  "source_registry_hash_value"
)
missing <- setdiff(required, names(source))
if (length(missing)) {
  stop(
    sprintf("Authoritative source is missing columns: %s", paste(missing, collapse = ", ")),
    call. = FALSE
  )
}

models <- c(
  dqlm_c13_mcmc = "DQLM",
  exdqlm_c13_mcmc = "exDQLM",
  qdesn_al_rhs_ns = "Q-DESN AL-RHS",
  qdesn_exal_rhs_ns = "Q-DESN exAL-RHS"
)
families <- c(
  normal = "Gaussian",
  laplace = "Laplace",
  gausmix = "Gaussian mixture"
)
taus <- c(0.05, 0.25, 0.50)
metrics <- list(
  list(
    metric = "fit_rmse",
    label = "Fit RMSE",
    value = "fit_qtrue_rmse",
    candidate = "fit_source_candidate_id",
    run_tag = "fit_source_run_tag",
    signoff = "fit_source_signoff_grade",
    path = "fit_source_path",
    sha256 = "fit_source_sha256"
  ),
  list(
    metric = "forecast_mae",
    label = "Forecast MAE",
    value = "forecast_qtrue_mae_H1000",
    candidate = "forecast_mae_source_candidate_id",
    run_tag = "forecast_mae_source_run_tag",
    signoff = "forecast_mae_source_signoff_grade",
    path = "forecast_mae_source_path",
    sha256 = "forecast_mae_source_sha256"
  ),
  list(
    metric = "forecast_check",
    label = "Forecast check loss",
    value = "forecast_check_loss_H1000",
    candidate = "forecast_check_source_candidate_id",
    run_tag = "forecast_check_source_run_tag",
    signoff = "forecast_check_source_signoff_grade",
    path = "forecast_check_source_path",
    sha256 = "forecast_check_source_sha256"
  )
)

expected <- expand.grid(
  model_variant = names(models),
  family = names(families),
  tau = taus,
  stringsAsFactors = FALSE
)
observed_keys <- paste(
  source$model_variant,
  source$family,
  sprintf("%.2f", as.numeric(source$tau))
)
expected_keys <- paste(
  expected$model_variant,
  expected$family,
  sprintf("%.2f", expected$tau)
)
source_registry_hash <- unique(source$source_registry_hash_value)
if (
  nrow(source) != 36L ||
  anyDuplicated(observed_keys) ||
  !setequal(observed_keys, expected_keys) ||
  any(as.integer(source$fit_size) != 500L) ||
  any(source$comparison_eligible != "STATUS_AGNOSTIC") ||
  any(!source$status %in% c("SUCCESS", "done")) ||
  any(source$source_promotion_id != promotion_id) ||
  length(source_registry_hash) != 1L ||
  !identical(
    source_registry_hash,
    manifest_value(manifest_lines, "source_registry_hash")
  )
) {
  stop("Authoritative source does not satisfy the complete frozen figure contract.", call. = FALSE)
}

workspace_root <- normalizePath(
  dirname(validation_root),
  winslash = "/",
  mustWork = TRUE
)
relative_to_workspace <- function(path) {
  normalized <- normalizePath(path, winslash = "/", mustWork = TRUE)
  prefix <- paste0(workspace_root, "/")
  if (!startsWith(normalized, prefix)) {
    stop("A metric source path escapes the canonical workspace root.", call. = FALSE)
  }
  substring(normalized, nchar(prefix) + 1L)
}

long <- do.call(
  rbind,
  lapply(metrics, function(definition) {
    data.frame(
      model_variant = source$model_variant,
      model_label = unname(models[source$model_variant]),
      family = source$family,
      family_label = unname(families[source$family]),
      tau = as.numeric(source$tau),
      metric = definition$metric,
      metric_label = definition$label,
      value = as.numeric(source[[definition$value]]),
      source_signoff_grade = source[[definition$signoff]],
      source_candidate_id = source[[definition$candidate]],
      source_run_tag = source[[definition$run_tag]],
      source_path_relative = vapply(
        source[[definition$path]],
        relative_to_workspace,
        character(1L)
      ),
      source_sha256 = source[[definition$sha256]],
      metric_source_mixed = source$metric_source_mixed,
      source_promotion_id = source$source_promotion_id,
      source_registry_hash_value = source$source_registry_hash_value,
      stringsAsFactors = FALSE
    )
  })
)

if (
  nrow(long) != 108L ||
  any(!is.finite(long$value)) ||
  any(long$value <= 0) ||
  any(!long$source_signoff_grade %in% c("PASS", "WARN", "FAIL"))
) {
  stop("Long-form figure data are incomplete or invalid.", call. = FALSE)
}

group <- interaction(long$family, long$tau, long$metric, drop = TRUE)
long$best_value <- ave(long$value, group, FUN = min)
long$ratio_to_best <- long$value / long$best_value
long$log2_ratio_to_best <- log2(long$ratio_to_best)
long$is_winner <- abs(long$value - long$best_value) < 1e-10
long$value_label <- ifelse(
  abs(long$value) >= 10,
  formatC(long$value, format = "f", digits = 2),
  formatC(long$value, format = "f", digits = 3)
)

model_levels <- unname(models)
metric_levels <- vapply(metrics, `[[`, character(1L), "label")
long$model_label <- factor(long$model_label, levels = rev(model_levels))
long$family_label <- factor(long$family_label, levels = unname(families))
long$metric_label <- factor(long$metric_label, levels = metric_levels)
long$tau_label <- factor(
  sprintf("%.2f", long$tau),
  levels = sprintf("%.2f", taus)
)

write_data <- long[
  order(
    match(as.character(long$metric_label), metric_levels),
    match(as.character(long$family_label), unname(families)),
    match(as.character(long$model_label), model_levels),
    long$tau
  ),
  c(
    "model_variant",
    "model_label",
    "family",
    "family_label",
    "tau",
    "metric",
    "metric_label",
    "value",
    "best_value",
    "ratio_to_best",
    "is_winner",
    "source_signoff_grade",
    "source_candidate_id",
    "source_run_tag",
    "source_path_relative",
    "source_sha256",
    "metric_source_mixed",
    "source_promotion_id",
    "source_registry_hash_value"
  )
]
dir.create(dirname(output_data), recursive = TRUE, showWarnings = FALSE)
write.csv(write_data, output_data, row.names = FALSE, na = "")

ratio_limit <- 12
fill_break_ratios <- c(1, 1.5, 2, 4, 8, 12)
fill_colors <- c("#F7F9FC", "#DCEBE7", "#9FC8BE", "#E6C36A", "#C87832", "#7E2F22")
fill_values <- scales::rescale(
  log2(c(1, 1.25, 1.75, 3, 6, ratio_limit)),
  from = c(0, log2(ratio_limit))
)

base_plot <- ggplot2::ggplot(
  long,
  ggplot2::aes(x = tau_label, y = model_label)
) +
  ggplot2::geom_tile(
    ggplot2::aes(fill = log2_ratio_to_best),
    width = 0.96,
    height = 0.94,
    color = "white",
    linewidth = 0.75
  ) +
  ggplot2::geom_tile(
    data = long[long$is_winner, , drop = FALSE],
    width = 0.96,
    height = 0.94,
    fill = NA,
    color = "#1F252B",
    linewidth = 0.72
  )

light_text <- long$ratio_to_best < 3
base_plot <- base_plot +
  ggplot2::geom_text(
    data = long[light_text, , drop = FALSE],
    ggplot2::aes(label = value_label, fontface = ifelse(is_winner, "bold", "plain")),
    color = "#1F252B",
    size = 3.05,
    show.legend = FALSE
  ) +
  ggplot2::geom_text(
    data = long[!light_text, , drop = FALSE],
    ggplot2::aes(label = value_label, fontface = ifelse(is_winner, "bold", "plain")),
    color = "white",
    size = 3.05,
    show.legend = FALSE
  )

diagnostic <- long[
  long$source_signoff_grade %in% c("WARN", "FAIL"),
  ,
  drop = FALSE
]
diagnostic$source_signoff_grade <- factor(
  diagnostic$source_signoff_grade,
  levels = c("WARN", "FAIL")
)
diagnostic$marker_color <- ifelse(
  diagnostic$source_signoff_grade == "WARN",
  "#B9831F",
  "#B23A3A"
)
plot <- base_plot +
  ggplot2::geom_point(
    data = diagnostic,
    ggplot2::aes(
      shape = source_signoff_grade,
      color = I(marker_color)
    ),
    position = ggplot2::position_nudge(x = 0.34, y = 0.31),
    size = 1.75,
    stroke = 0.72,
    fill = "#FFF8EA",
    show.legend = TRUE
  ) +
  ggplot2::facet_grid(metric_label ~ family_label) +
  ggplot2::scale_fill_gradientn(
    colours = fill_colors,
    values = fill_values,
    limits = c(0, log2(ratio_limit)),
    breaks = log2(fill_break_ratios),
    labels = c("Best", "1.5x", "2x", "4x", "8x", "12x"),
    oob = scales::squish,
    name = "Value relative to the within-cell best"
  ) +
  ggplot2::scale_shape_manual(
    values = c(WARN = 24, FAIL = 4),
    limits = c("WARN", "FAIL"),
    name = "Metric-source signoff"
  ) +
  ggplot2::scale_color_identity(guide = "none") +
  ggplot2::guides(
    fill = ggplot2::guide_colorbar(
      title.position = "top",
      title.hjust = 0.5,
      barwidth = grid::unit(11.5, "cm"),
      barheight = grid::unit(0.34, "cm"),
      order = 1
    ),
    shape = ggplot2::guide_legend(
      title.position = "top",
      title.hjust = 0.5,
      nrow = 1,
      order = 2,
      override.aes = list(
        size = 2.6,
        color = c("#B9831F", "#B23A3A"),
        fill = c("#FFF8EA", NA)
      )
    )
  ) +
  ggplot2::labs(
    x = "Target quantile level",
    y = NULL
  ) +
  ggplot2::theme_minimal(base_family = "Helvetica", base_size = 10) +
  ggplot2::theme(
    panel.grid = ggplot2::element_blank(),
    panel.spacing = grid::unit(0.42, "lines"),
    strip.background = ggplot2::element_rect(
      fill = "#F7F9FC",
      color = "#CFD8E3",
      linewidth = 0.45
    ),
    strip.text.x = ggplot2::element_text(
      face = "bold",
      color = "#17365D",
      size = 10.2,
      margin = ggplot2::margin(4, 2, 4, 2)
    ),
    strip.text.y = ggplot2::element_text(
      face = "bold",
      color = "#17365D",
      size = 9.6,
      margin = ggplot2::margin(2, 4, 2, 4)
    ),
    axis.text.x = ggplot2::element_text(color = "#1F252B", size = 9.1),
    axis.text.y = ggplot2::element_text(color = "#1F252B", size = 9.0),
    axis.title.x = ggplot2::element_text(
      color = "#1F252B",
      face = "bold",
      margin = ggplot2::margin(t = 8)
    ),
    legend.position = "bottom",
    legend.box = "horizontal",
    legend.box.just = "center",
    legend.spacing.x = grid::unit(0.35, "cm"),
    legend.title = ggplot2::element_text(face = "bold", size = 8.8),
    legend.text = ggplot2::element_text(size = 8.4),
    plot.margin = ggplot2::margin(7, 8, 5, 7)
  )

article_pdf <- function(filename, width, height, ...) {
  grDevices::pdf(
    file = filename,
    width = width,
    height = height,
    onefile = TRUE,
    family = "Helvetica",
    paper = "special",
    useDingbats = FALSE,
    timestamp = FALSE,
    producer = FALSE,
    ...
  )
}

dir.create(dirname(output_pdf), recursive = TRUE, showWarnings = FALSE)
ggplot2::ggsave(
  filename = output_pdf,
  plot = plot,
  device = article_pdf,
  width = 10.4,
  height = 7.6,
  units = "in",
  bg = "white"
)

output_pdf <- normalizePath(output_pdf, winslash = "/", mustWork = TRUE)
output_data <- normalizePath(output_data, winslash = "/", mustWork = TRUE)
output_manifest <- normalizePath(
  output_manifest,
  winslash = "/",
  mustWork = FALSE
)
manifest_output <- c(
  "Independent single-quantile MCMC performance figure",
  paste0("figure_id: qdesn_mcmc_metric_envelope_heatmap"),
  paste0("source_promotion_id: ", promotion_id),
  paste0("source_csv: ", source_csv),
  paste0("source_csv_sha256: ", sha256(source_csv)),
  paste0("source_registry_hash: ", source_registry_hash),
  paste0("source_rows: ", nrow(source)),
  paste0("plotted_values: ", nrow(long)),
  paste0("models: ", length(models)),
  paste0("families: ", length(families)),
  paste0("quantile_levels: ", length(taus)),
  paste0("metrics: ", length(metrics)),
  paste0("metric_source_mixed_rows: ", sum(as.logical(source$metric_source_mixed))),
  "normalization: value divided by the minimum across four models within family x tau x metric",
  "fill_transform: log2(ratio_to_best)",
  "selection_policy: status-agnostic metric-wise calibrated envelope; lower is better",
  "diagnostic_policy: WARN and FAIL markers reflect the contributing metric source",
  paste0("source_path_base: ", workspace_root),
  paste0("script: ", relative_to_repo(script_path)),
  paste0("script_sha256: ", sha256(script_path)),
  paste0("figure_pdf: ", relative_to_repo(output_pdf)),
  paste0("figure_pdf_sha256: ", sha256(output_pdf)),
  paste0("figure_data_csv: ", relative_to_repo(output_data)),
  paste0("figure_data_csv_sha256: ", sha256(output_data))
)
dir.create(dirname(output_manifest), recursive = TRUE, showWarnings = FALSE)
writeLines(manifest_output, output_manifest, useBytes = TRUE)

cat(sprintf("source rows verified: %d\n", nrow(source)))
cat(sprintf("plotted values verified: %d\n", nrow(long)))
cat(sprintf("figure: %s\n", output_pdf))
cat(sprintf("data: %s\n", output_data))
cat(sprintf("manifest: %s\n", output_manifest))
