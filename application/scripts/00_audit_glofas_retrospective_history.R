#!/usr/bin/env Rscript
# Purpose: verify that the materialized GloFAS retrospective uses the audited
# long-history histfix source and agrees with the previous short source on the
# dates where both are available.
# Inputs: materialized long-history retrospective and optional overlap
# comparison retrospective.
# Outputs: CSV and text summaries under the requested output directory.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))

args <- app_parse_args(list(
  config = "application/config/glofas_discrepancy_mcmc_large_dec25.yaml",
  source_registry = NULL,
  cutoff_id = "",
  long_path = "application/data_local/frozen_inputs/authoritative_cutoffs/cutoff_date=2022-12-25/glofas/glofas_retrospective.csv",
  overlap_path = "application/data_local/frozen_inputs/authoritative_dec25_2022/glofas/glofas_retrospective.csv",
  cutoff_date = "2022-12-25",
  expected_start = "1987-05-29",
  expected_source_id = "glofas_hist_v31_lisflood_cons",
  tolerance = "1e-8",
  output_dir = "application/runs/glofas_retrospective_history_audit/tables"
))

if (!is.null(args$source_registry) || nzchar(as.character(args$cutoff_id %||% ""))) {
  cfg <- app_read_config(app_path(args$config))
  registry_path <- if (!is.null(args$source_registry) && nzchar(as.character(args$source_registry))) {
    if (grepl("^/", args$source_registry)) args$source_registry else app_path(args$source_registry)
  } else {
    app_config_path(cfg, "source_registry")
  }
  registry <- app_read_csv(registry_path)
  required_registry_cols <- c(
    "cutoff_id", "cutoff_date", "bundle_root", "expected_retrospective_start",
    "expected_glofas_source_id", "overlap_comparison_path", "enabled"
  )
  app_check_required_columns(registry, required_registry_cols, "authoritative cutoff source registry")
  registry <- registry[app_as_bool_vec(registry$enabled), , drop = FALSE]
  if (nzchar(as.character(args$cutoff_id %||% ""))) {
    registry <- registry[registry$cutoff_id == args$cutoff_id, , drop = FALSE]
  }
  if (nrow(registry) != 1L) {
    stop(
      sprintf(
        "Expected exactly one source-registry row for retrospective audit but found %d.",
        nrow(registry)
      ),
      call. = FALSE
    )
  }
  args$long_path <- file.path(registry$bundle_root[[1L]], "glofas", "glofas_retrospective.csv")
  args$overlap_path <- registry$overlap_comparison_path[[1L]]
  args$cutoff_date <- registry$cutoff_date[[1L]]
  args$expected_start <- registry$expected_retrospective_start[[1L]]
  args$expected_source_id <- registry$expected_glofas_source_id[[1L]]
}

long_path <- app_resolve_path(args$long_path, must_work = TRUE)
overlap_path <- if (is.null(args$overlap_path) || !nzchar(as.character(args$overlap_path))) {
  NA_character_
} else {
  app_resolve_path(args$overlap_path, must_work = FALSE)
}
cutoff_date <- as.Date(args$cutoff_date)
expected_start <- as.Date(args$expected_start)
expected_source_id <- as.character(args$expected_source_id)
tolerance <- as.numeric(args$tolerance)
output_dir <- app_resolve_path(args$output_dir, must_work = FALSE)
app_ensure_dir(output_dir)

long <- app_read_csv(long_path)
app_check_required_columns(long, c("date", "source_id", "glofas_streamflow"), "long-history GloFAS retrospective")
long$date <- as.Date(long$date)

history_rows <- list(
  start_date = data.frame(
    check = "long history start date",
    status = if (min(long$date, na.rm = TRUE) <= expected_start) "ok" else "failed",
    detail = sprintf("date_min=%s; expected_start=%s", min(long$date, na.rm = TRUE), expected_start),
    stringsAsFactors = FALSE
  ),
  cutoff_end = data.frame(
    check = "retrospective clipped at cutoff",
    status = if (max(long$date, na.rm = TRUE) <= cutoff_date) "ok" else "failed",
    detail = sprintf("date_max=%s; cutoff_date=%s", max(long$date, na.rm = TRUE), cutoff_date),
    stringsAsFactors = FALSE
  ),
  source_id = data.frame(
    check = "GloFAS source id",
    status = if (all(long$source_id == expected_source_id)) "ok" else "failed",
    detail = paste(unique(long$source_id), collapse = ";"),
    stringsAsFactors = FALSE
  )
)

