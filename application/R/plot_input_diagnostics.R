# Input-diagnostic figures for the GloFAS Q-DESN application.

app_enabled_figure_specs <- function(path) {
  specs <- app_read_yaml(path)
  figs <- specs$figures %||% list()
  figs[vapply(figs, function(x) isTRUE(x$enabled %||% TRUE), logical(1L))]
}

app_pdf_plot <- function(path, width, height, expr) {
  app_ensure_dir(dirname(path))
  grDevices::pdf(path, width = width, height = height)
  on.exit(grDevices::dev.off(), add = TRUE)
  force(expr)
  invisible(path)
}

app_panel_sets <- function(panel) {
  panel$origin_date <- as.Date(panel$origin_date)
  panel$target_date <- as.Date(panel$target_date)
  list(
    retrospective = panel[panel$is_retrospective, , drop = FALSE],
    ensemble = panel[panel$is_ensemble, , drop = FALSE]
  )
}

app_load_cutoff_rows <- function(cfg) {
  cutoffs <- app_validate_cutoffs(app_config_path(cfg, "cutoffs"))
  if (!nrow(cutoffs)) return(cutoffs)
  for (nm in c("origin_date", "train_start", "train_end", "eval_start", "eval_end")) {
    cutoffs[[nm]] <- as.Date(cutoffs[[nm]])
  }
  cutoffs$horizon_min <- as.integer(cutoffs$horizon_min)
  cutoffs$horizon_max <- as.integer(cutoffs$horizon_max)
  cutoffs
}

app_select_cutoff <- function(cfg, fig) {
  cutoffs <- app_load_cutoff_rows(cfg)
  if (!nrow(cutoffs)) {
    stop("Cutoff-source diagnostic figures require at least one enabled cutoff.", call. = FALSE)
  }

  if (!is.null(fig$cutoff_id) && nzchar(as.character(fig$cutoff_id))) {
    idx <- which(cutoffs$cutoff_id == as.character(fig$cutoff_id))
    if (!length(idx)) {
      stop(sprintf("No enabled cutoff_id '%s' was found.", as.character(fig$cutoff_id)), call. = FALSE)
    }
    return(cutoffs[idx[[1L]], , drop = FALSE])
  }

  if (!is.null(fig$origin_date) && nzchar(as.character(fig$origin_date))) {
    origin_date <- as.Date(as.character(fig$origin_date))
    idx <- which(cutoffs$origin_date == origin_date)
    if (!length(idx)) {
      stop(sprintf("No enabled cutoff has origin_date '%s'.", as.character(origin_date)), call. = FALSE)
    }
    return(cutoffs[idx[[1L]], , drop = FALSE])
  }

  cutoffs[1L, , drop = FALSE]
}

app_unique_date_value <- function(x, date_col, value_col) {
  out <- x[!is.na(x[[value_col]]), c(date_col, value_col), drop = FALSE]
  names(out) <- c("target_date", "value")
  if (!nrow(out)) return(out)
  out <- out[order(out$target_date), , drop = FALSE]
  out[!duplicated(out$target_date), , drop = FALSE]
}

app_cutoff_source_data <- function(panel, cfg, fig) {
  cutoff <- app_select_cutoff(cfg, fig)
  origin_date <- as.Date(cutoff$origin_date[[1L]])
  before_days <- as.integer(fig$window_before_days %||% 30L)
  after_days <- as.integer(fig$window_after_days %||% cutoff$horizon_max[[1L]] %||% 30L)
  window_start <- origin_date - before_days
  window_end <- origin_date + after_days
  sets <- app_panel_sets(panel)

  hist <- sets$retrospective[
    sets$retrospective$target_date >= window_start &
      sets$retrospective$target_date <= origin_date,
    ,
    drop = FALSE
  ]
  ens <- sets$ensemble[
    sets$ensemble$origin_date == origin_date &
      sets$ensemble$target_date > origin_date &
      sets$ensemble$target_date <= window_end,
    ,
    drop = FALSE
  ]

  h_min <- as.integer(fig$horizon_min %||% cutoff$horizon_min[[1L]] %||% NA_integer_)
  h_max <- as.integer(fig$horizon_max %||% cutoff$horizon_max[[1L]] %||% NA_integer_)
  if (is.finite(h_min)) ens <- ens[ens$horizon >= h_min, , drop = FALSE]
  if (is.finite(h_max)) ens <- ens[ens$horizon <= h_max, , drop = FALSE]

  if (!nrow(hist)) {
    stop(sprintf("No retrospective rows were available before cutoff %s.", as.character(origin_date)), call. = FALSE)
  }
  if (!nrow(ens)) {
    stop(sprintf("No GloFAS ensemble rows were available for origin %s.", as.character(origin_date)), call. = FALSE)
  }

  members <- sort(unique(ens$member))
  max_members <- as.integer(fig$max_members %||% length(members))
  if (is.finite(max_members) && max_members > 0L && length(members) > max_members) {
    members <- members[seq_len(max_members)]
    ens <- ens[ens$member %in% members, , drop = FALSE]
  }

  ref_history <- app_unique_date_value(hist, "target_date", "y_transformed")
  ref_future <- app_unique_date_value(ens, "target_date", "y_transformed")
  ret <- app_unique_date_value(hist, "target_date", "g_transformed")
  ens_median <- aggregate(g_transformed ~ target_date, data = ens, FUN = stats::median, na.rm = TRUE)
  names(ens_median) <- c("target_date", "value")

  list(
    cutoff = cutoff,
    origin_date = origin_date,
    window_start = window_start,
    window_end = window_end,
    retrospective = ret,
    reference_history = ref_history,
    reference_future = ref_future,
    ensemble = ens,
    ensemble_median = ens_median
  )
}

