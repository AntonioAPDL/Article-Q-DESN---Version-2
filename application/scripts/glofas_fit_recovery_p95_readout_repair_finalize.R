#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_fit_recovery.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/glofas_fit_recovery_selection.R"))
source(app_path("application/R/glofas_fit_recovery_scientific_audit.R"))

args <- app_parse_args(list(
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_p95_readout_repair_20260809",
  control_root = "local_trackers/runtime_configs/glofas_fit_recovery_transition_full7_20260808",
  cutoff_date = "2022-12-25",
  windows = "all,1000,500,200,100,50"
))
resolve_repo <- function(path, must_work = FALSE) {
  normalizePath(if (grepl("^/", path)) path else app_path(path), mustWork = must_work)
}
output_root <- resolve_repo(args$output_root, TRUE)
control_root <- resolve_repo(args$control_root, TRUE)
cutoff_date <- as.Date(args$cutoff_date)
windows <- trimws(strsplit(as.character(args$windows), ",", fixed = TRUE)[[1L]])
windows <- vapply(windows, function(x) if (tolower(x) == "all") NA_integer_ else as.integer(x), integer(1L))
for (dir in c("tables", "figures", "manifest")) app_ensure_dir(file.path(output_root, dir))

runtime <- app_read_csv(file.path(output_root, "runtime_manifest.csv"))
if (!nrow(runtime)) stop("The p95 repair runtime manifest is empty.", call. = FALSE)
source_rows <- list()
for (i in seq_len(nrow(runtime))) {
  run_dir <- normalizePath(runtime$run_dir[[i]], mustWork = TRUE)
  if (!file.exists(file.path(run_dir, ".fit_recovery_complete"))) {
    stop(sprintf("P95 repair source is incomplete: %s.", runtime$candidate_id[[i]]), call. = FALSE)
  }
  fit_manifest <- app_read_csv(file.path(run_dir, "manifest", "qdesn_discrepancy_fit_manifest.csv"))
  if (nrow(fit_manifest) != 1L || fit_manifest$status[[1L]] != "completed") {
    stop(sprintf("P95 repair fit manifest is incomplete: %s.", runtime$candidate_id[[i]]), call. = FALSE)
  }
  fit_path <- resolve_repo(fit_manifest$fit_object[[1L]], TRUE)
  history_path <- normalizePath(file.path(run_dir, "tables", "post_fit_quantile_history_summary.csv"), mustWork = TRUE)
  source_rows[[length(source_rows) + 1L]] <- data.frame(
    candidate_id = runtime$candidate_id[[i]],
    quantile_id = "p95", quantile_level = 0.95,
    source_kind = runtime$source_kind[[i]],
    run_id = runtime$run_id[[i]], run_dir = run_dir,
    history_path = history_path, fit_object = fit_path,
    fit_object_sha256 = app_sha256_file(fit_path),
    candidate_role = runtime$role[[i]],
    stringsAsFactors = FALSE
  )
}
control_manifest <- app_read_csv(file.path(control_root, "quantile_source_manifest_completed.csv"))
control <- control_manifest[abs(as.numeric(control_manifest$quantile_level) - 0.95) < 1e-12, , drop = FALSE]
if (nrow(control) != 1L) stop("The frozen transition control lacks one p95 source.", call. = FALSE)
control$candidate_id <- "fr09_persistence_innovation_control"
control$candidate_role <- "frozen_full7_control"
source_manifest <- rbind(
  control[, names(source_rows[[1L]]), drop = FALSE],
  app_bind_rows_fill(source_rows)
)
source_manifest <- app_glofas_selection_validate_source_manifest(source_manifest, require_complete = TRUE)
app_write_csv(source_manifest, file.path(output_root, "manifest", "p95_source_manifest.csv"))
fit_gate <- app_glofas_selection_fit_gate(source_manifest)
app_write_csv(fit_gate, file.path(output_root, "tables", "p95_fit_gate.csv"))
if (!all(fit_gate$gate_pass)) stop("At least one p95 repair fit failed its technical gate.", call. = FALSE)

raw_histories <- lapply(seq_len(nrow(source_manifest)), function(i) {
  x <- app_read_csv(source_manifest$history_path[[i]])
  x$candidate_id <- source_manifest$candidate_id[[i]]
  x
})
names(raw_histories) <- source_manifest$candidate_id
histories <- lapply(seq_along(raw_histories), function(i) {
  app_glofas_fit_recovery_history(
    raw_histories[[i]], source_manifest$candidate_id[[i]], cutoff_date
  )
})
names(histories) <- names(raw_histories)
histories <- app_glofas_fit_recovery_align_histories(histories)
common_dates <- histories[[1L]]$target_date
if (length(common_dates) < 1000L) stop("P95 repair candidates have insufficient common history.", call. = FALSE)

