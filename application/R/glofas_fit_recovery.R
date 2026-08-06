# Utilities for recovering and auditing historical GloFAS observed-window fits.

app_glofas_fit_recovery_windows <- function(windows = c(NA_integer_, 1000L, 500L, 200L, 100L, 50L)) {
  windows <- suppressWarnings(as.integer(windows))
  if (any(is.finite(windows) & windows <= 0L)) {
    stop("Observed-fit windows must be positive integers or NA for the full window.", call. = FALSE)
  }
  unique(windows)
}

app_glofas_fit_recovery_window_label <- function(window) {
  if (!length(window) || !is.finite(window[[1L]])) "all" else paste0("last", as.integer(window[[1L]]))
}

app_glofas_fit_recovery_safe_expm1 <- function(x, upper = 40) {
  out <- expm1(pmin(as.numeric(x), upper))
  out[!is.finite(out)] <- NA_real_
  out
}

app_glofas_fit_recovery_check_loss <- function(y, qhat, tau = 0.5) {
  y <- as.numeric(y)
  qhat <- as.numeric(qhat)
  keep <- is.finite(y) & is.finite(qhat)
  if (!any(keep)) return(NA_real_)
  u <- y[keep] - qhat[keep]
  mean(u * (tau - as.numeric(u < 0)))
}

app_glofas_fit_recovery_portability_defaults <- function() {
  list(
    max_check_loss_ratio_vs_raw = 1,
    max_component_identity_error = 1e-8,
    max_forecast_to_observed_max_ratio = 10,
    max_abs_discrepancy_to_history_q995_ratio = 1.5
  )
}

app_glofas_fit_recovery_portability_audit <- function(
  qscored,
  rawscored,
  discrepancy_history,
  thresholds = app_glofas_fit_recovery_portability_defaults()
) {
  required_q <- c("target_date", "horizon", "qhat", "y_reference", "q_g_hat", "d_g_hat")
  required_raw <- c("target_date", "qhat")
  required_history <- c("target_date", "observed_discrepancy")
  missing_q <- setdiff(required_q, names(qscored))
  missing_raw <- setdiff(required_raw, names(rawscored))
  missing_history <- setdiff(required_history, names(discrepancy_history))
  if (length(missing_q) || length(missing_raw) || length(missing_history)) {
    stop(sprintf(
      "Portability audit inputs are incomplete (q: %s; raw: %s; history: %s).",
      paste(missing_q, collapse = ", "), paste(missing_raw, collapse = ", "),
      paste(missing_history, collapse = ", ")
    ), call. = FALSE)
  }
  threshold_names <- names(app_glofas_fit_recovery_portability_defaults())
  if (!all(threshold_names %in% names(thresholds))) {
    stop("Portability thresholds are incomplete.", call. = FALSE)
  }
  q <- qscored
  raw <- rawscored
  q$target_date <- as.Date(q$target_date)
  raw$target_date <- as.Date(raw$target_date)
  raw <- raw[match(q$target_date, raw$target_date), , drop = FALSE]
  if (any(is.na(raw$target_date)) || any(!is.finite(as.numeric(raw$qhat)))) {
    stop("Raw and Q-DESN forecasts do not share a complete target-date grid.", call. = FALSE)
  }
  numeric_q <- c("qhat", "y_reference", "q_g_hat", "d_g_hat")
  if (any(!vapply(q[numeric_q], function(x) all(is.finite(as.numeric(x))), logical(1L)))) {
    stop("Q-DESN portability inputs contain non-finite forecast components.", call. = FALSE)
  }
  qhat <- as.numeric(q$qhat)
  y <- as.numeric(q$y_reference)
  q_g <- as.numeric(q$q_g_hat)
  d_g <- as.numeric(q$d_g_hat)
  raw_qhat <- as.numeric(raw$qhat)
  identity_error <- abs(qhat - (q_g - d_g))
  q_loss <- app_glofas_fit_recovery_check_loss(y, qhat, tau = 0.5)
  raw_loss <- app_glofas_fit_recovery_check_loss(y, raw_qhat, tau = 0.5)
  observed_original <- app_glofas_fit_recovery_safe_expm1(y)
  qhat_original <- app_glofas_fit_recovery_safe_expm1(qhat)
  observed_max <- max(observed_original, na.rm = TRUE)
  forecast_ratio <- max(qhat_original, na.rm = TRUE) / observed_max
  historical_abs <- abs(as.numeric(discrepancy_history$observed_discrepancy))
  historical_abs <- historical_abs[is.finite(historical_abs)]
  if (!length(historical_abs)) stop("Historical discrepancy support is empty.", call. = FALSE)
  history_q995 <- unname(stats::quantile(historical_abs, 0.995, na.rm = TRUE))
  discrepancy_ratio <- max(abs(d_g), na.rm = TRUE) / max(history_q995, .Machine$double.eps)
  performance_pass <- is.finite(q_loss) && is.finite(raw_loss) &&
    q_loss <= thresholds$max_check_loss_ratio_vs_raw * raw_loss
  identity_pass <- max(identity_error) <= thresholds$max_component_identity_error
  forecast_scale_pass <- forecast_ratio <= thresholds$max_forecast_to_observed_max_ratio
  discrepancy_support_pass <- discrepancy_ratio <= thresholds$max_abs_discrepancy_to_history_q995_ratio

  detail <- data.frame(
    target_date = q$target_date,
    horizon = as.integer(q$horizon),
    y_log1p = y,
    raw_log1p = raw_qhat,
    q_g_log1p = q_g,
    d_g_log1p = d_g,
    q_y_log1p = qhat,
    component_identity_error = identity_error,
    y_original = observed_original,
    raw_original = app_glofas_fit_recovery_safe_expm1(raw_qhat),
    q_g_original = app_glofas_fit_recovery_safe_expm1(q_g),
    q_y_original = qhat_original,
    stringsAsFactors = FALSE
  )
  summary <- data.frame(
    qdesn_check_loss_mean = q_loss,
    raw_check_loss_mean = raw_loss,
    check_loss_ratio_vs_raw = q_loss / raw_loss,
    component_identity_max_abs_error = max(identity_error),
    forecast_to_observed_max_ratio = forecast_ratio,
    forecast_abs_discrepancy_max = max(abs(d_g)),
    history_abs_discrepancy_q995 = history_q995,
    forecast_abs_discrepancy_to_history_q995_ratio = discrepancy_ratio,
    performance_gate_pass = performance_pass,
    component_identity_gate_pass = identity_pass,
    forecast_scale_gate_pass = forecast_scale_pass,
    discrepancy_support_gate_pass = discrepancy_support_pass,
    scientific_portability_gate_pass = performance_pass && identity_pass &&
      forecast_scale_pass && discrepancy_support_pass,
    stringsAsFactors = FALSE
  )
  list(summary = summary, detail = detail)
}

