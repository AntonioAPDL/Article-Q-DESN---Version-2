# Monotone synthesis of fitted quantile grids.

app_isotonic_quantiles <- function(p, q) {
  ord <- order(p)
  p <- as.numeric(p[ord])
  q <- as.numeric(q[ord])
  ok <- is.finite(p) & is.finite(q)
  if (sum(ok) < 2L) return(q[order(ord)])
  iso <- stats::isoreg(p[ok], q[ok])
  q_out <- q
  q_out[ok] <- as.numeric(iso$yf)
  q_out[order(ord)]
}

app_synthesize_quantile_grid <- function(predictions) {
  required <- c("model_id", "origin_date", "target_date", "horizon", "quantile_level", "qhat")
  app_check_required_columns(predictions, required, "prediction table")
  groups <- unique(predictions[, c("model_id", "origin_date", "target_date", "horizon"), drop = FALSE])
  out <- vector("list", nrow(groups))
  for (i in seq_len(nrow(groups))) {
    idx <- predictions$model_id == groups$model_id[[i]] &
      predictions$origin_date == groups$origin_date[[i]] &
      predictions$target_date == groups$target_date[[i]] &
      predictions$horizon == groups$horizon[[i]]
    block <- predictions[idx, , drop = FALSE]
    block <- block[order(block$quantile_level), , drop = FALSE]
    block$qhat_monotone <- app_isotonic_quantiles(block$quantile_level, block$qhat)
    out[[i]] <- block
  }
  do.call(rbind, out)
}

app_quantile_crossing_diagnostics <- function(predictions, value_col, label) {
  key_cols <- c("model_id", "origin_date", "target_date", "horizon")
  required <- c(key_cols, "quantile_level", value_col)
  app_check_required_columns(predictions, required, "prediction table")
  keys <- unique(predictions[, key_cols, drop = FALSE])
  rows <- vector("list", nrow(keys))
  for (i in seq_len(nrow(keys))) {
    idx <- predictions$model_id == keys$model_id[[i]] &
      predictions$origin_date == keys$origin_date[[i]] &
      predictions$target_date == keys$target_date[[i]] &
      predictions$horizon == keys$horizon[[i]]
    block <- predictions[idx, , drop = FALSE]
    block <- block[order(block$quantile_level), , drop = FALSE]
    diffs <- diff(as.numeric(block[[value_col]]))
    violations <- diffs < -1.0e-10
    rows[[i]] <- cbind(
      keys[i, , drop = FALSE],
      data.frame(
        diagnostic = label,
        n_quantiles = nrow(block),
        n_adjacent_pairs = length(diffs),
        n_crossing_pairs = sum(violations, na.rm = TRUE),
        max_crossing_magnitude = if (any(violations, na.rm = TRUE)) max(-diffs[violations], na.rm = TRUE) else 0,
        stringsAsFactors = FALSE
      )
    )
  }
  do.call(rbind, rows)
}

app_quantile_crossing_summary <- function(crossing_diagnostics) {
  if (!nrow(crossing_diagnostics)) return(data.frame())
  cross_count <- aggregate(
    n_crossing_pairs ~ model_id + diagnostic,
    crossing_diagnostics,
    sum,
    na.rm = TRUE
  )
  cross_mag <- aggregate(
    max_crossing_magnitude ~ model_id + diagnostic,
    crossing_diagnostics,
    max,
    na.rm = TRUE
  )
  merge(cross_count, cross_mag, by = c("model_id", "diagnostic"), all = TRUE)
}
