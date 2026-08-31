#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
repo_root <- normalizePath(if (length(args)) args[[1L]] else ".", mustWork = TRUE)
table_dir <- file.path(repo_root, "tables")

expected_source_hashes <- c(
  joint_qdesn_phase181_article_scenario_model_summary.csv =
    "1fd2078f86c5c2c4daa902971bf9af713b3304bc84566229ba99a96aefd44ca7",
  joint_qdesn_phase181_numerical_winner_summary.csv =
    "22918ed621ae7288855f4d742a91faac8068663490fcfa7b70889977542e909e",
  joint_qdesn_phase181_mean_metric_promotion_decisions.csv =
    "ccb931c10d46cf96249ac187c6efc3aa29671ce9d6b806e7a2250a92c9bcdd02",
  joint_qdesn_phase181_joint_independent_contrast_summary.csv =
    "4dfe83932d90d1a9a62b7f822c0d377c7ef6b18612a252080630311ecaaf63af",
  joint_qdesn_phase181_supplemental_diagnostics.csv =
    "11b9e3d2044b7b3f57309ae74976a1df870c25dedb5ef19c84648f9441f96e17",
  joint_qdesn_phase181_crossing_provenance.csv =
    "893afccac5dbba192c4cebe9cb85e7db8c889e492ec60e61d413cf6796ff759b",
  joint_qdesn_phase181_manuscript_wording_guidance.csv =
    "b09ebdb86794b4abccd5b0048c6bb2373ccb762ceb369b4794c49c91e3a7d6da"
)

