#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- if (!is.na(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))

args <- app_parse_args(list(
  fit_dir = "application/cache/joint_qdesn_simulation_vb_fit_validation_article_20260706",
  forecast_dir = "application/cache/joint_qdesn_simulation_vb_forecast_validation_article_20260706",
  output_dir = "application/cache/joint_qdesn_simulation_post_vb_validation_audit_20260706"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

resolve_repo_path <- function(path, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

write_csv <- function(x, path) {
  app_ensure_dir(dirname(path))
  utils::write.csv(x, path, row.names = FALSE, na = "")
  normalizePath(path, mustWork = TRUE)
}

bind_rows <- function(rows) app_bind_rows_fill(rows)

verify_manifest <- function(dir, stage) {
  manifest_path <- file.path(dir, "artifact_manifest.csv")
  if (!file.exists(manifest_path)) {
    return(data.frame(
      stage = stage,
      label = "artifact_manifest",
      relative_path = "artifact_manifest.csv",
      path = manifest_path,
      exists = FALSE,
      declared_sha256 = NA_character_,
      actual_sha256 = NA_character_,
      declared_size_bytes = NA_real_,
      actual_size_bytes = NA_real_,
      status = "fail",
      stringsAsFactors = FALSE
    ))
  }
  manifest <- app_read_csv(manifest_path)
  app_check_required_columns(manifest, c("label", "relative_path", "size_bytes", "sha256"), sprintf("%s artifact manifest", stage))
  bind_rows(lapply(seq_len(nrow(manifest)), function(ii) {
    p <- file.path(dir, manifest$relative_path[[ii]])
    exists <- file.exists(p)
    actual_sha <- if (exists) app_sha256_file(p) else NA_character_
    actual_size <- if (exists) as.numeric(file.info(p)$size) else NA_real_
    data.frame(
      stage = stage,
      label = manifest$label[[ii]],
      relative_path = manifest$relative_path[[ii]],
      path = normalizePath(p, mustWork = FALSE),
      exists = exists,
      declared_sha256 = manifest$sha256[[ii]],
      actual_sha256 = actual_sha,
      declared_size_bytes = as.numeric(manifest$size_bytes[[ii]]),
      actual_size_bytes = actual_size,
      status = if (exists && identical(tolower(actual_sha), tolower(manifest$sha256[[ii]]))) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  }))
}

summarise_stage <- function(dir, stage) {
  assessment_file <- if (stage == "fit") "fit_validation_assessment.csv" else "forecast_validation_assessment.csv"
  quantile_file <- if (stage == "fit") "fit_quantiles.csv" else "forecast_quantiles.csv"
  manifest_check <- verify_manifest(dir, stage)
  assessment <- app_read_csv(file.path(dir, assessment_file))
  q <- app_read_csv(file.path(dir, quantile_file))
  vb <- app_read_csv(file.path(dir, "vb_convergence_audit.csv"))
  data.frame(
    stage = stage,
    artifact_dir = dir,
    artifact_manifest_status = if (all(manifest_check$status == "pass")) "pass" else "fail",
    artifact_files = nrow(manifest_check),
    artifact_size_mb = round(sum(manifest_check$actual_size_bytes, na.rm = TRUE) / 1024^2, 3),
    n_assessment_rows = nrow(assessment),
    n_quantile_rows = nrow(q),
    pass_rows = sum(assessment$gate_status == "pass"),
    review_rows = sum(assessment$gate_status == "review"),
    fail_rows = sum(assessment$gate_status == "fail"),
    contract_crossing_pairs = sum(assessment$contract_crossing_pairs, na.rm = TRUE),
    raw_crossing_pairs = sum(assessment$raw_crossing_pairs, na.rm = TRUE),
    max_abs_adjustment = max(assessment$max_abs_adjustment, na.rm = TRUE),
    max_adjustment_rate = max(assessment$adjustment_rate, na.rm = TRUE),
    finite_quantiles = all(assessment$finite_quantiles),
    finite_scores = all(assessment$finite_scores),
    finite_traces = all(vb$finite_trace),
    max_iter_rows = sum(vb$reached_max_iter),
    converged_rows = sum(vb$converged),
    overall_status = if (any(assessment$gate_status == "fail") || any(manifest_check$status == "fail")) {
      "fail"
    } else if (any(assessment$gate_status == "review")) {
      "review"
    } else {
      "pass"
    },
    stringsAsFactors = FALSE
  )
}

model_metrics <- function(dir, stage) {
  assessment_file <- if (stage == "fit") "fit_validation_assessment.csv" else "forecast_validation_assessment.csv"
  truth_file <- if (stage == "fit") "fit_truth_comparison.csv" else "forecast_truth_comparison.csv"
  assessment <- app_read_csv(file.path(dir, assessment_file))
  truth <- app_read_csv(file.path(dir, truth_file))
  check <- app_read_csv(file.path(dir, "check_loss_summary.csv"))
  crps <- app_read_csv(file.path(dir, "crps_grid_summary.csv"))
  hit <- app_read_csv(file.path(dir, "hit_rate_summary.csv"))
  interval <- app_read_csv(file.path(dir, "interval_summary.csv"))
  by_model <- c("model_id", "display_label", "likelihood", "fit_structure")
  truth_m <- aggregate(cbind(truth_abs_error, truth_sq_error, check_loss) ~ model_id + display_label + likelihood + fit_structure, truth, mean, na.rm = TRUE)
  truth_m$truth_rmse <- sqrt(truth_m$truth_sq_error)
  names(truth_m)[names(truth_m) == "truth_abs_error"] <- "truth_mae"
  names(truth_m)[names(truth_m) == "check_loss"] <- "check_loss_from_quantiles"
  check_m <- aggregate(check_loss_mean ~ model_id + display_label + likelihood + fit_structure, check, mean, na.rm = TRUE)
  crps_m <- aggregate(crps_grid_mean ~ model_id + display_label + likelihood + fit_structure, crps, mean, na.rm = TRUE)
  hit_m <- aggregate(abs_hit_rate_error ~ model_id + display_label + likelihood + fit_structure, hit, mean, na.rm = TRUE)
  interval_m <- aggregate(cbind(abs_coverage_error, interval_width_mean, interval_score_mean) ~ model_id + display_label + likelihood + fit_structure, interval, mean, na.rm = TRUE)
  adjust_m <- aggregate(cbind(raw_crossing_pairs, contract_crossing_pairs, max_abs_adjustment, adjustment_rate, elapsed_seconds) ~ model_id + display_label + likelihood + fit_structure, assessment, mean, na.rm = TRUE)
  gates <- aggregate(gate_status ~ model_id + display_label + likelihood + fit_structure, assessment, function(x) paste(names(sort(table(x), decreasing = TRUE)), collapse = ";"))
  out <- Reduce(function(x, y) merge(x, y, by = by_model, all = TRUE), list(truth_m, check_m, crps_m, hit_m, interval_m, adjust_m, gates))
  out$stage <- stage
  out[, c("stage", setdiff(names(out), "stage")), drop = FALSE]
}

scenario_metrics <- function(dir, stage) {
  assessment_file <- if (stage == "fit") "fit_validation_assessment.csv" else "forecast_validation_assessment.csv"
  truth_file <- if (stage == "fit") "fit_truth_comparison.csv" else "forecast_truth_comparison.csv"
  assessment <- app_read_csv(file.path(dir, assessment_file))
  truth <- app_read_csv(file.path(dir, truth_file))
  check <- app_read_csv(file.path(dir, "check_loss_summary.csv"))
  by_sm <- c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure")
  truth_m <- aggregate(cbind(truth_abs_error, truth_sq_error) ~ scenario_id + model_id + display_label + likelihood + fit_structure, truth, mean, na.rm = TRUE)
  truth_m$truth_rmse <- sqrt(truth_m$truth_sq_error)
  names(truth_m)[names(truth_m) == "truth_abs_error"] <- "truth_mae"
  check_m <- aggregate(check_loss_mean ~ scenario_id + model_id + display_label + likelihood + fit_structure, check, mean, na.rm = TRUE)
  adjust_m <- assessment[, c(by_sm, "gate_status", "raw_crossing_pairs", "contract_crossing_pairs", "max_abs_adjustment", "adjustment_rate", "status_reason"), drop = FALSE]
  out <- Reduce(function(x, y) merge(x, y, by = by_sm, all = TRUE), list(truth_m, check_m, adjust_m))
  out$stage <- stage
  out[, c("stage", setdiff(names(out), "stage")), drop = FALSE]
}

convergence_summary <- function(dir, stage) {
  vb <- app_read_csv(file.path(dir, "vb_convergence_audit.csv"))
  rt <- app_read_csv(file.path(dir, "runtime_summary.csv"))
  by_model <- c("model_id", "display_label", "likelihood", "fit_structure")
  conv <- aggregate(cbind(converged, reached_max_iter, finite_trace) ~ model_id + display_label + likelihood + fit_structure, vb, sum, na.rm = TRUE)
  n <- aggregate(final_iter ~ model_id + display_label + likelihood + fit_structure, vb, length)
  names(n)[names(n) == "final_iter"] <- "n_fits"
  iter <- aggregate(final_iter ~ model_id + display_label + likelihood + fit_structure, vb, mean, na.rm = TRUE)
  names(iter)[names(iter) == "final_iter"] <- "mean_final_iter"
  runtime <- aggregate(elapsed_seconds ~ model_id + display_label + likelihood + fit_structure, rt, function(x) c(mean = mean(x), max = max(x), sum = sum(x)))
  runtime <- do.call(data.frame, runtime)
  names(runtime) <- sub("^elapsed_seconds\\.", "runtime_", names(runtime))
  out <- Reduce(function(x, y) merge(x, y, by = by_model, all = TRUE), list(conv, n, iter, runtime))
  out$stage <- stage
  out[, c("stage", setdiff(names(out), "stage")), drop = FALSE]
}

article_ranking <- function(forecast_model_metrics, forecast_scenario_metrics) {
  out <- forecast_model_metrics
  out$rank_score <- out$truth_mae + 0.05 * out$abs_hit_rate_error + 0.001 * out$raw_crossing_pairs
  out$rank <- rank(out$rank_score, ties.method = "first")
  out$recommended_role <- ifelse(
    out$display_label == "JOINT QDESN RHS",
    "primary_article_candidate",
    ifelse(
      out$display_label == "QDESN RHS",
      "primary_independent_comparator",
      ifelse(
        out$display_label == "JOINT exQDESN RHS",
        "secondary_exal_comparator",
        "hold_for_targeted_failure_audit"
      )
    )
  )
  out$recommendation <- ifelse(
    out$display_label == "exQDESN RHS",
    "Do not use in the main article table until the asymmetric_laplace_tail failure is resolved.",
    ifelse(
      out$display_label == "JOINT QDESN RHS",
      "Use as the leading joint model candidate.",
      ifelse(out$display_label == "QDESN RHS", "Use as the main independent comparator.", "Use cautiously as a stable but less accurate exAL comparison.")
    )
  )
  out[order(out$rank), c("rank", "display_label", "recommended_role", "truth_mae", "truth_rmse", "check_loss_mean", "crps_grid_mean", "abs_hit_rate_error", "raw_crossing_pairs", "max_abs_adjustment", "recommendation"), drop = FALSE]
}

readme_lines <- function(summary_table, ranking) {
  c(
    "# Joint QDESN Post-VB Validation Audit",
    "",
    "This directory contains compact audit summaries for the completed article-scale VB fit and no-refit forecast validation artifacts.",
    "",
    "Source artifact directories:",
    "",
    sprintf("- Fit: `%s`", summary_table$artifact_dir[summary_table$stage == "fit"]),
    sprintf("- Forecast: `%s`", summary_table$artifact_dir[summary_table$stage == "forecast"]),
    "",
    "Main conclusion:",
    "",
    "- `JOINT QDESN RHS` is the strongest article candidate.",
    "- `QDESN RHS` is the main independent comparator.",
    "- `JOINT exQDESN RHS` is stable but less accurate.",
    "- `exQDESN RHS` is held for targeted failure audit because of the asymmetric-tail pathology.",
    "",
    "Top article ranking:",
    "",
    paste(capture.output(print(ranking[, c("rank", "display_label", "recommended_role")], row.names = FALSE)), collapse = "\n")
  )
}

fit_dir <- resolve_repo_path(arg_value("fit_dir"), must_work = TRUE)
forecast_dir <- resolve_repo_path(arg_value("forecast_dir"), must_work = TRUE)
out_dir <- resolve_repo_path(arg_value("output_dir"), must_work = FALSE)
app_ensure_dir(out_dir)

manifest_verification <- bind_rows(list(
  verify_manifest(fit_dir, "fit"),
  verify_manifest(forecast_dir, "forecast")
))
health <- bind_rows(list(
  summarise_stage(fit_dir, "fit"),
  summarise_stage(forecast_dir, "forecast")
))
model_summary <- bind_rows(list(
  model_metrics(fit_dir, "fit"),
  model_metrics(forecast_dir, "forecast")
))
scenario_summary <- bind_rows(list(
  scenario_metrics(fit_dir, "fit"),
  scenario_metrics(forecast_dir, "forecast")
))
adjustment_summary <- scenario_summary[, c("stage", "scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "gate_status", "raw_crossing_pairs", "contract_crossing_pairs", "max_abs_adjustment", "adjustment_rate", "status_reason"), drop = FALSE]
vb_summary <- bind_rows(list(
  convergence_summary(fit_dir, "fit"),
  convergence_summary(forecast_dir, "forecast")
))
ranking <- article_ranking(model_summary[model_summary$stage == "forecast", , drop = FALSE], scenario_summary[scenario_summary$stage == "forecast", , drop = FALSE])
run_config <- data.frame(
  run_id = "joint_qdesn_post_vb_fit_forecast_audit",
  fit_dir = fit_dir,
  forecast_dir = forecast_dir,
  out_dir = out_dir,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  stringsAsFactors = FALSE
)
readme_path <- file.path(out_dir, "README.md")
writeLines(readme_lines(health, ranking), readme_path, useBytes = TRUE)
paths <- c(
  run_config = write_csv(run_config, file.path(out_dir, "run_config.csv")),
  validation_health_summary = write_csv(health, file.path(out_dir, "validation_health_summary.csv")),
  model_metric_summary = write_csv(model_summary, file.path(out_dir, "model_metric_summary.csv")),
  scenario_metric_summary = write_csv(scenario_summary, file.path(out_dir, "scenario_metric_summary.csv")),
  raw_contract_adjustment_summary = write_csv(adjustment_summary, file.path(out_dir, "raw_contract_adjustment_summary.csv")),
  vb_convergence_summary = write_csv(vb_summary, file.path(out_dir, "vb_convergence_summary.csv")),
  artifact_manifest_verification = write_csv(manifest_verification, file.path(out_dir, "artifact_manifest_verification.csv")),
  article_candidate_model_ranking = write_csv(ranking, file.path(out_dir, "article_candidate_model_ranking.csv")),
  provenance = write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
  readme = normalizePath(readme_path, mustWork = TRUE)
)
manifest <- data.frame(
  label = names(paths),
  relative_path = basename(paths),
  size_bytes = as.numeric(file.info(paths)$size),
  sha256 = vapply(paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
manifest_path <- write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))

cat(sprintf("Joint QDESN post-VB compact audit written to %s\n", out_dir))
cat("Health status counts:\n")
print(table(health$overall_status))
cat("Article candidate ranking:\n")
print(ranking[, c("rank", "display_label", "recommended_role")], row.names = FALSE)
cat(sprintf("Artifact manifest: %s\n", manifest_path))
