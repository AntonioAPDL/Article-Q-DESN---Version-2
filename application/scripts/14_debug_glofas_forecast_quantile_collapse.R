#!/usr/bin/env Rscript
# Purpose: no-refit debug bundle for the GloFAS multi-quantile forecast
# collapse. The script compares historical fitted designs with forecast
# linearization designs, checks prediction identities, summarizes forecast
# components, and diagnoses cross-quantile spread/crossings.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/make_manuscript_outputs.R"))

args <- app_parse_args(list(
  config = "local_trackers/runtime_configs/glofas_multiquantile_dec25_20260603/synthesis_config.yaml",
  source_manifest = "local_trackers/runtime_configs/glofas_multiquantile_dec25_20260603/synthesis_source_manifest.csv",
  synthesis_run_id = "glofas_multiquantile_dec25_20260603_synthesis_final",
  pre_cutoff_run_id = "glofas_multiquantile_dec25_20260603_pre_cutoff_history",
  run_id = "glofas_multiquantile_dec25_20260603_forecast_debug",
  history_n = 1000
))

cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id)
app_stage_start("14_debug_glofas_forecast_quantile_collapse", run_dirs)
app_write_yaml(cfg, file.path(run_dirs$manifest, "run_config.yaml"))
app_write_json(cfg, file.path(run_dirs$manifest, "run_config.json"))
app_write_git_state(file.path(run_dirs$manifest, "git_state.txt"))
app_write_session_info(file.path(run_dirs$manifest, "session_info.txt"))

resolve_path <- function(path) {
  if (grepl("^/", path)) path else app_path(path)
}

safe_sd <- function(x) {
  s <- stats::sd(as.numeric(x), na.rm = TRUE)
  if (!is.finite(s) || s < 1.0e-10) 1 else s
}

matrix_feature_names <- function(X) {
  colnames(X) %||% paste0("feature_", seq_len(ncol(X)))
}

