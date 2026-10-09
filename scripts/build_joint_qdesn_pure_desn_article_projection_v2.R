#!/usr/bin/env Rscript

# Versioned article projection. The optional reconstruction step reads frozen
# fits/draws; the default public mode uses the tracked, authenticated summaries.
# Neither mode optimizes a variational objective or simulates an MCMC chain.
options(stringsAsFactors = FALSE, digits = 17)
args <- commandArgs(trailingOnly = TRUE)
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), ".."))
setwd(root)
Rscript <- file.path(R.home("bin"), "Rscript")
expect <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)
sha <- function(path) unname(tools::sha256sum(path)[[1L]])
prefix <- "joint_qdesn_pure_desn_v2_"
path <- function(name) file.path("tables", paste0(prefix, name))
read_table <- function(name) read.csv(path(name), check.names = FALSE)
if ("--reconstruct" %in% args) {
  forward <- args[args != "--reconstruct"]
  status <- system2(Rscript, c(shQuote("scripts/reconstruct_joint_qdesn_laplace_article_projection_v2.R"),
                              shQuote(forward)))
  expect(status == 0L, "Frozen deterministic reconstruction failed.")
}
score <- read_table("forecast_score_summary.csv")
fit <- read_table("fit_oracle_diagnostics.csv")
cross <- read_table("crossing_summary.csv")
contrasts_all <- read_table("posterior_contrast_summary.csv")
counts <- read_table("draw_cardinality.csv")
source("scripts/qdesn_evaluation_figure_style.R")
scenarios <- qdesn_scenario_order
models <- sub("_vb$", "_mcmc", qdesn_joint_model_order)
model_label <- setNames(unname(qdesn_joint_model_labels), models)
scenario_label <- qdesn_scenario_labels
scenario_label[["student_t_location_scale"]] <- "Student-\\(t\\) location--scale"
key <- function(x) paste(x$scenario_id, x$model_cell_id, x$inference_method, sep = "|")
expect(nrow(score) == 64L && !anyDuplicated(key(score)) &&
       all(table(score$inference_method) == 32L), "Incomplete versioned scientific packet.")
expect(all(is.finite(score$posterior_score_mean)) &&
       all(score$contract_crossing_pairs == 0) &&
       all(score$canonical_contract_crossing_pairs == 0) &&
       all(score$path_contract_crossing_pairs == 0), "Invalid scores or reporting grids.")
mcmc <- score[score$inference_method == "mcmc", , drop = FALSE]
vb <- score[score$inference_method == "vb", , drop = FALSE]
fit_mcmc <- fit[match(key(mcmc), key(fit)), , drop = FALSE]
counts_mcmc <- counts[match(key(mcmc), key(counts)), , drop = FALSE]
expect(nrow(counts_mcmc) == 32L && all(is.finite(counts_mcmc$n_score_draws)) &&
       all(counts_mcmc$n_score_draws > 0), "Actual score-draw counts are missing.")
expect(all(mcmc$score_stability_status == "pass"), "An active MCMC stability qualification remains.")
crossings <- do.call(rbind, lapply(models, function(mid) {
  ii <- which(mcmc$model_id == mid)
  data.frame(model_id = mid,
    fit_raw_pairs = sum(fit_mcmc$fit_raw_crossing_pairs[ii]),
    fit_opportunities = length(ii) * 500L * 6L,
    forecast_raw_pairs = sum(mcmc$canonical_raw_crossing_pairs[ii]),
    forecast_opportunities = length(ii) * 990L * 6L,
    posterior_forecast_raw_pairs = sum(mcmc$raw_crossing_pairs[ii]),
    posterior_forecast_opportunities = sum(counts_mcmc$n_score_draws[ii] * 990L * 6L),
    posterior_forecast_raw_percent_equal_scenario = mean(100 * mcmc$raw_crossing_pairs[ii] /
      (counts_mcmc$n_score_draws[ii] * 990L * 6L)),
    mean_abs_adjustment = mean(mcmc$canonical_mean_abs_monotone_adjustment[ii]),
    max_abs_adjustment = max(mcmc$canonical_max_abs_monotone_adjustment[ii]),
    contract_pairs = sum(mcmc$canonical_contract_crossing_pairs[ii]))
}))
expect(identical(as.integer(crossings$forecast_raw_pairs), c(10L, 2608L, 0L, 288L)) &&
       all(crossings$forecast_opportunities == 47520), "Corrected crossing reconciliation failed.")
