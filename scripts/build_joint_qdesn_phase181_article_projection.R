#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
repo_root <- normalizePath(if (length(args)) args[[1L]] else ".", mustWork = TRUE)
table_dir <- file.path(repo_root, "tables")

read_asset <- function(name) {
  path <- file.path(table_dir, name)
  if (!file.exists(path)) stop("Missing article asset: ", path)
  read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

assert_columns <- function(x, required, label) {
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(label, " is missing columns: ", paste(missing, collapse = ", "))
  }
}

format_interval <- function(mean, lower, upper) {
  sprintf("%.4f [%.4f, %.4f]", mean, lower, upper)
}

scenario_labels <- c(
  asymmetric_laplace_tail = "Asymmetric-Laplace tail",
  gaussian_mixture_bridge = "Gaussian-mixture innovations",
  laplace_bridge = "Laplace innovations",
  nonlinear_reservoir_friendly = "Nonlinear reservoir dynamics",
  normal_bridge = "Gaussian innovations",
  persistent_heavy_tail = "Persistent heavy tails",
  regime_shift = "Regime shift",
  student_t_location_scale = "Student-\\(t\\) location--scale"
)

model_order <- c(
  "joint_qdesn_rhs_vb",
  "qdesn_rhs_independent_vb",
  "joint_exqdesn_rhs_vb",
  "exqdesn_rhs_independent_vb"
)

model_labels <- c(
  joint_qdesn_rhs_vb = "Joint Q--DESN \\(\\AL\\)--\\(\\RHS\\)",
  qdesn_rhs_independent_vb = "Independent Q--DESN \\(\\AL\\)--\\(\\RHS\\)",
  joint_exqdesn_rhs_vb = "Joint exQDESN \\(\\exAL\\)--\\(\\RHS\\)",
  exqdesn_rhs_independent_vb = "Independent exQDESN \\(\\exAL\\)--\\(\\RHS\\)"
)

summary <- read_asset("joint_qdesn_phase181_article_scenario_model_summary.csv")
assert_columns(
  summary,
  c(
    "scenario_id", "source_model_id", "posterior_score_mean",
    "posterior_score_q025", "posterior_score_q975", "numerical_winner",
    "canonical_raw_crossing_pairs", "canonical_contract_crossing_pairs",
    "raw_crossing_rate"
  ),
  "Scenario-model summary"
)

if (nrow(summary) != 32L) stop("Expected exactly 32 scenario-model rows.")
if (!setequal(unique(summary$scenario_id), names(scenario_labels))) {
  stop("Unexpected scenario set in the scenario-model summary.")
}
if (!all(table(summary$scenario_id) == 4L)) {
  stop("Each scenario must contain exactly four model rows.")
}
if (!setequal(unique(summary$source_model_id), model_order)) {
  stop("Unexpected model set in the scenario-model summary.")
}
score_fields <- c("posterior_score_mean", "posterior_score_q025", "posterior_score_q975")
if (!all(vapply(summary[score_fields], function(x) all(is.finite(x)), logical(1)))) {
  stop("All posterior score summaries must be finite.")
}
if (any(summary$posterior_score_q025 > summary$posterior_score_q975)) {
  stop("Posterior score intervals are not ordered.")
}
if (sum(summary$numerical_winner) != 8L ||
    !all(tapply(summary$numerical_winner, summary$scenario_id, sum) == 1L)) {
  stop("Expected one numerical winner in each of eight scenarios.")
}
if (any(summary$canonical_contract_crossing_pairs != 0L)) {
  stop("Every reported quantile grid must be noncrossing after rearrangement.")
}

main_lines <- c(
  "\\begin{table}[!htbp]",
  "\\centering",
  "\\scriptsize",
  "\\resizebox{\\textwidth}{!}{%",
  "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.23\\textwidth}rrrr@{}}",
  "\\toprule",
  paste0(
    "Simulation setting & \\shortstack{Joint Q--DESN\\\\\\(\\AL\\)--\\(\\RHS\\)} & ",
    "\\shortstack{Independent Q--DESN\\\\\\(\\AL\\)--\\(\\RHS\\)} & ",
    "\\shortstack{Joint exQDESN\\\\\\(\\exAL\\)--\\(\\RHS\\)} & ",
    "\\shortstack{Independent exQDESN\\\\\\(\\exAL\\)--\\(\\RHS\\)} \\\\"
  ),
  "\\midrule"
)

for (scenario_id in names(scenario_labels)) {
  block <- summary[summary$scenario_id == scenario_id, , drop = FALSE]
  block <- block[match(model_order, block$source_model_id), , drop = FALSE]
  values <- mapply(
    format_interval,
    block$posterior_score_mean,
    block$posterior_score_q025,
    block$posterior_score_q975,
    USE.NAMES = FALSE
  )
  values[block$numerical_winner] <- paste0("\\textbf{", values[block$numerical_winner], "}")
  main_lines <- c(
    main_lines,
    paste(c(scenario_labels[[scenario_id]], values), collapse = " & ") |> paste0(" \\\\")
  )
}

