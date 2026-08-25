#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- if (!is.na(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
}
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))

out_dir <- if (length(args) >= 1L && nzchar(args[[1L]])) {
  args[[1L]]
} else {
  app_path("application/cache/joint_qvp_ts_asymmetric_laplace_tail_t500_washout_review_20260702")
}
out_dir <- normalizePath(out_dir, mustWork = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

slice_ts_fixture <- function(fixture, keep_idx) {
  out <- fixture
  out$y <- fixture$y[keep_idx]
  out$Z <- fixture$Z[keep_idx, , drop = FALSE]
  out$mu <- fixture$mu[keep_idx]
  out$sigma <- fixture$sigma[keep_idx]
  out$innovation <- fixture$innovation[keep_idx]
  out$innovation_raw <- fixture$innovation_raw[keep_idx]
  out$true_q <- fixture$true_q[keep_idx, , drop = FALSE]
  out$crossing_diagnostics <- app_joint_qvp_crossing_diagnostics(out$true_q, out$tau)
  out
}

qhat_vb_interval <- function(vb_fit, Z, K, p, level = 0.95) {
  z <- stats::qnorm((1 + level) / 2)
  lower <- upper <- matrix(NA_real_, nrow = nrow(Z), ncol = K)
  for (k in seq_len(K)) {
    idx <- ((k - 1L) * p + 1L):(k * p)
    beta_cov_k <- as.matrix(vb_fit$beta_cov[idx, idx, drop = FALSE])
    var_k <- rowSums((Z %*% beta_cov_k) * Z)
    se_k <- sqrt(pmax(var_k, 0))
    lower[, k] <- vb_fit$qhat_mean[, k] - z * se_k
    upper[, k] <- vb_fit$qhat_mean[, k] + z * se_k
  }
  list(lower = lower, upper = upper)
}

qhat_mcmc_interval <- function(pooled_mcmc, Z, K, p, probs = c(0.025, 0.975)) {
  lower <- upper <- matrix(NA_real_, nrow = nrow(Z), ncol = K)
  for (k in seq_len(K)) {
    idx <- ((k - 1L) * p + 1L):(k * p)
    q_draws <- pooled_mcmc$beta_draws[, idx, drop = FALSE] %*% t(Z)
    q_draws <- sweep(q_draws, 1L, pooled_mcmc$alpha_draws[, k], FUN = "+")
    qs <- apply(q_draws, 2L, stats::quantile, probs = probs, names = FALSE, type = 8)
    lower[, k] <- qs[1L, ]
    upper[, k] <- qs[2L, ]
  }
  list(lower = lower, upper = upper)
}

app_joint_qvp_cumulative_coverage <- function(y, qhat) {
  as.numeric(cumsum(as.numeric(y <= qhat)) / seq_along(y))
}

app_joint_qvp_vb_coverage_draws <- function(vb_fit, fixture, quantile_index, n_draws = 800L, seed = 20260702L) {
  set.seed(seed)
  K <- length(fixture$tau)
  p <- ncol(fixture$Z)
  k <- as.integer(quantile_index)
  idx <- ((k - 1L) * p + 1L):(k * p)
  cov_k <- as.matrix(vb_fit$beta_cov[idx, idx, drop = FALSE])
  cov_k <- (cov_k + t(cov_k)) / 2
  chol_k <- tryCatch(chol(cov_k + diag(1.0e-10, p)), error = function(e) chol(diag(1.0e-8, p)))
  z <- matrix(stats::rnorm(n_draws * p), nrow = n_draws, ncol = p)
  beta_draws <- sweep(z %*% chol_k, 2L, vb_fit$beta_mean[idx], FUN = "+")
  q_draws <- beta_draws %*% t(fixture$Z)
  q_draws <- q_draws + vb_fit$alpha_mean[[k]]
  t(apply(q_draws, 1L, function(qhat) app_joint_qvp_cumulative_coverage(fixture$y, qhat)))
}

app_joint_qvp_mcmc_coverage_draws <- function(pooled_mcmc, fixture, quantile_index) {
  K <- length(fixture$tau)
  p <- ncol(fixture$Z)
  k <- as.integer(quantile_index)
  idx <- ((k - 1L) * p + 1L):(k * p)
  q_draws <- pooled_mcmc$beta_draws[, idx, drop = FALSE] %*% t(fixture$Z)
  q_draws <- sweep(q_draws, 1L, pooled_mcmc$alpha_draws[, k], FUN = "+")
  t(apply(q_draws, 1L, function(qhat) app_joint_qvp_cumulative_coverage(fixture$y, qhat)))
}

app_joint_qvp_vb_qhat_draw_array <- function(vb_fit, fixture, n_draws = 800L, seed = 20260703L) {
  set.seed(seed)
  K <- length(fixture$tau)
  p <- ncol(fixture$Z)
  beta_cov <- as.matrix(vb_fit$beta_cov)
  beta_cov <- (beta_cov + t(beta_cov)) / 2
  chol_beta <- tryCatch(chol(beta_cov + diag(1.0e-10, K * p)), error = function(e) chol(diag(1.0e-8, K * p)))
  z <- matrix(stats::rnorm(n_draws * K * p), nrow = n_draws, ncol = K * p)
  beta_draws <- sweep(z %*% chol_beta, 2L, vb_fit$beta_mean, FUN = "+")
  qhat <- array(NA_real_, dim = c(n_draws, nrow(fixture$Z), K))
  for (draw_id in seq_len(n_draws)) {
    qhat[draw_id, , ] <- fixture$Z %*% app_joint_qvp_beta_matrix(beta_draws[draw_id, ], K, p) +
      matrix(vb_fit$alpha_mean, nrow = nrow(fixture$Z), ncol = K, byrow = TRUE)
  }
  qhat
}

app_joint_qvp_mcmc_qhat_draw_array <- function(pooled_mcmc, fixture) {
  K <- length(fixture$tau)
  p <- ncol(fixture$Z)
  n_draws <- nrow(pooled_mcmc$beta_draws)
  qhat <- array(NA_real_, dim = c(n_draws, nrow(fixture$Z), K))
  for (draw_id in seq_len(n_draws)) {
    qhat[draw_id, , ] <- fixture$Z %*% app_joint_qvp_beta_matrix(pooled_mcmc$beta_draws[draw_id, ], K, p) +
      matrix(pooled_mcmc$alpha_draws[draw_id, ], nrow = nrow(fixture$Z), ncol = K, byrow = TRUE)
  }
  qhat
}

app_joint_qvp_cumulative_band_coverage <- function(y, lower, upper) {
  as.numeric(cumsum(as.numeric(y >= lower & y <= upper)) / seq_along(y))
}

app_joint_qvp_band_coverage_draws <- function(y, qhat_draw_array, low_k, high_k) {
  n_draws <- dim(qhat_draw_array)[[1L]]
  out <- matrix(NA_real_, nrow = n_draws, ncol = length(y))
  for (draw_id in seq_len(n_draws)) {
    out[draw_id, ] <- app_joint_qvp_cumulative_band_coverage(
      y,
      qhat_draw_array[draw_id, , low_k],
      qhat_draw_array[draw_id, , high_k]
    )
  }
  out
}

app_joint_qvp_band_summary_row <- function(fixture, fit_label, lower, upper) {
  data.frame(
    fit = fit_label,
    lower_tau = min(fixture$tau),
    upper_tau = max(fixture$tau),
    lower_hit_rate = mean(fixture$y <= lower),
    upper_hit_rate = mean(fixture$y <= upper),
    central_band_coverage = mean(fixture$y >= lower & fixture$y <= upper),
    nominal_central_coverage = max(fixture$tau) - min(fixture$tau),
    mean_band_width = mean(upper - lower),
    max_band_width = max(upper - lower),
    stringsAsFactors = FALSE
  )
}

plot_ts_coverage_band_comparison <- function(fixture, vb_fit, pooled_mcmc, path, title) {
  tau_order <- order(fixture$tau)
  low_k <- tau_order[[1L]]
  high_k <- tau_order[[length(tau_order)]]
  low_tau <- fixture$tau[[low_k]]
  high_tau <- fixture$tau[[high_k]]
  nominal_central <- high_tau - low_tau
  x <- seq_along(fixture$y)

  true_lower <- fixture$true_q[, low_k]
  true_upper <- fixture$true_q[, high_k]
  vb_lower <- vb_fit$qhat_mean[, low_k]
  vb_upper <- vb_fit$qhat_mean[, high_k]
  mc_lower <- pooled_mcmc$qhat_mean[, low_k]
  mc_upper <- pooled_mcmc$qhat_mean[, high_k]

  vb_qdraw <- app_joint_qvp_vb_qhat_draw_array(vb_fit, fixture)
  mc_qdraw <- app_joint_qvp_mcmc_qhat_draw_array(pooled_mcmc, fixture)
  vb_central_draws <- app_joint_qvp_band_coverage_draws(fixture$y, vb_qdraw, low_k, high_k)
  mc_central_draws <- app_joint_qvp_band_coverage_draws(fixture$y, mc_qdraw, low_k, high_k)
  vb_central_band <- apply(vb_central_draws, 2L, stats::quantile, probs = c(0.025, 0.975), names = FALSE, type = 8)
  mc_central_band <- apply(mc_central_draws, 2L, stats::quantile, probs = c(0.025, 0.975), names = FALSE, type = 8)

  true_central <- app_joint_qvp_cumulative_band_coverage(fixture$y, true_lower, true_upper)
  vb_central <- app_joint_qvp_cumulative_band_coverage(fixture$y, vb_lower, vb_upper)
  mc_central <- app_joint_qvp_cumulative_band_coverage(fixture$y, mc_lower, mc_upper)

  true_low <- app_joint_qvp_cumulative_coverage(fixture$y, true_lower)
  vb_low <- app_joint_qvp_cumulative_coverage(fixture$y, vb_lower)
  mc_low <- app_joint_qvp_cumulative_coverage(fixture$y, mc_lower)
  true_high <- app_joint_qvp_cumulative_coverage(fixture$y, true_upper)
  vb_high <- app_joint_qvp_cumulative_coverage(fixture$y, vb_upper)
  mc_high <- app_joint_qvp_cumulative_coverage(fixture$y, mc_upper)

  blue <- "#0072B2"
  orange <- "#D55E00"
  green <- "#009E73"
  black <- "#222222"
  vb_fill <- grDevices::adjustcolor(blue, alpha.f = 0.14)
  mc_fill <- grDevices::adjustcolor(orange, alpha.f = 0.13)
  true_fill <- grDevices::adjustcolor(green, alpha.f = 0.18)

  app_joint_qvp_png(path, width = 2400, height = 1850, res = 180)
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)
  graphics::layout(matrix(c(1, 1, 2, 3, 4, 5), ncol = 2L, byrow = TRUE), heights = c(1.25, 1, 1))
  graphics::par(oma = c(0, 0, 3.2, 0), mar = c(4.1, 4.8, 2.7, 1.2))

  y_range <- range(fixture$y, true_lower, true_upper, vb_lower, vb_upper, mc_lower, mc_upper, finite = TRUE)
  y_pad <- 0.06 * diff(y_range)
  if (!is.finite(y_pad) || y_pad <= 0) y_pad <- 1
  graphics::plot(x, fixture$y,
    type = "n",
    ylim = y_range + c(-y_pad, y_pad),
    xlab = "retained time index",
    ylab = "response / central extreme-quantile band",
    main = sprintf("Data with true and fitted central bands: tau %.2f to %.2f", low_tau, high_tau)
  )
  graphics::grid(col = "grey88")
  graphics::polygon(c(x, rev(x)), c(true_lower, rev(true_upper)), border = NA, col = true_fill)
  graphics::polygon(c(x, rev(x)), c(vb_lower, rev(vb_upper)), border = NA, col = vb_fill)
  graphics::polygon(c(x, rev(x)), c(mc_lower, rev(mc_upper)), border = NA, col = mc_fill)
  point_col <- ifelse(fixture$y < true_lower, blue, ifelse(fixture$y > true_upper, orange, grDevices::adjustcolor("grey25", alpha.f = 0.58)))
  graphics::points(x, fixture$y, pch = 16, cex = 0.32, col = point_col)
  graphics::lines(x, true_lower, col = black, lwd = 2.4)
  graphics::lines(x, true_upper, col = black, lwd = 2.4)
  graphics::lines(x, vb_lower, col = blue, lwd = 2.1)
  graphics::lines(x, vb_upper, col = blue, lwd = 2.1)
  graphics::lines(x, mc_lower, col = orange, lwd = 2.1, lty = 2)
  graphics::lines(x, mc_upper, col = orange, lwd = 2.1, lty = 2)
  graphics::legend("topleft",
    legend = c("observed y", "below true lower", "above true upper", "true band", "VB band", "MCMC band"),
    col = c("grey25", blue, orange, green, blue, orange),
    pch = c(16, 16, 16, NA, NA, NA),
    lty = c(NA, NA, NA, 1, 1, 2),
    lwd = c(NA, NA, NA, 8, 8, 8),
    bty = "n",
    cex = 0.78
  )

  plot_cov_panel <- function(main, nominal, true_curve, vb_curve, mc_curve, ylab, band = NULL) {
    y_range <- range(nominal, true_curve, vb_curve, mc_curve, band, finite = TRUE)
    y_pad <- max(0.02, 0.08 * diff(y_range))
    graphics::plot(x, true_curve, type = "n",
      ylim = pmax(0, pmin(1, y_range + c(-y_pad, y_pad))),
      xlab = "retained time index",
      ylab = ylab,
      main = main
    )
    graphics::grid(col = "grey88")
    if (!is.null(band)) {
      graphics::polygon(c(x, rev(x)), c(band$vb[1L, ], rev(band$vb[2L, ])), border = NA, col = vb_fill)
      graphics::polygon(c(x, rev(x)), c(band$mc[1L, ], rev(band$mc[2L, ])), border = NA, col = mc_fill)
    }
    graphics::abline(h = nominal, col = "grey35", lwd = 2, lty = 3)
    graphics::lines(x, true_curve, col = black, lwd = 2.4)
    graphics::lines(x, vb_curve, col = blue, lwd = 2.1)
    graphics::lines(x, mc_curve, col = orange, lwd = 2.1, lty = 2)
    graphics::legend("bottomright",
      legend = c(
        sprintf("nominal %.3f", nominal),
        sprintf("true final %.3f", tail(true_curve, 1L)),
        sprintf("VB final %.3f", tail(vb_curve, 1L)),
        sprintf("MCMC final %.3f", tail(mc_curve, 1L))
      ),
      col = c("grey35", black, blue, orange),
      lwd = c(2, 2.4, 2.1, 2.1),
      lty = c(3, 1, 1, 2),
      bty = "n",
      cex = 0.75
    )
  }

  plot_cov_panel(
    "Central band empirical coverage",
    nominal_central,
    true_central,
    vb_central,
    mc_central,
    "cumulative P(lower <= y <= upper)",
    band = list(vb = vb_central_band, mc = mc_central_band)
  )
  plot_cov_panel(
    sprintf("Lower extreme quantile coverage tau = %.2f", low_tau),
    low_tau,
    true_low,
    vb_low,
    mc_low,
    "cumulative P(y <= lower)"
  )
  plot_cov_panel(
    sprintf("Upper extreme quantile coverage tau = %.2f", high_tau),
    high_tau,
    true_high,
    vb_high,
    mc_high,
    "cumulative P(y <= upper)"
  )

  graphics::plot.new()
  graphics::title("Final coverage audit")
  summary_rows <- rbind(
    app_joint_qvp_band_summary_row(fixture, "truth", true_lower, true_upper),
    app_joint_qvp_band_summary_row(fixture, "VB", vb_lower, vb_upper),
    app_joint_qvp_band_summary_row(fixture, "MCMC", mc_lower, mc_upper)
  )
  header <- sprintf("%-7s %8s %8s %8s %9s", "fit", "lower", "upper", "central", "width")
  graphics::text(0, 0.88, "Final empirical coverage on retained Tn = 500", adj = 0, font = 2, cex = 0.9)
  graphics::text(0, 0.78, header, adj = 0, family = "mono", cex = 0.72)
  yy <- 0.68
  for (ii in seq_len(nrow(summary_rows))) {
    row <- summary_rows[ii, , drop = FALSE]
    line <- sprintf("%-7s %8.3f %8.3f %8.3f %9.3f",
      row$fit, row$lower_hit_rate, row$upper_hit_rate, row$central_band_coverage, row$mean_band_width)
    col <- if (identical(row$fit[[1L]], "truth")) black else if (identical(row$fit[[1L]], "VB")) blue else orange
    graphics::text(0, yy, line, adj = 0, family = "mono", cex = 0.72, col = col)
    yy <- yy - 0.10
  }
  graphics::text(0, yy - 0.02,
    sprintf("Nominal lower %.2f, upper %.2f, central %.2f.", low_tau, high_tau, nominal_central),
    adj = 0, cex = 0.72, col = "grey25")
  graphics::text(0, yy - 0.12,
    sprintf("Central coverage bands use %d VB path draws and %d pooled MCMC path draws.",
      dim(vb_qdraw)[[1L]], dim(mc_qdraw)[[1L]]),
    adj = 0, cex = 0.72, col = "grey25")

  graphics::mtext(paste(title, "coverage-band comparison"), outer = TRUE, side = 3, line = 1.1, font = 2, cex = 1.02)
  graphics::mtext("Top panel shows true and fitted central extreme-quantile bands on the retained data; lower panels show empirical coverage convergence.", outer = TRUE, side = 3, line = -0.35, cex = 0.72, col = "grey30")
  invisible(path)
}

