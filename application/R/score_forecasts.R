# Forecast scoring for the GloFAS Q-DESN application.

app_check_loss <- function(y, q, p) {
  e <- y - q
  ifelse(e >= 0, p * e, (p - 1) * e)
}

app_interval_score <- function(y, lower, upper, alpha) {
  width <- upper - lower
  width + (2 / alpha) * (lower - y) * (y < lower) + (2 / alpha) * (y - upper) * (y > upper)
}

app_score_quantile_predictions <- function(
  predictions,
  cfg,
  value_col = "qhat",
  score_col = "check_loss"
) {
  required <- c("model_id", "origin_date", "target_date", "horizon", "quantile_level", value_col, "y_reference")
  app_check_required_columns(predictions, required, "prediction table")
  predictions[[score_col]] <- app_check_loss(
    predictions$y_reference,
    predictions[[value_col]],
    predictions$quantile_level
  )
  predictions
}

app_score_quantile_predictions_dual <- function(predictions, cfg) {
  out <- app_score_quantile_predictions(
    predictions,
    cfg,
    value_col = "qhat",
    score_col = "check_loss_independent"
  )
  if ("qhat_monotone" %in% names(out)) {
    out <- app_score_quantile_predictions(
      out,
      cfg,
      value_col = "qhat_monotone",
      score_col = "check_loss_monotone"
    )
    out$check_loss <- out$check_loss_monotone
  } else {
    out$check_loss <- out$check_loss_independent
  }
  out
}

app_score_intervals <- function(predictions, cfg) {
  intervals <- cfg$scoring$intervals %||% list()
  if (!length(intervals)) return(data.frame())
  rows <- list()
  key_cols <- c("model_id", "origin_date", "target_date", "horizon")
  keys <- unique(predictions[, key_cols, drop = FALSE])
  k <- 1L
  for (interval in intervals) {
    lo_p <- as.numeric(interval$lower)
    hi_p <- as.numeric(interval$upper)
    nominal <- as.numeric(interval$nominal)
    alpha <- 1 - nominal
    for (i in seq_len(nrow(keys))) {
      idx <- predictions$model_id == keys$model_id[[i]] &
        predictions$origin_date == keys$origin_date[[i]] &
        predictions$target_date == keys$target_date[[i]] &
        predictions$horizon == keys$horizon[[i]]
      block <- predictions[idx, , drop = FALSE]
      lo <- block$qhat_monotone[match(lo_p, block$quantile_level)]
      hi <- block$qhat_monotone[match(hi_p, block$quantile_level)]
      y <- block$y_reference[[which(is.finite(block$y_reference))[1L]]]
      if (!is.finite(lo) || !is.finite(hi) || !is.finite(y)) next
      rows[[k]] <- cbind(
        keys[i, , drop = FALSE],
        data.frame(
          lower = lo_p,
          upper = hi_p,
          nominal = nominal,
          covered = y >= lo && y <= hi,
          interval_score = app_interval_score(y, lo, hi, alpha),
          stringsAsFactors = FALSE
        )
      )
      k <- k + 1L
    }
  }
  if (!length(rows)) data.frame() else do.call(rbind, rows)
}

app_crps_quantile_grid <- function(block) {
  block <- block[order(block$quantile_level), , drop = FALSE]
  p <- block$quantile_level
  y <- block$y_reference[[which(is.finite(block$y_reference))[1L]]]
  q <- block$qhat_monotone
  if (length(p) < 2L || !is.finite(y)) return(NA_real_)
  loss <- app_check_loss(y, q, p)
  2 * sum(diff(p) * (head(loss, -1L) + tail(loss, -1L)) / 2)
}

app_score_crps_grid <- function(predictions) {
  key_cols <- c("model_id", "origin_date", "target_date", "horizon")
  keys <- unique(predictions[, key_cols, drop = FALSE])
  out <- vector("list", nrow(keys))
  for (i in seq_len(nrow(keys))) {
    idx <- predictions$model_id == keys$model_id[[i]] &
      predictions$origin_date == keys$origin_date[[i]] &
      predictions$target_date == keys$target_date[[i]] &
      predictions$horizon == keys$horizon[[i]]
    out[[i]] <- cbind(
      keys[i, , drop = FALSE],
      data.frame(crps_quantile_grid = app_crps_quantile_grid(predictions[idx, , drop = FALSE]))
    )
  }
  do.call(rbind, out)
}

app_score_summary <- function(scored_predictions, interval_scores, crps_scores) {
  models <- sort(unique(scored_predictions$model_id))
  rows <- vector("list", length(models))
  for (i in seq_along(models)) {
    model <- models[[i]]
    q_block <- scored_predictions[scored_predictions$model_id == model, , drop = FALSE]
    i_block <- interval_scores[interval_scores$model_id == model, , drop = FALSE]
    c_block <- crps_scores[crps_scores$model_id == model, , drop = FALSE]
    rows[[i]] <- data.frame(
      model_id = model,
      n_quantile_scores = sum(is.finite(q_block$check_loss)),
      check_loss_mean = mean(q_block$check_loss, na.rm = TRUE),
      check_loss_independent_mean = if ("check_loss_independent" %in% names(q_block)) {
        mean(q_block$check_loss_independent, na.rm = TRUE)
      } else {
        NA_real_
      },
      check_loss_monotone_mean = if ("check_loss_monotone" %in% names(q_block)) {
        mean(q_block$check_loss_monotone, na.rm = TRUE)
      } else {
        NA_real_
      },
      interval_score_mean = if (nrow(i_block)) mean(i_block$interval_score, na.rm = TRUE) else NA_real_,
      interval_coverage_mean = if (nrow(i_block)) mean(i_block$covered, na.rm = TRUE) else NA_real_,
      crps_quantile_grid_mean = if (nrow(c_block)) mean(c_block$crps_quantile_grid, na.rm = TRUE) else NA_real_,
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}
