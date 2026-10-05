#!/usr/bin/env Rscript

# Presentation-only projection of the frozen expanded pure-DESN comparison.
# This program verifies compact source evidence and never fits or scores a model.
# Public reproduction from the 15 immutable, tracked source CSVs:
# Rscript scripts/build_joint_qdesn_pure_desn_article_projection.R --published-sources
# The default mode verifies the complete original 54-file handoff inventory.
options(stringsAsFactors = FALSE, digits = 17)
args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(flag, default) {
  at <- match(flag, args)
  if (is.na(at)) return(default)
  if (at == length(args)) stop(paste("Missing value for", flag), call. = FALSE)
  args[[at + 1L]]
}
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
repo_root <- normalizePath(arg_value("--repo-root", file.path(dirname(script_path), "..")), mustWork = TRUE)
published_sources <- "--published-sources" %in% args
handoff_root <- if (published_sources) NULL else normalizePath(arg_value("--handoff-root", paste0(
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_pure_desn_expanded_score_closeout_20261004/",
  "local_trackers/joint_qdesn_pure_recursive_expanded_score_closeout_20261004/integration_handoff_20261005"
)), mustWork = TRUE)
expect <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)
sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
read_csv <- function(path) read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
prefix <- "joint_qdesn_pure_desn_v1_"
source_lane_head <- "de83993e89fc085df8799a5f43ca71fd64dcb77b"
expected_handoff_sha <- "16047c001451e6f14a5319e9e6942ed8829d861a237761fe8c413dc8ee695301"
expected_transfer_sha <- "e14362daf92ad2b8b750fef3519e21fc4a968e7fbb3edc010ddadfcf2603ad9e"
if (!published_sources) {
  handoff_path <- file.path(handoff_root, "JOINT_EXPANDED_CLOSEOUT_HANDOFF.md")
  inventory_path <- file.path(handoff_root, "transfer_inventory.csv")
  expect(identical(sha256(handoff_path), expected_handoff_sha), "Frozen handoff SHA-256 mismatch.")
  expect(identical(sha256(inventory_path), expected_transfer_sha), "Compact inventory SHA-256 mismatch.")
  inventory <- read_csv(inventory_path)
  expect(nrow(inventory) == 54L && sum(inventory$size_bytes) == 2256689,
         "Compact inventory cardinality or byte total changed.")
  expect(!anyDuplicated(inventory$relative_path) &&
           all(!grepl("(^/|(^|/)\\.\\.(/|$))", inventory$relative_path)),
         "Unsafe or duplicate compact inventory path.")
  for (ii in seq_len(nrow(inventory))) {
    path <- file.path(handoff_root, inventory$relative_path[[ii]])
    expect(file.exists(path) && file.info(path)$size == inventory$size_bytes[[ii]],
           paste("Compact evidence size mismatch:", inventory$relative_path[[ii]]))
    expect(identical(sha256(path), inventory$sha256[[ii]]),
           paste("Compact evidence hash mismatch:", inventory$relative_path[[ii]]))
  }
}

