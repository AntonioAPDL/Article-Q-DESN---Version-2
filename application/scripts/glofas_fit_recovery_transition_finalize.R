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
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_transition_repair_20260807"
))
output_root <- normalizePath(
  if (grepl("^/", args$output_root)) args$output_root else app_path(args$output_root),
  mustWork = TRUE
)

blocked_finalizer <- app_path("application/scripts/glofas_fit_recovery_blocked_finalize.R")
status <- system2(
  file.path(R.home("bin"), "Rscript"),
  c(blocked_finalizer, "--output_root", output_root)
)
if (!identical(as.integer(status), 0L)) {
  stop("The shared blocked-validation finalizer failed.", call. = FALSE)
}

manifest <- app_read_csv(file.path(output_root, "runtime_manifest.csv"))
by_cutoff <- app_read_csv(file.path(output_root, "tables", "blocked_validation_by_cutoff.csv"))
metadata <- unique(manifest[, c(
  "base_candidate_id", "cutoff_id", "glofas_source_id", "validation_role",
  "discrepancy_transition_strategy", "discrepancy_tau0"
), drop = FALSE])
names(metadata)[names(metadata) == "base_candidate_id"] <- "candidate_id"
by_cutoff <- merge(
  by_cutoff, metadata,
  by = c("candidate_id", "cutoff_id"), all.x = TRUE, sort = FALSE
)
if (any(is.na(by_cutoff$validation_role)) || any(is.na(by_cutoff$discrepancy_transition_strategy))) {
  stop("Transition-finalization metadata are incomplete.", call. = FALSE)
}
app_write_csv(by_cutoff, file.path(output_root, "tables", "transition_validation_by_cutoff.csv"))

ranking <- app_glofas_transition_validation_summary(by_cutoff)
app_write_csv(ranking, file.path(output_root, "tables", "transition_validation_ranking.csv"))

paired <- app_glofas_transition_paired_comparison(by_cutoff)
paired <- merge(
  paired,
  unique(metadata[, c("cutoff_id", "glofas_source_id", "validation_role"), drop = FALSE]),
  by = "cutoff_id", all.x = TRUE, sort = FALSE
)
app_write_csv(paired, file.path(output_root, "tables", "transition_paired_comparison.csv"))

plot_data <- by_cutoff[, c(
  "candidate_id", "cutoff_id", "validation_role", "qdesn_check_loss_mean", "raw_check_loss_mean"
), drop = FALSE]
plot_data <- rbind(
  data.frame(
    candidate_id = plot_data$candidate_id,
    cutoff_id = plot_data$cutoff_id,
    validation_role = plot_data$validation_role,
    series = "Q-DESN",
    check_loss = plot_data$qdesn_check_loss_mean,
    stringsAsFactors = FALSE
  ),
  data.frame(
    candidate_id = plot_data$candidate_id,
    cutoff_id = plot_data$cutoff_id,
    validation_role = plot_data$validation_role,
    series = "Raw GloFAS",
    check_loss = plot_data$raw_check_loss_mean,
    stringsAsFactors = FALSE
  )
)
plot_data$cutoff_id <- factor(plot_data$cutoff_id, levels = unique(manifest$cutoff_id))
comparison_plot <- ggplot2::ggplot(
  plot_data,
  ggplot2::aes(cutoff_id, check_loss, fill = series)
) +
  ggplot2::geom_col(position = "dodge", width = 0.72) +
  ggplot2::facet_wrap(~ candidate_id, ncol = 1L, scales = "free_y") +
  ggplot2::scale_fill_manual(values = c("Q-DESN" = "#C23B32", "Raw GloFAS" = "#3B6FB6")) +
  ggplot2::labs(x = NULL, y = "Mean p50 check loss", fill = NULL) +
  ggplot2::theme_bw(base_size = 9) +
  ggplot2::theme(legend.position = "bottom", panel.grid.minor = ggplot2::element_blank())
for (extension in c("pdf", "png")) {
  app_glofas_selection_save_plot(
    comparison_plot,
    file.path(output_root, "figures", paste0("transition_check_loss_comparison.", extension)),
    width = 8.4,
    height = 5.8
  )
}

artifact_paths <- list.files(
  output_root,
  recursive = TRUE,
  full.names = TRUE
)
artifact_paths <- artifact_paths[file.info(artifact_paths)$isdir %in% FALSE]
artifact_paths <- artifact_paths[!grepl("artifact_manifest\\.csv$", artifact_paths)]
app_write_csv(data.frame(
  path = artifact_paths,
  size_bytes = as.numeric(file.info(artifact_paths)$size),
  sha256 = vapply(artifact_paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
), file.path(output_root, "artifact_manifest.csv"))
writeLines(c(
  "Discrepancy-transition blocked validation completed.",
  paste("Primary v3.1 cutoffs:", sum(by_cutoff$validation_role == "primary_v31")),
  paste("Eligible candidates:", sum(ranking$eligible_for_full7_review)),
  "No seven-quantile launch was started automatically.",
  "The supplemental v2.1 replay is reported separately from the primary v3.1 selection gate.",
  paste("Ranking:", file.path(output_root, "tables", "transition_validation_ranking.csv"))
), file.path(output_root, "TRANSITION_FINALIZATION_COMPLETE.txt"))
cat(file.path(output_root, "tables", "transition_validation_ranking.csv"), "\n")
