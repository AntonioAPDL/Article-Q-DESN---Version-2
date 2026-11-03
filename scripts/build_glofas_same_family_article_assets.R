#!/usr/bin/env Rscript
# Presentation derivatives of authenticated small post-fit CSV/JSON packets only.
# No model object, feature callback, sampler or scientific fitting is used here.
source("scripts/build_glofas_same_family_article_projection.R")
source("scripts/glofas_same_family_publication_metrics.R")

gsaa_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS article assets: ", why), call. = FALSE)
  invisible(TRUE)
}

gsaa_prefix <- function() "glofas_same_family_20261103"
gsaa_decision_relative <- function() paste0("tables/", gsaa_prefix(), "_article_assets_decision.json")
gsaa_manifest_relative <- function() paste0("tables/", gsaa_prefix(), "_article_asset_manifest.csv")
gsaa_labels <- function(tex = FALSE) {
  setNames(if (tex) c("Raw GloFAS", "Normal Ridge", "Normal RHS", "Q--DESN (AL)",
    "Q--DESN (exAL)", "MQ--DESN (AL)", "MQ--DESN (exAL)") else
    c("Raw GloFAS", "Normal Ridge", "Normal RHS", "Q\u2013DESN (AL)",
      "Q\u2013DESN (exAL)", "MQ\u2013DESN (AL)", "MQ\u2013DESN (exAL)"), gsc_families())
}
gsaa_style <- function() list(history = "#24543A", truth = "#8E2529", product = "#B45D1B",
  quantiles = c("#153F63", "#315F83", "#688EAC", "#AEC3D2", "#688EAC", "#315F83", "#153F63"),
  # R graphics lwd=1 is 1/96 inch. This is approximately 0.15 mm.
  quantile_lwd = 0.57, observation_lwd = 0.7, member_lwd = 0.38,
  quantile_line_mm = 0.15, historical_points = 16L, future_points = 1L)

gsaa_pin <- function(path, sha256, max_bytes = 8 * 1024^2) {
  gsaa_require(is.character(path) && length(path) == 1L && !is.na(path) &&
    startsWith(path, "/") && file.exists(path), "explicit existing absolute input required")
  gsc_pin(list(path = path, size_bytes = as.numeric(file.info(path)$size), sha256 = sha256), max_bytes)
}

gsaa_manifest <- function(root, sha256, expected) {
  root <- normalizePath(root, mustWork = TRUE)
  path <- gsaa_pin(file.path(root, "artifact_manifest.csv"), sha256, 1024^2)
  m <- read.csv(path, stringsAsFactors = FALSE)
  gsaa_require(identical(names(m), c("relative_path", "size_bytes", "sha256")) &&
    !anyDuplicated(m$relative_path) && setequal(m$relative_path, expected) &&
    setequal(list.files(root, all.files = TRUE, no.. = TRUE), c(expected, "artifact_manifest.csv")),
    "exact input packet membership required")
  for (i in seq_len(nrow(m))) {
    gsaa_require(!grepl("[/\\\\]|^\\.", m$relative_path[i]), "input path traversal rejected")
    gsc_pin(list(path = file.path(root, m$relative_path[i]), size_bytes = m$size_bytes[i],
      sha256 = m$sha256[i]), 8 * 1024^2)
  }
  list(root = root, manifest = m, sha256 = sha256)
}

gsaa_history_grid <- function(rows) {
  dates <- seq(as.Date("2022-11-26"), as.Date("2022-12-25"), by = "day")
  fields <- c("family", "target_date", "tau", "quantile_transformed", "quantile", "time_role",
    "estimand", "future_path_factor_used", "posterior_predictive_quantile",
    "quantile_functional_credible_interval", "extra_response_noise_added", "isotonic_adjustment")
  gsaa_require(is.data.frame(rows) && all(fields %in% names(rows)) && nrow(rows) == 1260L &&
    setequal(unique(rows$family), gsc_families()[-1L]), "all six authentic fitted-history families required")
  expected <- expand.grid(family = gsc_families()[-1L], target_date = as.character(dates),
    tau = gsc_tau(), stringsAsFactors = FALSE)
  key <- function(x) paste(x$family, x$target_date, x$tau, sep = "|")
  gsaa_require(!anyDuplicated(key(rows)) && setequal(key(rows), key(expected)) &&
    all(is.finite(c(rows$quantile_transformed, rows$quantile))) &&
    all(abs(rows$quantile - expm1(rows$quantile_transformed)) < 1e-10 * pmax(1, abs(rows$quantile))) &&
    all(rows$time_role == "historical_fitted_conditional_quantile") &&
    all(rows$estimand == "VB_mean_conditional_quantile_on_log1p_scale") &&
    all(vapply(rows[c("future_path_factor_used", "posterior_predictive_quantile",
      "quantile_functional_credible_interval", "extra_response_noise_added", "isotonic_adjustment")],
      function(x) is.logical(x) && !anyNA(x) && all(!x), logical(1L))),
    "historical dates, transformation or conditional-quantile functional differs")
  invisible(TRUE)
}