source_files <- c(
  forecast_score_summary.csv = "final_packet/forecast_score_summary.csv",
  crossing_summary.csv = "final_packet/crossing_summary.csv",
  posterior_contrast_summary.csv = "final_packet/posterior_contrast_summary.csv",
  scenario_winner_summary.csv = "final_packet/scenario_winner_summary.csv",
  fit_oracle_diagnostics.csv = "scientific_comparison/fit_oracle_diagnostics.csv",
  complete_packet_comparison.csv = "scientific_comparison/complete_packet_comparison.csv",
  recursive_policy_comparison.csv = "scientific_comparison/recursive_policy_comparison.csv",
  selected_backbones.csv = "selected_backbones.csv",
  frozen_contract.csv = "frozen_contract.csv",
  review_closeout_receipt.csv = "review_closeout_receipt.csv",
  cell_plan.csv = "cell_plan.csv",
  source_hashes.csv = "scientific_comparison/source_hashes.csv",
  manifest_audit.csv = "scientific_comparison/manifest_audit.csv",
  mcmc_posterior_target_hash_audit.csv = "mcmc_posterior_target_hash_audit.csv",
  sampler_audit.csv = "scientific_comparison/sampler_audit.csv"
)
# Authenticated pins from the compact inventory; derivative manifests are not
# a trust source. Both modes require the same immutable scientific inputs.
source_sha <- c(
  "forecast_score_summary.csv" = "a0be319e4486d5be122ad6dfe5ee9e2a470cd09ce5dfafc5d0af3925aecf2d1c",
  "crossing_summary.csv" = "80c929b6f94fefde8ed0a18126c538467759eca093aafae9fbef9eb33afb2e67",
  "posterior_contrast_summary.csv" = "d17c30c73a1a775eb032cc30cc4661d4686d6a1dbfc067033ecc4389fd4a9010",
  "scenario_winner_summary.csv" = "b378e0433efd9a04944f062e2a4edf70f17c187b63b287f51aea4daa30c2f509",
  "fit_oracle_diagnostics.csv" = "8ddcfe7740f3f58274f2517b148daa8a149a85d660dcfc73745f64ac303a0280",
  "complete_packet_comparison.csv" = "dc4024cc183097bf888f39c703b14c2db6db4e3a4eb7a27c5e5c50e8fc37275e",
  "recursive_policy_comparison.csv" = "1b38d1bb588138c1df230699f9c84554c897863c02b1dc4530dcb1839b4dfa11",
  "selected_backbones.csv" = "17856f23b4878eea6e0f5aa46ead8e31a315d2d11285f483674043db8e2f4129",
  "frozen_contract.csv" = "bbf8b12dd05d352eb0cfa84ffc71b9510ff667a68cecc897a29991f85cd683c7",
  "review_closeout_receipt.csv" = "1c2b99d2336636f0b5b55666620ca410a0e8137f8cf2dc9b435667da7bb4b903",
  "cell_plan.csv" = "bdd9b9406d0d0dedc468795797e9f96ca9fdb15e035eb2e4ef837634caf7dc72",
  "source_hashes.csv" = "9becc3a48616aecaff813ae230387faa24354de944e782b0b2cbca7058cc10b7",
  "manifest_audit.csv" = "396c3373772279885fd092d11ca5ff695faf56cf66dbe177d345d685ec2776ce",
  "mcmc_posterior_target_hash_audit.csv" = "fe477ae3769a40244505cd3d85a22364a52c11e58fc08770b05a11e1ac660ec1",
  "sampler_audit.csv" = "175eb77f3410546682aac1f1af9c3e8633e8805743d5b964f5783246971a8fc1"
)
expect(identical(names(source_files), names(source_sha)),
       "Immutable public-source pin set differs from the requested sources.")
if (!published_sources) {
  expect(all(unname(source_files) %in% inventory$relative_path),
         "A public source is absent from the compact inventory.")
}
source_paths <- if (published_sources) {
  setNames(file.path(repo_root, "tables", paste0(prefix, names(source_files))), names(source_files))
} else {
  setNames(file.path(handoff_root, unname(source_files)), names(source_files))
}
for (name in names(source_paths)) {
  path <- source_paths[[name]]
  expect(file.exists(path) && identical(sha256(path), unname(source_sha[[name]])),
         paste("Immutable scientific source SHA-256 mismatch:", name))
}
sources <- lapply(source_paths, read_csv)
score <- sources[["forecast_score_summary.csv"]]
cross <- sources[["crossing_summary.csv"]]
fit <- sources[["fit_oracle_diagnostics.csv"]]
contract <- sources[["frozen_contract.csv"]]
plan <- sources[["cell_plan.csv"]]
comparison <- sources[["complete_packet_comparison.csv"]]
policy <- sources[["recursive_policy_comparison.csv"]]
get_contract <- function(key) {
  block <- contract[contract$name == key, , drop = FALSE]
  expect(nrow(block) == 1L, paste("Nonunique contract field:", key))
  block$value[[1L]]
}
taus <- as.numeric(strsplit(get_contract("tau_grid"), ";", fixed = TRUE)[[1L]])
weights <- as.numeric(strsplit(get_contract("trapezoidal_weights"), ";", fixed = TRUE)[[1L]])
expect(identical(taus, c(.05, .10, .25, .50, .75, .90, .95)) &&
         isTRUE(all.equal(weights, c(.025, .100, .200, .250, .200, .100, .025))) &&
         abs(sum(weights) - .90) < 1e-12, "Seven-level quadrature contract changed.")
