#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, digits = 17)

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(flag, default) {
  at <- match(flag, args)
  if (is.na(at) || at == length(args)) default else args[[at + 1L]]
}

runtime_root <- normalizePath(arg_value(
  "--runtime-root",
  paste0(
    "/data/jaguir26/local/src/",
    "Article-Q-DESN---Version-2__wt__joint_corrected_article_comparison_",
    "muscat_11core_20260909/application/cache/",
    "joint_qdesn_corrected_article_comparison_muscat_11core_20260909"
  )
), mustWork = TRUE)
packet_root <- file.path(runtime_root, "score_packet")
table_dir <- file.path(repo_root, "tables")
figure_dir <- file.path(repo_root, "figures", "joint_qdesn_simulation")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1"
)
if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("The ggplot2 package is required.", call. = FALSE)
}

sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
read_csv <- function(path) read.csv(
  path, stringsAsFactors = FALSE, check.names = FALSE
)
write_csv <- function(x, path) write.csv(x, path, row.names = FALSE, na = "")
expect <- function(value, message) {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}

expected_contract_sha <-
  "d2d118f1b1b1e6feedcd4d552c20ad6d95902d1be833f5af257d7b61f0289ad1"
expected_transfer_sha <-
  "e4b98fe89a8a0c2323f8205c1abef608ff733bc5ec323ea6372198caca02191d"
source_execution_commit <-
  "b9af9ef4a7da8b507827dce9cd0d6d0b2a53ab24"
source_lane_head <-
  "ca1cffa155cc5a3491f2492eeef83a31d30044bf"

expected_source_sha <- c(
  posterior_dgp_integrated_acrps_summary.csv =
    "2470ef53eed99899fea41b1f97cde18687b11c9d9b6455cda8dff8ea29b8adf8",
  scenario_winner_summary.csv =
    "f98ba9b18f4985afc085d68455e60a7e0bf19fd27bc86022591febd3518b98b2",
  joint_independent_contrast_summary.csv =
    "49cf419bdf0f4c89280f8b1d6a632c261d9c8b3eee70244376f6589f85a2fc34",
  forecast_metric_summary.csv =
    "8258d729ede6f577c0abbf3cabeb040d22cec0aafb72606aaa30c32322f8cdd6",
  oracle_recovery_summary.csv =
    "c160c0e12183ca3e1404e5efad8547dcb0599fe6b562b301a720173398b5d1aa",
  crossing_and_adjustment_summary.csv =
    "4f1efb0a95f23df485643ff9450272488eb48559c1f85fdd5dfd7c25e6be81e5",
  phase181_reconciliation.csv =
    "02deccb5d29df490b1031c52c9f3f1ffc817a37ffca4a14aaf3713c93d62274c"
)

contract_path <- file.path(packet_root, "score_contract.csv")
transfer_path <- file.path(packet_root, "transfer_inventory.csv")
expect(file.exists(contract_path) &&
         identical(sha256(contract_path), expected_contract_sha),
       "The frozen v4 score contract failed its SHA-256 gate.")
expect(file.exists(transfer_path) &&
         identical(sha256(transfer_path), expected_transfer_sha),
       "The frozen transfer inventory failed its SHA-256 gate.")

packet_manifest <- read_csv(file.path(packet_root, "artifact_manifest.csv"))
expect(nrow(packet_manifest) == 26L,
       "The frozen score-packet manifest does not contain 26 artifacts.")
for (ii in seq_len(nrow(packet_manifest))) {
  path <- file.path(packet_root, packet_manifest$relative_path[[ii]])
  expect(file.exists(path), paste("Missing frozen packet artifact:", path))
  expect(file.info(path)$size == packet_manifest$size_bytes[[ii]],
         paste("Frozen packet size mismatch:", path))
  expect(identical(sha256(path), packet_manifest$sha256[[ii]]),
         paste("Frozen packet SHA-256 mismatch:", path))
}

prefix <- "joint_qdesn_corrected_v4_"
staged_paths <- setNames(
  file.path(table_dir, paste0(prefix, names(expected_source_sha))),
  names(expected_source_sha)
)
for (name in names(expected_source_sha)) {
  source_path <- file.path(packet_root, name)
  expect(file.exists(source_path) &&
           identical(sha256(source_path), expected_source_sha[[name]]),
         paste("Frozen candidate input changed:", name))
  ok <- file.copy(source_path, staged_paths[[name]], overwrite = TRUE)
  expect(ok && identical(sha256(staged_paths[[name]]), expected_source_sha[[name]]),
         paste("Could not stage article-safe candidate:", name))
}