app_plot_input_coverage <- function(panel, path, title, width, height) {
  sets <- app_panel_sets(panel)
  labels <- c(
    "reference observations",
    "GloFAS retrospective",
    "GloFAS ensemble origins",
    "GloFAS ensemble targets"
  )
  starts <- as.Date(c(
    min(panel$target_date[!is.na(panel$y_reference)], na.rm = TRUE),
    min(sets$retrospective$target_date, na.rm = TRUE),
    min(sets$ensemble$origin_date, na.rm = TRUE),
    min(sets$ensemble$target_date, na.rm = TRUE)
  ), origin = "1970-01-01")
  ends <- as.Date(c(
    max(panel$target_date[!is.na(panel$y_reference)], na.rm = TRUE),
    max(sets$retrospective$target_date, na.rm = TRUE),
    max(sets$ensemble$origin_date, na.rm = TRUE),
    max(sets$ensemble$target_date, na.rm = TRUE)
  ), origin = "1970-01-01")
  app_pdf_plot(path, width, height, {
    old <- par(mar = c(4.1, 10.5, 2.5, 1))
    plot(range(c(starts, ends), na.rm = TRUE), c(0.5, length(labels) + 0.5),
      type = "n", yaxt = "n", xlab = "Date", ylab = "", main = title
    )
    axis(2, at = seq_along(labels), labels = labels, las = 1)
    segments(starts, seq_along(labels), ends, seq_along(labels), lwd = 5, col = "#2f6f9f")
    points(starts, seq_along(labels), pch = 19, col = "#2f6f9f")
    points(ends, seq_along(labels), pch = 19, col = "#2f6f9f")
    grid(nx = NA, ny = NULL, col = "gray90")
    par(old)
  })
}

app_plot_retrospective_series <- function(panel, path, title, width, height) {
  hist <- app_panel_sets(panel)$retrospective
  hist <- hist[order(hist$target_date), , drop = FALSE]
  app_pdf_plot(path, width, height, {
    plot(hist$target_date, hist$y_transformed, type = "l", col = "#1b4f72",
      xlab = "Date", ylab = "Transformed streamflow", main = title
    )
    lines(hist$target_date, hist$g_transformed, col = "#b03a2e")
    legend("topleft", legend = c("Reference", "GloFAS retrospective"),
      col = c("#1b4f72", "#b03a2e"), lty = 1, bty = "n"
    )
  })
}

app_plot_ensemble_fan <- function(panel, path, title, width, height, max_origins = 4L) {
  ens <- app_panel_sets(panel)$ensemble
  origins <- sort(unique(ens$origin_date))
  origins <- origins[seq_len(min(length(origins), max_origins))]
  ens <- ens[ens$origin_date %in% origins, , drop = FALSE]
  app_pdf_plot(path, width, height, {
    plot(range(ens$target_date, na.rm = TRUE), range(ens$g_transformed, na.rm = TRUE),
      type = "n", xlab = "Target date", ylab = "Transformed GloFAS forecast",
      main = title
    )
    cols <- grDevices::hcl.colors(length(origins), "Dark 3")
    for (j in seq_along(origins)) {
      sub <- ens[ens$origin_date == origins[[j]], , drop = FALSE]
      members <- unique(sub$member)
      for (m in members) {
        one <- sub[sub$member == m, , drop = FALSE]
        one <- one[order(one$target_date), , drop = FALSE]
        lines(one$target_date, one$g_transformed, col = grDevices::adjustcolor(cols[[j]], alpha.f = 0.45))
      }
    }
    legend("topleft", legend = as.character(origins), col = cols, lty = 1, bty = "n", title = "Origin")
  })
}

