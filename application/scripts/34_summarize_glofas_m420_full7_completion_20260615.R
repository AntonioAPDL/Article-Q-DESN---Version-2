#!/usr/bin/env Rscript
# Purpose: summarize health and scoring for the GloFAS m420 full-seven
# completion package prepared by script 33.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  runtime_dir = "local_trackers/runtime_configs/glofas_m420_full7_completion_20260615",
  batch_id = "glofas_m420_full7_completion_20260615",
  baseline_run_id = "glofas_reservoir_only_m360_full7_20260607_synthesis_final"
))

runtime_dir <- app_path(args$runtime_dir)
manifest_path <- file.path(runtime_dir, "synthesis_source_manifest.csv")
if (!file.exists(manifest_path)) stop(sprintf("Missing synthesis source manifest: %s", manifest_path), call. = FALSE)
manifest <- app_read_csv(manifest_path)

tmux_sessions <- tryCatch(system("tmux ls 2>/dev/null", intern = TRUE), error = function(e) character())
ps_lines <- tryCatch(system("ps -u \"$USER\" -o pid,psr,pcpu,pmem,etime,cmd", intern = TRUE), error = function(e) character())

read_optional <- function(path) {
  if (file.exists(path)) app_read_csv(path) else data.frame()
}

get_score <- function(score_path, model_id) {
  score <- read_optional(score_path)
  if (!nrow(score) || !"model_id" %in% names(score)) return(NA_real_)
  idx <- which(score$model_id == model_id)
  if (!length(idx)) return(NA_real_)
  as.numeric(score$check_loss_mean[[idx[[1L]]]])
}

status_rows <- vector("list", nrow(manifest))
for (i in seq_len(nrow(manifest))) {
  row <- manifest[i, , drop = FALSE]
  run_dir <- if (grepl("^/", row$run_dir[[1L]])) row$run_dir[[1L]] else app_path(row$run_dir[[1L]])
  tables_dir <- file.path(run_dir, "tables")
  fit_status_path <- file.path(tables_dir, "fit_status.csv")
  pred_path <- file.path(tables_dir, "prediction_quantiles.csv")
  score_path <- file.path(tables_dir, "score_summary.csv")
  fit_status <- read_optional(fit_status_path)
  fit_complete <- FALSE
  fit_runtime_min <- NA_real_
  message <- NA_character_
  if (nrow(fit_status)) {
    ids <- c(row$raw_fit_id[[1L]], row$qdesn_fit_id[[1L]])
    rows <- fit_status[fit_status$fit_id %in% ids, , drop = FALSE]
    fit_complete <- nrow(rows) == length(ids) && all(as.character(rows$status) == "completed")
    qrows <- rows[rows$fit_id == row$qdesn_fit_id[[1L]], , drop = FALSE]
    if (nrow(qrows) && "runtime_seconds" %in% names(qrows)) fit_runtime_min <- as.numeric(qrows$runtime_seconds[[1L]]) / 60
    if (nrow(qrows) && "message" %in% names(qrows)) message <- as.character(qrows$message[[1L]])
  }
  session <- sprintf("%s_%s", args$batch_id, as.character(row$quantile_id[[1L]]))
  live <- any(grepl(session, tmux_sessions, fixed = TRUE)) ||
    any(grepl(row$run_id[[1L]], ps_lines, fixed = TRUE))
  status <- if (fit_complete && file.exists(score_path)) {
    "complete_scored"
  } else if (fit_complete) {
    "complete_unscored"
  } else if (live) {
    "running"
  } else if (as.character(row$source_kind[[1L]]) == "new_completion_run") {
    "pending_or_failed"
  } else {
    "missing_reused_source"
  }
  status_rows[[i]] <- data.frame(
    run_index = as.integer(row$run_index[[1L]]),
    quantile_id = as.character(row$quantile_id[[1L]]),
    quantile_level = as.numeric(row$quantile_level[[1L]]),
    role = as.character(row$role[[1L]]),
    source_kind = as.character(row$source_kind[[1L]]),
    run_id = as.character(row$run_id[[1L]]),
    live = live,
    status = status,
    fit_runtime_min = fit_runtime_min,
    prediction_table_exists = file.exists(pred_path),
    qdesn_check_loss = get_score(score_path, row$qdesn_model_id[[1L]]),
    raw_check_loss = get_score(score_path, row$raw_model_id[[1L]]),
    message = message,
    stringsAsFactors = FALSE
  )
}

