#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- sub("^--file=", "", script_arg[[1L]])
repo_root <- normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
suppressPackageStartupMessages(library(ggplot2))

args <- app_parse_args(list(
  source_runtime_root = "",
  continuation_runtime_root = "",
  source_tag = "glofas_part4_joint_al_sweep10_20260911",
  output_tag = "glofas_part4_joint_al_sweep10_presentation_v2_20260911"
))

if (!nzchar(args$source_runtime_root) || !nzchar(args$continuation_runtime_root)) {
  stop("Both frozen runtime roots are required.", call. = FALSE)
}
source_root <- app_resolve_path(args$source_runtime_root, must_work = TRUE)
continuation_root <- app_resolve_path(args$continuation_runtime_root, must_work = TRUE)
source_tag <- trimws(as.character(args$source_tag)[[1L]])
output_tag <- trimws(as.character(args$output_tag)[[1L]])
if (!grepl("^[A-Za-z0-9_.-]+$", source_tag) || !grepl("^[A-Za-z0-9_.-]+$", output_tag)) {
  stop("Invalid source or output tag.", call. = FALSE)
}

table_path <- function(stem, tag = output_tag, ext = "csv") {
  app_path("tables", paste0(stem, "__", tag, ".", ext))
}
figure_path <- function(stem, diagnostics = FALSE) {
  pieces <- c("figures", "glofas_application")
  if (diagnostics) pieces <- c(pieces, "diagnostics")
  do.call(app_path, as.list(c(pieces, paste0(stem, "__", output_tag, ".pdf"))))
}
repo_relative <- function(path) {
  substring(normalizePath(path, mustWork = FALSE), nchar(normalizePath(repo_root)) + 2L)
}

source_manifest_path <- table_path("glofas_application_part4_publication_manifest", source_tag)
source_score_path <- table_path("glofas_application_part4_forecast_scores", source_tag)
source_guardrail_path <- table_path("glofas_application_part4_common_grid_tradeoff", source_tag)
if (!file.exists(source_manifest_path) || !file.exists(source_score_path) ||
    !file.exists(source_guardrail_path)) {
  stop("The frozen Part 4 publication package is missing.", call. = FALSE)
}
source_manifest <- read.csv(source_manifest_path, stringsAsFactors = FALSE)
source_targets <- file.path(repo_root, source_manifest$relative_path)
if (any(!file.exists(source_targets))) {
  stop("A frozen Part 4 manifest target is missing.", call. = FALSE)
}
source_hashes <- vapply(source_targets, app_sha256_file, character(1L))
if (any(tolower(source_hashes) != tolower(source_manifest$sha256))) {
  stop("The frozen Part 4 publication manifest no longer verifies.", call. = FALSE)
}
expected_score_hash <- "829d4467e4b734d4cd7a0dbab40ba72fe9b9c91c328908461f82f3093167d498"
if (!identical(tolower(app_sha256_file(source_score_path)), expected_score_hash)) {
  stop("The frozen seven-family score ledger has changed.", call. = FALSE)
}

scores <- read.csv(source_score_path, stringsAsFactors = FALSE)
required_families <- c(
  "Normal Ridge", "Normal RHS/VB", "Independent AL", "Independent exAL",
  "Joint AL", "Joint exAL", "Raw GloFAS"
)
if (nrow(scores) != 7L || !setequal(scores$family, required_families) ||
    any(scores$n_scored_horizons != 28L) || any(!is.finite(scores$crps_grid_log1p))) {
  stop("The frozen score ledger does not satisfy the presentation contract.", call. = FALSE)
}
joint_al <- scores[scores$family == "Joint AL", , drop = FALSE]
joint_exal <- scores[scores$family == "Joint exAL", , drop = FALSE]
if (nrow(joint_al) != 1L || joint_al$role != "selected_quantile_model" ||
    joint_al$numerical_status != "cap_stabilized_after_rhs_release" ||
    isTRUE(joint_al$converged) || nrow(joint_exal) != 1L ||
    joint_exal$role != "nonconverged_quantile_sensitivity" ||
    joint_exal$numerical_status != "source_fit_not_qualified" || isTRUE(joint_exal$converged)) {
  stop("The Joint AL or Joint exAL qualification changed.", call. = FALSE)
}

source_label <- basename(source_root)
tau_grid <- c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95)
tau_ids <- c("p05", "p20", "p35", "p50", "p65", "p80", "p95")
cutoff <- as.Date("2022-12-25")
issued_start <- as.Date("2022-12-26")
issued_end <- as.Date("2023-01-22")
history_start <- cutoff - 29L