origins <- as.integer(get_contract("origins"))
horizons <- as.integer(get_contract("horizons"))
score_rows <- as.integer(get_contract("score_rows"))
score_draws_per_chain <- as.integer(get_contract("mcmc_score_draws_per_chain"))
score_draws <- 5L * score_draws_per_chain
expect(origins == 33L && horizons == 30L && score_rows == origins * horizons &&
         score_draws == 3750L, "Forecast geometry or score draw cardinality changed.")
source_hashes <- sources[["source_hashes.csv"]]
for (path in c("frozen_contract.csv", "cell_plan.csv")) {
  row <- source_hashes[basename(source_hashes$path) == path, , drop = FALSE]
  expect(nrow(row) == 1L && identical(sha256(source_paths[[path]]), row$sha256[[1L]]),
         paste("Scientific provenance hash mismatch:", path))
}
source(file.path(repo_root, "scripts/qdesn_evaluation_figure_style.R"), local = TRUE, chdir = FALSE)
scenario_order <- qdesn_scenario_order
model_order <- c("joint_qdesn_rhs_mcmc", "qdesn_rhs_independent_mcmc",
                 "joint_exqdesn_rhs_mcmc", "exqdesn_rhs_independent_mcmc")
model_style <- setNames(qdesn_joint_model_order, model_order)
model_short <- setNames(unname(qdesn_joint_model_labels), model_order)
scenario_tex <- qdesn_scenario_labels
scenario_tex[["student_t_location_scale"]] <- "Student-\\(t\\) location--scale"
key <- function(x) paste(x$scenario_id, x$model_cell_id, x$inference_method, sep = "|")
expect(nrow(score) == 64L && nrow(fit) == 64L && nrow(cross) == 64L &&
         nrow(plan) == 64L && nrow(comparison) == 64L && nrow(policy) == 64L &&
         !anyDuplicated(key(score)) && setequal(score$scenario_id, scenario_order) &&
         setequal(score$model_id, model_order), "The compact packet is not the complete 64-cell comparison.")
expect(all(table(score$inference_method) == 32L) &&
         all(is.finite(score$posterior_score_mean)) &&
         all(score$posterior_score_q025 <= score$posterior_score_median) &&
         all(score$posterior_score_median <= score$posterior_score_q975) &&
         all(score$contract_crossing_pairs == 0L) &&
         all(score$canonical_contract_crossing_pairs == 0L) &&
         all(score$path_contract_crossing_pairs == 0L), "Scores, intervals, or monotone reporting failed.")
mcmc <- score[score$inference_method == "mcmc", , drop = FALSE]
vb <- score[score$inference_method == "vb", , drop = FALSE]
expect(sum(mcmc$score_stability_status == "pass") == 31L &&
         sum(mcmc$score_stability_status == "review") == 1L &&
         mcmc$worker_id[mcmc$score_stability_status == "review"] == 41L,
       "The 31-pass/one-review MCMC qualification changed.")
review <- sources[["review_closeout_receipt.csv"]]
expect(nrow(review) == 1L && review$worker_id[[1L]] == 41L &&
         !review$strict_score_gate_pass[[1L]] && review$review_eligible[[1L]],
       "The original bounded stability review must remain explicit.")
expect(all(plan$fit_rows == 500L) && all(plan$scored_forecast_rows == score_rows) &&
         all(!plan$raw_inputs_in_readout) && all(plan$shared_across_four_quantile_rows) &&
         all(plan$protected_rows_used_for_selection == 0L), "Pure-DESN/shared-backbone selection contract changed.")
expect(nrow(sources[["selected_backbones.csv"]]) == 8L, "Expected eight selected backbones.")
expect(nrow(sources[["manifest_audit.csv"]]) == 232L &&
         sum(sources[["manifest_audit.csv"]]$verified_payloads) == 4808L &&
         all(sources[["manifest_audit.csv"]]$status == "pass"), "Source manifest audit changed.")
cross_mcmc <- cross[cross$inference_method == "mcmc", , drop = FALSE]
fit_mcmc <- fit[fit$inference_method == "mcmc", , drop = FALSE]
cross_mcmc <- cross_mcmc[match(key(mcmc), key(cross_mcmc)), , drop = FALSE]
fit_mcmc <- fit_mcmc[match(key(mcmc), key(fit_mcmc)), , drop = FALSE]
expect(max(abs(mcmc$raw_crossing_pairs / score_draws -
                 cross_mcmc$posterior_raw_crossing_pairs_mean)) < 1e-8,
       "Posterior crossing totals are inconsistent with the 3,750 score draws per cell.")