gsaa_convergence <- function(pin) {
  gsaa_require(is.list(pin) && setequal(names(pin), c("path", "size_bytes", "sha256")),
    "exact convergence CSV pin required")
  z <- read.csv(gsc_pin(pin, 1024^2), stringsAsFactors = FALSE)
  fields <- c("task_id", "numerical_gates_pass", "iterations", "outer_iterations",
    "terminal_consecutive_passes", "wall_seconds", "cpu_seconds", "max_rss_bytes")
  gsaa_require(identical(names(z), fields) && nrow(z) == 16L && !anyDuplicated(z$task_id) &&
    setequal(z$task_id, gsc_tasks()) && is.logical(z$numerical_gates_pass) &&
    all(!is.na(z$numerical_gates_pass) & z$numerical_gates_pass), "sixteen accepted convergence records required")
  z <- z[match(gsc_tasks(), z$task_id), ]
  for (name in c("iterations", "outer_iterations", "terminal_consecutive_passes")) {
    gsaa_require((is.numeric(z[[name]]) || (is.logical(z[[name]]) && all(is.na(z[[name]])))) &&
      all(is.na(z[[name]]) | (is.finite(z[[name]]) & z[[name]] >= 0 & z[[name]] == floor(z[[name]]))),
      "invalid iteration count")
    z[[name]] <- as.numeric(z[[name]])
  }
  for (name in c("wall_seconds", "cpu_seconds", "max_rss_bytes"))
    gsaa_require(is.numeric(z[[name]]) && all(is.finite(z[[name]]) & z[[name]] > 0), "positive measured runtime required")
  mq <- startsWith(z$task_id, "gft-mq-")
  gsaa_require(all(!is.na(z$outer_iterations[mq]) & z$outer_iterations[mq] >= 1) &&
    all(!is.na(z$terminal_consecutive_passes[mq]) & z$terminal_consecutive_passes[mq] >= 3),
    "both MQ fits require measured outer iterations and three complete passes")
  z$family <- vapply(z$task_id, gsc_task_family, character(1L))
  z$tau <- vapply(z$task_id, function(id) if (startsWith(id, "gft-mq-")) NA_real_ else gsc_task_tau(id), numeric(1L))
  z
}

