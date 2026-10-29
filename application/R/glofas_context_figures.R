# Cutoff-context figures for an authoritative GloFAS Q-DESN synthesis.

app_context_require_columns <- function(x, required, label) {
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(sprintf("%s is missing required columns: %s", label, paste(missing, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}

app_context_transform <- function(x, transform = "log1p") {
  x <- suppressWarnings(as.numeric(x))
  if (identical(transform, "identity")) return(x)
  if (identical(transform, "log1p")) return(log1p(pmax(x, 0)))
  stop(sprintf("Unsupported context-figure transform '%s'.", transform), call. = FALSE)
}

app_context_quantile_name <- function(tau) {
  paste0("q", sprintf("%02d", as.integer(round(100 * tau))))
}

app_context_complete_grid <- function(x, row_col, column_col, label) {
  key <- paste(x[[row_col]], x[[column_col]], sep = "|")
  if (anyDuplicated(key)) {
    stop(sprintf("%s contains duplicate %s-by-%s rows.", label, row_col, column_col), call. = FALSE)
  }
  expected <- length(unique(x[[row_col]])) * length(unique(x[[column_col]]))
  if (nrow(x) != expected) {
    stop(sprintf("%s is incomplete: expected %d rows but found %d.", label, expected, nrow(x)), call. = FALSE)
  }
  invisible(TRUE)
}

app_context_make_bands <- function(quantile_paths) {
  dates <- sort(unique(quantile_paths$date))
  out <- data.frame(date = dates, stringsAsFactors = FALSE)
  for (tau in sort(unique(quantile_paths$quantile_level))) {
    one <- quantile_paths[abs(quantile_paths$quantile_level - tau) < 1e-10, c("date", "qdesn"), drop = FALSE]
    names(one)[[2L]] <- app_context_quantile_name(tau)
    out <- merge(out, one, by = "date", all.x = TRUE, sort = TRUE)
  }
  out$phase <- ifelse(out$date <= unique(quantile_paths$cutoff_date), "Fitted history", "Forecast")
  out$cutoff_date <- unique(quantile_paths$cutoff_date)
  out
}

app_prepare_glofas_cutoff_context <- function(
  predictions,
  observed_history,
  reference,
  retrospective,
  ensemble,
  history_observations = 60L,
  expected_members = 51L,
  candidate_id = NULL,
  transform = "log1p",
  tolerance = 1e-8
) {
  history_observations <- as.integer(history_observations)
  expected_members <- as.integer(expected_members)
  if (!is.finite(history_observations) || history_observations < 1L) {
    stop("history_observations must be a positive integer.", call. = FALSE)
  }
  if (!is.finite(expected_members) || expected_members < 1L) {
    stop("expected_members must be a positive integer.", call. = FALSE)
  }

  app_context_require_columns(
    predictions,
    c("model_family", "origin_date", "target_date", "quantile_level", "qhat"),
    "forecast predictions"
  )
  app_context_require_columns(
    observed_history,
    c("candidate_id", "target_date", "cutoff_date", "quantile_level", "y_log1p"),
    "observed-history quantiles"
  )
  app_context_require_columns(reference, c("date", "streamflow"), "reference gauge")
  app_context_require_columns(retrospective, c("date", "glofas_streamflow"), "GloFAS retrospective")
  app_context_require_columns(
    ensemble,
    c("origin_date", "target_date", "horizon", "member", "glofas_streamflow"),
    "GloFAS ensemble"
  )

  predictions$origin_date <- as.Date(predictions$origin_date)
  predictions$target_date <- as.Date(predictions$target_date)
  predictions$quantile_level <- suppressWarnings(as.numeric(predictions$quantile_level))
  observed_history$target_date <- as.Date(observed_history$target_date)
  observed_history$cutoff_date <- as.Date(observed_history$cutoff_date)
  observed_history$quantile_level <- suppressWarnings(as.numeric(observed_history$quantile_level))
  reference$date <- as.Date(reference$date)
  retrospective$date <- as.Date(retrospective$date)
  ensemble$origin_date <- as.Date(ensemble$origin_date)
  ensemble$target_date <- as.Date(ensemble$target_date)
  ensemble$horizon <- suppressWarnings(as.integer(ensemble$horizon))

  forecast <- predictions[predictions$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  raw <- predictions[predictions$model_family == "raw_glofas", , drop = FALSE]
  if (!nrow(forecast)) stop("No Q-DESN discrepancy forecast rows were found.", call. = FALSE)
  origins <- unique(na.omit(forecast$origin_date))
  if (length(origins) != 1L) stop("The context figure requires exactly one forecast origin.", call. = FALSE)
  cutoff <- origins[[1L]]
  forecast <- forecast[forecast$origin_date == cutoff & forecast$target_date > cutoff, , drop = FALSE]
  raw <- raw[raw$origin_date == cutoff & raw$target_date > cutoff, , drop = FALSE]
  q_col <- if ("qhat_monotone" %in% names(forecast)) "qhat_monotone" else "qhat"
  forecast$qdesn <- suppressWarnings(as.numeric(forecast[[q_col]]))
  forecast_levels <- sort(unique(forecast$quantile_level))
  if (length(forecast_levels) < 3L || any(!is.finite(forecast_levels))) {
    stop("Forecast quantile levels are missing or invalid.", call. = FALSE)
  }
  app_context_complete_grid(forecast, "target_date", "quantile_level", "Q-DESN forecast quantiles")
  if (any(!is.finite(forecast$qdesn))) stop("Q-DESN forecast quantiles contain non-finite values.", call. = FALSE)
  forecast_crossing <- vapply(split(forecast, forecast$target_date), function(one) {
    one <- one[order(one$quantile_level), , drop = FALSE]
    any(diff(one$qdesn) < -tolerance)
  }, logical(1L))
  if (any(forecast_crossing)) stop("Monotone forecast quantiles cross for at least one target date.", call. = FALSE)

  if (!is.null(candidate_id) && nzchar(as.character(candidate_id)[[1L]])) {
    observed_history <- observed_history[observed_history$candidate_id == as.character(candidate_id)[[1L]], , drop = FALSE]
  }
  candidates <- unique(observed_history$candidate_id)
  if (length(candidates) != 1L) {
    stop(sprintf("Observed-history input must identify one candidate; found: %s", paste(candidates, collapse = ", ")), call. = FALSE)
  }
  observed_history <- observed_history[observed_history$cutoff_date == cutoff & observed_history$target_date <= cutoff, , drop = FALSE]
  if (!nrow(observed_history)) stop("No observed-history quantiles match the forecast origin.", call. = FALSE)
  history_levels <- sort(unique(observed_history$quantile_level))
  if (!isTRUE(all.equal(history_levels, forecast_levels, tolerance = tolerance))) {
    stop("Historical and forecast quantile grids do not match.", call. = FALSE)
  }
  history_q_col <- if ("qhat_isotonic" %in% names(observed_history)) {
    "qhat_isotonic"
  } else if ("qhat_log1p" %in% names(observed_history)) {
    "qhat_log1p"
  } else {
    stop("Observed-history input has neither qhat_isotonic nor qhat_log1p.", call. = FALSE)
  }
  observed_history$qdesn <- suppressWarnings(as.numeric(observed_history[[history_q_col]]))
  available_dates <- sort(unique(observed_history$target_date[is.finite(observed_history$y_log1p)]))
  if (length(available_dates) < history_observations) {
    stop(sprintf("Only %d historical observations are available; %d were requested.", length(available_dates), history_observations), call. = FALSE)
  }
  history_dates <- tail(available_dates, history_observations)
  if (max(history_dates) != cutoff) stop("The historical context does not end exactly at the forecast origin.", call. = FALSE)
  history <- observed_history[observed_history$target_date %in% history_dates, , drop = FALSE]
  app_context_complete_grid(history, "target_date", "quantile_level", "Q-DESN historical quantiles")
  if (any(!is.finite(history$qdesn))) stop("Historical Q-DESN quantiles contain non-finite values.", call. = FALSE)
  history_crossing <- vapply(split(history, history$target_date), function(one) {
    one <- one[order(one$quantile_level), , drop = FALSE]
    any(diff(one$qdesn) < -tolerance)
  }, logical(1L))
  if (any(history_crossing)) stop("Monotone historical quantiles cross for at least one date.", call. = FALSE)
  history_source_columns <- intersect(
    c(
      "candidate_id", "target_date", "cutoff_date", "y_log1p", "qhat_log1p",
      "raw_log1p", "quantile_id", "quantile_level", "qhat_independent",
      "qhat_isotonic", "isotonic_abs_adjustment"
    ),
    names(history)
  )
  history_source <- history[, history_source_columns, drop = FALSE]
  history_source <- history_source[order(history_source$target_date, history_source$quantile_level), , drop = FALSE]

  reference_context <- reference[reference$date %in% c(history_dates, sort(unique(forecast$target_date))), c("date", "streamflow"), drop = FALSE]
  reference_context$value <- app_context_transform(reference_context$streamflow, transform)
  reference_context$phase <- ifelse(reference_context$date <= cutoff, "Observed", "Held out")
  reference_context <- reference_context[order(reference_context$date), , drop = FALSE]
  history_reference <- reference_context[reference_context$date %in% history_dates, , drop = FALSE]
  future_reference <- reference_context[reference_context$date %in% unique(forecast$target_date), , drop = FALSE]
  if (nrow(history_reference) != history_observations || any(!is.finite(history_reference$value))) {
    stop("The frozen reference gauge does not contain the requested 60-observation context.", call. = FALSE)
  }
  if (nrow(future_reference) != length(unique(forecast$target_date)) || any(!is.finite(future_reference$value))) {
    stop("The frozen reference gauge does not contain every held-out forecast target.", call. = FALSE)
  }
  history_y <- unique(history[, c("target_date", "y_log1p"), drop = FALSE])
  names(history_y) <- c("date", "history_value")
  history_match <- merge(history_reference[, c("date", "value"), drop = FALSE], history_y, by = "date", all = TRUE)
  if (nrow(history_match) != history_observations || max(abs(history_match$value - history_match$history_value), na.rm = TRUE) > tolerance) {
    stop("Observed-history responses do not match the frozen reference gauge on the transformed scale.", call. = FALSE)
  }

  retrospective_context <- retrospective[retrospective$date %in% history_dates, c("date", "glofas_streamflow"), drop = FALSE]
  retrospective_context$value <- app_context_transform(retrospective_context$glofas_streamflow, transform)
  retrospective_context <- retrospective_context[order(retrospective_context$date), , drop = FALSE]
  if (nrow(retrospective_context) != history_observations || any(!is.finite(retrospective_context$value))) {
    stop("The GloFAS retrospective does not contain the requested historical context.", call. = FALSE)
  }

  forecast_dates <- sort(unique(forecast$target_date))
  ensemble_context <- ensemble[
    ensemble$origin_date == cutoff & ensemble$target_date %in% forecast_dates,
    c("origin_date", "target_date", "horizon", "member", "glofas_streamflow"),
    drop = FALSE
  ]
  ensemble_context$value <- app_context_transform(ensemble_context$glofas_streamflow, transform)
  members <- sort(unique(as.character(ensemble_context$member)))
  if (length(members) != expected_members) {
    stop(sprintf("Expected %d GloFAS members but found %d.", expected_members, length(members)), call. = FALSE)
  }
  app_context_complete_grid(ensemble_context, "target_date", "member", "GloFAS ensemble")
  if (any(!is.finite(ensemble_context$value))) stop("GloFAS ensemble values contain non-finite values.", call. = FALSE)
  expected_horizon <- as.integer(ensemble_context$target_date - ensemble_context$origin_date)
  if (any(ensemble_context$horizon != expected_horizon)) stop("GloFAS ensemble horizons are inconsistent with their target dates.", call. = FALSE)
  ensemble_summary <- do.call(rbind, lapply(split(ensemble_context, ensemble_context$target_date), function(one) {
    data.frame(
      target_date = unique(one$target_date),
      horizon = unique(one$horizon),
      median = stats::median(one$value),
      q05 = stats::quantile(one$value, 0.05, names = FALSE),
      q95 = stats::quantile(one$value, 0.95, names = FALSE),
      n_members = nrow(one),
      stringsAsFactors = FALSE
    )
  }))
  ensemble_summary <- ensemble_summary[order(ensemble_summary$target_date), , drop = FALSE]
  raw_p50 <- raw[abs(raw$quantile_level - 0.5) < tolerance, , drop = FALSE]
  raw_col <- if ("qhat_monotone" %in% names(raw_p50)) "qhat_monotone" else "qhat"
  raw_p50$raw_p50 <- suppressWarnings(as.numeric(raw_p50[[raw_col]]))
  median_check <- merge(
    ensemble_summary[, c("target_date", "median"), drop = FALSE],
    raw_p50[, c("target_date", "raw_p50"), drop = FALSE],
    by = "target_date",
    all = TRUE
  )
  if (nrow(median_check) != length(forecast_dates) || any(!is.finite(median_check$raw_p50)) ||
      max(abs(median_check$median - median_check$raw_p50), na.rm = TRUE) > tolerance) {
    stop("The direct GloFAS member median does not match the stored raw-GloFAS p50 path.", call. = FALSE)
  }

  history_paths <- data.frame(
    date = history$target_date,
    quantile_level = history$quantile_level,
    qdesn = history$qdesn,
    phase = "Fitted history",
    cutoff_date = cutoff,
    stringsAsFactors = FALSE
  )
  forecast_paths <- data.frame(
    date = forecast$target_date,
    quantile_level = forecast$quantile_level,
    qdesn = forecast$qdesn,
    phase = "Forecast",
    cutoff_date = cutoff,
    stringsAsFactors = FALSE
  )
  quantile_paths <- rbind(history_paths, forecast_paths)
  quantile_paths <- quantile_paths[order(quantile_paths$quantile_level, quantile_paths$date), , drop = FALSE]
  bands <- app_context_make_bands(quantile_paths)
  required_bands <- app_context_quantile_name(c(0.05, 0.15, 0.35, 0.50, 0.65, 0.80, 0.95))
  if (!all(required_bands %in% names(bands))) {
    stop(sprintf("The context bands require quantiles %s.", paste(required_bands, collapse = ", ")), call. = FALSE)
  }

  audit <- data.frame(
    check = c(
      "single_forecast_origin",
      "history_ends_at_cutoff",
      "history_observation_count",
      "historical_quantile_grid_complete",
      "forecast_quantile_grid_complete",
      "quantile_levels_match",
      "quantiles_are_monotone",
      "reference_history_matches_fit_input",
      "glofas_retrospective_complete",
      "ensemble_member_count",
      "ensemble_grid_complete",
      "ensemble_median_matches_raw_p50",
      "heldout_reference_complete"
    ),
    passed = TRUE,
    detail = c(
      as.character(cutoff),
      as.character(max(history_dates)),
      sprintf("%d observations", length(history_dates)),
      sprintf("%d dates x %d quantiles", length(history_dates), length(history_levels)),
      sprintf("%d dates x %d quantiles", length(forecast_dates), length(forecast_levels)),
      paste(format(forecast_levels, trim = TRUE), collapse = ", "),
      "historical and forecast monotone paths",
      sprintf("maximum absolute difference %.3g", max(abs(history_match$value - history_match$history_value))),
      sprintf("%d retrospective values", nrow(retrospective_context)),
      sprintf("%d members", length(members)),
      sprintf("%d member-target rows", nrow(ensemble_context)),
      sprintf("maximum absolute difference %.3g", max(abs(median_check$median - median_check$raw_p50))),
      sprintf("%d held-out observations", nrow(future_reference))
    ),
    stringsAsFactors = FALSE
  )

  list(
    cutoff_date = cutoff,
    candidate_id = candidates[[1L]],
    transform = transform,
    quantile_levels = forecast_levels,
    observed_history_source = history_source,
    quantile_paths = quantile_paths,
    bands = bands,
    reference = reference_context,
    retrospective = retrospective_context,
    ensemble = ensemble_context,
    ensemble_summary = ensemble_summary,
    audit = audit
  )
}

app_glofas_context_theme <- function() {
  ggplot2::theme_minimal(base_size = 10.5) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 12),
      plot.subtitle = ggplot2::element_text(size = 9.4, color = "#4B5563"),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_blank(),
      axis.title = ggplot2::element_text(size = 10),
      legend.position = "bottom",
      legend.box = "vertical",
      legend.title = ggplot2::element_text(face = "bold", size = 9),
      legend.text = ggplot2::element_text(size = 8.2),
      plot.margin = ggplot2::margin(8, 12, 6, 8)
    )
}

app_glofas_context_source_levels <- function(n_members) {
  c(
    "USGS observed",
    "USGS held out",
    "GloFAS retrospective",
    sprintf("GloFAS forecast members (n=%d)", n_members),
    "GloFAS ensemble median"
  )
}

app_glofas_context_add_sources <- function(p, context, include_qdesn_median = FALSE) {
  data_levels <- app_glofas_context_source_levels(length(unique(context$ensemble$member)))
  data_colors <- c("#111827", "#C62828", "#B26A00", "#A8B0B8", "#59636E")
  data_linetypes <- c("solid", "solid", "solid", "solid", "22")
  data_widths <- c(1.0, 0.75, 0.8, 0.55, 0.9)
  source_levels <- data_levels
  source_colors <- data_colors
  source_linetypes <- data_linetypes
  source_widths <- data_widths
  if (isTRUE(include_qdesn_median)) {
    source_levels <- c("Q-DESN median", source_levels)
    source_colors <- c("#145DA0", source_colors)
    source_linetypes <- c("solid", source_linetypes)
    source_widths <- c(1.05, source_widths)
  }
  history_ref <- context$reference[context$reference$phase == "Observed", , drop = FALSE]
  future_ref <- context$reference[context$reference$phase == "Held out", , drop = FALSE]
  member_label <- data_levels[[4L]]
  p <- p +
    ggplot2::geom_line(
      data = context$ensemble,
      ggplot2::aes(x = target_date, y = value, group = member, linetype = member_label),
      color = data_colors[[4L]], linewidth = 0.28, alpha = 0.42
    ) +
    ggplot2::geom_line(
      data = context$retrospective,
      ggplot2::aes(x = date, y = value, linetype = "GloFAS retrospective"),
      color = data_colors[[3L]], linewidth = 0.8
    ) +
    ggplot2::geom_line(
      data = context$ensemble_summary,
      ggplot2::aes(x = target_date, y = median, linetype = "GloFAS ensemble median"),
      color = data_colors[[5L]], linewidth = 0.9
    ) +
    ggplot2::geom_line(
      data = history_ref,
      ggplot2::aes(x = date, y = value, linetype = "USGS observed"),
      color = data_colors[[1L]], linewidth = 1.0
    ) +
    ggplot2::geom_line(
      data = future_ref,
      ggplot2::aes(x = date, y = value, linetype = "USGS held out"),
      color = data_colors[[2L]], linewidth = 0.75
    ) +
    ggplot2::geom_point(
      data = future_ref,
      ggplot2::aes(x = date, y = value),
      color = data_colors[[2L]], size = 1.35, shape = 16
    ) +
    ggplot2::scale_linetype_manual(
      name = "Data source",
      breaks = source_levels,
      limits = source_levels,
      values = stats::setNames(source_linetypes, source_levels),
      drop = FALSE
    ) +
    ggplot2::guides(
      linetype = ggplot2::guide_legend(
        order = 3,
        nrow = 2,
        byrow = TRUE,
        override.aes = list(color = source_colors, linewidth = source_widths, alpha = 1)
      )
    )
  p
}

app_plot_glofas_context_quantile_paths <- function(context, path) {
  app_require_namespace("ggplot2")
  app_ensure_dir(dirname(path))
  q_levels <- sort(unique(context$quantile_paths$quantile_level))
  q_labels <- paste0("p", sprintf("%02d", round(100 * q_levels)))
  q_palette <- stats::setNames(grDevices::hcl.colors(length(q_levels), "Dark 3"), q_labels)
  paths <- context$quantile_paths
  paths$quantile <- factor(paste0("p", sprintf("%02d", round(100 * paths$quantile_level))), levels = q_labels)
  paths$line_width <- ifelse(abs(paths$quantile_level - 0.5) < 1e-10, 1.05, 0.72)
  date_limits <- range(c(context$reference$date, context$ensemble$target_date))

  p <- ggplot2::ggplot() +
    ggplot2::geom_vline(
      data = data.frame(cutoff_date = context$cutoff_date),
      ggplot2::aes(xintercept = cutoff_date),
      color = "#374151",
      linetype = "33",
      linewidth = 0.65
    )
  p <- app_glofas_context_add_sources(p, context)
  p <- p +
    ggplot2::geom_line(
      data = paths,
      ggplot2::aes(x = date, y = qdesn, color = quantile, group = quantile, linewidth = line_width),
      alpha = 0.96
    ) +
    ggplot2::scale_linewidth_identity() +
    ggplot2::scale_color_manual(name = "Q-DESN quantile", values = q_palette, drop = FALSE) +
    ggplot2::scale_x_date(date_breaks = "2 weeks", date_labels = "%b %d", limits = date_limits, expand = ggplot2::expansion(mult = c(0.01, 0.025))) +
    ggplot2::labs(
      title = "Q-DESN quantile paths around the forecast origin",
      subtitle = sprintf("Last 60 observed dates and %d issued forecast dates; all %d GloFAS members are shown", length(unique(context$ensemble$target_date)), length(unique(context$ensemble$member))),
      x = NULL,
      y = "Transformed streamflow, log(1 + flow)"
    ) +
    app_glofas_context_theme() +
    ggplot2::guides(color = ggplot2::guide_legend(order = 1, nrow = 1, byrow = TRUE, override.aes = list(linewidth = 1.2)))
  p <- p + ggplot2::annotate(
    "text",
    x = context$cutoff_date,
    y = Inf,
    label = "Forecast origin",
    vjust = 1.4,
    hjust = -0.08,
    size = 3.0,
    color = "#374151"
  )
  ggplot2::ggsave(path, p, width = 9.4, height = 5.8, units = "in", device = grDevices::cairo_pdf)
  invisible(path)
}

app_plot_glofas_context_bands <- function(context, path) {
  app_require_namespace("ggplot2")
  app_ensure_dir(dirname(path))
  bands <- context$bands
  date_limits <- range(c(context$reference$date, context$ensemble$target_date))
  interval_levels <- c("90% Q-DESN interval", "65% Q-DESN interval", "30% Q-DESN interval")

  p <- ggplot2::ggplot() +
    ggplot2::geom_vline(
      data = data.frame(cutoff_date = context$cutoff_date),
      ggplot2::aes(xintercept = cutoff_date),
      color = "#374151",
      linetype = "33",
      linewidth = 0.65
    ) +
    ggplot2::geom_ribbon(
      data = bands,
      ggplot2::aes(x = date, ymin = q05, ymax = q95, fill = "90% Q-DESN interval"),
      alpha = 0.62
    ) +
    ggplot2::geom_ribbon(
      data = bands,
      ggplot2::aes(x = date, ymin = q15, ymax = q80, fill = "65% Q-DESN interval"),
      alpha = 0.72
    ) +
    ggplot2::geom_ribbon(
      data = bands,
      ggplot2::aes(x = date, ymin = q35, ymax = q65, fill = "30% Q-DESN interval"),
      alpha = 0.82
    ) +
    ggplot2::scale_fill_manual(
      name = "Synthesized distribution",
      breaks = interval_levels,
      values = c("90% Q-DESN interval" = "#DCEAF7", "65% Q-DESN interval" = "#A8C8E5", "30% Q-DESN interval" = "#5D96C8"),
      drop = FALSE
    ) +
    ggplot2::scale_x_date(date_breaks = "2 weeks", date_labels = "%b %d", limits = date_limits, expand = ggplot2::expansion(mult = c(0.01, 0.025))) +
    ggplot2::labs(
      title = "Synthesized Q-DESN distribution around the forecast origin",
      subtitle = sprintf("Fitted distribution for 60 observed dates and forecast distribution for %d dates, with all %d GloFAS members", length(unique(context$ensemble$target_date)), length(unique(context$ensemble$member))),
      x = NULL,
      y = "Transformed streamflow, log(1 + flow)"
    ) +
    app_glofas_context_theme() +
    ggplot2::guides(fill = ggplot2::guide_legend(order = 1, nrow = 1, byrow = TRUE))
  p <- app_glofas_context_add_sources(p, context, include_qdesn_median = TRUE)
  p <- p +
    ggplot2::geom_line(
      data = bands,
      ggplot2::aes(x = date, y = q50, linetype = "Q-DESN median"),
      color = "#145DA0",
      linewidth = 1.05
    ) +
    ggplot2::annotate(
      "text",
      x = context$cutoff_date,
      y = Inf,
      label = "Forecast origin",
      vjust = 1.4,
      hjust = -0.08,
      size = 3.0,
      color = "#374151"
    )
  ggplot2::ggsave(path, p, width = 9.4, height = 6.4, units = "in", device = grDevices::cairo_pdf)
  invisible(path)
}

app_prepare_glofas_discrepancy_context <- function(
  discrepancy,
  cutoff_date,
  history_observations = 60L,
  expected_forecast_dates = NULL
) {
  app_context_require_columns(
    discrepancy,
    c(
      "quantile_id", "quantile_level", "target_date", "phase", "correction",
      "observed_discrepancy", "estimate"
    ),
    "discrepancy trace"
  )
  cutoff_date <- as.Date(cutoff_date)
  history_observations <- as.integer(history_observations)
  discrepancy$target_date <- as.Date(discrepancy$target_date)
  discrepancy$quantile_level <- suppressWarnings(as.numeric(discrepancy$quantile_level))
  discrepancy$observed_discrepancy <- suppressWarnings(as.numeric(discrepancy$observed_discrepancy))
  discrepancy$estimate <- suppressWarnings(as.numeric(discrepancy$estimate))
  corrections <- c("independent_fit", "monotone_implied")
  discrepancy <- discrepancy[discrepancy$correction %in% corrections, , drop = FALSE]
  if (!nrow(discrepancy)) stop("No independent or monotone-implied discrepancy traces were found.", call. = FALSE)

  pre_dates <- sort(unique(discrepancy$target_date[
    discrepancy$phase == "pre_cutoff_history" & discrepancy$target_date <= cutoff_date
  ]))
  if (length(pre_dates) < history_observations) {
    stop(sprintf("Only %d pre-cutoff discrepancy dates are available; %d were requested.", length(pre_dates), history_observations), call. = FALSE)
  }
  pre_dates <- tail(pre_dates, history_observations)
  if (max(pre_dates) != cutoff_date) stop("The discrepancy history does not end exactly at the cutoff.", call. = FALSE)
  forecast_dates <- sort(unique(discrepancy$target_date[
    discrepancy$phase == "post_cutoff_forecast" & discrepancy$target_date > cutoff_date
  ]))
  if (!is.null(expected_forecast_dates)) {
    expected_forecast_dates <- sort(as.Date(expected_forecast_dates))
    if (!identical(as.character(forecast_dates), as.character(expected_forecast_dates))) {
      stop("Discrepancy forecast dates do not match the authoritative forecast context.", call. = FALSE)
    }
  }
  keep_dates <- c(pre_dates, forecast_dates)
  trace <- discrepancy[discrepancy$target_date %in% keep_dates, , drop = FALSE]
  levels <- sort(unique(trace$quantile_level))
  if (length(levels) != 7L || any(!is.finite(levels))) {
    stop(sprintf("Expected seven finite discrepancy quantiles but found %d.", length(levels)), call. = FALSE)
  }
  for (correction in corrections) {
    one <- trace[trace$correction == correction, , drop = FALSE]
    app_context_complete_grid(one, "target_date", "quantile_level", sprintf("%s discrepancy trace", correction))
  }
  if (any(!is.finite(trace$observed_discrepancy)) || any(!is.finite(trace$estimate))) {
    stop("Discrepancy context contains non-finite observed or estimated values.", call. = FALSE)
  }
  duplicate_check <- merge(
    trace[trace$correction == "independent_fit", c("target_date", "quantile_level", "observed_discrepancy"), drop = FALSE],
    trace[trace$correction == "monotone_implied", c("target_date", "quantile_level", "observed_discrepancy"), drop = FALSE],
    by = c("target_date", "quantile_level"),
    suffixes = c("_independent", "_monotone")
  )
  observed_difference <- max(abs(
    duplicate_check$observed_discrepancy_independent - duplicate_check$observed_discrepancy_monotone
  ))
  if (!is.finite(observed_difference) || observed_difference > 1e-12) {
    stop("Observed discrepancy differs between correction representations.", call. = FALSE)
  }
  trace$quantile_label <- factor(
    paste0("p", sprintf("%02d", round(100 * trace$quantile_level))),
    levels = paste0("p", sprintf("%02d", round(100 * levels)))
  )
  trace <- trace[order(trace$quantile_level, trace$target_date, trace$correction), , drop = FALSE]
  audit <- data.frame(
    check = c(
      "history_ends_at_cutoff",
      "history_observation_count",
      "forecast_dates_match_context",
      "seven_quantile_levels",
      "independent_trace_complete",
      "monotone_trace_complete",
      "observed_trace_agrees_across_representations",
      "finite_observed_and_estimated_discrepancies"
    ),
    passed = TRUE,
    detail = c(
      as.character(max(pre_dates)),
      sprintf("%d observations", length(pre_dates)),
      sprintf("%d forecast dates", length(forecast_dates)),
      paste(format(levels, trim = TRUE), collapse = ", "),
      sprintf("%d rows", sum(trace$correction == "independent_fit")),
      sprintf("%d rows", sum(trace$correction == "monotone_implied")),
      sprintf("maximum absolute difference %.3g", observed_difference),
      sprintf("%d rows", nrow(trace))
    ),
    stringsAsFactors = FALSE
  )
  list(
    cutoff_date = cutoff_date,
    history_dates = pre_dates,
    forecast_dates = forecast_dates,
    quantile_levels = levels,
    trace = trace,
    audit = audit
  )
}

app_plot_glofas_discrepancy_context <- function(discrepancy_context, path) {
  app_require_namespace("ggplot2")
  app_ensure_dir(dirname(path))
  trace <- discrepancy_context$trace
  independent <- trace[trace$correction == "independent_fit", , drop = FALSE]
  observed_history <- independent[independent$phase == "pre_cutoff_history", , drop = FALSE]
  heldout_forecast <- independent[independent$phase == "post_cutoff_forecast", , drop = FALSE]
  monotone_forecast <- trace[
    trace$correction == "monotone_implied" & trace$phase == "post_cutoff_forecast",
    ,
    drop = FALSE
  ]
  forecast_shade <- data.frame(
    xmin = discrepancy_context$cutoff_date,
    xmax = max(discrepancy_context$forecast_dates),
    ymin = -Inf,
    ymax = Inf
  )
  p <- ggplot2::ggplot() +
    ggplot2::geom_rect(
      data = forecast_shade,
      ggplot2::aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
      inherit.aes = FALSE,
      fill = "#F3F4F6"
    ) +
    ggplot2::geom_hline(yintercept = 0, color = "#9CA3AF", linewidth = 0.3) +
    ggplot2::geom_line(
      data = observed_history,
      ggplot2::aes(x = target_date, y = observed_discrepancy, group = quantile_label, color = "Observed historical discrepancy"),
      linewidth = 0.58
    ) +
    ggplot2::geom_line(
      data = heldout_forecast,
      ggplot2::aes(x = target_date, y = observed_discrepancy, group = quantile_label, color = "Held-out realized discrepancy"),
      linewidth = 0.58
    ) +
    ggplot2::geom_point(
      data = heldout_forecast,
      ggplot2::aes(x = target_date, y = observed_discrepancy, color = "Held-out realized discrepancy"),
      size = 0.85
    ) +
    ggplot2::geom_line(
      data = independent,
      ggplot2::aes(x = target_date, y = estimate, group = quantile_label, color = "Independent Q-DESN discrepancy"),
      linewidth = 0.78
    ) +
    ggplot2::geom_line(
      data = monotone_forecast,
      ggplot2::aes(x = target_date, y = estimate, group = quantile_label, color = "Post-monotone implied discrepancy"),
      linewidth = 0.7,
      linetype = "22"
    ) +
    ggplot2::geom_vline(
      data = data.frame(cutoff_date = discrepancy_context$cutoff_date),
      ggplot2::aes(xintercept = cutoff_date),
      color = "#374151",
      linetype = "33",
      linewidth = 0.55
    ) +
    ggplot2::facet_wrap(~quantile_label, ncol = 4) +
    ggplot2::scale_color_manual(
      name = NULL,
      breaks = c(
        "Observed historical discrepancy",
        "Held-out realized discrepancy",
        "Independent Q-DESN discrepancy",
        "Post-monotone implied discrepancy"
      ),
      values = c(
        "Observed historical discrepancy" = "#111827",
        "Held-out realized discrepancy" = "#8B1E3F",
        "Independent Q-DESN discrepancy" = "#1769AA",
        "Post-monotone implied discrepancy" = "#D97706"
      )
    ) +
    ggplot2::scale_x_date(date_breaks = "1 month", date_labels = "%b %d") +
    ggplot2::labs(
      title = "Observed and estimated GloFAS discrepancy by quantile",
      subtitle = "Final 60 observations and 28-day forecast window; discrepancy is GloFAS minus USGS on the log1p scale",
      x = NULL,
      y = "Discrepancy on transformed scale"
    ) +
    app_glofas_context_theme() +
    ggplot2::theme(
      strip.text = ggplot2::element_text(face = "bold"),
      panel.grid.major.x = ggplot2::element_line(color = "#ECEFF1", linewidth = 0.25),
      axis.text.x = ggplot2::element_text(angle = 30, hjust = 1),
      legend.position = "bottom"
    ) +
    ggplot2::guides(color = ggplot2::guide_legend(nrow = 1, byrow = TRUE, override.aes = list(linewidth = c(0.8, 0.8, 1.0, 0.9))))
  ggplot2::ggsave(path, p, width = 11.2, height = 7.2, units = "in", device = grDevices::cairo_pdf)
  invisible(path)
}
