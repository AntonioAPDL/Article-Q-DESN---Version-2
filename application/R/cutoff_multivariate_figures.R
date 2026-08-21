# All-cutoff source and Q-DESN forecast figures for the GloFAS application.

app_cutoff_figure_slug <- function(cutoff_date) {
  paste0("cutoff_date=", format(as.Date(cutoff_date), "%Y-%m-%d"))
}

app_cutoff_transform_values <- function(x, transform = "log1p") {
  x <- suppressWarnings(as.numeric(x))
  if (identical(transform, "identity")) return(x)
  if (identical(transform, "log1p")) {
    return(ifelse(is.finite(x) & x > -1, log1p(x), NA_real_))
  }
  stop(sprintf("Unsupported cutoff-figure transform '%s'.", transform), call. = FALSE)
}

app_cutoff_col <- function(x, choices, required = TRUE) {
  hit <- intersect(choices, names(x))
  if (length(hit)) return(hit[[1L]])
  if (isTRUE(required)) {
    stop(sprintf("None of the expected columns were found: %s", paste(choices, collapse = ", ")), call. = FALSE)
  }
  NA_character_
}

app_discover_multivariate_cutoff_dirs <- function(source_root) {
  source_root <- app_resolve_path(source_root, must_work = TRUE)
  dirs <- list.dirs(source_root, full.names = TRUE, recursive = FALSE)
  dirs <- dirs[grepl("^cutoff_date=", basename(dirs))]
  if (!length(dirs)) {
    stop(sprintf("No cutoff_date=* directories were found under %s.", source_root), call. = FALSE)
  }
  dates <- as.Date(sub("^cutoff_date=", "", basename(dirs)))
  ord <- order(dates)
  data.frame(
    cutoff_date = dates[ord],
    cutoff_slug = basename(dirs[ord]),
    cutoff_dir = normalizePath(dirs[ord], mustWork = TRUE),
    stringsAsFactors = FALSE
  )
}

app_read_cutoff_csv <- function(cutoff_dir, primary, fallback = NULL, required = TRUE) {
  paths <- file.path(cutoff_dir, c(primary, fallback %||% character()))
  paths <- paths[nzchar(paths)]
  hit <- paths[file.exists(paths)]
  if (length(hit)) return(app_read_csv(hit[[1L]]))
  if (isTRUE(required)) {
    stop(sprintf("Missing cutoff CSV under %s: %s", cutoff_dir, paste(c(primary, fallback), collapse = " or ")), call. = FALSE)
  }
  data.frame()
}