forecast_opportunities <- score_rows * (length(taus) - 1L)
fit_opportunities <- unique(plan$fit_rows) * (length(taus) - 1L)
crossings <- do.call(rbind, lapply(model_order, function(mid) {
  ii <- which(mcmc$model_id == mid)
  data.frame(model_id = mid,
    fit_raw_pairs = sum(fit_mcmc$fit_raw_crossing_pairs[ii]),
    fit_opportunities = length(ii) * fit_opportunities,
    forecast_raw_pairs = sum(mcmc$canonical_raw_crossing_pairs[ii]),
    forecast_opportunities = length(ii) * forecast_opportunities,
    posterior_forecast_raw_pairs = sum(mcmc$raw_crossing_pairs[ii]),
    posterior_forecast_opportunities = length(ii) * forecast_opportunities * score_draws,
    mean_abs_adjustment = mean(mcmc$canonical_mean_abs_monotone_adjustment[ii]),
    max_abs_adjustment = max(mcmc$canonical_max_abs_monotone_adjustment[ii]),
    contract_pairs = sum(mcmc$canonical_contract_crossing_pairs[ii]))
}))
expect(identical(as.integer(crossings$forecast_raw_pairs), c(11L,2645L,0L,288L)) &&
         all(crossings$forecast_opportunities == 47520L), "Canonical forecast crossing counts changed.")
crossings$fit_raw_percent <- 100 * crossings$fit_raw_pairs / crossings$fit_opportunities
crossings$forecast_raw_percent <- 100 * crossings$forecast_raw_pairs / crossings$forecast_opportunities
crossings$posterior_forecast_raw_percent <- 100 * crossings$posterior_forecast_raw_pairs /
  crossings$posterior_forecast_opportunities
winners <- do.call(rbind, lapply(scenario_order, function(sid) {
  block <- mcmc[mcmc$scenario_id == sid, , drop = FALSE]
  block <- block[order(block$posterior_score_mean), , drop = FALSE]
  expect(max(block$posterior_score_q025[1:2]) <= min(block$posterior_score_q975[1:2]),
         paste("Winner/runner-up intervals no longer overlap:", sid))
  block[1L, , drop = FALSE]
}))
expect(sum(winners$fit_structure == "joint") == 2L &&
         sum(winners$fit_structure == "independent") == 6L, "MCMC winner pattern changed.")
contrasts <- sources[["posterior_contrast_summary.csv"]]
contrasts <- contrasts[contrasts$inference_method == "mcmc" &
                         contrasts$contrast_type == "joint_minus_independent", , drop = FALSE]
expect(nrow(contrasts) == 16L && sum(contrasts$q975_difference < 0) == 2L &&
         sum(contrasts$q025_difference > 0) == 2L &&
         sum(contrasts$q025_difference <= 0 & contrasts$q975_difference >= 0) == 12L,
       "Descriptive joint/independent contrast pattern changed.")

table_dir <- file.path(repo_root, "tables")
figure_dir <- file.path(repo_root, "figures", "joint_qdesn_simulation")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
outputs <- character()
register <- function(path) { outputs <<- c(outputs, path); invisible(path) }
table_path <- function(name) file.path(table_dir, paste0(prefix, name))
write_tex <- function(lines, name) {
  path <- table_path(name)
  writeLines(lines, path, useBytes = TRUE)
  register(path)
}
for (name in names(source_files)) {
  source_path <- source_paths[[name]]
  path <- table_path(name)
  if (!identical(normalizePath(source_path, mustWork = TRUE),
                 normalizePath(path, mustWork = FALSE))) {
    expect(file.copy(source_path, path, overwrite = TRUE),
           paste("Could not copy public source:", name))
  }
  expect(identical(sha256(path), unname(source_sha[[name]])),
         paste("Staged public source SHA-256 mismatch:", name))
  register(path)
}
write.csv(crossings, table_path("crossing_rates.csv"), row.names = FALSE, na = "")
register(table_path("crossing_rates.csv"))
provenance <- data.frame(
  field = c("source_lane_head", "handoff_sha256", "transfer_inventory_sha256",
            "compact_verified_files", "compact_verified_bytes", "verified_manifests",
            "verified_payload_records", "mcmc_cells", "mcmc_strict_pass", "mcmc_bounded_review",
            "bounded_review_worker", "score_draws_per_cell", "forecast_adjacent_pairs_per_cell",
            "main_interval_scope", "baseline_scope"),
  value = c(source_lane_head, expected_handoff_sha, expected_transfer_sha,
            "54", "2256689", "232", "4808", "32", "31", "1", "41", "3750", "5940",
            "readout_uncertainty_conditional_on_each_models_averaged_recursive_design",
            "previous_frozen_narrow_pure_DESN_packet_not_previous_published_article"))