app_plot_horizon_member_heatmap <- function(panel, path, title, width, height) {
  ens <- app_panel_sets(panel)$ensemble
  tab <- xtabs(~ horizon + origin_date, data = unique(ens[, c("origin_date", "horizon", "member")]))
  counts <- as.matrix(tab)
  app_pdf_plot(path, width, height, {
    old <- par(mar = c(5, 5, 2.5, 2))
    image(seq_len(ncol(counts)), as.numeric(rownames(counts)), t(counts),
      xlab = "Forecast origin index", ylab = "Horizon", main = title,
      col = grDevices::hcl.colors(12, "YlOrRd", rev = TRUE), axes = FALSE
    )
    axis(1)
    axis(2, at = as.numeric(rownames(counts)), las = 1)
    box()
    par(old)
  })
}

app_plot_retrospective_scatter <- function(panel, path, title, width, height) {
  hist <- app_panel_sets(panel)$retrospective
  app_pdf_plot(path, width, height, {
    plot(hist$g_transformed, hist$y_transformed,
      xlab = "GloFAS retrospective, transformed",
      ylab = "Reference streamflow, transformed",
      main = title,
      pch = 19, col = grDevices::adjustcolor("#2f6f9f", alpha.f = 0.55)
    )
    abline(0, 1, lty = 2, col = "gray40")
  })
}

app_plot_discrepancy_by_month <- function(panel, path, title, width, height) {
  hist <- app_panel_sets(panel)$retrospective
  hist$month <- factor(format(hist$target_date, "%m"), levels = sprintf("%02d", 1:12))
  hist$discrepancy <- hist$y_transformed - hist$g_transformed
  app_pdf_plot(path, width, height, {
    boxplot(discrepancy ~ month, data = hist,
      xlab = "Target month", ylab = "Reference minus GloFAS, transformed",
      main = title, col = "#d5e8d4", border = "#4f7942"
    )
    abline(h = 0, lty = 2, col = "gray40")
  })
}

