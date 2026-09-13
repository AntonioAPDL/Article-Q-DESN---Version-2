#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, digits = 17)

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
table_dir <- file.path(repo_root, "tables")
read_table <- function(name) read.csv(
  file.path(table_dir, name), stringsAsFactors = FALSE, check.names = FALSE
)
sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
expect <- function(value, message) {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}

contract_sha <-
  "d2d118f1b1b1e6feedcd4d552c20ad6d95902d1be833f5af257d7b61f0289ad1"
transfer_sha <-
  "e4b98fe89a8a0c2323f8205c1abef608ff733bc5ec323ea6372198caca02191d"
source_sha <- c(
  joint_qdesn_corrected_v4_posterior_dgp_integrated_acrps_summary.csv =
    "2470ef53eed99899fea41b1f97cde18687b11c9d9b6455cda8dff8ea29b8adf8",
  joint_qdesn_corrected_v4_scenario_winner_summary.csv =
    "f98ba9b18f4985afc085d68455e60a7e0bf19fd27bc86022591febd3518b98b2",
  joint_qdesn_corrected_v4_joint_independent_contrast_summary.csv =
    "49cf419bdf0f4c89280f8b1d6a632c261d9c8b3eee70244376f6589f85a2fc34",
  joint_qdesn_corrected_v4_forecast_metric_summary.csv =
    "8258d729ede6f577c0abbf3cabeb040d22cec0aafb72606aaa30c32322f8cdd6",
  joint_qdesn_corrected_v4_oracle_recovery_summary.csv =
    "c160c0e12183ca3e1404e5efad8547dcb0599fe6b562b301a720173398b5d1aa",
  joint_qdesn_corrected_v4_crossing_and_adjustment_summary.csv =
    "4f1efb0a95f23df485643ff9450272488eb48559c1f85fdd5dfd7c25e6be81e5",
  joint_qdesn_corrected_v4_phase181_reconciliation.csv =
    "02deccb5d29df490b1031c52c9f3f1ffc817a37ffca4a14aaf3713c93d62274c"
)
for (name in names(source_sha)) {
  path <- file.path(table_dir, name)
  expect(file.exists(path), paste("Missing staged v4 source:", name))
  expect(identical(sha256(path), source_sha[[name]]),
         paste("Staged v4 source hash mismatch:", name))
}

score <- read_table(
  "joint_qdesn_corrected_v4_posterior_dgp_integrated_acrps_summary.csv"
)
winners <- read_table("joint_qdesn_corrected_v4_scenario_winner_summary.csv")
contrasts <- read_table(
  "joint_qdesn_corrected_v4_joint_independent_contrast_summary.csv"
)
forecast <- read_table("joint_qdesn_corrected_v4_forecast_metric_summary.csv")
oracle <- read_table("joint_qdesn_corrected_v4_oracle_recovery_summary.csv")
crossings <- read_table(
  "joint_qdesn_corrected_v4_crossing_and_adjustment_summary.csv"
)
reconciliation <- read_table(
  "joint_qdesn_corrected_v4_phase181_reconciliation.csv"
)
manifest <- read_table("joint_qdesn_corrected_v4_article_asset_manifest.csv")

model_order <- c(
  "joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb",
  "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"
)
expect(nrow(score) == 32L && nrow(winners) == 8L &&
         nrow(contrasts) == 16L && nrow(forecast) == 32L &&
         nrow(oracle) == 64L && nrow(crossings) == 64L &&
         nrow(reconciliation) == 32L,
       "The corrected projection has an unexpected source row count.")
expect(all(table(score$scenario_id) == 4L) &&
         setequal(score$source_model_id, model_order),
       "The corrected score packet is not balanced over four models.")
expect(all(is.finite(score$posterior_score_mean)) &&
         all(score$posterior_score_q025 <= score$posterior_score_median) &&
         all(score$posterior_score_median <= score$posterior_score_q975) &&
         all(score$canonical_contract_crossing_pairs == 0L),
       "The score intervals or reporting contract are invalid.")

mean_winners <- do.call(rbind, lapply(split(score, score$scenario_id),
  function(x) x[which.min(x$posterior_score_mean), , drop = FALSE]))
action_winners <- do.call(rbind, lapply(split(score, score$scenario_id),
  function(x) x[which.min(x$canonical_action_dgp_integrated_acrps), , drop = FALSE]))
expect(sum(mean_winners$source_model_id == "exqdesn_rhs_independent_vb") == 7L &&
         sum(mean_winners$source_model_id == "joint_exqdesn_rhs_vb") == 1L &&
         all(action_winners$source_model_id == "exqdesn_rhs_independent_vb") &&
         all(winners$intervals_overlap_runner_up),
       "The posterior-mean or canonical-action winner pattern changed.")
expect(sum(contrasts$score_delta_q025 > 0) == 4L &&
         sum(contrasts$score_delta_q025 <= 0 & contrasts$score_delta_q975 >= 0) == 12L &&
         all(contrasts$score_delta_q975 >= 0),
       "The corrected joint-minus-independent contrasts changed.")
