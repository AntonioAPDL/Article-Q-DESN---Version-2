#!/usr/bin/env Rscript
# Purpose: no-refit audit of GloFAS multi-quantile synthesis and readout blocks.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/make_manuscript_outputs.R"))

args <- app_parse_args(list(
  config = "local_trackers/runtime_configs/glofas_multiquantile_dec25_20260603/synthesis_config.yaml",
  source_manifest = "local_trackers/runtime_configs/glofas_multiquantile_dec25_20260603/synthesis_source_manifest.csv",
  synthesis_run_id = "glofas_multiquantile_dec25_20260603_synthesis_final",
  run_id = "glofas_multiquantile_dec25_20260603_synthesis_readout_audit",
  draw_stride = 1,
  draw_max = 2000,
  write_full_draw_stress = "false"
))

cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id)
app_stage_start("16_audit_glofas_synthesis_and_readout_blocks", run_dirs)
app_write_yaml(cfg, file.path(run_dirs$manifest, "run_config.yaml"))
app_write_json(cfg, file.path(run_dirs$manifest, "run_config.json"))
app_write_git_state(file.path(run_dirs$manifest, "git_state.txt"))
app_write_session_info(file.path(run_dirs$manifest, "session_info.txt"))

generated_dir <- app_path("application/outputs/generated", args$run_id)
figure_dir <- file.path(generated_dir, "figures")
app_ensure_dir(generated_dir)
app_ensure_dir(figure_dir)

as_flag <- function(x) {
  tolower(as.character(x)[[1L]]) %in% c("true", "t", "yes", "y", "1")
}

safe_sd <- function(x) {
  s <- stats::sd(as.numeric(x), na.rm = TRUE)
  if (!is.finite(s) || s < 1.0e-10) 1.0 else s
}

artifact_path <- function(run_dir, fit_id, suffix = "") {
  file.path(app_path(run_dir), "objects", paste0(fit_id, suffix, ".rds"))
}

theta_parts <- function(fit, design) {
  theta <- as.numeric(fit$variational_state$theta_mean)
  beta_index <- design$beta_index %||% seq_len(ncol(design$X_beta))
  alpha_index <- design$alpha_index %||% (ncol(design$X_beta) + seq_len(ncol(design$X_alpha)))
  list(beta = theta[beta_index], alpha = theta[alpha_index])
}

feature_blocks <- function(feature_info) {
  block <- as.character(feature_info$block)
  block[!nzchar(block) | is.na(block)] <- "unknown"
  unique(block)
}