app_plot_cutoff_source_diagnostic <- function(panel, path, title, width, height, cfg, fig) {
  dat <- app_cutoff_source_data(panel, cfg, fig)
  ens <- dat$ensemble[order(dat$ensemble$target_date, dat$ensemble$member), , drop = FALSE]
  values <- c(
    dat$reference_history$value,
    dat$reference_future$value,
    dat$retrospective$value,
    ens$g_transformed,
    dat$ensemble_median$value
  )
  values <- values[is.finite(values)]
  if (!length(values)) stop("No finite values are available for the cutoff-source diagnostic.", call. = FALSE)
  y_pad <- diff(range(values))
  y_pad <- if (is.finite(y_pad) && y_pad > 0) 0.05 * y_pad else 0.1

  app_pdf_plot(path, width, height, {
    plot(
      c(dat$window_start, dat$window_end),
      range(values, na.rm = TRUE) + c(-y_pad, y_pad),
      type = "n",
      xlab = "Date",
      ylab = "Transformed streamflow",
      main = title
    )
    grid(col = "gray90")
    abline(v = dat$origin_date, lty = 3, col = "gray35")

    for (m in sort(unique(ens$member))) {
      one <- ens[ens$member == m, , drop = FALSE]
      one <- one[order(one$target_date), , drop = FALSE]
      lines(
        one$target_date,
        one$g_transformed,
        col = grDevices::adjustcolor("#b6b6b6", alpha.f = 0.42),
        lwd = 0.8
      )
    }

    if (nrow(dat$retrospective)) {
      lines(dat$retrospective$target_date, dat$retrospective$value, col = "#b35c00", lwd = 1.7, lty = 1)
    }
    if (nrow(dat$ensemble_median)) {
      lines(dat$ensemble_median$target_date, dat$ensemble_median$value, col = "#b35c00", lwd = 2.2, lty = 2)
    }
    if (nrow(dat$reference_history)) {
      lines(dat$reference_history$target_date, dat$reference_history$value, col = "#1b4f72", lwd = 2.0)
    }
    if (nrow(dat$reference_future)) {
      points(dat$reference_future$target_date, dat$reference_future$value, col = "#7f1d1d", pch = 19, cex = 0.55)
    }

    legend(
      "topleft",
      legend = c(
        "Reference, observed before cutoff",
        "Reference, held-out after cutoff",
        "GloFAS retrospective before cutoff",
        "GloFAS forecast ensemble median",
        "GloFAS ensemble members",
        "Cutoff / forecast origin"
      ),
      col = c("#1b4f72", "#7f1d1d", "#b35c00", "#b35c00", "#b6b6b6", "gray35"),
      lty = c(1, NA, 1, 2, 1, 3),
      lwd = c(2.0, NA, 1.8, 2.2, 1.0, 1.0),
      pch = c(NA, 19, NA, NA, NA, NA),
      bty = "n",
      cex = 0.82
    )
  })

  data.frame(
    figure_id = as.character(fig$figure_id %||% "cutoff_source_diagnostic"),
    cutoff_id = as.character(dat$cutoff$cutoff_id[[1L]]),
    origin_date = as.character(dat$origin_date),
    window_start = as.character(dat$window_start),
    window_end = as.character(dat$window_end),
    n_reference_history = nrow(dat$reference_history),
    n_reference_future = nrow(dat$reference_future),
    n_retrospective = nrow(dat$retrospective),
    n_ensemble_rows = nrow(dat$ensemble),
    n_members = length(unique(dat$ensemble$member)),
    horizon_min = min(dat$ensemble$horizon, na.rm = TRUE),
    horizon_max = max(dat$ensemble$horizon, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}

app_plot_cutoff_covariate_diagnostic <- function(panel, path, title, width, height, cfg, fig) {
  timeline <- app_panel_covariate_timeline(panel, required = TRUE)
  cutoff <- app_select_cutoff(cfg, fig)
  origin_date <- as.Date(cutoff$origin_date[[1L]])
  before_days <- as.integer(fig$window_before_days %||% 30L)
  after_days <- as.integer(fig$window_after_days %||% cutoff$horizon_max[[1L]] %||% 30L)
  window_start <- origin_date - before_days
  window_end <- origin_date + after_days
  dat <- timeline[timeline$date >= window_start & timeline$date <= window_end, , drop = FALSE]
  if (!nrow(dat)) stop("No covariate rows are available for the cutoff covariate diagnostic.", call. = FALSE)

  role_col <- if ("ppt_role" %in% names(dat)) "ppt_role" else NA_character_
  role <- if (!is.na(role_col)) dat[[role_col]] else rep("unknown", nrow(dat))
  role_palette <- c(
    retrospective_realized = "#1b4f72",
    forecast_blended = "#b03a2e",
    forecast_gefs = "#2f7d32",
    oracle_realized = "#6f3fa0",
    forecast_external = "#b26a00",
    unknown = "#666666"
  )
  cols <- role_palette[role]
  cols[is.na(cols)] <- role_palette[["unknown"]]
  legend_roles <- intersect(names(role_palette), unique(role))

  app_pdf_plot(path, width, height, {
    old <- par(mfrow = c(2, 1), mar = c(3.2, 4.2, 2.0, 1.0))
    plot(dat$date, dat$ppt, type = "h", lwd = 2, col = cols,
      xlab = "", ylab = "ppt", main = title
    )
    points(dat$date, dat$ppt, pch = 19, cex = 0.45, col = cols)
    abline(v = origin_date, lty = 3, col = "gray35")
    grid(col = "gray90")
    legend("topleft",
      legend = c(gsub("_", " ", legend_roles), "forecast origin"),
      col = c(role_palette[legend_roles], "gray35"),
      lty = c(rep(1, length(legend_roles)), 3),
      lwd = c(rep(2, length(legend_roles)), 1),
      bty = "n",
      cex = 0.78
    )
    plot(dat$date, dat$soil, type = "l", lwd = 2, col = "#3d6b35",
      xlab = "Date", ylab = "soil"
    )
    points(dat$date, dat$soil, pch = 19, cex = 0.45, col = cols)
    abline(v = origin_date, lty = 3, col = "gray35")
    grid(col = "gray90")
    par(old)
  })

  data.frame(
    figure_id = as.character(fig$figure_id %||% "cutoff_covariate_diagnostic"),
    cutoff_id = as.character(cutoff$cutoff_id[[1L]]),
    origin_date = as.character(origin_date),
    window_start = as.character(window_start),
    window_end = as.character(window_end),
    n_covariate_rows = nrow(dat),
    n_forecast_blended = sum(role == "forecast_blended", na.rm = TRUE),
    n_forecast_gefs = sum(role == "forecast_gefs", na.rm = TRUE),
    n_oracle_realized = sum(role == "oracle_realized", na.rm = TRUE),
    n_forecast_external = sum(role == "forecast_external", na.rm = TRUE),
    n_retrospective_realized = sum(role == "retrospective_realized", na.rm = TRUE),
    n_uses_realized_future = if ("ppt_uses_realized_future" %in% names(dat)) sum(as.logical(dat$ppt_uses_realized_future), na.rm = TRUE) else NA_integer_,
    future_policy = attr(timeline, "covariate_future_policy") %||% NA_character_,
    source_provider = attr(timeline, "covariate_source_provider") %||% NA_character_,
    variables = paste(attr(timeline, "variables") %||% c("ppt", "soil"), collapse = ";"),
    stringsAsFactors = FALSE
  )
}

app_make_input_diagnostic_figures <- function(cfg, panel, run_dirs, source_script = "application/scripts/02_make_input_figures.R") {
  specs_path <- app_config_path(cfg, "figure_specs")
  specs <- app_read_yaml(specs_path)
  figs <- app_enabled_figure_specs(specs_path)
  width <- as.numeric(specs$graphics$width %||% 7)
  height <- as.numeric(specs$graphics$height %||% 4.5)
  out_dir <- file.path(run_dirs$figures, "input_diagnostics")
  app_ensure_dir(out_dir)

  panel_path <- file.path(app_config_path(cfg, "cache"), "application_panel.rds")
  panel_hash <- app_sha256_file(panel_path)
  rows <- list()
  cutoff_source_rows <- list()
  cutoff_covariate_rows <- list()
  add_row <- function(id, path, notes) {
    rows[[id]] <<- app_figure_manifest_row(
      figure_id = id,
      output_path = app_prefer_repo_relative_path(path),
      source_script = source_script,
      run_id = basename(run_dirs$run_dir),
      input_manifest = app_prefer_repo_relative_path(app_config_path(cfg, "input_manifest")),
      panel_hash = panel_hash,
      config_path = app_prefer_repo_relative_path(cfg$.__config_path__),
      notes = notes
    )
  }

  for (id in names(figs)) {
    fig <- figs[[id]]
    path <- file.path(out_dir, fig$filename %||% paste0(id, ".pdf"))
    title <- fig$title %||% id
    fig$figure_id <- id
    if (id == "input_coverage_timeline") {
      app_plot_input_coverage(panel, path, title, width, height)
    } else if (id == "reference_glofas_retrospective_series") {
      app_plot_retrospective_series(panel, path, title, width, height)
    } else if (id == "glofas_ensemble_fan_selected_origins") {
      app_plot_ensemble_fan(panel, path, title, width, height, max_origins = as.integer(fig$max_origins %||% 4L))
    } else if (id == "horizon_member_availability_heatmap") {
      app_plot_horizon_member_heatmap(panel, path, title, width, height)
    } else if (id == "reference_glofas_retrospective_scatter") {
      app_plot_retrospective_scatter(panel, path, title, width, height)
    } else if (id == "retrospective_discrepancy_by_month") {
      app_plot_discrepancy_by_month(panel, path, title, width, height)
    } else if (id == "cutoff_source_diagnostic") {
      cutoff_source_rows[[id]] <- app_plot_cutoff_source_diagnostic(panel, path, title, width, height, cfg, fig)
    } else if (id == "cutoff_covariate_diagnostic") {
      cutoff_covariate_rows[[id]] <- app_plot_cutoff_covariate_diagnostic(panel, path, title, width, height, cfg, fig)
    } else {
      warning(sprintf("Skipping unknown input-diagnostic figure id '%s'.", id), call. = FALSE)
      next
    }
    notes <- if (id == "cutoff_source_diagnostic") {
      "Cutoff-centered source diagnostic generated from the audited application panel."
    } else if (id == "cutoff_covariate_diagnostic") {
      "Cutoff-centered ppt/soil diagnostic generated from the model covariate timeline."
    } else {
      "Input diagnostic generated from the audited application panel."
    }
    add_row(id, path, notes)
  }

  summary <- app_panel_summary(panel)
  app_write_csv(summary, file.path(run_dirs$tables, "input_figure_data_summary.csv"))
  if (length(cutoff_source_rows)) {
    app_write_csv(do.call(rbind, cutoff_source_rows), file.path(run_dirs$tables, "cutoff_source_figure_summary.csv"))
  }
  if (length(cutoff_covariate_rows)) {
    app_write_csv(do.call(rbind, cutoff_covariate_rows), file.path(run_dirs$tables, "cutoff_covariate_figure_summary.csv"))
  }
  manifest_path <- file.path(run_dirs$tables, "figure_manifest.csv")
  app_write_figure_manifest(rows, manifest_path)
  do.call(rbind, rows)
}