design_path <- file.path(source_root, "objects", "part4_shared_design_truth_free.rds")
truth_path <- file.path(source_root, "objects", "part4_scoring_panel_sidecar.rds")
if (!file.exists(design_path) || !file.exists(truth_path)) {
  stop("The frozen design or scoring-only truth sidecar is missing.", call. = FALSE)
}
design <- readRDS(design_path)
truth_sidecar <- readRDS(truth_path)$panel
panel <- design$base_panel
panel$target_date <- as.Date(panel$target_date)
truth_sidecar$target_date <- as.Date(truth_sidecar$target_date)
truth_sidecar <- truth_sidecar[
  truth_sidecar$target_date >= issued_start & truth_sidecar$target_date <= issued_end,
  , drop = FALSE
]
history_idx <- which(panel$target_date >= history_start & panel$target_date <= cutoff)
if (length(history_idx) != 30L || nrow(truth_sidecar) != 28L ||
    !isTRUE(all.equal(
      as.Date(sort(unique(truth_sidecar$target_date))),
      seq(issued_start, issued_end, by = "day"),
      check.attributes = FALSE
    ))) {
  stop("The 30-day historical context or 28-day scoring window changed.", call. = FALSE)
}

ensemble <- design$latent_data$g_ensemble
ensemble$target_date <- as.Date(ensemble$target_date)
ensemble <- ensemble[
  ensemble$target_date >= issued_start & ensemble$target_date <= issued_end,
  , drop = FALSE
]
if (length(unique(ensemble$target_date)) != 28L || length(unique(ensemble$member)) != 51L) {
  stop("The frozen issued GloFAS ensemble is not 28 dates by 51 members.", call. = FALSE)
}
ensemble_mean <- aggregate(g_transformed ~ target_date, ensemble, mean)

coefficient_file <- function(root, job) {
  file.path(root, "coefficients", paste0(job, "_coefficients.csv"))
}
prediction_file <- function(root, job) {
  file.path(root, "predictions", paste0(job, "_posterior_draws.csv.gz"))
}
read_coefficients <- function(root, job) {
  path <- coefficient_file(root, job)
  if (!file.exists(path)) stop("Missing coefficient file: ", path, call. = FALSE)
  read.csv(path, stringsAsFactors = FALSE)
}
read_predictions <- function(root, job) {
  path <- prediction_file(root, job)
  if (!file.exists(path)) stop("Missing prediction file: ", path, call. = FALSE)
  out <- read.csv(gzfile(path), stringsAsFactors = FALSE)
  out$target_date <- as.Date(out$target_date)
  out
}

coefficient_paths <- function(coefficients, quantile_level = NA_real_) {
  if (!is.na(quantile_level) && "quantile_level" %in% names(coefficients)) {
    coefficients <- coefficients[
      abs(as.numeric(coefficients$quantile_level) - quantile_level) < 1.0e-12,
      , drop = FALSE
    ]
  }
  beta <- coefficients[startsWith(coefficients$coefficient, "beta__"), , drop = FALSE]
  alpha <- coefficients[startsWith(coefficients$coefficient, "alpha__"), , drop = FALSE]
  if (nrow(beta) != ncol(design$X_beta) || nrow(alpha) != ncol(design$X_alpha)) {
    stop("Coefficient and design dimensions do not match.", call. = FALSE)
  }
  list(
    usgs = as.numeric(design$X_beta[history_idx, , drop = FALSE] %*% as.numeric(beta$mean)),
    discrepancy = as.numeric(design$X_alpha[history_idx, , drop = FALSE] %*% as.numeric(alpha$mean))
  )
}

quantile_history <- function(root, jobs, model) {
  do.call(rbind, lapply(seq_along(tau_grid), function(i) {
    paths <- coefficient_paths(read_coefficients(root, jobs[[i]]), tau_grid[[i]])
    rbind(
      data.frame(
        model = model, target = "USGS latent path",
        target_date = panel$target_date[history_idx], quantile_level = tau_grid[[i]],
        value = paths$usgs, stringsAsFactors = FALSE
      ),
      data.frame(
        model = model, target = "GloFAS - USGS discrepancy",
        target_date = panel$target_date[history_idx], quantile_level = tau_grid[[i]],
        value = paths$discrepancy, stringsAsFactors = FALSE
      )
    )
  }))
}