write.csv(provenance, table_path("projection_provenance.csv"), row.names = FALSE)
register(table_path("projection_provenance.csv"))

fmt_interval <- function(center, lo, hi) sprintf("%.4f [%.4f, %.4f]", center, lo, hi)
table_start <- function(columns, header, position = "p", size = "scriptsize") c(
  paste0("\\begin{table}[", position, "]"), "\\centering", paste0("\\", size),
  "\\setlength{\\tabcolsep}{3.5pt}", "\\renewcommand{\\arraystretch}{1.04}",
  "\\resizebox{\\textwidth}{!}{%", paste0("\\begin{tabular}{", columns, "}"),
  "\\toprule", paste0(header, " \\\\"), "\\midrule")
table_end <- function(caption, label) c("\\bottomrule", "\\end{tabular}", "}%",
  paste0("\\caption{", caption, "}"), paste0("\\label{", label, "}"), "\\end{table}")
balanced_table <- function(block, name, label, caption, fields, header, minima = FALSE) {
  lines <- table_start(paste0("@{}>{\\raggedright\\arraybackslash}p{0.21\\textwidth}",
    ">{\\raggedright\\arraybackslash}p{0.22\\textwidth}", paste(rep("r", length(fields)), collapse = ""), "@{}"), header)
  for (si in seq_along(scenario_order)) {
    sid <- scenario_order[[si]]
    x <- block[block$scenario_id == sid, , drop = FALSE]
    x <- x[match(model_order, x$model_id), , drop = FALSE]
    expect(nrow(x) == 4L && all(!is.na(x$model_id)), paste("Incomplete model block:", sid))
    for (mi in seq_along(model_order)) {
      values <- vapply(fields, function(field) sprintf("%.4f", x[[field]][[mi]]), character(1))
      if (minima && mi == which.min(x$posterior_score_mean))
        values[[1L]] <- paste0("\\textbf{", values[[1L]], "}")
      lines <- c(lines, paste0(paste(c(if (mi == 1L) scenario_tex[[sid]] else "",
        model_short[[model_order[[mi]]]], values), collapse = " & "), " \\\\"))
    }
    if (si < length(scenario_order)) lines <- c(lines, "\\addlinespace[2pt]")
  }
  write_tex(c(lines, table_end(caption, label)), name)
}
score_caption <- paste0("DGP-integrated finite-grid \\(\\aCRPS\\) in the pure-DESN multi-quantile study. ",
  "The posterior means, medians, and equal-tailed 95\\% limits condition on each model's averaged recursively generated forecast design. ",
  "The final column evaluates the posterior-mean quantile grid after the specified monotone projection; it is a different summary from the posterior mean of the score. ",
  "Boldface marks the lowest posterior mean within each setting. All winner/runner-up marginal intervals overlap.")
balanced_table(mcmc, "score_table.tex", "tab:joint-qdesn-pure-desn-v1-score", score_caption,
  c("posterior_score_mean", "posterior_score_median", "posterior_score_q025", "posterior_score_q975",
    "canonical_origin_marginal_dgp_integrated_acrps"),
  "Simulation setting & Model & Mean & Median & 2.5\\% & 97.5\\% & \\shortstack{Score at\\\\posterior-mean grid}", TRUE)
balanced_table(vb, "vb_score_table.tex", "tab:joint-qdesn-pure-desn-v1-vb-score",
  paste0("Approximate variational DGP-integrated \\(\\aCRPS\\) under the same seven-level comparison. ",
    "Intervals condition on point intercepts and each model's averaged recursive design; intercept covariance is omitted. ",
    "The final column is the score at the monotone posterior-mean quantile grid."),
  c("posterior_score_mean", "posterior_score_median", "posterior_score_q025", "posterior_score_q975",
    "canonical_origin_marginal_dgp_integrated_acrps"),
  "Simulation setting & Model & Mean & Median & 2.5\\% & 97.5\\% & \\shortstack{Score at\\\\posterior-mean grid}")