crossings$fit_raw_percent <- 100 * crossings$fit_raw_pairs / crossings$fit_opportunities
crossings$forecast_raw_percent <- 100 * crossings$forecast_raw_pairs / crossings$forecast_opportunities
crossings$posterior_forecast_raw_percent <- 100 * crossings$posterior_forecast_raw_pairs /
  crossings$posterior_forecast_opportunities
write.csv(crossings, path("crossing_rates.csv"), row.names = FALSE, na = "")
contrasts <- contrasts_all[contrasts_all$inference_method == "mcmc" &
  contrasts_all$contrast_type == "joint_minus_independent", , drop = FALSE]
expect(nrow(contrasts) == 16L &&
       sum(contrasts$q025_difference <= 0 & contrasts$q975_difference >= 0) == 14L &&
       sum(contrasts$q975_difference < 0) == 2L &&
       sum(contrasts$q025_difference > 0) == 0L, "Descriptive contrast reconciliation failed.")

table_start <- function(columns, header, position = "p", size = "footnotesize") c(
  paste0("\\begin{table}[", position, "]"), "\\centering", paste0("\\", size),
  "\\setlength{\\tabcolsep}{3pt}", "\\renewcommand{\\arraystretch}{1.08}",
  paste0("\\begin{tabular}{", columns, "}"), "\\toprule",
  paste0(header, " \\\\"), "\\midrule")
table_end <- function(caption, label) c("\\bottomrule", "\\end{tabular}",
  paste0("\\caption{", caption, "}"), paste0("\\label{", label, "}"), "\\end{table}")
write_tex <- function(lines, name) writeLines(lines, path(name), useBytes = TRUE)
fmt_interval <- function(center, lo, hi) sprintf("%.4f [%.4f, %.4f]", center, lo, hi)
balanced_table <- function(block, name, label, caption, fields, header, minima = FALSE) {
  lines <- table_start(paste0("@{}>{\\raggedright\\arraybackslash}p{0.26\\textwidth}",
    ">{\\raggedright\\arraybackslash}p{0.18\\textwidth}",
    paste(rep("r", length(fields)), collapse = ""), "@{}"), header)
  for (si in seq_along(scenarios)) {
    sid <- scenarios[[si]]
    x <- block[block$scenario_id == sid, , drop = FALSE]
    x <- x[match(models, x$model_id), , drop = FALSE]
    expect(nrow(x) == 4L && all(!is.na(x$model_id)), paste("Incomplete model block:", sid))
    for (mi in seq_along(models)) {
      values <- vapply(fields, function(field) sprintf("%.4f", x[[field]][[mi]]), character(1L))
      if (minima && mi == which.min(x$posterior_score_mean))
        values[[1L]] <- paste0("\\textbf{", values[[1L]], "}")
      lines <- c(lines, paste0(paste(c(if (mi == 1L) scenario_label[[sid]] else "",
        model_label[[models[[mi]]]], values), collapse = " & "), " \\\\"))
    }
    if (si < length(scenarios)) lines <- c(lines, "\\addlinespace[2pt]")
  }
  write_tex(c(lines, table_end(caption, label)), name)
}
score_fields <- c("posterior_score_mean", "posterior_score_median", "posterior_score_q025",
                  "posterior_score_q975", "canonical_origin_marginal_dgp_integrated_acrps")
score_header <- "Simulation setting & Model & Mean & Median & 2.5\\% & 97.5\\% & \\shortstack{Mean-grid\\\\score}"
balanced_table(mcmc, "score_table.tex", "tab:joint-qdesn-pure-desn-v2-score",
  paste0("DGP-integrated finite-grid \\(\\aCRPS\\) for the multi-quantile study. ",
    "Means, medians, and equal-tailed 95\\% limits describe posterior readout uncertainty conditional on each model's averaged recursive design. ",
    "The mean-grid score evaluates the projected posterior-mean quantile grid and differs from the posterior mean of the score. ",
    "Boldface marks descriptive numerical minima; every winner and runner-up marginal interval overlaps."),
  score_fields, score_header, TRUE)