summarize_quantile_prediction <- function(root, job, model) {
  draws <- read_predictions(root, job)
  if (!setequal(sort(unique(as.numeric(draws$quantile_level))), tau_grid) &&
      length(unique(as.numeric(draws$quantile_level))) != 1L) {
    stop("Unexpected probability levels in prediction file: ", job, call. = FALSE)
  }
  keys <- interaction(draws$target_date, as.numeric(draws$quantile_level), drop = TRUE)
  do.call(rbind, lapply(split(draws, keys), function(block) rbind(
    data.frame(
      model = model, target = "USGS latent path", target_date = unique(block$target_date),
      quantile_level = unique(as.numeric(block$quantile_level)), value = mean(block$q_y_draw),
      stringsAsFactors = FALSE
    ),
    data.frame(
      model = model, target = "GloFAS - USGS discrepancy", target_date = unique(block$target_date),
      quantile_level = unique(as.numeric(block$quantile_level)), value = mean(block$d_g_draw),
      stringsAsFactors = FALSE
    )
  )))
}

quantile_forecast <- function(root, jobs, model) {
  out <- do.call(rbind, lapply(jobs, function(job) summarize_quantile_prediction(root, job, model)))
  observed_grid <- sort(unique(as.numeric(out$quantile_level)))
  observed_dates <- sort(unique(out$target_date))
  if (!isTRUE(all.equal(observed_grid, tau_grid, tolerance = 1.0e-12)) ||
      !isTRUE(all.equal(
        as.Date(observed_dates), seq(issued_start, issued_end, by = "day"),
        check.attributes = FALSE
      ))) {
    stop("A displayed quantile model does not use the common grid and dates.", call. = FALSE)
  }
  out
}

normal_history <- function(root, job, model) {
  paths <- coefficient_paths(read_coefficients(root, job))
  rbind(
    data.frame(
      model = model, target = "USGS latent path", target_date = panel$target_date[history_idx],
      center = paths$usgs, stringsAsFactors = FALSE
    ),
    data.frame(
      model = model, target = "GloFAS - USGS discrepancy", target_date = panel$target_date[history_idx],
      center = paths$discrepancy, stringsAsFactors = FALSE
    )
  )
}

normal_forecast <- function(root, job, model) {
  draws <- read_predictions(root, job)
  summarize_target <- function(column, target) {
    blocks <- split(as.numeric(draws[[column]]), draws$target_date)
    do.call(rbind, lapply(names(blocks), function(date) {
      values <- blocks[[date]]
      data.frame(
        model = model, target = target, target_date = as.Date(date),
        center = unname(quantile(values, 0.50, type = 8)),
        lower = unname(quantile(values, 0.05, type = 8)),
        upper = unname(quantile(values, 0.95, type = 8)),
        stringsAsFactors = FALSE
      )
    }))
  }
  out <- rbind(
    summarize_target("latent_y_draw", "USGS latent path"),
    summarize_target("d_g_draw", "GloFAS - USGS discrepancy")
  )
  if (!isTRUE(all.equal(
    as.Date(sort(unique(out$target_date))), seq(issued_start, issued_end, by = "day"),
    check.attributes = FALSE
  ))) {
    stop("A displayed Normal model does not use the common issued dates.", call. = FALSE)
  }
  out
}

score_row <- function(family) {
  out <- scores[scores$family == family, , drop = FALSE]
  if (nrow(out) != 1L) stop("Missing score row: ", family, call. = FALSE)
  out
}
facet_label <- function(family, qualification = NULL) {
  row <- score_row(family)
  label <- sprintf("%s\naCRPS %.3f; 90%% coverage %.3f", family, row$crps_grid_log1p, row$coverage90)
  if (!is.null(qualification)) label <- paste0(label, "\n", qualification)
  label
}

normal_families <- c("Normal Ridge", "Normal RHS/VB")
normal_jobs <- c(
  paste0(source_label, "_normal_ridge_diagnostic"),
  paste0(source_label, "_normal_rhs_vb_diagnostic")
)
normal_labels <- c(
  "Normal Ridge" = facet_label("Normal Ridge"),
  "Normal RHS/VB" = facet_label("Normal RHS/VB")
)
normal_history_data <- do.call(rbind, lapply(seq_along(normal_jobs), function(i) {
  normal_history(source_root, normal_jobs[[i]], normal_labels[[normal_families[[i]]]])
}))
normal_forecast_data <- do.call(rbind, lapply(seq_along(normal_jobs), function(i) {
  normal_forecast(source_root, normal_jobs[[i]], normal_labels[[normal_families[[i]]]])
}))

