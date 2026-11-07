# Deterministic reconciliation of committed August and November GloFAS
# forecast evidence. This reader uses only small article CSVs.

gar_stop <- function(message) stop(paste0("GloFAS authority reconciliation: ",
  message), call. = FALSE)

gar_hash_file <- function(path) {
  if (!requireNamespace("digest", quietly = TRUE)) gar_stop("digest is required")
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

gar_require_columns <- function(x, columns, role) {
  missing <- setdiff(columns, names(x))
  if (length(missing)) gar_stop(paste(role, "lacks", paste(missing, collapse = ", ")))
  invisible(TRUE)
}

gar_trapezoid_weights <- function(probability) {
  probability <- sort(unique(as.numeric(probability)))
  if (length(probability) < 2L || any(!is.finite(probability)) ||
      any(probability <= 0 | probability >= 1)) gar_stop("invalid probability grid")
  gaps <- diff(probability)
  c(gaps[1L] / 2, (gaps[-length(gaps)] + gaps[-1L]) / 2,
    gaps[length(gaps)] / 2)
}

gar_check_loss <- function(observed, quantile, probability) {
  (probability - (observed < quantile)) * (observed - quantile)
}

gar_score <- function(rows, truth = "observed", estimate = "estimate") {
  gar_require_columns(rows, c("date", "probability", truth, estimate), "score rows")
  probabilities <- sort(unique(rows$probability))
  weights <- gar_trapezoid_weights(probabilities)
  dates <- sort(unique(rows$date))
  by_date <- lapply(dates, function(date) {
    block <- rows[rows$date == date, , drop = FALSE]
    block <- block[order(block$probability), , drop = FALSE]
    if (!identical(as.numeric(block$probability), probabilities) ||
        length(unique(block[[truth]])) != 1L) gar_stop("score grid is not rectangular")
    data.frame(date = date, score = 2 * sum(weights * gar_check_loss(
      block[[truth]], block[[estimate]], block$probability)))
  })
  by_date <- do.call(rbind, by_date)
  list(mean = mean(by_date$score), by_date = by_date,
    probabilities = probabilities, weights = weights)
}

gar_crossings <- function(rows, estimate = "estimate", tolerance = 1e-10) {
  gar_require_columns(rows, c("date", "probability", estimate), "crossing rows")
  dates <- sort(unique(rows$date))
  by_date <- lapply(dates, function(date) {
    block <- rows[rows$date == date, , drop = FALSE]
    block <- block[order(block$probability), , drop = FALSE]
    delta <- diff(block[[estimate]])
    data.frame(date = date, comparisons = length(delta),
      crossing_pairs = sum(delta < -tolerance),
      maximum_crossing = max(c(0, -delta)))
  })
  by_date <- do.call(rbind, by_date)
  list(pairs = sum(by_date$crossing_pairs), dates = sum(by_date$crossing_pairs > 0),
    comparisons = sum(by_date$comparisons), maximum = max(by_date$maximum_crossing),
    by_date = by_date)
}

gar_reconcile <- function(root = ".") {
  table_root <- file.path(root, "tables")
  paths <- c(
    previous_raw = file.path(table_root,
      "glofas_application_prediction_quantiles_independent__glofas_fr09_authoritative_full7_20260811.csv"),
    previous_monotone = file.path(table_root,
      "glofas_application_prediction_quantiles_monotone__glofas_fr09_authoritative_full7_20260811.csv"),
    current_paths = file.path(table_root, "glofas_same_family_20261103_quantile_paths.csv"),
    current_observations = file.path(table_root, "glofas_same_family_20261103_observations.csv"),
    current_fitted_history = file.path(table_root, "glofas_same_family_20261103_fitted_history.csv"),
    current_history = file.path(table_root, "glofas_same_family_20261103_history.csv"))
  if (any(!file.exists(paths))) gar_stop("one or more committed authority inputs are missing")
  previous <- utils::read.csv(paths[["previous_raw"]], stringsAsFactors = FALSE,
    check.names = FALSE)
  monotone <- utils::read.csv(paths[["previous_monotone"]], stringsAsFactors = FALSE,
    check.names = FALSE)
  current <- utils::read.csv(paths[["current_paths"]], stringsAsFactors = FALSE,
    check.names = FALSE)
  observations <- utils::read.csv(paths[["current_observations"]],
    stringsAsFactors = FALSE, check.names = FALSE)
  fitted <- utils::read.csv(paths[["current_fitted_history"]],
    stringsAsFactors = FALSE, check.names = FALSE)
  history <- utils::read.csv(paths[["current_history"]], stringsAsFactors = FALSE,
    check.names = FALSE)
  gar_require_columns(previous, c("model_family", "quantile_level", "qhat",
    "y_reference", "target_date"), "previous paths")
  gar_require_columns(current, c("family", "tau", "quantile_transformed",
    "target_date"), "current paths")
  gar_require_columns(observations, c("target_date", "y_transformed"),
    "current observations")
  old <- previous[previous$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  old_mono <- monotone[monotone$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  new <- current[current$family == "Independent AL", , drop = FALSE]
  common <- sort(intersect(unique(old$quantile_level), unique(new$tau)))
  if (!identical(common, c(.05, .35, .5, .65, .8, .95))) {
    gar_stop("unexpected previous/current common probability grid")
  }
  prepare_old <- function(x, estimate_column = "qhat") {
    gar_require_columns(x, estimate_column, "previous paths")
    data.frame(date = as.character(x$target_date),
      probability = x$quantile_level, observed = x$y_reference,
      estimate = x[[estimate_column]])
  }
  prepare_new <- function(x) {
    merged <- merge(x, observations, by = "target_date", all.x = TRUE, sort = FALSE)
    if (anyNA(merged$y_transformed)) gar_stop("current observations do not cover paths")
    data.frame(date = as.character(merged$target_date), probability = merged$tau,
      observed = merged$y_transformed, estimate = merged$quantile_transformed)
  }
  old <- prepare_old(old[old$quantile_level %in% common, , drop = FALSE])
  old_mono <- prepare_old(old_mono[old_mono$quantile_level %in% common, , drop = FALSE],
    estimate_column = "qhat_monotone")
  new <- prepare_new(new[new$tau %in% common, , drop = FALSE])
  forecast <- list(previous_raw = list(score = gar_score(old), crossings = gar_crossings(old)),
    previous_monotone = list(score = gar_score(old_mono), crossings = gar_crossings(old_mono)),
    current_independent_al = list(score = gar_score(new), crossings = gar_crossings(new)))
  gar_require_columns(fitted, c("family", "target_date", "tau", "quantile_transformed"),
    "fitted history")
  gar_require_columns(history, c("target_date", "y_transformed"), "history")
  historical <- lapply(split(fitted, fitted$family), function(block) {
    merged <- merge(block, history, by = "target_date", all.x = TRUE, sort = FALSE)
    rows <- data.frame(date = as.character(merged$target_date), probability = merged$tau,
      observed = merged$y_transformed, estimate = merged$quantile_transformed)
    list(score = gar_score(rows), crossings = gar_crossings(rows))
  })
  summary <- rbind(
    data.frame(authority = "previous_raw_common_grid",
      acrps = forecast$previous_raw$score$mean,
      crossing_pairs = forecast$previous_raw$crossings$pairs,
      crossing_dates = forecast$previous_raw$crossings$dates,
      maximum_crossing = forecast$previous_raw$crossings$maximum),
    data.frame(authority = "previous_monotone_common_grid",
      acrps = forecast$previous_monotone$score$mean,
      crossing_pairs = forecast$previous_monotone$crossings$pairs,
      crossing_dates = forecast$previous_monotone$crossings$dates,
      maximum_crossing = forecast$previous_monotone$crossings$maximum),
    data.frame(authority = "current_independent_al_common_grid",
      acrps = forecast$current_independent_al$score$mean,
      crossing_pairs = forecast$current_independent_al$crossings$pairs,
      crossing_dates = forecast$current_independent_al$crossings$dates,
      maximum_crossing = forecast$current_independent_al$crossings$maximum))
  list(schema_version = "glofas_authority_reconciliation_v1",
    input_sha256 = vapply(paths, gar_hash_file, character(1L)),
    common_probabilities = common, forecast = forecast, historical = historical,
    summary = summary, future_truth_role = "postfit_descriptive_scoring_only",
    model_selection_performed = FALSE, files_written = 0L)
}

