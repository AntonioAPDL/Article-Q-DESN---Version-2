# Distributional selection utilities for the GloFAS fit-recovery workflow.

app_glofas_selection_quantile_id <- function(p) {
  p <- as.numeric(p)
  if (length(p) != 1L || !is.finite(p) || p <= 0 || p >= 1) {
    stop("Quantile levels must be finite scalars in (0, 1).", call. = FALSE)
  }
  paste0("p", sprintf("%02d", as.integer(round(100 * p))))
}

app_glofas_selection_validate_shortlist <- function(x) {
  required <- c(
    "candidate_id", "role", "source_priority", "advance_to_triage",
    "retain_heavy", "description"
  )
  if (!is.data.frame(x) || !nrow(x)) stop("The distributional shortlist is empty.", call. = FALSE)
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(sprintf("The distributional shortlist is missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  if (any(!nzchar(as.character(x$candidate_id))) || anyDuplicated(x$candidate_id)) {
    stop("Shortlisted candidate IDs must be nonempty and unique.", call. = FALSE)
  }
  x$advance_to_triage <- app_as_bool_vec(x$advance_to_triage)
  x$retain_heavy <- app_as_bool_vec(x$retain_heavy)
  x$source_priority <- suppressWarnings(as.integer(x$source_priority))
  if (any(!is.finite(x$source_priority)) || anyDuplicated(x$source_priority)) {
    stop("Shortlist priorities must be finite and unique.", call. = FALSE)
  }
  x <- x[x$advance_to_triage, , drop = FALSE]
  x[order(x$source_priority), , drop = FALSE]
}

app_glofas_selection_validate_source_manifest <- function(x, require_complete = FALSE) {
  required <- c(
    "candidate_id", "quantile_id", "quantile_level", "source_kind",
    "run_id", "run_dir", "history_path", "fit_object", "fit_object_sha256"
  )
  if (!is.data.frame(x) || !nrow(x)) stop("The quantile source manifest is empty.", call. = FALSE)
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(sprintf("The quantile source manifest is missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  x$quantile_level <- suppressWarnings(as.numeric(x$quantile_level))
  if (any(!is.finite(x$quantile_level) | x$quantile_level <= 0 | x$quantile_level >= 1)) {
    stop("Source-manifest quantile levels must lie in (0, 1).", call. = FALSE)
  }
  expected_id <- vapply(x$quantile_level, app_glofas_selection_quantile_id, character(1L))
  if (any(as.character(x$quantile_id) != expected_id)) {
    stop("Source-manifest quantile IDs do not match their numeric levels.", call. = FALSE)
  }
  key <- paste(x$candidate_id, x$quantile_id, sep = "::")
  if (anyDuplicated(key)) stop("Candidate-quantile source pairs must be unique.", call. = FALSE)
  if (isTRUE(require_complete)) {
    missing_history <- !file.exists(as.character(x$history_path))
    missing_fit <- !file.exists(as.character(x$fit_object))
    missing_marker <- !file.exists(file.path(as.character(x$run_dir), ".fit_recovery_complete"))
    if (any(missing_history | missing_fit | missing_marker)) {
      bad <- key[missing_history | missing_fit | missing_marker]
      stop(sprintf("Incomplete quantile sources: %s.", paste(bad, collapse = ", ")), call. = FALSE)
    }
    observed_hash <- vapply(as.character(x$fit_object), app_sha256_file, character(1L))
    if (any(observed_hash != as.character(x$fit_object_sha256))) {
      bad <- key[observed_hash != as.character(x$fit_object_sha256)]
      stop(sprintf("Fit-object hashes changed for: %s.", paste(bad, collapse = ", ")), call. = FALSE)
    }
  }
  x
}

app_glofas_selection_history <- function(path, candidate_id, quantile_level, cutoff_date) {
  raw <- app_read_csv(path)
  if (!"quantile_level" %in% names(raw)) {
    stop(sprintf("Observed history lacks quantile_level: %s.", path), call. = FALSE)
  }
  observed_levels <- unique(as.numeric(raw$quantile_level[is.finite(as.numeric(raw$quantile_level))]))
  if (length(observed_levels) != 1L || !isTRUE(all.equal(observed_levels[[1L]], as.numeric(quantile_level), tolerance = 1e-12))) {
    stop(sprintf("Observed history quantile does not match the manifest for %s.", candidate_id), call. = FALSE)
  }
  history <- app_glofas_fit_recovery_history(
    raw,
    candidate_id = candidate_id,
    cutoff_date = cutoff_date
  )
  history$quantile_id <- app_glofas_selection_quantile_id(quantile_level)
  history$quantile_level <- as.numeric(quantile_level)
  history$history_path <- normalizePath(path, mustWork = TRUE)
  history
}

app_glofas_selection_combine_histories <- function(source_manifest, cutoff_date) {
  manifest <- app_glofas_selection_validate_source_manifest(source_manifest, require_complete = TRUE)
  candidates <- unique(as.character(manifest$candidate_id))
  rows <- list()
  date_audit <- list()
  for (candidate_id in candidates) {
    block <- manifest[manifest$candidate_id == candidate_id, , drop = FALSE]
    block <- block[order(block$quantile_level), , drop = FALSE]
    histories <- lapply(seq_len(nrow(block)), function(i) {
      app_glofas_selection_history(
        block$history_path[[i]],
        candidate_id = candidate_id,
        quantile_level = block$quantile_level[[i]],
        cutoff_date = cutoff_date
      )
    })
    common_dates <- Reduce(intersect, lapply(histories, function(x) as.character(x$target_date)))
    common_dates <- sort(as.Date(common_dates))
    if (!length(common_dates)) stop(sprintf("Candidate %s has no common quantile-history dates.", candidate_id), call. = FALSE)
    for (i in seq_along(histories)) {
      history <- histories[[i]]
      history <- history[history$target_date %in% common_dates, , drop = FALSE]
      history <- history[order(history$target_date), , drop = FALSE]
      rows[[length(rows) + 1L]] <- history
      date_audit[[length(date_audit) + 1L]] <- data.frame(
        candidate_id = candidate_id,
        quantile_id = history$quantile_id[[1L]],
        quantile_level = history$quantile_level[[1L]],
        n_source_dates = nrow(histories[[i]]),
        n_common_dates = nrow(history),
        date_min = as.character(min(history$target_date)),
        date_max = as.character(max(history$target_date)),
        stringsAsFactors = FALSE
      )
    }
    candidate_rows <- rows[vapply(rows, function(x) identical(x$candidate_id[[1L]], candidate_id), logical(1L))]
    y_matrix <- do.call(cbind, lapply(candidate_rows, function(x) x$y_log1p))
    if (max(abs(y_matrix - y_matrix[, 1L]), na.rm = TRUE) > 1e-10) {
      stop(sprintf("Reference observations differ across quantile fits for %s.", candidate_id), call. = FALSE)
    }
  }
  history <- app_bind_rows_fill(rows)
  history <- history[order(history$candidate_id, history$target_date, history$quantile_level), , drop = FALSE]
  rownames(history) <- NULL
  list(history = history, date_audit = app_bind_rows_fill(date_audit))
}

app_glofas_selection_apply_isotonic <- function(history, tolerance = 1e-10) {
  required <- c("candidate_id", "target_date", "quantile_level", "y_log1p", "qhat_log1p")
  missing <- setdiff(required, names(history))
  if (length(missing)) stop(sprintf("History lacks: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  key <- paste(history$candidate_id, history$target_date, sep = "::")
  groups <- split(seq_len(nrow(history)), key)
  out <- history
  out$qhat_independent <- as.numeric(out$qhat_log1p)
  out$qhat_isotonic <- NA_real_
  out$isotonic_abs_adjustment <- NA_real_
  diagnostics <- vector("list", length(groups))
  ii <- 0L
  for (idx in groups) {
    ii <- ii + 1L
    ord <- order(out$quantile_level[idx])
    idx <- idx[ord]
    p <- out$quantile_level[idx]
    q <- out$qhat_independent[idx]
    q_iso <- app_isotonic_quantiles(p, q)
    out$qhat_isotonic[idx] <- q_iso
    out$isotonic_abs_adjustment[idx] <- abs(q_iso - q)
    delta <- diff(q)
    diagnostics[[ii]] <- data.frame(
      candidate_id = out$candidate_id[idx[[1L]]],
      target_date = as.character(out$target_date[idx[[1L]]]),
      n_quantiles = length(idx),
      n_adjacent_crossings = sum(delta < -tolerance),
      max_crossing_magnitude = if (any(delta < -tolerance)) max(-delta[delta < -tolerance]) else 0,
      mean_abs_isotonic_adjustment = mean(abs(q_iso - q)),
      max_abs_isotonic_adjustment = max(abs(q_iso - q)),
      stringsAsFactors = FALSE
    )
  }
  list(history = out, crossing = app_bind_rows_fill(diagnostics))
}

app_glofas_selection_interval_score <- function(y, lower, upper, alpha = 0.10) {
  y <- as.numeric(y)
  lower <- as.numeric(lower)
  upper <- as.numeric(upper)
  width <- upper - lower
  width + (2 / alpha) * (lower - y) * as.numeric(y < lower) +
    (2 / alpha) * (y - upper) * as.numeric(y > upper)
}

app_glofas_selection_date_scores <- function(history, value_col) {
  key <- paste(history$candidate_id, history$target_date, sep = "::")
  groups <- split(seq_len(nrow(history)), key)
  rows <- vector("list", length(groups))
  ii <- 0L
  for (idx in groups) {
    ii <- ii + 1L
    block <- history[idx, , drop = FALSE]
    block <- block[order(block$quantile_level), , drop = FALSE]
    p <- as.numeric(block$quantile_level)
    q <- as.numeric(block[[value_col]])
    y <- block$y_log1p[[1L]]
    losses <- vapply(seq_along(p), function(j) {
      app_glofas_fit_recovery_check_loss(y, q[[j]], tau = p[[j]])
    }, numeric(1L))
    integrated <- if (length(p) >= 2L) {
      2 * sum(diff(p) * (head(losses, -1L) + tail(losses, -1L)) / 2)
    } else {
      NA_real_
    }
    lower_idx <- which.min(p)
    upper_idx <- which.max(p)
    median_idx <- which.min(abs(p - 0.5))
    interval_alpha <- p[[lower_idx]] + (1 - p[[upper_idx]])
    interval_valid <- interval_alpha > 0 && interval_alpha < 1 && lower_idx != upper_idx
    rows[[ii]] <- data.frame(
      candidate_id = block$candidate_id[[1L]],
      target_date = as.Date(block$target_date[[1L]]),
      y_log1p = y,
      n_quantiles = length(p),
      mean_pinball_loss = mean(losses),
      triage_integrated_quantile_score = integrated,
      lower_level = p[[lower_idx]],
      upper_level = p[[upper_idx]],
      interval_covered = if (interval_valid) as.numeric(y >= q[[lower_idx]] && y <= q[[upper_idx]]) else NA_real_,
      interval_width = if (interval_valid) q[[upper_idx]] - q[[lower_idx]] else NA_real_,
      interval_score = if (interval_valid) {
        app_glofas_selection_interval_score(y, q[[lower_idx]], q[[upper_idx]], alpha = interval_alpha)
      } else {
        NA_real_
      },
      median_abs_error = abs(q[[median_idx]] - y),
      median_squared_error = (q[[median_idx]] - y)^2,
      stringsAsFactors = FALSE
    )
  }
  app_bind_rows_fill(rows)
}

app_glofas_selection_score_windows <- function(
  history,
  crossing,
  windows = app_glofas_fit_recovery_windows()
) {
  candidates <- unique(as.character(history$candidate_id))
  modes <- c(independent = "qhat_independent", isotonic = "qhat_isotonic")
  summary_rows <- list()
  quantile_rows <- list()
  date_rows <- list()
  for (candidate_id in candidates) {
    candidate_history <- history[history$candidate_id == candidate_id, , drop = FALSE]
    dates <- sort(unique(as.Date(candidate_history$target_date)))
    for (window in windows) {
      selected_dates <- if (is.finite(window)) tail(dates, min(as.integer(window), length(dates))) else dates
      window_label <- app_glofas_fit_recovery_window_label(window)
      block <- candidate_history[candidate_history$target_date %in% selected_dates, , drop = FALSE]
      crossing_block <- crossing[crossing$candidate_id == candidate_id & as.Date(crossing$target_date) %in% selected_dates, , drop = FALSE]
      for (mode in names(modes)) {
        value_col <- modes[[mode]]
        per_date <- app_glofas_selection_date_scores(block, value_col = value_col)
        per_date$window <- window_label
        per_date$estimate_mode <- mode
        date_rows[[length(date_rows) + 1L]] <- per_date
        summary_rows[[length(summary_rows) + 1L]] <- data.frame(
          candidate_id = candidate_id,
          window = window_label,
          estimate_mode = mode,
          date_min = as.character(min(selected_dates)),
          date_max = as.character(max(selected_dates)),
          n_dates = length(selected_dates),
          n_quantiles = length(unique(block$quantile_level)),
          mean_pinball_loss = mean(per_date$mean_pinball_loss, na.rm = TRUE),
          triage_integrated_quantile_score = mean(per_date$triage_integrated_quantile_score, na.rm = TRUE),
          interval_coverage = mean(per_date$interval_covered, na.rm = TRUE),
          interval_width = mean(per_date$interval_width, na.rm = TRUE),
          interval_score = mean(per_date$interval_score, na.rm = TRUE),
          median_log1p_mae = mean(per_date$median_abs_error, na.rm = TRUE),
          median_log1p_rmse = sqrt(mean(per_date$median_squared_error, na.rm = TRUE)),
          crossing_date_fraction = mean(crossing_block$n_adjacent_crossings > 0, na.rm = TRUE),
          crossing_pair_count = sum(crossing_block$n_adjacent_crossings, na.rm = TRUE),
          max_crossing_magnitude = max(crossing_block$max_crossing_magnitude, na.rm = TRUE),
          mean_abs_isotonic_adjustment = mean(crossing_block$mean_abs_isotonic_adjustment, na.rm = TRUE),
          max_abs_isotonic_adjustment = max(crossing_block$max_abs_isotonic_adjustment, na.rm = TRUE),
          stringsAsFactors = FALSE
        )
        for (p in sort(unique(block$quantile_level))) {
          qb <- block[abs(block$quantile_level - p) < 1e-12, , drop = FALSE]
          quantile_rows[[length(quantile_rows) + 1L]] <- data.frame(
            candidate_id = candidate_id,
            window = window_label,
            estimate_mode = mode,
            quantile_id = app_glofas_selection_quantile_id(p),
            quantile_level = p,
            n = nrow(qb),
            check_loss_mean = app_glofas_fit_recovery_check_loss(qb$y_log1p, qb[[value_col]], tau = p),
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  list(
    summary = app_bind_rows_fill(summary_rows),
    by_quantile = app_bind_rows_fill(quantile_rows),
    by_date = app_bind_rows_fill(date_rows)
  )
}

app_glofas_selection_fit_gate <- function(source_manifest) {
  manifest <- app_glofas_selection_validate_source_manifest(source_manifest, require_complete = TRUE)
  rows <- lapply(seq_len(nrow(manifest)), function(i) {
    row <- manifest[i, , drop = FALSE]
    diagnostics_path <- file.path(row$run_dir[[1L]], "tables", "qdesn_discrepancy_fit_diagnostics.csv")
    fit_status_path <- file.path(row$run_dir[[1L]], "tables", "fit_status.csv")
    diagnostics <- app_read_csv(diagnostics_path)
    fit_status <- app_read_csv(fit_status_path)
    qdiag <- diagnostics[abs(as.numeric(diagnostics$quantile_level) - row$quantile_level[[1L]]) < 1e-12, , drop = FALSE]
    qstatus <- fit_status[
      fit_status$model_family == "qdesn_glofas_discrepancy" &
        abs(as.numeric(fit_status$quantile_level) - row$quantile_level[[1L]]) < 1e-12,
      , drop = FALSE
    ]
    finite_ok <- nrow(qdiag) == 1L && isTRUE(app_as_bool_vec(qdiag$finite_theta)[[1L]]) &&
      isTRUE(app_as_bool_vec(qdiag$finite_sigma)[[1L]])
    converged_ok <- nrow(qdiag) == 1L && isTRUE(app_as_bool_vec(qdiag$vb_converged)[[1L]])
    status_ok <- nrow(qstatus) == 1L && identical(as.character(qstatus$status[[1L]]), "completed")
    warm_required <- grepl("^new_", as.character(row$source_kind[[1L]]))
    warm_theta_ok <- if (warm_required) {
      nrow(qdiag) == 1L && isTRUE(app_as_bool_vec(qdiag$vb_warm_start_used)[[1L]]) &&
        isTRUE(app_as_bool_vec(qdiag$vb_warm_start_theta_used)[[1L]]) &&
        !isTRUE(app_as_bool_vec(qdiag$vb_warm_start_future_used)[[1L]]) &&
        !isTRUE(app_as_bool_vec(qdiag$vb_warm_start_sigma_used)[[1L]])
    } else {
      TRUE
    }
    data.frame(
      candidate_id = row$candidate_id[[1L]],
      quantile_id = row$quantile_id[[1L]],
      quantile_level = row$quantile_level[[1L]],
      source_kind = row$source_kind[[1L]],
      status_ok = status_ok,
      finite_ok = finite_ok,
      converged_ok = converged_ok,
      warm_start_contract_ok = warm_theta_ok,
      gate_pass = status_ok && finite_ok && converged_ok && warm_theta_ok,
      vb_iterations = if (nrow(qdiag)) qdiag$vb_iterations[[1L]] else NA_real_,
      vb_elbo_final = if (nrow(qdiag)) qdiag$vb_elbo_final[[1L]] else NA_real_,
      fit_object_sha256 = row$fit_object_sha256[[1L]],
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_glofas_selection_rank <- function(score_summary, gate, shortlist) {
  all_iso <- score_summary[
    score_summary$window == "all" & score_summary$estimate_mode == "isotonic",
    , drop = FALSE
  ]
  candidate_gate <- aggregate(gate_pass ~ candidate_id, gate, all)
  names(candidate_gate)[[2L]] <- "all_fit_gates_pass"
  out <- merge(all_iso, candidate_gate, by = "candidate_id", all.x = TRUE)
  out <- merge(
    out,
    shortlist[, c("candidate_id", "role", "source_priority", "description"), drop = FALSE],
    by = "candidate_id",
    all.x = TRUE
  )
  out <- out[order(
    !app_as_bool_vec(out$all_fit_gates_pass),
    out$triage_integrated_quantile_score,
    out$interval_score,
    out$mean_pinball_loss,
    out$source_priority
  ), , drop = FALSE]
  out$triage_rank <- seq_len(nrow(out))
  out$advance_eligible <- app_as_bool_vec(out$all_fit_gates_pass) & is.finite(out$triage_integrated_quantile_score)
  rownames(out) <- NULL
  out
}