independent_labels <- c(
  "Independent AL" = facet_label("Independent AL"),
  "Independent exAL" = facet_label("Independent exAL")
)
independent_al_jobs <- paste0(source_label, "_independent_al_rhs_vb_", tau_ids)
independent_exal_jobs <- paste0(source_label, "_independent_exal_rhs_vb_", tau_ids)
independent_history_data <- rbind(
  quantile_history(source_root, independent_al_jobs, independent_labels[["Independent AL"]]),
  quantile_history(source_root, independent_exal_jobs, independent_labels[["Independent exAL"]])
)
independent_forecast_data <- rbind(
  quantile_forecast(source_root, independent_al_jobs, independent_labels[["Independent AL"]]),
  quantile_forecast(source_root, independent_exal_jobs, independent_labels[["Independent exAL"]])
)

joint_labels <- c(
  "Joint AL" = facet_label("Joint AL"),
  "Joint exAL" = facet_label("Joint exAL", "Sensitivity; fit not qualified")
)
joint_al_job <- "glofas_part4_joint_al_continuation_20260907"
joint_exal_job <- paste0(source_label, "_joint_exal_rhs_vb")
joint_history_data <- rbind(
  quantile_history(continuation_root, rep(joint_al_job, length(tau_grid)), joint_labels[["Joint AL"]]),
  quantile_history(source_root, rep(joint_exal_job, length(tau_grid)), joint_labels[["Joint exAL"]])
)
joint_forecast_data <- rbind(
  quantile_forecast(continuation_root, joint_al_job, joint_labels[["Joint AL"]]),
  quantile_forecast(source_root, joint_exal_job, joint_labels[["Joint exAL"]])
)

target_levels <- c("USGS latent path", "GloFAS - USGS discrepancy")
forest <- "#1B5E3C"
orange <- "#A64B00"
orange_dark <- "#7F3800"
charcoal <- "#30343B"
grid_gray <- "#D8DEE3"
strip_fill <- "#F0F2F3"
strip_edge <- "#C8CED3"
quantile_colors <- c(
  "0.05" = "#243B53", "0.2" = "#345C78", "0.35" = "#527A91",
  "0.5" = "#6B6F8E", "0.65" = "#7F5D82", "0.8" = "#8E496F",
  "0.95" = "#9B3558"
)

context_for <- function(models) {
  history <- do.call(rbind, lapply(models, function(model) rbind(
    data.frame(
      model = model, target = target_levels[[1L]], target_date = panel$target_date[history_idx],
      value = panel$y_transformed[history_idx], series = "USGS observed through origin"
    ),
    data.frame(
      model = model, target = target_levels[[1L]], target_date = panel$target_date[history_idx],
      value = panel$g_transformed[history_idx], series = "GloFAS retrospective"
    ),
    data.frame(
      model = model, target = target_levels[[2L]], target_date = panel$target_date[history_idx],
      value = panel$g_transformed[history_idx] - panel$y_transformed[history_idx],
      series = "Historical discrepancy"
    )
  )))
  future <- merge(truth_sidecar, ensemble_mean, by = "target_date", all = FALSE)
  future <- do.call(rbind, lapply(models, function(model) rbind(
    data.frame(
      model = model, target = target_levels[[1L]], target_date = future$target_date,
      value = future$y_transformed, series = "USGS withheld for scoring"
    ),
    data.frame(
      model = model, target = target_levels[[2L]], target_date = future$target_date,
      value = future$g_transformed - future$y_transformed, series = "Withheld discrepancy"
    )
  )))
  members <- do.call(rbind, lapply(models, function(model) {
    transform(ensemble, model = model, target = target_levels[[1L]])
  }))
  center <- do.call(rbind, lapply(models, function(model) {
    transform(ensemble_mean, model = model, target = target_levels[[1L]])
  }))
  list(history = history, future = future, members = members, center = center)
}