app_glofas_fit_recovery_history <- function(
  x,
  candidate_id,
  cutoff_date,
  qhat_candidates = c("q_y_median", "q_y_mean", "qhat"),
  observed_candidates = c("y_reference", "y_transformed"),
  raw_candidates = c("glofas_retrospective", "raw_glofas", "g_transformed")
) {
  if (is.character(x) && length(x) == 1L) {
    x <- app_read_csv(x)
  }
  if (!is.data.frame(x) || !nrow(x)) {
    stop("Observed-fit history must be a nonempty data frame or CSV path.", call. = FALSE)
  }
  required_date <- "target_date"
  if (!required_date %in% names(x)) {
    stop("Observed-fit history requires target_date.", call. = FALSE)
  }
  first_present <- function(candidates, required = TRUE) {
    hit <- intersect(candidates, names(x))
    if (!length(hit)) {
      if (isTRUE(required)) {
        stop(sprintf("Observed-fit history lacks all candidate columns: %s.", paste(candidates, collapse = ", ")), call. = FALSE)
      }
      return(NULL)
    }
    hit[[1L]]
  }
  observed_col <- first_present(observed_candidates)
  qhat_col <- first_present(qhat_candidates)
  raw_col <- first_present(raw_candidates, required = FALSE)
  target_date <- as.Date(x$target_date)
  cutoff_date <- as.Date(cutoff_date)
  keep <- !is.na(target_date) &
    target_date <= cutoff_date &
    is.finite(as.numeric(x[[observed_col]])) &
    is.finite(as.numeric(x[[qhat_col]]))
  out <- data.frame(
    candidate_id = as.character(candidate_id),
    target_date = target_date[keep],
    cutoff_date = cutoff_date,
    y_log1p = as.numeric(x[[observed_col]])[keep],
    qhat_log1p = as.numeric(x[[qhat_col]])[keep],
    raw_log1p = if (is.null(raw_col)) NA_real_ else as.numeric(x[[raw_col]])[keep],
    stringsAsFactors = FALSE
  )
  out <- out[order(out$target_date), , drop = FALSE]
  if (!nrow(out)) {
    stop(sprintf("Candidate %s has no finite observations before cutoff %s.", candidate_id, cutoff_date), call. = FALSE)
  }
  if (anyDuplicated(out$target_date)) {
    stop(sprintf("Candidate %s has duplicate pre-cutoff target dates.", candidate_id), call. = FALSE)
  }
  out$y_original <- app_glofas_fit_recovery_safe_expm1(out$y_log1p)
  out$qhat_original <- app_glofas_fit_recovery_safe_expm1(out$qhat_log1p)
  out$raw_original <- app_glofas_fit_recovery_safe_expm1(out$raw_log1p)
  out
}

