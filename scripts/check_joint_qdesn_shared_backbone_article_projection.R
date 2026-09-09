#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, digits = 17)

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
read_table <- function(name) read.csv(
  file.path(repo_root, "tables", name), stringsAsFactors = FALSE,
  check.names = FALSE
)
expect <- function(value, message) {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}
sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])

score <- read_table("joint_qdesn_shared_backbone_score_summary.csv")
fit <- read_table("joint_qdesn_shared_backbone_fit_interval_summary.csv")
contrast <- read_table("joint_qdesn_shared_backbone_contrast_summary.csv")
crossing <- read_table("joint_qdesn_shared_backbone_crossing_summary.csv")
manifest <- read_table("joint_qdesn_shared_backbone_article_asset_manifest.csv")

model_order <- c(
  "joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb",
  "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"
)
expect(nrow(score) == 32L && nrow(fit) == 32L && nrow(contrast) == 16L,
       "The article projection does not have 32 score cells, 32 fit cells, and 16 contrasts.")
expect(all(table(score$scenario_id) == 4L) &&
         setequal(score$source_model_id, model_order),
       "The score table is not balanced over the four model classes.")
expect(all(is.finite(score$posterior_score_mean)) &&
         all(score$posterior_score_q025 <= score$posterior_score_q975) &&
         all(score$canonical_contract_crossing_pairs == 0L),
       "The score intervals or monotone-contract crossings are invalid.")
expect(all(is.finite(fit$posterior_mean)) &&
         all(fit$posterior_q025 <= fit$posterior_q975) &&
         setequal(fit$n_draws, c(3000L, 4500L)) &&
         all(fit$canonical_contract_crossing_pairs == 0L),
       "The fit intervals or draw allocations are invalid.")
expect(sum(contrast$score_delta_q025 > 0) == 5L &&
         sum(contrast$score_delta_q025 <= 0 & contrast$score_delta_q975 >= 0) == 11L &&
         all(contrast$score_delta_q975 >= 0),
       "The paired contrast interpretation changed.")

forecast_cross <- aggregate(
  raw_crossing_pairs ~ source_model_id,
  crossing[crossing$window == "forecast", , drop = FALSE], sum
)
expected_cross <- c(
  joint_qdesn_rhs_vb = 1426L,
  qdesn_rhs_independent_vb = 4705L,
  joint_exqdesn_rhs_vb = 0L,
  exqdesn_rhs_independent_vb = 281L
)
observed_cross <- forecast_cross$raw_crossing_pairs[
  match(names(expected_cross), forecast_cross$source_model_id)
]
expect(identical(as.integer(observed_cross), unname(expected_cross)),
       "The canonical forecast crossing totals changed.")

expect(nrow(manifest) == 15L && !anyDuplicated(manifest$tracked_path),
       "The article asset manifest is incomplete or duplicated.")
for (ii in seq_len(nrow(manifest))) {
  path <- file.path(repo_root, manifest$tracked_path[[ii]])
  expect(file.exists(path), paste("Missing article asset:", manifest$tracked_path[[ii]]))
  expect(identical(sha256(path), manifest$tracked_sha256[[ii]]),
         paste("Article asset hash mismatch:", manifest$tracked_path[[ii]]))
}
expect(all(manifest$source_score_contract_sha256 ==
  "473c0754c9a1c9a873c4db3b7e61912b57b18c1cac1e146dfd16079185f70600"),
  "The source score-contract hash changed.")
expect(all(manifest$source_execution_commit ==
  "fd48499308d613341274717b53643bece977fb39"),
  "The source execution commit changed.")

main <- paste(readLines(file.path(repo_root, "main.tex"), warn = FALSE), collapse = "\n")
supp <- paste(readLines(file.path(repo_root, "qdesn-supplement.tex"), warn = FALSE), collapse = "\n")
article_files <- readLines(file.path(repo_root, "overleaf", "article_files.txt"), warn = FALSE)
expect(grepl("\\input{tables/joint_qdesn_shared_backbone_forecast_figure.tex}",
             main, fixed = TRUE),
       "The main article does not use the shared-backbone forecast figure.")
expect(grepl("\\input{tables/joint_qdesn_shared_backbone_score_table.tex}",
             supp, fixed = TRUE) &&
         grepl("\\input{tables/joint_qdesn_shared_backbone_fit_figure.tex}",
               supp, fixed = TRUE),
       "The supplement does not use the shared-backbone table and fit figure.")
expect(!grepl("\\input{tables/joint_qdesn_phase181_", main, fixed = TRUE) &&
         !grepl("\\input{tables/joint_qdesn_phase181_", supp, fixed = TRUE),
       "A Phase181 article input remains active.")

required_overleaf <- c(
  "figures/joint_qdesn_simulation/joint_qdesn_shared_backbone_fit_oracle_rmse_intervals.pdf",
  "figures/joint_qdesn_simulation/joint_qdesn_shared_backbone_forecast_dgp_score_intervals.pdf",
  "tables/joint_qdesn_shared_backbone_score_table.tex",
  "tables/joint_qdesn_shared_backbone_contrast_table.tex",
  "tables/joint_qdesn_shared_backbone_crossing_table.tex",
  "tables/joint_qdesn_shared_backbone_oracle_recovery_table.tex",
  "tables/joint_qdesn_shared_backbone_protocol.tex",
  "tables/joint_qdesn_shared_backbone_fit_figure.tex",
  "tables/joint_qdesn_shared_backbone_forecast_figure.tex"
)
expect(all(required_overleaf %in% article_files),
       "The article-only file list is missing shared-backbone assets.")
expect(!any(grepl("joint_qdesn_phase181", article_files, fixed = TRUE)),
       "The article-only file list still publishes Phase181 assets.")

pdfs <- file.path(repo_root, required_overleaf[grepl("[.]pdf$", required_overleaf)])
for (pdf in pdfs) {
  info <- system2("pdfinfo", pdf, stdout = TRUE, stderr = TRUE)
  expect(any(grepl("^Pages:[[:space:]]+1$", info)),
         paste("Expected a one-page vector figure:", pdf))
}

cat(paste0(
  "JOINT_SHARED_BACKBONE_ARTICLE_PROJECTION_CHECK=PASS ",
  "score_cells=32 fit_cells=32 contrasts=16 ",
  "directional_independent=5 overlapping=11\n"
))
