# Reproducible campaign helpers for causal GloFAS discrepancy transitions.

app_glofas_transition_required_candidate_columns <- function() {
  c(
    "candidate_id", "anchor_method", "anchor_window", "anchor_half_life",
    "glofas_level", "glofas_anomaly", "anomaly_window",
    "context_in_reservoir", "context_in_readout", "context_lags",
    "priority", "enabled", "role", "retain_heavy"
  )
}

app_glofas_transition_validate_candidates <- function(x) {
  if (!is.data.frame(x) || !nrow(x)) {
    stop("The discrepancy-transition candidate registry is empty.", call. = FALSE)
  }
  missing <- setdiff(app_glofas_transition_required_candidate_columns(), names(x))
  if (length(missing)) {
    stop(sprintf(
      "The discrepancy-transition candidate registry is missing: %s.",
      paste(missing, collapse = ", ")
    ), call. = FALSE)
  }
  x <- x[app_as_bool_vec(x$enabled), , drop = FALSE]
  if (!nrow(x)) stop("No discrepancy-transition candidate is enabled.", call. = FALSE)
  if (any(!nzchar(as.character(x$candidate_id))) || anyDuplicated(x$candidate_id)) {
    stop("Enabled transition candidate IDs must be nonempty and unique.", call. = FALSE)
  }
  if (any(grepl("[/\\\\]", x$candidate_id))) {
    stop("Transition candidate IDs must be path safe.", call. = FALSE)
  }
  x$anchor_method <- tolower(as.character(x$anchor_method))
  x$anchor_window <- suppressWarnings(as.integer(x$anchor_window))
  x$anchor_half_life <- suppressWarnings(as.numeric(x$anchor_half_life))
  x$glofas_level <- app_as_bool_vec(x$glofas_level)
  x$glofas_anomaly <- app_as_bool_vec(x$glofas_anomaly)
  x$context_in_reservoir <- app_as_bool_vec(x$context_in_reservoir)
  x$context_in_readout <- app_as_bool_vec(x$context_in_readout)
  x$retain_heavy <- app_as_bool_vec(x$retain_heavy)
  x$anomaly_window <- suppressWarnings(as.integer(x$anomaly_window))
  x$priority <- suppressWarnings(as.integer(x$priority))
  allowed <- c("last", "rolling_mean", "rolling_median", "ewma")
  if (any(!x$anchor_method %in% allowed)) {
    stop("Transition registry contains an unsupported anchor method.", call. = FALSE)
  }
  rolling <- x$anchor_method %in% c("rolling_mean", "rolling_median")
  if (any(!is.finite(x$anchor_window[rolling]) | x$anchor_window[rolling] < 1L)) {
    stop("Rolling transition candidates require anchor_window >= 1.", call. = FALSE)
  }
  ewma <- x$anchor_method == "ewma"
  if (any(!is.finite(x$anchor_half_life[ewma]) | x$anchor_half_life[ewma] <= 0)) {
    stop("EWMA transition candidates require anchor_half_life > 0.", call. = FALSE)
  }
  if (any(!is.finite(x$anomaly_window) | x$anomaly_window < 1L)) {
    stop("Transition candidates require anomaly_window >= 1.", call. = FALSE)
  }
  if (any(!is.finite(x$priority)) || anyDuplicated(x$priority)) {
    stop("Transition candidate priorities must be finite and unique.", call. = FALSE)
  }
  legacy_comparator <- as.character(x$role) ==
    "legacy_mechanism_comparator"
  if (sum(legacy_comparator) != 1L ||
      !identical(as.character(x$candidate_id[legacy_comparator]), "t01_last")) {
    stop(
      "The transition registry requires exactly one t01_last legacy mechanism comparator.",
      call. = FALSE
    )
  }
  context_enabled <- x$glofas_level | x$glofas_anomaly
  if (any(context_enabled & !(x$context_in_reservoir | x$context_in_readout))) {
    stop("Enabled GloFAS context must enter a discrepancy feature block.", call. = FALSE)
  }
  x$context_lags <- vapply(x$context_lags, function(value) {
    paste(app_parse_lag_spec(
      strsplit(as.character(value), ";", fixed = TRUE)[[1L]],
      default = 0L,
      allow_zero = TRUE,
      label = "transition candidate context_lags"
    ), collapse = ";")
  }, character(1L))
  x[order(x$priority), , drop = FALSE]
}

