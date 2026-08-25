#!/usr/bin/env Rscript
# Purpose: materialize an audited jerez cutoff bundle into the article input
# schema used by the source-diagnostic figure workflow.
# Inputs: copied jerez cutoff directory with USGS, GloFAS retrospective,
# GloFAS member forecast, and covariate files.
# Outputs: local untracked frozen-input bundle plus provenance metadata.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/authoritative_source_audit.R"))
source(app_path("application/R/authoritative_cutoff_materialization.R"))

args <- app_parse_args(list(
  source_root = "application/data_local/upstream_jerez/frozen_shared_inputs/exalm_t1_authoritative_20260505/cutoff_date=2022-12-25",
  glofas_source_root = "application/data_local/upstream_jerez/histfix_stable_inputs/site=11160500/cutoff_date=2022-12-25/run_id=20260407_long_history_r01",
  cutoff_date = "2022-12-25",
  bundle_root = "application/data_local/frozen_inputs/authoritative_cutoffs/cutoff_date=2022-12-25",
  station_id = "11160500",
  requirements = "application/config/authoritative_source_requirements.yaml",
  overwrite = "true"
))

result <- app_materialize_authoritative_cutoff_bundle(
  source_root = args$source_root,
  cutoff_date = args$cutoff_date,
  bundle_root = args$bundle_root,
  station_id = args$station_id,
  requirements_path = args$requirements,
  glofas_source_root = args$glofas_source_root,
  overwrite = app_as_bool(args$overwrite)
)
cat(result$bundle_root, "\n")
