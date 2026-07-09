# No-refit spread calibration diagnostics for synthesized quantile forecasts.

app_interval_spec_table <- function(intervals) {
  if (is.null(intervals) || !length(intervals)) return(data.frame())
  if (is.data.frame(intervals)) {
    required <- c("lower", "upper", "nominal")
    missing <- setdiff(required, names(intervals))
    if (length(missing)) {
      stop(sprintf("Interval table is missing columns: %s", paste(missing, collapse = ", ")), call. = FALSE)
    }
    out <- intervals[, required, drop = FALSE]
  } else {
    out <- do.call(rbind, lapply(intervals, function(x) {
      data.frame(
        lower = as.numeric(x$lower),
        upper = as.numeric(x$upper),
        nominal = as.numeric(x$nominal),
        stringsAsFactors = FALSE
      )
    }))
  }
  out$lower <- as.numeric(out$lower)
  out$upper <- as.numeric(out$upper)
  out$nominal <- as.numeric(out$nominal)
  out
}

app_interval_miss_rows <- function(
  predictions,
  intervals,
  value_col = "qhat_monotone"
) {
  required <- c(
    "model_id", "origin_date", "target_date", "horizon",
    "quantile_level", value_col, "y_reference"
  )
  app_check_required_columns(predictions, required, "prediction table")
  intervals <- app_interval_spec_table(intervals)
  if (!nrow(intervals)) return(data.frame())

  pred <- predictions
  pred$origin_date <- as.Date(pred$origin_date)
  pred$target_date <- as.Date(pred$target_date)
  pred$horizon <- as.integer(pred$horizon)
  pred$quantile_level <- as.numeric(pred$quantile_level)
  pred[[value_col]] <- as.numeric(pred[[value_col]])
  pred$y_reference <- as.numeric(pred$y_reference)

  key_cols <- c("model_id", "origin_date", "target_date", "horizon")
  keys <- unique(pred[, key_cols, drop = FALSE])
  rows <- list()
  k <- 1L
  for (i in seq_len(nrow(keys))) {
    idx <- pred$model_id == keys$model_id[[i]] &
      pred$origin_date == keys$origin_date[[i]] &
      pred$target_date == keys$target_date[[i]] &
      pred$horizon == keys$horizon[[i]]
    block <- pred[idx, , drop = FALSE]
    y <- block$y_reference[[which(is.finite(block$y_reference))[1L]]]
    if (!is.finite(y)) next
    for (j in seq_len(nrow(intervals))) {
      lo_p <- intervals$lower[[j]]
      hi_p <- intervals$upper[[j]]
      lo <- block[[value_col]][match(lo_p, block$quantile_level)]
      hi <- block[[value_col]][match(hi_p, block$quantile_level)]
      if (!is.finite(lo) || !is.finite(hi)) next
      nominal <- intervals$nominal[[j]]
      alpha <- 1 - nominal
      direction <- if (y < lo) {
        "below_lower"
      } else if (y > hi) {
        "above_upper"
      } else {
        "covered"
      }
      rows[[k]] <- cbind(
        keys[i, , drop = FALSE],
        data.frame(
          lower = lo_p,
          upper = hi_p,
          nominal = nominal,
          lower_value = lo,
          upper_value = hi,
          y_reference = y,
          miss_direction = direction,
          covered = direction == "covered",
          interval_width = hi - lo,
          interval_score = app_interval_score(y, lo, hi, alpha),
          stringsAsFactors = FALSE
        )
      )
      k <- k + 1L
    }
  }
  if (!length(rows)) data.frame() else do.call(rbind, rows)
}

app_centered_spread_calibrate <- function(
  predictions,
  factor = 1,
  additive_width = 0,
  center_quantile = 0.5,
  value_col = "qhat_monotone",
  calibration_id = NULL
) {
  required <- c(
    "model_id", "origin_date", "target_date", "horizon",
    "quantile_level", value_col
  )
  app_check_required_columns(predictions, required, "prediction table")
  if (!is.finite(factor) || factor <= 0) {
    stop("Calibration factor must be finite and positive.", call. = FALSE)
  }
  if (!is.finite(additive_width) || additive_width < 0) {
    stop("Additive half-width must be finite and nonnegative.", call. = FALSE)
  }

  pred <- predictions
  pred$origin_date <- as.Date(pred$origin_date)
  pred$target_date <- as.Date(pred$target_date)
  pred$horizon <- as.integer(pred$horizon)
  pred$quantile_level <- as.numeric(pred$quantile_level)
  pred[[value_col]] <- as.numeric(pred[[value_col]])

  key_cols <- c("model_id", "origin_date", "target_date", "horizon")
  keys <- unique(pred[, key_cols, drop = FALSE])
  out <- vector("list", nrow(keys))
  for (i in seq_len(nrow(keys))) {
    idx <- pred$model_id == keys$model_id[[i]] &
      pred$origin_date == keys$origin_date[[i]] &
      pred$target_date == keys$target_date[[i]] &
      pred$horizon == keys$horizon[[i]]
    block <- pred[idx, , drop = FALSE]
    center_idx <- which.min(abs(block$quantile_level - center_quantile))
    center <- block[[value_col]][[center_idx]]
    if (!is.finite(center)) {
      block$qhat <- block[[value_col]]
    } else {
      deviation <- block[[value_col]] - center
      block$qhat <- center + factor * deviation + additive_width * sign(deviation)
    }
    block$qhat_calibrated_pre_monotone <- block$qhat
    out[[i]] <- block
  }
  calibrated <- do.call(rbind, out)
  calibrated$spread_calibration_factor <- factor
  calibrated$spread_calibration_additive_width <- additive_width
  calibrated$spread_calibration_id <- calibration_id %||% sprintf(
    "factor_%s_add_%s",
    formatC(factor, format = "fg", digits = 4),
    formatC(additive_width, format = "fg", digits = 4)
  )
  calibrated <- app_synthesize_quantile_grid(calibrated)
  rownames(calibrated) <- NULL
  calibrated
}