gsaa_inputs <- function(packet_root, packet_manifest_sha256, extraction_root, extraction_manifest_sha256,
    fitted_history_root, fitted_history_manifest_sha256, convergence_pin,
    derived_metrics_root = NULL, derived_metrics_manifest_sha256 = NULL) {
  packet <- gsc_check_packet(packet_root, packet_manifest_sha256)
  verified <- gspm_verify(packet_root, expected_manifest_sha256 = packet_manifest_sha256)
  gsaa_require(isTRUE(verified$verified), "independent publication metrics verification failed")
  ex <- gsaa_manifest(extraction_root, extraction_manifest_sha256, c("history.csv", "issued_member_paths.csv",
    "raw_members.csv", "raw_member_derivation.json", "EXTRACTION_DECISION.json"))
  hi <- gsaa_manifest(fitted_history_root, fitted_history_manifest_sha256, c("fitted_conditional_quantiles.csv",
    "raw_fitted_crossings.csv", "FITTED_HISTORY_DECISION.json"))
  er <- jsonlite::read_json(file.path(ex$root, "EXTRACTION_DECISION.json"), simplifyVector = FALSE)
  hr <- jsonlite::read_json(file.path(hi$root, "FITTED_HISTORY_DECISION.json"), simplifyVector = FALSE)
  seal <- gsc_verify_forecast_seal(packet_root, packet$decision$forecast_seal_sha256)
  gsaa_require(identical(er$status, "TRUTH_FREE_PLOT_INPUTS_EXTRACTED_NOT_SCIENTIFIC_RELEASE") &&
    er$producer_count == 16 && er$members == 51 && er$issued_rows == 1428 && er$history_rows == 30 &&
    identical(er$future_truth_read, FALSE) && er$new_fits == 0 &&
    identical(hr$status, "AUTHENTIC_FITTED_HISTORY_MATERIALIZED_NOT_FORECAST_OR_ARTICLE_RELEASE") &&
    identical(hr$selection, "all_six_families_v1") && hr$producer_count == 16 && hr$rows == 1260 &&
    identical(hr$future_truth_read, FALSE) && hr$new_fits == 0 &&
    identical(hr$isotonic_adjustment, FALSE) &&
    identical(er$prepared_design$sha256, seal$prepared_design_sha256) &&
    identical(hr$design$sha256, seal$prepared_design_sha256), "matching corrected extraction/history receipts required")
  for (name in c("raw_members", "raw_member_derivation")) {
    filename <- if (name == "raw_members") "raw_members.csv" else "raw_member_derivation.json"
    at <- which(ex$manifest$relative_path == filename); p <- seal$input_bindings[[name]]
    gsaa_require(length(at) == 1L && identical(ex$manifest$sha256[at], p$sha256) &&
      ex$manifest$size_bytes[at] == p$size_bytes, "plotting extraction differs from sealed forecast inputs")
  }
  history <- read.csv(file.path(ex$root, "history.csv"), stringsAsFactors = FALSE)
  gsaa_require(identical(names(history), c("target_date", "y_transformed", "g_transformed")) &&
    nrow(history) == 30 && !anyNA(as.Date(history$target_date)) &&
    all(as.character(history$target_date) == as.character(seq(as.Date("2022-11-26"), as.Date("2022-12-25"), by = "day"))) &&
    all(is.finite(c(history$y_transformed, history$g_transformed))), "thirty authentic consecutive historical dates required")
  members <- read.csv(file.path(ex$root, "raw_members.csv"), stringsAsFactors = FALSE)
  raw <- gsc_raw_rows(members)
  raw_packet <- packet$rows[packet$rows$family == "Raw GloFAS", ]
  raw_packet <- raw_packet[order(raw_packet$horizon, raw_packet$tau), ]
  raw <- raw[order(raw$horizon, raw$tau), ]
  gsaa_require(max(abs(raw$quantile_transformed - raw_packet$quantile_transformed)) < 2e-12,
    "authentic member quantiles disagree with the scored raw comparator")
  issued <- read.csv(file.path(ex$root, "issued_member_paths.csv"), stringsAsFactors = FALSE)
  gsaa_require(nrow(issued) == 1428L && all(c("origin_date", "target_date", "horizon", "member",
    "g_transformed", "ensemble_weight") %in% names(issued)) &&
    all(issued$origin_date == "2022-12-25") && all(issued$ensemble_weight == 1), "all authentic unit-weight issued members required")
  order_member <- function(z) z[order(z$horizon, z$member), c("target_date", "horizon", "member", "g_transformed")]
  gsaa_require(isTRUE(all.equal(order_member(issued), order_member(members), check.attributes = FALSE, tolerance = 0)),
    "issued member paths differ from sealed raw-member source")
  fitted <- read.csv(file.path(hi$root, "fitted_conditional_quantiles.csv"), stringsAsFactors = FALSE)
  gsaa_history_grid(fitted)
  convergence <- gsaa_convergence(convergence_pin)
  if (!is.null(derived_metrics_root) || !is.null(derived_metrics_manifest_sha256)) {
    gsaa_require(!is.null(derived_metrics_root) && gsc_hash_string(derived_metrics_manifest_sha256),
      "both independent derived-metrics root and expected manifest SHA required")
    dm <- gsaa_manifest(derived_metrics_root, derived_metrics_manifest_sha256, c("family_metrics.csv", "date_metrics.csv",
      "quantile_calibration.csv", "raw_crossings.csv", "source_manifest.csv", "DERIVED_METRICS_DECISION.json"))
    observed <- read.csv(file.path(dm$root, "family_metrics.csv"), stringsAsFactors = FALSE)
    gsaa_require(isTRUE(all.equal(observed, verified$family_metrics, check.attributes = FALSE, tolerance = 1e-12)),
      "independent derived-metrics table differs")
  }
  list(rows = packet$rows, truth = packet$truth, metrics = verified, history = history, members = members,
    fitted = fitted, convergence = convergence, lineage = list(scientific_source = gsc_identity(),
      packet_manifest_sha256 = packet_manifest_sha256, extraction_manifest_sha256 = extraction_manifest_sha256,
      fitted_history_manifest_sha256 = fitted_history_manifest_sha256,
      convergence_sha256 = convergence_pin$sha256, derived_metrics_manifest_sha256 = derived_metrics_manifest_sha256))
}

gsaa_pdf <- function(path, width, height, draw) {
  gsaa_require(capabilities("cairo"), "Cairo vector PDF support required for embedded fonts")
  grDevices::cairo_pdf(path, width = width, height = height, family = "Nimbus Sans", pointsize = 11,
    onefile = TRUE, fallback_resolution = 600)
  on.exit(grDevices::dev.off(), add = TRUE)
  force(draw)
  invisible(path)
}