plot_ts_extreme_coverage_bands <- function(fixture, vb_fit, pooled_mcmc, path, title) {
  tau_order <- order(fixture$tau)
  extreme_idx <- c(tau_order[[1L]], tau_order[[length(tau_order)]])
  x <- seq_along(fixture$y)
  blue <- "#0072B2"
  orange <- "#D55E00"
  black <- "#222222"
  vb_fill <- grDevices::adjustcolor(blue, alpha.f = 0.16)
  mc_fill <- grDevices::adjustcolor(orange, alpha.f = 0.15)
  app_joint_qvp_png(path, width = 1800, height = 1050, res = 170)
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)
  graphics::par(mfrow = c(1, 2), oma = c(0, 0, 3, 0), mar = c(4.4, 4.7, 3.1, 1.1))

  for (panel_id in seq_along(extreme_idx)) {
    k <- extreme_idx[[panel_id]]
    tau <- fixture$tau[[k]]
    true_cov <- app_joint_qvp_cumulative_coverage(fixture$y, fixture$true_q[, k])
    vb_mean_cov <- app_joint_qvp_cumulative_coverage(fixture$y, vb_fit$qhat_mean[, k])
    mc_mean_cov <- app_joint_qvp_cumulative_coverage(fixture$y, pooled_mcmc$qhat_mean[, k])
    vb_draw_cov <- app_joint_qvp_vb_coverage_draws(vb_fit, fixture, k, seed = 20260702L + k)
    mc_draw_cov <- app_joint_qvp_mcmc_coverage_draws(pooled_mcmc, fixture, k)
    vb_band <- apply(vb_draw_cov, 2L, stats::quantile, probs = c(0.025, 0.975), names = FALSE, type = 8)
    mc_band <- apply(mc_draw_cov, 2L, stats::quantile, probs = c(0.025, 0.975), names = FALSE, type = 8)
    y_range <- range(tau, true_cov, vb_mean_cov, mc_mean_cov, vb_band, mc_band, finite = TRUE)
    y_pad <- max(0.025, 0.08 * diff(y_range))
    graphics::plot(x, true_cov,
      type = "n",
      ylim = pmax(0, pmin(1, y_range + c(-y_pad, y_pad))),
      xlab = "retained time index",
      ylab = "cumulative empirical coverage",
      main = sprintf("Extreme quantile tau = %.2f", tau)
    )
    graphics::grid(col = "grey88")
    graphics::polygon(c(x, rev(x)), c(vb_band[1L, ], rev(vb_band[2L, ])), border = NA, col = vb_fill)
    graphics::polygon(c(x, rev(x)), c(mc_band[1L, ], rev(mc_band[2L, ])), border = NA, col = mc_fill)
    graphics::abline(h = tau, col = "grey35", lwd = 2, lty = 3)
    graphics::lines(x, true_cov, col = black, lwd = 2.5)
    graphics::lines(x, vb_mean_cov, col = blue, lwd = 2.2)
    graphics::lines(x, mc_mean_cov, col = orange, lwd = 2.2, lty = 2)
    graphics::legend(
      "topright",
      legend = c(
        sprintf("nominal %.2f", tau),
        sprintf("true final %.3f", tail(true_cov, 1L)),
        sprintf("VB final %.3f", tail(vb_mean_cov, 1L)),
        "VB 95% coverage band",
        sprintf("MCMC final %.3f", tail(mc_mean_cov, 1L)),
        "MCMC 95% coverage band"
      ),
      col = c("grey35", black, blue, vb_fill, orange, mc_fill),
      lwd = c(2, 2.5, 2.2, 8, 2.2, 8),
      lty = c(3, 1, 1, 1, 2, 1),
      bty = "n",
      cex = 0.78
    )
  }
  graphics::mtext(paste(title, "extreme-quantile cumulative coverage"), outer = TRUE, side = 3, line = 1.1, font = 2, cex = 1.03)
  graphics::mtext("Coverage bands vary fitted quantile paths; VB uses beta covariance with alpha point mass, MCMC uses pooled retained draws.", outer = TRUE, side = 3, line = -0.35, cex = 0.72, col = "grey30")
  invisible(path)
}

