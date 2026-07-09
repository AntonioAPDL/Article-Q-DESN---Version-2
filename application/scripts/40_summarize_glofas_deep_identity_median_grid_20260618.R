#!/usr/bin/env Rscript
# Purpose: close out the completed GloFAS deep-identity median grid with a
# durable ranking table and compact summaries. This script is read-only with
# respect to fit artifacts; it only writes summary CSV/Markdown files under the
# local runtime directory.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  runtime_dir = "local_trackers/runtime_configs/glofas_deep_identity_median_grid_20260617",
  c03_reference = "0.708783078980146",
  raw_reference = "0.875378727598426"
))

runtime_dir <- app_path(args$runtime_dir)
manifest_path <- file.path(runtime_dir, "launch_manifest.csv")
scheduler_path <- file.path(runtime_dir, "scheduler_status.csv")
if (!file.exists(manifest_path)) stop(sprintf("Missing launch manifest: %s", manifest_path), call. = FALSE)
if (!file.exists(scheduler_path)) stop(sprintf("Missing scheduler status: %s", scheduler_path), call. = FALSE)

c03_reference <- as.numeric(args$c03_reference)
raw_reference <- as.numeric(args$raw_reference)

num_or_na <- function(x) suppressWarnings(as.numeric(x))
read_optional <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(app_read_csv(path), error = function(e) NULL)
}

parse_candidate <- function(candidate_id) {
  out <- data.frame(
    D = NA_integer_,
    width = NA_integer_,
    reservoir_m = NA_integer_,
    max_iter = NA_integer_,
    alpha = NA_real_,
    stringsAsFactors = FALSE
  )
  hit <- regexec("(?:deepid|local_search|confirm_primary|confirm_clean_backup|confirm_stable_comparator)_d([0-9]+)_w([0-9]+)_m([0-9]+)_a([0-9]+)_r95.*(?:max([0-9]+))?", candidate_id)
  m <- regmatches(candidate_id, hit)[[1L]]
  if (length(m) >= 5L) {
    out$D <- as.integer(m[[2L]])
    out$width <- as.integer(m[[3L]])
    out$reservoir_m <- as.integer(m[[4L]])
    out$alpha <- as.numeric(m[[5L]]) / 1000
    if (length(m) >= 6L && nzchar(m[[6L]])) {
      out$max_iter <- as.integer(m[[6L]])
    }
  }
  out
}