contrast_lines <- table_start("@{}>{\\raggedright\\arraybackslash}p{0.37\\textwidth}rr@{}",
  "Simulation setting & AL & exAL", "!htbp", "small")
for (sid in scenario_order) {
  x <- contrasts[contrasts$scenario_id == sid, , drop = FALSE]
  x <- x[match(c("AL joint minus independent", "exAL joint minus independent"), x$contrast_label), , drop = FALSE]
  values <- mapply(fmt_interval, x$mean_difference, x$q025_difference, x$q975_difference, USE.NAMES = FALSE)
  contrast_lines <- c(contrast_lines, paste0(paste(c(scenario_tex[[sid]], values), collapse = " & "), " \\\\"))
}
write_tex(c(contrast_lines, table_end(paste0(
  "Joint-minus-independent differences in DGP-integrated \\(\\aCRPS\\), with means and equal-tailed 95\\% intervals. ",
  "Positive differences favor independent estimation. The deterministic index pairing defines descriptive contrasts between separately fitted models; ",
  "the two intervals for the asymmetric-tail setting favor joint estimation, the two Laplace intervals favor independent estimation, and twelve include zero."),
  "tab:joint-qdesn-pure-desn-v1-contrasts")), "contrast_table.tex")

cross_lines <- table_start("@{}lrrrr@{}", paste0("Model & \\shortstack{Fit grid\\\\crossings (\\%)} & ",
  "\\shortstack{Forecast grid\\\\crossings (\\%)} & \\shortstack{Posterior-draw forecast\\\\crossings (\\%)} & ",
  "\\shortstack{Forecast adjustment\\\\mean / maximum}"), "!htbp", "small")
for (ii in seq_len(nrow(crossings))) {
  x <- crossings[ii, , drop = FALSE]
  cross_lines <- c(cross_lines, sprintf("%s & %.2f & %.2f & %.2f & %.4f / %.4f \\\\",
    model_short[[x$model_id]], x$fit_raw_percent, x$forecast_raw_percent,
    x$posterior_forecast_raw_percent, x$mean_abs_adjustment, x$max_abs_adjustment))
}
write_tex(c(cross_lines, table_end(paste0("Raw adjacent-level crossing rates and monotone adjustments. ",
  "The first two columns use posterior-mean quantile grids; the third averages crossing rates over 3,750 posterior draws per model cell. ",
  "Each model has 24,000 fitting comparisons and 47,520 forecast comparisons across eight settings; the posterior-draw denominator is 178,200,000. ",
  "Adjustment magnitudes are on the response scale. Every projected grid has zero crossings."),
  "tab:joint-qdesn-pure-desn-v1-crossings")), "crossing_table.tex")

oracle_block <- mcmc
oracle_block$fit_oracle_mae <- fit_mcmc$fit_oracle_mae
oracle_block$fit_oracle_rmse <- fit_mcmc$fit_oracle_rmse
balanced_table(oracle_block, "oracle_recovery_table.tex", "tab:joint-qdesn-pure-desn-v1-oracle",
  paste0("Recovery of the known conditional quantile paths by the monotone posterior-mean grids. ",
    "MAE and RMSE diagnose oracle-path recovery and are separate from scores against observations. Fitting entries are point diagnostics; no posterior intervals are available in the compact evidence."),
  c("fit_oracle_mae", "fit_oracle_rmse", "canonical_origin_marginal_oracle_quantile_mae",
    "canonical_origin_marginal_oracle_quantile_rmse"),
  "Simulation setting & Model & Fit MAE & Fit RMSE & Forecast MAE & Forecast RMSE")
balanced_table(mcmc, "secondary_score_table.tex", "tab:joint-qdesn-pure-desn-v1-secondary",
  paste0("Secondary finite-grid \\(\\aCRPS\\) against realized observations. ",
    "The first column averages the score over posterior readout draws conditional on the averaged recursive design; ",
    "the second evaluates the projected posterior-mean grid. These are distinct from the DGP-integrated primary criterion."),
  c("posterior_realized_acrps_mean", "canonical_realized_acrps"),
  "Simulation setting & Model & Posterior mean realized score & Score at posterior-mean grid")
