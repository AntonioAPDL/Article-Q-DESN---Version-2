#!/usr/bin/env Rscript

# Editorial and scientific-invariance checks for the final unified revision.
# This script reads tracked article sources only; it does not fit a model,
# recompute a score, or modify an article asset.

options(stringsAsFactors = FALSE, digits = 17)

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
repo_path <- function(relative) file.path(repo_root, relative)
sha256 <- function(relative) unname(tools::sha256sum(repo_path(relative))[[1L]])
expect <- function(value, message) {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}
read_text <- function(relative) {
  paste(readLines(repo_path(relative), warn = FALSE), collapse = "\n")
}

immutable_hashes <- c(
  "tables/qdesn_validation_500obs_metric_intervals_v14_summary.csv" =
    "897ec68de29b8bdec29ef8b5058dec5b9760707b5320eb82a2ff1112e6730080",
  "tables/qdesn_validation_500obs_dgp_oracle_reference_v1.csv" =
    "1adc9c8c83b3564ef84be90e146286feac604484638ee31bbe684b66cbe928a8",
  "tables/qdesn_validation_500obs_dgp_oracle_figure_data_v14.csv" =
    "fefad4ff09b221483a2c299a06b7142d41090e06cfa9ad37f396a2551e9f398a",
  "tables/joint_qdesn_corrected_v4_posterior_dgp_integrated_acrps_summary.csv" =
    "2470ef53eed99899fea41b1f97cde18687b11c9d9b6455cda8dff8ea29b8adf8",
  "tables/joint_qdesn_corrected_v4_scenario_winner_summary.csv" =
    "f98ba9b18f4985afc085d68455e60a7e0bf19fd27bc86022591febd3518b98b2",
  "tables/joint_qdesn_corrected_v4_joint_independent_contrast_summary.csv" =
    "49cf419bdf0f4c89280f8b1d6a632c261d9c8b3eee70244376f6589f85a2fc34",
  "tables/joint_qdesn_corrected_v4_forecast_metric_summary.csv" =
    "8258d729ede6f577c0abbf3cabeb040d22cec0aafb72606aaa30c32322f8cdd6",
  "tables/joint_qdesn_corrected_v4_oracle_recovery_summary.csv" =
    "c160c0e12183ca3e1404e5efad8547dcb0599fe6b562b301a720173398b5d1aa",
  "tables/joint_qdesn_corrected_v4_crossing_and_adjustment_summary.csv" =
    "4f1efb0a95f23df485643ff9450272488eb48559c1f85fdd5dfd7c25e6be81e5",
  "tables/joint_qdesn_corrected_v4_phase181_reconciliation.csv" =
    "02deccb5d29df490b1031c52c9f3f1ffc817a37ffca4a14aaf3713c93d62274c",
  "tables/glofas_application_current_score_summary.csv" =
    "829d4467e4b734d4cd7a0dbab40ba72fe9b9c91c328908461f82f3093167d498",
  "tables/glofas_application_current_selection_manifest.csv" =
    "59792f78a055943cab6dd2e6e3eb829f08df9df6e2f98add05a4bec595b907de",
  "tables/pricefm_paper_aligned_main_comparison.csv" =
    "873e6cd28a26de916bbd4a0d096549057e443469aff084a9c12a4d03cd0c07ca",
  "tables/pricefm_r91_selective_promotions.csv" =
    "4d47aa52d44ff49187dd49a7921e590df39832a2927ce67ef9e68991f8023a1b"
)
for (relative in names(immutable_hashes)) {
  expect(file.exists(repo_path(relative)), paste("Missing scientific input:", relative))
  expect(identical(sha256(relative), immutable_hashes[[relative]]),
         paste("Scientific input changed:", relative))
}