score <- read_csv(staged_paths[["posterior_dgp_integrated_acrps_summary.csv"]])
winners <- read_csv(staged_paths[["scenario_winner_summary.csv"]])
contrasts <- read_csv(staged_paths[["joint_independent_contrast_summary.csv"]])
forecast <- read_csv(staged_paths[["forecast_metric_summary.csv"]])
oracle <- read_csv(staged_paths[["oracle_recovery_summary.csv"]])
crossings <- read_csv(staged_paths[["crossing_and_adjustment_summary.csv"]])
reconciliation <- read_csv(staged_paths[["phase181_reconciliation.csv"]])

scenario_order <- c(
  "asymmetric_laplace_tail", "gaussian_mixture_bridge", "laplace_bridge",
  "nonlinear_reservoir_friendly", "normal_bridge", "persistent_heavy_tail",
  "regime_shift", "student_t_location_scale"
)
scenario_labels <- c(
  asymmetric_laplace_tail = "Asymmetric-Laplace tail",
  gaussian_mixture_bridge = "Gaussian-mixture innovations",
  laplace_bridge = "Laplace innovations",
  nonlinear_reservoir_friendly = "Nonlinear reservoir dynamics",
  normal_bridge = "Gaussian innovations",
  persistent_heavy_tail = "Persistent heavy tails",
  regime_shift = "Regime shift",
  student_t_location_scale = "Student-t location-scale"
)
scenario_tex <- c(
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
  "joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb",
  "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"
)
model_short <- c(
  joint_qdesn_rhs_vb = "Joint AL",
  qdesn_rhs_independent_vb = "Independent AL",
  joint_exqdesn_rhs_vb = "Joint exAL",
  exqdesn_rhs_independent_vb = "Independent exAL"
)
model_tex <- c(
  joint_qdesn_rhs_vb = "Joint Q--DESN \\(\\AL\\)--\\(\\RHS\\)",
  qdesn_rhs_independent_vb = "Independent Q--DESN \\(\\AL\\)--\\(\\RHS\\)",
  joint_exqdesn_rhs_vb = "Joint exQDESN \\(\\exAL\\)--\\(\\RHS\\)",
  exqdesn_rhs_independent_vb = "Independent exQDESN \\(\\exAL\\)--\\(\\RHS\\)"
)

expect(nrow(score) == 32L && nrow(winners) == 8L &&
         nrow(contrasts) == 16L && nrow(forecast) == 32L &&
         nrow(oracle) == 64L && nrow(crossings) == 64L &&
         nrow(reconciliation) == 32L,
       "The seven article-safe inputs have an unexpected row count.")
expect(setequal(score$scenario_id, scenario_order) &&
         setequal(score$source_model_id, model_order) &&
         all(table(score$scenario_id) == 4L),
       "The primary score is not balanced over eight scenarios and four models.")
expect(all(is.finite(score$posterior_score_mean)) &&
         all(score$posterior_score_q025 <= score$posterior_score_median) &&
         all(score$posterior_score_median <= score$posterior_score_q975) &&
         all(score$canonical_contract_crossing_pairs == 0L),
       "The primary score intervals or reporting contract are invalid.")

mean_winners <- do.call(rbind, lapply(split(score, score$scenario_id),
  function(x) x[which.min(x$posterior_score_mean), , drop = FALSE]))
action_winners <- do.call(rbind, lapply(split(score, score$scenario_id),
  function(x) x[which.min(x$canonical_action_dgp_integrated_acrps), , drop = FALSE]))
expect(sum(mean_winners$source_model_id == "exqdesn_rhs_independent_vb") == 7L &&
         sum(mean_winners$source_model_id == "joint_exqdesn_rhs_vb") == 1L &&
         mean_winners$source_model_id[mean_winners$scenario_id == "laplace_bridge"] ==
           "joint_exqdesn_rhs_vb",
       "The posterior-mean winner pattern changed.")
expect(all(action_winners$source_model_id == "exqdesn_rhs_independent_vb"),
       "The canonical action no longer selects independent exQDESN in all settings.")
