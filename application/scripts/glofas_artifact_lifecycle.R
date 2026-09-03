#!/usr/bin/env Rscript
# Audited, task-scoped dry-run or execution of GloFAS heavy-artifact cleanup.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/artifact_hygiene.R"))

args <- app_parse_args(list(
  runs_root = "",
  delete_run_ids = "",
  protected_run_ids = "",
  execute = "false",
  manifest = ""
))
if (!nzchar(args$runs_root)) stop("--runs-root is required.", call. = FALSE)
runs_root <- app_resolve_path(args$runs_root, must_work = TRUE)
split_ids <- function(x) trimws(strsplit(as.character(x %||% ""), ",", fixed = TRUE)[[1L]])
delete_ids <- split_ids(args$delete_run_ids)
delete_ids <- delete_ids[nzchar(delete_ids)]
protected_ids <- split_ids(args$protected_run_ids)
protected_ids <- protected_ids[nzchar(protected_ids)]
manifest <- app_glofas_heavy_artifact_manifest(
  runs_root = runs_root,
  delete_run_ids = delete_ids,
  protected_run_ids = protected_ids
)
result <- app_glofas_execute_artifact_manifest(
  manifest,
  runs_root = runs_root,
  execute = app_as_bool(args$execute)
)
manifest_path <- if (nzchar(args$manifest)) {
  app_resolve_path(args$manifest, must_work = FALSE)
} else {
  file.path(runs_root, sprintf(
    "glofas_artifact_cleanup_%s.csv",
    format(Sys.time(), "%Y%m%d_%H%M%S")
  ))
}
app_write_csv(result, manifest_path)
cat(normalizePath(manifest_path, mustWork = TRUE), "\n")
