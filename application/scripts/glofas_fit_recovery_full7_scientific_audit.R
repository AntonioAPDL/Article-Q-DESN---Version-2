#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_fit_recovery.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/glofas_fit_recovery_mechanism_audit.R"))
source(app_path("application/R/glofas_fit_recovery_selection.R"))
source(app_path("application/R/glofas_fit_recovery_scientific_audit.R"))

args <- app_parse_args(list(
  current_root = "local_trackers/runtime_configs/glofas_fit_recovery_transition_full7_20260808",
  archive_runs_root = "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/runs",
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_full7_scientific_audit_20260809",
  cutoff_date = "2022-12-25",
  windows = "all,1000,500,200,100,50",
  top_n = 20
))
resolve_repo <- function(path, must_work = FALSE) {
  normalizePath(if (grepl("^/", path)) path else app_path(path), mustWork = must_work)
}
current_root <- resolve_repo(args$current_root, TRUE)
archive_runs_root <- normalizePath(args$archive_runs_root, mustWork = TRUE)
output_root <- resolve_repo(args$output_root, FALSE)
cutoff_date <- as.Date(args$cutoff_date)
windows <- trimws(strsplit(as.character(args$windows), ",", fixed = TRUE)[[1L]])
windows <- vapply(windows, function(x) if (tolower(x) == "all") NA_integer_ else as.integer(x), integer(1L))
top_n <- as.integer(args$top_n)
if (!is.finite(top_n) || top_n < 1L) stop("top_n must be a positive integer.", call. = FALSE)
for (dir in c("tables", "figures", "manifest")) app_ensure_dir(file.path(output_root, dir))

comparator_ids <- c(
  "stage_ae_d16w80_m1000_tau1em3_obs1000",
  "stage_ae_d32w50_m1000_tau1em3_forecast",
  "stage_ae_d32w50_m2000_tau1em3_obs200"
)
comparator_prefix <- "glofas_stage_ae_full7_shortlist_20260727_"
comparator_paths <- file.path(
  archive_runs_root,
  paste0(comparator_prefix, comparator_ids, "_p50_pre_cutoff_history_all"),
  "tables", "pre_cutoff_quantile_history.csv"
)
current_history_path <- file.path(current_root, "tables", "observed_history_full7_long.csv")
evidence_manifest <- data.frame(
  candidate_id = c("fr09_persistence_innovation", comparator_ids),
  source_role = c("current_transition_candidate", rep("historical_available_comparator", length(comparator_ids))),
  history_format = c("selection_long", rep("pre_cutoff_quantile_history", length(comparator_ids))),
  history_path = c(current_history_path, comparator_paths),
  stringsAsFactors = FALSE
)
if (any(!file.exists(evidence_manifest$history_path))) {
  stop(sprintf(
    "Scientific-audit inputs are missing: %s.",
    paste(evidence_manifest$history_path[!file.exists(evidence_manifest$history_path)], collapse = ", ")
  ), call. = FALSE)
}
evidence_manifest$history_path <- vapply(evidence_manifest$history_path, normalizePath, character(1L), mustWork = TRUE)
evidence_manifest$history_sha256 <- vapply(evidence_manifest$history_path, app_sha256_file, character(1L))
evidence_manifest <- app_glofas_scientific_validate_manifest(evidence_manifest)
app_write_csv(evidence_manifest, file.path(output_root, "manifest", "scientific_evidence_manifest.csv"))

common <- app_glofas_scientific_common_history(evidence_manifest, cutoff_date = cutoff_date)
synthesized <- app_glofas_scientific_apply_isotonic(common$history)
scores <- app_glofas_scientific_score_windows(
  synthesized$history, synthesized$crossing, windows = windows
)
score_distribution <- app_glofas_scientific_score_distribution(scores$by_date)
tail <- app_glofas_scientific_tail_audit(synthesized$history)