plot_ts_fit_overlay_bands <- function(fixture, vb_fit, pooled_mcmc, path, title) {
  K <- length(fixture$tau)
  p <- ncol(fixture$Z)
  x <- seq_along(fixture$y)
  vb_band <- qhat_vb_interval(vb_fit, fixture$Z, K, p)
  mc_band <- qhat_mcmc_interval(pooled_mcmc, fixture$Z, K, p)
  metrics <- rbind(
    app_joint_qvp_qhat_truth_summary(fixture, fixture$true_q, "truth", "plot"),
    app_joint_qvp_qhat_truth_summary(fixture, vb_fit$qhat_mean, "VB", "plot"),
    app_joint_qvp_qhat_truth_summary(fixture, pooled_mcmc$qhat_mean, "pooled MCMC", "plot")
  )
  tau_labels <- paste0("tau = ", formatC(fixture$tau, format = "f", digits = 2))
  tau_order <- order(fixture$tau)
  low_k <- tau_order[[1L]]
  high_k <- tau_order[[length(tau_order)]]
  mid_k <- which.min(abs(fixture$tau - stats::median(fixture$tau)))
  truth_cols <- app_joint_qvp_plot_palette(K)
  fit_cols <- c(truth = "#222222", VB = "#0072B2", "pooled MCMC" = "#D55E00")
  fit_lty <- c(truth = 1, VB = 1, "pooled MCMC" = 2)
  vb_fill <- grDevices::adjustcolor(fit_cols[["VB"]], alpha.f = 0.16)
  mc_fill <- grDevices::adjustcolor(fit_cols[["pooled MCMC"]], alpha.f = 0.15)

  overview_range <- range(c(fixture$y, fixture$true_q), finite = TRUE)
  overview_pad <- 0.06 * diff(overview_range)
  if (!is.finite(overview_pad) || overview_pad <= 0) overview_pad <- 1

  app_joint_qvp_png(path, width = 2300, height = 1750, res = 180)
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)

  layout_ids <- c(1L, 1L, seq_len(K) + 1L, K + 2L)
  if (length(layout_ids) %% 2L) layout_ids <- c(layout_ids, 0L)
  layout_matrix <- matrix(layout_ids, ncol = 2L, byrow = TRUE)
  graphics::layout(layout_matrix, heights = c(1.15, rep(1, nrow(layout_matrix) - 1L)))
  graphics::par(oma = c(0, 0, 3.1, 0), mar = c(4.1, 4.4, 2.4, 1.1))

  graphics::plot(x, fixture$y, type = "n",
    ylim = overview_range + c(-overview_pad, overview_pad),
    xlab = "retained time index", ylab = "response / true conditional quantile",
    main = "Truth and observed retained series")
  graphics::grid(col = "grey88")
  if (K >= 2L) {
    graphics::polygon(
      c(x, rev(x)),
      c(fixture$true_q[, low_k], rev(fixture$true_q[, high_k])),
      border = NA,
      col = grDevices::adjustcolor("#8DD3C7", alpha.f = 0.28)
    )
  }
  graphics::points(x, fixture$y, pch = 16, cex = 0.42, col = grDevices::adjustcolor("grey20", alpha.f = 0.68))
  for (k in seq_len(K)) {
    graphics::lines(x, fixture$true_q[, k], col = truth_cols[[k]], lwd = if (k == mid_k) 3 else 2)
  }
  graphics::legend("topleft",
    legend = c("observed y", "true central band", tau_labels),
    col = c("grey20", "#8DD3C7", truth_cols),
    pch = c(16, NA, rep(NA, K)),
    lty = c(NA, 1, rep(1, K)),
    lwd = c(NA, 8, rep(2.5, K)),
    bty = "n",
    cex = 0.82
  )

  for (k in seq_len(K)) {
    y_range <- range(
      fixture$y, fixture$true_q[, k],
      vb_band$lower[, k], vb_band$upper[, k],
      mc_band$lower[, k], mc_band$upper[, k],
      vb_fit$qhat_mean[, k], pooled_mcmc$qhat_mean[, k],
      finite = TRUE
    )
    y_pad <- 0.06 * diff(y_range)
    if (!is.finite(y_pad) || y_pad <= 0) y_pad <- 1
    graphics::plot(x, fixture$y, type = "n",
      ylim = y_range + c(-y_pad, y_pad),
      xlab = "retained time index", ylab = "response / fitted quantile",
      main = tau_labels[[k]])
    graphics::grid(col = "grey88")
    graphics::polygon(c(x, rev(x)), c(vb_band$lower[, k], rev(vb_band$upper[, k])), border = NA, col = vb_fill)
    graphics::polygon(c(x, rev(x)), c(mc_band$lower[, k], rev(mc_band$upper[, k])), border = NA, col = mc_fill)
    graphics::points(x, fixture$y, pch = 16, cex = 0.28, col = grDevices::adjustcolor("grey35", alpha.f = 0.32))
    graphics::lines(x, fixture$true_q[, k], col = fit_cols[["truth"]], lwd = 2.8, lty = fit_lty[["truth"]])
    graphics::lines(x, vb_fit$qhat_mean[, k], col = fit_cols[["VB"]], lwd = 2.2, lty = fit_lty[["VB"]])
    graphics::lines(x, pooled_mcmc$qhat_mean[, k], col = fit_cols[["pooled MCMC"]], lwd = 2.2, lty = fit_lty[["pooled MCMC"]])
    if (k == 1L) {
      graphics::legend("topright",
        legend = c("truth", "VB mean", "VB 95% band", "MCMC mean", "MCMC 95% band"),
        col = c(fit_cols[["truth"]], fit_cols[["VB"]], vb_fill, fit_cols[["pooled MCMC"]], mc_fill),
        lwd = c(2.8, 2.3, 8, 2.3, 8),
        lty = c(1, 1, 1, 2, 1),
        bty = "n",
        cex = 0.78
      )
    }
    vb_row <- metrics[metrics$fit == "VB" & metrics$quantile_index == k, , drop = FALSE]
    mc_row <- metrics[metrics$fit == "pooled MCMC" & metrics$quantile_index == k, , drop = FALSE]
    usr <- graphics::par("usr")
    graphics::text(usr[[1L]] + 0.02 * diff(usr[1:2]), usr[[4L]] - 0.09 * diff(usr[3:4]),
      labels = sprintf("VB RMSE %.2f, bias %.2f, hit %.2f", vb_row$rmse_to_truth, vb_row$mean_error_to_truth, vb_row$empirical_hit_rate),
      adj = c(0, 1), cex = 0.74, col = fit_cols[["VB"]])
    graphics::text(usr[[1L]] + 0.02 * diff(usr[1:2]), usr[[4L]] - 0.17 * diff(usr[3:4]),
      labels = sprintf("MCMC RMSE %.2f, bias %.2f, hit %.2f", mc_row$rmse_to_truth, mc_row$mean_error_to_truth, mc_row$empirical_hit_rate),
      adj = c(0, 1), cex = 0.74, col = fit_cols[["pooled MCMC"]])
  }

  graphics::plot.new()
  graphics::title("Numerical audit with pointwise bands")
  truth_width <- if (K >= 2L) fixture$true_q[, high_k] - fixture$true_q[, low_k] else rep(NA_real_, length(x))
  graphics::text(0, 0.94, "Bands are pointwise 95% intervals for fitted quantile paths", adj = 0, font = 2, cex = 0.9)
  graphics::text(0, 0.86,
    sprintf("VB band: beta covariance with alpha as point mass. MCMC band: pooled retained draws, n = %s.", nrow(pooled_mcmc$beta_draws)),
    adj = 0, cex = 0.64, col = "grey25")
  graphics::text(0, 0.79,
    sprintf("Truth band mean width %.3f; max width %.3f; observed y sd %.3f",
      mean(truth_width, na.rm = TRUE), max(truth_width, na.rm = TRUE), stats::sd(fixture$y)),
    adj = 0, cex = 0.64, col = "grey25")
  header <- sprintf("%-8s %-8s %8s %8s %8s %10s", "tau", "fit", "RMSE", "bias", "hit", "mean width")
  graphics::text(0, 0.70, header, adj = 0, family = "mono", cex = 0.68)
  yy <- 0.63
  for (k in seq_len(K)) {
    for (fit_label in c("VB", "pooled MCMC")) {
      row <- metrics[metrics$fit == fit_label & metrics$quantile_index == k, , drop = FALSE]
      width <- if (fit_label == "VB") mean(vb_band$upper[, k] - vb_band$lower[, k]) else mean(mc_band$upper[, k] - mc_band$lower[, k])
      fit_short <- if (identical(fit_label, "pooled MCMC")) "MCMC" else fit_label
      line <- sprintf("%-8.2f %-8s %8.3f %8.3f %8.3f %10.3f",
        row$tau, fit_short, row$rmse_to_truth, row$mean_error_to_truth, row$empirical_hit_rate, width)
      graphics::text(0, yy, line, adj = 0, family = "mono", cex = 0.64, col = fit_cols[[fit_label]])
      yy <- yy - 0.06
    }
    yy <- yy - 0.025
  }
  graphics::mtext(paste(title, "truth, fitted means, and 95% bands"), outer = TRUE, side = 3, line = 1.1, font = 2, cex = 1.05)
  graphics::mtext("Simulated length 1000; first 500 discarded as washout; retained effective Tn = 500.", outer = TRUE, side = 3, line = -0.35, cex = 0.76, col = "grey30")
  graphics::layout(1L)
  invisible(path)
}

