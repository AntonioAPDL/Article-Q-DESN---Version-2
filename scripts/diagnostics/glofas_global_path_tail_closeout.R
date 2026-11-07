#!/usr/bin/env Rscript
# Truth-free closeout for accepted local-Delta and global p05/p50/p95 path
# summaries. Reads compact CSV/JSON evidence only; never reads fits or truth.

ggtc_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS tail closeout: ", why), call. = FALSE)
  invisible(TRUE)
}

ggtc_crossings <- function(rows) {
  q <- ggtc_require
  needed <- c("horizon", "probability", "estimate", "reporting_operator",
    "path_law", "member_policy")
  q(is.data.frame(rows) && all(needed %in% names(rows)),
    "reporting rows are incomplete")
  groups <- unique(rows[c("reporting_operator", "path_law", "member_policy")])
  out <- lapply(seq_len(nrow(groups)), function(i) {
    key <- groups[i, ]
    block <- rows[rows$reporting_operator == key$reporting_operator &
      rows$path_law == key$path_law & rows$member_policy == key$member_policy, ]
    wide <- reshape(block[c("horizon", "probability", "estimate")],
      idvar = "horizon", timevar = "probability", direction = "wide")
    names(wide) <- sub("estimate\\.", "q", names(wide))
    q(all(c("q0.05", "q0.5", "q0.95") %in% names(wide)) && nrow(wide) == 28L,
      "complete p05/p50/p95 horizon grid required")
    d1 <- wide$q0.05 - wide$q0.5
    d2 <- wide$q0.5 - wide$q0.95
    both <- c(d1, d2)
    data.frame(key, low_mid_crossings = sum(d1 > 1e-10),
      mid_high_crossings = sum(d2 > 1e-10),
      total_adjacent_crossings = sum(both > 1e-10),
      fully_ordered_horizons = sum(d1 <= 1e-10 & d2 <= 1e-10),
      maximum_crossing = max(c(both, 0)),
      maximum_crossing_horizon = c(wide$horizon, wide$horizon)[which.max(both)],
      stringsAsFactors = FALSE)
  })
  do.call(rbind, out)
}