app_glofas_transition_required_cutoff_columns <- function() {
  c(
    "cutoff_id", "origin_date", "bundle_dir", "glofas_source_id",
    "future_policy", "selection_role", "priority", "enabled"
  )
}

app_glofas_transition_validate_cutoffs <- function(
  x,
  repo_root = app_repo_root(),
  data_local_root = NULL
) {
  if (!is.data.frame(x) || !nrow(x)) {
    stop("The discrepancy-transition cutoff registry is empty.", call. = FALSE)
  }
  missing <- setdiff(app_glofas_transition_required_cutoff_columns(), names(x))
  if (length(missing)) {
    stop(sprintf(
      "The discrepancy-transition cutoff registry is missing: %s.",
      paste(missing, collapse = ", ")
    ), call. = FALSE)
  }
  x <- x[app_as_bool_vec(x$enabled), , drop = FALSE]
  x$origin_date <- as.Date(x$origin_date)
  x$priority <- suppressWarnings(as.integer(x$priority))
  if (!nrow(x) || any(is.na(x$origin_date))) {
    stop("Enabled transition cutoffs require valid origin dates.", call. = FALSE)
  }
  if (anyDuplicated(x$cutoff_id) || anyDuplicated(x$origin_date)) {
    stop("Enabled transition cutoff IDs and origin dates must be unique.", call. = FALSE)
  }
  if (any(!is.finite(x$priority)) || anyDuplicated(x$priority)) {
    stop("Transition cutoff priorities must be finite and unique.", call. = FALSE)
  }
  if (any(as.character(x$future_policy) != "origin_persistence")) {
    stop("Development cutoffs must use future_policy = origin_persistence.", call. = FALSE)
  }
  if (any(x$origin_date == as.Date("2022-12-25"))) {
    stop("The December 2022 adjudication origin cannot enter development.", call. = FALSE)
  }
  allowed_roles <- c("primary_v31", "supplemental_v21")
  if (any(!as.character(x$selection_role) %in% allowed_roles)) {
    stop("Transition cutoff selection roles are invalid.", call. = FALSE)
  }
  if (sum(x$selection_role == "primary_v31") != 3L) {
    stop("The frozen campaign requires exactly three primary v3.1 origins.", call. = FALSE)
  }
  bundle_path <- vapply(x$bundle_dir, function(path) {
    candidate <- if (grepl("^/", path)) path else file.path(repo_root, path)
    if (!file.exists(candidate) && !is.null(data_local_root) &&
        startsWith(path, "application/data_local/")) {
      relative <- substring(path, nchar("application/data_local/") + 1L)
      candidate <- file.path(data_local_root, relative)
    }
    normalizePath(candidate, mustWork = TRUE)
  }, character(1L))
  required <- c(
    "reference/reference_gauge.csv",
    "glofas/glofas_retrospective.csv",
    "glofas/glofas_ensemble.csv",
    "covariates/climate_covariates.csv"
  )
  for (i in seq_len(nrow(x))) {
    missing_files <- required[!file.exists(file.path(bundle_path[[i]], required))]
    if (length(missing_files)) {
      stop(sprintf(
        "Cutoff %s is missing bundle files: %s.",
        x$cutoff_id[[i]], paste(missing_files, collapse = ", ")
      ), call. = FALSE)
    }
  }
  x$bundle_path <- bundle_path
  x[order(x$priority), , drop = FALSE]
}