scenario <- app_joint_qvp_default_ts_synthetic_scenarios()
scenario <- scenario[scenario$case_id == "ts_asymmetric_laplace_tail", , drop = FALSE]
if (nrow(scenario) != 1L) stop("Could not find default ts_asymmetric_laplace_tail scenario.", call. = FALSE)
scenario$case_id <- "ts_asymmetric_laplace_tail_T500_washout500"
scenario$Tn <- 1000L
fixture_full <- app_joint_qvp_ts_fixture_from_scenario(scenario)
keep_idx <- 501L:1000L
fixture <- slice_ts_fixture(fixture_full, keep_idx)

case_id <- scenario$case_id[[1L]]
K <- length(fixture$tau)
p <- ncol(fixture$Z)
Tn <- length(fixture$y)
title <- "ts_asymmetric_laplace_tail T500 washout500 asymmetric_laplace"

vb_elapsed <- system.time({
  vb_adaptive <- app_joint_qvp_fit_al_vb_adaptive(
    y = fixture$y,
    Z = fixture$Z,
    tau = fixture$tau,
    vb_max_iter = 180L,
    adaptive_vb_max_iter_grid = c(180L, 360L, 500L),
    tol = 1.0e-4,
    kappa = 1,
    tau0 = 1,
    a_sigma = 2,
    b_sigma = 1,
    alpha_prior_mean = "empirical_quantile",
    alpha_prior_sd = 1,
    rhs_vb_inner = 5L
  )
})[["elapsed"]]
vb_fit <- vb_adaptive$fit
vb_convergence_audit <- cbind(
  data.frame(case_id = case_id, dynamic = fixture$dynamic, likelihood = fixture$likelihood, stringsAsFactors = FALSE),
  vb_adaptive$audit
)
sigma_upper_bound <- max(1, 50 * max(vb_fit$sigma_mean))