app_score_spread_calibration_grid <- function(
  predictions,
  cfg,
  factors,
  additive_widths = 0,
  model_family = "qdesn_glofas_discrepancy",
  center_quantile = 0.5
) {
  required <- c("model_id", "model_family", "origin_date", "target_date", "horizon", "quantile_level", "qhat_monotone", "y_reference")
  app_check_required_columns(predictions, required, "prediction table")
  pred <- predictions[predictions$model_family == model_family, , drop = FALSE]
  if (!nrow(pred)) {
    stop(sprintf("No prediction rows found for model_family='%s'.", model_family), call. = FALSE)
  }

  scenario_rows <- list()
  k <- 1L
  for (factor in factors) {
    for (additive_width in additive_widths) {
      calibration_id <- sprintf("spread_x%s_plus%s",
        formatC(as.numeric(factor), format = "f", digits = 3),
        formatC(as.numeric(additive_width), format = "f", digits = 3)
      )
      calibrated <- app_centered_spread_calibrate(
        pred,
        factor = as.numeric(factor),
        additive_width = as.numeric(additive_width),
        center_quantile = center_quantile,
        value_col = "qhat_monotone",
        calibration_id = calibration_id
      )
      calibrated$source_model_id <- calibrated$model_id
      calibrated$model_id <- paste(calibrated$model_id, calibration_id, sep = "__")
      scenario_rows[[k]] <- calibrated
      k <- k + 1L
    }
  }

  calibrated_predictions <- do.call(rbind, scenario_rows)
  score_q <- app_score_quantile_predictions_dual(calibrated_predictions, cfg)
  score_i <- app_score_intervals(score_q, cfg)
  score_c <- app_score_crps_grid(score_q)
  summary <- app_score_summary(score_q, score_i, score_c)

  id_map <- unique(calibrated_predictions[, c(
    "model_id", "source_model_id", "spread_calibration_id",
    "spread_calibration_factor", "spread_calibration_additive_width"
  ), drop = FALSE])
  summary <- merge(summary, id_map, by = "model_id", all.x = TRUE, sort = FALSE)
  score_i <- merge(score_i, id_map, by = "model_id", all.x = TRUE, sort = FALSE)
  score_c <- merge(score_c, id_map, by = "model_id", all.x = TRUE, sort = FALSE)
  score_q <- merge(score_q, id_map, by = "model_id", all.x = TRUE, sort = FALSE)

  list(
    predictions = calibrated_predictions,
    score_by_quantile = score_q,
    score_by_interval = score_i,
    score_by_crps = score_c,
    score_summary = summary
  )
}

app_spread_calibration_config <- function(cfg) {
  spec <- cfg$synthesis$spread_calibration %||%
    cfg$post_synthesis$spread_calibration %||%
    cfg$spread_calibration %||%
    list()
  list(
    enabled = app_as_bool(spec$enabled %||% FALSE),
    model_family = spec$model_family %||% "qdesn_glofas_discrepancy",
    factor = as.numeric(spec$factor %||% 1),
    additive_width = as.numeric(spec$additive_width %||% 0),
    center_quantile = as.numeric(spec$center_quantile %||% 0.5),
    calibration_id = spec$calibration_id %||% NULL,
    note = spec$note %||% NA_character_
  )
}