expect(all(winners$intervals_overlap_runner_up),
       "A winner/runner-up marginal interval no longer overlaps.")
expect(sum(contrasts$score_delta_q025 > 0) == 4L &&
         sum(contrasts$score_delta_q025 <= 0 & contrasts$score_delta_q975 >= 0) == 12L &&
         all(contrasts$score_delta_q975 >= 0),
       "The joint-minus-independent contrast interpretation changed.")
expect(sum(score$score_functional_status == "pass") == 22L &&
         sum(score$score_functional_status == "review") == 10L &&
         sum(score$coherence_status == "pass") == 8L &&
         sum(score$coherence_status == "review") == 24L,
       "The score or coherence diagnostic counts changed.")
expect(all(reconciliation$comparability_label == "descriptively_comparable") &&
         all(reconciliation$score_contract_version ==
               "joint_qdesn_corrected_article_score_packet_v4"),
       "The Phase181 reconciliation no longer preserves the v4 replacement boundary.")

forecast_cross <- aggregate(
  cbind(raw_crossing_pairs, contract_crossing_pairs) ~ source_model_id,
  crossings[crossings$window == "forecast", , drop = FALSE], sum
)
expected_forecast_cross <- c(
  joint_qdesn_rhs_vb = 1197L,
  qdesn_rhs_independent_vb = 3522L,
  joint_exqdesn_rhs_vb = 0L,
  exqdesn_rhs_independent_vb = 269L
)
observed_forecast_cross <- forecast_cross$raw_crossing_pairs[
  match(names(expected_forecast_cross), forecast_cross$source_model_id)
]
expect(identical(as.integer(observed_forecast_cross),
                 unname(expected_forecast_cross)) &&
         all(forecast_cross$contract_crossing_pairs == 0L),
       "The canonical forecast crossing totals changed.")

fmt_interval <- function(center, lo, hi) {
  sprintf("%.4f [%.4f, %.4f]", center, lo, hi)
}
fmt_pair <- function(x, y) sprintf("%.4f (%.4f)", x, y)

score_table <- c(
  "\\begin{table}[p]", "\\centering", "\\scriptsize",
  "\\setlength{\\tabcolsep}{3.7pt}",
  "\\renewcommand{\\arraystretch}{1.04}",
  "\\resizebox{\\textwidth}{!}{%",
  "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.20\\textwidth}>{\\raggedright\\arraybackslash}p{0.30\\textwidth}rrc@{}}",
  "\\toprule",
  paste0("Simulation setting & Model & Posterior mean & Median & ",
         "Equal-tailed 95\\% interval \\\\"),
  "\\midrule"
)
for (ss in seq_along(scenario_order)) {
  sid <- scenario_order[[ss]]
  block <- score[score$scenario_id == sid, , drop = FALSE]
  block <- block[match(model_order, block$source_model_id), , drop = FALSE]
  mean_min <- which.min(block$posterior_score_mean)
  for (jj in seq_len(nrow(block))) {
    setting <- if (jj == 1L) scenario_tex[[sid]] else ""
    mean_value <- sprintf("%.4f", block$posterior_score_mean[[jj]])
    if (jj == mean_min) mean_value <- paste0("\\textbf{", mean_value, "}")
    interval <- sprintf("[%.4f, %.4f]", block$posterior_score_q025[[jj]],
                        block$posterior_score_q975[[jj]])
    score_table <- c(score_table, paste0(
      setting, " & ", model_tex[[block$source_model_id[[jj]]]], " & ",
      mean_value, " & ", sprintf("%.4f", block$posterior_score_median[[jj]]),
      " & ", interval, " \\\\"
    ))
  }
  if (ss < length(scenario_order)) score_table <- c(score_table, "\\addlinespace[2pt]")
}
score_table <- c(
  score_table, "\\bottomrule", "\\end{tabular}", "}%",
  paste0("\\caption{Corrected posterior DGP-integrated \\(\\aCRPS\\) for the ",
    "joint multi-quantile study. Entries are posterior means, medians, and ",
    "equal-tailed 95\\% intervals. Boldface marks the lowest posterior mean ",
    "within each simulation setting. All winner/runner-up marginal intervals ",
    "overlap, so the rankings are descriptive. Crossing frequencies and the ",
    "sizes of the monotone adjustments are reported separately.}"),
  "\\label{tab:joint-qdesn-corrected-v4-score}", "\\end{table}"
)
writeLines(score_table, file.path(table_dir,
  "joint_qdesn_corrected_v4_score_table.tex"), useBytes = TRUE)