metric_rows <- list()
component_rows <- list()
detail_rows <- list()
for (candidate_id in names(histories)) {
  history <- histories[[candidate_id]]
  raw_history <- raw_histories[[candidate_id]]
  component <- app_glofas_scientific_component_audit(raw_history, candidate_id)
  component_rows[[length(component_rows) + 1L]] <- component$summary
  detail_rows[[length(detail_rows) + 1L]] <- component$detail
  for (window in windows) {
    selected <- if (is.finite(window)) tail(seq_len(nrow(history)), min(as.integer(window), nrow(history))) else seq_len(nrow(history))
    block <- history[selected, , drop = FALSE]
    metric_rows[[length(metric_rows) + 1L]] <- data.frame(
      candidate_id = candidate_id,
      window = app_glofas_fit_recovery_window_label(window),
      n_dates = nrow(block),
      date_min = as.character(min(block$target_date)),
      date_max = as.character(max(block$target_date)),
      log1p_check_loss_mean = app_glofas_fit_recovery_check_loss(block$y_log1p, block$qhat_log1p, 0.95),
      original_check_loss_mean = app_glofas_fit_recovery_check_loss(block$y_original, block$qhat_original, 0.95),
      log1p_mae = mean(abs(block$qhat_log1p - block$y_log1p)),
      original_mae = mean(abs(block$qhat_original - block$y_original)),
      observed_max = max(block$y_original),
      fitted_max = max(block$qhat_original),
      fitted_max_to_observed_max_ratio = max(block$qhat_original) / max(block$y_original),
      n_above_20x_observed_max = sum(block$qhat_original > 20 * max(block$y_original)),
      stringsAsFactors = FALSE
    )
  }
}
metrics <- app_bind_rows_fill(metric_rows)
components <- app_bind_rows_fill(component_rows)
details <- app_bind_rows_fill(detail_rows)
all_metrics <- metrics[metrics$window == "all", , drop = FALSE]
candidate_gate <- merge(
  all_metrics,
  components[, c(
    "candidate_id", "prediction_identity_max_abs_error",
    "fitted_abs_discrepancy_to_history_q995_ratio"
  ), drop = FALSE],
  by = "candidate_id", all = TRUE
)
candidate_gate <- merge(
  candidate_gate,
  aggregate(gate_pass ~ candidate_id, fit_gate, all),
  by = "candidate_id", all = TRUE
)
candidate_gate$finite_score_gate_pass <- with(candidate_gate,
  is.finite(log1p_check_loss_mean) & is.finite(original_check_loss_mean))
candidate_gate$identity_gate_pass <- candidate_gate$prediction_identity_max_abs_error <= 1e-8
candidate_gate$tail_scale_gate_pass <- with(candidate_gate,
  fitted_max_to_observed_max_ratio <= 20 & n_above_20x_observed_max == 0L)
candidate_gate$discrepancy_support_gate_pass <-
  candidate_gate$fitted_abs_discrepancy_to_history_q995_ratio <= 1.5
candidate_gate$scientific_gate_pass <- with(candidate_gate,
  app_as_bool_vec(gate_pass) & finite_score_gate_pass & identity_gate_pass &
    tail_scale_gate_pass & discrepancy_support_gate_pass)
candidate_gate$is_new_candidate <- candidate_gate$candidate_id != "fr09_persistence_innovation_control"
candidate_gate$eligible_for_blocked_replay <- candidate_gate$scientific_gate_pass & candidate_gate$is_new_candidate
candidate_gate$auto_launch_blocked_replay <- FALSE
candidate_gate$auto_launch_full7 <- FALSE
candidate_gate$auto_promote <- FALSE
ranking <- candidate_gate[order(
  !candidate_gate$eligible_for_blocked_replay,
  candidate_gate$original_check_loss_mean,
  candidate_gate$log1p_check_loss_mean
), , drop = FALSE]
ranking$rank <- seq_len(nrow(ranking))
ranking$decision <- ifelse(
  ranking$eligible_for_blocked_replay,
  "eligible_for_human_review_then_blocked_pseudo_cutoff_replay",
  "blocked_scientific_gate"
)
ranking <- ranking[, c("rank", setdiff(names(ranking), "rank")), drop = FALSE]

app_write_csv(metrics, file.path(output_root, "tables", "p95_dual_scale_scores.csv"))
app_write_csv(components, file.path(output_root, "tables", "p95_component_summary.csv"))
app_write_csv(details, file.path(output_root, "tables", "p95_component_detail.csv"))
app_write_csv(candidate_gate, file.path(output_root, "tables", "p95_scientific_gate.csv"))
app_write_csv(ranking, file.path(output_root, "tables", "p95_repair_ranking.csv"))
app_write_csv(data.frame(
  n_common_dates = length(common_dates),
  date_min = as.character(min(common_dates)),
  date_max = as.character(max(common_dates)),
  stringsAsFactors = FALSE
), file.path(output_root, "tables", "p95_common_date_audit.csv"))

