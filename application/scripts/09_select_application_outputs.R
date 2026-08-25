#!/usr/bin/env Rscript
# Purpose: select one promoted GloFAS application run as the manuscript-facing
# current application output set.
# Inputs: a promotion manifest written by 08_promote_application_outputs.R.
# Outputs: stable current-output TeX aliases, a compact manuscript table, and a
# selection manifest with hashes.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/application_output_registry.R"))

args <- app_parse_args(list(
  promotion_manifest = "tables/glofas_application_promotion_manifest__latent_path_d1n300_m100a092r097_tau3em3_main1000_20260523_160355.csv",
  registry_tex = "tables/glofas_application_current_outputs.tex",
  score_tex = "tables/glofas_application_current_score_summary.tex",
  score_csv = "tables/glofas_application_current_score_summary.csv",
  selection_manifest = "tables/glofas_application_current_selection_manifest.csv"
))

app_write_current_application_selection(
  promotion_manifest = args$promotion_manifest,
  registry_tex = args$registry_tex,
  score_tex = args$score_tex,
  score_csv = args$score_csv,
  selection_manifest = args$selection_manifest
)
