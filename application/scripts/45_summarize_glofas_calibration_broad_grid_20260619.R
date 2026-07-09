#!/usr/bin/env Rscript
# Purpose: summarize the GloFAS calibration/broad-grid runtime package.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

repo_rel <- function(path) app_prefer_repo_relative_path(path)

args <- app_parse_args(list(
  runtime_dir = "local_trackers/runtime_configs/glofas_calibration_broad_grid_20260619",
  stage = "stage_a",
  baseline_score = "tables/glofas_application_current_score_summary.csv"
))

manifest_path <- app_path(args$runtime_dir, sprintf("%s_scheduler_manifest.csv", args$stage))
if (!file.exists(manifest_path)) {
  stop(sprintf("Missing scheduler manifest: %s", manifest_path), call. = FALSE)
}

manifest <- app_read_csv(manifest_path)
baseline <- app_read_csv(app_path(args$baseline_score), required = FALSE)
baseline_qdesn <- baseline[baseline$model_label == "Q--DESN calibration", , drop = FALSE]
baseline_check_loss <- if (nrow(baseline_qdesn)) as.numeric(baseline_qdesn$check_loss_mean[[1L]]) else NA_real_
baseline_crps <- if (nrow(baseline_qdesn)) as.numeric(baseline_qdesn$crps_quantile_grid_mean[[1L]]) else NA_real_

component_rows <- lapply(seq_len(nrow(manifest)), function(i) {
  row <- manifest[i, , drop = FALSE]
  run_dir <- app_path(row$run_dir[[1L]])
  fit_path <- file.path(run_dir, "tables", "fit_status.csv")
  score_path <- file.path(run_dir, "tables", "score_summary.csv")
  pred_path <- file.path(run_dir, "tables", "prediction_quantiles.csv")
  log_path <- app_path(row$log_path[[1L]])
  status <- "not_started"
  fit_status <- NA_character_
  qdesn_check_loss <- NA_real_
  raw_check_loss <- NA_real_
  if (file.exists(fit_path)) {
    fit <- app_read_csv(fit_path)
    if (nrow(fit) && "status" %in% names(fit)) {
      fit_status <- paste(unique(fit$status), collapse = ";")
      status <- if (any(tolower(fit$status) == "failed")) "failed" else if (file.exists(pred_path)) "completed" else "fit_done_no_predictions"
    }
  } else if (file.exists(log_path)) {
    status <- "running_or_failed_before_status"
  }
  if (file.exists(score_path)) {
    score <- app_read_csv(score_path)
    qrow <- score[score$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
    rrow <- score[score$model_family == "raw_glofas", , drop = FALSE]
    if (nrow(qrow) && "check_loss_mean" %in% names(qrow)) qdesn_check_loss <- as.numeric(qrow$check_loss_mean[[1L]])
    if (nrow(rrow) && "check_loss_mean" %in% names(rrow)) raw_check_loss <- as.numeric(rrow$check_loss_mean[[1L]])
  }
  data.frame(
    candidate_id = row$candidate_id,
    stage = row$stage,
    quantile_id = row$quantile_id,
    quantile_level = as.numeric(row$quantile_level),
    status = status,
    fit_status = fit_status,
    qdesn_check_loss = qdesn_check_loss,
    raw_check_loss = raw_check_loss,
    run_dir = row$run_dir,
    stringsAsFactors = FALSE
  )
})
components <- app_bind_rows_fill(component_rows)

candidate_rows <- lapply(split(components, components$candidate_id), function(x) {
  done <- x$status == "completed"
  failed <- x$status == "failed"
  data.frame(
    candidate_id = x$candidate_id[[1L]],
    n_components = nrow(x),
    completed = sum(done),
    failed = sum(failed),
    not_done = sum(!done & !failed),
    mean_qdesn_check_loss = if (any(done)) mean(x$qdesn_check_loss[done], na.rm = TRUE) else NA_real_,
    mean_raw_check_loss = if (any(done)) mean(x$raw_check_loss[done], na.rm = TRUE) else NA_real_,
    delta_vs_current_full7_check_loss = if (any(done) && is.finite(baseline_check_loss)) mean(x$qdesn_check_loss[done], na.rm = TRUE) - baseline_check_loss else NA_real_,
    stringsAsFactors = FALSE
  )
})
candidates <- app_bind_rows_fill(candidate_rows)
candidates <- candidates[order(candidates$failed, candidates$not_done, candidates$mean_qdesn_check_loss), , drop = FALSE]

out_dir <- app_path(args$runtime_dir)
app_write_csv(components, file.path(out_dir, sprintf("%s_component_health_latest.csv", args$stage)))
app_write_csv(candidates, file.path(out_dir, sprintf("%s_candidate_health_latest.csv", args$stage)))

cat(sprintf("runtime_dir=%s\n", args$runtime_dir))
cat(sprintf("stage=%s\n", args$stage))
cat(sprintf("components=%d completed=%d failed=%d not_done=%d\n",
            nrow(components),
            sum(components$status == "completed"),
            sum(components$status == "failed"),
            sum(!components$status %in% c("completed", "failed"))))
cat("candidate summary:\n")
print(candidates, row.names = FALSE)
cat(sprintf("wrote=%s\n", repo_rel(file.path(out_dir, sprintf("%s_candidate_health_latest.csv", args$stage)))))