contrast_table <- c(
  "\\begin{table}[!htbp]", "\\centering", "\\small",
  "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.39\\textwidth}rr@{}}",
  "\\toprule", "Simulation setting & \\(\\AL\\) & \\(\\exAL\\) \\\\",
  "\\midrule"
)
for (sid in scenario_order) {
  block <- contrasts[contrasts$base_scenario_id == sid, , drop = FALSE]
  block <- block[match(c("AL", "exAL"), block$variant_id), , drop = FALSE]
  values <- mapply(fmt_interval, block$score_delta_mean,
                   block$score_delta_q025, block$score_delta_q975,
                   USE.NAMES = FALSE)
  values[block$score_delta_q025 > 0] <- paste0(
    "\\textbf{", values[block$score_delta_q025 > 0], "}"
  )
  contrast_table <- c(contrast_table, paste0(
    paste(c(scenario_tex[[sid]], values), collapse = " & "), " \\\\"
  ))
}
contrast_table <- c(
  contrast_table, "\\bottomrule", "\\end{tabular}",
  paste0("\\caption{Joint-minus-independent contrasts in posterior ",
    "DGP-integrated \\(\\aCRPS\\). Entries are posterior means with ",
    "equal-tailed 95\\% intervals under the pre-specified chain-balanced ",
    "pairing. Positive values favor independent estimation. Boldface marks ",
    "the four intervals lying entirely above zero; the other twelve include ",
    "zero, and none favors joint estimation.}"),
  "\\label{tab:supp-joint-qdesn-corrected-v4-contrasts}", "\\end{table}"
)
writeLines(contrast_table, file.path(table_dir,
  "joint_qdesn_corrected_v4_contrast_table.tex"), useBytes = TRUE)

summarize_crossings <- function(block) {
  data.frame(
    raw_crossing_pairs = sum(block$raw_crossing_pairs),
    raw_crossing_opportunities = sum(block$raw_crossing_opportunities),
    raw_crossing_rate = sum(block$raw_crossing_pairs) /
      sum(block$raw_crossing_opportunities),
    mean_abs_monotone_adjustment = stats::weighted.mean(
      block$mean_abs_monotone_adjustment, w = block$rows
    ),
    max_abs_monotone_adjustment = max(block$max_abs_monotone_adjustment),
    contract_crossing_pairs = sum(block$contract_crossing_pairs)
  )
}
cross_agg <- do.call(rbind, lapply(model_order, function(mid) {
  do.call(rbind, lapply(c("fit", "forecast"), function(win) {
    block <- crossings[
      crossings$source_model_id == mid & crossings$window == win,
      , drop = FALSE
    ]
    cbind(data.frame(source_model_id = mid, window = win),
          summarize_crossings(block))
  }))
}))
fmt_crossing_rate <- function(block) {
  sprintf(
    "%.2f\\%% (%s/%s)",
    100 * block$raw_crossing_rate,
    format(block$raw_crossing_pairs, big.mark = ",", scientific = FALSE),
    format(block$raw_crossing_opportunities, big.mark = ",", scientific = FALSE)
  )
}
fmt_adjustment <- function(block) {
  sprintf("%.4f/%.4f", block$mean_abs_monotone_adjustment,
          block$max_abs_monotone_adjustment)
}
cross_table <- c(
  "\\begin{table}[!htbp]", "\\centering", "\\scriptsize",
  "\\setlength{\\tabcolsep}{3.5pt}",
  "\\resizebox{\\textwidth}{!}{%",
  "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.31\\textwidth}rrrr@{}}",
  "\\toprule",
  paste0("Model & \\shortstack{Fit raw crossings\\\\rate (count/\\(N\\))} & ",
         "\\shortstack{Fit adjustment\\\\mean/max} & ",
         "\\shortstack{Forecast raw crossings\\\\rate (count/\\(N\\))} & ",
         "\\shortstack{Forecast adjustment\\\\mean/max} \\\\"),
  "\\midrule"
)
for (mid in model_order) {
  fit <- cross_agg[cross_agg$source_model_id == mid &
                     cross_agg$window == "fit", , drop = FALSE]
  fore <- cross_agg[cross_agg$source_model_id == mid &
                      cross_agg$window == "forecast", , drop = FALSE]
  cross_table <- c(cross_table, paste0(
    model_tex[[mid]], " & ", fmt_crossing_rate(fit), " & ",
    fmt_adjustment(fit), " & ", fmt_crossing_rate(fore), " & ",
    fmt_adjustment(fore), " \\\\"
  ))
}
cross_table <- c(
  cross_table, "\\bottomrule", "\\end{tabular}", "}%",
  paste0("\\caption{Frequency and magnitude of monotone correction for the ",
    "posterior-mean quantile grids, aggregated over eight simulation settings. ",
    "Crossing rates are the proportions of adjacent-level comparisons that ",
    "cross before rearrangement; counts and total opportunities \\(N\\) are ",
    "shown in parentheses. Adjustment entries give the mean and maximum absolute change ",
    "on the simulation response scale ",
    "induced by the pre-specified monotone rule. Thus the rates measure how ",
    "often crossings occur, whereas the adjustment summaries describe their ",
    "magnitude. All rearranged grids have zero crossings.}"),
  "\\label{tab:supp-joint-qdesn-corrected-v4-crossings}", "\\end{table}"
)
writeLines(cross_table, file.path(table_dir,
  "joint_qdesn_corrected_v4_crossing_table.tex"), useBytes = TRUE)