base_plot <- function(models) {
  context <- context_for(models)
  usgs_history <- context$history[context$history$series == "USGS observed through origin", , drop = FALSE]
  glofas_history <- context$history[context$history$series == "GloFAS retrospective", , drop = FALSE]
  discrepancy_history <- context$history[context$history$series == "Historical discrepancy", , drop = FALSE]
  usgs_future <- context$future[context$future$series == "USGS withheld for scoring", , drop = FALSE]
  discrepancy_future <- context$future[context$future$series == "Withheld discrepancy", , drop = FALSE]

  ggplot() +
    geom_line(
      data = context$members,
      aes(
        target_date, g_transformed, group = interaction(model, member),
        alpha = "Issued GloFAS members"
      ),
      color = orange, linewidth = 0.20
    ) +
    geom_line(
      data = context$center,
      aes(target_date, g_transformed, alpha = "Issued GloFAS mean"),
      color = orange_dark, linewidth = 0.72
    ) +
    geom_line(
      data = glofas_history,
      aes(target_date, value, alpha = "Retrospective GloFAS"),
      color = orange, linewidth = 0.64
    ) +
    geom_line(data = usgs_history, aes(target_date, value), color = forest, linewidth = 0.48) +
    geom_point(
      data = usgs_history, aes(target_date, value, shape = series),
      color = forest, size = 1.40, stroke = 0.35
    ) +
    geom_line(data = usgs_future, aes(target_date, value), color = forest, linewidth = 0.52, linetype = "22") +
    geom_point(
      data = usgs_future, aes(target_date, value, shape = series),
      color = forest, fill = "white", size = 1.65, stroke = 0.62
    ) +
    geom_line(data = discrepancy_history, aes(target_date, value), color = charcoal, linewidth = 0.48) +
    geom_point(
      data = discrepancy_history, aes(target_date, value, shape = series),
      color = charcoal, size = 1.30, stroke = 0.30
    ) +
    geom_line(data = discrepancy_future, aes(target_date, value), color = charcoal, linewidth = 0.52, linetype = "22") +
    geom_point(
      data = discrepancy_future, aes(target_date, value, shape = series),
      color = charcoal, fill = "white", size = 1.55, stroke = 0.58
    ) +
    geom_vline(xintercept = cutoff, color = "#68737D", linetype = "dotted", linewidth = 0.55) +
    scale_shape_manual(
      values = c(
        "USGS observed through origin" = 16,
        "USGS withheld for scoring" = 1,
        "Historical discrepancy" = 16,
        "Withheld discrepancy" = 1
      ),
      breaks = c("USGS observed through origin", "USGS withheld for scoring"),
      name = NULL
    ) +
    scale_alpha_manual(
      values = c(
        "Retrospective GloFAS" = 1,
        "Issued GloFAS members" = 0.12,
        "Issued GloFAS mean" = 1
      ),
      breaks = c(
        "Retrospective GloFAS", "Issued GloFAS members", "Issued GloFAS mean"
      ),
      name = NULL
    ) +
    scale_x_date(
      date_breaks = "14 days", date_labels = "%b %d",
      limits = c(history_start, issued_end), expand = expansion(mult = c(0.01, 0.02))
    ) +
    labs(x = "Date", y = NULL) +
    theme_minimal(base_size = 9.5) +
    theme(
      panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(),
      panel.grid.major.y = element_line(color = grid_gray, linewidth = 0.28),
      strip.text = element_text(face = "plain", size = 9.2, lineheight = 1.08),
      strip.background = element_rect(fill = strip_fill, color = strip_edge, linewidth = 0.35),
      panel.spacing = grid::unit(0.60, "lines"),
      legend.position = "top", legend.box = "vertical",
      legend.margin = margin(0, 0, 2, 0), legend.key.height = grid::unit(0.34, "cm"),
      plot.margin = margin(4, 7, 4, 5)
    ) +
    guides(
      shape = guide_legend(order = 2, override.aes = list(color = forest, size = 2.4)),
      alpha = guide_legend(
        order = 3,
        override.aes = list(
          color = c(orange, orange, orange_dark),
          linewidth = c(0.75, 0.35, 0.75)
        )
      )
    )
}

quantile_plot <- function(models, history, forecast) {
  history_nonmedian <- history[abs(history$quantile_level - 0.50) > 1.0e-12, , drop = FALSE]
  history_median <- history[abs(history$quantile_level - 0.50) <= 1.0e-12, , drop = FALSE]
  forecast_nonmedian <- forecast[abs(forecast$quantile_level - 0.50) > 1.0e-12, , drop = FALSE]
  forecast_median <- forecast[abs(forecast$quantile_level - 0.50) <= 1.0e-12, , drop = FALSE]
  base_plot(models) +
    geom_line(
      data = history_nonmedian,
      aes(target_date, value, color = factor(quantile_level), group = interaction(model, target, quantile_level)),
      linewidth = 0.60, linetype = "dashed"
    ) +
    geom_line(
      data = forecast_nonmedian,
      aes(target_date, value, color = factor(quantile_level), group = interaction(model, target, quantile_level)),
      linewidth = 0.70
    ) +
    geom_line(
      data = history_median,
      aes(target_date, value, color = factor(quantile_level), group = interaction(model, target, quantile_level)),
      linewidth = 0.83, linetype = "dashed"
    ) +
    geom_line(
      data = forecast_median,
      aes(target_date, value, color = factor(quantile_level), group = interaction(model, target, quantile_level)),
      linewidth = 0.92
    ) +
    scale_color_manual(
      values = quantile_colors, breaks = as.character(tau_grid),
      labels = c("0.05", "0.20", "0.35", "0.50", "0.65", "0.80", "0.95"),
      name = "Probability level"
    ) +
    guides(
      color = guide_legend(order = 1, nrow = 1, byrow = TRUE, override.aes = list(linewidth = 0.85)),
      shape = guide_legend(order = 2, override.aes = list(color = forest, size = 2.4)),
      alpha = guide_legend(
        order = 3,
        override.aes = list(
          color = c(orange, orange, orange_dark),
          linewidth = c(0.75, 0.35, 0.75)
        )
      )
    )
}

