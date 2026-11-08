gpah_stop <- function(ok, message) if (!isTRUE(ok)) stop(message, call. = FALSE)

gpah_sha256 <- function(path) {
  gpah_stop(file.exists(path), paste0("Missing file: ", path))
  out <- system2("sha256sum", path, stdout = TRUE, stderr = TRUE)
  gpah_stop(length(out) == 1L, paste0("sha256sum failed: ", path))
  sub("[[:space:]].*$", "", out)
}

gpah_read_csv <- function(path) {
  gpah_stop(file.exists(path), paste0("Missing CSV: ", path))
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

gpah_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(x, path, row.names = FALSE, na = "")
}

gpah_write_lines <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(x, path, useBytes = TRUE)
}

gpah_git_value <- function(repo_root, args) {
  out <- system2("git", c("-C", repo_root, args), stdout = TRUE, stderr = TRUE)
  gpah_stop(is.null(attr(out, "status")) && length(out) == 1L,
    paste0("git command failed: ", paste(args, collapse = " ")))
  out[[1L]]
}

gpah_escape_tex <- function(x) {
  x <- gsub("\\\\", "\\\\textbackslash{}", x)
  gsub("([%&#_$])", "\\\\\\1", x)
}

gpah_tabular <- function(header, rows, align) {
  c(
    paste0("\\begin{tabular}{", align, "}"),
    "\\toprule",
    paste0(paste(header, collapse = " & "), " \\\\"),
    "\\midrule",
    if (nrow(rows)) apply(rows, 1L, function(z) paste0(paste(z, collapse = " & "), " \\\\")) else character(),
    "\\bottomrule",
    "\\end{tabular}"
  )
}

gpah_grid_weights <- function(tau) {
  tau <- sort(unique(as.numeric(tau)))
  gpah_stop(length(tau) >= 2L, "At least two quantile levels are required.")
  c((tau[[2L]] - tau[[1L]]) / 2,
    (tau[3:length(tau)] - tau[1:(length(tau) - 2L)]) / 2,
    (tau[[length(tau)]] - tau[[length(tau) - 1L]]) / 2)
}

