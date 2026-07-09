#!/usr/bin/env Rscript

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
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))

args <- app_parse_args(list(
  artifact_dir = "application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4e_targeted_crossing_followup_vb480",
  output_dir = "",
  scenario_ids = ""
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_csv <- function(x) {
  out <- trimws(strsplit(as.character(x), ",", fixed = TRUE)[[1L]])
  out[nzchar(out)]
}

read_required <- function(dir, filename) {
  path <- file.path(dir, filename)
  if (!file.exists(path)) stop(sprintf("Missing required overlay input: %s", path), call. = FALSE)
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

repo_rel <- function(path) app_prefer_repo_relative_path(normalizePath(path, mustWork = TRUE))

write_png <- function(path, width = 2200L, height = 1400L, res = 170L, code) {
  png_type <- if (isTRUE(capabilities("cairo"))) "cairo" else "cairo-png"
  grDevices::png(path, width = width, height = height, res = res, type = png_type)
  on.exit(grDevices::dev.off(), add = TRUE)
  force(code)
  normalizePath(path, mustWork = TRUE)
}

short_id <- function(x) {
  x <- sub("__calibration_r[0-9]+$", "", as.character(x))
  gsub("_", " ", x, fixed = TRUE)
}

safe_range <- function(...) {
  vals <- unlist(list(...), use.names = FALSE)
  vals <- vals[is.finite(vals)]
  if (!length(vals)) return(c(-1, 1))
  rng <- range(vals)
  if (diff(rng) <= 0) rng <- rng + c(-0.5, 0.5)
  pad <- 0.08 * diff(rng)
  rng + c(-pad, pad)
}

truth_wide_for_scenario <- function(truth, scenario_id) {
  x <- truth[truth$scenario_id == scenario_id & truth$split %in% c("train", "test"), , drop = FALSE]
  x <- x[order(x$time_index, x$tau), , drop = FALSE]
  taus <- sort(unique(as.numeric(x$tau)))
  base <- unique(x[, c("scenario_id", "time_index", "split", "split_index", "retained_time_index"), drop = FALSE])
  base <- base[order(base$time_index), , drop = FALSE]
  for (tau in taus) {
    vals <- x$true_quantile[as.numeric(x$tau) == tau]
    base[[sprintf("q_%0.2f", tau)]] <- vals
  }
  attr(base, "tau") <- taus
  base
}

qcol <- function(tau) sprintf("q_%0.2f", tau)

plot_overlay <- function(
  scenario_id,
  obs,
  truth,
  fit,
  raw_fit = NULL,
  adjustment = NULL,
  crossing_pairs = NULL,
  overview = FALSE
) {
  obs_sc <- obs[obs$scenario_id == scenario_id & obs$split %in% c("train", "test"), , drop = FALSE]
  obs_sc <- obs_sc[order(obs_sc$time_index), , drop = FALSE]
  truth_w <- truth_wide_for_scenario(truth, scenario_id)
  fit_sc <- fit[fit$scenario_id == scenario_id, , drop = FALSE]
  raw_sc <- if (!is.null(raw_fit)) raw_fit[raw_fit$scenario_id == scenario_id, , drop = FALSE] else NULL
  tau <- attr(truth_w, "tau")
  tau <- tau[is.finite(tau)]
  fit_taus <- sort(unique(as.numeric(fit_sc$tau)))
  lower_outer <- min(tau)
  upper_outer <- max(tau)
  inner_pair <- c(0.10, 0.90)
  if (!all(inner_pair %in% tau)) inner_pair <- c(0.25, 0.75)
  median_tau <- if (0.50 %in% tau) 0.50 else tau[ceiling(length(tau) / 2)]
  plot_taus <- if (overview) intersect(c(lower_outer, inner_pair, median_tau, upper_outer), fit_taus) else fit_taus
  plot_taus <- sort(unique(plot_taus))
  yr <- safe_range(
    obs_sc$y,
    unlist(truth_w[paste0("q_", sprintf("%0.2f", tau))], use.names = FALSE),
    fit_sc$qhat
  )
  graphics::plot(
    obs_sc$time_index,
    obs_sc$y,
    type = "n",
    ylim = yr,
    xlab = "time index",
    ylab = "y / quantile",
    main = if (overview) short_id(scenario_id) else sprintf("%s: data, true quantiles, and fitted forecast quantiles", short_id(scenario_id))
  )
  test_start <- min(obs_sc$time_index[obs_sc$split == "test"], na.rm = TRUE)
  graphics::grid(col = "#E5E7EB")
  graphics::abline(v = test_start, col = "#374151", lty = 3)
  truth_cols <- grDevices::colorRampPalette(c("#1E40AF", "#2563EB", "#0891B2", "#111827", "#059669", "#7C3AED", "#6D28D9"))(length(tau))
  names(truth_cols) <- sprintf("%0.2f", tau)
  for (tt in tau) {
    graphics::lines(
      truth_w$time_index,
      truth_w[[qcol(tt)]],
      col = grDevices::adjustcolor(truth_cols[[sprintf("%0.2f", tt)]], alpha.f = if (overview) 0.42 else 0.58),
      lwd = if (tt == median_tau) 1.8 else if (tt %in% c(lower_outer, upper_outer)) 1.2 else 0.95,
      lty = 1
    )
  }
  train <- obs_sc[obs_sc$split == "train", , drop = FALSE]
  test <- obs_sc[obs_sc$split == "test", , drop = FALSE]
  graphics::points(train$time_index, train$y, pch = 16, cex = if (overview) 0.24 else 0.34, col = grDevices::adjustcolor("#6B7280", alpha.f = 0.42))
  graphics::points(test$time_index, test$y, pch = 16, cex = if (overview) 0.30 else 0.43, col = grDevices::adjustcolor("#111827", alpha.f = 0.70))
  fit_cols <- grDevices::colorRampPalette(c("#7F1D1D", "#F97316", "#16A34A", "#0F766E", "#7C3AED"))(max(3L, length(plot_taus)))
  names(fit_cols) <- sprintf("%0.2f", plot_taus)
  for (tt in plot_taus) {
    f <- fit_sc[as.numeric(fit_sc$tau) == tt, , drop = FALSE]
    f <- f[order(f$forecast_time_index), , drop = FALSE]
    col <- fit_cols[[sprintf("%0.2f", tt)]]
    graphics::lines(f$forecast_time_index, f$qhat, col = col, lwd = if (tt == median_tau) 2.3 else 1.7)
    graphics::points(f$forecast_time_index, f$qhat, pch = 21, bg = "white", col = col, cex = if (overview) 0.42 else 0.58, lwd = 1.1)
  }

  if (!is.null(crossing_pairs) && nrow(crossing_pairs)) {
    cp <- crossing_pairs[crossing_pairs$scenario_id == scenario_id, , drop = FALSE]
    if (nrow(cp)) {
      segment_half_width <- if (overview) 8 else 14
      for (ii in seq_len(nrow(cp))) {
        y_lower <- cp$raw_lower_qhat[[ii]]
        y_upper <- cp$raw_upper_qhat[[ii]]
        if (!is.finite(y_lower) || !is.finite(y_upper)) next
        x_mid <- cp$forecast_time_index[[ii]]
        x0 <- cp$forecast_time_index[[ii]] - segment_half_width
        x1 <- cp$forecast_time_index[[ii]] + segment_half_width
        graphics::segments(
          x0 = x0,
          x1 = x_mid,
          y0 = y_lower,
          y1 = y_lower,
          col = grDevices::adjustcolor("#DC2626", alpha.f = if (overview) 0.80 else 0.95),
          lwd = if (overview) 1.8 else 2.6,
          lty = 2
        )
        graphics::segments(
          x0 = x_mid,
          x1 = x1,
          y0 = y_upper,
          y1 = y_upper,
          col = grDevices::adjustcolor("#DC2626", alpha.f = if (overview) 0.80 else 0.95),
          lwd = if (overview) 1.8 else 2.6,
          lty = 2
        )
        graphics::segments(
          x0 = x_mid,
          x1 = x_mid,
          y0 = y_upper,
          y1 = y_lower,
          col = grDevices::adjustcolor("#DC2626", alpha.f = if (overview) 0.65 else 0.85),
          lwd = if (overview) 1.1 else 1.6,
          lty = 3
        )
      }
    }
  }
  graphics::box()
  if (!overview) {
    graphics::legend(
      "topleft",
      legend = c(
        "true quantile dynamics",
        "train data",
        "test data",
        "contract fit",
        "raw crossing level"
      ),
      col = c("#2563EB", "#6B7280", "#111827", "#F97316", "#DC2626"),
      pch = c(NA, 16, 16, 21, NA),
      lty = c(1, NA, NA, 1, 2),
      pt.bg = c(NA, "#6B7280", "#111827", "white", NA),
      bty = "n",
      cex = 0.78
    )
  }
}

plot_crossing_ladders <- function(crossing_pairs, max_events = 24L) {
  cp <- crossing_pairs[order(-crossing_pairs$crossing_magnitude), , drop = FALSE]
  cp <- cp[seq_len(min(max_events, nrow(cp))), , drop = FALSE]
  if (!nrow(cp)) {
    graphics::plot.new()
    graphics::text(0.5, 0.5, "No raw crossings in crossing_pair_detail.csv")
    return(invisible(NULL))
  }
  n_col <- 4L
  n_row <- ceiling(nrow(cp) / n_col)
  old <- graphics::par(mfrow = c(n_row, n_col), mar = c(4.2, 4.1, 3.0, 1), oma = c(0, 0, 2.2, 0), las = 1)
  on.exit(graphics::par(old), add = TRUE)
  for (ii in seq_len(nrow(cp))) {
    row <- cp[ii, , drop = FALSE]
    tau_pair <- c(row$lower_tau[[1L]], row$upper_tau[[1L]])
    raw <- c(row$raw_lower_qhat[[1L]], row$raw_upper_qhat[[1L]])
    contract <- c(row$contract_lower_qhat[[1L]], row$contract_upper_qhat[[1L]])
    truth <- c(row$true_lower_quantile[[1L]], row$true_upper_quantile[[1L]])
    yr <- safe_range(raw, contract, truth)
    graphics::plot(
      tau_pair,
      raw,
      type = "n",
      xlim = range(tau_pair) + c(-0.015, 0.015),
      ylim = yr,
      xaxt = "n",
      xlab = "adjacent tau pair",
      ylab = "quantile value",
      main = sprintf(
        "%s\norigin %s, t=%s, mag=%.3f",
        short_id(row$scenario_id[[1L]]),
        row$origin_index[[1L]],
        row$forecast_time_index[[1L]],
        row$crossing_magnitude[[1L]]
      )
    )
    graphics::axis(1, at = tau_pair, labels = sprintf("%.2f", tau_pair))
    graphics::grid(col = "#E5E7EB")
    graphics::lines(tau_pair, truth, type = "b", pch = 17, col = "#111827", lwd = 1.6)
    graphics::lines(tau_pair, contract, type = "b", pch = 15, col = "#059669", lwd = 2.0)
    graphics::lines(tau_pair, raw, type = "b", pch = 16, col = "#DC2626", lwd = 2.8, lty = 2)
    graphics::segments(
      tau_pair[[1L]],
      raw[[1L]],
      tau_pair[[2L]],
      raw[[2L]],
      col = "#DC2626",
      lwd = 4,
      lty = 2
    )
    graphics::mtext(
      sprintf("%.2f raw %.3f > %.2f raw %.3f", tau_pair[[1L]], raw[[1L]], tau_pair[[2L]], raw[[2L]]),
      side = 3,
      line = -1.0,
      cex = 0.72,
      col = "#991B1B"
    )
    if (ii == 1L) {
      graphics::legend(
        "bottomleft",
        legend = c("raw crossed", "contract", "truth"),
        col = c("#DC2626", "#059669", "#111827"),
        pch = c(16, 15, 17),
        lty = c(2, 1, 1),
        lwd = c(2.8, 2.0, 1.6),
        bty = "n",
        cex = 0.75
      )
    }
  }
  if (nrow(cp) < n_row * n_col) {
    for (ii in seq_len(n_row * n_col - nrow(cp))) graphics::plot.new()
  }
  graphics::mtext("Raw crossing ladder panels: each red dashed segment slopes downward across an increasing tau pair", outer = TRUE, cex = 1.1, font = 2)
}

artifact_dir <- normalizePath(as.character(arg_value("artifact_dir"))[[1L]], mustWork = TRUE)
fixture_dir <- file.path(artifact_dir, "phase1_fixtures")
out_dir <- if (nzchar(as.character(arg_value("output_dir")))) {
  as.character(arg_value("output_dir"))
} else {
  file.path(artifact_dir, "phase4f_data_truth_fit_overlays")
}
out_dir <- normalizePath(out_dir, mustWork = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

obs <- read_required(fixture_dir, "observed_series.csv")
truth <- read_required(fixture_dir, "true_quantile_long.csv")
fit <- read_required(artifact_dir, "forecast_quantiles.csv")
raw_fit <- read_required(artifact_dir, "forecast_quantiles_raw.csv")
adjustment <- read_required(artifact_dir, "forecast_monotone_adjustment.csv")
raw_crossing <- read_required(artifact_dir, "raw_crossing_summary.csv")
contract_crossing <- read_required(artifact_dir, "crossing_summary.csv")
crossing_pairs_path <- file.path(artifact_dir, "phase4e_crossing_audit", "crossing_pair_detail.csv")
crossing_pairs <- if (file.exists(crossing_pairs_path)) {
  utils::read.csv(crossing_pairs_path, stringsAsFactors = FALSE, check.names = FALSE)
} else {
  data.frame(
    scenario_id = character(),
    forecast_time_index = integer(),
    lower_tau = numeric(),
    upper_tau = numeric(),
    raw_lower_qhat = numeric(),
    raw_upper_qhat = numeric(),
    stringsAsFactors = FALSE
  )
}

scenario_ids <- parse_csv(arg_value("scenario_ids"))
if (!length(scenario_ids)) scenario_ids <- unique(as.character(fit$scenario_id))
scenario_ids <- scenario_ids[scenario_ids %in% unique(as.character(fit$scenario_id))]
if (!length(scenario_ids)) stop("No requested scenario ids were found in forecast_quantiles.csv.", call. = FALSE)

plot_paths <- list()
plot_paths[["00_overview_data_truth_fit_overlay"]] <- write_png(
  file.path(out_dir, "00_overview_data_truth_fit_overlay.png"),
  width = 2400L,
  height = 2600L,
  code = {
    old <- graphics::par(mfrow = c(ceiling(length(scenario_ids) / 2), 2), mar = c(4.2, 4.2, 3.2, 1), las = 1)
    on.exit(graphics::par(old), add = TRUE)
    for (sid in scenario_ids) {
      plot_overlay(
        sid,
        obs,
        truth,
        fit,
        raw_fit = raw_fit,
        adjustment = adjustment,
        crossing_pairs = crossing_pairs,
        overview = TRUE
      )
    }
    if (length(scenario_ids) %% 2 == 1) graphics::plot.new()
  }
)

plot_paths[["01_raw_crossing_ladder_panels"]] <- write_png(
  file.path(out_dir, "01_raw_crossing_ladder_panels.png"),
  width = 2400L,
  height = 3400L,
  code = {
    plot_crossing_ladders(crossing_pairs, max_events = 24L)
  }
)

for (sid in scenario_ids) {
  file_id <- gsub("[^A-Za-z0-9]+", "_", sid)
  plot_paths[[paste0("scenario_", file_id)]] <- write_png(
    file.path(out_dir, sprintf("scenario_%s_data_truth_fit_overlay.png", file_id)),
    width = 2300L,
    height = 1350L,
    code = {
      old <- graphics::par(mar = c(5, 5.5, 4, 1), las = 1)
      on.exit(graphics::par(old), add = TRUE)
      plot_overlay(
        sid,
        obs,
        truth,
        fit,
        raw_fit = raw_fit,
        adjustment = adjustment,
        crossing_pairs = crossing_pairs,
        overview = FALSE
      )
      graphics::mtext("Fit = Phase 4e stronger-VB contract forecast quantiles; red dashed horizontal segments mark raw crossing levels", side = 3, line = 0.3, cex = 0.85)
    }
  )
}

scenario_summary <- do.call(rbind, lapply(scenario_ids, function(sid) {
  o <- obs[obs$scenario_id == sid & obs$split %in% c("train", "test"), , drop = FALSE]
  f <- fit[fit$scenario_id == sid, , drop = FALSE]
  a <- adjustment[adjustment$scenario_id == sid, , drop = FALSE]
  r <- raw_crossing[raw_crossing$scenario_id == sid, , drop = FALSE]
  c <- contract_crossing[contract_crossing$scenario_id == sid, , drop = FALSE]
  data.frame(
    scenario_id = sid,
    n_train = sum(o$split == "train"),
    n_test = sum(o$split == "test"),
    n_forecast_origins = length(unique(f$origin_index)),
    tau_grid = paste(format(sort(unique(as.numeric(f$tau))), trim = TRUE), collapse = ","),
    mean_abs_truth_error = mean(f$abs_truth_error, na.rm = TRUE),
    max_abs_truth_error = max(f$abs_truth_error, na.rm = TRUE),
    raw_crossing_pairs = if (nrow(r)) sum(r$n_crossing_pairs, na.rm = TRUE) else NA_real_,
    contract_crossing_pairs = if (nrow(c)) sum(c$n_crossing_pairs, na.rm = TRUE) else NA_real_,
    adjusted_origins = sum(a$n_adjusted_quantiles > 0, na.rm = TRUE),
    crossing_pair_markers = sum(crossing_pairs$scenario_id == sid, na.rm = TRUE),
    max_abs_monotone_adjustment = max(a$max_abs_adjustment, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}))

plot_index <- data.frame(
  figure = basename(unlist(plot_paths, use.names = FALSE)),
  label = names(plot_paths),
  relative_path = vapply(plot_paths, repo_rel, character(1L)),
  sha256 = vapply(plot_paths, app_sha256_file, character(1L)),
  description = c(
    "Overview panels for all plotted scenarios with observed data, true quantile dynamics, fitted contract quantiles, and red crossing-level markers.",
    "Raw crossing ladder panels showing adjacent tau-pair reversals directly; red raw segments slope downward when lower-tau qhat exceeds upper-tau qhat.",
    rep("Individual scenario overlay with observed data, true quantile dynamics, contract fit, and red dashed raw crossing-level markers.", length(scenario_ids))
  ),
  stringsAsFactors = FALSE
)

readme_path <- file.path(out_dir, "README.md")
writeLines(c(
  "# Joint-QVP Phase 4f Data / Truth / Fit Overlays",
  "",
  "These plots overlay observed data, oracle true conditional quantile dynamics, and fitted Phase 4e stronger-VB contract forecast quantiles.",
  "",
  "Interpretation guide:",
  "",
  "- Gray points: train observations.",
  "- Black points: held-out test observations.",
  "- Blue/purple/green lines: true conditional quantile dynamics from the synthetic DGP fixture.",
  "- Colored points/lines: fitted forecast quantiles at rolling-origin test rows.",
  "- Red dashed horizontal segments: raw crossing levels from adjacent crossing-pair diagnostics.",
  "",
  "Primary files:",
  "",
  "- `00_overview_data_truth_fit_overlay.png`: compact overview across scenarios.",
  "- `01_raw_crossing_ladder_panels.png`: direct adjacent-pair raw crossing evidence.",
  "- `scenario_*_data_truth_fit_overlay.png`: individual scenario overlays.",
  "- `phase4f_data_truth_fit_summary.csv`: numerical summary.",
  "- `phase4f_data_truth_fit_plot_index.csv`: figure index with hashes.",
  "- `artifact_manifest.csv`: reproducibility manifest."
), readme_path, useBytes = TRUE)

paths <- c(
  plot_index = app_joint_qvp_write_csv(plot_index, file.path(out_dir, "phase4f_data_truth_fit_plot_index.csv")),
  summary = app_joint_qvp_write_csv(scenario_summary, file.path(out_dir, "phase4f_data_truth_fit_summary.csv")),
  provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
  readme = normalizePath(readme_path, mustWork = TRUE),
  unlist(plot_paths, use.names = TRUE)
)
manifest <- data.frame(
  label = names(paths),
  relative_path = basename(paths),
  size_bytes = as.numeric(file.info(paths)$size),
  sha256 = vapply(paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))

cat(sprintf("Joint-QVP data/truth/fit overlays written to %s\n", out_dir))
cat(sprintf("Scenarios: %s\n", length(scenario_ids)))
cat(sprintf("Figures: %s\n", length(plot_paths)))
cat(sprintf("Artifact manifest: %s\n", manifest_path))