main_model <- joint_labels[["Joint AL"]]
main_plot <- quantile_plot(
  main_model,
  joint_history_data[joint_history_data$model == main_model, , drop = FALSE],
  joint_forecast_data[joint_forecast_data$model == main_model, , drop = FALSE]
) +
  facet_grid(rows = vars(factor(target, levels = target_levels)), scales = "free_y")

normal_plot <- base_plot(unname(normal_labels)) +
  geom_ribbon(
    data = normal_forecast_data,
    aes(target_date, ymin = lower, ymax = upper, group = interaction(model, target)),
    fill = "#6B6F8E", alpha = 0.14
  ) +
  geom_line(data = normal_history_data, aes(target_date, center), color = "#5C5F7E", linewidth = 0.73, linetype = "dashed") +
  geom_line(data = normal_forecast_data, aes(target_date, center), color = "#5C5F7E", linewidth = 0.83) +
  facet_grid(
    rows = vars(factor(target, levels = target_levels)),
    cols = vars(factor(model, levels = unname(normal_labels))), scales = "free_y"
  )

independent_plot <- quantile_plot(
  unname(independent_labels), independent_history_data, independent_forecast_data
) +
  facet_grid(
    rows = vars(factor(target, levels = target_levels)),
    cols = vars(factor(model, levels = unname(independent_labels))), scales = "free_y"
  )

joint_plot <- quantile_plot(
  unname(joint_labels), joint_history_data, joint_forecast_data
) +
  facet_grid(
    rows = vars(factor(target, levels = target_levels)),
    cols = vars(factor(model, levels = unname(joint_labels))), scales = "free_y"
  )

paths <- c(
  main_table = table_path("glofas_application_part4_main_scores", ext = "tex"),
  supplement_table = table_path("glofas_application_part4_supplementary_scores", ext = "tex"),
  historical_table = table_path("glofas_application_part4_historical_guardrail", ext = "tex"),
  output_registry = table_path("glofas_application_part4_current_outputs", ext = "tex"),
  main_figure = figure_path("glofas_part4_joint_al_last30_issued28"),
  normal_figure = figure_path("glofas_part4_normal_comparison", TRUE),
  independent_figure = figure_path("glofas_part4_independent_quantile_comparison", TRUE),
  joint_figure = figure_path("glofas_part4_joint_quantile_comparison", TRUE),
  manifest = table_path("glofas_application_part4_presentation_manifest")
)
app_ensure_dir(dirname(paths[["main_figure"]]))
app_ensure_dir(dirname(paths[["normal_figure"]]))

main_order <- c(
  "Joint AL", "Independent AL", "Independent exAL",
  "Normal Ridge", "Normal RHS/VB", "Raw GloFAS"
)
main_scores <- scores[match(main_order, scores$family), , drop = FALSE]
display_model <- c(
  "Joint AL" = "Joint AL Q--DESN (selected)",
  "Independent AL" = "Independent AL Q--DESN",
  "Independent exAL" = "Independent exAL Q--DESN",
  "Normal Ridge" = "Normal Ridge DESN",
  "Normal RHS/VB" = "Normal RHS/VB DESN",
  "Raw GloFAS" = "Raw GloFAS"
)
main_rows <- vapply(seq_len(nrow(main_scores)), function(i) {
  reduction <- if (main_scores$family[[i]] == "Raw GloFAS") "--" else {
    sprintf("%.1f\\%%", 100 * main_scores$crps_reduction_vs_raw[[i]])
  }
  sprintf(
    "%s & %.4f & %.4f & %.4f & %.3f & %s \\\\",
    display_model[[main_scores$family[[i]]]], main_scores$mean_check_loss[[i]],
    main_scores$interval_score[[i]], main_scores$crps_grid_log1p[[i]],
    main_scores$coverage90[[i]], reduction
  )
}, character(1L))
main_table <- c(
  "\\begin{tabularx}{\\textwidth}{@{}Yrrrrr@{}}",
  "\\toprule",
  "Model & \\shortstack{Mean check\\\\loss} & \\shortstack{Interval\\\\score} & \\(\\aCRPS\\) & \\shortstack{90\\%\\\\coverage} & \\shortstack{\\(\\aCRPS\\) reduction\\\\vs raw GloFAS} \\\\",
  "\\midrule",
  main_rows[1:3],
  "\\addlinespace[2pt]",
  main_rows[4:5],
  "\\addlinespace[2pt]",
  main_rows[6],
  "\\bottomrule",
  "\\end{tabularx}"
)
writeLines(main_table, paths[["main_table"]])

