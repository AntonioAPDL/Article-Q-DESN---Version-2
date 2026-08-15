pricefm_horizon_block_labels <- function(horizon, block_size = 24L) {
  horizon <- as.integer(horizon)
  block_size <- as.integer(block_size)[1L]
  if (!length(horizon) || any(!is.finite(horizon)) || any(horizon < 1L)) {
    stop("horizon must contain positive finite integers.", call. = FALSE)
  }
  if (!is.finite(block_size) || block_size < 1L) {
    stop("block_size must be a positive integer.", call. = FALSE)
  }
  max_horizon <- max(horizon)
  starts <- ((horizon - 1L) %/% block_size) * block_size + 1L
  ends <- pmin(starts + block_size - 1L, max_horizon)
  paste0(starts, "-", ends)
}

pricefm_fit_horizon_block_models <- function(X, y, horizon, block_size, fit_fn) {
  X <- as.matrix(X)
  y <- as.numeric(y)
  if (nrow(X) != length(y) || length(y) != length(horizon)) {
    stop("X, y, and horizon must have matching row counts.", call. = FALSE)
  }
  labels <- pricefm_horizon_block_labels(horizon, block_size)
  block_names <- unique(labels)
  fits <- setNames(vector("list", length(block_names)), block_names)
  for (block_name in block_names) {
    idx <- which(labels == block_name)
    fits[[block_name]] <- fit_fn(
      X[idx, , drop = FALSE],
      y[idx],
      block_name,
      idx
    )
  }
  fits
}