independent <- read.csv(
  repo_path("tables/qdesn_validation_500obs_dgp_oracle_figure_data_v14.csv"),
  check.names = FALSE
)
joint_score <- read.csv(
  repo_path("tables/joint_qdesn_corrected_v4_posterior_dgp_integrated_acrps_summary.csv"),
  check.names = FALSE
)
joint_oracle <- read.csv(
  repo_path("tables/joint_qdesn_corrected_v4_oracle_recovery_summary.csv"),
  check.names = FALSE
)
crossing <- read.csv(
  repo_path("tables/joint_qdesn_corrected_v4_crossing_and_adjustment_summary.csv"),
  check.names = FALSE
)
expect(nrow(independent) == 216L &&
         sum(independent$diagnostic_grade == "WARN") == 5L,
       "The independent figure surface or warning count changed.")
expect(nrow(joint_score) == 32L && nrow(joint_oracle) == 64L &&
         all(joint_score$canonical_contract_crossing_pairs == 0L) &&
         all(crossing$contract_crossing_pairs == 0L),
       "The JOINT article surface or transformed crossings changed.")
forecast_crossing <- aggregate(
  raw_crossing_pairs ~ source_model_id,
  crossing[crossing$window == "forecast", , drop = FALSE], sum
)
expected_crossing <- c(
  joint_qdesn_rhs_vb = 1197L,
  qdesn_rhs_independent_vb = 3522L,
  joint_exqdesn_rhs_vb = 0L,
  exqdesn_rhs_independent_vb = 269L
)
observed_crossing <- forecast_crossing$raw_crossing_pairs[
  match(names(expected_crossing), forecast_crossing$source_model_id)
]
expect(identical(as.integer(observed_crossing), unname(expected_crossing)),
       "The JOINT raw crossing totals changed.")

main <- read_text("main.tex")
supplement <- read_text("qdesn-supplement.tex")
manuscript <- paste(main, supplement, sep = "\n")
internal_terms <- paste0(
  "\\b(lane|worker|queue|coordinator|handoff|launch lock|runtime artifact|",
  "promotion packet|score contract|frozen HEAD|frozen branch)\\b"
)
expect(!grepl(internal_terms, manuscript, ignore.case = TRUE, perl = TRUE),
       "Internal development terminology entered the manuscript.")
expect(!grepl("\\\\lambda\\s*\\(\\s*\\\\gamma", manuscript, perl = TRUE),
       "The exAL shift/local-scale notation collision remains.")
expect(!grepl("\\\\mathcal\\s*\\{[PCGRM]\\}", manuscript, perl = TRUE),
       "A one-use calligraphic collection symbol remains.")
expect(!grepl("p_q|q=1,\\\\ldots,Q|Q=1", manuscript, perl = TRUE),
       "The superseded quantile-grid index notation remains.")
expect(grepl("D_{p_0}(\\gamma)", main, fixed = TRUE) &&
         grepl("D_{p_0}(\\gamma)", supplement, fixed = TRUE),
       "The exAL positive-shift coefficient is not defined consistently.")
expect(grepl("\\aCRPS_{p_1:p_K}", main, fixed = TRUE) &&
         grepl("\\aCRPS_{p_1:p_K}", supplement, fixed = TRUE),
       "The finite-grid integrated check-loss notation is inconsistent.")

expect(grepl(
  "tables/qdesn_validation_500obs_v14_mcmc_forecast_metric_interval_figures.tex",
  main, fixed = TRUE
), "The main article does not contain the independent forecast figures.")
expect(grepl("tables/joint_qdesn_corrected_v4_forecast_figure.tex",
             main, fixed = TRUE),
       "The main article does not contain the JOINT forecast figure.")
expect(grepl(
  "tables/qdesn_validation_500obs_v14_mcmc_fit_metric_interval_figure.tex",
  supplement, fixed = TRUE
) && grepl("tables/qdesn_validation_500obs_v14_vb_metric_interval_figures.tex",
           supplement, fixed = TRUE) &&
  grepl("tables/joint_qdesn_corrected_v4_fit_figure.tex",
        supplement, fixed = TRUE),
"The supplement does not contain all fitting-sample figures.")
expect(!grepl("v14_vb_forecast_", supplement, fixed = TRUE),
       "Repeated VB forecast figures remain active in the supplement.")