balanced_table(vb, "vb_score_table.tex", "tab:joint-qdesn-pure-desn-v2-vb-score",
  paste0("Approximate variational DGP-integrated \\(\\aCRPS\\) under the same seven-level comparison. ",
    "Intervals condition on point intercepts and each model's averaged recursive design, omitting intercept covariance. ",
    "The mean-grid score evaluates the projected posterior-mean quantile grid."),
  score_fields, score_header)

lines <- table_start("@{}>{\\raggedright\\arraybackslash}p{0.30\\textwidth}rr@{}",
  "Simulation setting & AL & exAL", "!htbp")
for (sid in scenarios) {
  x <- contrasts[contrasts$scenario_id == sid, , drop = FALSE]
  x <- x[match(c("AL joint minus independent", "exAL joint minus independent"), x$contrast_label), , drop = FALSE]
  values <- mapply(fmt_interval, x$mean_difference, x$q025_difference, x$q975_difference, USE.NAMES = FALSE)
  lines <- c(lines, paste0(paste(c(scenario_label[[sid]], values), collapse = " & "), " \\\\"))
}
write_tex(c(lines, table_end(paste0("Joint-minus-independent differences in DGP-integrated \\(\\aCRPS\\), ",
  "with posterior means and equal-tailed 95\\% intervals. Positive differences favor independent estimation. ",
  "Deterministic index pairing defines descriptive contrasts between separately fitted models. ",
  "The two asymmetric-tail intervals favor joint estimation; the other fourteen include zero."),
  "tab:joint-qdesn-pure-desn-v2-contrasts")), "contrast_table.tex")

lines <- table_start("@{}lrrrr@{}", paste0("Model & \\shortstack{Fit grid\\\\crossings (\\%)} & ",
  "\\shortstack{Forecast grid\\\\crossings (\\%)} & \\shortstack{Posterior-draw\\\\crossings (\\%)} & ",
  "\\shortstack{Mean and maximum\\\\adjustment}"), "!htbp")
for (ii in seq_len(nrow(crossings))) {
  x <- crossings[ii, ]
  lines <- c(lines, sprintf("%s & %.2f & %.2f & %.2f & %.4f / %.4f \\\\",
    model_label[[x$model_id]], x$fit_raw_percent, x$forecast_raw_percent,
    x$posterior_forecast_raw_percent_equal_scenario, x$mean_abs_adjustment, x$max_abs_adjustment))
}
write_tex(c(lines, table_end(paste0("Raw adjacent-level crossing percentages and monotone adjustments. ",
  "The first two columns concern posterior-mean grids; the third gives equal weight to the eight setting-specific crossing rates computed from posterior draws. ",
  "Each model has 24,000 fitting and 47,520 forecast comparisons. AL cells use 3,750 draws; exAL cells use 7,500 for Laplace and 3,750 otherwise. ",
  "Adjustment magnitudes are on the response scale. Every projected grid has zero crossings."),
  "tab:joint-qdesn-pure-desn-v2-crossings")), "crossing_table.tex")

oracle <- mcmc
oracle$fit_oracle_mae <- fit_mcmc$fit_oracle_mae
oracle$fit_oracle_rmse <- fit_mcmc$fit_oracle_rmse
balanced_table(oracle, "oracle_recovery_table.tex", "tab:joint-qdesn-pure-desn-v2-oracle",
  paste0("Recovery of known conditional quantile paths by projected posterior-mean grids. ",
    "MAE and RMSE are oracle-path diagnostics, separate from scores against observations. ",
    "Fitting entries are point diagnostics, without posterior intervals."),
  c("fit_oracle_mae", "fit_oracle_rmse", "canonical_origin_marginal_oracle_quantile_mae",
    "canonical_origin_marginal_oracle_quantile_rmse"),
  "Simulation setting & Model & Fit MAE & Fit RMSE & Forecast MAE & Forecast RMSE")