overlap_summary <- data.frame(
  overlap_path = if (is.na(overlap_path)) NA_character_ else app_prefer_repo_relative_path(overlap_path),
  overlap_rows = 0L,
  overlap_start = NA_character_,
  overlap_end = NA_character_,
  max_abs_difference = NA_real_,
  status = if (file.exists(overlap_path)) "not_run" else "missing_optional",
  stringsAsFactors = FALSE
)

if (!is.na(overlap_path) && file.exists(overlap_path)) {
  old <- app_read_csv(overlap_path)
  app_check_required_columns(old, c("date", "glofas_streamflow"), "overlap GloFAS retrospective")
  old$date <- as.Date(old$date)
  merged <- merge(
    long[, c("date", "glofas_streamflow"), drop = FALSE],
    old[, c("date", "glofas_streamflow"), drop = FALSE],
    by = "date",
    suffixes = c("_long", "_overlap")
  )
  merged <- merged[merged$date <= cutoff_date, , drop = FALSE]
  max_diff <- if (nrow(merged)) {
    max(abs(merged$glofas_streamflow_long - merged$glofas_streamflow_overlap), na.rm = TRUE)
  } else {
    Inf
  }
  overlap_summary <- data.frame(
    overlap_path = app_prefer_repo_relative_path(overlap_path),
    overlap_rows = nrow(merged),
    overlap_start = if (nrow(merged)) as.character(min(merged$date)) else NA_character_,
    overlap_end = if (nrow(merged)) as.character(max(merged$date)) else NA_character_,
    max_abs_difference = max_diff,
    status = if (nrow(merged) && is.finite(max_diff) && max_diff <= tolerance) "ok" else "failed",
    stringsAsFactors = FALSE
  )
  history_rows$overlap <- data.frame(
    check = "overlap agreement with previous short source",
    status = overlap_summary$status,
    detail = sprintf(
      "rows=%s; start=%s; end=%s; max_abs_difference=%.12g; tolerance=%.12g",
      overlap_summary$overlap_rows,
      overlap_summary$overlap_start,
      overlap_summary$overlap_end,
      overlap_summary$max_abs_difference,
      tolerance
    ),
    stringsAsFactors = FALSE
  )
}

audit <- do.call(rbind, history_rows)
profile <- data.frame(
  long_path = app_prefer_repo_relative_path(long_path),
  n_rows = nrow(long),
  date_min = as.character(min(long$date, na.rm = TRUE)),
  date_max = as.character(max(long$date, na.rm = TRUE)),
  source_ids = paste(unique(long$source_id), collapse = ";"),
  streamflow_min = min(long$glofas_streamflow, na.rm = TRUE),
  streamflow_max = max(long$glofas_streamflow, na.rm = TRUE),
  stringsAsFactors = FALSE
)

app_write_csv(audit, file.path(output_dir, "glofas_retrospective_history_audit.csv"))
app_write_csv(profile, file.path(output_dir, "glofas_retrospective_history_profile.csv"))
app_write_csv(overlap_summary, file.path(output_dir, "glofas_retrospective_overlap_summary.csv"))
writeLines(
  c(
    "GloFAS retrospective history audit",
    sprintf("status: %s", if (all(audit$status == "ok")) "ok" else "failed"),
    sprintf("long_path: %s", profile$long_path[[1L]]),
    sprintf("date range: %s to %s", profile$date_min[[1L]], profile$date_max[[1L]]),
    sprintf("rows: %s", profile$n_rows[[1L]]),
    sprintf("overlap status: %s", overlap_summary$status[[1L]])
  ),
  file.path(output_dir, "GLOFAS_RETROSPECTIVE_HISTORY_AUDIT.txt")
)

if (!all(audit$status == "ok")) {
  stop("GloFAS retrospective history audit failed.", call. = FALSE)
}

cat(file.path(output_dir, "glofas_retrospective_history_audit.csv"), "\n")