secondary_table <- c(
  "\\begin{table}[!htbp]", "\\centering", "\\scriptsize",
  "\\resizebox{\\textwidth}{!}{%",
  "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.23\\textwidth}rrrr@{}}",
  "\\toprule",
  paste0("Simulation setting & \\shortstack{Joint Q--DESN\\\\\\(\\AL\\)--\\(\\RHS\\)} & ",
         "\\shortstack{Independent Q--DESN\\\\\\(\\AL\\)--\\(\\RHS\\)} & ",
         "\\shortstack{Joint exQDESN\\\\\\(\\exAL\\)--\\(\\RHS\\)} & ",
         "\\shortstack{Independent exQDESN\\\\\\(\\exAL\\)--\\(\\RHS\\)} \\\\"),
  "\\midrule"
)
for (sid in scenario_order) {
  block <- forecast[forecast$scenario_id == sid, , drop = FALSE]
  block <- block[match(model_order, block$source_model_id), , drop = FALSE]
  values <- mapply(fmt_pair, block$realized_acrps,
                   block$average_quantile_loss, USE.NAMES = FALSE)
  secondary_table <- c(secondary_table, paste0(
    paste(c(scenario_tex[[sid]], values), collapse = " & "), " \\\\"
  ))
}
secondary_table <- c(
  secondary_table, "\\bottomrule", "\\end{tabular}", "}%",
  paste0("\\caption{Secondary scores against realized observations. Entries ",
    "are finite-grid realized \\(\\aCRPS\\) with unweighted average check ",
    "loss in parentheses, evaluated on the reported posterior-mean quantile grid. ",
    "These scores supplement, rather than replace, the known-DGP expected ",
    "score used for the primary comparison.}"),
  "\\label{tab:supp-joint-qdesn-corrected-v4-secondary}", "\\end{table}"
)
writeLines(secondary_table, file.path(table_dir,
  "joint_qdesn_corrected_v4_secondary_score_table.tex"), useBytes = TRUE)