supplement_order <- c(
  "Joint AL", "Independent AL", "Independent exAL", "Normal Ridge",
  "Normal RHS/VB", "Raw GloFAS", "Joint exAL"
)
supplement_scores <- scores[match(supplement_order, scores$family), , drop = FALSE]
qualification <- c(
  "Joint AL" = "Selected; cap-stabilized",
  "Independent AL" = "Completed comparator",
  "Independent exAL" = "Completed comparator",
  "Normal Ridge" = "Gaussian baseline",
  "Normal RHS/VB" = "Gaussian baseline",
  "Raw GloFAS" = "Issued benchmark",
  "Joint exAL" = "Sensitivity; fit not qualified"
)
supplement_rows <- vapply(seq_len(nrow(supplement_scores)), function(i) sprintf(
  "%s & %.4f & %.3f & %.3f & %.3f & %.3f & %s \\\\",
  supplement_scores$family[[i]], supplement_scores$crps_grid_log1p[[i]],
  supplement_scores$crps_grid_original[[i]], supplement_scores$median_mae_log1p[[i]],
  supplement_scores$median_rmse_log1p[[i]], supplement_scores$coverage90[[i]],
  qualification[[supplement_scores$family[[i]]]]
), character(1L))
supplement_table <- c(
  "\\begin{tabularx}{\\textwidth}{@{}YrrrrrY@{}}",
  "\\toprule",
  "Model & \\shortstack{\\(\\aCRPS\\)\\\\transformed} & \\shortstack{\\(\\aCRPS\\)\\\\original} & \\shortstack{Median\\\\MAE} & \\shortstack{Median\\\\RMSE} & \\shortstack{90\\%\\\\coverage} & Qualification \\\\",
  "\\midrule",
  supplement_rows[1:6],
  "\\midrule",
  supplement_rows[7],
  "\\bottomrule",
  "\\end{tabularx}"
)
writeLines(supplement_table, paths[["supplement_table"]])

guardrail <- read.csv(source_guardrail_path, stringsAsFactors = FALSE)
expected_windows <- c("all", "last1000", "last200", "last50")
if (nrow(guardrail) != 4L || !identical(guardrail$window, expected_windows) ||
    any(!is.finite(guardrail$fr09_crps_log1p)) ||
    any(!is.finite(guardrail$part4_joint_al_crps_log1p)) ||
    any(!is.finite(guardrail$relative_change))) {
  stop("The frozen common-grid historical guardrail changed.", call. = FALSE)
}
window_labels <- c(
  "all" = "Full history", "last1000" = "Last 1,000 dates",
  "last200" = "Last 200 dates", "last50" = "Last 50 dates"
)
guardrail_rows <- vapply(seq_len(nrow(guardrail)), function(i) sprintf(
  "%s & %.4f & %.4f & %+.1f\\%% \\\\",
  window_labels[[guardrail$window[[i]]]], guardrail$fr09_crps_log1p[[i]],
  guardrail$part4_joint_al_crps_log1p[[i]], 100 * guardrail$relative_change[[i]]
), character(1L))
historical_table <- c(
  "\\begin{tabular}{@{}lrrr@{}}",
  "\\toprule",
  "Historical window & FR09 \\(\\aCRPS\\) & Part 4 Joint AL \\(\\aCRPS\\) & Relative change \\\\",
  "\\midrule", guardrail_rows, "\\bottomrule", "\\end{tabular}"
)
writeLines(historical_table, paths[["historical_table"]])

ggsave(paths[["main_figure"]], main_plot, width = 7.15, height = 5.35, device = cairo_pdf)
ggsave(paths[["normal_figure"]], normal_plot, width = 7.35, height = 5.35, device = cairo_pdf)
ggsave(paths[["independent_figure"]], independent_plot, width = 7.35, height = 5.45, device = cairo_pdf)
ggsave(paths[["joint_figure"]], joint_plot, width = 7.35, height = 5.60, device = cairo_pdf)

