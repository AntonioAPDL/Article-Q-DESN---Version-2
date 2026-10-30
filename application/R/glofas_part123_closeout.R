# Score-only closeout helpers for the fixed Dec. 25, 2022 GloFAS workflow.

app_glofas_closeout_truth <- function(reference_path, expected_dates) {
  reference <- utils::read.csv(reference_path, stringsAsFactors = FALSE)
  required <- c("date", "streamflow")
  if (!all(required %in% names(reference))) {
    stop("Reference truth must contain date and streamflow columns.", call. = FALSE)
  }
  reference$date <- as.Date(reference$date)
  expected_dates <- as.Date(expected_dates)
  if (anyDuplicated(reference$date)) stop("Reference truth contains duplicate dates.", call. = FALSE)
  idx <- match(expected_dates, reference$date)
  if (anyNA(idx)) stop("Reference truth does not cover the complete forecast window.", call. = FALSE)
  raw <- as.numeric(reference$streamflow[idx])
  if (any(!is.finite(raw)) || any(raw < 0)) stop("Reference truth contains invalid streamflow.", call. = FALSE)
  data.frame(date = expected_dates, observed_usgs = log1p(raw), stringsAsFactors = FALSE)
}

app_glofas_closeout_empirical_crps <- function(observed, draws) {
  observed <- as.numeric(observed)
  draws <- as.matrix(draws)
  if (nrow(draws) != length(observed)) stop("Draw matrix and truth length differ.", call. = FALSE)
  vapply(seq_along(observed), function(ii) {
    x <- sort(as.numeric(draws[ii, ]))
    x <- x[is.finite(x)]
    if (!length(x)) return(NA_real_)
    n <- length(x)
    mean(abs(x - observed[ii])) - sum((2 * seq_len(n) - n - 1) * x) / n^2
  }, numeric(1L))
}

app_glofas_closeout_check_loss <- function(y, q, tau) {
  error <- as.numeric(y) - as.numeric(q)
  ifelse(error >= 0, tau * error, (tau - 1) * error)
}

app_glofas_closeout_quantile_crps <- function(y, qhat, tau) {
  qhat <- as.matrix(qhat)
  tau <- as.numeric(tau)
  ord <- order(tau)
  tau <- tau[ord]
  qhat <- qhat[, ord, drop = FALSE]
  if (length(tau) < 2L) return(rep(NA_real_, length(y)))
  loss <- vapply(seq_along(tau), function(k) {
    app_glofas_closeout_check_loss(y, qhat[, k], tau[k])
  }, numeric(length(y)))
  2 * rowSums(sweep((loss[, -ncol(loss), drop = FALSE] + loss[, -1L, drop = FALSE]) / 2,
    2L, diff(tau), "*"))
}

app_glofas_closeout_assert_forecast <- function(forecast, expected_dates) {
  dates <- as.Date(forecast$origin$future_dates)
  expected_dates <- as.Date(expected_dates)
  if (!identical(dates, expected_dates)) stop("Forecast dates violate the fixed closeout window.", call. = FALSE)
  if (!identical(as.Date(forecast$origin$origin_date), as.Date("2022-12-25"))) {
    stop("Forecast origin is not 2022-12-25.", call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_closeout_score_normal <- function(forecast, truth, model_id) {
  app_glofas_closeout_assert_forecast(forecast, truth$date)
  draws <- as.matrix(forecast$reference_draws)
  if (nrow(draws) != nrow(truth)) stop("Normal forecast draw horizon differs from truth.", call. = FALSE)
  centre <- rowMeans(draws)
  error <- centre - truth$observed_usgs
  crps <- app_glofas_closeout_empirical_crps(truth$observed_usgs, draws)
  data.frame(
    model_id = model_id, target = "usgs_reference", n = nrow(truth),
    mean_crps = mean(crps), mae = mean(abs(error)), rmse = sqrt(mean(error^2)),
    bias = mean(error), coverage_95 = mean(truth$observed_usgs >= apply(draws, 1L, stats::quantile, 0.025) &
      truth$observed_usgs <= apply(draws, 1L, stats::quantile, 0.975)),
    score_role = "post_fit_future_usgs_scoring_only", stringsAsFactors = FALSE
  )
}

app_glofas_closeout_score_quantile <- function(forecast, truth, model_id) {
  app_glofas_closeout_assert_forecast(forecast, truth$date)
  qhat <- as.matrix(forecast$reference)
  tau <- as.numeric(forecast$tau)
  if (nrow(qhat) != nrow(truth) || ncol(qhat) != length(tau)) {
    stop("Quantile forecast dimensions differ from truth or tau.", call. = FALSE)
  }
  rows <- lapply(seq_along(tau), function(k) {
    error <- qhat[, k] - truth$observed_usgs
    data.frame(
      model_id = model_id, target = "usgs_reference", tau = tau[k], n = nrow(truth),
      mean_check_loss = mean(app_glofas_closeout_check_loss(truth$observed_usgs, qhat[, k], tau[k])),
      mae = mean(abs(error)), rmse = sqrt(mean(error^2)), bias = mean(error),
      hit_rate = mean(truth$observed_usgs <= qhat[, k]),
      hit_rate_minus_tau = mean(truth$observed_usgs <= qhat[, k]) - tau[k],
      mean_crps_grid = if (length(tau) > 1L) mean(app_glofas_closeout_quantile_crps(truth$observed_usgs, qhat, tau)) else NA_real_,
      score_role = "post_fit_future_usgs_scoring_only", stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}