n_chains <- 2L
mcmc_n_iter <- 80L
mcmc_burn <- 40L
mcmc_thin <- 5L
fits <- vector("list", n_chains)
chain_seeds <- integer(n_chains)
chain_elapsed <- numeric(n_chains)
draw_rows <- list()
crossing_rows <- list()
for (chain_id in seq_len(n_chains)) {
  chain_seed <- as.integer(scenario$seed[[1L]]) + 1000L + (chain_id - 1L) * 10000L
  chain_seeds[[chain_id]] <- chain_seed
  chain_elapsed[[chain_id]] <- system.time({
    fits[[chain_id]] <- app_joint_qvp_fit_al_mcmc_tiny(
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      n_iter = mcmc_n_iter,
      burn = mcmc_burn,
      thin = mcmc_thin,
      seed = chain_seed,
      kappa = 1,
      tau0 = 1,
      a_sigma = 2,
      b_sigma = 1,
      alpha_prior_mean = "empirical_quantile",
      alpha_prior_sd = 1,
      init = vb_fit,
      max_dense_dim = 100L,
      sigma_bounds = c(1.0e-8, sigma_upper_bound)
    )
  })[["elapsed"]]
  draw_rows[[length(draw_rows) + 1L]] <- cbind(
    data.frame(chain_id = chain_id, chain_seed = chain_seed, stringsAsFactors = FALSE),
    app_joint_qvp_mcmc_draw_summary(
      fits[[chain_id]],
      case_id,
      "ts_asymmetric_laplace_T500_washout",
      fixture$dynamic,
      sigma_bounds = c(1.0e-8, sigma_upper_bound)
    )
  )
  crossing_rows[[length(crossing_rows) + 1L]] <- cbind(
    data.frame(case_id = case_id, fit = sprintf("chain_%s", chain_id), chain_id = chain_id, stringsAsFactors = FALSE),
    fits[[chain_id]]$crossing_diagnostics
  )
}
pool_elapsed <- system.time({
  pooled <- app_joint_qvp_pool_mcmc_chains(fits, fixture$Z, K, p, fixture$tau)
})[["elapsed"]]