app_glofas_fit_recovery_metric_row <- function(history, window = NA_integer_, tau = 0.5) {
  if (!is.data.frame(history) || !nrow(history)) {
    stop("Cannot score an empty observed-fit history.", call. = FALSE)
  }
  window <- suppressWarnings(as.integer(window))
  idx <- if (length(window) && is.finite(window)) {
    tail(seq_len(nrow(history)), min(window, nrow(history)))
  } else {
    seq_len(nrow(history))
  }
  h <- history[idx, , drop = FALSE]
  err_log <- h$qhat_log1p - h$y_log1p
  err_original <- h$qhat_original - h$y_original
  raw_ok <- is.finite(h$raw_log1p) & is.finite(h$raw_original)
  raw_err_log <- h$raw_log1p[raw_ok] - h$y_log1p[raw_ok]
  raw_err_original <- h$raw_original[raw_ok] - h$y_original[raw_ok]
  peak_cut <- suppressWarnings(stats::quantile(h$y_original, probs = 0.95, na.rm = TRUE, names = FALSE))
  peak <- is.finite(h$y_original) & h$y_original >= peak_cut
  check_loss <- app_glofas_fit_recovery_check_loss(h$y_log1p, h$qhat_log1p, tau = tau)
  absolute_error <- mean(abs(err_log))
  data.frame(
    candidate_id = unique(h$candidate_id)[[1L]],
    quantile_level = as.numeric(tau),
    window = app_glofas_fit_recovery_window_label(window),
    date_min = as.character(min(h$target_date)),
    date_max = as.character(max(h$target_date)),
    n = nrow(h),
    log1p_mae = mean(abs(err_log)),
    log1p_rmse = sqrt(mean(err_log^2)),
    log1p_bias = mean(err_log),
    check_loss_mean = check_loss,
    absolute_error_mean = absolute_error,
    p50_check_loss_mean = if (isTRUE(all.equal(as.numeric(tau), 0.5, tolerance = 1e-12))) check_loss else NA_real_,
    p50_degenerate_crps_proxy_mean = if (isTRUE(all.equal(as.numeric(tau), 0.5, tolerance = 1e-12))) absolute_error else NA_real_,
    original_mae = mean(abs(err_original)),
    original_rmse = sqrt(mean(err_original^2)),
    original_bias = mean(err_original),
    peak95_original_mae = if (any(peak)) mean(abs(err_original[peak])) else NA_real_,
    peak95_original_bias = if (any(peak)) mean(err_original[peak]) else NA_real_,
    max_observed_original = max(h$y_original, na.rm = TRUE),
    max_fitted_original = max(h$qhat_original, na.rm = TRUE),
    raw_log1p_mae = if (length(raw_err_log)) mean(abs(raw_err_log)) else NA_real_,
    raw_log1p_rmse = if (length(raw_err_log)) sqrt(mean(raw_err_log^2)) else NA_real_,
    raw_original_mae = if (length(raw_err_original)) mean(abs(raw_err_original)) else NA_real_,
    raw_original_rmse = if (length(raw_err_original)) sqrt(mean(raw_err_original^2)) else NA_real_,
    stringsAsFactors = FALSE
  )
}