app_cutoff_member_long <- function(x, product, cutoff_date, transform = "log1p") {
  if (!nrow(x)) {
    return(data.frame(
      product = character(),
      cutoff_date = as.Date(character()),
      target_date = as.Date(character()),
      horizon = integer(),
      member = character(),
      value_raw = numeric(),
      value = numeric(),
      stringsAsFactors = FALSE
    ))
  }
  target_col <- app_cutoff_col(x, c("target_date", "Date", "date"))
  member_cols <- setdiff(names(x), target_col)
  member_cols <- member_cols[vapply(x[member_cols], function(z) suppressWarnings(all(is.na(z) | is.finite(as.numeric(z)))), logical(1L))]
  if (!length(member_cols)) {
    stop(sprintf("No forecast member columns were found for %s cutoff %s.", product, as.character(cutoff_date)), call. = FALSE)
  }
  target_date <- as.Date(x[[target_col]])
  rows <- lapply(member_cols, function(member) {
    value_raw <- suppressWarnings(as.numeric(x[[member]]))
    data.frame(
      product = product,
      cutoff_date = as.Date(cutoff_date),
      target_date = target_date,
      horizon = as.integer(target_date - as.Date(cutoff_date)),
      member = member,
      value_raw = value_raw,
      value = app_cutoff_transform_values(value_raw, transform = transform),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out <- out[!is.na(out$target_date), , drop = FALSE]
  rownames(out) <- NULL
  out
}

app_cutoff_forecast_summary <- function(long) {
  if (!nrow(long)) {
    return(data.frame(
      product = character(),
      target_date = as.Date(character()),
      horizon = integer(),
      q05 = numeric(),
      q50 = numeric(),
      q95 = numeric(),
      n_members = integer(),
      stringsAsFactors = FALSE
    ))
  }
  keys <- unique(long[, c("product", "target_date", "horizon"), drop = FALSE])
  rows <- lapply(seq_len(nrow(keys)), function(i) {
    idx <- long$product == keys$product[[i]] &
      long$target_date == keys$target_date[[i]] &
      long$horizon == keys$horizon[[i]]
    vals <- long$value[idx]
    vals <- vals[is.finite(vals)]
    qs <- if (length(vals)) stats::quantile(vals, c(0.05, 0.50, 0.95), na.rm = TRUE, names = FALSE) else rep(NA_real_, 3L)
    data.frame(
      product = keys$product[[i]],
      target_date = keys$target_date[[i]],
      horizon = keys$horizon[[i]],
      q05 = qs[[1L]],
      q50 = qs[[2L]],
      q95 = qs[[3L]],
      n_members = length(vals),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out[order(out$product, out$target_date), , drop = FALSE]
}

app_load_multivariate_cutoff_bundle <- function(cutoff_dir, transform = "log1p") {
  cutoff_date <- as.Date(sub("^cutoff_date=", "", basename(cutoff_dir)))
  retros <- app_read_cutoff_csv(cutoff_dir, "retros/retros.csv", "forecats_bundle/retros.csv")
  date_col <- app_cutoff_col(retros, c("Date", "date", "target_date"))
  usgs_col <- app_cutoff_col(retros, c("USGS", "usgs", "reference", "y_reference"))
  glofas_col <- app_cutoff_col(retros, c("GloFAS", "glofas", "g_glofas"))
  nws_col <- app_cutoff_col(retros, c("NWS3.0", "NWS", "nws", "nws3"))
  retros_out <- data.frame(
    date = as.Date(retros[[date_col]]),
    usgs_raw = suppressWarnings(as.numeric(retros[[usgs_col]])),
    glofas_raw = suppressWarnings(as.numeric(retros[[glofas_col]])),
    nws_raw = suppressWarnings(as.numeric(retros[[nws_col]])),
    stringsAsFactors = FALSE
  )
  retros_out$usgs <- app_cutoff_transform_values(retros_out$usgs_raw, transform = transform)
  retros_out$glofas <- app_cutoff_transform_values(retros_out$glofas_raw, transform = transform)
  retros_out$nws <- app_cutoff_transform_values(retros_out$nws_raw, transform = transform)
  retros_out <- retros_out[order(retros_out$date), , drop = FALSE]

  usgs_daily <- app_read_cutoff_csv(cutoff_dir, "inputs/usgs_daily.csv", required = FALSE)
  if (nrow(usgs_daily)) {
    daily_date <- app_cutoff_col(usgs_daily, c("date", "Date", "target_date"))
    daily_value <- app_cutoff_col(usgs_daily, c("discharge_cms", "USGS", "discharge_cfs"), required = FALSE)
    future_usgs <- data.frame(
      date = as.Date(usgs_daily[[daily_date]]),
      usgs_raw = if (!is.na(daily_value)) suppressWarnings(as.numeric(usgs_daily[[daily_value]])) else NA_real_,
      stringsAsFactors = FALSE
    )
  } else {
    future_usgs <- data.frame(date = as.Date(character()), usgs_raw = numeric(), stringsAsFactors = FALSE)
  }
  future_usgs$usgs <- app_cutoff_transform_values(future_usgs$usgs_raw, transform = transform)
  future_usgs <- future_usgs[future_usgs$date > cutoff_date, , drop = FALSE]
  future_usgs <- future_usgs[order(future_usgs$date), , drop = FALSE]

  glofas <- app_read_cutoff_csv(cutoff_dir, "forecasts/glofas_forecast.csv", "forecats_bundle/glofas_forecast.csv")
  nws <- app_read_cutoff_csv(cutoff_dir, "forecasts/nws_forecast.csv", "forecats_bundle/nws_forecast.csv")
  glofas_long <- app_cutoff_member_long(glofas, "GloFAS", cutoff_date, transform = transform)
  nws_long <- app_cutoff_member_long(nws, "NWS", cutoff_date, transform = transform)
  forecast_long <- rbind(glofas_long, nws_long)

  list(
    cutoff_date = cutoff_date,
    cutoff_slug = app_cutoff_figure_slug(cutoff_date),
    cutoff_dir = normalizePath(cutoff_dir, mustWork = TRUE),
    transform = transform,
    retros = retros_out,
    future_usgs = future_usgs,
    forecast_long = forecast_long,
    forecast_summary = app_cutoff_forecast_summary(forecast_long)
  )
}

app_load_cutoff_qdesn_predictions <- function(prediction_run_id = NULL, run_dir = NULL) {
  if (is.null(run_dir)) {
    if (is.null(prediction_run_id) || !nzchar(prediction_run_id)) {
      return(list(predictions = data.frame(), draws = data.frame(), run_dir = NA_character_))
    }
    run_dir <- app_path("application", "runs", prediction_run_id)
  }
  predictions_path <- file.path(run_dir, "tables", "prediction_quantiles_synthesized.csv")
  draws_path <- file.path(run_dir, "tables", "posterior_draw_predictions.csv")
  predictions <- app_read_csv(predictions_path, required = FALSE)
  draws <- app_read_csv(draws_path, required = FALSE)
  if (nrow(predictions)) {
    predictions$origin_date <- as.Date(predictions$origin_date)
    predictions$target_date <- as.Date(predictions$target_date)
    predictions$quantile_level <- suppressWarnings(as.numeric(predictions$quantile_level))
  }
  if (nrow(draws)) {
    draws$origin_date <- as.Date(draws$origin_date)
    draws$target_date <- as.Date(draws$target_date)
    draws$quantile_level <- suppressWarnings(as.numeric(draws$quantile_level))
  }
  list(
    predictions = predictions,
    draws = draws,
    run_dir = normalizePath(run_dir, mustWork = file.exists(run_dir))
  )
}

app_filter_qdesn_overlay <- function(bundle, cutoff_date, model_family = "qdesn_glofas_discrepancy") {
  pred <- bundle$predictions
  draws <- bundle$draws
  if (nrow(pred) && "model_family" %in% names(pred)) {
    pred <- pred[pred$model_family == model_family & pred$origin_date == as.Date(cutoff_date), , drop = FALSE]
  } else {
    pred <- data.frame()
  }
  if (nrow(draws) && "model_family" %in% names(draws)) {
    draws <- draws[draws$model_family == model_family & draws$origin_date == as.Date(cutoff_date), , drop = FALSE]
  } else {
    draws <- data.frame()
  }
  list(predictions = pred, draws = draws)
}

app_qdesn_draw_interval_summary <- function(draws) {
  needed <- c("target_date", "quantile_level", "q_y_draw")
  if (!nrow(draws) || !all(needed %in% names(draws))) {
    return(data.frame(
      target_date = as.Date(character()),
      quantile_level = numeric(),
      lo95 = numeric(),
      hi95 = numeric(),
      n_draws = integer(),
      stringsAsFactors = FALSE
    ))
  }
  keys <- unique(draws[, c("target_date", "quantile_level"), drop = FALSE])
  rows <- lapply(seq_len(nrow(keys)), function(i) {
    idx <- draws$target_date == keys$target_date[[i]] & draws$quantile_level == keys$quantile_level[[i]]
    vals <- suppressWarnings(as.numeric(draws$q_y_draw[idx]))
    vals <- vals[is.finite(vals)]
    qs <- if (length(vals)) stats::quantile(vals, c(0.025, 0.975), na.rm = TRUE, names = FALSE) else c(NA_real_, NA_real_)
    data.frame(
      target_date = keys$target_date[[i]],
      quantile_level = keys$quantile_level[[i]],
      lo95 = qs[[1L]],
      hi95 = qs[[2L]],
      n_draws = length(vals),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out[order(out$quantile_level, out$target_date), , drop = FALSE]
}

app_cutoff_window_source <- function(bundle, before_days = 60L, after_days = 30L) {
  cutoff <- bundle$cutoff_date
  start <- cutoff - as.integer(before_days)
  end <- cutoff + as.integer(after_days)
  retros <- bundle$retros[bundle$retros$date >= start & bundle$retros$date <= cutoff, , drop = FALSE]
  future <- bundle$future_usgs[bundle$future_usgs$date > cutoff & bundle$future_usgs$date <= end, , drop = FALSE]
  forecast_long <- bundle$forecast_long[
    bundle$forecast_long$target_date > cutoff &
      bundle$forecast_long$target_date <= end,
    ,
    drop = FALSE
  ]
  forecast_summary <- bundle$forecast_summary[
    bundle$forecast_summary$target_date > cutoff &
      bundle$forecast_summary$target_date <= end,
    ,
    drop = FALSE
  ]
  list(
    cutoff_date = cutoff,
    window_start = start,
    window_end = end,
    retros = retros,
    future_usgs = future,
    forecast_long = forecast_long,
    forecast_summary = forecast_summary
  )
}

app_cutoff_y_limits <- function(parts, overlay_values = numeric()) {
  values <- c(
    parts$retros$usgs,
    parts$retros$glofas,
    parts$retros$nws,
    parts$future_usgs$usgs,
    parts$forecast_long$value,
    overlay_values
  )
  values <- values[is.finite(values)]
  if (!length(values)) return(c(0, 1))
  rng <- range(values)
  pad <- diff(rng)
  pad <- if (is.finite(pad) && pad > 0) 0.06 * pad else 0.1
  rng + c(-pad, pad)
}

app_plot_forecast_product <- function(parts, product, ret_col, col, member_alpha = 0.20) {
  retros <- parts$retros
  if (nrow(retros)) {
    lines(retros$date, retros[[ret_col]], col = col, lwd = 1.45)
  }
  fl <- parts$forecast_long[parts$forecast_long$product == product, , drop = FALSE]
  if (nrow(fl)) {
    for (m in sort(unique(fl$member))) {
      one <- fl[fl$member == m, , drop = FALSE]
      one <- one[order(one$target_date), , drop = FALSE]
      lines(one$target_date, one$value, col = grDevices::adjustcolor(col, alpha.f = member_alpha), lwd = 0.55)
    }
  }
  fs <- parts$forecast_summary[parts$forecast_summary$product == product, , drop = FALSE]
  if (nrow(fs)) {
    fs <- fs[order(fs$target_date), , drop = FALSE]
    lines(fs$target_date, fs$q50, col = col, lwd = 2.0, lty = 2)
  }
}

app_plot_multivariate_synthesis_cutoff <- function(bundle, overlay, path, before_days = 60L, after_days = 30L) {
  parts <- app_cutoff_window_source(bundle, before_days = before_days, after_days = after_days)
  pred <- overlay$predictions
  q_col <- if (nrow(pred) && "qhat_monotone" %in% names(pred)) "qhat_monotone" else "qhat"
  overlay_values <- if (nrow(pred) && q_col %in% names(pred)) suppressWarnings(as.numeric(pred[[q_col]])) else numeric()
  ylim <- app_cutoff_y_limits(parts, overlay_values = overlay_values)
  app_ensure_dir(dirname(path))
  grDevices::pdf(path, width = 8.6, height = 4.9)
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- par(mar = c(4.3, 4.6, 2.5, 1.0))
  on.exit(par(old), add = TRUE)
  plot(
    c(parts$window_start, parts$window_end),
    ylim,
    type = "n",
    xlab = "Date",
    ylab = "Transformed streamflow",
    main = sprintf("Multivariate source and Q-DESN forecast context, cutoff %s", as.character(bundle$cutoff_date))
  )
  grid(col = "gray90")
  abline(v = bundle$cutoff_date, lty = 3, col = "gray35", lwd = 1.1)
  app_plot_forecast_product(parts, "GloFAS", "glofas", "#B65F00", member_alpha = 0.17)
  app_plot_forecast_product(parts, "NWS", "nws", "#2C7A7B", member_alpha = 0.20)
  if (nrow(parts$retros)) {
    lines(parts$retros$date, parts$retros$usgs, col = "#12355B", lwd = 2.0)
  }
  if (nrow(parts$future_usgs)) {
    points(parts$future_usgs$date, parts$future_usgs$usgs, col = "#B00020", pch = 19, cex = 0.62)
  }
  if (nrow(pred) && all(c("target_date", "quantile_level", q_col) %in% names(pred))) {
    p05 <- pred[abs(pred$quantile_level - 0.05) < 1e-8, , drop = FALSE]
    p50 <- pred[abs(pred$quantile_level - 0.50) < 1e-8, , drop = FALSE]
    p95 <- pred[abs(pred$quantile_level - 0.95) < 1e-8, , drop = FALSE]
    if (nrow(p05) && nrow(p95)) {
      band <- merge(
        p05[, c("target_date", q_col), drop = FALSE],
        p95[, c("target_date", q_col), drop = FALSE],
        by = "target_date",
        suffixes = c("_lo", "_hi")
      )
      band <- band[order(band$target_date), , drop = FALSE]
      lo_col <- paste0(q_col, "_lo")
      hi_col <- paste0(q_col, "_hi")
      polygon(
        c(band$target_date, rev(band$target_date)),
        c(band[[lo_col]], rev(band[[hi_col]])),
        col = grDevices::adjustcolor("#6A3D9A", alpha.f = 0.12),
        border = NA
      )
    }
    if (nrow(p50)) {
      p50 <- p50[order(p50$target_date), , drop = FALSE]
      lines(p50$target_date, p50[[q_col]], col = "#6A3D9A", lwd = 2.3)
    }
  }
  legend(
    "topleft",
    legend = c(
      "USGS observed before cutoff",
      "USGS held out after cutoff",
      "GloFAS retrospective",
      "GloFAS forecast members / median",
      "NWS retrospective",
      "NWS forecast members / median",
      "Q-DESN forecast median and 90% band",
      "Cutoff"
    ),
    col = c("#12355B", "#B00020", "#B65F00", "#B65F00", "#2C7A7B", "#2C7A7B", "#6A3D9A", "gray35"),
    lty = c(1, NA, 1, 2, 1, 2, 1, 3),
    lwd = c(2.0, NA, 1.6, 1.8, 1.6, 1.8, 2.2, 1.1),
    pch = c(NA, 19, NA, NA, NA, NA, 15, NA),
    pt.cex = c(NA, 0.8, NA, NA, NA, NA, 1.2, NA),
    bty = "n",
    cex = 0.72
  )
  invisible(path)
}

app_quantile_palette <- function(tau) {
  cols <- grDevices::hcl.colors(max(3L, length(tau)), "Viridis")
  stats::setNames(cols[seq_along(tau)], as.character(tau))
}

app_plot_quantile_paths_cutoff <- function(bundle, overlay, path, before_days = 60L, after_days = 30L, monotone = FALSE) {
  parts <- app_cutoff_window_source(bundle, before_days = before_days, after_days = after_days)
  pred <- overlay$predictions
  q_col <- if (isTRUE(monotone) && "qhat_monotone" %in% names(pred)) "qhat_monotone" else "qhat"
  intervals <- app_qdesn_draw_interval_summary(overlay$draws)
  overlay_values <- c(
    if (nrow(pred) && q_col %in% names(pred)) suppressWarnings(as.numeric(pred[[q_col]])) else numeric(),
    intervals$lo95,
    intervals$hi95
  )
  ylim <- app_cutoff_y_limits(parts, overlay_values = overlay_values)
  app_ensure_dir(dirname(path))
  grDevices::pdf(path, width = 8.6, height = 4.9)
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- par(mar = c(4.3, 4.6, 2.5, 1.0))
  on.exit(par(old), add = TRUE)
  plot(
    c(parts$window_start, parts$window_end),
    ylim,
    type = "n",
    xlab = "Date",
    ylab = "Transformed streamflow",
    main = sprintf(
      "Q-DESN forecast quantile paths%s, cutoff %s",
      if (isTRUE(monotone)) " after monotone correction" else " before monotone correction",
      as.character(bundle$cutoff_date)
    )
  )
  grid(col = "gray90")
  abline(v = bundle$cutoff_date, lty = 3, col = "gray35", lwd = 1.1)
  app_plot_forecast_product(parts, "GloFAS", "glofas", "#B65F00", member_alpha = 0.10)
  app_plot_forecast_product(parts, "NWS", "nws", "#2C7A7B", member_alpha = 0.12)
  if (nrow(parts$retros)) {
    lines(parts$retros$date, parts$retros$usgs, col = "#12355B", lwd = 2.0)
  }
  if (nrow(parts$future_usgs)) {
    points(parts$future_usgs$date, parts$future_usgs$usgs, col = "#B00020", pch = 19, cex = 0.62)
  }
  if (nrow(pred) && all(c("target_date", "quantile_level", q_col) %in% names(pred))) {
    tau <- sort(unique(pred$quantile_level))
    pal <- app_quantile_palette(tau)
    for (tt in tau) {
      one <- pred[abs(pred$quantile_level - tt) < 1e-8, , drop = FALSE]
      one <- one[order(one$target_date), , drop = FALSE]
      ci <- intervals[abs(intervals$quantile_level - tt) < 1e-8, , drop = FALSE]
      ci <- ci[order(ci$target_date), , drop = FALSE]
      if (nrow(ci)) {
        polygon(
          c(ci$target_date, rev(ci$target_date)),
          c(ci$lo95, rev(ci$hi95)),
          col = grDevices::adjustcolor(pal[[as.character(tt)]], alpha.f = 0.08),
          border = NA
        )
      }
      if (nrow(one)) {
        lines(one$target_date, one[[q_col]], col = pal[[as.character(tt)]], lwd = 1.8)
      }
    }
    legend(
      "topleft",
      legend = c(
        paste0("tau=", format(tau, trim = TRUE)),
        "USGS observed",
        "Held-out USGS",
        "GloFAS/NWS context",
        "Cutoff"
      ),
      col = c(unname(pal[as.character(tau)]), "#12355B", "#B00020", "gray55", "gray35"),
      lty = c(rep(1, length(tau)), 1, NA, 1, 3),
      lwd = c(rep(1.8, length(tau)), 2.0, NA, 1.2, 1.1),
      pch = c(rep(NA, length(tau)), NA, 19, NA, NA),
      bty = "n",
      cex = 0.66
    )
  } else {
    legend(
      "topleft",
      legend = c("USGS observed", "Held-out USGS", "GloFAS/NWS context", "Cutoff", "Q-DESN overlay unavailable"),
      col = c("#12355B", "#B00020", "gray55", "gray35", "#6A3D9A"),
      lty = c(1, NA, 1, 3, NA),
      pch = c(NA, 19, NA, NA, 4),
      bty = "n",
      cex = 0.72
    )
  }
  invisible(path)
}

app_cutoff_validation_row <- function(bundle, overlay, paths, before_days, after_days, prediction_run_id) {
  parts <- app_cutoff_window_source(bundle, before_days = before_days, after_days = after_days)
  q_col_available <- nrow(overlay$predictions) && "qhat_monotone" %in% names(overlay$predictions)
  data.frame(
    cutoff_date = as.character(bundle$cutoff_date),
    source_cutoff_dir = app_prefer_repo_relative_path(bundle$cutoff_dir),
    transform = bundle$transform,
    retrospective_start = if (nrow(bundle$retros)) as.character(min(bundle$retros$date, na.rm = TRUE)) else NA_character_,
    retrospective_end = if (nrow(bundle$retros)) as.character(max(bundle$retros$date, na.rm = TRUE)) else NA_character_,
    window_start = as.character(parts$window_start),
    window_end = as.character(parts$window_end),
    n_usgs_history_window = nrow(parts$retros),
    n_usgs_heldout_window = nrow(parts$future_usgs),
    n_glofas_retrospective_window = sum(is.finite(parts$retros$glofas)),
    n_nws_retrospective_window = sum(is.finite(parts$retros$nws)),
    n_glofas_forecast_rows = sum(parts$forecast_long$product == "GloFAS"),
    n_nws_forecast_rows = sum(parts$forecast_long$product == "NWS"),
    max_glofas_horizon = suppressWarnings(max(parts$forecast_long$horizon[parts$forecast_long$product == "GloFAS"], na.rm = TRUE)),
    max_nws_horizon = suppressWarnings(max(parts$forecast_long$horizon[parts$forecast_long$product == "NWS"], na.rm = TRUE)),
    prediction_run_id = prediction_run_id %||% NA_character_,
    qdesn_overlay_available = nrow(overlay$predictions) > 0L,
    qdesn_prediction_rows = nrow(overlay$predictions),
    qdesn_draw_rows = nrow(overlay$draws),
    monotone_qhat_available = q_col_available,
    pre_cutoff_quantile_history_available = FALSE,
    history_quantile_status = "not_available_in_storage_light_promoted_tables",
    synthesis_figure = app_prefer_repo_relative_path(paths$synthesis),
    quantile_independent_figure = app_prefer_repo_relative_path(paths$quantile_independent),
    quantile_monotone_figure = app_prefer_repo_relative_path(paths$quantile_monotone),
    stringsAsFactors = FALSE
  )
}

app_manifest_row_cutoff_figure <- function(figure_id, cutoff_date, path, figure_type, prediction_run_id, notes) {
  data.frame(
    figure_id = figure_id,
    cutoff_date = as.character(as.Date(cutoff_date)),
    figure_type = figure_type,
    output_path = app_prefer_repo_relative_path(path),
    source_script = "application/scripts/43_make_glofas_multivariate_cutoff_figures.R",
    prediction_run_id = prediction_run_id %||% NA_character_,
    git_sha = app_git_sha(short = FALSE),
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    notes = notes,
    stringsAsFactors = FALSE
  )
}

app_make_glofas_multivariate_cutoff_figures <- function(
  source_root,
  output_root,
  prediction_run_id = NULL,
  before_days = 60L,
  after_days = 30L,
  transform = "log1p"
) {
  source_root <- app_resolve_path(source_root, must_work = TRUE)
  output_root <- app_resolve_path(output_root, must_work = FALSE)
  app_ensure_dir(output_root)
  app_ensure_dir(file.path(output_root, "figures", "multivariate_synthesis_by_cutoff"))
  app_ensure_dir(file.path(output_root, "figures", "multivariate_quantiles_by_cutoff"))
  app_ensure_dir(file.path(output_root, "tables"))
  app_ensure_dir(file.path(output_root, "logs"))

  qdesn <- app_load_cutoff_qdesn_predictions(prediction_run_id = prediction_run_id)
  cutoffs <- app_discover_multivariate_cutoff_dirs(source_root)
  manifests <- list()
  validations <- list()

  for (i in seq_len(nrow(cutoffs))) {
    cutoff_date <- cutoffs$cutoff_date[[i]]
    bundle <- app_load_multivariate_cutoff_bundle(cutoffs$cutoff_dir[[i]], transform = transform)
    overlay <- app_filter_qdesn_overlay(qdesn, cutoff_date)
    slug <- app_cutoff_figure_slug(cutoff_date)
    synth_dir <- file.path(output_root, "figures", "multivariate_synthesis_by_cutoff", slug)
    q_dir <- file.path(output_root, "figures", "multivariate_quantiles_by_cutoff", slug)
    paths <- list(
      synthesis = file.path(synth_dir, paste0("multivariate_synthesis_context__", slug, ".pdf")),
      quantile_independent = file.path(q_dir, paste0("qdesn_quantile_paths_independent__", slug, ".pdf")),
      quantile_monotone = file.path(q_dir, paste0("qdesn_quantile_paths_monotone__", slug, ".pdf"))
    )

    app_plot_multivariate_synthesis_cutoff(bundle, overlay, paths$synthesis, before_days = before_days, after_days = after_days)
    app_plot_quantile_paths_cutoff(bundle, overlay, paths$quantile_independent, before_days = before_days, after_days = after_days, monotone = FALSE)
    app_plot_quantile_paths_cutoff(bundle, overlay, paths$quantile_monotone, before_days = before_days, after_days = after_days, monotone = TRUE)

    manifests[[length(manifests) + 1L]] <- app_manifest_row_cutoff_figure(
      paste0("multivariate_synthesis_context__", slug),
      cutoff_date,
      paths$synthesis,
      "multivariate_synthesis_by_cutoff",
      prediction_run_id,
      "Cutoff-centered retrospective plus forecast-ensemble context with optional current Q-DESN overlay."
    )
    manifests[[length(manifests) + 1L]] <- app_manifest_row_cutoff_figure(
      paste0("qdesn_quantile_paths_independent__", slug),
      cutoff_date,
      paths$quantile_independent,
      "multivariate_quantiles_by_cutoff",
      prediction_run_id,
      "Independent Q-DESN forecast quantile paths with source context; historical fitted quantile paths are not available in the promoted storage-light tables."
    )
    manifests[[length(manifests) + 1L]] <- app_manifest_row_cutoff_figure(
      paste0("qdesn_quantile_paths_monotone__", slug),
      cutoff_date,
      paths$quantile_monotone,
      "multivariate_quantiles_by_cutoff",
      prediction_run_id,
      "Monotone-corrected Q-DESN forecast quantile paths with source context; intervals come from independent posterior predictive draws."
    )
    validations[[length(validations) + 1L]] <- app_cutoff_validation_row(
      bundle,
      overlay,
      paths,
      before_days = before_days,
      after_days = after_days,
      prediction_run_id = prediction_run_id
    )
  }

  manifest <- do.call(rbind, manifests)
  validation <- do.call(rbind, validations)
  validation$max_glofas_horizon[!is.finite(validation$max_glofas_horizon)] <- NA_integer_
  validation$max_nws_horizon[!is.finite(validation$max_nws_horizon)] <- NA_integer_
  app_write_csv(manifest, file.path(output_root, "tables", "cutoff_figure_manifest.csv"))
  app_write_csv(validation, file.path(output_root, "tables", "cutoff_figure_validation.csv"))
  app_write_git_state(file.path(output_root, "logs", "git_state.txt"))
  app_write_session_info(file.path(output_root, "logs", "session_info.txt"))
  invisible(list(manifest = manifest, validation = validation, output_root = output_root))
}