main_lines <- c(
  main_lines,
  "\\bottomrule",
  "\\end{tabular}",
  "}%",
  paste0(
    "\\caption{Posterior data-generating-process-integrated finite-grid ",
    "quantile scores for the ",
    "joint multi-quantile simulation. Entries are posterior means with ",
    "equal-tailed 95\\% credible intervals. The score averages the seven-level ",
    "integrated check loss over the known conditional response distribution ",
    "and the held-out forecast design. Lower values are better; boldface ",
    "identifies the numerical minimum, based on the unrounded posterior means, ",
    "within each simulation setting. Because ",
    "every joint-minus-independent posterior contrast interval under the ",
    "pre-specified pairing includes zero, the bolded comparisons are ",
    "descriptive.}"
  ),
  "\\label{tab:joint-qdesn-dgp-integrated-score}",
  "\\end{table}"
)
writeLines(
  main_lines,
  file.path(table_dir, "joint_qdesn_phase181_dgp_integrated_score_table.tex"),
  useBytes = TRUE
)

contrasts <- read_asset("joint_qdesn_phase181_joint_independent_contrast_summary.csv")
assert_columns(
  contrasts,
  c(
    "base_scenario_id", "variant_id", "n_draws", "score_delta_mean",
    "score_delta_q025", "score_delta_q975"
  ),
  "Joint-independent contrast summary"
)
if (nrow(contrasts) != 16L ||
    !all(table(contrasts$base_scenario_id) == 2L) ||
    !setequal(unique(contrasts$variant_id), c("AL", "exAL"))) {
  stop("Expected 16 contrasts: AL and exAL for each of eight scenarios.")
}
if (!all(is.finite(unlist(contrasts[c(
  "score_delta_mean", "score_delta_q025", "score_delta_q975"
)])))) {
  stop("All paired contrast summaries must be finite.")
}
if (any(contrasts$score_delta_q025 > 0 | contrasts$score_delta_q975 < 0)) {
  stop("Every paired joint-minus-independent interval must include zero.")
}

contrast_lines <- c(
  "\\begin{table}[!htbp]",
  "\\centering",
  "\\small",
  "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.39\\textwidth}rr@{}}",
  "\\toprule",
  "Simulation setting & \\(\\AL\\) & \\(\\exAL\\) \\\\",
  "\\midrule"
)
for (scenario_id in names(scenario_labels)) {
  block <- contrasts[contrasts$base_scenario_id == scenario_id, , drop = FALSE]
  block <- block[match(c("AL", "exAL"), block$variant_id), , drop = FALSE]
  values <- mapply(
    format_interval,
    block$score_delta_mean,
    block$score_delta_q025,
    block$score_delta_q975,
    USE.NAMES = FALSE
  )
  contrast_lines <- c(
    contrast_lines,
    paste(c(scenario_labels[[scenario_id]], values), collapse = " & ") |> paste0(" \\\\")
  )
}
contrast_lines <- c(
  contrast_lines,
  "\\bottomrule",
  "\\end{tabular}",
  paste0(
    "\\caption{Joint-minus-independent posterior contrasts in the ",
    "data-generating-process-integrated finite-grid quantile score. Entries ",
    "are means with equal-tailed 95\\% intervals from 8,000 score draws under ",
    "the pre-specified within-chain pairing; negative values favor joint ",
    "estimation. The intervals are conditional on this pairing, and every ",
    "interval includes zero.}"
  ),
  "\\label{tab:supp-joint-qdesn-dgp-score-contrasts}",
  "\\end{table}"
)
writeLines(
  contrast_lines,
  file.path(table_dir, "joint_qdesn_phase181_joint_independent_contrast_table.tex"),
  useBytes = TRUE
)

crossings <- read_asset("joint_qdesn_phase181_crossing_provenance.csv")
assert_columns(
  crossings,
  c("case_id", "window", "raw_crossing_pairs", "contract_crossing_pairs"),
  "Crossing summary"
)
forecast_crossings <- crossings[crossings$window == "forecast", , drop = FALSE]
mapping <- unique(summary[c("case_id", "source_model_id")])
forecast_crossings <- merge(
  forecast_crossings, mapping, by = "case_id", all.x = TRUE, sort = FALSE
)
if (anyNA(forecast_crossings$source_model_id)) {
  stop("Could not map every forecast crossing row to a model.")
}
crossing_summary <- aggregate(
  cbind(raw_crossing_pairs, contract_crossing_pairs) ~ source_model_id,
  data = forecast_crossings,
  FUN = sum
)
crossing_summary <- crossing_summary[
  match(model_order, crossing_summary$source_model_id), ,
  drop = FALSE
]
draw_crossing_rates <- aggregate(
  raw_crossing_rate ~ source_model_id,
  data = summary,
  FUN = mean
)
crossing_summary$mean_draw_crossing_rate <- draw_crossing_rates$raw_crossing_rate[
  match(crossing_summary$source_model_id, draw_crossing_rates$source_model_id)
]
if (!identical(as.integer(crossing_summary$raw_crossing_pairs), c(1L, 25L, 0L, 0L))) {
  stop("Unexpected canonical raw forecast crossing totals.")
}
if (any(crossing_summary$contract_crossing_pairs != 0L) ||
    any(!is.finite(crossing_summary$mean_draw_crossing_rate))) {
  stop("Crossings remain after monotone rearrangement.")
}

