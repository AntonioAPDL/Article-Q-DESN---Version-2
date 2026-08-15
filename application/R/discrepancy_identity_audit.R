# Identity and reconciliation diagnostics for GloFAS discrepancy predictions.

app_identity_abs_summary <- function(x) {
  x <- abs(as.numeric(x))
  x <- x[is.finite(x)]
  if (!length(x)) {
    return(data.frame(
      n = 0L,
      mean_abs = NA_real_,
      median_abs = NA_real_,
      q95_abs = NA_real_,
      max_abs = NA_real_,
      stringsAsFactors = FALSE
    ))
  }
  data.frame(
    n = length(x),
    mean_abs = mean(x),
    median_abs = stats::median(x),
    q95_abs = as.numeric(stats::quantile(x, 0.95, names = FALSE, na.rm = TRUE)),
    max_abs = max(x),
    stringsAsFactors = FALSE
  )
}

app_identity_group_summary <- function(rows, group_cols, value_cols) {
  if (!nrow(rows)) return(data.frame())
  missing <- setdiff(c(group_cols, value_cols), names(rows))
  if (length(missing)) {
    stop(sprintf("Identity audit rows are missing columns: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  keys <- unique(rows[, group_cols, drop = FALSE])
  out <- vector("list", nrow(keys))
  for (i in seq_len(nrow(keys))) {
    idx <- rep(TRUE, nrow(rows))
    for (nm in group_cols) idx <- idx & rows[[nm]] == keys[[nm]][[i]]
    block <- rows[idx, , drop = FALSE]
    stats <- lapply(value_cols, function(nm) {
      s <- app_identity_abs_summary(block[[nm]])
      names(s) <- paste(nm, names(s), sep = "_")
      s
    })
    out[[i]] <- cbind(keys[i, , drop = FALSE], do.call(cbind, stats))
  }
  do.call(rbind, out)
}

app_discrepancy_prediction_identity_rows <- function(predictions) {
  required <- c("model_id", "model_family", "origin_date", "target_date", "horizon", "quantile_level", "qhat", "q_g_hat", "d_g_hat")
  app_check_required_columns(predictions, required, "prediction table")
  pred <- predictions[predictions$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  if (!nrow(pred)) return(data.frame())

  pred$origin_date <- as.Date(pred$origin_date)
  pred$target_date <- as.Date(pred$target_date)
  pred$horizon <- as.integer(pred$horizon)
  pred$quantile_level <- as.numeric(pred$quantile_level)

  make_rows <- function(value_col, identity_expected) {
    if (!value_col %in% names(pred)) return(data.frame())
    q_y <- as.numeric(pred[[value_col]])
    q_g <- as.numeric(pred$q_g_hat)
    d_g <- as.numeric(pred$d_g_hat)
    raw <- if ("raw_glofas_quantile" %in% names(pred)) as.numeric(pred$raw_glofas_quantile) else rep(NA_real_, nrow(pred))
    out <- data.frame(
      model_id = pred$model_id,
      fit_id = if ("fit_id" %in% names(pred)) pred$fit_id else NA_character_,
      source_quantile_id = if ("source_quantile_id" %in% names(pred)) pred$source_quantile_id else NA_character_,
      value_col = value_col,
      identity_expected = identity_expected,
      origin_date = pred$origin_date,
      target_date = pred$target_date,
      horizon = pred$horizon,
      quantile_level = pred$quantile_level,
      q_y_value = q_y,
      q_g_hat = q_g,
      d_g_hat = d_g,
      raw_glofas_quantile = raw,
      reconstructed_glofas_from_reference = q_y + d_g,
      reconstructed_reference_from_glofas = q_g - d_g,
      reference_identity_error = q_y - (q_g - d_g),
      glofas_identity_error = q_g - (q_y + d_g),
      model_glofas_minus_raw_glofas = q_g - raw,
      stringsAsFactors = FALSE
    )
    if ("qhat" %in% names(pred) && value_col != "qhat") {
      out$posthoc_synthesis_adjustment <- q_y - as.numeric(pred$qhat)
    } else {
      out$posthoc_synthesis_adjustment <- 0
    }
    out
  }

  out <- list(make_rows("qhat", TRUE))
  if ("qhat_monotone" %in% names(pred)) {
    out[[length(out) + 1L]] <- make_rows("qhat_monotone", FALSE)
  }
  do.call(rbind, out)
}

app_discrepancy_draw_identity_summary <- function(draws) {
  if (is.null(draws) || !nrow(draws)) return(data.frame())
  required <- c("model_id", "model_family", "quantile_level", "q_y_draw", "q_g_draw", "d_g_draw")
  app_check_required_columns(draws, required, "posterior draw prediction table")
  draws <- draws[draws$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  if (!nrow(draws)) return(data.frame())
  draws$quantile_level <- as.numeric(draws$quantile_level)
  q_y <- as.numeric(draws$q_y_draw)
  q_g <- as.numeric(draws$q_g_draw)
  d_g <- as.numeric(draws$d_g_draw)
  raw <- if ("raw_glofas_quantile" %in% names(draws)) as.numeric(draws$raw_glofas_quantile) else rep(NA_real_, nrow(draws))
  rows <- data.frame(
    model_id = draws$model_id,
    quantile_level = draws$quantile_level,
    reference_identity_error = q_y - (q_g - d_g),
    glofas_identity_error = q_g - (q_y + d_g),
    model_glofas_minus_raw_glofas = q_g - raw,
    stringsAsFactors = FALSE
  )
  app_identity_group_summary(
    rows,
    c("model_id", "quantile_level"),
    c("reference_identity_error", "glofas_identity_error", "model_glofas_minus_raw_glofas")
  )
}

app_discrepancy_identity_audit <- function(predictions, draws = NULL, identity_tol = 1.0e-8) {
  row_checks <- app_discrepancy_prediction_identity_rows(predictions)
  if (!nrow(row_checks)) {
    return(list(
      prediction_row_checks = row_checks,
      prediction_summary = data.frame(),
      prediction_by_quantile = data.frame(),
      prediction_by_horizon = data.frame(),
      draw_summary = data.frame(),
      readiness = data.frame()
    ))
  }

  value_cols <- c(
    "reference_identity_error",
    "glofas_identity_error",
    "model_glofas_minus_raw_glofas",
    "posthoc_synthesis_adjustment"
  )
  summary <- app_identity_group_summary(row_checks, c("model_id", "value_col", "identity_expected"), value_cols)
  by_quantile <- app_identity_group_summary(row_checks, c("model_id", "value_col", "quantile_level", "identity_expected"), value_cols)
  by_horizon <- app_identity_group_summary(row_checks, c("model_id", "value_col", "horizon", "identity_expected"), value_cols)
  draw_summary <- app_discrepancy_draw_identity_summary(draws)

  independent <- summary[summary$value_col == "qhat" & summary$identity_expected, , drop = FALSE]
  monotone <- summary[summary$value_col == "qhat_monotone", , drop = FALSE]
  draw_max <- if (nrow(draw_summary)) max(draw_summary$reference_identity_error_max_abs, na.rm = TRUE) else NA_real_
  if (!is.finite(draw_max)) draw_max <- NA_real_
  readiness <- data.frame(
    check = c(
      "independent_prediction_reference_identity",
      "independent_prediction_glofas_identity",
      "posterior_draw_reference_identity",
      "monotone_synthesis_identity_expected",
      "monotone_synthesis_identity_error_recorded"
    ),
    passed = c(
      nrow(independent) > 0L && max(independent$reference_identity_error_max_abs, na.rm = TRUE) <= identity_tol,
      nrow(independent) > 0L && max(independent$glofas_identity_error_max_abs, na.rm = TRUE) <= identity_tol,
      is.na(draw_max) || draw_max <= identity_tol,
      TRUE,
      if (nrow(monotone)) max(monotone$reference_identity_error_max_abs, na.rm = TRUE) > identity_tol else TRUE
    ),
    detail = c(
      if (nrow(independent)) sprintf("max_abs=%.4g", max(independent$reference_identity_error_max_abs, na.rm = TRUE)) else "no independent qhat rows",
      if (nrow(independent)) sprintf("max_abs=%.4g", max(independent$glofas_identity_error_max_abs, na.rm = TRUE)) else "no independent qhat rows",
      if (is.na(draw_max)) "no posterior draw rows" else sprintf("max_abs=%.4g", draw_max),
      "qhat_monotone is post-hoc isotonic synthesis; it is not required to preserve q_g = q_y + d_g unless q_g or d_g are reprojected too",
      if (nrow(monotone)) sprintf("max_abs=%.4g; recorded as synthesis adjustment, not a sign failure", max(monotone$reference_identity_error_max_abs, na.rm = TRUE)) else "no qhat_monotone rows"
    ),
    stringsAsFactors = FALSE
  )

  list(
    prediction_row_checks = row_checks,
    prediction_summary = summary,
    prediction_by_quantile = by_quantile,
    prediction_by_horizon = by_horizon,
    draw_summary = draw_summary,
    readiness = readiness
  )
}

app_plot_discrepancy_identity_reconciliation <- function(row_checks, path) {
  if (!nrow(row_checks)) return(invisible(NULL))
  app_ensure_dir(dirname(path))
  grDevices::pdf(path, width = 8.0, height = 6.2)
  on.exit(grDevices::dev.off(), add = TRUE)

  old_par <- par(no.readonly = TRUE)
  on.exit(par(old_par), add = TRUE)
  par(mfrow = c(2, 2), mar = c(4.0, 4.0, 2.5, 1.2))

  plot_metric <- function(value_col, y_col, title, ylab, hline = 0) {
    block <- row_checks[row_checks$value_col == value_col, , drop = FALSE]
    if (!nrow(block)) {
      plot.new()
      title(title)
      text(0.5, 0.5, "not available")
      return(invisible(NULL))
    }
    x <- block$horizon
    y <- as.numeric(block[[y_col]])
    plot(x, y, pch = 19, cex = 0.55, col = "#2563eb", xlab = "Forecast horizon", ylab = ylab, main = title)
    grid(col = "gray90")
    abline(h = hline, lty = 2, col = "gray55")
    invisible(NULL)
  }

  plot_metric("qhat", "reference_identity_error", "Independent identity", expression(q[y] - (q[g] - d[g])))
  plot_metric("qhat_monotone", "reference_identity_error", "Post-hoc monotone identity", expression(q[y]^mono - (q[g] - d[g])))
  plot_metric("qhat", "model_glofas_minus_raw_glofas", "Model GloFAS vs raw GloFAS", expression(q[g] - q[g]^raw))
  plot_metric("qhat_monotone", "posthoc_synthesis_adjustment", "Isotonic synthesis adjustment", expression(q[y]^mono - q[y]))
  invisible(path)
}

app_write_discrepancy_identity_audit <- function(predictions, draws, tables_dir, figures_dir, identity_tol = 1.0e-8) {
  audit <- app_discrepancy_identity_audit(predictions, draws, identity_tol = identity_tol)
  app_write_csv(audit$prediction_row_checks, file.path(tables_dir, "discrepancy_identity_prediction_row_checks.csv"))
  app_write_csv(audit$prediction_summary, file.path(tables_dir, "discrepancy_identity_prediction_summary.csv"))
  app_write_csv(audit$prediction_by_quantile, file.path(tables_dir, "discrepancy_identity_prediction_by_quantile.csv"))
  app_write_csv(audit$prediction_by_horizon, file.path(tables_dir, "discrepancy_identity_prediction_by_horizon.csv"))
  app_write_csv(audit$draw_summary, file.path(tables_dir, "discrepancy_identity_draw_summary.csv"))
  app_write_csv(audit$readiness, file.path(tables_dir, "discrepancy_identity_readiness.csv"))

  figure_path <- file.path(figures_dir, "glofas_qdesn_discrepancy_identity_reconciliation.pdf")
  if (nrow(audit$prediction_row_checks)) {
    app_plot_discrepancy_identity_reconciliation(audit$prediction_row_checks, figure_path)
  }
  c(discrepancy_identity_reconciliation = figure_path)
}