policy_lines <- table_start(
  "@{}>{\\raggedright\\arraybackslash}p{0.20\\textwidth}>{\\raggedright\\arraybackslash}p{0.21\\textwidth}rr@{}",
  "Simulation setting & Model & Averaged design & Recursive trajectories", "p", "footnotesize")
for (si in seq_along(scenario_order)) {
  sid <- scenario_order[[si]]
  x <- mcmc[mcmc$scenario_id == sid, , drop = FALSE]
  x <- x[match(model_order, x$model_id), , drop = FALSE]
  for (mi in seq_along(model_order)) {
    values <- c(
      fmt_interval(x$posterior_score_mean[[mi]], x$posterior_score_q025[[mi]],
                   x$posterior_score_q975[[mi]]),
      fmt_interval(x$path_posterior_score_mean[[mi]], x$path_posterior_score_q025[[mi]],
                   x$path_posterior_score_q975[[mi]]))
    policy_lines <- c(policy_lines, paste0(paste(c(
      if (mi == 1L) scenario_tex[[sid]] else "",
      model_short[[model_order[[mi]]]], values), collapse = " & "), " \\\\"))
  }
  if (si < length(scenario_order)) policy_lines <- c(policy_lines, "\\addlinespace[2pt]")
}
write_tex(c(policy_lines, table_end(paste0(
  "Sensitivity to integration over recursively generated future designs. ",
  "Entries are posterior means with equal-tailed 95\\% intervals. ",
  "Averaged-design entries condition on each model's mean future feature matrix; trajectory entries retain draw-specific recursive states. ",
  "The comparison shows the effect of retaining recursive trajectories rather than conditioning on averaged features."),
  "tab:joint-qdesn-pure-desn-v1-recursive-policy")), "recursive_policy_table.tex")

# Reserve a separate annotation column without changing the shared plot style
# or the independent-study figures. Tick precision follows each panel's range.
separate_crossing_labels <- function(plot) {
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
  plot
}
plot_data <- data.frame(scenario_id = mcmc$scenario_id,
  source_model_id = unname(model_style[mcmc$model_id]), likelihood_family = mcmc$likelihood_family,
  mean = mcmc$posterior_score_mean, lo = mcmc$posterior_score_q025, hi = mcmc$posterior_score_q975,
  crossing = sprintf("%.2f%%", 100 * mcmc$canonical_raw_crossing_pairs / forecast_opportunities))
forecast_plot <- qdesn_joint_interval_plot(plot_data, "DGP-integrated aCRPS")
forecast_plot <- separate_crossing_labels(forecast_plot)
forecast_figure_path <- file.path(figure_dir, paste0(prefix, "forecast_dgp_acrps.pdf"))
qdesn_save_vector_pdf(forecast_figure_path, forecast_plot, 7.0, 8.1)
register(forecast_figure_path)
fit_plot_data <- plot_data
fit_plot_data$mean <- fit_mcmc$fit_oracle_rmse
fit_plot_data$lo <- fit_plot_data$hi <- fit_plot_data$mean
fit_plot_data$crossing <- sprintf("%.2f%%", 100 * fit_mcmc$fit_raw_crossing_pairs / fit_opportunities)
fit_plot <- qdesn_joint_interval_plot(fit_plot_data, "Fitting-sample quantile-path RMSE")
# Remove the interval layer: the frozen compact fit evidence contains point diagnostics only.
fit_plot$layers <- fit_plot$layers[-1L]
fit_plot <- separate_crossing_labels(fit_plot)
fit_figure_path <- file.path(figure_dir, paste0(prefix, "fit_oracle_rmse.pdf"))
qdesn_save_vector_pdf(fit_figure_path, fit_plot, 7.0, 8.1)
register(fit_figure_path)
write_tex(c("\\begin{figure}[!htbp]", "\\centering",
  paste0("\\includegraphics[width=0.94\\textwidth]{figures/joint_qdesn_simulation/", basename(forecast_figure_path), "}"),
  paste0("\\caption{DGP-integrated \\(\\aCRPS\\) for the pure-DESN multi-quantile study. ",
    "Points are posterior means and segments are equal-tailed 95\\% intervals, conditional on each model's averaged recursively generated forecast design. ",
    "Lower scores are better. The annotations \\(c\\) give raw adjacent-level crossing percentages for the posterior-mean grids; every grid is monotone after projection. ",
    "All winner/runner-up marginal intervals overlap.}"),
  "\\label{fig:joint-qdesn-pure-desn-v1-forecast-acrps}", "\\end{figure}"), "forecast_figure.tex")
