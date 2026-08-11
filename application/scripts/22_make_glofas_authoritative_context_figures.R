#!/usr/bin/env Rscript
# Purpose: rebuild authoritative GloFAS figures with pre-cutoff context and
# every issued ensemble member. This stage reads frozen outputs and does not fit.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/build_application_panel.R"))
source(app_path("application/R/glofas_context_figures.R"))

args <- app_parse_args(list(
  config = "local_trackers/runtime_configs/glofas_fr09_authoritative_full7_20260811/synthesis_config.yaml",
  synthesis_run_id = "glofas_fr09_authoritative_full7_20260811_synthesis_contractfixed",
  observed_history = "tables/glofas_application_cutoff_context_observed_history_source__glofas_fr09_authoritative_full7_20260811.csv",
  run_id = "glofas_fr09_authoritative_full7_20260811_context60_members",
  candidate_id = "fr09_persistence_innovation",
  history_observations = 60L,
  expected_members = 51L,
  figure_prefix = "glofas_fr09_authoritative_full7"
))

resolve_input <- function(path) {
  path <- as.character(path)[[1L]]
  if (grepl("^/", path)) normalizePath(path, mustWork = TRUE) else normalizePath(app_path(path), mustWork = TRUE)
}

cfg <- app_read_config(resolve_input(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = as.character(args$run_id)[[1L]])
generated_dir <- file.path(app_config_path(cfg, "generated_outputs"), basename(run_dirs$run_dir))
figure_dir <- file.path(generated_dir, "figures")
app_ensure_dir(figure_dir)
app_stage_start("authoritative_context_figures", run_dirs)

manifest_path <- app_config_path(cfg, "input_manifest")
schema_path <- app_config_path(cfg, "schema")
manifest <- app_load_input_manifest(manifest_path)
schema <- app_read_yaml(schema_path)
inputs <- app_load_application_inputs(manifest, schema)

synthesis_dirs <- app_create_run_dirs(cfg, run_id = as.character(args$synthesis_run_id)[[1L]])
prediction_path <- file.path(synthesis_dirs$tables, "prediction_quantiles_synthesized.csv")
observed_history_path <- resolve_input(args$observed_history)
predictions <- app_read_csv(prediction_path)
observed_history <- app_read_csv(observed_history_path)

context <- app_prepare_glofas_cutoff_context(
  predictions = predictions,
  observed_history = observed_history,
  reference = inputs$reference_gauge,
  retrospective = inputs$glofas_retrospective,
  ensemble = inputs$glofas_ensemble,
  history_observations = as.integer(args$history_observations),
  expected_members = as.integer(args$expected_members),
  candidate_id = as.character(args$candidate_id)[[1L]],
  transform = as.character(cfg$data$transform$response %||% "log1p")
)

prefix <- gsub("[^A-Za-z0-9_.-]+", "_", as.character(args$figure_prefix)[[1L]])
figures <- c(
  cutoff_context_quantile_paths = file.path(figure_dir, sprintf("%s_cutoff_context_quantile_paths.pdf", prefix)),
  cutoff_context_synthesized_bands = file.path(figure_dir, sprintf("%s_cutoff_context_synthesized_bands.pdf", prefix))
)
app_plot_glofas_context_quantile_paths(context, figures[["cutoff_context_quantile_paths"]])
app_plot_glofas_context_bands(context, figures[["cutoff_context_synthesized_bands"]])

tables <- c(
  cutoff_context_qdesn_quantiles = file.path(run_dirs$tables, "cutoff_context_qdesn_quantiles.csv"),
  cutoff_context_observed_history_source = file.path(run_dirs$tables, "cutoff_context_observed_history_source.csv"),
  cutoff_context_bands = file.path(run_dirs$tables, "cutoff_context_bands.csv"),
  cutoff_context_reference = file.path(run_dirs$tables, "cutoff_context_reference.csv"),
  cutoff_context_glofas_retrospective = file.path(run_dirs$tables, "cutoff_context_glofas_retrospective.csv"),
  cutoff_context_glofas_ensemble_members = file.path(run_dirs$tables, "cutoff_context_glofas_ensemble_members.csv"),
  cutoff_context_glofas_ensemble_summary = file.path(run_dirs$tables, "cutoff_context_glofas_ensemble_summary.csv"),
  cutoff_context_readiness = file.path(run_dirs$tables, "cutoff_context_readiness.csv")
)
app_write_csv(context$quantile_paths, tables[["cutoff_context_qdesn_quantiles"]])
app_write_csv(context$observed_history_source, tables[["cutoff_context_observed_history_source"]])
app_write_csv(context$bands, tables[["cutoff_context_bands"]])
app_write_csv(context$reference, tables[["cutoff_context_reference"]])
app_write_csv(context$retrospective, tables[["cutoff_context_glofas_retrospective"]])
app_write_csv(context$ensemble, tables[["cutoff_context_glofas_ensemble_members"]])
app_write_csv(context$ensemble_summary, tables[["cutoff_context_glofas_ensemble_summary"]])
app_write_csv(context$audit, tables[["cutoff_context_readiness"]])

source_paths <- c(
  config = cfg$.__config_path__,
  input_manifest = manifest_path,
  schema = schema_path,
  predictions = prediction_path,
  observed_history = observed_history_path,
  reference = app_manifest_path(manifest, "reference_gauge"),
  retrospective = app_manifest_path(manifest, "glofas_retrospective"),
  ensemble = app_manifest_path(manifest, "glofas_ensemble")
)
provenance <- data.frame(
  source_role = names(source_paths),
  source_path = vapply(normalizePath(source_paths, mustWork = TRUE), app_prefer_repo_relative_path, character(1L)),
  sha256 = vapply(source_paths, app_sha256_file, character(1L)),
  run_id = basename(run_dirs$run_dir),
  article_git_sha = app_git_sha(short = FALSE),
  created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  stringsAsFactors = FALSE
)
provenance_path <- file.path(run_dirs$manifest, "cutoff_context_source_provenance.csv")
app_write_csv(provenance, provenance_path)

output_manifest <- data.frame(
  output_role = c(names(figures), names(tables), "cutoff_context_source_provenance"),
  output_path = c(unname(figures), unname(tables), provenance_path),
  sha256 = vapply(c(unname(figures), unname(tables), provenance_path), app_sha256_file, character(1L)),
  run_id = basename(run_dirs$run_dir),
  created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  stringsAsFactors = FALSE
)
app_write_csv(output_manifest, file.path(run_dirs$manifest, "cutoff_context_output_manifest.csv"))
app_write_session_info(file.path(run_dirs$manifest, "session_info.txt"))
app_write_git_state(file.path(run_dirs$manifest, "git_state.txt"))
app_stage_done(
  "authoritative_context_figures",
  run_dirs,
  message = sprintf("Validated %d historical observations, %d forecast dates, and %d ensemble members.", as.integer(args$history_observations), length(unique(context$ensemble$target_date)), length(unique(context$ensemble$member)))
)

cat(normalizePath(generated_dir, mustWork = TRUE), "\n")