reader_facing_independent <- paste(c(
  main,
  supplement,
  read_text("tables/qdesn_validation_500obs_metric_intervals_v14_prose.tex"),
  read_text("tables/qdesn_validation_500obs_v14_mcmc_forecast_metric_interval_figures.tex"),
  read_text("tables/qdesn_validation_500obs_v14_mcmc_metric_intervals_normal.tex"),
  read_text("tables/qdesn_validation_500obs_v14_mcmc_metric_intervals_laplace.tex"),
  read_text("tables/qdesn_validation_500obs_v14_mcmc_metric_intervals_gausmix.tex")
), collapse = "\n")
expect(!grepl(
  "dagger|diagnostic caution|diagnostic qualification|receive warnings|warning details",
  reader_facing_independent, ignore.case = TRUE
), "Internal independent-validation diagnostics remain reader-facing.")

reader_facing_joint <- paste(c(
  main,
  supplement,
  read_text("tables/joint_qdesn_corrected_v4_score_table.tex"),
  read_text("tables/joint_qdesn_corrected_v4_crossing_table.tex"),
  read_text("tables/joint_qdesn_corrected_v4_secondary_score_table.tex"),
  read_text("tables/joint_qdesn_corrected_v4_oracle_recovery_table.tex"),
  read_text("tables/joint_qdesn_corrected_v4_forecast_figure.tex"),
  read_text("tables/joint_qdesn_corrected_v4_fit_figure.tex")
), collapse = "\n")
expect(!grepl(
  "canonical-action|Canonical action|black vertical|raw/reported",
  reader_facing_joint, ignore.case = TRUE
), "Reader-facing JOINT presentation still contains internal action or count labels.")
expect(grepl("47,520 adjacent-level", main, fixed = TRUE) &&
         grepl("2.52\\%", main, fixed = TRUE) &&
         grepl("7.41\\%", main, fixed = TRUE) &&
         grepl("0.57\\%", main, fixed = TRUE),
       "The main article does not report normalized JOINT crossing rates.")
expect(grepl(
  "Frequency and magnitude of monotone correction",
  read_text("tables/joint_qdesn_corrected_v4_crossing_table.tex"),
  fixed = TRUE
), "The supplement does not distinguish crossing frequency from adjustment magnitude.")

article_files <- readLines(repo_path("overleaf/article_files.txt"), warn = FALSE)
expect(!any(grepl("v14_vb_forecast_", article_files, fixed = TRUE)),
       "Repeated VB forecast figures remain in the article-only snapshot.")
expect(file.exists(repo_path(
  "docs/implementation_notes/joint_qvp_rhs_deferred_rerun_register_20260908.md"
)), "The deferred RHS correction register is missing.")

abstract <- sub(".*\\\\begin\\{abstract\\}", "", main)
abstract <- sub("\\\\end\\{abstract\\}.*", "", abstract)
abstract_plain <- gsub("\\\\[A-Za-z]+|[{}$]", " ", abstract)
abstract_words <- strsplit(trimws(gsub("[^[:alnum:]'-]+", " ", abstract_plain)),
                           "[[:space:]]+")[[1L]]
expect(length(abstract_words) <= 250L,
       "The abstract exceeds the 250-word editorial limit.")

cat(sprintf(
  paste0("QDESN_FINAL_MANUSCRIPT_REVISION_CHECK=PASS scientific_files=%d ",
         "independent_roles=216 joint_oracle=64 joint_forecast=32 ",
         "reader_facing_internal_markers=0 abstract_words=%d\n"),
  length(immutable_hashes), length(abstract_words)
))