current_registry <- readLines(app_path("tables/glofas_application_current_outputs.tex"), warn = FALSE)
replace_macro <- function(lines, name, value) {
  pattern <- paste0("^\\\\newcommand\\{\\\\", name, "\\}")
  replacement <- paste0("\\newcommand{\\", name, "}{", value, "}")
  hit <- grepl(pattern, lines)
  if (sum(hit) == 1L) {
    lines[hit] <- replacement
  } else if (!any(hit)) {
    lines <- c(lines, replacement)
  } else {
    stop("Output registry contains duplicate macro: ", name, call. = FALSE)
  }
  lines
}
current_registry <- replace_macro(current_registry, "GlofasApplicationCurrentScoreTable", repo_relative(paths[["main_table"]]))
current_registry <- replace_macro(current_registry, "GlofasApplicationCurrentCorrectedPathsFigure", repo_relative(paths[["main_figure"]]))
current_registry <- replace_macro(current_registry, "GlofasApplicationCurrentForecastWindowFigure", repo_relative(paths[["main_figure"]]))
current_registry <- replace_macro(current_registry, "GlofasApplicationCurrentSupplementScoreTable", repo_relative(paths[["supplement_table"]]))
current_registry <- replace_macro(current_registry, "GlofasApplicationCurrentHistoricalGuardrailTable", repo_relative(paths[["historical_table"]]))
current_registry <- replace_macro(current_registry, "GlofasApplicationCurrentNormalComparisonFigure", repo_relative(paths[["normal_figure"]]))
current_registry <- replace_macro(current_registry, "GlofasApplicationCurrentIndependentComparisonFigure", repo_relative(paths[["independent_figure"]]))
current_registry <- replace_macro(current_registry, "GlofasApplicationCurrentJointComparisonFigure", repo_relative(paths[["joint_figure"]]))
writeLines(current_registry, paths[["output_registry"]])

manifest_targets <- unname(paths[names(paths) != "manifest"])
presentation_manifest <- data.frame(
  relative_path = vapply(manifest_targets, repo_relative, character(1L)),
  size_bytes = as.numeric(file.info(manifest_targets)$size),
  sha256 = vapply(manifest_targets, app_sha256_file, character(1L)),
  article_safe = TRUE,
  publication_role = c(
    "main_table", "supplement_table", "historical_guardrail_table", "output_registry", "main_figure",
    "supplement_figure", "supplement_figure", "supplement_figure"
  ),
  overleaf_publish = TRUE,
  stringsAsFactors = FALSE
)
source_evidence <- data.frame(
  relative_path = c(repo_relative(source_score_path), repo_relative(source_manifest_path)),
  size_bytes = as.numeric(file.info(c(source_score_path, source_manifest_path))$size),
  sha256 = vapply(c(source_score_path, source_manifest_path), app_sha256_file, character(1L)),
  article_safe = TRUE,
  publication_role = "frozen_source_evidence",
  overleaf_publish = TRUE,
  stringsAsFactors = FALSE
)
presentation_manifest <- rbind(presentation_manifest, source_evidence)
reproduction_paths <- app_path(
  "application", "scripts",
  c(
    "393_build_glofas_part4_presentation_refresh.R",
    "394_check_glofas_part4_presentation_refresh.R"
  )
)
if (any(!file.exists(reproduction_paths))) {
  stop("Presentation reproduction code is missing.", call. = FALSE)
}
reproduction_code <- data.frame(
  relative_path = vapply(reproduction_paths, repo_relative, character(1L)),
  size_bytes = as.numeric(file.info(reproduction_paths)$size),
  sha256 = vapply(reproduction_paths, app_sha256_file, character(1L)),
  article_safe = TRUE,
  publication_role = "reproduction_code",
  overleaf_publish = FALSE,
  stringsAsFactors = FALSE
)
presentation_manifest <- rbind(presentation_manifest, reproduction_code)
write.csv(presentation_manifest, paths[["manifest"]], row.names = FALSE)

cat(sprintf(
  paste0(
    "GLOFAS_PART4_PRESENTATION_REFRESH_COMPLETE\n",
    "source_tag=%s\noutput_tag=%s\nmain_table_rows=%d\n",
    "main_figure=%s\n"
  ),
  source_tag, output_tag, nrow(main_scores), repo_relative(paths[["main_figure"]])
))