gsaa_axes <- function(ylim, label, last = FALSE, compact = FALSE) {
  dates <- c(as.Date("2022-11-26"), as.Date("2023-01-22"))
  graphics::plot(as.numeric(dates), ylim, type = "n", axes = FALSE, xlab = "", ylab = "",
    xaxs = "i", yaxs = "i", ylim = ylim)
  graphics::axis(2, las = 1, tck = -.02, cex.axis = .88)
  ticks <- as.Date(if (compact) c("2022-11-26", "2022-12-25", "2023-01-22") else
    c("2022-11-26", "2022-12-10", "2022-12-25", "2023-01-08", "2023-01-22"))
  graphics::axis(1, at = as.numeric(ticks), labels = FALSE, tck = -.02)
  # End-date labels face inward rather than extending beyond the panel/page.
  for (i in seq_along(ticks)) graphics::mtext(format(ticks[i], "%d %b"), side = 1,
    at = as.numeric(ticks[i]), line = .55, adj = if (i == 1L) 0 else if (i == length(ticks)) 1 else .5, cex = .88)
  graphics::box(bty = "l", col = "#444444", lwd = .6)
  graphics::abline(v = as.numeric(as.Date("2022-12-25")), col = "#666666", lty = 3, lwd = .6)
  graphics::mtext(label, 3, adj = 0, line = .35, cex = .96)
  if (last) graphics::mtext("Date", 1, line = 2.3, cex = .95)
}

gsaa_observations <- function(z) {
  s <- gsaa_style()
  graphics::lines(as.Date(z$history$target_date), z$history$y_transformed, col = s$history, lwd = s$observation_lwd)
  graphics::points(as.Date(z$history$target_date), z$history$y_transformed, pch = s$historical_points,
    col = s$history, cex = .38)
  graphics::lines(as.Date(z$truth$target_date), z$truth$y_transformed, col = s$truth, lwd = s$observation_lwd)
  graphics::points(as.Date(z$truth$target_date), z$truth$y_transformed, pch = s$future_points,
    col = s$truth, cex = .55, lwd = .65)
}

gsaa_quantiles <- function(rows) {
  s <- gsaa_style()
  for (i in seq_along(gsc_tau())) {
    b <- rows[rows$tau == gsc_tau()[i], ]; b <- b[order(b$target_date), ]
    graphics::lines(as.Date(b$target_date), b$quantile_transformed, col = s$quantiles[i], lwd = s$quantile_lwd)
  }
}

gsaa_range <- function(z, families) {
  y <- c(z$history$y_transformed, z$history$g_transformed, z$truth$y_transformed, z$members$g_transformed,
    z$rows$quantile_transformed[z$rows$family %in% families], z$fitted$quantile_transformed[z$fitted$family %in% families])
  r <- range(y); d <- max(diff(r), .1)
  r + c(-.04, .06) * d
}

gsaa_main_plot <- function(z, path) {
  s <- gsaa_style(); ylim <- gsaa_range(z, c("Independent AL", "Normal Ridge"))
  gsaa_pdf(path, 6.65, 7.0, {
    graphics::layout(matrix(1:4, ncol = 1), heights = c(1, 1, 1, .35))
    graphics::par(mar = c(3.0, 3.8, 1.7, 1.2), oma = c(.2, 1.8, .1, .3), mgp = c(2, .55, 0))
    # Multi-panel graphics otherwise silently reduce text to cex=0.66.
    graphics::par(cex = 1, mex = 1)
    gsaa_axes(ylim, "(a) Observed streamflow and issued ensemble")
    graphics::lines(as.Date(z$history$target_date), z$history$g_transformed, col = s$product, lwd = .75)
    for (member in unique(z$members$member)) {
      b <- z$members[z$members$member == member, ]; b <- b[order(b$horizon), ]
      graphics::lines(as.Date(b$target_date), b$g_transformed, col = grDevices::adjustcolor(s$product, alpha.f = .48),
        lwd = s$member_lwd)
    }
    gsaa_observations(z)
    for (i in seq_along(c("Independent AL", "Normal Ridge"))) {
      family <- c("Independent AL", "Normal Ridge")[i]
      gsaa_axes(ylim, paste0("(", letters[i + 1L], ") ", gsaa_labels()[[family]]), last = i == 2L)
      # Separate calls preserve the historical/forecast functional boundary.
      gsaa_quantiles(z$fitted[z$fitted$family == family, ])
      gsaa_quantiles(z$rows[z$rows$family == family, ])
      gsaa_observations(z)
    }
    graphics::mtext("log(1 + streamflow)", side = 2, outer = TRUE, line = .4, cex = .95)
    graphics::par(mar = rep(0, 4), xpd = FALSE)
    graphics::plot.new()
    graphics::legend(.5, .98, xjust = .5, yjust = 1, c("USGS through origin", "Held-out USGS", "GloFAS products"),
      col = c(s$history, s$truth, s$product), pch = c(16, 1, NA), lty = c(1, 1, 1),
      lwd = c(.7, .7, .7), pt.cex = .65, bty = "n", cex = .82, ncol = 3, x.intersp = .5, y.intersp = .8)
    graphics::legend(.5, .55, xjust = .5, yjust = 1, legend = sprintf("%.2f", gsc_tau()), col = s$quantiles,
      lty = 1, lwd = s$quantile_lwd, ncol = 7, bty = "n", cex = .85, title = "Quantile level")
  })
}