if (!requireNamespace("ggplot2", quietly = TRUE) || !isTRUE(capabilities("cairo"))) {
  stop("P95 repair finalization requires ggplot2 and Cairo graphics.", call. = FALSE)
}
last200 <- app_bind_rows_fill(lapply(histories, function(x) tail(x, 200L)))
last200_long <- rbind(
  data.frame(candidate_id = last200$candidate_id, target_date = last200$target_date,
             path = "observed", value = last200$y_log1p),
  data.frame(candidate_id = last200$candidate_id, target_date = last200$target_date,
             path = "fitted_p95", value = last200$qhat_log1p)
)
theme_repair <- ggplot2::theme_bw(base_size = 9) + ggplot2::theme(
  panel.grid.minor = ggplot2::element_blank(), legend.position = "bottom",
  strip.background = ggplot2::element_rect(fill = "gray94", color = "gray75")
)
fit_plot <- ggplot2::ggplot(last200_long, ggplot2::aes(target_date, value, color = path)) +
  ggplot2::geom_line(linewidth = 0.42) +
  ggplot2::facet_wrap(~ candidate_id, ncol = 1L) +
  ggplot2::scale_color_manual(values = c(observed = "gray45", fitted_p95 = "#A63D40")) +
  ggplot2::labs(
    title = "P95 readout-repair fit over the final 200 observed dates",
    subtitle = "Cold-start candidates; the held-out forecast window is not used for selection",
    x = NULL, y = "log(1 + streamflow)", color = NULL
  ) + theme_repair
tail_plot <- ggplot2::ggplot(
  details,
  ggplot2::aes(target_date, q_y_original, color = candidate_id)
) +
  ggplot2::geom_point(alpha = 0.38, size = 0.65) +
  ggplot2::scale_y_log10() +
  ggplot2::facet_wrap(~ candidate_id, ncol = 1L) +
  ggplot2::labs(
    title = "P95 fitted scale across the observed history",
    subtitle = "Original streamflow scale shown logarithmically",
    x = NULL, y = "Fitted p95 streamflow", color = NULL
  ) + theme_repair + ggplot2::theme(legend.position = "none")
for (spec in list(
  list(name = "p95_repair_last200_fit", plot = fit_plot, width = 9.4, height = 8.4),
  list(name = "p95_repair_full_history_scale", plot = tail_plot, width = 9.4, height = 8.4)
)) {
  app_glofas_selection_save_plot(spec$plot, file.path(output_root, "figures", paste0(spec$name, ".pdf")), spec$width, spec$height)
  app_glofas_selection_save_plot(spec$plot, file.path(output_root, "figures", paste0(spec$name, ".png")), spec$width, spec$height)
}

eligible <- ranking[ranking$eligible_for_blocked_replay, , drop = FALSE]
decision_path <- if (nrow(eligible)) {
  file.path(output_root, "P95_REPAIR_REVIEW_READY.txt")
} else {
  file.path(output_root, "P95_REPAIR_BLOCKED.txt")
}
writeLines(c(
  if (nrow(eligible)) {
    sprintf("Top candidate: %s", eligible$candidate_id[[1L]])
  } else {
    "No p95 repair candidate passed every scientific gate."
  },
  "The next permitted action is human review followed by blocked pseudo-cutoff replay.",
  "No full-seven launch, promotion, or article update is authorized."
), decision_path)
provenance <- data.frame(
  field = c(
    "finalized_at", "repo_head", "finalizer_sha256", "selection_helper_sha256",
    "scientific_helper_sha256", "source_manifest_sha256", "ranking_sha256",
    "selection_scope", "forecast_window_used"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)[[1L]],
    app_sha256_file(app_path("application/scripts/glofas_fit_recovery_p95_readout_repair_finalize.R")),
    app_sha256_file(app_path("application/R/glofas_fit_recovery_selection.R")),
    app_sha256_file(app_path("application/R/glofas_fit_recovery_scientific_audit.R")),
    app_sha256_file(file.path(output_root, "manifest", "p95_source_manifest.csv")),
    app_sha256_file(file.path(output_root, "tables", "p95_repair_ranking.csv")),
    "observed_history_only", "false"
  ),
  stringsAsFactors = FALSE
)
app_write_csv(provenance, file.path(output_root, "manifest", "p95_repair_finalization_provenance.csv"))
artifact_paths <- c(
  list.files(file.path(output_root, "tables"), full.names = TRUE),
  list.files(file.path(output_root, "figures"), full.names = TRUE),
  list.files(file.path(output_root, "manifest"), full.names = TRUE),
  decision_path
)
artifact_paths <- artifact_paths[basename(artifact_paths) != "artifact_manifest.csv"]
app_write_csv(data.frame(
  path = normalizePath(artifact_paths, mustWork = TRUE),
  size_bytes = as.numeric(file.info(artifact_paths)$size),
  sha256 = vapply(artifact_paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
), file.path(output_root, "manifest", "artifact_manifest.csv"))
cat(normalizePath(decision_path, mustWork = TRUE), "\n")