gpah_recompute_scores <- function(paths) {
  required <- c("target_date", "horizon", "quantile_level", "y_reference", "qhat", "family")
  gpah_stop(all(required %in% names(paths)), "Corrected path table schema changed.")
  tau <- sort(unique(paths$quantile_level))
  gpah_stop(identical(round(tau, 8), c(.05, .2, .35, .5, .65, .8, .95)),
    "Corrected probability grid changed.")
  weights <- gpah_grid_weights(tau)
  rows <- lapply(unique(paths$family), function(family) {
    z <- paths[paths$family == family, , drop = FALSE]
    gpah_stop(nrow(z) == 28L * 7L && !anyDuplicated(paste(z$target_date, z$quantile_level)),
      paste0("Incomplete path grid for ", family, "."))
    loss <- (z$quantile_level - (z$y_reference < z$qhat)) * (z$y_reference - z$qhat)
    by_tau <- tapply(loss, z$quantile_level, mean)
    wide <- reshape(z[c("horizon", "quantile_level", "qhat")], idvar = "horizon",
      timevar = "quantile_level", direction = "wide")
    wide <- wide[order(wide$horizon), , drop = FALSE]
    qcols <- paste0("qhat.", tau)
    crossing_pairs <- sum(as.matrix(wide[qcols[-length(qcols)]]) > as.matrix(wide[qcols[-1L]]))
    q05 <- z$qhat[z$quantile_level == .05]
    q50 <- z$qhat[z$quantile_level == .5]
    q95 <- z$qhat[z$quantile_level == .95]
    truth <- z$y_reference[z$quantile_level == .5]
    data.frame(
      family = family,
      n_scored_horizons = length(truth),
      mean_check_loss = mean(loss),
      crps_grid_log1p = 2 * sum(weights * by_tau[as.character(tau)]),
      coverage90 = mean(truth >= q05 & truth <= q95),
      median_mae_log1p = mean(abs(truth - q50)),
      median_rmse_log1p = sqrt(mean((truth - q50)^2)),
      crossing_pairs = crossing_pairs,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

gpah_validate_compact_sources <- function(repo_root, corrected_root, qualification_root) {
  gptq_check(qualification_root)
  ready <- jsonlite::fromJSON(file.path(qualification_root, "status/qualification_ready.json"),
    simplifyVector = TRUE)
  gpah_stop(identical(ready$decision,
    "CORRECTED_PART4_TARGET_QUALIFIED_NO_REFIT_REQUIRED_INTEGRATION_REVIEW_PENDING"),
    "Corrected-target qualification is not ready for integration review.")

  final_root <- file.path(corrected_root, "final_packet")
  source_manifest <- gpah_read_csv(file.path(final_root, "artifact_manifest.csv"))
  source_paths <- file.path(corrected_root, source_manifest$relative_path)
  gpah_stop(all(file.exists(source_paths)) &&
      all(vapply(source_paths, gpah_sha256, character(1L)) == source_manifest$sha256),
    "October compact final packet failed its source manifest.")
  decision <- jsonlite::fromJSON(file.path(final_root, "DECISION.json"), simplifyVector = TRUE)
  gpah_stop(decision$fit_units == 18L && decision$numerical_pass == 18L &&
      decision$numerical_review == 0L && !decision$model_selection_or_retuning &&
      !decision$article_changed && !decision$contract$future_truth_used_in_fit &&
      !decision$contract$quantile_future_y_likelihood &&
      decision$contract$included_issued_factors == 1428L,
    "October decision contract changed.")

  scores <- gpah_read_csv(file.path(final_root, "family_scores.csv"))
  calibration <- gpah_read_csv(file.path(final_root, "quantile_calibration.csv"))
  gates <- gpah_read_csv(file.path(final_root, "fit_numerical_gates.csv"))
  paths <- gpah_read_csv(file.path(final_root, "quantile_paths.csv"))
  recomputed <- gpah_recompute_scores(paths)
  ord <- match(scores$family, recomputed$family)
  gpah_stop(!anyNA(ord), "A scored family is absent from the corrected paths.")
  numeric_cols <- c("mean_check_loss", "crps_grid_log1p", "coverage90",
    "median_mae_log1p", "median_rmse_log1p")
  for (nm in numeric_cols) {
    gpah_stop(max(abs(scores[[nm]] - recomputed[[nm]][ord])) < 5e-12,
      paste0("Independent score recomputation failed for ", nm, "."))
  }
  gpah_stop(identical(as.integer(scores$crossing_pairs), as.integer(recomputed$crossing_pairs[ord])),
    "Independent crossing recomputation failed.")
  gpah_stop(nrow(gates) == 18L && all(gates$recorded_converged) &&
      all(gates$strict_numerical_gate) && all(gates$quadrature_pass),
    "October numerical gates are incomplete.")
  gpah_stop(nrow(calibration) == 49L && !anyDuplicated(paste(calibration$family, calibration$quantile_level)),
    "October calibration table is incomplete.")

  history <- gpah_read_csv(file.path(repo_root, "tables/glofas_same_family_20261103_history.csv"))
  observations <- gpah_read_csv(file.path(repo_root, "tables/glofas_same_family_20261103_observations.csv"))
  members <- gpah_read_csv(file.path(repo_root, "tables/glofas_same_family_20261103_issued_members.csv"))
  gpah_stop(nrow(history) == 30L && max(as.Date(history$target_date)) == as.Date("2022-12-25"),
    "Historical plotting context changed.")
  gpah_stop(nrow(observations) == 28L && nrow(members) == 28L * 51L &&
      length(unique(members$member)) == 51L, "Issued-window plotting context changed.")
  truth <- unique(paths[c("target_date", "horizon", "y_reference")])
  truth <- truth[order(truth$horizon), ]
  gpah_stop(identical(as.character(truth$target_date), as.character(observations$target_date)) &&
      max(abs(truth$y_reference - observations$y_transformed)) < 1e-12,
    "Corrected score truth and plotting truth differ.")

  raw <- paths[paths$family == "Raw GloFAS", ]
  tau <- sort(unique(paths$quantile_level))
  raw_check <- do.call(rbind, lapply(sort(unique(members$horizon)), function(h) {
    z <- members$g_transformed[members$horizon == h]
    data.frame(horizon = h, quantile_level = tau,
      qhat = as.numeric(stats::quantile(z, tau, type = 8, names = FALSE)))
  }))
  key <- paste(raw$horizon, raw$quantile_level)
  key2 <- paste(raw_check$horizon, raw_check$quantile_level)
  gpah_stop(max(abs(raw$qhat - raw_check$qhat[match(key, key2)])) < 1e-12,
    "Raw GloFAS quantiles do not reproduce from the 51 issued members.")

  search3_p123 <- gpah_read_csv(file.path(repo_root,
    "tables/glofas_search3_part1234_final_20261007_part123_scores.csv"))
  gpah_stop(nrow(search3_p123) == 18L && identical(sort(unique(search3_p123$part)),
    c("Part 1", "Part 2", "Part 3")), "Search III Parts 1-3 authority is incomplete.")

  list(scores = scores, calibration = calibration, gates = gates, paths = paths,
    recomputed = recomputed, history = history, observations = observations,
    members = members, decision = decision, source_manifest = source_manifest,
    qualification_ready = ready, search3_p123 = search3_p123)
}

gpah_family_order <- c("Independent AL", "Independent exAL", "MQ AL", "MQ exAL",
  "Normal Ridge", "Normal RHS/VB", "Raw GloFAS")

gpah_score_tex <- function(scores) {
  x <- scores[match(gpah_family_order, scores$family), ]
  raw <- x$crps_grid_log1p[x$family == "Raw GloFAS"]
  reduction <- 100 * (raw - x$crps_grid_log1p) / raw
  reduction[x$family == "Raw GloFAS"] <- NA_real_
  rows <- cbind(gpah_escape_tex(x$family), sprintf("%.4f", x$mean_check_loss),
    sprintf("%.4f", x$crps_grid_log1p), sprintf("%.3f", x$coverage90),
    as.character(x$crossing_pairs), ifelse(is.na(reduction), "--", sprintf("%.1f\\%%", reduction)))
  gpah_tabular(c("Family", "Check loss", "$\\aCRPS$", "Coverage", "Crossings", "Reduction"),
    rows, "lrrrrr")
}

gpah_calibration_tex <- function(calibration) {
  tau <- sort(unique(calibration$quantile_level))
  families <- c("Independent AL", "Independent exAL", "MQ AL", "MQ exAL")
  rows <- do.call(rbind, lapply(families, function(family) {
    z <- calibration[calibration$family == family, ]
    z <- z[match(tau, z$quantile_level), ]
    c(gpah_escape_tex(family), sprintf("%.3f", z$empirical_coverage))
  }))
  gpah_tabular(c("Family", sprintf("$q_{%.2f}$", tau)), rows,
    paste0("l", paste(rep("r", length(tau)), collapse = "")))
}

gpah_gate_summary <- function(gates) {
  do.call(rbind, lapply(unique(gates$family), function(family) {
    z <- gates[gates$family == family, ]
    data.frame(family = family, fit_units = nrow(z), converged = sum(z$recorded_converged),
      strict_gate_pass = sum(z$strict_numerical_gate), quadrature_pass = sum(z$quadrature_pass),
      stringsAsFactors = FALSE)
  }))
}

gpah_gate_tex <- function(summary) {
  rows <- cbind(gpah_escape_tex(summary$family), summary$fit_units, summary$converged,
    summary$strict_gate_pass, summary$quadrature_pass)
  gpah_tabular(c("Family", "Fits", "Converged", "Strict gate", "Quadrature"), rows, "lrrrr")
}

gpah_plot_panel <- function(paths, history, observations, members, family, title,
  show_members = FALSE, show_legend = FALSE) {
  tau <- sort(unique(paths$quantile_level))
  cols <- c("#184E77", "#1D6996", "#2A9D8F", "#202124", "#D4A017", "#E76F51", "#A61B1B")
  hist_date <- as.Date(history$target_date)
  obs_date <- as.Date(observations$target_date)
  all_y <- c(history$y_transformed, observations$y_transformed)
  if (show_members) all_y <- c(all_y, members$g_transformed)
  if (!is.null(family)) all_y <- c(all_y, paths$qhat[paths$family == family])
  ylim <- range(all_y, finite = TRUE)
  plot(range(c(hist_date, obs_date)), ylim, type = "n", xaxt = "n", xlab = "Date",
    ylab = "log(1 + streamflow)", main = title, las = 1)
  axis.Date(1, at = pretty(c(hist_date, obs_date), 7), format = "%b %d")
  abline(v = as.Date("2022-12-25"), col = "#555555", lty = 3, lwd = 1.2)
  if (show_members) {
    for (member in unique(members$member)) {
      z <- members[members$member == member, ]
      lines(as.Date(z$target_date), z$g_transformed, col = grDevices::adjustcolor("#E67E22", .18), lwd = .55)
    }
    lines(hist_date, history$g_transformed, col = "#E67E22", lwd = 1.5)
  }
  lines(hist_date, history$y_transformed, col = "#1B7F5A", lwd = 1.5)
  points(hist_date, history$y_transformed, pch = 16, cex = .48, col = "#1B7F5A")
  points(obs_date, observations$y_transformed, pch = 1, cex = .75, lwd = 1.2, col = "#8B1E1E")
  if (!is.null(family)) {
    z <- paths[paths$family == family, ]
    for (i in seq_along(tau)) {
      q <- z[z$quantile_level == tau[[i]], ]
      q <- q[order(q$horizon), ]
      lines(as.Date(q$target_date), q$qhat, col = cols[[i]], lwd = if (tau[[i]] == .5) 2.2 else 1.15)
    }
  }
  if (show_legend) {
    legend("topleft", legend = c("Historical USGS", "Held-out USGS", "GloFAS products"),
      col = c("#1B7F5A", "#8B1E1E", "#E67E22"), pch = c(16, 1, NA), lty = c(1, NA, 1),
      bty = "n", cex = .72)
  }
}

gpah_plot_main <- function(path, data) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(path, width = 9.2, height = 10.8, useDingbats = FALSE)
  on.exit(grDevices::dev.off(), add = TRUE)
  op <- par(no.readonly = TRUE); on.exit(par(op), add = TRUE)
  par(mfrow = c(3, 1), mar = c(3.4, 4.2, 3.0, .8), oma = c(0, 0, .5, 0))
  gpah_plot_panel(data$paths, data$history, data$observations, data$members, NULL,
    "(a) USGS history and issued GloFAS ensemble", TRUE, TRUE)
  gpah_plot_panel(data$paths, data$history, data$observations, data$members, "Independent AL",
    "(b) Q-DESN (AL): shared Normal-driver path prior", FALSE, FALSE)
  gpah_plot_panel(data$paths, data$history, data$observations, data$members, "Normal Ridge",
    "(c) Gaussian DESN (ridge)", FALSE, FALSE)
}

gpah_plot_all <- function(path, data) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(path, width = 12, height = 12, useDingbats = FALSE)
  on.exit(grDevices::dev.off(), add = TRUE)
  op <- par(no.readonly = TRUE); on.exit(par(op), add = TRUE)
  par(mfrow = c(4, 2), mar = c(3.0, 3.8, 2.6, .6), oma = c(0, 0, 1.3, 0))
  gpah_plot_panel(data$paths, data$history, data$observations, data$members, NULL,
    "Issued GloFAS ensemble", TRUE, TRUE)
  for (family in gpah_family_order[gpah_family_order != "Raw GloFAS"]) {
    score <- data$scores$crps_grid_log1p[data$scores$family == family]
    cross <- data$scores$crossing_pairs[data$scores$family == family]
    gpah_plot_panel(data$paths, data$history, data$observations, data$members, family,
      sprintf("%s | aCRPS %.3f | crossings %d", family, score, cross), FALSE, FALSE)
  }
  plot.new()
  text(.5, .56, "Corrected Part 4 authority", cex = 1.25, font = 2)
  text(.5, .43, "Frozen Search III geometry; coherent October future-path target", cex = .9)
  mtext("All curves are on the log(1 + streamflow) scale", outer = TRUE, cex = 1.05, font = 2)
}

gpah_plot_calibration <- function(path, calibration) {
  families <- c("Independent AL", "Independent exAL", "MQ AL", "MQ exAL")
  tau <- sort(unique(calibration$quantile_level))
  mat <- matrix(NA_real_, nrow = length(families), ncol = length(tau),
    dimnames = list(families, sprintf("%.2f", tau)))
  for (i in seq_len(nrow(calibration))) {
    if (calibration$family[[i]] %in% families)
      mat[calibration$family[[i]], sprintf("%.2f", calibration$quantile_level[[i]])] <- calibration$empirical_coverage[[i]]
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(path, width = 9, height = 5.3, useDingbats = FALSE)
  on.exit(grDevices::dev.off(), add = TRUE)
  op <- par(no.readonly = TRUE); on.exit(par(op), add = TRUE)
  par(mar = c(4.5, 9.2, 3.3, 1.2), las = 1)
  image(seq_along(tau), seq_along(families), t(mat), axes = FALSE,
    col = grDevices::colorRampPalette(c("#F4F7F5", "#6BAED6", "#08306B"))(100),
    xlab = "Quantile level", ylab = "", main = "Corrected Part 4 empirical quantile frequencies")
  axis(1, at = seq_along(tau), labels = sprintf("%.2f", tau))
  axis(2, at = seq_along(families), labels = families)
  for (i in seq_along(tau)) for (j in seq_along(families))
    text(i, j, sprintf("%.3f", mat[j, i]), col = if (mat[j, i] > .6) "white" else "black", cex = .82)
}

gpah_plot_gates <- function(path, summary) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(path, width = 8.8, height = 5.2, useDingbats = FALSE)
  on.exit(grDevices::dev.off(), add = TRUE)
  op <- par(no.readonly = TRUE); on.exit(par(op), add = TRUE)
  par(mar = c(7.5, 4.2, 3.2, 1), las = 2)
  mat <- t(as.matrix(summary[c("converged", "strict_gate_pass", "quadrature_pass")]))
  barplot(mat, beside = TRUE, names.arg = summary$family, col = c("#2A9D8F", "#355C7D", "#D4A017"),
    ylab = "Fit units passing", main = "Corrected Part 4 numerical qualification",
    ylim = c(0, max(summary$fit_units) + 1))
  legend("topright", legend = c("Recorded convergence", "Strict numerical gate", "Quadrature"),
    fill = c("#2A9D8F", "#355C7D", "#D4A017"), bty = "n", cex = .8)
}

gpah_aliases <- function(tag, scores) {
  pick <- function(family, column) scores[[column]][scores$family == family]
  raw <- pick("Raw GloFAS", "crps_grid_log1p")
  al <- pick("Independent AL", "crps_grid_log1p")
  reduction <- 100 * (raw - al) / raw
  c(
    "% Corrected hybrid authority: Search III Parts 1-3 plus qualified October Part 4.",
    paste0("\\renewcommand{\\GlofasApplicationCurrentRunId}{\\detokenize{", tag, "}}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentScoreTable}{tables/", tag, "_part4_scores.tex}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentForecastWindowFigure}{figures/glofas_application/", tag, "_part4_main.pdf}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentCorrectedPathsFigure}{figures/glofas_application/", tag, "_part4_main.pdf}"),
    "\\providecommand{\\GlofasApplicationCurrentFullComparisonFigure}{}",
    paste0("\\renewcommand{\\GlofasApplicationCurrentFullComparisonFigure}{figures/glofas_application/", tag, "_part4_all_families.pdf}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentCalibrationTable}{tables/", tag, "_part4_calibration.tex}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentCalibrationFigure}{figures/glofas_application/", tag, "_part4_calibration.pdf}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentConvergenceTable}{tables/", tag, "_part4_numerical_gates.tex}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentConvergenceFigure}{figures/glofas_application/", tag, "_part4_numerical_gates.pdf}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentQdesnAcrps}{", sprintf("%.4f", al), "}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentRawAcrps}{", sprintf("%.4f", raw), "}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentQdesnCrps}{", sprintf("%.4f", al), "}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentRawCrps}{", sprintf("%.4f", raw), "}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentQdesnCheckLoss}{", sprintf("%.4f", pick("Independent AL", "mean_check_loss")), "}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentRawCheckLoss}{", sprintf("%.4f", pick("Raw GloFAS", "mean_check_loss")), "}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentAcrpsReduction}{", sprintf("%.2f\\%%", reduction), "}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentCrpsReduction}{", sprintf("%.2f\\%%", reduction), "}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentCheckLossReduction}{", sprintf("%.2f\\%%", 100 * (pick("Raw GloFAS", "mean_check_loss") - pick("Independent AL", "mean_check_loss")) / pick("Raw GloFAS", "mean_check_loss")), "}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentQdesnMeanCoverage}{", sprintf("%.3f", pick("Independent AL", "coverage90")), "}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentRawMeanCoverage}{", sprintf("%.3f", pick("Raw GloFAS", "coverage90")), "}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentJointAlAcrps}{", sprintf("%.4f", pick("MQ AL", "crps_grid_log1p")), "}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentJointExalAcrps}{", sprintf("%.4f", pick("MQ exAL", "crps_grid_log1p")), "}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentJointAlCoverage}{", sprintf("%.3f", pick("MQ AL", "coverage90")), "}"),
    paste0("\\renewcommand{\\GlofasApplicationCurrentJointExalUpperCoverage}{", sprintf("%.3f", pick("MQ exAL", "coverage90")), "}"),
    "\\renewcommand{\\GlofasApplicationCurrentNormalRidgeAcrps}{0.8429}",
    "\\renewcommand{\\GlofasApplicationCurrentNormalRhsAcrps}{0.9463}",
    "\\renewcommand{\\GlofasApplicationCurrentDescriptivePartFourLeader}{Normal Ridge}",
    "\\renewcommand{\\GlofasApplicationCurrentNumericalStatus}{all 18 corrected Part 4 fits passed strict numerical and quadrature gates}",
    "\\renewcommand{\\GlofasApplicationCurrentJointAlNumericalStatus}{strict numerical gate passed}",
    "\\renewcommand{\\GlofasApplicationCurrentJointExalNumericalStatus}{strict numerical and quadrature gates passed}",
    "\\renewcommand{\\GlofasApplicationCurrentVbIterations}{18 of 18 corrected Part 4 fits passed their frozen numerical gates}",
    "\\renewcommand{\\GlofasApplicationCurrentOriginDate}{25 December 2022}",
    "\\renewcommand{\\GlofasApplicationCurrentScoredHorizons}{28}"
  )
}

gpah_manuscript_spec <- function(tag) c(
  "# GloFAS corrected hybrid-authority manuscript change specification", "",
  "## Authority composition", "",
  "- Keep every Search III Part 1-3 table, figure, selected specification and prior setting unchanged.",
  "- Replace only the Part 4 display layer with the qualified October coherent target.",
  "- Remove both active `glofas_same_family_20261103_display_aliases.tex` inputs.",
  paste0("- Add `tables/", tag, "_display_aliases.tex` after `glofas_application_current_outputs.tex` in both manuscripts."),
  "- Keep November files in Git as adverse evidence; never use them for article claims or aliases.", "",
  "## Main-text model correction", "",
  "Replace the future-reference working-likelihood line in Eq. (GloFAS Part 4) with a frozen Gaussian path-prior line:", "",
  "```tex", "\\text{Future path prior:}\\quad",
  "\\vect y_F\\mid D_T\\sim\\Normal(\\vect m_N,\\mat C_N),", "```", "",
  "State that `(m_N, C_N)` is moment-matched from 500 truth-free recursive paths of the frozen Part 3 Normal-RHS driver. The path prior replaces, rather than multiplies, future-USGS AL/exAL factors. The 1,428 issued-member factors remain in the likelihood. Future USGS is scoring-only.", "",
  "Replace the reported marginal-path-quantile equation with the frozen reporting rule:", "",
  "```tex", "\\widehat q_{p,h}=\\mathrm E_q\\{q_{p,T+h}(\\vect y_{F,1:h-1})\\},", "```", "",
  "Describe this as the Monte Carlo mean reference-readout location over the shared Normal-driver path law, not as a quantile of the latent-path Gaussian factor and not as a credible limit.", "",
  "## Results correction", "",
  "Report Normal Ridge as the descriptive Part 4 leader (aCRPS 0.8429). Report Independent AL 0.9299, Normal RHS/VB 0.9463, MQ AL 0.9544, Independent exAL 1.0501 and MQ exAL 1.0875, versus raw GloFAS 1.4360. All corrected quantile families improve on raw GloFAS. Raw adjacent crossings are 1 for Independent AL and 0 for the other corrected families.", "",
  "Do not claim that the issued-window scores selected the target, family, geometry, priors or stopping rules. The target correction follows from the pre-existing probability contract and truth-free root-cause audit.", "",
  "## Supplement correction", "",
  "In the Part 4 target, replace the product of future-USGS AL/exAL factors with `R_T(y_F)`, the frozen Gaussian driver prior. Set the reference-likelihood count to the historical reference count only; retain 12,455 + 28*51 issued/retrospective GloFAS contributions. Update the Delta description so the path precision combines the Gaussian prior and issued-member terms. Replace November crossing, inversion, negative-flow and runtime statements with the corrected tables in this packet.", "",
  "## Discussion correction", "",
  "Remove the statement that AL/exAL regressions fail to beat raw GloFAS. State instead that all six fitted corrections reduce grid aCRPS relative to raw GloFAS, with Gaussian ridge best on this one protected window, and that coverage remains imperfect. Preserve the single-origin limitation.", "",
  "## Hard exclusions", "",
  "- No November score, crossing, calibration, convergence or figure may remain active.",
  "- No Search III Part 1-3 value may change.",
  "- No final-window score may be described as model selection.",
  "- No fit, continuation, retuning, crossing repair or spread calibration is authorized."
)

gpah_build <- function(repo_root, corrected_root, qualification_root, output_root,
  base_ref = "origin/main", tag = "glofas_hybrid_part123_search3_part4_october_20261107") {
  repo_root <- normalizePath(repo_root, mustWork = TRUE)
  corrected_root <- normalizePath(corrected_root, mustWork = TRUE)
  qualification_root <- normalizePath(qualification_root, mustWork = TRUE)
  source_head <- gpah_git_value(repo_root, c("rev-parse", "HEAD"))
  source_tree <- gpah_git_value(repo_root, c("rev-parse", "HEAD^{tree}"))
  source_status <- system2("git", c("-C", repo_root, "status", "--porcelain"), stdout = TRUE)
  gpah_stop(!length(source_status), "Handoff must be built from a clean source worktree.")
  base_commit <- gpah_git_value(repo_root, c("rev-parse", base_ref))
  gpah_stop(base_commit == "82a8e70b1306aa2f36cf67ac8da65e6052df2c91",
    "The reviewed integration base changed; re-audit current main before rebuilding.")
  main_text <- readLines(file.path(repo_root, "main.tex"), warn = FALSE)
  gpah_stop(any(grepl("glofas_same_family_20261103_display_aliases", main_text, fixed = TRUE)),
    "Current main no longer exposes the reviewed November alias input.")

  output_root <- normalizePath(output_root, mustWork = FALSE)
  gpah_stop(!file.exists(output_root), "Output root already exists; refusing to overwrite.")
  stage <- paste0(output_root, ".staging-", Sys.getpid())
  gpah_stop(!file.exists(stage), "Staging root already exists.")
  dir.create(stage, recursive = TRUE)
  on.exit(unlink(stage, recursive = TRUE, force = TRUE), add = TRUE)

  data <- gpah_validate_compact_sources(repo_root, corrected_root, qualification_root)
  gate_summary <- gpah_gate_summary(data$gates)
  raw <- data$scores$crps_grid_log1p[data$scores$family == "Raw GloFAS"]
  scores <- data$scores
  scores$crps_reduction_vs_raw <- (raw - scores$crps_grid_log1p) / raw
  scores$authority_scope <- "Part 4 descriptive evaluation; not model selection"

  article <- file.path(stage, "article_safe")
  gpah_write_csv(scores, file.path(article, "tables", paste0(tag, "_part4_scores.csv")))
  gpah_write_lines(gpah_score_tex(scores), file.path(article, "tables", paste0(tag, "_part4_scores.tex")))
  gpah_write_csv(data$calibration, file.path(article, "tables", paste0(tag, "_part4_calibration.csv")))
  gpah_write_lines(gpah_calibration_tex(data$calibration),
    file.path(article, "tables", paste0(tag, "_part4_calibration.tex")))
  gpah_write_csv(data$gates, file.path(article, "tables", paste0(tag, "_part4_numerical_gates.csv")))
  gpah_write_csv(gate_summary, file.path(article, "tables", paste0(tag, "_part4_numerical_gate_summary.csv")))
  gpah_write_lines(gpah_gate_tex(gate_summary),
    file.path(article, "tables", paste0(tag, "_part4_numerical_gates.tex")))
  gpah_write_csv(data$paths, file.path(article, "tables", paste0(tag, "_part4_quantile_paths.csv")))
  gpah_write_csv(data$history, file.path(article, "tables", paste0(tag, "_history.csv")))
  gpah_write_csv(data$observations, file.path(article, "tables", paste0(tag, "_observations.csv")))
  gpah_write_csv(data$members, file.path(article, "tables", paste0(tag, "_issued_members.csv")))
  gpah_write_lines(gpah_aliases(tag, scores),
    file.path(article, "tables", paste0(tag, "_display_aliases.tex")))

  fig_root <- file.path(article, "figures/glofas_application")
  gpah_plot_main(file.path(fig_root, paste0(tag, "_part4_main.pdf")), data)
  gpah_plot_all(file.path(fig_root, paste0(tag, "_part4_all_families.pdf")), data)
  gpah_plot_calibration(file.path(fig_root, paste0(tag, "_part4_calibration.pdf")), data$calibration)
  gpah_plot_gates(file.path(fig_root, paste0(tag, "_part4_numerical_gates.pdf")), gate_summary)

  authority <- data.frame(
    component = c("Parts 1-3", "Part 4", "November same-family campaign"),
    authority = c("Search III", "October coherent unit-member target", "none"),
    disposition = c("retain unchanged", "install corrected article projection", "adverse evidence only"),
    source_head = c("e2a3be97853b1af9c8cb269a3e065336ca5590f3",
      "60daab261d52eec0ae24060babe186d618303e2b", "fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6"),
    protected_window_selection = FALSE, stringsAsFactors = FALSE)
  gpah_write_csv(authority, file.path(stage, "authority/authority_composition.csv"))
  gpah_write_csv(data$search3_p123, file.path(stage, "authority/search3_part123_scores_frozen.csv"))
  gpah_write_csv(data$source_manifest, file.path(stage, "authority/october_compact_source_manifest.csv"))
  gpah_write_csv(gpah_read_csv(file.path(qualification_root, "tables/qualification_gates.csv")),
    file.path(stage, "authority/corrected_target_qualification_gates.csv"))

  replacement <- data.frame(
    operation = c("remove_input", "remove_input", "add_input", "replace_part4_assets",
      "revise_main_model", "revise_main_results", "revise_supplement_target", "revise_discussion"),
    path = c("main.tex", "qdesn-supplement.tex", "main.tex and qdesn-supplement.tex",
      "tables/ and figures/glofas_application/", "main.tex", "main.tex", "qdesn-supplement.tex", "main.tex"),
    detail = c("Remove tables/glofas_same_family_20261103_display_aliases.tex input",
      "Remove tables/glofas_same_family_20261103_display_aliases.tex input",
      paste0("Add tables/", tag, "_display_aliases.tex after the Search III base aliases"),
      "Install every article_safe file at its relative path",
      "Replace future-USGS working likelihood with frozen Gaussian path prior and corrected reporting rule",
      "Use corrected October scores, coverage and crossings; preserve no-selection language",
      "Replace future-Y factors with R_T path prior and correct source counts/update description",
      "Remove rejected-family failure claim and retain single-origin limitation"), stringsAsFactors = FALSE)
  gpah_write_csv(replacement, file.path(stage, "integration/replacement_map.csv"))
  exclusions <- data.frame(
    surface = c("tables/glofas_same_family_20261103_display_aliases.tex",
      "tables/glofas_same_family_20261103_*", "figures/glofas_application/glofas_same_family_20261103_*",
      "November target hash 72ef0550...ef03", "final-window target selection", "new fits or continuations"),
    disposition = c("remove active imports", "retain in Git; no active authority use",
      "retain in Git; no active authority use", "adverse evidence only", "forbidden", "not authorized"),
    stringsAsFactors = FALSE)
  gpah_write_csv(exclusions, file.path(stage, "integration/exclusion_ledger.csv"))
  gpah_write_lines(gpah_manuscript_spec(tag), file.path(stage, "integration/manuscript_change_spec.md"))

  handoff <- c(
    "# Coordinator handoff: corrected GloFAS hybrid authority", "", "## Decision", "",
    "Install Search III Parts 1-3 unchanged and the qualified October coherent target for Part 4. Remove the November same-family packet from active manuscript authority. November remains immutable adverse evidence.", "",
    "This is a target-correction transaction, not selection by the protected December 2022 outcomes. The October target was specified and fitted before the November failure diagnosis; the read-only qualification verifies its common Normal-driver path law, no-future-truth contract, 18/18 numerical gates and complete issued-member likelihood.", "",
    "## Required coordinator transaction", "",
    "1. Start from the exact reviewed `origin/main` recorded in `status/READY_FOR_COORDINATOR_REVIEW.json`.",
    "2. Install the `article_safe/` tree without renaming files.",
    "3. Apply every row of `integration/replacement_map.csv` and the scientific wording in `integration/manuscript_change_spec.md`.",
    "4. Remove both active November alias imports; do not delete historical November files.",
    "5. Confirm Search III Parts 1-3 tables, figures, geometry and scores are byte-identical to main before the transaction.",
    "6. Compile both manuscripts and run the complete article and Overleaf snapshot checks.",
    "7. Search active manuscript dependencies for `glofas_same_family_20261103`; the result must be empty.",
    "8. Create a new integration receipt and publication manifest binding every installed asset to this packet.",
    "9. Merge/push main and update Overleaf only after independent review of the compiled PDFs.", "",
    "## Forbidden shortcuts", "",
    "Do not cherry-pick the full diagnostic branch, rerun models, tune from the protected window, apply crossing repair, relabel November, or replace Search III Parts 1-3.", "",
    "## Scientific summary", "",
    "Corrected Part 4 grid aCRPS: Normal Ridge 0.8429; Independent AL 0.9299; Normal RHS/VB 0.9463; MQ AL 0.9544; Independent exAL 1.0501; MQ exAL 1.0875; raw GloFAS 1.4360. Corrected quantile crossings are 1, 0, 0 and 0 across Independent AL, Independent exAL, MQ AL and MQ exAL.", "",
    "Final gate: `READY_FOR_COORDINATOR_REVIEW_NOT_AUTOMATIC_MAIN_PROMOTION`"
  )
  gpah_write_lines(handoff, file.path(stage, "integration/coordinator_handoff.md"))

  files <- list.files(stage, recursive = TRUE, full.names = TRUE)
  rel <- substring(files, nchar(stage) + 2L)
  manifest <- data.frame(relative_path = rel, size_bytes = as.numeric(file.info(files)$size),
    sha256 = vapply(files, gpah_sha256, character(1L)), stringsAsFactors = FALSE)
  manifest <- manifest[order(manifest$relative_path), ]
  gpah_write_csv(manifest, file.path(stage, "manifests/artifact_manifest.csv"))
  ready <- list(
    decision = "READY_FOR_COORDINATOR_REVIEW_NOT_AUTOMATIC_MAIN_PROMOTION",
    created_on = "2026-11-07", tag = tag, source_head = source_head, source_tree = source_tree,
    source_dirty = FALSE, reviewed_base_ref = base_ref, reviewed_base_commit = base_commit,
    qualification_ready_sha256 = gpah_sha256(file.path(qualification_root, "status/qualification_ready.json")),
    qualification_manifest_sha256 = gpah_sha256(file.path(qualification_root, "manifests/artifact_manifest.csv")),
    october_source_head = "60daab261d52eec0ae24060babe186d618303e2b",
    search3_integration_head = "e2a3be97853b1af9c8cb269a3e065336ca5590f3",
    rejected_november_head = "fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6",
    corrected_design_sha256 = "55edbd490c622bdc55ebf373d792dbbb4f1be71fffc8df115e44f089548c4b33",
    corrected_path_prior_sha256 = "0202bc19e26d84d6cbb55c2256a2071695f9c386c9dc64933005bd4d5acbb357",
    artifact_manifest_sha256 = gpah_sha256(file.path(stage, "manifests/artifact_manifest.csv")),
    model_fits_run = 0L, source_rds_reads = 0L, article_files_modified = 0L,
    protected_window_method_choices = 0L, search3_part123_changed = FALSE)
  dir.create(file.path(stage, "status"), recursive = TRUE, showWarnings = FALSE)
  gpah_write_lines(jsonlite::toJSON(ready, auto_unbox = TRUE, pretty = TRUE),
    file.path(stage, "status/READY_FOR_COORDINATOR_REVIEW.json"))

  gpah_check(stage)
  gpah_stop(file.rename(stage, output_root), "Atomic handoff publication failed.")
  on.exit(NULL, add = FALSE)
  cat("GLOFAS_PART4_HYBRID_AUTHORITY_HANDOFF_BUILD_PASS\n")
  cat("READY_FOR_COORDINATOR_REVIEW_NOT_AUTOMATIC_MAIN_PROMOTION\n")
  invisible(output_root)
}

gpah_check <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  manifest_path <- file.path(root, "manifests/artifact_manifest.csv")
  manifest <- gpah_read_csv(manifest_path)
  paths <- file.path(root, manifest$relative_path)
  gpah_stop(nrow(manifest) >= 20L && all(file.exists(paths)) &&
      all(as.numeric(file.info(paths)$size) == manifest$size_bytes) &&
      all(vapply(paths, gpah_sha256, character(1L)) == manifest$sha256),
    "Hybrid-authority artifact manifest failed.")
  ready <- jsonlite::fromJSON(file.path(root, "status/READY_FOR_COORDINATOR_REVIEW.json"), simplifyVector = TRUE)
  gpah_stop(identical(ready$decision, "READY_FOR_COORDINATOR_REVIEW_NOT_AUTOMATIC_MAIN_PROMOTION") &&
      ready$model_fits_run == 0L && ready$source_rds_reads == 0L &&
      ready$article_files_modified == 0L && ready$protected_window_method_choices == 0L &&
      !ready$search3_part123_changed &&
      identical(ready$artifact_manifest_sha256, gpah_sha256(manifest_path)),
    "Hybrid-authority ready receipt crossed a forbidden boundary.")
  authority <- gpah_read_csv(file.path(root, "authority/authority_composition.csv"))
  gpah_stop(nrow(authority) == 3L && authority$authority[authority$component == "Parts 1-3"] == "Search III" &&
      authority$authority[authority$component == "Part 4"] == "October coherent unit-member target" &&
      authority$authority[authority$component == "November same-family campaign"] == "none" &&
      !any(authority$protected_window_selection), "Authority composition changed.")
  scores <- gpah_read_csv(file.path(root, "article_safe/tables", paste0(ready$tag, "_part4_scores.csv")))
  q <- scores$family %in% c("Independent AL", "Independent exAL", "MQ AL", "MQ exAL")
  raw <- scores$crps_grid_log1p[scores$family == "Raw GloFAS"]
  gpah_stop(nrow(scores) == 7L && all(scores$crps_grid_log1p[q] < raw) &&
      max(scores$crossing_pairs[q]) <= 1L, "Corrected score projection changed.")
  aliases <- readLines(file.path(root, "article_safe/tables", paste0(ready$tag, "_display_aliases.tex")), warn = FALSE)
  gpah_stop(!any(grepl("glofas_same_family_20261103", aliases, fixed = TRUE)) &&
      any(grepl(ready$tag, aliases, fixed = TRUE)), "Alias projection still references November.")
  pdfs <- list.files(file.path(root, "article_safe/figures/glofas_application"), pattern = "[.]pdf$", full.names = TRUE)
  gpah_stop(length(pdfs) == 4L && all(file.info(pdfs)$size > 4000),
    "Hybrid-authority figures are missing or implausibly small.")
  spec <- paste(readLines(file.path(root, "integration/manuscript_change_spec.md"), warn = FALSE), collapse = "\n")
  gpah_stop(grepl("Gaussian path prior", spec, fixed = TRUE) &&
      grepl("No final-window score may be described as model selection", spec, fixed = TRUE),
    "Manuscript correction specification is incomplete.")
  cat("GLOFAS_PART4_HYBRID_AUTHORITY_HANDOFF_VERIFY_PASS\n")
  cat("READY_FOR_COORDINATOR_REVIEW_NOT_AUTOMATIC_MAIN_PROMOTION\n")
  invisible(manifest)
}