gsaa_full_plot <- function(z, path) {
  families <- gsc_families(); ylim <- gsaa_range(z, families)
  gsaa_pdf(path, 6.65, 7.1, {
    graphics::par(mfrow = c(4, 2), mar = c(2.9, 3.1, 1.65, 1.2), oma = c(.4, 1.8, .1, .3), mgp = c(1.7, .4, 0))
    graphics::par(cex = 1, mex = 1)
    for (i in seq_along(families)) {
      family <- families[i];gsaa_axes(ylim, paste0("(", letters[i], ") ", gsaa_labels()[[family]]), compact = TRUE)
      if (family == "Raw GloFAS")
        graphics::lines(as.Date(z$history$target_date), z$history$g_transformed, col = gsaa_style()$product, lwd = .7)
      else gsaa_quantiles(z$fitted[z$fitted$family == family, ])
      gsaa_quantiles(z$rows[z$rows$family == family, ]);gsaa_observations(z)
    }
    graphics::par(mar = rep(.1, 4));graphics::plot.new();s <- gsaa_style()
    graphics::legend("center", legend = c("Historical USGS", "Held-out USGS", "Historical GloFAS", sprintf("p = %.2f", gsc_tau())),
      col = c(s$history, s$truth, s$product, s$quantiles), pch = c(16, 1, NA, rep(NA, 7)),
      lty = 1, lwd = c(.7, .7, .7, rep(s$quantile_lwd, 7)), bty = "n", cex = .9, ncol = 2)
    graphics::mtext("log(1 + streamflow)", side = 2, outer = TRUE, line = .4, cex = .95)
  })
}

gsaa_calibration_plot <- function(z, path) {
  gsaa_pdf(path, 6.65, 7.1, {
    graphics::par(mfrow = c(4, 2), mar = c(3.1, 3.9, 1.8, .6), oma = c(.3, .5, .1, .1), mgp = c(1.8, .5, 0))
    graphics::par(cex = 1, mex = 1)
    for (family in gsc_families()) {
      b <- z$metrics$calibration[z$metrics$calibration$family == family, ];b <- b[order(b$tau), ]
      graphics::plot(b$tau, b$empirical_coverage, type = "b", pch = 1, lwd = .7, cex = .7,
        col = "#315F83", xlim = c(0, 1), ylim = c(0, 1), xlab = "Quantile level", ylab = "Observed frequency",
        main = gsaa_labels()[[family]], cex.main = .95, cex.axis = .85, cex.lab = .9, bty = "l", las = 1)
      graphics::abline(0, 1, col = "#777777", lty = 3, lwd = .7)
    }
    graphics::par(mar = rep(.2, 4));graphics::plot.new()
    graphics::text(.5, .67, "28 forecast dates per model", cex = .95)
    graphics::text(.5, .43, "Frequency of observed flow\nat or below each fitted quantile", cex = .9)
  })
}

gsaa_convergence_plot <- function(z, path) {
  b <- z$convergence;label <- paste0(gsaa_labels()[b$family], ifelse(is.na(b$tau), "", sprintf("  p=%.2f", b$tau)))
  gsaa_pdf(path, 6.65, 5.2, {
    graphics::par(mar = c(3.7, 10.0, 1.6, .7), mgp = c(2.1, .55, 0))
    at <- rev(seq_len(nrow(b)));upper <- max(c(b$wall_seconds, b$cpu_seconds)) / 3600
    graphics::plot(c(0, upper * 1.04), c(.5, nrow(b) + 1.6), type = "n", axes = FALSE,
      xlab = "Computation time (hours)", ylab = "", xaxs = "i")
    graphics::axis(1, cex.axis = .88);graphics::axis(2, at = at, labels = label, las = 1, tick = FALSE, cex.axis = .82)
    graphics::segments(0, at, b$wall_seconds / 3600, at, col = "#BEC7CD", lwd = .7)
    graphics::points(b$wall_seconds / 3600, at, pch = 1, col = "#315F83", cex = .75)
    graphics::points(b$cpu_seconds / 3600, at, pch = 16, col = "#333333", cex = .45)
    graphics::legend("topright", c("Wall time", "CPU time"), pch = c(1, 16), col = c("#315F83", "#333333"),
      pt.cex = c(.8, .6), bty = "n", cex = .85)
    graphics::box(bty = "l", lwd = .6)
  })
}

