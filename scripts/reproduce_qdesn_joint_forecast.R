#!/usr/bin/env Rscript
# Presentation-only example; no fitting, draw processing, or score computation.
options(stringsAsFactors = FALSE, digits = 17)
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), ".."))
input <- file.path(root, "tables/joint_qdesn_pure_desn_v1_forecast_score_summary.csv")
stopifnot(identical(unname(tools::sha256sum(input)[[1L]]),
  "a0be319e4486d5be122ad6dfe5ee9e2a470cd09ce5dfafc5d0af3925aecf2d1c"))
source(file.path(root, "scripts/qdesn_evaluation_figure_style.R"))
score <- read.csv(input, check.names = FALSE)
mcmc <- score[score$inference_method == "mcmc", , drop = FALSE]
model_order <- c("joint_qdesn_rhs_mcmc", "qdesn_rhs_independent_mcmc",
  "joint_exqdesn_rhs_mcmc", "exqdesn_rhs_independent_mcmc")
stopifnot(nrow(mcmc) == 32L, all(table(mcmc$scenario_id) == 4L),
  all(table(mcmc$model_id) == 8L), all(mcmc$canonical_contract_crossing_pairs == 0L),
  all(is.finite(mcmc$posterior_score_mean)))
model_style <- setNames(qdesn_joint_model_order, model_order)
model_short <- setNames(unname(qdesn_joint_model_labels), model_order)
scenario_tex <- qdesn_scenario_labels
scenario_tex[["student_t_location_scale"]] <- "Student-\\(t\\) location--scale"
fields <- c("posterior_score_mean", "posterior_score_median", "posterior_score_q025",
  "posterior_score_q975", "canonical_origin_marginal_dgp_integrated_acrps")
lines <- c("\\begin{table}[p]", "\\centering", "\\scriptsize",
  "\\setlength{\\tabcolsep}{3.5pt}", "\\renewcommand{\\arraystretch}{1.04}",
  "\\resizebox{\\textwidth}{!}{%",
  "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.21\\textwidth}>{\\raggedright\\arraybackslash}p{0.22\\textwidth}rrrrr@{}}",
  "\\toprule", "Simulation setting & Model & Mean & Median & 2.5\\% & 97.5\\% & \\shortstack{Score at\\\\posterior-mean grid} \\\\",
  "\\midrule")
for (si in seq_along(qdesn_scenario_order)) {
  sid <- qdesn_scenario_order[[si]]
  block <- mcmc[mcmc$scenario_id == sid, , drop = FALSE]
  block <- block[match(model_order, block$model_id), , drop = FALSE]
  stopifnot(nrow(block) == 4L, !anyNA(block$model_id))
  for (mi in seq_along(model_order)) {
    values <- vapply(fields, function(field) sprintf("%.4f", block[[field]][[mi]]), character(1))
    if (mi == which.min(block$posterior_score_mean))
      values[[1L]] <- paste0("\\textbf{", values[[1L]], "}")
    lines <- c(lines, paste0(paste(c(if (mi == 1L) scenario_tex[[sid]] else "",
      model_short[[model_order[[mi]]]], values), collapse = " & "), " \\\\"))
  }
  if (si < length(qdesn_scenario_order)) lines <- c(lines, "\\addlinespace[2pt]")
}
caption <- paste0("DGP-integrated finite-grid \\(\\aCRPS\\) in the pure-DESN multi-quantile study. ",
  "The posterior means, medians, and equal-tailed 95\\% limits condition on each model's averaged recursively generated forecast design. ",
  "The final column evaluates the posterior-mean quantile grid after the specified monotone projection; it is a different summary from the posterior mean of the score. ",
  "Boldface marks the lowest posterior mean within each setting. All winner/runner-up marginal intervals overlap.")
lines <- c(lines, "\\bottomrule", "\\end{tabular}", "}%", paste0("\\caption{", caption, "}"),
  "\\label{tab:joint-qdesn-pure-desn-v1-score}", "\\end{table}")
writeLines(lines, file.path(root, "tables/joint_qdesn_pure_desn_v1_score_table.tex"), useBytes = TRUE)
plot_data <- data.frame(scenario_id = mcmc$scenario_id,
  source_model_id = unname(model_style[mcmc$model_id]), likelihood_family = mcmc$likelihood_family,
  mean = mcmc$posterior_score_mean, lo = mcmc$posterior_score_q025, hi = mcmc$posterior_score_q975,
  crossing = sprintf("%.2f%%", 100 * mcmc$canonical_raw_crossing_pairs / (33L * 30L * 6L)))
plot <- qdesn_joint_interval_plot(plot_data, "DGP-integrated aCRPS")
for (scenario in levels(plot$data$scenario_id)) {
  rows <- which(plot$data$scenario_id == scenario)
  span <- max(plot$data$hi[rows]) - min(plot$data$lo[rows])
  if (!is.finite(span) || span <= 0) span <- max(abs(plot$data$hi[rows]), 1) * 0.1
  plot$data$label_x[rows] <- max(plot$data$hi[rows]) + 0.50 * span
}
xscale <- plot$scales$get_scales("x")
xscale$labels <- function(x) {
  digits <- if (length(x) > 1L && diff(range(x, na.rm = TRUE)) < 0.04) 3L else 2L
  formatC(x, format = "f", digits = digits)
}
out <- file.path(root, "figures/joint_qdesn_simulation")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
qdesn_save_vector_pdf(file.path(out, "joint_qdesn_pure_desn_v1_forecast_dgp_acrps.pdf"), plot, 7.0, 8.1)
cat("JOINT_FORECAST_PRESENTATION_REPRODUCED=PASS mcmc_cells=32\n")
