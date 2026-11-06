# Marginal future-response quantiles from equal-weight outer draws and terminal
# whole-ensemble particle weights. No Gaussian Delta or per-draw quantile averaging.

gpmq_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS particle marginal quantiles: ", why), call. = FALSE)
  invisible(TRUE)
}

gpmq_validate_draw <- function(x, H = NULL) {
  q <- gpmq_require
  q(is.list(x) && isTRUE(x$complete) && is.matrix(x$paths) && is.numeric(x$paths) &&
    all(is.finite(x$paths)) && is.numeric(x$weights) &&
    length(x$weights) == nrow(x$paths) && all(is.finite(x$weights)) &&
    all(x$weights >= 0) && sum(x$weights) > 0 &&
    is.data.frame(x$diagnostics) && nrow(x$diagnostics) == ncol(x$paths) &&
    identical(as.integer(x$completed_horizons), as.integer(ncol(x$paths))) &&
    identical(x$no_resampling_between_correction_and_next_member, TRUE),
    "complete full-path particle output with terminal weights required")
  if (!is.null(H)) q(ncol(x$paths) == H, "outer draws must share one horizon")
  invisible(TRUE)
}

gpmq_weighted_inverse_cdf <- function(values, weights, probability) {
  q <- gpmq_require
  q(is.numeric(values) && is.numeric(weights) && length(values) == length(weights) &&
    length(values) > 0L && all(is.finite(values)) && all(is.finite(weights)) &&
    all(weights >= 0) && sum(weights) > 0 && is.numeric(probability) &&
    length(probability) == 1L && is.finite(probability) &&
    probability > 0 && probability < 1, "finite weighted empirical CDF required")
  order <- order(values, seq_along(values)); values <- values[order]
  weights <- weights[order] / sum(weights)
  values[which(cumsum(weights) + 16 * .Machine$double.eps >= probability)[1L]]
}

gpmq_outer_jackknife_mcse <- function(draws, probability, horizon) {
  B <- length(draws)
  if (B < 4L) return(NA_real_)
  estimates <- vapply(seq_len(B), function(drop) {
    kept <- draws[-drop]
    values <- unlist(lapply(kept, function(x) x$paths[, horizon]), use.names = FALSE)
    weights <- unlist(lapply(kept, function(x) x$weights / sum(x$weights) /
      length(kept)), use.names = FALSE)
    gpmq_weighted_inverse_cdf(values, weights, probability)
  }, numeric(1L))
  sqrt((B - 1) / B * sum((estimates - mean(estimates))^2))
}

gpmq_format <- function(draws, probabilities, transform = "log1p") {
  q <- gpmq_require
  q(is.list(draws) && length(draws) >= 1L && is.numeric(probabilities) &&
    length(probabilities) >= 1L && all(is.finite(probabilities)) &&
    all(probabilities > 0 & probabilities < 1) && !anyDuplicated(probabilities) &&
    identical(transform, "log1p"), "outer draws, open probabilities, and log1p scale required")
  H <- ncol(draws[[1L]]$paths)
  for (x in draws) gpmq_validate_draw(x, H)
  B <- length(draws)
  rows <- vector("list", H * length(probabilities)); at <- 0L
  for (h in seq_len(H)) {
    values <- unlist(lapply(draws, function(x) x$paths[, h]), use.names = FALSE)
    weights <- unlist(lapply(draws, function(x) x$weights / sum(x$weights) / B),
      use.names = FALSE)
    for (p in probabilities) {
      at <- at + 1L
      transformed <- gpmq_weighted_inverse_cdf(values, weights, p)
      rows[[at]] <- data.frame(horizon = h, probability = p,
        quantile_transformed = transformed, quantile_original = expm1(transformed),
        outer_cluster_jackknife_mcse_transformed =
          gpmq_outer_jackknife_mcse(draws, p, h),
        outer_draws = B, total_particle_paths = length(values),
        outer_weight_policy = "equal_one_over_B_no_evidence_reweighting",
        particle_weight_policy = "normalized_terminal_H_weights_within_outer_draw",
        estimand = "marginal_future_response_quantile_conditional_on_whole_issued_ensemble",
        stringsAsFactors = FALSE)
    }
  }
  out <- do.call(rbind, rows); rownames(out) <- NULL
  attr(out, "formatter_contract") <- list(
    pooled_CDF = "B^-1 sum_b sum_n W_bn 1(Y_bnh<=y)",
    terminal_weights = TRUE, filtering_h_weights = FALSE,
    evidence_reweighted_outer_draws = FALSE, response_noise_appended = FALSE,
    per_draw_quantiles_averaged = FALSE, gaussian_delta_used = FALSE,
    mcse_unit = "independent_outer_draw_cluster_delete_one_jackknife",
    production_qualified = FALSE)
  out
}