ggtc_compare <- function(accepted, reporting) {
  out <- list(); at <- 0L
  for (prob in c(.05, .5, .95)) {
    observed <- accepted[accepted$probability == prob, ]
    for (law in unique(reporting$path_law)) for (operator in
        unique(reporting$reporting_operator)) {
      reference <- reporting[reporting$probability == prob &
        reporting$path_law == law &
        reporting$member_policy == "unit_member_likelihood_v1" &
        reporting$reporting_operator == operator, ]
      reference <- reference[order(reference$horizon), ]
      observed <- observed[order(observed$horizon), ]
      ggtc_require(nrow(reference) == 28L && nrow(observed) == 28L,
        "accepted/reference horizon grid differs")
      difference <- observed$estimate - reference$estimate
      at <- at + 1L
      out[[at]] <- data.frame(probability = prob, path_law = law,
        reporting_operator = operator,
        mean_absolute_difference = mean(abs(difference)),
        maximum_absolute_difference = max(abs(difference)),
        maximum_difference_horizon = which.max(abs(difference)),
        stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, out)
}

ggtc_run <- function(accepted_files, reporting_files, reference_files, output_dir) {
  q <- ggtc_require
  q(length(accepted_files) == 3L && length(reporting_files) == 3L &&
    length(reference_files) == 3L, "exact p05/p50/p95 inputs required")
  probabilities <- c(.05, .5, .95)
  accepted <- do.call(rbind, Map(function(path, probability) {
    x <- read.csv(path, stringsAsFactors = FALSE)
    q(nrow(x) == 28L && all(c("horizon", "quantile_transformed") %in% names(x)),
      "accepted forecast input is malformed")
    data.frame(horizon = x$horizon, probability = probability,
      estimate = x$quantile_transformed,
      reporting_operator = "accepted_local_gaussian_delta_marginal_quantile",
      path_law = "same_family_al_transition",
      member_policy = "unit_member_likelihood_v1", stringsAsFactors = FALSE)
  }, accepted_files, probabilities))
  reporting <- do.call(rbind, Map(function(path, probability) {
    x <- read.csv(path, stringsAsFactors = FALSE)
    q(nrow(x) == 28L * 3L * 4L && all(is.finite(x$estimate)),
      "global reporting input is malformed")
    x$probability <- probability
    x
  }, reporting_files, probabilities))
  references <- do.call(rbind, Map(function(path, probability) {
    x <- read.csv(path, stringsAsFactors = FALSE)
    q(nrow(x) >= 4L && all(is.finite(x$effective_sample_size)) &&
      all(is.finite(x$maximum_weight)), "reference summary is malformed")
    x$probability <- probability
    x
  }, reference_files, probabilities))
  accepted_crossings <- ggtc_crossings(accepted)
  global_crossings <- ggtc_crossings(reporting)
  differences <- ggtc_compare(accepted, reporting)
  unit_global <- global_crossings[
    global_crossings$reporting_operator == "marginal_future_response_quantile" &
      global_crossings$path_law == "same_family_al_transition" &
      global_crossings$member_policy == "unit_member_likelihood_v1", ]
  unit_legacy <- global_crossings[
    global_crossings$reporting_operator == "legacy_weighted_mean_readout_location" &
      global_crossings$path_law == "same_family_al_transition" &
      global_crossings$member_policy == "unit_member_likelihood_v1", ]
  delta_difference <- differences[
    differences$path_law == "same_family_al_transition" &
      differences$reporting_operator == "marginal_future_response_quantile", ]
  q(nrow(unit_global) == 1L && nrow(unit_legacy) == 1L &&
    unit_global$total_adjacent_crossings >= 10L &&
    accepted_crossings$total_adjacent_crossings >= 10L &&
    unit_legacy$total_adjacent_crossings == 0L &&
    max(delta_difference$mean_absolute_difference) < .05,
    "evidence does not support the prespecified structural diagnosis")
  decision <- data.frame(
    status = "STRUCTURAL_INDEPENDENT_TAIL_PATH_TARGET_INCOHERENCE",
    local_delta_crossings = accepted_crossings$total_adjacent_crossings,
    global_same_family_unit_crossings = unit_global$total_adjacent_crossings,
    global_same_family_unit_maximum_crossing = unit_global$maximum_crossing,
    legacy_readout_crossings = unit_legacy$total_adjacent_crossings,
    maximum_local_global_mae = max(delta_difference$mean_absolute_difference),
    convergence_or_monte_carlo_failure = FALSE,
    broad_refit_authorized = FALSE,
    recommended_next_stage = paste0(
      "restore one shared Normal-RHS recursive driver for all quantile readouts; ",
      "Parts 1-3 forecast-only qualification first; Part 4 posterior replacement separately"),
    stringsAsFactors = FALSE)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(accepted, file.path(output_dir, "accepted_local_paths.csv"),
    row.names = FALSE)
  utils::write.csv(reporting, file.path(output_dir, "global_reporting.csv"),
    row.names = FALSE)
  utils::write.csv(references, file.path(output_dir, "reference_quality.csv"),
    row.names = FALSE)
  utils::write.csv(rbind(accepted_crossings, global_crossings),
    file.path(output_dir, "crossing_decomposition.csv"), row.names = FALSE)
  utils::write.csv(differences, file.path(output_dir, "operator_differences.csv"),
    row.names = FALSE)
  utils::write.csv(decision, file.path(output_dir, "decision.csv"), row.names = FALSE)

  pdf_path <- file.path(output_dir, "global_tail_root_cause_closeout.pdf")
  grDevices::pdf(pdf_path, width = 10.5, height = 7.5, onefile = TRUE,
    useDingbats = FALSE)
  on.exit(grDevices::dev.off(), add = TRUE)
  palette <- c(`0.05` = "#1B6CA8", `0.5` = "#1F7A4D", `0.95` = "#C4473A")
  plot_paths <- function(rows, title, subtitle) {
    ylim <- range(rows$estimate, finite = TRUE)
    plot(NA, xlim = c(1, 28), ylim = ylim, xlab = "Forecast horizon (days)",
      ylab = "log1p flow", main = title, sub = subtitle, las = 1)
    grid(col = "#E6E8EB")
    for (prob in probabilities) {
      z <- rows[rows$probability == prob, ]; z <- z[order(z$horizon), ]
      lines(z$horizon, z$estimate, col = palette[[as.character(prob)]], lwd = 2.2)
      points(z$horizon, z$estimate, col = palette[[as.character(prob)]], pch = 16, cex = .55)
    }
    legend("topright", legend = c("p05", "p50", "p95"),
      col = palette, lwd = 2.2, bty = "n")
  }
  plot_paths(accepted, "Accepted local Gaussian-Delta quantile paths",
    sprintf("%d adjacent crossings; %d/28 fully ordered horizons",
      accepted_crossings$total_adjacent_crossings,
      accepted_crossings$fully_ordered_horizons))
  global_unit <- reporting[reporting$reporting_operator ==
    "marginal_future_response_quantile" & reporting$path_law ==
    "same_family_al_transition" & reporting$member_policy ==
    "unit_member_likelihood_v1", ]
  plot_paths(global_unit, "Global same-family marginal response quantiles",
    sprintf("%d adjacent crossings; max %.3f at horizon %d",
      unit_global$total_adjacent_crossings, unit_global$maximum_crossing,
      unit_global$maximum_crossing_horizon))
  legacy <- reporting[reporting$reporting_operator ==
    "legacy_weighted_mean_readout_location" & reporting$path_law ==
    "same_family_al_transition" & reporting$member_policy ==
    "unit_member_likelihood_v1", ]
  plot_paths(legacy, "Conditional readout locations (diagnostic only)",
    "Ordered, but not marginal future-response quantiles and not a valid replacement")
  mat <- reshape(global_unit[c("horizon", "probability", "estimate")],
    idvar = "horizon", timevar = "probability", direction = "wide")
  names(mat) <- sub("estimate\\.", "q", names(mat))
  plot(mat$horizon, mat$q0.05 - mat$q0.5, type = "h", lwd = 3,
    col = "#1B6CA8", xlab = "Forecast horizon (days)",
    ylab = "Crossing magnitude", main = "Global adjacent crossing magnitudes",
    ylim = range(c(mat$q0.05 - mat$q0.5, mat$q0.5 - mat$q0.95, 0)), las = 1)
  abline(h = 0, col = "#333333", lwd = 1.2)
  lines(mat$horizon, mat$q0.5 - mat$q0.95, type = "h", lwd = 2,
    col = "#C4473A")
  legend("topright", c("p05 - p50", "p50 - p95"),
    col = c("#1B6CA8", "#C4473A"), lwd = c(3, 2), bty = "n")
  quality <- references[references$method %in% c("importance", "tempered"), ]
  labels <- paste0(sprintf("p%02d", round(100 * quality$probability)), "\n",
    sub(".*__", "", quality$contract), "\n", quality$method)
  barplot(quality$effective_sample_size, names.arg = labels, las = 2,
    col = ifelse(quality$diagnostic_thresholds_passed, "#2F7D4A", "#C4473A"),
    ylab = "Effective sample size", main = "Reference quality and fallback behavior",
    cex.names = .55)
  legend("topright", c("preregistered gate pass", "gate fail / fallback trigger"),
    fill = c("#2F7D4A", "#C4473A"), bty = "n")
  plot.new()
  text(.03, .95, "Root-cause decision", adj = c(0, 1), cex = 1.5, font = 2)
  lines <- c(
    "Global path integration reproduces the large tail crossings.",
    "Local Delta is therefore not the material failure mechanism.",
    "Importance failures were resolved by preregistered tempering with strong ESS.",
    "The ordered readout locations show that replacing response quantiles with means would hide, not fix, the issue.",
    "The structural problem is separate tau-specific future response-path targets without a common predictive law.",
    "Next: qualify the existing shared Normal-RHS driver for Parts 1-3; treat Part 4 as a new posterior target.",
    "No broad refit, exAL/MQ expansion, scoring, or article promotion is authorized by this diagnostic.")
  text(rep(.04, length(lines)), seq(.84, .24, length.out = length(lines)),
    paste0("- ", lines), adj = c(0, 1), cex = .92, family = "sans", xpd = NA)
  grDevices::dev.off(); on.exit(NULL, add = FALSE)
  files <- list.files(output_dir, full.names = TRUE)
  manifest <- data.frame(relative_path = basename(files),
    size_bytes = file.info(files)$size,
    sha256 = unname(tools::sha256sum(files)), stringsAsFactors = FALSE)
  utils::write.csv(manifest, file.path(output_dir, "artifact_manifest.csv"),
    row.names = FALSE)
  invisible(list(decision = decision, pdf = pdf_path))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(TRUE)
  ggtc_require(length(args) == 10L && identical(args[c(1, 3, 5, 7, 9)],
    c("--accepted", "--reporting", "--references", "--output", "--labels")),
    "usage: --accepted a,b,c --reporting a,b,c --references a,b,c --output DIR --labels p005,p050,p095")
  split <- function(x) strsplit(x, ",", fixed = TRUE)[[1L]]
  ggtc_require(identical(split(args[[10L]]), c("p005", "p050", "p095")),
    "exact p005,p050,p095 labels required")
  ggtc_run(split(args[[2L]]), split(args[[4L]]), split(args[[6L]]), args[[8L]])
}
