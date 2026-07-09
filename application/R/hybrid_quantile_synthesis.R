# Hybrid quantile-synthesis helpers for the GloFAS Q-DESN application.

app_default_hybrid_synthesis_rules <- function() {
  data.frame(
    candidate_id = c(
      "raw_all",
      "qdesn_all",
      "qdesn_center_35_80_raw_tails",
      "qdesn_center_35_65_raw_tails",
      "qdesn_median_only_raw_rest",
      "qdesn_median_65_80_raw_rest",
      "blend50_all",
      "blend25_all",
      "blend75_all",
      "blend_tail_raw_center50"
    ),
    family = c(
      "raw",
      "qdesn",
      "hybrid",
      "hybrid",
      "hybrid",
      "hybrid",
      "blend",
      "blend",
      "blend",
      "blend"
    ),
    qdesn_quantiles = c(
      "",
      "all",
      "0.35;0.50;0.65;0.80",
      "0.35;0.50;0.65",
      "0.50",
      "0.50;0.65;0.80",
      "all",
      "all",
      "all",
      "0.35;0.50;0.65;0.80"
    ),
    qdesn_weight = c(0, 1, 1, 1, 1, 1, 0.50, 0.25, 0.75, 0.50),
    raw_weight = c(1, 0, 0, 0, 0, 0, 0.50, 0.75, 0.25, 0.50),
    description = c(
      "Raw GloFAS quantiles at every target level.",
      "Q-DESN discrepancy-corrected quantiles at every target level.",
      "Q-DESN quantiles for 0.35, 0.50, 0.65, and 0.80; raw GloFAS tails.",
      "Q-DESN quantiles for 0.35, 0.50, and 0.65; raw GloFAS tails.",
      "Q-DESN median only; raw GloFAS for all other quantiles.",
      "Q-DESN quantiles for 0.50, 0.65, and 0.80; raw GloFAS for all other quantiles.",
      "Equal raw/Q-DESN blend at every target level.",
      "Twenty-five percent Q-DESN and seventy-five percent raw GloFAS at every target level.",
      "Seventy-five percent Q-DESN and twenty-five percent raw GloFAS at every target level.",
      "Equal raw/Q-DESN blend for 0.35, 0.50, 0.65, and 0.80; raw GloFAS tails."
    ),
    stringsAsFactors = FALSE
  )
}

app_parse_quantile_set <- function(x, available) {
  x <- trimws(as.character(x %||% ""))
  if (!nzchar(x)) return(numeric())
  if (identical(tolower(x), "all")) return(sort(unique(as.numeric(available))))
  vals <- as.numeric(strsplit(x, ";", fixed = TRUE)[[1L]])
  vals[is.finite(vals)]
}

app_select_model_rows <- function(predictions, model_family) {
  rows <- predictions[predictions$model_family == model_family, , drop = FALSE]
  if (!nrow(rows)) stop(sprintf("No prediction rows found for model family '%s'.", model_family), call. = FALSE)
  rows
}

app_build_hybrid_quantile_candidates <- function(predictions, rules = app_default_hybrid_synthesis_rules()) {
  required <- c(
    "model_id", "model_family", "origin_date", "target_date", "horizon",
    "quantile_level", "qhat", "y_reference"
  )
  app_check_required_columns(predictions, required, "prediction table")
  pred <- predictions
  pred$origin_date <- as.Date(pred$origin_date)
  pred$target_date <- as.Date(pred$target_date)
  pred$horizon <- as.integer(pred$horizon)
  pred$quantile_level <- as.numeric(pred$quantile_level)
  pred$qhat <- as.numeric(pred$qhat)
  pred$y_reference <- as.numeric(pred$y_reference)

  raw <- app_select_model_rows(pred, "raw_glofas")
  qdesn <- app_select_model_rows(pred, "qdesn_glofas_discrepancy")
  key_cols <- c("origin_date", "target_date", "horizon", "quantile_level")
  merged <- merge(
    raw,
    qdesn,
    by = key_cols,
    suffixes = c("_raw", "_qdesn"),
    all = FALSE
  )
  if (!nrow(merged)) stop("Raw and Q-DESN prediction rows have no shared forecast/quantile keys.", call. = FALSE)

  available_q <- sort(unique(merged$quantile_level))
  rows <- vector("list", nrow(rules))
  for (i in seq_len(nrow(rules))) {
    rule <- rules[i, , drop = FALSE]
    qset <- app_parse_quantile_set(rule$qdesn_quantiles[[1L]], available_q)
    use_qdesn <- merged$quantile_level %in% qset
    w_q <- ifelse(use_qdesn, as.numeric(rule$qdesn_weight[[1L]]), 0)
    w_r <- ifelse(use_qdesn, as.numeric(rule$raw_weight[[1L]]), 1)
    total_w <- w_q + w_r
    total_w[total_w == 0] <- 1
    qhat <- (w_q * merged$qhat_qdesn + w_r * merged$qhat_raw) / total_w

    rows[[i]] <- data.frame(
      fit_id = paste0(rule$candidate_id[[1L]], "_synthesized"),
      model_id = rule$candidate_id[[1L]],
      model_family = paste0("hybrid_quantile_synthesis_", rule$family[[1L]]),
      quantile_level = merged$quantile_level,
      qhat = qhat,
      y_reference = merged$y_reference_raw,
      qhat_raw_source = merged$qhat_raw,
      qhat_qdesn_source = merged$qhat_qdesn,
      qdesn_weight = w_q / total_w,
      raw_weight = w_r / total_w,
      rule_family = rule$family[[1L]],
      rule_description = rule$description[[1L]],
      origin_date = merged$origin_date,
      target_date = merged$target_date,
      horizon = merged$horizon,
      stringsAsFactors = FALSE
    )
  }
  out <- do.call(rbind, rows)
  out[order(out$model_id, out$origin_date, out$target_date, out$horizon, out$quantile_level), , drop = FALSE]
}

app_monotone_adjustment_summary <- function(predictions) {
  required <- c("model_id", "quantile_level", "qhat", "qhat_monotone")
  app_check_required_columns(predictions, required, "monotone prediction table")
  predictions$monotone_adjustment <- predictions$qhat_monotone - predictions$qhat
  rows <- lapply(split(predictions, interaction(predictions$model_id, predictions$quantile_level, drop = TRUE)), function(block) {
    data.frame(
      model_id = block$model_id[[1L]],
      quantile_level = as.numeric(block$quantile_level[[1L]]),
      mean_abs_adjustment = mean(abs(block$monotone_adjustment), na.rm = TRUE),
      max_abs_adjustment = max(abs(block$monotone_adjustment), na.rm = TRUE),
      mean_adjustment = mean(block$monotone_adjustment, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out[order(out$model_id, out$quantile_level), , drop = FALSE]
}