app_apply_spread_calibration_to_predictions <- function(predictions, calibration) {
  if (is.null(calibration)) {
    calibration <- list(enabled = FALSE)
  }
  enabled <- app_as_bool(calibration$enabled %||% FALSE)
  manifest <- data.frame(
    enabled = enabled,
    model_family = calibration$model_family %||% NA_character_,
    spread_calibration_factor = as.numeric(calibration$factor %||% NA_real_),
    spread_calibration_additive_width = as.numeric(calibration$additive_width %||% NA_real_),
    center_quantile = as.numeric(calibration$center_quantile %||% NA_real_),
    calibration_id = calibration$calibration_id %||% NA_character_,
    n_rows_calibrated = 0L,
    stringsAsFactors = FALSE
  )
  if (!enabled) {
    return(list(predictions = predictions, manifest = manifest))
  }

  required <- c("model_id", "model_family", "origin_date", "target_date", "horizon", "quantile_level", "qhat", "qhat_monotone")
  app_check_required_columns(predictions, required, "prediction table")
  model_family <- calibration$model_family %||% "qdesn_glofas_discrepancy"
  idx <- predictions$model_family == model_family
  if (!any(idx)) {
    stop(sprintf("No prediction rows found for spread calibration model_family='%s'.", model_family), call. = FALSE)
  }

  out <- predictions
  out$qhat_uncalibrated <- out$qhat
  out$qhat_monotone_uncalibrated <- out$qhat_monotone
  calibrated <- app_centered_spread_calibrate(
    out[idx, , drop = FALSE],
    factor = as.numeric(calibration$factor %||% 1),
    additive_width = as.numeric(calibration$additive_width %||% 0),
    center_quantile = as.numeric(calibration$center_quantile %||% 0.5),
    value_col = "qhat_monotone",
    calibration_id = calibration$calibration_id %||% NULL
  )
  new_cols <- setdiff(names(calibrated), names(out))
  for (nm in new_cols) out[[nm]] <- NA
  out[idx, names(calibrated)] <- calibrated
  manifest$n_rows_calibrated <- nrow(calibrated)
  manifest$calibration_id <- unique(calibrated$spread_calibration_id)[[1L]]
  list(predictions = out, manifest = manifest)
}

app_interval_miss_summary <- function(interval_rows, group_cols = c("model_id", "nominal", "miss_direction")) {
  if (!nrow(interval_rows)) return(data.frame())
  required <- c(group_cols, "covered")
  app_check_required_columns(interval_rows, required, "interval miss rows")
  keys <- unique(interval_rows[, group_cols, drop = FALSE])
  rows <- vector("list", nrow(keys))
  denominator_cols <- if ("miss_direction" %in% group_cols) setdiff(group_cols, "miss_direction") else group_cols
  for (i in seq_len(nrow(keys))) {
    idx <- rep(TRUE, nrow(interval_rows))
    for (nm in group_cols) idx <- idx & interval_rows[[nm]] == keys[[nm]][[i]]
    block <- interval_rows[idx, , drop = FALSE]
    denom_idx <- rep(TRUE, nrow(interval_rows))
    for (nm in denominator_cols) denom_idx <- denom_idx & interval_rows[[nm]] == keys[[nm]][[i]]
    denom <- sum(denom_idx, na.rm = TRUE)
    rows[[i]] <- cbind(
      keys[i, , drop = FALSE],
      data.frame(
        n = nrow(block),
        fraction = if (denom > 0L) nrow(block) / denom else NA_real_,
        mean_interval_score = mean(block$interval_score, na.rm = TRUE),
        mean_interval_width = mean(block$interval_width, na.rm = TRUE),
        stringsAsFactors = FALSE
      )
    )
  }
  do.call(rbind, rows)
}

app_posterior_draw_spread_summary <- function(draws) {
  if (is.null(draws) || !nrow(draws)) return(data.frame())
  required <- c("model_id", "quantile_level", "horizon", "q_y_draw", "q_g_draw", "d_g_draw")
  app_check_required_columns(draws, required, "posterior draw prediction table")
  draws$quantile_level <- as.numeric(draws$quantile_level)
  draws$horizon <- as.integer(draws$horizon)
  value_cols <- c("q_y_draw", "q_g_draw", "d_g_draw")
  keys <- unique(draws[, c("model_id", "quantile_level", "horizon"), drop = FALSE])
  rows <- vector("list", nrow(keys))
  for (i in seq_len(nrow(keys))) {
    idx <- draws$model_id == keys$model_id[[i]] &
      draws$quantile_level == keys$quantile_level[[i]] &
      draws$horizon == keys$horizon[[i]]
    block <- draws[idx, , drop = FALSE]
    stats <- lapply(value_cols, function(nm) {
      x <- as.numeric(block[[nm]])
      x <- x[is.finite(x)]
      out <- if (length(x)) {
        data.frame(
          mean = mean(x),
          sd = stats::sd(x),
          q05 = as.numeric(stats::quantile(x, 0.05, names = FALSE, na.rm = TRUE)),
          q50 = as.numeric(stats::quantile(x, 0.50, names = FALSE, na.rm = TRUE)),
          q95 = as.numeric(stats::quantile(x, 0.95, names = FALSE, na.rm = TRUE)),
          stringsAsFactors = FALSE
        )
      } else {
        data.frame(mean = NA_real_, sd = NA_real_, q05 = NA_real_, q50 = NA_real_, q95 = NA_real_)
      }
      names(out) <- paste(nm, names(out), sep = "_")
      out
    })
    rows[[i]] <- cbind(
      keys[i, , drop = FALSE],
      data.frame(n_draws = nrow(block), stringsAsFactors = FALSE),
      do.call(cbind, stats)
    )
  }
  do.call(rbind, rows)
}