truth_fit_summary <- rbind(
  app_joint_qvp_qhat_truth_summary(fixture, fixture$true_q, "truth", case_id),
  app_joint_qvp_qhat_truth_summary(fixture, vb_fit$qhat_mean, "vb", case_id),
  app_joint_qvp_qhat_truth_summary(fixture, pooled$qhat_mean, "pooled_mcmc", case_id)
)
tau_order <- order(fixture$tau)
low_k <- tau_order[[1L]]
high_k <- tau_order[[length(tau_order)]]
coverage_band_summary <- rbind(
  app_joint_qvp_band_summary_row(fixture, "truth", fixture$true_q[, low_k], fixture$true_q[, high_k]),
  app_joint_qvp_band_summary_row(fixture, "vb", vb_fit$qhat_mean[, low_k], vb_fit$qhat_mean[, high_k]),
  app_joint_qvp_band_summary_row(fixture, "pooled_mcmc", pooled$qhat_mean[, low_k], pooled$qhat_mean[, high_k])
)
readout_truth_summary <- rbind(
  app_joint_qvp_readout_truth_summary(fixture, vb_fit, "vb", case_id),
  app_joint_qvp_readout_truth_summary(fixture, pooled, "pooled_mcmc", case_id)
)
vb_mcmc_distance_summary <- app_joint_qvp_vb_mcmc_distance_summary(
  vb_fit = vb_fit,
  mcmc_fit = pooled,
  case_id = case_id,
  stress_case = "ts_asymmetric_laplace_T500_washout",
  scenario = fixture$dynamic,
  Tn = Tn,
  p = p,
  K = K
)
chain_summary <- app_joint_qvp_chain_to_pooled_summary(
  fits = fits,
  pooled_fit = pooled,
  Z = fixture$Z,
  case_id = case_id,
  stress_case = "ts_asymmetric_laplace_T500_washout",
  scenario = fixture$dynamic,
  Tn = Tn,
  p = p,
  K = K
)
chain_summary$chain_seed <- chain_seeds[chain_summary$chain_id]
draw_summary <- do.call(rbind, draw_rows)
sigma_draw_rows <- draw_summary[draw_summary$block == "sigma", , drop = FALSE]
max_sigma_upper_hit <- if (nrow(sigma_draw_rows)) max(sigma_draw_rows$upper_bound_hit_fraction, na.rm = TRUE) else NA_real_

vb_crossing <- cbind(data.frame(case_id = case_id, fit = "vb", chain_id = NA_integer_, stringsAsFactors = FALSE), vb_fit$crossing_diagnostics)
pooled_crossing <- cbind(data.frame(case_id = case_id, fit = "pooled_mcmc", chain_id = NA_integer_, stringsAsFactors = FALSE), pooled$crossing_diagnostics)
crossing_summary <- do.call(rbind, c(crossing_rows, list(vb_crossing, pooled_crossing)))
objective_diagnostics <- cbind(
  data.frame(case_id = case_id, dynamic = fixture$dynamic, likelihood = fixture$likelihood, stringsAsFactors = FALSE),
  vb_fit$objective_diagnostics
)
final_elbo_terms <- vb_fit$elbo_terms[vb_fit$elbo_terms$iter == max(vb_fit$elbo_terms$iter), , drop = FALSE]
elbo_terms <- cbind(
  data.frame(case_id = case_id, dynamic = fixture$dynamic, likelihood = fixture$likelihood, stringsAsFactors = FALSE),
  final_elbo_terms
)