app_glofas_transition_contract_from_candidate <- function(row) {
  if (!is.data.frame(row) || nrow(row) != 1L) {
    stop("A transition candidate row must contain exactly one record.", call. = FALSE)
  }
  if (identical(
    as.character(row$role[[1L]]),
    "legacy_mechanism_comparator"
  )) {
    if (!identical(as.character(row$anchor_method[[1L]]), "last") ||
        isTRUE(row$glofas_level[[1L]]) ||
        isTRUE(row$glofas_anomaly[[1L]])) {
      stop(
        "The frozen FR09 comparator must use the legacy last-anchor contract without GloFAS context.",
        call. = FALSE
      )
    }
    return(app_glofas_discrepancy_transition_contract(list(
      prediction = list(
        discrepancy_transition_strategy = "persistence_anchored_innovation"
      )
    )))
  }
  lags <- as.integer(strsplit(
    as.character(row$context_lags[[1L]]), ";", fixed = TRUE
  )[[1L]])
  cfg <- list(prediction = list(discrepancy_transition = list(
    anchor = list(
      method = as.character(row$anchor_method[[1L]]),
      window = if (is.finite(row$anchor_window[[1L]])) {
        as.integer(row$anchor_window[[1L]])
      } else {
        NULL
      },
      half_life = if (is.finite(row$anchor_half_life[[1L]])) {
        as.numeric(row$anchor_half_life[[1L]])
      } else {
        NULL
      }
    ),
    evolution = list(method = "static_anchor_innovation"),
    context = list(
      glofas_level = isTRUE(row$glofas_level[[1L]]),
      glofas_anomaly = isTRUE(row$glofas_anomaly[[1L]]),
      anomaly_window = as.integer(row$anomaly_window[[1L]]),
      include_in_reservoir = isTRUE(row$context_in_reservoir[[1L]]),
      include_in_readout = isTRUE(row$context_in_readout[[1L]]),
      lags = lags
    )
  )))
  app_glofas_discrepancy_transition_contract(cfg)
}

app_glofas_transition_set_origin_persistence <- function(cfg) {
  cfg$covariates <- cfg$covariates %||% list()
  cfg$covariates$source_policy <- "realized_history_and_origin_persistence"
  cfg$covariates$future_policy <- "origin_persistence"
  cfg$covariates$allow_realized_future <- FALSE
  cfg$covariates$allow_realized_future_blend <- NULL
  cfg$covariates$forecast <- cfg$covariates$forecast %||% list()
  cfg$covariates$forecast$provider <- "historical_origin"
  cfg$covariates$forecast$handoff_root <- NULL
  for (variable in c("ppt", "soil")) {
    cfg$covariates[[variable]] <- cfg$covariates[[variable]] %||% list()
    cfg$covariates[[variable]]$noisy_blend <- NULL
    cfg$covariates[[variable]]$observed_blend <- NULL
    cfg$covariates[[variable]]$forecast_noise <- list(enabled = FALSE)
    cfg$covariates[[variable]]$realized_future_correction <- list(
      enabled = FALSE,
      observed_weight = 0
    )
  }
  cfg
}

app_glofas_transition_apply_candidate <- function(cfg, row) {
  contract <- app_glofas_transition_contract_from_candidate(row)
  cfg$prediction <- cfg$prediction %||% list()
  if (identical(
    as.character(row$role[[1L]]),
    "legacy_mechanism_comparator"
  )) {
    cfg$prediction[["discrepancy_transition"]] <- NULL
    cfg$prediction[["discrepancy_transition_strategy"]] <-
      "persistence_anchored_innovation"
    return(cfg)
  }
  cfg$prediction[["discrepancy_transition_strategy"]] <- NULL
  cfg$prediction[["discrepancy_transition"]] <- list(
    anchor = list(
      method = contract$anchor$method,
      window = if (is.finite(contract$anchor$window)) {
        as.integer(contract$anchor$window)
      } else {
        NULL
      },
      half_life = if (is.finite(contract$anchor$half_life)) {
        as.numeric(contract$anchor$half_life)
      } else {
        NULL
      }
    ),
    evolution = list(method = contract$evolution$method),
    context = list(
      glofas_level = contract$context$glofas_level,
      glofas_anomaly = contract$context$glofas_anomaly,
      anomaly_window = contract$context$anomaly_window,
      include_in_reservoir = contract$context$include_in_reservoir,
      include_in_readout = contract$context$include_in_readout,
      lags = as.integer(contract$context$lags)
    )
  )
  cfg
}

app_glofas_transition_check_loss <- function(y, q, tau = 0.5) {
  error <- as.numeric(y) - as.numeric(q)
  (as.numeric(tau) - as.numeric(error < 0)) * error
}

