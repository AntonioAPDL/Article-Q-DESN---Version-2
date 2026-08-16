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
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_triage_20260731",
  cutoff_date = "2022-12-25",
  windows = "all,1000,500,200,100,50",
  cleanup = FALSE
))
resolve_repo <- function(path) if (grepl("^/", path)) path else app_path(path)
output_root <- normalizePath(resolve_repo(args$output_root), mustWork = TRUE)
cutoff_date <- as.Date(args$cutoff_date)
if (is.na(cutoff_date)) stop("A valid cutoff date is required.", call. = FALSE)
windows <- trimws(strsplit(as.character(args$windows), ",", fixed = TRUE)[[1L]])
windows <- vapply(windows, function(x) if (tolower(x) == "all") NA_integer_ else as.integer(x), integer(1L))

for (dir in c("tables", "figures", "cleanup")) app_ensure_dir(file.path(output_root, dir))
prepared_manifest_path <- file.path(output_root, "quantile_source_manifest_prepared.csv")
source_manifest <- app_glofas_selection_validate_source_manifest(
  app_read_csv(prepared_manifest_path),
  require_complete = FALSE
)

for (i in seq_len(nrow(source_manifest))) {
  fit_object <- as.character(source_manifest$fit_object[[i]])
  run_dir <- as.character(source_manifest$run_dir[[i]])
  history_path <- as.character(source_manifest$history_path[[i]])
  if (!file.exists(file.path(run_dir, ".fit_recovery_complete")) ||
      !file.exists(fit_object) || !file.exists(history_path)) {
    stop(sprintf(
      "Stage A is not complete for %s::%s.",
      source_manifest$candidate_id[[i]], source_manifest$quantile_id[[i]]
    ), call. = FALSE)
  }
  source_manifest$fit_object_sha256[[i]] <- app_sha256_file(fit_object)
  source_manifest$status[[i]] <- "completed"
  warm_path <- as.character(source_manifest$warm_start_source_fit_object[[i]])
  warm_hash <- as.character(source_manifest$warm_start_source_sha256[[i]])
  if (identical(source_manifest$source_kind[[i]], "new_tail_fit")) {
    if (!file.exists(warm_path) || !identical(app_sha256_file(warm_path), warm_hash)) {
      stop(sprintf("Warm-start source changed for %s::%s.", source_manifest$candidate_id[[i]], source_manifest$quantile_id[[i]]), call. = FALSE)
    }
  }
}
completed_manifest_path <- file.path(output_root, "quantile_source_manifest_completed.csv")
app_write_csv(source_manifest, completed_manifest_path)
source_manifest <- app_glofas_selection_validate_source_manifest(source_manifest, require_complete = TRUE)

shortlist <- app_glofas_selection_validate_shortlist(app_read_csv(file.path(output_root, "shortlist_snapshot.csv")))
gate <- app_glofas_selection_fit_gate(source_manifest)
app_write_csv(gate, file.path(output_root, "tables", "fit_gate_audit.csv"))
if (!all(gate$gate_pass)) {
  failed <- paste(gate$candidate_id[!gate$gate_pass], gate$quantile_id[!gate$gate_pass], sep = "::")
  stop(sprintf("Stage A fit gates failed for: %s.", paste(failed, collapse = ", ")), call. = FALSE)
}

combined <- app_glofas_selection_combine_histories(source_manifest, cutoff_date = cutoff_date)
synthesized <- app_glofas_selection_apply_isotonic(combined$history)
scores <- app_glofas_selection_score_windows(
  synthesized$history,
  synthesized$crossing,
  windows = windows
)
ranking <- app_glofas_selection_rank(scores$summary, gate, shortlist)
policy_columns <- c(
  "candidate_id", "covariate_future_policy", "covariate_source_provider",
  "covariate_uses_realized_future", "covariate_deployable"
)
if (!all(policy_columns %in% names(source_manifest))) {
  stop("The Stage A source manifest lacks its covariate-policy audit.", call. = FALSE)
}
policy_audit <- unique(source_manifest[, policy_columns, drop = FALSE])
if (anyDuplicated(policy_audit$candidate_id)) {
  stop("A candidate has inconsistent covariate policies across Stage A quantiles.", call. = FALSE)
}
ranking <- merge(ranking, policy_audit, by = "candidate_id", all.x = TRUE, sort = FALSE)
ranking <- ranking[order(ranking$triage_rank), , drop = FALSE]
ranking$selection_scope <- "in_sample_triage_under_inherited_final_cutoff_covariate_policy"

