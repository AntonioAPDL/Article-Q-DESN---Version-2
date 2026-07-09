# Promotion helpers for storage-light application outputs.

app_path_is_git_ignored <- function(path, root = app_repo_root()) {
  rel <- app_root_relative_path(path, root = root)
  if (is.na(rel) || !nzchar(rel)) return(FALSE)
  status <- suppressWarnings(system2(
    "git",
    c("-C", root, "check-ignore", "-q", "--", rel),
    stdout = FALSE,
    stderr = FALSE
  ))
  identical(status, 0L)
}

app_assert_promotion_config_allowed <- function(cfg, config_path, allow_ignored_config = FALSE) {
  final_launch <- app_as_bool(cfg$execution$final_launch$enabled %||% FALSE)
  ignored <- app_path_is_git_ignored(config_path)
  if (final_launch && ignored && !app_as_bool(allow_ignored_config)) {
    stop(
      paste(
        "Refusing final promotion from an ignored config path:",
        app_prefer_repo_relative_path(config_path),
        "Copy the selected config into application/config/ or pass",
        "--allow_ignored_config true for an explicit local-only promotion."
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

app_build_promotion_provenance_map <- function(run_dirs, article_tables_dir, slug) {
  data.frame(
    role = c(
      "run_config_yaml",
      "model_grid_used",
      "quantile_grid_used",
      "input_manifest_used",
      "qdesn_discrepancy_fit_manifest",
      "qdesn_discrepancy_design_summary",
      "qdesn_discrepancy_fit_diagnostics",
      "qdesn_discrepancy_prediction_design_summary"
    ),
    source = c(
      file.path(run_dirs$manifest, "run_config.yaml"),
      file.path(run_dirs$manifest, "model_grid_used.csv"),
      file.path(run_dirs$manifest, "quantile_grid_used.csv"),
      file.path(run_dirs$manifest, "input_manifest_used.csv"),
      file.path(run_dirs$manifest, "qdesn_discrepancy_fit_manifest.csv"),
      file.path(run_dirs$tables, "qdesn_discrepancy_design_summary.csv"),
      file.path(run_dirs$tables, "qdesn_discrepancy_fit_diagnostics.csv"),
      file.path(run_dirs$tables, "qdesn_discrepancy_prediction_design_summary.csv")
    ),
    dest = c(
      file.path(article_tables_dir, sprintf("glofas_application_run_config__%s.yaml", slug)),
      file.path(article_tables_dir, sprintf("glofas_application_model_grid_used__%s.csv", slug)),
      file.path(article_tables_dir, sprintf("glofas_application_quantile_grid_used__%s.csv", slug)),
      file.path(article_tables_dir, sprintf("glofas_application_input_manifest_used__%s.csv", slug)),
      file.path(article_tables_dir, sprintf("glofas_application_fit_manifest__%s.csv", slug)),
      file.path(article_tables_dir, sprintf("glofas_application_design_summary__%s.csv", slug)),
      file.path(article_tables_dir, sprintf("glofas_application_fit_diagnostics__%s.csv", slug)),
      file.path(article_tables_dir, sprintf("glofas_application_prediction_design_summary__%s.csv", slug))
    ),
    storage_class = "provenance_snapshot",
    required = c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
    stringsAsFactors = FALSE
  )
}
