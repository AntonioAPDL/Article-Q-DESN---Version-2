if (!exists("app_repo_root", mode = "function")) {
  args_all <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args_all, value = TRUE)
  repo_root <- if (length(file_arg)) {
    normalizePath(file.path(dirname(sub("^--file=", "", file_arg[[1L]])), "..", ".."), mustWork = TRUE)
  } else {
    normalizePath(".", mustWork = TRUE)
  }
  source(file.path(repo_root, "application/R/00_packages.R"))
  app_set_repo_root(repo_root)
}
if (!exists("app_prepare_glofas_cutoff_context", mode = "function")) {
  source(app_path("application/R/glofas_context_figures.R"))
}

local({
  cutoff <- as.Date("2022-01-05")
  history_dates <- cutoff - 4:0
  forecast_dates <- cutoff + 1:2
  tau <- c(0.05, 0.15, 0.35, 0.50, 0.65, 0.80, 0.95)
  make_grid <- function(dates, levels) {
    expand.grid(target_date = dates, quantile_level = levels, KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  }

  q_forecast <- make_grid(forecast_dates, tau)
  q_forecast$model_family <- "qdesn_glofas_discrepancy"
  q_forecast$origin_date <- cutoff
  q_forecast$qhat <- rep(seq(0.2, 0.8, length.out = length(tau)), each = length(forecast_dates))
  q_forecast$qhat_monotone <- q_forecast$qhat
  raw <- make_grid(forecast_dates, tau)
  raw$model_family <- "raw_glofas"
  raw$origin_date <- cutoff
  raw$qhat <- rep(c(log1p(1), log1p(1.5), log1p(1.8), log1p(2), log1p(2.2), log1p(2.5), log1p(3)), each = length(forecast_dates))
  raw$qhat_monotone <- raw$qhat
  predictions <- rbind(q_forecast[, names(raw)], raw)

  history <- make_grid(history_dates, tau)
  history$candidate_id <- "toy"
  history$cutoff_date <- cutoff
  history$y_log1p <- rep(log1p(1:5), times = length(tau))
  history$qhat_isotonic <- history$y_log1p + rep(seq(-0.15, 0.15, length.out = length(tau)), each = length(history_dates))

  reference <- data.frame(
    date = c(history_dates, forecast_dates),
    streamflow = c(1:5, 6:7),
    stringsAsFactors = FALSE
  )
  retrospective <- data.frame(date = history_dates, glofas_streamflow = 0:4, stringsAsFactors = FALSE)
  ensemble <- expand.grid(
    target_date = forecast_dates,
    member = c("m1", "m2", "m3"),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  ensemble$origin_date <- cutoff
  ensemble$horizon <- as.integer(ensemble$target_date - cutoff)
  ensemble$glofas_streamflow <- rep(c(1, 2, 3), each = length(forecast_dates))

  context <- app_prepare_glofas_cutoff_context(
    predictions,
    history,
    reference,
    retrospective,
    ensemble,
    history_observations = 5L,
    expected_members = 3L,
    candidate_id = "toy"
  )
  stopifnot(all(context$audit$passed))
  stopifnot(nrow(context$quantile_paths) == (5L + 2L) * length(tau))
  stopifnot(nrow(context$observed_history_source) == 5L * length(tau))
  stopifnot(nrow(context$ensemble) == 2L * 3L)
  stopifnot(all(context$ensemble_summary$n_members == 3L))
  stopifnot(all(c("q05", "q50", "q95") %in% names(context$bands)))
  stopifnot(max(abs(context$ensemble_summary$median - log1p(2))) < 1e-12)

  incomplete <- ensemble[-1L, , drop = FALSE]
  failed <- tryCatch({
    app_prepare_glofas_cutoff_context(
      predictions,
      history,
      reference,
      retrospective,
      incomplete,
      history_observations = 5L,
      expected_members = 3L,
      candidate_id = "toy"
    )
    FALSE
  }, error = function(e) grepl("incomplete", conditionMessage(e), fixed = TRUE))
  stopifnot(failed)
})