score_from_run <- function(row) {
  run_dir <- app_path(file.path("application/runs", row$run_id[[1L]]))
  score_path <- file.path(run_dir, "tables", "score_summary.csv")
  diag_path <- file.path(run_dir, "tables", "qdesn_discrepancy_fit_diagnostics.csv")
  fit_path <- file.path(run_dir, "tables", "fit_status.csv")
  fig_manifest_path <- file.path(run_dir, "tables", "figure_manifest.csv")

  score <- read_optional(score_path)
  diag <- read_optional(diag_path)
  fit <- read_optional(fit_path)
  qdesn_score <- data.frame()
  raw_score <- data.frame()
  if (!is.null(score) && nrow(score) && "model_id" %in% names(score)) {
    qdesn_score <- score[grepl("^qdesn", as.character(score$model_id)), , drop = FALSE]
    raw_score <- score[grepl("^raw_glofas", as.character(score$model_id)), , drop = FALSE]
  }
  qdiag <- if (!is.null(diag) && nrow(diag)) diag[1L, , drop = FALSE] else data.frame()
  qfit <- data.frame()
  if (!is.null(fit) && nrow(fit) && "model_id" %in% names(fit)) {
    qfit <- fit[grepl("^qdesn", as.character(fit$model_id)), , drop = FALSE]
  }
  parsed <- parse_candidate(row$candidate_id[[1L]])
  candidate_name <- if ("candidate_name" %in% names(row) && length(row$candidate_name)) {
    as.character(row$candidate_name[[1L]])
  } else {
    as.character(row$candidate_id[[1L]])
  }
  q_loss <- if (nrow(qdesn_score) && "check_loss_mean" %in% names(qdesn_score)) num_or_na(qdesn_score$check_loss_mean[[1L]]) else NA_real_
  raw_loss <- if (nrow(raw_score) && "check_loss_mean" %in% names(raw_score)) num_or_na(raw_score$check_loss_mean[[1L]]) else NA_real_
  data.frame(
    run_index = as.integer(row$run_index[[1L]]),
    candidate_id = as.character(row$candidate_id[[1L]]),
    candidate_name = candidate_name,
    run_id = as.character(row$run_id[[1L]]),
    parsed,
    scheduler_status = as.character(row$status[[1L]]),
    returncode = as.character(row$returncode[[1L]]),
    elapsed_sec = num_or_na(row$elapsed_sec[[1L]]),
    qdesn_check_loss = q_loss,
    raw_check_loss = raw_loss,
    delta_vs_c03 = q_loss - c03_reference,
    pct_vs_c03 = 100 * (q_loss / c03_reference - 1),
    delta_vs_raw = q_loss - raw_reference,
    pct_vs_raw = 100 * (q_loss / raw_reference - 1),
    vb_converged = if (nrow(qdiag) && "vb_converged" %in% names(qdiag)) as.character(qdiag$vb_converged[[1L]]) else NA_character_,
    vb_iterations = if (nrow(qdiag) && "vb_iterations" %in% names(qdiag)) as.integer(qdiag$vb_iterations[[1L]]) else NA_integer_,
    vb_max_parameter_change = if (nrow(qdiag) && "vb_max_parameter_change" %in% names(qdiag)) num_or_na(qdiag$vb_max_parameter_change[[1L]]) else NA_real_,
    beta_norm_mean = if (nrow(qdiag) && "beta_norm_mean" %in% names(qdiag)) num_or_na(qdiag$beta_norm_mean[[1L]]) else NA_real_,
    alpha_norm_mean = if (nrow(qdiag) && "alpha_norm_mean" %in% names(qdiag)) num_or_na(qdiag$alpha_norm_mean[[1L]]) else NA_real_,
    sigma_Y_mean = if (nrow(qdiag) && "sigma_Y_mean" %in% names(qdiag)) num_or_na(qdiag$sigma_Y_mean[[1L]]) else NA_real_,
    sigma_G_mean = if (nrow(qdiag) && "sigma_G_mean" %in% names(qdiag)) num_or_na(qdiag$sigma_G_mean[[1L]]) else NA_real_,
    fit_status = if (nrow(qfit) && "status" %in% names(qfit)) as.character(qfit$status[[1L]]) else NA_character_,
    score_summary_exists = file.exists(score_path),
    diagnostics_exists = file.exists(diag_path),
    fit_status_exists = file.exists(fit_path),
    figure_manifest_exists = file.exists(fig_manifest_path),
    run_dir = normalizePath(run_dir, mustWork = FALSE),
    stringsAsFactors = FALSE
  )
}

scheduler <- app_read_csv(scheduler_path)
ranking <- app_bind_rows_fill(lapply(seq_len(nrow(scheduler)), function(i) score_from_run(scheduler[i, , drop = FALSE])))
ranking <- ranking[order(ranking$qdesn_check_loss, ranking$run_index, na.last = TRUE), , drop = FALSE]
ranking$rank <- seq_len(nrow(ranking))
ranking <- ranking[, c("rank", setdiff(names(ranking), "rank")), drop = FALSE]

app_write_csv(ranking, file.path(runtime_dir, "final_score_ranking.csv"))
app_write_csv(ranking[ranking$qdesn_check_loss < c03_reference, , drop = FALSE], file.path(runtime_dir, "final_winners_vs_c03.csv"))