gsaa_tables <- function(z) {
  b <- z$metrics$family_metrics;b <- b[match(gsc_families(), b$family), ];labels <- gsaa_labels(TRUE)
  end <- paste0(" ", strrep("\\", 2L))
  main <- c("\\begin{tabular}{lrrr}", "\\toprule",
    paste0("Model & Grid $\\aCRPS$ & 90\\% coverage & Crossings (\\%)", end), "\\midrule",
    vapply(seq_len(7L), function(i) paste0(sprintf("%s & %.4f & %d/28 (%.1f\\%%) & %.2f",
      labels[[b$family[i]]], b$grid_acrps_log1p[i], b$covered90_count[i], b$coverage90_percent[i],
      b$raw_crossing_percent[i]), end), character(1L)), "\\bottomrule", "\\end{tabular}")
  full <- c("\\begin{tabular}{lrrrrr}", "\\toprule",
    paste0("Model & Grid $\\aCRPS$ & Check loss & Coverage & Crossings (\\%) & Max. violation", end), "\\midrule",
    vapply(seq_len(7L), function(i) paste0(sprintf("%s & %.4f & %.4f & %d/28 & %.2f & %.4f",
      labels[[b$family[i]]], b$grid_acrps_log1p[i], b$mean_check_loss[i], b$covered90_count[i],
      b$raw_crossing_percent[i], b$max_positive_adjacent_violation_log1p[i]), end), character(1L)),
    "\\bottomrule", "\\end{tabular}")
  cal <- z$metrics$calibration
  calibration <- c("\\begin{tabular}{lrrrrrrr}", "\\toprule",
    paste0("Model & ", paste(sprintf("%.2f", gsc_tau()), collapse = " & "), end), "\\midrule",
    vapply(gsc_families(), function(f) {x <- cal[cal$family == f, ];x <- x[order(x$tau), ]
      paste0(labels[[f]], " & ", paste(sprintf("%.3f", x$empirical_coverage), collapse = " & "), end)}, character(1L)),
    "\\bottomrule", "\\end{tabular}")
  c <- z$convergence;fmt <- function(x) ifelse(is.na(x), "---", format(x, trim = TRUE, scientific = FALSE))
  convergence <- c("\\begin{tabular}{llrrrr}", "\\toprule",
    paste0("Model & Level & Iterations & Outer sweeps & Full passes & Wall (h)", end), "\\midrule",
    vapply(seq_len(nrow(c)), function(i) paste0(labels[[c$family[i]]], " & ",
      if (is.na(c$tau[i])) "All seven" else sprintf("%.2f", c$tau[i]), " & ", fmt(c$iterations[i]), " & ",
      fmt(c$outer_iterations[i]), " & ", fmt(c$terminal_consecutive_passes[i]), " & ",
      sprintf("%.2f", c$wall_seconds[i] / 3600), end), character(1L)), "\\bottomrule", "\\end{tabular}")
  lapply(list(main_scores = main, full_scores = full, calibration = calibration, convergence = convergence), unname)
}

