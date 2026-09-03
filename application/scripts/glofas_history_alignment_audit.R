#!/usr/bin/env Rscript

args_all <- commandArgs(trailingOnly = FALSE)
script_arg <- grep("^--file=", args_all, value = TRUE)[1L]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_history_alignment_audit.R"))

args <- app_parse_args(list(
  fit = NULL,
  design = NULL,
  panel = NULL,
  history = NULL,
  output_dir = NULL,
  recent_n = 200L
))

required_paths <- c(fit = args$fit, design = args$design, panel = args$panel, history = args$history)
if (any(!nzchar(as.character(required_paths))) || is.null(args$output_dir) || !nzchar(as.character(args$output_dir))) {
  stop("Required arguments: --fit, --design, --panel, --history, and --output_dir.", call. = FALSE)
}
required_paths <- stats::setNames(
  normalizePath(unname(required_paths), mustWork = TRUE),
  names(required_paths)
)
output_dir <- normalizePath(args$output_dir, mustWork = FALSE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
recent_n <- as.integer(args$recent_n)
if (!is.finite(recent_n) || recent_n < 2L) stop("--recent_n must be at least 2.", call. = FALSE)

fit <- readRDS(required_paths[["fit"]])
design <- readRDS(required_paths[["design"]])
panel <- readRDS(required_paths[["panel"]])
history <- utils::read.csv(required_paths[["history"]], check.names = FALSE, stringsAsFactors = FALSE)

metrics <- app_glofas_history_alignment_metrics(history)
offset_profile <- app_glofas_history_offset_profile(history)
innovation_diagnostics <- app_glofas_history_innovation_diagnostics(history)
source_audit <- app_glofas_source_panel_alignment_audit(panel, design)
design_audit <- app_glofas_history_design_alignment_audit(design, history)
export_audit <- app_glofas_history_export_reconstruction_audit(fit, design, history, recent_n = recent_n)
tail_table <- app_glofas_history_alignment_tail(history, n = 20L)

metrics_path <- file.path(output_dir, "history_alignment_metrics.csv")
offset_path <- file.path(output_dir, "history_alignment_offset_profile.csv")
innovation_path <- file.path(output_dir, "history_innovation_diagnostics.csv")
source_path <- file.path(output_dir, "source_panel_alignment_audit.csv")
design_path <- file.path(output_dir, "history_design_alignment_audit.csv")
export_path <- file.path(output_dir, "history_export_reconstruction_audit.csv")
tail_path <- file.path(output_dir, "history_alignment_tail.csv")
figure_path <- file.path(output_dir, "history_alignment_diagnostic_recent.pdf")
decision_path <- file.path(output_dir, "history_alignment_decision.csv")

utils::write.csv(metrics, metrics_path, row.names = FALSE)
utils::write.csv(offset_profile, offset_path, row.names = FALSE)
utils::write.csv(innovation_diagnostics, innovation_path, row.names = FALSE)
utils::write.csv(source_audit, source_path, row.names = FALSE)
utils::write.csv(design_audit, design_path, row.names = FALSE)
utils::write.csv(export_audit, export_path, row.names = FALSE)
utils::write.csv(tail_table, tail_path, row.names = FALSE)
app_plot_glofas_history_alignment(history, figure_path, recent_n = recent_n)

recent_metrics <- metrics[metrics$window == "last200", , drop = FALSE]
decision <- data.frame(
  audit_status = if (all(source_audit$passed) && all(design_audit$passed) && all(export_audit$passed)) "passed" else "failed",
  source_panel_alignment_passed = all(source_audit$passed),
  calendar_and_response_alignment_passed = all(design_audit$passed),
  posterior_export_reconstruction_passed = all(export_audit$passed),
  usgs_closest_observed_alignment = recent_metrics$closest_observed_alignment[recent_metrics$series == "usgs"],
  discrepancy_closest_observed_alignment = recent_metrics$closest_observed_alignment[recent_metrics$series == "discrepancy"],
  implementation_or_plot_index_shift_detected = !(all(source_audit$passed) && all(design_audit$passed) && all(export_audit$passed)),
  diagnosis = if (all(source_audit$passed) && all(design_audit$passed) && all(export_audit$passed)) {
    "No calendar, response-stack, posterior-export, or plotting-table shift; fitted paths are persistence-like model behavior."
  } else {
    "At least one alignment identity failed; inspect the failed audit rows before using the figures."
  },
  stringsAsFactors = FALSE
)
utils::write.csv(decision, decision_path, row.names = FALSE)

output_paths <- c(
  metrics_path, offset_path, innovation_path, source_path, design_path,
  export_path, tail_path, figure_path, decision_path
)
manifest <- data.frame(
  role = c("source_fit", "source_design", "source_panel", "source_history", basename(output_paths)),
  path = c(required_paths, output_paths),
  size_bytes = as.numeric(file.info(c(required_paths, output_paths))$size),
  sha256 = vapply(c(required_paths, output_paths), app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
utils::write.csv(manifest, file.path(output_dir, "artifact_manifest.csv"), row.names = FALSE)

if (!all(source_audit$passed) || !all(design_audit$passed) || !all(export_audit$passed)) {
  stop("GloFAS historical alignment audit failed.", call. = FALSE)
}
cat(sprintf("GloFAS historical alignment audit passed. Outputs: %s\n", output_dir))