expect(sum(score$score_functional_status == "pass") == 22L &&
         sum(score$score_functional_status == "review") == 10L &&
         sum(score$coherence_status == "pass") == 8L &&
         sum(score$coherence_status == "review") == 24L,
       "The score or coherence diagnostic counts changed.")

forecast_cross <- aggregate(
  cbind(raw_crossing_pairs, contract_crossing_pairs,
        raw_crossing_opportunities) ~ source_model_id,
  crossings[crossings$window == "forecast", , drop = FALSE], sum
)
expected_cross <- c(
  joint_qdesn_rhs_vb = 1197L,
  qdesn_rhs_independent_vb = 3522L,
  joint_exqdesn_rhs_vb = 0L,
  exqdesn_rhs_independent_vb = 269L
)
observed_cross <- forecast_cross$raw_crossing_pairs[
  match(names(expected_cross), forecast_cross$source_model_id)
]
expected_rate <- c(
  joint_qdesn_rhs_vb = 0.0251893939393939,
  qdesn_rhs_independent_vb = 0.0741161616161616,
  joint_exqdesn_rhs_vb = 0,
  exqdesn_rhs_independent_vb = 0.00566077441077441
)
observed_rate <- with(
  forecast_cross,
  raw_crossing_pairs / raw_crossing_opportunities
)[match(names(expected_rate), forecast_cross$source_model_id)]
expect(identical(as.integer(observed_cross), unname(expected_cross)) &&
         all(forecast_cross$raw_crossing_opportunities == 47520L) &&
         max(abs(observed_rate - unname(expected_rate))) < 1e-12 &&
         all(forecast_cross$contract_crossing_pairs == 0L),
       "The corrected crossing totals or rates changed.")
expect(all(reconciliation$comparability_label == "descriptively_comparable") &&
         all(reconciliation$score_contract_version ==
               "joint_qdesn_corrected_article_score_packet_v4"),
       "The corrected packet no longer preserves the Phase181 boundary.")

expect(nrow(manifest) == 17L && !anyDuplicated(manifest$tracked_path),
       "The corrected article asset manifest is incomplete or duplicated.")
expect(all(manifest$source_score_contract_sha256 == contract_sha) &&
         all(manifest$source_transfer_inventory_sha256 == transfer_sha) &&
         all(manifest$source_execution_commit ==
               "b9af9ef4a7da8b507827dce9cd0d6d0b2a53ab24") &&
         all(manifest$source_lane_head ==
               "ca1cffa155cc5a3491f2492eeef83a31d30044bf"),
       "The corrected article asset provenance changed.")
for (ii in seq_len(nrow(manifest))) {
  path <- file.path(repo_root, manifest$tracked_path[[ii]])
  expect(file.exists(path), paste("Missing corrected article asset:", path))
  expect(identical(sha256(path), manifest$tracked_sha256[[ii]]),
         paste("Corrected article asset hash mismatch:", path))
}

main <- paste(readLines(file.path(repo_root, "main.tex"), warn = FALSE),
              collapse = "\n")
supp <- paste(readLines(file.path(repo_root, "qdesn-supplement.tex"),
                       warn = FALSE), collapse = "\n")
article_files <- readLines(
  file.path(repo_root, "overleaf", "article_files.txt"), warn = FALSE
)
expect(grepl(
  "\\input{tables/joint_qdesn_corrected_v4_forecast_figure.tex}",
  main, fixed = TRUE),
  "The main article does not use the corrected v4 forecast figure.")
expect(grepl("four intervals favor", main, fixed = TRUE) &&
         grepl("twelve include", main, fixed = TRUE) &&
         grepl("47,520 adjacent-level", main, fixed = TRUE) &&
         grepl("2.52\\%", main, fixed = TRUE) &&
         grepl("7.41\\%", main, fixed = TRUE) &&
         grepl("0.57\\%", main, fixed = TRUE) &&
         grepl("22 comparisons", main, fixed = TRUE),
       "The main-text corrected interpretation is incomplete.")
expect(grepl("\\input{tables/joint_qdesn_corrected_v4_score_table.tex}",
             supp, fixed = TRUE) &&
         grepl("\\input{tables/joint_qdesn_corrected_v4_fit_figure.tex}",
               supp, fixed = TRUE) &&
         grepl("(d_\\beta+1)/2", supp, fixed = TRUE) &&
         grepl("Posterior-target hashes agree", supp, fixed = TRUE),
       "The supplement does not document the corrected v4 packet.")
expect(!grepl("joint_qdesn_shared_backbone_forecast_figure", main, fixed = TRUE) &&
         !grepl("joint_qdesn_shared_backbone_score_table", supp, fixed = TRUE) &&
         !grepl("provisional article authority", supp, fixed = TRUE),
       "A historical article input or provisional claim remains active.")