pricefm_predict_horizon_block_models <- function(fits, X, horizon, block_size, predict_fn) {
  X <- as.matrix(X)
  if (nrow(X) != length(horizon)) {
    stop("X and horizon must have matching row counts.", call. = FALSE)
  }
  labels <- pricefm_horizon_block_labels(horizon, block_size)
  missing <- setdiff(unique(labels), names(fits))
  if (length(missing)) {
    stop("Missing fitted horizon block(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }
  out <- rep(NA_real_, nrow(X))
  for (block_name in unique(labels)) {
    idx <- which(labels == block_name)
    values <- as.numeric(predict_fn(fits[[block_name]], X[idx, , drop = FALSE], block_name))
    if (length(values) != length(idx) || any(!is.finite(values))) {
      stop("Nonfinite or incorrectly sized predictions for block ", block_name, ".", call. = FALSE)
    }
    out[idx] <- values
  }
  if (any(!is.finite(out))) {
    stop("Horizon-block prediction left nonfinite values.", call. = FALSE)
  }
  out
}

pricefm_partial_pool_predictions <- function(shared, separate, weight) {
  shared <- as.numeric(shared)
  separate <- as.numeric(separate)
  weight <- as.numeric(weight)[1L]
  if (length(shared) != length(separate) || !length(shared)) {
    stop("shared and separate predictions must be nonempty and equally sized.", call. = FALSE)
  }
  if (!is.finite(weight) || weight < 0 || weight > 1) {
    stop("partial-pooling weight must be in [0, 1].", call. = FALSE)
  }
  if (any(!is.finite(shared)) || any(!is.finite(separate))) {
    stop("partial-pooling predictions must be finite.", call. = FALSE)
  }
  (1 - weight) * shared + weight * separate
}

pricefm_build_nested_temporal_folds <- function(
    rows,
    n_folds = 3L,
    initial_train_fraction = 0.55,
    validation_fraction = 0.15,
    min_train_origins = 120L,
    min_validation_origins = 30L) {
  required <- c("origin_id", "origin_market_time", "response_market_time")
  missing <- setdiff(required, names(rows))
  if (length(missing)) {
    stop("Nested validation rows missing: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  n_folds <- as.integer(n_folds)[1L]
  initial_train_fraction <- as.numeric(initial_train_fraction)[1L]
  validation_fraction <- as.numeric(validation_fraction)[1L]
  min_train_origins <- as.integer(min_train_origins)[1L]
  min_validation_origins <- as.integer(min_validation_origins)[1L]
  if (n_folds < 1L) stop("n_folds must be positive.", call. = FALSE)
  if (!is.finite(initial_train_fraction) || initial_train_fraction <= 0 || initial_train_fraction >= 1) {
    stop("initial_train_fraction must lie in (0, 1).", call. = FALSE)
  }
  if (!is.finite(validation_fraction) || validation_fraction <= 0 || validation_fraction >= 1) {
    stop("validation_fraction must lie in (0, 1).", call. = FALSE)
  }
  if (initial_train_fraction + validation_fraction > 1) {
    stop("initial_train_fraction + validation_fraction cannot exceed 1.", call. = FALSE)
  }

  origin_time <- as.POSIXct(rows$origin_market_time, tz = "UTC")
  response_time <- as.POSIXct(rows$response_market_time, tz = "UTC")
  if (any(is.na(origin_time)) || any(is.na(response_time))) {
    stop("Nested validation timestamps must parse as UTC times.", call. = FALSE)
  }
  origin_frame <- unique(data.frame(
    origin_id = as.character(rows$origin_id),
    origin_market_time = origin_time,
    stringsAsFactors = FALSE
  ))
  duplicate_times <- table(origin_frame$origin_id)
  if (any(duplicate_times != 1L)) {
    stop("Each origin_id must map to exactly one origin_market_time.", call. = FALSE)
  }
  origin_frame <- origin_frame[order(origin_frame$origin_market_time, origin_frame$origin_id), , drop = FALSE]
  n_origins <- nrow(origin_frame)
  validation_origins <- max(min_validation_origins, floor(n_origins * validation_fraction))
  first_train_end <- max(min_train_origins, floor(n_origins * initial_train_fraction))
  last_train_end <- n_origins - validation_origins
  if (first_train_end > last_train_end) {
    stop("Not enough origins for the requested nested-validation geometry.", call. = FALSE)
  }
  train_ends <- unique(as.integer(round(seq(first_train_end, last_train_end, length.out = n_folds))))
  if (length(train_ends) != n_folds) {
    stop("Nested-validation geometry produced duplicate fold boundaries.", call. = FALSE)
  }

  folds <- vector("list", n_folds)
  summary_rows <- vector("list", n_folds)
  row_origin_id <- as.character(rows$origin_id)
  for (fold_id in seq_len(n_folds)) {
    train_end <- train_ends[[fold_id]]
    val_start <- train_end + 1L
    val_end <- train_end + validation_origins
    train_ids <- origin_frame$origin_id[seq_len(train_end)]
    val_ids <- origin_frame$origin_id[val_start:val_end]
    val_start_time <- origin_frame$origin_market_time[[val_start]]
    val_end_time <- origin_frame$origin_market_time[[val_end]]
    train_idx <- which(row_origin_id %in% train_ids & response_time < val_start_time)
    val_idx <- which(row_origin_id %in% val_ids)
    if (!length(train_idx) || !length(val_idx)) {
      stop("Nested fold ", fold_id, " has an empty train or validation set.", call. = FALSE)
    }
    if (max(response_time[train_idx]) >= min(origin_time[val_idx])) {
      stop("Nested fold ", fold_id, " violates the response-time embargo.", call. = FALSE)
    }
    folds[[fold_id]] <- list(train_index = train_idx, validation_index = val_idx)
    summary_rows[[fold_id]] <- data.frame(
      inner_fold = fold_id,
      n_train_origins = length(unique(row_origin_id[train_idx])),
      n_validation_origins = length(unique(row_origin_id[val_idx])),
      n_train_rows = length(train_idx),
      n_validation_rows = length(val_idx),
      train_response_end = format(max(response_time[train_idx]), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      validation_origin_start = format(val_start_time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      validation_origin_end = format(val_end_time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      embargo_passed = TRUE,
      stringsAsFactors = FALSE
    )
  }
  list(folds = folds, summary = do.call(rbind, summary_rows))
}

pricefm_quantile_diagnostics <- function(y, prediction, tau) {
  y <- as.numeric(y)
  prediction <- as.numeric(prediction)
  tau <- as.numeric(tau)[1L]
  if (length(y) != length(prediction) || !length(y)) {
    stop("y and prediction must be nonempty and equally sized.", call. = FALSE)
  }
  if (any(!is.finite(y)) || any(!is.finite(prediction)) || !is.finite(tau) || tau <= 0 || tau >= 1) {
    stop("Quantile diagnostics require finite inputs and tau in (0, 1).", call. = FALSE)
  }
  error <- y - prediction
  data.frame(
    AQL_scaled = mean(pmax(tau * error, (tau - 1) * error)),
    MAE_scaled = mean(abs(error)),
    RMSE_scaled = sqrt(mean(error^2)),
    bias_scaled = mean(prediction - y),
    empirical_below_rate = mean(y <= prediction),
    stringsAsFactors = FALSE
  )
}