sha256 <- function(path) {
  output <- system2("sha256sum", shQuote(path), stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if (!is.null(status) && status != 0L) stop("sha256sum failed for ", path)
  strsplit(output[[1L]], "[[:space:]]+")[[1L]][[1L]]
}

for (name in names(expected_source_hashes)) {
  path <- file.path(table_dir, name)
  if (!file.exists(path)) stop("Missing tracked Phase181 source asset: ", name)
  actual <- sha256(path)
  if (!identical(actual, unname(expected_source_hashes[[name]]))) {
    stop("Source hash mismatch for ", name, ": ", actual)
  }
}

summary <- read.csv(
  file.path(table_dir, "joint_qdesn_phase181_article_scenario_model_summary.csv"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)
contrasts <- read.csv(
  file.path(table_dir, "joint_qdesn_phase181_joint_independent_contrast_summary.csv"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)
crossings <- read.csv(
  file.path(table_dir, "joint_qdesn_phase181_crossing_provenance.csv"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

stopifnot(
  nrow(summary) == 32L,
  length(unique(summary$scenario_id)) == 8L,
  all(table(summary$scenario_id) == 4L),
  sum(summary$numerical_winner) == 8L,
  all(is.finite(summary$posterior_score_mean)),
  all(is.finite(summary$posterior_score_q025)),
  all(is.finite(summary$posterior_score_q975)),
  all(summary$posterior_score_q025 <= summary$posterior_score_q975),
  all(summary$canonical_contract_crossing_pairs == 0L),
  nrow(contrasts) == 16L,
  all(contrasts$score_delta_q025 <= 0),
  all(contrasts$score_delta_q975 >= 0)
)

forecast_crossings <- crossings[crossings$window == "forecast", , drop = FALSE]
mapping <- unique(summary[c("case_id", "source_model_id")])
forecast_crossings <- merge(
  forecast_crossings, mapping, by = "case_id", all.x = TRUE, sort = FALSE
)
crossing_totals <- aggregate(
  cbind(raw_crossing_pairs, contract_crossing_pairs) ~ source_model_id,
  forecast_crossings,
  sum
)
expected_raw <- c(
  joint_qdesn_rhs_vb = 1,
  qdesn_rhs_independent_vb = 25,
  joint_exqdesn_rhs_vb = 0,
  exqdesn_rhs_independent_vb = 0
)
actual_raw <- setNames(crossing_totals$raw_crossing_pairs, crossing_totals$source_model_id)
draw_rate_summary <- aggregate(
  raw_crossing_rate ~ source_model_id,
  data = summary,
  FUN = mean
)
actual_draw_rates <- setNames(
  draw_rate_summary$raw_crossing_rate,
  draw_rate_summary$source_model_id
)
expected_draw_rates <- c(
  joint_qdesn_rhs_vb = 0.0035375184,
  qdesn_rhs_independent_vb = 0.0142383628,
  joint_exqdesn_rhs_vb = 0.0150205045,
  exqdesn_rhs_independent_vb = 0.0337331650
)
stopifnot(
  identical(as.numeric(actual_raw[names(expected_raw)]), as.numeric(expected_raw)),
  isTRUE(all.equal(
    as.numeric(actual_draw_rates[names(expected_draw_rates)]),
    as.numeric(expected_draw_rates),
    tolerance = 1e-9
  )),
  all(crossing_totals$contract_crossing_pairs == 0L)
)

generated <- c(
  "joint_qdesn_phase181_dgp_integrated_score_table.tex",
  "joint_qdesn_phase181_joint_independent_contrast_table.tex",
  "joint_qdesn_phase181_crossing_summary.tex",
  "joint_qdesn_phase181_oracle_recovery_table.tex"
)
for (name in generated) {
  path <- file.path(table_dir, name)
  if (!file.exists(path)) stop("Missing generated article table: ", name)
  text <- paste(readLines(path, warn = FALSE), collapse = "\n")
  forbidden <- c(
    "Phase18", "source replaces", "hard-gate", "contract",
    "Grid CRPS", "forecast MAE"
  )
  hits <- forbidden[vapply(forbidden, grepl, logical(1), x = text, fixed = TRUE)]
  if (length(hits)) {
    stop("Internal or stale wording in ", name, ": ", paste(hits, collapse = ", "))
  }
}

main <- paste(readLines(file.path(repo_root, "main.tex"), warn = FALSE), collapse = "\n")
supp <- paste(
  readLines(file.path(repo_root, "qdesn-supplement.tex"), warn = FALSE),
  collapse = "\n"
)
supp_joint_tables <- paste(
  readLines(
    file.path(table_dir, "joint_qdesn_article_validation_provenance_tables.tex"),
    warn = FALSE
  ),
  collapse = "\n"
)
stopifnot(
  grepl(
    "\\input{tables/joint_qdesn_phase181_dgp_integrated_score_table.tex}",
    main,
    fixed = TRUE
  ),
  grepl(
    "\\input{tables/joint_qdesn_phase181_joint_independent_contrast_table.tex}",
    supp_joint_tables,
    fixed = TRUE
  ),
  grepl(
    "\\input{tables/joint_qdesn_phase181_crossing_summary.tex}",
    supp_joint_tables,
    fixed = TRUE
  ),
  grepl(
    "\\input{tables/joint_qdesn_phase181_oracle_recovery_table.tex}",
    supp_joint_tables,
    fixed = TRUE
  ),
  !grepl(
    "\\input{tables/joint_qdesn_article_validation_mcmc_balanced_model_summary.tex}",
    main,
    fixed = TRUE
  ),
  !grepl("24 of the 25", main, fixed = TRUE),
  !grepl("Grid CRPS", main, fixed = TRUE),
  !grepl("Grid CRPS", supp, fixed = TRUE),
  grepl(
    "\\input{tables/joint_qdesn_article_validation_provenance_tables.tex}",
    supp,
    fixed = TRUE
  )
)

manifest <- read.csv(
  file.path(table_dir, "joint_qdesn_phase181_article_asset_manifest.csv"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)
stopifnot(
  nrow(manifest) == 11L,
  all(c(
    "artifact_id", "tracked_path", "source_sha256", "tracked_sha256",
    "source_commit", "scientific_closeout_commit", "integration_source_commit",
    "derivation_note"
  ) %in% names(manifest))
)
contrast_manifest <- manifest[
  manifest$artifact_id == "joint_independent_contrasts",
  ,
  drop = FALSE
]
stopifnot(
  nrow(contrast_manifest) == 1L,
  grepl("contrast_pairing_seed", contrast_manifest$derivation_note, fixed = TRUE),
  file.exists(file.path(
    repo_root,
    "docs/implementation_notes/joint_qdesn_phase181_contrast_seed_integration_repair_20260831.md"
  ))
)
for (i in seq_len(nrow(manifest))) {
  path <- file.path(repo_root, manifest$tracked_path[[i]])
  if (!file.exists(path)) stop("Manifest path is missing: ", manifest$tracked_path[[i]])
  if (!identical(sha256(path), manifest$tracked_sha256[[i]])) {
    stop("Tracked projection hash mismatch: ", manifest$tracked_path[[i]])
  }
}

cat(
  "JOINT_QDESN_PHASE181_ARTICLE_CHECK=PASS",
  "rows=32 contrasts=16 raw_crossings=1,25,0,0\n"
)
