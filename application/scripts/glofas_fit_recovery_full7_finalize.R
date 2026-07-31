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

args <- app_parse_args(list(
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_full7_20260731",
  cutoff_date = "2022-12-25",
  windows = "all,1000,500,200,100,50"
))
resolve_repo <- function(path) if (grepl("^/", path)) path else app_path(path)
output_root <- normalizePath(resolve_repo(args$output_root), mustWork = TRUE)
cutoff_date <- as.Date(args$cutoff_date)
windows <- trimws(strsplit(as.character(args$windows), ",", fixed = TRUE)[[1L]])
windows <- vapply(windows, function(x) if (tolower(x) == "all") NA_integer_ else as.integer(x), integer(1L))
for (dir in c("tables", "figures")) app_ensure_dir(file.path(output_root, dir))

source_manifest <- app_glofas_selection_validate_source_manifest(
  app_read_csv(file.path(output_root, "quantile_source_manifest_prepared.csv")),
  require_complete = FALSE
)
for (i in seq_len(nrow(source_manifest))) {
  run_dir <- source_manifest$run_dir[[i]]
  if (!file.exists(file.path(run_dir, ".fit_recovery_complete")) ||
      !file.exists(source_manifest$fit_object[[i]]) ||
      !file.exists(source_manifest$history_path[[i]])) {
    stop(sprintf("Full-seven source is incomplete for %s::%s.", source_manifest$candidate_id[[i]], source_manifest$quantile_id[[i]]), call. = FALSE)
  }
  source_manifest$fit_object_sha256[[i]] <- app_sha256_file(source_manifest$fit_object[[i]])
  source_manifest$status[[i]] <- "completed"
}
source_manifest <- app_glofas_selection_validate_source_manifest(source_manifest, require_complete = TRUE)
expected_levels <- c(0.05, 0.15, 0.35, 0.50, 0.65, 0.80, 0.95)
for (candidate_id in unique(source_manifest$candidate_id)) {
  observed <- sort(source_manifest$quantile_level[source_manifest$candidate_id == candidate_id])
  if (!isTRUE(all.equal(observed, expected_levels, tolerance = 1e-12))) {
    stop(sprintf("Candidate %s does not have the exact seven-quantile grid.", candidate_id), call. = FALSE)
  }
}
app_write_csv(source_manifest, file.path(output_root, "quantile_source_manifest_completed.csv"))

gate <- app_glofas_selection_fit_gate(source_manifest)
app_write_csv(gate, file.path(output_root, "tables", "fit_gate_audit.csv"))
if (!all(gate$gate_pass)) stop("At least one full-seven fit failed its completion/convergence gate.", call. = FALSE)
combined <- app_glofas_selection_combine_histories(source_manifest, cutoff_date = cutoff_date)
synthesized <- app_glofas_selection_apply_isotonic(combined$history)
scores <- app_glofas_selection_score_windows(synthesized$history, synthesized$crossing, windows = windows)
names(scores$summary)[names(scores$summary) == "triage_integrated_quantile_score"] <- "crps_quantile_grid_mean"
names(scores$by_date)[names(scores$by_date) == "triage_integrated_quantile_score"] <- "crps_quantile_grid"

ranking <- scores$summary[
  scores$summary$window == "all" & scores$summary$estimate_mode == "isotonic",
  , drop = FALSE
]
ranking <- ranking[order(ranking$crps_quantile_grid_mean, ranking$interval_score, ranking$mean_pinball_loss), , drop = FALSE]
ranking$rank <- seq_len(nrow(ranking))
ranking$selection_status <- "observed_window_evidence_complete_forecast_window_still_blinded"