oracle_table <- c(
  "\\begin{table}[p]", "\\centering", "\\scriptsize",
  "\\setlength{\\tabcolsep}{4pt}",
  "\\resizebox{\\textwidth}{!}{%",
  "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.18\\textwidth}>{\\raggedright\\arraybackslash}p{0.27\\textwidth}rrrr@{}}",
  "\\toprule",
  paste0("Simulation setting & Model & Fit MAE & Fit RMSE & ",
         "Forecast MAE & Forecast RMSE \\\\"), "\\midrule"
)
for (ss in seq_along(scenario_order)) {
  sid <- scenario_order[[ss]]
  fit <- oracle[oracle$scenario_id == sid & oracle$window == "fit", , drop = FALSE]
  fore <- oracle[oracle$scenario_id == sid & oracle$window == "forecast", , drop = FALSE]
  fit <- fit[match(model_order, fit$source_model_id), , drop = FALSE]
  fore <- fore[match(model_order, fore$source_model_id), , drop = FALSE]
  for (jj in seq_along(model_order)) {
    oracle_table <- c(oracle_table, sprintf(
      "%s & %s & %.4f & %.4f & %.4f & %.4f \\\\",
      if (jj == 1L) scenario_tex[[sid]] else "", model_tex[[model_order[[jj]]]],
      fit$oracle_quantile_mae[[jj]], fit$oracle_quantile_rmse[[jj]],
      fore$oracle_quantile_mae[[jj]], fore$oracle_quantile_rmse[[jj]]
    ))
  }
  if (ss < length(scenario_order)) oracle_table <- c(oracle_table, "\\addlinespace[2pt]")
}
oracle_table <- c(
  oracle_table, "\\bottomrule", "\\end{tabular}", "}%",
  paste0("\\caption{Recovery of the known conditional quantile paths by the ",
    "reported posterior-mean grids. MAE and RMSE are oracle recovery ",
    "diagnostics, not proper scores against realized observations. All values ",
    "are computed after the pre-specified monotone reporting rule.}"),
  "\\label{tab:supp-joint-qdesn-corrected-v4-oracle}", "\\end{table}"
)
writeLines(oracle_table, file.path(table_dir,
  "joint_qdesn_corrected_v4_oracle_recovery_table.tex"), useBytes = TRUE)

protocol <- c(
  "\\begin{table}[!htbp]", "\\centering", "\\small",
  "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.25\\textwidth}>{\\raggedright\\arraybackslash}p{0.65\\textwidth}@{}}",
  "\\toprule", "Item & Specification \\\\" , "\\midrule",
  paste0("Feature design & One scenario-specific DESN/RHS specification is ",
    "selected on separate source realizations and shared by all four model ",
    "classes; the evaluation realization is excluded from selection. \\\\"),
  "Quantile grid & 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, and 0.95. \\\\" ,
  paste0("Sequential initialization & Gaussian ridge initializes Gaussian ",
    "RHS--VB; independent AL fits proceed outward from the median; each AL fit ",
    "initializes exAL at the same level; complete independent grids initialize ",
    "the corresponding joint fits; matching VB fits initialize MCMC. \\\\"),
  paste0("Common posterior target & All five chains in a model cell share fixed ",
    "prior hyperparameters and one verified posterior-target hash. Dispersed ",
    "initial states do not enter prior centers. The RHS global-scale shape uses ",
    "\\((d_\\beta+1)/2\\). \\\\"),
  paste0("Posterior simulation & Five chains per model cell. AL chains use ",
    "4,000 iterations, 1,000 burn-in iterations, and thinning by four; exAL ",
    "chains use 8,000 iterations, 2,000 burn-in iterations, and thinning by ",
    "four. The complete calculation retains 180,000 draws. \\\\"),
  paste0("Score distribution & The primary summary uses 750 equally spaced ",
    "retained draws from each chain, or 3,750 chain-balanced draws per model ",
    "cell. Independent quantile draws use the pre-specified seeded product ",
    "coupling; joint draws preserve cross-level identity. \\\\"),
  paste0("Forecast evaluation & Each comparison uses the same 990 sequentially ",
    "conditional origin--horizon rows. The primary criterion is DGP-integrated ",
    "\\(\\aCRPS\\) after monotone reporting. \\\\"),
  "\\bottomrule", "\\end{tabular}",
  paste0("\\caption{Design of the corrected common-posterior joint ",
    "multi-quantile evaluation. Initialization transfers starting values only; ",
    "each destination retains its own likelihood, prior, and posterior target.}"),
  "\\label{tab:joint-qdesn-corrected-v4-protocol}", "\\end{table}"
)
writeLines(protocol, file.path(table_dir,
  "joint_qdesn_corrected_v4_protocol.tex"), useBytes = TRUE)

plot_data <- data.frame(
  scenario_id = factor(score$scenario_id, levels = scenario_order),
  source_model_id = factor(score$source_model_id, levels = rev(model_order)),
  likelihood_family = score$likelihood_family,
  fit_structure = score$fit_structure,
  mean = score$posterior_score_mean,
  lo = score$posterior_score_q025,
  hi = score$posterior_score_q975,
  stringsAsFactors = FALSE
)

