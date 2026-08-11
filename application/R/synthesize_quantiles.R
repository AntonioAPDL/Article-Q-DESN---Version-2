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

app_apply_synthesis_model_identity <- function(predictions, source_row) {
  if (!nrow(predictions)) return(predictions)
  app_check_required_columns(predictions, "model_id", "prediction table")
  if (nrow(source_row) != 1L) {
    stop("Synthesis model identity requires exactly one source-manifest row.", call. = FALSE)
  }

  mappings <- list(
    c("raw_fit_id", "raw_synthesis_model_id"),
    c("qdesn_fit_id", "qdesn_synthesis_model_id")
  )
  predictions$source_model_id <- as.character(predictions$model_id)
  for (mapping in mappings) {
    source_col <- mapping[[1L]]
    target_col <- mapping[[2L]]
    if (!all(c(source_col, target_col) %in% names(source_row))) next
    source_id <- trimws(as.character(source_row[[source_col]][[1L]]))
    target_id <- trimws(as.character(source_row[[target_col]][[1L]]))
    if (!nzchar(source_id) || !nzchar(target_id) || is.na(source_id) || is.na(target_id)) next
    predictions$model_id[predictions$model_id == source_id] <- target_id
  }
  predictions
}

app_synthesis_model_grid_audit <- function(predictions, target_quantiles, tolerance = 1.0e-12) {
  required <- c("model_id", "origin_date", "target_date", "horizon", "quantile_level")
  app_check_required_columns(predictions, required, "prediction table")
  target_quantiles <- sort(unique(as.numeric(target_quantiles)))
  if (!length(target_quantiles) || any(!is.finite(target_quantiles))) {
    stop("Target quantiles must be finite and nonempty.", call. = FALSE)
  }

  rows <- lapply(split(predictions, predictions$model_id), function(model) {
    group_key <- interaction(
      as.Date(model$origin_date),
      as.Date(model$target_date),
      as.integer(model$horizon),
      drop = TRUE
    )
    group_levels <- lapply(split(as.numeric(model$quantile_level), group_key), function(x) {
      sort(unique(x[is.finite(x)]))
    })
    group_complete <- vapply(group_levels, function(x) {
      length(x) == length(target_quantiles) && all(abs(x - target_quantiles) <= tolerance)
    }, logical(1L))
    available <- sort(unique(as.numeric(model$quantile_level)))
    data.frame(
      model_id = as.character(model$model_id[[1L]]),
      n_prediction_groups = length(group_levels),
      n_target_quantiles = length(target_quantiles),
      min_quantiles_per_group = min(lengths(group_levels)),
      max_quantiles_per_group = max(lengths(group_levels)),
      available_quantiles = paste(format(available, trim = TRUE), collapse = ";"),
      complete_quantile_grid = length(group_complete) > 0L && all(group_complete),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
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