balanced_table(mcmc, "secondary_score_table.tex", "tab:joint-qdesn-pure-desn-v2-secondary",
  paste0("Secondary finite-grid \\(\\aCRPS\\) against realized observations. ",
    "The posterior mean averages scores at the averaged recursive design; the mean-grid score evaluates the projected posterior-mean quantile grid. ",
    "These are distinct from the DGP-integrated primary criterion."),
  c("posterior_realized_acrps_mean", "canonical_realized_acrps"),
  "Simulation setting & Model & \\shortstack{Posterior mean\\\\realized score} & \\shortstack{Mean-grid\\\\realized score}")

lines <- table_start("@{}>{\\raggedright\\arraybackslash}p{0.24\\textwidth}lrr@{}",
  "Simulation setting & Model & Averaged design & Recursive trajectories")
for (si in seq_along(scenarios)) {
  sid <- scenarios[[si]]
  x <- mcmc[mcmc$scenario_id == sid, ]
  x <- x[match(models, x$model_id), ]
  for (mi in seq_along(models)) {
    values <- c(fmt_interval(x$posterior_score_mean[[mi]], x$posterior_score_q025[[mi]], x$posterior_score_q975[[mi]]),
      fmt_interval(x$path_posterior_score_mean[[mi]], x$path_posterior_score_q025[[mi]], x$path_posterior_score_q975[[mi]]))
    lines <- c(lines, paste0(paste(c(if (mi == 1L) scenario_label[[sid]] else "",
      model_label[[models[[mi]]]], values), collapse = " & "), " \\\\"))
  }
  if (si < length(scenarios)) lines <- c(lines, "\\addlinespace[2pt]")
}
write_tex(c(lines, table_end(paste0("Sensitivity to integration over recursively generated future features. ",
  "Entries are posterior means and equal-tailed 95\\% intervals. Averaged-design entries condition on each model's mean future feature matrix; ",
  "trajectory entries retain each draw's recursive states. The comparison concerns retained uncertainty, not interval calibration."),
  "tab:joint-qdesn-pure-desn-v2-recursive-policy")), "recursive_policy_table.tex")

lines <- table_start("@{}>{\\raggedright\\arraybackslash}p{0.23\\textwidth}>{\\raggedright\\arraybackslash}p{0.68\\textwidth}@{}",
  "Item & Specification", "!htbp", "small")
lines <- c(lines,
  "Feature design & One reservoir specification per setting, selected using separate source realizations and shared across all four regressions. The readout contains an intercept and all reservoir-layer states; response lags enter the reservoir only. \\\\",
  "Quantile levels & 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, and 0.95; trapezoidal weights sum to 0.90. \\\\",
  "Forecast design & 33 origins and 30 horizons, giving 990 rows per setting. Observed histories update states between origins; future response lags are generated recursively within each origin. \\\\",
  "Posterior simulation & Five chains per model cell. Scores use 3,750 pooled AL draws and 3,750 exAL draws, except 7,500 exAL draws for Laplace. All exAL chains use the exact scale-collapsed asymmetry transition. \\\\",
  "Initialization & Gaussian, AL, exAL, and joint fits supply starting values in the stated sequence. Prior hyperparameters define each target and are common across its five chains. \\\\",
  "Uncertainty & Primary intervals condition on each model's averaged recursive design; trajectory-inclusive intervals are reported separately. VB intervals additionally hold intercepts fixed. \\\\",
  "Computation & All 64 method--model comparisons are finite, and all 32 MCMC comparisons satisfy the score-functional criteria. These checks do not establish complete scalar-parameter mixing. \\\\")
write_tex(c(lines, table_end("Design and computation for the reservoir-only multi-quantile comparison.",
  "tab:joint-qdesn-pure-desn-v2-protocol")), "protocol.tex")

status <- system2(Rscript, shQuote("scripts/build_joint_qdesn_laplace_article_figures_v2.R"))
expect(status == 0L, "Versioned vector-figure generation failed.")
outputs <- c(list.files("tables", pattern = paste0("^", prefix, ".*\\.(csv|tex)$"), full.names = TRUE),
  list.files("figures/joint_qdesn_simulation", pattern = paste0("^", prefix, ".*\\.pdf$"), full.names = TRUE))