app_write_csv(combined$date_audit, file.path(output_root, "tables", "history_date_alignment_audit.csv"))
app_write_csv(synthesized$history, file.path(output_root, "tables", "observed_history_full7_long.csv"))
app_write_csv(synthesized$crossing, file.path(output_root, "tables", "observed_history_crossing_by_date.csv"))
app_write_csv(scores$summary, file.path(output_root, "tables", "observed_history_full7_scores.csv"))
app_write_csv(scores$by_quantile, file.path(output_root, "tables", "observed_history_full7_scores_by_quantile.csv"))
app_write_csv(scores$by_date, file.path(output_root, "tables", "observed_history_full7_scores_by_date.csv"))
app_write_csv(ranking, file.path(output_root, "tables", "observed_history_full7_ranking.csv"))

if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Full-seven finalization requires ggplot2.", call. = FALSE)
last200 <- do.call(rbind, lapply(split(synthesized$history, synthesized$history$candidate_id), function(x) {
  dates <- tail(sort(unique(as.Date(x$target_date))), 200L)
  x[x$target_date %in% dates, , drop = FALSE]
}))
last200$quantile_label <- factor(sprintf("%.2f", last200$quantile_level), levels = sprintf("%.2f", expected_levels))
theme_fit <- ggplot2::theme_bw(base_size = 9) + ggplot2::theme(
  panel.grid.minor = ggplot2::element_blank(),
  strip.background = ggplot2::element_rect(fill = "gray94", color = "gray75"),
  legend.position = "bottom"
)
p_paths <- ggplot2::ggplot(last200, ggplot2::aes(target_date)) +
  ggplot2::geom_line(ggplot2::aes(y = y_log1p), color = "gray55", linewidth = 0.34) +
  ggplot2::geom_line(ggplot2::aes(y = qhat_isotonic, color = quantile_label), linewidth = 0.44) +
  ggplot2::facet_wrap(~ candidate_id, ncol = 1) +
  ggplot2::scale_color_viridis_d(option = "C", end = 0.90) +
  ggplot2::labs(
    title = "Seven fitted quantiles over the final 200 pre-cutoff dates",
    subtitle = "Displayed paths use the declared post-hoc isotonic projection; component models were fitted independently",
    x = NULL, y = "log(1 + streamflow)", color = "Quantile"
  ) + theme_fit
p_rank <- ggplot2::ggplot(ranking, ggplot2::aes(reorder(candidate_id, crps_quantile_grid_mean), crps_quantile_grid_mean)) +
  ggplot2::geom_col(fill = "#2563EB", width = 0.66) +
  ggplot2::coord_flip() +
  ggplot2::labs(
    title = "Observed-window seven-quantile grid CRPS",
    subtitle = "Selection remains blinded to the 2022-12-25 held-out forecast score",
    x = NULL, y = "Mean grid CRPS"
  ) + theme_fit
for (spec in list(
  list(name = "observed_history_last200_full7_quantiles", plot = p_paths, width = 9.2, height = 5.8),
  list(name = "observed_history_full7_crps_ranking", plot = p_rank, width = 7.5, height = 4.5)
)) {
  ggplot2::ggsave(file.path(output_root, "figures", paste0(spec$name, ".pdf")), spec$plot, width = spec$width, height = spec$height, units = "in", device = grDevices::cairo_pdf)
  ggplot2::ggsave(file.path(output_root, "figures", paste0(spec$name, ".png")), spec$plot, width = spec$width, height = spec$height, units = "in", dpi = 180)
}

paths <- c(
  file.path(output_root, "quantile_source_manifest_completed.csv"),
  list.files(file.path(output_root, "tables"), full.names = TRUE),
  list.files(file.path(output_root, "figures"), full.names = TRUE)
)
app_write_csv(data.frame(
  path = paths,
  size_bytes = as.numeric(file.info(paths)$size),
  sha256 = vapply(paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
), file.path(output_root, "artifact_manifest.csv"))
writeLines(c(
  "Full-seven observed-window finalization completed.",
  "The winner is not yet promoted: the held-out forecast window remains blinded until this ranking is frozen.",
  paste("Ranking:", file.path(output_root, "tables", "observed_history_full7_ranking.csv"))
), file.path(output_root, "FINALIZATION_COMPLETE.txt"))
cat(file.path(output_root, "tables", "observed_history_full7_ranking.csv"), "\n")
