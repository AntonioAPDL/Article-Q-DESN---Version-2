#!/usr/bin/env Rscript
# Purpose: promote storage-light GloFAS multi-quantile synthesis outputs into
# article-facing tables/ and figures/ paths.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  config = "local_trackers/runtime_configs/glofas_reservoir_only_m360_full7_20260607/synthesis_config.yaml",
  synthesis_run_id = "glofas_reservoir_only_m360_full7_20260607_synthesis_final",
  diagnostic_run_id = "glofas_reservoir_only_m360_full7_20260607_diagnostic_figures",
  output_slug = "glofas_reservoir_only_m360_full7_20260607",
  allow_ignored_config = TRUE
))

cfg <- app_read_config(app_path(args$config))
slug <- gsub("[^A-Za-z0-9_.-]+", "_", as.character(args$output_slug)[[1L]])
synth_dirs <- app_create_run_dirs(cfg, run_id = args$synthesis_run_id)
diag_dirs <- app_create_run_dirs(cfg, run_id = args$diagnostic_run_id)

tables_dir <- app_path(cfg$paths$promoted_tables %||% "tables")
figures_dir <- app_path(cfg$paths$promoted_figures %||% "figures")
app_ensure_dir(tables_dir)
app_ensure_dir(file.path(figures_dir, "glofas_application"))
app_ensure_dir(file.path(figures_dir, "glofas_application", "diagnostics"))

synth_generated_dir <- file.path(app_config_path(cfg, "generated_outputs"), basename(synth_dirs$run_dir))
diag_generated_dir <- file.path(app_config_path(cfg, "generated_outputs"), basename(diag_dirs$run_dir))

readiness_path <- file.path(synth_dirs$tables, "launch_readiness_report.csv")
if (!file.exists(readiness_path)) {
  stop(sprintf("Missing synthesis readiness report: %s", readiness_path), call. = FALSE)
}
readiness <- app_read_csv(readiness_path)
if (!all(app_as_bool_vec(readiness$passed))) {
  failed <- readiness[!app_as_bool_vec(readiness$passed), , drop = FALSE]
  stop(sprintf("Refusing to promote synthesis with failed readiness checks: %s", paste(failed$check, collapse = ", ")), call. = FALSE)
}

diag_readiness_path <- file.path(diag_dirs$tables, "diagnostic_readiness_report.csv")
if (!file.exists(diag_readiness_path)) {
  stop(sprintf("Missing diagnostic readiness report: %s", diag_readiness_path), call. = FALSE)
}
diag_readiness <- app_read_csv(diag_readiness_path)
if (!all(app_as_bool_vec(diag_readiness$passed))) {
  failed <- diag_readiness[!app_as_bool_vec(diag_readiness$passed), , drop = FALSE]
  stop(sprintf("Refusing to promote diagnostics with failed checks: %s", paste(failed$check, collapse = ", ")), call. = FALSE)
}

promote_rows <- list()
add_output <- function(role, source, dest, storage_class = "article_table", required = TRUE) {
  promote_rows[[length(promote_rows) + 1L]] <<- data.frame(
    output_role = role,
    source_path = normalizePath(source, mustWork = FALSE),
    promoted_path = normalizePath(dest, mustWork = FALSE),
    storage_class = storage_class,
    required = required,
    stringsAsFactors = FALSE
  )
}

add_table <- function(role, file, dest_name = NULL, required = TRUE) {
  dest_name <- dest_name %||% sprintf("glofas_application_%s__%s.%s", role, slug, tools::file_ext(file))
  add_output(role, file.path(synth_dirs$tables, file), file.path(tables_dir, dest_name), "article_table", required)
}

add_diag_table <- function(role, file, dest_name = NULL, required = TRUE) {
  dest_name <- dest_name %||% sprintf("glofas_application_%s__%s.%s", role, slug, tools::file_ext(file))
  add_output(role, file.path(diag_dirs$tables, file), file.path(tables_dir, dest_name), "diagnostic_table", required)
}

add_figure <- function(role, source, dest_name, storage_class = "article_figure", required = TRUE) {
  add_output(role, source, file.path(figures_dir, "glofas_application", dest_name), storage_class, required)
}