app_glofas_transition_metric_row <- function(
  candidate_id,
  cutoff_id,
  selection_role,
  y,
  q_y,
  raw_q_g,
  d_hat,
  q_g_hat = raw_q_g,
  method_class = "learned_transition"
) {
  y <- as.numeric(y)
  q_y <- as.numeric(q_y)
  raw_q_g <- as.numeric(raw_q_g)
  d_hat <- as.numeric(d_hat)
  q_g_hat <- as.numeric(q_g_hat)
  keep <- is.finite(y) & is.finite(q_y) & is.finite(raw_q_g) &
    is.finite(d_hat) & is.finite(q_g_hat)
  if (!any(keep)) stop("Transition score has no finite aligned rows.", call. = FALSE)
  y <- y[keep]
  q_y <- q_y[keep]
  raw_q_g <- raw_q_g[keep]
  d_hat <- d_hat[keep]
  q_g_hat <- q_g_hat[keep]
  d_proxy <- raw_q_g - y
  d_error <- d_hat - d_proxy
  q_error <- q_y - y
  g_error <- q_g_hat - raw_q_g
  correlation <- if (length(d_hat) > 1L && stats::sd(d_hat) > 0 &&
      stats::sd(d_proxy) > 0) stats::cor(d_hat, d_proxy) else NA_real_
  data.frame(
    candidate_id = as.character(candidate_id),
    cutoff_id = as.character(cutoff_id),
    selection_role = as.character(selection_role),
    method_class = as.character(method_class),
    n_horizons = length(y),
    future_p50_check_loss = mean(app_glofas_transition_check_loss(y, q_y, 0.5)),
    future_mae = mean(abs(q_error)),
    future_rmse = sqrt(mean(q_error^2)),
    future_bias = mean(q_error),
    discrepancy_proxy_mae = mean(abs(d_error)),
    discrepancy_proxy_rmse = sqrt(mean(d_error^2)),
    discrepancy_proxy_bias = mean(d_error),
    discrepancy_proxy_correlation = correlation,
    glofas_reconstruction_mae = mean(abs(g_error)),
    glofas_reconstruction_rmse = sqrt(mean(g_error^2)),
    stringsAsFactors = FALSE
  )
}

app_glofas_transition_score_prediction_table <- function(
  predictions,
  candidate_id,
  cutoff_id,
  selection_role
) {
  required <- c(
    "model_family", "qhat", "y_reference", "q_g_hat", "d_g_hat",
    "raw_glofas_quantile", "horizon", "target_date"
  )
  missing <- setdiff(required, names(predictions))
  if (length(missing)) {
    stop(sprintf(
      "Transition prediction table is missing: %s.",
      paste(missing, collapse = ", ")
    ), call. = FALSE)
  }
  q <- predictions[
    predictions$model_family == "qdesn_glofas_discrepancy",
    ,
    drop = FALSE
  ]
  q <- q[order(as.integer(q$horizon), as.Date(q$target_date)), , drop = FALSE]
  if (!nrow(q) || anyDuplicated(q[, c("target_date", "horizon")])) {
    stop("Transition candidate predictions are empty or duplicated.", call. = FALSE)
  }
  summary <- app_glofas_transition_metric_row(
    candidate_id = candidate_id,
    cutoff_id = cutoff_id,
    selection_role = selection_role,
    y = q$y_reference,
    q_y = q$qhat,
    raw_q_g = q$raw_glofas_quantile,
    d_hat = q$d_g_hat,
    q_g_hat = q$q_g_hat,
    method_class = "learned_transition"
  )
  horizon <- data.frame(
    candidate_id = candidate_id,
    cutoff_id = cutoff_id,
    selection_role = selection_role,
    target_date = as.Date(q$target_date),
    horizon = as.integer(q$horizon),
    y_reference = as.numeric(q$y_reference),
    q_y_hat = as.numeric(q$qhat),
    raw_q_g = as.numeric(q$raw_glofas_quantile),
    q_g_hat = as.numeric(q$q_g_hat),
    discrepancy_hat = as.numeric(q$d_g_hat),
    discrepancy_proxy = as.numeric(q$raw_glofas_quantile) -
      as.numeric(q$y_reference),
    check_loss = app_glofas_transition_check_loss(q$y_reference, q$qhat, 0.5),
    stringsAsFactors = FALSE
  )
  list(summary = summary, horizon = horizon)
}

