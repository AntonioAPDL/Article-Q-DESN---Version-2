# Scientific closeout utilities for GloFAS full-quantile fit recovery.

app_glofas_scientific_audit_defaults <- function() {
  list(
    expected_quantiles = c(0.05, 0.15, 0.35, 0.50, 0.65, 0.80, 0.95),
    upper_quantile = 0.95,
    component_identity_tolerance = 1e-8,
    max_attribution_alignment_error = 0.005,
    max_fitted_to_observed_max_ratio = 20,
    max_abs_discrepancy_to_history_q995_ratio = 1.5
  )
}

app_glofas_scientific_validate_manifest <- function(x) {
  required <- c(
    "candidate_id", "source_role", "history_format", "history_path",
    "history_sha256"
  )
  if (!is.data.frame(x) || !nrow(x)) {
    stop("The scientific-audit evidence manifest is empty.", call. = FALSE)
  }
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(sprintf("The evidence manifest is missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  if (any(!nzchar(as.character(x$candidate_id))) || anyDuplicated(x$candidate_id)) {
    stop("Scientific-audit candidate IDs must be nonempty and unique.", call. = FALSE)
  }
  supported <- c("selection_long", "pre_cutoff_quantile_history")
  if (any(!as.character(x$history_format) %in% supported)) {
    stop("The evidence manifest contains an unsupported history format.", call. = FALSE)
  }
  missing_file <- !file.exists(as.character(x$history_path))
  if (any(missing_file)) {
    stop(sprintf(
      "Scientific-audit history files are missing for: %s.",
      paste(x$candidate_id[missing_file], collapse = ", ")
    ), call. = FALSE)
  }
  observed_hash <- vapply(as.character(x$history_path), app_sha256_file, character(1L))
  if (any(observed_hash != as.character(x$history_sha256))) {
    stop(sprintf(
      "Scientific-audit history hashes changed for: %s.",
      paste(x$candidate_id[observed_hash != as.character(x$history_sha256)], collapse = ", ")
    ), call. = FALSE)
  }
  x
}

app_glofas_scientific_read_history <- function(manifest_row, cutoff_date) {
  path <- as.character(manifest_row$history_path[[1L]])
  candidate_id <- as.character(manifest_row$candidate_id[[1L]])
  format <- as.character(manifest_row$history_format[[1L]])
  raw <- app_read_csv(path)
  if (format == "selection_long") {
    required <- c("target_date", "quantile_level", "y_log1p", "qhat_independent")
    missing <- setdiff(required, names(raw))
    if (length(missing)) {
      stop(sprintf("Selection history for %s lacks: %s.", candidate_id, paste(missing, collapse = ", ")), call. = FALSE)
    }
    qhat <- as.numeric(raw$qhat_independent)
    y <- as.numeric(raw$y_log1p)
    raw_log <- if ("raw_log1p" %in% names(raw)) as.numeric(raw$raw_log1p) else NA_real_
  } else {
    required <- c("target_date", "quantile_level", "y_reference", "qhat")
    missing <- setdiff(required, names(raw))
    if (length(missing)) {
      stop(sprintf("Pre-cutoff history for %s lacks: %s.", candidate_id, paste(missing, collapse = ", ")), call. = FALSE)
    }
    qhat <- as.numeric(raw$qhat)
    y <- as.numeric(raw$y_reference)
    raw_log <- rep(NA_real_, nrow(raw))
  }
  target_date <- as.Date(raw$target_date)
  quantile_level <- as.numeric(raw$quantile_level)
  cutoff_date <- as.Date(cutoff_date)
  keep <- !is.na(target_date) & target_date <= cutoff_date &
    is.finite(quantile_level) & is.finite(y) & is.finite(qhat)
  out <- data.frame(
    candidate_id = candidate_id,
    source_role = as.character(manifest_row$source_role[[1L]]),
    target_date = target_date[keep],
    cutoff_date = cutoff_date,
    y_log1p = y[keep],
    qhat_log1p = qhat[keep],
    raw_log1p = raw_log[keep],
    quantile_level = quantile_level[keep],
    history_path = normalizePath(path, mustWork = TRUE),
    stringsAsFactors = FALSE
  )
  out$quantile_id <- vapply(out$quantile_level, app_glofas_selection_quantile_id, character(1L))
  out$y_original <- app_glofas_fit_recovery_safe_expm1(out$y_log1p)
  out$qhat_original <- app_glofas_fit_recovery_safe_expm1(out$qhat_log1p)
  out$raw_original <- app_glofas_fit_recovery_safe_expm1(out$raw_log1p)
  key <- paste(out$target_date, out$quantile_id, sep = "::")
  if (!nrow(out) || anyDuplicated(key)) {
    stop(sprintf("Scientific history for %s is empty or has duplicate date-quantile rows.", candidate_id), call. = FALSE)
  }
  out[order(out$target_date, out$quantile_level), , drop = FALSE]
}

app_glofas_scientific_common_history <- function(
  manifest,
  cutoff_date,
  expected_quantiles = app_glofas_scientific_audit_defaults()$expected_quantiles,
  tolerance = 1e-10
) {
  manifest <- app_glofas_scientific_validate_manifest(manifest)
  histories <- lapply(seq_len(nrow(manifest)), function(i) {
    app_glofas_scientific_read_history(manifest[i, , drop = FALSE], cutoff_date)
  })
  names(histories) <- manifest$candidate_id
  audit <- lapply(histories, function(x) {
    data.frame(
      candidate_id = x$candidate_id[[1L]],
      source_role = x$source_role[[1L]],
      n_source_dates = length(unique(x$target_date)),
      source_date_min = as.character(min(x$target_date)),
      source_date_max = as.character(max(x$target_date)),
      n_quantiles = length(unique(x$quantile_level)),
      stringsAsFactors = FALSE
    )
  })
  for (candidate_id in names(histories)) {
    observed <- sort(unique(histories[[candidate_id]]$quantile_level))
    if (!isTRUE(all.equal(observed, expected_quantiles, tolerance = tolerance))) {
      stop(sprintf("Candidate %s does not have the exact expected quantile grid.", candidate_id), call. = FALSE)
    }
  }
  common_dates <- Reduce(intersect, lapply(histories, function(x) as.character(unique(x$target_date))))
  common_dates <- sort(as.Date(common_dates))
  if (!length(common_dates)) stop("Scientific-audit candidates have no common dates.", call. = FALSE)
  histories <- lapply(histories, function(x) {
    x <- x[x$target_date %in% common_dates, , drop = FALSE]
    x[order(x$target_date, x$quantile_level), , drop = FALSE]
  })
  combined <- app_bind_rows_fill(histories)
  observed_range <- tapply(combined$y_log1p, combined$target_date, function(z) diff(range(z)))
  if (any(!is.finite(observed_range)) || max(observed_range) > tolerance) {
    stop("Reference observations differ across scientific-audit candidates.", call. = FALSE)
  }
  audit <- app_bind_rows_fill(audit)
  audit$n_common_dates <- length(common_dates)
  audit$common_date_min <- as.character(min(common_dates))
  audit$common_date_max <- as.character(max(common_dates))
  list(
    history = combined[order(combined$candidate_id, combined$target_date, combined$quantile_level), , drop = FALSE],
    date_audit = audit,
    common_dates = common_dates
  )
}

app_glofas_scientific_apply_isotonic <- function(history, tolerance = 1e-10) {
  required <- c("candidate_id", "target_date", "quantile_level", "qhat_log1p")
  missing <- setdiff(required, names(history))
  if (length(missing)) stop(sprintf("Scientific isotonic history lacks: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  candidates <- unique(as.character(history$candidate_id))
  history_rows <- list()
  diagnostic_rows <- list()
  for (candidate_id in candidates) {
    block <- history[history$candidate_id == candidate_id, , drop = FALSE]
    block <- block[order(block$target_date, block$quantile_level), , drop = FALSE]
    dates <- sort(unique(as.Date(block$target_date)))
    p <- sort(unique(as.numeric(block$quantile_level)))
    n_dates <- length(dates)
    n_quantiles <- length(p)
    if (nrow(block) != n_dates * n_quantiles || any(table(block$target_date) != n_quantiles)) {
      stop(sprintf("Candidate %s does not have a rectangular isotonic grid.", candidate_id), call. = FALSE)
    }
    q <- matrix(as.numeric(block$qhat_log1p), nrow = n_dates, ncol = n_quantiles, byrow = TRUE)
    delta <- q[, -1L, drop = FALSE] - q[, -n_quantiles, drop = FALSE]
    crossed <- rowSums(delta < -tolerance) > 0L
    q_isotonic <- q
    for (i in which(crossed)) q_isotonic[i, ] <- app_isotonic_quantiles(p, q[i, ])
    adjustment <- abs(q_isotonic - q)
    block$qhat_independent <- as.vector(t(q))
    block$qhat_isotonic <- as.vector(t(q_isotonic))
    block$isotonic_abs_adjustment <- as.vector(t(adjustment))
    history_rows[[length(history_rows) + 1L]] <- block
    negative_delta <- pmax(-delta, 0)
    diagnostic_rows[[length(diagnostic_rows) + 1L]] <- data.frame(
      candidate_id = candidate_id,
      target_date = dates,
      n_quantiles = n_quantiles,
      n_adjacent_crossings = rowSums(delta < -tolerance),
      max_crossing_magnitude = apply(negative_delta, 1L, max),
      mean_abs_isotonic_adjustment = rowMeans(adjustment),
      max_abs_isotonic_adjustment = apply(adjustment, 1L, max),
      stringsAsFactors = FALSE
    )
  }
  list(
    history = app_bind_rows_fill(history_rows),
    crossing = app_bind_rows_fill(diagnostic_rows)
  )
}

app_glofas_scientific_score_windows <- function(
  history,
  crossing,
  windows = app_glofas_fit_recovery_windows()
) {
  candidates <- unique(as.character(history$candidate_id))
  modes <- c(independent = "qhat_independent", isotonic = "qhat_isotonic")
  date_rows <- list()
  summary_rows <- list()
  quantile_rows <- list()
  for (candidate_id in candidates) {
    candidate <- history[history$candidate_id == candidate_id, , drop = FALSE]
    candidate <- candidate[order(candidate$target_date, candidate$quantile_level), , drop = FALSE]
    dates <- sort(unique(as.Date(candidate$target_date)))
    p <- sort(unique(as.numeric(candidate$quantile_level)))
    n_dates <- length(dates)
    n_quantiles <- length(p)
    counts <- table(candidate$target_date)
    if (length(counts) != n_dates || any(counts != n_quantiles) ||
        nrow(candidate) != n_dates * n_quantiles) {
      stop(sprintf("Candidate %s does not have a rectangular date-quantile grid.", candidate_id), call. = FALSE)
    }
    y_log1p <- candidate$y_log1p[seq.int(1L, nrow(candidate), by = n_quantiles)]
    crossing_candidate <- crossing[crossing$candidate_id == candidate_id, , drop = FALSE]
    crossing_candidate$target_date <- as.Date(crossing_candidate$target_date)
    crossing_candidate <- crossing_candidate[match(dates, crossing_candidate$target_date), , drop = FALSE]
    if (any(is.na(crossing_candidate$target_date))) {
      stop(sprintf("Candidate %s lacks crossing diagnostics on the scoring grid.", candidate_id), call. = FALSE)
    }
    for (scale in c("log1p", "original")) {
      y <- if (scale == "log1p") y_log1p else app_glofas_fit_recovery_safe_expm1(y_log1p)
      for (mode in names(modes)) {
        q <- matrix(as.numeric(candidate[[modes[[mode]]]]), nrow = n_dates, ncol = n_quantiles, byrow = TRUE)
        if (scale == "original") q <- matrix(app_glofas_fit_recovery_safe_expm1(q), nrow = n_dates)
        u <- sweep(q, 1L, y, function(q_value, y_value) y_value - q_value)
        losses <- sweep(u, 2L, p, function(error, tau) error * (tau - as.numeric(error < 0)))
        integrated <- if (n_quantiles >= 2L) {
          2 * rowSums(sweep(
            losses[, -n_quantiles, drop = FALSE] + losses[, -1L, drop = FALSE],
            2L, diff(p) / 2, "*"
          ))
        } else rep(NA_real_, n_dates)
        lower_idx <- which.min(p)
        upper_idx <- which.max(p)
        median_idx <- which.min(abs(p - 0.5))
        interval_alpha <- p[[lower_idx]] + (1 - p[[upper_idx]])
        interval_valid <- interval_alpha > 0 && interval_alpha < 1 && lower_idx != upper_idx
        per_date <- data.frame(
          candidate_id = candidate_id,
          target_date = dates,
          estimate_mode = mode,
          score_scale = scale,
          observed_value = y,
          n_quantiles = n_quantiles,
          mean_pinball_loss = rowMeans(losses),
          integrated_quantile_score = integrated,
          lower_level = p[[lower_idx]],
          upper_level = p[[upper_idx]],
          interval_covered = if (interval_valid) as.numeric(y >= q[, lower_idx] & y <= q[, upper_idx]) else NA_real_,
          interval_width = if (interval_valid) q[, upper_idx] - q[, lower_idx] else NA_real_,
          interval_score = if (interval_valid) {
            app_glofas_selection_interval_score(y, q[, lower_idx], q[, upper_idx], alpha = interval_alpha)
          } else NA_real_,
          median_abs_error = abs(q[, median_idx] - y),
          median_squared_error = (q[, median_idx] - y)^2,
          stringsAsFactors = FALSE
        )
        date_rows[[length(date_rows) + 1L]] <- per_date
        for (window in windows) {
          selected <- if (is.finite(window)) tail(seq_len(n_dates), min(as.integer(window), n_dates)) else seq_len(n_dates)
          window_label <- app_glofas_fit_recovery_window_label(window)
          score_window <- per_date[selected, , drop = FALSE]
          crossing_window <- crossing_candidate[selected, , drop = FALSE]
          summary_rows[[length(summary_rows) + 1L]] <- data.frame(
            candidate_id = candidate_id,
            window = window_label,
            estimate_mode = mode,
            score_scale = scale,
            date_min = as.character(min(dates[selected])),
            date_max = as.character(max(dates[selected])),
            n_dates = length(selected),
            n_quantiles = n_quantiles,
            mean_pinball_loss = mean(score_window$mean_pinball_loss),
            integrated_quantile_score_mean = mean(score_window$integrated_quantile_score),
            interval_coverage = mean(score_window$interval_covered),
            interval_width = mean(score_window$interval_width),
            interval_score = mean(score_window$interval_score),
            median_mae = mean(score_window$median_abs_error),
            median_rmse = sqrt(mean(score_window$median_squared_error)),
            crossing_date_fraction = mean(crossing_window$n_adjacent_crossings > 0),
            crossing_pair_count = sum(crossing_window$n_adjacent_crossings),
            max_crossing_magnitude = max(crossing_window$max_crossing_magnitude),
            mean_abs_isotonic_adjustment = mean(crossing_window$mean_abs_isotonic_adjustment),
            max_abs_isotonic_adjustment = max(crossing_window$max_abs_isotonic_adjustment),
            stringsAsFactors = FALSE
          )
          for (j in seq_along(p)) {
            quantile_rows[[length(quantile_rows) + 1L]] <- data.frame(
              candidate_id = candidate_id,
              window = window_label,
              estimate_mode = mode,
              score_scale = scale,
              quantile_id = app_glofas_selection_quantile_id(p[[j]]),
              quantile_level = p[[j]],
              n = length(selected),
              check_loss_mean = mean(losses[selected, j]),
              stringsAsFactors = FALSE
            )
          }
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

app_glofas_scientific_score_distribution <- function(
  by_date,
  windows = app_glofas_fit_recovery_windows()
) {
  required <- c(
    "candidate_id", "target_date", "estimate_mode", "score_scale",
    "integrated_quantile_score"
  )
  missing <- setdiff(required, names(by_date))
  if (length(missing)) stop(sprintf("Per-date scores lack: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  key <- interaction(
    by_date$candidate_id, by_date$estimate_mode, by_date$score_scale,
    drop = TRUE, lex.order = TRUE
  )
  rows <- unlist(lapply(split(by_date, key), function(x) {
    x <- x[order(x$target_date), , drop = FALSE]
    lapply(windows, function(window) {
      selected <- if (is.finite(window)) tail(seq_len(nrow(x)), min(as.integer(window), nrow(x))) else seq_len(nrow(x))
      score <- as.numeric(x$integrated_quantile_score[selected])
      data.frame(
        candidate_id = x$candidate_id[[1L]],
        window = app_glofas_fit_recovery_window_label(window),
        estimate_mode = x$estimate_mode[[1L]],
        score_scale = x$score_scale[[1L]],
        n_dates = length(score),
        score_mean = mean(score),
        score_median = stats::median(score),
        score_q90 = unname(stats::quantile(score, 0.90)),
        score_q95 = unname(stats::quantile(score, 0.95)),
        score_q99 = unname(stats::quantile(score, 0.99)),
        score_max = max(score),
        all_finite = all(is.finite(score)),
        stringsAsFactors = FALSE
      )
    })
  }), recursive = FALSE)
  app_bind_rows_fill(rows)
}

app_glofas_scientific_tail_audit <- function(
  history,
  upper_level = app_glofas_scientific_audit_defaults()$upper_quantile
) {
  required <- c(
    "candidate_id", "target_date", "quantile_level", "y_original",
    "qhat_independent", "qhat_isotonic"
  )
  missing <- setdiff(required, names(history))
  if (length(missing)) stop(sprintf("Scientific tail history lacks: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  upper <- history[abs(history$quantile_level - upper_level) < 1e-12, , drop = FALSE]
  if (!nrow(upper)) stop("The scientific tail audit found no upper-quantile rows.", call. = FALSE)
  rows <- list()
  details <- list()
  for (candidate_id in unique(upper$candidate_id)) {
    block <- upper[upper$candidate_id == candidate_id, , drop = FALSE]
    observed_max <- max(block$y_original)
    for (mode in c("independent", "isotonic")) {
      fitted <- app_glofas_fit_recovery_safe_expm1(block[[paste0("qhat_", mode)]])
      rows[[length(rows) + 1L]] <- data.frame(
        candidate_id = candidate_id,
        source_role = block$source_role[[1L]],
        estimate_mode = mode,
        quantile_level = upper_level,
        n_dates = nrow(block),
        observed_max = observed_max,
        fitted_q95 = unname(stats::quantile(fitted, 0.95)),
        fitted_q99 = unname(stats::quantile(fitted, 0.99)),
        fitted_max = max(fitted),
        fitted_max_to_observed_max_ratio = max(fitted) / observed_max,
        n_above_observed_max = sum(fitted > observed_max),
        n_above_2x_observed_max = sum(fitted > 2 * observed_max),
        n_above_5x_observed_max = sum(fitted > 5 * observed_max),
        n_above_20x_observed_max = sum(fitted > 20 * observed_max),
        stringsAsFactors = FALSE
      )
      detail <- data.frame(
        candidate_id = candidate_id,
        source_role = block$source_role,
        estimate_mode = mode,
        target_date = block$target_date,
        y_original = block$y_original,
        fitted_original = fitted,
        observed_max = observed_max,
        fitted_to_observed_max = fitted / observed_max,
        stringsAsFactors = FALSE
      )
      details[[length(details) + 1L]] <- detail[detail$fitted_original > observed_max, , drop = FALSE]
    }
  }
  detail <- app_bind_rows_fill(details)
  detail <- detail[order(-detail$fitted_original, detail$candidate_id, detail$estimate_mode), , drop = FALSE]
  list(summary = app_bind_rows_fill(rows), excursions = detail)
}

app_glofas_scientific_component_audit <- function(
  history,
  candidate_id,
  upper_level = app_glofas_scientific_audit_defaults()$upper_quantile
) {
  required <- c(
    "target_date", "quantile_level", "y_reference", "glofas_retrospective",
    "observed_discrepancy", "q_y_mean", "q_g_mean", "d_g_mean",
    "q_y_median", "q_g_median", "d_g_median"
  )
  missing <- setdiff(required, names(history))
  if (length(missing)) stop(sprintf("Component history lacks: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  x <- history[abs(as.numeric(history$quantile_level) - upper_level) < 1e-12, , drop = FALSE]
  if (!nrow(x)) stop("Component audit found no upper-quantile rows.", call. = FALSE)
  x$target_date <- as.Date(x$target_date)
  x$prediction_identity_error <- as.numeric(x$q_y_mean) -
    (as.numeric(x$q_g_mean) - as.numeric(x$d_g_mean))
  x$marginal_median_nonadditivity <- as.numeric(x$q_y_median) -
    (as.numeric(x$q_g_median) - as.numeric(x$d_g_median))
  x$observed_identity_error <- as.numeric(x$observed_discrepancy) -
    (as.numeric(x$glofas_retrospective) - as.numeric(x$y_reference))
  x$q_y_original <- app_glofas_fit_recovery_safe_expm1(x$q_y_median)
  x$y_original <- app_glofas_fit_recovery_safe_expm1(x$y_reference)
  observed_max <- max(x$y_original)
  discrepancy_q995 <- unname(stats::quantile(abs(x$observed_discrepancy), 0.995))
  x$q_y_to_observed_max <- x$q_y_original / observed_max
  x$abs_d_g_to_history_q995 <- abs(x$d_g_median) / discrepancy_q995
  x$candidate_id <- candidate_id
  summary <- data.frame(
    candidate_id = candidate_id,
    quantile_level = upper_level,
    n_dates = nrow(x),
    prediction_identity_max_abs_error = max(abs(x$prediction_identity_error)),
    marginal_median_nonadditivity_max_abs_error = max(abs(x$marginal_median_nonadditivity)),
    observed_identity_max_abs_error = max(abs(x$observed_identity_error)),
    observed_max = observed_max,
    fitted_max = max(x$q_y_original),
    fitted_max_to_observed_max = max(x$q_y_to_observed_max),
    observed_abs_discrepancy_q995 = discrepancy_q995,
    fitted_abs_discrepancy_max = max(abs(x$d_g_median)),
    fitted_abs_discrepancy_to_history_q995_ratio = max(x$abs_d_g_to_history_q995),
    n_fitted_discrepancies_beyond_1_5x_q995 = sum(x$abs_d_g_to_history_q995 > 1.5),
    stringsAsFactors = FALSE
  )
  detail_columns <- c(
    "candidate_id", "target_date", "y_reference", "glofas_retrospective",
    "observed_discrepancy", "q_y_mean", "q_g_mean", "d_g_mean",
    "q_y_median", "q_g_median", "d_g_median",
    "q_y_original", "y_original", "q_y_to_observed_max",
    "abs_d_g_to_history_q995", "prediction_identity_error",
    "marginal_median_nonadditivity", "observed_identity_error"
  )
  detail <- x[order(-x$q_y_original), detail_columns, drop = FALSE]
  rownames(detail) <- NULL
  list(summary = summary, detail = detail)
}

app_glofas_scientific_contribution_audit <- function(
  fit,
  design,
  component_history,
  candidate_id,
  top_n = 20L
) {
  if (is.null(fit$variational_state$theta_mean) || is.null(design$X_beta) ||
      is.null(design$X_alpha) || is.null(design$beta_index) ||
      is.null(design$alpha_index) || is.null(design$feature_info_beta) ||
      is.null(design$feature_info_alpha)) {
    stop("The p95 fit/design lacks the two-block contribution contract.", call. = FALSE)
  }
  theta <- as.numeric(fit$variational_state$theta_mean)
  beta <- theta[as.integer(design$beta_index)]
  alpha <- theta[as.integer(design$alpha_index)]
  X_beta <- as.matrix(design$X_beta)
  X_alpha <- as.matrix(design$X_alpha)
  feature_info_beta <- design$feature_info_beta
  feature_info_alpha <- design$feature_info_alpha
  dates <- as.Date(design$base_panel$target_date)
  baseline <- as.numeric(design$discrepancy_baseline_fixed %||% rep(0, nrow(X_alpha)))
  if (nrow(X_beta) != length(dates) || nrow(X_alpha) != length(dates) ||
      nrow(X_alpha) != length(baseline)) {
    stop("The p95 two-block design and history dates are not aligned.", call. = FALSE)
  }
  fitted_reference <- as.numeric(X_beta %*% beta)
  fitted_discrepancy <- baseline + as.numeric(X_alpha %*% alpha)
  observed <- component_history[match(dates, component_history$target_date), , drop = FALSE]
  if (any(is.na(observed$target_date))) {
    stop("The retained p95 design dates do not match the component history.", call. = FALSE)
  }
  component_alignment <- data.frame(
    candidate_id = candidate_id,
    n_dates = length(dates),
    max_abs_reference_alignment_error = max(abs(fitted_reference - observed$q_y_mean)),
    max_abs_discrepancy_alignment_error = max(abs(fitted_discrepancy - observed$d_g_mean)),
    stringsAsFactors = FALSE
  )
  component_alignment$max_abs_component_alignment_error <- max(
    component_alignment$max_abs_reference_alignment_error,
    component_alignment$max_abs_discrepancy_alignment_error
  )
  top_n <- min(as.integer(top_n), length(dates))
  selected <- order(-observed$q_y_original)[seq_len(top_n)]
  contributions_beta <- app_glofas_mechanism_contributions(
    X_beta[selected, , drop = FALSE], beta, feature_info_beta,
    component = "q_y", path_name = "observed_history_p95_excursion",
    horizon = selected
  )
  contributions_alpha <- app_glofas_mechanism_contributions(
    X_alpha[selected, , drop = FALSE], alpha, feature_info_alpha,
    component = "d_g", path_name = "observed_history_p95_excursion",
    horizon = selected
  )
  contributions <- rbind(contributions_beta, contributions_alpha)
  contributions$target_date <- dates[match(contributions$horizon, selected)]
  contributions$candidate_id <- candidate_id
  if (any(baseline[selected] != 0)) {
    contributions <- rbind(
      contributions,
      data.frame(
        component = "d_g",
        path_name = "observed_history_p95_excursion",
        horizon = selected,
        feature_group = "persistence_baseline",
        contribution = baseline[selected],
        target_date = dates[selected],
        candidate_id = candidate_id,
        stringsAsFactors = FALSE
      )
    )
  }
  contributions <- contributions[order(contributions$target_date, -abs(contributions$contribution)), , drop = FALSE]
  group_summary_one <- function(X, coefficients, feature_info, component) {
    groups <- app_glofas_mechanism_feature_group(feature_info)
    app_bind_rows_fill(lapply(split(seq_len(ncol(X)), groups), function(index) {
      value <- as.numeric(X[, index, drop = FALSE] %*% coefficients[index])
      data.frame(
        candidate_id = candidate_id,
        component = component,
        feature_group = groups[index[[1L]]],
        n_features = length(index),
        mean_abs_contribution = mean(abs(value)),
        q99_abs_contribution = unname(stats::quantile(abs(value), 0.99)),
        max_abs_contribution = max(abs(value)),
        contribution_at_largest_q_y = value[selected[[1L]]],
        stringsAsFactors = FALSE
      )
    }))
  }
  group_rows <- list(
    group_summary_one(X_beta, beta, feature_info_beta, "q_y"),
    group_summary_one(X_alpha, alpha, feature_info_alpha, "d_g")
  )
  group_summary <- app_bind_rows_fill(group_rows)
  group_summary <- group_summary[order(-abs(group_summary$contribution_at_largest_q_y)), , drop = FALSE]
  shift <- rbind(
    app_glofas_mechanism_shift(
      X_beta, X_beta[selected, , drop = FALSE], feature_info_beta,
      block = "beta_readout", path_name = "observed_history_p95_excursion",
      horizon = selected
    ),
    app_glofas_mechanism_shift(
      X_alpha, X_alpha[selected, , drop = FALSE], feature_info_alpha,
      block = "alpha_readout", path_name = "observed_history_p95_excursion",
      horizon = selected
    )
  )
  shift$target_date <- dates[match(shift$horizon, selected)]
  shift$candidate_id <- candidate_id
  list(
    alignment = component_alignment,
    contributions = contributions,
    group_summary = group_summary,
    feature_shift = shift
  )
}

app_glofas_scientific_promotion_gate <- function(
  candidate_id,
  score_distribution,
  tail_summary,
  component_summary,
  contribution_alignment,
  thresholds = app_glofas_scientific_audit_defaults()
) {
  scores <- score_distribution[
    score_distribution$candidate_id == candidate_id &
      score_distribution$window == "all" &
      score_distribution$estimate_mode == "isotonic",
    , drop = FALSE
  ]
  upper <- tail_summary[
    tail_summary$candidate_id == candidate_id &
      tail_summary$estimate_mode == "independent",
    , drop = FALSE
  ]
  if (nrow(scores) != 2L || !setequal(scores$score_scale, c("log1p", "original")) ||
      nrow(upper) != 1L || nrow(component_summary) != 1L || nrow(contribution_alignment) != 1L) {
    stop("Scientific promotion evidence is incomplete or duplicated.", call. = FALSE)
  }
  dual_scale_pass <- all(app_as_bool_vec(scores$all_finite))
  identity_pass <- component_summary$prediction_identity_max_abs_error <=
    thresholds$component_identity_tolerance &&
    component_summary$observed_identity_max_abs_error <=
      thresholds$component_identity_tolerance
  attribution_pass <- contribution_alignment$max_abs_component_alignment_error <=
    thresholds$max_attribution_alignment_error
  tail_pass <- upper$fitted_max_to_observed_max_ratio <=
    thresholds$max_fitted_to_observed_max_ratio && upper$n_above_20x_observed_max == 0L
  discrepancy_pass <- component_summary$fitted_abs_discrepancy_to_history_q995_ratio <=
    thresholds$max_abs_discrepancy_to_history_q995_ratio
  gate_pass <- dual_scale_pass && identity_pass && attribution_pass && tail_pass && discrepancy_pass
  failed <- c(
    if (!dual_scale_pass) "dual_scale_finite",
    if (!identity_pass) "component_identity",
    if (!attribution_pass) "component_attribution_alignment",
    if (!tail_pass) "p95_tail_scale",
    if (!discrepancy_pass) "p95_discrepancy_support"
  )
  data.frame(
    candidate_id = candidate_id,
    dual_scale_finite_gate_pass = dual_scale_pass,
    component_identity_gate_pass = identity_pass,
    component_attribution_alignment_gate_pass = attribution_pass,
    p95_tail_scale_gate_pass = tail_pass,
    p95_discrepancy_support_gate_pass = discrepancy_pass,
    scientific_promotion_gate_pass = gate_pass,
    failed_gates = if (length(failed)) paste(failed, collapse = ";") else "none",
    decision = if (gate_pass) "eligible_for_human_review" else "promotion_blocked",
    auto_promote = FALSE,
    article_update_authorized = FALSE,
    stringsAsFactors = FALSE
  )
}