summarize_future_shift <- function(X_hist, X_future, row_info, quantile_id, quantile_level, block_name) {
  X_hist <- as.matrix(X_hist)
  X_future <- as.matrix(X_future)
  storage.mode(X_hist) <- "double"
  storage.mode(X_future) <- "double"
  mu <- colMeans(X_hist, na.rm = TRUE)
  sig <- apply(X_hist, 2L, safe_sd)
  lo <- apply(X_hist, 2L, min, na.rm = TRUE)
  hi <- apply(X_hist, 2L, max, na.rm = TRUE)
  Z <- sweep(sweep(X_future, 2L, mu, "-"), 2L, sig, "/")
  out_range <- sweep(X_future, 2L, lo, "<") | sweep(X_future, 2L, hi, ">")
  data.frame(
    quantile_id = quantile_id,
    quantile_level = quantile_level,
    block = block_name,
    horizon = as.integer(row_info$horizon),
    target_date = as.Date(row_info$target_date),
    max_abs_z = apply(abs(Z), 1L, max, na.rm = TRUE),
    mean_abs_z = rowMeans(abs(Z), na.rm = TRUE),
    n_abs_z_gt_3 = rowSums(abs(Z) > 3, na.rm = TRUE),
    n_abs_z_gt_5 = rowSums(abs(Z) > 5, na.rm = TRUE),
    frac_outside_history_range = rowMeans(out_range, na.rm = TRUE),
    future_row_norm = sqrt(rowSums(X_future^2, na.rm = TRUE)),
    history_row_norm_median = stats::median(sqrt(rowSums(X_hist^2, na.rm = TRUE)), na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}

top_shift_features <- function(X_hist, X_future, quantile_id, quantile_level, block_name, top_k = 25L) {
  X_hist <- as.matrix(X_hist)
  X_future <- as.matrix(X_future)
  mu <- colMeans(X_hist, na.rm = TRUE)
  sig <- apply(X_hist, 2L, safe_sd)
  Z <- sweep(sweep(X_future, 2L, mu, "-"), 2L, sig, "/")
  max_abs <- apply(abs(Z), 2L, max, na.rm = TRUE)
  h_idx <- apply(abs(Z), 2L, which.max)
  ord <- head(order(max_abs, decreasing = TRUE), min(top_k, length(max_abs)))
  data.frame(
    quantile_id = quantile_id,
    quantile_level = quantile_level,
    block = block_name,
    feature = matrix_feature_names(X_hist)[ord],
    max_abs_z = max_abs[ord],
    horizon_at_max = h_idx[ord],
    future_value_at_max = X_future[cbind(h_idx[ord], ord)],
    history_mean = mu[ord],
    history_sd = sig[ord],
    stringsAsFactors = FALSE
  )
}

summarize_draws <- function(draws) {
  key <- interaction(draws$quantile_level, draws$horizon, drop = TRUE)
  rows <- lapply(split(draws, key), function(block) {
    data.frame(
      quantile_level = as.numeric(block$quantile_level[[1L]]),
      horizon = as.integer(block$horizon[[1L]]),
      target_date = as.Date(block$target_date[[1L]]),
      q_y_mean = mean(block$q_y_draw, na.rm = TRUE),
      q_y_sd = stats::sd(block$q_y_draw, na.rm = TRUE),
      q_g_mean = mean(block$q_g_draw, na.rm = TRUE),
      q_g_sd = stats::sd(block$q_g_draw, na.rm = TRUE),
      d_g_mean = mean(block$d_g_draw, na.rm = TRUE),
      d_g_sd = stats::sd(block$d_g_draw, na.rm = TRUE),
      latent_y_mean = mean(block$latent_y_draw, na.rm = TRUE),
      latent_y_sd = stats::sd(block$latent_y_draw, na.rm = TRUE),
      raw_glofas_quantile = mean(block$raw_glofas_quantile, na.rm = TRUE),
      y_reference = mean(block$y_reference, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out[order(out$quantile_level, out$horizon), , drop = FALSE]
}

manifest <- app_read_csv(app_path(args$source_manifest))
if ("enabled" %in% names(manifest)) manifest <- manifest[app_as_bool_vec(manifest$enabled), , drop = FALSE]
required <- c("quantile_id", "quantile_level", "run_dir", "qdesn_fit_id")
app_check_required_columns(manifest, required, "synthesis source manifest")
manifest$quantile_level <- as.numeric(manifest$quantile_level)
manifest <- manifest[order(manifest$quantile_level), , drop = FALSE]
history_n <- as.integer(args$history_n)

feature_shift_rows <- list()
top_feature_rows <- list()
latent_rows <- list()
coef_rows <- list()
beta_means <- list()
alpha_means <- list()
identity_rows <- list()
component_rows <- list()
fit_paths <- character()

for (i in seq_len(nrow(manifest))) {
  row <- manifest[i, , drop = FALSE]
  qid <- row$quantile_id[[1L]]
  qlev <- row$quantile_level[[1L]]
  run_dir <- resolve_path(row$run_dir[[1L]])
  fit_id <- row$qdesn_fit_id[[1L]]
  fit_path <- file.path(run_dir, "objects", paste0(fit_id, ".rds"))
  design_path <- file.path(run_dir, "objects", paste0(fit_id, "__design.rds"))
  draw_path <- file.path(run_dir, "tables", "posterior_draw_predictions.csv")
  if (!file.exists(fit_path)) stop(sprintf("Missing fit object: %s", fit_path), call. = FALSE)
  if (!file.exists(design_path)) stop(sprintf("Missing design object: %s", design_path), call. = FALSE)
  if (!file.exists(draw_path)) stop(sprintf("Missing posterior draw prediction table: %s", draw_path), call. = FALSE)
  fit_paths <- c(fit_paths, fit_path, design_path, draw_path)

  fit <- readRDS(fit_path)
  design <- readRDS(design_path)
  lin <- fit$variational_state$future_linearization %||% NULL
  if (is.null(lin) || is.null(lin$X_beta_future) || is.null(lin$X_alpha_future)) {
    stop(sprintf("Fit is missing future linearization design matrices: %s", fit_path), call. = FALSE)
  }
  base <- design$base_panel
  base$target_date <- as.Date(base$target_date)
  origin <- as.Date(design$latent_data$origin_date %||% max(base$target_date, na.rm = TRUE))
  hist_idx <- which(base$target_date < origin & is.finite(base$y_transformed))
  hist_idx <- tail(hist_idx[order(base$target_date[hist_idx])], history_n)

  X_beta_hist <- as.matrix(design$X_beta[hist_idx, , drop = FALSE])
  X_alpha_hist <- as.matrix(design$X_alpha[hist_idx, , drop = FALSE])
  X_beta_future <- as.matrix(lin$X_beta_future)
  X_alpha_future <- as.matrix(lin$X_alpha_future)
  feature_shift_rows[[length(feature_shift_rows) + 1L]] <- summarize_future_shift(
    X_beta_hist, X_beta_future, design$future_key, qid, qlev, "beta"
  )
  feature_shift_rows[[length(feature_shift_rows) + 1L]] <- summarize_future_shift(
    X_alpha_hist, X_alpha_future, design$future_key, qid, qlev, "alpha"
  )
  top_feature_rows[[length(top_feature_rows) + 1L]] <- top_shift_features(
    X_beta_hist, X_beta_future, qid, qlev, "beta"
  )
  top_feature_rows[[length(top_feature_rows) + 1L]] <- top_shift_features(
    X_alpha_hist, X_alpha_future, qid, qlev, "alpha"
  )

  y_hist <- as.numeric(base$y_transformed[hist_idx])
  y_mean <- as.numeric(lin$y_mean %||% colMeans(fit$draws$y_future, na.rm = TRUE))
  y_future <- as.matrix(fit$draws$y_future)
  latent_rows[[length(latent_rows) + 1L]] <- data.frame(
    quantile_id = qid,
    quantile_level = qlev,
    horizon = as.integer(design$future_key$horizon),
    target_date = as.Date(design$future_key$target_date),
    y_future_linearization_mean = y_mean,
    y_future_draw_mean = colMeans(y_future, na.rm = TRUE),
    y_future_draw_sd = apply(y_future, 2L, stats::sd, na.rm = TRUE),
    y_future_draw_lo = apply(y_future, 2L, stats::quantile, probs = 0.05, na.rm = TRUE, names = FALSE),
    y_future_draw_hi = apply(y_future, 2L, stats::quantile, probs = 0.95, na.rm = TRUE, names = FALSE),
    y_future_oracle = as.numeric(design$y_future_oracle),
    hist_y_mean = mean(y_hist, na.rm = TRUE),
    hist_y_sd = safe_sd(y_hist),
    hist_y_min = min(y_hist, na.rm = TRUE),
    hist_y_max = max(y_hist, na.rm = TRUE),
    y_future_z_vs_history = (y_mean - mean(y_hist, na.rm = TRUE)) / safe_sd(y_hist),
    stringsAsFactors = FALSE
  )

  theta <- as.matrix(fit$draws$theta)
  beta_mean <- colMeans(theta[, design$beta_index, drop = FALSE], na.rm = TRUE)
  alpha_mean <- colMeans(theta[, design$alpha_index, drop = FALSE], na.rm = TRUE)
  beta_means[[qid]] <- beta_mean
  alpha_means[[qid]] <- alpha_mean
  coef_rows[[length(coef_rows) + 1L]] <- data.frame(
    quantile_id = qid,
    quantile_level = qlev,
    beta_norm = sqrt(sum(beta_mean^2)),
    alpha_norm = sqrt(sum(alpha_mean^2)),
    beta_max_abs = max(abs(beta_mean)),
    alpha_max_abs = max(abs(alpha_mean)),
    vb_converged = isTRUE(fit$vb_diagnostics$converged %||% FALSE),
    vb_iterations = as.integer(fit$vb_diagnostics$iterations %||% NA_integer_),
    vb_max_parameter_change = as.numeric(fit$vb_diagnostics$max_parameter_change %||% NA_real_),
    stringsAsFactors = FALSE
  )

  draws <- app_read_csv(draw_path)
  draws$q_y_draw <- as.numeric(draws$q_y_draw)
  draws$q_g_draw <- as.numeric(draws$q_g_draw)
  draws$d_g_draw <- as.numeric(draws$d_g_draw)
  draws$q_y_model_draw <- as.numeric(draws$q_y_model_draw)
  draws$q_g_model_draw <- as.numeric(draws$q_g_model_draw)
  identity_rows[[length(identity_rows) + 1L]] <- data.frame(
    quantile_id = qid,
    quantile_level = qlev,
    n_draw_rows = nrow(draws),
    max_abs_qy_identity_error = max(abs(draws$q_y_draw - (draws$q_g_draw - draws$d_g_draw)), na.rm = TRUE),
    max_abs_qy_model_error = max(abs(draws$q_y_draw - draws$q_y_model_draw), na.rm = TRUE),
    max_abs_qg_model_error = max(abs(draws$q_g_draw - draws$q_g_model_draw), na.rm = TRUE),
    finite_all = all(is.finite(draws$q_y_draw) & is.finite(draws$q_g_draw) & is.finite(draws$d_g_draw)),
    prediction_state_strategy = paste(sort(unique(draws$prediction_state_strategy)), collapse = ";"),
    stringsAsFactors = FALSE
  )
  comp <- summarize_draws(draws)
  comp$quantile_id <- qid
  component_rows[[length(component_rows) + 1L]] <- comp
  rm(fit, design, theta, y_future, X_beta_hist, X_alpha_hist, X_beta_future, X_alpha_future)
  gc()
}

feature_shift <- app_bind_rows_fill(feature_shift_rows)
top_features <- app_bind_rows_fill(top_feature_rows)
latent <- app_bind_rows_fill(latent_rows)
coef <- app_bind_rows_fill(coef_rows)
identity <- app_bind_rows_fill(identity_rows)
components <- app_bind_rows_fill(component_rows)

coef_corr_rows <- list()
if (length(beta_means) >= 2L) {
  beta_mat <- do.call(rbind, beta_means)
  alpha_mat <- do.call(rbind, alpha_means)
  beta_cor <- stats::cor(t(beta_mat), use = "pairwise.complete.obs")
  alpha_cor <- stats::cor(t(alpha_mat), use = "pairwise.complete.obs")
  qids <- rownames(beta_cor)
  for (i in seq_along(qids)) {
    for (j in seq_along(qids)) {
      coef_corr_rows[[length(coef_corr_rows) + 1L]] <- data.frame(
        quantile_id_1 = qids[[i]],
        quantile_id_2 = qids[[j]],
        beta_correlation = beta_cor[i, j],
        alpha_correlation = alpha_cor[i, j],
        stringsAsFactors = FALSE
      )
    }
  }
}
coef_corr <- app_bind_rows_fill(coef_corr_rows)

synthesis_pred_path <- file.path(app_config_path(cfg, "runs"), args$synthesis_run_id, "tables", "prediction_quantiles_synthesized.csv")
if (!file.exists(synthesis_pred_path)) stop(sprintf("Missing synthesis prediction table: %s", synthesis_pred_path), call. = FALSE)
synth <- app_read_csv(synthesis_pred_path)
synth$quantile_level <- as.numeric(synth$quantile_level)
synth$horizon <- as.integer(synth$horizon)
synth$target_date <- as.Date(synth$target_date)
qdesn_synth <- synth[synth$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
cross_rows <- list()
for (h in sort(unique(qdesn_synth$horizon))) {
  block <- qdesn_synth[qdesn_synth$horizon == h, , drop = FALSE]
  block <- block[order(block$quantile_level), , drop = FALSE]
  gaps <- diff(block$qhat)
  gaps_mono <- diff(block$qhat_monotone)
  p_lo <- head(block$quantile_level, -1L)
  p_hi <- tail(block$quantile_level, -1L)
  cross_rows[[length(cross_rows) + 1L]] <- data.frame(
    horizon = h,
    target_date = block$target_date[[1L]],
    pair = paste0("p", p_lo, "_p", p_hi),
    p_lower = p_lo,
    p_upper = p_hi,
    independent_gap = gaps,
    monotone_gap = gaps_mono,
    crossing = gaps < -1.0e-10,
    crossing_magnitude = pmax(-gaps, 0),
    stringsAsFactors = FALSE
  )
}
crossing <- do.call(rbind, cross_rows)

pre_spread_path <- file.path(app_config_path(cfg, "runs"), args$pre_cutoff_run_id, "tables", "pre_cutoff_quantile_spread_by_date_last1000.csv")
if (!file.exists(pre_spread_path)) {
  pre_spread_path <- file.path(app_config_path(cfg, "runs"), args$pre_cutoff_run_id, "tables", "pre_cutoff_quantile_spread_by_date.csv")
}
pre_spread <- if (file.exists(pre_spread_path)) app_read_csv(pre_spread_path) else data.frame()

forecast_spread_rows <- lapply(split(qdesn_synth, qdesn_synth$horizon), function(block) {
  block <- block[order(block$quantile_level), , drop = FALSE]
  pick <- function(col, p) block[[col]][match(p, block$quantile_level)]
  data.frame(
    horizon = block$horizon[[1L]],
    target_date = block$target_date[[1L]],
    width_90_independent = pick("qhat", 0.95) - pick("qhat", 0.05),
    width_65_independent = pick("qhat", 0.80) - pick("qhat", 0.15),
    width_30_independent = pick("qhat", 0.65) - pick("qhat", 0.35),
    width_90_monotone = pick("qhat_monotone", 0.95) - pick("qhat_monotone", 0.05),
    width_65_monotone = pick("qhat_monotone", 0.80) - pick("qhat_monotone", 0.15),
    width_30_monotone = pick("qhat_monotone", 0.65) - pick("qhat_monotone", 0.35),
    n_crossing_pairs = sum(diff(block$qhat) < -1.0e-10, na.rm = TRUE),
    n_zero_gaps_monotone = sum(abs(diff(block$qhat_monotone)) < 1.0e-8, na.rm = TRUE),
    n_distinct_monotone = length(unique(round(block$qhat_monotone, 8))),
    stringsAsFactors = FALSE
  )
})
forecast_spread <- do.call(rbind, forecast_spread_rows)

app_write_csv(feature_shift, file.path(run_dirs$tables, "forecast_feature_shift_by_quantile_horizon.csv"))
app_write_csv(top_features, file.path(run_dirs$tables, "forecast_feature_shift_top_features.csv"))
app_write_csv(latent, file.path(run_dirs$tables, "forecast_latent_path_diagnostics.csv"))
app_write_csv(identity, file.path(run_dirs$tables, "prediction_identity_check.csv"))
app_write_csv(components, file.path(run_dirs$tables, "forecast_component_summary.csv"))
app_write_csv(coef, file.path(run_dirs$tables, "coefficient_norms_by_quantile.csv"))
app_write_csv(coef_corr, file.path(run_dirs$tables, "coefficient_pairwise_correlation.csv"))
app_write_csv(crossing, file.path(run_dirs$tables, "forecast_crossing_by_horizon_pair.csv"))
app_write_csv(forecast_spread, file.path(run_dirs$tables, "forecast_spread_by_horizon.csv"))
if (nrow(pre_spread)) app_write_csv(pre_spread, file.path(run_dirs$tables, "pre_cutoff_spread_reference.csv"))

out_dir <- file.path(app_config_path(cfg, "generated_outputs"), basename(run_dirs$run_dir))
fig_dir <- file.path(out_dir, "figures")
app_ensure_dir(fig_dir)
plot_pdf <- function(name, width = 8.5, height = 5.2, expr) {
  path <- file.path(fig_dir, name)
  grDevices::pdf(path, width = width, height = height)
  on.exit(grDevices::dev.off(), add = TRUE)
  force(expr)
  path
}

q_levels <- sort(unique(manifest$quantile_level))
q_cols <- grDevices::hcl.colors(length(q_levels), "Dark 3")
names(q_cols) <- as.character(q_levels)
figures <- c()

figures <- c(figures, feature_shift = plot_pdf("glofas_forecast_feature_shift_by_horizon.pdf", 8.8, 5.5, {
  ylim <- range(feature_shift$max_abs_z, na.rm = TRUE)
  plot(range(feature_shift$horizon), ylim, type = "n", xlab = "Forecast horizon", ylab = "Maximum absolute feature z-score", main = "Future design shift relative to last 1000 fitted dates")
  grid(col = "gray90")
  for (q in q_levels) {
    for (block_name in c("beta", "alpha")) {
      block <- feature_shift[abs(feature_shift$quantile_level - q) < 1e-12 & feature_shift$block == block_name, , drop = FALSE]
      lines(block$horizon, block$max_abs_z, col = q_cols[[as.character(q)]], lwd = if (block_name == "beta") 1.6 else 1.1, lty = if (block_name == "beta") 1 else 2)
    }
  }
  abline(h = c(3, 5), lty = 3, col = "gray35")
  legend("topleft", legend = c(paste0("p=", q_levels), "beta solid / alpha dashed"), col = c(q_cols, "#111111"), lty = c(rep(1, length(q_levels)), 1), lwd = c(rep(1.6, length(q_levels)), 1), bty = "n", cex = 0.72, ncol = 2)
}))

figures <- c(figures, latent_path = plot_pdf("glofas_forecast_latent_path_diagnostics.pdf", 8.8, 5.5, {
  hist_ref <- latent[latent$quantile_id == latent$quantile_id[[1L]], , drop = FALSE]
  ylim <- range(c(latent$y_future_draw_lo, latent$y_future_draw_hi, latent$y_future_oracle), na.rm = TRUE)
  plot(range(latent$horizon), ylim, type = "n", xlab = "Forecast horizon", ylab = "Future latent response", main = "Recursive future latent path by quantile fit")
  grid(col = "gray90")
  for (q in q_levels) {
    block <- latent[abs(latent$quantile_level - q) < 1e-12, , drop = FALSE]
    polygon(c(block$horizon, rev(block$horizon)), c(block$y_future_draw_lo, rev(block$y_future_draw_hi)), border = NA, col = grDevices::adjustcolor(q_cols[[as.character(q)]], alpha.f = 0.10))
    lines(block$horizon, block$y_future_draw_mean, col = q_cols[[as.character(q)]], lwd = 1.5)
  }
  lines(hist_ref$horizon, hist_ref$y_future_oracle, col = "#111111", lwd = 1.8)
  legend("topright", legend = c(paste0("p=", q_levels), "observed future"), col = c(q_cols, "#111111"), lty = 1, lwd = c(rep(1.5, length(q_levels)), 1.8), bty = "n", cex = 0.72)
}))

figures <- c(figures, components = plot_pdf("glofas_forecast_component_summary.pdf", 9, 7.2, {
  par(mfrow = c(3, 1), mar = c(3.2, 4.3, 2.0, 1))
  for (metric in c("q_y_mean", "q_g_mean", "d_g_mean")) {
    ylim <- range(components[[metric]], na.rm = TRUE)
    plot(range(components$horizon), ylim, type = "n", xlab = "Forecast horizon", ylab = metric, main = metric)
    grid(col = "gray90")
    for (q in q_levels) {
      block <- components[abs(components$quantile_level - q) < 1e-12, , drop = FALSE]
      lines(block$horizon, block[[metric]], col = q_cols[[as.character(q)]], lwd = 1.5)
    }
  }
}))

figures <- c(figures, crossing_heatmap = plot_pdf("glofas_forecast_crossing_heatmap.pdf", 8.4, 5.2, {
  pairs <- unique(crossing$pair)
  horizons <- sort(unique(crossing$horizon))
  mat <- matrix(0, nrow = length(pairs), ncol = length(horizons), dimnames = list(pairs, horizons))
  for (i in seq_len(nrow(crossing))) {
    mat[crossing$pair[[i]], as.character(crossing$horizon[[i]])] <- crossing$crossing_magnitude[[i]]
  }
  image(seq_along(horizons), seq_along(pairs), t(mat[nrow(mat):1, , drop = FALSE]), axes = FALSE, xlab = "Forecast horizon", ylab = "Adjacent quantile pair", col = grDevices::hcl.colors(30, "YlOrRd"))
  axis(1, at = seq_along(horizons), labels = horizons, cex.axis = 0.75)
  axis(2, at = seq_along(pairs), labels = rev(pairs), las = 2, cex.axis = 0.72)
  box()
  title("Independent Q-DESN crossing magnitude")
}))

figures <- c(figures, spread_compare = plot_pdf("glofas_history_vs_forecast_spread_debug.pdf", 8.8, 5.5, {
  hist_medians <- if (nrow(pre_spread)) {
    c(
      w90 = stats::median(pre_spread$width_90_monotone, na.rm = TRUE),
      w65 = stats::median(pre_spread$width_65_monotone, na.rm = TRUE),
      w30 = stats::median(pre_spread$width_30_monotone, na.rm = TRUE)
    )
  } else c(w90 = NA_real_, w65 = NA_real_, w30 = NA_real_)
  ylim <- range(c(forecast_spread$width_90_monotone, forecast_spread$width_65_monotone, forecast_spread$width_30_monotone, hist_medians), na.rm = TRUE)
  plot(range(forecast_spread$horizon), ylim, type = "n", xlab = "Forecast horizon", ylab = "Quantile width", main = "Forecast spread versus pre-cutoff fitted spread")
  grid(col = "gray90")
  lines(forecast_spread$horizon, forecast_spread$width_90_monotone, col = "#2563eb", lwd = 1.8)
  lines(forecast_spread$horizon, forecast_spread$width_65_monotone, col = "#059669", lwd = 1.6)
  lines(forecast_spread$horizon, forecast_spread$width_30_monotone, col = "#7c3aed", lwd = 1.6)
  abline(h = hist_medians[["w90"]], col = "#2563eb", lty = 2)
  abline(h = hist_medians[["w65"]], col = "#059669", lty = 2)
  abline(h = hist_medians[["w30"]], col = "#7c3aed", lty = 2)
  legend("topleft", legend = c("forecast 90", "forecast 65", "forecast 30", "history medians dashed"), col = c("#2563eb", "#059669", "#7c3aed", "#111111"), lty = c(1, 1, 1, 2), lwd = c(1.8, 1.6, 1.6, 1.2), bty = "n", cex = 0.78)
}))

figures <- c(figures, coefficient_norms = plot_pdf("glofas_coefficient_coherence_debug.pdf", 8.8, 5.2, {
  par(mfrow = c(1, 2), mar = c(4, 4, 2, 1))
  plot(coef$quantile_level, coef$beta_norm, type = "b", pch = 19, col = "#2563eb", xlab = "Quantile level", ylab = "Coefficient norm", main = "Readout norm")
  lines(coef$quantile_level, coef$alpha_norm, type = "b", pch = 19, col = "#b91c1c")
  grid(col = "gray90")
  legend("topleft", legend = c("beta", "alpha"), col = c("#2563eb", "#b91c1c"), pch = 19, lty = 1, bty = "n")
  if (nrow(coef_corr)) {
    qids <- unique(coef_corr$quantile_id_1)
    mat <- matrix(coef_corr$beta_correlation, nrow = length(qids), byrow = TRUE, dimnames = list(qids, qids))
    image(seq_along(qids), seq_along(qids), t(mat[nrow(mat):1, , drop = FALSE]), axes = FALSE, xlab = "Quantile", ylab = "Quantile", col = grDevices::hcl.colors(30, "Blues"))
    axis(1, at = seq_along(qids), labels = qids, las = 2, cex.axis = 0.75)
    axis(2, at = seq_along(qids), labels = rev(qids), las = 2, cex.axis = 0.75)
    title("Beta correlation")
    box()
  }
}))

prov <- app_write_output_provenance(
  outputs = figures,
  run_dirs = run_dirs,
  cfg = cfg,
  path = file.path(run_dirs$tables, "forecast_debug_figure_provenance.csv")
)
app_write_csv(prov, file.path(out_dir, "forecast_debug_figure_provenance.csv"))

summary <- data.frame(
  metric = c(
    "max_identity_error",
    "max_feature_shift_z",
    "max_latent_future_z",
    "total_crossing_pairs",
    "forecast_zero_width_30_horizons",
    "pre_cutoff_median_width_30",
    "forecast_median_width_30"
  ),
  value = c(
    max(identity$max_abs_qy_identity_error, na.rm = TRUE),
    max(feature_shift$max_abs_z, na.rm = TRUE),
    max(abs(latent$y_future_z_vs_history), na.rm = TRUE),
    sum(crossing$crossing, na.rm = TRUE),
    sum(abs(forecast_spread$width_30_monotone) < 1.0e-8, na.rm = TRUE),
    if (nrow(pre_spread)) stats::median(pre_spread$width_30_monotone, na.rm = TRUE) else NA_real_,
    stats::median(forecast_spread$width_30_monotone, na.rm = TRUE)
  ),
  stringsAsFactors = FALSE
)
app_write_csv(summary, file.path(run_dirs$tables, "forecast_debug_summary.csv"))

readiness <- data.frame(
  category = c("sources", "identity", "features", "crossings", "figures"),
  check = c(
    "all_source_objects_exist",
    "prediction_identity_holds",
    "feature_shift_tables_written",
    "crossing_table_written",
    "figures_exist"
  ),
  passed = c(
    all(file.exists(fit_paths)),
    max(identity$max_abs_qy_identity_error, na.rm = TRUE) < 1.0e-8,
    nrow(feature_shift) > 0 && nrow(top_features) > 0,
    nrow(crossing) > 0,
    all(file.exists(unname(figures)))
  ),
  detail = c(
    sprintf("source files=%d", length(fit_paths)),
    sprintf("max_abs_error=%0.3g", max(identity$max_abs_qy_identity_error, na.rm = TRUE)),
    file.path(run_dirs$tables, "forecast_feature_shift_by_quantile_horizon.csv"),
    file.path(run_dirs$tables, "forecast_crossing_by_horizon_pair.csv"),
    paste(unname(figures), collapse = "; ")
  ),
  stringsAsFactors = FALSE
)
app_write_csv(readiness, file.path(run_dirs$tables, "forecast_debug_readiness_report.csv"))
writeLines(
  c(
    sprintf("run_id: %s", basename(run_dirs$run_dir)),
    sprintf("synthesis_run_id: %s", args$synthesis_run_id),
    sprintf("pre_cutoff_run_id: %s", args$pre_cutoff_run_id),
    sprintf("history_n: %d", history_n),
    sprintf("all_checks_passed: %s", all(readiness$passed)),
    sprintf("generated_outputs: %s", out_dir)
  ),
  file.path(run_dirs$tables, "forecast_debug_readiness_summary.txt")
)

app_stage_done("14_debug_glofas_forecast_quantile_collapse", run_dirs)
cat(run_dirs$run_dir, "\n")