write_tex(c("\\begin{figure}[p]", "\\centering",
  paste0("\\includegraphics[width=0.94\\textwidth]{figures/joint_qdesn_simulation/", basename(fit_figure_path), "}"),
  paste0("\\caption{Fitting-sample recovery of the known conditional quantile paths by the monotone posterior-mean grids. ",
    "Points show RMSE; the compact fitting evidence provides no posterior intervals. ",
    "The annotations \\(c\\) give raw adjacent-level crossing percentages before projection. These are oracle-recovery diagnostics rather than predictive scores.}"),
  "\\label{fig:joint-qdesn-pure-desn-v1-fit-rmse}", "\\end{figure}"), "fit_figure.tex")

protocol <- table_start("@{}>{\\raggedright\\arraybackslash}p{0.24\\textwidth}>{\\raggedright\\arraybackslash}p{0.67\\textwidth}@{}",
  "Item & Specification", "!htbp", "small")
protocol <- c(protocol,
  "Feature design & One selected reservoir specification per setting, shared across all four regressions. The readout contains an intercept and all reservoir-layer states; raw inputs enter the reservoir recursion only. \\\\",
  "Quantile levels & 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, and 0.95. Trapezoidal weights sum to 0.90. \\\\",
  "Forecast design & 33 origins and 30 horizons, giving 990 rows per setting. Observed histories update the state between origins; future response lags are generated recursively within each origin. \\\\",
  "Posterior simulation & Five chains per cell, retaining 750 AL draws or 1,500 exAL draws per chain. The score uses 750 draws per chain for either likelihood. Every exAL chain uses the exact scale-collapsed asymmetry transition. \\\\",
  "Initialization & Gaussian, AL, exAL, and joint fits provide starting values in the stated sequence. Fixed prior hyperparameters define each target and are common across its five chains. \\\\",
  "Primary intervals & Posterior readout uncertainty conditional on each model's averaged recursive design. Trajectory-inclusive intervals are reported separately. \\\\",
  "Computation & All 64 method--model cells are finite. One Laplace joint-AL MCMC cell remains under a bounded score-stability review; scalar-parameter mixing and score precision qualify descriptive comparisons. \\\\")
write_tex(c(protocol, table_end("Design and computation for the expanded pure-DESN comparison.",
  "tab:joint-qdesn-pure-desn-v1-protocol")), "protocol.tex")

asset_manifest <- data.frame(
  relative_path = substring(outputs, nchar(repo_root) + 2L),
  size_bytes = unname(file.info(outputs)$size),
  sha256 = vapply(outputs, sha256, character(1)),
  source_lane_head = source_lane_head,
  handoff_sha256 = expected_handoff_sha,
  transfer_inventory_sha256 = expected_transfer_sha,
  role = ifelse(grepl("\\.pdf$", outputs), "figure",
                ifelse(grepl("\\.tex$", outputs), "article_wrapper_or_table", "compact_scientific_summary")))
asset_manifest$metric <- ifelse(grepl("forecast_dgp_acrps\\.pdf$", outputs),
  "posterior_score_mean", ifelse(grepl("fit_oracle_rmse\\.pdf$", outputs), "fit_oracle_rmse", ""))
asset_manifest$interval_scope <- ifelse(grepl("forecast_dgp_acrps\\.pdf$", outputs),
  "posterior_score_q025_q975_conditional_on_mean_design",
  ifelse(grepl("fit_oracle_rmse\\.pdf$", outputs), "point_diagnostic_no_intervals", ""))
write.csv(asset_manifest, table_path("article_asset_manifest.csv"), row.names = FALSE, na = "")
cat(sprintf("JOINT_PURE_DESN_ARTICLE_BUILD=PASS source_verification=%s source_rows=64 mcmc_rows=32 figures=2 outputs=%d strict_mcmc_pass=31 bounded_review=1\n",
            if (published_sources) "15_immutable_published_csvs" else "54_file_original_handoff",
            nrow(asset_manifest)))
