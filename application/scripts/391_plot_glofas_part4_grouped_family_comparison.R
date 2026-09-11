#!/usr/bin/env Rscript

app_plot_glofas_part4_grouped_family_comparison <- function(
    source_root,
    continuation_root,
    output_pdf,
    output_scores,
    forecast_scores,
    design = NULL,
    truth_sidecar = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("ggplot2 is required for the Part 4 grouped figure.", call. = FALSE)
  }
  source_root <- normalizePath(source_root, mustWork = TRUE)
  continuation_root <- normalizePath(continuation_root, mustWork = TRUE)
  source_label <- basename(source_root)
  tau_grid <- c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95)
  tau_ids <- c("p05", "p20", "p35", "p50", "p65", "p80", "p95")
  cutoff <- as.Date("2022-12-25")
  issued_end <- as.Date("2023-01-22")
  history_start <- cutoff - 29L

  if (is.null(design)) {
    message("Reading the Part 4 truth-free design for the grouped figure...")
    design <- readRDS(file.path(source_root, "objects", "part4_shared_design_truth_free.rds"))
  }
  if (is.null(truth_sidecar)) {
    truth_sidecar <- readRDS(file.path(source_root, "objects", "part4_scoring_panel_sidecar.rds"))$panel
  }
  panel <- design$base_panel
  panel$target_date <- as.Date(panel$target_date)
  truth_sidecar$target_date <- as.Date(truth_sidecar$target_date)
  history_idx <- which(panel$target_date >= history_start & panel$target_date <= cutoff)
  if (length(history_idx) != 30L) stop("Grouped figure requires exactly 30 historical dates.", call. = FALSE)
  ensemble <- design$latent_data$g_ensemble
  ensemble$target_date <- as.Date(ensemble$target_date)
  ensemble <- ensemble[ensemble$target_date > cutoff & ensemble$target_date <= issued_end, , drop = FALSE]
  if (length(unique(ensemble$target_date)) != 28L || length(unique(ensemble$member)) != 51L) {
    stop("Grouped figure requires 28 issued dates and 51 GloFAS members.", call. = FALSE)
  }
  ensemble_mean <- aggregate(g_transformed ~ target_date, ensemble, mean)

  coefficient_file <- function(root, job) {
    file.path(root, "coefficients", paste0(job, "_coefficients.csv"))
  }
  prediction_file <- function(root, job) {
    file.path(root, "predictions", paste0(job, "_posterior_draws.csv.gz"))
  }
  read_coefficients <- function(root, job) {
    read.csv(coefficient_file(root, job), stringsAsFactors = FALSE)
  }
  read_predictions <- function(root, job) {
    out <- read.csv(gzfile(prediction_file(root, job)), stringsAsFactors = FALSE)
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
      stop("Grouped-figure coefficient/design dimensions do not match.", call. = FALSE)
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
        data.frame(model = model, target = "USGS latent path", target_date = panel$target_date[history_idx], quantile_level = tau_grid[[i]], value = paths$usgs),
        data.frame(model = model, target = "GloFAS - USGS discrepancy", target_date = panel$target_date[history_idx], quantile_level = tau_grid[[i]], value = paths$discrepancy)
      )
    }))
  }
  summarize_quantile_prediction <- function(root, job, model) {
    draws <- read_predictions(root, job)
    keys <- interaction(draws$target_date, as.numeric(draws$quantile_level), drop = TRUE)
    do.call(rbind, lapply(split(draws, keys), function(block) rbind(
      data.frame(model = model, target = "USGS latent path", target_date = unique(block$target_date), quantile_level = unique(as.numeric(block$quantile_level)), value = mean(block$q_y_draw)),
      data.frame(model = model, target = "GloFAS - USGS discrepancy", target_date = unique(block$target_date), quantile_level = unique(as.numeric(block$quantile_level)), value = mean(block$d_g_draw))
    )))
  }
  quantile_forecast <- function(root, jobs, model) {
    do.call(rbind, lapply(jobs, function(job) summarize_quantile_prediction(root, job, model)))
  }
  summarize_normal_prediction <- function(root, job, model) {
    draws <- read_predictions(root, job)
    summarize_target <- function(column, target) {
      blocks <- split(as.numeric(draws[[column]]), draws$target_date)
      do.call(rbind, lapply(names(blocks), function(date) {
        values <- blocks[[date]]
        data.frame(
          model = model, target = target, target_date = as.Date(date),
          center = mean(values), lower = unname(quantile(values, 0.025, type = 8)),
          upper = unname(quantile(values, 0.975, type = 8))
        )
      }))
    }
    rbind(
      summarize_target("q_y_draw", "USGS latent path"),
      summarize_target("d_g_draw", "GloFAS - USGS discrepancy")
    )
  }
  score_label <- function(family) {
    row <- forecast_scores[forecast_scores$family == family, , drop = FALSE]
    if (nrow(row) != 1L) stop("Grouped score table is missing family: ", family, call. = FALSE)
    sprintf("%s\nCRPS %.4f | 90%% cover %.1f%%", family, row$crps_grid_log1p, 100 * row$coverage90)
  }

  labels <- setNames(vapply(forecast_scores$family, score_label, character(1L)), forecast_scores$family)
  normal_families <- c("Normal Ridge", "Normal RHS/VB")
  normal_jobs <- c(
    paste0(source_label, "_normal_ridge_diagnostic"),
    paste0(source_label, "_normal_rhs_vb_diagnostic")
  )
  normal_history <- do.call(rbind, lapply(seq_along(normal_jobs), function(i) {
    paths <- coefficient_paths(read_coefficients(source_root, normal_jobs[[i]]))
    rbind(
      data.frame(model = labels[[normal_families[[i]]]], target = "USGS latent path", target_date = panel$target_date[history_idx], value = paths$usgs),
      data.frame(model = labels[[normal_families[[i]]]], target = "GloFAS - USGS discrepancy", target_date = panel$target_date[history_idx], value = paths$discrepancy)
    )
  }))
  normal_forecast <- do.call(rbind, lapply(seq_along(normal_jobs), function(i) {
    summarize_normal_prediction(source_root, normal_jobs[[i]], labels[[normal_families[[i]]]])
  }))

  independent_al_jobs <- paste0(source_label, "_independent_al_rhs_vb_", tau_ids)
  independent_exal_jobs <- paste0(source_label, "_independent_exal_rhs_vb_", tau_ids)
  joint_al_job <- "glofas_part4_joint_al_continuation_20260907"
  joint_exal_job <- paste0(source_label, "_joint_exal_rhs_vb")
  independent_history <- rbind(
    quantile_history(source_root, independent_al_jobs, labels[["Independent AL"]]),
    quantile_history(source_root, independent_exal_jobs, labels[["Independent exAL"]])
  )
  independent_forecast <- rbind(
    quantile_forecast(source_root, independent_al_jobs, labels[["Independent AL"]]),
    quantile_forecast(source_root, independent_exal_jobs, labels[["Independent exAL"]])
  )
  joint_history <- rbind(
    quantile_history(continuation_root, rep(joint_al_job, length(tau_grid)), labels[["Joint AL"]]),
    quantile_history(source_root, rep(joint_exal_job, length(tau_grid)), labels[["Joint exAL"]])
  )
  joint_forecast <- rbind(
    quantile_forecast(continuation_root, joint_al_job, labels[["Joint AL"]]),
    quantile_forecast(source_root, joint_exal_job, labels[["Joint exAL"]])
  )

  model_groups <- list(
    normal = unname(labels[normal_families]),
    independent = unname(labels[c("Independent AL", "Independent exAL")]),
    joint = unname(labels[c("Joint AL", "Joint exAL")])
  )
  target_levels <- c("USGS latent path", "GloFAS - USGS discrepancy")
  context_for <- function(models) {
    history <- do.call(rbind, lapply(models, function(model) rbind(
      data.frame(model = model, target = target_levels[[1L]], target_date = panel$target_date[history_idx], value = panel$y_transformed[history_idx], series = "Observed history"),
      data.frame(model = model, target = target_levels[[1L]], target_date = panel$target_date[history_idx], value = panel$g_transformed[history_idx], series = "GloFAS retrospective"),
      data.frame(model = model, target = target_levels[[2L]], target_date = panel$target_date[history_idx], value = panel$g_transformed[history_idx] - panel$y_transformed[history_idx], series = "Observed history")
    )))
    future <- merge(truth_sidecar, ensemble_mean, by = "target_date", all = FALSE)
    future <- do.call(rbind, lapply(models, function(model) rbind(
      data.frame(model = model, target = target_levels[[1L]], target_date = future$target_date, value = future$y_transformed, series = "Withheld truth (scoring only)"),
      data.frame(model = model, target = target_levels[[2L]], target_date = future$target_date, value = future$g_transformed - future$y_transformed, series = "Withheld truth (scoring only)")
    )))
    members <- do.call(rbind, lapply(models, function(model) transform(ensemble, model = model, target = target_levels[[1L]])))
    center <- do.call(rbind, lapply(models, function(model) transform(ensemble_mean, model = model, target = target_levels[[1L]])))
    list(history = history, future = future, members = members, center = center)
  }
  base_plot <- function(models, title, subtitle) {
    context <- context_for(models)
    ggplot2::ggplot() +
      ggplot2::geom_line(data = context$members, ggplot2::aes(target_date, g_transformed, group = interaction(model, member)), color = "#A8CCD2", linewidth = 0.22, alpha = 0.25) +
      ggplot2::geom_line(data = context$center, ggplot2::aes(target_date, g_transformed), color = "#005D6A", linewidth = 0.90) +
      ggplot2::geom_line(data = context$history[context$history$series == "GloFAS retrospective", ], ggplot2::aes(target_date, value), color = "#00839B", linewidth = 0.78) +
      ggplot2::geom_line(data = context$history[context$history$series == "Observed history", ], ggplot2::aes(target_date, value), color = "#181818", linewidth = 0.86) +
      ggplot2::geom_line(data = context$future, ggplot2::aes(target_date, value), color = "#7B2C83", linewidth = 0.92, linetype = "longdash") +
      ggplot2::geom_vline(xintercept = cutoff, color = "#66727A", linetype = "dotted", linewidth = 0.55) +
      ggplot2::facet_grid(
        rows = ggplot2::vars(factor(target, levels = target_levels)),
        cols = ggplot2::vars(factor(model, levels = models)), scales = "free_y"
      ) +
      ggplot2::scale_x_date(date_breaks = "14 days", date_labels = "%b %d", limits = c(history_start, issued_end), expand = ggplot2::expansion(mult = c(0.01, 0.02))) +
      ggplot2::labs(title = title, subtitle = subtitle, x = "Date", y = NULL) +
      ggplot2::theme_minimal(base_size = 10.5) +
      ggplot2::theme(
        plot.title = ggplot2::element_text(face = "bold", size = 15, hjust = 0.5),
        plot.subtitle = ggplot2::element_text(size = 9.7, color = "#4A5560", hjust = 0.5),
        strip.text.x = ggplot2::element_text(face = "bold", size = 10.5, lineheight = 1.1),
        strip.text.y = ggplot2::element_text(face = "bold", size = 10),
        strip.background = ggplot2::element_rect(fill = "#EEF2F4", color = "#CBD4D9", linewidth = 0.4),
        panel.grid.minor = ggplot2::element_blank(), panel.grid.major.x = ggplot2::element_blank(),
        panel.grid.major.y = ggplot2::element_line(color = "#D8E0E4", linewidth = 0.32, linetype = "dotted"),
        panel.spacing = grid::unit(0.75, "lines"), legend.position = "top",
        plot.margin = ggplot2::margin(8, 12, 8, 8)
      )
  }
  normal_plot <- base_plot(
    model_groups$normal, "GloFAS Part 4: Normal model comparison",
    "Last 30 historical dates and 28 issued horizons; fitted log1p scale; black/purple lines are observed/scoring-only truth"
  ) +
    ggplot2::geom_ribbon(data = normal_forecast, ggplot2::aes(target_date, ymin = lower, ymax = upper, group = interaction(model, target)), fill = "#D98B6A", alpha = 0.18) +
    ggplot2::geom_line(data = normal_history, ggplot2::aes(target_date, value), color = "#C44E24", linewidth = 0.95, linetype = "dashed") +
    ggplot2::geom_line(data = normal_forecast, ggplot2::aes(target_date, center), color = "#C44E24", linewidth = 1.05)

  tau_colors <- c("0.05" = "#3558A6", "0.2" = "#4C86B5", "0.35" = "#45A69A", "0.5" = "#238443", "0.65" = "#C49A21", "0.8" = "#E06B26", "0.95" = "#B83242")
  quantile_plot <- function(models, history, forecast, title, subtitle) {
    base_plot(models, title, subtitle) +
      ggplot2::geom_line(data = history, ggplot2::aes(target_date, value, color = factor(quantile_level), group = interaction(model, target, quantile_level)), linewidth = 0.76, linetype = "dashed") +
      ggplot2::geom_line(data = forecast, ggplot2::aes(target_date, value, color = factor(quantile_level), group = interaction(model, target, quantile_level)), linewidth = 0.88) +
      ggplot2::scale_color_manual(values = tau_colors, name = "Quantile") +
      ggplot2::guides(color = ggplot2::guide_legend(nrow = 1, byrow = TRUE))
  }
  independent_plot <- quantile_plot(
    model_groups$independent, independent_history, independent_forecast,
    "GloFAS Part 4: independent quantile comparison",
    "AL and exAL RHS/VB fits; dashed historical fits and solid issued-window latent paths; no crossing correction"
  )
  joint_plot <- quantile_plot(
    model_groups$joint, joint_history, joint_forecast,
    "GloFAS Part 4: joint quantile comparison",
    "Joint AL uses the Sweep 10 cap-stabilized state; Joint exAL is a nonconverged sensitivity result"
  )

  dir.create(dirname(output_pdf), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(output_scores), recursive = TRUE, showWarnings = FALSE)
  grDevices::cairo_pdf(output_pdf, width = 13.5, height = 9.0, onefile = TRUE)
  print(normal_plot)
  print(independent_plot)
  print(joint_plot)
  grDevices::dev.off()
  write.csv(forecast_scores, output_scores, row.names = FALSE)
  invisible(normalizePath(output_pdf, mustWork = TRUE))
}

if (sys.nframe() == 0L) {
  script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  script_path <- sub("^--file=", "", script_arg[[1L]])
  repo_root <- normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
  source(file.path(repo_root, "application/R/00_packages.R"))
  app_set_repo_root(repo_root)
  args <- app_parse_args(list(
    source_runtime_root = "",
    continuation_runtime_root = "",
    forecast_scores = "",
    output_pdf = "",
    output_scores = ""
  ))
  required <- c("source_runtime_root", "continuation_runtime_root", "forecast_scores", "output_pdf", "output_scores")
  if (any(!nzchar(vapply(args[required], as.character, character(1L))))) {
    stop("All grouped-figure command-line paths are required.", call. = FALSE)
  }
  app_plot_glofas_part4_grouped_family_comparison(
    app_resolve_path(args$source_runtime_root, must_work = TRUE),
    app_resolve_path(args$continuation_runtime_root, must_work = TRUE),
    app_resolve_path(args$output_pdf, must_work = FALSE),
    app_resolve_path(args$output_scores, must_work = FALSE),
    read.csv(app_resolve_path(args$forecast_scores, must_work = TRUE), stringsAsFactors = FALSE)
  )
}
