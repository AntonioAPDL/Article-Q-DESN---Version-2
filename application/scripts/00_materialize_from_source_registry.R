#!/usr/bin/env Rscript
# Purpose: materialize an article input bundle from the tracked authoritative
# cutoff-source registry. This keeps GloFAS source selection, storage-scale
# conversion, and bundle roots declarative rather than hard-coded in commands.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/authoritative_source_audit.R"))
source(app_path("application/R/authoritative_cutoff_materialization.R"))

app_source_registry_path <- function(cfg, override = NULL) {
  if (!is.null(override) && nzchar(as.character(override))) {
    path <- as.character(override)
    return(if (grepl("^/", path)) path else app_path(path))
  }
  app_config_path(cfg, "source_registry")
}

app_source_registry_select <- function(registry, cutoff_id = "", cutoff_date = "") {
  required <- c(
    "cutoff_id", "cutoff_date", "station_id", "source_root",
    "glofas_source_root", "bundle_root", "expected_retrospective_start",
    "expected_retrospective_end", "expected_glofas_source_id",
    "retrospective_storage_scale", "requirements_path", "enabled"
  )
  app_check_required_columns(registry, required, "authoritative cutoff source registry")
  registry <- registry[app_as_bool_vec(registry$enabled), , drop = FALSE]
  if (!nrow(registry)) stop("No enabled rows are available in the source registry.", call. = FALSE)
  if (nzchar(cutoff_id)) registry <- registry[registry$cutoff_id == cutoff_id, , drop = FALSE]
  if (nzchar(cutoff_date)) registry <- registry[as.Date(registry$cutoff_date) == as.Date(cutoff_date), , drop = FALSE]
  if (nrow(registry) != 1L) {
    stop(
      sprintf(
        "Expected exactly one enabled source-registry row but found %d. Provide --cutoff_id or --cutoff_date.",
        nrow(registry)
      ),
      call. = FALSE
    )
  }
  registry[1L, , drop = FALSE]
}

args <- app_parse_args(list(
  config = "application/config/glofas_discrepancy_mcmc_large_dec25.yaml",
  source_registry = NULL,
  cutoff_id = "",
  cutoff_date = "",
  run_id = NULL,
  overwrite = "true"
))

cfg <- app_read_config(app_path(args$config))
run_dirs <- if (!is.null(args$run_id) && nzchar(as.character(args$run_id))) {
  app_create_run_dirs(cfg, run_id = args$run_id)
} else {
  NULL
}
if (!is.null(run_dirs)) app_stage_start("00_materialize_from_source_registry", run_dirs)

registry_path <- app_source_registry_path(cfg, override = args$source_registry)
registry <- app_read_csv(registry_path)
row <- app_source_registry_select(
  registry,
  cutoff_id = as.character(args$cutoff_id %||% ""),
  cutoff_date = as.character(args$cutoff_date %||% "")
)

result <- tryCatch(
  app_materialize_authoritative_cutoff_bundle(
    source_root = row$source_root[[1L]],
    glofas_source_root = row$glofas_source_root[[1L]],
    cutoff_date = row$cutoff_date[[1L]],
    bundle_root = row$bundle_root[[1L]],
    station_id = row$station_id[[1L]],
    requirements_path = row$requirements_path[[1L]],
    overwrite = app_as_bool(args$overwrite)
  ),
  error = function(e) {
    if (!is.null(run_dirs)) {
      msg <- conditionMessage(e)
      app_write_csv(data.frame(issue = msg), file.path(run_dirs$logs, "source_registry_materialization_issues.csv"))
      app_stage_done("00_materialize_from_source_registry", run_dirs, status = "failed", message = msg)
    }
    stop(conditionMessage(e), call. = FALSE)
  }
)

selected <- row
selected$source_registry <- app_prefer_repo_relative_path(registry_path)
selected$materialized_bundle_root <- app_prefer_repo_relative_path(result$bundle_root)
selected$materialized_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
if (!is.null(run_dirs)) {
  app_write_csv(selected, file.path(run_dirs$manifest, "authoritative_cutoff_source_selected.csv"))
  app_write_csv(result$summary, file.path(run_dirs$tables, "authoritative_materialization_summary.csv"))
  app_stage_done("00_materialize_from_source_registry", run_dirs)
}

cat(result$bundle_root, "\n")