forecast_plot <- ggplot2::ggplot(
  plot_data, ggplot2::aes(y = source_model_id)
) +
  ggplot2::geom_segment(
    ggplot2::aes(x = lo, xend = hi, yend = source_model_id,
                 colour = likelihood_family), linewidth = 0.55
  ) +
  ggplot2::geom_point(
    ggplot2::aes(x = mean, colour = likelihood_family,
                 shape = interaction(fit_structure, likelihood_family)),
    size = 2.0, stroke = 0.75
  ) +
  ggplot2::facet_wrap(
    ~scenario_id, ncol = 2, scales = "free_x",
    labeller = ggplot2::as_labeller(scenario_labels)
  ) +
  ggplot2::scale_y_discrete(labels = model_short) +
  ggplot2::scale_colour_manual(values = c(AL = "#244E73", exAL = "#8A493D")) +
  ggplot2::scale_shape_manual(values = c(
    "joint.AL" = 16, "independent.AL" = 1,
    "joint.exAL" = 17, "independent.exAL" = 2
  )) +
  ggplot2::scale_x_continuous(
    breaks = function(limits) pretty(limits, n = 3),
    labels = function(x) formatC(x, format = "f", digits = 2)
  ) +
  ggplot2::labs(x = "DGP-integrated aCRPS", y = NULL) +
  ggplot2::theme_bw(base_size = 8.5) +
  ggplot2::theme(
    legend.position = "none",
    panel.grid.major.y = ggplot2::element_blank(),
    panel.grid.minor = ggplot2::element_blank(),
    strip.background = ggplot2::element_rect(fill = "#F1F2F3", colour = "#747474"),
    strip.text = ggplot2::element_text(face = "bold", size = 8),
    axis.text.y = ggplot2::element_text(size = 7.25),
    plot.margin = ggplot2::margin(5.5, 7, 5.5, 5.5)
  )
forecast_figure_path <- file.path(
  figure_dir, "joint_qdesn_corrected_v4_forecast_dgp_acrps.pdf"
)
ggplot2::ggsave(forecast_figure_path, forecast_plot,
                device = grDevices::cairo_pdf,
                width = 7.0, height = 8.1, units = "in")

fit_oracle <- oracle[oracle$window == "fit", , drop = FALSE]
fit_oracle$scenario_id <- factor(fit_oracle$scenario_id, levels = scenario_order)
fit_oracle$source_model_id <- factor(fit_oracle$source_model_id,
                                     levels = rev(model_order))
fit_plot <- ggplot2::ggplot(
  fit_oracle, ggplot2::aes(y = source_model_id)
) +
  ggplot2::geom_point(
    ggplot2::aes(x = oracle_quantile_rmse, colour = likelihood_family,
                 shape = interaction(fit_structure, likelihood_family)),
    size = 2.1, stroke = 0.75
  ) +
  ggplot2::facet_wrap(
    ~scenario_id, ncol = 2, scales = "free_x",
    labeller = ggplot2::as_labeller(scenario_labels)
  ) +
  ggplot2::scale_y_discrete(labels = model_short) +
  ggplot2::scale_colour_manual(values = c(AL = "#244E73", exAL = "#8A493D")) +
  ggplot2::scale_shape_manual(values = c(
    "joint.AL" = 16, "independent.AL" = 1,
    "joint.exAL" = 17, "independent.exAL" = 2
  )) +
  ggplot2::scale_x_continuous(
    breaks = function(limits) pretty(limits, n = 3),
    labels = function(x) formatC(x, format = "f", digits = 2)
  ) +
  ggplot2::labs(x = "Fitting-sample quantile-path RMSE", y = NULL) +
  ggplot2::theme_bw(base_size = 8.5) +
  ggplot2::theme(
    legend.position = "none",
    panel.grid.major.y = ggplot2::element_blank(),
    panel.grid.minor = ggplot2::element_blank(),
    strip.background = ggplot2::element_rect(fill = "#F1F2F3", colour = "#747474"),
    strip.text = ggplot2::element_text(face = "bold", size = 8),
    axis.text.y = ggplot2::element_text(size = 7.25),
    plot.margin = ggplot2::margin(5.5, 7, 5.5, 5.5)
  )