app_write_csv(combined$date_audit, file.path(output_root, "tables", "history_date_alignment_audit.csv"))
app_write_csv(synthesized$history, file.path(output_root, "tables", "observed_history_quantiles_long.csv"))
app_write_csv(synthesized$crossing, file.path(output_root, "tables", "observed_history_crossing_by_date.csv"))
app_write_csv(scores$summary, file.path(output_root, "tables", "observed_history_distributional_scores.csv"))
app_write_csv(scores$by_quantile, file.path(output_root, "tables", "observed_history_scores_by_quantile.csv"))
app_write_csv(scores$by_date, file.path(output_root, "tables", "observed_history_scores_by_date.csv"))
app_write_csv(ranking, file.path(output_root, "tables", "stage_a_triage_ranking.csv"))

tail_audit <- app_glofas_selection_tail_audit(synthesized$history, upper_level = 0.95)
app_write_csv(tail_audit$summary, file.path(output_root, "tables", "upper_tail_excursion_summary.csv"))
app_write_csv(tail_audit$excursions, file.path(output_root, "tables", "upper_tail_excursions.csv"))

recommendations <- ranking[ranking$advance_eligible, , drop = FALSE]
recommendations <- head(recommendations, 2L)
finalists <- data.frame(
  candidate_id = recommendations$candidate_id,
  triage_rank = recommendations$triage_rank,
  role = recommendations$role,
  covariate_future_policy = recommendations$covariate_future_policy,
  covariate_uses_realized_future = recommendations$covariate_uses_realized_future,
  recommended = TRUE,
  approved_for_blocked_validation = FALSE,
  approved_for_full7 = FALSE,
  tail_review_required = tail_audit$summary$tail_review_required[
    match(recommendations$candidate_id, tail_audit$summary$candidate_id)
  ],
  evidence_path = file.path(output_root, "tables", "stage_a_triage_ranking.csv"),
  notes = "Recommendation only; scientific approval is required before any successor launch.",
  stringsAsFactors = FALSE
)
app_write_csv(finalists, file.path(output_root, "tables", "stage_a_finalists_recommended.csv"))

if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("Stage A finalization requires ggplot2 for the diagnostic figure gate.", call. = FALSE)
}
history_last200 <- do.call(rbind, lapply(split(synthesized$history, synthesized$history$candidate_id), function(x) {
  dates <- tail(sort(unique(as.Date(x$target_date))), 200L)
  x[x$target_date %in% dates, , drop = FALSE]
}))
history_last200$quantile_label <- factor(
  history_last200$quantile_id,
  levels = c("p05", "p50", "p95"),
  labels = c("0.05", "0.50", "0.95")
)
candidate_order <- shortlist$candidate_id
history_last200$candidate_id <- factor(history_last200$candidate_id, levels = candidate_order)
palette <- c("0.05" = "#2563EB", "0.50" = "#111827", "0.95" = "#C2410C")
theme_recovery <- ggplot2::theme_bw(base_size = 9) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    strip.background = ggplot2::element_rect(fill = "gray94", color = "gray75"),
    legend.position = "bottom"
  )

p_raw <- ggplot2::ggplot(history_last200, ggplot2::aes(target_date)) +
  ggplot2::geom_line(ggplot2::aes(y = y_log1p), color = "gray55", linewidth = 0.35) +
  ggplot2::geom_line(
    ggplot2::aes(y = qhat_independent, color = quantile_label),
    linewidth = 0.48
  ) +
  ggplot2::facet_wrap(~ candidate_id, ncol = 2) +
  ggplot2::scale_color_manual(values = palette) +
  ggplot2::labs(
    title = "Independent fitted quantiles over the final 200 pre-cutoff dates",
    subtitle = "Gray: observed transformed USGS streamflow; colored paths: independently fitted quantiles",
    x = NULL, y = "log(1 + streamflow)", color = "Quantile"
  ) + theme_recovery