current_sources <- app_read_csv(file.path(current_root, "quantile_source_manifest_completed.csv"))
p95_source <- current_sources[abs(as.numeric(current_sources$quantile_level) - 0.95) < 1e-12, , drop = FALSE]
if (nrow(p95_source) != 1L) stop("Current full-seven evidence does not identify one p95 source.", call. = FALSE)
p95_history_path <- normalizePath(p95_source$history_path[[1L]], mustWork = TRUE)
p95_history <- app_read_csv(p95_history_path)
component <- app_glofas_scientific_component_audit(
  p95_history, candidate_id = "fr09_persistence_innovation"
)
fit_manifest_path <- file.path(p95_source$run_dir[[1L]], "manifest", "qdesn_discrepancy_fit_manifest.csv")
fit_manifest <- app_read_csv(fit_manifest_path)
if (nrow(fit_manifest) != 1L || fit_manifest$status[[1L]] != "completed") {
  stop("The retained p95 fit manifest is missing or incomplete.", call. = FALSE)
}
fit_path <- resolve_repo(fit_manifest$fit_object[[1L]], TRUE)
design_path <- resolve_repo(fit_manifest$design_object[[1L]], TRUE)
p95_source_manifest <- data.frame(
  artifact = c("component_history", "fit_object", "design_object", "fit_manifest"),
  path = c(p95_history_path, fit_path, design_path, normalizePath(fit_manifest_path, mustWork = TRUE)),
  stringsAsFactors = FALSE
)
p95_source_manifest$sha256 <- vapply(p95_source_manifest$path, app_sha256_file, character(1L))
p95_source_manifest$size_bytes <- as.numeric(file.info(p95_source_manifest$path)$size)
app_write_csv(p95_source_manifest, file.path(output_root, "manifest", "p95_component_source_manifest.csv"))

message("[scientific-audit] loading retained p95 fit and design for attribution")
fit <- readRDS(fit_path)
design <- readRDS(design_path)
contribution <- app_glofas_scientific_contribution_audit(
  fit, design, component$detail,
  candidate_id = "fr09_persistence_innovation", top_n = top_n
)
rm(fit, design)
invisible(gc())

gate <- app_glofas_scientific_promotion_gate(
  candidate_id = "fr09_persistence_innovation",
  score_distribution = score_distribution,
  tail_summary = tail$summary,
  component_summary = component$summary,
  contribution_alignment = contribution$alignment
)

all_scores <- score_distribution[
  score_distribution$window == "all" & score_distribution$estimate_mode == "isotonic",
  c("candidate_id", "score_scale", "n_dates", "score_mean", "score_median", "score_q95", "score_q99", "score_max"),
  drop = FALSE
]
original <- all_scores[all_scores$score_scale == "original", , drop = FALSE]
names(original)[-(1:2)] <- paste0("original_", names(original)[-(1:2)])
log1p <- all_scores[all_scores$score_scale == "log1p", , drop = FALSE]
names(log1p)[-(1:2)] <- paste0("log1p_", names(log1p)[-(1:2)])
ranking <- merge(original[, -2L, drop = FALSE], log1p[, -2L, drop = FALSE], by = "candidate_id", all = TRUE)
ranking <- merge(
  ranking,
  tail$summary[tail$summary$estimate_mode == "independent", c(
    "candidate_id", "fitted_max", "fitted_max_to_observed_max_ratio",
    "n_above_20x_observed_max"
  ), drop = FALSE],
  by = "candidate_id", all.x = TRUE
)
ranking <- ranking[order(ranking$original_score_mean, ranking$original_score_q95, ranking$log1p_score_mean), , drop = FALSE]
ranking$scientific_rank <- seq_len(nrow(ranking))
ranking$comparison_scope <- "exact_common_10000_date_pre_cutoff_support"
ranking$promotion_authority <- ranking$candidate_id == "fr09_persistence_innovation"
ranking <- ranking[, c("scientific_rank", setdiff(names(ranking), "scientific_rank")), drop = FALSE]

