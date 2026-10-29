# Alignment diagnostics for historical GloFAS discrepancy fits.

app_glofas_alignment_require_columns <- function(x, required, label) {
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(sprintf("%s is missing required columns: %s.", label, paste(missing, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_alignment_lag_by_date <- function(values, dates, lag_days = 1L) {
  dates <- as.Date(dates)
  values <- as.numeric(values)
  values[match(dates - as.integer(lag_days), dates)]
}

app_glofas_history_alignment_metrics <- function(
  history,
  windows = c(all = Inf, last1000 = 1000, last200 = 200, last50 = 50)
) {
  required <- c(
    "target_date", "y_reference", "glofas_retrospective", "observed_discrepancy",
    "q_y_median", "d_g_median"
  )
  app_glofas_alignment_require_columns(history, required, "Historical fit summary")
  history$target_date <- as.Date(history$target_date)
  history <- history[order(history$target_date), , drop = FALSE]
  if (anyNA(history$target_date) || anyDuplicated(history$target_date)) {
    stop("Historical fit summary must have unique finite target dates.", call. = FALSE)
  }

  series <- list(
    usgs = list(observed = history$y_reference, fitted = history$q_y_median),
    discrepancy = list(observed = history$observed_discrepancy, fitted = history$d_g_median)
  )
  rows <- list()
  k <- 0L
  for (window_name in names(windows)) {
    n_window <- as.numeric(windows[[window_name]])
    idx <- seq_len(nrow(history))
    if (is.finite(n_window)) idx <- utils::tail(idx, min(as.integer(n_window), length(idx)))
    for (series_name in names(series)) {
      observed <- as.numeric(series[[series_name]]$observed)
      fitted <- as.numeric(series[[series_name]]$fitted)
      previous <- app_glofas_alignment_lag_by_date(observed, history$target_date, 1L)
      next_day <- app_glofas_alignment_lag_by_date(observed, history$target_date, -1L)
      ok_current <- idx[is.finite(observed[idx]) & is.finite(fitted[idx])]
      ok_previous <- idx[is.finite(previous[idx]) & is.finite(observed[idx]) & is.finite(fitted[idx])]
      ok_next <- idx[is.finite(next_day[idx]) & is.finite(fitted[idx])]
      mae_current <- mean(abs(fitted[ok_current] - observed[ok_current]))
      mae_previous <- mean(abs(fitted[ok_previous] - previous[ok_previous]))
      mae_next <- mean(abs(fitted[ok_next] - next_day[ok_next]))
      persistence_mae <- mean(abs(previous[ok_previous] - observed[ok_previous]))
      candidates <- c(target_date = mae_current, previous_day = mae_previous, next_day = mae_next)
      closest <- names(candidates)[[which.min(candidates)]]
      k <- k + 1L
      rows[[k]] <- data.frame(
        window = window_name,
        series = series_name,
        n_target_date = length(ok_current),
        mae_target_date = mae_current,
        n_previous_day = length(ok_previous),
        mae_previous_day = mae_previous,
        persistence_mae_target_date = persistence_mae,
        improvement_over_persistence_fraction = if (is.finite(persistence_mae) && persistence_mae > 0) {
          1 - mae_current / persistence_mae
        } else {
          NA_real_
        },
        n_next_day = length(ok_next),
        mae_next_day = mae_next,
        closest_observed_alignment = closest,
        previous_to_target_mae_ratio = mae_previous / mae_current,
        interpretation = if (identical(closest, "previous_day")) {
          "fitted path tracks the previous observed day most closely"
        } else if (identical(closest, "target_date")) {
          "fitted path tracks the declared target date most closely"
        } else {
          "fitted path tracks the next observed day most closely"
        },
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

app_glofas_alignment_audit_row <- function(item, value, tolerance, passed, detail) {
  data.frame(
    audit_item = item,
    observed_value = as.numeric(value),
    tolerance = as.numeric(tolerance),
    passed = isTRUE(passed),
    detail = detail,
    stringsAsFactors = FALSE
  )
}

app_glofas_alignment_max_error <- function(observed, expected) {
  observed <- as.numeric(observed)
  expected <- as.numeric(expected)
  if (length(observed) != length(expected) || !length(observed) ||
      any(!is.finite(observed)) || any(!is.finite(expected))) {
    return(Inf)
  }
  max(abs(observed - expected))
}

app_glofas_source_panel_alignment_audit <- function(panel, design, tolerance = 1.0e-10) {
  app_glofas_alignment_require_columns(
    panel,
    c(
      "origin_date", "target_date", "horizon", "is_retrospective", "is_ensemble",
      "y_reference", "g_glofas", "y_transformed", "g_transformed"
    ),
    "Source application panel"
  )
  required_design <- c("base_panel_full", "base_panel_disc_full")
  missing <- setdiff(required_design, names(design))
  if (length(missing)) {
    stop(sprintf("Serialized design is missing required fields: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }

  retrospective <- panel[panel$is_retrospective %in% TRUE, , drop = FALSE]
  retrospective$origin_date <- as.Date(retrospective$origin_date)
  retrospective$target_date <- as.Date(retrospective$target_date)
  retrospective <- retrospective[order(retrospective$target_date), , drop = FALSE]
  full <- design$base_panel_full
  discrepancy <- design$base_panel_disc_full
  full$target_date <- as.Date(full$target_date)
  discrepancy$target_date <- as.Date(discrepancy$target_date)
  full <- full[order(full$target_date), , drop = FALSE]
  discrepancy <- discrepancy[order(discrepancy$target_date), , drop = FALSE]

  same_full_dates <- identical(retrospective$target_date, full$target_date)
  same_discrepancy_dates <- identical(retrospective$target_date, discrepancy$target_date)
  y_transform_error <- app_glofas_alignment_max_error(log1p(retrospective$y_reference), retrospective$y_transformed)
  g_transform_error <- app_glofas_alignment_max_error(log1p(retrospective$g_glofas), retrospective$g_transformed)
  y_design_error <- app_glofas_alignment_max_error(retrospective$y_transformed, full$y_transformed)
  g_design_error <- app_glofas_alignment_max_error(retrospective$g_transformed, full$g_transformed)
  discrepancy_design_error <- app_glofas_alignment_max_error(
    retrospective$g_transformed - retrospective$y_transformed,
    discrepancy$y_transformed
  )

  rows <- list(
    app_glofas_alignment_audit_row(
      "source_retrospective_rows_present", nrow(retrospective), 1, nrow(retrospective) > 0L,
      "The source application panel contains historical retrospective rows."
    ),
    app_glofas_alignment_audit_row(
      "source_retrospective_dates_unique", anyDuplicated(retrospective$target_date), 0,
      anyDuplicated(retrospective$target_date) == 0L,
      "Each source retrospective row has one unique target date."
    ),
    app_glofas_alignment_audit_row(
      "source_retrospective_dates_daily", sum(diff(retrospective$target_date) != 1), 0,
      nrow(retrospective) > 1L && all(diff(retrospective$target_date) == 1),
      "Source retrospective target dates are daily and gap free."
    ),
    app_glofas_alignment_audit_row(
      "source_origin_equals_target", sum(retrospective$origin_date != retrospective$target_date), 0,
      all(retrospective$origin_date == retrospective$target_date),
      "Historical source rows assign origin and target to the same calendar date."
    ),
    app_glofas_alignment_audit_row(
      "source_horizon_zero", sum(as.integer(retrospective$horizon) != 0L), 0,
      all(as.integer(retrospective$horizon) == 0L),
      "Historical source rows have horizon zero."
    ),
    app_glofas_alignment_audit_row(
      "source_usgs_log1p_transform", y_transform_error, tolerance, y_transform_error <= tolerance,
      "Transformed USGS values are log1p of the same source row."
    ),
    app_glofas_alignment_audit_row(
      "source_glofas_log1p_transform", g_transform_error, tolerance, g_transform_error <= tolerance,
      "Transformed GloFAS values are log1p of the same source row."
    ),
    app_glofas_alignment_audit_row(
      "source_to_design_full_dates", as.numeric(!same_full_dates), 0, same_full_dates,
      "Serialized full-history design dates exactly equal source retrospective target dates."
    ),
    app_glofas_alignment_audit_row(
      "source_to_discrepancy_design_dates", as.numeric(!same_discrepancy_dates), 0, same_discrepancy_dates,
      "Serialized discrepancy-history dates exactly equal source retrospective target dates."
    ),
    app_glofas_alignment_audit_row(
      "source_to_design_usgs_values", y_design_error, tolerance,
      same_full_dates && y_design_error <= tolerance,
      "Serialized USGS history reproduces the same-date source values."
    ),
    app_glofas_alignment_audit_row(
      "source_to_design_glofas_values", g_design_error, tolerance,
      same_full_dates && g_design_error <= tolerance,
      "Serialized GloFAS history reproduces the same-date source values."
    ),
    app_glofas_alignment_audit_row(
      "source_to_design_discrepancy_values", discrepancy_design_error, tolerance,
      same_discrepancy_dates && discrepancy_design_error <= tolerance,
      "Serialized discrepancy is same-date transformed GloFAS minus transformed USGS."
    )
  )
  do.call(rbind, rows)
}

app_glofas_history_offset_profile <- function(history, offsets = -3L:3L) {
  required <- c("target_date", "y_reference", "observed_discrepancy", "q_y_median", "d_g_median")
  app_glofas_alignment_require_columns(history, required, "Historical fit summary")
  history$target_date <- as.Date(history$target_date)
  history <- history[order(history$target_date), , drop = FALSE]
  series <- list(
    usgs = list(observed = history$y_reference, fitted = history$q_y_median),
    discrepancy = list(observed = history$observed_discrepancy, fitted = history$d_g_median)
  )
  rows <- list()
  k <- 0L
  for (series_name in names(series)) {
    observed <- as.numeric(series[[series_name]]$observed)
    fitted <- as.numeric(series[[series_name]]$fitted)
    for (offset in as.integer(offsets)) {
      matched <- observed[match(history$target_date + offset, history$target_date)]
      keep <- is.finite(fitted) & is.finite(matched)
      k <- k + 1L
      rows[[k]] <- data.frame(
        series = series_name,
        observed_date_offset_days = offset,
        n = sum(keep),
        mae = mean(abs(fitted[keep] - matched[keep])),
        rmse = sqrt(mean((fitted[keep] - matched[keep])^2)),
        correlation = if (sum(keep) > 2L) stats::cor(fitted[keep], matched[keep]) else NA_real_,
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

app_glofas_history_innovation_diagnostics <- function(history) {
  required <- c("target_date", "y_reference", "observed_discrepancy", "q_y_median", "d_g_median")
  app_glofas_alignment_require_columns(history, required, "Historical fit summary")
  history$target_date <- as.Date(history$target_date)
  history <- history[order(history$target_date), , drop = FALSE]
  series <- list(
    usgs = list(observed = history$y_reference, fitted = history$q_y_median),
    discrepancy = list(observed = history$observed_discrepancy, fitted = history$d_g_median)
  )
  rows <- lapply(names(series), function(series_name) {
    observed <- as.numeric(series[[series_name]]$observed)
    fitted <- as.numeric(series[[series_name]]$fitted)
    previous <- app_glofas_alignment_lag_by_date(observed, history$target_date, 1L)
    observed_innovation <- observed - previous
    fitted_innovation <- fitted - previous
    keep <- is.finite(observed_innovation) & is.finite(fitted_innovation)
    observed_sd <- stats::sd(observed_innovation[keep])
    fitted_sd <- stats::sd(fitted_innovation[keep])
    data.frame(
      series = series_name,
      n = sum(keep),
      innovation_mae = mean(abs(fitted_innovation[keep] - observed_innovation[keep])),
      fitted_innovation_mean = mean(fitted_innovation[keep]),
      fitted_innovation_sd = fitted_sd,
      observed_innovation_mean = mean(observed_innovation[keep]),
      observed_innovation_sd = observed_sd,
      innovation_correlation = if (sum(keep) > 2L && is.finite(fitted_sd) && fitted_sd > 0 &&
          is.finite(observed_sd) && observed_sd > 0) {
        stats::cor(fitted_innovation[keep], observed_innovation[keep])
      } else {
        NA_real_
      },
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_glofas_history_design_alignment_audit <- function(design, history = NULL, tolerance = 1.0e-10) {
  required_design <- c(
    "base_panel", "base_panel_full", "base_panel_disc_full", "row_info_fixed", "z_fixed",
    "X_beta", "feature_info_beta", "discrepancy_baseline_fixed", "discrepancy_transition_strategy"
  )
  missing <- setdiff(required_design, names(design))
  if (length(missing)) {
    stop(sprintf("Serialized design is missing required fields: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  base <- design$base_panel
  app_glofas_alignment_require_columns(
    base,
    c("target_date", "y_transformed", "g_transformed"),
    "Serialized design base panel"
  )
  dates <- as.Date(base$target_date)
  n <- nrow(base)
  observed_discrepancy <- as.numeric(base$g_transformed) - as.numeric(base$y_transformed)
  baseline <- as.numeric(design$discrepancy_baseline_fixed)
  full_dates <- as.Date(design$base_panel_disc_full$target_date)
  full_discrepancy <- as.numeric(design$base_panel_disc_full$y_transformed)
  expected_baseline <- full_discrepancy[match(dates - 1L, full_dates)]
  row_info <- design$row_info_fixed
  rows <- list(
    app_glofas_alignment_audit_row(
      "target_dates_unique", anyDuplicated(dates), 0, anyDuplicated(dates) == 0L,
      "Each retained design row must have one target date."
    ),
    app_glofas_alignment_audit_row(
      "target_dates_daily", sum(diff(dates) != 1), 0, all(diff(dates) == 1),
      "The authoritative retrospective contract is daily and gap free."
    ),
    app_glofas_alignment_audit_row(
      "discrepancy_panel_same_day",
      app_glofas_alignment_max_error(observed_discrepancy, full_discrepancy[match(dates, full_dates)]),
      tolerance,
      app_glofas_alignment_max_error(observed_discrepancy, full_discrepancy[match(dates, full_dates)]) <= tolerance,
      "The discrepancy feature panel equals same-date transformed GloFAS minus same-date transformed USGS."
    ),
    app_glofas_alignment_audit_row(
      "persistence_baseline_previous_day", max(abs(baseline - expected_baseline)), tolerance,
      all(is.finite(expected_baseline)) && max(abs(baseline - expected_baseline)) <= tolerance,
      "At target date t, the persistence baseline must equal observed discrepancy at t-1."
    ),
    app_glofas_alignment_audit_row(
      "stacked_usgs_response_same_day", max(abs(design$z_fixed[seq_len(n)] - base$y_transformed)), tolerance,
      max(abs(design$z_fixed[seq_len(n)] - base$y_transformed)) <= tolerance,
      "The USGS response stack uses the response observed at its declared target date."
    ),
    app_glofas_alignment_audit_row(
      "stacked_glofas_innovation_same_day",
      max(abs(design$z_fixed[n + seq_len(n)] - (base$g_transformed - baseline))), tolerance,
      max(abs(design$z_fixed[n + seq_len(n)] - (base$g_transformed - baseline))) <= tolerance,
      "The GloFAS response stack uses same-day GloFAS after subtracting the declared t-1 baseline."
    ),
    app_glofas_alignment_audit_row(
      "row_info_usgs_target_dates", sum(as.Date(row_info$target_date[seq_len(n)]) != dates), 0,
      identical(as.Date(row_info$target_date[seq_len(n)]), dates),
      "USGS likelihood rows preserve base-panel target dates."
    ),
    app_glofas_alignment_audit_row(
      "row_info_glofas_target_dates", sum(as.Date(row_info$target_date[n + seq_len(n)]) != dates), 0,
      identical(as.Date(row_info$target_date[n + seq_len(n)]), dates),
      "GloFAS likelihood rows preserve base-panel target dates."
    )
  )

  lag1_info <- design$feature_info_beta[
    design$feature_info_beta$block == "direct_output_lag" &
      design$feature_info_beta$variable == "y" &
      as.integer(design$feature_info_beta$lag) == 1L,
    , drop = FALSE
  ]
  if (nrow(lag1_info) == 1L) {
    column_name <- as.character(lag1_info$column_name[[1L]])
    column_index <- as.integer(lag1_info$column_index[[1L]])
    scale_info <- design$readout_scale_info$output_lags
    center <- as.numeric(scale_info$center[[column_name]])
    scale <- as.numeric(scale_info$scale[[column_name]])
    raw_lag1 <- as.numeric(design$X_beta[, column_index]) * scale + center
    full_y_dates <- as.Date(design$base_panel_full$target_date)
    full_y <- as.numeric(design$base_panel_full$y_transformed)
    expected_lag1 <- full_y[match(dates - 1L, full_y_dates)]
    lag1_error <- max(abs(raw_lag1 - expected_lag1))
    rows[[length(rows) + 1L]] <- app_glofas_alignment_audit_row(
      "beta_direct_y_lag1_previous_day", lag1_error, tolerance,
      all(is.finite(expected_lag1)) && lag1_error <= tolerance,
      "The direct y_lag_1 feature is the transformed USGS value at target_date - 1."
    )
  }

  if (!is.null(history)) {
    required_history <- c("target_date", "y_reference", "glofas_retrospective", "observed_discrepancy")
    app_glofas_alignment_require_columns(history, required_history, "Historical fit export")
    history$target_date <- as.Date(history$target_date)
    history <- history[order(history$target_date), , drop = FALSE]
    idx <- match(dates, history$target_date)
    exact_dates <- !anyNA(idx) && nrow(history) == n && identical(history$target_date[idx], dates)
    rows[[length(rows) + 1L]] <- app_glofas_alignment_audit_row(
      "history_export_target_dates", sum(is.na(idx)), 0, exact_dates,
      "The exported plotting table must contain exactly the serialized design target dates."
    )
    if (exact_dates) {
      comparisons <- list(
        history_export_usgs = cbind(history$y_reference[idx], base$y_transformed),
        history_export_glofas = cbind(history$glofas_retrospective[idx], base$g_transformed),
        history_export_discrepancy = cbind(history$observed_discrepancy[idx], observed_discrepancy)
      )
      for (item in names(comparisons)) {
        error <- max(abs(comparisons[[item]][, 1L] - comparisons[[item]][, 2L]))
        rows[[length(rows) + 1L]] <- app_glofas_alignment_audit_row(
          item, error, tolerance, error <= tolerance,
          "Exported source values are reproduced from the same serialized design row."
        )
      }
    }
  }
  do.call(rbind, rows)
}

app_glofas_history_export_reconstruction_audit <- function(
  fit,
  design,
  history,
  recent_n = 200L,
  tolerance = 1.0e-10
) {
  required <- c("target_date", "q_y_mean", "q_y_median", "d_g_mean", "d_g_median")
  app_glofas_alignment_require_columns(history, required, "Historical fit export")
  theta <- as.matrix(fit$draws$theta)
  if (!nrow(theta) || any(!is.finite(theta))) stop("Posterior theta draws are unavailable or non-finite.", call. = FALSE)
  history$target_date <- as.Date(history$target_date)
  history <- history[order(history$target_date), , drop = FALSE]
  design_dates <- as.Date(design$base_panel$target_date)
  idx <- utils::tail(seq_len(nrow(design$X_beta)), min(as.integer(recent_n), nrow(design$X_beta)))
  export_idx <- match(design_dates[idx], history$target_date)
  if (anyNA(export_idx)) stop("Historical fit export is missing recent serialized design dates.", call. = FALSE)
  beta <- theta[, design$beta_index, drop = FALSE]
  alpha <- theta[, design$alpha_index, drop = FALSE]
  q_y <- beta %*% t(design$X_beta[idx, , drop = FALSE])
  d_g <- sweep(
    alpha %*% t(design$X_alpha[idx, , drop = FALSE]),
    2L,
    as.numeric(design$discrepancy_baseline_fixed[idx]),
    "+"
  )
  recomputed <- list(
    q_y_mean = colMeans(q_y),
    q_y_median = apply(q_y, 2L, stats::median),
    d_g_mean = colMeans(d_g),
    d_g_median = apply(d_g, 2L, stats::median)
  )
  rows <- lapply(names(recomputed), function(name) {
    error <- max(abs(as.numeric(recomputed[[name]]) - as.numeric(history[[name]][export_idx])))
    app_glofas_alignment_audit_row(
      paste0("export_reconstruction_", name), error, tolerance, error <= tolerance,
      sprintf("Recent %d-date export is recomputed directly from posterior draws and the serialized design.", length(idx))
    )
  })
  do.call(rbind, rows)
}

app_glofas_history_alignment_tail <- function(history, n = 20L) {
  required <- c("target_date", "y_reference", "q_y_median", "observed_discrepancy", "d_g_median")
  app_glofas_alignment_require_columns(history, required, "Historical fit summary")
  history$target_date <- as.Date(history$target_date)
  history <- history[order(history$target_date), , drop = FALSE]
  y_previous <- app_glofas_alignment_lag_by_date(history$y_reference, history$target_date, 1L)
  d_previous <- app_glofas_alignment_lag_by_date(history$observed_discrepancy, history$target_date, 1L)
  out <- data.frame(
    target_date = history$target_date,
    usgs_observed = history$y_reference,
    usgs_previous_day = y_previous,
    usgs_fitted = history$q_y_median,
    usgs_fit_minus_previous_day = history$q_y_median - y_previous,
    discrepancy_observed = history$observed_discrepancy,
    discrepancy_previous_day = d_previous,
    discrepancy_fitted = history$d_g_median,
    discrepancy_fit_minus_previous_day = history$d_g_median - d_previous,
    stringsAsFactors = FALSE
  )
  utils::tail(out, min(as.integer(n), nrow(out)))
}

app_plot_glofas_history_alignment <- function(history, path, recent_n = 200L) {
  required <- c("target_date", "y_reference", "q_y_median", "observed_discrepancy", "d_g_median")
  app_glofas_alignment_require_columns(history, required, "Historical fit summary")
  history$target_date <- as.Date(history$target_date)
  history <- history[order(history$target_date), , drop = FALSE]
  history$y_previous <- app_glofas_alignment_lag_by_date(history$y_reference, history$target_date, 1L)
  history$d_previous <- app_glofas_alignment_lag_by_date(history$observed_discrepancy, history$target_date, 1L)
  recent <- utils::tail(history, min(as.integer(recent_n), nrow(history)))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(path, width = 10, height = 7.2)
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- graphics::par(mfrow = c(2, 1), mar = c(3.5, 4.2, 2.8, 1.0), oma = c(0, 0, 1.4, 0))
  on.exit(graphics::par(old), add = TRUE)
  panels <- list(
    list(
      observed = recent$y_reference, previous = recent$y_previous, fitted = recent$q_y_median,
      color = "#2f6f9f", ylab = "Transformed streamflow", title = "USGS historical conditional fit"
    ),
    list(
      observed = recent$observed_discrepancy, previous = recent$d_previous, fitted = recent$d_g_median,
      color = "#8f3d56", ylab = "Transformed discrepancy", title = "GloFAS - USGS discrepancy historical conditional fit"
    )
  )
  for (panel_index in seq_along(panels)) {
    panel <- panels[[panel_index]]
    yr <- range(c(panel$observed, panel$previous, panel$fitted), na.rm = TRUE)
    graphics::plot(
      recent$target_date,
      panel$observed,
      type = "n",
      ylim = yr,
      xlab = if (panel_index == length(panels)) "Date" else "",
      ylab = panel$ylab,
      main = panel$title
    )
    graphics::grid(col = "gray90")
    graphics::lines(recent$target_date, panel$fitted, col = panel$color, lwd = 1.8)
    graphics::lines(recent$target_date, panel$previous, col = "#777777", lty = 2, lwd = 1.2)
    graphics::lines(recent$target_date, panel$observed, col = "#111111", lwd = 1.0)
    graphics::legend(
      "topleft",
      legend = c("Observed at target date t", "Fitted value assigned to target date t", "Observed persistence baseline from t-1"),
      col = c("#111111", panel$color, "#777777"), lty = c(1, 1, 2), lwd = c(1, 1.8, 1.2),
      bty = "o", bg = "white", box.col = "white", cex = 0.72
    )
  }
  graphics::mtext(
    "Calendar dates are unchanged; closeness to the dashed t-1 path diagnoses persistence-like model behavior.",
    outer = TRUE,
    side = 3,
    cex = 0.78
  )
  invisible(path)
}