runtime_summary <- rbind(
  data.frame(component = "VB adaptive", elapsed_sec = vb_elapsed, n_iter = nrow(vb_fit$trace), sec_per_iter = vb_elapsed / nrow(vb_fit$trace), n_chains = NA_integer_, n_keep_total = NA_integer_, stringsAsFactors = FALSE),
  data.frame(component = "MCMC chain 1", elapsed_sec = chain_elapsed[[1L]], n_iter = mcmc_n_iter, sec_per_iter = chain_elapsed[[1L]] / mcmc_n_iter, n_chains = 1L, n_keep_total = nrow(fits[[1L]]$beta_draws), stringsAsFactors = FALSE),
  data.frame(component = "MCMC chain 2", elapsed_sec = chain_elapsed[[2L]], n_iter = mcmc_n_iter, sec_per_iter = chain_elapsed[[2L]] / mcmc_n_iter, n_chains = 1L, n_keep_total = nrow(fits[[2L]]$beta_draws), stringsAsFactors = FALSE),
  data.frame(component = "MCMC pooled total", elapsed_sec = sum(chain_elapsed) + pool_elapsed, n_iter = n_chains * mcmc_n_iter, sec_per_iter = (sum(chain_elapsed) + pool_elapsed) / (n_chains * mcmc_n_iter), n_chains = n_chains, n_keep_total = nrow(pooled$beta_draws), stringsAsFactors = FALSE)
)
runtime_summary$case_id <- case_id
runtime_summary$Tn <- Tn
runtime_summary$p <- p
runtime_summary$K <- K

fit_summary <- data.frame(
  case_id = case_id,
  dynamic = fixture$dynamic,
  likelihood = fixture$likelihood,
  seed = as.integer(scenario$seed[[1L]]),
  simulated_Tn = length(fixture_full$y),
  washout = 500L,
  retained_Tn = Tn,
  p = p,
  K = K,
  tau = paste(fixture$tau, collapse = ","),
  kappa = 1,
  vb_status = vb_fit$manifest$status[[1L]],
  vb_converged = isTRUE(vb_fit$converged),
  vb_n_iter = nrow(vb_fit$trace),
  vb_max_iter_grid = paste(vb_adaptive$grid, collapse = ","),
  vb_max_iter_used = max(vb_convergence_audit$max_iter),
  vb_retry_count = max(vb_convergence_audit$attempt) - 1L,
  vb_final_max_beta_change = tail(vb_fit$trace$max_beta_change, 1L),
  objective_status = vb_fit$objective_diagnostics$objective_status[[1L]],
  n_chains = n_chains,
  mcmc_n_iter = mcmc_n_iter,
  mcmc_burn = mcmc_burn,
  mcmc_thin = mcmc_thin,
  mcmc_n_keep_total = nrow(pooled$beta_draws),
  mcmc_init_source = pooled$init_source,
  sigma_upper_bound = sigma_upper_bound,
  max_sigma_upper_bound_hit_fraction = max_sigma_upper_hit,
  vb_truth_normalized_qhat_distance = app_joint_qvp_qhat_truth_distance(fixture, vb_fit$qhat_mean),
  pooled_mcmc_truth_normalized_qhat_distance = app_joint_qvp_qhat_truth_distance(fixture, pooled$qhat_mean),
  vb_mcmc_max_normalized_distance = vb_mcmc_distance_summary$max_normalized_distance[[1L]],
  max_chain_to_pooled_normalized_distance = max(chain_summary$max_normalized_to_pooled, na.rm = TRUE),
  max_abs_vb_hit_rate_error = max(abs(truth_fit_summary$hit_rate_minus_tau[truth_fit_summary$fit == "vb"])),
  max_abs_pooled_mcmc_hit_rate_error = max(abs(truth_fit_summary$hit_rate_minus_tau[truth_fit_summary$fit == "pooled_mcmc"])),
  total_vb_crossing_pairs = sum(vb_fit$crossing_diagnostics$n_crossing_pairs),
  total_pooled_mcmc_crossing_pairs = sum(pooled$crossing_diagnostics$n_crossing_pairs),
  all_chain_draws_finite = all(draw_summary$all_finite),
  vb_elapsed_sec = vb_elapsed,
  mcmc_elapsed_sec = sum(chain_elapsed) + pool_elapsed,
  total_elapsed_sec = vb_elapsed + sum(chain_elapsed) + pool_elapsed,
  stringsAsFactors = FALSE
)

run_config <- data.frame(
  case_id = case_id,
  source_case_id = "ts_asymmetric_laplace_tail",
  simulated_Tn = length(fixture_full$y),
  washout = 500L,
  retained_Tn = Tn,
  keep_start = keep_idx[[1L]],
  keep_end = keep_idx[[length(keep_idx)]],
  seed = as.integer(scenario$seed[[1L]]),
  tau = paste(fixture$tau, collapse = ","),
  innovation = scenario$innovation[[1L]],
  al_tau = as.numeric(scenario$al_tau[[1L]]),
  df = as.numeric(scenario$df[[1L]]),
  period = as.integer(scenario$period[[1L]]),
  location_intercept = as.numeric(scenario$location_intercept[[1L]]),
  scale_intercept = as.numeric(scenario$scale_intercept[[1L]]),
  beta_location = scenario$beta_location[[1L]],
  beta_scale = scenario$beta_scale[[1L]],
  kappa = 1,
  vb_max_iter = 180L,
  adaptive_vb_max_iter_grid = "180,360,500",
  mcmc_n_iter = mcmc_n_iter,
  mcmc_burn = mcmc_burn,
  mcmc_thin = mcmc_thin,
  n_chains = n_chains,
  stringsAsFactors = FALSE
)