reader_files <- c(
  "tables/joint_qdesn_corrected_v4_score_table.tex",
  "tables/joint_qdesn_corrected_v4_crossing_table.tex",
  "tables/joint_qdesn_corrected_v4_secondary_score_table.tex",
  "tables/joint_qdesn_corrected_v4_oracle_recovery_table.tex",
  "tables/joint_qdesn_corrected_v4_forecast_figure.tex",
  "tables/joint_qdesn_corrected_v4_fit_figure.tex"
)
reader_text <- paste(c(
  main, supp,
  unlist(lapply(reader_files, function(path) {
    readLines(file.path(repo_root, path), warn = FALSE)
  }))
), collapse = "\n")
expect(!grepl(
  "canonical-action|Canonical action|black vertical|raw/reported",
  reader_text, ignore.case = TRUE
), "Reader-facing canonical-action or count-label terminology remains.")
score_tex <- paste(readLines(
  file.path(repo_root, "tables/joint_qdesn_corrected_v4_score_table.tex"),
  warn = FALSE
), collapse = "\n")
crossing_tex <- paste(readLines(
  file.path(repo_root, "tables/joint_qdesn_corrected_v4_crossing_table.tex"),
  warn = FALSE
), collapse = "\n")
expect(!grepl("canonical", score_tex, ignore.case = TRUE) &&
         grepl("rate (count/\\(N\\))", crossing_tex, fixed = TRUE) &&
         grepl("mean/max", crossing_tex, fixed = TRUE) &&
         grepl("magnitude", crossing_tex, fixed = TRUE),
       "The simplified score or crossing table contract is incomplete.")

required_overleaf <- c(
  "figures/joint_qdesn_simulation/joint_qdesn_corrected_v4_fit_oracle_rmse.pdf",
  "figures/joint_qdesn_simulation/joint_qdesn_corrected_v4_forecast_dgp_acrps.pdf",
  "tables/joint_qdesn_corrected_v4_contrast_table.tex",
  "tables/joint_qdesn_corrected_v4_crossing_table.tex",
  "tables/joint_qdesn_corrected_v4_fit_figure.tex",
  "tables/joint_qdesn_corrected_v4_forecast_figure.tex",
  "tables/joint_qdesn_corrected_v4_oracle_recovery_table.tex",
  "tables/joint_qdesn_corrected_v4_protocol.tex",
  "tables/joint_qdesn_corrected_v4_score_table.tex",
  "tables/joint_qdesn_corrected_v4_secondary_score_table.tex"
)
expect(all(required_overleaf %in% article_files),
       "The article-only file list is missing corrected v4 assets.")
expect(!any(grepl("joint_qdesn_shared_backbone", article_files, fixed = TRUE)),
       "The article-only file list still publishes historical assets.")
listed_files <- article_files[!grepl("^[[:space:]]*(#|$)", article_files)]
expect(identical(listed_files, sort(listed_files)),
       "The article-only file list is not sorted.")

pdfs <- file.path(repo_root, required_overleaf[grepl("[.]pdf$", required_overleaf)])
for (pdf in pdfs) {
  info <- system2("pdfinfo", pdf, stdout = TRUE, stderr = TRUE)
  expect(is.null(attr(info, "status")) &&
           any(grepl("^Pages:[[:space:]]+1$", info)),
         paste("Expected a one-page corrected figure:", pdf))
  images <- system2("pdfimages", c("-list", pdf), stdout = TRUE, stderr = TRUE)
  image_rows <- grep(
    "^[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+image", images,
    value = TRUE
  )
  expect(is.null(attr(images, "status")) && length(image_rows) == 0L,
         paste("Expected a vector-only corrected figure:", pdf))
  text_path <- tempfile(fileext = ".txt")
  status <- system2("pdftotext", c(pdf, text_path), stdout = TRUE, stderr = TRUE)
  expect(is.null(attr(status, "status")) && file.exists(text_path),
         paste("Could not inspect visible labels in:", pdf))
  visible <- paste(readLines(text_path, warn = FALSE), collapse = " ")
  unlink(text_path)
  label <- if (grepl("forecast", basename(pdf), fixed = TRUE)) {
    "DGP-integrated aCRPS"
  } else {
    "Fitting-sample quantile-path RMSE"
  }
  expect(grepl(label, visible, fixed = TRUE),
         paste("The visible metric label is missing from:", pdf))
  expect(!grepl("[0-9]+/[0-9]+", visible, perl = TRUE),
         paste("A raw/reported crossing label remains in:", pdf))
}

cat(paste0(
  "JOINT_CORRECTED_ARTICLE_PROJECTION_V4_CHECK=PASS ",
  "score_cells=32 contrasts=16 mean_winners_independent_exal=7 ",
  "canonical_winners_independent_exal=8 directional_independent=4 ",
  "overlapping=12 forecast_crossings=1197,3522,0,269\n"
))