gsaa_aliases <- function(z) {
  prefix <- gsaa_prefix();f <- paste0("figures/glofas_application/", prefix);t <- paste0("tables/", prefix)
  path <- c(GlofasApplicationCurrentScoreTable = paste0(t, "_main_scores.tex"),
    GlofasApplicationCurrentForecastWindowFigure = paste0(f, "_main.pdf"),
    GlofasApplicationCurrentCorrectedPathsFigure = paste0(f, "_main.pdf"),
    GlofasApplicationCurrentFullComparisonFigure = paste0(f, "_all_families.pdf"),
    GlofasApplicationCurrentCalibrationTable = paste0(t, "_calibration.tex"),
    GlofasApplicationCurrentCalibrationFigure = paste0(f, "_calibration.pdf"),
    GlofasApplicationCurrentConvergenceTable = paste0(t, "_convergence.tex"),
    GlofasApplicationCurrentConvergenceFigure = paste0(f, "_convergence.pdf"))
  lines <- vapply(names(path), function(k) paste0("\\renewcommand{\\", k, "}{", path[[k]], "}"), character(1L))
  b <- z$metrics$family_metrics;score <- function(f, col) b[[col]][match(f, b$family)]
  reduction <- function(col) sprintf("%.2f\\%%", 100 * (1 - score("Independent AL", col) / score("Raw GloFAS", col)))
  mq <- z$convergence[match(c("gft-mq-al", "gft-mq-exal"), z$convergence$task_id), ]
  upper <- z$metrics$calibration$empirical_coverage[z$metrics$calibration$family == "MQ exAL" &
    z$metrics$calibration$tau == .95]
  values <- c(GlofasApplicationCurrentNormalRidgeAcrps = sprintf("%.4f", score("Normal Ridge", "grid_acrps_log1p")),
    GlofasApplicationCurrentNormalRhsAcrps = sprintf("%.4f", score("Normal RHS", "grid_acrps_log1p")),
    GlofasApplicationCurrentQdesnAcrps = sprintf("%.4f", score("Independent AL", "grid_acrps_log1p")),
    GlofasApplicationCurrentRawAcrps = sprintf("%.4f", score("Raw GloFAS", "grid_acrps_log1p")),
    GlofasApplicationCurrentQdesnCheckLoss = sprintf("%.4f", score("Independent AL", "mean_check_loss")),
    GlofasApplicationCurrentRawCheckLoss = sprintf("%.4f", score("Raw GloFAS", "mean_check_loss")),
    GlofasApplicationCurrentQdesnCrps = sprintf("%.4f", score("Independent AL", "grid_acrps_log1p")),
    GlofasApplicationCurrentRawCrps = sprintf("%.4f", score("Raw GloFAS", "grid_acrps_log1p")),
    GlofasApplicationCurrentCheckLossReduction = reduction("mean_check_loss"),
    GlofasApplicationCurrentAcrpsReduction = reduction("grid_acrps_log1p"),
    GlofasApplicationCurrentCrpsReduction = reduction("grid_acrps_log1p"),
    GlofasApplicationCurrentQdesnMeanCoverage = sprintf("%.3f", score("Independent AL", "coverage90")),
    GlofasApplicationCurrentRawMeanCoverage = sprintf("%.3f", score("Raw GloFAS", "coverage90")),
    GlofasApplicationCurrentJointAlAcrps = sprintf("%.4f", score("MQ AL", "grid_acrps_log1p")),
    GlofasApplicationCurrentJointExalAcrps = sprintf("%.4f", score("MQ exAL", "grid_acrps_log1p")),
    GlofasApplicationCurrentJointAlCoverage = sprintf("%.3f", score("MQ AL", "coverage90")),
    GlofasApplicationCurrentJointExalUpperCoverage = sprintf("%.3f", upper),
    GlofasApplicationCurrentJointAlNumericalStatus = "strictly converged",
    GlofasApplicationCurrentJointExalNumericalStatus = "strictly converged",
    GlofasApplicationCurrentDescriptivePartFourLeader = gsaa_labels(TRUE)[[b$family[which.min(b$grid_acrps_log1p)]]],
    GlofasApplicationCurrentVbIterations = paste0("MQ--DESN (AL): ", mq$outer_iterations[1L],
      " outer sweeps; MQ--DESN (exAL): ", mq$outer_iterations[2L], " outer sweeps; three consecutive complete passes each"),
    GlofasApplicationCurrentOriginDate = "25 December 2022", GlofasApplicationCurrentScoredHorizons = "28",
    GlofasApplicationCurrentNumericalStatus = "all sixteen quantile fits passed their prescribed convergence checks")
  unname(c("% Generated from the complete corrected issued-window packet; no historical Parts 1--3 alias is replaced.",
    lines, paste0("\\providecommand{\\GlofasApplicationCurrentNormalRidgeAcrps}{}"),
    paste0("\\providecommand{\\GlofasApplicationCurrentNormalRhsAcrps}{}"),
    paste0("\\providecommand{\\GlofasApplicationCurrentIssuedSupplementScoreTable}{}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentIssuedSupplementScoreTable}{", t, "_full_scores.tex}"),
    vapply(names(values), function(k) paste0("\\renewcommand{\\", k, "}{", values[[k]], "}"), character(1L))))
}

gsaa_expected_files <- function() {
  p <- gsaa_prefix()
  sort(c(paste0("figures/glofas_application/", p, c("_main.pdf", "_all_families.pdf", "_calibration.pdf", "_convergence.pdf")),
    paste0("tables/", p, c("_main_scores.tex", "_full_scores.tex", "_calibration.tex", "_convergence.tex",
      "_display_aliases.tex", "_family_metrics.csv", "_date_metrics.csv", "_calibration.csv", "_convergence.csv",
      "_quantile_paths.csv", "_fitted_history.csv", "_history.csv", "_issued_members.csv", "_observations.csv")),
    gsaa_decision_relative()))
}

gsaa_output <- function(output_root) {
  gsaa_require(is.character(output_root) && length(output_root) == 1L && !is.na(output_root) &&
    startsWith(output_root, "/"), "one absolute candidate output required")
  link <- Sys.readlink(output_root)
  gsaa_require(!file.exists(output_root) && (is.na(link) || !nzchar(link)) && dir.exists(dirname(output_root)) &&
    identical(normalizePath(dirname(output_root)), dirname(output_root)) &&
    !grepl("(^|/)\\.\\.(/|$)", output_root) &&
    system2("git", c("check-ignore", "--quiet", "--", shQuote(output_root))) == 0L,
    "fresh ignored candidate output required")
  invisible(TRUE)
}

