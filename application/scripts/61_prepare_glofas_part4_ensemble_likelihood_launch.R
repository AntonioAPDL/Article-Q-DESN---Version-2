#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/glofas_part4_ensemble_likelihood_contract.R"))

args <- app_parse_args(list(
  base_config = "application/config/glofas_latent_path_al_vb_dec25_main.yaml",
  anchor_manifest = "",
  run_label = paste0("glofas_part4_ensemble_likelihood_deferred_", format(Sys.time(), "%Y%m%d_%H%M%S")),
  runtime_root = "",
  require_frozen = "true",
  allow_forbidden_sources = "false",
  write_candidate_configs = "true",
  dry_run = "true"
))

run_label <- as.character(args$run_label)[[1L]]
if (!nzchar(run_label) || grepl("[^A-Za-z0-9_.-]", run_label)) {
  stop("run_label must be path-safe.", call. = FALSE)
}
runtime_root <- as.character(args$runtime_root)[[1L]]
if (!nzchar(runtime_root)) {
  runtime_root <- file.path("local_trackers", "runtime_configs", run_label)
}

bundle <- app_glofas_part4_prepare_bundle(
  base_config_path = as.character(args$base_config)[[1L]],
  anchor_manifest_path = as.character(args$anchor_manifest)[[1L]],
  run_label = run_label,
  runtime_root = runtime_root,
  require_frozen = app_as_bool(args$require_frozen),
  allow_forbidden_sources = app_as_bool(args$allow_forbidden_sources),
  dry_run = app_as_bool(args$dry_run),
  write_candidate_configs = app_as_bool(args$write_candidate_configs)
)

cat("Part 4 dry-run launch bundle prepared.\n")
cat(sprintf("Runtime root: %s\n", bundle$metadata$runtime_root))
cat(sprintf("Manifest: %s\n", bundle$metadata$manifest_path))
cat(sprintf("Ready rows: %d\n", bundle$metadata$ready_rows))
cat(sprintf("Blocked rows: %d\n", bundle$metadata$blocked_rows))
cat("No models were launched.\n")