summarize_group <- function(x, group_name) {
  split_x <- split(x, x[[group_name]])
  out <- lapply(names(split_x), function(g) {
    block <- split_x[[g]]
    block <- block[is.finite(block$qdesn_check_loss), , drop = FALSE]
    if (!nrow(block)) return(NULL)
    best <- block[which.min(block$qdesn_check_loss), , drop = FALSE]
    data.frame(
      group = group_name,
      value = g,
      n = nrow(block),
      best_check_loss = best$qdesn_check_loss[[1L]],
      median_check_loss = stats::median(block$qdesn_check_loss, na.rm = TRUE),
      mean_check_loss = mean(block$qdesn_check_loss, na.rm = TRUE),
      winners_vs_c03 = sum(block$qdesn_check_loss < c03_reference, na.rm = TRUE),
      winners_vs_raw = sum(block$qdesn_check_loss < raw_reference, na.rm = TRUE),
      strict_vb_converged = sum(toupper(as.character(block$vb_converged)) == "TRUE", na.rm = TRUE),
      best_candidate_id = best$candidate_id[[1L]],
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(out)
}

summary_tables <- app_bind_rows_fill(list(
  summarize_group(ranking, "D"),
  summarize_group(ranking, "width"),
  summarize_group(ranking, "reservoir_m"),
  summarize_group(ranking, "alpha")
))
app_write_csv(summary_tables, file.path(runtime_dir, "final_factor_summaries.csv"))

quality <- data.frame(
  check = c(
    "scheduler_rows",
    "scheduler_all_complete",
    "score_rows_present",
    "diagnostics_present",
    "fit_status_present",
    "figure_manifest_present",
    "nonzero_returncodes"
  ),
  value = c(
    nrow(scheduler),
    sum(scheduler$status == "complete", na.rm = TRUE),
    sum(ranking$score_summary_exists, na.rm = TRUE),
    sum(ranking$diagnostics_exists, na.rm = TRUE),
    sum(ranking$fit_status_exists, na.rm = TRUE),
    sum(ranking$figure_manifest_exists, na.rm = TRUE),
    sum(!(is.na(scheduler$returncode) | as.character(scheduler$returncode) %in% c("0", "0.0", "")), na.rm = TRUE)
  ),
  expected = c(nrow(scheduler), nrow(scheduler), nrow(scheduler), nrow(scheduler), nrow(scheduler), nrow(scheduler), 0),
  stringsAsFactors = FALSE
)
quality$passed <- quality$value == quality$expected
app_write_csv(quality, file.path(runtime_dir, "final_closeout_quality.csv"))

top <- head(ranking, 10L)
md <- c(
  sprintf("# Final Closeout: %s", basename(runtime_dir)),
  "",
  sprintf("- Completed scheduler rows: `%d/%d`", sum(scheduler$status == "complete"), nrow(scheduler)),
  sprintf("- Score rows present: `%d/%d`", sum(ranking$score_summary_exists), nrow(ranking)),
  sprintf("- Nonzero return codes: `%d`", quality$value[quality$check == "nonzero_returncodes"]),
  sprintf("- c03 reference p50 check loss: `%.12f`", c03_reference),
  sprintf("- raw GloFAS p50 check loss: `%.12f`", raw_reference),
  "",
  "## Top Candidates",
  "",
  "| Rank | Candidate | Check loss | vs c03 | VB strict | max parameter change |",
  "|---:|---|---:|---:|---|---:|",
  apply(top, 1L, function(r) {
    sprintf(
      "| %s | `%s` | %.6f | %.1f%% | %s | %.6g |",
      r[["rank"]],
      r[["candidate_id"]],
      as.numeric(r[["qdesn_check_loss"]]),
      as.numeric(r[["pct_vs_c03"]]),
      r[["vb_converged"]],
      as.numeric(r[["vb_max_parameter_change"]])
    )
  }),
  "",
  "## Required Next Step",
  "",
  "Run post-fit diagnostics for the primary winner and clean-convergence backup before any full-seven quantile launch."
)
writeLines(md, file.path(runtime_dir, "final_closeout_summary.md"))

cat("\nDeep-identity median grid closeout\n")
print(quality, row.names = FALSE)
cat("\nTop 10\n")
print(top[, c("rank", "candidate_id", "qdesn_check_loss", "pct_vs_c03", "vb_converged", "vb_max_parameter_change"), drop = FALSE], row.names = FALSE)
cat("\nWrote:\n")
cat(file.path(args$runtime_dir, "final_score_ranking.csv"), "\n")
cat(file.path(args$runtime_dir, "final_factor_summaries.csv"), "\n")
cat(file.path(args$runtime_dir, "final_closeout_summary.md"), "\n")