gsaa_build <- function(packet_root, packet_manifest_sha256, extraction_root, extraction_manifest_sha256,
    fitted_history_root, fitted_history_manifest_sha256, convergence_pin, output_root,
    derived_metrics_root = NULL, derived_metrics_manifest_sha256 = NULL) {
  gsaa_output(output_root)
  z <- gsaa_inputs(packet_root, packet_manifest_sha256, extraction_root, extraction_manifest_sha256,
    fitted_history_root, fitted_history_manifest_sha256, convergence_pin, derived_metrics_root, derived_metrics_manifest_sha256)
  gsaa_require(dir.create(output_root), "candidate creation failed")
  dir.create(file.path(output_root, "tables"));dir.create(file.path(output_root, "figures"))
  dir.create(file.path(output_root, "figures/glofas_application"))
  t <- file.path(output_root, "tables", gsaa_prefix());f <- file.path(output_root, "figures/glofas_application", gsaa_prefix())
  tables <- gsaa_tables(z)
  for (name in names(tables)) writeLines(tables[[name]], paste0(t, "_", name, ".tex"), useBytes = TRUE)
  writeLines(gsaa_aliases(z), paste0(t, "_display_aliases.tex"), useBytes = TRUE)
  csv <- list(family_metrics = z$metrics$family_metrics, date_metrics = z$metrics$date_metrics,
    calibration = z$metrics$calibration, convergence = z$convergence[, c("family", "tau", "numerical_gates_pass",
      "iterations", "outer_iterations", "terminal_consecutive_passes", "wall_seconds", "cpu_seconds", "max_rss_bytes")],
    quantile_paths = z$rows[, c("family", "target_date", "horizon", "tau", "quantile_transformed", "quantile")],
    fitted_history = z$fitted, history = z$history, issued_members = z$members,
    observations = z$truth[, c("target_date", "horizon", "y_transformed")])
  for (name in names(csv)) write.csv(csv[[name]], paste0(t, "_", name, ".csv"), row.names = FALSE, na = "")
  gsaa_main_plot(z, paste0(f, "_main.pdf"));gsaa_full_plot(z, paste0(f, "_all_families.pdf"))
  gsaa_calibration_plot(z, paste0(f, "_calibration.pdf"));gsaa_convergence_plot(z, paste0(f, "_convergence.pdf"))
  jsonlite::write_json(list(schema_version = "glofas_same_family_article_assets_v1",
    status = "COMPLETE_ARTICLE_ASSET_CANDIDATE_NOT_AUTHORITY", lineage = z$lineage,
    forecast_rows = 1372L, historical_fitted_rows = 1260L, issued_member_rows = 1428L,
    history_rows = 30L, truth_rows = 28L, models = 7L, probabilities = gsc_tau(),
    history_start = "2022-11-26", origin = "2022-12-25", forecast_end = "2023-01-22",
    forecast_functional = "ensemble_conditioned_Gaussian_VB_marginal_response_quantile",
    historical_functional = "VB_mean_conditional_quantile_on_log1p_scale",
    isotonic_adjustment = FALSE, clipping_or_smoothing = FALSE, added_credible_ribbons = FALSE,
    extra_response_noise_added = FALSE, new_fits = 0L, source_models_opened = 0L,
    style = gsaa_style(), article_publication_authorized = FALSE),
    file.path(output_root, gsaa_decision_relative()), auto_unbox = TRUE, pretty = TRUE, digits = 17, null = "null")
  files <- gsaa_expected_files();actual <- list.files(output_root, recursive = TRUE, all.files = TRUE)
  gsaa_require(setequal(files, actual), "complete candidate membership differs")
  paths <- file.path(output_root, files)
  gsaa_require(all(file.info(paths)$size > 0) && sum(file.info(paths)$size) < 16 * 1024^2,
    "bounded article-safe output size exceeded")
  write.csv(data.frame(relative_path = files, size_bytes = as.numeric(file.info(paths)$size),
    sha256 = unname(tools::sha256sum(paths))), file.path(output_root, gsaa_manifest_relative()), row.names = FALSE)
  invisible(list(root = output_root, manifest_sha256 = unname(tools::sha256sum(file.path(output_root, gsaa_manifest_relative())))))
}

gsaa_cli <- function(args) {
  required <- c("--packet", "--packet-manifest-sha256", "--extraction", "--extraction-manifest-sha256",
    "--fitted-history", "--fitted-history-manifest-sha256", "--convergence", "--convergence-sha256", "--out")
  gsaa_require(length(args) %in% c(18L, 22L) && identical(args[seq(1L, 17L, 2L)], required),
    "exact packet/extraction/history/convergence pins and fresh output required")
  values <- args[seq(2L, 18L, 2L)]
  pin <- list(path = values[7L], size_bytes = as.numeric(file.info(values[7L])$size), sha256 = values[8L])
  optional <- list(derived_metrics_root = NULL, derived_metrics_manifest_sha256 = NULL)
  if (length(args) == 22L) {
    gsaa_require(identical(args[c(19L, 21L)], c("--derived-metrics", "--derived-metrics-manifest-sha256")),
      "exact independent derived-metrics pins required")
    optional <- list(derived_metrics_root = args[20L], derived_metrics_manifest_sha256 = args[22L])
  }
  do.call(gsaa_build, c(list(values[1L], values[2L], values[3L], values[4L], values[5L], values[6L], pin, values[9L]), optional))
  cat("GLOFAS_ARTICLE_ASSETS_CANDIDATE_COMPLETE_NOT_PUBLICATION\n")
}
if (sys.nframe() == 0L) gsaa_cli(commandArgs(TRUE))