wide_rows <- lapply(split(history_last200, paste(history_last200$candidate_id, history_last200$target_date)), function(x) {
  x <- x[order(x$quantile_level), , drop = FALSE]
  data.frame(
    candidate_id = x$candidate_id[[1L]],
    target_date = as.Date(x$target_date[[1L]]),
    y_log1p = x$y_log1p[[1L]],
    q05 = x$qhat_isotonic[which.min(x$quantile_level)],
    q50 = x$qhat_isotonic[which.min(abs(x$quantile_level - 0.5))],
    q95 = x$qhat_isotonic[which.max(x$quantile_level)],
    stringsAsFactors = FALSE
  )
})
history_wide <- app_bind_rows_fill(wide_rows)
history_wide$candidate_id <- factor(history_wide$candidate_id, levels = candidate_order)
p_iso <- ggplot2::ggplot(history_wide, ggplot2::aes(target_date)) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = q05, ymax = q95), fill = "#93C5FD", alpha = 0.38) +
  ggplot2::geom_line(ggplot2::aes(y = y_log1p), color = "gray45", linewidth = 0.35) +
  ggplot2::geom_line(ggplot2::aes(y = q50), color = "#111827", linewidth = 0.58) +
  ggplot2::facet_wrap(~ candidate_id, ncol = 2) +
  ggplot2::labs(
    title = "Post-hoc monotone 90% fitted intervals over the final 200 pre-cutoff dates",
    subtitle = "The projection is used only for distributional synthesis; the three quantile models are fitted independently",
    x = NULL, y = "log(1 + streamflow)"
  ) + theme_recovery

ranking_plot <- ranking
ranking_plot$candidate_id <- factor(ranking_plot$candidate_id, levels = rev(ranking$candidate_id))
p_rank <- ggplot2::ggplot(ranking_plot, ggplot2::aes(candidate_id, triage_integrated_quantile_score)) +
  ggplot2::geom_col(fill = "#2563EB", width = 0.68) +
  ggplot2::coord_flip() +
  ggplot2::labs(
    title = "Stage A three-quantile screening score",
    subtitle = "Twice the trapezoidal integrated pinball loss over p = 0.05, 0.50, 0.95; this is not full-grid CRPS",
    x = NULL, y = "Three-quantile integrated score"
  ) + theme_recovery

save_plot <- function(name, plot, width, height) {
  app_glofas_selection_save_plot(plot, file.path(output_root, "figures", paste0(name, ".pdf")), width, height)
  app_glofas_selection_save_plot(plot, file.path(output_root, "figures", paste0(name, ".png")), width, height)
}
save_plot("observed_history_last200_independent_quantiles", p_raw, 10.0, 6.4)
save_plot("observed_history_last200_isotonic_intervals", p_iso, 10.0, 6.4)
save_plot("stage_a_triage_score_comparison", p_rank, 8.0, 4.8)

figure_paths <- list.files(file.path(output_root, "figures"), full.names = TRUE)
finalization_provenance_path <- file.path(output_root, "finalization_provenance.csv")
app_write_csv(data.frame(
  field = c(
    "finalized_at", "repo_head", "finalizer_sha256", "selection_helper_sha256",
    "completed_source_manifest_sha256", "ranking_sha256"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)[[1L]],
    app_sha256_file(app_path("application/scripts/glofas_fit_recovery_triage_finalize.R")),
    app_sha256_file(app_path("application/R/glofas_fit_recovery_selection.R")),
    app_sha256_file(completed_manifest_path),
    app_sha256_file(file.path(output_root, "tables", "stage_a_triage_ranking.csv"))
  ),
  stringsAsFactors = FALSE
), finalization_provenance_path)
artifact_paths <- c(
  completed_manifest_path,
  finalization_provenance_path,
  list.files(file.path(output_root, "tables"), full.names = TRUE),
  figure_paths
)
artifact_manifest <- data.frame(
  path = artifact_paths,
  size_bytes = as.numeric(file.info(artifact_paths)$size),
  sha256 = vapply(artifact_paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
app_write_csv(artifact_manifest, file.path(output_root, "artifact_manifest.csv"))

if (app_as_bool(args$cleanup)) {
  stop(
    "Stage A cleanup is intentionally unavailable during finalization; approve finalists and use the separate guarded cleanup step.",
    call. = FALSE
  )
}

writeLines(c(
  "Stage A finalization completed.",
  "No blocked-validation or full-seven fit was launched.",
  "The integrated score is a three-quantile screening approximation, not full-grid CRPS.",
  paste("Ranking:", file.path(output_root, "tables", "stage_a_triage_ranking.csv")),
  paste("Recommended finalists:", file.path(output_root, "tables", "stage_a_finalists_recommended.csv"))
), file.path(output_root, "FINALIZATION_COMPLETE.txt"))

cat(file.path(output_root, "tables", "stage_a_triage_ranking.csv"), "\n")