outputs <- sort(setdiff(outputs, path("article_asset_manifest.csv")))
expect(!anyDuplicated(outputs) && length(outputs) > 20L, "Incomplete article asset surface.")
manifest <- data.frame(relative_path = outputs,
  size_bytes = unname(file.info(outputs)$size), sha256 = vapply(outputs, sha, character(1L)),
  source_lane_head = "6ff88298d7f10814071a9fec4a9a6d32804cdfb1",
  role = ifelse(grepl("\\.pdf$", outputs), "figure",
    ifelse(grepl("\\.tex$", outputs), "article_wrapper_or_table", "compact_scientific_summary")),
  metric = ifelse(grepl("forecast_dgp_acrps\\.pdf$", outputs), "posterior_score_mean",
    ifelse(grepl("fit_oracle_rmse\\.pdf$", outputs), "fit_oracle_rmse", "")),
  interval_scope = ifelse(grepl("forecast_dgp_acrps\\.pdf$", outputs),
    "posterior_score_q025_q975_conditional_on_mean_design",
    ifelse(grepl("fit_oracle_rmse\\.pdf$", outputs), "point_diagnostic_no_intervals", "")))
write.csv(manifest, path("article_asset_manifest.csv"), row.names = FALSE, na = "")
# The historical PRO receipt remains unchanged in Git. The publication
# companion retains its nine unaffected displays and replaces its four JOINT
# displays, rather than deploying the obsolete JOINT receipt and its assets.
previous <- jsonlite::fromJSON("tables/qdesn_pro_review_presentation_manifest.json", simplifyVector = FALSE)
retained_outputs <- Filter(function(entry) !grepl("joint_qdesn", entry$file), previous$outputs)
retained_sources <- previous$sources[!grepl("joint_qdesn", names(previous$sources))]
for (entry in retained_outputs) expect(identical(sha(entry$file), entry$sha256),
  paste("Unrelated presentation output changed:", entry$file))
for (relative in names(retained_sources)) expect(identical(sha(relative), retained_sources[[relative]]),
  paste("Unrelated presentation source changed:", relative))
new_figures <- manifest$relative_path[manifest$role == "figure"]
new_wrappers <- paste0("tables/", prefix, c("forecast_figure.tex", "fit_figure.tex"))
joint_outputs <- lapply(c(new_figures, new_wrappers), function(p) list(file = p, sha256 = sha(p)))
joint_sources <- setNames(lapply(c(path("forecast_score_summary.csv"), path("fit_oracle_diagnostics.csv")), sha),
  c(path("forecast_score_summary.csv"), path("fit_oracle_diagnostics.csv")))
publication <- list(schema = "qdesn-article-presentation-v2",
  purpose = "Versioned JOINT replacement; independent and GloFAS displays unchanged",
  historical_receipt_sha256 = sha("tables/qdesn_pro_review_presentation_manifest.json"),
  preserved_generator = previous$source_script, preserved_generator_sha256 = previous$script_sha256,
  joint_generator = "scripts/build_joint_qdesn_laplace_article_figures_v2.R",
  joint_generator_sha256 = sha("scripts/build_joint_qdesn_laplace_article_figures_v2.R"),
  shared_style_sha256 = sha("scripts/qdesn_evaluation_figure_style.R"),
  simulation_minimum_native_ordinary_label_pt = 10.4,
  sources = c(retained_sources, joint_sources), outputs = c(retained_outputs, joint_outputs))
expect(length(publication$outputs) == 13L, "Presentation companion lost an unaffected display.")
jsonlite::write_json(publication, "tables/qdesn_article_presentation_manifest_v2.json",
  pretty = TRUE, auto_unbox = TRUE, digits = 17)
cat(sprintf("JOINT_PURE_DESN_ARTICLE_V2_BUILD=PASS rows=64 mcmc=32 assets=%d strict_pass=32 review=0\n", nrow(manifest)))