app_glofas_fit_recovery_score_history <- function(
  history,
  windows = app_glofas_fit_recovery_windows(),
  tau = 0.5
) {
  rows <- lapply(windows, function(window) {
    app_glofas_fit_recovery_metric_row(history, window = window, tau = tau)
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

app_glofas_fit_recovery_align_histories <- function(histories) {
  if (!is.list(histories) || length(histories) < 2L) {
    stop("At least two candidate histories are required for common-date alignment.", call. = FALSE)
  }
  common_dates <- Reduce(intersect, lapply(histories, function(x) as.Date(x$target_date)))
  common_dates <- sort(as.Date(common_dates, origin = "1970-01-01"))
  if (!length(common_dates)) stop("Candidate histories have no common target dates.", call. = FALSE)
  lapply(histories, function(x) {
    out <- x[x$target_date %in% common_dates, , drop = FALSE]
    out[order(out$target_date), , drop = FALSE]
  })
}

app_glofas_fit_recovery_required_candidate_columns <- function() {
  c(
    "candidate_id", "role", "include_input_block",
    "direct_output_lag_max", "direct_covariate_lag_max",
    "alpha", "rhs_tau0", "rhs_alpha_tau0",
    "retain_heavy", "priority"
  )
}

app_glofas_fit_recovery_validate_candidates <- function(x) {
  if (!is.data.frame(x) || !nrow(x)) stop("Recovery candidate manifest is empty.", call. = FALSE)
  missing <- setdiff(app_glofas_fit_recovery_required_candidate_columns(), names(x))
  if (length(missing)) {
    stop(sprintf("Recovery candidate manifest is missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  if (any(!nzchar(x$candidate_id)) || anyDuplicated(x$candidate_id)) {
    stop("Recovery candidate IDs must be nonempty and unique.", call. = FALSE)
  }
  x$include_input_block <- app_as_bool_vec(x$include_input_block)
  x$retain_heavy <- app_as_bool_vec(x$retain_heavy)
  numeric_columns <- c(
    "direct_output_lag_max", "direct_covariate_lag_max", "alpha",
    "rhs_tau0", "rhs_alpha_tau0", "priority"
  )
  for (nm in numeric_columns) x[[nm]] <- suppressWarnings(as.numeric(x[[nm]]))
  if (any(!is.finite(x$alpha) | x$alpha <= 0 | x$alpha > 1)) {
    stop("Recovery candidate alpha values must lie in (0, 1].", call. = FALSE)
  }
  if (any(!is.finite(x$rhs_tau0) | x$rhs_tau0 <= 0) ||
      any(!is.finite(x$rhs_alpha_tau0) | x$rhs_alpha_tau0 <= 0)) {
    stop("Recovery candidate RHS tau0 values must be positive.", call. = FALSE)
  }
  direct <- x$include_input_block
  if (any(!is.finite(x$direct_output_lag_max[direct]) | x$direct_output_lag_max[direct] < 1) ||
      any(!is.finite(x$direct_covariate_lag_max[direct]) | x$direct_covariate_lag_max[direct] < 0)) {
    stop("Enabled direct readout blocks require valid output and covariate lag maxima.", call. = FALSE)
  }
  if (any(!is.finite(x$priority)) || anyDuplicated(x$priority)) {
    stop("Recovery candidate priorities must be finite and unique.", call. = FALSE)
  }
  x$expected_n_block_features <- ifelse(
    x$include_input_block,
    1L + 300L + as.integer(x$direct_output_lag_max) +
      2L * (as.integer(x$direct_covariate_lag_max) + 1L),
    301L
  )
  x[order(x$priority), , drop = FALSE]
}

app_glofas_fit_recovery_contract_audit <- function(
  observed,
  expected,
  required_fields = names(expected)
) {
  if (!is.data.frame(observed) || nrow(observed) != 1L) {
    stop("Observed design summary must contain exactly one row.", call. = FALSE)
  }
  missing <- setdiff(required_fields, names(observed))
  if (length(missing)) {
    stop(sprintf("Design summary lacks required parity fields: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  rows <- lapply(required_fields, function(field) {
    expected_value <- expected[[field]]
    observed_value <- observed[[field]][[1L]]
    equal <- if (is.numeric(expected_value) || is.numeric(observed_value)) {
      isTRUE(all.equal(as.numeric(observed_value), as.numeric(expected_value), tolerance = 0))
    } else {
      identical(as.character(observed_value), as.character(expected_value))
    }
    data.frame(
      field = field,
      expected = paste(expected_value, collapse = ";"),
      observed = paste(observed_value, collapse = ";"),
      equal = equal,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

app_glofas_fit_recovery_heavy_inventory <- function(run_dir) {
  run_dir <- normalizePath(run_dir, mustWork = TRUE)
  paths <- list.files(run_dir, recursive = TRUE, full.names = TRUE)
  ext <- tolower(tools::file_ext(paths))
  paths <- paths[ext %in% app_generated_artifact_extensions()]
  info <- file.info(paths)
  data.frame(
    path = paths,
    extension = tolower(tools::file_ext(paths)),
    size_bytes = as.numeric(info$size),
    stringsAsFactors = FALSE
  )
}

app_glofas_fit_recovery_cleanup <- function(
  run_dir,
  runs_root,
  execute = FALSE,
  protected = FALSE,
  completion_marker = ".fit_recovery_complete"
) {
  run_dir <- normalizePath(run_dir, mustWork = TRUE)
  runs_root <- normalizePath(runs_root, mustWork = TRUE)
  prefix <- paste0(runs_root, .Platform$file.sep)
  if (!startsWith(run_dir, prefix)) {
    stop("Cleanup target is outside the declared recovery runs root.", call. = FALSE)
  }
  inventory <- app_glofas_fit_recovery_heavy_inventory(run_dir)
  inventory$action <- if (isTRUE(protected)) "keep_protected" else "delete_candidate"
  inventory$executed <- FALSE
  if (!isTRUE(protected) && isTRUE(execute)) {
    marker <- file.path(run_dir, completion_marker)
    if (!file.exists(marker)) {
      stop(sprintf("Refusing cleanup without completion marker: %s.", marker), call. = FALSE)
    }
    if (nrow(inventory)) {
      removed <- file.remove(inventory$path)
      if (!all(removed)) stop("One or more heavy recovery artifacts could not be removed.", call. = FALSE)
      inventory$executed <- removed
    }
  }
  inventory
}
