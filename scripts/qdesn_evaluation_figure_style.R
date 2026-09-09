# Shared visual specification for article evaluation figures.
#
# This file contains presentation logic only.  It accepts already validated,
# tracked article summaries and does not fit a model or compute a score.

qdesn_figure_palette <- c(AL = "#1F4E79", exAL = "#8B4A3C")

qdesn_independent_model_order <- c(
  "qdesn_al_rhs_ns", "dqlm", "qdesn_exal_rhs_ns", "exdqlm"
)
qdesn_independent_model_labels <- c(
  qdesn_al_rhs_ns = "Q-DESN AL-RHS",
  dqlm = "DQLM",
  qdesn_exal_rhs_ns = "Q-DESN exAL-RHS",
  exdqlm = "exDQLM"
)
qdesn_independent_model_family <- c(
  qdesn_al_rhs_ns = "AL", dqlm = "AL",
  qdesn_exal_rhs_ns = "exAL", exdqlm = "exAL"
)
qdesn_independent_model_shape <- c(
  qdesn_al_rhs_ns = 16, dqlm = 1,
  qdesn_exal_rhs_ns = 17, exdqlm = 2
)

qdesn_joint_model_order <- c(
  "joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb",
  "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"
)
qdesn_joint_model_labels <- c(
  joint_qdesn_rhs_vb = "Joint AL",
  qdesn_rhs_independent_vb = "Independent AL",
  joint_exqdesn_rhs_vb = "Joint exAL",
  exqdesn_rhs_independent_vb = "Independent exAL"
)
qdesn_joint_model_shape <- c(
  joint_qdesn_rhs_vb = 16,
  qdesn_rhs_independent_vb = 1,
  joint_exqdesn_rhs_vb = 17,
  exqdesn_rhs_independent_vb = 2
)

qdesn_family_labels <- c(
  normal = "Gaussian", laplace = "Laplace",
  gausmix = "Gaussian mixture"
)
qdesn_scenario_order <- c(
  "asymmetric_laplace_tail", "gaussian_mixture_bridge", "laplace_bridge",
  "nonlinear_reservoir_friendly", "normal_bridge", "persistent_heavy_tail",
  "regime_shift", "student_t_location_scale"
)
qdesn_scenario_labels <- c(
  asymmetric_laplace_tail = "Asymmetric-Laplace tail",
  gaussian_mixture_bridge = "Gaussian-mixture innovations",
  laplace_bridge = "Laplace innovations",
  nonlinear_reservoir_friendly = "Nonlinear reservoir dynamics",
  normal_bridge = "Gaussian innovations",
  persistent_heavy_tail = "Persistent heavy tails",
  regime_shift = "Regime shift",
  student_t_location_scale = "Student-t location-scale"
)

qdesn_panel_prefix <- function(labels) {
  letters <- LETTERS[seq_along(labels)]
  stats::setNames(paste0(letters, "  ", unname(labels)), names(labels))
}

