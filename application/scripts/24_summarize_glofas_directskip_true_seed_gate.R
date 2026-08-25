#!/usr/bin/env Rscript
# Purpose: summarize corrected true reservoir-seed GloFAS p50 gate runs.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  runtime_dir = "local_trackers/runtime_configs/glofas_directskip_true_seed_gate_20260610"
))

runtime_dir <- app_path(args$runtime_dir)
manifest <- app_read_csv(file.path(runtime_dir, "launch_manifest.csv"))
sessions <- tryCatch(system("tmux list-sessions 2>/dev/null", intern = TRUE), error = function(e) character())

read_csv_or_null <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(app_read_csv(path), error = function(e) NULL)
}

extract_score <- function(run_id) {
  score <- read_csv_or_null(app_path(file.path("application/runs", run_id, "tables", "score_summary.csv")))
  out <- list(q_check = NA_real_, raw_check = NA_real_)
  if (is.null(score) || !nrow(score)) return(out)
  q_idx <- grepl("qdesn", score$model_id, ignore.case = TRUE)
  r_idx <- grepl("raw_glofas", score$model_id, ignore.case = TRUE)
  if (any(q_idx)) out$q_check <- as.numeric(score$check_loss_mean[which(q_idx)[1L]])
  if (any(r_idx)) out$raw_check <- as.numeric(score$check_loss_mean[which(r_idx)[1L]])
  out
}

extract_fit <- function(run_id) {
  fit <- read_csv_or_null(app_path(file.path("application/runs", run_id, "tables", "fit_status.csv")))
  out <- list(status = NA_character_, runtime_min = NA_real_, message = NA_character_)
  if (is.null(fit) || !nrow(fit)) return(out)
  q_idx <- grepl("qdesn", fit$model_family, ignore.case = TRUE) | grepl("qdesn", fit$fit_id, ignore.case = TRUE)
  row <- fit[if (any(q_idx)) which(q_idx)[1L] else 1L, , drop = FALSE]
  out$status <- as.character(row$status[[1L]])
  out$message <- as.character(row$message[[1L]])
  if ("runtime_seconds" %in% names(row)) out$runtime_min <- as.numeric(row$runtime_seconds[[1L]]) / 60
  out
}

extract_seed_contract <- function(run_id) {
  seed <- read_csv_or_null(app_path(file.path("application/runs", run_id, "manifest", "qdesn_seed_contract.csv")))
  if (is.null(seed) || !nrow(seed)) {
    return(list(effective = NA_integer_, reference = NA_integer_, discrepancy = NA_integer_, status = NA_character_))
  }
  list(
    effective = as.integer(seed$effective_reservoir_seed[[1L]]),
    reference = as.integer(seed$reference_reservoir_seed[[1L]]),
    discrepancy = as.integer(seed$discrepancy_reservoir_seed[[1L]]),
    status = as.character(seed$status[[1L]])
  )
}

rows <- lapply(seq_len(nrow(manifest)), function(i) {
  m <- manifest[i, , drop = FALSE]
  run_id <- m$run_id[[1L]]
  score <- extract_score(run_id)
  fit <- extract_fit(run_id)
  seed <- extract_seed_contract(run_id)
  live <- any(grepl(m$session[[1L]], sessions, fixed = TRUE))
  status <- if (!is.na(score$q_check)) {
    "complete_scored"
  } else if (!is.na(fit$status) && grepl("failed", fit$status, ignore.case = TRUE)) {
    "failed"
  } else if (live) {
    "running"
  } else if (!is.na(fit$status)) {
    "partial_or_unscored"
  } else {
    "not_started_or_pre_fit"
  }
  data.frame(
    candidate_id = m$candidate_id,
    search_role = m$search_role,
    repeat_seed = as.integer(m$repeat_seed),
    status = status,
    run_id = run_id,
    original_q_check = as.numeric(m$original_q_check),
    repeat_q_check = score$q_check,
    delta_repeat_minus_original = score$q_check - as.numeric(m$original_q_check),
    raw_check = score$raw_check,
    runtime_min = fit$runtime_min,
    fit_status = fit$status,
    effective_reservoir_seed = seed$effective,
    reference_reservoir_seed = seed$reference,
    discrepancy_reservoir_seed = seed$discrepancy,
    seed_contract_status = seed$status,
    message = fit$message,
    stringsAsFactors = FALSE
  )
})

summary <- app_bind_rows_fill(rows)
summary <- summary[order(is.na(summary$repeat_q_check), summary$repeat_q_check, summary$candidate_id), , drop = FALSE]
app_write_csv(summary, file.path(runtime_dir, "true_seed_gate_summary.csv"))

lines <- c(
  "# GloFAS Corrected True-Seed Gate Summary",
  "",
  sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "## Status",
  "",
  paste(capture.output(print(table(summary$status, useNA = "ifany"))), collapse = "\n"),
  "",
  "## Decision Rule",
  "",
  "- Rank candidates by repeat p50 check loss only after all required runs are complete.",
  "- Prefer the candidate with the best stable original/repeat profile, not a one-seed outlier.",
  "- Do not launch full-seven quantiles until this table and the forecast figures are audited.",
  "",
  "## Summary Table",
  "",
  paste(capture.output(print(summary, row.names = FALSE)), collapse = "\n")
)
writeLines(lines, file.path(runtime_dir, "true_seed_gate_summary.md"))
cat(file.path(args$runtime_dir, "true_seed_gate_summary.csv"), "\n")
