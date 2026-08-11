#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- if (!is.na(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_fixtures.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_calibration_screening.R"))
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_exqdesn_phase148_target_invariance.R"))
source(app_path("application/R/joint_exqdesn_phase149_case_specific_screening.R"))
source(app_path("application/R/joint_exqdesn_phase150_case_specific_mcmc_confirmation.R"))

args <- app_parse_args(list(
  mcmc_dir = "application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727",
  freeze_dir = "application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_freeze_20260727",
  output_dir = "",
  article_scenario_table = "tables/joint_qdesn_article_validation_mcmc_balanced_scenario_summary.csv"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

resolve_path <- function(path, default = "", must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(trimws(path))) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

mcmc_dir <- resolve_path(arg_value("mcmc_dir"), must_work = TRUE)
freeze_dir <- resolve_path(arg_value("freeze_dir"), must_work = TRUE)
output_dir <- resolve_path(
  arg_value("output_dir"),
  default = file.path(mcmc_dir, "phase150_result_audit"),
  must_work = FALSE
)

result <- app_joint_exqdesn_phase150_audit_mcmc_output(
  mcmc_dir = mcmc_dir,
  freeze_dir = freeze_dir,
  out_dir = output_dir,
  article_scenario_table = resolve_path(arg_value("article_scenario_table"), must_work = FALSE)
)

cat(sprintf("Phase150 MCMC result audit written to %s\n", result$out_dir))
cat(sprintf("Gate status: %s\n", result$assessment$gate_status[[1L]]))
cat(sprintf("Cases: %s\n", result$assessment$n_cases[[1L]]))
cat(sprintf("Raw crossings: %s\n", result$assessment$raw_crossing_pairs[[1L]]))
if ("delta_vs_article_joint_al_forecast_mae" %in% names(result$comparison)) {
  cat(sprintf("Scenarios beating article Joint AL forecast MAE: %s\n", result$assessment$scenarios_beating_article_joint_al[[1L]]))
}
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