crossing_lines <- c(
  "\\begin{table}[!htbp]",
  "\\centering",
  "\\small",
  "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.43\\textwidth}rrr@{}}",
  "\\toprule",
  paste0(
    "Model & \\shortstack{Before\\\\rearrangement} & ",
    "\\shortstack{After\\\\rearrangement} & ",
    "\\shortstack{Mean draw-level\\\\crossing rate (\\%)} \\\\"
  ),
  "\\midrule"
)
for (i in seq_len(nrow(crossing_summary))) {
  crossing_lines <- c(
    crossing_lines,
    sprintf(
      "%s & %d & %d & %.2f \\\\",
      model_labels[[crossing_summary$source_model_id[[i]]]],
      crossing_summary$raw_crossing_pairs[[i]],
      crossing_summary$contract_crossing_pairs[[i]],
      100 * crossing_summary$mean_draw_crossing_rate[[i]]
    )
  )
}
crossing_lines <- c(
  crossing_lines,
  "\\bottomrule",
  "\\end{tabular}",
  paste0(
    "\\caption{Adjacent-level crossings in the posterior-mean forecast ",
    "quantile grids, summed over the eight simulation settings. Counts before ",
    "rearrangement describe departures from monotonicity in the fitted ",
    "quantiles; monotone rearrangement produces ordered grids in all 32 ",
    "scenario--model comparisons. Within a setting, the draw-level rate is ",
    "the number of adjacent-level crossings divided by the six adjacent ",
    "quantile pairs across 8,000 draws and 990 forecast rows; the final column ",
    "averages this rate over the eight settings for each model.}"
  ),
  "\\label{tab:supp-joint-qdesn-crossings}",
  "\\end{table}"
)
writeLines(
  crossing_lines,
  file.path(table_dir, "joint_qdesn_phase181_crossing_summary.tex"),
  useBytes = TRUE
)

diagnostics <- read_asset("joint_qdesn_phase181_supplemental_diagnostics.csv")
assert_columns(
  diagnostics,
  c(
    "scenario_id", "source_model_id", "oracle_quantile_mae",
    "oracle_quantile_rmse"
  ),
  "Supplemental diagnostics"
)
if (nrow(diagnostics) != 32L ||
    !all(is.finite(diagnostics$oracle_quantile_mae)) ||
    !all(is.finite(diagnostics$oracle_quantile_rmse))) {
  stop("Expected 32 finite oracle-recovery rows.")
}

recovery_lines <- c(
  "\\begin{table}[!htbp]",
  "\\centering",
  "\\scriptsize",
  "\\resizebox{\\textwidth}{!}{%",
  "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.23\\textwidth}rrrr@{}}",
  "\\toprule",
  paste0(
    "Simulation setting & \\shortstack{Joint Q--DESN\\\\\\(\\AL\\)--\\(\\RHS\\)} & ",
    "\\shortstack{Independent Q--DESN\\\\\\(\\AL\\)--\\(\\RHS\\)} & ",
    "\\shortstack{Joint exQDESN\\\\\\(\\exAL\\)--\\(\\RHS\\)} & ",
    "\\shortstack{Independent exQDESN\\\\\\(\\exAL\\)--\\(\\RHS\\)} \\\\"
  ),
  "\\midrule"
)
for (scenario_id in names(scenario_labels)) {
  block <- diagnostics[diagnostics$scenario_id == scenario_id, , drop = FALSE]
  block <- block[match(model_order, block$source_model_id), , drop = FALSE]
  values <- sprintf(
    "%.3f (%.3f)",
    block$oracle_quantile_mae,
    block$oracle_quantile_rmse
  )
  recovery_lines <- c(
    recovery_lines,
    paste(c(scenario_labels[[scenario_id]], values), collapse = " & ") |>
      paste0(" \\\\")
  )
}
recovery_lines <- c(
  recovery_lines,
  "\\bottomrule",
  "\\end{tabular}",
  "}%",
  paste0(
    "\\caption{Forecast quantile-path recovery in the joint multi-quantile ",
    "simulation. Entries are mean absolute error with root-mean-square error ",
    "in parentheses for the monotonically rearranged posterior-mean forecast ",
    "quantile paths, computed relative to the known conditional quantiles. ",
    "These diagnostics complement the data-generating-process-integrated ",
    "score comparison in the ",
    "main article.}"
  ),
  "\\label{tab:supp-joint-qdesn-oracle-recovery}",
  "\\end{table}"
)
writeLines(
  recovery_lines,
  file.path(table_dir, "joint_qdesn_phase181_oracle_recovery_table.tex"),
  useBytes = TRUE
)

cat(
  "JOINT_QDESN_PHASE181_ARTICLE_BUILD=PASS",
  "rows=32 contrasts=16 models=4 recovery_rows=32\n"
)