app_write_csv(common$date_audit, file.path(output_root, "tables", "common_date_alignment_audit.csv"))
app_write_csv(scores$summary, file.path(output_root, "tables", "dual_scale_scores.csv"))
app_write_csv(scores$by_quantile, file.path(output_root, "tables", "dual_scale_scores_by_quantile.csv"))
app_write_csv(scores$by_date, file.path(output_root, "tables", "dual_scale_scores_by_date.csv"))
app_write_csv(score_distribution, file.path(output_root, "tables", "dual_scale_score_distribution.csv"))
app_write_csv(ranking, file.path(output_root, "tables", "dual_scale_common_support_ranking.csv"))
app_write_csv(synthesized$crossing, file.path(output_root, "tables", "crossing_by_date.csv"))
app_write_csv(tail$summary, file.path(output_root, "tables", "p95_tail_summary.csv"))
app_write_csv(tail$excursions, file.path(output_root, "tables", "p95_tail_excursions.csv"))
app_write_csv(component$summary, file.path(output_root, "tables", "current_p95_component_summary.csv"))
app_write_csv(component$detail, file.path(output_root, "tables", "current_p95_component_detail.csv"))
app_write_csv(contribution$alignment, file.path(output_root, "tables", "current_p95_contribution_alignment.csv"))
app_write_csv(contribution$contributions, file.path(output_root, "tables", "current_p95_top_excursion_contributions.csv"))
app_write_csv(contribution$group_summary, file.path(output_root, "tables", "current_p95_feature_group_summary.csv"))
app_write_csv(contribution$feature_shift, file.path(output_root, "tables", "current_p95_top_excursion_feature_shift.csv"))
app_write_csv(gate, file.path(output_root, "tables", "scientific_promotion_gate.csv"))

if (!requireNamespace("ggplot2", quietly = TRUE) || !isTRUE(capabilities("cairo"))) {
  stop("Scientific-audit figures require ggplot2 and Cairo graphics.", call. = FALSE)
}
theme_audit <- ggplot2::theme_bw(base_size = 9) + ggplot2::theme(
  panel.grid.minor = ggplot2::element_blank(),
  legend.position = "bottom",
  strip.background = ggplot2::element_rect(fill = "gray94", color = "gray75")
)
rank_plot <- ggplot2::ggplot(
  ranking,
  ggplot2::aes(reorder(candidate_id, original_score_mean), original_score_mean,
               fill = promotion_authority)
) +
  ggplot2::geom_col(width = 0.68) +
  ggplot2::coord_flip() +
  ggplot2::scale_fill_manual(values = c(`TRUE` = "#1F5A94", `FALSE` = "#A7ADB4"), guide = "none") +
  ggplot2::labs(
    title = "Common-support observed-history distributional fit",
    subtitle = "Original streamflow scale; identical 10,000-date support and isotonic seven-quantile grid",
    x = NULL, y = "Mean grid CRPS approximation"
  ) + theme_audit
original_dates <- scores$by_date[
  scores$by_date$score_scale == "original" & scores$by_date$window == "all" &
    scores$by_date$estimate_mode == "isotonic",
  , drop = FALSE
]
distribution_plot <- ggplot2::ggplot(
  original_dates,
  ggplot2::aes(integrated_quantile_score, color = candidate_id)
) +
  ggplot2::stat_ecdf(linewidth = 0.6) +
  ggplot2::scale_x_log10() +
  ggplot2::labs(
    title = "Distribution of date-specific grid scores",
    subtitle = "Original streamflow scale; logarithmic horizontal axis exposes both routine and extreme errors",
    x = "Date-specific grid CRPS approximation", y = "Empirical cumulative probability", color = "Candidate"
  ) + theme_audit
tail_plot_data <- tail$excursions[tail$excursions$estimate_mode == "independent", , drop = FALSE]
tail_plot_data <- do.call(rbind, lapply(split(tail_plot_data, tail_plot_data$candidate_id), function(x) head(x, 20L)))
tail_plot <- ggplot2::ggplot(
  tail_plot_data,
  ggplot2::aes(target_date, fitted_original, color = candidate_id)
) +
  ggplot2::geom_point(size = 1.35, alpha = 0.82) +
  ggplot2::geom_hline(
    data = unique(tail_plot_data[c("candidate_id", "observed_max")]),
    ggplot2::aes(yintercept = observed_max), linetype = 2, color = "gray45"
  ) +
  ggplot2::scale_y_log10() +
  ggplot2::facet_wrap(~ candidate_id, scales = "free_x") +
  ggplot2::labs(
    title = "Largest fitted p95 excursions beyond the historical maximum",
    subtitle = "Dashed line is each candidate's observed historical maximum",
    x = NULL, y = "Fitted streamflow quantile (logarithmic scale)", color = "Candidate"
  ) + theme_audit + ggplot2::theme(legend.position = "none")