health <- do.call(rbind, status_rows)
health <- health[order(health$run_index), , drop = FALSE]
health$relative_improvement <- (health$raw_check_loss - health$qdesn_check_loss) / health$raw_check_loss
app_write_csv(health, file.path(runtime_dir, "health_check_latest.csv"))

synth_run <- file.path(app_path("application/runs"), paste0(args$batch_id, "_synthesis_final"))
baseline_run <- file.path(app_path("application/runs"), args$baseline_run_id)
synth_score_path <- file.path(synth_run, "tables", "score_summary.csv")
baseline_score_path <- file.path(baseline_run, "tables", "score_summary.csv")
synth_diag_path <- file.path(synth_run, "tables", "quantile_synthesis_diagnostic_summary.csv")
baseline_diag_path <- file.path(baseline_run, "tables", "quantile_synthesis_diagnostic_summary.csv")

comparison <- data.frame()
if (file.exists(synth_score_path) && file.exists(baseline_score_path)) {
  read_score_one <- function(path, label) {
    x <- app_read_csv(path)
    q <- x[grepl("^qdesn_", x$model_id), , drop = FALSE][1L, , drop = FALSE]
    r <- x[grepl("^raw_glofas", x$model_id), , drop = FALSE][1L, , drop = FALSE]
    data.frame(
      run_label = label,
      qdesn_check_loss = as.numeric(q$check_loss_mean[[1L]]),
      raw_check_loss = as.numeric(r$check_loss_mean[[1L]]),
      qdesn_crps = as.numeric(q$crps_quantile_grid_mean[[1L]]),
      raw_crps = as.numeric(r$crps_quantile_grid_mean[[1L]]),
      qdesn_interval_score = as.numeric(q$interval_score_mean[[1L]]),
      qdesn_interval_coverage = as.numeric(q$interval_coverage_mean[[1L]]),
      stringsAsFactors = FALSE
    )
  }
  comparison <- rbind(
    read_score_one(baseline_score_path, "m360_current_baseline"),
    read_score_one(synth_score_path, "m420_candidate")
  )
  comparison$delta_check_vs_baseline <- comparison$qdesn_check_loss - comparison$qdesn_check_loss[comparison$run_label == "m360_current_baseline"]
  comparison$delta_crps_vs_baseline <- comparison$qdesn_crps - comparison$qdesn_crps[comparison$run_label == "m360_current_baseline"]
  app_write_csv(comparison, file.path(runtime_dir, "synthesis_vs_baseline_latest.csv"))
}

cat("\nGloFAS m420 full-seven completion health\n")
print(health[, c(
  "quantile_id", "source_kind", "status", "live", "fit_runtime_min",
  "qdesn_check_loss", "raw_check_loss", "relative_improvement"
)], row.names = FALSE)

cat("\nStatus counts\n")
print(table(health$status, useNA = "ifany"))

if (file.exists(synth_score_path)) {
  cat("\nSynthesis score\n")
  print(app_read_csv(synth_score_path), row.names = FALSE)
  if (file.exists(synth_diag_path)) {
    cat("\nSynthesis crossing diagnostics\n")
    print(app_read_csv(synth_diag_path), row.names = FALSE)
  }
  if (nrow(comparison)) {
    cat("\nComparison to current m360 baseline\n")
    print(comparison, row.names = FALSE)
  }
} else {
  cat("\nSynthesis unavailable: waiting for all component sources and watcher/manual synthesis.\n")
}

cat("\nWrote:\n")
cat(file.path(args$runtime_dir, "health_check_latest.csv"), "\n")
if (nrow(comparison)) cat(file.path(args$runtime_dir, "synthesis_vs_baseline_latest.csv"), "\n")