app_glofas_transition_panel_future <- function(panel, origin_date) {
  origin_date <- as.Date(origin_date)
  ensemble <- panel[
    panel$is_ensemble & as.Date(panel$origin_date) == origin_date &
      as.Date(panel$target_date) > origin_date,
    ,
    drop = FALSE
  ]
  keys <- unique(ensemble[, c("target_date", "horizon"), drop = FALSE])
  keys <- keys[order(as.integer(keys$horizon), as.Date(keys$target_date)), , drop = FALSE]
  rows <- lapply(seq_len(nrow(keys)), function(i) {
    idx <- as.Date(ensemble$target_date) == as.Date(keys$target_date[[i]]) &
      as.integer(ensemble$horizon) == as.integer(keys$horizon[[i]])
    block <- ensemble[idx, , drop = FALSE]
    data.frame(
      target_date = as.Date(keys$target_date[[i]]),
      horizon = as.integer(keys$horizon[[i]]),
      y_reference = as.numeric(block$y_transformed[[1L]]),
      raw_q_g = app_ensemble_quantile(block, 0.5),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_glofas_transition_causal_baseline_scores <- function(
  panel,
  cutoff_id,
  origin_date,
  selection_role
) {
  history <- panel[
    panel$is_retrospective & as.Date(panel$target_date) <= as.Date(origin_date),
    c("target_date", "y_transformed", "g_transformed"),
    drop = FALSE
  ]
  history <- history[order(as.Date(history$target_date)), , drop = FALSE]
  history <- history[!duplicated(as.Date(history$target_date), fromLast = TRUE), , drop = FALSE]
  discrepancy_panel <- data.frame(
    target_date = as.Date(history$target_date),
    y_transformed = as.numeric(history$g_transformed) -
      as.numeric(history$y_transformed),
    stringsAsFactors = FALSE
  )
  future <- app_glofas_transition_panel_future(panel, origin_date)
  anchors <- app_glofas_discrepancy_causal_baselines(
    discrepancy_panel,
    as.Date(origin_date),
    nrow(future)
  )
  rows <- lapply(unique(anchors$baseline_id), function(baseline_id) {
    block <- anchors[anchors$baseline_id == baseline_id, , drop = FALSE]
    block <- block[order(block$horizon), , drop = FALSE]
    app_glofas_transition_metric_row(
      candidate_id = baseline_id,
      cutoff_id = cutoff_id,
      selection_role = selection_role,
      y = future$y_reference,
      q_y = future$raw_q_g - block$discrepancy,
      raw_q_g = future$raw_q_g,
      d_hat = block$discrepancy,
      q_g_hat = future$raw_q_g,
      method_class = "deterministic_causal_baseline"
    )
  })
  rows[[length(rows) + 1L]] <- app_glofas_transition_metric_row(
    candidate_id = "raw_glofas",
    cutoff_id = cutoff_id,
    selection_role = selection_role,
    y = future$y_reference,
    q_y = future$raw_q_g,
    raw_q_g = future$raw_q_g,
    d_hat = rep(0, nrow(future)),
    q_g_hat = future$raw_q_g,
    method_class = "raw_forecast_baseline"
  )
  do.call(rbind, rows)
}

app_glofas_transition_equal_origin_aggregate <- function(scores) {
  if (!is.data.frame(scores) || !nrow(scores)) {
    stop("Transition aggregation requires nonempty scores.", call. = FALSE)
  }
  metric_names <- c(
    "future_p50_check_loss", "future_mae", "future_rmse", "future_bias",
    "discrepancy_proxy_mae", "discrepancy_proxy_rmse",
    "discrepancy_proxy_bias", "discrepancy_proxy_correlation",
    "glofas_reconstruction_mae", "glofas_reconstruction_rmse"
  )
  rows <- lapply(unique(scores$candidate_id), function(candidate_id) {
    block <- scores[scores$candidate_id == candidate_id, , drop = FALSE]
    values <- vapply(metric_names, function(metric) {
      mean(as.numeric(block[[metric]]), na.rm = TRUE)
    }, numeric(1L))
    out <- data.frame(
      candidate_id = candidate_id,
      method_class = as.character(block$method_class[[1L]]),
      n_origins = nrow(block),
      stringsAsFactors = FALSE
    )
    for (metric in metric_names) out[[metric]] <- values[[metric]]
    out
  })
  do.call(rbind, rows)
}