add_diag_figure <- function(role, file, required = TRUE) {
  add_output(
    role,
    file.path(diag_generated_dir, "figures", file),
    file.path(figures_dir, "glofas_application", "diagnostics", sprintf("%s__%s.pdf", tools::file_path_sans_ext(file), slug)),
    "diagnostic_figure",
    required
  )
}

add_output(
  "score_summary_tex",
  file.path(synth_generated_dir, "glofas_application_score_summary.tex"),
  file.path(tables_dir, sprintf("glofas_application_score_summary__%s.tex", slug)),
  "article_table",
  TRUE
)
add_output("score_summary_csv", file.path(synth_dirs$tables, "score_summary.csv"), file.path(tables_dir, sprintf("glofas_application_score_summary__%s.csv", slug)))
add_table("post_fit_metrics_by_model", "post_fit_metrics_by_model.csv")
add_table("post_fit_metrics_by_horizon", "post_fit_metrics_by_horizon.csv")
add_output(
  "post_fit_forecast_window_band_check",
  file.path(synth_dirs$tables, "prediction_quantiles_synthesized.csv"),
  file.path(tables_dir, sprintf("glofas_application_forecast_window_band_check__%s.csv", slug))
)
add_output(
  "post_fit_forecast_window_band_check_uncalibrated",
  file.path(synth_dirs$tables, "prediction_quantiles_synthesized_uncalibrated.csv"),
  file.path(tables_dir, sprintf("glofas_application_forecast_window_band_check_uncalibrated__%s.csv", slug)),
  "diagnostic_table",
  FALSE
)
add_output(
  "spread_calibration_manifest",
  file.path(synth_dirs$tables, "spread_calibration_manifest.csv"),
  file.path(tables_dir, sprintf("glofas_application_spread_calibration_manifest__%s.csv", slug)),
  "provenance_snapshot",
  FALSE
)
add_output(
  "post_fit_parameter_summary",
  file.path(diag_dirs$tables, "vb_convergence_runtime_summary.csv"),
  file.path(tables_dir, sprintf("glofas_application_post_fit_parameter_summary__%s.csv", slug))
)
add_output(
  "post_fit_trace_summary",
  file.path(diag_dirs$tables, "vb_convergence_runtime_summary.csv"),
  file.path(tables_dir, sprintf("glofas_application_post_fit_trace_summary__%s.csv", slug))
)
add_table("launch_readiness_report", "launch_readiness_report.csv")
add_table("launch_readiness_summary", "launch_readiness_summary.txt")
add_table("quantile_synthesis_diagnostic_summary", "quantile_synthesis_diagnostic_summary.csv")
add_table("score_by_quantile", "score_by_quantile.csv")
add_table("score_by_interval", "score_by_interval.csv")
add_table("score_by_crps", "score_by_crps.csv")
add_table("synthesis_source_readiness", "synthesis_source_readiness.csv")
add_table("qdesn_discrepancy_fit_diagnostics_synthesis", "qdesn_discrepancy_fit_diagnostics.csv")
add_table("qdesn_discrepancy_vb_iteration_timing", "qdesn_discrepancy_vb_iteration_timing.csv", required = FALSE)
add_diag_table("diagnostic_readiness_report", "diagnostic_readiness_report.csv")
add_diag_table("score_relative_improvement", "score_relative_improvement.csv")
add_diag_table("interval_score_coverage_summary", "interval_score_coverage_summary.csv")
add_diag_table("isotonic_adjustment_summary", "isotonic_adjustment_summary.csv")
add_diag_table("vb_convergence_runtime_summary", "vb_convergence_runtime_summary.csv")

add_output(
  "run_config_yaml",
  file.path(synth_dirs$manifest, "run_config.yaml"),
  file.path(tables_dir, sprintf("glofas_application_run_config__%s.yaml", slug)),
  "provenance_snapshot"
)
add_output("qdesn_discrepancy_fit_manifest", file.path(synth_dirs$tables, "fit_status.csv"), file.path(tables_dir, sprintf("glofas_application_fit_manifest__%s.csv", slug)), "provenance_snapshot")
add_output("qdesn_discrepancy_fit_diagnostics", file.path(synth_dirs$tables, "qdesn_discrepancy_fit_diagnostics.csv"), file.path(tables_dir, sprintf("glofas_application_fit_diagnostics__%s.csv", slug)), "provenance_snapshot")