block_shift_rows <- function(X_hist, X_future, feature_info, quantile_id, quantile_level, design_block) {
  X_hist <- as.matrix(X_hist)
  X_future <- as.matrix(X_future)
  rows <- list()
  for (block in feature_blocks(feature_info)) {
    idx <- which(as.character(feature_info$block) == block)
    if (!length(idx)) next
    H <- X_hist[, idx, drop = FALSE]
    F <- X_future[, idx, drop = FALSE]
    mu <- colMeans(H, na.rm = TRUE)
    sig <- apply(H, 2L, safe_sd)
    lo <- apply(H, 2L, min, na.rm = TRUE)
    hi <- apply(H, 2L, max, na.rm = TRUE)
    Z <- sweep(sweep(F, 2L, mu, "-"), 2L, sig, "/")
    outside <- sweep(F, 2L, lo, "<") | sweep(F, 2L, hi, ">")
    rows[[length(rows) + 1L]] <- data.frame(
      quantile_id = quantile_id,
      quantile_level = quantile_level,
      design_block = design_block,
      feature_block = block,
      horizon = seq_len(nrow(F)),
      n_features = ncol(F),
      max_abs_z = apply(abs(Z), 1L, max, na.rm = TRUE),
      mean_abs_z = rowMeans(abs(Z), na.rm = TRUE),
      n_abs_z_gt_3 = rowSums(abs(Z) > 3, na.rm = TRUE),
      n_abs_z_gt_5 = rowSums(abs(Z) > 5, na.rm = TRUE),
      frac_outside_history_range = rowMeans(outside, na.rm = TRUE),
      future_row_norm = sqrt(rowSums(F^2, na.rm = TRUE)),
      history_row_norm_median = stats::median(sqrt(rowSums(H^2, na.rm = TRUE)), na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }
  if (!length(rows)) data.frame() else do.call(rbind, rows)
}

zero_blocks <- function(X, feature_info, drop_blocks) {
  X <- as.matrix(X)
  idx <- which(as.character(feature_info$block) %in% drop_blocks)
  if (length(idx)) X[, idx] <- 0
  X
}

predict_components <- function(X_beta, X_alpha, beta, alpha) {
  q_y <- as.numeric(as.matrix(X_beta) %*% as.numeric(beta))
  d_g <- as.numeric(as.matrix(X_alpha) %*% as.numeric(alpha))
  data.frame(q_y = q_y, d_g = d_g, q_g = q_y + d_g)
}

interval_width <- function(block, lo, hi, value_col) {
  qlo <- block[[value_col]][match(lo, block$quantile_level)]
  qhi <- block[[value_col]][match(hi, block$quantile_level)]
  if (!is.finite(qlo) || !is.finite(qhi)) NA_real_ else qhi - qlo
}

summarize_widths <- function(pred, value_col, label) {
  keys <- unique(pred[, c("model_id", "origin_date", "target_date", "horizon"), drop = FALSE])
  rows <- vector("list", nrow(keys))
  for (i in seq_len(nrow(keys))) {
    idx <- pred$model_id == keys$model_id[[i]] &
      pred$origin_date == keys$origin_date[[i]] &
      pred$target_date == keys$target_date[[i]] &
      pred$horizon == keys$horizon[[i]]
    block <- pred[idx, , drop = FALSE]
    block <- block[order(block$quantile_level), , drop = FALSE]
    rows[[i]] <- cbind(
      keys[i, , drop = FALSE],
      data.frame(
        value_col = label,
        width_90 = interval_width(block, 0.05, 0.95, value_col),
        width_65 = interval_width(block, 0.15, 0.80, value_col),
        width_30 = interval_width(block, 0.35, 0.65, value_col),
        stringsAsFactors = FALSE
      )
    )
  }
  do.call(rbind, rows)
}

make_ablation_predictions <- function(fit, design, source_row) {
  lin <- fit$variational_state$future_linearization
  if (is.null(lin$X_beta_future) || is.null(lin$X_alpha_future)) return(data.frame())
  parts <- theta_parts(fit, design)
  future_key <- design$future_key %||% design$latent_data$future_key
  if (is.null(future_key)) {
    future_key <- data.frame(
      origin_date = NA,
      target_date = NA,
      horizon = seq_len(nrow(lin$X_beta_future)),
      stringsAsFactors = FALSE
    )
  }
  n_future <- nrow(lin$X_beta_future)
  reference_path <- file.path(app_path(source_row$run_dir), "tables", "prediction_quantiles.csv")
  reference_table <- if (file.exists(reference_path)) {
    read.csv(reference_path, stringsAsFactors = FALSE)
  } else {
    data.frame()
  }
  if (nrow(reference_table) && "horizon" %in% names(reference_table)) {
    reference_table <- reference_table[order(reference_table$horizon), , drop = FALSE]
  }
  origin_default <- if (nrow(reference_table) && "origin_date" %in% names(reference_table)) {
    as.character(reference_table$origin_date)
  } else {
    NA_character_
  }
  target_default <- if (nrow(reference_table) && "target_date" %in% names(reference_table)) {
    as.character(reference_table$target_date)
  } else {
    NA_character_
  }
  horizon_default <- if (nrow(reference_table) && "horizon" %in% names(reference_table)) {
    as.integer(reference_table$horizon)
  } else {
    seq_len(n_future)
  }
  get_future_col <- function(name, default) {
    if (name %in% names(future_key)) {
      x <- future_key[[name]]
    } else {
      x <- default
    }
    if (length(x) == 0L) x <- default
    if (length(x) == 1L) x <- rep(x, n_future)
    x
  }
  y_ref <- design$y_future_oracle %||% future_key$y_reference %||% reference_table$y_reference %||% NA_real_
  if (length(y_ref) == 1L) y_ref <- rep(y_ref, nrow(lin$X_beta_future))
  scenarios <- list(
    full = list(beta_drop = character(), alpha_drop = character()),
    reservoir_only = list(beta_drop = c("direct_output_lag", "direct_covariate_lag"), alpha_drop = c("direct_output_lag", "direct_covariate_lag")),
    no_direct_output_lags = list(beta_drop = "direct_output_lag", alpha_drop = "direct_output_lag"),
    no_direct_covariate_lags = list(beta_drop = "direct_covariate_lag", alpha_drop = "direct_covariate_lag"),
    no_direct_input_block = list(beta_drop = c("direct_output_lag", "direct_covariate_lag"), alpha_drop = c("direct_output_lag", "direct_covariate_lag")),
    beta_no_direct_input_block = list(beta_drop = c("direct_output_lag", "direct_covariate_lag"), alpha_drop = character()),
    alpha_no_direct_input_block = list(beta_drop = character(), alpha_drop = c("direct_output_lag", "direct_covariate_lag"))
  )
  rows <- list()
  for (name in names(scenarios)) {
    sc <- scenarios[[name]]
    Xb <- zero_blocks(lin$X_beta_future, design$feature_info_beta, sc$beta_drop)
    Xa <- zero_blocks(lin$X_alpha_future, design$feature_info_alpha, sc$alpha_drop)
    comp <- predict_components(Xb, Xa, parts$beta, parts$alpha)
    rows[[length(rows) + 1L]] <- data.frame(
      model_id = paste0("diagnostic_", name),
      diagnostic_scenario = name,
      source_run_id = source_row$run_id,
      source_quantile_id = source_row$quantile_id,
      fit_id = source_row$qdesn_fit_id,
      quantile_level = as.numeric(source_row$quantile_level),
      origin_date = as.character(get_future_col("origin_date", origin_default)),
      target_date = as.character(get_future_col("target_date", target_default)),
      horizon = as.integer(get_future_col("horizon", horizon_default)),
      qhat = comp$q_y,
      q_g = comp$q_g,
      d_g = comp$d_g,
      y_reference = as.numeric(y_ref),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

draw_level_synthesis <- function(draws) {
  req <- c("draw_index", "model_id", "origin_date", "target_date", "horizon", "quantile_level", "q_y_draw", "y_reference")
  app_check_required_columns(draws, req, "posterior draw prediction table")
  pava <- function(y) {
    level <- as.numeric(y)
    weight <- rep(1.0, length(level))
    block_start <- seq_along(level)
    block_end <- seq_along(level)
    k <- 1L
    while (k < length(level)) {
      if (level[k] <= level[k + 1L] + 1.0e-14) {
        k <- k + 1L
        next
      }
      pooled_weight <- weight[k] + weight[k + 1L]
      pooled_level <- (weight[k] * level[k] + weight[k + 1L] * level[k + 1L]) / pooled_weight
      level[k] <- pooled_level
      weight[k] <- pooled_weight
      block_end[k] <- block_end[k + 1L]
      level <- level[-(k + 1L)]
      weight <- weight[-(k + 1L)]
      block_start <- block_start[-(k + 1L)]
      block_end <- block_end[-(k + 1L)]
      if (k > 1L) k <- k - 1L
    }
    out <- numeric(length(y))
    for (j in seq_along(level)) out[block_start[j]:block_end[j]] <- level[j]
    out
  }
  draws <- draws[order(
    draws$draw_index,
    draws$model_id,
    draws$origin_date,
    draws$target_date,
    draws$horizon,
    draws$quantile_level
  ), , drop = FALSE]
  q_levels <- sort(unique(as.numeric(draws$quantile_level)))
  n_q <- length(q_levels)
  if (!n_q || nrow(draws) %% n_q != 0L) {
    stop("Posterior draw synthesis stress requires a complete draw x horizon x quantile grid.", call. = FALSE)
  }
  group_keys <- draws[seq(1L, nrow(draws), by = n_q), c("draw_index", "model_id", "origin_date", "target_date", "horizon", "y_reference"), drop = FALSE]
  q_raw <- matrix(as.numeric(draws$q_y_draw), ncol = n_q, byrow = TRUE)
  q_mono <- t(apply(q_raw, 1L, pava))
  gaps <- t(apply(q_raw, 1L, diff))
  gaps_mono <- t(apply(q_mono, 1L, diff))
  draws$q_y_draw_monotone <- as.numeric(t(q_mono))
  draws$abs_isotonic_adjustment <- abs(draws$q_y_draw_monotone - as.numeric(draws$q_y_draw))
  per_group_cross <- rowSums(gaps < -1.0e-10, na.rm = TRUE)
  per_group_max_cross <- apply(pmax(-gaps, 0), 1L, max, na.rm = TRUE)
  per_group_zero <- rowSums(abs(gaps_mono) < 1.0e-10, na.rm = TRUE)
  draws$n_crossing_pairs_draw <- rep(per_group_cross, each = n_q)
  draws$max_crossing_magnitude_draw <- rep(per_group_max_cross, each = n_q)
  draws$n_zero_monotone_gaps_draw <- rep(per_group_zero, each = n_q)
  attr(draws, "group_keys") <- group_keys
  attr(draws, "q_levels") <- q_levels
  attr(draws, "q_raw") <- q_raw
  attr(draws, "q_mono") <- q_mono
  draws
}

source_manifest <- read.csv(app_path(args$source_manifest), stringsAsFactors = FALSE)
source_manifest <- source_manifest[source_manifest$enabled & source_manifest$required, , drop = FALSE]
shift_rows <- list()
ablation_rows <- list()
availability_rows <- list()

for (i in seq_len(nrow(source_manifest))) {
  row <- source_manifest[i, , drop = FALSE]
  fit_path <- artifact_path(row$run_dir, row$qdesn_fit_id)
  design_path <- artifact_path(row$run_dir, row$qdesn_fit_id, "__design")
  has_objects <- file.exists(fit_path) && file.exists(design_path)
  availability_rows[[i]] <- data.frame(
    run_id = row$run_id,
    quantile_id = row$quantile_id,
    quantile_level = as.numeric(row$quantile_level),
    fit_path = app_prefer_repo_relative_path(fit_path),
    design_path = app_prefer_repo_relative_path(design_path),
    has_fit_object = file.exists(fit_path),
    has_design_object = file.exists(design_path),
    block_audit_available = has_objects,
    stringsAsFactors = FALSE
  )
  if (!has_objects) next
  fit <- readRDS(fit_path)
  design <- readRDS(design_path)
  lin <- fit$variational_state$future_linearization
  if (!is.null(lin$X_beta_future)) {
    shift_rows[[length(shift_rows) + 1L]] <- block_shift_rows(design$X_beta, lin$X_beta_future, design$feature_info_beta, row$quantile_id, as.numeric(row$quantile_level), "beta_readout")
  }
  if (!is.null(lin$X_alpha_future)) {
    shift_rows[[length(shift_rows) + 1L]] <- block_shift_rows(design$X_alpha, lin$X_alpha_future, design$feature_info_alpha, row$quantile_id, as.numeric(row$quantile_level), "alpha_readout")
  }
  ablation_rows[[length(ablation_rows) + 1L]] <- make_ablation_predictions(fit, design, row)
}

availability <- do.call(rbind, availability_rows)
app_write_csv(availability, file.path(run_dirs$tables, "fit_object_availability.csv"))

if (length(shift_rows)) {
  shift_by_horizon <- do.call(rbind, shift_rows)
  shift_summary <- aggregate(
    cbind(max_abs_z, mean_abs_z, n_abs_z_gt_3, n_abs_z_gt_5, frac_outside_history_range) ~ design_block + feature_block,
    shift_by_horizon,
    function(x) c(mean = mean(x, na.rm = TRUE), max = max(x, na.rm = TRUE))
  )
  shift_summary <- do.call(data.frame, shift_summary)
  names(shift_summary) <- gsub("\\.", "_", names(shift_summary))
  app_write_csv(shift_by_horizon, file.path(run_dirs$tables, "readout_feature_block_shift_by_horizon.csv"))
  app_write_csv(shift_summary, file.path(run_dirs$tables, "readout_feature_block_shift_summary.csv"))
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    p <- ggplot2::ggplot(shift_by_horizon, ggplot2::aes(x = horizon, y = max_abs_z, color = feature_block)) +
      ggplot2::geom_line(linewidth = 0.7) +
      ggplot2::facet_grid(design_block ~ quantile_id) +
      ggplot2::geom_hline(yintercept = 3, linetype = 2, color = "gray55") +
      ggplot2::geom_hline(yintercept = 5, linetype = 2, color = "gray35") +
      ggplot2::labs(x = "Forecast horizon", y = "Maximum absolute z-score", color = "Feature block", title = "Forecast design shift by readout block") +
      ggplot2::theme_bw(base_size = 9) +
      ggplot2::theme(legend.position = "bottom")
    ggplot2::ggsave(file.path(figure_dir, "glofas_readout_block_feature_shift.pdf"), p, width = 12, height = 6)
  }
}

if (length(ablation_rows)) {
  ablation_pred <- do.call(rbind, ablation_rows)
  ablation_synth <- app_synthesize_quantile_grid(ablation_pred)
  ablation_scored <- app_score_quantile_predictions_dual(ablation_synth, cfg)
  ablation_intervals <- app_score_intervals(ablation_scored, cfg)
  ablation_crps <- app_score_crps_grid(ablation_scored)
  ablation_scores <- app_score_summary(ablation_scored, ablation_intervals, ablation_crps)
  ablation_cross <- app_quantile_crossing_summary(app_quantile_crossing_diagnostics(ablation_pred, "qhat", "independent_theta_mean"))
  ablation_width_raw <- summarize_widths(ablation_pred, "qhat", "independent")
  ablation_width_mono <- summarize_widths(ablation_synth, "qhat_monotone", "monotone")
  app_write_csv(ablation_pred, file.path(run_dirs$tables, "readout_block_ablation_predictions.csv"))
  app_write_csv(ablation_synth, file.path(run_dirs$tables, "readout_block_ablation_predictions_synthesized.csv"))
  app_write_csv(ablation_scored, file.path(run_dirs$tables, "readout_block_ablation_score_by_quantile.csv"))
  app_write_csv(ablation_intervals, file.path(run_dirs$tables, "readout_block_ablation_score_by_interval.csv"))
  app_write_csv(ablation_crps, file.path(run_dirs$tables, "readout_block_ablation_score_by_crps.csv"))
  app_write_csv(ablation_scores, file.path(run_dirs$tables, "readout_block_ablation_score_summary.csv"))
  app_write_csv(ablation_cross, file.path(run_dirs$tables, "readout_block_ablation_crossing_summary.csv"))
  app_write_csv(ablation_width_raw, file.path(run_dirs$tables, "readout_block_ablation_width_independent.csv"))
  app_write_csv(ablation_width_mono, file.path(run_dirs$tables, "readout_block_ablation_width_monotone.csv"))
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    p_score <- ggplot2::ggplot(ablation_scores, ggplot2::aes(x = reorder(model_id, crps_quantile_grid_mean), y = crps_quantile_grid_mean)) +
      ggplot2::geom_col(fill = "#4C78A8", width = 0.7) +
      ggplot2::coord_flip() +
      ggplot2::labs(x = "Diagnostic ablation", y = "Mean CRPS grid", title = "No-refit readout-block ablation scores") +
      ggplot2::theme_bw(base_size = 9)
    ggplot2::ggsave(file.path(figure_dir, "glofas_readout_block_ablation_scores.pdf"), p_score, width = 7, height = 4.5)
    p_width <- ggplot2::ggplot(ablation_width_mono, ggplot2::aes(x = horizon, y = width_30, color = model_id)) +
      ggplot2::geom_line(linewidth = 0.7) +
      ggplot2::labs(x = "Forecast horizon", y = "Monotone 30% interval width", color = "Diagnostic ablation") +
      ggplot2::theme_bw(base_size = 9) +
      ggplot2::theme(legend.position = "bottom")
    ggplot2::ggsave(file.path(figure_dir, "glofas_readout_block_ablation_widths.pdf"), p_width, width = 9, height = 4.5)
  }
}

draw_path <- file.path(app_path("application/runs", args$synthesis_run_id), "tables", "posterior_draw_predictions.csv")
draw_stress_written <- FALSE
if (file.exists(draw_path)) {
  draws <- read.csv(draw_path, stringsAsFactors = FALSE)
  draws <- draws[draws$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  draw_ids <- sort(unique(as.integer(draws$draw_index)))
  if (as.integer(args$draw_stride) > 1L) draw_ids <- draw_ids[seq(1L, length(draw_ids), by = as.integer(args$draw_stride))]
  draw_ids <- head(draw_ids, as.integer(args$draw_max))
  draws <- draws[as.integer(draws$draw_index) %in% draw_ids, , drop = FALSE]
  draw_synth <- draw_level_synthesis(draws)
  draw_group_keys <- attr(draw_synth, "group_keys")
  draw_q_levels <- attr(draw_synth, "q_levels")
  draw_q_raw <- attr(draw_synth, "q_raw")
  draw_q_mono <- attr(draw_synth, "q_mono")
  draw_pred <- data.frame(
    model_id = draw_synth$model_id,
    origin_date = draw_synth$origin_date,
    target_date = draw_synth$target_date,
    horizon = draw_synth$horizon,
    draw_index = draw_synth$draw_index,
    quantile_level = draw_synth$quantile_level,
    qhat = draw_synth$q_y_draw,
    qhat_monotone = draw_synth$q_y_draw_monotone,
    y_reference = draw_synth$y_reference,
    stringsAsFactors = FALSE
  )
  draw_pred$check_loss_independent <- app_check_loss(draw_pred$y_reference, draw_pred$qhat, draw_pred$quantile_level)
  draw_pred$check_loss_monotone <- app_check_loss(draw_pred$y_reference, draw_pred$qhat_monotone, draw_pred$quantile_level)
  draw_summary <- aggregate(
    cbind(n_crossing_pairs_draw, max_crossing_magnitude_draw, n_zero_monotone_gaps_draw, abs_isotonic_adjustment) ~ horizon,
    draw_synth,
    mean,
    na.rm = TRUE
  )
  width_matrix <- function(Q, lo, hi) {
    Q[, match(hi, draw_q_levels)] - Q[, match(lo, draw_q_levels)]
  }
  draw_width_raw <- data.frame(
    horizon = draw_group_keys$horizon,
    value_col = "draw_independent",
    width_90 = width_matrix(draw_q_raw, 0.05, 0.95),
    width_65 = width_matrix(draw_q_raw, 0.15, 0.80),
    width_30 = width_matrix(draw_q_raw, 0.35, 0.65),
    stringsAsFactors = FALSE
  )
  draw_width_mono <- data.frame(
    horizon = draw_group_keys$horizon,
    value_col = "draw_monotone",
    width_90 = width_matrix(draw_q_mono, 0.05, 0.95),
    width_65 = width_matrix(draw_q_mono, 0.15, 0.80),
    width_30 = width_matrix(draw_q_mono, 0.35, 0.65),
    stringsAsFactors = FALSE
  )
  draw_width_summary <- aggregate(
    cbind(width_90, width_65, width_30) ~ horizon + value_col,
    rbind(draw_width_raw, draw_width_mono),
    function(x) c(mean = mean(x, na.rm = TRUE), median = stats::median(x, na.rm = TRUE), min = min(x, na.rm = TRUE))
  )
  draw_width_summary <- do.call(data.frame, draw_width_summary)
  names(draw_width_summary) <- gsub("\\.", "_", names(draw_width_summary))
  if (as_flag(args$write_full_draw_stress)) {
    app_write_csv(draw_synth, file.path(run_dirs$tables, "posterior_draw_synthesis_stress_predictions.csv"))
    app_write_csv(draw_pred, file.path(run_dirs$tables, "posterior_draw_synthesis_stress_scores.csv"))
  }
  app_write_csv(draw_summary, file.path(run_dirs$tables, "posterior_draw_synthesis_stress_by_horizon.csv"))
  app_write_csv(draw_width_summary, file.path(run_dirs$tables, "posterior_draw_synthesis_stress_width_summary.csv"))
  draw_stress_written <- TRUE
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    p_cross <- ggplot2::ggplot(draw_summary, ggplot2::aes(x = horizon, y = n_crossing_pairs_draw)) +
      ggplot2::geom_line(color = "#B279A2", linewidth = 0.8) +
      ggplot2::labs(x = "Forecast horizon", y = "Mean crossing pairs per draw", title = "Draw-level quantile crossing stress") +
      ggplot2::theme_bw(base_size = 9)
    ggplot2::ggsave(file.path(figure_dir, "glofas_draw_level_synthesis_crossings.pdf"), p_cross, width = 7, height = 4)
    p_width <- ggplot2::ggplot(draw_width_summary, ggplot2::aes(x = horizon, y = width_30_median, color = value_col)) +
      ggplot2::geom_line(linewidth = 0.8) +
      ggplot2::labs(x = "Forecast horizon", y = "Median 30% width across draw-index alignments", color = "Draw synthesis") +
      ggplot2::theme_bw(base_size = 9) +
      ggplot2::theme(legend.position = "bottom")
    ggplot2::ggsave(file.path(figure_dir, "glofas_draw_level_synthesis_widths.pdf"), p_width, width = 7, height = 4)
  }
}

summary_rows <- data.frame(
  run_id = args$run_id,
  source_manifest = args$source_manifest,
  synthesis_run_id = args$synthesis_run_id,
  n_source_runs = nrow(source_manifest),
  n_block_audit_available = sum(availability$block_audit_available),
  block_shift_tables_written = length(shift_rows) > 0L,
  ablation_tables_written = length(ablation_rows) > 0L,
  draw_stress_tables_written = draw_stress_written,
  diagnostic_scope = "no_refit; individual quantile fits unchanged; monotone adjustments are post-hoc synthesis diagnostics",
  stringsAsFactors = FALSE
)
app_write_csv(summary_rows, file.path(run_dirs$tables, "synthesis_readout_audit_summary.csv"))

provenance <- data.frame(
  artifact = c(
    "readout_feature_block_shift_by_horizon",
    "readout_block_ablation_score_summary",
    "posterior_draw_synthesis_stress_by_horizon",
    "diagnostic_figures"
  ),
  path = c(
    app_prefer_repo_relative_path(file.path(run_dirs$tables, "readout_feature_block_shift_by_horizon.csv")),
    app_prefer_repo_relative_path(file.path(run_dirs$tables, "readout_block_ablation_score_summary.csv")),
    app_prefer_repo_relative_path(file.path(run_dirs$tables, "posterior_draw_synthesis_stress_by_horizon.csv")),
    app_prefer_repo_relative_path(figure_dir)
  ),
  role = c(
    "Block-wise feature-shift audit for beta and alpha readouts.",
    "No-refit diagnostic score summary after zeroing selected readout blocks.",
    "Draw-level post-hoc synthesis stress audit using aligned draw indices.",
    "Diagnostic figures for audit interpretation."
  ),
  stringsAsFactors = FALSE
)
app_write_csv(provenance, file.path(generated_dir, "synthesis_readout_audit_provenance.csv"))
app_stage_done("16_audit_glofas_synthesis_and_readout_blocks", run_dirs)