fit_figure_path <- file.path(
  figure_dir, "joint_qdesn_corrected_v4_fit_oracle_rmse.pdf"
)
ggplot2::ggsave(fit_figure_path, fit_plot,
                device = grDevices::cairo_pdf,
                width = 7.0, height = 8.1, units = "in")

forecast_wrapper <- c(
  "\\begin{figure}[!htbp]", "\\centering",
  "\\includegraphics[width=0.94\\textwidth]{figures/joint_qdesn_simulation/joint_qdesn_corrected_v4_forecast_dgp_acrps.pdf}",
  paste0("\\caption{Corrected posterior DGP-integrated \\(\\aCRPS\\) for the ",
    "joint multi-quantile study. Colored points are posterior means and ",
    "horizontal segments are equal-tailed 95\\% intervals. Lower values are ",
    "better. Filled ",
    "symbols denote joint fits, open symbols independent fits, blue \\(\\AL\\), ",
    "and red \\(\\exAL\\). Marginal intervals for the numerical winner and ",
    "runner-up overlap in every setting. Crossing frequencies and monotone-",
    "adjustment magnitudes are reported in the supplement.}"),
  "\\label{fig:joint-qdesn-corrected-v4-forecast-acrps}", "\\end{figure}"
)
fit_wrapper <- c(
  "\\begin{figure}[!htbp]", "\\centering",
  "\\includegraphics[width=0.94\\textwidth]{figures/joint_qdesn_simulation/joint_qdesn_corrected_v4_fit_oracle_rmse.pdf}",
  paste0("\\caption{Fitting-sample recovery of the known conditional quantile ",
    "paths in the corrected joint study. Points are RMSE values for the ",
    "reported posterior-mean quantile grids, not posterior intervals. Filled ",
    "symbols denote joint fits, open symbols independent fits, blue \\(\\AL\\), ",
    "and red \\(\\exAL\\). Crossing frequencies and monotone-adjustment ",
    "magnitudes are reported separately.}"),
  "\\label{fig:joint-qdesn-corrected-v4-fit-rmse}", "\\end{figure}"
)
writeLines(forecast_wrapper, file.path(table_dir,
  "joint_qdesn_corrected_v4_forecast_figure.tex"), useBytes = TRUE)
writeLines(fit_wrapper, file.path(table_dir,
  "joint_qdesn_corrected_v4_fit_figure.tex"), useBytes = TRUE)

generated <- c(
  sub(paste0("^", normalizePath(repo_root, mustWork = TRUE), "/"), "",
      normalizePath(unname(staged_paths), mustWork = TRUE)),
  "tables/joint_qdesn_corrected_v4_score_table.tex",
  "tables/joint_qdesn_corrected_v4_contrast_table.tex",
  "tables/joint_qdesn_corrected_v4_crossing_table.tex",
  "tables/joint_qdesn_corrected_v4_secondary_score_table.tex",
  "tables/joint_qdesn_corrected_v4_oracle_recovery_table.tex",
  "tables/joint_qdesn_corrected_v4_protocol.tex",
  "tables/joint_qdesn_corrected_v4_forecast_figure.tex",
  "tables/joint_qdesn_corrected_v4_fit_figure.tex",
  "figures/joint_qdesn_simulation/joint_qdesn_corrected_v4_forecast_dgp_acrps.pdf",
  "figures/joint_qdesn_simulation/joint_qdesn_corrected_v4_fit_oracle_rmse.pdf"
)
manifest <- data.frame(
  artifact_id = sub("[.][^.]+$", "", basename(generated)),
  tracked_path = generated,
  tracked_sha256 = vapply(file.path(repo_root, generated), sha256, character(1L)),
  source_score_contract_sha256 = expected_contract_sha,
  source_transfer_inventory_sha256 = expected_transfer_sha,
  source_execution_commit = source_execution_commit,
  source_lane_head = source_lane_head,
  source_runtime = basename(runtime_root),
  stringsAsFactors = FALSE
)
write_csv(manifest, file.path(table_dir,
  "joint_qdesn_corrected_v4_article_asset_manifest.csv"))

cat(paste0(
  "JOINT_CORRECTED_ARTICLE_PROJECTION_V4=PASS ",
  "score_cells=32 contrasts=16 mean_winners_independent_exal=7 ",
  "canonical_winners_independent_exal=8 directional_independent=4 ",
  "overlapping=12 forecast_crossings=1197,3522,0,269\n"
))
