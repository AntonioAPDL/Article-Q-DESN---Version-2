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
  baseline_dir = "application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702",
  followup_dir = "",
  baseline_crossing_audit_dir = "",
  followup_crossing_audit_dir = "",
  phase4e_audit_dir = "",
  output_dir = ""
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

read_required <- function(dir, filename) {
  path <- file.path(dir, filename)
  if (!file.exists(path)) stop(sprintf("Missing required Phase 4f input: %s", path), call. = FALSE)
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

repo_rel <- function(path) app_prefer_repo_relative_path(normalizePath(path, mustWork = TRUE))

short_scenario <- function(x) {
  out <- sub("__calibration_r[0-9]+$", "", as.character(x))
  out <- gsub("_", "\n", out, fixed = TRUE)
  out
}

write_png <- function(path, width = 1800L, height = 1200L, res = 160L, code) {
  png_type <- if (isTRUE(capabilities("cairo"))) "cairo" else "cairo-png"
  grDevices::png(path, width = width, height = height, res = res, type = png_type)
  on.exit(grDevices::dev.off(), add = TRUE)
  force(code)
  normalizePath(path, mustWork = TRUE)
}

safe_range <- function(...) {
  vals <- unlist(list(...), use.names = FALSE)
  vals <- vals[is.finite(vals)]
  if (!length(vals)) return(c(0, 1))
  rng <- range(vals)
  if (diff(rng) <= 0) rng <- rng + c(-0.5, 0.5)
  pad <- 0.08 * diff(rng)
  rng + c(-pad, pad)
}

load_qhat_ladder <- function(dir, scenario_id, origin_index, forecast_time_index, raw = TRUE) {
  filename <- if (raw) "forecast_quantiles_raw.csv" else "forecast_quantiles.csv"
  x <- read_required(dir, filename)
  x <- x[
    x$scenario_id == scenario_id &
      x$origin_index == origin_index &
      x$forecast_time_index == forecast_time_index,
    ,
    drop = FALSE
  ]
  x[order(x$tau), , drop = FALSE]
}

make_tau_pair <- function(x) sprintf("%.2f-%.2f", as.numeric(x$lower_tau), as.numeric(x$upper_tau))

baseline_dir <- normalizePath(as.character(arg_value("baseline_dir"))[[1L]], mustWork = TRUE)
baseline_phase3_dir <- file.path(baseline_dir, "phase3_forecast_validation")
followup_dir <- if (nzchar(as.character(arg_value("followup_dir")))) {
  normalizePath(as.character(arg_value("followup_dir"))[[1L]], mustWork = TRUE)
} else {
  normalizePath(file.path(baseline_dir, "phase4e_targeted_crossing_followup_vb480"), mustWork = TRUE)
}
baseline_crossing_audit_dir <- if (nzchar(as.character(arg_value("baseline_crossing_audit_dir")))) {
  normalizePath(as.character(arg_value("baseline_crossing_audit_dir"))[[1L]], mustWork = TRUE)
} else {
  normalizePath(file.path(baseline_dir, "phase4c_crossing_audit"), mustWork = TRUE)
}
followup_crossing_audit_dir <- if (nzchar(as.character(arg_value("followup_crossing_audit_dir")))) {
  normalizePath(as.character(arg_value("followup_crossing_audit_dir"))[[1L]], mustWork = TRUE)
} else {
  normalizePath(file.path(followup_dir, "phase4e_crossing_audit"), mustWork = TRUE)
}
phase4e_audit_dir <- if (nzchar(as.character(arg_value("phase4e_audit_dir")))) {
  normalizePath(as.character(arg_value("phase4e_audit_dir"))[[1L]], mustWork = TRUE)
} else {
  normalizePath(file.path(followup_dir, "phase4e_raw_crossing_vb_audit"), mustWork = TRUE)
}
out_dir <- if (nzchar(as.character(arg_value("output_dir")))) {
  as.character(arg_value("output_dir"))
} else {
  file.path(baseline_dir, "phase4f_sparsity_tau0_diagnostics")
}
out_dir <- normalizePath(out_dir, mustWork = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

scenario_comparison <- read_required(phase4e_audit_dir, "phase4e_before_after_scenario_comparison.csv")
overall <- read_required(phase4e_audit_dir, "phase4e_before_after_overall_summary.csv")
pair_compare <- read_required(phase4e_audit_dir, "phase4e_crossing_origin_set_comparison.csv")
baseline_pairs <- read_required(baseline_crossing_audit_dir, "crossing_pair_detail.csv")
followup_pairs <- read_required(followup_crossing_audit_dir, "crossing_pair_detail.csv")
baseline_adjust <- read_required(baseline_phase3_dir, "forecast_monotone_adjustment.csv")
followup_adjust <- read_required(followup_dir, "forecast_monotone_adjustment.csv")

scenario_ids <- scenario_comparison$scenario_id
scenario_labels <- short_scenario(scenario_ids)
colors <- c(baseline = "#6B7280", vb480 = "#2563EB", contract = "#059669", raw = "#DC2626", truth = "#111827")

plot_paths <- list()

plot_paths[["01_raw_contract_crossing_counts_by_scenario"]] <- write_png(
  file.path(out_dir, "01_raw_contract_crossing_counts_by_scenario.png"),
  width = 1900L,
  height = 1300L,
  code = {
    mat <- rbind(
      baseline_raw = scenario_comparison$baseline_raw_crossing_pairs,
      vb480_raw = scenario_comparison$followup_raw_crossing_pairs,
      baseline_contract = scenario_comparison$baseline_contract_crossing_pairs,
      vb480_contract = scenario_comparison$followup_contract_crossing_pairs
    )
    old <- graphics::par(mar = c(5, 11.5, 4, 1), las = 1)
    on.exit(graphics::par(old), add = TRUE)
    bp <- graphics::barplot(
      mat,
      beside = TRUE,
      horiz = TRUE,
      col = c(colors[["baseline"]], colors[["vb480"]], "#9CA3AF", colors[["contract"]]),
      border = NA,
      names.arg = gsub("\n", " ", scenario_labels, fixed = TRUE),
      xlab = "Crossing pairs",
      xlim = c(0, max(mat, na.rm = TRUE) + 1.5),
      main = "Raw crossings persist; contract crossings remain zero"
    )
    graphics::legend(
      "bottomright",
      fill = c(colors[["baseline"]], colors[["vb480"]], "#9CA3AF", colors[["contract"]]),
      border = NA,
      legend = c("Baseline raw", "VB480 raw", "Baseline contract", "VB480 contract"),
      bty = "n"
    )
    graphics::text(mat + 0.15, bp, labels = ifelse(mat > 0, mat, ""), cex = 0.75, xpd = TRUE)
    graphics::mtext("Phase 4e targeted rows: stronger VB mostly solved max-iteration review, not raw crossings", side = 3, line = 0.3, cex = 0.85)
  }
)

plot_paths[["02_vb_max_iter_rate_vs_raw_crossings"]] <- write_png(
  file.path(out_dir, "02_vb_max_iter_rate_vs_raw_crossings.png"),
  height = 1300L,
  code = {
    old <- graphics::par(mfrow = c(1, 2), mar = c(8.5, 5, 4, 1), las = 1)
    on.exit(graphics::par(old), add = TRUE)
    raw_ylim <- c(0, max(c(scenario_comparison$baseline_raw_crossing_pairs, scenario_comparison$followup_raw_crossing_pairs), na.rm = TRUE) + 1)
    for (prefix in c("baseline", "followup")) {
      rate <- scenario_comparison[[paste0(prefix, "_vb_max_iter_rate")]]
      crosses <- scenario_comparison[[paste0(prefix, "_raw_crossing_pairs")]]
      title <- if (identical(prefix, "baseline")) "Baseline controls" else "Stronger VB controls"
      graphics::plot(
        rate,
        crosses,
        xlim = c(0, 1),
        ylim = raw_ylim,
        pch = 21,
        bg = if (identical(prefix, "baseline")) colors[["baseline"]] else colors[["vb480"]],
        col = "white",
        cex = 1.6,
        xlab = "VB max-iteration rate",
        ylab = "Raw crossing pairs",
        main = title
      )
      graphics::abline(h = 0, col = "#D1D5DB")
      graphics::abline(v = 0.25, col = "#F59E0B", lty = 2)
      graphics::text(rate, crosses + 0.35, labels = seq_along(scenario_ids), cex = 0.75)
    }
  }
)

plot_paths[["03_max_monotone_adjustment_by_scenario"]] <- write_png(
  file.path(out_dir, "03_max_monotone_adjustment_by_scenario.png"),
  height = 1300L,
  code = {
    mat <- rbind(
      baseline = scenario_comparison$baseline_max_monotone_adjustment,
      vb480 = scenario_comparison$followup_max_monotone_adjustment
    )
    old <- graphics::par(mar = c(8.5, 5, 4, 1), las = 1)
    on.exit(graphics::par(old), add = TRUE)
    bp <- graphics::barplot(
      mat,
      beside = TRUE,
      col = c(colors[["baseline"]], colors[["vb480"]]),
      border = NA,
      names.arg = scenario_labels,
      ylab = "Max absolute monotone adjustment",
      ylim = c(0, max(mat, na.rm = TRUE) * 1.25),
      main = "Raw-to-contract adjustment size by targeted scenario"
    )
    graphics::legend("topright", fill = c(colors[["baseline"]], colors[["vb480"]]), border = NA, legend = c("Baseline", "VB480"), bty = "n")
    graphics::text(bp, mat, labels = ifelse(mat > 0, sprintf("%.3f", mat), ""), pos = 3, cex = 0.7)
  }
)

plot_paths[["04_crossing_magnitude_by_tau_pair"]] <- write_png(
  file.path(out_dir, "04_crossing_magnitude_by_tau_pair.png"),
  code = {
    baseline_pairs$run <- "Baseline"
    followup_pairs$run <- "VB480"
    x <- rbind(baseline_pairs, followup_pairs)
    x$tau_pair <- make_tau_pair(x)
    x$group <- paste(x$run, x$tau_pair, sep = "\n")
    old <- graphics::par(mar = c(7, 5, 4, 1), las = 1)
    on.exit(graphics::par(old), add = TRUE)
    graphics::boxplot(
      crossing_magnitude ~ group,
      data = x,
      col = rep(c("#D1D5DB", "#BFDBFE"), length.out = length(unique(x$group))),
      border = "#374151",
      ylab = "Raw crossing magnitude",
      main = "Crossing magnitudes concentrate at adjacent extreme-tail pairs"
    )
    graphics::stripchart(crossing_magnitude ~ group, data = x, vertical = TRUE, add = TRUE, method = "jitter", pch = 16, col = grDevices::adjustcolor("#111827", alpha.f = 0.65))
  }
)

plot_paths[["05_qhat_ladder_examples_baseline_vs_vb480"]] <- write_png(
  file.path(out_dir, "05_qhat_ladder_examples_baseline_vs_vb480.png"),
  width = 2200L,
  height = 1700L,
  code = {
    top_pairs <- baseline_pairs[order(-baseline_pairs$crossing_magnitude), , drop = FALSE]
    top_pairs <- top_pairs[!duplicated(top_pairs$scenario_id), , drop = FALSE]
    top_pairs <- top_pairs[seq_len(min(4L, nrow(top_pairs))), , drop = FALSE]
    old <- graphics::par(mfrow = c(nrow(top_pairs), 2), mar = c(4.5, 4.3, 3.2, 1), las = 1)
    on.exit(graphics::par(old), add = TRUE)
    for (ii in seq_len(nrow(top_pairs))) {
      ex <- top_pairs[ii, , drop = FALSE]
      for (run_label in c("Baseline", "VB480")) {
        phase_dir <- if (identical(run_label, "Baseline")) baseline_phase3_dir else followup_dir
        raw <- load_qhat_ladder(phase_dir, ex$scenario_id[[1L]], ex$origin_index[[1L]], ex$forecast_time_index[[1L]], raw = TRUE)
        contract <- load_qhat_ladder(phase_dir, ex$scenario_id[[1L]], ex$origin_index[[1L]], ex$forecast_time_index[[1L]], raw = FALSE)
        yr <- safe_range(raw$qhat, contract$qhat, raw$true_quantile)
        graphics::plot(
          raw$tau,
          raw$qhat,
          type = "b",
          pch = 16,
          col = colors[["raw"]],
          lty = 2,
          ylim = yr,
          xlab = "tau",
          ylab = "forecast quantile",
          main = sprintf("%s: %s\norigin %s, time %s", run_label, sub("__calibration.*$", "", ex$scenario_id[[1L]]), ex$origin_index[[1L]], ex$forecast_time_index[[1L]])
        )
        graphics::lines(contract$tau, contract$qhat, type = "b", pch = 15, col = colors[["contract"]], lwd = 2)
        graphics::lines(raw$tau, raw$true_quantile, type = "b", pch = 17, col = colors[["truth"]], lwd = 2)
        graphics::abline(v = c(ex$lower_tau[[1L]], ex$upper_tau[[1L]]), col = "#F59E0B", lty = 3)
        if (ii == 1L) {
          graphics::legend(
            "topleft",
            legend = c("Raw qhat", "Contract qhat", "Truth"),
            col = c(colors[["raw"]], colors[["contract"]], colors[["truth"]]),
            pch = c(16, 15, 17),
            lty = c(2, 1, 1),
            bty = "n",
            cex = 0.8
          )
        }
      }
    }
  }
)

plot_paths[["06_crossing_origin_set_overlap"]] <- write_png(
  file.path(out_dir, "06_crossing_origin_set_overlap.png"),
  height = 1100L,
  code = {
    counts <- table(pair_compare$set_status)
    counts <- counts[c("both", "baseline_only", "followup_only")]
    counts[is.na(counts)] <- 0L
    old <- graphics::par(mar = c(5, 5, 4, 1), las = 1)
    on.exit(graphics::par(old), add = TRUE)
    bp <- graphics::barplot(
      counts,
      col = c("#4B5563", "#F59E0B", "#2563EB"),
      border = NA,
      ylab = "Crossing pair origins",
      main = "Raw crossing set overlap: stronger VB removes only one event"
    )
    graphics::text(bp, counts, labels = as.integer(counts), pos = 3)
  }
)

plot_paths[["07_rhs_tau0_prior_precision_curve"]] <- write_png(
  file.path(out_dir, "07_rhs_tau0_prior_precision_curve.png"),
  code = {
    tau0 <- exp(seq(log(0.05), log(5), length.out = 300L))
    lambda2 <- 1
    zeta_levels <- c(Inf, 10, 4, 1)
    mat <- sapply(zeta_levels, function(zeta2) 1 / (tau0^2 * lambda2) + if (is.finite(zeta2)) 1 / zeta2 else 0)
    old <- graphics::par(mar = c(5, 5, 4, 2), las = 1)
    on.exit(graphics::par(old), add = TRUE)
    graphics::matplot(
      tau0,
      mat,
      type = "l",
      log = "xy",
      lwd = 2,
      lty = 1,
      col = c("#111827", "#2563EB", "#059669", "#DC2626"),
      xlab = "tau0 prior scale",
      ylab = "prior precision",
      main = "RHS prior precision decreases as tau0 increases"
    )
    graphics::grid(col = "#E5E7EB")
    graphics::legend(
      "topright",
      legend = paste0("zeta2 = ", c("Inf", "10", "4", "1")),
      col = c("#111827", "#2563EB", "#059669", "#DC2626"),
      lwd = 2,
      bty = "n"
    )
    graphics::mtext("Precision = 1 / (tau0^2 * lambda2) + 1 / zeta2, shown for lambda2 = 1", side = 3, line = 0.2, cex = 0.85)
  }
)

plot_paths[["08_tau_pair_crossing_heatmap"]] <- write_png(
  file.path(out_dir, "08_tau_pair_crossing_heatmap.png"),
  width = 1800L,
  height = 1300L,
  code = {
    baseline_pairs$tau_pair <- make_tau_pair(baseline_pairs)
    tab <- table(factor(baseline_pairs$scenario_id, levels = scenario_ids), baseline_pairs$tau_pair)
    old <- graphics::par(mar = c(6, 12, 4, 2), las = 1)
    on.exit(graphics::par(old), add = TRUE)
    graphics::image(
      x = seq_len(ncol(tab)),
      y = seq_len(nrow(tab)),
      z = t(as.matrix(tab)),
      axes = FALSE,
      col = grDevices::colorRampPalette(c("#FFFFFF", "#BFDBFE", "#1D4ED8"))(20),
      xlab = "Adjacent tau pair",
      ylab = "",
      main = "Baseline raw crossing counts by scenario and adjacent tau pair"
    )
    graphics::axis(1, at = seq_len(ncol(tab)), labels = colnames(tab))
    graphics::axis(2, at = seq_len(nrow(tab)), labels = short_scenario(rownames(tab)))
    for (i in seq_len(nrow(tab))) {
      for (j in seq_len(ncol(tab))) {
        val <- tab[i, j]
        if (val > 0) graphics::text(j, i, labels = val, cex = 0.9, col = "#111827")
      }
    }
  }
)

prior_grid <- expand.grid(
  tau0 = c(0.10, 0.25, 0.50, 1, 2, 5),
  zeta2 = c(Inf, 10, 4, 1)
)
prior_grid$lambda2 <- 1
prior_grid$rhs_prior_precision <- 1 / (prior_grid$tau0^2 * prior_grid$lambda2) +
  ifelse(is.finite(prior_grid$zeta2), 1 / prior_grid$zeta2, 0)
prior_grid$rhs_prior_variance_equivalent <- 1 / prior_grid$rhs_prior_precision

summary_rows <- data.frame(
  metric = c(
    "tau_grid_size",
    "baseline_raw_crossing_pairs",
    "followup_raw_crossing_pairs",
    "baseline_contract_crossing_pairs",
    "followup_contract_crossing_pairs",
    "baseline_vb_max_iter_rate",
    "followup_vb_max_iter_rate",
    "raw_crossing_reduction_fraction"
  ),
  value = c(
    length(unique(read_required(baseline_phase3_dir, "forecast_quantiles.csv")$tau)),
    overall$baseline_raw_crossing_pairs[[1L]],
    overall$followup_raw_crossing_pairs[[1L]],
    overall$baseline_contract_crossing_pairs[[1L]],
    overall$followup_contract_crossing_pairs[[1L]],
    overall$baseline_vb_max_iter_rate[[1L]],
    overall$followup_vb_max_iter_rate[[1L]],
    if (overall$baseline_raw_crossing_pairs[[1L]] > 0) {
      (overall$baseline_raw_crossing_pairs[[1L]] - overall$followup_raw_crossing_pairs[[1L]]) /
        overall$baseline_raw_crossing_pairs[[1L]]
    } else {
      NA_real_
    }
  ),
  stringsAsFactors = FALSE
)

prior_interpretation <- data.frame(
  topic = c(
    "implemented_rhs_precision",
    "tau0_direction",
    "larger_tau0_implication",
    "sparsity_direction",
    "coefficient_similarity_direction",
    "desn_design_direction"
  ),
  finding = c(
    "The current RHS prior precision is 1 / (tau2 * lambda2) + 1 / zeta2, with tau2 initialized from tau0^2.",
    "Increasing tau0 decreases prior precision and increases prior variance when lambda2 is fixed.",
    "A larger tau0 is a weaker RHS shrinkage setting, so it is not the direct lever for reducing noisy readout coefficients.",
    "For more sparsity/noise reduction, the direct sensitivity grid should test smaller tau0 and finite slab scales zeta2.",
    "To force adjacent quantile coefficients to be more similar without flattening the whole readout, prefer stronger shrinkage on adjacent innovation blocks than on the anchor block.",
    "DESN design should be audited through feature standardization, reservoir-feature dimension, spectral radius/leak controls, and tail-specific sensitivity rather than changing article outputs silently."
  ),
  evidence = c(
    "application/R/joint_qvp_qdesn.R: app_joint_qvp_rhs_ns_precision and app_joint_qvp_initialize_rhs_state",
    "See 07_rhs_tau0_prior_precision_curve.png and phase4f_rhs_prior_tau0_precision_grid.csv.",
    "Phase 4e showed stronger VB iterations reduced max-iteration rates but left 22 of 23 raw crossings, so additional prior/design levers need targeted testing.",
    "Candidate exploratory grid: tau0 in {1, 0.5, 0.25, 0.1}; zeta2 in {Inf, 10, 4, 1}; keep seeds and origins fixed.",
    "This may require separating anchor_tau0 from innovation_tau0 in a narrow experimental branch.",
    "Use targeted crossing scenario rows first, then only rerun full calibration after a material raw-crossing improvement is observed."
  ),
  stringsAsFactors = FALSE
)

recommendation <- data.frame(
  gate_status = "review",
  recommendation_status = "run_targeted_prior_design_sensitivity_before_full_calibration",
  larger_tau0_recommended = FALSE,
  smaller_tau0_candidate = TRUE,
  separate_anchor_innovation_shrinkage_candidate = TRUE,
  finite_zeta2_candidate = TRUE,
  keep_raw_contract_policy = TRUE,
  rationale = paste(
    "Raw crossings persisted under stronger VB controls, while contract crossings stayed at zero.",
    "The implemented tau0 direction means larger tau0 weakens shrinkage.",
    "The next high-value experiment is a targeted fixed-seed sensitivity grid over stronger RHS shrinkage and readout/DESN controls, not another full calibration campaign."
  ),
  stringsAsFactors = FALSE
)

plot_index <- data.frame(
  figure = basename(unlist(plot_paths, use.names = FALSE)),
  label = names(plot_paths),
  relative_path = vapply(plot_paths, repo_rel, character(1L)),
  sha256 = vapply(plot_paths, app_sha256_file, character(1L)),
  description = c(
    "Baseline and stronger-VB raw/contract crossing counts by targeted scenario.",
    "Scenario-level relationship between VB max-iteration rate and raw crossing counts.",
    "Raw-to-contract monotone adjustment sizes by targeted scenario.",
    "Raw crossing magnitude distribution by adjacent tau pair and run.",
    "Example forecast quantile ladders showing raw, contract, and true quantiles.",
    "Overlap of raw crossing origin/tau-pair events before and after stronger VB.",
    "RHS prior precision curve as a function of tau0 and zeta2.",
    "Baseline raw crossing count heatmap by scenario and adjacent tau pair."
  ),
  stringsAsFactors = FALSE
)

readme_path <- file.path(out_dir, "README.md")
writeLines(c(
  "# Joint-QVP Phase 4f Sparsity/Tau0 Diagnostic Plots",
  "",
  "This artifact investigates whether stronger RHS sparsity, more similar adjacent quantile coefficients, or DESN/readout design changes are plausible next levers for reducing raw forecast quantile crossings.",
  "",
  "The key prior interpretation is directional: in the current implementation, larger `tau0` is weaker RHS shrinkage, not stronger shrinkage.",
  "",
  sprintf("- Baseline raw crossings: %s", overall$baseline_raw_crossing_pairs[[1L]]),
  sprintf("- Stronger-VB raw crossings: %s", overall$followup_raw_crossing_pairs[[1L]]),
  sprintf("- Baseline contract crossings: %s", overall$baseline_contract_crossing_pairs[[1L]]),
  sprintf("- Stronger-VB contract crossings: %s", overall$followup_contract_crossing_pairs[[1L]]),
  sprintf("- Baseline VB max-iteration rate: %.3f", overall$baseline_vb_max_iter_rate[[1L]]),
  sprintf("- Stronger-VB VB max-iteration rate: %.3f", overall$followup_vb_max_iter_rate[[1L]]),
  "",
  "Primary recommendation: run a targeted fixed-seed prior/design sensitivity before another full calibration campaign. Test smaller `tau0`, finite `zeta2`, and ideally separate anchor and adjacent-innovation shrinkage. Keep the raw/contract forecast policy intact.",
  "",
  "Primary files:",
  "",
  "- `phase4f_plot_index.csv`: figure index with hashes.",
  "- `phase4f_summary.csv`: compact numerical summary.",
  "- `phase4f_rhs_prior_tau0_precision_grid.csv`: prior precision grid for tau0/zeta2 interpretation.",
  "- `phase4f_prior_interpretation.csv`: audit findings for tau0, sparsity, coefficient similarity, and DESN design.",
  "- `phase4f_sparsity_recommendation.csv`: conservative next-action recommendation.",
  "- `artifact_manifest.csv`: SHA-256 hashes."
), readme_path, useBytes = TRUE)

paths <- c(
  plot_index = app_joint_qvp_write_csv(plot_index, file.path(out_dir, "phase4f_plot_index.csv")),
  summary = app_joint_qvp_write_csv(summary_rows, file.path(out_dir, "phase4f_summary.csv")),
  rhs_prior_tau0_precision_grid = app_joint_qvp_write_csv(prior_grid, file.path(out_dir, "phase4f_rhs_prior_tau0_precision_grid.csv")),
  prior_interpretation = app_joint_qvp_write_csv(prior_interpretation, file.path(out_dir, "phase4f_prior_interpretation.csv")),
  sparsity_recommendation = app_joint_qvp_write_csv(recommendation, file.path(out_dir, "phase4f_sparsity_recommendation.csv")),
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

cat(sprintf("Joint-QVP Phase 4f sparsity/tau0 diagnostics written to %s\n", out_dir))
cat(sprintf("Plots: %s\n", length(plot_paths)))
cat(sprintf("Recommendation: %s\n", recommendation$recommendation_status[[1L]]))
cat(sprintf("Artifact manifest: %s\n", manifest_path))