qdesn_save_vector_pdf <- function(path, plot, width, height) {
  if (!isTRUE(capabilities("cairo"))) {
    stop("Cairo graphics support is required for vector article figures.",
         call. = FALSE)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  grDevices::cairo_pdf(
    filename = path, width = width, height = height,
    family = "sans", bg = "white", onefile = TRUE
  )
  on.exit(grDevices::dev.off(), add = TRUE)
  print(plot)
  invisible(path)
}

qdesn_independent_interval_plot <- function(data, inference, metric_role) {
  stopifnot(requireNamespace("ggplot2", quietly = TRUE))
  block <- data[
    data$inference == inference & data$metric_role == metric_role, , drop = FALSE
  ]
  if (nrow(block) != 36L) {
    stop("An independent interval figure must contain 36 model cells.",
         call. = FALSE)
  }

  family_order <- names(qdesn_family_labels)
  tau_order <- sort(unique(block$tau))
  panel_keys <- unlist(lapply(family_order, function(family) {
    paste(family, sprintf("%.2f", tau_order), sep = "|")
  }), use.names = FALSE)
  panel_text <- unlist(lapply(family_order, function(family) {
    paste0(qdesn_family_labels[[family]], "\np = ", sprintf("%.2f", tau_order))
  }), use.names = FALSE)
  names(panel_text) <- panel_keys
  panel_text <- qdesn_panel_prefix(panel_text)

  block$panel_key <- paste(block$family, sprintf("%.2f", block$tau), sep = "|")
  block$panel_key <- factor(block$panel_key, levels = panel_keys)
  block$model_variant <- factor(
    block$model_variant, levels = rev(qdesn_independent_model_order)
  )
  block$likelihood_family <- unname(
    qdesn_independent_model_family[as.character(block$model_variant)]
  )

  references <- unique(block[c("panel_key", "plot_reference_value")])

  metric_labels <- c(
    fit_rmse = "Fitting-sample quantile-path RMSE",
    forecast_mae = "Forecast quantile-path MAE",
    forecast_check = "Forecast check loss"
  )

  plot <- ggplot2::ggplot(block, ggplot2::aes(y = model_variant)) +
    ggplot2::geom_vline(
      data = references,
      ggplot2::aes(xintercept = plot_reference_value),
      inherit.aes = FALSE, colour = "#4A4A4A", linetype = "22",
      linewidth = 0.42
    ) +
    ggplot2::geom_segment(
      ggplot2::aes(
        x = cri_lower, xend = cri_upper, yend = model_variant,
        colour = likelihood_family
      ), linewidth = 0.62
    ) +
    ggplot2::geom_point(
      ggplot2::aes(
        x = posterior_mean, colour = likelihood_family, shape = model_variant
      ), size = 2.25, stroke = 0.78
    ) +
    ggplot2::facet_wrap(
      ~panel_key, ncol = 3L, scales = "free_x",
      labeller = ggplot2::as_labeller(panel_text)
    ) +
    ggplot2::scale_y_discrete(labels = qdesn_independent_model_labels) +
    ggplot2::scale_colour_manual(values = qdesn_figure_palette, drop = FALSE) +
    ggplot2::scale_shape_manual(values = qdesn_independent_model_shape) +
    ggplot2::scale_x_continuous(
      breaks = function(limits) pretty(limits, n = 3L),
      labels = function(x) formatC(x, format = "f", digits = 2),
      expand = ggplot2::expansion(mult = c(0.04, 0.04))
    ) +
    ggplot2::labs(x = unname(metric_labels[[metric_role]]), y = NULL) +
    ggplot2::coord_cartesian(clip = "on") +
    ggplot2::theme_bw(base_size = 8.5, base_family = "sans") +
    ggplot2::theme(
      legend.position = "none",
      panel.grid.major.y = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_line(
        colour = "#E1E3E5", linewidth = 0.28
      ),
      strip.background = ggplot2::element_rect(
        fill = "#F1F2F3", colour = "#777777", linewidth = 0.35
      ),
      strip.text = ggplot2::element_text(
        face = "bold", size = 8.0, lineheight = 0.95
      ),
      axis.text.x = ggplot2::element_text(size = 7.4),
      axis.text.y = ggplot2::element_text(size = 7.3, colour = "#242424"),
      axis.title.x = ggplot2::element_text(size = 8.3),
      panel.spacing = grid::unit(0.95, "lines"),
      plot.margin = ggplot2::margin(5.5, 7.5, 5.5, 5.5)
    )
  plot
}

qdesn_joint_interval_plot <- function(data, xlab, oracle_lines = NULL) {
  stopifnot(requireNamespace("ggplot2", quietly = TRUE))
  if (nrow(data) != 32L) {
    stop("A joint interval figure must contain 32 model cells.", call. = FALSE)
  }
  panel_labels <- qdesn_panel_prefix(
    qdesn_scenario_labels[qdesn_scenario_order]
  )
  data$scenario_id <- factor(data$scenario_id, levels = qdesn_scenario_order)
  data$source_model_id <- factor(
    data$source_model_id, levels = rev(qdesn_joint_model_order)
  )
  limits <- lapply(split(data, data$scenario_id, drop = TRUE), function(block) {
    span <- max(block$hi) - min(block$lo)
    if (!is.finite(span) || span <= 0) span <- max(abs(block$hi), 1) * 0.1
    data.frame(
      scenario_id = block$scenario_id[[1L]],
      label_x = max(block$hi) + 0.18 * span
    )
  })
  limits <- do.call(rbind, limits)
  data <- merge(data, limits, by = "scenario_id", all.x = TRUE, sort = FALSE)
  data$scenario_id <- factor(data$scenario_id, levels = qdesn_scenario_order)
  data$source_model_id <- factor(
    data$source_model_id, levels = rev(qdesn_joint_model_order)
  )

  plot <- ggplot2::ggplot(data, ggplot2::aes(y = source_model_id)) +
    ggplot2::geom_segment(
      ggplot2::aes(
        x = lo, xend = hi, yend = source_model_id,
        colour = likelihood_family
      ), linewidth = 0.62
    ) +
    ggplot2::geom_point(
      ggplot2::aes(
        x = mean, colour = likelihood_family, shape = source_model_id
      ), size = 2.25, stroke = 0.78
    ) +
    ggplot2::geom_text(
      ggplot2::aes(x = label_x, label = paste0("c = ", crossing)),
      hjust = 1, size = 2.35, colour = "#404040"
    ) +
    ggplot2::facet_wrap(
      ~scenario_id, ncol = 2L, scales = "free_x",
      labeller = ggplot2::as_labeller(panel_labels)
    ) +
    ggplot2::scale_y_discrete(labels = qdesn_joint_model_labels) +
    ggplot2::scale_colour_manual(values = qdesn_figure_palette, drop = FALSE) +
    ggplot2::scale_shape_manual(values = qdesn_joint_model_shape) +
    ggplot2::scale_x_continuous(
      breaks = function(limits) pretty(limits, n = 3L),
      labels = function(x) formatC(x, format = "f", digits = 2),
      expand = ggplot2::expansion(mult = c(0.04, 0.08))
    ) +
    ggplot2::labs(x = xlab, y = NULL) +
    ggplot2::coord_cartesian(clip = "on") +
    ggplot2::theme_bw(base_size = 8.5, base_family = "sans") +
    ggplot2::theme(
      legend.position = "none",
      panel.grid.major.y = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_line(
        colour = "#E1E3E5", linewidth = 0.28
      ),
      strip.background = ggplot2::element_rect(
        fill = "#F1F2F3", colour = "#777777", linewidth = 0.35
      ),
      strip.text = ggplot2::element_text(face = "bold", size = 8.0),
      axis.text.x = ggplot2::element_text(size = 7.4),
      axis.text.y = ggplot2::element_text(size = 7.3, colour = "#242424"),
      axis.title.x = ggplot2::element_text(size = 8.3),
      panel.spacing = grid::unit(0.9, "lines"),
      plot.margin = ggplot2::margin(5.5, 7.5, 5.5, 5.5)
    )

  if (!is.null(oracle_lines)) {
    oracle_lines$scenario_id <- factor(
      oracle_lines$scenario_id, levels = qdesn_scenario_order
    )
    plot <- plot + ggplot2::geom_vline(
      data = oracle_lines,
      ggplot2::aes(xintercept = oracle),
      inherit.aes = FALSE, colour = "#4A4A4A", linetype = "22",
      linewidth = 0.42
    )
  }
  plot
}
