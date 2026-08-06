#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_fit_recovery.R"))
source(app_path("application/R/glofas_fit_recovery_selection.R"))

args <- app_parse_args(list(
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_blocked_20260731"
))
resolve_repo <- function(path) if (grepl("^/", path)) path else app_path(path)
output_root <- normalizePath(resolve_repo(args$output_root), mustWork = TRUE)
manifest <- app_read_csv(file.path(output_root, "runtime_manifest.csv"))
if (!nrow(manifest)) stop("The blocked-validation runtime manifest is empty.", call. = FALSE)
app_ensure_dir(file.path(output_root, "tables"))

rows <- lapply(seq_len(nrow(manifest)), function(i) {
  item <- manifest[i, , drop = FALSE]
  run_dir <- item$run_dir[[1L]]
  if (!file.exists(file.path(run_dir, ".fit_recovery_complete"))) {
    stop(sprintf("Blocked-validation run is incomplete: %s.", item$candidate_id[[1L]]), call. = FALSE)
  }
  model_grid <- app_read_csv(item$model_grid_path[[1L]])
  qrow <- model_grid[model_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  rawrow <- model_grid[model_grid$model_family == "raw_glofas", , drop = FALSE]
  if (nrow(qrow) != 1L || nrow(rawrow) != 1L) stop("Blocked model grid is not a one-pair grid.", call. = FALSE)
  summary <- app_read_csv(file.path(run_dir, "tables", "score_summary.csv"))
  qscore <- summary[summary$model_id == qrow$model_id[[1L]], , drop = FALSE]
  rawscore <- summary[summary$model_id == rawrow$model_id[[1L]], , drop = FALSE]
  diagnostics <- app_read_csv(file.path(run_dir, "tables", "qdesn_discrepancy_fit_diagnostics.csv"))
  fit_manifest <- app_read_csv(file.path(run_dir, "manifest", "qdesn_discrepancy_fit_manifest.csv"))
  scored <- app_read_csv(file.path(run_dir, "tables", "score_by_quantile.csv"))
  qscored <- scored[scored$model_id == qrow$model_id[[1L]], , drop = FALSE]
  rawscored <- scored[scored$model_id == rawrow$model_id[[1L]], , drop = FALSE]
  discrepancy_history <- app_read_csv(file.path(run_dir, "tables", "post_fit_discrepancy_history_summary.csv"))
  if (nrow(qscore) != 1L || nrow(rawscore) != 1L || nrow(diagnostics) != 1L || nrow(fit_manifest) != 1L || !nrow(qscored)) {
    stop(sprintf("Blocked-validation outputs are incomplete for %s.", item$candidate_id[[1L]]), call. = FALSE)
  }
  policy_ok <- identical(as.character(fit_manifest$covariate_future_policy[[1L]]), "oracle_realized") &&
    identical(as.character(fit_manifest$covariate_source_provider[[1L]]), "realized_future_oracle") &&
    isTRUE(app_as_bool_vec(fit_manifest$covariate_uses_realized_future)[[1L]])
  cold_start_ok <- !isTRUE(app_as_bool_vec(diagnostics$vb_warm_start_enabled)[[1L]]) &&
    !isTRUE(app_as_bool_vec(diagnostics$vb_warm_start_used)[[1L]])
  fit_ok <- isTRUE(app_as_bool_vec(diagnostics$vb_converged)[[1L]]) &&
    isTRUE(app_as_bool_vec(diagnostics$finite_theta)[[1L]]) &&
    isTRUE(app_as_bool_vec(diagnostics$finite_sigma)[[1L]])
  portability <- app_glofas_fit_recovery_portability_audit(
    qscored, rawscored, discrepancy_history
  )
  portability$detail$candidate_id <- item$base_candidate_id[[1L]]
  portability$detail$cutoff_id <- item$cutoff_id[[1L]]
  detail_path <- file.path(
    output_root, "tables",
    paste0("portability_components_", item$base_candidate_id[[1L]], "_", item$cutoff_id[[1L]], ".csv")
  )
  app_write_csv(portability$detail, detail_path)
  p <- portability$summary
  q_original <- app_glofas_fit_recovery_safe_expm1(qscored$qhat)
  y_original <- app_glofas_fit_recovery_safe_expm1(qscored$y_reference)
  data.frame(
    candidate_id = item$base_candidate_id[[1L]],
    cutoff_id = item$cutoff_id[[1L]],
    origin_date = item$origin_date[[1L]],
    n_horizons = nrow(qscored),
    qdesn_check_loss_mean = qscore$check_loss_mean[[1L]],
    raw_check_loss_mean = rawscore$check_loss_mean[[1L]],
    check_loss_reduction_vs_raw = (rawscore$check_loss_mean[[1L]] - qscore$check_loss_mean[[1L]]) / rawscore$check_loss_mean[[1L]],
    qdesn_original_mae = mean(abs(q_original - y_original), na.rm = TRUE),
    qdesn_original_rmse = sqrt(mean((q_original - y_original)^2, na.rm = TRUE)),
    vb_iterations = diagnostics$vb_iterations[[1L]],
    fit_gate_pass = fit_ok,
    cold_start_gate_pass = cold_start_ok,
    oracle_policy_gate_pass = policy_ok,
    technical_gate_pass = fit_ok && cold_start_ok && policy_ok,
    performance_gate_pass = p$performance_gate_pass,
    component_identity_gate_pass = p$component_identity_gate_pass,
    forecast_scale_gate_pass = p$forecast_scale_gate_pass,
    discrepancy_support_gate_pass = p$discrepancy_support_gate_pass,
    check_loss_ratio_vs_raw = p$check_loss_ratio_vs_raw,
    forecast_to_observed_max_ratio = p$forecast_to_observed_max_ratio,
    forecast_abs_discrepancy_to_history_q995_ratio = p$forecast_abs_discrepancy_to_history_q995_ratio,
    component_identity_max_abs_error = p$component_identity_max_abs_error,
    scientific_portability_gate_pass = p$scientific_portability_gate_pass,
    all_gates_pass = fit_ok && cold_start_ok && policy_ok && p$scientific_portability_gate_pass,
    run_id = item$run_id[[1L]],
    stringsAsFactors = FALSE
  )
})
by_cutoff <- app_bind_rows_fill(rows)
if (!all(by_cutoff$technical_gate_pass)) stop("One or more blocked-validation technical gates failed.", call. = FALSE)

aggregate_rows <- lapply(split(by_cutoff, by_cutoff$candidate_id), function(x) {
  data.frame(
    candidate_id = x$candidate_id[[1L]],
    n_cutoffs = nrow(x),
    mean_qdesn_check_loss = mean(x$qdesn_check_loss_mean),
    mean_raw_check_loss = mean(x$raw_check_loss_mean),
    mean_check_loss_reduction_vs_raw = mean(x$check_loss_reduction_vs_raw),
    mean_original_mae = mean(x$qdesn_original_mae),
    mean_original_rmse = mean(x$qdesn_original_rmse),
    wins_vs_raw = sum(x$qdesn_check_loss_mean < x$raw_check_loss_mean),
    worst_check_loss = max(x$qdesn_check_loss_mean),
    all_gates_pass = all(x$all_gates_pass),
    all_technical_gates_pass = all(x$technical_gate_pass),
    all_scientific_portability_gates_pass = all(x$scientific_portability_gate_pass),
    stringsAsFactors = FALSE
  )
})
ranking <- app_bind_rows_fill(aggregate_rows)
ranking <- ranking[order(ranking$mean_qdesn_check_loss, ranking$worst_check_loss, ranking$mean_original_rmse), , drop = FALSE]
ranking$blocked_rank <- seq_len(nrow(ranking))
ranking$decision_status <- ifelse(
  ranking$all_scientific_portability_gates_pass,
  "eligible_for_full7_review_not_authoritative_forecast_evidence",
  "blocked_scientific_portability_failure"
)

app_write_csv(by_cutoff, file.path(output_root, "tables", "blocked_validation_by_cutoff.csv"))
app_write_csv(ranking, file.path(output_root, "tables", "blocked_validation_ranking.csv"))
component_paths <- list.files(
  file.path(output_root, "tables"), pattern = "^portability_components_.*\\.csv$", full.names = TRUE
)
components <- app_bind_rows_fill(lapply(component_paths, app_read_csv))
components$target_date <- as.Date(components$target_date)
component_long <- rbind(
  data.frame(components[c("candidate_id", "cutoff_id", "target_date", "horizon")], series = "Observed USGS", value = components$y_log1p),
  data.frame(components[c("candidate_id", "cutoff_id", "target_date", "horizon")], series = "Raw GloFAS", value = components$raw_log1p),
  data.frame(components[c("candidate_id", "cutoff_id", "target_date", "horizon")], series = "Reference block", value = components$q_g_log1p),
  data.frame(components[c("candidate_id", "cutoff_id", "target_date", "horizon")], series = "Q-DESN corrected", value = components$q_y_log1p)
)
component_long$series <- factor(
  component_long$series,
  levels = c("Observed USGS", "Raw GloFAS", "Reference block", "Q-DESN corrected")
)
plot <- ggplot2::ggplot(component_long, ggplot2::aes(target_date, value, color = series, linetype = series)) +
  ggplot2::geom_line(linewidth = 0.55) +
  ggplot2::geom_point(data = component_long[component_long$series == "Observed USGS", ], size = 1.1) +
  ggplot2::facet_grid(candidate_id ~ cutoff_id, scales = "free_x") +
  ggplot2::scale_color_manual(values = c("#111111", "#3B6FB6", "#2A9D6F", "#C23B32")) +
  ggplot2::scale_linetype_manual(values = c("solid", "dashed", "dotdash", "solid")) +
  ggplot2::labs(x = NULL, y = "log(1 + streamflow)", color = NULL, linetype = NULL) +
  ggplot2::theme_bw(base_size = 9) +
  ggplot2::theme(legend.position = "bottom", panel.grid.minor = ggplot2::element_blank())
for (extension in c("pdf", "png")) {
  app_glofas_selection_save_plot(
    plot, file.path(output_root, "figures", paste0("blocked_portability_components.", extension)),
    width = 9.5, height = 5.8
  )
}
paths <- list.files(file.path(output_root, "tables"), full.names = TRUE)
app_write_csv(data.frame(
  path = paths,
  size_bytes = as.numeric(file.info(paths)$size),
  sha256 = vapply(paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
), file.path(output_root, "artifact_manifest.csv"))
writeLines(c(
  "Blocked historical pseudo-cutoff validation completed.",
  paste("Technical gates:", if (all(by_cutoff$technical_gate_pass)) "PASS" else "FAIL"),
  paste("Scientific portability gates:", if (all(by_cutoff$scientific_portability_gate_pass)) "PASS" else "FAIL"),
  "All fits were cold-started and used explicitly oracle-realized future ppt/soil covariates.",
  "These results are a portability safeguard and are not deployable operational evidence.",
  "A scientific-gate failure blocks full-seven advancement but preserves all diagnostic outputs.",
  paste("Ranking:", file.path(output_root, "tables", "blocked_validation_ranking.csv"))
), file.path(output_root, "FINALIZATION_COMPLETE.txt"))
cat(file.path(output_root, "tables", "blocked_validation_ranking.csv"), "\n")