worst_date <- component$detail$target_date[[1L]]
worst_contribution <- contribution$contributions[
  contribution$contributions$target_date == worst_date,
  , drop = FALSE
]
contribution_plot <- ggplot2::ggplot(
  worst_contribution,
  ggplot2::aes(reorder(feature_group, contribution), contribution, fill = contribution < 0)
) +
  ggplot2::geom_col(width = 0.68) +
  ggplot2::coord_flip() +
  ggplot2::facet_wrap(~ component, ncol = 2L, scales = "free_y") +
  ggplot2::scale_fill_manual(values = c(`TRUE` = "#B9473D", `FALSE` = "#3977A8"), guide = "none") +
  ggplot2::labs(
    title = sprintf("Two-block readout attribution at the largest p95 excursion (%s)", worst_date),
    subtitle = "Matched reference and discrepancy contributions reveal cancellation through q_g = q_y + d_g",
    x = NULL, y = "Contribution on the log1p scale"
  ) + theme_audit
for (spec in list(
  list(name = "dual_scale_common_support_ranking", plot = rank_plot, width = 8.7, height = 4.8),
  list(name = "original_scale_score_ecdf", plot = distribution_plot, width = 9.2, height = 5.4),
  list(name = "p95_tail_excursions", plot = tail_plot, width = 10.2, height = 6.6),
  list(name = "current_p95_worst_excursion_contributions", plot = contribution_plot, width = 8.2, height = 4.8)
)) {
  app_glofas_selection_save_plot(spec$plot, file.path(output_root, "figures", paste0(spec$name, ".pdf")), spec$width, spec$height)
  app_glofas_selection_save_plot(spec$plot, file.path(output_root, "figures", paste0(spec$name, ".png")), spec$width, spec$height)
}

decision_file <- if (isTRUE(gate$scientific_promotion_gate_pass[[1L]])) {
  file.path(output_root, "ELIGIBLE_FOR_HUMAN_REVIEW.txt")
} else {
  file.path(output_root, "PROMOTION_BLOCKED.txt")
}
writeLines(c(
  sprintf("Decision: %s", gate$decision[[1L]]),
  sprintf("Candidate: %s", gate$candidate_id[[1L]]),
  sprintf("Failed gates: %s", gate$failed_gates[[1L]]),
  "No automatic promotion or article update is authorized.",
  "The held-out forecast result was not used to select or repair this candidate."
), decision_file)

provenance <- data.frame(
  field = c(
    "audited_at", "repo_head", "audit_script_sha256", "audit_helper_sha256",
    "selection_helper_sha256", "mechanism_helper_sha256", "evidence_manifest_sha256",
    "p95_source_manifest_sha256", "decision", "failed_gates"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)[[1L]],
    app_sha256_file(app_path("application/scripts/glofas_fit_recovery_full7_scientific_audit.R")),
    app_sha256_file(app_path("application/R/glofas_fit_recovery_scientific_audit.R")),
    app_sha256_file(app_path("application/R/glofas_fit_recovery_selection.R")),
    app_sha256_file(app_path("application/R/glofas_fit_recovery_mechanism_audit.R")),
    app_sha256_file(file.path(output_root, "manifest", "scientific_evidence_manifest.csv")),
    app_sha256_file(file.path(output_root, "manifest", "p95_component_source_manifest.csv")),
    gate$decision[[1L]], gate$failed_gates[[1L]]
  ),
  stringsAsFactors = FALSE
)
app_write_csv(provenance, file.path(output_root, "manifest", "scientific_audit_provenance.csv"))
artifact_paths <- c(
  list.files(file.path(output_root, "tables"), full.names = TRUE),
  list.files(file.path(output_root, "figures"), full.names = TRUE),
  list.files(file.path(output_root, "manifest"), full.names = TRUE),
  decision_file
)
artifact_paths <- artifact_paths[basename(artifact_paths) != "artifact_manifest.csv"]
app_write_csv(data.frame(
  path = normalizePath(artifact_paths, mustWork = TRUE),
  size_bytes = as.numeric(file.info(artifact_paths)$size),
  sha256 = vapply(artifact_paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
), file.path(output_root, "manifest", "artifact_manifest.csv"))
cat(normalizePath(decision_file, mustWork = TRUE), "\n")