figure_paths <- c(
  fit_overlay = file.path(out_dir, paste0(case_id, "_fit_overlay.png")),
  fit_overlay_95_bands = file.path(out_dir, paste0(case_id, "_fit_overlay_95_bands.png")),
  error_hit = file.path(out_dir, paste0(case_id, "_error_hit.png")),
  extreme_coverage_bands = file.path(out_dir, paste0(case_id, "_extreme_coverage_bands.png")),
  coverage_band_comparison = file.path(out_dir, paste0(case_id, "_coverage_band_comparison.png")),
  elbo_trace = file.path(out_dir, paste0(case_id, "_elbo_trace.png")),
  parameter_traces = file.path(out_dir, paste0(case_id, "_parameter_traces.png"))
)
app_joint_qvp_plot_ts_fit_overlay(fixture, vb_fit, pooled, figure_paths[["fit_overlay"]], title)
plot_ts_fit_overlay_bands(fixture, vb_fit, pooled, figure_paths[["fit_overlay_95_bands"]], title)
app_joint_qvp_plot_ts_error_hit(fixture, vb_fit, pooled, figure_paths[["error_hit"]], title)
plot_ts_extreme_coverage_bands(fixture, vb_fit, pooled, figure_paths[["extreme_coverage_bands"]], title)
plot_ts_coverage_band_comparison(fixture, vb_fit, pooled, figure_paths[["coverage_band_comparison"]], title)
app_joint_qvp_plot_ts_elbo(vb_fit, figure_paths[["elbo_trace"]], title)
app_joint_qvp_plot_ts_mcmc_traces(fits, fixture$tau, figure_paths[["parameter_traces"]], title)
figure_manifest <- data.frame(
  label = names(figure_paths),
  relative_path = basename(figure_paths),
  size_bytes = as.numeric(file.info(figure_paths)$size),
  sha256 = vapply(figure_paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)

html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub('"', "&quot;", x, fixed = TRUE)
}
generated <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
readme_path <- file.path(out_dir, "README.md")
writeLines(c(
  "# Joint QVP T500 Washout Asymmetric-Laplace Review",
  "",
  sprintf("Generated: %s", generated),
  "",
  "Design:",
  "- DGP: default `ts_asymmetric_laplace_tail` scenario.",
  "- Simulated length: 1000.",
  "- Washout discarded: first 500 observations.",
  "- Retained effective sample size: 500.",
  "",
  "Open `index.html` to browse the figures."
), readme_path)
html_blocks <- unlist(lapply(seq_len(nrow(figure_manifest)), function(ii) {
  row <- figure_manifest[ii, , drop = FALSE]
  c(
    "<section>",
    sprintf("<h2>%s</h2>", html_escape(row$label)),
    sprintf("<p><code>%s</code><br><code>%s</code></p>", html_escape(row$relative_path), html_escape(row$sha256)),
    sprintf("<img src=\"%s\" alt=\"%s\">", html_escape(row$relative_path), html_escape(row$label)),
    "</section>"
  )
}), use.names = FALSE)
html_path <- file.path(out_dir, "index.html")
writeLines(c(
  "<!doctype html>",
  "<html lang=\"en\">",
  "<head>",
  "<meta charset=\"utf-8\">",
  "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
  "<title>Joint QVP T500 Washout Review</title>",
  "<style>",
  "body{font-family:Arial,sans-serif;margin:24px;background:#f7f7f4;color:#1f2328;}",
  "main{max-width:1280px;margin:0 auto;}",
  "section{margin:28px 0;padding-bottom:28px;border-bottom:1px solid #d8d8d2;}",
  "h1{font-size:28px;margin-bottom:4px;}h2{font-size:18px;margin-bottom:8px;}",
  "p{font-size:13px;line-height:1.45;color:#3f454d;}code{font-size:12px;}",
  "img{display:block;width:100%;height:auto;background:white;border:1px solid #d8d8d2;}",
  "</style>",
  "</head>",
  "<body><main>",
  "<h1>Joint QVP T500 Washout Review</h1>",
  sprintf("<p>Generated %s. Simulated length 1000, washout 500, retained Tn 500.</p>", html_escape(generated)),
  html_blocks,
  "</main></body></html>"
), html_path)

paths <- c(
  run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
  fit_summary = app_joint_qvp_write_csv(fit_summary, file.path(out_dir, "fit_summary.csv")),
  truth_fit_summary = app_joint_qvp_write_csv(truth_fit_summary, file.path(out_dir, "truth_fit_summary.csv")),
  coverage_band_summary = app_joint_qvp_write_csv(coverage_band_summary, file.path(out_dir, "coverage_band_summary.csv")),
  readout_truth_summary = app_joint_qvp_write_csv(readout_truth_summary, file.path(out_dir, "readout_truth_summary.csv")),
  vb_mcmc_distance_summary = app_joint_qvp_write_csv(vb_mcmc_distance_summary, file.path(out_dir, "vb_mcmc_distance_summary.csv")),
  chain_summary = app_joint_qvp_write_csv(chain_summary, file.path(out_dir, "chain_summary.csv")),
  mcmc_draw_summary = app_joint_qvp_write_csv(draw_summary, file.path(out_dir, "mcmc_draw_summary.csv")),
  crossing_summary = app_joint_qvp_write_csv(crossing_summary, file.path(out_dir, "crossing_summary.csv")),
  vb_convergence_audit = app_joint_qvp_write_csv(vb_convergence_audit, file.path(out_dir, "vb_convergence_audit.csv")),
  objective_diagnostics = app_joint_qvp_write_csv(objective_diagnostics, file.path(out_dir, "objective_diagnostics.csv")),
  elbo_terms = app_joint_qvp_write_csv(elbo_terms, file.path(out_dir, "elbo_terms.csv")),
  runtime_summary = app_joint_qvp_write_csv(runtime_summary, file.path(out_dir, "runtime_summary.csv")),
  figure_manifest = app_joint_qvp_write_csv(figure_manifest, file.path(out_dir, "figure_manifest.csv")),
  readme = normalizePath(readme_path, mustWork = TRUE),
  index_html = normalizePath(html_path, mustWork = TRUE),
  provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
  figure_paths
)
manifest <- data.frame(
  label = names(paths),
  relative_path = basename(paths),
  size_bytes = as.numeric(file.info(paths)$size),
  sha256 = vapply(paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))

cat(sprintf("Joint-QVP T500 washout asymmetric-Laplace review written to %s\n", out_dir))
cat(sprintf("Artifact manifest: %s\n", manifest_path))
cat("Fit summary:\n")
print(fit_summary[, c(
  "case_id",
  "simulated_Tn",
  "washout",
  "retained_Tn",
  "vb_status",
  "vb_converged",
  "vb_n_iter",
  "vb_retry_count",
  "mcmc_n_keep_total",
  "vb_truth_normalized_qhat_distance",
  "pooled_mcmc_truth_normalized_qhat_distance",
  "vb_mcmc_max_normalized_distance",
  "max_abs_vb_hit_rate_error",
  "max_abs_pooled_mcmc_hit_rate_error",
  "vb_elapsed_sec",
  "mcmc_elapsed_sec",
  "total_elapsed_sec"
)], row.names = FALSE)