add_figure(
  "discrepancy_corrected_quantile_paths",
  file.path(synth_generated_dir, "figures", "glofas_qdesn_discrepancy_corrected_quantile_paths.pdf"),
  sprintf("glofas_qdesn_discrepancy_corrected_quantile_paths__%s.pdf", slug)
)
add_figure(
  "discrepancy_draws_by_horizon",
  file.path(synth_generated_dir, "figures", "glofas_qdesn_discrepancy_draws_by_horizon.pdf"),
  sprintf("glofas_qdesn_discrepancy_draws_by_horizon__%s.pdf", slug)
)
add_diag_figure_by_suffix <- function(role, suffix, required = TRUE) {
  matches <- list.files(file.path(diag_generated_dir, "figures"), pattern = paste0(suffix, "$"), full.names = FALSE)
  if (!length(matches)) {
    if (required) {
      add_output(
        role,
        file.path(diag_generated_dir, "figures", suffix),
        file.path(figures_dir, "glofas_application", "diagnostics", sprintf("%s__%s.pdf", tools::file_path_sans_ext(suffix), slug)),
        "diagnostic_figure",
        TRUE
      )
    }
    return(invisible(NULL))
  }
  add_diag_figure(role, matches[[1L]], required = required)
  invisible(matches[[1L]])
}

add_diag_figure_by_suffix("post_fit__forecast_window_pm30", "qdesn_synthesized_bands.pdf")
add_diag_figure_by_suffix("post_fit_diagnostic_traces", "vb_parameter_change_traces.pdf")
for (file in list.files(file.path(diag_generated_dir, "figures"), pattern = "[.]pdf$", full.names = FALSE)) {
  role <- paste0("diagnostic_", tools::file_path_sans_ext(file))
  if (!role %in% vapply(promote_rows, function(x) x$output_role[[1L]], character(1L))) {
    add_diag_figure(role, file, required = TRUE)
  }
}

promote_map <- do.call(rbind, promote_rows)
missing <- promote_map[app_as_bool_vec(promote_map$required) & !file.exists(promote_map$source_path), , drop = FALSE]
if (nrow(missing)) {
  stop(sprintf("Missing required promotion source files: %s", paste(missing$source_path, collapse = "; ")), call. = FALSE)
}
promote_map <- promote_map[file.exists(promote_map$source_path), , drop = FALSE]
for (dir in unique(dirname(promote_map$promoted_path))) app_ensure_dir(dir)
for (i in seq_len(nrow(promote_map))) {
  ok <- file.copy(promote_map$source_path[[i]], promote_map$promoted_path[[i]], overwrite = TRUE, copy.date = TRUE)
  if (!isTRUE(ok)) stop(sprintf("Failed to promote %s", promote_map$source_path[[i]]), call. = FALSE)
}

engine_sha <- as.character(cfg$dependencies$qdesn_engine_required_commit %||% NA_character_)
manifest <- data.frame(
  output_role = promote_map$output_role,
  storage_class = promote_map$storage_class,
  promoted_path = promote_map$promoted_path,
  source_path = promote_map$source_path,
  run_id = basename(synth_dirs$run_dir),
  diagnostic_run_id = basename(diag_dirs$run_dir),
  config_path = normalizePath(cfg$.__config_path__, mustWork = FALSE),
  article_git_sha = app_git_sha(short = FALSE) %||% NA_character_,
  engine_repo_sha = engine_sha,
  engine_repo_sha_source = "synthesis_config.dependencies.qdesn_engine_required_commit",
  engine_repo_sha_field = "dependencies.qdesn_engine_required_commit",
  source_sha256 = vapply(promote_map$source_path, app_sha256_file, character(1L)),
  promoted_sha256 = vapply(promote_map$promoted_path, app_sha256_file, character(1L)),
  file_size_bytes = file.info(promote_map$promoted_path)$size,
  promoted_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  stringsAsFactors = FALSE
)
manifest_path <- file.path(tables_dir, sprintf("glofas_application_promotion_manifest__%s.csv", slug))
app_write_csv(manifest, manifest_path)
cat(manifest_path, "\n")
